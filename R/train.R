library(data.table)
library(torch)
set.seed(527)
torch_manual_seed(527)

source('R/prep_data.R')
source('R/process_data.R')
source('R/models.R')
#prep_data()
process_data()

# Instantiate the model
feature_len <- 5
model_dim <- 32
num_layers <- 2
output_dim <- 7 # offense formation
dropout <- 0.3

model <- sports_transformer(
  feature_len = feature_len,
  model_dim = model_dim,
  num_layers = num_layers,
  output_dim = output_dim,
  dropout = dropout
)

device <- torch_device('mps')
model$to(device = device)

# Load raw data
train_data <- torch_load('datasets/R/train_dataset.pt', device = device)
val_data <- torch_load('datasets/R/val_dataset.pt', device = device)

batch_size <- 16

# Create dataloaders
train_loader <- torch::dataloader(
  train_data,
  batch_size = batch_size,
  shuffle = TRUE,
)
val_loader <- torch::dataloader(
  val_data,
  batch_size = batch_size,
  shuffle = TRUE,
)

folds <- 1

accuracies <- torch_zeros(length(folds), device = device)
best_epochs <- torch_zeros(length(folds), device = device)

epochs <- 50

optimizer <- optim_adam(model$parameters, lr = 0.01)
scheduler <- lr_step(optimizer, step_size = 1, 0.95)


num_folds <- 5 # or however many folds you have
accuracies <- rep(0, num_folds)
best_epochs <- rep(0, num_folds)

for (fold in 1:num_folds) {
  message(glue::glue("Starting fold {fold}"))

  # Here you would set up your train_loader and val_loader for this fold
  # e.g., train_loader <- create_dataloader(fold_train_data[[fold]])
  #       val_loader   <- create_dataloader(fold_val_data[[fold]])

  for (epoch in 1:epochs) {
    message(glue::glue("Epoch {epoch} / Fold {fold}"))
    losses <- c()
    valid_losses <- c()
    valid_accuracies <- c()

    # Training step
    model$train()
    pb <- progress::progress_bar$new(
      total = length(train_loader),
      format = "  Training [:bar] :percent :elapsed",
      clear = FALSE,
      width = 60
    )
    coro::loop(
      for (b in train_loader) {
        features <- b$features$to(device = device)
        target <- b$target$to(device = device)

        optimizer$zero_grad()
        loss <- nnf_cross_entropy(model(features), torch_squeeze(target))
        loss$backward()
        optimizer$step()

        losses <- c(losses, loss$item())
        pb$tick()
      }
    )

    # Validation step
    model$eval()
    coro::loop(
      for (b in val_loader) {
        features <- b$features$to(device = device)
        target <- b$target$to(device = device)

        output <- model(features)
        valid_losses <- c(
          valid_losses,
          nnf_cross_entropy(output, torch_squeeze(target))$item()
        )
        pred <- torch_max(output, dim = 2)[[2]]
        correct <- (pred == target)$sum()$item()
        valid_accuracies <- c(valid_accuracies, correct / length(target))
      }
    )

    scheduler$step()

    # Print progress every 10 epochs
    if (epoch %% 10 == 0) {
      cat(sprintf(
        "\nFold %d, Epoch %d: training loss %1.4f, validation loss %1.4f, validation accuracy %1.4f\n",
        fold,
        epoch,
        mean(losses),
        mean(valid_losses),
        mean(valid_accuracies)
      ))
    }

    # Save best model for this fold
    if (mean(valid_accuracies) > accuracies[fold]) {
      message(glue::glue(
        "Fold {fold}: New best at epoch {epoch} ({round(mean(valid_accuracies), 3)}). Saving model"
      ))
      torch_save(model, glue::glue("models/best_model_{fold}.pt"))
      accuracies[fold] <- mean(valid_accuracies)
      best_epochs[fold] <- epoch
    }
  }
}
