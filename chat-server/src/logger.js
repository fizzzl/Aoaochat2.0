// chat-server/src/logger.js — 结构化日志
const levels = { INFO: 'INFO', WARN: 'WARN', ERROR: 'ERR' };

function log(level, message, data = {}) {
  const entry = {
    timestamp: new Date().toISOString(),
    level,
    message,
    ...data,
  };
  const line = JSON.stringify(entry);
  if (level === levels.ERROR) console.error(line);
  else if (level === levels.WARN) console.warn(line);
  else console.log(line);
}

module.exports = {
  info: (msg, data) => log(levels.INFO, msg, data),
  warn: (msg, data) => log(levels.WARN, msg, data),
  error: (msg, data) => log(levels.ERROR, msg, data),
  levels,
};
