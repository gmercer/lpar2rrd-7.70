SET HEADING OFF
SET LIN 999


SELECT '2'||';'||'Redo Generated Per Sec'||';'||value||';'||value||';;;' "Result"
  FROM v$sysstat
  WHERE name = 'redo size';

SELECT '2'||';'||'Physical Read Bytes Per Sec'||';'||value||';'||value||';;;' "Result"
  FROM v$sysstat
  WHERE name = 'physical read total bytes';

SELECT '2'||';'||'Physical Write Bytes Per Sec'||';'||value||';'||value||';;;' "Result"
  FROM v$sysstat
  WHERE name = 'physical write total bytes';

SELECT '2'||';'||'Physical Reads Per Sec'||';'||value||';'||value||';;;' "Result"
  FROM v$sysstat
  WHERE name = 'physical read total IO requests';

SELECT '2'||';'||'Physical Writes Per Sec'||';'||value||';'||value||';;;' "Result"
  FROM v$sysstat
  WHERE name = 'physical write total IO requests';

SELECT '2'||';'||'DB Block Changes Per Sec'||';'||value||';'||value||';;;' "Result"
  FROM v$sysstat
  WHERE name = 'db block changes';

SELECT '2'||';'||'Logical Reads Per Sec'||';'||value||';'||value||';;;' "Result"
  FROM v$sysstat
  WHERE name = 'session logical reads';
prompt ;;;Data rate|

SELECT 'filler'||';'||'used'||';'||'filler'||';'||sum(bytes)/1073741824||';;;' "AVG (ms)"
  FROM  dba_data_files;

SELECT 'filler'||';'||'free'||';'||'filler'||';'||sum(bytes)/1073741824||';;;' "AVG (ms)"
  FROM  dba_free_space;
prompt ;;;Capacity|

SELECT '2'||';'||'Current Logons Count'||';'||value||';'||value||';;;' "Result"
  FROM v$sysstat
  WHERE name = 'logons current';

SELECT '2'||';'||'Logons Per Sec'||';'||value||';'||value||';;;' "Result"
  FROM v$sysstat
  WHERE name = 'user logons cumulative';
prompt ;;;Session info|



SELECT '2'||';'||'User Commits Per Sec'||';'||value||';'||value||';;;' "Result"
  FROM v$sysstat
  WHERE name = 'user commits';

SELECT '2'||';'||'Current Open Cursors Count'||';'||value||';'||value||';;;' "Result"
  FROM v$sysstat
  WHERE name = 'opened cursors current';

SELECT '2'||';'||'Open Cursors Per Sec'||';'||value||';'||value||';;;' "Result"
  FROM v$sysstat
  WHERE name = 'opened cursors cumulative';

SELECT '2'||';'||'Hard Parse Count Per Sec'||';'||value||';'||value||';;;' "Result"
  FROM v$sysstat
  WHERE name = 'parse count (hard)';

SELECT '2'||';'||'Executions Per Sec'||';'||value||';'||value||';;;' "Result"
  FROM v$sysstat
  WHERE name = 'execute count';
prompt ;;;SQL query|


SELECT to_char(max(end_time),'yyyy-mm-dd hh24:mi')||';'||metric_name||';'||metric_unit||';'||round(avg(value))||';;;' "Result"
  FROM v$con_sysmetric_history
  WHERE metric_name = 'Network Traffic Volume Per Sec' AND ROWNUM <= 5
  GROUP BY metric_name,metric_unit;
prompt ;;;Network|


SELECT total_waits||';'||event||';'||time_waited_micro||';'||round(time_waited_micro/total_waits)/1e3||';;;' "AVG (ms)"
  FROM  v$system_event
  WHERE event = 'db file sequential read';


SELECT total_waits||';'||event||';'||time_waited_micro||';'||round(time_waited_micro/total_waits)/1e3||';;;' "AVG (ms)"
  FROM  v$system_event
  WHERE event = 'db file scattered read';


SELECT total_waits||';'||event||';'||time_waited_micro||';'||round(time_waited_micro/total_waits)/1e3||';;;' "AVG (ms)"
  FROM  v$system_event
  WHERE event = 'db file single write';


SELECT total_waits||';'||event||';'||time_waited_micro||';'||round(time_waited_micro/total_waits)/1e3||';;;' "AVG (ms)"
  FROM  v$system_event
  WHERE event = 'db file parallel write';


SELECT total_waits||';'||event||';'||time_waited_micro||';'||round(time_waited_micro/total_waits)/1e3||';;;' "AVG (ms)"
  FROM  v$system_event
  WHERE event = 'log file single write';


SELECT total_waits||';'||event||';'||time_waited_micro||';'||round(time_waited_micro/total_waits)/1e3||';;;' "AVG (ms)"
  FROM  v$system_event
  WHERE event = 'log file parallel write';


SELECT total_waits||';'||event||';'||time_waited_micro||';'||round(time_waited_micro/total_waits)/1e3||';;;' "AVG (ms)"
  FROM  v$system_event
  WHERE event = 'log file sync';


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
  WHERE metric_name = 'PGA Cache Hit %' AND ROWNUM <= 5
  GROUP BY metric_name,metric_unit;

SELECT 'Buffer Cache Ratio'||';'||'Buffer Cache Ratio'||';'||'Buffer Cache Ratio'||';'||round(sum((c.log_read-c.phys_read)/c.log_read)*100,2)||';;;' "Result"
  FROM (select a.value as log_read,b.value as phys_read
  FROM v$sysstat a,
       v$sysstat b
       WHERE a.name = 'logical read bytes from cache'
       AND b.name = 'physical read total bytes') c;

SELECT 'Memory Sorts Ratio'||';'||'Memory Sorts Ratio'||';'||'Memory Sorts Ratio'||';'||round(sum(c.mem_sort/(c.mem_sort + c.disk_sort))*100,2)||';;;' "Result"
  FROM (select a.value as mem_sort,b.value as disk_sort
  FROM v$sysstat a,
       v$sysstat b
       WHERE a.name = 'sorts (memory)'
       AND b.name = 'sorts (disk)') c;

SELECT 'Soft Parse Ratio'||';'||'Soft Parse Ratio'||';'||'Soft Parse Ratio'||';'||round(sum(c.soft_parse/c.total_parse)*100,2)||';;;' "Result"
  FROM (select a.value as total_parse,(a.value-b.value) as soft_parse
  FROM v$sysstat a,
       v$sysstat b
       WHERE a.name = 'parse count (total)'
       AND b.name = 'parse count (hard)') c;
prompt ;;;Ratio|

SELECT name||';'||'PDB name'||';'||name||';'||name||';;;' "AVG (ms)"
FROM v$containers;

prompt ;;;PDBname|

exit;
