#!/usr/bin/env Rscript
# 04_benchmarks.R -- eMethods 5: the cause-restricted benchmarks under the
# manuscript's uniform strata, the 2022-2024 period benchmark and its
# restrictions, and the within-group race and ethnicity ratios as the
# race-specific components of the pooled benchmark. Appends REVISION_STRATA,
# REVISION_AUDIT, and REVISION_RACE4 rows; persists per-occupation tables
# under results/. The hardcoded guards are deliberate (see README): if an
# estimate moves, the script halts rather than reproduce something other
# than the manuscript.
#
# # DECISIONS (dated)
# 2026-11-05  (archival pipeline) The originally submitted restriction values
#             (1.95; 1.75) were computed under sex x 5-year age strata only,
#             although eMethods 5 described the benchmark's full strata. The
#             revision recomputes both restrictions under sex x 5-year age x
#             race/ethnicity - the strata of every other estimate - and the
#             response letter reports the correction. CHANGES.md carries it.
# 2026-11-10  (archival pipeline, Job 0.1) The within-group race/ethnicity
#             ratios originally shipped as crude within-group share ratios;
#             they are recomputed here as the race-specific components of the
#             pooled benchmark (sex x 5-year age within group), which sum to
#             the pooled expected count. Recorded in CHANGES.md; the old
#             crude rows remain in the letter block of numbers.csv.
source("revision_lib.R")

deaths <- rev_pmr_deaths()
rows <- list()

# ---- cause-restricted benchmarks, uniform strata (REVISION_STRATA) ------------
strict <- pmr_by_occupation(deaths, strata = c("sex", "age5", "raceeth"),
                            cause_restriction = "strict_natural", min_deaths = 100)
natural <- pmr_by_occupation(deaths, strata = c("sex", "age5", "raceeth"),
                             cause_restriction = "natural", min_deaths = 100)
cs <- strict[strict$occ == CLERGY, ]; cn <- natural[natural$occ == CLERGY, ]
stopifnot(round(cs$pmr, 2) == 1.86, round(cs$lo, 2) == 1.79, round(cs$hi, 2) == 1.92,
          cs$rank == 1, cs$n_ranked[1] == 449,
          round(cn$pmr, 2) == 1.69, round(cn$lo, 2) == 1.63, round(cn$hi, 2) == 1.76,
          cn$rank == 1, cn$n_ranked[1] == 449)
log_msg("restrictions (uniform strata): strict %.4f (%.4f-%.4f) rank %d/449; natural %.4f (%.4f-%.4f) rank %d/449",
        cs$pmr, cs$lo, cs$hi, cs$rank, cn$pmr, cn$lo, cn$hi, cn$rank)
readr::write_csv(strict, "results/benchmark_strict_uniform.csv")
readr::write_csv(natural, "results/benchmark_natural_uniform.csv")
rows[[length(rows) + 1L]] <- R6("revision_pmr_clergy_natural_strict_raceadj",
  round(cs$pmr, 4), round(cs$lo, 4), round(cs$hi, 4), cs$observed,
  sprintf("clergy PMR excluding external causes, sex x 5-y age x race/ethnicity strata; rank %d of %d; supersedes the sex x age-only 1.95 for the revision (submitted row untouched)", cs$rank, cs$n_ranked[1]),
  "REVISION_STRATA")
rows[[length(rows) + 1L]] <- R6("revision_pmr_clergy_natural_raceadj",
  round(cn$pmr, 4), round(cn$lo, 4), round(cn$hi, 4), cn$observed,
  sprintf("clergy PMR excluding external, tobacco-related and alcohol-induced causes, sex x 5-y age x race/ethnicity strata; rank %d of %d; supersedes the sex x age-only 1.75 for the revision (submitted row untouched)", cn$rank, cn$n_ranked[1]),
  "REVISION_STRATA")
rows[[length(rows) + 1L]] <- R6("revision_pmr_clergy_natural_strict_raceadj_rank",
  cs$rank, n = cs$n_ranked[1],
  note = sprintf("rank among %d occupations (n in this row)", cs$n_ranked[1]),
  context = "REVISION_STRATA")
rows[[length(rows) + 1L]] <- R6("revision_pmr_clergy_natural_raceadj_rank",
  cn$rank, n = cn$n_ranked[1],
  note = sprintf("rank among %d occupations (n in this row)", cn$n_ranked[1]),
  context = "REVISION_STRATA")
# eTable 2's overlap count for the strict benchmark
ov_strict <- sum(strict$occ != CLERGY & strict$hi > cs$lo)
rows[[length(rows) + 1L]] <- R6("revision_audit_overlap_strict_25_74", ov_strict,
  n = cs$n_ranked[1],
  note = "occupations whose CI upper bound exceeds clergy's lower bound, pooled 25-74 excluding external causes (benchmark size in n)",
  context = "REVISION_AUDIT")
rows[[length(rows) + 1L]] <- R6("revision_audit_expected_strict_25_74",
  round(cs$expected, 1), n = cs$observed,
  note = "expected clergy COVID-19 deaths, pooled 25-74 benchmark excluding external causes (observed in n)",
  context = "REVISION_AUDIT")

