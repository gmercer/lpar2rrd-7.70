# NutanixGraph.pm
# keep Nutanix graph generation in one place, if possible
# (separated from `detail-graph-cgi.pl`)

package NutanixGraph;

use strict;
use warnings;

use Data::Dumper;

use NutanixDataWrapper;

defined $ENV{INPUTDIR} || warn( localtime() . ': INPUTDIR undefined, config etc/lpar2rrd.cfg probably has not been loaded ' . __FILE__ . ':' . __LINE__ ) && exit 1;

my $inputdir = $ENV{INPUTDIR};
my $wrkdir   = "$inputdir/data";

my $hosts_path = "$wrkdir/NUTANIX";
my $vms_path   = "$wrkdir/NUTANIX/VM";

# helper delimiter: used to convert graph legends to HTML tables in `detail-graph-cgi.pl`
my $delimiter = 'XORUX';

################################################################################

# current usage in detail-graph-cgi.pl
#   graph_nutanix( $host, $server, $lpar, $time, $name_out, $type_sam, $detail, $start_unix, $end_unix );
#   graph_nutanix_totals( $host, $server, $lpar, $time, $name_out, $type_sam, $detail, $start_unix, $end_unix );
# and custom.pl
#   multiview_nutanixvm( ... );

################################################################################

# assemble graph header
#   params: $type, $uuid, $context
#   output: "<platform> <context> @ $type <label-$type-$uuid>"
sub get_header {
  my $type    = shift;
  my $uuid    = shift;
  my $context = shift;

  my $label = NutanixDataWrapper::get_label( $type, $uuid );

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

sub get_params_memory {
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
    elsif ( $type eq 'latency-total' ) {
      $unit = 'ms';
      $result .= " --vertical-label=\"Total - $unit\"";
    }
    elsif ( $type eq 'iops' ) {
      $unit = 'IOPS';
      $result .= " --vertical-label=\"Read - $unit - Write\"";
    }
    elsif ( $type eq "vm-total" ) {
      $unit = 'MB/s';
      $result .= " --vertical-label=\"Total - $unit\"";
    }
  }
  else {
    $result .= " --vertical-label=\"Read - $unit - Write\"";
  }

  return $result;
}

################################################################################

sub graph_cpu {
  my $type        = shift;    # value: 'host' or 'vm'
  my $uuid        = shift;
  my $metric_type = shift;    # value: 'percent' or 'cores'
  my $skip_acl    = shift || 0; # optional flag

  # necessary information
  my $rrd = '';
  if ( $type eq 'host' ) {
    $rrd = NutanixDataWrapper::get_filepath_rrd( { 'type' => 'host', 'uuid' => $uuid, skip_acl => $skip_acl } );
  }
  elsif ( $type eq 'vm' ) {
    $rrd = NutanixDataWrapper::get_filepath_rrd( { 'type' => 'vm', 'uuid' => $uuid, skip_acl => $skip_acl } );
  }

  # RRD command parts
  my $cmd_params = get_params_cpu();
  my $cmd_def    = my $cmd_cdef = my $cmd_legend = '';

  my $metric = 'cpu';
  if ( $metric_type eq 'cores' ) {    # 'cpu_cores' are the same for both 'vm' and 'host'
    $metric = 'cpu_cores';
  }
  elsif ( $type eq 'host' ) {
    $metric = 'cpu_avg';

    #$metric = 'cpu_usage_percent';
  }
  elsif ( $type eq 'vm' ) {
    $metric = 'cpu';
  }
  $cmd_def .= " DEF:$metric=\"$rrd\":$metric:AVERAGE";
  if ( $metric_type eq 'percent' ) {
    $cmd_cdef .= " CDEF:cpu_graph=$metric,100,*";
  }
  else {    # 'cores'
    $cmd_cdef .= " CDEF:cpu_graph=$metric";

    # add a metric for available cores, kind of like memory_total
    $cmd_def  .= " DEF:cpu_core_count=\"$rrd\":cpu_core_count:AVERAGE";
    $cmd_cdef .= " CDEF:core_count_graph=cpu_core_count";
  }
  if ( $metric_type eq 'cores' ) {
    $cmd_legend .= " COMMENT:\"[cores]               Avrg       Max\\n\"";
    $cmd_legend .= " LINE1:cpu_graph#FF0000:\" Utilization   \"";
    $cmd_legend .= " GPRINT:cpu_graph:AVERAGE:\" %6.1lf\"";
    $cmd_legend .= " GPRINT:cpu_graph:MAX:\" %6.1lf\"";
    $cmd_legend .= " COMMENT:\\n";
  }
  else {
    $cmd_legend .= " COMMENT:\"[%]                   Avrg       Max\\n\"";
    $cmd_legend .= " LINE1:cpu_graph#FF0000:\" Utilization   \"";
    $cmd_legend .= " GPRINT:cpu_graph:AVERAGE:\" %6.0lf\"";
    $cmd_legend .= " GPRINT:cpu_graph:MAX:\" %6.0lf\"";
    $cmd_legend .= " COMMENT:\\n";
  }
  if ( $metric_type eq 'cores' ) {
    $cmd_legend .= " LINE1:core_count_graph#000000:\" Available     \"";
    $cmd_legend .= " GPRINT:core_count_graph:AVERAGE:\" %6.1lf\"";
    $cmd_legend .= " GPRINT:core_count_graph:MAX:\" %6.1lf\"";
    $cmd_legend .= " COMMENT:\\n";
  }

  # return the data
  my %result = (
    cmd_params => $cmd_params,
    cmd_def    => $cmd_def,
    cmd_cdef   => $cmd_cdef,
    cmd_legend => $cmd_legend,
  );

  return \%result;
}

