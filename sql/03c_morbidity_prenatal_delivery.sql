-- =====================================================================
-- CHAPTER 3C: OUTCOME -- Severe Maternal Morbidity x Prenatal Care
--             Timing x Delivery Method
-- Source: fact_morbidity_prenatal_delivery
-- =====================================================================

-- ---------------------------------------------------------------------
-- Marginal: morbidity rate by month prenatal care began.
-- ---------------------------------------------------------------------
SELECT
    t.timing_label,
    SUM(f.births) AS births,
    ROUND(100.0 * SUM(CASE WHEN ms.morbidity_label = 'At least one checked' THEN f.births ELSE 0 END)
          / SUM(f.births), 3) AS morbidity_rate_pct
FROM fact_morbidity_prenatal_delivery f
JOIN dim_prenatal_care_timing t ON t.prenatal_timing_id = f.prenatal_timing_id
JOIN dim_morbidity_status ms ON ms.morbidity_id = f.morbidity_id
GROUP BY t.timing_label
ORDER BY t.sort_order;

-- Finding: "No prenatal care" shows the 2nd-highest rate of any timing
-- category (1.636%). Rates then generally decline the later care began
-- (peaking again mid-pregnancy, tapering by month 8-9) -- but this
-- marginal view mixes together very different populations (why someone
-- has zero prenatal care varies enormously). The real signal shows up
-- once delivery method is added below.


-- ---------------------------------------------------------------------
-- Stratified: no prenatal care vs. early (1st-trimester) care, split
-- by delivery method -- tests whether lack of care compounds risk
-- specifically for cesarean deliveries.
-- ---------------------------------------------------------------------
SELECT
    CASE WHEN t.timing_label = 'No prenatal care' THEN 'No care'
         WHEN t.timing_label IN ('1st month','2nd month','3rd month') THEN 'Early (1st trimester)'
    END AS care_group,
    dm.delivery_method_label,
    SUM(f.births) AS births,
    ROUND(100.0 * SUM(CASE WHEN ms.morbidity_label = 'At least one checked' THEN f.births ELSE 0 END)
          / SUM(f.births), 3) AS morbidity_rate_pct
FROM fact_morbidity_prenatal_delivery f
JOIN dim_prenatal_care_timing t ON t.prenatal_timing_id = f.prenatal_timing_id
JOIN dim_delivery_method dm ON dm.delivery_method_id = f.delivery_method_id
JOIN dim_morbidity_status ms ON ms.morbidity_id = f.morbidity_id
WHERE dm.delivery_method_label IN ('Cesarean','Vaginal')
  AND t.timing_label IN ('No prenatal care','1st month','2nd month','3rd month')
GROUP BY care_group, dm.delivery_method_label
ORDER BY care_group, dm.delivery_method_label;

-- Finding (headline of this chapter): "No care + Cesarean" is the
-- single highest morbidity rate found anywhere in this project --
-- 2.845%, more than double the 1.242% rate for "Early care + Cesarean."
-- For vaginal delivery, the pattern doesn't hold the same way: "No
-- care + Vaginal" (1.162%) is actually *lower* than "Early care +
-- Vaginal" (1.553%) -- likely reflecting that the "no prenatal care +
-- vaginal" group includes unplanned/precipitous deliveries with little
-- time for any intervention to go wrong, a different population than
-- "no care + ends up needing a cesarean," which likely signals a
-- complication serious enough to require surgery with no prior
-- monitoring in place. That combination -- no prenatal care, followed
-- by an unplanned cesarean -- is exactly the access-to-outcome pathway
-- this project set out to investigate.
