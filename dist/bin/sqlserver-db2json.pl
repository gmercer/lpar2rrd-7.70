use strict;
use warnings;

use DBI;
use HostCfg;
use Xorux_lib qw(error read_json write_json);
use Data::Dumper;
use SQLServerDataWrapper;

my $sh_alias;

if (@ARGV) {
  $sh_alias = $ARGV[0];
}

if ( !$sh_alias ) {
  warn "SQL Server couldn't retrieve alias" && exit 1;
}

my $alias          = "$sh_alias";
my $inputdir       = $ENV{INPUTDIR};
my $home_dir       = "$inputdir/data/SQLServer";
my $act_dir        = "$home_dir/$alias";
my $iostats_dir    = "$act_dir/iostats";
my $conf_dir       = "$act_dir/Configuration";
my $hs_dir         = "$ENV{INPUTDIR}/tmp/health_status_summary";
my $hs_dir_mssql   = "$hs_dir/SQLServer";
my $total_dir      = "$home_dir/_Totals";
my $total_conf_dir = "$total_dir/Configuration";
my %creds          = %{ HostCfg::getHostConnections("SQLServer") };
my $db_name        = $creds{$alias}{instance};
my $port           = $creds{$alias}{port};
my $username       = $creds{$alias}{username};
my $password       = $creds{$alias}{password};
my $ip             = $creds{$alias}{host};
my $use_whitelist  = $creds{$alias}{use_whitelist};
my $mirrored       = $creds{$alias}{mirrored};
my $odbc_inst      = "/etc/odbcinst.ini";
my $driver_file    = "$home_dir/sqlserver_driver.txt";
my %instances;

#warn Dumper \%creds;
my %whitelisted;

#warn $use_whitelist;
if ($use_whitelist) {
  if ( defined $creds{$alias}{dbs}[0] ) {
    foreach my $wl_db ( @{ $creds{$alias}{dbs} } ) {
      $whitelisted{$wl_db} = 1;
    }
  }

  #  warn Dumper \%whitelisted;
}

my $driver = SQLServerDataWrapper::get_driver();
chomp($driver);

if ( $driver eq "err-incodriver" ) {

  #my $cat = `cat $driver_file`;
  warn("Incorrect driver in the file \"$driver_file\" ");    #\nFILE contents: $cat");
  exit 1;
}
elsif ( $driver eq "err-driverne" ) {

  #my $cat = `cat $odbc_inst`;
  warn("Could't find suitable driver in the file \"$odbc_inst\" \n ");    #FILE contents:\n $cat");
  exit 1;
}
elsif ( $driver eq "err-instne" ) {
  warn("File \"$odbc_inst\" doesn't exist.");
  exit 1;
}

my @health_status;

unless ( -d $home_dir ) {
  mkdir( $home_dir, 0755 ) || warn("Cannot mkdir $home_dir: $!") && exit 1;
}
unless ( -d $act_dir ) {
  mkdir( $act_dir, 0755 ) || warn("Cannot mkdir $act_dir: $!") && exit 1;
}
unless ( -d $iostats_dir ) {
  mkdir( $iostats_dir, 0755 ) || warn("Cannot mkdir $iostats_dir: $!") && exit 1;
}
unless ( -d $hs_dir ) {
  mkdir( $hs_dir, 0755 ) || warn("Cannot mkdir $hs_dir: $!") && exit 1;
}
unless ( -d $hs_dir_mssql ) {
  mkdir( $hs_dir_mssql, 0755 ) || warn("Cannot mkdir $hs_dir_mssql: $!") && exit 1;
}
unless ( -d $conf_dir ) {
  mkdir( $conf_dir, 0755 ) || warn("Cannot mkdir $conf_dir: $!") && exit 1;
}
unless ( -d $total_dir ) {
  mkdir( $total_dir, 0755 ) || warn("Cannot mkdir $total_dir: $!") && exit 1;
}
unless ( -d $total_conf_dir ) {
  mkdir( $total_conf_dir, 0755 ) || warn("Cannot mkdir $total_conf_dir: $!") && exit 1;
}

