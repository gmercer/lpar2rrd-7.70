# LoadDataModuleXenServer.pm
# create/update RRDs with XenServer [XAPI] metrics

package LoadDataModuleXenServer;

use strict;
use warnings;

use Data::Dumper;
use Date::Parse;
use RRDp;
use File::Copy qw(copy);
use Xorux_lib;
use Math::BigInt;

use XenServerDataWrapper;

my $rrdtool = $ENV{RRDTOOL};

my $step    = 60;
my $no_time = $step * 7;

my $one_minute_sample = 86400;
my $five_mins_sample  = 25920;
my $one_hour_sample   = 4320;
my $five_hours_sample = 1734;
my $one_day_sample    = 1080;

# metrics gathered from XAPI and how they correspond to RRD data structures
# (in part because of the RRD's DS name length limit

my %metrics_host = (
  cpu_percent      => 'cpu_avg',
  cpu_cores        => 'cpu_cores',
  cpu_core_count   => 'cpu_core_count',
  memory_total_kib => 'memory_total',
  memory_free_kib  => 'memory_free'
);

my %metrics_host_lan = (
  pif_tx => 'net_transmitted',
  pif_rx => 'net_received'
);

my %metrics_host_disk = (
  iowait              => 'vbd_iowait',
  iops_total          => 'vbd_iops_total',
  iops_read           => 'vbd_iops_read',
  iops_write          => 'vbd_iops_write',
  io_throughput_total => 'vbd_io_tp_total',
  io_throughput_read  => 'vbd_io_tp_read',
  io_throughput_write => 'vbd_io_tp_write',
  read_latency        => 'vbd_read_latency',
  write_latency       => 'vbd_write_latency',
  read                => 'vbd_read',
  write               => 'vbd_write'
);

my %metrics_vm = (
  cpu_percent             => 'cpu',
  cpu_cores               => 'cpu_cores',
  cpu_core_count          => 'cpu_core_count',
  memory                  => 'memory',
  memory_internal_free    => 'memory_int_free',
  memory_target           => 'memory_target',
  vif_tx                  => 'net_transmitted',
  vif_rx                  => 'net_received',
  vbd_iowait              => 'vbd_iowait',
  vbd_iops_total          => 'vbd_iops_total',
  vbd_iops_read           => 'vbd_iops_read',
  vbd_iops_write          => 'vbd_iops_write',
  vbd_io_throughput_total => 'vbd_io_tp_total',
  vbd_io_throughput_read  => 'vbd_io_tp_read',
  vbd_io_throughput_write => 'vbd_io_tp_write',
  vbd_read_latency        => 'vbd_read_latency',
  vbd_write_latency       => 'vbd_write_latency',
  vbd_read                => 'vbd_read',
  vbd_write               => 'vbd_write'
);

################################################################################

sub update_rrd_host {
  my $filepath  = shift;
  my $timestamp = shift;
  my %args      = %{ shift() };

  # check if the data is new enough
  my $last_update = Xorux_lib::rrd_last_update($filepath);
  unless ( $timestamp > $$last_update ) {
    return 0;
  }

  # (ad-hoc) get the host's CPU/core count
  $filepath =~ m/XEN\/(.*)\/sys\.rrd$/;
  my $host_uuid          = $1;
  my $reported_cpu_count = XenServerDataWrapper::get_host_cpu_count($host_uuid);

  my $cpu_percent = exists $args{cpu_avg} ? $args{cpu_avg} : 'U';
  my $cpu_cores   = my $cpu_core_count = 'U';
  if ( $reported_cpu_count > 0 ) {
    $cpu_cores      = exists $args{cpu_avg} ? ( $args{cpu_avg} * $reported_cpu_count ) : 'U';
    $cpu_core_count = $reported_cpu_count;
  }
  my $memory_total = exists $args{memory_total_kib} ? $args{memory_total_kib} : 'U';
  my $memory_free  = exists $args{memory_free_kib}  ? $args{memory_free_kib}  : 'U';

  my $values = join ':', ( $cpu_percent, $cpu_cores, $cpu_core_count, $memory_total, $memory_free );

  RRDp::cmd qq(update "$filepath" $timestamp:$values);
  eval { my $answer = RRDp::read; };

  if ($@) {
    warn( localtime() . ": Failed during read last time $filepath: $@ " . __FILE__ . ':' . __LINE__ );
    return 1;
  }

  return 0;
}

