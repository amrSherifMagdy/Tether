import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:image/image.dart' as img;

/// Direct Win32 calls through dart:ffi: no PowerShell, no process start, no compile step.
/// Only fixed functions are called, and remote data reaches them only as numbers or typed text.
typedef _I1 = int Function(int);
typedef _N1 = Int32 Function(Int32);

class Native {
  Native._() {
    final u = DynamicLibrary.open('user32.dll');
    getSystemMetrics = u.lookupFunction<_N1, _I1>('GetSystemMetrics');
    setCursorPos = u
        .lookupFunction<Int32 Function(Int32, Int32), int Function(int, int)>(
          'SetCursorPos',
        );
    mouseEvent = u
        .lookupFunction<
          Void Function(Uint32, Uint32, Uint32, Uint32, IntPtr),
          void Function(int, int, int, int, int)
        >('mouse_event');
    keybdEvent = u
        .lookupFunction<
          Void Function(Uint8, Uint8, Uint32, IntPtr),
          void Function(int, int, int, int)
        >('keybd_event');
    sendInput = u
        .lookupFunction<
          Uint32 Function(Uint32, Pointer<Uint8>, Int32),
          int Function(int, Pointer<Uint8>, int)
        >('SendInput');
    getAsyncKeyState = u
        .lookupFunction<Int16 Function(Int32), int Function(int)>(
          'GetAsyncKeyState',
        );
    try {
      messageBeep = u
          .lookupFunction<Int32 Function(Uint32), int Function(int)>('MessageBeep');
    } catch (_) {}
    try {
      u.lookupFunction<Int32 Function(), int Function()>(
        'SetProcessDPIAware',
      )();
    } catch (_) {}
  }

  static final Native i = Native._();

  int Function(int)? messageBeep;
  late final int Function(int) getSystemMetrics;
  late final int Function(int, int) setCursorPos;
  late final void Function(int, int, int, int, int) mouseEvent;
  late final void Function(int, int, int, int) keybdEvent;
  late final int Function(int, Pointer<Uint8>, int) sendInput;
  late final int Function(int) getAsyncKeyState;

  int get screenW => getSystemMetrics(0);
  int get screenH => getSystemMetrics(1);

  int _clamp(int v, int lo, int hi) => v < lo ? lo : (v > hi ? hi : v);

  void moveTo(int x, int y) {
    if (setCursorPos(_clamp(x, 0, screenW - 1), _clamp(y, 0, screenH - 1)) ==
        0) {
      throw StateError('SetCursorPos failed');
    }
  }

  Future<void> click(int x, int y, bool right, int count) async {
    moveTo(x, y);
    final d = right ? 0x8 : 0x2, u = right ? 0x10 : 0x4;
    for (var k = 0; k < _clamp(count, 1, 2); k++) {
      mouseEvent(d, 0, 0, 0, 0);
      await Future.delayed(const Duration(milliseconds: 25));
      mouseEvent(u, 0, 0, 0, 0);
      await Future.delayed(const Duration(milliseconds: 40));
    }
  }

  Future<void> scroll(int x, int y, int dy) async {
    moveTo(x, y);
    final n = _clamp(dy, -50, 50);
    final delta = (n > 0 ? -120 : 120) & 0xFFFFFFFF;
    for (var k = 0; k < n.abs(); k++) {
      mouseEvent(0x800, 0, 0, delta, 0);
      await Future.delayed(const Duration(milliseconds: 15));
    }
  }

  void _typeUnit(int ch) {
    final p = calloc<Uint8>(80);
    try {
      final b = ByteData.view(
        p.asTypedList(80).buffer,
        p.asTypedList(80).offsetInBytes,
        80,
      );
      for (var k = 0; k < 2; k++) {
        final o = k * 40;
        b.setUint32(o, 1, Endian.little); // INPUT_KEYBOARD
        b.setUint16(o + 8, 0, Endian.little); // wVk
        b.setUint16(o + 10, ch, Endian.little); // wScan = UTF-16 unit
        b.setUint32(
          o + 12,
          k == 0 ? 0x4 : 0x6,
          Endian.little,
        ); // UNICODE (+KEYUP)
      }
      final n = sendInput(2, p, 40);
      if (n != 2) throw StateError('SendInput failed');
    } finally {
      calloc.free(p);
    }
  }

