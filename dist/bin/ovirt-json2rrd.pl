use 5.008_008;

use strict;
use warnings;

use RRDp;
use Data::Dumper;
use File::Copy;
use Xorux_lib qw(error read_json write_json);
use OVirtDataWrapper;
use OVirtLoadDataModule;
use POSIX ":sys_wait_h";

defined $ENV{INPUTDIR} || warn( ' INPUTDIR undefined, config etc/lpar2rrd.cfg probably has not been loaded ' . __FILE__ . ':' . __LINE__ ) && exit 1;

my $upgrade              = defined $ENV{UPGRADE} ? $ENV{UPGRADE} : 0;
my $rrdtool              = $ENV{RRDTOOL};
my $inputdir             = $ENV{INPUTDIR};
my $tmpdir               = "$inputdir/tmp";
my $ovirt_dir            = "$inputdir/data/oVirt";
my $iostats_dir          = "$ovirt_dir/iostats";
my $host_data_dir        = "$ovirt_dir/host";
my $storage_data_dir     = "$ovirt_dir/storage";
my $vm_data_dir          = "$ovirt_dir/vm";
my $conf_dir             = "$ovirt_dir/configuration";
my $metadata_file        = "$ovirt_dir/metadata.json";
my $metadata_tmp_file    = "$metadata_file-part";
my $agents_uuid_file     = "$inputdir/data/Linux--unknown/no_hmc/linux_uuid_name.json";
my $win_agents_uuid_file = "$tmpdir/win_host_uuid.json";
my $conf_touch_file      = "$inputdir/tmp/oVirt_genconf.touch";
my $act_time             = time;

my $ovirt_data_update_timeout = 1800;
my %metadata_loaded;
my %metadata;
my %processed_on_host;
my %conf_values;
my %nic_parent_map;
my $rrd_start_time;
my $data;
my $db_hostname;

my $LPAR2RRD_FORK_MAX = defined $ENV{LPAR2RRD_FORK_MAX} && $ENV{LPAR2RRD_FORK_MAX} =~ /^\d{1,3}$/ ? $ENV{LPAR2RRD_FORK_MAX} : 16;

################################################################################

unless ( -d $ovirt_dir ) {
  mkdir( "$ovirt_dir", 0755 ) || Xorux_lib::error( "Cannot mkdir $ovirt_dir: $!" . __FILE__ . ':' . __LINE__ ) && exit;
}
unless ( -d $vm_data_dir ) {
  mkdir( "$vm_data_dir", 0755 ) || Xorux_lib::error( "Cannot mkdir $vm_data_dir: $!" . __FILE__ . ':' . __LINE__ ) && exit;
}

unless ( -d $host_data_dir ) {
  mkdir( $host_data_dir, 0755 ) || Xorux_lib::error( "Cannot mkdir $host_data_dir: $!" . __FILE__ . ':' . __LINE__ ) && exit;
}

unless ( -d $storage_data_dir ) {
  mkdir( $storage_data_dir, 0755 ) || Xorux_lib::error( "Cannot mkdir $storage_data_dir: $!" . __FILE__ . ':' . __LINE__ ) && exit;
}

unless ( -d $conf_dir ) {
  mkdir( $conf_dir, 0755 ) || Xorux_lib::error( "Cannot mkdir $conf_dir: $!" . __FILE__ . ':' . __LINE__ ) && exit;
}

unless ( -d $iostats_dir ) {
  print "ovirt-json2rrd.pl : no iostats dir, skip\n";
  exit 1;
}

my ( $mapping_code,     $linux_uuids ) = -f $agents_uuid_file     ? Xorux_lib::read_json($agents_uuid_file)     : ( 0, undef );
my ( $win_mapping_code, $win_uuids )   = -f $win_agents_uuid_file ? Xorux_lib::read_json($win_agents_uuid_file) : ( 0, undef );
print Dumper ($win_uuids);

update_backup_files();
load_metadata();
load_perf_data();

exit 0;

################################################################################

