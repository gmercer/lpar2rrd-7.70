SET LIN 999
SET MARKUP CSV ON DELIMITER |

prompt ##
prompt Interconnect info

select	b.host_name "Host name",
	b.instance_name "Instance_name",
	b.status "Status",	
	a.name "Bond name",
	a.ip_address "IPaddress",
	a.is_public "Is public"
from	gv$cluster_interconnects a, 
	gv$instance b
where a.inst_id = b.inst_id
order by a.inst_id;

prompt ##
prompt Main info

select  a.host_name "Host",
        a.host_name "Host name",
        b.dbid "DBID",
        b.db_unique_name "Unique name",
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
prompt SGA info

select  b.instance_name "Instance name",
        a.name "Pool name",
        round(a.bytes/1024/1024) "Pool size MB"
from  gv$sgainfo a,
      gv$instance b
where a.inst_id = b.inst_id
and a.name in ('Buffer Cache Size','Shared Pool Size','Large Pool Size','Java Pool Size','Redo Buffers')
order by a.inst_id,a.name;

prompt ##
prompt Tablespace info

select
  tablespace_name "TBS name",
  sum(velikost_MB-free_space_MB) "TBS allocate size MB",
  sum(velikost_MB) "TBS size MB",
  sum(Max_MB) "TBS max size MB"
    from
(select
             b.file_name,
             b.file_id,
             b.tablespace_name,
             round(NVL2(a.bytes,a.bytes,'0')/1024/1024) as Free_space_MB,
             round(b.bytes/1024/1024) Velikost_MB,
             round(b.maxbytes/1024/1024) Max_MB,
             b.autoextensible
           from
             ( select
                 file_id,
                 sum(bytes) bytes
               from
                 dba_free_space
               group by
                 file_id ) a
                   right join
                     dba_data_files b
                   ON
                     a.file_id = b.file_id
                   where
                     b.autoextensible= 'YES'
      union all
select
             b.file_name,
             b.file_id,
             b.tablespace_name,
             round(NVL2(a.bytes,a.bytes,'0')/1024/1024) as Free_space_MB,
             round(b.bytes/1024/1024) Velikost_MB,
             round(b.bytes/1024/1024) Max_MB,
             b.autoextensible
           from
             ( select
                 file_id,
                 sum(bytes) bytes
               from
                 dba_free_space
               group by
                 file_id ) a
                   right join
                     dba_data_files b
                   ON
                     a.file_id = b.file_id
                   where
                     b.autoextensible= 'NO'
union all
select
             b.file_name,
             b.file_id,
             b.tablespace_name,
             round(NVL2(a.bytes,a.bytes,'0')/1024/1024) as Free_space_MB,
             round(b.bytes/1024/1024) Velikost_MB,
             round(b.maxbytes/1024/1024) Max_MB,
             b.autoextensible
           from
             ( select
                 tablespace_name,
                  sum(free_space) bytes 
                 from
                 dba_temp_free_space
               group by
                 tablespace_name ) a
                   right join
                     dba_temp_files b
                   ON
                     a.tablespace_name = b.tablespace_name
                   where
                     b.autoextensible= 'YES'
union all
select
             b.file_name,
             b.file_id,
             b.tablespace_name,
             round(NVL2(a.bytes,a.bytes,'0')/1024/1024) as Free_space_MB,
             round(b.bytes/1024/1024) Velikost_MB,
             round(b.bytes/1024/1024) Max_MB,
             b.autoextensible
           from
             ( select
                 tablespace_name,
                 sum(free_space) bytes 
                from
                 dba_temp_free_space
               group by
                 tablespace_name ) a
                   right join
                     dba_temp_files b
                   ON
                     a.tablespace_name = b.tablespace_name
                   where
                     b.autoextensible= 'NO')
    group by tablespace_name
    order by 1;



prompt ##
prompt IO Read Write per datafile

select  DF.NAME,
     FS.PHYRDS "Physical Reads",
     FS.PHYWRTS "Physical Writes",
       (case
              when (FS.PHYRDS+FS.PHYWRTS) = 0 then 0
              else round((FS.PHYRDS/(FS.PHYRDS+FS.PHYWRTS))*100)
       end) "Read/Write %",
       (case
              when (FS.PHYRDS+FS.PHYWRTS) = 0 then 0
              else round((FS.PHYWRTS/(FS.PHYRDS+FS.PHYWRTS))*100)
        end) "Write/Read %",
        (case
              when FS.PHYRDS = 0 then 0
              else round((FS.READTIM/FS.PHYRDS)*10,2) 
        end) "Avg read wait ms",
        (case
              when FS.PHYWRTS = 0 then 0
              else round((FS.WRITETIM/FS.PHYWRTS)*10,2) 
        end) "Avg write wait ms"
from (
     select
		     sum(PHYRDS) PHYS_READS,
         sum(PHYWRTS) PHYS_WRTS
     from      v$filestat
     ) pd,
     v$datafile df,
     v$filestat fs
