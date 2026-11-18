# Turnproof Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship Turnproof v1 — an offline iPhone app that turns a room-by-room rental walkthrough into a tenant-signed, hash-sealed PDF condition report, monetized by a hard paywall.

**Architecture:** Feature-first SwiftUI app on SwiftData. A thin domain layer (inspection state machine, photo ingest, integrity hashing, PDF layout) holds all logic and is injected with a `Clock` and a `PhotoSource`, so every rule is unit-testable without a simulator session. The UI is dumb SwiftUI on top of those services. StoreKit 2 + a Keychain free-report counter gate export, not data entry.

**Tech Stack:** Swift 6, SwiftUI, SwiftData, PDFKit, CoreImage (QR), CryptoKit, StoreKit 2, BaseNavigationStack, XcodeGen, Swift Testing for units, XCTest/XCUITest for UI, SnapshotTesting-style image capture in UITests.

**Spec:** `docs/superpowers/specs/2026-11-18-turnproof-design.md`

## Global Constraints

- iPhone only, portrait, iOS 18.0 deployment target, `TARGETED_DEVICE_FAMILY = "1"`.
- No third-party SDKs. No network calls in v1. AppUpdateKit is not installed.
- Environments Dev/Staging/Prod per `ios-new-app`; only `<App>-Dev` owns tests.
- `AppConfiguration.environment` is the only env switch; per-env values live in `Config/*.xcconfig`.
- Bundle id `com.iletai.turnproof`; Dev/Staging suffixes `.dev` / `.staging`.
- Product copy: "condition report", "evidence packet"; never "legally binding" or "legal advice".
- Free allowance: exactly one completed report, counter in Keychain (`turnproof.free_reports.v1`).
- Photos: max 40 per inspection, longest edge 1600 px, JPEG 0.75; packet target < 20 MB.
- PDF localized en-US and vi; the sealed packet is immutable, corrections create a new revision.
- All user-facing strings via `String(localized:)`; keys extracted into `Localizable.xcstrings`.
- Custom Info.plist keys only in `project.yml` `info.properties`, never `INFOPLIST_KEY_*`.

## Review Focus

These are the inputs and conditions the spec implies but no happy-path test covers. Each has a test named in the owning task.

1. A corrupt, HEIC-with-alpha, or 50 MP photo arrives from the library — ingest must downscale and re-encode without OOM or crash.
2. User text is empty, whitespace-only, 200 characters long, or full Vietnamese diacritics — PDF captions truncate and never overflow a page.
3. The app is killed mid-capture or mid-signature — the inspection reopens as a draft, nothing is sealed, no orphan report exists.
4. Device clock is wrong, moved backwards, or in the future — hashes and captions stay internally consistent and verifiable.
5. Entitlement is absent, restored, or expires mid-inspection — data is never lost, and export is gated exactly at seal time.

---

### Task 0: Scaffold and Gate 0

**Files:**
- Create: whole project at `~/orca/projects/turnproof` via the generator
- Modify: `project.yml`, `App/PrivacyInfo.xcprivacy`, `Config/Secrets.xcconfig` (local only, gitignored)

**Interfaces:**
- Consumes: nothing.
- Produces: schemes `Turnproof-Dev`, `Turnproof-Staging`, `Turnproof`; targets `Turnproof`, `TurnproofTests`, `TurnproofUITests`; `Store` (from `--with storekit`) and `AppRouter` (from `--with nav`).

- [ ] **Step 1: Generate the project**

```bash
APPLE_TEAM_ID=<team> ~/.agents/skills/ios-new-app/scripts/new_app.sh Turnproof com.iletai.turnproof ~/orca/projects/turnproof --with storekit,nav
cd ~/orca/projects/turnproof && xcodegen generate
```

- [ ] **Step 2: Add camera/photo usage strings and privacy manifest entries**

In `project.yml` `info.properties`: `NSCameraUsageDescription`, `NSPhotoLibraryUsageDescription`. In `App/PrivacyInfo.xcprivacy`: `NSPrivacyAccessedAPICategoryFileTimestamp` reason `C617.1` (PDF export writes files) and the existing `UserDefaults` entry; no tracking, no collected data.

- [ ] **Step 3: Verify it builds both configs**

