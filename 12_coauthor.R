#!/usr/bin/env Rscript
# 12_coauthor.R -- coauthor-requested checks (2026-11-16 memo; context
# REVISION_COAUTHOR). (1) The 2020-2021 benchmark under sex x 5-year age
# strata only, in all three cause specifications, with the submitted
# sex-x-age values (1.95; 1.75) and the sex x 10-year-age value (2.05)
# reproduced so their sources are on record; (2) graders and sorters of
# agricultural products across all six benchmarks; (3) meat processing by
# occupation (7810) and industry (1180) under the cause restrictions, with
# external-cause and alcohol-induced death shares; (4) the community and
# social services ratio among men 25-64 in 2021; the within-2021 period
# estimates by age group; the region-only composition ratio for 2021 alone.
# Also restores the eMethods 12 industry row (REVISION_IND), which the
# revision branch had omitted. No existing numbers.csv row changes.
# Run after 02-04:  Rscript 12_coauthor.R
source("revision_lib.R")
rows <- list()
deaths <- rev_pmr_deaths()
memo <- c("# Coauthor checks (2026-11-16): full-precision results", "")
say <- function(...) { line <- sprintf(...); log_msg("%s", line); memo <<- c(memo, line) }

## ---- 1. sex x 5-year-age-only benchmarks --------------------------------------
lbl <- c(all = "all causes", strict_natural = "excluding external causes",
         natural = "additionally excluding tobacco-related and alcohol-induced causes")
key <- c(all = "all", strict_natural = "exexternal", natural = "exext_tob_alc")
sexage5 <- list()
memo <- c(memo, "## 1. Benchmarks under sex x 5-year age strata only (2020-2021)", "")
for (restr in names(lbl)) {
  tab <- pmr_by_occupation(deaths, strata = c("sex", "age5"),
                           cause_restriction = restr, min_deaths = 100)
  sexage5[[restr]] <- tab
  cl <- tab[tab$occ == CLERGY, ]
  min100 <- tab[tab$observed >= 100, ] |> arrange(desc(pmr))
  rank100 <- which(min100$occ == CLERGY)
  say("%s: clergy %.7f (%.7f-%.7f); rank %d of %d; among the %d occupations with >=100 COVID-19 deaths, rank %d",
      lbl[[restr]], cl$pmr, cl$lo, cl$hi, cl$rank, cl$n_ranked[1],
      nrow(min100), rank100)
  t5 <- tab |> arrange(rank) |> head(5)
  for (i in seq_len(5))
    say("  rank %d: %s - %.7f (%.7f-%.7f); %d COVID-19 deaths", t5$rank[i],
        t5$lab[i], t5$pmr[i], t5$lo[i], t5$hi[i], t5$observed[i])
  rows[[length(rows) + 1L]] <- R6(
    sprintf("revision_coauthor_pmr_clergy_sexage5_%s", key[[restr]]),
    round(cl$pmr, 4), round(cl$lo, 4), round(cl$hi, 4), cl$observed,
    sprintf("clergy COVID-19 PMR 2020-2021, sex x 5-y age strata ONLY, %s; rank %d of %d (rank %d of %d among occupations with >=100 COVID-19 deaths); expected %.1f",
            lbl[[restr]], cl$rank, cl$n_ranked[1], rank100, nrow(min100), cl$expected),
    "REVISION_COAUTHOR")
}
# the submitted sex x age values must reproduce from these tables exactly
s_str <- sexage5[["strict_natural"]][sexage5[["strict_natural"]]$occ == CLERGY, ]
s_nat <- sexage5[["natural"]][sexage5[["natural"]]$occ == CLERGY, ]
stopifnot(round(s_str$pmr, 2) == 1.95, round(s_str$lo, 2) == 1.88,
          round(s_str$hi, 2) == 2.02, s_str$rank == 1,
          round(s_nat$pmr, 2) == 1.75, round(s_nat$lo, 2) == 1.69,
          round(s_nat$hi, 2) == 1.82, s_nat$rank == 2)
