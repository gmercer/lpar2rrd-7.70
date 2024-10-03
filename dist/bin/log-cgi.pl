
#use strict;
# no strict as definition of @inp does not work with it, o idea why ....

#use lib qw (/opt/freeware/lib/perl/5.8.0);
# no longer need to use "use lib qw" as the library PATH is already in PERL5LIB (lpar2rrd.cfg)

use Env qw(QUERY_STRING);
use Date::Parse;

# print CGI-BIN HTML header
print "Content-type: text/html\n\n";

#$QUERY_STRING .= ":.";

my $inputdir = $ENV{INPUTDIR};
my $webdir   = $ENV{WEBDIR};
my $wrkdir   = "$inputdir/data";
my $DEBUG    = $ENV{DEBUG};
my $errlog   = $ENV{ERRLOG};

my $bindir = $ENV{BINDIR};

open( OUT, ">> $errlog" ) if $DEBUG == 2;

( my $ftype, my $gui ) = split( /&/, $QUERY_STRING );

$ftype =~ s/name=//;
$ftype =~ s/:\.$//;
$gui   =~ s/gui=//;
if ( $gui eq '' ) {
  $gui = 0;
}

if ( $gui == 0 ) {
  print_header();
}

my $done = 0;

if ( $ftype =~ m/maincfg/ ) { print_plain( $ftype, "lpar2rrd.cfg", "Configuration file: ", "", );                              $done = 1; }
if ( $ftype =~ m/favcfg/ )  { print_valid( $ftype, "favourites.cfg", "Favourites configuration file: ", "", );                 $done = 1; }
if ( $ftype =~ m/custcfg/ ) { print_valid( $ftype, "web_config/custom_groups.cfg", "Custom Groups configuration file:", "", ); $done = 1; }
if ( $ftype =~ m/alrtcfg/ ) { print_valid( $ftype, "web_config/alerting.cfg", "Alert configuration file:", "", );              $done = 1; }

#if ( $ftype =~ m/alhist/ ) { print_log( $ftype, "alert_history.log","Alert history log (last 500 rows):","",1, 500 );  $done = 1; }
if ( $ftype =~ m/alhist/ )       { print_table( $ftype, "alert_history.log", "Alert history log (last 500 rows):", "", 1, 500 );          $done = 1; }
if ( $ftype =~ m/alert_hw_log/ ) { print_table_hw( $ftype, "alert_event_history.log", "Alert history log (last 500 rows):", "", 1, 500 ); $done = 1; }
if ( $ftype =~ m/loadout/ )      { print_log( $ftype, "load.out", "Last run log:", "", 0, 0 );                                            $done = 1; }