sub graph_memory {
  my $type = shift;    # value: 'host' or 'vm'
  my $uuid = shift;
  my $skip_acl = shift || 0; # optional flag

  # necessary information
  my $rrd = '';
  if ( $type eq 'host' ) {
    $rrd = NutanixDataWrapper::get_filepath_rrd( { 'type' => 'host', 'uuid' => $uuid, skip_acl => $skip_acl } );
  }
  elsif ( $type eq 'vm' ) {
    $rrd = NutanixDataWrapper::get_filepath_rrd( { 'type' => 'vm', 'uuid' => $uuid, skip_acl => $skip_acl } );
  }

  # RRD command parts
  my $cmd_params = get_params_memory();
  my $cmd_def    = my $cmd_cdef = my $cmd_legend = '';

  my ( $metric_total, $metric_free );
  if ( $type eq 'host' ) {
    $metric_total = 'memory_total';
    $metric_free  = 'memory_free';
  }
  elsif ( $type eq 'vm' ) {
    $metric_total = 'memory';
    $metric_free  = 'memory_int_free';
  }
  $cmd_def .= " DEF:mem_total=\"$rrd\":${metric_total}:AVERAGE";
  $cmd_def .= " DEF:mem_free=\"$rrd\":${metric_free}:AVERAGE";

  my $b2gib   = 1024**3;
  my $kib2gib = 1024**2;
  if ( $type eq 'host' ) {
    $cmd_cdef .= " CDEF:total=mem_total,$kib2gib,/";
  }
  elsif ( $type eq 'vm' ) {
    $cmd_cdef .= " CDEF:total=mem_total,$kib2gib,/";
  }
  $cmd_cdef .= " CDEF:free=mem_free,$kib2gib,/";
  $cmd_cdef .= " CDEF:used=total,free,-";

  $cmd_legend .= " COMMENT:\"[GB]                       Avrg       Max\\n\"";
  $cmd_legend .= " AREA:used#FF0000:\" Memory used        \"";
  $cmd_legend .= " GPRINT:used:AVERAGE:\" %6.1lf\"";
  $cmd_legend .= " GPRINT:used:MAX:\" %6.1lf\"";
  $cmd_legend .= " COMMENT:\\n";
  $cmd_legend .= " STACK:free#00FF00:\" Memory free        \"";
  $cmd_legend .= " GPRINT:free:AVERAGE:\" %6.1lf\"";
  $cmd_legend .= " GPRINT:free:MAX:\" %6.1lf\"";
  $cmd_legend .= " COMMENT:\\n";

  if ( $type eq 'vm' ) {    # graph total VM's memory in case `free` isn't reported
    $cmd_legend .= " LINE1:total#0000FF:\" Memory total       \"";
    $cmd_legend .= " GPRINT:total:AVERAGE:\" %6.1lf\"";
    $cmd_legend .= " GPRINT:total:MAX:\" %6.1lf\"";
    $cmd_legend .= " COMMENT:\\n";
  }

  # return the data
  my %result = (
    cmd_params => $cmd_params,
    cmd_def    => $cmd_def,
    cmd_cdef   => $cmd_cdef,
    cmd_legend => $cmd_legend,
  );

  return \%result;
}

sub graph_lan {
  my $type = shift;    # value: 'host' or 'vm'
  my $uuid = shift;
  my $skip_acl = shift || 0; # optional flag

  # necessary information
  my $rrd = '';
  if ( $type eq 'host' ) {
    $rrd = NutanixDataWrapper::get_filepath_rrd( { 'type' => 'lan', 'uuid' => $uuid, skip_acl => $skip_acl } );
  }
  elsif ( $type eq 'vm' ) {
    $rrd = NutanixDataWrapper::get_filepath_rrd( { 'type' => 'vm', 'uuid' => $uuid, skip_acl => $skip_acl } );
  }

  # RRD command parts
  my $cmd_params = get_params_lan();
  my $cmd_def    = my $cmd_cdef = my $cmd_legend = '';

  $cmd_def .= " DEF:transmitted=\"$rrd\":net_transmitted:AVERAGE";
  $cmd_def .= " DEF:received=\"$rrd\":net_received:AVERAGE";

  my $b2mb = 1000**2;
  $cmd_cdef .= " CDEF:transmitted_mbps=transmitted,$b2mb,/";
  $cmd_cdef .= " CDEF:received_mbps=received,$b2mb,/";
  $cmd_cdef .= " CDEF:received_graph=0,received_mbps,-";

  $cmd_legend .= " COMMENT:\"[MB/s]               Avrg       Max\\n\"";
  $cmd_legend .= " LINE1:received_graph#FF0000:\" Read         \"";
  $cmd_legend .= " GPRINT:received_mbps:AVERAGE:\" %6.2lf\"";
  $cmd_legend .= " GPRINT:received_mbps:MAX:\" %6.2lf\"";
  $cmd_legend .= " COMMENT:\\n";
  $cmd_legend .= " LINE1:transmitted_mbps#0000FF:\" Write        \"";
  $cmd_legend .= " GPRINT:transmitted_mbps:AVERAGE:\" %6.2lf\"";
  $cmd_legend .= " GPRINT:transmitted_mbps:MAX:\" %6.2lf\"";
  $cmd_legend .= " COMMENT:\\n";

  # return the data
  my %result = (
    cmd_params => $cmd_params,
    cmd_def    => $cmd_def,
    cmd_cdef   => $cmd_cdef,
    cmd_legend => $cmd_legend,
  );

  return \%result;
}

