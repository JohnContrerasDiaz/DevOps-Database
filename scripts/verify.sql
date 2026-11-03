WHENEVER OSERROR EXIT FAILURE
WHENEVER SQLERROR EXIT FAILURE
SET ECHO OFF
SET VERIFY OFF
SET SERVEROUTPUT ON

DECLARE
    column_count PLS_INTEGER;
    history_count PLS_INTEGER;
BEGIN
    IF USER <> 'DEVOPS_DEMO'
       OR SYS_CONTEXT('USERENV', 'CURRENT_SCHEMA') <> 'DEVOPS_DEMO' THEN
        RAISE_APPLICATION_ERROR(-20001, 'Expected DEVOPS_DEMO session and schema');
    END IF;

    SELECT COUNT(*)
      INTO column_count
      FROM USER_TAB_COLUMNS
     WHERE TABLE_NAME = 'DEVOPS_CHANGE_DEMO'
       AND COLUMN_NAME IN ('ID', 'DESCRIPTION', 'CREATED_AT');

    IF column_count <> 3 THEN
        RAISE_APPLICATION_ERROR(-20002, 'Demo table verification failed');
    END IF;

    SELECT COUNT(*)
      INTO history_count
      FROM DATABASECHANGELOG
     WHERE ID = '001-create-devops-demo'
       AND AUTHOR = 'database-devops'
       AND EXECTYPE = 'EXECUTED';

    IF history_count <> 1 THEN
        RAISE_APPLICATION_ERROR(-20003, 'Migration history verification failed');
    END IF;

    DBMS_OUTPUT.PUT_LINE('MIGRATION_001_VERIFIED');
END;
/
