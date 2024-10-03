package OracleDBGraph;

use strict;

use OracleDBDataWrapper;
use OracleDBDataWrapperOOP;
use Data::Dumper;
use Xorux_lib qw(error read_json);

defined $ENV{INPUTDIR} || warn "INPUTDIR undefined, config etc/lpar2rrd.cfg probably has not been loaded " && exit 1;

my $inputdir      = $ENV{INPUTDIR};
my $bindir        = $ENV{BINDIR};
my $main_data_dir = "$inputdir/data/OracleDB";
my $log_err       = "L_ERR";
my $log_err_file  = "$inputdir/html/.b";
my $log_err_v;

my $instance_names;
my $can_read;
my $ref;
my $del = "XORUX";    # delimiter, this is for rrdtool print lines for clickable legend

my $oracledbDataWrapper = OracleDBDataWrapperOOP->new();
################################################################################

sub basename {
  my $full      = shift;
  my $separator = shift;
  my $out       = "";

  #my $length = length($full);
  if ( defined $separator and defined $full and index( $full, $separator ) != -1 ) {
    $out = substr( $full, length($full) - index( reverse($full), $separator ), length($full) );
    return $out;
  }
  return $full;
}

sub get_formatted_label {
  my $label_space = shift;

  $label_space .= " " x ( 20 - length($label_space) );

  return $label_space;
}

sub get_formatted_label_val {
  my $label_space = shift;

  $label_space .= " " x ( 13 - length($label_space) );

  return $label_space;
}

sub signpost {
  my $acl_check = shift;
  my $host      = shift;
  my $server    = shift;
  my $lpar      = shift;
  my $item      = shift;
  my $colors    = shift;

  if ( $item =~ m/^oracledb_CPU_info_cpu_usage/ ) {
    return graph_cpu_usage( $acl_check, $host, $server, $lpar );
  }
  elsif ( $item =~ m/^oracledb_Session_info/ ) {
    return graph_session_info( $acl_check, $host, $server, $lpar );
  }
  elsif ( ( $host !~ m/^aggregated/ or $lpar eq "configuration_Multitenant" ) and $item =~ m/^oracledb_.*_capacity/ ) {
    return graph_capacity( $acl_check, $host, $server, $lpar );
  }
  elsif ( $item =~ m/^oracledb_.*_logratio/ ) {
    return graph_logratio( $acl_check, $host, $server, $lpar );
  }
  elsif ( $item =~ m/^oracledb_Data_rate_physical/ ) {
    return graph_dr_phys( $acl_check, $host, $server, $lpar );
  }
  elsif ( $item =~ m/^oracledb_Datarate_physical_bytes/ ) {
    return graph_dr_phys_bytes( $acl_check, $host, $server, $lpar );
  }
  elsif ( $item =~ m/^oracledb_SQL_query_user_info/ ) {
    return graph_u_info( $acl_check, $host, $server, $lpar );
  }
  elsif ( $item =~ m/^oracledb_SQL_query_cursors_info/ ) {
    return graph_c_info( $acl_check, $host, $server, $lpar );
  }
  elsif ( $item =~ m/^oracledb_Disk_latency_db_file_read/ ) {
    return graph_disk_fr_na( $acl_check, $host, $server, $lpar, $colors );
  }
  elsif ( $item =~ m/^oracledb_Disk_latency_db_file_write/ ) {
    return graph_disk_fw_na( $acl_check, $host, $server, $lpar, $colors );
  }
  elsif ( $item =~ m/^oracledb_Disk_latency_log_sync/ ) {
    return graph_disk_log_sync_na( $acl_check, $host, $server, $lpar, $colors );
  }
  elsif ( $item =~ m/^oracledb_Disk_latency_log_write/ ) {
    return graph_log_w_na( $acl_check, $host, $server, $lpar, $colors );
  }
  elsif ( $item =~ m/^oracledb_colorclick/ ) {
    return graph_aggrsingle( $acl_check, $host, $server, $lpar, $item );
  }
  elsif ( $item =~ m/^oracledb_singlehost/ ) {
    return graph_singlehost( $acl_check, $host, $server, $lpar, $item );
  }
  elsif ( $item =~ m/^oracledb/ ) {
    if ( $host =~ m/^aggregated/ ) {

      #return graph_default_aggr($host, $server, $lpar, $item, $colors);
    }
    else {
      return graph_default( $acl_check, $host, $server, $lpar, $item, $colors );
    }
  }
  else {
    return 0;
  }
}

################################################################################

sub graph_default {
  my $acl_check = shift;
  my $host      = shift;
  my $server    = shift;
  my $type      = shift;
  my $item      = shift;
  my $color     = "#FF0000";
  if ( $item =~ m/_a_/ ) {
    $color = "#";
    $color .= basename( $item, '_a_' );
    $item = substr( $item, 0, index( $item, '_a_' ) );
  }
  my $page = basename( $item, '__' );
  my $rrd;
  my $act_type_fp = $oracledbDataWrapper->get_type_from_page($page);
  $rrd = $oracledbDataWrapper->get_filepath_rrd( { type => $act_type_fp, uuid => $server, acl_check => $acl_check, id => $host } );
  my $legend = OracleDBDataWrapper::graph_legend($page);

  #my ( $header, $reduced_header ) = get_header( $type, 'Network Traffic Volume' );
  my $cmd_params = my $cmd_legend = my $cmd_cdef = my $cmd_def = my $cmd_vlabel = "";
  my $rrd_name   = $legend->{rrd_vname};

  $cmd_vlabel .= " --vertical-label=\"$legend->{v_label}\"";
  if ( $type eq "Ratio" or $item =~ /CPU_Uti/ ) {
    $cmd_params .= " --upper-limit=100";
  }
  $cmd_params .= " --lower-limit=0.00";
  if ($legend->{brackets} ne "[ms]"){
    $cmd_params .= " --units-exponent=1.00";
  }
  $cmd_def    .= " DEF:name=\"$rrd\":$rrd_name:AVERAGE";
  if ( $legend->{denom} == 1000000 ) {
    $cmd_cdef .= " CDEF:name_result=name,10000,LT,0,name,IF";
    $cmd_cdef .= " CDEF:name_div=name_result,1000000,/";
  }
  else {
    $cmd_cdef .= " CDEF:name_div=name,$legend->{denom},/";
  }
  my $label = get_formatted_label( $legend->{brackets} );
  $cmd_legend .= " COMMENT:\"$label Avrg       Max\\n\"";
  $label = "";
  $label = get_formatted_label_val( $legend->{value} );
  $cmd_legend .= " LINE1:name_div$color:\" $label\"";
  my $decimals = get_decimals($type);

  $cmd_legend .= " GPRINT:name_div:AVERAGE:\" %6.".$decimals."lf\"";
  $cmd_legend .= " GPRINT:name_div:MAX:\" %6.".$decimals."lf\"";
  $cmd_legend .= " COMMENT:\\n";

  return {
    filename => $rrd,     header   => $legend->{header}, reduced_header => "$server - $legend->{header}", cmd_params => $cmd_params,
    cmd_def  => $cmd_def, cmd_cdef => $cmd_cdef,         cmd_legend     => $cmd_legend,                   cmd_vlabel => $cmd_vlabel
  };
}

sub get_color {
  my $colors_ref = shift;
  my $col        = shift;
  my @colors     = @{$colors_ref};
  my $color;
  my $next_index = $col % $#colors;
  $color = $colors[$next_index];
}

sub get_decimals {
  my $type = shift;

  my $decimal = 1;

  if ( $type =~ /"ession|Ratio|SQL_query|CPU|Data_rate/) {
    $decimal = 0;
  }
  elsif ( $type eq "Wait_class_Main"){
    $decimal = 2; 
  }

  return $decimal;
}

sub graph_default_aggr {
  my $acl_check  = shift;
  my $host       = shift;
  my $server     = shift;
  my $type       = shift;
  my $item       = shift;
  my $colors_ref = shift;
  my $g_number   = 0;
  my @hosts      = split( /_/, $host );
  shift @hosts;
  my $page = basename( $item, '__' );
  my $rrd;
  my $legend = OracleDBDataWrapper::graph_legend($page);
  my $pdb_names;

  if ( $server ne "hostname" ) {
    ( $can_read, $ref ) = Xorux_lib::read_json("$main_data_dir/$server/instance_names.json");
    undef $instance_names;
    if ($can_read) {
      $instance_names = $ref;
    }
  }
  if ( -f "$main_data_dir/$server/pdb_names.json" ) {
    my ( $can_read_p, $ref_p ) = Xorux_lib::read_json("$main_data_dir/$server/pdb_names.json");
    if ($can_read_p) {
      $pdb_names = $ref_p;
    }
  }

  #my ( $header, $reduced_header ) = get_header( $type, 'Network Traffic Volume' );
  my $cmd_params = my $cmd_legend = my $cmd_cdef = my $cmd_def = my $cmd_vlabel = "";
  my $rrd_name   = $legend->{rrd_vname};

  $cmd_vlabel .= " --vertical-label=\"$legend->{v_label}\"";
  my $decimals = get_decimals($type);

  #$cmd_params .= " --units-exponent=1.00";
  my $cur_hos = 0;
  foreach my $cur_host (@hosts) {
    undef $rrd;
    my $color;
    my $act_type_fp = $oracledbDataWrapper->get_type_from_page($page);
    $rrd = $oracledbDataWrapper->get_filepath_rrd( { type => $act_type_fp, uuid => $server, acl_check => $acl_check, id => $cur_host } );
    $cmd_def .= " DEF:name-$cur_hos=\"$rrd\":$rrd_name:AVERAGE";
    if ( $legend->{denom} == 1000000 ) {
      $cmd_cdef .= " CDEF:name_result-$cur_hos=name-$cur_hos,10000,LT,0,name-$cur_hos,IF";
      $cmd_cdef .= " CDEF:name_div-$cur_hos=name_result-$cur_hos,1000000,/";
    }
    else {
      $cmd_cdef .= " CDEF:name_div-$cur_hos=name-$cur_hos,$legend->{denom},/";
    }

    my $instance_name = "not_found";
    my @inst_parts    = split( ",", $cur_host );
    if ( $instance_names->{$cur_host} ) {
      $instance_name = $instance_names->{$cur_host};
    }
    elsif ( $pdb_names->{$cur_host} ) {
      $instance_name = $pdb_names->{$cur_host};
    }
    elsif ( $pdb_names->{ $inst_parts[1] } ) {
      $instance_name = $pdb_names->{ $inst_parts[1] };
    }

    my $label = "";    #get_formatted_label("$instance_names->{$cur_host},Avg CR");
    if ( $legend->{graph_type} eq "LINE1" ) {
      if ( $cur_hos == 0 ) {
        $cmd_legend .= " COMMENT:\"$legend->{brackets}                          Avrg       Max\\n\"";
        $color = get_color( $colors_ref, $g_number );
        $g_number++;
        $label = get_formatted_label("$instance_name,$legend->{value}");
        $cmd_legend .= " LINE1:name_div-$cur_hos" . "$color:\" $label\"";
      }
      else {
        $cmd_legend .= " COMMENT:\\n";
        $color = get_color( $colors_ref, $g_number );
        $g_number++;
        $label = get_formatted_label("$instance_name,$legend->{value}");
        $cmd_legend .= " LINE1:name_div-$cur_hos" . "$color:\" $label\"";
      }
    }
    else {
      if ( $cur_hos == 0 ) {
        $cmd_legend .= " COMMENT:\"$legend->{brackets} " . ( ' ' x 20 ) . "Avrg      Max\\n\"";
        $color = get_color( $colors_ref, $g_number );
        $g_number++;
        $label = get_formatted_label("$instance_name,$legend->{value}");
        $cmd_legend .= " AREA:name_div-$cur_hos" . "$color:\" $label\"";
      }
      else {
        $cmd_legend .= " COMMENT:\\n";
        $color = get_color( $colors_ref, $g_number );
        $g_number++;
        $label = get_formatted_label("$instance_name,$legend->{value}");
        $cmd_legend .= " STACK:name_div-$cur_hos" . "$color:\" $label\"";
      }
    }
    $cmd_legend .= " GPRINT:name_div-$cur_hos:AVERAGE:\" %6.".$decimals."lf\"";
    $cmd_legend .= " GPRINT:name_div-$cur_hos:MAX:\" %6.".$decimals."lf\"";
    $cmd_legend .= " PRINT:name_div-$cur_hos:AVERAGE:\" %6.".$decimals."lf $del $item $del $label $del $color $del $rrd_name\"";
    $cmd_legend .= " PRINT:name_div-$cur_hos:MAX:\" %6.".$decimals."lf $del $item $del $label $del $cur_host \"";

    $cur_hos += 1;
  }
  $cmd_legend .= " COMMENT:\\n";
  return {
    filepath => $rrd,     header   => $legend->{header}, reduced_header => "$server-$legend->{header}", cmd_params => $cmd_params,
    cmd_def  => $cmd_def, cmd_cdef => $cmd_cdef,         cmd_legend     => $cmd_legend,                 cmd_vlabel => $cmd_vlabel
  };

}

sub graph_cpu_usage {
  my $acl_check = shift;
  my $host      = shift;
  my $server    = shift;
  my $type      = shift;

  my $rrd = $oracledbDataWrapper->get_filepath_rrd( { type => $type, uuid => $server, acl_check => $acl_check, id => $host } );

  #my ( $header, $reduced_header ) = get_header( $type, $uuid, 'CPU %' );

  my $cmd_params = my $cmd_legend = my $cmd_cdef = my $cmd_def = my $cmd_vlabel = "";

  $cmd_vlabel .= " --vertical-label=\"CPU Core\"";

  #  $cmd_params .= " --upper-limit=100.0";
  $cmd_params .= " --lower-limit=0.00";
  $cmd_def    .= " DEF:CPUusgPT=\"$rrd\":CPUusgPT:AVERAGE";
  $cmd_def    .= " DEF:CPUusgPS=\"$rrd\":CPUusgPS:AVERAGE";
  $cmd_cdef   .= " CDEF:CPUusgPT_v=CPUusgPT,100,/";
  $cmd_cdef   .= " CDEF:CPUusgPS_v=CPUusgPS,100,/";
  my $label = get_formatted_label("[#]");
  $cmd_legend .= " COMMENT:\"$label Avrg       Max\\n\"";
  $label = get_formatted_label_val("per txn");
  $cmd_legend .= " LINE1:CPUusgPT_v#0000FF:\"$label\"";
  $cmd_legend .= " GPRINT:CPUusgPT_v:AVERAGE:\" %6.0lf\"";
  $cmd_legend .= " GPRINT:CPUusgPT_v:MAX:\" %6.0lf\"";
  $cmd_legend .= " COMMENT:\\n";
  $label = get_formatted_label_val("per sec");
  $cmd_legend .= " LINE1:CPUusgPS_v#FF0000:\"$label\"";
  $cmd_legend .= " GPRINT:CPUusgPS_v:AVERAGE:\" %6.0lf\"";
  $cmd_legend .= " GPRINT:CPUusgPS_v:MAX:\" %6.0lf\"";

  $cmd_legend .= " COMMENT:\\n";

  return {
    filename => $rrd,     header   => "CPU Core Usage", reduced_header => "$server - CPU Core Usage", cmd_params => $cmd_params,
    cmd_def  => $cmd_def, cmd_cdef => $cmd_cdef,        cmd_legend     => $cmd_legend,                cmd_vlabel => $cmd_vlabel
  };
}

