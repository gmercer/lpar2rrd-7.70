package OracleDBDataWrapper;

use strict;
use warnings;

use JSON;
use Data::Dumper;
use Xorux_lib qw(error read_json);
use Digest::MD5 qw(md5 md5_hex md5_base64);

my $use_sql = 0;    # defined $ENV{XORMON};

my $acl;
if ( defined $ENV{XORMON} && $ENV{XORMON} ) {
  $use_sql = 1;

  require ACLx;
  $acl = ACLx->new();

  sub isGranted {
    my $uuid = shift;
    return $acl->isGranted( { hw_type => 'ORACLEDB', item_id => $uuid, match => 'granted' } );
  }
}

defined $ENV{INPUTDIR} || Xorux_lib::error( "INPUTDIR undefined, config etc/lpar2rrd.cfg probably has not been loaded " . __FILE__ . ":" . __LINE__ ) && exit 1;

my $inputdir   = $ENV{INPUTDIR};
my $tmpdir     = "$inputdir/tmp";
my $odb_dir    = "$inputdir/data/OracleDB";
my $totals_dir = "$odb_dir/Totals";

#my $iostats_dir      = "$odb_dir/iostats";
#my $cpu_info_dir     = "$odb_dir/CPU_info";
#my $network_dir      = "$odb_dir/Network";
#my $ratio_dir        = "$odb_dir/Ratio";
#my $sql_query_dir    = "$odb_dir/SQL_query";
#my $data_rate_dir    = "$odb_dir/Data_rate";
#my $session_info_dir = "$odb_dir/Session_info";

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

my %host_metrics = (
  "CPU info"  => 1,
  "Data rate" => 1,
  "Capacity"  => 1,
);
################################################################################

sub is_host_metric {
  my $metric = shift;
  if ( $host_metrics{$metric} ) {
    return 1;
  }
  else {
    return 0;
  }
}

sub get_host_metrics {
  return \%host_metrics;
}