say("guard: the submitted sex x age restriction values reproduce (1.95 [1.88-2.02] rank 1; 1.75 [1.69-1.82] rank 2)")
# sex x 10-year age, all causes: the 2.05 (1.97-2.12) on record
t10 <- pmr_by_occupation(deaths, strata = c("sex", "age10"), min_deaths = 100)
c10 <- t10[t10$occ == CLERGY, ]
say("sex x 10-y age, all causes: clergy %.7f (%.7f-%.7f); rank %d of %d",
    c10$pmr, c10$lo, c10$hi, c10$rank, c10$n_ranked[1])
stopifnot(round(c10$pmr, 2) == 2.05, round(c10$lo, 2) == 1.97, round(c10$hi, 2) == 2.12)
rows[[length(rows) + 1L]] <- R6("revision_coauthor_pmr_clergy_sexage10_all",
  round(c10$pmr, 4), round(c10$lo, 4), round(c10$hi, 4), c10$observed,
  sprintf("clergy COVID-19 PMR 2020-2021, sex x 10-y age strata ONLY, all causes; rank %d of %d; the 2.05 (1.97-2.12) of the development record", c10$rank, c10$n_ranked[1]),
  "REVISION_COAUTHOR")

## ---- 2. graders and sorters of agricultural products ---------------------------
full <- list(all = read_benchmark(),
             strict_natural = readr::read_csv("results/benchmark_strict_uniform.csv",
               show_col_types = FALSE, col_types = cols(occ = col_character())),
             natural = readr::read_csv("results/benchmark_natural_uniform.csv",
               show_col_types = FALSE, col_types = cols(occ = col_character())))
gcode <- unique(full$all$occ[grepl("Graders and Sorters, Agricultural", full$all$lab)])
stopifnot(length(gcode) == 1)
memo <- c(memo, "", sprintf("## 2. Graders and sorters of agricultural products (analysis code %s)", gcode), "")
for (strat in c("full", "sexage5")) {
  for (restr in names(lbl)) {
    tab <- if (strat == "full") full[[restr]] else sexage5[[restr]]
    r <- tab[tab$occ == gcode, ]
    if (nrow(r) == 0) { say("%s strata, %s: below the 100-death floor", strat, lbl[[restr]]); next }
    say("%s strata, %s: %.7f (%.7f-%.7f); rank %d of %d; %d deaths, %d COVID-19",
        ifelse(strat == "full", "sex x age5 x race/ethnicity", "sex x age5 only"),
        lbl[[restr]], r$pmr, r$lo, r$hi, r$rank, r$n_ranked[1],
        r$denom_deaths, r$observed)
    rows[[length(rows) + 1L]] <- R6(
      sprintf("revision_coauthor_pmr_graders_%s_%s", strat, key[[restr]]),
      round(r$pmr, 4), round(r$lo, 4), round(r$hi, 4), r$observed,
      sprintf("graders and sorters of agricultural products (%s), 2020-2021, %s strata, %s; rank %d of %d; denom deaths %d",
              gcode, ifelse(strat == "full", "sex x age5 x race/ethnicity", "sex x age5 only"),
              lbl[[restr]], r$rank, r$n_ranked[1], r$denom_deaths),
      "REVISION_COAUTHOR")
  }
}

