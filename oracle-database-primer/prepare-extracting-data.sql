rem
rem SCRIPT prepare-extracting-data.sql
rem
rem COURSE Oracle Database Primer
rem        https://teamoneill.org/course/oracle-database-primer
rem
rem LESSON Extracting Data
rem        https://teamoneill.org/lesson/extracting-data
rem
rem 2020-12-06  teamoneill  created
rem
rem Copyright (c) 2020 Michael O'Neill. All rights reserved.
rem 
rem Permission is granted, free of charge, to any person obtaining
rem a copy of this script to use or modify it.
rem 
rem THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND
rem EXPRESSED OR IMPLIED
rem

set echo off
clear screen
set serveroutput on
set feedback off
set define off;
whenever sqlerror exit 1;

------------------------------------------------------------------------------------------------------------------------------------
prompt    Script: prepare-extracting-data.sql
prompt    Course: Oracle Database Primer
prompt    Lesson: Extracting Data
------------------------------------------------------------------------------------------------------------------------------------

------------------------------------------------------------------------------------------------------------------------------------
prompt
prompt check for necessary privileges
------------------------------------------------------------------------------------------------------------------------------------
prompt CREATE PROCEDURE
prompt CREATE SEQUENCE
prompt CREATE TABLE
prompt CREATE TRIGGER
prompt CREATE VIEW
------------------------------------------------------------------------------------------------------------------------------------
declare
   privilege_count_actual integer := 0;
   privilege_count_required integer := 5;
begin
   select count(1)
     into privilege_count_actual
     from session_privs 
    where privilege in ( 'CREATE TABLE', 'CREATE VIEW', 'CREATE PROCEDURE', 'CREATE TRIGGER', 'CREATE SEQUENCE' );

   if (privilege_count_actual < privilege_count_required) then
      raise_application_error(-20000, 'this script requires: CREATE INDEX, CREATE TABLE, CREATE VIEW, CREATE PROCEDURE, CREATE TRIGGER, CREATE SEQUENCE privileges');
   end if;
end;
/

------------------------------------------------------------------------------------------------------------------------------------
prompt
prompt breakdown any exisisting lesson objects
------------------------------------------------------------------------------------------------------------------------------------
declare
   type object_record_type is record (object_type varchar2(30), object_name varchar2(128), object_exists boolean := false, object_scripted boolean := false);
   type object_table_type is table of object_record_type;

   objects object_table_type := new object_table_type();

   function does_object_exist (p_object in object_record_type) return boolean is
      v_found integer := 0;
   begin
      select count(1)
        into v_found
        from user_objects
       where object_type = decode(p_object.object_type, 'PACKAGE', 'PACKAGE SPECIFICATION', p_object.object_type)
         and object_name = p_object.object_name;
      
      if (v_found) = 0 then 
         return false;
      else 
         return true;
      end if;
   end does_object_exist; 

   function is_object_scripted (p_object in object_record_type) return boolean is
      v_found integer := 0;
   begin
      case
         when p_object.object_type in ('PROCEDURE','FUNCTION','PACKAGE')
         then
            select count(1)
              into v_found
              from user_source 
             where type = decode(p_object.object_type, 'PACKAGE', 'PACKAGE SPECIFICATION', p_object.object_type)
               and name = p_object.object_name 
               and text like '%/*(scripted by teamoneill.org)*/%';
 
         when p_object.object_type in ('TABLE','VIEW')
         then
            select count(1)
              into v_found
              from user_tab_comments 
             where table_type = p_object.object_type
               and table_name = p_object.object_name 
               and comments like '%/*(scripted by teamoneill.org)*/%';
               
         when p_object.object_type = 'SEQUENCE'
         then
            select count(1)
              into v_found
              from user_col_comments 
             where comments like '%/*(scripted by teamoneill.org ' || p_object.object_name || ')*/%';
         
         else
            return null; -- object_type is unknown to function
      end case;
      
      if (v_found) = 0 then 
         return false;
      else 
         return true;
      end if;
   end is_object_scripted; 
   
   procedure add_object_to_drop (p_objects in out object_table_type, p_object in object_record_type) is
      v_object object_record_type := p_object;
   begin     
      p_objects.extend;
      v_object.object_exists := does_object_exist(p_object);
      v_object.object_scripted := is_object_scripted(p_object);
      p_objects(p_objects.last) := v_object;
   end add_object_to_drop;

   procedure add_objects_to_drop(p_objects in out object_table_type) is
   begin
      add_object_to_drop(p_objects, new object_record_type('PROCEDURE','ADD_JOB_HISTORY',false,false));
      add_object_to_drop(p_objects, new object_record_type('PROCEDURE','SECURE_DML',false,false));
      --add_object(p_objects, new object_record_type('FUNCTION','FUNCTION_NAME',false,false));
      --add_object(p_objects, new object_record_type('PACKAGE','PACKAGE_NAME',false,false));
      add_object_to_drop(p_objects, new object_record_type('VIEW','EMP_DETAILS_VIEW',false,false));
      add_object_to_drop(p_objects, new object_record_type('TABLE','COUNTRIES',false,false));
      add_object_to_drop(p_objects, new object_record_type('TABLE','DEPARTMENTS',false,false));
      add_object_to_drop(p_objects, new object_record_type('TABLE','EMPLOYEES',false,false));
      add_object_to_drop(p_objects, new object_record_type('TABLE','JOB_HISTORY',false,false));
      add_object_to_drop(p_objects, new object_record_type('TABLE','JOBS',false,false));
      add_object_to_drop(p_objects, new object_record_type('TABLE','LOCATIONS',false,false));
      add_object_to_drop(p_objects, new object_record_type('TABLE','REGIONS',false,false));
      add_object_to_drop(p_objects, new object_record_type('SEQUENCE','DEPARTMENTS_SEQ',false,false));
      add_object_to_drop(p_objects, new object_record_type('SEQUENCE','EMPLOYEES_SEQ',false,false));
      add_object_to_drop(p_objects, new object_record_type('SEQUENCE','LOCATIONS_SEQ',false,false)); 
   end add_objects_to_drop;
   procedure drop_objects (p_objects in out object_table_type) is
      type commands_table_type is table of varchar2(4000) index by pls_integer;
      commands commands_table_type;
      command varchar2(4000);
   begin
      for i in p_objects.first .. p_objects.last
      loop
         if (NOT p_objects(i).object_exists) then
            --dbms_output.put_line('could not drop ' || p_objects(i).object_type || ' "' || p_objects(i).object_name || '" (does not exist)');
            null;
         elsif (NOT p_objects(i).object_scripted) then
            --dbms_output.put_line('could not drop ' || p_objects(i).object_type || ' "' || p_objects(i).object_name || '" (not scripted by teamoneill.org)');
            raise_application_error(-20000, 'script cannot continue - cannot not drop ' || p_objects(i).object_type || ' "' || p_objects(i).object_name || '" (not scripted by teamoneill.org)');
         else
            command := 'DROP ' || p_objects(i).object_type || ' "' || p_objects(i).object_name || '"';
            if (p_objects(i).object_type = 'TABLE') then
               command := command || ' CASCADE CONSTRAINTS';
            end if;
            commands(commands.count+1) := command;
            --execute immediate (command);
            --dbms_output.put_line('dropped ' || p_objects(i).object_type || ' "' || p_objects(i).object_name || '" ');            
         end if;        
      end loop;
         
      for i in 1 .. commands.count
      loop
         begin
            execute immediate (commands(i));
         exception
            when others 
            then 
               raise_application_error(-20000, 'script cannot continue - cannot not drop ' || p_objects(i).object_type || ' "' || p_objects(i).object_name || '" (' || sqlerrm || ')');
         end;
      end loop;
   end drop_objects;
begin
   add_objects_to_drop(objects);
   drop_objects(objects);
end;
/
purge recyclebin;
commit;

------------------------------------------------------------------------------------------------------------------------------------
prompt
prompt create tables
------------------------------------------------------------------------------------------------------------------------------------
create table countries (
   country_id
      char(2)
      constraint country_c_id_pk primary key
      constraint country_id_nn not null,
   country_name
      varchar2(40),
   region_id
      number)
organization index;
comment on table countries is 'country table. Contains 25 rows. References with locations table. /*(scripted by teamoneill.org)*/';
comment on column countries.country_id is 'Primary key of countries table.';
comment on column countries.country_name is 'Country name';
comment on column countries.region_id is 'Region ID for the country. Foreign key to region_id column in the departments table.';
prompt COUNTRIES


create table departments (
   department_id
      number(4)
      constraint dept_id_pk primary key,
   department_name
      varchar2(30)
      constraint dept_name_nn not null,
   manager_id
      number(6),
   location_id     
      number(4));
comment on table departments is 'Departments table that shows details of departments where employees work. Contains 27 rows; references with locations, employees, and job_history tables. /*(scripted by teamoneill.org)*/';
comment on column departments.department_id is 'Primary key column of departments table. /*(scripted by teamoneill.org DEPARTMENTS_SEQ)*/';
comment on column departments.department_name is 'A not null column that shows name of a department. Administration, Marketing, Purchasing, Human Resources, Shipping, IT, Executive, Public Relations, Sales, Finance, and Accounting. ';
comment on column departments.manager_id is 'Manager_id of a department. Foreign key to employee_id column of employees table. The manager_id column of the employee table references this column.';
comment on column departments.location_id is 'Location id where a department is located. Foreign key to location_id column of locations table.';
prompt DEPARTMENTS

