import 'dart:io';

import 'package:flutter/painting.dart';

/// Resolve only a ticker filename inside the verified desktop icon directory.
ImageProvider? runtimeAssetIcon(String directory, String ticker) {
  if (!RegExp(r'^[a-z0-9_]+$').hasMatch(ticker)) return null;
  final file = File('$directory/$ticker.png');
  return file.existsSync() ? FileImage(file) : null;
}