where     DF.FILE# = FS.FILE#
order     by FS.PHYBLKRD+FS.PHYBLKWRT desc;

prompt ##
prompt Wait class Main

select  b.instance_name "Instance name",
  a.wait_class "Wait class",
        (case 
    when a.time_waited = 0 then 0 
    else round((a.time_waited*10)/a.total_waits,2) 
  end)  "Average wait ms",
        (case 
    when a.time_waited_fg = 0 then 0 
    else round((a.time_waited_fg*10)/a.total_waits_fg,2) 
  end) as "Average wait FG ms"
from gv$system_wait_class a,
     gv$instance b 
where  a.inst_id = b.inst_id
      and a.wait_class in ('Idle','Scheduler','Application','Administrative','Concurrency','User I/O','System I/O','Configuration','Commit','Network','Other')
order by a.inst_id,a.wait_class;


prompt ##
prompt Installed DB components

select  comp_name,
        version,
        status,
        modified "DATE"
  from dba_registry;

prompt ##
prompt Upgrade, Downgrade info

select  to_char(action_time,'yyyy-mm-dd') "DATE",
        action,
        namespace,
        version,id,
        comments 
  from  sys.registry$history
  order by action_time;

prompt ##
prompt PSU, patches info

select  to_char(action_time,'yyyy-mm-dd') "DATE",
        patch_id,
        version,
        action,
        status,
        description 
  from  sys.registry$sqlpatch 
  order by action_time;

prompt ##
prompt Data rate per service name

select  b.instance_name,
        a.service_name,
        a.stat_name,
        a.value "DB blocks"
  from  gv$service_stats a, gv$instance b
where   a.inst_id = b.inst_id
  and   a.stat_name like 'physical%'
  and   a.service_name not like 'SYS%' 
  and   a.service_name not like '%UNKNOW%'
order by 
        a.stat_name,
        b.instance_name;


prompt ##
prompt gc cr block 2-way

select  b.instance_name "Instance name",
        a.event "Event name",
        a.wait_time_milli "Wait time ms",
        wait_count "Count"
from    gv$event_histogram a, gv$instance b
where   a.inst_id = b.inst_id
and     a.event = 'gc cr block 2-way'
order by 1,3;


prompt ##
prompt gc cr block 3-way

select  b.instance_name "Instance name",
        a.event "Event name",
        a.wait_time_milli "Wait time ms",
        wait_count "Count"
from    gv$event_histogram a, gv$instance b
where   a.inst_id = b.inst_id
and     a.event = 'gc cr block 3-way'
order by 1,3;


prompt ##
prompt gc current block 2-way

select  b.instance_name "Instance name",
        a.event "Event name",
        a.wait_time_milli "Wait time ms",
        wait_count "Count"
from    gv$event_histogram a, gv$instance b
where   a.inst_id = b.inst_id
and     a.event =  'gc current block 2-way'
order by 1,3;


prompt ##
prompt gc current block 3-way

select  b.instance_name "Instance name",
        a.event "Event name",
        a.wait_time_milli "Wait time ms",
        wait_count "Count"
from    gv$event_histogram a, gv$instance b
where   a.inst_id = b.inst_id
and     a.event =  'gc current block 3-way'
order by 1,3;


prompt ##
prompt gc cr block busy

select  b.instance_name "Instance name",
        a.event "Event name",
        a.wait_time_milli "Wait time ms",
        wait_count "Count"
from    gv$event_histogram a, gv$instance b
where   a.inst_id = b.inst_id
and     a.event = 'gc cr block busy'
order by 1,3;


prompt ##
prompt gc cr block congested

select  b.instance_name "Instance name",
        a.event "Event name",
        a.wait_time_milli "Wait time ms",
        wait_count "Count"
from    gv$event_histogram a, gv$instance b
where   a.inst_id = b.inst_id
and     a.event = 'gc cr block congested'
order by 1,3;


prompt ##
prompt gc cr grant 2-way

select  b.instance_name "Instance name",
        a.event "Event name",
        a.wait_time_milli "Wait time ms",
        wait_count "Count"
from    gv$event_histogram a, gv$instance b
where   a.inst_id = b.inst_id
and     a.event = 'gc cr grant 2-way'
order by 1,3;


prompt ##
prompt gc cr grant congested

select  b.instance_name "Instance name",
        a.event "Event name",
        a.wait_time_milli "Wait time ms",
        wait_count "Count"
from    gv$event_histogram a, gv$instance b
where   a.inst_id = b.inst_id
and     a.event =  'gc cr grant congested'
order by 1,3;


prompt ##
prompt gc current block busy

select  b.instance_name "Instance name",
        a.event "Event name",
        a.wait_time_milli "Wait time ms",
        wait_count "Count"
from    gv$event_histogram a, gv$instance b
where   a.inst_id = b.inst_id
and     a.event =  'gc current block busy'
order by 1,3;


prompt ##
prompt gc current block congested

select  b.instance_name "Instance name",
        a.event "Event name",
        a.wait_time_milli "Wait time ms",
        wait_count "Count"
