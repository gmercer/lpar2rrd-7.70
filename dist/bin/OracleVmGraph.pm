# OracleVmGraph.pm
# keep OracleVm graph generation in one place, if possible
# (separated from `detail-graph-cgi.pl`)

package OracleVmGraph;

use strict;

use OracleVmDataWrapper;
use Data::Dumper;
use Xorux_lib qw(error);

defined $ENV{INPUTDIR} || Xorux_lib::error( "INPUTDIR undefined, config etc/lpar2rrd.cfg probably has not been loaded " . __FILE__ . ":" . __LINE__ ) && exit 1;

my $inputdir        = $ENV{INPUTDIR};
my $oraclevm_dir    = "$inputdir/data/OracleVM";
my $server_data_dir = "$oraclevm_dir/host";
my $vm_data_dir     = "$oraclevm_dir/vm";
my $metadata_file   = "$oraclevm_dir/conf.json";

my $pow2 = 1000**2;
my $del  = "XORUX";    # delimiter, this is for rrdtool print lines for clickable legend

################################################################################

sub get_header {
  my $type   = shift;
  my $uuid   = shift;
  my $metric = shift;
  my $label  = OracleVmDataWrapper::get_label( $type, $uuid );

  #print "get_header: type-$type,uuid-$uuid,metric-$metric,label-$label\n";
  if    ( $type eq 'vm' )     { $type = 'VM'; }
  elsif ( $type eq 'server' ) { $type = 'SERVER'; }
  else                        { $type = ucfirst $type; }

  return ( "$type $metric : $label", "$metric:$label" );
}    ## sub get_header

sub get_formatted_label {
  my $label_space = shift;

  $label_space .= " " x ( 30 - length($label_space) );

  return $label_space;
}    ## sub get_formatted_label

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

sub get_params_mem {
  my $result = '';
  $result .= " --vertical-label=\"Memory in [GiB]\"";
  $result .= " --lower-limit=0.00";

  return $result;
}

################################################################################

sub graph_cpu_cores {
  my $type = shift;
  my $uuid = shift;
  my $skip_acl = shift || 0; # optional flag

  my $rrd  = OracleVmDataWrapper::get_filepath_rrd( { type => $type, uuid => $uuid, skip_acl => $skip_acl } );
  my ( $header, $reduced_header ) = get_header( $type, $uuid, 'CPU cores' );
  my $cmd_params = my $cmd_legend = my $cmd_cdef = my $cmd_def = my $cmd_vlabel = '';

  $cmd_vlabel .= " --vertical-label=\"CPU load in cores\"";
  $cmd_params .= " --lower-limit=0.00";
  $cmd_params .= " --units-exponent=1.00";
  $cmd_def    .= " DEF:cpu_in_per=\"$rrd\":CPU_UTILIZATION:AVERAGE";
  $cmd_def    .= " DEF:cpu_count=\"$rrd\":CPU_COUNT:AVERAGE";
  if ( $type eq "server" ) {
    $cmd_def  .= " DEF:cpu_cores=\"$rrd\":CORES_COUNT:AVERAGE";
    $cmd_cdef .= " CDEF:cpu_in_percent=cpu_in_per,100,*";
    $cmd_cdef .= " CDEF:cpu_count_per=cpu_count,100,/";
    $cmd_cdef .= " CDEF:cpu_c=cpu_count_per,cpu_in_percent,*";

    #$cmd_cdef   .= " CDEF:cpu_c1=cpu_count,cpu_in_per,*";
    #$cmd_cdef   .= " CDEF:cpu_c=cpu_c1,cpu_cores,/";
  }
  else {
    $cmd_cdef .= " CDEF:cpu_c=cpu_count,cpu_in_per,*";
  }
  $cmd_legend .= " COMMENT:\"[cores]               Avrg       Max\\n\"";
  $cmd_legend .= " LINE1:cpu_c#FF0000:\" Utilization   \"";
  $cmd_legend .= " GPRINT:cpu_c:AVERAGE:\" %6.1lf\"";
  $cmd_legend .= " GPRINT:cpu_c:MAX:\" %6.1lf\"";
  $cmd_legend .= " COMMENT:\\n";

  return {
    filename => $rrd,     header   => $header,   reduced_header => $reduced_header, cmd_params => $cmd_params,
    cmd_def  => $cmd_def, cmd_cdef => $cmd_cdef, cmd_legend     => $cmd_legend,     cmd_vlabel => $cmd_vlabel
  };
}

