# Databases_Mini-project_20205_324710144
proposal:

# Travel Agency Personnel Schema

This document describes the **Personnel** section of a travel agency database.  
It explains the high-level goals, the chosen entities, relationships, normalization steps, and supported workflows.

---

## High-Level Goals and Intent
The personnel schema was designed to capture the core HR and staffing data needed by a travel agency.  
This database is designed to manage the personnel and operational data of a travel agency. It organizes employee records, payroll information, and on-call shift schedules in a structured and efficient way. The system ensures data integrity through constraints on key attributes such as hire dates, ages, and payroll amounts, while also maintaining clear relationships between employees, payroll records, and shifts. By providing a reliable framework for storing and querying information, the database supports the agency’s day-to-day operations and enables accurate reporting and decision-making. 

The database should make it easy to answer practical questions such as:
- Which employees are in each department and position?  
- Who manages whom?  
- Has every employee been paid appropriately?  
- When do licenses expire?  
- Who is scheduled to be on call at a given time?  

---

# ERD:
<img width="3066" height="1548" alt="erdplus (4)" src="https://github.com/user-attachments/assets/0725ae09-701a-4e6f-883d-13faed391242" />

<img width="798" height="550" alt="image" src="https://github.com/user-attachments/assets/0774995e-01ca-4feb-b05e-9ea212c5227e" />


## Final Chosen Entities (and Why)

### `department`
- Canonical list of departments (Personnel, Ticketing, Advertising, etc.).  
- Centralizes department names, prevents duplication, and enables consistent reporting.  

### `position`
- Job roles/titles, each linked to a department.  
- Normalizes role definitions so they can be reused across employees and analyzed consistently.  

### `employee`
- Core entity for individuals working at the agency.  
- Stores identifying info, hire/termination dates, birth date, reporting manager (self-reference), emergency contacts, and related notes.  
- Acts as the anchor for payroll, licenses, and on-call scheduling.  

### `payroll`
- Records pay events tied to employees.  
- Supports payroll history queries, compliance checks, and audit trails.  
- Enforces that pay dates cannot precede the employee’s hire date.  

### `employee_license`
- Stores professional certifications or licenses with issued and expiry dates.  
- Allows compliance officers to monitor license validity and upcoming expirations.  

### `oncall_shift`
- Weekly recurring shifts with employee, day of week, start and end time, and escalation order.  
- Supports staffing and escalation processes for customer or operational issues.  

---

## Relationships and Keys
- `position.department_id` → `department.department_id`  
- `employee.department_id` → `department.department_id`  
- `employee.position_id` → `position.position_id`  
- `employee.manager_id` → `employee.employee_id` (self-reference)  
- `payroll.employee_id`, `employee_license.employee_id`, `oncall_shift.employee_id` → `employee.employee_id`  

These relationships maintain referential integrity and make reporting straightforward.  

---

## Normalization Reasoning
- Each table holds atomic values with no repeating groups (1NF).  
- Non-key attributes depend on the whole primary key (2NF).  
- No transitive dependencies; role and department details are separated from employee records (3NF).  
- The only intentional relaxation is using JSONB for emergency contacts, chosen for flexibility where structure varies and query frequency is low.  

---

## Use Cases and Workflows Supported
- **Onboarding:** Add new employees with department, position, manager, and emergency contacts.  
- **Payroll:** Track pay history for each employee, ensuring compliance with hire dates.  
- **Compliance:** Monitor license expirations and maintain valid certification records.  
- **On-call scheduling:** Assign recurring shifts and escalation orders for employees.  
- **Management:** Build reporting structures and analyze department or position distributions.  

---

## What This Design Does Not Cover
- Detailed payroll mechanics (salaries, deductions, taxes, bank accounts).  
- Leave, vacation, or absence tracking.  
- Full audit trails of all data changes.  
- Authentication, authorization, or role-based access control.  
- Automated notifications (license expiry alerts, on-call reminders).  
- Multi-timezone support.

