## What

<!-- One paragraph: user-visible or CI-visible outcome. Link issues (#N). -->

## Quality gate (all must hold)

- [ ] `dart format` clean, `dart analyze --fatal-infos` clean, all package tests green
- [ ] Money stays integer minor units + ISO code — no doubles on any money path
- [ ] No silent guesses: extracted fields with uncertainty go to the review sheet (feasibility §4.5)
- [ ] UI changes respect the design-first bar (decision 10) — attach screenshots for user-visible changes
- [ ] No new permissions, network calls, or analytics (decisions 4 & 8: zero collection; ad path is dead)
- [ ] DB schema touched? Migration + a test that walks it; `schemaVersion` bumped

## Notes for reviewer

<!-- Risks, reverted experiments, follow-ups carved out. -->