sub load_perf_data {
  my @pids;
  my $pid;

  my $rrdtool_version = 'Unknown';
  $_ = `$rrdtool`;
  if (/^RRDtool ([1-9]*\.[0-9]*(\.[0-9]*)?)/) {
    $rrdtool_version = $1;
  }
  print "RRDp    version   : $RRDp::VERSION \n";
  print "RRDtool version   : $rrdtool_version\n";

  opendir( my $DH, $iostats_dir ) || Xorux_lib::error("Could not open '$iostats_dir' for reading '$!'\n") && exit;
  my @files = sort( grep /.*perf\d{3}\.json/, readdir $DH );
  closedir $DH;

  my $file_count = scalar @files;
  my $fork_no    = $file_count > $LPAR2RRD_FORK_MAX ? $LPAR2RRD_FORK_MAX : $file_count;

  print "ovirt-json2rrd.pl : processing $file_count perf files with $fork_no forks\n";

  my $i = 0;
  while ( $i < $fork_no ) {
    unless ( defined( $pid = fork() ) ) {
      Xorux_lib::error( "Error: failed to fork:" . __FILE__ . ":" . __LINE__ );
      next;
    }
    else {
      if ($pid) {
        push @pids, $pid;
        $i++;
      }
      else {
        last;
      }
    }
  }

  unless ($pid) {
    while ( $i < $file_count ) {
      load_perf_file( $files[$i] );
      $i += $LPAR2RRD_FORK_MAX;
    }

    exit 0;
  }

  for $pid (@pids) {
    waitpid( $pid, 0 );
  }

  return 1;
}

sub load_perf_file {
  my $file = shift;
  my ( $code, $ref );

  RRDp::start "$rrdtool";

  # read perf file
  if ( -f "$iostats_dir/$file" ) {
    ( $code, $ref ) = Xorux_lib::read_json("$iostats_dir/$file");
    backup_file($file);

    unless ($code) {
      print "ovirt-json2rrd.pl : file $file cannot be loaded\n";
      Xorux_lib::error( "Perf file $file cannot be loaded " . __FILE__ . ":" . __LINE__ );
      return 0;
    }
  }

  # check if metadata for this perf file are correctly loaded
  $file =~ /(.*)_\d{4}_\d{4}_\d{4}_perf\d{3}\.json$/;
  $db_hostname = $1;

  unless ( $metadata_loaded{$db_hostname} ) {
    print "ovirt-json2rrd.pl : no metadata for host $db_hostname, skipping file $file\n";
    Xorux_lib::error( "No metadata for host $db_hostname, perf file $file cannot be processed " . __FILE__ . ":" . __LINE__ );
    return 0;
  }

  $data = $ref;
  print "ovirt-json2rrd.pl : processing file $file\n";

  eval {
    foreach my $type ( keys %{$data} ) {
      foreach my $uuid ( keys %{ $data->{$type} } ) {
        my $perf_data = $data->{$type}{$uuid};
        my ( $rrd_path, $rrd_path2 );

        # VMs, disks, VM NICs and storage domains can migrate between DB hosts and can remain in old DB
        if ( !defined $processed_on_host{$uuid} ) {
          print "ovirt-json2rrd.pl : skipping $type with ID $uuid on $db_hostname, its configuration wasn't processed\n";
          next;
        }
        elsif ( $processed_on_host{$uuid} ne $db_hostname ) {
          print "ovirt-json2rrd.pl : skipping $type with ID $uuid on $db_hostname, already processed on host $processed_on_host{$uuid}\n";
          next;
        }

        if ( $type =~ /^(vm_nic|host_nic)$/ ) {

          # due to folder structure NICs need their parent uuid to get filepath
          my $parent_uuid = $nic_parent_map{$1}{$uuid};

          next unless ( defined $parent_uuid );
          $rrd_path = OVirtDataWrapper::get_filepath_rrd( { type => $type, uuid => $parent_uuid, id => $uuid, skip_acl => 1 } );
        }
        elsif ( $type =~ /disk/ ) {
          $rrd_path  = OVirtDataWrapper::get_filepath_rrd( { type => $type, uuid   => $uuid, skip_acl => 1 } );
          $rrd_path2 = OVirtDataWrapper::get_filepath_rrd( { type => $type, metric => 'iops', uuid => $uuid, skip_acl => 1 } );
        }
        else {
          $rrd_path = OVirtDataWrapper::get_filepath_rrd( { type => $type, uuid => $uuid, skip_acl => 1 } );
        }

        unless ( -f $rrd_path ) {
          OVirtLoadDataModule::create_rrd( $rrd_path, $act_time, $type );
        }
        if ( defined $rrd_path2 && !-f $rrd_path2 ) {
          OVirtLoadDataModule::create_rrd( $rrd_path2, $act_time, $type . '2' );
        }

        # update RRDs
        if ( $type eq 'host' ) {
          OVirtLoadDataModule::update_rrd_host( $rrd_path, $perf_data, $conf_values{host}{$uuid} );
        }
        elsif ( $type eq 'vm' ) {
          OVirtLoadDataModule::update_rrd_vm( $rrd_path, $perf_data, $conf_values{vm}{$uuid} );
        }
        elsif ( $type eq 'disk' ) {
          OVirtLoadDataModule::update_rrd_disk( $rrd_path, $perf_data, $conf_values{disk}{$uuid} );
          OVirtLoadDataModule::update_rrd_disk_iops( $rrd_path2, $perf_data, $conf_values{disk}{$uuid} );
        }
        elsif ( $type eq 'storage_domain' ) {
          OVirtLoadDataModule::update_rrd_storage_domain( $rrd_path, $perf_data );
        }
        elsif ( $type =~ /^(vm|host)_nic$/ ) {
          OVirtLoadDataModule::update_rrd_nic( $rrd_path, $perf_data );
        }
      }
    }
  };
  if ($@) {
    Xorux_lib::error( "Error while saving data from $file to RRDs: $@ : " . __FILE__ . ':' . __LINE__ );
  }

  RRDp::end;
  return 1;
}

