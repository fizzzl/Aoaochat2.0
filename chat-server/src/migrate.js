// chat-server/src/migrate.js — 数据库迁移（10 表 + 6 索引 + 触发器）
require('dotenv').config();
const { getPool, close } = require('./db');

const schema = `
-- 1. users
CREATE TABLE IF NOT EXISTS users (
  id SERIAL PRIMARY KEY,
  username VARCHAR(50) UNIQUE NOT NULL,
  password_hash VARCHAR(255) NOT NULL,
  display_name VARCHAR(100) NOT NULL,
  avatar_url TEXT,
  avatar_thumb_url TEXT,
  phone VARCHAR(20),
  is_admin BOOLEAN DEFAULT FALSE,
  token_version INT DEFAULT 0,
  last_seen_at TIMESTAMP,
  deactivated_at TIMESTAMP,
  created_at TIMESTAMP DEFAULT NOW(),
  updated_at TIMESTAMP DEFAULT NOW()
);

-- 2. refresh_tokens
CREATE TABLE IF NOT EXISTS refresh_tokens (
  id SERIAL PRIMARY KEY,
  user_id INT REFERENCES users(id),
  token_hash VARCHAR(255) UNIQUE NOT NULL,
  parent_token_id INT,
  expires_at TIMESTAMP NOT NULL,
  revoked BOOLEAN DEFAULT FALSE,
  created_at TIMESTAMP DEFAULT NOW()
);

-- 3. conversations
CREATE TABLE IF NOT EXISTS conversations (
  id SERIAL PRIMARY KEY,
  type VARCHAR(10) NOT NULL DEFAULT 'private',
  name VARCHAR(100),
  last_message TEXT,
  last_message_time TIMESTAMP,
  created_at TIMESTAMP DEFAULT NOW()
);

-- 4. conversation_members
CREATE TABLE IF NOT EXISTS conversation_members (
  conversation_id INT REFERENCES conversations(id),
  user_id INT REFERENCES users(id),
  unread_count INT DEFAULT 0,
  last_read_msg_id INT,
  joined_at TIMESTAMP DEFAULT NOW(),
  UNIQUE(conversation_id, user_id)
);

-- 5. messages
CREATE TABLE IF NOT EXISTS messages (
  id SERIAL PRIMARY KEY,
  conversation_id INT REFERENCES conversations(id),
  sender_id INT REFERENCES users(id),
  reply_to_msg_id INT,
  type VARCHAR(10) NOT NULL DEFAULT 'text',
  content TEXT NOT NULL,
  read_at TIMESTAMP,
  deleted_at TIMESTAMP,
  created_at TIMESTAMP DEFAULT NOW()
);

-- 6. message_reads
CREATE TABLE IF NOT EXISTS message_reads (
  message_id INT REFERENCES messages(id),
  user_id INT REFERENCES users(id),
  read_at TIMESTAMP DEFAULT NOW(),
  PRIMARY KEY (message_id, user_id)
);

-- 7. attachments
CREATE TABLE IF NOT EXISTS attachments (
  id SERIAL PRIMARY KEY,
  message_id INT REFERENCES messages(id),
  url TEXT NOT NULL,
  thumb_url TEXT,
  mime_type VARCHAR(100),
  size INT,
  width INT,
  height INT,
  created_at TIMESTAMP DEFAULT NOW()
);

-- 8. friendships
CREATE TABLE IF NOT EXISTS friendships (
  id SERIAL PRIMARY KEY,
  user_id INT REFERENCES users(id),
  friend_id INT REFERENCES users(id),
  action_user_id INT,
  status VARCHAR(10) NOT NULL DEFAULT 'pending',
  created_at TIMESTAMP DEFAULT NOW(),
  updated_at TIMESTAMP DEFAULT NOW()
);

-- 9. calls
CREATE TABLE IF NOT EXISTS calls (
  id SERIAL PRIMARY KEY,
  caller_id INT REFERENCES users(id),
  callee_id INT REFERENCES users(id),
  type VARCHAR(10) NOT NULL DEFAULT 'voice',
  room_id VARCHAR(36),
  status VARCHAR(10) NOT NULL DEFAULT 'missed',
  started_at TIMESTAMP,
  ended_at TIMESTAMP
);

-- 10. devices
CREATE TABLE IF NOT EXISTS devices (
  id SERIAL PRIMARY KEY,
  user_id INT REFERENCES users(id),
  platform VARCHAR(10) NOT NULL,
  push_token TEXT NOT NULL,
  created_at TIMESTAMP DEFAULT NOW(),
  updated_at TIMESTAMP DEFAULT NOW()
);

-- Indexes
CREATE INDEX IF NOT EXISTS idx_messages_conv_id ON messages(conversation_id, id DESC);
CREATE INDEX IF NOT EXISTS idx_messages_unread ON messages(sender_id, read_at) WHERE read_at IS NULL;
CREATE INDEX IF NOT EXISTS idx_friendships_user ON friendships(user_id, status);
CREATE INDEX IF NOT EXISTS idx_friendships_friend ON friendships(friend_id, status);
CREATE INDEX IF NOT EXISTS idx_refresh_tokens_active ON refresh_tokens(user_id, revoked) WHERE revoked = false;
CREATE INDEX IF NOT EXISTS idx_devices_user ON devices(user_id);
CREATE UNIQUE INDEX IF NOT EXISTS idx_friendships_uniq ON friendships(LEAST(user_id, friend_id), GREATEST(user_id, friend_id));

-- Trigger: update conversation last_message
CREATE OR REPLACE FUNCTION update_conversation_last_message()
RETURNS TRIGGER AS $$
BEGIN
  IF TG_OP = 'INSERT' THEN
    UPDATE conversations SET last_message = NEW.content, last_message_time = NEW.created_at
    WHERE id = NEW.conversation_id;
  ELSIF TG_OP = 'UPDATE' AND NEW.deleted_at IS NOT NULL THEN
    UPDATE conversations SET last_message = COALESCE(
      (SELECT content FROM messages WHERE conversation_id = NEW.conversation_id AND deleted_at IS NULL ORDER BY created_at DESC LIMIT 1),
      ''
    ) WHERE id = NEW.conversation_id;
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_messages_last ON messages;
CREATE TRIGGER trg_messages_last
  AFTER INSERT OR UPDATE OF deleted_at ON messages
  FOR EACH ROW EXECUTE FUNCTION update_conversation_last_message();
`;

async function migrate() {
  console.log('[Migrate] Running database migration...');
  const pool = getPool();
  await pool.query(schema);
  console.log('[Migrate] Migration complete.');
}

if (require.main === module) {
  migrate().then(() => close()).catch((err) => {
    console.error('[Migrate] Error:', err);
    process.exit(1);
  });
}

module.exports = { migrate };
