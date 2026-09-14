#!/usr/bin/env Rscript
# 01_data.R -- download and parse the public data behind the research letter
# "COVID-19 Mortality Among US Clergy, 2020-2024".
#
# Companion repository to the full analysis pipeline (tag jamaim-v3); the code
# here is EXTRACTED from that repository, not reimplemented. Origin of every
# function is noted at its definition. Run from this directory:
#     Rscript 01_data.R      (then Rscript 02_analysis.R)
#
# Inputs : NVSS multiple cause-of-death zips 2020-2024 (NCHS) and ACS 1-year
#          PUMS person files 2019, 2021-2024 (Census). ~3.6 GB of downloads.
# Outputs: data/nvss_{2020..2024}.parquet, data/acs_{2019,2021..2024}.parquet.
# Ends with the 2020 NCHS control-total canary (four published counts).
#
# Package versions when the acceptance run was recorded (see README.md):
#   R 4.5.1; readr 2.1.5; dplyr 1.1.4; tidyr 1.3.1; arrow 21.0.0.1; ggplot2 4.0.0
#
# # DECISIONS (dated; also see 02_analysis.R)
# 2026-09-14  Superseding build for the submitted letter: extraction baseline
#             is the full repository at tag jamaim-v3 (108 statistics).
#             month_of_death added to every layout and parsed in the main
#             pass (positions 65-66, verified in each year's layout PDF by
#             the full repository), because the submitted analyses split
#             2021 at April 30.
# 2026-08-28  SHA-256 is computed by shelling out to shasum -a 256 (base R has
#             no SHA-256 and the openssl package is not on the allowed list);
#             if no shasum/sha256sum tool exists the check is skipped with a
#             warning.
# 2026-08-28  NVSS zips use Deflate64, which R's internal unzip() rejects as
#             corrupt; extraction shells out to /usr/bin/unzip, as in the full
#             pipeline (its decisions.md, 2026-08-25).
# 2026-08-28  Plumbing-only YAML configs of the full repo are carried here as
#             hardcoded constants with their values copied verbatim: the
#             occupation-code scheme by year (config/layouts/*.yaml,
#             occupation_code_scheme) and the supplemental not-employed codes,
#             which are derived from occ_crosswalk.csv mapping_kind rather than
#             occ_groups.yaml. This keeps the repo YAML-free; no statistic
#             depends on code not extracted verbatim.

suppressPackageStartupMessages({
  library(readr); library(dplyr); library(arrow)
})

log_msg  <- function(...) { cat(sprintf(...), "\n", sep = ""); flush.console() }
stop_hard <- function(...) stop(sprintf(...), call. = FALSE)

YEARS     <- 2020:2024                      # NVSS data years
ACS_YEARS <- c(2019, 2021, 2022, 2023, 2024) # 2020 1-year PUMS is experimental;
                                             # 2019 exists only to average with
                                             # 2021 for the 2020 denominator
dir.create("data/raw", recursive = TRUE, showWarnings = FALSE)

## ---- 1. Download ----------------------------------------------------------
# URLs as in the full repository's R/01_download.R (verified 2026-08 against
# the NCHS mortality data page and the Census PUMS directory).
NVSS_BASE <- "https://ftp.cdc.gov/pub/Health_Statistics/NCHS/Datasets/DVS/mortality"
ACS_BASE  <- "https://www2.census.gov/programs-surveys/acs/data/pums"
downloads <- rbind(
  data.frame(url  = sprintf("%s/mort%dus.zip", NVSS_BASE, YEARS),
             dest = sprintf("mort%dus.zip", YEARS)),
  data.frame(url  = sprintf("%s/%d/1-Year/csv_pus.zip", ACS_BASE, ACS_YEARS),
             dest = sprintf("acs_pus_%d.zip", ACS_YEARS)))

