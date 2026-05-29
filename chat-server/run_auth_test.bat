@echo off
set DATABASE_URL=postgresql://chat_admin:ChatApp2026@39.105.90.177:5432/chat_app
set JWT_SECRET=test-secret
set JWT_REFRESH_SECRET=test-refresh
cd /d C:\Users\WIN10\AppData\Local\Reasonix\.worktrees\aoaochat-v2\chat-server
npx jest tests/auth.test.js --forceExit
