-- =====================================================================
-- CHAPTER 2: INTERVENTION
-- Who ends up with a cesarean, and what predicts it?
-- Source: fact_delivery_risk (Year x State x Delivery Method x
--         Previous Cesarean x Pre-pregnancy BMI, 2019-2024)
-- Note: "Unknown or Not Stated" delivery-method births are excluded from
-- rate denominators throughout, so rates reflect known-outcome births only.
-- =====================================================================

-- ---------------------------------------------------------------------
-- Q1. National cesarean rate trend by year.
-- ---------------------------------------------------------------------
SELECT
    y.year_id,
    ROUND(100.0 * SUM(CASE WHEN dm.delivery_method_label = 'Cesarean' THEN f.births ELSE 0 END)
          / SUM(CASE WHEN dm.delivery_method_label IN ('Cesarean','Vaginal') THEN f.births ELSE 0 END), 2) AS cesarean_rate_pct
FROM fact_delivery_risk f
JOIN dim_year y ON y.year_id = f.year_id
JOIN dim_delivery_method dm ON dm.delivery_method_id = f.delivery_method_id
GROUP BY y.year_id
ORDER BY y.year_id;

-- Finding: steady climb -- 31.68% (2019) to 32.38% (2024).
-- Not a COVID-era spike; a slow multi-year drift upward.


-- ---------------------------------------------------------------------
-- Q2. Cesarean rate by pre-pregnancy BMI category.
-- ---------------------------------------------------------------------
SELECT
    b.bmi_label,
    ROUND(100.0 * SUM(CASE WHEN dm.delivery_method_label = 'Cesarean' THEN f.births ELSE 0 END)
          / SUM(CASE WHEN dm.delivery_method_label IN ('Cesarean','Vaginal') THEN f.births ELSE 0 END), 2) AS cesarean_rate_pct
FROM fact_delivery_risk f
JOIN dim_bmi_category b ON b.bmi_id = f.bmi_id
JOIN dim_delivery_method dm ON dm.delivery_method_id = f.delivery_method_id
GROUP BY b.bmi_label
ORDER BY b.sort_order;

-- Finding (headline): a clean, monotonic dose-response relationship.
--   Underweight        -> 20.89%
--   Normal              -> 25.36%
--   Overweight           -> 31.79%
--   Obesity I            -> 37.35%
--   Obesity II            -> 43.03%
--   Extreme Obesity III   -> 52.12%
-- Cesarean rate roughly doubles from Underweight to Obesity I, and more
-- than doubles again by Extreme Obesity III -- over half of extremely
-- obese mothers deliver via cesarean, vs. roughly 1 in 4 at normal BMI.


-- ---------------------------------------------------------------------
-- Q3. Cesarean rate by prior-cesarean history -- the VBAC angle.
-- ---------------------------------------------------------------------
SELECT
    pc.previous_cesarean_label,
    SUM(CASE WHEN dm.delivery_method_label IN ('Cesarean','Vaginal') THEN f.births ELSE 0 END) AS known_delivery_births,
    ROUND(100.0 * SUM(CASE WHEN dm.delivery_method_label = 'Cesarean' THEN f.births ELSE 0 END)
          / SUM(CASE WHEN dm.delivery_method_label IN ('Cesarean','Vaginal') THEN f.births ELSE 0 END), 2) AS cesarean_rate_pct
FROM fact_delivery_risk f
JOIN dim_previous_cesarean pc ON pc.previous_cesarean_id = f.previous_cesarean_id
JOIN dim_delivery_method dm ON dm.delivery_method_id = f.delivery_method_id
GROUP BY pc.previous_cesarean_label;

-- Finding: 85.51% of mothers with a prior cesarean have another one,
-- vs. 22.33% of those without prior-cesarean history -- consistent with
-- the well-documented low VBAC (vaginal birth after cesarean) uptake
-- in the US, a long-standing ACOG policy concern. "Once a cesarean,
-- almost always a cesarean" shows up clearly in this data.


-- ---------------------------------------------------------------------
-- Q4. State-level variation -- top 5 and bottom 5 by cesarean rate.
--     Window function: two RANK() calls (descending and ascending)
--     let one query surface both ends of the distribution at once.
-- ---------------------------------------------------------------------
WITH state_rates AS (
    SELECT
        s.state_name,
        ROUND(100.0 * SUM(CASE WHEN dm.delivery_method_label = 'Cesarean' THEN f.births ELSE 0 END)
              / SUM(CASE WHEN dm.delivery_method_label IN ('Cesarean','Vaginal') THEN f.births ELSE 0 END), 2) AS cesarean_rate_pct
    FROM fact_delivery_risk f
    JOIN dim_state s ON s.state_id = f.state_id
    JOIN dim_delivery_method dm ON dm.delivery_method_id = f.delivery_method_id
    GROUP BY s.state_name
),
ranked AS (
    SELECT *,
        RANK() OVER (ORDER BY cesarean_rate_pct DESC) AS rank_high,
        RANK() OVER (ORDER BY cesarean_rate_pct ASC) AS rank_low
    FROM state_rates
)
SELECT state_name, cesarean_rate_pct, rank_high
FROM ranked
WHERE rank_high <= 5 OR rank_low <= 5
ORDER BY cesarean_rate_pct DESC;

-- Finding: a 15-point spread nationally (23.04% Alaska to 38.25%
-- Mississippi; national average 30.89%). The five highest-rate states
-- -- Mississippi, Louisiana, Florida, Connecticut, Georgia -- notably
-- overlap with several of the slowest / non-Medicaid-expansion states
-- from Chapter 1's access findings. Worth revisiting once a Medicaid
-- expansion status lookup is joined in, to see if that overlap holds
-- up as a real pattern rather than coincidence.
