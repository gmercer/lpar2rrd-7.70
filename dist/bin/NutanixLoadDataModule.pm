# LoadDataModuleNutanix.pm
# create/update RRDs with Nutanix metrics

package NutanixLoadDataModule;

use strict;
use warnings;

use Data::Dumper;
use Date::Parse;
use RRDp;
use File::Copy qw(copy);
use Xorux_lib;
use Math::BigInt;
use POSIX;

use NutanixDataWrapper;

my $rrdtool = $ENV{RRDTOOL};

my $step    = 60;
my $no_time = $step * 7;

my $one_minute_sample = 86400;
my $five_mins_sample  = 25920;
my $one_hour_sample   = 4320;
my $five_hours_sample = 1734;
my $one_day_sample    = 1080;

################################################################################

sub rrd_last_update {
  my $filepath    = shift;
  my $last_update = -1;

  RRDp::cmd qq(last "$filepath");
  eval { $last_update = RRDp::read; };

  if ($@) {
    warn( localtime() . ": Failed during read last time $filepath: $@ " . __FILE__ . ":" . __LINE__ );
    return 1;
  }

  return $last_update;
}

sub update_rrd_host {
  my $filepath  = shift;
  my $timestamp = shift;
  my %args      = %{ shift() };

  # check if the data is new enough
  my $last_update = rrd_last_update($filepath);
  unless ( $timestamp > $$last_update ) {
    return 0;
  }

  my $cpu_percent     = exists_and_defined( $args{cpu_usage_percent} ) == 1                            ? $args{cpu_usage_percent} / 1000000                                : "U";
  my $cpu_cores       = exists_and_defined( $args{cpu_cores} ) == 1 && $cpu_percent ne "U"             ? $args{cpu_cores} * $cpu_percent                                   : "U";
  my $cpu_cores_count = exists_and_defined( $args{cpu_cores} ) == 1                                    ? $args{cpu_cores}                                                  : "U";
  my $memory_total    = exists_and_defined( $args{memory} ) == 1                                       ? $args{memory} * 1024                                              : "U";
  my $memory_free     = exists_and_defined( $args{memory_usage_percent} ) == 1 && $memory_total ne "U" ? $memory_total * ( 1 - ( $args{memory_usage_percent} / 1000000 ) ) : "U";

  my $values = join ":", ( $cpu_percent, $cpu_cores, $cpu_cores_count, $memory_total, $memory_free );

  RRDp::cmd qq(update "$filepath" $timestamp:$values);
  eval { my $answer = RRDp::read; };

  if ($@) {
    warn( localtime() . ": Failed during read last time $filepath: $@ " . __FILE__ . ":" . __LINE__ );
    return 1;
  }

  return 0;
}

sub update_rrd_host_disk {
  my $filepath  = shift;
  my $timestamp = shift;
  my %args      = %{ shift() };

  # check if the data is new enough
  my $last_update = rrd_last_update($filepath);
  unless ( $timestamp > $$last_update ) {
    return 0;
  }

  my (
    $iowait,       $iops_total,    $iops_read, $iops_write,
    $io_tp_total,  $io_tp_read,    $io_tp_write,
    $read_latency, $write_latency, $total_latency, $read, $write
  ) = ("U") x 12;

  for my $metric ( keys %args ) {

    # quick fix if data are incomplete
    if ( !exists( $args{$metric} ) || !defined($args{$metric}) || $args{$metric} eq '') { next; }

    my $id = ( split( "_", $metric ) )[-1];
    if ( $metric =~ m/^iowait$/ ) {
      $iowait = $args{$metric};
    }
    elsif ( $metric =~ m/^iops_total$/ ) {
      $iops_total = $args{$metric};
    }
    elsif ( $metric =~ m/^iops_read$/ ) {
      $iops_read = $args{$metric};
    }
    elsif ( $metric =~ m/^iops_write$/ ) {
      $iops_write = $args{$metric};
    }
    elsif ( $metric =~ m/^io_throughput_total$/ ) {
      $io_tp_total = $args{$metric};
    }
    elsif ( $metric =~ m/^io_throughput_read$/ ) {
      $io_tp_read = $args{$metric};
    }
    elsif ( $metric =~ m/^io_throughput_write$/ ) {
      $io_tp_write = $args{$metric};
    }
    elsif ( $metric =~ m/^read_latency$/ ) {
      $read_latency = $args{$metric};
    }
    elsif ( $metric =~ m/^write_latency$/ ) {
      $write_latency = $args{$metric};
    }
    elsif ( $metric =~ m/^total_latency$/ ) {
      $total_latency = $args{$metric};
    }
    elsif ( $metric =~ m/^read$/ ) {
      $read = $args{$metric} * 1000;
    }
    elsif ( $metric =~ m/^write$/ ) {
      $write = $args{$metric} * 1000;
    }
  }

  my $values = join ":", (
    $iowait,       $iops_total,    $iops_read, $iops_write,
    $io_tp_total,  $io_tp_read,    $io_tp_write,
    $read_latency, $write_latency, $total_latency, $read, $write
  );

  RRDp::cmd qq(update "$filepath" $timestamp:$values);
  eval { my $answer = RRDp::read; };

  if ($@) {
    warn( localtime() . ": Failed during read last time $filepath: $@ " . __FILE__ . ":" . __LINE__ );
    return 1;
  }

  return 0;
}