## Data Generation:
https://github.com/Yosef100/Databases_Mini-project_20205_324710144/blob/main/personnel_generator.py

## Dump/Restore Test:
<img width="553" height="295" alt="image" src="https://github.com/user-attachments/assets/2032c380-fb8e-4c5d-9f96-217507f65ae3" />
<img width="566" height="279" alt="image" src="https://github.com/user-attachments/assets/25449eae-aaa4-40ef-a192-2573a52302ee" />

## Stage 2:
# Backups:
the script, backup and log for the two backup methods

A.

https://github.com/Yosef100/Databases_Mini-project_20205_324710144/blob/main/PSQL%20backup%20script.bat
https://github.com/Yosef100/Databases_Mini-project_20205_324710144/blob/main/backupSQL.sql
https://github.com/Yosef100/Databases_Mini-project_20205_324710144/blob/main/backupSQL.log

B.

https://github.com/Yosef100/Databases_Mini-project_20205_324710144/blob/main/PSQL%20backup%20script.bat
https://github.com/Yosef100/Databases_Mini-project_20205_324710144/blob/main/backupPSQL.sql
https://github.com/Yosef100/Databases_Mini-project_20205_324710144/blob/main/backupPSQL.log

# Queries
https://github.com/Yosef100/Databases_Mini-project_20205_324710144/blob/main/Queries.sql

Select:

1- list every active employee with their department name, job title and manager's name (if any), ordered alphabetically by last name.

2- for each month with payroll activity, show how many payments were made and the total, average, minimum and maximum payment amounts — newest months first.

3- find all employee licenses that will expire in the next 60 days, with how many days remain — ordered by nearest expiry.

4- for each employee show how many on-call shifts they have and the total on-call time (as an interval), ordered by who has the most on-call time.


Update:

5- deactivate employees in departments with low average payroll

6- For each employee and day of the week, compute the correct ordering of that employee's shifts and update the escalation_order column accordingly


Delete:

7- delete license rows belonging to employees who are already inactive and whose expiry_date is more than 1 year ago.

8- delete old oncall_shift rows, keeping the most recent per employee


Parametrized:

9- the top N employees (by total payroll amount) in department department_name between start_date and end_date.

10- for the next X days (where X = days_ahead), list employees who have licenses that will expire, how many licenses will expire, and the nearest expiry date — ordered by most urgent

11- for year YYYY (pass as year), compute each employee's total pay that year, then summarize those per position: how many employees had payroll activity, average of employee totals, min, max and sum — sorted by average descending

12- for the chosen day_of_week, find every pair of employees who have shifts that overlap in time. Returns each pair, how many overlapping shift-pairs they have, and the earliest/latest overlap times (per grouped set).


# Indexes:
Added indexes on:

- paydate of Payroll - aids in queries 2,7,9,11

- dept. ID of Employee - aids in queries 1,8,9,11

- expiry_date of employee_license - aids in queries 3,10

# Timing: Before | After
<img width="317" height="339" alt="image" src="https://github.com/user-attachments/assets/3c5c9b35-e28e-468e-8fee-6cf37a0f75a1" />


# Constraints
https://github.com/Yosef100/Databases_Mini-project_20205_324710144/blob/main/Constraints.sql

- department — NOT NULL — name must be present.

- department — UNIQUE — name must be unique.

- position — NOT NULL — title must be present.

- position — UNIQUE — title must be unique.

- employee — NOT NULL — first_name must be present.

- employee — NOT NULL — last_name must be present.

- employee — NOT NULL — hire_date must be present.

- employee — CHECK — termination_date, if present, must be after hire_date.

- employee — CHECK — if birth_date is present, age at hire must be between 18 and 65 years.

- employee — CHECK — email must not be NULL or blank.

- employee — UNIQUE — email must be unique.

- employee — TRIGGER (row-level BEFORE) — manager_id assignments must not create a management cycle (no A→B→…→A loops; also disallow self-management).

- payroll — NOT NULL — employee_id must be present.

