# Decisions log

Judgment calls not specified in CLAUDE.md. Each entry: date, decision, reason, where it lives in code.

## 2026-08-24 — Raw/interim data stored outside the Box-synced repo
`data/` is a symlink to `~/clergy-mortality-data/` (outside Box CloudStorage).
**Reason:** the repo lives in a Box Drive sync folder. Raw NVSS + ACS PUMS downloads total
~3.7 GB zipped and ~25 GB unzipped; writing them inside Box would trigger cloud upload of
data that CLAUDE.md says must not be committed or shared. The symlink keeps every relative
path in the spec (`data/raw/`, `data/interim/`) working unchanged.
**Where:** repo root symlink; `.gitignore` excludes both `data/` and `data`.

## 2026-08-24 — Python toolchain via `uv`
System Python is 3.9.6 with no third-party packages; spec requires 3.11+. Installed `uv`
(Homebrew) and pinned CPython 3.12.14 in a project venv.
**Reason:** no existing 3.11+ interpreter; `uv` keeps the environment reproducible via
`pyproject.toml` + `uv.lock` without touching system Python.
**Where:** `pyproject.toml`, `uv.lock`, `Makefile` (`PY = uv run python`).

## 2026-08-24 — Race/ethnicity built from Hispanic Origin + Race Recode 40, not from a recode
CLAUDE.md asks for the "race recode (bridged or single-race, whichever is present)".
No single recode is usable across 2020–2024:
- Bridged race (445–450) exists only in 2020; NCHS dropped it from 2021 onward.
- The Hispanic-origin/race recode is at position **488** (bridged-race based) in 2020,
  **reserved and not populated** in 2021, and at **487–488** (single-race based) from 2022.
  The 2024 layout states the 2022+ version is not comparable with the 2020 one.
Hispanic Origin (484–486) and Race Recode 40 (489–490) are the only race/ethnicity items
present and identically defined in all five years, so the analysis categories
(NH White / NH Black / Hispanic / NH other) are derived from those two.
**Where:** `src/groups.py::nvss_race_eth_expr`; positions in `config/layouts/*.yaml`.

## 2026-08-24 — Overlapping cause definitions resolved by an explicit priority order
CLAUDE.md requires one exclusive underlying-cause category per death, but the listed
definitions overlap: K70 is both chronic liver disease and alcohol-induced; X60–X64 are
both suicide and drug poisoning; X85 is both drug poisoning and homicide; I42.6 is both
other cardiovascular and alcohol-induced. Resolved by a documented priority order
(COVID → suicide → homicide → transport → drug poisoning → alcohol-induced → other
unintentional → natural causes → residual). Consequences: K70 and I42.6 count as
alcohol-induced, so the exclusive "chronic liver disease" category is K73–K74 only; the
exclusive drug-poisoning category is unintentional/undetermined only.
To avoid losing the conventional definitions, the overlapping ones are ALSO published as
**non-exclusive indicators** (`drug_poisoning_all_intents`, `chronic_liver_incl_alcoholic`,
`deaths_of_despair`), so both views are available.
**Where:** `config/cause_groups.yaml` (`priority` field), `src/causes.py`,
`tests/test_causes.py::test_documented_overlap_resolutions`.

## 2026-08-24 — NCHS alcohol-induced list is NOT verified against a primary source
The 14-code NCHS alcohol-induced list is implemented from knowledge, not from a fetched
NCHS document. CDC WONDER help pages and the NVSR directory listing did not yield the
code list, and CLAUDE.md forbids hunting mirrors. The stop-and-report rule in CLAUDE.md
is scoped to *record layout positions*, which are all verified, so this does not block
the pass — but it must be checked by a human before anything is published.
**Codes used:** E24.4, F10, G31.2, G62.1, G72.1, I42.6, K29.2, K70, K85.2, K86.0, R78.0,
X45, X65, Y15.
**Where:** `config/cause_groups.yaml`, key `alcohol_induced`. Flagged in the memo Concerns.

## 2026-08-24 — Occupation harmonisation is the coarsest common refinement, not "2018 canonical"
CLAUDE.md asks for 2018 codes as canonical. That is unattainable without imputation: the
2010→2018 revision both split codes (2000 Counselors → 2001–2006) and merged them
(3850+3860 → 3870 Police Officers), so a 2020 record coded 2000 has no single 2018 code.
The analysis code is instead the connected component of the bipartite 2010↔2018 mapping
graph — closed under the crosswalk in both directions, so both schemes map in exactly.
457 of 513 components are a clean 1:1 pair. **Clergy (2040), 2050 and 2060 are 1:1 in both
directions, so Paper A is unaffected.** 6 retired 2012-only and 5 new 2018-only codes are
kept as their own analysis codes rather than being mapped by guesswork.
**Where:** `src/04_crosswalk.py`, `config/occ_crosswalk.csv`, `output/qc/crosswalk_summary.md`.

## 2026-08-24 — Denominator restricted to civilian employed (ESR 1–2); military excluded both sides
CLAUDE.md offers a choice between `ESR in {1,2,4,5}` and "anyone with a nonblank OCCP".
Chosen: **ESR in {1,2}**, i.e. civilian employed, armed forces excluded. NVSS codes military
decedents with NIOSH supplemental codes 9830/9840/9850, which are not Census codes and have
no clean ACS OCCP counterpart; including armed forces in the denominator but matching them
against supplemental numerator codes would put the two sides on different definitions.
Military codes are therefore excluded from "all other employed" as well.
**Where:** `src/03_parse_acs.py::EMPLOYED_ESR`, `src/groups.py::not_employed_codes`.

## 2026-08-24 — "Not in labor force" codes taken from the NCHS/NIOSH supplemental tables
Identified from the I&O background document Tables A and B (pages 6–7), not guessed:
9010 homemaker, 9020 volunteer, 9060 retired, 9070 student, 9100 did not work/child/
patient/disabled/inmate, 9900 blank-or-uncodable, 9830/9840/9850 military.
A **blank** occupation field and code **9900** mean different things: blank = never submitted
for coding (age <15, unknown age, foreign resident, or a non-participating jurisdiction);
9900 = submitted but not classifiable. There is no jurisdiction-participation flag in the
record layout, so non-participating jurisdictions are identifiable only as blanks.
**Where:** `config/occ_groups.yaml`; QC Table 1 reports blank and 9900 separately.

## 2026-08-24 — Combined-sex rates use standard-population sex weights
The 2000 standard population is not published by sex. Clergy are ~85% male against ~53%
male for all workers, so pooling the sexes would leave a large sex-composition difference
uncontrolled. Combined rates are therefore computed as w_M·ASR_M + w_F·ASR_F with weights
from the Census 2000 resident population (0.4906 / 0.5094). Sex-specific rates are
reported alongside and are the primary presentation.
**Where:** `config/std_pop_2000_sex.csv`.

## 2026-08-24 — ACS uses Census 2018 occupation codes in every year, NVSS does not
Verified empirically: ACS 2019–2024 all contain codes 2001–2006 and 2011–2014, which exist
only in the 2018 scheme. So for data years 2020–2022 the numerator is on the Census 2012
scheme while the denominator is on the 2018 scheme. The crosswalk maps both sides to the
common analysis codes. For clergy this is a non-issue (2040 is 1:1), but it matters for the
Paper B occupation profiles and is why harmonisation is applied to ACS as well as NVSS.
**Where:** `src/groups.py::harmonise_occ`, applied with scheme "2018" for all ACS years.

## 2026-08-24 — Gate 1 criterion is ambiguous; both readings reported, strict reading governs
"No ACS clergy age × sex cell has effective n < 100" can mean per-year cells or cells with
person-years pooled over 2020–2024. They disagree (7 of 50 cells fail per-year, minimum 71;
pooled minimum is 447). Rather than silently pick one, both are computed and written to `output/gates.md`.
The pipeline stopped and the question went to the researcher, who decided on
**2026-08-24** that **reading B governs**: Paper A pools 2020-2024, so the pooled
denominator is the one the reported rates actually use, and the per-year cells are never
used on their own. Gate 1 therefore passes and Phases 2-4 proceed. Reading A is still
computed and reported in full, and the 7 thin female-clergy cells (all female, ages <55,
2020-2022) are carried into the memo's Concerns section.
**Where:** `src/05_qc.py`, Gate 1 block, constant `GOVERNING_READING`.

---

# Phase 2 (R pipeline and research letter)

## 2026-08-25 — Alcohol-induced list confirmed; no code change was needed
CLAUDE.md Phase 2 specifies the NCHS alcohol-induced list as
E24.4, F10, G31.2, G62.1, G72.1, I42.6, K29.2, K70, K85.2, K86.0, R78.0, X45, X65, Y15.
Compared code-by-code against what Phase 1 had implemented: **identical**. The Phase 1
concern was that the list was unverified, not that it was wrong. It is now confirmed as
the NCHS "alcohol-induced causes" list used in NVSR mortality reports, and
`config/cause_groups.yaml` is unchanged. The Phase 1 priority order for the overlapping
codes is retained (K70 → alcohol-induced before chronic liver disease; X60–X64 → suicide
before drug poisoning; X85 → homicide before drug poisoning; I42.6 → alcohol-induced
before other cardiovascular), and the non-exclusive indicators are still published.
**Where:** `config/cause_groups.yaml`; asserted in `tests/testthat/test-causes.R`.

## 2026-08-25 — Extraction shells out to /usr/bin/unzip
The NVSS public-use zips use Deflate64 (compression method 9). R's internal `unzip()`
rejects them as "zip file is corrupt", and there is no CRAN package that reads Deflate64.
`R/parse_nvss.R` therefore calls `system2("unzip", "-p", ...)`.
**Reason:** CLAUDE.md forbids `reticulate` and shelling out to Python; `unzip` is neither.
The alternative would be to require a manual extraction step before the pipeline runs.
**Where:** `R/parse_nvss.R::extract_nvss`.

## 2026-08-25 — `R/util.R` added beyond the file list in CLAUDE.md
CLAUDE.md names the analysis modules. `R/util.R` holds only plumbing — project paths,
logging, the filter-count log, and the <20 suppression helper — that every module needs
and that would otherwise be copied into each.
**Where:** `R/util.R`.

## 2026-08-25 — Record length is asserted from file size, not measured per row
Phase 1's parquet carries a `_reclen` column. Reconstructing it in R would mean holding
the full 817-character record for 3.4M rows. Instead the parser asserts that the file size
is an exact multiple of 819 (817 + CRLF) and that the implied row count matches the rows
actually read, then writes the constant. The Python-match test independently confirms the
column agrees with Phase 1 row for row.
**Where:** `R/parse_nvss.R::parse_nvss_year`.

## 2026-08-25 — Community and social services is narrower than in Phase 1
CLAUDE.md Step 4 defines the comparator as "Census codes 2000–2015 in the 2018 scheme".
Verified against the crosswalk: the 2018 scheme has no 2000 or 2010 (both were split), so
the range resolves to source codes 2001–2006 and 2011–2015, i.e. analysis codes
{2001, 2011, 2015}. This **excludes** 2016 (social and human service assistants) and 2025
(other community and social service specialists), both of which the Phase 1 group
included. The Phase 2 definition is the one used, as specified.
**Where:** `R/groups.R::community_social_services`.

