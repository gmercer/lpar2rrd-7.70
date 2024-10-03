SET HEADING OFF
SET LIN 999

SELECT to_char(max(end_time),'yyyy-mm-dd hh24:mi')||';'||metric_name||';'||metric_unit||';'||round(avg(value))||';;;' "Result"
  FROM v$sysmetric_history
  WHERE metric_name = 'Host CPU Utilization (%)' AND ROWNUM <= 5
  GROUP BY metric_name,metric_unit;

SELECT to_char(max(end_time),'yyyy-mm-dd hh24:mi')||';'||metric_name||';'||metric_unit||';'||round(avg(value))||';;;' "Result"
  FROM v$sysmetric_history
  WHERE metric_name = 'CPU Usage Per Sec' AND ROWNUM <= 5
  GROUP BY metric_name,metric_unit;

SELECT to_char(max(end_time),'yyyy-mm-dd hh24:mi')||';'||metric_name||';'||metric_unit||';'||round(avg(value))||';;;' "Result"
  FROM v$sysmetric_history
  WHERE metric_name = 'CPU Usage Per Txn' AND ROWNUM <= 5
  GROUP BY metric_name,metric_unit;
prompt ;;;CPU info|



SELECT to_char(max(end_time),'yyyy-mm-dd hh24:mi')||';'||metric_name||';'||metric_unit||';'||round(avg(value))||';;;' "Result"
  FROM v$sysmetric_history
  WHERE metric_name = 'I/O Requests per Second' AND ROWNUM <= 5
  GROUP BY metric_name,metric_unit;

SELECT to_char(max(end_time),'yyyy-mm-dd hh24:mi')||';'||metric_name||';'||metric_unit||';'||round(avg(value))||';;;' "Result"
  FROM v$sysmetric_history
  WHERE metric_name = 'I/O Megabytes per Second' AND ROWNUM <= 5
  GROUP BY metric_name,metric_unit;

SELECT to_char(max(end_time),'yyyy-mm-dd hh24:mi')||';'||metric_name||';'||metric_unit||';'||round(avg(value))||';;;' "Result"
  FROM v$sysmetric_history
  WHERE metric_name = 'Redo Generated Per Sec' AND ROWNUM <= 5
  GROUP BY metric_name,metric_unit;

SELECT to_char(max(end_time),'yyyy-mm-dd hh24:mi')||';'||metric_name||';'||metric_unit||';'||round(avg(value))||';;;' "Result"
  FROM v$sysmetric_history
  WHERE metric_name = 'DB Block Changes Per Sec' AND ROWNUM <= 5
  GROUP BY metric_name,metric_unit;

SELECT to_char(max(end_time),'yyyy-mm-dd hh24:mi')||';'||metric_name||';'||metric_unit||';'||round(avg(value))||';;;' "Result"
  FROM v$sysmetric_history
  WHERE metric_name = 'Logical Reads Per Sec' AND ROWNUM <= 5
  GROUP BY metric_name,metric_unit;

SELECT to_char(max(end_time),'yyyy-mm-dd hh24:mi')||';'||metric_name||';'||metric_unit||';'||round(avg(value))||';;;' "Result"
  FROM v$sysmetric_history
  WHERE metric_name = 'Physical Reads Per Sec' AND ROWNUM <= 5
  GROUP BY metric_name,metric_unit;

SELECT to_char(max(end_time),'yyyy-mm-dd hh24:mi')||';'||metric_name||';'||metric_unit||';'||round(avg(value))||';;;' "Result"
  FROM v$sysmetric_history
  WHERE metric_name = 'Physical Writes Per Sec' AND ROWNUM <= 5
  GROUP BY metric_name,metric_unit;

SELECT to_char(max(end_time),'yyyy-mm-dd hh24:mi')||';'||metric_name||';'||metric_unit||';'||round(avg(value))||';;;' "Result"
  FROM v$sysmetric_history
  WHERE metric_name = 'Physical Read Bytes Per Sec' AND ROWNUM <= 5
  GROUP BY metric_name,metric_unit;

