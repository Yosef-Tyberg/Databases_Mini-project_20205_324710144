#!/usr/bin/env python3
# generator_personnel_explicit_ids.py  (updated)
# Changes:
#   (1) Licenses have levels (license_level column + composed display name).
#   (2) Manager assignment guarantees an acyclic org chart (no cycles), with
#       defensive cycle detection.
#   (3) Shifts are generated per-employee with non-overlapping intervals per day,
#       reasonable durations, minute precision (HH:MM), and sequential escalation_order.

import os
import sys
import random
import datetime
import json
import argparse

# --------------------------- Configurable parameters ---------------------------
DEFAULT_NUM_EMPLOYEES = 100000
OUT_DIR_DEFAULT = os.path.join(os.getcwd(), "output_sql_explicit_ids")
CHUNK_SIZE = 1000  # rows per INSERT statement chunk

PAYROLL_PER_EMP_RANGE = (1, 3)   # at least 1 payroll per employee

LICENSE_RATIO = 0.5              # fraction of employees who have license rows
LICENSE_PER_EMP_RANGE = (1, 3)   # licenses per selected employee

# On-call scheduling
ONCALL_MIN_SHIFTS_PER_DAY = 0    # per employee per day
ONCALL_MAX_SHIFTS_PER_DAY = 2
ONCALL_SHIFT_MIN_HOURS = 2
ONCALL_SHIFT_MAX_HOURS = 6
ONCALL_START_WINDOW = (6, 20)    # earliest, latest start hour

# Date bounds used for most generated dates
DATE_MIN = datetime.date(2020, 1, 1)
DATE_MAX = datetime.date(2029, 12, 31)
DT_MIN = datetime.datetime.combine(DATE_MIN, datetime.time(0, 0))
DT_MAX = datetime.datetime.combine(DATE_MAX, datetime.time(23, 59))

EMAIL_DOMAINS = ["gmail.com", "yahoo.com", "hotmail.com", "outlook.com", "protonmail.com", "icloud.com"]
TIME_MINUTE_CHOICES = (0, 15, 30, 45)

# Manager policy
ALLOW_NULL_MANAGER_PROB = 0.05   # small chance of top-level (no manager)
ROOT_COUNT_APPROX = 100          # approx number of roots at start (no manager)

# --------------------------- Helper functions ---------------------------

def sql_escape(val):
    if val is None:
        return "NULL"
    return "'" + str(val).replace("'", "''") + "'"

def rand_date():
    delta = (DATE_MAX - DATE_MIN).days
    d = DATE_MIN + datetime.timedelta(days=random.randint(0, delta))
    return d.isoformat()

def rand_date_between(start_iso, end_iso):
    if isinstance(start_iso, str):
        start = datetime.date.fromisoformat(start_iso)
    else:
        start = start_iso
    if isinstance(end_iso, str):
        end = datetime.date.fromisoformat(end_iso)
    else:
        end = end_iso
    if end < start:
        start, end = end, start
    delta = (end - start).days
    d = start + datetime.timedelta(days=random.randint(0, max(0, delta)))
    return d.isoformat()

