library(data.table)

# get tracking / change if you want more than 1 week
get_tracking_dt <- function() {
  tracking <- fread('raw-data/tracking_week_1.csv', na.strings = 'NA')
  tracking <- tracking[displayName != "football"]
  tracking
}

# get players data, convert height and weight to Z values
get_players_dt <- function() {
  if (!file.exists('raw-data/players.csv')) {
    stop("File 'raw-data/players.csv' does not exist.")
  }
  players <- fread('raw-data/players.csv')
  players[, `:=`(
      height_inches = sapply(
        strsplit(height, "-"),
        function(x) as.integer(x[1]) * 12 + as.integer(x[2])
      ))]
  players[, `:=`(
      weight_Z = (weight - mean(weight, na.rm = TRUE)) / sd(weight, na.rm = TRUE),
      height_Z = (height_inches - mean(height_inches, na.rm = TRUE)) / sd(height_inches, na.rm = TRUE)
    )]

  players
}

# get plays and modify the distance to goal
get_plays_dt <- function() {
  plays <- fread('raw-data/plays.csv', na.strings = 'NA')

  plays[, distanceToGoal := ifelse(
    possessionTeam == yardlineSide,
    100 - yardlineNumber,
    yardlineNumber
  )]

  plays
}

# join tracking with other data, assign side for flipping to align everything later
clean_tracking <- function(tracking, plays, players) {
  checkmate::assert_data_table(tracking)

  og_len = nrow(tracking)
  tracking <- tracking[
    plays[, c("gameId", "playId", "possessionTeam", "down", "yardsToGo")],
    on=.(gameId, playId),
    nomatch=NULL
  ][
    players[,c('nflId', 'weight_Z', 'height_Z')],
    on=.(nflId),
    nomatch = NULL
  ]

  tracking[, `:=`(
    side = ifelse(club == possessionTeam, 1, 0)
  )]

  tracking[,possessionTeam:=NULL]

  checkmate::assert_true(og_len == nrow(tracking))
  tracking
}

# map values to unit circle
convert_tracking_to_cartesian <- function(tracking) {
  checkmate::assert_data_table(tracking)

  tracking[, `:=`(
    dir = ((dir - 90) * -1) %% 360,
    o = ((o - 90) * -1) %% 360
  )]

  tracking[, `:=`(
    vx = s * cos(dir * pi / 180), # Convert dir to radians for cos
    vy = s * sin(dir * pi / 180), # Convert dir to radians for sin
    ox = cos(o * pi / 180),       # Convert o to radians for cos
    oy = sin(o * pi / 180)        # Convert o to radians for sin
  )]

  tracking
}

# do all of the standardization so the plays are all oriented right
standardize_tracking_directions <- function(tracking) {
  checkmate::assert_data_table(tracking)

  tracking[, `:=` (
  x = ifelse(playDirection == 'right', x , 120 - x),
  y = ifelse(playDirection == 'right', y, 53.3 - y ),
  vx = ifelse(playDirection == 'right', vx, -1 * vx),
  vy = ifelse(playDirection == 'right', vy, -1 * vy),
  ox = ifelse(playDirection == 'right', ox, -1 * ox),
  oy = ifelse(playDirection == 'right', oy, -1 * oy)
)]
  tracking
}

# duplicate the dataset by created a mirrored world across y-axis
augment_mirror_tracking <- function(tracking) {
  checkmate::assert_data_table(tracking)
  checkmate::assert_true(nrow(tracking) > 0)

  og_len = nrow(tracking)

  # Mirror the dataset
  mirrored_tracking <- copy(tracking)[
    , `:=`(
      y = 53.3 - y,        # Flip y values
      vy = -1 * vy,            # Reverse vy
      oy = -1 * oy,            # Reverse oy
      mirrored = TRUE      # Mark as mirrored
    )
  ]
  tracking[, mirrored := FALSE]
  tracking <- rbind(tracking, mirrored_tracking)
  checkmate::assert_true(og_len * 2 == nrow(tracking))
  tracking

}