SELECT to_char(max(end_time),'yyyy-mm-dd hh24:mi')||';'||metric_name||';'||metric_unit||';'||round(avg(value))||';;;' "Result"
  FROM v$sysmetric_history
  WHERE metric_name = 'Physical Write Bytes Per Sec' AND ROWNUM <= 5
  GROUP BY metric_name,metric_unit;
prompt ;;;Data rate|


SELECT to_char(max(end_time),'yyyy-mm-dd hh24:mi')||';'||metric_name||';'||metric_unit||';'||round(avg(value))||';;;' "Result"
  FROM v$sysmetric_history
  WHERE metric_name = 'Current Logons Count' AND ROWNUM <= 5
  GROUP BY metric_name,metric_unit;

SELECT to_char(max(end_time),'yyyy-mm-dd hh24:mi')||';'||metric_name||';'||metric_unit||';'||round(avg(value))||';;;' "Result"
  FROM v$sysmetric_history
  WHERE metric_name = 'Average Active Sessions' AND ROWNUM <= 5
  GROUP BY metric_name,metric_unit;

SELECT to_char(max(end_time),'yyyy-mm-dd hh24:mi')||';'||metric_name||';'||metric_unit||';'||round(avg(value))||';;;' "Result"
  FROM v$sysmetric_history
  WHERE metric_name = 'Active Serial Sessions' AND ROWNUM <= 5
  GROUP BY metric_name,metric_unit;

SELECT to_char(max(end_time),'yyyy-mm-dd hh24:mi')||';'||metric_name||';'||metric_unit||';'||round(avg(value))||';;;' "Result"
  FROM v$sysmetric_history
  WHERE metric_name = 'Active Parallel Sessions' AND ROWNUM <= 5
  GROUP BY metric_name,metric_unit;

SELECT to_char(max(end_time),'yyyy-mm-dd hh24:mi')||';'||metric_name||';'||metric_unit||';'||round(avg(value))||';;;' "Result"
  FROM v$sysmetric_history
  WHERE metric_name = 'Logons Per Sec' AND ROWNUM <= 5
  GROUP BY metric_name,metric_unit;
prompt ;;;Session info|


SELECT to_char(max(end_time),'yyyy-mm-dd hh24:mi')||';'||metric_name||';'||metric_unit||';'||round(avg(value/1024/1024))||';;;' "Result"
  FROM v$sysmetric_history
  WHERE metric_name = 'Cell Physical IO Interconnect Bytes' and INTSIZE_CSEC > 2400 AND ROWNUM <= 5
  GROUP BY metric_name,metric_unit;

SELECT to_char(max(end_time),'yyyy-mm-dd hh24:mi')||';'||metric_name||';'||metric_unit||';'||round(avg((value*10)),1)||';;;' "Result"
  FROM v$sysmetric_history
  WHERE metric_name = 'Global Cache Average Current Get Time' AND ROWNUM <= 5
  GROUP BY metric_name,metric_unit;

SELECT to_char(max(end_time),'yyyy-mm-dd hh24:mi')||';'||metric_name||';'||metric_unit||';'||round(avg((value*10)),1)||';;;' "Result"
  FROM v$sysmetric_history
  WHERE metric_name = 'Global Cache Average CR Get Time' AND ROWNUM <= 5
  GROUP BY metric_name,metric_unit;

SELECT to_char(max(end_time),'yyyy-mm-dd hh24:mi')||';'||metric_name||';'||metric_unit||';'||round(avg(value))||';;;' "Result"
  FROM v$sysmetric_history
  WHERE metric_name = 'GC Current Block Received Per Second' AND ROWNUM <= 5
  GROUP BY metric_name,metric_unit;
  
SELECT to_char(max(end_time),'yyyy-mm-dd hh24:mi')||';'||metric_name||';'||metric_unit||';'||round(avg(value))||';;;' "Result"
  FROM v$sysmetric_history
  WHERE metric_name = 'GC CR Block Received Per Second'  AND ROWNUM <= 5
  GROUP BY metric_name,metric_unit;
  
SELECT to_char(max(end_time),'yyyy-mm-dd hh24:mi')||';'||metric_name||';'||metric_unit||';'||round(avg(value))||';;;' "Result"
  FROM v$sysmetric_history
  WHERE metric_name = 'Global Cache Blocks Corrupted'  AND ROWNUM <= 5
  GROUP BY metric_name,metric_unit;

