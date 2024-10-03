use strict;
use warnings;

use Xorux_lib;

# use CGI::Carp qw(fatalsToBrowser);
use Time::Local;
use POSIX qw(mktime strftime);
use Data::Dumper;

# use PowerDataWrapper;
# use Overview;
my $acl;

if ( $ENV{HTTP_XORUX_APP} && $ENV{HTTP_XORUX_APP} eq "Xormon" ) {
  require ACLx;
  $acl = ACLx->new();
}
else {
  require ACL;
  $acl = ACL->new();
}

# my ( $SERV, $CONF ) = PowerDataWrapper::init();

#
# basic variables
#
RRDp::start "$ENV{RRDTOOL}";
my $basedir = $ENV{INPUTDIR} || Xorux_lib::error("INPUTDIR in not defined!") && exit;
my $webdir  = $ENV{WEBDIR} ||= "$basedir/www";
my $wrkdir  = "$basedir/data";
my $tmpdir  = "$basedir/tmp";
if ( defined $ENV{TMPDIR_LPAR} ) {
  $tmpdir = $ENV{TMPDIR_LPAR};
}
my $bindir = "$basedir/bin";

#eval (require "$bindir/reporter.pl");

my $table_width = "900px";

my ( $sunix, $eunix );

sub getURLparams {
  my ( $buffer, $PAR );

  if ( defined $ENV{'REQUEST_METHOD'} ) {
    if ( lc $ENV{'REQUEST_METHOD'} eq "post" ) {
      read( STDIN, $buffer, $ENV{'CONTENT_LENGTH'} );
    }
    else {
      $buffer = $ENV{'QUERY_STRING'};
    }

    $PAR = Xorux_lib::parse_url_params($buffer);

    return $PAR;
  }
  else {
    return 0;
  }
}

my $params = getURLparams();

print "Content-type: text/html\n\n";

# print STDERR Dumper ($params);

#print "<pre>";
#print Dumper $params;
#print "</pre>";

print "<center>";

#
# set report time range
#
$eunix = "";
$sunix = "";

if ( exists $params->{timerange} ) {
  ( $sunix, $eunix ) = set_report_timerange( $params->{timerange} );
  my $diff = $eunix - $sunix;
}
elsif ( exists $params->{sunix} && exists $params->{eunix} ) {
  $sunix = $params->{sunix};
  $eunix = $params->{eunix};
}
else {
  Xorux_lib::error( "Cannot set report timerange! QUERY_STRING=''  $!" . __FILE__ . ":" . __LINE__ ) && exit;
}

my @menu_vmware = ();

my @vcenters_configs = ();
my $vcenter_name     = $params->{vcenter};
my $cluster_name     = $params->{source};

my $html_file = "$tmpdir/vcenters_clusters_config.html";
if ( open( my $FH, "< $html_file" ) ) {
  my $thead = 1;
  foreach (<$FH>) {    # heading
    push @vcenters_configs, $_ if $thead;
    $thead = 0 if ( index( $_, "</thead>" ) != -1 );

    # chosen cluster info
    push @vcenters_configs, $_ if ( ( index( $_, $vcenter_name ) != -1 ) && ( ( index( $_, $cluster_name . ">" ) != -1 ) or ( index( $_, $cluster_name . "<" ) != -1 ) ) );
  }
  close $FH;
  push @vcenters_configs, "</TABLE></CENTER>";    # end of table
}
else {
  error( "Cannot open file $html_file: $!" . __FILE__ . ":" . __LINE__ );
}

# print "<a class='pdffloat' href='Premium_support_LPAR2RRD.pdf' target='_blank' title='PDF' style='position: fixed; top: 70px; right: 16px;'></a>";
# it is in overview_vmware.html

print "<h4>Configuration</h4>";

print "@vcenters_configs\n";

# print STDERR "---\n @vcenters_configs ---\n";

# get uid cluster & vcenter from menu.txt

read_menu_vmware( \@menu_vmware );

my @matches = grep { /^A/ && /cluster_$cluster_name/ } @menu_vmware;

# print STDERR "123 @matches\n";
if ( !@matches || scalar @matches < 1 ) {
  error( "no menu item for ^A cluster_$cluster_name: $!" . __FILE__ . ":" . __LINE__ );
  exit;
}

# A:10.22.11.10:cluster_2nd Cluster:Totals:/lpar2rrd-cgi/detail.sh?host=cluster_domain-c314&server=vmware_eb6102a7-1fa0-4376-acbb-f67e34a2212c_28&lpar=nope&item=cluster&entitle=0&gui=1&none=none::Hosting::V:
( my $cluster_uuid, my $vcenter_uuid ) = split "&server=", $matches[0];

