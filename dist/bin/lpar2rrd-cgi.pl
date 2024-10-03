use strict;
use Date::Parse;

#
### Linux historical reports
#
my $DEBUG  = $ENV{DEBUG};
my $errlog = $ENV{ERRLOG};
my $xport  = $ENV{EXPORT_TO_CSV};
open( OUT, ">> $errlog" ) if $DEBUG == 2;
my $lpm     = $ENV{LPM};
my $basedir = $ENV{INPUTDIR};
my $wrkdir  = $basedir . "/data";

my $detail_graph = "detail-graph";
if ( defined $ENV{NMON_EXTERNAL} ) {
  $wrkdir .= $ENV{NMON_EXTERNAL};
  $detail_graph = "detail-graph-external";
}

my $width_detail  = 1200;
my $height_detail = 450;

# set unbuffered stdout
$| = 1;

print "Content-type: text/html\n\n";

# get QUERY_STRING
use Env qw(QUERY_STRING);
print OUT "99 $QUERY_STRING\n" if $DEBUG == 2;

# print STDERR "26 lpar2rrd-cgi.pl \$QUERY_STRING $QUERY_STRING\n";

my $act_unix = time();
my $shour    = "";
my $sday     = "";
my $smon     = "";
my $syear    = "";
my $ehour    = "";
my $eday     = "";
my $emon     = "";
my $eyear    = "";
my $type     = "";
my $height   = "";
my $width    = "";
my $yaxis    = "";
my $host     = "";
my $server   = "";
my $referer  = "na";
my @lpar_row = "";
my $entitle  = 0;
my $new_gui  = 0;
my $NMON     = "--NMON--";

# just for backward compatability if users use historical reporting for whatever
if ( $QUERY_STRING =~ m/referer=/ ) {

  # new way
  ( $shour, $sday, $smon, $syear, $ehour, $eday, $emon, $eyear, $type, $height, $width, $yaxis, $host, $server, $referer, @lpar_row ) = split( /&/, $QUERY_STRING );
}
else {
  ( $shour, $sday, $smon, $syear, $ehour, $eday, $emon, $eyear, $type, $height, $width, $yaxis, $host, $server, @lpar_row ) = split( /&/, $QUERY_STRING );
}

# entitle and gui parameters are passed through @lpar_row as last items
foreach my $lpar_line (@lpar_row) {
  if ( $lpar_line =~ m/^entitle=/ ) {
    $entitle = $lpar_line;
  }
  if ( $lpar_line =~ m/^gui=/ ) {
    $new_gui = $lpar_line;
    last;
  }
}

# remove alias info
foreach my $lpar_line (@lpar_row) {
  $lpar_line =~ s/%20%5B.*%5D//g;
}

$entitle =~ s/entitle=//;

# if == 1 then restrict views (only CPU and mem)
if ( $entitle eq '' || isdigit($entitle) == 0 ) {
  $entitle = 0;    # when any problem then allow it!
}

$new_gui =~ s/gui=//;
if ( $new_gui eq '' || isdigit($new_gui) == 0 ) {
  $new_gui = 0;    # when any problem then old GUI
}

# no URL decode here, as it goes immediately into URL again

$host    =~ s/HMC=//;
$server  =~ s/MNAME=//;
$smon    =~ s/start-mon=//;
$sday    =~ s/start-day=//;
$shour   =~ s/start-hour=//;
$syear   =~ s/start-yr=//;
$emon    =~ s/end-mon=//;
$eday    =~ s/end-day=//;
$ehour   =~ s/end-hour=//;
$eyear   =~ s/end-yr=//;
$type    =~ s/type=//;
$height  =~ s/\+//;
$height  =~ s/HEIGHT=//;
$width   =~ s/\+//;
$width   =~ s/WIDTH=//;
$yaxis   =~ s/yaxis=//;
$referer =~ s/referer=//;                                         # HTTP_REFERER
$referer =~ s/%([a-fA-F0-9][a-fA-F0-9])/pack("C", hex($1))/seg;
$referer =~ s/\+/ /g;

# `echo "$QUERY_STRING\n$shour, $sday, $smon, $syear, $ehour, $eday, $emon,$eyear,$type, $height, $width, $yaxis, $host, $server, $referer" >/tmp/xx3`;

my $host_url = $host;
$host =~ s/%([a-fA-F0-9][a-fA-F0-9])/pack("C", hex($1))/seg;

#$host  =~ s/\+/ /g;
my $server_url = $server;

# print STDERR "lpar2rrd-cgi.pl 115 pred url \$server $server\n";
$server =~ s/%([a-fA-F0-9][a-fA-F0-9])/pack("C", hex($1))/seg;

#$server =~ s/\+/ /g;
# print STDERR "lpar2rrd-cgi.pl 118 po url \$server $server\n";
my $detail_yes = 1;
my $detail_no  = 0;
my $detail_9   = 9;

if ( $yaxis =~ m/r/ || $yaxis =~ m/s/ ) {
  not_implemented();
  exit 0;
}

my $human_start = $shour . ":00:00 " . $sday . "." . $smon . "." . $syear;
my $human_end   = $ehour . ":00:00 " . $eday . "." . $emon . "." . $eyear;

my $start_unix = str2time( $syear . "-" . $smon . "-" . $sday . " " . $shour . ":00:00" );
my $end_unix   = "";

# workaround for 24:00. If is used proper 00:00 of the next day then there are 2 extra records in cvs after the midnight
# looks like rrdtool issue
if ( $ehour == 24 ) {
  $end_unix = str2time( $eyear . "-" . $emon . "-" . $eday . " 23:59:00" );
}
else {
  $end_unix = str2time( $eyear . "-" . $emon . "-" . $eday . " " . $ehour . ":00:00" );
}

my $l = length($start_unix);
print OUT "$human_start : $human_end : $start_unix : $end_unix : $l \n" if $DEBUG == 2;

if ( length($start_unix) < 1 ) {
  print "<center><br>Start date (<B>$sday.$smon.$syear</B>) does not seem to be valid</center>\n";
  exit(0);
}

if ( length($end_unix) < 1 ) {
  print "<center><br>End date (<B>$eday.$emon.$eyear</B>) does not seem to be valid</center>\n";
  exit(0);
}

if ( $end_unix <= $start_unix ) {
  print "<center><br>Start (<B>$human_start</B>) should be less than end (<B>$human_end</B>)</center>\n";
  exit(0);
}

if ( defined $end_unix && isdigit($end_unix) && $end_unix > $act_unix ) {
  $end_unix = $act_unix;    # if eunix higher than act unix - set it up to act unix
}