- payroll — NOT NULL — amount must be present.

- payroll — NOT NULL — pay_date must be present.

- payroll — CHECK — amount must be non-negative.

- payroll — TRIGGER (row-level BEFORE) — pay_date must be on or after the referenced employee’s hire_date.

- oncall_shift — NOT NULL — day_of_week must be present.

- oncall_shift — CHECK — day_of_week must be between 1 and 7.

- oncall_shift — NOT NULL — start_time must be present.

- oncall_shift — NOT NULL — end_time must be present.

- oncall_shift — NOT NULL — escalation_order must be present.

- oncall_shift — CHECK — escalation_order must be greater than zero.

- oncall_shift — CHECK — start_time must be before end_time.

employee_license — TRIGGER (row-level BEFORE) — prevents inserting/updating a lower-level license when a higher-level license for the same employee + field already exists (levels: junior < intermediate < senior).

log

<img width="862" height="505" alt="constraints" src="https://github.com/user-attachments/assets/622ae9b6-029f-48f5-b114-721a40257e17" />


Violations:

script:

https://github.com/Yosef100/Databases_Mini-project_20205_324710144/blob/main/ConstraintsViolations.sql

error types:

NOT NULL
Effect: Attempting to insert or update a row with a NULL value in a NOT NULL column.

UNIQUE
Effect: Attempting to insert or update a row with a duplicate value in a column or column combination defined as UNIQUE.

CHECK
Effect: Attempting to insert or update a row that violates the condition specified in a CHECK constraint.

TRIGGER (row-level BEFORE)
Effect: Custom procedural validation logic failed; the trigger raised an exception because the operation violated a business rule (e.g., cycle in management, invalid date order, or lower-level license insertion).


resulting errors:

https://github.com/Yosef100/Databases_Mini-project_20205_324710144/blob/main/constrainsViolationsOutput.txt

Explanation of errors:

https://github.com/Yosef100/Databases_Mini-project_20205_324710144/blob/main/constraintsErrorsExplanations.txt


## Stage 3:

# Queries

Select

- list of Organizations Phone Book + Department/Position/Manager
- list of Cumulative monthly salary for each department (last 12 months)
- list of Licenses that are about to expire (30 days ahead) or have expired

Time:
<img width="1708" height="1545" alt="image" src="https://github.com/user-attachments/assets/f0835629-d568-40c9-9377-ea496135579e" />
<img width="1696" height="1356" alt="image" src="https://github.com/user-attachments/assets/dd286d6e-0df3-4146-b4ae-9c352e3c33ed" />
<img width="1687" height="1326" alt="image" src="https://github.com/user-attachments/assets/54de496e-3295-44a8-a12e-1040aee96453" />


script:
https://github.com/Yosef100/Databases_Mini-project_20205_324710144/blob/main/Stage%203%20query

# view
first view: active employees
<img width="1648" height="860" alt="image" src="https://github.com/user-attachments/assets/96164b1e-a38d-45a1-b036-287d21e6c933" />

second view: oncall valid
<img width="1640" height="980" alt="image" src="https://github.com/user-attachments/assets/fe70beaa-d302-4c8e-935c-5504607bd8b4" />
The day is out of the day that exist. Error.

third view: current licenses
<img width="1627" height="835" alt="image" src="https://github.com/user-attachments/assets/17affee8-10dd-47a8-bb03-5dbe00f0986b" />
v3 is updatable he didn't know where to go.

fourth view: all about the employee
<img width="1637" height="831" alt="image" src="https://github.com/user-attachments/assets/740f3bb0-55e2-45c2-ab6c-176c22eedab8" />
v4 is updatable he didn't know where to go.

script:
https://github.com/Yosef100/Databases_Mini-project_20205_324710144/blob/main/view


# visualization

first - pie chart
- Active employees by department
<img width="2212" height="1343" alt="image" src="https://github.com/user-attachments/assets/65c6ae11-9541-42b5-b656-22b5ec8074cb" />

