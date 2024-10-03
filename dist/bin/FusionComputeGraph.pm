# FusionComputeGraph.pm
# keep FusionCompute graph generation in one place, if possible
# (separated from `detail-graph-cgi.pl`)

package FusionComputeGraph;

use strict;
use warnings;

use Data::Dumper;

use FusionComputeDataWrapper;

defined $ENV{INPUTDIR} || warn( localtime() . ': INPUTDIR undefined, config etc/lpar2rrd.cfg probably has not been loaded ' . __FILE__ . ':' . __LINE__ ) && exit 1;

my $inputdir     = $ENV{INPUTDIR};
my $wrkdir       = "$inputdir/data";
my $proxmox_path = "$wrkdir/FusionCompute";

# helper delimiter: used to convert graph legends to HTML tables in `detail-graph-cgi.pl`
my $delimiter = 'XORUX';

################################################################################

# current usage in detail-graph-cgi.pl
#   graph_cloudstack( $host, $server, $lpar, $time, $name_out, $type_sam, $detail, $start_unix, $end_unix );
#   graph_cloudstack_totals( $host, $server, $lpar, $time, $name_out, $type_sam, $detail, $start_unix, $end_unix );
# and custom.pl

################################################################################

sub get_header {
  my $type    = shift;
  my $uuid    = shift;
  my $context = shift;

  my $label  = FusionComputeDataWrapper::get_label( $type, $uuid );
  my $result = '';
  if ( defined $context && $context ne '' ) {
    $result .= "$context :";
  }
  $result .= " $label";

  return $result;
}

# copied from OVirtGraph.pm
sub get_formatted_label {
  my $label_space = shift;

  if ( length($label_space) < 20 ) {
    $label_space .= ' ' x ( 20 - length($label_space) );
  }

  return $label_space;
}

################################################################################

sub get_params_cpu {
  my $type = shift;    # value: 'percent' or 'cores'

  my $result = '';
  my $unit   = '%';
  if ( defined $type && $type eq 'cores' ) {
    $unit = 'cores';
  }
  $result .= " --vertical-label=\"CPU load in [$unit]\"";
  if ( defined $type && $type eq 'percent' ) {
    $result .= " --upper-limit=100.0";
  }
  $result .= " --lower-limit=0.00";

  return $result;
}

sub get_params_custom {
  my $legend = shift;
  my $max    = shift;
  my $min    = shift;
  my $result = '';
  $result .= " --vertical-label=\"$legend\"";
  $result .= " --lower-limit=0.00";
  if ( defined $max ) {
    $result .= " --upper-limit=100.0";
  }
  if ( defined $min ) {
    $result .= " --lower-limit=-100.0";
  }

  return $result;
}

sub get_params_memory {
  my $type   = shift;
  my $result = '';
  $result .= " --vertical-label=\"Memory in [GB]\"";
  $result .= " --lower-limit=0.00";

  return $result;
}

sub get_params_lan {
  my $result = '';
  $result .= " --vertical-label=\"Read - MB/sec - Write\"";
  $result .= " --lower-limit=0.00";

  return $result;
}

sub get_params_storage {
  my $type = shift;

  my $result = '';
  my $unit   = 'MB/s';
  if ( defined $type ) {
    if ( $type eq 'latency' ) {
      $unit = 'ms';
      $result .= " --vertical-label=\"Read - $unit - Write\"";
    }
    elsif ( $type eq 'iops' ) {
      $unit = 'IOPS';
      $result .= " --vertical-label=\"Read - $unit - Write\"";
    }
  }
  else {
    $result .= " --vertical-label=\"Read - $unit - Write\"";
  }

  return $result;
}

################################################################################

sub graph_cpu {
  my $uuid = shift;
  my $type = shift;
  my $skip_acl = shift || 0; # optional flag

  # necessary information
  my $rrd = FusionComputeDataWrapper::get_filepath_rrd( { type => $type, uuid => $uuid, skip_acl => $skip_acl } );

  # RRD command parts
  my $cmd_params = get_params_cpu('cores');
  my $cmd_def    = my $cmd_cdef = my $cmd_legend = '';

  my $metric;
  if ( $type eq "vm" ) {
    $metric = "cpu_quantity";
  }
  else {
    $metric = "cpu_cores";
  }

  $cmd_def  .= " DEF:cpu_cores=\"$rrd\":$metric:AVERAGE";
  $cmd_def  .= " DEF:cpu_usage=\"$rrd\":cpu_usage:AVERAGE";
  $cmd_cdef .= " CDEF:usage=cpu_usage,100,/";
  $cmd_cdef .= " CDEF:used=cpu_cores,usage,*";

  $cmd_legend .= " COMMENT:\"[%]              Avrg       Max\\n\"";
  $cmd_legend .= " AREA:used#ff4040:\" Used     \"";
  $cmd_legend .= " GPRINT:used:AVERAGE:\" %6.1lf\"";
  $cmd_legend .= " GPRINT:used:MAX:\"  %6.1lf\"";
  $cmd_legend .= " COMMENT:\\n";
  $cmd_legend .= " LINE1:cpu_cores#000000:\" Total    \"";
  $cmd_legend .= " GPRINT:cpu_cores:AVERAGE:\" %6.1lf\"";
  $cmd_legend .= " GPRINT:cpu_cores:MAX:\"  %6.1lf\"";
  $cmd_legend .= " COMMENT:\\n";

  my %result = (
    cmd_params => $cmd_params,
    cmd_def    => $cmd_def,
    cmd_cdef   => $cmd_cdef,
    cmd_legend => $cmd_legend,
  );

  return \%result;
}

