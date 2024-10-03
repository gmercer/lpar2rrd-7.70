#GCloudGraph.pm
# keep GCloud graph generation in one place, if possible
# (separated from `detail-graph-cgi.pl`)

package GCloudGraph;

use strict;
use warnings;

use Data::Dumper;

use GCloudDataWrapper;

defined $ENV{INPUTDIR} || warn( localtime() . ': INPUTDIR undefined, config etc/lpar2rrd.cfg probably has not been loaded ' . __FILE__ . ':' . __LINE__ ) && exit 1;

my $inputdir = $ENV{INPUTDIR};
my $wrkdir   = "$inputdir/data";

my $gcloud_path  = "$wrkdir/GCloud";
my $compute_path = "$wrkdir/GCloud/compute";

# helper delimiter: used to convert graph legends to HTML tables in `detail-graph-cgi.pl`
my $delimiter = 'XORUX';

################################################################################

# current usage in detail-graph-cgi.pl
#   graph_gcloud( $host, $server, $lpar, $time, $name_out, $type_sam, $detail, $start_unix, $end_unix );
#   graph_gcloud_totals( $host, $server, $lpar, $time, $name_out, $type_sam, $detail, $start_unix, $end_unix );
# and custom.pl

################################################################################

# assemble graph header
#   params: $type, $uuid, $context
#   output: "<platform> <context> @ $type <label-$type-$uuid>"
sub get_header {
  my $type    = shift;
  my $uuid    = shift;
  my $context = shift;

  my $label  = GCloudDataWrapper::get_label( $type, $uuid );
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
  $result .= " --vertical-label=\"Memory in [GB]\"";
  $result .= " --lower-limit=0.00";

  return $result;
}