# check if agent data  --> then tabs in place
my $agent           = 0;
my $agent_oscpu     = 0;
my $agent_ame       = 0;
my $agent_pgs       = 0;
my $agent_mem       = 0;
my $agent_san       = 0;
my $agent_lan       = 0;
my $agent_sea       = 0;
my $agent_san_resp  = 0;
my $agent_queue_cpu = 0;
my $agent_iops      = 0;
my $agent_data      = 0;
my $agent_latency   = 0;
my $agent_core      = 0;

# NMON part
my $agent_oscpu_n = 0;
my $agent_ame_n   = 0;
my $agent_pgs_n   = 0;
my $agent_mem_n   = 0;
my $agent_san_n   = 0;
my $agent_lan_n   = 0;
my $agent_sea_n   = 0;

foreach my $lpar (@lpar_row) {

  # print STDERR "lpar2rrd-cgi.pl 181 $lpar :$lpar : \n";
  if ( $lpar =~ m/^LPAR=/ ) {
    my $lpar_tmp = $lpar;    # must be like that to do not modify the original script
    $lpar =~ s/LPAR=//;
    $lpar =~ s/%([a-fA-F0-9][a-fA-F0-9])/pack("C", hex($1))/seg;

    #$lpar =~ s/\+/ /g;
    my $lpar_slash = $lpar;         #must be in separate env!!
    $lpar_slash =~ s/\//\&\&1/g;    # replace for "/"
    my $test_dir      = "$wrkdir/$server/$host/$lpar_slash";
    my $test_dir_nmon = "$wrkdir/$server/$host/$lpar_slash$NMON";

    # print STDERR "lpar2rrd-cgi.pl 191 -d $test_dir\n";
    if ( !-d "$test_dir" && !-d "$test_dir_nmon" ) {
      $lpar = $lpar_tmp;
      next;
    }
    $agent++;
    if ( $entitle == 0 && test_file_in_directory( "$test_dir", "cpu" ) ) {
      $agent_oscpu++;
    }
    $agent_oscpu_n++ if ( $entitle == 0 && test_file_in_directory( "$test_dir_nmon", "cpu" ) );

    if ( test_file_in_directory( "$test_dir", "queue_cpu" ) ) {
      $agent_queue_cpu++;
    }
    if ( test_file_in_directory( "$test_dir", "mem" ) ) {
      $agent_mem++;
    }
    $agent_mem_n++ if ( test_file_in_directory( "$test_dir_nmon", "mem" ) );

    if ( $entitle == 0 && test_file_in_directory( "$test_dir", "pgs" ) ) {
      $agent_pgs++;
    }
    $agent_pgs_n++ if ( $entitle == 0 && test_file_in_directory( "$test_dir_nmon", "pgs" ) );

    if ( $entitle == 0 && test_file_in_directory( "$test_dir", "ame" ) ) {
      $agent_ame++;
    }
    $agent_ame_n++ if ( $entitle == 0 && test_file_in_directory( "$test_dir_nmon", "ame" ) );

    if ( $entitle == 0 && test_file_in_directory( "$test_dir", "san" ) ) {
      $agent_san++;
    }
    $agent_san_n++ if ( $entitle == 0 && test_file_in_directory( "$test_dir_nmon", "san" ) );

    if ( $entitle == 0 && test_file_in_directory( "$test_dir", "lan" ) ) {
      $agent_lan++;
    }
    $agent_lan_n++ if ( $entitle == 0 && test_file_in_directory( "$test_dir_nmon", "lan" ) );

    if ( $entitle == 0 && test_file_in_directory( "$test_dir", "sea" ) ) {
      $agent_sea++;
    }
    $agent_sea_n++ if ( $entitle == 0 && test_file_in_directory( "$test_dir_nmon", "sea" ) );

    if ( $entitle == 0 && test_file_in_directory( "$test_dir", "san_resp" ) ) {
      $agent_san_resp++;
    }
    if ( $entitle == 0 && test_file_in_directory( "$test_dir", "disk-total" ) ) {
      $agent_iops++;
      $agent_data++;
      $agent_latency++;
    }
    if ( $entitle == 0 && test_file_in_directory( "$test_dir", "linux_cpu" ) ) {
      $agent_core++;
    }

    $lpar = $lpar_tmp;

    #print STDERR "004 1 $lpar_tmp :$lpar\n";
  }
}

my $html_base = "";

my $tabagent = "tabnmon";

if ( $agent > 0 ) {
  print "<div  id=\"tabs\"> <ul>\n";
  if ( !defined $ENV{NMON_EXTERNAL} && !( $server eq 'Linux--unknown' ) ) {
    $tabagent = "tabagent";
    print "  <li class=\"tabhmc\"><a href=\"#tabs-0\">CPU</a></li>\n";
  }
  if ( $agent_oscpu > 0 ) {
    print "  <li class=\"$tabagent\"><a href=\"#tabs-1\">CPU OS</a></li>\n";
  }
  if ( $agent_core > 0 ) {
    print "  <li class=\"$tabagent\"><a href=\"#tabs-2\">CPU Core</a></li>\n";
  }
  if ( $agent_queue_cpu > 0 ) {
    print "  <li class=\"$tabagent\"><a href=\"#tabs-3\">CPU Queue</a></li>\n";
  }
  if ( $agent_mem > 0 ) {
    print "  <li class=\"$tabagent\"><a href=\"#tabs-4\">Memory</a></li>\n";
  }
  if ( $agent_pgs > 0 ) {
    print "  <li class=\"$tabagent\"><a href=\"#tabs-5\">Paging 1</a></li>\n";
    print "  <li class=\"$tabagent\"><a href=\"#tabs-6\">Paging 2</a></li>\n";
  }
  if ( $agent_lan > 0 ) {
    print "  <li class=\"$tabagent\"><a href=\"#tabs-7\">LAN</a></li>\n";
  }
  if ( $agent_san > 0 ) {
    print "  <li class=\"$tabagent\"><a href=\"#tabs-8\">SAN</a></li>\n";
    print "  <li class=\"$tabagent\"><a href=\"#tabs-9\">SAN IOPS</a></li>\n";
  }
  if ( $agent_sea > 0 ) {
    print "  <li class=\"$tabagent\"><a href=\"#tabs-10\">SEA</a></li>\n";
  }
  if ( $agent_ame > 0 ) {
    print "  <li class=\"$tabagent\"><a href=\"#tabs-11\">AME</a></li>\n";
  }
  if ( $agent_san_resp > 0 ) {
    print "  <li class=\"$tabagent\"><a href=\"#tabs-12\">SAN RESP</a></li>\n";
  }
  if ( $agent_iops > 0 ) {    # all three are coming together
    print "  <li class=\"$tabagent\"><a href=\"#tabs-13\">IOPS</a></li>\n";
    print "  <li class=\"$tabagent\"><a href=\"#tabs-14\">Data</a></li>\n";
    print "  <li class=\"$tabagent\"><a href=\"#tabs-15\">Latency</a></li>\n";
  }
  $tabagent = "tabnmon";
  print "  <li class=\"$tabagent\"><a href=\"#tabs-21\">CPU OS [N]</a></li>\n"   if $agent_oscpu_n > 0;
  print "  <li class=\"$tabagent\"><a href=\"#tabs-22\">Memory [N]</a></li>\n"   if $agent_mem_n > 0;
  print "  <li class=\"$tabagent\"><a href=\"#tabs-23\">Paging 1 [N]</a></li>\n" if $agent_pgs_n > 0;
  print "  <li class=\"$tabagent\"><a href=\"#tabs-24\">Paging 2 [N]</a></li>\n" if $agent_pgs_n > 0;
  print "  <li class=\"$tabagent\"><a href=\"#tabs-25\">LAN [N]</a></li>\n"      if $agent_lan_n > 0;
  print "  <li class=\"$tabagent\"><a href=\"#tabs-26\">SAN [N]</a></li>\n"      if $agent_san_n > 0;
  print "  <li class=\"$tabagent\"><a href=\"#tabs-27\">SAN IOPS [N]</a></li>\n" if $agent_san_n > 0;
  print "  <li class=\"$tabagent\"><a href=\"#tabs-28\">SEA [N]</a></li>\n"      if $agent_sea_n > 0;
  print "  <li class=\"$tabagent\"><a href=\"#tabs-29\">AME [N]</a></li>\n"      if $agent_ame_n > 0;

  print "   </ul> \n";
}