create table employees (
   employee_id
      number(6)
      constraint emp_emp_id_pk primary key,
   first_name  
      varchar2(20),
   last_name
      varchar2(25)
      constraint emp_last_name_nn not null,
   email
      varchar2(25)
      constraint emp_email_nn not null,
   phone_number
      varchar2(20),
   hire_date
      date
      constraint emp_hire_date_nn not null,
   job_id
      varchar2(10)
      constraint emp_job_nn  not null,
   salary
      number(8,2),
   commission_pct
      number(2,2),
   manager_id
      number(6),
   department_id
      number(4),
   constraint emp_salary_min check (salary > 0),
   constraint emp_email_uk unique (email));
comment on table employees is 'employees table. Contains 107 rows. References with departments, jobs, job_history tables. Contains a self reference. /*(scripted by teamoneill.org)*/';
comment on column employees.employee_id is 'Primary key of employees table. /*(scripted by teamoneill.org EMPLOYEES_SEQ)*/';
comment on column employees.first_name is 'First name of the employee. A not null column.';
comment on column employees.last_name is 'Last name of the employee. A not null column.';
comment on column employees.email is 'Email id of the employee';
comment on column employees.phone_number is 'Phone number of the employee; includes country code and area code';
comment on column employees.hire_date is 'Date when the employee started on this job. A not null column.';
comment on column employees.job_id is 'Current job of the employee; foreign key to job_id column of the jobs table. A not null column.';
comment on column employees.salary is 'Monthly salary of the employee. Must be greater than zero (enforced by constraint emp_salary_min)';
comment on column employees.commission_pct is 'Commission percentage of the employee; Only employees in sales department elgible for commission percentage';
comment on column employees.manager_id is 'Manager id of the employee; has same domain as manager_id in departments table. Foreign key to employee_id column of employees table. (useful for reflexive joins and CONNECT BY query)';
comment on column employees.department_id is 'Department id where employee works; foreign key to department_id column of the departments table';
prompt EMPLOYEES

create table job_history (
   employee_id
      number(6)
      constraint jhist_employee_nn not null,
   start_date
      date
      constraint jhist_start_date_nn not null,
   end_date
      date
      constraint jhist_end_date_nn not null,
   job_id
      varchar2(10)
      constraint jhist_job_nn not null,
   department_id number(4),
   constraint jhist_emp_id_st_date_pk primary key (employee_id, start_date),
   constraint jhist_date_interval check (end_date > start_date));
comment on table job_history is 'Table that stores job history of the employees. If an employee changes departments within the job or changes jobs within the department, new rows get inserted into this table with old job information of the employee. Contains a complex primary key: employee_id+start_date. Contains 25 rows. References with jobs, employees, and departments tables. /*(scripted by teamoneill.org)*/';
comment on column job_history.employee_id is 'A not null column in the complex primary key employee_id+start_date. Foreign key to employee_id column of the employee table';
comment on column job_history.start_date is 'A not null column in the complex primary key employee_id+start_date. Must be less than the end_date of the job_history table. (enforced by constraint jhist_date_interval)';
comment on column job_history.end_date is 'Last day of the employee in this job role. A not null column. Must be greater than the start_date of the job_history table. (enforced by constraint jhist_date_interval)';
comment on column job_history.job_id is 'Job role in which the employee worked in the past; foreign key to job_id column in the jobs table. A not null column.';
comment on column job_history.department_id is 'Department id in which the employee worked in the past; foreign key to deparment_id column in the departments table';
prompt JOB_HISTORY

create table jobs (
   job_id
      varchar2(10)
      constraint job_id_pk primary key,
   job_title
      varchar2(35)
      constraint job_title_nn not null,
   min_salary
      number(6),
   max_salary
      number(6));
comment on table jobs is 'jobs table with job titles and salary ranges. Contains 19 rows. References with employees and job_history table. /*(scripted by teamoneill.org)*/';
comment on column jobs.job_id is 'Primary key of jobs table.';
comment on column jobs.job_title is 'A not null column that shows job title, e.g. AD_VP, FI_ACCOUNTANT';
comment on column jobs.min_salary is 'Minimum salary for a job title.';
comment on column jobs.max_salary is 'Maximum salary for a job title';
prompt JOBS

create table locations (
   location_id
      number(4)
      constraint loc_id_pk primary key,
   street_address
      varchar2(40),
   postal_code
      varchar2(12),
   city
      varchar2(30)
      constraint loc_city_nn  not null,
   state_province
      varchar2(25),
   country_id
      char(2));
comment on table locations is 'Locations table that contains specific address of a specific office, warehouse, and/or production site of a company. Does not store addresses / locations of customers. Contains 23 rows; references with the departments and countries tables. /*(scripted by teamoneill.org)*/';
comment on column locations.location_id is 'Primary key of locations table. /*(scripted by teamoneill.org LOCATIONS_SEQ)*/';
comment on column locations.street_address is 'Street address of an office, warehouse, or production site of a company. Contains building number and street name';
comment on column locations.postal_code is 'Postal code of the location of an office, warehouse, or production site of a company. ';
comment on column locations.city is 'A not null column that shows city where an office, warehouse, or production site of a company is located. ';
comment on column locations.state_province is 'State or Province where an office, warehouse, or production site of a company is located.';
comment on column locations.country_id is 'Country where an office, warehouse, or production site of a company is located. Foreign key to country_id column of the countries table.';
prompt LOCATIONS

create table regions (
   region_id
      number
      constraint reg_id_pk primary key
      constraint region_id_nn not null,
   region_name
      varchar2(25));
comment on table regions is 'Regions table that contains region numbers and names. Contains 4 rows; references with the Countries table. /*(scripted by teamoneill.org)*/';
comment on column regions.region_id is 'Primary key of regions table.';
comment on column regions.region_name is 'Names of regions. Locations are in the countries of these regions.';
prompt REGIONS

------------------------------------------------------------------------------------------------------------------------------------
prompt
prompt create sequences
------------------------------------------------------------------------------------------------------------------------------------
create sequence departments_seq
   start with     280
   increment by   10
   maxvalue       9990
   nocache
   nocycle;  
prompt DEPARTMENTS_SEQ

create sequence employees_seq
   start with     207
   increment by   1
   nocache
   nocycle;
prompt EMPLOYEES_SEQ

create sequence locations_seq
   start with     3300
   increment by   100
   maxvalue       9900
   nocache
   nocycle;
prompt LOCATIONS_SEQ

------------------------------------------------------------------------------------------------------------------------------------
prompt
prompt create views
------------------------------------------------------------------------------------------------------------------------------------
create or replace view emp_details_view (
   employee_id,
   job_id,
   manager_id,
   department_id,
   location_id,
   country_id,
   first_name,
   last_name,
   salary,
   commission_pct,
   department_name,
   job_title,
   city,
   state_province,
   country_name,
   region_name ) as 
select e.employee_id,
       e.job_id,
       e.manager_id,
       e.department_id,
       d.location_id,
       l.country_id,
       e.first_name,
       e.last_name,
       e.salary,
       e.commission_pct,
       d.department_name,
       j.job_title,
       l.city,
       l.state_province,
       c.country_name,
       r.region_name
  from employees e,
       departments d,
       jobs j,
       locations l,
       countries c,
       regions r
 where e.department_id = d.department_id
   and d.location_id = l.location_id
   and l.country_id = c.country_id
   and c.region_id = r.region_id
   and j.job_id = e.job_id 
with read only;
comment on table emp_details_view is 'Employees view /*(scripted by teamoneill.org)*/';
comment on column emp_details_view.employee_id is 'Primary key of employees table.';
comment on column emp_details_view.job_id is 'Current job of the employee; foreign key to job_id column of the jobs table. A not null column.';
comment on column emp_details_view.manager_id is 'Manager id of the employee; has same domain as manager_id in departments table. Foreign key to employee_id column of employees table. (useful for reflexive joins and CONNECT BY query)';
comment on column emp_details_view.department_id is 'Department id where employee works; foreign key to department_id column of the departments table';
comment on column emp_details_view.location_id is 'Location id where a department is located. Foreign key to location_id column of locations table.';
comment on column emp_details_view.first_name is 'First name of the employee. A not null column.';
comment on column emp_details_view.last_name is 'Last name of the employee. A not null column.';
comment on column emp_details_view.salary is 'Monthly salary of the employee. Must be greater than zero (enforced by constraint emp_salary_min)';
comment on column emp_details_view.commission_pct is 'Commission percentage of the employee; Only employees in sales department elgible for commission percentage';
comment on column emp_details_view.job_title is 'A not null column that shows job title, e.g. AD_VP, FI_ACCOUNTANT';
comment on column emp_details_view.city is 'A not null column that shows city where an office, warehouse, or production site of a company is located. ';
comment on column emp_details_view.state_province is 'State or Province where an office, warehouse, or production site of a company is located.';
comment on column emp_details_view.country_name is 'Country name';
comment on column emp_details_view.region_name is 'Names of regions. Locations are in the countries of these regions.';
prompt EMP_DETAILS_VIEW

