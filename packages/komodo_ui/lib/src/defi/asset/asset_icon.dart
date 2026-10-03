import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show AssetManifest, rootBundle;
import 'package:komodo_defi_types/komodo_defi_types.dart';

/// A widget that displays an icon for a given [AssetId].
///
/// The icon is first looked up in local assets, then a ticker badge is rendered
/// locally when the artwork is not bundled.
class AssetIcon extends StatelessWidget {
  /// Creates an [AssetIcon] widget that displays an icon for the given [AssetId].
  /// This is the preferred constructor as it provides type safety and additional
  /// metadata about the asset.
  const AssetIcon(
    this.assetId, {
    this.size = 20,
    this.suspended = false,
    this.heroTag,
    super.key,
  }) : _legacyTicker = null;

  /// Legacy constructor that accepts a ticker/abbreviation string.
  /// Provided for backwards compatibility with [CoinIcon].
  ///
  /// Consider migrating to the default constructor with [AssetId] for better
  /// type safety and asset metadata support.
  ///
  /// NB! This will likely be deprecated in the future.
  AssetIcon.ofTicker(
    String ticker, {
    this.size = 20,
    this.suspended = false,
    this.heroTag,
    super.key,
  }) : _legacyTicker = ticker.toLowerCase(),
       assetId = null;

  final AssetId? assetId;
  final String? _legacyTicker;
  final double size;
  final bool suspended;
  final Object? heroTag;

  String get _effectiveId => assetId?.id ?? _legacyTicker!;

  @override
  Widget build(BuildContext context) {
    final disabledTheme = Theme.of(context).disabledColor;
    Widget icon = SizedBox.square(
      dimension: size,
      child: _AssetIconResolver(
        key: ValueKey(_effectiveId),
        assetId: _effectiveId,
        size: size,
      ),
    );

    // Apply opacity first for disabled state
    icon = Opacity(opacity: suspended ? disabledTheme.a : 1.0, child: icon);

    // Then wrap with Hero widget if provided (Hero should be outermost)
    if (heroTag != null) {
      icon = Hero(tag: heroTag!, child: icon);
    }

    return icon;
  }

  /// Clears all caches used by [AssetIcon]
  static void clearCaches() {
    _AssetIconResolver.clearCaches();
  }

  /// Uses icons from a verified P2Pirate Assets snapshot on desktop.
  static void setRuntimeIconDirectory(String? directory) {
    _AssetIconResolver.runtimeIconDirectory = directory;
    _AssetIconResolver.clearCaches();
  }

  /// Registers a custom icon for a given coin abbreviation.
  ///
  /// The [imageProvider] will be used instead of the default asset image
  /// when displaying the icon for the specified [assetId].
  ///
  /// Example:
  /// ```dart
  /// // Register a custom icon from an asset
  /// CoinIcon.registerCustomIcon(
  ///   'MYCOIN',
  ///   AssetImage('assets/my_custom_coin.png'),
  /// );
  ///
  /// // Register a custom icon from memory
  /// CoinIcon.registerCustomIcon(
  ///   'MYCOIN',
  ///   MemoryImage(customIconBytes),
  /// );
  /// ```
  static void registerCustomIcon(AssetId assetId, ImageProvider imageProvider) {
    _AssetIconResolver.registerCustomIcon(assetId, imageProvider);
  }

  /// Pre-loads the asset icon image into the cache.
  ///
  /// This is useful when you know you'll need an icon soon and want to avoid
  /// a loading delay.
  ///
  /// Set [throwExceptions] to true if you want to handle caching errors.
  static Future<void> precacheAssetIcon(
    BuildContext context,
    AssetId asset, {
    bool throwExceptions = false,
  }) {
    return _AssetIconResolver.precacheAssetIcon(
      context,
      asset,
      throwExceptions: throwExceptions,
    );
  }

  /// Checks registered and installed P2Pirate icons directly, then consults
  /// the bundled-asset existence cache.
  ///
  /// A bundled icon that has not been loaded or pre-cached still returns
  /// `false` until its existence is recorded in `_assetExistenceCache`.
  ///
  /// To ensure an up-to-date result for bundled icons, call
  /// [precacheAssetIcon] first.
  ///
  /// Returns true if the icon is known to exist (per cache), false otherwise.
  static bool assetIconExists(String assetIconId) {
    return _AssetIconResolver.assetIconExists(assetIconId);
  }
}

/// [precacheImage] with [ImageStreamListener.onError] still completes its future
/// successfully; this type records whether loading actually succeeded.
final class _PrecacheOutcome {
  _PrecacheOutcome() : _succeeded = true;

  bool _succeeded;
  bool get succeeded => _succeeded;

  void recordFailure(Object error, StackTrace? stackTrace) {
    _succeeded = false;
  }
}

class _AssetIconResolver extends StatelessWidget {
  const _AssetIconResolver({
    required this.assetId,
    required this.size,
    super.key,
  });

  final String assetId;
  final double size;

  static const _coinImagesFolder =
      'packages/komodo_defi_framework/assets/coin_icons/png/';
  static final Map<String, bool> _assetExistenceCache = {};
  static final Map<String, ImageProvider> _customIconsCache = {};
  static Set<String>? _bundledAssetPaths;
  static Future<Set<String>>? _bundledAssetPathsLoader;
  static String? runtimeIconDirectory;
  static final Map<String, bool> _runtimeIconExists = {};

  static void registerCustomIcon(AssetId assetId, ImageProvider imageProvider) {
    final sanitizedId = assetId.symbol.configSymbol.toLowerCase();
    _customIconsCache[sanitizedId] = imageProvider;
  }

