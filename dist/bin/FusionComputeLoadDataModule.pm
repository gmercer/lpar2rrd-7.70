# LoadDataModuleFusionCompute.pm
# create/update RRDs with FusionCompute metrics

package FusionComputeLoadDataModule;

use strict;
use warnings;

use Data::Dumper;
use Date::Parse;
use RRDp;
use File::Copy qw(copy);
use Xorux_lib;
use Math::BigInt;
use POSIX;

use FusionComputeDataWrapper;

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

sub update_rrd_cluster {
  my $filepath  = shift;
  my $timestamp = shift;
  my %args      = %{ shift() };

  # check if the data is new enough
  my $last_update = rrd_last_update($filepath);
  unless ( $timestamp > $$last_update ) {
    return 0;
  }

  my $cpu_usage          = exists_and_defined( $args{cpu_usage} ) == 1          ? $args{cpu_usage}          : "U";
  my $mem_usage          = exists_and_defined( $args{mem_usage} ) == 1          ? $args{mem_usage}          : "U";
  my $logic_disk_usage   = exists_and_defined( $args{logic_disk_usage} ) == 1   ? $args{logic_disk_usage}   : "U";
  my $disk_io_in         = exists_and_defined( $args{disk_io_in} ) == 1         ? $args{disk_io_in}         : "U";
  my $disk_io_out        = exists_and_defined( $args{disk_io_out} ) == 1        ? $args{disk_io_out}        : "U";
  my $nic_byte_in_usage  = exists_and_defined( $args{nic_byte_in_usage} ) == 1  ? $args{nic_byte_in_usage}  : "U";
  my $nic_byte_out_usage = exists_and_defined( $args{nic_byte_out_usage} ) == 1 ? $args{nic_byte_out_usage} : "U";
  my $nic_byte_in        = exists_and_defined( $args{nic_byte_in} ) == 1        ? $args{nic_byte_in}        : "U";
  my $nic_byte_out       = exists_and_defined( $args{nic_byte_out} ) == 1       ? $args{nic_byte_out}       : "U";

  my $values = join ":", ( $cpu_usage, $mem_usage, $logic_disk_usage, $disk_io_in, $disk_io_out, $nic_byte_in_usage, $nic_byte_out_usage, $nic_byte_in, $nic_byte_out );

  RRDp::cmd qq(update "$filepath" $timestamp:$values);
  eval { my $answer = RRDp::read; };

  if ($@) {
    warn( localtime() . ": Failed during read last time $filepath: $@ " . __FILE__ . ":" . __LINE__ );
    return 1;
  }

  return 0;
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

  my $cpu_usage             = exists_and_defined( $args{cpu_usage} ) == 1             ? $args{cpu_usage}             : "U";
  my $dom0_cpu_usage        = exists_and_defined( $args{dom0_cpu_usage} ) == 1        ? $args{dom0_cpu_usage}        : "U";
  my $cpu_cores             = exists_and_defined( $args{cpu_cores} ) == 1             ? $args{cpu_cores}             : "U";
  my $cpu_cores_wr          = exists_and_defined( $args{cpu_cores_wr} ) == 1          ? $args{cpu_cores_wr}          : "U";
  my $mem_usage             = exists_and_defined( $args{mem_usage} ) == 1             ? $args{mem_usage}             : "U";
  my $dom0_mem_usage        = exists_and_defined( $args{dom0_mem_usage} ) == 1        ? $args{dom0_mem_usage}        : "U";
  my $mem_total             = exists_and_defined( $args{mem_total} ) == 1             ? $args{mem_total}             : "U";
  my $nic_byte_in           = exists_and_defined( $args{nic_byte_in} ) == 1           ? $args{nic_byte_in}           : "U";
  my $nic_byte_out          = exists_and_defined( $args{nic_byte_out} ) == 1          ? $args{nic_byte_out}          : "U";
  my $nic_pkg_send          = exists_and_defined( $args{nic_pkg_send} ) == 1          ? $args{nic_pkg_send}          : "U";
  my $nic_pkg_rcv           = exists_and_defined( $args{nic_pkg_rcv} ) == 1           ? $args{nic_pkg_rcv}           : "U";
  my $nic_byte_in_usage     = exists_and_defined( $args{nic_byte_in_usage} ) == 1     ? $args{nic_byte_in_usage}     : "U";
  my $nic_byte_out_usage    = exists_and_defined( $args{nic_byte_out_usage} ) == 1    ? $args{nic_byte_out_usage}    : "U";
  my $nic_pkg_rx_drop_speed = exists_and_defined( $args{nic_pkg_rx_drop_speed} ) == 1 ? $args{nic_pkg_rx_drop_speed} : "U";
  my $nic_pkg_tx_drop_speed = exists_and_defined( $args{nic_pkg_tx_drop_speed} ) == 1 ? $args{nic_pkg_tx_drop_speed} : "U";
  my $disk_io_in            = exists_and_defined( $args{disk_io_in} ) == 1            ? $args{disk_io_in}            : "U";
  my $disk_io_out           = exists_and_defined( $args{disk_io_out} ) == 1           ? $args{disk_io_out}           : "U";
  my $disk_io_read          = exists_and_defined( $args{disk_io_read} ) == 1          ? $args{disk_io_read}          : "U";
  my $disk_io_write         = exists_and_defined( $args{disk_io_write} ) == 1         ? $args{disk_io_write}         : "U";
  my $logic_disk_usage      = exists_and_defined( $args{logic_disk_usage} ) == 1      ? $args{logic_disk_usage}      : "U";
  my $domU_cpu_usage        = exists_and_defined( $args{domU_cpu_usage} ) == 1        ? $args{domU_cpu_usage}        : "U";
  my $domU_mem_usage        = exists_and_defined( $args{domU_mem_usage} ) == 1        ? $args{domU_mem_usage}        : "U";

  my $values = join ":", ( $cpu_usage, $dom0_cpu_usage, $cpu_cores, $cpu_cores_wr, $mem_usage, $dom0_mem_usage, $mem_total, $nic_byte_in, $nic_byte_out, $nic_pkg_send, $nic_pkg_rcv, $nic_byte_in_usage, $nic_byte_out_usage, $nic_pkg_rx_drop_speed, $nic_pkg_tx_drop_speed, $disk_io_in, $disk_io_out, $disk_io_read, $disk_io_write, $logic_disk_usage, $domU_cpu_usage, $domU_mem_usage );

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

  my $cpu_usage             = exists_and_defined( $args{cpu_usage} ) == 1             ? $args{cpu_usage}                  : "U";
  my $cpu_quantity          = exists_and_defined( $args{cpu_quantity} ) == 1          ? $args{cpu_quantity}               : "U";
  my $cores_per_socket      = exists_and_defined( $args{cores_per_socket} ) == 1      ? $args{cores_per_socket}           : "U";
  my $cpu_cores             = $cpu_quantity ne "U" && $cores_per_socket ne "U"        ? $cores_per_socket * $cpu_quantity : "U";
  my $mem_usage             = exists_and_defined( $args{mem_usage} ) == 1             ? $args{mem_usage}                  : "U";
  my $mem_total             = exists_and_defined( $args{mem_total} ) == 1             ? $args{mem_total}                  : "U";
  my $disk_usage            = exists_and_defined( $args{disk_usage} ) == 1            ? $args{disk_usage}                 : "U";
  my $disk_io_in            = exists_and_defined( $args{disk_io_in} ) == 1            ? $args{disk_io_in}                 : "U";
  my $disk_io_out           = exists_and_defined( $args{disk_io_out} ) == 1           ? $args{disk_io_out}                : "U";
  my $disk_req_in           = exists_and_defined( $args{disk_req_in} ) == 1           ? $args{disk_req_in}                : "U";
  my $disk_req_out          = exists_and_defined( $args{disk_req_out} ) == 1          ? $args{disk_req_out}               : "U";
  my $disk_rd_ios           = exists_and_defined( $args{disk_rd_ios} ) == 1           ? $args{disk_rd_ios}                : "U";
  my $disk_wr_ios           = exists_and_defined( $args{disk_wr_ios} ) == 1           ? $args{disk_wr_ios}                : "U";
  my $disk_iowr_ticks       = exists_and_defined( $args{disk_iowr_ticks} ) == 1       ? $args{disk_iowr_ticks}            : "U";
  my $disk_iord_ticks       = exists_and_defined( $args{disk_iord_ticks} ) == 1       ? $args{disk_iord_ticks}            : "U";
  my $disk_rd_sectors       = exists_and_defined( $args{disk_rd_sectors} ) == 1       ? $args{disk_rd_sectors}            : "U";
  my $disk_wr_sectors       = exists_and_defined( $args{disk_wr_sectors} ) == 1       ? $args{disk_wr_sectors}            : "U";
  my $disk_tot_ticks        = exists_and_defined( $args{disk_tot_ticks} ) == 1        ? $args{disk_tot_ticks}             : "U";
  my $nic_byte_in           = exists_and_defined( $args{nic_byte_in} ) == 1           ? $args{nic_byte_in}                : "U";
  my $nic_byte_out          = exists_and_defined( $args{nic_byte_out} ) == 1          ? $args{nic_byte_out}               : "U";
  my $nic_byte_in_out       = exists_and_defined( $args{nic_byte_in_out} ) == 1       ? $args{nic_byte_in_out}            : "U";
  my $nic_rx_drop_pkt_speed = exists_and_defined( $args{nic_rx_drop_pkt_speed} ) == 1 ? $args{nic_rx_drop_pkt_speed}      : "U";
  my $nic_tx_drop_pkt_speed = exists_and_defined( $args{nic_tx_drop_pkt_speed} ) == 1 ? $args{nic_tx_drop_pkt_speed}      : "U";

  my $values = join ":", ( $cpu_usage, $cpu_quantity, $cores_per_socket, $cpu_cores, $mem_usage, $mem_total, $disk_usage, $disk_io_in, $disk_io_out, $disk_req_in, $disk_req_out, $disk_rd_ios, $disk_wr_ios, $disk_iowr_ticks, $disk_iord_ticks, $disk_rd_sectors, $disk_wr_sectors, $disk_tot_ticks, $nic_byte_in, $nic_byte_out, $nic_byte_in_out, $nic_rx_drop_pkt_speed, $nic_tx_drop_pkt_speed );

  RRDp::cmd qq(update "$filepath" $timestamp:$values);
  eval { my $answer = RRDp::read; };

  if ($@) {
    warn( localtime() . ": Failed during read last time $filepath: $@ " . __FILE__ . ":" . __LINE__ );
    return 1;
  }

  return 0;
}

