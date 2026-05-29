// chat-server/src/socket.js — Socket.IO 全部事件处理
const db = require('./db');
const logger = require('./logger');
const { sendPush } = require('./push');

const onlineUsers = new Map();   // userId -> { status, displayName }
const userSockets = new Map();   // userId -> Set<socketId>
const activeCalls = new Map();   // userId -> roomId
const rateLimit = new Map();     // event:userId -> count

function setupSocket(io) {
  io.on('connection', async (socket) => {
    const { userId, username } = socket;
    logger.info('Socket 连接', { userId, username });
    console.log(`[D] Socket connect: userId=${userId} username=${username}`);

    // 加入房间
    socket.join(`user:${userId}`);

    // 查询显示名
    const user = await db.getOne(
      'SELECT display_name FROM users WHERE id = $1',
      [userId]
    );
    const displayName = user?.display_name || username;

    // 更新在线状态
    onlineUsers.set(userId, { status: 'online', displayName, username });
    if (!userSockets.has(userId)) userSockets.set(userId, new Set());
    userSockets.get(userId).add(socket.id);

    // 更新数据库
    await db.run('UPDATE users SET last_seen_at = NOW() WHERE id = $1', [userId]);

    broadcastOnlineUsers(io);

    function checkRate(event) {
      const key = `${event}:${userId}`;
      const now = Date.now();
      const entry = rateLimit.get(key);
      if (entry && now - entry.time < 1000) {
        if (entry.count >= 10) {
          socket.emit('error', { code: 22010, message: '操作太频繁' });
          return false;
        }
        entry.count++;
      } else {
        rateLimit.set(key, { time: now, count: 1 });
      }
      return true;
    }

    // ═══════════ 消息 ═══════════
    socket.on('message:send', async (data) => {
      try {
        const { conversationId, content, type = 'text', tempId } = data;
        if (!conversationId || !content?.trim()) {
          return socket.emit('error', { code: 22002, message: '参数不完整' });
        }
        // 拒绝前端传的 senderId 与连接用户不匹配
        if (data.senderId && data.senderId !== userId) {
          logger.warn('串号拦截', { fromSocket: userId, claimedSender: data.senderId });
          return socket.emit('error', { code: 22011, message: '用户身份异常' });
        }
        if (content.length > 5000) {
          return socket.emit('error', { code: 22003, message: '消息过长（上限 5000 字符）' });
        }

        // 检查是否为会话成员
        const member = await db.getOne(
          'SELECT 1 FROM conversation_members WHERE conversation_id = $1 AND user_id = $2',
          [conversationId, userId]
        );
        if (!member) {
          return socket.emit('error', { code: 22004, message: '不是会话成员' });
        }

        // 检查好友关系（私聊）
        const conv = await db.getOne('SELECT type FROM conversations WHERE id = $1', [conversationId]);
        if (conv?.type === 'private') {
          const other = await db.getOne(
            `SELECT user_id FROM conversation_members
             WHERE conversation_id = $1 AND user_id != $2`,
            [conversationId, userId]
          );
          if (other) {
            const smaller = Math.min(userId, other.user_id);
            const larger = Math.max(userId, other.user_id);
            const friendship = await db.getOne(
              'SELECT status FROM friendships WHERE user_id = $1 AND friend_id = $2',
              [smaller, larger]
            );
            if (!friendship || friendship.status !== 'accepted') {
              return socket.emit('error', { code: 21001, message: '不是好友关系' });
            }
          }
        }

        const result = await db.run(
          `INSERT INTO messages (conversation_id, sender_id, type, content) VALUES ($1, $2, $3, $4) RETURNING id`,
          [conversationId, userId, type, content.trim()]
        );

        const message = {
          id: result.rows[0].id,
          conversationId,
          senderId: userId,
          senderUsername: username,
          senderDisplayName: displayName,
          type,
          content: content.trim(),
          readAt: null,
          deletedAt: null,
          createdAt: new Date().toISOString(),
          tempId,
        };

        // 推送消息
        socket.to(`conv:${conversationId}`).emit('message:new', message);
        socket.emit('message:sent', message);

        // 更新未读计数（排除发送者）
        await db.run(
          `UPDATE conversation_members SET unread_count = unread_count + 1
           WHERE conversation_id = $1 AND user_id != $2`,
          [conversationId, userId]
        );

        logger.info('消息发送', { msgId: message.id, conversationId });
        // 离线推送
        const convMembers = await db.getAll(
          'SELECT user_id FROM conversation_members WHERE conversation_id = $1 AND user_id != $2',
          [conversationId, userId]
        );
        for (const m of convMembers) {
          if (!userSockets.has(m.user_id) || userSockets.get(m.user_id).size === 0) {
            sendPush(m.user_id, displayName, content.trim().substring(0, 100), { conversationId: String(conversationId) });
          }
        }
      } catch (err) {
        logger.error('消息发送失败', { error: err.message });
        socket.emit('error', { code: 50000, message: '发送失败' });
      }
    });

    socket.on('message:read', async (data) => {
      try {
        const { conversationId } = data;
        await db.run(
          `UPDATE conversation_members SET unread_count = 0
           WHERE conversation_id = $1 AND user_id = $2`,
          [conversationId, userId]
        );
        // 标记消息已读时间
        await db.run(
          `UPDATE messages SET read_at = NOW()
           WHERE conversation_id = $1 AND sender_id != $2 AND read_at IS NULL`,
          [conversationId, userId]
        );
        socket.to(`conv:${conversationId}`).emit('message:read_ack', { conversationId, userId });
      } catch (err) {
        logger.error('已读标记失败', { error: err.message });
      }
    });

    socket.on('message:recall', async (data) => {
      try {
        const { messageId } = data;
        const msg = await db.getOne(
          'SELECT id, sender_id, conversation_id, created_at FROM messages WHERE id = $1 AND deleted_at IS NULL',
          [messageId]
        );
        if (!msg) return socket.emit('error', { code: 22005, message: '消息不存在' });
        if (msg.sender_id !== userId) {
          return socket.emit('error', { code: 22006, message: '只能撤回自己的消息' });
        }
        const diff = Date.now() - new Date(msg.created_at).getTime();
        if (diff > 2 * 60 * 1000) {
          return socket.emit('error', { code: 22007, message: '超过 2 分钟撤回时限' });
        }

        await db.run(
          'UPDATE messages SET deleted_at = NOW() WHERE id = $1',
          [messageId]
        );
        const recalled = { messageId, conversationId: msg.conversation_id };
        socket.emit('message:recalled', recalled);
        socket.to(`conv:${msg.conversation_id}`).emit('message:recalled', recalled);
        logger.info('消息撤回', { messageId });
      } catch (err) {
        logger.error('撤回失败', { error: err.message });
      }
    });

    socket.on('conversation:list', async () => {
      try {
        console.log(`[D] conversation:list for userId=${userId}`);
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
          [userId]
        );
        socket.emit('conversation:list', { conversations: convs });
      } catch (err) {
        logger.error('会话列表失败', { error: err.message });
      }
    });

    socket.on('conversation:history', async (data) => {
      try {
        const { conversationId, cursor, limit = 20 } = data;
        let query, params;
        if (cursor) {
          query = `SELECT id, conversation_id AS "conversationId", sender_id AS "senderId",
                    type, content, read_at AS "readAt", deleted_at AS "deletedAt",
                    created_at AS "createdAt"
                   FROM messages
                   WHERE conversation_id = $1 AND id < $2 AND deleted_at IS NULL
                   ORDER BY id DESC LIMIT $3`;
          params = [conversationId, cursor, limit];
        } else {
          query = `SELECT id, conversation_id AS "conversationId", sender_id AS "senderId",
                    type, content, read_at AS "readAt", deleted_at AS "deletedAt",
                    created_at AS "createdAt"
                   FROM messages
                   WHERE conversation_id = $1 AND deleted_at IS NULL
                   ORDER BY id DESC LIMIT $2`;
          params = [conversationId, limit];
        }
        const messages = await db.getAll(query, params);
        socket.emit('conversation:history', {
          conversationId,
          messages: messages.reverse(),
          hasMore: messages.length === limit,
        });
      } catch (err) {
        logger.error('历史消息失败', { error: err.message });
      }
    });

    socket.on('conversation:typing', (data) => {
      socket.to(`conv:${data.conversationId}`).emit('typing:update', {
        conversationId: data.conversationId,
        userId,
        displayName,
      });
    });

    // ═══════════ 好友 ═══════════
    socket.on('friend:add', async (data) => {
      try {
        if (!checkRate('friend:add')) return;
        const { friendId } = data;
        if (friendId === userId) {
          return socket.emit('error', { code: 21002, message: '不能添加自己' });
        }
        const smaller = Math.min(userId, friendId);
        const larger = Math.max(userId, friendId);
        const existing = await db.getOne(
          'SELECT id, status FROM friendships WHERE user_id = $1 AND friend_id = $2',
          [smaller, larger]
        );
        if (existing) {
          return socket.emit('error', { code: 21003, message: '已发送过请求' });
        }

        await db.run(
          `INSERT INTO friendships (user_id, friend_id, action_user_id, status)
           VALUES ($1, $2, $3, 'pending')`,
          [smaller, larger, userId]
        );
        socket.emit('friend:request_sent', { friendId });
        io.to(`user:${friendId}`).emit('friend:request', {
          userId, username, displayName, status: 'pending',
        });
        sendPush(friendId, '新的好友请求', `${displayName} 请求添加你为好友`, { type: 'friend_request' });
      } catch (err) {
        logger.error('添加好友失败', { error: err.message });
      }
    });

    socket.on('friend:accept', async (data) => {
      try {
        const { friendId } = data;
        const smaller = Math.min(userId, friendId);
        const larger = Math.max(userId, friendId);

        const convId = await db.transaction(async (client) => {
          await client.query(
            `UPDATE friendships SET status = 'accepted', updated_at = NOW()
             WHERE user_id = $1 AND friend_id = $2`,
            [smaller, larger]
          );

          const existing = await client.query(
            `SELECT c.id FROM conversations c
             JOIN conversation_members cm1 ON c.id = cm1.conversation_id AND cm1.user_id = $1
             JOIN conversation_members cm2 ON c.id = cm2.conversation_id AND cm2.user_id = $2
             WHERE c.type = 'private'`,
            [userId, friendId]
          );

          if (existing.rows.length > 0) return existing.rows[0].id;

          const conv = await client.query(
            `INSERT INTO conversations (type) VALUES ('private') RETURNING id`, []
          );
          const cid = conv.rows[0].id;
          await client.query(
            `INSERT INTO conversation_members (conversation_id, user_id) VALUES ($1, $2), ($1, $3)`,
            [cid, userId, friendId]
          );
          return cid;
        });

        socket.emit('friend:accepted', { friendId, conversationId: convId });
        io.to(`user:${friendId}`).emit('friend:accepted', { friendId: userId, conversationId: convId });
        logger.info('好友通过', { userId, friendId, convId });
      } catch (err) {
        logger.error('接受好友失败', { error: err.message });
      }
    });

    socket.on('friend:remove', async (data) => {
      try {
        const { friendId } = data;
        const smaller = Math.min(userId, friendId);
        const larger = Math.max(userId, friendId);
        await db.run(
          `DELETE FROM friendships WHERE user_id = $1 AND friend_id = $2`,
          [smaller, larger]
        );
        socket.emit('friend:removed', { friendId });
        io.to(`user:${friendId}`).emit('friend:removed', { friendId: userId });
      } catch (err) {
        logger.error('删除好友失败', { error: err.message });
      }
    });

    // ═══════════ 通话 ═══════════
    socket.on('call:start', async (data) => {
      try {
        if (!checkRate('call:start')) return;
        const { calleeId, type = 'voice' } = data;
        // 忙线检测
        if (activeCalls.has(calleeId)) {
          return socket.emit('call:rejected', { reason: 'busy' });
        }
        const roomId = require('uuid').v4();
        activeCalls.set(userId, roomId);

        // 创建通话记录
        await db.run(
          `INSERT INTO calls (caller_id, callee_id, type, room_id, status)
           VALUES ($1, $2, $3, $4, 'missed')`,
          [userId, calleeId, type, roomId]
        );

        io.to(`user:${calleeId}`).emit('call:incoming', {
          callerId: userId,
          callerName: displayName,
          type,
          roomId,
        });
        sendPush(calleeId, `${displayName} 的${type === 'video' ? '视频' : '语音'}通话`, '来电', { type: 'call', roomId });
        logger.info('通话发起', { roomId, callerId: userId, calleeId });
      } catch (err) {
        logger.error('发起通话失败', { error: err.message });
      }
    });

    socket.on('call:accept', async (data) => {
      const { roomId } = data;
      const call = await db.getOne(
        'SELECT caller_id, callee_id FROM calls WHERE room_id = $1', [roomId]
      );
      if (!call) return;
      if (call.callee_id !== userId) {
        return socket.emit('call:rejected', { reason: 'not_for_you' });
      }
      activeCalls.set(userId, roomId);
      await db.run(
        `UPDATE calls SET status = 'answered', started_at = NOW()
         WHERE room_id = $1 AND status = 'missed'`,
        [roomId]
      );
      const otherId = call?.caller_id === userId ? call?.callee_id : call?.caller_id;
      if (otherId) io.to(`user:${otherId}`).emit('call:accepted', { roomId });
    });

    socket.on('call:reject', async (data) => {
      const { roomId } = data;
      await db.run(
        `UPDATE calls SET status = 'rejected' WHERE room_id = $1`, [roomId]
      );
      const call = await db.getOne(
        'SELECT caller_id, callee_id FROM calls WHERE room_id = $1', [roomId]
      );
      const otherId = call?.caller_id === userId ? call?.callee_id : call?.caller_id;
      if (otherId) io.to(`user:${otherId}`).emit('call:rejected', { roomId, reason: 'declined' });
      activeCalls.delete(userId);
    });

    socket.on('call:end', async () => {
      const roomId = activeCalls.get(userId);
      if (!roomId) return;
      await db.run(
        `UPDATE calls SET status = CASE WHEN status = 'missed' THEN 'cancelled' ELSE status END, ended_at = NOW()
         WHERE room_id = $1`, [roomId]
      );
      const call = await db.getOne(
        'SELECT caller_id, callee_id FROM calls WHERE room_id = $1', [roomId]
      );
      const otherId = call?.caller_id === userId ? call?.callee_id : call?.caller_id;
      if (otherId) {
        io.to(`user:${otherId}`).emit('call:ended', { roomId });
        if (activeCalls.get(otherId) === roomId) activeCalls.delete(otherId);
      }
      activeCalls.delete(userId);
    });

    socket.on('call:cancel', async () => {
      if (activeCalls.has(userId)) {
        const roomId = activeCalls.get(userId);
        await db.run(
          `UPDATE calls SET status = 'cancelled' WHERE room_id = $1`, [roomId]
        );
        activeCalls.delete(userId);
      }
    });

    socket.on('call:signal', (data) => {
      const { toUserId, signal } = data;
      io.to(`user:${toUserId}`).emit('call:signal', {
        fromUserId: userId,
        signal,
      });
    });

    // ═══════════ 心跳 ═══════════
    socket.on('ping', () => {
      if (onlineUsers.has(userId)) {
        onlineUsers.get(userId).status = 'online';
      }
    });

    // ═══════════ 断开 ═══════════
    socket.on('disconnect', () => {
      logger.info('Socket 断开', { userId, username });
      const sockets = userSockets.get(userId);
      if (sockets) {
        sockets.delete(socket.id);
        if (sockets.size === 0) {
          userSockets.delete(userId);
          onlineUsers.set(userId, { ...onlineUsers.get(userId), status: 'offline' });
          // 延迟广播离线（可能是短暂断线重连）
          setTimeout(() => {
            if (!userSockets.has(userId)) {
              onlineUsers.delete(userId);
              broadcastOnlineUsers(io);
            }
          }, 60_000);
        }
      }
      if (activeCalls.has(userId)) {
        const roomId = activeCalls.get(userId);
        activeCalls.delete(userId);
      }
    });
  });
}

function broadcastOnlineUsers(io) {
  const users = [];
  for (const [userId, info] of onlineUsers) {
    users.push({ userId, ...info });
  }
  io.emit('online:update', { users });
}

module.exports = { setupSocket };