SELECT to_char(max(end_time),'yyyy-mm-dd hh24:mi')||';'||metric_name||';'||metric_unit||';'||round(avg(value))||';;;' "Result"
  FROM v$sysmetric_history
  WHERE metric_name = 'Global Cache Blocks Lost'  AND ROWNUM <= 5
  GROUP BY metric_name,metric_unit;
prompt ;;;Cache|

SELECT to_char(max(end_time),'yyyy-mm-dd hh24:mi')||';'||"current_500B"||';'||current_500B||';'||round(avg(value/1e3))||';;;' "Result"
  FROM sys.V_$INSTANCE_PING
  WHERE current_500B != 0 AND ROWNUM <= 5
  GROUP BY metric_name,metric_unit;

SELECT to_char(max(end_time),'yyyy-mm-dd hh24:mi')||';'||"current_8K"||';'||current_8K||';'||round(avg(value/1e3))||';;;' "Result"
  FROM sys.V_$INSTANCE_PING
  WHERE current_500B != 0 AND ROWNUM <= 5
  GROUP BY metric_name,metric_unit;
prompt ;;;Ping|


SELECT total_waits||';'||event||';'||time_waited_micro||';'||round(time_waited_micro/total_waits)/1e3||';;;' "AVG (ms)"
  FROM  v$system_event
  WHERE event = 'gc cr block 2-way';

SELECT total_waits||';'||event||';'||time_waited_micro||';'||round(time_waited_micro/total_waits)/1e3||';;;' "AVG (ms)"
  FROM  v$system_event
  WHERE event = 'gc cr block 3-way';

SELECT total_waits||';'||event||';'||time_waited_micro||';'||round(time_waited_micro/total_waits)/1e3||';;;' "AVG (ms)"
  FROM  v$system_event
  WHERE event = 'gc current block 2-way';

SELECT total_waits||';'||event||';'||time_waited_micro||';'||round(time_waited_micro/total_waits)/1e3||';;;' "AVG (ms)"
  FROM  v$system_event
  WHERE event = 'gc current block 3-way';

SELECT total_waits||';'||event||';'||time_waited_micro||';'||round(time_waited_micro/total_waits)/1e3||';;;' "AVG (ms)"
  FROM  v$system_event
  WHERE event = 'gc cr block busy';

SELECT total_waits||';'||event||';'||time_waited_micro||';'||round(time_waited_micro/total_waits)/1e3||';;;' "AVG (ms)"
  FROM  v$system_event
  WHERE event = 'gc cr block congested';

SELECT total_waits||';'||event||';'||time_waited_micro||';'||round(time_waited_micro/total_waits)/1e3||';;;' "AVG (ms)"
  FROM  v$system_event
  WHERE event = 'gc cr grant 2-way';

SELECT total_waits||';'||event||';'||time_waited_micro||';'||round(time_waited_micro/total_waits)/1e3||';;;' "AVG (ms)"
  FROM  v$system_event
  WHERE event = 'gc cr grant congested';

SELECT total_waits||';'||event||';'||time_waited_micro||';'||round(time_waited_micro/total_waits)/1e3||';;;' "AVG (ms)"
  FROM  v$system_event
  WHERE event = 'gc current block busy';

SELECT total_waits||';'||event||';'||time_waited_micro||';'||round(time_waited_micro/total_waits)/1e3||';;;' "AVG (ms)"
  FROM  v$system_event
  WHERE event = 'gc current block congested';

SELECT total_waits||';'||event||';'||time_waited_micro||';'||round(time_waited_micro/total_waits)/1e3||';;;' "AVG (ms)"
  FROM  v$system_event
  WHERE event = 'gc current grant 2-way';

SELECT total_waits||';'||event||';'||time_waited_micro||';'||round(time_waited_micro/total_waits)/1e3||';;;' "AVG (ms)"
  FROM  v$system_event
  WHERE event = 'gc current grant congested';

SELECT total_waits||';'||event||';'||time_waited_micro||';'||round(time_waited_micro/total_waits)/1e3||';;;' "AVG (ms)"
  FROM  v$system_event
  WHERE event = 'gc cr block lost';

