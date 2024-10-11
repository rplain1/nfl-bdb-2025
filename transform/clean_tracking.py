import duckdb
from globals.globals import DB_PATH

con = duckdb.connect(DB_PATH)
con.sql("select count(*) from tracking")

statement = """
DROP TABLE IF EXISTS tracking_clean;
CREATE TABLE tracking_clean AS
WITH tracking_windowed AS (
    SELECT
        *,
        -- Calculate x_std and y_std based on playDirection
        CASE WHEN playDirection = 'left' THEN 120 - x ELSE x END AS x_std,
        CASE WHEN playDirection = 'left' THEN 160 / y ELSE y END AS y_std,
        -- Calculate x_start as the football's initial x position (at frameId = 1)
        MIN(CASE WHEN club = 'football' AND frameId = 1 THEN x ELSE NULL END) OVER (PARTITION BY gameId, playId) AS x_start,
        -- Standardize the orientation and direction
        CASE WHEN playDirection = 'left' THEN abs(o - 180) ELSE o END AS o_std,
        CASE WHEN playDirection = 'left' THEN abs(dir - 180) ELSE dir END AS dir_std
    FROM tracking
),
tracking_final AS (
    SELECT
        *,
        -- Adjusted x_std (subtracting x_start) and y_std
        x_std - x_start AS x_adj,
        -- Calculate x_end and y_end based on the direction and speed
        s * COS((90 - dir_std) * (pi() / 180)) + (x_std - x_start) AS x_end,
        s * SIN((90 - dir_std) * (pi() / 180)) + y_std AS y_end,
        -- Calculate ball position (x_ball and y_ball) separately
        MIN(CASE WHEN club = 'football' THEN x_std - x_start ELSE NULL END) OVER (PARTITION BY gameId, playId, frameId) AS x_ball,
        MIN(CASE WHEN club = 'football' THEN y_std ELSE NULL END) OVER (PARTITION BY gameId, playId, frameId) AS y_ball
    FROM tracking_windowed
)
SELECT
    *,
    -- Calculate distance to the ball
    SQRT(POW(x_adj - x_ball, 2) + POW(y_std - y_ball, 2)) AS distance_to_ball
FROM tracking_final;
"""

con.execute(statement)
