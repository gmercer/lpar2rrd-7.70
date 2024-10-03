# OVirtGraph.pm
# keep oVirt graph generation in one place, if possible
# (separated from `detail-graph-cgi.pl`)

package OVirtGraph;

use strict;
use warnings;

use Data::Dumper;
use Xorux_lib qw(error);

use OVirtDataWrapper;

defined $ENV{INPUTDIR} || warn( ' INPUTDIR undefined, config etc/lpar2rrd.cfg probably has not been loaded ' . __FILE__ . ':' . __LINE__ ) && exit 1;

my $inputdir         = $ENV{INPUTDIR};
my $ovirt_dir        = "$inputdir/data/oVirt";
my $host_data_dir    = "$ovirt_dir/host";
my $storage_data_dir = "$ovirt_dir/storage";
my $vm_data_dir      = "$ovirt_dir/vm";
my $metadata_file    = "$ovirt_dir/conf.json";

my $pow2 = 1000**2;
my $del  = 'XORUX';    # delimiter, this is for rrdtool print lines for clickable legend

################################################################################

sub get_header {
  my $type   = shift;
  my $uuid   = shift;
  my $metric = shift;
  my $label  = OVirtDataWrapper::get_label( $type, $uuid );

  if    ( $type eq 'vm' )             { $type = 'VM'; }
  elsif ( $type eq 'storage_domain' ) { $type = 'Storage domain'; }
  elsif ( $type eq 'host_nic' )       { $type = ''; }
  else                                { $type = ucfirst $type; }

  return ( "$type $metric : $label", "$metric:$label" );
}    ## sub get_header

sub get_formatted_label {
  my $label_space = shift;

  my $len = ( length($label_space) < 20 ) ? ( 20 - length($label_space) ) : 1;
  $label_space .= " " x $len;

  return $label_space;
}    ## sub get_formatted_label

################################################################################

sub graph_cpu_cores {
  my $type     = shift;
  my $uuid     = shift;
  my $skip_acl = shift || 0; # optional flag

  my $rrd      = OVirtDataWrapper::get_filepath_rrd( { type => $type, uuid => $uuid, skip_acl => $skip_acl } );
  my ( $header, $reduced_header ) = get_header( $type, $uuid, 'CPU cores' );

  my $cmd_params = my $cmd_legend = my $cmd_cdef = my $cmd_def = my $cmd_vlabel = '';

  $cmd_vlabel .= " --vertical-label=\"CPU load in cores\"";
  $cmd_params .= " --lower-limit=0.00";
  $cmd_params .= " --units-exponent=1.00";
  $cmd_def    .= " DEF:cpu_c=\"$rrd\":cpu_usage_c:AVERAGE";
  $cmd_def    .= " DEF:cores=\"$rrd\":number_of_cores:AVERAGE";
  $cmd_legend .= " COMMENT:\"[cores]               Avrg       Max\\n\"";
  $cmd_legend .= " LINE1:cpu_c#FF0000:\" Utilization   \"";
  $cmd_legend .= " GPRINT:cpu_c:AVERAGE:\" %6.1lf\"";
  $cmd_legend .= " GPRINT:cpu_c:MAX:\" %6.1lf\"";
  $cmd_legend .= " COMMENT:\\n";
  $cmd_legend .= " LINE2:cores#0a0a0a:\" Available     \"";
  $cmd_legend .= " GPRINT:cores:MAX:\" %6.1lf\"";
  $cmd_legend .= " GPRINT:cores:MAX:\" %6.1lf\"";
  $cmd_legend .= " COMMENT:\\n";

  return {
    filename => $rrd,     header   => $header,   reduced_header => $reduced_header, cmd_params => $cmd_params,
    cmd_def  => $cmd_def, cmd_cdef => $cmd_cdef, cmd_legend     => $cmd_legend,     cmd_vlabel => $cmd_vlabel
  };
}

