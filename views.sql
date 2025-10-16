-- =========================
--  Updatable Views Script
--  (create views + INSTEAD OF triggers for complex ones)
-- =========================

/* -------------------------
   v1: active employees
   (simple direct projection of employee; WITH CHECK OPTION makes
    sure updates/inserts remain active = TRUE)
   ------------------------- */
DROP VIEW IF EXISTS v_active_employees CASCADE;
CREATE VIEW v_active_employees AS
SELECT
  employee_id, first_name, last_name, email, phone, hire_date,
  department_id, position_id, manager_id, active, created_at
FROM employee
WHERE active = TRUE
WITH CHECK OPTION;  -- prevents updates/inserts that would violate WHERE


/* -------------------------
   v2: oncall shifts valid
   (fix: day_of_week range 1..7 to match your table constraint;
    simple projection + WITH CHECK OPTION)
   ------------------------- */
DROP VIEW IF EXISTS v_oncall_shifts_valid CASCADE;
CREATE VIEW v_oncall_shifts_valid AS
SELECT
  shift_id, employee_id, day_of_week, start_time, end_time,
  escalation_order, created_at
FROM oncall_shift
WHERE day_of_week BETWEEN 1 AND 7
  AND start_time < end_time
WITH CHECK OPTION;


/* -------------------------
   v3: current licenses
   - view shows employee name (join) so it's not directly updatable.
   - create INSTEAD OF trigger that maps I/U/D to employee_license.
   - enforce expiry_date >= CURRENT_DATE (to match view filter).
   ------------------------- */
DROP VIEW IF EXISTS v_current_licenses CASCADE;
CREATE VIEW v_current_licenses AS
SELECT
  el.license_id,
  el.employee_id,
  (e.first_name || ' ' || e.last_name) AS employee,
  el.license_name,
  el.issued_date,
  el.expiry_date,
  el.created_at
FROM employee_license el
JOIN employee e ON e.employee_id = el.employee_id
WHERE el.expiry_date >= CURRENT_DATE;

-- Trigger function for v_current_licenses
CREATE OR REPLACE FUNCTION trg_v_current_licenses_iud()
RETURNS TRIGGER AS $$
BEGIN
  IF TG_OP = 'INSERT' THEN
    -- enforce view filter
    IF NEW.expiry_date IS NULL OR NEW.expiry_date < CURRENT_DATE THEN
      RAISE EXCEPTION 'Cannot insert: expiry_date must be >= CURRENT_DATE';
    END IF;
    -- employee must exist
    PERFORM 1 FROM employee WHERE employee_id = NEW.employee_id;
    IF NOT FOUND THEN
      RAISE EXCEPTION 'Cannot insert: employee % not found', NEW.employee_id;
    END IF;
    -- perform insert into underlying table
    INSERT INTO employee_license (employee_id, license_name, issued_date, expiry_date, created_at)
    VALUES (NEW.employee_id, NEW.license_name, NEW.issued_date, NEW.expiry_date, COALESCE(NEW.created_at, now()))
    RETURNING license_id INTO NEW.license_id;
    -- fill the derived "employee" column for the view row
    SELECT (first_name || ' ' || last_name) INTO NEW.employee FROM employee WHERE employee_id = NEW.employee_id;
    RETURN NEW;

  ELSIF TG_OP = 'UPDATE' THEN
    -- enforce view filter on new values
    IF NEW.expiry_date IS NULL OR NEW.expiry_date < CURRENT_DATE THEN
      RAISE EXCEPTION 'Cannot update: expiry_date must be >= CURRENT_DATE';
    END IF;
    -- ensure referenced employee exists
    PERFORM 1 FROM employee WHERE employee_id = NEW.employee_id;
    IF NOT FOUND THEN
      RAISE EXCEPTION 'Cannot update: employee % not found', NEW.employee_id;
    END IF;
    -- update underlying row
    UPDATE employee_license
      SET employee_id = NEW.employee_id,
          license_name = NEW.license_name,
          issued_date = NEW.issued_date,
          expiry_date = NEW.expiry_date,
          created_at = COALESCE(NEW.created_at, created_at)
    WHERE license_id = OLD.license_id;
    -- set the derived employee name for returned row
    SELECT (first_name || ' ' || last_name) INTO NEW.employee FROM employee WHERE employee_id = NEW.employee_id;
    NEW.license_id := OLD.license_id;
    RETURN NEW;

  ELSIF TG_OP = 'DELETE' THEN
    -- delete underlying row
    DELETE FROM employee_license WHERE license_id = OLD.license_id;
    RETURN OLD;
  END IF;

  RETURN NULL; -- should never reach
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_v_current_licenses_iud ON v_current_licenses;
CREATE TRIGGER trg_v_current_licenses_iud
INSTEAD OF INSERT OR UPDATE OR DELETE ON v_current_licenses
FOR EACH ROW EXECUTE FUNCTION trg_v_current_licenses_iud();


