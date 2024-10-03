# AWSLoadDataModule.pm
# create/update RRDs with AWS metrics

package AWSLoadDataModule;

use strict;
use warnings;

use Data::Dumper;
use Date::Parse;
use RRDp;
use File::Copy qw(copy);
use Xorux_lib;
use Math::BigInt;
use POSIX;

use AWSDataWrapper;

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

sub update_rrd_region {
  my $filepath  = shift;
  my $timestamp = shift;
  my %args      = %{ shift() };

  #check if the data is new enough
  my $last_update = rrd_last_update($filepath);
  unless ( $timestamp > $$last_update ) {
    return 0;
  }

  my $instances_running = exists $args{instances_running} ? $args{instances_running} : "U";
  my $instances_stopped = exists $args{instances_stopped} ? $args{instances_stopped} : "U";

  my $values = join ":", ( $instances_running, $instances_stopped );

  RRDp::cmd qq(update "$filepath" $timestamp:$values);
  my $answer;
  eval { $answer = RRDp::read; };

  if ($@) {
    warn( localtime() . ": Failed during read last time $filepath: $@ " . __FILE__ . ":" . __LINE__ );
    return 1;
  }

  return 0;
}

sub update_rrd_ec2 {
  my $filepath  = shift;
  my $timestamp = shift;
  my %args      = %{ shift() };

  # check if the data is new enough
  my $last_update = rrd_last_update($filepath);
  unless ( $timestamp > $$last_update ) {
    return 0;
  }

  my $cpu_percent      = exists $args{cpu_usage_percent} && defined $args{cpu_usage_percent}                     ? $args{cpu_usage_percent} / 100                        : "U";
  my $cpu_cores        = exists $args{cpu_cores} && defined $args{cpu_usage_percent} && defined $args{cpu_cores} ? $args{cpu_cores} * ( $args{cpu_usage_percent} / 100 ) : "U";
  my $cpu_cores_count  = exists $args{cpu_cores}                                                                 ? $args{cpu_cores}                                      : "U";
  my $memory_total     = exists $args{memory_total_mb}                                                           ? $args{memory_total_mb}                                : "U";
  my $memory_free      = exists $args{memory_free_mb}                                                            ? $args{memory_free_mb}                                 : "U";
  my $disk_read_ops    = exists $args{disk_read_ops} && defined $args{disk_read_ops}                             ? $args{disk_read_ops} / 300                            : "U";
  my $disk_write_ops   = exists $args{disk_write_ops} && defined $args{disk_write_ops}                           ? $args{disk_write_ops} / 300                           : "U";
  my $disk_read_bytes  = exists $args{disk_read_bytes} && defined $args{disk_read_bytes}                         ? $args{disk_read_bytes} / 300                          : "U";
  my $disk_write_bytes = exists $args{disk_write_bytes} && defined $args{disk_write_bytes}                       ? $args{disk_write_bytes} / 300                         : "U";
  my $network_in       = exists $args{network_in} && defined $args{network_in}                                   ? $args{network_in} / 300                               : "U";
  my $network_out      = exists $args{network_out} && defined $args{network_out}                                 ? $args{network_out} / 300                              : "U";

  my $values = join ":", ( $cpu_percent, $cpu_cores, $cpu_cores_count, $memory_total, $memory_free, $disk_read_ops, $disk_write_ops, $disk_read_bytes, $disk_write_bytes, $network_in, $network_out );

  RRDp::cmd qq(update "$filepath" $timestamp:$values);
  my $answer;
  eval { $answer = RRDp::read; };

  if ($@) {
    warn( localtime() . ": Failed during read last time $filepath: $@ " . __FILE__ . ":" . __LINE__ );
    return 1;
  }

  return 0;
}

