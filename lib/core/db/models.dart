enum SyncStatus { pending, synced }

enum LineSource { manual, grai }

class CaptureLine {
  CaptureLine({
    required this.id,
    required this.boxModel,
    required this.quantity,
    required this.source,
    this.graiRaw,
  });

  final String id;
  final String boxModel;
  final int quantity;
  final LineSource source;
  final String? graiRaw;

  Map<String, Object?> toMap(String captureId) => {
        'id': id,
        'capture_id': captureId,
        'box_model': boxModel,
        'quantity': quantity,
        'source': source.name,
        'grai_raw': graiRaw,
      };

  factory CaptureLine.fromMap(Map<String, Object?> m) => CaptureLine(
        id: m['id'] as String,
        boxModel: m['box_model'] as String,
        quantity: m['quantity'] as int,
        source: LineSource.values.byName(m['source'] as String),
        graiRaw: m['grai_raw'] as String?,
      );

  Map<String, Object?> toJson() => {
        'boxModel': boxModel,
        'quantity': quantity,
        'source': source.name,
        'graiRaw': graiRaw,
      };
}

class Capture {
  Capture({
    required this.id,
    required this.order,
    required this.supplier,
    required this.scannedAt,
    required this.lines,
    this.status = SyncStatus.pending,
  });

  final String id;
  final String order;
  final String supplier;
  final DateTime scannedAt; // fecha/hora del escaneo
  final List<CaptureLine> lines;
  final SyncStatus status;

  Map<String, Object?> toMap() => {
        'id': id,
        'order_code': order,
        'supplier': supplier,
        'scanned_at': scannedAt.toUtc().toIso8601String(),
        'sync_status': status.name,
      };

  Map<String, Object?> toJson() => {
        'id': id,
        'order': order,
        'supplier': supplier,
        'scannedAt': scannedAt.toUtc().toIso8601String(),
        'lines': lines.map((l) => l.toJson()).toList(),
      };
}

/// Producto (modelo de caja) de los datos maestros.
/// [code] es el trozo del GRAI que lo identifica; null = solo se usa a mano.
class Product {
  const Product({required this.id, required this.name, this.code});
  final int id;
  final String name;
  final String? code;
}
