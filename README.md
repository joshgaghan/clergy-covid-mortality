# clergy-covid-letter

Reproduces every number in the research letter **"COVID-19 Mortality Among
US Clergy, 2020-2024"** The archival record is the full pipeline repository at tag
`jamaim-v3` ([REPO-URL]), from which all analysis code here is extracted
verbatim.

## Data sources (public; downloaded by script, not redistributed)

- NVSS multiple cause-of-death files, 2020-2024:
  https://ftp.cdc.gov/pub/Health_Statistics/NCHS/Datasets/DVS/mortality/
- ACS 1-year PUMS person files, 2019 and 2021-2024:
  https://www2.census.gov/programs-surveys/acs/data/pums/
- CDC WONDER (region-level counts): interactive; the extract ships as `wonder_covid_region.csv`; the four-query specification is in
  `02_analysis.R`, section 11.

## Run

```
Rscript 01_data.R       # downloads ~3.5 GB, parses to parquet; ~9 min
Rscript 02_analysis.R   # all analyses, figure, verification; ~1 min
```

Measured on Apple silicon, excluding downloads: 9 min 15 s and 46 s;
disk 5.0 GB in `data/`, peaking near 8 GB during parsing. `01_data.R` ends
on NCHS's four published 2020 control totals; `02_analysis.R` ends on the
verification: **all 108 statistics reported in the letter are verified
against `numbers.csv` on every run.**

## Notes

- SHA-256 checks need `shasum`/`sha256sum` (skipped with a warning where
  absent, e.g. stock Windows; the control-total canary is the backstop).
- The NVSS zips use Deflate64, which R's built-in `unzip()` cannot read;
  extraction uses the system `unzip` (Info-ZIP 6.0+, standard on macOS and
  Linux).
- Comments citing "CLAUDE.md", "Phase 1/2/3", briefs, memo sections, or
  "decisions.md" refer to the archival repository's development history and
  audit trail, not files here.
- The hardcoded 1.94 guards are deliberate: NCHS revises files in place; if
  an estimate moves, the script halts rather than reproduce something other
  than the paper.

Code: MIT (LICENSE); federal data remain subject to the agencies' terms.
Packages: R 4.5.1, readr 2.1.5, dplyr 1.1.4, tidyr 1.3.1, arrow 21.0.0.1,
ggplot2 4.0.0.