sub update_rrd_storage_container {
  my $filepath  = shift;
  my $timestamp = shift;
  my %args      = %{ shift() };

  # check if the data is new enough
  my $last_update = rrd_last_update($filepath);
  unless ( $timestamp > $$last_update ) {
    return 0;
  }

  my (
    $iowait,       $iops_total,    $iops_read, $iops_write,
    $io_tp_total,  $io_tp_read,    $io_tp_write,
    $read_latency, $write_latency, $total_latency, $read, $write
  ) = ("U") x 12;

  for my $metric ( keys %args ) {

    # quick fix if data are incomplete
    if ( !exists( $args{$metric} ) ) { next; }

    my $id = ( split( "_", $metric ) )[-1];
    if ( $metric =~ m/^iowait$/ ) {
      $iowait = $args{$metric};
    }
    elsif ( $metric =~ m/^iops_total$/ ) {
      $iops_total = $args{$metric};
    }
    elsif ( $metric =~ m/^iops_read$/ ) {
      $iops_read = $args{$metric};
    }
    elsif ( $metric =~ m/^iops_write$/ ) {
      $iops_write = $args{$metric};
    }
    elsif ( $metric =~ m/^io_throughput_total$/ ) {
      $io_tp_total = $args{$metric};
    }
    elsif ( $metric =~ m/^io_throughput_read$/ ) {
      $io_tp_read = $args{$metric};
    }
    elsif ( $metric =~ m/^io_throughput_write$/ ) {
      $io_tp_write = $args{$metric};
    }
    elsif ( $metric =~ m/^read_latency$/ ) {
      $read_latency = $args{$metric};
    }
    elsif ( $metric =~ m/^write_latency$/ ) {
      $write_latency = $args{$metric};
    }
    elsif ( $metric =~ m/^total_latency$/ ) {
      $total_latency = $args{$metric};
    }
    elsif ( $metric =~ m/^read$/ ) {
      $read = $args{$metric} * 1024;
    }
    elsif ( $metric =~ m/^write$/ ) {
      $write = $args{$metric} * 1024;
    }
  }

  my $values = join ":", (
    $iowait,       $iops_total,    $iops_read, $iops_write,
    $io_tp_total,  $io_tp_read,    $io_tp_write,
    $read_latency, $write_latency, $total_latency, $read, $write
  );

  RRDp::cmd qq(update "$filepath" $timestamp:$values);
  eval { my $answer = RRDp::read; };

  if ($@) {
    warn( localtime() . ": Failed during read last time $filepath: $@ " . __FILE__ . ":" . __LINE__ );
    return 1;
  }

  return 0;
}

