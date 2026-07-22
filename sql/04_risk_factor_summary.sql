-- =====================================================================
-- CHAPTER 3 SUMMARY: Risk Factor Scan
-- Unions the strongest stratified comparison from each of 3A/3C/3D into
-- a single ranked table -- the closest this project's data and tools
-- can honestly get to answering "what predicted severe maternal
-- morbidity." Each row compares two groups *within the same delivery
-- method* (mostly cesarean), which is what makes them comparable to
-- each other -- see the individual 3A/3B/3C/3D files for the full
-- stratified breakdowns these are drawn from.
--
-- These are crude/unadjusted rate ratios (group rate / reference rate),
-- not an adjusted multivariate model -- each factor was tested one at
-- a time, not simultaneously. See README limitations section.
-- =====================================================================

WITH risk_factor_scan AS (

    -- From 3A: among mothers with a prior cesarean, does attempting a
    -- vaginal birth (VBAC) carry more risk than a planned repeat cesarean?
    SELECT
        'Prior cesarean: attempting vaginal birth (VBAC) vs. repeat cesarean' AS risk_factor,
        MAX(CASE WHEN grp = 'Vaginal (VBAC attempt)' THEN rate END) AS group_rate_pct,
        MAX(CASE WHEN grp = 'Cesarean (repeat)' THEN rate END) AS reference_rate_pct
    FROM (
        SELECT
            CASE WHEN dm.delivery_method_label = 'Vaginal' THEN 'Vaginal (VBAC attempt)'
                 ELSE 'Cesarean (repeat)' END AS grp,
            ROUND(100.0 * SUM(CASE WHEN ms.morbidity_label = 'At least one checked' THEN f.births ELSE 0 END)
                  / SUM(f.births), 3) AS rate
        FROM fact_morbidity_delivery_cesarean f
        JOIN dim_delivery_method dm ON dm.delivery_method_id = f.delivery_method_id
        JOIN dim_previous_cesarean pc ON pc.previous_cesarean_id = f.previous_cesarean_id
        JOIN dim_morbidity_status ms ON ms.morbidity_id = f.morbidity_id
        WHERE pc.previous_cesarean_label = 'Yes'
          AND dm.delivery_method_label IN ('Cesarean','Vaginal')
        GROUP BY grp
    )

    UNION ALL

    -- From 3C: among cesarean deliveries, does no prenatal care carry
    -- more risk than starting care in the 1st trimester?
    SELECT
        'No prenatal care vs. 1st-trimester care, among cesarean deliveries',
        MAX(CASE WHEN grp = 'No care' THEN rate END),
        MAX(CASE WHEN grp = 'Early' THEN rate END)
    FROM (
        SELECT
            CASE WHEN t.timing_label = 'No prenatal care' THEN 'No care'
                 WHEN t.timing_label IN ('1st month','2nd month','3rd month') THEN 'Early' END AS grp,
            ROUND(100.0 * SUM(CASE WHEN ms.morbidity_label = 'At least one checked' THEN f.births ELSE 0 END)
                  / SUM(f.births), 3) AS rate
        FROM fact_morbidity_prenatal_delivery f
        JOIN dim_prenatal_care_timing t ON t.prenatal_timing_id = f.prenatal_timing_id
        JOIN dim_delivery_method dm ON dm.delivery_method_id = f.delivery_method_id
        JOIN dim_morbidity_status ms ON ms.morbidity_id = f.morbidity_id
        WHERE dm.delivery_method_label = 'Cesarean'
          AND t.timing_label IN ('No prenatal care','1st month','2nd month','3rd month')
        GROUP BY grp
    )

    UNION ALL

    -- From 3D: among cesarean deliveries, does Medicaid carry more risk
    -- than Private Insurance?
    SELECT
        'Medicaid vs. Private Insurance, among cesarean deliveries',
        MAX(CASE WHEN grp = 'Medicaid' THEN rate END),
        MAX(CASE WHEN grp = 'Private Insurance' THEN rate END)
    FROM (
        SELECT
            p.payment_label AS grp,
            ROUND(100.0 * SUM(CASE WHEN ms.morbidity_label = 'At least one checked' THEN f.births ELSE 0 END)
                  / SUM(f.births), 3) AS rate
        FROM fact_morbidity_payment_delivery f
        JOIN dim_payment_source p ON p.payment_id = f.payment_id
        JOIN dim_delivery_method dm ON dm.delivery_method_id = f.delivery_method_id
        JOIN dim_morbidity_status ms ON ms.morbidity_id = f.morbidity_id
        WHERE p.payment_label IN ('Medicaid','Private Insurance')
          AND dm.delivery_method_label = 'Cesarean'
        GROUP BY p.payment_label
    )
)
SELECT
    risk_factor,
    group_rate_pct,
    reference_rate_pct,
    ROUND(group_rate_pct / reference_rate_pct, 2) AS rate_ratio,
    RANK() OVER (ORDER BY group_rate_pct / reference_rate_pct DESC) AS risk_rank
FROM risk_factor_scan
ORDER BY risk_rank;

-- RESULT:
-- 1. No prenatal care (vs. 1st-trimester care), among cesareans   -> 2.29x  (2.845% vs 1.242%)
-- 2. VBAC attempt (vs. repeat cesarean), prior-cesarean mothers   -> 1.79x  (2.222% vs 1.243%)
-- 3. Medicaid (vs. Private Insurance), among cesareans            -> 1.36x  (1.589% vs 1.168%)
--
-- Read together with Chapters 1 and 2, this is the project's central
-- finding: the single strongest predictor of severe morbidity found in
-- this data isn't a fixed clinical trait (age, BMI) -- it's the absence
-- of prenatal care, and that absence hits hardest specifically when it
-- ends in a cesarean delivery. That's the access -> intervention ->
-- outcome pathway the whole project was built to test, and the data
-- supports it.