Run: `xcodebuild -scheme Turnproof-Dev -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build`
Expected: `BUILD SUCCEEDED`. Then repeat with `-scheme Turnproof -configuration Release-Prod`.

- [ ] **Step 4: Commit**

```bash
git add -A && git commit -m "chore: scaffold Turnproof from house template"
```

---

### Task 1: Design tokens from the Stitch pass

**Files:**
- Create: `App/DesignSystem/TurnproofTheme.swift`, `App/DesignSystem/Components/ConditionChip.swift`, `App/DesignSystem/Components/SectionHeader.swift`
- Test: `Tests/DesignSystem/ThemeContrastTests.swift`
- Reference: `docs/brand/DESIGN.md` exported from Stitch (Task 0 of the design run)

**Interfaces:**
- Produces: `enum TPColor`, `enum TPSpacing`, `enum TPType`, `struct TPCard<Content: View>`; `ConditionChip(condition: Condition, isSelected: Bool)`.

- [ ] **Step 1: Write the failing contrast test**

```swift
@Test func conditionChipColorsMeetContrast() {
    for c in Condition.allCases {
        #expect(TPColor.foreground(for: c).contrastRatio(against: TPColor.background(for: c)) >= 4.5)
    }
}
```

- [ ] **Step 2: Run it, expect failure** — `xcodebuild test -scheme Turnproof-Dev -only-testing:TurnproofTests/ThemeContrastTests`

- [ ] **Step 3: Implement the tokens** exactly matching `docs/brand/DESIGN.md` (hex values, type ramp, 4 pt spacing scale), plus `contrastRatio(against:)` using WCAG relative luminance.

- [ ] **Step 4: Run test, expect PASS**, then commit `feat: add design tokens from Stitch system`.

---

### Task 2: SwiftData model and repository

**Files:**
- Create: `App/Domain/Models/{Property,Inspection,Room,Finding,Signature,Report}.swift`, `App/Domain/InspectionRepository.swift`
- Test: `Tests/Domain/RepositoryTests.swift`

**Interfaces:**
- Produces: `@Model final class Property { var id: UUID; var label: String; var addressLine1: String; var unit: String?; var landlordName: String; var createdAt: Date }`; `Inspection { id, kind: InspectionKind, status: InspectionStatus, startedAt, sealedAt: Date?, tenantName, tenantEmail, inspectorName, revision: Int }`; `Room { id, templateKey, name, order }`; `Finding { id, order, photoData: Data, condition: Condition, note: String, isDamageFlagged: Bool, capturedAt: Date, exifTakenAt: Date? }`; `Signature { id, role: SignatureRole, pngData: Data, signedAt: Date }`; `Report { id, revision: Int, generatedAt: Date, sha256: String, pageCount: Int, pdfData: Data, supersedesID: UUID? }`.
- `protocol InspectionRepository { func properties() throws -> [Property]; func addProperty(label:...) throws -> Property; func inspections(for property: Property) throws -> [Inspection]; func startInspection(property:kind:clock:) throws -> Inspection; func delete(_ inspection: Inspection) throws }`
- Concurrency: repository is `@MainActor`; models are not `Sendable`, pass `PersistentIdentifier` across boundaries.

- [ ] **Step 1: Write failing tests** for: adding a property with whitespace-only label throws `RepositoryError.invalidLabel`; a started inspection has `status == .draft`, six template rooms in the documented order, `revision == 1`; deleting a property cascades to inspections, rooms, findings, signatures, reports.
- [ ] **Step 2: Run, expect failure.**
- [ ] **Step 3: Implement models + `SwiftDataInspectionRepository`** with an in-memory `ModelContainer` factory for tests.
- [ ] **Step 4: Run tests, expect PASS.** Commit `feat: add SwiftData model and repository`.

---

### Task 3: Inspection state machine and completion gate

**Files:**
- Create: `App/Domain/InspectionService.swift`
- Test: `Tests/Domain/InspectionServiceTests.swift`