sub graph_storage {
  my $type        = shift;    # value: 'host', 'sc', or 'vm'
  my $uuid        = shift;
  my $metric_type = shift;    # value: 'vbd', 'iops' or 'latency'
  my $skip_acl    = shift || 0; # optional flag

  # necessary information
  my $rrd = '';
  if ( $type eq 'host' ) {
    $rrd = NutanixDataWrapper::get_filepath_rrd( { 'type' => 'disk', 'uuid' => $uuid, skip_acl => $skip_acl } );
  }
  elsif ( $type eq 'vm' ) {
    $rrd = NutanixDataWrapper::get_filepath_rrd( { 'type' => 'vm', 'uuid' => $uuid, skip_acl => $skip_acl } );
  }
  elsif ( $type eq 'sc' ) {
    $rrd = NutanixDataWrapper::get_filepath_rrd( { 'type' => 'container', 'uuid' => $uuid, skip_acl => $skip_acl } );
  }
  elsif ( $type eq 'vd' ) {
    $rrd = NutanixDataWrapper::get_filepath_rrd( { 'type' => 'vdisk', 'uuid' => $uuid, skip_acl => $skip_acl } );
  }
  elsif ( $type eq 'sp' ) {
    $rrd = NutanixDataWrapper::get_filepath_rrd( { 'type' => 'pool', 'uuid' => $uuid, skip_acl => $skip_acl } );
  }

  # RRD command parts
  my $cmd_params = get_params_storage($metric_type);
  my $cmd_def    = my $cmd_cdef = my $cmd_legend = '';

  my ( $metric_read, $metric_write, $metric );
  $metric_read  = 'vbd_read';
  $metric_write = 'vbd_write';
  if ( $metric_type eq 'vbd' && $type eq 'vm' ) {
    $metric = 'vbd_total';
  }
  if ( $metric_type eq 'iops' ) {
    $metric_read  = 'vbd_iops_read';
    $metric_write = 'vbd_iops_write';
  }
  elsif ( $metric_type eq 'latency' ) {
    if ( $type ne 'vm' ) {
      $metric = 'vbd_total_latency';
    }
    else {
      $metric_read  = 'vbd_read_latency';
      $metric_write = 'vbd_write_latency';
    }
  }

  if ( ( $metric_type eq 'latency' && $type ne 'vm' ) || ( $metric_type eq 'vbd' && $type eq 'vm' ) ) {
    $cmd_def .= " DEF:${metric}=\"$rrd\":${metric}:AVERAGE";
  }
  else {
    $cmd_def .= " DEF:${metric_write}=\"$rrd\":${metric_write}:AVERAGE";
    $cmd_def .= " DEF:${metric_read}=\"$rrd\":${metric_read}:AVERAGE";
  }

  if ( $metric_type eq 'vbd' ) {
    if ( $type eq 'vm' ) {
      my $b2mib = 1000**2;
      $cmd_cdef .= " CDEF:total_graph=${metric},$b2mib,/";
    }
    else {
      my $b2mib = 1000**2;
      $cmd_cdef .= " CDEF:write_graph=${metric_write},$b2mib,/";
      $cmd_cdef .= " CDEF:read_graph=${metric_read},$b2mib,/";
      $cmd_cdef .= " CDEF:read_neg=0,read_graph,-";
    }
  }
  elsif ( $metric_type eq 'iops' ) {
    $cmd_cdef .= " CDEF:write_graph=${metric_write}";
    $cmd_cdef .= " CDEF:read_graph=${metric_read}";
    $cmd_cdef .= " CDEF:read_neg=0,read_graph,-";
  }
  elsif ( $metric_type eq 'latency' ) {
    if ( $type eq 'vm' ) {
      $cmd_cdef .= " CDEF:write_graph=${metric_write},1000,/";
      $cmd_cdef .= " CDEF:read_graph=${metric_read},1000,/";
      $cmd_cdef .= " CDEF:read_neg=0,read_graph,-";
    }
    else {
      $cmd_cdef .= " CDEF:total_graph=${metric},1000,/";
    }
  }

  if ( $metric_type eq 'iops' ) {
    $cmd_legend .= " COMMENT:\"[iops]                Avrg      Max\\n\"";
  }
  elsif ( $metric_type eq 'latency' ) {
    $cmd_legend .= " COMMENT:\"[millisec]            Avrg      Max\\n\"";
  }
  else {
    $cmd_legend .= " COMMENT:\"[MB/s]                Avrg      Max\\n\"";
  }

  if ( ( $metric_type eq 'latency' && $type ne 'vm' ) || ( $metric_type eq 'vbd' && $type eq 'vm' ) ) {
    $cmd_legend .= " LINE1:total_graph#0000FF:\" Total        \"";
    $cmd_legend .= " GPRINT:total_graph:AVERAGE:\" %6.2lf\"";
    $cmd_legend .= " GPRINT:total_graph:MAX:\" %6.2lf\"";
    $cmd_legend .= " COMMENT:\\n";
  } elsif($metric_type eq 'iops') {
    $cmd_legend .= " LINE1:write_graph#0000FF:\" Write        \"";
    $cmd_legend .= " GPRINT:write_graph:AVERAGE:\" %6.0lf\"";
    $cmd_legend .= " GPRINT:write_graph:MAX:\" %6.0lf\"";
    $cmd_legend .= " COMMENT:\\n";
    $cmd_legend .= " LINE1:read_neg#FF0000:\" Read         \"";
    $cmd_legend .= " GPRINT:read_graph:AVERAGE:\" %6.0lf\"";
    $cmd_legend .= " GPRINT:read_graph:MAX:\" %6.0lf\"";
    $cmd_legend .= " COMMENT:\\n";
  } else {
    $cmd_legend .= " LINE1:write_graph#0000FF:\" Write        \"";
    $cmd_legend .= " GPRINT:write_graph:AVERAGE:\" %6.2lf\"";
    $cmd_legend .= " GPRINT:write_graph:MAX:\" %6.2lf\"";
    $cmd_legend .= " COMMENT:\\n";
    $cmd_legend .= " LINE1:read_neg#FF0000:\" Read         \"";
    $cmd_legend .= " GPRINT:read_graph:AVERAGE:\" %6.2lf\"";
    $cmd_legend .= " GPRINT:read_graph:MAX:\" %6.2lf\"";
    $cmd_legend .= " COMMENT:\\n";
  }

  # return the data
  my %result = (
    cmd_params => $cmd_params,
    cmd_def    => $cmd_def,
    cmd_cdef   => $cmd_cdef,
    cmd_legend => $cmd_legend,
  );

  return \%result;
}

