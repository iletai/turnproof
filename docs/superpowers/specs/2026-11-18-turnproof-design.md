# Turnproof — Product & Technical Design

Date: 2026-11-18
Status: awaiting owner approval
Owner: iletai (solo)
Working name: **Turnproof** (bundle `com.iletai.turnproof`)

## 1. Intent and why

Solo landlords and small property managers lose deposit disputes because the evidence
lives in their Camera Roll: hundreds of undated photos, no room structure, no tenant
acknowledgement, nothing presentable if the case goes to a mediator or small-claims court.

Turnproof produces a **tenant-signed, timestamped, tamper-evident condition report** for one
unit in about ten minutes, entirely offline. The landlord walks the unit room by room,
rates each item, flags damage, both parties sign on the phone, and a sealed PDF packet is
exported and shared on the spot.

Why now:

- Supply signal: 7+ keyword-clone apps launched in 2026 target `RentProof` / `RoomProof` /
  `MoveOut Proof` (App Store search, verified 2026-11-18). All are free, zero-rated, and
  look interchangeable. Demand exists; trust does not.
- Incumbents (zInspector, HappyCo, RentCheck) are enterprise SaaS at $50–250/month with
  mandatory cloud accounts and desktop-first UX. Nothing serves the 1–4 unit landlord.
- Business-category economics are the best on the store (RevenueCat SotSA 2026):
  9.1% median download-to-trial, 89.9% of trial starts on Day 0, $35.48 median one-year
  realized LTV per payer, top decile above $120.

The moat is not features. It is craft, trust, and a sharper promise than the clones:
**"a packet your tenant signs and cannot dispute."**

## 2. Goals

1. Ship v1 in ~6 weeks for one segment: US small landlords, 1–4 units, English-first.
2. Monetize with a hard paywall: $79.99/yr (7-day trial), $12.99/mo, $149.99 lifetime.
3. 100% on-device. No account, no backend, no analytics SDK, no network calls in v1.
4. Complete E2E flow: property → room-by-room inspection → annotate/flag → dual signature
   → sealed PDF → share/export.
5. Design and polish that visibly beats the clone wave in the first three screenshots.

## 3. Non-goals for v1

- Tenant-side app, rent collection, accounting, maintenance tickets, team seats.
- Cloud sync, multi-device, web dashboard, Android.
- AI photo analysis, auto damage detection, OCR of serial numbers (candidate for v1.1).
- Watch, widgets, Live Activities, Shortcuts (candidate for v1.1 — not on the critical path).
- State-specific legal templates or any claim of legal validity.

## 4. Anti-goals

- A subscription that only makes sense once. Retention must come from recurring turnovers,
  periodic inspections, and multi-unit portfolios.
- A free tier that lets someone finish and export a report. Data entry stays free; the
  deliverable is paid.
- Any capability that needs an Apple entitlement review beyond camera/photos.

## 5. Constraints

- House standard from `ios-new-app`: Dev/Staging/Prod, 3 bundle ids, 6 configs, XcodeGen,
  Swift 6, StoreKit 2, BaseNavigationStack, fastlane, CI Gate 0. AppUpdateKit is **not**
  scaffolded in v1: its remote-config fetch would break the zero-network promise.
- SwiftData + PDFKit + SwiftUI; iOS 18+.
- en-US primary, vi second. VN pricing localized separately.
- No third-party SDKs. Privacy manifest stays minimal: camera, photo library, UserDefaults.
- Review wording: "condition report" and "evidence packet", never "legally binding".

## 6. Approaches considered

| # | Approach | Trade-off | Verdict |
|---|---|---|---|
| A | Rental inspection app for small landlords | Recurring JTBD, best category economics, low review risk; distribution needs community work | **Chosen** |
| B | Contractor job closeout (same engine, trades vertical) | Higher LTV, but trades don't search the App Store; ASA Business CPT ~$6 | Deferred — same engine, later vertical |
| C | Consumer condition report (move-out for tenants, used-car, resale) | Easiest to market, but one-shot usage kills subscription economics | Rejected |

Positioning inside A:

- A1 "generic rental inspection app" — fights seven clones on the same keyword. Rejected.
- A2 **"deposit-proof packet with a tenant signature"** — sharper promise, defensible,
  screenshot-friendly. **Chosen.**
- A3 "property manager turnover ops" — higher ARPU but needs team seats and a backend.
  Data model stays multi-property-ready; team features are out of scope.

