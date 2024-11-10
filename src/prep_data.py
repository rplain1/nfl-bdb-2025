# %% [code]
"""
Data Preparation Module for NFL Big Data Bowl 2025

This module processes raw NFL tracking data to prepare it for machine learning models.
It includes functions for loading, cleaning, and transforming the data, as well as
splitting it into train, validation, and test sets.

Functions:
    get_players_df: Load and preprocess player data
    get_plays_df: Load and preprocess play data
    get_tracking_df: Load and preprocess tracking data
    add_features_to_tracking_df: Add derived features to tracking data
    convert_tracking_to_cartesian: Convert polar coordinates to Cartesian
    standardize_tracking_directions: Standardize play directions
    augment_mirror_tracking: Augment data by mirroring the field
    add_relative_positions: Add relative position features
    offenseFormation_df: Generate target dataframe offenseFormation prediction
    split_train_test_val: Split data into train, validation, and test sets
    main: Main execution function

"""

from argparse import ArgumentParser
from pathlib import Path
import nfl_data_py as nfl
import polars as pl

INPUT_DATA_DIR = Path("raw-data/")
OUT_DIR = Path("split_prepped_data/")


def get_nflverse_pbp() -> pl.DataFrame:
    return (
        pl.read_parquet("https://github.com/nflverse/nflverse-data/releases/download/pbp/play_by_play_2022.parquet")
        .with_columns(
            pl.col("old_game_id").cast(pl.Int64),
            pl.col("play_id").cast(pl.Int64),
            play_type_nflverse=pl.when(pl.col("pass") == 1)
            .then(pl.lit("pass"))
            .when(pl.col("rush") == 1)
            .then(pl.lit("run"))
            .otherwise(pl.lit(None)),
        )
        .rename({"old_game_id": "gameId", "play_id": "playId"})
    )


def get_players_df() -> pl.DataFrame:
    """
    Load player-level data and preprocesses features.

    Returns:
        pl.DataFrame: Preprocessed player data with additional features.
    """
    return (
        pl.read_csv(INPUT_DATA_DIR / "players.csv", null_values=["NA", "nan", "N/A", "NaN", ""])
        .with_columns(
            height_inches=(
                pl.col("height").str.split("-").map_elements(lambda s: int(s[0]) * 12 + int(s[1]), return_dtype=int)
            ),
        )
        .with_columns(
            weight_Z=(pl.col("weight") - pl.col("weight").mean()) / pl.col("weight").std(),
            height_Z=(pl.col("height_inches") - pl.col("height_inches").mean()) / pl.col("height_inches").std(),
        )
    )


def get_plays_df() -> pl.DataFrame:
    """
    Load play-level data and preprocesses features.

    Returns:
        pl.DataFrame: Preprocessed play data with additional features.
    """
    return pl.read_csv(INPUT_DATA_DIR / "plays.csv", null_values=["NA", "nan", "N/A", "NaN", ""]).with_columns(
        distanceToGoal=(
            pl.when(pl.col("possessionTeam") == pl.col("yardlineSide"))
            .then(100 - pl.col("yardlineNumber"))
            .otherwise(pl.col("yardlineNumber"))
        )
    )


def get_player_play_df() -> pl.DataFrame:
    """
    Load play-level data and preprocesses features.

    Returns:
        pl.DataFrame: Preprocessed play data with additional features.
    """
    return pl.read_csv(INPUT_DATA_DIR / "player_play.csv", null_values=["NA", "nan", "N/A", "NaN", ""]).with_columns(
        distanceToGoal=(
            pl.when(pl.col("possessionTeam") == pl.col("yardlineSide"))
            .then(100 - pl.col("yardlineNumber"))
            .otherwise(pl.col("yardlineNumber"))
        )
    )


