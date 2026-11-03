import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_email_sender/flutter_email_sender.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import '../db/app_database.dart';
import '../db/models.dart';

/// Contrato con el backend. Sustituye la implementación por tu API real.
abstract class RemoteApi {
  /// Envía una captura. Debe ser idempotente por `capture.id`.
  Future<void> pushCapture(Capture capture);

  /// Descarga catálogos (modelos de caja y pedido -> proveedor).
  Future<({Map<String, String> models, Map<String, String> orderSuppliers})>
      fetchCatalogs();
}

/// Implementación HTTP de ejemplo. Ajusta URL, autenticación y formato.
class HttpRemoteApi implements RemoteApi {
  HttpRemoteApi({required this.baseUrl, this.token});
  final String baseUrl;
  final String? token;

  Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        if (token != null) 'Authorization': 'Bearer $token',
      };

  @override
  Future<void> pushCapture(Capture c) async {
    final r = await http.post(
      Uri.parse('$baseUrl/captures'),
      headers: _headers,
      body: jsonEncode(c.toJson()),
    );
    if (r.statusCode < 200 || r.statusCode >= 300) {
      throw Exception('HTTP ${r.statusCode}');
    }
  }

  @override
  Future<({Map<String, String> models, Map<String, String> orderSuppliers})>
      fetchCatalogs() async {
    final r = await http.get(Uri.parse('$baseUrl/catalogs'), headers: _headers);
    if (r.statusCode != 200) throw Exception('HTTP ${r.statusCode}');
    final j = jsonDecode(r.body) as Map<String, dynamic>;
    return (
      models: Map<String, String>.from(j['models'] ?? {}),
      orderSuppliers: Map<String, String>.from(j['orderSuppliers'] ?? {}),
    );
  }
}

/// Envía las capturas pendientes cuando hay conexión.
class SyncService {
  SyncService(this._db, {RemoteApi? api}) : _api = api;

  final AppDatabase _db;
  RemoteApi? _api; // si no es null, anula la configuración de ajustes (tests)
  StreamSubscription<List<ConnectivityResult>>? _sub;
  bool _running = false;

  /// Callback para refrescar la UI al terminar.
  void Function()? onChanged;

  void configure(RemoteApi api) => _api = api;

  void start() {
    _sub = Connectivity().onConnectivityChanged.listen((results) {
      if (!results.contains(ConnectivityResult.none)) syncNow(auto: true);
    });
    syncNow(auto: true);
  }

  void dispose() => _sub?.cancel();

  /// Modo de envío elegido en ajustes: 'none' | 'api' | 'email'.
  Future<String> syncMode() async => await _db.getSetting('sync_mode') ?? 'none';

  Future<RemoteApi?> _buildApi() async {
    if (_api != null) return _api;
    final url = (await _db.getSetting('api_base_url'))?.trim() ?? '';
    if (url.isEmpty) return null;
    final token = (await _db.getSetting('api_token'))?.trim();
    return HttpRemoteApi(
        baseUrl: url, token: (token == null || token.isEmpty) ? null : token);
  }

  /// [auto] = disparado por conectividad. El envío por email necesita que el
  /// usuario pulse "enviar" en su app de correo, así que solo se lanza a mano.
  Future<String> syncNow({bool auto = false}) async {
    final mode = _api != null ? 'api' : await syncMode();
    if (mode == 'none') {
      return 'Envío no configurado: datos guardados en el dispositivo';
    }
    if (mode == 'email') {
      if (auto) return 'Envío por email: pendiente de lanzar manualmente';
      return _syncByEmail();
    }
    final api = await _buildApi();
    if (api == null) return 'Falta la URL de la API en ajustes';
    if (_running) return 'Sincronización en curso';
    _running = true;
    try {
      final conn = await Connectivity().checkConnectivity();
      if (conn.contains(ConnectivityResult.none)) return 'Sin conexión';

      final pending = await _db.listCaptures(status: SyncStatus.pending);
      var ok = 0;
      for (final c in pending.reversed) {
        try {
          await api.pushCapture(c);
          await _db.markSynced(c.id);
          ok++;
        } catch (_) {
          break; // reintentará en la próxima conexión
        }
      }
      try {
        final cat = await api.fetchCatalogs();
        await _db.upsertCatalogs(
            models: cat.models, orderSuppliers: cat.orderSuppliers);
      } catch (_) {/* catálogos opcionales */}

      onChanged?.call();
      return 'Enviadas $ok de ${pending.length}';
    } finally {
      _running = false;
    }
  }

  /// Genera un CSV con las capturas pendientes y abre el cliente de correo
  /// con el adjunto y el destinatario configurado en ajustes.
  Future<String> _syncByEmail() async {
    final to = (await _db.getSetting('email_to'))?.trim() ?? '';
    if (to.isEmpty) return 'Falta el email de destino en ajustes';
    final pending = await _db.listCaptures(status: SyncStatus.pending);
    if (pending.isEmpty) return 'No hay capturas pendientes';

    final csv = StringBuffer('pedido,proveedor,fecha_escaneo,modelo,cantidad,origen\n');
    for (final c in pending.reversed) {
      for (final l in c.lines) {
        csv.writeln([
          c.order,
          c.supplier,
          c.scannedAt.toIso8601String(),
          l.boxModel,
          l.quantity,
          l.source.name,
        ].map(_csvCell).join(','));
      }
    }

    final dir = await getTemporaryDirectory();
    final stamp = DateTime.now().millisecondsSinceEpoch;
    final file = File('${dir.path}/capturas_$stamp.csv');
    await file.writeAsString(csv.toString());

    try {
      await FlutterEmailSender.send(Email(
        recipients: [to],
        subject: 'Capturas de cajas (${pending.length})',
        body: 'Adjunto CSV con ${pending.length} capturas pendientes.',
        attachmentPaths: [file.path],
      ));
    } catch (e) {
      return 'No se pudo abrir el cliente de correo: $e';
    }
    // La app de correo se abre con el borrador listo; se da por enviado al
    // lanzarlo. Si el usuario cancela, puede volver a generarlo desde el
    // detalle (ver README).
    for (final c in pending) {
      await _db.markSynced(c.id);
    }
    onChanged?.call();
    return 'Correo preparado con ${pending.length} capturas';
  }

  String _csvCell(Object v) {
    final s = '$v';
    return s.contains(RegExp(r'[",\n]')) ? '"${s.replaceAll('"', '""')}"' : s;
  }
}
