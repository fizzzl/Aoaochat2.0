// chat-server/src/cache.js — 内存 Map（预留 Redis 接口）
class Cache {
  constructor() {
    this._store = new Map();
  }

  get(key) {
    const entry = this._store.get(key);
    if (entry && entry.expiresAt && entry.expiresAt < Date.now()) {
      this._store.delete(key);
      return undefined;
    }
    return entry?.value;
  }

  set(key, value, ttlMs) {
    this._store.set(key, {
      value,
      expiresAt: ttlMs ? Date.now() + ttlMs : undefined,
    });
  }

  delete(key) {
    this._store.delete(key);
  }

  clear() {
    this._store.clear();
  }
}

module.exports = new Cache();
