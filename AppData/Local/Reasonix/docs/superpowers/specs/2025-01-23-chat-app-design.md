# 即时通讯 App 设计文档（v1.2）

> 全新聊天应用，替代嗷嗷聊天 (AoaoChat)，从零构建「嗷嗷聊天二代」。
> v1.2 — + 管理后台（用户管理 / 数据看板 / 消息监控 / 系统日志）

## 项目概述

- **应用名称**：嗷嗷聊天二代
- **平台**：移动端优先（Android + iOS），后续可扩展桌面/Web
- **定位**：即时通讯（微信/WhatsApp 风格），熟人社交
- **客户端**：Flutter（Dart）
- **服务端**：Node.js + Express + Socket.IO
- **数据库**：PostgreSQL
- **音视频通话**：WebRTC P2P + Google STUN

---

## MVP 功能范围

| 功能 | 说明 |
|------|------|
| 单聊消息 | 文字、图片、表情、消息已读、撤回（2 分钟内） |
| 音视频通话 | WebRTC P2P，语音 + 视频，忙线/拒接/超时处理 |
| 推送通知 | FCM (Android) + APNs (iOS)，通知点击 Deep Link |
| 好友管理 | 搜索、添加、接受、删除、拉黑 |
| 用户资料 | 显示名、头像编辑 |

**明确不纳入 MVP**：群聊、朋友圈/动态、文件传输（附件表已预留）、暗色主题

---

## 第一节：整体架构

### 架构风格

单体 Node.js 服务，包含 HTTP API + Socket.IO + WebRTC 信令，部署为单一进程。

```
Flutter App  ←→  REST API (HTTPS)  +  Socket.IO (WSS)  →  PostgreSQL
Flutter App  ←→  P2P WebRTC (经信令建立后直连)
```

### 服务端项目结构

```
chat-server/
├── src/index.js         入口 & Express 启动
├── src/socket.js        Socket.IO 事件处理 + 在线状态 + 心跳
├── src/signaling.js     WebRTC 信令转发 (SDP/ICE)
├── src/auth.js          JWT 鉴权 + 注册/登录 + refresh token 轮换
├── src/db.js            PostgreSQL 连接池 + 查询
├── src/push.js          FCM/APNs 推送
├── src/upload.js        文件/头像上传（IStorageProvider 接口）
├── src/cache.js         内存 Map (预留 Redis 接口)
├── public/admin/        管理后台（纯静态 HTML）
│   ├── index.html       数据看板
│   ├── users.html       用户管理
│   ├── messages.html    消息监控
│   ├── logs.html        系统日志
│   └── login.html       管理员登录
└── src/middleware/
    ├── auth.js          JWT 验证中间件
    ├── socketAuth.js    Socket.IO 鉴权中间件
    └── rateLimiter.js   速率限制中间件
```

### 客户端项目结构

```
chat_app/lib/
├── main.dart            App 入口 + 主题 + 路由 + 通知处理
├── models/              User, Message, Call, Conversation
├── services/            ApiService, SocketService, AuthService, CallService
├── screens/             详见第五节 UI 设计
├── widgets/             详见第五节 UI 设计
└── webrtc/              WebRTC 连接管理 + 信令客户端
```

### 基础设施策略

| 组件 | MVP 策略 |
|------|----------|
| PostgreSQL | ✅ 必须 |
| STUN | ✅ Google 免费: `stun:stun.l.google.com:19302` |
| Redis | 🔒 预留 — 内存 Map 先行，cache.js 预留接口 |
| TURN | 🔒 可选 — coturn 按需部署（对称 NAT 场景） |
| 对象存储 | 🔒 本地文件系统，upload.js 抽象 `IStorageProvider` 接口 |

### 安全配置

| 项 | 值 |
|----|-----|
| JWT access_token 有效期 | 15 分钟 |
| JWT refresh_token 有效期 | 7 天 |
| API 限流 — 登录 | 5 次/分钟/IP |
| API 限流 — 发消息 | 30 次/分钟/用户 |
| 手机号格式 | E.164: `+8613800000000` |
| 文本消息上限 | 5000 字符 |
| 文件上传上限 | 10MB |
| 图片自动压缩 | 最长边 1080px |

