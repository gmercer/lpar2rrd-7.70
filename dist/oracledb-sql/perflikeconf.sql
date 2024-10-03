SET LIN 999
SET MARKUP CSV ON DELIMITER |


prompt ##
prompt Wait class Main

select  b.instance_name "Instance name",
        a.wait_class "Wait class",
        a.time_waited, 
        a.total_waits,
        a.time_waited_fg,
        a.total_waits_fg
from gv$system_wait_class a,
     gv$instance b 
where  a.inst_id = b.inst_id
      and a.wait_class in ('Scheduler','Application','Administrative','Concurrency','User I/O','System I/O','Configuration','Commit','Network','Other')
order by a.inst_id,a.wait_class;




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

prompt db file scattered read

select 
        b.instance_name "Instance name",
        a.event "Event",
        a.time_waited_micro,
        a.total_waits
      from
        gv$system_event a,
        gv$instance b
      where
        a.inst_id = b.inst_id
      and
        a.event = 'db file scattered read'
      order by 1; 

prompt ##

prompt db file sequential read

select 
        b.instance_name "Instance name",
        a.event "Event",
        a.time_waited_micro,
        a.total_waits
      from
        gv$system_event a,
        gv$instance b
      where
        a.inst_id = b.inst_id
      and
        a.event = 'db file sequential read'
      order by 1; 

prompt ##

prompt db file single write

select 
        b.instance_name "Instance name",
        a.event "Event",
        a.time_waited_micro,
        a.total_waits
      from
        gv$system_event a,
        gv$instance b
      where
        a.inst_id = b.inst_id
      and
        a.event = 'db file single write'
      order by 1;


prompt ##

prompt db file parallel write

select 
        b.instance_name "Instance name",
        a.event "Event",
        a.time_waited_micro,
        a.total_waits
      from
        gv$system_event a,
        gv$instance b
      where
        a.inst_id = b.inst_id
      and
        a.event = 'db file parallel write'
      order by 1;



prompt ##

prompt log file sync

select 
        b.instance_name "Instance name",
        a.event "Event",
        a.time_waited_micro,
        a.total_waits
      from
        gv$system_event a,
        gv$instance b
      where
        a.inst_id = b.inst_id
      and
        a.event = 'log file sync'
      order by 1;


prompt ##

prompt log file single write

select 
        b.instance_name "Instance name",
        a.event "Event",
        a.time_waited_micro,
        a.total_waits
      from
        gv$system_event a,
        gv$instance b
      where
        a.inst_id = b.inst_id
      and
        a.event = 'log file single write'
      order by 1;



prompt ##

prompt log file parallel write

select 
        b.instance_name "Instance name",
        a.event "Event",
        a.time_waited_micro,
        a.total_waits
      from
        gv$system_event a,
        gv$instance b
      where
        a.inst_id = b.inst_id
      and
        a.event = 'log file parallel write'
      order by 1;


prompt ##

prompt flashback log file sync

select 
        b.instance_name "Instance name",
        a.event "Event",
        a.time_waited_micro,
        a.total_waits
      from
        gv$system_event a,
        gv$instance b
      where
        a.inst_id = b.inst_id
      and
        a.event = 'flashback log file sync'
      order by 1;

exit;
