import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:path/path.dart' as p;
import 'package:win32/win32.dart';

import 'app_logger.dart';

/// חילוץ אייקון מקובץ הרצה: מחזיר נתיב ל-PNG זמני, או `null`. הקונטרולר
/// מחזיק אחד כזה כדי שבדיקות לא יחלצו אייקון אמיתי.
typedef ExeIconExtraction = Future<String?> Function(String exePath);

/// כותב את האייקון של קובץ הרצה ל-PNG ומחזיר אם הצליח. תפר לבדיקות.
typedef IconPngWriter = Future<bool> Function(String exePath, String outPath);

/// חילוץ האייקון של קובץ הרצה לקובץ PNG.
///
/// **למה בכלל:** הרשומה של תוכנה נוספת נוצרת במחשב המקוון, שבו התוכנה
/// בדרך כלל אינה מותקנת — אבל קובץ ההתקנה כן שם, ומתקין של Inno או NSIS
/// נושא כמעט תמיד את האייקון של התוכנה עצמה.
///
/// ווינדוס בלבד: `PrivateExtractIcons` (256×256) עם נפילה ל-
/// `ExtractAssociatedIcon` (32×32), וקידוד ל-PNG — הכול ב-isolate.
abstract final class ExeIconExtractor {
  static bool get isSupported => Platform.isWindows;

  /// מחלץ את האייקון של [exePath] לקובץ PNG **זמני** ומחזיר את נתיבו, או
  /// `null` כשאין אייקון או שהחילוץ נכשל.
  static Future<String?> extract(
    String exePath, {
    IconPngWriter? writer,
  }) async {
    if (!isSupported) return null;
    if (!await File(exePath).exists()) return null;

    final dir = await Directory.systemTemp.createTemp('otzaria_icon_');
    final out = p.join(dir.path, 'icon.png');
    try {
      final written = await (writer ?? _writeInIsolate)(exePath, out);
      final file = File(out);
      if (!written || !await file.exists()) return null;
      if (await file.length() == 0) return null;
      return out;
    } catch (e) {
      AppLogger.instance.warn('חילוץ האייקון מ-$exePath נכשל: $e');
      return null;
    }
  }

  static Future<bool> _writeInIsolate(String exePath, String outPath) =>
      Isolate.run(() => writeExeIconPng(exePath, outPath));
}

/// Synchronous GDI work; run it inside an isolate.
bool writeExeIconPng(String exePath, String outPath) {
  final icon = _loadIcon(exePath);
  if (icon == 0) return false;
  try {
    final image = _iconPixels(icon);
    if (image == null) return false;
    File(outPath).writeAsBytesSync(
      encodeRgbaPng(image.width, image.height, image.rgba),
    );
    return true;
  } finally {
    DestroyIcon(icon);
  }
}

int _loadIcon(String exePath) {
  final file = exePath.toNativeUtf16();
  final handle = calloc<IntPtr>();
  final id = calloc<Uint32>();
  final path = calloc<Uint16>(MAX_PATH + 1);
  final index = calloc<Uint16>();
  try {
    final count = PrivateExtractIcons(file, 0, 256, 256, handle, id, 1, 0);
    if (count > 0 && count != 0xFFFFFFFF && handle.value != 0) {
      return handle.value;
    }
    if (exePath.length > MAX_PATH) return 0;
    for (var i = 0; i < exePath.length; i++) {
      path[i] = exePath.codeUnitAt(i);
    }
    path[exePath.length] = 0;
    return ExtractAssociatedIcon(0, path.cast<Utf16>(), index);
  } finally {
    free(file);
    free(handle);
    free(id);
    free(path);
    free(index);
  }
}

typedef _Pixels = ({int width, int height, Uint8List rgba});