/* -------------------------
   v4: employee overview
   - view joins department/position and computes full_name and payments_count
   - create INSTEAD OF trigger that maps I/U/D primarily to employee table.
   - INSERT will:
       * parse full_name -> first_name/last_name (split on first space)
       * resolve department (by name) -> department_id (require existence)
       * resolve position (by title)     -> position_id (require existence)
       * set hire_date = CURRENT_DATE if not available (employee.hire_date is NOT NULL)
   - UPDATE will update employee row fields accordingly (names, dept, pos).
   - DELETE will delete the underlying employee row.
   ------------------------- */
DROP VIEW IF EXISTS v_employee_overview CASCADE;
CREATE VIEW v_employee_overview AS
SELECT
  e.employee_id,
  (e.first_name || ' ' || e.last_name) AS full_name,
  d.name  AS department,
  p.title AS position,
  (SELECT COUNT(*) FROM payroll pr WHERE pr.employee_id = e.employee_id) AS payments_count
FROM employee e
LEFT JOIN department d ON d.department_id = e.department_id
LEFT JOIN position   p ON p.position_id   = e.position_id;

-- Trigger function for v_employee_overview

CREATE OR REPLACE FUNCTION trg_v_employee_overview_iud()
RETURNS TRIGGER AS $$
/*
  INSTEAD OF trigger for v_employee_overview.
  - Allows INSERT/UPDATE/DELETE using only the view columns (full_name, department, position).
  - On INSERT: synthesize a safe default email when none provided.
  - On UPDATE: preserve existing email unless NEW.email provided.
  - Requires department/position names to exist (will RAISE if not found).
*/
DECLARE
  dept_id INT;
  pos_id INT;
  split_pos INT;
  first_part TEXT;
  last_part TEXT;
  gen_email TEXT;
  existing_email TEXT;