#
# CPU
#

if ( !defined $ENV{NMON_EXTERNAL} && !( $server eq 'Linux--unknown' ) ) {
  if ( $agent > 0 ) {
    print "<div id=\"tabs-0\">\n";
  }

  print "<center><table align=\"center\" summary=\"Graphs\">\n";

  # Loop per each chosen lpar/CPU pool/Memory
  foreach my $lpar (@lpar_row) {
    if ( $lpar =~ m/^LPAR=/ ) {
      my $lpar_tmp = $lpar;    # must be like that to do not modify the original script
      $lpar =~ s/LPAR=//;
      $lpar =~ s/%([a-fA-F0-9][a-fA-F0-9])/pack("C", hex($1))/seg;

      #$lpar =~ s/\+/ /g;

      my $lpar_url = $lpar;
      $lpar_url =~ s/\&\&1/\//g;                                         # replace for "/"
      $lpar_url =~ s/([^A-Za-z0-9\+-_])/sprintf("%%%02X",ord($1))/seg;

      #$lpar_slash =~ s/ /%20/g ;
      #$lpar_slash =~ s/\#/\%23/g;
      my $host_url = $host;
      $host_url =~ s/([^A-Za-z0-9\+-_])/sprintf("%%%02X",ord($1))/seg;
      my $server_url = $server;
      $server_url =~ s/([^A-Za-z0-9\+-_])/sprintf("%%%02X",ord($1))/seg;

      my $type_sam = $type;
      my $upper    = 0;
      my $item     = $lpar_url;
      my $legend   = "legend";

      if ( $item ne 'pool' && $item ne 'mem' && $item ne 'multiview' && $item !~ /SharedPool/ ) {
        $item = 'lpar';
      }
      ( $lpar_url eq 'mem' )        && ( $item = 'memalloc' );
      ( $lpar_url =~ /SharedPool/ ) && ( $item = 'shpool' );
      ( $lpar_url eq 'multiview' )  && do {
        $item   = 'lparagg';
        $legend = "nolegend";
      };

      #print STDERR "335 lpar2rrd-rep.sh hmc=$host_url&mname=$server_url&lpar=$lpar_url&shour=$shour&smon=$smon&sday=$sday&syear=$syear&ehour=$ehour&emon=$emon&eday=$eday&eyear=$eyear&type=$type&height=$height&width=$width&yaxis=$yaxis&xport=0\n";

      print '<tr><td>';

      # new method not now for lpar because of LPM
      if ( $item ne "lpar" ) {
        print_item( $host, $server, $lpar, $item, $type, $type_sam, $entitle, $detail_yes, $start_unix, $end_unix, $html_base, $legend );
      }
      else {
        print "<tr><td class=\"relpos\"><img class=\"lazy\" data-src=\"/lpar2rrd-cgi/lpar2rrd-rep.sh?hmc=$host_url&mname=$server_url&lpar=$lpar_url&shour=$shour&smon=$smon&sday=$sday&syear=$syear&ehour=$ehour&emon=$emon&eday=$eday&eyear=$eyear&type=$type&height=$height&width=$width&yaxis=$yaxis&xport=0\" src=\"$html_base/css/images/loading.gif\"></td>\n";
      }
      print "</td>";

      if ( $xport == 1 ) {
        print "<td valign=\"top\"><font size=-1><A class=\"csvfloat\" HREF=\"/lpar2rrd-cgi/lpar2rrd-rep.sh?host=$host_url&mname=$server_url&lpar=$lpar_url&shour=$shour&smon=$smon&sday=$sday&syear=$syear&ehour=$ehour&emon=$emon&eday=$eday&eyear=$eyear&type=$type&height=$height&width=$width&yaxis=$yaxis&xport=1\">CSV</A></font></td>";
      }
      print "</tr>\n";
      $lpar = $lpar_tmp;
    }
  }
  print "</table></center>\n";

  if ( $agent > 0 ) {
    print "</div>\n";
  }
  else {
    # Exit, no agent in place
    exit(0);
  }
}

#
# CPU OS
#

if ( $agent_oscpu > 0 ) {
  print "<div id=\"tabs-1\">\n";
  my $item = "oscpu";
  agent( $host_url, $server_url, $item, $type, $entitle, $detail_yes, $start_unix, $end_unix, $html_base, \@lpar_row );
  print "</div>\n";
}
if ( $agent_oscpu_n > 0 ) {
  print "<div id=\"tabs-21\">\n";
  my $item = "nmon_oscpu";
  agent( $host_url, $server_url, $item, $type, $entitle, $detail_yes, $start_unix, $end_unix, $html_base, \@lpar_row );
  print "</div>\n";
}

