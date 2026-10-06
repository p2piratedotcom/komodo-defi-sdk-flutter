# Flutter SDK: AI and contributor project guide

Read [AGENTS.md](../AGENTS.md) first. Fact-checked on 2026-10-06 against the source
revision listed there. Upstream SDK platform examples are not the acceptance
matrix of the P2Pirate application.

## Purpose and boundaries

This is the P2Pirate fork of the Komodo DeFi Flutter SDK workspace. It provides
Dart/Flutter clients and types around an external KDF runtime. It is **not** the
Rust KDF project, the wallet's screens, or the CEX market-maker risk engine.

[Wallet](https://github.com/p2piratedotcom/P2Pirate-ALPHA/blob/cheetahdex/AGENTS.md)
consumes an exact SDK Git submodule commit; its gitlink need not equal this default
branch. [MM_Engine](https://github.com/p2piratedotcom/MM_Engine/blob/main/AGENTS.md)
attaches to that wallet's KDF and owns trading strategy/coverage. Downloadable
[Spot plugins](https://github.com/p2piratedotcom/CEX_configs/blob/main/AGENTS.md)
are separate from `komodo_cex_market_data`, which supplies informational prices.
[Assets](https://github.com/p2piratedotcom/Assets/blob/main/AGENTS.md) supplies the
wallet's user-approved configuration/artwork snapshot.

## Package map

| Package | Role |
| --- | --- |
| `packages/komodo_defi_sdk/` | High-level orchestration: auth, activation, balances, history, withdrawals |
| `packages/komodo_defi_framework/` | Host config, API client, backend/process lifecycle, streaming events |
| `packages/komodo_defi_local_auth/` | Local authentication/encrypted wallet handling |
| `packages/komodo_defi_rpc_methods/` | Typed KDF RPC requests/responses and namespaces |
| `packages/komodo_defi_types/` | Shared asset/wallet/balance and domain types |
| `packages/komodo_coins/`, `packages/komodo_coin_updates/` | Coin parsing/catalog utilities and update infrastructure |
| `packages/komodo_cex_market_data/` | Market-price repositories/providers; not CEX trading permission |
| `packages/komodo_ui/`, `packages/dragon_charts_flutter/` | Reusable UI/artwork/chart widgets |
| `packages/dragon_logs/` | Logging infrastructure; never permission to emit secrets |
| `packages/komodo_wallet_build_transformer/` | Build-time artifact/assets steps |
| `playground/`, `products/`, package examples | Reference consumers with their own requirements |

Public API starts at `packages/komodo_defi_sdk/lib/komodo_defi_sdk.dart` and
implementation at `lib/src/komodo_defi_sdk.dart` within that package. Prefer
public managers rather than app-specific raw RPC calls. Changes spanning a domain
type, RPC namespace and manager should update the compatible layers together.

## Lifecycle and data flow

A consumer selects local/remote host configuration and initializes the SDK.
Framework operations provide local executable/native/WASM or remote backends;
inspect `packages/komodo_defi_framework/lib/src/operations/` and its factory for
which path the target actually selects. Auth establishes a wallet session;
activation and balance/history managers then produce account-scoped state and
streams. A withdrawal/DEX mutation is an explicit operation, not an initialization
side effect to exercise casually.

For P2Pirate Linux, the separately installed executable is selected by
`native/kdf_executable_finder.dart` under the framework package. An absolute
`P2PIRATE_KDF_PATH` is an explicit external path; standard external install
locations are checked, and legacy bundled Linux locations are excluded. Finding
an executable alone does not verify the wallet's pinned-release checksum; that
installer/trust policy belongs to the consuming wallet.

`operations/kdf_operations_local_executable.dart` tracks child ownership and exit
identity. It distinguishes no RPC from confirmed termination and retains ownership
when shutdown is uncertain. Auth/startup recovery is coordinated with write locks;
health probes must not restart an authenticated wallet in no-auth mode or let late
cleanup clear a replacement process. Null/delayed version responses are unhealthy
RPC observations, not proof of logout. Remote/no-child adapters have a different
ownership boundary.

Relevant adjacent files:

- `packages/komodo_defi_framework/lib/src/startup_config_manager.dart`
- `packages/komodo_defi_framework/lib/src/config/kdf_startup_config.dart`
- `packages/komodo_defi_framework/lib/src/config/kdf_tor_config.dart`
- `packages/komodo_defi_framework/lib/src/services/tor_seed_resolver.dart`
- `packages/komodo_defi_framework/lib/src/streaming/`
- `packages/komodo_defi_sdk/lib/src/auth/`
- `packages/komodo_defi_sdk/lib/src/activation/` and `src/activations/` in that package
- `packages/komodo_defi_sdk/lib/src/balances/balance_manager.dart`
- `packages/komodo_defi_sdk/lib/src/withdrawals/withdrawal_manager.dart`

## IDs, balances, routing and catalog rules

KDF config IDs can carry case-sensitive chain suffixes. A ticker, `AssetId`, KDF
config ID and exchange canonical symbol are not interchangeable. Preserve
explicit mappings and network identity rather than stripping suffixes globally.
P2Pirate uses the configured NetID 8762; startup validation rejects conflicting
network configuration rather than silently selecting another P2P group.

A balance may be unknown/activating/unavailable; it is not necessarily zero.
Spendable, locked/unspendable and total values have distinct meanings. Stream
subscriptions, cached data and pending async results must stay scoped to their
wallet/asset. Do not leak old-session values or authorize spending from a UI cache.

Tor configuration is supplied by the wallet. Seed resolution must not perform a
local/direct DNS fallback when Tor is selected. Local loopback RPC remains local.
The SDK does not decide to disable the wallet's privacy route on a timeout.

P2Pirate owns consent and snapshot verification for catalog/artwork downloads.
Automatic build/runtime replacement of that catalog is disabled in the relevant
fork paths. Icon selection checks custom overrides first, then verified runtime
PNGs, bundled images, and a local badge when missing. Preserve offline fallback
and licensing boundaries; do not introduce arbitrary image/network fetches in
widget build methods. See [P2Pirate coin assets](P2PIRATE_COIN_ASSETS.md).

## Workspace setup and focused validation

The root `pubspec.yaml` declares a Dart workspace and Melos scripts; at review its
Dart constraint is >=3.9.0 <4.0.0. Individual packages/examples and the consuming
wallet can require a newer Flutter/Dart version. Inspect those manifests before
selecting a toolchain. The SDK workspace does not commit a root `pubspec.lock`.
Do not pretend `--enforce-lockfile` can validate an absent workspace lockfile.

Representative source setup (not a live-wallet launch):

```sh
flutter pub get
```

For approved package code work, scope formatting/analysis and tests to affected
packages and their dependants, using fixture transports/dummy credentials:

```sh
# From the relevant package directory, with workspace dependencies resolved:
flutter analyze --no-fatal-infos
flutter test
```

Workspace preparation/code generation is declared under `melos.scripts` in the
root manifest: `dart run melos run prepare` dispatches the index/build-runner
scripts. It rewrites generated outputs and is not necessary for documentation.
Do not run major upgrades, publish packages or generate an entire workspace just
to fix a description. Existing generated models/indexes are not hand-maintained
alternatives to their annotated source.

### CI caveat

Read `.github/workflows/flutter-tests.yml` before assuming a check ran. At review
its automatic push filter is `main`, and its pull-request base filters include
`main`, `dev`, `feat/**`, `bugfix/**`, `hotfix/**`, **not** the fork's default
`cheetahdex`. A PR into this fork default can therefore have no package-test job.
The workflow has explicit package/regex dispatch inputs and discovers packages
with `test/`; missing/skipped checks do not mean the workspace was tested. Its
pinned Flutter version and upstream web/example asset step can differ from the
wallet toolchain. Treat workflow repair or a broader validation run as its own
scoped work; do not publish a fictitious all-platform/funded acceptance claim.

## Compatibility and limitations

The upstream SDK includes multiple platform backends and example products.
P2Pirate's exercised deployment path is separate Linux KDF; macOS, Windows,
mobile/Web behavior needs corresponding host/runtime evidence. A package unit
suite does not certify every blockchain, network endpoint, GPU or signing backend.

A manager interface change may require RPC model/type changes, migrations,
consumer changes and a wallet gitlink update. The SDK source pin never identifies
the external KDF binary's provenance. Do not attribute local source edits to an
already-running KDF or packaged wallet.

Never collect an operator's wallet recovery phrase, RPC password, CEX key or
process environment to reproduce a bug. Use disposable fixtures, preserve encrypted
storage/Secret Service scope, sanitize logs, and distinguish an unavailable RPC
from a confirmed session exit. Never replace unknown withdrawal outcomes with a
retry. KDF remains the final transaction/protocol authority.

## Further reading

- [Framework README](../packages/komodo_defi_framework/README.md)
- [SDK README](../packages/komodo_defi_sdk/README.md)
- [Domain types](../packages/komodo_defi_types/README.md)
- [RPC methods](../packages/komodo_defi_rpc_methods/README.md)
- [Build transformer](../packages/komodo_wallet_build_transformer/README.md)
- [Coin asset policy](P2PIRATE_COIN_ASSETS.md)
- Workspace/package manifests and actual CI workflows take precedence over old setup examples.

## A safe starting prompt for an AI contributor

```text
Read AGENTS.md and docs/AI_PROJECT_GUIDE.md at this checkout's revision.
My task is: [describe the requested change].
Identify the component boundary, relevant source/contracts, current limitations,
validation appropriate to this scope, and whether these guides need updating.
Use disposable fixtures; do not start a real wallet/service or submit funded
operations without the operator's explicit authorization.
Report facts separately from assumptions and checks performed from checks not run.
```

## Maintenance and PR handoff

Recheck this guide and `AGENTS.md` in the same PR when architecture, public
contracts, ownership, safety, persistence, routing, supported platforms,
dependencies, setup/tests, generated outputs, provenance or acceptance limits
change. Update linked specifications too when their contract changed. The PR
maintenance checklist requires either the corresponding edits or an explicit
no-update reason; a checkbox alone does not make an old statement true.

Keep version claims dated and tied to source/release evidence. Do not copy a local
runtime path, user account, balance, API credential or private monitoring result
into public guidance. Prefer links to manifests/constants over repeated moving
pins or exhaustive API copies. A cross-repository change needs companion PRs and
compatibility notes; do not assume that merging one repo deploys the whole system.

A useful AI handoff states: repository and commit, requested scope, relevant
modules/contracts, proposed change, risks, exact checks actually performed,
checks not run, companion repositories affected, and guide sections updated.
Implementation, fixture tests, a compatible release, installation, startup,
read-only account validation and funded acceptance are separate milestones.
