# CloudstackLoadDataModule.pm
# create/update RRDs with Cloudstack metrics

package CloudstackLoadDataModule;

use strict;
use warnings;

use Data::Dumper;
use Date::Parse;
use RRDp;
use File::Copy qw(copy);
use Xorux_lib;
use Math::BigInt;
use POSIX;

use CloudstackDataWrapper;

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

sub update_rrd_host {
  my $filepath  = shift;
  my $timestamp = shift;
  my %args      = %{ shift() };

  #check if the data is new enough
  my $last_update = rrd_last_update($filepath);
  unless ( $timestamp > $$last_update ) {
    return 0;
  }

  my $cpuusedghz      = exists $args{cpuusedghz}      && defined $args{cpuusedghz}      ? $args{cpuusedghz}      : "U";
  my $cputotalghz     = exists $args{cputotalghz}     && defined $args{cputotalghz}     ? $args{cputotalghz}     : "U";
  my $cpuused         = exists $args{cpuused}         && defined $args{cpuused}         ? $args{cpuused}         : "U";
  my $cpunumber       = exists $args{cpunumber}       && defined $args{cpunumber}       ? $args{cpunumber}       : "U";
  my $memoryused      = exists $args{memoryused}      && defined $args{memoryused}      ? $args{memoryused}      : "U";
  my $memoryallocated = exists $args{memoryallocated} && defined $args{memoryallocated} ? $args{memoryallocated} : "U";
  my $memorytotal     = exists $args{memorytotal}     && defined $args{memorytotal}     ? $args{memorytotal}     : "U";
  my $networkkbswrite = exists $args{networkkbswrite} && defined $args{networkkbswrite} ? $args{networkkbswrite} : "U";
  my $networkkbsread  = exists $args{networkkbsread}  && defined $args{networkkbsread}  ? $args{networkkbsread}  : "U";

  my $values = join ":", ( $cpuusedghz, $cputotalghz, $cpuused, $cpunumber, $memoryused, $memoryallocated, $memorytotal, $networkkbswrite, $networkkbsread );

  RRDp::cmd qq(update "$filepath" $timestamp:$values);
  eval { my $answer = RRDp::read; };

  if ($@) {
    warn( localtime() . ": Failed during read last time $filepath: $@ " . __FILE__ . ":" . __LINE__ );
    return 1;
  }

  return 0;
}

sub update_rrd_instance {
  my $filepath  = shift;
  my $timestamp = shift;
  my %args      = %{ shift() };

  #check if the data is new enough
  my $last_update = rrd_last_update($filepath);
  unless ( $timestamp > $$last_update ) {
    return 0;
  }

  my $cpuused          = exists $args{cpuused}          && defined $args{cpuused}          ? $args{cpuused}          : "U";
  my $cpuspeed         = exists $args{cpuspeed}         && defined $args{cpuspeed}         ? $args{cpuspeed}         : "U";
  my $memoryintfreekbs = exists $args{memoryintfreekbs} && defined $args{memoryintfreekbs} ? $args{memoryintfreekbs} : "U";
  my $memory           = exists $args{memory}           && defined $args{memory}           ? $args{memory}           : "U";
  my $diskkbswrite     = exists $args{diskkbswrite}     && defined $args{diskkbswrite}     ? $args{diskkbswrite}     : "U";
  my $diskkbsread      = exists $args{diskkbsread}      && defined $args{diskkbsread}      ? $args{diskkbsread}      : "U";
  my $diskiopstotal    = exists $args{diskiopstotal}    && defined $args{diskiopstotal}    ? $args{diskiopstotal}    : "U";
  my $diskiowrite      = exists $args{diskiowrite}      && defined $args{diskiowrite}      ? $args{diskiowrite}      : "U";
  my $diskioread       = exists $args{diskioread}       && defined $args{diskioread}       ? $args{diskioread}       : "U";
  my $networkread      = exists $args{networkread}      && defined $args{networkread}      ? $args{networkread}      : "U";
  my $networkwrite     = exists $args{networkwrite}     && defined $args{networkwrite}     ? $args{networkwrite}     : "U";
  my $networkkbswrite  = exists $args{networkkbswrite}  && defined $args{networkkbswrite}  ? $args{networkkbswrite}  : "U";
  my $networkkbsread   = exists $args{networkkbsread}   && defined $args{networkkbsread}   ? $args{networkkbsread}   : "U";

  my $values = join ":", ( $cpuused, $cpuspeed, $memoryintfreekbs, $memory, $diskkbswrite, $diskkbsread, $diskiopstotal, $diskiowrite, $diskioread, $networkread, $networkwrite, $networkkbswrite, $networkkbsread );

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

  my $utilization   = exists $args{utilization}   && defined $args{utilization}   ? $args{utilization}   : "U";
  my $physicalsize  = exists $args{physicalsize}  && defined $args{physicalsize}  ? $args{physicalsize}  : "U";
  my $size          = exists $args{size}          && defined $args{size}          ? $args{size}          : "U";
  my $virtualsize   = exists $args{virtualsize}   && defined $args{virtualsize}   ? $args{virtualsize}   : "U";
  my $diskiowrite   = exists $args{diskiowrite}   && defined $args{diskiowrite}   ? $args{diskiowrite}   : "U";
  my $diskioread    = exists $args{diskioread}    && defined $args{diskioread}    ? $args{diskioread}    : "U";
  my $diskiopstotal = exists $args{diskiopstotal} && defined $args{diskiopstotal} ? $args{diskiopstotal} : "U";
  my $diskkbswrite  = exists $args{diskkbswrite}  && defined $args{diskkbswrite}  ? $args{diskkbswrite}  : "U";
  my $diskkbsread   = exists $args{diskkbsread}   && defined $args{diskkbsread}   ? $args{diskkbsread}   : "U";

  my $values = join ":", ( $utilization, $physicalsize, $size, $virtualsize, $diskiowrite, $diskioread, $diskiopstotal, $diskkbswrite, $diskkbsread );

  RRDp::cmd qq(update "$filepath" $timestamp:$values);
  eval { my $answer = RRDp::read; };

  if ($@) {
    warn( localtime() . ": Failed during read last time $filepath: $@ " . __FILE__ . ":" . __LINE__ );
    return 1;
  }

  return 0;
}

