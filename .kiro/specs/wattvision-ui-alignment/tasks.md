# Implementation Plan: WattVision UI Alignment

## Overview

Nine phases, in the order established by design.md's "Migration and Sequencing" section. Each phase is independently verifiable and depends only on phases before it.

This is a two-client feature. Every phase lands in both `flutter_app/` (Dart) and `react_app/` (TypeScript), and Requirements 13.1 and 13.2 require the two to agree. Flutter and React sub-tasks for the same piece of work are therefore adjacent under a shared parent, so a parity break surfaces in the phase that caused it rather than at phase 9. Where a piece is genuinely shared — the parity fixtures under `test_fixtures/`, the five domain-icon path files under `design/icons/` — it is its own task placed before both client tasks that consume it.

The 30 correctness properties from design.md are each implemented as exactly one property-based test, in the same task as the behaviour it constrains. Properties are referenced by their design number and title.

Nothing under `firmware/` is touched. `arduino-cli` is available and the firmware compiles clean; it stays out of scope.

**Toolchain reality:** Node 22.21 / npm 11.20 are available and `react_app` currently builds clean under TypeScript strict + Vite 8, with no test script and no test dependencies. **Flutter 3.47.5 stable / Dart 3.13.4 IS installed** at `C:\Users\User0\Desktop\flutter` — this corrects the earlier assumption that no SDK was present, and it means every Flutter verification step in every phase is executable and must actually be run, never reported as blocked. The native host projects still do not exist (`flutter create` has never been run); that is task 17.6 and is deliberately not a blocker for `flutter analyze` or `flutter test`. **The `flutter analyze` baseline was not clean: 6 pre-existing errors and 5 infos. All 11 have since been remediated** (user-approved remediation task, run before Phase 1 continued) and `flutter analyze` now reports **`No issues found!`** — see the task 1.1 baseline record and its remediation note below. Requirement 13.5 therefore holds as of the start of Phase 1, and later checkpoints must keep it there.

## Tasks