## ---- 3. meat processing: occupation 7810 and industry 1180 ---------------------
# industry frame with the same universe and cause flags as the occupation frame
build_ind_deaths <- function(years = c(2020, 2021)) {
  out <- list()
  for (y in years) {
    d <- arrow::read_parquet(sprintf("data/nvss_%d.parquet", y),
      col_select = c("resident_status", "age_years", "sex", "occ_code4",
                     "ind_code4", "cause_cat", "cancer_site", "hispanic_origin",
                     "race_recode_40", "icd10_underlying"))
    d <- d[d$resident_status != 4L, ]
    d <- d[!is.na(d$age_years) & d$age_years >= 25 & d$age_years <= 74, ]
    h <- harmonise_occ(d$occ_code4, unname(year_scheme()[as.character(y)]))
    d$occ_analysis <- h$analysis
    d <- d[!is.na(d$occ_analysis), ]
    d <- d[!d$occ_analysis %in% not_employed_codes(), ]
    is_lung <- !is.na(d$cancer_site) & d$cancer_site == "lung"
    is_external <- substr(d$icd10_underlying, 1, 1) %in% c("V", "W", "X", "Y") |
                   substr(d$icd10_underlying, 1, 3) == "U03"
    out[[length(out) + 1L]] <- tibble::tibble(
      occ = d$ind_code4, lab = NA_character_, occ_analysis = d$occ_analysis,
      sex = d$sex,
      age5 = as.character(cut(d$age_years, breaks = seq(25, 75, 5), right = FALSE)),
      raceeth = nvss_race_eth(d$hispanic_origin, d$race_recode_40),
      covid_underlying = d$cause_cat == "covid19",
      natural = !d$cause_cat %in% PMR_EXCLUDE_CAUSES & !is_lung,
      natural_strict = !is_external,
      alcohol = d$cause_cat == "alcohol_induced", year = y)
  }
  bind_rows(out)
}
ind <- build_ind_deaths()
IND <- "1180"
memo <- c(memo, "", "## 3. Meat processing: occupation 7810 and industry 1180", "")
for (restr in names(lbl)) {
  tocc <- if (restr == "all") full$all else full[[restr]]
  r <- tocc[tocc$occ == "7810", ]
  say("occupation 7810, full strata, %s: %.7f (%.7f-%.7f); rank %d of %d",
      lbl[[restr]], r$pmr, r$lo, r$hi, r$rank, r$n_ranked[1])
  if (restr != "all")
    rows[[length(rows) + 1L]] <- R6(
      sprintf("revision_coauthor_pmr_butchers_full_%s", key[[restr]]),
      round(r$pmr, 4), round(r$lo, 4), round(r$hi, 4), r$observed,
      sprintf("butchers and other meat/poultry/fish processing workers (7810), 2020-2021, full strata, %s; rank %d of %d", lbl[[restr]], r$rank, r$n_ranked[1]),
      "REVISION_COAUTHOR")
  tind <- pmr_by_occupation(ind |> select(-occ_analysis, -alcohol),
                            cause_restriction = restr)
  ri <- tind[!is.na(tind$occ) & tind$occ == IND, ]
  say("industry 1180, full strata, %s: %.7f (%.7f-%.7f); obs %d, denom %d",
      lbl[[restr]], ri$pmr, ri$lo, ri$hi, ri$observed, ri$denom_deaths)
  if (restr == "all") {
    # the eMethods 12 row, restored (REVISION_IND; omitted at the first cut)
    rows[[length(rows) + 1L]] <- R6("revision_ind_pmr_meat_processing",
      round(ri$pmr, 4), round(ri$lo, 4), round(ri$hi, 4), ri$observed,
      sprintf("COVID-19 PMR, animal slaughtering and processing INDUSTRY (census code 1180), 2020-2021, same strata; expected %.1f, denom %d", ri$expected, ri$denom_deaths),
      "REVISION_IND")
  } else {
    rows[[length(rows) + 1L]] <- R6(
      sprintf("revision_coauthor_pmr_meatind_full_%s", key[[restr]]),
      round(ri$pmr, 4), round(ri$lo, 4), round(ri$hi, 4), ri$observed,
      sprintf("animal slaughtering and processing industry (1180), 2020-2021, full strata, %s; denom %d", lbl[[restr]], ri$denom_deaths),
      "REVISION_COAUTHOR")
  }
}
# sex x age5 only, all causes, both units
r5occ <- sexage5[["all"]][sexage5[["all"]]$occ == "7810", ]
t5ind <- pmr_by_occupation(ind |> select(-occ_analysis, -alcohol),
                           strata = c("sex", "age5"))
r5ind <- t5ind[!is.na(t5ind$occ) & t5ind$occ == IND, ]
say("occupation 7810, sex x age5 only, all causes: %.7f (%.7f-%.7f); rank %d of %d",
    r5occ$pmr, r5occ$lo, r5occ$hi, r5occ$rank, r5occ$n_ranked[1])
