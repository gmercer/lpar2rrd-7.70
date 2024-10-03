# nutanix-api2json.pl
# download API data

use 5.008_008;

use strict;
use warnings;

use HostCfg;
use Nutanix;
use JSON;
use Data::Dumper;
use Digest::MD5 qw(md5_hex);
use POSIX;

#use Devel::Size qw(total_size);

defined $ENV{INPUTDIR} || warn( localtime() . ': INPUTDIR undefined, probably have not read etc/lpar2rrd.cfg ' . __FILE__ . ':' . __LINE__ ) && exit 1;

if ( keys %{ HostCfg::getHostConnections('Nutanix') } == 0 ) {
  exit(0);
}

my $input_dir   = $ENV{INPUTDIR};
my $path_prefix = "$input_dir/data/NUTANIX";
my $json_path   = "$path_prefix/json";
my $conf_path   = "$path_prefix/conf";
my $raw_path    = "$path_prefix/raw";

# create directories in data/
my @create_dir = ( $path_prefix, $json_path, $conf_path, $raw_path );
for (@create_dir) {
  my $dir = $_;
  unless ( -d $dir ) {
    mkdir( "$dir", 0755 ) || warn( localtime() . ": Cannot mkdir $dir: $!" . __FILE__ . ':' . __LINE__ );
  }
}

# api version per type
my %api = (
  "central" => {
    "cluster"   => "v3",
    "host"      => "v3",
    "vm"        => "v3",
    "disk"      => "v2",
    "container" => "v2",
    "pool"      => "v1",
    "vdisk"     => "v2"
  },
  "element" => {
    "cluster"   => "v2",
    "host"      => "v2",
    "vm"        => "v2",
    "disk"      => "v2",
    "container" => "v2",
    "pool"      => "v1",
    "vdisk"     => "v2"
  },
  "element_old" => {
    "cluster"   => "v1",
    "host"      => "v1",
    "vm"        => "v1",
    "disk"      => "v1",
    "container" => "v1",
    "pool"      => "v1",
    "vdisk"     => "v1"
  }
);

my %hosts = %{ HostCfg::getHostConnections('Nutanix') };
my @pids;
my $pid;
my $timeout = 900;
my %conf_hash;

my $interval = 60;                  # metrics interval
my $page_max = 200;                 # items in page
my $max_size = 1024 * 1024 * 16;    # max perf size per file (16 MB)

foreach my $host ( keys %hosts ) {
  my $uuid = defined $hosts{$host}{uuid} ? $hosts{$host}{uuid} : $host;
  $conf_hash{$uuid} = 1;
  unless ( defined( $pid = fork() ) ) {
    warn( localtime() . ": Error: failed to fork for $host.\n" );
    next;
  }
  else {
    if ($pid) {
      push @pids, $pid;
    }
    else {
      local $SIG{ALRM} = sub { die "Nutanix API2JSON: $pid timeouted.\n"; };
      alarm($timeout);

      my ( $protocol, $hostname, $port, $username, $password, $type ) = ( $hosts{$host}{proto}, $hosts{$host}{host}, $hosts{$host}{api_port}, $hosts{$host}{username}, $hosts{$host}{password}, $hosts{$host}{type} );
      api2json( $protocol, $hostname, $port, $username, $password, $type, $uuid, $host );
      exit;
    }
  }
}

# wait for forked data retrieval
for $pid (@pids) {
  waitpid( $pid, 0 );
}

# merge conf
Nutanix::log("Configuration: merging and saving");
opendir( DH, "$conf_path" ) || die "Could not open '$conf_path' for reading '$!'\n";
my @files = grep /.*.json/, readdir DH;
my %conf;
my %health;
my %specification;
my %label;
my %architecture;
my %alert;
my $data;

foreach my $file ( sort @files ) {
  my @splits = split /_/, $file;
  if ( !defined $conf_hash{ $splits[0] } ) {
    Nutanix::log("Configuration: skipping old conf $file");
    next;
  }

  Nutanix::log("Configuration: processing $file");

  my $json = '';
  if ( open( my $fh, '<', "$conf_path/$file" ) ) {
    while ( my $row = <$fh> ) {
      chomp $row;
      $json .= $row;
    }
    close($fh);
  }
  else {
    warn( localtime() . ": Cannot open the file $file ($!)" ) && next;
    next;
  }

  # decode JSON
  eval { $data = decode_json($json); };
  if ($@) {
    my $error = $@;
    Nutanix::error("Empty conf file, deleting $conf_path/$file");
    unlink "$conf_path/$file";
    next;
  }
  if ( ref($data) ne "HASH" ) {
    warn( localtime() . ": Error decoding JSON in file $file: missing data" ) && next;
  }

  # conf file
  if ( $splits[1] eq "conf.json" ) {
    foreach my $key ( keys %{ $data->{architecture} } ) {
      foreach my $key2 ( keys %{ $data->{architecture}->{$key} } ) {
        if ( !defined $architecture{architecture}{$key}{$key2} ) {
          $architecture{architecture}{$key}{$key2} = $data->{architecture}->{$key}->{$key2};
        }
        else {
          for ( @{ $data->{architecture}->{$key}->{$key2} } ) {
            my $value = $_;
            push( @{ $architecture{architecture}{$key}{$key2} }, $value );
          }
        }
      }
    }
    foreach my $key ( keys %{ $data->{specification} } ) {
      foreach my $key2 ( keys %{ $data->{specification}->{$key} } ) {
        $specification{specification}{$key}{$key2} = $data->{specification}->{$key}->{$key2};
      }
    }
    foreach my $key ( keys %{ $data->{labels} } ) {
      foreach my $key2 ( keys %{ $data->{labels}->{$key} } ) {
        $label{labels}{$key}{$key2} = $data->{labels}->{$key}->{$key2};
      }
    }
  }
  elsif ( $splits[1] eq "health.json" ) {
    foreach my $id ( keys %{$data} ) {
      $health{$id} = \%{ $data->{$id} };
    }
  }
  elsif ( $splits[1] eq "alert.json" ) {
    foreach my $id ( keys %{ $data->{events} } ) {
      $alert{events}{$id} = \%{ $data->{events}->{$id} };
    }
    foreach my $id ( keys %{ $data->{alerts} } ) {
      $alert{alerts}{$id} = \%{ $data->{alerts}->{$id} };
    }
  }

  #save merged
  if (%alert) {
    open my $fa, ">", $path_prefix . "/alerts.json";
    print $fa JSON->new->utf8->pretty->encode( \%alert );
    close $fa;
  }
  if (%health) {
    open my $fa, ">", $path_prefix . "/health.json";
    print $fa JSON->new->utf8->pretty->encode( \%health );
    close $fa;
  }
  if (%architecture) {
    open my $fa, ">", $path_prefix . "/architecture.json";
    print $fa JSON->new->utf8->pretty->encode( \%architecture );
    close $fa;
  }
  if (%label) {
    open my $fa, ">", $path_prefix . "/label.json";
    print $fa JSON->new->utf8->pretty->encode( \%label );
    close $fa;
  }
  if (%specification) {
    open my $fa, ">", $path_prefix . "/specification.json";
    print $fa JSON->new->utf8->pretty->encode( \%specification );
    close $fa;
  }
}