# ---- 2022-2024 benchmark and restrictions (REVISION_AUDIT) --------------------
d2224 <- build_pmr_deaths(years = 2022:2024)
lbl <- c(all = "all causes", strict_natural = "excluding external causes",
         natural = "additionally excluding tobacco-related and alcohol-induced causes")
key <- c(all = "", strict_natural = "_exexternal", natural = "_exext_tob_alc")
for (restr in names(lbl)) {
  tab <- pmr_by_occupation(d2224, cause_restriction = restr)
  cl <- tab[tab$occ == CLERGY, ]
  if (restr == "all")
    stopifnot(round(cl$pmr, 2) == 1.59, round(cl$lo, 2) == 1.46,
              round(cl$hi, 2) == 1.73, cl$observed == 529, cl$denom_deaths == 12111)
  log_msg("2022-2024 (%s): %.4f (%.4f-%.4f); obs %d exp %.1f denom %d; rank %d of %d",
          restr, cl$pmr, cl$lo, cl$hi, cl$observed, cl$expected,
          cl$denom_deaths, cl$rank, cl$n_ranked[1])
  rows[[length(rows) + 1L]] <- R6(paste0("revision_audit_pmr_clergy_2022_2024", key[[restr]]),
    round(cl$pmr, 4), round(cl$lo, 4), round(cl$hi, 4), cl$observed,
    sprintf("clergy COVID-19 PMR 2022-2024, %s; expected %.1f; clergy denom deaths %d; rank %d of %d (same strata/floor machinery, floor within period)",
            lbl[[restr]], cl$expected, cl$denom_deaths, cl$rank, cl$n_ranked[1]),
    "REVISION_AUDIT")
}

# ---- within-group components of the pooled benchmark (REVISION_AUDIT) ---------
pub <- read_benchmark()
pooled_cl <- pub[pub$occ == CLERGY, ]
groups <- c("hispanic", "nh_black", "nh_white", "nh_other", "unknown")
comp <- bind_rows(lapply(groups, function(g) {
  d <- deaths[deaths$raceeth == g, ]
  ref <- d |> group_by(sex, age5) |>
    summarise(p = sum(covid_underlying) / n(), .groups = "drop")
  cl <- d[d$occ == CLERGY, ] |> group_by(sex, age5) |>
    summarise(n = n(), obs = sum(covid_underlying), .groups = "drop") |>
    left_join(ref, by = c("sex", "age5"))
  stopifnot(!any(is.na(cl$p)))
  obs <- sum(cl$obs); expd <- sum(cl$n * cl$p)
  tibble::tibble(group = g, clergy_deaths = sum(cl$n), obs = obs, expected = expd,
                 ratio = obs / expd,
                 lo = stats::qgamma(0.025, obs) / expd,
                 hi = stats::qgamma(0.975, obs + 1) / expd)
}))
# the decomposition identity: the same-strata guard for Figure 2B
stopifnot(abs(sum(comp$expected) - pooled_cl$expected) < 1e-9,
          sum(comp$obs) == pooled_cl$observed,
          abs(sum(comp$obs) / sum(comp$expected) - pooled_cl$pmr) < 1e-9)
log_msg("race components pool to %.4f; expected sums to %.4f (pooled benchmark row)",
        sum(comp$obs) / sum(comp$expected), sum(comp$expected))
readr::write_csv(comp, "results/race_ratio_components.csv")
nm4 <- c(hispanic = "pmr_clergy_hispanic_strat", nh_black = "pmr_clergy_nhblack_strat",
         nh_white = "pmr_clergy_nhwhite_strat", nh_other = "pmr_clergy_nhother_strat")
for (g in names(nm4)) {
  cw <- comp[comp$group == g, ]
  rows[[length(rows) + 1L]] <- R6(nm4[[g]],
    round(cw$ratio, 4), round(cw$lo, 4), round(cw$hi, 4), cw$obs,
    sprintf("within-%s clergy COVID-19 ratio as the pooled-benchmark component: sex x 5-y age strata within group, reference = all coded employed decedents of the group; expected %.1f, clergy deaths in group %d",
            g, cw$expected, cw$clergy_deaths),
    "REVISION_AUDIT")
}
# the crude nh_other row of the first-round response (REVISION_RACE4), from
# the shipped within-race share table, as in the archival pipeline
rc <- readr::read_csv("results/covid_share_by_race.csv", show_col_types = FALSE)
ro <- rc[rc$raceeth == "nh_other", ][1, ]
obs <- ro$clergy_covid; expd <- ro$clergy_deaths * ro$ref_covid / ro$ref_deaths
rows[[length(rows) + 1L]] <- R6("pmr_clergy_nhother",
  round(obs / expd, 2), round(stats::qgamma(0.025, obs) / expd, 2),
  round(stats::qgamma(0.975, obs + 1) / expd, 2), obs,
  "within-nh_other COVID share ratio, clergy vs all employed, 2020-2021 (crude within-group, as the three letter rows; superseded for the revision by pmr_clergy_nhother_strat)",
  "REVISION_RACE4")

append_numbers(bind_rows(rows))
