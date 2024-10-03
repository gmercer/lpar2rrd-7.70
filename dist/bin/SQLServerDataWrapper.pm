package SQLServerDataWrapper;

use strict;
use warnings;

use JSON;
use Data::Dumper;
use Xorux_lib qw(error read_json);
use Digest::MD5 qw(md5 md5_hex md5_base64);

my $use_sql = 0;
defined $ENV{INPUTDIR} || warn("INPUTDIR undefined, config etc/lpar2rrd.cfg probably has not been loaded ") && exit 1;

my $inputdir = $ENV{INPUTDIR};
my $home_dir = "$inputdir/data/SQLServer";
my $tmpdir   = "$inputdir/tmp";

my %type_check = (
  "virtual" => {
    "data_rw" => {
      "blks_read" => "blksrd",
    },
    "io_rw" => {
      "tup_deleted" => "tpdltd",
    },
    "io_total" => {
      "temp_bytes" => "lcks",    #
    },
    "data_total" => {
      "current_transactions" => "crrnttxn",
    },
    "latency_rw" => {
      "current_cursors" => "lcks",
    },    #x
    "latency_total" => {
      "cache_hit_ratio" => "cchhtrt",
    },
  },
  "counters" => {
    "cache_hit" => {
      "buffers_backend" => "bfrsbcknd",
    },
    "buffer_cache_hit" => {
      "checkpoints_timed" => "chckpntstmd",
    },
    "log_cache_hit" => { "autovacuum" => "atvcm", },
    "buffer"        => { "autovacuum" => "atvcm", },
    "readahead"     => { "autovacuum" => "atvcm", },
    "page_rw"       => { "autovacuum" => "atvcm", },
    "pags"          => { "autovacuum" => "atvcm", },
    "sessions"      => { "autovacuum" => "atvcm", },
    "cursors"       => { "autovacuum" => "atvcm", },
    "transactions"  => { "autovacuum" => "atvcm", },
    memory          => {
      'Free'  => 'lwlcknmd',
      'Total' => 'lwlcktrnch',
    },
  },
  "locks" => {
    "locks"     => { userlock => "hsrlck" },
    "deadlocks" => {
      relation => "arltn",
    },
  },
  "wait_events" => {
    latches_io => {
      PAGEIOLATCH_UP => 'pageioup',
    },
    latches_bfr => {
      PAGELATCH_DT => 'pagedt',
    },
    latches_nonbfr => {
      LATCH_UP => 'latchup',
    },
    "lock_events" => {
      LCK_M_X => 'LCKMX',
    },
    "events" => {
      LCK_M_X => 'LCKMX',
    },
  },
  "_event" => {
    "LWLockNamed"   => { ads => "asd", },
    "LWLockTranche" => { ads => "asd", },
    "Lock"          => { ads => "asd", },
    "BufferPin"     => { ads => "asd", }
  },
  "configuration_capacity" => {
    "size" => {
      "available" => 'available',
      "used"      => 'used',
      "log_space" => 'log_space',
      "unused"    => 'unused',
    },
  },
  "_vacuum" => {
    "phase" => {
      idle => "dl",
    }
  }
);
#############################################
# relation to links_sqlserver.json for IO
# IO       = "type" : "IO",
#
# io_total = "tabs" :  [
#         {
#            "_io_total" : "Total"
#         },
#
#
# "total"  = metric description in the graph legend
#
# "io_t"   = rrd value name
sub get_pages {
  my %pages = (
    "IO" => {
      "io_total" => {
        "total" => "io_t",
      },
      "io_rw" => {
        "read"  => "io_rd",
        "write" => "io_wr",
      },
    },
    "Data" => {
      "data_total" => {
        "total" => "data_t",
      },
      "data_rw" => {
        "read"  => "data_rd",
        "write" => "data_wr",
      },
    },
    "Latency" => {
      "latency_total" => {
        "total" => "ltnc_t",
      },
      "latency_rw" => {
        "read"  => "ltnc_rd",
        "write" => "ltnc_wr",
      },
    },
    "Buffers" => {
      "buffer" => {
        "Background writer pages/sec" => 'BGdwrpgPS',
        "Checkpoint pages/sec"        => 'ChckptpgPS',
        "Lazy writes/sec"             => 'LazywrPS',
      },
      "readahead" => {
        "Readahead pages/sec" => 'RdahdpagePS',
        "Readahead time/sec"  => 'RdahdtimePS',
      },
      "page_rw" => {
        "Page reads/sec"  => 'PagerdPS',
        "Page writes/sec" => 'PagewrPS',
      },
      "pags" => {
        "Page life expectancy"      => 'Pagelexpect',
        "Database pages"            => 'Dbpages',
        "Extension allocated pages" => 'Extnallocpg',
        "Extension free pages"      => 'Extnfreepg',
        "Target pages"              => 'Targetpages',
      },
    },
    "Memory" => {
      memory => {
        'Free'     => 'FreeMemory',
        'Total'    => 'TotalMemory',
        'Target'   => 'TargetMemory',
        'Reserved' => 'ReservedMemory',
      },
    },
    "Ratio" => {
      "cache_hit"        => { "cache hit"        => "CacheHitRat" },
      "buffer_cache_hit" => { "buffer cache hit" => "LogCacheHit" },
      "log_cache_hit"    => { "log cache hit"    => "LogCacheHit" },
    },
    "Sessions" => {
      "sessions" => {
        "User Connections"      => 'UsrCons',
        "Connection resets/sec" => 'ConresetsPS',
        "Logins/sec"            => 'LoginsPS',
        "Logouts/sec"           => 'LogoutsPS',
      },
    },
    "configuration_Capacity" => {
      "size" => {
        "available" => 'available',
        "used"      => 'used',
        "log_space" => 'log_space',
        "unused"    => 'unused',
      },
    },
    "Latches" => {
      latches_io => {
        PAGEIOLATCH_DT => 'pageiodt',
        PAGEIOLATCH_EX => 'pageioex',
        PAGEIOLATCH_KP => 'pageiokp',
        PAGEIOLATCH_NL => 'pageionl',
        PAGEIOLATCH_SH => 'pageiosh',
        PAGEIOLATCH_UP => 'pageioup',
      },
      latches_bfr => {
        PAGELATCH_DT => 'pagedt',
        PAGELATCH_EX => 'pageex',
        PAGELATCH_KP => 'pagekp',
        PAGELATCH_NL => 'pagenl',
        PAGELATCH_SH => 'pagesh',
        PAGELATCH_UP => 'pageup',
      },
      latches_nonbfr => {
        LATCH_DT => 'latchdt',
        LATCH_EX => 'latchex',
        LATCH_KP => 'latchkp',
        LATCH_NL => 'latchnl',
        LATCH_SH => 'latchsh',
        LATCH_UP => 'latchup',
      },
    },
    "Locks" => {
      "locks" => {
        'Requests/sec' => 'LockRqstsPS',
        'Waits/sec'    => 'LockWaitsPS',
        'Timeouts/sec' => 'LockTmtsPS',
      },
      "deadlocks" => {
        'Deadlocks' => 'DeadlocksPS',
      },
    },
    "SQL_query" => {
      cursors => {
        'Active cursors'        => 'Activecrsrs',
        'Cursor Requests/sec'   => 'CrsrRqstsPS',
        'Cached Cursors Counts' => 'CchdCrsrCnt',
      },
      transactions => {
        "Transactions"             => 'Txns',
        "Transactions/sec"         => 'Transaction',
        "Tracked transactions/sec" => 'Trackedtxn',
        "Write Transactions"       => 'WTxnsPS',
        "Active Transactions"      => 'ActiveTxn',
      },
    },
    "Wait_events" => {
      "events" => {
        'RSRC QUERY COMPILE'  => 'RSSMQUER',
        'SOS SCHEDULER YIELD' => 'SOSSCHED',
        'ASYNC NETWORK IO'    => 'ASYNCNET',
        'MSQL XP'             => 'MSQLXP',
        'EXECSYNC'            => 'EXECSYNC',
        'WRITE COMPLETION'    => 'WRITECOM',
        'IO COMPLETION'       => 'IOCOMPLE',
        'CXPACKET'            => 'CXPACKET',
        'WRITELOG'            => 'WRITELOG',
        'THREADPOOL'          => 'THREADPL'
      },
      "lock_events" => {
        LCK_M_BU     => 'LCKMBU',
        LCK_M_IS     => 'LCKMIS',
        LCK_M_IU     => 'LCKMIU',
        LCK_M_IX     => 'LCKMIX',
        LCK_M_RIn_NL => 'LCKMRInNL',
        LCK_M_RIn_S  => 'LCKMRInS',
        LCK_M_RIn_U  => 'LCKMRInU',
        LCK_M_RIn_X  => 'LCKMRInX',
        LCK_M_RS_S   => 'LCKMRSS',
        LCK_M_RS_U   => 'LCKMRSU',
        LCK_M_RX_S   => 'LCKMRXS',
        LCK_M_RX_U   => 'LCKMRXU',
        LCK_M_RX_X   => 'LCKMRXX',
        LCK_M_S      => 'LCKMS',
        LCK_M_SCH_M  => 'LCKMSCHM',
        LCK_M_SCH_S  => 'LCKMSCHS',
        LCK_M_SIU    => 'LCKMSIU',
        LCK_M_SIX    => 'LCKMSIX',
        LCK_M_U      => 'LCKMU',
        LCK_M_UIX    => 'LCKMUIX',
        LCK_M_X      => 'LCKMX',
      },
    }
  );

  return \%pages;
}