sub api2json {
  my ( $protocol, $hostname, $port, $username, $password, $type, $hostcfg_uuid, $hostcfg_label ) = @_;

  my $nutanix = Nutanix->new( $protocol, $hostname, $port, $username, $password );

  # user variables
  my $var_file = $path_prefix . "/variables.json";
  my $variables_json;
  if ( -e $var_file ) {
    if ( open( my $fv, '<', $var_file ) ) {
      while ( my $row = <$fv> ) {
        chomp $row;
        $variables_json .= $row;
      }
      close($fv);

      my $variables = Nutanix::decode_json_eval($variables_json);

      # user defined api version
      if ( defined $variables->{api} ) {
        foreach my $api_k ( keys %{ $variables->{api} } ) {
          $api{$type}{$api_k} = $variables->{api}{$api_k};
	  Nutanix::log( "$hostcfg_label: loaded api variable: $api_k - $api{$type}{$api_k}");
        }
      }

      # user defined tls version
      if ( defined $variables->{tls} ) {
        $nutanix->setTls( $variables->{tls} );
      }
    }
  }

  #Get last record
  my $timestamp_json = '';
  if ( open( my $fh, '<', $path_prefix . "/" . $hostcfg_uuid . "_last.json" ) ) {
    while ( my $row = <$fh> ) {
      chomp $row;
      $timestamp_json .= $row;
    }
    close($fh);
  }
  else {
    open my $hl, ">", $path_prefix . "/" . $hostcfg_uuid . "_last.json";
    $timestamp_json = "{\"timestamp\":\"" . ( time() - 1800 ) . "\"}";
    print $hl $timestamp_json;
    close($hl);
  }

  # decode JSON
  my ( $timestamp_start, $timestamp_end );
  my $timestamp_data = Nutanix::decode_json_eval($timestamp_json);
  if ( ref($timestamp_data) ne "HASH" || !defined $timestamp_data->{timestamp} ) {
    warn( localtime() . ": Error decoding JSON in timestamp file: missing data" );
    $timestamp_start = time() - 1800;
  }
  else {
    $timestamp_start = $timestamp_data->{timestamp};
  }
  $timestamp_start = $timestamp_start - 600;
  $timestamp_end   = time() - 180;

  $timestamp_start = $timestamp_start - ( $timestamp_start % 60 );
  $timestamp_end   = $timestamp_end - ( $timestamp_end % 60 );

  my %conf;
  my %perf;
  my %alert;
  my %hs;
  my $health_cluster;
  my $index = 0;

  # clusters
  my $clusters = $nutanix->getClusters( $api{$type}{'cluster'} );
  saveRaw( $clusters, $hostcfg_uuid, 'clusters' );
  if ( $api{$type}{'cluster'} eq "v3" ) {

    # API v3
    Nutanix::log( "$hostcfg_label: fetching " . $clusters->{metadata}{total_matches} . " clusters" );
    for ( @{ $clusters->{entities} } ) {
      my $cluster = $_;

      $health_cluster                                                                 = 'central';
      $conf{'labels'}{'cluster'}{ $cluster->{metadata}->{uuid} }                      = $cluster->{status}->{name};
      $conf{'specification'}{'cluster'}{ $cluster->{metadata}->{uuid} }{hostcfg_uuid} = $hostcfg_uuid;
    }
  }
  elsif ( $api{$type}{'cluster'} eq "v2" ) {

    # API v2
    Nutanix::log( "$hostcfg_label: fetching " . $clusters->{metadata}{total_entities} . " clusters" );
    for ( @{ $clusters->{entities} } ) {
      my $cluster = $_;

      $health_cluster                                                     = $cluster->{uuid};
      $conf{'labels'}{'cluster'}{ $cluster->{uuid} }                      = $cluster->{name};
      $conf{'specification'}{'cluster'}{ $cluster->{uuid} }{hostcfg_uuid} = $hostcfg_uuid;
    }
  }
  elsif ( $api{$type}{'cluster'} eq "v1" ) {

    # API v1
    Nutanix::log( "$hostcfg_label: fetching " . $clusters->{metadata}{totalEntities} . " clusters" );
    for ( @{ $clusters->{entities} } ) {
      my $cluster = $_;

      $health_cluster                                                     = $cluster->{uuid};
      $conf{'labels'}{'cluster'}{ $cluster->{uuid} }                      = $cluster->{name};
      $conf{'specification'}{'cluster'}{ $cluster->{uuid} }{hostcfg_uuid} = $hostcfg_uuid;
    }
  }
  $clusters = ();

  # nodes
  my $nodes = $nutanix->getNodes( $api{$type}{'host'} );
  saveRaw( $nodes, $hostcfg_uuid, 'hosts' );
  if ( $api{$type}{'host'} eq "v3" ) {

    # API v3
    Nutanix::log( "$hostcfg_label: fetching " . $nodes->{metadata}{total_matches} . " hosts" );
    for ( @{ $nodes->{entities} } ) {
      my $host = $_;

      if ( !defined $host->{status}{cluster_reference}{uuid} ) {
        next;
      }

      $conf{'labels'}{'host'}{ $host->{metadata}->{uuid} }                      = $host->{spec}{name};
      $conf{specification}{'host'}{ $host->{metadata}->{uuid} }{name}           = $host->{spec}{name};
      $conf{specification}{'host'}{ $host->{metadata}->{uuid} }{address}        = $host->{spec}{resources}{controller_vm}{ip};
      $conf{specification}{'host'}{ $host->{metadata}->{uuid} }{memory}         = defined $host->{status}{resources}{memory_capacity_mib} ? $host->{status}{resources}{memory_capacity_mib} / 1024: ();
      $conf{specification}{'host'}{ $host->{metadata}->{uuid} }{cpu_count}      = $host->{status}{resources}{num_cpu_cores};
      $conf{specification}{'host'}{ $host->{metadata}->{uuid} }{socket_count}   = $host->{status}{resources}{num_cpu_sockets};
      $conf{specification}{'host'}{ $host->{metadata}->{uuid} }{cpu_model}      = $host->{status}{resources}{cpu_model};
      $conf{specification}{'host'}{ $host->{metadata}->{uuid} }{version}        = $host->{status}{resources}{hypervisor}{hypervisor_full_name};
      $conf{specification}{'host'}{ $host->{metadata}->{uuid} }{parent_cluster} = $host->{status}{cluster_reference}{uuid};

      if ( defined $conf{'architecture'}{'cluster'}{ $host->{status}{cluster_reference}{uuid} }[0] ) {
        push( @{ $conf{'architecture'}{'cluster'}{ $host->{status}{cluster_reference}{uuid} } }, $host->{metadata}->{uuid} );
      }
      else {
        $conf{'architecture'}{'cluster'}{ $host->{status}{cluster_reference}{uuid} }[0] = $host->{metadata}->{uuid};
      }

      my $tmpTime;
      my $metrics  = "hypervisor_cpu_usage_ppm,hypervisor_memory_usage_ppm";
      my $nodePerf = $nutanix->getNodePerf( $host->{metadata}->{uuid}, $metrics, $timestamp_start, $timestamp_end, $interval, $api{$type}{'host'} );
      for ( @{ $nodePerf->{"stats_specific_responses"} } ) {
        my $nodeMetrics = $_;
        $tmpTime = ceil( $nodeMetrics->{start_time_in_usecs} / 1000000 );
        for ( @{ $nodeMetrics->{values} } ) {
          my $value = $_;
          if ( $value < 0 ) { $value = 0; }
          $perf{nodes}{ $host->{metadata}->{uuid} }{$tmpTime}{ $nodeMetrics->{metric} } = $value;
          $perf{nodes}{ $host->{metadata}->{uuid} }{$tmpTime}{'cpu_cores'}              = $host->{status}{resources}{num_cpu_cores};
          $perf{nodes}{ $host->{metadata}->{uuid} }{$tmpTime}{'memory'}                 = $host->{status}{resources}{memory_capacity_mib} * 1024 * 1024;
          $tmpTime += $interval;
        }
      }
    }
  }
  elsif ( $api{$type}{'host'} eq "v2" ) {

    # API v2
    Nutanix::log( "$hostcfg_label: fetching " . $nodes->{metadata}{total_entities} . " hosts" );
    for ( @{ $nodes->{entities} } ) {
      my $host = $_;

      if ( !defined $host->{cluster_uuid} ) {
        next;
      }

      $conf{'labels'}{'host'}{ $host->{uuid} }                      = $host->{name};
      $conf{specification}{'host'}{ $host->{uuid} }{name}           = $host->{name};
      $conf{specification}{'host'}{ $host->{uuid} }{address}        = $host->{hypervisor_address};
      $conf{specification}{'host'}{ $host->{uuid} }{memory}         = $host->{memory_capacity_in_bytes} / (1024**3);
      $conf{specification}{'host'}{ $host->{uuid} }{cpu_count}      = $host->{num_cpu_cores};
      $conf{specification}{'host'}{ $host->{uuid} }{socket_count}   = $host->{num_cpu_sockets};
      $conf{specification}{'host'}{ $host->{uuid} }{cpu_model}      = $host->{cpu_model};
      $conf{specification}{'host'}{ $host->{uuid} }{version}        = $host->{hypervisor_full_name};
      $conf{specification}{'host'}{ $host->{uuid} }{parent_cluster} = $host->{cluster_uuid};

      if ( defined $conf{'architecture'}{'cluster'}{ $host->{cluster_uuid} }[0] ) {
        push( @{ $conf{'architecture'}{'cluster'}{ $host->{cluster_uuid} } }, $host->{uuid} );
      }
      else {
        $conf{'architecture'}{'cluster'}{ $host->{cluster_uuid} }[0] = $host->{uuid};
      }

      my $tmpTime;
      my $metrics  = "hypervisor_cpu_usage_ppm,hypervisor_memory_usage_ppm";
      my $nodePerf = $nutanix->getNodePerf( $host->{uuid}, $metrics, $timestamp_start, $timestamp_end, $interval, $api{$type}{'host'} );
      for ( @{ $nodePerf->{"stats_specific_responses"} } ) {
        my $nodeMetrics = $_;
        $tmpTime = ceil( $nodeMetrics->{start_time_in_usecs} / 1000000 );
        for ( @{ $nodeMetrics->{values} } ) {
          my $value = $_;
          if ( $value < 0 ) { $value = 0; }
          $perf{nodes}{ $host->{uuid} }{$tmpTime}{ $nodeMetrics->{metric} } = $value;
          $perf{nodes}{ $host->{uuid} }{$tmpTime}{'cpu_cores'}              = $host->{num_cpu_cores};
          $perf{nodes}{ $host->{uuid} }{$tmpTime}{'memory'}                 = $host->{memory_capacity_in_bytes};
          $tmpTime += $interval;
        }
      }
    }
  }
  elsif ( $api{$type}{'host'} eq "v1" ) {

    # API v1
    Nutanix::log( "$hostcfg_label: fetching " . $nodes->{metadata}{totalEntities} . " hosts" );
    for ( @{ $nodes->{entities} } ) {
      my $host = $_;

      if ( !defined $host->{clusterUuid} ) {
        next;
      }

      $conf{'labels'}{'host'}{ $host->{uuid} }                      = $host->{name};
      $conf{specification}{'host'}{ $host->{uuid} }{name}           = $host->{name};
      $conf{specification}{'host'}{ $host->{uuid} }{address}        = $host->{hypervisorAddress};
      $conf{specification}{'host'}{ $host->{uuid} }{memory}         = $host->{memoryCapacityInBytes} / (1024**3);
      $conf{specification}{'host'}{ $host->{uuid} }{cpu_count}      = $host->{numCpuCores};
      $conf{specification}{'host'}{ $host->{uuid} }{socket_count}   = $host->{numCpuSockets};
      $conf{specification}{'host'}{ $host->{uuid} }{cpu_model}      = $host->{cpuModel};
      $conf{specification}{'host'}{ $host->{uuid} }{version}        = $host->{hypervisorFullName};
      $conf{specification}{'host'}{ $host->{uuid} }{parent_cluster} = $host->{clusterUuid};

      if ( defined $conf{'architecture'}{'cluster'}{ $host->{clusterUuid} }[0] ) {
        push( @{ $conf{'architecture'}{'cluster'}{ $host->{clusterUuid} } }, $host->{uuid} );
      }
      else {
        $conf{'architecture'}{'cluster'}{ $host->{clusterUuid} }[0] = $host->{uuid};
      }

      my $tmpTime;
      my $metrics  = "hypervisor_cpu_usage_ppm,hypervisor_memory_usage_ppm";
      my $nodePerf = $nutanix->getNodePerf( $host->{uuid}, $metrics, $timestamp_start, $timestamp_end, $interval, $api{$type}{'host'} );
      for ( @{ $nodePerf->{"statsSpecificResponses"} } ) {
        my $nodeMetrics = $_;
        $tmpTime = ceil( $nodeMetrics->{startTimeInUsecs} / 1000000 );
        for ( @{ $nodeMetrics->{values} } ) {
          my $value = $_;
          if ( $value < 0 ) { $value = 0; }
          $perf{nodes}{ $host->{uuid} }{$tmpTime}{ $nodeMetrics->{metric} } = $value;
          $perf{nodes}{ $host->{uuid} }{$tmpTime}{'cpu_cores'}              = $host->{numCpuCores};
          $perf{nodes}{ $host->{uuid} }{$tmpTime}{'memory'}                 = $host->{memoryCapacityInBytes};
          $tmpTime += $interval;
        }
      }
    }
  }
  $nodes = ();

  my $page = 1;
  my $loop = 1;
  while($loop eq "1") {
    if (!defined $api{$type}{'vm'}) { last; }
    my $vms = $nutanix->getVMs( $api{$type}{'vm'}, $page_max, $page );
    saveRaw( $vms, $hostcfg_uuid, 'vms_' . $page );
    if ( $api{$type}{'vm'} eq "v3" ) {

      if ($vms->{metadata}{total_matches} < ($page-1)*$page_max || $vms->{metadata}{length} eq "0") {
        $loop = 0;
        last;
      }

      # API v3
      Nutanix::log( "$hostcfg_label: fetching " . $vms->{metadata}{length} . " vms" . " [step ".$page." / " . ceil($vms->{metadata}{total_matches}/$page_max) . "]" );
      for ( @{ $vms->{entities} } ) {
        my $vm = $_;

        if ( !defined $vm->{spec}->{cluster_reference}->{uuid} ) {
          next;
        }

        $conf{labels}{vm}{ $vm->{metadata}->{uuid} }                        = $vm->{status}->{name};
        $conf{specification}{vm}{ $vm->{metadata}->{uuid} }{memory}         = $vm->{spec}->{resources}->{memory_size_mib} / 1024;
        $conf{specification}{vm}{ $vm->{metadata}->{uuid} }{cpu_count}      = $vm->{spec}->{resources}->{num_vcpus_per_socket} * $vm->{spec}->{resources}->{num_sockets};
        $conf{specification}{vm}{ $vm->{metadata}->{uuid} }{os}             = " ";
        $conf{specification}{vm}{ $vm->{metadata}->{uuid} }{parent_host}    = $vm->{status}->{resources}->{host_reference}->{uuid};
        $conf{specification}{vm}{ $vm->{metadata}->{uuid} }{parent_cluster} = $vm->{spec}->{cluster_reference}->{uuid};
        $conf{specification}{vm}{ $vm->{metadata}->{uuid} }{hypervisor}     = $vm->{status}->{resources}->{hypervisor_type};

        if ( defined $vm->{status}->{resources}->{host_reference}->{uuid} ) {
          if ( defined $conf{architecture}{host_vm}{ $vm->{status}->{resources}->{host_reference}->{uuid} }[0] ) {
            push( @{ $conf{architecture}{host_vm}{ $vm->{status}->{resources}->{host_reference}->{uuid} } }, $vm->{metadata}->{uuid} );
          }
          else {
            $conf{architecture}{host_vm}{ $vm->{status}->{resources}->{host_reference}->{uuid} }[0] = $vm->{metadata}->{uuid};
          }
        }

        if ( defined $conf{architecture}{cluster_vm}{ $vm->{status}->{cluster_reference}->{uuid} }[0] ) {
          push( @{ $conf{architecture}{cluster_vm}{ $vm->{status}->{cluster_reference}->{uuid} } }, $vm->{metadata}->{uuid} );
        }
        else {
          $conf{architecture}{cluster_vm}{ $vm->{status}->{cluster_reference}->{uuid} }[0] = $vm->{metadata}->{uuid};
        }

        #if (total_size(\%perf) >= $max_size) { savePerf(\%perf, $hostcfg_uuid, $timestamp_start, $timestamp_end, $index); $index++; %perf = (); }

        my $tmpTime;
        my $metrics = "controller_read_io_bandwidth_kBps,hypervisor_cpu_usage_ppm,controller_write_io_bandwidth_kBps,controller_io_bandwidth_kBps";
        my $vmPerf  = $nutanix->getVMPerf( $vm->{metadata}->{uuid}, $metrics, $timestamp_start, $timestamp_end, $interval );
        for ( @{ $vmPerf->{"statsSpecificResponses"} } ) {
          my $vmMetrics = $_;
          $tmpTime = ceil( $vmMetrics->{startTimeInUsecs} / 1000000 );
          for ( @{ $vmMetrics->{values} } ) {
            my $value = $_;
            if ( $value < 0 ) { $value = 0; }
            $perf{vms}{ $vm->{metadata}->{uuid} }{$tmpTime}{ $vmMetrics->{metric} } = $value;
            $tmpTime += $interval;
          }
        }

        $metrics = "controller_avg_write_io_latency_usecs,controller_avg_read_io_latency_usecs,controller_avg_io_latency_usecs,memory_usage_ppm,guest.memory_usage_bytes";
        $vmPerf  = $nutanix->getVMPerf( $vm->{metadata}->{uuid}, $metrics, $timestamp_start, $timestamp_end, $interval );
        for ( @{ $vmPerf->{"statsSpecificResponses"} } ) {
          my $vmMetrics = $_;
          $tmpTime = ceil( $vmMetrics->{startTimeInUsecs} / 1000000 );
          for ( @{ $vmMetrics->{values} } ) {
            my $value = $_;
            if ( $value < 0 ) { $value = 0; }
            $perf{vms}{ $vm->{metadata}->{uuid} }{$tmpTime}{ $vmMetrics->{metric} } = $value;
            $perf{vms}{ $vm->{metadata}->{uuid} }{$tmpTime}{'cpu_cores'}            = $vm->{spec}->{resources}->{num_vcpus_per_socket} * $vm->{spec}->{resources}->{num_sockets};
            $perf{vms}{ $vm->{metadata}->{uuid} }{$tmpTime}{'memory'}               = $vm->{spec}->{resources}->{memory_size_mib} * 1024 * 1024;
            $tmpTime += $interval;
          }
        }

        $metrics = "controller_num_read_io,controller_num_write_io,controller_num_io,hypervisor_num_transmitted_bytes,hypervisor_num_received_bytes";
        $vmPerf  = $nutanix->getVMPerf( $vm->{metadata}->{uuid}, $metrics, $timestamp_start, $timestamp_end, $interval );
        for ( @{ $vmPerf->{"statsSpecificResponses"} } ) {
          my $vmMetrics = $_;
          $tmpTime = ceil( $vmMetrics->{startTimeInUsecs} / 1000000 );
          for ( @{ $vmMetrics->{values} } ) {
            my $value = $_;
            if ( $value < 0 ) { $value = 0; }
            $perf{vms}{ $vm->{metadata}->{uuid} }{$tmpTime}{ $vmMetrics->{metric} } = $value / $interval;
            $tmpTime += $interval;
          }
        }
      }
    }
    elsif ( $api{$type}{'vm'} eq "v2" ) {

      if ($vms->{metadata}{total_entities} < ($page-1)*$page_max || $vms->{metadata}{start_index} eq "-1") {
        $loop = 0;
        last;
      }

      # API v2
      Nutanix::log( "$hostcfg_label: fetching ".(($vms->{metadata}{end_index}+1)-$vms->{metadata}{start_index})." vms [step ".$page." / ".ceil($vms->{metadata}{total_entities}/$page_max)."]");

      for ( @{ $vms->{entities} } ) {
        my $vm = $_;

        if ( !defined $vm->{host_uuid} ) {
          next;
        }

        $conf{labels}{vm}{ $vm->{uuid} }                        = $vm->{name};
        $conf{specification}{vm}{ $vm->{uuid} }{memory}         = $vm->{memory_mb} / 1024;
        $conf{specification}{vm}{ $vm->{uuid} }{cpu_count}      = $vm->{num_vcpus};
        $conf{specification}{vm}{ $vm->{uuid} }{os}             = " ";
        $conf{specification}{vm}{ $vm->{uuid} }{parent_host}    = $vm->{host_uuid};
        $conf{specification}{vm}{ $vm->{uuid} }{parent_cluster} = $conf{specification}{'host'}{ $vm->{host_uuid} }{parent_cluster};
        $conf{specification}{vm}{ $vm->{uuid} }{hypervisor}     = " ";

        if ( defined $conf{architecture}{host_vm}{ $vm->{host_uuid} }[0] ) {
          push( @{ $conf{architecture}{host_vm}{ $vm->{host_uuid} } }, $vm->{uuid} );
        }
        else {
          $conf{architecture}{host_vm}{ $vm->{host_uuid} }[0] = $vm->{uuid};
        }

        if ( defined $conf{specification}{'host'}{ $vm->{host_uuid} }{parent_cluster} ) {
          if ( defined $conf{architecture}{cluster_vm}{ $conf{specification}{'host'}{ $vm->{host_uuid} }{parent_cluster} }[0] ) {
            push( @{ $conf{architecture}{cluster_vm}{ $conf{specification}{'host'}{ $vm->{host_uuid} }{parent_cluster} } }, $vm->{uuid} );
          }
          else {
            $conf{architecture}{cluster_vm}{ $conf{specification}{'host'}{ $vm->{host_uuid} }{parent_cluster} }[0] = $vm->{uuid};
          }
        }

        #if (total_size(\%perf) >= $max_size) { savePerf(\%perf, $hostcfg_uuid, $timestamp_start, $timestamp_end, $index); $index++; %perf = (); }

        my $tmpTime;
        my $metrics = "controller_read_io_bandwidth_kBps,hypervisor_cpu_usage_ppm,controller_write_io_bandwidth_kBps,controller_io_bandwidth_kBps";
        my $vmPerf  = $nutanix->getVMPerf( $vm->{uuid}, $metrics, $timestamp_start, $timestamp_end, $interval );
        for ( @{ $vmPerf->{"statsSpecificResponses"} } ) {
          my $vmMetrics = $_;
          $tmpTime = ceil( $vmMetrics->{startTimeInUsecs} / 1000000 );
          for ( @{ $vmMetrics->{values} } ) {
            my $value = $_;
            if ( $value < 0 ) { $value = 0; }
            $perf{vms}{ $vm->{uuid} }{$tmpTime}{ $vmMetrics->{metric} } = $value;
            $tmpTime += $interval;
          }
        }

        $metrics = "controller_avg_write_io_latency_usecs,controller_avg_read_io_latency_usecs,controller_avg_io_latency_usecs,memory_usage_ppm,guest.memory_usage_bytes";
        $vmPerf  = $nutanix->getVMPerf( $vm->{uuid}, $metrics, $timestamp_start, $timestamp_end, $interval );
        for ( @{ $vmPerf->{"statsSpecificResponses"} } ) {
          my $vmMetrics = $_;
          $tmpTime = ceil( $vmMetrics->{startTimeInUsecs} / 1000000 );
          for ( @{ $vmMetrics->{values} } ) {
            my $value = $_;
            if ( $value < 0 ) { $value = 0; }
            $perf{vms}{ $vm->{uuid} }{$tmpTime}{ $vmMetrics->{metric} } = $value;
            $perf{vms}{ $vm->{uuid} }{$tmpTime}{'cpu_cores'}            = $vm->{num_vcpus};
            $perf{vms}{ $vm->{uuid} }{$tmpTime}{'memory'}               = $vm->{memory_mb} * 1024 * 1024;
            $tmpTime += $interval;
          }
        }

        $metrics = "controller_num_read_io,controller_num_write_io,controller_num_io,hypervisor_num_transmitted_bytes,hypervisor_num_received_bytes";
        $vmPerf  = $nutanix->getVMPerf( $vm->{uuid}, $metrics, $timestamp_start, $timestamp_end, $interval );
        for ( @{ $vmPerf->{"statsSpecificResponses"} } ) {
          my $vmMetrics = $_;
          $tmpTime = ceil( $vmMetrics->{startTimeInUsecs} / 1000000 );
          for ( @{ $vmMetrics->{values} } ) {
            my $value = $_;
            if ( $value < 0 ) { $value = 0; }
            $perf{vms}{ $vm->{uuid} }{$tmpTime}{ $vmMetrics->{metric} } = $value / $interval;
            $tmpTime += $interval;
          }
        }
      }
    }
    elsif ( $api{$type}{'vm'} eq "v1" ) {

      if ($vms->{metadata}{totalEntities} < ($page-1)*$page_max || $vms->{metadata}{startIndex} eq "-1") {
        $loop = 0;
        last;
      }

      # API v1
      Nutanix::log( "$hostcfg_label: fetching ".(($vms->{metadata}{endIndex}+1)-$vms->{metadata}{startIndex})." vms [step ".$page." / ".ceil($vms->{metadata}{totalEntities}/$page_max)."]");
      for ( @{ $vms->{entities} } ) {
        my $vm = $_;

        if ( !defined $vm->{clusterUuid} ) {
          next;
        }

        $conf{labels}{vm}{ $vm->{uuid} }                        = $vm->{vmName};
        $conf{specification}{vm}{ $vm->{uuid} }{memory}         = $vm->{memoryCapacityInBytes} / (1024**3);
        $conf{specification}{vm}{ $vm->{uuid} }{cpu_count}      = $vm->{numVCpus};
        $conf{specification}{vm}{ $vm->{uuid} }{os}             = " ";
        $conf{specification}{vm}{ $vm->{uuid} }{parent_host}    = $vm->{hostUuid};
        $conf{specification}{vm}{ $vm->{uuid} }{parent_cluster} = $vm->{clusterUuid};
        $conf{specification}{vm}{ $vm->{uuid} }{hypervisor}     = $vm->{hypervisorType};

        if ( defined $vm->{hostUuid} ) {
          if ( defined $conf{architecture}{host_vm}{ $vm->{hostUuid} }[0] ) {
            push( @{ $conf{architecture}{host_vm}{ $vm->{hostUuid} } }, $vm->{uuid} );
          }
          else {
            $conf{architecture}{host_vm}{ $vm->{hostUuid} }[0] = $vm->{uuid};
          }
        }

        if ( defined $conf{architecture}{cluster_vm}{ $vm->{clusterUuid} }[0] ) {
          push( @{ $conf{architecture}{cluster_vm}{ $vm->{clusterUuid} } }, $vm->{uuid} );
        }
        else {
          $conf{architecture}{cluster_vm}{ $vm->{clusterUuid} }[0] = $vm->{uuid};
        }

        #if (total_size(\%perf) >= $max_size) { savePerf(\%perf, $hostcfg_uuid, $timestamp_start, $timestamp_end, $index); $index++; %perf = (); }

        my $tmpTime;
        my $metrics = "controller_read_io_bandwidth_kBps,hypervisor_cpu_usage_ppm,controller_write_io_bandwidth_kBps,controller_io_bandwidth_kBps";
        my $vmPerf  = $nutanix->getVMPerf( $vm->{uuid}, $metrics, $timestamp_start, $timestamp_end, $interval );
        for ( @{ $vmPerf->{"statsSpecificResponses"} } ) {
          my $vmMetrics = $_;
          $tmpTime = ceil( $vmMetrics->{startTimeInUsecs} / 1000000 );
          for ( @{ $vmMetrics->{values} } ) {
            my $value = $_;
            if ( $value < 0 ) { $value = 0; }
            $perf{vms}{ $vm->{uuid} }{$tmpTime}{ $vmMetrics->{metric} } = $value;
            $tmpTime += $interval;
          }
        }

        $metrics = "controller_avg_write_io_latency_usecs,controller_avg_read_io_latency_usecs,controller_avg_io_latency_usecs,memory_usage_ppm,guest.memory_usage_bytes";
        $vmPerf  = $nutanix->getVMPerf( $vm->{uuid}, $metrics, $timestamp_start, $timestamp_end, $interval );
        for ( @{ $vmPerf->{"statsSpecificResponses"} } ) {
          my $vmMetrics = $_;
          $tmpTime = ceil( $vmMetrics->{startTimeInUsecs} / 1000000 );
          for ( @{ $vmMetrics->{values} } ) {
            my $value = $_;
            if ( $value < 0 ) { $value = 0; }
            $perf{vms}{ $vm->{uuid} }{$tmpTime}{ $vmMetrics->{metric} } = $value;
            $perf{vms}{ $vm->{uuid} }{$tmpTime}{'cpu_cores'}            = $vm->{numVCpus};
            $perf{vms}{ $vm->{uuid} }{$tmpTime}{'memory'}               = $vm->{memoryCapacityInBytes};
            $tmpTime += $interval;
          }
        }

        $metrics = "controller_num_read_io,controller_num_write_io,controller_num_io,hypervisor_num_transmitted_bytes,hypervisor_num_received_bytes";
        $vmPerf  = $nutanix->getVMPerf( $vm->{uuid}, $metrics, $timestamp_start, $timestamp_end, $interval );
        for ( @{ $vmPerf->{"statsSpecificResponses"} } ) {
          my $vmMetrics = $_;
          $tmpTime = ceil( $vmMetrics->{startTimeInUsecs} / 1000000 );
          for ( @{ $vmMetrics->{values} } ) {
            my $value = $_;
            if ( $value < 0 ) { $value = 0; }
            $perf{vms}{ $vm->{uuid} }{$tmpTime}{ $vmMetrics->{metric} } = $value / $interval;
            $tmpTime += $interval;
          }
        }
      }
    }
    $page++;
  }

  $page = 1;
  $loop = 1;
  while ( $loop eq "1" ) {
    if ( !defined $api{$type}{'disk'} ) { last; }

    #if (total_size(\%perf) >= $max_size) { savePerf(\%perf, $hostcfg_uuid, $timestamp_start, $timestamp_end, $index); $index++; %perf = (); }
    my $disks = $nutanix->getDisks( $api{$type}{'disk'}, $page_max, $page );
    saveRaw( $disks, $hostcfg_uuid, 'disks_' . $page );
    if ( $api{$type}{'disk'} eq "v3" || $api{$type}{'disk'} eq "v2" ) {
      if ( $disks->{metadata}{total_entities} < ( $page - 1 ) * $page_max || $disks->{metadata}{start_index} eq "-1" ) {
        $loop = 0;
        last;
      }

      # API v3 & v2
      Nutanix::log( "$hostcfg_label: fetching " . ( ( $disks->{metadata}{end_index} + 1 ) - $disks->{metadata}{start_index} ) . " disks [step " . $page . " / " . ceil( $disks->{metadata}{total_entities} / $page_max ) . "]" );
      for ( @{ $disks->{entities} } ) {
        my $disk = $_;

        $conf{labels}{'disk'}{ $disk->{disk_uuid} }                       = $disk->{node_name} . " - " . $disk->{location};
        $conf{specification}{'disk'}{ $disk->{disk_uuid} }{label}         = $disk->{node_name} . " - " . $disk->{location};
        $conf{specification}{'disk'}{ $disk->{disk_uuid} }{type}          = $disk->{storage_tier_name};
        $conf{specification}{'disk'}{ $disk->{disk_uuid} }{node_uuid}     = $disk->{node_uuid};
        $conf{specification}{'disk'}{ $disk->{disk_uuid} }{physical_size} = ceil( $disk->{usage_stats}->{'storage.capacity_bytes'} / 1024 / 1024 / 1024 );

        if ( defined $conf{architecture}{host_disk}{ $disk->{node_uuid} }[0] ) {
          push( @{ $conf{architecture}{host_disk}{ $disk->{node_uuid} } }, $disk->{disk_uuid} );
        }
        else {
          $conf{architecture}{host_disk}{ $disk->{node_uuid} }[0] = $disk->{disk_uuid};
        }

        if ( defined $conf{architecture}{cluster_disk}{ $disk->{cluster_uuid} }[0] ) {
          push( @{ $conf{architecture}{cluster_disk}{ $disk->{cluster_uuid} } }, $disk->{disk_uuid} );
        }
        else {
          $conf{architecture}{cluster_disk}{ $disk->{cluster_uuid} }[0] = $disk->{disk_uuid};
        }

        $perf{disk_node}{ $disk->{disk_uuid} } = $disk->{node_uuid};

        my $tmpTime;
        my $metrics  = "read_io_bandwidth_kBps,write_io_bandwidth_kBps,avg_io_latency_usecs";
        my $diskPerf = $nutanix->getDiskPerf( $disk->{disk_uuid}, $metrics, $timestamp_start, $timestamp_end, $interval, $api{$type}{'disk'} );
        for ( @{ $diskPerf->{"stats_specific_responses"} } ) {
          my $diskMetrics = $_;
          $tmpTime = ceil( $diskMetrics->{start_time_in_usecs} / 1000000 );
          for ( @{ $diskMetrics->{values} } ) {
            my $value = $_;
            if ( $value < 0 ) { $value = 0; }
            $perf{disks}{ $disk->{disk_uuid} }{$tmpTime}{ $diskMetrics->{metric} } = $value;
            $tmpTime += $interval;
          }
        }

        $metrics  = "num_io,num_write_io,num_read_io";
        $diskPerf = $nutanix->getDiskPerf( $disk->{disk_uuid}, $metrics, $timestamp_start, $timestamp_end, $interval, $api{$type}{'disk'} );
        for ( @{ $diskPerf->{"stats_specific_responses"} } ) {
          my $diskMetrics = $_;
          $tmpTime = ceil( $diskMetrics->{start_time_in_usecs} / 1000000 );
          for ( @{ $diskMetrics->{values} } ) {
            my $value = $_;
            if ( $value < 0 ) { $value = 0; }
            $perf{disks}{ $disk->{disk_uuid} }{$tmpTime}{ $diskMetrics->{metric} } = $value / $interval;
            $tmpTime += $interval;
          }
        }
      }
    }
    elsif ( $api{$type}{'disk'} eq "v1" ) {
      if ( $disks->{metadata}{totalEntities} < ( $page - 1 ) * $page_max || $disks->{metadata}{startIndex} eq "-1" ) {
        $loop = 0;
        last;
      }

      # API v1
      Nutanix::log( "$hostcfg_label: fetching " . ( ( $disks->{metadata}{endIndex} + 1 ) - $disks->{metadata}{startIndex} ) . " disks [step " . $page . " / " . ceil( $disks->{metadata}{totalEntities} / $page_max ) . "]" );
      for ( @{ $disks->{entities} } ) {
        my $disk = $_;

        $conf{labels}{'disk'}{ $disk->{diskUuid} }                       = $disk->{nodeName} . " - " . $disk->{location};
        $conf{specification}{'disk'}{ $disk->{diskUuid} }{label}         = $disk->{nodeName} . " - " . $disk->{location};
        $conf{specification}{'disk'}{ $disk->{diskUuid} }{type}          = $disk->{storageTierName};
        $conf{specification}{'disk'}{ $disk->{diskUuid} }{node_uuid}     = $disk->{nodeUuid};
        $conf{specification}{'disk'}{ $disk->{diskUuid} }{physical_size} = ceil( $disk->{usageStats}->{'storage.capacity_bytes'} / 1024 / 1024 / 1024 );

        if ( defined $conf{architecture}{host_disk}{ $disk->{nodeUuid} }[0] ) {
          push( @{ $conf{architecture}{host_disk}{ $disk->{nodeUuid} } }, $disk->{diskUuid} );
        }
        else {
          $conf{architecture}{host_disk}{ $disk->{nodeUuid} }[0] = $disk->{diskUuid};
        }

        if ( defined $conf{architecture}{cluster_disk}{ $disk->{clusterUuid} }[0] ) {
          push( @{ $conf{architecture}{cluster_disk}{ $disk->{clusterUuid} } }, $disk->{diskUuid} );
        }
        else {
          $conf{architecture}{cluster_disk}{ $disk->{clusterUuid} }[0] = $disk->{diskUuid};
        }

        my $tmpTime;
        my $metrics  = "read_io_bandwidth_kBps,write_io_bandwidth_kBps,avg_io_latency_usecs";
        my $diskPerf = $nutanix->getDiskPerf( $disk->{diskUuid}, $metrics, $timestamp_start, $timestamp_end, $interval, $api{$type}{'disk'} );
        for ( @{ $diskPerf->{"statsSpecificResponses"} } ) {
          my $diskMetrics = $_;
          $tmpTime = ceil( $diskMetrics->{startTimeInUsecs} / 1000000 );
          for ( @{ $diskMetrics->{values} } ) {
            my $value = $_;
            if ( $value < 0 ) { $value = 0; }
            $perf{disks}{ $disk->{diskUuid} }{$tmpTime}{ $diskMetrics->{metric} } = $value;
            $tmpTime += $interval;
          }
        }

        $metrics  = "num_io,num_write_io,num_read_io";
        $diskPerf = $nutanix->getDiskPerf( $disk->{diskUuid}, $metrics, $timestamp_start, $timestamp_end, $interval, $api{$type}{'disk'} );
        for ( @{ $diskPerf->{"statsSpecificResponses"} } ) {
          my $diskMetrics = $_;
          $tmpTime = ceil( $diskMetrics->{startTimeInUsecs} / 1000000 );
          for ( @{ $diskMetrics->{values} } ) {
            my $value = $_;
            if ( $value < 0 ) { $value = 0; }
            $perf{disks}{ $disk->{diskUuid} }{$tmpTime}{ $diskMetrics->{metric} } = $value / $interval;
            $tmpTime += $interval;
          }
        }

      }
    }
    $page++;
  }

  my $containers = $nutanix->getStorageContainers( $api{$type}{'container'} );
  saveRaw( $containers, $hostcfg_uuid, 'containers' );
  if ( $api{$type}{'container'} eq "v3" || $api{$type}{'container'} eq "v2" ) {

    # API v3 & v2
    Nutanix::log( "$hostcfg_label: fetching " . $containers->{metadata}{total_entities} . " storage containers" );
    for ( @{ $containers->{entities} } ) {
      my $container = $_;

      $conf{labels}{'container'}{ $container->{storage_container_uuid} }                             = $container->{name};
      $conf{specification}{'container'}{ $container->{storage_container_uuid} }{label}               = $container->{name};
      $conf{specification}{'container'}{ $container->{storage_container_uuid} }{uuid}                = $container->{storage_container_uuid};
      $conf{specification}{'container'}{ $container->{storage_container_uuid} }{compression_enabled} = $container->{compression_enabled};
      $conf{specification}{'container'}{ $container->{storage_container_uuid} }{is_nutanix_managed}  = $container->{is_nutanix_managed};
      $conf{specification}{'container'}{ $container->{storage_container_uuid} }{capacity_size}       = ceil( $container->{usage_stats}->{'storage.capacity_bytes'} / ( 1024 * 1024 * 1024 ) );
      $conf{specification}{'container'}{ $container->{storage_container_uuid} }{capacity_used}       = ceil( $container->{usage_stats}->{'storage.usage_bytes'} / ( 1024 * 1024 * 1024 ) );
      $conf{specification}{'container'}{ $container->{storage_container_uuid} }{capacity_free}       = ceil( ( $container->{usage_stats}->{'storage.capacity_bytes'} - $container->{usage_stats}->{'storage.usage_bytes'} ) / ( 1024 * 1024 * 1024 ) );

      if ( exists $conf{architecture}{'cluster_container'}{ $container->{cluster_uuid} }[0] ) {
        push( @{ $conf{architecture}{'cluster_container'}{ $container->{cluster_uuid} } }, $container->{storage_container_uuid} );
      }
      else {
        $conf{architecture}{'cluster_container'}{ $container->{cluster_uuid} }[0] = $container->{storage_container_uuid};
      }

      my $tmpTime;
      my $metrics       = "controller_read_io_bandwidth_kBps,controller_write_io_bandwidth_kBps,controller_avg_io_latency_usecs";
      my $containerPerf = $nutanix->getStorageContainerPerf( $container->{storage_container_uuid}, $metrics, $timestamp_start, $timestamp_end, $interval, $api{$type}{'container'} );
      for ( @{ $containerPerf->{"stats_specific_responses"} } ) {
        my $containerMetrics = $_;
        $tmpTime = ceil( $containerMetrics->{start_time_in_usecs} / 1000000 );
        for ( @{ $containerMetrics->{values} } ) {
          my $value = $_;
          if ( $value < 0 ) { $value = 0; }
          $perf{containers}{ $container->{storage_container_uuid} }{$tmpTime}{ $containerMetrics->{metric} } = $value;
          $tmpTime += $interval;
        }
      }

      $metrics       = "controller_num_io,controller_num_write_io,controller_num_read_io";
      $containerPerf = $nutanix->getStorageContainerPerf( $container->{storage_container_uuid}, $metrics, $timestamp_start, $timestamp_end, $interval, $api{$type}{'container'} );
      for ( @{ $containerPerf->{"stats_specific_responses"} } ) {
        my $containerMetrics = $_;
        $tmpTime = ceil( $containerMetrics->{start_time_in_usecs} / 1000000 );
        for ( @{ $containerMetrics->{values} } ) {
          my $value = $_;
          if ( $value < 0 ) { $value = 0; }
          $perf{containers}{ $container->{storage_container_uuid} }{$tmpTime}{ $containerMetrics->{metric} } = $value / $interval;
          $tmpTime += $interval;
        }
      }

    }
  }
  elsif ( $api{$type}{'container'} eq "v1" ) {

    # API v1
    Nutanix::log( "$hostcfg_label: fetching " . $containers->{metadata}{totalEntities} . " storage containers" );
    for ( @{ $containers->{entities} } ) {
      my $container = $_;

      $conf{labels}{'container'}{ $container->{containerUuid} }                             = $container->{name};
      $conf{specification}{'container'}{ $container->{containerUuid} }{label}               = $container->{name};
      $conf{specification}{'container'}{ $container->{containerUuid} }{uuid}                = $container->{containerUuid};
      $conf{specification}{'container'}{ $container->{containerUuid} }{compression_enabled} = $container->{compressionEnabled};
      $conf{specification}{'container'}{ $container->{containerUuid} }{is_nutanix_managed}  = $container->{isNutanixManaged};
      $conf{specification}{'container'}{ $container->{containerUuid} }{capacity_size}       = ceil( $container->{usageStats}->{'storage.capacity_bytes'} / ( 1024 * 1024 * 1024 ) );
      $conf{specification}{'container'}{ $container->{containerUuid} }{capacity_used}       = ceil( $container->{usageStats}->{'storage.usage_bytes'} / ( 1024 * 1024 * 1024 ) );
      $conf{specification}{'container'}{ $container->{containerUuid} }{capacity_free}       = ceil( ( $container->{usageStats}->{'storage.capacity_bytes'} - $container->{usageStats}->{'storage.usage_bytes'} ) / ( 1024 * 1024 * 1024 ) );

      if ( exists $conf{architecture}{'cluster_container'}{ $container->{clusterUuid} }[0] ) {
        push( @{ $conf{architecture}{'cluster_container'}{ $container->{clusterUuid} } }, $container->{containerUuid} );
      }
      else {
        $conf{architecture}{'cluster_container'}{ $container->{clusterUuid} }[0] = $container->{containerUuid};
      }

      my $tmpTime;
      my $metrics       = "controller_read_io_bandwidth_kBps,controller_write_io_bandwidth_kBps,controller_avg_io_latency_usecs";
      my $containerPerf = $nutanix->getStorageContainerPerf( $container->{containerUuid}, $metrics, $timestamp_start, $timestamp_end, $interval, $api{$type}{'container'} );
      for ( @{ $containerPerf->{"statsSpecificResponses"} } ) {
        my $containerMetrics = $_;
        $tmpTime = ceil( $containerMetrics->{startTimeInUsecs} / 1000000 );
        for ( @{ $containerMetrics->{values} } ) {
          my $value = $_;
          if ( $value < 0 ) { $value = 0; }
          $perf{containers}{ $container->{containerUuid} }{$tmpTime}{ $containerMetrics->{metric} } = $value;
          $tmpTime += $interval;
        }
      }

      $metrics       = "controller_num_io,controller_num_write_io,controller_num_read_io";
      $containerPerf = $nutanix->getStorageContainerPerf( $container->{containerUuid}, $metrics, $timestamp_start, $timestamp_end, $interval, $api{$type}{'container'} );
      for ( @{ $containerPerf->{"statsSpecificResponses"} } ) {
        my $containerMetrics = $_;
        $tmpTime = ceil( $containerMetrics->{startTimeInUsecs} / 1000000 );
        for ( @{ $containerMetrics->{values} } ) {
          my $value = $_;
          if ( $value < 0 ) { $value = 0; }
          $perf{containers}{ $container->{containerUuid} }{$tmpTime}{ $containerMetrics->{metric} } = $value / $interval;
          $tmpTime += $interval;
        }
      }
    }
  }
  $containers = ();

  my $pools = $nutanix->getStoragePools( $api{$type}{'pool'} );
  saveRaw( $pools, $hostcfg_uuid, 'pools' );
  if ( $api{$type}{'pool'} eq "v3" || $api{$type}{'pool'} eq "v2" || $api{$type}{'pool'} eq "v1" ) {

    # API v3 & v2 & v1
    Nutanix::log( "$hostcfg_label: fetching " . $pools->{metadata}{totalEntities} . " storage pools" );
    for ( @{ $pools->{entities} } ) {
      my $pool = $_;

      $conf{labels}{'pool'}{ $pool->{storagePoolUuid} }                     = $pool->{name};
      $conf{specification}{'pool'}{ $pool->{storagePoolUuid} }{label}       = $pool->{name};
      $conf{specification}{'pool'}{ $pool->{storagePoolUuid} }{uuid}        = $pool->{storagePoolUuid};
      $conf{specification}{'pool'}{ $pool->{storagePoolUuid} }{cluster}     = $pool->{clusterUuid};
      $conf{specification}{'pool'}{ $pool->{storagePoolUuid} }{capacity_gb} = ceil( $pool->{capacity} / ( 1024 * 1024 * 1024 ) );
      $conf{specification}{'pool'}{ $pool->{storagePoolUuid} }{used_gb}     = ceil( $pool->{usageStats}->{'storage.usage_bytes'} / ( 1024 * 1024 * 1024 ) );
      $conf{specification}{'pool'}{ $pool->{storagePoolUuid} }{free_gb}     = ceil( $pool->{usageStats}->{'storage.free_bytes'} / ( 1024 * 1024 * 1024 ) );

      if ( exists $conf{architecture}{'cluster_pool'}{ $pool->{clusterUuid} }[0] ) {
        push( @{ $conf{architecture}{'cluster_pool'}{ $pool->{clusterUuid} } }, $pool->{storagePoolUuid} );
      }
      else {
        $conf{architecture}{'cluster_pool'}{ $pool->{clusterUuid} }[0] = $pool->{storagePoolUuid};
      }

      my $tmpTime;
      my $metrics  = "read_io_bandwidth_kBps,write_io_bandwidth_kBps,avg_io_latency_usecs";
      my $poolPerf = $nutanix->getStoragePoolPerf( $pool->{storagePoolUuid}, $metrics, $timestamp_start, $timestamp_end, $interval, $api{$type}{'pool'} );
      for ( @{ $poolPerf->{"statsSpecificResponses"} } ) {
        my $poolMetrics = $_;
        $tmpTime = ceil( $poolMetrics->{startTimeInUsecs} / 1000000 );
        for ( @{ $poolMetrics->{values} } ) {
          my $value = $_;
          if ( $value < 0 ) { $value = 0; }
          $perf{pools}{ $pool->{storagePoolUuid} }{$tmpTime}{ $poolMetrics->{metric} } = $value;
          $tmpTime += $interval;
        }
      }

      $metrics  = "num_io,num_write_io,num_read_io";
      $poolPerf = $nutanix->getStoragePoolPerf( $pool->{storagePoolUuid}, $metrics, $timestamp_start, $timestamp_end, $interval, $api{$type}{'pool'} );
      for ( @{ $poolPerf->{"statsSpecificResponses"} } ) {
        my $poolMetrics = $_;
        $tmpTime = ceil( $poolMetrics->{startTimeInUsecs} / 1000000 );
        for ( @{ $poolMetrics->{values} } ) {
          my $value = $_;
          if ( $value < 0 ) { $value = 0; }
          $perf{pools}{ $pool->{storagePoolUuid} }{$tmpTime}{ $poolMetrics->{metric} } = $value / $interval;
          $tmpTime += $interval;
        }
      }

    }
  }
  $pools = ();

  $page = 1;
  $loop = 1;
  while ( $loop eq "1" ) {
    if ( !defined $api{$type}{'vdisk'} ) { last; }

    #if (total_size(\%perf) >= $max_size) { savePerf(\%perf, $hostcfg_uuid, $timestamp_start, $timestamp_end, $index); $index++; %perf = (); }
    my $vdisks = $nutanix->getVdisks( $api{$type}{'vdisk'}, $page_max, $page );
    saveRaw( $vdisks, $hostcfg_uuid, 'vdisks_' . $page );
    if ( $api{$type}{'vdisk'} eq "v3" || $api{$type}{'vdisk'} eq "v2" ) {

      # API v3 & v2
      if ( $vdisks->{metadata}{total_entities} < ( $page - 1 ) * $page_max || $vdisks->{metadata}{start_index} eq "-1" ) {
        $loop = 0;
        last;
      }
      Nutanix::log( "$hostcfg_label: fetching " . ( ( $vdisks->{metadata}{end_index} + 1 ) - $vdisks->{metadata}{start_index} ) . " virtual disks [step " . $page . " / " . ceil( $vdisks->{metadata}{total_entities} / $page_max ) . "]" );
      for ( @{ $vdisks->{entities} } ) {
        my $vdisk = $_;

        if ( !defined $vdisk->{attached_vm_uuid} ) {
          next;
        }

        if ( defined $vdisk->{attached_vmname} ) {
          $conf{labels}{'vdisk'}{ $vdisk->{uuid} } = $vdisk->{attached_vmname} . " - " . $vdisk->{disk_address};
        }
        else {
          $conf{labels}{'vdisk'}{ $vdisk->{uuid} } = $vdisk->{uuid};
        }

        $conf{specification}{'vdisk'}{ $vdisk->{uuid} }{label}                    = $conf{labels}{'vdisk'}{ $vdisk->{uuid} };
        $conf{specification}{'vdisk'}{ $vdisk->{uuid} }{uuid}                     = $vdisk->{uuid};
        $conf{specification}{'vdisk'}{ $vdisk->{uuid} }{attached_vm_uuid}         = $vdisk->{attached_vm_uuid};
        $conf{specification}{'vdisk'}{ $vdisk->{uuid} }{attached_vmname}          = $vdisk->{attached_vmname};
        $conf{specification}{'vdisk'}{ $vdisk->{uuid} }{attached_volume_group_id} = $vdisk->{attached_volume_group_id};
        $conf{specification}{'vdisk'}{ $vdisk->{uuid} }{capacity_mb}              = sprintf("%.1f",$vdisk->{disk_capacity_in_bytes} / ( 1024 * 1024 * 1024 ) );
        $conf{specification}{'vdisk'}{ $vdisk->{uuid} }{cluster_uuid}             = $vdisk->{cluster_uuid};
        $conf{specification}{'vdisk'}{ $vdisk->{uuid} }{storage_container_uuid}   = $vdisk->{storage_container_uuid};

        if ( defined $conf{architecture}{'cluster_vdisk'}{ $vdisk->{cluster_uuid} }[0] ) {
          push( @{ $conf{architecture}{'cluster_vdisk'}{ $vdisk->{cluster_uuid} } }, $vdisk->{uuid} );
        }
        else {
          $conf{architecture}{'cluster_vdisk'}{ $vdisk->{cluster_uuid} }[0] = $vdisk->{uuid};
        }

        if ( defined $conf{architecture}{'container_vdisk'}{ $vdisk->{storage_container_uuid} }[0] ) {
          push( @{ $conf{architecture}{'container_vdisk'}{ $vdisk->{storage_container_uuid} } }, $vdisk->{uuid} );
        }
        else {
          $conf{architecture}{'container_vdisk'}{ $vdisk->{storage_container_uuid} }[0] = $vdisk->{uuid};
        }

        my $tmpTime;
        my $metrics   = "controller_read_io_bandwidth_kBps,controller_write_io_bandwidth_kBps,controller_avg_io_latency_usecs";
        my $vdiskPerf = $nutanix->getVdiskPerf( $vdisk->{uuid}, $metrics, $timestamp_start, $timestamp_end, $interval, $api{$type}{'vdisk'} );
        for ( @{ $vdiskPerf->{"stats_specific_responses"} } ) {
          my $vdiskMetrics = $_;
          $tmpTime = ceil( $vdiskMetrics->{start_time_in_usecs} / 1000000 );
          for ( @{ $vdiskMetrics->{values} } ) {
            my $value = $_;
            if ( $value < 0 ) { $value = 0; }
            $perf{vdisks}{ $vdisk->{uuid} }{$tmpTime}{ $vdiskMetrics->{metric} } = $value;
            $tmpTime += $interval;
          }
        }

        $metrics   = "controller_num_io,controller_num_write_io,controller_num_read_io";
        $vdiskPerf = $nutanix->getVdiskPerf( $vdisk->{uuid}, $metrics, $timestamp_start, $timestamp_end, $interval, $api{$type}{'vdisk'} );
        for ( @{ $vdiskPerf->{"stats_specific_responses"} } ) {
          my $vdiskMetrics = $_;
          $tmpTime = ceil( $vdiskMetrics->{start_time_in_usecs} / 1000000 );
          for ( @{ $vdiskMetrics->{values} } ) {
            my $value = $_;
            if ( $value < 0 ) { $value = 0; }
            $perf{vdisks}{ $vdisk->{uuid} }{$tmpTime}{ $vdiskMetrics->{metric} } = $value / $interval;
            $tmpTime += $interval;
          }
        }

      }

    }
    elsif ( $api{$type}{'vdisk'} eq "v1" ) {

      # API v1
      if ( $vdisks->{metadata}{totalEntities} < ( $page - 1 ) * $page_max || $vdisks->{metadata}{startIndex} eq "-1" ) {
        $loop = 0;
        last;
      }
      Nutanix::log( "$hostcfg_label: fetching " . ( ( $vdisks->{metadata}{endIndex} + 1 ) - $vdisks->{metadata}{startIndex} ) . " virtual disks [step " . $page . " / " . ceil( $vdisks->{metadata}{totalEntities} / $page_max ) . "]" );
      for ( @{ $vdisks->{entities} } ) {
        my $vdisk = $_;

        if ( !defined $vdisk->{attachedVmUuid} ) {
          next;
        }

        if ( defined $vdisk->{attachedVMName} && defined $vdisk->{diskAddress} ) {
          $conf{labels}{'vdisk'}{ $vdisk->{uuid} } = $vdisk->{attachedVMName} . " - " . $vdisk->{diskAddress};
        }
        else {
          $conf{labels}{'vdisk'}{ $vdisk->{uuid} } = $vdisk->{uuid};
        }

        $conf{specification}{'vdisk'}{ $vdisk->{uuid} }{label}                    = $conf{labels}{'vdisk'}{ $vdisk->{uuid} };
        $conf{specification}{'vdisk'}{ $vdisk->{uuid} }{uuid}                     = $vdisk->{uuid};
        $conf{specification}{'vdisk'}{ $vdisk->{uuid} }{attached_vm_uuid}         = $vdisk->{attachedVmUuid};
        $conf{specification}{'vdisk'}{ $vdisk->{uuid} }{attached_vmname}          = $vdisk->{attachedVMName};
        $conf{specification}{'vdisk'}{ $vdisk->{uuid} }{attached_volume_group_id} = $vdisk->{attachedVolumeGroupId};
        $conf{specification}{'vdisk'}{ $vdisk->{uuid} }{capacity_mb}              = sprintf("%.1f",$vdisk->{diskCapacityInBytes} / ( 1024 * 1024 * 1024 ) );
        $conf{specification}{'vdisk'}{ $vdisk->{uuid} }{cluster_uuid}             = $vdisk->{clusterUuid};
        $conf{specification}{'vdisk'}{ $vdisk->{uuid} }{storage_container_uuid}   = $vdisk->{containerUuid};

        if ( defined $conf{architecture}{'cluster_vdisk'}{ $vdisk->{clusterUuid} }[0] ) {
          push( @{ $conf{architecture}{'cluster_vdisk'}{ $vdisk->{clusterUuid} } }, $vdisk->{uuid} );
        }
        else {
          $conf{architecture}{'cluster_vdisk'}{ $vdisk->{clusterUuid} }[0] = $vdisk->{uuid};
        }

        if ( defined $conf{architecture}{'container_vdisk'}{ $vdisk->{containerUuid} }[0] ) {
          push( @{ $conf{architecture}{'container_vdisk'}{ $vdisk->{containerUuid} } }, $vdisk->{uuid} );
        }
        else {
          $conf{architecture}{'container_vdisk'}{ $vdisk->{containerUuid} }[0] = $vdisk->{uuid};
        }

        my $tmpTime;
        my $metrics   = "controller_read_io_bandwidth_kBps,controller_write_io_bandwidth_kBps,controller_avg_io_latency_usecs";
        my $vdiskPerf = $nutanix->getVdiskPerf( $vdisk->{uuid}, $metrics, $timestamp_start, $timestamp_end, $interval, $api{$type}{'vdisk'} );
        for ( @{ $vdiskPerf->{"statsSpecificResponses"} } ) {
          my $vdiskMetrics = $_;
          $tmpTime = ceil( $vdiskMetrics->{startTimeInUsecs} / 1000000 );
          for ( @{ $vdiskMetrics->{values} } ) {
            my $value = $_;
            if ( $value < 0 ) { $value = 0; }
            $perf{vdisks}{ $vdisk->{uuid} }{$tmpTime}{ $vdiskMetrics->{metric} } = $value;
            $tmpTime += $interval;
          }
        }

        $metrics   = "controller_num_io,controller_num_write_io,controller_num_read_io";
        $vdiskPerf = $nutanix->getVdiskPerf( $vdisk->{uuid}, $metrics, $timestamp_start, $timestamp_end, $interval, $api{$type}{'vdisk'} );
        for ( @{ $vdiskPerf->{"statsSpecificResponses"} } ) {
          my $vdiskMetrics = $_;
          $tmpTime = ceil( $vdiskMetrics->{startTimeInUsecs} / 1000000 );
          for ( @{ $vdiskMetrics->{values} } ) {
            my $value = $_;
            if ( $value < 0 ) { $value = 0; }
            $perf{vdisks}{ $vdisk->{uuid} }{$tmpTime}{ $vdiskMetrics->{metric} } = $value / $interval;
            $tmpTime += $interval;
          }
        }

      }
    }
    $page++;
  }

  # Events
  my $events_start = time() - 172800;                      # last 2 days
  my $events       = $nutanix->getEvents($events_start);
  Nutanix::log("$hostcfg_label: fetching events");
  for ( @{ $events->{"entities"} } ) {
    my $event = $_;
    $alert{events}{ $event->{id} }{created_time_stamp_in_usecs}         = $event->{created_time_stamp_in_usecs};
    $alert{events}{ $event->{id} }{last_occurrence_time_stamp_in_usecs} = $event->{last_occurrence_time_stamp_in_usecs};
    $alert{events}{ $event->{id} }{severity}                            = $event->{severity};

    my $cc = 0;
    my %dict;
    my $dict;
    for ( @{ $event->{context_types} } ) {
      my $context = $_;
      $dict->{$context} = $event->{context_values}->[$cc];
      $cc += 1;
    }

    $alert{events}{ $event->{id} }{message} = $event->{message};
    for my $key ( keys %{$dict} ) {
      $alert{events}{ $event->{id} }{message} =~ s/{$key}/$dict->{$key}/g;
    }

    $alert{events}{ $event->{id} }{cluster}                      = $event->{cluster_uuid};
    $alert{events}{ $event->{id} }{alert_title}                  = $event->{alert_title};
    $alert{events}{ $event->{id} }{resolved_time_stamp_in_usecs} = $event->{resolved_time_stamp_in_usecs};
  }

  # Alerts
  my $alerts_start = time() - 172800;                      # last 2 days
  my $alerts       = $nutanix->getAlerts($alerts_start);
  Nutanix::log("$hostcfg_label: fetching alerts");
  for ( @{ $alerts->{"entities"} } ) {
    my $al = $_;

    $alert{alerts}{ $al->{id} }{created_time_stamp_in_usecs}         = $al->{created_time_stamp_in_usecs};
    $alert{alerts}{ $al->{id} }{last_occurrence_time_stamp_in_usecs} = $al->{last_occurrence_time_stamp_in_usecs};
    $alert{alerts}{ $al->{id} }{severity}                            = $al->{severity};

    my $cc = 0;
    my %dict;
    my $dict;
    for ( @{ $al->{context_types} } ) {
      my $context = $_;
      $dict->{$context} = $al->{context_values}->[$cc];
      $cc += 1;
    }

    $alert{alerts}{ $al->{id} }{message} = $al->{message};
    for my $key ( keys %{$dict} ) {
      $alert{alerts}{ $al->{id} }{message} =~ s/{$key}/$dict->{$key}/g;
    }

    $alert{alerts}{ $al->{id} }{cluster}     = $al->{cluster_uuid};
    $alert{alerts}{ $al->{id} }{alert_title} = $al->{alert_title};

    for my $key ( keys %{$dict} ) {
      $alert{alerts}{ $al->{id} }{alert_title} =~ s/{$key}/$dict->{$key}/g;
    }
    $alert{alerts}{ $al->{id} }{resolved_time_stamp_in_usecs} = $al->{resolved_time_stamp_in_usecs};
  }

  # Health status
  Nutanix::log("$hostcfg_label: fetching health status");
  my $critical = 0;
  my $hs_alias;
  if ( $health_cluster eq 'central' ) {
    $hs_alias = $hostcfg_label . "_central";
  }
  else {
    $hs_alias = $conf{'labels'}{'cluster'}{$health_cluster};
  }
  my @health_set = ( { "item" => "vms", "uuid_text" => "uuid" }, { "item" => "hosts", "uuid_text" => "uuid" }, { "item" => "disks", "uuid_text" => "diskUuid" }, { "item" => "storage_pools", "uuid_text" => "storagePoolUuid" }, { "item" => "containers", "uuid_text" => "containerUuid" }, { "item" => "clusters", "uuid_text" => "uuid" } );
  for (@health_set) {
    my $health_item = $_;
    my $healths     = $nutanix->getItemHealth( $health_item->{item} );
    for ( @{ $healths->{entities} } ) {
      my $health = $_;
      $hs{$health_cluster}{health}{ $health_item->{item} }{ $health->{ $health_item->{uuid_text} } }{status} = $health->{healthSummary}->{healthStatus};
      if ( $health->{healthSummary}->{healthStatus} ne "Good" ) {
        foreach my $key ( keys %{ $health->{healthSummary}->{healthCheckSummaries} } ) {
          if ( $health->{healthSummary}->{healthCheckSummaries}->{$key}->{healthStatus} ne "Good" ) {
            $hs{$health_cluster}{health}{ $health_item->{item} }{ $health->{ $health_item->{uuid_text} } }{errors}{$key}{id}     = $key;
            $hs{$health_cluster}{health}{ $health_item->{item} }{ $health->{ $health_item->{uuid_text} } }{errors}{$key}{status} = $health->{healthSummary}->{healthCheckSummaries}->{$key}->{healthStatus};
            my $test_response = $nutanix->getHealthCheck($key);
            if ( exists $test_response->{name} ) {
              $hs{$health_cluster}{health}{ $health_item->{item} }{ $health->{ $health_item->{uuid_text} } }{errors}{$key}{name}        = $test_response->{name};
              $hs{$health_cluster}{health}{ $health_item->{item} }{ $health->{ $health_item->{uuid_text} } }{errors}{$key}{description} = $test_response->{description};
            }
          }
        }
      }
    }
  }
  my $healths = $nutanix->getHealthSummary();
  if ( ref($healths) eq 'ARRAY' ) {
    for ( @{$healths} ) {
      my $health = $_;
      if ( defined $health->{entityType} ) {
        $hs{$health_cluster}{summary}{ $health->{entityType} }{Warning}  = $health->{healthSummary}->{Warning};
        $hs{$health_cluster}{summary}{ $health->{entityType} }{Critical} = $health->{healthSummary}->{Critical};
        $hs{$health_cluster}{summary}{ $health->{entityType} }{Unknown}  = $health->{healthSummary}->{Unknown};
        $hs{$health_cluster}{summary}{ $health->{entityType} }{Good}     = $health->{healthSummary}->{Good};
        $hs{$health_cluster}{summary}{ $health->{entityType} }{Error}    = $health->{healthSummary}->{Error};

        foreach my $id ( keys %{ $health->{detailedCheckSummary} } ) {
          my $test = $health->{detailedCheckSummary}->{$id};
          if ( ( $test->{Critical} eq "1" ) || ( $test->{Error} eq "1" ) ) {
            my $test_response = $nutanix->getHealthCheck($id);
            if ( exists $test_response->{name} ) {
              $hs{$health_cluster}{detail}{$id}{type}        = $health->{entityType};
              $hs{$health_cluster}{detail}{$id}{name}        = $test_response->{name};
              $hs{$health_cluster}{detail}{$id}{description} = $test_response->{description};

              if ( $test->{Critical} eq "1" ) {
                $hs{$health_cluster}{detail}{$id}{severity} = "Critical";
              }
              else {
                $hs{$health_cluster}{detail}{$id}{severity} = "Error";
              }
            }
            $critical = 1;
          }
        }
      }
    }
  }
  if ( $critical == 1 ) {
    statusFile( $hs_alias,         'nok' );
    statusFile( 'Nutanix_central', 'nok' );
  }
  else {
    statusFile( $hs_alias, 'ok' );
  }

  # Save conf
  Nutanix::log("$hostcfg_label: saving data to json");
  if (%conf) {
    open my $fc, ">", $path_prefix . "/conf/" . $hostcfg_uuid . "_conf.json";
    print $fc JSON->new->utf8->pretty->encode( \%conf );
    close $fc;

    # last timestmap
    open my $hl, ">", $path_prefix . "/" . $hostcfg_uuid . "_last.json";
    print $hl "{\"timestamp\":\"$timestamp_end\"}";
    close $hl;
  }
  if (%alert) {
    open my $fa, ">", $path_prefix . "/conf/" . $hostcfg_uuid . "_alerts.json";
    print $fa JSON->new->utf8->pretty->encode( \%alert );
    close $fa;
  }
  if (%hs) {
    open my $he, ">", $path_prefix . "/conf/" . $hostcfg_uuid . "_health.json";
    print $he JSON->new->utf8->pretty->encode( \%hs );
    close $he;
  }

  # Save perf
  savePerf( \%perf, $hostcfg_uuid, $timestamp_start, $timestamp_end, $index );

}

