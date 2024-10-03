# KubernetesLoadDataModule.pm
# create/update RRDs with Kubernetes metrics

package KubernetesLoadDataModule;

use strict;
use warnings;

use Data::Dumper;
use Date::Parse;
use RRDp;
use File::Copy qw(copy);
use Xorux_lib;
use Math::BigInt;
use POSIX;

use KubernetesDataWrapper;

my $rrdtool = $ENV{RRDTOOL};

my $step           = 60;
my $no_time        = $step * 7;
my $no_time_twenty = $step * 25;

my $one_minute_sample = 86400;
my $five_mins_sample  = 25920;
my $one_hour_sample   = 4320;
my $five_hours_sample = 1734;
my $one_day_sample    = 1080;

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

sub update_rrd_node {
  my $filepath  = shift;
  my $timestamp = shift;
  my %args      = %{ shift() };

  #check if the data is new enough
  my $last_update = rrd_last_update($filepath);
  unless ( $timestamp > $$last_update ) {
    return 0;
  }

  my $cpu                = exists $args{cpu}                && defined $args{cpu}                ? $args{cpu}                : "U";
  my $cpu_allocatable    = exists $args{cpu_allocatable}    && defined $args{cpu_allocatable}    ? $args{cpu_allocatable}    : "U";
  my $cpu_capacity       = exists $args{cpu_capacity}       && defined $args{cpu_capacity}       ? $args{cpu_capacity}       : "U";
  my $memory             = exists $args{memory}             && defined $args{memory}             ? $args{memory}             : "U";
  my $memory_allocatable = exists $args{memory_allocatable} && defined $args{memory_allocatable} ? $args{memory_allocatable} : "U";
  my $memory_capacity    = exists $args{memory_capacity}    && defined $args{memory_capacity}    ? $args{memory_capacity}    : "U";

  my $ephemeral_storage_allocatable = exists $args{ephemeral_storage_allocatable} && defined $args{ephemeral_storage_allocatable} ? $args{ephemeral_storage_allocatable} : "U";
  my $ephemeral_storage_capacity    = exists $args{ephemeral_storage_capacity}    && defined $args{ephemeral_storage_capacity}    ? $args{ephemeral_storage_capacity}    : "U";
  my $pods                          = exists $args{pods}                          && defined $args{pods}                          ? $args{pods}                          : "U";
  my $pods_allocatable              = exists $args{pods_allocatable}              && defined $args{pods_allocatable}              ? $args{pods_allocatable}              : "U";
  my $pods_capacity                 = exists $args{pods_capacity}                 && defined $args{pods_capacity}                 ? $args{pods_capacity}                 : "U";

  #cadvisor
  my $container_fs_reads_bytes_total   = exists $args{container_fs_reads_bytes_total}   && defined $args{container_fs_reads_bytes_total}   ? int( $args{container_fs_reads_bytes_total} )          : "U";
  my $container_fs_writes_bytes_total  = exists $args{container_fs_writes_bytes_total}  && defined $args{container_fs_writes_bytes_total}  ? int( $args{container_fs_writes_bytes_total} )         : "U";
  my $container_fs_reads_total         = exists $args{container_fs_reads_total}         && defined $args{container_fs_reads_total}         ? int( $args{container_fs_reads_total} * 1000 ) / 1000  : "U";
  my $container_fs_writes_total        = exists $args{container_fs_writes_total}        && defined $args{container_fs_writes_total}        ? int( $args{container_fs_writes_total} * 1000 ) / 1000 : "U";
  my $container_fs_read_seconds_total  = exists $args{container_fs_read_seconds_total}  && defined $args{container_fs_read_seconds_total}  ? int( $args{container_fs_read_seconds_total} * 1000 )  : "U";
  my $container_fs_write_seconds_total = exists $args{container_fs_write_seconds_total} && defined $args{container_fs_write_seconds_total} ? int( $args{container_fs_write_seconds_total} * 1000 ) : "U";
  my $container_network_receive_bytes_total    = exists $args{container_network_receive_bytes_total}    && defined $args{container_network_receive_bytes_total}    && $args{container_network_receive_bytes_total} ne "U"    ? int( $args{container_network_receive_bytes_total} )    : "U";
  my $container_network_receive_packets_total  = exists $args{container_network_receive_packets_total}  && defined $args{container_network_receive_packets_total}  && $args{container_network_receive_packets_total} ne "U"  ? int( $args{container_network_receive_packets_total} )  : "U";
  my $container_network_transmit_bytes_total   = exists $args{container_network_transmit_bytes_total}   && defined $args{container_network_transmit_bytes_total}   && $args{container_network_transmit_bytes_total} ne "U"   ? int( $args{container_network_transmit_bytes_total} )   : "U";
  my $container_network_transmit_packets_total = exists $args{container_network_transmit_packets_total} && defined $args{container_network_transmit_packets_total} && $args{container_network_transmit_packets_total} ne "U" ? int( $args{container_network_transmit_packets_total} ) : "U";
  my $metric_resolution        = exists $args{metric_resolution}        && defined $args{metric_resolution}        ? $args{metric_resolution}        : "U";
  my $container_fs_usage_bytes = exists $args{container_fs_usage_bytes} && defined $args{container_fs_usage_bytes} ? $args{container_fs_usage_bytes} : "U";

  my $values = join ":", ( $cpu, $cpu_allocatable, $cpu_capacity, $memory, $memory_allocatable, $memory_capacity, $ephemeral_storage_allocatable, $ephemeral_storage_capacity, $pods, $pods_allocatable, $pods_capacity, $container_fs_reads_bytes_total, $container_fs_writes_bytes_total, $container_fs_reads_total, $container_fs_writes_total, $container_fs_read_seconds_total, $container_fs_write_seconds_total, $container_network_receive_bytes_total, $container_network_receive_packets_total, $container_network_transmit_bytes_total, $container_network_transmit_packets_total, $metric_resolution, $container_fs_usage_bytes );

  RRDp::cmd qq(update "$filepath" $timestamp:$values);
  eval { my $answer = RRDp::read; };

  if ($@) {
    warn( localtime() . ": Failed during read last time $filepath: $@ " . __FILE__ . ":" . __LINE__ );
    return 1;
  }

  return 0;
}

