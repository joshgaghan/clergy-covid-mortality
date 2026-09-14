# clergy-covid-letter

Reproduces every number in the research letter **"COVID-19 Mortality Among US
Clergy, 2020-2024"** (Gaghan & Eagle, submitted to *JAMA Internal Medicine*;
citation will be updated on publication) from public data, in two R scripts.
This is the runnable companion for reviewers and students; the archival
record is the full pipeline repository at tag `jamaim-v3` ([REPO-URL]), from
which all analysis code here is extracted verbatim.

## Data sources (public; downloaded by script, not redistributed)

- NVSS multiple cause-of-death files, 2020-2024:
  https://ftp.cdc.gov/pub/Health_Statistics/NCHS/Datasets/DVS/mortality/
- ACS 1-year PUMS person files, 2019 and 2021-2024:
  https://www2.census.gov/programs-surveys/acs/data/pums/
- CDC WONDER, Underlying Cause of Death (region-level counts):
  https://wonder.cdc.gov/ucd-icd10-expanded.html — interactive, so the
  aggregate extract ships as `wonder_covid_region.csv`; the exact four-query
  specification is documented in `02_analysis.R` (section 11).

## Run

```
Rscript 01_data.R       # downloads ~3.5 GB, parses to parquet; ~9 min
Rscript 02_analysis.R   # all analyses, figure, verification; ~1 min
```

Measured on an Apple-silicon Mac (times exclude downloads): `01_data.R`
9 min 14 s, `02_analysis.R` 46 s; disk use 5.0 GB in `data/`, peaking near
8 GB while a year's fixed-width extract exists.

`01_data.R` ends by checking the parse against NCHS's four published 2020
control totals. `02_analysis.R` ends by comparing every computed statistic
against the shipped `numbers.csv`: **all 108 statistics reported in the
letter are verified against `numbers.csv` on every run.**

Code is MIT-licensed (see LICENSE); the federal data remain subject to the
originating agencies' terms.

Packages: R 4.5.1, readr 2.1.5, dplyr 1.1.4, tidyr 1.3.1, arrow 21.0.0.1,
ggplot2 4.0.0.
