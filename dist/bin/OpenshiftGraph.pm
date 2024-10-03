# OpenshiftGraph.pm
# keep Openshift graph generation in one place, if possible
# (separated from `detail-graph-cgi.pl`)

package OpenshiftGraph;

use strict;
use warnings;

use Data::Dumper;

use OpenshiftDataWrapper;

defined $ENV{INPUTDIR} || warn( localtime() . ': INPUTDIR undefined, config etc/lpar2rrd.cfg probably has not been loaded ' . __FILE__ . ':' . __LINE__ ) && exit 1;

my $inputdir = $ENV{INPUTDIR};
my $wrkdir   = "$inputdir/data";

my $openshift_path = "$wrkdir/Openshift";

# helper delimiter: used to convert graph legends to HTML tables in `detail-graph-cgi.pl`
my $delimiter = 'XORUX';

################################################################################

# current usage in detail-graph-cgi.pl
#   graph_openshift( $host, $server, $lpar, $time, $name_out, $type_sam, $detail, $start_unix, $end_unix );
#   graph_openshift_totals( $host, $server, $lpar, $time, $name_out, $type_sam, $detail, $start_unix, $end_unix );
# and custom.pl

################################################################################

sub get_header {
  my $type    = shift;
  my $uuid    = shift;
  my $context = shift;

  my $label  = OpenshiftDataWrapper::get_label( $type, $uuid );
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

sub get_params_cadvisor {
  my $legend   = shift;
  my $exponent = shift;
  my $result   = '';
  $result .= " --vertical-label=\"$legend\"";
  if ( defined $exponent ) {
    $result .= " --units-exponent=$exponent";
  }

  return $result;
}

sub get_params_memory {
  my $result = '';
  $result .= " --vertical-label=\"Memory in [GiB]\"";
  $result .= " --lower-limit=0.00";

  return $result;
}

################################################################################

sub graph_pods {
  my $uuid = shift;
  my $skip_acl = shift || 0; # optional flag

  # necessary information
  my $rrd = OpenshiftDataWrapper::get_filepath_rrd( { type => 'node', uuid => $uuid, skip_acl => $skip_acl } );

  # RRD command parts
  my $cmd_params = get_params_custom('Count');
  my $cmd_def    = my $cmd_cdef = my $cmd_legend = '';

  my ( $metric_pods, $metric_pods_allocatable, $metric_pods_capacity );

  $metric_pods_capacity    = 'pods_capacity';
  $metric_pods_allocatable = 'pods_allocatable';
  $metric_pods             = 'pods';

  $cmd_def .= " DEF:pods=\"$rrd\":${metric_pods}:AVERAGE";
  $cmd_def .= " DEF:pods_allocatable=\"$rrd\":${metric_pods_allocatable}:AVERAGE";
  $cmd_def .= " DEF:pods_capacity=\"$rrd\":${metric_pods_capacity}:AVERAGE";

  $cmd_cdef .= " CDEF:actual=pods,1,/";
  $cmd_cdef .= " CDEF:allocatable=pods_allocatable,1,/";
  $cmd_cdef .= " CDEF:capacity=pods_capacity,1,/";

  $cmd_legend .= " COMMENT:\"[Count]                        Avrg       Max\\n\"";
  $cmd_legend .= " AREA:capacity#75ff80:\" Capacity          \"";
  $cmd_legend .= " GPRINT:capacity:AVERAGE:\" %6.1lf\"";
  $cmd_legend .= " GPRINT:capacity:MAX:\" %6.1lf\"";
  $cmd_legend .= " COMMENT:\\n";
  $cmd_legend .= " AREA:allocatable#0080fc:\" Allocatable       \"";
  $cmd_legend .= " GPRINT:allocatable:AVERAGE:\" %6.1lf\"";
  $cmd_legend .= " GPRINT:allocatable:MAX:\" %6.1lf\"";
  $cmd_legend .= " COMMENT:\\n";
  $cmd_legend .= " AREA:actual#ff4040:\" Used              \"";
  $cmd_legend .= " GPRINT:actual:AVERAGE:\" %6.1lf\"";
  $cmd_legend .= " GPRINT:actual:MAX:\" %6.1lf\"";
  $cmd_legend .= " COMMENT:\\n";

  my %result = (
    cmd_params => $cmd_params,
    cmd_def    => $cmd_def,
    cmd_cdef   => $cmd_cdef,
    cmd_legend => $cmd_legend,
  );

  return \%result;
}

sub graph_cadvisor {
  my $type   = shift;
  my $metric = shift;
  my $uuid   = shift;
  my $skip_acl = shift || 0; # optional flag

  # necessary information
  my $rrd = OpenshiftDataWrapper::get_filepath_rrd( { type => $type, uuid => $uuid, skip_acl => $skip_acl } );

  # RRD command parts
  my $cmd_params = get_params_cadvisor();
  my $cmd_def    = my $cmd_cdef = my $cmd_legend = '';

  my ( $metric_read, $metric_write, $resolution );

  my $division = 1;
  my $comment;
  if ( $metric eq 'data' ) {
    $metric_read  = 'reads_bytes';
    $metric_write = 'writes_bytes';
    $division     = 1000 ** 2;
    $comment      = '[MB/sec]';
  }
  elsif ( $metric eq 'iops' ) {
    $metric_read  = 'reads';
    $metric_write = 'writes';
    $comment      = '[IOPS]     ';
  }
  elsif ( $metric eq 'latency' ) {
    $metric_read  = 'read_seconds';
    $metric_write = 'write_seconds';
    $comment      = '[ms]       ';
  }
  elsif ( $metric eq 'net' ) {
    $metric_read  = 'receive_bytes';
    $metric_write = 'transmit_bytes';
    $division     = 1000 ** 2;
    $comment      = '[MB/sec]';
  }

  $cmd_def .= " DEF:metric_read=\"$rrd\":${metric_read}:AVERAGE";
  $cmd_def .= " DEF:metric_write=\"$rrd\":${metric_write}:AVERAGE";

  $cmd_cdef .= " CDEF:read=metric_read,$division,/";
  $cmd_cdef .= " CDEF:write=metric_write,$division,/";
  $cmd_cdef .= " CDEF:read_neg=0,metric_read,-";

  $cmd_legend .= " COMMENT:\"$comment             Avrg       Max\\n\"";
  $cmd_legend .= " LINE1:read_neg#FF0000:\" Read           \"";
  $cmd_legend .= " GPRINT:read:AVERAGE:\" %6.2lf\"";
  $cmd_legend .= " GPRINT:read:MAX:\"  %6.2lf\"";
  $cmd_legend .= " COMMENT:\\n";
  $cmd_legend .= " LINE1:metric_write#0000FF:\" Write         \"";
  $cmd_legend .= " GPRINT:write:AVERAGE:\"  %6.2lf\"";
  $cmd_legend .= " GPRINT:write:MAX:\"  %6.2lf\"";
  $cmd_legend .= " COMMENT:\\n";
  $cmd_legend .= " COMMENT:\\n";

  my %result = (
    cmd_params => $cmd_params,
    cmd_def    => $cmd_def,
    cmd_cdef   => $cmd_cdef,
    cmd_legend => $cmd_legend,
  );

  return \%result;
}

sub graph_cpu {
  my $type = shift;
  my $uuid = shift;
  my $skip_acl = shift || 0; # optional flag

  # necessary information
  my $rrd = OpenshiftDataWrapper::get_filepath_rrd( { type => $type, uuid => $uuid, skip_acl => $skip_acl } );

  # RRD command parts
  my $cmd_params = get_params_memory();
  my $cmd_def    = my $cmd_cdef = my $cmd_legend = '';

  my ( $metric_cpu, $metric_cpu_request, $metric_cpu_limit );

  $metric_cpu_request = 'cpu_request';
  $metric_cpu_limit   = 'cpu_limit';
  $metric_cpu         = 'cpu';

  if ( $type eq "namespace" ) {

    $cmd_def  .= " DEF:cpu=\"$rrd\":${metric_cpu}:AVERAGE";
    $cmd_cdef .= " CDEF:actual=cpu,1,/";

    $cmd_legend .= " COMMENT:\"[Cores]                   Avrg       Max\\n\"";
    $cmd_legend .= " AREA:actual#ff4040:\" Used              \"";
    $cmd_legend .= " GPRINT:actual:AVERAGE:\" %6.2lf\"";
    $cmd_legend .= " GPRINT:actual:MAX:\"  %6.2lf\"";
    $cmd_legend .= " COMMENT:\\n";

  }
  else {

    $cmd_def .= " DEF:cpu=\"$rrd\":${metric_cpu}:AVERAGE";
    $cmd_def .= " DEF:cpu_request=\"$rrd\":${metric_cpu_request}:AVERAGE";
    $cmd_def .= " DEF:cpu_limit=\"$rrd\":${metric_cpu_limit}:AVERAGE";

    $cmd_cdef .= " CDEF:actual=cpu,1,/";
    $cmd_cdef .= " CDEF:request=cpu_request,1,/";
    $cmd_cdef .= " CDEF:limit=cpu_limit,1,/";

    $cmd_legend .= " COMMENT:\"[Cores]                   Avrg       Max\\n\"";
    $cmd_legend .= " AREA:actual#ff4040:\" Used              \"";
    $cmd_legend .= " GPRINT:actual:AVERAGE:\" %6.2lf\"";
    $cmd_legend .= " GPRINT:actual:MAX:\"  %6.2lf\"";
    $cmd_legend .= " COMMENT:\\n";
    $cmd_legend .= " LINE2:request#00FF00:\" Request           \"";
    $cmd_legend .= " GPRINT:request:AVERAGE:\" %6.2lf\"";
    $cmd_legend .= " GPRINT:request:MAX:\"  %6.2lf\"";
    $cmd_legend .= " COMMENT:\\n";
    $cmd_legend .= " LINE2:limit#000000:\" Limit             \"";
    $cmd_legend .= " GPRINT:limit:AVERAGE:\" %6.2lf\"";
    $cmd_legend .= " GPRINT:limit:MAX:\"  %6.2lf\"";
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

sub graph_memory {
  my $type = shift;
  my $uuid = shift;
  my $skip_acl = shift || 0; # optional flag

  # necessary information
  my $rrd = OpenshiftDataWrapper::get_filepath_rrd( { type => $type, uuid => $uuid, skip_acl => $skip_acl } );

  # RRD command parts
  my $cmd_params = get_params_memory();
  my $cmd_def    = my $cmd_cdef = my $cmd_legend = '';

  my ( $metric_memory, $metric_memory_request, $metric_memory_limit );

  $metric_memory_request = 'memory_request';
  $metric_memory_limit   = 'memory_limit';
  $metric_memory         = 'memory';

  my $b2gib   = 1024**3;
  my $kib2gib = 1024**2;
  my $mib2gib = 1024**1;
 
  if ( $type eq "namespace" ) {

    $cmd_def  .= " DEF:mem=\"$rrd\":${metric_memory}:AVERAGE";
    $cmd_cdef .= " CDEF:actual=mem,$mib2gib,/";

    $cmd_legend .= " COMMENT:\"[GiB]                      Avrg       Max\\n\"";
    $cmd_legend .= " AREA:actual#ff4040:\" Used              \"";
    $cmd_legend .= " GPRINT:actual:AVERAGE:\" %6.2lf\"";
    $cmd_legend .= " GPRINT:actual:MAX:\"  %6.2lf\"";
    $cmd_legend .= " COMMENT:\\n";

  }
  else {

    $cmd_def .= " DEF:mem=\"$rrd\":${metric_memory}:AVERAGE";
    $cmd_def .= " DEF:mem_request=\"$rrd\":${metric_memory_request}:AVERAGE";
    $cmd_def .= " DEF:mem_limit=\"$rrd\":${metric_memory_limit}:AVERAGE";

    $cmd_cdef .= " CDEF:actual=mem,$mib2gib,/";
    $cmd_cdef .= " CDEF:request=mem_request,$mib2gib,/";
    $cmd_cdef .= " CDEF:limit=mem_limit,$mib2gib,/";

    $cmd_legend .= " COMMENT:\"[GiB]                      Avrg       Max\\n\"";
    $cmd_legend .= " AREA:actual#ff4040:\" Used              \"";
    $cmd_legend .= " GPRINT:actual:AVERAGE:\" %6.2lf\"";
    $cmd_legend .= " GPRINT:actual:MAX:\"  %6.2lf\"";
    $cmd_legend .= " COMMENT:\\n";
    $cmd_legend .= " LINE2:request#00FF00:\" Request           \"";
    $cmd_legend .= " GPRINT:request:AVERAGE:\" %6.2lf\"";
    $cmd_legend .= " GPRINT:request:MAX:\"  %6.2lf\"";
    $cmd_legend .= " COMMENT:\\n";
    $cmd_legend .= " LINE2:limit#000000:\" Limit             \"";
    $cmd_legend .= " GPRINT:limit:AVERAGE:\" %6.2lf\"";
    $cmd_legend .= " GPRINT:limit:MAX:\"  %6.2lf\"";
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

sub graph_memory_node {
  my $uuid = shift;
  my $skip_acl = shift || 0; # optional flag

  # necessary information
  my $rrd = OpenshiftDataWrapper::get_filepath_rrd( { type => 'node', uuid => $uuid, skip_acl => $skip_acl } );

  # RRD command parts
  my $cmd_params = get_params_memory();
  my $cmd_def    = my $cmd_cdef = my $cmd_legend = '';

  my ( $metric_memory, $metric_memory_allocatable, $metric_memory_capacity );

  $metric_memory_capacity    = 'memory_capacity';
  $metric_memory_allocatable = 'memory_allocatable';
  $metric_memory             = 'memory';

  $cmd_def .= " DEF:mem=\"$rrd\":${metric_memory}:AVERAGE";
  $cmd_def .= " DEF:mem_allocatable=\"$rrd\":${metric_memory_allocatable}:AVERAGE";
  $cmd_def .= " DEF:mem_capacity=\"$rrd\":${metric_memory_capacity}:AVERAGE";

  my $b2gib   = 1024**3;
  my $kib2gib = 1024**2;
  my $mib2gib = 1024**1;

  $cmd_cdef .= " CDEF:actual=mem,$mib2gib,/";
  $cmd_cdef .= " CDEF:allocatable=mem_allocatable,$mib2gib,/";
  $cmd_cdef .= " CDEF:capacity=mem_capacity,$mib2gib,/";

  $cmd_legend .= " COMMENT:\"[GiB]                      Avrg       Max\\n\"";
  $cmd_legend .= " AREA:capacity#75ff80:\" Capacity          \"";
  $cmd_legend .= " GPRINT:capacity:AVERAGE:\" %6.1lf\"";
  $cmd_legend .= " GPRINT:capacity:MAX:\" %6.1lf\"";
  $cmd_legend .= " COMMENT:\\n";
  $cmd_legend .= " AREA:allocatable#0080fc:\" Allocatable       \"";
  $cmd_legend .= " GPRINT:allocatable:AVERAGE:\" %6.1lf\"";
  $cmd_legend .= " GPRINT:allocatable:MAX:\" %6.1lf\"";
  $cmd_legend .= " COMMENT:\\n";
  $cmd_legend .= " AREA:actual#ff4040:\" Used              \"";
  $cmd_legend .= " GPRINT:actual:AVERAGE:\" %6.1lf\"";
  $cmd_legend .= " GPRINT:actual:MAX:\" %6.1lf\"";
  $cmd_legend .= " COMMENT:\\n";

  my %result = (
    cmd_params => $cmd_params,
    cmd_def    => $cmd_def,
    cmd_cdef   => $cmd_cdef,
    cmd_legend => $cmd_legend,
  );

  return \%result;
}

sub graph_cpu_node {
  my $uuid     = shift;
  my $cpu_type = shift;    # value: 'percent' or 'cores'
  my $skip_acl = shift || 0; # optional flag

  # necessary information
  my $rrd = OpenshiftDataWrapper::get_filepath_rrd( { type => 'node', uuid => $uuid, skip_acl => $skip_acl } );

  # RRD command parts
  my $cmd_params;
  if ( $cpu_type eq 'percent' ) {
    $cmd_params = get_params_cpu('percent');
  }
  else {
    $cmd_params = get_params_cpu('cores');
  }
  my $cmd_def = my $cmd_cdef = my $cmd_legend = '';

  my ( $metric_cpu, $metric_cpu_allocatable, $metric_cpu_capacity );

  $metric_cpu_capacity    = 'cpu_capacity';
  $metric_cpu_allocatable = 'cpu_allocatable';
  $metric_cpu             = 'cpu';

  $cmd_def .= " DEF:cpu=\"$rrd\":${metric_cpu}:AVERAGE";
  $cmd_def .= " DEF:cpu_allocatable=\"$rrd\":${metric_cpu_allocatable}:AVERAGE";
  $cmd_def .= " DEF:cpu_capacity=\"$rrd\":${metric_cpu_capacity}:AVERAGE";

  my $b2gib   = 1024**3;
  my $kib2gib = 1024**2;
  my $mib2gib = 1024**1;
  $cmd_cdef .= " CDEF:actual=cpu,1,/";
  $cmd_cdef .= " CDEF:allocatable=cpu_allocatable,1,/";
  $cmd_cdef .= " CDEF:capacity=cpu_capacity,1,/";

  $cmd_cdef .= " CDEF:capacity_percent=cpu_capacity,100,/";
  $cmd_cdef .= " CDEF:allocatable_percent=cpu_allocatable,100,/";
  $cmd_cdef .= " CDEF:to_allocatable=cpu,allocatable_percent,/";
  $cmd_cdef .= " CDEF:to_capacity=cpu,capacity_percent,/";

  if ( $cpu_type eq 'percent' ) {
    $cmd_legend .= " COMMENT:\"[%]                       Avrg       Max\\n\"";
    $cmd_legend .= " LINE1:to_allocatable#0080fc:\" To Allocatable   \"";
    $cmd_legend .= " GPRINT:to_allocatable:AVERAGE:\" %6.1lf\"";
    $cmd_legend .= " GPRINT:to_allocatable:MAX:\"  %6.1lf\"";
    $cmd_legend .= " COMMENT:\\n";
    $cmd_legend .= " LINE1:to_capacity#75ff80:\" To Capacity      \"";
    $cmd_legend .= " GPRINT:to_capacity:AVERAGE:\" %6.1lf\"";
    $cmd_legend .= " GPRINT:to_capacity:MAX:\"  %6.1lf\"";
    $cmd_legend .= " COMMENT:\\n";
  }
  else {
    $cmd_legend .= " COMMENT:\"[Cores]                    Avrg       Max\\n\"";
    $cmd_legend .= " AREA:capacity#75ff80:\" Capacity          \"";
    $cmd_legend .= " GPRINT:capacity:AVERAGE:\" %6.1lf\"";
    $cmd_legend .= " GPRINT:capacity:MAX:\" %6.1lf\"";
    $cmd_legend .= " COMMENT:\\n";
    $cmd_legend .= " AREA:allocatable#0080fc:\" Allocatable       \"";
    $cmd_legend .= " GPRINT:allocatable:AVERAGE:\" %6.1lf\"";
    $cmd_legend .= " GPRINT:allocatable:MAX:\" %6.1lf\"";
    $cmd_legend .= " COMMENT:\\n";
    $cmd_legend .= " AREA:actual#ff4040:\" Used              \"";
    $cmd_legend .= " GPRINT:actual:AVERAGE:\" %6.1lf\"";
    $cmd_legend .= " GPRINT:actual:MAX:\" %6.1lf\"";
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

################################################################################
# to be moved to OpenshiftDataWrapper
sub get_uuid_from_filepath {
  my $type     = shift;    # value: 'vm' or 'host'
  my $filepath = shift;

  my $uuid;
  $filepath =~ m/\/Openshift\/(.*)\/(.*)\.rrd/;
  $uuid = $2;

  return $uuid;
}

################################################################################

sub graph_cadvisor_aggr {
  my $type        = shift;    # value: 'node' or 'container'
  my $metric      = shift;
  my $filepath    = shift;
  my $counter     = shift;
  my $color1      = shift;
  my $color2      = shift;
  my $label       = shift;
  my $group_label = shift;
  my $group_type  = shift;

  # RRD command parts
  my $cmd_def    = my $cmd_cdef = my $cmd_legend_lower = my $cmd_legend_upper = '';
  my $graph_type = ( $counter > 0 ) ? 'STACK' : 'AREA';

  my ( $metric_read, $metric_write, $resolution );

  my $division = 1;
  if ( $metric eq 'data' ) {
    $metric_read  = 'reads_bytes';
    $metric_write = 'writes_bytes';
    $division     = 1000 * 2;
  }
  elsif ( $metric eq 'iops' ) {
    $metric_read  = 'reads';
    $metric_write = 'writes';
  }
  elsif ( $metric eq 'latency' ) {
    $metric_read  = 'read_seconds';
    $metric_write = 'write_seconds';
  }
  elsif ( $metric eq 'net' ) {
    $metric_read  = 'receive_bytes';
    $metric_write = 'transmit_bytes';
    $division     = 1000 ** 2;
  }
  elsif ( $metric eq 'network' ) {
    $metric_read  = 'receive_bytes';
    $metric_write = 'transmit_bytes';
    $division     = 1000 ** 2;
  }

  $cmd_def  .= " DEF:write_${counter}=\"$filepath\":$metric_write:AVERAGE";
  $cmd_def  .= " DEF:read_${counter}=\"$filepath\":$metric_read:AVERAGE";
  $cmd_cdef .= " CDEF:write_text_${counter}=write_${counter},$division,/";
  $cmd_cdef .= " CDEF:read_text_${counter}=read_${counter},$division,/";

  $cmd_cdef .= " CDEF:read_graph_${counter}=read_${counter},-1,*";

  # $url_item is used in `ret_graph_param` to transform legends' table in `detail-graph-cgi.pl`
  my $url_item = "openshift-$type-$metric-aggr";
  if ( $group_type eq "project" ) {
    $url_item = "openshift-" . $type . "-$metric-aggr";
  }

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

  $cmd_legend_upper .= " ${graph_type}:write_${counter}${color2}: ";
  $cmd_legend_lower .= " ${graph_type}:0${color2}:\" \"";
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

sub graph_cpu_percent_aggr {
  my $type        = shift;    # value: 'node'
  my $filepath    = shift;
  my $counter     = shift;
  my $color       = shift;
  my $label       = shift;
  my $group_label = shift;
  my $group_type  = shift;    # value: 'pool' (for pool or custom groups) or 'host'

  # RRD command parts
  my $cmd_def = my $cmd_cdef = my $cmd_legend = '';
  my ( $metric, $graph_type );

  $graph_type = 'LINE1';

  $cmd_def  .= " DEF:cpu_${counter}=\"${filepath}\":cpu:AVERAGE";
  $cmd_def  .= " DEF:cpu_allocatable_${counter}=\"${filepath}\":cpu_allocatable:AVERAGE";
  $cmd_cdef .= " CDEF:percent_${counter}=cpu_allocatable_${counter},100,/";
  $cmd_cdef .= " CDEF:custom_graph_${counter}=cpu_${counter},percent_${counter},/";

  my $url_item = "openshift-" . $type . "-cpu-percent-aggr";

  my $label_space = get_formatted_label($label);
  my $group_space = get_formatted_label($group_label);

  # $uuid is used to form hypertext links in legends' tables
  my $uuid = get_uuid_from_filepath( $type, $filepath );

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

sub graph_pods_aggr {
  my $type        = shift;    # value: 'pod-container'
  my $metric_type = shift;    # value: 'cores'
  my $filepath    = shift;
  my $counter     = shift;
  my $color       = shift;
  my $label       = shift;
  my $group_label = shift;
  my $group_type  = shift;    # value: 'pool' (for pool or custom groups) or 'host'

  # RRD command parts
  my $cmd_def = my $cmd_cdef = my $cmd_legend = '';
  my ( $metric, $graph_type );

  $metric     = $metric_type;
  $graph_type = 'AREA';

  $cmd_def  .= " DEF:${metric}_${counter}=\"${filepath}\":${metric}:AVERAGE";
  $cmd_cdef .= " CDEF:custom_graph_${counter}=${metric}_${counter},1,/";

  my $url_item = "openshift-" . $type . "-pods-aggr";

  my $label_space = get_formatted_label($label);
  my $group_space = get_formatted_label($group_label);

  # $uuid is used to form hypertext links in legends' tables
  my $uuid = get_uuid_from_filepath( $type, $filepath );

  if ( $graph_type eq 'AREA' && $counter > 0 ) {
    $graph_type = 'STACK';
  }
  $cmd_legend .= " ${graph_type}:custom_graph_${counter}${color}:\" \"";
  $cmd_legend .= " COMMENT:\"$group_space  $label_space\"";
  $cmd_legend .= " GPRINT:custom_graph_${counter}:AVERAGE:\" %6.2lf\"";
  $cmd_legend .= " GPRINT:custom_graph_${counter}:MAX:\" %6.2lf    \"";
  $cmd_legend .= " PRINT:custom_graph_${counter}:AVERAGE:\" %6.2lf $delimiter $url_item $delimiter $label $delimiter $color $delimiter $color\"";
  $cmd_legend .= " PRINT:custom_graph_${counter}:MAX:\" %6.2lf $delimiter $label $delimiter ${group_label} $delimiter $uuid\"";
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
  my $type        = shift;    # value: 'pod-container'
  my $metric_type = shift;    # value: 'cores'
  my $filepath    = shift;
  my $counter     = shift;
  my $color       = shift;
  my $label       = shift;
  my $group_label = shift;
  my $group_type  = shift;    # value: 'pool' (for pool or custom groups) or 'host'

  # RRD command parts
  my $cmd_def = my $cmd_cdef = my $cmd_legend = '';
  my ( $metric, $graph_type );

  $metric     = $metric_type;
  $graph_type = 'AREA';

  $cmd_def  .= " DEF:${metric}_${counter}=\"${filepath}\":${metric}:AVERAGE";
  $cmd_cdef .= " CDEF:custom_graph_${counter}=${metric}_${counter},1,/";

  if ( $type eq "container" ) {
    $type = "pod-container";
  }

  my $url_item = "openshift-" . $type . "-cpu-aggr";
  if ( $group_type eq "project" ) {
    $url_item = "openshift-project-" . $type . "-cpu-aggr";
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
  $cmd_legend .= " GPRINT:custom_graph_${counter}:AVERAGE:\" %6.2lf\"";
  $cmd_legend .= " GPRINT:custom_graph_${counter}:MAX:\" %6.2lf    \"";
  $cmd_legend .= " PRINT:custom_graph_${counter}:AVERAGE:\" %6.2lf $delimiter $url_item $delimiter $label $delimiter $color $delimiter $color\"";
  $cmd_legend .= " PRINT:custom_graph_${counter}:MAX:\" %6.2lf $delimiter $label $delimiter ${group_label} $delimiter $uuid\"";
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
  my $type        = shift;    # value: 'pod-container'
  my $metric_type = shift;    # value: 'cores'
  my $filepath    = shift;
  my $counter     = shift;
  my $color       = shift;
  my $label       = shift;
  my $group_label = shift;
  my $group_type  = shift;    # value: 'pool' (for pool or custom groups) or 'host'

  # RRD command parts
  my $cmd_def = my $cmd_cdef = my $cmd_legend = '';
  my ( $metric, $graph_type );

  $metric     = $metric_type;
  $graph_type = 'AREA';

  my $mib2gib = 1024**1;

  $cmd_def  .= " DEF:${metric}_${counter}=\"${filepath}\":${metric}:AVERAGE";
  $cmd_cdef .= " CDEF:custom_graph_${counter}=${metric}_${counter},$mib2gib,/";

  if ( $type eq "container" ) {
    $type = "pod-container";
  }

  my $url_item = "openshift-" . $type . "-memory-aggr";
  if ( $group_type eq "project" ) {
    $url_item = "openshift-project-" . $type . "-memory-aggr";
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
  $cmd_legend .= " GPRINT:custom_graph_${counter}:AVERAGE:\" %6.0lf\"";
  $cmd_legend .= " GPRINT:custom_graph_${counter}:MAX:\" %6.0lf    \"";
  $cmd_legend .= " PRINT:custom_graph_${counter}:AVERAGE:\" %6.0lf $delimiter $url_item $delimiter $label $delimiter $color $delimiter $color\"";
  $cmd_legend .= " PRINT:custom_graph_${counter}:MAX:\" %6.0lf $delimiter $label $delimiter ${group_label} $delimiter $uuid\"";
  $cmd_legend .= " COMMENT:\\n";

  # return the data
  my %result = (
    cmd_def    => $cmd_def,
    cmd_cdef   => $cmd_cdef,
    cmd_legend => $cmd_legend
  );

  return \%result;
}

################################################################################

1;
