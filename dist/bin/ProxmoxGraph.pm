# ProxmoxGraph.pm
# keep Proxmox graph generation in one place, if possible
# (separated from `detail-graph-cgi.pl`)

package ProxmoxGraph;

use strict;
use warnings;

use Data::Dumper;

use ProxmoxDataWrapper;
use CloudstackDataWrapper;

defined $ENV{INPUTDIR} || warn( localtime() . ': INPUTDIR undefined, config etc/lpar2rrd.cfg probably has not been loaded ' . __FILE__ . ':' . __LINE__ ) && exit 1;

my $inputdir     = $ENV{INPUTDIR};
my $wrkdir       = "$inputdir/data";
my $proxmox_path = "$wrkdir/Proxmox";

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

  my $label  = ProxmoxDataWrapper::get_label( $type, $uuid );
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
  } else {
    #$label_space = substr($label_space, 0, 20 - length($label_space))
    $label_space = substr($label_space, 0, 11 - length($label_space)) . "..." . substr($label_space, length($label_space)-6, length($label_space));
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
  my $type   = shift;
  my $result = '';
  if ( defined $type && $type eq "instance" ) {
    $result .= " --vertical-label=\"Memory in [MB]\"";
  }
  else {
    $result .= " --vertical-label=\"Memory in [GB]\"";
  }
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
  my $rrd = ProxmoxDataWrapper::get_filepath_rrd( { type => $type, uuid => $uuid, skip_acl => $skip_acl } );

  # RRD command parts
  my $cmd_params = get_params_cpu();
  my $cmd_def    = my $cmd_cdef = my $cmd_legend = '';

  my ( $metric_cputotal, $metric_cpuused );

  $metric_cputotal = 'maxcpu';
  $metric_cpuused  = 'cpu';

  $cmd_def .= " DEF:cpu_used=\"$rrd\":${metric_cpuused}:AVERAGE";
  $cmd_def .= " DEF:cpu_total=\"$rrd\":${metric_cputotal}:AVERAGE";

  $cmd_cdef .= " CDEF:used=cpu_used,cpu_total,*";
  $cmd_cdef .= " CDEF:total=cpu_total,1,/";

  $cmd_legend .= " COMMENT:\"[cores]         Avrg       Max\\n\"";
  $cmd_legend .= " AREA:used#ff4040:\" Used   \"";
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

sub graph_cpu_percent {
  my $uuid = shift;
  my $type = shift;
  my $skip_acl = shift || 0; # optional flag

  # necessary information
  my $rrd = ProxmoxDataWrapper::get_filepath_rrd( { type => $type, uuid => $uuid, skip_acl => $skip_acl } );

  # RRD command parts
  my $cmd_params = get_params_cpu();
  my $cmd_def    = my $cmd_cdef = my $cmd_legend = '';

  my ( $metric_cputotal, $metric_cpuused );

  $metric_cpuused = 'cpu';

  $cmd_def  .= " DEF:cpu_used=\"$rrd\":${metric_cpuused}:AVERAGE";
  $cmd_cdef .= " CDEF:used=cpu_used,100,*";

  $cmd_legend .= " COMMENT:\"[%]            Avrg       Max\\n\"";
  $cmd_legend .= " LINE1:used#ff4040:\" Used \"";
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

sub graph_size {
  my $uuid = shift;
  my $type = shift;
  my $skip_acl = shift || 0; # optional flag

  # necessary information
  my $rrd = ProxmoxDataWrapper::get_filepath_rrd( { type => $type, uuid => $uuid, skip_acl => $skip_acl } );

  # RRD command parts
  my $cmd_params = get_params_cpu();
  my $cmd_def    = my $cmd_cdef = my $cmd_legend = '';

  my ( $metric_size, $metric_used );

  if ( $type eq 'storage' ) {
    $metric_size = 'total';
    $metric_used = 'used';
  }
  else {
    $metric_size = 'roottotal';
    $metric_used = 'rootused';
  }

  $cmd_def .= " DEF:metric_used=\"$rrd\":${metric_used}:AVERAGE";
  $cmd_def .= " DEF:metric_total=\"$rrd\":${metric_size}:AVERAGE";

  my $b2gb = 1024 ** 3;
  $cmd_cdef .= " CDEF:total=metric_total,$b2gb,/";
  $cmd_cdef .= " CDEF:used=metric_used,$b2gb,/";

  $cmd_legend .= " COMMENT:\"[GiB]           Avrg       Max\\n\"";
  $cmd_legend .= " AREA:used#ff4040:\" Used    \"";
  $cmd_legend .= " GPRINT:used:AVERAGE:\" %6.1lf\"";
  $cmd_legend .= " GPRINT:used:MAX:\"  %6.1lf\"";
  $cmd_legend .= " COMMENT:\\n";
  $cmd_legend .= " LINE2:total#000000:\" Total   \"";
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
  my $type = shift;
  my $skip_acl = shift || 0; # optional flag

  # necessary information
  my $rrd = ProxmoxDataWrapper::get_filepath_rrd( { type => $type, uuid => $uuid, skip_acl => $skip_acl } );

  # RRD command parts
  my $cmd_params = get_params_cpu();
  my $cmd_def    = my $cmd_cdef = my $cmd_legend = '';

  my ( $metric_memorytotal, $metric_memoryused );

  if ( $type eq 'node' ) {
    $metric_memorytotal = 'memtotal';
    $metric_memoryused  = 'memused';
  }
  else {
    $metric_memorytotal = 'maxmem';
    $metric_memoryused  = 'mem';
  }

  $cmd_def .= " DEF:memory_used=\"$rrd\":${metric_memoryused}:AVERAGE";
  $cmd_def .= " DEF:memory_total=\"$rrd\":${metric_memorytotal}:AVERAGE";

  my $b2gb = 1000 ** 3;
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

sub graph_swap {
  my $uuid = shift;
  my $type = shift;
  my $skip_acl = shift || 0; # optional flag

  # necessary information
  my $rrd = ProxmoxDataWrapper::get_filepath_rrd( { type => $type, uuid => $uuid, skip_acl => $skip_acl } );

  # RRD command parts
  my $cmd_params = get_params_cpu();
  my $cmd_def    = my $cmd_cdef = my $cmd_legend = '';

  my ( $metric_total, $metric_used );

  $metric_total = 'swaptotal';
  $metric_used  = 'swapused';

  $cmd_def .= " DEF:swap_used=\"$rrd\":${metric_used}:AVERAGE";
  $cmd_def .= " DEF:swap_total=\"$rrd\":${metric_total}:AVERAGE";

  my $b2gb = 1000 ** 3;
  $cmd_cdef .= " CDEF:total=swap_total,$b2gb,/";
  $cmd_cdef .= " CDEF:used=swap_used,$b2gb,/";

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

sub graph_iowait {
  my $uuid = shift;
  my $type = shift;
  my $skip_acl = shift || 0; # optional flag

  # necessary information
  my $rrd = ProxmoxDataWrapper::get_filepath_rrd( { type => $type, uuid => $uuid, skip_acl => $skip_acl } );

  # RRD command parts
  my $cmd_params = get_params_cpu();
  my $cmd_def    = my $cmd_cdef = my $cmd_legend = '';

  my $metric = 'iowait';

  $cmd_def .= " DEF:metric_iowait=\"$rrd\":${metric}:AVERAGE";

  my $percent = 100;
  $cmd_cdef .= " CDEF:iowait=metric_iowait,$percent,*";

  $cmd_legend .= " COMMENT:\"[%]                  Avrg       Max\\n\"";

  $cmd_legend .= " AREA:iowait#ff4040:\" CPU IO wait \"";
  $cmd_legend .= " GPRINT:iowait:AVERAGE:\" %6.0lf\"";
  $cmd_legend .= " GPRINT:iowait:MAX:\"  %6.0lf\"";
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
  my $type = shift;
  my $skip_acl = shift || 0; # optional flag

  # necessary information
  my $rrd = ProxmoxDataWrapper::get_filepath_rrd( { type => $type, uuid => $uuid, skip_acl => $skip_acl } );

  # RRD command parts
  my $cmd_params = get_params_cpu();
  my $cmd_def    = my $cmd_cdef = my $cmd_legend = '';

  my ( $metric_write, $metric_read, $division );

  $division     = 1000 ** 2;
  $metric_write = 'netout';
  $metric_read  = 'netin';

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

sub graph_data {
  my $uuid = shift;
  my $type = shift;
  my $skip_acl = shift || 0; # optional flag

  # necessary information
  my $rrd = ProxmoxDataWrapper::get_filepath_rrd( { type => $type, uuid => $uuid, skip_acl => $skip_acl } );

  # RRD command parts
  my $cmd_params = get_params_cpu();
  my $cmd_def    = my $cmd_cdef = my $cmd_legend = '';

  my ( $metric_write, $metric_read, $division );

  $metric_write = 'diskwrite';
  $metric_read  = 'diskread';
  $division     = 1000 ** 2;

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

################################################################################

sub graph_cpu_aggr {
  my $type        = shift;    # value: 'node'
  my $filepath    = shift;
  my $counter     = shift;
  my $color       = shift;
  my $label       = shift;
  my $group_label = shift;
  my $group_type  = shift;    # value: 'pool' (for pool or custom groups) or 'host'

  my $cmd_def = my $cmd_cdef = my $cmd_legend = '';
  my ( $metric_total, $metric_used );

  $metric_used  = 'cpu';
  $metric_total = 'maxcpu';

  $cmd_def .= " DEF:cpu_used_${counter}=\"${filepath}\":${metric_used}:AVERAGE";
  $cmd_def .= " DEF:cpu_total_${counter}=\"${filepath}\":${metric_total}:AVERAGE";

  $cmd_cdef .= " CDEF:used_percent_${counter}=cpu_total_${counter},cpu_used_${counter},*";
  $cmd_cdef .= " CDEF:custom_graph_${counter}=used_percent_${counter},1,/";

  my $graph_type = ( $counter > 0 ) ? 'STACK' : 'AREA';

  my $url_item = "proxmox-" . $type . "-cpu-aggr";

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

sub graph_cpu_percent_aggr {
  my $type        = shift;    # value: 'node'
  my $filepath    = shift;
  my $counter     = shift;
  my $color       = shift;
  my $label       = shift;
  my $group_label = shift;
  my $group_type  = shift;    # value: 'pool' (for pool or custom groups) or 'host'

  my $cmd_def = my $cmd_cdef = my $cmd_legend = '';
  my ( $metric_total, $metric_used );

  $metric_total = 'cpu';

  $cmd_def  .= " DEF:cpu_total_${counter}=\"${filepath}\":${metric_total}:AVERAGE";
  $cmd_cdef .= " CDEF:custom_graph_${counter}=cpu_total_${counter},100,*";

  my $graph_type = "LINE1";

  my $url_item = "proxmox-" . $type . "-cpu-percent-aggr";

  my $label_space = get_formatted_label($label);
  my $group_space = get_formatted_label($group_label);

  # $uuid is used to form hypertext links in legends' tables
  my $uuid = get_uuid_from_filepath( $type, $filepath );

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

sub graph_memory_aggr {
  my $type        = shift;    # value: 'node'
  my $filepath    = shift;
  my $counter     = shift;
  my $color       = shift;
  my $label       = shift;
  my $group_label = shift;
  my $group_type  = shift;    # value: 'pool' (for pool or custom groups) or 'host'
  my $mem_type    = shift;

  # RRD command parts
  my $cmd_def = my $cmd_cdef = my $cmd_legend = '';

  my ( $metric_total, $metric_used );
  if ( $type eq "node" ) {
    $metric_total = 'memtotal';
    $metric_used  = 'memused';
  }
  elsif ( $type eq "vm" || $type eq "lxc" ) {
    $metric_total = 'maxmem';
    $metric_used  = 'mem';
  }

  my $b2gb = 1000 ** 3;
  $cmd_def  .= " DEF:memory_used_${counter}=\"${filepath}\":${metric_used}:AVERAGE";
  $cmd_def  .= " DEF:memory_total_${counter}=\"${filepath}\":${metric_total}:AVERAGE";
  $cmd_cdef .= " CDEF:memory_free_${counter}=memory_total_${counter},memory_used_${counter},-";

  if ( $mem_type eq "used" ) {
    $cmd_cdef .= " CDEF:custom_graph_${counter}=memory_used_${counter},$b2gb,/";
  }
  else {
    $cmd_cdef .= " CDEF:custom_graph_${counter}=memory_free_${counter},$b2gb,/";
  }

  my $graph_type = ( $counter > 0 ) ? 'STACK' : 'AREA';

  my $url_item = "proxmox-" . $type . "-memory-aggr";

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

sub graph_net_aggr {
  my $type        = shift;    # value: 'node' or 'container'
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

  #my $graph_type = 'LINE1';

  my $division = 1000 ** 2;
  my ( $metric_read, $metric_write );
  $metric_write = 'netout';
  $metric_read  = 'netin';

  $cmd_def .= " DEF:write_${counter}=\"$filepath\":${metric_write}:AVERAGE";
  $cmd_def .= " DEF:read_${counter}=\"$filepath\":${metric_read}:AVERAGE";

  $cmd_cdef .= " CDEF:write_text_${counter}=write_${counter},$division,/";
  $cmd_cdef .= " CDEF:read_text_${counter}=read_${counter},$division,/";
  $cmd_cdef .= " CDEF:read_graph_${counter}=read_text_${counter},-1,*";

  # $url_item is used in `ret_graph_param` to transform legends' table in `detail-graph-cgi.pl`
  my $url_item = "proxmox-$type-net-aggr";

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

sub graph_data_aggr {
  my $type        = shift;    # value: 'node' or 'container'
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

  my $division = 1;
  my ( $metric_read, $metric_write );
  $metric_write = 'diskwrite';
  $metric_read  = 'diskread';
  $division     = 1000 ** 2;

  $cmd_def .= " DEF:write_${counter}=\"$filepath\":${metric_write}:AVERAGE";
  $cmd_def .= " DEF:read_${counter}=\"$filepath\":${metric_read}:AVERAGE";

  $cmd_cdef .= " CDEF:write_text_${counter}=write_${counter},$division,/";
  $cmd_cdef .= " CDEF:read_text_${counter}=read_${counter},$division,/";
  $cmd_cdef .= " CDEF:read_graph_${counter}=read_text_${counter},-1,*";

  # $url_item is used in `ret_graph_param` to transform legends' table in `detail-graph-cgi.pl`
  my $url_item = "proxmox-$type-data-aggr";

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

sub graph_size_aggr {
  my $type        = shift;    # value: 'node'
  my $filepath    = shift;
  my $counter     = shift;
  my $color       = shift;
  my $label       = shift;
  my $group_label = shift;
  my $group_type  = shift;    # value: 'pool' (for pool or custom groups) or 'host'
  my $mem_type    = shift;

  # RRD command parts
  my $cmd_def = my $cmd_cdef = my $cmd_legend = '';

  my ( $metric_total, $metric_used );
  if ( $type eq "node" ) {
    $metric_total = 'roottotal';
    $metric_used  = 'rootused';
  }
  else {
    $metric_total = 'total';
    $metric_used  = 'used';
  }

  $cmd_def .= " DEF:metric_used_${counter}=\"${filepath}\":${metric_used}:AVERAGE";
  $cmd_def .= " DEF:metric_total_${counter}=\"${filepath}\":${metric_total}:AVERAGE";

  my $b2gb = 1024 ** 3;
  $cmd_cdef .= " CDEF:total_${counter}=metric_total_${counter},$b2gb,/";
  $cmd_cdef .= " CDEF:used_${counter}=metric_used_${counter},$b2gb,/";
  $cmd_cdef .= " CDEF:free_${counter}=total_${counter},used_${counter},-";

  if ( $mem_type eq "used" ) {
    $cmd_cdef .= " CDEF:custom_graph_${counter}=used_${counter},1,/";
  }
  else {
    $cmd_cdef .= " CDEF:custom_graph_${counter}=free_${counter},1,/";
  }

  my $graph_type = ( $counter > 0 ) ? 'STACK' : 'AREA';

  my $url_item;
  if ( $type eq "node" ) {
    $url_item = "proxmox-" . $type . "-disk-aggr";
  }
  else {
    $url_item = "proxmox-" . $type . "-size-aggr";
  }

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

sub graph_swap_aggr {
  my $type        = shift;    # value: 'node'
  my $filepath    = shift;
  my $counter     = shift;
  my $color       = shift;
  my $label       = shift;
  my $group_label = shift;
  my $group_type  = shift;    # value: 'pool' (for pool or custom groups) or 'host'
  my $mem_type    = shift;

  # RRD command parts
  my $cmd_def = my $cmd_cdef = my $cmd_legend = '';

  my ( $metric_total, $metric_used );
  if ( $type eq "node" ) {
    $metric_total = 'swaptotal';
    $metric_used  = 'swapused';
  }

  $cmd_def .= " DEF:metric_used_${counter}=\"${filepath}\":${metric_used}:AVERAGE";
  $cmd_def .= " DEF:metric_total_${counter}=\"${filepath}\":${metric_total}:AVERAGE";

  my $b2gb = 1024 ** 3;
  $cmd_cdef .= " CDEF:total_${counter}=metric_total_${counter},$b2gb,/";
  $cmd_cdef .= " CDEF:used_${counter}=metric_used_${counter},$b2gb,/";
  $cmd_cdef .= " CDEF:free_${counter}=total_${counter},used_${counter},-";

  if ( $mem_type eq "used" ) {
    $cmd_cdef .= " CDEF:custom_graph_${counter}=used_${counter},1,/";
  }
  else {
    $cmd_cdef .= " CDEF:custom_graph_${counter}=free_${counter},1,/";
  }

  my $graph_type = ( $counter > 0 ) ? 'STACK' : 'AREA';

  my $url_item = "proxmox-" . $type . "-swap-aggr";

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

sub graph_io_aggr {
  my $type        = shift;    # value: 'node'
  my $filepath    = shift;
  my $counter     = shift;
  my $color       = shift;
  my $label       = shift;
  my $group_label = shift;
  my $group_type  = shift;    # value: 'pool' (for pool or custom groups) or 'host'

  # RRD command parts
  my $cmd_def = my $cmd_cdef = my $cmd_legend = '';

  my ( $metric_total, $metric_used );
  if ( $type eq "node" ) {
    $metric_total = 'iowait';
  }

  $cmd_def .= " DEF:metric_total_${counter}=\"${filepath}\":${metric_total}:AVERAGE";

  my $percent = 100;
  $cmd_cdef .= " CDEF:custom_graph_${counter}=metric_total_${counter},$percent,*";

  my $graph_type = ( $counter > 0 ) ? 'STACK' : 'AREA';

  my $url_item = "proxmox-" . $type . "-io-aggr";

  my $label_space = get_formatted_label($label);
  my $group_space = get_formatted_label($group_label);

  # $uuid is used to form hypertext links in legends' tables
  my $uuid = get_uuid_from_filepath( $type, $filepath );

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

sub get_uuid_from_filepath {
  my $type     = shift;    # value: 'vm' or 'host'
  my $filepath = shift;

  my $uuid;
  $filepath =~ m/\/Proxmox\/(.*)\/(.*)\.rrd/;
  $uuid = $2;

  return $uuid;
}

################################################################################

1;