################################################################################

sub load_metadata {
  my $save_conf_flag = check_configuration_update();

  opendir( my $DH, $iostats_dir ) || Xorux_lib::error("Could not open '$iostats_dir' for reading '$!'\n") && exit;
  my @files = grep /.*conf\.json/, readdir $DH;
  closedir $DH;

  unless ( scalar @files ) {
    print "ovirt-json2rrd.pl : no data files, skip\n";
    exit 1;
  }

  foreach my $file ( sort @files ) {
    my ( $code, $ref );

    if ( -f "$iostats_dir/$file" ) {
      ( $code, $ref ) = Xorux_lib::read_json("$iostats_dir/$file");
      backup_file($file);
    }

    if ($code) {
      eval {
        $data        = $ref;
        $db_hostname = $data->{db_hostname};
        print "ovirt-json2rrd.pl : processing file $file\n";

        unless ( defined $db_hostname ) {
          print "ovirt-json2rrd.pl : missing hostname in file $file\n";
          Xorux_lib::error( "Missing hostname in file $file cannot be processed " . __FILE__ . ":" . __LINE__ );
          next;
        }

        load_datacenters();
        load_clusters();
        load_hosts();
        load_host_nics();
        load_disks();
        load_storage_domain();
        load_vms();
        load_vm_nics();

        save_configuration() if $save_conf_flag;

        if ( Xorux_lib::write_json( $metadata_tmp_file, \%metadata ) ) {
          $metadata_loaded{$db_hostname} = 1;
        }
      };
      if ($@) {
        Xorux_lib::error( "Error while saving metadata from $file: $@ : " . __FILE__ . ":" . __LINE__ );
      }
    }
  }

  if ( keys %metadata_loaded ) {
    rename( $metadata_tmp_file, $metadata_file );
  }

  return 1;
}

sub load_datacenters {
  foreach my $uuid ( keys %{ $data->{datacenter} } ) {
    my $datacenter = $data->{datacenter}{$uuid};

    if ( $datacenter && ref($datacenter) eq 'HASH' && !exists $processed_on_host{$uuid} ) {

      # save HostCfg UUID
      my $hostcfg_uuid = $data->{hostcfg_uuid};
      $metadata{architecture}{hostcfg}{$hostcfg_uuid}{datacenter} = $uuid;

      $metadata{labels}{datacenter}{$uuid} = $datacenter->{datacenter_name};
      $processed_on_host{$uuid} = $db_hostname;
    }
  }
  return 1;
}