  Future<void> typeText(String text) async {
    for (final ch in text.codeUnits) {
      if (ch == 10) {
        keybdEvent(0x0D, 0, 0, 0);
        keybdEvent(0x0D, 0, 2, 0);
      } else if (ch != 13) {
        _typeUnit(ch);
      }
      await Future.delayed(const Duration(milliseconds: 4));
    }
  }

  Future<void> keys(List<List<int>> list) async {
    for (final k in list) {
      keybdEvent(k[0], 0, k[1] == 1 ? 1 : 0, 0);
      await Future.delayed(const Duration(milliseconds: 15));
    }
    for (final k in list.reversed) {
      keybdEvent(k[0], 0, k[1] == 1 ? 3 : 2, 0);
      await Future.delayed(const Duration(milliseconds: 15));
    }
  }

  /// Short system sound (used when the laptop asks a question).
  void beep() {
    try {
      messageBeep?.call(0x30);
    } catch (_) {}
  }

  /// True while this one key is physically held (used for the approval keys).
  bool keyDown(int vk) => (getAsyncKeyState(vk) & 0x8000) != 0;

  /// Ctrl + Alt + Shift + S held together.
  bool hotkeyDown() {
    for (final k in const [0x11, 0x12, 0x10, 0x53]) {
      if ((getAsyncKeyState(k) & 0x8000) == 0) return false;
    }
    return true;
  }
}

/// Runs in a background isolate so the UI never stalls. Returns base64 JPEG and sizes.
Future<Map<String, dynamic>> captureNative(int maxW, int quality) {
  return Isolate.run(() => _capture(maxW, quality));
}

