library(torch)

# replicate Sumer sports transformer
# Note: transformers not available yet in torch for R
sports_transformer <- nn_module(
  clasname = "sports_transformer",
  # the initialize function tuns whenever we instantiate the model
  initialize = function(
    feature_len,
    model_dim,
    num_layers,
    output_dim,
    dropout
  ) {

    dim_feedforward <- model_dim * 4
    num_heads <- min(16, max(2, 2 * round(model_dim / 64)))
    self$hyper_params <- list(
      model_dim = model_dim,
      num_layers = num_layers,
      num_heads = num_heads,
      dim_feedforward = dim_feedforward
    )
    self$feature_norm_layer <- nn_batch_norm1d(feature_len)
    self$feature_embedding_layer <- nn_sequential(
      nn_linear(feature_len, model_dim),
      nn_relu(),
      nn_layer_norm(model_dim),
      nn_dropout(dropout)
    )

    # insert transformer code here
    # self$transformer_encoder = nn_transformer_encoder(
    #   nn_transformer_encoder_layer(
    #     d_model = model_dim,
    #     nhead = num_heads,
    #     dim_feedforward=dim_feedforward,
    #     dropout = dropout,
    #     batch_first = TRUE
    #   )
    # )

    self$player_pooling_layer = nn_adaptive_avg_pool1d(1)

    self$decoder = nn_sequential(
      nn_linear(model_dim, model_dim),
      nn_relu(),
      nn_dropout(dropout),
      nn_linear(model_dim, model_dim %/% 4),
      nn_relu(),
      nn_layer_norm(model_dim %/% 4),
      nn_linear(model_dim %/% 4, output_dim) # Adjusted to match target shape
    )

  },

  # this function is called whenever we call our model on input.
  forward = function(x) {
    # batch_size
    B <- dim(x)[[1]]
    # players
    P <- dim(x)[[2]]
    #feature_len
    F <- dim(x)[[3]]

    # normalize features
    x <- x$permute(c(1, 3, 2))
    x <- self$feature_norm_layer(x)
    x <- x$permute(c(1, 3, 2))

    # embed features
    x <- self$feature_embedding_layer(x)

    # apply transformer encoder
    # x <- sefl$transfromer_encoder(x)

    # pool over player dimension
    x <- x$permute(c(1, 3, 2))
    x <- self$player_pooling_layer(x)
    x <- torch_squeeze(x, dim = -1)

    # decode to predict output
    x <- self$decoder(x)

    return(x)

  }
)

# development

# # Instantiate the model
# feature_len <- 10
# model_dim <- 32
# num_layers <- 2
# output_dim <- 7 # offense formation
# dropout <- 0.3

# model <- sports_transformer(
#   feature_len = feature_len,
#   model_dim = model_dim,
#   num_layers = num_layers,
#   output_dim = output_dim,
#   dropout = dropout
# )

# # Create example input data
# batch_size <- 4
# num_players <- 22
# input_tensor <- torch_randn(c(batch_size, num_players, feature_len)) # [B, P, F]

# # Run the forward pass
# output <- model(input_tensor)
# cat("Output shape: ", dim(output), "\n")
