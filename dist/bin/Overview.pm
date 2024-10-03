# Overview.pm
# interface for overview IBM Power data:

package Overview;

use strict;

use JSON;
use Data::Dumper;
use Xorux_lib qw(error read_json write_json);
use HostCfg;
use Digest::MD5 qw(md5 md5_hex md5_base64);
use Storable;
use POSIX qw(mktime strftime);

#use PowerDataWrapper;

defined $ENV{INPUTDIR} || Xorux_lib::error( "INPUTDIR undefined, config etc/lpar2rrd.cfg probably has not been loaded " . __FILE__ . ":" . __LINE__ ) && exit 1;
my $cpu_max_filter = 100;    # max 10k peak in % is allowed (in fact it cann by higher than 1k now when 1 logical CPU == 0.1 entitlement
if ( defined $ENV{CPU_MAX_FILTER} ) { $cpu_max_filter = $ENV{CPU_MAX_FILTER}; }

sub item_prep_to_rrd_graph {
  my $rrd  = shift;
  my $item = shift;
  my $cf   = shift;
  my $cmd  = "";
  if ( $item eq 'pool-total' || $item eq 'pool-total' ) {
    $cmd .= " DEF:capped=\"$rrd\":capped_cycles:$cf";
    $cmd .= " DEF:uncapped=\"$rrd\":uncapped_cycles:$cf";
    $cmd .= " DEF:entitled=\"$rrd\":entitled_cycles:$cf";
    $cmd .= " DEF:cur=\"$rrd\":curr_proc_units:$cf";
    $cmd .= " CDEF:tot=capped,uncapped,+";
    $cmd .= " CDEF:utl=tot,entitled,/";
    $cmd .= " CDEF:util=utl,cur,*";
  }
  return $cmd;
}

sub set_cmd {
  my $rrd  = shift;
  my $item = shift;
  my $cf   = shift;
  $rrd =~ s/:/\\:/g;
  my $eunix = time;
  my $sunix = $eunix - ( 86400 * 365 );

  #my $max_rows = 365;
  my $graph_cmd = "graph";
  if ( -f "$ENV{INPUTDIR}/tmp/graphv" ) {
    $graph_cmd = "graphv";    # if exists - call this function
  }
  my $STEP = 60 * 60 * 24;
  my $val  = 1;               # this can be used to convert values e.g.: from kB to MB -> value/1024

  my $cmd .= "$graph_cmd";
  if ( -f "$ENV{INPUTDIR}/tmp/rrdtool-xport-showtime" ) {

    # RRDTOOL: suported since 1.6, without that does not print timestamp like older 1.4 (1.5 does not support it)
    #$cmd .= " --showtime";
  }
  $cmd .= " --start $sunix";
  $cmd .= " --end $eunix";
  $cmd .= " --step $STEP";

  #$cmd .= " --maxrows $max_rows";

  my $cmd_tmp = item_prep_to_rrd_graph( $rrd, $item, $cf );
  my @metrics = @{ get_item_metrics($item) };
  $cmd .= $cmd_tmp;
  foreach my $metric (@metrics) {
    $cmd .= " $graph_cmd:$metric";
  }
  return $cmd;
}

sub get_item_metrics {
  my $item    = shift;
  my $metrics = [];
  if ( $item eq 'trendpool-total' || $item eq 'trendpool-total-max' ) {
    push @{$metrics}, "util";
  }
  return $metrics;
}