BEGIN
  -- ensure full_name exists on INSERT
  IF TG_OP = 'INSERT' THEN
    IF NEW.full_name IS NULL OR btrim(NEW.full_name) = '' THEN
      RAISE EXCEPTION 'Cannot insert: full_name is required';
    END IF;

    -- parse full_name -> first + last (split on first space)
    split_pos := strpos(btrim(NEW.full_name), ' ');
    IF split_pos = 0 THEN
      first_part := btrim(NEW.full_name);
      last_part := '';
    ELSE
      first_part := substr(btrim(NEW.full_name), 1, split_pos - 1);
      last_part  := btrim(substr(btrim(NEW.full_name), split_pos + 1));
    END IF;

    -- resolve department name -> id if provided
    IF NEW.department IS NOT NULL THEN
      SELECT department_id INTO dept_id FROM department WHERE name = NEW.department;
      IF NOT FOUND THEN
        RAISE EXCEPTION 'Cannot insert: department "%" not found', NEW.department;
      END IF;
    ELSE
      dept_id := NULL;
    END IF;

    -- resolve position name -> id if provided
    IF NEW.position IS NOT NULL THEN
      SELECT position_id INTO pos_id FROM position WHERE title = NEW.position;
      IF NOT FOUND THEN
        RAISE EXCEPTION 'Cannot insert: position "%" not found', NEW.position;
      END IF;
    ELSE
      pos_id := NULL;
    END IF;

    -- if view didn't provide an email (view doesn't expose it), synthesize a safe default
    IF NEW.email IS NULL OR btrim(NEW.email) = '' THEN
      gen_email := lower(regexp_replace(first_part || COALESCE('.' || NULLIF(last_part,''), ''), '[^a-z0-9]+', '', 'gi')) || '@example.com';
      -- ensure unique-ish by appending random numeric suffix if email already exists
      IF EXISTS (SELECT 1 FROM employee WHERE email = gen_email) THEN
        gen_email := regexp_replace(gen_email, '@', ('_' || floor(random()*100000)::int || '@'));
      END IF;
      NEW.email := gen_email;
    END IF;

    -- Insert into employee; ensure required columns are given or defaulted
    INSERT INTO employee (
      first_name, last_name, email, phone, address, birth_date,
      hire_date, termination_date, active, department_id, position_id,
      manager_id, emergency_contacts, notes, created_at
    )
    VALUES (
      first_part,
      COALESCE(last_part, ''),
      NEW.email,
      COALESCE(NEW.phone, ''),      -- view doesn't expose phone; leave empty if not provided
      COALESCE(NEW.address, NULL),
      NULL,
      COALESCE(NEW.hire_date, CURRENT_DATE), -- hire_date NOT NULL => default to today if not provided
      NULL,
      COALESCE(NEW.active, TRUE),
      dept_id,
      pos_id,
      NULL,
      NULL,
      NULL,
      COALESCE(NEW.created_at, now())
    )
    RETURNING employee_id INTO NEW.employee_id;

    -- compute payments_count for returned row
    NEW.payments_count := (SELECT COUNT(*) FROM payroll WHERE employee_id = NEW.employee_id);

    RETURN NEW;

  ELSIF TG_OP = 'UPDATE' THEN
    -- parse full_name if provided in update
    IF NEW.full_name IS NOT NULL THEN
      split_pos := strpos(btrim(NEW.full_name), ' ');
      IF split_pos = 0 THEN
        first_part := btrim(NEW.full_name);
        last_part := '';
      ELSE
        first_part := substr(btrim(NEW.full_name), 1, split_pos - 1);
        last_part := btrim(substr(btrim(NEW.full_name), split_pos + 1));
      END IF;
    END IF;

    -- find existing email so we don't clobber it when view doesn't provide one
    SELECT email INTO existing_email FROM employee WHERE employee_id = OLD.employee_id;

    -- resolve department if provided
    IF NEW.department IS NOT NULL THEN
      SELECT department_id INTO dept_id FROM department WHERE name = NEW.department;
      IF NOT FOUND THEN
        RAISE EXCEPTION 'Cannot update: department "%" not found', NEW.department;
      END IF;
    ELSE
      dept_id := (SELECT department_id FROM employee WHERE employee_id = OLD.employee_id);
    END IF;

    -- resolve position if provided
    IF NEW.position IS NOT NULL THEN
      SELECT position_id INTO pos_id FROM position WHERE title = NEW.position;
      IF NOT FOUND THEN
        RAISE EXCEPTION 'Cannot update: position "%" not found', NEW.position;
      END IF;
    ELSE
      pos_id := (SELECT position_id FROM employee WHERE employee_id = OLD.employee_id);
    END IF;

    -- apply update on underlying employee (coalesce to keep old values where NEW.* is null)
    UPDATE employee
      SET first_name = COALESCE(first_part, first_name),
          last_name  = COALESCE(last_part, last_name),
          email      = COALESCE(NEW.email, existing_email),
          phone      = COALESCE(NEW.phone, phone),
          address    = COALESCE(NEW.address, address),
          birth_date = COALESCE(NEW.birth_date, birth_date),
          hire_date  = COALESCE(NEW.hire_date, hire_date),
          termination_date = COALESCE(NEW.termination_date, termination_date),
          active     = COALESCE(NEW.active, active),
          department_id = dept_id,
          position_id   = pos_id,
          manager_id    = COALESCE(NEW.manager_id, manager_id),
          emergency_contacts = COALESCE(NEW.emergency_contacts, emergency_contacts),
          notes = COALESCE(NEW.notes, notes),
          created_at = COALESCE(NEW.created_at, created_at)
    WHERE employee_id = OLD.employee_id;

    NEW.employee_id := OLD.employee_id;
    NEW.full_name := (SELECT first_name || ' ' || last_name FROM employee WHERE employee_id = NEW.employee_id);
    NEW.payments_count := (SELECT COUNT(*) FROM payroll WHERE employee_id = NEW.employee_id);
    RETURN NEW;

  ELSIF TG_OP = 'DELETE' THEN
    DELETE FROM employee WHERE employee_id = OLD.employee_id;
    RETURN OLD;
  END IF;

  RETURN NULL;
END;
$$ LANGUAGE plpgsql;

-- (re)create the trigger binding to view (if previously dropped)
DROP TRIGGER IF EXISTS trg_v_employee_overview_iud ON v_employee_overview;
CREATE TRIGGER trg_v_employee_overview_iud
INSTEAD OF INSERT OR UPDATE OR DELETE ON v_employee_overview
FOR EACH ROW EXECUTE FUNCTION trg_v_employee_overview_iud();