################################################################################

# to be moved to NutanixDataWrapper
sub get_uuid_from_filepath {
  my $type     = shift;    # value: 'vm' or 'host'
  my $filepath = shift;

  my $uuid;
  if ( $type eq 'vm' ) {
    $filepath =~ m/\/NUTANIX\/VM\/(.*)\.rrd/;
    $uuid = $1;
  }
  elsif ( $type eq 'host' ) {
    $filepath =~ m/\/NUTANIX\/HOST\/(.*)\.rrd/;
    $uuid = $1;
  }
  elsif ( $type eq 'sc' ) {
    $filepath =~ m/\/NUTANIX\/SC\/(.*)\.rrd/;
    $uuid = $1;
  }
  elsif ( $type eq 'vdisk' ) {
    $filepath =~ m/\/NUTANIX\/VD\/(.*)\.rrd/;
    $uuid = $1;
  }
  elsif ( $type eq 'vg' ) {
    $filepath =~ m/\/NUTANIX\/VG\/(.*)\.rrd/;
    $uuid = $1;
  }
  elsif ( $type eq 'sp' ) {
    $filepath =~ m/\/NUTANIX\/SP\/(.*)\.rrd/;
    $uuid = $1;
  }
  else {
    $filepath =~ m/\/NUTANIX\/(.*)\/(.*)\.rrd/;
    $uuid = $2;
  }

  return $uuid;
}

################################################################################

# more specific subroutine, assumes that the caller has already figured out filepath, label, etc.
#   params: $type, $filepath, $counter, $color, $label,…
#   return: hash w/ def, cdef, legend

