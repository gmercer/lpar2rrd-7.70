# OracleDBDataWrapperOOP.pm
# interface for accessing OracleDB data:

package OracleDBDataWrapperOOP;

use strict;
use warnings;

use Data::Dumper;
use JSON;
use Xorux_lib;
use Digest::MD5 qw(md5 md5_hex md5_base64);

# TODO introduce toggle between JSON and SQLite backends
my $use_sql = 0;    # defined $ENV{XORMON};

defined $ENV{INPUTDIR} || warn( localtime() . ': INPUTDIR undefined, config etc/lpar2rrd.cfg probably has not been loaded ' . __FILE__ . ':' . __LINE__ ) && exit 1;

my $inputdir   = $ENV{INPUTDIR};
my $wrkdir     = "$inputdir/data";
my $tmpdir     = "$inputdir/tmp";
my $odb_dir    = "$inputdir/data/OracleDB";
my $totals_dir = "$odb_dir/Totals";

################################################################################

sub new {
  my ( $self, $args ) = @_;

  my $o = {};

  #  $o->{configuration} = get_arc();
  #  $o->{groups} = get_groups();
  $o->{acl_check} = ( defined $args->{acl_check} ) ? $args->{acl_check} : 0;
  if ( $o->{acl_check} ) {
    require ACLx;
    $o->{aclx} = ACLx->new();
  }
  bless $o;

  return $o;
}

