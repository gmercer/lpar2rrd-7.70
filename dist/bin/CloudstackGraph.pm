# CloudstackGraph.pm
# keep Cloudstack graph generation in one place, if possible
# (separated from `detail-graph-cgi.pl`)

package CloudstackGraph;

use strict;
use warnings;

use Data::Dumper;

use KubernetesDataWrapper;

defined $ENV{INPUTDIR} || warn( localtime() . ': INPUTDIR undefined, config etc/lpar2rrd.cfg probably has not been loaded ' . __FILE__ . ':' . __LINE__ ) && exit 1;

my $inputdir        = $ENV{INPUTDIR};
my $wrkdir          = "$inputdir/data";
my $cloudstack_path = "$wrkdir/Cloudstack";

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

  my $label  = CloudstackDataWrapper::get_label( $type, $uuid );
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

sub graph_cpu_host {
  my $uuid = shift;
  my $skip_acl = shift || 0; # optional flag

  # necessary information
  my $rrd = CloudstackDataWrapper::get_filepath_rrd( { type => 'host', uuid => $uuid, skip_acl => $skip_acl } );

  # RRD command parts
  my $cmd_params = get_params_cpu();
  my $cmd_def    = my $cmd_cdef = my $cmd_legend = '';

  my ( $metric_cputotalghz, $metric_cpuusedghz );

  $metric_cputotalghz = 'cputotalghz';
  $metric_cpuusedghz  = 'cpuusedghz';

  $cmd_def .= " DEF:cpu_used=\"$rrd\":${metric_cpuusedghz}:AVERAGE";
  $cmd_def .= " DEF:cpu_total=\"$rrd\":${metric_cputotalghz}:AVERAGE";

  $cmd_cdef .= " CDEF:used=cpu_used,100,/";
  $cmd_cdef .= " CDEF:total=cpu_total,100,/";

  $cmd_legend .= " COMMENT:\"[GHz]          Avrg       Max\\n\"";
  $cmd_legend .= " AREA:used#ff4040:\" Used   \"";
  $cmd_legend .= " GPRINT:used:AVERAGE:\" %6.2lf\"";
  $cmd_legend .= " GPRINT:used:MAX:\"  %6.2lf\"";
  $cmd_legend .= " COMMENT:\\n";
  $cmd_legend .= " LINE2:total#000000:\" Total  \"";
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

sub graph_cpu_cores_host {
  my $uuid = shift;
  my $skip_acl = shift || 0; # optional flag

  # necessary information
  my $rrd = CloudstackDataWrapper::get_filepath_rrd( { type => 'host', uuid => $uuid, skip_acl => $skip_acl } );

  # RRD command parts
  my $cmd_params = get_params_cpu();
  my $cmd_def    = my $cmd_cdef = my $cmd_legend = '';

  my ( $metric_used, $metric_total );

  $metric_used  = 'cpuused';
  $metric_total = 'cpunumber';

  $cmd_def .= " DEF:cpu_used=\"$rrd\":${metric_used}:AVERAGE";
  $cmd_def .= " DEF:cpu_total=\"$rrd\":${metric_total}:AVERAGE";

  $cmd_cdef .= " CDEF:used_percent=cpu_total,cpu_used,*";
  $cmd_cdef .= " CDEF:used=used_percent,100,/";
  $cmd_cdef .= " CDEF:total=cpu_total,1,/";

  $cmd_legend .= " COMMENT:\"[cores]          Avrg       Max\\n\"";
  $cmd_legend .= " AREA:used#ff4040:\" Used   \"";
  $cmd_legend .= " GPRINT:used:AVERAGE:\" %6.2lf\"";
  $cmd_legend .= " GPRINT:used:MAX:\"  %6.2lf\"";
  $cmd_legend .= " COMMENT:\\n";
  $cmd_legend .= " LINE2:total#000000:\" Total  \"";
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

sub graph_cpu_instance {
  my $uuid = shift;
  my $skip_acl = shift || 0; # optional flag

  # necessary information
  my $rrd = CloudstackDataWrapper::get_filepath_rrd( { type => 'instance', uuid => $uuid, skip_acl => $skip_acl } );

  # RRD command parts
  my $cmd_params = get_params_cpu();
  my $cmd_def    = my $cmd_cdef = my $cmd_legend = '';

  my ( $metric_cpuspeed, $metric_cpuused );

  $metric_cpuspeed = 'cpuspeed';
  $metric_cpuused  = 'cpuused';

  $cmd_def .= " DEF:cpu_used=\"$rrd\":${metric_cpuused}:AVERAGE";
  $cmd_def .= " DEF:cpu_total=\"$rrd\":${metric_cpuspeed}:AVERAGE";

  $cmd_cdef .= " CDEF:total=cpu_total,1,/";
  $cmd_cdef .= " CDEF:total_percent=cpu_total,100,/";
  $cmd_cdef .= " CDEF:used=total_percent,cpu_used,*";

  $cmd_legend .= " COMMENT:\"[MHz]        Avrg       Max\\n\"";
  $cmd_legend .= " AREA:used#ff4040:\" Used  \"";
  $cmd_legend .= " GPRINT:used:AVERAGE:\" %6.2lf\"";
  $cmd_legend .= " GPRINT:used:MAX:\"  %6.2lf\"";
  $cmd_legend .= " COMMENT:\\n";
  $cmd_legend .= " LINE2:total#000000:\" Total  \"";
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

sub graph_size_allocated {
  my $uuid = shift;
  my $skip_acl = shift || 0; # optional flag

  # necessary information
  my $rrd = CloudstackDataWrapper::get_filepath_rrd( { type => 'primaryStorage', uuid => $uuid, skip_acl => $skip_acl } );

  # RRD command parts
  my $cmd_params = get_params_cpu();
  my $cmd_def    = my $cmd_cdef = my $cmd_legend = '';

  my ( $metric_size, $metric_allocated, $metric_overprovisioning );

  $metric_size             = 'disksizetotal';
  $metric_overprovisioning = 'overprovisioning';
  $metric_allocated        = 'disksizeallocated';

  $cmd_def .= " DEF:metric_total=\"$rrd\":${metric_size}:AVERAGE";
  $cmd_def .= " DEF:metric_overprovisioning=\"$rrd\":${metric_overprovisioning}:AVERAGE";
  $cmd_def .= " DEF:metric_allocated=\"$rrd\":${metric_allocated}:AVERAGE";

  my $mb2gb = 1024;
  $cmd_cdef .= " CDEF:total=metric_total,$mb2gb,/";
  $cmd_cdef .= " CDEF:overprovisioning=metric_overprovisioning,$mb2gb,/";
  $cmd_cdef .= " CDEF:allocated=metric_allocated,$mb2gb,/";

  $cmd_legend .= " COMMENT:\"[GiB]                   Avrg       Max\\n\"";
  $cmd_legend .= " AREA:allocated#ff4040:\" Allocated       \"";
  $cmd_legend .= " GPRINT:allocated:AVERAGE:\" %6.2lf\"";
  $cmd_legend .= " GPRINT:allocated:MAX:\"  %6.2lf\"";
  $cmd_legend .= " COMMENT:\\n";
  $cmd_legend .= " LINE2:total#75ff80:\" Total            \"";
  $cmd_legend .= " GPRINT:total:AVERAGE:\"%6.2lf\"";
  $cmd_legend .= " GPRINT:total:MAX:\"  %6.2lf\"";
  $cmd_legend .= " COMMENT:\\n";
  $cmd_legend .= " LINE2:overprovisioning#000000:\" Overprovisioning\"";
  $cmd_legend .= " GPRINT:overprovisioning:AVERAGE:\" %6.2lf\"";
  $cmd_legend .= " GPRINT:overprovisioning:MAX:\"  %6.2lf\"";
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
  my $type = shift;
  my $uuid = shift;
  my $skip_acl = shift || 0; # optional flag

  # necessary information
  my $rrd = CloudstackDataWrapper::get_filepath_rrd( { type => $type, uuid => $uuid, skip_acl => $skip_acl } );

  # RRD command parts
  my $cmd_params = get_params_cpu();
  my $cmd_def    = my $cmd_cdef = my $cmd_legend = '';

  my ( $metric_size, $metric_physicalsize, $metric_used );

  if ( $type eq "volume" ) {
    $metric_size         = 'size';
    $metric_physicalsize = 'physicalsize';

    $cmd_def .= " DEF:metric_used=\"$rrd\":${metric_physicalsize}:AVERAGE";
    $cmd_def .= " DEF:metric_total=\"$rrd\":${metric_size}:AVERAGE";

    my $b2gb = 1024 * 1024 * 1024;
    $cmd_cdef .= " CDEF:total=metric_total,$b2gb,/";
    $cmd_cdef .= " CDEF:used=metric_used,$b2gb,/";
  }
  elsif ( $type eq "primaryStorage" ) {
    $metric_size = 'disksizetotal';
    $metric_used = 'disksizeused';
    my $metric_allocated = 'disksizeallocated';

    $cmd_def .= " DEF:metric_used=\"$rrd\":${metric_used}:AVERAGE";
    $cmd_def .= " DEF:metric_total=\"$rrd\":${metric_size}:AVERAGE";
    $cmd_def .= " DEF:metric_allocated=\"$rrd\":${metric_allocated}:AVERAGE";

    my $mb2gb = 1024;
    $cmd_cdef .= " CDEF:total=metric_total,$mb2gb,/";
    $cmd_cdef .= " CDEF:used=metric_used,$mb2gb,/";
    $cmd_cdef .= " CDEF:allocated=metric_allocated,$mb2gb,/";

  }

  $cmd_legend .= " COMMENT:\"[GiB]           Avrg       Max\\n\"";
  $cmd_legend .= " AREA:used#ff4040:\" Used    \"";
  $cmd_legend .= " GPRINT:used:AVERAGE:\" %6.2lf\"";
  $cmd_legend .= " GPRINT:used:MAX:\"  %6.2lf\"";
  $cmd_legend .= " COMMENT:\\n";
  if ( $type eq "primaryStorage" ) {
    $cmd_legend .= " LINE2:allocated#75ff80:\" Allocated\"";
    $cmd_legend .= " GPRINT:allocated:AVERAGE:\"%6.2lf\"";
    $cmd_legend .= " GPRINT:allocated:MAX:\"  %6.2lf\"";
    $cmd_legend .= " COMMENT:\\n";
  }
  $cmd_legend .= " LINE2:total#000000:\" Total   \"";
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

sub graph_memory {
  my $type = shift;
  my $uuid = shift;
  my $skip_acl = shift || 0; # optional flag

  # necessary information
  my $rrd = CloudstackDataWrapper::get_filepath_rrd( { type => $type, uuid => $uuid, skip_acl => $skip_acl } );

  # RRD command parts
  my $cmd_params = get_params_cpu();
  my $cmd_def    = my $cmd_cdef = my $cmd_legend = '';

  my ( $metric_memorytotal, $metric_memoryused, $metric_memoryfree );

  if ( $type eq 'host' ) {
    $metric_memorytotal = 'memorytotal';
    $metric_memoryused  = 'memoryused';

    $cmd_def .= " DEF:memory_used=\"$rrd\":${metric_memoryused}:AVERAGE";
    $cmd_def .= " DEF:memory_total=\"$rrd\":${metric_memorytotal}:AVERAGE";

    my $b2gb = 1000 * 1000 * 1000;
    $cmd_cdef .= " CDEF:total=memory_total,$b2gb,/";
    $cmd_cdef .= " CDEF:used=memory_used,$b2gb,/";

    $cmd_legend .= " COMMENT:\"[GB]         Avrg       Max\\n\"";

  }
  else {
    $metric_memorytotal = 'memory';
    $metric_memoryfree  = 'memoryintfreekbs';

    $cmd_def .= " DEF:memory_free=\"$rrd\":${metric_memoryfree}:AVERAGE";
    $cmd_def .= " DEF:memory_total=\"$rrd\":${metric_memorytotal}:AVERAGE";

    my $kb2mb = 1000;
    $cmd_cdef .= " CDEF:total=memory_total,1,/";
    $cmd_cdef .= " CDEF:free=memory_free,$kb2mb,/";
    $cmd_cdef .= " CDEF:used=total,free,-";

    $cmd_legend .= " COMMENT:\"[MB]          Avrg       Max\\n\"";
  }

  $cmd_legend .= " AREA:used#ff4040:\" Used \"";
  $cmd_legend .= " GPRINT:used:AVERAGE:\" %6.2lf\"";
  $cmd_legend .= " GPRINT:used:MAX:\"  %6.2lf\"";
  $cmd_legend .= " COMMENT:\\n";
  $cmd_legend .= " LINE2:total#000000:\" Total\"";
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

sub graph_net {
  my $type = shift;
  my $uuid = shift;
  my $skip_acl = shift || 0; # optional flag

  # necessary information
  my $rrd = CloudstackDataWrapper::get_filepath_rrd( { type => $type, uuid => $uuid, skip_acl => $skip_acl } );

  # RRD command parts
  my $cmd_params = get_params_cpu();
  my $cmd_def    = my $cmd_cdef = my $cmd_legend = '';

  my ( $metric_write, $metric_read, $division );

  $division     = 1;
  $metric_write = 'networkkbswrite';
  $metric_read  = 'networkkbsread';

  if ( $type eq 'instance' ) {
    $division = 1000;
  }

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
  my $type = shift;
  my $uuid = shift;
  my $skip_acl = shift || 0; # optional flag

  # necessary information
  my $rrd = CloudstackDataWrapper::get_filepath_rrd( { type => $type, uuid => $uuid, skip_acl => $skip_acl } );

  # RRD command parts
  my $cmd_params = get_params_cpu();
  my $cmd_def    = my $cmd_cdef = my $cmd_legend = '';

  my ( $metric_write, $metric_read, $division );

  $metric_write = 'diskkbswrite';
  $metric_read  = 'diskkbsread';
  $division     = 1000;

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

sub graph_iops {
  my $type = shift;
  my $uuid = shift;
  my $skip_acl = shift || 0; # optional flag

  # necessary information
  my $rrd = CloudstackDataWrapper::get_filepath_rrd( { type => $type, uuid => $uuid, skip_acl => $skip_acl } );

  # RRD command parts
  my $cmd_params = get_params_cpu();
  my $cmd_def    = my $cmd_cdef = my $cmd_legend = '';

  my ( $metric_write, $metric_read, $division );

  $metric_write = 'diskiowrite';
  $metric_read  = 'diskioread';

  $cmd_def .= " DEF:metric_write=\"$rrd\":${metric_write}:AVERAGE";
  $cmd_def .= " DEF:metric_read=\"$rrd\":${metric_read}:AVERAGE";

  $cmd_cdef .= " CDEF:read=metric_read,1,/";
  $cmd_cdef .= " CDEF:write=metric_write,1,/";
  $cmd_cdef .= " CDEF:read_neg=0,metric_read,-";

  $cmd_legend .= " COMMENT:\"[IOPS]        Avrg       Max\\n\"";
  $cmd_legend .= " LINE1:read_neg#FF0000:\" Read  \"";
  $cmd_legend .= " GPRINT:read:AVERAGE:\" %6.2lf\"";
  $cmd_legend .= " GPRINT:read:MAX:\"  %6.2lf\"";
  $cmd_legend .= " COMMENT:\\n";
  $cmd_legend .= " LINE1:metric_write#0000FF:\" Write\"";
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

sub graph_cpu_cores_aggr {
  my $type        = shift;    # value: 'node'
  my $filepath    = shift;
  my $counter     = shift;
  my $color       = shift;
  my $label       = shift;
  my $group_label = shift;
  my $group_type  = shift;    # value: 'pool' (for pool or custom groups) or 'host'

  my $cmd_def = my $cmd_cdef = my $cmd_legend = '';
  my ( $metric_total, $metric_used );

  $metric_used  = 'cpuused';
  $metric_total = 'cpunumber';

  $cmd_def .= " DEF:cpu_used_${counter}=\"${filepath}\":${metric_used}:AVERAGE";
  $cmd_def .= " DEF:cpu_total_${counter}=\"${filepath}\":${metric_total}:AVERAGE";

  $cmd_cdef .= " CDEF:used_percent_${counter}=cpu_total_${counter},cpu_used_${counter},*";
  $cmd_cdef .= " CDEF:custom_graph_${counter}=used_percent_${counter},100,/";

  my $graph_type = ( $counter > 0 ) ? 'STACK' : 'AREA';

  my $url_item = "cloudstack-" . $type . "-cpu-cores-aggr";

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

sub graph_cpu_aggr {
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
  if ( $type eq "host" ) {
    $metric_total = 'cputotalghz';
    $metric_used  = 'cpuusedghz';

    $cmd_def  .= " DEF:cpu_${counter}=\"${filepath}\":${metric_used}:AVERAGE";
    $cmd_cdef .= " CDEF:custom_graph_${counter}=cpu_${counter},100,/";

  }
  elsif ( $type eq "instance" ) {
    $metric_total = 'cpuspeed';
    $metric_used  = 'cpuused';

    $cmd_def .= " DEF:cpu_used_${counter}=\"${filepath}\":${metric_used}:AVERAGE";
    $cmd_def .= " DEF:cpu_total_${counter}=\"${filepath}\":${metric_total}:AVERAGE";

    $cmd_cdef .= " CDEF:total_${counter}=cpu_total_${counter},1,/";
    $cmd_cdef .= " CDEF:total_percent_${counter}=cpu_total_${counter},100,/";
    $cmd_cdef .= " CDEF:cpu_${counter}=total_percent_${counter},cpu_used_${counter},*";
    $cmd_cdef .= " CDEF:custom_graph_${counter}=cpu_${counter},1000,/";
  }

  my $graph_type = ( $counter > 0 ) ? 'STACK' : 'AREA';

  my $url_item = "cloudstack-" . $type . "-cpu-aggr";

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
  if ( $type eq "host" ) {
    $metric_total = 'memorytotal';
    $metric_used  = 'memoryused';

    my $b2gb = 1000 * 1000 * 1000;
    $cmd_def  .= " DEF:memory_used_${counter}=\"${filepath}\":${metric_used}:AVERAGE";
    $cmd_def  .= " DEF:memory_total_${counter}=\"${filepath}\":${metric_total}:AVERAGE";
    $cmd_cdef .= " CDEF:memory_free_${counter}=memory_total_${counter},memory_used_${counter},-";

    if ( $mem_type eq "used" ) {
      $cmd_cdef .= " CDEF:custom_graph_${counter}=memory_used_${counter},$b2gb,/";
    }
    else {
      $cmd_cdef .= " CDEF:custom_graph_${counter}=memory_free_${counter},$b2gb,/";
    }

  }
  elsif ( $type eq "instance" ) {
    $metric_total = 'memory';
    $metric_used  = 'memoryintfreekbs';

    my $kb2mb = 1000;
    $cmd_def .= " DEF:memory_free_${counter}=\"${filepath}\":${metric_used}:AVERAGE";
    $cmd_def .= " DEF:memory_total_${counter}=\"${filepath}\":${metric_total}:AVERAGE";

    $cmd_cdef .= " CDEF:total_${counter}=memory_total_${counter},1,/";
    $cmd_cdef .= " CDEF:free_${counter}=memory_free_${counter},$kb2mb,/";
    $cmd_cdef .= " CDEF:used_${counter}=total_${counter},free_${counter},-";

    if ( $mem_type eq "used" ) {
      $cmd_cdef .= " CDEF:custom_graph_${counter}=used_${counter},1024,/";
    }
    else {
      $cmd_cdef .= " CDEF:custom_graph_${counter}=free_${counter},1024,/";
    }

  }

  my $graph_type = ( $counter > 0 ) ? 'STACK' : 'AREA';

  my $url_item = "cloudstack-" . $type . "-memory-aggr";

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

  my $division = 1;
  my ( $metric_read, $metric_write );
  $metric_write = 'networkkbswrite';
  $metric_read  = 'networkkbsread';

  if ( $type eq 'instance' ) {
    $division = 1000;
  }

  $cmd_def .= " DEF:write_${counter}=\"$filepath\":${metric_write}:AVERAGE";
  $cmd_def .= " DEF:read_${counter}=\"$filepath\":${metric_read}:AVERAGE";

  $cmd_cdef .= " CDEF:write_text_${counter}=write_${counter},$division,/";
  $cmd_cdef .= " CDEF:read_text_${counter}=read_${counter},$division,/";
  $cmd_cdef .= " CDEF:read_graph_${counter}=read_text_${counter},-1,*";

  # $url_item is used in `ret_graph_param` to transform legends' table in `detail-graph-cgi.pl`
  my $url_item = "cloudstack-$type-net-aggr";

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
  $metric_write = 'diskkbswrite';
  $metric_read  = 'diskkbsread';
  $division     = 1000;

  $cmd_def .= " DEF:write_${counter}=\"$filepath\":${metric_write}:AVERAGE";
  $cmd_def .= " DEF:read_${counter}=\"$filepath\":${metric_read}:AVERAGE";

  $cmd_cdef .= " CDEF:write_text_${counter}=write_${counter},$division,/";
  $cmd_cdef .= " CDEF:read_text_${counter}=read_${counter},$division,/";
  $cmd_cdef .= " CDEF:read_graph_${counter}=read_text_${counter},-1,*";

  # $url_item is used in `ret_graph_param` to transform legends' table in `detail-graph-cgi.pl`
  my $url_item = "cloudstack-$type-data-aggr";

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

  # RRD command parts
  my $cmd_def    = my $cmd_cdef = my $cmd_legend_lower = my $cmd_legend_upper = '';
  my $graph_type = ( $counter > 0 ) ? 'STACK' : 'AREA';

  my $division = 1;
  my ( $metric_read, $metric_write );
  $metric_write = 'diskiowrite';
  $metric_read  = 'diskioread';

  $cmd_def .= " DEF:write_${counter}=\"$filepath\":${metric_write}:AVERAGE";
  $cmd_def .= " DEF:read_${counter}=\"$filepath\":${metric_read}:AVERAGE";

  $cmd_cdef .= " CDEF:write_text_${counter}=write_${counter},$division,/";
  $cmd_cdef .= " CDEF:read_text_${counter}=read_${counter},$division,/";
  $cmd_cdef .= " CDEF:read_graph_${counter}=read_${counter},-1,*";

  # $url_item is used in `ret_graph_param` to transform legends' table in `detail-graph-cgi.pl`
  my $url_item = "cloudstack-$type-iops-aggr";

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
  if ( $type eq "volume" ) {
    $metric_total = 'size';
    $metric_used  = 'physicalsize';

    $cmd_def .= " DEF:metric_used_${counter}=\"${filepath}\":${metric_used}:AVERAGE";
    $cmd_def .= " DEF:metric_total_${counter}=\"${filepath}\":${metric_total}:AVERAGE";

    my $b2gb = 1024 * 1024 * 1024;
    $cmd_cdef .= " CDEF:total_${counter}=metric_total_${counter},$b2gb,/";
    $cmd_cdef .= " CDEF:used_${counter}=metric_used_${counter},$b2gb,/";
    $cmd_cdef .= " CDEF:free_${counter}=total_${counter},used_${counter},-";

    if ( $mem_type eq "used" ) {
      $cmd_cdef .= " CDEF:custom_graph_${counter}=used_${counter},1,/";
    }
    else {
      $cmd_cdef .= " CDEF:custom_graph_${counter}=free_${counter},1,/";
    }

  }
  elsif ( $type eq "primaryStorage" ) {

    $metric_total = 'disksizetotal';
    $metric_used  = 'disksizeused';

    my $metric_allocated   = 'disksizeallocated';
    my $metric_unallocated = 'disksizeunallocated';

    $cmd_def .= " DEF:metric_used_${counter}=\"${filepath}\":${metric_used}:AVERAGE";
    $cmd_def .= " DEF:metric_total_${counter}=\"${filepath}\":${metric_total}:AVERAGE";
    $cmd_def .= " DEF:metric_allocated_${counter}=\"${filepath}\":${metric_allocated}:AVERAGE";
    $cmd_def .= " DEF:metric_unallocated_${counter}=\"${filepath}\":${metric_unallocated}:AVERAGE";

    my $mb2gb = 1024;
    $cmd_cdef .= " CDEF:total_${counter}=metric_total_${counter},$mb2gb,/";
    $cmd_cdef .= " CDEF:used_${counter}=metric_used_${counter},$mb2gb,/";
    $cmd_cdef .= " CDEF:free_${counter}=total_${counter},used_${counter},-";
    $cmd_cdef .= " CDEF:allocated_${counter}=metric_allocated_${counter},$mb2gb,/";
    $cmd_cdef .= " CDEF:unallocated_${counter}=metric_unallocated_${counter},$mb2gb,/";

    if ( $mem_type eq "used" ) {
      $cmd_cdef .= " CDEF:custom_graph_${counter}=used_${counter},1,/";
    }
    elsif ( $mem_type eq "free" ) {
      $cmd_cdef .= " CDEF:custom_graph_${counter}=free_${counter},1,/";
    }
    elsif ( $mem_type eq "allocated" ) {
      $cmd_cdef .= " CDEF:custom_graph_${counter}=allocated_${counter},1,/";
    }
    elsif ( $mem_type eq "unallocated" ) {
      $cmd_cdef .= " CDEF:custom_graph_${counter}=unallocated_${counter},1,/";
    }

  }

  my $graph_type = ( $counter > 0 ) ? 'STACK' : 'AREA';

  my $url_item = "cloudstack-" . $type . "-size-aggr";

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

################################################################################

sub get_uuid_from_filepath {
  my $type     = shift;    # value: 'vm' or 'host'
  my $filepath = shift;

  my $uuid;
  $filepath =~ m/\/Cloudstack\/(.*)\/(.*)\.rrd/;
  $uuid = $2;

  return $uuid;
}

################################################################################

1;
