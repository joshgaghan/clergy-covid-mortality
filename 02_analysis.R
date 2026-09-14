#!/usr/bin/env Rscript
# 02_analysis.R -- every statistic in the research letter "COVID-19 Mortality
# Among US Clergy, 2020-2024" (submitted to JAMA Internal Medicine),
# recomputed from the parquet written by 01_data.R and verified, statistic by
# statistic, against the shipped numbers.csv (108 statistics). Any mismatch
# exits with a nonzero status.
#
# Companion repository to the full analysis pipeline (tag jamaim-v3); all
# analysis code is EXTRACTED from that repository, never reimplemented, and
# every function below carries an origin comment naming its source file.
#
# Run:  Rscript 01_data.R  then  Rscript 02_analysis.R   (from this directory)
#
# Package versions when the acceptance run was recorded (see README.md):
#   R 4.5.1; readr 2.1.5; dplyr 1.1.4; tidyr 1.3.1; arrow 21.0.0.1; ggplot2 4.0.0
#
# # DECISIONS (dated)
# 2026-09-14  This build supersedes the 2026-08-28 companion (tag jamaim-v2
#             era, 98 statistics): the letter gained year-specific PMRs, the
#             within-2021 split, the conditional obesity mention ratio, and
#             the workforce CI, and numbers.csv now carries 108 statistics.
# 2026-09-14  Month of death is parsed in the main 01_data.R pass (positions
#             65-66, verified in every year's layout PDF by the full repo),
#             so the within-2021 split reads month straight from the parquet.
#             The full repo instead re-reads month from the raw file and
#             aligns by record order (its interim parquet predates the
#             split); the same two guards are kept here - the split frame
#             must reproduce build_pmr_deaths(2021)'s row count and COVID-19
#             total, and the two periods must partition the 2021 clergy
#             COVID-19 deaths exactly.
# 2026-09-14  tibble::tibble() calls inside extracted functions are kept
#             verbatim; tibble is a hard dependency of dplyr and readr, so no
#             package beyond the allowed list is installed.
# 2026-09-14  std_pop_2000.csv and std_pop_2000_sex.csv ship alongside the
#             listed std_pop_2000_5yr.csv: the sixteen sex-only rate-ratio
#             rows use the verbatim standardise(), which standardizes over
#             the 10-year 2000 standard population with Census 2000 sex
#             weights.
# 2026-09-14  Config-plumbing functions (year_scheme, not_employed_codes,
#             non_participating) carry hardcoded constants or read the
#             shipped crosswalk instead of the full repo's YAML; values
#             copied verbatim and noted at each definition. The only new
#             function in this file is near().

suppressPackageStartupMessages({
  library(readr); library(dplyr); library(tidyr); library(arrow); library(ggplot2)
})

## ---- plumbing shims -------------------------------------------------------
# PATHS, adapted from R/util.R: this repository keeps config CSVs at top
# level, parquet under data/, and everything it produces under results/.
PATHS <- list(
  config  = function(...) file.path(...),
  layouts = function(...) file.path("layouts", ...),
  interim = function(...) file.path("data", ...),
  output  = function(...) { p <- c(...); file.path("results", p[p != "letter"]) }
)
dir.create("results", showWarnings = FALSE)

# from R/util.R: analysis years (NVSS) and ACS source years (2020 1-year PUMS
# is an experimental release; 2019 exists only to average with 2021).
YEARS     <- 2020:2024
ACS_YEARS <- c(2019, 2021, 2022, 2023, 2024)

# The one NEW function in this file: NA-safe "equal at the stored rounding".
near <- function(a, b) {
  (is.na(a) & is.na(b)) | (!is.na(a) & !is.na(b) & abs(a - b) < 1e-8)
}

## ---- from R/util.R (verbatim): logging, filter log, suppression ----------
log_msg <- function(...) {
  cat(sprintf(...), "\n", sep = "")
  utils::flush.console()
}

banner <- function(...) {
  log_msg("%s", strrep("=", 72))
  log_msg(...)
  log_msg("%s", strrep("=", 72))
}

stop_hard <- function(...) {
  stop(sprintf(...), call. = FALSE)
}

# --- filter logging --------------------------------------------------------
# CLAUDE.md: "Log counts at every filter. Every drop prints before/after and the
# reason." A filter_log accumulates the rows so they can be written out as QC.

new_filter_log <- function(scope, start_n) {
  log_msg("[%s] start: %s rows", scope, format(start_n, big.mark = ","))
  structure(
    new.env(parent = emptyenv()) |>
      (\(e) { e$scope <- scope; e$n <- start_n; e$rows <- list(); e })(),
    class = "filter_log"
  )
}

fl_step <- function(fl, reason, after_n) {
  dropped <- fl$n - after_n
  pct <- if (fl$n > 0) 100 * dropped / fl$n else 0
  fl$rows[[length(fl$rows) + 1L]] <- tibble::tibble(
    scope = fl$scope, reason = reason, before = fl$n, after = after_n,
    dropped = dropped, pct_dropped = round(pct, 3)
  )
  log_msg("[%s] %s: %s -> %s (dropped %s, %.2f%%)", fl$scope, reason,
          format(fl$n, big.mark = ","), format(after_n, big.mark = ","),
          format(dropped, big.mark = ","), pct)
  fl$n <- after_n
  invisible(after_n)
}

fl_table <- function(fl) {
  if (!length(fl$rows)) return(tibble::tibble())
  dplyr::bind_rows(fl$rows)
}

# NCHS convention required by CLAUDE.md: suppress counts under 20 and mark them.
SUPPRESS_UNDER <- 20L

suppress_small <- function(x, mark = "<20") {
  ifelse(!is.na(x) & x < SUPPRESS_UNDER & x > 0, mark,
         ifelse(is.na(x), NA_character_, format(x, big.mark = ",", trim = TRUE)))
}

is_suppressed <- function(x) !is.na(x) & x < SUPPRESS_UNDER

## ---- from R/standardize.R (VERBATIM; the letter's standardization code) ---
# Direct age standardisation, Fay-Feuer intervals, and rate ratios.
PER <- 1e5

std_pop <- local({
  cache <- NULL
  function() {
    if (is.null(cache)) {
      x <- readr::read_csv(PATHS$config("std_pop_2000.csv"), comment = "#",
                           show_col_types = FALSE)
      cache <<- setNames(as.numeric(x$std_pop), x$age_group)
    }
    cache
  }
})

sex_weights <- local({
  cache <- NULL
  function() {
    if (is.null(cache)) {
      x <- readr::read_csv(PATHS$config("std_pop_2000_sex.csv"), comment = "#",
                           show_col_types = FALSE)
      cache <<- setNames(as.numeric(x$weight), x$sex)
    }
    cache
  }
})

new_asr <- function(rate, var, wmax, deaths, pop) {
  list(rate = rate, var = var, wmax = wmax, deaths = deaths, pop = pop)
}

# `cells` is a data frame with age_band, deaths, pop and optionally sex.
# When `by_sex` is TRUE the sex weights are applied inside each age group.
standardise <- function(cells, bands = BAND_LABELS, by_sex = FALSE) {
  sp <- std_pop()
  cells <- cells[!is.na(cells$pop) & cells$pop > 0 &
                   as.character(cells$age_band) %in% bands, , drop = FALSE]
  if (!nrow(cells)) return(new_asr(NA_real_, NA_real_, NA_real_, 0L, 0))

  cells$age_band <- as.character(cells$age_band)
  if (by_sex) {
    sw <- sex_weights()
    cells$sw <- unname(sw[cells$sex])
    cells <- cells[!is.na(cells$sw), , drop = FALSE]
    # Renormalise the sex weights within each age group over the sexes present.
    denom <- tapply(cells$sw, cells$age_band, sum)
    cells$sw <- cells$sw / unname(denom[cells$age_band])
  } else {
    cells$sw <- 1
  }
  # Age weights renormalise over the bands that actually have population.
  present <- unique(cells$age_band)
  W <- sum(sp[present])
  cells$aw <- unname(sp[cells$age_band]) / W

  w <- cells$aw * cells$sw
  r <- cells$deaths / cells$pop
  new_asr(
    rate   = sum(w * r) * PER,
    var    = sum(w^2 * cells$deaths / cells$pop^2) * PER^2,
    wmax   = max(w / cells$pop) * PER,
    deaths = as.integer(sum(cells$deaths)),
    pop    = sum(cells$pop)
  )
}

# Fay MP, Feuer EJ. Confidence intervals for directly standardized rates: a
# method based on the gamma distribution. Stat Med. 1997;16(7):791-801.
fay_feuer <- function(a, alpha = 0.05) {
  y <- a$rate; v <- a$var; wm <- a$wmax
  if (!is.finite(y) || !is.finite(v)) return(c(lower = NA_real_, upper = NA_real_))
  lower <- if (y <= 0 || v <= 0) 0 else stats::qgamma(alpha / 2, shape = y^2 / v, scale = v / y)
  num <- v + wm^2
  upper <- stats::qgamma(1 - alpha / 2, shape = (y + wm)^2 / num, scale = num / (y + wm))
  c(lower = lower, upper = upper)
}

# Ratio a/b with a log-transformed interval; Var(log RR) by the delta method,
# treating the two groups as independent.
rate_ratio <- function(a, b, alpha = 0.05) {
  if (!is.finite(a$rate) || !is.finite(b$rate) || a$rate <= 0 || b$rate <= 0) {
    return(c(rr = NA_real_, lower = NA_real_, upper = NA_real_))
  }
  rr <- a$rate / b$rate
  v <- a$var / a$rate^2 + b$var / b$rate^2
  if (!is.finite(v) || v <= 0) return(c(rr = rr, lower = NA_real_, upper = NA_real_))
  half <- stats::qnorm(1 - alpha / 2) * sqrt(v)
  c(rr = rr, lower = rr * exp(-half), upper = rr * exp(half))
}

## ---- from R/groups.R (verbatim except where noted): occupation groups -----
BANDS <- list(c(25, 34), c(35, 44), c(45, 54), c(55, 64), c(65, 74))
BAND_LABELS <- vapply(BANDS, function(b) sprintf("%d-%d", b[1], b[2]), "")

band_of <- function(age) {
  out <- rep(NA_character_, length(age))
  for (i in seq_along(BANDS)) {
    b <- BANDS[[i]]
    out[!is.na(age) & age >= b[1] & age <= b[2]] <- BAND_LABELS[i]
  }
  factor(out, levels = BAND_LABELS)
}

crosswalk_tbl <- local({
  cache <- NULL
  function() {
    if (is.null(cache)) {
      cache <<- readr::read_csv(PATHS$config("occ_crosswalk.csv"),
                                col_types = readr::cols(.default = readr::col_character()))
    }
    cache
  }
})

# year_scheme, from R/groups.R: there the scheme is read from
# config/layouts/*.yaml (occupation_code_scheme, verified against each year's
# layout PDF); carried here as a constant. NVSS coded usual occupation with
# Census 2012 codes for data years 2020-2022 and Census 2018 codes for
# 2023-2024 (also recorded in the header of each layouts/nvss_*.csv).
year_scheme <- function() c(`2020` = "2012", `2021` = "2012", `2022` = "2012",
                            `2023` = "2018", `2024` = "2018")

# Map a scheme's source codes onto the harmonised analysis codes.
harmonise_occ <- function(occ_code4, scheme) {
  x <- crosswalk_tbl()
  x <- x[x$scheme == scheme, ]
  idx <- match(occ_code4, x$source_code)
  list(analysis = x$analysis_code[idx], label = x$analysis_label[idx])
}

CLERGY       <- "2040"
CLERGY_BROAD <- c("2040", "2050", "2060")
MILITARY_CODES <- c("9830", "9840", "9850")

# not_employed_codes, from R/groups.R: there the codes come from
# occ_groups.yaml supplemental_codes; here they are recovered from the shipped
# crosswalk's mapping_kind column (identical set: 9010 9020 9060 9070 9100
# 9830 9840 9850 9900).
not_employed_codes <- function() {
  x <- crosswalk_tbl()
  sort(unique(x$source_code[x$mapping_kind %in%
    c("supplemental_not_in_labor_force", "supplemental_unknown",
      "supplemental_military")]))
}