#################################################################################################################################

my $data = get_data( $driver, $ip, $db_name, $port, $username, $password, $mirrored );

#print Dumper $data->{waitevents};
#print Dumper $data->{counters};
#warn Dumper $data->{size};
#warn Dumper $data;

if ( $data ne "err" ) {
  my %arc;
  foreach my $row ( @{ $data->{db_list}->{$db_name}->{data} } ) {
    my $db_id = Xorux_lib::uuid_big_endian_format( SQLServerDataWrapper::md5_string("$row->{database_name}-$row->{database_id}-$alias") );
    $arc{hostnames}{ $creds{$alias}{uuid} }{alias} = $alias;
    $arc{hostnames}{ $creds{$alias}{uuid} }{label} = "Cluster";

    $arc{hostnames}{ $creds{$alias}{uuid} }{_dbs}{$db_id}{id}    = "$row->{database_id}";
    $arc{hostnames}{ $creds{$alias}{uuid} }{_dbs}{$db_id}{label} = "$row->{database_name}";
  }

  #  warn Dumper \%arc;
  Xorux_lib::write_json( "$conf_dir/arc.json", \%arc );

  my $act_perf = make_perf($data);

  #warn Dumper \%instances;
  for my $instance ( keys %instances ) {
    next if ( $instance eq $db_name );
    my $n_data = get_data( $driver, $ip, $instance, $port, $username, $password, $mirrored, "MULTIDATA" );
    next if( $n_data eq "err" );
    #    warn Dumper $n_data;
    for my $data_type ( keys %{$n_data} ) {
      for my $db ( keys %{ $n_data->{$data_type} } ) {
        $data->{$data_type}->{$db} = $n_data->{$data_type}->{$db};
      }
    }

    #    warn Dumper $data;
  }

  #print Dumper $data;
  #warn Dumper $data;
  my $act_conf = make_conf($data);

  #  warn Dumper $act_conf;
  $act_perf->{capacity} = $act_conf->{capacity};

  #warn Dumper $act_perf;
  Xorux_lib::write_json( "$iostats_dir/sqlserver_perf.json", $act_perf );
  Xorux_lib::write_json( "$conf_dir/sqlserver_conf.json",    $act_conf );

}

generate_hsfiles();

#print Dumper $res;

#################################################################################################################################

sub make_perf {
  my $_data      = shift;
  my %_data      = %{$_data};
  my %perf_types = (
    virtual     => 1,
    c_counters  => 1,
    counters    => 1,
    wait_events => 1,
    capacity    => 1,
  );

  my %perf;
  for my $type ( keys %perf_types ) {

    #    if($perf_types{$type}){
    #      warn "Couldn't find the data for type: $type in perf";
    #    }
    #    print Dumper $_data{$type}{$db_name}{data};
    if ( $type eq "virtual" ) {
      foreach my $row ( @{ $_data{$type}{$db_name}{data} } ) {
        my %row_dup = %{$row};
        delete $row_dup{name};
        my $accepted = 0;
        if ($use_whitelist) {
          if ( $whitelisted{ $row->{name} } ) {
            $accepted = 1;
          }
        }
        else {
          $accepted = 1;
        }

        if ($accepted) {
          $instances{ $row->{name} } = 1;
          $perf{$type}{ $row->{name} } = \%row_dup;
        }
      }
    }
    elsif ( $type eq "counters" ) {
      foreach my $row ( @{ $_data{$type}{$db_name}{data} } ) {
        my %row_dup = %{$row};
        $row_dup{instance_name} =~ s/\s+$//g;
        $row_dup{counter_name}  =~ s/\s+$//g;
        my $accepted = 0;
        if ($use_whitelist) {
          if ( $whitelisted{ $row_dup{instance_name} } ) {
            $accepted = 1;
          }
        }
        else {
          $accepted = 1;
        }

        if ($accepted) {
          $instances{ $row_dup{instance_name} } = 1;
          $perf{$type}{ $row_dup{instance_name} }{ $row_dup{counter_name} } = $row_dup{cntr_value};
        }
      }
    }
    elsif ( $type eq "c_counters" ) {
      foreach my $row ( @{ $_data{$type}{$db_name}{data} } ) {
        my %row_dup = %{$row};
        $row_dup{instance_name} =~ s/\s+$//g;
        $row_dup{counter_name}  =~ s/\s+$//g;
        my $accepted = 0;
        $perf{counters}{Cluster}{ $row_dup{counter_name} } = $row_dup{cntr_value};
      }
    }
    elsif ( $type eq "wait_events" ) {
      foreach my $row ( @{ $_data{$type}{$db_name}{data} } ) {
        my %row_dup = %{$row};
        $perf{$type}{Cluster}{ $row_dup{wait_type} } = $row_dup{wait_time_ms};
      }
    }
  }

  $perf{_info}{timestamp}     = time;
  $perf{_info}{readable_time} = localtime( $perf{_info}{timestamp} );

  return \%perf;
}