sub load_clusters {
  foreach my $uuid ( keys %{ $data->{cluster} } ) {
    my $cluster = $data->{cluster}{$uuid};

    if ( $cluster && ref($cluster) eq 'HASH' && !exists $processed_on_host{$uuid} ) {
      my $dc_uuid = $cluster->{datacenter_id};

      if ($dc_uuid) {
        push @{ $metadata{architecture}{datacenter}{$dc_uuid}{cluster} }, $uuid;
        $metadata{architecture}{cluster}{$uuid}{parent} = $dc_uuid;
        $metadata{labels}{cluster}{$uuid}               = $cluster->{cluster_name};
        $processed_on_host{$uuid}                       = $db_hostname;
      }
      else {
        print "ovirt-json2rrd.pl : skipping cluster configuration for $uuid, no parent datacenter\n";
      }
    }
  }
  return 1;
}

sub load_hosts {
  foreach my $uuid ( keys %{ $data->{host} } ) {
    my $host = $data->{host}{$uuid};
    if ( $host && ref($host) eq 'HASH' && !exists $processed_on_host{$uuid} ) {
      my $cl_uuid     = $host->{cluster_id};
      my $uniq_id     = defined $host->{host_unique_id} ? $host->{host_unique_id} : '';
      my $mapped_host = $linux_uuids->{ uc $uniq_id } if $mapping_code;
      if ($cl_uuid) {
        push @{ $metadata{architecture}{cluster}{$cl_uuid}{host} }, $uuid;
        $metadata{architecture}{host}{$uuid}{parent} = $cl_uuid;
        $metadata{mapping}{$uuid}                    = $mapped_host if $mapped_host;
        $metadata{mapping}{$uniq_id}                 = $mapped_host if $mapped_host;
        $metadata{labels}{host}{$uuid}               = $host->{host_name};
        $processed_on_host{$uuid}                    = $db_hostname;
        $conf_values{host}{$uuid}{memory_size_mb}    = $host->{memory_size_mb};
        $conf_values{host}{$uuid}{number_of_cores}   = $host->{number_of_cores};

        unless ( -d "$host_data_dir/$uuid" ) {
          mkdir("$host_data_dir/$uuid")
            || Xorux_lib::error( " Cannot mkdir $host_data_dir/$uuid: $!" . __FILE__ . ':' . __LINE__ );
        }
      }
      else {
        print "ovirt-json2rrd.pl : skipping host configuration for $uuid, no parent cluster\n";
      }
    }
  }
  return 1;
}

sub load_host_nics {
  foreach my $uuid ( keys %{ $data->{host_nic} } ) {
    my $nic = $data->{host_nic}{$uuid};

    if ( $nic && ref($nic) eq 'HASH' && !exists $processed_on_host{$uuid} ) {
      my $host_uuid = $nic->{host_id};

      if ($host_uuid) {
        push @{ $metadata{architecture}{host}{$host_uuid}{nic} }, $uuid if $host_uuid;
        $metadata{architecture}{host_nic}{$uuid}{parent} = $host_uuid if $host_uuid;
        $metadata{labels}{host_nic}{$uuid}               = $nic->{host_interface_name};
        $processed_on_host{$uuid}                        = $db_hostname;
        $nic_parent_map{host_nic}{$uuid}                 = $host_uuid;
      }
      else {
        print "ovirt-json2rrd.pl : skipping host interface configuration for $uuid, no parent host\n";
      }
    }
  }
  return 1;
}

sub load_storage_domain {
  foreach my $uuid ( keys %{ $data->{storage_domain} } ) {
    my $sd = $data->{storage_domain}{$uuid};

    if ( $sd && ref($sd) eq 'HASH' && !exists $processed_on_host{$uuid} ) {
      my $dc_uuid = $sd->{datacenter_id};

      if ($dc_uuid) {
        push @{ $metadata{architecture}{datacenter}{$dc_uuid}{storage_domain} }, $uuid;
        $metadata{architecture}{storage_domain}{$uuid}{parent} = $dc_uuid;
        $metadata{labels}{storage_domain}{$uuid}               = $sd->{storage_domain_name};
        $processed_on_host{$uuid}                              = $db_hostname;
      }
      else {
        print "ovirt-json2rrd.pl : skipping storage domain configuration for $uuid, no parent datacenter\n";
      }
    }
  }

  return 1;
}