**Interfaces:**
- Produces: `enum InspectionAction { case addFinding(roomID: UUID, photo: Data, condition: Condition, note: String, isDamageFlagged: Bool, exifTakenAt: Date?) ; case deleteFinding(UUID); case sign(role: SignatureRole, png: Data); case seal }`
- `struct InspectionService { init(clock: Clock); func apply(_ action: InspectionAction, to: Inspection) throws; func validation(for: Inspection) -> [ValidationIssue] }`
- `enum ValidationIssue: Equatable { case noRooms, emptyRoom(String), missingTenantSignature, missingLandlordSignature, unresolvedDamage(room: String, note: String), tooManyPhotos(Int) }`
- `enum InspectionError: Error { case sealed, notDraft, photoLimit, emptyNote }`

- [ ] **Step 1: Write failing tests** for: applying an action to a sealed inspection throws `.sealed`; a damage-flagged finding with an empty note yields `.unresolvedDamage` and `seal` throws `.emptyNote`; `seal` with 41 photos throws `.photoLimit`; `seal` without both signatures throws `.missingTenantSignature`; a valid inspection sets `status == .sealed`, `sealedAt == clock.now`.
- [ ] **Step 2: Run, expect failure.**
- [ ] **Step 3: Implement the service** as a pure reducer over the model graph; `validation(for:)` returns issues in a fixed order so the Review screen and tests agree.
- [ ] **Step 4: Run tests, expect PASS.** Commit `feat: add inspection state machine and seal gate`.

---

### Task 4: Photo ingest

**Files:**
- Create: `App/Domain/PhotoIngest.swift`, `App/Domain/PhotoSource.swift`
- Test: `Tests/Domain/PhotoIngestTests.swift`

**Interfaces:**
- Produces: `protocol PhotoSource { func capturePhoto() async throws -> Data; func pickFromLibrary() async throws -> Data }`; `struct PhotoIngest { static let maxEdge: CGFloat = 1600; func ingest(_ raw: Data) throws -> IngestedPhoto }`; `struct IngestedPhoto { let jpeg: Data; let exifTakenAt: Date? }`; `enum PhotoIngestError: Error { case undecodable, tooLargeAfterDownscale }`

- [ ] **Step 1: Write failing tests** using fixtures in `Tests/Fixtures/photos/`: a 4032×3024 HEIC, a PNG with alpha, a 50 MP JPEG, and a 12-byte corrupt file. Assert the three valid ones produce `jpeg.count < 600_000`, `max(pixelWidth, pixelHeight) <= 1600`, no alpha channel, and that the corrupt file throws `.undecodable`.
- [ ] **Step 2: Run, expect failure.**
- [ ] **Step 3: Implement** with `CGImageSourceCreateThumbnailAtIndex` (max pixel size 1600), flatten onto white, `CGImageDestination` JPEG 0.75. Read EXIF `DateTimeOriginal` when present.
- [ ] **Step 4: Run tests, expect PASS.** Commit `feat: add bounded photo ingest`.

---

### Task 5: Integrity manifest and hashing

**Files:**
- Create: `App/Domain/IntegrityService.swift`
- Test: `Tests/Domain/IntegrityServiceTests.swift`, `Tests/Fixtures/manifest-golden.json`

**Interfaces:**
- Produces: `struct IntegrityService { func manifest(for packet: ReportPacket, clock: Clock) throws -> Data; func digest(_ packet: ReportPacket, clock: Clock) throws -> String; func shortCode(_ digest: String) -> String /* 12 upper-case chars, grouped 4-4-4 */ func verify(_ report: Report, against packet: ReportPacket, clock: Clock) -> Bool }`
- `struct ReportPacket` is defined in Task 6; this task defines it (see Step 3) so both tasks compile.

- [ ] **Step 1: Write failing tests**: same packet + same clock produces byte-identical manifests; changing one finding note changes the digest; reordering rooms changes the digest (order is part of the evidence); the golden manifest matches `manifest-golden.json`; `shortCode` of a known digest is `A1B2-C3D4-E5F6`.
- [ ] **Step 2: Run, expect failure.**
- [ ] **Step 3: Implement** `ReportPacket` (property fields, inspection fields, `[RoomPacket]`, signatures with their SHA-256, report id, revision, pageCount) and canonical JSON encoding with `.sortedKeys` and ISO-8601 with milliseconds, then SHA-256 via CryptoKit. Images are hashed individually, never inlined.
- [ ] **Step 4: Run tests, expect PASS.** Commit `feat: add canonical manifest and evidence digest`.

---

### Task 6: PDF renderer

