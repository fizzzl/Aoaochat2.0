// chat-server/src/middleware/auth.js — JWT 验证中间件 + tokenVersion 校验
const jwt = require('jsonwebtoken');
const { JWT_SECRET } = require('../auth');
const db = require('../db');

async function authMiddleware(req, res, next) {
  const header = req.headers.authorization;
  if (!header || !header.startsWith('Bearer ')) {
    return res.status(401).json({ code: 20001, message: '未登录' });
  }
  try {
    const decoded = jwt.verify(header.slice(7), JWT_SECRET());
    // 验证 tokenVersion 匹配（支持密码修改后全量注销）
    const user = await db.getOne('SELECT token_version, deactivated_at FROM users WHERE id = $1', [decoded.userId]);
    if (!user || user.deactivated_at) {
      return res.status(401).json({ code: 20002, message: '账号已被禁用' });
    }
    if (user.token_version !== (decoded.tokenVersion || 0)) {
      return res.status(401).json({ code: 20001, message: '令牌已失效，请重新登录' });
    }
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
