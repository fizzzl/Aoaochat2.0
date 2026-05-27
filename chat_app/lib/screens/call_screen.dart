// chat_app/lib/screens/call_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import '../services/socket_service.dart';

class CallScreen extends StatefulWidget {
  final int calleeId;
  final String calleeName;
  final String type; // voice | video
  final bool isIncoming;
  final String? roomId;
  final int? callerId;
  final String? callerName;

  const CallScreen({
    super.key,
    required this.calleeId,
    required this.calleeName,
    this.type = 'voice',
    this.isIncoming = false,
    this.roomId,
    this.callerId,
    this.callerName,
  });

  @override
  State<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends State<CallScreen> {
  RTCPeerConnection? _pc;
  MediaStream? _localStream;
  bool _muted = false;
  bool _speakerOn = true;
  bool _connected = false;
  String _status = '';

  @override
  void initState() {
    super.initState();
    _status = widget.isIncoming ? '来电...' : '呼叫中...';
    _initWebRTC();
  }

  Future<void> _initWebRTC() async {
    try {
      final config = {
        'iceServers': [
          {'urls': 'stun:stun.l.google.com:19302'},
          {'urls': 'stun:stun1.l.google.com:19302'},
        ],
      };
      _pc = await createPeerConnection(config);

      _localStream = await navigator.mediaDevices.getUserMedia({
        'audio': true,
        'video': widget.type == 'video',
      });
      _pc!.addStream(_localStream!);

      _pc!.onIceCandidate = (candidate) {
        // Send via signaling
      };

      _pc!.onAddStream = (stream) {
        setState(() { _connected = true; _status = '通话中'; });
      };

      if (!widget.isIncoming) {
        final offer = await _pc!.createOffer();
        await _pc!.setLocalDescription(offer);
        // Send offer via socket service
        if (mounted) setState(() => _status = '等待对方接听...');
      }
    } catch (e) {
      setState(() => _status = '连接失败: $e');
    }
  }

  void _hangUp() {
    _pc?.close();
    _localStream?.dispose();
    Navigator.pop(context);
  }

  @override
  void dispose() {
    _pc?.close();
    _localStream?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1a1a2e),
      body: SafeArea(
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          const Spacer(),
          CircleAvatar(
            radius: 40,
            backgroundColor: const Color(0xFFDBE1FF),
            child: Text(
              widget.isIncoming ? (widget.callerName ?? '?')[0] : widget.calleeName[0],
              style: const TextStyle(fontSize: 32, color: Color(0xFF2563EB)),
            ),
          ),
          const SizedBox(height: 16),
          Text(widget.isIncoming ? (widget.callerName ?? '未知') : widget.calleeName,
            style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Text(_status, style: const TextStyle(color: Colors.grey, fontSize: 14)),
          const Spacer(),
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            _callButton(Icons.mic_off, _muted ? Colors.white : const Color(0xFF334155), () => setState(() => _muted = !_muted)),
            const SizedBox(width: 20),
            _callButton(Icons.volume_up, _speakerOn ? Colors.white : const Color(0xFF334155), () => setState(() => _speakerOn = !_speakerOn)),
            const SizedBox(width: 20),
            _callButton(Icons.call_end, const Color(0xFFEF4444), _hangUp, size: 28),
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
        child: Icon(icon, color: color == const Color(0xFFEF4444) ? Colors.white : const Color(0xFF0B1C30), size: size),
      ),
    );
  }
}
