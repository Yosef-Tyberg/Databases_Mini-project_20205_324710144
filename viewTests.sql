-- =====================================================================
-- VIEW 1: v_active_employees
-- =====================================================================

-- Ensure department and position exist for employees to reference
INSERT INTO department (name, description, created_at)
VALUES ('IT', 'IT Department', now())
ON CONFLICT (name) DO NOTHING;

INSERT INTO position (title, department_id, description, created_at)
VALUES ('Developer', (SELECT department_id FROM department WHERE name='IT'), 'Software Developer', now())
ON CONFLICT (title) DO NOTHING;

-- 1) Insert a valid employee via the view (active = TRUE required by view)
WITH ins AS (
  INSERT INTO v_active_employees
    (first_name, last_name, email, phone, hire_date, department_id, position_id, manager_id, active, created_at)
  VALUES
    ('Alice','Smith','alice.smith@example.com', '+972500000001', CURRENT_DATE - INTERVAL '30 days',
     (SELECT department_id FROM department WHERE name='IT'),
     (SELECT position_id FROM position WHERE title='Developer'),
     NULL, TRUE, now())
  RETURNING *
)
SELECT 'Inserted (view)' AS note, * FROM ins;

-- 2) Select that row from the view and underlying base table
SELECT 'From view v_active_employees' AS src, * FROM v_active_employees WHERE email = 'alice.smith@example.com';
SELECT 'From base employee'          AS src, * FROM employee WHERE email = 'alice.smith@example.com';

-- 3) Update the row in a valid way via the view (change phone)
UPDATE v_active_employees
SET phone = '+972500000002'
WHERE employee_id = (SELECT employee_id FROM employee WHERE email = 'alice.smith@example.com')
RETURNING *;

-- 5) Show updated rows
SELECT 'After update: view' AS src, * FROM v_active_employees WHERE email = 'alice.smith@example.com';
SELECT 'After update: base' AS src, * FROM employee WHERE email = 'alice.smith@example.com';

-- Demonstrate view-specific error: WITH CHECK OPTION violation
DO $$
BEGIN
  -- Attempt to set active = FALSE via the view; this should fail due to WITH CHECK OPTION.
  UPDATE v_active_employees
  SET active = FALSE
  WHERE email = 'alice.smith@example.com';
--EXCEPTION WHEN OTHERS THEN
  --RAISE NOTICE 'EXPECTED ERROR (v_active_employees CHECK OPTION): %', SQLERRM;
END$$;

-- Show that no change happened
SELECT 'After failed set active=false: base' AS src, * FROM employee WHERE email = 'alice.smith@example.com';

-- 4) Delete the row via the view
DELETE FROM v_active_employees
WHERE employee_id = (SELECT employee_id FROM employee WHERE email = 'alice.smith@example.com')
RETURNING *;

-- 6) Confirm deletion in base table
SELECT 'After delete: base (should be empty)' AS note, * FROM employee WHERE email = 'alice.smith@example.com';


-- =====================================================================
-- VIEW 2: v_oncall_shifts_valid
-- =====================================================================

-- Create a dedicated test employee for oncall (idempotent)
INSERT INTO employee (first_name,last_name,email,phone,hire_date,active,created_at)
VALUES ('Oncall','User','oncall.user@example.com','+972500000100', CURRENT_DATE - INTERVAL '60 days', TRUE, now())
ON CONFLICT (email) DO NOTHING;

-- Get employee id for use
-- (We will refer by email in statements where needed)

-- 1) Insert a valid oncall shift via the view (day_of_week 1..7; start_time < end_time)
WITH ins AS (
  INSERT INTO v_oncall_shifts_valid
    (employee_id, day_of_week, start_time, end_time, escalation_order, created_at)
  VALUES (
    (SELECT employee_id FROM employee WHERE email = 'oncall.user@example.com'),
    3, -- Wednesday
    TIME '09:00:00',
    TIME '17:00:00',
    1,
    now()
  )
  RETURNING *
)
SELECT 'Inserted (view) oncall' AS note, * FROM ins;

-- 2) Select from view and base table
SELECT 'From view v_oncall_shifts_valid' AS src, * FROM v_oncall_shifts_valid
 WHERE employee_id = (SELECT employee_id FROM employee WHERE email='oncall.user@example.com');

SELECT 'From base oncall_shift' AS src, * FROM oncall_shift
 WHERE employee_id = (SELECT employee_id FROM employee WHERE email='oncall.user@example.com');

