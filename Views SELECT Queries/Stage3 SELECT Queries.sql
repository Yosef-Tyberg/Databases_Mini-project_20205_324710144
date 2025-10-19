\o 'C:/sql/Stage3/v1output.txt'
-- v_active_employees
SELECT
  employee_id, first_name, last_name, email, phone, hire_date,
  department_id, position_id, manager_id, active, created_at
FROM v_active_employees;

\o 'C:/sql/Stage3/v2output.txt'
-- v_oncall_shifts_valid
SELECT
  employee_id,
  COUNT(*)                              AS shift_count,
  MIN(start_time)                       AS earliest_start,
  MAX(end_time)                         AS latest_end,
  MIN(escalation_order)                 AS min_escalation_order,
  MIN(created_at)                       AS first_shift_created_at
FROM v_oncall_shifts_valid
GROUP BY employee_id
ORDER BY employee_id;

\o 'C:/sql/Stage3/v3output.txt'
-- v_current_licenses
WITH parsed AS (
  SELECT
    license_id,
    employee_id,
    employee,
    license_name,
    expiry_date,
    btrim(
      CASE lower(split_part(coalesce(license_name,''),' ',1))
        WHEN 'junior' THEN substr(license_name, length(split_part(license_name,' ',1)) + 1)
        WHEN 'intermediate' THEN substr(license_name, length(split_part(license_name,' ',1)) + 1)
        WHEN 'senior' THEN substr(license_name, length(split_part(license_name,' ',1)) + 1)
        ELSE license_name
      END
    ) AS base_name,
    CASE lower(split_part(coalesce(license_name,''),' ',1))
      WHEN 'junior' THEN 1
      WHEN 'intermediate' THEN 2
      WHEN 'senior' THEN 3
      ELSE 0
    END AS rank_val
  FROM v_current_licenses
)
SELECT
  employee_id,
  employee,
  base_name,
  COUNT(*)                           AS current_count_for_base,
  MAX(rank_val)                      AS highest_rank,
  (MIN(expiry_date) - CURRENT_DATE)  AS days_until_soonest_expiry
FROM parsed
GROUP BY employee_id, employee, base_name
ORDER BY employee_id, base_name;

\o 'C:/sql/Stage3/v4output.txt'
-- v_employee_overview
SELECT
  employee_id,
  full_name,
  department,
  position,
  payments_count
FROM v_employee_overview
WHERE payments_count > 0
ORDER BY payments_count DESC, full_name
LIMIT 5836;

\o
-- reset output back to terminal
