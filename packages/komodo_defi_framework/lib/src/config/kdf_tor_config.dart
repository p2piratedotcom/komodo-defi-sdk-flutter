class KdfTorConfig {
  KdfTorConfig._();

  static bool enabled = false;
  static int? socksPort;
  static String? torsocksLibraryPath;
  static String? torsocksConfigPath;

  static void configure({
    required int port,
    required String libraryPath,
    required String configPath,
  }) {
    if (port < 1 || port > 65535) {
      throw ArgumentError.value(port, 'port');
    }
    socksPort = port;
    torsocksLibraryPath = libraryPath;
    torsocksConfigPath = configPath;
    enabled = true;
  }

  static void disable() {
    enabled = false;
    socksPort = null;
    torsocksLibraryPath = null;
    torsocksConfigPath = null;
  }

  static void ensureConfigured() {
    if (!enabled ||
        socksPort == null ||
        torsocksLibraryPath == null ||
        torsocksConfigPath == null) {
      throw StateError('KDF Tor mode is not fully configured');
    }
  }
}
