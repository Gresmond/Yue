import 'dart:io';

import 'package:flutter/services.dart';

const _phone = MethodChannel('yue/phone');

/// Opens a URL with the operating system's default application.
Future<void> openExternal(String target) async {
  if (Platform.isAndroid) {
    await _phone.invokeMethod<void>('openUrl', target);
  } else if (Platform.isWindows) {
    await Process.start('explorer.exe', [target], mode: ProcessStartMode.detached);
  } else {
    await Process.run(Platform.isMacOS ? 'open' : 'xdg-open', [target]);
  }
}

/// Back from the browser once a sign-in has come through, on a phone.
Future<void> bringToFront() async {
  if (Platform.isAndroid) await _phone.invokeMethod<void>('toFront');
}
