-- =====================================================================
-- Maternal Health Access, Delivery Intervention & Outcomes (2019-2024)
-- Schema: fact constellation over conformed dimensions
-- Source: CDC WONDER, Natality - Birth Records (Expanded), 2016-2024
-- =====================================================================
-- Design note: this is a "fact constellation" (multiple fact tables
-- sharing conformed dimensions) rather than a single flat table,
-- because CDC WONDER only returns pre-aggregated cross-tabs (max 5
-- grouping variables per query, cells <10 births suppressed). Each
-- fact table reflects one query's grain; shared dimensions (state,
-- year, delivery method, morbidity status) let them be joined for
-- cross-chapter analysis.
-- =====================================================================

PRAGMA foreign_keys = ON;

-- ---------------------------------------------------------------------
-- DIMENSION TABLES
-- ---------------------------------------------------------------------

CREATE TABLE dim_year (
    year_id     INTEGER PRIMARY KEY   -- e.g. 2019
);

CREATE TABLE dim_state (
    state_id    INTEGER PRIMARY KEY AUTOINCREMENT,
    state_name  TEXT NOT NULL UNIQUE,
    state_code  TEXT
);

CREATE TABLE dim_census_division (
    division_id     INTEGER PRIMARY KEY AUTOINCREMENT,
    division_name   TEXT NOT NULL UNIQUE,
    division_code   TEXT
);

-- Maps each state to its census division and to Medicaid expansion
-- status, so state-level fact tables can be rolled up regionally and
-- cut by health-policy status. Medicaid expansion data is curated
-- separately from public KFF tracking data (not part of the CDC pull).
CREATE TABLE dim_medicaid_expansion (
    state_id                INTEGER PRIMARY KEY,
    expanded_medicaid       INTEGER NOT NULL,   -- 1 = yes, 0 = no (as of study period)
    expansion_date          TEXT,               -- NULL if never expanded (as of 2024)
    FOREIGN KEY (state_id) REFERENCES dim_state(state_id)
);

CREATE TABLE dim_age_group (
    age_group_id    INTEGER PRIMARY KEY AUTOINCREMENT,
    age_label       TEXT NOT NULL UNIQUE,
    sort_order      INTEGER NOT NULL
);

CREATE TABLE dim_payment_source (
    payment_id      INTEGER PRIMARY KEY AUTOINCREMENT,
    payment_label   TEXT NOT NULL UNIQUE
);

CREATE TABLE dim_prenatal_care_timing (
    prenatal_timing_id     INTEGER PRIMARY KEY AUTOINCREMENT,
    timing_label            TEXT NOT NULL UNIQUE,
    sort_order               INTEGER NOT NULL
);

CREATE TABLE dim_delivery_method (
    delivery_method_id     INTEGER PRIMARY KEY AUTOINCREMENT,
    delivery_method_label  TEXT NOT NULL UNIQUE
);

CREATE TABLE dim_previous_cesarean (
    previous_cesarean_id       INTEGER PRIMARY KEY AUTOINCREMENT,
    previous_cesarean_label    TEXT NOT NULL UNIQUE
);

CREATE TABLE dim_bmi_category (
    bmi_id          INTEGER PRIMARY KEY AUTOINCREMENT,
    bmi_label       TEXT NOT NULL UNIQUE,
    sort_order      INTEGER NOT NULL
);

CREATE TABLE dim_morbidity_status (
    morbidity_id        INTEGER PRIMARY KEY AUTOINCREMENT,
    morbidity_label      TEXT NOT NULL UNIQUE
);

-- ---------------------------------------------------------------------
-- FACT TABLES
-- ---------------------------------------------------------------------

-- Chapter 1: ACCESS
-- Grain: one row per year x census division x maternal age x payment
--        source x month prenatal care began
CREATE TABLE fact_prenatal_care_access (
    year_id                 INTEGER NOT NULL,
    division_id             INTEGER NOT NULL,
    age_group_id            INTEGER NOT NULL,
    payment_id              INTEGER NOT NULL,
    prenatal_timing_id      INTEGER NOT NULL,
    births                  INTEGER NOT NULL,
    avg_prenatal_visits     REAL,   -- NULL when WONDER reports "Not Applicable"
    FOREIGN KEY (year_id) REFERENCES dim_year(year_id),
    FOREIGN KEY (division_id) REFERENCES dim_census_division(division_id),
    FOREIGN KEY (age_group_id) REFERENCES dim_age_group(age_group_id),
    FOREIGN KEY (payment_id) REFERENCES dim_payment_source(payment_id),
    FOREIGN KEY (prenatal_timing_id) REFERENCES dim_prenatal_care_timing(prenatal_timing_id)
);

