# Changes from `submission-v1` to the revision

`submission-v1` reproduces the Research Letter as submitted. This branch
reproduces the revised manuscript ("COVID-19 Mortality Among US Clergy,
2020-2024", Original Investigation) and its supplement. Nothing at
`submission-v1` was rewritten; the revision adds scripts 03-11, verify.R,
three parsed fields, and the rows and exhibits they produce.

## Corrections to submitted estimates

1. **Cause-restricted benchmarks: strata corrected.** The submitted
   sensitivity estimates excluding external causes (1.95; 95% CI, 1.88-2.02;
   rank 1) and additionally excluding tobacco-related and alcohol-induced
   causes (1.75; 95% CI, 1.69-1.82; rank 2) had been standardized for sex
   and 5-year age only, although the supplement described the benchmark's
   full strata. Recomputed under sex x 5-year age x race and ethnicity (the
   strata of every other estimate): 1.86 (95% CI, 1.79-1.92; rank 1 of 449)
   and 1.69 (95% CI, 1.63-1.76; rank 1 of 449). The occupation previously
   ranked first in the most restrictive comparison (graders and sorters of
   agricultural products) loses its excess once comparisons are made within
   race and ethnicity. The submitted rows remain in numbers.csv (letter
   block) and reproduce at `submission-v1`; the corrected rows carry the
   REVISION_STRATA tag. Reported in the response letter.

2. **Within-group race and ethnicity ratios: standardized within group.**
   The within-group ratios the first-round response reported (Hispanic 1.83;
   non-Hispanic Black 1.80; non-Hispanic White 2.42; non-Hispanic other
   1.72) were crude within-group share ratios: no sex or age stratification,
   which clergy's older age structure inflates. The revision reports each
   group's ratio as the race-specific component of the pooled benchmark
   (sex x 5-year age within the group, the group's own reference
   composition): Hispanic 1.68 (1.55-1.82); non-Hispanic Black 1.73
   (1.59-1.87); non-Hispanic White 2.25 (2.14-2.36); non-Hispanic other
   1.56 (1.34-1.81). The four expected counts, plus the stratum of unknown
   race or ethnicity, sum to the pooled benchmark's expected count, and the
   components pool to exactly the published 1.94; verify.R enforces this
   identity for Figure 2B. Every interval continues to exclude 1,
   non-Hispanic White remains the largest, and no conclusion changes. The
   crude rows remain in the letter block of numbers.csv.

## Additions

- **Parse (01_data.R, layouts/)**: three NVSS fields (education_2003,
  education_flag, ind_code4) and the ACS SCHL variable, for the education
  calibration (eMethods 8) and the industry analysis (eMethods 12). The
  2020 NCHS control-total canary is unchanged and still passes.
- **03_coverage.R**: blank-occupation shares on both bases; the analytic
  population; the within-2021 period floors; the clergy workforce share in
  the 2020 nonreporting jurisdictions (eMethods 1).
- **04_benchmarks.R**: the corrected cause-restricted benchmarks; the
  2022-2024 benchmark and its restrictions; the within-group components
  (eMethods 5; eTable 2's strict-benchmark columns).
- **05_rank_bootstrap.R**: the rank bootstrap, CI-overlap set, and lowest
  drawn ranks (eMethods 6; seed 20261106).
- **06_misclassification.R**: the mixture bound, its inversion, and the
  direct simulation (eMethods 7; eTable 3).
- **07_education.R**: the education calibration - attenuation log odds
  ratios, the age-band table, the eFigure, and the two disclosed earlier
  specifications (the superseded linear fit's rows carry SUPERSEDED_EDU;
  the abandoned logit fit is printed, not stored) (eMethods 8).
- **08_age_retirement.R**: the 25-84 extension, the age-window benchmarks
  with their bootstraps, and the late-retirement index (eMethods 9;
  eTable 2).
- **09_rates.R**: year-specific COVID-19 rate ratios; the same-period
  all-cause rate ratio and the denominator bound (eMethods 11); period and
  per-year non-COVID rate ratios; the 25-44 rate ratio; COVID-anywhere
  rates and both conditional obesity mention ratios (eMethods 13).
- **10_exhibits.R**: Table 1 (Original Investigation version; counts are
  the race-known deaths entering the rates) and eTables 1-3, every cell
  guarded.
- **11_figures.R**: the revised Figure 1 (color key, no in-panel text) and
  Figure 2 (four-benchmark strips; clergy-only forest with the stratified
  race components).
- **verify.R**: recomputes everything and fails beyond 1e-8 against the
  committed numbers.csv; enforces the Figure 2 same-strata checks.
- **decisions.md**: the archival pipeline's dated decision log for the
  revision, copied in (includes the pre-registered stop rule for the
  age-window benchmarks, the education-check sequence, and the 2022-2024
  PMR decision).
- **02_analysis.R**: one compatibility change only - its Section 13
  verification now filters numbers.csv to the letter block (empty context),
  since the file also carries the revision rows.

## numbers.csv

The letter block (108 rows, empty context) is unchanged and still verified
row-by-row by 02_analysis.R. The revision rows carry context tags
(REVISION_C2, REVISION_C3, REVISION_STRATA, REVISION_EDU, SUPERSEDED_EDU,
REVISION_RANK, REVISION_RACE4, REVISION_AGECAP, REVISION_POP,
REVISION_RETIRE, REVISION_AUDIT) naming the analysis family; verify.R
checks all of them.
