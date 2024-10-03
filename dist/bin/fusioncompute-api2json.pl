# fusioncompute-api2json.pl
# download API data

use 5.008_008;

use strict;
use warnings;

use HostCfg;
use Nutanix;
use JSON;
use Data::Dumper;
use POSIX;
use FusionCompute;

defined $ENV{INPUTDIR} || warn( localtime() . ': INPUTDIR undefined, probably have not read etc/lpar2rrd.cfg ' . __FILE__ . ':' . __LINE__ ) && exit 1;

if ( keys %{ HostCfg::getHostConnections('FusionCompute') } == 0 ) {
  exit(0);
}

my $input_dir   = $ENV{INPUTDIR};
my $path_prefix = "$input_dir/data/FusionCompute";
my $json_path   = "$path_prefix/json";
my $conf_path   = "$path_prefix/conf";
my $raw_path    = "$path_prefix/raw";

my @cluster_metrics = ( 'cpu_usage', 'mem_usage',      'logic_disk_usage', 'disk_io_in',     'disk_io_out', 'nic_byte_in_usage', 'nic_byte_out_usage', 'nic_byte_in', 'nic_byte_out' );
my @host_metrics    = ( 'cpu_usage', 'dom0_cpu_usage', 'mem_usage',        'dom0_mem_usage', 'nic_byte_in', 'nic_byte_out',      'nic_pkg_send',       'nic_pkg_rcv', 'nic_byte_in_usage', 'nic_byte_out_usage', 'nic_pkg_rx_drop_speed', 'nic_pkg_tx_drop_speed', 'disk_io_in', 'disk_io_out', 'disk_io_read', 'disk_io_write', 'logic_disk_usage', 'domU_cpu_usage', 'domU_mem_usage' );
my @vm_metrics      = ( 'cpu_usage', 'mem_usage',      'disk_usage',       'disk_io_in',     'disk_io_out', 'disk_req_in',       'disk_req_out',       'disk_rd_ios', 'disk_wr_ios', 'disk_iowr_ticks', 'disk_iord_ticks', 'disk_rd_sectors', 'disk_wr_sectors', 'disk_tot_ticks', 'nic_byte_in', 'nic_byte_out', 'nic_byte_in_out', 'nic_rx_drop_pkt_speed', 'nic_tx_drop_pkt_speed' );

# create directories in data/
my @create_dir = ( $path_prefix, $json_path, $conf_path, $raw_path );
for (@create_dir) {
  my $dir = $_;
  unless ( -d $dir ) {
    mkdir( "$dir", 0755 ) || warn( localtime() . ": Cannot mkdir $dir: $!" . __FILE__ . ':' . __LINE__ );
  }
}

my %hosts = %{ HostCfg::getHostConnections('FusionCompute') };
my @pids;
my $pid;
my $timeout = 900;
my %conf_hash;

my $interval = 60;                  # metrics interval
my $page_max = 100;                 # items in page
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
      local $SIG{ALRM} = sub { die "FusionCompute API2JSON: $pid timeouted.\n"; };
      alarm($timeout);

      my ( $protocol, $hostname, $port, $username, $password, $usertype, $f_version ) = ( $hosts{$host}{proto}, $hosts{$host}{host}, $hosts{$host}{api_port}, $hosts{$host}{username}, $hosts{$host}{password}, $hosts{$host}{usertype}, $hosts{$host}{version} );
      api2json( $protocol, $hostname, $port, $username, $password, $uuid, $host, $usertype, $f_version );
      exit;
    }
  }
}

# wait for forked data retrieval
for $pid (@pids) {
  waitpid( $pid, 0 );
}

# merge conf
FusionCompute::log("Configuration: merging and saving");
opendir( DH, "$conf_path" ) || die "Could not open '$conf_path' for reading '$!'\n";
my @files = grep /.*.json/, readdir DH;
my %conf;
my %specification;
my %label;
my %architecture;
my %alarms;
my %urn;
my $data;