sub update_rrd_datastore {
  my $filepath  = shift;
  my $timestamp = shift;
  my %args      = %{ shift() };

  # check if the data is new enough
  my $last_update = rrd_last_update($filepath);
  unless ( $timestamp > $$last_update ) {
    return 0;
  }

  my $used  = exists_and_defined( $args{used} ) == 1  ? $args{used}  : "U";
  my $free  = exists_and_defined( $args{free} ) == 1  ? $args{free}  : "U";
  my $total = exists_and_defined( $args{total} ) == 1 ? $args{total} : "U";

  my $values = join ":", ( $used, $free, $total );

  RRDp::cmd qq(update "$filepath" $timestamp:$values);
  eval { my $answer = RRDp::read; };

  if ($@) {
    warn( localtime() . ": Failed during read last time $filepath: $@ " . __FILE__ . ":" . __LINE__ );
    return 1;
  }

  return 0;
}

################################################################################

sub create_rrd_cluster {
  my $filepath   = shift;
  my $start_time = shift;

  touch("create_rrd_cluster $filepath");

  RRDp::cmd qq(create "$filepath" --start "$start_time" --step "$step"
        "DS:cpu_usage:GAUGE:$no_time:0:U"
        "DS:mem_usage:GAUGE:$no_time:0:U"
        "DS:logic_disk_usage:GAUGE:$no_time:0:U"
        "DS:disk_io_in:GAUGE:$no_time:0:U"
        "DS:disk_io_out:GAUGE:$no_time:0:U"
        "DS:nic_byte_in_usage:GAUGE:$no_time:0:U"
        "DS:nic_byte_out_usage:GAUGE:$no_time:0:U"
        "DS:nic_byte_in:GAUGE:$no_time:0:U"
        "DS:nic_byte_out:GAUGE:$no_time:0:U"
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

sub create_rrd_host {
  my $filepath   = shift;
  my $start_time = shift;

  touch("create_rrd_host $filepath");

  RRDp::cmd qq(create "$filepath" --start "$start_time" --step "$step"
        "DS:cpu_usage:GAUGE:$no_time:0:U"
        "DS:0_cpu_usage:GAUGE:$no_time:0:U"
	"DS:cpu_cores:GAUGE:$no_time:0:U"
        "DS:cpu_cores_wr:GAUGE:$no_time:0:U"
	"DS:mem_usage:GAUGE:$no_time:0:U"
        "DS:0_mem_usage:GAUGE:$no_time:0:U"
	"DS:mem_total:GAUGE:$no_time:0:U"
	"DS:nic_byte_in:GAUGE:$no_time:0:U"
        "DS:nic_byte_out:GAUGE:$no_time:0:U"
        "DS:nic_pkg_send:GAUGE:$no_time:0:U"
        "DS:nic_pkg_rcv:GAUGE:$no_time:0:U"
        "DS:nic_byte_in_usage:GAUGE:$no_time:0:U"
        "DS:nic_byte_out_usage:GAUGE:$no_time:0:U"
        "DS:nic_pkg_rx_speed:GAUGE:$no_time:0:U"
        "DS:nic_pkg_tx_speed:GAUGE:$no_time:0:U"
        "DS:disk_io_in:GAUGE:$no_time:0:U"
        "DS:disk_io_out:GAUGE:$no_time:0:U"
        "DS:disk_io_read:GAUGE:$no_time:0:U"
        "DS:disk_io_write:GAUGE:$no_time:0:U"
        "DS:logic_disk_usage:GAUGE:$no_time:0:U"
        "DS:U_cpu_usage:GAUGE:$no_time:0:U"
        "DS:U_mem_usage:GAUGE:$no_time:0:U"
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
        "DS:cpu_usage:GAUGE:$no_time:0:U"
	"DS:cpu_quantity:GAUGE:$no_time:0:U"
	"DS:cores_per_socket:GAUGE:$no_time:0:U"
	"DS:cpu_cores:GAUGE:$no_time:0:U"
        "DS:mem_usage:GAUGE:$no_time:0:U"
	"DS:mem_total:GAUGE:$no_time:0:U"
        "DS:disk_usage:GAUGE:$no_time:0:U"
	"DS:disk_io_in:GAUGE:$no_time:0:U"
        "DS:disk_io_out:GAUGE:$no_time:0:U"
	"DS:disk_req_in:GAUGE:$no_time:0:U"
        "DS:disk_req_out:GAUGE:$no_time:0:U"
	"DS:disk_rd_ios:GAUGE:$no_time:0:U"
        "DS:disk_wr_ios:GAUGE:$no_time:0:U"
	"DS:disk_iowr_ticks:GAUGE:$no_time:0:U"
        "DS:disk_iord_ticks:GAUGE:$no_time:0:U"
	"DS:disk_rd_sectors:GAUGE:$no_time:0:U"
        "DS:disk_wr_sectors:GAUGE:$no_time:0:U"
	"DS:disk_tot_ticks:GAUGE:$no_time:0:U"
	"DS:nic_byte_in:GAUGE:$no_time:0:U"
        "DS:nic_byte_out:GAUGE:$no_time:0:U"
        "DS:nic_byte_inout:GAUGE:$no_time:0:U"
        "DS:nic_rx_drop_speed:GAUGE:$no_time:0:U"
        "DS:nic_tx_drop_speed:GAUGE:$no_time:0:U"
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

sub create_rrd_datastore {
  my $filepath   = shift;
  my $start_time = shift;

  touch("create_rrd_datastore $filepath");

  RRDp::cmd qq(create "$filepath" --start "$start_time" --step "$step"
        "DS:used:GAUGE:$no_time:0:U"
        "DS:free:GAUGE:$no_time:0:U"
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

###

# copied from LoadDataModule.pm with minor changes (removed $host/HMC)

sub touch {
  my $text = shift;

  my $version    = "$ENV{version}";
  my $basedir    = $ENV{INPUTDIR};
  my $new_change = "$basedir/tmp/$version-fusioncompute";
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

