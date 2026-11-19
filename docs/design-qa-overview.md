# LinkWallet asset overview — design QA

final result: passed

## Visual target and evidence

- Selected visual: `/Users/bob/.codex/generated_images/01a1f125-f470-7b62-aedc-cf597122261b/exec-dc51dec9-c489-4626-829f-dade5966fb62.png`.
- Final rendered Flutter component capture: `/tmp/linkwallet-design-fixture.png`.
- Full comparison: `/tmp/linkwallet-design-comparison.png`.
- Focused comparison: `/tmp/linkwallet-design-detail-comparison.png`.
- Source: 1536 × 1024, normalized to 1200 × 800; native title bar cropped by 33 pixels. Flutter fixture: 1200 × 800 logical pixels, pixel ratio 1, cropped to the matching 1200 × 767 app-content region for comparison.
- State: dark green theme, TRON, selected signing wallet, three chain-scoped wallets, two assets, four transactions, small-transaction filter enabled. The render uses synthetic data; no live balances or private data are stored in this report.
- The native app was also inspected at 1200 × 800 after installation. Existing-wallet selection and the receive QR dialog worked. After the final alignment update, native data loading requires the user's macOS Keychain authorization again. The final visual comparison therefore uses rendered production widgets with synthetic data rather than claiming the final native Keychain flow has completed.

## Comparison history

1. Native first pass: [P2] asset actions did not align consistently between native and token rows; the history heading was lower than the asset heading. Fixed by making the balance columns fill their allocated width, using equal 32-pixel header controls, and restoring row separators. The final fixture comparison shows aligned asset actions and headings. Breakpoint tests assert the two section headings align within 8 pixels.
2. Post-fix full and focused comparison: no remaining actionable P0/P1/P2 findings. The icon navigation rail, wallet list, selected-wallet context, resource strip, primary/secondary actions and parallel asset/activity regions follow the chosen composition.

## Required fidelity surfaces

- Typography: native Chinese system fallback and existing shadcn Geist hierarchy retained. Wallet heading 24, region headings 18, balance/activity text 13–14. The isolated capture loads local PingFang for Chinese text; font rasterization and weight differ slightly from the native capture. Text remains readable without wrapping into adjacent controls.
- Spacing/layout: 64-pixel navigation rail, 216-pixel wallet sidebar, 24-pixel content inset, compact wallet toolbar and resource strip. Main grid uses 48:52 tracks and a thin vertical divider. Below 850 pixels of available content width the sections stack. Tests at window widths 1200, 1000 and 760 pass without overflow.
- Color/tokens: charcoal background, warm neutral panels/borders and mint primary use centralized theme tokens. Existing alternate palettes and light/dark/system modes remain available. Incoming/outgoing activity has direction icons as well as semantic color.
- Assets/icons: existing bundled LinkWallet, network and token artwork retained. Chain/token logos use circular masks. Navigation and actions use the installed Lucide icon font; no generated screenshot or mockup is used as interface content.
- Copy/content: names, balances, resources, token definitions, permissions and history come from the existing controller. Demo amounts are only in tests. Addresses stay masked in the overview, with full-address tooltip and copy action. Non-transfer contract events remain supported in activity.

## Interaction and verification

- Native: selected a different existing wallet and observed refreshed identity/resources/assets; opened and dismissed receive QR dialog.
- Automated: wallet selection; current-chain filtering; watch-only transfer disablement; small-transaction switch; horizontal versus stacked layout at three widths; existing theme, clipboard, transfer and governance regression coverage.
- `flutter analyze --no-pub`: passed.
- `flutter test --no-pub`: 69 tests passed.
- Release macOS build and deep/strict code-signature verification: passed.
- `git diff --check`: passed.
- Native Flutter application: browser console checks are not applicable. No real transfer, vote, stake or external publication was performed during UI verification.

## Follow-up polish and limitations

- [P3] ImageGen lettering, mock address lengths and timestamps differ from actual dynamic content. Existing desktop type scale and exact balance formatting are preserved rather than reproducing raster lettering.
- [P3] Settings stays anchored at the bottom of the icon rail, with tooltips for all navigation icons. This keeps preferences reachable as the wallet list grows.
- Final installed native process is awaiting user completion of the macOS Keychain prompt. This does not block component-level visual QA, but that final OS authorization cannot be completed by the agent.

## Implementation checklist

- [x] Icon rail plus wallet sidebar.
- [x] Compact wallet context/actions/resources.
- [x] Parallel assets and recent activity; responsive stacking.
- [x] Existing real-data flows, signing permissions, token controls and themes preserved.
- [x] Full and focused comparison after alignment corrections.
- [x] Static checks, regression tests, release build and local installation.