# print STDERR "131 $cluster_uuid $vcenter_uuid\n";

( undef, $cluster_uuid ) = split "host=", $cluster_uuid;
( $vcenter_uuid, undef ) = split "&lpar=", $vcenter_uuid;

# res pool config table if exists
print "<h4>Resource pools configuration</h4>";

$html_file = "$wrkdir/$vcenter_uuid/$cluster_uuid/rp_config.html";
if ( -f "$html_file" ) {
  print_html_file( urldecode("$html_file") );
}

# get cluster performance data
my $rrd    = "$wrkdir/$vcenter_uuid/$cluster_uuid/cluster.rrc";
my $answer = "";
eval {
  RRDp::cmd qq(graph "anyname"
      "--start" "$sunix"
      "--end" "$eunix"
      "--step=60"

      "DEF:cpu_MHz=\"$rrd\":CPU_total_MHz:AVERAGE"
      "CDEF:cpu=cpu_MHz,1000,/"
      "DEF:cpuutiltot_MHz=\"$rrd\":CPU_usage_MHz:AVERAGE"
      "CDEF:cpuutiltot=cpuutiltot_MHz,1000,/"

      "DEF:total=$rrd:Memory_total_MB:AVERAGE"
      "DEF:granted=$rrd:Memory_granted_KB:AVERAGE"
      "DEF:active=$rrd:Memory_active_KB:AVERAGE"
      "DEF:consumed=$rrd:Memory_consumed_KB:AVERAGE"
      "DEF:balloon=$rrd:Memory_baloon_KB:AVERAGE"
      "DEF:swap=$rrd:Memory_swap_KB:AVERAGE"
      "CDEF:grantg=granted,1024,/,1024,/"
      "CDEF:activeg=active,1024,/,1024,/"
      "CDEF:totg=total,1024,/"
      "CDEF:consumg=consumed,1024,/,1024,/"
      "CDEF:balloong=balloon,1024,/,1024,/"
      "CDEF:swapg=swap,1024,/,1024,/"
      "CDEF:grantb=granted,1024,*"
      "CDEF:activeb=active,1024,*"
      "CDEF:totb=total,1024,*,1024,*"
      "CDEF:consumb=consumed,1024,*"
      "CDEF:balloonb=balloon,1024,*"
      "CDEF:swapb=swap,1024,*"

      "PRINT:cpu:AVERAGE:cpu %2.0lf"
      "PRINT:cpuutiltot:AVERAGE:cpuutil %2.0lf"
      "PRINT:totg:AVERAGE:total %2.0lf"
      "PRINT:grantg:AVERAGE:granted %2.0lf"
      "PRINT:activeg:AVERAGE:active %2.0lf"
      "PRINT:consumg:AVERAGE:consumed %2.0lf"
      "PRINT:balloong:AVERAGE:balloon %2.2lf"
      "PRINT:swapg:AVERAGE:svap %2.2lf"

      "PRINT:cpu:MAX:cpu %2.0lf"
      "PRINT:cpuutiltot:MAX:cpuutil %2.0lf"
      "PRINT:totg:MAX:total %2.0lf"
      "PRINT:grantg:MAX:granted %2.0lf"
      "PRINT:activeg:MAX:active %2.0lf"
      "PRINT:consumg:MAX:consumed %2.0lf"
      "PRINT:balloong:MAX:balloon %2.2lf"
      "PRINT:swapg:MAX:svap %2.2lf"
      );
  $answer = RRDp::read;
};
if ($@) {
  if ( $@ =~ "ERROR" ) {
    error("Rrrdtool error : $@");
    exit;
  }
}
my $aaa = $$answer;

#if ( $aaa =~ /NaNQ/ ) { next; }
( undef, my $cpu, my $cpuutiltot, my $total, my $granted, my $active, my $consumed, my $balloon, my $svap, my $cpu_x, my $cpuutiltot_x, my $total_x, my $granted_x, my $active_x, my $consumed_x, my $balloon_x, my $svap_x ) = split( "\n", $aaa );
$cpu          =~ s/cpu\s+//g;
$cpuutiltot   =~ s/cpuutil\s+//g;
$total        =~ s/total\s+//g;
$granted      =~ s/granted\s+//g;
$active       =~ s/active\s+//g;
$consumed     =~ s/consumed\s+//g;
$balloon      =~ s/balloon\s+//g;
$svap         =~ s/svap\s+//g;
$cpu_x        =~ s/cpu\s+//g;
$cpuutiltot_x =~ s/cpuutil\s+//g;
$total_x      =~ s/total\s+//g;
$granted_x    =~ s/granted\s+//g;
$active_x     =~ s/active\s+//g;
$consumed_x   =~ s/consumed\s+//g;
$balloon_x    =~ s/balloon\s+//g;
$svap_x       =~ s/svap\s+//g;

