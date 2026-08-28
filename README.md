# clergy-covid-letter

Reproduces every number in the research letter **"COVID-19 Mortality Among US
Clergy, 2020-2024"** (Gaghan & Eagle, submitted to *JAMA Internal Medicine*)
from public data, in two R scripts. This is the minimal companion for
reviewers and students; the archival record is the full pipeline repository
at tag `jamaim-v2` ([REPO-URL]), from which all analysis code here is
extracted verbatim.

## Data sources (public)

- NVSS multiple cause-of-death files, 2020-2024:
  https://ftp.cdc.gov/pub/Health_Statistics/NCHS/Datasets/DVS/mortality/
- ACS 1-year PUMS person files, 2019 and 2021-2024:
  https://www2.census.gov/programs-surveys/acs/data/pums/
- CDC WONDER, Underlying Cause of Death (region-level counts):
  https://wonder.cdc.gov/ucd-icd10-expanded.html — interactive, so the
  extract is shipped as `wonder_covid_region.csv`; the exact query is
  documented in a comment block in `02_analysis.R` (section 9).

## Run

```
Rscript 01_data.R       # downloads ~3.5 GB, parses to parquet; ~9 min
Rscript 02_analysis.R   # all analyses, figure, verification; ~40 s
```

Measured on an Apple-silicon Mac (times exclude downloads): `01_data.R`
9 min 8 s, `02_analysis.R` 40 s; disk use 5.0 GB in `data/` (raw 3.5 GB +
parquet 1.5 GB), peaking near 8 GB while a year's fixed-width extract exists.

`01_data.R` ends by checking the parse against NCHS's four published 2020
control totals. `02_analysis.R` ends by comparing every computed statistic
against the shipped `numbers.csv`: **all 98 statistics in the published
letter are verified against `numbers.csv` on every run.**

Packages: R 4.5.1, readr 2.1.5, dplyr 1.1.4, tidyr 1.3.1, arrow 21.0.0.1,
ggplot2 4.0.0.
