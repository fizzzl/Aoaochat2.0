// chat-server/src/upload.js — 文件/头像上传（IStorageProvider 接口）
const multer = require('multer');
const path = require('path');
const fs = require('fs');
const sharp = require('sharp');

const UPLOAD_DIR = process.env.UPLOAD_DIR || './uploads';

// ── IStorageProvider 接口 ──
class LocalStorage {
  async upload(filePath, buffer) {
    const fullPath = path.join(UPLOAD_DIR, filePath);
    const dir = path.dirname(fullPath);
    if (!fs.existsSync(dir)) fs.mkdirSync(dir, { recursive: true });
    fs.writeFileSync(fullPath, buffer);
    return `/uploads/${filePath}`;
  }

  async delete(filePath) {
    const fullPath = path.join(UPLOAD_DIR, filePath);
    if (fs.existsSync(fullPath)) fs.unlinkSync(fullPath);
  }

  getUrl(filePath) {
    return `/uploads/${filePath}`;
  }
}

const storage = new LocalStorage();

// ── Multer 配置 ──
const fileFilter = (req, file, cb) => {
  const allowed = ['image/jpeg', 'image/png', 'image/webp', 'image/gif', 'audio/aac', 'audio/mp4', 'video/mp4'];
  if (allowed.includes(file.mimetype)) cb(null, true);
  else cb(new Error('不支持的文件类型'), false);
};

const upload = multer({
  storage: multer.memoryStorage(),
  limits: { fileSize: 10 * 1024 * 1024 }, // 10MB
  fileFilter,
});

// ── 通用上传 ──
async function handleUpload(file) {
  const ext = path.extname(file.originalname);
  const filename = `${Date.now()}-${Math.random().toString(36).slice(2, 8)}${ext}`;
  const subdir = file.mimetype.startsWith('image/') ? 'images' : 'files';
  const filePath = `${subdir}/${filename}`;

  let buffer = file.buffer;
  let thumbUrl = null;

  // 图片：自动压缩 + 生成缩略图
  if (file.mimetype.startsWith('image/')) {
    buffer = await sharp(file.buffer)
      .resize(1080, 1080, { fit: 'inside', withoutEnlargement: true })
      .jpeg({ quality: 85 })
      .toBuffer();

    const thumbFilename = `thumb_${filename}`;
    const thumbBuffer = await sharp(file.buffer)
      .resize(200, 200, { fit: 'cover' })
      .jpeg({ quality: 75 })
      .toBuffer();
    await storage.upload(`images/${thumbFilename}`, thumbBuffer);
    thumbUrl = `/uploads/images/${thumbFilename}`;
  }

  const url = await storage.upload(filePath, buffer);
  return { url, thumbUrl, mimeType: file.mimetype, size: buffer.length };
}

// ── 头像上传 ──
async function handleAvatarUpload(file) {
  const filename = `avatar_${Date.now()}.jpg`;

  const original = await sharp(file.buffer)
    .resize(400, 400, { fit: 'cover' })
    .jpeg({ quality: 85 })
    .toBuffer();

  const thumb = await sharp(file.buffer)
    .resize(200, 200, { fit: 'cover' })
    .jpeg({ quality: 75 })
    .toBuffer();

  const avatarUrl = await storage.upload(`avatars/${filename}`, original);
  const thumbUrl = await storage.upload(`avatars/thumb_${filename}`, thumb);

  return { avatarUrl, thumbUrl };
}

module.exports = { upload, handleUpload, handleAvatarUpload, LocalStorage, storage };