sub graph_cpu_percent {
  my $type = shift;
  my $uuid = shift;
  my $skip_acl = shift || 0; # optional flag

  my $rrd  = OracleVmDataWrapper::get_filepath_rrd( { type => $type, uuid => $uuid, skip_acl => $skip_acl } );
  my ( $header, $reduced_header ) = get_header( $type, $uuid, 'CPU %' );

  my $cmd_params = my $cmd_legend = my $cmd_cdef = my $cmd_def = my $cmd_vlabel = '';

  $cmd_vlabel .= " --vertical-label=\"CPU load in [%]\"";
  $cmd_params .= " --upper-limit=100.0";
  $cmd_params .= " --lower-limit=0.00";
  $cmd_def    .= " DEF:util_in_perc=\"$rrd\":CPU_UTILIZATION:AVERAGE";
  $cmd_def    .= " DEF:cpu_count=\"$rrd\":CPU_COUNT:AVERAGE";
  $cmd_cdef   .= " CDEF:util=util_in_perc,100,*";
  $cmd_legend .= " COMMENT:\"[%]                Avrg       Max\\n\"";
  $cmd_legend .= " LINE1:util#FF4040:\" Util        \"";
  $cmd_legend .= " GPRINT:util:AVERAGE:\" %6.1lf\"";
  $cmd_legend .= " GPRINT:util:MAX:\" %6.1lf\"";
  $cmd_legend .= " COMMENT:\\n";

  return {
    filename => $rrd,     header   => $header,   reduced_header => $reduced_header, cmd_params => $cmd_params,
    cmd_def  => $cmd_def, cmd_cdef => $cmd_cdef, cmd_legend     => $cmd_legend,     cmd_vlabel => $cmd_vlabel
  };
}

sub graph_mem_vm {
  my $type = shift;
  my $uuid = shift;
  my $skip_acl = shift || 0; # optional flag

  my $rrd  = OracleVmDataWrapper::get_filepath_rrd( { type => $type, uuid => $uuid, skip_acl => $skip_acl } );
  my ( $header, $reduced_header ) = get_header( $type, $uuid, 'MEM' );

  my $cmd_params = my $cmd_legend = my $cmd_cdef = my $cmd_def = my $cmd_vlabel = '';

  $cmd_vlabel .= " --vertical-label=\"Memory in GBytes\"";
  $cmd_params .= " --lower-limit=0.00";
  $cmd_params .= " --base=1024";
  $cmd_params .= " --units-exponent=1.00";
  $cmd_def    .= " DEF:mem_used=\"$rrd\":MEMORY_USED:AVERAGE";
  $cmd_cdef   .= " CDEF:mem_used_gb=mem_used,1024,/";
  $cmd_legend .= " COMMENT:\"[GB]                     Avrg      Max\\n\"";
  $cmd_legend .= " LINE1:mem_used_gb#FF4040:\" Allocated memory      \"";
  $cmd_legend .= " GPRINT:mem_used_gb:AVERAGE:\" %6.1lf\"";
  $cmd_legend .= " GPRINT:mem_used_gb:MAX:\" %6.1lf\"";
  $cmd_legend .= " COMMENT:\\n";
  return {
    filename => $rrd,     header   => $header,   reduced_header => $reduced_header, cmd_params => $cmd_params,
    cmd_def  => $cmd_def, cmd_cdef => $cmd_cdef, cmd_legend     => $cmd_legend,     cmd_vlabel => $cmd_vlabel
  };
}    ## sub graph_mem

