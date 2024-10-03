# GCloudLoadDataModule.pm
# create/update RRDs with GCloud metrics

package GCloudLoadDataModule;

use strict;
use warnings;

use Data::Dumper;
use Date::Parse;
use RRDp;
use File::Copy qw(copy);
use Xorux_lib;
use Math::BigInt;
use POSIX;

use GCloudDataWrapper;

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

sub update_rrd_postgres {
  my $filepath  = shift;
  my $timestamp = shift;
  my %args      = %{ shift() };

  #check if the data is new enough
  my $last_update = rrd_last_update($filepath);
  unless ( $timestamp > $$last_update ) {
    return 0;
  }

  my $cpu_percent = exists $args{cpu_util}    && defined $args{cpu_util}    ? $args{cpu_util}         : "U";
  my $read_ops    = exists $args{read_ops}    && defined $args{read_ops}    ? $args{read_ops} / 60    : "U";
  my $write_ops   = exists $args{write_ops}   && defined $args{write_ops}   ? $args{write_ops} / 60   : "U";
  my $network_in  = exists $args{network_in}  && defined $args{network_in}  ? $args{network_in} / 60  : "U";
  my $network_out = exists $args{network_out} && defined $args{network_out} ? $args{network_out} / 60 : "U";
  my $disk_total  = exists $args{disk_quota}  && defined $args{disk_quota}  ? $args{disk_quota}       : "U";
  my $disk_used   = exists $args{disk_used}   && defined $args{disk_used}   ? $args{disk_used}        : "U";
  my $mem_used    = exists $args{mem_used}    && defined $args{mem_used}    ? $args{mem_used}         : "U";
  my $mem_total   = exists $args{mem_total}   && defined $args{mem_total}   ? $args{mem_total}        : "U";

  my $connections       = exists $args{connections}       && defined $args{connections}       ? $args{connections}       : "U";
  my $transaction_count = exists $args{transaction_count} && defined $args{transaction_count} ? $args{transaction_count} : "U";

  my $mem_free = "U";
  if ( $mem_used ne "U" && $mem_total ne "U" ) {
    $mem_free = $mem_total - $mem_used;
  }

  my $disk_free = "U";
  if ( $disk_used ne "U" && $disk_total ne "U" ) {
    $disk_free = $disk_total - $disk_used;
  }

  my $values = join ":", ( $cpu_percent, $read_ops, $write_ops, $network_in, $network_out, $disk_free, $disk_used, $mem_free, $mem_used, $connections, $transaction_count );

  RRDp::cmd qq(update "$filepath" $timestamp:$values);
  eval { my $answer = RRDp::read; };

  if ($@) {
    warn( localtime() . ": Failed during read last time $filepath: $@ " . __FILE__ . ":" . __LINE__ );
    return 1;
  }

  return 0;
}

