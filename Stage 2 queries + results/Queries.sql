--Q1
SELECT
  e.employee_id,
  e.first_name || ' ' || e.last_name AS full_name,
  d.name          AS department,
  p.title         AS position,
  COALESCE(m.first_name || ' ' || m.last_name, '—') AS manager,
  e.email,
  e.hire_date
FROM employee e
LEFT JOIN department d ON e.department_id = d.department_id
LEFT JOIN position p   ON e.position_id = p.position_id
LEFT JOIN employee m   ON e.manager_id = m.employee_id
WHERE e.active = TRUE
ORDER BY e.last_name, e.first_name;

--Q2
SELECT
  date_trunc('month', pay_date)                AS month,
  COUNT(*)                                     AS payments_count,
  SUM(amount)::numeric(18,2)                   AS total_paid,
  ROUND(AVG(amount)::numeric,2)                AS avg_payment,
  MIN(amount)                                  AS smallest_payment,
  MAX(amount)                                  AS largest_payment
FROM payroll
GROUP BY date_trunc('month', pay_date)
ORDER BY month DESC;

--Q3
SELECT
  el.license_id,
  el.employee_id,
  e.first_name || ' ' || e.last_name AS employee,
  el.license_name,
  el.expiry_date,
  (el.expiry_date - CURRENT_DATE) AS days_until_expiry
FROM employee_license el
JOIN employee e ON el.employee_id = e.employee_id
WHERE el.expiry_date IS NOT NULL
  AND el.expiry_date BETWEEN CURRENT_DATE AND (CURRENT_DATE + INTERVAL '60 days')
ORDER BY el.expiry_date ASC;

--Q4
SELECT
  e.employee_id,
  e.first_name || ' ' || e.last_name AS employee,
  COUNT(s.shift_id) AS shifts_per_week,
  SUM(s.end_time - s.start_time) AS total_oncall_duration -- returns an interval
FROM oncall_shift s
JOIN employee e ON s.employee_id = e.employee_id
GROUP BY e.employee_id, employee
ORDER BY total_oncall_duration DESC NULLS LAST;

--Q5
BEGIN;

WITH low_depts AS (
  SELECT e.department_id
  FROM employee e
  JOIN payroll p ON p.employee_id = e.employee_id
  GROUP BY e.department_id
  HAVING AVG(p.amount) < 99999
),
updated AS (
  UPDATE employee
  SET
    active = false,
    notes = COALESCE(notes, '') || ' | Auto-deactivated: dept avg payroll < 99999'
  FROM low_depts
  WHERE employee.department_id = low_depts.department_id
    AND employee.active = true
  RETURNING employee_id, employee.department_id, active, notes
)
COMMIT;

--Q6
-- UPDATE-2: normalize escalation_order by ordering shifts by start_time per employee/day
BEGIN;

WITH seq AS (
  SELECT shift_id,
         ROW_NUMBER() OVER (PARTITION BY employee_id, day_of_week ORDER BY start_time) AS rn
  FROM oncall_shift
),
updated AS (
  UPDATE oncall_shift o
  SET escalation_order = seq.rn
  FROM seq
  WHERE o.shift_id = seq.shift_id
    AND (o.escalation_order IS DISTINCT FROM seq.rn)
  RETURNING o.shift_id, o.employee_id, o.day_of_week, o.start_time, o.escalation_order
)
COMMIT;

--Q7
BEGIN;

WITH to_delete AS (
  SELECT el.license_id
  FROM employee_license el
  JOIN employee e ON el.employee_id = e.employee_id
  WHERE e.active = false
    AND el.expiry_date IS NOT NULL
    AND el.expiry_date < (CURRENT_DATE - INTERVAL '365 days')
),
deleted AS (
  DELETE FROM employee_license
  WHERE license_id IN (SELECT license_id FROM to_delete)
  RETURNING license_id, employee_id, license_name, expiry_date
)
COMMIT;

--Q8
BEGIN;

WITH ranked AS (
  SELECT shift_id,
         employee_id,
         ROW_NUMBER() OVER (PARTITION BY employee_id ORDER BY created_at DESC) AS rn
  FROM oncall_shift
),
to_delete AS (
  SELECT shift_id FROM ranked WHERE rn > 3
),
deleted AS (
  DELETE FROM oncall_shift
  WHERE shift_id IN (SELECT shift_id FROM to_delete)
  RETURNING shift_id, employee_id, created_at
)
COMMIT;