sub graph_mem_server {
  my $type = shift;
  my $uuid = shift;
  my $skip_acl = shift || 0; # optional flag

  my $rrd  = OracleVmDataWrapper::get_filepath_rrd( { type => $type, uuid => $uuid, skip_acl => $skip_acl } );
  my ( $header, $reduced_header ) = get_header( $type, $uuid, 'MEM' );

  my $cmd_params = my $cmd_legend = my $cmd_cdef = my $cmd_def = my $cmd_vlabel = '';

  $cmd_vlabel .= " --vertical-label=\"Memory in GBytes\"";
  $cmd_params .= " --lower-limit=0.00";
  $cmd_params .= " --base=1024";
  $cmd_params .= " --units-exponent=1.00";
  $cmd_def    .= " DEF:mem_used=\"$rrd\":MEMORY_USED:AVERAGE";
  $cmd_def    .= " DEF:mem_free=\"$rrd\":FREE_MEMORY:AVERAGE";
  $cmd_def    .= " DEF:mem_swap=\"$rrd\":FREE_SWAP:AVERAGE";
  $cmd_cdef   .= " CDEF:mem_used_gb=mem_used,1024,/";
  $cmd_cdef   .= " CDEF:mem_free_gb=mem_free,1024,/";
  $cmd_cdef   .= " CDEF:mem_swap_gb=mem_swap,1024,/,1024,/";
  $cmd_legend .= " COMMENT:\"[GB]                     Avrg      Max\\n\"";
  $cmd_legend .= " AREA:mem_used_gb#FF4040:\" Used memory      \"";
  $cmd_legend .= " GPRINT:mem_used_gb:AVERAGE:\" %6.1lf\"";
  $cmd_legend .= " GPRINT:mem_used_gb:MAX:\" %6.1lf\"";
  $cmd_legend .= " COMMENT:\\n";
  $cmd_legend .= " STACK:mem_free_gb#00FF00:\" Free             \"";
  $cmd_legend .= " GPRINT:mem_free_gb:AVERAGE:\" %6.1lf\"";
  $cmd_legend .= " GPRINT:mem_free_gb:MAX:\" %6.1lf\"";
  $cmd_legend .= " COMMENT:\\n";
  $cmd_legend .= " STACK:mem_swap_gb#0080FF:\" Free swap       \"";
  $cmd_legend .= " GPRINT:mem_swap_gb:AVERAGE:\" %6.1lf\"";
  $cmd_legend .= " GPRINT:mem_swap_gb:MAX:\" %6.1lf\"";
  $cmd_legend .= " COMMENT:\\n";
  return {
    filename => $rrd,     header   => $header,   reduced_header => $reduced_header, cmd_params => $cmd_params,
    cmd_def  => $cmd_def, cmd_cdef => $cmd_cdef, cmd_legend     => $cmd_legend,     cmd_vlabel => $cmd_vlabel
  };
}    ## sub graph_mem

sub graph_mem_percent {
  my $type = shift;
  my $uuid = shift;
  my $skip_acl = shift || 0; # optional flag

  my $rrd  = OracleVmDataWrapper::get_filepath_rrd( { type => $type, uuid => $uuid, skip_acl => $skip_acl } );
  my ( $header, $reduced_header ) = get_header( $type, $uuid, 'MEM %' );

  my $cmd_params = my $cmd_legend = my $cmd_cdef = my $cmd_def = my $cmd_vlabel = '';

  $cmd_vlabel .= " --vertical-label=\"MEM util in [%]\"";
  $cmd_params .= " --upper-limit=100.0";
  $cmd_params .= " --lower-limit=0.00";
  $cmd_def    .= " DEF:system=\"$rrd\":MEMORY_UTILIZATION:AVERAGE";
  $cmd_cdef   .= " CDEF:system_p=system,100,*";
  $cmd_legend .= " COMMENT:\"[%]                Avrg       Max\\n\"";
  $cmd_legend .= " LINE1:system_p#FF4040:\" Util        \"";
  $cmd_legend .= " GPRINT:system_p:AVERAGE:\" %6.1lf\"";
  $cmd_legend .= " GPRINT:system_p:MAX:\" %6.1lf\"";
  $cmd_legend .= " COMMENT:\\n";

  return {
    filename => $rrd,     header   => $header,   reduced_header => $reduced_header, cmd_params => $cmd_params,
    cmd_def  => $cmd_def, cmd_cdef => $cmd_cdef, cmd_legend     => $cmd_legend,     cmd_vlabel => $cmd_vlabel
  };
}

sub graph_vm_net {
  my $type = shift;
  my $uuid = shift;
  my $skip_acl = shift || 0; # optional flag

  my $rrd  = OracleVmDataWrapper::get_filepath_rrd( { type => $type, uuid => $uuid, skip_acl => $skip_acl } );
  my ( $header, $reduced_header ) = get_header( $type, $uuid, 'NET' );

  my $cmd_params = my $cmd_legend = my $cmd_cdef = my $cmd_def = my $cmd_vlabel = '';

  $cmd_vlabel .= " --vertical-label=\"Read - Bytes/sec - Write\"";
  $cmd_def    .= " DEF:read=\"$rrd\":NETWORK_SENT:AVERAGE";
  $cmd_def    .= " DEF:write=\"$rrd\":NETWORK_RECEIVED:AVERAGE";
  $cmd_cdef   .= " CDEF:read_mb=read,$pow2,/";
  $cmd_cdef   .= " CDEF:read_graph=0,read,-";
  $cmd_cdef   .= " CDEF:write_mb=write,$pow2,/";
  $cmd_legend .= " COMMENT:\"[MB/sec]           Avrg       Max\\n\"";
  $cmd_legend .= " LINE1:write#0000FF:\" Write      \"";
  $cmd_legend .= " GPRINT:write_mb:AVERAGE:\" %6.2lf\"";
  $cmd_legend .= " GPRINT:write_mb:MAX:\" %6.2lf\"";
  $cmd_legend .= " COMMENT:\\n";
  $cmd_legend .= " LINE1:read_graph#FF0000:\" Read       \"";
  $cmd_legend .= " GPRINT:read_mb:AVERAGE:\" %6.2lf\"";
  $cmd_legend .= " GPRINT:read_mb:MAX:\" %6.2lf\"";
  $cmd_legend .= " COMMENT:\\n";

  return {
    filename => $rrd,     header   => $header,   reduced_header => $reduced_header, cmd_params => $cmd_params,
    cmd_def  => $cmd_def, cmd_cdef => $cmd_cdef, cmd_legend     => $cmd_legend,     cmd_vlabel => $cmd_vlabel
  };
}

