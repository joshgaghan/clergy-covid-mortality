#!/usr/bin/env Rscript
# 09_rates.R -- the revision's harmonized-rate statistics: eMethods 4 (year-
# specific COVID-19 rate ratios; the same-period all-cause rate ratio),
# eMethods 11 (the denominator bound), eMethods 13 (COVID-anywhere rates and
# both conditional obesity mention ratios), the 25-44 rate ratio of Table 1,
# the period and per-year non-COVID rate ratios, and the 2022-2024 all-cause
# rate ratio. Appends REVISION_POP, REVISION_RETIRE, and REVISION_AUDIT rows.
# Run after 02.
source("revision_lib.R")
rows <- list()
H <- rev_harm(); dp <- H$dp; pp <- H$pp; W <- H$W
rrh <- function(measure, years) {
  a <- harm_asr(dp, pp, W, "clergy", measure, years)
  b <- harm_asr(dp, pp, W, "other_employed", measure, years)
  r <- rate_ratio(a, b)
  list(rr = unname(r[["rr"]]), lo = unname(r[["lower"]]), hi = unname(r[["upper"]]),
       a = a, b = b)
}
py <- function(grp, years) sum(pp$pop[pp$grp == grp & pp$year %in% years])

# ---- eMethods 4: per-year COVID RRs; same-period all-cause (eMethods 11) ------
for (y in c(2020, 2021)) {
  r <- rrh("covid19", y)
  log_msg("COVID RR %d: %.4f (%.4f-%.4f)", y, r$rr, r$lo, r$hi)
  rows[[length(rows) + 1L]] <- R6(sprintf("revision_audit_rr_covid_%d", y),
    round(r$rr, 4), round(r$lo, 4), round(r$hi, 4), r$a$deaths,
    sprintf("clergy vs other employed COVID-19 rate ratio, %d only, harmonized standardization (clergy COVID deaths in n)", y),
    "REVISION_AUDIT")
}
r_ac21 <- rrh("all_cause", 2020:2021)
log_msg("all-cause 2020-2021: %.4f (%.4f-%.4f)", r_ac21$rr, r_ac21$lo, r_ac21$hi)
rows[[length(rows) + 1L]] <- R6("revision_retire_rr_allcause_2020_2021",
  round(r_ac21$rr, 4), round(r_ac21$lo, 4), round(r_ac21$hi, 4), r_ac21$a$deaths,
  "clergy vs other employed all-cause rate ratio, 2020-2021 only, harmonized standardization (clergy deaths in n)",
  "REVISION_RETIRE")
num_shipped <- readr::read_csv("numbers.csv", show_col_types = FALSE)
k <- num_shipped$value[num_shipped$name == "rr_covid_2020_2021_harm"]
stopifnot(length(k) == 1)
rows[[length(rows) + 1L]] <- R6("revision_retire_denominator_k", k,
  note = "factor by which the clergy denominator would need to be too small for the true 2020-2021 COVID-19 rate ratio to equal 1 (= published 2.05)",
  context = "REVISION_RETIRE")
rows[[length(rows) + 1L]] <- R6("revision_retire_implied_allcause_rr",
  round(unname(r_ac21$rr) / k, 4),
  note = "implied true 2020-2021 all-cause rate ratio under that denominator error (same-period all-cause RR / k)",
  context = "REVISION_RETIRE")
r_ac24 <- rrh("all_cause", 2022:2024)
rows[[length(rows) + 1L]] <- R6("revision_audit_rr_allcause_2022_2024",
  round(r_ac24$rr, 4), round(r_ac24$lo, 4), round(r_ac24$hi, 4), r_ac24$a$deaths,
  "clergy vs other employed all-cause rate ratio, 2022-2024, harmonized standardization (clergy deaths in n)",
  "REVISION_AUDIT")
log_msg("all-cause 2022-2024: %.4f (%.4f-%.4f)", r_ac24$rr, r_ac24$lo, r_ac24$hi)

