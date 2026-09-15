# Acceptance run (submission-v1)

Re-run 2026-09-14 after code-review fixes (comment corrections; rank-2
figure label now looked up from the crosswalk rather than hardcoded;
DECISIONS block restored in 01_data.R; self-contained stop message;
verification banner count taken from the shipped file). Recorded 2026-09-14 (Apple silicon, macOS; R 4.5.1, readr 2.1.5, dplyr 1.1.4,
tidyr 1.3.1, arrow 21.0.0.1, ggplot2 4.0.0). Fresh directory
(`~/clergy-covid-letter-run2`) containing only the repository files.

**Raw data**: the ten zips were copied in from the local archive rather than
freshly downloaded; all ten SHA-256 digests recomputed by `01_data.R`
**match the Phase 1 record** (10/10), so the copies are byte-identical to
what the official URLs served when the pipeline was built. A fresh-download
run adds ~3.5 GB of network transfer.

## Elapsed time (`/usr/bin/time -p`)

| script | real |
|---|---|
| `01_data.R` (parse incl. month of death + canary; downloads skipped) | 555.1 s (9 min 15 s) |
| `02_analysis.R` (all analyses + verification) | 46.5 s |

## Disk

`data/` after the run: **5.0 GB** (raw zips 3.5 GB, parquet 1.5 GB); peak
~7.9 GB while one year's fixed-width extract (~2.9 GB, deleted after
parsing) coexists with the zips and parquet.

## Verification

- `01_data.R` canary: all four published 2020 NCHS control totals reproduce
  (3,390,278 / 3,354,879 / 3,077,127 / 2,443,813) — **4/4 PASS**
- `02_analysis.R`: **`VERIFICATION: 108/108 PASS, 0 FAIL`** (exit 0), one
  PASS line per statistic in the shipped `numbers.csv`; the computed table
  is written to `results/numbers_computed.csv`
- Within-2021 split guards passed: the month-bearing 2021 frame reproduces
  `build_pmr_deaths(2021)` exactly, and Jan-Apr + May-Dec partition the
  clergy 2021 COVID-19 deaths

## Warnings

One, cosmetic, unchanged from the previous acceptance run: macOS's `pdf()`
device substitutes ">=" for the U+2265 glyph in the figure's axis title
(the PNG renders it correctly; the full pipeline does the same). No other
warnings in either log.
