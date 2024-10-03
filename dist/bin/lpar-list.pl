
#use strict;
#use RRDp;
use POSIX qw(strftime);
use Env qw(QUERY_STRING);

my $DEBUG                   = $ENV{DEBUG};
my $inputdir                = $ENV{INPUTDIR};
my $rrdtool                 = $ENV{RRDTOOL};
my $referer_tmp             = $ENV{HTTP_REFERER};
my $errlog                  = $ENV{ERRLOG};
my $managed_systems_exclude = $ENV{MANAGED_SYSTEMS_EXCLUDE};
use Env qw(QUERY_STRING);

( my $sort_order, my $entitle, my $referer ) = split( /&/, $QUERY_STRING );

my $new_gui = 0;

$entitle =~ s/entitle=//;

# if == 1 then restrict views (only CPU and mem)
if ( $entitle eq '' || isdigit($entitle) == 0 ) {
  $entitle = 0;    # when eny problem then allow it!
}

if ( $referer eq '' ) {

  # to persist original referer through sorting in the form
  $referer = $referer_tmp;
}

if ( $sort_order =~ m/referer=/ ) {

  # first argv is referer, just for compatability or a bug in calling it
  $referer    = $sort_order;
  $sort_order = "";
}

if ( $entitle =~ m/referer=/ ) {

  # 2nd argv is referer, just for compatability or a bug in calling it
  $referer    = $entitle;
  $sort_order = "";
}

$referer =~ s/referer=//g;
$referer =~ s/%([a-fA-F0-9][a-fA-F0-9])/pack("C", hex($1))/seg;

#`echo "$QUERY_STRING : $referer" >> /tmp/xx3`;

if ( $referer =~ m/gui=/ ) {

  # 2nd argv is referer, just for compatability or a bug in calling it
  $new_gui = $referer;
  $new_gui =~ s/gui=//;
}

$sort_order =~ s/sort=//;

open( OUT, ">> $errlog" ) if $DEBUG == 2;

# print HTML header
print "Content-type: text/html\n";
my $time = gmtime();

#print "Expires: $time\n\n";
#print "<HTML><BODY BGCOLOR=\"#D3D2D2\" TEXT=\"#000000\" LINK=\"#0000FF\" VLINK=\"#0000FF\" ALINK=\"#FF0000\" >";

#print "$QUERY_STRING -- $sort_order\n";
print_html($sort_order);

close(OUT) if $DEBUG == 2;
exit(0);

