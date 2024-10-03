# AzureLoadDataModule.pm
# create/update RRDs with Azure metrics

package AzureLoadDataModule;

use strict;
use warnings;

use Data::Dumper;
use Date::Parse;
use RRDp;
use File::Copy qw(copy);
use Xorux_lib;
use Math::BigInt;
use POSIX;

use AzureDataWrapper;

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

sub update_rrd_vm {
  my $filepath  = shift;
  my $timestamp = shift;
  my %args      = %{ shift() };

  #check if the data is new enough
  my $last_update = rrd_last_update($filepath);
  unless ( $timestamp > $$last_update ) {
    return 0;
  }

  my $cpu_percent      = exists $args{cpu_usage_percent} && defined $args{cpu_usage_percent} ? $args{cpu_usage_percent} / 100 : "U";
  my $disk_read_ops    = exists $args{disk_read_ops}     && defined $args{disk_read_ops}     ? $args{disk_read_ops}           : "U";
  my $disk_write_ops   = exists $args{disk_write_ops}    && defined $args{disk_write_ops}    ? $args{disk_write_ops}          : "U";
  my $disk_read_bytes  = exists $args{disk_read_bytes}   && defined $args{disk_read_bytes}   ? $args{disk_read_bytes}         : "U";
  my $disk_write_bytes = exists $args{disk_write_bytes}  && defined $args{disk_write_bytes}  ? $args{disk_write_bytes}        : "U";
  my $network_in       = exists $args{network_in}        && defined $args{network_in}        ? $args{network_in}              : "U";
  my $network_out      = exists $args{network_out}       && defined $args{network_out}       ? $args{network_out}             : "U";
  my $mem_free         = exists $args{mem_free}          && defined $args{mem_free}          ? $args{mem_free}                : "U";
  my $mem_used         = exists $args{mem_used}          && defined $args{mem_used}          ? $args{mem_used}                : "U";

  my $values = join ":", ( $cpu_percent, $disk_read_ops, $disk_write_ops, $disk_read_bytes, $disk_write_bytes, $network_in, $network_out, $mem_free, $mem_used );

  RRDp::cmd qq(update "$filepath" $timestamp:$values);
  eval { my $answer = RRDp::read; };

  if ($@) {
    warn( localtime() . ": Failed during read last time $filepath: $@ " . __FILE__ . ":" . __LINE__ );
    return 1;
  }

  return 0;
}

sub update_rrd_app {
  my $filepath  = shift;
  my $timestamp = shift;
  my %args      = %{ shift() };

  #check if the data is new enough
  my $last_update = rrd_last_update($filepath);
  unless ( $timestamp > $$last_update ) {
    return 0;
  }

  my $cpu_time         = exists $args{cpu_time}         && defined $args{cpu_time}         ? $args{cpu_time}         : "U";
  my $requests         = exists $args{requests}         && defined $args{requests}         ? $args{requests}         : "U";
  my $read_bytes       = exists $args{read_bytes}       && defined $args{read_bytes}       ? $args{read_bytes}       : "U";
  my $write_bytes      = exists $args{write_bytes}      && defined $args{write_bytes}      ? $args{write_bytes}      : "U";
  my $read_ops         = exists $args{read_ops}         && defined $args{read_ops}         ? $args{read_ops}         : "U";
  my $write_ops        = exists $args{write_ops}        && defined $args{write_ops}        ? $args{write_ops}        : "U";
  my $received_bytes   = exists $args{received_bytes}   && defined $args{received_bytes}   ? $args{received_bytes}   : "U";
  my $sent_bytes       = exists $args{sent_bytes}       && defined $args{sent_bytes}       ? $args{sent_bytes}       : "U";
  my $http_2xx         = exists $args{http_2xx}         && defined $args{http_2xx}         ? $args{http_2xx}         : "U";
  my $http_3xx         = exists $args{http_3xx}         && defined $args{http_3xx}         ? $args{http_3xx}         : "U";
  my $http_4xx         = exists $args{http_4xx}         && defined $args{http_4xx}         ? $args{http_4xx}         : "U";
  my $http_5xx         = exists $args{http_5xx}         && defined $args{http_5xx}         ? $args{http_5xx}         : "U";
  my $response         = exists $args{response}         && defined $args{response}         ? $args{response}         : "U";
  my $connections      = exists $args{connections}      && defined $args{connections}      ? $args{connections}      : "U";
  my $filesystem_usage = exists $args{filesystem_usage} && defined $args{filesystem_usage} ? $args{filesystem_usage} : "U";

  my $values = join ":", ( $cpu_time, $requests, $read_ops, $write_ops, $read_bytes, $write_bytes, $received_bytes, $sent_bytes, $http_2xx, $http_3xx, $http_4xx, $http_5xx, $response, $connections, $filesystem_usage );

  RRDp::cmd qq(update "$filepath" $timestamp:$values);
  eval { my $answer = RRDp::read; };

  if ($@) {
    warn( localtime() . ": Failed during read last time $filepath: $@ " . __FILE__ . ":" . __LINE__ );
    return 1;
  }

  return 0;
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
  eval { my $answer = RRDp::read; };

  if ($@) {
    warn( localtime() . ": Failed during read last time $filepath: $@ " . __FILE__ . ":" . __LINE__ );
    return 1;
  }

  return 0;
}

################################################################################

sub create_rrd_vm {
  my $filepath   = shift;
  my $start_time = shift;

  touch("create_rrd_compute $filepath");

  RRDp::cmd qq(create "$filepath" --start "$start_time" --step "$step"
        "DS:cpu_percent:GAUGE:$no_time:0:U"
        "DS:disk_read_ops:GAUGE:$no_time:0:U"
        "DS:disk_write_ops:GAUGE:$no_time:0:U"
        "DS:disk_read_bytes:GAUGE:$no_time:0:U"
        "DS:disk_write_bytes:GAUGE:$no_time:0:U"
        "DS:network_in:GAUGE:$no_time:0:U"
        "DS:network_out:GAUGE:$no_time:0:U"
	"DS:mem_free:GAUGE:$no_time:0:U"
	"DS:mem_used:GAUGE:$no_time:0:U"
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

sub create_rrd_app {
  my $filepath   = shift;
  my $start_time = shift;

  touch("create_rrd_app $filepath");

  RRDp::cmd qq(create "$filepath" --start "$start_time" --step "$step"
        "DS:cpu_time:GAUGE:$no_time:0:U"
        "DS:requests:GAUGE:$no_time:0:U"
        "DS:read_bytes:GAUGE:$no_time:0:U"
        "DS:write_bytes:GAUGE:$no_time:0:U"
        "DS:read_ops:GAUGE:$no_time:0:U"
        "DS:write_ops:GAUGE:$no_time:0:U"
        "DS:received_bytes:GAUGE:$no_time:0:U"
        "DS:sent_bytes:GAUGE:$no_time:0:U"
        "DS:http_2xx:GAUGE:$no_time:0:U"
	"DS:http_3xx:GAUGE:$no_time:0:U"
	"DS:http_4xx:GAUGE:$no_time:0:U"
	"DS:http_5xx:GAUGE:$no_time:0:U"
	"DS:response:GAUGE:$no_time:0:U"
	"DS:connections:GAUGE:$no_time:0:U"
	"DS:filesystem_usage:GAUGE:$no_time:0:U"
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
