
use strict;

my $DEBUG                   = $ENV{DEBUG};
my $inputdir                = $ENV{INPUTDIR};
my $errlog                  = $ENV{ERRLOG};
my $managed_systems_exclude = $ENV{MANAGED_SYSTEMS_EXCLUDE};
my $webdir                  = $ENV{WEBDIR};
my $wrkdir                  = $inputdir . "/data";
my $act_time                = localtime();
my $number_bad              = 0;
my $upgrade                 = $ENV{UPGRADE};
my $time                    = time();

if ( once_a_day("$webdir/gui-rmc.html") == 0 ) {
  if ( $upgrade == 0 ) {
    exit(0);    # run just ponce a day per timestamp on $webdir/gui-rmc.html
  }
  else {
    print "rmc check      : run it as first run after the upgrade : $upgrade\n";
  }
}

open( FHW, "> $webdir/gui-rmc.html" ) || die "$act_time: Can't open $webdir/gui-rmc.html : $!";
print_head();

# Find out all config.cfg files
foreach my $server (<$wrkdir/*>) {
  chomp($server);
  if ( !-d $server ) {
    next;    # sym link
  }
  if ( -l $server ) {
    next;    # sym link
  }

  if ( is_IP($server) == 1 ) {
    next;    # wrong entry from the HMC, a problem of the HMC or unconfigured server yet
  }

  my $server_name = basename($server);
  my $managed_ok  = 1;
  if ( $managed_systems_exclude ne '' ) {
    my @m_excl = split( /:/, $managed_systems_exclude );
    foreach my $managedname_exl (@m_excl) {
      chomp($managedname_exl);
      if ( $server_name =~ m/^$managedname_exl$/ ) {
        $managed_ok = 0;
      }
    }
  }
  if ( $managed_ok == 0 ) {
    next;
  }

  #print "$server\n";
  foreach my $config (<$server/*/config.cfg>) {
    chomp($config);
    if ( !-f "$config" ) {
      next;
    }

    #print "$config\n";
    my $hmc_all = $config;
    $hmc_all =~ s/\/config.cfg//;
    my $hmc_name = basename($hmc_all);

    # check how old is config.cfg, exclude it for more than 5 days old as it is not being updated
    my $time_cfg = ( ( stat($config) )[9] );
    if ( ( $time - $time_cfg ) > 432000 ) {
      next;    # old config.cfg
    }

    # search through the cfg file for RMC info
    my $ret = rmc_find( $config, $server_name, $hmc_name );
    $number_bad = $number_bad + $ret;
  }
}

print FHW "</table></center><br>";
if ( $number_bad == 0 ) {
  print FHW "<b>Congrats, all LPARs have RMC connection fine</b><br><br>\n";
}
print FHW "Report has been created at: $act_time<br>\n";
print FHW "<br><a href=\"http://aix4admins.blogspot.cz/2012/01/rmc-resource-monitoring-and-control-rmc.html\" target=\"_blank\">RMC</a> is a distributed framework and architecture that allows the HMC to communicate with a managed logical partition.<br>\n";
print FHW "RMC daemons should be running on a partition in order to be able to do DLPAR operations on HMC.<br>\n";
print FHW "You can use <a href=\"http://www-01.ibm.com/support/docview.wss?uid=isg3T1020611\">this link</a> for RMC troubleshooting.<br>\n";
print FHW "<ul style=\"display: none\"><li class=\"tabhmc\"></li></ul>\n";    # to add the data source icon
close(FHW);

# end of body for the new GUI

# create full HTML for the old GUI
open( FHW, "> $webdir/rmc.html" )     || die "$act_time: Can't open $webdir/rmc.html : $!";
open( FHR, "< $webdir/gui-rmc.html" ) || die "$act_time: Can't open $webdir/gui-rmc.html : $!";
print_head_html();

foreach my $line (<FHR>) {
  print FHW $line;
}

print FHW "</body></html>\n";

close(FHW);
close(FHR);
exit(0);