# Expected SHA-256, copied from the Phase 1 record (full repo,
# data/raw/checksums.tsv). NCHS revises files in place, so a mismatch warns
# but does not stop.
EXPECTED_SHA256 <- c(
  mort2020us.zip   = "e9b0e551e6e5e47acd36f2df7ccbf686ae22db9e3d3aa03a0009dd5998d21bf4",
  mort2021us.zip   = "4666c46c615ef0926908f2f60593cec85faaea962bb1bc3030bbd211fded6550",
  mort2022us.zip   = "ed56fc2403746dcdff19e3d5e61ea43fa23ffb92c16de26f0d1e2fb5a8cea4d2",
  mort2023us.zip   = "d181d0e12fea6b2f7f3138f0426f829b890d6dc8d6626ff37a032ffc87fc932d",
  mort2024us.zip   = "7f61a343a5c014d66cb028425cb2b849d96af9156abf0b6d054a7cb23ee630e2",
  acs_pus_2019.zip = "18e4ece4cc24781c01e8046c2d5afbabeb1f15452ddec43f60fdf3b1f6e67b92",
  acs_pus_2021.zip = "e1e64f81718e7d478cf2bf4ad8d1ae1fa03c690f6c86afa3984d1a6bd38dc8f2",
  acs_pus_2022.zip = "687a97773d0fdfec6c624ea6bf48466f12059d3ee80283a2ad8604ea7a66231e",
  acs_pus_2023.zip = "98b6ecb14b4830d1f2b54c265a5bd997828415c2dab14e17369c40e98b78d9d4",
  acs_pus_2024.zip = "afdc6d90c6e2f0bab365ed32d95ba4c4d8ac651162f46ac7861295b2dc469894")

sha256_file <- function(path) {
  tool <- Sys.which(c("shasum", "sha256sum"))
  tool <- tool[nzchar(tool)][1]
  if (is.na(tool)) return(NA_character_)
  args <- if (grepl("shasum$", tool)) c("-a", "256", shQuote(path)) else shQuote(path)
  strsplit(system2(tool, args, stdout = TRUE)[1], "\\s+")[[1]][1]
}

old_timeout <- getOption("timeout"); options(timeout = 3600)
for (i in seq_len(nrow(downloads))) {
  dest <- file.path("data", "raw", downloads$dest[i])
  if (file.exists(dest) && file.size(dest) > 1e6) {
    log_msg("skip (present): %s  %s bytes", basename(dest),
            format(file.size(dest), big.mark = ","))
  } else {
    log_msg("GET %s", downloads$url[i])
    status <- tryCatch(download.file(downloads$url[i], dest, mode = "wb",
                                     quiet = TRUE),
                       error = function(e) conditionMessage(e))
    if (!identical(status, 0L)) stop_hard("download failed for %s: %s",
                                          downloads$url[i], status)
  }
  digest <- sha256_file(dest)
  want <- EXPECTED_SHA256[[basename(dest)]]
  if (is.na(digest)) {
    log_msg("  sha256: no shasum/sha256sum tool found; check SKIPPED")
  } else if (identical(digest, want)) {
    log_msg("  sha256 %s...  MATCHES the Phase 1 record", substr(digest, 1, 16))
  } else {
    log_msg("  sha256 %s...  WARNING: differs from the Phase 1 record %s...;",
            substr(digest, 1, 16), substr(want, 1, 16))
    log_msg("  continuing -- NCHS revises public-use files in place. If the")
    log_msg("  control-total canary at the end of this script still passes,")
    log_msg("  the revision did not touch the fields this letter uses.")
  }
}
options(timeout = old_timeout)

## ---- 2. Cause-of-death rules (from cause_groups.csv) ----------------------
# Matching machinery copied VERBATIM from the full repository's R/causes.R
# (which reads the same definitions from config/cause_groups.yaml; here they
# are flattened into cause_groups.csv so this repo needs no YAML package).

rules_tbl <- readr::read_csv("cause_groups.csv", comment = "#",
                             col_types = "cicicc", progress = FALSE)