#if ( $ftype =~ m/apache/ )  { print_log( $ftype, "/var/log/httpd/error_log", "Apache error log (last 500 rows):","",1, 500 );  $done = 1; }
if ( $ftype =~ m/apache/ ) {
  if ( defined $ENV{VI_IMAGE} && $ENV{VI_IMAGE} == 1 ) {
    print_log( $ftype, "/var/log/httpd/error_log", "Apache error log (last 500 rows):", "", 1, 500 );
    $done = 1;
  }
  else {
    $done = 1;
  }
}
if ( $ftype =~ m/errlogvm/ )            { print_log( $ftype, "error.log-vmware",                   "VMware error log (last 500 rows):",               "",                                                                                    1, 500 );  $done = 1; }
if ( $ftype =~ m/errlog$/ )             { print_log( $ftype, "error.log",                          "Error log (last 500 rows):",                      "",                                                                                    1, 500 );  $done = 1; }
if ( $ftype =~ m/errcgi/ )              { print_log( $ftype, "error-cgi.log",                      "cgi-bin error log (last 500 rows):",              "",                                                                                    1, 500 );  $done = 1; }
if ( $ftype =~ m/entitle/ )             { print_log( $ftype, "entitle-check.log",                  "CPU Configuration Advisor log (last 1000 rows):", "<a href=\"http://www.lpar2rrd.com/cpu_configuration_advisor.html\">How it works</a>", 1, 1000 ); $done = 1; }
if ( $ftype =~ m/errlogdaemon/ )        { print_log( $ftype, "error.log-daemon",                   "Daemon error log (last 500 rows):",               "",                                                                                    1, 500 );  $done = 1; }
if ( $ftype =~ m/errloghyperv/ )        { print_log( $ftype, "error.log-hyperv",                   "Hyper-V error log (last 500 rows):",              "",                                                                                    1, 500 );  $done = 1; }
if ( $ftype =~ m/errlogovirt/ )         { print_log( $ftype, "error.log-ovirt",                    "oVirt/RHV error log (last 500 rows):",            "",                                                                                    1, 500 );  $done = 1; }
if ( $ftype =~ m/errlogxen/ )           { print_log( $ftype, "error.log-xen",                      "XenServer error log (last 500 rows):",            "",                                                                                    1, 500 );  $done = 1; }
if ( $ftype =~ m/errlognutanix/ )       { print_log( $ftype, "error.log-nutanix",                  "Nutanix error log (last 500 rows):",              "",                                                                                    1, 500 );  $done = 1; }
if ( $ftype =~ m/errlogaws/ )           { print_log( $ftype, "error.log-aws",                      "Amazon Web Services error log (last 500 rows):",  "",                                                                                    1, 500 );  $done = 1; }
if ( $ftype =~ m/errloggcloud/ )        { print_log( $ftype, "error.log-gcloud",                   "Google Cloud error log (last 500 rows):",         "",                                                                                    1, 500 );  $done = 1; }
if ( $ftype =~ m/errlogazure/ )         { print_log( $ftype, "error.log-azure",                    "Microsoft Azure error log (last 500 rows):",      "",                                                                                    1, 500 );  $done = 1; }
if ( $ftype =~ m/errlogkubernetes/ )    { print_log( $ftype, "error.log-kubernetes",               "Kubernetes error log (last 500 rows):",           "",                                                                                    1, 500 );  $done = 1; }
if ( $ftype =~ m/errlogopenshift/ )     { print_log( $ftype, "error.log-openshift",                "Openshift error log (last 500 rows):",            "",                                                                                    1, 500 );  $done = 1; }
if ( $ftype =~ m/errlogcloudstack/ )    { print_log( $ftype, "error.log-cloudstack",               "Cloudstack error log (last 500 rows):",           "",                                                                                    1, 500 );  $done = 1; }
if ( $ftype =~ m/errlogproxmox/ )       { print_log( $ftype, "error.log-proxmox",                  "Proxmox error log (last 500 rows):",              "",                                                                                    1, 500 );  $done = 1; }
if ( $ftype =~ m/errlogfusioncompute/ ) { print_log( $ftype, "error.log-fusioncompute",            "Huawei FusionCompute error log (last 500 rows):", "",                                                                                    1, 500 );  $done = 1; }
if ( $ftype =~ m/errlogdocker/ )        { print_log( $ftype, "error.log-docker",                   "Docker error log (last 500 rows):",               "",                                                                                    1, 500 );  $done = 1; }
if ( $ftype =~ m/errlogibmrest/ )       { print_log( $ftype, "error.log-hmc_rest_api",             "IBM Power REST API error log (last 500 rows):",   "",                                                                                    1, 500 );  $done = 1; }
if ( $ftype =~ m/counters/ )            { print_log( $ftype, "counter-info.txt",                   "VMWARE counters log:",                            "",                                                                                    0, 0 );    $done = 1; }
if ( $ftype =~ m/errlogoracledb/ )      { print_log( $ftype, "error.log-oracledb",                 "OracleDB error log (last 500 rows):",             "",                                                                                    1, 500 );  $done = 1; }
if ( $ftype =~ m/errlogsqlserver/ )     { print_log( $ftype, "error.log-sqlserver",                "SQLServer error log (last 500 rows):",            "",                                                                                    1, 500 );  $done = 1; }
if ( $ftype =~ m/errlogdb2/ )           { print_log( $ftype, "error.log-db2",                      "IBM Db2 error log (last 500 rows):",              "",                                                                                    1, 500 );  $done = 1; }
if ( $ftype =~ m/errlogpostgres/ )      { print_log( $ftype, "error.log-postgres",                 "PostgreSQL error log (last 500 rows):",           "",                                                                                    1, 500 );  $done = 1; }
if ( $ftype =~ m/errlogoraclevm/ )      { print_log( $ftype, "error.log-oraclevm",                 "OracleVM error log (last 500 rows):",             "",                                                                                    1, 500 );  $done = 1; }
if ( $ftype =~ m/audit/ )               { print_log( $ftype, "$inputdir/etc/web_config/audit.log", "Audit log (last 500 rows):",                      "",                                                                                    0, 500 );  $done = 1; }