sub graph_server_net {
  my $type = shift;
  my $uuid = shift;
  my $skip_acl = shift || 0; # optional flag

  #my $rrd       = OracleVmDataWrapper::get_filepath_rrd_server_net( $type, $uuid );
  opendir( DIR, "$oraclevm_dir/server/$uuid" );
  my @net_all = grep /^lan-/, readdir(DIR);
  closedir(DIR);
  my $rrd = '';
  foreach my $net (@net_all) {
    $rrd = "$oraclevm_dir/server/$uuid/$net";
    my ( $header, $reduced_header ) = get_header( $type, $uuid, 'NET' );

    my $cmd_params = my $cmd_legend = my $cmd_cdef = my $cmd_def = my $cmd_vlabel = '';

    $cmd_vlabel .= " --vertical-label=\"Read - Bytes/sec - Write\"";
    $cmd_def    .= " DEF:read=\"$rrd\":NETWORK_SENT:AVERAGE";
    $cmd_def    .= " DEF:write=\"$rrd\":NETWORK_RECEIVED:AVERAGE";
    $cmd_cdef   .= " CDEF:read_mb=read,$pow2,/";
    $cmd_cdef   .= " CDEF:read_graph=0,read,-";
    $cmd_cdef   .= " CDEF:write_mb=write,$pow2,/";
    $cmd_legend .= " COMMENT:\"[MB/sec]           Avrg       Max\\n\"";
    $cmd_legend .= " LINE1:write#0000FF:\" Write      \"";
    $cmd_legend .= " GPRINT:write_mb:AVERAGE:\" %6.2lf\"";
    $cmd_legend .= " GPRINT:write_mb:MAX:\" %6.2lf\"";
    $cmd_legend .= " COMMENT:\\n";
    $cmd_legend .= " LINE1:read_graph#FF0000:\" Read       \"";
    $cmd_legend .= " GPRINT:read_mb:AVERAGE:\" %6.2lf\"";
    $cmd_legend .= " GPRINT:read_mb:MAX:\" %6.2lf\"";
    $cmd_legend .= " COMMENT:\\n";
    return {
      filename => $rrd,     header   => $header,   reduced_header => $reduced_header, cmd_params => $cmd_params,
      cmd_def  => $cmd_def, cmd_cdef => $cmd_cdef, cmd_legend     => $cmd_legend,     cmd_vlabel => $cmd_vlabel
    };
  }
}

sub graph_disk {
  my $type = shift;
  my $uuid = shift;
  my $skip_acl = shift || 0; # optional flag

  my $rrd  = OracleVmDataWrapper::get_filepath_rrd( { type => $type, uuid => $uuid, skip_acl => $skip_acl } );
  my ( $header, $reduced_header ) = get_header( $type, $uuid, 'DISK' );

  my $cmd_params = my $cmd_legend = my $cmd_cdef = my $cmd_def = my $cmd_vlabel = '';

  $cmd_vlabel .= " --vertical-label=\"Read - Bytes/sec - Write\"";
  $cmd_def    .= " DEF:read=\"$rrd\":DISK_READ:AVERAGE";
  $cmd_def    .= " DEF:write=\"$rrd\":DISK_WRITE:AVERAGE";
  $cmd_cdef   .= " CDEF:read_mb=read,$pow2,/";
  $cmd_cdef   .= " CDEF:read_graph=0,read,-";
  $cmd_cdef   .= " CDEF:write_mb=write,$pow2,/";
  $cmd_legend .= " COMMENT:\"[MB/sec]           Avrg       Max\\n\"";
  $cmd_legend .= " LINE1:write#0000FF:\" Write      \"";
  $cmd_legend .= " GPRINT:write_mb:AVERAGE:\" %6.2lf\"";
  $cmd_legend .= " GPRINT:write_mb:MAX:\" %6.2lf\"";
  $cmd_legend .= " COMMENT:\\n";
  $cmd_legend .= " LINE1:read_graph#FF0000:\" Read       \"";
  $cmd_legend .= " GPRINT:read_mb:AVERAGE:\" %6.2lf\"";
  $cmd_legend .= " GPRINT:read_mb:MAX:\" %6.2lf\"";
  $cmd_legend .= " COMMENT:\\n";

  return {
    filename => $rrd,     header   => $header,   reduced_header => $reduced_header, cmd_params => $cmd_params,
    cmd_def  => $cmd_def, cmd_cdef => $cmd_cdef, cmd_legend     => $cmd_legend,     cmd_vlabel => $cmd_vlabel
  };
}

