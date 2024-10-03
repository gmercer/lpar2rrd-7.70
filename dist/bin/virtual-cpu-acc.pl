#
# used only for DHL accounting purposes
# etc/.magic : KEEP_VIRTUAL=1 --> it has to be setup after initial installation!!!
#

#use strict;
use POSIX qw(strftime);
use Env qw(QUERY_STRING);
use Date::Parse;

my $DEBUG    = $ENV{DEBUG};
my $inputdir = $ENV{INPUTDIR};
my $rrdtool  = $ENV{RRDTOOL};

#my $refer = $ENV{HTTP_REFERER};
my $errlog                  = $ENV{ERRLOG};
my $managed_systems_exclude = $ENV{MANAGED_SYSTEMS_EXCLUDE};

#use Env qw(QUERY_STRING);

open( OUT, ">> $errlog" ) if $DEBUG == 2;

# print HTML header
print "Content-type: text/html\n";
my $time = gmtime();

print_html();

close(OUT) if $DEBUG == 2;
exit(0);

sub print_lpar {
  my @out = "";

  @out = `cd $inputdir/data; find . -type f -name "pool.rr[m|h]"|cut -d "/" -f 2|sort|uniq`;
  print OUT "$uname \n" if ( $DEBUG == 2 );

  my $managedname_exl = "";
  my @m_excl          = "";

  $size = 0;

  # count just number of lpars at first --> use uniq
  foreach my $managed (@out) {
    chomp($managed);
    if ( $managed eq '' ) {
      next;
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

    $size++;
  }

  print "<SELECT NAME=SERVERS MULTIPLE SIZE=$size style=\"font-family:Courier New\">\n";

  my $hmc   = "";
  my $first = 1;
  foreach my $managed (@out) {
    chomp($managed);
    if ( $managed eq '' ) {
      next;
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

    if ( $first == 1 ) {
      print "<OPTION VALUE=\"$managed\"  SELECTED >$managed</OPTION>\n";
      $first++;
    }
    else {
      print "<OPTION VALUE=\"$managed\">$managed</OPTION>\n";
    }

    #print "<OPTION VALUE=\"$managed\">$managed</OPTION>\n"; #--PH temporary
  }

  return 0;
}

sub print_html {

  my @abbr = qw( Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec );
  my $date = strftime "%d-%m-%Y", localtime( time() - 86400 );
  ( my $day, my $month, my $year ) = split( /-/, $date );
  $month--;

  #<FORM METHOD=\"GET\" ACTION=\"/lpar2rrd-cgi/virtual-cgi.sh\">
  print "
<CENTER>
<h3>Accounting based on Virtual CPU weekly average</h3>
  <FORM METHOD=\"GET\" ACTION=\"/lpar2rrd-cgi/virtual-wrapper.sh\">
  <TABLE BORDER=0 CELLSPACING=5 SUMMARY=\"Accounting\"> <TR> <TD>
  <SELECT NAME=\"week\">\n";

  print_week();
  print "</SELECT></td><td>";

  print "<SELECT NAME=\"month\">\n";
  my $j = 1;
  for ( my $i = 0; $i < 12; $i++, $j++ ) {
    if ( $i == $month ) {
      print "<OPTION VALUE=\"$j\" SELECTED >$abbr[$i]\n";
    }
    else {
      print "<OPTION VALUE=\"$j\" >$abbr[$i]\n";
    }
  }
  print "</SELECT> </td><td>\n";

  print "<SELECT NAME=\"year\">\n";
  for ( my $i = 2013; $i < $year; $i++ ) {
    print "<OPTION VALUE=\"$i\" >$i\n";
  }
  print "<OPTION VALUE=\"$year\" SELECTED > $year";
  print "</SELECT></td></tr></table>\n";
  print "<br><TABLE BORDER=0 CELLSPACING=5 SUMMARY=\"Accounting\">\n";
  print "<tr><th align=\"center\">&nbsp;&nbsp;&nbsp;CPU&nbsp;&nbsp;&nbsp;</th><th align=\"center\">&nbsp;&nbsp;&nbsp;weekly/monthly report&nbsp;&nbsp;&nbsp;</th><th align=\"center\">&nbsp;&nbsp;&nbsp;data source&nbsp;&nbsp;&nbsp;</th></tr>\n";
  print "<tr><td align=\"center\"><input type=\"radio\" name=\"util\" value=\"0\" checked>Allocation<br>\n";
  print "                         <input type=\"radio\" name=\"util\" value=\"1\">Utilization</td>\n";
  print "<td align=\"center\"><input type=\"radio\" name=\"time\" value=\"month\" checked>Month<br>\n";
  print "                         <input type=\"radio\" name=\"time\" value=\"week\"d>Week&nbsp;</td>\n";
  print "<td align=\"center\">    <input type=\"radio\" name=\"input\" value=\"3600\" checked>1 hour<br>\n";
  print "                         <input type=\"radio\" name=\"input\" value=\"300\">5 mins</td></tr>\n";

  print "<tr><td colspan=\"3\" align=\"center\"><br><B>List of HMCs</b></td></tr>\n";
  print "<tr><td colspan=\"3\" align=\"center\">";
  print_hmc();

  print "<tr><td colspan=\"3\" align=\"center\"><br><B>List of servers</b></td></tr>\n";
  print "<tr><td colspan=\"3\" align=\"center\">";

  print_lpar();

  print "
        </SELECT>
          <BR><BR>
          <INPUT TYPE=\"SUBMIT\" style=\"font-weight: bold\" NAME=\"Report\" VALUE=\"Generate Report\" ALT=\"Generate Report\">
       </FORM>
       </TD>
      </TR>
      <tr><td colspan=\"4\"  align=\"left\"><br><font size=-1>You can select more rows (servers) via holding Ctrl/Shift.<br></td></tr>
   </TABLE>
</center>
</font>
"
}

sub print_week {

  my $year  = strftime "%Y", localtime( time() );
  my $stime = str2time("1/1/$year");
  my $etime = $stime;
  $year++;
  my $utime_end  = str2time("1/1/$year");
  my $weekNumber = "";
  my $weekday    = strftime( "%u", localtime($stime) );
  while ( $weekday != 1 ) {

    # find first Monday
    $stime -= 86400;
    $weekday = strftime( "%u", localtime($stime) );
  }

  my $act_time = time();

  while ( $stime < $utime_end ) {

    # list all weeks
    ( my $sec, my $min, my $hour, my $sday, my $smonth, my $year, my $wday, my $yday, my $isdst ) = localtime($stime);
    $etime = $stime + 604800;
    ( my $sec, my $min, my $hour, my $eday, my $emonth, my $year, my $wday, my $yday, my $isdst ) = localtime($etime);
    $smonth += 1;
    $emonth += 1;
    $weekNumber = strftime( "%U", localtime($etime) );

    # --> it start with Monday as first day (%U starts with Sunday, %V starts with Monday)
    #print "$weekNumber : $sday/$smonth - $eday/$emonth\n";
    $sday = sprintf( "%02.0f", $sday );
    $eday = sprintf( "%02.0f", $eday );
    $smon = sprintf( "%02.0f", $smon );
    $emon = sprintf( "%02.0f", $emon );
    if ( $act_time > $stime && $act_time < $etime ) {
      print "<OPTION VALUE=\"$stime $etime\" SELECTED >$weekNumber : $sday/$smonth - $eday/$emonth\n";
    }
    else {
      print "<OPTION VALUE=\"$stime $etime\" >$weekNumber : $sday/$smonth - $eday/$emonth\n";
    }
    $stime = $etime;
  }
}

sub print_hmc {

  my $hmc_list = $ENV{HMC_LIST};
  my @hmcs     = split( / /, $hmc_list );

  print "<SELECT NAME=hmc MULTIPLE SIZE=3 style=\"font-family:Courier New\">\n";
  print "<OPTION VALUE=\"auto\"  SELECTED >automatic</OPTION>\n";
  foreach my $hmc (@hmcs) {
    chomp($hmc);
    if ( $hmc eq '' ) {
      next;
    }
    print "<OPTION VALUE=\"$hmc\">$hmc</OPTION>\n";
  }
  print "</SELECT>\n";
  return 0;
}
