SET LIN 999
SET MARKUP CSV ON DELIMITER |

prompt ##Main info


select  a.host_name "Host name",
        b.name "DB name",
        a.instance_name "Instance name",
        a.version "Version",
        a.edition "Edition",
        b.cdb "CDB",
        a.status "Status",
        b.open_mode "Open mode",
        a.logins "Logins",
        b.log_mode "Archive mode",
        b.force_logging "Force logging",
        b.flashback_on "Flashback activate",
        to_char(a.startup_time,'yyyy-mm-dd') "Startup",
        b.platform_name "Platform",
        a.instance_role "Instance role",
        c.CPUS,
        c.CORES,
        c.SOCKETS,
        c.VCPUS,
        c.LCPUS,
        c.RAM_GB
  from  gv$instance a,
        gv$database b,(select b.inst_id,
			sum(case when b.stat_name = 'NUM_CPUS' then value end) "CPUS",
			sum(case when b.stat_name = 'NUM_CPU_CORES' then value end) "CORES",
			sum(case when b.stat_name = 'NUM_CPU_SOCKETS' then value end) "SOCKETS",
			sum(case when b.stat_name = 'NUM_VCPUS' then value end) "VCPUS",
			sum(case when b.stat_name = 'NUM_LCPUS' then value end) "LCPUS",
			round(sum(case when b.stat_name = 'PHYSICAL_MEMORY_BYTES'then value end)/1024/1024/1024) "RAM_GB"
	from gv$osstat b
	where B.STAT_NAME in ('NUM_CPUS','NUM_CPU_CORES','NUM_CPU_SOCKETS','PHYSICAL_MEMORY_BYTES','NUM_VCPUS','NUM_LCPUS') group by b.inst_id) c
  where a.inst_id = b.inst_id
  and a.inst_id = c.inst_id
  order by a.inst_id;

prompt ##
prompt Alert History

SELECT instance_name,to_char((creation_time),'YYYY-MM-DD hh24:mi:ss') as "CREATION_TIME",reason,message_type,resolution, message_level FROM dba_alert_history_detail WHERE resolution NOT LIKE 'cleared';



prompt ##SGA info

select  b.instance_name "Instance name",
        a.name "Pool name",
        round(a.bytes/1024/1024) "Pool size MB"
from  gv$sgainfo a,
      gv$instance b
where a.inst_id = b.inst_id
and a.name in ('Buffer Cache Size','Shared Pool Size','Large Pool Size','Java Pool Size','Redo Buffers')
order by a.inst_id,a.name;

prompt ##
prompt Online Redo Logs 

SELECT lf.GROUP#,
       l.thread# "Thread",
       lf.group# "Group number",
       lf.member "Member",
       TRUNC(l.bytes/1024/1024) "Size in MiB",
       l.status "Status",
       l.archived "Archived",
       lf.type "Type",
       lf.is_recovery_dest_file "RDF",
       l.sequence# "Sequence"
FROM   v$logfile lf
       JOIN v$log l ON l.group# = lf.group#
ORDER BY l.thread#,lf.group#, lf.member;



/*
prompt ##Registry info, Update RDBMS info

select  comp_name,
        version,
        status,
        modified "DATE"
  from dba_registry;

select  to_char(action_time,'yyyy-mm-dd') "DATE",
        action,
        namespace,
        version,id,
        comments 
  from  sys.registry$history
  order by action_time;

select  to_char(action_time,'yyyy-mm-dd') "DATE",
        patch_id,
        version,
        action,
        status,
        description 
  from  sys.REGISTRY$SQLPATCH 
  order by action_time;
*/
exit;