_Pixels? _iconPixels(int icon) {
  final info = calloc<ICONINFO>();
  final bitmap = calloc<BITMAP>();
  final header = calloc<BITMAPINFO>();
  final screen = GetDC(NULL);
  try {
    if (GetIconInfo(icon, info) == 0) return null;
    final color = info.ref.hbmColor;
    final mask = info.ref.hbmMask;
    try {
      if (color == 0 ||
          GetObject(color, sizeOf<BITMAP>(), bitmap) == 0 ||
          bitmap.ref.bmWidth <= 0 ||
          bitmap.ref.bmHeight <= 0) {
        return null;
      }
      final width = bitmap.ref.bmWidth;
      final height = bitmap.ref.bmHeight;
      final bgra = _readBits(screen, color, header, width, height);
      if (bgra == null) return null;
      final andMask =
          mask == 0 ? null : _readBits(screen, mask, header, width, height);
      return (
        width: width,
        height: height,
        rgba: bgraToRgba(bgra, andMask),
      );
    } finally {
      if (color != 0) DeleteObject(color);
      if (mask != 0) DeleteObject(mask);
    }
  } finally {
    ReleaseDC(NULL, screen);
    free(info);
    free(bitmap);
    free(header);
  }
}

Uint8List? _readBits(
  int dc,
  int bitmap,
  Pointer<BITMAPINFO> header,
  int width,
  int height,
) {
  final bytes = width * height * 4;
  final buffer = calloc<Uint8>(bytes);
  try {
    header.ref.bmiHeader
      ..biSize = sizeOf<BITMAPINFOHEADER>()
      ..biWidth = width
      ..biHeight = -height
      ..biPlanes = 1
      ..biBitCount = 32
      ..biCompression = BI_RGB;
    final lines =
        GetDIBits(dc, bitmap, 0, height, buffer, header, DIB_RGB_COLORS);
    if (lines != height) return null;
    return Uint8List.fromList(buffer.asTypedList(bytes));
  } finally {
    free(buffer);
  }
}

/// 32bpp BGRA from GDI to RGBA. An icon without alpha takes its
/// transparency from the AND mask, as `Icon.ToBitmap` does.
Uint8List bgraToRgba(Uint8List bgra, Uint8List? andMask) {
  var hasAlpha = false;
  for (var i = 3; i < bgra.length; i += 4) {
    if (bgra[i] != 0) {
      hasAlpha = true;
      break;
    }
  }
  final rgba = Uint8List(bgra.length);
  for (var i = 0; i < bgra.length; i += 4) {
    rgba[i] = bgra[i + 2];
    rgba[i + 1] = bgra[i + 1];
    rgba[i + 2] = bgra[i];
    rgba[i + 3] = hasAlpha
        ? bgra[i + 3]
        : andMask != null && andMask[i] != 0
            ? 0
            : 255;
  }
  return rgba;
}

/// A minimal truecolour+alpha PNG (filter 0, zlib).
Uint8List encodeRgbaPng(int width, int height, Uint8List rgba) {
  final raw = BytesBuilder(copy: false);
  final stride = width * 4;
  for (var y = 0; y < height; y++) {
    raw
      ..addByte(0)
      ..add(Uint8List.sublistView(rgba, y * stride, (y + 1) * stride));
  }
  final header = ByteData(13)
    ..setUint32(0, width)
    ..setUint32(4, height)
    ..setUint8(8, 8)
    ..setUint8(9, 6);
  final out = BytesBuilder(copy: false)
    ..add(const [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]);
  void chunk(String type, List<int> data) {
    final typed = Uint8List.fromList([...type.codeUnits, ...data]);
    out
      ..add((ByteData(4)..setUint32(0, data.length)).buffer.asUint8List())
      ..add(typed)
      ..add((ByteData(4)..setUint32(0, _crc32(typed))).buffer.asUint8List());
  }

  chunk('IHDR', header.buffer.asUint8List());
  chunk('IDAT', ZLibCodec().encode(raw.takeBytes()));
  chunk('IEND', const []);
  return out.takeBytes();
}

final Uint32List _crcTable = () {
  final table = Uint32List(256);
  for (var n = 0; n < 256; n++) {
    var c = n;
    for (var k = 0; k < 8; k++) {
      c = c & 1 != 0 ? 0xEDB88320 ^ (c >> 1) : c >> 1;
    }
    table[n] = c;
  }
  return table;
}();

int _crc32(List<int> bytes) {
  var crc = 0xFFFFFFFF;
  for (final b in bytes) {
    crc = _crcTable[(crc ^ b) & 0xFF] ^ (crc >> 8);
  }
  return crc ^ 0xFFFFFFFF;
}
