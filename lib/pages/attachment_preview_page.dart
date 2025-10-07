import 'dart:typed_data';
import 'package:flutter/cupertino.dart';

class AttachmentPreviewPage extends StatelessWidget {
  final String name;
  final Uint8List bytes;
  final String? mime;
  const AttachmentPreviewPage({super.key, required this.name, required this.bytes, this.mime});

  @override
  Widget build(BuildContext context) {
    final isImage = (mime ?? '').startsWith('image/');
    return CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar(middle: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis)),
      child: SafeArea(
        child: Center(
          child: isImage
              ? InteractiveViewer(child: Image.memory(bytes, fit: BoxFit.contain))
              : const Text('Vorschau nicht verfügbar. Bitte "Öffnen…" benutzen.'),
        ),
      ),
    );
  }
}

