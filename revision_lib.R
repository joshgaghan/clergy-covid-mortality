# revision_lib.R -- shared machinery for the revision scripts (03-12) and
# verify.R. Loads the DEFINITIONS of 02_analysis.R (everything above its
# "Section 2" banner: the verbatim letter machinery) without running the
# analysis sections, then adds the helpers the revision analyses share.
#
# The revision scripts append context-tagged rows to numbers.csv, mirroring
# the archival pipeline's convention: letter rows carry an empty context;
# every revision statistic carries the tag of the analysis family that
# produced it. Appends are idempotent (a script removes its own context's
# rows before re-appending), so any script can be rerun alone.
#
# # DECISIONS (dated)
# 2026-11-10  Definitions are loaded by parsing 02_analysis.R and evaluating
#             the expressions that END before its Section 2 banner. This
#             keeps the letter code in one place (nothing duplicated, nothing
#             rewritten) at the cost of a structural assumption that the
#             banner line "## Section 2. Groups and population" marks where
#             execution begins; the loader stops hard if the banner moves.
# 2026-11-10  Expensive shared inputs (the harmonized panels; the pooled
#             deaths frame) are cached under data/ (gitignored) so the
#             revision scripts do not rebuild them repeatedly. Caches carry
#             no analysis decisions: they are the direct output of the
#             02_analysis.R builder functions.

suppressPackageStartupMessages({
  library(readr); library(dplyr); library(tidyr); library(arrow)
})

source_defs <- function(path = "02_analysis.R") {
  lines <- readLines(path, warn = FALSE)
  marker <- grep("^## Section 2\\. Groups and population", lines)
  if (length(marker) != 1) stop("revision_lib: cannot find the Section 2 banner in 02_analysis.R", call. = FALSE)
  exprs <- parse(path, keep.source = TRUE)
  ends <- vapply(attr(exprs, "srcref"), function(r) as.integer(r[3]), 1L)
  for (e in exprs[ends < marker[1]]) eval(e, envir = globalenv())
  invisible(TRUE)
}
source_defs()

# revision measures for the harmonized machinery: deaths with COVID-19
# anywhere on the record, and non-COVID deaths (derived after the panel
# builds, because the panel carries the all_cause and covid19 columns)
HARM_MAP <- c(HARM_MAP, list(rr_covid_anywhere = list(measure = "covid_anywhere")))

CACHE <- function(name, builder) {
  f <- sprintf("data/_cache_%s.parquet", name)
  if (file.exists(f)) return(arrow::read_parquet(f))
  x <- builder()
  arrow::write_parquet(x, f)
  x
}
rev_pmr_deaths <- function() CACHE("pmr_deaths_2020_2021", function() build_pmr_deaths(c(2020, 2021)))
rev_harm <- local({
  memo <- NULL
  function() {
    if (!is.null(memo)) return(memo)
    dp <- CACHE("harm_deaths_panel", harm_deaths_panel)
    pp <- CACHE("harm_pop_panel", harm_pop_panel)
    dp$non_covid <- dp$all_cause - dp$covid19
    memo <<- list(dp = dp, pp = pp, W = harm_weights(pp))
    memo
  }
})

# band-set variant of harm_asr (the 25-44 rate ratio spans two 10-year bands)
harm_asr_bands <- function(deaths, pop, W, grp_name, bands, measure = "covid19") {
  d <- deaths[deaths$grp == grp_name & deaths$age10 %in% bands, ]
  p <- pop[pop$grp == grp_name & pop$age10 %in% bands, ]
  dd <- d |> group_by(age5, sex, raceeth) |>
    summarise(deaths = sum(.data[[measure]]), .groups = "drop")
  pp2 <- p |> group_by(age5, sex, raceeth) |>
    summarise(pop = sum(pop), .groups = "drop")
  cells <- pp2 |> left_join(dd, by = c("age5", "sex", "raceeth")) |>
    mutate(deaths = coalesce(deaths, 0)) |>
    inner_join(W, by = c("age5", "sex", "raceeth")) |>
    filter(pop > 0, w > 0)
  wn <- cells$w / sum(cells$w)
  new_asr(rate = sum(wn * cells$deaths / cells$pop) * PER,
          var = sum(wn^2 * cells$deaths / cells$pop^2) * PER^2,
          wmax = max(wn / cells$pop) * PER,
          deaths = as.integer(sum(cells$deaths)), pop = sum(cells$pop))
}

# the rank bootstrap of eMethods 6 (seed is set by the caller): Poisson draws
# on observed counts, expected fixed; optional subset rank from the same draws
boot_ranks <- function(tab, n_rep = 10000, subset = NULL) {
  cl_i <- which(tab$occ == CLERGY)
  stopifnot(length(cl_i) == 1, is.null(subset) || subset[cl_i])
  ranks <- integer(n_rep)
  ranks_sub <- if (is.null(subset)) NULL else integer(n_rep)
  for (r in seq_len(n_rep)) {
    p <- rpois(nrow(tab), tab$observed) / tab$expected
    ranks[r] <- 1L + sum(p > p[cl_i])
    if (!is.null(subset)) ranks_sub[r] <- 1L + sum(p[subset] > p[cl_i])
  }
  if (is.null(subset)) list(all = ranks) else list(all = ranks, sub = ranks_sub)
}

# idempotent context-tagged append to numbers.csv. Idempotency is by NAME
# (a rerun replaces its own rows and nothing else), because one context tag
# can span several scripts; `context` labels the rows being appended and each
# row may carry its own tag via a context column already present in `rows`.
append_numbers <- function(rows, context = NULL) {
  stopifnot(nrow(rows) > 0, !any(duplicated(rows$name)))
  if (!"context" %in% names(rows)) rows$context <- context
  stopifnot(!any(is.na(rows$context)))
  num <- readr::read_csv("numbers.csv", show_col_types = FALSE)
  if (!"context" %in% names(num)) num$context <- NA_character_
  num <- num |> filter(!(.data$name %in% rows$name))
  readr::write_csv(bind_rows(num, rows), "numbers.csv")
  log_msg("appended/replaced %d rows (%s); numbers.csv now %d rows",
          nrow(rows), paste(unique(rows$context), collapse = ", "),
          nrow(num) + nrow(rows))
}
R6 <- function(name, value, lower = NA_real_, upper = NA_real_, n = NA_integer_,
               note = "", context) {
  tibble::tibble(name = name, value = value, lower = lower, upper = upper,
                 n = as.integer(round(n)), note = note, context = context)
}

# the shipped pooled benchmark (written by 02_analysis.R section 6)
read_benchmark <- function() {
  f <- "results/pmr_benchmark.csv"
  if (!file.exists(f)) stop_hard("run 02_analysis.R first: %s is missing", f)
  readr::read_csv(f, show_col_types = FALSE, col_types = cols(occ = col_character()))
}
