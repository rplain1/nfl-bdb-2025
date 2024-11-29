library(data.table)
library(torch)

# Define a simple dataset class that inherits from torch::dataset
BDB2025_Dataset <- torch::dataset(
  name = "BDB2025_Dataset",
  initialize = function(feature_df, tgt_df) {
    self$feature_df <- feature_df
    self$tgt_df <- tgt_df
    self$keys <- unique(feature_df[, c("gameId", "playId", "mirrored", 'frameId')])
  },
  .length = function() {
    nrow(self$keys)
  },
  .getitem = function(idx) {
    key <- self$keys[idx, ]
    feature_row <- self$feature_df[key, .(x, y, vx, vy, side)]
    target_row <- self$tgt_df[key, ncol(self$tgt_df)]
    feature_array <- as.matrix(feature_row)  # Transform to matrix
    target_array <- as.matrix(target_row)    # Transform to matrix

    list(features = torch_tensor(feature_array), target = torch_tensor(target_array))
  }
)

# Example usage (assuming feature_df and tgt_df are your preprocessed data.tables):
feature_df <- arrow::read_parquet('split_prepped_data/test_features.parquet')
tgt_df <- arrow::read_parquet('split_prepped_data/test_targets.parquet')
set(tgt_df, j = ncol(tgt_df), value = as.numeric(factor(tgt_df[[ncol(tgt_df)]])))
d <- BDB2025_Dataset(feature_df = feature_df, tgt_df = tgt_df)

d$.length()
d$keys
d$.getitem(1)

test_loader <- torch::dataloader(d, batch_size =  64, shuffle = TRUE)
# Iterate through the dataloader and print the shapes

# we can then loop trough the elements of the dataloader with
coro::loop(for(batch in dl) {
  cat("X size:  ")
  print(batch[[1]]$size())
  cat("Y size:  ")
  print(batch[[2]]$size())

  break
})