-- 3) Update the oncall shift (valid): change start_time earlier
UPDATE v_oncall_shifts_valid
SET start_time = TIME '08:00:00'
WHERE shift_id = (
  SELECT shift_id FROM oncall_shift WHERE employee_id = (SELECT employee_id FROM employee WHERE email='oncall.user@example.com') LIMIT 1
)
RETURNING *;

-- 5) Show after update
SELECT 'After update: view' AS src, * FROM v_oncall_shifts_valid
 WHERE employee_id = (SELECT employee_id FROM employee WHERE email='oncall.user@example.com');

SELECT 'After update: base' AS src, * FROM oncall_shift
 WHERE employee_id = (SELECT employee_id FROM employee WHERE email='oncall.user@example.com');

-- Demonstrate view-specific errors (WITH CHECK OPTION violations) wrapped so script continues:

DO $$
BEGIN
  -- Attempt to insert an invalid day_of_week = 8 (out of 1..7) -> should be blocked by WITH CHECK OPTION
  INSERT INTO v_oncall_shifts_valid (employee_id, day_of_week, start_time, end_time, escalation_order, created_at)
  VALUES ((SELECT employee_id FROM employee WHERE email='oncall.user@example.com'), 8, TIME '09:00:00', TIME '10:00:00', 1, now());
END$$;

DO $$
BEGIN
  -- Attempt to update to make start_time >= end_time -> violates start_time < end_time in view/world
  UPDATE v_oncall_shifts_valid
  SET start_time = TIME '18:00:00', end_time = TIME '17:00:00'
  WHERE employee_id = (SELECT employee_id FROM employee WHERE email='oncall.user@example.com');
END$$;

-- 4) Delete the shift via the view
DELETE FROM v_oncall_shifts_valid
WHERE shift_id = (
  SELECT shift_id FROM oncall_shift WHERE employee_id = (SELECT employee_id FROM employee WHERE email='oncall.user@example.com') LIMIT 1
)
RETURNING *;

-- 6) Confirm deletion
SELECT 'After delete: base oncall_shift (should be empty)' AS note, * FROM oncall_shift
 WHERE employee_id = (SELECT employee_id FROM employee WHERE email='oncall.user@example.com');


-- =====================================================================
-- VIEW 3: v_current_licenses
-- Note: this view has an INSTEAD OF trigger (trg_v_current_licenses_iud) that:
--   * requires expiry_date >= CURRENT_DATE (raises exception if not)
--   * requires employee exists
--   * inserts into employee_license underlying table
-- We'll demonstrate both a successful insert and trigger-caused errors.
-- =====================================================================

-- Create a test employee for licenses (idempotent)
INSERT INTO employee (first_name,last_name,email,phone,hire_date,active,created_at)
VALUES ('Charlie','License','charlie.license@example.com','+972500000200', CURRENT_DATE - INTERVAL '365 days', TRUE, now())
ON CONFLICT (email) DO NOTHING;

-- 1) Insert a valid current license via the view
WITH ins AS (
  INSERT INTO v_current_licenses
    (employee_id, license_name, issued_date, expiry_date, created_at)
  VALUES (
    (SELECT employee_id FROM employee WHERE email='charlie.license@example.com'),
    'Senior Programmer',
    (CURRENT_DATE - INTERVAL '365 days'),
    (CURRENT_DATE + INTERVAL '365 days'), -- >= CURRENT_DATE
    now()
  )
  RETURNING *
)
SELECT 'Inserted (view) v_current_licenses' AS note, * FROM ins;

-- 2) Select the license from the view and underlying table
SELECT 'From view v_current_licenses' AS src, * FROM v_current_licenses
 WHERE employee_id = (SELECT employee_id FROM employee WHERE email='charlie.license@example.com');

SELECT 'From base employee_license' AS src, * FROM employee_license
 WHERE employee_id = (SELECT employee_id FROM employee WHERE email='charlie.license@example.com');

-- 3) Update the license via the view (extend expiry_date)
UPDATE v_current_licenses
SET expiry_date = (CURRENT_DATE + INTERVAL '730 days')
WHERE license_id = (
  SELECT license_id FROM employee_license WHERE employee_id = (SELECT employee_id FROM employee WHERE email='charlie.license@example.com') LIMIT 1
)
RETURNING *;

-- 5) Show after update
SELECT 'After update: view' AS src, * FROM v_current_licenses
 WHERE employee_id = (SELECT employee_id FROM employee WHERE email='charlie.license@example.com');

SELECT 'After update: base' AS src, * FROM employee_license
 WHERE employee_id = (SELECT employee_id FROM employee WHERE email='charlie.license@example.com');