#
# CPU Core
#

if ( $agent_core > 0 ) {
  print "<div id=\"tabs-2\">\n";
  my $item = "cpu-linux";
  agent( $host_url, $server_url, $item, $type, $entitle, $detail_yes, $start_unix, $end_unix, $html_base, \@lpar_row );
  print "</div>\n";
}

#
# CPU Queue
#

if ( $agent_queue_cpu > 0 ) {
  print "<div id=\"tabs-3\">\n";
  my $item = "queue_cpu";
  agent( $host_url, $server_url, $item, $type, $entitle, $detail_yes, $start_unix, $end_unix, $html_base, \@lpar_row );
  print "</div>\n";
}

#
# OS mem
#

if ( $agent_mem > 0 ) {
  print "<div id=\"tabs-4\">\n";
  my $item = "mem";
  agent( $host_url, $server_url, $item, $type, $entitle, $detail_yes, $start_unix, $end_unix, $html_base, \@lpar_row );
  print "</div>\n";

}
if ( $agent_mem_n > 0 ) {
  print "<div id=\"tabs-22\">\n";
  my $item = "nmon_mem";
  agent( $host_url, $server_url, $item, $type, $entitle, $detail_yes, $start_unix, $end_unix, $html_base, \@lpar_row );
  print "</div>\n";
}

#
# OS paging
#

if ( $agent_pgs > 0 ) {
  print "<div id=\"tabs-5\">\n";
  my $item = "pg1";
  agent( $host_url, $server_url, $item, $type, $entitle, $detail_yes, $start_unix, $end_unix, $html_base, \@lpar_row );
  print "</div>\n";
  print "<div id=\"tabs-6\">\n";
  my $item = "pg2";
  agent( $host_url, $server_url, $item, $type, $entitle, $detail_yes, $start_unix, $end_unix, $html_base, \@lpar_row );
  print "</div>\n";
}
if ( $agent_pgs_n > 0 ) {
  print "<div id=\"tabs-23\">\n";
  my $item = "nmon_pg1";
  agent( $host_url, $server_url, $item, $type, $entitle, $detail_yes, $start_unix, $end_unix, $html_base, \@lpar_row );
  print "</div>\n";
  print "<div id=\"tabs-24\">\n";
  my $item = "nmon_pg2";
  agent( $host_url, $server_url, $item, $type, $entitle, $detail_yes, $start_unix, $end_unix, $html_base, \@lpar_row );
  print "</div>\n";
}

#
# OS Ethernet
#

if ( $agent_lan > 0 ) {
  print "<div id=\"tabs-7\">\n";
  my $item = "lan";
  agent( $host_url, $server_url, $item, $type, $entitle, $detail_yes, $start_unix, $end_unix, $html_base, \@lpar_row );
  print "</div>\n";
}
if ( $agent_lan_n > 0 ) {
  print "<div id=\"tabs-25\">\n";
  my $item = "nmon_lan";
  agent( $host_url, $server_url, $item, $type, $entitle, $detail_yes, $start_unix, $end_unix, $html_base, \@lpar_row );
  print "</div>\n";
}

#
# OS FC
#

if ( $agent_san > 0 ) {
  print "<div id=\"tabs-8\">\n";
  my $item = "san1";
  agent( $host_url, $server_url, $item, $type, $entitle, $detail_yes, $start_unix, $end_unix, $html_base, \@lpar_row );
  print "</div>\n";
  print "<div id=\"tabs-9\">\n";
  my $item = "san2";
  agent( $host_url, $server_url, $item, $type, $entitle, $detail_yes, $start_unix, $end_unix, $html_base, \@lpar_row );
  print "</div>\n";
}
if ( $agent_san_n > 0 ) {
  print "<div id=\"tabs-26\">\n";
  my $item = "nmon_san1";
  agent( $host_url, $server_url, $item, $type, $entitle, $detail_yes, $start_unix, $end_unix, $html_base, \@lpar_row );
  print "</div>\n";
  print "<div id=\"tabs-27\">\n";
  my $item = "nmon_san2";
  agent( $host_url, $server_url, $item, $type, $entitle, $detail_yes, $start_unix, $end_unix, $html_base, \@lpar_row );
  print "</div>\n";
}

#
# OS SEA
#

if ( $agent_sea > 0 ) {
  print "<div id=\"tabs-10\">\n";
  my $item = "sea";
  agent( $host_url, $server_url, $item, $type, $entitle, $detail_yes, $start_unix, $end_unix, $html_base, \@lpar_row );
  print "</div>\n";
}
if ( $agent_sea_n > 0 ) {
  print "<div id=\"tabs-28\">\n";
  my $item = "nmon_sea";
  agent( $host_url, $server_url, $item, $type, $entitle, $detail_yes, $start_unix, $end_unix, $html_base, \@lpar_row );
  print "</div>\n";
}

#
# OS AME
#

if ( $agent_ame > 0 ) {
  print "<div id=\"tabs-11\">\n";
  my $item = "ame";
  agent( $host_url, $server_url, $item, $type, $entitle, $detail_yes, $start_unix, $end_unix, $html_base, \@lpar_row );
  print "</div>\n";
}
if ( $agent_ame > 0 ) {
  print "<div id=\"tabs-29\">\n";
  my $item = "nmon_ame";
  agent( $host_url, $server_url, $item, $type, $entitle, $detail_yes, $start_unix, $end_unix, $html_base, \@lpar_row );
  print "</div>\n";
}

#
# OS SAN RESP
#

if ( $agent_san_resp > 0 ) {
  print "<div id=\"tabs-12\">\n";
  my $item = "san_resp";
  agent( $host_url, $server_url, $item, $type, $entitle, $detail_yes, $start_unix, $end_unix, $html_base, \@lpar_row );
  print "</div>\n";
}

#
# IOPS, Data, Latency
#

if ( $agent_iops > 0 ) {
  print "<div id=\"tabs-13\">\n";
  my $item = "total_iops";
  agent( $host_url, $server_url, $item, $type, $entitle, $detail_yes, $start_unix, $end_unix, $html_base, \@lpar_row );
  print "</div>\n";

  print "<div id=\"tabs-14\">\n";
  my $item = "total_data";
  agent( $host_url, $server_url, $item, $type, $entitle, $detail_yes, $start_unix, $end_unix, $html_base, \@lpar_row );
  print "</div>\n";

  print "<div id=\"tabs-15\">\n";
  my $item = "total_latency";
  agent( $host_url, $server_url, $item, $type, $entitle, $detail_yes, $start_unix, $end_unix, $html_base, \@lpar_row );
  print "</div>\n";
}

