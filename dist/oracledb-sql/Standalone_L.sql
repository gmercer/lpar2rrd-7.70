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

SELECT 'filler'||';'||'used'||';'||'filler'||';'||sum(bytes)/1073741824||';;;' "AVG (ms)"
  FROM  dba_data_files;

SELECT 'filler'||';'||'free'||';'||'filler'||';'||sum(bytes)/1073741824||';;;' "AVG (ms)"
  FROM  dba_free_space;
SELECT 'filler'||';'||'log_capacity'||';'||'filler'||';'||SUM(BYTES)/1073741824||';;;' "AVG (ms)"
  FROM  V$LOG;

prompt ;;;Capacity|



select 'filler'||';'||'recoverysize'||';'||'filler'||';'|| nvl(sum(space_limit), 0) / 1024 / 1024 / 1024||';;;' "AVG (ms)"
 from v$recovery_file_dest;

select 'filler'||';'||'recoveryused'||';'||'filler'||';'|| nvl(sum(space_used), 0) / 1024 / 1024 / 1024||';;;' "AVG (ms)"
 from v$recovery_file_dest;

SELECT 'filler'||';'||'tempfiles'||';'||'filler'||';'|| nvl(sum(bytes),0)/1024/1024/1024||';;;' "AVG (ms)"
 from dba_temp_files; 

SELECT 'filler'||';'||'controlfiles'||';'||'filler'||';'|| sum(BLOCK_SIZE*FILE_SIZE_BLKS)/1024/1024/1024||';;;' "AVG (ms)"
 from v$controlfile;

prompt ;;;Cpct|


SELECT instance_name||';'||'Instance name'||';'||instance_name||';'||instance_name||';;;' "AVG (ms)"
  FROM  v$instance;

prompt ;;;Instance name|

SELECT host_name||';'||'Host name'||';'||host_name||';'||host_name||';;;' "AVG (ms)"
  FROM  v$instance;

prompt ;;;Host name|

exit;
