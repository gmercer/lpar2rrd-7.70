# DockerGraph.pm
# keep Docker graph generation in one place, if possible
# (separated from `detail-graph-cgi.pl`)

package DockerGraph;

use strict;
use warnings;

use Data::Dumper;

use DockerDataWrapper;

defined $ENV{INPUTDIR} || warn( localtime() . ': INPUTDIR undefined, config etc/lpar2rrd.cfg probably has not been loaded ' . __FILE__ . ':' . __LINE__ ) && exit 1;

my $inputdir     = $ENV{INPUTDIR};
my $wrkdir       = "$inputdir/data";
my $proxmox_path = "$wrkdir/Docker";

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

  my $label = DockerDataWrapper::get_label( $type, $uuid );
  $label = length($label) >= 12 ? substr( $label, 0, 12 ) : $label;
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
  my $limit = shift;
  my $result = '';
  $result .= " --vertical-label=\"$legend\"";
  $result .= " --lower-limit=0.00";

  if (defined $limit) {
    $result .= " --upper-limit=$limit";
  }

  return $result;
}

sub get_params_memory {
  my $type   = shift;
  my $result = '';
  if ( defined $type && $type eq "instance" ) {
    $result .= " --vertical-label=\"Memory in [MB]\"";
  }
  else {
    $result .= " --vertical-label=\"Memory in [GB]\"";
  }
  $result .= " --lower-limit=0.00";
  $result .= " --upper-limit=0.01";

  return $result;
}

sub get_params_lan {
  my $result = '';
  $result .= " --vertical-label=\"Read - MB/sec - Write\"";
  $result .= " --lower-limit=0.00";
  $result .= " --upper-limit=0.01";

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
      $result .= " --upper-limit=0.01";
    }
    elsif ( $type eq 'iops' ) {
      $unit = 'IOPS';
      $result .= " --vertical-label=\"Read - $unit - Write\"";
      $result .= " --upper-limit=1";
    }
  }
  else {
    $result .= " --vertical-label=\"Read - $unit - Write\"";
    $result .= " --upper-limit=0.01";
  }

  return $result;
}

################################################################################

sub graph_cpu_real {
  my $uuid = shift;
  my $skip_acl = shift || 0; # optional flag

  # necessary information
  my $rrd = DockerDataWrapper::get_filepath_rrd( { type => 'container', uuid => $uuid, skip_acl => $skip_acl } );

  # RRD command parts
  my $cmd_params = get_params_cpu();
  my $cmd_def    = my $cmd_cdef = my $cmd_legend = '';

  $cmd_def  .= " DEF:cpu_usage=\"$rrd\":cpu_usage:AVERAGE";
  $cmd_def  .= " DEF:cpu_cores=\"$rrd\":cpu_number:AVERAGE";
  $cmd_cdef .= " CDEF:used=cpu_usage,cpu_cores,/";

  $cmd_legend .= " COMMENT:\"[%]         Avrg       Max\\n\"";
  $cmd_legend .= " LINE1:used#ff4040:\" Util \"";
  $cmd_legend .= " GPRINT:used:AVERAGE:\" %6.0lf\"";
  $cmd_legend .= " GPRINT:used:MAX:\"  %6.0lf\"";
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
  my $uuid = shift;
  my $skip_acl = shift || 0; # optional flag

  # necessary information
  my $rrd = DockerDataWrapper::get_filepath_rrd( { type => 'container', uuid => $uuid, skip_acl => $skip_acl } );

  # RRD command parts
  my $cmd_params = get_params_cpu();
  my $cmd_def    = my $cmd_cdef = my $cmd_legend = '';

  $cmd_def  .= " DEF:cpu_usage=\"$rrd\":cpu_usage:AVERAGE";
  $cmd_cdef .= " CDEF:used=cpu_usage,1,*";

  $cmd_legend .= " COMMENT:\"[%]         Avrg       Max\\n\"";
  $cmd_legend .= " LINE1:used#ff4040:\" Util \"";
  $cmd_legend .= " GPRINT:used:AVERAGE:\" %6.0lf\"";
  $cmd_legend .= " GPRINT:used:MAX:\"  %6.0lf\"";
  $cmd_legend .= " COMMENT:\\n";

  my %result = (
    cmd_params => $cmd_params,
    cmd_def    => $cmd_def,
    cmd_cdef   => $cmd_cdef,
    cmd_legend => $cmd_legend,
  );

  return \%result;
}