sub get_filepath_rrd {
  my $params = shift;

  my $type      = $params->{type};
  my $server    = $params->{uuid};
  my $host      = $params->{id};
  my $skip_acl  = $params->{skip_acl};
  my $acl_check = $params->{acl_check};
  my $filepath  = "";

  $type =~ s/configuration_//g;

  if    ( $type eq 'virtual' )                           { $filepath = "$home_dir/$server/$host/Virtual/virt.rrd"; }
  elsif ( $type eq 'capacity' )                          { $filepath = "$home_dir/$server/$host/Capacity/capacity.rrd"; }
  elsif ( $type eq 'counters' or $type eq 'locks' )      { $filepath = "$home_dir/$server/$host/Counters/counters.rrd"; }
  elsif ( $type eq 'wait_events' or $type eq 'latches' ) { $filepath = "$home_dir/$server/$host/Wait_events/wait_events.rrd"; }
  else {
    warn "Unknown rrd type $type";
    $filepath = "";
  }

  # ACL check
  if ( $acl_check && !$skip_acl ) {
    my $uuid = get_uuid( $server, $host );

    if ( !isGranted($uuid) ) {
      return;
    }
  }

  if ( defined $filepath ) {
    return $filepath;
  }
  else {
    return;
  }
}

sub isGranted {
  my $uuid = shift;

  require ACLx;
  my $acl = ACLx->new();

  return $acl->isGranted( { hw_type => 'SQLSERVER', item_id => $uuid, match => 'granted' } );
}