sub load_vms {
  foreach my $uuid ( keys %{ $data->{vm} } ) {
    my $vm = $data->{vm}{$uuid};

    if ( $vm && ref($vm) eq 'HASH' && !exists $processed_on_host{$uuid} ) {
      my $cl_uuid       = $vm->{cluster_id};
      my $host_uuid     = $data->{vm_running_on_host}{$uuid}{currently_running_on_host};
      my $mapped_vm     = $linux_uuids->{ uc $uuid } if $mapping_code;
      my $win_mapped_vm = $win_uuids->{ uc $uuid }   if $win_mapping_code;

      if ($cl_uuid) {
        push @{ $metadata{architecture}{host}{$host_uuid}{vm} },  $uuid if $host_uuid;
        push @{ $metadata{architecture}{cluster}{$cl_uuid}{vm} }, $uuid;
        $metadata{architecture}{vm}{$uuid}{parent} = $cl_uuid;
        $metadata{mapping}{$uuid}                  = $mapped_vm     if $mapped_vm;
        $metadata{win_mapping}{$uuid}              = $win_mapped_vm if $win_mapped_vm;
        $metadata{labels}{vm}{$uuid}               = $vm->{vm_name};
        $processed_on_host{$uuid}                  = $db_hostname;
        $conf_values{vm}{$uuid}{memory_size_mb}    = $vm->{memory_size_mb};
        $conf_values{vm}{$uuid}{cpu_per_socket}    = $vm->{cpu_per_socket};
        $conf_values{vm}{$uuid}{number_of_sockets} = $vm->{number_of_sockets};

        unless ( -d "$vm_data_dir/$uuid" ) {
          mkdir("$vm_data_dir/$uuid")
            || Xorux_lib::error( " Cannot mkdir $vm_data_dir/$uuid: $!" . __FILE__ . ':' . __LINE__ );
        }
      }
      else {
        print "ovirt-json2rrd.pl : skipping VM configuration for $uuid, no parent cluster\n";
      }
    }
  }

  return 1;
}

sub load_vm_nics {
  foreach my $uuid ( keys %{ $data->{vm_nic} } ) {
    my $nic = $data->{vm_nic}{$uuid};

    if ( $nic && ref($nic) eq 'HASH' && !exists $processed_on_host{$uuid} ) {
      my $vm_uuid = $data->{vm_devices}{$uuid}{vm_id};

      if ($vm_uuid) {
        push @{ $metadata{architecture}{vm}{$vm_uuid}{nic} }, $uuid;
        $metadata{architecture}{vm_nic}{$uuid}{parent} = $vm_uuid;
        $metadata{labels}{vm_nic}{$uuid}               = $nic->{vm_interface_name};
        $processed_on_host{$uuid}                      = $db_hostname;
        $nic_parent_map{vm_nic}{$uuid}                 = $vm_uuid;
      }
      else {
        print "ovirt-json2rrd.pl : skipping VM interface configuration for $uuid, no parent VM\n";
      }
    }
  }

  return 1;
}

sub load_disks {
  foreach my $uuid ( keys %{ $data->{disk} } ) {
    my $disk = $data->{disk}{$uuid};

    if ( $disk && ref($disk) eq 'HASH' && !exists $processed_on_host{$uuid} ) {
      my $sd_uuid = $disk->{storage_domain_id};
      my $vm_uuid = $data->{vm_devices}{$uuid}{vm_id};

      if ( $vm_uuid && $sd_uuid ) {
        push @{ $metadata{architecture}{storage_domain}{$sd_uuid}{disk} }, $uuid;
        push @{ $metadata{architecture}{vm}{$vm_uuid}{disk} },             $uuid;
        $metadata{architecture}{disk}{$uuid}{parent} = $sd_uuid;
        $metadata{labels}{disk}{$uuid}               = $disk->{disk_name};
        $processed_on_host{$uuid}                    = $db_hostname;
        $conf_values{disk}{$uuid}{vm_status}         = $data->{vm_running_on_host}{$vm_uuid}{vm_status};
        $conf_values{disk}{$uuid}{vm_disk_size_mb}   = $disk->{vm_disk_size_mb};
      }
      else {
        print "ovirt-json2rrd.pl : skipping disk configuration for $uuid, no parent VM or domain\n";
      }
    }
  }

  return 1;
}