SELECT total_waits||';'||event||';'||time_waited_micro||';'||round(time_waited_micro/total_waits)/1e3||';;;' "AVG (ms)"
  FROM  v$system_event
  WHERE event = 'gc current block lost';

SELECT total_waits||';'||event||';'||time_waited_micro||';'||round(time_waited_micro/total_waits)/1e3||';;;' "AVG (ms)"
  FROM  v$system_event
  WHERE event = 'gc cr failure';

SELECT total_waits||';'||event||';'||time_waited_micro||';'||round(time_waited_micro/total_waits)/1e3||';;;' "AVG (ms)"
  FROM  v$system_event
  WHERE event = 'gc current retry';

SELECT total_waits||';'||event||';'||time_waited_micro||';'||round(time_waited_micro/total_waits)/1e3||';;;' "AVG (ms)"
  FROM  v$system_event
  WHERE event = 'gc current split';

SELECT total_waits||';'||event||';'||time_waited_micro||';'||round(time_waited_micro/total_waits)/1e3||';;;' "AVG (ms)"
  FROM  v$system_event
  WHERE event = 'gc current multi block request';

SELECT total_waits||';'||event||';'||time_waited_micro||';'||round(time_waited_micro/total_waits)/1e3||';;;' "AVG (ms)"
  FROM  v$system_event
  WHERE event = 'gc current grant busy';

SELECT total_waits||';'||event||';'||time_waited_micro||';'||round(time_waited_micro/total_waits)/1e3||';;;' "AVG (ms)"
  FROM  v$system_event
  WHERE event = 'gc cr disk read';

SELECT total_waits||';'||event||';'||time_waited_micro||';'||round(time_waited_micro/total_waits)/1e3||';;;' "AVG (ms)"
  FROM  v$system_event
  WHERE event = 'gc cr multi block request';

SELECT total_waits||';'||event||';'||time_waited_micro||';'||round(time_waited_micro/total_waits)/1e3||';;;' "AVG (ms)"
  FROM  v$system_event
  WHERE event = 'gc buffer busy acquire';

SELECT total_waits||';'||event||';'||time_waited_micro||';'||round(time_waited_micro/total_waits)/1e3||';;;' "AVG (ms)"
  FROM  v$system_event
  WHERE event = 'gc buffer busy release';


SELECT total_waits||';'||'DB files read latency'||';'||time_waited_micro||';'||round(time_waited_micro/total_waits)/1e3||';;;' "AVG (ms)"
  FROM  v$system_event
  WHERE event in ('db file sequential read','db file scattered read');

SELECT total_waits||';'||'DB files write latency'||';'||time_waited_micro||';'||round(time_waited_micro/total_waits)/1e3||';;;' "AVG (ms)"
  FROM  v$system_event
  WHERE event in ('db file single write','db file parallel write');

SELECT total_waits||';'||'LOG files write latency'||';'||time_waited_micro||';'||round(time_waited_micro/total_waits)/1e3||';;;' "AVG (ms)"
  FROM  v$system_event
  WHERE event in ('log file sync','log file single write','log file parallel write');

SELECT name||';'||'gc cr block receive time'||';'||name||';'||value||';;;' "ms"
  FROM  v$sysstat
  WHERE name =  'gc cr block receive time';

SELECT name||';'||'gc cr blocks received'||';'||name||';'||value||';;;' "ms"
  FROM  v$sysstat
  WHERE name =  'gc cr blocks received';

SELECT name||';'||'gc current block receive time'||';'||name||';'||value||';;;' "ms"
  FROM  v$sysstat
  WHERE name =  'gc current block receive time';

SELECT name||';'||'gc current blocks received'||';'||name||';'||value||';;;' "ms"
  FROM  v$sysstat
  WHERE name =  'gc current blocks received';

SELECT total_waits||';'||event||';'||time_waited_micro||';'||round(time_waited_micro/total_waits)/1e3||';;;' "AVG (ms)"
  FROM  v$system_event
  WHERE event = 'gc remaster';

prompt ;;;RAC|