sub update_rrd_host_lan {
  my $filepath  = shift;
  my $timestamp = shift;
  my %args      = %{ shift() };

  # check if the data is new enough
  my $last_update = Xorux_lib::rrd_last_update($filepath);
  unless ( $timestamp > $$last_update ) {
    return 0;
  }

  my ( $transmitted, $received ) = ('U') x 2;

  for my $metric ( keys %args ) {

    # quick fix if data are incomplete
    if ( !exists( $args{$metric} ) ) { next; }

    my $id = ( split( '_', $metric ) )[1];
    if ( $metric =~ m/^pif_($id)_tx$/ ) {
      $transmitted = $args{$metric};
    }
    elsif ( $metric =~ m/^pif_($id)_rx$/ ) {
      $received = $args{$metric};
    }
  }

  my $values = join ':', ( $transmitted, $received );

  RRDp::cmd qq(update "$filepath" $timestamp:$values);

  eval { my $answer = RRDp::read; };

  if ($@) {
    warn( localtime() . ": Failed during read last time $filepath: $@ " . __FILE__ . ':' . __LINE__ );
    return 1;
  }

  return 0;
}

sub update_rrd_host_disk {
  my $filepath  = shift;
  my $timestamp = shift;
  my %args      = %{ shift() };

  # check if the data is new enough
  my $last_update = Xorux_lib::rrd_last_update($filepath);
  unless ( $timestamp > $$last_update ) {
    return 0;
  }

  my (
    $iowait,       $iops_total,    $iops_read, $iops_write,
    $io_tp_total,  $io_tp_read,    $io_tp_write,
    $read_latency, $write_latency, $read, $write
  ) = ('U') x 11;

  for my $metric ( keys %args ) {

    # quick fix if data are incomplete
    if ( !exists( $args{$metric} ) ) { next; }

    my $id = ( split( '_', $metric ) )[-1];
    if ( $metric =~ m/^iowait_($id)$/ ) {
      $iowait = $args{$metric};
    }
    elsif ( $metric =~ m/^iops_total_($id)$/ ) {
      $iops_total = $args{$metric};
    }
    elsif ( $metric =~ m/^iops_read_($id)$/ ) {
      $iops_read = $args{$metric};
    }
    elsif ( $metric =~ m/^iops_write_($id)$/ ) {
      $iops_write = $args{$metric};
    }
    elsif ( $metric =~ m/^io_throughput_total_($id)$/ ) {
      $io_tp_total = $args{$metric};
    }
    elsif ( $metric =~ m/^io_throughput_read_($id)$/ ) {
      $io_tp_read = $args{$metric};
    }
    elsif ( $metric =~ m/^io_throughput_write_($id)$/ ) {
      $io_tp_write = $args{$metric};
    }
    elsif ( $metric =~ m/^read_latency_($id)$/ ) {
      $read_latency = $args{$metric};
    }
    elsif ( $metric =~ m/^write_latency_($id)$/ ) {
      $write_latency = $args{$metric};
    }
    elsif ( $metric =~ m/^read_($id)$/ ) {
      $read = $args{$metric};
    }
    elsif ( $metric =~ m/^write_($id)$/ ) {
      $write = $args{$metric};
    }
  }

  my $values = join ':', (
    $iowait,       $iops_total,    $iops_read, $iops_write,
    $io_tp_total,  $io_tp_read,    $io_tp_write,
    $read_latency, $write_latency, $read, $write
  );

  RRDp::cmd qq(update "$filepath" $timestamp:$values);
  eval { my $answer = RRDp::read; };

  if ($@) {
    warn( localtime() . ": Failed during read last time $filepath: $@ " . __FILE__ . ':' . __LINE__ );
    return 1;
  }

  return 0;
}