sub update_rrd_pod {
  my $filepath  = shift;
  my $timestamp = shift;
  my %args      = %{ shift() };

  #check if the data is new enough
  my $last_update = rrd_last_update($filepath);
  unless ( $timestamp > $$last_update ) {
    return 0;
  }

  my $cpu            = exists $args{cpu}            && defined $args{cpu}            ? $args{cpu}            : "U";
  my $cpu_request    = exists $args{cpu_request}    && defined $args{cpu_request}    ? $args{cpu_request}    : "U";
  my $cpu_limit      = exists $args{cpu_limit}      && defined $args{cpu_limit}      ? $args{cpu_limit}      : "U";
  my $memory         = exists $args{memory}         && defined $args{memory}         ? $args{memory}         : "U";
  my $memory_request = exists $args{memory_request} && defined $args{memory_request} ? $args{memory_request} : "U";
  my $memory_limit   = exists $args{memory_limit}   && defined $args{memory_limit}   ? $args{memory_limit}   : "U";

  #cadvisor
  my $container_network_receive_bytes_total  = exists $args{container_network_receive_bytes_total}  && defined $args{container_network_receive_bytes_total}  && $args{container_network_receive_bytes_total} ne "U"  ? int( $args{container_network_receive_bytes_total} )  : "U";
  my $container_network_transmit_bytes_total = exists $args{container_network_transmit_bytes_total} && defined $args{container_network_transmit_bytes_total} && $args{container_network_transmit_bytes_total} ne "U" ? int( $args{container_network_transmit_bytes_total} ) : "U";

  my $values = join ":", ( $cpu, $cpu_request, $cpu_limit, $memory, $memory_request, $memory_limit, $container_network_receive_bytes_total, $container_network_transmit_bytes_total );

  RRDp::cmd qq(update "$filepath" $timestamp:$values);
  eval { my $answer = RRDp::read; };

  if ($@) {
    warn( localtime() . ": Failed during read last time $filepath: $@ " . __FILE__ . ":" . __LINE__ );
    return 1;
  }

  return 0;
}

sub update_rrd_namespace {
  my $filepath  = shift;
  my $timestamp = shift;
  my %args      = %{ shift() };

  #check if the data is new enough
  my $last_update = rrd_last_update($filepath);
  unless ( $timestamp > $$last_update ) {
    return 0;
  }

  my $cpu    = exists $args{cpu}    && defined $args{cpu}    ? $args{cpu}    : "U";
  my $memory = exists $args{memory} && defined $args{memory} ? $args{memory} : "U";

  my $values = join ":", ( $cpu, $memory );

  RRDp::cmd qq(update "$filepath" $timestamp:$values);
  eval { my $answer = RRDp::read; };

  if ($@) {
    warn( localtime() . ": Failed during read last time $filepath: $@ " . __FILE__ . ":" . __LINE__ );
    return 1;
  }

  return 0;
}