sub make_conf {
  my $_data      = shift;
  my %_data      = %{$_data};
  my %conf_types = (
    flgrps     => 1,
    datafiles2 => 1,
    m1         => 1,
    m2         => 1,
    m3         => 1,
    capacity   => 1,
  );

  my %perf;
  for my $type ( keys %conf_types ) {

    #    if($conf_types{$type}){
    #      warn "Couldn't find the data for type: $type in conf";
    #    }

    if ( $type =~ m/m[1,2,3]/ ) {
      if ( $type eq "m1" ) {
        foreach my $row ( @{ $_data{$type}{$db_name}{data} } ) {
          my %row_dup = %{$row};
          my %nr;
          my $value = $row_dup{value};
          $value =~ s/[\r\n]//g;
          $perf{_cluster}{main}{cluster}[0]{ $row_dup{name} } = $value;
        }
      }
      else {
        foreach my $row ( @{ $_data{$type}{$db_name}{data} } ) {
          my %row_dup = %{$row};
          for my $key ( keys %row_dup ) {
            my $value = $row_dup{$key};
            $value =~ s/[\r\n]//g;
            $perf{_cluster}{main}{cluster}[0]{$key} = $value;
          }
        }
      }
    }
    elsif ( $type eq "capacity" ) {
      for my $_db_name ( keys %{ $_data{$type} } ) {
        foreach my $row ( @{ $_data{$type}{$_db_name}{data} } ) {
          my %row_dup = %{$row};

          my $_data              = convert_to_gb( $row->{'data'},              'data' );
          my $_index_size        = convert_to_gb( $row->{'index_size'},        'index_size' );
          my $_reserved          = convert_to_gb( $row->{'reserved'},          'reserved' );
          my $_unallocated_space = convert_to_gb( $row->{'unallocated space'}, 'unallocated space' );
          my $_database_size     = convert_to_gb( $row->{'database_size'},     'database_size' );
          my $_unused            = convert_to_gb( $row->{'unused'},            'unused' );
          $perf{$type}{$_db_name}{used}      = $_data + $_index_size;
          $perf{$type}{$_db_name}{available} = $_unallocated_space;
          $perf{$type}{$_db_name}{log_space} = $_database_size - ( $_unallocated_space + $_reserved );
          $perf{$type}{$_db_name}{unused}    = $_unused;
        }
      }
    }
    else {
      for my $d_name ( keys %{ $_data{$type} } ) {
        my $row_counter = 0;
        foreach my $row ( @{ $_data{$type}{$d_name}{data} } ) {
          my %row_dup = %{$row};
          next if ( !defined $row or !defined $type or !defined $d_name or !defined $_data{$type}{$d_name}{data} );
          $perf{_cluster}{$type}{$d_name}[$row_counter] = \%row_dup;
          $row_counter++;
        }
      }
    }
  }

  $perf{_info}{timestamp}     = time;
  $perf{_info}{readable_time} = localtime( $perf{_info}{timestamp} );

  return \%perf;
}