# ---- non-COVID rate ratios by period and year ----------------------------------
for (w in list(list(k = "2020_2021", y = 2020:2021), list(k = "2022_2024", y = 2022:2024),
               list(k = "2020", y = 2020), list(k = "2021", y = 2021),
               list(k = "2022", y = 2022), list(k = "2023", y = 2023),
               list(k = "2024", y = 2024))) {
  r <- rrh("non_covid", w$y)
  caveat <- if (w$k == "2022") "; CAUTION: single-year ACS cells are sparse for clergy (a 43-person-weight stratum carries 11 deaths), which widens this CI and destabilizes the point estimate" else ""
  rows[[length(rows) + 1L]] <- R6(paste0("revision_audit_rr_noncovid_", w$k),
    round(r$rr, 4), round(r$lo, 4), round(r$hi, 4), r$a$deaths,
    sprintf("clergy vs other employed non-COVID-19 rate ratio, %s, harmonized standardization; clergy non-COVID deaths in n, clergy person-years %.0f, other deaths %d%s",
            gsub("_", "-", w$k), py("clergy", w$y), r$b$deaths, caveat),
    "REVISION_AUDIT")
  log_msg("non-COVID %s: RR %.4f (%.4f-%.4f); clergy deaths %s, py %s", w$k,
          r$rr, r$lo, r$hi, format(r$a$deaths, big.mark = ","),
          format(round(py("clergy", w$y)), big.mark = ","))
}

# ---- the 25-44 rate ratio (Table 1; REVISION_POP) -------------------------------
a25 <- harm_asr_bands(dp, pp, W, "clergy", c("25-34", "35-44"))
b25 <- harm_asr_bands(dp, pp, W, "other_employed", c("25-34", "35-44"))
r25 <- rate_ratio(a25, b25)
log_msg("COVID RR ages 25-44, 2020-2024: %.4f (%.4f-%.4f); clergy deaths %d",
        r25[["rr"]], r25[["lower"]], r25[["upper"]], a25$deaths)
rows[[length(rows) + 1L]] <- R6("revision_pop_rr_covid_age_25_44",
  round(unname(r25[["rr"]]), 2), round(unname(r25[["lower"]]), 2),
  round(unname(r25[["upper"]]), 2), a25$deaths,
  "harmonized COVID-19 rate ratio, ages 25-44, 2020-2024 (clergy COVID deaths in n); absent from the letter's age rows because only 45-54/55-64/65-74 were harmonized there",
  "REVISION_POP")

# ---- eMethods 13: COVID-anywhere rates; both obesity mention ratios ------------
a <- harm_asr(dp, pp, W, "clergy", "covid_anywhere")
b <- harm_asr(dp, pp, W, "other_employed", "covid_anywhere")
rr <- rate_ratio(a, b); cia <- fay_feuer(a); cib <- fay_feuer(b)
log_msg("COVID-anywhere: clergy %.2f vs other %.2f per 100k; RR %.4f (%.4f-%.4f)",
        a$rate, b$rate, rr[["rr"]], rr[["lower"]], rr[["upper"]])
rows[[length(rows) + 1L]] <- R6("revision_audit_rr_covid_anywhere_harm",
  round(unname(rr[["rr"]]), 4), round(unname(rr[["lower"]]), 4),
  round(unname(rr[["upper"]]), 4), a$deaths,
  "clergy vs other employed rate ratio, deaths with COVID-19 anywhere on the record, 2020-2024, harmonized standardization (clergy deaths in n)",
  "REVISION_AUDIT")
rows[[length(rows) + 1L]] <- R6("revision_audit_rate_clergy_covid_anywhere_harm",
  round(a$rate, 2), round(unname(cia[["lower"]]), 2), round(unname(cia[["upper"]]), 2),
  a$deaths, "clergy rate per 100,000, deaths with COVID-19 anywhere, harmonized",
  "REVISION_AUDIT")
rows[[length(rows) + 1L]] <- R6("revision_audit_rate_other_covid_anywhere_harm",
  round(b$rate, 2), round(unname(cib[["lower"]]), 2), round(unname(cib[["upper"]]), 2),
  note = "other employed rate per 100,000, deaths with COVID-19 anywhere, harmonized",
  context = "REVISION_AUDIT")

