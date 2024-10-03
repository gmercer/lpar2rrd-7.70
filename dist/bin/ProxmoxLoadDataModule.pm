# ProxmoxLoadDataModule.pm
# create/update RRDs with Proxmox metrics

package ProxmoxLoadDataModule;

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

sub update_rrd_node {
  my $filepath  = shift;
  my $timestamp = shift;
  my %args      = %{ shift() };

  #check if the data is new enough
  my $last_update = rrd_last_update($filepath);
  unless ( $timestamp > $$last_update ) {
    return 0;
  }

  my $cpu       = exists $args{cpu}       && defined $args{cpu}       ? $args{cpu}       : "U";
  my $loadavg   = exists $args{loadavg}   && defined $args{loadavg}   ? $args{loadavg}   : "U";
  my $maxcpu    = exists $args{maxcpu}    && defined $args{maxcpu}    ? $args{maxcpu}    : "U";
  my $memused   = exists $args{memused}   && defined $args{memused}   ? $args{memused}   : "U";
  my $memtotal  = exists $args{memtotal}  && defined $args{memtotal}  ? $args{memtotal}  : "U";
  my $iowait    = exists $args{iowait}    && defined $args{iowait}    ? $args{iowait}    : "U";
  my $swapused  = exists $args{swapused}  && defined $args{swapused}  ? $args{swapused}  : "U";
  my $swaptotal = exists $args{swaptotal} && defined $args{swaptotal} ? $args{swaptotal} : "U";
  my $netin     = exists $args{netin}     && defined $args{netin}     ? $args{netin}     : "U";
  my $netout    = exists $args{netout}    && defined $args{netout}    ? $args{netout}    : "U";
  my $rootused  = exists $args{rootused}  && defined $args{rootused}  ? $args{rootused}  : "U";
  my $roottotal = exists $args{roottotal} && defined $args{roottotal} ? $args{roottotal} : "U";

  my $values = join ":", ( $cpu, $loadavg, $maxcpu, $memused, $memtotal, $iowait, $swapused, $swaptotal, $netin, $netout, $rootused, $roottotal );

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

  #check if the data is new enough
  my $last_update = rrd_last_update($filepath);
  unless ( $timestamp > $$last_update ) {
    return 0;
  }

  my $cpu       = exists $args{cpu}       && defined $args{cpu}       ? $args{cpu}       : "U";
  my $maxcpu    = exists $args{maxcpu}    && defined $args{maxcpu}    ? $args{maxcpu}    : "U";
  my $mem       = exists $args{mem}       && defined $args{mem}       ? $args{mem}       : "U";
  my $maxmem    = exists $args{maxmem}    && defined $args{maxmem}    ? $args{maxmem}    : "U";
  my $netin     = exists $args{netin}     && defined $args{netin}     ? $args{netin}     : "U";
  my $netout    = exists $args{netout}    && defined $args{netout}    ? $args{netout}    : "U";
  my $diskread  = exists $args{diskread}  && defined $args{diskread}  ? $args{diskread}  : "U";
  my $diskwrite = exists $args{diskwrite} && defined $args{diskwrite} ? $args{diskwrite} : "U";

  my $values = join ":", ( $cpu, $maxcpu, $mem, $maxmem, $netin, $netout, $diskread, $diskwrite );

  RRDp::cmd qq(update "$filepath" $timestamp:$values);
  eval { my $answer = RRDp::read; };

  if ($@) {
    warn( localtime() . ": Failed during read last time $filepath: $@ " . __FILE__ . ":" . __LINE__ );
    return 1;
  }

  return 0;
}

sub update_rrd_storage {
  my $filepath  = shift;
  my $timestamp = shift;
  my %args      = %{ shift() };

  #check if the data is new enough
  my $last_update = rrd_last_update($filepath);
  unless ( $timestamp > $$last_update ) {
    return 0;
  }

  my $used  = exists $args{used}  && defined $args{used}  ? $args{used}  : "U";
  my $total = exists $args{total} && defined $args{total} ? $args{total} : "U";

  my $values = join ":", ( $used, $total );

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
        "DS:loadavg:GAUGE:$no_time:0:U"
	"DS:maxcpu:GAUGE:$no_time:0:U"
	"DS:memused:GAUGE:$no_time:0:U"
        "DS:memtotal:GAUGE:$no_time:0:U"
        "DS:iowait:GAUGE:$no_time:0:U"
        "DS:swapused:GAUGE:$no_time:0:U"
        "DS:swaptotal:GAUGE:$no_time:0:U"
        "DS:netin:GAUGE:$no_time:0:U"
	"DS:netout:GAUGE:$no_time:0:U"
	"DS:rootused:GAUGE:$no_time:0:U"
	"DS:roottotal:GAUGE:$no_time:0:U"
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
        "DS:cpu:GAUGE:$no_time:0:U"
        "DS:maxcpu:GAUGE:$no_time:0:U"
        "DS:mem:GAUGE:$no_time:0:U"
        "DS:maxmem:GAUGE:$no_time:0:U"
        "DS:netin:GAUGE:$no_time:0:U"
        "DS:netout:GAUGE:$no_time:0:U"
        "DS:diskread:GAUGE:$no_time:0:U"
        "DS:diskwrite:GAUGE:$no_time:0:U"
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

sub create_rrd_storage {
  my $filepath   = shift;
  my $start_time = shift;

  touch("create_rrd_storage $filepath");

  RRDp::cmd qq(create "$filepath" --start "$start_time" --step "$step"
        "DS:used:GAUGE:$no_time:0:U"
        "DS:total:GAUGE:$no_time:0:U"
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
  my $new_change = "$basedir/tmp/$version-vm";
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
