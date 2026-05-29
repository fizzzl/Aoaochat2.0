import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../config.dart';

class ImagePreviewScreen extends StatelessWidget {
  final String imageUrl;
  final String? tag;
  const ImagePreviewScreen({super.key, required this.imageUrl, this.tag});

  @override
  Widget build(BuildContext context) {
    final fullUrl = imageUrl.startsWith('http') ? imageUrl : '${AppConfig.serverUrl}$imageUrl';
    return Scaffold(
      backgroundColor: const Color(0xFF0B1C30),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0B1C30),
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.download_outlined),
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('长按图片保存'), behavior: SnackBarBehavior.floating));
            },
          ),
        ],
      ),
      body: Center(
        child: InteractiveViewer(
          minScale: 0.5,
          maxScale: 4.0,
          child: tag != null
            ? Hero(tag: tag!, child: Image.network(fullUrl, fit: BoxFit.contain))
            : Image.network(fullUrl, fit: BoxFit.contain),
        ),
      ),
    );
  }
}