rules_of <- function(section) {
  x <- rules_tbl[rules_tbl$section == section, ]
  x <- x[order(x$ord), ]
  lapply(seq_len(nrow(x)), function(i) list(
    key = x$key[i], priority = x$priority[i],
    catch_all = isTRUE(x$catch_all[i]),
    blocks = if (is.na(x$blocks[i]) || !nzchar(x$blocks[i])) NULL else
      strsplit(x$blocks[i], ";", fixed = TRUE)[[1]],
    codes = if (is.na(x$codes[i]) || !nzchar(x$codes[i])) NULL else
      strsplit(x$codes[i], ";", fixed = TRUE)[[1]]))
}
exclusive_rules    <- function() {          # ordered by priority, as in causes.R
  r <- rules_of("underlying_exclusive")
  r[order(vapply(r, function(x) as.numeric(x$priority), 0))]
}
cancer_site_rules  <- function() rules_of("cancer_sites")
indicator_rules    <- function() rules_of("indicators")
contributing_rules <- function() rules_of("contributing_flags")

# -- from R/causes.R, verbatim ----------------------------------------------
expand_blocks <- function(blocks) {
  if (!length(blocks)) return(character(0))
  out <- unlist(lapply(blocks, function(spec) {
    parts <- strsplit(spec, "-", fixed = TRUE)[[1]]
    lo <- parts[1]; hi <- if (length(parts) > 1) parts[2] else parts[1]
    lo_l <- substr(lo, 1, 1); lo_n <- as.integer(substr(lo, 2, 3))
    hi_l <- substr(hi, 1, 1); hi_n <- as.integer(substr(hi, 2, 3))
    letters_seq <- LETTERS[which(LETTERS == lo_l):which(LETTERS == hi_l)]
    unlist(lapply(letters_seq, function(L) {
      first <- if (L == lo_l) lo_n else 0L
      last  <- if (L == hi_l) hi_n else 99L
      sprintf("%s%02d", L, first:last)
    }))
  }), use.names = FALSE)
  unique(out)
}
norm_code <- function(x) {
  x <- toupper(trimws(as.character(x)))
  gsub(".", "", x, fixed = TRUE)
}
rule_match <- function(code, rule) {
  if (isTRUE(rule$catch_all)) return(rep(TRUE, length(code)))
  hit <- rep(FALSE, length(code))
  blocks <- expand_blocks(rule$blocks)
  if (length(blocks)) hit <- hit | (substr(code, 1, 3) %in% blocks)
  if (length(rule$codes)) hit <- hit | (code %in% norm_code(unlist(rule$codes)))
  hit
}
classify_causes <- function(code) {
  code <- norm_code(code)
  out <- rep(NA_character_, length(code))
  for (r in exclusive_rules()) {
    todo <- is.na(out)
    if (!any(todo)) break
    hit <- rule_match(code[todo], r)
    out[which(todo)[hit]] <- r$key
  }
  out[is.na(out)] <- "all_other"
  out
}
cancer_site <- function(code, cause_cat) {
  code <- norm_code(code)
  out <- rep(NA_character_, length(code))
  is_ca <- !is.na(cause_cat) & cause_cat == "cancer"
  if (!any(is_ca)) return(out)
  sub <- rep(NA_character_, sum(is_ca))
  cc <- code[is_ca]
  for (r in cancer_site_rules()) {
    todo <- is.na(sub)
    if (!any(todo)) break
    hit <- rule_match(cc[todo], r)
    sub[which(todo)[hit]] <- r$key
  }
  sub[is.na(sub)] <- "other_cancer"
  out[is_ca] <- sub
  out
}
contributing_flag <- function(record_axis_raw, rule, n_slots = 20L, slot_w = 5L) {
  hit <- rep(FALSE, length(record_axis_raw))
  for (i in seq_len(n_slots) - 1L) {
    slot <- norm_code(substr(record_axis_raw, i * slot_w + 1L, i * slot_w + 4L))
    hit <- hit | (nzchar(slot) & rule_match(slot, rule))
  }
  hit
}