sub convert_to_gb {
  my $_value  = shift;
  my $type    = shift;
  my $new_val = $_value;
  if ( defined $new_val and $new_val =~ / KB/ ) {
    $new_val =~ s/ KB//g;
    $new_val /= 1000;
  }
  elsif ( defined $new_val and $new_val =~ / MB/ ) {
    $new_val =~ s/ MB//g;
    $new_val /= 1;
  }
  elsif ( defined $new_val and $new_val =~ / GB/ ) {
    $new_val =~ s/ GB//g;
  }
  elsif ( defined $new_val and $new_val =~ / TB/ ) {
    $new_val =~ s/ TB//g;
    $new_val *= 1;
  }
  else {
    warn "$_value, $type";
    return 0;
  }

  return $new_val;
}

sub get_data {
  my $_driver   = shift;
  my $_ip       = shift;
  my $_database = shift;
  my $_port     = shift;
  my $_user     = shift;
  my $_password = shift;
  my $mirrored  = shift;
  my $multidata = shift;

  my $msfail    = "";
  if (!defined $mirrored or (defined $mirrored and $mirrored)){
    $msfail = ";MultiSubnetFailover=Yes";
  }

  my $dbh = DBI->connect(
    "DBI:ODBC:driver=$_driver;Server=$_ip,$_port;database=$_database;
                          ApplicationIntent=ReadOnly$msfail;Encrypt=no",
    $_user, $_password, { PrintError => 0, RaiseError => 0, ReadOnly => 1 }
  );

  my $time_is_now = time;
  my $err         = DBI->errstr;

  #warn "ERROR $err";
  if ( $err and !( defined $dbh ) ) {
    my @row;
    $row[0] = "SQLServer";
    $row[1] = "$alias";
    $row[2] = "$_database";
    $row[3] = "NOT_OK";
    $row[4] = "$time_is_now";
    $row[5] = $err;
    push( @health_status, \@row );
  }
  else {
    my @row;
    $row[0] = "SQLServer";
    $row[1] = "$alias";
    $row[2] = "$_database";
    $row[3] = "OK";
    $row[4] = "$time_is_now";
    push( @health_status, \@row );
  }

  if ( !( defined $dbh ) ) {
    warn $err;
    return "err";
  }

  my %_data;
  my %queries = %{ get_queries($multidata) };

  #trade
  for my $query_name ( keys %queries ) {
    my $array_ref = get_query_result( $dbh, $queries{$query_name} );
    $_data{$query_name}{$_database}{data} = $array_ref;
    $_data{$query_name}{$_database}{info}{db_name} = $_database;
  }

  # clean up
  $dbh->disconnect();

  return \%_data;
}

sub get_query_result {
  my $_dbh  = shift;
  my $query = shift;
  my @array;

  #warn $query;
  my $sth = $_dbh->prepare($query);
  $sth->execute();
  if (!defined $sth->err){
    if ( $query =~ /sp_spaceused/ ) {

      my ( %hash1, %hash2 );
      while ( my $row = $sth->fetchrow_hashref() ) {
        %hash1 = %{$row};
      }
      while ( my $row = $sth->fetchrow_hashref() ) {
        %hash2 = %{$row};
      }
      %hash1 = ( %hash1, %hash2 );

      push( @array, \%hash1 );
    }
    else {
      while ( my $ref = $sth->fetchrow_hashref() ) {
        push( @array, $ref );
      }
    }
    return \@array;
  }else{
    warn DBI->errstr;
    return [];
  }
}