# CLAUDE.md Step 4: "Community and social services: Census codes 2000-2015 in the
# 2018 scheme (verify against crosswalk), excluding clergy-broad." Verified: the
# 2018 scheme has no 2000 or 2010 (both were split), so the range resolves to
# 2001-2006 and 2011-2015. This is NARROWER than the Phase 1 group, which also
# included 2016 and 2025; see decisions.md 2026-08-25.
community_social_services <- function() {
  x <- crosswalk_tbl()
  c18 <- x$source_code[x$scheme == "2018"]
  in_range <- c18[as.integer(c18) >= 2000 & as.integer(c18) <= 2015]
  a <- unique(x$analysis_code[x$scheme == "2018" & x$source_code %in% in_range])
  sort(setdiff(a, CLERGY_BROAD))
}


# --- comparison-group assignment for deaths and for denominators -----------

assign_group <- function(analysis_code) {
  css <- community_social_services()
  nec <- not_employed_codes()
  out <- rep("uncoded", length(analysis_code))
  has <- !is.na(analysis_code)
  out[has] <- "other_employed"
  out[has & analysis_code %in% nec] <- "not_employed"
  out[has & analysis_code %in% css] <- "community_social_services"
  out[has & analysis_code %in% CLERGY_BROAD] <- "clergy_other_religious"
  out[has & analysis_code %in% CLERGY] <- "clergy"
  out
}

# --- denominator rules -----------------------------------------------------
#
# PRIMARY (Phase 2): anyone with a nonblank OCCP -- i.e. who worked in the past
# five years -- who is civilian (ESR not 4 or 5, and not a military occupation
# code), ages 25-74.
#
# WHY THE CHANGE. Phase 1 used ESR in {1,2}, currently employed. The numerator is
# the decedent's USUAL occupation, which an informant reports for people who have
# stopped working; the ESR 1-2 denominator counts only people still working. For
# occupations with early retirement the denominator therefore loses people the
# numerator keeps, and the age-band rate ratios come out implausibly high at
# 55-74. "Worked in the past five years" is the closer match to "usual
# occupation" and is applied identically to every comparison group.
#
# ESR in {1,2} is retained as a pre-specified sensitivity analysis.

denominator_rule <- function(df, rule = c("occp", "esr12")) {
  rule <- match.arg(rule)
  civilian <- !(df$ESR %in% c(4L, 5L))
  military <- !is.na(df$occ_analysis) & df$occ_analysis %in% MILITARY_CODES
  if (rule == "occp") {
    !is.na(df$occ_code4) & civilian & !military
  } else {
    # employed_civilian is NA where ESR is missing; treat that as not included
    # rather than letting NA propagate into the row filter.
    !is.na(df$employed_civilian) & df$employed_civilian & !military
  }
}

# --- race / ethnicity (kept for parity with Phase 1; not used in the letter) --

nvss_race_eth <- function(hispanic_origin, race_recode_40) {
  is_h <- !is.na(hispanic_origin) & hispanic_origin >= 200 & hispanic_origin <= 299
  known <- !is.na(hispanic_origin) & hispanic_origin >= 100 & hispanic_origin <= 299
  out <- rep("unknown", length(hispanic_origin))
  out[known & !is.na(race_recode_40) & race_recode_40 == 1L] <- "nh_white"
  out[known & !is.na(race_recode_40) & race_recode_40 == 2L] <- "nh_black"
  out[known & !(out %in% c("nh_white", "nh_black"))] <- "nh_other"
  out[is_h] <- "hispanic"
  out
}

acs_race_eth <- function(HISP, RAC1P) {
  out <- rep("nh_other", length(HISP))
  out[!is.na(RAC1P) & RAC1P == 1L] <- "nh_white"
  out[!is.na(RAC1P) & RAC1P == 2L] <- "nh_black"
  out[!is.na(HISP) & HISP != 1L] <- "hispanic"
  out
}

## ---- from R/letter.R (verbatim except non_participating): rate machinery --
# 2020 has no usable 1-year PUMS; its denominator is the mean of 2019 and 2021.
ACS_FOR <- list(`2020` = c(2019, 2021), `2021` = 2021, `2022` = 2022,
                `2023` = 2023, `2024` = 2024)

# non_participating, from R/letter.R: there the jurisdiction lists are read
# from config/io_participation.yaml; carried here as constants (2-digit state
# FIPS, matching the ACS ST/STATE variable). Source: NCHS I&O documentation
# for 2020 and the record-layout PDFs for later years.
non_participating <- function() list(
  `2020` = c("04", "19", "37", "44", "11"),   # AZ, IA, NC, RI, DC
  `2021` = c("44", "11"),                     # RI, DC
  `2022` = character(0), `2023` = character(0), `2024` = character(0))


# ---- measures -------------------------------------------------------------
# Each is a predicate over the deaths table. The cardiometabolic composite is
# CLAUDE.md categories 1, 2, 3 and 5 as UNDERLYING cause, so it is a partition of
# those four exclusive categories and cannot double-count a death.
CARDIOMETABOLIC <- c("ihd", "other_cvd", "stroke", "diabetes")

measure_defs <- function() {
  list(
    all_cause        = function(d) rep(TRUE, nrow(d)),
    cardiometabolic  = function(d) d$cause_cat %in% CARDIOMETABOLIC,
    ihd              = function(d) d$cause_cat == "ihd",
    other_cvd        = function(d) d$cause_cat == "other_cvd",
    stroke           = function(d) d$cause_cat == "stroke",
    diabetes         = function(d) d$cause_cat == "diabetes",
    cancer           = function(d) d$cause_cat == "cancer",
    lung_cancer      = function(d) !is.na(d$cancer_site) & d$cancer_site == "lung",
    clrd             = function(d) d$cause_cat == "clrd",
    covid19          = function(d) d$cause_cat == "covid19",
    covid_anywhere   = function(d) d$cf_covid_anywhere,
    despair          = function(d) d$ind_deaths_of_despair,
    suicide          = function(d) d$cause_cat == "suicide",
    drug_any_intent  = function(d) d$ind_drug_poisoning_all_intents,
    alcohol_induced  = function(d) d$cause_cat == "alcohol_induced",
    obesity_contrib      = function(d) d$cf_obesity_anywhere,
    diabetes_contrib     = function(d) d$cf_diabetes_anywhere,
    hypertension_contrib = function(d) d$cf_hypertension_anywhere,
    # --- post hoc COVID stratification, author-requested 2026-08-25 ----------
    # Not prespecified; reported separately in covid_stratified.csv, never in
    # the prespecified secondary list. See output/decisions.md.
    obesity_contrib_covid        = function(d) d$cf_obesity_anywhere & d$cf_covid_anywhere,
    obesity_contrib_nocovid      = function(d) d$cf_obesity_anywhere & !d$cf_covid_anywhere,
    diabetes_contrib_covid       = function(d) d$cf_diabetes_anywhere & d$cf_covid_anywhere,
    diabetes_contrib_nocovid     = function(d) d$cf_diabetes_anywhere & !d$cf_covid_anywhere,
    hypertension_contrib_covid   = function(d) d$cf_hypertension_anywhere & d$cf_covid_anywhere,
    hypertension_contrib_nocovid = function(d) d$cf_hypertension_anywhere & !d$cf_covid_anywhere,
    cardiometabolic_nocovid      = function(d) d$cause_cat %in% CARDIOMETABOLIC &
                                                 !d$cf_covid_anywhere
  )
}

MEASURE_LABELS <- c(
  all_cause = "All causes", cardiometabolic = "Cardiometabolic (composite)",
  ihd = "Ischemic heart disease", other_cvd = "Other cardiovascular",
  stroke = "Stroke", diabetes = "Diabetes", cancer = "Cancer",
  lung_cancer = "Lung cancer", clrd = "Chronic lower respiratory disease",
  covid19 = "COVID-19", covid_anywhere = "COVID-19, contributing cause",
  despair = "Deaths of despair", suicide = "Suicide",
  drug_any_intent = "Drug poisoning, any intent",
  alcohol_induced = "Alcohol-induced",
  obesity_contrib = "Obesity, contributing cause",
  diabetes_contrib = "Diabetes, contributing cause",
  hypertension_contrib = "Hypertension, contributing cause",
  obesity_contrib_covid = "Obesity, contributing cause",
  obesity_contrib_nocovid = "Obesity, contributing cause",
  diabetes_contrib_covid = "Diabetes, contributing cause",
  diabetes_contrib_nocovid = "Diabetes, contributing cause",
  hypertension_contrib_covid = "Hypertension, contributing cause",
  hypertension_contrib_nocovid = "Hypertension, contributing cause",
  cardiometabolic_nocovid = "Cardiometabolic (composite)"
)

# ---- panels ---------------------------------------------------------------


build_deaths_panel <- function(years = YEARS) {
  banner("Building deaths panel (ages 25-74, US residents)")
  ms <- measure_defs()
  out <- list()
  for (y in years) {
    d <- open_dataset(PATHS$interim(sprintf("nvss_%d.parquet", y))) |>
      select(resident_status, age_years, sex, occ_code4, cause_cat, cancer_site,
             ind_deaths_of_despair, ind_drug_poisoning_all_intents,
             cf_covid_anywhere, cf_obesity_anywhere, cf_diabetes_anywhere,
             cf_hypertension_anywhere) |>
      collect()
    fl <- new_filter_log(sprintf("deaths_%d", y), nrow(d))
    d <- d[d$resident_status != 4L, ]
    fl_step(fl, "drop foreign residents (resident status 4)", nrow(d))
    d <- d[!is.na(d$age_years) & d$age_years >= 25 & d$age_years <= 74, ]
    fl_step(fl, "ages 25-74", nrow(d))
    d$age_band <- band_of(d$age_years)
    d <- d[!is.na(d$age_band), ]
    fl_step(fl, "valid age band", nrow(d))

    h <- harmonise_occ(d$occ_code4, unname(year_scheme()[as.character(y)]))
    d$occ_analysis <- h$analysis
    d$grp <- assign_group(d$occ_analysis)

    flags <- vapply(ms, function(f) f(d), logical(nrow(d)))
    flags[is.na(flags)] <- FALSE
    agg <- as_tibble(cbind(d[, c("grp", "sex", "age_band")], flags)) |>
      group_by(grp, sex, age_band) |>
      summarise(across(all_of(names(ms)), ~ sum(.x)), .groups = "drop") |>
      mutate(year = y)
    out[[length(out) + 1L]] <- agg
    attr(out[[length(out)]], "filters") <- fl_table(fl)
  }
  filters <- bind_rows(lapply(out, attr, "filters"))
  res <- bind_rows(out) |>
    pivot_longer(all_of(names(ms)), names_to = "measure", values_to = "deaths")
  attr(res, "filters") <- filters
  log_msg("  deaths panel: %s rows", format(nrow(res), big.mark = ","))
  res
}

build_pop_panel <- function(years = YEARS, rule = c("occp", "esr12")) {
  rule <- match.arg(rule)
  banner(sprintf("Building population panel (denominator rule: %s)", rule))
  np <- non_participating()
  out <- list()
  for (y in years) {
    excl <- np[[as.character(y)]]
    srcs <- ACS_FOR[[as.character(y)]]
    per_src <- list()
    for (s in srcs) {
      a <- open_dataset(PATHS$interim(sprintf("acs_%d.parquet", s))) |>
        select(state, age, sex, occ_code4, ESR, employed_civilian, PWGTP) |>
        collect()
      fl <- new_filter_log(sprintf("acs_%d_for_%d_%s", s, y, rule), nrow(a))
      a <- a[a$age >= 25 & a$age <= 74, ]
      fl_step(fl, "ages 25-74", nrow(a))
      if (length(excl)) {
        a <- a[!a$state %in% excl, ]
        fl_step(fl, sprintf("drop jurisdictions not reporting I&O in %d (%s)", y,
                            paste(excl, collapse = ",")), nrow(a))
      }
      # ACS uses the Census 2018 scheme in every year.
      a$occ_analysis <- harmonise_occ(a$occ_code4, "2018")$analysis
      keep <- denominator_rule(a, rule)
      a <- a[keep, ]
      fl_step(fl, sprintf("denominator rule '%s'", rule), nrow(a))
      a$grp <- assign_group(a$occ_analysis)
      a$age_band <- band_of(a$age)
      per_src[[length(per_src) + 1L]] <- a |>
        group_by(grp, sex, age_band) |>
        summarise(pop = sum(as.numeric(PWGTP)), n_sample = n(), .groups = "drop") |>
        mutate(acs_year = s)
    }
    # Average the source years within a data year (only 2020 has two).
    out[[length(out) + 1L]] <- bind_rows(per_src) |>
      group_by(grp, sex, age_band) |>
      summarise(pop = mean(pop), n_sample = mean(n_sample), .groups = "drop") |>
      mutate(year = y)
  }
  res <- bind_rows(out)
  log_msg("  population panel: %s rows", format(nrow(res), big.mark = ","))
  res
}

