package Db2DataWrapper;

use strict;
use warnings;

use JSON;
use Data::Dumper;
use Xorux_lib qw(error read_json);
use Digest::MD5 qw(md5 md5_hex md5_base64);

defined $ENV{INPUTDIR} || warn("INPUTDIR undefined, config etc/lpar2rrd.cfg probably has not been loaded ") && exit 1;

my $inputdir = $ENV{INPUTDIR};
my $home_dir = "$inputdir/data/DB2";
my $tmpdir   = "$inputdir/tmp";

sub get_pages {
  my $metric_type = shift;
  my %pages = (
    'Agents' => {
      'Agents' => {
        'Agents top' =>'AGENTSTOP', 
        'Pooled' => 'ASSOCAGNT',
        'Associated' => 'POOLEDAGNT', 
        'Coordinated' => 'COORDAGNT',
        'Registered' => 'AGENTSREGT',
        'Idle' => 'IDLEAGENTS',
        'Stolen' => 'AGENTSSTLN',
       }, 
    }, 
    'Locks' => {
      'Locks' => {
        'Held' => 'LCKSHELD',
        'Waiting' => 'LCKSWAITING',
        'Escals' => 'LCKESCALS',
        'Timeouts' => 'LCKTMOUTS',
       }, 
    
      'Deadlocks' => {
        'Deadlocks' => 'DEADLOCKS',
      }, 
    }, 
    'IO' => {
      'io_read' => {
        'Logical' => 'LOGICALRD',
        'Physical' => 'PHYSICALRD',
        'Direct' => 'DIRECTRDS',
      }, 
      'io_write' => {
        'Writes' => 'WRITES',
        'Direct writes' => 'DIRECTWRTS',
      }, 
     }, 
    'Latency' => {
      'latency_direct' => {
        'Direct read time' => 'DIRECTRDT',
        'Direct write time' => 'DIRECTWRT',
      }, 
      'latency_pool' => {
        'Pool read time' => 'POOLREADT',
        'Pool write time' => 'POOLWRITETM',
      }, 
      'latency_log' => {
        'Log disk' => 'LOGDISKWT',
      },    }, 
    'Rows' => {
      'rows_t' => {
        'Read' => 'ROWREAD',
        'Returned' => 'ROWRETURNED',
        'Updated' => 'ROWUPDATED', 
        'Deleted' => 'ROWDELETED',
        'Inserted' => 'ROWINSERTED',
        'Modified' => 'ROWMODIFIED',
       }, 
      'rows_int' => {
        'Deleted' => 'INTRDELETED',
        'Inserted' => 'INTRINSERT',
        'Updated' => 'INTRUPDATED',
       }, 
      'rows_fed' => {
        'Returned' => 'FEDRRETURN',
        'Read' => 'FEDRREAD',
        'Updated' => 'FEDRUPDAT',
        'Deleted' => 'FEDRDELET',
        'Inserted' => 'FEDRINSERT',
      }, 
    }, 
    'Network' => {
      'network_remote' => {                                               
        'TCPIP send' => 'TCPIPSENDVL',
        'TCPIP recv' => 'TCPIPRECVVL',
      }, 
      'network_local' => {
        'IPC send' => 'IPCSENDVOL',
        'IPC recv' => 'IPCRECVVOL',
      }, 
      'network_fcm' => {      
        'FCM send' => 'FCMSENDVOL',
        'FCM recv' => 'FCMRECVVOL',
      }, 
    }, 
    'SQL_query' => {
      'sql_comp' => {                                                                      
        'cache inserts' => 'PKGINSERTS',   
        'cache lookups' => 'PKGLOOKUPS',
      }, 
      'sql_txn' => {
        'commits' => 'COMMITS',
        'rollbacks' => 'ROLLBACKS',
      }, 
    }, 
    'Waits' => {
      'wait_total' => {
        'Pool read' => 'POOLREADT',      
        'Pool write' => 'POOLWRITETM',     
        'Direct read' => 'DIRECTRDT',    
        'Direct write' => 'DIRECTWRT',   
        'Log disk' => 'LOGDISKWT',  
        'Tcpip send' => 'TCPIPSENDWT',
        'Tcpip recv' => 'TCPIPRECVWT',
        'Ipc send' => 'IPCSENDWT',
        'Ipc recv' => 'IPCRECVWT',
        'Fcm send' => 'FCMSENDWT',
        'Fcm recv' => 'FCMRECVWT',
        'Cf' => 'CFWAITTIME',
        #'Client idle' => 'CLIENTIDLWT',
        'Lock' => 'LOCKWT',        
        'Agent' => 'AGENTWT',
        'Wlm queue total' =>   'WLMQUEUET',
      },
      'wait_io' => {         
        'Pool read' => 'POOLREADT',      
        'Pool write' => 'POOLWRITETM',     
        'Direct read' => 'DIRECTRDT',    
        'Direct write' => 'DIRECTWRT',   
        'Log disk' => 'LOGDISKWT',  
      },    
      'wait_net' => {          
        'Tcpip send' => 'TCPIPSENDWT',
        'Tcpip recv' => 'TCPIPRECVWT',
        'Ipc send' => 'IPCSENDWT',
        'Ipc recv' => 'IPCRECVWT',
        'Fcm send' => 'FCMSENDWT',
        'Fcm recv' => 'FCMRECVWT',
      }, 
      'wait_msc' => {  
        'CF' => 'CFWAITTIME',
        #'Client idle' => 'CLIENTIDLWT',
        'Lock' => 'LOCKWT',        
        'Agent' => 'AGENTWT',
        'WLM queue total' =>   'WLMQUEUET',
      },
    },
    'Ratio' => {
      'ratio' => {                                                                      
        'Cache hit' => 'RATIOCACHE',   
        'buffer hit' => 'RATIOBUFFER',
        'CPU time' => 'RATIOCPUT',
        'Hit ratio' => 'RATINLOG',
      },
    },
    'Session' => {
       'session' => {                                                                      
         'Max conns' => 'CONNSTOP',
         'Conns/s' => 'TOTALCONS',
         'Second conns/s' => 'TSECCONS',
         'Current conns' => 'CURCONS',
      },
    } 
  );
  if (defined $metric_type){
    return $pages{$metric_type};
  }else{
    return \%pages;
  }
}
sub get_lastperiod_metrics {
    my %raw_metrics = (
      'NUM_LOCKS_HELD'     => "1",
      'NUM_LOCKS_WAITING'  => "1",
      'DEADLOCKS'          => "1",
      'LOCK_ESCALS'        => "1",
      'LOCK_TIMEOUTS'      => "1",
    );

  return \%raw_metrics;
}


