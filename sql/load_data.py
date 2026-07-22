#!/usr/bin/env python3
"""
ETL script: loads CDC WONDER natality exports (CSV) into
maternal_health.db, per schema.sql.

Usage:
    python3 load_data.py <project_root> <output_db_path>

<project_root> should be the top of the project (the folder containing
data/raw/, sql/, etc.) -- raw CSVs are read from <project_root>/data/raw/.

Handles: stripping the WONDER footer (Notes/Messages/Caveats block),
"Not Applicable" -> NULL for average measures, de-duplicated dimension
inserts, and unioning multi-year-batch export files into single fact
tables.
"""
import csv
import glob
import os
import sqlite3
import sys

AGE_SORT = {
    "Under 15 years": 0, "15-19 years": 1, "20-24 years": 2, "25-29 years": 3,
    "30-34 years": 4, "35-39 years": 5, "40-44 years": 6, "45-49 years": 7,
    "50 years and over": 8,
}
PRENATAL_SORT = {
    "No prenatal care": 0, "1st month": 1, "2nd month": 2, "3rd month": 3,
    "4th month": 4, "5th month": 5, "6th month": 6, "7th month": 7,
    "8th month": 8, "9th month": 9, "10th month": 10,
    "Unknown or Not Stated": 99,
}
BMI_SORT = {
    "Underweight <18.5": 0, "Normal 18.5-24.9": 1, "Overweight 25.0-29.9": 2,
    "Obesity I 30.0-34.9": 3, "Obesity II 35.0-39.9": 4,
    "Extreme Obesity III > 39.9": 5, "Unknown or Not Stated": 99,
}


def raw_path(data_dir, filename):
    """Resolve a raw CDC export filename against <project_root>/data/raw/."""
    return os.path.join(data_dir, "data", "raw", filename)


def read_valid_rows(path):
    """Read a WONDER CSV export, dropping the trailing Notes/Messages/
    Caveats footer block (identified by rows where Year is not a
    4-digit number)."""
    with open(path, newline="", encoding="utf-8-sig", errors="replace") as f:
        reader = csv.DictReader(f)
        rows = [r for r in reader if r.get("Year") and r["Year"].strip().isdigit()]
    return rows


def to_int(val):
    return int(val.replace(",", "").strip())


def to_float_or_none(val):
    val = (val or "").strip()
    if val in ("", "Not Applicable", "Unknown", "Not Stated"):
        return None
    try:
        return float(val)
    except ValueError:
        return None


def get_or_create(cur, table, id_col, label_col, label_value, extra_cols=None, extra_vals=None):
    """Fetch the surrogate key for label_value in `table`, inserting it
    (with any extra columns, e.g. sort_order/code) if it doesn't exist yet."""
    cur.execute(f"SELECT {id_col} FROM {table} WHERE {label_col} = ?", (label_value,))
    row = cur.fetchone()
    if row:
        return row[0]
    cols = [label_col] + (extra_cols or [])
    vals = [label_value] + (extra_vals or [])
    placeholders = ",".join("?" * len(vals))
    cur.execute(f"INSERT INTO {table} ({','.join(cols)}) VALUES ({placeholders})", vals)
    return cur.lastrowid


def ensure_year(cur, year):
    cur.execute("INSERT OR IGNORE INTO dim_year (year_id) VALUES (?)", (year,))


def load_export1(cur, data_dir):
    files = [
        raw_path(data_dir, "export1_prenatal_care_2019_2021.csv"),
        raw_path(data_dir, "export1_prenatal_care_2022_2024.csv"),
    ]
    n = 0
    for path in files:
        for r in read_valid_rows(path):
            year = int(r["Year"])
            ensure_year(cur, year)
            div_id = get_or_create(cur, "dim_census_division", "division_id", "division_name",
                                    r["Census Division of Residence"],
                                    ["division_code"], [r["Census Division of Residence Code"]])
            age_id = get_or_create(cur, "dim_age_group", "age_group_id", "age_label",
                                    r["Age of Mother 9"],
                                    ["sort_order"], [AGE_SORT.get(r["Age of Mother 9"], 99)])
            pay_id = get_or_create(cur, "dim_payment_source", "payment_id", "payment_label",
                                    r["Source of Payment for Delivery"])
            timing_id = get_or_create(cur, "dim_prenatal_care_timing", "prenatal_timing_id", "timing_label",
                                       r["Month Prenatal Care Began"],
                                       ["sort_order"], [PRENATAL_SORT.get(r["Month Prenatal Care Began"], 99)])
            cur.execute(
                """INSERT INTO fact_prenatal_care_access
                   (year_id, division_id, age_group_id, payment_id, prenatal_timing_id, births, avg_prenatal_visits)
                   VALUES (?,?,?,?,?,?,?)""",
                (year, div_id, age_id, pay_id, timing_id, to_int(r["Births"]),
                 to_float_or_none(r["Average Number of Prenatal Visits"])),
            )
            n += 1
    return n


