@echo off
set JAVA_HOME=C:\Android\jdk-17
set PATH=C:\Android\jdk-17\bin;%PATH%
cd /d C:\Users\WIN10\AppData\Local\Reasonix\.worktrees\aoaochat-v2\chat_app
flutter build apk --debug
if %ERRORLEVEL% NEQ 0 exit /b %ERRORLEVEL%
C:\Android\Sdk\platform-tools\adb.exe install -r build\app\outputs\flutter-apk\app-debug.apk
C:\Android\Sdk\platform-tools\adb.exe shell am start -n com.chat.chat_app/.MainActivity