# ---- one estimate ---------------------------------------------------------

GROUPSETS <- list(
  clergy = "clergy",
  clergy_broad = c("clergy", "clergy_other_religious"),
  other_employed = "other_employed",
  community_social_services = "community_social_services"
)

cell_asr <- function(deaths, pop, gset, measure, years, bands = BAND_LABELS,
                     sex = NULL) {
  d <- deaths[deaths$grp %in% gset & deaths$measure == measure &
                deaths$year %in% years, ]
  p <- pop[pop$grp %in% gset & pop$year %in% years, ]
  if (!is.null(sex)) { d <- d[d$sex == sex, ]; p <- p[p$sex == sex, ] }
  d <- d[as.character(d$age_band) %in% bands, ]
  p <- p[as.character(p$age_band) %in% bands, ]
  dd <- d |> group_by(sex, age_band) |> summarise(deaths = sum(deaths), .groups = "drop")
  pp <- p |> group_by(sex, age_band) |> summarise(pop = sum(pop), .groups = "drop")
  cells <- full_join(dd, pp, by = c("sex", "age_band")) |>
    mutate(deaths = coalesce(deaths, 0), pop = coalesce(pop, 0))
  standardise(cells, bands = bands, by_sex = is.null(sex))
}

estimate <- function(deaths, pop, measure, a_set, b_set, years = YEARS,
                     bands = BAND_LABELS, sex = NULL) {
  A <- cell_asr(deaths, pop, a_set, measure, years, bands, sex)
  B <- cell_asr(deaths, pop, b_set, measure, years, bands, sex)
  ciA <- fay_feuer(A); ciB <- fay_feuer(B); rr <- rate_ratio(A, B)
  # Unpack before building the tibble: tibble() evaluates its arguments in
  # order and exposes each to the ones after it, so a column named `rr` would
  # shadow the `rr` vector and rr[["lower"]] would then fail.
  rr_point <- unname(rr[["rr"]]); rr_low <- unname(rr[["lower"]])
  rr_high <- unname(rr[["upper"]])
  tibble::tibble(
    measure = measure, label = unname(MEASURE_LABELS[measure]),
    sex = if (is.null(sex)) "both" else sex,
    a_deaths = A$deaths, a_pop = A$pop, a_rate = A$rate,
    a_lo = unname(ciA[["lower"]]), a_hi = unname(ciA[["upper"]]),
    b_deaths = B$deaths, b_pop = B$pop, b_rate = B$rate,
    b_lo = unname(ciB[["lower"]]), b_hi = unname(ciB[["upper"]]),
    rr = rr_point, rr_lo = rr_low, rr_hi = rr_high
  )
}

# ---- demographics for the Results paragraph -------------------------------

clergy_demographics <- function(pop, years = YEARS) {
  banner("Clergy demographics for the Results paragraph")
  rows <- list()
  for (y in years) {
    d <- open_dataset(PATHS$interim(sprintf("nvss_%d.parquet", y))) |>
      select(resident_status, age_years, sex, occ_code4) |> collect()
    d <- d[d$resident_status != 4L & !is.na(d$age_years) &
             d$age_years >= 25 & d$age_years <= 74, ]
    d$occ_analysis <- harmonise_occ(
      d$occ_code4, unname(year_scheme()[as.character(y)]))$analysis
    d <- d[!is.na(d$occ_analysis) & d$occ_analysis == CLERGY, ]
    rows[[length(rows) + 1L]] <- d[, c("age_years", "sex")]
  }
  d <- bind_rows(rows)
  py <- sum(pop$pop[pop$grp == "clergy" & pop$year %in% years])
  list(
    deaths = nrow(d),
    person_years = py,
    n_male = sum(d$sex == "M"), pct_male = 100 * mean(d$sex == "M"),
    mean_age = mean(d$age_years), sd_age = stats::sd(d$age_years),
    median_age = stats::median(d$age_years),
    q1 = unname(stats::quantile(d$age_years, 0.25)),
    q3 = unname(stats::quantile(d$age_years, 0.75))
  )
}

## ---- from R/pmr.R (VERBATIM; the letter's PMR code) -----------------------
# and smoking-driven categories where clergy differ most from other workers.
# NOTE: Phase 3's brief says this list is defined in config/cause_groups.yaml;
# it is not - config/ defines the cause CATEGORIES, and Phase 2 defined this
# exclusion list (by those category keys, plus lung cancer) in R/benchmark.R.
# It is MOVED here unchanged, not redefined; benchmark.R now reads it from
# this file. See output/decisions.md, 2026-08-26.
PMR_EXCLUDE_CAUSES <- c("suicide", "drug_poisoning", "alcohol_induced", "homicide",
                        "transport", "other_unintentional", "clrd")

# The one computation. `agg` has occ, lab, the strata columns, and .num/.den.
# Expected deaths for an occupation are the sum over strata of (occupation
# deaths in stratum x stratum-specific outcome proportion among ALL employed
# decedents). Exact Poisson interval on the observed count.
pmr_core <- function(agg, strata, min_den, min_obs, alpha = 0.05) {
  ref <- agg |>
    group_by(across(all_of(strata))) |>
    summarise(.p = sum(.num) / sum(.den), .groups = "drop")
  agg |>
    left_join(ref, by = strata) |>
    group_by(occ, lab) |>
    summarise(observed = sum(.num), expected = sum(.den * .p),
              denom_deaths = sum(.den), .groups = "drop") |>
    filter(denom_deaths >= min_den, observed >= min_obs) |>
    mutate(pmr = observed / expected,
           lo = stats::qgamma(alpha / 2, shape = observed) / expected,
           hi = stats::qgamma(1 - alpha / 2, shape = observed + 1) / expected) |>
    # .data pronoun, not the bare symbol: `pmr` is also the name of the
    # panel wrapper in benchmark.R, and targets' static analysis reads a bare
    # `pmr` here as that global, creating a pmr -> pmr_core -> pmr cycle that
    # fails tar_make() with "igraph::is_dag(graph) is not TRUE".
    arrange(desc(.data$pmr)) |>
    mutate(rank = row_number(), n_ranked = n())
}

# Row-per-death analysis frame for the PMR: one row per employed decedent aged
# 25-74, 2020-2021 unless `years` says otherwise. Columns follow the Phase 3
# interface: sex, age5, age10, raceeth, covid_underlying, natural.
build_pmr_deaths <- function(years = c(2020, 2021)) {
  out <- list()
  for (y in years) {
    d <- read_parquet(PATHS$interim(sprintf("nvss_%d.parquet", y)),
      col_select = c("resident_status", "age_years", "sex", "occ_code4",
                     "cause_cat", "cancer_site", "hispanic_origin",
                     "race_recode_40", "icd10_underlying"))
    fl <- new_filter_log(sprintf("pmr_deaths_%d", y), nrow(d))
    d <- d[d$resident_status != 4L, ]
    fl_step(fl, "drop foreign residents", nrow(d))
    d <- d[!is.na(d$age_years) & d$age_years >= 25 & d$age_years <= 74, ]
    fl_step(fl, "ages 25-74", nrow(d))
    h <- harmonise_occ(d$occ_code4, unname(year_scheme()[as.character(y)]))
    d$occ <- h$analysis; d$lab <- h$label
    d <- d[!is.na(d$occ), ]
    fl_step(fl, "occupation maps to an analysis code", nrow(d))
    d <- d[!d$occ %in% not_employed_codes(), ]
    fl_step(fl, "drop not-in-labor-force, unknown and military codes", nrow(d))
    is_lung <- !is.na(d$cancer_site) & d$cancer_site == "lung"
    # Strictly natural = not an external cause: underlying ICD-10 V01-Y89
    # (plus U03). This is what "natural causes" means to a reviewer; the
    # broader PMR_EXCLUDE_CAUSES set additionally removes alcohol-induced and
    # smoking-related NATURAL deaths and is labeled accordingly in outputs.
    is_external <- substr(d$icd10_underlying, 1, 1) %in% c("V", "W", "X", "Y") |
                   substr(d$icd10_underlying, 1, 3) == "U03"
    out[[length(out) + 1L]] <- tibble::tibble(
      occ = d$occ, lab = d$lab, sex = d$sex,
      age5 = as.character(cut(d$age_years, breaks = seq(25, 75, 5), right = FALSE)),
      age10 = as.character(band_of(d$age_years)),
      raceeth = nvss_race_eth(d$hispanic_origin, d$race_recode_40),
      covid_underlying = d$cause_cat == "covid19",
      natural = !d$cause_cat %in% PMR_EXCLUDE_CAUSES & !is_lung,
      natural_strict = !is_external,
      year = y
    )
  }
  bind_rows(out)
}

# Phase 3 Step 1 interface. `deaths` is one row per death (build_pmr_deaths).
# `cause_restriction = "natural"` drops the excluded categories from both the
# occupation's deaths and the reference composition (one filter does both,
# because the reference IS the pooled occupations); the outcome column is
# unaffected because COVID-19 is a natural cause.
pmr_by_occupation <- function(deaths,
                              strata = c("sex", "age5", "raceeth"),
                              cause_restriction = c("all", "natural",
                                                    "strict_natural"),
                              min_deaths = 100,
                              outcome = "covid_underlying",
                              min_obs = SUPPRESS_UNDER,
                              alpha = 0.05) {
  cause_restriction <- match.arg(cause_restriction)
  stopifnot(outcome %in% names(deaths), all(strata %in% names(deaths)))
  d <- switch(cause_restriction,
              all = deaths,
              natural = deaths[deaths$natural, ],
              strict_natural = deaths[deaths$natural_strict, ])
  agg <- d |>
    group_by(across(all_of(c("occ", "lab", strata)))) |>
    summarise(.num = sum(.data[[outcome]]), .den = n(), .groups = "drop")
  pmr_core(agg, strata, min_den = min_deaths, min_obs = min_obs, alpha = alpha)
}

## ---- from R/harmonize.R (verbatim): harmonized standardization ------------
AGE5_BREAKS <- seq(25, 75, 5)
age5_of <- function(age) as.character(cut(age, breaks = AGE5_BREAKS, right = FALSE))

std5 <- local({
  cache <- NULL
  function() {
    if (is.null(cache)) {
      x <- readr::read_csv(PATHS$config("std_pop_2000_5yr.csv"), comment = "#",
                           show_col_types = FALSE)
      # cut() labels: "[25,30)" etc.; map from the age5 labels in the file.
      lab <- sprintf("[%d,%d)", AGE5_BREAKS[-length(AGE5_BREAKS)], AGE5_BREAKS[-1])
      cache <<- setNames(x$std_pop / sum(x$std_pop), lab)
    }
    cache
  }
})

# The 16 numbers.csv rate-ratio rows -> measure + slice.
HARM_MAP <- list(
  rr_allcause = list(measure = "all_cause"),
  rr_drug = list(measure = "drug_any_intent"),
  rr_alcohol = list(measure = "alcohol_induced"),
  rr_suicide = list(measure = "suicide"),
  rr_diabetes_underlying = list(measure = "diabetes"),
  rr_obesity_anywhere = list(measure = "obesity_contrib"),
  rr_covid_underlying = list(measure = "covid19"),
  rr_covid_2020_2021 = list(measure = "covid19", years = c(2020, 2021)),
  rr_covid_2022_2024 = list(measure = "covid19", years = c(2022, 2023, 2024)),
  rr_covid_age_45_54 = list(measure = "covid19", age10 = "45-54"),
  rr_covid_age_55_64 = list(measure = "covid19", age10 = "55-64"),
  rr_covid_age_65_74 = list(measure = "covid19", age10 = "65-74"),
  rr_obesity_covid_cert = list(measure = "obesity_contrib_covid"),
  rr_diabetes_covid_cert = list(measure = "diabetes_contrib_covid"),
  rr_obesity_noncovid_cert = list(measure = "obesity_contrib_nocovid"),
  rr_diabetes_noncovid_cert = list(measure = "diabetes_contrib_nocovid")
)
# Reported in the memo comparison but not added to numbers.csv (the letter
# does not cite the composite).
HARM_EXTRA <- list(rr_cardiometabolic = list(measure = "cardiometabolic"))