sub get_something {
  my $rrd      = shift;
  my $item     = shift;
  my $file_pth = shift;
  my $rrd_end  = shift;
  my $params   = shift;

  $file_pth .= $rrd_end;
  $rrd      .= $rrd_end;

  my $eunix;
  my $sunix;

  if ( defined $params->{sunix} && defined $params->{eunix} ) {
    $sunix = $params->{sunix};
    $eunix = $params->{eunix};
  }
  elsif ( defined $params->{timerange} ) {
    ( $sunix, $eunix ) = set_report_timerange( $params->{timerange} );
  }
  else {
    $eunix = time;
    $sunix = $eunix - ( 86400 * 365 );
  }

  #  $rrd =~ s/ /\ /g;
  #  $rrd =~ s/: /\:/g;

  #  $cmd .= "$graph_cmd \"$name_out\"";
  #  $cmd .= " --title \"$header\"";
  #  $cmd .= " --start $start_time";
  #  $cmd .= " --end $end_time";

  my $dummy = "/tmp/dummy";
  my $cmd   = "";
  if ( $item eq "pool" ) {
    my ( $result_cmd, $total_pool_cycles, $utilized_pool_cyc, $conf_proc_units, $bor_proc_units ) = LPM_easy( "AVERAGE", $file_pth, "0", "0", "total_pool_cycles", "utilized_pool_cyc", "conf_proc_units", "bor_proc_units" );
    $cmd .= "graphv $dummy";
    $cmd .= " --start $sunix";
    $cmd .= " --end $eunix";
    $cmd .= $result_cmd;

    $cmd .= " CDEF:totcyc=$total_pool_cycles";
    $cmd .= " CDEF:uticyc=$utilized_pool_cyc";
    $cmd .= " CDEF:cpu=$conf_proc_units";
    $cmd .= " CDEF:cpubor=$bor_proc_units";
    $cmd .= " CDEF:totcpu=cpu,cpubor,+";
    $cmd .= " CDEF:fail=uticyc,totcyc,GT,1,0,IF";
    $cmd .= " CDEF:cpuutil=uticyc,totcyc,GT,UNKN,uticyc,totcyc,/,IF";
    $cmd .= " CDEF:cpuutiltot=cpuutil,totcpu,*";
    $cmd .= " CDEF:utilisa=cpuutil,100,*";

    $cmd .= " PRINT:cpuutiltot:AVERAGE:%3.2lf";
    my $p_answ = run_rrdtool_cmd_eval($cmd);

    return $p_answ if defined $p_answ;
  }
  elsif ( $item eq "pool-max" ) {
    my ( $result_cmd, $total_pool_cycles, $utilized_pool_cyc, $conf_proc_units, $bor_proc_units ) = LPM_easy( "MAX", $file_pth, "0", "0", "total_pool_cycles", "utilized_pool_cyc", "conf_proc_units", "bor_proc_units" );
    $cmd .= "graphv $dummy";
    $cmd .= " --start $sunix";
    $cmd .= " --end $eunix";
    $cmd .= $result_cmd;

    $cmd .= " CDEF:totcyc=$total_pool_cycles";
    $cmd .= " CDEF:uticyc=$utilized_pool_cyc";
    $cmd .= " CDEF:cpu=$conf_proc_units";
    $cmd .= " CDEF:cpubor=$bor_proc_units";
    $cmd .= " CDEF:totcpu=cpu,cpubor,+";
    $cmd .= " CDEF:fail=uticyc,totcyc,GT,1,0,IF";
    $cmd .= " CDEF:cpuutil=uticyc,totcyc,GT,UNKN,uticyc,totcyc,/,IF";
    $cmd .= " CDEF:cpuutiltot=cpuutil,totcpu,*";
    $cmd .= " CDEF:utilisa=cpuutil,100,*";

    $cmd .= " PRINT:cpuutiltot:MAX:%3.2lf";
    my $p_answ = run_rrdtool_cmd_eval($cmd);
    return $p_answ if defined $p_answ;
  }
  elsif ( $item eq "pool-total" ) {
    my ( $result_cmd, $configured_avg, $curr_proc_units_avg, $entitled_avg, $capped_avg, $uncapped_avg ) = LPM_easy( "AVERAGE", $file_pth, "0", "0", "configured", "curr_proc_units", "entitled_cycles", "capped_cycles", "uncapped_cycles" );
    my $file_pth_pool = $file_pth;

    $file_pth_pool =~ s/pool_total.*/pool\.rrm/g;

    my ( $result_cmd_pool, $borrowed_avg ) = LPM_easy( "AVERAGE", $file_pth_pool, "1", "0", "bor_proc_units" );

    $cmd .= "graphv $dummy";
    $cmd .= " --start $sunix";
    $cmd .= " --end $eunix";
    $cmd .= $result_cmd;
    $cmd .= $result_cmd_pool;

    $cmd .= " CDEF:curr_proc_units_avg=$curr_proc_units_avg,1,*";
    $cmd .= " CDEF:entitled_avg=$entitled_avg,1,*";
    $cmd .= " CDEF:capped_avg=$capped_avg,1,*";
    $cmd .= " CDEF:uncapped_avg=$uncapped_avg,1,*";
    $cmd .= " CDEF:configured_avg=$configured_avg,1,*";

    # to simulate lower configured - comment above line, uncomment following line
    #$cmd .= " CDEF:configured_avg=$configured_avg,0.5,*";

    #borrowed
    $cmd .= " CDEF:borrowed_avg=$borrowed_avg,1,*";
    $cmd .= " CDEF:ded_ent_avg=configured_avg,borrowed_avg,-";

    $cmd .= " CDEF:tot_avg=capped_avg,uncapped_avg,+";
    $cmd .= " CDEF:util_avg=tot_avg,entitled_avg,/,$cpu_max_filter,GT,UNKN,tot_avg,entitled_avg,/,IF";
    $cmd .= " CDEF:utilperct_avg=util_avg,100,*";
    $cmd .= " CDEF:utiltot_avg_peak=util_avg,curr_proc_units_avg,*";

    # there are sometimes peaks in utiltot higher than configured
    # replace them for -nan
    $cmd .= " CDEF:utiltot_avg=utiltot_avg_peak,configured_avg,GT,UNKN,utiltot_avg_peak,IF";

    $cmd .= " PRINT:utiltot_avg:AVERAGE:%3.2lf";
    my $p_answ = run_rrdtool_cmd_eval($cmd);

    return $p_answ if defined $p_answ;
  }
  elsif ( $item eq "pool-total-max" ) {
    my ( $result_cmd, $configured_max, $curr_proc_units_max, $entitled_max, $capped_max, $uncapped_max ) = LPM_easy( "MAX", $file_pth, "0", "0", "configured", "curr_proc_units", "entitled_cycles", "capped_cycles", "uncapped_cycles" );
    my $file_pth_pool = $file_pth;

    $file_pth_pool =~ s/pool_total.*/pool\.xrm/g;

    my ( $result_cmd_pool, $borrowed_max ) = LPM_easy( "MAX", $file_pth_pool, "1", "0", "bor_proc_units" );

    $cmd .= "graphv $dummy";
    $cmd .= " --start $sunix";
    $cmd .= " --end $eunix";
    $cmd .= $result_cmd;
    $cmd .= $result_cmd_pool;

    $cmd .= " CDEF:curr_proc_units_max=$curr_proc_units_max,1,*";
    $cmd .= " CDEF:entitled_max=$entitled_max,1,*";
    $cmd .= " CDEF:capped_max=$capped_max,1,*";
    $cmd .= " CDEF:uncapped_max=$uncapped_max,1,*";
    $cmd .= " CDEF:configured_max=$configured_max,1,*";

    # to simulate lower configured - comment above line, uncomment following line
    #$cmd .= " CDEF:configured_max=$configured_max,0.5,*";

    #borrowed
    $cmd .= " CDEF:borrowed_max=$borrowed_max,1,*";
    $cmd .= " CDEF:ded_ent_max=configured_max,borrowed_max,-";

    $cmd .= " CDEF:tot_max=capped_max,uncapped_max,+";
    $cmd .= " CDEF:util_max=tot_max,entitled_max,/,$cpu_max_filter,GT,UNKN,tot_max,entitled_max,/,IF";
    $cmd .= " CDEF:utilperct_max=util_max,100,*";
    $cmd .= " CDEF:utiltot_max_peak=util_max,curr_proc_units_max,*";

    # there are sometimes peaks in utiltot higher than configured
    # replace them for -nan
    $cmd .= " CDEF:utiltot_max=utiltot_max_peak,configured_max,GT,UNKN,utiltot_max_peak,IF";

    $cmd .= " PRINT:utiltot_max:MAX:%3.2lf";
    my $p_answ = run_rrdtool_cmd_eval($cmd);

    return $p_answ if defined $p_answ;
  }
  elsif ( $item eq "mem" ) {
    my ( $result_cmd, $curr_avail_mem, $sys_firmware_mem, $conf_sys_mem ) = LPM_easy( "AVERAGE", $file_pth, "0", "0", "curr_avail_mem", "sys_firmware_mem", "conf_sys_mem" );
    $cmd .= "graphv $dummy";
    $cmd .= " --start $sunix";
    $cmd .= " --end $eunix";
    $cmd .= $result_cmd;

    $cmd .= " CDEF:free=$curr_avail_mem";
    $cmd .= " CDEF:fw=$sys_firmware_mem";
    $cmd .= " CDEF:tot=$conf_sys_mem";
    $cmd .= " CDEF:freeg=free,1024,/";
    $cmd .= " CDEF:fwg=fw,1024,/";
    $cmd .= " CDEF:totg=tot,1024,/";
    $cmd .= " CDEF:used=totg,freeg,-";
    $cmd .= " CDEF:used1=used,fwg,-";

    $cmd .= " PRINT:used1:AVERAGE:%3.2lf";
    my $p_answ = run_rrdtool_cmd_eval($cmd);
    return $p_answ if defined $p_answ;
  }
  elsif ( $item eq "mem-max" ) {
    my ( $result_cmd, $curr_avail_mem, $sys_firmware_mem, $conf_sys_mem ) = LPM_easy( "AVERAGE", $file_pth, "0", "0", "curr_avail_mem", "sys_firmware_mem", "conf_sys_mem" );
    $cmd .= "graphv $dummy";
    $cmd .= " --start $sunix";
    $cmd .= " --end $eunix";
    $cmd .= $result_cmd;

    $cmd .= " CDEF:free=$curr_avail_mem";
    $cmd .= " CDEF:fw=$sys_firmware_mem";
    $cmd .= " CDEF:tot=$conf_sys_mem";
    $cmd .= " CDEF:freeg=free,1024,/";
    $cmd .= " CDEF:fwg=fw,1024,/";
    $cmd .= " CDEF:totg=tot,1024,/";
    $cmd .= " CDEF:used=totg,freeg,-";
    $cmd .= " CDEF:used1=used,fwg,-";

    $cmd .= " PRINT:used1:MAX:%3.2lf";
    my $p_answ = run_rrdtool_cmd_eval($cmd);
    return $p_answ if defined $p_answ;
  }
  elsif ( $item eq "lpar-cpu-avg" ) {
    my ( $result_cmd, $capped_cycles, $uncapped_cycles, $entitled_cycles, $curr_proc_units ) = LPM_easy( "AVERAGE", $file_pth, "0", "0", "capped_cycles", "uncapped_cycles", "entitled_cycles", "curr_proc_units" );
    $cmd .= "graphv $dummy";
    $cmd .= " --start $sunix";
    $cmd .= " --end $eunix";
    $cmd .= $result_cmd;

    $cmd .= " CDEF:capped=$capped_cycles";
    $cmd .= " CDEF:uncapped=$uncapped_cycles";
    $cmd .= " CDEF:entitled=$entitled_cycles";
    $cmd .= " CDEF:cur=$curr_proc_units";
    $cmd .= " CDEF:tot=capped,uncapped,+";
    $cmd .= " CDEF:utl=tot,entitled,/";
    $cmd .= " CDEF:util=utl,cur,*";

    $cmd .= " PRINT:util:AVERAGE:%3.2lf";

    my $p_answ = run_rrdtool_cmd_eval($cmd);
    return $p_answ if defined $p_answ;
  }
  elsif ( $item eq "lpar-cpu-avg" ) {
    my ( $result_cmd, $capped_cycles, $uncapped_cycles, $entitled_cycles, $curr_proc_units ) = LPM_easy( "AVERAGE", $file_pth, "0", "0", "capped_cycles", "uncapped_cycles", "entitled_cycles", "curr_proc_units" );
    $cmd .= "graphv $dummy";
    $cmd .= " --start $sunix";
    $cmd .= " --end $eunix";
    $cmd .= $result_cmd;

    $cmd .= " CDEF:capped=$capped_cycles";
    $cmd .= " CDEF:uncapped=$uncapped_cycles";
    $cmd .= " CDEF:entitled=$entitled_cycles";
    $cmd .= " CDEF:cur=$curr_proc_units";
    $cmd .= " CDEF:tot=capped,uncapped,+";
    $cmd .= " CDEF:utl=tot,entitled,/";
    $cmd .= " CDEF:util=utl,cur,*";

    $cmd .= " PRINT:util:AVERAGE:%3.2lf";
    my $p_answ = run_rrdtool_cmd_eval($cmd);
    return $p_answ if defined $p_answ;
  }
  elsif ( $item eq "lpar-cpu-max" ) {
    my ( $result_cmd, $capped_cycles, $uncapped_cycles, $entitled_cycles, $curr_proc_units ) = LPM_easy( "MAX", $file_pth, "0", "0", "capped_cycles", "uncapped_cycles", "entitled_cycles", "curr_proc_units" );
    $cmd .= "graphv $dummy";
    $cmd .= " --start $sunix";
    $cmd .= " --end $eunix";
    $cmd .= $result_cmd;

    $cmd .= " CDEF:capped=$capped_cycles";
    $cmd .= " CDEF:uncapped=$uncapped_cycles";
    $cmd .= " CDEF:entitled=$entitled_cycles";
    $cmd .= " CDEF:cur=$curr_proc_units";
    $cmd .= " CDEF:tot=capped,uncapped,+";
    $cmd .= " CDEF:utl=tot,entitled,/";
    $cmd .= " CDEF:util=utl,cur,*";

    $cmd .= " PRINT:util:MAX:%3.2lf";
    my $p_answ = run_rrdtool_cmd_eval($cmd);
    return $p_answ if defined $p_answ;
  }
  elsif ( $item eq "lpar-mem-avg" ) {
    my ( $result_cmd, $curr_mem ) = LPM_easy( "AVERAGE", $file_pth, "0", "0", "curr_mem" );
    $cmd .= "graphv $dummy";
    $cmd .= " --start $sunix";
    $cmd .= " --end $eunix";
    $cmd .= $result_cmd;

    $cmd .= " CDEF:curr_mem=$curr_mem";

    $cmd .= " PRINT:curr_mem:AVERAGE:%3.2lf";

    my $p_answ = run_rrdtool_cmd_eval($cmd);
    return $p_answ if defined $p_answ;
  }
  elsif ( $item eq "lpar-mem-max" ) {
    my ( $result_cmd, $curr_mem ) = LPM_easy( "MAX", $file_pth, "0", "0", "curr_mem" );
    $cmd .= "graphv $dummy";
    $cmd .= " --start $sunix";
    $cmd .= " --end $eunix";
    $cmd .= $result_cmd;

    $cmd .= " CDEF:curr_mem=$curr_mem";

    $cmd .= " PRINT:curr_mem:MAX:%3.2lf";

    my $p_answ = run_rrdtool_cmd_eval($cmd);
    return $p_answ if defined $p_answ;
  }
  elsif ( $item eq "shpool-cpu" ) {
    my ( $result_cmd, $max_pool_units, $res_pool_units, $total_pool_cycles, $utilized_pool_cyc ) = LPM_easy( "AVERAGE", "$file_pth", "0", "0", "max_pool_units", "res_pool_units", "total_pool_cycles", "utilized_pool_cyc" );
    $cmd .= "graphv $dummy";
    $cmd .= " --start $sunix";
    $cmd .= " --end $eunix";

    $cmd .= $result_cmd;

    $cmd .= " CDEF:max=\"$max_pool_units\"";
    $cmd .= " CDEF:res=\"$res_pool_units\"";
    $cmd .= " CDEF:totcyc=\"$total_pool_cycles\"";
    $cmd .= " CDEF:uticyc=\"$utilized_pool_cyc\"";
    $cmd .= " CDEF:max1=max,res,-";
    $cmd .= " CDEF:cpuutil=uticyc,totcyc,GT,UNKN,uticyc,totcyc,/,IF";
    $cmd .= " CDEF:cpuutiltot=cpuutil,max,*";
    $cmd .= " CDEF:utilisa=cpuutil,100,*";

    $cmd .= " PRINT:cpuutiltot:AVERAGE:%3.2lf";
    $cmd =~ s/\\\\/\\/g;

    my $p_answ = run_rrdtool_cmd_eval($cmd);
    return $p_answ if defined $p_answ;

  }
  elsif ( $item eq "shpool-cpu-max" ) {
    my ( $result_cmd, $max_pool_units, $res_pool_units, $total_pool_cycles, $utilized_pool_cyc ) = LPM_easy( "MAX", $file_pth, "0", "0", "max_pool_units", "res_pool_units", "total_pool_cycles", "utilized_pool_cyc" );
    $cmd .= "graphv $dummy";
    $cmd .= " --start $sunix";
    $cmd .= " --end $eunix";

    $cmd .= $result_cmd;

    $cmd .= " CDEF:max=$max_pool_units";
    $cmd .= " CDEF:res=$res_pool_units";
    $cmd .= " CDEF:totcyc=$total_pool_cycles";
    $cmd .= " CDEF:uticyc=$utilized_pool_cyc";
    $cmd .= " CDEF:max1=max,res,-";
    $cmd .= " CDEF:cpuutil=uticyc,totcyc,GT,UNKN,uticyc,totcyc,/,IF";
    $cmd .= " CDEF:cpuutiltot=cpuutil,max,*";
    $cmd .= " CDEF:utilisa=cpuutil,100,*";

    $cmd .= " PRINT:cpuutiltot:MAX:%3.2lf";
    $cmd =~ s/\\\\/\\/g;

    my $p_answ = run_rrdtool_cmd_eval($cmd);
    return $p_answ if defined $p_answ;
  }
  else {
    print STDERR "NO ITEM or $item ???\n";
  }
  return [];
}

