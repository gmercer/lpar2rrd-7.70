# DockerLoadDataModule.pm
# create/update RRDs with Docker metrics

package DockerLoadDataModule;

use strict;
use warnings;

use Data::Dumper;
use Date::Parse;
use RRDp;
use File::Copy qw(copy);
use Xorux_lib;
use Math::BigInt;
use POSIX;

use ProxmoxDataWrapper;

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

sub update_rrd_container {
  my $filepath  = shift;
  my $timestamp = shift;
  my %args      = %{ shift() };

  #check if the data is new enough
  my $last_update = rrd_last_update($filepath);
  unless ( $timestamp > $$last_update ) {
    return 0;
  }

  my $cpu_number       = exists $args{cpu_number}       && defined $args{cpu_number}       ? $args{cpu_number}       : "U";
  my $cpu_usage        = exists $args{cpu_usage}        && defined $args{cpu_usage}        ? $args{cpu_usage}        : "U";
  my $memory_used      = exists $args{memory_used}      && defined $args{memory_used}      ? $args{memory_used}      : "U";
  my $memory_available = exists $args{memory_available} && defined $args{memory_available} ? $args{memory_available} : "U";
  my $memory_free      = exists $args{memory_free}      && defined $args{memory_free}      ? $args{memory_free}      : "U";
  my $memory_usage     = exists $args{memory_usage}     && defined $args{memory_usage}     ? $args{memory_usage}     : "U";
  my $read_bytes       = exists $args{read_bytes}       && defined $args{read_bytes}       ? $args{read_bytes}       : "U";
  my $write_bytes      = exists $args{write_bytes}      && defined $args{write_bytes}      ? $args{write_bytes}      : "U";
  my $read_io          = exists $args{read_io}          && defined $args{read_io}          ? $args{read_io}          : "U";
  my $write_io         = exists $args{write_io}         && defined $args{write_io}         ? $args{write_io}         : "U";
  my $rx_bytes         = exists $args{rx_bytes}         && defined $args{rx_bytes}         ? $args{rx_bytes}         : "U";
  my $tx_bytes         = exists $args{tx_bytes}         && defined $args{tx_bytes}         ? $args{tx_bytes}         : "U";
  my $size_rw          = exists $args{size_rw}          && defined $args{size_rw}          ? $args{size_rw}          : "U";
  my $size_root_fs     = exists $args{size_root_fs}     && defined $args{size_root_fs}     ? $args{size_root_fs}     : "U";

  my $values = join ":", ( $cpu_number, $cpu_usage, $memory_used, $memory_available, $memory_free, $memory_usage, $read_bytes, $write_bytes, $read_io, $write_io, $rx_bytes, $tx_bytes, $size_rw, $size_root_fs );

  RRDp::cmd qq(update "$filepath" $timestamp:$values);
  eval { my $answer = RRDp::read; };

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

  #check if the data is new enough
  my $last_update = rrd_last_update($filepath);
  unless ( $timestamp > $$last_update ) {
    return 0;
  }

  my $size = exists $args{size} && defined $args{size} ? $args{size} : "U";

  my $values = join ":", ($size);

  RRDp::cmd qq(update "$filepath" $timestamp:$values);
  eval { my $answer = RRDp::read; };

  if ($@) {
    warn( localtime() . ": Failed during read last time $filepath: $@ " . __FILE__ . ":" . __LINE__ );
    return 1;
  }

  return 0;
}

################################################################################

sub create_rrd_container {
  my $filepath   = shift;
  my $start_time = shift;

  touch("create_rrd_container $filepath");

  RRDp::cmd qq(create "$filepath" --start "$start_time" --step "$step"
        "DS:cpu_number:GAUGE:$no_time:0:U"
        "DS:cpu_usage:GAUGE:$no_time:0:U"
	"DS:memory_used:GAUGE:$no_time:0:U"
	"DS:memory_available:GAUGE:$no_time:0:U"
        "DS:memory_free:GAUGE:$no_time:0:U"
        "DS:memory_usage:GAUGE:$no_time:0:U"
        "DS:read_bytes:GAUGE:$no_time:0:U"
        "DS:write_bytes:GAUGE:$no_time:0:U"
        "DS:read_io:GAUGE:$no_time:0:U"
	"DS:write_io:GAUGE:$no_time:0:U"
	"DS:rx_bytes:GAUGE:$no_time:0:U"
	"DS:tx_bytes:GAUGE:$no_time:0:U"
	"DS:size_rw:GAUGE:$no_time:0:U"
        "DS:size_root_fs:GAUGE:$no_time:0:U"
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
        "DS:size:GAUGE:$no_time:0:U"
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
  my $new_change = "$basedir/tmp/$version-container";
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