sub update_rrd_primaryStorage {
  my $filepath  = shift;
  my $timestamp = shift;
  my %args      = %{ shift() };

  #check if the data is new enough
  my $last_update = rrd_last_update($filepath);
  unless ( $timestamp > $$last_update ) {
    return 0;
  }

  my $disksizetotal       = exists $args{disksizetotalgb}       && defined $args{disksizetotalgb}       ? $args{disksizetotalgb}       : "U";
  my $disksizeused        = exists $args{disksizeusedgb}        && defined $args{disksizeusedgb}        ? $args{disksizeusedgb}        : "U";
  my $disksizeallocated   = exists $args{disksizeallocatedgb}   && defined $args{disksizeallocatedgb}   ? $args{disksizeallocatedgb}   : "U";
  my $disksizeunallocated = exists $args{disksizeunallocatedgb} && defined $args{disksizeunallocatedgb} ? $args{disksizeunallocatedgb} : "U";
  my $overprovisioning    = exists $args{overprovisioning}      && defined $args{overprovisioning}      ? $args{overprovisioning}      : "U";

  my $values = join ":", ( $disksizetotal, $disksizeused, $disksizeallocated, $disksizeunallocated, $overprovisioning );

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
        "DS:cpuusedghz:GAUGE:$no_time:0:U"
        "DS:cputotalghz:GAUGE:$no_time:0:U"
	"DS:cpuused:GAUGE:$no_time:0:U"
	"DS:cpunumber:GAUGE:$no_time:0:U"
        "DS:memoryused:GAUGE:$no_time:0:U"
        "DS:memoryallocated:GAUGE:$no_time:0:U"
        "DS:memorytotal:GAUGE:$no_time:0:U"
        "DS:networkkbswrite:COUNTER:$no_time:0:U"
        "DS:networkkbsread:COUNTER:$no_time:0:U"
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

sub create_rrd_instance {
  my $filepath   = shift;
  my $start_time = shift;

  touch("create_rrd_instance $filepath");

  RRDp::cmd qq(create "$filepath" --start "$start_time" --step "$step"
        "DS:cpuused:GAUGE:$no_time:0:U"
        "DS:cpuspeed:GAUGE:$no_time:0:U"
        "DS:memoryintfreekbs:GAUGE:$no_time:0:U"
        "DS:memory:GAUGE:$no_time:0:U"
        "DS:diskkbswrite:COUNTER:$no_time:0:U"
        "DS:diskkbsread:COUNTER:$no_time:0:U"
        "DS:diskiopstotal:COUNTER:$no_time:0:U"
        "DS:diskiowrite:COUNTER:$no_time:0:U"
        "DS:diskioread:COUNTER:$no_time:0:U"
        "DS:networkread:COUNTER:$no_time:0:U"
        "DS:networkwrite:COUNTER:$no_time:0:U"
	"DS:networkkbswrite:COUNTER:$no_time:0:U"
        "DS:networkkbsread:COUNTER:$no_time:0:U"
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
        "DS:utilization:GAUGE:$no_time:0:U"
        "DS:physicalsize:GAUGE:$no_time:0:U"
        "DS:size:GAUGE:$no_time:0:U"
        "DS:virtualsize:GAUGE:$no_time:0:U"
        "DS:diskiowrite:COUNTER:$no_time:0:U"
        "DS:diskioread:COUNTER:$no_time:0:U"
        "DS:diskiopstotal:COUNTER:$no_time:0:U"
        "DS:diskkbswrite:COUNTER:$no_time:0:U"
        "DS:diskkbsread:COUNTER:$no_time:0:U"
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

sub create_rrd_primaryStorage {
  my $filepath   = shift;
  my $start_time = shift;

  touch("create_rrd_primaryStorage $filepath");

  RRDp::cmd qq(create "$filepath" --start "$start_time" --step "$step"
        "DS:disksizetotal:GAUGE:$no_time:0:U"
        "DS:disksizeused:GAUGE:$no_time:0:U"
        "DS:disksizeallocated:GAUGE:$no_time:0:U"
        "DS:disksizeunallocated:GAUGE:$no_time:0:U"
        "DS:overprovisioning:GAUGE:$no_time:0:U"
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