# method to sample keys for test/train
sample_rows <- function(d) {
    d[sample(nrow(d), size = ceiling(nrow(d)/2)), ]
}

# default function to get the y value of offenseFormation from Sumer
get_offense_formation <- function(tracking, plays) {

  checkmate::assert_data_table(tracking)
  checkmate::assert_data_table(plays)


  plays <- plays[!is.na(offenseFormation)]
  checkmate::check_character(unique(plays[!is.na(offenseFormation), offenseFormation]), any.missing = FALSE)

  tracking <- tracking[
    plays[, c("gameId", "playId", "offenseFormation")],
    on=.(gameId, playId),
    nomatch=NULL
  ]

  offense_formation <- unique(tracking[, c('gameId', 'playId', 'mirrored', 'frameId', 'offenseFormation')])

  tracking <- tracking[, offenseFormation := NULL]

  list(
    offense_formation = offense_formation,
    tracking_df = tracking
  )
}

# split the data into train, validation, and test datasets.
# returns a list of keys for each
split_data <- function(tracking, keycols = c("gameId", "playId", 'mirrored', 'frameId')) {
  checkmate::assert_data_table(tracking)
  checkmate::assert_character(keycols)
  ids <- unique(tracking[,..keycols])
  #setorder(tracking, gameId, playId, mirrored, frameId)

  setkeyv(ids, keycols)
  train_ids <- sample_rows(ids)
  setkeyv(train_ids, keycols)
  val_ids <- sample_rows(ids[!train_ids, ])
  test_ids <- ids[!train_ids, ][!val_ids, ]

  return(
    list(
      train_ids = train_ids,
      val_ids = val_ids,
      test_ids = test_ids
    )
  )
}

process_split_data <- function(data_list, data_name, ids, keycols) {
  checkmate::check_list(data_list)
  checkmate::check_tibble(!data_name %in% names(data_list))
  checkmate::check_data_table(data_list[[data_name]])

  setkeyv(data_list[[data_name]], keycols)
  setkeyv(ids, keycols)
  result <- data_list[[data_name]][ids]

  return(result)
}

prep_data <- function() {

  message('Loading tracking data')
  tracking <- get_tracking_dt()
  message('Loading players')
  players <- get_players_dt()
  message('Loading plays')
  plays <- get_plays_dt()
  message('Cleaning tracking data')
  tracking <- clean_tracking(tracking = tracking, plays = plays, players = players) |>
    convert_tracking_to_cartesian() |>
    standardize_tracking_directions() |>
    augment_mirror_tracking()
  message('Getting target data')
  train_target_data <- get_offense_formation(tracking, plays)

  ids <- split_data(train_target_data[['tracking_df']])
  # loop over the combination of train/val/test and feature/target datasets
  lapply(names(ids), function(id_name) {
  message("Processing ", id_name)
  lapply(names(train_target_data), function(data_name) {
    # join keys
    keycols <- c('gameId','playId', 'mirrored', 'frameId')
    #inner join
    tmp <- process_split_data(train_target_data, data_name, ids[[id_name]], keycols)

    # Check dimensions of features and targets before proceeding
    if (data_name == 'tracking_df') {
      assertthat::assert_that(all(tmp[, .N, by = keycols]$N == 22))  # Assert 22 players
    }
    if (data_name == 'offense_formation') {
      assertthat::assert_that(all(tmp[, .N, by = keycols]$N == 1))
    }

    data_name <- ifelse(data_name == 'tracking_df','features', 'targets')
    id_name <- gsub('_ids', '', id_name)
    file_name <- paste0('split_prepped_data/', id_name, "_", data_name, ".parquet")
    message("writing ", file_name)
    message("Total rows: ", nrow(tmp))
    arrow::write_parquet(tmp, file_name)
  })
})
}
