// test_call.js - qafinal 接听来电
const io = require('socket.io-client');
const http = require('http');
const SERVER = 'http://39.105.90.177:3000';

const loginData = JSON.stringify({username:'qafinal',password:'test123'});
const req = http.request(`${SERVER}/api/auth/login`, {
  method: 'POST',
  headers: {'Content-Type':'application/json','Content-Length':Buffer.byteLength(loginData)}
}, res => {
  let body = '';
  res.on('data', d => body += d);
  res.on('end', () => {
    const token = JSON.parse(body).data.accessToken;
    console.log('✅ qafinal 已登录, 等待来电...');

    const socket = io(SERVER, { transports: ['websocket'], auth: { token } });
    
    socket.on('connect', () => console.log('✅ Socket 连接'));
    
    let answered = false;
    socket.on('call:incoming', data => {
      if (answered) return;
      answered = true;
      console.log(`\n🔔 来电！${data.callerName} (${data.type}) roomId:${data.roomId}`);
      console.log('📞 接听中...');
      socket.emit('call:accept', { roomId: data.roomId });
    });

    socket.on('call:accepted', () => console.log('✅ 通话建立！'));
    socket.on('call:ended', () => console.log('📴 通话结束'));
    socket.on('call:signal', d => console.log(`📡 ${d.signal?.type}`));
    
    setTimeout(() => { console.log('⏰ 超时'); process.exit(0); }, 120000);
  });
});
req.write(loginData);
req.end();
