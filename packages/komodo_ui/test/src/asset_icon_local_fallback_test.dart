import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:komodo_ui/src/defi/asset/asset_icon.dart';
import 'package:komodo_ui/src/defi/asset/runtime_asset_icon_stub.dart'
    as web_icons;

void main() {
  tearDown(() {
    AssetIcon.setRuntimeIconDirectory(null);
    AssetIcon.clearCaches();
  });

  test('web resolver leaves filesystem paths to the local badge fallback', () {
    expect(web_icons.runtimeAssetIcon('/desktop/only', 'arrr'), isNull);
  });

  test('selecting or clearing a snapshot preserves custom registrations', () {
    final asset = AssetId(
      id: 'BTC',
      name: 'Bitcoin',
      symbol: AssetSymbol(assetConfigId: 'BTC'),
      chainId: AssetChainId(chainId: 0, decimalsValue: 8),
      derivationPath: null,
      subClass: CoinSubClass.utxo,
    );
    AssetIcon.registerCustomIcon(asset, MemoryImage(Uint8List(0)));
    AssetIcon.setRuntimeIconDirectory('/missing-snapshot');
    expect(AssetIcon.assetIconExists('BTC'), isTrue);
    AssetIcon.setRuntimeIconDirectory(null);
    expect(AssetIcon.assetIconExists('BTC'), isTrue);
  });

  testWidgets('missing artwork renders a local ticker badge', (tester) async {
    AssetIcon.clearCaches();
    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: AssetIcon.ofTicker('ARRR', size: 32))),
    );
    await tester.pumpAndSettle();

    expect(find.text('ARR'), findsOneWidget);
    expect(
      tester
          .widgetList<Image>(find.byType(Image))
          .every((image) => image.image is! NetworkImage),
      isTrue,
    );
  });
}
