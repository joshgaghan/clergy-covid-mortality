#!/usr/bin/env Rscript
# 08_age_retirement.R -- eMethods 9 and eTable 2: age range and retirement
# timing. (1) The 25-84 extension (numerator-side only; strata extended to
# [80,85)), guarded by exact reproduction of the pooled clergy row from the
# same frame restricted to 25-74. (2) The age-window benchmarks (25-59,
# 25-64; all causes and excluding external causes), with the eMethods 6
# bootstrap on the two restricted runs (seed 20261106). (3) The
# late-retirement index: each occupation's share of workers aged 65-74 (ACS
# 2021), clergy's percentile, the ten oldest-workforce occupations, and the
# Spearman correlation with the published PMR. The stop rule for the window
# benchmarks (reframe if clergy rank outside the top 5 at 25-59 excluding
# external causes) was pre-registered in the archival pipeline's decisions
# log before the analyses ran; it did not trip. Appends REVISION_AGECAP,
# REVISION_RETIRE rows. Run after 02.
source("revision_lib.R")
SEED <- 20261106; N_REP <- 10000
rows <- list()
pub <- read_benchmark()
pooled_cl <- pub[pub$occ == CLERGY, ]

# ---- 25-84 extension (REVISION_AGECAP) -----------------------------------------
build_pmr_deaths_cap <- function(years = c(2020, 2021), cap = 84) {
  out <- list()
  for (y in years) {
    d <- arrow::read_parquet(sprintf("data/nvss_%d.parquet", y),
      col_select = c("resident_status", "age_years", "sex", "occ_code4",
                     "cause_cat", "cancer_site", "hispanic_origin",
                     "race_recode_40", "icd10_underlying"))
    d <- d[d$resident_status != 4L, ]
    d <- d[!is.na(d$age_years) & d$age_years >= 25 & d$age_years <= cap, ]
    h <- harmonise_occ(d$occ_code4, unname(year_scheme()[as.character(y)]))
    d$occ <- h$analysis; d$lab <- h$label
    d <- d[!is.na(d$occ), ]
    d <- d[!d$occ %in% not_employed_codes(), ]
    is_lung <- !is.na(d$cancer_site) & d$cancer_site == "lung"
    is_external <- substr(d$icd10_underlying, 1, 1) %in% c("V", "W", "X", "Y") |
                   substr(d$icd10_underlying, 1, 3) == "U03"
    out[[length(out) + 1L]] <- tibble::tibble(
      occ = d$occ, lab = d$lab, sex = d$sex,
      age5 = as.character(cut(d$age_years, breaks = seq(25, 5 * ceiling((cap + 1) / 5), 5),
                              right = FALSE)),
      raceeth = nvss_race_eth(d$hispanic_origin, d$race_recode_40),
      covid_underlying = d$cause_cat == "covid19",
      natural = !d$cause_cat %in% PMR_EXCLUDE_CAUSES & !is_lung,
      natural_strict = !is_external,
      age_years = d$age_years, year = y)
  }
  bind_rows(out)
}
d84 <- build_pmr_deaths_cap()
t74 <- pmr_by_occupation(d84[d84$age_years <= 74, ] |> select(-age_years))
c74 <- t74[t74$occ == CLERGY, ]
stopifnot(abs(c74$pmr - pooled_cl$pmr) < 1e-12, c74$observed == pooled_cl$observed)
t84 <- pmr_by_occupation(d84 |> select(-age_years))
c84 <- t84[t84$occ == CLERGY, ]
log_msg("25-84 PMR: %.4f (%.4f-%.4f); obs %d exp %.1f (25-74 guard reproduced %.4f)",
        c84$pmr, c84$lo, c84$hi, c84$observed, c84$expected, c74$pmr)
rows[[length(rows) + 1L]] <- R6("revision_agecap_pmr_clergy_25_84",
  round(c84$pmr, 4), round(c84$lo, 4), round(c84$hi, 4), c84$observed,
  "clergy COVID-19 PMR ages 25-84, 2020-2021; same strata/machinery, age strata extended to [80,85); 25-74 companion is the published 1.94",
  "REVISION_AGECAP")