sub update_rrd_volume {
  my $filepath  = shift;
  my $timestamp = shift;
  my %args      = %{ shift() };

  # check if the data is new enough
  my $last_update = rrd_last_update($filepath);
  unless ( $timestamp > $$last_update ) {
    return 0;
  }

  my $disk_read_ops    = exists $args{disk_read_ops}    && defined $args{disk_read_ops}    ? $args{disk_read_ops}    : "U";
  my $disk_write_ops   = exists $args{disk_write_ops}   && defined $args{disk_write_ops}   ? $args{disk_write_ops}   : "U";
  my $disk_read_bytes  = exists $args{disk_read_bytes}  && defined $args{disk_read_bytes}  ? $args{disk_read_bytes}  : "U";
  my $disk_write_bytes = exists $args{disk_write_bytes} && defined $args{disk_write_bytes} ? $args{disk_write_bytes} : "U";

  my $values = join ":", ( $disk_read_ops, $disk_write_ops, $disk_read_bytes, $disk_write_bytes );

  RRDp::cmd qq(update "$filepath" $timestamp:$values);
  my $answer;
  eval { $answer = RRDp::read; };

  if ($@) {
    warn( localtime() . ": Failed during read last time $filepath: $@ " . __FILE__ . ":" . __LINE__ );
    return 1;
  }

  return 0;
}

sub update_rrd_s3 {
  my $filepath  = shift;
  my $timestamp = shift;
  my %args      = %{ shift() };

  # check if the data is new enough
  my $last_update = rrd_last_update($filepath);
  unless ( $timestamp > $$last_update ) {
    return 0;
  }

  my $number_objects = exists $args{number_objects} ? $args{number_objects} : "U";
  my $bucket_size    = exists $args{bucket_size}    ? $args{bucket_size}    : "U";

  my $values = join ":", ( $number_objects, $bucket_size );

  RRDp::cmd qq(update "$filepath" $timestamp:$values);
  my $answer;
  eval { $answer = RRDp::read; };

  if ($@) {
    warn( localtime() . ": Failed during read last time $filepath: $@ " . __FILE__ . ":" . __LINE__ );
    return 1;
  }

  return 0;
}

sub update_rrd_api {
  my $filepath  = shift;
  my $timestamp = shift;
  my %args      = %{ shift() };

  # check if the data is new enough
  my $last_update = rrd_last_update($filepath);
  unless ( $timestamp > $$last_update ) {
    return 0;
  }

  my $count               = exists $args{count}               && defined $args{count}               ? $args{count}               : "U";
  my $latency             = exists $args{latency}             && defined $args{latency}             ? $args{latency}             : "U";
  my $five_error          = exists $args{five_error}          && defined $args{five_error}          ? $args{five_error}          : "U";
  my $four_error          = exists $args{four_error}          && defined $args{four_error}          ? $args{four_error}          : "U";
  my $integration_latency = exists $args{integration_latency} && defined $args{integration_latency} ? $args{integration_latency} : "U";

  my $values = join ":", ( $count, $latency, $five_error, $four_error, $integration_latency );

  RRDp::cmd qq(update "$filepath" $timestamp:$values);
  my $answer;
  eval { $answer = RRDp::read; };

  if ($@) {
    warn( localtime() . ": Failed during read last time $filepath: $@ " . __FILE__ . ":" . __LINE__ );
    return 1;
  }

  return 0;
}

sub update_rrd_lambda {
  my $filepath  = shift;
  my $timestamp = shift;
  my %args      = %{ shift() };

  # check if the data is new enough
  my $last_update = rrd_last_update($filepath);
  unless ( $timestamp > $$last_update ) {
    return 0;
  }

  my $invocations           = exists $args{invocations}           && defined $args{invocations}           ? $args{invocations}           : "U";
  my $errors                = exists $args{errors}                && defined $args{errors}                ? $args{errors}                : "U";
  my $duration              = exists $args{duration}              && defined $args{duration}              ? $args{duration}              : "U";
  my $throttles             = exists $args{throttles}             && defined $args{throttles}             ? $args{throttles}             : "U";
  my $concurrent_executions = exists $args{concurrent_executions} && defined $args{concurrent_executions} ? $args{concurrent_executions} : "U";

  my $values = join ":", ( $invocations, $errors, $duration, $throttles, $concurrent_executions );

  RRDp::cmd qq(update "$filepath" $timestamp:$values);
  my $answer;
  eval { $answer = RRDp::read; };

  if ($@) {
    warn( localtime() . ": Failed during read last time $filepath: $@ " . __FILE__ . ":" . __LINE__ );
    return 1;
  }

  return 0;
}