------------------------------------------------------------------------------------------------------------------------------------
prompt
prompt insert data
------------------------------------------------------------------------------------------------------------------------------------
begin 
   insert into regions (region_id,region_name) values (1,'Europe');
   insert into regions (region_id,region_name) values (2,'Americas');
   insert into regions (region_id,region_name) values (3,'Asia');
   insert into regions (region_id,region_name) values (4,'Middle East and Africa');
   
   insert into countries (country_id,country_name,region_id) values ('IT','Italy',1);
   insert into countries (country_id,country_name,region_id) values ('JP','Japan',3);
   insert into countries (country_id,country_name,region_id) values ('US','United States of America',2);
   insert into countries (country_id,country_name,region_id) values ('CA','Canada',2);
   insert into countries (country_id,country_name,region_id) values ('CN','China',3);
   insert into countries (country_id,country_name,region_id) values ('IN','India',3);
   insert into countries (country_id,country_name,region_id) values ('AU','Australia',3);
   insert into countries (country_id,country_name,region_id) values ('ZW','Zimbabwe',4);
   insert into countries (country_id,country_name,region_id) values ('SG','Singapore',3);
   insert into countries (country_id,country_name,region_id) values ('UK','United Kingdom',1);
   insert into countries (country_id,country_name,region_id) values ('FR','France',1);
   insert into countries (country_id,country_name,region_id) values ('DE','Germany',1);
   insert into countries (country_id,country_name,region_id) values ('ZM','Zambia',4);
   insert into countries (country_id,country_name,region_id) values ('EG','Egypt',4);
   insert into countries (country_id,country_name,region_id) values ('BR','Brazil',2);
   insert into countries (country_id,country_name,region_id) values ('CH','Switzerland',1);
   insert into countries (country_id,country_name,region_id) values ('NL','Netherlands',1);
   insert into countries (country_id,country_name,region_id) values ('MX','Mexico',2);
   insert into countries (country_id,country_name,region_id) values ('KW','Kuwait',4);
   insert into countries (country_id,country_name,region_id) values ('IL','Israel',4);
   insert into countries (country_id,country_name,region_id) values ('DK','Denmark',1);
   insert into countries (country_id,country_name,region_id) values ('ML','Malaysia',3);
   insert into countries (country_id,country_name,region_id) values ('NG','Nigeria',4);
   insert into countries (country_id,country_name,region_id) values ('AR','Argentina',2);
   insert into countries (country_id,country_name,region_id) values ('BE','Belgium',1);
   
   insert into locations (location_id,street_address,postal_code,city,state_province,country_id) values (1000,'1297 Via Cola di Rie','00989','Roma',null,'IT');
   insert into locations (location_id,street_address,postal_code,city,state_province,country_id) values (1100,'93091 Calle della Testa','10934','Venice',null,'IT');
   insert into locations (location_id,street_address,postal_code,city,state_province,country_id) values (1200,'2017 Shinjuku-ku','1689','Tokyo','Tokyo Prefecture','JP');
   insert into locations (location_id,street_address,postal_code,city,state_province,country_id) values (1300,'9450 Kamiya-cho','6823','Hiroshima',null,'JP');
   insert into locations (location_id,street_address,postal_code,city,state_province,country_id) values (1400,'2014 Jabberwocky Rd','26192','Southlake','Texas','US');
   insert into locations (location_id,street_address,postal_code,city,state_province,country_id) values (1500,'2011 Interiors Blvd','99236','South San Francisco','California','US');
   insert into locations (location_id,street_address,postal_code,city,state_province,country_id) values (1600,'2007 Zagora St','50090','South Brunswick','New Jersey','US');
   insert into locations (location_id,street_address,postal_code,city,state_province,country_id) values (1700,'2004 Charade Rd','98199','Seattle','Washington','US');
   insert into locations (location_id,street_address,postal_code,city,state_province,country_id) values (1800,'147 Spadina Ave','M5V 2L7','Toronto','Ontario','CA');
   insert into locations (location_id,street_address,postal_code,city,state_province,country_id) values (1900,'6092 Boxwood St','YSW 9T2','Whitehorse','Yukon','CA');
   insert into locations (location_id,street_address,postal_code,city,state_province,country_id) values (2000,'40-5-12 Laogianggen','190518','Beijing',null,'CN');
   insert into locations (location_id,street_address,postal_code,city,state_province,country_id) values (2100,'1298 Vileparle (E)','490231','Bombay','Maharashtra','IN');
   insert into locations (location_id,street_address,postal_code,city,state_province,country_id) values (2200,'12-98 Victoria Street','2901','Sydney','New South Wales','AU');
   insert into locations (location_id,street_address,postal_code,city,state_province,country_id) values (2300,'198 Clementi North','540198','Singapore',null,'SG');
   insert into locations (location_id,street_address,postal_code,city,state_province,country_id) values (2400,'8204 Arthur St',null,'London',null,'UK');
   insert into locations (location_id,street_address,postal_code,city,state_province,country_id) values (2500,'Magdalen Centre, The Oxford Science Park','OX9 9ZB','Oxford','Oxford','UK');
   insert into locations (location_id,street_address,postal_code,city,state_province,country_id) values (2600,'9702 Chester Road','09629850293','Stretford','Manchester','UK');
   insert into locations (location_id,street_address,postal_code,city,state_province,country_id) values (2700,'Schwanthalerstr. 7031','80925','Munich','Bavaria','DE');
   insert into locations (location_id,street_address,postal_code,city,state_province,country_id) values (2800,'Rua Frei Caneca 1360 ','01307-002','Sao Paulo','Sao Paulo','BR');
   insert into locations (location_id,street_address,postal_code,city,state_province,country_id) values (2900,'20 Rue des Corps-Saints','1730','Geneva','Geneve','CH');
   insert into locations (location_id,street_address,postal_code,city,state_province,country_id) values (3000,'Murtenstrasse 921','3095','Bern','BE','CH');
   insert into locations (location_id,street_address,postal_code,city,state_province,country_id) values (3100,'Pieter Breughelstraat 837','3029SK','Utrecht','Utrecht','NL');
   insert into locations (location_id,street_address,postal_code,city,state_province,country_id) values (3200,'Mariano Escobedo 9991','11932','Mexico City','Distrito Federal,','MX');
   
   insert into departments (department_id,department_name,manager_id,location_id) values (10,'Administration',200,1700);
   insert into departments (department_id,department_name,manager_id,location_id) values (20,'Marketing',201,1800);
   insert into departments (department_id,department_name,manager_id,location_id) values (30,'Purchasing',114,1700);
   insert into departments (department_id,department_name,manager_id,location_id) values (40,'Human Resources',203,2400);
   insert into departments (department_id,department_name,manager_id,location_id) values (50,'Shipping',121,1500);
   insert into departments (department_id,department_name,manager_id,location_id) values (60,'IT',103,1400);
   insert into departments (department_id,department_name,manager_id,location_id) values (70,'Public Relations',204,2700);
   insert into departments (department_id,department_name,manager_id,location_id) values (80,'Sales',145,2500);
   insert into departments (department_id,department_name,manager_id,location_id) values (90,'Executive',100,1700);
   insert into departments (department_id,department_name,manager_id,location_id) values (100,'Finance',108,1700);
   insert into departments (department_id,department_name,manager_id,location_id) values (110,'Accounting',205,1700);
   insert into departments (department_id,department_name,manager_id,location_id) values (120,'Treasury',null,1700);
   insert into departments (department_id,department_name,manager_id,location_id) values (130,'Corporate Tax',null,1700);
   insert into departments (department_id,department_name,manager_id,location_id) values (140,'Control And Credit',null,1700);
   insert into departments (department_id,department_name,manager_id,location_id) values (150,'Shareholder Services',null,1700);
   insert into departments (department_id,department_name,manager_id,location_id) values (160,'Benefits',null,1700);
   insert into departments (department_id,department_name,manager_id,location_id) values (170,'Manufacturing',null,1700);
   insert into departments (department_id,department_name,manager_id,location_id) values (180,'Construction',null,1700);
   insert into departments (department_id,department_name,manager_id,location_id) values (190,'Contracting',null,1700);
   insert into departments (department_id,department_name,manager_id,location_id) values (200,'Operations',null,1700);
   insert into departments (department_id,department_name,manager_id,location_id) values (210,'IT Support',null,1700);
   insert into departments (department_id,department_name,manager_id,location_id) values (220,'NOC',null,1700);
   insert into departments (department_id,department_name,manager_id,location_id) values (230,'IT Helpdesk',null,1700);
   insert into departments (department_id,department_name,manager_id,location_id) values (240,'Government Sales',null,1700);
   insert into departments (department_id,department_name,manager_id,location_id) values (250,'Retail Sales',null,1700);
   insert into departments (department_id,department_name,manager_id,location_id) values (260,'Recruiting',null,1700);
   insert into departments (department_id,department_name,manager_id,location_id) values (270,'Payroll',null,1700);
   
   insert into jobs (job_id,job_title,min_salary,max_salary) values ('AD_PRES','President',20080,40000);
   insert into jobs (job_id,job_title,min_salary,max_salary) values ('AD_VP','Administration Vice President',15000,30000);
   insert into jobs (job_id,job_title,min_salary,max_salary) values ('AD_ASST','Administration Assistant',3000,6000);
   insert into jobs (job_id,job_title,min_salary,max_salary) values ('FI_MGR','Finance Manager',8200,16000);
   insert into jobs (job_id,job_title,min_salary,max_salary) values ('FI_ACCOUNT','Accountant',4200,9000);
   insert into jobs (job_id,job_title,min_salary,max_salary) values ('AC_MGR','Accounting Manager',8200,16000);
   insert into jobs (job_id,job_title,min_salary,max_salary) values ('AC_ACCOUNT','Public Accountant',4200,9000);
   insert into jobs (job_id,job_title,min_salary,max_salary) values ('SA_MAN','Sales Manager',10000,20080);
   insert into jobs (job_id,job_title,min_salary,max_salary) values ('SA_REP','Sales Representative',6000,12008);
   insert into jobs (job_id,job_title,min_salary,max_salary) values ('PU_MAN','Purchasing Manager',8000,15000);
   insert into jobs (job_id,job_title,min_salary,max_salary) values ('PU_CLERK','Purchasing Clerk',2500,5500);
   insert into jobs (job_id,job_title,min_salary,max_salary) values ('ST_MAN','Stock Manager',5500,8500);
   insert into jobs (job_id,job_title,min_salary,max_salary) values ('ST_CLERK','Stock Clerk',2008,5000);
   insert into jobs (job_id,job_title,min_salary,max_salary) values ('SH_CLERK','Shipping Clerk',2500,5500);
   insert into jobs (job_id,job_title,min_salary,max_salary) values ('IT_PROG','Programmer',4000,10000);
   insert into jobs (job_id,job_title,min_salary,max_salary) values ('MK_MAN','Marketing Manager',9000,15000);
   insert into jobs (job_id,job_title,min_salary,max_salary) values ('MK_REP','Marketing Representative',4000,9000);
   insert into jobs (job_id,job_title,min_salary,max_salary) values ('HR_REP','Human Resources Representative',4000,9000);
   insert into jobs (job_id,job_title,min_salary,max_salary) values ('PR_REP','Public Relations Representative',4500,10500);
   
   insert into employees (employee_id,first_name,last_name,email,phone_number,hire_date,job_id,salary,commission_pct,manager_id,department_id) values (196,'Alana','Walsh','AWALSH','650.507.9811',to_date('2006-04-24 00:00:00','YYYY-MM-DD HH24:MI:SS'),'SH_CLERK',3100,null,124,50);
   insert into employees (employee_id,first_name,last_name,email,phone_number,hire_date,job_id,salary,commission_pct,manager_id,department_id) values (197,'Kevin','Feeney','KFEENEY','650.507.9822',to_date('2006-05-23 00:00:00','YYYY-MM-DD HH24:MI:SS'),'SH_CLERK',3000,null,124,50);
   insert into employees (employee_id,first_name,last_name,email,phone_number,hire_date,job_id,salary,commission_pct,manager_id,department_id) values (198,'Donald','OConnell','DOCONNEL','650.507.9833',to_date('2007-06-21 00:00:00','YYYY-MM-DD HH24:MI:SS'),'SH_CLERK',2600,null,124,50);
   insert into employees (employee_id,first_name,last_name,email,phone_number,hire_date,job_id,salary,commission_pct,manager_id,department_id) values (199,'Douglas','Grant','DGRANT','650.507.9844',to_date('2008-01-13 00:00:00','YYYY-MM-DD HH24:MI:SS'),'SH_CLERK',2600,null,124,50);
   insert into employees (employee_id,first_name,last_name,email,phone_number,hire_date,job_id,salary,commission_pct,manager_id,department_id) values (200,'Jennifer','Whalen','JWHALEN','515.123.4444',to_date('2003-09-17 00:00:00','YYYY-MM-DD HH24:MI:SS'),'AD_ASST',4400,null,101,10);
   insert into employees (employee_id,first_name,last_name,email,phone_number,hire_date,job_id,salary,commission_pct,manager_id,department_id) values (201,'Michael','Hartstein','MHARTSTE','515.123.5555',to_date('2004-02-17 00:00:00','YYYY-MM-DD HH24:MI:SS'),'MK_MAN',13000,null,100,20);
   insert into employees (employee_id,first_name,last_name,email,phone_number,hire_date,job_id,salary,commission_pct,manager_id,department_id) values (202,'Pat','Fay','PFAY','603.123.6666',to_date('2005-08-17 00:00:00','YYYY-MM-DD HH24:MI:SS'),'MK_REP',6000,null,201,20);
   insert into employees (employee_id,first_name,last_name,email,phone_number,hire_date,job_id,salary,commission_pct,manager_id,department_id) values (203,'Susan','Mavris','SMAVRIS','515.123.7777',to_date('2002-06-07 00:00:00','YYYY-MM-DD HH24:MI:SS'),'HR_REP',6500,null,101,40);
   insert into employees (employee_id,first_name,last_name,email,phone_number,hire_date,job_id,salary,commission_pct,manager_id,department_id) values (204,'Hermann','Baer','HBAER','515.123.8888',to_date('2002-06-07 00:00:00','YYYY-MM-DD HH24:MI:SS'),'PR_REP',10000,null,101,70);
   insert into employees (employee_id,first_name,last_name,email,phone_number,hire_date,job_id,salary,commission_pct,manager_id,department_id) values (205,'Shelley','Higgins','SHIGGINS','515.123.8080',to_date('2002-06-07 00:00:00','YYYY-MM-DD HH24:MI:SS'),'AC_MGR',12008,null,101,110);
   insert into employees (employee_id,first_name,last_name,email,phone_number,hire_date,job_id,salary,commission_pct,manager_id,department_id) values (206,'William','Gietz','WGIETZ','515.123.8181',to_date('2002-06-07 00:00:00','YYYY-MM-DD HH24:MI:SS'),'AC_ACCOUNT',8300,null,205,110);
   insert into employees (employee_id,first_name,last_name,email,phone_number,hire_date,job_id,salary,commission_pct,manager_id,department_id) values (100,'Steven','King','SKING','515.123.4567',to_date('2003-06-17 00:00:00','YYYY-MM-DD HH24:MI:SS'),'AD_PRES',24000,null,null,90);
   insert into employees (employee_id,first_name,last_name,email,phone_number,hire_date,job_id,salary,commission_pct,manager_id,department_id) values (101,'Neena','Kochhar','NKOCHHAR','515.123.4568',to_date('2005-09-21 00:00:00','YYYY-MM-DD HH24:MI:SS'),'AD_VP',17000,null,100,90);
   insert into employees (employee_id,first_name,last_name,email,phone_number,hire_date,job_id,salary,commission_pct,manager_id,department_id) values (102,'Lex','De Haan','LDEHAAN','515.123.4569',to_date('2001-01-13 00:00:00','YYYY-MM-DD HH24:MI:SS'),'AD_VP',17000,null,100,90);
   insert into employees (employee_id,first_name,last_name,email,phone_number,hire_date,job_id,salary,commission_pct,manager_id,department_id) values (103,'Alexander','Hunold','AHUNOLD','590.423.4567',to_date('2006-01-03 00:00:00','YYYY-MM-DD HH24:MI:SS'),'IT_PROG',9000,null,102,60);
   insert into employees (employee_id,first_name,last_name,email,phone_number,hire_date,job_id,salary,commission_pct,manager_id,department_id) values (104,'Bruce','Ernst','BERNST','590.423.4568',to_date('2007-05-21 00:00:00','YYYY-MM-DD HH24:MI:SS'),'IT_PROG',6000,null,103,60);
   insert into employees (employee_id,first_name,last_name,email,phone_number,hire_date,job_id,salary,commission_pct,manager_id,department_id) values (105,'David','Austin','DAUSTIN','590.423.4569',to_date('2005-06-25 00:00:00','YYYY-MM-DD HH24:MI:SS'),'IT_PROG',4800,null,103,60);
   insert into employees (employee_id,first_name,last_name,email,phone_number,hire_date,job_id,salary,commission_pct,manager_id,department_id) values (106,'Valli','Pataballa','VPATABAL','590.423.4560',to_date('2006-02-05 00:00:00','YYYY-MM-DD HH24:MI:SS'),'IT_PROG',4800,null,103,60);
   insert into employees (employee_id,first_name,last_name,email,phone_number,hire_date,job_id,salary,commission_pct,manager_id,department_id) values (107,'Diana','Lorentz','DLORENTZ','590.423.5567',to_date('2007-02-07 00:00:00','YYYY-MM-DD HH24:MI:SS'),'IT_PROG',4200,null,103,60);
   insert into employees (employee_id,first_name,last_name,email,phone_number,hire_date,job_id,salary,commission_pct,manager_id,department_id) values (108,'Nancy','Greenberg','NGREENBE','515.124.4569',to_date('2002-08-17 00:00:00','YYYY-MM-DD HH24:MI:SS'),'FI_MGR',12008,null,101,100);
   insert into employees (employee_id,first_name,last_name,email,phone_number,hire_date,job_id,salary,commission_pct,manager_id,department_id) values (109,'Daniel','Faviet','DFAVIET','515.124.4169',to_date('2002-08-16 00:00:00','YYYY-MM-DD HH24:MI:SS'),'FI_ACCOUNT',9000,null,108,100);
   insert into employees (employee_id,first_name,last_name,email,phone_number,hire_date,job_id,salary,commission_pct,manager_id,department_id) values (110,'John','Chen','JCHEN','515.124.4269',to_date('2005-09-28 00:00:00','YYYY-MM-DD HH24:MI:SS'),'FI_ACCOUNT',8200,null,108,100);
   insert into employees (employee_id,first_name,last_name,email,phone_number,hire_date,job_id,salary,commission_pct,manager_id,department_id) values (111,'Ismael','Sciarra','ISCIARRA','515.124.4369',to_date('2005-09-30 00:00:00','YYYY-MM-DD HH24:MI:SS'),'FI_ACCOUNT',7700,null,108,100);
   insert into employees (employee_id,first_name,last_name,email,phone_number,hire_date,job_id,salary,commission_pct,manager_id,department_id) values (112,'Jose Manuel','Urman','JMURMAN','515.124.4469',to_date('2006-03-07 00:00:00','YYYY-MM-DD HH24:MI:SS'),'FI_ACCOUNT',7800,null,108,100);
   insert into employees (employee_id,first_name,last_name,email,phone_number,hire_date,job_id,salary,commission_pct,manager_id,department_id) values (113,'Luis','Popp','LPOPP','515.124.4567',to_date('2007-12-07 00:00:00','YYYY-MM-DD HH24:MI:SS'),'FI_ACCOUNT',6900,null,108,100);
   insert into employees (employee_id,first_name,last_name,email,phone_number,hire_date,job_id,salary,commission_pct,manager_id,department_id) values (114,'Den','Raphaely','DRAPHEAL','515.127.4561',to_date('2002-12-07 00:00:00','YYYY-MM-DD HH24:MI:SS'),'PU_MAN',11000,null,100,30);
   insert into employees (employee_id,first_name,last_name,email,phone_number,hire_date,job_id,salary,commission_pct,manager_id,department_id) values (115,'Alexander','Khoo','AKHOO','515.127.4562',to_date('2003-05-18 00:00:00','YYYY-MM-DD HH24:MI:SS'),'PU_CLERK',3100,null,114,30);
   insert into employees (employee_id,first_name,last_name,email,phone_number,hire_date,job_id,salary,commission_pct,manager_id,department_id) values (116,'Shelli','Baida','SBAIDA','515.127.4563',to_date('2005-12-24 00:00:00','YYYY-MM-DD HH24:MI:SS'),'PU_CLERK',2900,null,114,30);
   insert into employees (employee_id,first_name,last_name,email,phone_number,hire_date,job_id,salary,commission_pct,manager_id,department_id) values (117,'Sigal','Tobias','STOBIAS','515.127.4564',to_date('2005-07-24 00:00:00','YYYY-MM-DD HH24:MI:SS'),'PU_CLERK',2800,null,114,30);
   insert into employees (employee_id,first_name,last_name,email,phone_number,hire_date,job_id,salary,commission_pct,manager_id,department_id) values (118,'Guy','Himuro','GHIMURO','515.127.4565',to_date('2006-11-15 00:00:00','YYYY-MM-DD HH24:MI:SS'),'PU_CLERK',2600,null,114,30);
   insert into employees (employee_id,first_name,last_name,email,phone_number,hire_date,job_id,salary,commission_pct,manager_id,department_id) values (119,'Karen','Colmenares','KCOLMENA','515.127.4566',to_date('2007-08-10 00:00:00','YYYY-MM-DD HH24:MI:SS'),'PU_CLERK',2500,null,114,30);
   insert into employees (employee_id,first_name,last_name,email,phone_number,hire_date,job_id,salary,commission_pct,manager_id,department_id) values (120,'Matthew','Weiss','MWEISS','650.123.1234',to_date('2004-07-18 00:00:00','YYYY-MM-DD HH24:MI:SS'),'ST_MAN',8000,null,100,50);
   insert into employees (employee_id,first_name,last_name,email,phone_number,hire_date,job_id,salary,commission_pct,manager_id,department_id) values (121,'Adam','Fripp','AFRIPP','650.123.2234',to_date('2005-04-10 00:00:00','YYYY-MM-DD HH24:MI:SS'),'ST_MAN',8200,null,100,50);
   insert into employees (employee_id,first_name,last_name,email,phone_number,hire_date,job_id,salary,commission_pct,manager_id,department_id) values (122,'Payam','Kaufling','PKAUFLIN','650.123.3234',to_date('2003-05-01 00:00:00','YYYY-MM-DD HH24:MI:SS'),'ST_MAN',7900,null,100,50);
   insert into employees (employee_id,first_name,last_name,email,phone_number,hire_date,job_id,salary,commission_pct,manager_id,department_id) values (123,'Shanta','Vollman','SVOLLMAN','650.123.4234',to_date('2005-10-10 00:00:00','YYYY-MM-DD HH24:MI:SS'),'ST_MAN',6500,null,100,50);
   insert into employees (employee_id,first_name,last_name,email,phone_number,hire_date,job_id,salary,commission_pct,manager_id,department_id) values (124,'Kevin','Mourgos','KMOURGOS','650.123.5234',to_date('2007-11-16 00:00:00','YYYY-MM-DD HH24:MI:SS'),'ST_MAN',5800,null,100,50);
   insert into employees (employee_id,first_name,last_name,email,phone_number,hire_date,job_id,salary,commission_pct,manager_id,department_id) values (125,'Julia','Nayer','JNAYER','650.124.1214',to_date('2005-07-16 00:00:00','YYYY-MM-DD HH24:MI:SS'),'ST_CLERK',3200,null,120,50);
   insert into employees (employee_id,first_name,last_name,email,phone_number,hire_date,job_id,salary,commission_pct,manager_id,department_id) values (126,'Irene','Mikkilineni','IMIKKILI','650.124.1224',to_date('2006-09-28 00:00:00','YYYY-MM-DD HH24:MI:SS'),'ST_CLERK',2700,null,120,50);
   insert into employees (employee_id,first_name,last_name,email,phone_number,hire_date,job_id,salary,commission_pct,manager_id,department_id) values (127,'James','Landry','JLANDRY','650.124.1334',to_date('2007-01-14 00:00:00','YYYY-MM-DD HH24:MI:SS'),'ST_CLERK',2400,null,120,50);
   insert into employees (employee_id,first_name,last_name,email,phone_number,hire_date,job_id,salary,commission_pct,manager_id,department_id) values (128,'Steven','Markle','SMARKLE','650.124.1434',to_date('2008-03-08 00:00:00','YYYY-MM-DD HH24:MI:SS'),'ST_CLERK',2200,null,120,50);
   insert into employees (employee_id,first_name,last_name,email,phone_number,hire_date,job_id,salary,commission_pct,manager_id,department_id) values (129,'Laura','Bissot','LBISSOT','650.124.5234',to_date('2005-08-20 00:00:00','YYYY-MM-DD HH24:MI:SS'),'ST_CLERK',3300,null,121,50);
   insert into employees (employee_id,first_name,last_name,email,phone_number,hire_date,job_id,salary,commission_pct,manager_id,department_id) values (130,'Mozhe','Atkinson','MATKINSO','650.124.6234',to_date('2005-10-30 00:00:00','YYYY-MM-DD HH24:MI:SS'),'ST_CLERK',2800,null,121,50);
   insert into employees (employee_id,first_name,last_name,email,phone_number,hire_date,job_id,salary,commission_pct,manager_id,department_id) values (131,'James','Marlow','JAMRLOW','650.124.7234',to_date('2005-02-16 00:00:00','YYYY-MM-DD HH24:MI:SS'),'ST_CLERK',2500,null,121,50);
   insert into employees (employee_id,first_name,last_name,email,phone_number,hire_date,job_id,salary,commission_pct,manager_id,department_id) values (132,'TJ','Olson','TJOLSON','650.124.8234',to_date('2007-04-10 00:00:00','YYYY-MM-DD HH24:MI:SS'),'ST_CLERK',2100,null,121,50);
   insert into employees (employee_id,first_name,last_name,email,phone_number,hire_date,job_id,salary,commission_pct,manager_id,department_id) values (133,'Jason','Mallin','JMALLIN','650.127.1934',to_date('2004-06-14 00:00:00','YYYY-MM-DD HH24:MI:SS'),'ST_CLERK',3300,null,122,50);
   insert into employees (employee_id,first_name,last_name,email,phone_number,hire_date,job_id,salary,commission_pct,manager_id,department_id) values (134,'Michael','Rogers','MROGERS','650.127.1834',to_date('2006-08-26 00:00:00','YYYY-MM-DD HH24:MI:SS'),'ST_CLERK',2900,null,122,50);
   insert into employees (employee_id,first_name,last_name,email,phone_number,hire_date,job_id,salary,commission_pct,manager_id,department_id) values (135,'Ki','Gee','KGEE','650.127.1734',to_date('2007-12-12 00:00:00','YYYY-MM-DD HH24:MI:SS'),'ST_CLERK',2400,null,122,50);
   insert into employees (employee_id,first_name,last_name,email,phone_number,hire_date,job_id,salary,commission_pct,manager_id,department_id) values (136,'Hazel','Philtanker','HPHILTAN','650.127.1634',to_date('2008-02-06 00:00:00','YYYY-MM-DD HH24:MI:SS'),'ST_CLERK',2200,null,122,50);
   insert into employees (employee_id,first_name,last_name,email,phone_number,hire_date,job_id,salary,commission_pct,manager_id,department_id) values (137,'Renske','Ladwig','RLADWIG','650.121.1234',to_date('2003-07-14 00:00:00','YYYY-MM-DD HH24:MI:SS'),'ST_CLERK',3600,null,123,50);
   insert into employees (employee_id,first_name,last_name,email,phone_number,hire_date,job_id,salary,commission_pct,manager_id,department_id) values (138,'Stephen','Stiles','SSTILES','650.121.2034',to_date('2005-10-26 00:00:00','YYYY-MM-DD HH24:MI:SS'),'ST_CLERK',3200,null,123,50);
   insert into employees (employee_id,first_name,last_name,email,phone_number,hire_date,job_id,salary,commission_pct,manager_id,department_id) values (139,'John','Seo','JSEO','650.121.2019',to_date('2006-02-12 00:00:00','YYYY-MM-DD HH24:MI:SS'),'ST_CLERK',2700,null,123,50);
   insert into employees (employee_id,first_name,last_name,email,phone_number,hire_date,job_id,salary,commission_pct,manager_id,department_id) values (140,'Joshua','Patel','JPATEL','650.121.1834',to_date('2006-04-06 00:00:00','YYYY-MM-DD HH24:MI:SS'),'ST_CLERK',2500,null,123,50);
   insert into employees (employee_id,first_name,last_name,email,phone_number,hire_date,job_id,salary,commission_pct,manager_id,department_id) values (141,'Trenna','Rajs','TRAJS','650.121.8009',to_date('2003-10-17 00:00:00','YYYY-MM-DD HH24:MI:SS'),'ST_CLERK',3500,null,124,50);
   insert into employees (employee_id,first_name,last_name,email,phone_number,hire_date,job_id,salary,commission_pct,manager_id,department_id) values (142,'Curtis','Davies','CDAVIES','650.121.2994',to_date('2005-01-29 00:00:00','YYYY-MM-DD HH24:MI:SS'),'ST_CLERK',3100,null,124,50);
   insert into employees (employee_id,first_name,last_name,email,phone_number,hire_date,job_id,salary,commission_pct,manager_id,department_id) values (143,'Randall','Matos','RMATOS','650.121.2874',to_date('2006-03-15 00:00:00','YYYY-MM-DD HH24:MI:SS'),'ST_CLERK',2600,null,124,50);
   insert into employees (employee_id,first_name,last_name,email,phone_number,hire_date,job_id,salary,commission_pct,manager_id,department_id) values (144,'Peter','Vargas','PVARGAS','650.121.2004',to_date('2006-07-09 00:00:00','YYYY-MM-DD HH24:MI:SS'),'ST_CLERK',2500,null,124,50);
   insert into employees (employee_id,first_name,last_name,email,phone_number,hire_date,job_id,salary,commission_pct,manager_id,department_id) values (145,'John','Russell','JRUSSEL','011.44.1344.429268',to_date('2004-10-01 00:00:00','YYYY-MM-DD HH24:MI:SS'),'SA_MAN',14000,0.4,100,80);
   insert into employees (employee_id,first_name,last_name,email,phone_number,hire_date,job_id,salary,commission_pct,manager_id,department_id) values (146,'Karen','Partners','KPARTNER','011.44.1344.467268',to_date('2005-01-05 00:00:00','YYYY-MM-DD HH24:MI:SS'),'SA_MAN',13500,0.3,100,80);
   insert into employees (employee_id,first_name,last_name,email,phone_number,hire_date,job_id,salary,commission_pct,manager_id,department_id) values (147,'Alberto','Errazuriz','AERRAZUR','011.44.1344.429278',to_date('2005-03-10 00:00:00','YYYY-MM-DD HH24:MI:SS'),'SA_MAN',12000,0.3,100,80);
   insert into employees (employee_id,first_name,last_name,email,phone_number,hire_date,job_id,salary,commission_pct,manager_id,department_id) values (148,'Gerald','Cambrault','GCAMBRAU','011.44.1344.619268',to_date('2007-10-15 00:00:00','YYYY-MM-DD HH24:MI:SS'),'SA_MAN',11000,0.3,100,80);
   insert into employees (employee_id,first_name,last_name,email,phone_number,hire_date,job_id,salary,commission_pct,manager_id,department_id) values (149,'Eleni','Zlotkey','EZLOTKEY','011.44.1344.429018',to_date('2008-01-29 00:00:00','YYYY-MM-DD HH24:MI:SS'),'SA_MAN',10500,0.2,100,80);
   insert into employees (employee_id,first_name,last_name,email,phone_number,hire_date,job_id,salary,commission_pct,manager_id,department_id) values (150,'Peter','Tucker','PTUCKER','011.44.1344.129268',to_date('2005-01-30 00:00:00','YYYY-MM-DD HH24:MI:SS'),'SA_REP',10000,0.3,145,80);
   insert into employees (employee_id,first_name,last_name,email,phone_number,hire_date,job_id,salary,commission_pct,manager_id,department_id) values (151,'David','Bernstein','DBERNSTE','011.44.1344.345268',to_date('2005-03-24 00:00:00','YYYY-MM-DD HH24:MI:SS'),'SA_REP',9500,0.25,145,80);
   insert into employees (employee_id,first_name,last_name,email,phone_number,hire_date,job_id,salary,commission_pct,manager_id,department_id) values (152,'Peter','Hall','PHALL','011.44.1344.478968',to_date('2005-08-20 00:00:00','YYYY-MM-DD HH24:MI:SS'),'SA_REP',9000,0.25,145,80);
   insert into employees (employee_id,first_name,last_name,email,phone_number,hire_date,job_id,salary,commission_pct,manager_id,department_id) values (153,'Christopher','Olsen','COLSEN','011.44.1344.498718',to_date('2006-03-30 00:00:00','YYYY-MM-DD HH24:MI:SS'),'SA_REP',8000,0.2,145,80);
   insert into employees (employee_id,first_name,last_name,email,phone_number,hire_date,job_id,salary,commission_pct,manager_id,department_id) values (154,'Nanette','Cambrault','NCAMBRAU','011.44.1344.987668',to_date('2006-12-09 00:00:00','YYYY-MM-DD HH24:MI:SS'),'SA_REP',7500,0.2,145,80);
   insert into employees (employee_id,first_name,last_name,email,phone_number,hire_date,job_id,salary,commission_pct,manager_id,department_id) values (155,'Oliver','Tuvault','OTUVAULT','011.44.1344.486508',to_date('2007-11-23 00:00:00','YYYY-MM-DD HH24:MI:SS'),'SA_REP',7000,0.15,145,80);
   insert into employees (employee_id,first_name,last_name,email,phone_number,hire_date,job_id,salary,commission_pct,manager_id,department_id) values (156,'Janette','King','JKING','011.44.1345.429268',to_date('2004-01-30 00:00:00','YYYY-MM-DD HH24:MI:SS'),'SA_REP',10000,0.35,146,80);
   insert into employees (employee_id,first_name,last_name,email,phone_number,hire_date,job_id,salary,commission_pct,manager_id,department_id) values (157,'Patrick','Sully','PSULLY','011.44.1345.929268',to_date('2004-03-04 00:00:00','YYYY-MM-DD HH24:MI:SS'),'SA_REP',9500,0.35,146,80);
   insert into employees (employee_id,first_name,last_name,email,phone_number,hire_date,job_id,salary,commission_pct,manager_id,department_id) values (158,'Allan','McEwen','AMCEWEN','011.44.1345.829268',to_date('2004-08-01 00:00:00','YYYY-MM-DD HH24:MI:SS'),'SA_REP',9000,0.35,146,80);
   insert into employees (employee_id,first_name,last_name,email,phone_number,hire_date,job_id,salary,commission_pct,manager_id,department_id) values (159,'Lindsey','Smith','LSMITH','011.44.1345.729268',to_date('2005-03-10 00:00:00','YYYY-MM-DD HH24:MI:SS'),'SA_REP',8000,0.3,146,80);
   insert into employees (employee_id,first_name,last_name,email,phone_number,hire_date,job_id,salary,commission_pct,manager_id,department_id) values (160,'Louise','Doran','LDORAN','011.44.1345.629268',to_date('2005-12-15 00:00:00','YYYY-MM-DD HH24:MI:SS'),'SA_REP',7500,0.3,146,80);
   insert into employees (employee_id,first_name,last_name,email,phone_number,hire_date,job_id,salary,commission_pct,manager_id,department_id) values (161,'Sarath','Sewall','SSEWALL','011.44.1345.529268',to_date('2006-11-03 00:00:00','YYYY-MM-DD HH24:MI:SS'),'SA_REP',7000,0.25,146,80);
   insert into employees (employee_id,first_name,last_name,email,phone_number,hire_date,job_id,salary,commission_pct,manager_id,department_id) values (162,'Clara','Vishney','CVISHNEY','011.44.1346.129268',to_date('2005-11-11 00:00:00','YYYY-MM-DD HH24:MI:SS'),'SA_REP',10500,0.25,147,80);
   insert into employees (employee_id,first_name,last_name,email,phone_number,hire_date,job_id,salary,commission_pct,manager_id,department_id) values (163,'Danielle','Greene','DGREENE','011.44.1346.229268',to_date('2007-03-19 00:00:00','YYYY-MM-DD HH24:MI:SS'),'SA_REP',9500,0.15,147,80);
   insert into employees (employee_id,first_name,last_name,email,phone_number,hire_date,job_id,salary,commission_pct,manager_id,department_id) values (164,'Mattea','Marvins','MMARVINS','011.44.1346.329268',to_date('2008-01-24 00:00:00','YYYY-MM-DD HH24:MI:SS'),'SA_REP',7200,0.1,147,80);
   insert into employees (employee_id,first_name,last_name,email,phone_number,hire_date,job_id,salary,commission_pct,manager_id,department_id) values (165,'David','Lee','DLEE','011.44.1346.529268',to_date('2008-02-23 00:00:00','YYYY-MM-DD HH24:MI:SS'),'SA_REP',6800,0.1,147,80);
   insert into employees (employee_id,first_name,last_name,email,phone_number,hire_date,job_id,salary,commission_pct,manager_id,department_id) values (166,'Sundar','Ande','SANDE','011.44.1346.629268',to_date('2008-03-24 00:00:00','YYYY-MM-DD HH24:MI:SS'),'SA_REP',6400,0.1,147,80);
   insert into employees (employee_id,first_name,last_name,email,phone_number,hire_date,job_id,salary,commission_pct,manager_id,department_id) values (167,'Amit','Banda','ABANDA','011.44.1346.729268',to_date('2008-04-21 00:00:00','YYYY-MM-DD HH24:MI:SS'),'SA_REP',6200,0.1,147,80);
   insert into employees (employee_id,first_name,last_name,email,phone_number,hire_date,job_id,salary,commission_pct,manager_id,department_id) values (168,'Lisa','Ozer','LOZER','011.44.1343.929268',to_date('2005-03-11 00:00:00','YYYY-MM-DD HH24:MI:SS'),'SA_REP',11500,0.25,148,80);
   insert into employees (employee_id,first_name,last_name,email,phone_number,hire_date,job_id,salary,commission_pct,manager_id,department_id) values (169,'Harrison','Bloom','HBLOOM','011.44.1343.829268',to_date('2006-03-23 00:00:00','YYYY-MM-DD HH24:MI:SS'),'SA_REP',10000,0.2,148,80);
   insert into employees (employee_id,first_name,last_name,email,phone_number,hire_date,job_id,salary,commission_pct,manager_id,department_id) values (170,'Tayler','Fox','TFOX','011.44.1343.729268',to_date('2006-01-24 00:00:00','YYYY-MM-DD HH24:MI:SS'),'SA_REP',9600,0.2,148,80);
   insert into employees (employee_id,first_name,last_name,email,phone_number,hire_date,job_id,salary,commission_pct,manager_id,department_id) values (171,'William','Smith','WSMITH','011.44.1343.629268',to_date('2007-02-23 00:00:00','YYYY-MM-DD HH24:MI:SS'),'SA_REP',7400,0.15,148,80);
   insert into employees (employee_id,first_name,last_name,email,phone_number,hire_date,job_id,salary,commission_pct,manager_id,department_id) values (172,'Elizabeth','Bates','EBATES','011.44.1343.529268',to_date('2007-03-24 00:00:00','YYYY-MM-DD HH24:MI:SS'),'SA_REP',7300,0.15,148,80);
   insert into employees (employee_id,first_name,last_name,email,phone_number,hire_date,job_id,salary,commission_pct,manager_id,department_id) values (173,'Sundita','Kumar','SKUMAR','011.44.1343.329268',to_date('2008-04-21 00:00:00','YYYY-MM-DD HH24:MI:SS'),'SA_REP',6100,0.1,148,80);
   insert into employees (employee_id,first_name,last_name,email,phone_number,hire_date,job_id,salary,commission_pct,manager_id,department_id) values (174,'Ellen','Abel','EABEL','011.44.1644.429267',to_date('2004-05-11 00:00:00','YYYY-MM-DD HH24:MI:SS'),'SA_REP',11000,0.3,149,80);
   insert into employees (employee_id,first_name,last_name,email,phone_number,hire_date,job_id,salary,commission_pct,manager_id,department_id) values (175,'Alyssa','Hutton','AHUTTON','011.44.1644.429266',to_date('2005-03-19 00:00:00','YYYY-MM-DD HH24:MI:SS'),'SA_REP',8800,0.25,149,80);
   insert into employees (employee_id,first_name,last_name,email,phone_number,hire_date,job_id,salary,commission_pct,manager_id,department_id) values (176,'Jonathon','Taylor','JTAYLOR','011.44.1644.429265',to_date('2006-03-24 00:00:00','YYYY-MM-DD HH24:MI:SS'),'SA_REP',8600,0.2,149,80);
   insert into employees (employee_id,first_name,last_name,email,phone_number,hire_date,job_id,salary,commission_pct,manager_id,department_id) values (177,'Jack','Livingston','JLIVINGS','011.44.1644.429264',to_date('2006-04-23 00:00:00','YYYY-MM-DD HH24:MI:SS'),'SA_REP',8400,0.2,149,80);
   insert into employees (employee_id,first_name,last_name,email,phone_number,hire_date,job_id,salary,commission_pct,manager_id,department_id) values (178,'Kimberely','Grant','KGRANT','011.44.1644.429263',to_date('2007-05-24 00:00:00','YYYY-MM-DD HH24:MI:SS'),'SA_REP',7000,0.15,149,null);
   insert into employees (employee_id,first_name,last_name,email,phone_number,hire_date,job_id,salary,commission_pct,manager_id,department_id) values (179,'Charles','Johnson','CJOHNSON','011.44.1644.429262',to_date('2008-01-04 00:00:00','YYYY-MM-DD HH24:MI:SS'),'SA_REP',6200,0.1,149,80);
   insert into employees (employee_id,first_name,last_name,email,phone_number,hire_date,job_id,salary,commission_pct,manager_id,department_id) values (180,'Winston','Taylor','WTAYLOR','650.507.9876',to_date('2006-01-24 00:00:00','YYYY-MM-DD HH24:MI:SS'),'SH_CLERK',3200,null,120,50);
   insert into employees (employee_id,first_name,last_name,email,phone_number,hire_date,job_id,salary,commission_pct,manager_id,department_id) values (181,'Jean','Fleaur','JFLEAUR','650.507.9877',to_date('2006-02-23 00:00:00','YYYY-MM-DD HH24:MI:SS'),'SH_CLERK',3100,null,120,50);
   insert into employees (employee_id,first_name,last_name,email,phone_number,hire_date,job_id,salary,commission_pct,manager_id,department_id) values (182,'Martha','Sullivan','MSULLIVA','650.507.9878',to_date('2007-06-21 00:00:00','YYYY-MM-DD HH24:MI:SS'),'SH_CLERK',2500,null,120,50);
   insert into employees (employee_id,first_name,last_name,email,phone_number,hire_date,job_id,salary,commission_pct,manager_id,department_id) values (183,'Girard','Geoni','GGEONI','650.507.9879',to_date('2008-02-03 00:00:00','YYYY-MM-DD HH24:MI:SS'),'SH_CLERK',2800,null,120,50);
   insert into employees (employee_id,first_name,last_name,email,phone_number,hire_date,job_id,salary,commission_pct,manager_id,department_id) values (184,'Nandita','Sarchand','NSARCHAN','650.509.1876',to_date('2004-01-27 00:00:00','YYYY-MM-DD HH24:MI:SS'),'SH_CLERK',4200,null,121,50);
   insert into employees (employee_id,first_name,last_name,email,phone_number,hire_date,job_id,salary,commission_pct,manager_id,department_id) values (185,'Alexis','Bull','ABULL','650.509.2876',to_date('2005-02-20 00:00:00','YYYY-MM-DD HH24:MI:SS'),'SH_CLERK',4100,null,121,50);
   insert into employees (employee_id,first_name,last_name,email,phone_number,hire_date,job_id,salary,commission_pct,manager_id,department_id) values (186,'Julia','Dellinger','JDELLING','650.509.3876',to_date('2006-06-24 00:00:00','YYYY-MM-DD HH24:MI:SS'),'SH_CLERK',3400,null,121,50);
   insert into employees (employee_id,first_name,last_name,email,phone_number,hire_date,job_id,salary,commission_pct,manager_id,department_id) values (187,'Anthony','Cabrio','ACABRIO','650.509.4876',to_date('2007-02-07 00:00:00','YYYY-MM-DD HH24:MI:SS'),'SH_CLERK',3000,null,121,50);
   insert into employees (employee_id,first_name,last_name,email,phone_number,hire_date,job_id,salary,commission_pct,manager_id,department_id) values (188,'Kelly','Chung','KCHUNG','650.505.1876',to_date('2005-06-14 00:00:00','YYYY-MM-DD HH24:MI:SS'),'SH_CLERK',3800,null,122,50);
   insert into employees (employee_id,first_name,last_name,email,phone_number,hire_date,job_id,salary,commission_pct,manager_id,department_id) values (189,'Jennifer','Dilly','JDILLY','650.505.2876',to_date('2005-08-13 00:00:00','YYYY-MM-DD HH24:MI:SS'),'SH_CLERK',3600,null,122,50);
   insert into employees (employee_id,first_name,last_name,email,phone_number,hire_date,job_id,salary,commission_pct,manager_id,department_id) values (190,'Timothy','Gates','TGATES','650.505.3876',to_date('2006-07-11 00:00:00','YYYY-MM-DD HH24:MI:SS'),'SH_CLERK',2900,null,122,50);
   insert into employees (employee_id,first_name,last_name,email,phone_number,hire_date,job_id,salary,commission_pct,manager_id,department_id) values (191,'Randall','Perkins','RPERKINS','650.505.4876',to_date('2007-12-19 00:00:00','YYYY-MM-DD HH24:MI:SS'),'SH_CLERK',2500,null,122,50);
   insert into employees (employee_id,first_name,last_name,email,phone_number,hire_date,job_id,salary,commission_pct,manager_id,department_id) values (192,'Sarah','Bell','SBELL','650.501.1876',to_date('2004-02-04 00:00:00','YYYY-MM-DD HH24:MI:SS'),'SH_CLERK',4000,null,123,50);
   insert into employees (employee_id,first_name,last_name,email,phone_number,hire_date,job_id,salary,commission_pct,manager_id,department_id) values (193,'Britney','Everett','BEVERETT','650.501.2876',to_date('2005-03-03 00:00:00','YYYY-MM-DD HH24:MI:SS'),'SH_CLERK',3900,null,123,50);
   insert into employees (employee_id,first_name,last_name,email,phone_number,hire_date,job_id,salary,commission_pct,manager_id,department_id) values (194,'Samuel','McCain','SMCCAIN','650.501.3876',to_date('2006-07-01 00:00:00','YYYY-MM-DD HH24:MI:SS'),'SH_CLERK',3200,null,123,50);
   insert into employees (employee_id,first_name,last_name,email,phone_number,hire_date,job_id,salary,commission_pct,manager_id,department_id) values (195,'Vance','Jones','VJONES','650.501.4876',to_date('2007-03-17 00:00:00','YYYY-MM-DD HH24:MI:SS'),'SH_CLERK',2800,null,123,50);
   
   insert into job_history (employee_id,start_date,end_date,job_id,department_id) values (102,to_date('2001-01-13 00:00:00','YYYY-MM-DD HH24:MI:SS'),to_date('2006-07-24 00:00:00','YYYY-MM-DD HH24:MI:SS'),'IT_PROG',60);
   insert into job_history (employee_id,start_date,end_date,job_id,department_id) values (101,to_date('1997-09-21 00:00:00','YYYY-MM-DD HH24:MI:SS'),to_date('2001-10-27 00:00:00','YYYY-MM-DD HH24:MI:SS'),'AC_ACCOUNT',110);
   insert into job_history (employee_id,start_date,end_date,job_id,department_id) values (101,to_date('2001-10-28 00:00:00','YYYY-MM-DD HH24:MI:SS'),to_date('2005-03-15 00:00:00','YYYY-MM-DD HH24:MI:SS'),'AC_MGR',110);
   insert into job_history (employee_id,start_date,end_date,job_id,department_id) values (201,to_date('2004-02-17 00:00:00','YYYY-MM-DD HH24:MI:SS'),to_date('2007-12-19 00:00:00','YYYY-MM-DD HH24:MI:SS'),'MK_REP',20);
   insert into job_history (employee_id,start_date,end_date,job_id,department_id) values (114,to_date('2006-03-24 00:00:00','YYYY-MM-DD HH24:MI:SS'),to_date('2007-12-31 00:00:00','YYYY-MM-DD HH24:MI:SS'),'ST_CLERK',50);
   insert into job_history (employee_id,start_date,end_date,job_id,department_id) values (122,to_date('2007-01-01 00:00:00','YYYY-MM-DD HH24:MI:SS'),to_date('2007-12-31 00:00:00','YYYY-MM-DD HH24:MI:SS'),'ST_CLERK',50);
   insert into job_history (employee_id,start_date,end_date,job_id,department_id) values (200,to_date('1995-09-17 00:00:00','YYYY-MM-DD HH24:MI:SS'),to_date('2001-06-17 00:00:00','YYYY-MM-DD HH24:MI:SS'),'AD_ASST',90);
   insert into job_history (employee_id,start_date,end_date,job_id,department_id) values (176,to_date('2006-03-24 00:00:00','YYYY-MM-DD HH24:MI:SS'),to_date('2006-12-31 00:00:00','YYYY-MM-DD HH24:MI:SS'),'SA_REP',80);
   insert into job_history (employee_id,start_date,end_date,job_id,department_id) values (176,to_date('2007-01-01 00:00:00','YYYY-MM-DD HH24:MI:SS'),to_date('2007-12-31 00:00:00','YYYY-MM-DD HH24:MI:SS'),'SA_MAN',80);
   insert into job_history (employee_id,start_date,end_date,job_id,department_id) values (200,to_date('2002-07-01 00:00:00','YYYY-MM-DD HH24:MI:SS'),to_date('2006-12-31 00:00:00','YYYY-MM-DD HH24:MI:SS'),'AC_ACCOUNT',90);
