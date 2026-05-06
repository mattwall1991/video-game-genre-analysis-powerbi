-- ============================================
-- Video Game Genre Trend Analysis
-- Author: Matthew Wall
-- Database: DuckDB
-- ============================================

-- ============================================
-- 1. Load and Validate Source Data
-- ============================================

CREATE OR REPLACE TABLE games AS
SELECT *
FROM read_csv_auto('vgchartz-2024.csv');

-- Validate row count
SELECT COUNT(*) AS total_rows FROM games;

-- Check for nulls
SELECT
    COUNT(*) AS total_rows,
    SUM(CASE WHEN genre IS NULL THEN 1 ELSE 0 END) AS null_genre,
    SUM(CASE WHEN total_sales IS NULL THEN 1 ELSE 0 END) AS null_total_sales,
    SUM(CASE WHEN release_date IS NULL THEN 1 ELSE 0 END) AS null_release_date
FROM games;

-- ============================================
-- 2. Data Cleaning and Preparation
-- ============================================

CREATE VIEW games_clean AS
SELECT
    title,
    console,
    genre,
    publisher,
    developer,
    critic_score,
    total_sales,
    na_sales,
    jp_sales,
    pal_sales,
    other_sales,
    release_date,
    CAST(EXTRACT(YEAR FROM release_date) AS INTEGER) AS release_year
FROM games
WHERE release_date IS NOT NULL
  AND genre IS NOT NULL
  AND total_sales IS NOT NULL
  AND total_sales > 0;
  
  -- ============================================
-- 3. Aggregation and Feature Engineering
-- ============================================

-- Top 6 genres
CREATE VIEW top_genres AS
SELECT genre
FROM (
    SELECT genre, SUM(total_sales) AS total_sales_millions
    FROM games_clean
    GROUP BY genre
    ORDER BY total_sales_millions DESC
    LIMIT 6
);

-- Yearly sales by genre
CREATE VIEW genre_year_sales AS
SELECT
    g.release_year,
    g.genre,
    SUM(g.total_sales) AS yearly_genre_sales_millions
FROM games_clean g
JOIN top_genres t ON g.genre = t.genre
GROUP BY g.release_year, g.genre;

-- ============================================
-- 4. Growth and Time-Series Metrics
-- ============================================

-- Year-over-year growth
CREATE VIEW genre_year_growth AS
SELECT
    release_year,
    genre,
    yearly_genre_sales_millions,
    LAG(yearly_genre_sales_millions) OVER (
        PARTITION BY genre ORDER BY release_year
    ) AS prior_year_sales_millions,
    CASE
        WHEN prior_year_sales_millions IS NULL OR prior_year_sales_millions = 0 THEN NULL
        ELSE (
            (yearly_genre_sales_millions - prior_year_sales_millions)
            / prior_year_sales_millions
        ) * 100
    END AS yoy_growth_pct
FROM genre_year_sales;

-- Rolling 3-year average
CREATE VIEW genre_year_rolling_avg AS
SELECT
    release_year,
    genre,
    AVG(yearly_genre_sales_millions) OVER (
        PARTITION BY genre
        ORDER BY release_year
        ROWS BETWEEN 2 PRECEDING AND CURRENT ROW
    ) AS rolling_3yr_avg_sales_millions
FROM genre_year_sales;

-- ============================================
-- 5. Volatility and Summary Metrics
-- ============================================

-- Volatility
CREATE VIEW genre_volatility AS
SELECT
    genre,
    STDDEV_SAMP(yearly_genre_sales_millions) AS sales_volatility_millions
FROM genre_year_sales
GROUP BY genre;

-- Final scorecard
CREATE VIEW genre_scorecard AS
SELECT
    s.genre,
    SUM(s.yearly_genre_sales_millions) AS total_sales_millions,
    AVG(s.yearly_genre_sales_millions) AS avg_yearly_sales_millions,
    AVG(g.yoy_growth_pct) AS avg_yoy_growth_pct,
    STDDEV_SAMP(s.yearly_genre_sales_millions) AS sales_volatility_millions
FROM genre_year_sales s
LEFT JOIN genre_year_growth g
    ON s.genre = g.genre
   AND s.release_year = g.release_year
GROUP BY s.genre;

-- ============================================
-- 6. Final Output Tables
-- ============================================

SELECT * FROM genre_year_sales;
SELECT * FROM genre_year_growth;
SELECT * FROM genre_year_rolling_avg;
SELECT * FROM genre_scorecard;
SELECT * FROM genre_volatility;

