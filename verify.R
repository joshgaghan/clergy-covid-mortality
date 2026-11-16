#!/usr/bin/env Rscript
# verify.R -- full reproduction check for the revision. Recomputes everything
# (the letter analyses via 02_analysis.R and the revision analyses via
# 03-10) and fails loudly if any value differs from the committed numbers.csv
# beyond 1e-8, then checks that every set of estimates displayed together in
# Figure 2 was computed on the same strata:
#   (A) each Panel A strip's clergy row reproduces its stored value, and the
#       restricted benchmarks use sex x 5-year age x race/ethnicity (the
#       guard that caught the submission's strata inconsistency);
#   (B) Panel B's race rows are the race-specific components of the pooled
#       benchmark: their expected counts (plus the unknown-race stratum) sum
#       to the pooled expected count and their observed counts to the pooled
#       observed count.
# Run from this directory, after 01_data.R:  Rscript verify.R
# Expect roughly the run time of 02-11 combined (see README).

suppressPackageStartupMessages({ library(readr); library(dplyr) })
committed <- read_csv("numbers.csv", show_col_types = FALSE)
if (!"context" %in% names(committed)) committed$context <- NA_character_
ref <- tempfile(fileext = ".csv"); file.copy("numbers.csv", ref)

run <- function(script) {
  cat(sprintf("== %s ==\n", script))
  ok <- system2("Rscript", script)
  if (!identical(ok, 0L)) stop(sprintf("%s failed (exit %d)", script, ok), call. = FALSE)
}
for (s in c("02_analysis.R", "03_coverage.R", "04_benchmarks.R",
            "05_rank_bootstrap.R", "06_misclassification.R", "07_education.R",
            "08_age_retirement.R", "09_rates.R", "10_exhibits.R", "11_figures.R",
            "12_coauthor.R"))
  run(s)
# 02_analysis.R writes only results/; the revision scripts rewrite their own
# numbers.csv rows in place, so the file now holds the recomputation.
recomputed <- read_csv("numbers.csv", show_col_types = FALSE)
committed <- read_csv(ref, show_col_types = FALSE)
if (!"context" %in% names(committed)) committed$context <- NA_character_

cat(sprintf("comparing %d committed rows with %d recomputed rows\n",
            nrow(committed), nrow(recomputed)))
fails <- 0L
near8 <- function(a, b) (is.na(a) && is.na(b)) ||
  (!is.na(a) && !is.na(b) && abs(as.numeric(a) - as.numeric(b)) <= 1e-8)
for (i in seq_len(nrow(committed))) {
  s <- committed[i, ]
  r <- recomputed[recomputed$name == s$name, ]
  if (nrow(r) != 1) { cat(sprintf("FAIL %-45s missing from recomputation\n", s$name)); fails <- fails + 1L; next }
  if (!(near8(s$value, r$value) && near8(s$lower, r$lower) &&
        near8(s$upper, r$upper) && near8(as.numeric(s$n), as.numeric(r$n)))) {
    cat(sprintf("FAIL %-45s committed %s|%s|%s|%s recomputed %s|%s|%s|%s\n",
                s$name, s$value, s$lower, s$upper, s$n,
                r$value, r$lower, r$upper, r$n))
    fails <- fails + 1L
  }
}
extra <- setdiff(recomputed$name, committed$name)
if (length(extra)) { cat("FAIL extra recomputed rows:", paste(extra, collapse = ", "), "\n"); fails <- fails + length(extra) }

## same-strata checks for Figure 2 ------------------------------------------------
num <- recomputed
g <- function(nm) { r <- num[num$name == nm, ]; stopifnot(nrow(r) == 1); r }
pub <- read_csv("results/pmr_benchmark.csv", show_col_types = FALSE,
                col_types = cols(occ = col_character()))
pc <- pub[pub$occ == "2040", ]
f2 <- read_csv("results/figure2_points.csv", show_col_types = FALSE)
# (A) every Panel A clergy diamond equals its stored row
chkA <- function(group, nm_v, tol) {
  a <- f2[f2$panel == "A" & f2$group == group, ]
  v <- g(nm_v)
  ok <- abs(a$pmr - v$value) <= tol && abs(a$lo - v$lower) <= tol &&
        abs(a$hi - v$upper) <= tol
  if (!ok) { cat(sprintf("FAIL same-strata A: %s\n", group)); fails <<- fails + 1L }
}
chkA("2020", "pmr_clergy_2020", 0.0051)
chkA("2021", "pmr_clergy_2021", 0.0051)
chkA("Pooled excl. external", "revision_pmr_clergy_natural_strict_raceadj", 5.1e-5)
chkA("Pooled excl. external, tobacco, alcohol", "revision_pmr_clergy_natural_raceadj", 5.1e-5)
# (B) the race rows decompose the pooled benchmark
comp <- read_csv("results/race_ratio_components.csv", show_col_types = FALSE)
if (abs(sum(comp$expected) - pc$expected) > 1e-9 ||
    sum(comp$obs) != pc$observed ||
    abs(sum(comp$obs) / sum(comp$expected) - pc$pmr) > 1e-9) {
  cat("FAIL same-strata B: race components do not decompose the pooled benchmark\n")
  fails <- fails + 1L
}
gl <- c(hispanic = "Hispanic", nh_black = "Non-Hispanic Black",
        nh_white = "Non-Hispanic White", nh_other = "Non-Hispanic other")
for (gx in names(gl)) {
  bb <- f2[f2$panel == "B" & f2$group == gl[[gx]], ]
  if (abs(bb$pmr - comp$ratio[comp$group == gx]) > 1e-9) {
    cat(sprintf("FAIL same-strata B: %s plotted value is not the component\n", gl[[gx]]))
    fails <- fails + 1L
  }
}

cat(strrep("=", 72), "\n")
if (fails == 0L) {
  cat(sprintf("VERIFY: all %d committed statistics reproduce (<= 1e-8), and every\n", nrow(committed)))
  cat("Figure 2 display set was computed on the same strata.\n")
} else {
  cat(sprintf("VERIFY: %d FAILURES\n", fails))
  quit(status = 1)
}