sub savePerf {
  my ( $data, $uuid, $start, $end, $index ) = @_;

  open my $fh, ">", $json_path . "/" . $uuid . "_" . $start . "_" . $end . "_" . $index . "_perf.json";
  print $fh JSON->new->pretty(0)->encode($data);
  close $fh;
}

sub saveRaw {
  my ( $data, $uuid, $type ) = @_;

  if (ref $data eq ref {}) {
    open my $fh, ">", $raw_path . "/" . $uuid . "_" . $type . "_raw.json";
    print $fh JSON->new->utf8->pretty->encode($data);
    close $fh;
  } else {
    open my $fh, ">", $raw_path . "/" . $uuid . "_" . $type . "_raw.txt";
    print $fh $data;
    close $fh;
  }
}

sub statusFile {
  my $alias = shift;
  my $state = shift;
  my %timestamp;

  my $hss_dir = "$input_dir/tmp/health_status_summary/";
  my $hsm_dir = "$input_dir/tmp/health_status_summary/Nutanix/";
  unless ( -d $hss_dir ) {
    mkdir( "$hss_dir", 0755 ) || warn( localtime() . ": Cannot mkdir $hss_dir: $!" . __FILE__ . ':' . __LINE__ );
  }
  unless ( -d $hsm_dir ) {
    mkdir( "$hsm_dir", 0755 ) || warn( localtime() . ": Cannot mkdir $hsm_dir: $!" . __FILE__ . ':' . __LINE__ );
  }

  my $okFile  = "$input_dir/tmp/health_status_summary/Nutanix/" . $alias . ".ok";
  my $nokFile = "$input_dir/tmp/health_status_summary/Nutanix/" . $alias . ".nok";

  if ( $state eq 'nok' ) {
    if ( -e $okFile ) {
      unlink($okFile);
    }
    my $timestamp = time();
    open my $st, ">", $nokFile;
    $timestamp{timestamp} = time();
    print $st JSON->new->pretty->encode( \%timestamp );
    close($st);
  }

  if ( $state eq 'ok' ) {
    if ( -e $nokFile ) {
      unlink($nokFile);
    }
    my $timestamp = time();
    open my $st, ">", $okFile;
    $timestamp{timestamp} = time();
    print $st JSON->new->pretty->encode( \%timestamp );
    close($st);
  }
}