sub update_rrd_rds {
  my $filepath  = shift;
  my $timestamp = shift;
  my %args      = %{ shift() };

  # check if the data is new enough
  my $last_update = rrd_last_update($filepath);
  unless ( $timestamp > $$last_update ) {
    return 0;
  }

  my $cpu_percent        = exists $args{cpu_usage_percent}  && defined $args{cpu_usage_percent}  ? $args{cpu_usage_percent} / 100 : "U";
  my $disk_read_ops      = exists $args{disk_read_ops}      && defined $args{disk_read_ops}      ? $args{disk_read_ops}           : "U";
  my $disk_write_ops     = exists $args{disk_write_ops}     && defined $args{disk_write_ops}     ? $args{disk_write_ops}          : "U";
  my $disk_read_bytes    = exists $args{disk_read_bytes}    && defined $args{disk_read_bytes}    ? $args{disk_read_bytes}         : "U";
  my $disk_write_bytes   = exists $args{disk_write_bytes}   && defined $args{disk_write_bytes}   ? $args{disk_write_bytes}        : "U";
  my $network_in         = exists $args{network_in}         && defined $args{network_in}         ? $args{network_in}              : "U";
  my $network_out        = exists $args{network_out}        && defined $args{network_out}        ? $args{network_out}             : "U";
  my $disk_read_latency  = exists $args{disk_read_latency}  && defined $args{disk_read_latency}  ? $args{disk_read_latency}       : "U";
  my $disk_write_latency = exists $args{disk_write_latency} && defined $args{disk_write_latency} ? $args{disk_write_latency}      : "U";
  my $disk_free          = exists $args{disk_free}          && defined $args{disk_free}          ? $args{disk_free}               : "U";
  my $mem_free           = exists $args{mem_free}           && defined $args{mem_free}           ? $args{mem_free}                : "U";
  my $db_connection      = exists $args{db_connection}      && defined $args{db_connection}      ? $args{db_connection}           : "U";
  my $burst_balance      = exists $args{burst_balance}      && defined $args{burst_balance}      ? $args{burst_balance}           : "U";

  my $values = join ":", ( $cpu_percent, $disk_read_ops, $disk_write_ops, $disk_read_bytes, $disk_write_bytes, $disk_read_latency, $disk_write_latency, $mem_free, $disk_free, $db_connection, $burst_balance, $network_in, $network_out );

  RRDp::cmd qq(update "$filepath" $timestamp:$values);
  my $answer;
  eval { $answer = RRDp::read; };

  if ($@) {
    warn( localtime() . ": Failed during read last time $filepath: $@ " . __FILE__ . ":" . __LINE__ );
    return 1;
  }

  return 0;
}

################################################################################

