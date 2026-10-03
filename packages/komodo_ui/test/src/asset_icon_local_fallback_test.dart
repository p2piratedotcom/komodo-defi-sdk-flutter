import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:komodo_ui/src/defi/asset/asset_icon.dart';

void main() {
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