sub run_rrdtool_cmd_eval {
  my $cmd = shift;
  my $answ;
  eval {
    RRDp::cmd qq($cmd);
    my $answer = RRDp::read;
    $answ = parse_answer($answer);
  };
  if ($@) {
    print STDERR "Error cgi overview of $cmd : $@ @ " . __FILE__ . ":" . __LINE__ . "\n";
  }
  return $answ;
}

sub parse_answer {

  my $in = shift;
  my @output;

  my $tmp    = "";
  my $ref_in = ref($in);
  if ( $ref_in eq "SCALAR" ) {
    $tmp = $$in;
  }
  elsif ( $ref_in eq "HASH" || $ref_in eq "ARRAY" ) {
    print STDERR "Overview.pm expected scalar, got arr or hash ref. Return empty array instead at " . __FILE__ . ":" . __LINE__ . "\n";
    return \@output;
  }
  else {
    $tmp = $in;
  }

  if ( !defined $tmp || $tmp eq "" ) {
    return \@output;
  }

  my @lines = split( "\n", $tmp );

  foreach my $l (@lines) {
    my ( $index, $val ) = split( "=", $l );
    $index =~ s/^print\[//g;
    $index =~ s/\] $//g;
    $val   =~ s/^ \"//g;
    $val   =~ s/"$//g;
    push @output, $val;
  }

  return \@output;
}