def load_export2(cur, data_dir):
    files = sorted(glob.glob(raw_path(data_dir, "export2_delivery_risk_*.csv")))
    n = 0
    for path in files:
        for r in read_valid_rows(path):
            year = int(r["Year"])
            ensure_year(cur, year)
            state_id = get_or_create(cur, "dim_state", "state_id", "state_name",
                                      r["State of Residence"],
                                      ["state_code"], [r["State of Residence Code"]])
            dm_id = get_or_create(cur, "dim_delivery_method", "delivery_method_id", "delivery_method_label",
                                   r["Delivery Method"])
            pc_id = get_or_create(cur, "dim_previous_cesarean", "previous_cesarean_id", "previous_cesarean_label",
                                   r["Previous Cesarean Delivery"])
            bmi_id = get_or_create(cur, "dim_bmi_category", "bmi_id", "bmi_label",
                                    r["Mother's Pre-pregnancy BMI"],
                                    ["sort_order"], [BMI_SORT.get(r["Mother's Pre-pregnancy BMI"], 99)])
            cur.execute(
                """INSERT INTO fact_delivery_risk
                   (year_id, state_id, delivery_method_id, previous_cesarean_id, bmi_id, births)
                   VALUES (?,?,?,?,?,?)""",
                (year, state_id, dm_id, pc_id, bmi_id, to_int(r["Births"])),
            )
            n += 1
    return n


def load_3a(cur, data_dir):
    files = [
        raw_path(data_dir, "export3a_delivery_method_prior_cesarean_2019_2021.csv"),
        raw_path(data_dir, "export3a_delivery_method_prior_cesarean_2022_2024.csv"),
    ]
    n = 0
    for path in files:
        for r in read_valid_rows(path):
            year = int(r["Year"])
            ensure_year(cur, year)
            state_id = get_or_create(cur, "dim_state", "state_id", "state_name",
                                      r["State of Residence"], ["state_code"], [r["State of Residence Code"]])
            dm_id = get_or_create(cur, "dim_delivery_method", "delivery_method_id", "delivery_method_label",
                                   r["Delivery Method"])
            pc_id = get_or_create(cur, "dim_previous_cesarean", "previous_cesarean_id", "previous_cesarean_label",
                                   r["Previous Cesarean Delivery"])
            morb_id = get_or_create(cur, "dim_morbidity_status", "morbidity_id", "morbidity_label",
                                     r["Maternal Morbidity Checked"])
            cur.execute(
                """INSERT INTO fact_morbidity_delivery_cesarean
                   (year_id, state_id, delivery_method_id, previous_cesarean_id, morbidity_id, births)
                   VALUES (?,?,?,?,?,?)""",
                (year, state_id, dm_id, pc_id, morb_id, to_int(r["Births"])),
            )
            n += 1
    return n


def load_3b(cur, data_dir):
    path = raw_path(data_dir, "export3b_age_bmi_2019_2024.csv")
    n = 0
    for r in read_valid_rows(path):
        year = int(r["Year"])
        ensure_year(cur, year)
        state_id = get_or_create(cur, "dim_state", "state_id", "state_name",
                                  r["State of Residence"], ["state_code"], [r["State of Residence Code"]])
        age_id = get_or_create(cur, "dim_age_group", "age_group_id", "age_label",
                                r["Age of Mother 9"], ["sort_order"], [AGE_SORT.get(r["Age of Mother 9"], 99)])
        bmi_id = get_or_create(cur, "dim_bmi_category", "bmi_id", "bmi_label",
                                r["Mother's Pre-pregnancy BMI"],
                                ["sort_order"], [BMI_SORT.get(r["Mother's Pre-pregnancy BMI"], 99)])
        morb_id = get_or_create(cur, "dim_morbidity_status", "morbidity_id", "morbidity_label",
                                 r["Maternal Morbidity Checked"])
        cur.execute(
            """INSERT INTO fact_morbidity_age_bmi
               (year_id, state_id, age_group_id, bmi_id, morbidity_id, births)
               VALUES (?,?,?,?,?,?)""",
            (year, state_id, age_id, bmi_id, morb_id, to_int(r["Births"])),
        )
        n += 1
    return n