sub update_rrd_vm {
  my $filepath  = shift;
  my $timestamp = shift;
  my %args      = %{ shift() };

  # check if the data is new enough
  my $last_update = Xorux_lib::rrd_last_update($filepath);
  unless ( $timestamp > $$last_update ) {
    return 0;
  }

  my (
    $cpu_percent, $cpu_cores,            $cpu_core_count,
    $memory,      $memory_internal_free, $memory_target,
    $transmitted, $received,
    $vbd_iops_total,  $vbd_iops_read,    $vbd_iops_write,
    $vbd_io_tp_total, $vbd_io_tp_read,   $vbd_io_tp_write,
    $vbd_iowait,      $vbd_read_latency, $vbd_write_latency,
    $vbd_read,        $vbd_write
  ) = ('U') x 19;

  my ( @weight_iops_total, @weight_iops_read, @weight_iops_write );
  my $count_cpu = 0;

  for my $metric ( keys %args ) {

    # quick fix if data are incomplete
    if ( !exists( $args{$metric} ) ) { next; }

    if ( $metric =~ m/^cpu/ ) {
      if ( $cpu_percent eq 'U' ) {
        $cpu_percent = $args{$metric};
      }
      else {
        $cpu_percent += $args{$metric};
      }
      if ( $cpu_cores eq 'U' ) {
        $cpu_cores = $args{$metric};
      }
      else {
        $cpu_cores += $args{$metric};
      }
      $count_cpu++ unless ( $args{$metric} eq 'U' );
    }
    elsif ( $metric =~ m/^memory$/ ) {
      $memory = $args{$metric};
    }
    elsif ( $metric =~ m/^memory_internal_free$/ ) {
      $memory_internal_free = $args{$metric};
    }
    elsif ( $metric =~ m/^memory_target$/ ) {
      $memory_target = $args{$metric};
    }
    elsif ( $metric =~ m/^(vif|vbd)_/ ) {
      my $id = ( split( '_', $metric ) )[1];

      if ( $metric =~ m/^vif_($id)_tx$/ ) {
        $transmitted = $args{$metric} + ( ( $transmitted eq 'U' ) ? 0 : $transmitted );
      }
      elsif ( $metric =~ m/^vif_($id)_rx$/ ) {
        $received = $args{$metric} + ( ( $received eq 'U' ) ? 0 : $received );
      }
      elsif ( $metric =~ m/^vbd_($id)_iops_total$/ ) {
        $vbd_iops_total = $args{$metric} + ( ( $vbd_iops_total eq 'U' ) ? 0 : $vbd_iops_total );
      }
      elsif ( $metric =~ m/^vbd_($id)_iops_read$/ ) {
        $vbd_iops_read = $args{$metric} + ( ( $vbd_iops_read eq 'U' ) ? 0 : $vbd_iops_read );
      }
      elsif ( $metric =~ m/^vbd_($id)_iops_write$/ ) {
        $vbd_iops_write = $args{$metric} + ( ( $vbd_iops_write eq 'U' ) ? 0 : $vbd_iops_write );
      }
      elsif ( $metric =~ m/^vbd_($id)_io_throughput_total$/ ) {
        $vbd_io_tp_total = $args{$metric} + ( ( $vbd_io_tp_total eq 'U' ) ? 0 : $vbd_io_tp_total );
      }
      elsif ( $metric =~ m/^vbd_($id)_io_throughput_read$/ ) {
        $vbd_io_tp_read = $args{$metric} + ( ( $vbd_io_tp_read eq 'U' ) ? 0 : $vbd_io_tp_read );
      }
      elsif ( $metric =~ m/^vbd_($id)_io_throughput_write$/ ) {
        $vbd_io_tp_write = $args{$metric} + ( ( $vbd_io_tp_write eq 'U' ) ? 0 : $vbd_io_tp_write );
      }
      elsif ( $metric =~ m/^vbd_($id)_iowait$/ ) {
        my $weight = exists( $args{"vbd_$id\_iops_total"} ) ? $args{"vbd_$id\_iops_total"} : 1;
        push @weight_iops_total, $weight;
        $vbd_iowait = $args{$metric} * $weight + ( ( $vbd_iowait eq 'U' ) ? 0 : $vbd_iowait );
      }
      elsif ( $metric =~ m/^vbd_($id)_read_latency$/ ) {
        my $weight = exists( $args{"vbd_$id\_iops_read"} ) ? $args{"vbd_$id\_iops_read"} : 1;
        push @weight_iops_read, $weight;
        $vbd_read_latency = $args{$metric} * $weight + ( ( $vbd_read_latency eq 'U' ) ? 0 : $vbd_read_latency );
      }
      elsif ( $metric =~ m/^vbd_($id)_write_latency$/ ) {
        my $weight = exists( $args{"vbd_$id\_iops_write"} ) ? $args{"vbd_$id\_iops_write"} : 1;
        push @weight_iops_write, $weight;
        $vbd_write_latency = $args{$metric} * $weight + ( ( $vbd_write_latency eq 'U' ) ? 0 : $vbd_write_latency );
      }
      elsif ( $metric =~ m/^vbd_($id)_read$/ ) {
        $vbd_read = $args{$metric} + ( ( $vbd_read eq 'U' ) ? 0 : $vbd_read );
      }
      elsif ( $metric =~ m/^vbd_($id)_write$/ ) {
        $vbd_write = $args{$metric} + ( ( $vbd_write eq 'U' ) ? 0 : $vbd_write );
      }
    }
  }

  # finish computing averages
  unless ( $cpu_percent eq 'U' ) {
    $cpu_percent /= $count_cpu;

    # also save the number of reported VCPUs/cores
    $cpu_core_count = $count_cpu;
  }
  unless ( $vbd_iowait eq 'U' ) {
    my $weights_iops_total;
    $weights_iops_total += $_ for (@weight_iops_total);
    $vbd_iowait         /= ( $weights_iops_total != 0 ) ? $weights_iops_total : 1;
  }
  unless ( $vbd_read_latency eq 'U' ) {
    my $weights_iops_read;
    $weights_iops_read += $_ for (@weight_iops_read);
    $vbd_read_latency  /= ( $weights_iops_read != 0 ) ? $weights_iops_read : 1;
  }
  unless ( $vbd_write_latency eq 'U' ) {
    my $weights_iops_write;
    $weights_iops_write += $_ for (@weight_iops_write);
    $vbd_write_latency  /= ( $weights_iops_write != 0 ) ? $weights_iops_write : 1;
  }

  my $values = join ':', (
    $cpu_percent, $cpu_cores,            $cpu_core_count,
    $memory,      $memory_internal_free, $memory_target,
    $transmitted, $received,
    $vbd_iops_total,  $vbd_iops_read,    $vbd_iops_write,
    $vbd_io_tp_total, $vbd_io_tp_read,   $vbd_io_tp_write,
    $vbd_iowait,      $vbd_read_latency, $vbd_write_latency,
    $vbd_read,        $vbd_write
  );

  RRDp::cmd qq(update "$filepath" $timestamp:$values);
  eval { my $answer = RRDp::read; };

  if ($@) {
    warn( localtime() . ": Failed during read last time $filepath: $@ " . __FILE__ . ':' . __LINE__ );
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
        "DS:$metrics_host{cpu_percent}:GAUGE:$no_time:0:1"
        "DS:$metrics_host{cpu_cores}:GAUGE:$no_time:0:U"
        "DS:$metrics_host{cpu_core_count}:GAUGE:$no_time:0:U"
        "DS:$metrics_host{memory_total_kib}:GAUGE:$no_time:0:U"
        "DS:$metrics_host{memory_free_kib}:GAUGE:$no_time:0:U"
        "RRA:AVERAGE:0.5:1:$one_minute_sample"
        "RRA:AVERAGE:0.5:5:$five_mins_sample"
        "RRA:AVERAGE:0.5:60:$one_hour_sample"
        "RRA:AVERAGE:0.5:300:$five_hours_sample"
        "RRA:AVERAGE:0.5:1440:$one_day_sample"
        );

  if ( !Xorux_lib::create_check("file: $filepath, $one_minute_sample, $five_mins_sample, $one_hour_sample, $five_hours_sample, $one_day_sample") ) {
    warn( localtime() . ": failed to create $filepath : at " . __FILE__ . ': line ' . __LINE__ );
    RRDp::end;
    RRDp::start "$rrdtool";
    return 2;
  }

  return 0;
}