sub graph_cpu_percent {
  my $type     = shift;
  my $uuid     = shift;
  my $skip_acl = shift || 0; # optional flag

  my $rrd      = OVirtDataWrapper::get_filepath_rrd( { type => $type, uuid => $uuid, skip_acl => $skip_acl } );
  my ( $header, $reduced_header ) = get_header( $type, $uuid, 'CPU %' );

  my $cmd_params = my $cmd_legend = my $cmd_cdef = my $cmd_def = my $cmd_vlabel = '';

  $cmd_vlabel .= " --vertical-label=\"CPU load in [%]\"";
  $cmd_params .= " --upper-limit=100.0";
  $cmd_params .= " --lower-limit=0.00";
  $cmd_def    .= " DEF:user_p=\"$rrd\":user_cpu_usage_p:AVERAGE";
  $cmd_def    .= " DEF:system_p=\"$rrd\":system_cpu_usage_p:AVERAGE";
  $cmd_def    .= " CDEF:idle_p=100,user_p,-,system_p,-";
  $cmd_legend .= " COMMENT:\"[%]                Avrg       Max\\n\"";
  $cmd_legend .= " AREA:system_p#0080FF:\" Sys        \"";
  $cmd_legend .= " GPRINT:system_p:AVERAGE:\" %6.0lf\"";
  $cmd_legend .= " GPRINT:system_p:MAX:\" %6.0lf\"";
  $cmd_legend .= " COMMENT:\\n";
  $cmd_legend .= " STACK:user_p#FFFF00:\" User       \"";
  $cmd_legend .= " GPRINT:user_p:AVERAGE:\" %6.0lf\"";
  $cmd_legend .= " GPRINT:user_p:MAX:\" %6.0lf\"";
  $cmd_legend .= " COMMENT:\\n";
  $cmd_legend .= " STACK:idle_p#00FF00:\" Idle       \"";
  $cmd_legend .= " GPRINT:idle_p:AVERAGE:\" %6.0lf\"";
  $cmd_legend .= " GPRINT:idle_p:MAX:\" %6.0lf\"";

  $cmd_legend .= " COMMENT:\\n";

  return {
    filename => $rrd,     header   => $header,   reduced_header => $reduced_header, cmd_params => $cmd_params,
    cmd_def  => $cmd_def, cmd_cdef => $cmd_cdef, cmd_legend     => $cmd_legend,     cmd_vlabel => $cmd_vlabel
  };
}

sub graph_mem {
  my $type     = shift;
  my $uuid     = shift;
  my $skip_acl = shift || 0; # optional flag

  my $rrd      = OVirtDataWrapper::get_filepath_rrd( { type => $type, uuid => $uuid, skip_acl => $skip_acl } );
  my ( $header, $reduced_header ) = get_header( $type, $uuid, 'MEM' );

  my $cmd_params = my $cmd_legend = my $cmd_cdef = my $cmd_def = my $cmd_vlabel = '';

  $cmd_vlabel .= " --vertical-label=\"Memory in GBytes\"";
  $cmd_params .= " --lower-limit=0.00";
  $cmd_params .= " --base=1024";
  $cmd_params .= " --units-exponent=1.00";
  $cmd_def    .= " DEF:mem=\"$rrd\":memory_used:AVERAGE";
  $cmd_def    .= " DEF:mem_free=\"$rrd\":memory_free:AVERAGE";
  $cmd_cdef   .= " CDEF:mem_gb=mem,1024,/";
  $cmd_cdef   .= " CDEF:mem_free_gb=mem_free,1024,/";
  $cmd_legend .= " COMMENT:\"[GB]                     Avrg      Max\\n\"";
  $cmd_legend .= " AREA:mem_gb#FF4040:\" Memory used     \"";
  $cmd_legend .= " GPRINT:mem_gb:AVERAGE:\" %6.1lf\"";
  $cmd_legend .= " GPRINT:mem_gb:MAX:\" %6.1lf\"";
  $cmd_legend .= " COMMENT:\\n";

  if ( $type eq 'vm' ) {
    $cmd_def    .= " DEF:mem_buffer=\"$rrd\":memory_buffered:AVERAGE";
    $cmd_def    .= " DEF:mem_cache=\"$rrd\":memory_cached:AVERAGE";
    $cmd_cdef   .= " CDEF:mem_buffer_gb=mem_buffer,1024,/";
    $cmd_cdef   .= " CDEF:mem_cache_gb=mem_cache,1024,/";
    $cmd_legend .= " STACK:mem_cache_gb#0080FF:\" Memory cache    \"";
    $cmd_legend .= " GPRINT:mem_cache_gb:AVERAGE:\" %6.1lf\"";
    $cmd_legend .= " GPRINT:mem_cache_gb:MAX:\" %6.1lf\"";
    $cmd_legend .= " COMMENT:\\n";
    $cmd_legend .= " STACK:mem_buffer_gb#F808F8:\" Memory buffer   \"";
    $cmd_legend .= " GPRINT:mem_buffer_gb:AVERAGE:\" %6.1lf\"";
    $cmd_legend .= " GPRINT:mem_buffer_gb:MAX:\" %6.1lf\"";
    $cmd_legend .= " COMMENT:\\n";
  }

  $cmd_legend .= " STACK:mem_free_gb#00FF00:\" Memory free     \"";
  $cmd_legend .= " GPRINT:mem_free_gb:AVERAGE:\" %6.1lf\"";
  $cmd_legend .= " GPRINT:mem_free_gb:MAX:\" %6.1lf\"";
  $cmd_legend .= " COMMENT:\\n";

  return {
    filename => $rrd,     header   => $header,   reduced_header => $reduced_header, cmd_params => $cmd_params,
    cmd_def  => $cmd_def, cmd_cdef => $cmd_cdef, cmd_legend     => $cmd_legend,     cmd_vlabel => $cmd_vlabel
  };
}    ## sub graph_mem