harm_deaths_panel <- function() {
  banner("harmonize: deaths by group x sex x 5-y age x race/ethnicity")
  ms <- measure_defs()
  need <- unique(vapply(c(HARM_MAP, HARM_EXTRA), function(x) x$measure, ""))
  parts <- list()
  for (y in YEARS) {
    d <- read_parquet(PATHS$interim(sprintf("nvss_%d.parquet", y)),
      col_select = c("resident_status", "age_years", "sex", "occ_code4",
                     "cause_cat", "cancer_site", "hispanic_origin", "race_recode_40",
                     "ind_deaths_of_despair", "ind_drug_poisoning_all_intents",
                     "cf_covid_anywhere", "cf_obesity_anywhere",
                     "cf_diabetes_anywhere", "cf_hypertension_anywhere"))
    d <- d[d$resident_status != 4L & !is.na(d$age_years) &
             d$age_years >= 25 & d$age_years <= 74, ]
    d$occ_analysis <- harmonise_occ(
      d$occ_code4, unname(year_scheme()[as.character(y)]))$analysis
    d$grp <- assign_group(d$occ_analysis)
    d <- d[d$grp %in% c("clergy", "other_employed"), ]
    d$age5 <- age5_of(d$age_years)
    d$age10 <- as.character(band_of(d$age_years))
    d$raceeth <- nvss_race_eth(d$hispanic_origin, d$race_recode_40)
    # unknown race cannot enter race-stratified cells; ~0.05% of deaths
    # (see decisions.md 2026-08-27).
    d <- d[d$raceeth != "unknown", ]
    flags <- vapply(need, function(m) ms[[m]](d), logical(nrow(d)))
    flags[is.na(flags)] <- FALSE
    parts[[length(parts) + 1L]] <- as_tibble(
      cbind(d[, c("grp", "sex", "age5", "age10", "raceeth")], flags)) |>
      group_by(grp, sex, age5, age10, raceeth) |>
      summarise(across(all_of(need), sum), n_all_deaths = n(), .groups = "drop") |>
      mutate(year = y)
  }
  bind_rows(parts)
}

harm_pop_panel <- function() {
  banner("harmonize: person-years by group x sex x 5-y age x race/ethnicity")
  parts <- list()
  for (y in YEARS) {
    excl <- non_participating()[[as.character(y)]]
    for (src in ACS_FOR[[as.character(y)]]) {
      a <- read_parquet(PATHS$interim(sprintf("acs_%d.parquet", src)),
        col_select = c("state", "age", "sex", "occ_code4", "ESR",
                       "employed_civilian", "RAC1P", "HISP", "PWGTP"))
      a <- a[a$age >= 25 & a$age <= 74, ]
      if (length(excl)) a <- a[!a$state %in% excl, ]
      a$occ_analysis <- harmonise_occ(a$occ_code4, "2018")$analysis
      a <- a[denominator_rule(a, "occp"), ]
      a$grp <- assign_group(a$occ_analysis)
      a <- a[a$grp %in% c("clergy", "other_employed"), ]
      a$age5 <- age5_of(a$age)
      a$age10 <- as.character(band_of(a$age))
      a$raceeth <- acs_race_eth(a$HISP, a$RAC1P)
      parts[[length(parts) + 1L]] <- a |>
        group_by(grp, sex, age5, age10, raceeth) |>
        summarise(pop = sum(as.numeric(PWGTP)), .groups = "drop") |>
        mutate(year = y, src = src)
    }
  }
  bind_rows(parts) |>
    group_by(year, grp, sex, age5, age10, raceeth) |>
    summarise(pop = mean(pop), .groups = "drop")
}

# Joint standard weights: 2000 std pop over 5-y age x all-employed ACS
# composition of sex x race WITHIN each age band.
harm_weights <- function(pop) {
  comp <- pop |>
    group_by(age5, sex, raceeth) |>
    summarise(pop = sum(pop), .groups = "drop") |>
    group_by(age5) |>
    mutate(share = pop / sum(pop)) |>
    ungroup()
  comp$w <- unname(std5()[comp$age5]) * comp$share
  comp |> select(age5, sex, raceeth, w)
}

harm_asr <- function(deaths, pop, W, grp_name, measure, years = YEARS,
                     age10 = NULL) {
  d <- deaths[deaths$grp == grp_name & deaths$year %in% years, ]
  p <- pop[pop$grp == grp_name & pop$year %in% years, ]
  if (!is.null(age10)) { d <- d[d$age10 == age10, ]; p <- p[p$age10 == age10, ] }
  dd <- d |> group_by(age5, sex, raceeth) |>
    summarise(deaths = sum(.data[[measure]]), .groups = "drop")
  pp <- p |> group_by(age5, sex, raceeth) |>
    summarise(pop = sum(pop), .groups = "drop")
  cells <- pp |> left_join(dd, by = c("age5", "sex", "raceeth")) |>
    mutate(deaths = coalesce(deaths, 0)) |>
    inner_join(W, by = c("age5", "sex", "raceeth")) |>
    filter(pop > 0, w > 0)
  wn <- cells$w / sum(cells$w)                        # renormalize over cells present
  new_asr(rate = sum(wn * cells$deaths / cells$pop) * PER,
          var = sum(wn^2 * cells$deaths / cells$pop^2) * PER^2,
          wmax = max(wn / cells$pop) * PER,
          deaths = as.integer(sum(cells$deaths)), pop = sum(cells$pop))
}

## ---- from R/geo_bound.R (verbatim): geographic composition-only bound -----
WONDER_CSV <- function() PATHS$config("wonder_covid_region.csv")
GEO_YEARS <- c(2020, 2021)

state_region <- local({
  cache <- NULL
  function() {
    if (is.null(cache)) {
      x <- readr::read_csv(PATHS$config("state_region.csv"), comment = "#",
                           col_types = "ccc")
      cache <<- setNames(x$region, x$fips)
    }
    cache
  }
})


# ACS person-year distributions over region x age10 x sex for clergy,
# clergy-broad, and all other employed (letter comparator), 2020-2021 pooled,
# with the 80 replicate weights carried for the bootstrap.
geo_region_weights <- function() {
  banner("geo bound: ACS region x age x sex person-year distributions")
  reps <- sprintf("PWGTP%d", 1:80)
  parts <- list()
  for (y in GEO_YEARS) {
    excl <- non_participating()[[as.character(y)]]
    for (src in ACS_FOR[[as.character(y)]]) {
      a <- read_parquet(PATHS$interim(sprintf("acs_%d.parquet", src)),
        col_select = c("state", "age", "sex", "occ_code4", "ESR",
                       "employed_civilian", "PWGTP", all_of(reps)))
      a <- a[a$age >= 25 & a$age <= 74, ]
      if (length(excl)) a <- a[!a$state %in% excl, ]
      a$occ_analysis <- harmonise_occ(a$occ_code4, "2018")$analysis
      a <- a[denominator_rule(a, "occp"), ]
      a$grp <- assign_group(a$occ_analysis)
      a$region <- unname(state_region()[a$state])
      a$age10 <- as.character(band_of(a$age))
      g <- a |>
        mutate(gset = case_when(
          occ_analysis == "2040" ~ "clergy",
          occ_analysis %in% c("2040", "2050", "2060") ~ "broad_only",
          grp == "other_employed" ~ "other",
          TRUE ~ NA_character_)) |>
        filter(!is.na(gset), !is.na(region), !is.na(age10)) |>
        group_by(gset, region, age10, sex) |>
        summarise(across(c("PWGTP", all_of(reps)), \(x) sum(as.numeric(x))),
                  .groups = "drop") |>
        mutate(year = y, src = src)
      parts[[length(parts) + 1L]] <- g
    }
  }
  w <- bind_rows(parts) |>
    group_by(year, gset, region, age10, sex) |>
    summarise(across(c("PWGTP", all_of(reps)), mean), .groups = "drop") |>  # avg 2019/2021 for 2020
    group_by(gset, region, age10, sex) |>
    summarise(across(c("PWGTP", all_of(reps)), sum), .groups = "drop")      # pool 2020+2021
  # clergy-broad = clergy + the two other religious codes
  broad <- w |> filter(gset %in% c("clergy", "broad_only")) |>
    group_by(region, age10, sex) |>
    summarise(across(c("PWGTP", all_of(reps)), sum), .groups = "drop") |>
    mutate(gset = "clergy_broad")
  bind_rows(w |> filter(gset != "broad_only"), broad)
}

read_wonder <- function() {
  x <- readr::read_csv(WONDER_CSV(), show_col_types = FALSE, comment = "#")
  need <- c("year", "region", "age10", "sex", "total_deaths", "covid_deaths")
  miss <- setdiff(need, names(x))
  if (length(miss)) stop_hard("wonder_covid_region.csv lacks columns: %s",
                              paste(miss, collapse = ", "))
  x$sex <- dplyr::recode(x$sex, Male = "M", Female = "F", .default = x$sex)
  bad_r <- setdiff(unique(x$region), c("Northeast", "Midwest", "South", "West"))
  if (length(bad_r)) stop_hard("unexpected region values: %s", paste(bad_r, collapse = ", "))
  if (!all(x$covid_deaths <= x$total_deaths)) stop_hard("covid_deaths > total_deaths in WONDER file")
  x |> group_by(region, age10, sex) |>                    # pool 2020-2021
    summarise(total_deaths = sum(total_deaths),
              covid_deaths = sum(covid_deaths), .groups = "drop") |>
    mutate(p = covid_deaths / total_deaths)
}

# Composition-only PMR for one weight column, one stratification.
geo_ratio <- function(w, p_tab, wcol, strata = c("region", "age10", "sex")) {
  ww <- w |> group_by(gset, across(all_of(strata))) |>
    summarise(wt = sum(.data[[wcol]]), .groups = "drop")
  pp <- p_tab |> group_by(across(all_of(strata))) |>
    summarise(covid = sum(covid_deaths), tot = sum(total_deaths), .groups = "drop") |>
    mutate(p = covid / tot)
  j <- ww |> inner_join(pp |> select(all_of(strata), p), by = strata) |>
    group_by(gset) |> summarise(mean_p = sum(wt * p) / sum(wt), .groups = "drop")
  g <- setNames(j$mean_p, j$gset)
  c(clergy = unname(g["clergy"] / g["other"]),
    clergy_broad = unname(g["clergy_broad"] / g["other"]))
}

# Compute the bound quantities, or NULL when the WONDER file is absent.
geo_bound_values <- function(pmr_deaths) {
  if (!file.exists(WONDER_CSV())) return(NULL)
  w <- geo_region_weights()
  p_tab <- read_wonder()
  main <- geo_ratio(w, p_tab, "PWGTP")
  region_only <- geo_ratio(w, p_tab, "PWGTP", strata = "region")
  reps <- sprintf("PWGTP%d", 1:80)
  rep_vals <- vapply(reps, function(rc) geo_ratio(w, p_tab, rc)["clergy"], 0)
  se <- sqrt(4 / 80 * sum((rep_vals - main["clergy"])^2))
  rep_ro <- vapply(reps, function(rc)
    geo_ratio(w, p_tab, rc, strata = "region")["clergy"], 0)
  se_ro <- sqrt(4 / 80 * sum((rep_ro - region_only["clergy"])^2))
  ranked <- pmr_by_occupation(pmr_deaths, strata = c("sex", "age5", "raceeth"))
  cl <- ranked[ranked$occ == "2040", ]
  if (sprintf("%.2f", cl$pmr) != "1.94") {
    stop_hard("clergy PMR is %.2f, not the published 1.94 - stopping.", cl$pmr)
  }
  list(main = main, region_only = region_only,
       lo = main["clergy"] - 1.96 * se, hi = main["clergy"] + 1.96 * se,
       ro_lo = region_only["clergy"] - 1.96 * se_ro,
       ro_hi = region_only["clergy"] + 1.96 * se_ro,
       cl = cl, adj = unname(cl$pmr / main["clergy"]))
}

## ---- from R/letter_targets.R and R/pmr_period.R (verbatim): letter targets
LETTER_REF_OCCS <- c(clergy = "2040", taxi = "9141", childcare = "4600",
                     physicians = "3065", lawyers = "2100")