def load_3c(cur, data_dir):
    path = raw_path(data_dir, "export3c_prenatal_care_timing_delivery_method_2019_2024.csv")
    n = 0
    for r in read_valid_rows(path):
        year = int(r["Year"])
        ensure_year(cur, year)
        state_id = get_or_create(cur, "dim_state", "state_id", "state_name",
                                  r["State of Residence"], ["state_code"], [r["State of Residence Code"]])
        timing_id = get_or_create(cur, "dim_prenatal_care_timing", "prenatal_timing_id", "timing_label",
                                   r["Month Prenatal Care Began"],
                                   ["sort_order"], [PRENATAL_SORT.get(r["Month Prenatal Care Began"], 99)])
        dm_id = get_or_create(cur, "dim_delivery_method", "delivery_method_id", "delivery_method_label",
                               r["Delivery Method"])
        morb_id = get_or_create(cur, "dim_morbidity_status", "morbidity_id", "morbidity_label",
                                 r["Maternal Morbidity Checked"])
        cur.execute(
            """INSERT INTO fact_morbidity_prenatal_delivery
               (year_id, state_id, prenatal_timing_id, delivery_method_id, morbidity_id, births)
               VALUES (?,?,?,?,?,?)""",
            (year, state_id, timing_id, dm_id, morb_id, to_int(r["Births"])),
        )
        n += 1
    return n


def load_3d(cur, data_dir):
    path = raw_path(data_dir, "export3d_source_payment_2019_2024.csv")
    n = 0
    for r in read_valid_rows(path):
        year = int(r["Year"])
        ensure_year(cur, year)
        state_id = get_or_create(cur, "dim_state", "state_id", "state_name",
                                  r["State of Residence"], ["state_code"], [r["State of Residence Code"]])
        pay_id = get_or_create(cur, "dim_payment_source", "payment_id", "payment_label",
                                r["Source of Payment for Delivery"])
        dm_id = get_or_create(cur, "dim_delivery_method", "delivery_method_id", "delivery_method_label",
                               r["Delivery Method"])
        morb_id = get_or_create(cur, "dim_morbidity_status", "morbidity_id", "morbidity_label",
                                 r["Maternal Morbidity Checked"])
        cur.execute(
            """INSERT INTO fact_morbidity_payment_delivery
               (year_id, state_id, payment_id, delivery_method_id, morbidity_id, births)
               VALUES (?,?,?,?,?,?)""",
            (year, state_id, pay_id, dm_id, morb_id, to_int(r["Births"])),
        )
        n += 1
    return n


def main():
    data_dir = sys.argv[1] if len(sys.argv) > 1 else "."
    db_path = sys.argv[2] if len(sys.argv) > 2 else "maternal_health.db"
    schema_path = os.path.join(os.path.dirname(os.path.abspath(__file__)), "schema.sql")

    if os.path.exists(db_path):
        os.remove(db_path)

    conn = sqlite3.connect(db_path)
    with open(schema_path) as f:
        conn.executescript(f.read())
    cur = conn.cursor()

    counts = {}
    counts["fact_prenatal_care_access"] = load_export1(cur, data_dir)
    counts["fact_delivery_risk"] = load_export2(cur, data_dir)
    counts["fact_morbidity_delivery_cesarean"] = load_3a(cur, data_dir)
    counts["fact_morbidity_age_bmi"] = load_3b(cur, data_dir)
    counts["fact_morbidity_prenatal_delivery"] = load_3c(cur, data_dir)
    counts["fact_morbidity_payment_delivery"] = load_3d(cur, data_dir)

    conn.commit()

    print("Rows inserted (Python-side count) vs rows in DB (SQL-side count):")
    for table, py_count in counts.items():
        db_count = cur.execute(f"SELECT COUNT(*) FROM {table}").fetchone()[0]
        status = "OK" if py_count == db_count else "MISMATCH"
        print(f"  {table:40s} python={py_count:6d}  db={db_count:6d}  [{status}]")

    print("\nDimension table sizes:")
    for t in ["dim_year", "dim_state", "dim_census_division", "dim_age_group",
              "dim_payment_source", "dim_prenatal_care_timing", "dim_delivery_method",
              "dim_previous_cesarean", "dim_bmi_category", "dim_morbidity_status"]:
        c = cur.execute(f"SELECT COUNT(*) FROM {t}").fetchone()[0]
        print(f"  {t:30s} {c}")

    conn.close()
    print(f"\nDatabase written to: {db_path}")


if __name__ == "__main__":
    main()
