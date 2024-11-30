library(data.table)
library(torch)
set.seed(527)
torch_manual_seed(527)

source('R/prep_data.R')
source('R/process_data.R')
source('R/models.R')
prep_data()
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

train_loader <- torch::dataloader(readRDS('datasets/R/train_dataset.rds'), batch_size =  64, shuffle = TRUE)
val_loader <- torch::dataloader(readRDS('datasets/R/val_dataset.rds'), batch_size =  64, shuffle = TRUE)

#accuracies <- torch_zeros(length(folds))
#best_epochs <- torch_zeros(length(folds))

epochs <- 50

optimizer <- optim_adam(model$parameters, lr = 0.001)
scheduler <- lr_step(optimizer, step_size = 1, 0.975)

for (epoch in 1:epochs) {
  message(epoch)
  losses <- c()
  valid_losses <- c()
  valid_accuracies <- c()
  # train step: loop over batches
  model$train()
  coro::loop(for(b in train_loader) {
    cat('\n', dim(b))
    optimizer$zero_grad()
    loss <- nnf_cross_entropy(model(b$features), torch_squeeze(b$target))
    loss$backward()
    optimizer$step()
    losses <- c(losses, loss$item())
  })
  message('train complete')
  # validation step: loop over batches
  model$eval()
  coro::loop(for(b in val_loader) {
    output <- model(b$features)

    valid_losses <- c(valid_losses, nnf_cross_entropy(output, torch_squeeze(b$target))$item())

    pred <- torch_max(output, dim = 2)[[2]]
    correct <- (pred == b$features)$sum()$item()
    valid_accuracies <- c(valid_accuracies, correct / length(b$target))
  })

  scheduler$step()

  if (epoch %% 10 == 0) {
    cat(sprintf("\nLoss at epoch %d: training: %1.4f, validation: %1.4f // validation accuracy %1.4f", epoch, mean(losses), mean(valid_losses), mean(valid_accuracies)))
  }
  break
  # if (mean(valid_accuracies) > as.numeric(accuracies[fold])) {
  #   message(glue::glue("Fold {fold}: New best at epoch {epoch} ({round(mean(valid_accuracies), 3)}). Saving model"))

  #   torch_save(model, glue::glue("best_model_{fold}.pt"))

  #   # save new best loss
  #   accuracies[fold] <- mean(valid_accuracies)
  #   best_epochs[fold] <- epoch
  # }
}