Map<String, dynamic> _capture(int maxW, int quality) {
  final u = DynamicLibrary.open('user32.dll');
  final g = DynamicLibrary.open('gdi32.dll');
  final metrics = u.lookupFunction<_N1, _I1>('GetSystemMetrics');
  final getDC = u.lookupFunction<IntPtr Function(IntPtr), int Function(int)>(
    'GetDC',
  );
  final releaseDC = u
      .lookupFunction<Int32 Function(IntPtr, IntPtr), int Function(int, int)>(
        'ReleaseDC',
      );
  final getCursorPos = u
      .lookupFunction<
        Int32 Function(Pointer<Int32>),
        int Function(Pointer<Int32>)
      >('GetCursorPos');
  final createDC = g.lookupFunction<IntPtr Function(IntPtr), int Function(int)>(
    'CreateCompatibleDC',
  );
  final createBmp = g
      .lookupFunction<
        IntPtr Function(IntPtr, Int32, Int32),
        int Function(int, int, int)
      >('CreateCompatibleBitmap');
  final selectObj = g
      .lookupFunction<IntPtr Function(IntPtr, IntPtr), int Function(int, int)>(
        'SelectObject',
      );
  final setMode = g
      .lookupFunction<Int32 Function(IntPtr, Int32), int Function(int, int)>(
        'SetStretchBltMode',
      );
  final stretch = g
      .lookupFunction<
        Int32 Function(
          IntPtr,
          Int32,
          Int32,
          Int32,
          Int32,
          IntPtr,
          Int32,
          Int32,
          Int32,
          Int32,
          Uint32,
        ),
        int Function(int, int, int, int, int, int, int, int, int, int, int)
      >('StretchBlt');
  final getDIBits = g
      .lookupFunction<
        Int32 Function(
          IntPtr,
          IntPtr,
          Uint32,
          Uint32,
          Pointer<Uint8>,
          Pointer<Uint8>,
          Uint32,
        ),
        int Function(int, int, int, int, Pointer<Uint8>, Pointer<Uint8>, int)
      >('GetDIBits');
  final deleteObj = g.lookupFunction<Int32 Function(IntPtr), int Function(int)>(
    'DeleteObject',
  );
  final deleteDC = g.lookupFunction<Int32 Function(IntPtr), int Function(int)>(
    'DeleteDC',
  );
  try {
    u.lookupFunction<Int32 Function(), int Function()>('SetProcessDPIAware')();
  } catch (_) {}

  final w = metrics(0), h = metrics(1);
  final scale = w > maxW ? maxW / w : 1.0;
  final tw = (w * scale).round(), th = (h * scale).round();

  final screen = getDC(0);
  if (screen == 0) throw StateError('GetDC failed');
  final mem = createDC(screen);
  final bmp = createBmp(screen, tw, th);
  if (mem == 0 || bmp == 0) throw StateError('could not create capture bitmap');
  final old = selectObj(mem, bmp);
  setMode(mem, 4); // HALFTONE
  final ok = stretch(
    mem,
    0,
    0,
    tw,
    th,
    screen,
    0,
    0,
    w,
    h,
    0x40CC0020,
  ); // SRCCOPY | CAPTUREBLT
  selectObj(mem, old);
  if (ok == 0) throw StateError('StretchBlt failed');

  final bmi = calloc<Uint8>(48);
  final bits = calloc<Uint8>(tw * th * 4);
  final pt = calloc<Int32>(2);
  try {
    final bl = bmi.asTypedList(48);
    final bd = ByteData.view(bl.buffer, bl.offsetInBytes, 48);
    bd.setUint32(0, 40, Endian.little);
    bd.setInt32(4, tw, Endian.little);
    bd.setInt32(8, -th, Endian.little); // top-down
    bd.setUint16(12, 1, Endian.little);
    bd.setUint16(14, 32, Endian.little);
    final lines = getDIBits(mem, bmp, 0, th, bits, bmi, 0);
    if (lines == 0) throw StateError('GetDIBits failed');
    final px = Uint8List.fromList(bits.asTypedList(tw * th * 4));
    for (var k = 3; k < px.length; k += 4) {
      px[k] = 255;
    }
    final image = img.Image.fromBytes(
      width: tw,
      height: th,
      bytes: px.buffer,
      numChannels: 4,
      order: img.ChannelOrder.bgra,
    );
    if (getCursorPos(pt) != 0) {
      final cx = (pt[0] * scale).round(), cy = (pt[1] * scale).round();
      img.drawCircle(
        image,
        x: cx,
        y: cy,
        radius: 8,
        color: img.ColorRgb8(255, 0, 0),
      );
      img.drawCircle(
        image,
        x: cx,
        y: cy,
        radius: 7,
        color: img.ColorRgb8(255, 0, 0),
      );
    }
    final jpg = img.encodeJpg(image, quality: quality);
    return {
      'b64': base64Encode(jpg),
      'width': tw,
      'height': th,
      'scale': scale,
      'screenW': w,
      'screenH': h,
    };
  } finally {
    calloc.free(bmi);
    calloc.free(bits);
    calloc.free(pt);
    deleteObj(bmp);
    deleteDC(mem);
    releaseDC(0, screen);
  }
}

bool get nativeSupported => Platform.isWindows;

/// Title of the window that has the keyboard focus (empty when unknown). Read-only.
String foregroundWindowTitle() {
  try {
    final u = DynamicLibrary.open('user32.dll');
    final gfw = u.lookupFunction<IntPtr Function(), int Function()>(
      'GetForegroundWindow',
    );
    final gwt = u
        .lookupFunction<
          Int32 Function(IntPtr, Pointer<Utf16>, Int32),
          int Function(int, Pointer<Utf16>, int)
        >('GetWindowTextW');
    final h = gfw();
    if (h == 0) return '';
    final buf = calloc<Uint16>(256).cast<Utf16>();
    try {
      final n = gwt(h, buf, 256);
      return n > 0 ? buf.toDartString(length: n) : '';
    } finally {
      calloc.free(buf);
    }
  } catch (_) {
    return '';
  }
}