# Mean annual ACS-weighted clergy workforce, primary denominator rule
# (civilian, 25-74, nonblank OCCP, participation-restricted), 2020-2024, with
# a successive-difference-replication CI from the 80 replicate weights.
clergy_workforce <- function() {
  reps <- sprintf("PWGTP%d", 1:80)
  per_year <- list()
  for (y in YEARS) {
    excl <- non_participating()[[as.character(y)]]
    srcs <- list()
    for (src in ACS_FOR[[as.character(y)]]) {
      a <- arrow::read_parquet(PATHS$interim(sprintf("acs_%d.parquet", src)),
        col_select = c("state", "age", "occ_code4", "ESR", "employed_civilian",
                       "PWGTP", all_of(reps)))
      a <- a[a$age >= 25 & a$age <= 74, ]
      if (length(excl)) a <- a[!a$state %in% excl, ]
      a$occ_analysis <- harmonise_occ(a$occ_code4, "2018")$analysis
      a <- a[denominator_rule(a, "occp"), ]
      a <- a[!is.na(a$occ_analysis) & a$occ_analysis == "2040", ]
      srcs[[length(srcs) + 1L]] <- colSums(a[, c("PWGTP", reps)])
    }
    per_year[[length(per_year) + 1L]] <- Reduce(`+`, srcs) / length(srcs)
  }
  avg <- Reduce(`+`, per_year) / length(per_year)
  theta <- avg[["PWGTP"]]
  se <- sqrt(4 / 80 * sum((avg[reps] - theta)^2))
  c(est = theta, lo = theta - 1.96 * se, hi = theta + 1.96 * se)
}

# GATE check (2026-09-01, draft-9 author note): the Discussion's conditional
# claim - among deaths with COVID-19 on the certificate, obesity is mentioned
# about as often for clergy as for other workers - was inferred from the
# ratio of two population rate ratios (2.07/2.05), not computed. This
# computes it directly: observed clergy obesity mentions among
# COVID-19-certificate deaths vs the count expected at the other-employed
# stratum-specific mention proportions (sex x 5-y age x race/ethnicity, the
# letter's harmonized strata; unknown race excluded as in R/harmonize.R),
# with an exact Poisson interval on the observed count. Same filters as the
# harmonized deaths panel; 2020-2024.
obesity_conditional_covid <- function() {
  parts <- list()
  for (y in YEARS) {
    d <- arrow::read_parquet(PATHS$interim(sprintf("nvss_%d.parquet", y)),
      col_select = c("resident_status", "age_years", "sex", "occ_code4",
                     "hispanic_origin", "race_recode_40",
                     "cf_covid_anywhere", "cf_obesity_anywhere"))
    d <- d[d$resident_status != 4L & !is.na(d$age_years) &
             d$age_years >= 25 & d$age_years <= 74 & d$cf_covid_anywhere, ]
    d$occ_analysis <- harmonise_occ(
      d$occ_code4, unname(year_scheme()[as.character(y)]))$analysis
    d$grp <- assign_group(d$occ_analysis)
    d <- d[d$grp %in% c("clergy", "other_employed"), ]
    d$age5 <- as.character(cut(d$age_years, breaks = seq(25, 75, 5),
                               right = FALSE))
    d$raceeth <- nvss_race_eth(d$hispanic_origin, d$race_recode_40)
    d <- d[d$raceeth != "unknown", ]
    parts[[length(parts) + 1L]] <- d |>
      group_by(grp, sex, age5, raceeth) |>
      summarise(covid_deaths = n(), obesity = sum(cf_obesity_anywhere),
                .groups = "drop")
  }
  agg <- bind_rows(parts) |>
    group_by(grp, sex, age5, raceeth) |>
    summarise(covid_deaths = sum(covid_deaths), obesity = sum(obesity),
              .groups = "drop")
  ref <- agg[agg$grp == "other_employed", ]
  cl <- agg[agg$grp == "clergy", ] |>
    left_join(ref |> mutate(p = obesity / covid_deaths) |>
                select(sex, age5, raceeth, p),
              by = c("sex", "age5", "raceeth"))
  # every clergy stratum must have a reference proportion, or expected and
  # observed would cover different deaths
  stopifnot(!any(is.na(cl$p)))
  obs <- sum(cl$obesity); expd <- sum(cl$covid_deaths * cl$p)
  list(obs = obs, expected = expd, ratio = obs / expd,
       lo = stats::qgamma(0.025, obs) / expd,
       hi = stats::qgamma(0.975, obs + 1) / expd,
       clergy_share = obs / sum(cl$covid_deaths),
       other_share = sum(ref$obesity) / sum(ref$covid_deaths))
}

# Plot construction, split out of letter_figure_build 2026-09-14 so the
# submission exports (cairo PDF with embedded fonts; 350-dpi LZW TIFF) draw
# the IDENTICAL plot object. No aesthetic change; the figure-labels test and
# figure1_points.csv are unaffected.
letter_figure_plot <- function(pmr_deaths) {
  main <- pmr_by_occupation(pmr_deaths, strata = c("sex", "age5", "raceeth"))

  # Labeled points: everything the letter discusses, PLUS the rank-2
  # occupation - previously unlabeled, it sat between clergy and taxi and made
  # the leader lines ambiguous (memo section 8).
  lab_map <- c("2040" = "Clergy",
               "9141" = "Taxi drivers and chauffeurs",
               "2050" = "Directors, religious activities",
               "2060" = "Religious workers, all other",
               "4600" = "Childcare workers",
               "2310" = "Elementary/middle school teachers",
               "3065" = "Physicians and surgeons",
               "2100" = "Lawyers")
  rank2 <- main[main$rank == 2L, ]
  extra <- setNames("Furnace, kiln, and oven operators", rank2$occ)
  lab_map <- c(lab_map, extra[setdiff(names(extra), names(lab_map))])
  hi <- main[main$occ %in% names(lab_map), ] |>
    mutate(display = unname(lab_map[occ]), is_clergy = occ == "2040")

  # Every labeled point's plotted value is persisted and tested against
  # numbers.csv (tests/testthat/test-figure-labels.R).
  readr::write_csv(hi |> select(occ, display, rank, observed, pmr, lo, hi),
                   PATHS$output("letter", "figure1_points.csv"))

  clust <- hi |> filter(!is_clergy, rank <= 25) |> arrange(desc(pmr)) |>
    mutate(lx = 62, ly = 1.70 * 0.935^(row_number() - 1))
  right <- hi |> filter(!is_clergy, rank > 25) |>
    mutate(hj = ifelse(occ == "2310", 0, 1),
           lx = ifelse(occ == "2310", rank + 12, rank - 10),
           ly = pmr * ifelse(occ == "2100", 0.86,
                             ifelse(occ == "3065", 0.88, 1.07)))
  cl <- hi |> filter(is_clergy) |> mutate(lx = rank + 10, ly = hi * 1.04)

  p <- ggplot(main, aes(x = rank, y = pmr)) +
    geom_hline(yintercept = 1, linetype = "dashed", linewidth = 0.4,
               colour = "grey35") +
    geom_linerange(aes(ymin = lo, ymax = hi), colour = "grey78",
                   linewidth = 0.28) +
    geom_point(size = 0.55, colour = "grey30") +
    geom_linerange(data = hi, aes(ymin = lo, ymax = hi), colour = "black",
                   linewidth = 0.5) +
    geom_point(data = hi[!hi$is_clergy, ], size = 1.9, shape = 21,
               fill = "white", colour = "black", stroke = 0.7) +
    # Clergy: small filled diamond drawn BEFORE its CI so the interval stays
    # visible across the marker.
    geom_point(data = hi[hi$is_clergy, ], size = 1.8, shape = 23,
               fill = "black", colour = "black") +
    geom_linerange(data = hi[hi$is_clergy, ], aes(ymin = lo, ymax = hi),
                   colour = "black", linewidth = 0.6) +
    geom_segment(data = clust, aes(x = rank, y = pmr, xend = lx - 3, yend = ly),
                 linewidth = 0.25, colour = "grey55") +
    geom_text(data = clust, aes(x = lx, y = ly, label = display),
              hjust = 0, size = 2.6) +
    geom_text(data = right, aes(x = lx, y = ly, label = display, hjust = hj),
              size = 2.6) +
    geom_text(data = cl, aes(x = lx, y = ly, label = display),
              hjust = 0, size = 3.0, fontface = "bold") +
    scale_y_continuous(trans = "log", breaks = c(0.5, 1, 2),
                       labels = c("0.5", "1", "2")) +
    labs(x = sprintf("Occupation, ranked by ratio (n = %d with \u2265100 deaths)",
                     main$n_ranked[1]),
         y = "Standardized proportional mortality ratio (95% CI)") +
    theme_bw(base_size = 9) +
    theme(panel.grid.minor = element_blank(),
          panel.grid.major.x = element_blank())
  list(p = p, hi = hi, main = main)
}

letter_figure_build <- function(pmr_deaths,
                                out_pdf = PATHS$output("letter", "figure1.pdf"),
                                out_png = PATHS$output("letter", "figure1.png")) {
  banner("letter_figure: ranked COVID-19 PMR plot (Figure, panel A only)")
  fp <- letter_figure_plot(pmr_deaths)
  p <- fp$p; hi <- fp$hi
  ggsave(out_pdf, p, width = 6.8, height = 4.2, device = grDevices::pdf)
  ggsave(out_png, p, width = 6.8, height = 4.2, dpi = 300)
  log_msg("  wrote %s, %s, figure1_points.csv; %d occupations labeled",
          basename(out_pdf), basename(out_png), nrow(hi))
  c(out_pdf, out_png)
}

# ---- Community-and-social-services disaggregation (2026-08-27) -------------
# Locates the CSS group's COVID-19 excess: per-occupation PMRs for every
# 4-digit occupation in the Census community-and-social-services group, plus
# group-level PMRs with and without the religious codes. Same benchmark as the
# letter (2020-2021; sex x 5-year age x race/ethnicity; >=100-death floor for
# the official ranking).
#
# Analysis codes, verified against config/occ_crosswalk.csv: the 2018-scheme
# counselor codes 2001-2006 collapse to analysis code 2001 and the social
# worker codes 2011-2014 to 2011 (splits of the 2012-scheme 2000 and 2010), so
# "counselors" and "social workers" are already pooled at the analysis level.
# Note: 2016 is Social and Human Service Assistants; 2025 is Other Community
# and Social Service Specialists (the task brief's label for 2016 belongs to
# 2025 - both are included; see output/decisions.md).
CSS_CODES <- c("2001", "2011", "2015", "2016", "2025", "2040", "2050", "2060")
CLERGY_BROAD_CODES <- c("2040", "2050", "2060")

css_pmr_summary <- function(pmr_deaths) {
  # Reference proportions are computed before any floor is applied, so PMR
  # values are identical between the unfiltered and ranked runs; the ranked
  # run supplies the official rank among occupations with >=100 deaths.
  all_rows <- pmr_by_occupation(pmr_deaths, strata = c("sex", "age5", "raceeth"),
                                min_deaths = 0, min_obs = 0)
  ranked <- pmr_by_occupation(pmr_deaths, strata = c("sex", "age5", "raceeth"))

  cl <- ranked[ranked$occ == "2040", ]
  if (sprintf("%.2f", cl$pmr) != "1.94" ||
      sprintf("%.2f-%.2f", cl$lo, cl$hi) != "1.87-2.01" || cl$rank != 1L) {
    stop_hard("clergy PMR is %.2f (%.2f-%.2f) rank %d, not the published 1.94 ",
              "(1.87-2.01) rank 1 - an estimate changed; stopping per the task brief.",
              cl$pmr, cl$lo, cl$hi, cl$rank)
  }

  tab <- all_rows |>
    filter(occ %in% CSS_CODES) |>
    left_join(ranked |> select(occ, official_rank = rank), by = "occ") |>
    mutate(below_floor = denom_deaths < 100,
           small_count = observed < SUPPRESS_UNDER) |>
    arrange(desc(pmr))

  grp <- function(codes, label) {
    m <- all_rows[all_rows$occ %in% codes, ]
    obs <- sum(m$observed); expd <- sum(m$expected)
    tibble::tibble(occ = NA_character_, lab = label,
                   denom_deaths = sum(m$denom_deaths), observed = obs,
                   expected = expd, pmr = obs / expd,
                   lo = stats::qgamma(0.025, obs) / expd,
                   hi = stats::qgamma(0.975, obs + 1) / expd,
                   official_rank = NA_integer_,
                   below_floor = FALSE, small_count = obs < SUPPRESS_UNDER)
  }
  list(
    table = tab,
    group_all = grp(CSS_CODES, "Community and social services, all"),
    group_excl = grp(setdiff(CSS_CODES, CLERGY_BROAD_CODES),
                     "Community and social services, excl. clergy-broad"),
    n_ranked = ranked$n_ranked[1]
  )
}

