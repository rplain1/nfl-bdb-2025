library(data.table)
library(torch)

# Define a simple dataset class that inherits from torch::dataset
BDB2025_Dataset <- torch::dataset(
  name = "BDB2025_Dataset",
  initialize = function(feature_df, tgt_df) {
    self$feature_df <- feature_df
    self$tgt_df <- tgt_df
    self$keys <- unique(feature_df[, c(
      "gameId",
      "playId",
      "mirrored",
      'frameId'
    )])
  },
  .length = function() {
    nrow(self$keys)
  },
  .getbatch = function(idx) {
    B <- length(idx)

    feature_array <- array(NA_real_, dim = c(B, 22L, 5L))
    target_array <- array(NA_real_, dim = (B))

    target_col <- names(self$tgt_df)[ncol(self$tgt_df)]

    for (i in seq_along(idx)) {
      key <- self$keys[idx[i], ]
      feature_row <- self$feature_df[key, .(x, y, vx, vy, side)]
      target_row <- self$tgt_df[key, ..target_col]
      feature_array[i, , ] <- as.matrix(feature_row) # Transform to matrix
      target_array[[i]] <- target_row[[1]] # Transform to matrix
    }
    # .getbatch change requires 22 -> 352
    if (dim(feature_array)[1] != 16) {
      print('wtf')
      print(key)
      print(feature_array)
    }

    # Assert dimensions for feature_array and target_array
    assertthat::assert_that(
      length(dim(feature_array)) == 3, # Should be 3D (batch x players x features)
      dim(feature_array)[2] == 22, # Should have 22 players
      dim(feature_array)[3] == 5 # Should have 5 features per player,
    )

    assertthat::assert_that(
      dim(target_array) == 16 # Should be 2D (batch_size x 1)
      # dim(target_array)[1] == 1, # Should be a single row (1 sample)
      # dim(target_array)[2] == 1 # Should have a single column (1 target value)
    )
    list(
      features = torch_tensor(feature_array),
      target = torch_tensor(target_array)
    )
  }
)

process_data <- function() {
  # TODO: removing test for dev
  for (split in c('train', 'val')) {
    message(glue::glue('Creating {split} dataset'))
    feature_df <- arrow::read_parquet(glue::glue(
      'split_prepped_data/{split}_features.parquet'
    ))
    tgt_df <- arrow::read_parquet(glue::glue(
      'split_prepped_data/{split}_targets.parquet'
    ))
    set(
      tgt_df,
      j = ncol(tgt_df),
      value = as.numeric(factor(tgt_df[[ncol(tgt_df)]]))
    )
    bdb_dataset <- BDB2025_Dataset(feature_df = feature_df, tgt_df = tgt_df)
    message(glue::glue('Writing {split} dataset'))
    torch_save(bdb_dataset, glue::glue('datasets/R/{split}_dataset.pt'))
  }
}

# development

# # load to dataset object
#feature_df <- arrow::read_parquet('split_prepped_data/test_features.parquet')
# tgt_df <- arrow::read_parquet('split_prepped_data/test_targets.parquet')
# set(tgt_df, j = ncol(tgt_df), value = as.numeric(factor(tgt_df[[ncol(tgt_df)]])))
# bdb_dataset <- BDB2025_Dataset(feature_df = feature_df, tgt_df = tgt_df)

# bdb_dataset$.length()
# bdb_dataset$keys
# bdb_dataset$.getitem(1)

# # load to dataloader object
# test_loader <- torch::dataloader(bdb_dataset, batch_size =  64, shuffle = TRUE)

# # Iterate through the dataloader and print the shapes
# # we can then loop trough the elements of the dataloader with
# # pulled from https://torch.mlverse.org/docs/articles/examples/dataset
# coro::loop(for(batch in test_loader) {
#   cat("X size:  ")
#   print(batch[[1]]$size())
#   cat("Y size:  ")
#   print(batch[[2]]$size())

#   break
# })