sub graph_memory {
  my $uuid = shift;
  my $type = shift;
  my $skip_acl = shift || 0; # optional flag

  # necessary information
  my $rrd = FusionComputeDataWrapper::get_filepath_rrd( { type => $type, uuid => $uuid, skip_acl => $skip_acl } );

  # RRD command parts
  my $cmd_params = get_params_custom('Memory in [GB]');
  my $cmd_def    = my $cmd_cdef = my $cmd_legend = '';

  my $b2gb = 1024 * 1024 * 1024;

  $cmd_def  .= " DEF:mem_total=\"$rrd\":mem_total:AVERAGE";
  $cmd_def  .= " DEF:mem_usage=\"$rrd\":mem_usage:AVERAGE";
  $cmd_cdef .= " CDEF:usage=mem_usage,100,/";
  $cmd_cdef .= " CDEF:total=mem_total,$b2gb,/";
  $cmd_cdef .= " CDEF:used=total,usage,*";
  $cmd_cdef .= " CDEF:free=total,used,-";

  $cmd_legend .= " COMMENT:\"[GB]             Avrg       Max\\n\"";
  $cmd_legend .= " AREA:used#ff4040:\" Used     \"";
  $cmd_legend .= " GPRINT:used:AVERAGE:\" %6.1lf\"";
  $cmd_legend .= " GPRINT:used:MAX:\"  %6.1lf\"";
  $cmd_legend .= " COMMENT:\\n";
  $cmd_legend .= " STACK:free#00FF00:\" Free     \"";
  $cmd_legend .= " GPRINT:free:AVERAGE:\" %6.1lf\"";
  $cmd_legend .= " GPRINT:free:MAX:\"  %6.1lf\"";
  $cmd_legend .= " COMMENT:\\n";
  $cmd_legend .= " LINE1:total#000000:\" Total    \"";
  $cmd_legend .= " GPRINT:total:AVERAGE:\" %6.1lf\"";
  $cmd_legend .= " GPRINT:total:MAX:\"  %6.1lf\"";
  $cmd_legend .= " COMMENT:\\n";

  my %result = (
    cmd_params => $cmd_params,
    cmd_def    => $cmd_def,
    cmd_cdef   => $cmd_cdef,
    cmd_legend => $cmd_legend,
  );

  return \%result;
}

sub graph_cpu_percent {
  my $uuid = shift;
  my $type = shift;
  my $skip_acl = shift || 0; # optional flag

  # necessary information
  my $rrd = FusionComputeDataWrapper::get_filepath_rrd( { type => $type, uuid => $uuid, skip_acl => $skip_acl } );

  # RRD command parts
  my $cmd_params = get_params_cpu();
  my $cmd_def    = my $cmd_cdef = my $cmd_legend = '';

  my ( $metric_cputotal, $metric_cpuused );

  $metric_cpuused = 'cpu_usage';

  $cmd_def  .= " DEF:cpu_used=\"$rrd\":${metric_cpuused}:AVERAGE";
  $cmd_cdef .= " CDEF:used=cpu_used,1,*";

  if ( $type eq "host" ) {
    $cmd_def  .= " DEF:0_cpu_used=\"$rrd\":0_cpu_usage:AVERAGE";
    $cmd_cdef .= " CDEF:0_used=0_cpu_used,1,*";
    $cmd_def  .= " DEF:U_cpu_used=\"$rrd\":U_cpu_usage:AVERAGE";
    $cmd_cdef .= " CDEF:U_used=U_cpu_used,1,*";

    $cmd_legend .= " COMMENT:\"[%]                          Avrg       Max\\n\"";
    $cmd_legend .= " LINE1:used#ff4040:\" Usage                \"";
    $cmd_legend .= " GPRINT:used:AVERAGE:\" %6.1lf\"";
    $cmd_legend .= " GPRINT:used:MAX:\"  %6.1lf\"";
    $cmd_legend .= " COMMENT:\\n";
    $cmd_legend .= " LINE1:0_used#0080fc:\" Control domain       \"";
    $cmd_legend .= " GPRINT:0_used:AVERAGE:\" %6.1lf\"";
    $cmd_legend .= " GPRINT:0_used:MAX:\"  %6.1lf\"";
    $cmd_legend .= " COMMENT:\\n";
    $cmd_legend .= " LINE1:U_used#75ff80:\" Virtualization domain\"";
    $cmd_legend .= " GPRINT:U_used:AVERAGE:\" %6.1lf\"";
    $cmd_legend .= " GPRINT:U_used:MAX:\"  %6.1lf\"";
    $cmd_legend .= " COMMENT:\\n";
  }
  else {
    $cmd_legend .= " COMMENT:\"[%]              Avrg       Max\\n\"";
    $cmd_legend .= " LINE1:used#ff4040:\" Usage   \"";
    $cmd_legend .= " GPRINT:used:AVERAGE:\" %6.1lf\"";
    $cmd_legend .= " GPRINT:used:MAX:\"  %6.1lf\"";
    $cmd_legend .= " COMMENT:\\n";
  }

  my %result = (
    cmd_params => $cmd_params,
    cmd_def    => $cmd_def,
    cmd_cdef   => $cmd_cdef,
    cmd_legend => $cmd_legend,
  );

  return \%result;
}