sub get_params_proc {
  my $result = '';
  $result .= " --vertical-label=\"Processes in [Count]\"";
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
  my $unit   = 'MiB/s';
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

sub graph_processes {
  my $type = shift;    # value: 'host' or 'vm'
  my $uuid = shift;
  my $skip_acl = shift || 0; # optional flag

  # necessary information
  my $rrd = '';
  if ( $type eq 'compute' ) {
    $rrd = GCloudDataWrapper::get_filepath_rrd_compute($uuid);
  }

  # RRD command parts
  my $cmd_params = get_params_proc();
  my $cmd_def    = my $cmd_cdef = my $cmd_legend = '';

  my $metric_run = 'process_run';
  my $metric_pag = 'process_pag';
  my $metric_sto = 'process_sto';
  my $metric_blo = 'process_blo';
  my $metric_zom = 'process_zom';
  my $metric_sle = 'process_sle';

  $cmd_def .= " DEF:proc_run=\"$rrd\":${metric_run}:AVERAGE";
  $cmd_def .= " DEF:proc_pag=\"$rrd\":${metric_pag}:AVERAGE";
  $cmd_def .= " DEF:proc_sto=\"$rrd\":${metric_sto}:AVERAGE";
  $cmd_def .= " DEF:proc_blo=\"$rrd\":${metric_blo}:AVERAGE";
  $cmd_def .= " DEF:proc_zom=\"$rrd\":${metric_zom}:AVERAGE";
  $cmd_def .= " DEF:proc_sle=\"$rrd\":${metric_sle}:AVERAGE";

  $cmd_legend .= " COMMENT:\"[Count]                    Avrg       Max\\n\"";

  $cmd_legend .= " AREA:proc_run#FF0000:\" Running           \"";
  $cmd_legend .= " GPRINT:proc_run:AVERAGE:\" %6.1lf \"";
  $cmd_legend .= " GPRINT:proc_run:MAX:\" %6.1lf\"";
  $cmd_legend .= " COMMENT:\\n";

  $cmd_legend .= " STACK:proc_pag#00FF00:\" Paging            \"";
  $cmd_legend .= " GPRINT:proc_pag:AVERAGE:\" %6.1lf \"";
  $cmd_legend .= " GPRINT:proc_pag:MAX:\" %6.1lf\"";
  $cmd_legend .= " COMMENT:\\n";

  $cmd_legend .= " STACK:proc_sto#F0F00F:\" Stopped           \"";
  $cmd_legend .= " GPRINT:proc_sto:AVERAGE:\" %6.1lf \"";
  $cmd_legend .= " GPRINT:proc_sto:MAX:\" %6.1lf\"";
  $cmd_legend .= " COMMENT:\\n";

  $cmd_legend .= " STACK:proc_blo#c52f82:\" Blocked           \"";
  $cmd_legend .= " GPRINT:proc_blo:AVERAGE:\" %6.1lf \"";
  $cmd_legend .= " GPRINT:proc_blo:MAX:\" %6.1lf\"";
  $cmd_legend .= " COMMENT:\\n";

  $cmd_legend .= " STACK:proc_zom#4caa82:\" Zombie            \"";
  $cmd_legend .= " GPRINT:proc_zom:AVERAGE:\" %6.1lf \"";
  $cmd_legend .= " GPRINT:proc_zom:MAX:\" %6.1lf\"";
  $cmd_legend .= " COMMENT:\\n";

  $cmd_legend .= " STACK:proc_sle#0000FF:\" Sleeping          \"";
  $cmd_legend .= " GPRINT:proc_sle:AVERAGE:\" %6.1lf \"";
  $cmd_legend .= " GPRINT:proc_sle:MAX:\" %6.1lf\"";
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
  my $type = shift;    # value: 'host' or 'vm'
  my $uuid = shift;
  my $skip_acl = shift || 0; # optional flag

  # necessary information
  my $rrd = '';
  if ( $type eq 'compute' ) {
    $rrd = GCloudDataWrapper::get_filepath_rrd_compute($uuid);
  }
  elsif ( $type eq 'database' ) {
    $rrd = GCloudDataWrapper::get_filepath_rrd_database($uuid);
  }

  # RRD command parts
  my $cmd_params = get_params_memory();
  my $cmd_def    = my $cmd_cdef = my $cmd_legend = '';

  my ( $metric_total, $metric_free, $metric_used );

  $metric_free = 'mem_free';
  $metric_used = 'mem_used';

  $cmd_def .= " DEF:mem_free=\"$rrd\":${metric_free}:AVERAGE";
  $cmd_def .= " DEF:mem_used=\"$rrd\":${metric_used}:AVERAGE";

  my $b2gib   = 1000**3;
  my $kib2gib = 1000**2;
  my $mib2gib = 1000**1;

  $cmd_cdef .= " CDEF:used=mem_used,$b2gib,/";
  $cmd_cdef .= " CDEF:free=mem_free,$b2gib,/";

  #$cmd_cdef      .= " CDEF:total=used,free,+";

  $cmd_legend .= " COMMENT:\"[GiB]                      Avrg       Max\\n\"";
  $cmd_legend .= " AREA:used#FF0000:\" Memory used        \"";
  $cmd_legend .= " GPRINT:used:AVERAGE:\" %6.1lf\"";
  $cmd_legend .= " GPRINT:used:MAX:\" %6.1lf\"";
  $cmd_legend .= " COMMENT:\\n";
  $cmd_legend .= " STACK:free#00FF00:\" Memory free        \"";
  $cmd_legend .= " GPRINT:free:AVERAGE:\" %6.1lf\"";
  $cmd_legend .= " GPRINT:free:MAX:\" %6.1lf\"";
  $cmd_legend .= " COMMENT:\\n";
  my %result = (
    cmd_params => $cmd_params,
    cmd_def    => $cmd_def,
    cmd_cdef   => $cmd_cdef,
    cmd_legend => $cmd_legend,
  );

  return \%result;
}

sub graph_custom_2 {
  my $type         = shift;    # value: 'host' or 'vm'
  my $uuid         = shift;
  my $metric_free  = shift;
  my $metric_total = shift;
  my $item1        = shift;
  my $item2        = shift;
  my $skip_acl     = shift || 0; # optional flag

  # necessary information
  my $rrd = '';
  if ( $type eq 'database' ) {
    $rrd = GCloudDataWrapper::get_filepath_rrd_database($uuid);
  }

  # RRD command parts
  my $cmd_params = " --lower-limit=0.00";
  my $cmd_def    = my $cmd_cdef = my $cmd_legend = '';

  $cmd_def .= " DEF:item_free=\"$rrd\":${metric_free}:AVERAGE";
  $cmd_def .= " DEF:item_total=\"$rrd\":${metric_total}:AVERAGE";

  my $b2gib   = 1000**3;
  my $kib2gib = 1000**2;
  my $mib2gib = 1000**1;

  $cmd_cdef .= " CDEF:used=item_total,item_free,-";
  $cmd_cdef .= " CDEF:free=item_free,1,/";

  #$cmd_cdef      .= " CDEF:total=used,free,+";

  $cmd_legend .= " COMMENT:\"[Pages]                   Avrg       Max\\n\"";
  $cmd_legend .= " AREA:used#FF0000:\" $item2        \"";
  $cmd_legend .= " GPRINT:used:AVERAGE:\" %6.1lf\"";
  $cmd_legend .= " GPRINT:used:MAX:\" %6.1lf\"";
  $cmd_legend .= " COMMENT:\\n";
  $cmd_legend .= " STACK:free#00FF00:\" $item1        \"";
  $cmd_legend .= " GPRINT:free:AVERAGE:\" %6.1lf\"";
  $cmd_legend .= " GPRINT:free:MAX:\" %6.1lf\"";
  $cmd_legend .= " COMMENT:\\n";
  my %result = (
    cmd_params => $cmd_params,
    cmd_def    => $cmd_def,
    cmd_cdef   => $cmd_cdef,
    cmd_legend => $cmd_legend,
  );

  return \%result;
}

sub graph_storage_db {
  my $type = shift;    # value: 'host' or 'vm'
  my $uuid = shift;
  my $skip_acl = shift || 0; # optional flag

  # necessary information
  my $rrd = '';
  if ( $type eq 'database' ) {
    $rrd = GCloudDataWrapper::get_filepath_rrd_database($uuid);
  }

  # RRD command parts
  my $cmd_params = " --vertical-label=\"Storage in [GB]\"";
  my $cmd_def    = my $cmd_cdef = my $cmd_legend = '';

  my ( $metric_total, $metric_free, $metric_used );

  $metric_free = 'disk_free';
  $metric_used = 'disk_used';

  $cmd_def .= " DEF:disk_free=\"$rrd\":${metric_free}:AVERAGE";
  $cmd_def .= " DEF:disk_used=\"$rrd\":${metric_used}:AVERAGE";

  my $b2gib   = 1024**3;
  my $kib2gib = 1024**2;
  my $mib2gib = 1024**1;

  $cmd_cdef .= " CDEF:used=disk_used,$b2gib,/";
  $cmd_cdef .= " CDEF:free=disk_free,$b2gib,/";

  #$cmd_cdef      .= " CDEF:total=used,free,+";

  $cmd_legend .= " COMMENT:\"[GiB]                      Avrg       Max\\n\"";
  $cmd_legend .= " AREA:used#FF0000:\" Disk used          \"";
  $cmd_legend .= " GPRINT:used:AVERAGE:\" %6.1lf\"";
  $cmd_legend .= " GPRINT:used:MAX:\" %6.1lf\"";
  $cmd_legend .= " COMMENT:\\n";
  $cmd_legend .= " STACK:free#00FF00:\" Disk free          \"";
  $cmd_legend .= " GPRINT:free:AVERAGE:\" %6.1lf\"";
  $cmd_legend .= " GPRINT:free:MAX:\" %6.1lf\"";
  $cmd_legend .= " COMMENT:\\n";
  my %result = (
    cmd_params => $cmd_params,
    cmd_def    => $cmd_def,
    cmd_cdef   => $cmd_cdef,
    cmd_legend => $cmd_legend,
  );

  return \%result;
}

sub graph_pages {
  my $type = shift;    # value: 'host' or 'vm'
  my $uuid = shift;
  my $skip_acl = shift || 0; # optional flag

  # necessary information
  my $rrd = '';
  if ( $type eq 'database' ) {
    $rrd = GCloudDataWrapper::get_filepath_rrd_database($uuid);
  }

  # RRD command parts
  my $cmd_params = " --vertical-label=\"Pages in [Count]\"";
  my $cmd_def    = my $cmd_cdef = my $cmd_legend = '';

  $cmd_def .= " DEF:write_def=\'$rrd\':innodb_write:AVERAGE";
  $cmd_def .= " DEF:read_def=\'$rrd\':innodb_read:AVERAGE";

  $cmd_cdef .= " CDEF:write=write_def,1,/";
  $cmd_cdef .= " CDEF:read=read_def,1,/";
  $cmd_cdef .= " CDEF:read_graph=0,read_def,-";

  $cmd_legend .= " COMMENT:\"[Count]               Avrg       Max\\n\"";
  $cmd_legend .= " LINE1:read_graph#FF0000:\" Read         \"";
  $cmd_legend .= " GPRINT:read:AVERAGE:\" %6.2lf\"";
  $cmd_legend .= " GPRINT:read:MAX:\" %6.2lf\"";
  $cmd_legend .= " COMMENT:\\n";
  $cmd_legend .= " LINE1:write#0000FF:\" Write        \"";
  $cmd_legend .= " GPRINT:write:AVERAGE:\" %6.2lf\"";
  $cmd_legend .= " GPRINT:write:MAX:\" %6.2lf\"";
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

sub graph_cpu {
  my $type        = shift;    # value: 'host' or 'vm'
  my $uuid        = shift;
  my $metric_type = shift;    # value: 'percent' or 'cores'
  my $skip_acl    = shift || 0; # optional flag

  # necessary information
  my $rrd = '';
  if ( $type eq 'compute' ) {
    $rrd = GCloudDataWrapper::get_filepath_rrd_compute($uuid);
  }
  elsif ( $type eq 'database' ) {
    $rrd = GCloudDataWrapper::get_filepath_rrd_database($uuid);
  }

  # RRD command parts
  my $cmd_params = get_params_cpu();
  my $cmd_def    = my $cmd_cdef = my $cmd_legend = '';

  my $metric = 'cpu';
  if ( $metric_type eq 'cores' ) {    # 'cpu_cores' are the same for both 'vm' and 'host'
    $metric = 'cpu_cores';
  }
  elsif ( $type eq 'compute' || $type eq 'database' ) {
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

sub graph_lan {
  my $type = shift;
  my $uuid = shift;
  my $skip_acl = shift || 0; # optional flag

  # necessary information
  my $rrd = '';
  if ( $type eq 'compute' ) {
    $rrd = GCloudDataWrapper::get_filepath_rrd_compute($uuid);
  }
  elsif ( $type eq 'database' ) {
    $rrd = GCloudDataWrapper::get_filepath_rrd_database($uuid);
  }

  # RRD command parts
  my $cmd_params = get_params_lan();
  my $cmd_def    = my $cmd_cdef = my $cmd_legend = '';

  $cmd_def .= " DEF:transmitted=\'$rrd\':network_out:AVERAGE";
  $cmd_def .= " DEF:received=\'$rrd\':network_in:AVERAGE";

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
  if ( $type eq 'compute' ) {
    $rrd = GCloudDataWrapper::get_filepath_rrd_compute($uuid);
  }
  elsif ( $type eq 'database' ) {
    $rrd = GCloudDataWrapper::get_filepath_rrd_database($uuid);
  }

  # RRD command parts
  my $cmd_params = get_params_storage($metric_type);
  my $cmd_def    = my $cmd_cdef = my $cmd_legend = '';

  my ( $metric_read, $metric_write, $metric );
  $metric_read  = 'disk_read_bytes';
  $metric_write = 'disk_write_bytes';

  if ( $metric_type eq 'iops' ) {
    $metric_read  = 'disk_read_ops';
    $metric_write = 'disk_write_ops';
    if ( $type eq 'database' ) {
      $metric_read  = 'read_ops';
      $metric_write = 'write_ops';
    }
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

sub graph_custom {
  my $type        = shift;
  my $uuid        = shift;
  my $metric_type = shift;
  my $legend      = shift;
  my $toGB        = shift;
  my $item        = shift;
  my $skip_acl    = shift || 0; # optional flag

  # necessary information
  my $rrd = '';

  if ( $type eq 'database' ) {
    $rrd = GCloudDataWrapper::get_filepath_rrd_database($uuid);
  }

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

################################################################################
# to be moved to GCloudDataWrapper
sub get_uuid_from_filepath {
  my $type     = shift;    # value: 'vm' or 'host'
  my $filepath = shift;

  my $uuid;
  if ( $type eq 'compute' ) {
    $filepath =~ m/\/GCloud\/compute\/(.*)\.rrd/;
    $uuid = $1;
  }
  elsif ( $type eq 'region' ) {
    $filepath =~ m/\/GCloud\/region\/(.*)\.rrd/;
    $uuid = $1;
  }
  else {
    $filepath =~ m/\/GCloud\/(.*)\/(.*)\.rrd/;
    $uuid = $2;
  }

  return $uuid;
}

################################################################################

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
  my ( $metric_total, $metric_free, $graph_type, $metric_used );

  $metric_free = 'mem_free';
  $metric_used = 'mem_used';

  $graph_type = ( $counter > 0 ) ? 'STACK' : 'AREA';
  $cmd_def .= " DEF:mem_used_${counter}=\"${filepath}\":${metric_used}:AVERAGE";
  $cmd_def .= " DEF:mem_free_${counter}=\"${filepath}\":${metric_free}:AVERAGE";

  my $b2gib   = 1000**3;
  my $kib2gib = 1000**2;
  my $mib2gib = 1000**1;

  $cmd_cdef .= " CDEF:used_${counter}=mem_used_${counter},$b2gib,/";
  $cmd_cdef .= " CDEF:free_${counter}=mem_free_${counter},$b2gib,/";

  # $url_item is used in `ret_graph_param` to transform legends' table in `detail-graph-cgi.pl`
  my $url_item = "gcloud-compute-mem-${metric_type}-aggr";

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
  my $url_item = "gcloud-compute-${metric_type}-aggr";

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
  elsif ( $type eq 'compute' ) {
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
  my $url_item = "gcloud-$type-cpu-${metric_type}-aggr";
  if ( $type eq 'compute' && $group_type eq 'region' ) {    # VMs under host
    $url_item = "gcloud-region-compute-cpu-${metric_type}-aggr";
  }
  elsif ( $type eq 'compute' ) {                            # ad-hoc assignment for Custom groups
    $url_item = "custom-gcloud-compute-cpu-${metric_type}";
  }

  $url_item = "gcloud-compute-cpu-percent-aggr";

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
  my $url_item = "gcloud-$type-lan-aggr";
  if ( $type eq 'compute' ) {    # ad-hoc assignment for Custom groups; perhaps make a separate argument
    $url_item = 'custom-gcloud-compute-lan';
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

  #$cmd_legend_lower .= " ${graph_type}:0${color2}:\" \"";
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
  if ( $type eq 'compute' ) {                                                    # ad-hoc assignment for Custom groups; perhaps make a separate argument
    $url_item = "gcloud-compute-${item_type}-aggr";
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