def get_tracking_df() -> pl.DataFrame:
    """
    Load tracking data and preprocesses features. Notably, exclude rows representing the football's movement.

    Returns:
        pl.DataFrame: Preprocessed tracking data with additional features.
    """
    # don't include football rows for this project.
    # NOTE: Only processing week 1 for the sake of time.  Change "1" to "*" to process all weeks
    return pl.read_csv(INPUT_DATA_DIR / "tracking_week_1.csv", null_values=["NA", "nan", "N/A", "NaN", ""]).filter(
        pl.col("displayName") != "football"
    )


def add_features_to_tracking_df(
    tracking_df: pl.DataFrame, players_df: pl.DataFrame, plays_df: pl.DataFrame, nflverse_pbp_df: pl.DataFrame
) -> pl.DataFrame:
    """
    Consolidates play and player level data into the tracking data.

    Args:
        tracking_df (pl.DataFrame): Tracking data
        players_df (pl.DataFrame): Player data
        plays_df (pl.DataFrame): Play data

    Returns:
        pl.DataFrame: Tracking data with additional features.
    """
    # add `is_ball_carrier`, `team_indicator`, and other features to tracking data
    og_len = len(tracking_df)
    tracking_df = (
        tracking_df.join(
            nflverse_pbp_df.select("gameId", "playId", "play_type_nflverse"), on=["gameId", "playId"], how="left"
        )
        .join(
            plays_df.select(
                "gameId",
                "playId",
                "possessionTeam",
                "down",
                "yardsToGo",
            ),
            on=["gameId", "playId"],
            how="inner",
        )
        .join(
            players_df.select(["nflId", "weight_Z", "height_Z", "position"]).unique(),
            on="nflId",
            how="inner",
        )
        .with_columns(
            side=pl.when(pl.col("club") == pl.col("possessionTeam"))
            .then(pl.lit(1))
            .otherwise(pl.lit(-1))
            .alias("side"),
        )
        .drop(["possessionTeam"])
    )
    assert len(tracking_df) == og_len, "Lost rows when joining tracking data with play/player data"

    return tracking_df


def convert_tracking_to_cartesian(tracking_df: pl.DataFrame) -> pl.DataFrame:
    """
    Convert polar coordinates to Unit-circle Cartesian format.

    Args:
        tracking_df (pl.DataFrame): Tracking data

    Returns:
        pl.DataFrame: Tracking data with Cartesian coordinates.
    """
    return (
        tracking_df.with_columns(
            dir=((pl.col("dir") - 90) * -1) % 360,
            o=((pl.col("o") - 90) * -1) % 360,
        )
        # convert polar vectors to cartesian ((s, dir) -> (vx, vy), (o) -> (ox, oy))
        .with_columns(
            vx=pl.col("s") * pl.col("dir").radians().cos(),
            vy=pl.col("s") * pl.col("dir").radians().sin(),
            ox=pl.col("o").radians().cos(),
            oy=pl.col("o").radians().sin(),
        )
    )


def standardize_tracking_directions(tracking_df: pl.DataFrame) -> pl.DataFrame:
    """
    Standardize play directions to always moving left to right.

    Args:
        tracking_df (pl.DataFrame): Tracking data

    Returns:
        pl.DataFrame: Tracking data with standardized directions.
    """
    return tracking_df.with_columns(
        x=pl.when(pl.col("playDirection") == "right").then(pl.col("x")).otherwise(120 - pl.col("x")),
        y=pl.when(pl.col("playDirection") == "right").then(pl.col("y")).otherwise(53.3 - pl.col("y")),
        vx=pl.when(pl.col("playDirection") == "right").then(pl.col("vx")).otherwise(-1 * pl.col("vx")),
        vy=pl.when(pl.col("playDirection") == "right").then(pl.col("vy")).otherwise(-1 * pl.col("vy")),
        ox=pl.when(pl.col("playDirection") == "right").then(pl.col("ox")).otherwise(-1 * pl.col("ox")),
        oy=pl.when(pl.col("playDirection") == "right").then(pl.col("oy")).otherwise(-1 * pl.col("oy")),
    ).drop("playDirection")