#List of metrics that are used in graphs for given type(Ratio)
my %hsh = (
  'Ratio' => {
    'Memory Sorts Ratio'       => 'MmrSrts',
    'Database Wait Time Ratio' => 'DbWtTm',
    'PGA Cache Hit'            => 'PGACchHt',
    'Soft Parse Ratio'         => 'SftPrs',
    'Database CPU Time Ratio'  => 'DbCPUTm',
    'Buffer Cache Hit Ratio'   => 'BffrCchHt'
  },
  'Session_info' => {
    'Current Logons Count'     => 'CrntLgnsCnt',
    'Logons Per Sec'           => 'LgnsPS',
    'Active Serial Sessions'   => 'ActSrlSsion',
    'Active Parallel Sessions' => 'ActPrllSsion',
    'Average Active Sessions'  => 'AvgActSsion'
  },
  'Network'   => { 'Network Traffic Volume Per Sec' => 'NetTrfcVlPS' },
  'SQL_query' => {
    'Executions Per Sec'         => 'ExecsPS',
    'Hard Parse Count Per Sec'   => 'HrdPrsCntPS',
    'Current Open Cursors Count' => 'CntOpnCrs',
    'User Commits Per Sec'       => 'UsrComtsPS',
    'User Transaction Per Sec'   => 'UsrTxnPS',
    'Open Cursors Per Sec'       => 'OpnCrsPS'
  },
  'Data_rate' => {
    'Physical Read Bytes Per Sec'  => 'PhysReadBPS',
    'Physical Writes Per Sec'      => 'PhysWritePS',
    'IO Megabytes per Second'      => 'IOMbPS',
    'IO Requests per Second'       => 'IORqstPS',
    'Logical Reads Per Sec'        => 'LgclReadPS',
    'Redo Generated Per Sec'       => 'RdoGenPS',
    'Physical Reads Per Sec'       => 'PhysReadPS',
    'Physical Write Bytes Per Sec' => 'PhysWriteBPS',
    'DB Block Changes Per Sec'     => 'DBBlckChngPS'
  },
  'CPU_info' => {
    'CPU Usage Per Txn'    => 'CPUusgPT',
    'Host CPU Utilization' => 'HstCPUutil',
    'CPU Usage Per Sec'    => 'CPUusgPS'
  },
  'Cache' => {
    'Global Cache Blocks Lost'              => 'GCBlckLst',
    'Global Cache Average CR Get Time'      => 'GCAvgCRGtTm',
    'Global Cache Average Current Get Time' => 'GCAvgCtGtTm',
    'GC CR Block Received Per Second'       => 'GCCRBlckRcPS',
    'GC Current Block Received Per Second'  => 'GCCtBlckRcPS',
    'Cell Physical IO Interconnect Bytes'   => 'CPIOIntB',
    'Global Cache Blocks Corrupted'         => 'GCBlckCrrptd',
    'GC Avg CR Block receive ms'            => 'AvgCRBlkrc',
    'GC Avg CUR Block receive ms'           => 'AvgCURBlkrc'
  },
  'Interconnect' => {
    'Cell Physical IO Interconnect Bytes' => 'CPIOIntB',
  },
  'Disk_latency' => {
    'DB files read latency'   => 'flsrltnc',
    'db file scattered read'  => 'dbflscttrdr',
    'db file sequential read' => 'flsqentlr',
    'db file single write'    => 'flsnglw',
    'db file parallel write'  => 'flprlllw',
    'log file sync'           => 'lgflsnc',
    'log file single write'   => 'lgflsnglw',
    'log file parallel write' => 'lgflprlllw',
    'flashback log file sync' => 'flshbcklgfl',
    'DB files write latency'  => 'flswltnc',
    'LOG files write latency' => 'LGflswltnc',
  },
  'viewone' => {
    'gc cr block 2-way'      => 'crblocktwy',
    'gc current block 2-way' => 'crntblcktwy',
    'gc cr block 3-way'      => 'crblckthwy',
    'gc current block 3-way' => 'crntblckthwy',
  },
  'viewtwo' => {
    'gc cr block busy'           => 'crblckbs',
    'gc cr block congested'      => 'crblckcngstd',
    'gc cr grant 2-way'          => 'crgrnttwy',
    'gc cr grant congested'      => 'crgrntcngstd',
    'gc current block busy'      => 'crntblckbs',
    'gc current block congested' => 'crntblckcngs',
    'gc current grant 2-way'     => 'crntgrnttwy',
    'gc current grant congested' => 'crntgrntcstd',
  },
  'viewthree' => {
    'gc cr block lost'              => 'crblcklst',
    'gc current block lost'         => 'crntblcklst',
    'Global Cache Blocks Lost'      => 'GCBlckLst',
    'Global Cache Blocks Corrupted' => 'GCBlckCrrptd',
    'gc cr failure'                 => 'crflr',
    'gc current retry'              => 'crntrtr',
  },
  'viewfour' => {
    'gc current split'               => 'crntsplt',
    'gc current multi block request' => 'crntmltrqst',
    'gc current grant busy'          => 'crntgrntbs',
    'gc cr disk read'                => 'crdskr',
    'gc cr multi block request'      => 'crmtblckrqst',
    'gc buffer busy acquire'         => 'bfrbsacqr',
    'gc buffer busy release'         => 'bfrbsrls',
  },
  'viewfive' => {
    'gc remaster' => 'gcrmstr',
  },
  'RAC' => {
    'gc cr block 2-way'                     => 'crblocktwy',
    'gc current block 2-way'                => 'crntblcktwy',
    'gc cr block 3-way'                     => 'crblckthwy',
    'gc current block 3-way'                => 'crntblckthwy',
    'gc cr block busy'                      => 'crblckbs',
    'gc cr block congested'                 => 'crblckcngstd',
    'gc cr grant 2-way'                     => 'crgrnttwy',
    'gc cr grant congested'                 => 'crgrntcngstd',
    'gc current block busy'                 => 'crntblckbs',
    'gc current block congested'            => 'crntblckcngs',
    'gc current grant 2-way'                => 'crntgrnttwy',
    'gc current grant congested'            => 'crntgrntcstd',
    'gc cr block lost'                      => 'crblcklst',
    'gc current block lost'                 => 'crntblcklst',
    'Global Cache Blocks Lost'              => 'GCBlckLst',
    'Global Cache Blocks Corrupted'         => 'GCBlckCrrptd',
    'gc cr failure'                         => 'crflr',
    'gc current retry'                      => 'crntrtr',
    'gc current split'                      => 'crntsplt',
    'gc current multi block request'        => 'crntmltrqst',
    'gc current grant busy'                 => 'crntgrntbs',
    'gc cr disk read'                       => 'crdskr',
    'gc cr multi block request'             => 'crmtblckrqst',
    'gc buffer busy acquire'                => 'bfrbsacqr',
    'gc buffer busy release'                => 'bfrbsrls',
    'gc remaster'                           => 'gcrmstr',
    'Global Cache Blocks Lost'              => 'GCBlckLst',
    'Global Cache Average CR Get Time'      => 'GCAvgCRGtTm',
    'Global Cache Average Current Get Time' => 'GCAvgCtGtTm',
    'GC CR Block Received Per Second'       => 'GCCRBlckRcPS',
    'GC Current Block Received Per Second'  => 'GCCtBlckRcPS',
    'Global Cache Blocks Corrupted'         => 'GCBlckCrrptd',
    'GC Avg CR Block receive ms'            => 'AvgCRBlkrc',
    'GC Avg CUR Block receive ms'           => 'AvgCURBlkrc',
  },
  'Wait_class_Main' => {
    'Average wait FG ms' => 'AvgwtFGms',
    'Average wait ms'    => 'Avgwtms',
  },
  'IO_Read_Write_per_datafile' => {
    'Physical Writes'   => 'physW',
    'Physical Reads'    => 'physR',
    'Avg write read ms' => 'avgwrms',
    'Avg read wait ms'  => 'avgrwms',
    'ReadWrite'         => 'rw',
  },
  'Services' => {
    'physical writes' => 'physW',
    'physical reads'  => 'physR',
  },
  'Overview' => {
    'overview' => 'Overview',
  },
  'host_metrics' => {
    'host' => 'metrics',
  },
  'Session_info_PDB' => {
    'host' => 'metrics',
  },
  'hosts_Total' => {
    'hosts' => 'total',
  },
  'Capacity' => {
    'used'   => 'used',
    'free'   => 'free',
    'logcap' => 'log',
  },
  'Cpct' => {
    'controlfiles' => 'controlfiles',
    'tempfiles'    => 'tempfiles',
    'recoverysize' => 'recoverysize',
    'recoveryused' => 'recoveryused',
  }
);

my %conf_types = (
  "configuration"             => 1,
  "configuration_S"           => 1,
  "configuration_Multitenant" => 1,
  "configuration_PDB"         => 1,
  "configuration_Total"       => 1,
  "configuration_dg"          => 1,
  "viewone"                   => 1,
  "viewtwo"                   => 1,
  "viewthree"                 => 1,
  "viewfour"                  => 1,
  "viewfive"                  => 1,
  "waitclass"                 => 1,
  "datafiles"                 => 1,
  "Interconnect"              => 1,
  "Capacity"                  => 1,
  "healthstatus"              => 1,
);