## 2026-08-25 — Phase 1 vs Phase 2 denominator comparison is computed in R, not copied
The memo's "what changed when the denominator switched" table needs a Phase 1 column. It
is produced by running the Phase 2 R code under the `ESR ∈ {1,2}` rule rather than by
quoting the Phase 1 Python output, so the two columns differ only in the denominator and
not in the implementation. The Phase 1 published all-cause figure of 0.66 is reproduced as
a check.
**Where:** `_targets.R` target `results_esr12`; `R/memo.R::write_phase2_memo`.

## 2026-08-25 — ACS participation restriction carried forward from Phase 1
CLAUDE.md Phase 2 does not mention `config/io_participation.yaml`, but removing it would
reintroduce the Phase 1 bias: the NVSS public-use file has no state field, so deaths from
jurisdictions that did not report occupation data cannot be removed from the numerator,
and an unrestricted ACS denominator would count people the numerator never had. The
restriction is retained unchanged.
**Where:** `R/letter.R::build_pop_panel`.

## 2026-08-25 — Row-for-row comparisons must use `read_parquet`, not `open_dataset`
The Python-match gate first reported ~22 of 32 columns differing for every year, while a
direct check of the same columns showed them identical. Cause: `arrow::open_dataset()` +
`collect()` runs a multi-threaded scan that does **not** guarantee row order, so reading
two columns in two separate `collect()` calls can return them in different row orders.
Verified: two Dataset reads of the same column from the same file are not `identical()`,
whereas two `read_parquet()` reads are, and `read_parquet()` agrees with the first Dataset
read. The gate and its testthat equivalent now use `read_parquet(col_select=)`.
This affects only code where row order matters. The analysis code is unaffected because
each aggregation collects all its columns in a single `collect()` call and then groups.
**Where:** `R/qc.R::qc_parse_matches_python`, `tests/testthat/test-parse-matches-python.R`.

## 2026-08-25 — ACS person files are read with explicit column types
Reading all 94 retained columns as character and binding both person files before
converting needed several GB of string data and drove the machine into swap: one year took
4,715 seconds. Reading each file with `col_types` fixed (integer for everything except
SERIALNO, SPORDER, OCCP and the state code, which need their leading zeros) and reducing
to the output columns before binding brought it to ~23 seconds per year.
**Where:** `R/parse_acs.R::read_one`.

## 2026-08-25 — Reference occupation codes are analysis codes, not raw 2018 codes
CLAUDE.md Step 4 gives physicians as "3090 in 2018 scheme; verify". Verified, and the
verification mattered: the 2012 code 3060 "Physicians and Surgeons" split into 2018 codes
3065/3070/3090/3100, so the whole component collapses to analysis code **3065**. Filtering
on the literal "3090" matched nothing and silently produced an empty physicians group in
the first run of the validity check. Reference codes are now mapped through the crosswalk
before use. 2310 (teachers) is one-to-one; 2011 and 2012 (social workers) both collapse to
2011, so the pooling CLAUDE.md asks for happens automatically.
**Where:** `R/groups.R::reference_occupations`, asserted by `verify_reference_codes()`.

## 2026-08-25 — Phase 1 reproduction test uses the Phase 1 comparator
CLAUDE.md Step 6 requires reproducing the Phase 1 all-cause figure of 0.66 (0.64–0.67)
under the ESR 1–2 denominator. Two things changed between phases, not one: Step 3 changes
the denominator and Step 4 narrows the community-and-social-services comparator, which
moves people into "all other employed". Holding the comparator at the Phase 1 definition
and switching only the denominator reproduces Phase 1 exactly — 0.655826 against Python's
0.655827, CI 0.6448–0.6671 — which isolates the standardization code, the thing the test
exists to check. Under full Phase 2 definitions the same quantity is 0.6564, still 0.66 to
two decimals but with the lower bound rounding to 0.65 rather than 0.64.
**Where:** `tests/testthat/test-reproduces-phase1.R`.

## 2026-08-25 — Methods paragraph length is enforced, not just noted
CLAUDE.md caps the Methods block at 170 words. The generator now errors rather than warns
if the draft exceeds it, so the constraint cannot drift as numbers are edited. Current
draft: 168 words.
**Where:** `R/memo.R::write_methods_text`.

## 2026-08-25 — Figure 1 uses the standard PDF device
`cairo_pdf` is unavailable on this machine (no X11 libraries), so `ggsave` falls back with
a warning. Figure 1 is written with `grDevices::pdf`, which is still vector output and
meets the JAMA requirement.
**Where:** `R/exhibits.R::build_figure1`.

## 2026-08-25 — Unplanned diagnostic: why obesity-mention is elevated while cardiometabolic is low
CLAUDE.md says not to add analyses beyond the plan without recording the reason. These were
run to answer an interpretation question from the lead author, **not** for the letter, and
nothing from them enters Table 1, Figure 1 or the text blocks.

Question: obesity recorded anywhere gives RR 1.12 (1.04–1.21) while the cardiometabolic
composite gives 0.83 (0.81–0.86). Both are rates over the same person-years, so this is a
real difference in the numerators, not an artefact of the ratio.

Findings:
1. **Differential ascertainment is ruled out.** Conditions listed per record: clergy 3.39,
   other employed 3.42; clergy have slightly *more* single-condition records (19.9% vs
   17.9%). Clergy certificates are not filled out more fully. Hypertension-anywhere is 0.83,
   so there is no blanket inflation of any-mention flags.
2. **The obesity elevation is entirely COVID.** Obesity with COVID on the record, RR 1.94
   (1.67–2.26); obesity with no COVID on the record, 0.97 (0.89–1.07). By period: 1.28
   (1.15–1.43) in 2020–2021 and 0.98 (0.87–1.10) in 2022–2024. COVID was the underlying
   cause on 25.4% of clergy obesity-mentioned deaths against 13.7% for other employed.
3. **The residual pattern is a pathway contrast.** With COVID removed: obesity 0.97,
   diabetes 0.94, hypertension 0.77, cardiometabolic underlying 0.83 — against CLRD 0.27,
   suicide 0.31, alcohol 0.19, drug poisoning 0.13. Clergy's advantage is concentrated in
   the tobacco/alcohol/drug pathways; their metabolic burden is close to average.

Implication for the letter: the Table 1 obesity row is prespecified and stays, but read
alone it invites "clergy are more obese", which the period and COVID splits do not support.
**Where:** diagnostic script only, not in the pipeline. Numbers above are reproducible from
`R/letter.R` helpers.

## 2026-08-25 — Post-hoc COVID-19 stratification added at the lead author's request
The lead author reviewed the obesity/cardiometabolic diagnostic and directed: "At the very
least, I think we need to stratify by COVID." This adds analyses beyond the prespecified
Step 7 plan, so per CLAUDE.md the reason is recorded here. Additions, all labelled post hoc:
- `output/letter/covid_stratified.csv`: obesity/diabetes/hypertension recorded anywhere and
  the cardiometabolic composite, each split by COVID-19 on/off the record, plus the period
  split for obesity. Suppression under 20 applies.
- A footnote on Table 1's obesity row and a clearly-marked post-hoc paragraph in
  `results_text.md`. Table 1's prespecified rows and the sensitivity table are unchanged.
Supporting diagnostic (not in the pipeline): conditional on underlying cause and age band,
clergy and other workers co-mention obesity at nearly identical rates (e.g. COVID deaths at
55–64: 10.2% vs 8.5%; cardiometabolic deaths at 65–74: 4.8% vs 4.3%), and obesity is
mentioned on 8.1%/8.5% (clergy/other) of COVID deaths vs 6.5%/6.7% of cardiometabolic and
2.8%/2.5% of all other deaths. So the 1.12 is composition — clergy had 1.69x the COVID
death rate, and COVID certificates are the certificates that mention obesity most — not
differential certification of clergy.
**Where:** `R/letter.R::run_covid_stratified`, `R/exhibits.R::build_table1`,
`R/memo.R::write_results_text`, `_targets.R` target `covid_stratified`.

## 2026-08-25 — Exploratory: cross-occupation COVID-19 benchmark (not yet in the pipeline)
Run to answer the lead author's question about benchmarking clergy's COVID-19 result against
other occupations. Out of plan, exploratory, and **not** wired into `_targets.R` or any
letter output pending a decision. Two findings, the first of which is a methodological trap
worth recording whether or not the benchmark is adopted.

**1. A rate-based cross-occupation ranking is invalid with this design.** The
numerator–denominator mismatch is not uniform across occupations: it is severe for shrinking
occupations, because the certificate records a *usual lifetime* occupation while ACS counts
current or recent workers. Implied all-cause rates per 100,000 at ages 65–74:
clergy 2,709 (plausible), underground mining machine operators **25,452**, other textile and
apparel workers **20,043** — i.e. a 25% annual mortality rate. Retired miners die recorded as
miners; almost nobody is still working as one at 65–74. Age standardization does not fix this
because the deficiency is *within* age bands. A naive ranking put mining and textile at the
top with rate ratios of 8, which is an artefact, not a finding.

**2. Proportional mortality is the appropriate tool and it validates.** An age- and
sex-standardized proportional mortality ratio uses death records only, so any multiplicative
denominator error cancels. This is the approach NIOSH uses in NOMS for the same reason. The
resulting 2020–2021 ranking reproduces the published occupational COVID literature without
being tuned to it: agriculture, taxi drivers, sewing/textile, food processing, childcare and
personal care at the top; scientists, writers, editors, lawyers at the bottom — the
in-person versus remotable gradient.

Clergy rank **1 of 450** on an all-cause denominator (PMR 2.05) and **2 of 449** on a
natural-cause denominator that removes external, substance and smoking-driven causes, i.e.
the causes where clergy most differ (PMR 1.75, 95% CI 1.69–1.82). So roughly 15% of the
elevation is composition and the rest survives. Clergy are also the only occupation in the
top tier estimated from thousands of deaths (n = 2,922) rather than dozens.

Caveats if this is adopted: PMR is not a risk measure and must not be described as one; the
composition sensitivity must be reported alongside the headline; and JAMA Network Open allows
two exhibits, so a benchmark exhibit has to share or displace Figure 1.
**Where:** exploratory scripts only. Nothing in `output/letter/` derives from this.

## 2026-08-25 — Benchmark robustness: age and race/ethnicity adjustment
Follow-up to the exploratory benchmark above, still not in the pipeline. Two confounders
could inflate clergy's COVID-19 proportional mortality; both were tested.

| Adjustment | Clergy PMR (95% CI) | Rank |
|---|---|---|
| sex x 10-year age | 2.05 (1.97–2.12) | 1 of 450 |
| sex x 5-year age | 2.05 (1.97–2.12) | 1 of 450 |
| sex x 5-year age x race/ethnicity | 1.94 (1.87–2.01) | 1 of 450 |
| natural-cause denominator (composition) | 1.75 (1.69–1.82) | 2 of 449 |