-- Demonstrate view-trigger-specific errors (these are errors raised by the view's INSTEAD OF trigger):

DO $$
BEGIN
  -- 1) Try inserting a license with expiry_date < CURRENT_DATE (trigger should raise BEFORE underlying insert)
  INSERT INTO v_current_licenses (employee_id, license_name, issued_date, expiry_date, created_at)
  VALUES ((SELECT employee_id FROM employee WHERE email='charlie.license@example.com'),
          'Expired Cert', CURRENT_DATE - INTERVAL '400 days', CURRENT_DATE - INTERVAL '1 day', now());
END$$;

DO $$
BEGIN
  -- 2) Try inserting a license for non-existent employee (trigger should raise)
  INSERT INTO v_current_licenses (employee_id, license_name, issued_date, expiry_date, created_at)
  VALUES (-99999, 'Another Cert', CURRENT_DATE, CURRENT_DATE + INTERVAL '365 days', now());
END$$;

-- 4) Delete the license via the view
DELETE FROM v_current_licenses
WHERE license_id = (
  SELECT license_id FROM employee_license WHERE employee_id = (SELECT employee_id FROM employee WHERE email='charlie.license@example.com') LIMIT 1
)
RETURNING *;

-- 6) Confirm deletion
SELECT 'After delete: base employee_license (should be empty)' AS note, * FROM employee_license
 WHERE employee_id = (SELECT employee_id FROM employee WHERE email='charlie.license@example.com');


-- =====================================================================
-- VIEW 4: v_employee_overview
-- This view has an INSTEAD OF trigger that:
--  * on INSERT parses full_name -> first_name/last_name
--  * requires department and position names to exist (raises if not found)
--  * sets hire_date = CURRENT_DATE if not provided
-- =====================================================================

-- Ensure department/position exist (again; idempotent)
INSERT INTO department (name, description, created_at)
VALUES ('HR', 'Human Resources', now())
ON CONFLICT (name) DO NOTHING;

INSERT INTO position (title, department_id, description, created_at)
VALUES ('HR Manager', (SELECT department_id FROM department WHERE name='HR'), 'HR lead', now())
ON CONFLICT (title) DO NOTHING;

-- 1) Insert a valid employee via the view using full_name, department, position.
WITH ins AS (
  INSERT INTO v_employee_overview (full_name, department, position)
  VALUES ('Bobby B Jones', 'IT', 'Developer')  -- IT & Developer exist earlier
  RETURNING *
)
SELECT 'Inserted (view) v_employee_overview' AS note, * FROM ins;

-- 2) Select that row from the view and underlying base table.
-- Need to find the new employee's id (look up by name)
SELECT 'From view v_employee_overview' AS src, * FROM v_employee_overview
 WHERE full_name = 'Bobby B Jones';

SELECT 'From base employee' AS src, * FROM employee
 WHERE first_name = 'Bobby' AND last_name = 'B Jones';

-- 3) Update the row via the view (change name and keep department same)
UPDATE v_employee_overview
SET full_name = 'Ozymanthus Jones'
WHERE employee_id = (
  SELECT employee_id FROM employee WHERE first_name='Bobby' AND last_name='B Jones' LIMIT 1
)
RETURNING *;

-- 5) Show after update
SELECT 'After update: view' AS src, * FROM v_employee_overview
 WHERE employee_id = (SELECT employee_id FROM employee WHERE first_name='Ozymanthus' AND last_name='Jones');

SELECT 'After update: base' AS src, * FROM employee
 WHERE first_name='Ozymanthus' AND last_name='Jones';

-- Demonstrate view-trigger-specific errors:

DO $$
BEGIN
  -- 1) Attempt to insert with a non-existent department -> trigger should RAISE EXCEPTION
  INSERT INTO v_employee_overview (full_name, department, position)
  VALUES ('No Dept','Nonexistent Dept','Developer');
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'EXPECTED ERROR (v_employee_overview: department not found): %', SQLERRM;
END$$;

DO $$
BEGIN
  -- 2) Attempt to insert with NULL/empty full_name -> trigger should RAISE EXCEPTION
  INSERT INTO v_employee_overview (full_name, department, position)
  VALUES ('', 'IT', 'Developer');
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'EXPECTED ERROR (v_employee_overview: missing full_name): %', SQLERRM;
END$$;

-- 4) Delete the employee via the view
DELETE FROM v_employee_overview
WHERE employee_id = (SELECT employee_id FROM employee WHERE first_name='Ozymanthus' AND last_name='Jones' LIMIT 1)
RETURNING *;

-- 6) Confirm deletion
SELECT 'After delete: base employee (should be empty)' AS note, * FROM employee
 WHERE first_name='Ozymanthus' AND last_name='Jones';
