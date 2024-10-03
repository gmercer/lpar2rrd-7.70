
use strict;
use Date::Parse;

my $DEBUG    = $ENV{DEBUG};
my $errlog   = $ENV{ERRLOG};
my $xport    = $ENV{EXPORT_TO_CSV};
my $SSH      = $ENV{SSH} . " ";
my $ident    = $ENV{SSH_WEB_IDENT};
my $hmc_user = $ENV{HMC_USER};

open( OUT, ">> $errlog" ) if $DEBUG == 2;

# print HTML header
print "Content-type: text/html\n";
my $time = gmtime();
print "Expires: $time\n\n";

# get QUERY_STRING
use Env qw(QUERY_STRING);

#$QUERY_STRING .= ":.";
print OUT "-- $QUERY_STRING\n" if $DEBUG == 2;

( my $lpar, my $hmc, my $managedname, my $new_gui, my $none ) = split( /&/, $QUERY_STRING );

#`echo "$QUERY_STRING" >>/tmp/xx55`;

$lpar =~ s/source=//;
my $lpar_en = $lpar;
$lpar =~ tr/+/ /;
$lpar =~ s/%([\dA-Fa-f][\dA-Fa-f])/ pack ("C",hex ($1))/seg;
$hmc  =~ s/hmc=//;
$hmc  =~ s/host=//;
my $hmc_en = $hmc;
$hmc =~ tr/+/ /;
$hmc =~ s/%([\dA-Fa-f][\dA-Fa-f])/ pack ("C",hex ($1))/seg;
my $host = $hmc;    # due to compatability reasons
$managedname =~ s/mname=//;
my $managedname_en = $managedname;
$managedname =~ tr/+/ /;
$managedname =~ s/%([\dA-Fa-f][\dA-Fa-f])/ pack ("C",hex ($1))/seg;
my $managedname_sp = $managedname;
$managedname_sp =~ s/%20/ /;       # useless now when it is decoded before ...
$new_gui        =~ s/new_gui=//;

if ( $new_gui eq '' || isdigit($new_gui) == 0 ) {
  $new_gui = 0;                    # when eny problem then old GUI
}
if ( !$none eq '' ) {
  $none =~ s/none=//;
}

if ( !-f $ident ) {
  my $webuser = `ps -ef|egrep "apache|httpd"|grep -v grep|awk '{print \$1}'|grep -v "root"|head -1`;
  chomp($webuser);
  print "<PRE>";
  print "LPAR2RRD could not read SSH identity file (under WEB user : $webuser): $ident\n";
  print "\n";
  print "\# ls -l $ident\n";
  my $ls = `ls -l $ident 2>&1`;
  print "$ls\n";
  print "\n";
  print "1. copy lpar2rrd ssh identity file (/home/lpar2rrd/.ssh/id_dsa (id_rsa) to $ident\n";
  print "2. under root user change ownership to the user under which runs the WEB server:\n";
  print " # chown $webuser $ident\n";
  print "3. change .ssh dir to be world-wide readable:\n";
  print " # chmod 755 /home/lpar2rrd/.ssh\n";
  print "4. assure it has 600 file rights \n";
  print " # chmod 600 $ident \n";
  print "</PRE></BODY></HTML>";
  close(OUT) if $DEBUG == 2;
  exit(0);
}

my $rate = `$SSH -i $ident $hmc_user\@$host "lslparutil -r config -m \\"$managedname_sp\\" -F sample_rate 2>&1" 2>&1|egrep -iv "Could not create directory|known hosts"`;
chomp($rate);
if ( $rate =~ /Permission denied/ ) {

  #my $webuser = getlogin();  # It does not work .... why?
  my $webuser = `ps -ef|egrep "apache|httpd"|grep -v grep|awk '{print \$1}'|grep -v "root"|head -1`;
  chomp($webuser);
  print "<PRE>";
  print "LPAR2RRD could not connect to $host under the web user : $webuser\n";
  print " # $SSH -i $ident $hmc_user\@$host \"lshmc -v\"\n";
  print "   $rate\n";
  print "\n";
  print "Make sure that following conditions are passed:\n\n";
  print "It should be owned by user : $webuser\n";

  #print "\# ls -l $ident\n";
  my $ls = `ls -l $ident 2>&1`;
  print "$ls\n";
  print "\nFix under root user:\n";
  print "chown $webuser $ident\n\n";
  my @ident_dir = split( /\//, $ident );
  my $dir       = "";
  print "All following directories should be readable for user : $webuser\n";

  foreach my $item (@ident_dir) {
    $dir .= "/" . $item;
    $dir =~ s/\/\//\//g;
    if ( "$dir" !~ m/$ident/ ) {
      my $ls = `ls -ld $dir 2>&1`;
      print "$ls";
    }
  }
  print "\n\n\nMake sure that ssh key is properly copied into /home/lpar2rrd/.ssh/realt_dsa :\n";
  print " # diff .ssh/realt_dsa .ssh/id_dsa\n";
  print "\n\n\n\nFor further deguging you might temporary allow logon to $webuser account (assign a shell in /etc/passwd) \n and try the command on the top under $hmc_user user.\n";
  print "</PRE></BODY></HTML>";
  close(OUT) if $DEBUG == 2;
  exit(0);
}
if ( $rate == 3600 ) {
  print "<PRE>";

  #print "$rate $managedname\n";
  print "LPAR2RRD does not support \"refresh\" for systems where is utilization sample rate 3600 secs (it makes no sense)\n";
  print "</PRE></BODY></HTML>";
  close(OUT) if $DEBUG == 2;
  exit(0);
}

print "<table align=\"center\" summary=\"Graphs\">";
print "<tr>
           <td class=\"relpospar\">
            <div class=\"relpos\">
              <div>
                <div class=\"g_title\">
                  <div class=\"popdetail\"></div>
                  <div class=\"refresh fas fa-sync-alt\">
                    <a href=\"/lpar2rrd-cgi/lpar2rrd-realt.sh?source=$lpar_en&hmc=$hmc_en&mname=$managedname_en&new_gui=$new_gui\"></a>
                  </div>
                  <div class=\"g_text\"><span></span></div>
                </div>
                     <div title=\"Click to show detail\"><img class=\"lazy\" border=\"0\" data-src=\"/lpar2rrd-cgi/real-time.sh?source=$lpar_en&hmc=$hmc_en&mname=$managedname_en&new_gui=$new_gui&none=$none\" src=\"css/images/sloading.gif\" >
                       <div class=\"zoom\" title=\"Click and drag to select range\"></div>
                     </div>
              </div>
              <div class=\"legend\"></div>
            <div>
           </td>
           </tr>\n";

print "</table><br>\n";

if ( $hmc_en =~ m/^sdmc$/ ) {
  if ( $managedname_en =~ m/^p795-fake$/ || $managedname_en =~ m/^p595-fake$/ ) {

    # it is lpar2rrd demo site, refresh does not work for those 2 fake servers, print it ou ...
    print "<br><h3>Refresh does not work (does not get new data) on demo site for fake p795-fake and p595-fake servers<br>It works ony for real p
710 server</h3><br>";
  }
}
print "<ul style=\"display: none\"><li class=\"tabagent\"></li></ul>\n";    # to add the data source icon

close(OUT) if $DEBUG == 2;

exit(0);

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