end;
/
commit;

------------------------------------------------------------------------------------------------------------------------------------
prompt
prompt create indexes
------------------------------------------------------------------------------------------------------------------------------------
create index dept_location_ix on departments (location_id);
create index emp_department_ix on employees (department_id);
create index emp_job_ix on employees (job_id);
create index emp_manager_ix on employees (manager_id);
create index emp_name_ix on employees (last_name, first_name);
create index jhist_job_ix on job_history (job_id);
create index jhist_employee_ix on job_history (employee_id);
create index jhist_department_ix on job_history (department_id);
create index loc_city_ix on locations (city);
create index loc_state_province_ix on locations (state_province);
create index loc_country_ix on locations (country_id);

------------------------------------------------------------------------------------------------------------------------------------
prompt
prompt create foreign key constraints
------------------------------------------------------------------------------------------------------------------------------------
alter table countries add ( constraint countr_reg_fk foreign key (region_id) references regions(region_id));
alter table departments add ( 
   constraint dept_mgr_fk foreign key (manager_id) references employees (employee_id),
   constraint dept_loc_fk foreign key (location_id) references locations (location_id) );
alter table employees add ( 
   constraint emp_dept_fk foreign key (department_id) references departments (department_id),
   constraint emp_job_fk foreign key (job_id) references jobs (job_id),
   constraint emp_manager_fk foreign key (manager_id) references employees (employee_id) );