sub get_filepath_rrd {
  my $self   = shift;
  my $params = shift;

  my $type      = $params->{type};
  my $server    = $params->{uuid};
  my $host      = $params->{id};
  my $skip_acl  = $params->{skip_acl};
  my $acl_check = $params->{acl_check};
  my $filepath  = "";

  #return if ($use_sql && ! isGranted($uuid));
  if ( $type =~ /aggr_/ ) {
    $type =~ s/aggr_//g;
    $type =~ s/_/ /g;
  }
  else {
    #    $type = remove_subs($type);
    $type =~ s/_PDB//g;
    $type =~ s/_/ /g;
  }
  $type =~ s/;//g;

  if    ( $type eq 'CPU info' )                                                  { $filepath = "$odb_dir/$server/CPU_info/$host-CPU_info.rrd"; }
  elsif ( $type eq 'Ratio' )                                                     { $filepath = "$odb_dir/$server/Ratio/$host-Ratio.rrd"; }
  elsif ( $type eq 'Network' )                                                   { $filepath = "$odb_dir/$server/Network/$host-Network.rrd"; }
  elsif ( $type eq 'Session info' )                                              { $filepath = "$odb_dir/$server/Session_info/$host-Session_info.rrd"; }
  elsif ( $type eq 'SQL query' )                                                 { $filepath = "$odb_dir/$server/SQL_query/$host-SQL_query.rrd"; }
  elsif ( $type eq 'SQLquery' )                                                  { $filepath = "$odb_dir/$server/SQL_query/$host-SQL_query.rrd"; }
  elsif ( $type eq 'Data rate' )                                                 { $filepath = "$odb_dir/$server/Data_rate/$host-Data_rate.rrd"; }
  elsif ( $type eq 'Datarate' )                                                  { $filepath = "$odb_dir/$server/Data_rate/$host-Data_rate.rrd"; }
  elsif ( $type eq 'Data rate r' )                                               { $filepath = "$odb_dir/$server/Data_rate/$host-Data_rate.rrd"; }
  elsif ( $type eq 'RAC' )                                                       { $filepath = "$odb_dir/$server/RAC/$host-RAC.rrd"; }
  elsif ( $type eq 'Cache' )                                                     { $filepath = "$odb_dir/$server/RAC/$host-Cache.rrd"; }
  elsif ( $type eq 'Interconnect' )                                              { $filepath = "$odb_dir/$server/RAC/$host-Cache.rrd"; }
  elsif ( $type eq 'Global' )                                                    { $filepath = "$odb_dir/$server/RAC/Global.rrd"; }
  elsif ( $type eq 'Disk latency' )                                              { $filepath = "$odb_dir/$server/Disk_latency/$host-Disk_latency.rrd"; }
  elsif ( $type eq 'Services' )                                                  { $filepath = "$odb_dir/$server/Services/"; }
  elsif ( $type eq 'Cpct' )                                                      { $filepath = "$odb_dir/$server/Capacity/$host-Cpct.rrd"; }
  elsif ( $type =~ /configuration/ or $type eq 'Capacity' or $type eq 'logcap' ) { $filepath = "$odb_dir/$server/Capacity/$host-Capacity.rrd"; }
  elsif ( $type =~ /view/ )                                                      { $filepath = "$odb_dir/$server/RAC/$host-RAC.rrd"; }
  elsif ( $type eq 'info' )                                                      { $filepath = ""; }
  elsif ( $type eq 'Wait class Main' )                                           { $filepath = "$odb_dir/$server/Wait_class/"; }
  elsif ( $type eq 'IO Read Write per datafile' )                                { $filepath = "$odb_dir/$server/Datafiles/"; }
  else {
    warn "Unknown rrd type $type";
    $filepath = "";
  }

  # ACL check
  if ( $acl_check && !$skip_acl ) {
    my $uuid = get_uuid($server);
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

sub get_uuid {
  my $server = shift;
  my $type   = shift;
  my $name   = shift;
  my $arc    = get_arc();
  my $uuid   = "";
  my %types  = (
    'Standalone'  => 1,
    'RAC'         => 1,
    'Multitenant' => 1,
  );
  for my $k_uuid ( keys %{$arc} ) {
    my $_server = defined $arc->{$k_uuid}->{server} ? $arc->{$k_uuid}->{server} : "";
    my $_type   = defined $arc->{$k_uuid}->{type}   ? $arc->{$k_uuid}->{type}   : "";
    my $_host   = defined $arc->{$k_uuid}->{host}   ? $arc->{$k_uuid}->{host}   : "";
    if ( $_server and $_type and $_host ) {
      if ( $type and $name ) {
        if ( $_server eq $server and $_type eq $type and $_host eq $name ) {
          $uuid = $k_uuid;
          last;
        }
      }
      else {
        if ( $type and $type ne "" ) {
          if ( $_server eq $server and $_type eq $type ) {
            $uuid = $k_uuid;
            last;
          }
        }
        else {
          if ( $_server eq $server and $types{$_type} ) {
            $uuid = $k_uuid;
            last;
          }
        }
      }
    }
  }
  return $uuid;
}

sub get_filepath_rrd_bpage {
  my $self   = shift;
  my $page   = shift;
  my $server = shift;
  my $host   = shift;
  my $skip   = shift;

  my $type = get_type_from_page($page);
  $type =~ s/_/ /g;
  if ( defined $skip and $skip == 1 ) {
    get_filepath_rrd( { type => $type, uuid => $server, id => $host, skip_acl => $skip } );
  }
  else {
    get_filepath_rrd( { type => $type, uuid => $server, id => $host } );
  }
}

sub get_type_from_page {
  my $self = shift;
  my $page = shift;
  $page =~ s/_/ /g;
  my $type = "empty";
  for my $key ( keys %hsh ) {
    if ( $hsh{$key}{$page} ) {
      $type = $key;
      last;
    }
  }
  return $type;
}

sub get_pages {
  my $self = shift;
  my $type = shift;
  $type =~ s/aggr_//g;

  #x$type =~ s/_//g;
  if ( $hsh{$type} ) {
    return $hsh{$type};
  }
  else {
    return "empty";
  }
}

sub does_type_exist {
  my $self = shift;
  my $type = shift;

  #  $type = remove_subs($type);

  if ( $conf_types{$type} ) {
    return "conf";
  }

  if ( $type =~ /aggr_/ ) {
    $type =~ s/aggr_//g;
  }

  if ( $type eq "Datarate" or $type eq "Data_rate_r" ) {
    return 1;
  }
  if ( $hsh{$type} ) {
    return 1;
  }
  else {
    return 0;
  }
}

sub get_arc {
  my $self = shift;
  my ( $can_read, $ref ) = Xorux_lib::read_json("$odb_dir/Totals/arc.json");
  if ($can_read) {
    return $ref;
  }
  else {
    return "0";
  }
}

sub get_groups {
  my $self = shift;
  my $type = shift;

  my ( $can_read, $ref );
  if ( $type and $type eq "old" ) {
    ( $can_read, $ref ) = Xorux_lib::read_json("$odb_dir/Totals/groups.json.old");
  }
  else {
    ( $can_read, $ref ) = Xorux_lib::read_json("$odb_dir/Totals/groups.json");
  }
  if ($can_read) {
    return $ref;
  }
  else {
    return "0";
  }
}

sub is_granted {
  my $self = shift;
  my $uuid = shift;

  if ( $self->{aclx} ) {
    return $self->{aclx}->isGranted( { hw_type => 'ORACLEDB', item_id => $uuid, match => 'granted' } );
  }

  return;
}

sub isGranted {
  my $uuid = shift;

  require ACLx;
  my $acl = ACLx->new();

  return $acl->isGranted( { hw_type => 'ORACLEDB', item_id => $uuid, match => 'granted' } );
}

sub graph_legend {
  my $self = shift;
  my $page = shift;
  $page =~ s/_Total//g;
  $page =~ s/_/ /g;

  #types have tabs that are defined in links_oracledb.json
  #This defines rules for graphs in each tab
  my %legend = (
    'Memory Sorts Ratio' => {
      'denom'      => '1',
      'brackets'   => '[%]',
      'header'     => 'Memory Sorts',
      'value'      => 'Total',
      'rrd_vname'  => 'MmrSrts',
      'graph_type' => 'LINE1',
      'v_label'    => '% MemSort/(MemSort + DiskSort)'
    },
    'Database Wait Time Ratio' => {
      'denom'      => '1',
      'brackets'   => '[%]',
      'header'     => 'Database Wait Time',
      'value'      => 'Total',
      'graph_type' => 'LINE1',
      'rrd_vname'  => 'DbWtTm',
      'v_label'    => '% Wait/DB_Time'
    },
    'PGA Cache Hit' => {
      'denom'      => '1',
      'brackets'   => '[%]',
      'header'     => 'PGA Cache Hit',
      'value'      => 'Total',
      'rrd_vname'  => 'PGACchHt',
      'graph_type' => 'LINE1',
      'v_label'    => '% Bytes/TotalBytes'
    },
    'Soft Parse Ratio' => {
      'denom'      => '1',
      'brackets'   => '[%]',
      'header'     => 'Soft Parse',
      'value'      => 'Total',
      'graph_type' => 'LINE1',
      'rrd_vname'  => 'SftPrs',
      'v_label'    => '% SoftParses/TotalParses'
    },
    'Database CPU Time Ratio' => {
      'denom'      => '1',
      'brackets'   => '[%]',
      'header'     => 'Database CPU Time',
      'value'      => 'Total',
      'graph_type' => 'LINE1',
      'rrd_vname'  => 'DbCPUTm',
      'v_label'    => '% Cpu/DB_Time'
    },
    'Buffer Cache Hit Ratio' => {
      'denom'      => '1',
      'brackets'   => '[%]',
      'header'     => 'Buffer Cache Hit',
      'value'      => 'Total',
      'graph_type' => 'LINE1',
      'rrd_vname'  => 'BffrCchHt',
      'v_label'    => '% (LogRead - PhyRead)/LogRead'
    },
    'Network Traffic Volume Per Sec' => {
      'denom'      => '1000000',
      'brackets'   => '[MB/s]',
      'header'     => 'Network Traffic Volume',
      'value'      => 'Total',
      'graph_type' => 'AREA',
      'rrd_vname'  => 'NetTrfcVlPS',
      'v_label'    => 'Bytes Per Second'
    },
    'Executions Per Sec' => {
      'denom'      => '1',
      'brackets'   => '',
      'header'     => 'Executions',
      'value'      => 'Executes',
      'graph_type' => 'LINE1',
      'rrd_vname'  => 'ExecsPS',
      'v_label'    => 'Executes Per Second'
    },
    'Hard Parse Count Per Sec' => {
      'denom'      => '1',
      'brackets'   => '',
      'header'     => 'Hard Parse Count',
      'value'      => 'Parses',
      'graph_type' => 'LINE1',
      'rrd_vname'  => 'HrdPrsCntPS',
      'v_label'    => 'Parses Per Second'
    },
    'IO Megabytes per Second' => {
      'denom'      => '1',
      'brackets'   => '[MB/s]',
      'header'     => 'Data',
      'value'      => 'Total',
      'graph_type' => 'AREA',
      'rrd_vname'  => 'IOMbPS',
      'v_label'    => 'Megabtyes per Second'
    },
    'IO Requests per Second' => {
      'denom'      => '1',
      'brackets'   => '[IOPS]',
      'header'     => 'IO',
      'value'      => 'Total',
      'graph_type' => 'AREA',
      'rrd_vname'  => 'IORqstPS',
      'v_label'    => 'Requests per Second'
    },
    'Logical Reads Per Sec' => {
      'denom'      => '1',
      'brackets'   => '',
      'header'     => 'Logical Read',
      'value'      => 'Total',
      'graph_type' => 'LINE1',
      'rrd_vname'  => 'LgclReadPS',
      'v_label'    => 'Reads Per Second'
    },
    'Redo Generated Per Sec' => {
      'denom'      => '1000000',
      'brackets'   => '[MB/s]',
      'header'     => 'Redo Generated',
      'value'      => 'Total',
      'graph_type' => 'AREA',
      'rrd_vname'  => 'RdoGenPS',
      'v_label'    => 'MegaBytes Per Second'
    },
    'DB Block Changes Per Sec' => {
      'denom'      => '1',
      'brackets'   => '',
      'header'     => 'DB Block Changes',
      'value'      => 'Total',
      'graph_type' => 'LINE1',
      'rrd_vname'  => 'DBBlckChngPS',
      'v_label'    => 'Blocks Per Second'
    },
    'Host CPU Utilization' => {
      'denom'      => '1',
      'brackets'   => '[Utilization in %]',
      'header'     => 'Host CPU Utilization',
      'value'      => 'Utilization',
      'graph_type' => 'LINE1',
      'rrd_vname'  => 'HstCPUutil',
      'v_label'    => '% Busy/(Idle+Busy)'
    },
    'CPU Usage Per Txn' => {
      'denom'      => '100',
      'brackets'   => '[Utilization in cores]',
      'header'     => 'CPU Core Usage Per Txn',
      'value'      => 'Per Txn',
      'graph_type' => 'LINE1',
      'rrd_vname'  => 'CPUusgPT',
      'v_label'    => 'CPU Core'
    },
    'CPU Usage Per Sec' => {
      'denom'      => '100',
      'brackets'   => '[Utilization in cores]',
      'header'     => 'CPU Core Usage Per Sec',
      'value'      => 'Per Sec',
      'graph_type' => 'LINE1',
      'rrd_vname'  => 'CPUusgPS',
      'v_label'    => 'CPU Core'
    },
    'Global Cache Blocks Lost' => {
      'denom'      => '1',
      'brackets'   => '',
      'header'     => 'Global Cache Blocks Lost',
      'value'      => 'Blocks lost',
      'graph_type' => 'LINE1',
      'rrd_vname'  => 'GCBlckLst',
      'v_label'    => 'Blocks lost'
    },
    'Physical Read Bytes Per Sec' => {
      'denom'      => '1000000',
      'brackets'   => '[MB/s]',
      'header'     => 'Physical Read Bytes Per Sec',
      'value'      => 'Total',
      'graph_type' => 'AREA',
      'rrd_vname'  => 'PhysReadBPS',
      'v_label'    => 'Megabytes per second'
    },
    'Physical Write Bytes Per Sec' => {
      'denom'      => '1000000',
      'brackets'   => '[MB/s]',
      'header'     => 'Physical Write Bytes Per Sec',
      'value'      => 'Total',
      'graph_type' => 'AREA',
      'rrd_vname'  => 'PhysWriteBPS',
      'v_label'    => 'Megabytes per second'
    },
    'Physical Reads Per Sec' => {
      'denom'      => '1',
      'brackets'   => '',
      'header'     => 'Physical Reads Per Sec',
      'value'      => 'Total',
      'graph_type' => 'AREA',
      'rrd_vname'  => 'PhysReadPS',
      'v_label'    => 'IOPS Read'
    },
    'Physical Writes Per Sec' => {
      'denom'      => '1',
      'brackets'   => '',
      'header'     => 'Physical Writes Per Sec',
      'value'      => 'Total',
      'graph_type' => 'AREA',
      'rrd_vname'  => 'PhysWritePS',
      'v_label'    => 'IOPS Write'
    },

    'Global Cache Average CR Get Time' => {
      'denom'      => '1',
      'brackets'   => '[ms]',
      'header'     => 'Global Cache Average CR Get Time',
      'value'      => 'ms per wait',
      'graph_type' => 'LINE1',
      'rrd_vname'  => 'GCAvgCRGtTm',
      'v_label'    => 'Milliseconds per wait'
    },
    'Global Cache Average Current Get Time' => {
      'denom'      => '1',
      'brackets'   => '[ms]',
      'header'     => 'Global Cache Average Current Get Time',
      'value'      => 'ms per wait',
      'graph_type' => 'LINE1',
      'rrd_vname'  => 'GCAvgCtGtTm',
      'v_label'    => 'Milliseconds per wait'
    },
    'GC CR Block Received Per Second' => {
      'denom'      => '1',
      'brackets'   => '',
      'header'     => 'GC CR Block Received Per Second',
      'value'      => 'Blocks recieved',
      'graph_type' => 'LINE1',
      'rrd_vname'  => 'GCCRBlckRcPS',
      'v_label'    => 'Blocks Per Second'
    },
    'GC Current Block Received Per Second' => {
      'denom'      => '1',
      'brackets'   => '',
      'header'     => 'GC Current Block Received Per Second',
      'value'      => 'Blocks recieved',
      'graph_type' => 'LINE1',
      'rrd_vname'  => 'GCCtBlckRcPS',
      'v_label'    => 'Blocks Per Second'
    },
    'Global Cache Blocks Corrupted' => {
      'denom'      => '1',
      'brackets'   => '',
      'header'     => 'Global Cache Blocks Corrupted',
      'value'      => 'Blocks corrupted',
      'graph_type' => 'LINE1',
      'rrd_vname'  => 'GCBlckCrrptd',
      'v_label'    => 'Blocks corrupted'
    },

    'Cell Physical IO Interconnect Bytes' => {
      'denom'      => '1',
      'brackets'   => '[MB/s]',
      'header'     => 'Interconnect traffic',
      'value'      => 'Total',
      'graph_type' => 'AREA',
      'rrd_vname'  => 'CPIOIntB',
      'v_label'    => 'Megabytes per second'
    },
    'GC Avg CR Block receive ms' => {
      'denom'      => '1',
      'brackets'   => '',
      'header'     => 'GC Avg CR Block receive ms',
      'value'      => 'Blocks corrupted',
      'graph_type' => 'LINE1',
      'rrd_vname'  => 'AvgCRBlkrc',
      'v_label'    => 'Blocks corrupted'
    },
    'GC Avg CUR Block receive ms' => {
      'denom'      => '1',
      'brackets'   => '',
      'header'     => 'GC Avg CUR Block receive ms',
      'value'      => 'Blocks',
      'graph_type' => 'LINE1',
      'rrd_vname'  => 'AvgCURBlkrc',
      'v_label'    => 'Blocks Per Second'
    },
    'DB files read latency' => {
      'denom'      => '1',
      'brackets'   => '',
      'header'     => 'DB files read latency',
      'value'      => 'ms per wait',
      'graph_type' => 'LINE1',
      'rrd_vname'  => 'flsrltnc',
      'v_label'    => 'Milliseconds per wait'
    },
    'db file scattered read' => {
      'denom'      => '1',
      'brackets'   => '',
      'header'     => 'db file scattered read',
      'value'      => 'ms per wait',
      'graph_type' => 'LINE1',
      'rrd_vname'  => 'dbflscttrdr',
      'v_label'    => 'Milliseconds per wait'
    },
    'db file sequential read' => {
      'denom'      => '1',
      'brackets'   => '',
      'header'     => 'db file sequential read',
      'value'      => 'ms per wait',
      'graph_type' => 'LINE1',
      'rrd_vname'  => 'flsqentlr',
      'v_label'    => 'Milliseconds per wait'
    },
    'db file single write' => {
      'denom'      => '1',
      'brackets'   => '',
      'header'     => 'db file single write',
      'value'      => 'ms per wait',
      'graph_type' => 'LINE1',
      'rrd_vname'  => 'flsnglw',
      'v_label'    => 'Milliseconds per wait'
    },
    'db file parallel write' => {
      'denom'      => '1',
      'brackets'   => '',
      'header'     => 'db file parallel write',
      'value'      => 'ms per wait',
      'graph_type' => 'LINE1',
      'rrd_vname'  => 'flprlllw',
      'v_label'    => 'Milliseconds per wait'
    },
    'log file sync' => {
      'denom'      => '1',
      'brackets'   => '',
      'header'     => 'log file sync',
      'value'      => 'ms per wait',
      'graph_type' => 'LINE1',
      'rrd_vname'  => 'lgflsnc',
      'v_label'    => 'Milliseconds per wait'
    },
    'log file single write' => {
      'denom'      => '1',
      'brackets'   => '',
      'header'     => 'log file single write',
      'value'      => 'ms per wait',
      'graph_type' => 'LINE1',
      'rrd_vname'  => 'lgflsnglw',
      'v_label'    => 'Milliseconds per wait'
    },
    'log file parallel write' => {
      'denom'      => '1',
      'brackets'   => '',
      'header'     => 'log file parallel write',
      'value'      => 'ms per wait',
      'graph_type' => 'LINE1',
      'rrd_vname'  => 'lgflprlllw',
      'v_label'    => 'Milliseconds per wait'
    },
    'flashback log file sync' => {
      'denom'      => '1',
      'brackets'   => '',
      'header'     => 'flashback log file sync',
      'value'      => 'ms per wait',
      'graph_type' => 'LINE1',
      'rrd_vname'  => 'flshbcklgfl',
      'v_label'    => 'Milliseconds per wait'
    },
    'DB files write latency' => {
      'denom'      => '1',
      'brackets'   => '',
      'header'     => 'DB files write latency',
      'value'      => 'ms per wait',
      'graph_type' => 'LINE1',
      'rrd_vname'  => 'flswltnc',
      'v_label'    => 'Milliseconds per wait'
    },
    'LOG files write latency' => {
      'denom'      => '1',
      'brackets'   => '',
      'header'     => 'LOG files write latency',
      'value'      => 'ms per wait',
      'graph_type' => 'LINE1',
      'rrd_vname'  => 'LGflswltnc',
      'v_label'    => 'Latency per wait'
    },
    'gc cr block 2-way' => {
      'denom'      => '1',
      'brackets'   => '',
      'header'     => 'gc cr block 2-way',
      'value'      => 'ms per wait',
      'graph_type' => 'LINE1',
      'rrd_vname'  => 'crblocktwy',
      'v_label'    => 'Milliseconds per wait'
    },
    'gc current block 2-way' => {
      'denom'      => '1',
      'brackets'   => '',
      'header'     => 'gc current block 2-way',
      'value'      => 'ms per wait',
      'graph_type' => 'LINE1',
      'rrd_vname'  => 'crntblcktwy',
      'v_label'    => 'Milliseconds per wait'
    },
    'gc cr block 3-way' => {
      'denom'      => '1',
      'brackets'   => '',
      'header'     => 'gc cr block 3-way',
      'value'      => 'ms per wait',
      'graph_type' => 'LINE1',
      'rrd_vname'  => 'crblckthwy',
      'v_label'    => 'Milliseconds per wait'
    },
    'gc current block 3-way' => {
      'denom'      => '1',
      'brackets'   => '',
      'header'     => 'gc current block 3-way',
      'value'      => 'ms per wait',
      'graph_type' => 'LINE1',
      'rrd_vname'  => 'crntblckthwy',
      'v_label'    => 'Milliseconds per wait'
    },
    'gc cr block busy' => {
      'denom'      => '1',
      'brackets'   => '',
      'header'     => 'gc cr block busy',
      'value'      => 'ms per wait',
      'graph_type' => 'LINE1',
      'rrd_vname'  => 'crblckbs',
      'v_label'    => 'Milliseconds per wait'
    },
    'gc cr block congested' => {
      'denom'      => '1',
      'brackets'   => '',
      'header'     => 'gc cr block congested',
      'value'      => 'ms per wait',
      'graph_type' => 'LINE1',
      'rrd_vname'  => 'crblckcngstd',
      'v_label'    => 'Milliseconds per wait'
    },
    'gc cr grant 2-way' => {
      'denom'      => '1',
      'brackets'   => '',
      'header'     => 'gc cr grant 2-way',
      'value'      => 'ms per wait',
      'graph_type' => 'LINE1',
      'rrd_vname'  => 'crgrnttwy',
      'v_label'    => 'Milliseconds per wait'
    },
    'gc cr grant congested' => {
      'denom'      => '1',
      'brackets'   => '',
      'header'     => 'gc cr grant congested',
      'value'      => 'ms per wait',
      'graph_type' => 'LINE1',
      'rrd_vname'  => 'crgrntcngstd',
      'v_label'    => 'Milliseconds per wait'
    },
    'gc current block busy' => {
      'denom'      => '1',
      'brackets'   => '',
      'header'     => 'gc current block busy',
      'value'      => 'ms per wait',
      'graph_type' => 'LINE1',
      'rrd_vname'  => 'crntblckbs',
      'v_label'    => 'Milliseconds per wait'
    },
    'gc current block congested' => {
      'denom'      => '1',
      'brackets'   => '',
      'header'     => 'gc current block congested',
      'value'      => 'ms per wait',
      'graph_type' => 'LINE1',
      'rrd_vname'  => 'crntblckcngs',
      'v_label'    => 'Milliseconds per wait'
    },
    'gc current grant 2-way' => {
      'denom'      => '1',
      'brackets'   => '',
      'header'     => 'gc current grant 2-way',
      'value'      => 'ms per wait',
      'graph_type' => 'LINE1',
      'rrd_vname'  => 'crntgrnttwy',
      'v_label'    => 'Milliseconds per wait'
    },
    'gc current grant congested' => {
      'denom'      => '1',
      'brackets'   => '',
      'header'     => 'gc current grant congested',
      'value'      => 'ms per wait',
      'graph_type' => 'LINE1',
      'rrd_vname'  => 'crntgrntcstd',
      'v_label'    => 'Milliseconds per wait'
    },
    'gc cr block lost' => {
      'denom'      => '1',
      'brackets'   => '',
      'header'     => 'gc cr block lost',
      'value'      => 'ms per wait',
      'graph_type' => 'LINE1',
      'rrd_vname'  => 'crblcklst',
      'v_label'    => 'Milliseconds per wait'
    },
    'gc current block lost' => {
      'denom'      => '1',
      'brackets'   => '',
      'header'     => 'gc current block lost',
      'value'      => 'ms per wait',
      'graph_type' => 'LINE1',
      'rrd_vname'  => 'crntblcklst',
      'v_label'    => 'Milliseconds per wait'
    },
    'gc cr failure' => {
      'denom'      => '1',
      'brackets'   => '',
      'header'     => 'gc cr failure',
      'value'      => 'ms per wait',
      'graph_type' => 'LINE1',
      'rrd_vname'  => 'crflr',
      'v_label'    => 'Milliseconds per wait'
    },
    'gc current retry' => {
      'denom'      => '1',
      'brackets'   => '',
      'header'     => 'gc current retry',
      'value'      => 'ms per wait',
      'graph_type' => 'LINE1',
      'rrd_vname'  => 'crntrtr',
      'v_label'    => 'Milliseconds per wait'
    },
    'gc current split' => {
      'denom'      => '1',
      'brackets'   => '',
      'header'     => 'gc current split',
      'value'      => 'ms per wait',
      'graph_type' => 'LINE1',
      'rrd_vname'  => 'crntsplt',
      'v_label'    => 'Milliseconds per wait'
    },
    'gc current multi block request' => {
      'denom'      => '1',
      'brackets'   => '',
      'header'     => 'gc current multi block request',
      'value'      => 'ms per wait',
      'graph_type' => 'LINE1',
      'rrd_vname'  => 'crntmltrqst',
      'v_label'    => 'Milliseconds per wait'
    },
    'gc current grant busy' => {
      'denom'      => '1',
      'brackets'   => '',
      'header'     => 'gc current grant busy',
      'value'      => 'ms per wait',
      'graph_type' => 'LINE1',
      'rrd_vname'  => 'crntgrntbs',
      'v_label'    => 'Milliseconds per wait'
    },
    'gc cr disk read' => {
      'denom'      => '1',
      'brackets'   => '',
      'header'     => 'gc cr disk read',
      'value'      => 'ms per wait',
      'graph_type' => 'LINE1',
      'rrd_vname'  => 'crdskr',
      'v_label'    => 'Milliseconds per wait'
    },
    'gc cr multi block request' => {
      'denom'      => '1',
      'brackets'   => '',
      'header'     => 'gc cr multi block request',
      'value'      => 'ms per wait',
      'graph_type' => 'LINE1',
      'rrd_vname'  => 'crmtblckrqst',
      'v_label'    => 'Milliseconds per wait'
    },
    'gc buffer busy acquire' => {
      'denom'      => '1',
      'brackets'   => '',
      'header'     => 'gc buffer busy acquire',
      'value'      => 'ms per wait',
      'graph_type' => 'LINE1',
      'rrd_vname'  => 'bfrbsacqr',
      'v_label'    => 'Milliseconds per wait'
    },
    'Current Logons Count' => {
      'denom'      => '1',
      'brackets'   => '',
      'header'     => 'Current Logons Count',
      'value'      => 'Total',
      'graph_type' => 'LINE1',
      'rrd_vname'  => 'CrntLgnsCnt',
      'v_label'    => 'Current Logons'
    },
    'Logons Per Sec' => {
      'denom'      => '1',
      'brackets'   => '',
      'header'     => 'Logons Per Sec',
      'value'      => 'Total',
      'graph_type' => 'LINE1',
      'rrd_vname'  => 'LgnsPS',
      'v_label'    => 'Logons Per Sec'
    },
    'Active Serial Sessions' => {
      'denom'      => '1',
      'brackets'   => '',
      'header'     => 'Active Serial Sessions',
      'value'      => 'Total',
      'graph_type' => 'LINE1',
      'rrd_vname'  => 'ActSrlSsion',
      'v_label'    => 'Active Serial Sessions'
    },
    'Active Parallel Sessions' => {
      'denom'      => '1',
      'brackets'   => '',
      'header'     => 'Active Parallel Sessions',
      'value'      => 'Total',
      'graph_type' => 'LINE1',
      'rrd_vname'  => 'ActPrllSsion',
      'v_label'    => 'Active Parallel Sessions'
    },
    'Average Active Sessions' => {
      'denom'      => '1',
      'brackets'   => '',
      'header'     => 'Average Active Sessions',
      'value'      => 'Total',
      'graph_type' => 'LINE1',
      'rrd_vname'  => 'AvgActSsion',
      'v_label'    => 'Average Active Sessions'
    },
    'gc remaster' => {
      'denom'      => '1',
      'brackets'   => '[ms]',
      'header'     => 'gc remaster',
      'value'      => 'ms per wait',
      'graph_type' => 'LINE1',
      'rrd_vname'  => 'gcrmstr',
      'v_label'    => 'Milliseconds per wait'
    },
    'Current Open Cursors Count' => {
      'denom'      => '1',
      'brackets'   => '',
      'header'     => 'Current Open Cursors Count',
      'value'      => 'current open cursors',
      'graph_type' => 'LINE1',
      'rrd_vname'  => 'CntOpnCrs',
      'v_label'    => 'Blocks per second'
    },
    'User Commits Per Sec' => {
      'denom'      => '1',
      'brackets'   => '',
      'header'     => 'User Commits Per Sec',
      'value'      => 'user commits/s',
      'graph_type' => 'LINE1',
      'rrd_vname'  => 'UsrComtsPS',
      'v_label'    => 'Blocks per second'
    },
    'User Transaction Per Sec' => {
      'denom'      => '1',
      'brackets'   => '',
      'header'     => 'User Transaction Per Sec',
      'value'      => 'user transactions/s',
      'graph_type' => 'LINE1',
      'rrd_vname'  => 'UsrTxnPS',
      'v_label'    => 'Blocks per second'
    },
    'Open Cursors Per Sec' => {
      'denom'      => '1',
      'brackets'   => '[ms]',
      'header'     => 'Open Cursors Per Sec',
      'value'      => 'open cursors/s',
      'graph_type' => 'LINE1',
      'rrd_vname'  => 'OpnCrsPS',
      'v_label'    => 'Blocks per second'
    },
    'gc buffer busy release' => {
      'denom'      => '1',
      'brackets'   => '',
      'header'     => 'gc buffer busy release',
      'value'      => 'ms per wait',
      'graph_type' => 'LINE1',
      'rrd_vname'  => 'bfrbsrls',
      'v_label'    => 'Milliseconds per wait'
    },
    'used' => {
      'denom'      => '1',
      'brackets'   => '[GiB]',
      'header'     => 'Usec',
      'value'      => 'Used',
      'graph_type' => 'AREA',
      'rrd_vname'  => 'used',
      'v_label'    => 'Used'
    },
    'free' => {
      'denom'      => '1',
      'brackets'   => '[GiB]',
      'header'     => 'Free',
      'value'      => 'Free',
      'graph_type' => 'AREA',
      'rrd_vname'  => 'free',
      'v_label'    => 'Free'
    },
    'logcap' => {
      'denom'      => '1',
      'brackets'   => '[GiB]',
      'header'     => 'LOG space used',
      'value'      => 'LOG space used',
      'graph_type' => 'AREA',
      'rrd_vname'  => 'log',
      'v_label'    => 'LOG space used'
    }
  );
  if ( $legend{$page} ) {
    return $legend{$page};
  }
  else {
    return undef;
  }
}

1;
