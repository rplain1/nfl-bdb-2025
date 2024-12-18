library(tidyverse)
library(duckdb)

con <- dbConnect(duckdb(), "data/bdb.duckdb")
tbl(con, "tracking")


tbl(con, "tracking") |>
  mutate(
    # make all plays go from left to right
    x = ifelse(playDirection == "left", 120 - x, x),
    y = ifelse(playDirection == "left", 160 / 3 - y, y),
    # flip player direction and orientation
    dir = ifelse(playDirection == "left", dir + 180, dir),
    dir = ifelse(dir > 360, dir - 360, dir),
    o = ifelse(playDirection == "left", o + 180, o),
    o = ifelse(o > 360, o - 360, o),
    dir_rad = pi * (dir / 180),
    # get orientation and direction in x and y direction
    # NA checks are for the ball
    dir_x = ifelse(is.na(dir), NA_real_, sin(dir_rad)),
    dir_y = ifelse(is.na(dir), NA_real_, cos(dir_rad)),
    # Get directional speed/velo
    s_x = dir_x * s,
    s_y = dir_y * s,
    # Get directional acceleration
    a_x = dir_x * a,
    a_y = dir_y * a,

    x_end = s*cos((90 - dir)*pi / 180) + x,
    y_end = s*sin((90 - dir)*pi / 180) + y,
  ) |>
  compute(name = "tracking_clean", temporary = FALSE, overwrite = TRUE)

tbl(con, "tracking_clean") |>
  select(a_x, a_y, x_end)

tbl(con, "tracking_clean") |>
  group_by(gameId, playId, frameId, club) |>
  summarise(
    x_min = min(x, na.rm = TRUE),
    x_max = max(x, na.rm = TRUE),
    y_min = min(y, na.rm = TRUE),
    y_max = max(y, na.rm = TRUE)
  ) |>
  mutate(
    x_range = x_max - x_min,
    y_range = y_max - y_min
  ) |>
  compute(name = "tracking_range")