  static void clearCaches() {
    _assetExistenceCache.clear();
    _customIconsCache.clear();
    _bundledAssetPaths = null;
    _bundledAssetPathsLoader = null;
    _runtimeIconExists.clear();
  }

  String get _sanitizedId =>
      AssetSymbol.symbolFromConfigId(assetId).toLowerCase();
  String get _imagePath => '$_coinImagesFolder$_sanitizedId.png';

  File? get _runtimeIcon {
    final directory = runtimeIconDirectory;
    if (directory == null) return null;
    final file = File('$directory/$_sanitizedId.png');
    if (!(_runtimeIconExists[_sanitizedId] ??= file.existsSync())) return null;
    return file;
  }

  static Future<Set<String>> _loadBundledAssetPaths() async {
    if (_bundledAssetPaths != null) {
      return _bundledAssetPaths!;
    }

    if (_bundledAssetPathsLoader != null) {
      return _bundledAssetPathsLoader!;
    }

    _bundledAssetPathsLoader = () async {
      final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
      return manifest.listAssets().toSet();
    }();

    try {
      _bundledAssetPaths = await _bundledAssetPathsLoader;
      return _bundledAssetPaths!;
    } finally {
      _bundledAssetPathsLoader = null;
    }
  }

  static Future<bool?> _isBundledAssetDeclared(String assetPath) async {
    try {
      final bundledPaths = await _loadBundledAssetPaths();
      return bundledPaths.contains(assetPath);
    } catch (e) {
      debugPrint('Failed to load asset manifest for icon precache: $e');
      return null;
    }
  }

  static Future<bool> _didImagePrecacheSucceed(
    ImageProvider image,
    BuildContext context,
  ) async {
    final outcome = _PrecacheOutcome();
    await precacheImage(image, context, onError: outcome.recordFailure);
    return outcome.succeeded;
  }

  static Future<void> precacheAssetIcon(
    BuildContext context,
    AssetId asset, {
    bool throwExceptions = false,
  }) async {
    final resolver = _AssetIconResolver(assetId: asset.id, size: 20);
    final sanitizedId = resolver._sanitizedId;

    try {
      if (_customIconsCache.containsKey(sanitizedId)) {
        if (!context.mounted) return;

        final customSucceeded = await _didImagePrecacheSucceed(
          _customIconsCache[sanitizedId]!,
          context,
        );
        if (throwExceptions && !customSucceeded) {
          throw Exception('Failed to pre-cache custom image for coin $asset.');
        }
        return;
      }

      final runtimeIcon = resolver._runtimeIcon;
      if (runtimeIcon != null) {
        if (!context.mounted) return;
        final succeeded = await _didImagePrecacheSucceed(
          FileImage(runtimeIcon),
          context,
        );
        if (throwExceptions && !succeeded) {
          throw Exception('Failed to pre-cache P2Pirate icon for $asset.');
        }
        return;
      }

      final assetImage = AssetImage(resolver._imagePath);
      final bundledAssetExists = await _isBundledAssetDeclared(
        resolver._imagePath,
      );

      if (bundledAssetExists == true || bundledAssetExists == null) {
        if (!context.mounted) return;
        final assetSucceeded = await _didImagePrecacheSucceed(
          assetImage,
          context,
        );
        _assetExistenceCache[resolver._imagePath] = assetSucceeded;
        if (assetSucceeded) {
          return;
        }
        return;
      }

      _assetExistenceCache[resolver._imagePath] = false;
    } catch (e) {
      debugPrint('Error in precacheAssetIcon for ${asset.id}: $e');
      if (throwExceptions) rethrow;
    }
  }

  static bool assetIconExists(String assetIconId) {
    final resolver = _AssetIconResolver(assetId: assetIconId, size: 20);
    if (_customIconsCache.containsKey(resolver._sanitizedId) ||
        resolver._runtimeIcon != null) {
      return true;
    }
    return _assetExistenceCache[resolver._imagePath] ?? false;
  }

  Widget _buildFallbackIcon(BuildContext context) {
    final ticker = _sanitizedId.toUpperCase();
    final label = ticker.length > 3 ? ticker.substring(0, 3) : ticker;
    final colors = Theme.of(context).colorScheme;
    return Semantics(
      label: '$ticker coin icon',
      child: Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: colors.primary.withValues(alpha: 0.18),
          shape: BoxShape.circle,
        ),
        child: Text(
          label,
          maxLines: 1,
          style: TextStyle(
            color: colors.primary,
            fontSize: size * 0.3,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_customIconsCache.containsKey(_sanitizedId)) {
      return Image(
        image: _customIconsCache[_sanitizedId]!,
        filterQuality: FilterQuality.high,
        errorBuilder: (context, error, stackTrace) {
          debugPrint('Error loading custom icon for $assetId: $error');
          return _buildFallbackIcon(context);
        },
      );
    }

    final runtimeIcon = _runtimeIcon;
    if (runtimeIcon != null) {
      return Image.file(
        runtimeIcon,
        filterQuality: FilterQuality.high,
        errorBuilder: (context, error, stackTrace) =>
            _buildFallbackIcon(context),
      );
    }

    final bundledState = _assetExistenceCache[_imagePath];
    if (bundledState == false) {
      return _buildFallbackIcon(context);
    }

    _assetExistenceCache[_imagePath] = bundledState ?? true;
    return Image.asset(
      _imagePath,
      filterQuality: FilterQuality.high,
      errorBuilder: (context, error, stackTrace) {
        _assetExistenceCache[_imagePath] = false;
        return _buildFallbackIcon(context);
      },
    );
  }
}
