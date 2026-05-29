// chat-server/src/index.js — Express + Socket.IO 入口
require('dotenv').config({ path: require('path').join(__dirname, '..', '.env') });
const express = require('express');
const http = require('http');
const path = require('path');
const { Server } = require('socket.io');
const cors = require('cors');

const { migrate } = require('./migrate');
const auth = require('./auth');
const { authMiddleware, adminMiddleware } = require('./middleware/auth');
const { socketAuth } = require('./middleware/socketAuth');
const { loginLimiter } = require('./middleware/rateLimiter');
const { setupSocket } = require('./socket');
const { upload, handleUpload, handleAvatarUpload } = require('./upload');
const multer = require('multer');
const { initFCM, sendPush } = require('./push');
const db = require('./db');
const logger = require('./logger');

const PORT = process.env.PORT || 3000;

async function main() {
  // 数据库迁移
  try { await migrate(); } catch (err) {
    logger.warn('数据库迁移跳过（可能已执行）', { error: err.message });
  }

  // 初始化 FCM
  initFCM();

  const app = express();
  const server = http.createServer(app);

  // 中间件
  app.use(cors());
  app.use(express.json());
  app.use('/uploads', express.static(path.join(__dirname, '..', 'uploads')));
  app.use(express.static(path.join(__dirname, '..', 'public')));

  // ═══════════ REST API ═══════════

  // 鉴权
  app.post('/api/auth/register', async (req, res) => {
    try {
      const result = await auth.register(req.body);
      res.json({ code: 0, data: result });
    } catch (err) {
      res.status(err.code >= 20000 ? 400 : 500).json(err);
    }
  });

  app.post('/api/auth/login', loginLimiter, async (req, res) => {
    try {
      const result = await auth.login(req.body);
      res.json({ code: 0, data: result });
    } catch (err) {
      res.status(err.code >= 20000 ? 400 : 500).json(err);
    }
  });

  app.post('/api/auth/refresh', async (req, res) => {
    try {
      const { refreshToken } = req.body;
      if (!refreshToken) return res.status(400).json({ code: 20004, message: '缺少 refresh token' });
      const result = await auth.refreshAccessToken(refreshToken);
      res.json({ code: 0, data: result });
    } catch (err) {
      res.status(err.code >= 20000 ? 400 : 500).json(err);
    }
  });

  app.post('/api/auth/logout', authMiddleware, async (req, res) => {
    try {
      await auth.logout(req.body.refreshToken);
      res.json({ code: 0, message: '已登出' });
    } catch (err) {
      res.json({ code: 0, message: '已登出' });
    }
  });

  // 用户
  app.get('/api/users/search', authMiddleware, async (req, res) => {
    try {
      const { q } = req.query;
      if (!q || q.length < 1) return res.json({ code: 0, data: [] });
      const users = await db.getAll(
        `SELECT id, username, display_name, avatar_url, avatar_thumb_url
         FROM users WHERE (username ILIKE $1 OR display_name ILIKE $1)
         AND id != $2 AND deactivated_at IS NULL LIMIT 20`,
        [`%${q}%`, req.user.userId]
      );
      res.json({ code: 0, data: users });
    } catch (err) {
      res.status(500).json({ code: 50000, message: err.message });
    }
  });

  app.get('/api/users/:id/profile', authMiddleware, async (req, res) => {
    const user = await db.getOne(
      'SELECT id, username, display_name, avatar_url, avatar_thumb_url, last_seen_at FROM users WHERE id = $1 AND deactivated_at IS NULL',
      [req.params.id]
    );
    if (!user) return res.status(404).json({ code: 20008, message: '用户不存在' });
    res.json({ code: 0, data: user });
  });

  app.put('/api/users/me/profile', authMiddleware, async (req, res) => {
    const { displayName } = req.body;
    if (!displayName) return res.status(400).json({ code: 22002, message: '显示名不能为空' });
    await db.run('UPDATE users SET display_name = $1, updated_at = NOW() WHERE id = $2',
      [displayName, req.user.userId]);
    res.json({ code: 0, message: '已更新' });
  });

  app.post('/api/users/me/avatar', authMiddleware, upload.single('avatar'), async (req, res) => {
    try {
      if (!req.file) return res.status(400).json({ code: 23001, message: '请选择文件' });
      const { avatarUrl, thumbUrl } = await handleAvatarUpload(req.file);
      await db.run(
        'UPDATE users SET avatar_url = $1, avatar_thumb_url = $2 WHERE id = $3',
        [avatarUrl, thumbUrl, req.user.userId]
      );
      res.json({ code: 0, data: { avatarUrl, thumbUrl } });
    } catch (err) {
      res.status(400).json({ code: 23002, message: err.message });
    }
  });

  // 好友
  app.get('/api/friends', authMiddleware, async (req, res) => {
    const friends = await db.getAll(
      `SELECT u.id, u.username, u.display_name, u.avatar_url, u.avatar_thumb_url, f.status
       FROM friendships f JOIN users u
       ON (CASE WHEN f.user_id = $1 THEN f.friend_id ELSE f.user_id END) = u.id
       WHERE (f.user_id = $1 OR f.friend_id = $1) AND f.status = 'accepted' AND u.deactivated_at IS NULL`,
      [req.user.userId]
    );
    res.json({ code: 0, data: friends });
  });

  app.get('/api/friends/requests', authMiddleware, async (req, res) => {
    const requests = await db.getAll(
      `SELECT u.id, u.username, u.display_name, u.avatar_url, f.status, f.action_user_id, f.created_at
       FROM friendships f JOIN users u ON f.action_user_id = u.id
       WHERE (f.user_id = $1 OR f.friend_id = $1) AND f.status = 'pending'`,
      [req.user.userId]
    );
    res.json({ code: 0, data: requests });
  });

  // 通话记录
  app.get('/api/calls', authMiddleware, async (req, res) => {
    const calls = await db.getAll(
      `SELECT c.id, c.caller_id AS "callerId", c.callee_id AS "calleeId",
              cu.display_name AS "callerName", cu2.display_name AS "calleeName",
              c.type, c.room_id AS "roomId", c.status,
              c.started_at AS "startedAt", c.ended_at AS "endedAt"
       FROM calls c
       JOIN users cu ON c.caller_id = cu.id
       JOIN users cu2 ON c.callee_id = cu2.id
       WHERE c.caller_id = $1 OR c.callee_id = $1
       ORDER BY COALESCE(c.started_at, c.ended_at) DESC LIMIT 50`,
      [req.user.userId]
    );
    res.json({ code: 0, data: calls });
  });

  // 删除会话
  app.delete('/api/conversations/:id', authMiddleware, async (req, res) => {
    await db.run(
      'DELETE FROM conversation_members WHERE conversation_id = $1 AND user_id = $2',
      [req.params.id, req.user.userId]
    );
    res.json({ code: 0, message: '已删除' });
  });

  // 会话
  app.get('/api/conversations/:id', authMiddleware, async (req, res) => {
    const conv = await db.getOne(
      `SELECT c.*, cm.unread_count FROM conversations c
       JOIN conversation_members cm ON c.id = cm.conversation_id AND cm.user_id = $2
       WHERE c.id = $1`,
      [req.params.id, req.user.userId]
    );
    if (!conv) return res.status(404).json({ code: 22008, message: '会话不存在' });
    res.json({ code: 0, data: conv });
  });

  // 消息
  app.delete('/api/messages/:id', authMiddleware, async (req, res) => {
    await db.run(
      'UPDATE messages SET deleted_at = NOW() WHERE id = $1 AND sender_id = $2 AND deleted_at IS NULL',
      [req.params.id, req.user.userId]
    );
    res.json({ code: 0, message: '已删除' });
  });

  // 文件上传
  app.post('/api/upload', authMiddleware, upload.single('file'), async (req, res) => {
    try {
      if (!req.file) return res.status(400).json({ code: 23001, message: '请选择文件' });
      const result = await handleUpload(req.file);
      res.json({ code: 0, data: result });
    } catch (err) {
      res.status(400).json({ code: 23002, message: err.message });
    }
  });

  // 设备
  app.post('/api/devices', authMiddleware, async (req, res) => {
    const { platform, pushToken } = req.body;
    if (!platform || !pushToken) return res.status(400).json({ code: 20005, message: '参数不完整' });
    await db.run(
      `INSERT INTO devices (user_id, platform, push_token)
       VALUES ($1, $2, $3)
       ON CONFLICT DO NOTHING`,
      [req.user.userId, platform, pushToken]
    );
    res.json({ code: 0, message: '已注册' });
  });

  app.delete('/api/devices/:id', authMiddleware, async (req, res) => {
    await db.run('DELETE FROM devices WHERE id = $1 AND user_id = $2', [req.params.id, req.user.userId]);
    res.json({ code: 0, message: '已注销' });
  });

  // ═══════════ Admin API ═══════════
  app.get('/api/admin/stats', adminMiddleware, async (req, res) => {
    const [users, dailyActive, todayMessages, todayCalls] = await Promise.all([
      db.getOne('SELECT COUNT(*) AS count FROM users WHERE deactivated_at IS NULL'),
      db.getOne('SELECT COUNT(*) AS count FROM users WHERE last_seen_at > NOW() - INTERVAL \'24 hours\''),
      db.getOne('SELECT COUNT(*) AS count FROM messages WHERE created_at > NOW() - INTERVAL \'24 hours\''),
      db.getOne('SELECT COUNT(*) AS count FROM calls WHERE started_at > NOW() - INTERVAL \'24 hours\''),
    ]);
    res.json({ code: 0, data: {
      totalUsers: parseInt(users.count),
      dailyActive: parseInt(dailyActive.count),
      todayMessages: parseInt(todayMessages.count),
      todayCalls: parseInt(todayCalls.count),
    }});
  });

  app.get('/api/admin/users', adminMiddleware, async (req, res) => {
    const { q, page = 1, limit = 20 } = req.query;
    const offset = (page - 1) * limit;
    let query, countQuery, params;
    if (q) {
      query = `SELECT id, username, display_name, phone, is_admin, created_at, deactivated_at
               FROM users WHERE (username ILIKE $1 OR display_name ILIKE $1)
               ORDER BY created_at DESC LIMIT $2 OFFSET $3`;
      params = [`%${q}%`, limit, offset];
      countQuery = `SELECT COUNT(*) FROM users WHERE username ILIKE $1 OR display_name ILIKE $1`;
    } else {
      query = `SELECT id, username, display_name, phone, is_admin, created_at, deactivated_at
               FROM users ORDER BY created_at DESC LIMIT $1 OFFSET $2`;
      params = [limit, offset];
      countQuery = `SELECT COUNT(*) FROM users`;
    }
    const [users, count] = await Promise.all([
      db.getAll(query, params),
      q ? db.getOne(countQuery, [`%${q}%`]) : db.getOne(countQuery),
    ]);
    res.json({ code: 0, data: { users, total: parseInt(count.count), page: parseInt(page) } });
  });

  app.put('/api/admin/users/:id', adminMiddleware, async (req, res) => {
    const { deactivated } = req.body;
    if (deactivated) {
      await db.run('UPDATE users SET deactivated_at = NOW() WHERE id = $1', [req.params.id]);
    } else {
      await db.run('UPDATE users SET deactivated_at = NULL WHERE id = $1', [req.params.id]);
    }
    res.json({ code: 0, message: '已更新' });
  });

  app.get('/api/admin/messages', adminMiddleware, async (req, res) => {
    const { q, page = 1, limit = 20 } = req.query;
    const offset = (page - 1) * limit;
    const data = await db.getAll(
      `SELECT c.id AS conv_id, c.type, COUNT(m.id) AS msg_count
       FROM conversations c JOIN messages m ON c.id = m.conversation_id
       ${q ? `WHERE m.content ILIKE $1` : ''}
       GROUP BY c.id ORDER BY msg_count DESC LIMIT $2 OFFSET $3`,
      q ? [`%${q}%`, limit, offset] : [limit, offset]
    );
    res.json({ code: 0, data });
  });

  app.get('/api/admin/logs', adminMiddleware, (req, res) => {
    // 系统日志返回最近 N 条（简化实现，生产环境应接入日志系统）
    res.json({ code: 0, data: { message: '日志系统就绪', timestamp: new Date().toISOString() } });
  });

  // 静态页面（管理后台）
  app.use('/admin', express.static(path.join(__dirname, '..', 'public', 'admin')));

  // 健康检查
  app.get('/api/health', (req, res) => {
    res.json({ status: 'ok', time: new Date().toISOString() });
  });

  // ═══════════ Token 诊断 ═══════════
  const jwt = require('jsonwebtoken');
  app.get('/api/whoami', (req, res) => {
    const header = req.headers.authorization;
    if (!header || !header.startsWith('Bearer ')) {
      return res.json({ code: 20001, auth: null });
    }
    try {
      const decoded = jwt.verify(header.slice(7), auth.JWT_SECRET());
      res.json({ code: 0, auth: decoded });
    } catch (e) {
      res.json({ code: 20001, auth: null, error: e.message });
    }
  });

  // 会话列表（REST API，不依赖 WebSocket）
  app.get('/api/conversations', authMiddleware, async (req, res) => {
    try {
      const convs = await db.getAll(
        `SELECT c.id, c.type, c.name, c.last_message, c.last_message_time,
                cm.unread_count,
                CASE WHEN c.type = 'private' THEN
                  (SELECT u.display_name FROM users u
                   JOIN conversation_members cm2 ON u.id = cm2.user_id
                   WHERE cm2.conversation_id = c.id AND cm2.user_id != $1 LIMIT 1)
                ELSE c.name END as display_name,
                CASE WHEN c.type = 'private' THEN
                  (SELECT u.id FROM users u
                   JOIN conversation_members cm2 ON u.id = cm2.user_id
                   WHERE cm2.conversation_id = c.id AND cm2.user_id != $1 LIMIT 1)
                END as other_user_id,
                CASE WHEN c.type = 'private' THEN
                  (SELECT u.avatar_thumb_url FROM users u
                   JOIN conversation_members cm2 ON u.id = cm2.user_id
                   WHERE cm2.conversation_id = c.id AND cm2.user_id != $1 LIMIT 1)
                END as avatar_url
         FROM conversations c
         JOIN conversation_members cm ON c.id = cm.conversation_id AND cm.user_id = $1
         ORDER BY c.last_message_time DESC NULLS LAST`,
        [req.user.userId]
      );
      res.json({ code: 0, data: convs });
    } catch (err) {
      res.status(500).json({ code: 50000, message: err.message });
    }
  });

  // ═══════════ Socket.IO ═══════════
  const io = new Server(server, {
    cors: { origin: '*', methods: ['GET', 'POST'] },
  });
  io.use(socketAuth);
  setupSocket(io);

  // ═══════════ 全局错误处理 ═══════════
  app.use((err, req, res, next) => {
    if (err instanceof multer.MulterError) {
      return res.status(400).json({ code: 23003, message: err.code === 'LIMIT_FILE_SIZE' ? '文件超过限制(10MB)' : '文件上传错误' });
    }
    if (err) {
      res.status(500).json({ code: 50000, message: err.message || '服务器内部错误' });
    }
  });

  // ═══════════ 启动 ═══════════
  server.listen(PORT, () => {
    console.log('====================================');
    console.log('  嗷嗷聊天二代 服务端已启动');
    console.log(`  HTTP:  http://localhost:${PORT}`);
    console.log(`  Admin: http://localhost:${PORT}/admin`);
    console.log('====================================');
  });
}

main().catch((err) => {
  console.error('[FATAL] 启动失败:', err);
  process.exit(1);
});