if ( $done == 0 ) {
  error("wrong parameter: $ftype : $QUERY_STRING");
}

if ( $gui == 0 ) {
  print_trailer();
}

exit 0;

sub print_plain {
  my $ftype     = shift;
  my $file_base = shift;
  my $text      = shift;
  my $file      = $inputdir . "/etc/web_config/" . $file_base;

  if ( !-f "$file" ) {
    $file = $inputdir . "/etc/" . $file_base;
  }

  if ( !-f "$file" ) {
    print "<CENTER><B>$text $file</B></CENTER>";
    print "<B>File: $file does not exist</B>";
    return 0;
  }

  open( FH, "< $file" ) || error("$0: Can't open $file") && return 0;
  print "<CENTER><B>$text $file</B></CENTER><PRE>";
  foreach my $line (<FH>) {
    if ( $line =~ m/^export / ) {
      next;    # exclude exporting variables lines
    }
    print "$line";
  }
  return 1;
}

sub print_valid {
  my $ftype     = shift;
  my $file_base = shift;
  my $text      = shift;
  my $file      = $inputdir . "/etc/" . $file_base;
  my $file_org  = $file;

  if ( !-f "$file" ) {
    $file =~ s/alerting.cfg/alert.cfg/ if $file =~ /alerting.cfg/;
    $file =~ s/web_config\///;    # try once more with the GUI cfg (old way)

    if ( !-f "$file" ) {
      print "<B>$text $file_org</B><br>";
      print "<B>File: $file or $file_org does not exist</B>";
      return 0;
    }
  }

  open( FH, "< $file" ) || error("$0: Can't open $file") && return 0;
  print "<CENTER><B>$text $file</B></CENTER><PRE>";
  foreach my $line (<FH>) {
    if ( $line =~ m/^#LPAR/ || $line =~ m/^#POOL/ ) {
      next;    # print only valid lines
    }
    if ( $ftype =~ m/custcfg/ || $ftype =~ m/favcfg/ ) {
      if ( $line =~ m/^LPAR/ || $line =~ m/^POOL/ ) {
        my $group = "";
        ( my $type, my $server, my $lpar, $group ) = split( /:/, $line );
        if ( $group =~ m/^$/ ) {
          next;    # print only valid lines
        }
      }
    }
    print "$line";
  }
  return 1;
}

