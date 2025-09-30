In `data.table`,

```
self$tgt_df[idx, 5]
```

was not working, it only returned `5`. I had to do:

```
target_col <- names(self$tgt_df)[ncol(self$tgt_df)]
self$tgt_df[idx, ..target_col]
```