sub graph_session_info {
  my $acl_check = shift;
  my $host      = shift;
  my $server    = shift;
  my $type      = shift;

  my $rrd = $oracledbDataWrapper->get_filepath_rrd( { type => $type, uuid => $server, acl_check => $acl_check, id => $host } );

  #my ( $header, $reduced_header ) = get_header( $type, $uuid, 'CPU %' );

  my $cmd_params = my $cmd_legend = my $cmd_cdef = my $cmd_def = my $cmd_vlabel = "";

  $cmd_vlabel .= " --vertical-label=\"Session info\"";
  $cmd_params .= " --lower-limit=0.00";
  $cmd_def    .= " DEF:CrntLgnsCnt=\"$rrd\":CrntLgnsCnt:AVERAGE";
  $cmd_def    .= " DEF:LgnsPS=\"$rrd\":LgnsPS:AVERAGE";
  my $label = get_formatted_label("");
  if ( $type ne "Session_info_PDB" ) {
    $cmd_def    .= " DEF:AvgActSsion=\"$rrd\":AvgActSsion:AVERAGE";
    $cmd_def    .= " DEF:ActSrlSsion=\"$rrd\":ActSrlSsion:AVERAGE";
    $cmd_def    .= " DEF:ActPrllSsion=\"$rrd\":ActPrllSsion:AVERAGE";
    $cmd_legend .= " COMMENT:\"$label        Avrg       Max\\n\"";
    $label = get_formatted_label_val("avg active sessions");
    $cmd_legend .= " LINE1:AvgActSsion#00FF00:\"$label \"";
    $cmd_legend .= " GPRINT:AvgActSsion:AVERAGE:\" %6.0lf\"";
    $cmd_legend .= " GPRINT:AvgActSsion:MAX:\" %6.0lf\"";
    $cmd_legend .= " COMMENT:\\n";
    $label = get_formatted_label_val("actv serial sessions");
    $cmd_legend .= " LINE1:ActSrlSsion#0080FF:\"$label\"";
    $cmd_legend .= " GPRINT:ActSrlSsion:AVERAGE:\" %6.0lf\"";
    $cmd_legend .= " GPRINT:ActSrlSsion:MAX:\" %6.0lf\"";
    $cmd_legend .= " COMMENT:\\n";
    $label = get_formatted_label_val("actv paralel sessions");
    $cmd_legend .= " LINE1:ActPrllSsion#FF0000:\"$label\"";
    $cmd_legend .= " GPRINT:ActPrllSsion:AVERAGE:\"%6.0lf\"";
    $cmd_legend .= " GPRINT:ActPrllSsion:MAX:\" %6.0lf\"";
    $cmd_legend .= " COMMENT:\\n";
  }
  $label = get_formatted_label_val("current Logons count");
  $cmd_legend .= " LINE1:CrntLgnsCnt#FFe119:\"$label \"";
  $cmd_legend .= " GPRINT:CrntLgnsCnt:AVERAGE:\" %6.0lf\"";
  $cmd_legend .= " GPRINT:CrntLgnsCnt:MAX:\" %6.0lf\"";
  $cmd_legend .= " COMMENT:\\n";
  $label = get_formatted_label_val("Logons per second");
  $cmd_legend .= " LINE1:LgnsPS#911ef4:\"$label   \"";
  $cmd_legend .= " GPRINT:LgnsPS:AVERAGE:\" %6.0lf\"";
  $cmd_legend .= " GPRINT:LgnsPS:MAX:\" %6.0lf\"";
  $cmd_legend .= " COMMENT:\\n";

  return {
    filename => $rrd,     header   => "Session info", reduced_header => "$server - Session info", cmd_params => $cmd_params,
    cmd_def  => $cmd_def, cmd_cdef => $cmd_cdef,      cmd_legend     => $cmd_legend,              cmd_vlabel => $cmd_vlabel
  };
}

sub graph_dr_phys {
  my $acl_check = shift;
  my $host      = shift;
  my $server    = shift;
  my $type      = shift;

  my $rrd = $oracledbDataWrapper->get_filepath_rrd( { type => $type, uuid => $server, acl_check => $acl_check, id => $host } );

  #my ( $header, $reduced_header ) = get_header( $type, $uuid, 'CPU %' );

  my $cmd_params = my $cmd_legend = my $cmd_cdef = my $cmd_def = my $cmd_vlabel = "";

  $cmd_vlabel .= " --vertical-label=\"Physical Read and Write\"";
  $cmd_def    .= " DEF:read=\"$rrd\":PhysReadPS:AVERAGE";
  $cmd_def    .= " DEF:write=\"$rrd\":PhysWritePS:AVERAGE";
  $cmd_cdef   .= " CDEF:read_graph=0,read,-";
  my $label = get_formatted_label("[IOPS]");
  $cmd_legend .= " COMMENT:\"$label Avrg     Max\\n\"";
  $label = get_formatted_label_val("Write");
  $cmd_legend .= " LINE1:write#0080FF:\"$label\"";
  $cmd_legend .= " GPRINT:write:AVERAGE:\" %6.0lf\"";
  $cmd_legend .= " GPRINT:write:MAX:\" %6.0lf\"";
  $cmd_legend .= " COMMENT:\\n";
  $label = get_formatted_label_val("Read");
  $cmd_legend .= " LINE1:read_graph#00FF00:\"$label\"";
  $cmd_legend .= " GPRINT:read:AVERAGE:\" %6.0lf\"";
  $cmd_legend .= " GPRINT:read:MAX:\" %6.0lf\"";
  $cmd_legend .= " COMMENT:\\n";

  return {
    filename => $rrd,     header   => "Physical", reduced_header => "$server - Physical", cmd_params => $cmd_params,
    cmd_def  => $cmd_def, cmd_cdef => $cmd_cdef,  cmd_legend     => $cmd_legend,          cmd_vlabel => $cmd_vlabel
  };
}

sub graph_dr_phys_bytes {
  my $acl_check = shift;
  my $host      = shift;
  my $server    = shift;
  my $type      = shift;

  my $rrd = $oracledbDataWrapper->get_filepath_rrd( { type => $type, uuid => $server, acl_check => $acl_check, id => $host } );

  #my ( $header, $reduced_header ) = get_header( $type, $uuid, 'CPU %' );

  my $cmd_params = my $cmd_legend = my $cmd_cdef = my $cmd_def = my $cmd_vlabel = "";

  $cmd_vlabel .= " --vertical-label=\"Physical Read and Write\"";

  $cmd_def  .= " DEF:read=\"$rrd\":PhysReadBPS:AVERAGE";
  $cmd_def  .= " DEF:write=\"$rrd\":PhysWriteBPS:AVERAGE";
  $cmd_cdef .= " CDEF:w_result=write,10000,LT,0,write,IF";
  $cmd_cdef .= " CDEF:write_b=w_result,1000000,/";

  $cmd_cdef .= " CDEF:r_result=read,10000,LT,0,read,IF";
  $cmd_cdef .= " CDEF:read_b=r_result,1000000,/";
  my $label = get_formatted_label("[MB/sec]");
  $cmd_legend .= " COMMENT:\"$label Avrg     Max\\n\"";
  $label = get_formatted_label_val("Write");
  $cmd_cdef   .= " CDEF:read_b_graph=0,read_b,-";
  $cmd_legend .= " LINE1:write_b#0080FF:\"$label\"";
  $cmd_legend .= " GPRINT:write_b:AVERAGE:\" %6.2lf\"";
  $cmd_legend .= " GPRINT:write_b:MAX:\" %6.2lf\"";
  $cmd_legend .= " COMMENT:\\n";
  $label = get_formatted_label_val("Read");
  $cmd_legend .= " LINE1:read_b_graph#00FF00:\"$label\"";
  $cmd_legend .= " GPRINT:read_b:AVERAGE:\" %6.2lf\"";
  $cmd_legend .= " GPRINT:read_b:MAX:\" %6.2lf\"";
  $cmd_legend .= " COMMENT:\\n";

  return {
    filename => $rrd,     header   => "Physical data", reduced_header => "$server - Physical data", cmd_params => $cmd_params,
    cmd_def  => $cmd_def, cmd_cdef => $cmd_cdef,       cmd_legend     => $cmd_legend,               cmd_vlabel => $cmd_vlabel
  };
}

sub graph_user_info {
  my $acl_check  = shift;
  my $host       = shift;
  my $server     = shift;
  my $type       = shift;
  my $item       = shift;
  my $colors_ref = shift;
  my $color;
  my $g_number = 0;
  my @hosts    = split( /_/, $host );
  shift @hosts;
  my $rrd;

  if ( -f "$main_data_dir/$server/pdb_names.json" ) {
    ( $can_read, $ref ) = Xorux_lib::read_json("$main_data_dir/$server/instance_names.json");
    undef $instance_names;
    if ($can_read) {
      $instance_names = $ref;
    }
  }
  my $pdb_names;
  if ( -f "$main_data_dir/$server/pdb_names.json" ) {
    my ( $can_read_p, $ref_p ) = Xorux_lib::read_json("$main_data_dir/$server/pdb_names.json");
    if ($can_read_p) {
      $pdb_names = $ref_p;
    }
  }

  #my ( $header, $reduced_header ) = get_header( $type, 'Network Traffic Volume' );
  my $cmd_params = my $cmd_legend = my $cmd_cdef = my $cmd_def = my $cmd_vlabel = "";

  my $cur_hos = 0;
  $cmd_vlabel .= " --vertical-label=\"Blocks per second\"";
  $cmd_params .= " --lower-limit=0.00";
  $cmd_legend .= " COMMENT:\\n";

  foreach my $cur_host (@hosts) {
    undef $rrd;
    $rrd = $oracledbDataWrapper->get_filepath_rrd( { type => $type, uuid => $server, acl_check => $acl_check, id => $cur_host } );
    $cmd_def .= " DEF:OpnCrsPS-$cur_hos=\"$rrd\":UsrTxnPS:AVERAGE";
    $cmd_def .= " DEF:CntOpnCrs-$cur_hos=\"$rrd\":UsrComtsPS:AVERAGE";

    #    if($cur_hos == 0){
    #      $cmd_legend .= " COMMENT:\"[#]                          Avrg      Max\\n\"";
    #    }else{
    #      $cmd_legend .= " COMMENT:\\n";
    #    }
    $color = get_color( $colors_ref, $g_number );
    $g_number++;
    my $ins;
    if ( $instance_names->{$cur_host} ) {
      $ins = $instance_names->{$cur_host};
    }
    else {
      $ins = $pdb_names->{$cur_host};
    }
    my $label = "$ins,user transactions/s";
    $cmd_legend .= " LINE1:OpnCrsPS-$cur_hos" . "$color:\" $label     \"";
    $cmd_legend .= " GPRINT:OpnCrsPS-$cur_hos:AVERAGE:\" %6.0lf\"";
    $cmd_legend .= " GPRINT:OpnCrsPS-$cur_hos:MAX:\" %6.0lf\"";
    $cmd_legend .= " PRINT:OpnCrsPS-$cur_hos:AVERAGE:\" %6.0lf $del $item $del $label $del $color $del User_Transaction_Per_Sec\"";
    $cmd_legend .= " PRINT:OpnCrsPS-$cur_hos:MAX:\" %6.0lf $del asd $del $label $del $cur_host\"";

    $cmd_legend .= " COMMENT:\\n";

    #$cmd_legend_t .= " COMMENT:\\n";
    $color = get_color( $colors_ref, $g_number );
    $g_number++;
    $label = "$ins,user commits/s";
    $cmd_legend .= " LINE1:CntOpnCrs-$cur_hos" . "$color:\" $label    \"";
    $cmd_legend .= " GPRINT:CntOpnCrs-$cur_hos:AVERAGE:\" %6.0lf\"";
    $cmd_legend .= " GPRINT:CntOpnCrs-$cur_hos:MAX:\" %6.0lf\"";
    $cmd_legend .= " PRINT:CntOpnCrs-$cur_hos:AVERAGE:\" %6.0lf $del $item $del $label $del $color $del User_Commits_Per_Sec\"";
    $cmd_legend .= " PRINT:CntOpnCrs-$cur_hos:MAX:\" %6.0lf $del asd $del $label $del $cur_host\"";

    $cmd_legend .= " COMMENT:\\n";

    $cur_hos += 1;
  }

  #$cmd_legend .= " COMMENT:\\n";

  return {
    filepath => $rrd,     header   => "Cursors info", reduced_header => "Cursors info", cmd_params => $cmd_params,
    cmd_def  => $cmd_def, cmd_cdef => $cmd_cdef,      cmd_legend     => $cmd_legend,    cmd_vlabel => $cmd_vlabel
  };
}

sub graph_u_info {
  my $acl_check = shift;
  my $host      = shift;
  my $server    = shift;
  my $type      = shift;

  my $rrd = $oracledbDataWrapper->get_filepath_rrd( { type => $type, uuid => $server, acl_check => $acl_check, id => $host } );

  #my ( $header, $reduced_header ) = get_header( $type, $uuid, 'CPU %' );

  my $cmd_params = my $cmd_legend = my $cmd_cdef = my $cmd_def = my $cmd_vlabel = "";

  $cmd_vlabel .= " --vertical-label=\"User info\"";
  $cmd_params .= " --lower-limit=0.00";
  $cmd_def    .= " DEF:UsrTxnPS=\"$rrd\":UsrTxnPS:AVERAGE";
  $cmd_def    .= " DEF:UsrComtsPS=\"$rrd\":UsrComtsPS:AVERAGE";
  my $label = get_formatted_label("[#]");
  $cmd_legend .= " COMMENT:\"$label      Avrg      Max\\n\"";
  $label = get_formatted_label_val("user transactions/s");
  $cmd_legend .= " LINE1:UsrTxnPS#0080FF:\"$label\"";
  $cmd_legend .= " GPRINT:UsrTxnPS:AVERAGE:\" %6.0lf\"";
  $cmd_legend .= " GPRINT:UsrTxnPS:MAX:\" %6.0lf\"";
  $cmd_legend .= " COMMENT:\\n";
  $label = get_formatted_label_val("users commits/s");
  $cmd_legend .= " LINE1:UsrComtsPS#00FF00:\"$label   \"";
  $cmd_legend .= " GPRINT:UsrComtsPS:AVERAGE:\" %6.0lf\"";
  $cmd_legend .= " GPRINT:UsrComtsPS:MAX:\" %6.0lf\"";

  $cmd_legend .= " COMMENT:\\n";

  return {
    filename => $rrd,     header   => "User info", reduced_header => "$server - User info", cmd_params => $cmd_params,
    cmd_def  => $cmd_def, cmd_cdef => $cmd_cdef,   cmd_legend     => $cmd_legend,           cmd_vlabel => $cmd_vlabel
  };
}

