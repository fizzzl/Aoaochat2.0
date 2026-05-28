// chat_app/lib/screens/call_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:provider/provider.dart';
import 'package:permission_handler/permission_handler.dart';
import '../services/socket_service.dart';

class CallScreen extends StatefulWidget {
  final int calleeId;
  final String calleeName;
  final String type;
  final bool isIncoming;
  final String? roomId;
  final int? callerId;
  final String? callerName;

  const CallScreen({super.key, required this.calleeId, required this.calleeName,
    this.type = 'voice', this.isIncoming = false, this.roomId, this.callerId, this.callerName});

  @override
  State<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends State<CallScreen> {
  RTCPeerConnection? _pc;
  MediaStream? _localStream;
  RTCVideoRenderer? _remoteRenderer;
  bool _muted = false;
  bool _speakerOn = true;
  bool _connected = false;
  String _status = '';

  @override
  void initState() {
    super.initState();
    _status = widget.isIncoming ? '来电...' : '呼叫中...';
    _setupCallbacks();
    _initWebRTC();
  }

  void _setupCallbacks() {
    final socket = context.read<SocketService>();
    socket.onCallAccepted = (data) {
      setState(() => _status = '对方已接听');
    };
    socket.onCallRejected = (data) {
      _hangUp();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(data['reason'] == 'busy' ? '对方正忙' : '对方拒绝'), behavior: SnackBarBehavior.floating));
    };
    socket.onCallEnded = (data) {
      _hangUp();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('通话结束'), behavior: SnackBarBehavior.floating));
    };
    socket.onCallSignal = (data) async {
      final signal = data['signal'];
      if (signal == null || _pc == null) return;
      try {
        if (signal['type'] == 'offer') {
          await _pc!.setRemoteDescription(
            RTCSessionDescription(signal['sdp'], 'offer'));
          final answer = await _pc!.createAnswer();
          await _pc!.setLocalDescription(answer);
          final otherId = widget.isIncoming ? widget.callerId : widget.calleeId;
          socket.sendSignal(toUserId: otherId!, signal: {
            'type': 'answer', 'sdp': answer.sdp,
          });
        } else if (signal['type'] == 'answer') {
          await _pc!.setRemoteDescription(
            RTCSessionDescription(signal['sdp'], 'answer'));
        } else if (signal['type'] == 'candidate') {
          await _pc!.addCandidate(RTCIceCandidate(
            signal['candidate'], signal['sdpMid'], signal['sdpMLineIndex']));
        }
      } catch (e) {
        debugPrint('Call signal error: $e');
      }
    };
  }

  Future<void> _initWebRTC() async {
    // 请求麦克风权限
    final micStatus = await Permission.microphone.request();
    if (!micStatus.isGranted) {
      setState(() => _status = '需要麦克风权限');
      return;
    }
    if (widget.type == 'video') {
      final camStatus = await Permission.camera.request();
      if (!camStatus.isGranted) {
        setState(() => _status = '需要摄像头权限');
        return;
      }
    }

    try {
      final config = {
        'iceServers': [
          {'urls': 'stun:stun.l.google.com:19302'},
          {'urls': 'stun:stun1.l.google.com:19302'},
        ],
      };
      _pc = await createPeerConnection(config);

      _localStream = await navigator.mediaDevices.getUserMedia({
        'audio': true, 'video': widget.type == 'video',
      });
      _pc!.addStream(_localStream!);

      final socket = context.read<SocketService>();

      _pc!.onIceCandidate = (candidate) {
        if (candidate.candidate != null) {
          final otherId = widget.isIncoming ? widget.callerId : widget.calleeId;
          socket.sendSignal(toUserId: otherId!, signal: {
            'type': 'candidate',
            'candidate': candidate.candidate,
            'sdpMid': candidate.sdpMid,
            'sdpMLineIndex': candidate.sdpMLineIndex,
          });
        }
      };

      _pc!.onAddStream = (stream) {
        setState(() { _connected = true; _status = '通话中'; });
      };

      if (!widget.isIncoming) {
        final offer = await _pc!.createOffer();
        await _pc!.setLocalDescription(offer);
        socket.sendSignal(toUserId: widget.calleeId, signal: {
          'type': 'offer', 'sdp': offer.sdp,
        });
        if (mounted) setState(() => _status = '等待对方接听...');
      }
    } catch (e) {
      setState(() => _status = '连接失败: $e');
    }
  }

  void _hangUp() {
    context.read<SocketService>().endCall();
    _pc?.close();
    _localStream?.dispose();
    _remoteRenderer?.dispose();
    Navigator.pop(context);
  }

  @override
  void dispose() {
    _pc?.close();
    _localStream?.dispose();
    _remoteRenderer?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1a1a2e),
      body: SafeArea(
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          const Spacer(),
          CircleAvatar(radius: 40, backgroundColor: const Color(0xFFDBE1FF),
            child: Text(widget.isIncoming ? (widget.callerName ?? '?')[0] : widget.calleeName[0],
              style: const TextStyle(fontSize: 32, color: Color(0xFF2563EB)))),
          const SizedBox(height: 16),
          Text(widget.isIncoming ? (widget.callerName ?? '未知') : widget.calleeName,
            style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Text(_status, style: const TextStyle(color: Colors.grey, fontSize: 14)),
          const Spacer(),
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            if (widget.isIncoming && !_connected) ...[
              _callButton(Icons.call_end, const Color(0xFFEF4444), () {
                context.read<SocketService>().rejectCall(widget.roomId ?? '');
                Navigator.pop(context);
              }, size: 28),
              const SizedBox(width: 24),
              _callButton(Icons.call, const Color(0xFF22C55E), () {
                context.read<SocketService>().acceptCall(widget.roomId ?? '');
                setState(() => _status = '连接中...');
              }, size: 28),
            ] else ...[
              _callButton(Icons.mic_off, _muted ? Colors.white : const Color(0xFF334155), () => setState(() => _muted = !_muted)),
              const SizedBox(width: 20),
              _callButton(Icons.volume_up, _speakerOn ? Colors.white : const Color(0xFF334155), () => setState(() => _speakerOn = !_speakerOn)),
              const SizedBox(width: 20),
              _callButton(Icons.call_end, const Color(0xFFEF4444), _hangUp, size: 28),
            ],
          ]),
          const SizedBox(height: 40),
        ]),
      ),
    );
  }

  Widget _callButton(IconData icon, Color color, VoidCallback onTap, {double size = 22}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(width: 56, height: 56, decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        child: Icon(icon, color: color == const Color(0xFFEF4444) ? Colors.white : const Color(0xFF0B1C30), size: size)),
    );
  }
}
