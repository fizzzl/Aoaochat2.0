// chat-server/tests/auth.test.js
require('dotenv').config();
const auth = require('../src/auth');
const factory = require('./helpers/factory');

beforeAll(async () => {
  await factory.cleanup();
});

afterAll(async () => {
  await factory.cleanup();
  const db = require('../src/db');
  await db.close();
});

describe('auth.register', () => {
  test('registers a new user and returns token pair', async () => {
    const result = await auth.register({
      username: 'user_a', password: 'pass123', displayName: 'A',
    });
    expect(result.accessToken).toBeTruthy();
    expect(result.refreshToken).toBeTruthy();
    expect(result.user.username).toBe('user_a');
    expect(result.user.displayName).toBe('A');
  });

  test('rejects duplicate username', async () => {
    await expect(auth.register({
      username: 'user_a', password: 'pass123', displayName: 'A2',
    })).rejects.toMatchObject({ code: 20003 });
  });

  test('rejects short password', async () => {
    await expect(auth.register({
      username: 'newuser', password: '12', displayName: 'X',
    })).rejects.toMatchObject({ code: 20006 });
  });

  test('rejects invalid phone format', async () => {
    await expect(auth.register({
      username: 'phoneuser', password: 'pass123', displayName: 'P', phone: '12345',
    })).rejects.toMatchObject({ code: 20005 });
  });
});

describe('auth.login', () => {
  test('logs in with correct credentials', async () => {
    const result = await auth.login({ username: 'user_a', password: 'pass123' });
    expect(result.accessToken).toBeTruthy();
    expect(result.user.id).toBeTruthy();
  });

  test('rejects wrong password', async () => {
    await expect(auth.login({
      username: 'user_a', password: 'wrong',
    })).rejects.toMatchObject({ code: 20001 });
  });

  test('rejects nonexistent user', async () => {
    await expect(auth.login({
      username: 'nobody', password: 'pass123',
    })).rejects.toMatchObject({ code: 20001 });
  });
});

describe('auth.refreshAccessToken', () => {
  let refreshToken;

  beforeAll(async () => {
    const result = await auth.login({ username: 'user_a', password: 'pass123' });
    refreshToken = result.refreshToken;
  });

  test('rotates refresh token', async () => {
    const result = await auth.refreshAccessToken(refreshToken);
    expect(result.accessToken).toBeTruthy();
    expect(result.refreshToken).toBeTruthy();
    expect(result.refreshToken).not.toBe(refreshToken);
  });

  test('detects replay attack', async () => {
    // Reuse the OLD token (which was revoked during rotation)
    await expect(auth.refreshAccessToken(refreshToken))
      .rejects.toMatchObject({ code: 20004 });
  });
});
