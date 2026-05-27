// chat-server/src/middleware/rateLimiter.js — 速率限制
const rateLimit = require('express-rate-limit');

const loginLimiter = rateLimit({
  windowMs: 60 * 1000, // 1 分钟
  max: 5,
  message: { code: 20010, message: '登录尝试过多，请稍后再试' },
  standardHeaders: true,
  legacyHeaders: false,
});

const messageLimiter = rateLimit({
  windowMs: 60 * 1000,
  max: 30,
  message: { code: 22001, message: '发送消息过于频繁' },
  standardHeaders: true,
  legacyHeaders: false,
  keyGenerator: (req) => req.user?.userId || req.ip,
});

module.exports = { loginLimiter, messageLimiter };
