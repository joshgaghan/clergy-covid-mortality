#!/usr/bin/env Rscript
# 05_rank_bootstrap.R -- eMethods 6: uncertainty in the rank of clergy.
# Parametric bootstrap (each occupation's observed COVID-19 count drawn
# Poisson around its observed value, expected counts fixed; 10,000
# replicates, seed 20261106), on the pooled 2020-2021 benchmark and the
# 2020-only benchmark, overall and among occupations with at least 100
# observed COVID-19 deaths; the CI-overlap set; the lowest ranks drawn.
# Appends REVISION_RANK and REVISION_AUDIT rows. Run after 02 and 04.
source("revision_lib.R")
SEED <- 20261106; N_REP <- 10000
rows <- list()

pooled <- read_benchmark()
cl <- pooled[pooled$occ == CLERGY, ]
overlap <- pooled |> filter(occ != CLERGY, hi > cl$lo) |> arrange(desc(pmr))
stopifnot(nrow(overlap) == 6)   # the six small-count occupations of eMethods 6
readr::write_csv(overlap |> select(occ, lab, observed, expected, pmr, lo, hi, rank),
                 "results/rank_overlap_occupations.csv")
log_msg("CI-overlap occupations (hi > clergy lo %.4f): %d; deaths %d-%d",
        cl$lo, nrow(overlap), min(overlap$observed), max(overlap$observed))
rows[[length(rows) + 1L]] <- R6("revision_rank_overlap_count", nrow(overlap),
  n = nrow(pooled),
  note = sprintf("occupations (excluding clergy) whose 95%% CI upper bound exceeds clergy's lower bound %.4f, pooled 2020-2021 benchmark (benchmark size in n)", cl$lo),
  context = "REVISION_RANK")

min100 <- pooled$observed >= 100
set.seed(SEED)
bk <- boot_ranks(pooled, N_REP, subset = min100)
p1 <- mean(bk$all == 1); p3 <- mean(bk$all <= 3)
p1m <- mean(bk$sub == 1); p3m <- mean(bk$sub <= 3)
stopifnot(round(p1, 4) == 0.7812, round(p3, 4) == 0.9989)  # eMethods 6 guard
log_msg("pooled: P(rank1) %.4f P(top3) %.4f; among %d >=100-obs occs %.4f/%.4f; worst %d",
        p1, p3, sum(min100), p1m, p3m, max(bk$all))
rows[[length(rows) + 1L]] <- R6("revision_rank_p_rank1_pooled", round(p1, 4), n = N_REP,
  note = sprintf("parametric bootstrap P(clergy ranks 1), pooled 2020-2021 benchmark; Poisson draws on observed counts, expected fixed; seed %d (replicates in n)", SEED),
  context = "REVISION_RANK")
rows[[length(rows) + 1L]] <- R6("revision_rank_p_rank3_pooled", round(p3, 4), n = N_REP,
  note = "parametric bootstrap P(clergy ranks in top 3), pooled 2020-2021 benchmark; same draws",
  context = "REVISION_RANK")
rows[[length(rows) + 1L]] <- R6("revision_rank_p_rank1_pooled_min100obs", round(p1m, 4),
  n = sum(min100),
  note = "parametric bootstrap P(clergy ranks 1) among occupations with >=100 observed COVID-19 deaths, pooled 2020-2021; same draws and seed (count of such occupations in n)",
  context = "REVISION_RANK")
rows[[length(rows) + 1L]] <- R6("revision_rank_p_rank3_pooled_min100obs", round(p3m, 4),
  n = sum(min100),
  note = "parametric bootstrap P(clergy ranks in top 3) among occupations with >=100 observed COVID-19 deaths, pooled 2020-2021; same draws (count in n)",
  context = "REVISION_RANK")
rows[[length(rows) + 1L]] <- R6("revision_audit_boot_worst_rank_pooled", max(bk$all),
  n = N_REP,
  note = sprintf("lowest clergy rank drawn in the pooled-benchmark parametric bootstrap (seed %d; replicates in n)", SEED),
  context = "REVISION_AUDIT")

# 2020-only benchmark
deaths <- rev_pmr_deaths()
t2020 <- pmr_by_occupation(deaths[deaths$year == 2020, ])
c20 <- t2020[t2020$occ == CLERGY, ]
stopifnot(round(c20$pmr, 2) == 1.79, c20$rank == 2, c20$n_ranked[1] == 363)
set.seed(SEED)
b20 <- boot_ranks(t2020, N_REP)
p1_20 <- mean(b20$all == 1); p2_20 <- mean(b20$all <= 2)
log_msg("2020: P(rank1) %.4f P(top2) %.4f; worst %d", p1_20, p2_20, max(b20$all))
rows[[length(rows) + 1L]] <- R6("revision_rank_p_rank1_2020", round(p1_20, 4), n = N_REP,
  note = "parametric bootstrap P(clergy ranks 1), 2020-only benchmark (363 occupations); same method and seed",
  context = "REVISION_RANK")
rows[[length(rows) + 1L]] <- R6("revision_rank_p_rank2_2020", round(p2_20, 4), n = N_REP,
  note = "parametric bootstrap P(clergy ranks in top 2), 2020-only benchmark; same draws",
  context = "REVISION_RANK")
rows[[length(rows) + 1L]] <- R6("revision_audit_boot_worst_rank_2020", max(b20$all),
  n = N_REP,
  note = "lowest clergy rank drawn in the 2020-benchmark parametric bootstrap (same seed)",
  context = "REVISION_AUDIT")

append_numbers(bind_rows(rows))
