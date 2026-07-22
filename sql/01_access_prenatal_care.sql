-- =====================================================================
-- CHAPTER 1: ACCESS
-- Who gets prenatal care, when, and how much?
-- Source: fact_prenatal_care_access (Year x Census Division x Age of
--         Mother x Payment Source x Month Prenatal Care Began, 2019-2024)
-- =====================================================================

-- ---------------------------------------------------------------------
-- Q1. National trend: % of births where prenatal care began in the
--     1st trimester (months 1-3), by year.
--     Frames the COVID-19 disruption narrative: did care-seeking
--     behavior change, and did it recover?
-- ---------------------------------------------------------------------
WITH yearly_timing AS (
    SELECT
        y.year_id,
        SUM(CASE WHEN t.timing_label IN ('1st month','2nd month','3rd month')
                 THEN f.births ELSE 0 END) AS first_trimester_births,
        SUM(f.births) AS total_births
    FROM fact_prenatal_care_access f
    JOIN dim_year y ON y.year_id = f.year_id
    JOIN dim_prenatal_care_timing t ON t.prenatal_timing_id = f.prenatal_timing_id
    GROUP BY y.year_id
)
SELECT
    year_id,
    ROUND(100.0 * first_trimester_births / total_births, 2) AS pct_first_trimester_care
FROM yearly_timing
ORDER BY year_id;

-- Finding: 1st-trimester care initiation held steady through the pandemic
-- (75.9% in 2019, 76.75% in 2021) but has since eroded to 74.09% by 2024
-- -- a slow decline, not a one-year COVID dip. Worth flagging as an
-- ongoing trend rather than a pandemic-era anomaly.


-- ---------------------------------------------------------------------
-- Q2. Access by payment source -- the headline disparity cut.
--     Compares 1st-trimester care initiation and complete lack of
--     prenatal care, across Medicaid / Private Insurance / Self Pay.
-- ---------------------------------------------------------------------
WITH payment_timing AS (
    SELECT
        p.payment_label,
        SUM(CASE WHEN t.timing_label = 'No prenatal care'
                 THEN f.births ELSE 0 END) AS no_care_births,
        SUM(CASE WHEN t.timing_label IN ('1st month','2nd month','3rd month')
                 THEN f.births ELSE 0 END) AS first_tri_births,
        SUM(f.births) AS total_births
    FROM fact_prenatal_care_access f
    JOIN dim_payment_source p ON p.payment_id = f.payment_id
    JOIN dim_prenatal_care_timing t ON t.prenatal_timing_id = f.prenatal_timing_id
    WHERE p.payment_label != 'Unknown or Not Stated'
    GROUP BY p.payment_label
)
SELECT
    payment_label,
    ROUND(100.0 * first_tri_births / total_births, 2) AS pct_first_trimester_care,
    ROUND(100.0 * no_care_births / total_births, 3) AS pct_no_prenatal_care
FROM payment_timing
ORDER BY pct_first_trimester_care DESC;

-- Finding (headline): a clear access gradient by payment source.
--   Private Insurance -> 84.96% start in 1st trimester, only 0.88% get no care
--   Medicaid          -> 66.34% start in 1st trimester, 2.92% get no care  (3.3x Private's rate)
--   Self Pay          -> 52.77% start in 1st trimester, 7.57% get no care  (8.6x Private's rate)
-- This is the single clearest quantitative expression of the project's
-- access thesis: insurance status predicts how early -- or whether --
-- prenatal care begins.


-- ---------------------------------------------------------------------
-- Q3. Access by maternal age -- the teen-pregnancy access angle.
-- ---------------------------------------------------------------------
SELECT
    a.age_label,
    SUM(f.births) AS total_births,
    ROUND(100.0 * SUM(CASE WHEN t.timing_label = 'No prenatal care'
                           THEN f.births ELSE 0 END) / SUM(f.births), 3) AS pct_no_care,
    ROUND(AVG(f.avg_prenatal_visits), 2) AS avg_visits
FROM fact_prenatal_care_access f
JOIN dim_age_group a ON a.age_group_id = f.age_group_id
JOIN dim_prenatal_care_timing t ON t.prenatal_timing_id = f.prenatal_timing_id
WHERE f.avg_prenatal_visits IS NOT NULL
GROUP BY a.age_label
ORDER BY a.sort_order;

-- Finding: mothers under 15 have a 9.58% no-care rate -- roughly 5x the
-- rate of mothers in their late 20s/early 30s (~2%), and by far the
-- highest of any age group. Access to care is worst exactly where
-- clinical risk (adolescent pregnancy) is highest.
-- Caveat: the youngest (<15) and oldest (50+) age bands have very small
-- underlying birth counts nationally, so their rates are more volatile
-- year-to-year than the middle age bands -- worth noting, not excluding.


-- ---------------------------------------------------------------------
-- Q4. Regional variation in care adequacy, split by payment source.
--     Window function: ranks each census division's average prenatal
--     visit count separately within Medicaid and within Private
--     Insurance, so regions can be compared on equal footing.
-- ---------------------------------------------------------------------
WITH division_payment AS (
    SELECT
        d.division_name,
        p.payment_label,
        ROUND(AVG(f.avg_prenatal_visits), 2) AS avg_visits
    FROM fact_prenatal_care_access f
    JOIN dim_census_division d ON d.division_id = f.division_id
    JOIN dim_payment_source p ON p.payment_id = f.payment_id
    WHERE f.avg_prenatal_visits IS NOT NULL
      AND p.payment_label IN ('Medicaid','Private Insurance')
    GROUP BY d.division_name, p.payment_label
)
SELECT
    division_name,
    payment_label,
    avg_visits,
    RANK() OVER (PARTITION BY payment_label ORDER BY avg_visits DESC) AS rank_within_payment_type
FROM division_payment
ORDER BY payment_label, rank_within_payment_type;

-- Finding: the Medicaid-vs-Private gap in average visit count holds
-- within *every* census division -- it's not explained away by any one
-- region. West South Central (AR, LA, OK, TX) ranks last for both
-- payment types, suggesting a regional access floor on top of the
-- payment-source gap.