foreach my $file ( sort @files ) {
  my @splits = split /_/, $file;
  if ( !defined $conf_hash{ $splits[0] } ) {
    FusionCompute::log("Configuration: skipping old conf $file");
    next;
  }

  FusionCompute::log("Configuration: processing $file");

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
    error("Empty conf file, deleting $conf_path/$file");
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
    foreach my $key ( keys %{ $data->{label} } ) {
      foreach my $key2 ( keys %{ $data->{label}->{$key} } ) {
        $label{label}{$key}{$key2} = $data->{label}->{$key}->{$key2};
      }
    }
  }
  elsif ( $splits[1] eq "alerts.json" ) {
    foreach my $key ( keys %{$data} ) {
      $alarms{$key} = $data->{$key};
    }
  }
  elsif ( $splits[1] eq "urn.json" ) {
    foreach my $key ( keys %{$data} ) {
      $urn{$key} = $data->{$key};
    }
  }

  #save merged
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
  if (%alarms) {
    open my $fa, ">", $path_prefix . "/alerts.json";
    print $fa JSON->new->utf8->pretty->encode( \%alarms );
    close $fa;
  }
  if (%urn) {
    open my $fa, ">", $path_prefix . "/urn.json";
    print $fa JSON->new->utf8->pretty->encode( \%urn );
    close $fa;
  }
}

