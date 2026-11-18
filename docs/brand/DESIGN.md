# Turnproof — Design System

## 1. Visual theme and atmosphere

Turnproof looks like an instrument for producing documents, not a social app. The surface is
warm paper (`#F6F2EA`), the ink is deep navy, and structure comes from 1 px hairlines rather
than shadows. Density is calm and generous: one idea per screen, large serif headlines,
small monospaced metadata. Nothing glows, nothing floats, nothing is glassy.

Emotional target: **quiet authority**. A landlord should feel that what they produce here
would be taken seriously by a tenant, a mediator, or a small-claims clerk — without the app
ever claiming legal force.

Keywords: editorial, archival, ledger, seal, paper, precise, unfussy, trustworthy.

Explicitly banned: gradients, glassmorphism, neon, drop shadows, pill-shaped primary
buttons, novelty illustrations, confetti, countdown timers, fake social proof.

## 2. Color palette and roles

### Foundation

| Token | Hex | Role |
|---|---|---|
| `paper` | `#F6F2EA` | App background, always |
| `paperRaised` | `#FFFDF8` | Cards, sheets, photo captions |
| `ink` | `#10233B` | Primary text, primary button fill, rules of emphasis |
| `inkSecondary` | `#4A5A6A` | Body copy, helper text |
| `inkTertiary` | `#5F6E7C` | Metadata, disabled, timestamps |
| `hairline` | `#DED7C9` | 1 px dividers, card borders, field outlines |

### Accent and interactive

| Token | Hex | Role |
|---|---|---|
| `brass` | `#B08A4F` | Seal marks, selected plan border, small emphasis rules |
| `brassSoft` | `#EFE3CF` | Selected chip background, seal halo |

### Status

| Token | Hex | Role |
|---|---|---|
| `good` | `#1F6F4A` | Condition good, verified, sealed-and-valid |
| `goodSoft` | `#E4EFE8` | Good chip background |
| `damage` | `#B42318` | Damaged condition, unresolved issue, destructive |
| `damageSoft` | `#F7E7E4` | Damage chip background |
| `warning` | `#9C4A06` | Missing photo, needs attention |
| `warningSoft` | `#FBEFDD` | Warning banner background |

Rules: status color appears only as a small chip, a 1 px edge, or an icon — never as a large
fill. `damage` is never used for non-destructive actions.

## 3. Typography

| Family | Role | Character |
|---|---|---|
| **Newsreader** | Display, H1–H3, property and room names, report titles | Editorial serif, slightly warm, high trust |
| **Inter** | Body, controls, lists, buttons | Neutral, legible at small sizes |
| **Courier Prime** | Eyebrows, hashes, timestamps, report IDs, counts, section labels | Typewriter; signals "record" |

Scale (pt, Dynamic Type–aware):

| Style | Font | Size / line | Weight | Tracking |
|---|---|---|---|---|
| Display | Newsreader | 34 / 38 | 500 | -0.5 |
| H1 | Newsreader | 28 / 34 | 500 | -0.3 |
| H2 | Newsreader | 22 / 28 | 500 | -0.2 |
| H3 | Newsreader | 18 / 24 | 500 | 0 |
| Body | Inter | 16 / 22 | 400 | 0 |
| Body strong | Inter | 16 / 22 | 600 | 0 |
| Small | Inter | 14 / 20 | 400 | 0 |
| Caption | Inter | 12 / 16 | 400 | 0 |
| Eyebrow | Courier Prime | 11 / 14 | 400 | +1.6, uppercase |
| Mono meta | Courier Prime | 12 / 16 | 400 | +0.4 |

Sentence case everywhere except eyebrows, status chips, and mono metadata, which are
uppercase. Numbers in tables and report metadata are tabular.

## 4. Components

**Button (primary)** — full-width, 52 pt tall, radius 4, fill `ink`, label Inter 16/600 in
`paperRaised`, no shadow. Pressed: 8% black overlay. Disabled: `inkTertiary` fill at 40%.
Icon leading, 20 pt, 8 pt gap.

**Button (secondary)** — same geometry, transparent fill, 1 px `ink` border, label `ink`.
**Text action** — Inter 15/600, `ink`, underline only on press.

**Card** — `paperRaised` fill, 1 px `hairline` border, radius 4, padding 16. No shadow.
Cards may have a 3 pt left edge in `good`, `warning`, or `damage` when they carry status.

**Status chip** — height 24, radius 2, uppercase Courier Prime 11, soft background plus
matching text color, optional 6 pt dot. Never a pill, never more than four words.

**Property row** — H3 name, `inkSecondary` address line, mono metadata line, chevron on the
right, hairline divider below. 72 pt minimum height.

**Photo tile** — radius 2, 1 px hairline, 2-column grid, 8 pt gutters. A numbered mono badge
sits top-left; a condition chip sits bottom-left over a `paperRaised` strip, not over the
image. Damage tiles get a 2 pt `damage` edge.

**Condition control** — three equal segments, 44 pt tall, 1 px `hairline` outline, selected
segment fills with `goodSoft`, `warningSoft`, or `damageSoft` and its text turns to the
matching status color. Never a slider.

**Field** — `paperRaised`, 1 px `hairline`, radius 4, 48 pt tall, 16 pt horizontal padding,
label above in Eyebrow style.

**Signature box** — 1 px `hairline` box, 160 pt tall, baseline rule inset 24 pt, placeholder
"Sign here" in Caption, `paperRaised` fill.

**Issue banner** — `warningSoft` fill, 1 px `warning` edge, warning glyph, one sentence, and
a single text action on the right.

**Seal** — 56 pt circle, `brass` 1.5 pt ring, `brassSoft` fill, report short hash beneath in
Mono meta. Used on the export screen and as the app mark.

**Navigation** — inline back chevron plus a mono eyebrow title in the top bar; no tab bar.
Flows are linear: Properties → Property → Rooms → Capture → Review → Sign → Export.

## 5. Layout principles

- Base unit 4 pt; gutter 20 pt; section gap 32 pt; card internal padding 16 pt.
- Content column is full width on iPhone; nothing exceeds 640 pt on iPad compatibility.
- Vertical rhythm: eyebrow → title → subtitle → 24 pt → content.
- Sticky bottom action bar: 16 pt inset, `paper` background, 1 px `hairline` top border,
  safe-area aware; exactly one primary action per screen.
- Minimum touch target 44×44 pt.
- Light mode only in v1; dark mode must map paper→`#12161C`, raised→`#1A2028`, ink→`#F2EEE6`,
  hairline→`#2C3540` without inventing new hues.

## 6. Stitch generation notes

Atmosphere prompt fragment: "editorial paper-and-ink interface, warm paper background,
deep navy ink, typewriter mono metadata, hairline dividers, no shadows, no gradients,
quiet authority, archival document".

Canonical colors: paper `#F6F2EA`, raised `#FFFDF8`, ink `#10233B`, brass `#B08A4F`,
good `#1F6F4A`, damage `#B42318`, warning `#9C4A06`, hairline `#DED7C9`.

Component prompts:

1. "A property list row: serif property name, muted address line, typewriter metadata line
   with a short hash, chevron, hairline divider, no shadow."
2. "A photo review grid: two columns, numbered typewriter badges, status chips under each
   tile on a paper strip, a single red edge on damaged tiles."
3. "A sealed-report export screen: overlapping paper page thumbnails, a brass seal badge,
   typewriter short hash, metadata list with hairline dividers, one primary share button."

Copy rules: say "condition report" and "evidence packet". Never claim the report is legally
binding, court-admissible, or legal advice.