sub graph_cpu_aggr {
  my $type        = shift;    # value: 'host' or 'vm'
  my $metric_type = shift;    # value: 'percent' or 'cores'
  my $filepath    = shift;
  my $counter     = shift;
  my $color       = shift;
  my $label       = shift;
  my $group_label = shift;
  my $group_type  = shift;    # value: 'pool' (for pool or custom groups) or 'host'

  # RRD command parts
  my $cmd_def = my $cmd_cdef = my $cmd_legend = '';
  my ( $metric, $graph_type );
  if ( $metric_type eq 'cores' ) {    # 'cpu_cores' are the same for both 'vm' and 'host'
    $metric     = 'cpu_cores';
    $graph_type = ( $counter > 0 ) ? 'STACK' : 'AREA';
  }
  elsif ( $type eq 'host' ) {
    $metric     = 'cpu_avg';
    $graph_type = 'LINE1';
  }
  elsif ( $type eq 'vm' ) {
    $metric     = 'cpu';
    $graph_type = 'LINE1';
  }
  $cmd_def .= " DEF:${metric}_${counter}=\"${filepath}\":${metric}:AVERAGE";

  if ( $metric_type eq 'percent' ) {
    $cmd_cdef .= " CDEF:cpu_graph_${counter}=${metric}_${counter},100,*";
  }
  else {    # 'cores'
    $cmd_cdef .= " CDEF:cpu_graph_${counter}=${metric}_${counter}";
  }

  # $url_item is used in `ret_graph_param` to transform legends' table in `detail-graph-cgi.pl`
  my $url_item = "nutanix-$type-cpu-${metric_type}-aggr";
  if ( $type eq 'vm' && $group_type eq 'pool' ) {    # VMs under host
    $url_item = "nutanix-vm-cpu-${metric_type}-aggr";
  }
  elsif ( $type eq 'vm' ) {                          # ad-hoc assignment for Custom groups
    $url_item = "custom-nutanixvm-cpu-${metric_type}";
  }
  my $label_space = get_formatted_label($label);
  my $group_space = get_formatted_label($group_label);

  # $uuid is used to form hypertext links in legends' tables
  my $uuid = get_uuid_from_filepath( $type, $filepath );

  if ( $metric_type eq 'percent' ) {
    $cmd_legend .= " ${graph_type}:cpu_graph_${counter}${color}:\" \"";
    $cmd_legend .= " COMMENT:\"$group_space  $label_space\"";
    $cmd_legend .= " GPRINT:cpu_graph_${counter}:AVERAGE:\" %6.0lf\"";
    $cmd_legend .= " GPRINT:cpu_graph_${counter}:MAX:\" %6.0lf    \"";
    $cmd_legend .= " PRINT:cpu_graph_${counter}:AVERAGE:\" %6.0lf $delimiter $url_item $delimiter $label $delimiter $color $delimiter $color\"";
    $cmd_legend .= " PRINT:cpu_graph_${counter}:MAX:\" %6.0lf $delimiter $label $delimiter ${group_label} $delimiter $uuid\"";
    $cmd_legend .= " COMMENT:\\n";
  } else {
    $cmd_legend .= " ${graph_type}:cpu_graph_${counter}${color}:\" \"";
    $cmd_legend .= " COMMENT:\"$group_space  $label_space\"";
    $cmd_legend .= " GPRINT:cpu_graph_${counter}:AVERAGE:\" %6.1lf\"";
    $cmd_legend .= " GPRINT:cpu_graph_${counter}:MAX:\" %6.1lf    \"";
    $cmd_legend .= " PRINT:cpu_graph_${counter}:AVERAGE:\" %6.1lf $delimiter $url_item $delimiter $label $delimiter $color $delimiter $color\"";
    $cmd_legend .= " PRINT:cpu_graph_${counter}:MAX:\" %6.1lf $delimiter $label $delimiter ${group_label} $delimiter $uuid\"";
    $cmd_legend .= " COMMENT:\\n";
  }

  # return the data
  my %result = (
    cmd_def    => $cmd_def,
    cmd_cdef   => $cmd_cdef,
    cmd_legend => $cmd_legend
  );

  return \%result;
}

sub graph_memory_aggr {
  my $type        = shift;    # value: 'host' or 'vm'
  my $metric_type = shift;    # value: 'free' or 'used'
  my $filepath    = shift;
  my $counter     = shift;
  my $color       = shift;
  my $label       = shift;
  my $group_label = shift;
  my $group_type  = shift;    # value: 'pool' (for pool or custom groups) or 'host'

  # RRD command parts
  my $cmd_def = my $cmd_cdef = my $cmd_legend = '';
  my ( $metric_total, $metric_free, $graph_type );
  if ( $type eq 'host' ) {
    $metric_total = 'memory_total';
    $metric_free  = 'memory_free';
  }
  elsif ( $type eq 'vm' ) {
    $metric_total = 'memory';
    $metric_free  = 'memory_int_free';
  }
  $graph_type = ( $counter > 0 ) ? 'STACK' : 'AREA';
  $cmd_def .= " DEF:mem_total_${counter}=\"${filepath}\":${metric_total}:AVERAGE";
  $cmd_def .= " DEF:mem_free_${counter}=\"${filepath}\":${metric_free}:AVERAGE";

  my $b2gib   = 1024**3;
  my $kib2gib = 1024**2;
  if ( $type eq 'host' ) {
    $cmd_cdef .= " CDEF:total_${counter}=mem_total_${counter},$kib2gib,/";
  }
  elsif ( $type eq 'vm' ) {
    $cmd_cdef .= " CDEF:total_${counter}=mem_total_${counter},$kib2gib,/";
  }
  $cmd_cdef .= " CDEF:free_${counter}=mem_free_${counter},$kib2gib,/";
  $cmd_cdef .= " CDEF:used_${counter}=total_${counter},free_${counter},-";

  # $url_item is used in `ret_graph_param` to transform legends' table in `detail-graph-cgi.pl`
  my $url_item = "nutanix-$type-memory-${metric_type}-aggr";
  if ( $type eq 'vm' && $group_type eq 'pool' ) {    # VMs under host
    $url_item = "nutanix-vm-memory-${metric_type}-aggr";
  }
  elsif ( $type eq 'vm' ) {                          # ad-hoc assignment for Custom groups / Pool
    $url_item = "custom-nutanixvm-memory-${metric_type}";
  }
  my $label_space = get_formatted_label($label);
  my $group_space = get_formatted_label($group_label);

  # $uuid is used to form hypertext links in legends' tables
  my $uuid = get_uuid_from_filepath( $type, $filepath );

  $cmd_legend .= " ${graph_type}:${metric_type}_${counter}${color}:\" \"";
  $cmd_legend .= " COMMENT:\"$group_space  $label_space\"";
  $cmd_legend .= " GPRINT:${metric_type}_${counter}:AVERAGE:\" %6.1lf\"";
  $cmd_legend .= " GPRINT:${metric_type}_${counter}:MAX:\" %6.1lf    \"";
  $cmd_legend .= " PRINT:${metric_type}_${counter}:AVERAGE:\" %6.1lf $delimiter $url_item $delimiter $label $delimiter $color $delimiter $color\"";
  $cmd_legend .= " PRINT:${metric_type}_${counter}:MAX:\" %6.1lf $delimiter $label $delimiter ${group_label} $delimiter $uuid\"";
  $cmd_legend .= " COMMENT:\\n";

  # return the data
  my %result = (
    cmd_def    => $cmd_def,
    cmd_cdef   => $cmd_cdef,
    cmd_legend => $cmd_legend
  );

  return \%result;
}