SELECT total_waits||';'||event||';'||time_waited_micro||';'||round(time_waited_micro/total_waits)/1e3||';;;' "AVG (ms)"
  FROM  v$system_event
  WHERE event = 'db file scattered read';

SELECT total_waits||';'||event||';'||time_waited_micro||';'||round(time_waited_micro/total_waits)/1e3||';;;' "AVG (ms)"
  FROM  v$system_event
  WHERE event = 'db file sequential read';

SELECT total_waits||';'||event||';'||time_waited_micro||';'||round(time_waited_micro/total_waits)/1e3||';;;' "AVG (ms)"
  FROM  v$system_event
  WHERE event = 'db file single write';

SELECT total_waits||';'||event||';'||time_waited_micro||';'||round(time_waited_micro/total_waits)/1e3||';;;' "AVG (ms)"
  FROM  v$system_event
  WHERE event = 'db file parallel write';

SELECT total_waits||';'||event||';'||time_waited_micro||';'||round(time_waited_micro/total_waits)/1e3||';;;' "AVG (ms)"
  FROM  v$system_event
  WHERE event = 'log file sync';

SELECT total_waits||';'||event||';'||time_waited_micro||';'||round(time_waited_micro/total_waits)/1e3||';;;' "AVG (ms)"
  FROM  v$system_event
  WHERE event = 'log file single write';

SELECT total_waits||';'||event||';'||time_waited_micro||';'||round(time_waited_micro/total_waits)/1e3||';;;' "AVG (ms)"
  FROM  v$system_event
  WHERE event = 'log file parallel write';

SELECT total_waits||';'||event||';'||time_waited_micro||';'||round(time_waited_micro/total_waits)/1e3||';;;' "AVG (ms)"
  FROM  v$system_event
  WHERE event = 'flashback log file sync';
prompt ;;;Disk latency|


SELECT 'filler'||';'||'used'||';'||'filler'||';'||sum(bytes)/1073741824||';;;' "AVG (ms)"
  FROM  dba_data_files;

SELECT 'filler'||';'||'free'||';'||'filler'||';'||sum(bytes)/1073741824||';;;' "AVG (ms)"
  FROM  dba_free_space;

SELECT 'filler'||';'||'log_capacity'||';'||'filler'||';'||SUM(BYTES)/1073741824||';;;' "AVG (ms)"
  FROM  V$LOG;
prompt ;;;Capacity|

select 'filler'||';'||'recoverysize'||';'||'filler'||';'|| nvl(space_limit, 0) / 1024 / 1024 / 1024||';;;' "AVG (ms)"
 from v$recovery_file_dest;

select 'filler'||';'||'recoveryused'||';'||'filler'||';'|| nvl(space_used, 0) / 1024 / 1024 / 1024||';;;' "AVG (ms)"
 from v$recovery_file_dest;

SELECT 'filler'||';'||'tempfiles'||';'||'filler'||';'|| nvl(sum(bytes),0)/1024/1024/1024||';;;' "AVG (ms)"
 from dba_temp_files;

SELECT 'filler'||';'||'controlfiles'||';'||'filler'||';'|| sum(BLOCK_SIZE*FILE_SIZE_BLKS)/1024/1024/1024||';;;' "AVG (ms)"
 from v$controlfile;

prompt ;;;Cpct|

SELECT to_char(max(end_time),'yyyy-mm-dd hh24:mi')||';'||metric_name||';'||metric_unit||';'||round(avg(value))||';;;' "Result"
  FROM v$sysmetric_history
  WHERE metric_name = 'User Transaction Per Sec' AND ROWNUM <= 5
  GROUP BY metric_name,metric_unit;

SELECT to_char(max(end_time),'yyyy-mm-dd hh24:mi')||';'||metric_name||';'||metric_unit||';'||round(avg(value))||';;;' "Result"
  FROM v$sysmetric_history
  WHERE metric_name = 'User Commits Per Sec' AND ROWNUM <= 5
  GROUP BY metric_name,metric_unit;

SELECT to_char(max(end_time),'yyyy-mm-dd hh24:mi')||';'||metric_name||';'||metric_unit||';'||round(avg(value))||';;;' "Result"
  FROM v$sysmetric_history
  WHERE metric_name = 'Open Cursors Per Sec' AND ROWNUM <= 5
  GROUP BY metric_name,metric_unit;

