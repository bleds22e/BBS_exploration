# Download BBS Data through R
# Create BBS named list RDS file
# EKB; May 2023

## Install python, retriever, and rdataretriver

install.packages('reticulate') # Install R package for interacting with Python
reticulate::install_miniconda() # Install Python
reticulate::py_install('retriever') # Install the Python retriever package
install.packages('rdataretriever') # Install the R package for running the retriever
rdataretriever::get_updates() # Update the available datasets

library(rdataretriever)

dataset_names()

## Download Files ##

rdataretriever::install_sqlite("breed-bird-survey")
rdataretriever::install_csv("breed-bird-survey")

## Create Named List and RDS file ##

install.packages("tidyverse")
library(tidyverse)

bbs_counts <- read_csv("breed_bird_survey_counts.csv")
bbs_migrants <- read_csv("breed_bird_survey_migrants.csv")
bbs_migrants_summary <- read_csv("breed_bird_survey_migrantsummary.csv")
bbs_routes <- read_csv("breed_bird_survey_routes.csv")
bbs_species <- read_csv("breed_bird_survey_species.csv")
bbs_vehicle <- read_csv("breed_bird_survey_vehicledata.csv")
bbs_weather <- read_csv("breed_bird_survey_weather.csv")

bbs_list <- list(bbs_counts = bbs_counts, 
                 bbs_migrants = bbs_migrants,
                 bbs_migrants_summary = bbs_migrants_summary,
                 bbs_routes = bbs_routes,
                 bbs_species = bbs_species,
                 bbs_vehicle = bbs_vehicle,
                 bbs_weather = bbs_weather)
saveRDS(bbs_list, "bbs_data.RDS")