sub create_rrd_host_lan {
  my $filepath   = shift;
  my $start_time = shift;

  touch("create_rrd_host_lan $filepath");

  RRDp::cmd qq(create "$filepath" --start "$start_time" --step "$step"
        "DS:$metrics_host_lan{pif_tx}:GAUGE:$no_time:0:U"
        "DS:$metrics_host_lan{pif_rx}:GAUGE:$no_time:0:U"
        "RRA:AVERAGE:0.5:1:$one_minute_sample"
        "RRA:AVERAGE:0.5:5:$five_mins_sample"
        "RRA:AVERAGE:0.5:60:$one_hour_sample"
        "RRA:AVERAGE:0.5:300:$five_hours_sample"
        "RRA:AVERAGE:0.5:1440:$one_day_sample"
        );

  if ( !Xorux_lib::create_check("file: $filepath, $one_minute_sample, $five_mins_sample, $one_hour_sample, $five_hours_sample, $one_day_sample") ) {
    warn( localtime() . ": failed to create $filepath : at " . __FILE__ . ': line ' . __LINE__ );
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
        "DS:$metrics_host_disk{iowait}:GAUGE:$no_time:0:U"
        "DS:$metrics_host_disk{iops_total}:GAUGE:$no_time:0:U"
        "DS:$metrics_host_disk{iops_read}:GAUGE:$no_time:0:U"
        "DS:$metrics_host_disk{iops_write}:GAUGE:$no_time:0:U"
        "DS:$metrics_host_disk{io_throughput_total}:GAUGE:$no_time:0:U"
        "DS:$metrics_host_disk{io_throughput_read}:GAUGE:$no_time:0:U"
        "DS:$metrics_host_disk{io_throughput_write}:GAUGE:$no_time:0:U"
        "DS:$metrics_host_disk{read_latency}:GAUGE:$no_time:0:U"
        "DS:$metrics_host_disk{write_latency}:GAUGE:$no_time:0:U"
        "DS:$metrics_host_disk{read}:GAUGE:$no_time:0:U"
        "DS:$metrics_host_disk{write}:GAUGE:$no_time:0:U"
        "RRA:AVERAGE:0.5:1:$one_minute_sample"
        "RRA:AVERAGE:0.5:5:$five_mins_sample"
        "RRA:AVERAGE:0.5:60:$one_hour_sample"
        "RRA:AVERAGE:0.5:300:$five_hours_sample"
        "RRA:AVERAGE:0.5:1440:$one_day_sample"
        );

  if ( !Xorux_lib::create_check("file: $filepath, $one_minute_sample, $five_mins_sample, $one_hour_sample, $five_hours_sample, $one_day_sample") ) {
    warn( localtime() . ": failed to create $filepath : at " . __FILE__ . ': line ' . __LINE__ );
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
        "DS:$metrics_vm{cpu_percent}:GAUGE:$no_time:0:1"
        "DS:$metrics_vm{cpu_cores}:GAUGE:$no_time:0:U"
        "DS:$metrics_vm{cpu_core_count}:GAUGE:$no_time:0:U"
        "DS:$metrics_vm{memory}:GAUGE:$no_time:0:U"
        "DS:$metrics_vm{memory_internal_free}:GAUGE:$no_time:0:U"
        "DS:$metrics_vm{memory_target}:GAUGE:$no_time:0:U"
        "DS:$metrics_vm{vif_tx}:GAUGE:$no_time:0:U"
        "DS:$metrics_vm{vif_rx}:GAUGE:$no_time:0:U"
        "DS:$metrics_vm{vbd_iops_total}:GAUGE:$no_time:0:U"
        "DS:$metrics_vm{vbd_iops_read}:GAUGE:$no_time:0:U"
        "DS:$metrics_vm{vbd_iops_write}:GAUGE:$no_time:0:U"
        "DS:$metrics_vm{vbd_io_throughput_total}:GAUGE:$no_time:0:U"
        "DS:$metrics_vm{vbd_io_throughput_read}:GAUGE:$no_time:0:U"
        "DS:$metrics_vm{vbd_io_throughput_write}:GAUGE:$no_time:0:U"
        "DS:$metrics_vm{vbd_iowait}:GAUGE:$no_time:0:U"
        "DS:$metrics_vm{vbd_read_latency}:GAUGE:$no_time:0:U"
        "DS:$metrics_vm{vbd_write_latency}:GAUGE:$no_time:0:U"
        "DS:$metrics_vm{vbd_read}:GAUGE:$no_time:0:U"
        "DS:$metrics_vm{vbd_write}:GAUGE:$no_time:0:U"
        "RRA:AVERAGE:0.5:1:$one_minute_sample"
        "RRA:AVERAGE:0.5:5:$five_mins_sample"
        "RRA:AVERAGE:0.5:60:$one_hour_sample"
        "RRA:AVERAGE:0.5:300:$five_hours_sample"
        "RRA:AVERAGE:0.5:1440:$one_day_sample"
        );

  if ( !Xorux_lib::create_check("file: $filepath, $one_minute_sample, $five_mins_sample, $one_hour_sample, $five_hours_sample, $one_day_sample") ) {
    warn( localtime() . ": failed to create $filepath : at " . __FILE__ . ': line ' . __LINE__ );
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
  my $new_change = "$basedir/tmp/$version-xenserver";
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

1;
