# 5-year portfolio model instruments

`model5yr.py` regenerates the workbook (owner-requested model,
steiner-portfolio-5yr-model-v4-ios-2026-11-12.xlsx in the workspace).
`model-check.py` is its GATE: run after every regeneration — exit 0 or
the numbers do not leave this folder.

    python3 model5yr.py && python3 model-check.py <out.xlsx>

Rules R1-R7 encode measured failure modes (see docstring); --selftest
proves the gate still bites.
