// chat-server/src/middleware/socketAuth.js — Socket.IO 鉴权 + tokenVersion 校验
const jwt = require('jsonwebtoken');
const { JWT_SECRET } = require('../auth');
const db = require('../db');

async function socketAuth(socket, next) {
  const token = socket.handshake.auth?.token;
  if (!token) return next(new Error('未提供认证令牌'));
  try {
    const decoded = jwt.verify(token, JWT_SECRET());
    const user = await db.getOne(
      'SELECT token_version, deactivated_at FROM users WHERE id = $1',
      [decoded.userId]
    );
    if (!user || user.deactivated_at) return next(new Error('账号已被禁用'));
    if (user.token_version !== (decoded.tokenVersion || 0)) {
      return next(new Error('令牌已失效，请重新登录'));
    }
    socket.userId = decoded.userId;
    socket.username = decoded.username;
    next();
  } catch (err) {
    next(new Error('令牌无效或已过期'));
  }
}

module.exports = { socketAuth };
