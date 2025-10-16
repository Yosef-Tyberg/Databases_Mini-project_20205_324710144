---------------------------------------------------------------------
-- Add column-level NOT NULLs and UNIQUEs and CHECKs (dropping same-named
-- constraints first to be idempotent)
---------------------------------------------------------------------

-- Departments
ALTER TABLE department DROP CONSTRAINT IF EXISTS dept_name_unique;
-- make name NOT NULL and UNIQUE
ALTER TABLE department ALTER COLUMN name SET NOT NULL;
ALTER TABLE department ADD CONSTRAINT dept_name_unique UNIQUE (name);

-- Positions
ALTER TABLE position DROP CONSTRAINT IF EXISTS position_title_unique;
ALTER TABLE position ALTER COLUMN title SET NOT NULL;
ALTER TABLE position ADD CONSTRAINT position_title_unique UNIQUE (title);

-- Employee
ALTER TABLE employee DROP CONSTRAINT IF EXISTS chk_hire_before_termination;
ALTER TABLE employee DROP CONSTRAINT IF EXISTS chk_birth_age;
ALTER TABLE employee DROP CONSTRAINT IF EXISTS chk_email_nonempty;
ALTER TABLE employee DROP CONSTRAINT IF EXISTS employee_email_unique;

ALTER TABLE employee ALTER COLUMN first_name SET NOT NULL;
ALTER TABLE employee ALTER COLUMN last_name SET NOT NULL;
ALTER TABLE employee ALTER COLUMN email SET NOT NULL;
ALTER TABLE employee ALTER COLUMN hire_date SET NOT NULL;

ALTER TABLE employee ADD CONSTRAINT employee_email_unique UNIQUE (email);
ALTER TABLE employee ADD CONSTRAINT chk_email_nonempty CHECK (email IS NOT NULL AND btrim(email) <> '');
ALTER TABLE employee ADD CONSTRAINT chk_hire_before_termination CHECK (termination_date IS NULL OR hire_date < termination_date);
ALTER TABLE employee ADD CONSTRAINT chk_birth_age CHECK (birth_date IS NULL OR (date_part('year', age(hire_date, birth_date)) BETWEEN 18 AND 65));

-- Payroll
ALTER TABLE payroll DROP CONSTRAINT IF EXISTS chk_payroll_amount_nonneg;
ALTER TABLE payroll ALTER COLUMN employee_id SET NOT NULL;
ALTER TABLE payroll ALTER COLUMN amount SET NOT NULL;
ALTER TABLE payroll ALTER COLUMN pay_date SET NOT NULL;
ALTER TABLE payroll ADD CONSTRAINT chk_payroll_amount_nonneg CHECK (amount >= 0);

-- Oncall shift checks and NOT NULLs
ALTER TABLE oncall_shift DROP CONSTRAINT IF EXISTS chk_shift_order;
ALTER TABLE oncall_shift ALTER COLUMN day_of_week SET NOT NULL;
ALTER TABLE oncall_shift ALTER COLUMN start_time SET NOT NULL;
ALTER TABLE oncall_shift ALTER COLUMN end_time SET NOT NULL;
ALTER TABLE oncall_shift ALTER COLUMN escalation_order SET NOT NULL;
ALTER TABLE oncall_shift ADD CONSTRAINT chk_oncall_day_range CHECK (day_of_week >= 1 AND day_of_week <= 7);
ALTER TABLE oncall_shift ADD CONSTRAINT chk_escalation_positive CHECK (escalation_order > 0);
ALTER TABLE oncall_shift ADD CONSTRAINT chk_shift_order CHECK (start_time < end_time);

---------------------------------------------------------------------
-- 3) Triggers
---------------------------------------------------------------------

-- If function exists, replace it
CREATE OR REPLACE FUNCTION payroll_pay_date_after_hire()
RETURNS TRIGGER AS $$
DECLARE
  emp_hire DATE;
BEGIN
  -- retrieve hire date for the referenced employee
  SELECT hire_date INTO emp_hire FROM employee WHERE employee_id = NEW.employee_id;
  IF emp_hire IS NULL THEN
    RAISE EXCEPTION 'Referenced employee % does not exist or has no hire_date', NEW.employee_id;
  END IF;
  IF NEW.pay_date < emp_hire THEN
    RAISE EXCEPTION 'Payroll pay_date (%) is before employee (%) hire_date (%)', NEW.pay_date, NEW.employee_id, emp_hire;
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_payroll_pay_date_before_ins_upd ON payroll;
CREATE TRIGGER trg_payroll_pay_date_before_ins_upd
BEFORE INSERT OR UPDATE ON payroll
FOR EACH ROW EXECUTE FUNCTION payroll_pay_date_after_hire();


