#!/usr/bin/env Rscript
# 06_misclassification.R -- eMethods 7 and eTable 3: the mixture bound on
# occupation misclassification. Derivation (on the expected-death scale):
# observed clergy decedents are a mixture of share (1-p) true clergy with
# proportional mortality PMR_true and share p misclassified decedents whose
# stratum-specific COVID-19 proportions equal the reference (PMR = 1), so
#   PMR_obs = (1-p) PMR_true + p   and   PMR_true = (PMR_obs - p)/(1 - p);
# inversion with true clergy at the null: R = (PMR_obs - (1-p))/p.
# A direct simulation mixes the reference stratum proportions into the
# observed clergy composition at p = 0.20 and recomputes the ratio through
# the full machinery. Appends REVISION_C2 rows; writes the grid and the
# simulation check under results/. Run after 02.
source("revision_lib.R")

pub <- read_benchmark()
cl <- pub[pub$occ == CLERGY, ]
rows <- list()

grid <- tibble::tibble(p = seq(0.05, 0.50, by = 0.05)) |>
  mutate(pmr_true = (cl$pmr - p) / (1 - p),
         lo_true = (cl$lo - p) / (1 - p),
         hi_true = (cl$hi - p) / (1 - p),
         note = "misclassified decedents assumed at the reference composition (PMR = 1); conservative - see derivation")
readr::write_csv(grid, "results/c2_misclassification_grid.csv")
inv <- tibble::tibble(p = c(0.1, 0.2, 0.3, 0.5)) |>
  mutate(required_R = (cl$pmr - (1 - p)) / p,
         note = "relative COVID-19 proportional mortality the misclassified fraction would need if true clergy were at the null")
readr::write_csv(inv, "results/c2_inversion_required_R.csv")
for (p in c(0.1, 0.2, 0.3, 0.5)) {
  gg <- grid[abs(grid$p - p) < 1e-9, ]
  tag <- sprintf("p%02.0f", 100 * p)
  rows[[length(rows) + 1L]] <- R6(sprintf("revision_misclass_pmr_true_%s", tag),
    round(gg$pmr_true, 4), round(gg$lo_true, 4), round(gg$hi_true, 4),
    note = sprintf("implied PMR among true clergy at misclassified fraction p = %.2f (mixture bound; eTable 3)", p),
    context = "REVISION_C2")
  rows[[length(rows) + 1L]] <- R6(sprintf("revision_misclass_required_R_%s", tag),
    round((cl$pmr - (1 - p)) / p, 4),
    note = sprintf("COVID-19 PMR the misclassified fraction would need for true clergy to be at the null, p = %.2f", p),
    context = "REVISION_C2")
  log_msg("p=%.2f: PMR_true %.2f (%.2f-%.2f); required R %.1f", p, gg$pmr_true,
          gg$lo_true, gg$hi_true, (cl$pmr - (1 - p)) / p)
}

# direct simulation at p = 0.20 on the actual strata (sex x age5 x raceeth)
deaths <- rev_pmr_deaths()
strata <- c("sex", "age5", "raceeth")
agg <- deaths |> group_by(across(all_of(c("occ", "lab", strata)))) |>
  summarise(.num = sum(covid_underlying), .den = n(), .groups = "drop")
ref <- agg |> group_by(across(all_of(strata))) |>
  summarise(.p = sum(.num) / sum(.den), .groups = "drop")
p_mix <- 0.2
agg_mix <- agg |> left_join(ref, by = strata)
cl_rows <- agg_mix$occ == CLERGY
agg_mix$.num[cl_rows] <- (1 - p_mix) * agg_mix$.num[cl_rows] +
  p_mix * agg_mix$.den[cl_rows] * agg_mix$.p[cl_rows]
exp_cl <- sum(agg_mix$.den[cl_rows] * agg_mix$.p[cl_rows])
pmr_fixedref <- sum(agg_mix$.num[cl_rows]) / exp_cl
pmr_full <- pmr_core(agg_mix |> select(-.p), strata, min_den = 100,
                     min_obs = SUPPRESS_UNDER)
pmr_fullref <- pmr_full$pmr[pmr_full$occ == CLERGY]
formula_val <- (1 - p_mix) * cl$pmr + p_mix
chk <- tibble::tibble(p = p_mix, formula = formula_val,
                      sim_fixed_reference = pmr_fixedref,
                      sim_full_recompute = pmr_fullref,
                      diff_fixed = pmr_fixedref - formula_val,
                      diff_full = pmr_fullref - formula_val)
readr::write_csv(chk, "results/c2_simulation_check.csv")
stopifnot(abs(chk$diff_fixed) < 1e-10, abs(chk$diff_full) < 0.01)
log_msg("simulation p=0.2: formula %.4f, fixed-ref %.4f (diff %.1e), full recompute %.4f (diff %.4f)",
        formula_val, pmr_fixedref, chk$diff_fixed, pmr_fullref, chk$diff_full)
rows[[length(rows) + 1L]] <- R6("revision_misclass_sim_diff_p20",
  round(abs(chk$diff_full), 4),
  note = "absolute difference between the mixture formula and a full-recompute simulation at p = 0.20 (reference re-pooled including the mixed clergy counts)",
  context = "REVISION_C2")

append_numbers(bind_rows(rows))