################################################################################

sub check_configuration_update {
  my $save_conf_flag = 0;

  if ( !-f $conf_touch_file ) {
    $save_conf_flag = 1;
  }
  else {
    my $run_time = ( stat($conf_touch_file) )[9];
    my ( undef, undef, undef, $actual_day )   = localtime( time() );
    my ( undef, undef, undef, $last_run_day ) = localtime($run_time);

    $save_conf_flag = !( $actual_day == $last_run_day && $upgrade == 0 );
  }

  if ($save_conf_flag) {
    my @old_files = <$conf_dir/*.json>;

    print 'ovirt-json2rrd.pl : save new configuration files, ' . localtime() . "\n";

    foreach my $file (@old_files) {
      unlink $file or Xorux_lib::error( "Cannot unlink $file: $! " . __FILE__ . ':' . __LINE__ );
    }
  }
  else {
    print 'ovirt-json2rrd.pl : do not save configuration files, ' . localtime() . "\n";
  }

  return $save_conf_flag;
}

sub save_configuration {
  foreach my $datacenter_uuid ( keys %{ $data->{datacenter} } ) {
    my $datacenter_name = $metadata{labels}{datacenter}{$datacenter_uuid};
    my $clusters        = $metadata{architecture}{datacenter}{$datacenter_uuid}{cluster};
    my %configuration;

    $configuration{timestamp}                   = $data->{timestamp};
    $configuration{datacenter}{datacenter_name} = $datacenter_name;
    $configuration{datacenter}{datacenter_uuid} = $datacenter_uuid;

    storage_domain_conf( \%configuration, $datacenter_uuid );
    disk_conf( \%configuration );

    foreach my $cluster_uuid ( @{$clusters} ) {
      vm_conf( \%configuration, $cluster_uuid );
      host_conf( \%configuration, $cluster_uuid );
    }

    my $datacenter_conf_file = "$conf_dir/$datacenter_uuid.json";
    Xorux_lib::write_json( $datacenter_conf_file, \%configuration );
  }

  return 1;
}

sub vm_conf {
  my $configuration = shift;
  my $cluster_uuid  = shift;
  my $cluster_name  = $metadata{labels}{cluster}{$cluster_uuid};
  my $vms           = $metadata{architecture}{cluster}{$cluster_uuid}{vm};

  foreach my $uuid ( @{$vms} ) {
    my $vm = $data->{vm}{$uuid};

    if ( $vm && ref($vm) eq 'HASH' ) {
      $configuration->{vm}{$uuid}{cluster_name}      = $cluster_name;
      $configuration->{vm}{$uuid}{vm_name}           = $vm->{vm_name};
      $configuration->{vm}{$uuid}{vm_type}           = $vm->{vm_type};
      $configuration->{vm}{$uuid}{cpu_per_socket}    = $vm->{cpu_per_socket};
      $configuration->{vm}{$uuid}{number_of_sockets} = $vm->{number_of_sockets};
      $configuration->{vm}{$uuid}{memory_size_mb}    = $vm->{memory_size_mb};
      $configuration->{vm}{$uuid}{operating_system}  = $vm->{operating_system};
    }
  }

  return 1;
}

sub host_conf {
  my $configuration = shift;
  my $cluster_uuid  = shift;
  my $cluster_name  = $metadata{labels}{cluster}{$cluster_uuid};
  my $hosts         = $metadata{architecture}{cluster}{$cluster_uuid}{host};

  foreach my $uuid ( @{$hosts} ) {
    my $host = $data->{host}{$uuid};

    if ( $host && ref($host) eq 'HASH' ) {
      $configuration->{host}{$uuid}{cluster_name}           = $cluster_name;
      $configuration->{host}{$uuid}{host_name}              = $host->{host_name};
      $configuration->{host}{$uuid}{host_type}              = $host->{host_type};
      $configuration->{host}{$uuid}{fqdn_or_ip}             = $host->{fqdn_or_ip};
      $configuration->{host}{$uuid}{memory_size_mb}         = $host->{memory_size_mb};
      $configuration->{host}{$uuid}{swap_size_mb}           = $host->{swap_size_mb};
      $configuration->{host}{$uuid}{cpu_model}              = $host->{cpu_model};
      $configuration->{host}{$uuid}{number_of_cores}        = $host->{number_of_cores};
      $configuration->{host}{$uuid}{number_of_sockets}      = $host->{number_of_sockets};
      $configuration->{host}{$uuid}{cpu_speed_mh}           = $host->{cpu_speed_mh};
      $configuration->{host}{$uuid}{host_os}                = $host->{host_os};
      $configuration->{host}{$uuid}{kernel_version}         = $host->{kernel_version};
      $configuration->{host}{$uuid}{kvm_version}            = $host->{kvm_version};
      $configuration->{host}{$uuid}{threads_per_core}       = $host->{threads_per_core};
      $configuration->{host}{$uuid}{hardware_product_name}  = $host->{hardware_product_name};
      $configuration->{host}{$uuid}{hardware_serial_number} = $host->{hardware_serial_number};
    }
  }

  return 1;
}

sub storage_domain_conf {
  my $configuration   = shift;
  my $datacenter_uuid = shift;
  my $storage_domains = $metadata{architecture}{datacenter}{$datacenter_uuid}{storage_domain};

  foreach my $uuid ( @{$storage_domains} ) {
    my $sd      = $data->{storage_domain}{$uuid};
    my $sd_perf = $sd->{perf};

    if ( $sd && ref($sd) eq 'HASH' ) {
      my $free = $data->{storage_domain_size}{$uuid}{available_disk_size_gb};
      my $used = $data->{storage_domain_size}{$uuid}{used_disk_size_gb};
      my $size = $free + $used if defined $free && defined $used;

      $configuration->{storage_domain}{$uuid}{storage_domain_name} = $sd->{storage_domain_name};
      $configuration->{storage_domain}{$uuid}{storage_domain_type} = $sd->{storage_domain_type};
      $configuration->{storage_domain}{$uuid}{storage_type}        = $sd->{storage_type};
      $configuration->{storage_domain}{$uuid}{total_disk_size_gb}  = $size;
      $configuration->{storage_domain}{$uuid}{used_disk_size_gb}   = $used;
      $configuration->{storage_domain}{$uuid}{free_disk_size_gb}   = $free;
    }
  }

  return 1;
}

sub disk_conf {
  my $configuration = shift;

  foreach my $uuid ( keys %{ $metadata{architecture}{disk} } ) {
    my $disk = $data->{disk}{$uuid};

    if ( $disk && ref($disk) eq 'HASH' ) {
      $configuration->{disk}{$uuid}{disk_name}       = $disk->{disk_name};
      $configuration->{disk}{$uuid}{vm_disk_size_mb} = $disk->{vm_disk_size_mb};
    }
  }

  return 1;
}

################################################################################

sub update_backup_files {
  my @old_files = <$tmpdir/oVirt_*_last2.txt>;
  my @new_files = <$tmpdir/oVirt_*_last1.txt>;

  foreach my $file (@old_files) {
    unlink $file or Xorux_lib::error( "Cannot unlink $file: $! " . __FILE__ . ":" . __LINE__ );
  }

  foreach my $file (@new_files) {
    my $target = $file;
    $target =~ s/_last1\.txt$/_last2.txt/;
    move( $file, $target ) or Xorux_lib::error( "Cannot unlink $file: $! " . __FILE__ . ':' . __LINE__ );
  }

  return 1;
}

sub backup_file {

  # expects file name for the file, that is supposed to be moved from iostats_dir,
  #   with file name "hostname_datetime.json" to tmpdir
  my $src_file = shift;
  my $source   = "$iostats_dir/${src_file}";
  $src_file =~ s/\.json//;
  my $target = "$tmpdir/oVirt_${src_file}\_last1.txt";

  move( $source, $target ) or Xorux_lib::error( "Cannot backup data $source: $!" . __FILE__ . ':' . __LINE__ );

  return 1;
}    ## sub backup_file
