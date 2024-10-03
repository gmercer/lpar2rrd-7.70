# OVirtLoadDataModule.pm
# create/update RRDs with oVirt

package OVirtLoadDataModule;

use strict;

use Date::Parse;
use RRDp;
use File::Copy;
use Xorux_lib;
use Math::BigInt;
use Data::Dumper;
use File::Copy qw(copy);

my $rrdtool = $ENV{RRDTOOL};

my $step            = 60;
my $no_time         = $step * 7;
my $no_time_storage = $step * 180;

my $one_minute_sample = 86400;
my $five_mins_sample  = 25920;
my $one_hour_sample   = 4320;
my $five_hours_sample = 1734;
my $one_day_sample    = 1080;

my %metrics = (
  host => [
    'cpu_usage_p', 'cpu_usage_c', 'user_cpu_usage_p', 'system_cpu_usage_p',
    'ksm_cpu_p',   'cpu_load',   'total_vms_vcpus', 'number_of_cores', 'memory_used',
    'memory_free', 'memory_ksm', 'swap_used',       'reserve1',        'reserve2'
  ],
  disk => [
    'data_current_write', 'data_current_read', 'disk_write_latency',
    'disk_read_latency',  'vm_disk_size_mb'
  ],
  disk2 => [ 'disk_write_iops', 'disk_read_iops' ],
  vm    => [
    'cpu_usage_p', 'cpu_usage_c', 'user_cpu_usage_p', 'system_cpu_usage_p',
    'number_of_cores', 'memory_used', 'memory_free', 'memory_buffered', 'memory_cached'
  ],
  vm_nic         => [ 'received_byte',      'transmitted_byte' ],
  host_nic       => [ 'received_byte',      'transmitted_byte' ],
  storage_domain => [ 'total_disk_size_gb', 'used_disk_size_gb' ]
);

################################################################################

sub touch {
  my $text       = shift;
  my $version    = "$ENV{version}";
  my $basedir    = $ENV{INPUTDIR};
  my $new_change = "$basedir/tmp/$version-ovirt";
  my $DEBUG      = $ENV{DEBUG};

  if ( !-f $new_change ) {
    `touch $new_change`;    # tell install_html.sh that there has been a change
    if ( $text eq '' ) {
      print "touch             : $new_change\n" if $DEBUG;
    }
    else {
      print "touch             : $new_change : $text\n" if $DEBUG;
    }
  }

  return 0;
}

sub isdigit {
  my $digit = shift;

  my $digit_work = $digit;
  $digit_work =~ s/[0-9]//g;
  $digit_work =~ s/\.//;

  if ( length($digit_work) == 0 ) {

    # is a number
    return 1;
  }

  return 0;
}

################################################################################

sub create_rrd {
  my $filepath = shift;
  my $time     = ( shift @_ ) - 3600;
  my $type     = shift;
  my $cmd      = qq(create "$filepath" --start "$time" --step "$step"\n);
  my $samples  = "$one_minute_sample, $five_mins_sample, $one_hour_sample, $five_hours_sample, $one_day_sample";

  touch("create_rrd $type $filepath");

  foreach my $metric ( @{ $metrics{$type} } ) {
    if ( $type eq 'storage_domain' ) {
      $cmd .= qq("DS:$metric:GAUGE:$no_time_storage:0:U"\n);
    }
    else {
      $cmd .= qq("DS:$metric:GAUGE:$no_time:0:U"\n);
    }
  }

  print "Creating RRD      : $filepath\n";

  if ( $type eq 'storage_domain' ) {

    # storage domains have only hourly data
    $samples = "$one_hour_sample, $five_hours_sample, $one_day_sample";
    $cmd .= qq(
               "RRA:AVERAGE:0.5:60:$one_hour_sample"
               "RRA:AVERAGE:0.5:300:$five_hours_sample"
               "RRA:AVERAGE:0.5:1440:$one_day_sample"
              );
  }
  else {
    $cmd .= qq(
               "RRA:AVERAGE:0.5:1:$one_minute_sample"
               "RRA:AVERAGE:0.5:5:$five_mins_sample"
               "RRA:AVERAGE:0.5:60:$one_hour_sample"
               "RRA:AVERAGE:0.5:300:$five_hours_sample"
               "RRA:AVERAGE:0.5:1440:$one_day_sample"
              );
  }

  if ( defined $cmd ) {
    RRDp::cmd $cmd;

    if ( !Xorux_lib::create_check("file: $filepath, $samples") ) {
      Xorux_lib::error( "Unable to create $filepath : at " . __FILE__ . ": line " . __LINE__ );
      RRDp::end;
      RRDp::start "$rrdtool";
      return 0;
    }
  }

  return 1;
}

