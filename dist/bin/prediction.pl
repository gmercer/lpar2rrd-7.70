use strict;
use warnings;
use Date::Parse;
use POSIX qw(strftime);
use File::Basename;
use MIME::Base64 qw(encode_base64 decode_base64);
use CGI::Carp qw(fatalsToBrowser);
use Xorux_lib;
use Prediction;
use JSON qw(encode_json decode_json);
use RRDp;
use PowerDataWrapper;
use PowerMenu;
use Data::Dumper;
use RRDDump;
use File::Copy;
use File::Glob qw(bsd_glob GLOB_TILDE);

my $DEBUG   = $ENV{DEBUG};
my $errlog  = $ENV{ERRLOG};
my $rrdtool = $ENV{RRDTOOL};
RRDp::start "$rrdtool";

my $useacl;

if ( !$ENV{XORMON} ) {
  use ACL;    # use module ACL.pm
  $useacl = ACL::useACL;
}

my $basedir = $ENV{INPUTDIR};
my $tmp_dir = "$basedir/tmp";

print "Content-type: application/json\n\n";

if ( !defined $rrdtool || $rrdtool eq "" ) {
  warn("RRDTOOL does not defined");
  print '{"status" : "RRDTOOL is not defined"}';
  exit 1;
}

my $threshold2 = 90;
if ( $ENV{CPU_THRESHOLD} ) {
  $threshold2 = $ENV{CPU_THRESHOLD};
}
my $c = $threshold2 / 100;
if ( $ENV{DEMO} ) {
  my $file = "$basedir/etc/demo-prediction.json";
  my $string;
  my $output;
  {
    local $/ = undef;
    open( my $file, '<', $file ) or exit 1;
    $string = <$file>;
    close $file;
  }
  if ($string) {
    print $string;
  }
  else {
    print '{}';
  }
  exit 0;
}
if ( defined $ENV{PREDICTION} ) {
  my ( $SERV, $CONF ) = PowerDataWrapper::init();    #(Storable::retrieve("$basedir/tmp/servers_conf.storable"), Storable::retrieve("$basedir/tmp/power_conf.storable"));
  my $file = "$basedir/www/smart_trends.html";
  if ( !once_a_day("$file") ) {
    exit;
  }
  open( my $table, ">", "$file-tmp" );
  my $metrics = [ "Server", "Pool", "CPU Cores" ];
  if ( !Xorux_lib::isdigit($threshold2) ) {
    warn "Error: threshold is 0 or not number : \'$threshold2\'\n";
    print "{\"status\" : \"Error: threshold is 0 or not number : $threshold2\"}";
    exit(1);
  }
  else {
    push( @{$metrics}, "Days to $threshold2%" );
  }
  push @{$metrics}, "Days to 100%";
  push @{$metrics}, "Smart Trend";

  print $table "<center>\n";
  print $table "<h2 id=\"title\" style=\"display: block;\">Smart Trends (based on average data)</h2>";

  print_header_table( $table, $metrics );

  print_body_table( $table, $metrics );

  print_footer_table( $table, $metrics );
  print $table "</center>\n";

  close($table);
  copy( "$file-tmp", "$file" );
  unlink("$file-tmp");

  exit;
}

sub print_header_table {
  my $fh  = shift;
  my $met = shift;
  print $fh '<TABLE class="captab tabconfig tablesorter tablesorter-ice tablesorter5f3418770156d"><thead class="chead"><TR class="tablesorter-headerRow">' . "\n";
  foreach my $metric ( @{$met} ) {
    print $fh " <TH class=\"sortable tablesorter-header tablesorter-headerAsc\" valign=\"center\">$metric</TH>\n";
  }
  print $fh '</TR></thead>';
}