say("industry 1180, sex x age5 only, all causes: %.7f (%.7f-%.7f)",
    r5ind$pmr, r5ind$lo, r5ind$hi)
rows[[length(rows) + 1L]] <- R6("revision_coauthor_pmr_butchers_sexage5_all",
  round(r5occ$pmr, 4), round(r5occ$lo, 4), round(r5occ$hi, 4), r5occ$observed,
  sprintf("butchers (7810), 2020-2021, sex x age5 strata only, all causes; rank %d of %d", r5occ$rank, r5occ$n_ranked[1]),
  "REVISION_COAUTHOR")
rows[[length(rows) + 1L]] <- R6("revision_coauthor_pmr_meatind_sexage5_all",
  round(r5ind$pmr, 4), round(r5ind$lo, 4), round(r5ind$hi, 4), r5ind$observed,
  "animal slaughtering and processing industry (1180), 2020-2021, sex x age5 strata only, all causes",
  "REVISION_COAUTHOR")
# death-composition shares: external and alcohol-induced
grp_share <- function(sel, label, nmkey) {
  n <- sum(sel); ext <- 100 * sum(!ind$natural_strict[sel]) / n
  alc <- 100 * sum(ind$alcohol[sel]) / n
  say("%s: %d deaths; external causes %.4f%%; alcohol-induced %.4f%%", label, n, ext, alc)
  rows[[length(rows) + 1L]] <<- R6(sprintf("revision_coauthor_share_external_%s", nmkey),
    round(ext, 2), n = n,
    note = sprintf("share (%%) of %s deaths 2020-2021 from external causes (V01-Y89, U03); deaths in n", label),
    context = "REVISION_COAUTHOR")
  rows[[length(rows) + 1L]] <<- R6(sprintf("revision_coauthor_share_alcohol_%s", nmkey),
    round(alc, 2), n = n,
    note = sprintf("share (%%) of %s deaths 2020-2021 from alcohol-induced underlying causes; deaths in n", label),
    context = "REVISION_COAUTHOR")
}
grp_share(ind$occ_analysis == "7810", "butcher-occupation (7810)", "butchers")
grp_share(!is.na(ind$occ) & ind$occ == IND, "meat-industry (1180)", "meatind")
grp_share(rep(TRUE, nrow(ind)), "all employed decedents", "allemp")

## ---- 4. checks -----------------------------------------------------------------
memo <- c(memo, "", "## 4. Checks", "")
# (a) community and social services, men 25-64, 2021
A5_young <- sort(unique(deaths$age5))
young <- A5_young[as.integer(sub("\\[(\\d+),.*", "\\1", A5_young)) < 65]
d_m <- deaths[deaths$year == 2021 & deaths$sex == "M" & deaths$age5 %in% young, ]
t_m <- pmr_by_occupation(d_m, strata = c("age5", "raceeth"),
                         min_deaths = 0, min_obs = 0)
css <- t_m[t_m$occ %in% CSS_CODES, ]
obs <- sum(css$observed); expd <- sum(css$expected)
say("(a) community and social services, men 25-64, 2021: %.7f (%.7f-%.7f); %d observed vs %.4f expected (Syamlal et al: 1.68, men 15-64)",
    obs / expd, qgamma(0.025, obs) / expd, qgamma(0.975, obs + 1) / expd, obs, expd)
rows[[length(rows) + 1L]] <- R6("revision_coauthor_pmr_css_men_25_64_2021",
  round(obs / expd, 4), round(qgamma(0.025, obs) / expd, 4),
  round(qgamma(0.975, obs + 1) / expd, 4), obs,
  sprintf("community and social services group COVID-19 PMR, men aged 25-64, 2021 (age5 x race/ethnicity strata within men; expected %.1f); comparator for Syamlal et al's 1.68 at ages 15-64", expd),
  "REVISION_COAUTHOR")
