library(duckplyr)

INPUT_DATA_DIR = here::here('raw-data')
OUT_DIR = here::here("split_prepped_data")
DUCKDB_FILE <- here::here("data/bdb.duckdb")
con <- DBI::dbConnect(duckdb::duckdb(), DUCKDB_FILE)

read_pbp_data_duckplyr <- function(path) {
  duckplyr::duckplyr_df_from_csv(path, options = list(nullstr = 'NA'))
}

# players
get_players_df <- function() {
  read_pbp_data_duckplyr(here::here(INPUT_DATA_DIR, 'players.csv')) |>
    dplyr::mutate(
      height_inches = sapply(stringr::str_split(height, "-"), function(x) {
        as.integer(x[1]) * 12 + as.integer(x[2])
      }),
      weight_Z = (weight - mean(weight, na.rm = TRUE)) / sd(weight, na.rm =TRUE),
      height_Z = (height_inches - mean(height_inches, na.rm = TRUE)) / sd(height_inches, na.rm =TRUE)
    )
}
get_players_df()
dplyr::copy_to(con, get_players_df(), "players", overwrite = TRUE, temporary = FALSE)

# get_plays_df <- function() {
#   read_pbp_data_duckplyr(here::here(INPUT_DATA_DIR, 'plays.csv')) |>
#     dplyr::mutate(
#       distanceToGoal = dplyr::if_else(possessionTeam == yardlineSide, 100 - yardlineNumber, yardlineNumber)
#     )
# }

# get_player_play_df <- function() {
#   read_pbp_data_duckplyr(here::here(INPUT_DATA_DIR, 'player_play.csv')) |>
#     dplyr::mutate(
#       distanceToGoal = dplyr::if_else(possessionTeam == yardlineSide, 100 - yardlineNumber, yardlineNumber)
#     )
# }

# get_tracking_df <- function() {
#   read_pbp_data_duckplyr(here::here(INPUT_DATA_DIR, 'tracking_week_1.csv')) |>
#     dplyr::filter(displayName != 'football')
# }

# add_features_to_tracking_df <- function(tracking_df, players_df, plays_df) {
#   og_len = nrow(tracking_df)
#   tracking_df
# }
# dplyr::copy_to(con, process_players(), name = 'players', overwrite = TRUE, temporary = FALSE)
# dplyr::copy_to(con, process_plays(), name = 'plays', overwrite = TRUE, temporary = FALSE)
# dplyr::copy_to(con, process_tracking(), name = 'tracking', overwrite = TRUE, temporary = FALSE)

DBI::dbDisconnect(con)























  dplyr::mutate(
      height_inches = sapply(stringr::str_split(height, "-"), function(x) {
        as.integer(x[1]) * 12 + as.integer(x[2])
      }),
      weight_Z = (weight - mean(weight, na.rm = TRUE)) / sd(weight, na.rm =TRUE),
      height_Z = (height_inches - mean(height_inches, na.rm = TRUE)) / sd(height_inches, na.rm =TRUE)
    )
