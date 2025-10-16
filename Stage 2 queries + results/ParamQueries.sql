-- Q9
PREPARE q9(text, date, date, int) AS
SELECT
  e.employee_id,
  e.first_name || ' ' || e.last_name AS full_name,
  d.name AS department,
  SUM(p.amount) AS total_paid
FROM payroll p
JOIN employee e ON p.employee_id = e.employee_id
JOIN department d ON e.department_id = d.department_id
WHERE d.name = $1
  AND p.pay_date BETWEEN $2 AND $3
GROUP BY e.employee_id, full_name, d.name
ORDER BY total_paid DESC
LIMIT $4;

EXECUTE q9('IT', '2021-01-01', '2029-06-30', 100000)
-- Q10
PREPARE q10(int) AS
SELECT
  el.employee_id,
  e.first_name || ' ' || e.last_name AS employee,
  COUNT(*) AS expiring_licenses,
  MIN(el.expiry_date) AS nearest_expiry
FROM employee_license el
JOIN employee e ON el.employee_id = e.employee_id
WHERE el.expiry_date IS NOT NULL
  AND el.expiry_date BETWEEN CURRENT_DATE AND (CURRENT_DATE + ($1 * INTERVAL '1 day'))
GROUP BY el.employee_id, employee
ORDER BY nearest_expiry ASC;

EXECUTE q10(600) 

-- Q11
PREPARE q11(int) AS
WITH yearly_employee AS (
  SELECT
    e.employee_id,
    e.position_id,
    SUM(p.amount) AS total_pay
  FROM payroll p
  JOIN employee e ON p.employee_id = e.employee_id
  WHERE p.pay_date BETWEEN TO_DATE($1::text || '-01-01','YYYY-MM-DD')
                       AND TO_DATE($1::text || '-12-31','YYYY-MM-DD')
  GROUP BY e.employee_id, e.position_id
)
SELECT
  pos.title AS position,
  COUNT(ye.employee_id) AS employees_with_pay,
  ROUND(AVG(ye.total_pay)::numeric,2) AS avg_total_pay,
  MIN(ye.total_pay) AS min_total_pay,
  MAX(ye.total_pay) AS max_total_pay,
  SUM(ye.total_pay) AS sum_total_pay
FROM yearly_employee ye
LEFT JOIN position pos ON ye.position_id = pos.position_id
GROUP BY pos.title
ORDER BY avg_total_pay DESC NULLS LAST;

-- Q12
PREPARE q12(int, int) AS
SELECT
  e1.employee_id AS emp1_id,
  e1.first_name || ' ' || e1.last_name AS emp1_name,
  e2.employee_id AS emp2_id,
  e2.first_name || ' ' || e2.last_name AS emp2_name,
  COUNT(*) AS overlapping_shifts_count,
  MIN(GREATEST(s1.start_time, s2.start_time)) AS first_overlap_start,
  MAX(LEAST(s1.end_time, s2.end_time)) AS last_overlap_end
FROM oncall_shift s1
JOIN oncall_shift s2
  ON s1.day_of_week = s2.day_of_week
  AND s1.shift_id < s2.shift_id
  AND s1.start_time < s2.end_time
  AND s2.start_time < s1.end_time
  AND s1.day_of_week = $1
  AND s1.employee_id < $2
JOIN employee e1 ON s1.employee_id = e1.employee_id
JOIN employee e2 ON s2.employee_id = e2.employee_id
GROUP BY e1.employee_id, emp1_name, e2.employee_id, emp2_name
ORDER BY overlapping_shifts_count DESC, emp1_name, emp2_name;
