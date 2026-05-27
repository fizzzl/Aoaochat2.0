// chat_app/lib/screens/image_preview_screen.dart
import 'package:flutter/material.dart';

class ImagePreviewScreen extends StatelessWidget {
  const ImagePreviewScreen({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('图片预览')),
    body: const Center(child: Text('图片预览', style: TextStyle(color: Colors.grey))),
  );
}