sub get_raw_metrics {
    my %raw_metrics = (
      'AGENTS_TOP'         => "1",
      'TOTAL_CONNECTIONS'  => "1",
      'NUM_POOLED_AGENTS'  => "1",
      'NUM_ASSOC_AGENTS'   => "1",
      'NUM_COORD_AGENTS'   => "1",
      'AGENTS_REGISTERED'  => "1",
      'IDLE_AGENTS'        => "1",
      'AGENTS_STOLEN'      => "1",
      'APPLS_CUR_CONS'     => "1",
      'CONNECTIONS_TOP'    => "1",
      'TOTAL_SEC_CONS'     => "1",
    );

  return \%raw_metrics;
}

sub get_filepath_rrd {
  my $params = shift;

  my $type      = $params->{type};
  my $server    = $params->{uuid};
  my $host      = $params->{id};
  my $skip_acl  = $params->{skip_acl};
  my $acl_check = $params->{acl_check};
  my $filepath  = "";

  if    ( $type eq 'members' ) { $filepath = "$home_dir/$server/$type/$host/data.rrd"; }
  elsif ( $type eq 'bp' )      { $filepath = "$home_dir/$server/$type/$host/data.rrd"; }
  elsif ( $type eq '_vacuum' ) { $filepath = "$home_dir/$server/$host/Vacuum/vacuum.rrd"; }
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

  return $acl->isGranted( { hw_type => 'DB2', item_id => $uuid, match => 'granted' } );
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

sub get_filepath_rrd_bpage {
  my $page   = shift;
  my $server = shift;
  my $host   = shift;
  my $type   = get_type_from_page($page);
  get_filepath_rrd( { type => $type, uuid => $server, id => $host } );
}

sub get_type {
  my $type_checker = shift;

  if ($type_checker eq "BUFFERPOOL"){
    return "bp";
  }else{
    return "members";
  }
}

sub get_type_from_page {
  my $page  = shift;
  my %pages = %{ get_pages() };

  for my $metric_type (%pages){
    if ($pages{$metric_type}{$page}){
      return $metric_type;
    }
  }
  return "not_found";
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

sub get_alias {
  my $db = shift;

  my ( $can_read, $ref ) = Xorux_lib::read_json("$home_dir/_Totals/Configuration/arc_total.json");
  if ($can_read) {
    if ( $ref->{hostnames}->{$db} ) {
      return $ref->{hostnames}->{$db}->{alias};
    }
    for my $hostname ( keys %{ $ref->{hostnames} } ) {
      if ( $ref->{hostnames}->{$hostname}->{_dbs}->{$db} or $ref->{hostnames}->{$hostname}->{_bps}->{$db}) {
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
      if ( $ref->{hostnames}->{$hostname}->{_dbs}->{$dbid}) {
        return $ref->{hostnames}->{$hostname}->{_dbs}->{$dbid}->{label};
      }elsif($ref->{hostnames}->{$hostname}->{_bps}->{$dbid}){
        return $ref->{hostnames}->{$hostname}->{_bps}->{$dbid}->{label};
      }
    }
  }
  else {
    warn "Couldn't open $home_dir/_Totals/Configuration/arc_total.json";
    return "";
  }
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
    @conf_files = ( get_dir( "main", $alias ), get_dir( "size", $alias ), get_dir( "member", $alias ));
  }
  elsif ( $type eq "member" ) {
    @conf_files = ( get_dir( "member", $alias, $host_url ));
  }

  return \@conf_files;
}

sub get_dir {
  my $type  = shift;
  my $alias = shift;
  my $uuid  = shift;

  my $conf_dir = "$home_dir/$alias/Configuration";

  my %known_types = (
     size   => 1,
     member => 1,
     main   => 1,
  );

  if ( defined $known_types{$type} ){
    return "$conf_dir/$type.html";
    #return "$conf_dir/$uuid-$type.html";
  }
  else {
    return "err";
  }
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
      for my $db ( keys %{ $ref->{hostnames}->{$hostname}->{_bps} } ) {
        if ( $ref->{hostnames}->{$hostname}->{_bps}->{$db}->{$name} eq "$server" ) {
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

#takes initial values in bytes
sub get_fancy_value {
  my $value           = shift;
  my $step            = 1024;
  my @supported_types = ( $step**3, $step**4, $step**5 );
  my @supported_names = ( "GiB", "TiB", "PiB" );
  my $counter         = 0;

  foreach my $step_type (@supported_types) {
    my $decimals  = $supported_names[$counter] eq "MiB" ? 0 : 1;
    my $converted = sprintf( "%.".$decimals."f", $value / $step_type );
    if ( $converted >= $step ) {
      if ( $counter >= $#supported_types ) {
        return "$converted $supported_names[$counter]";
      }
      else {
        $counter++;
        next;
      }
    }
    else {
      return "$converted $supported_names[$counter]";
    }
  }
}

sub graph_legend {
  my $page = shift;

   if( $page =~/wait_/){
     $page = "wait_";
   }
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
    'session' => {
      'denom'      => '1',
      'brackets'   => '',
      'header'     => 'Sessions',
      'value'      => 'Total',
      'rrd_vname'  => '',
      'graph_type' => 'LINE1',
      'v_label'    => 'Sessions',
      'decimals'   => '0'
    },
    'Agents' => {
      'denom'      => '1',
      'brackets'   => '[#]',
      'header'     => 'Agents',
      'value'      => '#',
      'graph_type' => 'LINE1',
      'v_label'    => 'count',
      'decimals'   => '0'

    },
    'Locks' => {
      'denom'      => '1',
      'brackets'   => '[#]',
      'header'     => 'Locks',
      'value'      => '#',
      'graph_type' => 'LINE1',
      'v_label'    => 'In the last 5 minutes',
      'decimals'   => '0'

    },
    'Deadlocks' => {
      'denom'      => '1',
      'brackets'   => '[#]',
      'header'     => 'Deadlocks',
      'value'      => '#',
      'graph_type' => 'LINE1',
      'v_label'    => 'In the last 5 minutes',
      'decimals'   => '0'

    },
    'io_read' => {
      'denom'      => '1',
      'brackets'   => '[IOPS]',
      'header'     => 'Read',
      'value'      => 'IOPS',
      'graph_type' => 'LINE1',
      'v_label'    => 'IOPS',
      'decimals'   => '0'

    },
    'io_write' => {
      'denom'      => '1',
      'brackets'   => '[IOPS]',
      'header'     => 'Write',
      'value'      => 'IOPS',
      'graph_type' => 'LINE1',
      'v_label'    => 'IOPS',
      'decimals'   => '0'
    },
    'latency_direct' => {
      'denom'      => '1',
      'brackets'   => '[ms]',
      'header'     => 'Read/Write Latency',
      'value'      => 'ms',
      'graph_type' => 'LINE1',
      'v_label'    => 'Milliseconds',
      'decimals'   => '2'

    },
    'latency_pool' => {
      'denom'      => '1',
      'brackets'   => '[ms]',
      'header'     => 'Read/Write Latency',
      'value'      => 'ms',
      'graph_type' => 'LINE1',
      'v_label'    => 'Milliseconds',
      'decimals'   => '2'

    },
    'latency_log' => {
      'denom'      => '1',
      'brackets'   => '[ms]',
      'header'     => 'Read/Write Latency',
      'value'      => 'ms',
      'graph_type' => 'LINE1',
      'v_label'    => 'Milliseconds',
      'decimals'   => '2'

    },
    'cache_log' => {
      'denom'      => '1',
      'brackets'   => '[%]',
      'header'     => 'Cache hit ratio',
      'value'      => '%',
      'graph_type' => 'LINE1',
      'v_label'    => 'Percentage',
      'decimals'   => '0'

    },
    'rows_t' => {
      'denom'      => '1',
      'brackets'   => '[#]',
      'header'     => 'Rows',
      'value'      => '#',
      'graph_type' => 'LINE1',
      'v_label'    => 'rows',
      'decimals'   => '0'

    },
    'rows_int' => {
      'denom'      => '1',
      'brackets'   => '[#]',
      'header'     => 'Rows',
      'value'      => '#',
      'graph_type' => 'LINE1',
      'v_label'    => 'rows',
      'decimals'   => '0'

    },
    'rows_fed' => {
      'denom'      => '1',
      'brackets'   => '[#]',
      'header'     => 'Rows',
      'value'      => '#',
      'graph_type' => 'LINE1',
      'v_label'    => 'rows',
      'decimals'   => '0'

    },
    'ratio' => {
      'denom'      => '1',
      'brackets'   => '[%]',
      'header'     => 'Ratio',
      'value'      => '%',
      'graph_type' => 'LINE1',
      'v_label'    => 'Percentage',
      'decimals'   => '0'

    },
    'ratio_buffer' => {
      'denom'      => '1',
      'brackets'   => '[%]',
      'header'     => 'Buffer Cache hit ratio',
      'value'      => '%',
      'graph_type' => 'LINE1',
      'v_label'    => 'Percentage',
      'decimals'   => '0'

    },
    'ratio_cpu' => {
      'denom'      => '1',
      'brackets'   => '[%]',
      'header'     => 'CPU wait ratio',
      'value'      => '%',
      'graph_type' => 'LINE1',
      'v_label'    => 'Percentage',
      'decimals'   => '0'

    },
    'ratio_log' => {
      'denom'      => '1',
      'brackets'   => '[%]',
      'header'     => 'Log hit ratio',
      'value'      => '%',
      'graph_type' => 'LINE1',
      'v_label'    => 'Percentage',
      'decimals'   => '0'

    },
    'network_remote' => {
      'denom'      => '1000',
      'brackets'   => '[MB/s]',
      'header'     => 'Remote',
      'value'      => 'MB/s',
      'graph_type' => 'AREA',
      'v_label'    => 'MB/s',
      'decimals'   => '2'

    },
    'network_local' => {
      'denom'      => '1000',
      'brackets'   => '[MB/s]',
      'header'     => 'Local clients',
      'value'      => 'MB/s',
      'graph_type' => 'AREA',
      'v_label'    => 'MB/s',
      'decimals'   => '2'

    },
    'network_fcm' => {
      'denom'      => '1000',
      'brackets'   => '[MB/s]',
      'header'     => 'FCM',
      'value'      => 'MB/s',
      'graph_type' => 'AREA',
      'v_label'    => 'MB/s',
      'decimals'   => '2'
    },
    'sql_txn' => {
      'denom'      => '1',
      'brackets'   => '[#]',
      'header'     => 'Transaction',
      'value'      => '#',
      'graph_type' => 'AREA',
      'v_label'    => 'Transactions',
      'decimals'   => '0'

    },
    'sql_comp' => {
      'denom'      => '1',
      'brackets'   => '[#]',
      'header'     => 'Compilation',
      'value'      => '#',
      'graph_type' => 'LINE1',
      'v_label'    => 'Compilations',
      'decimals'   => '0'

    },
    'wait_' => {
      'denom'      => '1',
      'brackets'   => '[ms]',
      'header'     => 'Wait time',
      'value'      => 'ms',
      'graph_type' => 'LINE1',
      'v_label'    => 'Milliseconds',
      'decimals'   => '2'

    },

  );

  if ( $legend{$page} ) {
    return $legend{$page};
  }
  else {
    return $legend{default};
  }
}