sub print_body_table {
  my $fh  = shift;
  my $met = shift;
  print $fh '<tbody class="cdata" aria-live="polite" aria-relevant="all">' . "\n";

  my $servers = PowerDataWrapper::get_items("SERVER");
  my $data;
  foreach my $server_hash ( @{$servers} ) {
    my $server_uid = ( keys %{$server_hash} )[0];
    my $server     = $server_hash->{$server_uid};
    $data->{$server}{total}{'CPU Cores'}   = PowerDataWrapper::get_server_metric( $server, "ConfigurableSystemProcessorUnits", 0 );
    $data->{$server}{total}{'Smart Trend'} = "";
    $data->{$server}{total}{'Pool'}        = "Total Pool";

    my $data_out_total = get_prediction_from_server_total_pool( $server, "trendpool-total" );
    $data->{$server}{total}{'Days to 100%'} = Prediction::get_days_to_value_by_array( $data_out_total, $data->{$server}{total}{'CPU Cores'}, "max" );
    if ( $data->{$server}{total}{'Days to 100%'} == -1 ) {
      $data->{$server}{total}{'Days to 100%'} = "365+";
    }
    elsif ( $data->{$server}{total}{'Days to 100%'} == -2 ) {
      $data->{$server}{total}{'Days to 100%'} = "n/a";
    }

    $data->{$server}{total}{"Days to $threshold2%"} = Prediction::get_days_to_value_by_array( $data_out_total, $data->{$server}{total}{'CPU Cores'} * $c, "max" );
    if ( $data->{$server}{total}{"Days to $threshold2%"} == -1 ) {
      $data->{$server}{total}{"Days to $threshold2%"} = "365+";
    }
    elsif ( $data->{$server}{total}{"Days to $threshold2%"} == -2 ) {
      $data->{$server}{total}{"Days to $threshold2%"} = "n/a";
    }
    my $curr_pool_lim_json = [];
    $curr_pool_lim_json = Xorux_lib::read_json("$basedir/tmp/curr_pool_lim_cpu_$server.json") if ( -e "$basedir/tmp/curr_pool_lim_cpu_$server.json" );
    my $lim = 0;
    $lim = $curr_pool_lim_json->[0] if ( defined $curr_pool_lim_json->[0] );

    $data->{$server}{pool}{'CPU Cores'}   = $lim;
    $data->{$server}{pool}{'Smart Trend'} = "";
    $data->{$server}{pool}{'Pool'}        = "CPU Pool";

    my $data_out_pool = get_prediction_from_server_pool( $server, "trendpool" );
    $data->{$server}{pool}{'Days to 100%'} = Prediction::get_days_to_value_by_array( $data_out_pool, $lim, "max" );
    if ( $data->{$server}{pool}{'Days to 100%'} == -1 ) {
      $data->{$server}{pool}{'Days to 100%'} = "365+";
    }
    elsif ( $data->{$server}{pool}{'Days to 100%'} == -2 ) {
      $data->{$server}{pool}{'Days to 100%'} = "n/a";
    }

    $data->{$server}{pool}{"Days to $threshold2%"} = Prediction::get_days_to_value_by_array( $data_out_pool, $data->{$server}{pool}{'CPU Cores'} * $c, "max" );
    if ( $data->{$server}{pool}{"Days to $threshold2%"} == -1 ) {
      $data->{$server}{pool}{"Days to $threshold2%"} = "365+";
    }
    elsif ( $data->{$server}{pool}{"Days to $threshold2%"} == -2 ) {
      $data->{$server}{pool}{"Days to $threshold2%"} = "n/a";
    }
  }

  my $color = "odd";
  foreach my $server_hash ( @{$servers} ) {
    my $server_uid = ( keys %{$server_hash} )[0];
    my $server     = $server_hash->{$server_uid};
    print $fh "<tr role=\"row\" class=\"$color\">\n";
    print $fh "<td class='tdr'>$server</td>\n";
    foreach my $metric ( @{$met} ) {
      if ( $metric eq $met->[0] ) { next; }
      if ( $metric eq "Smart Trend" ) {
        print $fh "<td class='tdr'><a style='width:100%; display:block; font-size: 15px;' class='fas fa-chart-line' href=\"/lpar2rrd-cgi/detail-graph.sh?host=vhmc&server=$server&lpar=pool&item=pool&tab=0\"></a> </td>\n";
      }
      else {
        if ( defined $data->{$server}{total}{$metric} ) {
          print $fh "<td class='tdr'> $data->{$server}{total}{$metric} </td>\n";
        }
        else {
          print $fh "<td class='tdr'>  </td>\n";
        }
      }
    }
    print $fh "</tr><tr>\n";
    print $fh "<td class='tdr'>$server</td>\n";
    foreach my $metric ( @{$met} ) {
      if ( $metric eq $met->[0] ) { next; }
      if ( $metric eq "Smart Trend" ) {
        print $fh "<td class='tdr'><a style='width:100%; display:block; font-size: 15px;' class='fas fa-chart-line' href=\"/lpar2rrd-cgi/detail-graph.sh?host=vhmc&server=$server&lpar=pool&item=pool&tab=2\"></a> </td>\n";
      }
      else {
        if ( defined $data->{$server}{pool}{$metric} ) {
          print $fh "<td class='tdr'> $data->{$server}{pool}{$metric} </td>\n";
        }
        else {
          print $fh "<td class='tdr'>  </td>\n";
        }
      }
    }
    print $fh "</tr>\n";
  }

  print $fh '</tbody>';

}