sub graph_cpu_aggr {
  my $type        = shift;                                # value: 'host' or 'vm'
  my $metric_type = shift;                                # value: 'percent' or 'cores'
  my $filepath    = shift;
  my $counter     = shift;
  my $color       = shift;
  my $label       = shift;
  my $group_label = shift;
  my $group_type  = shift;                                # value: 'pool' (for pool or custom groups) or 'host'
                                                          # RRD command parts
  my $cmd_def     = my $cmd_cdef = my $cmd_legend = '';
  my ( $metric, $graph_type, $metric2 );
  $graph_type = ( $counter > 0 ) ? 'STACK' : 'AREA';
  $metric     = 'CPU_COUNT';
  $metric2    = 'CPU_UTILIZATION';

  $cmd_def .= " DEF:${metric}_${counter}=\"${filepath}\":${metric}:AVERAGE";
  $cmd_def .= " DEF:${metric2}_${counter}=\"${filepath}\":${metric2}:AVERAGE";
  if ( $metric_type eq 'percent' ) {
    $cmd_cdef .= " CDEF:cpu_graph_${counter}=${metric}_${counter},100,*";
  }
  else {                                                  # 'cores'
    $cmd_cdef .= " CDEF:cpu_util_${counter}=${metric}_${counter},${metric2}_${counter},*";
    $cmd_cdef .= " CDEF:cpu_graph_${counter}=cpu_util_${counter}";
  }

  # $url_item is used in `ret_graph_param` to transform legends' table in `detail-graph-cgi.pl`
  my $url_item = '';
  if ( $type eq 'vm' ) {                                  # ad-hoc assignment for Custom groups
    $url_item = "custom_orvm_vm_cpu";
  }
  my $label_space = get_formatted_label($label);
  my $group_space = get_formatted_label($group_label);

  # $uuid is used to form hypertext links in legends' tables
  my $uuid = get_uuid_from_filepath( $type, $filepath );

  #print "line 365-$type,$metric_type,$filepath, $counter , $label, $group_label, $group_type, $url_item, $label, $uuid\n";
  $cmd_legend .= " ${graph_type}:cpu_graph_${counter}${color}:\" \"";
  $cmd_legend .= " COMMENT:\"$group_space  $label_space\"";
  $cmd_legend .= " GPRINT:cpu_graph_${counter}:AVERAGE:\" %6.1lf\"";
  $cmd_legend .= " GPRINT:cpu_graph_${counter}:MAX:\" %6.1lf    \"";
  $cmd_legend .= " PRINT:cpu_graph_${counter}:AVERAGE:\" %6.1lf $del $url_item $del $label $del $color $del $color\"";
  $cmd_legend .= " PRINT:cpu_graph_${counter}:MAX:\" %6.1lf $del $label $del ${group_label}\"";
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
  my $type        = shift;    # value: 'host' or 'vm'
  my $metric_type = shift;    # value: 'free' or 'used'
  my $filepath    = shift;
  my $counter     = shift;
  my $color       = shift;
  my $label       = shift;
  my $group_label = shift;
  my $group_type  = shift;    # value: 'pool' (for pool or custom groups) or 'host'

  #print "line 404-$type,$metric_type,$filepath, $counter , $label, $group_label, $group_type, $label\n";
  # RRD command parts
  my $cmd_def = my $cmd_cdef = my $cmd_legend = '';
  my ( $metric_total, $metric_free, $graph_type );
  if ( $type eq 'vm' ) {
    $metric_total = 'MEMORY_USED';
  }
  $graph_type = ( $counter > 0 ) ? 'STACK' : 'AREA';
  $cmd_def .= " DEF:mem_total_${counter}=\"${filepath}\":${metric_total}:AVERAGE";

  my $b2gib   = 1024**3;
  my $kib2gib = 1024**2;
  my $mib2gib = 1024;
  if ( $type eq 'vm' ) {
    $cmd_cdef .= " CDEF:total_${counter}=mem_total_${counter},$mib2gib,/";

    #$cmd_cdef    .= " CDEF:total_${counter}=mem_total_${counter}";
  }

  # $url_item is used in `ret_graph_param` to transform legends' table in `detail-graph-cgi.pl`
  my $url_item = "xen-$type-memory-${metric_type}-aggr";
  if ( $type eq 'vm' ) {    # ad-hoc assignment for Custom groups / Pool
    $url_item = "custom_orvm_vm_mem";
  }
  my $label_space = get_formatted_label($label);
  my $group_space = get_formatted_label($group_label);

  # $uuid is used to form hypertext links in legends' tables
  my $uuid = get_uuid_from_filepath( $type, $filepath );

  $cmd_legend .= " ${graph_type}:total_${counter}${color}:\" \"";
  $cmd_legend .= " COMMENT:\"$group_space  $label_space\"";
  $cmd_legend .= " GPRINT:total_${counter}:AVERAGE:\" %6.1lf\"";
  $cmd_legend .= " GPRINT:total_${counter}:MAX:\" %6.1lf    \"";
  $cmd_legend .= " PRINT:total_${counter}:AVERAGE:\" %6.1lf $del $url_item $del $label $del $color $del $color\"";
  $cmd_legend .= " PRINT:total_${counter}:MAX:\" %6.1lf $del $label $del ${group_label} $del \"";
  $cmd_legend .= " COMMENT:\\n";

  # return the data
  my %result = (
    cmd_def    => $cmd_def,
    cmd_cdef   => $cmd_cdef,
    cmd_legend => $cmd_legend
  );

  return \%result;
}

