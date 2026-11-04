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
      body: MobileScanner(
        controller: _controller,
        onDetect: _onDetect,
        placeholderBuilder: (context, child) =>
            const Center(child: CircularProgressIndicator()),
        errorBuilder: (context, error, child) => _CameraError(
          error: error,
          onRetry: () => _controller.start(),
        ),
      ),
    );
  }
}

/// Explica por qué no arranca la cámara en lugar de dejar la pantalla en negro.
class _CameraError extends StatelessWidget {
  const _CameraError({required this.error, required this.onRetry});
  final MobileScannerException error;
  final VoidCallback onRetry;

  String get _explanation {
    switch (error.errorCode) {
      case MobileScannerErrorCode.permissionDenied:
        return 'La app no tiene permiso para usar la cámara.\n\n'
            'Ábrela desde Ajustes del móvil → Aplicaciones → Scannapp → '
            'Permisos → Cámara → Permitir, y pulsa Reintentar.';
      case MobileScannerErrorCode.unsupported:
        return 'Este dispositivo no admite el escáner de la cámara.';
      default:
        return 'No se pudo iniciar la cámara.';
    }
  }

  @override
  Widget build(BuildContext context) {
    final details = error.errorDetails?.message;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.no_photography, size: 48),
            const SizedBox(height: 16),
            Text(_explanation, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            SelectableText(
              'Código: ${error.errorCode.name}'
              '${details == null ? '' : '\n$details'}',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('Reintentar'),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Volver y escribir a mano'),
            ),
          ],
        ),
      ),
    );
  }
}
