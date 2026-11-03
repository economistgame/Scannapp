/// Extrae el "trozo" del GRAI que identifica el modelo de caja.
///
/// El GRAI (GS1 AI 8003) tiene la forma: 0 + prefijo de empresa + tipo de
/// activo + dígito de control (14 dígitos) + número de serie opcional.
/// Como la longitud del prefijo varía según la empresa, la posición del
/// trozo que identifica el modelo es CONFIGURABLE (start/length, base 0,
/// sobre los 14 dígitos del GRAI).
class GraiParser {
  const GraiParser({this.start = 7, this.length = 4});

  final int start;
  final int length;

  /// Admite "(8003)012345..." , "8003012345..." o el GRAI a secas.
  String normalize(String raw) {
    var s = raw.trim().replaceAll(RegExp(r'[()\s]'), '');
    // Si trae el AI 8003 delante y hay datos suficientes, lo quitamos.
    if (s.startsWith('8003') && s.length >= 4 + 14) s = s.substring(4);
    return s;
  }

  /// Devuelve el código de modelo, o null si el código no es válido.
  String? extractModelCode(String raw) {
    final grai = normalize(raw);
    if (grai.length < 14 || !RegExp(r'^\d{14}').hasMatch(grai)) return null;
    if (start + length > 14) return null;
    return grai.substring(start, start + length);
  }
}