sub print_footer_table {
  my $fh = shift;
  print $fh "</TABLE>\n";

}

###########################################################

# decode URL
my $query_string = Xorux_lib::urldecode( $ENV{'QUERY_STRING'} );
$query_string =~ s/^.*host/host/g;
my %url_params = %{ Xorux_lib::parse_url_params($query_string) };

my %data_merge;
my @data_out = [];
my $json;
my $t = [];
if ( $url_params{item} eq 'trendpool-total' || $url_params{item} eq 'trendpool-total-max' ) {
  my $max = 0;
  if ( $url_params{item} =~ 'max' ) { $max = 1; }

  my $file_pth = "$basedir/data/$url_params{server}/*/pool_total.rrt";
  $file_pth = "$basedir/data/$url_params{server}/*/pool_total.rxm" if ($max);

  my $cf = "AVERAGE";
  $cf = "MAX" if ($max);
  $file_pth =~ s/ /\\ /g;
  my @files = bsd_glob("$file_pth");
  foreach my $file (@files) {

    my $cmd   = set_cmd( "$file", "$url_params{item}", $cf );
    my $xport = get_rrd_xport($cmd);

    my %data = xport_to_hash( $xport, "$url_params{item}" );
    %data_merge = %{ merge_data( \%data_merge, \%data, $url_params{item} ) };
  }
  my $t    = [];
  my $vcpu = PowerDataWrapper::get_server_metric( $url_params{server}, "ConfigurableSystemProcessorUnits", 0 );
  if ( $vcpu == 0 ) {
    print '{"status" : "Couldn\'t find ConfigurableSystemProcessorUnits for server."}';
    exit 1;
  }
  $t        = create_data_array( \%data_merge, $vcpu );
  @data_out = @{$t} if ( defined $t );

  # construction agains peaking CPU that caused prediction to be unusable for pool total
  # if there is a peak to 100% (only bad data provided), use previous value to solve it.
  my $prev;
  foreach my $i (@data_out){
    if ($i == $vcpu && defined $prev){
      $i = $prev;
    }
    $prev = $i;
  }


  $json     = Prediction::export_get_days_to_value_by_array( \@data_out, 1, $vcpu, "max" );
  my $data;
  eval { $data = decode_json($json); };
  if ($@ || (( ref($data) ne "HASH" || ref($data) ne "ARRAY" ) && $data < 0)) {
    my $err = $@;
    chomp($err);
    if ( $json == -2 ) {
      print '{"status" : "<a href=\"https://www.lpar2rrd.com/smart_trends.php\"> Smart Trends</a>: Not enough of data, prediction needs 20days+, the best prediction works with 60days+"}';
    }
    else {
      print "{\"status\" : \"ERROR: Encode JSON failed: $err\"}";
    }
    exit 1;
  }

  push @{ $data->{thresholds} }, { "title" => "configured", "value" => $vcpu };

  #push @{ $data->{thresholds} }, { "title" => "set", "value" => $threshold2 };

  eval { $json = encode_json($data); };
  if ($@) {
    my $err = $@;
    chomp($err);
    if ( $json == -2 ) {
      print '{"status" : "<a href=\"https://www.lpar2rrd.com/smart_trends.php\"> Smart Trends</a>: Not enough of data, prediction needs 20days+, the best prediction works with 60days+"}';
    }
    else {
      print "{\"status\" : \"ERROR: Encode JSON failed: $err\"}";
    }
    exit 1;
  }

}
elsif ( $url_params{item} eq 'trendpool' || $url_params{item} eq 'trendpool-max' ) {
  my $max = 0;
  if ( $url_params{item} =~ 'max' ) { $max = 1; }

  my $file_pth = "$basedir/data/$url_params{server}/*/pool.rrm";
  $file_pth = "$basedir/data/$url_params{server}/*/pool.xrm" if ($max);

  my $cf = "AVERAGE";
  $cf = "MAX" if ($max);
  $file_pth =~ s/ /\\ /g;
  my @files = bsd_glob("$file_pth");
  foreach my $file (@files) {

    my $cmd   = set_cmd( "$file", "$url_params{item}", $cf );
    my $xport = get_rrd_xport($cmd);

    my %data = xport_to_hash( $xport, "$url_params{item}" );
    %data_merge = %{ merge_data( \%data_merge, \%data, $url_params{item} ) };
  }
  if ( !-e "$basedir/tmp/curr_pool_lim_cpu_$url_params{server}.json" ) {
    print '{"status" : "Wait until next load.sh or load_hmc_rest_api.sh. There is no information about currently available cores for this pool"}';
    exit 1;
  }
  my $json_cpu_lim_cont = Xorux_lib::read_json("$basedir/tmp/curr_pool_lim_cpu_$url_params{server}.json");
  my $threshold         = $json_cpu_lim_cont->[0];
  $t        = create_data_array( \%data_merge, $threshold );
  @data_out = @{$t} if ( defined $t );
  $json     = Prediction::export_get_days_to_value_by_array( \@data_out, 1, $threshold, "max" );
  my $data;
  eval { $data = decode_json($json); };
  if ($@ || (( ref($data) ne "HASH" || ref($data) ne "ARRAY" ) && $data < 0)) {
    my $err = $@;
    chomp($err);
    if ( $json == -2 ) {
      print '{"status" : "<a href=\"https://www.lpar2rrd.com/smart_trends.php\"> Smart Trends</a>: Not enough of data, prediction needs 20days+, the best prediction works with 60days+"}';
    }
    else {
      print "{\"status\" : \"ERROR: Decode JSON $json failed $err\"}";
    }
    exit 1;
  }

  push @{ $data->{thresholds} }, { "title" => "configured", "value" => $threshold };

  #push @{ $data->{thresholds} }, { "title" => "set", "value" => $threshold2 };

  eval { $json = encode_json($data); };
  if ($@) {
    my $err = $@;
    chomp($err);
    if ( $json == -2 ) {
      print '{"status" : "<a href=\"https://www.lpar2rrd.com/smart_trends.php\"> Smart Trends</a>: Not enough of data, prediction needs 20days+, the best prediction works with 60days+"}';
    }
    else {
      print "{\"status\" : \"ERROR: Encode JSON failed: $err\"}";
    }
    exit 1;
  }
}