## 7. Product design

### 7.1 Data model (SwiftData)

- `Property`: label, address lines, unit, landlordName, createdAt.
- `Inspection`: property, kind (`.moveIn` / `.moveOut` / `.periodic`), startedAt,
  completedAt, tenantName, tenantEmail, inspectorName, status.
- `Room`: inspection, templateKey, name, order.
- `Finding`: room, order, photoData, condition (`.good` / `.fair` / `.damaged`),
  note, isDamageFlagged, capturedAt.
- `Signature`: inspection, role (`.tenant` / `.landlord`), pngData, signedAt,
  attestationVersion.
- `Report`: inspection, revision, generatedAt, sha256, pageCount, pdfData, supersedesID.

Invariants: an inspection can only be sealed with ≥1 room, ≥1 finding, both signatures,
and zero unresolved findings. "Unresolved" means a damage-flagged finding without a
non-empty note; every finding must carry exactly one photo in v1. Once sealed, the
inspection is immutable (`status = .sealed`); corrections create a new revision that
supersedes the old report rather than mutating it. Report hash is a function of a
canonical manifest of all records, each image's SHA-256, and the logical page count —
deterministic, recomputable, and verifiable in-app.

The free-report counter lives in the Keychain, not UserDefaults, so deleting and
reinstalling the app does not reset it.

### 7.2 Screens

1. **Properties** — list/empty state, add property, per-property last inspection.
2. **Property detail** — history, "Start inspection" with kind picker.
3. **Room checklist** — default template (Kitchen, Living, Bedroom, Bath, Hall, Exterior),
   add custom room, per-room photo count and progress.
4. **Capture** — full-bleed camera, condition segmented control, one-line note,
   damage flag, next/back; library import as fallback. One-thumb reachable.
5. **Review** — grid per room, missing-photo and unflagged-damage warnings, reorder, edit.
6. **Sign & attest** — dual signature canvases, attestation copy, timestamp.
7. **Export** — PDF preview, share sheet, hash short code + full hash, "verify" screen.

Paywall appears at export of the first report: one complete free packet is allowed (the
aha moment), and every later export is gated. Entry and stored data stay accessible
after the wall. The allowance counter is stored in the Keychain and survives reinstall.

### 7.3 PDF packet spec

- Cover: brand mark, property/unit, inspection kind and date, parties, report id,
  short hash, page count.
- One page per room (up to 4 photos) with overflow pages, two-column photo grid, caption
  under each photo (condition, note, captured time), damage findings highlighted.
- Signature page: both signature images, printed names, timestamp, attestation text.
- Integrity page: full SHA-256, algorithm and canonical-manifest note, QR code encoding
  the hash, report id, revision.
- Every page footer: report id, generated timestamp, page x/y.
- Budget: max 40 photos per inspection, longest edge 1600 px, JPEG 0.75 (~250–400 KB
  each). Target packet size is **under 20 MB**, not 15 MB.
- PDFKit writes a non-deterministic creation date and document id; both are pinned from
  `Report.generatedAt` so the golden-file test is stable.
- Layout is deterministic and golden-file tested, per locale (en-US and vi).

### 7.4 Evidence integrity

SHA-256 over a canonical manifest: sorted-key JSON of property, inspection, rooms,
findings (metadata + capturedAt), signatures' SHA-256, each photo's SHA-256, and the
logical page count. The hash is printed as a 12-character short code in the footer, in
full on the integrity page, in PDF metadata, and in a QR code. An in-app "Verify" screen
recomputes it from stored records and reports match/mismatch.

A third party holding the PDF can read the hash but cannot recompute it without the
source records; the packet is therefore self-identifying, not independently verifiable.
That is stated plainly on the integrity page. No blockchain, no server.

## 8. Monetization

- Hard paywall, annual preselected: $79.99/yr with 7-day trial; $12.99/mo;
  $149.99 lifetime. One completed free report before the wall.
- Rationale: hard paywall converts downloads to paid at 10.7% median by D35 vs 2.1% for
  freemium, and delivers $3.09 vs $0.38 RPI at D60; 17–32 day trials convert at 42.5%
  median vs 25.5% for sub-4-day trials.
- Annual is the default because business buyers prefer annual and it doubles RPI.
- No ads, no data sale, no third-party analytics.

## 9. Distribution