sub print_table {
  use POSIX qw(strftime);
  use Date::Parse;
  my $type      = shift;
  my $file_base = shift;
  my $text      = shift;
  my $text_tail = shift;
  my $reverse   = shift;
  my $max_rows  = shift;
  my $file      = $inputdir . "/logs/" . $file_base;

  if ( $file_base =~ m/^\// ) {

    # absolute path
    $file = $file_base;
  }

  if ( !-f "$file" ) {
    print "<CENTER><B>$text $file $text_tail</B></CENTER>";
    print "<B>File: $file does not exist</B>";
    return 0;
  }
  print "<CENTER><B>$text $file $text_tail</B></CENTER><PRE>";

  my @lines;
  my $data;
  if ( $max_rows > 0 ) {
    @lines = `tail -$max_rows $file`;
  }
  else {
    @lines = `cat $file`;
  }
  if ( $reverse == 1 ) {
    my @reverse = reverse @lines;
    @lines = @reverse;
  }

  #if ( $reverse == 1 ) {
  #  print reverse @lines;
  #}
  #else {
  #  print @lines;
  #}
  print "<table class='tabconfig tablesorter'>";
  print "<thead>";
  print "<tr>";
  print "<th class='sortable'>Date/Time</th><th class='sortable'>Server</th><th class='sortable'>Subsystem</th><th class='sortable'>Item</th><th class='sortable'>Reason</th>";
  print "</tr>";
  print "</thead>";
  print "<tbody>";

  foreach my $line (@lines) {

    #Mon Jun  7 07:38:10 2021; PAGING 2; LPAR; Linux; vm-lukas; actual util:9.70%, limit max:0%,
    #Mon Jun  7 07:38:10 2021; MEMORY; LPAR; Linux; vm-lukas; actual util:60.28%, limit max:0%,
    #Mon Jun  7 07:50:11 2021; OS CPU; LPAR; Linux; vm-lukas; actual util:1.84%, limit max:0%,
    if ( $line eq "" || !defined $line ) { next; }
    chomp $line;
    if ( $line eq "" || !defined $line ) { next; }
    my ( $time, $metric, $type, $server, $vm, $message ) = split( "; ", $line );
    if ( !defined $time || !defined $metric || !defined $server || !defined $vm ) { next; }
    if ( !defined $type ) {
      $type = "";
    }
    if ( !defined $message ) {
      $message = "";
    }
    my $subsystem = "";
    if ( $metric eq "Multipath" ) {
      $subsystem = "$vm";
    }
    else {
      $subsystem = "$type:$vm";
    }
    my $timestamp = str2time($time);

    #my @local = $time;
    #my $dates = strftime( '%Y-%m-%d %H:%M:%S', @local);
    my $date_human = strftime( "%Y-%m-%d %H:%M:%S", localtime($timestamp) );
    if ( $message =~ m/:$/ ) {
      chop $message;
    }
    print "<tr>";
    print "<td>$date_human</td><td>$server</td><td>$subsystem</td><td>$metric</td><td>$message</td>\n";
    print "</tr>";
  }
  print "</tbody>";
  print "</table>";
  return 1;

}

