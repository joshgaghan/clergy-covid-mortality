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

---

# Acceptance run (revision branch, pre-tag)

Recorded 2026-11-10 (Apple silicon, macOS; R 4.5.1, readr 2.1.5, dplyr
1.1.4, tidyr 1.3.1, arrow 21.0.0.1, ggplot2 4.0.0, patchwork 1.3.2). Fresh
clone of the `revision` branch into `~/clergy-ccm-acceptance-rev`,
containing only the repository files; the ten raw zips were copied in from
the local archive (01_data.R recomputes and reports their SHA-256 digests;
NCHS revises files in place, and the control-total canary is the backstop).

**01_data.R** (8 min 47 s): parsed all five NVSS years with the revision's
three added fields and all five ACS years with SCHL; ended on the canary:

```
  total_records                          published 3,390,278  parsed 3,390,278  PASS
  eligible_age15_us_resident             published 3,354,879  parsed 3,354,879  PASS
  coded_occupation_and_industry          published 3,077,127  parsed 3,077,127  PASS
  records_with_census_occupation_codes   published 2,443,813  parsed 2,443,813  PASS
All four control totals reproduce. Run: Rscript 02_analysis.R
```

**verify.R** (1 min 45 s): ran 02_analysis.R (letter verification: 108/108
PASS) and scripts 03-11, then compared every committed numbers.csv row with
the recomputation and ran the Figure 2 same-strata checks:

```
comparing 206 committed rows with 206 recomputed rows
========================================================================
VERIFY: all 206 committed statistics reproduce (<= 1e-8), and every
Figure 2 display set was computed on the same strata.
```

Education-calibration guard inside the run (hardcoded published values):
`guard passed: clergy 35.6/49.7, physicians 89.5/100.0`.

---

# Acceptance run (revision-v1, final)

Recorded 2026-11-18 (Apple silicon, macOS; R 4.5.1 and the renv.lock
package versions: readr 2.1.5, dplyr 1.1.4, tidyr 1.3.1, arrow 21.0.0.1,
ggplot2 4.0.0, patchwork 1.3.2). Fresh clone of the `revision` branch into
`~/clergy-ccm-acceptance-final`, containing only the repository files; the
ten raw zips copied in from the local archive (01_data.R recomputes and
reports their SHA-256 digests; the control-total canary is the backstop).

**01_data.R** (9 min 10 s): parsed all five NVSS years and all five ACS
years; all four published 2020 NCHS control totals reproduce
(3,390,278 / 3,354,879 / 3,077,127 / 2,443,813) — **4/4 PASS**.

**verify.R**: run twice — on the cloned tree (1 min 58 s) and again
(1 min 46 s) after placing the release commit's remaining changes in the
clone (the Table 1 obesity-label alignment in 10_exhibits.R, renv.lock,
and the documentation files; no other analysis code differs). Both runs:

```
comparing 235 committed rows with 235 recomputed rows
========================================================================
VERIFY: all 235 committed statistics reproduce (<= 1e-8), and every
Figure 2 display set was computed on the same strata.
```

02_analysis.R's letter verification inside the run: 108/108 PASS. Table 1
regenerates with the manuscript's obesity row labels ("COVID-19
certificates" / "other certificates"), values unchanged.