sub graph_memory_percent {
  my $uuid = shift;
  my $type = shift;
  my $skip_acl = shift || 0; # optional flag

  # necessary information
  my $rrd = FusionComputeDataWrapper::get_filepath_rrd( { type => $type, uuid => $uuid, skip_acl => $skip_acl } );

  # RRD command parts
  my $cmd_params = get_params_custom("Memory usage in [%]");
  my $cmd_def    = my $cmd_cdef = my $cmd_legend = '';

  my $metric_memused = 'mem_usage';

  $cmd_def  .= " DEF:mem_used=\"$rrd\":${metric_memused}:AVERAGE";
  $cmd_cdef .= " CDEF:used=mem_used,1,*";

  if ( $type eq "host" ) {
    $cmd_def  .= " DEF:0_mem_used=\"$rrd\":0_mem_usage:AVERAGE";
    $cmd_cdef .= " CDEF:0_used=0_mem_used,1,*";
    $cmd_def  .= " DEF:U_mem_used=\"$rrd\":U_mem_usage:AVERAGE";
    $cmd_cdef .= " CDEF:U_used=U_mem_used,1,*";

    $cmd_legend .= " COMMENT:\"[%]                          Avrg       Max\\n\"";
    $cmd_legend .= " LINE2:used#ff4040:\" Usage                \"";
    $cmd_legend .= " GPRINT:used:AVERAGE:\" %6.1lf\"";
    $cmd_legend .= " GPRINT:used:MAX:\"  %6.1lf\"";
    $cmd_legend .= " COMMENT:\\n";
    $cmd_legend .= " LINE2:0_used#0080fc:\" Control domain       \"";
    $cmd_legend .= " GPRINT:0_used:AVERAGE:\" %6.1lf\"";
    $cmd_legend .= " GPRINT:0_used:MAX:\"  %6.1lf\"";
    $cmd_legend .= " COMMENT:\\n";
    $cmd_legend .= " LINE2:U_used#75ff80:\" Virtualization domain\"";
    $cmd_legend .= " GPRINT:U_used:AVERAGE:\" %6.1lf\"";
    $cmd_legend .= " GPRINT:U_used:MAX:\"  %6.1lf\"";
    $cmd_legend .= " COMMENT:\\n";
  }
  else {
    $cmd_legend .= " COMMENT:\"[%]              Avrg       Max\\n\"";
    $cmd_legend .= " LINE1:used#ff4040:\" Usage   \"";
    $cmd_legend .= " GPRINT:used:AVERAGE:\" %6.1lf\"";
    $cmd_legend .= " GPRINT:used:MAX:\"  %6.1lf\"";
    $cmd_legend .= " COMMENT:\\n";
  }

  my %result = (
    cmd_params => $cmd_params,
    cmd_def    => $cmd_def,
    cmd_cdef   => $cmd_cdef,
    cmd_legend => $cmd_legend,
  );

  return \%result;
}

sub graph_disk_percent {
  my $uuid = shift;
  my $type = shift;
  my $skip_acl = shift || 0; # optional flag

  # necessary information
  my $rrd = FusionComputeDataWrapper::get_filepath_rrd( { type => $type, uuid => $uuid, skip_acl => $skip_acl } );

  # RRD command parts
  my $cmd_params = get_params_custom("Disk usage in [%]");
  my $cmd_def    = my $cmd_cdef = my $cmd_legend = '';

  my $metric_diskused = 'disk_usage';
  if ( $type eq "host" || $type eq "cluster" ) {
    $metric_diskused = 'logic_disk_usage';
  }

  $cmd_def  .= " DEF:disk_used=\"$rrd\":${metric_diskused}:AVERAGE";
  $cmd_cdef .= " CDEF:used=disk_used,1,*";

  $cmd_legend .= " COMMENT:\"[%]              Avrg       Max\\n\"";
  $cmd_legend .= " LINE1:used#ff4040:\" Usage   \"";
  $cmd_legend .= " GPRINT:used:AVERAGE:\" %6.1lf\"";
  $cmd_legend .= " GPRINT:used:MAX:\"  %6.1lf\"";
  $cmd_legend .= " COMMENT:\\n";

  my %result = (
    cmd_params => $cmd_params,
    cmd_def    => $cmd_def,
    cmd_cdef   => $cmd_cdef,
    cmd_legend => $cmd_legend,
  );

  return \%result;
}

sub graph_net_percent {
  my $uuid = shift;
  my $type = shift;
  my $skip_acl = shift || 0; # optional flag

  # necessary information
  my $rrd = FusionComputeDataWrapper::get_filepath_rrd( { type => $type, uuid => $uuid, skip_acl => $skip_acl } );

  # RRD command parts
  my $cmd_params = get_params_custom("Net usage in [%]");
  my $cmd_def    = my $cmd_cdef = my $cmd_legend = '';

  my $metric_in_usage  = 'nic_byte_in_usage';
  my $metric_out_usage = 'nic_byte_out_usage';

  $cmd_def  .= " DEF:in_usage=\"$rrd\":${metric_in_usage}:AVERAGE";
  $cmd_cdef .= " CDEF:in=in_usage,1,*";
  $cmd_def  .= " DEF:out_usage=\"$rrd\":${metric_out_usage}:AVERAGE";
  $cmd_cdef .= " CDEF:out=out_usage,1,*";

  $cmd_legend .= " COMMENT:\"[%]          Avrg       Max\\n\"";
  $cmd_legend .= " LINE1:in#FF0000:\" In   \"";
  $cmd_legend .= " GPRINT:in:AVERAGE:\" %6.1lf\"";
  $cmd_legend .= " GPRINT:in:MAX:\"  %6.1lf\"";
  $cmd_legend .= " COMMENT:\\n";
  $cmd_legend .= " LINE1:out#0000FF:\" Out  \"";
  $cmd_legend .= " GPRINT:out:AVERAGE:\" %6.1lf\"";
  $cmd_legend .= " GPRINT:out:MAX:\"  %6.1lf\"";
  $cmd_legend .= " COMMENT:\\n";

  my %result = (
    cmd_params => $cmd_params,
    cmd_def    => $cmd_def,
    cmd_cdef   => $cmd_cdef,
    cmd_legend => $cmd_legend,
  );

  return \%result;
}

sub graph_capacity {
  my $uuid = shift;
  my $type = shift;
  my $skip_acl = shift || 0; # optional flag

  # necessary information
  my $rrd = FusionComputeDataWrapper::get_filepath_rrd( { type => $type, uuid => $uuid, skip_acl => $skip_acl } );

  # RRD command parts
  my $cmd_params = get_params_custom("Capacity in [TB]");
  my $cmd_def    = my $cmd_cdef = my $cmd_legend = '';

  my $used  = 'used';
  my $free  = 'free';
  my $total = 'total';

  my $gb2tb = 1024;

  $cmd_def  .= " DEF:free_pure=\"$rrd\":${free}:AVERAGE";
  $cmd_cdef .= " CDEF:free=free_pure,$gb2tb,/";
  $cmd_def  .= " DEF:total_pure=\"$rrd\":${total}:AVERAGE";
  $cmd_cdef .= " CDEF:total=total_pure,$gb2tb,/";
  $cmd_cdef .= " CDEF:used=total,free,-";

  $cmd_legend .= " COMMENT:\"[TB]          Avrg       Max\\n\"";
  $cmd_legend .= " AREA:used#FF0000:\" Used \"";
  $cmd_legend .= " GPRINT:used:AVERAGE:\" %6.2lf\"";
  $cmd_legend .= " GPRINT:used:MAX:\"  %6.2lf\"";
  $cmd_legend .= " COMMENT:\\n";
  $cmd_legend .= " STACK:free#00FF00:\" Free \"";
  $cmd_legend .= " GPRINT:free:AVERAGE:\" %6.2lf\"";
  $cmd_legend .= " GPRINT:free:MAX:\"  %6.2lf\"";
  $cmd_legend .= " COMMENT:\\n";
  $cmd_legend .= " LINE1:total#0000FF:\" Total\"";
  $cmd_legend .= " GPRINT:total:AVERAGE:\" %6.2lf\"";
  $cmd_legend .= " GPRINT:total:MAX:\"  %6.2lf\"";
  $cmd_legend .= " COMMENT:\\n";

  my %result = (
    cmd_params => $cmd_params,
    cmd_def    => $cmd_def,
    cmd_cdef   => $cmd_cdef,
    cmd_legend => $cmd_legend,
  );

  return \%result;
}

