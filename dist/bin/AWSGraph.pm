#AWSGraph.pm
# keep AWS graph generation in one place, if possible
# (separated from `detail-graph-cgi.pl`)

package AWSGraph;

use strict;
use warnings;

use Data::Dumper;

use AWSDataWrapper;

defined $ENV{INPUTDIR} || warn( localtime() . ': INPUTDIR undefined, config etc/lpar2rrd.cfg probably has not been loaded ' . __FILE__ . ':' . __LINE__ ) && exit 1;

my $inputdir = $ENV{INPUTDIR};
my $wrkdir   = "$inputdir/data";

my $aws_path = "$wrkdir/AWS";
my $ec2_path = "$wrkdir/AWS/EC2";

# helper delimiter: used to convert graph legends to HTML tables in `detail-graph-cgi.pl`
my $delimiter = 'XORUX';

################################################################################

# current usage in detail-graph-cgi.pl
#   graph_aws( $host, $server, $lpar, $time, $name_out, $type_sam, $detail, $start_unix, $end_unix );
#   graph_aws_totals( $host, $server, $lpar, $time, $name_out, $type_sam, $detail, $start_unix, $end_unix );
# and custom.pl

################################################################################

# assemble graph header
#   params: $type, $uuid, $context
#   output: "<platform> <context> @ $type <label-$type-$uuid>"
sub get_header {
  my $type    = shift;
  my $uuid    = shift;
  my $context = shift;

  my $label  = AWSDataWrapper::get_label( $type, $uuid );
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
  my $result = '';
  $result .= " --vertical-label=\"$legend\"";
  $result .= " --lower-limit=0.00";

  return $result;
}

sub get_params_memory {
  my $result = '';
  $result .= " --vertical-label=\"Memory in [GiB]\"";
  $result .= " --lower-limit=0.00";

  return $result;
}