Within-band age structure explains none of it (10-year and 5-year strata agree to two
decimals). Race/ethnicity explains little: clergy are more Black than the employed workforce
(23.5% of clergy deaths vs 16.9%), but adjustment moves the PMR only 2.05 → 1.94, because
clergy are elevated **within every group**. Share of 2020–2021 deaths that were COVID-19,
clergy vs all employed: Hispanic 47.4% vs 25.9%; non-Hispanic Black 23.8% vs 13.2%;
non-Hispanic White 23.2% vs 9.6%; other 27.5% vs 16.0%. The largest relative gap is among
non-Hispanic White clergy (2.4x), which rules out the explanation that the finding reflects
minority clergy serving high-exposure communities.

Internal corroboration: Directors of Religious Activities and Education (code 2050), the
sibling occupation, independently ranks 5th on the race-adjusted measure (1.45, 1.10–1.86).
The rest of the adjusted top ten are recognisable frontline roles — taxi drivers, EMTs,
police and correctional supervisors, residential advisors.
**Where:** exploratory scripts only; nothing in `output/letter/` derives from this.

## 2026-08-25 — Reframe: COVID-19 foregrounded; Original Investigation track
Author decision (lead author, 2026-08-25), after reviewing the benchmark robustness
results: foreground the COVID-19 finding and target an Original Investigation rather than
the research letter. Consequences implemented:
- **Prespecification framing dropped, not transferred.** The "prespecified primary
  outcome" language originated as an unexamined suggestion during planning, not a
  registered protocol; the author has said not to treat it as binding. The Methods text no
  longer claims prespecification for anything. No analysis is deleted: the cardiometabolic
  composite and all Step 7 analyses remain computed and reported. What must NOT happen is
  the word "prespecified" reappearing in the manuscript attached to the COVID analyses,
  which were not.
- **Benchmark promoted into the pipeline** (`R/benchmark.R`, targets `pmr_panel`,
  `benchmark`, `figure2`, `table2`, `table3`), with unit tests including one that
  documents PMR's self-dilution property (scaling one occupation's deaths perturbs the
  reference; negligible at clergy's 0.4% share of deaths, tested at ~0.3%).
- **New exhibits:** Figure 2 (benchmark ranking + clergy age gradient), Table 2
  (robustness ladder), Table 3 (within-race COVID share — main text, not supplement,
  because it carries the argument against the community-composition explanation).
- The 170-word Methods cap was the letter constraint and no longer binds; the generator
  now enforces a 220-word ceiling instead.
- The letter-format outputs (Table 1, Figure 1, sensitivity.csv) remain built and current;
  nothing is discarded if the venue decision changes.
**Where:** `R/benchmark.R`, `R/exhibits.R`, `R/memo.R`, `_targets.R`,
`tests/testthat/test-benchmark.R`.

---

# Phase 3 (letter pipeline and submission-ready repo)

## 2026-08-26 — Test files live in tests/testthat/, not tests/
The Phase 3 brief names `tests/test_pmr.R` and `tests/test_letter_numbers.R`. The repo's
established harness is testthat with all suites under `tests/testthat/` and shared setup
in `helper-setup.R`; the new tests are `tests/testthat/test-pmr.R` and
`tests/testthat/test-letter-numbers.R` so a single `test_dir()` runs everything.
**Where:** `tests/testthat/`.

## 2026-08-26 — The natural-causes exclusion list is moved, not redefined
The brief says the list is "already defined in config/cause_groups.yaml under the name
Phase 2 used". It is not: config/ defines the cause CATEGORIES; Phase 2 defined the
exclusion list (by category key, plus lung cancer via cancer_site) in `R/benchmark.R` as
`PMR_EXCLUDE_CAUSES`. The identical list moved to `R/pmr.R` as the single definition;
`benchmark.R` now reads it from there. config/ untouched, per the do-not-touch rule.
**Where:** `R/pmr.R`, `R/benchmark.R`.

## 2026-08-26 — benchmark.R keeps a thin wrapper; refactor verified byte-identical
The PMR computation now has exactly one implementation (`pmr_core` in `R/pmr.R`).
`benchmark.R::pmr` is a three-line aggregation wrapper so the full-paper targets keep
their shape. The refactor necessarily invalidated the `benchmark` target; it was rebuilt
once and `covid_pmr_by_occupation.csv` / `covid_pmr_robustness.csv` are byte-identical to
pre-refactor. A first rebuild attempt failed with a targets DAG cycle: `pmr_core`'s
`arrange(desc(pmr))` is read by static analysis as the global function `pmr`, creating
pmr -> pmr_core -> pmr; fixed with the `.data` pronoun.
**Where:** `R/pmr.R::pmr_core`; commits "phase3: pmr refactor*".

## 2026-08-26 — letter figure1.pdf/png replaces the Phase 2 file of the same name
The brief specifies `output/letter/figure1.pdf` for the letter's ranked-PMR figure. The
Phase 2 exhibit target `figure1` (cardiometabolic + COVID age panels) wrote the same
path. The letter figure now owns the file name, matching the letter's single exhibit;
the Phase 2 figure remains regenerable via `tar_make(figure1)`, which would overwrite.
The two are never needed simultaneously.
**Where:** `R/letter_targets.R::letter_figure_build`.

## 2026-08-26 — CI omissions in the letter are reported, not failed
`test-letter-numbers.R` fails on any pipeline VALUE absent from the letter, but reports
missing CI strings as messages: the letter deliberately omits CIs for seven secondary
point estimates (drug, alcohol, suicide, and the four COVID-certificate rows) to stay
inside the word limit. Flagging them as failures would tell the author to "fix" an
intentional editorial choice.
**Where:** `tests/testthat/test-letter-numbers.R`.

## 2026-08-26 — CITATION.cff carries a TODO on the second author's given names
Author names inferred from the project (Gaghan from the maintainer identity; Eagle from
the folder name and the letter's self-citations, "Eagle DE"). Given names must be
confirmed by the authors before the DOI is minted; repository URL and DOI are
placeholders until publication.
**Where:** `CITATION.cff`.

## 2026-08-26 — R downloader hashes with openssl; Phase 1 hashes cross-checked
`R/01_download.R` logs SHA-256 via the openssl package (already in renv) to
`data/raw/checksums_r.tsv`. All hashes match the Phase 1 Python-computed values in
`data/raw/checksums.tsv` for every raw file, so the two downloaders are interchangeable
and the raw data on disk are what Phase 1 validated.
**Where:** `R/01_download.R`.

## 2026-08-27 — CSS disaggregation: label correction, both specialist codes included
The task brief labels code 2016 "community and social service specialists all other".
Verified against the crosswalk: 2016 is **Social and Human Service Assistants**; the
"all other" specialists are **2025**. Both are included in the disaggregation. Counselor
codes 2001-2006 and social-worker codes 2011-2014 collapse to analysis codes 2001 and
2011 respectively (splits of the 2012-scheme 2000/2010), so those occupations are pooled
by construction, as the brief intends. Group-level PMRs are computed as
sum(observed)/sum(expected) over member occupations against the unchanged all-employed
reference - algebraically identical to running the group as a single occupation. The four
new numbers.csv rows are not yet cited in the letter and are exempted from the
draft-verbatim test via an explicit named list, to be removed as they enter the prose.
**Where:** `R/letter_targets.R::css_pmr_summary`, `output/letter/css_disaggregation.csv`,
`tests/testthat/test-letter-numbers.R::NOT_YET_IN_LETTER`.

## 2026-08-27 — Geographic bound: soft-pending, and the comparator choice
(1) The brief says stop-and-print when `config/wonder_covid_region.csv` is absent. Inside
`tar_make()` a hard error would block the unrelated letter targets (pipeline option
`error = "stop"`), so the target instead prints the exact WONDER query, writes
`output/letter/geo_bound_PENDING.md`, and skips the `pmr_geo_*` rows; nothing is estimated
in place of the missing data. (2) "All other employed" in the bound denominator is the
letter's comparator group (`other_employed` from `assign_group`, which excludes
clergy-broad and the community-and-social-services group), for consistency with every
other clergy-vs-other estimate. (3) New config files added (`state_region.csv`,
`std_pop_2000_5yr.csv`, `raceeth.yaml`, `README.md`); no existing config file touched.
The 5-year standard population pairs sum exactly to the Phase 1 10-year values
(asserted in tests).
**Where:** `R/geo_bound.R`, `config/README.md`.

## 2026-08-27 — Harmonized standardization: joint standard and unknown race
The joint standard weight is w(age5, sex, race) = std2000(age5) x all-employed ACS share
of (sex, race) WITHIN that age band — age composition from the external standard,
sex/race composition from the study population, per the brief. Deaths with unknown race
cannot enter race-stratified cells and are excluded from the harmonized numerators only:
14 of 23,234 clergy deaths (0.06%) and a similar share of comparator deaths, which is why
`_harm` rows carry n = 23,220 etc. The cardiometabolic composite was harmonized for the
memo comparison but not added to numbers.csv (the letter does not cite it).
`harmonized_build` reads numbers.csv for the side-by-side "old" columns outside the
target graph; the old rate-ratio rows never change, so the untracked read is safe.
**Where:** `R/harmonize.R`, `config/raceeth.yaml`, `output/letter/rr_harmonized.csv`.

## 2026-08-27 — Within-race PMRs are arithmetic on the Phase 2 output, not recomputed
`pmr_clergy_nhwhite/nhblack/hispanic` are read from the persisted Phase 2
`covid_share_by_race.csv`: value = observed clergy COVID deaths / expected at the
all-employed within-race share (identical to the stored ratio, asserted at build), with
exact Poisson CIs computed from the stored counts. These are within-stratum share ratios
(crude PMRs), age/sex-unadjusted within each race group, and are labeled as such.
**Where:** `R/letter_targets.R` (Part C block).

## 2026-08-27 — WONDER retrieval and two integration fixes
The region-specific death counts were retrieved from CDC WONDER interactively (four
queries per output/letter/geo_bound_PENDING.md; the database is now titled 2018-2024 but
the query is identical to the 2018-2023 spec). The lead author approved accepting
WONDER's data-use restrictions in chat before the queries were run. Counts were read from
the on-screen results tables (no exports downloaded) and assembled into
config/wonder_covid_region.csv with per-run checksums recorded in the file header.
Note: WONDER states are state of RESIDENCE while I&O participation is the registration
jurisdiction; for a composition bound at region level the distinction is negligible and
is noted here rather than adjusted for.

Two pipeline defects found and fixed during integration:
1. `tar_source("R")` executed `R/01_download.R` (a script, not a function library) on
   every `tar_make`, silently re-running the download check. It is now excluded from
   `tar_source` and run explicitly per the README.
2. `config/wonder_covid_region.csv` was read inside targets without being tracked, so
   supplying the file did not invalidate `letter_geo`/`letter_numbers`. A cue target
   (`letter_wonder_state`, md5 of the file or "absent") now threads through both, so the
   pipeline reruns exactly when the file appears or changes and still degrades gracefully
   to the PENDING path when it is absent.