# (b) within-2021 periods by age group
d21m <- pmr_deaths_2021_by_month()
for (per in list(list(k = "jan_apr", m = 1:4, lab = "Jan-Apr 2021"),
                 list(k = "may_dec", m = 5:12, lab = "May-Dec 2021"))) {
  for (ag in list(list(k = "25_64", bands = young, lab = "ages 25-64"),
                  list(k = "65_74", bands = setdiff(A5_young, young), lab = "ages 65-74"))) {
    dd <- d21m[d21m$month %in% per$m & d21m$age5 %in% ag$bands, ]
    tab <- pmr_by_occupation(dd |> select(-month), min_deaths = 0, min_obs = 0)
    cl <- tab[tab$occ == CLERGY, ][1, ]
    say("(b) %s, %s: clergy %.7f (%.7f-%.7f); %d observed vs %.4f expected",
        per$lab, ag$lab, cl$pmr, cl$lo, cl$hi, cl$observed, cl$expected)
    rows[[length(rows) + 1L]] <- R6(
      sprintf("revision_coauthor_pmr_clergy_2021_%s_%s", per$k, ag$k),
      round(cl$pmr, 4), round(cl$lo, 4), round(cl$hi, 4), cl$observed,
      sprintf("clergy COVID-19 PMR, %s, %s (within-2021 machinery: clergy vs all employed, full strata, unfloored; expected %.1f)",
              per$lab, ag$lab, cl$expected),
      "REVISION_COAUTHOR")
  }
}
# (c) region-only composition ratio, 2021 alone
reps <- sprintf("PWGTP%d", 1:80)
w21 <- local({
  excl <- non_participating()[["2021"]]
  a <- arrow::read_parquet("data/acs_2021.parquet",
    col_select = c("state", "age", "sex", "occ_code4", "ESR",
                   "employed_civilian", "PWGTP", all_of(reps)))
  a <- a[a$age >= 25 & a$age <= 74, ]
  if (length(excl)) a <- a[!a$state %in% excl, ]
  a$occ_analysis <- harmonise_occ(a$occ_code4, "2018")$analysis
  a <- a[denominator_rule(a, "occp"), ]
  a$grp <- assign_group(a$occ_analysis)
  a$region <- unname(state_region()[a$state])
  a$age10 <- as.character(band_of(a$age))
  a |> mutate(gset = case_when(occ_analysis == "2040" ~ "clergy",
                               grp == "other_employed" ~ "other",
                               TRUE ~ NA_character_)) |>
    filter(!is.na(gset), !is.na(region), !is.na(age10)) |>
    group_by(gset, region, age10, sex) |>
    summarise(across(c("PWGTP", all_of(reps)), \(x) sum(as.numeric(x))),
              .groups = "drop")
})
won21 <- readr::read_csv(WONDER_CSV(), show_col_types = FALSE, comment = "#") |>
  mutate(sex = dplyr::recode(sex, Male = "M", Female = "F", .default = sex)) |>
  filter(year == 2021) |>
  group_by(region, age10, sex) |>
  summarise(total_deaths = sum(total_deaths), covid_deaths = sum(covid_deaths),
            .groups = "drop")
ro21 <- geo_ratio(w21, won21, "PWGTP", strata = "region")[["clergy"]]
rep_ro <- vapply(reps, function(rc) geo_ratio(w21, won21, rc, strata = "region")[["clergy"]], 0)
se <- sqrt(4 / 80 * sum((rep_ro - ro21)^2))
say("(c) region-only composition ratio, 2021 alone: %.7f (SDR 95%% CI, %.7f-%.7f)",
    ro21, ro21 - 1.96 * se, ro21 + 1.96 * se)
rows[[length(rows) + 1L]] <- R6("revision_coauthor_geo_region_only_2021",
  round(ro21, 4), round(ro21 - 1.96 * se, 4), round(ro21 + 1.96 * se, 4),
  note = "region-only composition ratio, 2021 alone (ACS 2021 weights, 2021 jurisdictions, WONDER 2021 rows; SDR CI from 80 replicate weights)",
  context = "REVISION_COAUTHOR")

append_numbers(bind_rows(rows))
writeLines(memo, "results/coauthor_checks_memo.md")
log_msg("wrote results/coauthor_checks_memo.md")
