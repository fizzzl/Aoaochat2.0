// chat-server/tests/friendships.test.js
require('dotenv').config();
const factory = require('./helpers/factory');
const db = require('../src/db');

let userA, userB;

beforeAll(async () => {
  await factory.cleanup();
  userA = await factory.createUser('friend_a');
  userB = await factory.createUser('friend_b');
});

afterAll(async () => {
  await factory.cleanup();
  await db.close();
});

describe('friendships', () => {
  test('creates a pending request (single row)', async () => {
    const smaller = Math.min(userA.id, userB.id);
    const larger = Math.max(userA.id, userB.id);
    await db.run(
      `INSERT INTO friendships (user_id, friend_id, action_user_id, status)
       VALUES ($1, $2, $3, 'pending')`,
      [smaller, larger, userA.id]
    );

    const row = await db.getOne(
      'SELECT * FROM friendships WHERE user_id = $1 AND friend_id = $2',
      [smaller, larger]
    );
    expect(row.status).toBe('pending');
    expect(row.action_user_id).toBe(userA.id);
  });

  test('prevents duplicate requests with UNIQUE index', async () => {
    const smaller = Math.min(userA.id, userB.id);
    const larger = Math.max(userA.id, userB.id);
    await expect(db.run(
      `INSERT INTO friendships (user_id, friend_id, action_user_id, status)
       VALUES ($1, $2, $3, 'pending')`,
      [smaller, larger, userB.id]
    )).rejects.toThrow();
  });

  test('updates status to accepted', async () => {
    const smaller = Math.min(userA.id, userB.id);
    const larger = Math.max(userA.id, userB.id);
    await db.run(
      `UPDATE friendships SET status = 'accepted', updated_at = NOW()
       WHERE user_id = $1 AND friend_id = $2`,
      [smaller, larger]
    );
    const row = await db.getOne(
      'SELECT status FROM friendships WHERE user_id = $1 AND friend_id = $2',
      [smaller, larger]
    );
    expect(row.status).toBe('accepted');
  });

  test('transaction: accept + create conversation atomically', async () => {
    const c1 = await factory.createUser('conv_user1');
    const c2 = await factory.createUser('conv_user2');
    const smaller = Math.min(c1.id, c2.id);
    const larger = Math.max(c1.id, c2.id);

    await db.run(
      `INSERT INTO friendships (user_id, friend_id, action_user_id, status)
       VALUES ($1, $2, $3, 'pending')`,
      [smaller, larger, c1.id]
    );

    const convId = await db.transaction(async (client) => {
      await client.query(
        `UPDATE friendships SET status = 'accepted' WHERE user_id = $1 AND friend_id = $2`,
        [smaller, larger]
      );
      const conv = await client.query(
        `INSERT INTO conversations (type) VALUES ('private') RETURNING id`, []
      );
      const cid = conv.rows[0].id;
      await client.query(
        `INSERT INTO conversation_members (conversation_id, user_id) VALUES ($1, $2), ($1, $3)`,
        [cid, c1.id, c2.id]
      );
      return cid;
    });

    expect(convId).toBeGreaterThan(0);

    const members = await db.getAll(
      'SELECT user_id FROM conversation_members WHERE conversation_id = $1',
      [convId]
    );
    expect(members.length).toBe(2);
  });
});