sub LPM_easy {

  # this is for case e.g. HMC change, similar to LPM
  # join data streams from rrd files in one data_stream
  # call:
  #  my ($result_cmd,$result_stream_1,...,$result_stream_x) = LPM_easy($path_to_find_files,$var_indx,$req_time,$data_stream_1,...,$data_stream_x);
  # no limit for x
  # $result_cmd is CMD string for RRD
  my $cf       = shift;
  my $file_pth = shift @_;    # path to find files
  my $var_indx = shift @_;    # to make variables unique in aggregated graphs
  my $req_time = shift @_;    # only files with newer timestamp are taken into consideration
  $file_pth =~ s/ /\\ /g;
  my $no_name = "";

  my @files    = (<$file_pth$no_name>);    # unsorted, workaround for space in names
                                           # print STDERR "found pool files: @files\n";
  my @ds       = @_;
  my $item_uid = "";

  #print STDERR "000 in sub LPM_easy \@ds @ds\n";

  # prepare help variables
  my $prep_names = "";
  for ( my $x = 0; $x < @ds; $x++ ) { $prep_names .= "var" . $var_indx . $x . "," }
  my @ids = split( ",", "$prep_names" );
  $prep_names = "";
  for ( my $x = 0; $x < @ds; $x++ ) { $prep_names .= "var_r" . $var_indx . $x . "," }
  my @rids = split( ",", "$prep_names" );

  my $i = -1;
  my $j;
  my $rrd = "";
  my $cmd = "";

  foreach my $rrd (@files) {    # LPM alias cycle
    chomp($rrd);
    if ( $req_time > 0 ) {
      my $rrd_upd_time = ( stat("$rrd") )[9];
      if ( $rrd_upd_time < $req_time ) {
        next;
      }
    }

    $i++;
    $j = $i - 1;
    $rrd =~ s/\:/\\:/g;
    $rrd =~ s/\:/\\:/g if ( $rrd =~ m/SharedPool/ );
    for ( my $k = 0; $k < @ds; $k++ ) { $cmd .= " DEF:$ids[$k]${i}=\"$rrd\":$ds[$k]:$cf"; }

    if ( $i == 0 ) {
      for ( my $k = 0; $k < @ds; $k++ ) { $cmd .= " CDEF:$rids[$k]${i}=$ids[$k]${i}"; }
      next;
    }
    for ( my $k = 0; $k < @ds; $k++ ) { $cmd .= " CDEF:$rids[$k]${i}=$rids[$k]${j},UN,$ids[$k]${i},$rids[$k]${j},IF"; }
  }

  if ( $i == -1 ) {

    # no fresh file has been found, do it once more qithout restriction to show at least the empty graph
    foreach my $rrd (@files) {    # LPM alias cycle
      chomp($rrd);
      $i++;
      $j = $i - 1;
      $rrd =~ s/\:/\\:/g;
      $rrd =~ s/\:/\\:/g if ( $rrd =~ m/SharedPool/ );
      for ( my $k = 0; $k < @ds; $k++ ) { $cmd .= " DEF:$ids[$k]${i}=\"$rrd\":$ds[$k]:$cf"; }

      if ( $i == 0 ) {
        for ( my $k = 0; $k < @ds; $k++ ) { $cmd .= " CDEF:$rids[$k]${i}=$ids[$k]${i}"; }
        next;
      }
      for ( my $k = 0; $k < @ds; $k++ ) { $cmd .= " CDEF:$rids[$k]${i}=$rids[$k]${j},UN,$ids[$k]${i},$rids[$k]${j},IF"; }
    }
  }

  my $ret_string = "";
  for ( my $k = 0; $k < @ds; $k++ ) {
    $ret_string .= "$rids[$k]${i},";
  }

  #print STDERR "001 $cmd,split(",",$ret_string)\n";
  return ( $cmd, split( ",", $ret_string ) );
}

