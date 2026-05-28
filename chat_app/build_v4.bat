@echo off
set JAVA_HOME=C:\Android\jdk-17
set PATH=C:\Android\jdk-17\bin;%PATH%
cd /d C:\Users\WIN10\AppData\Local\Reasonix\.worktrees\aoaochat-v2\chat_app
echo [BUILD v4] compileSdk=36
flutter build apk --debug
echo EXIT=%ERRORLEVEL%
dir build\app\outputs\flutter-apk\*.apk 2>nul
