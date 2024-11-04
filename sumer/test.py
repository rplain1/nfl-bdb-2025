import sumer.prep_data as prep
import sumer.process_datasets as process

plays_df = prep.get_plays_df()

# Model parameters
feature_len = 5  # Adjust this as needed based on input data
model_dim = 64  # Dimension of transformer model (adjustable)
num_layers = 4  # Number of transformer layers (adjustable)
dropout = 0.01
learning_rate = 1e-3
batch_size = 64
output_dim =  plays_df.to_pandas()['offenseFormation'].nunique()

prep.main()
process.main()

import torch
from torch.utils.data import DataLoader
from sumer.process_datasets import load_datasets

# Load preprocessed datasets
train_dataset = load_datasets(model_type='transformer', split='train')
val_dataset = load_datasets(model_type='transformer', split='val')
test_dataset = load_datasets(model_type='transformer', split='test')

# Create DataLoader objects
batch_size = 64
train_loader = DataLoader(train_dataset, batch_size=batch_size, shuffle=True, num_workers=3)
val_loader = DataLoader(val_dataset, batch_size=batch_size, num_workers=3)
test_loader = DataLoader(test_dataset, batch_size=64, shuffle=False, num_workers=3)

# Print feature and target shapes from DataLoaders
for batch in train_loader:
    features, targets = batch
    print("Train features shape:", features.shape)
    print("Train targets shape:", targets.shape)
    break


from sumer.models import SportsTransformerLitModel
# Initialize the model
model = SportsTransformerLitModel(
    feature_len=feature_len,
    batch_size=batch_size,
    model_dim=model_dim,
    num_layers=num_layers,
    output_dim=output_dim,
    dropout=dropout,
    learning_rate=learning_rate,
)


from pytorch_lightning import Trainer
from pytorch_lightning.callbacks import ModelCheckpoint, EarlyStopping
from pathlib import Path

# Define checkpointing to save the best model
checkpoint_callback = ModelCheckpoint(
   dirpath=Path("checkpoints/"),
   filename="best-checkpoint",
   save_top_k=1,
   verbose=True,
   monitor="val_loss",
   mode="min",
)

# Define early stopping
early_stop_callback = EarlyStopping(
   monitor="val_loss",
   min_delta=0.01,  # Minimum change in monitored value to qualify as an improvement
   patience=3,      # Number of epochs with no improvement after which training will be stopped
   verbose=True,
   mode="min"
)

# Initialize the trainer
trainer = Trainer(
   max_epochs=20,  # Adjust the number of epochs
   accelerator="gpu",  # Use 'gpu' if CUDA is available, otherwise use 'cpu'
   devices=1,
   callbacks=[checkpoint_callback, early_stop_callback],
)

# Start training
trainer.fit(model, train_loader, val_loader)

predictions = trainer.predict(model, test_loader)


# Concatenate predictions into a single tensor
predictions_tensor = torch.cat(predictions, dim=0)

# Assuming predictions are logits for a multi-class problem
predicted_labels = torch.argmax(predictions_tensor, dim=1)

import numpy as np

# Extract true labels from the test_loader
y_true = torch.cat([y for _, y in test_loader], dim=0)

# Convert tensors to numpy arrays if needed for sklearn functions
y_true_np = np.argmax(y_true.cpu().numpy(), axis=-1)
predicted_labels_np = predicted_labels.cpu().numpy()

print("y_true shape:", y_true_np.shape)
print("Predicted labels shape:", predicted_labels_np.shape)
import pandas as pd

# Create a test dataframe
df_test = pd.DataFrame({
    'gameId': [key[0] for key in test_dataset.keys],
    'playId': [key[1] for key in test_dataset.keys],
    'mirrored': [key[2] for key in test_dataset.keys],
    'frameId': [key[3] for key in test_dataset.keys],
    'true_labels': y_true_np,
    'predicted_labels': predicted_labels_np
})

# Attach metadata and filter to ball_snap event only
df_test_metadata = pd.read_parquet('split_prepped_data/test_features.parquet')