---

## 第二节：数据模型

### 表结构（10 张表）

#### users
| 字段 | 类型 | 约束 |
|------|------|------|
| id | SERIAL | PK |
| username | VARCHAR(50) | UNIQUE, NOT NULL |
| password_hash | VARCHAR(255) | NOT NULL |
| display_name | VARCHAR(100) | NOT NULL |
| avatar_url | TEXT | NULL |
| avatar_thumb_url | TEXT | NULL |
| phone | VARCHAR(20) | NULL |
| is_admin | BOOLEAN | DEFAULT FALSE |
| token_version | INT | DEFAULT 0 |
| last_seen_at | TIMESTAMP | NULL |
| deactivated_at | TIMESTAMP | NULL (NULL = 正常) |
| created_at | TIMESTAMP | DEFAULT NOW() |
| updated_at | TIMESTAMP | DEFAULT NOW() |

#### refresh_tokens
| 字段 | 类型 | 约束 |
|------|------|------|
| id | SERIAL | PK |
| user_id | INT | FK → users(id) |
| token_hash | VARCHAR(255) | UNIQUE, NOT NULL |
| parent_token_id | INT | NULL (首次登录为 NULL) |
| expires_at | TIMESTAMP | NOT NULL |
| revoked | BOOLEAN | DEFAULT FALSE |
| created_at | TIMESTAMP | DEFAULT NOW() |

> **Token 轮换逻辑**：POST /api/auth/refresh → 验证旧 token → 生成新 token（parent_token_id 指向旧 token）→ 吊销旧 token → 返回新 token 对。检测到重放（已吊销的 token 被使用）→ 吊销整个链。

#### conversations
| 字段 | 类型 | 约束 |
|------|------|------|
| id | SERIAL | PK |
| type | VARCHAR(10) | 'private' 或 'group' |
| name | VARCHAR(100) | 群聊时使用，private 为 NULL |
| last_message | TEXT | 最新消息预览缓存（触发器自动更新） |
| last_message_time | TIMESTAMP | 最新消息时间缓存（触发器自动更新） |
| created_at | TIMESTAMP | DEFAULT NOW() |

> last_message / last_message_time 通过 PostgreSQL TRIGGER 在 messages 表 INSERT/UPDATE/DELETE 时自动维护。

#### conversation_members
| 字段 | 类型 | 约束 |
|------|------|------|
| conversation_id | INT | FK → conversations(id) |
| user_id | INT | FK → users(id) |
| unread_count | INT | DEFAULT 0 |
| last_read_msg_id | INT | NULL |
| joined_at | TIMESTAMP | DEFAULT NOW() |

> 🔒 UNIQUE(conversation_id, user_id)
> 
> 未读计数：发送消息时 `unread_count + 1`（排除发送者），进入 ChatScreen 标记已读时归零。

#### messages
| 字段 | 类型 | 约束 |
|------|------|------|
| id | SERIAL | PK |
| conversation_id | INT | FK → conversations(id) |
| sender_id | INT | FK → users(id) |
| reply_to_msg_id | INT | NULL (引用回复，预留) |
| type | VARCHAR(10) | 'text', 'image', 'file', 'call' |
| content | TEXT | NOT NULL, 上限 5000 字符 |
| read_at | TIMESTAMP | NULL (NULL = 未读，单聊使用) |
| deleted_at | TIMESTAMP | NULL (NULL = 未撤回) |
| created_at | TIMESTAMP | DEFAULT NOW() |

> 撤回逻辑：设置 deleted_at，不清理 content；查询时 `WHERE deleted_at IS NULL`
> 
> 撤回时限：仅允许发送后 2 分钟内撤回
> 
> 消息分页：cursor 分页 (WHERE id < cursor ORDER BY id DESC LIMIT 20)，不用 OFFSET