**Files:**
- Create: `App/Domain/PDF/{ReportPDFRenderer.swift,PDFLayout.swift}`
- Test: `Tests/Domain/PDFLayoutTests.swift`, `Tests/Fixtures/pdf/*.layout.txt`

**Interfaces:**
- Consumes: `ReportPacket`, `IntegrityService`.
- Produces: `protocol ReportRendering { func layout(for packet: ReportPacket) -> [PageLayout]; func render(_ packet: ReportPacket, digest: String) throws -> Data }`; `struct PageLayout: Equatable { let index: Int; let blocks: [LayoutBlock] }`; `struct LayoutBlock: Equatable { let kind: BlockKind; let rect: CGRect; let text: String? }`.

- [ ] **Step 1: Write failing tests**: a packet with 3 rooms and 9 photos produces cover + 3 room pages + signature + integrity = 6 pages; a room with 5 photos overflows to a second page with a "continued" header; a 200-character note truncates to 3 lines with an ellipsis; Vietnamese diacritics render with the same layout as a plain ASCII string of equal length; the `layout(for:)` text dump equals the golden file after rounding rects to 0.5 pt.
- [ ] **Step 2: Run, expect failure.**
- [ ] **Step 3: Implement** A4-ish US Letter pages (612×792), two-column grid, pinned PDF metadata (`creationDate = packet.generatedAt`, fixed document id derived from the digest), footer on every page, QR via `CIQRCodeGenerator` on the integrity page.
- [ ] **Step 4: Run tests, expect PASS**; open one rendered PDF in Preview and confirm it is readable. Commit `feat: add deterministic PDF packet renderer`.

---

### Task 7: Properties and property detail screens

**Files:**
- Create: `App/Features/Properties/{PropertiesListView.swift,AddPropertySheet.swift,PropertyDetailView.swift}`, `App/Features/Properties/PropertiesViewModel.swift`
- Test: `Tests/Features/PropertiesViewModelTests.swift`, snapshot case in `UITests/SnapshotTests.swift`

**Interfaces:**
- Consumes: `InspectionRepository`.
- Produces: accessibility ids `property.add`, `property.row.<uuid>`, `inspection.start`, `inspection.kind.<kind>`; `PropertiesViewModel` with `func addProperty(label:address:unit:) throws` and `var rows: [PropertyRow]`.

- [ ] **Step 1: Write failing unit tests**: adding a blank property surfaces an inline error and does not insert; adding a valid one inserts and selects it; the detail screen lists inspections newest-first.
- [ ] **Step 2: Run, expect failure**, then implement the view model and views with the empty state from the Stitch design.
- [ ] **Step 3: Add a UI snapshot test** that launches with `-UITestMode -UITestResetState` and captures the empty, populated, and detail screens for light/dark.
- [ ] **Step 4: Run both suites, expect PASS.** Commit `feat: add properties and property detail`.

---

### Task 8: Room checklist, capture, and review

**Files:**
- Create: `App/Features/Inspection/{RoomChecklistView.swift,CaptureView.swift,ReviewView.swift,InspectionFlowModel.swift}`
- Test: `Tests/Features/InspectionFlowModelTests.swift`, `UITests/InspectionFlowUITests.swift`

**Interfaces:**
- Consumes: `InspectionService`, `PhotoIngest`, `PhotoSource`.
- Produces: ids `room.<templateKey>`, `capture.shutter`, `capture.library`, `capture.condition.{good,fair,damaged}`, `capture.note`, `capture.damageFlag`, `review.next`, `review.issue.<n>`; `InspectionFlowModel.func capture(condition:note:flag:) async throws`.

- [ ] **Step 1: Write failing unit tests**: capture appends a finding to the selected room with `capturedAt == clock.now`; a failed ingest surfaces an alert and adds nothing; review exposes exactly the issues returned by `validation(for:)`, in order.
- [ ] **Step 2: Run, expect failure**, then implement.
- [ ] **Step 3: Write the UI test** for: add finding to Kitchen → condition damaged without a note → Review blocks with `review.issue.1` visible. (Camera is replaced by the fixture source under `-UITestMode`.)
- [ ] **Step 4: Run both suites, expect PASS.** Commit `feat: add room-by-room capture and review`.