sub graph_host_net {
  my $uuid_host = shift;
  my $uuid_nic  = shift;
  my $skip_acl  = shift || 0; # optional flag

  my $rrd       = OVirtDataWrapper::get_filepath_rrd( { type => 'host_nic', uuid => $uuid_host, id => $uuid_nic, skip_acl => $skip_acl } );
  my ( $header, $reduced_header ) = get_header( 'host_nic', $uuid_nic, 'LAN' );

  my $cmd_params = my $cmd_legend = my $cmd_cdef = my $cmd_def = my $cmd_vlabel = '';

  $cmd_vlabel .= " --vertical-label=\"Read - Bytes/sec - Write\"";
  $cmd_def    .= " DEF:read=\"$rrd\":received_byte:AVERAGE";
  $cmd_def    .= " DEF:write=\"$rrd\":transmitted_byte:AVERAGE";
  $cmd_cdef   .= " CDEF:read_b=read,60,/";
  $cmd_cdef   .= " CDEF:write_b=write,60,/";
  $cmd_cdef   .= " CDEF:read_b_graph=0,read_b,-";
  $cmd_cdef   .= " CDEF:read_mb=read,$pow2,/,60,/";
  $cmd_cdef   .= " CDEF:write_mb=write,$pow2,/,60,/";
  $cmd_legend .= " COMMENT:\"[MB/sec]           Avrg       Max\\n\"";
  $cmd_legend .= " LINE1:write_b#0000FF:\" Write      \"";
  $cmd_legend .= " GPRINT:write_mb:AVERAGE:\" %6.2lf\"";
  $cmd_legend .= " GPRINT:write_mb:MAX:\" %6.2lf\"";
  $cmd_legend .= " COMMENT:\\n";
  $cmd_legend .= " LINE1:read_b_graph#FF0000:\" Read       \"";
  $cmd_legend .= " GPRINT:read_mb:AVERAGE:\" %6.2lf\"";
  $cmd_legend .= " GPRINT:read_mb:MAX:\" %6.2lf\"";
  $cmd_legend .= " COMMENT:\\n";

  return {
    filename => $rrd,     header   => $header,   reduced_header => $reduced_header, cmd_params => $cmd_params,
    cmd_def  => $cmd_def, cmd_cdef => $cmd_cdef, cmd_legend     => $cmd_legend,     cmd_vlabel => $cmd_vlabel
  };
}

