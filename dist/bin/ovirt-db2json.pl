use 5.008_008;

use Data::Dumper;
use strict;
use warnings;
use Xorux_lib qw(error read_json write_json);
use HostCfg;

defined $ENV{INPUTDIR} || warn( ' INPUTDIR undefined, config etc/lpar2rrd.cfg probably has not been loaded ' . __FILE__ . ':' . __LINE__ ) && exit 1;

my $inputdir    = $ENV{INPUTDIR};
my $cfgfile     = "$inputdir/etc/web_config/ovirt.json";
my $ovirt_dir   = "$inputdir/data/oVirt";
my $iostats_dir = "$ovirt_dir/iostats";

# create directories in data/
unless ( -d $ovirt_dir ) {
  mkdir( $ovirt_dir, 0755 ) || Xorux_lib::error( "Cannot mkdir $ovirt_dir: $!" . __FILE__ . ':' . __LINE__ ) && exit 1;
}
unless ( -d $iostats_dir ) {
  mkdir( $iostats_dir, 0755 ) || Xorux_lib::error( "Cannot mkdir $iostats_dir: $!" . __FILE__ . ':' . __LINE__ ) && exit 1;
}
else {
  # clean old files
  my @old_files = <$iostats_dir/*.json>;

  foreach my $file (@old_files) {
    unlink $file || Xorux_lib::error( "Cannot unlink $file: $! " . __FILE__ . ':' . __LINE__ );
  }
}
################################################################################
# Conf queries
################################################################################

my $dc_current_stmt = <<END;
SELECT datacenter_configuration.datacenter_id as uuid,
  datacenter_configuration.datacenter_name
FROM datacenter_configuration
  WHERE ( datacenter_configuration.history_id
          IN ( SELECT max(a.history_id) AS max
               FROM datacenter_configuration a
               GROUP BY a.datacenter_id ))
  AND datacenter_configuration.delete_date IS NULL;
END

my $cl_current_stmt = <<END;
SELECT cluster_configuration.cluster_id as uuid,
  cluster_configuration.cluster_name,
  cluster_configuration.datacenter_id,
  cluster_configuration.compatibility_version
FROM cluster_configuration
  WHERE ( cluster_configuration.history_id
          IN ( SELECT max(a.history_id) AS max
               FROM cluster_configuration a
               GROUP BY a.cluster_id ))
  AND cluster_configuration.delete_date IS NULL;
END

my $host_current_stmt = <<END;
SELECT host_configuration.host_id as uuid,
  host_configuration.host_unique_id,
  host_configuration.host_name,
  host_configuration.cluster_id,
  host_configuration.fqdn_or_ip,
  host_configuration.memory_size_mb,
  host_configuration.swap_size_mb,
  host_configuration.cpu_model,
  host_configuration.cpu_speed_mh,
  host_configuration.number_of_cores,
  host_configuration.number_of_sockets,
  host_configuration.host_os,
  host_configuration.kernel_version,
  host_configuration.kvm_version,
  host_configuration.threads_per_core,
  host_configuration.hardware_product_name,
  host_configuration.hardware_serial_number
FROM host_configuration
  WHERE ( host_configuration.history_id
          IN ( SELECT max(a.history_id) AS max
               FROM host_configuration a
               GROUP BY a.host_id ))
  AND host_configuration.delete_date IS NULL;
END

my $host_nic_current_stmt = <<END;
SELECT host_interface_configuration.host_interface_id as uuid,
  host_interface_configuration.host_interface_name,
  host_interface_configuration.host_id
FROM host_interface_configuration
  WHERE ( host_interface_configuration.history_id
          IN ( SELECT max(a.history_id) AS max
               FROM host_interface_configuration a
               GROUP BY a.host_interface_id ))
  AND host_interface_configuration.delete_date IS NULL;
END

my $storage_domain_current_stmt = <<END;
SELECT sdc.storage_domain_id as uuid,
  sdc.storage_domain_name,
  sd_type.storage_domain_type,
  s_type.storage_type,
  sd_dc.datacenter_id
FROM ( SELECT storage_domain_id,
         datacenter_id
       FROM datacenter_storage_domain_map
       WHERE ( datacenter_storage_domain_map.history_id
               IN ( SELECT max(a.history_id) AS max
                    FROM datacenter_storage_domain_map a
                    GROUP BY a.storage_domain_id ))
         AND datacenter_storage_domain_map.detach_date IS NULL ) AS sd_dc
JOIN ( SELECT storage_domain_id,
         storage_domain_name,
         storage_domain_type,
         storage_type
       FROM storage_domain_configuration
       WHERE ( storage_domain_configuration.history_id
               IN ( SELECT max(a.history_id) AS max
                    FROM storage_domain_configuration a
                    GROUP BY a.storage_domain_id ))
         AND storage_domain_configuration.delete_date IS NULL ) as sdc
ON sdc.storage_domain_id = sd_dc.storage_domain_id
JOIN ( SELECT enum_key,
         value AS storage_domain_type
       FROM enum_translator
       WHERE enum_type = 'STORAGE_DOMAIN_TYPE'
         AND language_code = 'en_US' ) AS sd_type
ON sdc.storage_domain_type = sd_type.enum_key
JOIN ( SELECT enum_key, value AS storage_type
       FROM enum_translator
       WHERE enum_type = 'STORAGE_TYPE'
         AND language_code = 'en_US' ) AS s_type
ON sdc.storage_type = s_type.enum_key;
END

my $storage_domain_size_stmt = <<END;
SELECT storage_domain_id as uuid,
  available_disk_size_gb,
  used_disk_size_gb
FROM storage_domain_samples_history
  WHERE ( storage_domain_samples_history.history_id
          IN ( SELECT max(a.history_id) AS max
               FROM storage_domain_samples_history a
               GROUP BY a.storage_domain_id ));
END

my $vm_current_stmt = <<END;
SELECT vm_conf.*,
   os_type.operating_system,
   vm_type.vm_type
FROM
  ( SELECT vm_id AS uuid,
      vm_name,
      cluster_id,
      cpu_per_socket,
      number_of_sockets,
      memory_size_mb,
      operating_system,
      vm_type
    FROM vm_configuration
    WHERE (vm_configuration.history_id
           IN ( SELECT max(a.history_id) AS max
                FROM vm_configuration a
                GROUP BY a.vm_id ))
    AND vm_configuration.delete_date IS NULL ) AS vm_conf
  JOIN
  ( SELECT enum_key, value AS operating_system FROM enum_translator
    WHERE enum_type = 'OS_TYPE'
    AND language_code = 'en_US' ) AS os_type
  ON vm_conf.operating_system = os_type.enum_key
  JOIN
  ( SELECT enum_key, value AS vm_type FROM enum_translator
    WHERE enum_type = 'VM_TYPE'
    AND language_code = 'en_US' ) AS vm_type
  ON vm_conf.vm_type = vm_type.enum_key;
END

my $vm_running_on_host_stmt = <<END;
SELECT vm_id AS uuid,
  currently_running_on_host,
  vm_status
FROM vm_samples_history
  WHERE ( vm_samples_history.history_id
          IN ( SELECT max(a.history_id) AS max
               FROM vm_samples_history a
               GROUP BY a.vm_id ));
END

my $vm_devices_current_stmt = <<END;
SELECT vm_device_history.vm_id,
  vm_device_history.device_id as uuid,
  vm_device_history.type
FROM vm_device_history
  WHERE ( vm_device_history.history_id
          IN ( SELECT max(a.history_id) AS max
               FROM vm_device_history a
               GROUP BY a.vm_id, a.device_id ))
  AND vm_device_history.delete_date IS NULL;
END

my $vm_disk_current_stmt = <<END;
SELECT vm_disk_configuration.vm_disk_id as uuid,
  CASE
    WHEN vm_disk_configuration.vm_disk_name IS NOT NULL
      THEN vm_disk_configuration.vm_disk_name::text
    ELSE 'disk '::text || vm_disk_configuration.vm_internal_drive_mapping::character varying::text
  END AS disk_name,
  vm_disk_configuration.storage_domain_id,
  vm_disk_size_mb
  FROM vm_disk_configuration
  WHERE ( vm_disk_configuration.history_id
          IN ( SELECT max(a.history_id) AS max
               FROM vm_disk_configuration a
               GROUP BY a.vm_disk_id ))
  AND vm_disk_configuration.delete_date IS NULL;
END

my $vm_nic_current_stmt = <<END;
SELECT vm_interface_configuration.vm_interface_id as uuid,
  vm_interface_configuration.vm_interface_name
FROM vm_interface_configuration
  WHERE ( vm_interface_configuration.history_id
          IN ( SELECT max(a.history_id) AS max
               FROM vm_interface_configuration a
               GROUP BY a.vm_interface_id ))
  AND vm_interface_configuration.delete_date IS NULL;
END

################################################################################
# Perf queries
################################################################################

sub get_host_perf_stmt {
  my $last_update = shift;
  my $act_db_time = shift;

  my $host_samples_stmt = <<END;
SELECT perf.host_id,
  CAST(EXTRACT(EPOCH FROM perf.history_datetime) AS BIGINT) AS timestamp,
  perf.cpu_usage_percent,
  perf.user_cpu_usage_percent,
  perf.system_cpu_usage_percent,
  perf.ksm_cpu_percent,
  perf.cpu_load,
  perf.total_vms_vcpus,
  perf.memory_usage_percent,
  perf.ksm_shared_memory_mb,
  perf.swap_used_mb,
  perf.host_status
FROM host_samples_history AS perf
WHERE history_datetime > to_timestamp($last_update)
  AND to_timestamp($act_db_time) > history_datetime
ORDER BY host_id, timestamp;
END

  return \$host_samples_stmt;
}

sub get_storage_domain_perf_stmt {
  my $last_update = shift;
  my $act_db_time = shift;

  my $storage_domain_samples_stmt = <<END;
SELECT perf.storage_domain_id,
  CAST(EXTRACT(EPOCH FROM perf.history_datetime) AS BIGINT) AS timestamp,
  perf.available_disk_size_gb,
  perf.used_disk_size_gb
FROM storage_domain_samples_history AS perf
WHERE history_datetime > to_timestamp($last_update)
  AND to_timestamp($act_db_time) > history_datetime
ORDER BY storage_domain_id, timestamp;
END

  return \$storage_domain_samples_stmt;
}

sub get_vm_perf_stmt {
  my $last_update = shift;
  my $act_db_time = shift;

  my $vm_samples_stmt = <<END;
SELECT perf.vm_id,
  CAST(EXTRACT(EPOCH FROM perf.history_datetime) AS BIGINT) AS timestamp,
  perf.cpu_usage_percent,
  perf.user_cpu_usage_percent,
  perf.system_cpu_usage_percent,
  perf.memory_usage_percent,
  perf.memory_buffered_kb,
  perf.memory_cached_kb,
  perf.vm_status
FROM vm_samples_history AS perf
WHERE perf.history_datetime > to_timestamp($last_update)
  AND to_timestamp($act_db_time) > perf.history_datetime
ORDER BY vm_id, timestamp;
END

  return \$vm_samples_stmt;
}

sub get_vm_disk_perf_stmt {
  my $last_update    = shift;
  my $act_db_time    = shift;
  my $schema_version = shift || 0;

  my $vm_disk_samples_stmt = <<END;
SELECT disk.vm_disk_id,
  CAST(EXTRACT(EPOCH FROM disk.history_datetime) AS BIGINT) AS timestamp,
  disk.write_rate_bytes_per_second,
  disk.read_rate_bytes_per_second,
  disk.write_latency_seconds,
  disk.read_latency_seconds,
  disk.vm_disk_actual_size_mb,
  disk.vm_disk_status
FROM vm_disk_samples_history AS disk
WHERE disk.history_datetime > to_timestamp($last_update)
  AND to_timestamp($act_db_time) > disk.history_datetime
ORDER BY disk.vm_disk_id, timestamp;
END

  if ( $schema_version eq '404' ) {
    $vm_disk_samples_stmt = <<END;
SELECT disk.vm_disk_id,
  CAST(EXTRACT(EPOCH FROM disk.history_datetime) AS BIGINT) AS timestamp,
  disk.write_rate_bytes_per_second,
  disk.read_rate_bytes_per_second,
  disk.write_latency_seconds,
  disk.read_latency_seconds,
  disk.vm_disk_actual_size_mb,
  disk.vm_disk_status,
  disk.write_ops_per_second,
  disk.read_ops_per_second
FROM vm_disk_samples_history AS disk
WHERE disk.history_datetime > to_timestamp($last_update)
  AND to_timestamp($act_db_time) > disk.history_datetime
ORDER BY disk.vm_disk_id, timestamp;
END

  }
  elsif ( $schema_version eq '405' ) {
    $vm_disk_samples_stmt = <<END;
SELECT disk.vm_disk_id,
  CAST(EXTRACT(EPOCH FROM disk.history_datetime) AS BIGINT) AS timestamp,
  disk.write_rate_bytes_per_second,
  disk.read_rate_bytes_per_second,
  disk.write_latency_seconds,
  disk.read_latency_seconds,
  disk.vm_disk_actual_size_mb,
  disk.vm_disk_status,
  disk.write_ops_total_count,
  disk.read_ops_total_count
FROM vm_disk_samples_history AS disk
WHERE disk.history_datetime > to_timestamp($last_update)
  AND to_timestamp($act_db_time) > disk.history_datetime
ORDER BY disk.vm_disk_id, timestamp;
END
  }

  return \$vm_disk_samples_stmt;
}

sub get_vm_nic_perf_stmt {
  my $last_update = shift;
  my $act_db_time = shift;

  my $vm_nic_samples_stmt = <<END;
SELECT nic.vm_interface_id,
  CAST(EXTRACT(EPOCH FROM nic.history_datetime) AS BIGINT) AS timestamp,
  nic.received_total_byte,
  nic.transmitted_total_byte
FROM vm_interface_samples_history AS nic
WHERE history_datetime > to_timestamp($last_update) - INTERVAL '1 MINUTES'
  AND to_timestamp($act_db_time) > history_datetime
ORDER BY vm_interface_id, timestamp;
END

  return \$vm_nic_samples_stmt;
}

sub get_host_nic_perf_stmt {
  my $last_update = shift;
  my $act_db_time = shift;

  my $host_nic_samples_stmt = <<END;
SELECT host_interface_id,
  CAST(EXTRACT(EPOCH FROM history_datetime) AS BIGINT) AS timestamp,
  received_total_byte,
  transmitted_total_byte
FROM host_interface_samples_history
WHERE history_datetime > to_timestamp($last_update) - INTERVAL '1 MINUTES'
  AND to_timestamp($act_db_time) > history_datetime
ORDER BY host_interface_id, timestamp;
END

  return \$host_nic_samples_stmt;
}

################################################################################

#check if modules DBI and DBD::Pg exists
eval {
  require 'DBI.pm';
  require 'DBD/Pg.pm';
  'DBI'->import();
  'DBD::Pg'->import();
  1;
} or do {
  print "ovirt-db2json.pl  : DBI or DBD\::Pg module is missing, skip\n $@\n";
  exit 1;
};

require DBI;

################################################################################

my ( $sec, $min, $hour, $day, $month, $year, $wday, $yday, $isdst ) = localtime();
my $datetime      = sprintf( "%4d_%02d%02d_%02d%02d", $year + 1900, $month + 1, $day, $hour, $min );
my $act_timestamp = time;
my $database      = "ovirt_engine_history";
my %conf          = ( timestamp => $act_timestamp );
my %data;

my $port;
my $host_ip;
my $password;
my $userid;
my $dbh;
my $dsn;

my $perf_file_index = 0;
my $perf_file_limit = 2000;
my $perf_index      = 0;

my $ovirt_data_collection_timeout = 1200;
if ( defined $ENV{OVIRT_DATA_COLLECTION_TIMEOUT} && Xorux_lib::isdigit( $ENV{OVIRT_DATA_COLLECTION_TIMEOUT} ) ) {
  $ovirt_data_collection_timeout = $ENV{OVIRT_DATA_COLLECTION_TIMEOUT};
}

my %hosts = %{ HostCfg::getHostConnections('RHV (oVirt)') };
my @pids;
my $pid;

foreach my $host ( keys %hosts ) {

  # fork for each host
  unless ( defined( $pid = fork() ) ) {
    Xorux_lib::error( "Error: failed to fork for $host:" . __FILE__ . ":" . __LINE__ );
    next;
  }
  else {
    if ($pid) {
      push @pids, $pid;
    }
    else {
      eval {
        # Set alarm
        my $act_time = localtime();
        local $SIG{ALRM} = sub { die "$act_time: died in SIG ALRM"; };
        alarm($ovirt_data_collection_timeout);
        collect_data_from_host($host);

        #  end of alarm
        alarm(0);
      };
      if ($@) {
        if ( $@ =~ /died in SIG ALRM/ ) {
          Xorux_lib::error( "oVirt data collection timed out on $hosts{ $host }{host} after $ovirt_data_collection_timeout seconds : " . __FILE__ . ":" . __LINE__ );
        }
        else {
          Xorux_lib::error( "While connecting to $hosts{ $host }{host} occured error $@ : " . __FILE__ . ":" . __LINE__ );
        }
        exit(0);
      }

      exit;
    }
  }
}

# wait for forked data retrieval
for $pid (@pids) {
  waitpid( $pid, 0 );
}

print "data collection   : done successfully, " . localtime() . "\n";
exit 0;

################################################################################

sub collect_data_from_host {
  my $host = shift;

  $port     = $hosts{$host}{api_port};
  $host_ip  = $hosts{$host}{host};
  $password = $hosts{$host}{password};
  $userid   = $hosts{$host}{username};

  $dsn = "DBI:Pg:dbname = $database; host = $host_ip; port = $port";
  $dbh = DBI->connect( $dsn, $userid, $password, { RaiseError => 1 } ) or die "DBI: " . $DBI::errstr;
  print "database          : connected to $host_ip successfully\n";

  my $db_time = get_db_time();
  my $last_update = get_last_update_time( $host_ip, $db_time );

  $conf{db_hostname} = $host_ip;
  $conf{db_time}     = $db_time;
  $conf{last_update} = $last_update;

  # save HostCfg UUID, to be mapped to respective items (datacenter)
  my $hostcfg_uuid = $hosts{$host}{uuid};
  $conf{hostcfg_uuid} = $hostcfg_uuid;

  unless ($db_time) {
    die "cannot read DB time";
  }

  my $schema_version = get_schema_version();

  get_conf( 'datacenter',          $dc_current_stmt );
  get_conf( 'cluster',             $cl_current_stmt );
  get_conf( 'host',                $host_current_stmt );
  get_conf( 'host_nic',            $host_nic_current_stmt );
  get_conf( 'vm',                  $vm_current_stmt );
  get_conf( 'vm_running_on_host',  $vm_running_on_host_stmt );
  get_conf( 'vm_nic',              $vm_nic_current_stmt );
  get_conf( 'vm_devices',          $vm_devices_current_stmt );
  get_conf( 'storage_domain',      $storage_domain_current_stmt );
  get_conf( 'storage_domain_size', $storage_domain_size_stmt );
  get_conf( 'disk',                $vm_disk_current_stmt, );

  save_data('conf');

  get_perf( 'host', get_host_perf_stmt( $last_update, $db_time ) );
  get_perf( 'host_nic', get_host_nic_perf_stmt( $last_update, $db_time ) );
  get_perf( 'storage_domain', get_storage_domain_perf_stmt( $last_update, $db_time ) );
  get_perf( 'disk', get_vm_disk_perf_stmt( $last_update, $db_time, $schema_version ) );
  get_perf( 'vm', get_vm_perf_stmt( $last_update, $db_time ) );
  get_perf( 'vm_nic', get_vm_nic_perf_stmt( $last_update, $db_time ) );

  save_data('perf');

  $dbh->disconnect();

  return 1;
}

sub get_conf {
  my $type = shift;
  my $stmt = shift;
  my $sth  = $dbh->prepare($stmt);
  my $rv   = $sth->execute() or die $DBI::errstr;

  if ( $rv < 0 ) {
    print $DBI::errstr;
  }

  while ( my $ref = $sth->fetchrow_hashref() ) {
    if ( $ref->{uuid} ) {
      $conf{$type}{ $ref->{uuid} } = $ref;
    }
  }

  return 1;
}

sub get_perf {
  my $type = shift;
  my $stmt = ${ shift @_ };
  my $sth  = $dbh->prepare($stmt);
  my $rv   = $sth->execute() or die $DBI::errstr;

  if ( $rv < 0 ) {
    print $DBI::errstr;
  }

  my $last_uuid;
  my $save_flag = 0;

  while ( my @row = $sth->fetchrow_array() ) {
    my $uuid      = $row[0];
    my $timestamp = $row[1];

    if ( $save_flag && $uuid ne $last_uuid ) {
      save_data('perf');
      $save_flag = 0;
    }

    push @{ $data{$type}{$uuid} }, \@row;
    $perf_index++;

    if ( $perf_index > $perf_file_limit ) {
      $save_flag = 1;
    }

    $last_uuid = $uuid;
  }

  return 1;
}

# check oVirt schema version
sub get_schema_version {
  my $sth = $dbh->prepare("SELECT version FROM schema_version WHERE current = TRUE;");
  my $rv = $sth->execute() or die $DBI::errstr;

  if ( $rv < 0 ) {
    print $DBI::errstr;
  }

  my @row = $sth->fetchrow_array();

  if ( scalar @row > 0 ) {
    my $current = substr( $row[0], 1, 3 );
    print "ovirt-db2json.pl  : current oVirt schema $row[0] ($current)\n";
    return $current;
  }

  return 0;
}

sub get_db_time {
  my $sth = $dbh->prepare("SELECT CAST(EXTRACT(EPOCH FROM NOW()) AS BIGINT) AS timestamp;");
  my $rv = $sth->execute() or die $DBI::errstr;

  if ( $rv < 0 ) {
    print $DBI::errstr;
  }

  my @row = $sth->fetchrow_array();

  if ( scalar @row > 0 && $row[0] =~ /^\d+$/ ) {
    return $row[0];
  }

  return 0;
}

sub get_last_update_time {
  my $hostname      = shift;
  my $db_time       = shift;
  my $last_update   = $db_time - 1800;
  my $last_upd_file = "$inputdir/tmp/oVirt_$hostname\_last_upd";

  if ( -f $last_upd_file ) {
    my ( $code, $ref ) = Xorux_lib::read_json($last_upd_file);

    if ( $code && ref $ref eq 'ARRAY' ) {

      # plus 1 because of coercion to BIG INT where milliseconds can be rounded down
      my $last_upd_value = $ref->[0] + 1;
      $last_update = $last_upd_value > $last_update ? $last_upd_value : $last_update;
    }
  }

  Xorux_lib::write_json( $last_upd_file, [$db_time] );

  return $last_update;
}    ## sub get_last_update_time

sub save_data {
  my $suffix = shift;
  my $output_file_path;
  my $code;

  if ( $suffix eq 'conf' ) {
    $output_file_path = "$iostats_dir/$host_ip\_$datetime\_conf.json";
    $code = Xorux_lib::write_json( $output_file_path, \%conf );
  }
  elsif ( $suffix eq 'perf' ) {
    my $index = sprintf( "%03d", $perf_file_index );
    $output_file_path = "$iostats_dir/$host_ip\_$datetime\_perf$index.json";
    $code             = Xorux_lib::write_json( $output_file_path, \%data );
    %data             = ();
    $perf_index       = 0;
    $perf_file_index++;
  }

  return $code;
}