#my $vcpu = PowerDataWrapper::get_server_metric($url_params{server}, "ConfigurableSystemProcessorUnits", 0);
#$t = create_data_array (\%data_merge, $vcpu);
#@data_out = @{ $t } if (defined $t);
#$json = Prediction::export_get_days_to_value_by_array(\@data_out, 1, $vcpu, "max");

#my $data;
#eval{
#  $data = decode_json( $json );
#};
#if ($@) {
##  warn("ERROR: Decode JSON $json failed: $@");
#  my $err = $@; chomp($err);
#  print "{\"status\" : \"ERROR: Decode JSON $json failed $err\"}";
#  exit 1;
#}
#
#push @{ $data->{thresholds} }, { "title" => "configured", "value" => $vcpu };
#
#eval{
#  $json = encode_json( $data );
##};
#if ($@) {
#  warn("ERROR: Encode JSON failed: $@");
#  my $err = $@; chomp($err);
#  print "{\"status\" : \"ERROR: Encode JSON failed: $err\"}";
##  exit 1;
#}

print $json;

RRDp::end;

exit(0);

sub create_data_array {
  my $data_merge = shift;
  my $vcpu       = shift;
  my $last_value = 0;
  my $data_out;
  foreach my $ts ( sort keys %{$data_merge} ) {
    my $value;
    if ( $data_merge->{$ts}{util} eq "U" ) {
      $value = $last_value;
      next;
    }
    else {
      $value = $data_merge->{$ts}{util};
    }
    if ( $value >= $vcpu ) { $value = $vcpu; }
    push( @{$data_out}, $value );
    $last_value = $data_merge->{$ts}{util} if ( $data_merge->{$ts}{util} ne "U" );
  }
  return $data_out;
}