sub get_params_lan {
  my $result = '';
  $result .= " --vertical-label=\"Read - Bytes/sec - Write\"";
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

sub graph_custom {
  my $type        = shift;
  my $uuid        = shift;
  my $metric_type = shift;
  my $legend      = shift;
  my $toGB        = shift;
  my $item        = shift;
  my $skip_acl    = shift || 0; # optional flag

  # necessary information
  my $rrd = AWSDataWrapper::get_filepath_rrd( { type => $type, uuid => $uuid, skip_acl => $skip_acl } );

  # RRD command parts
  my $cmd_params;
  $cmd_params .= " --lower-limit=0.00";
  my $cmd_def = my $cmd_cdef = my $cmd_legend = '';

  my $con;
  if ( $toGB eq '1' ) {
    $con = 1000**3;
  }
  else {
    $con = 1;
  }

  if ( $legend eq "ms" ) {
    $con = 1000;
  }

  $cmd_def  .= " DEF:$metric_type=\"$rrd\":$metric_type:AVERAGE";
  $cmd_cdef .= " CDEF:custom_graph=$metric_type,$con,/";

  $cmd_legend .= " COMMENT:\"[$legend]               Avrg       Max\\n\"";

  $cmd_legend .= " LINE1:custom_graph#FF0000:\" $item   \"";
  $cmd_legend .= " GPRINT:custom_graph:AVERAGE:\" %6.1lf\"";
  $cmd_legend .= " GPRINT:custom_graph:MAX:\" %6.1lf\"";
  $cmd_legend .= " COMMENT:\\n";

  $cmd_legend .= " --lower-limit=0.00";
  if ( $toGB eq '1' ) {
    $cmd_legend .= " --vertical-label=\"$legend in [GiB]\"";
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

sub graph_cpu {
  my $type        = shift;    # value: 'host' or 'vm'
  my $uuid        = shift;
  my $metric_type = shift;    # value: 'percent' or 'cores'
  my $skip_acl    = shift || 0; # optional flag

  # necessary information
  my $rrd = AWSDataWrapper::get_filepath_rrd( { type => $type, uuid => $uuid, skip_acl => $skip_acl } );

  # RRD command parts
  my $cmd_params = get_params_cpu();
  my $cmd_def    = my $cmd_cdef = my $cmd_legend = '';

  my $metric = 'cpu';
  if ( $metric_type eq 'cores' ) {    # 'cpu_cores' are the same for both 'vm' and 'host'
    $metric = 'cpu_cores';
  }
  elsif ( $type eq 'ec2' || $type eq 'rds' ) {
    $metric = 'cpu_percent';
  }

  $cmd_def .= " DEF:$metric=\"$rrd\":$metric:AVERAGE";
  if ( $metric_type eq 'percent' ) {
    $cmd_cdef .= " CDEF:cpu_graph=$metric,100,*";
  }
  else {                              # 'cores'
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
  }
  else {
    $cmd_legend .= " COMMENT:\"[%]                   Avrg       Max\\n\"";
    $cmd_legend .= " LINE1:cpu_graph#FF0000:\" Utilization   \"";
    $cmd_legend .= " GPRINT:cpu_graph:AVERAGE:\" %6.0lf\"";
    $cmd_legend .= " GPRINT:cpu_graph:MAX:\" %6.0lf\"";
  }
  $cmd_legend .= " COMMENT:\\n";
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

sub graph_lan {
  my $type = shift;
  my $uuid = shift;
  my $skip_acl = shift || 0; # optional flag

  # necessary information
  my $rrd = AWSDataWrapper::get_filepath_rrd( { type => $type, uuid => $uuid, skip_acl => $skip_acl } );

  # RRD command parts
  my $cmd_params = get_params_lan();
  my $cmd_def    = my $cmd_cdef = my $cmd_legend = '';

  $cmd_def .= " DEF:transmitted=\"$rrd\":network_out:AVERAGE";
  $cmd_def .= " DEF:received=\"$rrd\":network_in:AVERAGE";

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
  my $rrd = AWSDataWrapper::get_filepath_rrd( { type => $type, uuid => $uuid, skip_acl => $skip_acl } );

  # RRD command parts
  my $cmd_params = get_params_storage($metric_type);
  my $cmd_def    = my $cmd_cdef = my $cmd_legend = '';

  my ( $metric_read, $metric_write, $metric );
  $metric_read  = 'disk_read_bytes';
  $metric_write = 'disk_write_bytes';

  if ( $metric_type eq 'iops' ) {
    $metric_read  = 'disk_read_ops';
    $metric_write = 'disk_write_ops';
  }
  elsif ( $metric_type eq 'latency' ) {
    $metric_read  = 'disk_read_latency';
    $metric_write = 'disk_write_latency';
  }

  $cmd_def .= " DEF:write_graph_def=\"$rrd\":${metric_write}:AVERAGE";
  $cmd_def .= " DEF:read_graph_def=\"$rrd\":${metric_read}:AVERAGE";

  if ( $metric_type eq 'data' ) {
    my $b2mib = 1000**2;
    $cmd_cdef .= " CDEF:write_graph=write_graph_def,$b2mib,/";
    $cmd_cdef .= " CDEF:read_graph=read_graph_def,$b2mib,/";
    $cmd_cdef .= " CDEF:read_neg=0,read_graph,-";

    #$cmd_cdef    .= " CDEF:write_graph=${metric_write},$b2mib,/";
    #$cmd_cdef    .= " CDEF:read_graph=${metric_read},$b2mib,/";
    #$cmd_cdef    .= " CDEF:read_neg=0,read_graph,-";
  }
  elsif ( $metric_type eq 'iops' ) {
    $cmd_cdef .= " CDEF:write_graph=write_graph_def";
    $cmd_cdef .= " CDEF:read_graph=read_graph_def";
    $cmd_cdef .= " CDEF:read_neg=0,read_graph,-";
  }
  elsif ( $metric_type eq 'latency' ) {
    $cmd_cdef .= " CDEF:write_graph=write_graph_def,1000,*";
    $cmd_cdef .= " CDEF:read_graph=read_graph_def,1000,*";
    $cmd_cdef .= " CDEF:read_neg=0,read_graph,-";
  }

  if ( $metric_type eq 'iops' ) {
    $cmd_legend .= " COMMENT:\"[iops]                Avrg      Max\\n\"";
  }
  elsif ( $metric_type eq 'latency' ) {
    $cmd_legend .= " COMMENT:\"[ms]                  Avrg      Max\\n\"";
  }
  else {
    $cmd_legend .= " COMMENT:\"[MB/s]               Avrg      Max\\n\"";
  }

  if ( $metric_type eq 'iops' ) {
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
# to be moved to AWSDataWrapper
sub get_uuid_from_filepath {
  my $type     = shift;    # value: 'vm' or 'host'
  my $filepath = shift;

  my $uuid;
  $filepath =~ m/\/AWS\/(.*)\/(.*)\.rrd/;
  $uuid = $2;

  return $uuid;
}

################################################################################

# more specific subroutine, assumes that the caller has already figured out filepath, label, etc.
#   params: $type, $filepath, $counter, $color, $label,…
#   return: hash w/ def, cdef, legend

sub graph_instances_aggr {
  my $type        = shift;
  my $metric_type = shift;
  my $filepath    = shift;
  my $counter     = shift;
  my $color       = shift;
  my $label       = shift;
  my $group_label = shift;
  my $group_type  = shift;

  # RRD command parts
  my $cmd_def = my $cmd_cdef = my $cmd_legend = '';

  my $metric_running = 'instances_running';
  my $metric_stopped = 'instances_stopped';

  my $graph_type = ( $counter > 0 ) ? 'STACK' : 'AREA';
  $cmd_def .= " DEF:running_${counter}=\"${filepath}\":${metric_running}:AVERAGE";
  $cmd_def .= " DEF:stopped_${counter}=\"${filepath}\":${metric_stopped}:AVERAGE";

  # $url_item is used in `ret_graph_param` to transform legends' table in `detail-graph-cgi.pl`
  my $url_item = "aws-region-${metric_type}-aggr";

  my $label_space = get_formatted_label($label);
  my $group_space = get_formatted_label($group_label);

  # $uuid is used to form hypertext links in legends' tables
  my $uuid = get_uuid_from_filepath( $type, $filepath );
  $cmd_legend .= " ${graph_type}:${metric_type}_${counter}${color}:\" \"";
  $cmd_legend .= " COMMENT:\"$group_space  $label_space\"";
  $cmd_legend .= " GPRINT:${metric_type}_${counter}:AVERAGE:\" %6.1lf\"";
  $cmd_legend .= " GPRINT:${metric_type}_${counter}:MAX:\" %6.1lf    \"";
  $cmd_legend .= " PRINT:${metric_type}_${counter}:AVERAGE:\" %6.1lf $delimiter $url_item $delimiter $label $delimiter $color $delimiter $color\"";
  $cmd_legend .= " PRINT:${metric_type}_${counter}:MAX:\" %6.1lf $delimiter $label $delimiter ${group_label} $delimiter \"";
  $cmd_legend .= " COMMENT:\\n";

  # return the data
  my %result = (
    cmd_def    => $cmd_def,
    cmd_cdef   => $cmd_cdef,
    cmd_legend => $cmd_legend
  );

  return \%result;
}

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
  elsif ( $type eq 'ec2' || $type eq 'region' || $type eq 'rds' ) {
    $metric     = 'cpu_percent';
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
  my $url_item = "aws-ec2-cpu-${metric_type}-aggr";
  if ( $type eq 'ec2' && $group_type eq 'region' ) {    # VMs under host
    $url_item = "aws-ec2-cpu-${metric_type}-aggr";
  }
  elsif ( $type eq 'ec2' ) {                            # ad-hoc assignment for Custom groups
    $url_item = "aws-ec2-cpu-${metric_type}";
  }
  elsif ( $type eq 'rds' ) {                            # ad-hoc assignment for Custom groups
    $url_item = "aws-rds-cpu-${metric_type}-aggr";
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

sub graph_custom_aggr {
  my $type        = shift;    # value: 'host' or 'vm'
  my $metric_type = shift;    # value: 'percent' or 'cores'
  my $filepath    = shift;
  my $counter     = shift;
  my $color       = shift;
  my $label       = shift;
  my $group_label = shift;
  my $group_type  = shift;    # value: 'pool' (for pool or custom groups) or 'host'
  my $toGB        = shift;

  # RRD command parts
  my $cmd_def = my $cmd_cdef = my $cmd_legend = '';
  my ( $metric, $graph_type );

  $metric     = $metric_type;
  $graph_type = 'LINE1';

  $cmd_def .= " DEF:${metric}_${counter}=\"${filepath}\":${metric}:AVERAGE";

  my $cc;
  if ( $toGB eq '1' ) {
    $cc = 1000**3;
  }
  else {
    $cc = 1;
  }

  if ( $metric eq "duration" || $metric eq "latency" ) {
    $cc = 1000;
  }

  $cmd_cdef .= " CDEF:custom_graph_${counter}=${metric}_${counter},$cc,/";

  my $url_item;
  if ( $metric_type eq 'db_connection' ) {
    $url_item   = "aws-rds-db-connection-aggr";
    $graph_type = 'AREA';
  }
  elsif ( $metric_type eq 'mem_free' ) {
    $url_item   = "aws-rds-mem-free-aggr";
    $graph_type = 'AREA';
  }
  elsif ( $metric_type eq 'disk_free' ) {
    $url_item   = "aws-rds-disk-free-aggr";
    $graph_type = 'AREA';
  }
  elsif ( $metric_type eq 'count' || $metric_type eq '5xx_error' || $metric_type eq '4xx_error' ) {
    $url_item   = "aws-api-${metric_type}-aggr";
    $graph_type = 'AREA';
  }
  elsif ( $metric_type eq 'latency' || $metric_type eq 'integration_latency' ) {
    $url_item = "aws-api-${metric_type}-aggr";
  }
  elsif ( $metric_type eq 'invocations' ) {
    $url_item   = "aws-lambda-invocations-aggr";
    $graph_type = 'AREA';
  }
  elsif ( $metric_type eq 'errors' ) {
    $url_item   = "aws-lambda-errors-aggr";
    $graph_type = 'AREA';
  }
  elsif ( $metric_type eq 'duration' ) {
    $url_item = "aws-lambda-duration-aggr";
  }
  elsif ( $metric_type eq 'throttles' ) {
    $url_item   = "aws-lambda-throttles-aggr";
    $graph_type = 'AREA';
  }
  elsif ( $metric_type eq 'concurrent' ) {
    $url_item   = "aws-lambda-concurrent-executions-aggr";
    $graph_type = 'AREA';
  }
  else {
    $url_item = "aws-rds-${metric_type}-aggr";
  }
  my $label_space = get_formatted_label($label);
  my $group_space = get_formatted_label($group_label);

  # $uuid is used to form hypertext links in legends' tables
  my $uuid = get_uuid_from_filepath( $type, $filepath );

  if ( $graph_type eq 'AREA' && $counter > 0 ) {
    $graph_type = 'STACK';
  }

  $cmd_legend .= " ${graph_type}:custom_graph_${counter}${color}:\" \"";
  $cmd_legend .= " COMMENT:\"$group_space  $label_space\"";
  $cmd_legend .= " GPRINT:custom_graph_${counter}:AVERAGE:\" %6.1lf\"";
  $cmd_legend .= " GPRINT:custom_graph_${counter}:MAX:\" %6.1lf    \"";
  $cmd_legend .= " PRINT:custom_graph_${counter}:AVERAGE:\" %6.1lf $delimiter $url_item $delimiter $label $delimiter $color $delimiter $color\"";
  $cmd_legend .= " PRINT:custom_graph_${counter}:MAX:\" %6.1lf $delimiter $label $delimiter ${group_label} $delimiter $uuid\"";
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

  # RRD command parts
  my $cmd_def    = my $cmd_cdef = my $cmd_legend_lower = my $cmd_legend_upper = '';
  my $graph_type = ( $counter > 0 ) ? 'STACK' : 'AREA';
  my $b2mb       = 1000**2;
  $cmd_def  .= " DEF:transmitted_${counter}=\"$filepath\":network_out:AVERAGE";
  $cmd_def  .= " DEF:received_${counter}=\"$filepath\":network_in:AVERAGE";
  $cmd_cdef .= " CDEF:transmitted_mbps_${counter}=transmitted_${counter},$b2mb,/";
  $cmd_cdef .= " CDEF:received_mbps_${counter}=received_${counter},$b2mb,/";

  $cmd_cdef .= " CDEF:received_graph_${counter}=received_mbps_${counter},-1,*";

  # $url_item is used in `ret_graph_param` to transform legends' table in `detail-graph-cgi.pl`
  my $url_item = "aws-$type-net-aggr";
  if ( $type eq 'vm' ) {    # ad-hoc assignment for Custom groups; perhaps make a separate argument
    $url_item = "custom-aws-$type-net";
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

  # RRD command parts
  my $cmd_def = my $cmd_cdef = my $cmd_legend_lower = my $cmd_legend_upper = '';
  my ( $metric_read, $metric_write, $metric, $graph_type );
  $metric_read  = 'disk_read_bytes';
  $metric_write = 'disk_write_bytes';

  $graph_type = ( $counter > 0 ) ? 'STACK' : 'AREA';

  if ( $metric_type eq 'iops' ) {
    $metric_read  = 'disk_read_ops';
    $metric_write = 'disk_write_ops';
  }
  elsif ( $metric_type eq 'latency' ) {
    $metric_read  = 'disk_read_latency';
    $metric_write = 'disk_write_latency';
  }

  $cmd_def .= " DEF:write_${counter}=\"$filepath\":${metric_write}:AVERAGE";
  $cmd_def .= " DEF:read_${counter}=\"$filepath\":${metric_read}:AVERAGE";

  my $b2mib = 1000**2;
  if ( $metric_type eq 'data' ) {
    $cmd_cdef .= " CDEF:write_graph_${counter}=write_${counter},$b2mib,/";
    $cmd_cdef .= " CDEF:read_graph_${counter}=read_${counter},$b2mib,/";
    $cmd_cdef .= " CDEF:read_graph_neg_${counter}=0,read_graph_${counter},-";
  }
  elsif ( $metric_type eq 'iops' ) {
    $cmd_cdef .= " CDEF:write_graph_${counter}=write_${counter}";
    $cmd_cdef .= " CDEF:read_graph_${counter}=read_${counter}";

    #$cmd_cdef    .= " CDEF:read_graph_neg_${counter}=read_graph_${counter},-1,*";
    $cmd_cdef .= " CDEF:read_graph_neg_${counter}=0,read_graph_${counter},-";    #honza, nahradil jsem aby to bylo stejně ... viz prechozi radek, bez efektu
  }
  elsif ( $metric_type eq 'latency' ) {
    $cmd_cdef .= " CDEF:write_graph_${counter}=write_${counter},1000,*";
    $cmd_cdef .= " CDEF:read_graph_${counter}=read_${counter},1000,*";
    $cmd_cdef .= " CDEF:read_graph_neg_${counter}=0,read_graph_${counter},-";
  }

  # $url_item is used in `ret_graph_param` to transform legends' table in `detail-graph-cgi.pl`
  my $url_item;
  my $item_type = $metric_type;
  if ( $type eq 'ec2' ) {                                                        # ad-hoc assignment for Custom groups; perhaps make a separate argument
    $url_item = "aws-ec2-${item_type}-aggr";
  }
  if ( $type eq 'ebs' ) {                                                        # ad-hoc assignment for Custom groups; perhaps make a separate argument
    $url_item = "aws-ebs-${item_type}-aggr";
  }
  if ( $type eq 'rds' ) {                                                        # ad-hoc assignment for Custom groups; perhaps make a separate argument
    $url_item = "aws-rds-${item_type}-aggr";
  }

  my $label_space = get_formatted_label($label);
  my $group_space = get_formatted_label($group_label);

  # $uuid is used to form hypertext links in legends' tables
  my $uuid = get_uuid_from_filepath( $type, $filepath );

  $cmd_legend_lower .= " COMMENT:\"${group_space} ${label_space}\"";
  $cmd_legend_lower .= " ${graph_type}:read_graph_neg_${counter}${color1}:\" \"";

  if ( $metric_type eq 'iops' ) {
    #  $cmd_legend_lower .= " ${graph_type}:0${color2}:\" \""; #honza comment
    $cmd_legend_lower .= " GPRINT:read_graph_${counter}:AVERAGE:\" %6.0lf\"";
    $cmd_legend_lower .= " GPRINT:read_graph_${counter}:MAX:\" %6.0lf    \"";
    $cmd_legend_lower .= " PRINT:read_graph_${counter}:AVERAGE:\" %6.0lf $delimiter $url_item $delimiter $label $delimiter ${color1} $delimiter ${color1}\"";
    $cmd_legend_lower .= " PRINT:read_graph_${counter}:MAX:\" %6.0lf $delimiter $label $delimiter ${group_label} $delimiter $uuid\"";
    $cmd_legend_upper .= " ${graph_type}:write_graph_${counter}${color2}: ";

    #  $cmd_legend_upper .= " ${graph_type}:0${color2}:\" \""; #honza comment
    $cmd_legend_lower .= " GPRINT:write_graph_${counter}:AVERAGE:\" %6.0lf\"";
    $cmd_legend_lower .= " GPRINT:write_graph_${counter}:MAX:\" %6.0lf\"";
    $cmd_legend_lower .= " PRINT:write_graph_${counter}:AVERAGE:\" %6.0lf $delimiter ${color2}\"";
    $cmd_legend_lower .= " PRINT:write_graph_${counter}:MAX:\" %6.0lf $delimiter $label $delimiter ${group_label}\"";
    $cmd_legend_lower .= " COMMENT:\\n";
  } else {
    #  $cmd_legend_lower .= " ${graph_type}:0${color2}:\" \""; #honza comment
    $cmd_legend_lower .= " GPRINT:read_graph_${counter}:AVERAGE:\" %6.2lf\"";
    $cmd_legend_lower .= " GPRINT:read_graph_${counter}:MAX:\" %6.2lf    \"";
    $cmd_legend_lower .= " PRINT:read_graph_${counter}:AVERAGE:\" %6.2lf $delimiter $url_item $delimiter $label $delimiter ${color1} $delimiter ${color1}\"";
    $cmd_legend_lower .= " PRINT:read_graph_${counter}:MAX:\" %6.2lf $delimiter $label $delimiter ${group_label} $delimiter $uuid\"";
    $cmd_legend_upper .= " ${graph_type}:write_graph_${counter}${color2}: ";

    #  $cmd_legend_upper .= " ${graph_type}:0${color2}:\" \""; #honza comment
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