sub graph_cursors_info {
  my $acl_check  = shift;
  my $host       = shift;
  my $server     = shift;
  my $type       = shift;
  my $item       = shift;
  my $colors_ref = shift;
  my $color;
  my $g_number = 0;
  my @hosts    = split( /_/, $host );
  shift @hosts;
  my $rrd;
  ( $can_read, $ref ) = Xorux_lib::read_json("$main_data_dir/$server/instance_names.json");
  undef $instance_names;

  if ($can_read) {
    $instance_names = $ref;
  }
  my $pdb_names;
  if ( -f "$main_data_dir/$server/pdb_names.json" ) {
    my ( $can_read_p, $ref_p ) = Xorux_lib::read_json("$main_data_dir/$server/pdb_names.json");
    if ($can_read_p) {
      $pdb_names = $ref_p;
    }
  }

  #my ( $header, $reduced_header ) = get_header( $type, 'Network Traffic Volume' );
  my $cmd_params = my $cmd_legend = my $cmd_cdef = my $cmd_def = my $cmd_vlabel = "";

  my $cur_hos = 0;
  $cmd_vlabel .= " --vertical-label=\"Blocks per second\"";
  $cmd_params .= " --lower-limit=0.00";
  $cmd_legend .= " COMMENT:\\n";

  foreach my $cur_host (@hosts) {
    undef $rrd;
    $rrd = $oracledbDataWrapper->get_filepath_rrd( { type => $type, uuid => $server, acl_check => $acl_check, id => $cur_host } );
    $cmd_def .= " DEF:OpnCrsPS-$cur_hos=\"$rrd\":OpnCrsPS:AVERAGE";
    $cmd_def .= " DEF:CntOpnCrs-$cur_hos=\"$rrd\":CntOpnCrs:AVERAGE";

    #    if($cur_hos == 0){
    #      $cmd_legend .= " COMMENT:\"[#]                          Avrg      Max\\n\"";
    #    }else{
    #      $cmd_legend .= " COMMENT:\\n";
    #    }
    $color = get_color( $colors_ref, $g_number );
    $g_number++;
    my $ins;
    if ( $instance_names->{$cur_host} ) {
      $ins = $instance_names->{$cur_host};
    }
    else {
      $ins = $pdb_names->{$cur_host};
    }
    my $label = "$ins,open cursors/s";
    $cmd_legend .= " LINE1:OpnCrsPS-$cur_hos" . "$color:\" $label     \"";
    $cmd_legend .= " GPRINT:OpnCrsPS-$cur_hos:AVERAGE:\" %6.0lf\"";
    $cmd_legend .= " GPRINT:OpnCrsPS-$cur_hos:MAX:\" %6.0lf\"";
    $cmd_legend .= " PRINT:OpnCrsPS-$cur_hos:AVERAGE:\" %6.0lf $del $item $del $label $del $color $del Open_Cursors_Per_Sec\"";
    $cmd_legend .= " PRINT:OpnCrsPS-$cur_hos:MAX:\" %6.0lf $del asd $del $label $del $cur_host\"";

    $cmd_legend .= " COMMENT:\\n";

    #$cmd_legend_t .= " COMMENT:\\n";
    $color = get_color( $colors_ref, $g_number );
    $g_number++;
    $label = "$ins,urrent open cursors";
    $cmd_legend .= " LINE1:CntOpnCrs-$cur_hos" . "$color:\" $label    \"";
    $cmd_legend .= " GPRINT:CntOpnCrs-$cur_hos:AVERAGE:\" %6.0lf\"";
    $cmd_legend .= " GPRINT:CntOpnCrs-$cur_hos:MAX:\" %6.0lf\"";
    $cmd_legend .= " PRINT:CntOpnCrs-$cur_hos:AVERAGE:\" %6.0lf $del $item $del $label $del $color $del Current_Open_Cursors_Count\"";
    $cmd_legend .= " PRINT:CntOpnCrs-$cur_hos:MAX:\" %6.0lf $del asd $del $label $del $cur_host\"";

    $cmd_legend .= " COMMENT:\\n";

    $cur_hos += 1;
  }

  #$cmd_legend .= " COMMENT:\\n";

  return {
    filepath => $rrd,     header   => "Cursors info", reduced_header => "$server - Cursors info", cmd_params => $cmd_params,
    cmd_def  => $cmd_def, cmd_cdef => $cmd_cdef,      cmd_legend     => $cmd_legend,              cmd_vlabel => $cmd_vlabel
  };
}

sub graph_c_info {
  my $acl_check = shift;
  my $host      = shift;
  my $server    = shift;
  my $type      = shift;

  my $rrd = $oracledbDataWrapper->get_filepath_rrd( { type => $type, uuid => $server, acl_check => $acl_check, id => $host } );

  #my ( $header, $reduced_header ) = get_header( $type, $uuid, 'CPU %' );

  my $cmd_params = my $cmd_legend = my $cmd_cdef = my $cmd_def = my $cmd_vlabel = "";

  $cmd_vlabel .= " --vertical-label=\"Cursors info\"";
  $cmd_params .= " --lower-limit=0.00";
  $cmd_def    .= " DEF:OpnCrsPS=\"$rrd\":OpnCrsPS:AVERAGE";
  $cmd_def    .= " DEF:CntOpnCrs=\"$rrd\":CntOpnCrs:AVERAGE";
  $cmd_legend .= " COMMENT:\"[#]                         Avrg       Max\\n\"";
  $cmd_legend .= " LINE1:OpnCrsPS#0080FF:\" open cursors/s      \"";
  $cmd_legend .= " GPRINT:OpnCrsPS:AVERAGE:\" %6.0lf\"";
  $cmd_legend .= " GPRINT:OpnCrsPS:MAX:\" %6.0lf\"";
  $cmd_legend .= " COMMENT:\\n";
  $cmd_legend .= " LINE1:CntOpnCrs#00FF00:\" current open cursors \"";
  $cmd_legend .= " GPRINT:CntOpnCrs:AVERAGE:\" %6.0lf\"";
  $cmd_legend .= " GPRINT:CntOpnCrs:MAX:\" %6.0lf\"";

  $cmd_legend .= " COMMENT:\\n";

  return {
    filename => $rrd,     header   => "Cursors info", reduced_header => "$server - Cursors info", cmd_params => $cmd_params,
    cmd_def  => $cmd_def, cmd_cdef => $cmd_cdef,      cmd_legend     => $cmd_legend,              cmd_vlabel => $cmd_vlabel
  };
}

sub graph_cache {
  my $acl_check  = shift;
  my $host       = shift;
  my $server     = shift;
  my $type       = shift;
  my $item       = shift;
  my $colors_ref = shift;
  my $color;
  my $g_number = 0;
  my @hosts    = split( /_/, $host );
  shift @hosts;
  my $rrd;
  ( $can_read, $ref ) = Xorux_lib::read_json("$main_data_dir/$server/instance_names.json");
  undef $instance_names;

  if ($can_read) {
    $instance_names = $ref;
  }

  #my ( $header, $reduced_header ) = get_header( $type, 'Network Traffic Volume' );
  my $cmd_params = my $cmd_legend = my $cmd_cdef = my $cmd_def = my $cmd_vlabel = "";

  my $cur_hos = 0;
  $cmd_vlabel .= " --vertical-label=\"Milliseconds per wait\"";
  $cmd_params .= " --units-exponent=0";
  $cmd_params .= " --lower-limit=0.00";
  $cmd_legend .= " COMMENT:\\n";

  foreach my $cur_host (@hosts) {
    undef $rrd;
    $rrd = $oracledbDataWrapper->get_filepath_rrd( { type => $type, uuid => $server, acl_check => $acl_check, id => $cur_host } );
    $cmd_def .= " DEF:CntOpnCrs-$cur_hos=\"$rrd\":GCAvgCRGtTm:AVERAGE";
    $cmd_def .= " DEF:OpnCrsPS-$cur_hos=\"$rrd\":GCAvgCtGtTm:AVERAGE";

    #    if($cur_hos == 0){
    #      $cmd_legend .= " COMMENT:\"[#]                          Avrg      Max\\n\"";
    #    }else{
    #      $cmd_legend .= " COMMENT:\\n";
    #    }
    $color = get_color( $colors_ref, $g_number );
    $g_number++;
    my $label = "$instance_names->{$cur_host},GC Average Current Get Time";
    $cmd_legend .= " LINE1:OpnCrsPS-$cur_hos" . "$color:\" $label     \"";
    $cmd_legend .= " GPRINT:OpnCrsPS-$cur_hos:AVERAGE:\" %6.2lf\"";
    $cmd_legend .= " GPRINT:OpnCrsPS-$cur_hos:MAX:\" %6.2lf\"";
    $cmd_legend .= " PRINT:OpnCrsPS-$cur_hos:AVERAGE:\" %6.2lf $del $item $del $label $del $color $del Global_Cache_Average_Current_Get_Time\"";
    $cmd_legend .= " PRINT:OpnCrsPS-$cur_hos:MAX:\" %6.2lf $del asd $del $label $del $cur_host\"";

    $cmd_legend .= " COMMENT:\\n";

    #$cmd_legend_t .= " COMMENT:\\n";
    $color = get_color( $colors_ref, $g_number );
    $g_number++;
    $label = "$instance_names->{$cur_host},GC Average CR Get Time";
    $cmd_legend .= " LINE1:CntOpnCrs-$cur_hos" . "$color:\" $label    \"";
    $cmd_legend .= " GPRINT:CntOpnCrs-$cur_hos:AVERAGE:\" %6.2lf\"";
    $cmd_legend .= " GPRINT:CntOpnCrs-$cur_hos:MAX:\" %6.2lf\"";
    $cmd_legend .= " PRINT:CntOpnCrs-$cur_hos:AVERAGE:\" %6.2lf $del $item $del $label $del $color $del Global_Cache_Average_CR_Get_Time\"";
    $cmd_legend .= " PRINT:CntOpnCrs-$cur_hos:MAX:\" %6.2lf $del asd $del $label $del $cur_host\"";

    $cmd_legend .= " COMMENT:\\n";

    $cur_hos += 1;
  }

  #$cmd_legend .= " COMMENT:\\n";

  return {
    filepath => $rrd,     header   => "Cursors info", reduced_header => "Cursors info", cmd_params => $cmd_params,
    cmd_def  => $cmd_def, cmd_cdef => $cmd_cdef,      cmd_legend     => $cmd_legend,    cmd_vlabel => $cmd_vlabel
  };
}

sub graph_blocksrec {
  my $acl_check  = shift;
  my $host       = shift;
  my $server     = shift;
  my $type       = shift;
  my $item       = shift;
  my $colors_ref = shift;
  my $color;
  my $g_number = 0;
  my @hosts    = split( /_/, $host );
  shift @hosts;
  my $rrd;
  ( $can_read, $ref ) = Xorux_lib::read_json("$main_data_dir/$server/instance_names.json");
  undef $instance_names;

  if ($can_read) {
    $instance_names = $ref;
  }

  #my ( $header, $reduced_header ) = get_header( $type, 'Network Traffic Volume' );
  my $cmd_params = my $cmd_legend = my $cmd_cdef = my $cmd_def = my $cmd_vlabel = "";

  my $cur_hos = 0;
  $cmd_vlabel .= " --vertical-label=\"Blocks per second\"";
  $cmd_params .= " --lower-limit=0.00";
  $cmd_legend .= " COMMENT:\\n";

  foreach my $cur_host (@hosts) {
    undef $rrd;
    $rrd = $oracledbDataWrapper->get_filepath_rrd( { type => $type, uuid => $server, acl_check => $acl_check, id => $cur_host } );
    $cmd_def .= " DEF:OpnCrsPS-$cur_hos=\"$rrd\":GCCRBlckRcPS:AVERAGE";
    $cmd_def .= " DEF:CntOpnCrs-$cur_hos=\"$rrd\":GCCtBlckRcPS:AVERAGE";

    #    if($cur_hos == 0){
    #      $cmd_legend .= " COMMENT:\"[#]                          Avrg      Max\\n\"";
    #    }else{
    #      $cmd_legend .= " COMMENT:\\n";
    #    }
    $color = get_color( $colors_ref, $g_number );
    $g_number++;
    my $label = "$instance_names->{$cur_host},GC CR Block Received Per Second";
    $cmd_legend .= " LINE1:OpnCrsPS-$cur_hos" . "$color:\" $label     \"";
    $cmd_legend .= " GPRINT:OpnCrsPS-$cur_hos:AVERAGE:\" %6.1lf\"";
    $cmd_legend .= " GPRINT:OpnCrsPS-$cur_hos:MAX:\" %6.1lf\"";
    $cmd_legend .= " PRINT:OpnCrsPS-$cur_hos:AVERAGE:\" %6.1lf $del $item $del $label $del $color $del GC_CR_Block_Received_Per_Second\"";
    $cmd_legend .= " PRINT:OpnCrsPS-$cur_hos:MAX:\" %6.1lf $del asd $del $label $del $cur_host\"";

    $cmd_legend .= " COMMENT:\\n";

    #$cmd_legend_t .= " COMMENT:\\n";
    $color = get_color( $colors_ref, $g_number );
    $g_number++;
    $label = "$instance_names->{$cur_host},GC Current Block Received Per Second";
    $cmd_legend .= " LINE1:CntOpnCrs-$cur_hos" . "$color:\" $label    \"";
    $cmd_legend .= " GPRINT:CntOpnCrs-$cur_hos:AVERAGE:\" %6.1lf\"";
    $cmd_legend .= " GPRINT:CntOpnCrs-$cur_hos:MAX:\" %6.1lf\"";
    $cmd_legend .= " PRINT:CntOpnCrs-$cur_hos:AVERAGE:\" %6.1lf $del $item $del $label $del $color $del GC_Current_Block_Received_Per_Second\"";
    $cmd_legend .= " PRINT:CntOpnCrs-$cur_hos:MAX:\" %6.1lf $del asd $del $label $del $cur_host\"";

    $cmd_legend .= " COMMENT:\\n";

    $cur_hos += 1;
  }

  #$cmd_legend .= " COMMENT:\\n";

  return {
    filepath => $rrd,     header   => "Cursors info", reduced_header => "Cursors info", cmd_params => $cmd_params,
    cmd_def  => $cmd_def, cmd_cdef => $cmd_cdef,      cmd_legend     => $cmd_legend,    cmd_vlabel => $cmd_vlabel
  };
}

