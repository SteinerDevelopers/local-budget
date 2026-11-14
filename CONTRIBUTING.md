# Contributing to Steiner Budget

Thanks for your interest! Steiner Budget is AGPL-3.0 — see [LICENSE](LICENSE).

## Legal provenance of code in this repository

- Commits authored by the owner (`lance.hollon@gmail.com`) and by agent/bot
  identities (`Steiner-Bot`, `Local Budget Bot`, `bot@steinerdevelopers.dev`,
  `steiner-bot@…`, `agent-*`, `dsh-agent`) are works of **Steiner Developers,
  L.L.C.** (work-for-hire; agent tooling operated by and for the LLC).
  This repo's full copyright has been held by the LLC since inception;
  there are no third-party copyright holders in the history.

## If you'd like to contribute

Before we can merge anything from outside the LLC, two rules apply
(adopted under decision 17, owner ruling 2026-11-13, "keep and hedge"):

1. **DCO sign-off** — every commit must carry a
   `Signed-off-by: Your Name <you@example.com>` line (use
   `git commit -s`), certifying the
   [Developer Certificate of Origin 1.1](https://developercertificate.org/)
   — i.e., you wrote the change or otherwise have the right to submit it
   under this project's license.
2. **Relicense grant** — by submitting a contribution, you retain your
   copyright and grant Steiner Developers, L.L.C. a perpetual, worldwide,
   non-exclusive, sublicensable license to relicense your contribution
   (including combining or distributing it under GPL-family or other
   open-source licenses, and under commercial terms for dual-licensing).
   Submitting constitutes acceptance of this grant; no separate CLA needed.

Why rule 2 exists: the project license is AGPL-3.0, and choosing licenses
for the *combined* work — or offering the code under additional terms —
must remain possible as the project grows. We hedge the option now so the
freedom you contribute stays meaningful for whichever license best serves
users in the future.

## Practical bits

- Flutter/Dart; run `flutter analyze` and the existing test suites before
  submitting.
- Open an issue first for anything larger than a typo; we move in
  owner-ruled bursts and don't want your work to collide with a decision.