sub create_rrd_region {
  my $filepath   = shift;
  my $start_time = shift;

  touch("create_rrd_region $filepath");

  RRDp::cmd qq(create "$filepath" --start "$start_time" --step "$step"
        "DS:instances_running:GAUGE:$no_time_twenty:0:U"
        "DS:instances_stopped:GAUGE:$no_time_twenty:0:U"
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

sub create_rrd_ec2 {
  my $filepath   = shift;
  my $start_time = shift;

  touch("create_rrd_ec2 $filepath");

  RRDp::cmd qq(create "$filepath" --start "$start_time" --step "$step"
        "DS:cpu_percent:GAUGE:$no_time:0:1"
        "DS:cpu_cores:GAUGE:$no_time:0:U"
        "DS:cpu_core_count:GAUGE:$no_time:0:U"
        "DS:memory_total:GAUGE:$no_time:0:U"
        "DS:memory_free:GAUGE:$no_time:0:U"
        "DS:disk_read_ops:GAUGE:$no_time:0:U"
        "DS:disk_write_ops:GAUGE:$no_time:0:U"
        "DS:disk_read_bytes:GAUGE:$no_time:0:U"
        "DS:disk_write_bytes:GAUGE:$no_time:0:U"
        "DS:network_in:GAUGE:$no_time:0:U"
        "DS:network_out:GAUGE:$no_time:0:U"
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

sub create_rrd_volume {
  my $filepath   = shift;
  my $start_time = shift;

  touch("create_rrd_volume $filepath");

  RRDp::cmd qq(create "$filepath" --start "$start_time" --step "$step"
        "DS:disk_read_ops:GAUGE:$no_time:0:U"
        "DS:disk_write_ops:GAUGE:$no_time:0:U"
        "DS:disk_read_bytes:GAUGE:$no_time:0:U"
        "DS:disk_write_bytes:GAUGE:$no_time:0:U"
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

sub create_rrd_s3 {
  my $filepath   = shift;
  my $start_time = shift;

  touch("create_rrd_s3 $filepath");

  RRDp::cmd qq(create "$filepath" --start "$start_time" --step "$step"
        "DS:number_objects:GAUGE:$no_time:0:U"
        "DS:bucket_size:GAUGE:$no_time:0:U"
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

sub create_rrd_api {
  my $filepath   = shift;
  my $start_time = shift;

  touch("create_rrd_api $filepath");

  RRDp::cmd qq(create "$filepath" --start "$start_time" --step "$step"
        "DS:count:GAUGE:$no_time:0:U"
        "DS:latency:GAUGE:$no_time:0:U"
	"DS:5xx_error:GAUGE:$no_time:0:U"
	"DS:4xx_error:GAUGE:$no_time:0:U"
	"DS:integration_latency:GAUGE:$no_time:0:U"
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

sub create_rrd_lambda {
  my $filepath   = shift;
  my $start_time = shift;

  touch("create_rrd_lambda $filepath");

  RRDp::cmd qq(create "$filepath" --start "$start_time" --step "$step"
        "DS:invocations:GAUGE:$no_time:0:U"
        "DS:errors:GAUGE:$no_time:0:U"
	"DS:duration:GAUGE:$no_time:0:U"
	"DS:throttles:GAUGE:$no_time:0:U"
	"DS:concurrent:GAUGE:$no_time:0:U"
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

sub create_rrd_rds {
  my $filepath   = shift;
  my $start_time = shift;

  touch("create_rds_volume $filepath");

  RRDp::cmd qq(create "$filepath" --start "$start_time" --step "$step"
        "DS:cpu_percent:GAUGE:$no_time:0:1"
        "DS:disk_read_ops:GAUGE:$no_time:0:U"
        "DS:disk_write_ops:GAUGE:$no_time:0:U"
        "DS:disk_read_bytes:GAUGE:$no_time:0:U"
        "DS:disk_write_bytes:GAUGE:$no_time:0:U"
	"DS:disk_read_latency:GAUGE:$no_time:0:U"
        "DS:disk_write_latency:GAUGE:$no_time:0:U"
	"DS:mem_free:GAUGE:$no_time:0:U"
	"DS:disk_free:GAUGE:$no_time:0:U"
	"DS:db_connection:GAUGE:$no_time:0:U"
	"DS:burst_balance:GAUGE:$no_time:0:U"
	"DS:network_in:GAUGE:$no_time:0:U"
        "DS:network_out:GAUGE:$no_time:0:U"
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
  my $new_change = "$basedir/tmp/$version-aws";
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