css_disaggregation_build <- function(pmr_deaths,
                                     path = PATHS$output("letter", "css_disaggregation.csv")) {
  banner("letter_css: community-and-social-services disaggregation")
  s <- css_pmr_summary(pmr_deaths)
  x <- crosswalk_tbl()
  src <- function(occ) {
    if (is.na(occ)) return(NA_character_)
    paste0("2012:", paste(sort(unique(x$source_code[x$scheme == "2012" &
                                                      x$analysis_code == occ])),
                          collapse = "/"),
           " 2018:", paste(sort(unique(x$source_code[x$scheme == "2018" &
                                                       x$analysis_code == occ])),
                           collapse = "/"))
  }
  out <- bind_rows(s$table |> mutate(expected = expected), s$group_all, s$group_excl) |>
    mutate(source_codes = vapply(occ, src, ""),
           suppressed = below_floor | small_count,
           deaths_2020_2021 = denom_deaths,
           covid_deaths = ifelse(small_count, NA_integer_, observed),
           pmr = round(pmr, 2), lower = round(lo, 2), upper = round(hi, 2),
           rank = official_rank,
           note = case_when(
             below_floor ~ "below 100-death floor; not in the official ranking",
             small_count ~ sprintf("count under %d suppressed", SUPPRESS_UNDER),
             is.na(occ) ~ "group-level PMR (sum observed / sum expected)",
             TRUE ~ sprintf("rank among %d occupations with >=100 deaths", s$n_ranked))) |>
    select(analysis_code = occ, label = lab, source_codes, deaths_2020_2021,
           covid_deaths, pmr, lower, upper, rank, suppressed, note)
  readr::write_csv(out, path)
  log_msg("  wrote %s (%d occupations + 2 group rows)", basename(path), nrow(out) - 2L)
  path
}

# ---- Table 1 (2026-08-27): built from numbers.csv --------------------------

TABLE1_SPEC <- tibble::tribble(
  ~base,                  ~label,
  "allcause",             "All causes",
  "drug",                 "Drug poisoning",
  "alcohol",              "Alcohol-induced causes",
  "suicide",              "Suicide",
  "covid_underlying",     "COVID-19, 2020-2024",
  "covid_2020_2021",      "COVID-19, 2020-2021",
  "covid_2022_2024",      "COVID-19, 2022-2024",
  "obesity_covid_cert",   "Obesity mentioned, COVID-19 certificates",
  "obesity_noncovid_cert","Obesity mentioned, other certificates"
)

# Clergy row of an unfloored, unranked PMR run over a subset of deaths:
# clergy vs all employed decedents in the subset, exact Poisson CI.
clergy_pmr_of <- function(deaths, strata = c("sex", "age5", "raceeth")) {
  tab <- pmr_by_occupation(deaths, strata = strata, min_deaths = 0, min_obs = 0)
  tab[tab$occ == "2040", ][1, ]
}

# Clergy-broad (2040 + 2050 + 2060) from an unfloored run: summed observed
# and expected, as in css_pmr_summary's group rows.
pmr_broad_of <- function(tab_unfloored) {
  m <- tab_unfloored[tab_unfloored$occ %in% CLERGY_BROAD, ]
  obs <- sum(m$observed); expd <- sum(m$expected)
  tibble::tibble(observed = obs, expected = expd, pmr = obs / expd,
                 lo = stats::qgamma(0.025, obs) / expd,
                 hi = stats::qgamma(0.975, obs + 1) / expd,
                 denom_deaths = sum(m$denom_deaths))
}

# pmr_deaths_2021_by_month, ADAPTED from R/pmr_period.R: the full repo's
# interim parquet lacks month, so it re-reads the raw file and aligns by
# record order; here 01_data.R parses month in the main pass, so month comes
# straight from the parquet. The verification guard is kept unchanged: the
# frame must reproduce build_pmr_deaths(2021)'s row count and COVID-19 total.
pmr_deaths_2021_by_month <- function() {
  d <- arrow::read_parquet(PATHS$interim("nvss_2021.parquet"),
    col_select = c("resident_status", "age_years", "sex", "occ_code4",
                   "cause_cat", "hispanic_origin", "race_recode_40", "month"))
  d <- d[d$resident_status != 4L, ]
  d <- d[!is.na(d$age_years) & d$age_years >= 25 & d$age_years <= 74, ]
  h <- harmonise_occ(d$occ_code4, unname(year_scheme()[["2021"]]))
  d$occ <- h$analysis; d$lab <- h$label
  d <- d[!is.na(d$occ), ]
  d <- d[!d$occ %in% not_employed_codes(), ]
  out <- tibble::tibble(
    occ = d$occ, lab = d$lab, sex = d$sex,
    age5 = as.character(cut(d$age_years, breaks = seq(25, 75, 5),
                            right = FALSE)),
    raceeth = nvss_race_eth(d$hispanic_origin, d$race_recode_40),
    covid_underlying = d$cause_cat == "covid19",
    month = d$month)
  ref <- build_pmr_deaths(years = 2021)
  if (nrow(out) != nrow(ref) ||
      sum(out$covid_underlying) != sum(ref$covid_underlying)) {
    stop_hard("2021 month frame does not reproduce build_pmr_deaths(2021); aborting")
  }
  out
}

# add()/add_rr()/add_pmr()/st(), from R/letter_targets.R::letter_numbers_build
# (defined there as locals; lifted to the top level so the sections below
# accumulate the same rows with the same rounding).
ROWS <- list()
add <- function(name, value, lower = NA_real_, upper = NA_real_,
                n = NA_integer_, note = "") {
  ROWS[[length(ROWS) + 1L]] <<- tibble::tibble(
    name = name, value = value, lower = lower, upper = upper,
    n = as.integer(n), note = note)
}
add_rr <- function(name, e, note) {
  add(name, round(e$rr, 2), round(e$rr_lo, 2), round(e$rr_hi, 2),
      e$a_deaths, note)
}
add_pmr <- function(name, tab, occ, note) {
  r <- tab[tab$occ == occ, ][1, ]
  add(name, round(r$pmr, 2), round(r$lo, 2), round(r$hi, 2), r$observed, note)
}
st <- function(m, years = YEARS, bands = BAND_LABELS) {
  estimate(deaths_panel, pop_panel, m, GROUPSETS$clergy,
           GROUPSETS$other_employed, years = years, bands = bands)
}

## ===========================================================================
## Section 2. Groups and population
## Methods: "We analyzed National Vital Statistics System multiple cause-of-
## death public-use files, 2020-2024 (clergy, Census occupation code 2040).
## Person-years at risk in each occupation came from the American Community
## Survey." Comparators (Results): physicians, teachers, counselors, social
## workers, funeral workers.
## ===========================================================================
banner("Section 2: groups and population")
log_msg("  clergy %s; clergy-broad adds %s; comparators: physicians 3065,",
        CLERGY, paste(setdiff(CLERGY_BROAD, CLERGY), collapse = ","))
log_msg("  teachers 2310, counselors 2001, social workers 2011,")
log_msg("  morticians 4465, embalmers 4461; CSS group: %s",
        paste(CSS_CODES, collapse = " "))
log_msg("  jurisdiction restriction: 2020 drops %s; 2021 drops %s; none later",
        paste(non_participating()[["2020"]], collapse = ","),
        paste(non_participating()[["2021"]], collapse = ","))
pmr_deaths   <- build_pmr_deaths()        # employed decedents, 2020-2021
deaths_panel <- build_deaths_panel()      # deaths x measure x year, 2020-2024
pop_panel    <- build_pop_panel(rule = "occp")  # primary denominator

## ===========================================================================
## Section 3. Demographics and workforce
## Results: "There were 23,234 clergy deaths at ages 25 to 74 years (19,128
## [82.3%] male; mean [SD] age, 65.3 [8.3] years)." Introduction: "a
## workforce of approximately 490,000" (SDR CI from the 80 replicate weights).
## ===========================================================================
banner("Section 3: demographics")
demo <- clergy_demographics(pop_panel)
add("clergy_deaths", demo$deaths, n = demo$deaths,
    note = "clergy deaths, ages 25-74, 2020-2024")
add("clergy_male_n", demo$n_male, n = demo$n_male, note = "male decedents")
add("clergy_male_pct", round(demo$pct_male, 1), note = "percent male")
add("clergy_age_mean", round(demo$mean_age, 1), note = "mean age at death, y")
add("clergy_age_sd", round(demo$sd_age, 1), note = "SD of age at death, y")
add("clergy_person_years", round(demo$person_years),
    note = "ACS person-years, primary denominator")
wf <- clergy_workforce()
add("acs_clergy_workforce", round(wf[["est"]]), round(wf[["lo"]]),
    round(wf[["hi"]]), NA,
    paste0("mean annual ACS-weighted clergy, primary denominator ",
           "(civilian 25-74, nonblank OCCP, participating jurisdictions), ",
           "2020-2024; SDR CI"))
readr::write_csv(dplyr::bind_rows(ROWS), "results/demographics.csv")
log_msg("  deaths %s | male %.1f%% | age %.1f (SD %.1f) | workforce %s",
        format(demo$deaths, big.mark = ","), demo$pct_male, demo$mean_age,
        demo$sd_age, format(round(wf[["est"]]), big.mark = ","))

## ===========================================================================
## Section 4. Rates, rate ratios, and the Table
## Results: "Clergy mortality was lower than that of other employed adults
## for all causes and far lower for drug poisoning, alcohol-induced causes,
## and suicide (Table)." 4a: sex-only standardization (Table counts); 4b:
## harmonized standardization (the letter's quoted values); 4c: the Table.
## ===========================================================================
banner("Section 4a: sex-only standardized rate ratios")
add_rr("rr_allcause", st("all_cause"), "all-cause, clergy vs other employed")
add_rr("rr_drug", st("drug_any_intent"), "drug poisoning, any intent")
add_rr("rr_alcohol", st("alcohol_induced"), "alcohol-induced")
add_rr("rr_suicide", st("suicide"), "suicide")
add_rr("rr_diabetes_underlying", st("diabetes"), "diabetes as underlying cause")
add_rr("rr_obesity_anywhere", st("obesity_contrib"),
       "obesity recorded anywhere on the certificate")
add_rr("rr_covid_underlying", st("covid19"), "COVID-19 underlying, 2020-2024")
add_rr("rr_covid_2020_2021", st("covid19", years = c(2020, 2021)),
       "COVID-19 underlying, 2020-2021")
add_rr("rr_covid_2022_2024", st("covid19", years = c(2022, 2023, 2024)),
       "COVID-19 underlying, 2022-2024")
add_rr("rr_covid_age_45_54", st("covid19", bands = "45-54"),
       "COVID-19, ages 45-54")
add_rr("rr_covid_age_55_64", st("covid19", bands = "55-64"),
       "COVID-19, ages 55-64")
add_rr("rr_covid_age_65_74", st("covid19", bands = "65-74"),
       "COVID-19, ages 65-74")
add_rr("rr_obesity_covid_cert", st("obesity_contrib_covid"),
       "obesity mention, deaths with COVID-19 on the record")
add_rr("rr_diabetes_covid_cert", st("diabetes_contrib_covid"),
       "diabetes mention, deaths with COVID-19 on the record")
add_rr("rr_obesity_noncovid_cert", st("obesity_contrib_nocovid"),
       "obesity mention, deaths without COVID-19 on the record")
add_rr("rr_diabetes_noncovid_cert", st("diabetes_contrib_nocovid"),
       "diabetes mention, deaths without COVID-19 on the record")

