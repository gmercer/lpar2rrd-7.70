use strict;
use warnings;
use CGI;
use Sys::Hostname;
use File::Path 'rmtree';

my $basedir = $ENV{INPUTDIR};
my $tmpdir  = "$basedir/tmp";
if ( defined $ENV{TMPDIR_LPAR} ) {
  $tmpdir = $ENV{TMPDIR_LPAR};
}

# my $lpar2rrd_server = hostname();
# my $lpar2rrd_server = "localhost";
my $lpar2rrd_server = $ENV{LPAR2RRD_AGENT_DAEMON_IP} ||= "localhost";

#my $port            = "";
my $port = $ENV{LPAR2RRD_AGENT_DAEMON_PORT} ||= "";
$port = ":$port" if $port ne "";

# not used anymore
#if ( defined $ENV{DEMO} && $ENV{DEMO} ne '') {
#  $port = ":8262";
#}
my $user_name = getpwuid($<);

my $cgi       = new CGI;
my $file_orig = $cgi->param('file');
my $file      = $file_orig;
my $utime     = time;
my $DEBUG     = 3;

my $name = $file;
$file =~ m/^.*(\\|\/)(.*)/;    # strip the remote path and keep the filename
$name = $2 if defined $2;

my $nmon_dir = "/tmp/ext_nmon_$utime";    #dir for uploaded file
my $namex    = "$nmon_dir/$name";

print $cgi->header();

#unlink "/var/tmp/lpar2rrd-agent-nmon-$lpar2rrd_server-apache.err";
my $file_n = "/var/tmp/lpar2rrd-agent-nmon-$lpar2rrd_server-$user_name.txt";
if ( -f "$file_n" ) {
  unlink "$file_n" or print "Could not unlink $file_n: $!";
}
$file_n = "/var/tmp/lpar2rrd-agent-nmon-$lpar2rrd_server-$user_name-time_file.txt";
if ( -f "$file_n" ) {
  unlink "$file_n" or print "Could not unlink $file_n: $!";
}

if ( !-d $nmon_dir ) {
  mkdir( $nmon_dir, 0755 ) || error( " Cannot mkdir $nmon_dir: $!" . __FILE__ . ":" . __LINE__ ) && exit 0;
}

#print "$utime file_orig ,$file_orig, file ,$file, \$name ,$name,\n";
open( LOCAL, ">$namex" ) or die $!;
while (<$file>) {
  print LOCAL $_;
}
print "<BR>file $file has been successfully uploaded... thank you at " . localtime() . "<BR>";
print STDERR "<BR>file $file has been successfully uploaded... thank you at " . localtime() . "<BR>";

system "perl /opt/lpar2rrd-agent/lpar2rrd-agent.pl -n $nmon_dir $lpar2rrd_server$port >> /var/tmp/lpar2rrd-agent-nmon-ext.out 2>&1";

print "<BR>file $file has been  processed<BR>";
print STDERR "<BR>file $file has been  processed<BR>";

print "trying to remove old ext-nmon dirs<BR>";
my @files_to_delete = </tmp/ext_nmon_*>;
foreach (@files_to_delete) {
  next if !-d $_;    #only dir, files are deleted in install-html.sh:  find /tmp -name ext-nmon-query-

  #           print "trying delete $_\n";
  my $age = -M;
  if ( $age > 7 ) {
    rmtree( "$_", { error => \my $err } );
    if ( defined $err ) {
      for my $diag (@$err) {
        my ( $file, $message ) = %$diag;
        if ( $file eq '' ) {
          print "general error: $message\n";
        }
        else {
          print "problem removing $file: $message\n";
        }
      }
    }
    else {
      print "dir older 7 days $_ has been removed<BR>";
    }
  }
}

my $q_file = "$tmpdir/ext-nmon-query-$utime";
if ( !-f $q_file ) {
  print "<BR>query string ($q_file) has not been prepared - either some error: see file /var/tmp/lpar2rrd-agent-nmon-ext.out or you use Private (apache) /tmp <BR>";
  print "<BR>Please send announcement to support\@lpar2rrd.com, thanks<BR>";
  exit 0;
}

open my $fh, '<', "$q_file";
my @daem_q_file = <$fh>;
close $fh;
unlink $q_file || print "<BR>cannot remove query string file ($q_file) - some error appeared<BR>" && print STDERR "<BR>cannot remove query string file ($q_file) - some error appeared<BR>";

# server=LINUX-RedHat1402593519--unknown&lpar=bsrpmgt0008--NMON--&1444555666

# use server and lpar
# use time from first and last line
# prepare something like this:

#lpar2rrd-cgi/lpar2rrd-external-cgi.sh?
#start-hour=01&start-day=25&start-mon=06&start-yr=2014&
#end-hour=12&end-day=25&end-mon=06&end-yr=2014&
#type=m&HEIGHT=150&WIDTH=900&yaxis=c&
#HMC=no_hmc&MNAME=LINUX-RedHat1403776342--unknown&

( my $mname, my $lpar, my $first_time ) = split( '&', $daem_q_file[0] );    #first line
( undef, $mname ) = split( '=', $mname );
$mname =~ s/ /+/g;

#$mname =~s/([^A-Za-z0-9\+-_])/sprintf("%%%02X",ord($1))/seg;
( undef, $lpar ) = split( '=', $lpar );
$lpar =~ s/ /+/g;

#$lpar =~s/([^A-Za-z0-9\+-_])/sprintf("%%%02X",ord($1))/seg;
( undef, undef, my $shour, my $smday, my $smon, my $syear, undef ) = localtime($first_time);
$smon++;
$syear += 1900;
( undef, undef, my $last_time ) = split( '&', $daem_q_file[-1] );           #last line
( undef, undef, my $ehour, my $emday, my $emon, my $eyear, undef ) = localtime($last_time);
$ehour++;
$ehour = 1 if $ehour > 24;
$emon++;
$eyear += 1900;

# workaround for slash in server name
my $slash_alias = "∕";                                                      #hexadec 2215 or \342\210\225

# original slash not possible in query string, so replace it by fun string
# must be then again tested in detail-graph-cgi.pl/detail-cgi.pl/lpar2rrd-cgi.pl
$mname =~ s/$slash_alias/slashslash/g;

my $q_string = "?menu=extnmon&";
$q_string .= "start-hour=$shour&start-day=$smday&start-mon=$smon&start-yr=$syear&";
$q_string .= "end-hour=$ehour&end-day=$emday&end-mon=$emon&end-yr=$eyear&";
$q_string .= "type=m&HEIGHT=150&WIDTH=900&yaxis=c&";
$q_string .= "HMC=no_hmc&MNAME=$mname&";
$q_string .= "LPAR=$lpar&entitle=0&gui=1";

#print "mname je $mname\n $daem_q_file[0]\n";

print "<a id='nmon-link' href='" . $q_string . "' rel='nofollow' target='_blank'><BR>Click here to see your graphs.<BR><\/a>";

sub error {
  my $text     = shift;
  my $act_time = localtime();
  chomp($text);

  #print "ERROR          : $text : $!\n";
  print STDERR "$act_time: $text : $!\n";
  print "$act_time: $text : $!\n" if $DEBUG > 2;

  return 1;
}