Interpretation guard, also stated in the memo: the prespecified geography-adjusted PMR
(observed / composition-only over region x age x sex) double-adjusts age and sex, which
the PMR already conditions on; the region-only composition ratio (0.996) is the clean
geography-only bound. Both are reported as specified.
**Where:** `R/geo_bound.R`, `_targets.R`, `config/wonder_covid_region.csv`.

## 2026-08-27 — Draft 3 assembled from draft 2 by scripted substitution
`jamaim_letter_draft_3.md` was produced from the author's draft 2 by 14 exact-string
substitutions (each asserted to occur exactly once), replacing every cited rate ratio
that has a `_harm` counterpart with the harmonized value; PMRs and counts untouched.
Two sentences were inserted where the task's "[paste above]" placeholders arrived
empty; the wording is the pipeline author's proposal, cites only numbers.csv values
(geography: 1.08 and 1.00; within-race: 2.42/1.80/1.83 with CIs), and awaits the
lead author's edit. The Methods standardization sentence was changed as instructed.
Three flags for the author, reported rather than fixed:
1. **"at parity" is no longer accurate for diabetes**: the harmonized non-COVID
   diabetes mention ratio is 0.89 (95% CI, 0.85-0.93), which excludes 1 below the
   null; draft 2's 0.94 (0.90-0.98) also excluded 1, so the word was already
   arguable, but the substitution widens the gap.
2. The within-race sentence was inserted per the task instruction even though draft
   2's submission notes say those PMRs were "removed from the letter; retained for
   the companion paper" - the task, being later, was treated as controlling.
3. Rows the draft no longer cites (16 sex-only ratios superseded by _harm values,
   taxi/childcare, diabetes-underlying and diabetes-on-COVID rows, two geo variants)
   moved to the verbatim test's exemption list; pmr_teachers, pmr_directors_religious
   (+rank), pmr_religious_other (+rank) added to numbers.csv per the draft's own
   submission note.
**Where:** `output/letter/jamaim_letter_draft_3.md`,
`tests/testthat/test-letter-numbers.R`, `R/letter_targets.R`.

## 2026-08-27 — Letter figure relabeled for draft 3; manuscript figure left alone
The letter figure's PMR values are unaffected by the harmonization pivot (the benchmark
was race-adjusted from the start), but its labels lagged the prose: draft 3's Results
cite teachers and its Discussion names the two other religious occupations. The figure
now labels all eight occupations the letter discusses — clergy, taxi drivers, directors
of religious activities, religious workers all other, childcare workers (kept per the
author's "shown in Figure" note), teachers, physicians, lawyers — with a fixed
leader-line ladder for the rank-1-to-17 cluster so labels cannot collide.
The companion manuscript's two-panel figure (figure2.*) is deliberately NOT updated:
its Panel B plots the sex-only age-band rate ratios, which is internally consistent
with the manuscript text, which is still entirely sex-only. If the companion paper
adopts the harmonized standardization, Panel B and the manuscript text must move
together in one revision.
**Where:** `R/letter_targets.R::letter_figure_build`.

## 2026-08-27 — Exhibits and supplement (jamaim-v2)
1. **Figure mismatch was labeling, not data.** The old figure used the same
   race-adjusted benchmark as numbers.csv; unlabeled rank-2/3 points made leader lines
   ambiguous. Fixed by labeling rank 2 and shrinking the clergy marker; the labeled
   points are persisted to figure1_points.csv and tested against numbers.csv.
2. **Occupation-name rows** (`pmr_rank2_occupation`, `pmr_natural_rank1_occupation`)
   carry the name in `note`; value is the PMR where meaningful and NA for the pure name
   row, with the numbers-build guard relaxed only for `_occupation` rows. The verbatim
   test checks the NAME appears in the citation surface for such rows.
3. **Verbatim surface widened** to draft + table1.md + supplement.md; exemptions cut to
   five rows. Rate rows format to one decimal in the test, matching the letter
   convention.
4. **table1.docx ownership**: the letter Table 1 now owns output/letter/table1.docx,
   replacing the Phase 2 cardiometabolic exhibit file (still regenerable via the
   full-paper target, same name-collision policy as figure1).
5. **Tag ships with one intentionally red test**: the task mandates a reference-order
   test that must fail on draft 3 (refs 5 before 4) and forbids fixing the prose. All
   793 other tests pass; jamaim-v2 is tagged with this single documented failure.
6. Draft 3's Methods still cites the 1.08 region x age x sex composition figure that the
   supplement marks as not reported; flagged for draft 4 rather than edited.
**Where:** `R/letter_targets.R`, `R/harmonize.R`, `R/geo_bound.R`,
`tests/testthat/test-figure-labels.R`, `test-reference-order.R`, `test-letter-numbers.R`.

## 2026-08-27 — Review fixes (post jamaim-v2)
1. **Counts reconciled via Table 1 option B**: counts = full category counts; rates and
   ratios standardized on the known-race subset (14 of 23,234 clergy deaths excluded,
   one of them the 2020-2021 COVID death behind 2,922 vs 2,921), stated in the table
   footnote. Chosen over rewriting the demographic sentence because the table is
   pipeline-owned and the prose is not.
2. **"Natural causes" relabeled and both variants computed.** The exclusion set also
   removes natural alcohol-induced deaths, so the honest label is "excluding external,
   alcohol-induced, and smoking-related causes" (the author's proposed label omitted
   alcohol). Strict natural = ICD-10 V01-Y89 and U03 excluded (new column
   natural_strict in build_pmr_deaths; cause_restriction = "strict_natural"). Result:
   clergy 1.95 (1.88-2.02), rank 1 of 449; the 1.75 becomes the conservative variant.
   Existing "natural" option and all its values unchanged.
3. **Section 8 corrected**: the old figure's labels were right; the mismatch was a
   linear reading of the log axis. Recorded rather than silently rewritten.
4. **WONDER database name** unified to 2018-2024 Single Race (the database queried);
   wonder_query_text, the PENDING doc, and the supplement now agree.
5. New rows pmr_clergy_natural_strict(+rank) and pmr_natural_strict_rank2_occupation;
   strict rows exempt from the verbatim test until the draft-4 sentence lands.
**Where:** `R/pmr.R`, `R/letter_targets.R`, `output/letter/supplement.md`, memo section 9.

## 2026-08-27 — Death-care contrast rows added
Author-requested lookup. Codes verified via the crosswalk: 4465 (morticians,
undertakers, and funeral arrangers; the 2012 label says "Funeral Directors") and 4461
(embalmers, crematory operators, and funeral attendants); 0325 (funeral home managers)
is below the 100-death floor and is not added. Values from the existing race-adjusted
benchmark, no recomputation. Both rows exempt from the verbatim test until cited.
**Where:** `R/letter_targets.R`, memo section 10.

## 2026-08-28 — Expected/excess/share/workforce rows for the number pull
Five rows added at the lead author's request, all sourced from the benchmark table's own
expected column (never observed/PMR hand division) except the workforce CI, which no
existing output carried: it is a new counts-only computation (mean annual ACS-weighted
clergy under the primary denominator, SDR CI from the 80 replicate weights). Values:
expected 1,506; excess 1,416; clergy COVID share 26.3% vs 13.5% expected; workforce
489,712 (95% CI, 480,465-498,959). FLAG: the draft's planned "workforce of ~450,000"
clause does not match the primary-denominator workforce (~490,000); ~450,000 corresponds
to the currently-employed (ESR 1-2) definition, which is not the letter's denominator.
The author must either say ~490,000 or switch the clause's definition explicitly. All
five rows exempt from the verbatim test until cited.
**Where:** `R/letter_targets.R::clergy_workforce`, numbers.csv (98 statistics).

## 2026-08-31 — Supplement revision (seven author-requested changes)

Edited `letter_supplement_build()` (never supplement.md directly) and
regenerated. (1) eMethods 2 adds the death-care contrast codes with scheme
mappings read from the crosswalk — analysis 4465 is 2012 "Morticians,
Undertakers, and Funeral Directors" / 2018 "...Funeral Arrangers"; analysis
4461 maps from 2012 source code 4460 "Embalmers and Funeral Attendants" —
plus the note that Funeral Home Managers (0325) fall below the 100-death
floor (verified directly: 37 deaths 2020-2021; the count is deliberately not
printed in the supplement, to keep every printed number traceable to
numbers.csv). (2) eMethods 5 derives expected/excess/observed-and-expected
shares, and (3) eMethods 4 the workforce estimate with SDR CI — all five
values read from numbers.csv via gn() at build time, formatted exactly as the
verbatim test formats them. (4) The second cause restriction now states only
its increment over the external-causes restriction. (5) eMethods 3 notes the
drug-poisoning/suicide code overlap (X60-X64), so Table rows are not
mutually exclusive. (6) "smoking-related" -> "tobacco-related" throughout the
supplement, incl. the eTable 4 title, matching the letter; NOTE the
numbers.csv note fields for pmr_natural_rank1_value and pmr.R comments still
say "smoking-related" — left untouched because numbers.csv is not to be
rewritten for a label; flag for the next numbers rebuild. (7) eMethods 1 adds
the numerator-geography sentence. The five expected/excess/share/workforce
rows left NOT_YET_IN_LETTER (the supplement now cites them; the verbatim
guard covers them). Diff of old-vs-new supplement shows exactly the seven
changes; verbatim test passes both directions; letter_table1 rebuilt (stale
since 2026-08-28) and byte-identical. No estimate changed.

## 2026-09-01 — Draft-9 GATE computation and test surface repoint

**GATE (draft-9 author note, obesity sentence).** Computed the conditional
obesity-mention comparison directly rather than inferring it from 2.07/2.05:
observed clergy obesity mentions among deaths with COVID-19 on the
certificate vs the count expected at the other-employed stratum-specific
mention proportions (sex x 5-y age x race/ethnicity, unknown race excluded,
2020-2024), exact Poisson CI - new function
letter_targets.R::obesity_conditional_covid(), new numbers.csv row
obesity_share_covid_certs_ratio. RESULT: 1.22 (95% CI, 1.09-1.37), n = 293 -
NOT near 1.0, despite the crude shares sitting at rough parity (7.9% clergy
vs 8.3% other): clergy COVID-19 deaths skew old and obesity mentions fall
with age, so composition masks a within-stratum excess. Flagged to the
author per the note's instruction; the draft-9 sentence ("about as often")
is contradicted by the standardized version and the deleted severity-factor
clause is partially rehabilitated. No prose edited.

