#!/usr/bin/env Rscript
# 03_coverage.R -- eMethods 1: coverage, blank-occupation shares, the analytic
# population, the within-2021 period floors, and the clergy workforce share in
# the 2020 nonreporting jurisdictions. Appends context-tagged rows to
# numbers.csv (tags mirror the archival pipeline: REVISION_C3, REVISION_POP,
# REVISION_AUDIT). Run after 02_analysis.R:  Rscript 03_coverage.R
source("revision_lib.R")

# ---- blank-occupation shares, both bases -------------------------------------
# All-deaths basis: blank occ_code4 among every record in the file (the 2020
# value, 9.1%, appears parenthetically in eMethods 1). I&O-eligible basis
# (age >= 15, US resident): the basis the documents report for every year
# (8.3%, 0.6%, under 0.1%); written to results/coverage_blank_occ.csv.
rows <- list(); cov <- list()
for (y in 2020:2024) {
  d <- arrow::read_parquet(sprintf("data/nvss_%d.parquet", y),
                           col_select = c("age_years", "resident_status", "occ_code4"))
  blank <- trimws(d$occ_code4) == ""
  eligible <- !is.na(d$age_years) & d$age_years >= 15 & d$resident_status != 4L
  cov[[length(cov) + 1L]] <- tibble::tibble(
    year = y, total_deaths = nrow(d),
    pct_blank_all = round(100 * mean(blank), 3),
    io_eligible = sum(eligible),
    pct_blank_eligible = round(100 * mean(blank[eligible]), 3))
  nm <- if (y == 2020) "revision_blank_occ_all_2020_pct"
        else sprintf("revision_audit_blank_occ_%d", y)
  ctx <- if (y == 2020) "REVISION_C3" else "REVISION_AUDIT"
  rows[[length(rows) + 1L]] <- R6(nm, round(100 * mean(blank), if (y == 2020) 2 else 3),
    n = nrow(d), context = ctx,
    note = sprintf("blank occupation field, %% of ALL %d deaths in the file (file deaths in n); the I&O-eligible basis is in results/coverage_blank_occ.csv", y))
}
cov <- bind_rows(cov)
readr::write_csv(cov, "results/coverage_blank_occ.csv")
log_msg("blank occupation, I&O-eligible basis: %s",
        paste(sprintf("%d %.3f%%", cov$year, cov$pct_blank_eligible), collapse = "; "))
# the eMethods 1 sentence: 8.3% (2020), 0.6% (2021), under 0.1% from 2022
stopifnot(round(cov$pct_blank_eligible[cov$year == 2020], 1) == 8.3,
          round(cov$pct_blank_eligible[cov$year == 2021], 1) == 0.6,
          all(cov$pct_blank_eligible[cov$year >= 2022] < 0.1))

# ---- analytic population (REVISION_POP) ---------------------------------------
d_all <- build_pmr_deaths(years = 2020:2024)
d2021 <- d_all[d_all$year <= 2021, ]
tot <- list(d24 = nrow(d_all), d21 = nrow(d2021),
            c24 = sum(d_all$covid_underlying), c21 = sum(d2021$covid_underlying))
log_msg("analytic population: %s (2020-2024) / %s (2020-2021); COVID %s / %s",
        format(tot$d24, big.mark = ","), format(tot$d21, big.mark = ","),
        format(tot$c24, big.mark = ","), format(tot$c21, big.mark = ","))
rows[[length(rows) + 1L]] <- R6("revision_pop_deaths_coded_occ_2020_2024", tot$d24, n = tot$d24,
  note = "employed decedents aged 25-74 with a coded analysis occupation, 2020-2024 (the analytic population; value = n)", context = "REVISION_POP")
rows[[length(rows) + 1L]] <- R6("revision_pop_deaths_coded_occ_2020_2021", tot$d21, n = tot$d21,
  note = "employed decedents aged 25-74 with a coded analysis occupation, 2020-2021 (value = n)", context = "REVISION_POP")
rows[[length(rows) + 1L]] <- R6("revision_pop_covid_deaths_2020_2024", tot$c24, n = tot$c24,
  note = "COVID-19 underlying-cause deaths in the analytic population, 2020-2024 (value = n)", context = "REVISION_POP")
rows[[length(rows) + 1L]] <- R6("revision_pop_covid_deaths_2020_2021", tot$c21, n = tot$c21,
  note = "COVID-19 underlying-cause deaths in the analytic population, 2020-2021 (value = n)", context = "REVISION_POP")

# ---- within-2021 period floors (REVISION_AUDIT) --------------------------------
d21m <- pmr_deaths_2021_by_month()
n_floor <- function(d) sum(table(d$occ) >= 100)
nf_e <- n_floor(d21m[d21m$month <= 4L, ]); nf_l <- n_floor(d21m[d21m$month >= 5L, ])
log_msg("occupations with >=100 deaths: Jan-Apr 2021 %d; May-Dec 2021 %d", nf_e, nf_l)
rows[[length(rows) + 1L]] <- R6("revision_audit_floor_jan_apr_2021", nf_e,
  note = "occupations with >=100 deaths at ages 25-74 in Jan-Apr 2021", context = "REVISION_AUDIT")
rows[[length(rows) + 1L]] <- R6("revision_audit_floor_may_dec_2021", nf_l,
  note = "occupations with >=100 deaths at ages 25-74 in May-Dec 2021", context = "REVISION_AUDIT")

# ---- clergy workforce share in the 2020 nonreporting jurisdictions -------------
np20 <- non_participating()[["2020"]]
share_np <- function(src_year) {
  a <- arrow::read_parquet(sprintf("data/acs_%d.parquet", src_year),
    col_select = c("state", "age", "occ_code4", "ESR", "employed_civilian", "PWGTP"))
  a <- a[a$age >= 25 & a$age <= 74, ]
  a$occ_analysis <- harmonise_occ(a$occ_code4, "2018")$analysis
  a <- a[denominator_rule(a, "occp"), ]
  cl <- a[!is.na(a$occ_analysis) & a$occ_analysis == CLERGY, ]
  c(np = sum(as.numeric(cl$PWGTP)[cl$state %in% np20]),
    tot = sum(as.numeric(cl$PWGTP)))
}
s19 <- share_np(2019); s21 <- share_np(2021)
sh <- (s19[["np"]] + s21[["np"]]) / (s19[["tot"]] + s21[["tot"]])
log_msg("clergy workforce share in the 2020 nonreporting jurisdictions (%s): %.2f%%",
        paste(np20, collapse = ","), 100 * sh)
rows[[length(rows) + 1L]] <- R6("revision_audit_clergy_share_np2020", round(100 * sh, 2),
  note = sprintf("share (%%) of the clergy workforce (ACS person weights, 2019+2021, ages 25-74, occp rule) living in the jurisdictions not reporting occupation in 2020 (states %s = AZ, IA, NC, RI, DC)", paste(np20, collapse = ",")),
  context = "REVISION_AUDIT")

append_numbers(bind_rows(rows))