rows[[length(rows) + 1L]] <- R6("revision_agecap_expected_25_84",
  round(c84$expected, 1), n = c84$observed,
  note = "expected clergy COVID-19 deaths ages 25-84 (observed in n)",
  context = "REVISION_AGECAP")

# ---- age-window benchmarks (REVISION_RETIRE) -----------------------------------
deaths <- rev_pmr_deaths()
A5 <- sort(unique(deaths$age5))
win_bands <- function(upper) A5[as.integer(sub("\\[(\\d+),.*", "\\1", A5)) < upper]
run_win <- function(upper, restriction)
  pmr_by_occupation(deaths[deaths$age5 %in% win_bands(upper), ],
                    strata = c("sex", "age5", "raceeth"),
                    cause_restriction = restriction, min_deaths = 100)
RUNS <- tibble::tribble(
  ~key,              ~upper, ~restriction,     ~wlab,   ~rlab,
  "2559_all",        60,     "all",            "25-59", "all causes",
  "2559_exexternal", 60,     "strict_natural", "25-59", "excluding external",
  "2564_all",        65,     "all",            "25-64", "all causes",
  "2564_exexternal", 65,     "strict_natural", "25-64", "excluding external")
etab <- list()
for (i in seq_len(nrow(RUNS))) {
  k <- RUNS$key[i]
  tab <- run_win(RUNS$upper[i], RUNS$restriction[i])
  cl <- tab[tab$occ == CLERGY, ]
  overlap <- sum(tab$occ != CLERGY & tab$hi > cl$lo)
  stopifnot(cl$rank == 1)   # the pre-registered stop rule did not trip
  log_msg("R1 %s (%s): %.4f (%.4f-%.4f) rank %d/%d; overlap %d", RUNS$wlab[i],
          RUNS$rlab[i], cl$pmr, cl$lo, cl$hi, cl$rank, cl$n_ranked[1], overlap)
  p1 <- p3 <- p1m <- p3m <- NA_real_; n100 <- NA_integer_
  if (RUNS$restriction[i] == "strict_natural") {
    min100 <- tab$observed >= 100
    set.seed(SEED)
    bk <- boot_ranks(tab, N_REP, subset = min100)
    p1 <- mean(bk$all == 1); p3 <- mean(bk$all <= 3)
    p1m <- mean(bk$sub == 1); p3m <- mean(bk$sub <= 3)
    n100 <- sum(min100)
    log_msg("  bootstrap: %.4f/%.4f; among %d >=100-obs: %.4f/%.4f",
            p1, p3, n100, p1m, p3m)
  }
  pref <- paste0("revision_retire_pmr_clergy_", k)
  rows[[length(rows) + 1L]] <- R6(pref, round(cl$pmr, 4), round(cl$lo, 4),
    round(cl$hi, 4), cl$observed,
    sprintf("clergy COVID-19 PMR, ages %s, 2020-2021, %s; expected %.1f; rank %d of %d (sex x 5-y age x race/ethnicity, floor 100 in window)",
            RUNS$wlab[i], RUNS$rlab[i], cl$expected, cl$rank, cl$n_ranked[1]),
    "REVISION_RETIRE")
  rows[[length(rows) + 1L]] <- R6(paste0(pref, "_rank"), cl$rank, n = cl$n_ranked[1],
    note = sprintf("clergy rank, ages %s, %s (occupations meeting the floor in n)",
                   RUNS$wlab[i], RUNS$rlab[i]), context = "REVISION_RETIRE")
  rows[[length(rows) + 1L]] <- R6(paste0("revision_retire_overlap_", k), overlap,
    n = cl$n_ranked[1],
    note = sprintf("occupations whose CI upper bound exceeds clergy's lower bound, ages %s, %s",
                   RUNS$wlab[i], RUNS$rlab[i]), context = "REVISION_RETIRE")
  if (!is.na(p1)) {
    for (nm_p in c("p_rank1", "p_rank3", "p_rank1_min100obs", "p_rank3_min100obs")) {
      val <- switch(nm_p, p_rank1 = p1, p_rank3 = p3,
                    p_rank1_min100obs = p1m, p_rank3_min100obs = p3m)
      nv <- if (grepl("min100", nm_p)) n100 else N_REP
      rows[[length(rows) + 1L]] <- R6(paste0("revision_retire_", nm_p, "_", k),
        round(val, 4), n = nv,
        note = sprintf("parametric bootstrap %s, ages %s excluding external (seed %d, 10000 reps%s)",
                       gsub("_", " ", nm_p), RUNS$wlab[i], SEED,
                       if (grepl("min100", nm_p)) "; count of >=100-obs occupations in n" else "; replicates in n"),
        context = "REVISION_RETIRE")
    }
  }
  etab[[k]] <- tibble::tibble(window = RUNS$wlab[i], restriction = RUNS$rlab[i],
    n_occupations = cl$n_ranked[1], clergy_pmr = round(cl$pmr, 4),
    lo = round(cl$lo, 4), hi = round(cl$hi, 4), observed = cl$observed,
    expected = round(cl$expected, 1), rank = cl$rank,
    ci_overlap_count = overlap, p_rank1 = if (is.na(p1)) NA else round(p1, 4))
}
readr::write_csv(bind_rows(etab), "results/etable_retire.csv")

