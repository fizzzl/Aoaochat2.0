// chat-server/tests/helpers/factory.js
const bcrypt = require('bcrypt');
const crypto = require('crypto');
const db = require('../../src/db');

async function createUser(username, password = 'test123', displayName = username) {
  const hash = await bcrypt.hash(password, 10);
  const result = await db.getOne(
    `INSERT INTO users (username, password_hash, display_name) VALUES ($1, $2, $3)
     ON CONFLICT (username) DO UPDATE SET display_name = $3 RETURNING id, username, display_name, token_version`,
    [username, hash, displayName]
  );
  return result;
}

async function createFriendship(userId1, userId2, status = 'accepted') {
  const smaller = Math.min(userId1, userId2);
  const larger = Math.max(userId1, userId2);
  await db.run(
    `INSERT INTO friendships (user_id, friend_id, action_user_id, status)
     VALUES ($1, $2, $3, $4) ON CONFLICT DO NOTHING`,
    [smaller, larger, userId1, status]
  );
}

async function createConversation(userId1, userId2) {
  const conv = await db.getOne(
    `INSERT INTO conversations (type) VALUES ('private') RETURNING id`, []
  );
  await db.run(
    `INSERT INTO conversation_members (conversation_id, user_id) VALUES ($1, $2), ($1, $3)`,
    [conv.id, userId1, userId2]
  );
  return conv.id;
}

async function cleanup() {
  await db.run('DELETE FROM message_reads');
  await db.run('DELETE FROM attachments');
  await db.run('DELETE FROM messages');
  await db.run('DELETE FROM conversation_members');
  await db.run('DELETE FROM conversations');
  await db.run('DELETE FROM friendships');
  await db.run('DELETE FROM refresh_tokens');
  await db.run('DELETE FROM devices');
  await db.run('DELETE FROM calls');
  await db.run('DELETE FROM users');
}

module.exports = { createUser, createFriendship, createConversation, cleanup };