sub update_rrd_virtual_disk {
  my $filepath  = shift;
  my $timestamp = shift;
  my %args      = %{ shift() };

  # check if the data is new enough
  my $last_update = rrd_last_update($filepath);
  unless ( $timestamp > $$last_update ) {
    return 0;
  }

  my (
    $iowait,       $iops_total,    $iops_read, $iops_write,
    $io_tp_total,  $io_tp_read,    $io_tp_write,
    $read_latency, $write_latency, $total_latency, $read, $write
  ) = ("U") x 12;

  for my $metric ( keys %args ) {

    # quick fix if data are incomplete
    if ( !exists( $args{$metric} ) )  { next; }
    if ( !defined( $args{$metric} ) ) { next; }

    my $id = ( split( "_", $metric ) )[-1];
    if ( $metric =~ m/^iowait$/ ) {
      $iowait = $args{$metric};
    }
    elsif ( $metric =~ m/^iops_total$/ ) {
      $iops_total = $args{$metric};
    }
    elsif ( $metric =~ m/^iops_read$/ ) {
      $iops_read = $args{$metric};
    }
    elsif ( $metric =~ m/^iops_write$/ ) {
      $iops_write = $args{$metric};
    }
    elsif ( $metric =~ m/^io_throughput_total$/ ) {
      $io_tp_total = $args{$metric};
    }
    elsif ( $metric =~ m/^io_throughput_read$/ ) {
      $io_tp_read = $args{$metric};
    }
    elsif ( $metric =~ m/^io_throughput_write$/ ) {
      $io_tp_write = $args{$metric};
    }
    elsif ( $metric =~ m/^read_latency$/ ) {
      $read_latency = $args{$metric};
    }
    elsif ( $metric =~ m/^write_latency$/ ) {
      $write_latency = $args{$metric};
    }
    elsif ( $metric =~ m/^total_latency$/ ) {
      $total_latency = $args{$metric};
    }
    elsif ( $metric =~ m/^read$/ ) {
      if ( defined $args{$metric} ) {
        $read = $args{$metric} * 1024;
      }
    }
    elsif ( $metric =~ m/^write$/ ) {
      if ( defined $args{$metric} ) {
        $write = $args{$metric} * 1024;
      }
    }
  }

  my $values = join ":", (
    $iowait,       $iops_total,    $iops_read, $iops_write,
    $io_tp_total,  $io_tp_read,    $io_tp_write,
    $read_latency, $write_latency, $total_latency, $read, $write
  );

  RRDp::cmd qq(update "$filepath" $timestamp:$values);
  eval { my $answer = RRDp::read; };

  if ($@) {
    warn( localtime() . ": Failed during read last time $filepath: $@ " . __FILE__ . ":" . __LINE__ );
    return 1;
  }

  return 0;
}

sub update_rrd_storage_pool {
  my $filepath  = shift;
  my $timestamp = shift;
  my %args      = %{ shift() };

  # check if the data is new enough
  my $last_update = rrd_last_update($filepath);
  unless ( $timestamp > $$last_update ) {
    return 0;
  }

  my (
    $iowait,       $iops_total,    $iops_read, $iops_write,
    $io_tp_total,  $io_tp_read,    $io_tp_write,
    $read_latency, $write_latency, $total_latency, $read, $write
  ) = ("U") x 12;

  for my $metric ( keys %args ) {

    # quick fix if data are incomplete
    if ( !exists( $args{$metric} ) ) { next; }

    my $id = ( split( "_", $metric ) )[-1];
    if ( $metric =~ m/^iowait$/ ) {
      $iowait = $args{$metric};
    }
    elsif ( $metric =~ m/^iops_total$/ ) {
      $iops_total = $args{$metric};
    }
    elsif ( $metric =~ m/^iops_read$/ ) {
      $iops_read = $args{$metric};
    }
    elsif ( $metric =~ m/^iops_write$/ ) {
      $iops_write = $args{$metric};
    }
    elsif ( $metric =~ m/^io_throughput_total$/ ) {
      $io_tp_total = $args{$metric};
    }
    elsif ( $metric =~ m/^io_throughput_read$/ ) {
      $io_tp_read = $args{$metric};
    }
    elsif ( $metric =~ m/^io_throughput_write$/ ) {
      $io_tp_write = $args{$metric};
    }
    elsif ( $metric =~ m/^read_latency$/ ) {
      $read_latency = $args{$metric};
    }
    elsif ( $metric =~ m/^write_latency$/ ) {
      $write_latency = $args{$metric};
    }
    elsif ( $metric =~ m/^total_latency$/ ) {
      $total_latency = $args{$metric};
    }
    elsif ( $metric =~ m/^read$/ ) {
      $read = $args{$metric} * 1000;
    }
    elsif ( $metric =~ m/^write$/ ) {
      $write = $args{$metric} * 1000;
    }
  }

  my $values = join ":", (
    $iowait,       $iops_total,    $iops_read, $iops_write,
    $io_tp_total,  $io_tp_read,    $io_tp_write,
    $read_latency, $write_latency, $total_latency, $read, $write
  );

  RRDp::cmd qq(update "$filepath" $timestamp:$values);
  eval { my $answer = RRDp::read; };

  if ($@) {
    warn( localtime() . ": Failed during read last time $filepath: $@ " . __FILE__ . ":" . __LINE__ );
    return 1;
  }

  return 0;
}

