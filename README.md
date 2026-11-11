# clergy-covid-mortality

Reproduces every number in **"COVID-19 Mortality Among US Clergy,
2020-2024"** (Original Investigation revision of manuscript IMD26-3674) and
its supplement. Tag `submission-v1` reproduces the originally submitted
Research Letter; this branch adds the revision's analyses. The archival
record is the full pipeline repository, from which all analysis code here is
extracted verbatim; CHANGES.md lists what changed between the submission and
the revision, including two corrections to submitted estimates.

## Data sources (public; downloaded by script, not redistributed)

- NVSS multiple cause-of-death files, 2020-2024:
  https://ftp.cdc.gov/pub/Health_Statistics/NCHS/Datasets/DVS/mortality/
- ACS 1-year PUMS person files, 2019 and 2021-2024:
  https://www2.census.gov/programs-surveys/acs/data/pums/
- CDC WONDER (region-level counts): interactive; the extract ships as
  `wonder_covid_region.csv`; the four-query specification is in
  `02_analysis.R`, section 11.

## Run

```
Rscript 01_data.R              # downloads ~3.6 GB, parses to parquet; ~9 min
Rscript 02_analysis.R          # the letter analyses + verification
Rscript 03_coverage.R          # coverage, population, floors
Rscript 04_benchmarks.R        # restrictions, 2022-24, race groups
Rscript 05_rank_bootstrap.R    # rank bootstrap (seed 20261106)
Rscript 06_misclassification.R # mixture bound + simulation
Rscript 07_education.R         # education calibration + eFigure
Rscript 08_age_retirement.R    # age windows, late retirement
Rscript 09_rates.R             # harmonized rate ratios
Rscript 10_exhibits.R          # Table 1 + eTables 1-3, guarded
Rscript 11_figures.R           # Figures 1 and 2
Rscript verify.R               # reruns 02-11 and checks every committed
                               # numbers.csv row to 1e-8 plus the Figure 2
                               # same-strata identities; ~2 min for the
                               # whole chain (ACCEPTANCE.md)
```

Scripts 03-11 are one-per-analysis-family and idempotent: each replaces its
own rows of `numbers.csv` (context-tagged) and can be rerun alone. Disk:
~5 GB in `data/` (plus ~1 GB of cached panels), peaking near 8 GB during
parsing; measured on Apple silicon.

## What maps to what

| Manuscript / supplement | Script |
|---|---|
| Table 1 (rates and rate ratios, incl. ages 25-44) | 10_exhibits.R (values: 02 + 09) |
| Table 2 (community and social services) | 02_analysis.R (results/css_disaggregation.csv) |
| Figure 1 (450-occupation ranked benchmark) | 11_figures.R (benchmark: 02) |
| Figure 2A (4 benchmark specifications) | 11_figures.R (strips: 02 + 04) |
| Figure 2B (periods; race and ethnicity) | 11_figures.R (components: 04) |
| eMethods 1 (coverage, blank occupation, population) | 03_coverage.R |
| eMethods 2-4 (coding, causes, denominators, year rate ratios) | 02_analysis.R + 09_rates.R |
| eMethods 5 (PMRs, restrictions, periods, 2022-24, race groups) | 02 + 04_benchmarks.R |
| eMethods 6 (rank bootstrap) + eTable 2 overlap column | 05_rank_bootstrap.R + 04/08 |
| eMethods 7 (misclassification bound) + eTable 3 | 06_misclassification.R |
| eMethods 8 (education calibration) + eFigure | 07_education.R |
| eMethods 9 (age range, retirement) + eTable 2 | 08_age_retirement.R |
| eMethods 10 (geographic composition) | 02_analysis.R, section 11 |
| eMethods 11 (denominator bound) | 09_rates.R |
| eMethods 12 (meat processing by occupation and industry) | 02 (occupation) + 04_benchmarks.R (industry) |
| eMethods 13 (obesity mentions) | 02 + 09_rates.R |
| eTable 1 (top 15) | 10_exhibits.R (benchmark: 02) |

The animal-slaughtering INDUSTRY ratio of eMethods 12 is produced in
04_benchmarks.R's companion row `revision_ind_pmr_meat_processing`
(industry code 1180; the occupation-level rows are benchmark read-offs).

## Verification

`02_analysis.R` ends by verifying the 108 letter statistics against the
letter block of `numbers.csv` on every run. `verify.R` reruns everything and
verifies all committed rows (letter + revision) to 1e-8, then checks that
every set of estimates displayed together in Figure 2 was computed on the
same strata - the check that caught the submission's strata inconsistency
(CHANGES.md).

## Notes

- SHA-256 checks need `shasum`/`sha256sum` (skipped with a warning where
  absent; the control-total canary is the backstop).
- The NVSS zips use Deflate64, which R's built-in `unzip()` cannot read;
  extraction uses the system `unzip` (Info-ZIP 6.0+, standard on macOS and
  Linux).
- Comments citing "CLAUDE.md", memo sections, or "decisions.md" refer to the
  archival repository's development history; `decisions.md` here is the
  copied dated decision log for the revision (including the pre-registered
  stop rule for the age-window benchmarks).
- The hardcoded guards (1.94, 1.86, the education-agreement values, the
  eMethods 6 probabilities) are deliberate: NCHS revises files in place; if
  an estimate moves, the script halts rather than reproduce something other
  than the paper.
- All estimation routines (standardization, Fay-Feuer and exact Poisson CIs,
  rate ratios, OLS, the bootstrap) are base R; the packages below handle
  data and graphics only.

Code: MIT (LICENSE); federal data remain subject to the agencies' terms.
Packages: R 4.5.1, readr 2.1.5, dplyr 1.1.4, tidyr 1.3.1, arrow 21.0.0.1,
ggplot2 4.0.0, patchwork 1.3.2.