sub merge_data {
  my $data_merge = shift;
  my $data       = shift;
  my $item       = shift;
  my @metrics    = @{ get_item_metrics($item) };
  foreach my $metric (@metrics) {
    foreach my $ts ( keys %{$data} ) {
      $data_merge->{$ts}{$metric} = $data->{$ts}{$metric} if ( !defined $data_merge->{$ts}{$metric} || $data->{$ts}{$metric} ne "U" || $data_merge->{$ts}{$metric} eq "U" );
    }
  }
  return $data_merge;

}

sub get_rrd_xport {
  my $cmd = shift;
  RRDp::cmd qq($cmd);
  my $ret = RRDp::read;
  return $ret;
}

sub item_prep_to_rrd_xport {
  my $rrd  = shift;
  my $item = shift;
  my $cf   = shift;
  my $cmd  = "";
  if ( $item eq 'trendpool-total' || $item eq 'trendpool-total-max' ) {
    $cmd .= " DEF:capped=\"$rrd\":capped_cycles:$cf";
    $cmd .= " DEF:uncapped=\"$rrd\":uncapped_cycles:$cf";
    $cmd .= " DEF:entitled=\"$rrd\":entitled_cycles:$cf";
    $cmd .= " DEF:cur=\"$rrd\":curr_proc_units:$cf";
    $cmd .= " CDEF:tot=capped,uncapped,+";
    $cmd .= " CDEF:utl=tot,entitled,/";
    $cmd .= " CDEF:util=utl,cur,*";
  }
  elsif ( $item eq 'trendpool' || $item eq 'trendpool-max' ) {
    $cmd .= " DEF:total_pool_cycles=\"$rrd\":total_pool_cycles:$cf";
    $cmd .= " DEF:utilized_pool_cyc=\"$rrd\":utilized_pool_cyc:$cf";
    $cmd .= " DEF:conf_proc_units=\"$rrd\":conf_proc_units:$cf";
    $cmd .= " DEF:bor_proc_units=\"$rrd\":bor_proc_units:$cf";

    $cmd .= " CDEF:totcyc=total_pool_cycles";
    $cmd .= " CDEF:uticyc=utilized_pool_cyc";
    $cmd .= " CDEF:cpu=conf_proc_units";
    $cmd .= " CDEF:cpubor=bor_proc_units";

    $cmd .= " CDEF:totcpu=cpu,cpubor,+";
    $cmd .= " CDEF:fail=uticyc,totcyc,GT,1,0,IF";
    $cmd .= " CDEF:cpuutil=uticyc,totcyc,GT,UNKN,uticyc,totcyc,/,IF";
    $cmd .= " CDEF:util=cpuutil,totcpu,*";
  }
  return $cmd;
}

sub set_cmd {
  my $eunix = time;
  my $sunix = $eunix - ( 86400 * 365 );
  my $rrd   = shift;
  my $item  = shift;
  my $cf    = shift;
  $rrd =~ s/:/\\:/g;

  my $max_rows = 365;
  my $xport    = "xport";
  my $STEP     = 60 * 60 * 24;
  my $val      = 1;              # this can be used to convert values e.g.: from kB to MB -> value/1024

  my $cmd .= "$xport";
  if ( -f "$basedir/tmp/rrdtool-xport-showtime" ) {

    # RRDTOOL: suported since 1.6, without that does not print timestamp like older 1.4 (1.5 does not support it)
    $cmd .= " --showtime";
  }
  $cmd .= " --start $sunix";
  $cmd .= " --end $eunix";
  $cmd .= " --step $STEP";
  $cmd .= " --maxrows $max_rows";

  my $cmd_tmp = item_prep_to_rrd_xport( $rrd, $item, $cf );
  my @metrics = @{ get_item_metrics($item) };
  $cmd .= $cmd_tmp;
  foreach my $metric (@metrics) {
    $cmd .= " XPORT:$metric";
  }
  return $cmd;
}