sub graph_avgblockrec {
  my $acl_check  = shift;
  my $host       = shift;
  my $server     = shift;
  my $type       = shift;
  my $item       = shift;
  my $colors_ref = shift;
  my $color;
  my $g_number = 0;
  my @hosts    = split( /_/, $host );
  shift @hosts;
  my $rrd;
  ( $can_read, $ref ) = Xorux_lib::read_json("$main_data_dir/$server/instance_names.json");
  undef $instance_names;

  if ($can_read) {
    $instance_names = $ref;
  }

  #my ( $header, $reduced_header ) = get_header( $type, 'Network Traffic Volume' );
  my $cmd_params = my $cmd_legend = my $cmd_cdef = my $cmd_def = my $cmd_vlabel = "";

  my $cur_hos = 0;
  $cmd_vlabel .= " --vertical-label=\"Physical Read and Write\"";
  $cmd_params .= " --lower-limit=0.00";
  $cmd_legend .= " COMMENT:\\n";

  foreach my $cur_host (@hosts) {
    undef $rrd;
    $rrd = $oracledbDataWrapper->get_filepath_rrd( { type => $type, uuid => $server, acl_check => $acl_check, id => $cur_host } );
    $cmd_def .= " DEF:OpnCrsPS-$cur_hos=\"$rrd\":AvgCRBlkrc:AVERAGE";
    $cmd_def .= " DEF:CntOpnCrs-$cur_hos=\"$rrd\":AvgCURBlkrc:AVERAGE";

    #    if($cur_hos == 0){
    #      $cmd_legend .= " COMMENT:\"[#]                          Avrg      Max\\n\"";
    #    }else{
    #      $cmd_legend .= " COMMENT:\\n";
    #    }
    $color = get_color( $colors_ref, $g_number );
    $g_number++;
    my $label = "$instance_names->{$cur_host},GC Avg CR Block receive ms";
    $cmd_legend .= " LINE1:OpnCrsPS-$cur_hos" . "$color:\" $label     \"";
    $cmd_legend .= " GPRINT:OpnCrsPS-$cur_hos:AVERAGE:\" %6.1lf\"";
    $cmd_legend .= " GPRINT:OpnCrsPS-$cur_hos:MAX:\" %6.1lf\"";
    $cmd_legend .= " PRINT:OpnCrsPS-$cur_hos:AVERAGE:\" %6.1lf $del $item $del $label $del $color $del GC_Avg_CR_Block_receive_ms\"";
    $cmd_legend .= " PRINT:OpnCrsPS-$cur_hos:MAX:\" %6.1lf $del asd $del $label $del $cur_host\"";

    $cmd_legend .= " COMMENT:\\n";

    #$cmd_legend_t .= " COMMENT:\\n";
    $color = get_color( $colors_ref, $g_number );
    $g_number++;
    $label = "$instance_names->{$cur_host},GC Avg CUR Block receive ms";
    $cmd_legend .= " LINE1:CntOpnCrs-$cur_hos" . "$color:\" $label    \"";
    $cmd_legend .= " GPRINT:CntOpnCrs-$cur_hos:AVERAGE:\" %6.1lf\"";
    $cmd_legend .= " GPRINT:CntOpnCrs-$cur_hos:MAX:\" %6.1lf\"";
    $cmd_legend .= " PRINT:CntOpnCrs-$cur_hos:AVERAGE:\" %6.1lf $del $item $del $label $del $color $del GC_Avg_CUR_Block_receive_ms\"";
    $cmd_legend .= " PRINT:CntOpnCrs-$cur_hos:MAX:\" %6.1lf $del asd $del $label $del $cur_host\"";

    $cmd_legend .= " COMMENT:\\n";

    $cur_hos += 1;
  }

  #$cmd_legend .= " COMMENT:\\n";

  return {
    filepath => $rrd,     header   => "Cursors info", reduced_header => "reduced_header", cmd_params => $cmd_params,
    cmd_def  => $cmd_def, cmd_cdef => $cmd_cdef,      cmd_legend     => $cmd_legend,      cmd_vlabel => $cmd_vlabel
  };
}

sub graph_disk_fw_na {
  my $acl_check = shift;
  my $host      = shift;
  my $server    = shift;
  my $type      = shift;

  my $rrd = $oracledbDataWrapper->get_filepath_rrd( { type => $type, uuid => $server, acl_check => $acl_check, id => $host } );

  #my ( $header, $reduced_header ) = get_header( $type, $uuid, 'CPU %' );

  my $cmd_params = my $cmd_legend = my $cmd_cdef = my $cmd_def = my $cmd_vlabel = "";

  $cmd_vlabel .= " --vertical-label=\"Milliseconds\"";
  $cmd_params .= " --units-exponent=0";
  $cmd_params .= " --lower-limit=0.00";
  $cmd_def    .= " DEF:OpnCrsPS=\"$rrd\":flsnglw:AVERAGE";
  $cmd_def    .= " DEF:CntOpnCrs=\"$rrd\":flprlllw:AVERAGE";
  $cmd_legend .= " COMMENT:\"[ms]                Avrg       Max\\n\"";
  $cmd_legend .= " LINE1:OpnCrsPS#FF0000:\"db file single write\"";
  $cmd_legend .= " GPRINT:OpnCrsPS:AVERAGE:\" %6.2lf\"";
  $cmd_legend .= " GPRINT:OpnCrsPS:MAX:\" %6.2lf\"";
  $cmd_legend .= " COMMENT:\\n";
  $cmd_legend .= " LINE1:CntOpnCrs#0000FF:\"db file parallel write\"";
  $cmd_legend .= " GPRINT:CntOpnCrs:AVERAGE:\" %6.2lf\"";
  $cmd_legend .= " GPRINT:CntOpnCrs:MAX:\" %6.2lf\"";

  $cmd_legend .= " COMMENT:\\n";

  return {
    filename => $rrd,     header   => "db file write", reduced_header => "$server - db file write", cmd_params => $cmd_params,
    cmd_def  => $cmd_def, cmd_cdef => $cmd_cdef,       cmd_legend     => $cmd_legend,               cmd_vlabel => $cmd_vlabel
  };
}

sub graph_logratio {
  my $acl_check = shift;
  my $host      = shift;
  my $server    = shift;
  my $type      = shift;

  #my $rrd  = $oracledbDataWrapper->get_filepath_rrd({type => $type, uuid => $server, id => $host});
  my $rrd_two = $oracledbDataWrapper->get_filepath_rrd( { type => $type, uuid => $server, acl_check => $acl_check, id => $host } );
  $rrd_two =~ s/-Capacity\.rrd/-Cpct\.rrd/g;

  #my ( $header, $reduced_header ) = get_header( $type, $uuid, 'CPU %' );

  my $cmd_params = my $cmd_legend = my $cmd_cdef = my $cmd_def = my $cmd_vlabel = "";

  $cmd_vlabel .= " --vertical-label=\"Gibibytes\"";
  $cmd_params .= " --lower-limit=0.00";
  $cmd_def    .= " DEF:log=\"$rrd_two\":recoveryused:AVERAGE";
  $cmd_def    .= " DEF:total=\"$rrd_two\":recoverysize:AVERAGE";
  $cmd_cdef   .= " CDEF:prcnt=log,total,/,100,*";

  #
  my $label = "";
  $cmd_legend .= " COMMENT:\"[GiB]                Avrg      Max       % \\n\"";
  $label = get_formatted_label_val("Logs");
  $cmd_legend .= " LINE1:log#FF0000:\"$label\"";
  $cmd_legend .= " GPRINT:log:AVERAGE:\" %6.0lf\"";
  $cmd_legend .= " GPRINT:log:MAX:\" %6.0lf\"";
  $cmd_legend .= " GPRINT:prcnt:AVERAGE:\" %6.0lf\"";
  $cmd_legend .= " COMMENT:\\n";
  $label = get_formatted_label_val("Total");
  $cmd_legend .= " LINE1:total#000000:\"$label\"";
  $cmd_legend .= " GPRINT:total:AVERAGE:\" %6.0lf\"";
  $cmd_legend .= " GPRINT:total:MAX:\" %6.0lf\"";

  $cmd_legend .= " COMMENT:\\n";

  return {
    filename => $rrd_two, header   => "Recovery File Destination Usage", reduced_header => "$server - Recovery file usage", cmd_params => $cmd_params,
    cmd_def  => $cmd_def, cmd_cdef => $cmd_cdef,                         cmd_legend     => $cmd_legend,                     cmd_vlabel => $cmd_vlabel
  };
}

sub graph_capacity {
  my $acl_check = shift;
  my $host      = shift;
  my $server    = shift;
  my $type      = shift;
  if ( $host =~ /groups_/ ) {
    my $instance = $host;
    $instance =~ s/groups_//g;
    $host = "$instance";
  }

  my $rrd     = $oracledbDataWrapper->get_filepath_rrd( { type => $type, uuid => $server, acl_check => $acl_check, id => $host } );
  my $rrd_two = $oracledbDataWrapper->get_filepath_rrd( { type => $type, uuid => $server, acl_check => $acl_check, id => $host } );
  $rrd_two =~ s/-Capacity\.rrd/-Cpct\.rrd/g;

  #my ( $header, $reduced_header ) = get_header( $type, $uuid, 'CPU %' );

  my $cmd_params = my $cmd_legend = my $cmd_cdef = my $cmd_def = my $cmd_vlabel = "";

  $cmd_vlabel .= " --vertical-label=\"Capacity\"";
  $cmd_params .= " --lower-limit=0.00";
  $cmd_def    .= " DEF:used=\"$rrd\":used:AVERAGE";
  $cmd_def    .= " DEF:free=\"$rrd\":free:AVERAGE";
  $cmd_def    .= " DEF:log=\"$rrd\":log:AVERAGE";
  $cmd_def    .= " DEF:controlfiles=\"$rrd_two\":controlfiles:AVERAGE";
  $cmd_def    .= " DEF:tempfiles=\"$rrd_two\":tempfiles:AVERAGE";
  #
  $cmd_legend .= " COMMENT:\"[GB]                Avrg       Max\\n\"";
  my $label = get_formatted_label_val("Used");
  $cmd_legend .= " AREA:used#FF0000:\"$label\"";
  $cmd_legend .= " GPRINT:used:AVERAGE:\" %6.1lf\"";
  $cmd_legend .= " GPRINT:used:MAX:\" %6.1lf\"";
  $cmd_legend .= " COMMENT:\\n";
  $label = get_formatted_label_val("Logs");
  $cmd_legend .= " STACK:log#0000FF:\"$label\"";
  $cmd_legend .= " GPRINT:log:AVERAGE:\" %6.1lf\"";
  $cmd_legend .= " GPRINT:log:MAX:\" %6.1lf\"";
  $cmd_legend .= " COMMENT:\\n";
  $label = get_formatted_label_val("Control files");
  $cmd_legend .= " STACK:controlfiles#FFFF00:\"$label\"";
  $cmd_legend .= " GPRINT:controlfiles:AVERAGE:\" %6.1lf\"";
  $cmd_legend .= " GPRINT:controlfiles:MAX:\" %6.1lf\"";
  $cmd_legend .= " COMMENT:\\n";
  $label = get_formatted_label_val("Temp files");
  $cmd_legend .= " STACK:tempfiles#00FFFF:\"$label\"";
  $cmd_legend .= " GPRINT:tempfiles:AVERAGE:\" %6.1lf\"";
  $cmd_legend .= " GPRINT:tempfiles:MAX:\" %6.1lf\"";
  $cmd_legend .= " COMMENT:\\n";
  $label = get_formatted_label_val("Free");
  $cmd_legend .= " STACK:free#FFA500:\"$label\"";
  $cmd_legend .= " GPRINT:free:AVERAGE:\" %6.1lf\"";
  $cmd_legend .= " GPRINT:free:MAX:\" %6.1lf\"";

  $cmd_legend .= " COMMENT:\\n";

  return {
    filename => $rrd,     header   => "Capacity", reduced_header => "$server - Capacity", cmd_params => $cmd_params,
    cmd_def  => $cmd_def, cmd_cdef => $cmd_cdef,  cmd_legend     => $cmd_legend,          cmd_vlabel => $cmd_vlabel
  };
}

sub graph_disk_fr_na {
  my $acl_check = shift;
  my $host      = shift;
  my $server    = shift;
  my $type      = shift;

  my $rrd = $oracledbDataWrapper->get_filepath_rrd( { type => $type, uuid => $server, acl_check => $acl_check, id => $host } );

  #my ( $header, $reduced_header ) = get_header( $type, $uuid, 'CPU %' );

  my $cmd_params = my $cmd_legend = my $cmd_cdef = my $cmd_def = my $cmd_vlabel = "";

  $cmd_vlabel .= " --vertical-label=\"Milliseconds\"";
  $cmd_params .= " --lower-limit=0.00";
  $cmd_params .= " --units-exponent=0";
  $cmd_def    .= " DEF:OpnCrsPS=\"$rrd\":dbflscttrdr:AVERAGE";
  $cmd_def    .= " DEF:CntOpnCrs=\"$rrd\":flsqentlr:AVERAGE";
  #
  $cmd_legend .= " COMMENT:\"[ms]                Avrg       Max\\n\"";
  $cmd_legend .= " LINE1:OpnCrsPS#FF0000:\"db file scattered read\"";
  $cmd_legend .= " GPRINT:OpnCrsPS:AVERAGE:\" %6.2lf\"";
  $cmd_legend .= " GPRINT:OpnCrsPS:MAX:\" %6.2lf\"";
  $cmd_legend .= " COMMENT:\\n";
  $cmd_legend .= " LINE1:CntOpnCrs#0000FF:\"db file sequential read\"";
  $cmd_legend .= " GPRINT:CntOpnCrs:AVERAGE:\" %6.2lf\"";
  $cmd_legend .= " GPRINT:CntOpnCrs:MAX:\" %6.2lf\"";

  $cmd_legend .= " COMMENT:\\n";

  return {
    filename => $rrd,     header   => "db file read", reduced_header => "$server - db file read", cmd_params => $cmd_params,
    cmd_def  => $cmd_def, cmd_cdef => $cmd_cdef,      cmd_legend     => $cmd_legend,              cmd_vlabel => $cmd_vlabel
  };
}

sub graph_disk_log_sync_na {
  my $acl_check = shift;
  my $host      = shift;
  my $server    = shift;
  my $type      = shift;

  my $rrd = $oracledbDataWrapper->get_filepath_rrd( { type => $type, uuid => $server, acl_check => $acl_check, id => $host } );

  #my ( $header, $reduced_header ) = get_header( $type, $uuid, 'CPU %' );

  my $cmd_params = my $cmd_legend = my $cmd_cdef = my $cmd_def = my $cmd_vlabel = "";

  $cmd_vlabel .= " --vertical-label=\"Milliseconds\"";
  $cmd_params .= " --lower-limit=0.00";
  $cmd_params .= " --units-exponent=0";
  $cmd_def    .= " DEF:OpnCrsPS=\"$rrd\":flshbcklgfl:AVERAGE";
  $cmd_legend .= " COMMENT:\"[ms]                Avrg       Max\\n\"";
  $cmd_legend .= " LINE1:OpnCrsPS#FF0000:\"flashback log file sync\"";
  $cmd_legend .= " GPRINT:OpnCrsPS:AVERAGE:\" %6.2lf\"";
  $cmd_legend .= " GPRINT:OpnCrsPS:MAX:\" %6.2lf\"";
  $cmd_legend .= " COMMENT:\\n";

  return {
    filename => $rrd,     header   => "log sync", reduced_header => "$server - log sync", cmd_params => $cmd_params,
    cmd_def  => $cmd_def, cmd_cdef => $cmd_cdef,  cmd_legend     => $cmd_legend,          cmd_vlabel => $cmd_vlabel
  };
}

sub graph_log_w_na {
  my $acl_check = shift;
  my $host      = shift;
  my $server    = shift;
  my $type      = shift;

  my $rrd = $oracledbDataWrapper->get_filepath_rrd( { type => $type, uuid => $server, acl_check => $acl_check, id => $host } );

  #my ( $header, $reduced_header ) = get_header( $type, $uuid, 'CPU %' );

  my $cmd_params = my $cmd_legend = my $cmd_cdef = my $cmd_def = my $cmd_vlabel = "";

  $cmd_vlabel .= " --vertical-label=\"Milliseconds\"";
  $cmd_params .= " --units-exponent=0";
  $cmd_params .= " --lower-limit=0.00";
  $cmd_def    .= " DEF:OpnCrsPS=\"$rrd\":lgflsnglw:AVERAGE";
  $cmd_def    .= " DEF:CntOpnCrs=\"$rrd\":lgflprlllw:AVERAGE";
  $cmd_def    .= " DEF:opncrsps=\"$rrd\":lgflsnc:AVERAGE";

  $cmd_legend .= " COMMENT:\"[ms]                Avrg       Max\\n\"";
  $cmd_legend .= " LINE1:OpnCrsPS#FF0000:\"log file single write\"";
  $cmd_legend .= " GPRINT:OpnCrsPS:AVERAGE:\" %6.2lf\"";
  $cmd_legend .= " GPRINT:OpnCrsPS:MAX:\" %6.2lf\"";
  $cmd_legend .= " COMMENT:\\n";
  $cmd_legend .= " LINE1:CntOpnCrs#0000FF:\"log file parallel write\"";
  $cmd_legend .= " GPRINT:CntOpnCrs:AVERAGE:\" %6.2lf\"";
  $cmd_legend .= " GPRINT:CntOpnCrs:MAX:\" %6.2lf\"";
  $cmd_legend .= " COMMENT:\\n";
  $cmd_legend .= " LINE1:opncrsps#00FF00:\"log file sync\"";
  $cmd_legend .= " GPRINT:opncrsps:AVERAGE:\" %6.2lf\"";
  $cmd_legend .= " GPRINT:opncrsps:MAX:\" %6.2lf\"";
  $cmd_legend .= " COMMENT:\\n";

  return {
    filename => $rrd,     header   => "log write", reduced_header => "$server - log write", cmd_params => $cmd_params,
    cmd_def  => $cmd_def, cmd_cdef => $cmd_cdef,   cmd_legend     => $cmd_legend,           cmd_vlabel => $cmd_vlabel
  };
}