**New rows.** clergy_deaths_2020_2021 = 11,123 (benchmark denom_deaths
column; sources draft 9's "2,922 of 11,123") and the GATE row above. All 98
pre-existing rows verified NA-safe identical after rebuild; letter_table1
and letter_supplement regenerated with no content change (writeup copy
still identical).

**Tests.** Verbatim and reference-order tests now target
../writeup/letter_draft.md (draft 9; skip gracefully if the folder is
absent). Reference-order passes - draft 9's renumbering resolved the
designed failure. Exemption changes: pmr_morticians removed (draft 9 cites
1.15); clergy_person_years and pmr_lawyers added (author cut both from the
draft-9 prose); obesity_share_covid_certs_ratio added (no value cited);
clergy_deaths_2020_2021 added to COUNT_ROWS; "100,000" allow-listed in the
stray-number check as the rate unit. Full suite green for the first time:
794 pass, 0 fail.

**Outstanding author items carried from draft-9 submission notes:** embalmers
row (1.06) still needs its supplement home (eTable 1 area or a comparator
eTable); companion repository (clergy-covid-letter) ships the 98-row
numbers.csv and needs a refresh before release now that the canonical file
has 100 rows.

## 2026-09-01 (later) — Obesity sentence revised in the letter (author-directed)

At the author's explicit instruction (the one action the standing rules
reserve for it), revised writeup/letter_draft.md and regenerated
letter_draft.docx: header bumped to draft 10 with a change note; the
Discussion sentence now reports the standardized conditional ratio 1.22
(95% CI, 1.09-1.37) in place of "about as often", keeps the off-certificate
parity (0.97), and restores the severity-factor clause; the draft's gate
note replaced with its resolution. Body word count 871 -> 893 (+22; the
draft's own target is ~800 - flagged). obesity_share_covid_certs_ratio
removed from NOT_YET_IN_LETTER; verbatim and reference-order tests pass on
draft 10.

## 2026-09-01 (evening) — Submission supplement (JAMA format)

letter_supplement_build() gains a `submission` flag (default FALSE; internal
version verified byte-identical after the refactor). submission = TRUE writes
output/letter/supplement_submission.docx via pandoc from a markdown
intermediate: JAMA front matter (Supplemental Online Content, citation
placeholder, contents, provided-by-the-authors line), bold "eMethods N."
headers, page-number footer (config/supplement_reference.docx, a pandoc
reference doc with a PAGE-field footer), a real page break after the title
block. Differences from internal: eTables dropped (JAMA IM research-letter
supplements are brief methods only); every pipeline reference stripped
(paths, functions, config, numbers.csv citations); jurisdictions spelled out;
WONDER block reframed as the query run, no config paths; eMethods 4 adds the
conditional obesity-ratio derivation (1.22 [1.09-1.37], read from numbers.csv
at build time, with a stop-if-absent guard on the row); funeral occupations
framed as comparators; no embalmers estimate (internal/repo only). New target
letter_supplement_submission. Render check: structural XML verification
(page break, footer wired, no pipeline strings) + QuickLook render of the
docx + Chrome-print PDF of the full content, all pages inspected. Word and
Pages AppleScript PDF export both stalled on an invisible modal (likely the
one-time automation/first-run consent), so the pixel-final Word pagination
was not machine-checked; flagged in the report. Copy shipped to
writeup/supplement_submission.docx — the task's Box path placeholder was
unfilled; writeup/ is where submission materials live. GENERATED FILE: the
writeup copy must not be hand-edited; regenerate via
targets::tar_make("letter_supplement_submission").

## 2026-09-02 — Single-year and sub-year COVID-19 estimates

Task brief said "Read CLAUDE.md": no CLAUDE.md exists in the repo (retired in
Phase 3 hygiene; its rules live in README.md and this file). Judgment calls:
(1) Month of death is not in the interim parquet and R/parse_nvss.R is
frozen against the Python-match test, so R/pmr_period.R re-reads month (and
the sex byte) from the raw 2021 fixed-width file and aligns BY RECORD ORDER;
alignment is asserted (sex must match the parquet on every record) and the
rebuilt 2021 frame must reproduce build_pmr_deaths(2021)'s row count and
COVID-19 total, else the run stops. Month cached to
data/interim/nvss_2021_month.parquet. (2) Split boundary April 30, 2021 (all
US adults vaccine-eligible April 19; month is the finest public granularity,
so April is the last fully pre-eligibility month). (3) Year-specific
harmonized rate ratios use the SAME standard weights as every other _harm
row (all-years all-employed composition) so the two years differ only in the
data, not the standard. (4) Clergy-broad year PMRs from summed
observed/expected over 2040/2050/2060 in an unfloored run (the
css_pmr_summary group construction). (5) The >=50-floor sensitivity is
reported in the rank rows' notes rather than as separate rows. (6) The
pooled 1.94 guard ran and passed; all 100 pre-existing numbers.csv rows
verified identical. New rows (8) marked NOT_YET_IN_LETTER.

Also observed today: writeup/ was reorganized by the author (Sep 2-10) - the
markdown letter and supplement moved to writeup/archive/, letter_draft.docx
is now the working copy (edited Sep 10), and writeup/supplement_submission.docx
was modified after generation despite the do-not-hand-edit warning (word
count 1,116 vs generated 1,143; the citation placeholder line appears
removed). The two letter-surface tests now SKIP (their target,
../writeup/letter_draft.md, no longer exists). Flagged to the author;
options are to re-point the tests at the docx (extract text via pandoc at
test time) or restore a markdown working copy.

## 2026-09-14 — JAMA IM submission package (output/submission/jamaim-2026-09/)

Blockers: eMethods 5 year-split methods added to both supplement versions
(builder-owned); the hand-deleted citation line returns because the builder
always emitted it; the ONE other hand edit found in the writeup
supplement_submission.docx - the WONDER block rewritten as prose plus a
4-row query table - was folded into the builder verbatim (do-not-discard
rule). Manuscript: 15 mechanical fixes applied in word/document.xml of the
author's letter_draft.docx (runs coalesced first); references are Zotero
CSL fields, so a Zotero refresh would REGRESS every reference fix and the
Goldsmith-Pinkham correction (the typo also lives in the Zotero library
JSON) - flagged. Ref 5's existing ". 2021." was replaced rather than
appended to avoid a doubled year. Ref 2 cites the CISA landing page (the
v2.0 PDF is no longer hosted; verified 404). Ref 7 pages confirmed 1-33 on
PubMed (already correct). IRB item STOPPED per brief: the instructed target
"[BLINDED] Institutional Review Board" does not appear (text reads "Duke
Institutional Review Board"); no determination letter in the repo; left
unchanged for the author. Body word count 795 (<=800). Figure: cairo
unavailable in this R build, so the submission PDF uses the quartz device
(fonts embedded, verified with pdftools) and the TIFF is quartz + sips LZW
re-encode (2380x1470 = 350 dpi, RGB; carries an opaque alpha channel -
regenerate via ImageMagick/Pillow if the portal objects). Verbatim and
reference-order tests re-pointed at 01_manuscript.docx (pandoc text
extraction at test time; superscript citation parsing); four newly cited
year-split rows left NOT_YET_IN_LETTER. Supplement number audit: every
numeric token traces to numbers.csv or documented configuration (the only
non-matches are ICD codes U07.1/Y87.0 and the Race Recode 40 field name).
Data-sharing statement cites the companion reproduction repository
(acceptance 98/98 recorded), with [GitHub URL]/[Zenodo DOI]/[tag]
placeholders; NOTE the companion ships the 98-row numbers.csv and must be
refreshed (now 110 rows) before the DOI is minted. Package copied to
writeup/submission_jamaim/ - BOTH copies are generated; edits go through
the builders. Cover letter, title page, STROBE assembled from pandoc
markdown (sources in the session scratchpad; regeneration trivial).

## 2026-09-14 (later) — Companion repository rebuilt for submission

clergy-covid-letter superseded per the new brief: numbers.csv now the
108-statistic submission file; month of death parsed in the companion's main
pass (the full repo's record-order re-read is unnecessary there, with the
same two verification guards kept); new sections for year-specific PMRs,
the within-2021 split, year-specific rate ratios, and the conditional
obesity ratio, all extracted verbatim; LICENSE (MIT, with a federal-data
note) and CITATION.cff added. Tagged the FULL repo jamaim-v3 at the
submission-package commit so the companion's origin comments and README
reference a real archival tag (the brief said "at the submission tag";
none existed). Acceptance: control totals 4/4; VERIFICATION 108/108 PASS;
9m14s + 46s; companion committed and tagged submission-v1. GitHub/Zenodo
steps printed for the author; nothing pushed or minted.

## 2026-11-05 — JNO R&R revision statistics (response-letter inputs, C1–C3)

- **numbers.csv gains a `context` column.** Revision statistics are appended
  with context REVISION_C1/C2/C3; all 108 pre-existing letter rows are
  byte-identical (verified against a pre-append snapshot) with context NA.
  The verbatim letter test now scopes itself to rows without a context tag
  (one guard added at the top of test-letter-numbers.R); every other test
  reads rows by name and is unaffected.
- **The append is post-pipeline.** `tar_make()` rebuilds numbers.csv with
  letter rows only; `revision/04_append_and_verify.R` is idempotent (strips
  prior REVISION_ rows, re-appends) and must be rerun after any rebuild of
  the letter_numbers target.
- **C1 label matching:** the memo's "miscellaneous agricultural workers"
  resolves to analysis code 6050; the agriculture pattern also surfaced six
  adjacent agricultural occupations, kept in c1_granularity_lookups.csv as
  context but not appended to numbers.csv. "Slaughterers" matched no label:
  neither census scheme carries a separate slaughterers code (SOC 51-3023
  folds into the butchers/meat/poultry/fish processing code), stated in the
  C1 output. All matched codes cleared the 100-death floor, so no
  below-floor caveat was needed.
- **C2 all-cause-advantage variant:** a PMR is a composition measure, so an
  all-cause mortality LEVEL for the misclassified pool cancels and cannot
  enter the mixture without an assumption about that pool's COVID-19 share;
  the reference-composition assumption (PMR = 1) is the neutral case and is
  conservative for any contaminating pool with a below-reference COVID
  share. Noted in the derivation rather than computed, per the memo's
  "otherwise note it as conservative."
- **C3 blank-occupation share:** 9.08% of ALL 2020 deaths (any age,
  including under-15s who are never submitted for I&O coding) vs the stored
  8.28% of I&O-eligible deaths; both reported, labels state the universes.

## 2026-11-05 — JNO revision figures (editor's color-coding instruction)

- **STOP, per the figure memo's parity rule: the authorized 2022-2024 clergy
  COVID-19 PMR came out 1.59 (95% CI, 1.46-1.73)** — observed 529, expected
  332.1, denom 12,111 — not near parity. The script halted BEFORE appending
  anything (numbers.csv unchanged; no REVISION_FIG row; no figure drawn).
  Reconciliation sketch for the author, from existing numbers only: a PMR is
  a composition measure; with the 2022-2024 COVID rate ratio at 1.06 and
  clergy non-COVID mortality low relative to the reference, each clergy
  death is more likely to be COVID even at near-parity risk. The same wedge
  exists mildly in 2020-2021 (rate ratio 1.85 vs PMR 1.94). Panel A and the
  Figure 2 assembly are HELD (revision/07_figure2.R refuses to run) pending
  the author's decision.
- Figure 1 built to the editor's instruction: zero in-panel text (enforced
  by test), Okabe-Ito palette in one shared vector (revision/fig_palette.R),
  five-entry key outside the plot, all highlighted points selected by codes
  resolved from the benchmark output at build time (resolver stops on
  ambiguous label matches; EMT and counselor patterns required exact
  anchors). The archival figure's hardcoded rank-2 display name is moot
  here: no names appear anywhere in the figure.
- **cairo is no longer loadable on this machine** (XQuartz absent); the
  submission exports' cairo_pdf device fails. Revision figures use the
  macOS quartz PDF device, verified to embed TrueType font subsets
  (FontFile2 present). Note for the later assembly memo: the letter's
  submission-export targets will hit the same cairo failure if rerun here.
- Figure 2 Panel B plan (held with the figure): point ratios from stored
  covid_share_by_race.csv; exact Poisson CIs derived deterministically from
  the STORED counts with the pipeline's interval formula (not a new
  estimate; identity with stored ratios asserted in-script).