**Review Focus coverage:** corrupt/oversized photo (unit, Task 4); 200-char and Vietnamese note (unit, Task 6); app killed mid-capture (UI test relaunches with `-UITestResumeDraft` and asserts the draft reopens with the prior finding).

---

### Task 9: Signature and seal

**Files:**
- Create: `App/Features/Sign/SignView.swift`, `App/Features/Sign/SignatureCanvas.swift`
- Test: `UITests/SignatureUITests.swift`

**Interfaces:**
- Consumes: `InspectionService.sign`.
- Produces: ids `sign.tenant`, `sign.landlord`, `sign.seal`; `SignatureCanvas` exposes `onChange: (Data?) -> Void` with a 600×200 PNG of the drawn strokes on transparent background.

- [ ] **Step 1: Write the failing UI test**: seal is disabled until both canvases have strokes; drawing in the tenant canvas enables only after the landlord canvas too; tapping seal shows the export screen.
- [ ] **Step 2: Run, expect failure**, then implement with `Canvas` + `DragGesture`, clearing per-role state on cancel.
- [ ] **Step 3: Run, expect PASS.** Commit `feat: add dual signature and seal`.

---

### Task 10: Export and verify

**Files:**
- Create: `App/Features/Export/{ExportView.swift,VerifyView.swift,ExportViewModel.swift}`
- Test: `Tests/Features/ExportViewModelTests.swift`

**Interfaces:**
- Consumes: `IntegrityService`, `ReportRendering`, `FreeReportCounter`, `Store`.
- Produces: ids `export.share`, `export.copyHash`, `verify.result`; `ExportViewModel.func build() async throws -> ExportArtifact` where `ExportArtifact { pdfURL: URL; digest: String; shortCode: String; pageCount: Int }`.

- [ ] **Step 1: Write failing tests**: building twice for the same sealed inspection returns the stored report and does not recompute a different digest; verifying an untouched report returns true; mutating a finding copy returns false; a report over 20 MB surfaces a `sizeWarning` but still exports.
- [ ] **Step 2: Run, expect failure**, then implement: write to `FileManager.default.temporaryDirectory/<reportID>.pdf`, share via `ShareLink`, copy the digest to the pasteboard.
- [ ] **Step 3: Run, expect PASS.** Commit `feat: add sealed export and verification`.

---

### Task 11: Hard paywall and Keychain allowance

**Files:**
- Create: `App/Domain/Entitlement/FreeReportCounter.swift`, `App/Features/Paywall/ExportGate.swift`
- Modify: `App/RootView.swift` (gate at the seal→export transition only)
- Test: `Tests/Domain/FreeReportCounterTests.swift`, `UITests/PaywallUITests.swift`

**Interfaces:**
- Produces: `protocol AllowanceStoring { func count() -> Int; func increment() }`; `struct FreeReportCounter: AllowanceStoring` backed by Keychain service `com.iletai.turnproof.allowance`, key `turnproof.free_reports.v1`; `ExportGate.allowsExport(isPro: Bool, counter: AllowanceStoring) -> Bool` and `.recordExport()`.

- [ ] **Step 1: Write failing unit tests**: a fresh counter allows one export, the second is denied when `isPro == false`; a pro user is always allowed; incrementing twice then reinstalling (new counter instance, same fake keychain) still denies.
- [ ] **Step 2: Run, expect failure**, then implement with `SecItemCopyMatching`/`SecItemAdd`.
- [ ] **Step 3: Write the UI test** on the Dev scheme using `Products.storekit`: deny → tap `paywall.purchase.annual` → simulated purchase → export proceeds; also a cancel case that keeps the draft intact.
- [ ] **Step 4: Run both suites, expect PASS.** Commit `feat: gate export behind hard paywall`.

---

### Task 12: Localization and copy

**Files:**
- Modify: `App/Resources/Localizable.xcstrings`, `App/Resources/InfoPlist.xcstrings`, `fastlane/metadata/{en-US,vi}/*`
- Test: `Tests/Localization/LocalizationTests.swift`

**Interfaces:**
- Produces: complete en-US and vi catalogs; no user-facing literal outside `String(localized:)`.