sub basename {
  my $full = shift;
  my $out  = "";

  # basename without direct function
  my @base = split( /\//, $full );
  foreach my $m (@base) {
    $out = $m;
  }

  return $out;
}

#</PRE><B>LPAR config:</B><PRE>
#name                                   demo
#state                                  Not Activated
#rmc_state                              active
#rmc_ipaddr                             192.168.1.7
# when state none then there is no IP line

sub rmc_find {
  my $config      = shift;
  my $server_name = shift;
  my $hmc_name    = shift;

  open( FH, "< $config" ) || die "$act_time: Can't open $config : $!";
  my @lines = <FH>;
  close(FH);

  my $lpar_name  = "";
  my $lpar_found = 0;
  my $rmc_state  = "";
  my $rmc_ipaddr = "";
  my $number_bad = 0;

  foreach my $line (@lines) {
    chomp($line);

    #print "$line \n";
    if ( $line =~ m/LPAR config:/ ) {
      if ( !$rmc_state eq '' && $rmc_state !~ m/^active/ ) {
        print "rmc check nok  : $hmc_name:$server_name:$lpar_name $rmc_state $rmc_ipaddr\n";
        print FHW "<tr><td>$lpar_name</td><td>$server_name</td><td>$hmc_name</td><td>$rmc_state</td><td>$rmc_ipaddr</td></tr>\n";
        $number_bad++;
      }
      $lpar_found = 1;
      $rmc_ipaddr = "";
      $rmc_state  = "";
      next;
    }
    if ( $lpar_found == 1 ) {
      if ( $line =~ m/LPAR profiles:/ ) {

        # already behind lpar global section,
        $lpar_found = 0;
        next;
      }
      if ( $line =~ m/^name                                   / ) {
        $lpar_name = $line;
        $lpar_name =~ s/^name                                   //;
        next;
      }
      if ( $line =~ m/^state                                  Not Activated/ ) {
        $lpar_found = 0;
        next;    # skip switched off partitions
      }
      if ( $line =~ m/^rmc_state                              / ) {
        $rmc_state = $line;
        $rmc_state =~ s/^rmc_state                              //;
        if ( $rmc_state =~ m/^active/ ) {
          $lpar_found = 0;

          # all is ok, switch to next lpar ...
          #print "OK $lpar_name $rmc_state\n";
          #print FHW "<tr><td>$server_name</td><td>$lpar_name</td><td>$hmc_name</td><td>$rmc_state</td><td>$rmc_ipaddr</td></tr>\n";
        }

        #else {
        #  print "rmc check $hmc_name $server_name $lpar_name $rmc_state $rmc_ipaddr\n";
        #}
        next;
      }
      if ( $line =~ m/^rmc_ipaddr                             / ) {

        # note rmc_ipaddr item does not have to be in config.cfg especially when status is "none", no idea why
        $rmc_ipaddr = $line;
        $rmc_ipaddr =~ s/^rmc_ipaddr                             //;
        $lpar_found = 0;
        print "rmc check $lpar_name $rmc_state $rmc_ipaddr\n";
        if ( $rmc_state !~ m/^active/ ) {
          print "rmc check nok  : $hmc_name:$server_name:$lpar_name $rmc_state $rmc_ipaddr\n";
          print FHW "<tr><td>$lpar_name</td><td>$server_name</td><td>$hmc_name</td><td>$rmc_state</td><td>$rmc_ipaddr</td></tr>\n";
          $rmc_state = "";    # must be cleaned here
          $number_bad++;
        }
      }
    }
  }
  if ( !$rmc_state eq '' && $rmc_state !~ m/^active/ ) {
    print "rmc check nok  : $hmc_name:$server_name:$lpar_name $rmc_state $rmc_ipaddr\n";
    print FHW "<tr><td>$lpar_name</td><td>$server_name</td><td>$hmc_name</td><td>$rmc_state</td><td>$rmc_ipaddr</td></tr>\n";
    $number_bad++;
  }

  return $number_bad;
}

sub print_head_html {

  print FHW "<!DOCTYPE HTML PUBLIC \"-//W3C//DTD HTML 3.2 Final//EN\">
<HTML>
<HEAD>
  <TITLE>LPAR2RRD old GUI</TITLE>
  <META HTTP-EQUIV=\"pragma\" CONTENT=\"no-cache\">
  <META HTTP-EQUIV=\"Expires\" CONTENT=\"NOW\">
  <META HTTP-EQUIV=\"last modified\" CONTENT=\"NOW\">
<style>
<!--
a {text-decoration: none}
-->
</style>
</HEAD>
<BODY BGCOLOR=\"#D3D2D2\" TEXT=\"#000000\" LINK=\"#0000FF\" VLINK=\"#0000FF\" ALINK=\"#FF0000\" >\n";
  return (00);
}

sub print_head {
  print FHW "<center><h3>List of LPARs with no active RMC connection</h3></center>
<center><table class=\"tabconfig\">
<tr><th>LPAR&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;</th><th>SERVER&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;</th><th>HMC&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;</th><th>RMC state&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;</th><th>RMC IP</th></tr> ";

  return (00);
}

sub once_a_day {
  my $file = shift;

  # at first check whether it is a first run after the midnight
  if ( !-f $file ) {
    `touch $file`;    # first run after the upgrade
    print "rmc check      : first run after the midnight 01\n";
  }
  else {
    my $run_time = ( stat("$file") )[9];
    ( my $sec, my $min, my $h, my $aday, my $m, my $y, my $wday, my $yday, my $isdst ) = localtime( time() );
    ( $sec, $min, $h, my $png_day, $m, $y, $wday, $yday, $isdst ) = localtime($run_time);
    if ( $aday == $png_day ) {

      # If it is the same day then do not update static graphs
      # static graps need to be updated due to views and top10
      print "rmc check      : not this time $aday == $png_day\n";
      return (0);
    }
    else {
      print "rmc check      : first run after the midnight 02: $aday != $png_day\n";
      `touch $file`;    # first run after the upgrade
    }
  }
  return 1;
}

# return 1 if the argument is valid IP, otherwise 0
sub is_IP {
  my $ip = shift;

  if ( $ip =~ /^(\d{1,3})\.(\d{1,3})\.(\d{1,3})\.(\d{1,3})$/ && ( ( $1 <= 255 && $2 <= 255 && $3 <= 255 && $4 <= 255 ) ) ) {
    return 1;
  }
  else {
    return 0;
  }
}