sub update_rrd_mysql {
  my $filepath  = shift;
  my $timestamp = shift;
  my %args      = %{ shift() };

  #check if the data is new enough
  my $last_update = rrd_last_update($filepath);
  unless ( $timestamp > $$last_update ) {
    return 0;
  }

  my $cpu_percent = exists $args{cpu_util}    && defined $args{cpu_util}    ? $args{cpu_util}         : "U";
  my $read_ops    = exists $args{read_ops}    && defined $args{read_ops}    ? $args{read_ops} / 60    : "U";
  my $write_ops   = exists $args{write_ops}   && defined $args{write_ops}   ? $args{write_ops} / 60   : "U";
  my $network_in  = exists $args{network_in}  && defined $args{network_in}  ? $args{network_in} / 60  : "U";
  my $network_out = exists $args{network_out} && defined $args{network_out} ? $args{network_out} / 60 : "U";
  my $disk_total  = exists $args{disk_quota}  && defined $args{disk_quota}  ? $args{disk_quota}       : "U";
  my $disk_used   = exists $args{disk_used}   && defined $args{disk_used}   ? $args{disk_used}        : "U";
  my $mem_used    = exists $args{mem_used}    && defined $args{mem_used}    ? $args{mem_used}         : "U";
  my $mem_total   = exists $args{mem_total}   && defined $args{mem_total}   ? $args{mem_total}        : "U";

  my $connections = exists $args{connections} && defined $args{connections} ? $args{connections} : "U";
  my $questions   = exists $args{questions}   && defined $args{questions}   ? $args{questions}   : "U";
  my $queries     = exists $args{queries}     && defined $args{queries}     ? $args{queries}     : "U";

  my $innodb_read         = exists $args{innodb_read}         && defined $args{innodb_read}         ? $args{innodb_read}         : "U";
  my $innodb_write        = exists $args{innodb_write}        && defined $args{innodb_write}        ? $args{innodb_write}        : "U";
  my $innodb_buffer_free  = exists $args{innodb_buffer_free}  && defined $args{innodb_buffer_free}  ? $args{innodb_buffer_free}  : "U";
  my $innodb_buffer_total = exists $args{innodb_buffer_total} && defined $args{innodb_buffer_total} ? $args{innodb_buffer_total} : "U";
  my $innodb_os_fsyncs    = exists $args{innodb_os_fsyncs}    && defined $args{innodb_os_fsyncs}    ? $args{innodb_os_fsyncs}    : "U";
  my $innodb_data_fsyncs  = exists $args{innodb_data_fsyncs}  && defined $args{innodb_data_fsyncs}  ? $args{innodb_data_fsyncs}  : "U";

  my $mem_free = "U";
  if ( $mem_used ne "U" && $mem_total ne "U" ) {
    $mem_free = $mem_total - $mem_used;
  }

  my $disk_free = "U";
  if ( $disk_used ne "U" && $disk_total ne "U" ) {
    $disk_free = $disk_total - $disk_used;
  }

  my $values = join ":", ( $cpu_percent, $read_ops, $write_ops, $network_in, $network_out, $disk_free, $disk_used, $mem_free, $mem_used, $connections, $questions, $queries, $innodb_read, $innodb_write, $innodb_buffer_free, $innodb_buffer_total, $innodb_os_fsyncs, $innodb_data_fsyncs );

  RRDp::cmd qq(update "$filepath" $timestamp:$values);
  eval { my $answer = RRDp::read; };

  if ($@) {
    warn( localtime() . ": Failed during read last time $filepath: $@ " . __FILE__ . ":" . __LINE__ );
    return 1;
  }

  return 0;
}

