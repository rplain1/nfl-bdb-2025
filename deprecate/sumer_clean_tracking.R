library(tidyverse)
library(duckdb)

con <- dbConnect(duckdb(), 'data/bdb.duckdb')


tbl(con, 'tracking') |>
  inner_join(
    tbl(con, "plays") |>
      select(gameId, playId, down, yardsToGo, possessionTeam),
    by = c('gameId', 'playId')
  ) |>
  inner_join(
    tbl(con, "players") |>
      count(nflId, weight_Z, height_Z, position) |>
      select(-n),
    by = c('nflId')
  ) |>
  mutate(
    side = if_else(club == possessionTeam, 1, -1),
    dir = ((dir - 90) * -1) %% 360,
    o = (((o - 90) *-1) %% 360),
    vx = (s * cos(dir * pi / 180)),
    vy = (s * sin(dir * pi / 180)),
    ox = cos(o * pi / 180),
    oy = sin(o * pi / 180)
  ) |>
  mutate(
    x = if_else(playDirection == 'right', x , 120 - x),
    y = if_else(playDirection == 'right', y, 53.3 - y ),
    vx = if_else(playDirection == 'right', vx, -1 * vx),
    vy = if_else(playDirection == 'right', vy, -1 * vy),
    ox = if_else(playDirection == 'right', ox, -1 * ox),
    oy = if_else(playDirection == 'right', oy, -1 * oy),
  ) |>
  select(-possessionTeam) |>
  compute(name = "tracking_sumer", overwrite = TRUE, temporary = FALSE)


tbl(con, "tracking_sumer") |>
  union_all(
    tbl(con, "tracking_sumer") |>
      mutate(
        y = 53.3 - y,
        vy = -1 * vy,
        oy = -1 * oy,
        mirrored = TRUE
      )
  ) |>
  compute(name = "tracking_sumer_mirrored", overwrite = TRUE, temporary = FALSE)

ids <- tbl(con, 'tracking_sumer') |>
  count(gameId, playId, frameId) |>
  select(-n) |>
  collect()

train_ids <- ids |>
  slice_sample(prop = 0.7)

val_ids <- ids |>
  anti_join(train_ids) |>
  slice_sample(prop = 0.5)

test_ids <- ids |>
  anti_join(val_ids) |>
  anti_join(train_ids)

dbWriteTable(con, "train_ids", train_ids, overwrite = TRUE)
dbWriteTable(con, "val_ids", val_ids, overwrite = TRUE)
dbWriteTable(con, "test_ids", test_ids, overwrite = TRUE)


tbl(con, "tracking_sumer") |>
  inner_join(tbl(con, "test_ids")) #|> count()
