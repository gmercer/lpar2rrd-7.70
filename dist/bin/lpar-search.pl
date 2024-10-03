use strict;
use warnings;
use RRDp;
use POSIX qw(strftime);
use Env qw(QUERY_STRING);
use Time::Local;
use File::Basename;
use Time::Local;

use XenServerDataWrapperOOP;
use XenServerDataWrapper;
use XenServerMenu;

use OVirtDataWrapper;
use OVirtMenu;

use OracleVmDataWrapperOOP;
use OracleVmDataWrapper;
use OracleVmMenu;

use AWSDataWrapperOOP;
use AWSDataWrapper;
use AWSMenu;

use GCloudDataWrapperOOP;
use GCloudDataWrapper;
use GCloudMenu;

use AzureDataWrapperOOP;
use AzureDataWrapper;
use AzureMenu;

use KubernetesDataWrapperOOP;
use KubernetesDataWrapper;
use KubernetesMenu;

use OpenshiftDataWrapperOOP;
use OpenshiftDataWrapper;
use OpenshiftMenu;

use NutanixDataWrapperOOP;
use NutanixDataWrapper;
use NutanixMenu;

use ProxmoxDataWrapperOOP;
use ProxmoxDataWrapper;
use ProxmoxMenu;

use FusionComputeDataWrapperOOP;
use FusionComputeDataWrapper;
use FusionComputeMenu;

use DockerDataWrapperOOP;
use DockerMenu;

use Data::Dumper;
use Xorux_lib;

my $DEBUG = $ENV{DEBUG};

#$DEBUG = "2";
my $inputdir = $ENV{INPUTDIR};
my $webdir   = $ENV{WEBDIR};
my $tmpdir   = "$inputdir/tmp";
if ( defined $ENV{TMPDIR_LPAR} ) {
  $tmpdir = $ENV{TMPDIR_LPAR};
}

my $rrdtool                 = $ENV{RRDTOOL};
my $refer                   = $ENV{HTTP_REFERER};
my $errlog                  = $ENV{ERRLOG};
my $managed_systems_exclude = $ENV{MANAGED_SYSTEMS_EXCLUDE};

my $csv_separ = ";";    # CSV separator
if ( defined $ENV{CSV_SEPARATOR} ) {
  $csv_separ = $ENV{CSV_SEPARATOR};    # CSV separator
}
my $csv = 0;

# case sensitive search was canceled
my $case = 0;

my $vmware_vm_search = "vmware_vm_search.csv";

print STDERR "25 lpar-search.pl -- $QUERY_STRING\n" if $DEBUG == 2;
( my $pattern, my $entitle, my $sort_order, my $referer ) = split( /&/, $QUERY_STRING );

# print STDERR "48 $QUERY_STRING - $refer\n" ;

if ( defined $entitle ) {
  $entitle =~ s/entitle=//;
}
$pattern =~ s/LPAR=//;
$pattern =~ tr/+/ /;
$pattern =~ s/%([\dA-Fa-f][\dA-Fa-f])/ pack ("C",hex ($1))/seg;
if ( defined $sort_order ) {
  $sort_order =~ s/sort=//;
}
else {
  $sort_order = "";
}
if ( defined $referer ) {
  $referer =~ s/referer=//;
}

# menut.txt is used in vmware, hyperv
my $menu_txt = "$inputdir/tmp/menu.txt";
my @menu_array;

if ( -f $menu_txt ) {
  open( FC, "< $menu_txt" ) || error( "Cannot read $menu_txt: $!" . __FILE__ . ":" . __LINE__ ) && return 0;
  @menu_array = <FC>;
  close(FC);
}

#
### solution of possible CSV export
#
# /lpar2rrd-cgi/lpar-search.sh?LPAR=$pattern&host=CSV&type=VMWARE
if ( defined $entitle && $entitle eq "host=CSV" ) {
  $csv = 1;
  if ( $sort_order eq "type=VMWARE" ) {
    vmware_search();
    exit;
  }
}

# print HTML header
print "Content-type: text/html\n\n";

chdir("$inputdir/data");

# search through curr_profile
my @out_prof        = ();
my @out_prof_no_hmc = ();
my @out_prof_tmp    = ();
my $out_prof_indx   = 0;
foreach my $line (<*/*/lpar.cfg>) {
  chomp($line);
  my $sym_link = $line;
  $sym_link =~ s/\/.*//g;

  #`echo "00 $line : $sym_link" >> /tmp/e1`;
  if ( -l "$sym_link" ) {
    next;    # avoid sym links
  }

  #`echo "01 $line : $lpar" >> /tmp/e1`;
  my @out_prof_act = `egrep "curr_profile=.\*.,work_group_id=" "$line" |sed -e 's/^name=//' -e 's/,lpar_id.*//g'`;
  foreach my $line_lpar (@out_prof_act) {
    chomp($line_lpar);
    $line =~ s/lpar.cfg//g;
    $line_lpar =~ s/\//&&1/g;
    $out_prof_tmp[$out_prof_indx] = $line . $line_lpar;

    #`echo "$out_prof_tmp[$out_prof_indx]" >> /tmp/e1`;
    $out_prof_indx++;
  }
}

# search for lpars
my @out = ();
if ( $sort_order =~ m/lpar/ ) {

  # sorting per LPARs
  @out = `find . -type f -name "\*.rr[m|h]"|egrep -v "pool.rrh|pool.rrm|mem.rrh|mem.rrm|SharedPool[0-9].rrh|SharedPool[0-9].rrm|SharedPool[0-9][0-9].rrh|SharedPool[0-9][0-9].rrm"|sort -t "/" -f -k 4`;
  @out_prof = sort { ( split '/', $a )[2] cmp( split '/', $b )[2] } @out_prof_tmp;
}
else {
  if ( $sort_order =~ m/hmc/ ) {

    # sorting per HMC/SDMC/IVM
    @out = `find . -type f -name "\*.rr[m|h]"|egrep -v "pool.rrh|pool.rrm|mem.rrh|mem.rrm|SharedPool[0-9].rrh|SharedPool[0-9].rrm|SharedPool[0-9][0-9].rrh|SharedPool[0-9][0-9].rrm"|sort -t "/" -f -k 3`;
    @out_prof = sort { ( split '/', $a )[1] cmp( split '/', $b )[1] } @out_prof_tmp;
  }
  else {
    #sorting per server
    @out = `find . -type f -name "\*.rr[m|h]"|egrep -v "pool.rrh|pool.rrm|mem.rrh|mem.rrm|SharedPool[0-9].rrh|SharedPool[0-9].rrm|SharedPool[0-9][0-9].rrh|SharedPool[0-9][0-9].rrm"|sort -f`;
    @out_prof = sort { ( split '/', $a )[0] cmp( split '/', $b )[0] } @out_prof_tmp;
  }
}

my $wrkdir = "$inputdir/data";
opendir( DIR, "$wrkdir" ) || error( " directory does not exists : $wrkdir " . __FILE__ . ":" . __LINE__ ) && exit 1;
my @wrkdir_all = grep !/^\.\.?$/, readdir(DIR);
closedir(DIR);

foreach my $server_all (@wrkdir_all) {
  $server_all = "$wrkdir/$server_all";
  my $server = basename($server_all);
  if ( $server =~ /[vV][mM][wW][aA][rR][eE]/ ) { next; }
  if ( -l $server_all )                        { next; }
  if ( -f "$server_all" )                      { next; }
  if ( $server_all =~ /--HMC--/ )              { next; }
  if ( $server =~ /windows/ )                  { next; }

  chomp $server_all;
  chomp $server;
  opendir( DIR, "$wrkdir/$server" ) || error( "can't opendir $wrkdir/$server: $! :" . __FILE__ . ":" . __LINE__ ) && next;
  my @hmcdir_all = grep !/^\.\.?$/, readdir(DIR);
  closedir(DIR);

  foreach my $hmc_all_base (@hmcdir_all) {
    my $hmc_all = "$wrkdir/$server/$hmc_all_base";
    my $hmc     = basename($hmc_all);
    if ( $hmc eq "no_hmc" ) {
      opendir( DIR, "$wrkdir/$server/$hmc" ) || error( "can't opendir $wrkdir/$server/$hmc: $! :" . __FILE__ . ":" . __LINE__ ) && next;
      my @lpardir_all = grep !/^\.\.?$/, readdir(DIR);
      closedir(DIR);
      foreach my $lpar (@lpardir_all) {
        my $lpar_unmanaged = "$wrkdir/$server/$hmc/$lpar";

        #print STDERR"$lpar_unmanaged\n";
        push( @out_prof_no_hmc, "$server/$hmc/$lpar" );
      }

    }
  }
}

