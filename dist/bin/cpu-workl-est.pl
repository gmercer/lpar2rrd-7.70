
#use strict;
#use RRDp;
use POSIX qw(strftime);
use Env qw(QUERY_STRING);

my $DEBUG    = $ENV{DEBUG};
my $inputdir = $ENV{INPUTDIR};
my $rrdtool  = $ENV{RRDTOOL};

#my $refer = $ENV{HTTP_REFERER};
my $errlog                  = $ENV{ERRLOG};
my $managed_systems_exclude = $ENV{MANAGED_SYSTEMS_EXCLUDE};
use Env qw(QUERY_STRING);

( my $sort_order, my $sort_order_pool, my $new_gui ) = split( /&/, $QUERY_STRING );
$sort_order      =~ s/sort=//;
$sort_order_pool =~ s/sortpool=//;
$new_gui         =~ s/gui=//;
if ( $new_gui eq '' ) {
  $new_gui = 0;
}

open( OUT, ">> $errlog" ) if $DEBUG == 2;

# print CGI-BIN HTML header
print "Content-type: text/html\n\n";
my $time = gmtime();

print_html( $sort_order, $sort_order_pool, $new_gui );

close(OUT) if $DEBUG == 2;
exit(0);

sub print_lpar {
  my $sort_order      = shift;
  my $sort_order_pool = shift;
  my @out             = "";

  if ( $sort_order =~ m/lpar/ ) {

    # sorting per LPARs
    @out = `cd $inputdir/data; find . -type f -name "\*$lpar\*.rr[m|h]"|egrep -v "mem-agg.r|mem-multi.r|cod.r|mem-pool|pool.rrh|pool.rrm|mem.rrh|mem.rrm|SharedPool[0-9].rrh|SharedPool[0-9].rrm|SharedPool[0-9][0-9].rrh|SharedPool[0-9][0-9].rrm"|sort -t "/" -f -k 4`;
  }
  else {
    if ( $sort_order =~ m/hmc/ ) {

      # sorting per HMC/SDMC/IVM
      @out = `cd $inputdir/data; find . -type f -name "\*$lpar\*.rr[m|h]"|egrep -v "mem-agg.r|mem-multi.r|cod.r|mem-pool|pool.rrh|pool.rrm|mem.rrh|mem.rrm|SharedPool[0-9].rrh|SharedPool[0-9].rrm|SharedPool[0-9][0-9].rrh|SharedPool[0-9][0-9].rrm"|sort -t "/" -f -k 3`;
    }
    else {
      #sorting per server
      @out = `cd $inputdir/data; find . -type f -name "\*$lpar\*.rr[m|h]"|egrep -v "mem-agg.r|mem-multi.r|cod.r|mem-pool|pool.rrh|pool.rrm|mem.rrh|mem.rrm|SharedPool[0-9].rrh|SharedPool[0-9].rrm|SharedPool[0-9][0-9].rrh|SharedPool[0-9][0-9].rrm"|sort -f`;
    }
  }

  #print "-- $inputdir $sort_order -- $out[0]\n";

  # loop just to find ou length of lpar/hmc/server
  my $lpar_len   = length("LPAR");
  my $hmc_len    = length("HMC");
  my $server_len = length("Server");

  #just for finding out max len of lpar/hmc/server and headers
  foreach my $line (@out) {
    chomp($line);
    $line =~ s/^.\///;
    $line =~ s/\.rrh$//;
    $line =~ s/\.rrm$//;
    ( my $managed_act, my $hmc_act, my $lpar_act ) = split( /\//, $line );

    if ( is_IP($managed_act) == 1 ) {
      next;    # wrong entry from the HMC, a problem of the HMC or unconfigured server yet
    }

    if ( $managed_act =~ m/--unknown$/ ) {
      next;    # LPARs without the HMC, not supported here
    }

    my $lpar_slash = $lpar_act;
    $lpar_slash =~ s/\&\&1/\\/g;

    # Exclude excluded managed systems
    my $managed_ok = 1;
    if ( $managed_systems_exclude ne '' ) {
      @m_excl = split( /:/, $managed_systems_exclude );
      foreach $managedname_exl (@m_excl) {
        chomp($managedname_exl);
        if ( $managed =~ m/^$managedname_exl$/ ) {
          $managed_ok = 0;
        }
      }
    }
    if ( $managed_ok == 0 ) {
      next;
    }

    # open cpu.cfg to check if an LPAR is still exists (mostly due to LPM)
    my $cfg = "$inputdir/data/$managed/$hmc/cpu.cfg";
    if ( -f "$cfg" ) {
      my $found = 1;
      open( FCFG, "< $cfg$RR" ) || next;
      foreach my $cline (<FCFG>) {
        $found = 0;
        chomp($cline);
        if ( $cline =~ /HSCL/ || $cline =~ /VIOSE0/ ) {
          $found = 1;
          error("Error in cpu.cfg : $inputdir/data/$managed/$hmc/cpu.cfg : $cline");
          last;    # a problem occured, log error and continue
        }
        if ( $cline =~ m/^lpar_name=$lpar_slash,lpar_id=/ ) {
          $found = 1;
          last;    # lpar has been found, continue with displaing it
        }
      }
      close(FCFG);
      if ( $found == 0 ) {

        # lpar probbaly does not actually exist (removed/LPM)
        next;
      }
    }

    # end of checking if lpar exists

    if ( length($lpar_act) > $lpar_len ) {
      $lpar_len = length($lpar_act);
    }
    if ( length($hmc_act) > $hmc_len ) {
      $hmc_len = length($hmc_act);
    }
    if ( length($managed_act) > $server_len ) {
      $server_len = length($managed_act);
    }
  }

  print OUT "$uname \n" if ( $DEBUG == 2 );

  my $managedname_exl = "";
  my @m_excl          = "";

  foreach my $line (@out) {
    chomp($line);

    #print STDERR "++ $line  \n";
    $line =~ s/^.\///;
    $line =~ s/\.rrh$//;
    $line =~ s/\.rrm$//;
    ( my $managed, my $hmc, my $lpar ) = split( /\//, $line );
    if ( $lpar eq '' ) {
      next;
    }

    if ( is_IP($managed) == 1 ) {
      next;    # wrong entry from the HMC, a problem of the HMC or unconfigured server yet
    }

    if ( $managed =~ m/--unknown$/ ) {
      next;    # LPARs without the HMC, not supported here
    }

    # Exclude excluded managed systems
    my $managed_ok = 1;
    if ( $managed_systems_exclude ne '' ) {
      @m_excl = split( /:/, $managed_systems_exclude );
      foreach $managedname_exl (@m_excl) {
        chomp($managedname_exl);
        if ( $managed =~ m/^$managedname_exl$/ ) {
          $managed_ok = 0;
        }
      }
    }
    if ( $managed_ok == 0 ) {
      next;
    }
    my $lpar_slash = $lpar;
    $lpar_slash =~ s/\&\&1/\//g;
    my $lpar_ok  = $lpar_slash;
    my $managedn = $managed;
    my $hmcn     = $hmc;

    # open cpu.cfg to check if an LPAR is still exists (mostly due to LPM)
    my $cfg = "$inputdir/data/$managed/$hmc/cpu.cfg";
    if ( -f "$cfg" ) {
      my $found = 1;
      open( FCFG, "< $cfg$RR" ) || next;
      foreach my $cline (<FCFG>) {
        $found = 0;
        chomp($cline);
        if ( $cline =~ m/^lpar_name=$lpar_slash,lpar_id=/ ) {
          $found = 1;
          last;    # lpar has been found, continue with displaing it
        }
      }
      close(FCFG);
      if ( $found == 0 ) {

        # lpar probbaly does not actually exist (removed/LPM)
        next;
      }
    }

    # end of checking if lpar exists

    # max length into form names
    my $lpar_slash_mlen = $lpar_slash;
    for ( my $k = length($lpar_slash); $k < $lpar_len; $k++ ) {
      $lpar_slash_mlen .= "&nbsp;";
    }
    my $hmcn_mlen = $hmcn;
    for ( my $k = length($hmcn); $k < $hmc_len; $k++ ) {
      $hmcn_mlen .= "&nbsp;";
    }
    my $managedn_mlen = $managedn;
    for ( my $k = length($managedn); $k < $server_len; $k++ ) {
      $managedn_mlen .= "&nbsp;";
    }

    if ( $sort_order =~ m/lpar/ ) {

      # sorting per lpar
      print "<OPTION VALUE=\"$hmcn|$managedn|$lpar_slash\">$lpar_slash_mlen&nbsp;&nbsp;$managedn_mlen&nbsp;&nbsp;$hmcn</OPTION>\n";
    }
    else {
      if ( $sort_order =~ m/hmc/ ) {

        # sorting per hmcr
        print "<OPTION VALUE=\"$hmcn|$managedn|$lpar_slash\">$hmcn_mlen&nbsp;&nbsp;$managedn_mlen&nbsp;&nbsp;$lpar_slash</OPTION>\n";
      }
      else {
        # sorting per server
        print "<OPTION VALUE=\"$hmcn|$managedn|$lpar_slash\">$managedn_mlen&nbsp;&nbsp;$hmcn_mlen&nbsp;&nbsp;$lpar_slash</OPTION>\n";
      }
    }

    #print "$hmcn - $managedn - $lpar_slash\n";
    print OUT "-- $l -- $lpar\n" if ( $DEBUG == 2 );
  }

  return 0;
}

sub print_html {
  my $sort_order      = shift;
  my $sort_order_pool = shift;
  my $new_gui         = shift;

  my @abbr = qw( Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec );
  my $date = strftime "%d-%m-%Y", localtime( time() - 604800 );       # default is last week
  ( my $day, my $month, my $year ) = split( /-/, $date );
  $month--;

  my $date_e = strftime "%d-%m-%Y", localtime();
  ( my $day_e, my $month_e, my $year_e ) = split( /-/, $date_e );
  $month_e--;

  my $header = "<h3>CPU Workload Estimator</h3>";
  if ( $new_gui == 1 ) {
    $header = " ";
  }

  print "
<CENTER>

<TABLE BORDER=0 width=\"100%\"><tr><td>&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;</td><td align=\"center\">
$header
</td><td align=\"right\" valign=\"top\"><font size=\"-1\"><a href=\"http://www.lpar2rrd.com/cpu_workload_estimator.html\" target=\"_blank\">How it works</a></font>
</td></tr></table>

<font size=-1>
  <FORM METHOD=\"POST\" ACTION=\"/lpar2rrd-cgi/lpar-list-cgi.sh\">
  <TABLE BORDER=0 CELLSPACING=5 SUMMARY=\"CPU Workload Estimator\">
    <TR> <TD>
      <table  align=\"center\"><tr><td  align=\"right\">
          <SELECT NAME=\"start-hour\">";

  ( my $sec, my $minx, my $hour, my $mdayx, my $monx, my $yearx, my $wday, my $yday, my $isdst ) = localtime();
  for ( my $i = 0; $i < 24; $i++ ) {
    if ( $i == $hour ) {
      if ( $i < 10 ) {
        print "<OPTION VALUE=\"0$i\" SELECTED >0$i:00:00\n";
      }
      else {
        print "<OPTION VALUE=\"$i\" SELECTED >$i:00:00\n";
      }
    }
    else {
      if ( $i < 10 ) {
        print "<OPTION VALUE=\"0$i\" >0$i:00:00\n";
      }
      else {
        print "<OPTION VALUE=\"$i\" >$i:00:00\n";
      }
    }
  }

  print " </SELECT>
          <SELECT NAME=\"start-day\">";

  #print " $l -- $date $day, $month, $year\n";
  for ( my $i = 1; $i < 32; $i++ ) {
    if ( $i == $day ) {
      print "<OPTION VALUE=\"$i\"SELECTED >$i\n";
    }
    else {
      print "<OPTION VALUE=\"$i\" >$i\n";
    }
  }

  print " </SELECT> <SELECT NAME=\"start-mon\">\n";

  my $j = 1;
  for ( my $i = 0; $i < 12; $i++, $j++ ) {
    if ( $i == $month ) {
      print "<OPTION VALUE=\"$j\"SELECTED >$abbr[$i]\n";
    }
    else {
      print "<OPTION VALUE=\"$j\" >$abbr[$i]\n";
    }
  }

  print " </SELECT> <SELECT NAME=\"start-yr\">\n";

  for ( my $i = 2006; $i < $year; $i++ ) {
    print "<OPTION VALUE=\"$i\" >$i\n";
  }
  print "<OPTION VALUE=\"$year\"SELECTED > $year
          </SELECT> </td><td  align=\"left\">to&nbsp;
          <SELECT NAME=\"end-hour\">";

  for ( my $i = 0; $i < 25; $i++ ) {
    if ( $i == $hour ) {
      if ( $i < 10 ) {
        print "<OPTION VALUE=\"0$i\" SELECTED >0$i:00:00\n";
      }
      else {
        print "<OPTION VALUE=\"$i\" SELECTED >$i:00:00\n";
      }
    }
    else {
      if ( $i < 10 ) {
        print "<OPTION VALUE=\"0$i\" >0$i:00:00\n";
      }
      else {
        print "<OPTION VALUE=\"$i\" >$i:00:00\n";
      }
    }
  }

  print "   </SELECT>
          <SELECT NAME=\"end-day\">";

  for ( my $i = 1; $i < 32; $i++ ) {
    if ( $i == $day_e ) {
      print "<OPTION VALUE=\"$i\"SELECTED >$i\n";
    }
    else {
      print "<OPTION VALUE=\"$i\" >$i\n";
    }
  }

  print " </SELECT> <SELECT NAME=\"end-mon\">";

  $j = 1;
  for ( my $i = 0; $i < 12; $i++, $j++ ) {
    if ( $i == $month_e ) {
      print "<OPTION VALUE=\"$j\"SELECTED >$abbr[$i]\n";
    }
    else {
      print "<OPTION VALUE=\"$j\" >$abbr[$i]\n";
    }
  }

  print " </SELECT> <SELECT NAME=\"end-yr\">";

  for ( my $i = 2006; $i < $year_e; $i++ ) {
    print "<OPTION VALUE=\"$i\" >$i\n";
  }
  print "<OPTION VALUE=\"$year_e\"SELECTED > $year_e\n";

  print " </SELECT>
	  </td></tr></table><tr><td colspan=\"2\">
	  <table  align=\"center\"><tr><td align=\"right\">
          <B>Sample time</B>
          <SELECT NAME=\"type\">
<OPTION VALUE=\"m\" SELECTED >1 min
<OPTION VALUE=\"n\" >10 min
<OPTION VALUE=\"h\" >1 hour
<OPTION VALUE=\"d\" >1 day
          </SELECT>
	  </td><td>&nbsp;&nbsp
<B>Graph resolution</B> <input type=\"text\" name=\"HEIGHT\" value=\"150\" size=\"1\"> x <input type=\"text\" name=\"WIDTH\" value=\"700\" size=\"1\">
          </td><td align=\"left\">&nbsp;&nbsp
          <B>Y-axis</B>
	  <SELECT NAME=\"yaxis\">
<OPTION VALUE=\"r\" SELECTED >rPerf
<OPTION VALUE=\"w\" >CPW
<OPTION VALUE=\"c\" >CPU core
          </SELECT>
	  </td></tr></table>
          </td></tr><tr><td colspan=\"2\"  align=\"center\">
        <INPUT type=\"hidden\" name=\"sort\" value=\"$sort_order\">
        <INPUT type=\"hidden\" name=\"gui\" value=\"$new_gui\">
";

  #<OPTION VALUE=\"s\" >SAPs
  #<table width=\"100%\"><tr><td align=\"right\">

  # make a table for server pool and lpars
  print "<table border=\"0\">";
  print "<tr><td align=\"center\"><h3>Target server / CPU pool</h3></td><td align=\"center\"><h3>LPARs for migration</h3></td></tr>";
  print "<tr><td>";

  print "<table border=\"0\">";

  # start of print all models from rperf_table.txt
  print "<tr><td>";
  print_all_models();

  # end of server CPU section

  # start of server CPU section
  print "</td><td>";
  print_pool( $sort_order, $sort_order_pool, $new_gui );
  print "</td><tr>";

  # end of server CPU section
  print "</table>";

  print "</td><td><br>";

  # start lpar section
  print "<center>";
  if ( $sort_order =~ m/lpar/ ) {

    # sorting per lpar
    print "<B>LPAR</B>&nbsp;&nbsp;&nbsp;&nbsp;<A HREF=\"/lpar2rrd-cgi/cpu-workl-est.sh?sort=server&sortpool=$sort_order_pool&gui=$new_gui\" target=\"sample\"><B>Server</B></A>&nbsp;&nbsp;&nbsp;&nbsp;<A HREF=\"/lpar2rrd-cgi/cpu-workl-est.sh?sort=hmc&sortpool=$sort_order_pool&gui=$new_gui\" target=\"sample\"><B>HMC</B></A><br>\n";
  }
  else {
    if ( $sort_order =~ m/hmc/ ) {

      # sorting per hmcr
      print "<B>HMC</B>&nbsp;&nbsp;&nbsp;&nbsp;<A HREF=\"/lpar2rrd-cgi/cpu-workl-est.sh?sort=server&sortpool=$sort_order_pool&gui=$new_gui\" target=\"sample\"><B>Server</B></A>&nbsp;&nbsp;&nbsp;&nbsp;<A HREF=\"/lpar2rrd-cgi/cpu-workl-est.sh?sort=lpar&sortpool=$sort_order_pool&gui=$new_gui\" target=\"sample\"><B>LPAR</B></A><br>\n";
    }
    else {
      # sorting per server
      print "<B>Server</B>&nbsp;&nbsp;&nbsp;&nbsp;<A HREF=\"/lpar2rrd-cgi/cpu-workl-est.sh?sort=hmc&sortpool=$sort_order_pool&gui=$new_gui\" target=\"sample\"><B>HMC</B></A>&nbsp;&nbsp;&nbsp;&nbsp;<A HREF=\"/lpar2rrd-cgi/cpu-workl-est.sh?sort=lpar&sortpool=$sort_order_pool&gui=$new_gui\" target=\"sample\"><B>LPAR</B></A><br>\n";
    }
  }

  print "<SELECT NAME=LPAR MULTIPLE SIZE=30 style=\"font-family:Courier New\">\n";
  print_lpar( $sort_order, $sort_order_pool );
  print "</SELECT>";

  # end of lpar section

  print "</td></tr></table>";
  print "
          <BR>
          <INPUT TYPE=\"SUBMIT\" style=\"font-weight: bold\" NAME=\"Report\" VALUE=\"Generate Report\" ALT=\"Generate Report\">
       </FORM>
       </TD>
      </TR>
   </TABLE>
</center>
<br>You can select more lpars via holding Ctrl/Shift during lpar signing.<br>
This makes no sense for \"Target server/CPU pool\". If you select more of them then it will work only for the first one.";

  if ( $new_gui == 0 ) {
    print " </BODY> </HTML>\n ";
  }

}

sub print_pool {
  my $sort_order      = shift;
  my $sort_order_pool = shift;
  my $new_gui         = shift;
  my @out             = "";

  if ( $sort_order_pool =~ m/lpar/ ) {

    # sorting per POOLs
    # note that SharedPool[0] is excluded here
    @out = `cd $inputdir/data; find . -type f -name "\*ool\*.rr[m|h]"|egrep "pool.rrh|pool.rrm|SharedPool[1-9].rrh|SharedPool[1-9].rrm|SharedPool[1-9][0-9].rrh|SharedPool[1-9][0-9].rrm"|egrep -v "mem-pool.r|cod.r"|sort -t "/" -f -k 4`;
  }
  else {
    if ( $sort_order_pool =~ m/hmc/ ) {

      # sorting per HMC/SDMC/IVM
      @out = `cd $inputdir/data; find . -type f -name "\*ool\*.rr[m|h]"|egrep "pool.rrh|pool.rrm|mem.rrm|SharedPool[1-9].rrh|SharedPool[1-9].rrm|SharedPool[1-9][0-9].rrh|SharedPool[1-9][0-9].rrm"|egrep -v "mem-pool.r|cod.r"|sort -t "/" -f -k 3`;
    }
    else {
      #sorting per server
      @out = `cd $inputdir/data; find . -type f -name "\*ool\*.rr[m|h]"|egrep "pool.rrh|pool.rrm|SharedPool[1-9].rrh|SharedPool[1-9].rrm|SharedPool[1-9][0-9].rrh|SharedPool[0-9][1-9].rrm"|egrep -v "mem-pool.r|cod.r"|sort -f`;
    }
  }

  #print "-- $inputdir - $out[0]\n";

  # loop just to find ou length of lpar/hmc/server
  my $lpar_len   = length("POOL");
  my $hmc_len    = length("HMC");
  my $server_len = length("Server");
  foreach my $line (@out) {
    chomp($line);
    $line =~ s/^.\///;
    $line =~ s/\.rrh$//;
    $line =~ s/\.rrm$//;
    ( my $managed_act, my $hmc_act, my $lpar_act ) = split( /\//, $line );

    if ( is_IP($managed_act) == 1 ) {
      next;    # wrong entry from the HMC, a problem of the HMC or unconfigured server yet
    }

    if ( $managed_act =~ m/--unknown$/ ) {
      next;    # LPARs without the HMC, not supported here
    }

    # Exclude excluded managed systems
    my $managed_ok = 1;
    if ( $managed_systems_exclude ne '' ) {
      @m_excl = split( /:/, $managed_systems_exclude );
      foreach $managedname_exl (@m_excl) {
        chomp($managedname_exl);
        if ( $managed =~ m/^$managedname_exl$/ ) {
          $managed_ok = 0;
        }
      }
    }
    if ( $managed_ok == 0 ) {
      next;
    }

    if ( length($lpar_act) > $lpar_len ) {
      $lpar_len = length($lpar_act);
    }
    if ( length($hmc_act) > $hmc_len ) {
      $hmc_len = length($hmc_act);
    }
    if ( length($managed_act) > $server_len ) {
      $server_len = length($managed_act);
    }
  }

  # print out header
  my $lpar_name_mlen     = "POOL&nbsp;&nbsp;&nbsp;&nbsp;";
  my $hmcn_name_mlen     = "HMC&nbsp;&nbsp;&nbsp;&nbsp;";
  my $managedn_name_mlen = "Server&nbsp;&nbsp;&nbsp;&nbsp;";

  print "<center><strong><input type=\"radio\" name=\"newsrv\" value=\"0\" checked>Existing server/CPU pool</strong></center>";

  # sorting per servers only
  if ( $sort_order_pool =~ m/lpar/ ) {

    # sorting per lpar
    print "<center><B>$lpar_name_mlen<B><A HREF=\"/lpar2rrd-cgi/cpu-workl-est.sh?sort=$sort_order&sortpool=server&gui=$new_gui\" target=\"sample\"><B>$managedn_name_mlen<B></A><A HREF=\"/lpar2rrd-cgi/cpu-workl-est.sh?sort=$sort_order&sortpool=hmc&gui=$new_gui\" target=\"sample\"><B>$hmcn_name_mlen<B></A><br>\n";
  }
  else {
    if ( $sort_order_pool =~ m/hmc/ ) {

      # sorting per hmcr
      print "<center><B>$hmcn_name_mlen</B><A HREF=\"/lpar2rrd-cgi/cpu-workl-est.sh?sort=$sort_order&sortpool=server&gui=$new_gui\" target=\"sample\"><B>$managedn_name_mlen</B></A><A HREF=\"/lpar2rrd-cgi/cpu-workl-est.sh?sort=$sort_order&sortpool=lpar&gui=$new_gui\" target=\"sample\"><B>$lpar_name_mlen</B></A><br>\n";
    }
    else {
      # sorting per server
      print "<center><B>$managedn_name_mlen</B><A HREF=\"/lpar2rrd-cgi/cpu-workl-est.sh?sort=$sort_order&sortpool=hmc&gui=$new_gui\" target=\"sample\"><B>$hmcn_name_mlen</B></A><A HREF=\"/lpar2rrd-cgi/cpu-workl-est.sh?sort=$sort_order&sortpool=lpar&gui=$new_gui\" target=\"sample\"><B>$lpar_name_mlen</B></A><br>\n";
    }
  }

  print "<SELECT NAME=POOL MULTIPLE SIZE=30 style=\"font-family:Courier New\">\n";

  # end of header

  print OUT "$uname \n" if ( $DEBUG == 2 );

  my $managedname_exl = "";
  my @m_excl          = "";

  foreach my $line (@out) {
    chomp($line);

    #print "++ $line  \n";
    $line =~ s/^.\///;
    $line =~ s/\.rrh$//;
    $line =~ s/\.rrm$//;
    ( my $managed, my $hmc, my $lpar ) = split( /\//, $line );

    if ( is_IP($managed) == 1 ) {
      next;    # wrong entry from the HMC, a problem of the HMC or unconfigured server yet
    }

    if ( $managed =~ m/--unknown$/ ) {
      next;    # LPARs without the HMC, not supported here
    }

    # Exclude excluded managed systems
    my $managed_ok = 1;
    if ( $managed_systems_exclude ne '' ) {
      @m_excl = split( /:/, $managed_systems_exclude );
      foreach $managedname_exl (@m_excl) {
        chomp($managedname_exl);
        if ( $managed =~ m/^$managedname_exl$/ ) {
          $managed_ok = 0;
        }
      }
    }
    if ( $managed_ok == 0 ) {
      next;
    }
    my $lpar_org_name = $lpar;

    # find out name of shared pool from given SharedPoolXY name
    if ( $lpar =~ m/SharedPool[1-9]/ && -f "$inputdir/data/$managed/$hmc/cpu-pools-mapping.txt" ) {
      open( FR, "< $inputdir/data/$managed/$hmc/cpu-pools-mapping.txt" );
      my $pool_id = $lpar;
      $pool_id =~ s/SharedPool//;
      foreach my $linep (<FR>) {
        chomp($linep);
        ( my $id, my $pool_name ) = split( /,/, $linep );
        if ( $id == $pool_id ) {
          $lpar = $pool_name;
          last;
        }
      }
      close(FR);
    }
    else {
      if ( $lpar =~ m/^pool$/ ) {
        $lpar = "All&nbsp;CPU&nbsp;pools";
      }
    }

    my $lpar_ok  = $lpar;
    my $managedn = $managed;
    my $hmcn     = $hmc;

    # max length into form names
    my $lpar_mlen = $lpar;
    for ( my $k = length($lpar); $k < $lpar_len; $k++ ) {
      $lpar_mlen .= "&nbsp;";
    }
    my $hmcn_mlen = $hmcn;
    for ( my $k = length($hmcn); $k < $hmc_len; $k++ ) {
      $hmcn_mlen .= "&nbsp;";
    }
    my $managedn_mlen = $managedn;
    for ( my $k = length($managedn); $k < $server_len; $k++ ) {
      $managedn_mlen .= "&nbsp;";
    }

    if ( $sort_order_pool =~ m/lpar/ ) {

      # sorting per lpar
      print "<OPTION VALUE=\"$hmcn|$managedn|$lpar_org_name\">$lpar_mlen&nbsp;&nbsp;$managedn_mlen&nbsp;&nbsp;$hmcn</OPTION>\n";
    }
    else {
      if ( $sort_order_pool =~ m/hmc/ ) {

        # sorting per hmcr
        print "<OPTION VALUE=\"$hmcn|$managedn|$lpar_org_name\">$hmcn_mlen&nbsp;&nbsp;$managedn_mlen&nbsp;&nbsp;$lpar_mlen</OPTION>\n";
      }
      else {
        # sorting per server
        print "<OPTION VALUE=\"$hmcn|$managedn|$lpar_org_name\">$managedn_mlen&nbsp;&nbsp;$hmcn_mlen&nbsp;&nbsp;$lpar_mlen</OPTION>\n";
      }
    }

    #print "$hmcn - $managedn - $lpar_slash\n";
    print OUT "-- $l -- $lpar\n" if ( $DEBUG == 2 );
  }

  print "</SELECT></center>";
  return 0;
}

sub print_all_models {

  if ( -f "$inputdir/etc/rperf_table.txt" ) {
    open( FALL, "< $inputdir/etc/rperf_table.txt" ) || error( "$inputdir/etc/rperf_table.txt $! :" . __FILE__ . ":" . __LINE__ ) && return 1;
  }
  else {
    open( FALL, "< $inputdir/etc/free_rperf_table.txt" ) || error( "$inputdir/etc/free_rperf_table.txt $! :" . __FILE__ . ":" . __LINE__ ) && return 1;
  }
  my @lines = <FALL>;
  close(FALL);

  # remove spaces to be able correctly sort per CPU type
  my $i = 0;
  foreach my $line (@lines) {
    $lines[$i] =~ s/ //g;
    $lines[$i] =~ s/	//g;
    $i++;
  }
  my @lines_sort = sort { ( split ':', $a )[1] cmp( split ':', $b )[1] } @lines;

  print "<center><strong><input type=\"radio\" name=\"newsrv\" value=\"1\">New server</center></strong>";

  print "<strong>Model&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;Type&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;CPU&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;GHz</strong><br>";
  print "<SELECT NAME=NEW MULTIPLE SIZE=30 style=\"font-family:Courier New\">\n";

  # sort
  # 8284-22A : S822 :  P8/6   :  3.89   :  120.8    :
  # P8, P7+, P7, P6+, P6, P5+, P5

  print_new_server( "P9/",    \@lines_sort );
  print_new_server( "P8/",    \@lines_sort );
  print_new_server( "P7\\+/", \@lines_sort );
  print_new_server( "P7/",    \@lines_sort );
  print_new_server( "P6\\+/", \@lines_sort );
  print_new_server( "P6/",    \@lines_sort );
  print_new_server( "P5\\+/", \@lines_sort );
  print_new_server( "P5/",    \@lines_sort );

  print "</SELECT></center>";

  return 1;
}

sub print_new_server {
  my ( $cpu_filter, $lines_sort_tmp ) = @_;
  my @lines_sort = @{$lines_sort_tmp};

  foreach my $line (@lines_sort) {
    chomp($line);
    if ( $line =~ m/^#/ || $line =~ m/^$/ ) {
      next;
    }
    if ( $line !~ m/:/ ) {
      next;
    }

    my $rperf = 0;
    my $cpw   = 0;
    ( my $model, my $type, my $cpu, my $ghz, $rperf, $cpw ) = split( /:/, $line );

    if ( $cpu !~ m/^$cpu_filter/ ) {
      next;
    }

    # It must have defined status
    if ( $rperf eq '' ) {
      $rperf = 0;
    }
    if ( $cpw eq '' ) {
      $cpw = 0;
    }

    # add spaces
    my $model_space = $model;
    for ( my $k = length($model_space); $k < 9; $k++ ) {
      $model_space .= "&nbsp;";
    }
    my $type_space = $type;
    for ( my $k = length($type_space); $k < 7; $k++ ) {
      $type_space .= "&nbsp;";
    }
    my $cpu_space = $cpu;
    for ( my $k = length($cpu_space); $k < 6; $k++ ) {
      $cpu_space .= "&nbsp;";
    }

    print "<OPTION VALUE=\"$model|$type|$cpu|$ghz|$rperf|$cpw\">$model_space $type_space $cpu_space $ghz</OPTION>\n";
  }

  return 0;
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

