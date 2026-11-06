#!/usr/bin/env python3
"""Patch the vendored quarto-live runtime for this site.

Re-run after `quarto update r-wasm/quarto-live`:

    python3 tools/patch-quarto-live.py

What it changes: when an R exercise is graded, quarto-live normally runs the
exercise's solution code as well, so a checker can compare answers. Our checker
(lessons/_setup.qmd) only shows the learnr-style message and never uses the
solution result. For heavy exercises (e.g. separate() on the 405k-row `who`
table in Tidy your Data · Separate), the extra run doubles the wait and after a
few attempts crashes webR ("memory access out of bounds"). This skips it.
"""
from pathlib import Path

path = Path(__file__).resolve().parent.parent / "_extensions/r-wasm/live/resources/live-runtime.js"
src = path.read_text()

old = "a=await this.evaluateSolution();a&&(o.solution_code=a.code"
new = "a=null/*primers: solution not evaluated*/;a&&(o.solution_code=a.code"

if new in src:
    print("already patched")
elif src.count(old) == 1:
    path.write_text(src.replace(old, new))
    print("patched", path)
else:
    raise SystemExit("pattern not found: quarto-live changed; review the patch by hand")
