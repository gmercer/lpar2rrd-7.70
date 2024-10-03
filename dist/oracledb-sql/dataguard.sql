SET LIN 999
SET MARKUP CSV ON DELIMITER |


prompt ##
prompt Identify Primary/Standby
select dest_role,db_unique_name,current_scn from v$dataguard_config;

prompt ##
prompt Check service

select db_unique_name,decode(status,'VALID','OK','ERROR') as STBY_DEST from V$ARCHIVE_DEST where target = 'STANDBY';

prompt ##
prompt Identify service

select db_unique_name,type,database_mode,status,recovery_mode,protection_mode,destination,archived_seq#,applied_seq# from v$archive_dest_status where type = 'PHYSICAL';

prompt ##
prompt Transport delay

select  b.db_unique_name,
        a.archived_seq# as "PRIMARY_seq",
        b.archived_seq# as "DG_trans_seq",
        b.applied_seq# as "DG_app_seq",
        decode((sign(a.archived_seq# - b.archived_seq#)),1,'Error',0,'OK','OK') as "Transport_seq__diff",
        decode((sign(a.archived_seq# - (b.applied_seq#+1))),1,'Error',0,'OK','OK') as "Applied_seq_diff"
    from v$archive_dest_status a,v$archive_dest_status b
    where a.type = 'LOCAL' and a.database_mode = 'OPEN'
    and b.type = 'PHYSICAL';

exit;