sub update_rrd_volume_group {
  my $filepath  = shift;
  my $timestamp = shift;
  my %args      = %{ shift() };

  # check if the data is new enough
  my $last_update = rrd_last_update($filepath);
  unless ( $timestamp > $$last_update ) {
    return 0;
  }

  my (
    $iowait,       $iops_total,    $iops_read, $iops_write,
    $io_tp_total,  $io_tp_read,    $io_tp_write,
    $read_latency, $write_latency, $total_latency, $read, $write
  ) = ("U") x 12;

  for my $metric ( keys %args ) {

    # quick fix if data are incomplete
    if ( !exists( $args{$metric} ) ) { next; }

    my $id = ( split( "_", $metric ) )[-1];
    if ( $metric =~ m/^iowait$/ ) {
      $iowait = $args{$metric};
    }
    elsif ( $metric =~ m/^iops_total$/ ) {
      $iops_total = $args{$metric};
    }
    elsif ( $metric =~ m/^iops_read$/ ) {
      $iops_read = $args{$metric};
    }
    elsif ( $metric =~ m/^iops_write$/ ) {
      $iops_write = $args{$metric};
    }
    elsif ( $metric =~ m/^io_throughput_total$/ ) {
      $io_tp_total = $args{$metric};
    }
    elsif ( $metric =~ m/^io_throughput_read$/ ) {
      $io_tp_read = $args{$metric};
    }
    elsif ( $metric =~ m/^io_throughput_write$/ ) {
      $io_tp_write = $args{$metric};
    }
    elsif ( $metric =~ m/^read_latency$/ ) {
      $read_latency = $args{$metric};
    }
    elsif ( $metric =~ m/^write_latency$/ ) {
      $write_latency = $args{$metric};
    }
    elsif ( $metric =~ m/^total_latency$/ ) {
      $total_latency = $args{$metric};
    }
    elsif ( $metric =~ m/^read$/ ) {
      $read = $args{$metric} * 1000;
    }
    elsif ( $metric =~ m/^write$/ ) {
      $write = $args{$metric} * 1000;
    }
  }

  my $values = join ":", (
    $iowait,       $iops_total,    $iops_read, $iops_write,
    $io_tp_total,  $io_tp_read,    $io_tp_write,
    $read_latency, $write_latency, $total_latency, $read, $write
  );

  RRDp::cmd qq(update "$filepath" $timestamp:$values);
  eval { my $answer = RRDp::read; };

  if ($@) {
    warn( localtime() . ": Failed during read last time $filepath: $@ " . __FILE__ . ":" . __LINE__ );
    return 1;
  }

  return 0;
}

