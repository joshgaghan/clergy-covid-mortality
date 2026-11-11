#!/usr/bin/env Rscript
# 07_education.R -- eMethods 8 and the eFigure: the education calibration of
# the clergy label. For every benchmark occupation, the graduate/professional
# share of 2020-2021 decedents (certificate, 2003-revision item) against the
# ACS-weighted share among its workers (same ages, years, jurisdictions);
# the attenuation log odds ratio (empirical logits with a 0.5 continuity
# correction); and, as eMethods 8 discloses, the two earlier specifications:
# the superseded linear fit (clergy at the 14th percentile of residuals) and
# the abandoned death-weighted logit fit (coefficients reported, no rows).
# GUARD: the machinery must reproduce the published education-agreement
# values (clergy 35.6/49.7; physicians 89.5/100.0; 2020-2024) exactly before
# the 2020-2021 calibration runs. Appends REVISION_EDU and SUPERSEDED_EDU
# rows; writes the panel, the age-band table, and the eFigure. Run after 02.
source("revision_lib.R")
suppressPackageStartupMessages(library(ggplot2))
PHYS <- "3065"
band10_of <- function(a) as.character(band_of(a))

deaths_grad <- function(years) {
  rows <- list()
  for (y in years) {
    d <- arrow::read_parquet(sprintf("data/nvss_%d.parquet", y),
      col_select = c("resident_status", "age_years", "occ_code4",
                     "educ_2003", "educ_flag"))
    d <- d[d$resident_status != 4L & !is.na(d$age_years) &
             d$age_years >= 25 & d$age_years <= 74, ]
    d$occ <- harmonise_occ(d$occ_code4, unname(year_scheme()[as.character(y)]))$analysis
    d <- d[!is.na(d$occ) & !is.na(d$educ_flag) & d$educ_flag == 1L &
             !is.na(d$educ_2003) & d$educ_2003 %in% 1:8, ]
    d$grad <- d$educ_2003 %in% 7:8
    d$band <- band10_of(d$age_years)
    rows[[length(rows) + 1L]] <- d |> group_by(occ, band) |>
      summarise(n = n(), n_grad = sum(grad), .groups = "drop")
  }
  bind_rows(rows) |> group_by(occ, band) |>
    summarise(n = sum(n), n_grad = sum(n_grad), .groups = "drop")
}
acs_grad <- function(years) {
  np <- non_participating()
  rows <- list()
  for (y in years) {
    excl <- np[[as.character(y)]]
    for (s in ACS_FOR[[as.character(y)]]) {
      a <- arrow::read_parquet(sprintf("data/acs_%d.parquet", s),
        col_select = c("state", "age", "occ_code4", "ESR", "employed_civilian",
                       "SCHL", "PWGTP"))
      a <- a[a$age >= 25 & a$age <= 74, ]
      if (length(excl)) a <- a[!a$state %in% excl, ]
      a$occ_analysis <- harmonise_occ(a$occ_code4, "2018")$analysis
      a <- a[denominator_rule(a, "occp"), ]
      a <- a[!is.na(a$SCHL), ]
      a$grad <- a$SCHL >= 22L
      a$band <- band10_of(a$age)
      rows[[length(rows) + 1L]] <- a |>
        group_by(occ = occ_analysis, band) |>
        summarise(w = sum(as.numeric(PWGTP)),
                  w_grad = sum(as.numeric(PWGTP)[grad]), .groups = "drop")
      rm(a); gc(verbose = FALSE)
    }
    log_msg("  acs %d done", y)
  }
  bind_rows(rows) |> group_by(occ, band) |>
    summarise(w = sum(w), w_grad = sum(w_grad), .groups = "drop")
}

# ---- GUARD: the published 2020-2024 education-agreement values ---------------
dg_all <- deaths_grad(YEARS); ag_all <- acs_grad(YEARS)
gshare <- function(tab, codes, wcol, gcol) {
  s <- tab[tab$occ %in% codes, ]
  100 * sum(s[[gcol]]) / sum(s[[wcol]])
}
g_cl_d <- gshare(dg_all, CLERGY, "n", "n_grad")
g_cl_a <- gshare(ag_all, CLERGY, "w", "w_grad")
g_ph_d <- gshare(dg_all, PHYS, "n", "n_grad")
g_ph_a <- gshare(ag_all, PHYS, "w", "w_grad")
stopifnot(sprintf("%.1f", g_cl_d) == "35.6", sprintf("%.1f", g_cl_a) == "49.7",
          sprintf("%.1f", g_ph_d) == "89.5", sprintf("%.1f", g_ph_a) == "100.0")