sub update_rrd {
  my $rrd           = shift;
  my @values        = @_;
  my $act_time      = $values[0];
  my $update_string = '';
  my $last_rec      = '';

  foreach my $value (@values) {
    if ( !defined $value || !isdigit($value) || $value eq '' ) {
      $value = 'U';
    }
  }

  $update_string = join ':', @values;

  my $lastupdate = Xorux_lib::rrd_last_update($rrd);
  if ( $$lastupdate > $act_time ) {
    return 0;
  }

  RRDp::cmd qq(update "$rrd" $update_string);
  eval { my $answer = RRDp::read; };

  if ($@) {
    Xorux_lib::error( "Failed during read last time $rrd: $@ " . __FILE__ . ":" . __LINE__ );
    return 0;
  }
  return 1;

}    ## update_rrd

################################################################################

sub update_rrd_host {
  my $filepath = shift;
  my $data     = shift;
  my $conf     = shift;
  my $last_upd = 0;

  my $memory_size = $conf->{memory_size_mb};
  my $number_of_cores = $conf->{number_of_cores} if defined $conf->{number_of_cores};

  print "Updating RRD      : $filepath\n";

  foreach my $row_ref ( @{$data} ) {
    my @row         = @{$row_ref};
    my $timestamp   = $row[1];
    my $cpu_usage_p = $row[2];
    my $cpu_usage_c = $number_of_cores * ( $cpu_usage_p / 100 )
      if defined $number_of_cores && defined $cpu_usage_p;
    my $user_cpu_usage_p   = defined $row[3] && $row[3] < 0 ? 0 : $row[3];    # in db can be negative values
    my $system_cpu_usage_p = defined $row[4] && $row[4] < 0 ? 0 : $row[4];    # in db can be negative values
    my $ksm_cpu_p          = $row[5];
    my $cpu_load           = $row[6];
    my $total_vms_vcpus    = $row[7];
    my $memory_usage_p     = $row[8];
    my $memory_ksm         = $row[9];
    my $swap_used          = $row[10];
    my $memory_used;
    my $memory_free;
    my $reserve1;
    my $reserve2;

    if ( defined $memory_size && defined $memory_usage_p ) {
      $memory_used = ( $memory_size / 100 ) * $memory_usage_p;
      $memory_free = $memory_size - $memory_used;
    }

    if ( defined $timestamp && $last_upd < $timestamp ) {
      update_rrd(
        $filepath,   $timestamp, $cpu_usage_p,     $cpu_usage_c,     $user_cpu_usage_p, $system_cpu_usage_p,
        $ksm_cpu_p,  $cpu_load,  $total_vms_vcpus, $number_of_cores, $memory_used,      $memory_free,
        $memory_ksm, $swap_used, $reserve1,        $reserve2
      );
      $last_upd = $timestamp;
    }
  }

  return 1;
}    ## sub update_rrd_host

sub update_rrd_vm {
  my $filepath = shift;
  my $data     = shift;
  my $conf     = shift;
  my $last_upd = 0;

  my $number_of_cores;
  my $memory_size = $conf->{memory_size_mb};

  if ( defined $conf->{number_of_sockets} && defined $conf->{cpu_per_socket} ) {
    $number_of_cores = $conf->{number_of_sockets} * $conf->{cpu_per_socket};
  }

  print "Updating RRD      : $filepath\n";

  foreach my $row_ref ( @{$data} ) {
    my @row         = @{$row_ref};
    my $timestamp   = $row[1];
    my $cpu_usage_p = $row[2];
    my $cpu_usage_c = $number_of_cores * ( $cpu_usage_p / 100 )
      if defined $number_of_cores && defined $cpu_usage_p;
    my $user_cpu_usage_p   = defined $row[3] && $row[3] < 0 ? 0 : $row[3];    # in db can be negative values
    my $system_cpu_usage_p = defined $row[4] && $row[4] < 0 ? 0 : $row[4];    # in db can be negative values
    my $memory_usage_p     = $row[5];
    my $memory_used;
    my $memory_free;
    my $memory_buffered;
    my $memory_cached;

    if ( defined $memory_size && defined $memory_usage_p ) {
      $memory_buffered = defined $row[6] ? $row[6] / 1024 : 0;
      $memory_cached   = defined $row[7] ? $row[7] / 1024 : 0;
      $memory_used     = ( $memory_size / 100 ) * $memory_usage_p;
      $memory_free = $memory_size - ( $memory_used + $memory_buffered + $memory_cached );
    }

    if ( defined $timestamp && $last_upd < $timestamp ) {
      update_rrd(
        $filepath,        $timestamp,   $cpu_usage_p, $cpu_usage_c,     $user_cpu_usage_p, $system_cpu_usage_p,
        $number_of_cores, $memory_used, $memory_free, $memory_buffered, $memory_cached
      );
      $last_upd = $timestamp;
    }
  }

  return 1;
}    ## sub update_rrd_vm