sub print_lpar {
  my $sort_order = shift;
  my $lpar_form  = shift;    # lpar vrs pool
  my @out        = "";

  if ( $sort_order =~ m/lpar/ ) {

    # sorting per LPARs
    if ( $lpar_form == 1 ) {
      @out = `cd $inputdir/data; find . -type f -name "\*$lpar\*.rr[m|h]"|egrep -v "pool.rrh|pool.rrm|mem.rrh|mem.rrm|SharedPool[0-9].rrh|SharedPool[0-9].rrm|SharedPool[0-9][0-9].rrh|SharedPool[0-9][0-9].rrm"|sort -t "/" -f -k 4`;
    }
    else {
      @out = `cd $inputdir/data; find . -type f -name "\*$lpar\*.rr[m|h]"|egrep "pool.rrh|pool.rrm|SharedPool[0-9].rrh|SharedPool[0-9].rrm|SharedPool[0-9][0-9].rrh|SharedPool[0-9][0-9].rrm"|grep -v "mem-pool"|sort -t "/" -f -k 4`;
    }
  }
  else {
    if ( $sort_order =~ m/hmc/ ) {

      # sorting per HMC/SDMC/IVM
      if ( $lpar_form == 1 ) {
        @out = `cd $inputdir/data; find . -type f -name "\*$lpar\*.rr[m|h]"|egrep -v "pool.rrh|pool.rrm|mem.rrh|mem.rrm|SharedPool[0-9].rrh|SharedPool[0-9].rrm|SharedPool[0-9][0-9].rrh|SharedPool[0-9][0-9].rrm"|sort -t "/" -f -k 3`;
      }
      else {
        @out = `cd $inputdir/data; find . -type f -name "\*$lpar\*.rr[m|h]"|egrep "pool.rrh|pool.rrm|SharedPool[0-9].rrh|SharedPool[0-9].rrm|SharedPool[0-9][0-9].rrh|SharedPool[0-9][0-9].rrm"|grep -v "mem-pool"|sort -t "/" -f -k 3`;
      }
    }
    else {
      #sorting per server
      if ( $lpar_form == 1 ) {
        @out = `cd $inputdir/data; find . -type f -name "\*$lpar\*.rr[m|h]"|egrep -v "pool.rrh|pool.rrm|mem.rrh|mem.rrm|SharedPool[0-9].rrh|SharedPool[0-9].rrm|SharedPool[0-9][0-9].rrh|SharedPool[0-9][0-9].rrm"|sort -f`;
      }
      else {
        @out = `cd $inputdir/data; find . -type f -name "\*$lpar\*.rr[m|h]"|egrep "pool.rrh|pool.rrm|SharedPool[0-9].rrh|SharedPool[0-9].rrm|SharedPool[0-9][0-9].rrh|SharedPool[0-9][0-9].rrm"|grep -v "mem-pool"|sort -f`;
      }
    }
  }

  #print "-- $inputdir $sort_order -- $out[0]\n";

  # loop just to find ou length of lpar/hmc/server
  my $lpar_len   = length("LPAR");
  my $hmc_len    = length("HMC");
  my $server_len = length("Server");
  foreach my $line (@out) {
    chomp($line);
    $line =~ s/^.\///;
    $line =~ s/\.rrh$//;
    $line =~ s/\.rrm$//;
    ( my $managed_act, my $hmc_act, my $lpar_act ) = split( /\//, $line );
    if ( $lpar_act eq '' || $lpar_act =~ m/SharedPool0\.r/ || $managed_act =~ m/--unknown$/ ) {
      next;
    }

    if ( is_IP($managed_act) == 1 ) {
      next;    # wrong entry from the HMC, a problem of the HMC or unconfigured server yet
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

    # open cpu.cfg to check if an LPAR is still exists (mostly due to LPM)
    my $cfg = "$inputdir/data/$managed/$hmc/cpu.cfg";
    if ( -f "$cfg" && $lpar_form == 1 ) {
      my $found = 1;
      open( FCFG, "< $cfg$RR" ) || next;
      foreach my $cline (<FCFG>) {
        $found = 0;
        chomp($cline);
        if ( $cline =~ /HSCL/ || $cline =~ /VIOSE0/ ) {
          $found = 1;
          print STDERR "Error in cpu.cfg : $inputdir/data/$managed/$hmc/cpu.cfg : $cline \n";
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

    #print "++ $line  \n";
    $line =~ s/^.\///;
    $line =~ s/\.rrh$//;
    $line =~ s/\.rrm$//;
    ( my $managed, my $hmc, my $lpar ) = split( /\//, $line );
    if ( $lpar eq '' || $lpar =~ m/SharedPool0\.r/ || $managed =~ m/--unknown$/ ) {

      # exclude DefaultPool on purpose, it is useles
      next;
    }

    if ( is_IP($managed) == 1 ) {
      next;    # wrong entry from the HMC, a problem of the HMC or unconfigured server yet
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
    my $managedn = $managed;
    my $hmcn     = $hmc;

    # open cpu.cfg to check if an LPAR is still exists (mostly due to LPM)
    my $cfg = "$inputdir/data/$managed/$hmc/cpu.cfg";
    if ( -f "$cfg" && $lpar_form == 1 ) {
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

    my $lpar_print = $lpar_slash;

    if ( $lpar_form == 0 ) {

      # CPU pool name translation
      if ( $lpar_print =~ m/^pool$/ ) {
        $lpar_print = "CPU pool";
      }
      else {
        my $pool_id = $lpar_print;
        $pool_id =~ s/SharedPool//g;

        if ( -f "$inputdir/data/$managed/$hmc/cpu-pools-mapping.txt" ) {
          open( FR, "< $inputdir/data/$managed/$hmc/cpu-pools-mapping.txt" );
          foreach my $linep (<FR>) {
            chomp($linep);
            ( my $id, my $pool_name ) = split( /,/, $linep );
            if ( $id == $pool_id ) {
              $lpar_print = "$pool_name";
              last;
            }
          }
          close(FR);
        }
      }
    }

    # max length into form names
    my $lpar_slash_mlen = $lpar_print;
    for ( my $k = length($lpar_print); $k < $lpar_len; $k++ ) {
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
      print "<OPTION VALUE=\"$hmcn|$managedn|$lpar_slash\">$lpar_slash_mlen&nbsp;&nbsp;$managedn_mlen&nbsp;&nbsp;$hmcn_mlen</OPTION>\n";
    }
    else {
      if ( $sort_order =~ m/hmc/ ) {

        # sorting per hmcr
        print "<OPTION VALUE=\"$hmcn|$managedn|$lpar_slash\">$hmcn_mlen&nbsp;&nbsp;$managedn_mlen&nbsp;&nbsp;$lpar_slash_mlen</OPTION>\n";
      }
      else {
        # sorting per server
        print "<OPTION VALUE=\"$hmcn|$managedn|$lpar_slash\">$managedn_mlen&nbsp;&nbsp;$hmcn_mlen&nbsp;&nbsp;$lpar_slash_mlen</OPTION>\n";
      }
    }

    #print "$hmcn - $managedn - $lpar_slash\n";
    print OUT "-- $l -- $lpar\n" if ( $DEBUG == 2 );
  }

  return 0;
}

sub print_html {
  my $sort_order = shift;

  my @abbr = qw( Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec );
  my $date = strftime "%d-%m-%Y", localtime( time() - 86400 );
  ( my $day, my $month, my $year ) = split( /-/, $date );
  $month--;

  my $date_e = strftime "%d-%m-%Y", localtime();
  ( my $day_e, my $month_e, my $year_e ) = split( /-/, $date_e );
  $month_e--;

  # when exist in etc/.magic CGI_METHOD=POST then use cgi-bin POST instead of GET
  # GET has a problem with many selected lpar, it has restricted lenght of the URL
  my $r_method = $ENV{'CGI_METHOD'};
  if ( $r_method eq '' ) {
    $r_method = "POST";

    # no no, POST is better for further parsing, it is default since 3.58
    # GET could be forced in etc/.magic but it is not further tested!!!
  }

  my $header = "<h3>Historical reports - Global</h3>";
  if ( $new_gui == 1 ) {
    $header = " ";
  }

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
<CENTER>
<TABLE BORDER=0 width=\"100%\"><tr><td align=\"center\">$header
</td></tr></table>
<font size=-1>
  <FORM METHOD=\"$r_method\" ACTION=\"/lpar2rrd-cgi/lpar-list-cgi.sh\">
  <TABLE BORDER=0 CELLSPACING=5 SUMMARY=\"Historical reports\">
    <TR> <TD>
      <table  align=\"center\"><tr><td  align=\"right\">
          <SELECT NAME=\"start-hour\">";

  ( my $sec, my $minx, my $hour, my $mdayx, my $monx, my $yearx, my $wday, my $yday, my $isdst ) = localtime(time);
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
	  </td><td>&nbsp;&nbsp;
<B>Graph resolution</B> <input type=\"text\" name=\"HEIGHT\" value=\"150\" size=\"1\"> x <input type=\"text\" name=\"WIDTH\" value=\"700\" size=\"1\">
          </td><td align=\"left\">&nbsp;&nbsp;
          <B>Y-axis</B>
          <SELECT NAME=\"yaxis\">
<OPTION VALUE=\"c\" SELECTED >CPU core
          </SELECT>
          </td></tr></table>
          </td></tr>
          <tr><td colspan=\"2\" align=\"center\">
        <INPUT type=\"hidden\" name=\"sort\" value=\"$sort_order\">
        <INPUT type=\"hidden\" name=\"gui\" value=\"$new_gui\">
        <INPUT type=\"hidden\" name=\"pool\" value=\"\">
        <INPUT type=\"hidden\" name=referer value=\"$referer\">
";

  #<OPTION VALUE=\"r\" >rPerf

  print "<br><TABLE BORDER=0 width=\"100%\">\n";
  print "<tr><td align=\"center\"><b>LPARs</b></td><td align=\"center\"><b>CPU pools</b></td><td align=\"center\"><b>Custom Groups</b></td></tr>\n";
  print "<tr><td>\n";

  #print "<center><strong><input type=\"radio\" name=\"lparform\" value=\"1\" checked>LPARs</center></strong>\n";

  if ( $sort_order =~ m/lpar/ ) {

    # sorting per lpar
    print "<B>LPAR</B>&nbsp;&nbsp;<A HREF=\"/lpar2rrd-cgi/lpar-list.sh?sort=server&entitle=$entitle&referer=$referer\" target=\"sample\"><B>Server</B></A>&nbsp;&nbsp;<A HREF=\"/lpar2rrd-cgi/lpar-list.sh?sort=hmc&entitle=$entitle&referer=$referer\" target=\"sample\"><B>HMC</B></A> (sorting)<br>\n";
  }
  else {
    if ( $sort_order =~ m/hmc/ ) {

      # sorting per hmcr
      print "<B>HMC</B>&nbsp;&nbsp;<A HREF=\"/lpar2rrd-cgi/lpar-list.sh?sort=server&entitle=$entitle&referer=$referer\" target=\"sample\"><B>Server</B></A>&nbsp;&nbsp;<A HREF=\"/lpar2rrd-cgi/lpar-list.sh?sort=lpar&entitle=$entitle&referer=$referer\" target=\"sample\"><B>LPAR</B></A> (sorting)<br>\n";
    }
    else {
      # sorting per server
      print "<B>Server</B>&nbsp;&nbsp;<A HREF=\"/lpar2rrd-cgi/lpar-list.sh?sort=hmc&entitle=$entitle&referer=$referer\" target=\"sample\"><B>HMC</B></A>&nbsp;&nbsp;<A HREF=\"/lpar2rrd-cgi/lpar-list.sh?sort=lpar&entitle=$entitle&referer=$referer\" target=\"sample\"><B>LPAR</B></A> (sorting)<br>\n";
    }
  }

  print "<SELECT NAME=LPAR MULTIPLE SIZE=30 style=\"font-family:Courier New\">\n";

  print_lpar( $sort_order, 1 );    # for lpars 0
  print "</SELECT>\n";
  print "</td><td  align=\"center\">\n";

  # Pools
  #print "<center><strong><input type=\"radio\" name=\"lparform\" value=\"0\">CPU POOLs</center></strong>\n";
  if ( $sort_order =~ m/lpar/ ) {

    # sorting per lpar
    print "<B>CPU-POOL</B>&nbsp;&nbsp;<A HREF=\"/lpar2rrd-cgi/lpar-list.sh?sort=server&entitle=$entitlereferer=$referer\" target=\"sample\"><B>Server</B></A>&nbsp;&nbsp;<A HREF=\"/lpar2rrd-cgi/lpar-list.sh?sort=hmc&entitle=$entitle&referer=$referer\" target=\"sample\"><B>HMC</B></A> (sorting)<br>\n";
  }
  else {
    if ( $sort_order =~ m/hmc/ ) {

      # sorting per hmcr
      print "<B>HMC</B>&nbsp;&nbsp;<A HREF=\"/lpar2rrd-cgi/lpar-list.sh?sort=server&entitle=$entitlereferer=$referer\" target=\"sample\"><B>Server</B></A>&nbsp;&nbsp;<A HREF=\"/lpar2rrd-cgi/lpar-list.sh?sort=lpar&entitle=$entitle&referer=$referer\" target=\"sample\"><B>CPU-POOL</B></A> (sorting)<br>\n";
    }
    else {
      # sorting per server
      print "<B>Server</B>&nbsp;&nbsp;<A HREF=\"/lpar2rrd-cgi/lpar-list.sh?sort=hmc&entitle=$entitle&referer=$referer\" target=\"sample\"><B>HMC</B></A>&nbsp;&nbsp;<A HREF=\"/lpar2rrd-cgi/lpar-list.sh?sort=lpar&entitle=$entitle&referer=$referer\" target=\"sample\"><B>CPU-POOL</B></A> (sorting)<br>\n";
    }
  }
  print "<SELECT NAME=POOL MULTIPLE SIZE=30 style=\"font-family:Courier New\">\n";
  print_lpar( $sort_order, 0 );    # for pools 0
  print "</SELECT>\n";
  print "</td><td  align=\"center\"><br>\n";

  # Custom Groups

  print "<SELECT NAME=CGROUP MULTIPLE SIZE=30 style=\"font-family:Courier New\">\n";
  print_groups();
  print "</SELECT>\n";
  print "</td></tr></table>\n";

  print "<INPUT type=\"hidden\" name=entitle value=\"$entitle\">";

  print "<BR><BR>
          <INPUT TYPE=\"SUBMIT\" style=\"font-weight: bold\" NAME=\"Report\" VALUE=\"Generate Report\" ALT=\"Generate Report\">
       </FORM>
       </TD>
      </TR>
   </TABLE>
</center>
<br>You can select more rows (LPARs) via holding Ctrl/Shift.<br>
</BODY> </HTML>
"
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

sub print_groups {
  my $cfg_cust = "etc/custom_groups.cfg";

  if ( !-f "$inputdir/$cfg_cust" ) {
    return 0;
  }

  open( FH, "< $inputdir/$cfg_cust" ) || error( "Can't open $inputdir/$cfg_cust: $!" . __FILE__ . ":" . __LINE__ ) && return 0;

  my @cgroup      = "";
  my $cgroup_indx = 0;

  foreach my $line (<FH>) {
    chomp($line);
    if ( $line =~ m/^POOL/ || $line =~ m/^LPAR/ ) {
      ( my $trash, my $server, my $lpar, my $name ) = split( /:/, $line );
      if ( $name eq '' || $name =~ m/^ *$/ ) {
        next;
      }

      my $found = 0;
      foreach my $line1 (@cgroup) {
        if ( $line1 =~ m/^$name$/ ) {
          $found = 1;
          last;
        }
      }

      if ( $found == 0 ) {
        $cgroup[$cgroup_indx] = $name;
        $cgroup_indx++;
        print "<OPTION VALUE=\"$name\">$name</OPTION>\n";
      }
    }
  }
  close(FH);
  return 1;
}