sub graph_read_write {
  my $uuid   = shift;
  my $type   = shift;
  my $metric = shift;
  my $skip_acl = shift || 0; # optional flag

  # necessary information
  my $rrd = FusionComputeDataWrapper::get_filepath_rrd( { type => $type, uuid => $uuid, skip_acl => $skip_acl } );

  # RRD command parts
  my $cmd_def = my $cmd_params = my $cmd_cdef = my $cmd_legend = '';

  my ( $metric_write, $metric_read, $division );

  my $metric_write_text = "Write";
  my $metric_read_text  = "Read";
  my $legend            = " COMMENT:\"[MB/s]        Avrg       Max\\n\"";
  my $lo                = 1;

  if ( $metric eq "data" ) {
    $cmd_params   = get_params_custom('Read - MB/sec - Write');
    $division     = 1024;
    $metric_read  = 'disk_io_out';
    $metric_write = 'disk_io_in';
    $lo           = 2;
  }
  elsif ( $metric eq "disk_req" ) {
    $cmd_params   = get_params_custom('Read - IOPS - Write');
    $division     = 1;
    $metric_read  = 'disk_req_out';
    $metric_write = 'disk_req_in';
    $lo           = 0;
    $legend       = " COMMENT:\"[IOPS]        Avrg       Max\\n\"";
  }
  elsif ( $metric eq "disk_ios" ) {
    $cmd_params = get_params_custom('Read - IOPS - Write');
    $division   = 1;
    if ( $type eq "host" ) {
      $metric_write = 'disk_io_write';
      $metric_read  = 'disk_io_read';
    }
    else {
      $metric_read  = 'disk_rd_ios';
      $metric_write = 'disk_wr_ios';
    }
    $lo     = 0;
    $legend = " COMMENT:\"[IOPS]        Avrg       Max\\n\"";
  }
  elsif ( $metric eq "disk_ticks" ) {
    $cmd_params   = get_params_custom('Read - ms - Write');
    $division     = 1;
    $metric_read  = 'disk_iord_ticks';
    $metric_write = 'disk_iowr_ticks';
    $lo           = 2;
    $legend       = " COMMENT:\"[ms]          Avrg       Max\\n\"";
  }
  elsif ( $metric eq "disk_sectors" ) {
    $cmd_params   = get_params_custom('Read - MB/sec - Write');
    $division     = 1024;
    $metric_write = 'disk_wr_sectors';
    $metric_read  = 'disk_rd_sectors';
    $lo           = 2;
  }
  elsif ( $metric eq "net" ) {
    $cmd_params        = get_params_custom('Received - MB/sec - Transmitted');
    $division          = 1024;
    $metric_write      = 'nic_byte_out';
    $metric_read       = 'nic_byte_in';
    $metric_write_text = 'Tx   ';
    $metric_read_text  = 'Rx  ';
    $lo                = 2;
  }
  elsif ( $metric eq "net_packet" ) {
    $cmd_params        = get_params_custom('Read - Number - Write');
    $division          = 1;
    $metric_write      = 'nic_pkg_send';
    $metric_read       = 'nic_pkg_rcv';
    $metric_write_text = 'Packet Tx ';
    $metric_read_text  = 'Packet Rx';
    $lo                = 0;
    $legend            = " COMMENT:\"[number]           Avrg       Max\\n\"";
  }
  elsif ( $metric eq "net_packet_drop" ) {
    $cmd_params = get_params_custom('Read - Number - Write');
    $division   = 1;
    if ( $type eq "host" ) {
      $metric_write = 'nic_pkg_tx_speed';
      $metric_read  = 'nic_pkg_rx_speed';
    }
    else {
      $metric_write = 'nic_tx_drop_speed';
      $metric_read  = 'nic_rx_drop_speed';
    }
    $metric_write_text = 'Packet Tx ';
    $metric_read_text  = 'Packet Rx';
    $lo                = 0;
    $legend            = " COMMENT:\"[number]            Avrg       Max\\n\"";
  }

  $cmd_def .= " DEF:metric_write=\"$rrd\":${metric_write}:AVERAGE";
  $cmd_def .= " DEF:metric_read=\"$rrd\":${metric_read}:AVERAGE";

  $cmd_cdef .= " CDEF:read=metric_read,$division,/";
  $cmd_cdef .= " CDEF:write=metric_write,$division,/";
  $cmd_cdef .= " CDEF:read_neg=0,read,-";

  $cmd_legend .= $legend;
  $cmd_legend .= " LINE1:read_neg#FF0000:\" $metric_read_text  \"";
  $cmd_legend .= " GPRINT:read:AVERAGE:\" %6." . $lo . "lf\"";
  $cmd_legend .= " GPRINT:read:MAX:\"  %6." . $lo . "lf\"";
  $cmd_legend .= " COMMENT:\\n";
  $cmd_legend .= " LINE1:write#0000FF:\" $metric_write_text\"";
  $cmd_legend .= " GPRINT:write:AVERAGE:\"  %6." . $lo . "lf\"";
  $cmd_legend .= " GPRINT:write:MAX:\"  %6." . $lo . "lf\"";
  $cmd_legend .= " COMMENT:\\n";

  my %result = (
    cmd_params => $cmd_params,
    cmd_def    => $cmd_def,
    cmd_cdef   => $cmd_cdef,
    cmd_legend => $cmd_legend,
  );

  return \%result;
}

