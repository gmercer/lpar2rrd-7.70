use 5.008_008;

use strict;
use warnings;

use RRDp;
use Data::Dumper;
use File::Copy;
use Xorux_lib qw(error read_json write_json);
use POSIX ":sys_wait_h";
use OracleDBLoadDataModule;
use OracleDBDataWrapper;

defined $ENV{INPUTDIR} || Xorux_lib::error( "INPUTDIR undefined, probably have not read etc/lpar2rrd.cfg " . __FILE__ . ":" . __LINE__ ) && exit 1;

my $sh_out = "";
if (@ARGV) {
  $sh_out = $ARGV[0];
}
my @sh_arr   = split( /,/, $sh_out );
my $sh_alias = $sh_arr[1];
my $sh_type  = $sh_arr[0];
my $sh_host  = $sh_arr[2];
if ( !$sh_alias ) {
  warn( "No OracleDB host retrieved from params." . __FILE__ . ":" . __LINE__ ) && exit 1;
}

my $alias = $sh_alias;
print "\n\n$alias\n\n";
my $upgrade          = defined $ENV{UPGRADE} ? $ENV{UPGRADE} : 0;
my $rrdtool          = $ENV{RRDTOOL};
my $inputdir         = $ENV{INPUTDIR};
my $tmpdir           = "$inputdir/tmp";
my $odb_dir          = "$inputdir/data/OracleDB";
my $iostats_dir      = "$odb_dir/$alias/iostats";
my $cpu_info_dir     = "$odb_dir/$alias/CPU_info";
my $network_dir      = "$odb_dir/$alias/Network";
my $ratio_dir        = "$odb_dir/$alias/Ratio";
my $sql_query_dir    = "$odb_dir/$alias/SQL_query";
my $session_info_dir = "$odb_dir/$alias/Session_info";
my $data_rate_dir    = "$odb_dir/$alias/Data_rate";
my $RAC_dir          = "$odb_dir/$alias/RAC";
my $DL_dir           = "$odb_dir/$alias/Disk_latency";
my $waitclass_dir    = "$odb_dir/$alias/Wait_class";
my $datafiles_dir    = "$odb_dir/$alias/Datafiles";
my $services_dir     = "$odb_dir/$alias/Services";
my $conf_dir         = "$odb_dir/$alias/configuration";
my $capacity_dir     = "$odb_dir/$alias/Capacity";
my $alert_dir        = "$odb_dir/$alias/Alerts";
my $totals_dir       = "$odb_dir/Totals";
my $hosts_dir        = "$totals_dir/Hosts/";

my $act_time = time;

my $data_update_timeout = 1800;
my %processed_on_host;
my %conf_values;
my $rrd_start_time;
my $data;
my $db_hostname;
my $type_save;
my %data_to_export;

my %not_a_counter = (
  'GC CR Block Received Per Second'       => "",
  'GC Current Block Received Per Second'  => "",
  'Global Cache Average CR Get Time'      => "",
  'Cell Physical IO Interconnect Bytes'   => "",
  'Global Cache Average Current Get Time' => "",
  'LOG files write latency'               => "",
  'DB files write latency'                => "",
  'GC Avg CR Block receive ms'            => "",
  'GC Avg CUR Block receive ms'           => "",
  'gc cr blocks received'                 => "",
  'gc current block receive time'         => "",
  'gc current blocks received'            => "",
  'gc cr block receive time'              => "",
  'Current Open Cursors Count'            => "",
  'Current Logons Count'                  => ""
);

my %alerted_metrics = (
  'Current Logons Count' => "CLC",
);

my $LPAR2RRD_FORK_MAX = defined $ENV{LPAR2RRD_FORK_MAX} && $ENV{LPAR2RRD_FORK_MAX} =~ /^\d{1,3}$/ ? $ENV{LPAR2RRD_FORK_MAX} : 16;

################################################################################

unless ( -d $odb_dir ) {
  mkdir( "$odb_dir", 0755 ) || Xorux_lib::error( "Cannot mkdir $odb_dir: $!" . __FILE__ . ":" . __LINE__ ) && exit;
}
unless ( -d $cpu_info_dir ) {
  mkdir( "$cpu_info_dir", 0755 ) || Xorux_lib::error( "Cannot mkdir $cpu_info_dir: $!" . __FILE__ . ":" . __LINE__ ) && exit;
}
unless ( -d $network_dir ) {
  mkdir( $network_dir, 0755 ) || Xorux_lib::error( "Cannot mkdir $network_dir: $!" . __FILE__ . ":" . __LINE__ ) && exit;
}
unless ( -d $ratio_dir ) {
  mkdir( $ratio_dir, 0755 ) || Xorux_lib::error( "Cannot mkdir $ratio_dir: $!" . __FILE__ . ":" . __LINE__ ) && exit;
}
unless ( -d $sql_query_dir ) {
  mkdir( $sql_query_dir, 0755 ) || Xorux_lib::error( "Cannot mkdir $sql_query_dir: $!" . __FILE__ . ":" . __LINE__ ) && exit;
}
unless ( -d $data_rate_dir ) {
  mkdir( $data_rate_dir, 0755 ) || Xorux_lib::error( "Cannot mkdir $data_rate_dir: $!" . __FILE__ . ":" . __LINE__ ) && exit;
}
unless ( -d $session_info_dir ) {
  mkdir( $session_info_dir, 0755 ) || Xorux_lib::error( "Cannot mkdir $session_info_dir: $!" . __FILE__ . ":" . __LINE__ ) && exit;
}
unless ( -d $waitclass_dir ) {
  mkdir( $waitclass_dir, 0755 ) || Xorux_lib::error( "Cannot mkdir $waitclass_dir: $!" . __FILE__ . ":" . __LINE__ ) && exit;
}
unless ( -d $services_dir ) {
  mkdir( $services_dir, 0755 ) || Xorux_lib::error( "Cannot mkdir $services_dir: $!" . __FILE__ . ":" . __LINE__ ) && exit;
}
unless ( -d $DL_dir ) {
  mkdir( $DL_dir, 0755 ) || Xorux_lib::error( "Cannot mkdir $DL_dir: $!" . __FILE__ . ":" . __LINE__ ) && exit;
}
unless ( -d $alert_dir ) {
  mkdir( $alert_dir, 0755 ) || Xorux_lib::error( "Cannot mkdir $alert_dir: $!" . __FILE__ . ":" . __LINE__ ) && exit;
}
unless ( -d $capacity_dir ) {
  mkdir( $capacity_dir, 0755 ) || Xorux_lib::error( "Cannot mkdir $capacity_dir: $!" . __FILE__ . ":" . __LINE__ ) && exit;
}

