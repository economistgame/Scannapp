/// Datos leídos de un GRAI escaneado.
class GraiInfo {
  const GraiInfo({required this.ean, required this.serial});

  /// EAN del producto (13 dígitos) que va dentro del GRAI.
  final String ean;

  /// Número de serie del embalaje (puede venir vacío).
  final String serial;
}

/// Lee el GRAI (GS1 AI 8003) de una etiqueta.
///
/// Estructura: 8003 + 0 + EAN (13 dígitos) + nº de serie.
/// Ejemplo: 8003 0 8714548186004 7004946272
///   -> EAN 8714548186004, serie 7004946272.
/// El prefijo 8003 es opcional y se admite con o sin paréntesis.
class GraiParser {
  const GraiParser();

  /// Devuelve el EAN y la serie, o null si no tiene forma de GRAI
  /// (14 dígitos que empiezan por 0, tras el 8003 opcional).
  GraiInfo? parse(String raw) {
    var s = raw;
    // Si detrás del GRAI vienen otros datos GS1, los separa el carácter FNC1.
    final gs = s.indexOf('\u001d');
    if (gs >= 0) s = s.substring(0, gs);
    s = s.trim().replaceAll(RegExp(r'[()\s]'), '');
    if (s.startsWith('8003')) s = s.substring(4);
    if (!RegExp(r'^0\d{13}').hasMatch(s)) return null;
    return GraiInfo(ean: s.substring(1, 14), serial: s.substring(14));
  }
}

/// Comprueba que es un EAN/GTIN válido: 8, 12, 13 o 14 dígitos y dígito de
/// control GS1 correcto.
bool isValidEan(String code) {
  if (!RegExp(r'^\d+$').hasMatch(code)) return false;
  if (![8, 12, 13, 14].contains(code.length)) return false;
  var sum = 0;
  var weight = 3;
  for (var i = code.length - 2; i >= 0; i--) {
    sum += int.parse(code[i]) * weight;
    weight = 4 - weight; // alterna 3, 1, 3, 1...
  }
  return (10 - sum % 10) % 10 == int.parse(code[code.length - 1]);
}
