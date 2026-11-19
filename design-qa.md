# LinkWallet staking and voting — design QA

final result: passed

## Target and comparison evidence

- Selected target: first displayed staking concept, `/Users/bob/.codex/generated_images/01a1f125-f470-7b62-aedc-cf597122261b/exec-91e18c8d-eea4-4071-b93a-d24649e4aada.png`.
- Final production-widget renders, with synthetic accounts and balances:
  - `/Users/bob/.codex/visualizations/2026/11/19/01a1f125-f470-7b62-aedc-cf597122261b/governance/staking.png`
  - `/Users/bob/.codex/visualizations/2026/11/19/01a1f125-f470-7b62-aedc-cf597122261b/governance/voting.png`
- Side-by-side full comparison: `/Users/bob/.codex/visualizations/2026/11/19/01a1f125-f470-7b62-aedc-cf597122261b/governance/comparison.png`.
- Side-by-side focused comparison: `/Users/bob/.codex/visualizations/2026/11/19/01a1f125-f470-7b62-aedc-cf597122261b/governance/focused-comparison.png`.
- Viewport: 1254 × 854 logical pixels, widget capture pixel ratio 1. Source is 1520 × 1035, normalized to 1254 × 854, then cropped by 34 pixels at top to exclude the native title bar. Both app-content comparison regions are 1254 × 820.
- State: dark green, TRON, signing wallet selected, three wallets, energy/bandwidth holdings, no pending unlocks. Voting is a related state in the same selected design system, using the existing representative/allocation workflow. No real wallet details are in these saved renders.
- The isolated Flutter renderer loads the local PingFang font for Chinese text and the installed Lucide/Material icon fonts. Native font rasterization and weight may differ slightly.

## Findings and comparison history

1. Initial component/flow checks found unbounded width on the new shadcn header tabs. Fixed by explicitly constraining the tab bar to 224 pixels. Existing governance flow tests and workspace tests now pass.
2. First visual comparison found [P2] selected workflow tabs lacked the mint emphasis of the chosen target. Updated the selected background/foreground to shared primary tokens. Also adjusted resource detail heading scale. Re-rendered staking and voting and compared both the full composition and focused wallet/resource/table region.
3. Post-fix comparison: no remaining actionable P0/P1/P2 visual findings. Persistent navigation, chain-scoped wallet list, identity/tabs, thin metrics strip, paired resource operations, resource table and unlock section follow the selected hierarchy. Major regions fit above the fold at the target viewport.

## Required fidelity surfaces

- **Typography:** 19–20 pixel wallet/resource headings, 18 pixel resource section heading, 12–14 pixel content, existing system Chinese fallback and shadcn typography. Native-value precision is preserved instead of hardcoding the mock's trailing zeros. Long wallet/representative labels truncate without hiding controls.
- **Spacing/layout:** 64 pixel navigation rail, 216 pixel wallet list, 24 pixel main inset. Resource operations use two columns divided by a hairline at desktop widths and stack below 680 pixels of available content width. Header controls also stack when needed. The table retains its fixed action column and horizontal scrolling at narrow widths.
- **Colors/tokens:** shared charcoal surfaces, mint primary actions, muted secondary text and thin borders. Workflow tab active color now matches the concept. Light/dark and other palettes continue through existing shared theme tokens.
- **Images/icons:** original bundled LinkWallet/TRON logos; installed Lucide action/resource/representative icons; no screenshot UI or replacement artwork. Addresses are masked with full tooltips, with a working copy action.
- **Copy/content:** real controller/API state remains authoritative. Staking, unstaking, delegating, reclaiming, reward withdrawal and voting retain existing preview/signing dialogs. Resource estimates remain marked approximate, and the existing data-availability note is retained. Voting search, allocation editing, full-distribution preview, signing permissions and representative filtering remain functional.

## Intentional adaptations and P3 polish

- Retain the existing resource table's last-operation-time column and approximation note, omitted from the mock, to avoid removing useful data/context.
- Table rows retain their existing bandwidth/energy order; the two primary operation columns remain energy/bandwidth as selected.
- Settings remains at the bottom of the shared navigation rail for consistency with the implemented overview.
- Native balances keep exact existing decimal formatting; generated mock typography, sample address lengths and comma formatting are not reproduced literally.
- The voting page has no independently selected raster target. It extends the chosen staking shell and spacing with a compact representative list, while preserving its existing search/allocation/preview workflow.

## Functional and build checks

- `flutter analyze --no-pub`: passed.
- `flutter test --no-pub`: 73 tests passed, excluding the temporary capture-only harness.
- New governance workspace tests at 1254, 1000 and 760 pixels: no layout exceptions; wallet navigation retained; switching to watch-only disables allocation actions.
- Existing governance tests: delayed wallet-response isolation, vote allocation preservation/editing, preview/signature boundary and delegation wallet selection pass.
- Release macOS build: passed. Ad-hoc signature deep/strict verification: passed. Installed at `/Applications/LinkWallet.app`.
- Native app verified after installation: staking and voting both loaded live state with persistent wallet navigation. Selected wallet changed successfully; resource totals refreshed; voting displayed representative rows and allocation/preview controls. Native evidence is local-only at `/tmp/linkwallet-governance-native-staking.jpg` and `/tmp/linkwallet-governance-native-voting.jpg`; these contain user data and are not committed or embedded in the report. The native preview is left open on voting.
- This is a native Flutter app; browser console checks are not applicable. No actual financial operation was submitted during validation.
- Prior asset overview QA is preserved in `docs/design-qa-overview.md`.

## Implementation checklist

- [x] Reuse the existing shell and chain-scoped wallet sidebar in governance routes.
- [x] Return/navigation/network changes leave the governance route cleanly.
- [x] Paired energy/bandwidth operations and inline resource summary.
- [x] Flat resource details and unlock section.
- [x] Compact searchable representative rows and unified vote preview.
- [x] Split operation dialogs/resource overview/representative rows into separate files.
- [x] Post-fix visual comparison, regression tests, release build and local installation.


## Follow-up: embed governance inside the overview

User correction: staking/voting must be content components of the asset overview, not separate animated routes.

- Removed `Navigator.push` from `WalletActions.openTronGovernance`.
- `WalletHome` now owns one persistent `WalletShell`; staking/voting render inside its content slot in embedded mode, with no nested scaffold or shell.
- Sidebar and top bar stay fixed, including the asset-overview title. Return-to-assets clears the component selection instead of popping a route.
- Embedded state responds to parent wallet changes; switching away from TRON or navigating to another section exits governance.
- Regression tests at 1200, 1000 and 760 pixels assert that route pushes do not increase, the shell element remains identical, only one shell exists, returning restores the dashboard, and watch-only/network changes work.
- Final static analysis passed; full regression suite: 79 tests passed. Release build, strict signature verification and local installation passed.
- Native app restarted after installation; live-data loading may require renewed user Keychain authorization. The earlier native screenshots above predate this embedding correction; the route/shell invariants are verified by the new automated tests.