log_msg("guard passed: clergy %.1f/%.1f, physicians %.1f/%.1f (published values)",
        g_cl_d, g_cl_a, g_ph_d, g_ph_a)

# ---- the calibration panel, 2020-2021 ----------------------------------------
bench <- read_benchmark()
dg <- deaths_grad(c(2020, 2021)); ag <- acs_grad(c(2020, 2021))
occ_tab <- dg |> group_by(occ) |>
  summarise(n = sum(n), n_grad = sum(n_grad), .groups = "drop") |>
  inner_join(ag |> group_by(occ) |>
               summarise(w = sum(w), w_grad = sum(w_grad), .groups = "drop"),
             by = "occ") |>
  filter(occ %in% bench$occ) |>
  mutate(cert_share = 100 * n_grad / n, acs_share = 100 * w_grad / w,
         lab = bench$lab[match(occ, bench$occ)],
         el_cert = log((n_grad + 0.5) / (n - n_grad + 0.5)),
         el_acs  = log((w_grad + 0.5) / (w - w_grad + 0.5)),
         att     = el_cert - el_acs)
stopifnot(nrow(occ_tab) == 436)   # 14 benchmark codes lack an ACS counterpart
cl <- occ_tab[occ_tab$occ == CLERGY, ]; ph <- occ_tab[occ_tab$occ == PHYS, ]
att_med <- median(occ_tab$att); att_q <- quantile(occ_tab$att, c(0.25, 0.75))
pct_all <- 100 * mean(occ_tab$att < cl$att)
band2 <- occ_tab |> filter(acs_share >= 35, acs_share <= 65)
band_med <- median(band2$att)
pct_band <- 100 * mean(band2$att < cl$att)
rank_band <- sum(band2$att <= cl$att)
log_msg("attenuation: median %.3f IQR [%.3f, %.3f]; clergy %.4f pct %.1f/%d; band (n=%d) median %.3f, clergy rank %d",
        att_med, att_q[1], att_q[2], cl$att, pct_all, nrow(occ_tab),
        nrow(band2), band_med, rank_band)
if (pct_all < 10 || pct_band < 10)
  stop_hard("STOP (pre-set rule): clergy attenuation below the 10th percentile (overall %.1f; band %.1f)",
            pct_all, pct_band)

# age-band table (the 15-26 pp statement)
band_tab <- function(codes, label) {
  d <- dg |> filter(occ %in% codes) |> group_by(band) |>
    summarise(cert_share = 100 * sum(n_grad) / sum(n), n = sum(n), .groups = "drop")
  a <- ag |> filter(occ %in% codes) |> group_by(band) |>
    summarise(acs_share = 100 * sum(w_grad) / sum(w), .groups = "drop")
  full_join(d, a, by = "band") |> mutate(group = label)
}
med_tab <- {
  pob <- dg |> inner_join(ag, by = c("occ", "band")) |>
    filter(occ %in% bench$occ, n >= 20) |>
    mutate(cert_share = 100 * n_grad / n, acs_share = 100 * w_grad / w)
  pob |> group_by(band) |>
    summarise(cert_share = median(cert_share), acs_share = median(acs_share),
              n = NA_integer_, .groups = "drop") |>
    mutate(group = "all-occupation median (occs with >=20 band deaths)")
}
bands <- bind_rows(band_tab(CLERGY, "clergy"), band_tab(PHYS, "physicians"),
                   med_tab) |> arrange(group, band)
bands$n <- ifelse(!is.na(bands$n) & bands$n < SUPPRESS_UNDER, NA, bands$n)
readr::write_csv(bands, "results/edu_calibration_bands.csv")
cb <- bands[bands$group == "clergy", ]
log_msg("clergy band gaps (pp): %s",
        paste(sprintf("%s %.1f", cb$band, cb$acs_share - cb$cert_share), collapse = "; "))
readr::write_csv(occ_tab |> select(occ, lab, n, n_grad, w, w_grad, cert_share,
                                   acs_share, el_cert, el_acs, att),
                 "results/edu_calibration_occupations.csv")

# ---- the two earlier specifications eMethods 8 discloses ----------------------
fit_lin <- lm(cert_share ~ acs_share, data = occ_tab)
res_lin <- residuals(fit_lin)
lin_resid <- unname(res_lin[occ_tab$occ == CLERGY])
lin_pct <- 100 * mean(res_lin < res_lin[occ_tab$occ == CLERGY])
fit_logit <- lm(el_cert ~ el_acs, data = occ_tab, weights = n)
log_msg("superseded linear fit: clergy residual %+.4f pp, percentile %.2f (threshold set in advance: 10th)",
        lin_resid, lin_pct)
