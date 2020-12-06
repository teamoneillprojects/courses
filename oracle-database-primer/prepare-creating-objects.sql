rem
rem SCRIPT prepare-creating-objects.sql
rem
rem COURSE Oracle Database Primer
rem        https://teamoneill.org/course/oracle-database-primer
rem
rem LESSON Creating Objects
rem        https://teamoneill.org/lesson/creating-objects
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
prompt    Script: prepare-creating-objects.sql
prompt    Course: Oracle Database Primer
prompt    Lesson: Creating Objects
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

--------------------------------------------------------------------------------------------------------------------------------------
prompt
prompt script complete
--------------------------------------------------------------------------------------------------------------------------------------