sub get_filepath_rrd_bpage {
  my $page   = shift;
  my $server = shift;
  my $host   = shift;
  my $type   = get_type_from_page($page);
  get_filepath_rrd( { type => $type, uuid => $server, id => $host } );
}

sub get_type_from_page {
  my $_page = shift;

  #  my %pages = %{get_pages()};

  for my $type ( keys %type_check ) {
    if ( $type_check{$type}{$_page} ) {
      return $type;
    }
  }

  return "nope";
}

sub get_uuid {
  my $host   = shift;
  my $server = shift;
  my $name   = shift;
  $name = defined $name ? $name : "label";
  my ( $can_read, $ref ) = Xorux_lib::read_json("$home_dir/_Totals/Configuration/arc_total.json");
  if ($can_read) {
    for my $hostname ( keys %{ $ref->{hostnames} } ) {
      next if ( $ref->{hostnames}->{$hostname}->{alias} ne $host );
      if ( $name eq "cluster" and $ref->{hostnames}->{$hostname}->{alias} eq $host ) {
        return $hostname;
      }
      for my $db ( keys %{ $ref->{hostnames}->{$hostname}->{_dbs} } ) {
        if ( $ref->{hostnames}->{$hostname}->{_dbs}->{$db}->{$name} eq "$server" ) {
          return $db;
        }
      }
    }
  }
  else {
    warn "Couldn't open $home_dir/_Totals/Configuration/arc_total.json";
    return "";
  }
}