#### message_reads（群聊已读，单聊可复用）
| 字段 | 类型 | 约束 |
|------|------|------|
| message_id | INT | FK → messages(id) |
| user_id | INT | FK → users(id) |
| read_at | TIMESTAMP | DEFAULT NOW() |

> 🔒 PRIMARY KEY (message_id, user_id)
> 
> 单聊可继续用 messages.read_at 简化；群聊必须用此表。

#### attachments
| 字段 | 类型 | 约束 |
|------|------|------|
| id | SERIAL | PK |
| message_id | INT | FK → messages(id) |
| url | TEXT | NOT NULL |
| thumb_url | TEXT | NULL（缩略图） |
| mime_type | VARCHAR(100) | |
| size | INT | 字节数 |
| width | INT | 图片宽 (NULL) |
| height | INT | 图片高 (NULL) |
| created_at | TIMESTAMP | DEFAULT NOW() |

#### friendships（单行存储）
| 字段 | 类型 | 约束 |
|------|------|------|
| id | SERIAL | PK |
| user_id | INT | FK → users(id)（较小的一方） |
| friend_id | INT | FK → users(id)（较大的一方） |
| action_user_id | INT | 发起操作的用户 |
| status | VARCHAR(10) | 'pending', 'accepted', 'rejected', 'blocked' |
| created_at | TIMESTAMP | DEFAULT NOW() |
| updated_at | TIMESTAMP | DEFAULT NOW() |

> 🔒 UNIQUE INDEX `(LEAST(user_id, friend_id), GREATEST(user_id, friend_id))`
> 
> 单行存储，user_id 始终小于 friend_id。查询用 `(user_id = ? OR friend_id = ?) AND status = 'accepted'`。

#### calls
| 字段 | 类型 | 约束 |
|------|------|------|
| id | SERIAL | PK |
| caller_id | INT | FK → users(id) |
| callee_id | INT | FK → users(id) |
| type | VARCHAR(10) | 'voice' 或 'video' |
| room_id | VARCHAR(36) | UUID，服务端生成（预留 SFU 扩展） |
| status | VARCHAR(10) | 'missed', 'answered', 'rejected', 'cancelled' |
| started_at | TIMESTAMP | NULL |
| ended_at | TIMESTAMP | NULL |

#### devices
| 字段 | 类型 | 约束 |
|------|------|------|
| id | SERIAL | PK |
| user_id | INT | FK → users(id) |
| platform | VARCHAR(10) | 'ios' 或 'android' |
| push_token | TEXT | NOT NULL |
| created_at | TIMESTAMP | DEFAULT NOW() |
| updated_at | TIMESTAMP | DEFAULT NOW() |

### 核心索引

1. `messages(conversation_id, id DESC)` — 聊天历史 cursor 分页
2. `messages(sender_id, read_at) WHERE read_at IS NULL` — 未读消息（部分索引）
3. `friendships(user_id, status)` — 好友列表（user_id 方向）
4. `friendships(friend_id, status)` — 好友列表（friend_id 方向）
5. `refresh_tokens(user_id, revoked) WHERE revoked = false` — 活跃 token
6. `devices(user_id)` — 查找推送目标

### 私聊会话创建时机

好友请求被接受时，服务端自动创建 private 类型 conversation 并插入两个 conversation_members。发消息时若会话不存在则自动创建（幂等保护）。

### 头像处理

- 客户端上传前裁剪为正方形
- 服务端生成多尺寸：`avatar_200x200.jpg`（缩略图）、原图
- `avatar_thumb_url` 指向 200x200 缩略图

---

## 第三节：API 与 WebSocket

### REST API（14 接口）