# conditional obesity mention ratios: the shipped 1.22 (COVID-anywhere certs)
# is a letter row; its like-for-like companion among non-COVID certs is
# computed with the same machinery (cf_covid_anywhere negated)
cond_mentions <- function(keep_covid) {
  parts <- list()
  for (y in YEARS) {
    d <- arrow::read_parquet(sprintf("data/nvss_%d.parquet", y),
      col_select = c("resident_status", "age_years", "sex", "occ_code4",
                     "hispanic_origin", "race_recode_40",
                     "cf_covid_anywhere", "cf_obesity_anywhere"))
    d <- d[d$resident_status != 4L & !is.na(d$age_years) &
             d$age_years >= 25 & d$age_years <= 74 &
             d$cf_covid_anywhere == keep_covid, ]
    d$occ_analysis <- harmonise_occ(
      d$occ_code4, unname(year_scheme()[as.character(y)]))$analysis
    d$grp <- assign_group(d$occ_analysis)
    d <- d[d$grp %in% c("clergy", "other_employed"), ]
    d$age5 <- as.character(cut(d$age_years, breaks = seq(25, 75, 5), right = FALSE))
    d$raceeth <- nvss_race_eth(d$hispanic_origin, d$race_recode_40)
    d <- d[d$raceeth != "unknown", ]
    parts[[length(parts) + 1L]] <- d |>
      group_by(grp, sex, age5, raceeth) |>
      summarise(deaths = n(), obesity = sum(cf_obesity_anywhere), .groups = "drop")
  }
  agg <- bind_rows(parts) |> group_by(grp, sex, age5, raceeth) |>
    summarise(deaths = sum(deaths), obesity = sum(obesity), .groups = "drop")
  ref <- agg[agg$grp == "other_employed", ]
  cl <- agg[agg$grp == "clergy", ] |>
    left_join(ref |> mutate(p = obesity / deaths) |>
                select(sex, age5, raceeth, p), by = c("sex", "age5", "raceeth"))
  stopifnot(!any(is.na(cl$p)))
  obs <- sum(cl$obesity); expd <- sum(cl$deaths * cl$p)
  list(obs = obs, expected = expd, ratio = obs / expd,
       lo = stats::qgamma(0.025, obs) / expd,
       hi = stats::qgamma(0.975, obs + 1) / expd,
       n_unknownrace_total = NA)
}
chk22 <- cond_mentions(TRUE)
s22 <- num_shipped[num_shipped$name == "obesity_share_covid_certs_ratio", ]
stopifnot(round(chk22$ratio, 2) == s22$value, chk22$obs == s22$n)
nc <- cond_mentions(FALSE)
log_msg("obesity mention ratio, non-COVID certs: %.4f (%.4f-%.4f); obs %d exp %.1f",
        nc$ratio, nc$lo, nc$hi, nc$obs, nc$expected)
rows[[length(rows) + 1L]] <- R6("revision_audit_obesity_noncovid_mention_ratio",
  round(nc$ratio, 4), round(nc$lo, 4), round(nc$hi, 4), nc$obs,
  sprintf("obesity mentions per death WITHOUT COVID-19 anywhere on the record, clergy vs other employed, standardized over sex x 5-y age x race/ethnicity, 2020-2024; expected %.1f (like-for-like companion to the 1.22 row)", nc$expected),
  "REVISION_AUDIT")

# 810 vs 811: the single unknown-race clergy obesity/non-COVID death
parts <- list()
for (y in YEARS) {
  d <- arrow::read_parquet(sprintf("data/nvss_%d.parquet", y),
    col_select = c("resident_status", "age_years", "occ_code4",
                   "hispanic_origin", "race_recode_40",
                   "cf_covid_anywhere", "cf_obesity_anywhere"))
  d <- d[d$resident_status != 4L & !is.na(d$age_years) &
           d$age_years >= 25 & d$age_years <= 74 &
           d$cf_obesity_anywhere & !d$cf_covid_anywhere, ]
  d$occ_analysis <- harmonise_occ(
    d$occ_code4, unname(year_scheme()[as.character(y)]))$analysis
  d <- d[!is.na(d$occ_analysis) & d$occ_analysis == CLERGY, ]
  parts[[length(parts) + 1L]] <- tibble::tibble(
    raceeth = nvss_race_eth(d$hispanic_origin, d$race_recode_40))
}
ob <- bind_rows(parts)
stopifnot(nrow(ob) == 811, sum(ob$raceeth == "unknown") == 1)
rows[[length(rows) + 1L]] <- R6("revision_audit_obesity_noncovid_unknownrace",
  sum(ob$raceeth == "unknown"), n = nrow(ob),
  note = "clergy deaths with obesity recorded and no COVID-19 anywhere: total in n; value = those with unknown race/ethnicity (explains Table 1's race-known 810 vs the 811 total)",
  context = "REVISION_AUDIT")

append_numbers(bind_rows(rows))