sub xport_to_hash {
  my $ret  = shift;
  my $item = shift;
  my @rrd_result;
  my %data;
  if ( $ret =~ /0x/ ) {
    @rrd_result = split( '\n', $$ret );
  }
  else {
    @rrd_result = split( '\n', $ret );
  }
  my @metrics = @{ get_item_metrics($item) };
  foreach my $row (@rrd_result) {
    chomp $row;
    $row =~ s/^\s+//g;
    $row =~ s/\s+$//g;
    if ( $row =~ "^<row><t>" ) {
      my $m_ind = 0;
      foreach my $metric (@metrics) {
        my ( $timestamp, $values ) = split( "</t><v>", $row );
        $values =~ s/<\/v><\/row>/<\/v><v>/g;
        my @values = split( '</v><v>', $values );
        $timestamp =~ s/<row><t>//g;
        my $value = $values[$m_ind];
        $value =~ s/<\/v><\/row>//g;
        if ( !Xorux_lib::isdigit($value) ) {
          $value = 'U';
        }
        $data{$timestamp}{$metric} = $value;
      }
    }
  }
  return %data;
}

sub get_item_metrics {
  my $item    = shift;
  my $metrics = [];
  if ( $item eq 'trendpool-total' || $item eq 'trendpool-total-max' ) {
    push @{$metrics}, "util";
  }
  elsif ( $item eq 'trendpool' || $item eq 'trendpool-max' ) {
    push @{$metrics}, "util";
  }
  return $metrics;
}

sub get_prediction_from_server_total_pool {
  my $server = shift;
  my $item   = shift;
  my %data_merge;
  if ( $item =~ 'trendpool-total' ) {
    my $max = 0;
    if ( $item =~ 'max' ) { $max = 1; }

    my $file_pth = "$basedir/data/$server/*/pool_total.rrt";
    $file_pth = "$basedir/data/$server/*/pool_total.rxm" if ($max);

    my $cf = "AVERAGE";
    $cf = "MAX" if ($max);
    $file_pth =~ s/ /\\ /g;
    my @files = bsd_glob("$file_pth");
    foreach my $file (@files) {

      my $cmd = set_cmd( "$file", "$item", $cf );

      my $xport = get_rrd_xport($cmd);

      my %data = xport_to_hash( $xport, "$item" );
      %data_merge = %{ merge_data( \%data_merge, \%data, $item ) };
    }
  }

  my @data_out = [];
  my $t        = [];
  my $vcpu     = PowerDataWrapper::get_server_metric( $server, "ConfigurableSystemProcessorUnits", 0 );
  $t = create_data_array( \%data_merge, $vcpu );

  @data_out = @{$t} if ( defined $t );
  return \@data_out;
}

sub get_prediction_from_server_pool {
  my $server = shift;
  my $item   = shift;
  my %data_merge;
  if ( $item =~ 'trendpool' ) {
    my $max = 0;
    if ( $item =~ 'max' ) { $max = 1; }

    my $file_pth = "$basedir/data/$server/*/pool.rrm";
    $file_pth = "$basedir/data/$server/*/pool.xrm" if ($max);

    my $cf = "AVERAGE";
    $cf = "MAX" if ($max);
    $file_pth =~ s/ /\\ /g;
    my @files = bsd_glob("$file_pth");
    foreach my $file (@files) {

      my $cmd = set_cmd( "$file", "$item", $cf );

      my $xport = get_rrd_xport($cmd);

      my %data = xport_to_hash( $xport, "$item" );
      %data_merge = %{ merge_data( \%data_merge, \%data, $item ) };
    }
  }

  my @data_out           = [];
  my $t                  = [];
  my $curr_pool_lim_json = Xorux_lib::read_json("$basedir/tmp/curr_pool_lim_cpu_$server.json");
  my $lim                = $curr_pool_lim_json->[0];

  #print STDERR Dumper \%data_merge;
  $t = create_data_array( \%data_merge, $lim );

  @data_out = @{$t} if ( defined $t );
  return \@data_out;
}

sub once_a_day {
  my $file = shift;

  # at first check whether it is a first run after the midnight
  if ( !-f $file ) {
    `touch $file`;    # first run after the upgrade
  }
  else {
    my $run_time = ( stat("$file") )[9];
    ( my $sec, my $min, my $h, my $aday, my $m, my $y, my $wday, my $yday, my $isdst ) = localtime( time() );
    ( $sec, $min, $h, my $png_day, $m, $y, $wday, $yday, $isdst ) = localtime($run_time);
    if ( $aday == $png_day ) {

      # If it is the same day then do not update static graphs
      # static graps need to be updated due to views and top10
      return (0);
    }
    else {
      `touch $file`;    # first run after the upgrade
    }
  }
  return 1;
}