def rand_datetime_minute():
    total_minutes = int((DT_MAX - DT_MIN).total_seconds() // 60)
    mins = random.randint(0, total_minutes)
    dt = DT_MIN + datetime.timedelta(minutes=mins)
    return dt.strftime("%Y-%m-%d %H:%M")

def rand_time(min_hour=0, max_hour=23, minute_choices=TIME_MINUTE_CHOICES):
    h = random.randint(min_hour, max_hour)
    m = random.choice(minute_choices)
    return f"{h:02d}:{m:02d}"

def generate_unique_eids(n):
    start = 100_000_000
    end = 999_999_999
    return random.sample(range(start, end + 1), n)

# --------------------------- Constraint checkers ---------------------------

def hire_before_termination(hire_date, termination_date):
    if termination_date is None or termination_date == "":
        return True
    if isinstance(hire_date, str):
        hire_date = datetime.date.fromisoformat(hire_date)
    if isinstance(termination_date, str):
        termination_date = datetime.date.fromisoformat(termination_date)
    return hire_date < termination_date

def birth_within_age_range(hire_date, birth_date, min_age=18, max_age=65):
    if isinstance(hire_date, str):
        hire_date = datetime.date.fromisoformat(hire_date)
    if isinstance(birth_date, str):
        birth_date = datetime.date.fromisoformat(birth_date)
    years = hire_date.year - birth_date.year - ((hire_date.month, hire_date.day) < (birth_date.month, birth_date.day))
    return (years >= min_age) and (years <= max_age)

def hire_before_pay(hire_date, pay_date):
    if isinstance(hire_date, str):
        hire_date = datetime.date.fromisoformat(hire_date)
    if isinstance(pay_date, str):
        pay_date = datetime.date.fromisoformat(pay_date)
    return pay_date >= hire_date

# --------------------------- Static data ---------------------------

FIRST_NAMES = [
    "Oliver","Noah","Liam","Elijah","James","William","Benjamin","Lucas","Henry","Alexander",
    "Mason","Michael","Ethan","Daniel","Jacob","Logan","Jackson","Levi","Sebastian","Mateo",
    "Jack","Owen","Theodore","Aiden","Samuel","Joseph","John","David","Wyatt","Matthew",
    "Luke","Asher","Carter","Julian","Grayson","Leo","Jayden","Gabriel","Isaac","Lincoln",
    "Anthony","Hudson","Dylan","Ezra","Thomas","Charles","Christopher","Jaxon","Maverick",
    "Josiah","Isaiah","Andrew","Elias","Joshua","Nathan","Caleb","Ryan","Adrian","Miles","Eli",
    "Nolan","Christian","Aaron","Cameron","Ezekiel","Colton","Luca","Landon","Hunter","Jonathan",
    "Santiago","Axel","Easton","Cooper","Jeremiah","Angel","Roman","Connor","Jameson","Robert",
    "Greyson","Jordan","Ian","Carson","Jaxson","Leonardo","Nicholas","Dominic","Austin","Everett",
    "Brooks","Xavier","Kai","Jose","Parker","Adam","Jace","Wesley","Kayden","Silas","Bennett",
    "Declan","Waylon","Weston","Evan","Emmett","Micah","Ryder","Beau","Damian","Brayden","Gael",
    "Rowan","Hector","Victor","Peter","Max","Omar","Harlan","Rafael","Shane","Tristan","Kody","Malik",
    "Orion","Zane","Finn"
]
LAST_NAMES = [
    "Smith","Johnson","Williams","Brown","Jones","Garcia","Miller","Davis","Rodriguez","Martinez",
    "Hernandez","Lopez","Gonzalez","Wilson","Anderson","Thomas","Taylor","Moore","Jackson","Martin",
    "Lee","Perez","Thompson","White","Harris","Sanchez","Clark","Ramirez","Lewis","Robinson","Walker",
    "Young","Allen","King","Wright","Scott","Torres","Nguyen","Hill","Flores","Green","Adams","Nelson",
    "Baker","Hall","Rivera","Campbell","Mitchell","Carter","Roberts","Gomez","Phillips","Evans","Turner",
    "Diaz","Parker","Cruz","Edwards","Collins","Reyes","Stewart","Morris","Morales","Murphy","Cook","Rogers",
    "Gutierrez","Ortiz","Morgan","Cooper","Peterson","Bailey","Reed","Kelly","Howard","Ramos","Kim","Cox","Ward",
    "Richardson","Watson","Brooks","Chavez","Wood","James","Bennett","Gray","Mendoza","Ruiz","Hughes","Price",
    "Alvarez","Castillo","Sanders","Patel","Myers","Long","Ross","Foster","Jimenez","Powell","Schultz","Berg",
    "Fischer","Weber","Keller","Herrera","Douglas","Ray","Holmes","Stephens","Gardner","Spencer","Bryant","Lam",
    "Riley","Hamilton","Graham","Reeves","Sutton","Pena","Freeman","Walters","Baldwin","Potter","Serrano","Figueroa",
    "Cohen","Nolan","Cross"
]
DEPARTMENTS = [
    ("Personnel","Human Resources and personnel management"),
    ("Ticketing","Handles bookings and ticket issuance"),
    ("Customer Support","Customer support and post-booking assistance"),
    ("Advertising","Marketing and ad campaigns"),
    ("Payment Clearing","Payment processing and reconciliation"),
    ("Operations","General operations and management"),
    ("Business Development","New partnerships and deals"),
    ("IT","Infrastructure and support"),
    ("Legal & Compliance","Contracts, compliance, licensing"),
    ("Finance","Budgeting and financial reporting"),
    ("Training","Employee training and certification"),
    ("Logistics","Vendor and supplier coordination")
]
POSITIONS = [
    ("HR Manager",1,"Oversees HR and personnel policies"),
    ("Payroll Specialist",1,"Handles payroll and benefits processing"),
    ("Recruiter",1,"Finds and onboards new hires"),
    ("Travel Agent",2,"Books tickets and builds itineraries"),
    ("Ticketing Supervisor",2,"Supervises ticketing agents"),
    ("Support Agent",3,"Frontline customer support"),
    ("Support Supervisor",3,"Leads support agents"),
    ("Ad Campaign Manager",4,"Plans and runs ad campaigns"),
    ("Marketing Specialist",4,"Executes marketing tasks"),
    ("Payments Specialist",5,"Processes payments and reconciliations"),
    ("Clearing Analyst",5,"Handles clearing operations"),
    ("Operations Manager",6,"Oversees operations"),
    ("General Manager",6,"Top-level operations manager"),
    ("Partnerships Manager",7,"Handles business partnerships"),
    ("IT Support",8,"Day-to-day IT support"),
    ("Sysadmin",8,"Manages servers and deployments"),
    ("Legal Counsel",9,"Legal advice and contract drafting"),
    ("Compliance Officer",9,"Regulatory compliance"),
    ("Accountant",10,"Books and reconciles accounts"),
    ("Financial Analyst",10,"Analyzes financials"),
    ("Trainer",11,"Delivers training sessions"),
    ("Training Coordinator",11,"Schedules and manages training"),
    ("Logistics Coordinator",12,"Manages logistics tasks"),
    ("Vendor Manager",12,"Handles supplier relations"),
    ("Senior Travel Agent",2,"Experienced agent for VIPs"),
    ("Customer Experience Lead",3,"Improves CX across channels"),
    ("DevOps Engineer",8,"Automates infrastructure"),
    ("Data Analyst",10,"Insights from customer and sales data"),
    ("UX Designer",4,"Designs marketing and web UX"),
    ("Security Specialist",8,"Information security and monitoring")
]

# (1) Licenses with levels (each license has max level)
LICENSES = [
    {"name": "IATA Agent",                 "max_level": 3},
    {"name": "Tour Guide",                 "max_level": 2},
    {"name": "Corporate Travel Cert",      "max_level": 2},
    {"name": "Security Screening",         "max_level": 2},
    {"name": "VAT Handling",               "max_level": 2},
    {"name": "Advanced Ticketing",         "max_level": 3},
    {"name": "API Access",                 "max_level": 2},
    {"name": "Customer Privacy",           "max_level": 2},
    {"name": "AML Awareness",              "max_level": 1},
    {"name": "Accreditation (Senior)",     "max_level": 1},
    {"name": "Fraud Prevention",           "max_level": 2}
]

NOTES = [
    "Top performer in last quarter","Part-time; remote","Preferred contact: phone","Requires special accommodation",
    "Probationary period","Certified travel agent (IATA)","HR flagged: verify documents","Limited authorization for refunds",
    "Full access to ticketing system","Handles VIP accounts","Training scheduled","Fluent in Spanish and English","No night shifts",
    "Can approve discounts up to 10%","Safety trained","Temporary contractor","Under NDA","Background check pending",
    "Eligible for promotion","Receives travel benefits"
]

STREET_NAMES = ["Maple", "Oak", "Pine", "Cedar", "Elm", "Birch", "Main", "Park", "Lake", "Hill"]
STREET_SUFFIXES = ["St.", "Ave.", "Blvd.", "Rd.", "Ln.", "Dr."]

def generate_address():
    number = random.randint(1, 9999)
    name = random.choice(STREET_NAMES)
    suffix = random.choice(STREET_SUFFIXES)
    return f"{number} {name} {suffix}"

# --------------------------- Manager DAG helpers ---------------------------

def would_create_cycle(candidate_manager_id, employee_id, manager_of):
    """
    Return True if setting candidate_manager_id as manager of employee_id would create a cycle.
    manager_of: dict {employee_id -> manager_id or None}
    """
    if candidate_manager_id is None:
        return False
    # Walk upwards from candidate_manager_id; if we see employee_id, it's a cycle.
    seen = set()
    cur = candidate_manager_id
    while cur is not None and cur not in seen:
        if cur == employee_id:
            return True
        seen.add(cur)
        cur = manager_of.get(cur)
    return False

# --------------------------- Core generation logic ---------------------------

def write_inserts_chunked(path, table, cols, rows, chunk=CHUNK_SIZE):
    with open(path, "a", encoding="utf-8") as f:
        for i in range(0, len(rows), chunk):
            chunk_rows = rows[i:i+chunk]
            values = ",\n".join("(" + ", ".join(r) + ")" for r in chunk_rows)
            f.write(f"INSERT INTO {table} ({', '.join(cols)}) VALUES\n{values};\n\n")

def generate_files(num_employees=DEFAULT_NUM_EMPLOYEES, out_dir=OUT_DIR_DEFAULT, write_sequences=True):
    os.makedirs(out_dir, exist_ok=True)
    paths = {}

    # Department
    dept_file = os.path.join(out_dir, "department.sql")
    cols_dept = ["department_id", "name", "description", "created_at"]
    dept_rows = []
    for idx, (name, desc) in enumerate(DEPARTMENTS, start=1):
        dept_rows.append([str(idx), sql_escape(name), sql_escape(desc), sql_escape(rand_datetime_minute())])
    with open(dept_file, "w", encoding="utf-8") as f:
        f.write("-- departments\nBEGIN;\n\n")
    write_inserts_chunked(dept_file, "department", cols_dept, dept_rows)
    with open(dept_file, "a", encoding="utf-8") as f:
        f.write("COMMIT;\n")
    paths['department'] = dept_file

    # Position
    pos_file = os.path.join(out_dir, "position.sql")
    cols_pos = ["position_id", "title", "department_id", "description", "created_at"]
    pos_rows = []
    for idx, (title, dept_idx, desc) in enumerate(POSITIONS, start=1):
        pos_rows.append([str(idx), sql_escape(title), str(dept_idx), sql_escape(desc), sql_escape(rand_datetime_minute())])
    with open(pos_file, "w", encoding="utf-8") as f:
        f.write("-- positions\nBEGIN;\n\n")
    write_inserts_chunked(pos_file, "position", cols_pos, pos_rows)
    with open(pos_file, "a", encoding="utf-8") as f:
        f.write("COMMIT;\n")
    paths['position'] = pos_file

    # Employees
    emp_file = os.path.join(out_dir, "employee.sql")
    cols_emp = [
        "employee_id","first_name","last_name","email","phone","address","birth_date",
        "hire_date","termination_date","active","department_id","position_id","manager_id",
        "emergency_contacts","notes","created_at"
    ]
    eids = generate_unique_eids(num_employees)
    used_emails = set()
    employees = []               # keep dicts for later
    manager_of = {}              # employee_id -> manager_id (for cycle detection)

    emp_rows = []
    for idx in range(num_employees):
        eid = eids[idx]
        first = random.choice(FIRST_NAMES)
        last = random.choice(LAST_NAMES)
        base = f"{first.lower()}.{last.lower()}"
        domain = random.choice(EMAIL_DOMAINS)
        email = f"{base}@{domain}"
        suffix = 1
        while email in used_emails:
            email = f"{base}{suffix}@{domain}"
            suffix += 1
        used_emails.add(email)
        phone = f"+1{random.randint(2000000000, 9999999999)}"[:15]
        address = generate_address()

        hire_iso = rand_date()
        hire_date_obj = datetime.date.fromisoformat(hire_iso)
        birth_latest = hire_date_obj - datetime.timedelta(days=18*365 + 4)
        birth_earliest = hire_date_obj - datetime.timedelta(days=65*365 + 16)
        if birth_earliest > birth_latest:
            birth_date_obj = hire_date_obj - datetime.timedelta(days=30*365)
        else:
            span = (birth_latest - birth_earliest).days
            birth_date_obj = birth_earliest + datetime.timedelta(days=random.randint(0, max(0, span)))
        birth_iso = birth_date_obj.isoformat()

        termination_iso = None
        active = True
        if random.random() < 0.02:
            term_iso = rand_date_between(hire_iso, DATE_MAX.isoformat())
            if not hire_before_termination(hire_iso, term_iso):
                term_iso = (hire_date_obj + datetime.timedelta(days=30)).isoformat()
            termination_iso = term_iso
            active = False

        dept_id = random.randint(1, len(DEPARTMENTS))
        valid_positions = [i+1 for i,(_,d,_) in enumerate(POSITIONS) if d == dept_id]
        pos_id = random.choice(valid_positions) if valid_positions else random.randint(1, len(POSITIONS))

        # (2) Manager assignment — acyclic by construction + defensive cycle check
        manager = None
        if idx >= ROOT_COUNT_APPROX and random.random() > ALLOW_NULL_MANAGER_PROB:
            # choose a manager only among already-created employees (guarantees DAG)
            candidates = eids[:idx]
            # try a few times to avoid cycles (defensive)
            for _ in range(5):
                candidate = random.choice(candidates)
                if not would_create_cycle(candidate, eid, manager_of):
                    manager = candidate
                    break
            # if after attempts it would still cycle (very unlikely), leave as root
        manager_of[eid] = manager

        ec = {"contacts":[{"name": random.choice(FIRST_NAMES) + " " + random.choice(LAST_NAMES),
                           "phone": f"+1{random.randint(2000000000, 9999999999)}"}]}
        notes = random.choice(NOTES) if random.random() < 0.35 else ""
        created_at = rand_datetime_minute()

        if not birth_within_age_range(hire_iso, birth_iso):
            birth_iso = (hire_date_obj - datetime.timedelta(days=30*365)).isoformat()

        emp = {
            "employee_id": eid,
            "first": first,
            "last": last,
            "email": email,
            "phone": phone,
            "address": address,
            "birth": birth_iso,
            "hire": hire_iso,
            "termination": termination_iso,
            "active": active,
            "department_id": dept_id,
            "position_id": pos_id,
            "manager": manager,
            "emergency_contacts": ec,
            "notes": notes,
            "created_at": created_at
        }
        employees.append(emp)

        emp_row = [
            str(eid), sql_escape(first), sql_escape(last), sql_escape(email), sql_escape(phone), sql_escape(address),
            sql_escape(birth_iso), sql_escape(hire_iso),
            sql_escape(termination_iso) if termination_iso else "NULL",
            "true" if active else "false", str(dept_id), str(pos_id),
            str(manager) if manager else "NULL",
            sql_escape(json.dumps(ec)), sql_escape(notes), sql_escape(created_at)
        ]
        emp_rows.append(emp_row)

    with open(emp_file, "w", encoding="utf-8") as f:
        f.write("-- employees\nBEGIN;\n\n")
    write_inserts_chunked(emp_file, "employee", cols_emp, emp_rows)
    with open(emp_file, "a", encoding="utf-8") as f:
        f.write("COMMIT;\n")
    paths['employee'] = emp_file

    # Payroll
    payroll_file = os.path.join(out_dir, "payroll.sql")
    cols_pay = ["payroll_id","employee_id","amount","pay_date","notes","created_at"]
    pay_rows, pid = [], 1
    for emp in employees:
        num = random.randint(*PAYROLL_PER_EMP_RANGE)
        for _ in range(num):
            pay_date = rand_date_between(emp["hire"], DATE_MAX.isoformat())
            if not hire_before_pay(emp["hire"], pay_date):
                pay_date = emp["hire"]
            amt = round(random.uniform(800, 15000), 2)
            notes = random.choice(NOTES)
            created_at = rand_datetime_minute()
            pay_rows.append([str(pid), str(emp["employee_id"]), f"{amt:.2f}", sql_escape(pay_date), sql_escape(notes), sql_escape(created_at)])
            pid += 1
    with open(payroll_file, "w", encoding="utf-8") as f:
        f.write("-- payroll\nBEGIN;\n\n")
    write_inserts_chunked(payroll_file, "payroll", cols_pay, pay_rows)
    with open(payroll_file, "a", encoding="utf-8") as f:
        f.write("COMMIT;\n")
    paths['payroll'] = payroll_file

    # (1) Employee licenses with levels
    lic_file = os.path.join(out_dir, "employee_license.sql")
    # Added license_level column
    cols_lic = ["license_id","employee_id","license_name","license_level","issued_date","expiry_date","notes","created_at"]
    lic_rows, lid = [], 1
    num_license_emps = max(10, int(num_employees * LICENSE_RATIO))
    sample_emps = random.sample(employees, num_license_emps)
    for emp in sample_emps:
        for _ in range(random.randint(*LICENSE_PER_EMP_RANGE)):
            lic = random.choice(LICENSES)
            level = random.randint(1, lic["max_level"])
            disp_name = f"{lic['name']} (Level {level})"
            issued = rand_date_between(emp["hire"], DATE_MAX.isoformat())
            issued_dt = datetime.date.fromisoformat(issued)
            expiry_dt = issued_dt + datetime.timedelta(days=random.randint(365, 365*5))
            if expiry_dt > DATE_MAX:
                expiry_dt = DATE_MAX
            notes = random.choice(NOTES)
            created_at = rand_datetime_minute()
            lic_rows.append([
                str(lid), str(emp["employee_id"]),
                sql_escape(disp_name), str(level),
                sql_escape(issued), sql_escape(expiry_dt.isoformat()),
                sql_escape(notes), sql_escape(created_at)
            ])
            lid += 1
    with open(lic_file, "w", encoding="utf-8") as f:
        f.write("-- employee_license\nBEGIN;\n\n")
    write_inserts_chunked(lic_file, "employee_license", cols_lic, lic_rows)
    with open(lic_file, "a", encoding="utf-8") as f:
        f.write("COMMIT;\n")
    paths['employee_license'] = lic_file

    # (3) On-call shifts — non-overlapping per day, sequential escalation_order
    shift_file = os.path.join(out_dir, "oncall_shift.sql")
    cols_shift = ["shift_id","employee_id","day_of_week","start_time","end_time","escalation_order","created_at"]
    shift_rows, sid = [], 1

    def gen_day_shifts():
        """Generate a non-overlapping set of (start_hour, start_min, end_hour, end_min) for a single day."""
        count = random.randint(ONCALL_MIN_SHIFTS_PER_DAY, ONCALL_MAX_SHIFTS_PER_DAY)
        if count == 0:
            return []
        # sample start times, then expand with duration and prune overlaps
        candidates = []
        for _ in range(count * 2):  # extra candidates in case of pruning
            sh = random.randint(ONCALL_START_WINDOW[0], ONCALL_START_WINDOW[1])
            sm = random.choice(TIME_MINUTE_CHOICES)
            dur = random.randint(ONCALL_SHIFT_MIN_HOURS, ONCALL_SHIFT_MAX_HOURS)
            eh = min(23, sh + dur)
            em = sm
            if eh == sh and dur == 0:  # guard (shouldn't happen)
                eh = min(23, sh + 1)
            candidates.append((sh, sm, eh, em))
        # sort by start, then select greedily non-overlapping
        candidates.sort()
        selected = []
        cur_end = (-1, -1)
        for sh, sm, eh, em in candidates:
            if (sh, sm) >= cur_end:
                selected.append((sh, sm, eh, em))
                cur_end = (eh, em)
                if len(selected) >= count:
                    break
        return selected

    for emp in employees:
        for dow in range(1, 8):  # 1=Mon..7=Sun
            day_shifts = gen_day_shifts()
            # assign escalation_order sequentially
            for order, (sh, sm, eh, em) in enumerate(day_shifts, start=1):
                start = f"{sh:02d}:{sm:02d}"
                end = f"{eh:02d}:{em:02d}"
                created_at = rand_datetime_minute()
                shift_rows.append([
                    str(sid), str(emp["employee_id"]), str(dow),
                    sql_escape(start), sql_escape(end), str(order), sql_escape(created_at)
                ])
                sid += 1

    with open(shift_file, "w", encoding="utf-8") as f:
        f.write("-- oncall_shift\nBEGIN;\n\n")
    write_inserts_chunked(shift_file, "oncall_shift", cols_shift, shift_rows)
    with open(shift_file, "a", encoding="utf-8") as f:
        f.write("COMMIT;\n")
    paths['oncall_shift'] = shift_file

    # Optional sequences bump
    seq_file = None
    if write_sequences:
        seq_file = os.path.join(out_dir, "set_sequences.sql")
        with open(seq_file, "w", encoding="utf-8") as f:
            f.write("-- Set sequences to the current max values (use if your DDL used SERIAL for ids)\n\n")
            def write_seq(seq_name, table, col):
                f.write("SELECT setval('%s', (SELECT COALESCE(MAX(%s),0) FROM %s), true);\n" % (seq_name, col, table))
            write_seq('department_department_id_seq', 'department', 'department_id')
            write_seq('position_position_id_seq', 'position', 'position_id')
            write_seq('employee_employee_id_seq', 'employee', 'employee_id')
            write_seq('payroll_payroll_id_seq', 'payroll', 'payroll_id')
            write_seq('employee_license_license_id_seq', 'employee_license', 'license_id')
            write_seq('oncall_shift_shift_id_seq', 'oncall_shift', 'shift_id')
        paths['sequences'] = seq_file

    counts = {
        'departments': len(dept_rows),
        'positions': len(pos_rows),
        'employees': len(emp_rows),
        'payroll': len(pay_rows),
        'licenses': len(lic_rows),
        'shifts': len(shift_rows)
    }
    return paths, counts

# --------------------------- CLI ---------------------------

def parse_args():
    p = argparse.ArgumentParser(description='Generate personnel SQL files with explicit IDs (no cycles / leveled licenses / improved shifts).')
    p.add_argument('--employees', '-n', type=int, default=DEFAULT_NUM_EMPLOYEES, help='Number of employees to generate (default %(default)s).')
    p.add_argument('--outdir', '-o', default=OUT_DIR_DEFAULT, help='Output directory for SQL files.')
    p.add_argument('--no-sequences', action='store_true', help='Do not write the set_sequences.sql file.')
    return p.parse_args()

def main():
    args = parse_args()
    print('Generator starting with employees=%d, outdir=%s' % (args.employees, args.outdir))
    paths, counts = generate_files(num_employees=args.employees, out_dir=args.outdir, write_sequences=(not args.no_sequences))
    print('Files written:')
    for k, v in paths.items():
        print(' - %s: %s' % (k, v))
    print('Row counts: %s' % json.dumps(counts, indent=2))
    print('Done. You can import the SQL files into PostgreSQL.')

if __name__ == '__main__':
    main()
