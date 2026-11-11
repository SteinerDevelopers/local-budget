# #54 determination — does local budgeting meet Play's financial-app criteria?

_Researched 2026-11-11 per owner ruling ("does local budgeting meet the
financial apps criteria? deep dive research to confirm determination").
Sources are Google's own policy pages, fetched 2026-11-11; quoted text
matches the live pages._

## Short answer

**The declaration is mandatory for every app regardless of features — and
our honest declaration is a financial app under "Other" (offline money
management), not the "no financial features" certification.** No licenses
or extra documentation apply to us.

## The three facts that decide it

1. **Everyone completes the form.** "All developers that have an app
   published on Google Play must complete the Financial features
   declaration, including apps on closed testing, open testing, or
   production tracks … Even developers with apps that do not offer any
   financial features must complete this form and certify that no
   financial features are offered." Exemptions are system services and
   private apps only — neither is us.
   ([declaration help](https://support.google.com/googleplay/android-developer/answer/13849271))
2. **The policy definition is by what the app does for the user's money,
   not by custody:** "we consider financial products and services to be
   those related to the **management** or investment of money and
   cryptocurrencies, including personalized advice."
   Budgeting is literally management of money. The regulated-enforcement
   sections (loans, crypto exchanges, insurance…) are subsets, not the
   definition.
   ([financial services policy](https://support.google.com/googleplay/android-developer/answer/9876821))
3. **The declareable feature list is transactional/custodial** — Banking
   & loans, Payments/transfers/wallets/BNPL/rewards, Crypto wallet or
   exchange, Stock trading, Crowdfunding, Credit monitoring, Financial
   advice, Insurance, **Other** — or the certification "My app doesn't
   provide any financial features." Steiner Budget matches none of the
   enumerated features: it moves no money, holds no funds, trades nothing,
   gives no investment advice.

## Determination

- **Does the app offer an enumerated feature? No.** Every list item
  involves transacting, custodying, brokering, or advising on money; we
  record and plan money locally.
- **Is "my app doesn't provide any financial features" therefore the
  honest checkbox? No — that's the trap.** The policy umbrella sentence
  (fact 2) explicitly counts management of money as a financial product.
  Certifying "no financial features" for a budgeting app contradicts the
  policy's own definition — exactly the class of misdeclaration the 2026
  rolling sweeps remove.
- **Correct declaration: "Other"** with a short free-text description:
  offline personal budget / expense tracking; no funds movement, no
  custody, no transactions, no financial advice, no network requirement
  (free flavor ships with the INTERNET permission removed —
  manifest-guard-pinned).
- **Category:** Finance — already the planned listing category.
- **Additional documentation: none.** License uploads are required only
  for personal-loan features (and certain country lending regimes);
  nothing we declare triggers the documentation table.

## Residuals (honesty ledger)

- "Other" vs the none-certification is a judgment call at the seam
  between the definition sentence and the feature list. The conservative
  direction is chosen deliberately: an over-inclusive declaration costs
  nothing (no docs triggered); a wrong none-certification is a policy
  violation. If certainty is wanted beyond this brief, one Console
  support-ticket phrasing settles it: "offline budgeting app, no money
  movement — is the none-certification correct, or Other?"
- Form field labels can be revised by Google; re-read the declaration
  screen at filing time (the runbook Phase 3 step already says verify
  Console state at migration).

## Actions (lands with this doc)

- [ ] Runbook Phase 3 checklist: add "Financial features declaration =
      Other (offline money management); no docs expected" — owner files.
- [ ] `beta-data-safety-draft.md`: cross-link this determination (#54's
      "note into data-safety.md" ask).
- [ ] Close #54 when the runbook note + this brief are merged (owner word
      for the close itself).