## ---- 3. Parse NVSS (adapted from R/parse_nvss.R) --------------------------
# Fields the letter needs, and nothing else: resident_status, sex, age_detail,
# data_year, month_of_death (the submitted analyses split 2021 by month; it
# is parsed here for every year, which removes any need for the record-order
# re-read used in the full repository), icd10_underlying, hispanic_origin,
# race_recode_40, occ_code4, record_axis_raw (the 20 multiple-condition
# slots). Positions come from layouts/nvss_{year}.csv; nothing here
# hardcodes a position.

RECORD_LEN <- 817L

parse_nvss_year <- function(year) {
  out <- sprintf("data/nvss_%d.parquet", year)
  if (file.exists(out)) { log_msg("  skip %d: %s exists", year, out); return(invisible()) }
  t0 <- Sys.time()
  lay <- readr::read_csv(sprintf("layouts/nvss_%d.csv", year), comment = "#",
                         col_types = "ciic", progress = FALSE)
  zip <- sprintf("data/raw/mort%dus.zip", year)
  txt <- sprintf("data/mort%dus.txt", year)
  if (!file.exists(txt)) {   # Deflate64: shell out to unzip (see DECISIONS)
    log_msg("  extracting %s", basename(zip))
    ok <- system2("unzip", c("-p", shQuote(zip)), stdout = txt, stderr = FALSE)
    if (!identical(ok, 0L) || file.size(txt) == 0) stop_hard("unzip failed for %s", zip)
  }
  # Each record is 817 bytes plus CRLF; assert before trusting fixed widths.
  sz <- file.size(txt)
  if (sz %% (RECORD_LEN + 2L) != 0)
    stop_hard("%d: %s bytes is not a multiple of %d", year, sz, RECORD_LEN + 2L)
  expected_n <- sz %/% (RECORD_LEN + 2L)
  log_msg("  parsing %d (%s records expected) ...", year,
          format(expected_n, big.mark = ","))
  # na = character(0): a blank field must stay "" rather than become NA (a
  # blank occupation means "never submitted for coding", not "unknown").
  raw <- readr::read_fwf(txt,
    col_positions = readr::fwf_positions(lay$start, lay$end, col_names = lay$field),
    col_types = readr::cols(.default = readr::col_character()),
    na = character(0), trim_ws = FALSE, progress = FALSE, lazy = FALSE)
  if (nrow(raw) != expected_n)
    stop_hard("%d: read %d rows, file size implies %d", year, nrow(raw), expected_n)

  # -- derivations, verbatim from R/parse_nvss.R::derive_nvss -----------------
  int <- function(x) suppressWarnings(as.integer(trimws(x)))
  chr <- function(x) trimws(x)
  unit <- substr(raw$age_detail, 1, 1)
  val  <- suppressWarnings(as.integer(substr(raw$age_detail, 2, 4)))
  # Detail age: position 1 is the units flag, positions 2-4 the count. Anything
  # under a year is age 0; unit 9 (and 1/999) is "not stated".
  age_years <- ifelse(unit == "1" & !is.na(val) & val != 999L, val,
                      ifelse(unit %in% c("2", "4", "5", "6"), 0L, NA_integer_))
  df <- tibble::tibble(
    data_year        = int(raw$data_year),
    month            = int(raw$month_of_death),
    resident_status  = int(raw$resident_status),
    sex              = chr(raw$sex),
    age_years        = as.integer(age_years),
    hispanic_origin  = int(raw$hispanic_origin),
    race_recode_40   = int(raw$race_recode_40),
    icd10_underlying = toupper(chr(raw$icd10_underlying)),
    occ_code4        = chr(raw$occ_code4))
  df$cause_cat   <- classify_causes(df$icd10_underlying)
  df$cancer_site <- cancer_site(df$icd10_underlying, df$cause_cat)
  for (r in indicator_rules())
    df[[paste0("ind_", r$key)]] <- rule_match(norm_code(df$icd10_underlying), r)
  for (r in contributing_rules())
    df[[paste0("cf_", r$key)]] <- contributing_flag(raw$record_axis_raw, r)
  rm(raw); gc(verbose = FALSE)

  if (any(is.na(df$month)) || any(df$month < 1L | df$month > 12L)) {
    stop_hard("%d: month of death outside 1-12", year)
  }
  bad_year <- sum(df$data_year != year, na.rm = TRUE)
  if (bad_year > 0) stop_hard("%d: %d records carry another data year", year, bad_year)
  arrow::write_parquet(df, out)
  log_msg("  %d: %s records -> %s (%.0fs)", year,
          format(nrow(df), big.mark = ","), out,
          as.numeric(difftime(Sys.time(), t0, units = "secs")))
  unlink(txt)
  invisible()
}
log_msg("== NVSS fixed-width -> parquet ==")
for (y in YEARS) parse_nvss_year(y)