sub graph_disk_fr {
  my $acl_check  = shift;
  my $host       = shift;
  my $server     = shift;
  my $type       = shift;
  my $item       = shift;
  my $colors_ref = shift;
  my $color;
  my $g_number = 0;
  my @hosts    = split( /_/, $host );
  shift @hosts;
  my $rrd;
  ( $can_read, $ref ) = Xorux_lib::read_json("$main_data_dir/$server/instance_names.json");
  undef $instance_names;

  if ($can_read) {
    $instance_names = $ref;
  }
  my $pdb_names;
  if ( -f "$main_data_dir/$server/pdb_names.json" ) {
    my ( $can_read_p, $ref_p ) = Xorux_lib::read_json("$main_data_dir/$server/pdb_names.json");
    if ($can_read_p) {
      $pdb_names = $ref_p;
    }
  }

  #my ( $header, $reduced_header ) = get_header( $type, 'Network Traffic Volume' );
  my $cmd_params = my $cmd_legend = my $cmd_cdef = my $cmd_def = my $cmd_vlabel = "";

  my $cur_hos = 0;
  $cmd_vlabel .= " --vertical-label=\"Milliseconds per wait\"";
  $cmd_params .= " --units-exponent=0";
  $cmd_params .= " --lower-limit=0.00";
  $cmd_legend .= " COMMENT:\\n";

  foreach my $cur_host (@hosts) {
    undef $rrd;
    $rrd = $oracledbDataWrapper->get_filepath_rrd( { type => $type, uuid => $server, acl_check => $acl_check, id => $cur_host } );
    $cmd_def .= " DEF:OpnCrsPS-$cur_hos=\"$rrd\":dbflscttrdr:AVERAGE";
    $cmd_def .= " DEF:CntOpnCrs-$cur_hos=\"$rrd\":flsqentlr:AVERAGE";

    #    if($cur_hos == 0){
    #      $cmd_legend .= " COMMENT:\"[#]                          Avrg      Max\\n\"";
    #    }else{
    #      $cmd_legend .= " COMMENT:\\n";
    #    }
    $color = get_color( $colors_ref, $g_number );
    $g_number++;
    my $ins;
    if ( $instance_names->{$cur_host} ) {
      $ins = $instance_names->{$cur_host};
    }
    else {
      $ins = $pdb_names->{$cur_host};
    }
    my $label = "$ins,db file scattered read";
    $cmd_legend .= " LINE1:OpnCrsPS-$cur_hos" . "$color:\" $label     \"";
    $cmd_legend .= " GPRINT:OpnCrsPS-$cur_hos:AVERAGE:\" %6.2lf\"";
    $cmd_legend .= " GPRINT:OpnCrsPS-$cur_hos:MAX:\" %6.2lf\"";
    $cmd_legend .= " PRINT:OpnCrsPS-$cur_hos:AVERAGE:\" %6.2lf $del $item $del $label $del $color $del db_file_scattered_read\"";
    $cmd_legend .= " PRINT:OpnCrsPS-$cur_hos:MAX:\" %6.2lf $del asd $del $label $del $cur_host\"";

    $cmd_legend .= " COMMENT:\\n";

    #$cmd_legend_t .= " COMMENT:\\n";
    $color = get_color( $colors_ref, $g_number );
    $g_number++;
    if ( $instance_names->{$cur_host} ) {
      $ins = $instance_names->{$cur_host};
    }
    else {
      $ins = $pdb_names->{$cur_host};
    }
    $label = "$ins,db file sequential read";
    $cmd_legend .= " LINE1:CntOpnCrs-$cur_hos" . "$color:\" $label    \"";
    $cmd_legend .= " GPRINT:CntOpnCrs-$cur_hos:AVERAGE:\" %6.2lf\"";
    $cmd_legend .= " GPRINT:CntOpnCrs-$cur_hos:MAX:\" %6.2lf\"";
    $cmd_legend .= " PRINT:CntOpnCrs-$cur_hos:AVERAGE:\" %6.2lf $del $item $del $label $del $color $del db_file_sequential_read\"";
    $cmd_legend .= " PRINT:CntOpnCrs-$cur_hos:MAX:\" %6.2lf $del asd $del $label $del $cur_host\"";

    $cmd_legend .= " COMMENT:\\n";

    $cur_hos += 1;
  }

  #$cmd_legend .= " COMMENT:\\n";

  return {
    filepath => $rrd,     header   => "Cursors info", reduced_header => "reduced_header", cmd_params => $cmd_params,
    cmd_def  => $cmd_def, cmd_cdef => $cmd_cdef,      cmd_legend     => $cmd_legend,      cmd_vlabel => $cmd_vlabel
  };
}

sub graph_disk_fw {
  my $acl_check  = shift;
  my $host       = shift;
  my $server     = shift;
  my $type       = shift;
  my $item       = shift;
  my $colors_ref = shift;
  my $color;
  my $g_number = 0;
  my @hosts    = split( /_/, $host );
  shift @hosts;
  my $rrd;
  ( $can_read, $ref ) = Xorux_lib::read_json("$main_data_dir/$server/instance_names.json");
  undef $instance_names;

  if ($can_read) {
    $instance_names = $ref;
  }
  my $pdb_names;
  if ( -f "$main_data_dir/$server/pdb_names.json" ) {
    my ( $can_read_p, $ref_p ) = Xorux_lib::read_json("$main_data_dir/$server/pdb_names.json");
    if ($can_read_p) {
      $pdb_names = $ref_p;
    }
  }

  #my ( $header, $reduced_header ) = get_header( $type, 'Network Traffic Volume' );
  my $cmd_params = my $cmd_legend = my $cmd_cdef = my $cmd_def = my $cmd_vlabel = "";

  my $cur_hos = 0;
  $cmd_vlabel .= " --vertical-label=\"Milliseconds per wait\"";
  $cmd_params .= " --units-exponent=0";
  $cmd_params .= " --lower-limit=0.00";
  $cmd_legend .= " COMMENT:\\n";

  foreach my $cur_host (@hosts) {
    undef $rrd;
    $rrd = $oracledbDataWrapper->get_filepath_rrd( { type => $type, uuid => $server, acl_check => $acl_check, id => $cur_host } );
    $cmd_def .= " DEF:OpnCrsPS-$cur_hos=\"$rrd\":flsnglw:AVERAGE";
    $cmd_def .= " DEF:CntOpnCrs-$cur_hos=\"$rrd\":flprlllw:AVERAGE";

    #    if($cur_hos == 0){
    #      $cmd_legend .= " COMMENT:\"[#]                          Avrg      Max\\n\"";
    #    }else{
    #      $cmd_legend .= " COMMENT:\\n";
    #    }
    $color = get_color( $colors_ref, $g_number );
    $g_number++;
    my $ins;
    if ( $instance_names->{$cur_host} ) {
      $ins = $instance_names->{$cur_host};
    }
    else {
      $ins = $pdb_names->{$cur_host};
    }
    my $label = "$ins,db file single write";
    $cmd_legend .= " LINE1:OpnCrsPS-$cur_hos" . "$color:\" $label     \"";
    $cmd_legend .= " GPRINT:OpnCrsPS-$cur_hos:AVERAGE:\" %6.2lf\"";
    $cmd_legend .= " GPRINT:OpnCrsPS-$cur_hos:MAX:\" %6.2lf\"";
    $cmd_legend .= " PRINT:OpnCrsPS-$cur_hos:AVERAGE:\" %6.2lf $del $item $del $label $del $color $del db_file_single_write\"";
    $cmd_legend .= " PRINT:OpnCrsPS-$cur_hos:MAX:\" %6.2lf $del asd $del $label $del $cur_host\"";

    $cmd_legend .= " COMMENT:\\n";

    #$cmd_legend_t .= " COMMENT:\\n";
    $color = get_color( $colors_ref, $g_number );
    $g_number++;
    if ( $instance_names->{$cur_host} ) {
      $ins = $instance_names->{$cur_host};
    }
    else {
      $ins = $pdb_names->{$cur_host};
    }
    $label = "$ins,db file parallel write";
    $cmd_legend .= " LINE1:CntOpnCrs-$cur_hos" . "$color:\" $label    \"";
    $cmd_legend .= " GPRINT:CntOpnCrs-$cur_hos:AVERAGE:\" %6.2lf\"";
    $cmd_legend .= " GPRINT:CntOpnCrs-$cur_hos:MAX:\" %6.2lf\"";
    $cmd_legend .= " PRINT:CntOpnCrs-$cur_hos:AVERAGE:\" %6.2lf $del $item $del $label $del $color $del db_file_parallel_write\"";
    $cmd_legend .= " PRINT:CntOpnCrs-$cur_hos:MAX:\" %6.2lf $del asd $del $label $del $cur_host\"";

    $cmd_legend .= " COMMENT:\\n";

    $cur_hos += 1;
  }

  #$cmd_legend .= " COMMENT:\\n";

  return {
    filepath => $rrd,     header   => "Cursors info", reduced_header => "reduced_header", cmd_params => $cmd_params,
    cmd_def  => $cmd_def, cmd_cdef => $cmd_cdef,      cmd_legend     => $cmd_legend,      cmd_vlabel => $cmd_vlabel
  };

}

sub graph_log_sync {
  my $acl_check  = shift;
  my $host       = shift;
  my $server     = shift;
  my $type       = shift;
  my $item       = shift;
  my $colors_ref = shift;
  my $color;
  my $g_number = 0;
  my @hosts    = split( /_/, $host );
  shift @hosts;
  my $rrd;
  ( $can_read, $ref ) = Xorux_lib::read_json("$main_data_dir/$server/instance_names.json");
  undef $instance_names;

  if ($can_read) {
    $instance_names = $ref;
  }
  my $pdb_names;
  if ( -f "$main_data_dir/$server/pdb_names.json" ) {
    my ( $can_read_p, $ref_p ) = Xorux_lib::read_json("$main_data_dir/$server/pdb_names.json");
    if ($can_read_p) {
      $pdb_names = $ref_p;
    }
  }

  #my ( $header, $reduced_header ) = get_header( $type, 'Network Traffic Volume' );
  my $cmd_params = my $cmd_legend = my $cmd_cdef = my $cmd_def = my $cmd_vlabel = "";

  my $cur_hos = 0;
  $cmd_vlabel .= " --vertical-label=\"Milliseconds per wait\"";
  $cmd_params .= " --units-exponent=0";
  $cmd_params .= " --lower-limit=0.00";
  $cmd_legend .= " COMMENT:\\n";

  foreach my $cur_host (@hosts) {
    undef $rrd;
    $rrd = $oracledbDataWrapper->get_filepath_rrd( { type => $type, uuid => $server, acl_check => $acl_check, id => $cur_host } );
    $cmd_def .= " DEF:OpnCrsPS-$cur_hos=\"$rrd\":flshbcklgfl:AVERAGE";

    #    if($cur_hos == 0){
    #      $cmd_legend .= " COMMENT:\"[#]                          Avrg      Max\\n\"";
    #    }else{
    #      $cmd_legend .= " COMMENT:\\n";
    #    }
    $color = get_color( $colors_ref, $g_number );
    $g_number++;
    my $ins;
    if ( $instance_names->{$cur_host} ) {
      $ins = $instance_names->{$cur_host};
    }
    else {
      $ins = $pdb_names->{$cur_host};
    }
    my $label = "$ins,flashback log file sync";
    $cmd_legend .= " LINE1:OpnCrsPS-$cur_hos" . "$color:\" $label     \"";
    $cmd_legend .= " GPRINT:OpnCrsPS-$cur_hos:AVERAGE:\" %6.2lf\"";
    $cmd_legend .= " GPRINT:OpnCrsPS-$cur_hos:MAX:\" %6.2lf\"";
    $cmd_legend .= " PRINT:OpnCrsPS-$cur_hos:AVERAGE:\" %6.2lf $del $item $del $label $del $color $del flashback_log_file_sync\"";
    $cmd_legend .= " PRINT:OpnCrsPS-$cur_hos:MAX:\" %6.2lf $del asd $del $label $del $cur_host\"";

    $cmd_legend .= " COMMENT:\\n";

    $cur_hos += 1;
  }

  #$cmd_legend .= " COMMENT:\\n";

  return {
    filepath => $rrd,     header   => "Cursors info", reduced_header => "reduced_header", cmd_params => $cmd_params,
    cmd_def  => $cmd_def, cmd_cdef => $cmd_cdef,      cmd_legend     => $cmd_legend,      cmd_vlabel => $cmd_vlabel
  };
}

