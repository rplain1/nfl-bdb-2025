import duckdb
import polars as pl
import os
import glob

PATH = 'raw-data/*.csv'
files = glob.glob(PATH)


{
    'games':"raw-data/games.csv",
    'player_play': "raw-data/player_play.csv",
    'players': "raw-data/players.csv",
    'plays': "raw-data/plays.csv",
    'tracking': "raw-data/tracking_*.csv",
}


con = duckdb.connect(database='data/bdb.duckdb')
con.execute(
    """
    DROP TABLE IF EXISTS tracking;
    CREATE TABLE tracking AS
    SELECT * FROM read_csv_auto('raw-data/tracking*.csv')
"""
)
con.execute(
    """
    DROP TABLE IF EXISTS player_play;
    CREATE TABLE player_play AS
    SELECT * FROM read_csv_auto('raw-data/player_play.csv')
"""
)
con.execute(
    """
    DROP TABLE IF EXISTS players;
    CREATE TABLE players AS
    SELECT * FROM read_csv_auto('raw-data/players.csv')
"""
)
con.execute(
    """
    DROP TABLE IF EXISTS plays;
    CREATE TABLE plays AS
    SELECT * FROM read_csv_auto('raw-data/plays.csv')
"""
)
con.execute(
    """
    DROP TABLE IF EXISTS games;
    CREATE TABLE games AS
    SELECT * FROM read_csv_auto('raw-data/games.csv')
"""
)

con.close()