def augment_mirror_tracking(tracking_df: pl.DataFrame) -> pl.DataFrame:
    """
    Augment data by mirroring the field assuming all plays are moving right.
    There are arguments to not do this as football isn't perfectly symmetric (e.g. most QBs are right-handed) but
    offenseFormation is mostly symmetrical and for the sake of this demo I think more data is more important.

    Args:
        tracking_df (pl.DataFrame): Tracking data

    Returns:
        pl.DataFrame: Augmented tracking data.
    """
    og_len = len(tracking_df)

    mirrored_tracking_df = tracking_df.clone().with_columns(
        # only flip y values
        y=53.3 - pl.col("y"),
        vy=-1 * pl.col("vy"),
        oy=-1 * pl.col("oy"),
        mirrored=pl.lit(True),
    )

    tracking_df = pl.concat(
        [
            tracking_df.with_columns(mirrored=pl.lit(False)),
            mirrored_tracking_df,
        ],
        how="vertical",
    )

    assert len(tracking_df) == og_len * 2, "Lost rows when mirroring tracking data"
    return tracking_df


def get_offenseFormation(tracking_df: pl.DataFrame, plays_df: pl.DataFrame) -> pl.DataFrame:
    """
    Generate target dataframe for offenseFormation prediction.

    Args:
        tracking_df (pl.DataFrame): Tracking data

    Returns:
        tuple: tuple containing offenseFormation coverage
    """

    # drop rows where offenseFormation is None
    plays_df = plays_df.filter(pl.col("offenseFormation").is_not_null())

    tracking_df = tracking_df.join(
        plays_df[["gameId", "playId", "offenseFormation"]],
        on=["gameId", "playId"],
        how="inner",
    )

    offenseFormation_df = (
        tracking_df[
            ["gameId", "playId", "mirrored", "frameId", "offenseFormation"]
        ].unique()  # Polars equivalent of drop_duplicates()
    )

    tracking_df = tracking_df.drop(["offenseFormation"])

    return offenseFormation_df, tracking_df


def get_play_type(tracking_df: pl.DataFrame) -> pl.DataFrame:
    """
    Generate target dataframe for offenseFormation prediction.

    Args:
        tracking_df (pl.DataFrame): Tracking data

    Returns:
        tuple: tuple containing offenseFormation coverage
    """

    # drop rows where offenseFormation is None
    tracking_df = tracking_df.filter(pl.col("play_type_nflverse").is_not_null())
    play_type_df = (
        tracking_df[
            ["gameId", "playId", "mirrored", "frameId", "play_type_nflverse"]
        ].unique()  # Polars equivalent of drop_duplicates()
    )  # Polars equivalent of drop_duplicates()

    tracking_df = tracking_df.drop(["play_type_nflverse"])

    return play_type_df, tracking_df