- [ ] **Step 1: Write the failing test**: every key referenced by `TPCopy` exists in both locales and is non-empty in both; the attestation string contains no legal claim (`binding`, `court`, `legal advice`).
- [ ] **Step 2: Run, expect failure**, then fill the catalogs and the metadata files (name, subtitle, keywords per the spec's ASO list).
- [ ] **Step 3: Run, expect PASS**; snapshot the vi PDF layout golden. Commit `feat: localize en-US and vi`.

---

### Task 13: End-to-end suite

**Files:**
- Create: `UITests/EndToEndTests.swift`, `UITests/Support/UITestLaunch.swift`, `UITests/Fixtures/*.jpg`
- Modify: `App/App.swift` (launch-argument wiring for fixture photo source, fixed clock, state reset, draft resume)

**Interfaces:**
- Consumes: every accessibility id above.
- Produces: `XCUIApplication.turnproof(photos:clock:reset:)` helper; launch args `-UITestMode`, `-UITestPhotos`, `-UITestClock`, `-UITestResetState`, `-UITestResumeDraft`.

- [ ] **Step 1: Write the failing happy-path test**: add property → start move-out → capture 2 findings in Kitchen and 1 in Bath (one damaged with a note) → review → sign both → paywall (free slot) → export → share sheet appears.
- [ ] **Step 2: Run, expect failure** (flow incomplete), then wire the launch configuration and finish the flow.
- [ ] **Step 3: Add the negative tests**: seal blocked without signatures; second export gated when not pro; cancel paywall preserves the sealed report; relaunch with `-UITestResumeDraft` restores a draft.
- [ ] **Step 4: Run the full `Turnproof-Dev` test plan**, expect all PASS and a total runtime under 6 minutes.
- [ ] **Step 5: Commit** `test: add end-to-end inspection flow`.

**Review Focus coverage:** clock skew (fixed-clock test in Task 5 + relaunch test here); entitlement expiring mid-inspection (cancel case here); kill-mid-signature (resume-draft case here).

---

### Task 14: Snapshot gallery and accessibility audit

**Files:**
- Create: `UITests/SnapshotGalleryTests.swift`, `scripts/ui-gallery/gallery.py` (copied from `~/orca/Serene`)
- Test: same

**Interfaces:**
- Produces: PNGs per screen per appearance per Dynamic Type size in `TestResults/gallery/`.

- [ ] **Step 1: Write the failing test** rendering 7 screens × {light, dark} × {default, XXXL} and asserting each capture is non-blank and within 1% of its stored reference.
- [ ] **Step 2: Replace the `ConditionChip` and shutter button glyph-only controls** with labelled ones until `XCUIApplication().buttons["capture.shutter"].label == "Take photo"` passes.
- [ ] **Step 3: Run, expect PASS**; eyeball the gallery for truncation at XXXL and fix layout.
- [ ] **Step 4: Commit** `test: add snapshot gallery and accessibility labels`.

---

### Task 15: CI, metadata, and release readiness

**Files:**
- Modify: `.github/workflows/ci.yml`, `fastlane/metadata/**`, `CHANGELOG.md`, `docs/brand/screenshots-manifest.json`
- Test: CI run

**Interfaces:**
- Consumes: everything above.

- [ ] **Step 1: Push `develop`** and confirm `ci.yml` runs `Turnproof-Dev` tests on a simulator.
- [ ] **Step 2: Produce store screenshots** with `scripts/compose_screenshot.py` from the gallery captures: signed packet, room checklist, seal/hash, paywall.
- [ ] **Step 3: Fill metadata** (en-US + vi) with the spec's subtitle/keywords; confirm no "legally binding" copy.
- [ ] **Step 4: Run `scripts/doctor.sh`** and confirm it passes.
- [ ] **Step 5: Commit** `chore: wire CI and store metadata`.

---

## Self-review notes

- Spec §7.1 (models) → Task 2; §7.2 (screens) → Tasks 7–10; §7.3 (PDF) → Task 6; §7.4 (integrity) → Task 5; §8 (paywall) → Task 11; §9 (ASO) → Task 12/15; §10 (metrics) → Task 15 + MetricKit screen deferred to v1.1; §11 (tests) → Tasks 3–6, 13, 14; §12 risks → Review Focus and Task 4.
- Deferred to v1.1 and intentionally absent: MetricKit debug screen, manual archive import/export, multi-photo findings, iPad layout.