SELECT to_char(max(end_time),'yyyy-mm-dd hh24:mi')||';'||metric_name||';'||metric_unit||';'||round(avg(value))||';;;' "Result"
  FROM v$sysmetric_history
  WHERE metric_name = 'Current Open Cursors Count' AND ROWNUM <= 5
  GROUP BY metric_name,metric_unit;

SELECT to_char(max(end_time),'yyyy-mm-dd hh24:mi')||';'||metric_name||';'||metric_unit||';'||round(avg(value))||';;;' "Result"
  FROM v$sysmetric_history
  WHERE metric_name = 'Hard Parse Count Per Sec' AND ROWNUM <= 5
  GROUP BY metric_name,metric_unit;

SELECT to_char(max(end_time),'yyyy-mm-dd hh24:mi')||';'||metric_name||';'||metric_unit||';'||round(avg(value))||';;;' "Result"
  FROM v$sysmetric_history
  WHERE metric_name = 'Executions Per Sec' AND ROWNUM <= 5
  GROUP BY metric_name,metric_unit;
prompt ;;;SQL query|



SELECT to_char(max(end_time),'yyyy-mm-dd hh24:mi')||';'||metric_name||';'||metric_unit||';'||round(avg(value))||';;;' "Result"
  FROM v$sysmetric_history
  WHERE metric_name = 'Network Traffic Volume Per Sec' AND ROWNUM <= 5
  GROUP BY metric_name,metric_unit;
prompt ;;;Network|



SELECT to_char(max(end_time),'yyyy-mm-dd hh24:mi')||';'||metric_name||';'||metric_unit||';'||round(avg(value))||';;;' "Result"
  FROM v$sysmetric_history
  WHERE metric_name = 'Database Wait Time Ratio' AND ROWNUM <= 5
  GROUP BY metric_name,metric_unit;

SELECT to_char(max(end_time),'yyyy-mm-dd hh24:mi')||';'||metric_name||';'||metric_unit||';'||round(avg(value))||';;;' "Result"
  FROM v$sysmetric_history
  WHERE metric_name = 'Database CPU Time Ratio' AND ROWNUM <= 5
  GROUP BY metric_name,metric_unit;

SELECT to_char(max(end_time),'yyyy-mm-dd hh24:mi')||';'||metric_name||';'||metric_unit||';'||round(avg(value))||';;;' "Result"
  FROM v$sysmetric_history
  WHERE metric_name = 'Buffer Cache Hit Ratio' AND ROWNUM <= 5
  GROUP BY metric_name,metric_unit;

SELECT to_char(max(end_time),'yyyy-mm-dd hh24:mi')||';'||metric_name||';'||metric_unit||';'||round(avg(value))||';;;' "Result"
  FROM v$sysmetric_history
  WHERE metric_name = 'Memory Sorts Ratio' AND ROWNUM <= 5
  GROUP BY metric_name,metric_unit;

SELECT to_char(max(end_time),'yyyy-mm-dd hh24:mi')||';'||metric_name||';'||metric_unit||';'||round(avg(value))||';;;' "Result"
  FROM v$sysmetric_history
  WHERE metric_name = 'Soft Parse Ratio' AND ROWNUM <= 5
  GROUP BY metric_name,metric_unit;

SELECT to_char(max(end_time),'yyyy-mm-dd hh24:mi')||';'||metric_name||';'||metric_unit||';'||round(avg(value))||';;;' "Result"
  FROM v$sysmetric_history
  WHERE metric_name = 'PGA Cache Hit %' AND ROWNUM <= 5
  GROUP BY metric_name,metric_unit;
prompt ;;;Ratio|


SELECT instance_name||';'||'Instance name'||';'||instance_name||';'||instance_name||';;;' "AVG (ms)"
  FROM  v$instance;

prompt ;;;Instance name|

SELECT host_name||';'||'Host name'||';'||host_name||';'||host_name||';;;' "AVG (ms)"
  FROM  v$instance;

prompt ;;;Host name|

exit;