################################################################################

sub graph_cpu_aggr {
  my $type        = shift;    # value: 'node'
  my $filepath    = shift;
  my $counter     = shift;
  my $color       = shift;
  my $label       = shift;
  my $group_label = shift;
  my $group_type  = shift;    # value: 'pool' (for pool or custom groups) or 'host'
  my $url_item    = shift;

  my $cmd_def = my $cmd_cdef = my $cmd_legend = '';

  my $metric;
  if ( $type eq "vm" ) {
    $metric = "cpu_quantity";
  }
  else {
    $metric = "cpu_cores";
  }

  $cmd_def  .= " DEF:cpu_cores_${counter}=\"$filepath\":$metric:AVERAGE";
  $cmd_def  .= " DEF:cpu_usage_${counter}=\"$filepath\":cpu_usage:AVERAGE";
  $cmd_cdef .= " CDEF:usage_${counter}=cpu_usage_${counter},100,/";
  $cmd_cdef .= " CDEF:used_${counter}=cpu_cores_${counter},usage_${counter},*";

  my $graph_type = ( $counter > 0 ) ? 'STACK' : 'AREA';

  my $label_space = get_formatted_label($label);
  my $group_space = get_formatted_label($group_label);

  # $uuid is used to form hypertext links in legends' tables
  my $uuid = get_uuid_from_filepath( $type, $filepath );

  $cmd_legend .= " ${graph_type}:used_${counter}${color}:\" \"";
  $cmd_legend .= " COMMENT:\"$group_space  $label_space\"";
  $cmd_legend .= " GPRINT:used_${counter}:AVERAGE:\" %6.1lf\"";
  $cmd_legend .= " GPRINT:used_${counter}:MAX:\" %6.1lf    \"";
  $cmd_legend .= " PRINT:used_${counter}:AVERAGE:\" %6.1lf $delimiter $url_item $delimiter $label $delimiter $color $delimiter $color\"";
  $cmd_legend .= " PRINT:used_${counter}:MAX:\" %6.1lf $delimiter $label $delimiter ${group_label} $delimiter $uuid\"";
  $cmd_legend .= " COMMENT:\\n";

  # return the data
  my %result = (
    cmd_def    => $cmd_def,
    cmd_cdef   => $cmd_cdef,
    cmd_legend => $cmd_legend
  );

  return \%result;
}

sub graph_memory_aggr {
  my $type        = shift;    # value: 'node'
  my $filepath    = shift;
  my $counter     = shift;
  my $color       = shift;
  my $label       = shift;
  my $group_label = shift;
  my $group_type  = shift;    # value: 'pool' (for pool or custom groups) or 'host'
  my $metric      = shift;
  my $url_item    = shift;

  my $cmd_def = my $cmd_cdef = my $cmd_legend = '';

  my $b2gb = 1024 * 1024 * 1024;

  $cmd_def  .= " DEF:mem_total_${counter}=\"$filepath\":mem_total:AVERAGE";
  $cmd_def  .= " DEF:mem_usage_${counter}=\"$filepath\":mem_usage:AVERAGE";
  $cmd_cdef .= " CDEF:usage_${counter}=mem_usage_${counter},100,/";
  $cmd_cdef .= " CDEF:free_${counter}=1,usage_${counter},-";
  $cmd_cdef .= " CDEF:total_${counter}=mem_total_${counter},$b2gb,/";

  if ( $metric eq "free" ) {
    $cmd_cdef .= " CDEF:graph_${counter}=total_${counter},free_${counter},*";
  }
  else {
    $cmd_cdef .= " CDEF:graph_${counter}=total_${counter},usage_${counter},*";
  }

  my $graph_type = ( $counter > 0 ) ? 'STACK' : 'AREA';

  my $label_space = get_formatted_label($label);
  my $group_space = get_formatted_label($group_label);

  # $uuid is used to form hypertext links in legends' tables
  my $uuid = get_uuid_from_filepath( $type, $filepath );

  $cmd_legend .= " ${graph_type}:graph_${counter}${color}:\" \"";
  $cmd_legend .= " COMMENT:\"$group_space  $label_space\"";
  $cmd_legend .= " GPRINT:graph_${counter}:AVERAGE:\" %6.1lf\"";
  $cmd_legend .= " GPRINT:graph_${counter}:MAX:\" %6.1lf    \"";
  $cmd_legend .= " PRINT:graph_${counter}:AVERAGE:\" %6.1lf $delimiter $url_item $delimiter $label $delimiter $color $delimiter $color\"";
  $cmd_legend .= " PRINT:graph_${counter}:MAX:\" %6.1lf $delimiter $label $delimiter ${group_label} $delimiter $uuid\"";
  $cmd_legend .= " COMMENT:\\n";

  # return the data
  my %result = (
    cmd_def    => $cmd_def,
    cmd_cdef   => $cmd_cdef,
    cmd_legend => $cmd_legend
  );

  return \%result;
}