- **Author decision (2026-11-05, same day): option (c) — the 2022-2024
  category is dropped from Figure 2 Panel A.** The computed PMR 1.59
  (1.46-1.73) stays unpublished: it is recorded here and in
  revision/05_fig2_stat.R (retained as the record of the stop), appears in
  no figure, and was never appended to numbers.csv. Panel A shows the three
  stored periods (2020; Jan-Apr 2021; May-Dec 2021); the REVISION_FIG
  authorization goes unused.

- **Figure 2 extended (author instruction, 2026-11-05 follow-up):** Panel C
  added — cause-restriction sensitivity from the three STORED estimates
  (all causes 1.94 rank 1; excluding external 1.95 rank 1 of 449; excluding
  external/tobacco/alcohol 1.75 rank 2), ranks in the caption only; pooled
  reference band (1.94, CI shading) on panels A and B, keyed in the caption;
  shared y-range across all three panels. The three-panel render is a real
  exhibit — the eFigure-demotion fallback was not needed. eFigure candidate
  produced for the supplement decision: the C2 misclassification-bound
  curve (efigure_misclass.pdf), labeled as a bound under assumed
  contamination. All plotted and caption values test-pinned to stored
  numbers; no estimate computed or appended.

- **Submitted eMethods 5 misdescribed the cause-restriction strata — found
  2026-11-05** by the Figure 2 Panel A guard during the revision-figure
  build. eMethods 5 states the benchmark strata (sex x 5-year age x
  race/ethnicity) and then says "Each cause restriction in eMethods 3 is
  applied to occupation and reference composition alike," but the submitted
  restriction values (1.95 excluding external; 1.75 excluding
  external/tobacco/alcohol; eTable 4) were computed under sex x age5 ONLY
  (R/letter_targets.R:343; benchmark ladder row 4). Author instruction
  ("option 2, extended"): both restriction benchmarks recomputed as full
  per-occupation benchmarks under the uniform strata, clergy rows appended
  tagged REVISION_STRATA (strict 1.86 [1.79-1.92] rank 1 of 449; excl
  ext/tobacco/alcohol 1.69 [1.63-1.76] rank 1 of 449); the submitted
  sex x age rows remain untouched as the record. Notable: under uniform
  strata clergy move from rank 2 to RANK 1 in the heavily restricted
  benchmark (the former rank-1, graders and sorters of agricultural
  products, loses its excess under race/ethnicity adjustment). Figure 2
  Panel A draws from the uniform tables; tracked-changes passages listed in
  the 2026-11-05 report (letter Results sentence; eMethods 5 sentence;
  eTable 4 and its headnote; results_text.md counterparts).

## 2026-11-06 — education-calibration check (R2.1; revision/10_edu_calibration.R)

- **Guard interpretation.** The memo's guard requires the published clergy
  (35.6/49.7) and physician (89.5/100.0) education-agreement values to
  reproduce exactly. Those published values (output/qc/education_agreement.csv)
  are computed on 2020-2024; the calibration panel the memo specifies is
  2020-2021 (the benchmark period). Read the guard as a machinery-replication
  check: rebuild the eMethods conventions (educ_flag == 1, 2003-revision item,
  graduate = codes 7-8; ACS SCHL >= 22, same ages/jurisdictions/year mapping)
  and verify on 2020-2024 before running the 2020-2021 variant. Guard PASSED
  exactly; the period shift moves the clergy certificate share 35.6 -> 33.7
  and the ACS share 49.7 -> 49.5.
- **Stop rule, recorded before the run:** stop if the clergy residual from
  the cross-occupation OLS calibration (cert_share ~ acs_share) falls below
  the 10th percentile of the 436 residuals. **Outcome: percentile 13.8 —
  the rule did NOT trip, but the verdict is within rounding distance of the
  threshold and is flagged as borderline per the standing ground rule.**
  Clergy sit -3.4 pp below the fitted line (certificate 33.7% vs ACS 49.5%;
  the line predicts 37.1%). The initially drafted caption said "on the line,
  not below it"; that was inaccurate and was corrected the same day to
  "modestly below the fitted calibration, within its central range and above
  the pre-specified stop threshold" before anything was delivered.
- **Panel coverage:** 436 of 450 benchmark occupations. All 14 omissions are
  census occupation codes with no counterpart in the ACS OCCP coding for
  2020-2021 (e.g., Legislators 0030, Judges 2110, Computer Operators 5800);
  every omitted code has certificate deaths, none lacks them. Clergy
  unaffected. Noted in the eFigure caption.
- **Age bands:** the clergy certificate-ACS gap is large in every band
  (25-34: 17.6 vs 32.8; 45-54: 24.2 vs 49.9; 65-74: 37.0 vs 56.9), and
  physicians show same-sign within-band gaps (70.7-89.7 vs ~100), so the
  shortfall is not a retiree/oldest-band artifact; it is the economy-wide
  compression of certificate education at high ACS shares that the fitted
  line absorbs.
- Appended 4 REVISION_EDU rows (numbers.csv 125 -> 129); all pre-existing
  rows untouched.

## 2026-11-06 (later) — STOP: empirical-logit recalibration memo (R2.1)

- Author memo: refit the education calibration on the empirical-logit scale
  (log((x+0.5)/(n−x+0.5)) for certificate counts vs the same transform of the
  ACS weighted counts, weighted by certificate deaths), logit fit PRIMARY on
  a priori grounds, linear as sensitivity, implied misclassification
  p = (predicted − observed)/(predicted − c) against the logit prediction,
  stop rule percentile < 10 under the primary fit.
- Executed as specified; guard (35.6/49.7, 89.5/100.0) passed again. Result:
  the primary fit predicts clergy at 16.3% vs observed 33.7%; clergy logit
  residual +0.961, **88.1st percentile of 436** (unweighted variant: 93.1st);
  linear sensitivity unchanged (−3.37 pp, 13.8th). **Implied p = −1.57,
  outside [0,1): the memo's formula presupposes predicted > observed, which
  fails.** STOPPED on that item per the standing rule; nothing appended,
  caption/eMethods/eFigure from the logit run reverted to the committed
  linear-only state (numbers.csv back to 129 rows, byte-identical).
- Diagnosis (from the run's persisted panel, preserved in the session
  report): the certificate/ACS odds ratio is NOT constant across occupations
  — the median logit-scale residual rises monotonically with ACS share
  (−0.05 in the <5% bin, which carries 64.2% of certificate deaths and
  anchors the fit; +0.25 at 5–10%; +0.54 at 10–20%; +0.79 at 20–40%; +0.99
  at 40–100%), and the fitted slopes are well below 1 (0.834 weighted, 0.694
  unweighted). A straight line on the logit scale therefore underpredicts
  every high-education occupation, and the clergy percentile under it
  measures ACS share, not clergy-specific deviation: clergy (+0.96) sit
  slightly BELOW the median of their own 40–100% bin (+0.99). The favorable
  88th percentile is a model artifact, not evidence clergy certificates
  over-report education; reporting it as primary would be drafting around
  the linear result, not an a priori improvement on it.
- The numeric stop rule (percentile < 10) did not trip — it was the
  implied-p assumption that failed. A hard guard (p outside [0,1) stops
  before any writes) is now in revision/10_edu_calibration.R so reruns
  reproduce the stop until the author resolves the primary-fit
  specification. Candidate resolutions reported to the author: (a) keep the
  linear fit primary and report the logit fit as a sensitivity with its
  misspecification noted; (b) specify a curvature-respecting fit
  (e.g., quadratic in the logit, or a within-share-band comparison); (c)
  define the implied p against the linear prediction (predicted 37.1% >
  observed, p well-defined).

## 2026-11-06 (third memo) — attenuation log ORs replace fitted calibrations

- Author memo: drop both fitted calibrations as primary; primary statistic is
  the per-occupation attenuation log odds ratio, log((x+0.5)/(n−x+0.5)) for
  certificate counts minus the same for ACS weighted counts; report the
  distribution, clergy's value/percentile, physicians' value, and the local
  band (ACS share 35–65%); eFigure scatter with identity diagonal only; stop
  rule: clergy below the 10th percentile of attenuation ORs overall or within
  the band.
- **Record of the abandoned parametric fit** (memo instruction): the
  death-weighted empirical-logit line had intercept −1.6177, slope 0.8340,
  weighted R² 0.772. Its five highest-leverage points: Physicians and
  Surgeons 3065 (leverage 0.293 — ACS share at the 100% boundary, where the
  continuity-corrected ACS logit degenerates to ~log(2W+1) = 15.6, residual
  −9.47); Elementary and Middle School Teachers 2310 (0.077, n = 48,240);
  Driver/Sales Workers and Truck Drivers 9130 (0.059, n = 103,394); Dentists
  3010 (0.055, boundary like physicians, residual −7.45); Laborers and
  Freight/Stock/Material Movers 9620 (0.054, n = 94,760). Two boundary
  occupations and three mass-death occupations steered the fit; combined with
  the rising certificate/ACS odds ratio this is why the line underpredicted
  the upper range. The logit-fit code is retired from
  revision/10_edu_calibration.R.
- **Results:** attenuation across 436 occupations: median −0.865, IQR
  [−1.283, −0.588]. Clergy −0.6529, 67.7th percentile (less attenuated than
  the typical occupation). Physicians −13.67, reported with the boundary
  caveat (not informative). Local band (ACS 35–65%): 27 occupations, median
  −0.653; clergy rank 14 of 27 from most attenuated, 48.1st band percentile —
  clergy sit essentially at their band's median attenuation. **Stop rule did
  NOT trip under either criterion (67.7 and 48.1, both ≥ 10), and neither is
  near the threshold.**
- Interpretation of "keep the earlier linear-fit rows": the two fit-derived
  rows (residual −3.3685 pp; percentile 13.76) were retagged SUPERSEDED_EDU
  with values frozen; the raw cert/ACS share rows are inputs, not fit
  outputs, and remain current REVISION_EDU rows (re-appended identically).
- 8 REVISION_EDU rows now current (numbers.csv 135); letter rows and all
  other revision rows verified byte-identical.

## 2026-11-06 — Table 1 rebuilt for the OI draft (author instruction: "build T1")

- The OI draft's placeholder asks for Table 1 "rebuilt by the pipeline at
  assembly with rates and CIs to 2 decimal places; rows and footnotes as
  submitted," plus the Non-Hispanic-other definition sentence. Stored rate
  rows are rounded to 1 dp at write time (R/harmonize.R), so the 2-dp table
  was recomputed through the same functions (harm_* panels, harm_asr,
  fay_feuer, rate_ratio) in revision/11_table1_oi.R, guarded: all 9 rows x
  (rate, CI) x 2 groups + 9 rate ratios with CIs — 54 values — reproduce
  their stored numbers.csv rows exactly at stored precision. numbers.csv not
  touched; outputs in output/revision/table1_OI.{docx,md} +
  table1_oi_values.csv (full precision record).