sub update_rrd_container {
  my $filepath  = shift;
  my $timestamp = shift;
  my %args      = %{ shift() };

  #check if the data is new enough
  my $last_update = rrd_last_update($filepath);
  unless ( $timestamp > $$last_update ) {
    return 0;
  }

  my $cpu            = exists $args{cpu}            && defined $args{cpu}            ? $args{cpu}            : "U";
  my $cpu_request    = exists $args{cpu_request}    && defined $args{cpu_request}    ? $args{cpu_request}    : "U";
  my $cpu_limit      = exists $args{cpu_limit}      && defined $args{cpu_limit}      ? $args{cpu_limit}      : "U";
  my $memory         = exists $args{memory}         && defined $args{memory}         ? $args{memory}         : "U";
  my $memory_request = exists $args{memory_request} && defined $args{memory_request} ? $args{memory_request} : "U";
  my $memory_limit   = exists $args{memory_limit}   && defined $args{memory_limit}   ? $args{memory_limit}   : "U";

  #cadvisor
  my $container_fs_reads_bytes_total   = exists $args{container_fs_reads_bytes_total}   && defined $args{container_fs_reads_bytes_total}   && $args{container_fs_reads_bytes_total} ne "U"   ? int( $args{container_fs_reads_bytes_total} )          : "U";
  my $container_fs_writes_bytes_total  = exists $args{container_fs_writes_bytes_total}  && defined $args{container_fs_writes_bytes_total}  && $args{container_fs_writes_bytes_total} ne "U"  ? int( $args{container_fs_writes_bytes_total} )         : "U";
  my $container_fs_reads_total         = exists $args{container_fs_reads_total}         && defined $args{container_fs_reads_total}         && $args{container_fs_reads_total} ne "U"         ? int( $args{container_fs_reads_total} * 1000 ) / 1000  : "U";
  my $container_fs_writes_total        = exists $args{container_fs_writes_total}        && defined $args{container_fs_writes_total}        && $args{container_fs_writes_total} ne "U"        ? int( $args{container_fs_writes_total} * 1000 ) / 1000 : "U";
  my $container_fs_read_seconds_total  = exists $args{container_fs_read_seconds_total}  && defined $args{container_fs_read_seconds_total}  && $args{container_fs_read_seconds_total} ne "U"  ? int( $args{container_fs_read_seconds_total} * 1000 )  : "U";
  my $container_fs_write_seconds_total = exists $args{container_fs_write_seconds_total} && defined $args{container_fs_write_seconds_total} && $args{container_fs_write_seconds_total} ne "U" ? int( $args{container_fs_write_seconds_total} * 1000 ) : "U";
  my $container_fs_usage_bytes         = exists $args{container_fs_usage_bytes}         && defined $args{container_fs_usage_bytes}         && $args{container_fs_usage_bytes} ne "U"         ? $args{container_fs_usage_bytes}                       : "U";

  my $values = join ":", ( $cpu, $cpu_request, $cpu_limit, $memory, $memory_request, $memory_limit, $container_fs_reads_bytes_total, $container_fs_writes_bytes_total, $container_fs_reads_total, $container_fs_writes_total, $container_fs_read_seconds_total, $container_fs_write_seconds_total, $container_fs_usage_bytes );

  RRDp::cmd qq(update "$filepath" $timestamp:$values);
  eval { my $answer = RRDp::read; };

  if ($@) {
    warn( localtime() . ": Failed during read last time $filepath: $@ " . __FILE__ . ":" . __LINE__ );
    return 1;
  }

  return 0;
}

sub update_rrd_pod_network {
  my $filepath  = shift;
  my $timestamp = shift;
  my %args      = %{ shift() };

  #check if the data is new enough
  my $last_update = rrd_last_update($filepath);
  unless ( $timestamp > $$last_update ) {
    return 0;
  }

  my $container_network_receive_packets_total  = exists $args{container_network_receive_packets_total}  && defined $args{container_network_receive_packets_total}  ? int( $args{container_network_receive_packets_total} )  : "U";
  my $container_network_receive_bytes_total    = exists $args{container_network_receive_bytes_total}    && defined $args{container_network_receive_bytes_total}    ? int( $args{container_network_receive_bytes_total} )    : "U";
  my $container_network_transmit_bytes_total   = exists $args{container_network_transmit_bytes_total}   && defined $args{container_network_transmit_bytes_total}   ? int( $args{container_network_transmit_bytes_total} )   : "U";
  my $container_network_transmit_packets_total = exists $args{container_network_transmit_packets_total} && defined $args{container_network_transmit_packets_total} ? int( $args{container_network_transmit_packets_total} ) : "U";

  my $values = join ":", ( $container_network_receive_bytes_total, $container_network_transmit_bytes_total, $container_network_receive_packets_total, $container_network_transmit_packets_total );

  RRDp::cmd qq(update "$filepath" $timestamp:$values);
  eval { my $answer = RRDp::read; };

  if ($@) {
    warn( localtime() . ": Failed during read last time $filepath: $@ " . __FILE__ . ":" . __LINE__ );
    return 1;
  }

  return 0;
}