sub update_rrd_vm {
  my $filepath  = shift;
  my $timestamp = shift;
  my %args      = %{ shift() };

  # check if the data is new enough
  my $last_update = rrd_last_update($filepath);
  unless ( $timestamp > $$last_update ) {
    return 0;
  }

  my (
    $cpu_percent, $cpu_cores,            $cpu_core_count,
    $memory,      $memory_internal_free, $memory_target,
    $transmitted, $received,
    $iops_total,  $iops_read,    $iops_write,
    $io_tp_total, $io_tp_read,   $io_tp_write,
    $iowait,      $read_latency, $write_latency,
    $read,        $write,        $total
  ) = ("U") x 19;

  for my $metric ( keys %args ) {

    # quick fix if data are incomplete
    if ( !exists( $args{$metric} ) ) { next; }
  }

  $cpu_percent = exists $args{cpu_percent} && defined $args{cpu_percent} ? $args{cpu_percent} / 1000000 : "U";
  $cpu_cores            = exists $args{cpu_cores}            && defined $args{cpu_cores} && $cpu_percent ne "U" ? $args{cpu_cores} * $cpu_percent            : "U";
  $cpu_core_count       = exists $args{cpu_cores}            && defined $args{cpu_cores}                        ? $args{cpu_cores}                           : "U";
  $memory               = exists $args{memory}               && defined $args{memory}                           ? ceil( $args{memory} / 1024 )               : "U";
  $memory_internal_free = exists $args{memory_internal_free} && defined $args{memory_internal_free}             ? ceil( $args{memory_internal_free} / 1024 ) : "U";
  $memory_target        = $memory ne "U"                     && $memory_internal_free ne "U"                    ? $memory - $memory_internal_free            : "U";
  $read                 = exists $args{'read'}               && defined $args{'read'}                           ? $args{'read'} * 1024                       : "U";
  $write                = exists $args{'write'}              && defined $args{'write'}                          ? $args{'write'} * 1024                      : "U";
  $total                = exists $args{'total'}              && defined $args{'total'}                          ? $args{'total'} * 1024                      : "U";
  $iops_read            = exists $args{iops_read}            && defined $args{iops_read}                        ? $args{iops_read}                           : "U";
  $iops_write           = exists $args{iops_write}           && defined $args{iops_write}                       ? $args{iops_write}                          : "U";
  $read_latency         = exists $args{read_latency}         && defined $args{read_latency}                     ? $args{read_latency} / 1024                 : "U";
  $write_latency        = exists $args{write_latency}        && defined $args{write_latency}                    ? $args{write_latency} / 1024                : "U";
  $transmitted          = exists $args{transmitted}          && defined $args{transmitted}                      ? $args{transmitted}                         : "U";
  $received             = exists $args{received}             && defined $args{received}                         ? $args{received}                            : "U";

  my $values = join ":", (
    $cpu_percent, $cpu_cores,            $cpu_core_count,
    $memory,      $memory_internal_free, $memory_target,
    $transmitted, $received,
    $iops_total,  $iops_read,    $iops_write,
    $io_tp_total, $io_tp_read,   $io_tp_write,
    $iowait,      $read_latency, $write_latency,
    $total,       $read,         $write
  );

  RRDp::cmd qq(update "$filepath" $timestamp:$values);
  eval { my $answer = RRDp::read; };

  if ($@) {
    warn( localtime() . ": Failed during read last time $filepath: $@ " . __FILE__ . ":" . __LINE__ );
    return 1;
  }

  return 0;
}

################################################################################

sub create_rrd_host {
  my $filepath   = shift;
  my $start_time = shift;

  touch("create_rrd_host $filepath");

  RRDp::cmd qq(create "$filepath" --start "$start_time" --step "$step"
        "DS:cpu_avg:GAUGE:$no_time:0:1"
        "DS:cpu_cores:GAUGE:$no_time:0:U"
        "DS:cpu_core_count:GAUGE:$no_time:0:U"
        "DS:memory_total:GAUGE:$no_time:0:U"
        "DS:memory_free:GAUGE:$no_time:0:U"
        "RRA:AVERAGE:0.5:1:$one_minute_sample"
        "RRA:AVERAGE:0.5:5:$five_mins_sample"
        "RRA:AVERAGE:0.5:60:$one_hour_sample"
        "RRA:AVERAGE:0.5:300:$five_hours_sample"
        "RRA:AVERAGE:0.5:1440:$one_day_sample"
        );

  if ( !Xorux_lib::create_check("file: $filepath, $one_minute_sample, $five_mins_sample, $one_hour_sample, $five_hours_sample, $one_day_sample") ) {
    warn( localtime() . ": failed to create $filepath : at " . __FILE__ . ": line " . __LINE__ );
    RRDp::end;
    RRDp::start "$rrdtool";
    return 2;
  }

  return 0;
}