```
# 鉴权
POST   /api/auth/register             注册
POST   /api/auth/login                登录 → access_token + refresh_token
POST   /api/auth/refresh              刷新 token 对（轮换：新 token 替代旧 token）
POST   /api/auth/logout               吊销当前 refresh_token

# 用户
GET    /api/users/search?q=           搜索用户
GET    /api/users/:id/profile         查看用户资料
PUT    /api/users/me/profile          更新自己的资料（显示名/头像）
POST   /api/users/me/avatar           专用头像上传（自动裁剪 + 多尺寸）

# 好友
GET    /api/friends                   好友列表（分页）
GET    /api/friends/requests          待处理的好友请求

# 会话
GET    /api/conversations/:id         会话详情

# 消息
DELETE /api/messages/:id              删除消息（两端删除）

# 管理后台
GET    /api/admin/stats              数据看板统计
GET    /api/admin/users              用户列表（搜索 + 分页）
PUT    /api/admin/users/:id          修改用户（禁用/启用）
GET    /api/admin/messages           会话监控 + 关键词搜索
GET    /api/admin/logs               系统日志（分页 + 级别过滤）

# 文件 & 设备
POST   /api/upload                    上传文件/图片 (multipart)
POST   /api/devices                   注册推送 device token
DELETE /api/devices/:id              注销设备
```

### 统一错误码

```json
{"code": 21001, "message": "不是好友关系", "data": null}
```

| 区间 | 范围 |
|------|------|
| 20001-20099 | 用户相关（未登录/无权限/账号禁用） |
| 21001-21099 | 好友关系（非好友/已拉黑/请求已存在） |
| 22001-22099 | 消息（撤回超时/过于长/空内容） |
| 23001-23099 | 文件上传（过大/类型错误） |
| 24001-24099 | 通话（用户正忙/ICE 超时/权限拒绝） |

### Socket.IO 事件

**客户端 → 服务端**：
- `message:send` — 发送消息（content ≤ 5000 字符）
- `message:read` — 标记已读（更新 conversation_members.unread_count = 0）
- `message:recall` — 撤回消息（2 分钟内 + sender 校验）
- `conversation:list` — 获取会话列表（含 last_message、unread_count）
- `conversation:history` — 分页获取历史消息（cursor 分页，默认 20 条）
- `conversation:typing` — 正在输入
- `friend:add` / `friend:accept` / `friend:remove`
- `call:start` / `call:accept` / `call:reject` / `call:end` / `call:cancel`
- `call:signal` — WebRTC SDP/ICE 候选转发
- `ping` — 心跳（30s 间隔）

**服务端 → 客户端**：
- `message:new` — 新消息推送
- `message:recalled` — 撤回通知
- `message:read_ack` — 已读回执
- `friend:request` / `friend:accepted`
- `call:incoming` / `call:ended` / `call:rejected`
- `call:signal` — 转发对方 SDP/ICE
- `typing:update` — 对方正在输入
- `online:update` — 在线状态变更（{ userId, status: online|offline|background }）

### Socket.IO 房间管理

```javascript
// 用户连接时自动加入专属房间
socket.join(`user:${userId}`);

// 打开私聊时加入会话房间（可选，提高推送效率）
socket.join(`conv:${conversationId}`);

// 发送给特定用户
io.to(`user:${userId}`).emit('message:new', data);

// 广播给会话所有成员
io.to(`conv:${conversationId}`).emit('message:new', data);
```

### 在线状态机制

| 状态 | 触发条件 |
|------|----------|
| **online** | Socket.IO 连接建立 |
| **background** | 客户端进入后台时主动发送 `online:update { status: 'background' }` |
| **offline** | 心跳超时 60s 无 ping → 服务端标记离线 |

客户端每 30s 发送 `ping`，服务端 60s 未收到则广播 `online:update { status: 'offline' }`。

### 文件上传（IStorageProvider 抽象）

```javascript
// upload.js — 存储接口抽象
class IStorageProvider {
  async upload(path, buffer, options) {}  // 返回 URL
  async delete(path) {}
  async getUrl(path) {}                    // 返回可访问 URL
}

class LocalStorage extends IStorageProvider { /* 本地文件系统 */ }
class S3Storage extends IStorageProvider { /* S3/MinIO */ }

// MVP 使用 LocalStorage，切换云存储时注入 S3Storage 即可
```

---

## 第四节：WebRTC 通话流程