def split_train_test_val(tracking_df: pl.DataFrame, target_df: pl.DataFrame) -> dict[str, pl.DataFrame]:
    """
    Split data into train, validation, and test sets.
    Split is 70-15-15 for train-test-val respectively. Notably, we split at the play levle and not frame level.
    This ensures no target contamination between splits.

    Args:
        tracking_df (pl.DataFrame): Tracking data
        target_df (pl.DataFrame): Target data

    Returns:
        dict: Dictionary containing train, validation, and test dataframes.
    """
    tracking_df = tracking_df.sort(["gameId", "playId", "mirrored", "frameId"])
    target_df = target_df.sort(["gameId", "playId", "mirrored"])

    print(
        f"Total set: {tracking_df.n_unique(['gameId', 'playId', 'mirrored'])} plays,",
        f"{tracking_df.n_unique(['gameId', 'playId', 'mirrored', 'frameId'])} frames",
    )

    test_val_ids = tracking_df.select(["gameId", "playId"]).unique(maintain_order=True).sample(fraction=0.3, seed=42)
    train_tracking_df = tracking_df.join(test_val_ids, on=["gameId", "playId"], how="anti")
    train_tgt_df = target_df.join(test_val_ids, on=["gameId", "playId"], how="anti")
    print(
        f"Train set: {train_tracking_df.n_unique(['gameId', 'playId', 'mirrored'])} plays,",
        f"{train_tracking_df.n_unique(['gameId', 'playId', 'mirrored', 'frameId'])} frames",
    )

    test_ids = test_val_ids.sample(fraction=0.5, seed=42)  # 70-15-15 split
    test_tracking_df = tracking_df.join(test_ids, on=["gameId", "playId"], how="inner")
    test_tgt_df = target_df.join(test_ids, on=["gameId", "playId"], how="inner")
    print(
        f"Test set: {test_tracking_df.n_unique(['gameId', 'playId', 'mirrored'])} plays,",
        f"{test_tracking_df.n_unique(['gameId', 'playId', 'mirrored', 'frameId'])} frames",
    )

    val_ids = test_val_ids.join(test_ids, on=["gameId", "playId"], how="anti")
    val_tracking_df = tracking_df.join(val_ids, on=["gameId", "playId"], how="inner")
    val_tgt_df = target_df.join(val_ids, on=["gameId", "playId"], how="inner")
    print(
        f"Validation set: {val_tracking_df.n_unique(['gameId', 'playId', 'mirrored'])} plays,",
        f"{val_tracking_df.n_unique(['gameId', 'playId', 'mirrored', 'frameId'])} frames",
    )

    return {
        "train_features": train_tracking_df,
        "train_targets": train_tgt_df,
        "test_features": test_tracking_df,
        "test_targets": test_tgt_df,
        "val_features": val_tracking_df,
        "val_targets": val_tgt_df,
    }


def main():
    """
    Main execution function for data preparation.

    This function orchestrates the entire data preparation process, including:
    1. Loading raw data
    2. Adding features and transforming coordinates
    3. Generating target variables
    4. Splitting data into train, validation, and test sets
    5. Saving processed data to parquet files
    """
    print("Load players")
    players_df = get_players_df()
    print("Load plays")
    plays_df = get_plays_df()
    print("Load tracking")
    tracking_df = get_tracking_df()
    print("tracking_df rows:", len(tracking_df))
    print("Load nflverse")
    nflverse_pbp_df = get_nflverse_pbp()
    print("Add features to tracking")
    tracking_df = add_features_to_tracking_df(tracking_df, players_df, plays_df, nflverse_pbp_df)
    del players_df
    del nflverse_pbp_df
    print("Convert tracking to cartesian")
    tracking_df = convert_tracking_to_cartesian(tracking_df)
    print("Standardize play direction")
    tracking_df = standardize_tracking_directions(tracking_df)
    print("Augment data by mirroring")
    tracking_df = augment_mirror_tracking(tracking_df)

    print("Generate target - offenseFormation")
    # offenseFormation_df, rel_tracking_df = get_offenseFormation(tracking_df, plays_df)
    play_type_df, rel_tracking_df = get_play_type(tracking_df)
    print("Split train/test/val")
    # split_dfs = split_train_test_val(rel_tracking_df, offenseFormation_df)
    split_dfs = split_train_test_val(rel_tracking_df, play_type_df)
    out_dir = Path(OUT_DIR)
    out_dir.mkdir(exist_ok=True, parents=True)

    for key, df in split_dfs.items():
        sort_keys = ["gameId", "playId", "mirrored", "frameId"]
        df.sort(sort_keys).write_parquet(out_dir / f"{key}.parquet")


if __name__ == "__main__":
    main()
    # import os
    # import duckdb

    # with duckdb.connect(INPUT_DATA_DIR / "bdb.duckdb") as con:
    #     print(con.sql("select pff_defensiveCoverageAssignment, count(*) n from player_play group by 1 order by 2 desc"))
