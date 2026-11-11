#!/usr/bin/env Rscript
# 10_exhibits.R -- the manuscript's Table 1 (Original Investigation version)
# and the supplement's eTables 1-3, written as CSV and markdown under
# results/ with every cell guarded against numbers.csv or the persisted
# per-occupation tables. (The submitted .docx exhibits are generated from
# these same values in the archival pipeline; this repository ships the
# cell values and layout, not Word files.) Run after 02-09.
source("revision_lib.R")
num <- readr::read_csv("numbers.csv", show_col_types = FALSE)
g <- function(nm) { r <- num[num$name == nm, ]; stopifnot(nrow(r) == 1); r }
fmt <- function(v, lo, hi) sprintf("%.2f (%.2f-%.2f)", v, lo, hi)

# ---- Table 1: harmonized rates at 2 decimals, guarded --------------------------
# Rates are recomputed through the harmonized machinery at full precision and
# guarded against the stored rows (ratios at 2 dp; the letter's rate rows at
# 1 dp where they exist); counts are the race-known deaths entering the rates.
H <- rev_harm(); dp <- H$dp; pp <- H$pp; W <- H$W
SPEC <- tibble::tribble(
  ~base,                   ~label,                                      ~guard,
  "allcause",              "All causes",                                "rr_allcause_harm",
  "drug",                  "Drug poisoning",                            "rr_drug_harm",
  "alcohol",               "Alcohol-induced causes",                    "rr_alcohol_harm",
  "suicide",               "Suicide",                                   "rr_suicide_harm",
  "covid_underlying",      "COVID-19, 2020-2024",                       "rr_covid_underlying_harm",
  "covid_2020_2021",       "COVID-19, 2020-2021",                       "rr_covid_2020_2021_harm",
  "covid_2022_2024",       "COVID-19, 2022-2024",                       "rr_covid_2022_2024_harm",
  "covid_age_25_44",       "COVID-19, ages 25-44 y",                    "revision_pop_rr_covid_age_25_44",
  "covid_age_45_54",       "COVID-19, ages 45-54 y",                    "rr_covid_age_45_54_harm",
  "covid_age_55_64",       "COVID-19, ages 55-64 y",                    "rr_covid_age_55_64_harm",
  "covid_age_65_74",       "COVID-19, ages 65-74 y",                    "rr_covid_age_65_74_harm",
  "obesity_covid_cert",    "Obesity mentioned, COVID-19 on certificate", "rr_obesity_covid_cert_harm",
  "obesity_noncovid_cert", "Obesity mentioned, COVID-19 not on certificate", "rr_obesity_noncovid_cert_harm")
tab <- list(); vals <- list()
for (i in seq_len(nrow(SPEC))) {
  b <- SPEC$base[i]
  if (b == "covid_age_25_44") {
    a <- harm_asr_bands(dp, pp, W, "clergy", c("25-34", "35-44"))
    o <- harm_asr_bands(dp, pp, W, "other_employed", c("25-34", "35-44"))
  } else {
    spec <- HARM_MAP[[paste0("rr_", b)]]
    years <- if (is.null(spec$years)) YEARS else spec$years
    a <- harm_asr(dp, pp, W, "clergy", spec$measure, years, spec$age10)
    o <- harm_asr(dp, pp, W, "other_employed", spec$measure, years, spec$age10)
  }
  rr <- rate_ratio(a, o); cia <- fay_feuer(a); cio <- fay_feuer(o)
  sr <- g(SPEC$guard[i])
  stopifnot(abs(round(unname(rr[["rr"]]), 2) - sr$value) < 1e-9,
            abs(round(unname(rr[["lower"]]), 2) - sr$lower) < 1e-9,
            abs(round(unname(rr[["upper"]]), 2) - sr$upper) < 1e-9,
            a$deaths == sr$n)
  tab[[i]] <- tibble::tibble(
    Cause = SPEC$label[i],
    `Clergy deaths, No.` = format(a$deaths, big.mark = ","),
    `Clergy rate per 100,000 (95% CI)` =
      sprintf("%.2f (%.2f-%.2f)", a$rate, cia[["lower"]], cia[["upper"]]),
    `Other employed rate per 100,000 (95% CI)` =
      sprintf("%.2f (%.2f-%.2f)", o$rate, cio[["lower"]], cio[["upper"]]),
    `Rate ratio (95% CI)` =
      sprintf("%.2f (%.2f-%.2f)", rr[["rr"]], rr[["lower"]], rr[["upper"]]))
  rrv <- unname(rr[["rr"]]); rrl <- unname(rr[["lower"]]); rrh <- unname(rr[["upper"]])
  vals[[i]] <- tibble::tibble(base = b, clergy_deaths = a$deaths,
    clergy_rate = a$rate, clergy_rate_lo = unname(cia[["lower"]]),
    clergy_rate_hi = unname(cia[["upper"]]), other_rate = o$rate,
    other_rate_lo = unname(cio[["lower"]]), other_rate_hi = unname(cio[["upper"]]),
    rr = rrv, rr_lo = rrl, rr_hi = rrh)
  log_msg("  %-46s guard OK; RR %.2f", SPEC$label[i], rr[["rr"]])
}
tab <- bind_rows(tab)
readr::write_csv(bind_rows(vals), "results/table1_oi_values.csv")
foot <- paste("Ages 25-74 years, 2020-2024 unless a period or age range is stated.",
  "Counts are the deaths entering the standardized rates; rates per 100,000",
  "person-years and rate ratios are directly standardized by sex, age, and race",
  "and ethnicity to the 2000 US standard population and exclude records with",
  "unknown race or ethnicity (14 of 23,234 clergy deaths, 2020-2024).",
  "Non-Hispanic other comprises non-Hispanic American Indian and Alaska Native,",
  "Asian, multiple-race, and Native Hawaiian and Other Pacific Islander",
  "decedents. 95% CIs by the Fay-Feuer method. Denominators are American",
  "Community Survey respondents reporting an occupation, restricted to",
  "jurisdictions reporting occupation data. The drug poisoning and suicide",
  "rows share intentional drug poisonings and are not mutually exclusive.")