## ---- 4. Parse ACS PUMS (adapted from R/parse_acs.R) -----------------------
# Fields the letter needs: state, AGEP, SEX, RAC1P, HISP, OCCP, ESR, PWGTP and
# the 80 replicate weights PWGTP1-80 (for the workforce and geography CIs).

REPLICATES <- sprintf("PWGTP%d", 1:80)
ACS_MIN_AGE <- 15L   # NVSS excludes decedents under 15 from I&O coding entirely

parse_acs_year <- function(year) {
  out <- sprintf("data/acs_%d.parquet", year)
  if (file.exists(out)) { log_msg("  skip %d: %s exists", year, out); return(invisible()) }
  t0 <- Sys.time()
  z <- sprintf("data/raw/acs_pus_%d.zip", year)
  csvs <- grep("\\.csv$", unzip(z, list = TRUE)$Name, value = TRUE, ignore.case = TRUE)
  tmpdir <- sprintf("data/_acs_%d", year)
  dir.create(tmpdir, showWarnings = FALSE, recursive = TRUE)
  unzip(z, files = csvs, exdir = tmpdir, overwrite = TRUE)
  # Typed reads, reduced to the output columns immediately: reading all
  # columns as character drove the full pipeline's machine into swap.
  read_one <- function(m) {
    f <- file.path(tmpdir, m)
    hdr <- names(readr::read_csv(f, n_max = 0, show_col_types = FALSE, progress = FALSE))
    state_col <- intersect(c("ST", "STATE"), hdr)[1]
    if (is.na(state_col)) stop_hard("%d: no state column in %s", year, m)
    want <- c("AGEP", "SEX", "RAC1P", "HISP", "OCCP", "ESR", "PWGTP",
              REPLICATES, state_col)
    miss <- setdiff(want, hdr)
    if (length(miss)) stop_hard("%d: %s lacks %s", year, m, paste(miss, collapse = ", "))
    ct <- rep(list(readr::col_integer()), length(want)); names(ct) <- want
    # OCCP and the state code stay character: OCCP needs its leading zeros.
    for (k in c("OCCP", state_col)) ct[[k]] <- readr::col_character()
    d <- readr::read_csv(f, col_select = all_of(want),
                         col_types = do.call(readr::cols_only, ct),
                         progress = FALSE, show_col_types = FALSE)
    occ <- trimws(d$OCCP)
    res <- tibble::tibble(
      state = d[[state_col]],
      age   = as.integer(d$AGEP),
      sex   = ifelse(d$SEX == 1L, "M", ifelse(d$SEX == 2L, "F", NA_character_)),
      RAC1P = as.integer(d$RAC1P),
      HISP  = as.integer(d$HISP),
      occ_code4 = ifelse(grepl("^[0-9]{4}$", occ), occ, NA_character_),
      ESR   = as.integer(d$ESR),
      PWGTP = as.integer(d$PWGTP))
    # NA-preserving: ESR is missing only for 15-year-olds, but the derivation
    # matches the archival parquet exactly (parse_acs.R).
    res$employed_civilian <- ifelse(is.na(res$ESR), NA, res$ESR %in% c(1L, 2L))
    for (r in REPLICATES) res[[r]] <- as.integer(d[[r]])
    rm(d); gc(verbose = FALSE)
    res
  }
  res <- dplyr::bind_rows(lapply(csvs, read_one))
  unlink(tmpdir, recursive = TRUE)
  res <- res[!is.na(res$age) & res$age >= ACS_MIN_AGE, , drop = FALSE]
  arrow::write_parquet(res, out, compression = "zstd")
  log_msg("  %d: %s person records (ages %d+) -> %s (%.0fs)", year,
          format(nrow(res), big.mark = ","), ACS_MIN_AGE, out,
          as.numeric(difftime(Sys.time(), t0, units = "secs")))
  rm(res); gc(verbose = FALSE)
  invisible()
}
log_msg("== ACS 1-year PUMS -> parquet ==")
log_msg("  2020 is intentionally absent (experimental 1-year release);")
log_msg("  2019 is parsed only to average with 2021 for the 2020 denominator.")
for (y in ACS_YEARS) parse_acs_year(y)

