// chat-server/src/auth.js — JWT 生成/验证 + 注册/登录 + refresh 轮换
const jwt = require('jsonwebtoken');
const bcrypt = require('bcrypt');
const crypto = require('crypto');
const db = require('./db');
const logger = require('./logger');

const JWT_SECRET = () => process.env.JWT_SECRET || 'dev-secret';
const JWT_REFRESH_SECRET = () => process.env.JWT_REFRESH_SECRET || 'dev-refresh-secret';
const ACCESS_TTL = '15m';
const REFRESH_TTL_MS = 7 * 24 * 3600 * 1000; // 7 days

// ── Token 生成 ──
function generateAccessToken(user) {
  return jwt.sign(
    { userId: user.id, username: user.username, tokenVersion: user.token_version },
    JWT_SECRET(),
    { expiresIn: ACCESS_TTL }
  );
}

function generateRefreshToken() {
  return crypto.randomBytes(48).toString('hex');
}

function hashToken(token) {
  return crypto.createHash('sha256').update(token).digest('hex');
}

// ── 注册 ──
async function register({ username, password, displayName, phone }) {
  // E.164 格式校验
  if (phone && !/^\+[1-9]\d{6,14}$/.test(phone)) {
    throw { code: 20005, message: '手机号格式不正确（需 E.164 格式）' };
  }
  if (password.length < 6) {
    throw { code: 20006, message: '密码至少 6 位' };
  }
  if (!username || username.length < 2) {
    throw { code: 20007, message: '用户名至少 2 位' };
  }

  const existing = await db.getOne('SELECT id FROM users WHERE username = $1', [username]);
  if (existing) {
    throw { code: 20003, message: '用户名已存在' };
  }

  const passwordHash = await bcrypt.hash(password, 10);
  const user = await db.getOne(
    `INSERT INTO users (username, password_hash, display_name, phone)
     VALUES ($1, $2, $3, $4) RETURNING id, username, display_name, token_version`,
    [username, passwordHash, displayName || username, phone || null]
  );

  return loginForUser(user);
}

// ── 登录 ──
async function login({ username, password }) {
  const user = await db.getOne(
    'SELECT id, username, password_hash, display_name, token_version, deactivated_at, is_admin FROM users WHERE username = $1',
    [username]
  );
  if (!user) {
    throw { code: 20001, message: '用户名或密码错误' };
  }
  if (user.deactivated_at) {
    throw { code: 20002, message: '账号已被禁用' };
  }

  const valid = await bcrypt.compare(password, user.password_hash);
  if (!valid) {
    throw { code: 20001, message: '用户名或密码错误' };
  }

  return loginForUser(user);
}

// ── 生成 token 对 ──
async function loginForUser(user) {
  const accessToken = generateAccessToken(user);
  const refreshToken = generateRefreshToken();
  const tokenHash = hashToken(refreshToken);

  await db.run(
    `INSERT INTO refresh_tokens (user_id, token_hash, expires_at)
     VALUES ($1, $2, NOW() + INTERVAL '7 days')`,
    [user.id, tokenHash]
  );

  logger.info('用户登录', { userId: user.id, username: user.username });

  return {
    accessToken,
    refreshToken,
    user: {
      id: user.id,
      username: user.username,
      displayName: user.display_name,
      isAdmin: user.is_admin || false,
    },
  };
}

// ── Refresh Token 轮换 ──
async function refreshAccessToken(refreshTokenStr) {
  const tokenHash = hashToken(refreshTokenStr);
  const record = await db.getOne(
    `SELECT id, user_id, revoked, expires_at, parent_token_id FROM refresh_tokens WHERE token_hash = $1`,
    [tokenHash]
  );

  if (!record) {
    throw { code: 20004, message: 'Token 无效' };
  }

  // 重放检测：已吊销的 token 被使用 → 吊销整条链
  if (record.revoked) {
    await revokeTokenChain(record);
    logger.warn('Token 重放检测', { userId: record.user_id, tokenId: record.id });
    throw { code: 20004, message: 'Token 已失效（重放检测）' };
  }

  // 过期检查
  if (new Date(record.expires_at) < new Date()) {
    await db.run('UPDATE refresh_tokens SET revoked = TRUE WHERE id = $1', [record.id]);
    throw { code: 20004, message: 'Token 已过期' };
  }

  // 获取用户信息
  const user = await db.getOne(
    'SELECT id, username, display_name, token_version, deactivated_at, is_admin FROM users WHERE id = $1',
    [record.user_id]
  );
  if (!user || user.deactivated_at) {
    throw { code: 20002, message: '账号已被禁用' };
  }

  // 吊销旧 token，生成新 token
  await db.run('UPDATE refresh_tokens SET revoked = TRUE WHERE id = $1', [record.id]);

  const newRefreshToken = generateRefreshToken();
  const newHash = hashToken(newRefreshToken);

  await db.run(
    `INSERT INTO refresh_tokens (user_id, token_hash, parent_token_id, expires_at)
     VALUES ($1, $2, $3, NOW() + INTERVAL '7 days')`,
    [user.id, newHash, record.id]
  );

  const accessToken = generateAccessToken(user);
  return { accessToken, refreshToken: newRefreshToken };
}

// ── 吊销 token 链 ──
async function revokeTokenChain(record) {
  // 吊销所有子孙 token
  await db.run(
    `WITH RECURSIVE chain AS (
      SELECT id FROM refresh_tokens WHERE id = $1
      UNION ALL
      SELECT rt.id FROM refresh_tokens rt JOIN chain c ON rt.parent_token_id = c.id
    )
    UPDATE refresh_tokens SET revoked = TRUE WHERE id IN (SELECT id FROM chain)`,
    [record.id]
  );
}

// ── 登出 ──
async function logout(refreshTokenStr) {
  const tokenHash = hashToken(refreshTokenStr);
  await db.run('UPDATE refresh_tokens SET revoked = TRUE WHERE token_hash = $1', [tokenHash]);
  logger.info('用户登出', { tokenHash: tokenHash.substring(0, 8) });
}

module.exports = {
  register, login, refreshAccessToken, logout, generateAccessToken,
  hashToken, JWT_SECRET,
};