sub graph_cpu_cores {
  my $uuid = shift;
  my $skip_acl = shift || 0; # optional flag

  # necessary information
  my $rrd = DockerDataWrapper::get_filepath_rrd( { type => 'container', uuid => $uuid, skip_acl => $skip_acl } );

  # RRD command parts
  my $cmd_params = get_params_cpu('cores');
  my $cmd_def    = my $cmd_cdef = my $cmd_legend = '';

  $cmd_def  .= " DEF:cpu_usage=\"$rrd\":cpu_usage:AVERAGE";
  $cmd_def  .= " DEF:cpu_cores=\"$rrd\":cpu_number:AVERAGE";

  $cmd_cdef .= " CDEF:used=cpu_usage,100,/";
  $cmd_cdef .= " CDEF:total=cpu_cores,1,*";

  $cmd_legend .= " COMMENT:\"[cores]         Avrg       Max\\n\"";
  $cmd_legend .= " AREA:used#ff4040:\" Usage  \"";
  $cmd_legend .= " GPRINT:used:AVERAGE:\" %6.1lf\"";
  $cmd_legend .= " GPRINT:used:MAX:\"  %6.1lf\"";
  $cmd_legend .= " COMMENT:\\n";
  $cmd_legend .= " LINE2:total#000000:\" Total  \"";
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

sub graph_memory {
  my $uuid = shift;
  my $skip_acl = shift || 0; # optional flag

  # necessary information
  my $rrd = DockerDataWrapper::get_filepath_rrd( { type => 'container', uuid => $uuid, skip_acl => $skip_acl } );

  # RRD command parts
  my $cmd_params = get_params_cpu();
  my $cmd_def    = my $cmd_cdef = my $cmd_legend = '';

  $cmd_def .= " DEF:memory_used=\"$rrd\":memory_used:AVERAGE";
  $cmd_def .= " DEF:memory_total=\"$rrd\":memory_available:AVERAGE";

  my $b2gb = 1000 * 1000 * 1000;
  $cmd_cdef .= " CDEF:total=memory_total,$b2gb,/";
  $cmd_cdef .= " CDEF:used=memory_used,$b2gb,/";

  $cmd_legend .= " COMMENT:\"[GB]         Avrg       Max\\n\"";

  $cmd_legend .= " AREA:used#ff4040:\" Used \"";
  $cmd_legend .= " GPRINT:used:AVERAGE:\" %6.1lf\"";
  $cmd_legend .= " GPRINT:used:MAX:\"  %6.1lf\"";
  $cmd_legend .= " COMMENT:\\n";
  $cmd_legend .= " LINE2:total#000000:\" Total\"";
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

sub graph_net {
  my $uuid = shift;
  my $skip_acl = shift || 0; # optional flag

  # necessary information
  my $rrd = DockerDataWrapper::get_filepath_rrd( { type => 'container', uuid => $uuid, skip_acl => $skip_acl } );

  # RRD command parts
  my $cmd_params = get_params_cpu();
  my $cmd_def    = my $cmd_cdef = my $cmd_legend = '';

  my ( $metric_write, $metric_read, $division );

  $division     = 1000 ** 2;
  $metric_write = 'tx_bytes';
  $metric_read  = 'rx_bytes';

  $cmd_def .= " DEF:metric_write=\"$rrd\":${metric_write}:AVERAGE";
  $cmd_def .= " DEF:metric_read=\"$rrd\":${metric_read}:AVERAGE";

  $cmd_cdef .= " CDEF:read=metric_read,$division,/";
  $cmd_cdef .= " CDEF:write=metric_write,$division,/";
  $cmd_cdef .= " CDEF:read_neg=0,read,-";

  $cmd_legend .= " COMMENT:\"[MB/s]       Avrg       Max\\n\"";
  $cmd_legend .= " LINE1:read_neg#FF0000:\" Rx  \"";
  $cmd_legend .= " GPRINT:read:AVERAGE:\" %6.2lf\"";
  $cmd_legend .= " GPRINT:read:MAX:\"  %6.2lf\"";
  $cmd_legend .= " COMMENT:\\n";
  $cmd_legend .= " LINE1:write#0000FF:\" Tx \"";
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

sub graph_data {
  my $uuid = shift;
  my $skip_acl = shift || 0; # optional flag

  # necessary information
  my $rrd = DockerDataWrapper::get_filepath_rrd( { type => 'container', uuid => $uuid, skip_acl => $skip_acl } );

  # RRD command parts
  my $cmd_params = get_params_cpu();
  my $cmd_def    = my $cmd_cdef = my $cmd_legend = '';

  my ( $metric_write, $metric_read, $division );

  $metric_write = 'write_bytes';
  $metric_read  = 'read_bytes';
  $division     = 1000 * 1000;

  $cmd_def .= " DEF:metric_write=\"$rrd\":${metric_write}:AVERAGE";
  $cmd_def .= " DEF:metric_read=\"$rrd\":${metric_read}:AVERAGE";

  $cmd_cdef .= " CDEF:read=metric_read,$division,/";
  $cmd_cdef .= " CDEF:write=metric_write,$division,/";
  $cmd_cdef .= " CDEF:read_neg=0,read,-";

  $cmd_legend .= " COMMENT:\"[MB/s]       Avrg       Max\\n\"";
  $cmd_legend .= " LINE1:read_neg#FF0000:\" Read  \"";
  $cmd_legend .= " GPRINT:read:AVERAGE:\" %6.2lf\"";
  $cmd_legend .= " GPRINT:read:MAX:\"  %6.2lf\"";
  $cmd_legend .= " COMMENT:\\n";
  $cmd_legend .= " LINE1:write#0000FF:\" Write\"";
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

sub graph_io {
  my $uuid = shift;
  my $skip_acl = shift || 0; # optional flag

  # necessary information
  my $rrd = DockerDataWrapper::get_filepath_rrd( { type => 'container', uuid => $uuid, skip_acl => $skip_acl } );

  # RRD command parts
  my $cmd_params = get_params_cpu();
  my $cmd_def    = my $cmd_cdef = my $cmd_legend = '';

  my ( $metric_write, $metric_read, $division );

  $metric_write = 'write_io';
  $metric_read  = 'read_io';

  $cmd_def .= " DEF:metric_write=\"$rrd\":${metric_write}:AVERAGE";
  $cmd_def .= " DEF:metric_read=\"$rrd\":${metric_read}:AVERAGE";

  $cmd_cdef .= " CDEF:read=metric_read,1,*";
  $cmd_cdef .= " CDEF:write=metric_write,1,*";
  $cmd_cdef .= " CDEF:read_neg=0,read,-";

  $cmd_legend .= " COMMENT:\"[MB/s]       Avrg       Max\\n\"";
  $cmd_legend .= " LINE1:read_neg#FF0000:\" Read  \"";
  $cmd_legend .= " GPRINT:read:AVERAGE:\" %6.0lf\"";
  $cmd_legend .= " GPRINT:read:MAX:\"  %6.0lf\"";
  $cmd_legend .= " COMMENT:\\n";
  $cmd_legend .= " LINE1:write#0000FF:\" Write\"";
  $cmd_legend .= " GPRINT:write:AVERAGE:\"  %6.0lf\"";
  $cmd_legend .= " GPRINT:write:MAX:\"  %6.0lf\"";
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

sub graph_size {
  my $uuid = shift;
  my $type = shift;
  my $skip_acl = shift || 0; # optional flag

  # necessary information
  my $rrd = DockerDataWrapper::get_filepath_rrd( { type => $type, uuid => $uuid, skip_acl => $skip_acl } );

  # RRD command parts
  my $cmd_params = get_params_cpu();
  my $cmd_def    = my $cmd_cdef = my $cmd_legend = '';

  my $metric = $type eq "container" ? "size_root_fs" : "size";

  $cmd_def .= " DEF:size=\"$rrd\":\"$metric\":AVERAGE";

  my $b2gb = 1000 * 1000 * 1000;
  $cmd_cdef .= " CDEF:cap_size=size,$b2gb,/";

  $cmd_legend .= " COMMENT:\"[GB]         Avrg       Max\\n\"";

  $cmd_legend .= " AREA:cap_size#ff4040:\" Size \"";
  $cmd_legend .= " GPRINT:cap_size:AVERAGE:\" %6.2lf\"";
  $cmd_legend .= " GPRINT:cap_size:MAX:\"  %6.2lf\"";
  $cmd_legend .= " COMMENT:\\n";

  my %result = (
    cmd_params => $cmd_params,
    cmd_def    => $cmd_def,
    cmd_cdef   => $cmd_cdef,
    cmd_legend => $cmd_legend,
  );

  return \%result;
}

sub graph_size_rw {
  my $uuid = shift;
  my $skip_acl = shift || 0; # optional flag

  # necessary information
  my $rrd = DockerDataWrapper::get_filepath_rrd( { type => 'container', uuid => $uuid, skip_acl => $skip_acl } );

  # RRD command parts
  my $cmd_params = get_params_cpu();
  my $cmd_def    = my $cmd_cdef = my $cmd_legend = '';

  $cmd_def .= " DEF:size=\"$rrd\":size_rw:AVERAGE";

  my $b2gb = 1000 * 1000 * 1000;
  $cmd_cdef .= " CDEF:cap_size=size,$b2gb,/";

  $cmd_legend .= " COMMENT:\"[GB]         Avrg       Max\\n\"";

  $cmd_legend .= " AREA:cap_size#ff4040:\" Size \"";
  $cmd_legend .= " GPRINT:cap_size:AVERAGE:\" %6.2lf\"";
  $cmd_legend .= " GPRINT:cap_size:MAX:\"  %6.2lf\"";
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

sub graph_size_aggr {
  my $type        = shift;
  my $filepath    = shift;
  my $counter     = shift;
  my $color       = shift;
  my $label       = shift;
  my $group_label = shift;
  my $group_type  = shift;
  my $metric      = shift;
  my $total       = shift;

  my $cmd_def = my $cmd_cdef = my $cmd_legend = '';
  my ( $metric_total, $metric_used );

  my $b2gb = 1000 * 1000 * 1000;
  $cmd_def  .= " DEF:metric_size_${counter}=\"${filepath}\":${metric}:AVERAGE";
  $cmd_cdef .= " CDEF:size_${counter}=metric_size_${counter},$b2gb,/";

  my $graph_type = ( $counter > 0 ) ? 'STACK' : 'AREA';

  $type = ( $total eq "1" ) ? "total-$type" : $type;
  my $url_item = "docker-" . $type . "-size-aggr";

  my $label_space = get_formatted_label($label);
  my $group_space = get_formatted_label($group_label);

  # $uuid is used to form hypertext links in legends' tables
  my $uuid = get_uuid_from_filepath( $type, $filepath );

  $cmd_legend .= " ${graph_type}:size_${counter}${color}:\" \"";
  $cmd_legend .= " COMMENT:\"$group_space  $label_space\"";
  $cmd_legend .= " GPRINT:size_${counter}:AVERAGE:\" %6.1lf\"";
  $cmd_legend .= " GPRINT:size_${counter}:MAX:\" %6.1lf    \"";
  $cmd_legend .= " PRINT:size_${counter}:AVERAGE:\" %6.1lf $delimiter $url_item $delimiter $label $delimiter $color $delimiter $color\"";
  $cmd_legend .= " PRINT:size_${counter}:MAX:\" %6.1lf $delimiter $label $delimiter ${group_label} $delimiter $uuid\"";
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
  my $type        = shift;
  my $filepath    = shift;
  my $counter     = shift;
  my $color       = shift;
  my $label       = shift;
  my $group_label = shift;
  my $group_type  = shift;
  my $total       = shift;

  my $cmd_def = my $cmd_cdef = my $cmd_legend = '';
  my ( $metric_total, $metric_used );

  $cmd_def  .= " DEF:cpu_usage_${counter}=\"${filepath}\":cpu_usage:AVERAGE";
  $cmd_cdef .= " CDEF:cores_used_${counter}=cpu_usage_${counter},100,/";

  my $graph_type = ( $counter > 0 ) ? 'STACK' : 'AREA';

  $type = ( $total eq "1" ) ? "total-$type" : $type;
  my $url_item = "docker-" . $type . "-cpu-aggr";

  my $label_space = get_formatted_label($label);
  my $group_space = get_formatted_label($group_label);

  # $uuid is used to form hypertext links in legends' tables
  my $uuid = get_uuid_from_filepath( $type, $filepath );

  $cmd_legend .= " ${graph_type}:cores_used_${counter}${color}:\" \"";
  $cmd_legend .= " COMMENT:\"$group_space  $label_space\"";
  $cmd_legend .= " GPRINT:cores_used_${counter}:AVERAGE:\" %6.1lf\"";
  $cmd_legend .= " GPRINT:cores_used_${counter}:MAX:\" %6.1lf    \"";
  $cmd_legend .= " PRINT:cores_used_${counter}:AVERAGE:\" %6.1lf $delimiter $url_item $delimiter $label $delimiter $color $delimiter $color\"";
  $cmd_legend .= " PRINT:cores_used_${counter}:MAX:\" %6.1lf $delimiter $label $delimiter ${group_label} $delimiter $uuid\"";
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
  my $type        = shift;
  my $filepath    = shift;
  my $counter     = shift;
  my $color       = shift;
  my $label       = shift;
  my $group_label = shift;
  my $group_type  = shift;
  my $total       = shift;

  my $cmd_def = my $cmd_cdef = my $cmd_legend = '';
  my ( $metric_total, $metric_used );

  my $b2gb = 1000 * 1000 * 1000;

  $cmd_def  .= " DEF:memory_used_${counter}=\"${filepath}\":memory_used:AVERAGE";
  $cmd_cdef .= " CDEF:mem_${counter}=memory_used_${counter},$b2gb,/";

  my $graph_type = ( $counter > 0 ) ? 'STACK' : 'AREA';

  $type = ( $total eq "1" ) ? "total-$type" : $type;
  my $url_item = "docker-" . $type . "-memory-aggr";

  my $label_space = get_formatted_label($label);
  my $group_space = get_formatted_label($group_label);

  # $uuid is used to form hypertext links in legends' tables
  my $uuid = get_uuid_from_filepath( $type, $filepath );

  $cmd_legend .= " ${graph_type}:mem_${counter}${color}:\" \"";
  $cmd_legend .= " COMMENT:\"$group_space  $label_space\"";
  $cmd_legend .= " GPRINT:mem_${counter}:AVERAGE:\" %6.1lf\"";
  $cmd_legend .= " GPRINT:mem_${counter}:MAX:\" %6.1lf    \"";
  $cmd_legend .= " PRINT:mem_${counter}:AVERAGE:\" %6.1lf $delimiter $url_item $delimiter $label $delimiter $color $delimiter $color\"";
  $cmd_legend .= " PRINT:mem_${counter}:MAX:\" %6.1lf $delimiter $label $delimiter ${group_label} $delimiter $uuid\"";
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

  my $division = 1000 ** 2;
  my ( $metric_read, $metric_write );
  if ( $metric eq "data" ) {
    $metric_write = 'write_bytes';
    $metric_read  = 'read_bytes';
  }
  elsif ( $metric eq "net" ) {
    $metric_write = 'tx_bytes';
    $metric_read  = 'rx_bytes';
  }
  elsif ( $metric eq "io" ) {
    $division     = 1;
    $metric_write = 'write_io';
    $metric_read  = 'read_io';
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

  if ( $metric eq "io" ) {
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
  } else {
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
  }

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
  my $type     = shift;    # value: 'volume' or 'container'
  my $filepath = shift;

  my $uuid;
  $filepath =~ m/\/Docker\/(.*)\/(.*)\.rrd/;
  $uuid = $2;

  return $uuid;
}

################################################################################

1;