sub graph_capacity_aggr {
  my $type        = shift;    # value: 'node'
  my $filepath    = shift;
  my $counter     = shift;
  my $color       = shift;
  my $label       = shift;
  my $group_label = shift;
  my $group_type  = shift;    # value: 'pool' (for pool or custom groups) or 'host'
  my $metric      = shift;
  my $url_item    = shift;

  my $cmd_def = my $cmd_cdef = my $cmd_legend = '';

  my $gb2tb = 1024;

  $cmd_def  .= " DEF:total_pure_${counter}=\"$filepath\":total:AVERAGE";
  $cmd_def  .= " DEF:free_pure_${counter}=\"$filepath\":free:AVERAGE";
  $cmd_cdef .= " CDEF:total_${counter}=total_pure_${counter},$gb2tb,/";
  $cmd_cdef .= " CDEF:free_${counter}=free_pure_${counter},$gb2tb,/";

  if ( $metric eq "free" ) {
    $cmd_cdef .= " CDEF:graph_${counter}=free_${counter},1,*";
  }
  else {
    $cmd_cdef .= " CDEF:graph_${counter}=total_${counter},free_${counter},-";
  }

  my $graph_type = ( $counter > 0 ) ? 'STACK' : 'AREA';

  my $label_space = get_formatted_label($label);
  my $group_space = get_formatted_label($group_label);

  # $uuid is used to form hypertext links in legends' tables
  my $uuid = get_uuid_from_filepath( $type, $filepath );

  $cmd_legend .= " ${graph_type}:graph_${counter}${color}:\" \"";
  $cmd_legend .= " COMMENT:\"$group_space  $label_space\"";
  $cmd_legend .= " GPRINT:graph_${counter}:AVERAGE:\" %6.2lf\"";
  $cmd_legend .= " GPRINT:graph_${counter}:MAX:\" %6.2lf    \"";
  $cmd_legend .= " PRINT:graph_${counter}:AVERAGE:\" %6.2lf $delimiter $url_item $delimiter $label $delimiter $color $delimiter $color\"";
  $cmd_legend .= " PRINT:graph_${counter}:MAX:\" %6.2lf $delimiter $label $delimiter ${group_label} $delimiter $uuid\"";
  $cmd_legend .= " COMMENT:\\n";

  # return the data
  my %result = (
    cmd_def    => $cmd_def,
    cmd_cdef   => $cmd_cdef,
    cmd_legend => $cmd_legend
  );

  return \%result;
}

sub graph_percent_aggr {
  my $type        = shift;    # value: 'node'
  my $filepath    = shift;
  my $counter     = shift;
  my $color       = shift;
  my $label       = shift;
  my $group_label = shift;
  my $group_type  = shift;    # value: 'pool' (for pool or custom groups) or 'host'
  my $metric      = shift;
  my $url_item    = shift;

  my $cmd_def = my $cmd_cdef = my $cmd_legend = '';

  $cmd_def  .= " DEF:metric_usage_${counter}=\"${filepath}\":${metric}:AVERAGE";
  $cmd_cdef .= " CDEF:usage_${counter}=metric_usage_${counter},1,*";

  my $graph_type = "LINE1";

  my $label_space = get_formatted_label($label);
  my $group_space = get_formatted_label($group_label);

  # $uuid is used to form hypertext links in legends' tables
  my $uuid = get_uuid_from_filepath( $type, $filepath );

  $cmd_legend .= " ${graph_type}:usage_${counter}${color}:\" \"";
  $cmd_legend .= " COMMENT:\"$group_space  $label_space\"";
  $cmd_legend .= " GPRINT:usage_${counter}:AVERAGE:\" %6.1lf\"";
  $cmd_legend .= " GPRINT:usage_${counter}:MAX:\" %6.1lf    \"";
  $cmd_legend .= " PRINT:usage_${counter}:AVERAGE:\" %6.1lf $delimiter $url_item $delimiter $label $delimiter $color $delimiter $color\"";
  $cmd_legend .= " PRINT:usage_${counter}:MAX:\" %6.1lf $delimiter $label $delimiter ${group_label} $delimiter $uuid\"";
  $cmd_legend .= " COMMENT:\\n";

  # return the data
  my %result = (
    cmd_def    => $cmd_def,
    cmd_cdef   => $cmd_cdef,
    cmd_legend => $cmd_legend
  );

  return \%result;
}

sub graph_read_write_aggr {
  my $type        = shift;    # value: 'node' or 'container'
  my $filepath    = shift;
  my $counter     = shift;
  my $color1      = shift;
  my $color2      = shift;
  my $label       = shift;
  my $group_label = shift;
  my $group_type  = shift;
  my $metric      = shift;
  my $url_item    = shift;

  # RRD command parts
  my $cmd_def    = my $cmd_cdef = my $cmd_legend_lower = my $cmd_legend_upper = '';
  my $graph_type = ( $counter > 0 ) ? 'STACK' : 'AREA';

  #my $graph_type = 'LINE1';

  my $division = 1024;
  my ( $metric_read, $metric_write );
  if ( $metric eq "net" ) {
    $metric_write = 'nic_byte_out';
    $metric_read  = 'nic_byte_in';
  }
  elsif ( $metric eq "sectors" ) {
    $metric_write = 'disk_wr_sectors';
    $metric_read  = 'disk_rd_sectors';
  }
  elsif ( $metric eq "net_usage" ) {
    $division     = 1;
    $graph_type   = 'LINE1';
    $metric_read  = 'nic_byte_in_usage';
    $metric_write = 'nic_byte_out_usage';
  }
  else {
    $metric_read  = 'disk_io_out';
    $metric_write = 'disk_io_in';
  }

  $cmd_def .= " DEF:write_${counter}=\"$filepath\":${metric_write}:AVERAGE";
  $cmd_def .= " DEF:read_${counter}=\"$filepath\":${metric_read}:AVERAGE";

  $cmd_cdef .= " CDEF:write_text_${counter}=write_${counter},$division,/";
  $cmd_cdef .= " CDEF:read_text_${counter}=read_${counter},$division,/";
  $cmd_cdef .= " CDEF:read_graph_${counter}=read_text_${counter},-1,*";

  my $label_space = get_formatted_label($label);
  my $group_space = get_formatted_label($group_label);

  # $uuid is used to form hypertext links in legends' tables
  my $uuid = get_uuid_from_filepath( $type, $filepath );

  $cmd_legend_lower .= " COMMENT:\"${group_space} ${label_space}\"";
  $cmd_legend_lower .= " ${graph_type}:read_graph_${counter}${color1}:\" \"";
  $cmd_legend_lower .= " GPRINT:read_text_${counter}:AVERAGE:\" %6.2lf\"";
  $cmd_legend_lower .= " GPRINT:read_text_${counter}:MAX:\" %6.2lf    \"";
  $cmd_legend_lower .= " PRINT:read_text_${counter}:AVERAGE:\" %6.2lf $delimiter $url_item $delimiter $label $delimiter ${color1} $delimiter ${color1}\"";
  $cmd_legend_lower .= " PRINT:read_text_${counter}:MAX:\" %6.2lf $delimiter $label $delimiter ${group_label} $delimiter $uuid\"";

  $cmd_legend_upper .= " ${graph_type}:write_text_${counter}${color2}: ";

  #$cmd_legend_lower .= " ${graph_type}:0${color2}:\" \"";
  $cmd_legend_lower .= " GPRINT:write_text_${counter}:AVERAGE:\" %6.2lf\"";
  $cmd_legend_lower .= " GPRINT:write_text_${counter}:MAX:\" %6.2lf\"";
  $cmd_legend_lower .= " PRINT:write_text_${counter}:AVERAGE:\" %6.2lf $delimiter ${color2}\"";
  $cmd_legend_lower .= " PRINT:write_text_${counter}:MAX:\" %6.2lf $delimiter $label $delimiter ${group_label}\"";
  $cmd_legend_lower .= " COMMENT:\\n";

  # return the data
  my %result = (
    cmd_def          => $cmd_def,
    cmd_cdef         => $cmd_cdef,
    cmd_legend_lower => $cmd_legend_lower,
    cmd_legend_upper => $cmd_legend_upper,
  );

  return \%result;
}