banner("Section 4b: harmonized standardization (sex x 5-y age x race/ethnicity)")
hd <- harm_deaths_panel()
hp <- harm_pop_panel()
W  <- harm_weights(hp)
# loop and rounding verbatim from R/harmonize.R::harmonized_build (minus the
# old-vs-new comparison columns, which needed the full repo's numbers.csv)
harm <- list()
for (nm in names(c(HARM_MAP, HARM_EXTRA))) {
  spec <- c(HARM_MAP, HARM_EXTRA)[[nm]]
  years <- if (is.null(spec$years)) YEARS else spec$years
  a <- harm_asr(hd, hp, W, "clergy", spec$measure, years, spec$age10)
  b <- harm_asr(hd, hp, W, "other_employed", spec$measure, years, spec$age10)
  rr <- rate_ratio(a, b)
  cia <- fay_feuer(a); cib <- fay_feuer(b)
  harm[[length(harm) + 1L]] <- tibble::tibble(
    name = nm,
    harm_value = round(unname(rr[["rr"]]), 2),
    harm_lower = round(unname(rr[["lower"]]), 2),
    harm_upper = round(unname(rr[["upper"]]), 2),
    clergy_deaths = a$deaths,
    clergy_rate = round(a$rate, 1),
    clergy_rate_lo = round(unname(cia[["lower"]]), 1),
    clergy_rate_hi = round(unname(cia[["upper"]]), 1),
    other_rate = round(b$rate, 1),
    other_rate_lo = round(unname(cib[["lower"]]), 1),
    other_rate_hi = round(unname(cib[["upper"]]), 1),
    in_numbers_csv = nm %in% names(HARM_MAP))
}
harm <- dplyr::bind_rows(harm)
readr::write_csv(harm, "results/rr_harmonized.csv")
for (i in which(harm$in_numbers_csv)) {
  add(paste0(harm$name[i], "_harm"), harm$harm_value[i], harm$harm_lower[i],
      harm$harm_upper[i], harm$clergy_deaths[i],
      "harmonized standardization: sex x 5-y age x race/ethnicity")
}
t1 <- c(allcause = "rr_allcause", drug = "rr_drug", alcohol = "rr_alcohol",
        suicide = "rr_suicide", covid_underlying = "rr_covid_underlying",
        covid_2020_2021 = "rr_covid_2020_2021",
        covid_2022_2024 = "rr_covid_2022_2024",
        obesity_covid_cert = "rr_obesity_covid_cert",
        obesity_noncovid_cert = "rr_obesity_noncovid_cert")
for (b in names(t1)) {
  hr <- harm[harm$name == t1[[b]], ][1, ]
  add(paste0("rate_clergy_", b, "_harm"), hr$clergy_rate, hr$clergy_rate_lo,
      hr$clergy_rate_hi, hr$clergy_deaths,
      "clergy rate per 100,000, harmonized standardization")
  add(paste0("rate_other_", b, "_harm"), hr$other_rate, hr$other_rate_lo,
      hr$other_rate_hi, NA,
      "other employed rate per 100,000, harmonized standardization")
}

banner("Section 4c: the Table (results/table1.csv)")
# construction verbatim from R/letter_targets.R::letter_table1_build, minus
# the gt/docx rendering; counts are the FULL category counts (sex-only rows)
# while rates and ratios standardize on the known-race/ethnicity subset.
computed_so_far <- dplyr::bind_rows(ROWS)
tab <- do.call(rbind, lapply(seq_len(nrow(TABLE1_SPEC)), function(i) {
  b <- TABLE1_SPEC$base[i]
  rrn <- if (b == "allcause") "rr_allcause_harm" else
    paste0(sub("^", "rr_", b), "_harm")
  g <- function(nm) { r <- computed_so_far[computed_so_far$name == nm, ]
                      stopifnot(nrow(r) == 1); r }
  rr <- g(rrn); rc <- g(paste0("rate_clergy_", b, "_harm"))
  ro <- g(paste0("rate_other_", b, "_harm"))
  deaths <- g(sub("_harm$", "", rrn))$n
  data.frame(
    Cause = TABLE1_SPEC$label[i],
    `Clergy deaths, No.` = ifelse(is_suppressed(deaths), "NR",
                                  format(deaths, big.mark = ",")),
    `Clergy rate per 100,000 (95% CI)` =
      sprintf("%.1f (%.1f-%.1f)", rc$value, rc$lower, rc$upper),
    `Other employed rate per 100,000 (95% CI)` =
      sprintf("%.1f (%.1f-%.1f)", ro$value, ro$lower, ro$upper),
    `Rate ratio (95% CI)` = sprintf("%.2f (%.2f-%.2f)", rr$value, rr$lower, rr$upper),
    check.names = FALSE)
}))
readr::write_csv(tab, "results/table1.csv")
print(tab, right = FALSE, row.names = FALSE)

## ===========================================================================
## Section 5. Period, age-band, and year-specific COVID-19 rate ratios
## Results: "COVID-19 mortality among clergy was 1.76 times that of other
## employed adults. It was double in 2020-2021 (207.0 vs 101.1 per 100,000;
## rate ratio, 2.05; 95% CI, 1.95-2.15) and at parity in 2022-2024 (1.06;
## 95% CI, 0.93-1.21). The excess peaked at ages 45-54 (2.57) and 55-64
## (2.35) (Table)." Year-specific rate ratios use year-matched denominators
## (2020 = mean of the 2019 and 2021 ACS, as in Methods).
## ===========================================================================
banner("Section 5: COVID-19 by period, age band, and single year")
for (yy in c(2020L, 2021L)) {
  a <- harm_asr(hd, hp, W, "clergy", "covid19", years = yy)
  b <- harm_asr(hd, hp, W, "other_employed", "covid19", years = yy)
  rr <- rate_ratio(a, b)
  add(sprintf("rr_covid_%d", yy), round(unname(rr[["rr"]]), 2),
      round(unname(rr[["lower"]]), 2), round(unname(rr[["upper"]]), 2),
      a$deaths,
      sprintf(paste0("COVID-19 rate ratio, %d alone, harmonized ",
                     "standardization, year-matched ACS denominator"), yy))
}
pa <- dplyr::bind_rows(ROWS)
pa <- pa[grepl("^rr_covid", pa$name), ]
readr::write_csv(pa, "results/covid_periods_ages.csv")
for (i in seq_len(nrow(pa))) {
  log_msg("  %-28s %.2f (%.2f-%.2f)", pa$name[i], pa$value[i], pa$lower[i],
          pa$upper[i])
}

## ===========================================================================
## Section 6. The pooled PMR benchmark, 2020-2021
## Results: "Among 450 occupations, clergy had the highest COVID-19 PMR in
## 2020-2021 (1.94; 95% CI, 1.87-2.01) (Figure). ... More than 1 in 4 clergy
## deaths in 2020-2021 involved COVID-19 (2,922 of 11,123 [26.3%]) vs 1 in 8
## expected (13.5%), an excess of 1,416 deaths. Excluding external causes,
## clergy remained first (1.95). Additionally excluding tobacco-related and
## alcohol-induced causes, clergy ranked second (1.75; 95% CI, 1.69-1.82).
## Adjacent occupations were near the null: physicians (0.94), teachers
## (0.98), counselors (0.99), social workers (0.97), and funeral workers
## (1.15)."
## ===========================================================================
banner("Section 6: pooled proportional-mortality benchmark")
main <- pmr_by_occupation(pmr_deaths, strata = c("sex", "age5", "raceeth"))
readr::write_csv(main, "results/pmr_benchmark.csv")
cl <- main[main$occ == "2040", ][1, ]
add_pmr("pmr_clergy", main, "2040",
        "COVID-19 PMR 2020-2021, sex x 5-y age x race/ethnicity")
add("pmr_clergy_deaths", cl$observed, n = cl$observed,
    note = "observed clergy COVID-19 deaths, 2020-2021")
add("pmr_clergy_rank", cl$rank, note = "clergy rank on the PMR")
add("pmr_n_occupations", cl$n_ranked,
    note = "occupations with >=100 deaths, 2020-2021")
add_pmr("pmr_taxi", main, LETTER_REF_OCCS[["taxi"]],
        "taxi drivers and chauffeurs")
add_pmr("pmr_teachers", main, "2310", "elementary and middle school teachers")
add_pmr("pmr_morticians", main, "4465",
        "morticians, undertakers, and funeral arrangers")
add_pmr("pmr_embalmers", main, "4461",
        "embalmers, crematory operators, and funeral attendants")
add_pmr("pmr_childcare", main, LETTER_REF_OCCS[["childcare"]],
        "childcare workers")
add_pmr("pmr_physicians", main, LETTER_REF_OCCS[["physicians"]],
        "physicians and surgeons")
add_pmr("pmr_lawyers", main, LETTER_REF_OCCS[["lawyers"]], "lawyers")
r2 <- main[main$rank == 2L, ]
add("pmr_rank2_occupation", round(r2$pmr, 2), round(r2$lo, 2), round(r2$hi, 2),
    r2$observed, r2$lab[1])                     # note carries the name
nat <- pmr_by_occupation(pmr_deaths, strata = c("sex", "age5"),
                         cause_restriction = "natural")
natcl <- nat[nat$occ == "2040", ][1, ]
add_pmr("pmr_clergy_natural", nat, "2040",
        "clergy PMR restricted to natural causes")
add("pmr_clergy_natural_rank", natcl$rank,
    note = "clergy rank, natural-causes restriction")
n1 <- nat[nat$rank == 1L, ]
add("pmr_natural_rank1_occupation", NA_real_, NA, NA, n1$observed, n1$lab[1])
add("pmr_natural_rank1_value", round(n1$pmr, 2), round(n1$lo, 2),
    round(n1$hi, 2), n1$observed,
    "highest PMR excluding external, alcohol-induced, and smoking-related causes")
nats <- pmr_by_occupation(pmr_deaths, strata = c("sex", "age5"),
                          cause_restriction = "strict_natural")
ns_cl <- nats[nats$occ == "2040", ]
add("pmr_clergy_natural_strict", round(ns_cl$pmr, 2), round(ns_cl$lo, 2),
    round(ns_cl$hi, 2), ns_cl$observed,
    "clergy PMR restricted to natural causes (external causes excluded)")
add("pmr_clergy_natural_strict_rank", ns_cl$rank,
    note = sprintf("rank among %d occupations, strict natural causes",
                   ns_cl$n_ranked[1]))
ns2 <- nats[nats$rank == 2L, ]
add("pmr_natural_strict_rank2_occupation", round(ns2$pmr, 2), round(ns2$lo, 2),
    round(ns2$hi, 2), ns2$observed, ns2$lab[1])
clb <- main[main$occ == "2040", ]
add("pmr_clergy_expected_2020_2021", round(clb$expected), n = clb$observed,
    note = "expected clergy COVID-19 deaths 2020-2021 at all-worker composition")
add("excess_covid_deaths_2020_2021", round(clb$observed - clb$expected),
    n = clb$observed, note = "observed minus expected clergy COVID-19 deaths")
add("covid_share_clergy_2020_2021",
    round(100 * clb$observed / clb$denom_deaths, 1), n = clb$observed,
    note = "COVID-19 share of clergy deaths 2020-2021, %")
add("covid_share_expected_2020_2021",
    round(100 * clb$expected / clb$denom_deaths, 1), n = clb$observed,
    note = "expected COVID-19 share at all-worker composition, %")
add("clergy_deaths_2020_2021", clb$denom_deaths, n = clb$denom_deaths,
    note = "clergy deaths 2020-2021, benchmark denominator (employed decedents)")
log_msg("  clergy PMR %.2f (%.2f-%.2f), rank %d of %d", cl$pmr, cl$lo, cl$hi,
        cl$rank, cl$n_ranked)

## ===========================================================================
## Section 7. Year-specific PMR benchmarks
## Results: "The excess was already second highest in 2020 (1.79; 95% CI,
## 1.68-1.90)" -- reference composition within each year, >=100-death floor
## within each year (363 occupations in 2020; 419 in 2021).
## ===========================================================================
banner("Section 7: year-specific benchmarks")
yr_rows <- list()
for (yy in c(2020L, 2021L)) {
  dy <- build_pmr_deaths(years = yy)
  ranked_y   <- pmr_by_occupation(dy, strata = c("sex", "age5", "raceeth"))
  ranked_y50 <- pmr_by_occupation(dy, strata = c("sex", "age5", "raceeth"),
                                  min_deaths = 50)
  cly   <- ranked_y[ranked_y$occ == "2040", ][1, ]
  cly50 <- ranked_y50[ranked_y50$occ == "2040", ][1, ]
  add(sprintf("pmr_clergy_%d", yy), round(cly$pmr, 2), round(cly$lo, 2),
      round(cly$hi, 2), cly$observed,
      sprintf(paste0("clergy COVID-19 PMR, %d alone; expected %.0f; ",
                     "reference composition within the year"),
              yy, cly$expected))
  add(sprintf("pmr_clergy_%d_rank", yy), cly$rank,
      note = sprintf(paste0("rank among %d occupations with >=100 deaths ",
                            "in %d; >=50-death floor (sensitivity): rank ",
                            "%d of %d"),
                     cly$n_ranked, yy, cly50$rank, cly50$n_ranked))
  yr_rows[[length(yr_rows) + 1L]] <- tibble::tibble(
    year = yy, observed = cly$observed, expected = round(cly$expected, 1),
    pmr = round(cly$pmr, 3), lo = round(cly$lo, 3), hi = round(cly$hi, 3),
    rank = cly$rank, n_ranked = cly$n_ranked)
  log_msg("  %d: PMR %.2f (%.2f-%.2f), rank %d of %d", yy, cly$pmr, cly$lo,
          cly$hi, cly$rank, cly$n_ranked)
}
readr::write_csv(dplyr::bind_rows(yr_rows), "results/pmr_by_year.csv")

