import duckdb
from globals.globals import DB_PATH

con = duckdb.connect(DB_PATH)
con.sql("select count(*) from tracking")
