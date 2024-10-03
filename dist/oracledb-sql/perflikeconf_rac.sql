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



prompt ##

prompt gc cr block 3-way

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
        a.event = 'gc cr block 3-way'
      order by 1;

prompt ##

prompt gc cr block 2-way

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
        a.event = 'gc cr block 2-way'
      order by 1;

prompt ##

prompt gc current block congested

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
        a.event = 'gc current block congested'
      order by 1;

prompt ##

prompt gc current block busy

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
        a.event = 'gc current block busy'
      order by 1;

prompt ##

prompt gc cr grant congested

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
        a.event = 'gc cr grant congested'
      order by 1;

prompt ##

prompt gc cr grant 2-way

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
        a.event = 'gc cr grant 2-way'
      order by 1;

prompt ##

prompt gc cr block congested

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
        a.event = 'gc cr block congested'
      order by 1;

prompt ##

prompt gc cr block busy

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
        a.event = 'gc cr block busy'
      order by 1;

prompt ##

prompt gc current block 3-way

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
        a.event = 'gc current block 3-way'
      order by 1;

prompt ##

prompt gc current split

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
        a.event = 'gc current split'
      order by 1;

prompt ##

prompt gc current retry

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
        a.event = ''
      order by 1;

prompt ##

prompt gc cr failure

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
        a.event = 'gc cr failure'
      order by 1;

prompt ##

prompt gc current block lost

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
        a.event = 'gc current block lost'
      order by 1;

prompt ##

prompt gc cr block lost

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
        a.event = 'gc cr block lost'
      order by 1;

prompt ##

prompt gc current grant congested

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
        a.event = 'gc current grant congested'
      order by 1;

prompt ##

prompt gc current grant 2-way

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
        a.event = 'gc current grant 2-way'
      order by 1;

prompt ##

prompt gc buffer busy release

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
        a.event = 'gc buffer busy release'
      order by 1;

prompt ##

prompt gc buffer busy acquire

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
        a.event = 'gc buffer busy acquire'
      order by 1;


prompt ##

prompt gc cr multi block request

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
        a.event = 'gc cr multi block request'
      order by 1;

prompt ##

prompt gc cr disk read

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
        a.event = 'gc cr disk read'
      order by 1;

prompt ##

prompt gc current grant busy

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
        a.event = 'gc current grant busy'
      order by 1;

prompt ##

prompt gc current multi block request

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
        a.event = 'gc current multi block request'
      order by 1;

prompt ##

prompt gc remaster

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
        a.event = 'gc remaster'
      order by 1;

prompt ##

prompt gc current blocks received

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
        a.event = 'gc current blocks received'
      order by 1;

prompt ##

prompt gc current block receive time

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
        a.event = 'gc current block receive time'
      order by 1;

prompt ##

prompt gc cr blocks received

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
        a.event = 'gc cr blocks received'
      order by 1;

prompt ##

prompt gc cr block receive time

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
        a.event = 'gc cr block receive time'
      order by 1;

prompt ##

prompt DB files read latency

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
        a.event in ('db file sequential read','db file scattered read')
      order by 1;

prompt ##

prompt LOG files write latency

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
        a.event in ('log file sync','log file single write','log file parallel write')
      order by 1;

prompt ##

prompt DB files write latency

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
        a.event in ('db file single write','db file parallel write')
      order by 1;

exit;