sub graph_lan_aggr {
  my $type        = shift;    # value: 'host' or 'vm'
  my $filepath    = shift;
  my $counter     = shift;
  my $color1      = shift;
  my $color2      = shift;
  my $label       = shift;
  my $group_label = shift;    # either host's (graph interfaces), or pool's (graph VMs)
  my $group_type  = shift;

  # RRD command parts
  my $cmd_def    = my $cmd_cdef = my $cmd_legend_lower = my $cmd_legend_upper = '';
  my $graph_type = ( $counter > 0 ) ? 'STACK' : 'AREA';
  my $b2mb       = 1000**2;
  $cmd_def  .= " DEF:transmitted_${counter}=\"$filepath\":net_transmitted:AVERAGE";
  $cmd_def  .= " DEF:received_${counter}=\"$filepath\":net_received:AVERAGE";
  $cmd_cdef .= " CDEF:transmitted_mbps_${counter}=transmitted_${counter},$b2mb,/";
  $cmd_cdef .= " CDEF:received_mbps_${counter}=received_${counter},$b2mb,/";

  $cmd_cdef .= " CDEF:received_graph_${counter}=received_mbps_${counter},-1,*";

  # $url_item is used in `ret_graph_param` to transform legends' table in `detail-graph-cgi.pl`
  my $url_item = "nutanix-$type-lan-aggr";
  if ( $type eq 'vm' && $group_type eq 'pool' ) {
    $url_item = "nutanix-$type-lan-aggr";
  }
  elsif ( $type eq 'vm' ) {    # ad-hoc assignment for Custom groups; perhaps make a separate argument
    $url_item = 'custom-nutanixvm-lan';
  }
  my $label_space = get_formatted_label($label);
  my $group_space = get_formatted_label($group_label);

  # $uuid is used to form hypertext links in legends' tables
  my $uuid = get_uuid_from_filepath( $type, $filepath );

  $cmd_legend_lower .= " COMMENT:\"${group_space} ${label_space}\"";
  $cmd_legend_lower .= " ${graph_type}:received_graph_${counter}${color1}:\" \"";
  $cmd_legend_lower .= " GPRINT:received_mbps_${counter}:AVERAGE:\" %6.2lf\"";
  $cmd_legend_lower .= " GPRINT:received_mbps_${counter}:MAX:\" %6.2lf    \"";
  $cmd_legend_lower .= " PRINT:received_mbps_${counter}:AVERAGE:\" %6.2lf $delimiter $url_item $delimiter $label $delimiter ${color1} $delimiter ${color1}\"";
  $cmd_legend_lower .= " PRINT:received_mbps_${counter}:MAX:\" %6.2lf $delimiter $label $delimiter ${group_label} $delimiter $uuid\"";

  $cmd_legend_upper .= " ${graph_type}:transmitted_mbps_${counter}${color2}: ";
  $cmd_legend_lower .= " ${graph_type}:0${color2}:\" \"";
  $cmd_legend_lower .= " GPRINT:transmitted_mbps_${counter}:AVERAGE:\" %6.2lf\"";
  $cmd_legend_lower .= " GPRINT:transmitted_mbps_${counter}:MAX:\" %6.2lf\"";
  $cmd_legend_lower .= " PRINT:transmitted_mbps_${counter}:AVERAGE:\" %6.2lf $delimiter ${color2}\"";
  $cmd_legend_lower .= " PRINT:transmitted_mbps_${counter}:MAX:\" %6.2lf $delimiter $label $delimiter ${group_label}\"";
  $cmd_legend_lower .= " COMMENT:\\n";

  # return the data
  my %result = (
    cmd_def          => $cmd_def,
    cmd_cdef         => $cmd_cdef,
    cmd_legend_lower => $cmd_legend_lower,
    cmd_legend_upper => $cmd_legend_upper
  );

  return \%result;
}

