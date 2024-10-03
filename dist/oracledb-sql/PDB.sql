SET LIN 999
SET MARKUP CSV ON DELIMITER |

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
             round(NVL2(a.fbytes,a.fbytes,'0')/1024/1024) as Free_space_MB,
             round(a.tbytes/1024/1024) Velikost_MB,
             round(b.maxbytes/1024/1024) Max_MB,
             b.autoextensible
           from
             ( select
                 tablespace_name,
                 sum(tablespace_size) tbytes,
                 sum(free_space) fbytes 
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
             round(NVL2(a.fbytes,a.fbytes,'0')/1024/1024) as Free_space_MB,
             round(a.tbytes/1024/1024) Velikost_MB,
             round(b.bytes/1024/1024) Max_MB,
             b.autoextensible
           from
             ( select
                 tablespace_name,
                 sum(tablespace_size) tbytes,
                 sum(free_space) fbytes 
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
prompt PDB info

select name,dbid,block_size,round(total_size/1024/1024) PDB_total_size_MB,restricted,application_pdb,application_seed,proxy_pdb,con_uid,guid,open_mode from v$containers;


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