#print STDERR "-- $inputdir $lpar +$case+ \n"if $DEBUG == 2 ;
#print "-- $inputdir $lpar -- $sort_order -- $out[0]  \n";
print "<center>\n";

#print "<table><tr><td><table class=\"lparsearch tablesorter\" align=\"center\" summary=\"Graphs\">\n<thead>\n";
print "<tr><td><table class=\"lparsearch tablesorter\" align=\"center\" summary=\"Graphs\">\n<thead>\n";

# Check whether AIX or another OS due to "grep -p" which supports only AIX
my $uname = `uname -a`;
chomp($uname);
my $aix = 0;
my @u_a = split( / /, $uname );
foreach my $u (@u_a) {
  if ( $u =~ "AIX" ) {
    $aix = 1;
  }
  last;
}

# find out HTML_referer
# remove from the path last 4 things
# http://nim.praha.cz.ibm.com/lpar2rrd/hmc1/PWR6B-9117-MMA-SN103B5C0%20ttt/pool/top.html
# --> http://nim.praha.cz.ibm.com/lpar2rrd
my @full_path = split( /\//, $refer );
my $k = 0;
foreach my $path (@full_path) {
  $k++;
}

#
# if it goes through "custom groups" then there are only 2 subdirs instead standard 3 in lpar2rrd referer path!!!
#

if ( $refer =~ m/\/custom\// ) {
  $k--;
  $k--;
  $k--;
}
else {
  $k--;
  $k--;
  $k--;
  $k--;
}

my $j         = 0;
my $html_base = "";
foreach my $path (@full_path) {
  if ( $j < $k ) {
    if ( $j == 0 ) {
      $html_base .= $path;
    }
    else {
      $html_base .= "/" . $path;
    }
    $j++;
  }
}
my $html_base_en = $html_base;
$html_base_en =~ s/([^A-Za-z0-9+-_])/sprintf("%%%02X", ord($1))/seg;

if ( !$referer eq '' ) {
  $html_base_en = $referer;
  $referer =~ tr/+/ /;
  $referer =~ s/%([\dA-Fa-f][\dA-Fa-f])/ pack ("C",hex ($1))/seg;
  $html_base = $referer;
}

#$html_base_en contains encoded html_base (got from REFER) which has to be passed as HMC/Server sorting have there cgi-bin/...

#print "<BR>-- $html_base -- $refer <BR>";

my $target_sample = " ";
$sort_order = "lpar";

if ( $aix == 1 ) {

  # AIX with  grep -p support
  print "<tr><th class=\"sortable\"><B>Server</B></th><th class=\"sortable\"><B>LPAR</B></th><th class=\"sortable\"><B>HMC</B></th><th class=\"sortable\" align=\"center\"><B>Last update</B></th><th class=\"sortable\" align=\"center\"><B>OS</B></th></tr>";
}
else {
  # other platforms without OS support
  print "<tr><th class=\"sortable\" align=\"center\"><B>Server</B></th><th class=\"sortable\" align=\"center\"><B>LPAR</B></th><th align=\"center\" class=\"sortable\"><B>HMC</B></th><th class=\"sortable\" align=\"center\"><B>Last update</B></th><th class=\"sortable\" align=\"center\"><B>OS</B></th></tr>";
}
print "</thead><tbody>\n";

print STDERR "$uname $aix\n" if $DEBUG == 2;

#print "<BR><BR>$html_base -- $html_base_en -- $referer -- $refer\n";

# start RRD via a pipe for getting last update of data in RRDTool files
RRDp::start "$rrdtool";

my @solaris_vms = ();

solaris_search();

vmware_search();

xenserver_search();

ovirt_search();

windows_search();

oraclevm_search();

aws_search();

gcloud_search();

azure_search();

kubernetes_search();

openshift_search();

nutanix_search();

proxmox_search();

fusioncompute_search();

docker_search();

print "<br>Note you can use regular expressions for LPAR/VM search (search is case non sensitive)\n";

# close RRD pipe
RRDp::end;

exit(0);

sub lpar_display {
  my ( $pattern, $inputdir, $out_tmp ) = @_;
  my @out = @{$out_tmp};

  my $managedname_exl = "";
  my @m_excl          = ();
  my $pattern_upper   = uc($pattern);

  my $server_index  = "gui-cpu.html";
  my $target        = " ";
  my $target_sample = " ";
  foreach my $line (@out) {
    chomp($line);
    my $line_org = $line;
    $line =~ s/^.\///;
    $line =~ s/.rrh$//;
    $line =~ s/.rrm$//;
    ( my $managed, my $hmc, my $lpar ) = split( /\//, $line );
    if ( !defined $lpar || $lpar eq '' ) {
      next;
    }

    # windows is another sub
    next if $managed eq "windows";

    if ( is_IP($managed) == 1 ) {
      next;    # wrong entry from the HMC, a problem of the HMC or unconfigured server yet
    }

    # Exclude excluded managed systems
    my $managed_ok = 1;
    if ( defined($managed_systems_exclude) && $managed_systems_exclude ne '' ) {
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

    # print STDERR "368 \$lpar $lpar\n";
    # do not care if not in menu.txt
    my $lpar_short = $lpar;
    $lpar_short =~ s/\-\-NMON\-\-//;
    $lpar_short =~ s/:/===double-col===/;
    my ($lpar_in_menu) = grep /:$lpar_short:$lpar_short/, @menu_array;
    if ( !defined $lpar_in_menu ) {
      next;
    }

    my $lpar_slash = $lpar;
    $lpar_slash =~ s/\&\&1/\//g;

    #$lpar_slash =~ s/ /&nbsp;/g;
    my $managedn = $managed;

    #$managedn =~ s/ /&nbsp;/g;
    my $hmcn = $hmc;

    #$hmcn =~ s/ /&nbsp;/g;

    # LPAR regex search
    my $lpar_upper = uc($lpar);
    if ( $lpar_upper !~ m/$pattern_upper/ && length($pattern_upper) > 0 ) {
      next;
    }

    #print "+++ $lpar $inputdir/data/$managed/$hmc/cpu.cfg\n";
    # open cpu.cfg to check if an LPAR still exists (mostly due to LPM)
    my $cfg = "$inputdir/data/$managed/$hmc/cpu.cfg";
    if ( -f "$cfg" ) {
      my $found = 1;
      open( FCFG, "< $cfg" ) || next;
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

        # lpar probably does not actually exist (removed/LPM)
        next;
      }
    }

    # end of checking if lpar exists

    my $managed_unknown = $managedn;
    $managed_unknown =~ s/--unknown$//;

    my $lpar_url    = urlencode($lpar_short);
    my $managed_url = urlencode($managed);
    my $hmc_url     = urlencode($hmc);
    my $date        = get_date( $inputdir, $line_org );
    my $date_txt    = strftime "%Y-%m-%d %H:%M", localtime($date);
    my $os          = get_os( $managed, $hmc, $aix, $inputdir, $lpar_slash, $date_txt );

    # print "<tr><td nowrap><A HREF=\"$hmc/$managed/pool/$server_index\">$managed_unknown</A></td>";
    #my $line_to_print = "<tr><td nowrap><A HREF=\"$hmc/$managed/pool/$server_index\">$managed_unknown</A></td>";
    my $line_to_print = "";

    # my $line_to_print = "<tr><td nowrap><A class=\"backlink\" HREF=\"/lpar2rrd-cgi/detail.sh?host=$hmc_url&server=$managed_url&lpar=pool&item=pool\">$managed_unknown</A></td>";

    my $item_test = "";
    my $platform  = "";

    if ( $managed =~ /--unknown/ ) {
      $item_test     = "oscpu";
      $line_to_print = "<tr><td nowrap>$managed_unknown</td>";
      $platform      = "&d_platform=Linux";
    }
    else {
      $item_test     = "lpar";
      $line_to_print = "<tr><td nowrap><A class=\"backlink\" HREF=\"/lpar2rrd-cgi/detail.sh?host=$hmc_url&server=$managed_url&lpar=pool&item=pool\">$managed_unknown</A></td>";
    }

    ### test ACL ###
    if ( $ENV{HTTP_XORUX_APP} && $ENV{HTTP_XORUX_APP} eq "Xormon" ) {
      require ACLx;
      require PowerDataWrapper;
      require SolarisDataWrapper;

      my $url_old = "/lpar2rrd-cgi/detail.sh?host=$hmc&server=$managed&lpar=$lpar_url&item=$item_test&none=none$platform";
      my $url_new = Xorux_lib::url_old_to_new($url_old);
      my $params  = Xorux_lib::parse_url_params($url_new);

      my ( $acl_hw_type, $acl_item_id ) = ( '', '' );
      $acl_hw_type = 'POWER';
      $acl_item_id = $params->{id} if ( defined $params->{id} );

      my $acl = ACLx->new();
      my $aclitem = { hw_type => $acl_hw_type, item_id => $acl_item_id, match => 'granted' };
      if ( !$acl->isGranted($aclitem) ) { next; }
    }

    # print "    <td nowrap><a href=\"/lpar2rrd-cgi/detail.sh?host=$hmc&server=$managed&lpar=$lpar_url&item=$item_test&none=none\">$lpar_slash</a></td>";
    $line_to_print .= "    <td nowrap><a class=\"backlink\" href=\"/lpar2rrd-cgi/detail.sh?host=$hmc&server=$managed&lpar=$lpar_url&item=$item_test&none=none$platform\">$lpar_slash</a></td>";

    if ( $managed =~ /--unknown/ ) {
      $hmc = "";
    }

    # print "    <td nowrap>$hmc</td>";
    # print "$os\n";

    if ( $managed !~ /Solaris/ ) {
      $line_to_print .= "    <td nowrap>$hmc</td>";
    }
    $line_to_print .= "$os\n";

    if ( $managed =~ /Solaris/ ) {
      push @solaris_vms, $line_to_print;
      next;
    }

    print $line_to_print;

  }    #end of the foreach
}

sub urlencode {
  my $s = shift;

  #$s =~ s/ /+/g;
  #$s =~ s/([^A-Za-z0-9\+-_])/sprintf("%%%02X", ord($1))/seg;
  $s =~ s/([^a-zA-Z0-9_.!~*()'\''-])/sprintf("%%%02X", ord($1))/ge;
  return $s;
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

sub get_os {
  my $managed  = shift;
  my $hmc      = shift;
  my $aix      = shift;
  my $inputdir = shift;
  my $lpar_ok  = shift;
  my $date     = shift;
  my $os       = "";
  if ( -f "$inputdir/data/$managed/$hmc/config.cfg" ) {

    if ( $aix == 1 ) {

      # AIX with grep -p support
      $os = `egrep -p \"^name\.\*$lpar_ok\" $inputdir/data/"$managed"/"$hmc"/config.cfg|egrep \"^os_vers\"|head -1`;
    }
    else {
      $os = `egrep -A 20 \"^name\.\*$lpar_ok\" $inputdir/data/"$managed"/"$hmc"/config.cfg|egrep \"^os_vers\"|head -1`;
    }
    chomp($os);
    $os =~ s/^os_version//g;
    $os =~ s/  //g;
    $os =~ s/ /&nbsp;/g;
    $os =~ s/0.0.0.0.0.0//g;    # IVM somehow do not suport that, it places there 0.0.0.0.0.0
  }
  else {
    $os = "";
  }

  #print STDERR "001 $inputdir/data/$managed/$hmc/config.cfg : $managed - $lpar_ok - $os\n";

  $os =~ s/Unknown//;
  $date =~ s/ /&nbsp;/g;
  print STDERR "$html_base -- $lpar_ok $os $aix\n" if $DEBUG == 2;
  if ( $managed =~ /--unknown/ ) {
    $os = "NA";
    my $date_unknown = "unknown";
    if ( -f "$wrkdir/$managed/$hmc/$lpar_ok/cpu.mmm" ) {
      $date_unknown = ( stat("$wrkdir/$managed/$hmc/$lpar_ok/cpu.mmm") )[9];
      $date = strftime "%Y-%m-%d %H:%M", localtime($date_unknown);
    }
  }

  return "<td nowrap>$date</td><td nowrap>$os</td></tr>\n";
}

sub solaris_search {

  # my @solaris_vms = (); #this is filled by lpar_display procedure as side effect
  lpar_display( $pattern, $inputdir, \@out );

  print "</tbody></table></td></tr>\n";

  # skiped -PH
  print "<tr align =\"center\" ><td><br><b>Linux</b><br></td></tr>\n";
  print "<tr><td><table class=\"lparsearch tablesorter\" align=\"center\" summary=\"LPAR search\">\n<thead>\n";

  print "<tr><th class=\"sortable\" align=\"center\"><B>Server</B></th><th class=\"sortable\" align=\"center\"><B>LPAR</B></th><th class=\"sortable\" align=\"center\"><B>HMC</B></th><th align=\"center\" class=\"sortable\"><B>Last update</B></th><th class=\"sortable\" align=\"center\"><B>OS</B></th></tr>";
  print "</thead><tbody>\n";

  # profiles name search
  lpar_display( $pattern, $inputdir, \@out_prof_no_hmc );

  print "</tbody></table></td></tr>\n";

  if ( @solaris_vms > 0 ) {    # print solaris table
    print "<tr align =\"center\" ><td><br><b>Solaris search</b><br></td></tr>\n";
    print "<tr><td><table class=\"lparsearch tablesorter\" align=\"center\" summary=\"LPAR search - profiles\">\n<thead>\n";

    print "<tr><th class=\"sortable\" align=\"center\"><B>Server</B></th><th class=\"sortable\" align=\"center\"><B>LPAR</B></th><th align=\"center\" class=\"sortable\"><B>Last update</B></th><th class=\"sortable\" align=\"center\"><B>OS</B></th></tr>";
    print "</thead><tbody>\n";

    # print solaris items
    foreach (@solaris_vms) {

      #( my $managed, my $hmc, my $lpar ) = split( /\//, $line );
      #if ( !defined $lpar || $lpar eq '' ) left_curly
      #  next;
      print $_;
    }
    print "</tbody></table></td></tr>";    #</table></center><br><br>\n";
  }
}

sub vmware_search {
  if ( !defined $ENV{INPUTDIR} ) {
    error("Not defined INPUTDIR, probably not read etc/lpar2rrd.cfg") && return 0;
  }

  # CSV icon
  # print "<a href=\"vmware_vm_search.csv\"><div class=\"csvexport\">VMWARE_VM_search</div></a>";

  # following works in stor2rrd
  if ( !$csv ) {
    print "<a class=\"csvfloat\" href=\"/lpar2rrd-cgi/lpar-search.sh?LPAR=$pattern&host=CSV&type=VMWARE\" title=\"CSV\"><img src=\"css/images/csv.gif\"></a>";
    print "<tr align =\"center\" ><td><br><b>VMware search</b><br></td></tr>\n";
    print "<tr><td><table class=\"lparsearch tablesorter\" align=\"center\" summary=\"VMware search - profiles\">\n<thead>\n";
    print "<tr><th align=\"center\" class=\"sortable\"><B>ESXi</B></th><th align=\"center\" class=\"sortable\"><B>VM</B></th><th align=\"center\" class=\"sortable\"><B>vCenter</B></th><th align=\"center\" class=\"sortable\"><B>Cluster</B></th><th align=\"center\" class=\"sortable\"><B>Last update</B></th><th align=\"center\" class=\"sortable\"><B>vCPU</B></th><th align=\"center\"class=\"sortable\"><B>Reserved MHz</B></th><th align=\"center\"class=\"sortable\"><B>OS</B></th><th align=\"center\"class=\"sortable\"><B>Power</B></th><th align=\"center\"class=\"sortable\"><B>VMware tool</B></th><th align=\"center\"class=\"sortable\"><B>Memory Count (GB)</B></th><th align=\"center\"class=\"sortable\"><B>Provisioned Space (GB)</B></th><th align=\"center\"class=\"sortable\"><B>Used Space (GB)</B></th><th align=\"center\"class=\"sortable\"><B>UUID</B></th></tr>";
    print "</thead><tbody> \n";
  }
  else {
    print "Content-Disposition: attachment;filename=\"$vmware_vm_search\"\n\n";
    my $csv_header = "ESXi $csv_separ VM $csv_separ vCenter $csv_separ Cluster $csv_separ Last update $csv_separ vCPU $csv_separ Reserved MHz $csv_separ OS $csv_separ Power $csv_separ VMware tool $csv_separ Memory Count (GB) $csv_separ Provisioned Space (GB) $csv_separ Used Space (GB) $csv_separ UUID\n";
    print $csv_header;
  }

  my $actual_unix_time     = time;
  my $last_ten_days        = 10 * 86400;                            ### ten days back
  my $actual_last_ten_days = $actual_unix_time - $last_ten_days;    ### ten days back with actual unix time-
  my $wrkdir               = "$inputdir/data";
  my @wrkdir_all           = <$wrkdir/*>;
  my ( $uuid, $name_vm );
  my $list_of_vm    = "$wrkdir/vmware_VMs/vm_uuid_name.txt";
  my @all_rrm_files = <$wrkdir/vmware_VMs/*rrm>;

  # my @menu_array; # is global

  my @vm_list;
  if ( -f $list_of_vm ) {                                           ####### ALL VM servers in @vm_list
    open( FC, "< $list_of_vm" ) || error( "Cannot read $list_of_vm: $!" . __FILE__ . ":" . __LINE__ ) && return 0;
    @vm_list = <FC>;
    close(FC);
  }
  else {
    #error( "file $list_of_vm does not exist " . __FILE__ . ":" . __LINE__ ) && return 0;
    print "</tbody></table>\n";                                     # regular end of table
    return 0;
  }

  # test only 2nd coma separated part
  # 5030ead5-9ab7-8d0d-94b0-fb201c2dc2f5,cVM_cab_45e3d256024a,cVM_cab_45e3d256024a,f6b50c79-682a-552c-b439-d064de77f713
  my @vm_list_search = grep ( ( ( split( ",", $_ ) )[1] ) =~ /$pattern/i, @vm_list );

  #print STDERR "@vm_list_search";
  if ( defined $pattern && $pattern eq '' ) {
    @vm_list_search = @vm_list;
  }
  foreach my $rrm_file_path (@vm_list_search) {
    chomp $rrm_file_path;
    my ( $uuid_name, undef, undef ) = split /,/, $rrm_file_path;
    my ($vmware_path) = grep /$uuid_name/, @menu_array;
    if ( defined $vmware_path && $vmware_path ne '' ) {
      my ( undef, $cluster, $server, $uuid, $vm_name, undef, undef, $v_center ) = split /:/, $vmware_path;
      $cluster =~ s/===double-col===/:/g;
      my $last_timestamp = "$wrkdir/vmware_VMs/$uuid.last";
      my $timestamp      = "";
      if ( -f $last_timestamp ) {
        open( FC, "< $last_timestamp" ) || error( "Cannot read $last_timestamp: $!" . __FILE__ . ":" . __LINE__ ) && return 0;
        $timestamp = <FC>;
        close(FC);
      }

      #print "!$server,$vm_name,$v_center,$cluster,$timestamp?\n";
      my ($path) = split /&server/, $vmware_path;
      my ( undef, $host ) = split /\?host=/, $path;
      chomp $host;
      $host =~ s/===double-col===/:/g;
      my $cpu_html = "$wrkdir/$server/$host/cpu.csv";
      my @cpu_array;
      if ( -f $cpu_html ) {
        open( FC, "< $cpu_html" ) || error( "Cannot read $cpu_html: $!" . __FILE__ . ":" . __LINE__ ) && return 0;
        @cpu_array = <FC>;
        close(FC);
      }
      my $disk_html = "$wrkdir/$server/$host/disk.html";
      my @disk_array;
      if ( -f $disk_html ) {
        open( FC, "< $disk_html" ) || error( "Cannot read $disk_html: $!" . __FILE__ . ":" . __LINE__ ) && return 0;
        @disk_array = <FC>;
        close(FC);
      }

      chomp $vm_name;

      #print "CPU-HTML: $cpu_html\n";
      #print ",,$vm_name,,\n";
      $vm_name =~ s/ \[.*\]//g;

      #$vm_name =~ s/\]//g;
      my ($grep_vm) = grep /^$vm_name,/, @cpu_array;
      chomp $grep_vm;
      my ($grep_disk_vm) = grep />$vm_name</, @disk_array;
      chomp $grep_disk_vm;

      # print STDERR "524 ,$grep_disk_vm,@disk_array\n";
      my $provisioned_space_gb = "";
      my $used_space_gb        = "";
      if ( defined $grep_disk_vm && $grep_disk_vm ne '' ) {

        # <TR> <TD><B>Infra-mon</B></TD> <TD align="right" nowrap>112.2</TD> <TD align="right" nowrap>21.7</TD></TR>
        ( undef, $provisioned_space_gb, $used_space_gb, undef ) = split /nowrap>/, $grep_disk_vm;
        ( $provisioned_space_gb, undef ) = split /</, $provisioned_space_gb;
        ( $used_space_gb,        undef ) = split /</, $used_space_gb;
      }
      my $i_value = 0;

      #print "$index_id\n";
      if ( defined $grep_vm && $grep_vm ne '' ) {
        my ( undef, $v_cpu, $reser_mhz, undef, $shares, $shares_value, $os, $power_state, $tools_status, undef, undef, $memorySizeMB ) = split /,/, $grep_vm;
        my $memorySizeGB = $memorySizeMB / 1024;

        #(undef,$v_cpu,$reser_mhz,$shares,$shares_value,$os,$power_state,$tools_status) = split /"center">/, $grep_vm;
        my (@array_values) = split / /, $grep_vm;
        my ( $a, $b, $c, $d, $e ) = split //, $grep_vm;

        #print "$timestamp\n";
        my $last_time = "";
        if ( defined $timestamp && $timestamp ne '' ) {
          my ( $date, $time_a ) = split / /, $timestamp;
          my ( $month, $day, $year ) = split /\//, $date;
          my ( $hour, $min, undef ) = split /:/, $time_a;
          chomp( $month, $day, $year, $hour, $min );
          if ( $month =~ /^\d$/ ) { $month = "0$month"; }
          if ( $day =~ /^\d$/ )   { $day   = "0$day"; }

          #          if ( $min =~ /^\d$/ ) { my $number = "0"; $min = "$min$number"; }
          if ( $min =~ /^\d$/ ) { $min = "0$min"; }

          #          # if ( $hour =~ /^\d$/ ) { $hour = "$day"; }
          if ( $hour =~ /^\d$/ ) { $hour = "0$hour"; }
          $last_time = "$year-$month-$day $hour:$min";
        }

        my $cluster_name_only = $cluster;
        $cluster_name_only =~ s/^cluster_//;
        if ( !$csv ) {
          print "<tr><td nowrap><a class=\"backlink\" href=\"/lpar2rrd-cgi/detail.sh?host=$host&server=$server&lpar=pool&item=pool&d_platform=VMware\">$server</a></td><td nowrap><a class=\"backlink\" href=\"/lpar2rrd-cgi/detail.sh?host=$host&server=$server&lpar=$vm_name&item=lpar&d_platform=VMware&platform=VMware\">$vm_name</a></td><td nowrap><a class=\"backlink\" href=\"/lpar2rrd-cgi/detail.sh?vcenter=$v_center&item=vtop10&d_platform=VMware&host=$v_center\">$v_center</a></td><td nowrap><a class=\"backlink\" href=\"/lpar2rrd-cgi/detail.sh?vcenter=$v_center&cluster=$cluster_name_only&item=vm_cluster_totals&d_platform=VMware&host=$v_center\">$cluster_name_only</a></td><td nowrap align=\"right\">$last_time</td><td nowrap align=\"right\">$v_cpu</td><td nowrap align=\"right\">$reser_mhz</td><td nowrap align=\"left\">$os</td><td nowrap align=\"right\">$power_state</td><td nowrap align=\"right\">$tools_status</td><td nowrap align=\"right\">$memorySizeGB</td><td nowrap align=\"right\">$provisioned_space_gb</td><td nowrap align=\"right\">$used_space_gb</td><td nowrap align=\"left\">$uuid</td></tr>\n";

          #print "<tr><td nowrap><a class=\"backlink\" href=\"/lpar2rrd-cgi/detail.sh?host=$v_center&server=$server&lpar=pool&item=pool&none=none&d_platform=VMware\">$server</a></td><td nowrap><a class=\"backlink\" href=\"/lpar2rrd-cgi/detail.sh?host=$host&server=$server&lpar=$vm_name&item=lpar&none=none&d_platform=VMware\">$vm_name</a></td><td nowrap><a class=\"backlink\" href=\"/lpar2rrd-cgi/detail.sh?vcenter=$v_center&item=vtop10&none=none&d_platform=VMware\">$v_center</a></td><td nowrap><a class=\"backlink\" href=\"/lpar2rrd-cgi/detail.sh?vcenter=$v_center&cluster=$cluster_name_only&item=vm_cluster_totals&d_platform=VMware\">$cluster_name_only</a></td><td nowrap align=\"right\">$last_time</td><td nowrap align=\"right\">$v_cpu</td><td nowrap align=\"right\">$reser_mhz</td><td nowrap align=\"left\">$os</td><td nowrap align=\"right\">$power_state</td><td nowrap align=\"right\">$tools_status</td><td nowrap align=\"right\">$memorySizeGB</td><td nowrap align=\"right\">$provisioned_space_gb</td><td nowrap align=\"right\">$used_space_gb</td><td nowrap align=\"left\">$uuid</td></tr>\n";
        }
        else {
          print "$server $csv_separ $vm_name $csv_separ $v_center $csv_separ $cluster_name_only $csv_separ $last_time $csv_separ $v_cpu $csv_separ $reser_mhz $csv_separ $os $csv_separ $power_state $csv_separ $tools_status $csv_separ $memorySizeGB $csv_separ $provisioned_space_gb $csv_separ $used_space_gb $csv_separ $uuid\n";
        }
      }
    }
  }
  if ( !$csv ) {
    print "</tbody></table>\n";
  }
}

sub xenserver_search {
  if ( !defined $ENV{INPUTDIR} ) {
    warn( localtime() . ' : INPUTDIR undefined, probably have not read etc/lpar2rrd.cfg ' . __FILE__ . ':' . __LINE__ ) && return 0;
  }

  my $xenserver_acl = ( $ENV{HTTP_XORUX_APP} && $ENV{HTTP_XORUX_APP} eq 'Xormon' );
  my $xenserver_metadata = XenServerDataWrapperOOP->new( { acl_check => $xenserver_acl } );

  my @vms = @{ $xenserver_metadata->get_items( { item_type => 'vm' } ) };
  my $found = 0;
  my ( $vm_label, $vm_url );
  foreach my $vm (@vms) {
    my ( $vm_uuid, $vm_label ) = each %{$vm};

    if ( $vm_label =~ /$pattern/i || $vm_uuid =~ /$pattern/i ) {

      # print table header
      unless ($found) {
        print "<tr align =\"center\" ><td><br><b>XenServer search</b><br></td></tr>\n";
        print "<center><table class=\"lparsearch tablesorter\" align=\"center\" summary=\"Found VMs\">\n<thead>\n";
        print "<tr><th class=\"sortable\" align=\"center\"><b>VM</b></th><th class=\"sortable\" align=\"center\"><b>UUID</b></th></tr>\n";
        print "</thead><tbody>\n";
      }

      $vm_url = XenServerMenu::get_url( { type => 'vm', id => $vm_uuid } );
      print "<tr><td nowrap><a href=\"$vm_url\" class=\"backlink\">$vm_label</a></td><td nowrap>$vm_uuid</td></tr>\n";
      $found = 1;
    }
  }

  # print table footer
  if ($found) {
    print "</tbody></table></center><br><br>\n";
  }
}    ## sub xenserver_search

sub ovirt_search {
  my $ovirt_acl = ( $ENV{HTTP_XORUX_APP} && $ENV{HTTP_XORUX_APP} eq 'Xormon' );
  my $arch_vm = OVirtDataWrapper::get_conf_section('arch-vm');

  my $found = 0;
  foreach my $vm_uuid ( @{ OVirtDataWrapper::get_uuids('vm') } ) {
    my $vm_label = OVirtDataWrapper::get_label( 'vm', $vm_uuid );

    if ( $vm_label =~ /$pattern/i || $vm_uuid =~ /$pattern/i ) {

      # ACL check
      if ($ovirt_acl) {
        my $rrd = OVirtDataWrapper::get_filepath_rrd( { type => 'vm', uuid => $vm_uuid } );
        if ( !$rrd ) { next; }
      }

      my $vm_url = OVirtMenu::get_url( { type => 'vm', id => $vm_uuid } );
      my $cluster_uuid = OVirtDataWrapper::get_parent( 'vm', $vm_uuid );
      my $cluster_label = defined $cluster_uuid ? OVirtDataWrapper::get_label( 'cluster', $cluster_uuid ) : '';
      my $cluster_url = OVirtMenu::get_url( { type => 'cluster_aggr', id => $cluster_uuid } );
      my $datacenter_uuid = OVirtDataWrapper::get_parent( 'cluster', $cluster_uuid ) if defined $cluster_uuid;
      my $datacenter_label = defined $datacenter_uuid ? OVirtDataWrapper::get_label( 'datacenter', $datacenter_uuid ) : '';

      # include attached disks and their aggregate capacity
      my $disks = $arch_vm->{$vm_uuid}{disk};
      my @disk_links;
      my $disk_size_used = 0;
      foreach my $disk_uuid ( @{$disks} ) {
        my $disk_label = OVirtDataWrapper::get_label( 'disk', $disk_uuid );
        my $disk_url = OVirtMenu::get_url( { type => 'disk', id => $disk_uuid } );
        my $disk_link = "<a href=\"${disk_url}\" class=\"backlink\">${disk_label}</a>";
        push @disk_links, $disk_link;

        my $size = get_ovirt_disk_space_perf($disk_uuid);
        $disk_size_used += $size;
      }

      unless ($found) {

        # print "<h3>oVirt VMs</h3>\n";
        print "<tr align =\"center\" ><td><br><b>oVirt search</b><br></td></tr>\n";
        print "<center>";
        print "<table class=\"lparsearch tablesorter\" align=\"center\" summary=\"Found VMs\">\n<thead>\n";
        print "<tr>";
        print "<th class=\"sortable\" align=\"center\"><b>VM</b></th>";
        print "<th class=\"sortable\" align=\"center\"><b>Datacenter</b></th>";
        print "<th class=\"sortable\" align=\"center\"><b>Cluster</b></th>";
        print "<th class=\"sortable\" align=\"center\"><b>Attached disks</b></th>";
        print "<th class=\"sortable\" align=\"center\"><b>Used space [GB]</b></th></tr>\n";
        print "<tbody>\n";
      }

      print "<tr>";
      print "<td nowrap><a href=\"$vm_url\" class=\"backlink\">$vm_label</a></td>";
      print "<td nowrap>$datacenter_label</td>";
      print "<td nowrap><a href=\"$cluster_url\" class=\"backlink\">$cluster_label</a></td>";
      print "<td nowrap>" . join( '<br>', @disk_links ) . "</td>";
      print "<td nowrap>$disk_size_used</td>";
      print "</tr>\n";
      $found = 1;
    }
  }

  if ($found) {
    print "</tbody></table></center>\n";
  }

  # else {
  #   print "<p>no VM found</p>\n";
  # }

  sub get_ovirt_disk_space_perf {
    my $uuid = shift;

    my $disk_rrd = OVirtDataWrapper::get_filepath_rrd( { type => 'disk', uuid => $uuid } );
    if ( -f $disk_rrd ) {
      my $start_time = "now-3600";
      my $end_time   = time();
      my $name_out   = "test";
      RRDp::cmd qq(graph "$name_out"
      "--start" "$start_time"
      "--end" "$end_time"
      "DEF:space_mb=$disk_rrd:vm_disk_size_mb:AVERAGE"
      "CDEF:space_gb=space_mb,1024,/"
      "PRINT:space_gb:AVERAGE: %6.1lf"
      );
      my $answer = RRDp::read;
      if ( $$answer =~ "ERROR" ) {
        error("Rrdtool error : $$answer");
        return;
      }
      my $aaa = $$answer;
      ( undef, my $disk ) = split( "\n", $aaa );
      $disk = nan_to_null($disk);
      chomp($disk);

      return $disk;    # $line_disk_usage;
    }

    return;
  }

  sub nan_to_null {
    my $number = shift;
    $number =~ s/NaNQ/0/g;
    $number =~ s/NaN/0/g;
    $number =~ s/-nan/0/g;
    $number =~ s/nan/0/g;    # rrdtool v 1.2.27
    $number =~ s/,/\./;
    $number =~ s/\s+//;
    return $number;
  }
}    ## sub ovirt_search

sub aws_search {
  if ( !defined $ENV{INPUTDIR} ) {
    warn( localtime() . ' : INPUTDIR undefined, probably have not read etc/lpar2rrd.cfg ' . __FILE__ . ':' . __LINE__ ) && return 0;
  }

  my $aws_acl = ( $ENV{HTTP_XORUX_APP} && $ENV{HTTP_XORUX_APP} eq 'Xormon' );
  my $aws_metadata = AWSDataWrapperOOP->new( { acl_check => $aws_acl } );

  my @vms = @{ $aws_metadata->get_items( { item_type => 'ec2' } ) };
  my $found = 0;
  my ( $vm_label, $vm_url );
  foreach my $vm (@vms) {
    my ( $vm_uuid, $vm_label ) = each %{$vm};

    if ( $vm_label =~ /$pattern/i || $vm_uuid =~ /$pattern/i ) {

      # print table header
      unless ($found) {
        print "<tr align =\"center\" ><td><br><b>AWS search</b><br></td></tr>\n";
        print "<center><table class=\"lparsearch tablesorter\" align=\"center\" summary=\"Found VMs\">\n<thead>\n";
        print "<tr><th class=\"sortable\" align=\"center\"><b>EC2</b></th><th class=\"sortable\" align=\"center\"><b>UUID</b></th></tr>\n";
        print "</thead><tbody>\n";
      }

      $vm_url = AWSMenu::get_url( { type => 'ec2', ec2 => $vm_uuid } );
      print "<tr><td nowrap><a href=\"$vm_url\" class=\"backlink\">$vm_label</a></td><td nowrap>$vm_uuid</td></tr>\n";
      $found = 1;
    }
  }

  # print table footer
  if ($found) {
    print "</tbody></table></center><br><br>\n";
  }
}    ## sub aws_search

sub gcloud_search {
  if ( !defined $ENV{INPUTDIR} ) {
    warn( localtime() . ' : INPUTDIR undefined, probably have not read etc/lpar2rrd.cfg ' . __FILE__ . ':' . __LINE__ ) && return 0;
  }

  my $gcloud_acl = ( $ENV{HTTP_XORUX_APP} && $ENV{HTTP_XORUX_APP} eq 'Xormon' );
  my $gcloud_metadata = GCloudDataWrapperOOP->new( { acl_check => $gcloud_acl } );

  my @vms = @{ $gcloud_metadata->get_items( { item_type => 'compute' } ) };
  my $found = 0;
  my ( $vm_label, $vm_url );
  foreach my $vm (@vms) {
    my ( $vm_uuid, $vm_label ) = each %{$vm};

    if ( $vm_label =~ /$pattern/i || $vm_uuid =~ /$pattern/i ) {

      # print table header
      unless ($found) {
        print "<tr align =\"center\" ><td><br><b>Google Cloud search</b><br></td></tr>\n";
        print "<center><table class=\"lparsearch tablesorter\" align=\"center\" summary=\"Found VMs\">\n<thead>\n";
        print "<tr><th class=\"sortable\" align=\"center\"><b>Compute Engine</b></th><th class=\"sortable\" align=\"center\"><b>UUID</b></th></tr>\n";
        print "</thead><tbody>\n";
      }

      $vm_url = GCloudMenu::get_url( { type => 'compute', compute => $vm_uuid } );
      print "<tr><td nowrap><a href=\"$vm_url\" class=\"backlink\">$vm_label</a></td><td nowrap>$vm_uuid</td></tr>\n";
      $found = 1;
    }
  }

  # print table footer
  if ($found) {
    print "</tbody></table></center><br><br>\n";
  }
}    ## sub gcloud_search

sub azure_search {
  if ( !defined $ENV{INPUTDIR} ) {
    warn( localtime() . ' : INPUTDIR undefined, probably have not read etc/lpar2rrd.cfg ' . __FILE__ . ':' . __LINE__ ) && return 0;
  }

  my $azure_acl = ( $ENV{HTTP_XORUX_APP} && $ENV{HTTP_XORUX_APP} eq 'Xormon' );
  my $azure_metadata = AzureDataWrapperOOP->new( { acl_check => $azure_acl } );

  my @vms = @{ $azure_metadata->get_items( { item_type => 'vm' } ) };
  my $found = 0;
  my ( $vm_label, $vm_url );
  foreach my $vm (@vms) {
    my ( $vm_uuid, $vm_label ) = each %{$vm};

    if ( $vm_label =~ /$pattern/i || $vm_uuid =~ /$pattern/i ) {

      # print table header
      unless ($found) {
        print "<tr align =\"center\" ><td><br><b>Azure search</b><br></td></tr>\n";
        print "<center><table class=\"lparsearch tablesorter\" align=\"center\" summary=\"Found VMs\">\n<thead>\n";
        print "<tr><th class=\"sortable\" align=\"center\"><b>VM</b></th><th class=\"sortable\" align=\"center\"><b>UUID</b></th></tr>\n";
        print "</thead><tbody>\n";
      }

      $vm_url = AzureMenu::get_url( { type => 'vm', vm => $vm_uuid } );
      print "<tr><td nowrap><a href=\"$vm_url\" class=\"backlink\">$vm_label</a></td><td nowrap>$vm_uuid</td></tr>\n";
      $found = 1;
    }
  }

  # print table footer
  if ($found) {
    print "</tbody></table></center><br><br>\n";
  }
}    ## sub azure_search

sub kubernetes_search {
  if ( !defined $ENV{INPUTDIR} ) {
    warn( localtime() . ' : INPUTDIR undefined, probably have not read etc/lpar2rrd.cfg ' . __FILE__ . ':' . __LINE__ ) && return 0;
  }

  my $kubernetes_acl = ( $ENV{HTTP_XORUX_APP} && $ENV{HTTP_XORUX_APP} eq 'Xormon' );
  my $kubernetes_metadata = KubernetesDataWrapperOOP->new( { acl_check => $kubernetes_acl } );

  my @vms = @{ $kubernetes_metadata->get_items( { item_type => 'pod' } ) };
  my $found = 0;
  my ( $vm_label, $vm_url );
  foreach my $vm (@vms) {
    my ( $vm_uuid, $vm_label ) = each %{$vm};

    if ( $vm_label =~ /$pattern/i || $vm_uuid =~ /$pattern/i ) {

      # print table header
      unless ($found) {
        print "<tr align =\"center\" ><td><br><b>Kubernetes search</b><br></td></tr>\n";
        print "<center><table class=\"lparsearch tablesorter\" align=\"center\" summary=\"Found VMs\">\n<thead>\n";
        print "<tr><th class=\"sortable\" align=\"center\"><b>Pod</b></th><th class=\"sortable\" align=\"center\"><b>UUID</b></th></tr>\n";
        print "</thead><tbody>\n";
      }

      $vm_url = KubernetesMenu::get_url( { type => 'pod', pod => $vm_uuid } );
      print "<tr><td nowrap><a href=\"$vm_url\" class=\"backlink\">$vm_label</a></td><td nowrap>$vm_uuid</td></tr>\n";
      $found = 1;
    }
  }

  # print table footer
  if ($found) {
    print "</tbody></table></center><br><br>\n";
  }
}    ## sub kubernetes_search

sub openshift_search {
  if ( !defined $ENV{INPUTDIR} ) {
    warn( localtime() . ' : INPUTDIR undefined, probably have not read etc/lpar2rrd.cfg ' . __FILE__ . ':' . __LINE__ ) && return 0;
  }

  my $openshift_acl = ( $ENV{HTTP_XORUX_APP} && $ENV{HTTP_XORUX_APP} eq 'Xormon' );
  my $openshift_metadata = OpenshiftDataWrapperOOP->new( { acl_check => $openshift_acl } );

  my @vms = @{ $openshift_metadata->get_items( { item_type => 'pod' } ) };
  my $found = 0;
  my ( $vm_label, $vm_url );
  foreach my $vm (@vms) {
    my ( $vm_uuid, $vm_label ) = each %{$vm};

    if ( $vm_label =~ /$pattern/i || $vm_uuid =~ /$pattern/i ) {

      # print table header
      unless ($found) {
        print "<tr align =\"center\" ><td><br><b>Openshift search</b><br></td></tr>\n";
        print "<center><table class=\"lparsearch tablesorter\" align=\"center\" summary=\"Found VMs\">\n<thead>\n";
        print "<tr><th class=\"sortable\" align=\"center\"><b>Pod</b></th><th class=\"sortable\" align=\"center\"><b>UUID</b></th></tr>\n";
        print "</thead><tbody>\n";
      }

      $vm_url = OpenshiftMenu::get_url( { type => 'pod', pod => $vm_uuid } );
      print "<tr><td nowrap><a href=\"$vm_url\" class=\"backlink\">$vm_label</a></td><td nowrap>$vm_uuid</td></tr>\n";
      $found = 1;
    }
  }

  # print table footer
  if ($found) {
    print "</tbody></table></center><br><br>\n";
  }
}    ## sub openshift_search

sub nutanix_search {
  if ( !defined $ENV{INPUTDIR} ) {
    warn( localtime() . ' : INPUTDIR undefined, probably have not read etc/lpar2rrd.cfg ' . __FILE__ . ':' . __LINE__ ) && return 0;
  }

  my $nutanix_acl = ( $ENV{HTTP_XORUX_APP} && $ENV{HTTP_XORUX_APP} eq 'Xormon' );
  my $nutanix_metadata = NutanixDataWrapperOOP->new( { conf_labels => 1, conf_arch => 1, acl_check => $nutanix_acl } );

  my @vms = @{ $nutanix_metadata->get_items( { item_type => 'vm' } ) };
  my $found = 0;
  my ( $vm_label, $vm_url );
  foreach my $vm (@vms) {
    my ( $vm_uuid, $vm_label ) = each %{$vm};

    if ( !defined $vm_label ) {
      next;
    }

    if ( $vm_label =~ /$pattern/i || $vm_uuid =~ /$pattern/i ) {

      # print table header
      unless ($found) {
        print "<tr align =\"center\" ><td><br><b>Nutanix search</b><br></td></tr>\n";
        print "<center><table class=\"lparsearch tablesorter\" align=\"center\" summary=\"Found VMs\">\n<thead>\n";
        print "<tr><th class=\"sortable\" align=\"center\"><b>VM</b></th><th class=\"sortable\" align=\"center\"><b>UUID</b></th></tr>\n";
        print "</thead><tbody>\n";
      }

      $vm_url = NutanixMenu::get_url( { type => 'vm', vm => $vm_uuid } );
      print "<tr><td nowrap><a href=\"$vm_url\" class=\"backlink\">$vm_label</a></td><td nowrap>$vm_uuid</td></tr>\n";
      $found = 1;
    }
  }

  # print table footer
  if ($found) {
    print "</tbody></table></center><br><br>\n";
  }
}    ## sub nutanix_search

sub proxmox_search {
  if ( !defined $ENV{INPUTDIR} ) {
    warn( localtime() . ' : INPUTDIR undefined, probably have not read etc/lpar2rrd.cfg ' . __FILE__ . ':' . __LINE__ ) && return 0;
  }

  my $proxmox_acl = ( $ENV{HTTP_XORUX_APP} && $ENV{HTTP_XORUX_APP} eq 'Xormon' );
  my $proxmox_metadata = ProxmoxDataWrapperOOP->new( { conf_labels => 1, conf_arch => 1, acl_check => $proxmox_acl } );

  my @vms = @{ $proxmox_metadata->get_items( { item_type => 'vm' } ) };
  my $found = 0;
  my ( $vm_label, $vm_url );
  foreach my $vm (@vms) {
    my ( $vm_uuid, $vm_label ) = each %{$vm};

    if ( $vm_label =~ /$pattern/i || $vm_uuid =~ /$pattern/i ) {

      # print table header
      unless ($found) {
        print "<tr align =\"center\" ><td><br><b>Proxmox search</b><br></td></tr>\n";
        print "<center><table class=\"lparsearch tablesorter\" align=\"center\" summary=\"Found VMs\">\n<thead>\n";
        print "<tr><th class=\"sortable\" align=\"center\"><b>VM</b></th><th class=\"sortable\" align=\"center\"><b>UUID</b></th></tr>\n";
        print "</thead><tbody>\n";
      }

      $vm_url = ProxmoxMenu::get_url( { type => 'vm', vm => $vm_uuid } );
      print "<tr><td nowrap><a href=\"$vm_url\" class=\"backlink\">$vm_label</a></td><td nowrap>$vm_uuid</td></tr>\n";
      $found = 1;
    }
  }

  # print table footer
  if ($found) {
    print "</tbody></table></center><br><br>\n";
  }
}    ## sub proxmox_search

sub fusioncompute_search {
  if ( !defined $ENV{INPUTDIR} ) {
    warn( localtime() . ' : INPUTDIR undefined, probably have not read etc/lpar2rrd.cfg ' . __FILE__ . ':' . __LINE__ ) && return 0;
  }

  my $fc_acl = ( $ENV{HTTP_XORUX_APP} && $ENV{HTTP_XORUX_APP} eq 'Xormon' );
  my $fc_metadata = FusionComputeDataWrapperOOP->new( { conf_labels => 1, conf_arch => 1, acl_check => $fc_acl } );

  my @vms = @{ $fc_metadata->get_items( { item_type => 'vm' } ) };
  use Data::Dumper;
  my $found = 0;
  my ( $vm_label, $vm_url );
  foreach my $vm (@vms) {
    my ( $vm_uuid, $vm_label ) = each %{$vm};

    if ( $vm_label =~ /$pattern/i || $vm_uuid =~ /$pattern/i ) {

      # print table header
      unless ($found) {
        print "<tr align =\"center\" ><td><br><b>FusionCompute search</b><br></td></tr>\n";
        print "<center><table class=\"lparsearch tablesorter\" align=\"center\" summary=\"Found VMs\">\n<thead>\n";
        print "<tr><th class=\"sortable\" align=\"center\"><b>VM</b></th><th class=\"sortable\" align=\"center\"><b>UUID</b></th></tr>\n";
        print "</thead><tbody>\n";
      }

      $vm_url = FusionComputeMenu::get_url( { type => 'vm', vm => $vm_uuid } );
      print "<tr><td nowrap><a href=\"$vm_url\" class=\"backlink\">$vm_label</a></td><td nowrap>$vm_uuid</td></tr>\n";
      $found = 1;
    }
  }

  # print table footer
  if ($found) {
    print "</tbody></table></center><br><br>\n";
  }
}    ## sub fusioncompute_search

sub docker_search {
  if ( !defined $ENV{INPUTDIR} ) {
    warn( localtime() . ' : INPUTDIR undefined, probably have not read etc/lpar2rrd.cfg ' . __FILE__ . ':' . __LINE__ ) && return 0;
  }

  my $docker_acl = ( $ENV{HTTP_XORUX_APP} && $ENV{HTTP_XORUX_APP} eq 'Xormon' );
  my $docker_metadata = DockerDataWrapperOOP->new( { conf_labels => 1, conf_arch => 1, acl_check => $docker_acl } );

  my @containers = @{ $docker_metadata->get_items( { item_type => 'container' } ) };
  my $found = 0;
  foreach my $container (@containers) {
    my ( $container_uuid, $container_label ) = each %{$container};

    if ( $container_label =~ /$pattern/i || $container_uuid =~ /$pattern/i ) {

      # print table header
      unless ($found) {
        print "<tr align =\"center\" ><td><br><b>Docker search</b><br></td></tr>\n";
        print "<center><table class=\"lparsearch tablesorter\" align=\"center\" summary=\"Found Containers\">\n<thead>\n";
        print "<tr><th class=\"sortable\" align=\"center\"><b>Container</b></th><th class=\"sortable\" align=\"center\"><b>UUID</b></th></tr>\n";
        print "</thead><tbody>\n";
      }

      my $container_url = DockerMenu::get_url( { type => 'container', container => $container_uuid } );
      print "<tr><td nowrap><a href=\"$container_url\" class=\"backlink\">$container_label</a></td><td nowrap>$container_uuid</td></tr>\n";
      $found = 1;
    }
  }

  # print table footer
  if ($found) {
    print "</tbody></table></center><br><br>\n";
  }
}    ## sub docker_search

sub windows_search {
  if ( !defined $ENV{INPUTDIR} ) {
    error(" INPUTDIR undefined, probably have not read etc/lpar2rrd.cfg") && return 0;
  }
  my @windows_vms   = ();
  my $managed       = "";
  my $line_to_print = "";

  # find Hyperv VMs in menu.txt
  my @hyp_vms = grep { /^L:/ && ( ( split( ":", $_ ) )[8] =~ "H" ) } @menu_array;

  # print "\@hyp_vms @hyp_vms\n";

  foreach (@hyp_vms) {

    # L:ad.xorux.com:HVNODE01:61538264-853B-43A0-99F5-DCFE083864C0:hvlinux02:/lpar2rrd-cgi/detail.sh?host=HVNODE01&server=windows/domain_ad.xorux.com&lpar=61538264-853B-43A0-99F5-DCFE083864C0&item=lpar&entitle=0&gui=1&none=none:MSNET-HVCL::H
    ( undef, my $domain, my $server, my $vm_uuid, my $vm_name, undef, my $hyp_cluster ) = split ":", $_;

    # filtering
    next if !( $vm_name =~ /$pattern/i || $pattern eq "" );

    my $last_time = strftime( "%Y-%m-%d %H:%M", localtime( ( stat("$inputdir/data/windows/domain_$domain/hyperv_VMs/$vm_uuid.rrm") )[9] ) );

    push @windows_vms, "<tr><td nowrap align=\"left\">$domain</td><td nowrap><a href=\"?platform=hyperv&item=host&domain=$domain&name=$server\">$server</a></td><td nowrap><a href=\"?platform=hyperv&item=vm&cluster=$hyp_cluster&host=$server&name=$vm_name&id=$vm_uuid\">$vm_name</a></td><td nowrap align=\"leftt\">$last_time</td></tr>\n";
  }

  if ( scalar @windows_vms > 0 ) {    # print table
    print "<tr align =\"center\" ><td><br><b>WINDOWS Hyperv search</b><br></td></tr>\n";
    print "<center>\n";
    print "<tr><td><table class=\"lparsearch tablesorter\" align=\"center\" summary=\"LPAR search - profiles\">\n<thead>\n";

    print "<tr><th class=\"sortable\" align=\"center\"><B>Domain</B></th><th class=\"sortable\" align=\"center\"><B>Server</B></th><th align=\"center\" class=\"sortable\"><B>VM</B></th><th class=\"sortable\" align=\"center\"><B>Last update</B></th></tr>";
    print "</thead><tbody>\n";

    # print items
    foreach (@windows_vms) {
      print $_;
    }
    print "</tbody></table></td></tr><br>\n";
  }
  else {
    # print "<p>no VM found</p>\n";
  }
}

sub oraclevm_search {

  if ( !defined $ENV{INPUTDIR} ) {
    warn( localtime() . " : INPUTDIR undefined, probably have not read etc/lpar2rrd.cfg " . __FILE__ . ':' . __LINE__ ) && return 0;
  }

  my $oraclevm_acl = ( $ENV{HTTP_XORUX_APP} && $ENV{HTTP_XORUX_APP} eq 'Xormon' );
  my $oraclevm_metadata = OracleVmDataWrapperOOP->new( { acl_check => $oraclevm_acl } );

  my @vms                 = @{ $oraclevm_metadata->get_items( { item_type => 'vm' } ) };
  my $mapping_server_vm   = $oraclevm_metadata->get_conf_section('arch-vm_server');
  my $mapping_server_pool = $oraclevm_metadata->get_conf_section('arch-server_pool');
  my $found               = 0;
  my ( $vm_label, $vm_url );
  foreach my $vm_uuid (@vms) {
    foreach my $server ( keys %{$mapping_server_vm} ) {
      my $server_label = my $vm_label = my $server_url = my $server_pool_label = my $server_pool_url = '';
      if ( grep( /$vm_uuid/, @{ $mapping_server_vm->{$server} } ) ) {
        $server_label = $oraclevm_metadata->get_label( 'server', $server );
        $vm_label     = $oraclevm_metadata->get_label( 'vm',     $vm_uuid );
        $server_url = OracleVmMenu::get_url( { type => "server", server => $server } );
      }
      foreach my $server_pool ( sort keys %{$mapping_server_pool} ) {
        if ( grep( /$server/, @{ $mapping_server_pool->{$server_pool} } ) ) {
          $server_pool_label = $oraclevm_metadata->get_label( 'server_pool', $server_pool );
          $server_pool_url = OracleVmMenu::get_url( { type => "server_pool-aggr", server_pool => $server_pool } );
        }
      }
      if ( $vm_label =~ /$pattern/i || $vm_uuid =~ /$pattern/i ) {

        # print table header
        unless ($found) {
          print "<tr align =\"center\" ><td><br><b>OracleVM search</b><br></td></tr>\n";
          print "<center><table class=\"lparsearch tablesorter\" align=\"center\" summary=\"Found VMs\">\n<thead>\n";
          print "<tr><th class=\"sortable\" align=\"center\"><b>VM</b></th><th class=\"sortable\" align=\"center\"><b>UUID</b></th><th class=\"sortable\" align=\"center\"><b>SERVER</b></th><th class=\"sortable\" align=\"center\"><b>SERVER_POOL</b></th></tr>\n";
          print "</thead><tbody>\n";
        }

        $vm_url = OracleVmMenu::get_url( { type => 'vm', vm => $vm_uuid } );
        print "<tr><td nowrap><a href=\"$vm_url\" class=\"backlink\">$vm_label</a></td><td nowrap>$vm_uuid</td><td nowrap><a href=\"$server_url\" class=\"backlink\">$server_label</a></td><td nowrap><a href=\"$server_pool_url\" class=\"backlink\">$server_pool_label</a></td></tr>\n";
        $found = 1;
      }
    }
  }

  # print table footer
  if ($found) {
    print "</tbody></table></center><br><br>\n";
  }

}

sub get_date {
  my $inputdir = shift;
  my $line_org = shift;
  my $date     = "";

  my $filesize = -s "$inputdir/data/$line_org";
  if ( not defined $filesize )  { $filesize = 0; }
  if ( $line_org =~ /\.json$/ ) { $filesize = 0; }    # this file is not RRDTOOL file
  if ( $line_org =~ /\.txt$/ )  { $filesize = 0; }    # this file is not RRDTOOL file
  if ( $line_org =~ /\.cfg$/ )  { $filesize = 0; }    # this file is not RRDTOOL file

  if ( $filesize > 0 ) {

    # lpars not being managed by HMC can have 0 size, exclude them here
    if ( -f "$inputdir/data/$line_org" ) {

      # print STDERR "663 $inputdir/data/$line_org\n";
      my $last_rec = "";
      eval {
        RRDp::cmd qq(last "$inputdir/data/$line_org" );
        $last_rec = RRDp::read;
      };
      if ($@) {
        error( "$@ " . __FILE__ . ":" . __LINE__ );
        return 0;
      }

      chomp($$last_rec);

      #$date = strftime "%d.%m.%y %H:%M:%S", localtime($$last_rec);
      return $$last_rec;
    }
    else {
      # guess .rrm for profiles
      $line_org .= ".rrm";
      if ( !-f "$inputdir/data/$line_org" ) {
        $line_org =~ s/rrm$/rrh/;
      }
      if ( -f "$inputdir/data/$line_org" ) {
        RRDp::cmd qq(last "$inputdir/data/$line_org" );
        my $last_rec = RRDp::read;
        chomp($$last_rec);

        #$date = strftime "%d.%m.%y %H:%M:%S", localtime($$last_rec);
        return $$last_rec;
      }
    }
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