from    gv$event_histogram a, gv$instance b
where   a.inst_id = b.inst_id
and     a.event = 'gc current block congested'
order by 1,3;


prompt ##
prompt gc current grant 2-way

select  b.instance_name "Instance name",
        a.event "Event name",
        a.wait_time_milli "Wait time ms",
        wait_count "Count"
from    gv$event_histogram a, gv$instance b
where   a.inst_id = b.inst_id
and     a.event =  'gc current grant 2-way'
order by 1,3;


prompt ##
prompt gc current grant congested

select  b.instance_name "Instance name",
        a.event "Event name",
        a.wait_time_milli "Wait time ms",
        wait_count "Count"
from    gv$event_histogram a, gv$instance b
where   a.inst_id = b.inst_id
and     a.event =  'gc current grant congested'
order by 1,3;


prompt ##
prompt gc cr block lost

select  b.instance_name "Instance name",
        a.event "Event name",
        a.wait_time_milli "Wait time ms",
        wait_count "Count"
from    gv$event_histogram a, gv$instance b
where   a.inst_id = b.inst_id
and     a.event = 'gc cr block lost'
order by 1,3;


prompt ##
prompt gc current block lost

select  b.instance_name "Instance name",
        a.event "Event name",
        a.wait_time_milli "Wait time ms",
        wait_count "Count"
from    gv$event_histogram a, gv$instance b
where   a.inst_id = b.inst_id
and     a.event =  'gc current block lost'
      order by 2;


prompt ##
prompt gc cr failure

select  b.instance_name "Instance name",
        a.event "Event name",
        a.wait_time_milli "Wait time ms",
        wait_count "Count"
from    gv$event_histogram a, gv$instance b
where   a.inst_id = b.inst_id
and     a.event =  'gc cr failure'
order by 1,3;


prompt ##
prompt gc current retry

select  b.instance_name "Instance name",
        a.event "Event name",
        a.wait_time_milli "Wait time ms",
        wait_count "Count"
from    gv$event_histogram a, gv$instance b
where   a.inst_id = b.inst_id
and     a.event = 'gc current retry'
order by 1,3;


prompt ##
prompt gc current split

select  b.instance_name "Instance name",
        a.event "Event name",
        a.wait_time_milli "Wait time ms",
        wait_count "Count"
from    gv$event_histogram a, gv$instance b
where   a.inst_id = b.inst_id
and     a.event =  'gc current split'
order by 1,3;


prompt ##
prompt gc current multi block request

select  b.instance_name "Instance name",
        a.event "Event name",
        a.wait_time_milli "Wait time ms",
        wait_count "Count"
from    gv$event_histogram a, gv$instance b
where   a.inst_id = b.inst_id
and     a.event =  'gc current multi block request'
order by 1,3;


prompt ##
prompt gc current grant busy

select  b.instance_name "Instance name",
        a.event "Event name",
        a.wait_time_milli "Wait time ms",
        wait_count "Count"
from    gv$event_histogram a, gv$instance b
where   a.inst_id = b.inst_id
and     a.event =  'gc current grant busy'
order by 1,3;


prompt ##
prompt gc cr disk read

select  b.instance_name "Instance name",
        a.event "Event name",
        a.wait_time_milli "Wait time ms",
        wait_count "Count"
from    gv$event_histogram a, gv$instance b
where   a.inst_id = b.inst_id
and     a.event =  'gc cr disk read'
order by 1,3;


prompt ##
prompt gc cr multi block request

select  b.instance_name "Instance name",
        a.event "Event name",
        a.wait_time_milli "Wait time ms",
        wait_count "Count"
from    gv$event_histogram a, gv$instance b
where   a.inst_id = b.inst_id
and     a.event =  'gc cr multi block request'
order by 1,3;


prompt ##
prompt gc buffer busy acquire

select  b.instance_name "Instance name",
        a.event "Event name",
        a.wait_time_milli "Wait time ms",
        wait_count "Count"
from    gv$event_histogram a, gv$instance b
where   a.inst_id = b.inst_id
and     a.event = 'gc buffer busy acquire'
order by 1,3;


prompt ##
prompt gc buffer busy release

select  b.instance_name "Instance name",
        a.event "Event name",
        a.wait_time_milli "Wait time ms",
        wait_count "Count"
from    gv$event_histogram a, gv$instance b
where   a.inst_id = b.inst_id
and     a.event = 'gc buffer busy release'
order by 1,3;


prompt ##
prompt gc remaster

select  b.instance_name "Instance name",
        a.event "Event name",
        a.wait_time_milli "Wait time ms",
        wait_count "Count"
from    gv$event_histogram a, gv$instance b
where   a.inst_id = b.inst_id
and     a.event =  'gc remaster'
order by 1,3;

prompt ##
prompt Alert History

SELECT instance_name,to_char((creation_time),'YYYY-MM-DD hh24:mi:ss') as "CREATION_TIME",reason,message_type,resolution, message_level FROM dba_alert_history_detail WHERE resolution NOT LIKE 'cleared';

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

exit;