sub print_table_hw {
  use POSIX qw(strftime);
  use Date::Parse;
  my $type      = shift;
  my $file_base = shift;
  my $text      = shift;
  my $text_tail = shift;
  my $reverse   = shift;
  my $max_rows  = shift;
  my $file      = $inputdir . "/logs/" . $file_base;

  if ( $file_base =~ m/^\// ) {

    # absolute path
    $file = $file_base;
  }

  if ( !-f "$file" ) {
    print "<CENTER><B>$text $file $text_tail</B></CENTER>";
    print "<B>File: $file does not exist</B>";
    return 0;
  }
  print "<CENTER><B>$text $file $text_tail</B></CENTER><PRE>";

  my @lines;
  my $data;
  if ( $max_rows > 0 ) {
    @lines = `tail -$max_rows $file`;
  }
  else {
    @lines = `cat $file`;
  }
  if ( $reverse == 1 ) {
    my @reverse = reverse @lines;
    @lines = @reverse;
  }

  #if ( $reverse == 1 ) {
  #  print reverse @lines;
  #}
  #else {
  #  print @lines;
  #}
  print "<table class='tabconfig tablesorter'>";
  print "<thead>";
  print "<tr>";
  print "<th class='sortable'>Date/Time</th><th class='sortable'>Server</th><th class='sortable'>Subsystem</th><th class='sortable'>Item</th><th class='sortable'>Reason</th>";
  print "</tr>";
  print "</thead>";
  print "<tbody>";

  foreach my $line (@lines) {

    #Mon Jun  7 07:38:10 2021; PAGING 2; LPAR; Linux; vm-lukas; actual util:9.70%, limit max:0%,
    #Mon Jun  7 07:38:10 2021; MEMORY; LPAR; Linux; vm-lukas; actual util:60.28%, limit max:0%,
    #Mon Jun  7 07:50:11 2021; OS CPU; LPAR; Linux; vm-lukas; actual util:1.84%, limit max:0%,
    if ( $line eq "" || !defined $line ) { next; }
    chomp $line;
    if ( $line eq "" || !defined $line ) { next; }
    my ( $time, $metric, $type, $server, $vm, $message ) = split( "; ", $line );
    if ( !defined $time || !defined $metric || !defined $server || !defined $vm ) { next; }
    if ( !defined $type ) {
      $type = "";
    }
    if ( !defined $message ) {
      $message = "";
    }
    my $subsystem = "";
    if ( $metric eq "Multipath" ) {
      $subsystem = "$vm";
    }
    else {
      $subsystem = "$type:$vm";
    }
    my $timestamp = str2time($time);

    #my @local = $time;
    #my $dates = strftime( '%Y-%m-%d %H:%M:%S', @local);
    my $date_human = strftime( "%Y-%m-%d %H:%M:%S", localtime($timestamp) );
    if ( $message =~ m/:$/ ) {
      chop $message;
    }
    print "<tr>";
    print "<td>$date_human</td><td>$server</td><td>$subsystem</td><td>$metric</td><td>$message</td>\n";
    print "</tr>";
  }
  print "</tbody>";
  print "</table>";
  return 1;

}

sub print_log {
  my $ftype     = shift;
  my $file_base = shift;
  my $text      = shift;
  my $text_tail = shift;
  my $reverse   = shift;
  my $max_rows  = shift;
  my $file      = $inputdir . "/logs/" . $file_base;

  if ( $file_base =~ m/^\// ) {

    # absolute path
    $file = $file_base;
  }

  if ( !-f "$file" ) {
    print "<CENTER><B>$text $file $text_tail</B></CENTER>";
    print "<B>File: $file does not exist</B>";
    return 0;
  }
  print "<CENTER><B>$text $file $text_tail</B></CENTER><PRE>";

  my @lines;
  if ( $max_rows > 0 ) {
    @lines = `tail -$max_rows $file`;
  }
  else {
    @lines = `cat $file`;
  }
  if ( $reverse == 1 ) {
    print reverse @lines;
  }
  else {
    print @lines;
  }
  return 1;
}

sub print_trailer {

  print "</pre></body></html>\n";

  return 1;
}

sub print_header {

  print "
<!DOCTYPE HTML PUBLIC \"-//W3C//DTD HTML 3.2 Final//EN\">
<HTML>
<HEAD>
<TITLE>LPAR2RRD old GUI </TITLE>
<META HTTP-EQUIV=\"pragma\" CONTENT=\"no-cache\">
<META HTTP-EQUIV=\"Expires\" CONTENT=\"NOW\">
<META HTTP-EQUIV=\"last modified\" CONTENT=\"NOW\">
<style>
<!--
a {text-decoration: none}
-->
</style>
</HEAD>
<BODY BGCOLOR=\"#D3D2D2\" TEXT=\"#000000\" LINK=\"#0000FF\" VLINK=\"#0000FF\" ALINK=\"#FF0000\" >
";

  return 0;
}

# error handling
sub error {
  my $text     = shift;
  my $act_time = localtime();
  chomp($text);

  print "<pre>\n\nERROR          : $text : $!\n</pre>";
  print STDERR "$act_time: $text : $!\n";

  return 1;
}