alter table job_history add (
   constraint jhist_job_fk foreign key (job_id) references jobs,
   constraint jhist_emp_fk foreign key (employee_id) references employees,
   constraint jhist_dept_fk foreign key (department_id) references departments);
alter table locations add ( constraint loc_c_id_fk foreign key (country_id) references countries(country_id) );

------------------------------------------------------------------------------------------------------------------------------------
rem prompt create package specifications
------------------------------------------------------------------------------------------------------------------------------------

------------------------------------------------------------------------------------------------------------------------------------
prompt
prompt create standalone procedures and functions
------------------------------------------------------------------------------------------------------------------------------------
create or replace procedure secure_dml
is
begin
   if to_char (sysdate, 'HH24:MI') not between '08:00' and '18:00' or to_char (sysdate, 'DY') in ('SAT', 'SUN') 
   then
      raise_application_error (-20205, 'You may only make changes during normal office hours');
  end if;
end secure_dml /*(scripted by teamoneill.org)*/;
/
prompt SECURE_DML

create or replace procedure add_job_history (
   p_emp_id          job_history.employee_id%type,
   p_start_date      job_history.start_date%type,
   p_end_date        job_history.end_date%type,
   p_job_id          job_history.job_id%type,
   p_department_id   job_history.department_id%type )