sub update_rrd_compute {
  my $filepath  = shift;
  my $timestamp = shift;
  my %args      = %{ shift() };

  #check if the data is new enough
  my $last_update = rrd_last_update($filepath);
  unless ( $timestamp > $$last_update ) {
    return 0;
  }

  my $cpu_percent      = exists $args{cpu_usage_percent} && defined $args{cpu_usage_percent} ? $args{cpu_usage_percent}     : "U";
  my $disk_read_ops    = exists $args{disk_read_ops}     && defined $args{disk_read_ops}     ? $args{disk_read_ops} / 60    : "U";
  my $disk_write_ops   = exists $args{disk_write_ops}    && defined $args{disk_write_ops}    ? $args{disk_write_ops} / 60   : "U";
  my $disk_read_bytes  = exists $args{disk_read_bytes}   && defined $args{disk_read_bytes}   ? $args{disk_read_bytes} / 60  : "U";
  my $disk_write_bytes = exists $args{disk_write_bytes}  && defined $args{disk_write_bytes}  ? $args{disk_write_bytes} / 60 : "U";
  my $network_in       = exists $args{network_in}        && defined $args{network_in}        ? $args{network_in} / 60       : "U";
  my $network_out      = exists $args{network_out}       && defined $args{network_out}       ? $args{network_out} / 60      : "U";

  #agent metrics
  my $mem_used    = exists $args{mem_used}    && defined $args{mem_used}    ? $args{mem_used}    : "U";
  my $mem_usage   = exists $args{mem_usage}   && defined $args{mem_usage}   ? $args{mem_usage}   : "U";
  my $process_run = exists $args{process_run} && defined $args{process_run} ? $args{process_run} : "U";
  my $process_pag = exists $args{process_pag} && defined $args{process_pag} ? $args{process_pag} : "U";
  my $process_sto = exists $args{process_sto} && defined $args{process_sto} ? $args{process_sto} : "U";
  my $process_blo = exists $args{process_blo} && defined $args{process_blo} ? $args{process_blo} : "U";
  my $process_zom = exists $args{process_zom} && defined $args{process_zom} ? $args{process_zom} : "U";
  my $process_sle = exists $args{process_sle} && defined $args{process_sle} ? $args{process_sle} : "U";
  my $mem_free    = 0;

  if ( $mem_used ne "U" && $mem_usage ne "U" && $mem_usage ne "0" ) {
    $mem_free = ( $mem_used / $mem_usage ) * 100;
  }

  my $values = join ":", ( $cpu_percent, $disk_read_ops, $disk_write_ops, $disk_read_bytes, $disk_write_bytes, $network_in, $network_out, $mem_used, $mem_free, $process_run, $process_pag, $process_sto, $process_blo, $process_zom, $process_sle );

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

sub create_rrd_compute {
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
	"DS:mem_used:GAUGE:$no_time:0:U"
	"DS:mem_free:GAUGE:$no_time:0:U"
	"DS:process_run:GAUGE:$no_time:0:U"
	"DS:process_pag:GAUGE:$no_time:0:U"
	"DS:process_sto:GAUGE:$no_time:0:U"
	"DS:process_blo:GAUGE:$no_time:0:U"
	"DS:process_zom:GAUGE:$no_time:0:U"
	"DS:process_sle:GAUGE:$no_time:0:U"
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

sub create_rrd_mysql {
  my $filepath   = shift;
  my $start_time = shift;

  touch("create_rrd_database $filepath");

  RRDp::cmd qq(create "$filepath" --start "$start_time" --step "$step"
        "DS:cpu_percent:GAUGE:$no_time:0:U"
        "DS:read_ops:GAUGE:$no_time:0:U"
        "DS:write_ops:GAUGE:$no_time:0:U"
        "DS:network_in:GAUGE:$no_time:0:U"
        "DS:network_out:GAUGE:$no_time:0:U"
        "DS:disk_free:GAUGE:$no_time:0:U"
        "DS:disk_used:GAUGE:$no_time:0:U"
        "DS:mem_free:GAUGE:$no_time:0:U"
        "DS:mem_used:GAUGE:$no_time:0:U"
        "DS:connections:GAUGE:$no_time:0:U"
        "DS:questions:GAUGE:$no_time:0:U"
        "DS:queries:GAUGE:$no_time:0:U"
        "DS:innodb_read:GAUGE:$no_time:0:U"
        "DS:innodb_write:GAUGE:$no_time:0:U"
        "DS:innodb_buffer_free:GAUGE:$no_time:0:U"
	"DS:innodb_buffer_total:GAUGE:$no_time:0:U"
	"DS:innodb_os_fsyncs:GAUGE:$no_time:0:U"
	"DS:innodb_data_fsyncs:GAUGE:$no_time:0:U"
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

sub create_rrd_postgres {
  my $filepath   = shift;
  my $start_time = shift;

  touch("create_rrd_database $filepath");

  RRDp::cmd qq(create "$filepath" --start "$start_time" --step "$step"
        "DS:cpu_percent:GAUGE:$no_time:0:U"
        "DS:read_ops:GAUGE:$no_time:0:U"
        "DS:write_ops:GAUGE:$no_time:0:U"
        "DS:network_in:GAUGE:$no_time:0:U"
        "DS:network_out:GAUGE:$no_time:0:U"
        "DS:disk_free:GAUGE:$no_time:0:U"
        "DS:disk_used:GAUGE:$no_time:0:U"
        "DS:mem_free:GAUGE:$no_time:0:U"
        "DS:mem_used:GAUGE:$no_time:0:U"
	"DS:connections:GAUGE:$no_time:0:U"
	"DS:transaction_count:GAUGE:$no_time:0:U"
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

  touch("create_rrd_compute $filepath");

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