sub api2json {
  my ( $protocol, $hostname, $port, $username, $password, $hostcfg_uuid, $hostcfg_label, $usertype, $f_version ) = @_;

  if ( defined $f_version ) {
    FusionCompute::log( "Version: " . $f_version );
  }
  else {
    FusionCompute::log("Version is not set, please set the version in the configuration");
  }

  my $encrypted = 1;
  eval {
    require Digest::SHA;
    $password = Digest::SHA::sha256_hex($password);
  };

  if ($@) {
    $encrypted = 0;
  }

  if ( $encrypted eq "0" ) {
    FusionCompute::log("Digest::SHA module not found");
  }

  my $fusioncompute = FusionCompute->new( $protocol, $hostname, $port, $f_version );
  my $auth          = $fusioncompute->auth( $username, $password, $usertype, $encrypted );

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
  my $timestamp_data = FusionCompute::decode_json_eval($timestamp_json);
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

  my $index = 1;
  my %conf;
  my %perf;
  my %dict;
  my %alarm;
  my %urn;

  my $sites = $fusioncompute->listSites();
  saveRaw( $sites, $hostcfg_uuid, 'sites' );
  for ( @{ $sites->{sites} } ) {
    my $site      = $_;
    my $site_id   = FusionCompute::urnToId( $site->{urn}, 2 );
    my $site_uuid = $site->{urn};
    $site_uuid =~ s/:/-/g;
    $urn{ $site->{urn} } = {
      "subsystem" => "site",
      "uuid"      => $site_uuid,
      "label"     => $site->{name}
    };

    FusionCompute::log( "Site: fetching " . $site->{name} );

    $conf{label}{site}{$site_uuid} = $site->{name};

    $conf{specification}{site}{$site_uuid}{name}            = $site->{name};
    $conf{specification}{site}{$site_uuid}{status}          = $site->{status};
    $conf{specification}{site}{$site_uuid}{uri}             = $site->{uri};
    $conf{specification}{site}{$site_uuid}{mgntNetworkType} = $site->{mgntNetworkType};
    $conf{specification}{site}{$site_uuid}{ip}              = $site->{ip};
    $conf{specification}{site}{$site_uuid}{hostcfg_uuid}    = $hostcfg_uuid;

    # Clusters under site
    my $clusters = $fusioncompute->listClusters($site_id);
    FusionCompute::log("Clusters: fetching clusters");
    saveRaw( $clusters, $hostcfg_uuid, 'clusters' );
    for ( @{ $clusters->{clusters} } ) {
      my $cluster      = $_;
      my $cluster_id   = FusionCompute::urnToId( $cluster->{urn}, 4 );
      my $cluster_uuid = $cluster->{urn};
      $cluster_uuid =~ s/:/-/g;
      $urn{ $cluster->{urn} } = {
        "subsystem" => "cluster",
        "uuid"      => $cluster_uuid,
        "label"     => $cluster->{name}
      };

      $conf{label}{cluster}{$cluster_uuid} = $cluster->{name};

      $conf{specification}{cluster}{$cluster_uuid}{name} = $cluster->{name};

      if ( exists $conf{architecture}{site_cluster}{$site_uuid}[0] ) {
        push( @{ $conf{architecture}{site_cluster}{$site_uuid} }, $cluster_uuid );
      }
      else {
        $conf{architecture}{site_cluster}{$site_uuid}[0] = $cluster_uuid;
      }

      # metrics
      my $metrics = $fusioncompute->getMetrics( $site_id, $cluster->{urn}, \@cluster_metrics, "$timestamp_start", "$timestamp_end", "$interval" );
      for my $metric_item ( @{ $metrics->{items} } ) {
        for my $metric_value ( @{ $metric_item->{metricValue} } ) {
          $perf{cluster}{$cluster_uuid}{ $metric_value->{time} }{ $metric_item->{metricId} } = $metric_value->{value};
        }
      }

    }

    # Hosts under site
    my $hosts = $fusioncompute->listHosts($site_id);
    FusionCompute::log( "Hosts: fetching " . $hosts->{total} . " hosts" );
    saveRaw( $hosts, $hostcfg_uuid, 'hosts' );
    for ( @{ $hosts->{hosts} } ) {
      my $host      = $_;
      my $host_id   = FusionCompute::urnToId( $host->{urn}, 4 );
      my $host_uuid = ( defined $host->{uuid} ) ? $host->{uuid} : $host->{urn};
      $host_uuid =~ s/:/-/g;
      $dict{ $host->{urn} } = $host_uuid;
      $urn{ $host->{urn} }  = {
        "subsystem" => "host",
        "uuid"      => $host_uuid,
        "label"     => $host->{name}
      };

      $conf{label}{host}{$host_uuid} = $host->{name};

      $conf{specification}{host}{$host_uuid}{name}              = $host->{name};
      $conf{specification}{host}{$host_uuid}{hostMultiPathMode} = $host->{hostMultiPathMode};
      $conf{specification}{host}{$host_uuid}{status}            = $host->{status};
      $conf{specification}{host}{$host_uuid}{multiPathMode}     = $host->{multiPathMode};
      $conf{specification}{host}{$host_uuid}{ip}                = $host->{ip};
      $conf{specification}{host}{$host_uuid}{isMaintaining}     = $host->{isMaintaining};
      $conf{specification}{host}{$host_uuid}{cpuMHz}            = $host->{cpuMHz};
      $conf{specification}{host}{$host_uuid}{cpuQuantity}       = $host->{cpuQuantity};
      $conf{specification}{host}{$host_uuid}{memQuantityMB}     = $host->{memQuantityMB};
      $conf{specification}{host}{$host_uuid}{clusterName}       = $host->{clusterName};

      if ( exists $conf{architecture}{site_host}{$site_uuid}[0] ) {
        push( @{ $conf{architecture}{site_host}{$site_uuid} }, $host_uuid );
      }
      else {
        $conf{architecture}{site_host}{$site_uuid}[0] = $host_uuid;
      }

      my $cluster_uuid = $host->{clusterUrn};
      $cluster_uuid =~ s/:/-/g;
      if ( exists $conf{architecture}{cluster_host}{$cluster_uuid}[0] ) {
        push( @{ $conf{architecture}{cluster_host}{$cluster_uuid} }, $host_uuid );
      }
      else {
        $conf{architecture}{cluster_host}{$cluster_uuid}[0] = $host_uuid;
      }

      # detailed info
      my $hostDetail = $fusioncompute->getHost( $site_id, $host_id );

      # metrics
      my $i2m     = 1;
      my $metrics = $fusioncompute->getMetrics( $site_id, $host->{urn}, \@host_metrics, "$timestamp_start", "$timestamp_end", "$interval" );
      for my $metric_item ( @{ $metrics->{items} } ) {
        for my $metric_value ( @{ $metric_item->{metricValue} } ) {
          $perf{host}{$host_uuid}{ $metric_value->{time} }{ $metric_item->{metricId} } = $metric_value->{value};
          if ( $i2m == 1 ) {
            if ( defined $hostDetail->{cpuRealCores} && defined $hostDetail->{cpusReserve} ) {
              $perf{host}{$host_uuid}{ $metric_value->{time} }{cpuRealCoresWithoutReserved} = $hostDetail->{cpuRealCores} - $hostDetail->{cpusReserve};
            }
            elsif ( defined $hostDetail->{cpuQuantity} ) {
              $perf{host}{$host_uuid}{ $metric_value->{time} }{cpuRealCoresWithoutReserved} = $hostDetail->{cpuQuantity};
            }
            else {
              $perf{host}{$host_uuid}{ $metric_value->{time} }{cpuRealCoresWithoutReserved} = ();
            }
            if ( defined $hostDetail->{cpuRealCores} ) {
              $perf{host}{$host_uuid}{ $metric_value->{time} }{cpuRealCores} = $hostDetail->{cpuRealCores};
            }
            elsif ( defined $hostDetail->{cpuQuantity} ) {
              $perf{host}{$host_uuid}{ $metric_value->{time} }{cpuRealCores} = $hostDetail->{cpuQuantity};
            }
            else {
              $perf{host}{$host_uuid}{ $metric_value->{time} }{cpuRealCores} = ();
            }
            if ( defined $hostDetail->{hostTotalSizeMB} ) {
              $perf{host}{$host_uuid}{ $metric_value->{time} }{hostTotalSizeMB} = $hostDetail->{hostTotalSizeMB};
            }
            elsif ( defined $hostDetail->{memQuantityMB} ) {
              $perf{host}{$host_uuid}{ $metric_value->{time} }{hostTotalSizeMB} = $hostDetail->{memQuantityMB};
            }
            else {
              $perf{host}{$host_uuid}{ $metric_value->{time} }{hostTotalSizeMB} = ();
            }
          }
        }
        $i2m = 0;
      }
    }
    $hosts = ();

    # VMs under site
    my $loop   = 1;
    my $page   = 1;
    my $offset = 0;
    while ( $loop eq "1" ) {
      my $vms = $fusioncompute->listVMs( $site_id, $page_max, $offset );
      saveRaw( $vms, $hostcfg_uuid, 'vms_' . $page );
      my $count = $vms->{total} > $page * $page_max ? $page_max : $vms->{total} - ( ( $page - 1 ) * $page_max );
      my $end   = floor( $vms->{total} / $page_max );
      if ( $end == 0 ) { $end = 1; }
      FusionCompute::log("VMs: fetching $count vms [step $page/$end]");

      for ( @{ $vms->{vms} } ) {
        my $vm = $_;
        $urn{ $vm->{urn} } = {
          "subsystem" => "vm",
          "uuid"      => $vm->{uuid},
          "label"     => $vm->{name}
        };

        my $vm_id = FusionCompute::urnToId( $vm->{urn}, 4 );
        $conf{label}{vm}{ $vm->{uuid} } = $vm->{name};

        $conf{specification}{vm}{ $vm->{uuid} }{name}        = $vm->{name};
        $conf{specification}{vm}{ $vm->{uuid} }{arch}        = $vm->{arch};
        $conf{specification}{vm}{ $vm->{uuid} }{status}      = $vm->{status};
        $conf{specification}{vm}{ $vm->{uuid} }{cdRomStatus} = $vm->{cdRomStatus};
        $conf{specification}{vm}{ $vm->{uuid} }{createTime}  = $vm->{createTime};
        $conf{specification}{vm}{ $vm->{uuid} }{hostName}    = $vm->{hostName};
        $conf{specification}{vm}{ $vm->{uuid} }{hostUuid}    = $dict{ $vm->{hostUrn} };
        $conf{specification}{vm}{ $vm->{uuid} }{clusterName} = $vm->{clusterName};

        if ( exists $conf{architecture}{site_vm}{$site_uuid}[0] ) {
          push( @{ $conf{architecture}{site_vm}{$site_uuid} }, $vm->{uuid} );
        }
        else {
          $conf{architecture}{site_vm}{$site_uuid}[0] = $vm->{uuid};
        }

        my $cluster_uuid = $vm->{clusterUrn};
        $cluster_uuid =~ s/:/-/g;
        if ( exists $conf{architecture}{cluster_vm}{$cluster_uuid}[0] ) {
          push( @{ $conf{architecture}{cluster_vm}{$cluster_uuid} }, $vm->{uuid} );
        }
        else {
          $conf{architecture}{cluster_vm}{$cluster_uuid}[0] = $vm->{uuid};
        }

        my $host_uuid = $dict{ $vm->{hostUrn} };
        if ( defined $host_uuid ) {
          if ( exists $conf{architecture}{host_vm}{$host_uuid}[0] ) {
            push( @{ $conf{architecture}{host_vm}{$host_uuid} }, $vm->{uuid} );
          }
          else {
            $conf{architecture}{host_vm}{$host_uuid}[0] = $vm->{uuid};
          }
        }

        # detailed info
        my $vmDetail = $fusioncompute->getVM( $site_id, $vm_id );

        # metrics
        my $i2m     = 1;
        my $metrics = $fusioncompute->getMetrics( $site_id, $vm->{urn}, \@vm_metrics, "$timestamp_start", "$timestamp_end", "$interval" );
        for my $metric_item ( @{ $metrics->{items} } ) {
          for my $metric_value ( @{ $metric_item->{metricValue} } ) {
            $perf{vm}{ $vm->{uuid} }{ $metric_value->{time} }{ $metric_item->{metricId} } = $metric_value->{value};
            if ( $i2m == 1 ) {
              $perf{vm}{ $vm->{uuid} }{ $metric_value->{time} }{cpuQuantity}      = $vmDetail->{vmConfig}{cpu}{quantity};
              $perf{vm}{ $vm->{uuid} }{ $metric_value->{time} }{coresPerSocket}   = $vmDetail->{vmConfig}{cpu}{coresPerSocket};
              $perf{vm}{ $vm->{uuid} }{ $metric_value->{time} }{memoryQuantityMB} = $vmDetail->{vmConfig}{memory}{quantityMB};
            }
          }
          $i2m = 0;
        }
      }

      $offset = $offset + $page_max;
      $page++;
      if ( $offset > $vms->{total} ) {
        $loop = 0;
      }
    }

    # Datastores under site
    my $datastores = $fusioncompute->listDatastores($site_id);
    FusionCompute::log( "Datastores: fetching " . $datastores->{total} . " datastores" );
    saveRaw( $datastores, $hostcfg_uuid, 'datastores' );
    for ( @{ $datastores->{datastores} } ) {
      my $datastore      = $_;
      my $datastore_id   = FusionCompute::urnToId( $datastore->{urn}, 4 );
      my $datastore_uuid = $datastore->{urn};
      $datastore_uuid =~ s/:/-/g;
      $urn{ $datastore->{urn} } = {
        "subsystem" => "datastore",
        "uuid"      => $datastore_uuid,
        "label"     => $datastore->{name}
      };

      $conf{label}{datastore}{$datastore_uuid} = $datastore->{name};

      $conf{specification}{datastore}{$datastore_uuid}{name}        = $datastore->{name};
      $conf{specification}{datastore}{$datastore_uuid}{storageType} = $datastore->{storageType};
      $conf{specification}{datastore}{$datastore_uuid}{status}      = $datastore->{status};
      $conf{specification}{datastore}{$datastore_uuid}{isThin}      = $datastore->{isThin};
      $conf{specification}{datastore}{$datastore_uuid}{thinRate}    = $datastore->{thinRate};
      $conf{specification}{datastore}{$datastore_uuid}{description} = $datastore->{description};
      $conf{specification}{datastore}{$datastore_uuid}{capacityGB}  = $datastore->{capacityGB};

      if ( exists $conf{architecture}{site_datastore}{$site_uuid}[0] ) {
        push( @{ $conf{architecture}{site_datastore}{$site_uuid} }, $datastore_uuid );
      }
      else {
        $conf{architecture}{site_datastore}{$site_uuid}[0] = $datastore_uuid;
      }

      my $timestamp_actual = $timestamp_start;
      while ( $timestamp_actual < $timestamp_end ) {
        $perf{datastore}{$datastore_uuid}{$timestamp_actual}{capacityGB} = $datastore->{capacityGB};
        $perf{datastore}{$datastore_uuid}{$timestamp_actual}{usedSizeGB} = $datastore->{usedSizeGB};
        $perf{datastore}{$datastore_uuid}{$timestamp_actual}{freeSizeGB} = $datastore->{freeSizeGB};
        $timestamp_actual += $interval;
      }
    }
    $datastores = ();

    # alarms
    my $alarms = $fusioncompute->getActiveAlarms($site_id);
    FusionCompute::log( "Alarms: fetching " . $alarms->{total} . " active alarms" ) if ( !defined $alarms->{errorCode} );
    saveRaw( $alarms, $hostcfg_uuid, 'alarms' );
    for ( @{ $alarms->{items} } ) {
      my $item = $_;

      if ( $item->{dtClearTime} ne "-" ) {
        next;
      }

      my %alarm_site = (
        "svAlarmName"    => $item->{svAlarmName},
        "iAlarmCategory" => $item->{iAlarmCategory},
        "iAlarmLevel"    => $item->{iAlarmLevel},
        "dtArrivedTime"  => $item->{dtArrivedTime},
        "svAlarmCause"   => $item->{svAlarmCause},
        "objectUrn"      => $item->{objectUrn},
        "urnByName"      => $item->{urnByName}
      );

      if ( exists $alarm{ "urn-sites-" . $site_id }[0] ) {
        push( @{ $alarm{ "urn-sites-" . $site_id } }, \%alarm_site );
      }
      else {
        $alarm{ "urn-sites-" . $site_id }[0] = \%alarm_site;
      }
    }
  }

  # Save conf
  FusionCompute::log("$hostcfg_label: saving data to json");
  if (%conf) {
    open my $fc, ">", $path_prefix . "/conf/" . $hostcfg_uuid . "_conf.json";
    print $fc JSON->new->utf8->pretty->encode( \%conf );
    close $fc;

    # last timestmap
    open my $hl, ">", $path_prefix . "/" . $hostcfg_uuid . "_last.json";
    print $hl "{\"timestamp\":\"$timestamp_end\"}";
    close $hl;

    # alerts
    open my $ha, ">", $path_prefix . "/conf/" . $hostcfg_uuid . "_alerts.json";
    print $ha JSON->new->utf8->pretty->encode( \%alarm );
    close $ha;

    # urn
    open my $hu, ">", $path_prefix . "/conf/" . $hostcfg_uuid . "_urn.json";
    print $hu JSON->new->utf8->pretty->encode( \%urn );
    close $hu;
  }

  # Save perf
  savePerf( \%perf, $hostcfg_uuid, $timestamp_start, $timestamp_end, $index );

}

sub saveRaw {
  my ( $data, $uuid, $type ) = @_;

  open my $fh, ">", $raw_path . "/" . $uuid . "_" . $type . "_raw.json";
  print $fh JSON->new->utf8->pretty->encode($data);
  close $fh;
}

sub savePerf {
  my ( $data, $uuid, $start, $end, $index ) = @_;

  open my $fh, ">", $json_path . "/" . $uuid . "_" . $start . "_" . $end . "_" . $index . "_perf.json";
  print $fh JSON->new->utf8->pretty(0)->encode($data);
  close $fh;
}