# ---- late-retirement index (REVISION_RETIRE) -----------------------------------
np <- non_participating()[["2021"]]
a <- arrow::read_parquet("data/acs_2021.parquet",
  col_select = c("state", "age", "occ_code4", "ESR", "employed_civilian", "PWGTP"))
a <- a[a$age >= 25 & a$age <= 74, ]
if (length(np)) a <- a[!a$state %in% np, ]
a$occ_analysis <- harmonise_occ(a$occ_code4, "2018")$analysis
a <- a[denominator_rule(a, "occp"), ]
shares <- a |> group_by(occ = occ_analysis) |>
  summarise(w = sum(as.numeric(PWGTP)),
            w6574 = sum(as.numeric(PWGTP)[age >= 65]), .groups = "drop") |>
  mutate(share6574 = 100 * w6574 / w) |> filter(occ %in% pub$occ)
cl_sh <- shares$share6574[shares$occ == CLERGY]
pct_sh <- 100 * mean(shares$share6574 < cl_sh)
late10 <- shares |> filter(occ != CLERGY) |> arrange(desc(share6574)) |>
  head(10) |> left_join(pub, by = "occ") |>
  transmute(occ, lab, share6574 = round(share6574, 1), covid_deaths = observed,
            pmr = round(pmr, 4), lo = round(lo, 4), hi = round(hi, 4), rank)
readr::write_csv(late10, "results/retire_late10.csv")
sp <- cor(shares$share6574, pub$pmr[match(shares$occ, pub$occ)], method = "spearman")
log_msg("late retirement: clergy %.1f%% (pct %.1f of %d); Spearman %.3f",
        cl_sh, pct_sh, nrow(shares), sp)
rows[[length(rows) + 1L]] <- R6("revision_retire_clergy_share6574", round(cl_sh, 2),
  note = "share of employed clergy aged 65-74 among ages 25-74, ACS 2021 1-year, denominator conventions",
  context = "REVISION_RETIRE")
rows[[length(rows) + 1L]] <- R6("revision_retire_clergy_share6574_percentile",
  round(pct_sh, 1), n = nrow(shares),
  note = "percentile of clergy 65-74 worker share among benchmark occupations with ACS rows (count in n)",
  context = "REVISION_RETIRE")
rows[[length(rows) + 1L]] <- R6("revision_retire_spearman_share_pmr", round(sp, 3),
  n = nrow(shares),
  note = "Spearman correlation, 65-74 worker share vs published pooled PMR, descriptive",
  context = "REVISION_RETIRE")

append_numbers(bind_rows(rows))