- [x] 1. Phase 1 — Test harness, token registry and compliance suite
  - Makes every later phase checkable. Satisfies Requirement 1 on its own and changes no UI.

  - [x] 1.1 Verify the Flutter toolchain and record a baseline
    - Run `flutter --version`, then `flutter pub get`, `flutter analyze` and `flutter test` in `flutter_app/`
    - Record the actual output of each; none of these has ever been executed against this codebase
    - If `flutter pub get` fails to resolve the declared `sdk: ^3.12.0` constraint against any pinned dependency, fix the constraint before proceeding rather than working around it
    - If no Flutter SDK is present, record that fact in the task notes and treat every Flutter verification step in later phases as blocked-and-reported rather than silently skipped
    - _Requirements: 13.5_

    **Baseline recorded (task 1.1, first ever execution against this codebase):**

    - `flutter --version` → **Flutter 3.47.5 • channel stable**, Framework revision `6a19cca564`, Engine `af7e796e16`, **Tools • Dart 3.13.4 • DevTools 2.60.0**. SDK resolved from `C:\Users\User0\Desktop\flutter\bin\flutter.bat`. A Flutter SDK **is** present; the Overview's earlier "not installed" claim was wrong and has been corrected.
    - `flutter pub get` → **exit 0, `Got dependencies!`**. The declared `sdk: ^3.12.0` constraint resolves cleanly against Dart 3.13.4 and against every pinned dependency, so **no constraint fix was required**. Advisory only: 3 transitive packages are held below their newest versions by constraints (`dbus 0.7.15`→0.8.0, `material_color_utilities 0.13.0`→0.13.1, `test_api 0.7.12`→0.7.14). Not errors.
    - `flutter analyze` → **exit 1, 11 issues: 6 errors + 5 infos.** The baseline is **not** clean, so Requirement 13.5 is currently failing. The 6 errors, verbatim:
      1. `lib/core/protocol/leak_protocol.dart:10:1` — `library_directive_not_first`: the `library` directive must appear before all other directives.
      2. `lib/core/protocol/leak_protocol.dart:77:13` — `illegal_concrete_enum_member`: `SensorRole` declares `@override final int index`, and a concrete member named `index` is illegal on an enum.
      3. `lib/core/theme/app_theme.dart:183:50` — `argument_type_not_assignable`: `TextTheme` → `TextTheme?`.
      4. `lib/core/theme/app_theme.dart:250:18` — `argument_type_not_assignable`: `TextTheme` → `TextTheme?`. (3 and 4 are the `google_fonts` 9.0.0 call sites; they look like API skew against Flutter 3.47's material `TextTheme`.)
      5. `lib/data/ble/hm10_transport.dart:309:20` — `missing_required_argument`: required named parameter `license` has no corresponding argument.
      6. `lib/ui/diagnostics/diagnostics_sheet.dart:93:27` — `undefined_getter`: `grantsAccess` is not defined for `LinkState`.
      The 5 infos: `prefer_initializing_formals` at `lib/state/monitor_controller.dart:28:9`; `use_null_aware_elements` at `lib/ui/common/charts.dart:481:11`, `lib/ui/common/motion_widgets.dart:211:11` and `lib/ui/root_view.dart:35:11`; `unnecessary_underscores` at `lib/ui/diagnostics/diagnostics_sheet.dart:471:35`.
    - `flutter test` → **exit 1, `Test directory "test" not found.`** No `test/` directory exists yet. This is the expected pre-state, not a defect: tasks 1.3 and 1.4 create `flutter_app/test/`. `android/`, `ios/` and `web/` are likewise absent, confirming `flutter create` has never run (task 17.6).
    - **Consequence for later phases:** all four commands are runnable, so nothing Flutter-side is blocked. The 6 analyzer errors pre-dated this feature and blocked Requirement 13.5, so they were remediated in their own user-approved task before Phase 1 continued — see below.

    **Remediation of the 11 baseline issues (user-approved task, run before Phase 1 continued):**

    `flutter analyze` in `flutter_app/` now reports, verbatim:

    ```
    Analyzing flutter_app...
    No issues found! (ran in 2.8s)
    ```

    **0 errors, 0 warnings, 0 infos**, exit 0. Requirement 13.5 is satisfied. No dependency versions changed — `pubspec.yaml` is untouched, so `google_fonts 9.0.0` and `flutter_blue_plus 2.3.13` stay pinned as they were. What each fix was:

    1. `leak_protocol.dart` — the library-level doc comment and its `library;` directive moved above `import 'dart:convert';`. Comment text unchanged.
    2. `leak_protocol.dart` — `SensorRole` dropped its `@override final int index` field and the matching constructor positional. The ordinals are unchanged because declaration order already supplies them through `Enum.index`: `inlet` 0, `outletA` 1, `outletB` 2. `SensorRole.byIndex` and every call site (`settings_tab.dart`, `sensor_page.dart`) behave identically; a doc note now records that declaration order must stay in step with the firmware's sensor numbering. No wire semantics, calibration data or alarm logic touched (Requirement 13.9).
    3 & 4. `app_theme.dart` — the root cause was not version skew but a package split: `google_fonts 9.0.0` is built against the decoupled **`material_ui`** package, whose `TextTheme` is a distinct type from `package:flutter/material.dart`'s. `TextStyle` is still shared between the two, so `GoogleFonts.interTextTheme(base.textTheme)` was replaced with a local `AppTheme._applyInter(TextTheme)` that maps the same 15 slots through `GoogleFonts.inter(textStyle: …)` — exactly what `interTextTheme` does internally, minus the cross-package type. Every `.copyWith` override is byte-for-byte unchanged, so the WattVision typography still resolves to Inter SemiBold 24 titles, Inter Regular 14 body and JetBrains Mono Bold 32 KPIs, and `design_tokens.dart` was not touched (palette `#121212`, `#1E1E1E`, `#00E5FF`, `#FF453A`, `#32D74B`, `#FFFFFF`, `#98989D`, `#2C2C2E` all intact).
    5. `hm10_transport.dart` — `device.connect` gained `license: License.nonprofit`, the flutter_blue_plus 2.x licence acknowledgement; this is a personal/educational project, so the nonprofit terms apply. `timeout` and `autoConnect` are unchanged and no other default was overridden.
    6. `diagnostics_sheet.dart` — `grantsAccess` already exists as `LinkStateX.grantsAccess` in `data/ble/leak_transport.dart`; the extension simply was not in scope. Fixed by adding the missing import, so nothing was invented and Connection_Gate behaviour plus the `requireConnectionToBrowse` setting are untouched (Requirement 13.6).
    - The 5 infos were cleared locally: `monitor_controller.dart` now uses the initialising formal `required this._settings` (the named argument callers pass is still `settings:`, so `main.dart` is unchanged); the three `if (x != null) x` collection entries in `charts.dart`, `motion_widgets.dart` and `root_view.dart` became null-aware elements `?x`; and the `separatorBuilder` wildcard in `diagnostics_sheet.dart` became `(_, _)`.
    - `flutter_app/test/` was deliberately **not** created — that remains tasks 1.3 and 1.4. `flutter test` therefore still reports `Test directory "test" not found.`

  - [x] 1.2 Add the Vitest and fast-check harness to the Web_Client
    - Add exact-pinned `vitest` and `fast-check` dev dependencies to `react_app/package.json` plus a `"test": "vitest --run"` script
    - Create `react_app/tsconfig.test.json` and `react_app/vitest.config.ts` reusing the existing Vite resolution, with a `jsdom` environment for DOM assertions and a `node` environment for fixture-reading tests
    - Keep test files out of the production `tsc --build` path so `npm run build` is unaffected
    - Create `react_app/src/__tests__/compliance/` as the suite root
    - _Requirements: 13.3, 13.4_

  - [x] 1.3 Resolve the Dart property-testing library and add the generator harness
    - Attempt `glados` as a dev dependency in `flutter_app/pubspec.yaml` and run `flutter pub get` to verify resolution against `sdk: ^3.12.0`
    - This is an explicit decision point, not an assumption — design.md records it as unverified because no SDK was available
    - If resolution fails, remove the dependency and write the fallback harness at `flutter_app/test/support/props.dart`: a seeded `Random`, a `Gen<T>` typedef, a `forAll<T>` runner defaulting to 100 cases, and halving-based shrinking
    - Either way, print the seed on failure so counterexamples are reproducible
    - Create `flutter_app/test/compliance/` as the suite root
    - _Requirements: 13.5_

    **Decision recorded (task 1.3): `glados` resolves, so it is the generator and shrinker — the fallback harness was not needed.**

    The design.md open decision is now closed with evidence rather than assumption:

    - `flutter pub add --dev glados --dry-run` → **exit 0**, `glados 1.1.7` resolves against the declared `sdk: ^3.12.0` on Dart 3.13.4. It pulls 26 dev-only transitive changes, the notable ones being `test 1.31.1`, `analyzer 13.3.0`, `coverage 1.15.1` and a `package_config` downgrade from 3.0.0 to 2.2.0. All are dev-scoped test tooling; no runtime dependency moved, and `google_fonts 9.0.0` / `flutter_blue_plus 2.3.13` stay pinned exactly as they were.
    - `pubspec.yaml` gained one line under `dev_dependencies`: **`glados: 1.1.7`**, pinned exact, matching how the runtime dependencies are pinned. `flutter pub get` → exit 0, `Got dependencies!`.
    - A throwaway probe (`Glados<int>(any.int).test(...)`) was run under `flutter test` **before** any harness code was written, because resolving is not the same as running: glados exports `package:test`, which collides with `flutter_test`. The probe passed and printed `testing 100 inputs`, confirming glados' own default already matches the 100-case floor. The probe file was deleted once the real harness existed.
    - **Therefore the ~80-line fallback in design.md ("a seeded `Random`, a `Gen<T>` typedef, a `forAll<T>` runner, halving-based shrinking") is not implemented as a replacement for a library.** Hand-rolling generation and shrinking when a maintained package resolves would have contradicted the guidance not to write property testing from scratch.

    **What was built — `flutter_app/test/support/props.dart`.** A thin runner over glados, not a reimplementation. glados supplies `Generator<T>`, `Shrinkable<T>` and the whole `any.*` generator surface; this file supplies the four things the 30 properties need that glados does not give directly:

    1. **`forAll` / `forAll2` / `forAll3`** — declare a property with `cases` defaulting to `kPropertyCases = 100` and an `assert` that refuses fewer, so the design.md floor cannot be lowered by accident. The two- and three-input forms combine through `any.combine2`/`combine3` and hand the body plain positional arguments, with `examples:` typed as `(A, B)` / `(A, B, C)` records.
    2. **A fixed, reported seed.** `kPropertySeed = 0x57415454` (`WATT`). It appears in the test name — the runner names the test `<description> [100 cases, seed 1463899220]` — and again in the failure report, so a counterexample is reproducible from the failing line alone. `avoid_print` is enabled in `analysis_options.yaml`, so the report goes through `fail()` rather than `print`, which also keeps it attached to the failing test instead of the run's stdout.
    3. **`examples:`** — values checked before the generated cases. This is what makes "biased to include 599, 600, 601, 1023, 1024, 1025" (Property 1) exhaustive rather than probabilistic; `any.biasedTowards` is available for the probabilistic version where that is enough.
    4. **`checkProperty`** — the same runner as a plain function returning a `PropertyOutcome<T>` instead of failing the enclosing test. Without it the harness could not be tested, since asserting "this property fails and shrinks to 50" inside a test that fails on failure is not expressible.

    Shrinking is glados' `Shrinkable.shrink()`, driven by the same fixed-point loop glados uses, plus a `kMaxShrinkSteps = 500` cap glados does not have, so a slow-converging double shrinker cannot hang `flutter test`.

    **Shared generators, in an extension on glados' `Any` so they read like the built-ins.** `any.intBetween(min, max)` and `any.doubleBetween(min, max)` are inclusive on both ends and shrink by **halving towards the simplest in-range value** — the value nearest zero, which for `[320, 2560]` is 320. glados' own `intInRange` was not reused for these: it widens with the run size, so the top of a band is under-sampled early, and it shrinks by single decrements, which would turn a failing width of 2400 into a 2080-step walk. `any.pick(values)` is uniform and shrinks towards index 0, replacing glados' `choose`, whose index is clamped by the run size. `any.enumOf(Enum.values)` covers Layout_Mode, Appearance, Status and the unit enums. `any.listBetween(item, minLength:, maxLength:)` wraps glados' `listWithLengthInRange` with inclusive bounds for the span-list and event-list generators of Properties 4, 13 and 28. Everything glados already does well — `bool`, strings, `DateTime`, `Duration`, `map`, `set`, `combineN`, `map`/`bind`/`nullable` — is re-exported untouched, so a property test imports `flutter_test` and `../support/props.dart` and nothing else. The `show`/`export` clauses are explicit precisely so glados' re-exported `package:test` `test` and `expect` never shadow `flutter_test`'s.

    **`flutter_app/test/compliance/` created**, with `property_harness_test.dart` as its first file. It is not only a smoke test: it asserts the harness contract the other 29 properties will rely on — the default really is 100 cases, `examples` run first and in order, a failing example is reported unshrunk, a failing property shrinks to **exactly** the boundary (`< 50` over `[0, 1000]` reports 50, not merely something near it), the report contains the seed and the counterexample, the same seed replays the same inputs while a different seed does not, and `enumOf`, `listBetween` and `doubleBetween` stay inside their domains. Ten tests, one of them the smoke property with its eight boundary examples.

    **Verification, all three commands run in `flutter_app/`:**

    - `flutter pub get` → exit 0, `Got dependencies!`
    - `flutter analyze` → **`No issues found! (ran in 2.2s)`**, exit 0. Requirement 13.5 holds; the baseline established in 1.1 is unchanged. The first draft did produce 10 `unused_shown_name` warnings, because the `import ... show` list had been written to cover the re-export surface as well; splitting the narrow `import` from the wide `export` cleared them. The suite is not excluded from analysis — `test/` is analysed with the same `flutter_lints` rules, `strict-casts` and `strict-raw-types` as `lib/`.
    - `flutter test` → **`All tests passed!`**, 10/10, exit 0.

    Nothing outside `flutter_app/pubspec.yaml`, `pubspec.lock` and the two new test files was touched. No `lib/` file, no token registry (task 1.6), no contrast helper (task 1.4).

  - [x] 1.4 Add the contrast and colour-maths helper to the Flutter compliance suite
    - Create `flutter_app/test/compliance/contrast.dart` with sRGB linearisation (`c <= 0.03928 ? c/12.92 : pow((c+0.055)/1.055, 2.4)`), the 0.2126/0.7152/0.0722 luminance weights, `contrastRatio` as `(Llighter + 0.05) / (Ldarker + 0.05)`, and HSL lightness/saturation extraction
    - Assert and pin the Requirement 11.3 pair: `#00E5FF` on `#1E1E1E` is 10.84:1
    - _Requirements: 11.3_

  - [x] 1.5 Add the contrast and colour-maths helper to the React compliance suite
    - Create `react_app/src/__tests__/compliance/contrast.ts` with the identical algorithm and the same pinned 10.84:1 assertion, so both clients compute contrast the same way
    - _Requirements: 11.3_

  - [x] 1.6 Create the Flutter token registry
    - Create `flutter_app/lib/core/theme/token_registry.dart` with `TokenSpec` (name, argb, WattVision section) and `TokenExtensionSpec` (name, argb, rationale, consumedBy)
    - Populate `kWattVisionTokens` with every §2 colour and the §3 geometry, §4 type and §5 spacing numeric specs
    - Populate `kTokenExtensions` with `watch` `#FFD60A` and its recorded rationale, plus `watchBoxFill`, `normalBoxFill`, `idle` and the derived light palette entries
    - Record the computable pastel thresholds (HSL lightness > 0.8 with saturation < 0.5, achromatic excluded) in the registry
    - _Requirements: 1.1, 1.9, 1.10, 9.8_

  - [x] 1.7 Create the React token registry mirror
    - Create `react_app/src/styles/token-registry.json` keyed by custom-property name, mirroring 1.6 exactly including extension rationales and the pastel thresholds
    - _Requirements: 1.1, 1.9, 1.10, 9.8_

  - [x] 1.8 Write the Flutter literal-colour scanner and unit-test it
    - Walk `flutter_app/lib/**/*.dart` with `dart:io` and fail on `Color(0x········)` or `Colors.<name>` outside `core/theme/design_tokens.dart` and `core/theme/token_registry.dart`
    - Declare the single exemption explicitly: `Colors.transparent`, which the theme needs for `surfaceTintColor` and which carries no palette meaning
    - Unit-test the scanner itself against positive and negative fixture strings — Requirement 1.4 is a statement about the scanner failing, so the scanner's own behaviour must be asserted
    - _Requirements: 1.2, 1.4_

  - [x] 1.9 Write the React literal-colour and breakpoint scanners and unit-test them
    - Walk `react_app/src/**` and fail on `#rgb`/`#rrggbb`/`#rrggbbaa`, `rgb(`/`rgba(`, `hsl(`/`hsla(` outside `src/styles/tokens.css`, skipping `url(#...)` SVG gradient references
    - Add a second scan asserting no `@media (min-width:` or `(max-width:` breakpoint appears in `src/styles/*.css`, keeping `src/core/layout.ts` the single authority for the three thresholds
    - Unit-test both scanners against positive and negative fixture strings, for the same reason as 1.8
    - _Requirements: 1.3, 1.5, 2.1_

  - [x] 1.10 Assert the fixed WattVision constants in the Flutter compliance suite
    - Assert the eleven §2 colour values of Requirement 1.6 against `kWattVisionTokens`
    - Assert card radius 16, card padding 20, hairline 1, title 24, KPI 32, body 14
    - _Requirements: 1.6, 1.7_

  - [x] 1.11 Assert the fixed WattVision constants in the React compliance suite
    - Same eleven colours and six numeric values, read from `token-registry.json` and cross-checked against `tokens.css`
    - Assert the relationship bidirectionally: every registry key exists in `tokens.css` with the stated value, and every custom property in `tokens.css` exists in the registry, so an undocumented token is a failure
    - _Requirements: 1.6, 1.7, 1.9_

  - [x] 1.12 Write property test for the spacing scale and token extensions
    - **Property 21: Every spacing token is a multiple of eight and every extension is documented**
    - Generators: the registry itself — the spacing token set and the Token_Extension set
    - Invariant: `value % 8 == 0` for every spacing entry; `rationale` and `consumedBy` non-empty for every extension; registry and stylesheet agree bidirectionally
    - Implement in `flutter_app/test/compliance/` and `react_app/src/__tests__/compliance/`
    - **Validates: Requirements 1.8, 1.9**

- [x] 2. Checkpoint — Phase 1
  - Run `npm run typecheck`, `npm run build` and `npx vitest --run` in `react_app/`
  - Run `flutter analyze` and `flutter test` in `flutter_app/`
  - Ensure all tests pass, ask the user if questions arise.

- [x] 3. Phase 2 — Token and theme work
  - Verifiable against the phase 1 suite. Introduces `accentText`, High_Contrast_Dark and the `Appearance` enum with its legacy migration.

  - [x] 3.1 Add the accent-text and high-contrast tokens to the Mobile_Client theme
    - In `flutter_app/lib/core/theme/design_tokens.dart` add `hcTextSecondary` `#C7C7CC`, `hcBorder` `#48484A` and `lightAccentText` `#00707F`
    - In `flutter_app/lib/core/theme/app_theme.dart` add an `accentText` field to `AppPalette` (with `copyWith` and `lerp` coverage), aliasing `accent` in the dark palettes and `#00707F` in light — the measured light accent is 3.74:1 and fails as text
    - Add `AppPalette.highContrastDark` built with `copyWith` off `dark`, overriding only `textSecondary`, `border` and `accentText`; background, surface and surfaceRaised stay identical to Dark
    - Register the three new values as Token_Extensions in `token_registry.dart`
    - _Requirements: 1.9, 9.1, 9.2, 11.4_

  - [x] 3.2 Add the accent-text and high-contrast tokens to the Web_Client theme
    - In `react_app/src/styles/tokens.css` add `--accent-text`, group `:root[data-theme='dark'], :root[data-theme='hc-dark']` over the existing dark block, then override only `--text-secondary: #c7c7cc` and `--border: #48484a` for `hc-dark`; set `--accent-text: #00707f` in the light block
    - In `react_app/src/styles/global.css` switch `.section__title` and `.row__value` from `var(--accent)` to `var(--accent-text)` — this is the concrete application of Requirement 11.4
    - Mirror the new properties into `src/styles/token-registry.json`
    - _Requirements: 1.9, 9.1, 9.2, 11.4_

  - [x] 3.3 Replace `themeMode` with `Appearance` in the Mobile_Client settings
    - In `flutter_app/lib/data/settings/app_settings.dart` add an `Appearance` enum (`dark`, `highContrastDark`, `light`, `system`) defaulting to `dark`, remove the `ThemeMode themeMode` field, and update `copyWith`
    - In `flutter_app/lib/data/settings/settings_controller.dart` persist a new `appearance` key and read the legacy `themeMode` index once: 0→system, 1→light, 2→dark, out-of-range→dark
    - Leave every other persisted key untouched
    - _Requirements: 9.1, 9.6, 9.7, 13.7_

  - [x] 3.4 Replace `themeMode` with `appearance` in the Web_Client settings
    - In `react_app/src/state/settingsStore.ts` change the field to `appearance: 'dark' | 'hc-dark' | 'light' | 'system'` defaulting to `'dark'`, and add the equivalent one-time remap of a legacy persisted `themeMode` string inside `read()` before the merge over `DEFAULT_SETTINGS`
    - _Requirements: 9.1, 9.6, 9.7, 13.7_

  - [x] 3.5 Resolve the appearance to a theme in the Mobile_Client
    - In `flutter_app/lib/app.dart` map the four `Appearance` values onto `AppTheme.dark()`, a new `AppTheme.highContrastDark()`, `AppTheme.light()` and the platform brightness
    - _Requirements: 9.1, 9.2, 9.6_

  - [x] 3.6 Resolve the appearance to a theme in the Web_Client
    - In `react_app/src/App.tsx` map the four appearance values onto `data-theme` values `dark` / `hc-dark` / `light`, keeping the existing `prefers-color-scheme` listener for `system` and updating the `theme-color` meta tag accordingly
    - _Requirements: 9.1, 9.2, 9.6_

  - [x] 3.7 Rework the Mobile_Client appearance controls
    - In `flutter_app/lib/ui/settings/settings_tab.dart` offer Dark, High Contrast Dark and Follow system as the primary Appearance choice
    - Move the light appearance into an Accessibility section as a separate switch, and show a persistent advisory when it is selected stating that light backgrounds sit outside WattVision guidance for prolonged data reading
    - Add an example test for the advisory wording
    - _Requirements: 9.1, 9.2, 9.3, 9.4, 9.6_

  - [x] 3.8 Rework the Web_Client appearance controls
    - Same three-option primary control, same light-in-accessibility placement and same advisory in `react_app/src/screens/SettingsTab.tsx`, using the identical option names so Requirement 9.6 holds
    - Add an example test for the advisory wording
    - _Requirements: 9.1, 9.2, 9.3, 9.4, 9.6_

  - [x] 3.9 Write property test for text contrast across appearances
    - **Property 16: Every text token meets its contrast threshold on every surface in every appearance**
    - Generators: appearance (Dark, High_Contrast_Dark, Light); textToken with its declared role; surfaceToken (background, surface, surface-raised)
    - Invariant: `contrastRatio(text, surface) >= thresholdFor(role)` — 4.5:1 body and secondary, 3:1 KPI/title and focus indicators
    - **Validates: Requirements 11.1, 11.2, 11.7, 9.5**

  - [x] 3.10 Write property test for the accent used as text
    - **Property 17: The accent is never used as text where it fails 4.5:1**
    - Generators: appearance — the three appearances
    - Invariant: either the accent-as-text token meets 4.5:1 against every surface it appears on, or no text token in that appearance resolves to the raw graphical accent
    - **Validates: Requirements 11.3, 11.4**

  - [x] 3.11 Write property test for the pastel prohibition
    - **Property 20: No appearance contains a pastel colour**
    - Generators: appearance; every colour in that appearance's palette
    - Invariant: `!(lightness > 0.8 && saturation < 0.5)`, using the thresholds recorded in the token registry, with white and pure black excluded as achromatic
    - **Validates: Requirements 9.8**

  - [x] 3.12 Write property test for the High_Contrast_Dark appearance
    - **Property 26: High_Contrast_Dark strictly improves contrast without leaving the dark family**
    - Generators: token — the text and border tokens
    - Invariant: `ratio(hcDark) >= ratio(dark)` for every token, strict for secondary text and border; background, surface and surfaceRaised equal between the two appearances
    - **Validates: Requirements 9.2**

  - [x] 3.13 Write property test for appearance persistence
    - **Property 25: Appearance selection round-trips through persistence**
    - Generators: appearance — the four values; legacyIndex — integers including 0, 1, 2 and out-of-range
    - Invariant: reload yields the written appearance; legacy 0→system, 1→light, 2→dark, out-of-range→dark
    - **Validates: Requirements 9.6, 9.7**

  - [x] 3.14 Write property test for Reduce_Motion
    - **Property 19: Reduce_Motion collapses every transition and stops every ambient animation**
    - Generators: token — every entry in the motion token set; reduceMotion — booleans
    - Invariant: `reduceMotion` implies every resolved duration `<= 1ms` and `ambientEnabled == false`; otherwise the resolved duration equals the declared token value
    - **Validates: Requirements 4.8, 11.6**

- [x] 4. Checkpoint — Phase 2
  - Run `npm run typecheck`, `npm run build` and `npx vitest --run` in `react_app/`
  - Run `flutter analyze` and `flutter test` in `flutter_app/`
  - Confirm the literal-colour scanners still pass after the new tokens landed
  - Ensure all tests pass, ask the user if questions arise.

- [x] 5. Phase 3 — Layout_Engine and Grid_12
  - At the end of this phase both clients still render today's layout at phone widths; wide viewports gain a correct grid holding the existing content.

  - [x] 5.1 Define the Mobile_Client layout bands and metrics
    - Create `flutter_app/lib/core/layout/layout_mode.dart` with `LayoutMode` (compact, medium, expanded), `Breakpoints` (medium 600, expanded 1024, contentMax 1440) and `Breakpoints.resolve(double width)`
    - Add `GridMetrics` with the per-mode gutter/padding/contentMax triples: compact 16/16/560, medium 16/24/none, expanded 24/32/1440
    - _Requirements: 2.1, 2.3, 2.4, 2.5, 2.6_

  - [x] 5.2 Define the Web_Client layout bands and metrics
    - Create `react_app/src/core/layout.ts` with `BREAKPOINTS`, `CONTENT_MAX`, `GRID_METRICS` and `resolveLayoutMode(width)`, holding the same numbers as 5.1 as the single authority — CSS must not restate them
    - _Requirements: 2.1, 2.3, 2.4, 2.5, 2.6, 13.1_

  - [x] 5.3 Publish the resolved mode through the Mobile_Client widget tree
    - Create `flutter_app/lib/core/layout/layout_scope.dart` as an `InheritedWidget` with `LayoutScope.of(context)` and `updateShouldNotify` comparing only the `LayoutMode` enum, so dependents rebuild on a band change and never on a pixel resize
    - _Requirements: 2.1, 2.9_

  - [x] 5.4 Publish the resolved mode through the Web_Client DOM
    - Create `react_app/src/hooks/useLayoutMode.ts` using three `window.matchMedia` queries constructed from the `src/core/layout.ts` constants, wired through `useSyncExternalStore` to match the existing store shape
    - Write the result to `document.documentElement.dataset.layout` so CSS keys off `:root[data-layout='...']` attribute selectors rather than media queries
    - _Requirements: 2.1, 2.9, 2.10_

  - [x] 5.5 Build the Mobile_Client 12-column grid
    - Create `flutter_app/lib/ui/layout/grid12.dart` with `Grid12`, `Grid12Cell` and `Grid12Scaffold`, built on `LayoutBuilder` + `Wrap` + `SizedBox`
    - Column width is `(maxWidth - gutter * 11) / 12`; a cell's width is `columnWidth * span + gutter * (span - 1)`
    - Assert `span` is an integer 1..12 at construction; fall back to a single full-width column when the available width is zero or negative
    - `Grid12Scaffold` applies the Expanded 1440 cap via `Center(child: ConstrainedBox(...))` plus the mode's outer padding
    - Do not use `GridView` — it imposes a uniform tile extent that would clip at 200% text scale
    - _Requirements: 2.2, 2.3, 2.4, 2.5, 2.6, 2.7, 2.8, 11.10_

  - [x] 5.6 Build the Web_Client 12-column grid
    - In `react_app/src/styles/global.css` add `.grid12` with `repeat(12, minmax(0, 1fr))`, `gap: var(--grid-gutter)`, `max-width: var(--grid-content-max)`, `margin-inline: auto`, `padding-inline: var(--grid-pad)`, plus `.span-4`, `.span-8`, `.span-12`
    - Define `--grid-gutter`, `--grid-pad` and `--grid-content-max` per `:root[data-layout='...']` using the existing `--s3`/`--s4`/`--s5` steps, so Requirement 1.8 holds by construction
    - Rely on CSS Grid auto-placement for row wrapping — no JavaScript packing
    - _Requirements: 2.2, 2.3, 2.4, 2.5, 2.6, 2.7, 2.8, 1.8_

  - [x] 5.7 Relocate the Web_Client width caps to Compact scope
    - This is the single highest-risk change in the feature. Do not delete the caps
    - In `react_app/src/styles/global.css` change `.app { max-width: 560px }` to `:root[data-layout='compact'] .app { max-width: 560px }`, with `max-width: none` in Medium and the grid's own 1440 cap in Expanded; give `.sheet { max-width: 560px }` the same treatment so the Diagnostics_Sheet widens only in Expanded
    - Call `useLayoutMode()` from `react_app/src/App.tsx` so `data-layout` is set before first paint
    - Verify Compact rendering is unchanged
    - _Requirements: 2.10, 2.5, 2.6_

  - [x] 5.8 Host the Layout_Engine in the Mobile_Client root
    - In `flutter_app/lib/ui/root_view.dart` wrap the existing `AnimatedSwitcher` in a `LayoutBuilder` whose body constructs nothing but `LayoutScope` around a `const` child, so both the Connection_Gate and the `AppShell` see the mode
    - Use `LayoutBuilder` constraints rather than `MediaQuery.sizeOf`, so split-screen and resized-window widths resolve correctly and the semantics match the Web_Client's CSS-pixel reading
    - Confirm `AppShell` and both `_TabLayer`s stay out of the dependency set, preserving the `Stack` + `TickerMode` arrangement and the state it protects
    - _Requirements: 2.1, 2.9, 4.5_

  - [x] 5.9 Write property test for Layout_Mode resolution
    - **Property 1: Layout_Mode resolution is total and exclusive**
    - Generators: width — integers and reals in [320, 2560], biased to include 599, 600, 601, 1023, 1024, 1025
    - Invariant: `resolve(w)` is non-null; exactly one band predicate holds; the returned mode is the one whose predicate holds
    - **Validates: Requirements 2.1, 2.11**

  - [x] 5.10 Write property test for grid column arithmetic
    - **Property 2: Grid_12 arithmetic conserves the available width**
    - Generators: mode — the three Layout_Modes; width — reals in [320, 2560]
    - Invariant: all twelve column widths equal within tolerance; `12 * columnWidth + 11 * gutter == availableWidth`; `columnWidth > 0`
    - **Validates: Requirements 2.2, 2.3, 2.4, 2.5**

  - [x] 5.11 Write property test for the Expanded content cap
    - **Property 3: Expanded content is capped and centred without horizontal overflow**
    - Generators: width — reals in [1024, 2560]
    - Invariant: `contentWidth <= 1440`; left and right remainders equal within tolerance; `contentWidth + 2 * pad <= width`
    - **Validates: Requirements 2.6, 2.11**

  - [x] 5.12 Write property test for row packing
    - **Property 4: Row packing never exceeds twelve columns and preserves every cell**
    - Generators: spans — lists of length 0 to 30 drawn from integers [1, 12]
    - Invariant: every produced row sums to `<= 12`; flattening the rows yields the input list exactly; every output span is an integer in [1, 12]
    - **Validates: Requirements 2.7, 2.8**

  - [x] 5.13 Write example tests for the fixed per-mode metrics
    - Assert the gutter/padding pairs of Requirements 2.3, 2.4 and 2.5 in both clients, and that a sub-320 viewport resolves to Compact with 16 padding
    - Assert both clients read the same numbers, since the constants are duplicated across languages by necessity
    - _Requirements: 2.3, 2.4, 2.5, 2.11, 13.1_

- [x] 6. Checkpoint — Phase 3
  - Run `npm run typecheck`, `npm run build` and `npx vitest --run` in `react_app/`, and confirm the breakpoint-duplication scan from 1.9 still passes
  - Run `flutter analyze` and `flutter test` in `flutter_app/`
  - Confirm phone-width rendering is unchanged in both clients
  - Ensure all tests pass, ask the user if questions arise.

- [x] 7. Phase 4 — Component extraction and ChannelView
  - A pure refactor with no visual change. Makes Property 7 assertable before the dashboard exists.

  - [x] 7.1 Extract the Mobile_Client KPI card
    - Move `_LiveReadingCard` and `_FlowingBadge` out of `flutter_app/lib/ui/sensors/widgets/sensor_page.dart` into a new `channel_kpi_card.dart`, publishing `_LiveReadingCard` as `ChannelKpiCard`
    - Add a `dense` flag controlling the KPI type size — 32 per WattVision §4 in a dashboard cell, larger in the carousel hero slot
    - _Requirements: 3.5, 4.6, 13.1_

  - [x] 7.2 Extract the Mobile_Client channel cards and shrink the sensor page
    - Move `_BalanceCard`, `_BranchShareCard`, `_TotalsCard`, `_EnvelopeExplainerCard` and `_ExplainRow` into a new `flutter_app/lib/ui/sensors/widgets/channel_cards.dart` as public widgets
    - Reduce `sensor_page.dart` to a composition of `ChannelKpiCard`, `AveragesRow` and the extracted cards
    - _Requirements: 4.6, 13.1_

  - [x] 7.3 Extract the Web_Client channel components
    - Move `SensorPage`, `Averages`, `WindowDetail`, `BalanceCard`, `BranchShareCard`, `TotalsCard` and `EnvelopeExplainer` out of `react_app/src/screens/SensorsTab.tsx` into `react_app/src/components/channel/` as exported components, with the same `dense` flag as 7.1
    - _Requirements: 3.5, 4.6, 13.1_

  - [x] 7.4 Reduce the Web_Client SensorsTab to carousel chrome
    - Leave only the topbar, the link chip, the status strip, the switcher and the carousel viewport in `react_app/src/screens/SensorsTab.tsx`, composing the extracted components
    - _Requirements: 4.1, 4.6_

  - [x] 7.5 Add the Mobile_Client per-channel projection
    - Create `flutter_app/lib/ui/sensors/channel_view.dart` with a pure `ChannelView.of(monitor, settings, index)` returning live flow, the live series, the three window stats, the device Status and the formatted strings
    - No widget or platform dependency, so the parity fixtures can exercise it directly
    - _Requirements: 4.6, 13.2_

  - [x] 7.6 Add the Web_Client per-channel projection
    - Create `react_app/src/core/channelView.ts` with the same signature and the same derivation order, so the two clients cannot drift
    - _Requirements: 4.6, 13.2_

  - [x] 7.7 Write property test for carousel/dashboard agreement
    - **Property 7: The carousel and the dashboard agree on every channel value**
    - Generators: telemetry — synthetic snapshots with flows in [0, 60] L/min and volumes in [0, 10^6] L across all six Status values; aggregates — window stats with coverage in [0, 1]; settings — cross product of flow unit, volume unit, tariff and locale; channel — integers [0, 2]
    - Invariant: for the live reading, Status, the three averages and the Bs_Equivalence, the string produced through the carousel path equals the string produced through the dashboard path — both resolve through the single `ChannelView`
    - **Validates: Requirements 4.6**

- [x] 8. Checkpoint — Phase 4
  - Run `npm run typecheck`, `npm run build` and `npx vitest --run` in `react_app/`
  - Run `flutter analyze` and `flutter test` in `flutter_app/`
  - Confirm the extraction produced no visual change at phone widths
  - Ensure all tests pass, ask the user if questions arise.

- [x] 9. Phase 5 — Dashboard_View
  - Composes the extracted components on the grid, moves the channel selection above the layout switch, and adds multi-series charts.

  - [x] 9.1 Create the shared layout composition fixture
    - Create `test_fixtures/layout/compositions.json` at the repository root, outside both client directories, describing the expected ordered cells and spans per Layout_Mode: Expanded 4·4·4 then 8+4, Medium 4·4·4 then 12 then 12
    - Both client suites read this file, so a composition divergence cannot pass
    - _Requirements: 3.1, 3.2, 3.3, 3.4, 13.1_

  - [x] 9.2 Add the Mobile_Client selection controller
    - Create `flutter_app/lib/state/selection_controller.dart` as a `ChangeNotifier` holding `int selectedChannel`, and provide it in `flutter_app/lib/main.dart` alongside `MonitorController` and `SettingsController` — above the layout switch so it survives a breakpoint change
    - Session-scoped, not persisted
    - _Requirements: 4.3, 4.4_

  - [x] 9.3 Add the Web_Client selection store
    - Create `react_app/src/state/selectionStore.ts` with the same `useSyncExternalStore` shape as `settingsStore`, holding `selectedChannel`
    - _Requirements: 4.3, 4.4_

  - [x] 9.4 Move the Mobile_Client carousel page index into the controller
    - In `flutter_app/lib/ui/sensors/sensors_tab.dart` remove `_SensorsTabState._page` and read `SelectionController` instead
    - Seed `PageController(initialPage:)` from the controller once at mount and make `onPageChanged` the sole writer — do not drive the page from a listener, or the controller notify / animate / write-back loop will feed back
    - _Requirements: 4.1, 4.3, 4.4_

  - [x] 9.5 Move the Web_Client carousel page index into the store
    - In `react_app/src/screens/SensorsTab.tsx` replace the local `useState` page with `selectionStore`, keeping the chevron and dot controls as the only writers
    - _Requirements: 4.1, 4.3, 4.4_

  - [x] 9.6 Add multi-series support to the Mobile_Client chart
    - In `flutter_app/lib/ui/common/charts.dart` add `FlowSparkline.multi({required List<List<double>> series, required List<Color> colors, ...})`, keeping the existing single-series constructor as a thin delegate so carousel call sites are untouched
    - Draw one area gradient per series in draw order; grid lines stay in the border token and strokes stay at width 2
    - _Requirements: 3.7, 3.8, 3.9_

  - [x] 9.7 Add multi-series support to the Web_Client chart
    - In `react_app/src/components/charts.tsx` add `series`/`colors` props to `Sparkline`, keeping `values`/`color` as an overload that wraps into single-element arrays
    - _Requirements: 3.7, 3.8, 3.9_

  - [x] 9.8 Build the Mobile_Client Dashboard_View
    - Create `flutter_app/lib/ui/dashboard/dashboard_view.dart` composing the KPI_Row (three `Grid12Cell(span: 4)`), the Main_Chart (span 8 in Expanded, 12 in Medium) and an Alerts_Panel slot (span 4 in Expanded, 12 in Medium) as a single `List<Grid12Cell>` built from the mode — data, not branching layout code
    - Add a `FilterChip` row above the chart for channel selection, independent of `selectedChannel`, with all three selectable at once
    - Put the three averages behind an in-place disclosure on the KPI card, and expose a Diagnostics_Sheet entry point
    - _Requirements: 3.1, 3.2, 3.3, 3.4, 3.5, 3.6, 3.9, 3.10_

  - [x] 9.9 Build the Web_Client Dashboard_View
    - Create `react_app/src/screens/DashboardView.tsx` with the same composition on `.grid12` using `.span-4` / `.span-8` / `.span-12`, the same `.chip[aria-pressed]` channel selectors, the same averages disclosure and the same Diagnostics_Sheet entry point
    - Reuse the existing `.panel` animation so Reduce_Motion needs no new CSS
    - _Requirements: 3.1, 3.2, 3.3, 3.4, 3.5, 3.6, 3.9, 3.10, 4.8_

  - [x] 9.10 Switch presentations by Layout_Mode in the Mobile_Client shell
    - In `flutter_app/lib/ui/shell/app_shell.dart` keep the two bottom tabs in Compact and switch to a left navigation rail with the same two destinations in Medium and Expanded, placed as a sibling of the `Stack` so the mounted tab layers never depend on `LayoutScope`
    - Swap `SensorsTab` for `DashboardView` through an `AnimatedSwitcher` keyed on `LayoutMode`, reusing the `Motion` tokens and the existing `reduceMotion` fallback to a plain fade with no positional interpolation
    - Retain the link, the buffered history and the active tab across the swap
    - _Requirements: 3.10, 4.1, 4.2, 4.5, 4.7, 4.8_

  - [x] 9.11 Switch presentations by Layout_Mode in the Web_Client
    - In `react_app/src/App.tsx` render `SensorsTab` in Compact and `DashboardView` in Medium/Expanded from the `useLayoutMode()` result, keeping exactly two bottom tabs in Compact and the same two destinations in the wider modes
    - _Requirements: 3.10, 4.1, 4.2, 4.5, 4.7, 4.8_

  - [x] 9.12 Write property test for selection continuity
    - **Property 5: Channel selection survives any sequence of Layout_Mode changes**
    - Generators: channel — integers [0, 2]; modeSequence — lists of length 1 to 10 drawn from the three Layout_Modes
    - Invariant: `selection.channel` unchanged across the sequence; after each transition the mounted presentation's initial channel equals it — Compact to wide and back is the identity
    - **Validates: Requirements 4.3, 4.4**

  - [x] 9.13 Write property test for live-state retention
    - **Property 6: Live state is retained across a Layout_Mode change**
    - Generators: fromMode, toMode — the three Layout_Modes; history — lists of 0 to 200 synthetic telemetry samples
    - Invariant: `linkState`, `liveSeries` contents and the active tab identifier are equal before and after the transition
    - **Validates: Requirements 4.5**

  - [x] 9.14 Write property test for cross-client layout composition
    - **Property 29: Both clients agree on layout composition**
    - Generators: mode — the three Layout_Modes, read from `test_fixtures/layout/compositions.json`
    - Invariant: each client's ordered cell list with spans equals the fixture exactly; both suites read the same file, so divergence cannot pass
    - **Validates: Requirements 13.1, 3.1, 3.2, 3.3, 3.4**

  - [x] 9.15 Write example tests for dashboard structure and chart rendering
    - Three carousel pages with working chevrons in Compact (4.1); exactly two bottom tabs in Compact (4.2); Diagnostics_Sheet reachable in Medium and Expanded (3.10)
    - All eight subsets of the three chart channels, which is exhaustive and therefore stronger than sampling (3.9)
    - Snapshot the chart's gradient stops and grid stroke in both clients (3.7, 3.8)
    - _Requirements: 3.7, 3.8, 3.9, 3.10, 4.1, 4.2_

- [x] 10. Checkpoint — Phase 5
  - Run `npm run typecheck`, `npm run build` and `npx vitest --run` in `react_app/`
  - Run `flutter analyze` and `flutter test` in `flutter_app/`
  - Confirm a drag-resize across a band boundary does not remount the tabs or reset the carousel
  - Ensure all tests pass, ask the user if questions arise.

- [x] 11. Phase 6 — Tariff, Cost_Formatter and locale
  - A strictly presentation-only layer over canonical litres. Nothing monetary reaches either database.

  - [x] 11.1 Build the Mobile_Client tariff model
    - Create `flutter_app/lib/core/money/tariff.dart` with `min` 0 exclusive, `max` 1000 inclusive, `defaultValue` 5.0, `decimals` 4, `quantise`, a sealed `TariffParse` (`TariffOk` / `TariffInvalid`), `parse`, `formatForEditing` (ungrouped, trailing zeros trimmed — the representation the round-trip is stated over) and `formatForDisplay` (grouped)
    - `parse` accepts `,` or `.` as the decimal separator regardless of locale, rejects strings containing both as ambiguous, and rejects non-numeric input, zero, negatives and values above 1000 with a message stating the accepted range; rejection leaves the persisted value untouched
    - _Requirements: 5.1, 5.3, 5.4, 5.5, 5.6, 12.5_

  - [x] 11.2 Build the Web_Client tariff model
    - Create `react_app/src/core/tariff.ts` with the identical constants, parse rules, rejection messages and two formatters
    - _Requirements: 5.1, 5.3, 5.4, 5.5, 5.6, 12.5_

  - [x] 11.3 Add Mobile_Client locale resolution
    - Create `flutter_app/lib/core/locale/app_locale.dart` resolving in order: explicit settings override, then the platform locale's language subtag from `PlatformDispatcher.instance.locale` if in `{es, en}`, then `en`
    - Set `Intl.defaultLocale` once at startup; catch a `NumberFormat`/`DateFormat` construction failure at resolution time, downgrade to `en` and record a diagnostic line rather than letting it surface inside a build method
    - Uses the existing `intl 0.20.3` dependency; add no package
    - _Requirements: 12.6_

  - [x] 11.4 Add Web_Client locale resolution
    - Create `react_app/src/core/locale.ts` with the same chain over `navigator.language`, `Intl.NumberFormat` and `Intl.DateTimeFormat`, and the same single-point fallback on construction failure
    - _Requirements: 12.6_

  - [x] 11.5 Build the Mobile_Client Cost_Formatter
    - Create `flutter_app/lib/core/money/cost_formatter.dart` accepting only canonical litres, computing `litres / 1000 * tariff`, and returning `'Bs. '` plus a locale-formatted two-decimal body — a literal prefix, not ICU `style: 'currency'`, because the BOB symbol varies by locale
    - Return null when display is disabled, so the absence is modelled in the type rather than by an empty string; return the existing `'--'` sentinel for NaN or infinite input
    - Place it beside `UnitFormatter`, never inside it, so no display unit can enter the call
    - _Requirements: 6.1, 6.3, 6.4, 6.6, 6.7, 6.8, 5.8, 12.1, 12.2, 12.3, 12.4_

  - [x] 11.6 Build the Web_Client Cost_Formatter
    - Create `react_app/src/core/cost.ts` with `createCostFormatter` following 11.5 exactly, beside `createFormatter` rather than inside it
    - _Requirements: 6.1, 6.3, 6.4, 6.6, 6.7, 6.8, 5.8, 12.1, 12.2, 12.3, 12.4_

  - [x] 11.7 Add the tariff and locale fields to the Mobile_Client settings
    - In `flutter_app/lib/data/settings/app_settings.dart` add `tariffBsPerCubicMetre` (5.0), `tariffConfiguredByUser` (false), `showCostEquivalence` (true) and `localeOverride` ('')
    - Persist all four in `flutter_app/lib/data/settings/settings_controller.dart`, falling back to the default and leaving `tariffConfiguredByUser` false when the stored tariff is corrupt, missing or out of range
    - Keep monetary values out of the reading database
    - _Requirements: 5.1, 5.2, 5.5, 5.7, 5.8, 6.8, 12.6_

  - [x] 11.8 Add the tariff and locale fields to the Web_Client settings
    - Add the same four fields to `react_app/src/state/settingsStore.ts` and `DEFAULT_SETTINGS`, with the same corrupt-value fallback
    - _Requirements: 5.1, 5.2, 5.5, 5.7, 5.8, 6.8, 12.6_

  - [x] 11.9 Add the Mobile_Client tariff controls
    - In `flutter_app/lib/ui/settings/settings_tab.dart` add a Tariff text control in Bs. per cubic metre labelled as an editable placeholder rather than a billed figure, a switch disabling Bs_Equivalence display, and a locale override
    - Revert the draft to the persisted value on blur after a rejected entry, and show the accepted-range message
    - Apply a committed value to every Bs_Equivalence within 320ms
    - _Requirements: 5.1, 5.2, 5.3, 5.4, 5.8, 12.5, 12.6_

  - [x] 11.10 Add the Web_Client tariff controls
    - The same three controls with the same wording and behaviour in `react_app/src/screens/SettingsTab.tsx`
    - _Requirements: 5.1, 5.2, 5.3, 5.4, 5.8, 12.5, 12.6_

  - [x] 11.11 Render the Bs_Equivalence beside every Mobile_Client volume figure
    - Apply the Cost_Formatter in `flutter_app/lib/ui/sensors/widgets/channel_cards.dart` (TotalsCard cumulative, 24 h and 7 d figures) and `averages_row.dart` (per-day, per-3-day, per-week volumes)
    - Render in the secondary text colour at the body type size next to the primary volume value, route through `AnimatedMetric` so changes interpolate when Reduce_Motion is off, and show the default-tariff-in-use indication when `tariffConfiguredByUser` is false
    - _Requirements: 6.1, 6.2, 6.5, 6.8, 6.9_

  - [x] 11.12 Render the Bs_Equivalence beside every Web_Client volume figure
    - The same treatment across `react_app/src/components/channel/*`, using the existing animated-number hook
    - _Requirements: 6.1, 6.2, 6.5, 6.8, 6.9_

  - [x] 11.13 Write property test for tariff validation
    - **Property 8: Tariff validation accepts exactly the stated range**
    - Generators: text — well-formed decimals in and out of range, the boundaries 0, 0.0001, 1000, 1000.0001, locale separators, strings with both separators, empty, whitespace, alphabetic, `NaN`, `Infinity`, leading/trailing whitespace
    - Invariant: acceptance is equivalent to the range predicate; on rejection the stored value equals the pre-call value and the message is non-empty
    - **Validates: Requirements 5.3, 5.4**

  - [x] 11.14 Write property test for the tariff round-trip
    - **Property 9: Tariff parse and format round-trip**
    - Generators: value — reals in (0, 1000] including values needing exactly 4 decimals and more; locale — `{es, en}`
    - Invariant: `parse(formatForEditing(quantise(v), locale), locale) == quantise(v)` exactly, and `quantise(v)` has at most 4 decimal places
    - **Validates: Requirements 5.5, 5.6, 12.5**

  - [x] 11.15 Write property test for the cost computation
    - **Property 10: Bs_Equivalence is the canonical volume in cubic metres times the Tariff, at two decimals**
    - Generators: litres — reals in [0, 10^7] including 0 and very small values; tariff — reals in (0, 1000]; locale — `{es, en}`
    - Invariant: output matches the `Bs. ` prefix; parsing the body with the locale's separators recovers `litres / 1000 * tariff` rounded to two decimals; the body has exactly two fractional digits
    - **Validates: Requirements 6.3, 6.4**

  - [x] 11.16 Write property test for unit invariance
    - **Property 11: Bs_Equivalence is invariant under a change of displayed volume unit**
    - Generators: litres — reals in (0, 10^7]; tariff — reals in (0, 1000]; unitA, unitB — distinct volume units
    - Invariant: the cost string is identical for both units while the volume string differs; prevents a future refactor threading the display unit in
    - **Validates: Requirements 6.7, 13.8**

  - [x] 11.17 Write property test for disabling the cost display
    - **Property 12: Disabling cost display suppresses the Bs_Equivalence and nothing else**
    - Generators: litres — reals in [0, 10^7]; enabled — booleans
    - Invariant: `format(litres) == null` iff `!enabled`; the volume string is identical in both cases
    - **Validates: Requirements 5.8, 6.1**

  - [x] 11.18 Write property test for locale resolution
    - **Property 22: Locale resolution is total and falls back to English**
    - Generators: tag — `es`, `es-BO`, `es-419`, `en`, `en-US`, `pt-BR`, `qq`, empty strings, whitespace, malformed values
    - Invariant: the result is always in `{es, en}`; `es` iff the language subtag is `es`; otherwise `en`
    - **Validates: Requirements 12.6**

  - [x] 11.19 Write property test for locale formatting versus the currency prefix
    - **Property 23: The number body is locale-formatted and the currency prefix is not**
    - Generators: amount — reals in [0, 10^7] including values above 999 so grouping appears; locale — `{es, en}`
    - Invariant: in `es` the decimal separator is `,` and grouping is `.`; in `en` reversed; in both the output begins with `Bs. `
    - **Validates: Requirements 12.1, 12.2, 12.3, 12.4**

  - [x] 11.20 Write property test for canonical storage invariance
    - **Property 28: Canonical storage is invariant under display configuration**
    - Generators: sequence — 1 to 500 synthetic telemetry samples; config — the cross product of flow units, volume units, tariffs and locales
    - Invariant: the persisted row set is equal across all configurations; the row key set contains no monetary key
    - **Validates: Requirements 5.7, 6.6, 13.8**

- [x] 12. Checkpoint — Phase 6
  - Run `npm run typecheck`, `npm run build` and `npx vitest --run` in `react_app/`
  - Run `flutter analyze` and `flutter test` in `flutter_app/`
  - Confirm no monetary field appears in either database schema or in any written row
  - Ensure all tests pass, ask the user if questions arise.

- [ ] 13. Phase 7 — Alerts_Panel
  - A read-only projection over the event log that already exists in both databases. No schema change and no migration.

  - [x] 13.1 Add the WATCH event kind to the Mobile_Client model
    - Add `EventKind.watchRaised` to `flutter_app/lib/data/models/stored_reading.dart`; `events.kind` is `TEXT` in SQLite so this is additive
    - _Requirements: 7.3, 13.7_

  - [ ] 13.2 Add the WATCH event kind to the Web_Client model
    - Add `'WATCH_RAISED'` to the `EventKind` union in `react_app/src/data/db.ts`, leaving the IndexedDB version and schema unchanged
    - _Requirements: 7.3, 13.7_

  - [x] 13.3 Log the WATCH transition and add the alerts append hook in the Mobile_Client
    - **This is the only edit this feature makes inside alarm-adjacent code. Review it carefully.** No condition, threshold or status value may change
    - In `flutter_app/lib/state/monitor_controller.dart` add one `_logEvent(EventKind.watchRaised, ...)` call inside the existing `case LeakStatus.watch:` branch of `_handleStatusTransition`, which already executes only on a genuine transition and therefore cannot flap
    - Give `_logEvent` an append hook that pushes the same in-memory `LeakEvent` onto the head of the alerts list and fires the alerts notifier after the write resolves, so an entry appears in the same frame as the transition. If the database write fails, the in-memory append still happens and the failure goes to the raw log
    - Leave the device-reported Status and the alarm interpretation untouched
    - _Requirements: 7.3, 7.9, 13.9_

  - [ ] 13.4 Log the WATCH transition and add the alerts append hook in the Web_Client
    - The same additive change in `react_app/src/state/monitorStore.ts` — one `logEvent('WATCH_RAISED', ...)` inside the existing `current === 'WATCH'` branch, plus the same append hook in `logEvent`
    - _Requirements: 7.3, 7.9, 13.9_

  - [x] 13.5 Add the Mobile_Client alerts projection
    - Create `flutter_app/lib/state/alerts_controller.dart` as its own `ChangeNotifier` that notifies only on append or reload, so the 1 Hz telemetry stream never reaches the panel
    - Query the database exactly twice per session — once on initialise, once on manual refresh; project `AlertEntry` (ts, kind, status, channelName, summary, severity, affordance), filter to the alert-worthy kinds and exclude connection noise, order newest-first, bound the in-memory list at 200 with oldest-evicted
    - Map `LEAK_RAISED` and `FAULT_RAISED` to `alarm` severity; project an unrecognised kind as `info` with the raw kind as its summary rather than dropping it
    - Name the inlet channel for balance-derived entries, and the carried channel where an event has one
    - _Requirements: 7.1, 7.2, 7.4, 7.9_

  - [ ] 13.6 Add the Web_Client alerts projection
    - Create `react_app/src/state/alertsStore.ts` with its own `useSyncExternalStore` subscription, separate from `monitorStore`, and the same projection, ordering, filtering, bounding and severity mapping
    - _Requirements: 7.1, 7.2, 7.4, 7.9_

  - [x] 13.7 Build the Mobile_Client Alerts_Panel
    - Create `flutter_app/lib/ui/dashboard/alerts_panel.dart` rendering Alert_Entry rows with timestamp (locale date and time conventions), channel name, Status, summary and a Status_Affordance
    - Use the existing `SurfaceCard(leadingAccentBar: true)` §3 alert treatment for `alarm` severity: `#3A1C1C` fill, `#FF453A` text, 4-wide left border in `#FF453A`
    - Bound the height with `ConstrainedBox` + inner `ListView` so it scrolls independently of the Main_Chart in Expanded; show an empty state with a retry control when the list is empty or the initial query failed
    - _Requirements: 7.1, 7.2, 7.4, 7.5, 7.6, 7.8, 12.7_

  - [ ] 13.8 Build the Web_Client Alerts_Panel
    - Create `react_app/src/components/AlertsPanel.tsx` with the same rows, the same `.banner` left-border alert treatment, `max-height` plus `overflow-y: auto` for independent scrolling, and the same empty state
    - _Requirements: 7.1, 7.2, 7.4, 7.5, 7.6, 7.8, 12.7_

  - [x] 13.9 Make the alerts list reachable in Mobile_Client Compact
    - Add an entry point from the Sensors tab in `flutter_app/lib/ui/sensors/sensors_tab.dart` that opens the panel as a sheet, so no third bottom tab is added and Requirement 4.2 stays satisfied
    - _Requirements: 7.7, 4.2_

  - [ ] 13.10 Make the alerts list reachable in Web_Client Compact
    - The same sheet entry point from `react_app/src/screens/SensorsTab.tsx`, keeping exactly two bottom tabs
    - _Requirements: 7.7, 4.2_

  - [x] 13.11 Write property test for alert ordering and completeness
    - **Property 13: The Alerts_Panel is ordered newest-first and loses nothing**
    - Generators: events — lists of 0 to 200 records drawn from every `EventKind`, timestamps in arbitrary order including equal values
    - Invariant: `ts[i] >= ts[i+1]` for every adjacent pair; the output multiset equals the input filtered to the alert-worthy kinds; no non-alert kind appears
    - **Validates: Requirements 7.1, 7.9**

  - [x] 13.12 Write property test for alert entry completeness
    - **Property 14: Every Alert_Entry carries a complete, non-empty presentation**
    - Generators: event — records across every `EventKind`, with empty and very long messages, missing optional balance and threshold values, and every sensor-name configuration
    - Invariant: formatted timestamp, channel name, Status, summary and Status_Affordance all present and non-empty; `status` is a member of the Status vocabulary
    - **Validates: Requirements 7.2, 7.6**

  - [x] 13.13 Write property test for transition-to-entry cardinality
    - **Property 15: Every qualifying Status transition produces exactly one Alert_Entry**
    - Generators: fromStatus, toStatus — the Status vocabulary including the unknown state
    - Invariant: the entry count increases by exactly 1 when `from != to` and `to` is in {WATCH, LEAK, FAULT, CAL}, and by 0 otherwise; the appended entry's Status equals `toStatus`
    - **Validates: Requirements 7.3**

- [ ] 14. Checkpoint — Phase 7
  - Run `npm run typecheck`, `npm run build` and `npx vitest --run` in `react_app/`
  - Run `flutter analyze` and `flutter test` in `flutter_app/`
  - Drive the simulator through every status in both clients and confirm the alarm logic and thresholds are byte-identical to before the WATCH logging change
  - Confirm the Alerts_Panel does not re-render at 1 Hz
  - Ensure all tests pass, ask the user if questions arise.

- [ ] 15. Phase 8 — Table styling, Icon_Language and accessibility
  - The remaining presentation detail, including the single-pass emoji replacement in the Web_Client.

  - [x] 15.1 Add the Mobile_Client table row primitive
    - Create `flutter_app/lib/ui/common/data_table_row.dart` on `FocusableActionDetector`, surfacing `onShowHoverHighlight` and `onShowFocusHighlight` through one widget, applying the `surfaceRaised` `#252525` background on hover and on focus plus a visible focus indicator, with a 1 bottom border in `#2C2C2E`
    - _Requirements: 8.1, 8.2, 8.3_

  - [ ] 15.2 Add hover and focus row styling to the Web_Client
    - In `react_app/src/styles/global.css` extend `.table tr:hover td` to `.table tr:focus-within td`, keep the existing global `:focus-visible` outline as the focus indicator, add `.mono` and `text-align: right` for numeric cells, and add an `overflow-x: auto` table wrapper for Compact with no font-size reduction below `--size-label`
    - _Requirements: 8.1, 8.2, 8.3, 8.5, 8.7_

  - [x] 15.3 Restyle the Mobile_Client Calibration_Table
    - In `flutter_app/lib/ui/diagnostics/diagnostics_sheet.dart` render the baseline dataset with the plain `Table` widget and explicit `columnWidths` rather than `DataTable`, whose imposed row heights and theming would fight the tokens
    - Use `DataTableRow` per row, mono type with trailing alignment for numeric columns, and wrap in a horizontal `SingleChildScrollView` in Compact
    - Present the protocol-reported values unmodified
    - _Requirements: 8.1, 8.2, 8.3, 8.5, 8.6, 8.7, 13.10_

  - [ ] 15.4 Restyle the Web_Client Calibration_Table
    - In `react_app/src/components/DiagnosticsSheet.tsx` give rows `tabindex="0"`, apply the mono/right-aligned numeric columns and the Compact scroll wrapper, and keep the values exactly as reported
    - _Requirements: 8.1, 8.2, 8.3, 8.5, 8.6, 8.7, 13.10_

  - [x] 15.5 Apply the row primitive to Mobile_Client Alert_Entry rows
    - Use `DataTableRow` for the rows in `flutter_app/lib/ui/dashboard/alerts_panel.dart` — one primitive, two call sites
    - _Requirements: 8.4_

  - [ ] 15.6 Apply the row styling to Web_Client Alert_Entry rows
    - Use the same border and hover/focus background in `react_app/src/components/AlertsPanel.tsx`
    - _Requirements: 8.4_

  - [x] 15.7 Author the five shared domain icons
    - Create `design/icons/droplet.svg`, `valve.svg`, `gauge.svg`, `pipe.svg` and `wave.svg` as the single source of path data, plus `test_fixtures/icons/manifest.json` listing the shared glyph keys so both clients can be asserted to agree
    - _Requirements: 10.1, 10.3_

  - [x] 15.8 Expose the icon vocabulary in the Mobile_Client
    - Create `flutter_app/lib/ui/common/icon_language.dart` rendering the five domain glyphs as `Path` objects through a small `CustomPainter` — no `flutter_svg` dependency — exposed as a named `AppIcon` API, sized on the spacing or type scale and coloured from the tokens
    - Declare the separate closed set of structural glyphs (chevron, close, check, plus, refresh, expand) that stay as Material icons and are exempt from the domain vocabulary
    - _Requirements: 10.1, 10.2, 10.3, 10.5_

  - [ ] 15.9 Expose the icon vocabulary in the Web_Client
    - Create `react_app/src/components/icons.tsx` with inline `<svg>` components built from the same `design/icons/*.svg` path data, plus the same structural set
    - _Requirements: 10.1, 10.2, 10.3, 10.5_

  - [ ] 15.10 Replace every Web_Client emoji with a real glyph in one pass
    - Change the `icon` field of `react_app/src/components/statusVisuals.ts` from an emoji string to a glyph key, and update the `Banner` and `StatusBanner` props in `src/components/primitives` that consume it
    - Replace the emoji in `src/App.tsx` (`💧`, `⚙`), `src/screens/SensorsTab.tsx` (`⚕`, `🧪`, `📡`), `src/screens/SettingsTab.tsx` (`⚕`, `✓`, `⃠`), `src/components/DiagnosticsSheet.tsx` and `src/screens/ConnectionGate.tsx`
    - Do this as a single pass, because `statusVisuals.ts` exists specifically to keep status presentation consistent; pair every meaningful icon with a text label or accessible name
    - _Requirements: 10.1, 10.2, 10.4, 10.5_

  - [x] 15.11 Replace the out-of-vocabulary Mobile_Client icons
    - Swap `Icons.monitor_heart_outlined` in `flutter_app/lib/ui/sensors/sensors_tab.dart` and `Icons.cable_outlined` for approved domain glyphs from `AppIcon`, and pair each with a label or tooltip
    - _Requirements: 10.1, 10.2, 10.4_

  - [x] 15.12 Mobile_Client accessibility pass
    - Add an accessible name and current value to every KPI readout and every Bs_Equivalence in `channel_kpi_card.dart`, `channel_cards.dart`, `averages_row.dart` and `dashboard_view.dart`
    - Ensure interactive targets are at least 44 by 44 in Compact
    - Use `FittedBox(fit: scaleDown)` on KPI numerals and keep every text-bearing container on intrinsic height, so a 200% text scale grows a `Wrap` run instead of clipping — deliberately without reading the platform text scale
    - _Requirements: 11.5, 11.8, 11.9, 11.10_

  - [ ] 15.13 Web_Client accessibility pass
    - Make the KPI cards, the Main_Chart channel selectors, the Alert_Entry rows and every Settings control keyboard-reachable and operable with a visible focus indicator at 3:1 against the adjacent background
    - Add accessible names and values for every KPI readout and Bs_Equivalence; keep no fixed-height container around text
    - _Requirements: 11.5, 11.7, 11.8, 11.9, 11.10_

  - [x] 15.14 Write property test for Status affordances
    - **Property 18: Every Status presentation carries a non-colour affordance**
    - Generators: status — the six Status values plus the unknown state; component — the status pill, the status banner, the KPI card and the Alert_Entry row
    - Invariant: the rendered output contains a non-empty affordance token, and any two distinct Status values produce different affordances
    - **Validates: Requirements 1.11, 7.6, 11.5**

  - [x] 15.15 Write property test for the Calibration_Table round-trip
    - **Property 24: The Calibration_Table presents the firmware dataset unmodified**
    - Generators: rows — lists of 0 to 32 baseline rows with inlet, expected and margin values in [0, 100] including zeros and values needing rounding
    - Invariant: parsing each rendered numeric cell recovers the input value rounded to that cell's declared precision; row count and order match the input
    - **Validates: Requirements 8.6, 8.5**

  - [x] 15.16 Write example tests for interaction and scaling
    - Hover and keyboard focus on a table row producing the `#252525` background and a visible outline (8.2, 8.3)
    - A keyboard tab-order pass over the dashboard and the settings tab (11.7)
    - A render at 2.0 text scale in each Layout_Mode asserting no overflow (11.10)
    - Both clients reference the same glyph key for the same meaning, read from `test_fixtures/icons/manifest.json` (10.3)
    - _Requirements: 8.2, 8.3, 10.3, 11.7, 11.10_

- [ ] 16. Checkpoint — Phase 8
  - Run `npm run typecheck`, `npm run build` and `npx vitest --run` in `react_app/`
  - Run `flutter analyze` and `flutter test` in `flutter_app/`
  - Confirm all five Diagnostics_Sheet sections are still present in both clients
  - Ensure all tests pass, ask the user if questions arise.

- [ ] 17. Phase 9 — Parity fixtures and full verification

  - [x] 17.1 Create the shared parity fixtures
    - Create `test_fixtures/parity/*.json` at the repository root, outside both client directories so neither owns them
    - Each case supplies a settings configuration (flow unit, volume unit, tariff, locale, sensor names), a sequence of real protocol `lines` so both parsers are exercised, pre-built `windowStats` so no database is needed, and `expected` values as **formatted strings** — the strongest available cross-language assertion, catching numeric and separator divergence in one comparison without depending on float representation matching between Dart and JavaScript
    - Cover at least: a slow leak in `es`, the same in `en`, an idle system, a fault, and a calibration run
    - _Requirements: 13.2_

  - [x] 17.2 Write the Mobile_Client cross-client parity property test
    - **Property 30: Both clients agree on every derived value for the same telemetry**
    - Generators: case — every case in `test_fixtures/parity/*.json`, read with `File`
    - Invariant: for every assertion point, the client's formatted output equals the fixture's expected string — Status, live readings, per-day, per-3-day and per-week averages, and Bs_Equivalence
    - **Validates: Requirements 13.2**

  - [ ] 17.3 Write the Web_Client cross-client parity property test
    - **Property 30: Both clients agree on every derived value for the same telemetry**
    - Generators: the same fixture cases, read with `node:fs` in a Node-environment Vitest test
    - Invariant: identical to 17.2, against the same file, so a divergence between the clients cannot pass
    - **Validates: Requirements 13.2**

  - [x] 17.4 Write the non-regression tests
    - **Property 27: The Connection_Gate verdict is unchanged**
    - Generators: linkState — every `LinkState` value; requireConnection — booleans; historyOnly — booleans
    - Invariant: `grantsAccess == linkState.grantsAccess || (!requireConnection && historyOnly)`
    - Add example tests alongside it for the preserved Diagnostics_Sheet contents (13.10) and the unchanged logging interval, retention and pruning behaviour (13.7)
    - **Validates: Requirements 13.6, 13.7, 13.10**

  - [x] 17.5 Run the full verification matrix and fix what it finds
    - `react_app`: `npm run typecheck` (0 errors), `npm run build` (0 errors), `npx vitest --run` (all pass)
    - `flutter_app`: `flutter analyze` (0 errors), `flutter test` (all pass)
    - Confirm nothing under `firmware/` changed, and that the wire protocol, both database schemas and the alarm logic are untouched
    - Drive both clients through the in-process simulator across every status, since neither has ever been tested against real hardware and the simulator already reproduces the firmware's decision logic
    - _Requirements: 13.3, 13.4, 13.5, 13.6, 13.7, 13.8, 13.9, 13.10_

  - [x] 17.6 Generate the Flutter native host projects
    - Run `flutter create . --platforms=android,ios` in `flutter_app/`; the native projects have never been generated
    - Apply the Bluetooth and location permission entries documented in `flutter_app/PLATFORM_SETUP.md` to the generated `AndroidManifest.xml` and `Info.plist`
    - Deferred deliberately: this is required before the app can run on a device but is not required for `flutter analyze` or `flutter test`, so it does not block any earlier phase
    - _Requirements: 13.5_

- [x] 18. Final checkpoint
  - Ensure all tests pass, ask the user if questions arise.

## Notes

- Tasks marked with `*` are optional and can be skipped for a faster MVP. The compliance-suite infrastructure in phase 1 — the harness, the token registries, the literal-colour scanners and the fixed-constant assertions — is **not** optional, because Requirements 1.2 through 1.7 make it the deliverable rather than a test of one.
- Each task references specific requirements for traceability, and each property test names its design property number and title so the implementer does not re-derive it.
- Flutter and React sub-tasks for the same piece of work share a parent and sit adjacent, so a Requirement 13.1 or 13.2 parity break surfaces in the phase that caused it.
- Task 13.3 and 13.4 are the only edits inside alarm-adjacent code. They are strictly additive and require careful review.
- Task 5.7 is the highest-risk change in the feature. The width caps are relocated to Compact scope, never deleted.
- Task 1.1 and 1.3 are real verification steps, not assumptions: no Flutter SDK was available when the requirements and design were written, so `flutter pub get` may fail and the `glados` decision is genuinely open.

## Task Dependency Graph

```json
{
  "waves": [
    { "id": 0, "tasks": ["1.1", "1.2"] },
    { "id": 1, "tasks": ["1.3", "1.4", "1.5", "1.6", "1.7"] },
    { "id": 2, "tasks": ["1.8", "1.9", "1.10", "1.11"] },
    { "id": 3, "tasks": ["1.12"] },
    { "id": 4, "tasks": ["3.1", "3.2"] },
    { "id": 5, "tasks": ["3.3", "3.4"] },
    { "id": 6, "tasks": ["3.5", "3.6"] },
    { "id": 7, "tasks": ["3.7", "3.8"] },
    { "id": 8, "tasks": ["3.9", "3.10", "3.11", "3.12", "3.13", "3.14"] },
    { "id": 9, "tasks": ["5.1", "5.2"] },
    { "id": 10, "tasks": ["5.3", "5.4"] },
    { "id": 11, "tasks": ["5.5", "5.6"] },
    { "id": 12, "tasks": ["5.7", "5.8"] },
    { "id": 13, "tasks": ["5.9", "5.10", "5.11", "5.12", "5.13"] },
    { "id": 14, "tasks": ["7.1", "7.3"] },
    { "id": 15, "tasks": ["7.2", "7.4"] },
    { "id": 16, "tasks": ["7.5", "7.6"] },
    { "id": 17, "tasks": ["7.7"] },
    { "id": 18, "tasks": ["9.1", "9.2", "9.3"] },
    { "id": 19, "tasks": ["9.4", "9.5", "9.6", "9.7"] },
    { "id": 20, "tasks": ["9.8", "9.9"] },
    { "id": 21, "tasks": ["9.10", "9.11"] },
    { "id": 22, "tasks": ["9.12", "9.13", "9.14", "9.15"] },
    { "id": 23, "tasks": ["11.1", "11.2", "11.3", "11.4"] },
    { "id": 24, "tasks": ["11.5", "11.6"] },
    { "id": 25, "tasks": ["11.7", "11.8"] },
    { "id": 26, "tasks": ["11.9", "11.10"] },
    { "id": 27, "tasks": ["11.11", "11.12"] },
    { "id": 28, "tasks": ["11.13", "11.14", "11.15", "11.16", "11.17", "11.18", "11.19", "11.20"] },
    { "id": 29, "tasks": ["13.1", "13.2"] },
    { "id": 30, "tasks": ["13.3", "13.4"] },
    { "id": 31, "tasks": ["13.5", "13.6"] },
    { "id": 32, "tasks": ["13.7", "13.8"] },
    { "id": 33, "tasks": ["13.9", "13.10"] },
    { "id": 34, "tasks": ["13.11", "13.12", "13.13"] },
    { "id": 35, "tasks": ["15.1", "15.2", "15.7"] },
    { "id": 36, "tasks": ["15.3", "15.4", "15.8", "15.9"] },
    { "id": 37, "tasks": ["15.5", "15.6", "15.10", "15.11"] },
    { "id": 38, "tasks": ["15.12", "15.13"] },
    { "id": 39, "tasks": ["15.14", "15.15", "15.16"] },
    { "id": 40, "tasks": ["17.1"] },
    { "id": 41, "tasks": ["17.2", "17.3", "17.4"] },
    { "id": 42, "tasks": ["17.5"] },
    { "id": 43, "tasks": ["17.6"] }
  ]
}
```