sub graph_iops_aggr {
  my $type        = shift;    # value: 'node' or 'container'
  my $filepath    = shift;
  my $counter     = shift;
  my $color1      = shift;
  my $color2      = shift;
  my $label       = shift;
  my $group_label = shift;
  my $group_type  = shift;
  my $metric      = shift;
  my $url_item    = shift;

  # RRD command parts
  my $cmd_def    = my $cmd_cdef = my $cmd_legend_lower = my $cmd_legend_upper = '';
  my $graph_type = ( $counter > 0 ) ? 'STACK' : 'AREA';

  #my $graph_type = 'LINE1';

  my $division = 1;
  my ( $metric_read, $metric_write );
  if ( $metric eq "disk_req" ) {
    $metric_write = 'disk_req_out';
    $metric_read  = 'disk_req_in';
  }
  elsif ( $metric eq "disk_ios" ) {
    if ( $type eq "host" ) {
      $metric_write = 'disk_io_write';
      $metric_read  = 'disk_io_read';
    }
    else {
      $metric_read  = 'disk_rd_ios';
      $metric_write = 'disk_wr_ios';
    }
  }

  $cmd_def .= " DEF:write_${counter}=\"$filepath\":${metric_write}:AVERAGE";
  $cmd_def .= " DEF:read_${counter}=\"$filepath\":${metric_read}:AVERAGE";

  $cmd_cdef .= " CDEF:write_text_${counter}=write_${counter},$division,/";
  $cmd_cdef .= " CDEF:read_text_${counter}=read_${counter},$division,/";
  $cmd_cdef .= " CDEF:read_graph_${counter}=read_text_${counter},-1,*";

  my $label_space = get_formatted_label($label);
  my $group_space = get_formatted_label($group_label);

  # $uuid is used to form hypertext links in legends' tables
  my $uuid = get_uuid_from_filepath( $type, $filepath );

  $cmd_legend_lower .= " COMMENT:\"${group_space} ${label_space}\"";
  $cmd_legend_lower .= " ${graph_type}:read_graph_${counter}${color1}:\" \"";
  $cmd_legend_lower .= " GPRINT:read_text_${counter}:AVERAGE:\" %6.0lf\"";
  $cmd_legend_lower .= " GPRINT:read_text_${counter}:MAX:\" %6.0lf    \"";
  $cmd_legend_lower .= " PRINT:read_text_${counter}:AVERAGE:\" %6.0lf $delimiter $url_item $delimiter $label $delimiter ${color1} $delimiter ${color1}\"";
  $cmd_legend_lower .= " PRINT:read_text_${counter}:MAX:\" %6.0lf $delimiter $label $delimiter ${group_label} $delimiter $uuid\"";

  $cmd_legend_upper .= " ${graph_type}:write_text_${counter}${color2}: ";

  #$cmd_legend_lower .= " ${graph_type}:0${color2}:\" \"";
  $cmd_legend_lower .= " GPRINT:write_text_${counter}:AVERAGE:\" %6.0lf\"";
  $cmd_legend_lower .= " GPRINT:write_text_${counter}:MAX:\" %6.0lf\"";
  $cmd_legend_lower .= " PRINT:write_text_${counter}:AVERAGE:\" %6.0lf $delimiter ${color2}\"";
  $cmd_legend_lower .= " PRINT:write_text_${counter}:MAX:\" %6.0lf $delimiter $label $delimiter ${group_label}\"";
  $cmd_legend_lower .= " COMMENT:\\n";

  # return the data
  my %result = (
    cmd_def          => $cmd_def,
    cmd_cdef         => $cmd_cdef,
    cmd_legend_lower => $cmd_legend_lower,
    cmd_legend_upper => $cmd_legend_upper,
  );

  return \%result;
}

