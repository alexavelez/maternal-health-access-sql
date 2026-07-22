-- =====================================================================
-- CHAPTER 3D: OUTCOME -- Severe Maternal Morbidity x Payment Source x
--             Delivery Method
-- Source: fact_morbidity_payment_delivery
-- This is the headline "access" cut of the outcome chapter -- does
-- insurance status predict severe morbidity?
-- =====================================================================

-- ---------------------------------------------------------------------
-- Marginal: morbidity rate by payment source alone.
-- ---------------------------------------------------------------------
SELECT
    p.payment_label,
    SUM(f.births) AS births,
    ROUND(100.0 * SUM(CASE WHEN ms.morbidity_label = 'At least one checked' THEN f.births ELSE 0 END)
          / SUM(f.births), 3) AS morbidity_rate_pct
FROM fact_morbidity_payment_delivery f
JOIN dim_payment_source p ON p.payment_id = f.payment_id
JOIN dim_morbidity_status ms ON ms.morbidity_id = f.morbidity_id
WHERE p.payment_label != 'Unknown or Not Stated'
GROUP BY p.payment_label
ORDER BY morbidity_rate_pct DESC;

-- Finding at first glance: Private Insurance shows the *highest* crude
-- morbidity rate (1.633%), ahead of Medicaid (1.224%) and Self Pay
-- (1.17%) -- which looks like it contradicts the project's whole access
-- thesis. It doesn't hold up once delivery method is added below --
-- this is a textbook case of why unstratified rates can mislead, and
-- exactly the reason this project scans each risk factor stratified by
-- a second variable rather than trusting a single marginal rate.


-- ---------------------------------------------------------------------
-- Stratified: morbidity rate by payment source, split by delivery
-- method.
-- ---------------------------------------------------------------------
SELECT
    p.payment_label,
    dm.delivery_method_label,
    SUM(f.births) AS births,
    ROUND(100.0 * SUM(CASE WHEN ms.morbidity_label = 'At least one checked' THEN f.births ELSE 0 END)
          / SUM(f.births), 3) AS morbidity_rate_pct
FROM fact_morbidity_payment_delivery f
JOIN dim_payment_source p ON p.payment_id = f.payment_id
JOIN dim_delivery_method dm ON dm.delivery_method_id = f.delivery_method_id
JOIN dim_morbidity_status ms ON ms.morbidity_id = f.morbidity_id
WHERE p.payment_label IN ('Medicaid','Private Insurance','Self Pay')
  AND dm.delivery_method_label IN ('Cesarean','Vaginal')
GROUP BY p.payment_label, dm.delivery_method_label
ORDER BY p.payment_label, dm.delivery_method_label;

-- Finding (headline of the whole project): the marginal rate above was
-- masking a genuine Simpson's-paradox-style reversal.
--   Medicaid:            Cesarean 1.589%   vs.  Vaginal 1.054%
--   Private Insurance:   Cesarean 1.168%   vs.  Vaginal 1.867%
--   Self Pay:             Cesarean 1.204%   vs.  Vaginal 1.163%
--
-- Within cesarean deliveries specifically, Medicaid mothers have the
-- HIGHEST morbidity rate of the three payment groups (1.589%) --
-- consistent with the access thesis. But Private Insurance's higher
-- *overall* rate (from the marginal query above) is being driven by
-- its much larger share of vaginal deliveries, where -- for reasons
-- this dataset alone can't fully explain (possible case-mix or
-- reporting differences by hospital type) -- Private Insurance shows
-- the highest rate of any payment/delivery combination in this table.
--
-- The honest read: payment source's relationship to severe morbidity
-- is not a single clean gradient -- it depends on delivery method, and
-- the two variables interact rather than one simply dominating. That
-- nuance is more defensible, and more interesting, than either "no
-- disparity exists" or "Medicaid mothers always fare worse" -- neither
-- of which the data actually supports on its own.