print "<br>\n";
close(OUT) if $DEBUG == 2;

exit(0);

sub not_implemented {
  print "<br><br><center><strong>rPerf scaling is not implemented yet</strong>\n";

  return 0;
}

sub agent {
  my ( $host_url, $server_url, $item, $type, $entitle, $detail_yes, $start_unix, $end_unix, $html_base, $lpar_row_tmp ) = @_;
  my @lpar_row = @{$lpar_row_tmp};
  my $type_sam = "x";                # whatever, it is not significant for OS agent graphs

  print "<center><table align=\"center\" summary=\"$item\">\n";

  foreach my $lpar_tmp (@lpar_row) {
    my $lpar = $lpar_tmp;
    if ( $lpar =~ "LPAR=" ) {
      $lpar =~ s/LPAR=//;
      $lpar =~ s/%([a-fA-F0-9][a-fA-F0-9])/pack("C", hex($1))/seg;

      #$lpar =~ s/\+/ /g;
      my $lpar_slash = $lpar;
      $lpar_slash =~ s/\//\&\&1/g;    # replace for "/"
      my $lpar_url = $lpar;
      $lpar_url =~ s/\&\&1/\//g;                                         # replace for "/"
      $lpar_url =~ s/([^A-Za-z0-9\+-_])/sprintf("%%%02X",ord($1))/seg;

      #  print STDERR "lpar2rrd-cgi.pl 540 $lpar: $wrkdir/$server/$host/$lpar_slash.mmm : lpar_url: $lpar_url\n";
      my $test_dir      = "$wrkdir/$server/$host/$lpar_slash";
      my $test_dir_nmon = "$wrkdir/$server/$host/$lpar_slash--NMON--";
      if ( -d "$test_dir" || -d "$test_dir_nmon" ) {
        if ( $item =~ m/^oscpu$/ && $entitle == 0 ) {
          if ( test_file_in_directory( "$test_dir", "cpu" ) ) {
            print "<td>";
            if ( $xport == 1 ) {
              print_item( $host_url, $server_url, $lpar_url, $item, $type, $type_sam, $entitle, $detail_yes, $start_unix, $end_unix, $html_base, "legend" );
              print "<td valign=\"top\"><font size=-1><A class=\"csvfloat\" HREF=\"/lpar2rrd-cgi/lpar2rrd-rep.sh?host=$host_url&mname=$server_url&lpar=$lpar_url&shour=$shour&smon=$smon&sday=$sday&syear=$syear&ehour=$ehour&emon=$emon&eday=$eday&eyear=$eyear&type=$type&height=$height&width=$width&yaxis=$yaxis&xport=1&item=$item\">CSV</A></font></td>" if ( !defined $ENV{NMON_EXTERNAL} );
            }
            print "</td>";
            print "</tr>\n";
          }
          next;
        }
        if ( $item =~ m/^nmon_oscpu$/ && $entitle == 0 ) {
          if ( test_file_in_directory( "$test_dir_nmon", "cpu" ) ) {

            #$item = "oscpu";
            print "<td>";
            if ( $xport == 1 ) {
              print_item( $host_url, $server_url, "$lpar_url$NMON", "oscpu", $type, $type_sam, $entitle, $detail_yes, $start_unix, $end_unix, $html_base, "legend" );
              print "<td valign=\"top\"><font size=-1><A class=\"csvfloat\" HREF=\"/lpar2rrd-cgi/lpar2rrd-rep.sh?host=$host_url&mname=$server_url&lpar=$lpar_url&shour=$shour&smon=$smon&sday=$sday&syear=$syear&ehour=$ehour&emon=$emon&eday=$eday&eyear=$eyear&type=$type&height=$height&width=$width&yaxis=$yaxis&xport=1&item=$item\">CSV</A></font></td>";
            }
          }
          print "</td>";
          print "</tr>\n";
          next;
        }
        if ( $item =~ m/^cpu-linux$/ && test_file_in_directory( "$test_dir", "linux_cpu" ) ) {
          print "<td>";
          if ( $xport == 1 ) {
            print_item( $host_url, $server_url, $lpar_url, $item, $type, $type_sam, $entitle, $detail_yes, $start_unix, $end_unix, $html_base, "legend" );
            print "<td valign=\"top\"><font size=-1><A class=\"csvfloat\" HREF=\"/lpar2rrd-cgi/lpar2rrd-rep.sh?host=$host_url&mname=$server_url&lpar=$lpar_url&shour=$shour&smon=$smon&sday=$sday&syear=$syear&ehour=$ehour&emon=$emon&eday=$eday&eyear=$eyear&type=$type&height=$height&width=$width&yaxis=$yaxis&xport=1&item=$item\">CSV</A></font></td>" if ( !defined $ENV{NMON_EXTERNAL} );
          }
          print "</td>";
          print "</tr>\n";
          next;
        }
        if ( $item =~ m/^queue_cpu$/ && test_file_in_directory( "$test_dir", "queue_cpu" ) ) {
          print "<td>";
          if ( $xport == 1 ) {
            print_item( $host_url, $server_url, $lpar_url, $item, $type, $type_sam, $entitle, $detail_yes, $start_unix, $end_unix, $html_base, "legend" );
            print "<td valign=\"top\"><font size=-1><A class=\"csvfloat\" HREF=\"/lpar2rrd-cgi/lpar2rrd-rep.sh?host=$host_url&mname=$server_url&lpar=$lpar_url&shour=$shour&smon=$smon&sday=$sday&syear=$syear&ehour=$ehour&emon=$emon&eday=$eday&eyear=$eyear&type=$type&height=$height&width=$width&yaxis=$yaxis&xport=1&item=$item\">CSV</A></font></td>" if ( !defined $ENV{NMON_EXTERNAL} );
          }
          print "</td>";
          print "</tr>\n";
          next;
        }
        if ( $item =~ m/^mem$/ && test_file_in_directory( "$test_dir", "mem" ) ) {
          print "<td>";
          if ( $xport == 1 ) {
            print_item( $host_url, $server_url, $lpar_url, $item, $type, $type_sam, $entitle, $detail_yes, $start_unix, $end_unix, $html_base, "legend" );
            print "<td valign=\"top\"><font size=-1><A class=\"csvfloat\" HREF=\"/lpar2rrd-cgi/lpar2rrd-rep.sh?host=$host_url&mname=$server_url&lpar=$lpar_url&shour=$shour&smon=$smon&sday=$sday&syear=$syear&ehour=$ehour&emon=$emon&eday=$eday&eyear=$eyear&type=$type&height=$height&width=$width&yaxis=$yaxis&xport=1&item=$item\">CSV</A></font></td>" if ( !defined $ENV{NMON_EXTERNAL} );
          }
          print "</td>";
          print "</tr>\n";
          next;
        }
        if ( $item =~ m/^nmon_mem$/ && test_file_in_directory( "$test_dir_nmon", "mem" ) ) {
          print "<td>";
          if ( $xport == 1 ) {
            print_item( $host_url, $server_url, "$lpar_url$NMON", "mem", $type, $type_sam, $entitle, $detail_yes, $start_unix, $end_unix, $html_base, "legend" );
            print "<td valign=\"top\"><font size=-1><A class=\"csvfloat\" HREF=\"/lpar2rrd-cgi/lpar2rrd-rep.sh?host=$host_url&mname=$server_url&lpar=$lpar_url&shour=$shour&smon=$smon&sday=$sday&syear=$syear&ehour=$ehour&emon=$emon&eday=$eday&eyear=$eyear&type=$type&height=$height&width=$width&yaxis=$yaxis&xport=1&item=$item\">CSV</A></font></td>";
          }
          print "</td>";
          print "</tr>\n";
          next;
        }
        if ( $item =~ m/^pg/ && $entitle == 0 && test_file_in_directory( "$test_dir", "pgs" ) ) {
          print "<td>";
          if ( $xport == 1 ) {
            print_item( $host_url, $server_url, $lpar_url, $item, $type, $type_sam, $entitle, $detail_yes, $start_unix, $end_unix, $html_base, "legend" );
            print "<td valign=\"top\"><font size=-1><A class=\"csvfloat\" HREF=\"/lpar2rrd-cgi/lpar2rrd-rep.sh?host=$host_url&mname=$server_url&lpar=$lpar_url&shour=$shour&smon=$smon&sday=$sday&syear=$syear&ehour=$ehour&emon=$emon&eday=$eday&eyear=$eyear&type=$type&height=$height&width=$width&yaxis=$yaxis&xport=1&item=$item\">CSV</A></font></td>" if ( !defined $ENV{NMON_EXTERNAL} );
          }
          print "</td>";
          print "</tr>\n";
          next;
        }
        if ( $item =~ m/^nmon_pg/ && $entitle == 0 && test_file_in_directory( "$test_dir_nmon", "pgs" ) ) {
          my $itm = $item;
          $itm =~ s/nmon_//;
          print "<td>";
          if ( $xport == 1 ) {
            print_item( $host_url, $server_url, "$lpar_url$NMON", $itm, $type, $type_sam, $entitle, $detail_yes, $start_unix, $end_unix, $html_base, "legend" );
            print "<td valign=\"top\"><font size=-1><A class=\"csvfloat\" HREF=\"/lpar2rrd-cgi/lpar2rrd-rep.sh?host=$host_url&mname=$server_url&lpar=$lpar_url&shour=$shour&smon=$smon&sday=$sday&syear=$syear&ehour=$ehour&emon=$emon&eday=$eday&eyear=$eyear&type=$type&height=$height&width=$width&yaxis=$yaxis&xport=1&item=$item\">CSV</A></font></td>";
          }
          print "</td>";
          print "</tr>\n";
          next;
        }
        if ( $item =~ m/^lan$/ && $entitle == 0 && test_file_in_directory( "$test_dir", "lan" ) ) {
          print "<td>";
          if ( $xport == 1 ) {
            print_item( $host_url, $server_url, $lpar_url, $item, $type, $type_sam, $entitle, $detail_yes, $start_unix, $end_unix, $html_base, "nolegend" );
            print "<td valign=\"top\"><font size=-1><A class=\"csvfloat\" HREF=\"/lpar2rrd-cgi/lpar2rrd-rep.sh?host=$host_url&mname=$server_url&lpar=$lpar_url&shour=$shour&smon=$smon&sday=$sday&syear=$syear&ehour=$ehour&emon=$emon&eday=$eday&eyear=$eyear&type=$type&height=$height&width=$width&yaxis=$yaxis&xport=1&item=$item\">CSV</A></font></td>" if ( !defined $ENV{NMON_EXTERNAL} );
          }
          print "</td>";
          print "</tr>\n";
          next;
        }
        if ( $item =~ m/^nmon_lan$/ && $entitle == 0 && test_file_in_directory( "$test_dir_nmon", "lan" ) ) {
          print "<td>";
          if ( $xport == 1 ) {
            print_item( $host_url, $server_url, "$lpar_url$NMON", "lan", $type, $type_sam, $entitle, $detail_yes, $start_unix, $end_unix, $html_base, "nolegend" );
            print "<td valign=\"top\"><font size=-1><A class=\"csvfloat\" HREF=\"/lpar2rrd-cgi/lpar2rrd-rep.sh?host=$host_url&mname=$server_url&lpar=$lpar_url&shour=$shour&smon=$smon&sday=$sday&syear=$syear&ehour=$ehour&emon=$emon&eday=$eday&eyear=$eyear&type=$type&height=$height&width=$width&yaxis=$yaxis&xport=1&item=$item\">CSV</A></font></td>";
          }
          print "</td>";
          print "</tr>\n";
          next;
        }
        if ( $item =~ m/^san/ && $entitle == 0 && test_file_in_directory( "$test_dir", "san" ) ) {
          print "<td>";
          if ( $xport == 1 ) {
            print_item( $host_url, $server_url, $lpar_url, $item, $type, $type_sam, $entitle, $detail_yes, $start_unix, $end_unix, $html_base, "nolegend" );
            print "<td valign=\"top\"><font size=-1><A class=\"csvfloat\" HREF=\"/lpar2rrd-cgi/lpar2rrd-rep.sh?host=$host_url&mname=$server_url&lpar=$lpar_url&shour=$shour&smon=$smon&sday=$sday&syear=$syear&ehour=$ehour&emon=$emon&eday=$eday&eyear=$eyear&type=$type&height=$height&width=$width&yaxis=$yaxis&xport=1&item=$item\">CSV</A></font></td>" if ( !defined $ENV{NMON_EXTERNAL} );
          }
          print "</td>";
          print "</tr>\n";
          next;
        }
        if ( $item =~ m/^nmon_san/ && $entitle == 0 && test_file_in_directory( "$test_dir_nmon", "san" ) ) {
          my $itm = $item;
          $itm =~ s/nmon_//;
          print "<td>";
          if ( $xport == 1 ) {
            print_item( $host_url, $server_url, "$lpar_url$NMON", $itm, $type, $type_sam, $entitle, $detail_yes, $start_unix, $end_unix, $html_base, "nolegend" );
            print "<td valign=\"top\"><font size=-1><A class=\"csvfloat\" HREF=\"/lpar2rrd-cgi/lpar2rrd-rep.sh?host=$host_url&mname=$server_url&lpar=$lpar_url&shour=$shour&smon=$smon&sday=$sday&syear=$syear&ehour=$ehour&emon=$emon&eday=$eday&eyear=$eyear&type=$type&height=$height&width=$width&yaxis=$yaxis&xport=1&item=$item\">CSV</A></font></td>";
          }
          print "</td>";
          print "</tr>\n";
          next;
        }
        if ( $item =~ m/^sea$/ && $entitle == 0 && test_file_in_directory( "$test_dir", "sea" ) ) {
          print "<td>";
          if ( $xport == 1 ) {
            print_item( $host_url, $server_url, $lpar_url, $item, $type, $type_sam, $entitle, $detail_yes, $start_unix, $end_unix, $html_base, "nolegend" );
            print "<td valign=\"top\"><font size=-1><A class=\"csvfloat\" HREF=\"/lpar2rrd-cgi/lpar2rrd-rep.sh?host=$host_url&mname=$server_url&lpar=$lpar_url&shour=$shour&smon=$smon&sday=$sday&syear=$syear&ehour=$ehour&emon=$emon&eday=$eday&eyear=$eyear&type=$type&height=$height&width=$width&yaxis=$yaxis&xport=1&item=$item\">CSV</A></font></td>" if ( !defined $ENV{NMON_EXTERNAL} );
          }
          print "</td>";
          print "</tr>\n";
          next;
        }
        if ( $item =~ m/^nmon_sea$/ && $entitle == 0 && test_file_in_directory( "$test_dir_nmon", "sea" ) ) {
          print "<td>";
          if ( $xport == 1 ) {
            print_item( $host_url, $server_url, "$lpar_url$NMON", "sea", $type, $type_sam, $entitle, $detail_yes, $start_unix, $end_unix, $html_base, "nolegend" );
            print "<td valign=\"top\"><font size=-1><A class=\"csvfloat\" HREF=\"/lpar2rrd-cgi/lpar2rrd-rep.sh?host=$host_url&mname=$server_url&lpar=$lpar_url&shour=$shour&smon=$smon&sday=$sday&syear=$syear&ehour=$ehour&emon=$emon&eday=$eday&eyear=$eyear&type=$type&height=$height&width=$width&yaxis=$yaxis&xport=1&item=$item\">CSV</A></font></td>";
          }
          next;
        }
        if ( $item =~ m/^ame$/ && $entitle == 0 && test_file_in_directory( "$test_dir", "ame" ) ) {
          print "<td>";
          if ( $xport == 1 ) {
            print_item( $host_url, $server_url, $lpar_url, $item, $type, $type_sam, $entitle, $detail_yes, $start_unix, $end_unix, $html_base, "legend" );
            print "<td valign=\"top\"><font size=-1><A class=\"csvfloat\" HREF=\"/lpar2rrd-cgi/lpar2rrd-rep.sh?host=$host_url&mname=$server_url&lpar=$lpar_url&shour=$shour&smon=$smon&sday=$sday&syear=$syear&ehour=$ehour&emon=$emon&eday=$eday&eyear=$eyear&type=$type&height=$height&width=$width&yaxis=$yaxis&xport=1&item=$item\">CSV</A></font></td>" if ( !defined $ENV{NMON_EXTERNAL} );
          }
          print "</td>";
          print "</tr>\n";
          next;
        }
        if ( $item =~ m/^nmon_ame$/ && $entitle == 0 && test_file_in_directory( "$test_dir_nmon", "ame" ) ) {
          print "<td>";
          if ( $xport == 1 ) {
            print_item( $host_url, $server_url, "$lpar_url$NMON", "ame", $type, $type_sam, $entitle, $detail_yes, $start_unix, $end_unix, $html_base, "legend" );
            print "<td valign=\"top\"><font size=-1><A class=\"csvfloat\" HREF=\"/lpar2rrd-cgi/lpar2rrd-rep.sh?host=$host_url&mname=$server_url&lpar=$lpar_url&shour=$shour&smon=$smon&sday=$sday&syear=$syear&ehour=$ehour&emon=$emon&eday=$eday&eyear=$eyear&type=$type&height=$height&width=$width&yaxis=$yaxis&xport=1&item=$item\">CSV</A></font></td>";
          }
          print "</td>";
          print "</tr>\n";
          next;
        }
        if ( $item =~ m/^san_resp$/ && $entitle == 0 && test_file_in_directory( "$test_dir", "san_resp" ) ) {
          print "<td>";
          if ( $xport == 1 ) {
            print_item( $host_url, $server_url, $lpar_url, $item, $type, $type_sam, $entitle, $detail_yes, $start_unix, $end_unix, $html_base, "legend" );
            print "<td valign=\"top\"><font size=-1><A class=\"csvfloat\" HREF=\"/lpar2rrd-cgi/lpar2rrd-rep.sh?host=$host_url&mname=$server_url&lpar=$lpar_url&shour=$shour&smon=$smon&sday=$sday&syear=$syear&ehour=$ehour&emon=$emon&eday=$eday&eyear=$eyear&type=$type&height=$height&width=$width&yaxis=$yaxis&xport=1&item=$item\">CSV</A></font></td>" if ( !defined $ENV{NMON_EXTERNAL} );
          }
          print "</td>";
          print "</tr>\n";
          next;
        }
        if ( $item =~ m/^total_iops$/ && $entitle == 0 && test_file_in_directory( "$test_dir", "disk-total" ) ) {
          print "<td>";
          if ( $xport == 1 ) {
            print_item( $host_url, $server_url, $lpar_url, $item, $type, $type_sam, $entitle, $detail_yes, $start_unix, $end_unix, $html_base, "legend" );
            print "<td valign=\"top\"><font size=-1><A class=\"csvfloat\" HREF=\"/lpar2rrd-cgi/lpar2rrd-rep.sh?host=$host_url&mname=$server_url&lpar=$lpar_url&shour=$shour&smon=$smon&sday=$sday&syear=$syear&ehour=$ehour&emon=$emon&eday=$eday&eyear=$eyear&type=$type&height=$height&width=$width&yaxis=$yaxis&xport=1&item=$item\">CSV</A></font></td>" if ( !defined $ENV{NMON_EXTERNAL} );
          }
          print "</td>";
          print "</tr>\n";
          next;
        }
        if ( $item =~ m/^total_data$/ && $entitle == 0 && test_file_in_directory( "$test_dir", "disk-total" ) ) {
          print "<td>";
          if ( $xport == 1 ) {
            print_item( $host_url, $server_url, $lpar_url, $item, $type, $type_sam, $entitle, $detail_yes, $start_unix, $end_unix, $html_base, "legend" );
            print "<td valign=\"top\"><font size=-1><A class=\"csvfloat\" HREF=\"/lpar2rrd-cgi/lpar2rrd-rep.sh?host=$host_url&mname=$server_url&lpar=$lpar_url&shour=$shour&smon=$smon&sday=$sday&syear=$syear&ehour=$ehour&emon=$emon&eday=$eday&eyear=$eyear&type=$type&height=$height&width=$width&yaxis=$yaxis&xport=1&item=$item\">CSV</A></font></td>" if ( !defined $ENV{NMON_EXTERNAL} );
          }
          print "</td>";
          print "</tr>\n";
          next;
        }
        if ( $item =~ m/^total_latency$/ && $entitle == 0 && test_file_in_directory( "$test_dir", "disk-total" ) ) {
          print "<td>";
          if ( $xport == 1 ) {
            print_item( $host_url, $server_url, $lpar_url, $item, $type, $type_sam, $entitle, $detail_yes, $start_unix, $end_unix, $html_base, "legend" );
            print "<td valign=\"top\"><font size=-1><A class=\"csvfloat\" HREF=\"/lpar2rrd-cgi/lpar2rrd-rep.sh?host=$host_url&mname=$server_url&lpar=$lpar_url&shour=$shour&smon=$smon&sday=$sday&syear=$syear&ehour=$ehour&emon=$emon&eday=$eday&eyear=$eyear&type=$type&height=$height&width=$width&yaxis=$yaxis&xport=1&item=$item\">CSV</A></font></td>" if ( !defined $ENV{NMON_EXTERNAL} );
          }
          print "</td>";
          print "</tr>\n";
          next;
        }
      }
    }
  }

  print "</table></center>\n";
  return 1;
}