sub graph_storage_aggr {
  my $type        = shift;    # value: 'host' or 'vm'
  my $metric_type = shift;    # value: 'vbd', 'latency' or 'iops'
  my $filepath    = shift;
  my $counter     = shift;
  my $color1      = shift;
  my $color2      = shift;
  my $label       = shift;
  my $group_label = shift;    # either host's (graph storages), or pool's (graph VMs)
  my $group_type  = shift;

  # RRD command parts
  my $cmd_def = my $cmd_cdef = my $cmd_legend_lower = my $cmd_legend_upper = '';
  my ( $metric_read, $metric_write, $metric, $graph_type );
  $metric_read  = 'vbd_read';
  $metric_write = 'vbd_write';
  if ( $metric_type eq 'vbd' && $type eq 'vm' ) {
    $metric = 'vbd_total';
  }
  $graph_type = ( $counter > 0 ) ? 'STACK' : 'AREA';
  if ( $metric_type eq 'iops' ) {
    $metric_read  = 'vbd_iops_read';
    $metric_write = 'vbd_iops_write';
  }
  elsif ( $metric_type eq 'latency' && $type ne 'vm' ) {
    $metric = 'vbd_total_latency';

    #$metric_read  = 'vbd_read_latency';
    #$metric_write = 'vbd_write_latency';
    $graph_type = "LINE1";
  }
  elsif ( $metric_type eq 'latency' && $type eq 'vm' ) {
    $metric_read  = 'vbd_read_latency';
    $metric_write = 'vbd_write_latency';
    $graph_type   = "LINE1";
  }

  if ( ( $metric_type eq 'latency' && $type ne 'vm' ) || ( $metric_type eq 'vbd' && $type eq 'vm' ) ) {
    $cmd_def .= " DEF:total_${counter}=\"$filepath\":${metric}:AVERAGE";
  }
  else {
    $cmd_def .= " DEF:write_${counter}=\"$filepath\":${metric_write}:AVERAGE";
    $cmd_def .= " DEF:read_${counter}=\"$filepath\":${metric_read}:AVERAGE";
  }

  my $b2mib = 1000**2;
  if ( $metric_type eq 'vbd' ) {
    if ( $type eq 'vm' ) {
      $cmd_cdef .= " CDEF:total_graph_${counter}=total_${counter},$b2mib,/";
    }
    else {
      $cmd_cdef .= " CDEF:write_graph_${counter}=write_${counter},$b2mib,/";
      $cmd_cdef .= " CDEF:read_graph_${counter}=read_${counter},$b2mib,/";
    }
  }
  elsif ( $metric_type eq 'iops' ) {
    $cmd_cdef .= " CDEF:write_graph_${counter}=write_${counter}";
    $cmd_cdef .= " CDEF:read_graph_${counter}=read_${counter}";
  }
  elsif ( $metric_type eq 'latency' && $type ne 'vm' ) {
    $cmd_cdef .= " CDEF:total_graph_${counter}=total_${counter},1000,/";

    #$cmd_cdef    .= " CDEF:write_graph_${counter}=write_${counter},1000,/";
    #$cmd_cdef    .= " CDEF:read_graph_${counter}=read_${counter},1000,/";
  }
  elsif ( $metric_type eq 'latency' && $type eq 'vm' ) {
    $cmd_cdef .= " CDEF:write_graph_${counter}=write_${counter},1000,/";
    $cmd_cdef .= " CDEF:read_graph_${counter}=read_${counter},1000,/";
  }

  if ( !defined $metric ) {
    if ( ( $metric_type ne 'latency' ) || ( $metric_type eq 'latency' && $type eq 'vm' ) ) {
      $cmd_cdef .= " CDEF:read_graph_neg_${counter}=read_graph_${counter},-1,*";
    }
  }

  # $url_item is used in `ret_graph_param` to transform legends' table in `detail-graph-cgi.pl`
  my $item_type = $metric_type;
  if ( $metric_type ne 'vbd' ) { $item_type = "vbd-${metric_type}"; }
  my $url_item = "nutanix-disk-${item_type}-aggr";
  if ( defined $group_type && $type eq 'vm' && $group_type eq 'pool' ) {
    $url_item = "nutanix-vm-${item_type}-aggr";
  }
  elsif ( $type eq 'vm' ) {    # ad-hoc assignment for Custom groups; perhaps make a separate argument
    $url_item = "custom-nutanixvm-${item_type}-aggr";
  }
  elsif ( $type eq 'sp' ) {    # ad-hoc assignment for Custom groups; perhaps make a separate argument
    $url_item = "nutanix-disk-${item_type}-sp-aggr";
  }
  elsif ( $type eq 'sr' ) {    # ad-hoc assignment for Custom groups; perhaps make a separate argument
    $url_item = "nutanix-disk-${item_type}-sr-aggr";
  }
  elsif ( $type eq 'vg' ) {    # ad-hoc assignment for Custom groups; perhaps make a separate argument
    $url_item = "nutanix-disk-${item_type}-vg-aggr";
  }
  elsif ( $type eq 'vd' ) {    # ad-hoc assignment for Custom groups; perhaps make a separate argument
    $url_item = "nutanix-disk-${item_type}-vd-aggr";
  }
  elsif ( $type eq 'sc' ) {    # ad-hoc assignment for Custom groups; perhaps make a separate argument
    $url_item = "nutanix-disk-${item_type}-sc-aggr";
  }

  my $label_space = get_formatted_label($label);
  my $group_space = get_formatted_label($group_label);

  # $uuid is used to form hypertext links in legends' tables
  my $uuid = get_uuid_from_filepath( $type, $filepath );

  if ( ( $metric_type eq 'latency' && $type ne 'vm' ) || ( $metric_type eq 'vbd' && $type eq 'vm' ) ) {
    $cmd_legend_lower .= " ${graph_type}:total_graph_${counter}${color1}:\" \"";
    $cmd_legend_lower .= " COMMENT:\"$group_space  $label_space\"";
    $cmd_legend_lower .= " GPRINT:total_graph_${counter}:AVERAGE:\" %6.2lf\"";
    $cmd_legend_lower .= " GPRINT:total_graph_${counter}:MAX:\" %6.2lf    \"";
    $cmd_legend_lower .= " PRINT:total_graph_${counter}:AVERAGE:\" %6.2lf $delimiter $url_item $delimiter $label $delimiter ${color1} $delimiter ${color1}\"";
    $cmd_legend_lower .= " PRINT:total_graph_${counter}:MAX:\" %6.2lf $delimiter $label $delimiter ${group_label} $delimiter $uuid\"";
    $cmd_legend_lower .= " COMMENT:\\n";
  } elsif ( $metric_type eq 'iops' ) {
    $cmd_legend_lower .= " COMMENT:\"${group_space} ${label_space}\"";
    $cmd_legend_lower .= " ${graph_type}:read_graph_neg_${counter}${color1}:\" \"";
    $cmd_legend_lower .= " GPRINT:read_graph_${counter}:AVERAGE:\" %6.0lf\"";
    $cmd_legend_lower .= " GPRINT:read_graph_${counter}:MAX:\" %6.0lf    \"";
    $cmd_legend_lower .= " PRINT:read_graph_${counter}:AVERAGE:\" %6.0lf $delimiter $url_item $delimiter $label $delimiter ${color1} $delimiter ${color1}\"";
    $cmd_legend_lower .= " PRINT:read_graph_${counter}:MAX:\" %6.0lf $delimiter $label $delimiter ${group_label} $delimiter $uuid\"";
    $cmd_legend_upper .= " ${graph_type}:write_graph_${counter}${color2}: ";
    $cmd_legend_lower .= " ${graph_type}:0${color2}:\" \"";
    $cmd_legend_lower .= " GPRINT:write_graph_${counter}:AVERAGE:\" %6.0lf\"";
    $cmd_legend_lower .= " GPRINT:write_graph_${counter}:MAX:\" %6.0lf\"";
    $cmd_legend_lower .= " PRINT:write_graph_${counter}:AVERAGE:\" %6.0lf $delimiter ${color2}\"";
    $cmd_legend_lower .= " PRINT:write_graph_${counter}:MAX:\" %6.0lf $delimiter $label $delimiter ${group_label}\"";
    $cmd_legend_lower .= " COMMENT:\\n";
  } else {
    $cmd_legend_lower .= " COMMENT:\"${group_space} ${label_space}\"";
    $cmd_legend_lower .= " ${graph_type}:read_graph_neg_${counter}${color1}:\" \"";
    $cmd_legend_lower .= " GPRINT:read_graph_${counter}:AVERAGE:\" %6.2lf\"";
    $cmd_legend_lower .= " GPRINT:read_graph_${counter}:MAX:\" %6.2lf    \"";
    $cmd_legend_lower .= " PRINT:read_graph_${counter}:AVERAGE:\" %6.2lf $delimiter $url_item $delimiter $label $delimiter ${color1} $delimiter ${color1}\"";
    $cmd_legend_lower .= " PRINT:read_graph_${counter}:MAX:\" %6.2lf $delimiter $label $delimiter ${group_label} $delimiter $uuid\"";
    $cmd_legend_upper .= " ${graph_type}:write_graph_${counter}${color2}: ";
    $cmd_legend_lower .= " ${graph_type}:0${color2}:\" \"";
    $cmd_legend_lower .= " GPRINT:write_graph_${counter}:AVERAGE:\" %6.2lf\"";
    $cmd_legend_lower .= " GPRINT:write_graph_${counter}:MAX:\" %6.2lf\"";
    $cmd_legend_lower .= " PRINT:write_graph_${counter}:AVERAGE:\" %6.2lf $delimiter ${color2}\"";
    $cmd_legend_lower .= " PRINT:write_graph_${counter}:MAX:\" %6.2lf $delimiter $label $delimiter ${group_label}\"";
    $cmd_legend_lower .= " COMMENT:\\n";
  }

  # return the data
  my %result = (
    cmd_def          => $cmd_def,
    cmd_cdef         => $cmd_cdef,
    cmd_legend_lower => $cmd_legend_lower,
    cmd_legend_upper => $cmd_legend_upper
  );

  return \%result;
}

################################################################################

1;