sub set_report_timerange {
  my $time  = shift;
  my $sunix = "";
  my $eunix = "";

  my $day_sec  = 60 * 60 * 24;
  my $act_time = time();
  my ( $act_sec, $act_min, $act_hour, $act_day, $act_month, $act_year, $act_wday, $act_yday, $act_isdst ) = localtime();

  if ( $time eq "prevHour" ) {
    $eunix = mktime( 0, 0, $act_hour, $act_day, $act_month, $act_year );
    $sunix = $eunix - ( 60 * 60 );
  }
  elsif ( $time eq "prevDay" || $time eq "d" ) {
    $eunix = mktime( 0, 0, 0, $act_day, $act_month, $act_year );
    $sunix = $eunix - $day_sec;

    ( $sunix, $eunix ) = adjust_timerange( $sunix, $eunix );
  }
  elsif ( $time eq "prevWeek" || $time eq "w" ) {
    $eunix = mktime( 0, 0, 0, $act_day, $act_month, $act_year );
    $eunix = $eunix - ( ( $act_wday - 1 ) * $day_sec );
    $sunix = $eunix - ( 7 * $day_sec );

    ( $sunix, $eunix ) = adjust_timerange( $sunix, $eunix );
  }
  elsif ( $time eq "prevMonth" || $time eq "m" ) {
    $sunix = mktime( 0, 0, 0, 1, $act_month - 1, $act_year );
    $eunix = mktime( 0, 0, 0, 1, $act_month,     $act_year );

    ( $sunix, $eunix ) = adjust_timerange( $sunix, $eunix );
  }
  elsif ( $time eq "prevYear" || $time eq "y" ) {
    $sunix = mktime( 0, 0, 0, 1, 0, $act_year - 1 );
    $eunix = mktime( 0, 0, 0, 1, 0, $act_year );

    ( $sunix, $eunix ) = adjust_timerange( $sunix, $eunix );
  }
  elsif ( $time eq "lastHour" ) {
    $eunix = $act_time;
    $sunix = $eunix - ( 60 * 60 );
  }
  elsif ( $time eq "lastDay" ) {
    $eunix = $act_time;
    $sunix = $eunix - $day_sec;
  }
  elsif ( $time eq "lastWeek" ) {
    $eunix = $act_time;
    $sunix = $eunix - ( $day_sec * 7 );
  }
  elsif ( $time eq "lastMonth" ) {
    $sunix = mktime( $act_sec, $act_min, $act_hour, $act_day, $act_month - 1, $act_year );
    $eunix = $act_time;
  }
  elsif ( $time eq "lastYear" ) {
    $sunix = mktime( $act_sec, $act_min, $act_hour, $act_day, $act_month, $act_year - 1 );
    $eunix = $act_time;
  }
  else {
    Xorux_lib::error( "Cannot set report timerange! Unsupported time='$time'! $!" . __FILE__ . ":" . __LINE__ ) && exit;
  }

  return ( $sunix, $eunix ) if ( defined $sunix && defined $eunix );
  return ( 1,      2 );
}

sub adjust_timerange {

  # perl <5.12 has got some problems on aix with DST (daylight saving time)
  # sometimes there is one hour difference
  # therefore align the time to midnight again

  my $sunix = shift;
  my $eunix = shift;

  my ( $s_sec, $s_min, $s_hour, $s_day, $s_month, $s_year, $s_wday, $s_yday, $s_isdst ) = localtime($sunix);
  $sunix = mktime( 0, 0, 0, $s_day, $s_month, $s_year, $s_wday, $s_yday, $s_isdst );
  my ( $e_sec, $e_min, $e_hour, $e_day, $e_month, $e_year, $e_wday, $e_yday, $e_isdst ) = localtime($eunix);
  $eunix = mktime( 0, 0, 0, $e_day, $e_month, $e_year, $e_wday, $e_yday, $e_isdst );

  return ( $sunix, $eunix );

  return 1;
}

1;