##################################

# to be moved to OracleVmDataWrapper
sub get_uuid_from_filepath {
  my $type     = shift;    # value: 'vm' or 'host'
  my $filepath = shift;

  my $uuid;
  if ( $type eq 'vm' ) {
    $filepath =~ m/\/ORVM\/(.*)\.rrd/;
    $uuid = $1;
  }
  else {
    $filepath =~ m/\/XEN\/(.*)\/(.*)\.rrd/;
    $uuid = $1;
  }

  return $uuid;
}

##################################
sub graph_double_sided_aggr {
  my $uuid        = shift;
  my $owner_uuid  = shift;
  my $item        = shift;
  my $index       = shift;
  my $color_read  = shift;
  my $color_write = shift;
  my $skip_acl    = shift || 0; # optional flag
  my $cmd_def     = my $cmd_cdef = my $cmd_legend_lower = my $cmd_legend_upper = '';
  my $gtype;
  my $filepath;
  my $label;

  #print STDERR"line389-$uuid,$owner_uuid,$item,$index,$color_read,$color_write\n";
  if ( $item =~ /^ovm_server_aggr_net$/ && $owner_uuid ) {
    $label = OracleVmDataWrapper::get_label( 'server', $uuid );

    #$filepath = OracleVmDataWrapper::get_filepath_rrd_host_nic( $owner_uuid, $uuid );
    #print STDERR"OracleVmGraph:uuid-$uuid,owner-$owner_uuid,item-$item,index-$index,label $label\n";
    $filepath = "$oraclevm_dir/server/$owner_uuid/$uuid";
  }
  elsif ( $item =~ /ovm_server_aggr_disk_used$/ ) {
    my $get_repos_name = "$uuid";
    $get_repos_name =~ s/\.rrd//g;
    $get_repos_name =~ s/disk-//g;
    $filepath = "$oraclevm_dir/server/$owner_uuid/$uuid";
  }
  elsif ( $item =~ /^ovm_vm_aggr_net$/ ) {
    $label    = OracleVmDataWrapper::get_label( 'vm', $uuid );
    $filepath = "$oraclevm_dir/vm/$owner_uuid/$uuid";
  }
  elsif ( $item =~ /^ovm_vm_aggr_disk_used$/ ) {
    my $get_repos_name = "$uuid";
    $get_repos_name =~ s/\.rrd//g;
    $get_repos_name =~ s/disk-//g;
    $label    = OracleVmDataWrapper::get_label( 'repos', $get_repos_name );
    $filepath = "$oraclevm_dir/vm/$owner_uuid/$uuid";
  }
  elsif ( $item =~ /^ovm_server_total_cpu$|^ovm_server_total_mem|^ovm_serverpools_total_cpu$|^ovm_serverpools_total_mem$/ ) {
    $filepath = "$oraclevm_dir/server/$uuid/sys.rrd";
    $label    = OracleVmDataWrapper::get_label( 'server', $uuid );
  }
  elsif ( $item =~ /^ovm_server_total_net$|^ovm_serverpools_total_net$/ ) {
    $filepath = "$oraclevm_dir/server/$owner_uuid/$uuid";
    $label    = OracleVmDataWrapper::get_label( 'server', $owner_uuid );
  }
  elsif ( $item =~ /^ovm_vm_aggr_cpu_serverpool$|^ovm_vm_aggr_cpu_server$/ ) {
    $filepath = "$oraclevm_dir/vm/$uuid/sys.rrd";
    $label    = OracleVmDataWrapper::get_label( 'vm', $uuid );
  }
  elsif ( $item =~ /^ovm_server_total_disk$|^ovm_serverpools_total_disk$/ ) {
    my $get_repos_name = "$uuid";
    $get_repos_name =~ s/\.rrd//g;
    $get_repos_name =~ s/disk-//g;
    $label    = OracleVmDataWrapper::get_label( 'server', $owner_uuid );
    $filepath = "$oraclevm_dir/server/$owner_uuid/$uuid";
  }
  else {
    return {};
  }

  my $label_space = get_formatted_label($label);

  if ( $item =~ /_net$/ ) {
    $gtype = $index > 0 ? 'STACK' : 'AREA';
    $cmd_def  .= " DEF:read_$index=\"$filepath\":NETWORK_RECEIVED:AVERAGE";
    $cmd_def  .= " DEF:write_$index=\"$filepath\":NETWORK_SENT:AVERAGE";
    $cmd_cdef .= " CDEF:read_units_$index=read_$index,60,/";
    $cmd_cdef .= " CDEF:write_units_$index=write_$index,60,/";
    $cmd_cdef .= " CDEF:read_legend_$index=read_$index,$pow2,/,60,/";
    $cmd_cdef .= " CDEF:write_legend_$index=write_$index,$pow2,/,60,/";
  }
  elsif ( $item =~ /_used$|^ovm_server_total_disk$|^ovm_serverpools_total_disk$/ ) {
    $gtype = $index > 0 ? 'STACK' : 'AREA';
    $cmd_def  .= " DEF:read_$index=\"$filepath\":DISK_READ:AVERAGE";
    $cmd_def  .= " DEF:write_$index=\"$filepath\":DISK_WRITE:AVERAGE";
    $cmd_cdef .= " CDEF:read_units_$index=read_$index,60,/";
    $cmd_cdef .= " CDEF:write_units_$index=write_$index,60,/";
    $cmd_cdef .= " CDEF:read_legend_$index=read_$index,$pow2,/,60,/";
    $cmd_cdef .= " CDEF:write_legend_$index=write_$index,$pow2,/,60,/";
  }
  elsif ( $item =~ /^ovm_server_total_cpu|^ovm_serverpools_total_cpu$|^ovm_vm_aggr_cpu_serverpool$|^ovm_vm_aggr_cpu_server$/ ) {
    $gtype = $index > 0 ? 'STACK' : 'AREA';
    $cmd_def .= " DEF:cpu_in_per_$index=\"$filepath\":CPU_UTILIZATION:AVERAGE";
    $cmd_def .= " DEF:cpu_count_$index=\"$filepath\":CPU_COUNT:AVERAGE";
    if ( $item eq /ovm_server/ ) {
      $cmd_def  .= " DEF:cpu_cores_$index=\"$filepath\":CORES_COUNT:AVERAGE";
      $cmd_cdef .= " CDEF:cpu_in_percent_$index=cpu_in_per_$index,100,*";
      $cmd_cdef .= " CDEF:cpu_count_per_$index=cpu_count_$index,100,/";
      $cmd_cdef .= " CDEF:cpu_c_$index=cpu_count_per_$index,cpu_in_percent_$index,*";

      #$cmd_cdef   .= " CDEF:cpu_c1=cpu_count,cpu_in_per,*";
      #$cmd_cdef   .= " CDEF:cpu_c=cpu_c1,cpu_cores,/";
    }
    else {
      $cmd_cdef .= " CDEF:cpu_c_$index=cpu_count_$index,cpu_in_per_$index,*";
    }

    #$cmd_cdef .= " CDEF:cpu_c_$index=cpu_count_$index,cpu_in_per_$index,*";
    $cmd_cdef .= " CDEF:cpu_c_units_$index=cpu_c_$index";
    $cmd_cdef .= " CDEF:cpu_c_legend_$index=cpu_c_$index";
  }
  elsif ( $item =~ /^ovm_server_total_mem$|^ovm_serverpools_total_mem$/ ) {
    $gtype = $index > 0 ? 'STACK' : 'AREA';
    $cmd_def  .= " DEF:mem_u_$index=\"$filepath\":MEMORY_USED:AVERAGE";
    $cmd_cdef .= " CDEF:mem_used_$index=mem_u_$index,1024,/";
    $cmd_cdef .= " CDEF:mem_used_units_$index=mem_used_$index";
    $cmd_cdef .= " CDEF:mem_used_legend_$index=mem_used_$index";
  }

  if ( $item =~ /_net|_used|^ovm_server_total_disk$|^ovm_serverpools_total_disk$/ ) {
    $cmd_cdef .= " CDEF:read_graph_$index=read_units_$index,-1,*";
    $label       =~ s/===double-col===/-/g;
    $label       =~ s/://g;
    $label_space =~ s/lan-//g;
    $label_space =~ s/\.rrd//g;
    $label_space =~ s/===double-col===/-/g;
    $uuid        =~ s/===double-col===/-/g;
    $uuid        =~ s/disk-//g;
    $uuid        =~ s/lan-//g;
    $uuid        =~ s/\.rrd//g;
    $cmd_legend_lower .= " COMMENT:\"$uuid    \"";

    if ( $item !~ /^ovm_server_aggr_net|ovm_vm_aggr_net/ ) {
      $cmd_legend_lower .= " COMMENT:\"$label_space    \"";
    }
    $cmd_legend_lower .= " $gtype:read_graph_$index$color_read:\" \"";
    $cmd_legend_lower .= " GPRINT:read_legend_$index:AVERAGE:\" %6.2lf\"";
    $cmd_legend_lower .= " GPRINT:read_legend_$index:MAX:\" %6.2lf    \"";
    $cmd_legend_lower .= " PRINT:read_legend_$index:AVERAGE:\" %6.2lf $del $item $del $label $del $color_read $del $color_read\"";
    $cmd_legend_lower .= " PRINT:read_legend_$index:MAX:\" %6.2lf $del $label $del nope $del $uuid $del $owner_uuid\"";

    $cmd_legend_upper .= " $gtype:write_units_$index$color_write: ";
    $cmd_legend_lower .= " $gtype:0$color_write:\" \"";
    $cmd_legend_lower .= " GPRINT:write_legend_$index:AVERAGE:\" %6.2lf\"";
    $cmd_legend_lower .= " GPRINT:write_legend_$index:MAX:\" %6.2lf\"";
    $cmd_legend_lower .= " PRINT:write_legend_$index:AVERAGE:\" %6.2lf $del $color_write\"";
    $cmd_legend_lower .= " PRINT:write_legend_$index:MAX:\" %6.2lf $del $label\"";
    $cmd_legend_lower .= " COMMENT:\\n";
  }
  elsif ( $item =~ /^ovm_server_total_cpu|^ovm_serverpools_total_cpu$|^ovm_vm_aggr_cpu_serverpool$|^ovm_vm_aggr_cpu_server$/ ) {
    $cmd_cdef .= " CDEF:cpu_c_graph_$index=cpu_c_$index,1,*";
    $label =~ s/===double-col===/-/g;
    $label =~ s/://g;
    $cmd_legend_lower .= " COMMENT:\"$label_space    \"";
    $cmd_legend_lower .= " $gtype:cpu_c_graph_$index$color_read:\" \"";
    $cmd_legend_lower .= " GPRINT:cpu_c_legend_$index:AVERAGE:\" %6.2lf\"";
    $cmd_legend_lower .= " GPRINT:cpu_c_legend_$index:MAX:\" %6.2lf    \"";
    $cmd_legend_lower .= " PRINT:cpu_c_legend_$index:AVERAGE:\" %6.2lf $del $item $del $label $del $color_read $del $color_read\"";
    $cmd_legend_lower .= " PRINT:cpu_c_legend_$index:MAX:\" %6.2lf $del $label $del nope $del $uuid $del $owner_uuid\"";
    $cmd_legend_lower .= " COMMENT:\\n";
  }
  elsif ( $item =~ /^ovm_server_total_mem$|^ovm_serverpools_total_mem$/ ) {
    $cmd_cdef .= " CDEF:mem_used_graph_$index=mem_used_$index,1,*";
    $label =~ s/===double-col===/-/g;
    $label =~ s/://g;
    $cmd_legend_lower .= " COMMENT:\"$label_space    \"";
    $cmd_legend_lower .= " $gtype:mem_used_graph_$index$color_read:\" \"";
    $cmd_legend_lower .= " GPRINT:mem_used_legend_$index:AVERAGE:\" %6.2lf\"";
    $cmd_legend_lower .= " GPRINT:mem_used_legend_$index:MAX:\" %6.2lf    \"";
    $cmd_legend_lower .= " PRINT:mem_used_legend_$index:AVERAGE:\" %6.2lf $del $item $del $label $del $color_read $del $color_read\"";
    $cmd_legend_lower .= " PRINT:mem_used_legend_$index:MAX:\" %6.2lf $del $label $del nope $del $uuid $del $owner_uuid\"";
    $cmd_legend_lower .= " COMMENT:\\n";
  }

  return {
    cmd_def          => $cmd_def,          cmd_cdef => $cmd_cdef, cmd_legend_lower => $cmd_legend_lower,
    cmd_legend_upper => $cmd_legend_upper, filepath => $filepath
  };

}
