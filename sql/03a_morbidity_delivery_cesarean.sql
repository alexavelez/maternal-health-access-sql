-- =====================================================================
-- CHAPTER 3A: OUTCOME -- Severe Maternal Morbidity x Delivery Method x
--             Prior Cesarean History
-- Source: fact_morbidity_delivery_cesarean
-- Outcome proxy: "Maternal Morbidity Checked" = at least one of
-- transfusion / 3rd-4th degree laceration / ruptured uterus / unplanned
-- hysterectomy / ICU admission reported on the birth certificate.
-- All rates below are crude (unadjusted) associations -- see README
-- methodology/limitations section before drawing causal conclusions.
-- =====================================================================

-- ---------------------------------------------------------------------
-- Stratified: morbidity rate by delivery method, split by whether the
-- mother had a prior cesarean. This is the key stratification -- a
-- flat "cesarean vs. vaginal" comparison (run earlier, in chat) hides
-- what's actually going on underneath it.
-- ---------------------------------------------------------------------
SELECT
    pc.previous_cesarean_label,
    dm.delivery_method_label,
    SUM(f.births) AS births,
    ROUND(100.0 * SUM(CASE WHEN ms.morbidity_label = 'At least one checked' THEN f.births ELSE 0 END)
          / SUM(f.births), 3) AS morbidity_rate_pct
FROM fact_morbidity_delivery_cesarean f
JOIN dim_delivery_method dm ON dm.delivery_method_id = f.delivery_method_id
JOIN dim_previous_cesarean pc ON pc.previous_cesarean_id = f.previous_cesarean_id
JOIN dim_morbidity_status ms ON ms.morbidity_id = f.morbidity_id
WHERE dm.delivery_method_label IN ('Cesarean','Vaginal')
  AND pc.previous_cesarean_label IN ('Yes','No')
GROUP BY pc.previous_cesarean_label, dm.delivery_method_label
ORDER BY pc.previous_cesarean_label, dm.delivery_method_label;

-- Finding: the flat comparison (cesarean 1.37% vs. vaginal 1.49%,
-- computed earlier) was masking the real story. Stratified by prior
-- history:
--   No prior cesarean:  Cesarean 1.451%  vs.  Vaginal 1.462%   (~equal)
--   Prior cesarean:     Cesarean 1.243%  vs.  Vaginal 2.222%   (VBAC attempt
--                                                                nearly 2x higher)
-- The elevated risk isn't attached to cesarean delivery broadly -- it's
-- specifically attempting a vaginal birth after a prior cesarean (VBAC/
-- TOLAC) that shows the highest morbidity rate in this table, consistent
-- with the known clinical risk of uterine rupture during a trial of
-- labor after cesarean. Planned repeat cesareans, by contrast, show the
-- *lowest* rate of the four groups. This reframes the finding entirely:
-- it's not "cesarean is riskier," it's "VBAC attempts carry a real,
-- measurable risk that a repeat cesarean avoids" -- a genuine clinical
-- nuance a non-clinical analyst would likely miss.