### 信令流程（10 步）

```
① A → 服务端: call:start
② 服务端: 生成 room_id (UUID) + 检查 B 是否忙线
   - 忙线 → A: call:rejected (reason: busy)
   - 正常 → B: call:incoming（含 room_id）
③ B → 服务端: call:accept 或 call:reject
   - 拒绝 → A: call:rejected (reason: declined)
   - 接受 → A: call:accepted
④ A 创建 PeerConnection → createOffer()
⑤ A → 服务端 → B: call:signal (offer SDP)
⑥ B 创建 PeerConnection → setRemoteDescription → createAnswer()
⑦ B → 服务端 → A: call:signal (answer SDP)
⑧ A ↔ 服务端 ↔ B: call:signal (ICE candidates 双向)
⑨ A ←═══ 媒体流 P2P ═══→ B
⑩ A/B → 服务端: call:end → 对方: call:ended
```

> room_id 当前仅用于信令匹配和 calls 表记录。WebRTC 是 P2P 的，room_id 为未来 SFU 录制/中转预留。

### 边界规则

- **超时**：A 发出 call:start 后 60s 无应答 → A 端自动 call:cancel
- **忙线检测**：服务端维护 `Map<userId, roomId>` 活跃通话集合
- **ICE 超时**：30s → 提示"连接失败"
- **撤回时限**：消息发送后 2 分钟内可撤回
- **STUN 配置**：`stun:stun.l.google.com:19302` + 备用 `stun:stun1.l.google.com:19302`

---

## 第五节：客户端 UI 设计

### 页面（10 MVP + 2 预留）

| 页面 | 说明 |
|------|------|
| SplashScreen | token 检查 → 自动跳转 |
| AuthScreen | 登录 / 注册 |
| ConversationListScreen | 会话列表（💬 Tab） |
| ChatScreen | 消息列表 + 输入 + 通话入口 |
| CallScreen | 来电 / 通话中界面 |
| CallsHistoryScreen | 通话记录（📞 Tab） |
| ContactsScreen | 好友列表 + 搜索添加（👥 Tab） |
| ProfileScreen | 我的资料编辑 |
| UserDetailScreen | 好友详情 |
| ImagePreviewScreen | 图片/视频大图查看 |
| SettingsScreen | 设置（⚙️ Tab） |
| *GroupInfoScreen* | ⏳ 预留，非 MVP |

### 管理后台（4 页，纯静态 HTML）

| 页面 | 说明 |
|------|------|
| 数据看板 | 注册用户数、日活、消息量、通话量、在线用户 |
| 用户管理 | 搜索、列表、禁用/启用、分页 |
| 消息监控 | 会话列表、关键词搜索、举报处理 |
| 系统日志 | 按级别过滤（INFO/WARN/ERR）、时间范围 |

> 托管于 `chat-server/public/admin/`，管理员通过 `is_admin` 字段区分，独立 JWT 登录。
| *GroupChatScreen* | ⏳ 预留，非 MVP |

### 底部导航（4 Tab）

💬 聊天 | 📞 通话记录 | 👥 联系人 | ⚙️ 设置

### 核心组件（10 MVP + 1 预留）

| 组件 | 说明 |
|------|------|
| MessageBubble | 聊天气泡（状态机：sending → sent/delivered → failed） |
| ChatInputBar | 输入区域（文字 + 表情 + 附件，5000 字符限制提示） |
| ConversationCard | 会话条目（头像 + 最后消息 + 未读角标） |
| AvatarWidget | 用户头像（支持 thumb_url 渐进加载） |
| OnlineBadge | 在线绿点/黄点（后台）/灰点（离线） |
| CallControls | 通话中控制（静音/扬声器/挂断） |
| EmojiPicker | 表情面板 |
| TypingIndicator | 正在输入提示 |
| ImageMessageWidget | 图片消息展示 |
| VoiceRecordWidget | 语音消息录制 |
| *GroupAvatarWidget* | ⏳ 群头像，预留 |

### 原生桥接（2 项）

