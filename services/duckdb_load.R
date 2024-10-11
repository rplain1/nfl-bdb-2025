library(tidyverse)
library(duckdb)

read_csv_week <- function(file_name) {
  readr::read_csv(file_name) |>
    mutate(week = str_extract(file_name, "\\d")) |>
    # mutate(
    #   x_std = ifelse(playDirection == "left", 120 - x, x),
    #   y_std = ifelse(playDirection == "left", 160 / 3 - y, y)
    # ) |>
    janitor::clean_names()
}

df_tracking <- paste0("raw-data/", list.files(path = "raw-data/", pattern = "tracking*")) |>
  map_dfr(read_csv_week)


con <- dbConnect(duckdb::duckdb(), dbdir = "data/bdb.duckdb")
dbWriteTable(con, "tracking", df_tracking, overwrite = TRUE)
rm(df_tracking)
gc()
message("Table Updated")

players <- read_csv("data/players.csv") |> janitor::clean_names()
games <- read_csv("data/games.csv") |> janitor::clean_names()
plays <- read_csv("data/plays.csv") |> janitor::clean_names()
player_play <- read_csv("data/player_play.csv") |> janitor::clean_names()

dbWriteTable(con, "players", players, overwrite = TRUE)
dbWriteTable(con, "games", games, overwrite = TRUE)
dbWriteTable(con, "plays", plays, overwrite = TRUE)
dbWriteTable(con, "player_play", player_play, overwrite = TRUE)
