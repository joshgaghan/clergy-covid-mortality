#!/usr/bin/env Rscript
# 11_figures.R -- the manuscript's two figures, as revised. Figure 1: the
# 450-occupation ranked PMR plot with color-coded occupation categories and a
# key (the editor's instruction removed all in-panel text). Figure 2: Panel A,
# clergy against the full distribution of occupations under 4 benchmark
# specifications; Panel B, clergy-only forest (within 2021; by race and
# ethnicity, the stratified pooled-benchmark components). Writes
# results/figure1.{pdf,png} (OVERWRITING the letter's figure on this branch;
# the letter figure remains at tag submission-v1) and results/figure2.{pdf,png}.
# Guards: highlighted points resolve by label and must match the benchmark;
# Panel A strips must reproduce stored clergy rows; Panel B race rows carry
# the decomposition identity (the same-strata guard). Run after 02-08.
source("revision_lib.R")
suppressPackageStartupMessages({ library(ggplot2); library(tidyr) })

PALETTE <- c(clergy = "#D55E00", other_religious = "#E69F00",
             high_contact = "#0072B2", adjacent = "#009E73", other = "grey72")
LABELS <- c(clergy = "Clergy", other_religious = "Other religious occupations",
            high_contact = "High-contact comparison occupations",
            adjacent = "Occupations adjacent to clergy's work",
            other = "All other occupations")

main <- read_benchmark()
stopifnot(nrow(main) == 450)

## ---- Figure 1 -----------------------------------------------------------------
SPECS <- tibble::tribble(
  ~category,         ~short,                                  ~pattern,
  "clergy",          "Clergy",                                "^Clergy$",
  "other_religious", "Directors, religious activities",       "Directors, Religious",
  "other_religious", "Religious workers, all other",          "Religious Workers",
  "high_contact",    "Taxi drivers and chauffeurs",           "Taxi Drivers",
  "high_contact",    "EMTs and paramedics",                   "^Emergency Medical Technicians and Paramedics$",
  "high_contact",    "Bailiffs and correctional officers",    "Bailiffs|Correctional Officers, and Jailers",
  "high_contact",    "First-line supervisors of police",      "First-Line Supervisors of Police",
  "high_contact",    "Butchers and meat/poultry/fish processing", "Butchers and Other Meat",
  "adjacent",        "Physicians and surgeons",               "Physicians",
  "adjacent",        "Elementary and middle school teachers", "Elementary and Middle School Teachers",
  "adjacent",        "Counselors",                            "^Counselors$",
  "adjacent",        "Social workers",                        "Social Workers",
  "adjacent",        "Morticians, undertakers, funeral arrangers", "Mortician")
hi_rows <- list()
for (i in seq_len(nrow(SPECS))) {
  m <- main[grepl(SPECS$pattern[i], main$lab), ]
  if (nrow(m) != 1) stop_hard("label pattern '%s' matched %d rows", SPECS$pattern[i], nrow(m))
  hi_rows[[i]] <- m |> mutate(category = SPECS$category[i], short = SPECS$short[i])
}
hi <- bind_rows(hi_rows)
stopifnot(!any(duplicated(hi$occ)), hi$rank[hi$category == "clergy"] == 1)
readr::write_csv(hi |> select(occ, short, category, rank, observed, pmr, lo, hi),
                 "results/figure1_points.csv")