sub create_rrd_host_disk {
  my $filepath   = shift;
  my $start_time = shift;

  touch("create_rrd_host_disk $filepath");

  RRDp::cmd qq(create "$filepath" --start "$start_time" --step "$step"
        "DS:vbd_iowait:GAUGE:$no_time:0:U"
        "DS:vbd_iops_total:GAUGE:$no_time:0:U"
        "DS:vbd_iops_read:GAUGE:$no_time:0:U"
        "DS:vbd_iops_write:GAUGE:$no_time:0:U"
        "DS:vbd_io_tp_total:GAUGE:$no_time:0:U"
        "DS:vbd_io_tp_read:GAUGE:$no_time:0:U"
        "DS:vbd_io_tp_write:GAUGE:$no_time:0:U"
        "DS:vbd_read_latency:GAUGE:$no_time:0:U"
        "DS:vbd_write_latency:GAUGE:$no_time:0:U"
        "DS:vbd_total_latency:GAUGE:$no_time:0:U"
        "DS:vbd_read:GAUGE:$no_time:0:U"
        "DS:vbd_write:GAUGE:$no_time:0:U"
        "RRA:AVERAGE:0.5:1:$one_minute_sample"
        "RRA:AVERAGE:0.5:5:$five_mins_sample"
        "RRA:AVERAGE:0.5:60:$one_hour_sample"
        "RRA:AVERAGE:0.5:300:$five_hours_sample"
        "RRA:AVERAGE:0.5:1440:$one_day_sample"
        );

  if ( !Xorux_lib::create_check("file: $filepath, $one_minute_sample, $five_mins_sample, $one_hour_sample, $five_hours_sample, $one_day_sample") ) {
    warn( localtime() . ": failed to create $filepath : at " . __FILE__ . ": line " . __LINE__ );
    RRDp::end;
    RRDp::start "$rrdtool";
    return 2;
  }

  return 0;
}

sub create_rrd_storage_container {
  my $filepath   = shift;
  my $start_time = shift;

  touch("create_rrd_storage_container $filepath");

  RRDp::cmd qq(create "$filepath" --start "$start_time" --step "$step"
        "DS:vbd_iowait:GAUGE:$no_time:0:U"
        "DS:vbd_iops_total:GAUGE:$no_time:0:U"
        "DS:vbd_iops_read:GAUGE:$no_time:0:U"
        "DS:vbd_iops_write:GAUGE:$no_time:0:U"
        "DS:vbd_io_tp_total:GAUGE:$no_time:0:U"
        "DS:vbd_io_tp_read:GAUGE:$no_time:0:U"
        "DS:vbd_io_tp_write:GAUGE:$no_time:0:U"
        "DS:vbd_read_latency:GAUGE:$no_time:0:U"
        "DS:vbd_write_latency:GAUGE:$no_time:0:U"
        "DS:vbd_total_latency:GAUGE:$no_time:0:U"
        "DS:vbd_read:GAUGE:$no_time:0:U"
        "DS:vbd_write:GAUGE:$no_time:0:U"
        "RRA:AVERAGE:0.5:1:$one_minute_sample"
        "RRA:AVERAGE:0.5:5:$five_mins_sample"
        "RRA:AVERAGE:0.5:60:$one_hour_sample"
        "RRA:AVERAGE:0.5:300:$five_hours_sample"
        "RRA:AVERAGE:0.5:1440:$one_day_sample"
        );

  if ( !Xorux_lib::create_check("file: $filepath, $one_minute_sample, $five_mins_sample, $one_hour_sample, $five_hours_sample, $one_day_sample") ) {
    warn( localtime() . ": failed to create $filepath : at " . __FILE__ . ": line " . __LINE__ );
    RRDp::end;
    RRDp::start "$rrdtool";
    return 2;
  }

  return 0;
}