- Rows are exactly the submitted nine (letter table1.docx); the new footnote
  sentence is placed after the standardization/exclusion sentence it
  qualifies. Displayed counts remain the full category counts while rates
  standardize on the race-known subset, as in the submitted exhibit
  (decisions.md 2026-08-27, issue 1).
- FLAG for the author: the OI Results text cites the age-band rate ratios
  (45-54: 2.57; 55-64: 2.35; 65-74: 1.42) to "(Table 1)", but "rows as
  submitted" excludes age rows. The values exist as numbers.csv rows
  (rr_covid_age_*_harm). Either the citation should point elsewhere or three
  age rows should be added to Table 1 — author's call; not improvised here.

## 2026-11-06 — second-round analyses B1-B4, Table 1 fixes, figure addendum

- **B1 (REVISION_RANK):** pooled benchmark read as persisted. Six occupations'
  CI upper bounds exceed clergy's lower bound (1.8704), all with 21-35 COVID
  deaths (list in output/revision/rank_overlap_occupations.csv). Parametric
  bootstrap (Poisson draws on observed counts, expected fixed, seed 20261106,
  10,000 reps): pooled P(rank 1) = 0.78, P(top 3) = 0.999 (worst rank 5);
  2020-only (recomputed, guarded to the stored clergy row full-precision and
  3-dp) P(rank 1) = 0.08, P(top 2) = 0.27 (worst 11) — year-level ranks are
  noisy because year-specific counts are small; the pooled headline is the
  stable one. eMethods paragraph in emethods_rank.md.
- **B2 (REVISION_RACE4):** nh_other row read from the persisted
  covid_share_by_race.csv and computed exactly as the three Part C rows:
  1.72 (1.48-2.00), 178 observed vs 103.2 expected. ELEVATED - stop rule not
  tripped. Count note: the memo expected ~179 (2,922 minus the three reported
  groups); actual is 178 because one clergy COVID death has unknown
  race/ethnicity. Draft Results insertion in race4_sentence.md. The prior
  Figure 2 caption's claim that non-Hispanic other was "below the analysis's
  reporting threshold" was WRONG (178 >> 20; the group was simply not
  reported) - corrected in this build and noted here for the record.
- **B3 (REVISION_AGECAP):** ages 25-84 clergy COVID PMR 1.73 (1.68-1.78),
  4,694 obs vs 2,718.5 expected; the 25-74 consistency check reproduced the
  stored 1.9401 (1.8704-2.0117) at full precision before the 25-84 run was
  reported. Including 75-84 LOWERS the ratio (the known age attenuation),
  the opposite of what retiree over-reporting inflation would produce.
  emethods_agecap.md.
- **B4 (REVISION_IND):** ind_code4 is parsed in the interim parquet, so the
  optional check ran. Animal slaughtering and processing industry (census
  code 1180, same code in the 2012 and 2017 schemes): COVID PMR 1.23
  (1.16-1.30), 1,131 obs, 6,607 total deaths — the industry is elevated even
  though the butcher OCCUPATION (7810) is at the null (0.98), consistent
  with C1's point that processing-plant workers scatter across production
  occupations. Supplement line in industry_meat_line.md.
- **Table 1 (revision/11_table1_oi.R):** three age-band rows added after the
  COVID period rows (45-54: 2.57; 55-64: 2.35; 65-74: 1.42), rates recomputed
  at 2 dp through harm_asr with the RR guards extended to them (stored rate
  rows do not exist for the age bands, so the rate guard is conditional);
  displayed counts are the sex-only full-category n per the exhibit
  convention. Footnote standardization sentence corrected to "directly
  standardized by sex, age, and race and ethnicity to the 2000 US standard
  population" per the memo.
- **Figures:** axis labels harmonized to "Standardized proportional
  mortality ratio (95% CI)" + "log scale" and tick labels to 2 dp across
  Figure 1, 2A, 2B. Figure 1: rank 4-15 highlighted points drawn at size 1.4
  and spread to a minimum 5.5-rank horizontal gap (offsets 4->4, 5->9.5,
  6->15, 10->20.5, 12->26, 15->31.5; max drift ~16 of 450 ranks), disclosed
  in the caption; caption already carried ranks for all highlighted
  occupations including the adjacent set. Figure 1's caption write made
  idempotent (it previously truncated captions.md on rerun). Figure 2A: the
  memo's proposed sentence "95% CIs are narrower than the plotting symbols"
  was VERIFIED against the renders and is true for 2021 and both pooled
  strips but NOT for 2020 (its interval extends just beyond the diamond), so
  the caption carries the accurate variant instead. Figure 2B: asterisk
  replaced by the explicit three-line label; nh_other row added last with a
  guard tying it to the REVISION_RACE4 row.

## 2026-11-06 — B1 addendum: observed-count-restricted rank probabilities

- Author addendum: the bootstrap draws were not persisted (only the
  probabilities), so the script re-runs with the same seed (20261106) and
  now computes the restricted ranks from the SAME draw sequence as the
  unrestricted ones; a guard asserts the unrestricted probabilities
  reproduce the appended 0.7812 / 0.9989 exactly before anything is
  written. Restricted to the 301 occupations with >=100 observed COVID-19
  deaths: P(rank 1) = 0.9998, P(top 3) = 1.0000 (worst drawn rank 2) - all
  six CI-overlap occupations have 21-35 COVID deaths and drop out. Two
  REVISION_RANK rows appended (numbers.csv 146). eMethods gains the
  inferential-stance sentence (observed ranks as population facts; counts
  as rate realizations, Brillinger 1986) and the partial-pooling sentence
  (unrestricted probability is conservative).
- Note: the rerun moved the five original REVISION_RANK rows after the
  RACE4/AGECAP/IND blocks (the idempotent filter-and-re-append pattern
  re-appends a context block at the end). Verified: every pre-existing row
  is value-identical; only the position of that one block changed, as it
  would on any rerun of any revision append script.

## 2026-11-08 — OI Results-fix inputs: population totals + 25-44 band (REVISION_POP)

- Author request: the analytic-population totals and the 25-44 age-band rate
  ratio (or the reason it is absent from Table 1) were not in numbers.csv.
- Totals (revision/16_population_totals.R; the rebuilt 2020-2021 universe
  guard-matched the cached letter frame on rows, clergy deaths 11,123 and
  clergy COVID 2,922): 2020-2024, 5,664,185 employed decedents with a coded
  analysis occupation, 375,316 COVID-19 deaths (6.6%); 2020-2021, 2,400,041
  and 292,940 (12.2%).
- Why 25-44 was absent: the letter harmonized only 45-54/55-64/65-74
  (HARM_MAP); the younger bands existed only as sex-only letter values
  (25-34: 1.33 [0.81-2.19]; 35-44: 1.05 [0.76-1.43], results_text.md), with
  only 81 clergy COVID deaths at 25-44 in 2020-2024.
- Harmonized 25-44 rate ratio, computed with the same machinery (guard: the
  band path reproduces the stored 45-54 row 2.57 [2.25-2.94, n 359] before
  reporting): **1.36 (1.01-1.83), 81 clergy COVID deaths** - elevated with
  the lower bound just above 1; flagged as borderline per the standing
  ground rule (a verdict within rounding distance of a threshold is
  flagged). Band counts reconcile: 81 + 359 + 987 + 2,023 = 3,450
  race-known clergy COVID deaths.
- 5 REVISION_POP rows appended (numbers.csv 151); mirrored to
  response_numbers.csv.

## 2026-11-09 — PRE-REGISTERED (before R1 runs): retirement-timing stop rule

Pre-registered for R1: if clergy rank outside the top 5 in the 25-59
benchmark excluding external causes, the manuscript's ranking claim is
reframed by the authors ("among the highest, with the excess concentrated
at working ages") rather than defended. Results will be reported whichever
way they fall. (REVISION_RETIRE memo, Step 0; committed on its own so the
timestamp precedes the result.)

## 2026-11-09 — retirement-timing results (REVISION_RETIRE; revision/17_retire.R)

- Internal consistency guards passed at full precision (25-74 window
  reproduces the pooled 1.9401 rank 1/450 and excluding-external 1.8555
  rank 1/449 benchmarks) before any window ran.
- **R1: clergy rank 1 in all four runs; the pre-registered stop rule
  (commit 5c69069) did NOT trip.** 25-59 all causes 2.2173 (2.0582-2.3855),
  rank 1/357; 25-59 excl external 1.9240 (1.7860-2.0700), rank 1/352;
  25-64 all causes 2.1782 (2.0597-2.3016), rank 1/392; 25-64 excl external
  1.9766 (1.8691-2.0887), rank 1/391. Bootstraps (seed 20261106): 25-59(b)
  P(rank1) 0.2554, P(top3) 0.8208 (0.8752/1.0000 among the 168 occupations
  with >=100 observed COVID deaths in window); 25-64(b) 0.6000/0.9870
  (0.9410/1.0000 among 221). The lower point-estimate certainty at 25-59
  reflects small window counts (clergy 719 observed), not rank slippage:
  worst bootstrap ranks remain in the top tier and the >=100-obs
  probabilities are high.
- Judgment call: the memo's "report and append" for the top-10 lists and
  the R2 late-retiring table is implemented as persisted CSVs
  (retire_top10.csv, retire_late10.csv) plus scalar numbers.csv rows;
  26 REVISION_RETIRE rows appended (numbers.csv 177).
- R2: clergy 65-74 worker share 21.3%, 97.2nd percentile of the 436
  benchmark occupations with ACS 2021 rows (the same 14 ACS-coding
  omissions as the education calibration). The 10 oldest-workforce
  occupations' published PMRs run 0.85-1.35 (only bus drivers, rank 16,
  and tailors, rank 26, are elevated); Spearman(65-74 share, PMR) =
  -0.002. Late retirement does not track PMR.
- R3: same-period all-cause rate ratio (2020-2021, harmonized) 0.9111
  (0.8866-0.9362) - NOTE: higher than the published 2020-2024 all-cause
  0.77, i.e., the pandemic years pushed clergy all-cause mortality toward
  parity; worth a line in the response if asked. Denominator bound:
  k = 2.05 (published COVID RR), implied true all-cause RR 0.4444 - less
  than half other workers' rate, below any plausible healthy-worker margin.
- Wording corrections made before delivery: the eMethods bound clause
  ("barely two-fifths" -> "less than half", value 0.44) and the Spearman
  display (%.3f so the text matches the stored -0.002 rather than showing
  "-0.00").

## 2026-11-10 — Job 0 (revision audit memo): two targeted checks

