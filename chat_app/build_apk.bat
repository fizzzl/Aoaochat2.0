@echo off
set JAVA_HOME=C:\Android\jdk-17
set PATH=C:\Android\jdk-17\bin;%PATH%
cd /d C:\Users\WIN10\AppData\Local\Reasonix\.worktrees\aoaochat-v2\chat_app
echo [BUILD] compileSdk=35 minSdk=21...
flutter build apk --debug
echo [BUILD] Exit: %ERRORLEVEL%
dir build\app\outputs\flutter-apk\*.apk 2>nul || echo No APK found