- ASO: title `Turnproof`, subtitle with "Rental inspection & deposit proof"; long-tail
  keywords: rental inspection, move out report, deposit checklist, landlord inspection,
  tenant walkthrough, property condition report. Custom product pages per keyword cluster.
- Screenshots 1–3 must show: the signed packet, the room checklist, the sealed hash.
  Clones cannot copy trust framing quickly.
- Channels: r/Landlord, r/PropertyManagement, BiggerPockets forums, local landlord
  Facebook groups, one YouTube walkthrough. No Apple Search Ads at launch.
- Lead magnet: a free printable move-out checklist that links to the app.

## 10. Success metrics and how they are measured

- Median report completion under 12 minutes.
- Paywall view → purchase ≥ 8%; trial → paid ≥ 35%.
- Day-30 retention ≥ 20% (productivity median 15.5%).
- Crash-free sessions ≥ 99.8%.
- First 100 paying landlords within 90 days of launch.

With no third-party analytics: purchases, trials, and refunds come from App Store Connect;
local counters (report started/completed, paywall shown, duration, report size) live
on-device and are exported only when the user taps "Export diagnostics". Crashes and hangs
come from MetricKit, rendered locally in a debug screen, never uploaded.

## 11. Testing plan (full E2E)

- **Unit**: inspection state machine, completion invariants, hash determinism and
  verification, canonical JSON encoding, PDF layout golden files, image downscaling,
  filename/slug, entitlement gating, SwiftData migration.
- **Snapshot**: 7 screens × light/dark × 3 device sizes × Dynamic Type XXL.
- **UI E2E (XCUITest)**: happy path with `-UITestCamera` fixture injection (create
  property → inspect 2 rooms → flag damage → sign → paywall → StoreKit test purchase →
  export sheet), plus negatives: cannot complete without photos, cannot complete without
  both signatures, restore purchase, cancel at paywall keeps data.
- **Accessibility**: VoiceOver labels on every capture control, 44 pt targets,
  contrast checks on condition colors.

## 12. Risks

| Risk | Mitigation |
|---|---|
| Clone flood on the same keywords | Differentiate in screenshots and promise; brandable name, not a keyword clone |
| "Legally binding" wording triggers review or liability | Careful attestation copy; no legal claims; privacy policy states it is a record, not legal advice |
| PDF bloat with 60+ photos | Downscale, JPEG 0.8, per-room page cap with overflow page |
| Multi-state deposit rules | Stay generic; no state templates in v1 |
| Solo scope creep | v1.1 backlog is explicit; no widgets/watch/AI in v1 |
| Phone lost or broken — evidence gone | v1 relies on the iOS device backup (app container is included) plus per-report PDF export; in-app copy says so. Manual library archive export is v1.1 |
| Imported library photos have old EXIF dates | `capturedAt` is set to import time; the PDF caption prints both "taken" (EXIF) and "added" (import) when they differ |

## 13. Left to the builder

- Final brand palette, type scale, and icon (from Stitch design pass).
- Exact room template list and ordering.
- Copy tone for attestation and paywall.
- App Store screenshots copy and the free checklist lead magnet.
- iPhone-only in v1 (iPad runs in compatibility mode); universal layout is v1.1.

## 14. Decisions log (calls I made; correct any of these)

| Decision | Call | Why |
|---|---|---|
| Free allowance | One completed report, counter in Keychain | Strongest aha without turning the hard paywall into freemium; Keychain closes the reinstall loophole without a backend |
| AppUpdateKit | Not scaffolded in v1 | Its remote config fetch breaks the zero-network promise |
| Hash scope | Records manifest + per-image hashes + page count, embedded on an integrity page and QR | Allows in-app verification and gives the packet a visible seal; independent third-party verification is explicitly not claimed |
| Immutability | Sealed reports are immutable; corrections create a new revision | Otherwise the stored hash silently describes data that no longer exists |
| Unresolved finding | Damage flag without a note | Minimal new schema, no migration later |
| Photos | One photo per finding, max 40 per inspection, 1600 px | Keeps packets under 20 MB; multi-photo findings in v1.1 |
| Analytics | ASC + local counters + MetricKit, user-initiated diagnostics export | Keeps zero-network and the privacy label clean |
| Backup | iOS device backup + per-report PDF export; archive export in v1.1 | Cheapest honest answer for v1 |
| Language | en-US and vi ship together, including the sealed PDF | vi is a launch requirement |