sub get_alias {
  my $db = shift;
  my ( $can_read, $ref ) = Xorux_lib::read_json("$home_dir/_Totals/Configuration/arc_total.json");
  if ($can_read) {
    if ( $ref->{hostnames}->{$db} ) {
      return $ref->{hostnames}->{$db}->{alias};
    }
    for my $hostname ( keys %{ $ref->{hostnames} } ) {
      if ( $ref->{hostnames}->{$hostname}->{_dbs}->{$db} ) {
        return $ref->{hostnames}->{$hostname}->{alias};
      }
    }
  }
  else {
    warn "Couldn't open $home_dir/_Totals/Configuration/arc_total.json";
    return "";
  }
}

sub get_dbname {
  my $dbid = shift;
  my ( $can_read, $ref ) = Xorux_lib::read_json("$home_dir/_Totals/Configuration/arc_total.json");
  if ($can_read) {
    if ( $ref->{hostnames}->{$dbid} ) {
      return $ref->{hostnames}->{$dbid}->{label};
    }
    for my $hostname ( keys %{ $ref->{hostnames} } ) {
      if ( $ref->{hostnames}->{$hostname}->{_dbs}->{$dbid} ) {
        return $ref->{hostnames}->{$hostname}->{_dbs}->{$dbid}->{label};
      }
    }
  }
  else {
    warn "Couldn't open $home_dir/_Totals/Configuration/arc_total.json";
    return "";
  }
}

sub get_driver {
  my $odbc_inst   = "/etc/odbcinst.ini";
  my $driver_file = "$home_dir/sqlserver_driver.txt";
  my $_driver     = "";
  if ( -e $driver_file ) {
    open( FHR, "<", "$driver_file" );
    foreach my $line (<FHR>) {
      if ( $line =~ /ODBC Driver .* for SQL Server/ ) {
        $_driver = "$line";
        close FHR;
        return $_driver;
      }
    }
    close FHR;
    unlink($driver_file);
    return "err-incodriver";
  }
  elsif ( -e $odbc_inst ) {
    open( FHR, "<", "$odbc_inst" );
    foreach my $line (<FHR>) {
      if ( $line =~ /ODBC Driver .* for SQL Server/ ) {
        $line =~ s/\[/\{/g;
        $line =~ s/\]/\}/g;
        $_driver = "$line";

        unlink($driver_file);
        open my $fh, '>', $driver_file;
        print $fh $_driver;
        close $fh;
        close FHR;

        return $_driver;
      }
    }
    close FHR;
    return "err-driverne";
  }
  else {
    return "err-instne";
  }
}

sub isdigit {
  my $digit = shift;

  my $digit_work = $digit;
  $digit_work =~ s/[0-9]//g;
  $digit_work =~ s/\.//;

  #$digit_work =~ s/\-//;

  if ( length($digit_work) == 0 ) {

    # is a number
    return 1;
  }

  return 0;
}

sub basename {
  my $full      = shift;
  my $separator = shift;
  my $out       = "";

  #my $length = length($full);
  if ( defined $separator and defined $full and index( $full, $separator ) != -1 ) {
    $out = substr( $full, length($full) - index( reverse($full), $separator ), length($full) );
    return $out;
  }
  return $full;
}

sub md5_string {
  my $data = shift;
  my $out  = md5_hex($data);

  return $out;
}

sub get_arc {
  if ( -e "$home_dir/_Totals/Configuration/arc_total.json" ) {
    my ( $can_read, $ref ) = Xorux_lib::read_json("$home_dir/_Totals/Configuration/arc_total.json");
    if ($can_read) {
      return $ref;
    }
    else {
      return "0";
    }
  }
  return "0";
}

sub conf_files {
  my $wrkdir   = shift;
  my $type     = shift;
  my $alias    = shift;
  my $host_url = shift;

  #$type = remove_subs($type);

  my @conf_files;

  if ( $type eq "configuration_Cluster" ) {
    @conf_files = ( get_dir( "main", $alias ) );
  }
  elsif ( $type eq "configuration_Capacity" ) {
    @conf_files = ( " ", get_dir( "datafiles2", $alias, $host_url ), get_dir( "flgrps", $alias, $host_url ) );
  }

  return \@conf_files;
}