-- Chapter 2: INTERVENTION
-- Grain: one row per year x state x delivery method x previous
--        cesarean history x pre-pregnancy BMI
CREATE TABLE fact_delivery_risk (
    year_id                     INTEGER NOT NULL,
    state_id                    INTEGER NOT NULL,
    delivery_method_id          INTEGER NOT NULL,
    previous_cesarean_id        INTEGER NOT NULL,
    bmi_id                      INTEGER NOT NULL,
    births                      INTEGER NOT NULL,
    FOREIGN KEY (year_id) REFERENCES dim_year(year_id),
    FOREIGN KEY (state_id) REFERENCES dim_state(state_id),
    FOREIGN KEY (delivery_method_id) REFERENCES dim_delivery_method(delivery_method_id),
    FOREIGN KEY (previous_cesarean_id) REFERENCES dim_previous_cesarean(previous_cesarean_id),
    FOREIGN KEY (bmi_id) REFERENCES dim_bmi_category(bmi_id)
);

-- Chapter 3: OUTCOME (severe maternal morbidity) - four stratified cuts
-- 3A: delivery method x prior cesarean history
CREATE TABLE fact_morbidity_delivery_cesarean (
    year_id                     INTEGER NOT NULL,
    state_id                    INTEGER NOT NULL,
    delivery_method_id          INTEGER NOT NULL,
    previous_cesarean_id        INTEGER NOT NULL,
    morbidity_id                INTEGER NOT NULL,
    births                      INTEGER NOT NULL,
    FOREIGN KEY (year_id) REFERENCES dim_year(year_id),
    FOREIGN KEY (state_id) REFERENCES dim_state(state_id),
    FOREIGN KEY (delivery_method_id) REFERENCES dim_delivery_method(delivery_method_id),
    FOREIGN KEY (previous_cesarean_id) REFERENCES dim_previous_cesarean(previous_cesarean_id),
    FOREIGN KEY (morbidity_id) REFERENCES dim_morbidity_status(morbidity_id)
);

-- 3B: maternal age x pre-pregnancy BMI
CREATE TABLE fact_morbidity_age_bmi (
    year_id             INTEGER NOT NULL,
    state_id            INTEGER NOT NULL,
    age_group_id        INTEGER NOT NULL,
    bmi_id              INTEGER NOT NULL,
    morbidity_id        INTEGER NOT NULL,
    births               INTEGER NOT NULL,
    FOREIGN KEY (year_id) REFERENCES dim_year(year_id),
    FOREIGN KEY (state_id) REFERENCES dim_state(state_id),
    FOREIGN KEY (age_group_id) REFERENCES dim_age_group(age_group_id),
    FOREIGN KEY (bmi_id) REFERENCES dim_bmi_category(bmi_id),
    FOREIGN KEY (morbidity_id) REFERENCES dim_morbidity_status(morbidity_id)
);

-- 3C: prenatal care timing x delivery method
CREATE TABLE fact_morbidity_prenatal_delivery (
    year_id                 INTEGER NOT NULL,
    state_id                INTEGER NOT NULL,
    prenatal_timing_id      INTEGER NOT NULL,
    delivery_method_id      INTEGER NOT NULL,
    morbidity_id            INTEGER NOT NULL,
    births                   INTEGER NOT NULL,
    FOREIGN KEY (year_id) REFERENCES dim_year(year_id),
    FOREIGN KEY (state_id) REFERENCES dim_state(state_id),
    FOREIGN KEY (prenatal_timing_id) REFERENCES dim_prenatal_care_timing(prenatal_timing_id),
    FOREIGN KEY (delivery_method_id) REFERENCES dim_delivery_method(delivery_method_id),
    FOREIGN KEY (morbidity_id) REFERENCES dim_morbidity_status(morbidity_id)
);

-- 3D: payment source x delivery method (headline "access" cut)
CREATE TABLE fact_morbidity_payment_delivery (
    year_id                 INTEGER NOT NULL,
    state_id                INTEGER NOT NULL,
    payment_id              INTEGER NOT NULL,
    delivery_method_id      INTEGER NOT NULL,
    morbidity_id            INTEGER NOT NULL,
    births                   INTEGER NOT NULL,
    FOREIGN KEY (year_id) REFERENCES dim_year(year_id),
    FOREIGN KEY (state_id) REFERENCES dim_state(state_id),
    FOREIGN KEY (payment_id) REFERENCES dim_payment_source(payment_id),
    FOREIGN KEY (delivery_method_id) REFERENCES dim_delivery_method(delivery_method_id),
    FOREIGN KEY (morbidity_id) REFERENCES dim_morbidity_status(morbidity_id)
);

-- ---------------------------------------------------------------------
-- INDEXES (support the joins/group-bys the analysis queries will run)
-- ---------------------------------------------------------------------
CREATE INDEX idx_access_year_div       ON fact_prenatal_care_access(year_id, division_id);
CREATE INDEX idx_delivery_year_state   ON fact_delivery_risk(year_id, state_id);
CREATE INDEX idx_3a_year_state         ON fact_morbidity_delivery_cesarean(year_id, state_id);
CREATE INDEX idx_3b_year_state         ON fact_morbidity_age_bmi(year_id, state_id);
CREATE INDEX idx_3c_year_state         ON fact_morbidity_prenatal_delivery(year_id, state_id);
CREATE INDEX idx_3d_year_state         ON fact_morbidity_payment_delivery(year_id, state_id);