sub update_rrd_disk {
  my $filepath   = shift;
  my $data       = shift;
  my $conf       = shift;
  my $last_upd   = 0;
  my $vm_running = defined $conf->{vm_status} && $conf->{vm_status} eq '1' ? 1 : 0;

  print "Updating RRD      : $filepath\n";

  foreach my $row_ref ( @{$data} ) {
    my @row = @{$row_ref};

    # if vm is shut down then db continues to store last values for its disks
    # so if vm is not running then disk perf data are not valid -> save only NaN
    my $timestamp          = $row[1];
    my $data_current_write = $vm_running ? $row[2] : 'U';
    my $data_current_read  = $vm_running ? $row[3] : 'U';
    my $disk_write_latency = $vm_running ? $row[4] : 'U';
    my $disk_read_latency  = $vm_running ? $row[5] : 'U';
    my $vm_disk_size_mb    = $vm_running ? $row[6] : 'U';

    if ( defined $timestamp && $last_upd < $timestamp ) {
      update_rrd(
        $filepath,           $timestamp,         $data_current_write, $data_current_read,
        $disk_write_latency, $disk_read_latency, $vm_disk_size_mb
      );
      $last_upd = $timestamp;
    }
  }

  return 1;
}    ## sub update_rrd_disk

sub update_rrd_disk_iops {
  my $filepath   = shift;
  my $data       = shift;
  my $conf       = shift;
  my $last_upd   = 0;
  my $vm_running = defined $conf->{vm_status} && $conf->{vm_status} eq '1' ? 1 : 0;

  my $disk_write_diff;
  my $disk_read_diff;

  print "Updating RRD      : $filepath\n";

  # calculate the delta between last and current values, as in update_rrd_nic
  foreach my $row_ref ( @{$data} ) {
    my @row = @{$row_ref};

    if ( defined $disk_write_diff && defined $disk_read_diff ) {

      # if vm is shut down then db continues to store last values for its disks
      # so if vm is not running then disk perf data are not valid -> save only NaN
      my $timestamp       = $row[1];
      my $disk_write_iops = ( $vm_running && defined $row[8] ) ? $row[8] - $disk_write_diff : 'U';
      my $disk_read_iops  = ( $vm_running && defined $row[9] ) ? $row[9] - $disk_read_diff : 'U';

      $disk_write_diff = $row[8];
      $disk_read_diff  = $row[9];

      if ( defined $timestamp && $last_upd < $timestamp ) {
        update_rrd( $filepath, $timestamp, $disk_write_iops, $disk_read_iops );
        $last_upd = $timestamp;
      }
    }
    else {
      $disk_write_diff = $row[8];
      $disk_read_diff  = $row[9];
    }
  }

  return 1;
}    ## sub update_rrd_disk_iops

sub update_rrd_storage_domain {
  my $filepath = shift;
  my $data     = shift;
  my $last_upd = 0;

  print "Updating RRD      : $filepath\n";

  foreach my $row_ref ( @{$data} ) {
    my @row               = @{$row_ref};
    my $timestamp         = $row[1];
    my $free_disk_size_gb = $row[2];
    my $used_disk_size_gb = $row[3];
    my $total_disk_size   = $row[2] + $row[3] if defined $free_disk_size_gb && defined $used_disk_size_gb;

    if ( defined $timestamp && $last_upd < $timestamp ) {
      update_rrd( $filepath, $timestamp, $total_disk_size, $used_disk_size_gb );
      $last_upd = $timestamp;
    }
  }

  return 1;
}

sub update_rrd_nic {
  my $filepath = shift;
  my $data     = shift;
  my $last_upd = 0;

  my $received_byte_diff;
  my $transmitted_byte_diff;

  print "Updating RRD      : $filepath\n";

  # In collected data should be last value from previous update which is used only as starting point for
  # differences for counter values. If this value is undefined for some reason, then first defined value
  # is used instead.
  foreach my $row_ref ( @{$data} ) {
    my @row = @{$row_ref};

    if ( defined $received_byte_diff && defined $transmitted_byte_diff ) {
      my $timestamp        = $row[1];
      my $received_byte    = $row[2] - $received_byte_diff if defined $row[2];
      my $transmitted_byte = $row[3] - $transmitted_byte_diff if defined $row[3];

      $received_byte_diff    = $row[2];
      $transmitted_byte_diff = $row[3];

      if ( defined $timestamp && $last_upd < $timestamp ) {
        update_rrd( $filepath, $timestamp, $received_byte, $transmitted_byte );
        $last_upd = $timestamp;
      }
    }
    else {
      $received_byte_diff    = $row[2];
      $transmitted_byte_diff = $row[3];
    }
  }

  return 1;
}    ## sub update_rrd_nic

################################################################################

1;
