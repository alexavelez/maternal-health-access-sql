-- =====================================================================
-- CHAPTER 3B: OUTCOME -- Severe Maternal Morbidity x Maternal Age x
--             Pre-pregnancy BMI
-- Source: fact_morbidity_age_bmi
-- =====================================================================

-- ---------------------------------------------------------------------
-- Marginal: morbidity rate by age group alone.
-- ---------------------------------------------------------------------
SELECT
    a.age_label,
    ROUND(100.0 * SUM(CASE WHEN ms.morbidity_label = 'At least one checked' THEN f.births ELSE 0 END)
          / SUM(f.births), 3) AS morbidity_rate_pct
FROM fact_morbidity_age_bmi f
JOIN dim_age_group a ON a.age_group_id = f.age_group_id
JOIN dim_morbidity_status ms ON ms.morbidity_id = f.morbidity_id
GROUP BY a.age_label
ORDER BY a.sort_order;

-- Finding: morbidity rate rises through the childbearing years and
-- peaks at 30-34 (1.476%), then declines -- 15-19 (1.09%), 40-44
-- (0.99%), 45-49 (0.28%). The extreme ends (<15, 50+) show 0%, almost
-- certainly a small-sample artifact (very few births in these bands,
-- so most cells fall under the <10 suppression threshold) rather than
-- a genuine absence of risk -- flagged in README as a caveat, not a
-- real "safest" group.


-- ---------------------------------------------------------------------
-- Stratified: morbidity rate by age x BMI combined, restricted to
-- combinations with a meaningful sample size (>5,000 births) so we're
-- not ranking noise.
-- ---------------------------------------------------------------------
SELECT
    a.age_label,
    b.bmi_label,
    SUM(f.births) AS births,
    ROUND(100.0 * SUM(CASE WHEN ms.morbidity_label = 'At least one checked' THEN f.births ELSE 0 END)
          / SUM(f.births), 3) AS morbidity_rate_pct
FROM fact_morbidity_age_bmi f
JOIN dim_age_group a ON a.age_group_id = f.age_group_id
JOIN dim_bmi_category b ON b.bmi_id = f.bmi_id
JOIN dim_morbidity_status ms ON ms.morbidity_id = f.morbidity_id
WHERE b.bmi_label NOT LIKE 'Unknown%'
GROUP BY a.age_label, b.bmi_label
HAVING SUM(f.births) > 5000
ORDER BY morbidity_rate_pct DESC
LIMIT 10;

-- Finding: the highest-rate combinations are dominated by Normal BMI at
-- prime childbearing ages (30-34 + Normal BMI tops the list at 1.756%),
-- not by the obesity categories one might expect to see cluster at the
-- top. Age and BMI don't appear to "stack" multiplicatively in this
-- outcome measure the way they do for cesarean rate in Chapter 2 --
-- morbidity (as this proxy captures it: transfusion, laceration,
-- rupture, hysterectomy, ICU) looks more tied to acute delivery events
-- than to metabolic risk profile. Worth stating plainly in the README:
-- this is a real pattern in the data, not the pattern a purely clinical
-- prior might predict, and it's a good example of why the crude/
-- stratified caveat matters -- BMI's relationship to *cesarean rate*
-- (Chapter 2) is strong and monotonic; its relationship to this
-- morbidity proxy specifically is not.