sub create_rrd_virtual_disk {
  my $filepath   = shift;
  my $start_time = shift;

  touch("create_rrd_virtual_disk $filepath");

  RRDp::cmd qq(create "$filepath" --start "$start_time" --step "$step"
        "DS:vbd_iowait:GAUGE:$no_time:0:U"
        "DS:vbd_iops_total:GAUGE:$no_time:0:U"
        "DS:vbd_iops_read:GAUGE:$no_time:0:U"
        "DS:vbd_iops_write:GAUGE:$no_time:0:U"
        "DS:vbd_io_tp_total:GAUGE:$no_time:0:U"
        "DS:vbd_io_tp_read:GAUGE:$no_time:0:U"
        "DS:vbd_io_tp_write:GAUGE:$no_time:0:U"
        "DS:vbd_read_latency:GAUGE:$no_time:0:U"
        "DS:vbd_write_latency:GAUGE:$no_time:0:U"
        "DS:vbd_total_latency:GAUGE:$no_time:0:U"
        "DS:vbd_read:GAUGE:$no_time:0:U"
        "DS:vbd_write:GAUGE:$no_time:0:U"
        "RRA:AVERAGE:0.5:1:$one_minute_sample"
        "RRA:AVERAGE:0.5:5:$five_mins_sample"
        "RRA:AVERAGE:0.5:60:$one_hour_sample"
        "RRA:AVERAGE:0.5:300:$five_hours_sample"
        "RRA:AVERAGE:0.5:1440:$one_day_sample"
        );

  if ( !Xorux_lib::create_check("file: $filepath, $one_minute_sample, $five_mins_sample, $one_hour_sample, $five_hours_sample, $one_day_sample") ) {
    warn( localtime() . ": failed to create $filepath : at " . __FILE__ . ": line " . __LINE__ );
    RRDp::end;
    RRDp::start "$rrdtool";
    return 2;
  }

  return 0;
}

sub create_rrd_volume_group {
  my $filepath   = shift;
  my $start_time = shift;

  touch("create_rrd_volume_group $filepath");

  RRDp::cmd qq(create "$filepath" --start "$start_time" --step "$step"
        "DS:vbd_iowait:GAUGE:$no_time:0:U"
        "DS:vbd_iops_total:GAUGE:$no_time:0:U"
        "DS:vbd_iops_read:GAUGE:$no_time:0:U"
        "DS:vbd_iops_write:GAUGE:$no_time:0:U"
        "DS:vbd_io_tp_total:GAUGE:$no_time:0:U"
        "DS:vbd_io_tp_read:GAUGE:$no_time:0:U"
        "DS:vbd_io_tp_write:GAUGE:$no_time:0:U"
        "DS:vbd_read_latency:GAUGE:$no_time:0:U"
        "DS:vbd_write_latency:GAUGE:$no_time:0:U"
        "DS:vbd_total_latency:GAUGE:$no_time:0:U"
        "DS:vbd_read:GAUGE:$no_time:0:U"
        "DS:vbd_write:GAUGE:$no_time:0:U"
        "RRA:AVERAGE:0.5:1:$one_minute_sample"
        "RRA:AVERAGE:0.5:5:$five_mins_sample"
        "RRA:AVERAGE:0.5:60:$one_hour_sample"
        "RRA:AVERAGE:0.5:300:$five_hours_sample"
        "RRA:AVERAGE:0.5:1440:$one_day_sample"
        );

  if ( !Xorux_lib::create_check("file: $filepath, $one_minute_sample, $five_mins_sample, $one_hour_sample, $five_hours_sample, $one_day_sample") ) {
    warn( localtime() . ": failed to create $filepath : at " . __FILE__ . ": line " . __LINE__ );
    RRDp::end;
    RRDp::start "$rrdtool";
    return 2;
  }

  return 0;
}

