import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

/// Módulo reutilizable: abre la cámara y devuelve el primer código leído
/// con `Navigator.pop(context, valor)`.
///
/// Uso: `final code = await ScannerPage.scan(context, title: 'Escanear pedido');`
class ScannerPage extends StatefulWidget {
  const ScannerPage({super.key, required this.title});
  final String title;

  static Future<String?> scan(BuildContext context, {required String title}) {
    return Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => ScannerPage(title: title)),
    );
  }

  @override
  State<ScannerPage> createState() => _ScannerPageState();
}

class _ScannerPageState extends State<ScannerPage> {
  final _controller = MobileScannerController(
    detectionSpeed: DetectionSpeed.noDuplicates,
  );
  bool _done = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_done) return;
    final value = capture.barcodes
        .map((b) => b.rawValue)
        .whereType<String>()
        .firstWhere((v) => v.isNotEmpty, orElse: () => '');
    if (value.isEmpty) return;
    _done = true;
    Navigator.of(context).pop(value);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        actions: [
          IconButton(
            icon: const Icon(Icons.flash_on),
            onPressed: () => _controller.toggleTorch(),
          ),
          IconButton(
            icon: const Icon(Icons.cameraswitch),
            onPressed: () => _controller.switchCamera(),
          ),
        ],
      ),
      body: MobileScanner(controller: _controller, onDetect: _onDetect),
    );
  }
}