# print a link with detail
sub print_item {
  my ( $host_url, $server_url, $lpar_url, $item, $time_graph, $type_sam, $entitle, $detail, $start_unix, $end_unix, $html_base, $legend ) = @_;
  my $upper        = 0;    # same limit for all 4 graphs, not used in hist graphs
                           # print STDERR "627 lpar2rrd-cgi \$host_url $host_url \$server_url $server_url \$lpar_url $lpar_url \$item $item\n";
  my $legend_class = "";
  if ( $legend =~ m/nolegend/ ) {
    $legend_class = "nolegend";    # enable RRD graph clickable legend
  }

  # $time_graph contains step in seconds, is directly passsed to detail-graph-cgi & for xport too
  $type_sam = "m";                 # since 4.66 is always

  #$lpar_url =~s/([^A-Za-z0-9\+-_])/sprintf("%%%02X",ord($1))/seg;
  #$host_url =~s/([^A-Za-z0-9\+-_])/sprintf("%%%02X",ord($1))/seg;
  #$server_url =~s/([^A-Za-z0-9\+-_])/sprintf("%%%02X",ord($1))/seg;

  if ( $detail > 0 ) {
    print "<div class=\"relpos\">
             <div>
                <div class=\"g_title\">
                  <div class=\"popdetail\"></div>
                  <div class=\"g_text\" data-server=\"$server_url\"data-lpar=\"$lpar_url\" data-item=\"$item\" data-time=\"$time_graph\"><span></span></div>
                </div>
                  <a class=\"detail\" href=\"/lpar2rrd-cgi/$detail_graph.sh?host=$host_url&server=$server_url&lpar=$lpar_url&item=$item&time=$time_graph&type_sam=$type_sam&detail=1&upper=$upper&entitle=$entitle&sunix=$start_unix&eunix=$end_unix&height=$height_detail&width=$width_detail\">
                     <div title=\"Click to show detail\"><img class=\"$legend_class lazy\" border=\"0\" data-src=\"/lpar2rrd-cgi/$detail_graph.sh?host=$host_url&server=$server_url&lpar=$lpar_url&item=$item&time=$time_graph&type_sam=$type_sam&detail=$detail_9&upper=$upper&entitle=$entitle&sunix=$start_unix&eunix=$end_unix&height=$height&width=$width\" src=\"css/images/sloading.gif\" >
                       <div class=\"zoom\" title=\"Click and drag to select range\"></div>
                     </div>
                  </a>
              </div>
              <div class=\"legend\"></div>
           </div> \n";
  }
  else {
    print "<div class=\"relpos\">
             <div>
               <img class=\"lazy\" border=\"0\" data-src=\"/lpar2rrd-cgi/$detail_graph.sh?host=$host_url&server=$server_url&lpar=$lpar_url&item=$item&time=$time_graph&type_sam=$type_sam&detail=0&upper=$upper&entitle=$entitle&sunix=$start_unix&eunix=$end_unix&height=$height&width=$width\"src=\"css/images/sloading.gif\" >
                 <div class=\"zoom\" title=\"Click and drag to select range\"></div>
             </div>
           </div>\n";
  }
  return 1;
}

sub test_file_in_directory {

  # Use a regular expression to find files
  #    beginning by $fpn
  #    ending by .mmm
  #    returns 0 (zero) or first filename found i.e. non zero

  my $dir = shift;
  my $fpn = shift;

  my $found = 0;
  if ( !-d $dir ) { return $found; }
  opendir( DIR, $dir ) || error( "Error in opening dir $dir $! :" . __FILE__ . ":" . __LINE__ ) && return 0;

  while ( my $file = readdir(DIR) ) {
    if ( $file =~ m/^$fpn.*\.mmm$/ ) {

      #if ($file =~ m/\.mmm$/) {
      $found = "$dir/$file";
      last;

      #}
    }
  }
  closedir(DIR);
  return $found;
}

sub isdigit {
  my $digit = shift;

  my $digit_work = $digit;
  $digit_work =~ s/[0-9]//g;
  $digit_work =~ s/\.//;

  if ( length($digit_work) == 0 ) {

    # is a number
    return 1;
  }

  #if (($digit * 1) eq $digit){
  #  # is a number
  #  return 1;
  #}

  # NOT a number
  #error ("there was expected a digit but a string is there, field: $text , value: $digit");
  return 0;
}