print "<CENTER><h4>Performance</h4>";
print "<table class=\"tablesorter tablesorter-ice nofilter\" style=\"width:$table_width\">\n";
print "<thead>\n";
print "<tr>\n";
print "  <th class='sortable'>$cluster_name</th>\n";
print "  <th class='sortable'>average</th>\n";
print "  <th class='sortable'>maximum</th>\n";
print "</tr>\n";
print "</thead><tbody>\n";

print "<TR>
<TD><B>CPU Total effective [Ghz]</B></TD>
<TD align=\"left\">$cpu</TD>
<TD align=\"left\">$cpu_x</TD>
</TR>
<TR>
<TD><B>CPU Utilization [Ghz]</B></TD>
<TD align=\"left\">$cpuutiltot</TD>
<TD align=\"left\">$cpuutiltot_x</TD>
</TR>
<TR>
<TD><B>Memory Total effective [GB]</B></TD>
<TD align=\"left\">$total</TD>
<TD align=\"left\">$total_x</TD>
</TR>
<TR>
<TD><B>Memory Granted [GB]</B></TD>
<TD align=\"left\">$granted</TD>
<TD align=\"left\">$granted_x</TD>
</TR>
<TR>
<TD><B>Memory Consumed [GB]</B></TD>
<TD align=\"left\">$active</TD>
<TD align=\"left\">$active_x</TD>
</TR>
<TR>
<TD><B>Memory Active [GB]</B></TD>
<TD align=\"left\">$consumed</TD>
<TD align=\"left\">$consumed_x</TD>
</TR>
<TR>
<TD><B>Memory Balloon [GB]</B></TD>
<TD align=\"left\">$balloon</TD>
<TD align=\"left\">$balloon_x</TD>
</TR>
<TR>
<TD><B>Memory Swap out [GB]</B></TD>
<TD align=\"left\">$svap</TD>
<TD align=\"left\">$svap_x</TD>
</TR>\n";
print "</tr></tbody></table></CENTER>";

# 140 detail-graph-cgi.pl $QUERY_STRING host=cluster_domain-c7&server=vmware_ef81e113-3f75-4e78-bc8c-a86df46a4acb_12&lpar=nope&item=clustcpu&time=d&type_sam=m&detail=9&entitle=0&d_platform=VMware&sunix=1634050024&eunix=1634120656
# need to prepare
# print_graph("host=$hmc_label&server=$server&lpar=sas-totals&item=power_sas_data&time=d&type_sam=m&detail=5&sunix=$sunix&eunix=$eunix&overview_power=1");

print "<CENTER><table>";

my $item = "clustcpu";
print_graph("host=$cluster_uuid&server=$vcenter_uuid&lpar=nope&item=$item&time=d&type_sam=m&detail=7&entitle=0&d_platform=VMware&sunix=$sunix&eunix=$eunix&width=900");

#$item = "clustlpar";
#print_graph("host=$cluster_uuid&server=$vcenter_uuid&lpar=nope&item=$item&time=d&type_sam=m&detail=7&entitle=0&d_platform=VMware&sunix=$sunix&eunix=$eunix&width=900");

$item = "clustmem";
print_graph("host=$cluster_uuid&server=$vcenter_uuid&lpar=nope&item=$item&time=d&type_sam=m&detail=7&entitle=0&d_platform=VMware&sunix=$sunix&eunix=$eunix&width=900");

$item = "clustser";
print_graph("host=$cluster_uuid&server=$vcenter_uuid&lpar=nope&item=$item&time=d&type_sam=m&detail=7&entitle=0&d_platform=VMware&sunix=$sunix&eunix=$eunix&width=900");

#$item = "clustlpardy";
#print_graph("host=$cluster_uuid&server=$vcenter_uuid&lpar=nope&item=$item&time=d&type_sam=m&detail=7&entitle=0&d_platform=VMware&sunix=$sunix&eunix=$eunix&width=900");