## ===========================================================================
## Section 8. The within-2021 split
## Results: "...widened after universal adult vaccine eligibility, from 1.77
## in early 2021 to 2.18 thereafter." Boundary April 30, 2021 (all US adults
## vaccine-eligible by April 19); month of death from the parquet; reference
## composition within each period; clergy vs all employed, no ranking.
## ===========================================================================
banner("Section 8: within-2021 split at April 30")
d21m <- pmr_deaths_2021_by_month()
early <- clergy_pmr_of(d21m[d21m$month <= 4L, ])
late  <- clergy_pmr_of(d21m[d21m$month >= 5L, ])
stopifnot(early$observed + late$observed ==
            sum(d21m$covid_underlying[d21m$occ == "2040"]))
add("pmr_clergy_2021_jan_apr", round(early$pmr, 2), round(early$lo, 2),
    round(early$hi, 2), early$observed,
    sprintf(paste0("clergy COVID-19 PMR, 2021 Jan-Apr (boundary Apr 30; ",
                   "adults vaccine-eligible Apr 19); expected %.0f"),
            early$expected))
add("pmr_clergy_2021_may_dec", round(late$pmr, 2), round(late$lo, 2),
    round(late$hi, 2), late$observed,
    sprintf("clergy COVID-19 PMR, 2021 May-Dec; expected %.0f",
            late$expected))
log_msg("  Jan-Apr %.2f (%.2f-%.2f) | May-Dec %.2f (%.2f-%.2f)",
        early$pmr, early$lo, early$hi, late$pmr, late$lo, late$hi)

## ===========================================================================
## Section 9. Conditional obesity mention ratio among COVID-19 deaths
## Discussion: "Among COVID-19 deaths, obesity was mentioned more often for
## clergy (1.22; 95% CI, 1.09-1.37)..." (Population obesity rows for the
## Table were computed in section 4.)
## ===========================================================================
banner("Section 9: conditional obesity mention ratio")
oc <- obesity_conditional_covid()
add("obesity_share_covid_certs_ratio", round(oc$ratio, 2), round(oc$lo, 2),
    round(oc$hi, 2), oc$obs,
    sprintf(paste0("obesity mentions per COVID-19-certificate death, clergy ",
                   "vs other employed, standardized over sex x 5-y age x ",
                   "race/ethnicity, 2020-2024; crude %.1f%% vs %.1f%%"),
            100 * oc$clergy_share, 100 * oc$other_share))
log_msg("  ratio %.2f (%.2f-%.2f); crude %.1f%% vs %.1f%%", oc$ratio, oc$lo,
        oc$hi, 100 * oc$clergy_share, 100 * oc$other_share)

## ===========================================================================
## Section 10. CSS disaggregation and within-race/ethnicity ratios
## Discussion: "That excess was confined to the group's religious
## occupations, and the group fell to the null with them removed (eMethods).
## The elevation was present within every racial and ethnic group
## (eMethods)."
## ===========================================================================
banner("Section 10: CSS disaggregation and within-race ratios")
css <- css_pmr_summary(pmr_deaths)
add_pmr("pmr_directors_religious", css$table, "2050",
        "directors of religious activities and education")
add("pmr_directors_religious_rank",
    css$table$official_rank[css$table$occ == "2050"][1],
    note = "rank among occupations with >=100 deaths")
add_pmr("pmr_religious_other", css$table, "2060", "religious workers, all other")
add("pmr_religious_other_rank",
    css$table$official_rank[css$table$occ == "2060"][1],
    note = "rank among occupations with >=100 deaths")
add_pmr("pmr_counselors", css$table, "2001",
        "counselors (2018 codes 2001-2006 pooled)")
add_pmr("pmr_social_workers", css$table, "2011",
        "social workers (2018 codes 2011-2014 pooled)")
ga <- css$group_all
add("pmr_css_group", round(ga$pmr, 2), round(ga$lo, 2), round(ga$hi, 2),
    ga$observed, "community and social services group PMR")
ge <- css$group_excl
add("pmr_css_group_excl_clergy", round(ge$pmr, 2), round(ge$lo, 2),
    round(ge$hi, 2), ge$observed,
    "community and social services group PMR, excl. clergy-broad")
css_disaggregation_build(pmr_deaths)   # writes results/css_disaggregation.csv
# COVID-19 share of deaths by race, from the same records as the benchmark
# (origin: R/benchmark.R::covid_share_by_race + letter_numbers_build Part C;
# this repository has no persisted intermediates, so the identical
# quantities are computed directly; unknown race/ethnicity excluded).
sh <- pmr_deaths[pmr_deaths$raceeth != "unknown", ]
race_tab <- sh |>
  group_by(raceeth) |>
  summarise(ref_deaths = n(), ref_covid = sum(covid_underlying),
            .groups = "drop") |>
  left_join(sh[sh$occ == "2040", ] |>
              group_by(raceeth) |>
              summarise(clergy_deaths = n(),
                        clergy_covid = sum(covid_underlying), .groups = "drop"),
            by = "raceeth") |>
  mutate(clergy_pct = 100 * clergy_covid / clergy_deaths,
         ref_pct = 100 * ref_covid / ref_deaths,
         ratio = clergy_pct / ref_pct,
         suppressed = clergy_covid < SUPPRESS_UNDER) |>
  arrange(desc(clergy_deaths))
readr::write_csv(race_tab, "results/covid_share_by_race.csv")
for (nm in c(white = "nh_white", black = "nh_black", hispanic = "hispanic")) {
  lab <- names(which(c(white = "nh_white", black = "nh_black",
                       hispanic = "hispanic") == nm))
  row <- race_tab[race_tab$raceeth == nm, ][1, ]
  add(paste0("pmr_share_", lab), round(row$ratio, 2), n = row$clergy_deaths,
      note = sprintf("COVID share of deaths, clergy vs all employed, %s", nm))
}
part_c <- c(pmr_clergy_nhwhite = "nh_white", pmr_clergy_nhblack = "nh_black",
            pmr_clergy_hispanic = "hispanic")
for (nm in names(part_c)) {
  row <- race_tab[race_tab$raceeth == part_c[[nm]], ][1, ]
  obs <- row$clergy_covid
  expd <- row$clergy_deaths * row$ref_covid / row$ref_deaths
  stopifnot(abs(obs / expd - row$ratio) < 0.005)
  add(nm, round(obs / expd, 2),
      round(stats::qgamma(0.025, obs) / expd, 2),
      round(stats::qgamma(0.975, obs + 1) / expd, 2), obs,
      sprintf("within-%s COVID share ratio, clergy vs all employed, 2020-2021",
              part_c[[nm]]))
}

## ===========================================================================
## Section 11. Geography bound
## Discussion: "It was not explained by clergy's regional distribution
## (eMethods)."
##
## wonder_covid_region.csv is SHIPPED because CDC WONDER is interactive with
## data-use terms a person must accept. To regenerate (database: Underlying
## Cause of Death, 2018-2024, Single Race, wonder.cdc.gov), run FOUR queries,
## each grouped by Census Region, Ten-Year Age Groups (25-34..65-74), and
## Gender (the eMethods 6 table):
##   Query 1: year 2020, all states except AZ IA NC RI DC, all causes
##   Query 2: year 2020, same states, ICD-10 U07.1 (COVID-19)
##   Query 3: year 2021, all states except RI DC, all causes
##   Query 4: year 2021, same states, ICD-10 U07.1 (COVID-19)
## Combine into one table: year, region, age10, sex, total_deaths,
## covid_deaths (80 rows).
## ===========================================================================
banner("Section 11: geographic composition-only bound")
gv <- geo_bound_values(pmr_deaths)
if (is.null(gv)) {
  log_msg("STOP: wonder_covid_region.csv is missing; see the comment block above.")
  quit(status = 1)
}
add("pmr_geo_composition_only", round(unname(gv$main["clergy"]), 2),
    round(unname(gv$lo), 2), round(unname(gv$hi), 2), NA,
    "composition-only PMR: clergy regional/age/sex mix alone")
add("pmr_geo_composition_only_broad", round(unname(gv$main["clergy_broad"]), 2),
    NA, NA, NA, "composition-only PMR, clergy-broad")
add("pmr_geo_adjusted", round(gv$adj, 2), NA, NA, NA,
    "observed 1.94 / composition-only")
add("pmr_geo_region_only", round(unname(gv$region_only["clergy"]), 2),
    round(unname(gv$ro_lo), 2), round(unname(gv$ro_hi), 2), NA,
    "region-only composition ratio; SDR CI from replicate weights")
geo_out <- tibble::tibble(
  quantity = c("composition_only_pmr_clergy", "composition_only_pmr_clergy_broad",
               "composition_only_region_only_clergy",
               "observed_pmr_clergy", "geography_adjusted_pmr_clergy"),
  value = round(c(gv$main["clergy"], gv$main["clergy_broad"],
                  gv$region_only["clergy"], gv$cl$pmr, gv$adj), 3))
readr::write_csv(geo_out, "results/geo_bound.csv")

## ===========================================================================
## Section 12. The Figure
## "Standardized COVID-19 proportional mortality ratios, 2020-2021, for 450
## US occupations with >=100 deaths, ranked, with 95% CIs. Clergy (filled
## diamond) and reference occupations labeled. Ratio axis on log scale."
## ===========================================================================
banner("Section 12: the Figure")
letter_figure_build(pmr_deaths)   # results/figure1.pdf, figure1.png

## ===========================================================================
## Section 13. Verification against the shipped numbers.csv
## Every statistic recomputed above is compared, at its stored rounding, with
## the shipped numbers.csv. One PASS/FAIL line per statistic; any FAIL exits
## nonzero. If a statistic does not reproduce, report it - never adjust
## either side.
## ===========================================================================
banner("Section 13: verification against numbers.csv (108 statistics)")
shipped  <- readr::read_csv("numbers.csv", show_col_types = FALSE)
computed <- dplyr::bind_rows(ROWS)
stopifnot(!any(duplicated(computed$name)))
n_pass <- 0L; n_fail <- 0L
for (i in seq_len(nrow(shipped))) {
  s <- shipped[i, ]
  cc <- computed[computed$name == s$name, ]
  if (nrow(cc) != 1) {
    log_msg("FAIL  %-38s not computed by this script", s$name)
    n_fail <- n_fail + 1L
    next
  }
  ok <- near(s$value, cc$value) && near(s$lower, cc$lower) &&
    near(s$upper, cc$upper) && near(as.numeric(s$n), as.numeric(cc$n))
  if (ok) {
    n_pass <- n_pass + 1L
    log_msg("PASS  %-38s %s", s$name,
            paste(format(unlist(s[c("value", "lower", "upper", "n")])),
                  collapse = " "))
  } else {
    n_fail <- n_fail + 1L
    log_msg("FAIL  %-38s stored %s | computed %s", s$name,
            paste(format(unlist(s[c("value", "lower", "upper", "n")])),
                  collapse = " "),
            paste(format(unlist(cc[c("value", "lower", "upper", "n")])),
                  collapse = " "))
  }
}
extra <- setdiff(computed$name, shipped$name)
if (length(extra)) {
  n_fail <- n_fail + length(extra)
  log_msg("FAIL  computed statistics not in numbers.csv: %s",
          paste(extra, collapse = ", "))
}
readr::write_csv(computed, "results/numbers_computed.csv")
log_msg("%s", strrep("=", 72))
log_msg("VERIFICATION: %d/%d PASS, %d FAIL", n_pass, nrow(shipped), n_fail)
log_msg("%s", strrep("=", 72))
if (n_fail > 0) quit(status = 1)
