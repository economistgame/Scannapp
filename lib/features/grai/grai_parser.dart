/// Extrae del código escaneado el "trozo" que identifica el modelo de caja.
///
/// El trozo se define en CARACTERES sobre el texto escaneado completo:
/// [start] es la posición del primer carácter (1 = el primero) y [length]
/// cuántos caracteres se cogen. Ambos se configuran en la pantalla de ajustes.
///
/// Si el código viene con el identificador de aplicación GS1 delante
/// ("(8003)..." o "8003...") se descarta antes de contar los caracteres.
class GraiParser {
  const GraiParser({this.start = 8, this.length = 4});

  /// Posición del primer carácter del trozo (base 1).
  final int start;

  /// Número de caracteres del trozo.
  final int length;

  /// Mínimo de caracteres que debe tener el código para poder extraer el trozo.
  int get minChars => start - 1 + length;

  /// Admite "(8003)012345...", "8003012345..." o el GRAI a secas.
  String normalize(String raw) {
    var s = raw.trim().replaceAll(RegExp(r'[()\s]'), '');
    // Si trae el AI 8003 delante y hay datos suficientes, lo quitamos.
    if (s.startsWith('8003') && s.length >= 4 + 14) s = s.substring(4);
    return s;
  }

  /// Devuelve el código de modelo, o null si el código es demasiado corto o la
  /// configuración no es válida.
  String? extractModelCode(String raw) {
    if (start < 1 || length < 1) return null;
    final s = normalize(raw);
    if (s.length < minChars) return null;
    return s.substring(start - 1, start - 1 + length);
  }
}