main$category <- "other"
main$category[match(hi$occ, main$occ)] <- hi$category
main$category <- factor(main$category, levels = names(PALETTE))
hp <- main[main$category != "other", ] |> arrange(rank)
# occlusion fix: the rank 4-15 highlighted points sit within a few ranks of
# each other; drawn at size 1.4 and spread to a minimum 5.5-rank gap
# (disclosed in the legend text of the manuscript)
hp$xpos <- hp$rank
hp$small <- hp$category != "clergy" & hp$rank <= 15
idx <- which(hp$small)
for (k in seq_along(idx)) {
  hp$xpos[idx[k]] <- if (k == 1) max(hp$rank[idx[k]], 3) else
    max(hp$rank[idx[k]], hp$xpos[idx[k - 1]] + 5.5)
}
p1 <- ggplot(main, aes(x = rank, y = pmr)) +
  geom_hline(yintercept = 1, linetype = "dashed", linewidth = 0.4, colour = "grey35") +
  geom_linerange(data = main[main$category == "other", ],
                 aes(ymin = lo, ymax = hi), colour = "grey82", linewidth = 0.28) +
  geom_point(data = main[main$category == "other", ], aes(fill = category),
             size = 0.55, shape = 21, colour = "grey40", stroke = 0.1) +
  geom_linerange(data = hp, aes(x = xpos, ymin = lo, ymax = hi, colour = category),
                 linewidth = 0.55) +
  geom_point(data = hp[hp$category != "clergy" & !hp$small, ],
             aes(fill = category), size = 2.0, shape = 21, colour = "grey15",
             stroke = 0.45) +
  geom_point(data = hp[hp$small, ], aes(x = xpos, fill = category), size = 1.4,
             shape = 21, colour = "grey15", stroke = 0.45) +
  geom_point(data = hp[hp$category == "clergy", ], aes(fill = category),
             size = 2.9, shape = 23, colour = "grey15", stroke = 0.6) +
  geom_linerange(data = hp[hp$category == "clergy", ],
                 aes(ymin = lo, ymax = hi), colour = "grey15", linewidth = 0.55) +
  scale_colour_manual(values = PALETTE, guide = "none") +
  scale_fill_manual(values = PALETTE, breaks = names(PALETTE), labels = LABELS,
                    name = NULL, drop = FALSE,
                    guide = guide_legend(nrow = 2, override.aes = list(
                      shape = c(23, 21, 21, 21, 21), size = c(2.9, 2, 2, 2, 1.1),
                      fill = unname(PALETTE),
                      colour = c(rep("grey15", 4), "grey40")))) +
  scale_y_continuous(trans = "log", breaks = c(0.25, 0.5, 1, 2),
                     labels = sprintf("%.2f", c(0.25, 0.5, 1, 2))) +
  labs(x = sprintf("Occupation, ranked by ratio (n = %d occupations with >=100 deaths)",
                   main$n_ranked[1]),
       y = "Standardized proportional mortality ratio (95% CI), log scale") +
  theme_bw(base_size = 9) +
  theme(panel.grid.minor = element_blank(), panel.grid.major.x = element_blank(),
        legend.position = "bottom", legend.box.margin = margin(t = -6),
        legend.text = element_text(size = 7.6), legend.key.size = unit(0.9, "lines"))
ggsave("results/figure1.pdf", p1, width = 6.8, height = 4.5, device = grDevices::pdf)
ggsave("results/figure1.png", p1, width = 6.8, height = 4.5, dpi = 300)
log_msg("wrote results/figure1.pdf/.png")

## ---- Figure 2 -----------------------------------------------------------------
set.seed(20261105)   # fixed jitter, as in the archival build
deaths <- rev_pmr_deaths()
num <- readr::read_csv("numbers.csv", show_col_types = FALSE)
g <- function(n) { r <- num[num$name == n, ]; stopifnot(nrow(r) == 1); r }
run_spec <- function(d, restriction = "all")
  pmr_by_occupation(d, strata = c("sex", "age5", "raceeth"),
                    cause_restriction = restriction, min_deaths = 100)
rd_u <- function(f) readr::read_csv(f, show_col_types = FALSE,
                                    col_types = cols(occ = col_character()))
specs <- list(
  `2020`                 = run_spec(deaths[deaths$year == 2020, ]),
  `2021`                 = run_spec(deaths[deaths$year == 2021, ]),
  `Pooled\nexcl.\nexternal` = rd_u("results/benchmark_strict_uniform.csv"),
  `Pooled excl.\nexternal, tobacco,\nalcohol` = rd_u("results/benchmark_natural_uniform.csv"))