- **0.1 CONFIRMED: the published within-group race/ethnicity ratios are
  crude.** They come from R/benchmark.R covid_share_by_race() ("p <-
  panel[...]; cl ... group_by(race) ... clergy_pct = 100*clergy_covid/
  clergy_deaths; ratio = clergy_pct/ref_pct" - no sex or age strata;
  reference = all employed decedents of the group, clergy included,
  2020-2021, unknown race excluded) and R/letter_targets.R Part C, which
  wraps the stored shares in exact Poisson CIs ("expd <- row$clergy_deaths
  * row$ref_covid / row$ref_deaths"). The author's arithmetic was right:
  the implied expected counts (~1,403) cannot reconcile with the pooled
  benchmark's 1,506.1 because the pooled benchmark stratifies by sex x age
  within race and the crude ratios do not; clergy's older age structure
  inflates every crude within-group ratio.
- Stratified components (revision/18_job0.R; guards: expected sums to
  1,506.1258 at full precision incl. the unknown-race stratum [4 clergy
  deaths, 1 COVID, expected 0.54]; observed sums to 2,922; components pool
  to exactly 1.9401): Hispanic 1.83 -> 1.6808 (1.5473-1.8226, exp 348.1);
  NH Black 1.80 -> 1.7275 (1.5945-1.8686, exp 360.6); NH White 2.42 ->
  2.2477 (2.1367-2.3631, exp 682.9); NH other 1.72 -> 1.5617
  (1.3407-1.8088, exp 114.0). Every CI still excludes 1; NH White remains
  the largest; abstract range becomes 1.56-2.25. Old rows untouched; new
  rows REVISION_AUDIT (_strat suffix).
- Artifacts: figure2_OI_racefix.{pdf,png} + captions_racefix.md +
  figure2_racefix_points.csv (current figure2 files untouched);
  race_ratio_replacements.md (replacement sentences + the response-letter
  correction paragraph); same-strata guard extended to Figure 2B in the
  racefix script and the test suite (decomposition identity enforced).
  NOTE: the three input documents were not yet in manuscript/revision/, so
  the replacements file quotes the memo's enumerated values rather than
  verbatim document sentences; to be completed when the files arrive.
- **0.2 obesity, one scale.** (1) Conditional mention ratio among deaths
  WITHOUT COVID-19 anywhere, 2020-2024, same machinery as the 1.22 row:
  1.3345 (1.2442-1.4297); 810 observed vs 607.0 expected; crude 4.2% vs
  3.8%. (2) Harmonized standardized rates for deaths with COVID-19 anywhere:
  clergy 92.33 (88.20-97.08) vs other 55.47 (55.30-55.65) per 100,000;
  RR 1.6644 (1.5906-1.7416), 3,725 clergy deaths - the quantity against
  which the 2.07 obesity+COVID rate ratio can be read. (3) Confirmed: the
  1.22 row conditions on cf_covid_anywhere (COVID-19 anywhere on the
  record), not underlying cause; the machinery guard reproduced the stored
  row exactly. Numbers only; no interpretation drafted, per the memo.
- Job A/B inputs (01_manuscript_OI_v8.docx, 02_response_letter_v6.docx,
  03_supplement_v3.docx) were NOT present in manuscript/revision/ at run
  time; stopped after Job 0 per the memo, awaiting the files.

## 2026-11-10 — Job A: number audit of the three revision documents

- Inputs arrived as newer versions than the memo listed (manuscript v9,
  letter v7, supplement v4); audited as received. The v9 documents already
  carry the Job 0 values (stratified race ratios, 1.33 mention ratio).
- **A1 regeneration PASSED**: letter_pmr_deaths/letter_harmonized/
  letter_numbers invalidated and rebuilt from the interim parquets, then all
  ten appending revision scripts rerun in order; the regenerated numbers.csv
  equals the committed file row-for-row EXCEPT the two SUPERSEDED_EDU rows,
  which are a frozen record of the abandoned linear fit that current code
  intentionally does not recreate (retag-only logic; documented 2026-11-06).
  Judgment call: the parquet parse step was not rerun from the raw zips -
  the parse is frozen and verified by tests/test-parse-matches-python.R
  against an independent parser; logged as the regeneration boundary.
- **Audit: 199 claims across the three documents; 91 MATCH, 104 DERIVED
  (each verified against a named pipeline output), 0 MISMATCH, 0 incorrect
  roundings; 3 placeholders ([month]; Table 1 insert; [XX] word counts) and
  1 expected NO SOURCE (the Arkansas 35-of-92 attack rate, a literature
  value from reference 15).** Files: number_audit.csv,
  number_audit_letter.csv, number_audit_supplement.csv,
  number_audit_exceptions.csv.
- A3 gap fills (25 new REVISION_AUDIT rows; revision/20_audit_gaps.R):
  2022-2024 PMR 1.5929 (1.4601-1.7347; 529/332.1; denom 12,111; rank 6 of
  359) CONFIRMS the printed 1.59 (1.46-1.73); restrictions 1.5297 (rank 9)
  and 1.3869 (rank 15); non-COVID RRs by period and year (2020-2021 0.7517;
  2022-2024 0.6949; per year 0.76/0.75/1.00*/0.72/0.69 - *2022 flagged: a
  43-person-weight ACS stratum carries 11 deaths, destabilizing that
  single-year point, caveat in the row note); all-cause 2022-2024 0.7043;
  COVID RRs 2020 2.0001 / 2021 2.1131 (confirming eMethods 4's 2.00/2.11);
  clergy workforce share in the 2020 nonreporting jurisdictions 7.71%
  (AZ, IA, NC, RI, DC); period floors Jan-Apr 2021 = 355, May-Dec = 417
  occupations (the Methods' "fewer occupations reach the floor" is
  directionally right but mild); eTable 2 strict expected 1,574.8 and
  CI-overlap count 7 (fills the table's "Not computed"); worst bootstrap
  ranks 5 (pooled) and 11 (2020), now rows; blank-occupation all-deaths
  shares 2021-2024 (1.45%, 1.01%, 1.05%, 1.04%); obesity 811 = 810
  race-known + 1 unknown-race death (CONFIRMED).
- **Reviewer count question (A3.3): the fall in clergy non-COVID deaths
  (~4,100/y in 2020-2021 to ~3,860/y in 2022-2024) is in the COUNTS; clergy
  person-years ROSE (457k in 2020 to ~497k from 2021 on) as coverage
  expanded.** The data cannot separate period mortality decline from cohort
  change; nothing supports a denominator artifact.
- **Blank-occupation basis flag (A2):** the printed "0.6% in 2021 and under
  0.1% from 2022" are the I&O-ELIGIBLE-deaths basis (QC: 0.589%,
  0.057-0.064%), but both documents attach them to "of all deaths" (the
  2020 sentence gives both bases); all-deaths values are 1.45% and ~1.0%.
  Values are right on their own basis; the antecedent needs fixing.
- Other A2 notes: eMethods 6 prints 78.1% where the manuscript/letter print
  78% (precision only); eMethods 5 prints 1,506.1 where the manuscript
  prints 1,506 (precision only); the letter's corrections section discloses
  the strata correction but not the Job 0.1 race-ratio recomputation, whose
  values its Comment 1.2 and the manuscript nevertheless print - the
  drafted correction paragraph is in race_ratio_replacements.md.
- A4 traces: layout spec has NO geographic fields (confirmed, config/layouts);
  supplemental not-employed codes 9010-9900 incl military (excluded from the
  analytic population); software list in Methods is INCOMPLETE - the
  pipeline also loads readr, targets, yaml, patchwork, gt, scales, readxl
  (lockfile R 4.5.1, arrow 21.0.0.1, dplyr 1.1.4, tidyr 1.3.1, ggplot2
  4.0.0, readr 2.1.5); every CI, standardization and bootstrap routine is
  base R (qgamma/rpois/lm; Fay-Feuer hand-coded in R/standardize.R).
- OPTIONAL item skipped as not cheap: standardized all-cause rate ratios
  for all 450 occupations (occupation-level standardized denominators are a
  new analysis family; the rate machinery exists only for clergy vs
  reference). Said so per the memo.
- A5: table1_OI rebuilt with the 25-44 row (1.36; 1.01-1.83; 81) and the
  alphabetical non-Hispanic-other footnote; **counts switched to the
  race-known deaths entering the rates** (23,220; 2,921; 810 ...) so Table 1
  and eMethods 13 agree on 810, per the memo's instruction - a convention
  change from the submitted exhibit's full-category counts, footnote
  reworded accordingly, flagged for the author since the Results text's
  23,234 is the (correct) population count. etables_supplement.docx built
  (eTables 1-3, guarded; no cell differs from the supplement; eTable 2's
  overlap cell now computable = 7). eFigure already a vector PDF (quartz).
- **STOP RULE: Job 0.1 changed the within-group ratios, so Job B is NOT
  started; stopped after the audit for the author's review, per the memo.**

## 2026-11-10 — v10/v8/v5 re-audit; author decisions; Job B begins

- Author: the stratified within-group ratios STAND; Job B authorized. The
  race-ratio fix gets NO correction paragraph in the response letter - it is
  recorded here and in the public repository's CHANGES.md only (author
  instruction, 2026-11-10).
- Re-audit of the changed passages (appended to the three audit files; now
  214 claims, 97 MATCH / 113 DERIVED / 0 MISMATCH): blank-occupation shares
  now on the I&O-eligible basis (8.3/0.6/<0.1 vs QC 8.279/0.589/0.057-0.064)
  with 9.1%-of-all-deaths retained parenthetically in eMethods 1 - the Job A
  basis flag is RESOLVED; 7.7% workforce share printed (row 7.71); 2022-2024
  restricted PMRs printed (1.53 = 1.5297 [1.4021-1.6658]; 1.39 = 1.3869
  [1.2712-1.5102]) and all-cause 0.70 (= 0.7043 [0.6838-0.7254]); eTable 2
  overlap cell filled (7); Table 1 inserted cell-for-cell identical to the
  guarded build, with a new footnote sentence on the drug-poisoning/suicide
  overlap that matches eMethods 3; the software sentence ("all estimation
  routines ... base R, without statistical extension packages") verified;
  the period-ranking floor rationale was dropped (the audit had found the
  floors mild: 355 and 417).

## 2026-11-11 — SUPERSEDES 2026-11-10 on the race-ratio disclosure

The response letter now reports the within-group recomputation as its
second self-identified correction (alongside the cause-restriction strata
correction), reversing the 2026-11-10 decision to record it in CHANGES.md
and this log only. Reason: the crude within-group values are in the
submission's numbers.csv (letter block) and reproduce at the public
repository's submission-v1 release, so the change from them is a
correction to published-as-submitted estimates, not only to response-letter
text. The Research Letter itself printed no within-group values; the crude
rows stand behind its statement that the elevation was present within every
racial and ethnic group. Letter v9 carries the paragraph (1.72 to 2.42
becomes 1.68, 1.73, 2.25, 1.56); supplement v6 adds the 2022-2024
restricted-benchmark CIs (1.53 [1.40-1.67]; 1.39 [1.27-1.51]) and the
2022-2024 all-cause rate ratio (0.70 [0.68-0.73]) to eMethods 5. The
public CHANGES.md correction 2 was reworded to the same effect (the crude
ratios were never "reported in a first-round response"; no response had
been sent).