df_test = df_test.merge(df_test_metadata[["gameId", "playId", "mirrored", "frameId", "event", "frameType"]], on=["gameId", "playId", "mirrored", "frameId"], how="left")

# Remove frame after the snap
df_test_before_snap = df_test[df_test.frameType == "BEFORE_SNAP"]

# Filter to ball_snap event for evaluation
df_test_ball_snap = df_test[df_test.event == "ball_snap"]

df_test_ball_snap = df_test_ball_snap.drop_duplicates(subset=['gameId', 'playId', 'mirrored', 'frameId'])

df_test_ball_snap = df_test_ball_snap.sort_values(['gameId', 'playId', 'mirrored', 'frameId']).reset_index(drop=True)

true_labels = df_test_ball_snap['true_labels'].values
predicted_labels = df_test_ball_snap['predicted_labels'].values




from sklearn.metrics import accuracy_score, precision_score, recall_score, f1_score, confusion_matrix
import seaborn as sns
import matplotlib.pyplot as plt
plt.rcParams['font.family'] = 'Times New Roman'

# Get class labels from FORMATION_ENUM and sort alphabetically
formation_labels = sorted(list(process_datasets.FORMATION_ENUM.keys()))

# Print unique values to debug
print("Unique values in true labels:", np.unique(true_labels))
print("Unique values in predicted labels:", np.unique(predicted_labels))
print("Formation enum values:", process_datasets.FORMATION_ENUM)




from sklearn.metrics import accuracy_score, precision_score, recall_score, f1_score, confusion_matrix
import seaborn as sns
import matplotlib.pyplot as plt
plt.rcParams['font.family'] = 'Times New Roman'

# Get class labels from FORMATION_ENUM and sort alphabetically
formation_labels = sorted(list(process.FORMATION_ENUM.keys()))

# Print unique values to debug
print("Unique values in true labels:", np.unique(true_labels))
print("Unique values in predicted labels:", np.unique(predicted_labels))
print("Formation enum values:", process.FORMATION_ENUM)

# Calculate metrics using labels parameter to specify valid classes
accuracy = accuracy_score(true_labels, predicted_labels)
precision = precision_score(true_labels, predicted_labels, average='weighted',
                         labels=np.unique(true_labels))
recall = recall_score(true_labels, predicted_labels, average='weighted',
                    labels=np.unique(true_labels))
f1 = f1_score(true_labels, predicted_labels, average='weighted',
             labels=np.unique(true_labels))

# Create confusion matrix only for classes that appear in the data
present_classes = sorted(list(set(np.unique(true_labels)) | set(np.unique(predicted_labels))))
conf_matrix = confusion_matrix(true_labels, predicted_labels,
                            labels=present_classes)

# Get labels for present classes
present_labels = [formation_labels[i] for i in present_classes]

# Print metrics
print(f"Accuracy: {accuracy:.4f}")
print(f"Precision (weighted): {precision:.4f}")
print(f"Recall (weighted): {recall:.4f}")
print(f"F1 Score (weighted): {f1:.4f}")


# Plot confusion matrix with labels for present classes
plt.figure(figsize=(7, 6))
sns.heatmap(conf_matrix,
          annot=True,
          fmt='d',
          cmap='Blues',
          xticklabels=present_labels,
          yticklabels=present_labels)
plt.title('Confusion Matrix')
plt.xlabel('Predicted')
plt.ylabel('True')
plt.xticks(rotation=45)
plt.yticks(rotation=45)
plt.tight_layout()
plt.show()



# Show example play
df_play = df_test_before_snap[((df_test_before_snap.playId == 191) & (df_test_before_snap.mirrored == False))]

df_tracking_test = pd.read_parquet('/kaggle/working/split_prepped_data/test_features.parquet')
df_example_play = df_tracking_test[((df_tracking_test.playId == 191) & (df_tracking_test.mirrored == False))]
df_example_play = df_example_play[df_example_play.frameType == "BEFORE_SNAP"]
df_example_play = df_example_play.merge(df_play[["gameId", "playId", "mirrored", "frameId", "predicted_labels"]], on=["gameId", "playId", "mirrored", "frameId"], how="left").reset_index()
display(df_example_play)