$item = "clustlan";
print_graph("host=$cluster_uuid&server=$vcenter_uuid&lpar=nope&item=$item&time=d&type_sam=m&detail=7&entitle=0&d_platform=VMware&sunix=$sunix&eunix=$eunix&width=900");

print "</table></CENTER>";
print "</div>";
exit;

# read tmp/menu_vmware.txt
sub read_menu_vmware {
  my $menu_ref = shift;
  open( FF, "<$tmpdir/menu_vmware.txt" ) || error( "can't open $tmpdir!menu.txt: $! :" . __FILE__ . ":" . __LINE__ ) && return 0;
  @$menu_ref = (<FF>);
  close(FF);
  return;
}

sub print_html_file {
  my $file = shift;

  #open (my $in, "<", $file) || error ("Cannot read $file ".__FILE__.":".__LINE__."\n") && return -1;
  #my @lines = <$in>;
  #close($in);
  #  print "<div>\n";
  my $file_html = $file;
  my $print_html;
  if ( -f "$file_html" ) {
    open( FH, "< $file_html" );
    $print_html = do { local $/; <FH> };
    close(FH);
    print "$print_html";
  }
      #  print "</div>\n";
}

sub urldecode {
  my $s = shift;
  if ($s) {
    $s =~ s/\%([A-Fa-f0-9]{2})/pack('C', hex($1))/seg;
  }
  return $s;
}

sub print_graph {
  my $link = shift;

  #  print "<a href=\"$link\">text</a>\n";
  print "<tr><td align='center' valign='top'><div><img class='lazy' border='0' data-src='/lpar2rrd-cgi/detail-graph.sh?$link' src='css/images/sloading.gif'></div></td></tr>\n";
}

sub set_report_timerange {
  my $time  = shift;
  my $sunix = 0;
  my $eunix = 0;

  my $day_sec  = 60 * 60 * 24;
  my $act_time = time();
  my ( $act_sec, $act_min, $act_hour, $act_day, $act_month, $act_year, $act_wday, $act_yday, $act_isdst ) = localtime();

  if ( $time eq "prevHour" ) {
    $eunix = mktime( 0, 0, $act_hour, $act_day, $act_month, $act_year );
    $sunix = $eunix - ( 60 * 60 );
  }
  elsif ( $time eq "prevDay" ) {
    $eunix = mktime( 0, 0, 0, $act_day, $act_month, $act_year );
    $sunix = $eunix - $day_sec;

    adjust_timerange();
  }
  elsif ( $time eq "prevWeek" ) {
    $eunix = mktime( 0, 0, 0, $act_day, $act_month, $act_year );
    $eunix = $eunix - ( ( $act_wday - 1 ) * $day_sec );
    $sunix = $eunix - ( 7 * $day_sec );

    adjust_timerange();
  }
  elsif ( $time eq "prevMonth" ) {
    $sunix = mktime( 0, 0, 0, 1, $act_month - 1, $act_year );
    $eunix = mktime( 0, 0, 0, 1, $act_month,     $act_year );

    adjust_timerange();
  }
  elsif ( $time eq "prevYear" ) {
    $sunix = mktime( 0, 0, 0, 1, 0, $act_year - 1 );
    $eunix = mktime( 0, 0, 0, 1, 0, $act_year );

    adjust_timerange();
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
  return ( 1,      1 );
}

sub adjust_timerange {

  # perl <5.12 has got some problems on aix with DST (daylight saving time)
  # sometimes there is one hour difference
  # therefore align the time to midnight again
  if ( $sunix eq "" ) { $sunix = 0; }
  if ( $eunix eq "" ) { $eunix = 0; }
  my ( $s_sec, $s_min, $s_hour, $s_day, $s_month, $s_year, $s_wday, $s_yday, $s_isdst ) = localtime($sunix);
  $sunix = mktime( 0, 0, 0, $s_day, $s_month, $s_year, $s_wday, $s_yday, $s_isdst );
  my ( $e_sec, $e_min, $e_hour, $e_day, $e_month, $e_year, $e_wday, $e_yday, $e_isdst ) = localtime($eunix);
  $eunix = mktime( 0, 0, 0, $e_day, $e_month, $e_year, $e_wday, $e_yday, $e_isdst );

  return 1;
}

# error handling
sub error {
  my $text     = shift;
  my $act_time = localtime();
  chomp($text);

  #print "ERROR          : $text : $!\n";
  print STDERR "$act_time: $text : $!\n";

  return 1;
}

RRDp::end;
