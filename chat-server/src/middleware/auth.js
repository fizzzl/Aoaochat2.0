// chat-server/src/middleware/auth.js — JWT 验证中间件
const jwt = require('jsonwebtoken');
const { JWT_SECRET } = require('../auth');

function authMiddleware(req, res, next) {
  const header = req.headers.authorization;
  if (!header || !header.startsWith('Bearer ')) {
    return res.status(401).json({ code: 20001, message: '未登录' });
  }
  try {
    const decoded = jwt.verify(header.slice(7), JWT_SECRET());
    req.user = decoded;
    next();
  } catch (err) {
    return res.status(401).json({ code: 20001, message: '令牌无效或已过期' });
  }
}

function adminMiddleware(req, res, next) {
  authMiddleware(req, res, () => {
    if (!req.user.isAdmin) {
      return res.status(403).json({ code: 20009, message: '无管理员权限' });
    }
    next();
  });
}

module.exports = { authMiddleware, adminMiddleware };