hdr <- paste0("| ", paste(names(tab), collapse = " | "), " |")
sep <- paste0("|", paste(rep("---", ncol(tab)), collapse = "|"), "|")
body <- apply(tab, 1, function(r) paste0("| ", paste(r, collapse = " | "), " |"))
writeLines(c("# Table 1. Standardized Mortality Rates and Rate Ratios Among US Clergy vs Other Employed Adults Aged 25-74 Years, United States, 2020-2024",
             "", hdr, sep, body, "", foot), "results/table1_OI.md")
log_msg("wrote results/table1_OI.md + table1_oi_values.csv")

# ---- eTable 1: top 15 ----------------------------------------------------------
pub <- read_benchmark()
t15 <- pub |> arrange(rank) |> head(15)
stopifnot(t15$occ[1] == CLERGY, round(t15$pmr[1], 2) == 1.94)
readr::write_csv(t15 |> transmute(rank, occupation = lab, covid_deaths = observed,
                                  pmr = round(pmr, 4), lo = round(lo, 4),
                                  hi = round(hi, 4)),
                 "results/etable1.csv")

# ---- eTable 2: alternative age ranges ------------------------------------------
et <- readr::read_csv("results/etable_retire.csv", show_col_types = FALSE)
su <- readr::read_csv("results/benchmark_strict_uniform.csv", show_col_types = FALSE,
                      col_types = cols(occ = col_character()))
cs <- su[su$occ == CLERGY, ]
pc <- pub[pub$occ == CLERGY, ]
e2 <- bind_rows(
  et |> transmute(age_range = window, causes = restriction,
                  observed, expected, pmr = clergy_pmr, lo, hi,
                  rank = sprintf("1 of %d", n_occupations),
                  overlap = as.character(ci_overlap_count)),
  tibble::tibble(age_range = "25-74", causes = "all causes",
                 observed = pc$observed, expected = round(pc$expected, 1),
                 pmr = round(pc$pmr, 4), lo = round(pc$lo, 4), hi = round(pc$hi, 4),
                 rank = "1 of 450",
                 overlap = as.character(g("revision_rank_overlap_count")$value)),
  tibble::tibble(age_range = "25-74", causes = "excluding external",
                 observed = cs$observed, expected = round(cs$expected, 1),
                 pmr = round(cs$pmr, 4), lo = round(cs$lo, 4), hi = round(cs$hi, 4),
                 rank = "1 of 449",
                 overlap = as.character(g("revision_audit_overlap_strict_25_74")$value)),
  tibble::tibble(age_range = "25-84", causes = "all causes",
                 observed = g("revision_agecap_pmr_clergy_25_84")$n,
                 expected = g("revision_agecap_expected_25_84")$value,
                 pmr = g("revision_agecap_pmr_clergy_25_84")$value,
                 lo = g("revision_agecap_pmr_clergy_25_84")$lower,
                 hi = g("revision_agecap_pmr_clergy_25_84")$upper,
                 rank = "Not ranked", overlap = "Not computed"))
readr::write_csv(e2, "results/etable2.csv")

# ---- eTable 3: misclassification grid ------------------------------------------
gr <- readr::read_csv("results/c2_misclassification_grid.csv", show_col_types = FALSE)
e3 <- gr |> filter(round(p, 2) %in% c(0.10, 0.20, 0.30, 0.50)) |>
  transmute(p, implied_pmr_true = fmt(pmr_true, lo_true, hi_true),
            required_R = round((pc$pmr - (1 - p)) / p, 1))
readr::write_csv(e3, "results/etable3.csv")
log_msg("wrote results/etable1-3.csv")
