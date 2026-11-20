# Turnproof — Design System (v2, iOS 27 native)

Source of truth for the Turnproof iPhone app. Supersedes `docs/brand/DESIGN.md` (v1 paper/serif/brass, not glass-compatible).
Units are points (pt). Deployment target iOS 18.0, designed for the iOS 27 Liquid Glass look; every API newer than iOS 18 has a fallback in the SwiftUI mapping.

## 1. Visual theme and atmosphere

Direction: **Ledger Ink**. Turnproof is an instrument that produces a signed record, so it looks like a well-made system app: neutral grouped backgrounds, one deep ink-navy accent, SF Pro everywhere, and SF Mono only for things that are records (report code, timestamps, counts on the sealed report). Structure comes from the system inset grouped list, separators and whitespace, never from shadows or decoration.

Emotional target: quiet authority. Calm, precise, unfussy. A landlord should feel the output would be taken seriously, without the app ever claiming legal force.

Liquid Glass lives only on the navigation layer: navigation bar, toolbars, sheets, menus, the floating camera controls and the bottom action bar (`safeAreaBar`). Content (rows, photos, report preview) is never glass. Content scrolls under bars with the system scroll edge effect; no opaque custom bar backgrounds.

Keywords: ledger, ink, record, seal, precise, calm, native.

Banned: gradients, glow, drop shadows on content, glass on rows/cards, stacked identical cards, emoji, sparkles, cream paper backgrounds, decorative serif display type, brass/gold accents, confetti, countdown timers, fake social proof.

## 2. Color palette and roles

Semantic roles map to system colors first. Custom colors (asset catalog, light + dark) only where the system has no role or fails contrast.

| Role | Maps to | Light | Dark | Use |
|---|---|---|---|---|
| `background` | `systemGroupedBackground` | #F2F2F7 | #000000 | Screen background (grouped screens) |
| `surface` | `secondarySystemGroupedBackground` | #FFFFFF | #1C1C1E | Inset grouped rows, signature pads |
| `plainBackground` | `systemBackground` | #FFFFFF | #000000 | Plain lists, report preview page |
| `textPrimary` | `label` | #000000 | #FFFFFF | Titles, row titles, body |
| `textSecondary` | custom `TextSecondary` (Apple accessible gray) | #6C6C70 | #AEAEB2 | Row subtitles, metadata, footers. 5.2:1 on white. System `secondaryLabel` (3.4:1) is NOT used for text |
| `separator` | `separator` | #C6C6C8 | #38383A | Row separators, inset to text |
| `tint` (AccentColor) | custom `AccentColor` "Ink" | #1F3A64 | #9DB8E8 | Primary buttons, Done/Save, links, selected segment. 11.4:1 on white, 8.5:1 on #1C1C1E |
| `onTint` | custom | #FFFFFF | #000000 | Label on filled tint button |
| `statusGood` | custom `StatusGood` | #248A3D | #30D158 | Good condition / Sealed glyph only (4.4:1, icons ≥ 3:1). Never small text |
| `statusFair` | custom `StatusFair` | #C93400 | #FF9F0A | Fair condition, needs attention glyph |
| `statusDamage` | `systemRed` (accessible) | #D70015 | #FF453A | Damaged, unresolved issue, destructive actions |
| `cameraChrome` | fixed | #000000 | #000000 | Camera full-screen cover background (both modes) |