if ( $sh_type eq "RAC" or $sh_type eq "RAC_Multitenant" ) {
  unless ( -d $RAC_dir ) {
    mkdir( $RAC_dir, 0755 ) || Xorux_lib::error( "Cannot mkdir $RAC_dir: $!" . __FILE__ . ":" . __LINE__ ) && exit;
  }
  unless ( -d $waitclass_dir ) {
    mkdir( $waitclass_dir, 0755 ) || Xorux_lib::error( "Cannot mkdir $waitclass_dir: $!" . __FILE__ . ":" . __LINE__ ) && exit;
  }
  unless ( -d $datafiles_dir ) {
    mkdir( $datafiles_dir, 0755 ) || Xorux_lib::error( "Cannot mkdir $datafiles_dir: $!" . __FILE__ . ":" . __LINE__ ) && exit;
  }
}
unless ( -d $iostats_dir ) {
  print "oracleDB-json2rrd.pl : no iostats dir, skip\n";
  exit 1;
}

#my ( $mapping_code, $linux_uuids ) = -f $agents_uuid_file ? Xorux_lib::read_json( $agents_uuid_file ) : ( 0, undef );

#update_backup_files();
#load_metadata();
load_perf_data();

exit 0;

sub load_perf_data {
  my @pids;
  my $pid;

  my $rrdtool_version = 'Unknown';
  $_ = `$rrdtool`;
  if (/^RRDtool ([1-9]*\.[0-9]*(\.[0-9]*)?)/) {
    $rrdtool_version = $1;
  }
  print "RRDp    version   : $RRDp::VERSION\n";
  print "RRDtool version   : $rrdtool_version\n";
  my @files;
  opendir( DH, $iostats_dir ) || Xorux_lib::error("Could not open '$iostats_dir' for reading '$!'\n") && exit;
  @files = sort( grep /.*oracledb_.*\.json/, readdir DH );

  #  print Dumper \@files;
  closedir(DH);

  #  my $file_count = scalar @files;
  #  my $fork_no    = $file_count > $LPAR2RRD_FORK_MAX ? $LPAR2RRD_FORK_MAX : $file_count;
  #
  #  print "oracleDB-json2rrd.pl : processing $file_count perf files with $fork_no forks\n";
  #
  #  my $i = 0;
  #  while ( $i < $fork_no ) {
  #    unless ( defined( $pid = fork() ) ) {
  #      Xorux_lib::error( "Error: failed to fork:" . __FILE__ . ":" . __LINE__ );
  #      next;
  #    }
  #    else {
  #      if ( $pid ) {
  #        push @pids, $pid;
  #        $i++;
  #      }
  #      else {
  #        last;
  #      }
  #    }
  #  }
  #
  #  unless ( $pid ) {
  #    while ( $i < $file_count ) {
  #      load_perf_file( $files[$i] );
  #      $i += $LPAR2RRD_FORK_MAX;
  #    }
  #
  #    exit 0;
  #  }
  #
  #  for $pid (@pids) {
  #    waitpid( $pid, 0 );
  #  }
  #my $perf = "oracledb_perf.json";
  #  #if($files[0]){
  load_waitclass_file( "perflikeconf.json", "Wait class Main" );
  load_servicedata_file( "perflikeconf.json", "Data rate per service name" );
  my $perf = $files[$#files];

  #  if($sh_type eq "RAC_Multitenant" and $sh_alias eq "DSB"){
  #    load_perf_file("oracledb.json");
  #  }else{
  load_perf_file($perf);

  #  }
  if ( ( defined $ENV{BAKOTECH} and $ENV{BAKOTECH} eq "1" ) or ( defined $ENV{ULTRA} and $ENV{ULTRA} eq "1" ) ) {
    require OracleDBExport;

    OracleDBExport::export( \%data_to_export );
  }

  if ( -f "$iostats_dir/$perf" ) {
    unlink "$iostats_dir/$perf";
  }

  #  if ($sh_type eq "PDB"){
  #    load_waitclass_file("perflikeconf.json","Wait class Main");
  #  }

  #  move("$iostats_dir/$perf", "$tmpdir/oracledb-perf-last.json");
  #}
  #if($sh_type eq ""){
  #if($sh_type eq "RAC"){
  #      load_conf_file("conf.json","IO Read Write per datafile");
  #}
  return 1;
}

sub load_perf_file {
  my $file = shift;
  my ( $can_read, $ref );

  # read perf file
  if ( -f "$iostats_dir/$file" ) {
    ( $can_read, $ref ) = Xorux_lib::read_json("$iostats_dir/$file");
    backup_file($file);
  }
  else {
    Xorux_lib::error( "Perf file for $sh_alias doesn't exist " . __FILE__ . ":" . __LINE__ ) && exit 1;
  }

  unless ($can_read) {
    print "oracleDB-json2rrd.pl : file $file cannot be loaded\n";
    Xorux_lib::error( "Perf file $file for $sh_alias cannot be loaded " . __FILE__ . ":" . __LINE__ );
    return 0;
  }
  RRDp::start "$rrdtool";

  my ( $can_read_hst, $ref_hst, $host_names );
  ( $can_read_hst, $ref_hst ) = Xorux_lib::read_json("$odb_dir/$alias/host_names.json");

  print Dumper \$ref;
  $data = $ref;
  print "oracleDB-json2rrd.pl : processing file $file\n";

  if ( $sh_type eq "RAC" or $sh_type eq "RAC_Multitenant" ) {
    $type_save = $sh_type;
    $sh_type   = "RAC";
    my @instances;
    for my $instance ( keys %{ $data->{$sh_type} } ) {
      push( @instances, $instance );
      unless ( $instance eq "info" ) {
        for my $type ( keys %{ $data->{$sh_type}->{$instance} } ) {
          my $rrd_path = "";
          my $type_ns  = $type;
          $type_ns =~ s/ /_/g;
          if ( $type eq "RAC" or $type eq "Disk latency" or $type eq "PDB" ) { next; }
          print "\n$type\n";

          $rrd_path = OracleDBDataWrapper::get_filepath_rrd( { type => $type, uuid => $alias, id => $instance, skip_acl => 1 } );
          print "\n$rrd_path\n";

          data_to_rrd( $rrd_path, $data->{$sh_type}->{info}->{timestamp}, $type_ns, \%{ $data->{$sh_type}->{$instance}->{$type} }, $instance );
          my $is_host_metric = OracleDBDataWrapper::is_host_metric($type);
          if ($is_host_metric) {
            if ($can_read_hst) {
              $host_names = $ref_hst;
              my $host_rrd_path = $hosts_dir;
              $host_rrd_path .= "$alias-_-$instance-_-$type_ns.rrd";
              data_to_rrd( $host_rrd_path, $data->{$sh_type}->{info}->{timestamp}, $type_ns, \%{ $data->{$sh_type}->{$instance}->{$type} }, $instance );

            }
          }
        }
        load_event_file( "perflikeconf.json", "RAC",          $instance );
        load_event_file( "perflikeconf.json", "Disk latency", $instance );
      }
      if ( $type_save eq "RAC_Multitenant" ) {
        $sh_type = "PDB";
        for my $pdb_instance ( keys %{ $data->{RAC}->{$instance}->{$sh_type} } ) {
          for my $type ( keys %{ $data->{RAC}->{$instance}->{$sh_type}->{$pdb_instance} } ) {
            my $rrd_path = "";
            my $type_ns  = $type;
            $type_ns =~ s/ /_/g;
            if ( $type eq "Disk latency" or $type eq "Data rate" or $type eq "SQL query" or $type eq "Session info" ) {
              next;
            }
            print "\n$type\n";

            $rrd_path = OracleDBDataWrapper::get_filepath_rrd( { type => $type, uuid => $alias, id => "$instance,$pdb_instance", skip_acl => 1 } );
            print "\n$rrd_path\n";
            data_to_rrd( $rrd_path, $data->{RAC}->{info}->{timestamp}, $type_ns, \%{ $data->{RAC}->{$instance}->{$sh_type}->{$pdb_instance}->{$type} }, $instance );

          }
          load_event_file( "perflikeconf.json", "Disk latency", "$instance,$pdb_instance", "PDB" );
          work_counters( "Data rate",    "$instance,$pdb_instance", $data->{RAC}->{$instance}->{$sh_type}->{$pdb_instance}->{"Data rate"},    $pdb_instance );
          work_counters( "SQL query",    "$instance,$pdb_instance", $data->{RAC}->{$instance}->{$sh_type}->{$pdb_instance}->{"SQL query"},    $pdb_instance );
          work_counters( "Session info", "$instance,$pdb_instance", $data->{RAC}->{$instance}->{$sh_type}->{$pdb_instance}->{"Session info"}, $pdb_instance );

          #work_counters("RAC", $instance, $data->{$sh_type}->{$instance}->{RAC});
        }
        $sh_type = "RAC";
      }
    }
    OracleDBAlerting::check_config( $alias, $data, $sh_type );
  }
  elsif ( $sh_type eq "Multitenant" ) {
    for my $type ( keys %{ $data->{$sh_type} } ) {
      if ( $type eq "Disk latency" or $type eq "info" or $type eq "Cache" ) {
        next;
      }
      my $rrd_path = "";
      my $type_ns  = $type;
      $type_ns =~ s/ /_/g;
      print "\n$type\n";

      $rrd_path = OracleDBDataWrapper::get_filepath_rrd( { type => $type, uuid => $alias, id => $sh_host, skip_acl => 1 } );
      print "\ntype $type alias $alias host $sh_host\n";
      if ( !$rrd_path ) {
        warn "Couldnt get rrd path for type $type alias $alias host $sh_host";
        next;
      }
      print "\n$rrd_path\n";
      unless ( $type_ns eq "info" ) {
        data_to_rrd( $rrd_path, $data->{$sh_type}->{info}->{timestamp}, $type_ns, \%{ $data->{$sh_type}->{$type} }, $sh_host );
        my $is_host_metric = OracleDBDataWrapper::is_host_metric($type);
        if ($is_host_metric) {
          if ($can_read_hst) {
            $host_names = $ref_hst;
            my $host_rrd_path = $hosts_dir;
            $host_rrd_path .= "$alias-_-$sh_host-_-$type_ns.rrd";
            data_to_rrd( $host_rrd_path, $data->{$sh_type}->{info}->{timestamp}, $type_ns, \%{ $data->{$sh_type}->{$type} }, $sh_host );
          }
        }
      }
    }
    load_event_file( "perflikeconf.json", "Disk latency", $sh_host );

    $sh_type = "PDB";
    for my $instance ( keys %{ $data->{$sh_type} } ) {
      for my $type ( keys %{ $data->{$sh_type}->{$instance} } ) {
        my $rrd_path = "";
        my $type_ns  = $type;
        $type_ns =~ s/ /_/g;
        if ( $type eq "Disk latency" or $type eq "Data rate" or $type eq "SQL query" or $type eq "Session info" ) {
          next;
        }
        print "\n$type\n";

        $rrd_path = OracleDBDataWrapper::get_filepath_rrd( { type => $type, uuid => $alias, id => $instance, skip_acl => 1 } );
        print "\n$rrd_path\n";
        data_to_rrd( $rrd_path, $data->{Multitenant}->{info}->{timestamp}, $type_ns, \%{ $data->{$sh_type}->{$instance}->{$type} }, $instance );
      }
      work_counters( "Data rate",    $instance, $data->{$sh_type}->{$instance}->{"Data rate"},    $instance );
      work_counters( "SQL query",    $instance, $data->{$sh_type}->{$instance}->{"SQL query"},    $instance );
      work_counters( "Session info", $instance, $data->{$sh_type}->{$instance}->{"Session info"}, $instance );
      $sh_type = "Multitenant";
      load_event_file( "perflikeconf.json", "Disk latency", $instance, "PDB" );
      $sh_type = "PDB";

      #work_counters("RAC", $instance, $data->{$sh_type}->{$instance}->{RAC});
    }
  }
  else {
    for my $type ( keys %{ $data->{$sh_type} } ) {
      if ( $type eq "Disk latency" or $type eq "info" or $type eq "DG" ) {
        next;
      }
      my $rrd_path = "";
      my $type_ns  = $type;
      $type_ns =~ s/ /_/g;
      print "\n$type\n";

      $rrd_path = OracleDBDataWrapper::get_filepath_rrd( { type => $type, uuid => $alias, id => $sh_host, skip_acl => 1 } );
      print "\ntype $type alias $alias host $sh_host\n";
      if ( !$rrd_path ) {
        warn "Couldnt get rrd path for type $type alias $alias host $sh_host";
        next;
      }
      print "\n$rrd_path\n";
      unless ( $type_ns eq "info" ) {
        data_to_rrd( $rrd_path, $data->{$sh_type}->{info}->{timestamp}, $type_ns, \%{ $data->{$sh_type}->{$type} }, $sh_host );
        my $is_host_metric = OracleDBDataWrapper::is_host_metric($type);
        if ($is_host_metric) {
          if ($can_read_hst) {
            $host_names = $ref_hst;
            my $host_rrd_path = $hosts_dir;
            $host_rrd_path .= "$alias-_-$sh_host-_-$type_ns.rrd";
            data_to_rrd( $host_rrd_path, $data->{$sh_type}->{info}->{timestamp}, $type_ns, \%{ $data->{$sh_type}->{$type} }, $sh_host );
          }
        }
      }
    }
    if ( $data->{$sh_type}->{DG} ) {
      add_dataguard($data);
    }
    load_event_file( "perflikeconf.json", "Disk latency", $sh_host );
    OracleDBAlerting::check_config( $alias, \%{ $data->{$sh_type} }, $sh_type, $sh_host );

  }

  RRDp::end;
  return 1;

  #  }
}

sub add_dataguard {
  my $data = shift;

  for my $instance ( keys %{ $data->{$sh_type}->{DG} } ) {
    for my $type ( keys %{ $data->{$sh_type}->{DG}->{$instance} } ) {
      next if ( $type eq "Instance name" or $type eq "Host name" );
      my $rrd_path = "";
      my $type_ns  = $type;
      $type_ns =~ s/ /_/g;
      if ( $type eq "Disk latency" ) {
        next;
      }
      print "\n$type\n";

      $rrd_path = OracleDBDataWrapper::get_filepath_rrd( { type => $type, uuid => $alias, id => "DG$instance", skip_acl => 1 } );
      print "\n$rrd_path\n";
      data_to_rrd( $rrd_path, $data->{$sh_type}->{info}->{timestamp}, $type_ns, \%{ $data->{$sh_type}->{DG}->{$instance}->{$type} }, $instance );
    }
  }
}

sub data_to_rrd {
  my $_rrd_path = shift;
  my $timestamp = shift;
  my $_type_ns  = shift;
  my $_data     = shift;
  my $_instance = shift;
  my $_alias    = $alias;

  if ( !defined $_rrd_path or $_rrd_path eq "" ) {
    warn "RRD path doesnt exist for $_type_ns";
    return;
  }

  unless ( -f $_rrd_path ) {
    OracleDBLoadDataModule::create_rrd( $_rrd_path, $act_time, $_type_ns );
  }
  print Dumper \$_data;
  OracleDBLoadDataModule::update_rrd( $_rrd_path, $timestamp, $_type_ns, $_data, $alias );

  if ( ( defined $ENV{BAKOTECH} and $ENV{BAKOTECH} eq "1" ) or ( defined $ENV{ULTRA} and $ENV{ULTRA} eq "1" ) ) {
    require OracleDBExport;
    my %types_to_export = OracleDBExport::get_types();
    if ( $types_to_export{$_type_ns} ) {
      $_data->{timestamp} = $timestamp;
      for my $metric ( keys %{$_data} ) {
        $data_to_export{ "$alias" . "," . "$_instance" }{$metric} = $_data->{$metric};
      }

      #OracleDBExport::export($_instance, $timestamp, $_type_ns, $_data, $alias);
    }
  }
}

sub work_counters {
  my $type      = shift;
  my $instance  = shift;
  my $perf_data = shift;
  my $pdb       = shift;
  my %perf_data = defined $perf_data ? %{$perf_data} : undef;
  my $file_serv;
  my $denom = 1;
  if ( $type eq "RAC" or $type eq "RAC_Multitenant" ) {
    $file_serv = "$RAC_dir/$instance-lastRAC.json";
  }
  elsif ( $type eq "Disk latency" ) {
    $file_serv = "$DL_dir/$instance-lastDisk_latency.json";
  }
  elsif ( $type eq "Data rate" ) {
    $file_serv = "$data_rate_dir/$instance-lastData_rate.json";
    $denom     = 300;
  }
  elsif ( $type eq "SQL query" ) {
    $file_serv = "$sql_query_dir/$instance-lastSQL_query.json";
    $denom     = 300;
  }
  elsif ( $type eq "Session info" ) {
    $file_serv = "$session_info_dir/$instance-lastSession_info.json";
    $denom     = 300;
  }

  my $type_ns = $type;
  $type_ns =~ s/ /_/g;

  my ( $p_can_read, $p_ref );
  if ( -f $file_serv ) {
    ( $p_can_read, $p_ref ) = Xorux_lib::read_json($file_serv);

    #backup_file( $file );
  }
  else {
    Xorux_lib::write_json( $file_serv, \%perf_data );
  }
  if ($p_can_read) {
    my %p_data = %{$p_ref};

    #print "\n$alias - $instance\n";
    #print Dumper \%p_data;
    #print "$alias - $instance\n";
    #print Dumper \%perf_data;
    for my $metric ( keys %p_data ) {
      if ( $perf_data{$metric} ) {
        if ( exists $not_a_counter{$metric} ) {
          $p_data{$metric} = $perf_data{$metric};
        }
        else {
          $p_data{$metric} = ( sprintf( "%e", $perf_data{$metric} ) - sprintf( "%e", $p_data{$metric} ) ) / $denom;    #$perf_data{$metric};
        }
      }
    }
    unlink "$file_serv";
    Xorux_lib::write_json( $file_serv, \%perf_data );
    my $rrd_path = "";
    print "\n$type\n";
    my $inst = "";
    if ( $sh_type eq "RAC" or $sh_type eq "RAC_Multitenant" ) {
      $inst     = "$instance";
      $rrd_path = OracleDBDataWrapper::get_filepath_rrd( { type => $type, uuid => $alias, id => $instance, skip_acl => 1 } );
    }
    elsif ( $pdb and $sh_type eq "PDB" ) {
      $inst     = "$instance";
      $rrd_path = OracleDBDataWrapper::get_filepath_rrd( { type => $type, uuid => $alias, id => $instance, skip_acl => 1 } );
    }
    else {
      $inst     = $sh_host;
      $rrd_path = OracleDBDataWrapper::get_filepath_rrd( { type => $type, uuid => $alias, id => $sh_host, skip_acl => 1 } );
    }
    data_to_rrd( $rrd_path, $act_time, $type_ns, \%p_data, $inst );
  }
}

sub load_conf_file {
  my $file      = shift;
  my $stat_type = shift;
  my ( $can_read, $ref );

  # read perf file
  if ( -f "$conf_dir/$file" ) {
    ( $can_read, $ref ) = Xorux_lib::read_json("$conf_dir/$file");

    #backup_file( $file );
  }

  unless ($can_read) {
    print "oracleDB-json2rrd.pl : file $file cannot be loaded\n";
    Xorux_lib::error( "Conf file $file cannot be loaded " . __FILE__ . ":" . __LINE__ );
    return 0;
  }

  RRDp::start "$rrdtool";

  $data = $ref;
  my %dict;

  #print Dumper \$ref;
  print "oracleDB-json2rrd.pl : processing file $file\n";
  for my $instance ( keys %{ $data->{RAC}->{$stat_type} } ) {

    #print Dumper \%{$data->{RAC}->{"Wait class Main"}};
    if ( $instance eq "Idle" ) {
      next;
    }
    my $rrd_path = "";
    my $type_ns  = $stat_type;
    $type_ns =~ s/ /_/g;
    print "\n$instance\n";
    my $name = $instance;
    $name =~ s/\///g;
    print "\n$name\n";
    my $uuid = OracleDBDataWrapper::md5_string($name);

    #print "\n$uuid\n";
    #if($type eq "RAC"){ next; }
    if ( $stat_type eq "IO Read Write per datafile" ) {
      $dict{$uuid} = $instance;
    }
    else {
      $dict{$uuid} = $name;
    }
    $rrd_path = OracleDBDataWrapper::get_filepath_rrd( { type => $type_ns, uuid => $alias, skip_acl => 1 } );
    $rrd_path .= "$uuid.rrd";
    print $rrd_path;
    data_to_rrd( $rrd_path, $act_time, $type_ns, \%{ $data->{RAC}->{$stat_type}->{$instance}->[0] }, $instance );
  }
  RRDp::end;
  if ( $stat_type eq "IO Read Write per datafile" ) {
    Xorux_lib::write_json( "$datafiles_dir/dict.json", \%dict );
  }
  else {
    Xorux_lib::write_json( "$waitclass_dir/dict.json", \%dict );
  }
  return 1;
}

sub load_event_file {
  my $file    = shift;
  my $type    = shift;
  my $ip      = shift;
  my $pdb     = shift;
  my $type_ns = $type;
  $type_ns =~ s/ /_/g;
  my $file_serv = "";
  my $foo_one   = "TIME_WAITED_MICRO";
  my $foo_two   = "TOTAL_WAITS";
  my $save_type = $sh_type;

  if ( $type_save and $type_save eq "RAC_Multitenant" ) {
    $save_type = "RAC";
  }

  if ( $type eq "RAC" or $type eq "RAC_Multitenant" ) {
    $file_serv = "$RAC_dir/$ip-lastRAC.json";
  }
  elsif ( $type eq "Disk latency" ) {
    $file_serv = "$DL_dir/$ip-lastDisk_latency.json";
  }
  my ( $can_read, $ref );

  # read perf file
  if ( -f "$conf_dir/$file" ) {
    ( $can_read, $ref ) = Xorux_lib::read_json("$conf_dir/$file");

    #backup_file( $file );
  }

  unless ($can_read) {
    print "oracleDB-json2rrd.pl : file $file cannot be loaded\n";
    Xorux_lib::error( "$file cannot be loaded $sh_alias " . __FILE__ . ":" . __LINE__ );
    return 0;
  }

  my $data_counters = $ref;

  #print "Maybe?";
  #print Dumper $data_counters;
  #  print "oracleDB-json2rrd.pl : processing file $file\n";
  my %perf_data;

  my $pages = OracleDBDataWrapper::get_pages($type_ns);
  for my $stat_type ( keys %{$pages} ) {

    #unless($type eq "Disk latency"){
    #  print"DEBUG $save_type $stat_type";
    #}
    #    print Dumper $data_counters;
    for my $instance ( keys %{ $data_counters->{$save_type}->{$stat_type} } ) {

      #print Dumper \$data->{RAC}->{$stat_type}->{$instance};
      my @act = @{ $data_counters->{$save_type}->{$stat_type}->{$instance} };

      #      print "$instance";
      #      print Dumper \@act;

      foreach my $stat (@act) {
        if ( $stat->{$foo_one} ) {
          $stat->{$foo_one} =~ s/,/./g;
          if ( $stat->{$foo_one} =~ /^\./ ) {
            $stat->{$foo_one} = "0" . "$stat->{$foo_one}";
          }
        }
        if ( $stat->{$foo_two} ) {
          $stat->{$foo_two} =~ s/,/./g;
          if ( $stat->{$foo_two} =~ /^\./ ) {
            $stat->{$foo_two} = "0" . "$stat->{$foo_two}";
          }
        }
        $perf_data{"$instance"}->{ $stat->{"Event"} }->{$foo_one} = $stat->{$foo_one};
        $perf_data{"$instance"}->{ $stat->{"Event"} }->{$foo_two} = $stat->{$foo_two};
      }
    }
  }
  my ( $p_can_read, $p_ref );

  #print "HERE";
  #print Dumper \%perf_data;

  if ( -f $file_serv ) {
    ( $p_can_read, $p_ref ) = Xorux_lib::read_json($file_serv);

    #backup_file( $file );
  }
  else {
    Xorux_lib::write_json( $file_serv, \%perf_data );
  }

  #print "FILE CONTENTS";
  #print Dumper $p_ref;
  if ( $p_ref and ref $p_ref ne "HASH" ) {
    unlink($file_serv);
  }
  if ( $p_can_read and ref $p_ref eq "HASH" ) {
    my %actual_data;
    my %old_perf_data = %{$p_ref};
    print "perf data\n";
    print Dumper \%perf_data;
    my $instance = "";
    if ( $sh_type eq "RAC" or $sh_type eq "RAC_Multitenant" ) {
      my ( $c_r, $instance_names ) = Xorux_lib::read_json("$odb_dir/$sh_alias/instance_names.json");
      if ($c_r) {
        $instance = $instance_names->{$ip};
      }
    }
    elsif ( $pdb and $sh_type eq "Multitenant" or $sh_type eq "PDB" ) {
      my ( $can_read_pdb, $ref_pdb ) = Xorux_lib::read_json("$odb_dir/$sh_alias/pdb_names.json");
      if ($can_read_pdb) {
        if ( $type_save and $type_save eq "RAC_Multitenant" ) {
          my @inst_parts = split( ",", $ip );
          $instance = "$inst_parts[0],$ref_pdb->{$inst_parts[1]}";
        }
        else {
          $instance = $ref_pdb->{$ip};
        }
      }
    }
    else {
      my ( $c_r, $instance_names ) = Xorux_lib::read_json("$odb_dir/$sh_alias/instance_names.json");
      if ($c_r) {
        $instance = $instance_names->{$ip};
      }
    }
    if ( $perf_data{$instance} and $old_perf_data{$instance} ) {
      for my $type ( keys %{ $perf_data{$instance} } ) {
        if ( $not_a_counter{$type} ) {
          $actual_data{$type} = $perf_data{$type};
        }
        else {
          my $val1 = sprintf( "%e", $perf_data{$instance}{$type}{"$foo_one"} ) - ( sprintf( "%e", $old_perf_data{$instance}{$type}{"$foo_one"} ) );
          my $val2 = sprintf( "%e", $perf_data{$instance}{$type}{"$foo_two"} ) - ( sprintf( "%e", $old_perf_data{$instance}{$type}{"$foo_two"} ) );
          if ( $val2 == 0 ) {
            $val2 = 1;
          }
          $actual_data{$type} = ( ( $val1 / $val2 ) / 1000 );
        }
      }
      my $rrd_path = OracleDBDataWrapper::get_filepath_rrd( { type => $type, uuid => $alias, id => $ip, skip_acl => 1 } );
      print "olddata\n";
      print Dumper \%old_perf_data;
      print "actual data\n";
      print Dumper \%actual_data;

      #warn "$rrd_path";
      data_to_rrd( $rrd_path, $act_time, $type_ns, \%actual_data, $ip );
    }
    Xorux_lib::write_json( $file_serv, \%perf_data );
  }
}

sub load_waitclass_file {
  my $file      = shift;
  my $stat_type = shift;
  my ( $can_read, $ref );
  my $save_type = $sh_type;
  if ( $save_type eq "RAC_Multitenant" ) {
    $save_type = "RAC";
  }

  # read perf file
  if ( -f "$conf_dir/$file" ) {

    ( $can_read, $ref ) = Xorux_lib::read_json("$conf_dir/$file");

    #backup_file( $file );
  }

  unless ($can_read) {
    print "oracleDB-json2rrd.pl : file $file cannot be loaded\n";
    Xorux_lib::error( "$file cannot be loaded $sh_alias " . __FILE__ . ":" . __LINE__ );
    return 0;
  }
  RRDp::start "$rrdtool";

  $data = $ref;
  my %dict;

  #  print "oracleDB-json2rrd.pl : processing file $file\n";
  my %perf_data;

  for my $instance ( keys %{ $data->{$save_type}->{$stat_type} } ) {
    if ( $instance =~ /CDB\$ROOT/ ) {
      next;
    }

    #print Dumper \$data->{RAC}->{$stat_type}->{$instance};
    my @act = @{ $data->{$save_type}->{$stat_type}->{$instance} };

    #   print Dumper \@act;
    foreach my $stat (@act) {
      $perf_data{ "$instance" . "," . $stat->{"Wait class"} }->{"TIME_WAITED"}    = $stat->{"TIME_WAITED"};
      $perf_data{ "$instance" . "," . $stat->{"Wait class"} }->{"TIME_WAITED_FG"} = $stat->{"TIME_WAITED_FG"};
      $perf_data{ "$instance" . "," . $stat->{"Wait class"} }->{"TOTAL_WAITS"}    = $stat->{"TOTAL_WAITS"};
      $perf_data{ "$instance" . "," . $stat->{"Wait class"} }->{"TOTAL_WAITS_FG"} = $stat->{"TOTAL_WAITS_FG"};
    }
  }
  my ( $p_can_read, $p_ref );
  my $file_serv = "$conf_dir/wait_classes_perf.json";
  if ( -f $file_serv ) {
    ( $p_can_read, $p_ref ) = Xorux_lib::read_json($file_serv);

    #backup_file( $file );
  }
  else {
    Xorux_lib::write_json( $file_serv, \%perf_data );
  }
  if ( $p_ref and ref $p_ref ne "HASH" ) {
    unlink($file_serv);
  }
  if ( $p_can_read and ref $p_ref eq "HASH" ) {
    my %p_data = %{$p_ref};
    my %actual_data;
    print Dumper \%p_data;

    #print Dumper \%perf_data;
    for my $type ( keys %perf_data ) {
      my $rrd_path = "";
      my $type_ns  = "$stat_type";
      $type_ns =~ s/ /_/g;

      #warn "\n\n$timediff\n\n";
      $type =~ s/-/,/g;
      my $val_one_fg = defined $perf_data{$type}{"TIME_WAITED_FG"} ? $perf_data{$type}{"TIME_WAITED_FG"} : 0;
      my $val_two_fg = defined $p_data{$type}{"TOTAL_WAITS_FG"}    ? $p_data{$type}{"TOTAL_WAITS_FG"}    : 1;
      $val_one_fg =~ s/,/./g;
      $val_two_fg =~ s/,/./g;
      $actual_data{$type}{"Average wait FG ms"} = ( sprintf( "%e", $val_one_fg ) * 10 ) / sprintf( "%e", $val_two_fg );
      my $val_one = defined $perf_data{$type}{"TIME_WAITED"} ? $perf_data{$type}{"TIME_WAITED"} : 0;
      my $val_two = defined $p_data{$type}{"TOTAL_WAITS"}    ? $p_data{$type}{"TOTAL_WAITS"}    : 1;
      $val_one =~ s/,/./g;
      $val_two =~ s/,/./g;
      $actual_data{$type}{"Average wait ms"} = ( sprintf( "%e", $val_one ) * 10 ) / sprintf( "%e", $val_two );
      Xorux_lib::write_json( $file_serv, \%perf_data );

      #      print "\n$type_ns\n";
      #      print "\n$type\n";
      my $name = $type;
      $name =~ s/\///g;
      print "\n$name\n";
      my $uuid = OracleDBDataWrapper::md5_string($name);

      #print "\n$uuid\n";
      $dict{$uuid} = $type;
      $rrd_path = OracleDBDataWrapper::get_filepath_rrd( { type => $type_ns, uuid => $alias, skip_acl => 1 } );
      $rrd_path .= "$uuid.rrd";

      #      print $rrd_path;
      data_to_rrd( $rrd_path, $act_time, $type_ns, \%{ $actual_data{$type} }, "none" );
    }
  }
  RRDp::end;

  #print Dumper \%dict;
  if ($p_can_read) {
    Xorux_lib::write_json( "$waitclass_dir/dict.json", \%dict );
  }
  return 1;
}

sub load_servicedata_file {
  my $file      = shift;
  my $stat_type = shift;
  my ( $can_read, $ref );
  my $save_type = $sh_type;
  if ( $save_type eq "RAC_Multitenant" ) {
    $save_type = "RAC";
  }

  # read perf file
  if ( -f "$conf_dir/$file" ) {
    ( $can_read, $ref ) = Xorux_lib::read_json("$conf_dir/$file");

    #backup_file( $file );
  }

  unless ($can_read) {
    print "oracleDB-json2rrd.pl : file $file cannot be loaded\n";
    Xorux_lib::error( "$file cannot be loaded $sh_alias " . __FILE__ . ":" . __LINE__ );
    return 0;
  }
  RRDp::start "$rrdtool";

  $data = $ref;
  my %dict;

  #  print "oracleDB-json2rrd.pl : processing file $file\n";
  my %perf_data;
  for my $instance ( keys %{ $data->{$save_type}->{$stat_type} } ) {

    #    print Dumper \$data->{RAC}->{$stat_type}->{$instance};
    my @act = @{ $data->{$save_type}->{$stat_type}->{$instance} };

    #   print Dumper \@act;
    foreach my $stat (@act) {
      $perf_data{ "$instance" . ",$stat->{SERVICE_NAME}" }{ $stat->{STAT_NAME} } = $stat->{'DB blocks'};
    }
  }
  my $file_serv = "$conf_dir/services_perf.json";
  my ( $p_can_read, $p_ref );
  if ( -f $file_serv ) {
    ( $p_can_read, $p_ref ) = Xorux_lib::read_json($file_serv);

    #backup_file( $file );
  }
  else {
    Xorux_lib::write_json( $file_serv, \%perf_data );
  }
  if ( $p_ref and ref $p_ref ne "HASH" ) {
    unlink($file_serv);
  }
  if ( $p_can_read and ref $p_ref eq "HASH" ) {
    my %p_data = %{$p_ref};
    print Dumper \%p_data;
    my $modtime  = ( stat($file_serv) )[9];
    my $timediff = time - $modtime;
    print $timediff;

    #print Dumper \%perf_data;
    for my $type ( keys %perf_data ) {
      my $rrd_path = "";
      my $type_ns  = "Services";
      $type_ns =~ s/ /_/g;

      #warn "\n\n$timediff\n\n";
      if ( defined $p_data{$type}{"physical writes"} and defined $perf_data{$type}{"physical writes"} ) {
        $p_data{$type}{"physical writes"}    =~ s/,/./g;
        $perf_data{$type}{"physical writes"} =~ s/,/./g;
        $p_data{$type}{"physical writes"} = ( sprintf( "%e", $perf_data{$type}{"physical writes"} ) - ( sprintf( "%e", $p_data{$type}{"physical writes"} ) ) ) / 300;
      }
      if ( defined $p_data{$type}{"physical reads"} and defined $perf_data{$type}{"physical reads"} ) {
        $p_data{$type}{"physical reads"}    =~ s/,/./g;
        $perf_data{$type}{"physical reads"} =~ s/,/./g;
        $p_data{$type}{"physical reads"} = ( sprintf( "%e", $perf_data{$type}{"physical reads"} ) - ( sprintf( "%e", $p_data{$type}{"physical reads"} ) ) ) / 300;
      }
      Xorux_lib::write_json( $file_serv, \%perf_data );

      #      print "\n$type_ns\n";
      #      print "\n$type\n";
      my $name = $type;
      $name =~ s/\///g;
      print "\n$name\n";
      my $uuid = OracleDBDataWrapper::md5_string($name);

      #print "\n$uuid\n";
      $dict{$uuid} = $type;
      $rrd_path = OracleDBDataWrapper::get_filepath_rrd( { type => $type_ns, uuid => $alias, skip_acl => 1 } );
      $rrd_path .= "$uuid.rrd";

      #      print $rrd_path;
      data_to_rrd( $rrd_path, $act_time, $type_ns, \%{ $p_data{$type} }, "none" );

      #   unless ( -f $rrd_path) {
      #     OracleDBLoadDataModule::create_rrd( $rrd_path, $act_time, $type_ns );
      #   }
      #   #print Dumper \$perf_data{$type};
      #   OracleDBLoadDataModule::update_rrd( $rrd_path, $act_time, $type_ns, \%{$p_data{$type}});
    }
  }
  RRDp::end;

  #print Dumper \%dict;
  if ($p_can_read) {
    Xorux_lib::write_json( "$services_dir/dict.json", \%dict );
  }
  return 1;
}

sub backup_file {

  # expects file name for the file, that's supposed to be moved from iostats_dir, with file
  # name "hostname_datetime.json" to tmpdir
  my $src_file = shift;
  my $source   = "$iostats_dir/$src_file";
  $src_file =~ s/\.json//;
  my $target = "$tmpdir/oracledbperf\_last1_$alias.json";

  move( $source, $target ) or Xorux_lib::error( "Cannot backup data $source: $!" . __FILE__ . ":" . __LINE__ );

  return 1;
}    ## sub backup_file
