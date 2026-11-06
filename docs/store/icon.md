# Icon design — Steiner Budget

_Status: **candidate sheet ready — awaiting owner pick** (agent recommendation:
**A2 · Outline Wallet & Receipt**). Candidates: `docs/store/icon-candidates/`
`contact-sheet.png`, incl. launcher-mask previews + 32 px legibility strip;
family pair-review vs Steiner Vault in deliverables). Production exports will be
hand-authored SVGs mirroring the Vault V8 pipeline — this sheet is the concept
stage, same as Vault's._

## The house system (inherited from Steiner Vault V8, unchanged)

One silhouette; **tier carried by colorway alone**:

| | ground | glyph | accent |
|---|---|---|---|
| **Free** | paper `#F4F1EA` | steel `#37474F` | — (clasp cut-out in paper) |
| **Pro** | deep `#263238` | paper `#F4F1EA` | amber `#F9A825`, one element |

The single amber element answers Vault's own element: Vault Pro ambers the
**roof**; Budget Pro ambers the **receipt's torn edge** (or clasp, in solid
variants) — top-of-glyph accent in both, one notch of differentiation apart.
Note `#F9A825` is already the app's own `Tokens.warning`, and `#2E7D32`
(green) stays in-app — the launcher pair speaks steel/paper/amber; the chrome
stays green, like every finance app whose icon ≠ its UI theme.

## The concepts

| | concept | category read (advisory vision) | risk |
|---|---|---|---|
| **A** | Wallet & Receipt (solid) | budgeting/expense ✅ | low; competes with vault A's *fill weight* slightly less than it differs in shape |
| **A2** | **Outline Wallet & Receipt** | budgeting/expense ✅ | **recommended** — same grammar as Vault A (outline container holding one sheet), zero silhouette overlap |
| **B** | Receipt alone | notes/receipts/journaling | medium — no money cue; reads notes app |
| **C** | Wallet alone | **payments/banking/cards** | HIGH — vision review flagged card-app confusion; demoted from "small variant" to sheet reference only |
| **D** | Receipt + check | tasks/approval/security | HIGH — checkmark dominates; "to-do/verified" crowd |

Advisory votes (ollamatest, both verified against the sheets by agent):
best = A/A2, avoid C; pair-review verdict: same family ✅, confusion low
"provided Budget avoids the House & Sheet silhouette" — A2 satisfies both.

## The pick rationale (A2)

- **Pictorial sibling, not twin**: Vault A is *a house holding a sheet*;
  Budget A2 is *a wallet holding a receipt* — same outline grammar, same
  paper-through-the-slot story ("your home's papers" / "your money's proof"),
  unmistakably two products.
- **Hero feature in the glyph**: the torn receipt edge is the capture
  promise; listing direction (listing.md §feature graphic) said exactly this.
- **32 px behavior**: outline wallet-only small variant (receipt dropped
  below ~48 px, mirroring Vault's house-only small export). Vision review
  judged the full A2 legible at 32, but the small variant stays for parity —
  owner sees both strips on the sheet.
- No text in the icon (house rule).

## Export table (on pick)

| asset | size | source |
|---|---|---|
| adaptive `ic_launcher` fg/bg (free+pro) | 108 dp layers, hand-authored SVG → PNG | `a2-wallet-receipt-outline-{free,pro}.svg` |
| legacy/round | 48/32 (small variant, wallet-only) | `a2-outline-{tier}-{48,32}` geometry |
| monochrome (Android 13 themed icons) | fg layer, single-color | outline only, no accent |
| Play store icon | 512×512, squircle-safe | full A2 |
| feature graphic | 1024×512 | A2 at 40% + product name lockup (E9, owner copy) |

Pending: owner pick → SVG authoring (same craft bar as Vault V8) →
`app/android` mipmap layers per flavor → goldens untouched (icons are
out-of-app assets).
