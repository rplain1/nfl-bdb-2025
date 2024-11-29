import duckdb

con = duckdb.connect(database='data/bdb.duckdb')
con.execute(
    """
    DROP TABLE IF EXISTS tracking;
    CREATE TABLE tracking AS
    SELECT * FROM read_csv_auto('raw-data/tracking*.csv', nullstr='NA')
"""
)
con.execute(
    """
    DROP TABLE IF EXISTS player_play;
    CREATE TABLE player_play AS
    SELECT * FROM read_csv_auto('raw-data/player_play.csv', nullstr='NA')
"""
)
con.execute(
    """
    DROP TABLE IF EXISTS players;
    CREATE TABLE players AS
    SELECT * FROM read_csv_auto('raw-data/players.csv', nullstr='NA')
"""
)
con.execute(
    """
    DROP TABLE IF EXISTS plays;
    CREATE TABLE plays AS
    SELECT * FROM read_csv_auto('raw-data/plays.csv', nullstr='NA')
"""
)
con.execute(
    """
    DROP TABLE IF EXISTS games;
    CREATE TABLE games AS
    SELECT * FROM read_csv_auto('raw-data/games.csv', nullstr='NA')
"""
)

con.close()
