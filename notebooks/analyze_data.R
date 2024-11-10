library(tidyverse)
library(duckplyr)

player_play <- duckplyr_df_from_csv('raw-data/player_play.csv')
plays <- duckplyr_df_from_csv('raw-data/plays.csv')
players <- duckplyr_df_from_csv('raw-data/players.csv')
tracking <- duckplyr_df_from_csv('raw-data/tracking_week_1.csv')
nflreadr::load_pbp(seasons = 2022) |> as_tibble() |> as_duckplyr_df() |>inner_join(plays |> mutate(gameId = as.character(gameId)), by = c('old_game_id' = 'gameId', 'play_id' = 'playId')) -> pbp


tracking |> head()

route_combinations <- player_play |>
  left_join(plays, by = c("gameId", "playId")) |>
  left_join(players, by = c("nflId")) |>
  filter(!is.na(passResult), position %in% c("WR", "TE", "RB")) |>
  count(gameId, playId, possessionTeam, routeRan) |>
  pivot_wider(id_cols = gameId:playId, names_from = routeRan, values_from = n, values_fn = sum)
