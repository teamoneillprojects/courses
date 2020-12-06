rem
rem SCRIPT breakdown-modifying-data.sql
rem
rem COURSE Oracle Database Primer
rem        https://teamoneill.org/course/oracle-database-primer
rem
rem LESSON Modifying Data
rem        https://teamoneill.org/lesson/modifying-data
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
prompt    Script: breakdown-modifying-data.sql
prompt    Course: Oracle Database Primer
prompt    Lesson: Modifying Data
------------------------------------------------------------------------------------------------------------------------------------

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

--------------------------------------------------------------------------------------------------------------------------------------
prompt
prompt script complete
--------------------------------------------------------------------------------------------------------------------------------------