chk2 <- function(tab, val, lo, hi, rank, digits = 2) {
  cl <- tab[tab$occ == CLERGY, ]
  tol <- 0.51 * 10^(-digits)
  stopifnot(abs(cl$pmr - val) <= tol, abs(cl$lo - lo) <= tol,
            abs(cl$hi - hi) <= tol, is.na(rank) || cl$rank == rank)
  cl
}
cl_rows <- list(
  chk2(specs[[1]], g("pmr_clergy_2020")$value, g("pmr_clergy_2020")$lower,
       g("pmr_clergy_2020")$upper, 2),
  chk2(specs[[2]], g("pmr_clergy_2021")$value, g("pmr_clergy_2021")$lower,
       g("pmr_clergy_2021")$upper, 1),
  chk2(specs[[3]], g("revision_pmr_clergy_natural_strict_raceadj")$value,
       g("revision_pmr_clergy_natural_strict_raceadj")$lower,
       g("revision_pmr_clergy_natural_strict_raceadj")$upper,
       g("revision_pmr_clergy_natural_strict_raceadj_rank")$value, digits = 4),
  chk2(specs[[4]], g("revision_pmr_clergy_natural_raceadj")$value,
       g("revision_pmr_clergy_natural_raceadj")$lower,
       g("revision_pmr_clergy_natural_raceadj")$upper,
       g("revision_pmr_clergy_natural_raceadj_rank")$value, digits = 4))
field <- bind_rows(lapply(seq_along(specs), function(i)
  specs[[i]] |> filter(occ != CLERGY) |>
    transmute(spec = names(specs)[i], pmr, above = pmr > cl_rows[[i]]$pmr)))
clA <- bind_rows(lapply(seq_along(specs), function(i)
  cl_rows[[i]] |> transmute(spec = names(specs)[i], pmr, lo, hi, rank, n_ranked)))
field$spec <- factor(field$spec, levels = names(specs))
clA$spec <- factor(clA$spec, levels = names(specs))
above <- field |> filter(above) |>
  mutate(xpos = as.numeric(spec) + 0.19 + runif(n(), -0.05, 0.05))
pa <- ggplot(field[!field$above, ], aes(x = spec, y = pmr)) +
  geom_hline(yintercept = 1, linetype = "dashed", linewidth = 0.4, colour = "grey35") +
  geom_jitter(width = 0.12, height = 0, size = 0.45, alpha = 0.25, colour = "grey40") +
  geom_linerange(data = clA, aes(ymin = lo, ymax = hi), colour = PALETTE[["clergy"]],
                 linewidth = 0.6) +
  geom_point(data = clA, shape = 23, size = 2.7, fill = PALETTE[["clergy"]],
             colour = "grey15", stroke = 0.6) +
  geom_point(data = above, aes(x = xpos, y = pmr), size = 0.8, alpha = 0.75,
             colour = "grey35") +
  scale_y_continuous(trans = "log", breaks = c(0.25, 0.5, 1, 2, 4),
                     labels = sprintf("%.2f", c(0.25, 0.5, 1, 2, 4))) +
  labs(x = "Benchmark specification",
       y = "Standardized proportional mortality ratio\n(95% CI), log scale") +
  theme_bw(base_size = 9) +
  theme(panel.grid.minor = element_blank(), panel.grid.major.x = element_blank(),
        axis.text.x = element_text(size = 6.3, lineheight = 0.9)) +
  ggtitle("A")

comp <- readr::read_csv("results/race_ratio_components.csv", show_col_types = FALSE)
pubb_cl <- main[main$occ == CLERGY, ]
stopifnot(abs(sum(comp$expected) - pubb_cl$expected) < 1e-9,
          sum(comp$obs) == pubb_cl$observed)   # same-strata guard, Panel B