sub get_dir {
  my $type  = shift;
  my $alias = shift;
  my $uuid  = shift;

  my $conf_dir = "$home_dir/$alias/Configuration";

  if ( $type eq "main" ) {
    return "$conf_dir/main.html";
  }
  elsif ( $type eq "datafiles2"
    or $type eq "flgrps" )
  {
    return "$conf_dir/$uuid-$type.html";
  }
  else {
    return "err";
  }
}

sub get_items {
  my %params = %{ shift() };
  my @result;

  my $arc = get_arc();
  if ( defined $params{item_type} or $arc == 0 or !defined $arc->{ $params{item_type} } ) {
    my @empty = [];
    return \@empty;
  }

  my %arc = %{$arc};
  if ( $params{item_type} eq "hostnames" ) {
    @result = keys %{ $arc{ $params{item_type} } };
  }
  elsif ( $params{item_type} eq "dbs" ) {
    for my $hostname ( keys %{ $arc{hostnames} } ) {
      push( @result, keys %{ $arc{hostnames}{$hostname}{"_$params{item_type}"} } );
    }
  }

  return \@result;
}

sub graph_legend {
  my $page = shift;

  #  $page =~ s/_/ /g;

  #types have tabs that are defined in links_*.json
  #This defines rules for graphs in each tab
  my %legend = (
    'default' => {
      'denom'      => '1',
      'brackets'   => '',
      'header'     => 'not_defined',
      'value'      => 'Total',
      'rrd_vname'  => '',
      'graph_type' => 'LINE1',
      'v_label'    => 'not_defined',
      'decimals'   => '1'
    },
    'io_total' => {
      'denom'      => '1',
      'brackets'   => '[iops]',
      'header'     => 'Total IO',
      'value'      => 'iops',
      'graph_type' => 'LINE1',
      'v_label'    => 'IOPS',
      'decimals'   => '0'

    },
    'io_rw' => {
      'denom'      => '1',
      'brackets'   => '[iops]',
      'header'     => 'Read/Write IO',
      'value'      => 'iops',
      'graph_type' => 'AREA',
      'v_label'    => 'IOPS',
      'decimals'   => '0'

    },
    'data_total' => {
      'denom'      => '1000',
      'brackets'   => '[MB/s]',
      'header'     => 'Total Data',
      'value'      => 'MB/s',
      'graph_type' => 'LINE1',
      'v_label'    => 'MB/s',
      'decimals'   => '2'

    },
    'data_rw' => {
      'denom'      => '1000',
      'brackets'   => '[MB/s]',
      'header'     => 'Read/Write Data',
      'value'      => 'MB/s',
      'graph_type' => 'AREA',
      'v_label'    => 'MB/s',
      'decimals'   => '2'

    },
    'size' => {
      'denom'      => '1000',
      'brackets'   => '[GB]',
      'header'     => 'Capacity',
      'value'      => 'GB',
      'graph_type' => 'AREA',
      'v_label'    => 'Gigabytes',
      'decimals'   => '1'

    },
    'latency_total' => {
      'denom'      => '1',
      'brackets'   => '[ms]',
      'header'     => 'Total Latency',
      'value'      => 'ms',
      'graph_type' => 'LINE1',
      'v_label'    => 'Latency',
      'decimals'   => '2'

    },
    'latency_rw' => {
      'denom'      => '1',
      'brackets'   => '[ms]',
      'header'     => 'Read/Write Latency',
      'value'      => 'ms',
      'graph_type' => 'LINE1',
      'v_label'    => 'Latency',
      'decimals'   => '2'

    },
    'cache_hit' => {
      'denom'      => '1',
      'brackets'   => '[%]',
      'header'     => 'Cache hit ratio',
      'value'      => '%',
      'graph_type' => 'LINE1',
      'v_label'    => 'Percentage',
      'decimals'   => '0'

    },
    'buffer_cache_hit' => {
      'denom'      => '1',
      'brackets'   => '[%]',
      'header'     => 'Buffer Cache hit ratio',
      'value'      => '%',
      'graph_type' => 'LINE1',
      'v_label'    => 'Percentage',
      'decimals'   => '0'

    },
    'log_cache_hit' => {
      'denom'      => '1',
      'brackets'   => '[%]',
      'header'     => 'Log Cache hit ratio',
      'value'      => '%',
      'graph_type' => 'LINE1',
      'v_label'    => 'Percentage',
      'decimals'   => '0'

    },
    "buffer" => {
      'denom'      => '1',
      'brackets'   => '',
      'header'     => 'Buffer',
      'value'      => '%',
      'graph_type' => 'LINE1',
      'v_label'    => '',
      'decimals'   => '1'

    },
    "readahead" => {
      'denom'      => '1',
      'brackets'   => '',
      'header'     => 'Readahead',
      'value'      => '%',
      'graph_type' => 'LINE1',
      'v_label'    => '',
      'decimals'   => '1'

    },
    "page_rw" => {
      'denom'      => '1',
      'brackets'   => '',
      'header'     => 'Page R/W',
      'value'      => '',
      'graph_type' => 'LINE1',
      'v_label'    => '',
      'decimals'   => '1'

    },
    "pags" => {
      'denom'      => '1',
      'brackets'   => '',
      'header'     => 'Pages',
      'value'      => '',
      'graph_type' => 'LINE1',
      'v_label'    => '',
      'decimals'   => '1'

    },
    "sessions" => {
      'denom'      => '1',
      'brackets'   => '',
      'header'     => 'Sessions',
      'value'      => '%',
      'graph_type' => 'LINE1',
      'v_label'    => '',
      'decimals'   => '0'

    },
    "cursors" => {
      'denom'      => '1',
      'brackets'   => '',
      'header'     => 'Cursors',
      'value'      => '%',
      'graph_type' => 'LINE1',
      'v_label'    => '',
      'decimals'   => '0'

    },
    "transactions" => {
      'denom'      => '1',
      'brackets'   => '',
      'header'     => 'Transactions',
      'value'      => '%',
      'graph_type' => 'LINE1',
      'v_label'    => '',
      'decimals'   => '0'

    },
    "memory" => {
      'denom'      => '1000',
      'brackets'   => '[GB]',
      'header'     => 'Memory',
      'value'      => 'MB',
      'graph_type' => 'LINE1',
      'v_label'    => '',
      'decimals'   => '1'

    },
    "locks" => {
      'denom'      => '1',
      'brackets'   => '',
      'header'     => 'Locks',
      'value'      => '%',
      'graph_type' => 'LINE1',
      'v_label'    => '',
      'decimals'   => '1'

    },
    "deadlocks" => {
      'denom'      => '1',
      'brackets'   => '',
      'header'     => 'Deadlocks',
      'value'      => '%',
      'graph_type' => 'LINE1',
      'v_label'    => '',
      'decimals'   => '1'

    },
    latches_io => {
      'denom'      => '1',
      'brackets'   => '[ms]',
      'header'     => 'IO Latches',
      'value'      => '%',
      'graph_type' => 'LINE1',
      'v_label'    => 'Milliseconds',
      'decimals'   => '2'

    },
    latches_bfr => {
      'denom'      => '1',
      'brackets'   => '[ms]',
      'header'     => 'Buffer Latches',
      'value'      => '%',
      'graph_type' => 'LINE1',
      'v_label'    => 'Milliseconds',
      'decimals'   => '2'

    },
    latches_nonbfr => {
      'denom'      => '1',
      'brackets'   => '[ms]',
      'header'     => 'Non-Buffer Latches',
      'value'      => '%',
      'graph_type' => 'LINE1',
      'v_label'    => 'Milliseconds',
      'decimals'   => '2'

    },
    events => {
      'denom'      => '1',
      'brackets'   => '[ms]',
      'header'     => 'Events',
      'value'      => '%',
      'graph_type' => 'LINE1',
      'v_label'    => 'Milliseconds',
      'decimals'   => '2'

    },
    lock_events => {
      'denom'      => '1',
      'brackets'   => '[ms]',
      'header'     => 'Lock events',
      'value'      => '%',
      'graph_type' => 'LINE1',
      'v_label'    => 'Milliseconds',
      'decimals'   => '2'

    }
  );

  if ( $legend{$page} ) {
    return $legend{$page};
  }
  else {
    return $legend{default};
  }
}

1;