- **CallKit (iOS) / ConnectionService (Android)** — 系统级来电界面，锁屏/后台可用
- **NotificationHandler** — FCM/APNs 推送 + Deep Link 跳转（携带 conversation_id）

### 状态管理

Riverpod 或 Provider，按领域拆分：
- AuthState — 登录状态
- ChatState — 消息 + 会话列表 + 消息队列（重连恢复）
- CallState — 通话状态
- OnlineState — 在线用户 + 心跳

---

## 第六节：错误处理 & 边界情况

### 服务端（11 项）

| 场景 | 处理 |
|------|------|
| Socket.IO 鉴权失败 | next(Error)，封禁账号实时踢出 |
| API JWT 过期 | 401 → 客户端自动 refresh → 失败则登出 |
| Refresh Token 重放 | 检测到已吊销 token 被使用 → 吊销整个 token 链 |
| 数据库断开 | 连接池自动重连 |
| 重复会话创建 | UNIQUE 索引 + SELECT FOR UPDATE 防并发 |
| 文件上传 | 类型白名单 + 10MB 上限 + 图片压缩至 1080p |
| 文本消息过长 | content > 5000 字符 → 拒绝 |
| 撤回非自己消息 | 检查 sender_id，403 |
| 撤回超时 | 仅 2 分钟内可撤回 |
| 非好友发消息 | 检查 friendships 状态，拒绝 |
| 账号被封禁 | Socket.IO middleware 校验 + deactivated_at |

### 客户端（12 项）

| 场景 | 处理 |
|------|------|
| 网络断开 | 消息队列暂存 → 重连后按序发送（最多 3 次，指数退避） |
| 消息发送失败 | 状态机：sending → sent → failed，气泡显示红色 ⚠️ + 重发 |
| 图片加载失败 | 占位图 + 点击重试 |
| 通话 ICE 超时 | 30s 提示"连接失败" |
| 权限被拒 | 引导对话框 → openAppSettings() |
| Push Token 失败 | 静默，下次重试 |
| 消息 ID 冲突 | 客户端 UUID 临时 ID → 服务端返回真实 ID 替换 |
| 消息插入顺序 | WebSocket + HTTP 历史合并后按 created_at 排序 |
| 未读数清零 | 仅进入 ChatScreen 时清零，列表页不清零 |
| 消息清理 | 每会话上限 5000 条 + 7 天未看图片清缓存 |
| 旧设备 token | 定期清理 30 天未更新的设备记录 |
| 被踢出群聊 | ⏳ 清理本地会话消息 + 不再接收推送 |

### 日志与监控

- 服务端：401 失败率、消息发送失败率（>5% 告警）、Socket.IO 断线原因统计
- 客户端：Firebase Crashlytics / Sentry 崩溃上报

---

## 第七节：测试策略

### 测试分层（6 层）

| 层级 | 工具 | 覆盖率目标 |
|------|------|------------|
| 服务端单元 | Jest | auth ≥95% · 消息 ≥90% · 好友 ≥85% |
| 服务端集成 | Supertest + socket.io-client | API + Socket.IO 事件流 |
| 客户端 Widget | flutter_test | Service ≥90% · Widget ≥80% · 页面 ≥70% |
| 客户端集成 | integration_test | 登录→聊天→已读→通话 完整流程 |
| E2E | Patrol (Flutter) | 安装→登录→聊天→退出（中优先级） |
| 性能 | k6 / Artillery | WebSocket 并发 + 消息吞吐（MVP 后） |

### 核心测试场景（14 项）

1. 注册 → 登录 → JWT 过期 → refresh 轮换 → 登出
2. Refresh token 重放检测 → 吊销整条链
3. 好友添加 → 接受 → 自动创建会话
4. 消息发送 → 撤回（2 分钟内 + 超时拒绝 + 非 sender 拒绝）
5. 非好友发消息被拒绝
6. 弱网下 10 条消息顺序验证
7. 多设备未读数同步（conversation_members.unread_count）
8. 文件上传中断恢复
9. DB 迁移兼容旧数据
10. 通话忙线/拒接/超时取消/正常通话
11. 网络断开 → 消息队列 → 重连恢复
12. 在线状态：online → background → offline 转换
13. 时区时间戳 + DB 死锁恢复 + 推送限流
14. 头像上传 → 多尺寸生成 → thumb_url 渐进加载