sub get_filepath_rrd {
  my $params = shift;

  my $type     = $params->{type};
  my $server   = $params->{uuid};
  my $host     = $params->{id};
  my $skip_acl = $params->{skip_acl};
  my $filepath = "";

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
  if ( $use_sql && !$skip_acl ) {
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

sub remove_subs {
  my $_type = shift;

  $_type =~ s/_MULTITENANT//g;
  $_type =~ s/_PDBS//g;
  $_type =~ s/_INSTANCE//g;
  $_type =~ s/_GLOBAL_CACHE//g;
  $_type =~ s/_RAC//g;
  $_type =~ s/_STANDALONE//g;
  $_type =~ s/_ITEMS//g;
  $_type =~ s/_HOSTS//g;
  $_type =~ s/_TOTAL//g;
  $_type =~ s/_ODBFOLDER//g;
  $_type =~ s/_PDBTOTAL//g;

  return $_type;
}

#sub get_instances {
#  my $host = shift;
#  my $server = shift;
#  my $type = shift;
#
#my $instance_names;
#my $can_read;
#my $ref;
#}
sub instancename_to_ip {
  my $instance_name = shift;
  my $alias         = shift;
  my $instance_names;
  my $pdb_names;
  if ( $alias ne "hostname" ) {
    my ( $can_read, $ref ) = Xorux_lib::read_json("$odb_dir/$alias/instance_names.json");
    if ($can_read) {
      $instance_names = $ref;
      for my $instance ( keys %{$instance_names} ) {
        if ( $instance_names->{$instance} eq $instance_name ) {
          my $type = get_dbtype($alias);
          if ( $type eq "Standalone" or $type eq "Multitenant" ) {
            return { type => "$type", ip => $instance };
          }
          else {
            return { type => "instance", ip => $instance };
          }
        }
      }
    }
    if ( -e "$odb_dir/$alias/pdb_names.json" ) {
      my ( $can_read_pdb, $ref_pdb ) = Xorux_lib::read_json("$odb_dir/$alias/pdb_names.json");
      if ($can_read_pdb) {
        $pdb_names = $ref_pdb;
        for my $pdb ( keys %{$pdb_names} ) {
          if ( $pdb_names->{$pdb} eq $instance_name ) {
            return { type => "pdbs", ip => $pdb };
          }
        }
      }
    }
  }
  return { type => "nothing", ip => "nothing" };
}

sub get_uuids {
  my $host          = shift;
  my $server        = shift;
  my $type          = shift;
  my $waitclass_dir = get_filepath_rrd( { type => $type, uuid => $server, id => $host } );
  my @instance_keys;
  my @files;

  # opendir( DH, $waitclass_dir ) || Xorux_lib::error( "Could not open '$waitclass_dir' for reading '$!'\n" ) && exit;
  # @files = sort( grep /.*\.rrd/, readdir DH );
  # closedir( DH );
  my ( $can_read, $ref );
  my %dict;
  if ( -f "$waitclass_dir/dict.json" ) {
    ( $can_read, $ref ) = Xorux_lib::read_json("$waitclass_dir/dict.json");
  }

  # foreach my $file (@files){
  #    undef $rrd;
  #    $rrd = "$waitclass_dir"."$file";
  #
  #    my $id = substr($file,0,-4);
  #    my $name;
  #    if ($can_read){
  #      $name = defined $dict->{$id}? $dict->{$id} : $id;
  #    }else{
  #      $name = $id;
  #    }
  my @host_separ;

  if ($can_read) {
    %dict = %{$ref};
    if ( $host =~ "_PDB_" ) {
      my $pdb = "empty";
      my @host_separ;
      @host_separ = split( "_PDB_", $host );
      $pdb        = $host_separ[1];
      foreach my $uuid ( keys %dict ) {
        my $cur_inst = $pdb;
        if ( $dict{$uuid} =~ /$cur_inst/ ) {
          push( @instance_keys, $uuid );
        }
      }
      return \@instance_keys;
    }
    elsif ( $host ne "not_needed" and $server ne "hostname" ) {
      my $can_read_i;
      my $ref_i;
      my $instance_names;
      ( $can_read, $ref ) = Xorux_lib::read_json("$odb_dir/$server/instance_names.json");
      if ($can_read) {
        $instance_names = $ref;
        foreach my $uuid ( keys %dict ) {
          my $cur_inst = defined $instance_names->{$host} ? $instance_names->{$host} : "nothing";
          if ( $cur_inst ne "nothing" and $dict{$uuid} =~ /$cur_inst,/ ) {
            push( @instance_keys, $uuid );
          }
        }
      }
      return \@instance_keys;
    }
    else {
      my @keys = keys %dict;
      return \@keys;
    }

  }
  else {
    my @keys;
    return \@keys;
  }
}

sub process_custom_odb {
  my $cfg;
  my ( $instance_names, $can_read, $ref );
  if ( -f "$inputdir/etc/web_config/custom_groups.cfg" ) {
    $cfg = "$inputdir/etc/web_config/custom_groups.cfg";
  }

  if ( !-f $cfg ) {

    # cfg does not exist
    warn("custom : custom cfg file does not exist: $cfg ");
    exit 1;
  }
  ( $can_read, $ref ) = Xorux_lib::read_json("$odb_dir/Totals/instance_names_total.json");
  undef $instance_names;
  if ($can_read) {
    $instance_names = $ref;
  }
  else {
    warn "Couldn't open $odb_dir/Totals/instance_names_total.json";
  }
  my %groups;
  open( FHR, "< $cfg" );
  foreach my $line (<FHR>) {
    chomp($line);
    $line =~ s/ *$//g;
    if ( $line =~ m/^$/ || $line !~ m/^(ODB)/ || $line =~ m/^#/ || $line !~ m/:/ || $line =~ m/:$/ || $line =~ m/: *$/ ) {
      next;
    }

    ( my $type, my $server, my $name, my $group_act ) = split( /(?<!\\):/, $line );    # my super regex takes just not backslashed colon
    if ( $type eq '' || $server eq '' || $name eq '' || $group_act eq '' ) {
      warn("custom : syntax error in $cfg: $line ");
      next;
    }
    foreach my $alias ( keys %{$instance_names} ) {
      my $name_lc  = lc($name);
      my $alias_lc = lc($alias);

      if ( $alias_lc =~ m/^$name_lc$/ or $name eq ".*" ) {
        my @dbs = keys %{ $instance_names->{$alias} };
        push( @{ $groups{_mgroups}{"_$group_act"}{_dbs}{$alias} }, @dbs );
      }
    }

  }
  return \%groups;
}

sub md5_string {
  my $data = shift;
  my $out  = md5_hex($data);
  return $out;
}

sub conf_files {
  my $wrkdir     = shift;
  my $type       = shift;
  my $server_url = shift;
  my $host_url   = shift;

  #$type = remove_subs($type);

  my @conf_files;

  if ( $type eq "configuration" ) {
    @conf_files = ( get_dir( "Main info", $server_url ), get_dir( "SGA info", $server_url ), get_dir( "Tablespace info", $server_url ), get_dir( "Installed DB components", $server_url ), get_dir( "Upgrade, Downgrade info", $server_url ), get_dir( "PSU, patches info", $server_url ) );

    #    @conf_files = (get_dir("Main info", $server_url), get_dir("SGA info", $server_url), get_dir("Tablespace info", $server_url), get_dir("Registry info", $server_url), get_dir("Update RDBMS info", $server_url));
  }
  elsif ( $type eq "configuration_dg" ) {
    @conf_files = ( get_dir( "Main info", $server_url ), get_dir( "SGA info", $server_url ), get_dir( "Tablespace info", $server_url ), get_dir( "Installed DB components", $server_url ), get_dir( "Upgrade, Downgrade info", $server_url ), get_dir( "PSU, patches info", $server_url ), get_dir( "Dataguard", $server_url ) );

  }
  elsif ( $type eq "viewone" ) {
    @conf_files = ( " ", get_dir( "viewone", $server_url ) );
  }

  # elsif($type eq "Installed DB components"){
  #   @conf_files = ($crblckbs,$crblckcngstd,$crgrntt,$crgrntcngstd,$currntblckbs,$crrntblckctd,$crrntgrntt,$crrntgrntctd);
  # }elsif($type eq "GCHVthree"){
  #    @conf_files = ($crblcklst,$currntblcklst,$crflr,$crrntrtry);
  #  }elsif($type eq "GCHVfour"){
  #    @conf_files = ($crntsplt,$crntmltblckrqst,$crntgrntbsy,$crdskr,$crmltblckrqst,$bffrbsacqr,$bffrbsrls);
  #  }elsif($type eq "GCHVfive"){
  #    @conf_files = ($gcrmstr);
  #  }
  elsif ( $type eq "viewtwo" ) {
    @conf_files = ( " ", get_dir( "viewtwo", $server_url ) );
  }
  elsif ( $type eq "viewthree" ) {
    @conf_files = ( " ", get_dir( "viewthree", $server_url ) );
  }
  elsif ( $type eq "viewfour" ) {
    @conf_files = ( " ", get_dir( "viewfour", $server_url ) );
  }
  elsif ( $type eq "viewfive" ) {
    @conf_files = ( " ", get_dir( "viewfive", $server_url ) );
  }
  elsif ( $type eq "datafiles" ) {
    @conf_files = ( get_dir( "IO Read Write per datafile", $server_url ) );
  }
  elsif ( $type eq "healthstatus" ) {
    @conf_files = ( get_dir( "Health status", $server_url, "T" ) );
  }
  elsif ( $type eq "waitclass" ) {
    @conf_files = ( get_dir( "Wait class Main", $server_url ) );
  }
  elsif ( $type eq "Interconnect" ) {
    @conf_files = ( " ", get_dir( "Interconnect info", $server_url ) );
  }
  elsif ( $type eq "Capacity" ) {
    @conf_files = ( " ", " ", get_dir( "Online Redo Logs", $server_url ) );
  }
  elsif ( $type eq "configuration_S" ) {
    @conf_files = ( get_dir( "Main info", $server_url ), get_dir( "SGA info", $server_url ), get_dir( "Tablespace info", $server_url ), get_dir( "Installed DB components", $server_url ), get_dir( "Upgrade, Downgrade info", $server_url ), get_dir( "PSU, patches info", $server_url ) );
  }
  elsif ( $type eq "configuration_Multitenant" ) {
    @conf_files = ( get_dir( "Main info", $server_url ), get_dir( "PDB info", $server_url ), get_dir( "SGA info", $server_url ), get_dir( "Installed DB components", $server_url ), get_dir( "Upgrade, Downgrade info", $server_url ), get_dir( "PSU, patches info", $server_url ) );
  }
  elsif ( $type eq "configuration_Total" ) {
    $host_url =~ s/groups_//g;
    my @act_groups = split( /,/, $host_url );
    my $group      = "";
    if ( $act_groups[1] ) {
      $group = "$act_groups[1]";
    }
    else {
      $group = "$act_groups[0]";
    }
    @conf_files = ( get_dir( "Main info", $server_url, "T", "_$group" ), " ", " ", " ", " ", " ", " ", get_dir( "Tablespace info", $server_url, "T", "_$group" ) );
  }
  elsif ( $type eq "configuration_PDB" ) {
    $host_url =~ s/groups_//g;
    my @act_groups = split( /,/, $host_url );
    my $group      = "";
    if ( $act_groups[1] ) {
      $group = "$act_groups[1]";
    }
    else {
      $group = "$act_groups[0]";
    }
    @conf_files = ( get_dir( "PDB info", $server_url, "pdb", "_$group" ), get_dir( "Tablespace info", $server_url, "pdb", "_$group" ), get_dir( "SGA info", $server_url, "pdb", "_$group" ) );
  }
  else {
    @conf_files = ( get_dir( "Main info", $server_url ), get_dir( "SGA info", $server_url ), get_dir( "Tablespace info", $server_url ), get_dir( "IO Read Write per datafile", $server_url ), get_dir( "Wait class Main", $server_url ), get_dir( "Data rate per service name", $server_url ) );
  }

  return \@conf_files;
}

sub get_dir {
  my $type        = shift;
  my $alias       = shift;
  my $total_check = shift;
  my $g_check     = shift;
  my $group       = defined $g_check ? $g_check : "_OracleDB";

  if ( $total_check and $total_check ne "pdb" ) {
    $alias = "Totals";
  }
  my $conf_dir = "$odb_dir/$alias/configuration";

  my %elif = (
    "Main info" => "$conf_dir/main" . $group . ".html",
    "SGA info" => "$conf_dir/sga.html",
    "Tablespace info" => "$conf_dir/tablespace" . $group . ".html",
    "IO Read Write per datafile" => "$conf_dir/iorw.html",  
    "Wait class Main"  => "$conf_dir/waitclass.html",
    "Registry info" => "$conf_dir/reginfo.html",
    "Update RDBMS info" => "$conf_dir/urdbms.html",
    "Installed DB components" => "$conf_dir/insdbcomp.html",
    "Upgrade, Downgrade info" => "$conf_dir/updowngrade.html",
    "PSU, patches info" => "$conf_dir/psu.html",
    "Data rate per service name" => "$conf_dir/dtratesrvc.html",
    "Interconnect info" => "$conf_dir/intcon.html",
    "viewone" => "$conf_dir/viewone.html",
    "viewtwo" => "$conf_dir/viewtwo.html",
    "viewthree" => "$conf_dir/viewthree.html",
    "viewfour" => "$conf_dir/viewfour.html",
    "viewfive" => "$conf_dir/viewfive.html",
    "Health status" => "$conf_dir/healthstatus.html",
    "PDB info" => "$conf_dir/pdbinf" . $group . ".html",
    "Alert History" => "$conf_dir/alrthst" . $group . ".html",
    'Dataguard' => "$conf_dir/dg.html",
    'Online Redo Logs' => "$conf_dir/ord.html",
  );

  return defined $elif{$type} ? $elif{$type} : "err";


}

sub get_arc {
  my ( $can_read, $ref ) = Xorux_lib::read_json("$odb_dir/Totals/arc.json");
  if ($can_read) {
    return $ref;
  }
  else {
    return "0";
  }
}

sub get_groups {
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

sub get_alias {
  my $ip       = shift;
  my $instance = shift;
  my $instance_names;
  my ( $can_read, $ref ) = Xorux_lib::read_json("$odb_dir/Totals/instance_names_total.json");
  undef $instance_names;
  if ($can_read) {
    $instance_names = $ref;
  }
  else {
    warn "Couldn't open $odb_dir/Totals/instance_names_total.json";
    return "";
  }

  for my $alias ( %{$instance_names} ) {
    if ( $instance_names->{$alias}->{$ip} and $instance_names->{$alias}->{$ip} eq $instance ) {
      return $alias;
    }
  }
}

sub get_instance_names_total {
  my ( $can_read, $ref ) = Xorux_lib::read_json("$odb_dir/Totals/instance_names_total.json");
  if ($can_read) {
    return $ref;
  }
  else {
    warn "Couldn't open $odb_dir/Totals/instance_names_total.json";
    return "";
  }
}

sub get_groups_pa {
  my ( $can_read, $ref ) = Xorux_lib::read_json("$odb_dir/Totals/groups_pa.json");
  if ($can_read) {
    return $ref;
  }
  else {
    warn "Couldn't open $odb_dir/Totals/groups_pa.json";
    return "";
  }
}

sub get_dbtype {
  my $alias = shift;

  require HostCfg;
  my %creds = %{ HostCfg::getHostConnections("OracleDB") };

  if ( $creds{$alias} ) {
    return $creds{$alias}{type};
  }
  else {
    return "";
  }

}

sub get_dbuuid {
  my $alias = shift;

  require HostCfg;
  my %creds = %{ HostCfg::getHostConnections("OracleDB") };
  if ( $creds{$alias} ) {
    return $creds{$alias}{uuid};
  }
  else {
    return "";
  }
}

sub graph_legend {
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
      'brackets'   => '[%]',
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

