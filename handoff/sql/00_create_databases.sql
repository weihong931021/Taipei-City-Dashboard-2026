-- Run this AS the postgres superuser BEFORE applying the per-database files.
-- Creates the two databases the BE talks to + enables PostGIS in dashboarddb
-- (needed for the AI spatial tools — restaurants / ev_stations geography column).

CREATE DATABASE dashboarddb;
CREATE DATABASE dashboardmanagerdb;

-- PostGIS in dashboarddb (host: psql -d dashboarddb -f 03_ai_tools_schema.sql
-- will also CREATE EXTENSION IF NOT EXISTS, so this line is for clarity).
\c dashboarddb
CREATE EXTENSION IF NOT EXISTS postgis;
