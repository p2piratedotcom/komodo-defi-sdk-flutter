import 'package:komodo_defi_framework/komodo_defi_framework.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:test/test.dart';

void main() {
  test('P2Pirate startup JSON explicitly contains netid 8762', () async {
    final config = await KdfStartupConfig.generateWithDefaults(
      walletName: 'test-wallet',
      walletPassword: 'test-password',
      enableHd: false,
      coinsPath: '/tmp/coins.json',
      userHome: '/tmp',
      dbDir: '/tmp/pirate-kdf-test',
      disableP2p: true,
    );

    expect(kPirateKdfNetId, 8762);
    expect(config.encodeStartParams()['netid'], 8762);
  });

  test('a different KDF netid is rejected', () async {
    await expectLater(
      KdfStartupConfig.generateWithDefaults(
        walletName: 'test-wallet',
        walletPassword: 'test-password',
        enableHd: false,
        coinsPath: '/tmp/coins.json',
        userHome: '/tmp',
        dbDir: '/tmp/pirate-kdf-test',
        disableP2p: true,
        netid: 6133,
      ),
      throwsArgumentError,
    );
  });
}
