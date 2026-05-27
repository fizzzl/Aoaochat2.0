// chat-server/src/signaling.js — WebRTC 信令（预留 SFU 扩展）
// 当前实现：信令直接通过 Socket.IO 的 call:signal 事件转发
// room_id 用于 calls 表记录，未来 SFU 接入时在此处理房间管理

const activeRooms = new Map(); // roomId -> Set<userId>

function joinRoom(roomId, userId) {
  if (!activeRooms.has(roomId)) {
    activeRooms.set(roomId, new Set());
  }
  activeRooms.get(roomId).add(userId);
}

function leaveRoom(roomId, userId) {
  const room = activeRooms.get(roomId);
  if (room) {
    room.delete(userId);
    if (room.size === 0) activeRooms.delete(roomId);
  }
}

function getRoomUsers(roomId) {
  return activeRooms.get(roomId) || new Set();
}

module.exports = { joinRoom, leaveRoom, getRoomUsers };