sub create_rrd_storage_pool {
  my $filepath   = shift;
  my $start_time = shift;

  touch("create_rrd_storage_pool $filepath");

  RRDp::cmd qq(create "$filepath" --start "$start_time" --step "$step"
        "DS:vbd_iowait:GAUGE:$no_time:0:U"
        "DS:vbd_iops_total:GAUGE:$no_time:0:U"
        "DS:vbd_iops_read:GAUGE:$no_time:0:U"
        "DS:vbd_iops_write:GAUGE:$no_time:0:U"
        "DS:vbd_io_tp_total:GAUGE:$no_time:0:U"
        "DS:vbd_io_tp_read:GAUGE:$no_time:0:U"
        "DS:vbd_io_tp_write:GAUGE:$no_time:0:U"
        "DS:vbd_read_latency:GAUGE:$no_time:0:U"
        "DS:vbd_write_latency:GAUGE:$no_time:0:U"
        "DS:vbd_total_latency:GAUGE:$no_time:0:U"
        "DS:vbd_read:GAUGE:$no_time:0:U"
        "DS:vbd_write:GAUGE:$no_time:0:U"
        "RRA:AVERAGE:0.5:1:$one_minute_sample"
        "RRA:AVERAGE:0.5:5:$five_mins_sample"
        "RRA:AVERAGE:0.5:60:$one_hour_sample"
        "RRA:AVERAGE:0.5:300:$five_hours_sample"
        "RRA:AVERAGE:0.5:1440:$one_day_sample"
        );

  if ( !Xorux_lib::create_check("file: $filepath, $one_minute_sample, $five_mins_sample, $one_hour_sample, $five_hours_sample, $one_day_sample") ) {
    warn( localtime() . ": failed to create $filepath : at " . __FILE__ . ": line " . __LINE__ );
    RRDp::end;
    RRDp::start "$rrdtool";
    return 2;
  }

  return 0;
}

sub create_rrd_vm {
  my $filepath   = shift;
  my $start_time = shift;

  touch("create_rrd_vm $filepath");

  RRDp::cmd qq(create "$filepath" --start "$start_time" --step "$step"
        "DS:cpu:GAUGE:$no_time:0:1"
        "DS:cpu_cores:GAUGE:$no_time:0:U"
        "DS:cpu_core_count:GAUGE:$no_time:0:U"
        "DS:memory:GAUGE:$no_time:0:U"
        "DS:memory_int_free:GAUGE:$no_time:0:U"
        "DS:memory_target:GAUGE:$no_time:0:U"
        "DS:net_transmitted:GAUGE:$no_time:0:U"
        "DS:net_received:GAUGE:$no_time:0:U"
        "DS:vbd_iops_total:GAUGE:$no_time:0:U"
        "DS:vbd_iops_read:GAUGE:$no_time:0:U"
        "DS:vbd_iops_write:GAUGE:$no_time:0:U"
        "DS:vbd_io_tp_total:GAUGE:$no_time:0:U"
        "DS:vbd_io_tp_read:GAUGE:$no_time:0:U"
        "DS:vbd_io_tp_write:GAUGE:$no_time:0:U"
        "DS:vbd_iowait:GAUGE:$no_time:0:U"
        "DS:vbd_read_latency:GAUGE:$no_time:0:U"
        "DS:vbd_write_latency:GAUGE:$no_time:0:U"
        "DS:vbd_total:GAUGE:$no_time:0:U"
	      "DS:vbd_read:GAUGE:$no_time:0:U"
        "DS:vbd_write:GAUGE:$no_time:0:U"
        "RRA:AVERAGE:0.5:1:$one_minute_sample"
        "RRA:AVERAGE:0.5:5:$five_mins_sample"
        "RRA:AVERAGE:0.5:60:$one_hour_sample"
        "RRA:AVERAGE:0.5:300:$five_hours_sample"
        "RRA:AVERAGE:0.5:1440:$one_day_sample"
        );

  if ( !Xorux_lib::create_check("file: $filepath, $one_minute_sample, $five_mins_sample, $one_hour_sample, $five_hours_sample, $one_day_sample") ) {
    warn( localtime() . ": failed to create $filepath : at " . __FILE__ . ": line " . __LINE__ );
    RRDp::end;
    RRDp::start "$rrdtool";
    return 2;
  }

  return 0;
}

###

# copied from LoadDataModule.pm with minor changes (removed $host/HMC)

sub touch {
  my $text = shift;

  my $version    = "$ENV{version}";
  my $basedir    = $ENV{INPUTDIR};
  my $new_change = "$basedir/tmp/$version-nutanix";
  my $DEBUG      = $ENV{DEBUG};

  if ( !-f $new_change ) {
    `touch $new_change`;    # tell install_html.sh that there has been a change
    if ( $text eq '' ) {
      print "touch          : $new_change\n" if $DEBUG;
    }
    else {
      print "touch          : $new_change : $text\n" if $DEBUG;
    }
  }

  return 0;
}

sub exists_and_defined {
  my ($data) = @_;
  if ( defined $data ) {
    return 1;
  }
  else {
    return 0;
  }
}

1;