sub graph_disk_data {
  my $uuid     = shift;
  my $skip_acl = shift || 0; # optional flag

  my $rrd      = OVirtDataWrapper::get_filepath_rrd( { type => 'disk', uuid => $uuid, skip_acl => $skip_acl } );
  my ( $header, $reduced_header ) = get_header( 'disk', $uuid, 'Data' );

  my $cmd_params = my $cmd_legend = my $cmd_cdef = my $cmd_def = my $cmd_vlabel = '';

  $cmd_vlabel .= " --vertical-label=\"Read - Bytes/sec - Write\"";
  $cmd_def    .= " DEF:read=\"$rrd\":data_current_read:AVERAGE";
  $cmd_def    .= " DEF:write=\"$rrd\":data_current_write:AVERAGE";
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

sub graph_disk_latency {
  my $uuid     = shift;
  my $skip_acl = shift || 0; # optional flag

  my $rrd      = OVirtDataWrapper::get_filepath_rrd( { type => 'disk', uuid => $uuid, skip_acl => $skip_acl } );
  my ( $header, $reduced_header ) = get_header( 'disk', $uuid, 'Latency' );

  my $cmd_params = my $cmd_legend = my $cmd_cdef = my $cmd_def = my $cmd_vlabel = '';

  $cmd_vlabel .= " --vertical-label=\"Read - millisec - Write\"";
  $cmd_def    .= " DEF:read=\"$rrd\":disk_read_latency:AVERAGE";
  $cmd_def    .= " DEF:write=\"$rrd\":disk_write_latency:AVERAGE";
  $cmd_cdef   .= " CDEF:read_ms=read,1000,*";
  $cmd_cdef   .= " CDEF:read_ms_graph=0,read_ms,-";
  $cmd_cdef   .= " CDEF:write_ms=write,1000,*";
  $cmd_legend .= " COMMENT:\"[millisec]         Avrg       Max\\n\"";
  $cmd_legend .= " LINE1:write_ms#0000FF:\" Write      \"";
  $cmd_legend .= " GPRINT:write_ms:AVERAGE:\" %6.1lf\"";
  $cmd_legend .= " GPRINT:write_ms:MAX:\" %6.1lf\"";
  $cmd_legend .= " COMMENT:\\n";
  $cmd_legend .= " LINE1:read_ms_graph#FF0000:\" Read       \"";
  $cmd_legend .= " GPRINT:read_ms:AVERAGE:\" %6.1lf\"";
  $cmd_legend .= " GPRINT:read_ms:MAX:\" %6.1lf\"";
  $cmd_legend .= " COMMENT:\\n";

  return {
    filename => $rrd,     header   => $header,   reduced_header => $reduced_header, cmd_params => $cmd_params,
    cmd_def  => $cmd_def, cmd_cdef => $cmd_cdef, cmd_legend     => $cmd_legend,     cmd_vlabel => $cmd_vlabel
  };
}

sub graph_disk_iops {
  my $uuid     = shift;
  my $skip_acl = shift || 0; # optional flag

  # TODO change filepath to the new RRD
  my $rrd      = OVirtDataWrapper::get_filepath_rrd( { type => 'disk', metric => 'iops', uuid => $uuid, skip_acl => $skip_acl } );
  my ( $header, $reduced_header ) = get_header( 'disk', $uuid, 'IOPS' );

  my $cmd_params = my $cmd_legend = my $cmd_cdef = my $cmd_def = my $cmd_vlabel = '';

  $cmd_vlabel .= " --vertical-label=\"Read - IOPS - Write\"";
  $cmd_def    .= " DEF:read=\"$rrd\":disk_read_iops:AVERAGE";
  $cmd_def    .= " DEF:write=\"$rrd\":disk_write_iops:AVERAGE";
  $cmd_cdef   .= " CDEF:read_ps=read,60,/";
  $cmd_cdef   .= " CDEF:write_ps=write,60,/";
  $cmd_cdef   .= " CDEF:read_graph=read_ps,-1,*";
  $cmd_legend .= " COMMENT:\"[IOPS]             Avrg       Max\\n\"";
  $cmd_legend .= " LINE1:write_ps#0000FF:\" Write      \"";
  $cmd_legend .= " GPRINT:write_ps:AVERAGE:\" %6.0lf\"";
  $cmd_legend .= " GPRINT:write_ps:MAX:\" %6.0lf\"";
  $cmd_legend .= " COMMENT:\\n";
  $cmd_legend .= " LINE1:read_graph#FF0000:\" Read       \"";
  $cmd_legend .= " GPRINT:read_ps:AVERAGE:\" %6.0lf\"";
  $cmd_legend .= " GPRINT:read_ps:MAX:\" %6.0lf\"";
  $cmd_legend .= " COMMENT:\\n";

  return {
    filename => $rrd,     header   => $header,   reduced_header => $reduced_header, cmd_params => $cmd_params,
    cmd_def  => $cmd_def, cmd_cdef => $cmd_cdef, cmd_legend     => $cmd_legend,     cmd_vlabel => $cmd_vlabel
  };
}

sub graph_disk_space {
  my $uuid     = shift;
  my $skip_acl = shift || 0; # optional flag

  my $rrd      = OVirtDataWrapper::get_filepath_rrd( { type => 'disk', uuid => $uuid, skip_acl => $skip_acl } );
  my ( $header, $reduced_header ) = get_header( 'disk', $uuid, 'Space' );

  my $cmd_params = my $cmd_legend = my $cmd_cdef = my $cmd_def = my $cmd_vlabel = '';

  $cmd_vlabel .= " --vertical-label=\"Space in GBytes\"";
  $cmd_params .= " --base=1024";
  $cmd_params .= " --lower-limit=0.00";
  $cmd_def    .= " DEF:actual=\"$rrd\":vm_disk_size_mb:AVERAGE";
  $cmd_cdef   .= " CDEF:actual_gb=actual,1024,/";
  $cmd_legend .= " COMMENT:\"[GB]               Avrg       Max\\n\"";
  $cmd_legend .= " LINE1:actual_gb#FF0000:\" Used space \"";
  $cmd_legend .= " GPRINT:actual_gb:AVERAGE:\" %6.1lf\"";
  $cmd_legend .= " GPRINT:actual_gb:MAX:\" %6.1lf\"";
  $cmd_legend .= " COMMENT:\\n";

  return {
    filename => $rrd,     header   => $header,   reduced_header => $reduced_header, cmd_params => $cmd_params,
    cmd_def  => $cmd_def, cmd_cdef => $cmd_cdef, cmd_legend     => $cmd_legend,     cmd_vlabel => $cmd_vlabel
  };
}

sub graph_storage_domain_space {
  my $uuid     = shift;
  my $skip_acl = shift || 0; # optional flag

  my $rrd      = OVirtDataWrapper::get_filepath_rrd( { type => 'storage_domain', uuid => $uuid, skip_acl => $skip_acl } );
  my ( $header, $reduced_header ) = get_header( 'storage_domain', $uuid, 'Space' );

  my $cmd_params = my $cmd_legend = my $cmd_cdef = my $cmd_def = my $cmd_vlabel = '';

  $cmd_vlabel .= " --vertical-label=\"Space in Terabytes\"";
  $cmd_params .= " --base=1024";
  $cmd_params .= " --lower-limit=0.00";
  $cmd_def    .= " DEF:space_gb=\"$rrd\":used_disk_size_gb:AVERAGE";
  $cmd_def    .= " DEF:space_total_gb=\"$rrd\":total_disk_size_gb:AVERAGE";
  $cmd_cdef   .= " CDEF:space_tb=space_gb,1024,/";
  $cmd_cdef   .= " CDEF:space_total_tb=space_total_gb,1024,/";
  $cmd_legend .= " COMMENT:\"[TB]                     Avrg       Max\\n\"";
  $cmd_legend .= " AREA:space_total_tb#00FF00:\" Space total      \"";
  $cmd_legend .= " GPRINT:space_total_tb:AVERAGE:\" %6.2lf\"";
  $cmd_legend .= " GPRINT:space_total_tb:MAX:\" %6.2lf\"";
  $cmd_legend .= " COMMENT:\\n";
  $cmd_legend .= " AREA:space_tb#FF0000:\" Space used       \"";
  $cmd_legend .= " GPRINT:space_tb:AVERAGE:\" %6.2lf\"";
  $cmd_legend .= " GPRINT:space_tb:MAX:\" %6.2lf\"";
  $cmd_legend .= " COMMENT:\\n";

  return {
    filename => $rrd,     header   => $header,   reduced_header => $reduced_header, cmd_params => $cmd_params,
    cmd_def  => $cmd_def, cmd_cdef => $cmd_cdef, cmd_legend     => $cmd_legend,     cmd_vlabel => $cmd_vlabel
  };
}

################################################################################

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

  if ( $item =~ /(vm|storage_domain)_aggr_(data|latency|iops)$/ ) {
    $label = OVirtDataWrapper::get_label( 'disk', $uuid );
    $filepath = OVirtDataWrapper::get_filepath_rrd( { type => 'disk', uuid => $uuid, skip_acl => $skip_acl } );
    if ( $item =~ /iops$/ ) {
      $filepath = OVirtDataWrapper::get_filepath_rrd( { type => 'disk', metric => 'iops', uuid => $uuid, skip_acl => $skip_acl } );
    }
  }
  elsif ( $item =~ /storage_domains_total_aggr_(data|latency|iops)$/ ) {
    my $disk_label = OVirtDataWrapper::get_label( 'disk', $uuid );
    my $storage_domain_uuid = OVirtDataWrapper::get_parent( 'disk', $uuid );
    my $storage_domain_label = $storage_domain_uuid ? OVirtDataWrapper::get_label( 'storage_domain', $storage_domain_uuid ) : '';

    $label = "$storage_domain_label $disk_label";
    $filepath = OVirtDataWrapper::get_filepath_rrd( { type => 'disk', uuid => $uuid, skip_acl => $skip_acl } );
    if ( $item =~ /iops$/ ) {
      $filepath = OVirtDataWrapper::get_filepath_rrd( { type => 'disk', metric => 'iops', uuid => $uuid, skip_acl => $skip_acl } );
    }
  }
  elsif ( $item =~ /vm_aggr_net$/ && $owner_uuid ) {
    $label = OVirtDataWrapper::get_label( 'vm_nic', $uuid );
    $filepath = OVirtDataWrapper::get_filepath_rrd( { type => 'vm_nic', uuid => $owner_uuid, id => $uuid, skip_acl => $skip_acl } );
  }
  elsif ( $item =~ /host_nic_aggr_net$/ && $owner_uuid ) {
    $label = OVirtDataWrapper::get_label( 'host_nic', $uuid );
    $filepath = OVirtDataWrapper::get_filepath_rrd( { type => 'host_nic', uuid => $owner_uuid, id => $uuid, skip_acl => $skip_acl } );
  }
  else {
    return {};
  }

  my $label_space = get_formatted_label($label);

  if ( $item =~ /_aggr_data$/ ) {
    $gtype = $index > 0 ? 'STACK' : 'AREA';
    $cmd_def  .= " DEF:read_$index=\"$filepath\":data_current_read:AVERAGE";
    $cmd_def  .= " DEF:write_$index=\"$filepath\":data_current_write:AVERAGE";
    $cmd_cdef .= " CDEF:read_units_$index=read_$index";
    $cmd_cdef .= " CDEF:write_units_$index=write_$index";
    $cmd_cdef .= " CDEF:read_legend_$index=read_$index,$pow2,/";
    $cmd_cdef .= " CDEF:write_legend_$index=write_$index,$pow2,/";
  }
  elsif ( $item =~ /aggr_latency$/ ) {
    $gtype = 'LINE1';
    $cmd_def  .= " DEF:read_$index=\"$filepath\":disk_read_latency:AVERAGE";
    $cmd_def  .= " DEF:write_$index=\"$filepath\":disk_write_latency:AVERAGE";
    $cmd_cdef .= " CDEF:read_units_$index=read_$index,1000,*";
    $cmd_cdef .= " CDEF:write_units_$index=write_$index,1000,*";
    $cmd_cdef .= " CDEF:read_legend_$index=read_$index,1000,*";
    $cmd_cdef .= " CDEF:write_legend_$index=write_$index,1000,*";
  }
  elsif ( $item =~ /aggr_iops$/ ) {
    $gtype = 'LINE1';
    $cmd_def  .= " DEF:read_$index=\"$filepath\":disk_read_iops:AVERAGE";
    $cmd_def  .= " DEF:write_$index=\"$filepath\":disk_write_iops:AVERAGE";
    $cmd_cdef .= " CDEF:read_units_$index=read_$index,60,/";
    $cmd_cdef .= " CDEF:write_units_$index=write_$index,60,/";
    $cmd_cdef .= " CDEF:read_legend_$index=read_$index,60,/";
    $cmd_cdef .= " CDEF:write_legend_$index=write_$index,60,/";
  }
  elsif ( $item =~ /_net$/ ) {
    $gtype = $index > 0 ? 'STACK' : 'AREA';
    $cmd_def  .= " DEF:read_$index=\"$filepath\":received_byte:AVERAGE";
    $cmd_def  .= " DEF:write_$index=\"$filepath\":transmitted_byte:AVERAGE";
    $cmd_cdef .= " CDEF:read_units_$index=read_$index,60,/";
    $cmd_cdef .= " CDEF:write_units_$index=write_$index,60,/";
    $cmd_cdef .= " CDEF:read_legend_$index=read_$index,$pow2,/,60,/";
    $cmd_cdef .= " CDEF:write_legend_$index=write_$index,$pow2,/,60,/";
  }

  $cmd_cdef .= " CDEF:read_graph_$index=read_units_$index,-1,*";

  if ( $item =~ /aggr_iops$/ ) {
  $cmd_legend_lower .= " COMMENT:\"$label_space\"";
  $cmd_legend_lower .= " $gtype:read_graph_$index$color_read:\" \"";
  $cmd_legend_lower .= " GPRINT:read_legend_$index:AVERAGE:\" %6.0lf\"";
  $cmd_legend_lower .= " GPRINT:read_legend_$index:MAX:\" %6.0lf    \"";
  $cmd_legend_lower .= " PRINT:read_legend_$index:AVERAGE:\" %6.0lf $del $item $del $label $del $color_read $del $color_read\"";
  $cmd_legend_lower .= " PRINT:read_legend_$index:MAX:\" %6.0lf $del $label $del nope $del $uuid $del $owner_uuid\"";

  $cmd_legend_upper .= " $gtype:write_units_$index$color_write: ";
  $cmd_legend_lower .= " $gtype:0$color_write:\" \"";
  $cmd_legend_lower .= " GPRINT:write_legend_$index:AVERAGE:\" %6.0lf\"";
  $cmd_legend_lower .= " GPRINT:write_legend_$index:MAX:\" %6.0lf\"";
  $cmd_legend_lower .= " PRINT:write_legend_$index:AVERAGE:\" %6.0lf $del $color_write\"";
  $cmd_legend_lower .= " PRINT:write_legend_$index:MAX:\" %6.0lf $del $label\"";
  $cmd_legend_lower .= " COMMENT:\\n";
  }
  else {
    $cmd_legend_lower .= " COMMENT:\"$label_space\"";
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

  return {
    cmd_def          => $cmd_def,          cmd_cdef => $cmd_cdef, cmd_legend_lower => $cmd_legend_lower,
    cmd_legend_upper => $cmd_legend_upper, filepath => $filepath
  };
}

sub graph_simple_aggr {
  my $uuid     = shift;
  my $item     = shift;
  my $index    = shift;
  my $color    = shift;
  my $skip_acl = shift || 0; # optional flag
  my $cmd_def  = my $cmd_cdef = my $cmd_legend = '';
  my $gtype;

  $item =~ /(vm|host)_(cpu_core|cpu_percent|mem_used|mem_free|mem_used_percent)$/;

  unless ( $1 && $2 ) { return {}; }

  my $rrd_type    = $1;
  my $graph_type  = $2;
  my $label       = OVirtDataWrapper::get_label( $rrd_type, $uuid );
  my $filepath    = OVirtDataWrapper::get_filepath_rrd( { type => $rrd_type, uuid => $uuid, skip_acl => $skip_acl } );
  my $label_space = get_formatted_label($label);

  if ( $graph_type eq 'cpu_core' ) {
    $gtype = $index > 0 ? 'STACK' : 'AREA';
    $cmd_def  .= " DEF:metric_$index=\"$filepath\":cpu_usage_c:AVERAGE";
    $cmd_cdef .= " CDEF:metric_units_$index=metric_$index";
    $cmd_cdef .= " CDEF:metric_legend_$index=metric_$index";
  }
  elsif ( $graph_type eq 'cpu_percent' ) {
    $gtype = 'LINE1';
    $cmd_def  .= " DEF:metric_$index=\"$filepath\":cpu_usage_p:AVERAGE";
    $cmd_cdef .= " CDEF:metric_units_$index=metric_$index";
    $cmd_cdef .= " CDEF:metric_legend_$index=metric_$index";
  }
  elsif ( $graph_type eq 'mem_used' ) {
    $gtype = $index > 0 ? 'STACK' : 'AREA';
    $cmd_def  .= " DEF:metric_$index=\"$filepath\":memory_used:AVERAGE";
    $cmd_cdef .= " CDEF:metric_units_$index=metric_$index,1024,/";
    $cmd_cdef .= " CDEF:metric_legend_$index=metric_units_$index";
  }
  elsif ( $graph_type eq 'mem_free' ) {
    $gtype = $index > 0 ? 'STACK' : 'AREA';
    $cmd_def  .= " DEF:metric_$index=\"$filepath\":memory_free:AVERAGE";
    $cmd_cdef .= " CDEF:metric_units_$index=metric_$index,1024,/";
    $cmd_cdef .= " CDEF:metric_legend_$index=metric_units_$index";
  }
  elsif ( $graph_type eq 'mem_used_percent' ) {
    $gtype = 'LINE1';
    $cmd_def .= " DEF:metric_used_$index=\"$filepath\":memory_used:AVERAGE";
    $cmd_def .= " DEF:metric_free_$index=\"$filepath\":memory_free:AVERAGE";

    if ( $rrd_type eq 'vm' ) {
      $cmd_def  .= " DEF:metric_cache_$index=\"$filepath\":memory_cached:AVERAGE";
      $cmd_def  .= " DEF:metric_buffer_$index=\"$filepath\":memory_buffered:AVERAGE";
      $cmd_cdef .= " CDEF:metric_total_$index=metric_used_$index,metric_free_$index,metric_cache_$index,metric_buffer_$index,+,+,+";
      $cmd_cdef .= " CDEF:metric_$index=metric_used_$index,metric_total_$index,/,100,*";
    }
    else {
      $cmd_cdef .= " CDEF:metric_total_$index=metric_used_$index,metric_free_$index,+";
      $cmd_cdef .= " CDEF:metric_$index=metric_used_$index,metric_total_$index,/,100,*";
    }

    $cmd_cdef .= " CDEF:metric_units_$index=metric_$index";
    $cmd_cdef .= " CDEF:metric_legend_$index=metric_units_$index";
  }

  if ( $item =~ /percent$/ ) {
    $cmd_legend .= " COMMENT:\"$label_space\"";
    $cmd_legend .= " $gtype:metric_units_$index$color:\" \"";
    $cmd_legend .= " GPRINT:metric_legend_$index:AVERAGE:\" %6.0lf\"";
    $cmd_legend .= " GPRINT:metric_legend_$index:MAX:\" %6.0lf    \"";
    $cmd_legend .= " PRINT:metric_legend_$index:AVERAGE:\" %6.0lf $del $item $del $label $del $color $del $color\"";
    $cmd_legend .= " PRINT:metric_legend_$index:MAX:\" %6.0lf $del $label $del nope $del $uuid\"";
    $cmd_legend .= " COMMENT:\\n";
  }
  else {
    $cmd_legend .= " COMMENT:\"$label_space\"";
    $cmd_legend .= " $gtype:metric_units_$index$color:\" \"";
    $cmd_legend .= " GPRINT:metric_legend_$index:AVERAGE:\" %6.1lf\"";
    $cmd_legend .= " GPRINT:metric_legend_$index:MAX:\" %6.1lf    \"";
    $cmd_legend .= " PRINT:metric_legend_$index:AVERAGE:\" %6.1lf $del $item $del $label $del $color $del $color\"";
    $cmd_legend .= " PRINT:metric_legend_$index:MAX:\" %6.1lf $del $label $del nope $del $uuid\"";
    $cmd_legend .= " COMMENT:\\n";
  }

  return { cmd_def => $cmd_def, cmd_cdef => $cmd_cdef, cmd_legend => $cmd_legend, filepath => $filepath };
}    ## sub graph_simple_aggr

################################################################################

sub graph_custom_cpu {
  my $type     = shift;
  my $filepath = shift;
  my $index    = shift;
  my $color    = shift;
  my $label    = shift;
  my $cluster  = shift;

  # RRD command parts
  my $cmd_def = my $cmd_cdef = my $cmd_legend = '';
  my $label_space   = get_formatted_label($label);
  my $cluster_space = get_formatted_label($cluster);
  my $gtype;
  my $item;

  $filepath =~ /\/oVirt\/(vm|host)\/(.*)\/sys.rrd/;
  my $uuid = $2;
  my $cluster_uuid = OVirtDataWrapper::get_parent( 'vm', $uuid );

  if ( $type eq 'core' ) {
    $cmd_def  .= " DEF:metric_$index=\"$filepath\":cpu_usage_c:AVERAGE";
    $cmd_cdef .= " CDEF:metric_units_$index=metric_$index";
    $cmd_cdef .= " CDEF:metric_legend_$index=metric_$index";
    $item = 'custom_ovirt_vm_cpu_core';
    $gtype = ( $index > 0 ) ? 'STACK' : 'AREA';
  }
  elsif ( $type eq 'percent' ) {
    $cmd_def  .= " DEF:metric_$index=\"$filepath\":cpu_usage_p:AVERAGE";
    $cmd_cdef .= " CDEF:metric_units_$index=metric_$index";
    $cmd_cdef .= " CDEF:metric_legend_$index=metric_$index";
    $item  = 'custom_ovirt_vm_cpu_percent';
    $gtype = "LINE1";
  }

  if ( $type eq 'percent' ) {
    $cmd_legend .= " $gtype:metric_units_$index$color:\" \"";
    $cmd_legend .= " COMMENT:\"$cluster_space  $label_space\"";
    $cmd_legend .= " GPRINT:metric_legend_$index:AVERAGE:\" %6.0lf\"";
    $cmd_legend .= " GPRINT:metric_legend_$index:MAX:\" %6.0lf    \"";
    $cmd_legend .= " PRINT:metric_legend_$index:AVERAGE:\" %6.0lf $del $item $del $label $del $color $del $color\"";
    $cmd_legend .= " PRINT:metric_legend_$index:MAX:\" %6.0lf $del $label $del $cluster $del $uuid $del $cluster_uuid\"";
    $cmd_legend .= " COMMENT:\\n";
  }
  else {
    $cmd_legend .= " $gtype:metric_units_$index$color:\" \"";
    $cmd_legend .= " COMMENT:\"$cluster_space  $label_space\"";
    $cmd_legend .= " GPRINT:metric_legend_$index:AVERAGE:\" %6.1lf\"";
    $cmd_legend .= " GPRINT:metric_legend_$index:MAX:\" %6.1lf    \"";
    $cmd_legend .= " PRINT:metric_legend_$index:AVERAGE:\" %6.1lf $del $item $del $label $del $color $del $color\"";
    $cmd_legend .= " PRINT:metric_legend_$index:MAX:\" %6.1lf $del $label $del $cluster $del $uuid $del $cluster_uuid\"";
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

sub graph_custom_memory {
  my $type     = shift;
  my $filepath = shift;
  my $index    = shift;
  my $color    = shift;
  my $label    = shift;
  my $cluster  = shift;

  # RRD command parts
  my $cmd_def = my $cmd_cdef = my $cmd_legend = '';
  my $label_space   = get_formatted_label($label);
  my $cluster_space = get_formatted_label($cluster);
  my $gtype         = ( $index > 0 ) ? 'STACK' : 'AREA';
  my $item;
  $filepath =~ /\/oVirt\/(vm|host)\/(.*)\/sys.rrd/;

  my $uuid = $2;
  my $cluster_uuid = OVirtDataWrapper::get_parent( 'vm', $uuid );

  if ( $type eq 'mem_used' ) {
    $cmd_def  .= " DEF:metric_$index=\"$filepath\":memory_used:AVERAGE";
    $cmd_cdef .= " CDEF:metric_units_$index=metric_$index,1024,/";
    $cmd_cdef .= " CDEF:metric_legend_$index=metric_units_$index";
    $item = 'custom_ovirt_vm_mem_used';
  }
  elsif ( $type eq 'mem_free' ) {
    $cmd_def  .= " DEF:metric_$index=\"$filepath\":memory_free:AVERAGE";
    $cmd_cdef .= " CDEF:metric_units_$index=metric_$index,1024,/";
    $cmd_cdef .= " CDEF:metric_legend_$index=metric_units_$index";
    $item = 'custom_ovirt_vm_mem_free';
  }

  $cmd_legend .= " $gtype:metric_units_$index$color:\" \"";
  $cmd_legend .= " COMMENT:\"$cluster_space  $label_space\"";
  $cmd_legend .= " GPRINT:metric_legend_$index:AVERAGE:\" %6.1lf\"";
  $cmd_legend .= " GPRINT:metric_legend_$index:MAX:\" %6.1lf    \"";
  $cmd_legend .= " PRINT:metric_legend_$index:AVERAGE:\" %6.1lf $del $item $del $label $del $color $del $color\"";
  $cmd_legend .= " PRINT:metric_legend_$index:MAX:\" %6.1lf $del $label $del $cluster $del $uuid $del $cluster_uuid\"";
  $cmd_legend .= " COMMENT:\\n";

  # return the data
  my %result = (
    cmd_def    => $cmd_def,
    cmd_cdef   => $cmd_cdef,
    cmd_legend => $cmd_legend
  );

  return \%result;
}

1;