### CI/CD

GitHub Actions: push → backend-test + flutter-test → build APK/IPA

### 测试数据工厂

`TestFactory` 工具类: `createUser()` / `createConversation()` / `createMessage()` / `createFriendship()`

---

## 技术选型摘要

| 层 | 选型 |
|----|------|
| 客户端框架 | Flutter (Dart) |
| 状态管理 | Riverpod 或 Provider |
| WebRTC 库 | flutter_webrtc |
| 服务端框架 | Express.js |
| 实时通信 | Socket.IO |
| 数据库 | PostgreSQL |
| 鉴权 | JWT (access 15min + refresh 7d，轮换机制) |
| 推送 | Firebase Cloud Messaging + APNs |
| 对象存储 | 本地文件系统 (IStorageProvider 接口) |
| STUN | Google 免费 STUN |
| 崩溃上报 | Firebase Crashlytics / Sentry |

---

## 变更记录

### v1.1（审查修正）

**严重修复（4 项）：**
1. Refresh Token 轮换 — `parent_token_id` 链式追踪 + 重放检测
2. 未读数持久化 — `conversation_members.unread_count` 冗余字段
3. 好友关系单行存储 — LEAST/GREATEST + 唯一索引
4. `message_reads` 表 — 完整 schema 即时定义

**中等改进（5 项）：**
5. 文件上传 `IStorageProvider` 接口抽象
6. room_id 用途说明（信令匹配 + 预留 SFU）
7. 消息体 5000 字符限制
8. Socket.IO 房间管理（user room / conv room）
9. 在线状态细化（online/offline/background + 心跳机制）

**轻微优化（6 项）：**
10. 术语统一（friendships 增加 rejected；calls 增加 cancelled）
11. 头像多尺寸（avatar_thumb_url 200x200）
12. API 补充（好友列表/请求、会话详情、专用头像上传、消息删除）
13. users 表补充（avatar_thumb_url、deactivated_at、last_seen_at）；messages 表补充（reply_to_msg_id）
14. 安全加固（速率限制、E.164 格式、token TTL 15min/7d）
15. 性能优化（触发器自动更新 last_message、cursor 分页）
16. 日志监控 + 测试场景增至 14 项

### v1.2（管理后台）
17. 新增管理后台（4 页纯静态 HTML + 5 个 Admin API）
18. users 表增加 `is_admin` 字段

---

## 与原嗷嗷项目的差异

| 维度 | 原 AoaoChat | 新设计 |
|------|-------------|--------|
| 会话模型 | 消息直接绑定 from_user → to_user | conversation 抽象，消息绑定 conversation_id |
| 好友关系 | 单表双向行 | friendships 单行 + LEAST/GREATEST |
| 消息撤回 | 无 | ✅ deleted_at 软删除 + 2 分钟时限 |
| 已读 | read BOOLEAN | read_at TIMESTAMP + unread_count 持久化 |
| 阅读回执 | 无 | ✅ message_reads 表（单聊+群聊通用） |
| 数据库 | SQLite/PostgreSQL 双模式 | PostgreSQL 统一 |
| 通话 | 占位提示"即将上线" | ✅ WebRTC P2P 完整实现 |
| Token 管理 | 无 refresh | ✅ 轮换 + 链式追踪 + 重放检测 |
| 附件 | 无独立表 | ✅ attachments 表 |
| 设备管理 | 无 | ✅ devices 表 + push token 管理 |
| 在线状态 | 简单 connect/disconnect | ✅ 心跳 + online/background/offline |
| 速率限制 | 无 | ✅ express-rate-limit |
| 测试 | widget_test.dart 空壳 | ✅ 6 层测试 + 14 场景 + CI/CD |