Rules
- One accent only (Ink). Tint only the primary action of a screen and the confirm button of a sheet; other toolbar items are plain `label` symbols.
- Status is never color alone: always an SF Symbol shape plus a text label (`checkmark.seal.fill` + "Sealed", `circle.dotted` + "In progress", `exclamationmark.triangle.fill` + "Needs a note").
- Status text is set in `textPrimary`/`textSecondary`; status color only on the glyph.
- Increase Contrast: asset catalog provides high-contrast variants (Ink #102540 / #C2D6F5).

## 3. Typography

SF Pro via Dynamic Type text styles only. SF Mono (`.monospaced()`) for report code, timestamps on the sealed report, and the "4 of 6" counters' digits (`.monospacedDigit()`). No other families.

| Style | Size/Line (pt) | Weight | Use |
|---|---|---|---|
| Large Title | 34/41 | Bold | Top-level screen titles (Properties, Settings) |
| Title 1 | 28/34 | Bold | Paywall headline |
| Title 2 | 22/28 | Bold | Report sealed confirmation, camera room name |
| Title 3 | 20/25 | Semibold | Section lead on Sign & Attest |
| Headline | 17/22 | Semibold | Row titles, button labels |
| Body | 17/22 | Regular | Paragraphs, attestation text |
| Callout | 16/21 | Regular | Explanatory copy under titles |
| Subheadline | 15/20 | Regular | Row subtitles (address, tenant) |
| Footnote | 13/18 | Regular | Section footers, metadata, legal links |
| Caption 1 | 12/16 | Regular | Photo captions, timestamps |
| Caption 2 | 11/13 | Regular | Minimum. Thumbnail index numbers only |
| Mono code | Body 17/22 SF Mono | Medium | Verification code "7F3A-92C1-B04E" |

Sentence case everywhere. Section headers use the system style (Footnote, uppercase by the system in grouped lists). Must survive AX5 and +30% Vietnamese length: rows wrap, never truncate the meaning; HStack rows reflow to VStack via `ViewThatFits`.

## 4. Components

All components are standard SwiftUI/iOS components.

- **Navigation bar** — Large title on top-level (Properties, Settings); inline title on pushed screens; system back chevron + previous title. Trailing items max 2 plain SF Symbols; overflow in `Menu` (`ellipsis.circle`) / `ToolbarOverflowMenu` (iOS 27).
- **No tab bar.** Single `NavigationStack`, linear flow: Properties → Property → Rooms → Capture (cover) → Review → Sign & attest → Report sealed. Settings is a sheet from a toolbar `gearshape` on Properties.
- **List row (property)** — inset grouped, min height 60. Title Headline (label + unit), subtitle Subheadline `textSecondary` (address), trailing status line: SF Symbol + Footnote text. Disclosure chevron. Separator inset to text (16).
- **List row (room)** — inset grouped, min 52. Leading status glyph 22 (`checkmark.circle.fill` StatusGood / `circle` textSecondary / `exclamationmark.triangle.fill` StatusFair), title Body, trailing Footnote "3 photos", chevron.
- **Resume row** — first section on Properties when a draft exists: Headline "Continue inspection", Subheadline "Maple Court, Unit 2B · 4 of 6 rooms", `ProgressView(value:)` linear 4 pt, chevron. Not a card.
- **Primary button** — system `.borderedProminent`, `.controlSize(.large)`, capsule, tint Ink, full width minus 16 margins, min height 50, pinned with `safeAreaBar(edge: .bottom)` (iOS 26+, fallback `safeAreaInset`). On iOS 26+ `.glassProminent`. Disabled uses system disabled style plus a Footnote reason above it.
- **Secondary button** — `.bordered` capsule, or plain text button in tint.
- **Segmented control** — system `Picker(.segmented)`: "Good | Fair | Damaged". Selected segment shows a leading SF Symbol (`checkmark.circle`, `minus.circle`, `xmark.octagon`) so meaning is not color only.
- **Toggle** — system toggle, tint Ink.
- **Text field** — system in inset grouped row, placeholder `textSecondary`.
- **Signature pad** — `surface` fill, 1 pt `separator` stroke, continuous radius 12 (or `ConcentricRectangle`), height 160, baseline rule 1 pt inset 24 from bottom, placeholder Footnote "Sign here" with `signature` symbol, Clear text button trailing in the section header.
- **Photo thumbnail** — square, continuous radius 8, 1 pt separator stroke; condition glyph below on the row, never overlay text on the photo. Damaged gets `xmark.octagon.fill` badge 20 pt top-trailing on a `surface` circle.
- **Issue row** — inset grouped row: `exclamationmark.triangle.fill` StatusFair glyph, Body text, trailing "Add note" tint text button. Not a colored banner.
- **Seal mark** — SF Symbol `checkmark.seal.fill` 56 pt hierarchical, tint Ink. App mark/logo uses a custom glyph (not SF Symbol) in the icon only.
- **Verification code** — SF Mono Body, grouped in 3×4 characters, `textPrimary`, with "Copy" plain button; Footnote explanation below.
- **Empty state** — `ContentUnavailableView` (symbol `building.2`, title, description, action button).
- **Camera controls** — full-screen cover on black; top: Close (`xmark`) glass circle 44 leading, room name Title 3 white center, Library (`photo.on.rectangle`) glass circle 44 trailing. Bottom: glass panel (sheet-like, `GlassEffectContainer`) with segmented control, note field, flag toggle, shutter 72 pt (white ring), last-photo thumbnail 44, Done (`.glassProminent` capsule).
- **Paywall** — `SubscriptionStoreView` look: marketing content (seal symbol, headline, 3 benefit rows with SF Symbols), plan picker rows (Annual preselected with "7-day free trial"), primary Continue button, Restore Purchases, Terms of Use, Privacy Policy, close `xmark` top trailing.
- **Sheets** — Cancel leading, one confirm trailing (tinted). Detents `.medium`/`.large` where a panel is non-blocking.

## 5. Layout principles

- Spacing scale: 4, 8, 12, 16, 20, 24, 32, 40. Screen margin 16 (system inset grouped). Row vertical padding 11–12, row min height 44. Section gap = system grouped spacing (~20–24).
- Fluid width 390–440 pt; never hard-code width. iPhone only, portrait.
- Radius: `ConcentricRectangle` / `containerShape` on iOS 26+; fallback continuous 8 (thumbnails), 12 (signature pads, preview page), 22 (camera panel). Buttons use system capsule.
- Exactly one primary action per screen, pinned bottom via `safeAreaBar`; content never sits under it (list gets bottom inset automatically).
- Nothing under status bar / Dynamic Island / home indicator except the camera preview (intentional full-bleed media).
- Hit targets ≥ 44×44.
- Light and dark for every screen; semantic roles only.

## 6. Stitch generation notes

Atmosphere: "native iOS 27 system app, Ledger Ink: neutral grouped gray background #F2F2F7, white inset grouped rows, single deep ink-navy accent #1F3A64, SF Pro text, SF Mono only for the report code, Liquid Glass only on bars and floating controls, no shadows, no gradients, calm and precise".

Canonical colors: background #F2F2F7 / #000000, surface #FFFFFF / #1C1C1E, text #000000 / #FFFFFF, secondary text #6C6C70 / #AEAEB2, separator #C6C6C8 / #38383A, Ink tint #1F3A64 / #9DB8E8, good #248A3D / #30D158, fair #C93400 / #FF9F0A, damage #D70015 / #FF453A.

Rules repeated for every prompt:
1. iOS vocabulary only: large title, inline title, back chevron, toolbar item, inset grouped list, list row, section header/footer, sheet, full-screen cover, segmented control, toggle, ContentUnavailableView. Never: hero, header bar, navbar, footer, sidebar, dashboard, card grid, chips, FAB, hover, Material icons, Tailwind.
2. Navigation stated in every prompt: "NO tab bar. Single NavigationStack." plus the exact back chevron / title / toolbar items.
3. Content contract: show ONLY the listed copy and numbers; invent no labels, stats, badges, icons, brand names, legal or security claims, or features. Language: English.
4. PLATFORM LIMITS: never claim legally binding, court-admissible, legal grade, certified, tamper-proof, immutable, encrypted, secure vault, or name a hash algorithm on screen. Say "condition report" and "verification code". No account, no cloud, no sign-in.

Component prompts:
1. "Inset grouped list row: property name and unit in Headline, address in Subheadline gray, trailing seal symbol with the word Sealed, disclosure chevron, separator inset 16pt."
2. "Room checklist: inset grouped rows with a leading status symbol (filled green checkmark, empty circle, orange triangle), room name, trailing photo count, chevron; pinned bottom capsule button, disabled with a footnote reason."
3. "Sealed report: large seal symbol in ink navy, title 'Report sealed', white report page preview with continuous corners, verification code in SF Mono with Copy button, one primary Share PDF button pinned at the bottom."