second - bar
- Cumulative on-call hours by day of the week
<img width="2215" height="1337" alt="image" src="https://github.com/user-attachments/assets/1bc82b6f-254d-48b1-ae67-7d11845abea7" />

# function

first - Returning the employee's full name. (now we can put the full name in one time)

second - License status by validity. (we don't need to write case anymore)

third - Total payments to an employee in a particular month. (we don't need sum for this anymore)

fourth - Counting employees in the department. 

<img width="798" height="238" alt="image" src="https://github.com/user-attachments/assets/5d54bfa2-918f-4676-8ea5-54b0bb72102e" />

script:
https://github.com/Yosef100/Databases_Mini-project_20205_324710144/blob/main/function

New_query_with_the_function:
https://github.com/Yosef100/Databases_Mini-project_20205_324710144/blob/main/stage_3_new_query
run_time:
<img width="1695" height="1539" alt="image" src="https://github.com/user-attachments/assets/3f94516f-e861-47e8-88d7-8f6883d99528" />
<img width="1706" height="1241" alt="image" src="https://github.com/user-attachments/assets/7ff98632-3c01-4b9e-8a2b-d491944853c5" />
<img width="1709" height="1205" alt="image" src="https://github.com/user-attachments/assets/2df82a42-95e8-4690-8d7a-70082626da45" />
We can see that the running times are shorter.

## Stage 4:
The goal of the phase: Integrate our database (HR) with another team's external database (Advertising), perform a logical merge using FDW + mapping table, build useful views, and produce more ERD/DSD diagrams and full data.

# Integration between two databases (FDW)
Creating an extension (once per DB) and creating a Foreign Server and User Mapping:
<img width="1709" height="666" alt="image" src="https://github.com/user-attachments/assets/8db2a883-8906-48e5-a92d-06b6b73d2eb2" />
Logical schemes on our side:
<img width="1621" height="372" alt="image" src="https://github.com/user-attachments/assets/3820c059-1077-440d-9749-2066703001f4" />
Import schemas/tables from the other team (FDW → Foreign Tables):
<img width="1667" height="556" alt="image" src="https://github.com/user-attachments/assets/2a60748c-1772-4492-9290-87abfeb4df07" />
Preparing the data on our side (HR)
We assume that the core tables are in main (e.g. main.employee, main.department, main.position).
Checking columns:
<img width="1265" height="476" alt="image" src="https://github.com/user-attachments/assets/16d6772f-c081-4a5d-9206-c229a2e95f62" />
Mapping table (Bridge) – logical bridge between HR and Ads:
<img width="1252" height="684" alt="image" src="https://github.com/user-attachments/assets/71d5cf16-7180-40e2-a4ae-821f34317057" />

# view:
the first view:
Agent Profile ↔ HR Employee
<img width="1713" height="826" alt="image" src="https://github.com/user-attachments/assets/da6d88e0-14c7-485c-8eeb-e72d8f557538" />
select:
<img width="1702" height="1272" alt="image" src="https://github.com/user-attachments/assets/a6436886-9729-4cd3-bf7c-6932a0b97799" />
dml:
<img width="1716" height="1143" alt="image" src="https://github.com/user-attachments/assets/01e02c9e-6f45-4f52-91d5-144a9f28b7c9" />

the second view:
Mapping table wrapper
<img width="1707" height="891" alt="image" src="https://github.com/user-attachments/assets/d9630b4e-c481-436e-894b-f6c9a72bc195" />
select:
<img width="1720" height="1333" alt="image" src="https://github.com/user-attachments/assets/4ab8c3fe-004e-4c38-ae42-32b40495c735" />
dml:
<img width="1712" height="1008" alt="image" src="https://github.com/user-attachments/assets/4fecdf66-c43b-437b-9f53-5f456c660af1" />

# queriers:
first querier:
![תמונה של WhatsApp‏ 2025-10-15 בשעה 22 24 20_183db99f](https://github.com/user-attachments/assets/08282322-870b-47bc-abe1-3e1be6f66d89)