is
begin
   insert into job_history (employee_id, start_date, end_date, job_id, department_id)
   values(p_emp_id, p_start_date, p_end_date, p_job_id, p_department_id);
end add_job_history /*(scripted by teamoneill.org)*/;
/
prompt ADD_JOB_HISTORY

------------------------------------------------------------------------------------------------------------------------------------
rem prompt create package bodies
------------------------------------------------------------------------------------------------------------------------------------

------------------------------------------------------------------------------------------------------------------------------------
prompt
prompt create table triggers
------------------------------------------------------------------------------------------------------------------------------------
create or replace trigger secure_employees
   -- (scripted by teamoneill.org)
   before insert or update or delete 
   on employees
begin
   secure_dml;
end secure_employees /*(scripted by teamoneill.org)*/;
/
alter trigger secure_employees disable;
prompt SECURE_EMPLOYEES

create or replace trigger update_job_history
   after update of job_id, department_id 
   on employees
   for each row
begin
  add_job_history(:old.employee_id, :old.hire_date, sysdate, :old.job_id, :old.department_id);
end update_job_history  /*(scripted by teamoneill.org)*/;
/
prompt UPDATE_JOB_HISTORY

--------------------------------------------------------------------------------------------------------------------------------------
prompt
prompt gather statistics
--------------------------------------------------------------------------------------------------------------------------------------
begin
   dbms_stats.gather_schema_stats( 'HR', granularity => 'ALL', cascade => TRUE, block_sample => TRUE );
exception
   when others then 
      null; /* ignore failure */
end;
/

--------------------------------------------------------------------------------------------------------------------------------------
prompt
prompt script complete
--------------------------------------------------------------------------------------------------------------------------------------