## ---- 5. Canary: 2020 NCHS control totals ----------------------------------
# The four published counts from NCHS "Industry and Occupation (I&O) data as
# applicable to mortality vital statistics, 2020", Table C, page 8. Copied
# verbatim from the full repository's R/qc.R (CONTROL_2020 and
# qc_control_totals); the crosswalk lookup and supplemental-code list follow
# R/groups.R (harmonise_occ, not_employed_codes) with the codes taken from
# occ_crosswalk.csv mapping_kind instead of occ_groups.yaml (see DECISIONS).
CONTROL_2020 <- c(
  total_records                        = 3390278,
  eligible_age15_us_resident           = 3354879,
  coded_occupation_and_industry        = 3077127,
  records_with_census_occupation_codes = 2443813)

cw <- readr::read_csv("occ_crosswalk.csv",
                      col_types = readr::cols(.default = readr::col_character()))
sup <- sort(unique(cw$source_code[grepl("^supplemental_(not_in_labor_force|unknown|military)$",
                                        cw$mapping_kind)]))
d <- arrow::read_parquet("data/nvss_2020.parquet",
                         col_select = c("age_years", "resident_status", "occ_code4"))
x2012 <- cw[cw$scheme == "2012", ]                  # 2020 uses Census 2012 codes
analysis <- x2012$analysis_code[match(d$occ_code4, x2012$source_code)]
eligible <- !is.na(d$age_years) & d$age_years >= 15 & d$resident_status != 4L
has_occ  <- !is.na(d$occ_code4) & nzchar(d$occ_code4)
census_occ <- eligible & has_occ & !d$occ_code4 %in% sup & !is.na(analysis)
got <- c(total_records                        = nrow(d),
         eligible_age15_us_resident           = sum(eligible),
         coded_occupation_and_industry        = sum(eligible & has_occ),
         records_with_census_occupation_codes = sum(census_occ))

log_msg("== 2020 control totals (NCHS I&O documentation, Table C p.8) ==")
all_ok <- TRUE
for (nm in names(CONTROL_2020)) {
  ok <- got[[nm]] == CONTROL_2020[[nm]]
  all_ok <- all_ok && ok
  log_msg("  %-38s published %s  parsed %s  %s", nm,
          format(CONTROL_2020[[nm]], big.mark = ","),
          format(got[[nm]], big.mark = ","), if (ok) "PASS" else "FAIL")
}
if (!all_ok) { log_msg("CANARY FAILED: the parse does not reproduce the published totals."); quit(status = 1) }
log_msg("All four control totals reproduce. Run: Rscript 02_analysis.R")
