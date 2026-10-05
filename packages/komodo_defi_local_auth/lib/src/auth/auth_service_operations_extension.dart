part of 'auth_service.dart';

extension KdfAuthServiceOperationsExtension on KdfAuthService {
  Future<T> _runReadOperation<T>(Future<T> Function() operation) async {
    return _authMutex.protectRead(operation);
  }

  Future<T> _lockWriteOperation<T>(Future<T> Function() operation) async {
    return _authMutex.protectWrite(operation);
  }

  void _startHealthCheck() {
    _healthCheckTimer?.cancel();
    // With shutdown signal streaming in place, health checks serve primarily
    // as a backup for edge cases where the event stream might miss a shutdown.
    // Reduced from 5 minutes to 30 minutes to minimize RPC spam while
    // maintaining a safety net for detecting stale KDF instances.
    _healthCheckTimer = Timer.periodic(
      const Duration(minutes: 5),
      (_) => _checkKdfHealth(),
    );
  }

  /// Subscribes to shutdown signal events from KDF to immediately detect
  /// when KDF is shutting down, eliminating the need for frequent polling.
  ///
  /// This provides near-instant detection of KDF shutdown (< 1 second) compared
  /// to the periodic health check (up to 30 minutes delay).
  void _subscribeToShutdownSignals() {
    _shutdownSubscription?.cancel();

    // Enable shutdown signal streaming via RPC and subscribe to events
    _shutdownSubscription = _kdfFramework.streaming.shutdownSignals.listen(
      _handleShutdownSignal,
      onError: (Object error, StackTrace stackTrace) {
        _logger.warning(
          'Error in shutdown signal stream, '
          'will rely on periodic health checks',
          error,
          stackTrace,
        );
      },
      cancelOnError: false,
    );

    // Enable the shutdown signal stream on KDF
    // Note: This is fire-and-forget; if it fails, we'll rely on health checks
    _enableShutdownStream().catchError((Object error) {
      _logger.warning(
        'Failed to enable shutdown signal stream, '
        'will rely on periodic health checks: $error',
      );
    });
  }

  /// Enables the shutdown signal stream on KDF.
  Future<void> _enableShutdownStream() async {
    // TODO: Remove if/when shutdown signal stream is supported on Web
    // and Windows
    if (kIsWeb || Platform.isWindows) {
      _logger.info('Shutdown signal stream not supported on Web');
      return;
    }
    try {
      if (!await _kdfFramework.isRunning()) {
        return;
      }

      await _client.rpc.streaming.enableShutdownSignal();
      _logger.info(
        '[EVENT STREAM] Shutdown signal stream enabled successfully',
      );
    } catch (e) {
      // Log but don't throw - streaming is a nice-to-have optimization
      _logger.warning('Could not enable shutdown signal stream: $e');
    }
  }

  /// Handles shutdown signal events by immediately updating auth state.
  void _handleShutdownSignal(ShutdownSignalEvent event) {
    _logger.info(
      'Received shutdown signal (${event.signalName}), '
      'signing out user immediately',
    );

    // Immediately emit signed out state without waiting for health check
    if (_lastEmittedUser != null) {
      _emitAuthStateChange(null);
    }
  }

  Future<void> _checkKdfHealth() async {
    try {
      await _runReadOperation(() async {
        if (!await _verifyKdfHealthy().timeout(
          const Duration(seconds: 5),
          onTimeout: () => false,
        )) {
          _logger.warning('KDF health probe unavailable; preserving session');
          return;
        }
        // Only a successful wallet-names RPC can prove that authentication
        // ended. isRunning()==false can also mean a transient connection error.
        final activeWallet =
            (await _client.rpc.wallet.getWalletNames()).activatedWallet;
        if (activeWallet == null) {
          if (_lastEmittedUser != null) _emitAuthStateChange(null);
          return;
        }
        final currentUser = await _secureStorage.getUser(activeWallet);
        if (currentUser == null) {
          // KDF successfully identified an active wallet that this client does
          // not own locally. The previous wallet session is no longer valid.
          if (_lastEmittedUser != null) _emitAuthStateChange(null);
        } else if (currentUser.walletId != _lastEmittedUser?.walletId) {
          _emitAuthStateChange(currentUser);
        }
      });
    } catch (e, s) {
      // Log the error but don't immediately sign out on transient RPC failures.
      // The next health check (in 5 minutes) will verify if this is persistent.
      // This prevents false sign-outs during temporary network issues.
      _logger.warning('Health check failed, will retry on next interval', e, s);
      // Note: We intentionally do NOT emit null here to avoid false sign-outs
      // from transient errors. KDF may still be running and user authenticated.
    }
  }
}