rc <- comp |> filter(group != "unknown") |>
  transmute(race = group, pmr = ratio, lo, hi,
            row = c(hispanic = "Hispanic", nh_black = "Non-Hispanic Black",
                    nh_white = "Non-Hispanic White",
                    nh_other = "Non-Hispanic other")[race],
            grp = "By race and ethnicity")
MAYDEC <- "May-Dec 2021\n(after universal adult\nvaccine eligibility)"
b <- bind_rows(
  tibble::tibble(row = "Jan-Apr 2021", grp = "Within 2021",
                 pmr = g("pmr_clergy_2021_jan_apr")$value,
                 lo = g("pmr_clergy_2021_jan_apr")$lower,
                 hi = g("pmr_clergy_2021_jan_apr")$upper),
  tibble::tibble(row = MAYDEC, grp = "Within 2021",
                 pmr = g("pmr_clergy_2021_may_dec")$value,
                 lo = g("pmr_clergy_2021_may_dec")$lower,
                 hi = g("pmr_clergy_2021_may_dec")$upper),
  rc |> select(row, grp, pmr, lo, hi))
b$row <- factor(b$row, levels = rev(c("Jan-Apr 2021", MAYDEC, "Hispanic",
                                      "Non-Hispanic Black", "Non-Hispanic White",
                                      "Non-Hispanic other")))
b$grp <- factor(b$grp, levels = c("Within 2021", "By race and ethnicity"))
band <- g("pmr_clergy")
pb <- ggplot(b, aes(x = pmr, y = row)) +
  annotate("rect", ymin = -Inf, ymax = Inf, xmin = band$lower, xmax = band$upper,
           fill = PALETTE[["clergy"]], alpha = 0.13) +
  geom_vline(xintercept = band$value, colour = PALETTE[["clergy"]], alpha = 0.55,
             linewidth = 0.3) +
  geom_vline(xintercept = 1, linetype = "dashed", linewidth = 0.4, colour = "grey35") +
  geom_linerange(aes(xmin = lo, xmax = hi), colour = PALETTE[["clergy"]],
                 linewidth = 0.6) +
  geom_point(shape = 23, size = 2.7, fill = PALETTE[["clergy"]], colour = "grey15",
             stroke = 0.6) +
  facet_grid(grp ~ ., scales = "free_y", space = "free_y", switch = "y") +
  scale_x_continuous(trans = "log", breaks = c(1, 1.5, 2, 2.5),
                     labels = sprintf("%.2f", c(1, 1.5, 2, 2.5))) +
  labs(x = "Standardized proportional mortality ratio\n(95% CI), log scale", y = NULL) +
  theme_bw(base_size = 9) +
  theme(panel.grid.minor = element_blank(), panel.grid.major.y = element_blank(),
        strip.placement = "outside", strip.background = element_blank(),
        strip.text.y.left = element_text(angle = 90, size = 7.0, face = "bold"),
        panel.spacing.y = unit(0.5, "lines"),
        axis.text.y = element_text(size = 6.8, lineheight = 0.95)) +
  ggtitle("B")
suppressPackageStartupMessages(library(patchwork))
p2 <- pa + pb + plot_layout(widths = c(3.6, 3.4))
ggsave("results/figure2.pdf", p2, width = 7.0, height = 3.6, device = grDevices::pdf)
ggsave("results/figure2.png", p2, width = 7.0, height = 3.6, dpi = 300)
readr::write_csv(bind_rows(
  clA |> transmute(panel = "A", group = gsub("\n", " ", as.character(spec)),
                   pmr, lo, hi, rank, n_ranked),
  b |> transmute(panel = "B", group = gsub("\n", " ", as.character(row)),
                 pmr, lo, hi, rank = NA, n_ranked = NA)),
  "results/figure2_points.csv")
log_msg("wrote results/figure2.pdf/.png + figure2_points.csv")