sub generate_hsfiles {
  foreach my $row (@health_status) {
    my @row_arr = @{$row};

    if ( $row_arr[3] eq "OK" ) {
      my $checkup_file_ok  = "$hs_dir_mssql/$alias\_$row_arr[2].ok";
      my $checkup_file_nok = "$hs_dir_mssql/$alias\_$row_arr[2].nok";
      if ( -f $checkup_file_nok ) {
        unlink $checkup_file_nok;
      }
      my $joined_row = join( " : ", @row_arr );
      open my $fh, '>', $checkup_file_ok;

      print $fh $joined_row;
      close $fh;

    }
    elsif ( $row_arr[3] eq "NOT_OK" ) {
      my $checkup_file_ok  = "$hs_dir_mssql/$alias\_$row_arr[2].ok";
      my $checkup_file_nok = "$hs_dir_mssql/$alias\_$row_arr[2].nok";
      if ( -f $checkup_file_ok ) {
        unlink $checkup_file_ok;
      }

      if ( !-f $checkup_file_nok ) {
        my $joined_row = join( " : ", @row_arr );
        open my $fh, '>', $checkup_file_nok;
        print $fh $joined_row;
        close $fh;
      }
    }
  }
}

sub get_queries {
  my $multidata = shift;

  my $dbs = q( 
  SELECT [name] AS database_name, 
      database_id, 
      create_date
  FROM sys.databases
  ORDER BY name;
  );

  my $dbs2 = q(
  SELECT name FROM master.dbo.sysdatabases;
  );

  my $dbs3 = q(
  EXEC sp_databases;
  );

  my $cpu = q(
  USE [master]

  SELECT
    cpu_idle = record.value('(./Record/SchedulerMonitorEvent/SystemHealth/SystemIdle)[1]', 'int'),
    cpu_sql = record.value('(./Record/SchedulerMonitorEvent/SystemHealth/ProcessUtilization)[1]', 'int')
  FROM (
      SELECT TOP 1 CONVERT(XML, record) AS record
      FROM sys.dm_os_ring_buffers
      WHERE ring_buffer_type = N'RING_BUFFER_SCHEDULER_MONITOR'
        AND record LIKE '% %'
    ORDER BY TIMESTAMP DESC
  ) as cpu_usage;
  );

  #CPU time
  my $cpu_per_db = q(
  WITH CPU_Per_DB
  AS
  (
   SELECT 
    dmpa.DatabaseID,
    DB_Name(dmpa.DatabaseID) AS [Database],
    SUM(dmqs.total_worker_time) AS CPUTimeAsMS
    FROM sys.dm_exec_query_stats dmqs 
    CROSS APPLY 
   (
    SELECT 
     CONVERT(INT, value) AS [DatabaseID] 
     FROM sys.dm_exec_plan_attributes(dmqs.plan_handle)
    WHERE attribute = N'dbid'
   ) dmpa GROUP BY dmpa.DatabaseID
  )
   
   SELECT 
   [DatabaseID],
   [Database],
   [CPUTimeAsMS],
   CAST([CPUTimeAsMS] * 1.0 / SUM([CPUTimeAsMS]) OVER() * 100.0 AS DECIMAL(5, 2)) AS [CPUTimeAs_percent]
   FROM CPU_Per_DB
   ORDER BY [CPUTimeAsMS] DESC;
  );

  my $cpu_lgcl = q(
  SELECT (cpu_count / hyperthread_ratio) AS PhysicalCPUs,   
  cpu_count AS logicalCPUs   
  FROM sys.dm_os_sys_info; 
  );

  # great showcase of using CTE as a way to save myself the trouble of calculating it afterwards
  my $datafiles = q(
  ;WITH f AS 
  (
    SELECT name, size = size/128.0 FROM sys.database_files
  ),
  s AS
  (
    SELECT name, size, free = size-CONVERT(INT,FILEPROPERTY(name,'SpaceUsed'))/128.0
    FROM f
  )
  SELECT name, size, free, percent_free = free * 100.0 / size
  FROM s;
  );

  my $datafiles2 = q(
  SELECT
    TOP (50)
    s.Name AS SchemaName,
    t.NAME AS TableName,
    o.type_desc AS Type,
    p.rows,
    SUM(a.total_pages) * 8000 AS TotalSpace,
    SUM(a.used_pages) * 8000  AS UsedSpace,
    CAST((CAST(SUM(a.used_pages) AS float) / NULLIF(CAST(SUM(a.total_pages) AS float), 0.0) *100) AS int) AS UsedPercent
  FROM 
    sys.tables t
  INNER JOIN      
    sys.indexes i ON t.OBJECT_ID = i.object_id
  INNER JOIN 
    sys.partitions p ON i.object_id = p.OBJECT_ID AND i.index_id = p.index_id
  INNER JOIN 
    sys.objects o ON t.OBJECT_ID = o.OBJECT_ID OR i.object_id = o.OBJECT_ID OR i.index_id = o.object_id
  INNER JOIN 
    sys.allocation_units a ON p.partition_id = a.container_id
  LEFT OUTER JOIN 
    sys.schemas s ON t.schema_id = s.schema_id
  WHERE 
    t.NAME NOT LIKE 'dt%' 
    AND t.is_ms_shipped = 0
    AND i.OBJECT_ID > 255 
  GROUP BY 
    t.Name, s.Name, p.Rows,o.type_desc
  ORDER BY 
    TotalSpace DESC, t.Name;
  );

  my $logspace = q(
  SELECT *  
  FROM sys.dm_db_log_space_usage; 
  );

  #GRANT EXECUTE ON xp_readerrorlog TO _USERNAME_or_GROUPNAME
  #sp_readerrorlog
  my $err_log = q(
  EXEC xp_ReadErrorLog 0;
  );

  my $hosts = q( 
  SELECT * FROM sys.dm_os_hosts;
  );

  my $blocks = q(
  USE [master]

  SELECT
  session_id,
  blocking_session_id,
  wait_time,
  wait_type,
  last_wait_type,
  wait_resource,
  transaction_isolation_level,
  lock_timeout
  FROM sys.dm_exec_requests
  WHERE blocking_session_id >= 0;
  );

  my $event_log = q(
  SELECT [Begin Time], [Transaction Name] from fn_dblog(null, null);
  );

  my $transactions = q(
  SELECT I.instance_name
        ,I.counter_name
        ,I.cntr_type
        ,I.cntr_value
        ,I.object_name
  FROM sys.dm_os_performance_counters as I
    INNER JOIN sys.databases AS D  
      ON I.instance_name = d.name;
  );

  my $cluster_node = q(
  SELECT * FROM sys.dm_os_cluster_nodes;
  );

  my $filegroups = q(
  SELECT
  df.name AS [DB File Name],
  df.size AS [File Size],
  fg.name AS [File Group Name],
  df.physical_name AS [File Path]
  FROM sys.database_files AS df
  INNER JOIN sys.filegroups AS fg
  ON df.data_space_id = fg.data_space_id;
  );

  # Make sure to monitor MAXDOP, really usefull for parallelism control
  my $p_counters = q(
  SELECT I.instance_name
        ,I.counter_name
        ,I.cntr_type
        ,I.cntr_value
  FROM sys.dm_os_performance_counters as I
    INNER JOIN sys.databases AS D  
      ON I.instance_name = d.name
  WHERE I.counter_name IN
      ('Background writer pages/sec','Checkpoint pages/sec','Page life expectancy',
      'Lazy writes/sec','Page reads/sec','Page writes/sec','Readahead pages/sec',
      'Readahead time/sec','Database pages','Extension allocated pages',
      'Extension free pages','Target pages','User Connections','Connection Reset/sec',
      'Logins/sec','Logouts/sec','Active cursors','Cursor Requests/sec',
      'Cached Cursors Counts','Transactions','Transactions/sec','Tracked transactions/sec',
      'Write Transactions/sec','Active Transactions','Locks Requests/sec',
      'Locks Waits/sec','Number of Deadlocks/sec','Lock Timeouts/sec',
      'Cache Hit Ratio','Cache Hit Ratio base',
      'Buffer cache hit ratio','Buffer cache hit ratio base',
      'Log Cache Hit Ratio','Log Cache Hit Ratio base');
  );

  #WHERE object_name = 'Resource';

  # Make sure to monitor MAXDOP, really usefull for parallelism control
  my $c_counters = q(
  SELECT instance_name
        ,counter_name
        ,cntr_type
        ,cntr_value
  FROM sys.dm_os_performance_counters as I
  WHERE instance_name = '' AND I.counter_name IN
      ('Background writer pages/sec','Buffer cache hit ratio','Buffer cache hit ratio base',
       'Checkpoint pages/sec','Database pages','Extension allocated pages',
       'Extension free pages','Lazy writes/sec','Logins/sec',
       'Logouts/sec','Page life expectancy','Page reads/sec',
       'Page writes/sec','Readahead pages/sec','Readahead time/sec',
       'Target pages','Transactions','User Connections','Connection Reset/sec',
       'Free Memory (KB)','Reserved Server Memory (KB)',
       'Target Server Memory (KB)','Total Server Memory (KB)'
      );
  );

  my $waitevents_l = q(
    SELECT * FROM sys.dm_os_wait_stats  WHERE ( wait_type LIKE '%LATCH_%' OR wait_type LIKE 'LCK_M_%') OR wait_type in (
      'RESOURCE_SEMAPHORE_QUERY_COMPILE','SOS_SCHEDULER_YIELD','ASYNC_NETWORK_IO',
      'MSQL_XP','EXECSYNC,WRITE_COMPLETION',
      'IO_COMPLETION','CXPACKET','WRITELOG','THREADPOOL');
  );

  my $waitevents = q(
  WITH waits AS
  (SELECT
    wait_type,
    wait_time_ms / 1000.0 AS waits,
    (wait_time_ms - signal_wait_time_ms) / 1000.0 AS resources,
    signal_wait_time_ms / 1000.0 AS signals,
    waiting_tasks_count AS waitcount,
    100.0 * wait_time_ms / sum (wait_time_ms) over() AS percentage,
    row_number() over(order by wait_time_ms desc) AS rownum
  FROM sys.dm_os_wait_stats
  WHERE wait_type NOT IN (
    N'CLR_SEMAPHORE', N'LAZYWRITER_SLEEP',
    N'RESOURCE_QUEUE', N'SQLTRACE_BUFFER_FLUSH',
    N'SLEEP_TASK', N'SLEEP_SYSTEMTASK',
    N'WAITFOR', N'HADR_FILESTREAM_IOMGR_IOCOMPLETION',
    N'CHECKPOINT_QUEUE', N'REQUEST_FOR_DEADLOCK_SEARCH',
    N'XE_TIMER_EVENT', N'XE_DISPATCHER_JOIN',
    N'LOGMGR_QUEUE', N'FT_IFTS_SCHEDULER_IDLE_WAIT',
    N'BROKER_TASK_STOP', N'CLR_MANUAL_EVENT',
    N'CLR_AUTO_EVENT', N'DISPATCHER_QUEUE_SEMAPHORE',
    N'TRACEWRITE', N'XE_DISPATCHER_WAIT',
    N'BROKER_TO_FLUSH', N'BROKER_EVENTHANDLER',
    N'FT_IFTSHC_MUTEX', N'SQLTRACE_INCREMENTAL_FLUSH_SLEEP',
    N'DIRTY_PAGE_POLL', N'SP_SERVER_DIAGNOSTICS_SLEEP')
  )
  SELECT
    w1.wait_type AS waittype, 
    CAST (w1.waits AS decimal(14, 2)) wait_s,
    CAST (w1.resources AS decimal(14, 2)) resource_s,
    CAST (w1.signals AS decimal(14, 2)) signal_s,
    w1.waitcount wait_count,
    CAST (w1.percentage AS decimal(4, 2)) percentage,
    CAST ((w1.waits / w1.waitcount) AS decimal (14, 4)) avgWait_s,
    CAST ((w1.resources / w1.waitcount) AS decimal (14, 4)) avgResource_s,
    CAST ((w1.signals / w1.waitcount) AS decimal (14, 4)) avgSignal_s
  FROM waits AS w1
  INNER JOIN waits AS w2 ON w2.rownum <= w1.rownum
  GROUP BY w1.rownum, w1.wait_type, w1.waits, w1.resources, w1.signals, w1.waitcount, w1.percentage
  HAVING sum (w2.percentage) - w1.percentage < 95; -- percentage threshold;
  );

  my $virtual = q(
  SELECT name
      ,SUM(num_of_reads) AS 'io_rd'
      ,SUM(num_of_writes) AS 'io_wr'
      ,SUM(num_of_reads + num_of_writes) AS 'io_total'
      ,SUM(num_of_bytes_read / 1024) AS 'data_rd'
      ,SUM(num_of_bytes_written / 1024) AS 'data_wr'
      ,SUM((num_of_bytes_read + num_of_bytes_written) / 1024) AS 'data_total'
      ,CAST(SUM(io_stall_read_ms) / (1.0 + SUM(num_of_reads)) AS NUMERIC(10,1)) AS 'latency_rd'
      ,CAST(SUM(io_stall_write_ms) / (1.0 + SUM(num_of_writes) ) AS NUMERIC(10,1)) AS 'latency_wr'
      ,CAST(SUM(io_stall) / (1.0 + SUM(num_of_reads + num_of_writes)) AS NUMERIC(10,1)) AS 'latency_total'
  FROM sys.dm_io_virtual_file_stats(NULL, NULL) AS I
    INNER JOIN sys.databases AS D  
      ON I.database_id = d.database_id
  GROUP BY name ORDER BY 'name' DESC;
  );

  my $vrtl = q(
  SELECT name AS 'Database Name'
      ,SUM(num_of_reads) AS 'Number of Read'
      ,SUM(num_of_writes) AS 'Number of Writes' 
  FROM sys.dm_io_virtual_file_stats(NULL, NULL) I
  INNER JOIN sys.databases D  
      ON I.database_id = d.database_id
  GROUP BY name ORDER BY 'Number of Read' DESC;
  );

  my $main01 = q(
  SELECT name,value FROM sys.configurations WHERE name IN('remote access','remote data archive','max degree of parallelism');
  );

  my $main02 = q(
  SELECT physical_memory_kb*1000 as physical_memory,virtual_memory_kb*1000 as virtual_memory,max_workers_count,socket_count,cores_per_socket,cpu_count,hyperthread_ratio,numa_node_count,softnuma_configuration FROM sys.dm_os_sys_info;
  );

  my $main03 = q(
  SELECT host_platform, host_distribution, host_release FROM sys.dm_os_host_info;

  );

  # exec sp_spaceused @oneresultset = 1
  my $size = q(
    exec sp_spaceused;
  );

  my %queries = (
    capacity => $size,
    db_list  => $dbs,
##    datafiles   => $datafiles,
    datafiles2 => $datafiles2,
    counters   => $p_counters,
    c_counters => $c_counters,
    virtual    => $virtual,
##    txn         => $logspace,
    m1     => $main01,
    m2     => $main02,
    m3     => $main03,
    flgrps => $filegroups,

    #    test        => $,
    wait_events => $waitevents_l,
  );
  my %multidata = (
    capacity   => $size,
    datafiles2 => $datafiles2,
    flgrps     => $filegroups,
  );
  if ($multidata) {
    return \%multidata;
  }
  else {
    return \%queries;
  }
}
