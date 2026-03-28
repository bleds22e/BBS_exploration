# North American Breeding Bird Survey: Data Download and Cleaning

2026-03-28

- [Overview](#overview)
- [1. Parameters](#1-parameters)
- [2. Package Setup](#2-package-setup)
- [3. Download BBS Data](#3-download-bbs-data)
- [4. Load Data Tables](#4-load-data-tables)
- [5. Survey-Level Filters](#5-survey-level-filters)
  - [5a. RPID = 101: Standard Protocol
    Only](#5a-rpid--101-standard-protocol-only)
  - [5b. RunType = 1: Acceptable Survey
    Conditions](#5b-runtype--1-acceptable-survey-conditions)
  - [5c. Year Range](#5c-year-range)
- [6. First-Year Observer Exclusion](#6-first-year-observer-exclusion)
- [7. Join Birds Table to Cleaned Survey
  Keys](#7-join-birds-table-to-cleaned-survey-keys)
- [8. Species-Level Filters](#8-species-level-filters)
  - [8a. Unidentified and Hybrid Taxa](#8a-unidentified-and-hybrid-taxa)
  - [8b. Nocturnal Species (Owls and
    Nightjars)](#8b-nocturnal-species-owls-and-nightjars)
  - [8c. Waterbirds (Optional)](#8c-waterbirds-optional)
  - [8d. Shorebirds (Optional)](#8d-shorebirds-optional)
- [9. Attach Route Metadata](#9-attach-route-metadata)
- [10. Summary Statistics](#10-summary-statistics)
- [11. Save Outputs](#11-save-outputs)
- [Notes for Downstream Analysis](#notes-for-downstream-analysis)

## Overview

This document downloads the North American Breeding Bird Survey (BBS)
dataset from the USGS and applies expert-recommended quality filters to
produce a general-purpose cleaned dataset suitable for any downstream
analysis (population trend modeling, occupancy models, species
distribution models, diversity analyses, etc.).

The BBS is a long-running roadside point-count survey of breeding birds
in the United States and Canada, conducted annually since 1966 along
thousands of standardized routes. For full program details, see the
[USGS BBS program page](https://www.pwrc.usgs.gov/bbs/).

------------------------------------------------------------------------

## 1. Parameters

All user-adjustable settings are defined here. Edit this block before
running the document to customize the cleaning behavior for your
analysis.

``` r
# ── Year range ──────────────────────────────────────────────────────────────
# 1966 is the first BBS year for US routes; Canada began in 1967.
# 1993 is a common alternative start year because RPID=101 standardization
# and digital record-keeping improved substantially around that time.
# See: Sauer et al. (2017) https://doi.org/10.1650/CONDOR-17-83.1
YEAR_MIN <- 1993
YEAR_MAX <- as.integer(format(Sys.Date(), "%Y"))

# ── Observer filters ────────────────────────────────────────────────────────
# Exclude route-years where the observer is running that route for the first
# time. First-year observers show a consistent negative detection bias
# (see Section 6 for full rationale and citations).
EXCLUDE_FIRST_YEAR_OBSERVERS <- TRUE

# ── Nocturnal species filter ─────────────────────────────────────────────────
# BBS is a diurnal survey; owls and nightjars are poorly and inconsistently
# detected. TRUE removes them (see Section 8b).
EXCLUDE_NOCTURNAL <- TRUE

# ── Waterbird filter (optional, stricter analyses) ───────────────────────────
# BBS routes are roadside; aquatic habitats are undersampled. FALSE is
# appropriate for general-purpose datasets.
EXCLUDE_WATERBIRDS <- FALSE

# ── Shorebird filter (optional) ───────────────────────────────────────────────
EXCLUDE_SHOREBIRDS <- FALSE

# ── Output directory ─────────────────────────────────────────────────────────
OUTPUT_DIR <- "../data/bbsBayes2_clean"
```

------------------------------------------------------------------------

## 2. Package Setup

``` r
required_pkgs <- c("bbsBayes2", "dplyr", "readr", "knitr")

for (pkg in required_pkgs) {
  if (!requireNamespace(pkg, quietly = TRUE)) {
    install.packages(pkg, dependencies = TRUE)
  }
}

library(bbsBayes2)
library(dplyr)
library(readr)
library(knitr)

if (!dir.exists(OUTPUT_DIR)) {
  dir.create(OUTPUT_DIR, recursive = TRUE)
}
```

------------------------------------------------------------------------

## 3. Download BBS Data

The [`bbsBayes2`](https://bbsbayes2.github.io/bbsBayes2/) package
provides `fetch_bbs_data()`, which downloads the official BBS dataset
directly from the [USGS ScienceBase
repository](https://doi.org/10.5066/P9HE8XYJ) and caches it locally.
Subsequent calls detect the cache and skip re-downloading unless
`force = TRUE` is passed.

**Note:** The first download is approximately 500 MB and may take
several minutes depending on your connection speed.

``` r
if (!bbsBayes2::have_bbs_data()) {
  message("BBS data not found in cache. Downloading from USGS...")
  bbsBayes2::fetch_bbs_data()
  message("Download complete.")
} else {
  message("BBS data already cached. Skipping download.",
          " Use fetch_bbs_data(force = TRUE) to refresh.")
}
```

------------------------------------------------------------------------

## 4. Load Data Tables

`load_bbs_data()` returns a named list with four tibbles. In bbsBayes2,
the `routes` table combines both survey-level metadata (observer,
conditions, quality flags) and route-level metadata (BCR, coordinates,
route type).

| Table | Contents |
|----|----|
| `$birds` | Species count records: one row per species per route-year |
| `$routes` | Survey + route metadata: observer, conditions, quality flags, coordinates |
| `$species` | AOU code lookup with taxonomy and unidentified-taxa flags |
| `$meta` | Release and download date metadata |

``` r
bbs_raw <- bbsBayes2::load_bbs_data()

# Snapshot raw dimensions
raw_dims <- tibble::tibble(
  Table   = c("birds", "routes", "species", "meta"),
  Rows    = c(nrow(bbs_raw$birds), nrow(bbs_raw$routes),
              nrow(bbs_raw$species), nrow(bbs_raw$meta)),
  Columns = c(ncol(bbs_raw$birds), ncol(bbs_raw$routes),
              ncol(bbs_raw$species), ncol(bbs_raw$meta))
)

kable(raw_dims, caption = "Raw BBS table dimensions before any filtering")
```

| Table   |    Rows | Columns |
|:--------|--------:|--------:|
| birds   | 7566328 |      16 |
| routes  |  127482 |      32 |
| species |    1526 |       9 |
| meta    |       1 |       2 |

Raw BBS table dimensions before any filtering

------------------------------------------------------------------------

## 5. Survey-Level Filters

All three filters below are applied to the **routes table** (which
contains survey-level quality fields). The resulting set of valid survey
keys (`state_num` + `route` + `year`) is then used in Section 7 to
subset the much larger birds table via an inner join.

We track row counts after each step for a complete audit trail.

``` r
weather <- bbs_raw$routes
n_weather_raw <- nrow(weather)
```

### 5a. RPID = 101: Standard Protocol Only

`rpid` (Run Protocol ID) encodes the BBS protocol variant used on a
given survey. RPID 101 is the standard roadside 50-stop count. Other
values include mini-routes, off-road routes, and experimental designs.
Mixing protocols inflates variance and introduces systematic differences
in detectability that cannot be modeled away.

[Sauer et al. (2017)](https://doi.org/10.1650/CONDOR-17-83.1) restrict
all published BBS trend analyses to RPID = 101, as does every subsequent
USGS BBS analysis.

``` r
weather <- weather |> filter(rpid == 101)

cat(sprintf("After rpid==101:  %d rows  (removed %d)\n",
            nrow(weather), n_weather_raw - nrow(weather)))
```

    After rpid==101:  127482 rows  (removed 0)

``` r
n_after_rpid <- nrow(weather)
```

### 5b. RunType = 1: Acceptable Survey Conditions

`run_type` is a binary quality flag assigned by USGS BBS program staff
after reviewing observer-submitted weather and protocol notes:

- **run_type = 1**: Survey met all protocol requirements (correct start
  time, acceptable wind and precipitation, complete route, etc.)
- **run_type = 0**: Survey conducted under non-standard conditions
  (excessive wind or rain, late start, incomplete route, etc.)

Including run_type = 0 surveys introduces detection heterogeneity that
cannot be adequately modeled and will bias trend estimates. All
published BBS trend analyses exclude them. See the [USGS BBS Data Use
Cautions](https://www.pwrc.usgs.gov/bbs/rawdata/PDF/WeatherCodes.pdf)
and the official data release: [Pardieck et al., USGS
ScienceBase](https://doi.org/10.5066/P9HE8XYJ).

``` r
weather <- weather |> filter(run_type == 1)

cat(sprintf("After run_type==1: %d rows  (removed %d)\n",
            nrow(weather), n_after_rpid - nrow(weather)))
```

    After run_type==1: 127482 rows  (removed 0)

``` r
n_after_runtype <- nrow(weather)
```

### 5c. Year Range

Restrict to the user-specified year range. The default start year of
1993 reflects improved RPID=101 standardization and digital
record-keeping quality. Analysts requiring longer time series may set
`YEAR_MIN <- 1966`, but should note that pre-1980 data has more missing
routes, higher observer turnover, and some residual protocol differences
([Sauer et al. 2017](https://doi.org/10.1650/CONDOR-17-83.1)).

``` r
weather <- weather |> filter(year >= YEAR_MIN, year <= YEAR_MAX)

cat(sprintf("After year [%d, %d]: %d rows  (removed %d)\n",
            YEAR_MIN, YEAR_MAX,
            nrow(weather), n_after_runtype - nrow(weather)))
```

    After year [1993, 2026]: 84424 rows  (removed 43058)

``` r
n_after_year <- nrow(weather)
```

------------------------------------------------------------------------

## 6. First-Year Observer Exclusion

Multiple studies have documented that observers running a BBS route for
the **first time** count detectably fewer birds than in subsequent
years. This startup bias likely reflects the time needed to learn a
route’s optimal listening positions, local species assemblages, and
difficult songs.

Key references:

- [Kendall et al. (1996)](https://doi.org/10.2307/2265700) — First
  documented the observer-learning effect quantitatively; showed removal
  of first-year observations reduced trend estimates for most species.
- [Sauer et al. (1994)](https://doi.org/10.2307/4088504) — Described
  observer-related variance in BBS data and recommended accounting for
  observer identity in modeling.
- [USGS BBS observer effects summary](https://www.pwrc.usgs.gov/bbs/) —
  Program documentation noting that first-year surveys produce lower
  counts.

The standard correction is to identify and remove (or flag) surveys
where the observer is running that specific route for the first time.
Observer ID (`obs_n`) is **route-specific** in USGS records — two
different routes can share an `obs_n` value for different people, so the
grouping key must include `state_num + route + obs_n`.

``` r
# Identify the first year each observer ran each route
observer_first_year <- weather |>
  group_by(state_num, route, obs_n) |>
  summarise(first_year = min(year), .groups = "drop")

# Join back and flag first-year surveys
weather <- weather |>
  left_join(observer_first_year, by = c("state_num", "route", "obs_n")) |>
  mutate(is_first_year_observer = (year == first_year))

n_first_yr <- sum(weather$is_first_year_observer)
cat(sprintf("First-year observer surveys identified: %d\n", n_first_yr))
```

    First-year observer surveys identified: 13115

``` r
if (EXCLUDE_FIRST_YEAR_OBSERVERS) {
  weather <- weather |> filter(!is_first_year_observer)
  cat(sprintf("After first-year exclusion: %d rows  (removed %d)\n",
              nrow(weather), n_after_year - nrow(weather)))
} else {
  message("First-year observers flagged but retained.",
          " Column 'is_first_year_observer' available for sensitivity analysis.")
}
```

    After first-year exclusion: 71309 rows  (removed 13115)

``` r
n_after_observer <- nrow(weather)
```

------------------------------------------------------------------------

## 7. Join Birds Table to Cleaned Survey Keys

Having filtered the routes table to only valid surveys, we now propagate
those filters to the birds table via an inner join on
`state_num + route + year`. Only bird records from surveys that passed
all weather/observer filters are retained.

``` r
weather_keys <- weather |>
  select(state_num, route, year, obs_n, first_year, is_first_year_observer)

birds <- bbs_raw$birds
n_birds_raw <- nrow(birds)

birds_filtered <- birds |>
  inner_join(weather_keys, by = c("state_num", "route", "year"))

cat(sprintf("Birds before join (raw):       %d rows\n", n_birds_raw))
```

    Birds before join (raw):       7566328 rows

``` r
cat(sprintf("Birds after survey-key join:   %d rows  (removed %d)\n",
            nrow(birds_filtered), n_birds_raw - nrow(birds_filtered)))
```

    Birds after survey-key join:   4061961 rows  (removed 3504367)

``` r
n_birds_after_join <- nrow(birds_filtered)
```

------------------------------------------------------------------------

## 8. Species-Level Filters

### 8a. Unidentified and Hybrid Taxa

The BBS species table includes records where identification was
ambiguous — for example, *Empidonax* sp., gull hybrids, or combined
counts of cryptic species pairs. These cannot be reliably attributed to
a single species and are excluded. USGS uses AOU codes above 48,000 for
most unidentified records; the `unid_combined` flag in the species table
provides a more explicit filter. See the [USGS BBS species list
documentation](https://www.pwrc.usgs.gov/bbs/rawdata/).

``` r
species_tbl <- bbs_raw$species

# Attempt to use the unid_combined flag; fall back to AOU < 48000 if absent
if ("unid_combined" %in% names(species_tbl)) {
  valid_aou <- species_tbl |>
    filter(unid_combined == 0) |>
    pull(aou)
} else {
  message("Column 'unid_combined' not found; using AOU < 48000 as fallback.")
  valid_aou <- species_tbl |>
    filter(aou < 48000) |>
    pull(aou)
}

n_before_unid <- nrow(birds_filtered)
birds_filtered <- birds_filtered |> filter(aou %in% valid_aou)

cat(sprintf("After unidentified taxa removal: %d rows  (removed %d)\n",
            nrow(birds_filtered), n_before_unid - nrow(birds_filtered)))
```

    After unidentified taxa removal: 4061961 rows  (removed 0)

### 8b. Nocturnal Species (Owls and Nightjars)

The BBS protocol begins approximately 30 minutes before local sunrise
and covers 50 roadside stops over roughly 4.5 hours — it is
fundamentally a **diurnal** survey. Owls (Strigiformes) and nightjars
(Caprimulgiformes) may be heard incidentally at the earliest stops but
are not systematically detected, and their apparent BBS trends more
likely reflect variation in ambient light conditions and observer
behavior than true population change.

[Robbins et al. (1986)](https://doi.org/10.2307/3830552) — the
foundational BBS methods paper — explicitly listed these groups as
poorly sampled. This exclusion is standard practice in all published BBS
trend analyses; see also the [bbsBayes2 species list
rationale](https://bbsbayes2.github.io/bbsBayes2/).

AOU ranges used:

| Group                       | AOU range | Example species                  |
|-----------------------------|-----------|----------------------------------|
| Barn Owl (*Tytonidae*)      | 3600      | Barn Owl                         |
| Owls (*Strigidae*)          | 3650–3810 | Great Horned, Barred, Saw-whet   |
| Nightjars (*Caprimulgidae*) | 4160–4210 | Whip-poor-will, Common Nighthawk |

``` r
if (EXCLUDE_NOCTURNAL) {
  # Verify which species fall in these ranges against the actual species table
  nocturnal_check <- species_tbl |>
    filter((aou >= 3600 & aou <= 3810) | (aou >= 4160 & aou <= 4210)) |>
    select(aou, english) |>
    arrange(aou)

  cat("Species removed as nocturnal:\n")
  print(nocturnal_check, n = Inf)

  n_before_noct <- nrow(birds_filtered)
  birds_filtered <- birds_filtered |>
    filter(
      !(aou >= 3600 & aou <= 3810),   # Barn Owl + Strigidae owls
      !(aou >= 4160 & aou <= 4210)    # Caprimulgidae nightjars
    )

  cat(sprintf("\nAfter nocturnal species removal: %d rows  (removed %d)\n",
              nrow(birds_filtered), n_before_noct - nrow(birds_filtered)))
}
```

    Species removed as nocturnal:
    # A tibble: 64 × 2
         aou english                                     
       <dbl> <chr>                                       
     1  3600 American Kestrel                            
     2  3600 American Kestrel                            
     3  3620 Crested Caracara                            
     4  3620 Crested Caracara                            
     5  3640 Osprey                                      
     6  3640 Osprey                                      
     7  3650 American Barn Owl                           
     8  3650 American Barn Owl                           
     9  3660 Long-eared Owl                              
    10  3660 Long-eared Owl                              
    11  3670 Short-eared Owl                             
    12  3670 Short-eared Owl                             
    13  3680 Barred Owl                                  
    14  3680 Barred Owl                                  
    15  3690 Spotted Owl                                 
    16  3690 Spotted Owl                                 
    17  3700 Great Gray Owl                              
    18  3700 Great Gray Owl                              
    19  3710 Boreal Owl                                  
    20  3710 Boreal Owl                                  
    21  3720 Northern Saw-whet Owl                       
    22  3720 Northern Saw-whet Owl                       
    23  3730 Eastern Screech-Owl                         
    24  3730 Eastern Screech-Owl                         
    25  3731 Whiskered Screech-Owl                       
    26  3731 Whiskered Screech-Owl                       
    27  3732 Western Screech-Owl                         
    28  3732 Western Screech-Owl                         
    29  3740 Flammulated Owl                             
    30  3740 Flammulated Owl                             
    31  3750 Great Horned Owl                            
    32  3750 Great Horned Owl                            
    33  3760 Snowy Owl                                   
    34  3760 Snowy Owl                                   
    35  3770 Northern Hawk Owl                           
    36  3770 Northern Hawk Owl                           
    37  3780 Burrowing Owl                               
    38  3780 Burrowing Owl                               
    39  3790 Northern Pygmy-Owl                          
    40  3790 Northern Pygmy-Owl                          
    41  3800 Ferruginous Pygmy-Owl                       
    42  3800 Ferruginous Pygmy-Owl                       
    43  3810 Elf Owl                                     
    44  3810 Elf Owl                                     
    45  4160 Chuck-will's-widow                          
    46  4160 Chuck-will's-widow                          
    47  4171 Eastern Whip-poor-will                      
    48  4171 Eastern Whip-poor-will                      
    49  4172 Mexican Whip-poor-will                      
    50  4172 Mexican Whip-poor-will                      
    51  4180 Common Poorwill                             
    52  4180 Common Poorwill                             
    53  4190 Common Pauraque                             
    54  4190 Common Pauraque                             
    55  4200 Common Nighthawk                            
    56  4200 Common Nighthawk                            
    57  4201 Antillean Nighthawk                         
    58  4201 Antillean Nighthawk                         
    59  4205 unid. Lesser Nighthawk / Common Nighthawk   
    60  4205 unid. Lesser Nighthawk / Common Nighthawk   
    61  4206 unid. Common Nighthawk / Antillean Nighthawk
    62  4206 unid. Common Nighthawk / Antillean Nighthawk
    63  4210 Lesser Nighthawk                            
    64  4210 Lesser Nighthawk                            

    After nocturnal species removal: 3991518 rows  (removed 70443)

### 8c. Waterbirds (Optional)

BBS roadside routes systematically undersample aquatic habitats. Loons,
grebes, pelicans, cormorants, herons, and related waterbirds (AOU \<
200, approximately) are detected far less reliably than on dedicated
waterbird surveys. [Link & Sauer
(2002)](https://doi.org/10.1890/0012-9658(2002)083%5B2832:AHMOPCA%5D2.0.CO;2)
discuss the detectability assumptions underlying BBS analyses and note
that habitat-associated detectability heterogeneity is a key concern.

This filter is **disabled by default** (`EXCLUDE_WATERBIRDS <- FALSE`)
because many analysts retain waterbirds for general richness or
community composition work. Enable it for analyses where detectability
or habitat association is central.

``` r
if (EXCLUDE_WATERBIRDS) {
  n_before_water <- nrow(birds_filtered)
  birds_filtered <- birds_filtered |> filter(aou >= 200)
  cat(sprintf("After waterbird removal (AOU < 200): %d rows  (removed %d)\n",
              nrow(birds_filtered), n_before_water - nrow(birds_filtered)))
  message("NOTE: AOU < 200 cutoff is approximate. Verify against species list.")
}
```

### 8d. Shorebirds (Optional)

Shorebirds (Charadriiformes, approximately AOU 2390–2980) are also
undersampled by BBS methods for the same habitat-detectability reasons
as waterbirds. This filter is disabled by default.

``` r
if (EXCLUDE_SHOREBIRDS) {
  n_before_shore <- nrow(birds_filtered)
  birds_filtered <- birds_filtered |>
    filter(!(aou >= 2390 & aou <= 2980))
  cat(sprintf("After shorebird removal (AOU 2390–2980): %d rows  (removed %d)\n",
              nrow(birds_filtered), n_before_shore - nrow(birds_filtered)))
}
```

------------------------------------------------------------------------

## 9. Attach Route Metadata

Join route-level covariates (coordinates, route type, active status) to
the cleaned bird records. In bbsBayes2, this information is in
`bbs_raw$routes`; we deduplicate to one row per route before joining.

``` r
route_meta <- bbs_raw$routes |>
  select(state_num, route, latitude, longitude, route_type_id, active) |>
  distinct()

bbs_clean <- birds_filtered |>
  left_join(route_meta, by = c("state_num", "route"))

n_missing_route <- sum(is.na(bbs_clean$latitude))
if (n_missing_route > 0) {
  warning(sprintf("%d records could not be matched to route metadata.",
                  n_missing_route))
}
```

------------------------------------------------------------------------

## 10. Summary Statistics

``` r
summary_stats <- tibble::tibble(
  Metric  = c("Total bird count records",
               "Unique species (AOU codes)",
               "Unique routes",
               "Year range",
               "BCRs represented"),
  Value   = c(
    format(nrow(bbs_clean), big.mark = ","),
    format(n_distinct(bbs_clean$aou), big.mark = ","),
    format(n_distinct(paste(bbs_clean$state_num, bbs_clean$route)), big.mark = ","),
    paste(min(bbs_clean$year), "–", max(bbs_clean$year)),
    as.character(n_distinct(bbs_clean$bcr))
  )
)

kable(summary_stats, caption = "Cleaned dataset summary")
```

| Metric                     | Value       |
|:---------------------------|:------------|
| Total bird count records   | 3,991,518   |
| Unique species (AOU codes) | 697         |
| Unique routes              | 4,680       |
| Year range                 | 1994 – 2024 |
| BCRs represented           | 37          |

Cleaned dataset summary

``` r
# Filter audit table
audit <- tibble::tibble(
  Step = c(
    "Raw birds table",
    "After survey-key join (rpid, run_type, year, observer filters)",
    "After species-level filters",
    "Final cleaned dataset"
  ),
  Rows = c(
    n_birds_raw,
    n_birds_after_join,
    nrow(birds_filtered),
    nrow(bbs_clean)
  )
) |>
  mutate(
    `Rows removed` = c(0, -diff(Rows)),
    `% of raw` = round(Rows / n_birds_raw * 100, 1)
  )

kable(audit, caption = "Filter audit: rows retained at each step",
      format.args = list(big.mark = ","))
```

| Step | Rows | Rows removed | % of raw |
|:---|---:|---:|---:|
| Raw birds table | 7,566,328 | 0 | 100.0 |
| After survey-key join (rpid, run_type, year, observer filters) | 4,061,961 | 3,504,367 | 53.7 |
| After species-level filters | 3,991,518 | 70,443 | 52.8 |
| Final cleaned dataset | 3,991,518 | 0 | 52.8 |

Filter audit: rows retained at each step

------------------------------------------------------------------------

## 11. Save Outputs

``` r
# Primary analysis file (preserves all R data types)
rds_path <- file.path(OUTPUT_DIR, "bbs_birds_clean.rds")
saveRDS(bbs_clean, file = rds_path)
message("Saved: ", rds_path)

# Compressed CSV for interoperability (Python, Stan, Excel, etc.)
csv_path <- file.path(OUTPUT_DIR, "bbs_birds_clean.csv.gz")
write_csv(bbs_clean, file = csv_path)
message("Saved: ", csv_path, "  (gzip compressed)")

# Cleaned weather/survey metadata for observer-level modeling
weather_path <- file.path(OUTPUT_DIR, "bbs_weather_clean.rds")
saveRDS(weather, file = weather_path)
message("Saved: ", weather_path)

# Reproducibility log
params_log <- tibble::tibble(
  parameter = c("YEAR_MIN", "YEAR_MAX",
                "EXCLUDE_FIRST_YEAR_OBSERVERS",
                "EXCLUDE_NOCTURNAL",
                "EXCLUDE_WATERBIRDS",
                "EXCLUDE_SHOREBIRDS",
                "date_run",
                "R_version",
                "bbsBayes2_version"),
  value = c(YEAR_MIN, YEAR_MAX,
            EXCLUDE_FIRST_YEAR_OBSERVERS,
            EXCLUDE_NOCTURNAL,
            EXCLUDE_WATERBIRDS,
            EXCLUDE_SHOREBIRDS,
            as.character(Sys.Date()),
            as.character(getRversion()),
            as.character(packageVersion("bbsBayes2")))
)

params_path <- file.path(OUTPUT_DIR, "run_parameters.csv")
write_csv(params_log, file = params_path)
message("Saved: ", params_path)

message("\nDone. Load cleaned data with: bbs <- readRDS('", rds_path, "')")
```

------------------------------------------------------------------------

## Notes for Downstream Analysis

**Zero-filling**: This output is a *detections-only* table — unobserved
species on a route-year are implicit zeros. Most population trend and
occupancy models require explicit zero rows. Zero-filling is
deliberately omitted here because (1) it inflates file size 10–50× and
(2) the correct approach depends on your target species list and spatial
extent. When ready:

``` r
bbs_complete <- tidyr::complete(
  bbs_clean,
  tidyr::nesting(state_num, route, year, obs_n),
  aou,
  fill = list(stop_total = 0)
)
```

**Column name compatibility**: bbsBayes2 returns snake_case column names
(`aou`, `state_num`). If downstream joins fail, standardize with
`names(df) <- tolower(names(df))`.

**Further stratification**: For trend modeling, the cleaned data can be
passed to `bbsBayes2::stratify(by = "bcr")` after subsetting to a single
species, or used directly with `lme4`, `Stan`, or `JAGS` models.