sub graph_log_w {
  my $acl_check  = shift;
  my $host       = shift;
  my $server     = shift;
  my $type       = shift;
  my $item       = shift;
  my $colors_ref = shift;
  my $color;
  my $g_number = 0;
  my @hosts    = split( /_/, $host );
  shift @hosts;
  my $rrd;
  ( $can_read, $ref ) = Xorux_lib::read_json("$main_data_dir/$server/instance_names.json");
  undef $instance_names;

  if ($can_read) {
    $instance_names = $ref;
  }
  my $pdb_names;
  if ( -f "$main_data_dir/$server/pdb_names.json" ) {
    my ( $can_read_p, $ref_p ) = Xorux_lib::read_json("$main_data_dir/$server/pdb_names.json");
    if ($can_read_p) {
      $pdb_names = $ref_p;
    }
  }

  #my ( $header, $reduced_header ) = get_header( $type, 'Network Traffic Volume' );
  my $cmd_params = my $cmd_legend = my $cmd_cdef = my $cmd_def = my $cmd_vlabel = "";

  my $cur_hos = 0;
  $cmd_vlabel .= " --vertical-label=\"Milliseconds per wait\"";
  $cmd_params .= " --units-exponent=0";
  $cmd_params .= " --lower-limit=0.00";
  $cmd_legend .= " COMMENT:\\n";

  foreach my $cur_host (@hosts) {
    undef $rrd;
    $rrd = $oracledbDataWrapper->get_filepath_rrd( { type => $type, uuid => $server, acl_check => $acl_check, id => $cur_host } );
    $cmd_def .= " DEF:OpnCrsPS-$cur_hos=\"$rrd\":lgflsnglw:AVERAGE";
    $cmd_def .= " DEF:CntOpnCrs-$cur_hos=\"$rrd\":lgflprlllw:AVERAGE";
    $cmd_def .= " DEF:opncrsps-$cur_hos=\"$rrd\":lgflsnc:AVERAGE";

    #    if($cur_hos == 0){
    #      $cmd_legend .= " COMMENT:\"[#]                          Avrg      Max\\n\"";
    #    }else{
    #      $cmd_legend .= " COMMENT:\\n";
    #    }
    $color = get_color( $colors_ref, $g_number );
    $g_number++;
    my $ins;
    if ( $instance_names->{$cur_host} ) {
      $ins = $instance_names->{$cur_host};
    }
    else {
      $ins = $pdb_names->{$cur_host};
    }
    my $label = "$ins,log file single write";
    $cmd_legend .= " LINE1:OpnCrsPS-$cur_hos" . "$color:\" $label     \"";
    $cmd_legend .= " GPRINT:OpnCrsPS-$cur_hos:AVERAGE:\" %6.2lf\"";
    $cmd_legend .= " GPRINT:OpnCrsPS-$cur_hos:MAX:\" %6.2lf\"";
    $cmd_legend .= " PRINT:OpnCrsPS-$cur_hos:AVERAGE:\" %6.2lf $del $item $del $label $del $color $del log_file_single_write\"";
    $cmd_legend .= " PRINT:OpnCrsPS-$cur_hos:MAX:\" %6.2lf $del asd $del $label $del $cur_host\"";

    #$cmd_legend_t .= " COMMENT:\\n";
    $color = get_color( $colors_ref, $g_number );
    $g_number++;
    if ( $instance_names->{$cur_host} ) {
      $ins = $instance_names->{$cur_host};
    }
    else {
      $ins = $pdb_names->{$cur_host};
    }
    $label = "$ins,log file parallel write";
    $cmd_legend .= " LINE1:CntOpnCrs-$cur_hos" . "$color:\" $label    \"";
    $cmd_legend .= " GPRINT:CntOpnCrs-$cur_hos:AVERAGE:\" %6.2lf\"";
    $cmd_legend .= " GPRINT:CntOpnCrs-$cur_hos:MAX:\" %6.2lf\"";
    $cmd_legend .= " PRINT:CntOpnCrs-$cur_hos:AVERAGE:\" %6.2lf $del $item $del $label $del $color $del log_file_parallel_write\"";
    $cmd_legend .= " PRINT:CntOpnCrs-$cur_hos:MAX:\" %6.2lf $del asd $del $label $del $cur_host\"";

    $color = get_color( $colors_ref, $g_number );
    $g_number++;
    if ( $instance_names->{$cur_host} ) {
      $ins = $instance_names->{$cur_host};
    }
    else {
      $ins = $pdb_names->{$cur_host};
    }
    $label = "$ins,log file sync";
    $cmd_legend .= " LINE1:opncrsps-$cur_hos" . "$color:\" $label    \"";
    $cmd_legend .= " GPRINT:opncrsps-$cur_hos:AVERAGE:\" %6.2lf\"";
    $cmd_legend .= " GPRINT:opncrsps-$cur_hos:MAX:\" %6.2lf\"";
    $cmd_legend .= " PRINT:opncrsps-$cur_hos:AVERAGE:\" %6.2lf $del $item $del $label $del $color $del log_file_sync\"";
    $cmd_legend .= " PRINT:opncrsps-$cur_hos:MAX:\" %6.2lf $del asd $del $label $del $cur_host\"";

    $cur_hos += 1;
  }

  #$cmd_legend .= " COMMENT:\\n";

  return {
    filepath => $rrd,     header   => "Cursors info", reduced_header => "reduced_header", cmd_params => $cmd_params,
    cmd_def  => $cmd_def, cmd_cdef => $cmd_cdef,      cmd_legend     => $cmd_legend,      cmd_vlabel => $cmd_vlabel
  };
}

sub graph_block_xway {
  my $acl_check  = shift;
  my $host       = shift;
  my $server     = shift;
  my $type       = shift;
  my $item       = shift;
  my $colors_ref = shift;
  my $color;
  my $g_number = 0;
  my @hosts    = split( /_/, $host );
  shift @hosts;
  my $rrd;
  ( $can_read, $ref ) = Xorux_lib::read_json("$main_data_dir/$server/instance_names.json");
  undef $instance_names;

  if ($can_read) {
    $instance_names = $ref;
  }

  #my ( $header, $reduced_header ) = get_header( $type, 'Network Traffic Volume' );
  my $cmd_params = my $cmd_legend = my $cmd_cdef = my $cmd_def = my $cmd_vlabel = "";

  my $cur_hos = 0;
  $cmd_vlabel .= " --vertical-label=\"Milliseconds per wait\"";
  $cmd_params .= " --units-exponent=0";
  $cmd_params .= " --lower-limit=0.00";
  $cmd_legend .= " COMMENT:\\n";

  foreach my $cur_host (@hosts) {
    undef $rrd;
    $rrd = $oracledbDataWrapper->get_filepath_rrd( { type => $type, uuid => $server, acl_check => $acl_check, id => $cur_host } );
    $cmd_def .= " DEF:AvgActSsion-$cur_hos=\"$rrd\":crblocktwy:AVERAGE";
    $cmd_def .= " DEF:ActSrlSsion-$cur_hos=\"$rrd\":crntblcktwy:AVERAGE";
    $cmd_def .= " DEF:ActPrllSsion-$cur_hos=\"$rrd\":crblckthwy:AVERAGE";
    $cmd_def .= " DEF:CrntLgnsCnt-$cur_hos=\"$rrd\":crntblckthwy:AVERAGE";

    if ( $cur_hos == 0 ) {

      #$cmd_cdef   .= " CDEF:read_graph=0,read-$cur_hos,-";
      $cmd_legend .= " COMMENT:\"                                   Avrg      Max\\n\"";
    }
    else {
      $cmd_legend .= " COMMENT:\\n";
    }
    $color = get_color( $colors_ref, $g_number );
    $g_number++;
    my $label = "$instance_names->{$cur_host},gc cr block 2-way";
    $cmd_legend .= " LINE1:AvgActSsion-$cur_hos" . "$color:\" $label\"";
    $cmd_legend .= " GPRINT:AvgActSsion-$cur_hos:AVERAGE:\" %6.2lf\"";
    $cmd_legend .= " GPRINT:AvgActSsion-$cur_hos:MAX:\" %6.2lf\"";
    $cmd_legend .= " PRINT:AvgActSsion-$cur_hos:AVERAGE:\" %6.2lf $del $item $del $label $del $color $del gc_cr_block_2-way\"";
    $cmd_legend .= " PRINT:AvgActSsion-$cur_hos:MAX:\" %6.2lf $del asd $del $label $del $cur_host\"";

    $cmd_legend .= " COMMENT:\\n";
    $color = get_color( $colors_ref, $g_number );
    $g_number++;
    $label = "$instance_names->{$cur_host},gc current block 2-way";
    $cmd_legend .= " LINE1:ActSrlSsion-$cur_hos" . "$color:\" $label\"";
    $cmd_legend .= " GPRINT:ActSrlSsion-$cur_hos:AVERAGE:\" %6.2lf\"";
    $cmd_legend .= " GPRINT:ActSrlSsion-$cur_hos:MAX:\" %6.2lf\"";
    $cmd_legend .= " PRINT:ActSrlSsion-$cur_hos:AVERAGE:\" %6.2lf $del $item $del $label $del $color $del gc_current_block_2-way\"";
    $cmd_legend .= " PRINT:ActSrlSsion-$cur_hos:MAX:\" %6.2lf $del asd $del $label $del $cur_host\"";

    $cmd_legend .= " COMMENT:\\n";
    $color = get_color( $colors_ref, $g_number );
    $g_number++;
    $label = "$instance_names->{$cur_host},gc cr block 3-way";
    $cmd_legend .= " LINE1:ActPrllSsion-$cur_hos" . "$color:\" $label\"";
    $cmd_legend .= " GPRINT:ActPrllSsion-$cur_hos:AVERAGE:\"%6.2lf\"";
    $cmd_legend .= " GPRINT:ActPrllSsion-$cur_hos:MAX:\" %6.2lf\"";
    $cmd_legend .= " PRINT:ActPrllSsion-$cur_hos:AVERAGE:\" %6.2lf $del $item $del $label $del $color $del gc_cr_block_3-way\"";
    $cmd_legend .= " PRINT:ActPrllSsion-$cur_hos:MAX:\" %6.2lf $del asd $del $label $del $cur_host\"";

    $cmd_legend .= " COMMENT:\\n";
    $color = get_color( $colors_ref, $g_number );
    $g_number++;
    $label = "$instance_names->{$cur_host},gc current block 3-way";
    $cmd_legend .= " LINE1:CrntLgnsCnt-$cur_hos" . "$color:\" $label\"";
    $cmd_legend .= " GPRINT:CrntLgnsCnt-$cur_hos:AVERAGE:\" %6.2lf\"";
    $cmd_legend .= " GPRINT:CrntLgnsCnt-$cur_hos:MAX:\" %6.2lf\"";
    $cmd_legend .= " PRINT:CrntLgnsCnt-$cur_hos:AVERAGE:\" %6.2lf $del $item $del $label $del $color $del gc_current_block_3-way\"";
    $cmd_legend .= " PRINT:CrntLgnsCnt-$cur_hos:MAX:\" %6.2lf $del asd $del $label $del $cur_host\"";

    $cmd_legend .= " COMMENT:\\n";

    $cur_hos += 1;
  }

  $cmd_legend .= " COMMENT:\\n";

  return {
    filepath => $rrd,     header   => "Cursors info", reduced_header => "reduced_header", cmd_params => $cmd_params,
    cmd_def  => $cmd_def, cmd_cdef => $cmd_cdef,      cmd_legend     => $cmd_legend,      cmd_vlabel => $cmd_vlabel
  };
}

sub graph_aggr {
  my $acl_check = shift;
  my $host      = shift;
  my $server    = shift;
  my $type      = shift;
  my $item      = shift;
  my $uuid      = shift;
  my $color     = shift;
  my $cur_host  = shift;
  my $g_number  = 0;
  my $rrd;
  my $page       = basename( $item, '__' );
  my $cmd_params = my $cmd_legend = my $cmd_cdef = my $cmd_def = my $cmd_vlabel = "";

  my $waitclass_dir = $oracledbDataWrapper->get_filepath_rrd( { type => $type, uuid => $server, acl_check => $acl_check, id => $host } );
  my $decimals = get_decimals($type);
  my $rrd;
  my ( $can_read, $ref );
  my $dict;
  if ( -f "$waitclass_dir/dict.json" ) {
    ( $can_read, $ref ) = Xorux_lib::read_json("$waitclass_dir/dict.json");
  }
  $dict = $ref;

  undef $rrd;
  $rrd = "$waitclass_dir" . "$uuid" . ".rrd";
  my $name;
  if ($can_read) {
    $name = defined $dict->{$uuid} ? $dict->{$uuid} : $uuid;
  }
  else {
    $name = $uuid;
  }

  $cmd_def  .= " DEF:units-$cur_host=\"$rrd\":$page:AVERAGE";
  $cmd_cdef .= " CDEF:metric_units-$cur_host=units-$cur_host";
  $cmd_cdef .= " CDEF:metric_legend-$cur_host=units-$cur_host";
  my $test = get_formatted_label($name);
  $cmd_legend .= " COMMENT:\"$test\"";
  $cmd_legend .= " LINE1:metric_units-$cur_host$color:\" \"";
  $cmd_legend .= " GPRINT:metric_legend-$cur_host:AVERAGE:\" %6.".$decimals."lf\"";
  $cmd_legend .= " GPRINT:metric_legend-$cur_host:MAX:\" %6.".$decimals."lf\"";
  $cmd_legend .= " PRINT:metric_legend-$cur_host:AVERAGE:\" %6.".$decimals."lf $del $item $del $name $del $color\"";    #
  $cmd_legend .= " PRINT:metric_legend-$cur_host:MAX:\" %6.".$decimals."lf $del asd $del asd $del $uuid\"";             #
  $cmd_legend .= " COMMENT:\\n";
  $cur_host++;

  return { cmd_def => $cmd_def, cmd_cdef => $cmd_cdef, cmd_legend => $cmd_legend, filepath => $rrd };
}

sub graph_aggrsingle {
  my $acl_check = shift;
  my $host      = shift;
  my $server    = shift;
  my $type      = shift;
  my $item      = shift;
  my $color     = "#";
  my $cur_host  = 1;
  my $g_number  = 0;
  my $rrd;
  my $uuid = "";
  $color .= basename( $item, '_a_' );
  $item = substr( $item, 0, index( $item, '_a_' ) );
  $uuid = basename( $item, '___' );
  $item = substr( $item, 0, index( $item, '___' ) );
  my $page       = basename( $item, '__' );
  my $cmd_params = my $cmd_legend = my $cmd_cdef = my $cmd_def = my $cmd_vlabel = "";

  my $waitclass_dir = $oracledbDataWrapper->get_filepath_rrd( { type => $type, uuid => $server, acl_check => $acl_check, id => $host } );

  my $rrd;
  my ( $can_read, $ref );
  my $dict;
  if ( -f "$waitclass_dir/dict.json" ) {
    ( $can_read, $ref ) = Xorux_lib::read_json("$waitclass_dir/dict.json");
  }
  $dict = $ref;

  undef $rrd;
  $rrd = "$waitclass_dir" . "$uuid" . ".rrd";
  my $name;
  if ($can_read) {
    $name = defined $dict->{$uuid} ? $dict->{$uuid} : $uuid;
  }
  else {
    $name = $uuid;
  }
  $cmd_vlabel .= " --vertical-label=\"Session info\"";
  $cmd_params .= " --lower-limit=0.00";
  $cmd_legend .= " COMMENT:\\n";

  $cmd_def    .= " DEF:units-$uuid=\"$rrd\":$page:AVERAGE";
  $cmd_cdef   .= " CDEF:metric_units-$uuid=units-$uuid";
  $cmd_cdef   .= " CDEF:metric_legend-$uuid=units-$uuid";
  $cmd_legend .= " LINE1:metric_units-$uuid$color:\" $name \"";
  $cmd_legend .= " GPRINT:metric_units-$uuid:AVERAGE:\" %6.1lf\"";
  $cmd_legend .= " GPRINT:metric_units-$uuid:MAX:\" %6.1lf\"";
  $cmd_legend .= " COMMENT:\\n";
  $cur_host++;

  return {
    filename => $rrd,     header   => "Cursors info", reduced_header => "$server - Cursors info", cmd_params => $cmd_params,
    cmd_def  => $cmd_def, cmd_cdef => $cmd_cdef,      cmd_legend     => $cmd_legend,              cmd_vlabel => $cmd_vlabel
  };
}