COMMIT;

-- Prevent employee manager cycles
CREATE OR REPLACE FUNCTION prevent_employee_manager_cycle()
RETURNS TRIGGER AS $$
DECLARE
  found BOOLEAN;
BEGIN
  -- If no manager assigned, nothing to check
  IF NEW.manager_id IS NULL THEN
    RETURN NEW;
  END IF;

  -- Disallow self-reference
  IF NEW.manager_id = NEW.employee_id THEN
    RAISE EXCEPTION 'Employee % cannot be their own manager', NEW.employee_id;
  END IF;

  -- Walk up the manager chain starting at NEW.manager_id:
  WITH RECURSIVE mgr_chain(emp_id, mgr_id) AS (
    SELECT e.employee_id, e.manager_id
    FROM employee e
    WHERE e.employee_id = NEW.manager_id
    UNION ALL
    SELECT e2.employee_id, e2.manager_id
    FROM employee e2
    JOIN mgr_chain mc ON e2.employee_id = mc.mgr_id
    WHERE e2.manager_id IS NOT NULL
  )
  SELECT true INTO found
  FROM mgr_chain
  WHERE emp_id = NEW.employee_id
  LIMIT 1;

  IF found THEN
    RAISE EXCEPTION 'Manager loop detected: assigning manager % to employee % would create a cycle', NEW.manager_id, NEW.employee_id;
  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_employee_manager_cycle ON employee;
CREATE TRIGGER trg_employee_manager_cycle
BEFORE INSERT OR UPDATE OF manager_id ON employee
FOR EACH ROW EXECUTE FUNCTION prevent_employee_manager_cycle();

-- Enforce license-name rank rule:
-- first word may be a rank: junior|intermediate|senior
-- base name (rest) is compared case-insensitively after trimming.
CREATE OR REPLACE FUNCTION prevent_lower_license_by_name()
RETURNS TRIGGER AS $$
DECLARE
  new_first text;
  new_rank int;
  new_base text;
  exists_higher boolean;
  existing_rank_expr int;
  existing_base_expr text;
BEGIN
  -- parse NEW.license_name
  new_first := lower(split_part(coalesce(NEW.license_name, ''),' ',1));
  IF new_first IN ('junior','intermediate','senior') THEN
    new_rank := CASE new_first
                  WHEN 'junior' THEN 1
                  WHEN 'intermediate' THEN 2
                  WHEN 'senior' THEN 3
                END;
    -- base is the remainder after the first word (trimmed, lowercased)
    new_base := btrim(lower(substr(NEW.license_name, length(split_part(NEW.license_name,' ',1)) + 1)));
    IF new_base = '' THEN
      -- require a base name when a rank is present (avoid "senior" alone)
      RAISE EXCEPTION 'License name must include a base name after the rank (e.g. "intermediate programmer")';
    END IF;
  ELSE
    -- unranked licenses are treated as rank 0 for comparison purposes
    new_rank := 0;
    new_base := btrim(lower(NEW.license_name));
  END IF;

  -- Find any existing license for same employee where:
  --   computed existing_rank > new_rank
  -- AND existing_base = new_base
  -- Exclude the row being updated (if UPDATE).
  SELECT true INTO exists_higher
  FROM employee_license el
  WHERE el.employee_id = NEW.employee_id
    AND (
      (CASE lower(split_part(coalesce(el.license_name, ''),' ',1))
         WHEN 'junior' THEN 1
         WHEN 'intermediate' THEN 2
         WHEN 'senior' THEN 3
         ELSE 0
       END) > new_rank
    )
    AND (
      btrim(lower(
        CASE lower(split_part(coalesce(el.license_name, ''),' ',1))
          WHEN 'junior' THEN substr(el.license_name, length(split_part(el.license_name,' ',1)) + 1)
          WHEN 'intermediate' THEN substr(el.license_name, length(split_part(el.license_name,' ',1)) + 1)
          WHEN 'senior' THEN substr(el.license_name, length(split_part(el.license_name,' ',1)) + 1)
          ELSE el.license_name
        END
      ))) = new_base
    AND (TG_OP = 'INSERT' OR el.license_id IS DISTINCT FROM NEW.license_id)
  LIMIT 1;

  IF exists_higher THEN
    RAISE EXCEPTION 'Cannot add license "%" for employee %: a higher-level license already exists for "%".', NEW.license_name, NEW.employee_id, new_base;
  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_employee_license_prevent_lower_by_name ON employee_license;
CREATE TRIGGER trg_employee_license_prevent_lower_by_name
BEFORE INSERT OR UPDATE ON employee_license
FOR EACH ROW EXECUTE FUNCTION prevent_lower_license_by_name();

-- End of add_constraints.sql