sub graph_latency_aggr {
  my $type        = shift;    # value: 'node' or 'container'
  my $filepath    = shift;
  my $counter     = shift;
  my $color1      = shift;
  my $color2      = shift;
  my $label       = shift;
  my $group_label = shift;
  my $group_type  = shift;
  my $metric      = shift;
  my $url_item    = shift;

  # RRD command parts
  my $cmd_def    = my $cmd_cdef = my $cmd_legend_lower = my $cmd_legend_upper = '';
  my $graph_type = ( $counter > 0 ) ? 'LINE1' : 'LINE1';

  #my $graph_type = 'LINE1';

  my $division = 1;
  my ( $metric_read, $metric_write );
  $metric_read  = 'disk_iord_ticks';
  $metric_write = 'disk_iowr_ticks';

  $cmd_def .= " DEF:write_${counter}=\"$filepath\":${metric_write}:AVERAGE";
  $cmd_def .= " DEF:read_${counter}=\"$filepath\":${metric_read}:AVERAGE";

  $cmd_cdef .= " CDEF:write_text_${counter}=write_${counter},$division,/";
  $cmd_cdef .= " CDEF:read_text_${counter}=read_${counter},$division,/";
  $cmd_cdef .= " CDEF:read_graph_${counter}=read_text_${counter},-1,*";

  my $label_space = get_formatted_label($label);
  my $group_space = get_formatted_label($group_label);

  # $uuid is used to form hypertext links in legends' tables
  my $uuid = get_uuid_from_filepath( $type, $filepath );

  $cmd_legend_lower .= " COMMENT:\"${group_space} ${label_space}\"";
  $cmd_legend_lower .= " ${graph_type}:read_graph_${counter}${color1}:\" \"";
  $cmd_legend_lower .= " GPRINT:read_text_${counter}:AVERAGE:\" %6.2lf\"";
  $cmd_legend_lower .= " GPRINT:read_text_${counter}:MAX:\" %6.2lf    \"";
  $cmd_legend_lower .= " PRINT:read_text_${counter}:AVERAGE:\" %6.2lf $delimiter $url_item $delimiter $label $delimiter ${color1} $delimiter ${color1}\"";
  $cmd_legend_lower .= " PRINT:read_text_${counter}:MAX:\" %6.2lf $delimiter $label $delimiter ${group_label} $delimiter $uuid\"";

  $cmd_legend_upper .= " ${graph_type}:write_text_${counter}${color2}: ";

  #$cmd_legend_lower .= " ${graph_type}:0${color2}:\" \"";
  $cmd_legend_lower .= " GPRINT:write_text_${counter}:AVERAGE:\" %6.2lf\"";
  $cmd_legend_lower .= " GPRINT:write_text_${counter}:MAX:\" %6.2lf\"";
  $cmd_legend_lower .= " PRINT:write_text_${counter}:AVERAGE:\" %6.2lf $delimiter ${color2}\"";
  $cmd_legend_lower .= " PRINT:write_text_${counter}:MAX:\" %6.2lf $delimiter $label $delimiter ${group_label}\"";
  $cmd_legend_lower .= " COMMENT:\\n";

  # return the data
  my %result = (
    cmd_def          => $cmd_def,
    cmd_cdef         => $cmd_cdef,
    cmd_legend_lower => $cmd_legend_lower,
    cmd_legend_upper => $cmd_legend_upper,
  );

  return \%result;
}

sub graph_number_aggr {
  my $type        = shift;    # value: 'node' or 'container'
  my $filepath    = shift;
  my $counter     = shift;
  my $color1      = shift;
  my $color2      = shift;
  my $label       = shift;
  my $group_label = shift;
  my $group_type  = shift;
  my $metric      = shift;
  my $url_item    = shift;

  # RRD command parts
  my $cmd_def    = my $cmd_cdef = my $cmd_legend_lower = my $cmd_legend_upper = '';
  my $graph_type = ( $counter > 0 ) ? 'STACK' : 'AREA';

  #my $graph_type = 'LINE1';

  my $division = 1;
  my ( $metric_read, $metric_write );
  if ( $metric eq "packet_drop" ) {
    if ( $type eq "host" ) {
      $metric_write = 'nic_pkg_tx_speed';
      $metric_read  = 'nic_pkg_rx_speed';
    }
    else {
      $metric_write = 'nic_tx_drop_speed';
      $metric_read  = 'nic_rx_drop_speed';
    }
  }
  elsif ( $metric eq "packets" ) {
    $metric_write = 'nic_pkg_send';
    $metric_read  = 'nic_pkg_rcv';
  }

  $cmd_def .= " DEF:write_${counter}=\"$filepath\":${metric_write}:AVERAGE";
  $cmd_def .= " DEF:read_${counter}=\"$filepath\":${metric_read}:AVERAGE";

  $cmd_cdef .= " CDEF:write_text_${counter}=write_${counter},$division,/";
  $cmd_cdef .= " CDEF:read_text_${counter}=read_${counter},$division,/";
  $cmd_cdef .= " CDEF:read_graph_${counter}=read_text_${counter},-1,*";

  my $label_space = get_formatted_label($label);
  my $group_space = get_formatted_label($group_label);

  # $uuid is used to form hypertext links in legends' tables
  my $uuid = get_uuid_from_filepath( $type, $filepath );

  $cmd_legend_lower .= " COMMENT:\"${group_space} ${label_space}\"";
  $cmd_legend_lower .= " ${graph_type}:read_graph_${counter}${color1}:\" \"";
  $cmd_legend_lower .= " GPRINT:read_text_${counter}:AVERAGE:\" %6.0lf\"";
  $cmd_legend_lower .= " GPRINT:read_text_${counter}:MAX:\" %6.0lf    \"";
  $cmd_legend_lower .= " PRINT:read_text_${counter}:AVERAGE:\" %6.0lf $delimiter $url_item $delimiter $label $delimiter ${color1} $delimiter ${color1}\"";
  $cmd_legend_lower .= " PRINT:read_text_${counter}:MAX:\" %6.0lf $delimiter $label $delimiter ${group_label} $delimiter $uuid\"";

  $cmd_legend_upper .= " ${graph_type}:write_text_${counter}${color2}: ";

  #$cmd_legend_lower .= " ${graph_type}:0${color2}:\" \"";
  $cmd_legend_lower .= " GPRINT:write_text_${counter}:AVERAGE:\" %6.0lf\"";
  $cmd_legend_lower .= " GPRINT:write_text_${counter}:MAX:\" %6.0lf\"";
  $cmd_legend_lower .= " PRINT:write_text_${counter}:AVERAGE:\" %6.0lf $delimiter ${color2}\"";
  $cmd_legend_lower .= " PRINT:write_text_${counter}:MAX:\" %6.0lf $delimiter $label $delimiter ${group_label}\"";
  $cmd_legend_lower .= " COMMENT:\\n";

  # return the data
  my %result = (
    cmd_def          => $cmd_def,
    cmd_cdef         => $cmd_cdef,
    cmd_legend_lower => $cmd_legend_lower,
    cmd_legend_upper => $cmd_legend_upper,
  );

  return \%result;
}

################################################################################

sub get_uuid_from_filepath {
  my $type     = shift;    # value: 'vm' or 'host'
  my $filepath = shift;

  my $uuid;
  $filepath =~ m/\/FusionCompute\/(.*)\/(.*)\.rrd/;
  $uuid = $2;

  return $uuid;
}

################################################################################

1;