sub graph_views {
  my $acl_check  = shift;
  my $host       = shift;
  my $server     = shift;
  my $type       = shift;
  my $item       = shift;
  my $colors_ref = shift;
  my $color;
  my $pages_ref = OracleDBDataWrapper::get_pages($type);
  my $g_number  = 0;
  my @hosts     = split( /_/, $host );
  shift @hosts;
  my $rrd;
  ( $can_read, $ref ) = Xorux_lib::read_json("$main_data_dir/$server/instance_names.json");
  undef $instance_names;

  if ($can_read) {
    $instance_names = $ref;
  }
  my $pdb_names;
  if ( -f "$main_data_dir/$server/pdb_names.json" ) {
    my ( $can_read_p, $ref_p ) = Xorux_lib::read_json("$main_data_dir/$server/pdb_names.json");
    if ($can_read_p) {
      $pdb_names = $ref_p;
    }
  }

  #my ( $header, $reduced_header ) = get_header( $type, 'Network Traffic Volume' );
  my $cmd_params = my $cmd_legend = my $cmd_cdef = my $cmd_def = my $cmd_vlabel = "";

  my %pages;
  if ( $pages_ref and $pages_ref ne "empty" ) {
    %pages = %{$pages_ref};
  }
  else {
    warn "no pages in views";
  }

  my $cur_hos = 0;

  #view 3 jsou kombi. Asi by to chtělo if ?
  if ( $type ne "viewthree" ) {
    if ( $type eq "aggr_Session_info" ) {
      $cmd_vlabel .= " --vertical-label=\"Sessions/Logons\"";
    }
    else {
      $cmd_vlabel .= " --vertical-label=\"Milliseconds per wait\"";
      $cmd_params .= " --units-exponent=0";
    }
  }
  $cmd_params .= " --lower-limit=0.00";
  $cmd_legend .= " COMMENT:\\n";
  my $decimals = get_decimals($type);

  foreach my $cur_host (@hosts) {
    undef $rrd;
    $rrd = $oracledbDataWrapper->get_filepath_rrd( { type => $type, uuid => $server, acl_check => $acl_check, id => $cur_host } );
    for my $page ( keys %pages ) {
      my $rrdval = $pages{$page};
      $cmd_def .= " DEF:view-$cur_hos-$rrdval=\"$rrd\":$rrdval:AVERAGE";

      #      if($cur_hos == 0){
      #        $cmd_legend .= " COMMENT:\"[#]                          Avrg      Max\\n\"";
      #      }else{
      #        $cmd_legend .= " COMMENT:\\n";
      #      }
      $color = get_color( $colors_ref, $g_number );
      $g_number++;
      my $ins;
      if ( $instance_names->{$cur_host} ) {
        $ins = $instance_names->{$cur_host};
      }
      else {
        $ins = $pdb_names->{$cur_host};
      }
      my $label = "$ins,$page";
      $label =~ s/Global Cache/GC/g;
      my $ns_page = $page;
      $ns_page =~ s/ /_/g;
      $cmd_legend .= " LINE1:view-$cur_hos-$rrdval" . "$color:\" $label     \"";

      $cmd_legend .= " GPRINT:view-$cur_hos-$rrdval:AVERAGE:\" %6.".$decimals."1lf\"";
      $cmd_legend .= " GPRINT:view-$cur_hos-$rrdval:MAX:\" %6.".$decimals."lf\"";
      $cmd_legend .= " PRINT:view-$cur_hos-$rrdval:AVERAGE:\" %6.".$decimals."lf $del $item $del $label $del $color $del $ns_page\"";
      $cmd_legend .= " PRINT:view-$cur_hos-$rrdval:MAX:\" %6.".$decimals."lf $del asd $del $label $del $cur_host\"";
      $cmd_legend .= " COMMENT:\\n";
    }
    $cur_hos += 1;
  }

  #$cmd_legend .= " COMMENT:\\n";

  return {
    filepath => $rrd,     header   => "Cursors info", reduced_header => "reduced_header", cmd_params => $cmd_params,
    cmd_def  => $cmd_def, cmd_cdef => $cmd_cdef,      cmd_legend     => $cmd_legend,      cmd_vlabel => $cmd_vlabel
  };
}

sub graph_color_host {
  my $acl_check = shift;
  my $host      = shift;
  my $server    = shift;
  my $type      = shift;
  my $item      = shift;
  my $color     = "#";
  my $cur_host  = 1;
  my $g_number  = 0;
  my $rrd;
  my $uuid = "";
  $color .= basename( $item, '_a_' );
  $item = substr( $item, 0, index( $item, '_a_' ) );
  $uuid = basename( $item, '___' );
  $item = substr( $item, 0, index( $item, '___' ) );
  my $page       = basename( $item, '__' );
  my $cmd_params = my $cmd_legend = my $cmd_cdef = my $cmd_def = my $cmd_vlabel = "";

  my $waitclass_dir = $oracledbDataWrapper->get_filepath_rrd( { type => $type, uuid => $server, acl_check => $acl_check, id => $host } );

  my $rrd;
  my ( $can_read, $ref );
  my $dict;
  if ( -f "$waitclass_dir/dict.json" ) {
    ( $can_read, $ref ) = Xorux_lib::read_json("$waitclass_dir/dict.json");
  }
  $dict = $ref;

  undef $rrd;
  $rrd = "$waitclass_dir" . "$uuid" . ".rrd";
  my $name;
  if ($can_read) {
    $name = defined $dict->{$uuid} ? $dict->{$uuid} : $uuid;
  }
  else {
    $name = $uuid;
  }
  $cmd_vlabel .= " --vertical-label=\"Session info\"";
  $cmd_params .= " --lower-limit=0.00";
  $cmd_legend .= " COMMENT:\\n";

  $cmd_def    .= " DEF:units-$uuid=\"$rrd\":$page:AVERAGE";
  $cmd_cdef   .= " CDEF:metric_units-$uuid=units-$uuid";
  $cmd_cdef   .= " CDEF:metric_legend-$uuid=units-$uuid";
  $cmd_legend .= " LINE1:metric_units-$uuid$color:\" $name \"";
  $cmd_legend .= " GPRINT:metric_units-$uuid:AVERAGE:\" %6.1lf\"";
  $cmd_legend .= " GPRINT:metric_units-$uuid:MAX:\" %6.1lf\"";
  $cmd_legend .= " COMMENT:\\n";
  $cur_host++;

  return {
    filename => $rrd,     header   => "Cursors info", reduced_header => "reduced_header", cmd_params => $cmd_params,
    cmd_def  => $cmd_def, cmd_cdef => $cmd_cdef,      cmd_legend     => $cmd_legend,      cmd_vlabel => $cmd_vlabel
  };

}

sub graph_total_aggr {
  my $acl_check  = shift;
  my $host       = shift;
  my $server     = shift;
  my $type       = shift;
  my $item       = shift;
  my $colors_ref = shift;
  my $host_names;
  my $g_number = 0;
  my $page     = basename( $item, '__' );
  $page =~ s/_Total//g;
  my $rrd;
  my $legend     = OracleDBDataWrapper::graph_legend($page);
  my $rrd_name   = $legend->{rrd_vname};
  my $cmd_params = my $cmd_legend = my $cmd_cdef = my $cmd_def = my $cmd_vlabel = "";
  my ( $can_read_groups, $ref_groups, $groups, @act_groups, @host_aliases, %main_hash );

  $host =~ s/groups_//g;
  @act_groups = split( /,/, $host );
  if ( $server eq "custom" ) {

    $groups = OracleDBDataWrapper::process_custom_odb();
  }
  else {
    ( $can_read_groups, $ref_groups, $groups ) = Xorux_lib::read_json("$main_data_dir/Totals/groups.json");
    if ($can_read_groups) {
      $groups = $ref_groups;
    }
  }
  @host_aliases;
  %main_hash;
  if ( $act_groups[1] ) {
    if ( %{ $groups->{_mgroups}->{ $act_groups[0] }->{_sgroups}{ $act_groups[1] }->{_dbs} } ) {
      %main_hash    = %{ $groups->{_mgroups}->{ $act_groups[0] }->{_sgroups}{ $act_groups[1] }->{_dbs} };
      @host_aliases = keys %{ $groups->{_mgroups}->{ $act_groups[0] }->{_sgroups}{ $act_groups[1] }->{_dbs} };
    }
  }
  else {
    if ( %{ $groups->{_mgroups}->{ $act_groups[0] }->{_dbs} } ) {
      %main_hash    = %{ $groups->{_mgroups}->{ $act_groups[0] }->{_dbs} };
      @host_aliases = keys %{ $groups->{_mgroups}->{ $act_groups[0] }->{_dbs} };
    }
  }
  my $cur_hos = 0;
  foreach my $alias (@host_aliases) {
    my $db_type = OracleDBDataWrapper::get_dbtype($alias);
    if ( OracleDBDataWrapper::get_dbtype($alias) eq "RAC_Multitenant" ) {
      if ( index( $page, "DB_Block_Changes" ) != -1 or index( $page, "Logical_Reads_Pe" ) != -1 ) {
        next;
      }
    }
    if ( $server eq "custom" ) {
      if ( !-e $log_err_file && $cur_hos >= 4 ) {
        last;
      }
    }
    ( $can_read, $ref ) = Xorux_lib::read_json("$main_data_dir/$alias/instance_names.json");
    undef $instance_names;
    if ($can_read) {
      $instance_names = $ref;
    }
    else {
      next;
    }
    my $can_read_hosts;
    my $host_ref;
    ( $can_read_hosts, $host_ref ) = Xorux_lib::read_json("$main_data_dir/$alias/host_names.json");
    undef $host_names;
    if ($can_read_hosts) {
      $host_names = $host_ref;
    }
    my @hosts = @{ $main_hash{$alias} };
    $cmd_vlabel .= " --vertical-label=\"$legend->{v_label}\"";
    foreach my $cur_host (@hosts) {
      if ( $server eq "custom" ) {
        if ( !-e $log_err_file && $cur_hos >= 4 ) {
          last;
        }
      }
      undef $rrd;
      my $color;
      if ( $server eq "custom" ) {
        my $act_type_fp = $oracledbDataWrapper->get_type_from_page($page);
        $rrd = $oracledbDataWrapper->get_filepath_rrd( { type => $act_type_fp, uuid => $alias, id => $cur_host, skip_acl => 1 } );
      }
      else {
        my $act_type_fp = $oracledbDataWrapper->get_type_from_page($page);
        $rrd = $oracledbDataWrapper->get_filepath_rrd( { type => $act_type_fp, uuid => $alias, acl_check => $acl_check, id => $cur_host } );
      }
      unless ( -f $rrd ) {
        next;
      }
      my $name = OracleDBDataWrapper::md5_string("name-$cur_hos-$alias");
      $cmd_def .= " DEF:$name=\"$rrd\":$rrd_name:AVERAGE";
      my $name_div = OracleDBDataWrapper::md5_string("name_div-$cur_hos-$alias");
      if ( $legend->{denom} == 1000000 ) {
        my $name_result = OracleDBDataWrapper::md5_string("name_result-$cur_hos-$alias");
        $cmd_cdef .= " CDEF:$name_result=$name,10000,LT,0,name-$cur_hos,IF";
        $cmd_cdef .= " CDEF:$name_div=$name_result,1000000,/";
      }
      else {
        $cmd_cdef .= " CDEF:$name_div=$name,$legend->{denom},/";
      }
      my $label = "";    #get_formatted_label("$instance_names->{$cur_host}-Avg CR");
      if ( $cur_hos == 0 ) {
        $cmd_legend .= " COMMENT:\"$legend->{brackets} " . ( ' ' x 20 ) . "Avrg      Max\\n\"";
        $color = get_color( $colors_ref, $g_number );
        $g_number++;
        $label = get_formatted_label("$instance_names->{$cur_host},$legend->{value}");
        $cmd_legend .= " AREA:$name_div" . "$color:\" $label\"";
      }
      else {
        $cmd_legend .= " COMMENT:\\n";
        $color = get_color( $colors_ref, $g_number );
        $g_number++;
        $label = get_formatted_label("$instance_names->{$cur_host},$legend->{value}");
        $cmd_legend .= " STACK:$name_div" . "$color:\" $label\"";
      }
      $cmd_legend .= " GPRINT:$name_div:AVERAGE:\" %6.1lf\"";
      $cmd_legend .= " GPRINT:$name_div:MAX:\" %6.1lf\"";
      my $temp_shajt = "$instance_names->{$cur_host},$host_names->{$cur_host},$alias";
      $cmd_legend .= " PRINT:$name_div:AVERAGE:\" %6.1lf $del $item $del $temp_shajt $del $color $del $rrd_name\"";
      $cmd_legend .= " PRINT:$name_div:MAX:\" %6.1lf $del $item $del $temp_shajt $del $cur_host \"";

      $cur_hos += 1;
    }
    $cmd_legend .= " COMMENT:\\n";
  }
  return {
    filepath => $rrd,     header   => $legend->{header}, reduced_header => "$server-$legend->{header}", cmd_params => $cmd_params,
    cmd_def  => $cmd_def, cmd_cdef => $cmd_cdef,         cmd_legend     => $cmd_legend,                 cmd_vlabel => $cmd_vlabel
  };
}

sub graph_test_total {
  my $acl_check  = shift;
  my $host       = shift;
  my $server     = shift;
  my $type       = shift;
  my $item       = shift;
  my $colors_ref = shift;
  my $g_number   = 0;
  my $rrd;
  $item =~ s/_Htotal//g;
  my $page       = basename( $item, '__' );
  my $legend     = OracleDBDataWrapper::graph_legend($page);
  my $rrd_name   = $legend->{rrd_vname};
  my $cmd_params = my $cmd_legend = my $cmd_cdef = my $cmd_def = my $cmd_vlabel = "";
  my $hosts_dir  = "$main_data_dir/Totals/Hosts";
  my $act_type   = $oracledbDataWrapper->get_type_from_page($page);
  my $file_end   = "$act_type.rrd";
  my @files;
  my $hosts_dbs;

  #  opendir( DH, $hosts_dir ) || Xorux_lib::error( "Could not open '$hosts_dir' for reading '$!'\n" );
  #  @files = sort( grep /.*.*$file_end/, readdir DH );
  #  closedir( DH );

  #TODO: might wanna lo0ok into changing rrd naming and how I work with it so far it seem like it may be really prone to error

  $cmd_vlabel .= " --vertical-label=\"$legend->{v_label}\"";
  if ($item =~ /CPU_Uti/ ) {
    $cmd_params .= " --upper-limit=100";
  }

  my $cur_hos = 0;
  ( $can_read, $ref ) = Xorux_lib::read_json("$main_data_dir/Totals/hosts_dbs.json");
  if ($can_read) {
    $hosts_dbs = $ref;
  }
  else {
    warn "Couldn't open $main_data_dir/Totals/hosts_dbs.json";
  }
  my $cur_host = "";
  my $color;
  my $host_number = 0;
  $cmd_legend .= " COMMENT:\"Host " . ( ' ' x 20 ) . "Avrg      Max\\n\"";
  for my $hostname ( keys %{$hosts_dbs} ) {
    my $db_number = 0;
    my $names     = "";
    foreach my $db ( @{ $hosts_dbs->{$hostname} } ) {
      unless ( $db =~ m/$file_end/ ) {
        next;
      }
      if ( -f "$hosts_dir/$db" ) {
        $rrd = "$hosts_dir/$db";
        $cmd_def .= " DEF:host-$host_number-db-$db_number=\"$rrd\":$rrd_name:AVERAGE";
        if ( $db_number == 0 ) {
          $names .= "host-$host_number-db-$db_number";
        }
        else {
          $names .= ",host-$host_number-db-$db_number";
        }
        $db_number++;
        if ( $page =~ /Host_CPU_Utilization/ ) {
          last;
        }
      }
      else {
        next;
      }
    }
    if ( $db_number <= 0 ) {
      next;
    }
    $cmd_cdef .= " CDEF:host-$host_number=$names,0" . ( ',+' x $db_number ) . ",$legend->{denom},/";
    my $label = "";    #get_formatted_label("$instance_names->{$cur_host}-Avg CR");
    $label = get_formatted_label("$hostname");
    if ( $page =~ /Host_CPU_Utilization/ ) {
      $color = get_color( $colors_ref, $g_number );
      $g_number++;
      $cmd_legend .= " LINE1:host-$host_number" . "$color:\" $label\"";
    }
    else {
      if ( $host_number == 0 ) {
        $color = get_color( $colors_ref, $g_number );
        $g_number++;
        $cmd_legend .= " AREA:host-$host_number" . "$color:\" $label\"";
      }
      else {
        $color = get_color( $colors_ref, $g_number );
        $g_number++;
        $cmd_legend .= " STACK:host-$host_number" . "$color:\" $label\"";
      }
    }
    $cmd_legend .= " GPRINT:host-$host_number:AVERAGE:\" %6.1lf\"";
    $cmd_legend .= " GPRINT:host-$host_number:MAX:\" %6.1lf\"";
    my $temp_shajt = "$hostname";
    $cmd_legend .= " PRINT:host-$host_number:AVERAGE:\" %6.1lf $del $item $del $temp_shajt $del $color $del $rrd_name\"";
    $cmd_legend .= " PRINT:host-$host_number:MAX:\" %6.1lf $del $item $del $temp_shajt $del $hostname \"";
    $cmd_legend .= " COMMENT:\\n";

    $host_number++;
  }
  $cmd_legend .= " COMMENT:\\n";
  return {
    filepath => $rrd,     header   => $legend->{header}, reduced_header => "$server-$legend->{header}", cmd_params => $cmd_params,
    cmd_def  => $cmd_def, cmd_cdef => $cmd_cdef,         cmd_legend     => $cmd_legend,                 cmd_vlabel => $cmd_vlabel
  };
}

