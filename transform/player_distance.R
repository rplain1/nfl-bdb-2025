library(tidyverse)
library(duckdb)

con <- dbConnect(duckdb(), 'data/bdb.duckdb')
tbl(con, "tracking_clean")

ids <- tbl(con, "plays") |>
  slice_sample(n = 1) |>
  select(ends_with('Id')) |>
  collect()

ids


tbl(con, "tracking") |>
  filter(gameId == ids$gameId, playId == ids$playId) |>
   left_join(tbl(con, "players") |> select(nflId, position)) |>
  mutate(nflId = if_else(displayName == 'football', -1, nflId)) |>
  collect() -> df

df |>
    mutate(
      position_group = case_when(
          position %in% c('DB', 'CB') ~ 'CB',
          position %in% c('SS', 'FS') ~ 'S',
          position %in% c('G', 'C', 'LS') ~ 'IOL',
          position %in% c('DT', 'NT') ~ 'DT',
          position %in% c('ILB', 'MLB') ~ 'ILB',
          is.na(position) ~ 'FOOTBALL',
          TRUE ~ position
      )
  ) |>
  group_by(frameId, position_group) |>
  arrange(y) |>
  mutate(
    rn = row_number(),
    pos_unique = if_else(position_group == 'FOOTBALL', 'football', paste0(position_group, rn))
  ) |>
  ungroup() -> df_positions

coords <- df_positions |>
  filter(frameId == 1) |>
  select(x, y)

df_distances <- as.data.frame(as.matrix(dist(coords)))
rownames(df_distances) <- df_positions |> filter(frameId == 1) |> pull(nflId)
colnames(df_distances) <- df_positions |> filter(frameId == 1) |> pull(pos_unique)

df_distances


df_positions |>
  filter(frameId == 1) |>
  ggplot(aes(x, y, color = club)) +
  geom_point() +
  ggrepel::geom_text_repel(aes(label = pos_unique))


###

tbl(con, "tracking_clean") |>
  select(gameId, playId, nflId, frameId, club, x, y) |>
  left_join(tbl(con, "players") |> select(nflId, position)) |>
  mutate(
    position_group = case_when(
        position %in% c('DB', 'CB') ~ 'CB',
        position %in% c('SS', 'FS') ~ 'S',
        position %in% c('G', 'C', 'LS') ~ 'IOL',
        position %in% c('DT', 'NT') ~ 'DT',
        position %in% c('ILB', 'MLB') ~ 'ILB',
        is.na(position) ~ 'FOOTBALL',
        TRUE ~ position
    )
  ) |>
  mutate(
    rn = sql('ROW_NUMBER() OVER (PARTITION BY frameId, position_group ORDER BY y)')
  ) |>
  mutate(
    pos_unique = if_else(position_group == 'FOOTBALL', 'football', paste0(position_group, rn))
  ) |>
  compute(name = 'position_distance_staging', temporary = FALSE, overwrite = TRUE)


tbl(con, "position_distance_staging") |>
  select(gameId, playId, nflId, frameId, pos_unique, x, y) |>
  cross_join(
    tbl(con, "staging_position_distance") |>
      select(gameId, playId, nflId, frameId, pos_unique, x, y),
    suffix = c('', '_join')
  ) |>
  mutate(
    distance = sql('SQRT(POWER(x - x_join, 2) + POWER(y - y_join, 2))')
  ) |>
  select(gameId, playId, nflId, frameId, pos_unique, pos_unique_join, distance) |>
  #pivot_wider(id_cols = c(gameId, playId, nflId, frameId, pos_unique), names_from = pos_unique_join, values_from = distance) |>
  compute(name = 'position_distance_long', temporary = FALSE, overwrite = TRUE)