################################################################################

sub create_rrd_node {
  my $filepath   = shift;
  my $start_time = shift;

  touch("create_rrd_node $filepath");

  RRDp::cmd qq(create "$filepath" --start "$start_time" --step "$step"
        "DS:cpu:GAUGE:$no_time:0:U"
        "DS:cpu_allocatable:GAUGE:$no_time:0:U"
        "DS:cpu_capacity:GAUGE:$no_time:0:U"
        "DS:memory:GAUGE:$no_time:0:U"
        "DS:memory_allocatable:GAUGE:$no_time:0:U"
        "DS:memory_capacity:GAUGE:$no_time:0:U"
        "DS:storage_allocatable:GAUGE:$no_time:0:U"
	"DS:storage_capacity:GAUGE:$no_time:0:U"
	"DS:pods:GAUGE:$no_time:0:U"
	"DS:pods_allocatable:GAUGE:$no_time:0:U"
	"DS:pods_capacity:GAUGE:$no_time:0:U"
	"DS:reads_bytes:GAUGE:$no_time:0:U"
	"DS:writes_bytes:GAUGE:$no_time:0:U"
	"DS:reads:GAUGE:$no_time:0:U"
	"DS:writes:GAUGE:$no_time:0:U"
	"DS:read_seconds:GAUGE:$no_time:0:U"
	"DS:write_seconds:GAUGE:$no_time:0:U"
	"DS:receive_bytes:COUNTER:$no_time:0:U"
	"DS:receive_packets:COUNTER:$no_time:0:U"
	"DS:transmit_bytes:COUNTER:$no_time:0:U"
	"DS:transmit_packets:COUNTER:$no_time:0:U"
	"DS:metric_resolution:GAUGE:$no_time:0:U"
        "DS:usage_bytes:GAUGE:$no_time:0:U"
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

sub create_rrd_pod {
  my $filepath   = shift;
  my $start_time = shift;

  touch("create_rrd_pod $filepath");

  RRDp::cmd qq(create "$filepath" --start "$start_time" --step "$step"
        "DS:cpu:GAUGE:$no_time:0:U"
        "DS:cpu_request:GAUGE:$no_time:0:U"
        "DS:cpu_limit:GAUGE:$no_time:0:U"
        "DS:memory:GAUGE:$no_time:0:U"
        "DS:memory_request:GAUGE:$no_time:0:U"
        "DS:memory_limit:GAUGE:$no_time:0:U"
        "DS:receive_bytes:COUNTER:$no_time:0:U"
        "DS:transmit_bytes:COUNTER:$no_time:0:U"
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

sub create_rrd_namespace {
  my $filepath   = shift;
  my $start_time = shift;

  touch("create_rrd_namespace $filepath");

  RRDp::cmd qq(create "$filepath" --start "$start_time" --step "$step"
        "DS:cpu:GAUGE:$no_time:0:U"
        "DS:memory:GAUGE:$no_time:0:U"
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

sub create_rrd_container {
  my $filepath   = shift;
  my $start_time = shift;

  touch("create_rrd_container $filepath");

  RRDp::cmd qq(create "$filepath" --start "$start_time" --step "$step"
        "DS:cpu:GAUGE:$no_time:0:U"
        "DS:cpu_request:GAUGE:$no_time:0:U"
        "DS:cpu_limit:GAUGE:$no_time:0:U"
        "DS:memory:GAUGE:$no_time:0:U"
        "DS:memory_request:GAUGE:$no_time:0:U"
        "DS:memory_limit:GAUGE:$no_time:0:U"
	"DS:reads_bytes:GAUGE:$no_time:0:U"
        "DS:writes_bytes:GAUGE:$no_time:0:U"
        "DS:reads:GAUGE:$no_time:0:U"
        "DS:writes:GAUGE:$no_time:0:U"
        "DS:read_seconds:GAUGE:$no_time:0:U"
        "DS:write_seconds:GAUGE:$no_time:0:U"
	"DS:usage_bytes:GAUGE:$no_time:0:U"
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

sub create_rrd_pod_network {
  my $filepath   = shift;
  my $start_time = shift;

  touch("create_rrd_pod_network $filepath");

  RRDp::cmd qq(create "$filepath" --start "$start_time" --step "$step"
        "DS:receive_bytes:COUNTER:$no_time:0:U"
        "DS:transmit_bytes:COUNTER:$no_time:0:U"
        "DS:receive_packets:COUNTER:$no_time:0:U"
        "DS:transmit_packets:COUNTER:$no_time:0:U"
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

sub touch {
  my $text = shift;

  my $version    = "$ENV{version}";
  my $basedir    = $ENV{INPUTDIR};
  my $new_change = "$basedir/tmp/$version-compute";
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
