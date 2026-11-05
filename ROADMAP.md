# Proposed Technical Roadmap

These are potential improvements based on the current code and tests. They are not approved, scheduled, or commitments by the project owner. Estimates are engineering effort, not elapsed calendar time. No CI/CD work is included.

## Reliability and Error Handling — 4–6 hours

### Make persistent-store startup failures recoverable — 2–3 hours

- **Why:** `MarginRunApp` currently terminates with `fatalError` if SwiftData container creation fails. A clear recovery path would make startup failures easier to diagnose and less abrupt.
- **Areas:** `MarginRun/MarginRunApp.swift`, app root views, launch tests.
- **Acceptance:** Container creation failures are surfaced through a deliberate user-facing state; a test can inject a failing container factory; normal startup remains unchanged.
- **Status:** Verified behavior; improvement proposed.

### Review persistence save failure reporting — 2–3 hours

- **Why:** Check that every user-initiated create/edit/delete path reports persistence failures consistently and does not imply a save succeeded when it did not.
- **Areas:** `MarginRun/Views`, draft types, SwiftData model context call sites.
- **Acceptance:** A documented inventory of save paths exists; injected save failures retain entered data and present an actionable error; tests cover representative create, edit, and delete flows.
- **Status:** Investigation required; no specific user-visible defect verified in this audit.

## SwiftData Persistence — 3–5 hours

### Define a migration and recovery strategy — 3–5 hours

- **Why:** The models are SwiftData `@Model` types, but the repository has no explicit migration plan. Schema evolution should preserve existing user jobs, costs, and receipt references.
- **Areas:** `MarginRun/Models`, `MarginRun/MarginRunApp.swift`, persistence tests.
- **Acceptance:** A versioned schema and migration plan are documented; a migration test opens a fixture from the previous schema and verifies relationships and values; recovery behavior for a damaged store is documented.
- **Status:** Potential future need; no migration failure verified.

## Receipt OCR and Validation — 3–5 hours

### Expand OCR validation against realistic receipt layouts — 3–5 hours

- **Why:** OCR output varies with layout, lighting, locale, and currency formatting. Existing tests cover the OCR service, but broader fixtures can identify where users need correction before saving.
- **Areas:** `MarginRun/Receipt/ReceiptOCRService.swift`, `MarginRun/Views/AddExpenseView.swift`, `MarginRunTests/ReceiptOCRServiceTests.swift`.
- **Acceptance:** A privacy-safe synthetic fixture set covers multiple layouts and number formats; extraction confidence and field validation are tested; uncertain values remain editable and are never silently accepted as certain.
- **Status:** Improvement proposal; accuracy investigation required.

## Labor Timer and Live Activity — 3–5 hours

### Exercise timer restoration and ActivityKit edge cases — 3–5 hours

- **Why:** The timer reconciles persisted state with ActivityKit state. More lifecycle coverage can protect elapsed time through app termination, denied Live Activities, and stale activity state.
- **Areas:** `MarginRun/Labor/LaborTimerStore.swift`, `LaborLiveActivityManager.swift`, `LaborLiveActivityReconciler.swift`, `MarginRunWidgets`, `MarginRunTests/LaborLiveActivityTests.swift`.
- **Acceptance:** Deterministic tests cover relaunch, stale/missing activities, permission denial, and repeated start/stop; a manual device checklist documents behavior when Live Activities are unavailable.
- **Status:** Existing reconciliation logic and tests verified; added edge coverage is proposed.

## Testing — 5–7 hours

### Add end-to-end financial lifecycle coverage — 3–4 hours

- **Why:** Unit coverage exists for calculations and drafts. A lifecycle test can ensure edits to expenses, labor, and revenue update job and portfolio summaries together.
- **Areas:** `MarginRun/Views/JobDetailView.swift`, `InsightsView.swift`, `MarginRunTests`, `MarginRunUITests`.
- **Acceptance:** Tests create a job, add and edit costs/revenue, complete it, and verify the resulting margin and portfolio summaries; fixtures avoid live services.
- **Status:** Coverage opportunity; no failure verified.

### Improve UI test stability and accessibility identifiers — 2–3 hours

- **Why:** UI tests depend on visible copy and UI layout. A review of identifiers and navigation waits can reduce fragile tests and improve accessibility automation.
- **Areas:** `MarginRun/Views`, `MarginRunUITests/MarginRunUITests.swift`.
- **Acceptance:** Critical controls have stable identifiers; tests prefer semantic identifiers for navigation/actions; repeated simulator runs show no timing-dependent failures.
- **Status:** Proposed investigation.

## Accessibility and User Experience — 4–6 hours

### Audit VoiceOver, Dynamic Type, and contrast for core flows — 4–6 hours

- **Why:** Job creation, expense entry, and paywall decisions carry important financial information. Users should be able to complete them with assistive technologies and larger text.
- **Areas:** `MarginRun/Views/CreateJobView.swift`, `AddExpenseView.swift`, `JobDetailView.swift`, `InsightsView.swift`, `Purchases/MarginRunPaywall.swift`.
- **Acceptance:** VoiceOver labels and reading order are reviewed for core flows; key screens remain usable at accessibility text sizes; contrast issues found are corrected without changing business rules; a manual verification checklist is recorded.
- **Status:** Audit not yet performed; no accessibility defect asserted.

## Documentation and Maintainability — 3–5 hours

### Document privacy boundaries and local data lifecycle — 2–3 hours

- **Why:** The app stores receipt images locally and sends product analytics. Contributors need a precise explanation of what stays on device, what leaves it, and how deletion behaves.
- **Areas:** `MarginRun/Storage/ReceiptStorage.swift`, `MarginRun/Analytics`, `MarginRun/Models`, README and privacy documentation.
- **Acceptance:** A data-flow document lists locally stored fields/files, outbound analytics properties, retention/deletion behavior, and integration endpoints; claims are verified against code.
- **Status:** Proposed; requires product/privacy owner review.

### Add contributor setup and troubleshooting notes — 1–2 hours

- **Why:** The project relies on Xcode-managed packages and external dashboards for full subscription behavior.
- **Areas:** `README.md`, `MarginRun/Purchases/RevenueCatConfig.swift`, Xcode project settings.
- **Acceptance:** A fresh contributor can build and run local flows from documented steps; simulator/runtime and third-party service limitations are clear; no secrets are requested in source control.
- **Status:** Documentation created in this preparation; follow-up verification remains useful.

## Estimated Effort

The ranges above total approximately **25–39 hours**. The total is a planning estimate for plausible future engineering, not work already performed or a commitment. The accessibility, persistence, and OCR investigations may adjust their estimates after implementation details are validated.