log_msg("abandoned logit fit (disclosed, no rows): intercept %.4f, slope %.4f - dominated by boundary and mass-death occupations; ran below most of the data",
        coef(fit_logit)[1], coef(fit_logit)[2])

# ---- appends -------------------------------------------------------------------
rows <- list(
  R6("revision_edu_clergy_cert_share_2020_2021", round(cl$cert_share, 4), n = cl$n,
     note = "graduate/professional share of clergy decedents 2020-2021 (certificate, education-agreement conventions)",
     context = "REVISION_EDU"),
  R6("revision_edu_clergy_acs_share_2020_2021", round(cl$acs_share, 4),
     note = "ACS-weighted graduate/professional share among clergy workers 2020-2021",
     context = "REVISION_EDU"),
  R6("revision_edu_attenuation_median", round(att_med, 4),
     round(att_q[[1]], 4), round(att_q[[2]], 4), nrow(occ_tab),
     "median attenuation log OR (empirical logit certificate minus empirical logit ACS) across benchmark occupations (n in this row); lower/upper are the IQR, not a CI",
     "REVISION_EDU"),
  R6("revision_edu_clergy_attenuation", round(cl$att, 4),
     note = "clergy attenuation log OR (certificate vs ACS)", context = "REVISION_EDU"),
  R6("revision_edu_clergy_attenuation_percentile", round(pct_all, 2), n = nrow(occ_tab),
     note = "percentile of clergy attenuation among benchmark occupations (n in this row); higher = less attenuated",
     context = "REVISION_EDU"),
  R6("revision_edu_physicians_attenuation", round(ph$att, 4),
     note = "physicians attenuation log OR; ACS share at the 100% boundary, so the value is an artifact of the continuity correction and not informative",
     context = "REVISION_EDU"),
  R6("revision_edu_band_median_attenuation", round(band_med, 4), n = nrow(band2),
     note = "median attenuation log OR among occupations with ACS graduate share 35-65% (count in n)",
     context = "REVISION_EDU"),
  R6("revision_edu_clergy_band_rank", rank_band, n = nrow(band2),
     note = sprintf("clergy rank within the 35-65%% ACS-share band, 1 = most attenuated (band percentile %.1f; band count in n)", pct_band),
     context = "REVISION_EDU"),
  R6("revision_edu_clergy_residual_pp", round(lin_resid, 4),
     note = "clergy residual from the cross-occupation calibration line (cert ~ ACS, OLS, 436 occupations); superseded by the attenuation log OR 2026-11-06",
     context = "SUPERSEDED_EDU"),
  R6("revision_edu_clergy_residual_percentile", round(lin_pct, 2), n = nrow(occ_tab),
     note = "percentile of clergy residual among benchmark occupations (n in this row); linear fit, superseded by the attenuation log OR 2026-11-06",
     context = "SUPERSEDED_EDU"))
append_numbers(bind_rows(rows))

# ---- the eFigure ---------------------------------------------------------------
hi <- occ_tab |> filter(occ %in% c(CLERGY, PHYS))
pe <- ggplot(occ_tab, aes(x = acs_share, y = cert_share)) +
  geom_abline(linetype = "dashed", linewidth = 0.4, colour = "grey45") +
  geom_point(size = 0.9, alpha = 0.35, colour = "grey40") +
  geom_point(data = hi[hi$occ != CLERGY, ], shape = 21, size = 2.4,
             fill = "#009E73", colour = "grey15", stroke = 0.6) +
  geom_point(data = hi[hi$occ == CLERGY, ], shape = 23, size = 2.9,
             fill = "#D55E00", colour = "grey15", stroke = 0.6) +
  scale_x_continuous(limits = c(0, 100)) + scale_y_continuous(limits = c(0, 100)) +
  labs(x = "Graduate or professional degree among workers, ACS (%)",
       y = "Graduate or professional degree among decedents, certificate (%)") +
  theme_bw(base_size = 9) + theme(panel.grid.minor = element_blank())
ggsave("results/efigure_edu_calibration.pdf", pe, width = 5.2, height = 5.0,
       device = grDevices::pdf)
ggsave("results/efigure_edu_calibration.png", pe, width = 5.2, height = 5.0, dpi = 300)
log_msg("wrote results/efigure_edu_calibration.pdf/.png")
