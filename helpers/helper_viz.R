library(gganimate)
library(tidyverse)
source("https://raw.githubusercontent.com/mlfurman3/gg_field/main/gg_field.R")
teams <- nflreadr::load_teams()

watch_film <- function(game_id, play_id) {
  d <- tbl(con, "tracking_clean") |>
    filter(gameId == game_id, playId == play_id) |>
    left_join(tbl(con, "plays")) |>
    collect() |>
    left_join(
      teams |>
        select(club = team_abbr, team_color, team_color2)
    ) |>
    mutate(
      cols_fill = if_else(is.na(team_color), "#663300", team_color),
      cols_col = if_else(is.na(team_color), "#663300", team_color),
      size_vals = if_else(is.na(team_color), 4, 6),
      shape_vals = if_else(is.na(team_color), 16, 22)
    )

  plot_title <- d$playDescription
  nFrames <- max(d$frameId)

  anim <- ggplot() +
    gg_field(yardmin = 0, yardmax = 122) +
    theme(
      panel.background = element_rect(
        fill = "forestgreen",
        color = "forestgreen"
      ),
      panel.grid = element_blank()
    ) +
    # setting size and color parameters
    geom_point(data = d, aes(x, y, shape = shape_vals, fill = cols_fill, group = nflId, size = size_vals, color = cols_col)) +
    geom_segment(aes(x = x, y = y, xend = x_end, yend = y_end), data = d) +
    geom_text(
      data = d,
      aes(x = x, y = y, label = jerseyNumber),
      colour = "white",
      vjust = 0.36, size = 3.5
    ) +
    scale_size_identity(guide = FALSE) +
    scale_shape_identity(guide = FALSE) +
    scale_fill_identity(guide = FALSE) +
    scale_colour_identity(guide = FALSE) +
    labs(title = plot_title) +
    transition_time(frameId) +
    ease_aes("linear") +
    NULL

  anim_save(
    glue::glue("plays/{unique(plot_title)}.gif"),
    animate(anim,
      width = 720, height = 440,
      fps = 10, nframe = nFrames
    )
  )
}
