# Download BBS Data through R
# Create BBS named list RDS file
# EKB; May 2023; updated with Claude March 2026

## Install python, retriever, and rdataretriever

if (!requireNamespace('reticulate', quietly = TRUE)) install.packages('reticulate')
if (!requireNamespace('rdataretriever', quietly = TRUE)) install.packages('rdataretriever')
reticulate::use_python("/Library/Developer/CommandLineTools/usr/bin/python3", required = TRUE)
rdataretriever::get_updates() # Update the available datasets

library(rdataretriever)

dataset_names()

## Download Files ##

if (!dir.exists("data/bbs_dataretriever")) dir.create("data/bbs_dataretriever", recursive = TRUE)

rdataretriever::install_csv("breed-bird-survey",
                           output_path = "data/bbs_dataretriever",
                           overwrite = TRUE,
                           show_progress = TRUE)

## Create Named List and RDS file ##

if (!requireNamespace('tidyverse', quietly = TRUE)) install.packages('tidyverse')
library(tidyverse)

bbs_counts <- read_csv("data/bbs_dataretriever/breed_bird_survey_counts.csv")
bbs_migrants <- read_csv("data/bbs_dataretriever/breed_bird_survey_migrants.csv")
bbs_migrants_summary <- read_csv("data/bbs_dataretriever/breed_bird_survey_migrantsummary.csv")
bbs_routes <- read_csv("data/bbs_dataretriever/breed_bird_survey_routes.csv")
bbs_species <- read_csv("data/bbs_dataretriever/breed_bird_survey_species.csv")
bbs_vehicle <- read_csv("data/bbs_dataretriever/breed_bird_survey_vehicledata.csv")
bbs_weather <- read_csv("data/bbs_dataretriever/breed_bird_survey_weather.csv")

bbs_list <- list(bbs_counts = bbs_counts,
                 bbs_migrants = bbs_migrants,
                 bbs_migrants_summary = bbs_migrants_summary,
                 bbs_routes = bbs_routes,
                 bbs_species = bbs_species,
                 bbs_vehicle = bbs_vehicle,
                 bbs_weather = bbs_weather)
saveRDS(bbs_list, "data/bbs_dataretriever/bbs_data.RDS")

## Delete CSV files ##

file.remove(list.files("data/bbs_dataretriever", pattern = "\\.csv$", full.names = TRUE))