sub graph_singlehost {
  my $acl_check = shift;
  my $host      = shift;
  my $server    = shift;
  my $type      = shift;
  my $item      = shift;
  my $g_number  = 0;
  my $rrd;
  my $color = "#";
  my $rrd;
  my $uuid = "";
  $color .= basename( $item, '_a_' );
  $item = substr( $item, 0, index( $item, '_a_' ) );
  my $page = basename( $item, '__' );
  $item = substr( $item, 0, index( $item, '__' ) );

  #my $page  = basename($item, '__');
  my $legend     = OracleDBDataWrapper::graph_legend($page);
  my $rrd_name   = $legend->{rrd_vname};
  my $cmd_params = my $cmd_legend = my $cmd_cdef = my $cmd_def = my $cmd_vlabel = "";
  my $hosts_dir  = "$main_data_dir/Totals/Hosts";
  my $act_type   = $oracledbDataWrapper->get_type_from_page($page);
  my $file_end   = "$act_type.rrd";
  my @files;
  my $hosts_dbs;

  $cmd_vlabel .= " --vertical-label=\"$legend->{v_label}\"";
  if ($item =~ /CPU_Uti/ ) {
    $cmd_params .= " --upper-limit=100";
  }

  my $cur_hos = 0;
  ( $can_read, $ref ) = Xorux_lib::read_json("$main_data_dir/Totals/hosts_dbs.json");
  if ($can_read) {
    $hosts_dbs = $ref;
  }
  else {
    warn "Couldn't open $main_data_dir/Totals/hosts_dbs.json";
  }
  my $cur_host    = "";
  my $host_number = 0;
  $cmd_legend .= " COMMENT:\"Hostname " . ( ' ' x 20 ) . "Avrg      Max\\n\"";
  my $hostname  = $host;
  my $db_number = 0;
  my $names     = "";
  foreach my $db ( @{ $hosts_dbs->{$hostname} } ) {
    unless ( $db =~ m/$file_end/ ) {
      next;
    }
    if ( -f "$hosts_dir/$db" ) {
      $rrd = "$hosts_dir/$db";
      $cmd_def .= " DEF:host-$host_number-db-$db_number=\"$rrd\":$rrd_name:AVERAGE";
      if ( $db_number == 0 ) {
        $names .= "host-$host_number-db-$db_number";
      }
      else {
        $names .= ",host-$host_number-db-$db_number";
      }
      $db_number++;
      if ( $page =~ /Host_CPU_Utilization/ ) {
        last;
      }
    }
    else {
      next;
    }
  }
  if ( $db_number <= 0 ) {
    next;
  }
  $cmd_cdef .= " CDEF:host-$host_number=$names,0" . ( ',+' x $db_number ) . ",$legend->{denom},/";
  my $label = "";    #get_formatted_label("$instance_names->{$cur_host}-Avg CR");
  $label = get_formatted_label("$hostname");
  $g_number++;
  $cmd_legend .= " LINE1:host-$host_number" . "$color:\" $label\"";
  $cmd_legend .= " GPRINT:host-$host_number:AVERAGE:\" %6.1lf\"";
  $cmd_legend .= " GPRINT:host-$host_number:MAX:\" %6.1lf\"";
  my $temp_shajt = "$hostname";
  $cmd_legend .= " COMMENT:\\n";

  #$host_number++;
  #$cmd_legend .= " COMMENT:\\n";
  return {
    filename => $rrd,     header   => $legend->{header}, reduced_header => "$server-$legend->{header}", cmd_params => $cmd_params,
    cmd_def  => $cmd_def, cmd_cdef => $cmd_cdef,         cmd_legend     => $cmd_legend,                 cmd_vlabel => $cmd_vlabel
  };
}

sub graph_db_total {
  my $acl_check  = shift;
  my $host       = shift;
  my $server     = shift;
  my $type       = shift;
  my $item       = shift;
  my $colors_ref = shift;
  my $host_names;
  my $g_number = 0;
  my $page     = basename( $item, '__' );
  $page =~ s/_DBTotal//g;
  my $rrd;
  my $legend     = OracleDBDataWrapper::graph_legend($page);
  my $rrd_name   = $legend->{rrd_vname};
  my $cmd_params = my $cmd_legend = my $cmd_cdef = my $cmd_def = my $cmd_vlabel = "";
  my ( $can_read_groups, $ref_groups, $groups, @act_groups, @host_aliases, %main_hash );

  $host =~ s/groups_//g;
  @act_groups = split( /,/, $host );
  if ( $server eq "custom" ) {

    $groups = OracleDBDataWrapper::process_custom_odb();
  }
  else {
    ( $can_read_groups, $ref_groups, $groups ) = Xorux_lib::read_json("$main_data_dir/Totals/groups.json");
    if ($can_read_groups) {
      $groups = $ref_groups;
    }
  }
  @host_aliases;
  %main_hash;
  if ( $act_groups[1] ) {
    if ( %{ $groups->{_mgroups}->{ $act_groups[0] }->{_sgroups}{ $act_groups[1] }->{_dbs} } ) {
      %main_hash    = %{ $groups->{_mgroups}->{ $act_groups[0] }->{_sgroups}{ $act_groups[1] }->{_dbs} };
      @host_aliases = keys %{ $groups->{_mgroups}->{ $act_groups[0] }->{_sgroups}{ $act_groups[1] }->{_dbs} };
    }
  }
  else {
    if ( %{ $groups->{_mgroups}->{ $act_groups[0] }->{_dbs} } ) {
      %main_hash    = %{ $groups->{_mgroups}->{ $act_groups[0] }->{_dbs} };
      @host_aliases = keys %{ $groups->{_mgroups}->{ $act_groups[0] }->{_dbs} };
    }
  }
  my $cur_hos = 0;
  foreach my $alias (@host_aliases) {
    if ( $server eq "custom" ) {
      if ( !-e $log_err_file && $cur_hos >= 4 ) {
        last;
      }
    }
    ( $can_read, $ref ) = Xorux_lib::read_json("$main_data_dir/$alias/instance_names.json");
    undef $instance_names;
    if ($can_read) {
      $instance_names = $ref;
    }
    else {
      next;
    }
    my $can_read_hosts;
    my $host_ref;
    ( $can_read_hosts, $host_ref ) = Xorux_lib::read_json("$main_data_dir/$alias/host_names.json");
    undef $host_names;
    if ($can_read_hosts) {
      $host_names = $host_ref;
    }
    my @hosts = @{ $main_hash{$alias} };
    $cmd_vlabel .= " --vertical-label=\"$legend->{v_label}\"";
    my $names = "";
    my $color;
    my $db_number = 0;
    foreach my $cur_host (@hosts) {
      undef $rrd;
      my $act_type_fp = $oracledbDataWrapper->get_type_from_page($page);
      $rrd = $oracledbDataWrapper->get_filepath_rrd( { type => $act_type_fp, uuid => $alias, acl_check => $acl_check, id => $cur_host } );
      $cmd_def .= " DEF:name-$cur_hos-db-$db_number=\"$rrd\":$rrd_name:AVERAGE";
      if ( $db_number == 0 ) {
        $names .= "name-$cur_hos-db-$db_number";
      }
      else {
        $names .= ",name-$cur_hos-db-$db_number";
      }
      $db_number++;
    }

    $cmd_cdef .= " CDEF:db-$cur_hos=$names,0" . ( ',+' x $db_number ) . ",$legend->{denom},/";

    my $label = "";    #get_formatted_label("$instance_names->{$cur_host}-Avg CR");
    if ( $cur_hos == 0 ) {
      $cmd_legend .= " COMMENT:\"$legend->{brackets} " . ( ' ' x 20 ) . "Avrg      Max\\n\"";
      $color = get_color( $colors_ref, $g_number );
      $g_number++;
      $label = get_formatted_label("$legend->{value}");
      $cmd_legend .= " AREA:db-$cur_hos" . "$color:\" $label\"";
    }
    else {
      $cmd_legend .= " COMMENT:\\n";
      $color = get_color( $colors_ref, $g_number );
      $g_number++;
      $label = get_formatted_label("$legend->{value}");
      $cmd_legend .= " STACK:db-$cur_hos" . "$color:\" $label\"";
    }
    $cmd_legend .= " GPRINT:db-$cur_hos:AVERAGE:\" %6.1lf\"";
    $cmd_legend .= " GPRINT:db-$cur_hos:MAX:\" %6.1lf\"";
    my $temp_shajt = "$alias";
    $cmd_legend .= " PRINT:db-$cur_hos:AVERAGE:\" %6.1lf $del $item $del $temp_shajt $del $color $del $rrd_name\"";
    $cmd_legend .= " PRINT:db-$cur_hos:MAX:\" %6.1lf $del $item $del $temp_shajt $del $alias \"";

    $cur_hos += 1;
    $cmd_legend .= " COMMENT:\\n";
  }
  return {
    filepath => $rrd,     header   => $legend->{header}, reduced_header => "$server-$legend->{header}", cmd_params => $cmd_params,
    cmd_def  => $cmd_def, cmd_cdef => $cmd_cdef,         cmd_legend     => $cmd_legend,                 cmd_vlabel => $cmd_vlabel
  };
}

sub graph_host_aggr {
  my $acl_check  = shift;
  my $host       = shift;
  my $server     = shift;
  my $type       = shift;
  my $item       = shift;
  my $colors_ref = shift;
  my $g_number   = 0;
  my $rrd;
  my $page       = basename( $item, '__' );
  my $legend     = OracleDBDataWrapper::graph_legend($page);
  my $rrd_name   = $legend->{rrd_vname};
  my $cmd_params = my $cmd_legend = my $cmd_cdef = my $cmd_def = my $cmd_vlabel = "";
  my $hosts_dir  = "$main_data_dir/Totals/Hosts";
  my $act_type   = $oracledbDataWrapper->get_type_from_page($page);
  my $file_end   = "-_-$act_type.rrd";
  my @files;
  $cmd_vlabel .= " --vertical-label=\"$legend->{v_label}\"";

  #$cmd_params .= " --lower-limit=0.00";
  #$cmd_params .= " --units-exponent=1.00";
  my $cur_hos = 0;
  ( $can_read, $ref ) = Xorux_lib::read_json("$main_data_dir/Totals/instance_names_total.json");
  undef $instance_names;
  if ($can_read) {
    $instance_names = $ref;
  }
  else {
    warn "Couldn't open $main_data_dir/Totals/instance_names_total.json";
  }
  my ( $can_read_hd, $ref_hd, $hosts_dbs ) = Xorux_lib::read_json("$main_data_dir/Totals/hosts_dbs.json");
  if ($can_read_hd) {
    $hosts_dbs = $ref_hd;
  }
  else {
    warn "Couldn't open $main_data_dir/Totals/hosts_dbs.json";
  }

  foreach my $db ( @{ $hosts_dbs->{$host} } ) {
    unless ( $db =~ m/$file_end/ ) {
      next;
    }
    my @dbname   = split( /-_-/, $db );
    my $alias    = $dbname[0];
    my $ip       = $dbname[1];
    my $cur_host = $ip;
    undef $rrd;
    my $color;

    #   $rrd = $oracledbDataWrapper->get_filepath_rrd_bpage($page, $alias, $cur_host);
    $rrd = "$hosts_dir/$db";
    $cmd_def .= " DEF:name-$cur_hos=\"$rrd\":$rrd_name:AVERAGE";
    if ( $legend->{denom} == 1000000 ) {
      $cmd_cdef .= " CDEF:name_result-$cur_hos=name-$cur_hos,10000,LT,0,name-$cur_hos,IF";
      $cmd_cdef .= " CDEF:name_div-$cur_hos=name_result-$cur_hos,1000000,/";
    }
    else {
      $cmd_cdef .= " CDEF:name_div-$cur_hos=name-$cur_hos,$legend->{denom},/";
    }
    my $label = "";    #get_formatted_label("$instance_names->{$cur_host}-Avg CR");
    if ( $cur_hos == 0 ) {
      $cmd_legend .= " COMMENT:\"$legend->{brackets} " . ( ' ' x 20 ) . "Avrg      Max\\n\"";
      $color = get_color( $colors_ref, $g_number );
      $g_number++;
      $label = get_formatted_label("$instance_names->{$alias}->{$cur_host},$legend->{value}");
      $cmd_legend .= " AREA:name_div-$cur_hos" . "$color:\" $label\"";
    }
    else {
      $cmd_legend .= " COMMENT:\\n";
      $color = get_color( $colors_ref, $g_number );
      $g_number++;
      $label = get_formatted_label("$instance_names->{$alias}->{$cur_host},$legend->{value}");
      $cmd_legend .= " STACK:name_div-$cur_hos" . "$color:\" $label\"";
    }
    $cmd_legend .= " GPRINT:name_div-$cur_hos:AVERAGE:\" %6.1lf\"";
    $cmd_legend .= " GPRINT:name_div-$cur_hos:MAX:\" %6.1lf\"";
    my $temp_shajt = "$host, $instance_names->{$alias}->{$cur_host}";
    my $hst_alias  = "$cur_host,$alias";
    $cmd_legend .= " PRINT:name_div-$cur_hos:AVERAGE:\" %6.1lf $del $item $del $temp_shajt $del $color $del $rrd_name\"";
    $cmd_legend .= " PRINT:name_div-$cur_hos:MAX:\" %6.1lf $del $item $del $temp_shajt $del $hst_alias \"";

    $cur_hos += 1;
  }
  $cmd_legend .= " COMMENT:\\n";
  return {
    filepath => $rrd,     header   => $legend->{header}, reduced_header => "$server-$legend->{header}", cmd_params => $cmd_params,
    cmd_def  => $cmd_def, cmd_cdef => $cmd_cdef,         cmd_legend     => $cmd_legend,                 cmd_vlabel => $cmd_vlabel
  };

}

1;
