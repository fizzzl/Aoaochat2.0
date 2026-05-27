// chat-server/src/push.js — FCM/APNs 推送
const db = require('./db');
const logger = require('./logger');

let fcm = null;

function initFCM() {
  const keyPath = process.env.FCM_SERVICE_ACCOUNT_PATH;
  if (!keyPath) {
    logger.warn('FCM 未配置，推送功能不可用');
    return;
  }
  try {
    const admin = require('firebase-admin');
    const serviceAccount = require(keyPath);
    fcm = admin.initializeApp({ credential: admin.credential.cert(serviceAccount) });
    logger.info('FCM 初始化成功');
  } catch (err) {
    logger.error('FCM 初始化失败', { error: err.message });
  }
}

async function sendPush(userId, title, body, data = {}) {
  if (!fcm) return;

  try {
    const devices = await db.getAll(
      'SELECT push_token, platform FROM devices WHERE user_id = $1 AND updated_at > NOW() - INTERVAL \'30 days\'',
      [userId]
    );

    for (const device of devices) {
      const message = {
        notification: { title, body },
        data: { ...data, click_action: 'FLUTTER_NOTIFICATION_CLICK' },
        token: device.push_token,
      };

      if (device.platform === 'android') {
        message.android = { priority: 'high', notification: { sound: 'default', channelId: 'chat' } };
      } else if (device.platform === 'ios') {
        message.apns = { payload: { aps: { sound: 'default', badge: 1 } } };
      }

      try {
        await fcm.messaging().send(message);
      } catch (err) {
        if (err.code === 'messaging/registration-token-not-registered') {
          await db.run('DELETE FROM devices WHERE push_token = $1', [device.push_token]);
        } else {
          logger.error('FCM 发送失败', { error: err.message, userId });
        }
      }
    }
  } catch (err) {
    logger.error('推送失败', { error: err.message });
  }
}

module.exports = { initFCM, sendPush };
