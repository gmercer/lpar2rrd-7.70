use warnings;
no warnings "deprecated";
use strict;
use Date::Parse;
use Data::Dumper;
use RRDp;

#use File::Glob ':glob';
use CGI::Carp qw(fatalsToBrowser);
use JSON;
use Xorux_lib qw(read_json write_json uuid_big_endian_format parse_url_params);
use Env qw(QUERY_STRING);

use XenServerDataWrapper;
use XenServerDataWrapperOOP;
use XenServerMenu;
use NutanixMenu;
use NutanixDataWrapper;
use NutanixDataWrapperOOP;
use AWSMenu;
use AWSDataWrapper;
use GCloudMenu;
use GCloudDataWrapper;
use AzureMenu;
use AzureDataWrapper;
use KubernetesMenu;
use KubernetesDataWrapper;
use KubernetesDataWrapperOOP;
use OpenshiftMenu;
use OpenshiftDataWrapper;
use OpenshiftDataWrapperOOP;
use CloudstackMenu;
use CloudstackDataWrapper;
use ProxmoxMenu;
use ProxmoxDataWrapper;
use DockerMenu;
use DockerDataWrapper;
use FusionComputeMenu;
use FusionComputeDataWrapper;
use OVirtDataWrapper;
use OVirtMenu;
use PowerDataWrapper;
use PowerMenu;
use VmwareDataWrapper;
use VmwareMenu;
use OracleDBDataWrapper;
use OracleDBMenu;
use PostgresDataWrapper;
use PostgresMenu;
use SQLServerDataWrapper;
use SQLServerMenu;
use Db2DataWrapper;
use Db2Menu;
use OracleVmDataWrapperOOP;
use OracleVmDataWrapper;
use OracleVmMenu;
use PowercmcMenu;
use PowercmcDataWrapper;
use WindowsMenu;
use SolarisMenu;
use SolarisDataWrapper;
use HostCfg;
use Overview;
use XoruxEdition;

use File::Glob qw(bsd_glob GLOB_TILDE);

my $xormon = 0;
if ( exists $ENV{HTTP_XORUX_APP} && $ENV{HTTP_XORUX_APP} eq "Xormon" ) {
  require SQLiteDataWrapper;
  $xormon = 1;
}

my $power_new    = 0;
my $prediction   = "prediction";
my $DEBUG        = $ENV{DEBUG};
my $errlog       = $ENV{ERRLOG};
my $xport        = $ENV{EXPORT_TO_CSV};
my $webdir       = $ENV{WEBDIR};
my $lpm_env      = $ENV{LPM};
my $basedir      = $ENV{INPUTDIR};
my $wrkdir       = $basedir . "/data";
my $detail_graph = "detail-graph";
my $tmpdir       = "$basedir/tmp";
my $rest_api     = 0;
my $bindir       = $ENV{BINDIR};
my $sep          = ";";

my $agents_uuid_file = "$wrkdir/Linux--unknown/no_hmc/linux_uuid_name.json";

if ( defined $ENV{TMPDIR_LPAR} ) {
  $tmpdir = $ENV{TMPDIR_LPAR};
}

if ( defined $ENV{NMON_EXTERNAL} ) {
  $wrkdir .= $ENV{NMON_EXTERNAL};
  $detail_graph = "detail-graph-external";
}
my $cpu_max_filter = 100;    # max 10k peak in % is allowed (in fact it cann by higher than 1k now when 1 logical CPU == 0.1 entitlement
if ( defined $ENV{CPU_MAX_FILTER} ) {
  $cpu_max_filter = $ENV{CPU_MAX_FILTER};
}

my $base          = 0;
my $detail_yes    = 1;
my $detail_no     = 0;
my $gui           = 0;
my $NMON          = "--NMON--";
my $WPAR          = "--WPAR--";
my $AS400         = "--AS400--";
my $false_picture = "";            # if you do not want to show picture but some notice
my @lpar2volumes;                  # KZ: here will be stored uuids of volumes from stor2rrd which belongs under lpar

my $tab_exe = "";                  # for preparing tab executive string
my $vmware  = 0;
my $item;
my %vm_uuid_names = ();            # using for topten vmware

# set unbuffered stdout
$| = 1;

my $csv = 0;

# print STDERR "25 detail-cgi.pl -- $QUERY_STRING\n"; #if $DEBUG == 2;
( my $pattern, my $entitle, my $sort_order, my $referer, my $item_a, my $period ) = split( /&/, $QUERY_STRING );

### solution of possible CSV export to LPAR/VM TOP
# examples:
# /lpar2rrd-cgi/top10_csv.sh?LPAR=$pattern&host=CSV&type=POWER&table=topten&item=name_item&period=1|2|3|4
if ( defined $entitle && $entitle eq "host=CSV" ) {
  $csv = 1;
  $pattern    =~ s/LPAR=//g;
  $period     =~ s/period=//g;
  $referer    =~ s/table=//g;
  $item_a     =~ s/item=//g;
  $sort_order =~ s/type=//g;
  $item = $referer;
  my $server_url_csv = urldecode("$pattern");
  print_topten_to_csv( $sort_order, $item, $item_a, $period, $server_url_csv );
}

#/lpar2rrd-cgi/top10_csv.sh?SERVER=$server&HMC=$host&LPAR=$lpar&host=CSV_multi&item=aix_multipath\" title=\"MULTIPATH CSV\"><img src=\"css/images/csv.gif\"></a>";
if ( defined $referer && $referer =~ /host=CSV_multi|host=CSV_filesystem/ ) {
  $csv = 1;
  $pattern    =~ s/SERVER=//g;
  $entitle    =~ s/HMC=//g;
  $sort_order =~ s/LPAR=//g;
  $item_a     =~ s/item=//g;

  #$item = $referer;
  my $lpar_url_csv = urlencode("$sort_order");
  if ( $item_a eq "aix_multipath" ) {
    print_aix_multipath_to_csv( $pattern, $entitle, $lpar_url_csv, $item_a );
  }
  elsif ( $item_a eq "filesystem" ) {
    $lpar_url_csv = urldecode("$lpar_url_csv");
    print_fs_to_csv( $pattern, $entitle, $lpar_url_csv, $item_a );
  }
}

# CGI-BIN HTML header
print "Content-type: text/html\n\n";

open( OUT, ">> $errlog" ) if $DEBUG == 2;

#foreach $key (sort keys(%ENV)) {
#   print "$key = $ENV{$key}<p>";
#}
#window.open(href, windowname, 'width=1200,height=450,scrollbars=yes');

# get QUERY_STRING
use Env qw(QUERY_STRING);
timing_debug($QUERY_STRING);

# print STDERR "111 ".localtime()." detail_cgi \$QUERY_STRING $QUERY_STRING\n";

sub urlencode {
  my $s = shift;
  $s =~ s/([^a-zA-Z0-9!~*()'\''-])/sprintf("%%%02X", ord($1))/ge;
  return $s;
}

sub urldecode {
  my $s = shift;
  if ($s) {
    $s =~ s/\%([A-Fa-f0-9]{2})/pack('C', hex($1))/seg;
  }
  return $s;
}

my @menu_vmware = ();

# read tmp/menu_vmware.txt
sub read_menu_vmware {
  my $menu_ref = shift;
  open( FF, "<$tmpdir/menu_vmware.txt" ) || error( "can't open $tmpdir!menu.txt: $! :" . __FILE__ . ":" . __LINE__ ) && return 0;
  @$menu_ref = (<FF>);
  close(FF);
  return;
}

my $buffer;

if ( defined $ENV{'REQUEST_METHOD'} ) {
  if ( lc $ENV{'REQUEST_METHOD'} eq "post" ) {
    read( STDIN, $buffer, $ENV{'CONTENT_LENGTH'} );
  }
  else {
    $buffer = $ENV{'QUERY_STRING'};
  }
}

# hash containing URL parameters. Use like this: $params{server}
my %params = %{ Xorux_lib::parse_url_params($buffer) };

if ( exists $ENV{HTTP_XORUX_APP} && $ENV{HTTP_XORUX_APP} eq 'Xormon' && defined $params{type} ) {

  # print STDERR "ATT XORMON\n";
  my $url_old;
  my %url_params_new;

  #print STDERR"\n==========================================\n";
  #print STDERR Dumper \%params;
  #print STDERR"\n==========================================\n";
  foreach my $parameter ( keys %params ) {
    $url_params_new{$parameter} = $params{$parameter};
  }

  if ( defined $params{platform} ) {
    if ( $params{platform} eq "Power" ) {
      my ( $SERV, $CONF ) = PowerDataWrapper::init();
      $url_old = PowerMenu::url_new_to_old( \%url_params_new );
    }
    elsif ( $params{platform} eq "VMware" || $params{platform} eq "Vmware" ) {

      # print STDERR ("150 detail-cgi.pl platform VMware");
      $vmware  = 1;
      $url_old = VmwareMenu::url_new_to_old( \%url_params_new );
    }
    elsif ( $params{platform} eq "Linux" ) {

      # $QUERY_STRING host=no_hmc&server=Linux--unknown&lpar=internal.int.xorux.com&item=lpar&entitle=0&gui=1&none=none&_=1587043782431
      $url_old = VmwareMenu::url_new_to_old( \%url_params_new );
    }
    elsif ( $params{platform} eq "Windows" ) {

      # $QUERY_STRING platform=Windows&type=pool&id=ad.xorux.com_server_DC
      # $QUERY_STRING host=DC&server=windows/domain_ad.xorux.com&lpar=pool&item=pool&entitle=0&gui=1&none=none&_=1611133576322
      # $hyperv = 1;
      $url_old = WindowsMenu::url_new_to_old( \%url_params_new );
    }
    elsif ( $params{platform} eq "Solaris" ) {
      $url_old = SolarisMenu::url_new_to_old( \%url_params_new );
    }
    else {
      # add a branch for other virtualization if necessary
      # uncomment next line when debugging
      # error ("not supported platform ".$params{platform}.__FILE__.":".__LINE__);
    }
  }
  foreach my $par ( keys %{ $url_old->{params} } ) {
    $params{$par} = $url_old->{params}{$par};

    #print STDERR"detail-cgi.pl(line206)-$params{$par}\n";
  }

}

# assign values from %params for back compatibility
my ( $host, $server, $lpar, $sunix, $eunix );
( $host, $server, $lpar, $item, $entitle, $gui, $sunix, $eunix ) = ( $params{host}, $params{server}, $params{lpar}, $params{item}, $params{entitle}, $params{gui}, $params{sunix}, $params{eunix} );

# my $sunix, my $eunix used only for VMWARE datastore top

# initialize if only custom URL params are used (because the older code here depends on these variables)
$host   = '' if not defined $params{host};
$server = '' if not defined $params{server};
$lpar   = '' if not defined $params{lpar};
$item   = '' if not defined $params{item};

$gui     = '' if not defined $gui;
$entitle = '' if not defined $entitle;
$sunix   = '' if not defined $sunix;
$eunix   = '' if not defined $eunix;

if ( $host eq '' || $server eq '' || $lpar eq '' ) {

  # error( "One of passed args: hmc/server/lpar is null ($QUERY_STRING) " . __FILE__ . ":" . __LINE__ );
  # could be in oVirt
  # exit(1);
}

# print STDERR "233 $host, $server, $lpar, $item, $entitle, $sunix, $eunix\n";

if ( is_host_rest($host) ) {
  $rest_api = 1;
}
else {
  $rest_api = 0;
}

# POWER NEW
if ($power_new) {

  if ( $params{type} eq "vm" ) {
    print_power_new_lpars();
  }
  elsif ( $params{type} eq "pool" ) {
    print_power_new_pool();
  }
  elsif ( $params{type} eq "interface" ) {
    print_power_adapters( $params{host}, $params{server}, $params{lpar}, $params{item}, 0 );
  }
  elsif ( $params{type} eq "another_type" ) {
    print "TEST\n";
  }
  else {
    print "Not implemented for New Power \n";
    print Dumper \%params;
  }

  exit(0);
}
if ( $params{source} ) {
  print_html_file("$webdir/$params{source}");
}

sub print_html_file {
  my $file = shift;
  open( my $in, "<", $file ) || error( "Cannot read $file " . __FILE__ . ":" . __LINE__ . "\n" ) && return -1;
  my @lines = <$in>;
  close($in);

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

my $bmax = 10;

#if ( $entitle =~ m/MAX/ ) {
#  $bmax = $entitle;
#}
if ( defined $params{MAX} ) {
  $bmax = $params{MAX};
}

# if == 1 then restrict views (only CPU and mem)
if ( $entitle eq '' || isdigit($entitle) == 0 ) {
  $entitle = 0;    # when any problem then allow it!
}
my $host_url   = urlencode("$host");
my $server_url = urlencode("$server");
my $lpar_url   = urlencode("$lpar");

#print STDERR "host: ";print STDERR Dumper $host;print STDERR "\nhost_url: ";print STDERR Dumper $host_url;
#print STDERR "server: ";print STDERR Dumper $server;print STDERR "\nserver_url: ";print STDERR Dumper $server_url;
#print STDERR "lpar: ";print STDERR Dumper $lpar;print STDERR "\nlpar_url: ";print STDERR Dumper $lpar_url;

#$lpar =~ s/\+/ /g;
$lpar =~ s/ \[.*\]//g;             # remove alias info
my $lpar_slash = $lpar;
$lpar_slash =~ s/\//\&\&1/g;       # replace for "/"
$lpar_slash =~ s/--WPAR--/\//g;    # WPAR delimiter replace

if ( $gui =~ m/gui=/ ) {
  $gui =~ s/gui=//;
}
else {
  $gui = 0;
}

###   if VMWARE
# my $vmware = 0;
if ( !$vmware && $host ne "" ) {
  my $pth = "$wrkdir/*/$host/vmware.txt";
  $pth =~ s/ /\\ /g;
  my $no_name = "";
  my @files   = (<$pth$no_name>);    # unsorted, workaround for space in names
  $vmware = 1 if ( defined $files[0] && ( $files[0] ne "" ) && index( $files[0], "vmware.txt" ) != -1 );
}
my $tab_type = "tabhmc";
if ($vmware) {
  $tab_type           = "";
  $params{platform}   = "VMware";
  $params{d_platform} = "VMware";
}

my $hyperv = 0;
if ( !$vmware ) {    # then try if hyperv
                     # print STDERR "188 detail-cgi.pl ,$wrkdir / $server / $host /hyperv.txt,\n";
  $hyperv = 1 if ( -f "$wrkdir/windows/$host/$server/hyperv.txt" );
  $hyperv = 1 if $server =~ /^windows/;
  if ($hyperv) {
    $tab_type = "";
    if ( $server !~ /^windows/ ) {
      $server     = "windows/$server";
      $server_url = "windows/$server_url";
    }
  }
}

# print STDERR "350 \$hyperv $hyperv\n";
my $hitachi = 0;
if ( $server =~ /^Hitachi$/ ) {
  $hitachi = 1;
}

# flags for platforms that use the new URL format
my $xenserver = my $nutanix = my $aws = my $gcloud = my $azure = my $kubernetes = my $openshift = my $cloudstack = my $proxmox = my $docker = my $fusioncompute = my $ovirt = my $power = my $oracledb = my $sqlserver = my $postgres = my $db2 = my $orvm = my $solaris = my $powercmc = 0;

if ( defined $params{platform} ) {

  # set other flags=0 as an ad-hoc workaround to prevent evaluation of branches for older platform implementations
  $vmware = $hyperv = $hitachi = $power = $orvm = 0;
  if ( $params{platform} =~ m/^XenServer$/ ) {
    $xenserver = 1;
    $item      = 'xenserver';
  }
  elsif ( $params{platform} =~ m/^Nutanix$/ ) {
    $nutanix = 1;
    $item    = 'nutanix';
  }
  elsif ( $params{platform} =~ m/^FusionCompute$/ ) {
    $fusioncompute = 1;
    $item          = 'fusioncompute';
  }
  elsif ( $params{platform} =~ m/^AWS$/ ) {
    $aws  = 1;
    $item = 'aws';
  }
  elsif ( $params{platform} =~ m/^GCloud$/ ) {
    $gcloud = 1;
    $item   = 'gcloud';
  }
  elsif ( $params{platform} =~ m/^Azure$/ ) {
    $azure = 1;
    $item  = 'azure';
  }
  elsif ( $params{platform} =~ m/^Kubernetes$/ ) {
    $kubernetes = 1;
    $item       = 'kubernetes';
  }
  elsif ( $params{platform} =~ m/^Openshift$/ ) {
    $openshift = 1;
    $item      = 'openshift';
  }
  elsif ( $params{platform} =~ m/^Cloudstack$/ ) {
    $cloudstack = 1;
    $item       = 'cloudstack';
  }
  elsif ( $params{platform} =~ m/^Proxmox$/ ) {
    $proxmox = 1;
    $item    = 'proxmox';
  }
  elsif ( $params{platform} =~ m/^Docker$/ ) {
    $docker = 1;
    $item   = 'docker';
  }
  elsif ( $params{platform} =~ m/^oVirt$/ ) {
    $ovirt = 1;
    $item  = 'ovirt';
  }
  elsif ( $params{platform} =~ m/^PowerCMC/ ) {
    $powercmc = 1;
    $item     = 'powercmc';
  }
  elsif ( $params{platform} =~ m/Power/ ) {
    $power = 1;

    # $item = 'power';
  }
  elsif ( $params{platform} =~ m/VMware/ ) {
    $vmware = 1;
  }
  elsif ( $params{platform} =~ m/Windows/ ) {
    $hyperv = 1;
  }
  elsif ( $params{platform} =~ m/^OracleDB$/ ) {
    $oracledb = 1;
    $item     = 'oracledb';
  }
  elsif ( $params{platform} =~ m/^PostgreSQL$/ ) {
    $postgres = 1;
    $item     = 'postgres';
  }
  elsif ( $params{platform} =~ m/^DB2$/ ) {
    $db2  = 1;
    $item = 'db2';
  }
  elsif ( $params{platform} =~ m/^SQLServer$/ ) {
    $sqlserver = 1;
    $item      = 'sqlserver';
  }
  elsif ( $params{platform} =~ m/OracleVM/ ) {
    $orvm = 1;
    $item = 'oraclevm';
  }
  elsif ( $params{platform} =~ m/Solaris/ ) {
    $solaris = 1;
    if ( $params{item} =~ m/sol_ldom_xor/ ) {
      $item = 'sol_ldom_xor';
    }
    elsif ( $params{item} =~ m/sol_cdom_xor/ ) {
      $item = 'sol_cdom_xor';
    }
    elsif ( $params{item} =~ m/sol_zone_c_xor/ ) {
      $item = 'sol_zone_c_xor';
    }
    elsif ( $params{item} =~ m/sol_zone_l_xor10/ ) {
      $item = 'sol_zone_l_xor10';
    }
    elsif ( $params{item} =~ m/sol_zone_l_xor11/ ) {
      $item = 'sol_zone_l_xor11';
    }
    elsif ( $params{item} =~ m/sol_ldom_agg_c/ ) {
      $item = 'cpuagg-sol';
    }
  }
}

# print STDERR "363 detail_cgi \$QUERY_STRING $QUERY_STRING \$vmware $vmware \$hyperv $hyperv \$server $server \$item $item\n";

# notice to upper right corner - VMs aggregated
my $question_mark = "<div id=\"hiw\"><a href=\"http://www.lpar2rrd.com/VMware-GHz-vrs-real_CPU.htm\" target=\"_blank\" class=\"nowrap\"><img src=\"css/images/help-browser.gif\" alt=\"How it works?\" title=\"How it works?\"></img></a></div>";

my $wpar = 0;
if ( $lpar =~ m/$WPAR/ ) {
  $wpar = 1;
}

# print HTML header

# find out $type_sam [m/d/h]
my $type_sam      = type_sam( $host, $server, $lpar, 0, $lpar_slash );
my $type_sam_year = type_sam( $host, $server, $lpar, 0, $lpar_slash );
my $upper         = -1;

##############################
### Solaris CDOM/LDOM/ZONE
##############################
if ( $item =~ m/sol\d+-*/ ) {
  if ( $item =~ /sol11-all/ ) { next; }
  if ( $item =~ /sol10-*/ ) {
    print_solaris10( $host_url, $server_url, $lpar_url, $item, $type_sam, $entitle, $upper );
  }
  elsif ( $item =~ /sol11-*/ ) {
    print_solaris( $host_url, $server_url, $lpar_url, $item, $type_sam, $entitle, $upper );
  }
  exit(0);
}
if ( $item =~ m/sol-ldom|sol_ldom_xor|sol_cdom_xor/ ) {
  print_solaris_ldom( $host_url, $server_url, $lpar_url, $item, $type_sam, $entitle, $upper );
}
if ( $item =~ m/sol_zone_c_xor|sol_zone_l_xor11/ ) {
  print_solaris( $host_url, $server_url, $lpar_url, $item, $type_sam, $entitle, $upper );
}
if ( $item =~ /sol_zone_l_xor10/ ) {
  print_solaris10( $host_url, $server_url, $lpar_url, $item, $type_sam, $entitle, $upper );
}

#################################################################################################

if ( $item =~ m/^codused$/ ) {

  # CoD
  print_cod( $host_url, $server_url, $lpar_url, $item, $type_sam, $entitle, $upper );
  exit(0);
}

if ( $item eq "cpuagg-sol" ) {
  print_ldom_agg( $host_url, $server_url, $lpar_url, $item, $entitle );
  exit(0);
}

if ( $item =~ m/^data_check_div/ ) {
  print_data_check_div();
  exit(0);
}

if ( $item =~ m/^pagingagg$/ ) {

  # Epaging aggregated
  print_pagingagg( $host_url, $server_url, $lpar_url, $item, $type_sam, $bmax, $upper );
  exit(0);
}

if ( $item =~ m/^pool$/ ) {

  # Server pool
  if ($hyperv) {
    my $tab_num = 1;

    # print STDERR "388 $host_url, $server_url, $lpar_url, $item, $type_sam, $tab_num\n";
    print_hyperv_pool_tabs( $host_url, $server_url, $lpar_url, $item, $type_sam, $tab_num );
    print_hyperv_pool_html( $host_url, $server_url, $lpar_url, $item, $type_sam, $tab_num );
  }
  else {
    print_pool( $host_url, $server_url, $lpar_url, $item, $type_sam );
  }
  exit(0);
}

if ( $item =~ m/^physdisk$/ ) {

  my $tab_num = 1;

  # print STDERR "388 $host_url, $server_url, $lpar_url, $item, $type_sam, $tab_num\n";
  print_phys_disk_tabs( $host_url, $server_url, $lpar_url, $item, $type_sam, $tab_num );
  print_phys_disk_html( $host_url, $server_url, $lpar_url, $item, $type_sam, $tab_num );
  exit(0);

}

if ( $item =~ m/^s2dvolume$/ ) {

  my $tab_num = 1;
  print_s2dvol_tabs( $host_url, $server_url, $lpar_url, $item, $type_sam, $tab_num );
  print_s2dvol_html( $host_url, $server_url, $lpar_url, $item, $type_sam, $tab_num );
  exit(0);

}

if ( $item =~ m/^shpool$/ ) {

  # Server pool
  print_shpool( $host_url, $server_url, $lpar_url, $item, $type_sam );
  exit(0);
}

if ( $item =~ m/^hea/ ) {
  print_hea( $host_url, $server_url, $lpar_url, $item, $entitle );
  exit(0);
}

if ( $item =~ m/^memalloc/ ) {
  print_memory( $host_url, $server_url, $lpar_url, $item, $entitle );
  exit(0);
}

if ( $item =~ m/^hmctotals/ ) {    #formerly in install-html.sh print_multipool
  print_hmctotals( $host_url, $server_url, $lpar_url, $item, $entitle );
  exit(0);
}

# differentiate based on $host (power, vmware, xenserver)
if ( $item =~ m/^custom/ ) {    # formerly in custom.pl & install-html.sh
  if ( $host =~ m/^XENVM|XenServer/ ) {
    print_custom_xenserver( $host_url, $server_url, $lpar_url, $item, $entitle );
  }
  elsif ( $host =~ m/^NUTANIXVM|Nutanix/ ) {
    print_custom_nutanix( $host_url, $server_url, $lpar_url, $item, $entitle );
  }
  elsif ( $host =~ m/^PROXMOXVM|Proxmox/ ) {
    print_custom_proxmox( $host_url, $server_url, $lpar_url, $item, $entitle );
  }
  elsif ( $host =~ m/^KUBERNETESNODE|KubernetesNode/ ) {
    print_custom_kubernetes( $host_url, $server_url, $lpar_url, $item, $entitle );
  }
  elsif ( $host =~ m/^KUBERNETESNAMESPACE|KubernetesNamespace/ ) {
    print_custom_kubernetes_namespace( $host_url, $server_url, $lpar_url, $item, $entitle );
  }
  elsif ( $host =~ m/^OPENSHIFTNODE|OpenshiftNode/ ) {
    print_custom_openshift( $host_url, $server_url, $lpar_url, $item, $entitle );
  }
  elsif ( $host =~ m/^OPENSHIFTPROJECT|OPENSHIFTNAMESPACE|OpenshiftProject/ ) {
    print_custom_openshift_namespace( $host_url, $server_url, $lpar_url, $item, $entitle );
  }
  elsif ( $host =~ m/^FUSIONCOMPUTEVM|FusionCompute/ ) {
    print_custom_fusioncompute( $host_url, $server_url, $lpar_url, $item, $entitle );
  }
  elsif ( $host =~ m/^OVIRTVM|oVirt/ ) {
    print_custom_ovirt( $host_url, $server_url, $lpar_url, $item, $entitle );
  }
  elsif ( $host =~ m/^SOLARIS|Solaris/ ) {
    print_custom_solaris( $host_url, $server_url, $lpar_url, $item, $entitle );
  }
  elsif ( $host =~ m/^HYPERVM|Hyperv/ ) {
    print_custom_hyperv( $host_url, $server_url, $lpar_url, $item, $entitle );
  }
  elsif ( $host =~ m/^LINUX|Linux/ ) {
    print_custom_linux( $host_url, $server_url, $lpar_url, $item, $entitle );
  }
  elsif ( $host =~ m/^ESXI/ ) {
    print_custom_esxi( $host_url, $server_url, $lpar_url, $item, $entitle );
  }
  elsif ( $host =~ m/^ORVM|OracleVM/ ) {
    print_custom_orvm( $host_url, $server_url, $lpar_url, $item, $entitle );
  }
  elsif ( $host =~ m/^ODB|OracleDB/ ) {
    print_custom_oracledb( $host_url, $server_url, $lpar_url, $item, $entitle );
  }
  else {
    print_custom( $host_url, $server_url, $lpar_url, $item, $entitle );
  }
  exit(0);
}

if ( $item =~ m/^view/ ) {
  print_view( $host_url, $server_url, $lpar_url, $item, $entitle );
  exit(0);
}
if ( $item =~ m/^topten$/ ) {
  print_topten_all( $host_url, $server_url, $lpar_url, $item, $entitle );
  exit(0);
}

if ( $item =~ m/^topten_vm$/ ) {
  print_topten_vm( $host_url, $server_url, $lpar_url, $item, $entitle );
  exit(0);
}

if ( $item =~ m/^topten_hyperv$/ ) {
  print_topten_hyperv( $host_url, $server_url, $lpar_url, $item, $entitle );
  exit(0);
}

if ( $item =~ m/^data_check/ ) {
  print_data_check( $host_url, $server_url, $lpar_url, $item, $entitle );
  exit(0);
}
if ( $item eq "servers" ) {
  print_data_servers( $host_url, $server_url, $lpar_url, $item, $entitle );
  exit(0);
}
if ( $item eq "serversvm" ) {
  print_data_serversvm( $host_url, $server_url, $lpar_url, $item, $entitle );
  exit(0);
}
if ( $item =~ m/^vmdisk/ ) {
  print_vmw_disk( $host_url, $server_url, $lpar_url, $item, $entitle );
  exit(0);
}
if ( $item =~ m/^vmnet/ ) {
  print_vmw_disk( $host_url, $server_url, $lpar_url, $item, $entitle );
  exit(0);
}
if ( $item =~ m/^cluster/ ) {
  print_cluster( $host_url, $server_url, $lpar_url, $item, $entitle );
  exit(0);
}
if ( $item =~ m/^resourcepool/ ) {
  print_resourcepool( $host_url, $server_url, $lpar_url, $item, $entitle );
  exit(0);
}
if ( $item =~ m/^datastore/ ) {
  print_datastore( $host_url, $server_url, $lpar_url, $item, $entitle );
  exit(0);
}
if ( $item =~ m/^dstr-table-top/ ) {
  print_datastore_table_top();
  exit(0);
}
if ( $item =~ m/^dstr-top/ ) {
  print_datastore_top( $sunix, $eunix );
  exit(0);
}
if ( $item =~ m/^(hitachi-lan|hitachi-san)$/ ) {
  print_hitachi_adapters( $host_url, $server_url, $lpar_url, $item, $entitle );
  exit(0);
}

if ( $item =~ m/^(hitachi-lan-totals|hitachi-san-totals)/ ) {
  print_hitachi_adapters_totals( $host_url, $server_url, $lpar_url, $item, $entitle );
  exit(0);
}

if ( $item =~ m/(power_lan|power_san|power_sas|power_sri|power_hea)/ && !( $lpar =~ m/totals/ ) ) {
  print_power_adapters( $host_url, $server_url, $lpar_url, $item, $entitle );
  exit(0);
}

if ( $item =~ m/(power_lan|power_san|power_sas|power_sri|power_hea)/ && ( $lpar =~ m/totals/ ) ) {
  print_power_adapters_agg( $host_url, $server_url, $lpar_url, $item, $entitle );
  exit(0);
}

if ( $item =~ m/^hdt_data/ || $item =~ m/^hdt_io/ ) {
  print_hyperv_disk_total( $host_url, $server_url, $lpar_url, $item, $entitle );
  exit(0);
}

if ( $item =~ m/^lfd/ || $item =~ m/^csv/ ) {
  print_hyperv_disk_lfd( $host_url, $server_url, $lpar_url, $item, $entitle );
  exit(0);
}

if ( $item =~ m/power-overview-global/ ) {
  print_power_overview( \%params );
  exit(0);
}

if ( 0 && $item =~ m/power-total/ ) {
  print_power_total_servers( "all", "all", "none", $item, $entitle );
  exit(0);
}

#if ( $item =~ m/power-overview-server/){
#  print_view( $host_url, $server_url, $lpar_url, $item, $entitle );
#  exit(0);
#}

my $tab_number;
my @item_agent      = ();
my @item_agent_tab  = ();
my $item_agent_indx = 0;
my $os_agent        = 0;
my $nmon_agent      = 0;
my $iops            = "IOPS";

# VMWARE
if ($vmware) {

  # TABs
  # basic CPU
  $tab_number = 0;
  print "\n<div  id=\"tabs\"> <ul>\n";

  # my $cpu = 0;

  # if ( -f "$wrkdir/vmware_VMs/$lpar_slash.rrm") {
  $tab_number++;

  # $cpu = $tab_number;
  print "  <li class=\"\"><a href=\"#tabs-$tab_number\">CPU</a></li>\n";
  $upper = rrd_upper( $wrkdir, "vmware_VMs", "", $lpar, $type_sam, $type_sam_year, $item, $lpar_slash );

  # }
  $tab_number++;
  print "  <li class=\"\"><a href=\"#tabs-$tab_number\">CPU GHz</a></li>\n";
  $tab_number++;
  print "  <li class=\"\"><a href=\"#tabs-$tab_number\">MEM</a></li>\n";

  # if there are not data (no counters), do not show tabs
  my $is_dusage = test_metric_in_rrd( "vmware_VMs", "", "$lpar.rrm", $item, "Disk_usage" );
  my $is_dread  = test_metric_in_rrd( "vmware_VMs", "", "$lpar.rrm", $item, "Disk_read" );
  if ( $is_dusage || $is_dread ) {
    $tab_number++;
    print "  <li class=\"\"><a href=\"#tabs-$tab_number\">DISK</a></li>\n";
  }

  # if there is data for IOPS under any datastore in vCenter/datacenter/datastore/*.rrv
  # print STDERR "282 \$host $host \$server $server \$lpar $lpar\n";
  my $vm_iops = 0;
  if ( open( FH, "< $wrkdir/$server/$host/my_vcenter_name" ) ) {
    my $vcenter_name = <FH>;
    close(FH);
    chomp $vcenter_name;    # e.g. '10.22.11.10|Regina-new'
                            # now look for the appropriate vCenter
    ( undef, $vcenter_name ) = split( /\|/, $vcenter_name );

    # print STDERR "287 \$vcenter_name $vcenter_name\n";
    my $vCenter     = "";
    my $last_update = 0;

    foreach my $center (<$wrkdir/vmware_*>) {
      next if $center =~ "vmware_VMs";
      next if !open( FH, "< $center/vmware_alias_name" );
      my $vmware_alias_name = <FH>;
      close(FH);
      next if $vmware_alias_name !~ /$vcenter_name$/;

      # find the newest one vcenter
      my $update = ( stat("$center/vmware_alias_name") )[9];
      if ( $last_update < $update ) {
        $vCenter     = $center;
        $last_update = $update;
      }
    }

    # print STDERR "299 found \$vCenter $vCenter $vCenter/*/*/$lpar.rrv\n";
    if ( $vCenter ne "" ) {
      my @files = <$vCenter/*/*/$lpar.rrv>;

      #print STDERR "302 \@files @files\n";
      if ( defined $files[0] && $files[0] ne "" ) {
        $tab_number++;
        print "  <li class=\"\"><a href=\"#tabs-$tab_number\">IOPS</a></li>\n";
        $vm_iops = 1;
      }
    }
  }

  my $is_nusage    = test_metric_in_rrd( "vmware_VMs", "", "$lpar.rrm", $item, "Network_usage" );
  my $is_nreceived = test_metric_in_rrd( "vmware_VMs", "", "$lpar.rrm", $item, "Network_received" );
  if ( $is_nusage || $is_nreceived ) {
    $tab_number++;
    print "  <li class=\"\"><a href=\"#tabs-$tab_number\">LAN</a></li>\n";
  }

  my $is_memswap = test_metric_in_rrd( "vmware_VMs", "", "$lpar.rrm", $item, "Memory_swapin" );
  if ($is_memswap) {
    $tab_number++;
    print "  <li class=\"\"><a href=\"#tabs-$tab_number\">SWAP</a></li>\n";
  }

  my $is_memcomp = test_metric_in_rrd( "vmware_VMs", "", "$lpar.rrm", $item, "Memory_compres" );
  if ($is_memcomp) {
    $tab_number++;
    print "  <li class=\"\"><a href=\"#tabs-$tab_number\">COMP</a></li>\n";
  }

  my $is_ready = test_metric_in_rrd( "vmware_VMs", "", "$lpar.rrm", $item, "CPU_ready_ms" );

  #    my $is_ready = 0;
  if ($is_ready) {
    $tab_number++;
    print "  <li class=\"\"><a href=\"#tabs-$tab_number\">CPU Ready</a></li>\n";
  }

  # show vMotion only if exists
  # since 4.84-5 show always, users have info on which ESXi is VM now
  # my @path_lines = `grep "$lpar" "$wrkdir"/*/*/VM_hosting.vmh`; #vmx
  # print STDERR "...... \$lpar $lpar \$wrkdir $wrkdir \@path_lines @path_lines\n";
  # if (scalar @path_lines > 2) {
  $tab_number++;
  print "  <li class=\"\"><a href=\"#tabs-$tab_number\">vMotion</a></li>\n";

  # }

  #
  ### join Linux agent data with vmware VM
  #

  my $lpar_name_agent = "";
  my ( $code, $linux_uuids ) = -f $agents_uuid_file ? Xorux_lib::read_json($agents_uuid_file) : ( 0, undef );

  # 1st method: look for the right VM old UUID inside all agents data uuid.txt
  # agents uuids are prepared by find_active_lpar.pl in a txt file

  # get VMs data with the old uuid (not instanceUuid)
  my $vm_uuid_name_file = "$wrkdir/vmware_VMs/vm_uuid_name.txt";

  # e.g. 501c487b-66db-574a-1578-8bb38694a41f,vm-jindra,vm-jindra,421c05d2-69c4-da27-3ff6-6e508678c004,other-vm-name-can-be-here
  #                                                              ,     this is old UUID               ,
  my @vm_uuid_names = ();
  if ( open( FH, " < $vm_uuid_name_file" ) ) {
    @vm_uuid_names = <FH>;
    close FH;
  }
  else {
    error( "Cannot open $vm_uuid_name_file: $!" . __FILE__ . ":" . __LINE__ );
  }

  # get proper VM line (for this actual $lpar) from vm_uuid_names according to instanceUuid
  my @matches = grep {/^$lpar/} @vm_uuid_names;
  if ( !defined $matches[0] ) { error( "! defined VM uuid ($lpar) in vmware_VMs/vm_uuid_name.txt & exit " . __FILE__ . ":" . __LINE__ ) && exit }

  # will you test  or scalar @matches > 1 ?
  chomp $matches[0];
  ( undef, my $lpar_name, undef, my $uuid_old, my $other_lpar_name ) = split( ",", $matches[0] );

  if ( defined $uuid_old && $uuid_old ne '' ) {
    chomp $uuid_old;
    my $formatted_uuid = Xorux_lib::uuid_big_endian_format( $uuid_old, '-' );

    if ( $code && defined $linux_uuids->{$formatted_uuid} ) {
      $lpar_name_agent = $linux_uuids->{$formatted_uuid};

      #print STDERR "743 \$lpar $lpar \$lpar_name $lpar_name \$other_lpar_name $other_lpar_name\n";
    }
  }

  if ( !$lpar_name_agent ) {

    # 2nd method: get VM name & try directly the agent data path
    # print STDERR "533 2nd method -f $wrkdir/Linux/no_hmc/$lpar_name/uuid.txt\n";
    if ( -f "$wrkdir/Linux/no_hmc/$lpar_name/uuid.txt" ) {
      $lpar_name_agent = $lpar_name;

      # print STDERR "752 \$lpar_name_agent \$lpar_name_agent for $lpar_name\n";
    }

    # 3rd method: look for the other lpar name
    if ( !$lpar_name_agent ) {
      if ( defined $other_lpar_name ) {
        chomp $other_lpar_name;
        if ( -f "$wrkdir/Linux/no_hmc/$other_lpar_name/uuid.txt" ) {
          $lpar_name_agent = $other_lpar_name;

          # print STDERR "760 \$lpar_name_agent $lpar_name_agent for $lpar_name\n";
        }
      }
    }
  }

  if ($lpar_name_agent) {
    @item_agent      = ();
    @item_agent_tab  = ();
    $item_agent_indx = $tab_number;
    $os_agent        = 0;
    $nmon_agent      = 0;
    $iops            = "IOPS";

    build_agents_tabs( "Linux", "no_hmc", $lpar_name_agent );
  }

  #
  ### join Hyperv agent with Windows computer data if exists
  #

  # my @matches = grep {/^$lpar/} @vm_uuid_names;
  # print STDERR "709 \@matches @matches \$uuid_old $uuid_old\n";

  my $win_uuid_name_file = "$tmpdir/win_uuid.txt";

  # e.g. 421cd1bb-d769-0b16-db20-995fee1f72d5 /home/lpar2rrd/lpar2rrd/data/windows/domain_ad.int.xorux.com/WS2012R2-1/pool.rrm

  my @win_lines = ();
  if ( -f $win_uuid_name_file ) {
    if ( open( FH, " < $win_uuid_name_file" ) ) {
      @win_lines = <FH>;
      close FH;
    }
    else {
      error( "Cannot open $win_uuid_name_file: $!" . __FILE__ . ":" . __LINE__ );
    }
  }

  my ( $w_host, $w_server, $w_lpar, $w_item, $w_type_sam );

  # get proper WIN line (for this actual $lpar) from win_uuid_names according to instanceUuid
  my @matches_win = grep {/^$uuid_old/} @win_lines;
  if ( defined $matches_win[0] ) {

    # will you test  or scalar @matches > 1 ?
    chomp $matches_win[0];
    ( undef, my $pool_path, undef ) = split( " ", $matches_win[0] );

    if ( defined $pool_path && $pool_path ne '' ) {
      chomp $uuid_old;

      # print STDERR "734 \$pool_path $pool_path\n";
      # HVNODE01, windows%2Fdomain%5Fad%2Exorux%2Ecom, pool, pool, m, 1

      my @dirs    = split( "\/", $pool_path );
      my $tab_num = $tab_number;
      $tab_num++;

      # print STDERR "740 $host_url, $server_url, $lpar_url, $item, $type_sam, $tab_num\n";

      $w_host     = $dirs[-2];
      $w_server   = "windows/$dirs[-3]";
      $w_lpar     = "pool";
      $w_item     = "pool";
      $w_type_sam = "m";

      # print STDERR "747 \$tab_num $tab_num\n";
      print_hyperv_pool_tabs( $w_host, $w_server, $w_lpar, $w_item, $w_type_sam, $tab_num );

      #print_hyperv_pool_html($w_host, $w_server, $w_lpar, $w_item, $w_type_sam, $tab_num);
    }
  }

  # TABs header end
  print "   </ul> \n";

  $tab_number = 1;
  $item       = "vmw-proc";

  # if ( $cpu > 0 ) {
  # lpar without HMC use only agents --> so no cpu graphs, probably no use for vmware
  print "<div id=\"tabs-$tab_number\"><br><br>\n";
  $tab_number++;
  my $refresh = "";
  $refresh = "<div class=\"refresh fas fa-sync-alt\"><A HREF=\"/lpar2rrd-cgi/lpar2rrd-realt.sh?source=$lpar_url&hmc=$host_url&mname=$server_url&new_gui=$gui\"></A></div>\n";
  print "<table align=\"center\" summary=\"Graphs\">\n";
  print "<tr>\n";
  print_item( $host_url, $server_url, $lpar_url, $item, "d", $type_sam, $entitle, $detail_yes, $refresh, "star", 1, "legend" );
  print_item( $host_url, $server_url, $lpar_url, $item, "w", $type_sam, $entitle, $detail_yes, "norefr", "star", 1, "legend" );
  print "</tr>\n<tr>\n";
  print_item( $host_url, $server_url, $lpar_url, $item, "m", $type_sam,      $entitle, $detail_yes, "norefr", "star", 1, "legend" );
  print_item( $host_url, $server_url, $lpar_url, $item, "y", $type_sam_year, $entitle, $detail_yes, "norefr", "star", 1, "legend" );
  print "</tr>\n";
  print "<tr>\n";
  print_item( $host_url, $server_url, $lpar_url, "trendvm", "y", $type_sam_year, $entitle, $detail_yes, "norefr", "nostar", 2, "legend" );
  print "</tr>\n";
  print "<tr><td align=\"left\" colspan=\"2\"><br>\n";

  # maybe later
  #    print_lpar_cfg ($host_url,$server_url,$lpar_url,$wrkdir,$server,$host,$lpar_slash,$lpar);
  print "</td></tr></table>\n";
  print "</div>\n\n";

  # }

  my $vmw_tab = $tab_number;
  print "<div id=\"tabs-$vmw_tab\"><br><br>\n";
  $vmw_tab++;
  print "<center>\n";
  $item = "lpar";
  print "<table align=\"center\" summary=\"Graphs\">\n";
  print "<tr>\n";
  print_item( $host_url, $server_url, $lpar_url, $item, "d", $type_sam, $entitle, $detail_yes, "norefr", "star", 1, "legend" );
  print_item( $host_url, $server_url, $lpar_url, $item, "w", $type_sam, $entitle, $detail_yes, "norefr", "star", 1, "legend" );
  print "</tr>\n<tr>\n";
  print_item( $host_url, $server_url, $lpar_url, $item, "m", $type_sam,      $entitle, $detail_yes, "norefr", "star", 1, "legend" );
  print_item( $host_url, $server_url, $lpar_url, $item, "y", $type_sam_year, $entitle, $detail_yes, "norefr", "star", 1, "legend" );
  print "</tr></table>\n";
  print "</center></div>\n\n";

  print "<div id=\"tabs-$vmw_tab\"><br><br>\n";
  $vmw_tab++;
  print "<center>\n";
  $item = "vmw-mem";
  print "<table align=\"center\" summary=\"Graphs\">\n";
  print "<tr>\n";
  print_item( $host_url, $server_url, $lpar_url, $item, "d", $type_sam, $entitle, $detail_yes, "norefr", "star", 1, "legend" );
  print_item( $host_url, $server_url, $lpar_url, $item, "w", $type_sam, $entitle, $detail_yes, "norefr", "star", 1, "legend" );
  print "</tr>\n<tr>\n";
  print_item( $host_url, $server_url, $lpar_url, $item, "m", $type_sam,      $entitle, $detail_yes, "norefr", "star", 1, "legend" );
  print_item( $host_url, $server_url, $lpar_url, $item, "y", $type_sam_year, $entitle, $detail_yes, "norefr", "star", 1, "legend" );
  print "</tr>\n";
  print "<tr>\n";
  print_item( $host_url, $server_url, $lpar_url, "trendvmem", "y", $type_sam_year, $entitle, $detail_yes, "norefr", "nostar", 2, "legend" );
  print "</tr>\n";
  print "<tr><td align=\"left\" colspan=\"2\"><br>\n";
  print "</td></tr></table>\n";
  print "</div>\n\n";

  if ( $is_dusage || $is_dread ) {
    print "<div id=\"tabs-$vmw_tab\"><br><br>\n";
    $vmw_tab++;
    print "<center>\n";
    $item = "vmw-disk";
    if ($is_dread) {
      $item = "vmw-diskrw";
    }
    print "<table align=\"center\" summary=\"Graphs\">\n";
    print "<tr>\n";
    print_item( $host_url, $server_url, $lpar_url, $item, "d", $type_sam, $entitle, $detail_yes, "norefr", "star", 1, "legend" );
    print_item( $host_url, $server_url, $lpar_url, $item, "w", $type_sam, $entitle, $detail_yes, "norefr", "star", 1, "legend" );
    print "</tr>\n<tr>\n";
    print_item( $host_url, $server_url, $lpar_url, $item, "m", $type_sam,      $entitle, $detail_yes, "norefr", "star", 1, "legend" );
    print_item( $host_url, $server_url, $lpar_url, $item, "y", $type_sam_year, $entitle, $detail_yes, "norefr", "star", 1, "legend" );
    print "</tr></table>\n";
    print "</center></div>\n\n";
  }

  if ($vm_iops) {
    print "<div id=\"tabs-$vmw_tab\"><br><br>\n";
    $vmw_tab++;
    print "<center>\n";
    print "<table align=\"center\" summary=\"Graphs\">\n";
    $item = "vmw-iops";

    print "<tr>\n";
    print_item( $host_url, $server_url, $lpar_url, $item, "d", $type_sam, $entitle, $detail_yes, "norefr", "star", 1, "nolegend" );
    print_item( $host_url, $server_url, $lpar_url, $item, "w", $type_sam, $entitle, $detail_yes, "norefr", "star", 1, "nolegend" );
    print "</tr>\n<tr>\n";
    print_item( $host_url, $server_url, $lpar_url, $item, "m", $type_sam,      $entitle, $detail_yes, "norefr", "star", 1, "nolegend" );
    print_item( $host_url, $server_url, $lpar_url, $item, "y", $type_sam_year, $entitle, $detail_yes, "norefr", "star", 1, "nolegend" );
    print "</tr></table>\n";
    print "</center></div>\n\n";
  }

  if ( $is_nusage || $is_nreceived ) {
    print "<div id=\"tabs-$vmw_tab\"><br><br>\n";
    $vmw_tab++;
    print "<center>\n";
    print "<table align=\"center\" summary=\"Graphs\">\n";
    $item = "vmw-net";
    if ($is_nreceived) {
      $item = "vmw-netrw";
    }
    print "<tr>\n";
    print_item( $host_url, $server_url, $lpar_url, $item, "d", $type_sam, $entitle, $detail_yes, "norefr", "star", 1, "legend" );
    print_item( $host_url, $server_url, $lpar_url, $item, "w", $type_sam, $entitle, $detail_yes, "norefr", "star", 1, "legend" );
    print "</tr>\n<tr>\n";
    print_item( $host_url, $server_url, $lpar_url, $item, "m", $type_sam,      $entitle, $detail_yes, "norefr", "star", 1, "legend" );
    print_item( $host_url, $server_url, $lpar_url, $item, "y", $type_sam_year, $entitle, $detail_yes, "norefr", "star", 1, "legend" );
    print "</tr></table>\n";
    print "</center></div>\n\n";
  }

  if ($is_memswap) {
    print "<div id=\"tabs-$vmw_tab\"><br><br>\n";
    $vmw_tab++;
    print "<center>\n";
    print "<table align=\"center\" summary=\"Graphs\">\n";
    $item = "vmw-swap";
    print "<tr>\n";
    print_item( $host_url, $server_url, $lpar_url, $item, "d", $type_sam, $entitle, $detail_yes, "norefr", "star", 1, "legend" );
    print_item( $host_url, $server_url, $lpar_url, $item, "w", $type_sam, $entitle, $detail_yes, "norefr", "star", 1, "legend" );
    print "</tr>\n<tr>\n";
    print_item( $host_url, $server_url, $lpar_url, $item, "m", $type_sam,      $entitle, $detail_yes, "norefr", "star", 1, "legend" );
    print_item( $host_url, $server_url, $lpar_url, $item, "y", $type_sam_year, $entitle, $detail_yes, "norefr", "star", 1, "legend" );
    print "</tr></table>\n";
    print "</center></div>\n\n";
  }

  if ($is_memcomp) {
    print "<div id=\"tabs-$vmw_tab\"><br><br>\n";
    $vmw_tab++;
    print "<center>\n";
    print "<table align=\"center\" summary=\"Graphs\">\n";
    $item = "vmw-comp";
    print "<tr>\n";
    print_item( $host_url, $server_url, $lpar_url, $item, "d", $type_sam, $entitle, $detail_yes, "norefr", "star", 1, "legend" );
    print_item( $host_url, $server_url, $lpar_url, $item, "w", $type_sam, $entitle, $detail_yes, "norefr", "star", 1, "legend" );
    print "</tr>\n<tr>\n";
    print_item( $host_url, $server_url, $lpar_url, $item, "m", $type_sam,      $entitle, $detail_yes, "norefr", "star", 1, "legend" );
    print_item( $host_url, $server_url, $lpar_url, $item, "y", $type_sam_year, $entitle, $detail_yes, "norefr", "star", 1, "legend" );
    print "</tr></table>\n";
    print "</center></div>\n\n";
  }

  if ($is_ready) {
    print "<div id=\"tabs-$vmw_tab\"><br><br>\n";
    $vmw_tab++;

    # notice to upper right corner - VM CPU Ready
    my $question_mark = "<div id=\"hiw\"><a href=\"https://lpar2rrd.com/VMware-CPU-ready.php\" target=\"_blank\" class=\"nowrap\"><img src=\"css/images/help-browser.gif\" alt=\"How it works?\" title=\"How it works?\"></img></a></div>";
    print $question_mark;
    print "<center>\n";
    print "<table align=\"center\" summary=\"Graphs\">\n";
    $item = "vmw-ready";
    print "<tr>\n";
    print_item( $host_url, $server_url, $lpar_url, $item, "d", $type_sam, $entitle, $detail_yes, "norefr", "star", 1, "legend" );
    print_item( $host_url, $server_url, $lpar_url, $item, "w", $type_sam, $entitle, $detail_yes, "norefr", "star", 1, "legend" );
    print "</tr>\n<tr>\n";
    print_item( $host_url, $server_url, $lpar_url, $item, "m", $type_sam,      $entitle, $detail_yes, "norefr", "star", 1, "legend" );
    print_item( $host_url, $server_url, $lpar_url, $item, "y", $type_sam_year, $entitle, $detail_yes, "norefr", "star", 1, "legend" );
    print "</tr></table>\n";
    print "</center></div>\n\n";
  }

  # show vMotion only if exists
  # since 4.84-5 show always, users have info on which ESXi is VM now
  #    if (scalar @path_lines > 2) {
  print "<div id=\"tabs-$vmw_tab\"><br><br>\n";
  $vmw_tab++;
  print "<center>\n";
  print "<table align=\"center\" summary=\"Graphs\">\n";
  $item = "vmw-vmotion";
  print "<tr>\n";
  print_item( $host_url, $server_url, $lpar_url, $item, "d", $type_sam, $entitle, $detail_yes, "norefr", "star", 1, "nolegend" );
  print_item( $host_url, $server_url, $lpar_url, $item, "w", $type_sam, $entitle, $detail_yes, "norefr", "star", 1, "nolegend" );
  print "</tr>\n<tr>\n";
  print_item( $host_url, $server_url, $lpar_url, $item, "m", $type_sam,      $entitle, $detail_yes, "norefr", "star", 1, "nolegend" );
  print_item( $host_url, $server_url, $lpar_url, $item, "y", $type_sam_year, $entitle, $detail_yes, "norefr", "star", 1, "nolegend" );
  print "</tr></table>\n";
  print "</center></div>\n\n";

  #    }

  $tab_number = $vmw_tab;
  if ($lpar_name_agent) {
    $tab_number--;

    $host   = "no_hmc";
    $server = "Linux";
    $lpar   = $lpar_name_agent;

    build_agents_html( "Linux", "no_hmc", $lpar_name_agent, $tab_number );
  }

  #
  ### join Hyperv agent with Windows computer data if exists
  #

  # my @matches = grep {/^$lpar/} @vm_uuid_names;
  # print STDERR "956 \@matches @matches \$uuid_old $uuid_old\n";

  my $tab_num = $vmw_tab;

  #$tab_num--;
  # print STDERR "960 \$tab_num $tab_num\n";

  if ( defined $w_host && $w_host ne "" ) {
    print_hyperv_pool_html( $w_host, $w_server, $w_lpar, $w_item, $w_type_sam, $tab_num );
  }

  print "</div><br>\n";
  exit(0);

}

# HYPER-V
if ($hyperv) {

  # TABs
  # basic CPU
  $tab_number = 0;
  print "\n<div  id=\"tabs\"> <ul>\n";

  # my $cpu = 0;

  # if ( -f "$wrkdir/hyperv_VMs/$lpar_slash.rrm") {
  $tab_number++;

  # $cpu = $tab_number;
  print "  <li class=\"\"><a href=\"#tabs-$tab_number\">CPU</a></li>\n";

  # $upper = rrd_upper( $wrkdir, "vmware_VMs", "", $lpar, $type_sam, $type_sam_year, $item, $lpar_slash );

  # }
  $tab_number++;
  print "  <li class=\"\"><a href=\"#tabs-$tab_number\">MEM</a></li>\n";

  # if there are not data (no counters), do not show tabs
  #my $is_dusage = test_metric_in_rrd("vmware_VMs","","$lpar.rrm",$item,"Disk_usage");
  #my $is_dread  = test_metric_in_rrd("vmware_VMs","","$lpar.rrm",$item,"Disk_read");
  #if ($is_dusage || $is_dread) {
  $tab_number++;
  print "  <li class=\"\"><a href=\"#tabs-$tab_number\">DISK</a></li>\n";

  # }
  $tab_number++;
  print "  <li class=\"\"><a href=\"#tabs-$tab_number\">LAN</a></li>\n";

  # vmotion not, it is not ready
  #$tab_number++;
  #print "  <li class=\"\"><a href=\"#tabs-$tab_number\">vMotion</a></li>\n";

  # TABs header end
  print "   </ul> \n";

  $tab_number = 1;
  $item       = "hyp-cpu";

  # if ( $cpu > 0 ) {
  # lpar without HMC use only agents --> so no cpu graphs, probably no use for vmware and no use for hyperv
  print "<div id=\"tabs-$tab_number\"><br><br>\n";
  $tab_number++;
  my $refresh = "";
  $refresh = "<div class=\"refresh fas fa-sync-alt\"><A HREF=\"/lpar2rrd-cgi/lpar2rrd-realt.sh?source=$lpar_url&hmc=$host_url&mname=$server_url&new_gui=$gui\"></A></div>\n";
  print "<table align=\"center\" summary=\"Graphs\">\n";
  print "<tr>\n";
  print_item( $host_url, $server_url, $lpar_url, $item, "d", $type_sam, $entitle, $detail_yes, $refresh, "star", 1, "legend" );
  print_item( $host_url, $server_url, $lpar_url, $item, "w", $type_sam, $entitle, $detail_yes, "norefr", "star", 1, "legend" );
  print "</tr>\n<tr>\n";
  print_item( $host_url, $server_url, $lpar_url, $item, "m", $type_sam,      $entitle, $detail_yes, "norefr", "star", 1, "legend" );
  print_item( $host_url, $server_url, $lpar_url, $item, "y", $type_sam_year, $entitle, $detail_yes, "norefr", "star", 1, "legend" );
  print "</tr>\n";
  print "<tr>\n";

  # maybe later
  #  print_item ($host_url,$server_url,$lpar_url,"trendvm","y",$type_sam_year,$entitle,$detail_no,"norefr","nostar",2,"legend");
  print "</tr>\n";
  print "<tr><td align=\"left\" colspan=\"2\"><br>\n";

  # maybe later
  #    print_lpar_cfg ($host_url,$server_url,$lpar_url,$wrkdir,$server,$host,$lpar_slash,$lpar);
  print "</td></tr></table>\n";
  print "</div>\n\n";

  # }

  print "<div id=\"tabs-$tab_number\"><br><br>\n";
  $tab_number++;
  print "<center>\n";
  $item = "hyp-mem";
  print "<table align=\"center\" summary=\"Graphs\">\n";
  print "<tr>\n";
  print_item( $host_url, $server_url, $lpar_url, $item, "d", $type_sam, $entitle, $detail_yes, "norefr", "star", 1, "legend" );
  print_item( $host_url, $server_url, $lpar_url, $item, "w", $type_sam, $entitle, $detail_yes, "norefr", "star", 1, "legend" );
  print "</tr>\n<tr>\n";
  print_item( $host_url, $server_url, $lpar_url, $item, "m", $type_sam,      $entitle, $detail_yes, "norefr", "star", 1, "legend" );
  print_item( $host_url, $server_url, $lpar_url, $item, "y", $type_sam_year, $entitle, $detail_yes, "norefr", "star", 1, "legend" );
  print "</tr>\n";
  print "<tr>\n";

  # maybe later
  # print_item( $host_url, $server_url, $lpar_url, "trendvmem", "y", $type_sam_year, $entitle, $detail_no, "norefr", "nostar", 2, "legend" );
  print "</tr>\n";
  print "<tr><td align=\"left\" colspan=\"2\"><br>\n";
  print "</td></tr></table>\n";
  print "</div>\n\n";

  #if ($is_dusage || $is_dread) {
  print "<div id=\"tabs-$tab_number\"><br><br>\n";
  $tab_number++;
  print "<center>\n";
  $item = "hyp-disk";

  #if ($is_dread) {
  #  $item = "vmw-diskrw";
  #}
  print "<table align=\"center\" summary=\"Graphs\">\n";
  print "<tr>\n";
  print_item( $host_url, $server_url, $lpar_url, $item, "d", $type_sam, $entitle, $detail_yes, "norefr", "star", 1, "legend" );
  print_item( $host_url, $server_url, $lpar_url, $item, "w", $type_sam, $entitle, $detail_yes, "norefr", "star", 1, "legend" );
  print "</tr>\n<tr>\n";
  print_item( $host_url, $server_url, $lpar_url, $item, "m", $type_sam,      $entitle, $detail_yes, "norefr", "star", 1, "legend" );
  print_item( $host_url, $server_url, $lpar_url, $item, "y", $type_sam_year, $entitle, $detail_yes, "norefr", "star", 1, "legend" );
  print "</tr></table>\n";
  print "</center></div>\n\n";

  #}

  print "<div id=\"tabs-$tab_number\"><br><br>\n";
  $tab_number++;
  print "<center>\n";
  $item = "hyp-net";

  print "<table align=\"center\" summary=\"Graphs\">\n";
  print "<tr>\n";
  print_item( $host_url, $server_url, $lpar_url, $item, "d", $type_sam, $entitle, $detail_yes, "norefr", "star", 1, "legend" );
  print_item( $host_url, $server_url, $lpar_url, $item, "w", $type_sam, $entitle, $detail_yes, "norefr", "star", 1, "legend" );
  print "</tr>\n<tr>\n";
  print_item( $host_url, $server_url, $lpar_url, $item, "m", $type_sam,      $entitle, $detail_yes, "norefr", "star", 1, "legend" );
  print_item( $host_url, $server_url, $lpar_url, $item, "y", $type_sam_year, $entitle, $detail_yes, "norefr", "star", 1, "legend" );
  print "</tr></table>\n";
  print "</center></div>\n\n";

  # show vMotion only if exists
  #    if (scalar @path_lines > 2) {
  #    it is not ready
  #print "<div id=\"tabs-$tab_number\"><br><br>\n";
  #$tab_number++;
  #print "<center>\n";
  #print "<table align=\"center\" summary=\"Graphs\">\n";
  #$item = "hyp-vmotion";
  #print "<tr>\n";
  #print_item( $host_url, $server_url, $lpar_url, $item, "d", $type_sam, $entitle, $detail_yes, "norefr", "star", 1, "nolegend" );
  #print_item( $host_url, $server_url, $lpar_url, $item, "w", $type_sam, $entitle, $detail_yes, "norefr", "star", 1, "nolegend" );
  #print "</tr>\n<tr>\n";
  #print_item( $host_url, $server_url, $lpar_url, $item, "m", $type_sam,      $entitle, $detail_yes, "norefr", "star", 1, "nolegend" );
  #print_item( $host_url, $server_url, $lpar_url, $item, "y", $type_sam_year, $entitle, $detail_yes, "norefr", "star", 1, "nolegend" );
  #print "</tr></table>\n";
  #print "</center></div>\n\n";

  # }
  print "</div><br>\n";
  exit(0);

}

if ($hitachi) {
  my $lpar_uuids_file = "$wrkdir/Hitachi/$host/lpar_uuids.json";
  my ( $code1, $lpar_uuids )  = -f $lpar_uuids_file  ? Xorux_lib::read_json($lpar_uuids_file)  : ( 0, undef );
  my ( $code2, $linux_uuids ) = -f $agents_uuid_file ? Xorux_lib::read_json($agents_uuid_file) : ( 0, undef );

  my $lpar_agent_name = $lpar_uuids->{$lpar}{agent_name} if $code1;
  my $lpar_uuid       = $lpar_uuids->{$lpar}{uuid}       if $code1;

  $tab_number = 1;

  print "<CENTER>";
  print "<div id=\"tabs\">\n";
  print "<ul>\n";
  print "  <li class=\"$tab_type\"><a href=\"#tabs-$tab_number\">CPU</a></li>\n";
  $tab_number++;
  print "  <li class=\"$tab_type\"><a href=\"#tabs-$tab_number\">CPU percentage</a></li>\n";
  $tab_number++;

  if ( $lpar_uuid && $lpar_agent_name && $code2 && $linux_uuids->{$lpar_uuid} ) {
    @item_agent      = ();
    @item_agent_tab  = ();
    $item_agent_indx = $tab_number;
    $os_agent        = 0;
    $nmon_agent      = 0;
    $iops            = "IOPS";

    build_agents_tabs( "Linux", "no_hmc", $lpar_agent_name );
  }

  print "</ul>\n";

  $tab_number = 1;

  $item = "lpar";
  print "<div id=\"tabs-$tab_number\">\n";
  print "<table border=\"0\">\n";
  print "<tr>";
  print_item( $host_url, $server_url, $lpar_url, $item, "d", $type_sam, $entitle, $detail_yes, "norefr", "star", 1, "legend" );
  print_item( $host_url, $server_url, $lpar_url, $item, "w", $type_sam, $entitle, $detail_yes, "norefr", "star", 1, "legend" );
  print "</tr>\n<tr>\n";
  print_item( $host_url, $server_url, $lpar_url, $item, "m", $type_sam,      $entitle, $detail_yes, "norefr", "star", 1, "legend" );
  print_item( $host_url, $server_url, $lpar_url, $item, "y", $type_sam_year, $entitle, $detail_yes, "norefr", "star", 1, "legend" );
  print "</tr></table>";
  print "</div>\n";
  $tab_number++;

  $item = "cpu-percentages";
  print "<div id=\"tabs-$tab_number\">\n";
  print "<table border=\"0\">\n";
  print "<tr>";
  print_item( $host_url, $server_url, $lpar_url, $item, "d", $type_sam, $entitle, $detail_yes, "norefr", "star", 1, "legend" );
  print_item( $host_url, $server_url, $lpar_url, $item, "w", $type_sam, $entitle, $detail_yes, "norefr", "star", 1, "legend" );
  print "</tr>\n<tr>\n";
  print_item( $host_url, $server_url, $lpar_url, $item, "m", $type_sam,      $entitle, $detail_yes, "norefr", "star", 1, "legend" );
  print_item( $host_url, $server_url, $lpar_url, $item, "y", $type_sam_year, $entitle, $detail_yes, "norefr", "star", 1, "legend" );
  print "</tr></table>";
  print "</div>\n";
  $tab_number++;

  if ($lpar_agent_name) {
    build_agents_html( "Linux", "no_hmc", $lpar_agent_name, $tab_number );
  }
  print "</CENTER>";
  print "</div><br>\n";

  #  print STDERR Dumper(@item_agent_tab) . " ## " . Dumper(@item_agent) . "\n";

  exit(0);
}

if ($ovirt) {
  my $mapping;
  my $win_mapping;

  $host_url   = 'oVirt';
  $server_url = 'nope';

  if ( $params{type} eq 'vm' ) {
    $lpar_url    = ( exists $params{id} ) ? $params{id} : $params{vm};
    $mapping     = OVirtDataWrapper::get_mapping($lpar_url);
    $win_mapping = OVirtDataWrapper::get_win_mapping($lpar_url);

    # print STDERR "1470 \$win_mapping $win_mapping\n";

  }
  elsif ( $params{type} eq 'host' ) {
    $lpar_url = ( exists $params{id} ) ? $params{id} : $params{host};
    $mapping  = OVirtDataWrapper::get_mapping($lpar_url);
  }
  elsif ( $params{type} eq 'host_nic_aggr' ) {
    $lpar_url = ( exists $params{id} ) ? $params{id} : $params{host};
  }
  elsif ( $params{type} eq 'host_nic' ) {
    $server_url = ( exists $params{id} ) ? OVirtDataWrapper::get_parent( 'host_nic', $params{id} ) : $params{host};
    $lpar_url   = ( exists $params{id} ) ? $params{id}                                             : $params{nic};
  }
  elsif ( $params{type} eq 'storage_domain' ) {
    $lpar_url = ( exists $params{id} ) ? $params{id} : $params{storage_domain};
  }
  elsif ( $params{type} eq 'disk' ) {
    $lpar_url = ( exists $params{id} ) ? $params{id} : $params{disk};
  }
  elsif ( $params{type} eq 'disk_aggr' ) {
    $lpar_url = ( exists $params{id} ) ? $params{id} : $params{storage_domain};
  }
  elsif ( $params{type} eq 'cluster_aggr' ) {
    $lpar_url = ( exists $params{id} ) ? $params{id} : $params{cluster};
  }
  elsif ( $params{type} eq 'storage_domains_total_aggr' ) {
    $lpar_url = 'nope';
  }
  elsif ( $params{type} eq 'topten_ovirt' ) {
    $lpar_url = $params{type};
  }
  print "<CENTER>";

  # get tabs
  my @tabs  = @{ OVirtMenu::get_tabs( $params{type} ) };
  my @items = ();
  $tab_number = 1;
  if (@tabs) {
    print "<div id=\"tabs\">\n";
    print "<ul>\n";

    foreach my $tab_header (@tabs) {
      while ( my ( $tab_type, $tab_label ) = each %$tab_header ) {
        if ( $tab_type =~ /^(aggr_data|aggr_latency|aggr_iops)$/
          && $params{type} eq 'storage_domain'
          && !scalar @{ OVirtDataWrapper::get_arch( $lpar_url, 'storage_domain', 'disk' ) } )
        {
          next;    # there are no disks on this storage, thus skip tabs with disks totals
        }

        #if ($params{type} eq 'topten_ovirt'){next}
        print "  <li class=\"$tab_type\"><a href=\"#tabs-$tab_number\">$tab_label</a></li>\n";
        $tab_number++;
        push @items, "ovirt_$params{type}\_$tab_type";
      }
    }

    if ($mapping) {
      @item_agent      = ();
      @item_agent_tab  = ();
      $item_agent_indx = $tab_number;
      $os_agent        = 0;
      $nmon_agent      = 0;
      $iops            = 'IOPS';
      build_agents_tabs( 'Linux', 'no_hmc', $mapping );
    }

    # Linux & WINDOWS mapping cannot come together
    if ($win_mapping) {
      my @dirs    = split( "\/", $win_mapping );
      my $tab_num = $tab_number;
      $tab_num++;

      # print STDERR "740 $host_url, $server_url, $lpar_url, $item, $type_sam, $tab_num\n";

      my $w_host     = $dirs[-2];
      my $w_server   = "windows/$dirs[-3]";
      my $w_lpar     = "pool";
      my $w_item     = "pool";
      my $w_type_sam = "m";

      # print STDERR "747 \$tab_num $tab_num\n";
      print_hyperv_pool_tabs( $w_host, $w_server, $w_lpar, $w_item, $w_type_sam, $tab_num );

      #print_hyperv_pool_html($w_host, $w_server, $w_lpar, $w_item, $w_type_sam, $tab_num);
    }

    print "</ul>\n";
  }

  if ( $params{type} =~ m/^topten_ovirt$/ ) {
    ############## LOAD TOPTEN FILE #####################
    my $topten_file_ovirt = "$tmpdir/topten_ovirt.tmp";
    my $last_update       = localtime( ( stat($topten_file_ovirt) )[9] );
    #####################################################
    my $server_pool = "";

    # last day
    print "<div id=\"tabs-1\">\n";
    print "<table align=\"center\" summary=\"Graphs\">\n";
    print "<tr><th align=center>CPU in cores<a class=\"csvfloat\" href=\"/lpar2rrd-cgi/top10_csv.sh?LPAR=$server_pool&host=CSV&type=OVIRT&table=topten&item=load_cpu&period=1\" title=\"LOAD CPU CSV\"><img src=\"css/images/csv.gif\"></a></th><th align=center>CPU %<a class=\"csvfloat\" href=\"/lpar2rrd-cgi/top10_csv.sh?LPAR=$server_pool&host=CSV&type=OVIRT&table=topten&item=cpu_perc&period=1\" title=\"CPU % CSV\"><img src=\"css/images/csv.gif\"></a></th><th align=center>NET in MB/sec<a class=\"csvfloat\" href=\"/lpar2rrd-cgi/top10_csv.sh?LPAR=$server_pool&host=CSV&type=OVIRT&table=topten&item=net&period=1\" title=\"NET CSV\"><img src=\"css/images/csv.gif\"></a></th><th align=center>DISK in MB/sec<a class=\"csvfloat\" href=\"/lpar2rrd-cgi/top10_csv.sh?LPAR=$server_pool&host=CSV&type=OVIRT&table=topten&item=disk&period=1\" title=\"DISK CSV\"><img src=\"css/images/csv.gif\"></a></th></tr>";
    print "<tr style=\"vertical-align:top\">";
    print_top10_to_table_ovirt( "1", "$server_pool", "load_cpu" );
    print_top10_to_table_ovirt( "1", "$server_pool", "cpu_perc" );
    print_top10_to_table_ovirt( "1", "$server_pool", "net" );
    print_top10_to_table_ovirt( "1", "$server_pool", "disk" );
    print "</tr>";
    print "</table>";
    print "<tfoot><tr><td colspan=\"6\">Last update time: $last_update</td></tr></tfoot>";
    print "</div>\n";

    # last week
    print "<div id=\"tabs-2\">\n";
    print "<table align=\"center\" summary=\"Graphs\">\n";
    print "<tr><th align=center>CPU in cores<a class=\"csvfloat\" href=\"/lpar2rrd-cgi/top10_csv.sh?LPAR=$server_pool&host=CSV&type=OVIRT&table=topten&item=load_cpu&period=2\" title=\"LOAD CPU CSV\"><img src=\"css/images/csv.gif\"></a></th><th align=center>CPU %<a class=\"csvfloat\" href=\"/lpar2rrd-cgi/top10_csv.sh?LPAR=$server_pool&host=CSV&type=OVIRT&table=topten&item=cpu_perc&period=2\" title=\"CPU % CSV\"><img src=\"css/images/csv.gif\"></a></th><th align=center>NET in MB/sec<a class=\"csvfloat\" href=\"/lpar2rrd-cgi/top10_csv.sh?LPAR=$server_pool&host=CSV&type=OVIRT&table=topten&item=net&period=2\" title=\"NET CSV\"><img src=\"css/images/csv.gif\"></a></th><th align=center>DISK in MB/sec<a class=\"csvfloat\" href=\"/lpar2rrd-cgi/top10_csv.sh?LPAR=$server_pool&host=CSV&type=OVIRT&table=topten&item=disk&period=2\" title=\"DISK CSV\"><img src=\"css/images/csv.gif\"></a></th></tr>";
    print "<tr style=\"vertical-align:top\">";
    print_top10_to_table_ovirt( "2", "$server_pool", "load_cpu" );
    print_top10_to_table_ovirt( "2", "$server_pool", "cpu_perc" );
    print_top10_to_table_ovirt( "2", "$server_pool", "net" );
    print_top10_to_table_ovirt( "2", "$server_pool", "disk" );
    print "</tr>";
    print "</table>";
    print "<tfoot><tr><td colspan=\"6\">Last update time: $last_update</td></tr></tfoot>";
    print "</div>\n";

    # last month
    print "<div id=\"tabs-3\">\n";
    print "<table align=\"center\" summary=\"Graphs\">\n";
    print "<tr><th align=center>CPU in cores<a class=\"csvfloat\" href=\"/lpar2rrd-cgi/top10_csv.sh?LPAR=$server_pool&host=CSV&type=OVIRT&table=topten&item=load_cpu&period=3\" title=\"LOAD CPU CSV\"><img src=\"css/images/csv.gif\"></a></th><th align=center>CPU %<a class=\"csvfloat\" href=\"/lpar2rrd-cgi/top10_csv.sh?LPAR=$server_pool&host=CSV&type=OVIRT&table=topten&item=cpu_perc&period=3\" title=\"CPU % CSV\"><img src=\"css/images/csv.gif\"></a></th><th align=center>NET in MB/sec<a class=\"csvfloat\" href=\"/lpar2rrd-cgi/top10_csv.sh?LPAR=$server_pool&host=CSV&type=OVIRT&table=topten&item=net&period=3\" title=\"NET CSV\"><img src=\"css/images/csv.gif\"></a></th><th align=center>DISK in MB/sec<a class=\"csvfloat\" href=\"/lpar2rrd-cgi/top10_csv.sh?LPAR=$server_pool&host=CSV&type=OVIRT&table=topten&item=disk&period=3\" title=\"DISK CSV\"><img src=\"css/images/csv.gif\"></a></th></tr>";
    print "<tr style=\"vertical-align:top\">";
    print_top10_to_table_ovirt( "3", "$server_pool", "load_cpu" );
    print_top10_to_table_ovirt( "3", "$server_pool", "cpu_perc" );
    print_top10_to_table_ovirt( "3", "$server_pool", "net" );
    print_top10_to_table_ovirt( "3", "$server_pool", "disk" );
    print "</tr>";
    print "</table>";
    print "<tfoot><tr><td colspan=\"6\">Last update time: $last_update</td></tr></tfoot>";
    print "</div>\n";

    # last year
    print "<div id=\"tabs-4\">\n";
    print "<table align=\"center\" summary=\"Graphs\">\n";
    print "<tr><th align=center>CPU in cores<a class=\"csvfloat\" href=\"/lpar2rrd-cgi/top10_csv.sh?LPAR=$server_pool&host=CSV&type=OVIRT&table=topten&item=load_cpu&period=4\" title=\"LOAD CPU CSV\"><img src=\"css/images/csv.gif\"></a></th><th align=center>CPU %<a class=\"csvfloat\" href=\"/lpar2rrd-cgi/top10_csv.sh?LPAR=$server_pool&host=CSV&type=OVIRT&table=topten&item=cpu_perc&period=4\" title=\"CPU % CSV\"><img src=\"css/images/csv.gif\"></a></th><th align=center>NET in MB/sec<a class=\"csvfloat\" href=\"/lpar2rrd-cgi/top10_csv.sh?LPAR=$server_pool&host=CSV&type=OVIRT&table=topten&item=net&period=4\" title=\"NET CSV\"><img src=\"css/images/csv.gif\"></a></th><th align=center>DISK in MB/sec<a class=\"csvfloat\" href=\"/lpar2rrd-cgi/top10_csv.sh?LPAR=$server_pool&host=CSV&type=OVIRT&table=topten&item=disk&period=4\" title=\"DISK CSV\"><img src=\"css/images/csv.gif\"></a></th></tr>";
    print "<tr style=\"vertical-align:top\">";
    print_top10_to_table_ovirt( "4", "$server_pool", "load_cpu" );
    print_top10_to_table_ovirt( "4", "$server_pool", "cpu_perc" );
    print_top10_to_table_ovirt( "4", "$server_pool", "net" );
    print_top10_to_table_ovirt( "4", "$server_pool", "disk" );
    print "</tr>";
    print "</table>";
    print "<tfoot><tr><td colspan=\"6\">Last update time: $last_update</td></tr></tfoot>";
    print "</div>\n";
  }

  sub print_top10_to_table_ovirt {
    my ( $period, $server_pool, $item_name ) = @_;
    my $topten_file_ovirt = "$tmpdir/topten_ovirt.tmp";
    my $html_tab_header   = sub {
      my @columns = @_;
      my $result  = '';
      $result .= "<center>";
      $result .= "<table style=\"white-space: nowrap;\" class=\"tabconfig tablesorter \" data-sortby='1'>";
      $result .= "<thead><tr>";
      foreach my $item (@columns) {
        $result .= "<th class=\"sortable\">" . $item . "</th>";
      }
      $result .= "</tr></thead>";
      $result .= "<tbody>";
      return $result;
    };
    my $html_table_row = sub {
      my @cells  = @_;
      my $result = '';

      $result .= "<tr>";
      foreach my $cell (@cells) { $result .= "<td>" . $cell . "</td>"; }
      $result .= "</tr>";

      return $result;
    };

    # Table or create CSV file
    my $csv_file;
    if ( $item_name eq "load_cpu" ) {
      $csv_file = "ovirt-load-cpu.csv";
    }
    elsif ( $item_name eq "cpu_perc" ) {
      $csv_file = "ovirt-cpu-perc.csv";
    }
    elsif ( $item_name eq "net" ) {
      $csv_file = "ovirt-net.csv";
    }
    elsif ( $item_name eq "disk" ) {
      $csv_file = "ovirt-disk.csv";
    }
    if ( !$csv ) {
      if ( $item_name eq "load_cpu" or $item_name eq "cpu_perc" ) {
        print "<TD><TABLE class=\"tabconfig tablesorter\" data-sortby=\"1\">";
        if ( $period == 4 ) {    # last year
          print $html_tab_header->( 'Avrg', "VM", 'Cluster', 'Datacenter' );
        }
        else {
          print $html_tab_header->( 'Avrg', 'Max', "VM", 'Cluster', 'Datacenter' );
        }
      }
      elsif ( $item_name eq "net" ) {
        print "<TD><TABLE class=\"tabconfig tablesorter\" data-sortby=\"1\">";
        if ( $period == 4 ) {    # last year
          print $html_tab_header->( 'Avrg', "Name", "VM", 'Cluster', 'Datacenter' );
        }
        else {
          print $html_tab_header->( 'Avrg', 'Max', "Name", "VM", 'Cluster', 'Datacenter' );
        }
      }
      elsif ( $item_name eq "disk" ) {
        print "<TD><TABLE class=\"tabconfig tablesorter\" data-sortby=\"1\">";
        if ( $period == 4 ) {    # last year
          print $html_tab_header->( 'Avrg', "Name", "VM", 'Cluster', 'Datacenter' );
        }
        else {
          print $html_tab_header->( 'Avrg', 'Max', "Name", "VM", 'Cluster', 'Datacenter' );
        }
      }
    }
    else {
      print "Content-Disposition: attachment;filename=\"$csv_file\"\n\n";
      my $csv_header = "";
      if ( $item_name eq "load_cpu" or $item_name eq "cpu_perc" ) {
        if ( $period == 4 ) {    # last year
          $csv_header = "Avrg" . "$sep" . "VM" . "$sep" . "Cluster" . "$sep" . "Datacenter\n";
        }
        else {
          $csv_header = "Avrg" . "$sep" . "Max" . "$sep" . "VM" . "$sep" . "Cluster" . "$sep" . "Datacenter\n";
        }
      }
      elsif ( $item_name eq "net" ) {
        if ( $period == 4 ) {    # last year
          $csv_header = "Avrg" . "$sep" . "Name" . "$sep" . "VM" . "$sep" . "Cluster" . "$sep" . "Datacenter\n";
        }
        else {
          $csv_header = "Avrg" . "$sep" . "Max" . "$sep" . "Name" . "$sep" . "VM" . "$sep" . "Cluster" . "$sep" . "Datacenter\n";
        }
      }
      elsif ( $item_name eq "disk" ) {
        if ( $period == 4 ) {    # last year
          $csv_header = "Avrg" . "$sep" . "Name" . "$sep" . "VM" . "$sep" . "Cluster" . "$sep" . "Datacenter\n";
        }
        else {
          $csv_header = "Avrg" . "$sep" . "Max" . "$sep" . "Name" . "$sep" . "VM" . "$sep" . "Cluster" . "$sep" . "Datacenter\n";
        }
      }
      print "$csv_header";
    }
    my @topten;
    my @topten_not_sorted;
    my @topten_sorted;
    my $topten_limit = 0;
    my @top_values_avrg;
    my @top_values_max;
    if ( -f $topten_file_ovirt ) {
      open( FH, " < $topten_file_ovirt" ) || error( "Cannot open $topten_file_ovirt: $!" . __FILE__ . ":" . __LINE__ );
      @topten = <FH>;
      close FH;
      if ( defined $ENV{TOPTEN} ) {
        $topten_limit = $ENV{TOPTEN};
      }
      $topten_limit = 50 if $topten_limit < 1;
      my @topten_server;
      if ( $item_name eq "load_cpu" ) {
        @topten_server = grep {/cpu_util,/} @topten;
      }
      elsif ( $item_name eq "cpu_perc" ) {
        @topten_server = grep {/cpu_perc,/} @topten;
      }
      elsif ( $item_name eq "net" ) {
        @topten_server = grep {/net,/} @topten;
      }
      elsif ( $item_name eq "disk" ) {
        @topten_server = grep {/disk,/} @topten;
      }
      @topten = @topten_server;
      foreach my $line (@topten) {
        chomp $line;
        my ( $item, $vm_name, $server_pool_name, $manager_name, $net_name, $disk_name );
        if ( $item_name eq "load_cpu" or $item_name eq "cpu_perc" ) {
          ( $item, $vm_name, $server_pool_name, $manager_name, $top_values_avrg[1], $top_values_max[1], $top_values_avrg[2], $top_values_max[2], $top_values_avrg[3], $top_values_max[3], $top_values_avrg[4], $top_values_max[4] ) = split( ",", $line );
          $top_values_avrg[4] = 0 if !defined $top_values_avrg[4] or $top_values_avrg[4] eq "";    # no year value yet, new file
          $top_values_max[4]  = 0 if !defined $top_values_max[4]  or $top_values_max[4] eq "";     # no year value yet, new file
          if ( $top_values_avrg[1] == 0 && $top_values_max[1] == 0 && $top_values_avrg[2] == 0 && $top_values_max[2] == 0 && $top_values_avrg[3] == 0 && $top_values_max[3] == 0 && $top_values_avrg[4] == 0 && $top_values_max[4] == 0 ) { next; }
          push @topten_not_sorted, "$item,$top_values_avrg[$period],$top_values_max[$period],$vm_name,$server_pool_name,$manager_name\n";
        }
        elsif ( $item_name eq "net" ) {
          ( $item, $vm_name, $net_name, $server_pool_name, $manager_name, $top_values_avrg[1], $top_values_max[1], $top_values_avrg[2], $top_values_max[2], $top_values_avrg[3], $top_values_max[3], $top_values_avrg[4], $top_values_max[4] ) = split( ",", $line );
          $top_values_avrg[4] = 0 if !defined $top_values_avrg[4] or $top_values_avrg[4] eq "";    # no year value yet, new file
          $top_values_max[4]  = 0 if !defined $top_values_max[4]  or $top_values_max[4] eq "";     # no year value yet, new file
          $net_name =~ s/===double-col===/:/g;
          $net_name =~ s/\.rrd//g;
          $net_name =~ s/^lan-//g;
          if ( $top_values_avrg[1] == 0 && $top_values_max[1] == 0 && $top_values_avrg[2] == 0 && $top_values_max[2] == 0 && $top_values_avrg[3] == 0 && $top_values_max[3] == 0 && $top_values_avrg[4] == 0 && $top_values_max[4] == 0 ) { next; }
          push @topten_not_sorted, "$item,$top_values_avrg[$period],$top_values_max[$period],$vm_name,$net_name,$server_pool_name,$manager_name\n";
        }
        elsif ( $item_name eq "disk" ) {
          ( $item, $vm_name, $disk_name, $server_pool_name, $manager_name, $top_values_avrg[1], $top_values_max[1], $top_values_avrg[2], $top_values_max[2], $top_values_avrg[3], $top_values_max[3], $top_values_avrg[4], $top_values_max[4] ) = split( ",", $line );
          $top_values_avrg[4] = 0 if !defined $top_values_avrg[4] or $top_values_avrg[4] eq "";    # no year value yet, new file
          $top_values_max[4]  = 0 if !defined $top_values_max[4]  or $top_values_max[4] eq "";     # no year value yet, new file
          if ( $top_values_avrg[1] == 0 && $top_values_max[1] == 0 && $top_values_avrg[2] == 0 && $top_values_max[2] == 0 && $top_values_avrg[3] == 0 && $top_values_max[3] == 0 && $top_values_avrg[4] == 0 && $top_values_max[4] == 0 ) { next; }
          push @topten_not_sorted, "$item,$top_values_avrg[$period],$top_values_max[$period],$vm_name,$disk_name,$server_pool_name,$manager_name\n";
        }
      }
      {
        no warnings;
        @topten_sorted = sort { $b <=> $a } @topten_not_sorted;
      }
    }
    my @topten_sorted_load_cpu;
    {
      no warnings;
      @topten_sorted_load_cpu = sort {
        my @b = split( /,/, $b );
        my @a = split( /,/, $a );

        #print "$b[4] --- $a[4]\n";
        $b[1] <=> $a[1]
      } @topten_sorted;
    }
    foreach my $line1 (@topten_sorted_load_cpu) {
      my ( $item_a, $load_cpu, $load_peak, $vm_name, $server_pool_name, $manager_name, $net_name, $disk_name );
      if ( $item_name eq "load_cpu" or $item_name eq "cpu_perc" ) {
        ( $item_a, $load_cpu, $load_peak, $vm_name, $server_pool_name, $manager_name ) = split( ",", $line1 );
      }
      elsif ( $item_name eq "net" ) {
        ( $item_a, $load_cpu, $load_peak, $vm_name, $net_name, $server_pool_name, $manager_name ) = split( ",", $line1 );
      }
      elsif ( $item_name eq "disk" ) {
        ( $item_a, $load_cpu, $load_peak, $vm_name, $disk_name, $server_pool_name, $manager_name ) = split( ",", $line1 );
      }

      #print STDERR"$item_a, $load_cpu, $load_peak, $vm_name, $uuid\n";
      if ( !$csv ) {
        if ( $item_name eq "load_cpu" or $item_name eq "cpu_perc" ) {
          if ( $period == 4 ) {    # last year
            print $html_table_row->( $load_cpu, $vm_name, $server_pool_name, $manager_name );
          }
          else {
            print $html_table_row->( $load_cpu, $load_peak, $vm_name, $server_pool_name, $manager_name );
          }
        }
        elsif ( $item_name eq "net" ) {
          if ( $period == 4 ) {    # last year
            print $html_table_row->( $load_cpu, $vm_name, $net_name, $server_pool_name, $manager_name );
          }
          else {
            print $html_table_row->( $load_cpu, $load_peak, $vm_name, $net_name, $server_pool_name, $manager_name );
          }
        }
        elsif ( $item_name eq "disk" ) {
          if ( $period == 4 ) {    # last year
            print $html_table_row->( $load_cpu, $vm_name, $disk_name, $server_pool_name, $manager_name );
          }
          else {
            print $html_table_row->( $load_cpu, $load_peak, $vm_name, $disk_name, $server_pool_name, $manager_name );
          }
        }
      }
      else {
        if ( $item_name eq "load_cpu" or $item_name eq "cpu_perc" ) {
          if ( $period == 4 ) {    # last year
            print "$load_cpu" . "$sep" . "$load_peak" . "$sep" . "$vm_name" . "$sep" . "$server_pool_name" . "$sep" . "$manager_name";
          }
          else {
            print "$load_cpu" . "$sep" . "$load_peak" . "$sep" . "$vm_name" . "$sep" . "$server_pool_name" . "$sep" . "$manager_name";
          }
        }
        elsif ( $item_name eq "net" ) {
          if ( $period == 4 ) {    # last year
            print "$load_cpu" . "$sep" . "$vm_name" . "$sep" . "$net_name" . "$sep" . "$server_pool_name" . "$sep" . "$manager_name";
          }
          else {
            print "$load_cpu" . "$sep" . "$load_peak" . "$sep" . "$vm_name" . "$sep" . "$net_name" . "$sep" . "$server_pool_name" . "$sep" . "$manager_name";
          }
        }
        elsif ( $item_name eq "disk" ) {
          if ( $period == 4 ) {    # last year
            print "$load_cpu" . "$sep" . "$vm_name" . "$sep" . "$disk_name" . "$sep" . "$server_pool_name" . "$sep" . "$manager_name";
          }
          else {
            print "$load_cpu" . "$sep" . "$load_peak" . "$sep" . "$vm_name" . "$sep" . "$disk_name" . "$sep" . "$server_pool_name" . "$sep" . "$manager_name";
          }
        }
      }
    }
    if ( !$csv ) {
      print "</TABLE></TD>";
    }
    return 1;
  }

  # print tab content
  sub print_tab_content {
    my ( $tab_number, $host_url, $server_url, $lpar_url, $item, $entitle, $detail_yes, $legend ) = @_;

    print "<div id=\"tabs-$tab_number\">\n";
    print "<table border=\"0\">\n";
    print "<tr>";

    print_item( $host_url, $server_url, $lpar_url, $item, "d", "", $entitle, $detail_yes, "norefr", "star", 1, $legend );
    print_item( $host_url, $server_url, $lpar_url, $item, "w", "", $entitle, $detail_yes, "norefr", "star", 1, $legend );
    print "</tr>\n<tr>\n";
    print_item( $host_url, $server_url, $lpar_url, $item, "m", "", $entitle, $detail_yes, "norefr", "star", 1, $legend );
    print_item( $host_url, $server_url, $lpar_url, $item, "y", "", $entitle, $detail_yes, "norefr", "star", 1, $legend );
    print "</tr></table>";
    print "</div>\n";
  }

  my $conf_dir                 = "$wrkdir/oVirt/configuration";
  my $hosts_cfg_file           = "$conf_dir/hosts.html";
  my $vms_cfg_file             = "$conf_dir/vms.html";
  my $storage_domains_cfg_file = "$conf_dir/storage_domains.html";
  my $storage_vms_cfg_file     = "$conf_dir/storage_vms.html";
  my $vm_disk_cfg_file         = "$conf_dir/vm_disks.html";
  my @conf_files               = ( $hosts_cfg_file, $vms_cfg_file, $storage_domains_cfg_file, $storage_vms_cfg_file, $vm_disk_cfg_file );

  for ( $tab_number = 1; $tab_number <= $#items + 1; $tab_number++ ) {
    if ( $params{type} eq 'configuration' ) {
      my @file;
      my $conf_file = $conf_files[ $tab_number - 1 ];

      if ( -f $conf_file ) {
        open( CFGH, '<', $conf_file ) || Xorux_lib::error( "Could not open file $conf_file $!" . __FILE__ . ':' . __LINE__ );
        @file = <CFGH>;
        close(CFGH);
      }

      print "<div id=\"tabs-$tab_number\">\n";

      if ( scalar @file ) {
        print @file;
      }
      else {
        print "<p>Configuration is generated during first load each day.</p>";
      }

      print "</div>\n";
    }
    elsif ( $params{type} eq 'topten_ovirt' ) {
      next;
    }
    else {
      my $ovirt_item = $items[ $tab_number - 1 ];
      my $legend     = $ovirt_item =~ /aggr/ ? 'nolegend' : 'legend';

      print_tab_content(
        $tab_number, $host_url, $server_url, $lpar_url, $ovirt_item, $entitle,
        $detail_yes, $legend
      );
    }
  }

  if ($mapping) {
    $server = 'Linux';
    $host   = 'no_hmc';
    $lpar   = $mapping;
    build_agents_html( 'Linux', 'no_hmc', $mapping, $tab_number );
  }

  # Linux & WINDOWS mapping cannot come together
  if ($win_mapping) {
    my @dirs    = split( "\/", $win_mapping );
    my $tab_num = $tab_number;
    $tab_num++;

    # print STDERR "740 $host_url, $server_url, $lpar_url, $item, $type_sam, $tab_num\n";

    my $w_host     = $dirs[-2];
    my $w_server   = "windows/$dirs[-3]";
    my $w_lpar     = "pool";
    my $w_item     = "pool";
    my $w_type_sam = "m";

    print_hyperv_pool_html( $w_host, $w_server, $w_lpar, $w_item, $w_type_sam, $tab_num );
  }

  print "</CENTER>";
  print "</div><br>\n";

  exit 0;
}

# XenServer
if ($xenserver) {

  # TODO temporary wrapper for compatibility with legacy subroutines interfacing mainly detail-graph-cgi.pl
  $host_url = 'XenServer';
  if ( $params{type} =~ m/^pool-aggr$/ || $params{type} =~ m/^pool-storage-aggr$/ ) {
    $server_url = $params{id};
    $lpar_url   = 'nope';
  }
  elsif ( $params{type} =~ m/^vm$/ ) {
    $server_url = 'nope';
    $lpar_url   = $params{id};
  }
  elsif ( $params{type} =~ m/^(host|net|storage)/ ) {
    if ( $params{type} =~ m/^host$/ || $params{type} =~ m/-aggr$/ ) {
      $server_url = $params{id};
      $lpar_url   = 'nope';
    }
    elsif ( $params{type} =~ m/^(net|storage)$/ ) {
      $server_url = 'nope';
      $lpar_url   = $params{id};
    }
    elsif ( $params{type} =~ m/topten_xenserver/ ) {
      $lpar_url = $params{type};
    }
    else {
      $lpar_url = 'nope';
    }
  }

  # print page contents
  print "<CENTER>";

  # get tabs
  my @tabs = @{ XenServerMenu::get_tabs( $params{type} ) };

  if (@tabs) {
    print "<div id=\"tabs\">\n";
    print "<ul>\n";

    my $tab_counter = 1;
    foreach my $tab_header (@tabs) {
      while ( my ( $tab_type, $tab_label ) = each %$tab_header ) {
        print "  <li class=\"$tab_type\"><a href=\"#tabs-$tab_counter\">$tab_label</a></li>\n";
        $tab_counter++;
      }
    }

    print "</ul>\n";
  }

  # print tab contents
  sub print_tab_contents {
    my ( $tab_number, $host_url, $server_url, $lpar_url, $item, $entitle, $detail_yes, $legend ) = @_;

    print "<div id=\"tabs-$tab_number\">\n";
    print "<table border=\"0\">\n";
    print "<tr>";

    print_item( $host_url, $server_url, $lpar_url, $item, "d", "", $entitle, $detail_yes, "norefr", "star", 1, $legend );
    print_item( $host_url, $server_url, $lpar_url, $item, "w", "", $entitle, $detail_yes, "norefr", "star", 1, $legend );
    print "</tr>\n<tr>\n";
    print_item( $host_url, $server_url, $lpar_url, $item, "m", "", $entitle, $detail_yes, "norefr", "star", 1, $legend );
    print_item( $host_url, $server_url, $lpar_url, $item, "y", "", $entitle, $detail_yes, "norefr", "star", 1, $legend );
    print "</tr></table>";
    print "</div>\n";
  }

  my $legend = ( $params{type} =~ m/aggr/ ) ? 'nolegend' : 'legend';
  if ( $params{type} =~ m/^host$/ ) {
    my @xen_items = ( 'xen-host-cpu-cores', 'xen-host-cpu-percent', 'xen-host-vm-cpu-cores-aggr', 'xen-host-vm-cpu-percent-aggr', 'xen-host-memory', 'xen-host-vm-memory-used-aggr', 'xen-host-vm-memory-free-aggr' );
    for $tab_number ( 1 .. $#xen_items + 1 ) {

      # adjust $legend for aggregated VM graphs
      $legend = ( $xen_items[ $tab_number - 1 ] =~ m/aggr/ ) ? 'nolegend' : 'legend';
      print_tab_contents( $tab_number, $host_url, $server_url, $lpar_url, $xen_items[ $tab_number - 1 ], $entitle, $detail_yes, $legend );
    }

  }
  elsif ( $params{type} =~ m/^pool-aggr$/ ) {
    my @xen_items = ( 'xen-host-cpu-cores', 'xen-host-cpu-percent', 'xen-vm-cpu-cores', 'xen-vm-cpu-percent', 'xen-host-memory-used', 'xen-host-memory-free', 'xen-vm-memory-used', 'xen-vm-memory-free' );
    for $tab_number ( 1 .. $#xen_items + 1 ) {
      my $xen_item = $xen_items[ $tab_number - 1 ] . '-aggr';
      print_tab_contents( $tab_number, $host_url, $server_url, $lpar_url, $xen_item, $entitle, $detail_yes, $legend );
    }

  }
  elsif ( $params{type} =~ m/^net$/ || $params{type} =~ m/^net-aggr$/ ) {
    my @xen_items = ('xen-lan-traffic');
    for $tab_number ( 1 .. $#xen_items + 1 ) {
      my $xen_item = $xen_items[ $tab_number - 1 ];
      if ( $params{type} =~ m/^net-aggr$/ ) { $xen_item .= '-aggr'; }
      print_tab_contents( $tab_number, $host_url, $server_url, $lpar_url, $xen_item, $entitle, $detail_yes, $legend );
    }

  }
  elsif ( $params{type} =~ m/^storage$/ || $params{type} =~ m/^storage-aggr$/ || $params{type} =~ m/^pool-storage-aggr$/ ) {
    my @xen_items = ( 'xen-disk-vbd', 'xen-disk-vbd-iops', 'xen-disk-vbd-latency' );
    for $tab_number ( 1 .. $#xen_items + 1 ) {
      my $xen_item = $xen_items[ $tab_number - 1 ];
      if ( $params{type} =~ m/storage-aggr$/ ) { $xen_item .= '-aggr'; }
      if ( $params{type} =~ m/^pool-storage-aggr$/ ) { $xen_item =~ s/disk/pool/; }
      print_tab_contents( $tab_number, $host_url, $server_url, $lpar_url, $xen_item, $entitle, $detail_yes, $legend );
    }

  }
  elsif ( $params{type} =~ m/^vm$/ ) {
    my @xen_items = ( 'xen-vm-cpu-cores', 'xen-vm-cpu-percent', 'xen-vm-memory', 'xen-vm-vbd', 'xen-vm-vbd-iops', 'xen-vm-vbd-latency', 'xen-vm-lan' );
    for $tab_number ( 1 .. $#xen_items + 1 ) {
      print_tab_contents( $tab_number, $host_url, $server_url, $lpar_url, $xen_items[ $tab_number - 1 ], $entitle, $detail_yes, $legend );
    }
  }
  elsif ( $params{type} =~ m/^configuration$/ ) {
    my $xenserver_metadata = XenServerDataWrapperOOP->new();

    my $mapping_host_pool  = $xenserver_metadata->get_conf_section('arch-pool');
    my $mapping_vm_host    = $xenserver_metadata->get_conf_section('arch-host-vm');
    my $host_config        = $xenserver_metadata->get_conf_section('spec-host');
    my $vm_config          = $xenserver_metadata->get_conf_section('spec-vm');
    my $config_update_time = localtime( $xenserver_metadata->get_conf_update_time() );

    my $html_tab_header = sub {
      my @columns = @_;
      my $result  = '';

      $result .= "<center>";
      $result .= "<table class=\"tabconfig tablesorter\">";
      $result .= "<thead><tr>";
      foreach my $item (@columns) {
        $result .= "<th class=\"sortable\">" . $item . "</th>";
      }
      $result .= "</tr></thead>";
      $result .= "<tbody>";

      return $result;
    };

    my $html_table_row = sub {
      my @cells  = @_;
      my $result = '';

      $result .= "<tr>";
      foreach my $cell (@cells) { $result .= "<td>" . $cell . "</td>"; }
      $result .= "</tr>";

      return $result;
    };

    my $html_tab_footer = "</tbody></table><p>Last update time: " . $config_update_time . "</p></center>";

    # Host tab
    print "<div id=\"tabs-1\">\n";

    print $html_tab_header->(
      'Pool',      'Host',         'Address', 'Memory [GiB]',
      'CPU count', 'Socket count', 'CPU model',
      'Xen version'
    );

    my @hosts = @{ $xenserver_metadata->get_items( { item_type => 'host' } ) };
    unless ( scalar @hosts > 0 ) {
      print "<tr><td colspan=\"8\" align=\"center\">no hosts found</td></tr>";
    }
    foreach my $host (@hosts) {
      my ( $host_uuid, $host_label ) = each %{$host};
      my $cell_pool = 'NA';
      foreach my $pool ( keys %{$mapping_host_pool} ) {
        if ( grep( /^$host_uuid$/, @{ $mapping_host_pool->{$pool} } ) ) {
          my $pool_label = $xenserver_metadata->get_label( 'pool', $pool );
          my $pool_link  = XenServerMenu::get_url( { type => 'pool-aggr', id => $pool } );
          $cell_pool = "<a href=\"${pool_link}\" class=\"backlink\">${pool_label}</a>";
        }
      }

      my $host_link = XenServerMenu::get_url( { type => 'host', id => $host_uuid } );
      my $cell_host = "<a href=\"${host_link}\" class=\"backlink\">${host_label}</a>";

      my $address      = exists $host_config->{$host_uuid}{address}      ? $host_config->{$host_uuid}{address}      : 'NA';
      my $memory       = exists $host_config->{$host_uuid}{memory}       ? $host_config->{$host_uuid}{memory}       : 'NA';
      my $cpu_count    = exists $host_config->{$host_uuid}{cpu_count}    ? $host_config->{$host_uuid}{cpu_count}    : 'NA';
      my $socket_count = exists $host_config->{$host_uuid}{socket_count} ? $host_config->{$host_uuid}{socket_count} : 'NA';
      my $cpu_model    = exists $host_config->{$host_uuid}{cpu_model}    ? $host_config->{$host_uuid}{cpu_model}    : 'NA';
      my $xen_version  = exists $host_config->{$host_uuid}{version_xen}  ? $host_config->{$host_uuid}{version_xen}  : 'NA';

      print $html_table_row->(
        $cell_pool, $cell_host,    $address,   $memory,
        $cpu_count, $socket_count, $cpu_model, $xen_version
      );
    }

    print $html_tab_footer;
    print "</div>\n";

    # VM tab
    print "<div id=\"tabs-2\">\n";

    print $html_tab_header->(
      'Pool', 'Host',            'VM', 'Memory [GiB]',
      'VCPU', 'VCPU at startup', 'VCPU max',
      'Operating system'
    );

    my @vms = @{ $xenserver_metadata->get_items( { item_type => 'vm' } ) };
    unless ( scalar @vms > 0 ) {
      print "<tr><td colspan=\"8\" align=\"center\">no VMs found</td></tr>";
    }
    foreach my $vm (@vms) {
      my ( $vm_uuid, $vm_label ) = each %{$vm};
      my $cell_pool = my $cell_host = 'NA';
      foreach my $host ( keys %{$mapping_vm_host} ) {
        if ( grep( /^$vm_uuid$/, @{ $mapping_vm_host->{$host} } ) ) {
          my $host_label = $xenserver_metadata->get_label( 'host', $host );
          my $host_link  = XenServerMenu::get_url( { type => 'host', id => $host } );
          $cell_host = "<a href=\"${host_link}\" class=\"backlink\">${host_label}</a>";

          foreach my $pool ( keys %{$mapping_host_pool} ) {
            if ( grep( /^$host$/, @{ $mapping_host_pool->{$pool} } ) ) {
              my $pool_label = $xenserver_metadata->get_label( 'pool', $pool );
              my $pool_link  = XenServerMenu::get_url( { type => 'pool-aggr', id => $pool } );
              $cell_pool = "<a href=\"${pool_link}\" class=\"backlink\">${pool_label}</a>";
            }
          }
        }
      }

      my $vm_link = XenServerMenu::get_url( { type => 'vm', id => $vm_uuid } );
      my $cell_vm = "<a href=\"${vm_link}\" class=\"backlink\">${vm_label}</a>";

      my $memory          = exists $vm_config->{$vm_uuid}{memory}          ? $vm_config->{$vm_uuid}{memory}          : 'NA';
      my $cpu_count       = exists $vm_config->{$vm_uuid}{cpu_count}       ? $vm_config->{$vm_uuid}{cpu_count}       : 'NA';
      my $cpu_count_start = exists $vm_config->{$vm_uuid}{cpu_count_start} ? $vm_config->{$vm_uuid}{cpu_count_start} : 'NA';
      my $cpu_count_max   = exists $vm_config->{$vm_uuid}{cpu_count_max}   ? $vm_config->{$vm_uuid}{cpu_count_max}   : 'NA';
      my $vm_os           = exists $vm_config->{$vm_uuid}{os}              ? $vm_config->{$vm_uuid}{os}              : 'NA';

      print $html_table_row->(
        $cell_pool, $cell_host,       $cell_vm,       $memory,
        $cpu_count, $cpu_count_start, $cpu_count_max, $vm_os
      );
    }

    print $html_tab_footer;
    print "</div>\n";

    # Storage tab
    print "<div id=\"tabs-3\">\n";

    print $html_tab_header->(
      'Hosts',                     'Storage',
      'Physical utilisation [GB]', 'Physical size [GB]', 'Virtual allocation [GB]',
      'Volume',                    'Physical utilisation [GB]', 'Virtual size [GB]', 'VM'
    );

    # architecture > storage > ( sr_host, sr_vdi, vdi_vm )
    my $mapping_storage = $xenserver_metadata->get_conf_section('arch-storage');
    my $sr_config       = $xenserver_metadata->get_conf_section('spec-sr');
    my $vdi_config      = $xenserver_metadata->get_conf_section('spec-vdi');

    my @sr_list = keys %{$sr_config};

    unless ( scalar @sr_list > 0 ) {
      print "<tr><td colspan=\"9\" align=\"center\">no storages found</td></tr>";
    }

    foreach my $sr (@sr_list) {

      # skip certain types (hardware devices, media images)
      if ( exists $sr_config->{$sr}{type} ) {
        my $sr_type = $sr_config->{$sr}{type};

        if ( $sr_type eq 'udev' || $sr_type eq 'iso' ) { next; }
      }

      # get label
      my $sr_label = $xenserver_metadata->get_label( 'sr', $sr );
      if ( $sr_label eq $sr ) {
        $sr_label = 'no label';
      }

      # get params
      my $sr_phys_util  = exists $sr_config->{$sr}{physical_utilisation} ? $sr_config->{$sr}{physical_utilisation} : 'NA';
      my $sr_phys_size  = exists $sr_config->{$sr}{physical_size}        ? $sr_config->{$sr}{physical_size}        : 'NA';
      my $sr_virt_alloc = exists $sr_config->{$sr}{virtual_allocation}   ? $sr_config->{$sr}{virtual_allocation}   : 'NA';

      # get a list of hosts connected to this storage, generate hypertext links
      my @sr_hosts    = exists $mapping_storage->{sr_host}{$sr} ? @{ $mapping_storage->{sr_host}{$sr} } : ();
      my $cell_hosts  = '';
      my $cell_sr     = '';
      my $sr_link_url = '';
      foreach my $sr_host (@sr_hosts) {
        unless ($sr_host) { next; }
        my $host_label    = $xenserver_metadata->get_label( 'host', $sr_host );
        my $host_link_url = XenServerMenu::get_url( { type => 'host', id => $sr_host } );

        $cell_hosts .= "<a href=\"$host_link_url\" class=\"backlink\">$host_label</a><br>";
        $sr_link_url = XenServerMenu::get_url( { type => 'storage', id => $sr } );
      }
      if ($sr_link_url) {
        $cell_sr = "<a href=\"${sr_link_url}\" class=\"backlink\">${sr_label}<br>UUID: $sr</a>";
      }
      else {
        $cell_hosts = 'NA';
        $cell_sr    = $sr_label . "<br>UUID: " . $sr;
      }

      # walk through underlying VDIs (volumes)
      my @sr_vdis = exists $mapping_storage->{sr_vdi}{$sr} ? @{ $mapping_storage->{sr_vdi}{$sr} } : ();

      unless ( scalar @sr_vdis > 0 ) {

        # print the storage with empty remaining cells
        my $cell_vdi = my $vdi_phys_util = my $vdi_virt_size = my $cell_vm = 'NA';
        print $html_table_row->(
          $cell_hosts, $cell_sr,       $sr_phys_util,  $sr_phys_size, $sr_virt_alloc,
          $cell_vdi,   $vdi_phys_util, $vdi_virt_size, $cell_vm
        );
        next;
      }

      foreach my $vdi (@sr_vdis) {
        unless ($vdi) { next; }
        my $vdi_label = $xenserver_metadata->get_label( 'vdi', $vdi );
        if ( $vdi_label eq $vdi ) { $vdi_label = 'no label'; }
        my $cell_vdi = $vdi_label . "<br>UUID: " . $vdi;

        # get VDI params
        my $vdi_phys_util = exists $vdi_config->{$vdi}{physical_utilisation} ? $vdi_config->{$vdi}{physical_utilisation} : 'NA';
        my $vdi_virt_size = exists $vdi_config->{$vdi}{virtual_size}         ? $vdi_config->{$vdi}{virtual_size}         : 'NA';

        # walk through VMs that use this VDI as storage
        my @vm_list = exists $mapping_storage->{vdi_vm}{$vdi} ? @{ $mapping_storage->{vdi_vm}{$vdi} } : ();

        unless ( scalar @vm_list > 0 ) {

          # print the storage with empty remaining cell
          my $cell_vm = 'NA';
          print $html_table_row->(
            $cell_hosts, $cell_sr,       $sr_phys_util,  $sr_phys_size, $sr_virt_alloc,
            $cell_vdi,   $vdi_phys_util, $vdi_virt_size, $cell_vm
          );
        }

        foreach my $vm (@vm_list) {
          unless ($vm) { next; }
          my $vm_label    = $xenserver_metadata->get_label( 'vm', $vm );
          my $vm_link_url = XenServerMenu::get_url( { type => 'vm', id => $vm } );
          my $cell_vm     = "<a href=\"$vm_link_url\" class=\"backlink\">$vm_label</a>";

          print $html_table_row->(
            $cell_hosts, $cell_sr,       $sr_phys_util,  $sr_phys_size, $sr_virt_alloc,
            $cell_vdi,   $vdi_phys_util, $vdi_virt_size, $cell_vm
          );
        }
      }
    }

    print $html_tab_footer;
    print "</div>\n";

    # Storage-VM tab
    print "<div id=\"tabs-4\">\n";

    print $html_tab_header->( 'Host', 'Storage', 'Volume', 'VM' );

    unless ( scalar @sr_list > 0 ) {
      print "<tr><td colspan=\"4\" align=\"center\">no storages found</td></tr>";
    }

    # reuse config and @sr_list from the previous tab
    foreach my $sr (@sr_list) {
      my $sr_label = $xenserver_metadata->get_label( 'sr', $sr );
      if ( $sr_label eq $sr ) {
        $sr_label = 'no label';
      }

      my @sr_hosts = @{ $mapping_storage->{sr_host}{$sr} };

      foreach my $sr_host (@sr_hosts) {
        unless ($sr_host) { next; }
        my $host_label    = $xenserver_metadata->get_label( 'host', $sr_host );
        my $host_link_url = XenServerMenu::get_url( { type => 'host',    id => $sr_host } );
        my $sr_link_url   = XenServerMenu::get_url( { type => 'storage', id => $sr } );

        if ( exists $mapping_storage->{sr_vdi}{$sr} ) {
          my @vdi_list = @{ $mapping_storage->{sr_vdi}{$sr} };
          foreach my $vdi (@vdi_list) {
            if ( exists $mapping_storage->{vdi_vm}{$vdi} ) {
              my $vdi_label = $xenserver_metadata->get_label( 'vdi', $vdi );
              if ( $vdi_label eq $vdi ) {
                $vdi_label = 'no label';
              }

              my @vm_list = @{ $mapping_storage->{vdi_vm}{$vdi} };
              foreach my $vm (@vm_list) {
                unless ($vm) { next; }
                my $vm_label    = $xenserver_metadata->get_label( 'vm', $vm );
                my $vm_link_url = XenServerMenu::get_url( { type => 'vm', id => $vm } );
                print "<tr><td><a href=\"$host_link_url\" class=\"backlink\">$host_label</a></td><td><a href=\"$sr_link_url\" class=\"backlink\">$sr_label ($sr)</a></td><td>$vdi_label ($vdi)</td><td><a href=\"$vm_link_url\" class=\"backlink\">$vm_label</a></td></tr>\n";
              }
            }
          }
        }
      }
    }

    print $html_tab_footer;
    print "</div>\n";
  }

  if ( $params{type} =~ m/^topten_xenserver$/ ) {
    ############## LOAD TOPTEN FILE #####################
    my $topten_file_xenserver = "$tmpdir/topten_xenserver.tmp";
    my $last_update           = localtime( ( stat($topten_file_xenserver) )[9] );
    #####################################################
    my $server_pool = "";

    # last day
    print "<div id=\"tabs-1\">\n";
    print "<table align=\"center\" summary=\"Graphs\">\n";
    print "<tr><th align=center>CPU in cores<a class=\"csvfloat\" href=\"/lpar2rrd-cgi/top10_csv.sh?LPAR=$server_pool&host=CSV&type=XENSERVER&table=topten&item=load_cpu&period=1\" title=\"LOAD CPU CSV\"><img src=\"css/images/csv.gif\"></a></th><th align=center>CPU %<a class=\"csvfloat\" href=\"/lpar2rrd-cgi/top10_csv.sh?LPAR=$server_pool&host=CSV&type=XENSERVER&table=topten&item=cpu_perc&period=1\" title=\"CPU % CSV\"><img src=\"css/images/csv.gif\"></a></th><th align=center>IOPS<a class=\"csvfloat\" href=\"/lpar2rrd-cgi/top10_csv.sh?LPAR=$server_pool&host=CSV&type=XENSERVER&table=topten&item=iops&period=1\" title=\"IOPS\"><img src=\"css/images/csv.gif\"></a></th><th align=center>NET in MB/sec<a class=\"csvfloat\" href=\"/lpar2rrd-cgi/top10_csv.sh?LPAR=$server_pool&host=CSV&type=XENSERVER&table=topten&item=net&period=1\" title=\"NET CSV\"><img src=\"css/images/csv.gif\"></a></th><th align=center>DISK in MB/sec<a class=\"csvfloat\" href=\"/lpar2rrd-cgi/top10_csv.sh?LPAR=$server_pool&host=CSV&type=XENSERVER&table=topten&item=disk&period=1\" title=\"DISK CSV\"><img src=\"css/images/csv.gif\"></a></th></tr>";
    print "<tr style=\"vertical-align:top\">";
    print_top10_to_table_xenserver( "1", "$server_pool", "load_cpu" );
    print_top10_to_table_xenserver( "1", "$server_pool", "cpu_perc" );
    print_top10_to_table_xenserver( "1", "$server_pool", "iops" );
    print_top10_to_table_xenserver( "1", "$server_pool", "disk" );
    print_top10_to_table_xenserver( "1", "$server_pool", "net" );
    print "</tr>";
    print "</table>";
    print "<tfoot><tr><td colspan=\"6\">Last update time: $last_update</td></tr></tfoot>";
    print "</div>\n";

    # last week
    print "<div id=\"tabs-2\">\n";
    print "<table align=\"center\" summary=\"Graphs\">\n";
    print "<tr><th align=center>CPU in cores<a class=\"csvfloat\" href=\"/lpar2rrd-cgi/top10_csv.sh?LPAR=$server_pool&host=CSV&type=XENSERVER&table=topten&item=load_cpu&period=2\" title=\"LOAD CPU CSV\"><img src=\"css/images/csv.gif\"></a></th><th align=center>CPU %<a class=\"csvfloat\" href=\"/lpar2rrd-cgi/top10_csv.sh?LPAR=$server_pool&host=CSV&type=XENSERVER&table=topten&item=cpu_perc&period=2\" title=\"CPU % CSV\"><img src=\"css/images/csv.gif\"></a></th><th align=center>IOPS<a class=\"csvfloat\" href=\"/lpar2rrd-cgi/top10_csv.sh?LPAR=$server_pool&host=CSV&type=XENSERVER&table=topten&item=iops&period=2\" title=\"IOPS\"><img src=\"css/images/csv.gif\"></a></th><th align=center>NET in MB/sec<a class=\"csvfloat\" href=\"/lpar2rrd-cgi/top10_csv.sh?LPAR=$server_pool&host=CSV&type=XENSERVER&table=topten&item=net&period=2\" title=\"NET CSV\"><img src=\"css/images/csv.gif\"></a></th><th align=center>DISK in MB/sec<a class=\"csvfloat\" href=\"/lpar2rrd-cgi/top10_csv.sh?LPAR=$server_pool&host=CSV&type=XENSERVER&table=topten&item=disk&period=2\" title=\"DISK CSV\"><img src=\"css/images/csv.gif\"></a></th></tr>";
    print "<tr style=\"vertical-align:top\">";
    print_top10_to_table_xenserver( "2", "$server_pool", "load_cpu" );
    print_top10_to_table_xenserver( "2", "$server_pool", "cpu_perc" );
    print_top10_to_table_xenserver( "2", "$server_pool", "iops" );
    print_top10_to_table_xenserver( "2", "$server_pool", "disk" );
    print_top10_to_table_xenserver( "2", "$server_pool", "net" );
    print "</tr>";
    print "</table>";
    print "<tfoot><tr><td colspan=\"6\">Last update time: $last_update</td></tr></tfoot>";
    print "</div>\n";

    # last month
    print "<div id=\"tabs-3\">\n";
    print "<table align=\"center\" summary=\"Graphs\">\n";
    print "<tr><th align=center>CPU in cores<a class=\"csvfloat\" href=\"/lpar2rrd-cgi/top10_csv.sh?LPAR=$server_pool&host=CSV&type=XENSERVER&table=topten&item=load_cpu&period=3\" title=\"LOAD CPU CSV\"><img src=\"css/images/csv.gif\"></a></th><th align=center>CPU %<a class=\"csvfloat\" href=\"/lpar2rrd-cgi/top10_csv.sh?LPAR=$server_pool&host=CSV&type=XENSERVER&table=topten&item=cpu_perc&period=3\" title=\"CPU % CSV\"><img src=\"css/images/csv.gif\"></a></th><th align=center>IOPS<a class=\"csvfloat\" href=\"/lpar2rrd-cgi/top10_csv.sh?LPAR=$server_pool&host=CSV&type=XENSERVER&table=topten&item=iops&period=3\" title=\"IOPS\"><img src=\"css/images/csv.gif\"></a></th><th align=center>NET in MB/sec<a class=\"csvfloat\" href=\"/lpar2rrd-cgi/top10_csv.sh?LPAR=$server_pool&host=CSV&type=XENSERVER&table=topten&item=net&period=3\" title=\"NET CSV\"><img src=\"css/images/csv.gif\"></a></th><th align=center>DISK in MB/sec<a class=\"csvfloat\" href=\"/lpar2rrd-cgi/top10_csv.sh?LPAR=$server_pool&host=CSV&type=XENSERVER&table=topten&item=disk&period=3\" title=\"DISK CSV\"><img src=\"css/images/csv.gif\"></a></th></tr>";
    print "<tr style=\"vertical-align:top\">";
    print_top10_to_table_xenserver( "3", "$server_pool", "load_cpu" );
    print_top10_to_table_xenserver( "3", "$server_pool", "cpu_perc" );
    print_top10_to_table_xenserver( "3", "$server_pool", "iops" );
    print_top10_to_table_xenserver( "3", "$server_pool", "disk" );
    print_top10_to_table_xenserver( "3", "$server_pool", "net" );
    print "</tr>";
    print "</table>";
    print "<tfoot><tr><td colspan=\"6\">Last update time: $last_update</td></tr></tfoot>";
    print "</div>\n";

    # last year
    print "<div id=\"tabs-4\">\n";
    print "<table align=\"center\" summary=\"Graphs\">\n";
    print "<tr><th align=center>CPU in cores<a class=\"csvfloat\" href=\"/lpar2rrd-cgi/top10_csv.sh?LPAR=$server_pool&host=CSV&type=XENSERVER&table=topten&item=load_cpu&period=4\" title=\"LOAD CPU CSV\"><img src=\"css/images/csv.gif\"></a></th><th align=center>CPU %<a class=\"csvfloat\" href=\"/lpar2rrd-cgi/top10_csv.sh?LPAR=$server_pool&host=CSV&type=XENSERVER&table=topten&item=cpu_perc&period=4\" title=\"CPU % CSV\"><img src=\"css/images/csv.gif\"></a></th><th align=center>IOPS<a class=\"csvfloat\" href=\"/lpar2rrd-cgi/top10_csv.sh?LPAR=$server_pool&host=CSV&type=XENSERVER&table=topten&item=iops&period=4\" title=\"IOPS\"><img src=\"css/images/csv.gif\"></a></th><th align=center>NET in MB/sec<a class=\"csvfloat\" href=\"/lpar2rrd-cgi/top10_csv.sh?LPAR=$server_pool&host=CSV&type=XENSERVER&table=topten&item=net&period=4\" title=\"NET CSV\"><img src=\"css/images/csv.gif\"></a></th><th align=center>DISK in MB/sec<a class=\"csvfloat\" href=\"/lpar2rrd-cgi/top10_csv.sh?LPAR=$server_pool&host=CSV&type=XENSERVER&table=topten&item=disk&period=4\" title=\"DISK CSV\"><img src=\"css/images/csv.gif\"></a></th></tr>";
    print "<tr style=\"vertical-align:top\">";
    print_top10_to_table_xenserver( "4", "$server_pool", "load_cpu" );
    print_top10_to_table_xenserver( "4", "$server_pool", "cpu_perc" );
    print_top10_to_table_xenserver( "4", "$server_pool", "iops" );
    print_top10_to_table_xenserver( "4", "$server_pool", "disk" );
    print_top10_to_table_xenserver( "4", "$server_pool", "net" );
    print "</tr>";
    print "</table>";
    print "<tfoot><tr><td colspan=\"6\">Last update time: $last_update</td></tr></tfoot>";
    print "</div>\n";
  }

  sub print_top10_to_table_xenserver {
    my ( $period, $server_pool, $item_name ) = @_;
    my $topten_file_xenserver = "$tmpdir/topten_xenserver.tmp";
    my $html_tab_header       = sub {
      my @columns = @_;
      my $result  = '';
      $result .= "<center>";
      $result .= "<table style=\"white-space: nowrap;\" class=\"tabconfig tablesorter \" data-sortby='1'>";
      $result .= "<thead><tr>";
      foreach my $item (@columns) {
        $result .= "<th class=\"sortable\">" . $item . "</th>";
      }
      $result .= "</tr></thead>";
      $result .= "<tbody>";
      return $result;
    };
    my $html_table_row = sub {
      my @cells  = @_;
      my $result = '';

      $result .= "<tr>";
      foreach my $cell (@cells) { $result .= "<td>" . $cell . "</td>"; }
      $result .= "</tr>";

      return $result;
    };

    # Table or create CSV file
    my $csv_file;
    if ( $item_name eq "load_cpu" ) {
      $csv_file = "xenserver-load-cpu.csv";
    }
    elsif ( $item_name eq "cpu_perc" ) {
      $csv_file = "xenserver-cpu-perc.csv";
    }
    elsif ( $item_name eq "iops" ) {
      $csv_file = "xenserver-iops.csv";
    }
    elsif ( $item_name eq "net" ) {
      $csv_file = "xenserver-net.csv";
    }
    elsif ( $item_name eq "disk" ) {
      $csv_file = "xenserver-disk.csv";
    }
    if ( !$csv ) {
      print "<TD><TABLE class=\"tabconfig tablesorter\" data-sortby=\"1\">";
      if ( $period == 4 ) {    # last year
        print $html_tab_header->( 'Avrg', "VM", 'Pool' );
      }
      else {
        print $html_tab_header->( 'Avrg', 'Max', "VM", 'Pool' );
      }
    }
    else {
      print "Content-Disposition: attachment;filename=\"$csv_file\"\n\n";
      my $csv_header;
      if ( $period == 4 ) {    # last year
        $csv_header = "Avrg" . "$sep" . "VM" . "$sep" . "Pool\n";
      }
      else {
        $csv_header = "Avrg" . "$sep" . "Max" . "$sep" . "VM" . "$sep" . "Pool\n";
      }
      print "$csv_header";
    }
    my @topten;
    my @topten_not_sorted;
    my @topten_sorted;
    my $topten_limit = 0;
    my @top_values_avrg;
    my @top_values_max;
    if ( -f $topten_file_xenserver ) {
      open( FH, " < $topten_file_xenserver" ) || error( "Cannot open $topten_file_xenserver: $!" . __FILE__ . ":" . __LINE__ );
      @topten = <FH>;
      close FH;
      if ( defined $ENV{TOPTEN} ) {
        $topten_limit = $ENV{TOPTEN};
      }
      $topten_limit = 50 if $topten_limit < 1;
      my @topten_server;
      if ( $item_name eq "load_cpu" ) {
        @topten_server = grep {/cpu_util,/} @topten;
      }
      elsif ( $item_name eq "cpu_perc" ) {
        @topten_server = grep {/cpu_perc,/} @topten;
      }
      elsif ( $item_name eq "iops" ) {
        @topten_server = grep {/iops,/} @topten;
      }
      elsif ( $item_name eq "net" ) {
        @topten_server = grep {/net,/} @topten;
      }
      elsif ( $item_name eq "disk" ) {
        @topten_server = grep {/disk,/} @topten;
      }
      @topten = @topten_server;
      foreach my $line (@topten) {
        chomp $line;
        my ( $item, $vm_name, $server_pool_name );
        ( $item, $vm_name, $server_pool_name, $top_values_avrg[1], $top_values_max[1], $top_values_avrg[2], $top_values_max[2], $top_values_avrg[3], $top_values_max[3], $top_values_avrg[4], $top_values_max[4] ) = split( ",", $line );
        $top_values_avrg[4] = 0 if !defined $top_values_avrg[4] or $top_values_avrg[4] eq "";    # no year value yet, new file
        $top_values_max[4]  = 0 if !defined $top_values_max[4]  or $top_values_max[4] eq "";     # no year value yet, new file
        if ( $top_values_avrg[1] == 0 && $top_values_max[1] == 0 && $top_values_avrg[2] == 0 && $top_values_max[2] == 0 && $top_values_avrg[3] == 0 && $top_values_max[3] == 0 && $top_values_avrg[4] == 0 && $top_values_max[4] == 0 ) { next; }
        push @topten_not_sorted, "$item,$top_values_avrg[$period],$top_values_max[$period],$vm_name,$server_pool_name\n";
      }
      {
        no warnings;
        @topten_sorted = sort { $b <=> $a } @topten_not_sorted;
      }
    }
    my @topten_sorted_load_cpu;
    {
      no warnings;
      @topten_sorted_load_cpu = sort {
        my @b = split( /,/, $b );
        my @a = split( /,/, $a );

        #print "$b[4] --- $a[4]\n";
        $b[1] <=> $a[1]
      } @topten_sorted;
    }
    foreach my $line1 (@topten_sorted_load_cpu) {
      my ( $item_a, $load_cpu, $load_peak, $vm_name, $server_pool_name );
      ( $item_a, $load_cpu, $load_peak, $vm_name, $server_pool_name ) = split( ",", $line1 );
      if ( !$csv ) {
        if ( $period == 4 ) {    # last year
          print $html_table_row->( $load_cpu, $vm_name, $server_pool_name );
        }
        else {
          print $html_table_row->( $load_cpu, $load_peak, $vm_name, $server_pool_name );
        }
      }
      else {
        if ( $period == 4 ) {    # last year
          print "$load_cpu" . "$sep" . "$vm_name" . "$sep" . "$server_pool_name";
        }
        else {
          print "$load_cpu" . "$sep" . "$load_peak" . "$sep" . "$vm_name" . "$sep" . "$server_pool_name";
        }
      }
    }
    if ( !$csv ) {
      print "</TABLE></TD>";
    }
    return 1;
  }

  # closing page contents
  print "</CENTER>";
  print "</div><br>\n";

  exit(0);
}

# Nutanix
if ($nutanix) {
  my $mapping;

  if ( $params{type} eq 'vm' ) {
    $mapping = NutanixDataWrapper::get_mapping( $params{id} );
  }

  # TODO temporary wrapper for compatibility with legacy subroutines interfacing mainly detail-graph-cgi.pl
  $host_url = 'Nutanix';
  if ( $params{type} =~ m/^pool-aggr$/ || $params{type} =~ m/^pool-storage-aggr$/ || $params{type} =~ m/^vm-aggr$/ || $params{type} =~ m/^sr-aggr$/ ) {
    $server_url = $params{id};
    $lpar_url   = 'nope';
  }
  elsif ( $params{type} =~ m/^vm$/ ) {
    $server_url = 'nope';
    $lpar_url   = $params{id};
  }
  elsif ( $params{type} =~ m/^(host|net|storage|sc|vd|health|vg|sp)/ ) {
    if ( $params{type} =~ m/^host$/ || $params{type} =~ m/-aggr$/ ) {
      $server_url = $params{id};
      $lpar_url   = 'nope';
    }
    elsif ( $params{type} =~ m/^(net|storage|sc|vd|health|vg|sp)$/ ) {
      $server_url = 'nope';
      $lpar_url   = $params{id};
    }
    else {
      $lpar_url = 'nope';
    }
  }

  # print page contents
  print "<CENTER>";

  # get tabs
  my @tabs = @{ NutanixMenu::get_tabs( $params{type} ) };

  $tab_number = 1;
  if (@tabs) {
    print "<div id=\"tabs\">\n";
    print "<ul>\n";

    my $tab_counter = 1;
    foreach my $tab_header (@tabs) {
      while ( my ( $tab_type, $tab_label ) = each %$tab_header ) {
        print "  <li class=\"$tab_type\"><a href=\"#tabs-$tab_number\">$tab_label</a></li>\n";
        $tab_counter++;
        $tab_number++;
      }
    }

    if ($mapping) {
      @item_agent      = ();
      @item_agent_tab  = ();
      $item_agent_indx = $tab_number;
      $os_agent        = 0;
      $nmon_agent      = 0;
      $iops            = "IOPS";

      build_agents_tabs( "Linux", "no_hmc", $mapping );
    }

    print "</ul>\n";
  }

  # print tab contents
  sub print_tab_contents_nutanix {
    my ( $tab_number, $host_url, $server_url, $lpar_url, $item, $entitle, $detail_yes, $legend ) = @_;

    print "<div id=\"tabs-$tab_number\">\n";

    print "<table border=\"0\">\n";
    print "<tr>";
    print_item( $host_url, $server_url, $lpar_url, $item, "d", "", $entitle, $detail_yes, "norefr", "star", 1, $legend );
    print_item( $host_url, $server_url, $lpar_url, $item, "w", "", $entitle, $detail_yes, "norefr", "star", 1, $legend );
    print "</tr>\n<tr>\n";
    print_item( $host_url, $server_url, $lpar_url, $item, "m", "", $entitle, $detail_yes, "norefr", "star", 1, $legend );
    print_item( $host_url, $server_url, $lpar_url, $item, "y", "", $entitle, $detail_yes, "norefr", "star", 1, $legend );
    print "</tr></table>";

    print "</div>\n";
  }
  my $legend = ( $params{type} =~ m/aggr/ ) ? 'nolegend' : 'legend';
  if ( $params{type} =~ m/^host$/ ) {
    my @nutanix_items = ( 'nutanix-host-cpu-cores', 'nutanix-host-cpu-percent', 'nutanix-host-vm-cpu-cores-aggr', 'nutanix-host-vm-cpu-percent-aggr', 'nutanix-host-memory', 'nutanix-host-vm-memory-used-aggr', 'nutanix-host-vm-memory-free-aggr' );
    for $tab_number ( 1 .. $#nutanix_items + 1 ) {

      # adjust $legend for aggregated VM graphs
      $legend = ( $nutanix_items[ $tab_number - 1 ] =~ m/aggr/ ) ? 'nolegend' : 'legend';
      print_tab_contents_nutanix( $tab_number, $host_url, $server_url, $lpar_url, $nutanix_items[ $tab_number - 1 ], $entitle, $detail_yes, $legend );
    }

  }
  elsif ( $params{type} =~ m/^pool-aggr$/ ) {
    my @nutanix_items = ( 'nutanix-host-cpu-cores', 'nutanix-host-cpu-percent', 'nutanix-vm-cpu-cores', 'nutanix-vm-cpu-percent', 'nutanix-host-memory-used', 'nutanix-host-memory-free', 'nutanix-vm-memory-used', 'nutanix-vm-memory-free' );
    for $tab_number ( 1 .. $#nutanix_items + 1 ) {
      my $nutanix_item = $nutanix_items[ $tab_number - 1 ] . '-aggr';
      print_tab_contents_nutanix( $tab_number, $host_url, $server_url, $lpar_url, $nutanix_item, $entitle, $detail_yes, $legend );
    }

  }
  elsif ( $params{type} =~ m/^net$/ || $params{type} =~ m/^net-aggr$/ ) {
    my @nutanix_items = ('nutanix-lan-traffic');
    for $tab_number ( 1 .. $#nutanix_items + 1 ) {
      my $nutanix_item = $nutanix_items[ $tab_number - 1 ];
      if ( $params{type} =~ m/^net-aggr$/ ) { $nutanix_item .= '-aggr'; }
      print_tab_contents_nutanix( $tab_number, $host_url, $server_url, $lpar_url, $nutanix_item, $entitle, $detail_yes, $legend );
    }

  }
  elsif ( $params{type} =~ m/^storage$/ || $params{type} =~ m/^storage-aggr$/ || $params{type} =~ m/^pool-storage-aggr$/ ) {
    my @nutanix_items = ( 'nutanix-disk-vbd', 'nutanix-disk-vbd-iops', 'nutanix-disk-vbd-latency' );
    for $tab_number ( 1 .. $#nutanix_items + 1 ) {
      my $nutanix_item = $nutanix_items[ $tab_number - 1 ];
      if ( $params{type} =~ m/storage-aggr$/ ) { $nutanix_item .= '-aggr'; }
      if ( $params{type} =~ m/^pool-storage-aggr$/ ) { $nutanix_item =~ s/disk/pool/; }
      print_tab_contents_nutanix( $tab_number, $host_url, $server_url, $lpar_url, $nutanix_item, $entitle, $detail_yes, $legend );
    }

  }
  elsif ( $params{type} =~ m/^sc$/ || $params{type} =~ m/^sc-aggr$/ || $params{type} =~ m/^pool-sc-aggr$/ ) {
    my @nutanix_items = ( 'nutanix-disk-vbd-sc', 'nutanix-disk-vbd-iops-sc', 'nutanix-disk-vbd-latency-sc' );
    for $tab_number ( 1 .. $#nutanix_items + 1 ) {
      my $nutanix_item = $nutanix_items[ $tab_number - 1 ];
      if ( $params{type} =~ m/sc-aggr$/ ) { $nutanix_item .= '-aggr'; }
      if ( $params{type} =~ m/^pool-sc-aggr$/ ) { $nutanix_item =~ s/sc/pool/; }
      print_tab_contents_nutanix( $tab_number, $host_url, $server_url, $lpar_url, $nutanix_item, $entitle, $detail_yes, $legend );
    }
  }
  elsif ( $params{type} =~ m/^sr-aggr$/ ) {
    my @nutanix_items = ( 'nutanix-disk-vbd-sp-aggr', 'nutanix-disk-vbd-iops-sp-aggr', 'nutanix-disk-vbd-latency-sp-aggr', 'nutanix-disk-vbd-sc-aggr', 'nutanix-disk-vbd-iops-sc-aggr', 'nutanix-disk-vbd-latency-sc-aggr', 'nutanix-disk-vbd-vd-aggr', 'nutanix-disk-vbd-iops-vd-aggr', 'nutanix-disk-vbd-latency-vd-aggr', 'nutanix-disk-vbd-sr-aggr', 'nutanix-disk-vbd-iops-sr-aggr', 'nutanix-disk-vbd-latency-sr-aggr' );
    for $tab_number ( 1 .. $#nutanix_items + 1 ) {
      my $nutanix_item = $nutanix_items[ $tab_number - 1 ];
      print_tab_contents_nutanix( $tab_number, $host_url, $server_url, $lpar_url, $nutanix_item, $entitle, $detail_yes, $legend );
    }
  }
  elsif ( $params{type} =~ m/^sp$/ || $params{type} =~ m/^sp-aggr$/ ) {
    my @nutanix_items = ( 'nutanix-disk-vbd-sp', 'nutanix-disk-vbd-iops-sp', 'nutanix-disk-vbd-latency-sp' );
    for $tab_number ( 1 .. $#nutanix_items + 1 ) {
      my $nutanix_item = $nutanix_items[ $tab_number - 1 ];
      if ( $params{type} =~ m/sp-aggr$/ ) { $nutanix_item .= '-aggr'; }
      if ( $params{type} =~ m/sr-aggr$/ ) { $nutanix_item .= '-aggr'; }
      print_tab_contents_nutanix( $tab_number, $host_url, $server_url, $lpar_url, $nutanix_item, $entitle, $detail_yes, $legend );
    }

  }
  elsif ( $params{type} =~ m/^vg$/ || $params{type} =~ m/^vg-aggr$/ ) {
    my @nutanix_items = ( 'nutanix-disk-vbd-vg', 'nutanix-disk-vbd-iops-vg', 'nutanix-disk-vbd-latency-vg' );
    for $tab_number ( 1 .. $#nutanix_items + 1 ) {
      my $nutanix_item = $nutanix_items[ $tab_number - 1 ];
      if ( $params{type} =~ m/vg-aggr$/ ) { $nutanix_item .= '-aggr'; }
      print_tab_contents_nutanix( $tab_number, $host_url, $server_url, $lpar_url, $nutanix_item, $entitle, $detail_yes, $legend );
    }

  }
  elsif ( $params{type} =~ m/^vd$/ || $params{type} =~ m/^vd-aggr$/ || $params{type} =~ m/^pool-vd-aggr$/ ) {
    my @nutanix_items = ( 'nutanix-disk-vbd-vd', 'nutanix-disk-vbd-iops-vd', 'nutanix-disk-vbd-latency-vd' );
    for $tab_number ( 1 .. $#nutanix_items + 1 ) {
      my $nutanix_item = $nutanix_items[ $tab_number - 1 ];
      if ( $params{type} =~ m/vd-aggr$/ ) { $nutanix_item .= '-aggr'; }
      if ( $params{type} =~ m/^pool-vd-aggr$/ ) { $nutanix_item =~ s/vd/pool/; }
      print_tab_contents_nutanix( $tab_number, $host_url, $server_url, $lpar_url, $nutanix_item, $entitle, $detail_yes, $legend );
    }

  }
  elsif ( $params{type} =~ m/^vm$/ || $params{type} =~ m/^vm-aggr$/ ) {
    my @nutanix_items;
    if ( $params{type} =~ m/^vm$/ ) {
      @nutanix_items = ( 'nutanix-vm-cpu-cores', 'nutanix-vm-cpu-percent', 'nutanix-vm-memory', 'nutanix-vm-vbd', 'nutanix-vm-vbd-iops', 'nutanix-vm-vbd-latency', 'nutanix-vm-lan' );
    }
    else {
      @nutanix_items = ( 'nutanix-vm-cpu-cores', 'nutanix-vm-cpu-percent', 'nutanix-vm-memory-used', 'nutanix-vm-memory-free', 'nutanix-vm-vbd', 'nutanix-vm-vbd-iops', 'nutanix-vm-vbd-latency', 'nutanix-vm-lan' );
    }
    for $tab_number ( 1 .. $#nutanix_items + 1 ) {
      my $nutanix_item = $nutanix_items[ $tab_number - 1 ];
      if ( $params{type} =~ m/vm-aggr$/ ) { $nutanix_item .= '-aggr'; }
      print_tab_contents_nutanix( $tab_number, $host_url, $server_url, $lpar_url, $nutanix_item, $entitle, $detail_yes, $legend );
    }
    if ($mapping) {
      my $start = $#nutanix_items + 2;
      my $break;

      $server = 'Linux';
      $host   = 'no_hmc';
      $lpar   = $mapping;
      build_agents_html( "Linux", "no_hmc", $mapping, $start );

    }
  }
  elsif ( $params{type} =~ m/^health$/ ) {
    my $config_update_time = defined NutanixDataWrapper::get_conf_update_time() ? localtime( NutanixDataWrapper::get_conf_update_time() ) : 'undefined';

    my $html_tab_header = sub {
      my @columns = @_;
      my $result  = '';

      $result .= "<center>";
      $result .= "<table class=\"tabconfig tablesorter\">";
      $result .= "<thead><tr>";
      foreach my $item (@columns) {
        $result .= "<th class=\"sortable\">" . $item . "</th>";
      }
      $result .= "</tr></thead>";
      $result .= "<tbody>";

      return $result;
    };

    my $html_tab_header_center = sub {
      my @columns = @_;
      my $result  = '';

      $result .= "<center>";
      $result .= "<table class=\"tabconfig tablesorter\">";
      $result .= "<thead><tr style=\"text-align: center;\">";
      foreach my $item (@columns) {
        $result .= "<th class=\"sortable\">" . $item . "</th>";
      }
      $result .= "</tr></thead>";
      $result .= "<tbody>";

      return $result;
    };

    my $html_table_row = sub {
      my @cells  = @_;
      my $result = '';

      $result .= "<tr>";
      foreach my $cell (@cells) { $result .= "<td>" . $cell . "</td>"; }
      $result .= "</tr>";

      return $result;
    };

    my $html_table_row_health = sub {
      my @cells  = @_;
      my $result = '';

      $result .= "<tr>";
      foreach my $cell (@cells) { $result .= $cell; }
      $result .= "</tr>";

      return $result;
    };

    my $red_dot     = "<span style=\"height: 10px; width: 10px; background-color: red; border-radius: 50%; display: inline-block;\"></span>";
    my $orange_dot  = "<span style=\"height: 10px; width: 10px; background-color: orange; border-radius: 50%; display: inline-block;\"></span>";
    my $green_dot   = "<span style=\"height: 10px; width: 10px; background-color: green; border-radius: 50%; display: inline-block;\"></span>";
    my $unknown_dot = "<span style=\"height: 10px; width: 10px; background-color: gray; border-radius: 50%; display: inline-block;\"></span>";

    my $html_tab_footer2 = "</tbody></table></center>";
    my $html_tab_footer  = "</tbody></table></center>";

    my $healths = NutanixDataWrapper::get_conf_section('health');

    my @severity       = ( 'Good',       'Warning',     'Critical', 'Error' );
    my @severity_asc   = ( 'Critical',   'Warning',     'Error',    'Good' );
    my @severity_color = ( "$green_dot", "$orange_dot", "$red_dot", "$red_dot" );

    my $health_alias = $lpar_url;

    if ( exists $healths->{$health_alias} ) {

      my $actual_severity = 0;
      my %cluster_health;
      foreach my $health_key ( keys %{ $healths->{$health_alias}->{summary} } ) {
        if ( ( $healths->{$health_alias}->{summary}->{$health_key}->{Warning} > 0 ) && ( $actual_severity < 1 ) ) {
          $actual_severity                      = 1;
          $cluster_health{$health_alias}{name}  = "Warning";
          $cluster_health{$health_alias}{class} = "hs_warning";
        }
        if ( ( $healths->{$health_alias}->{summary}->{$health_key}->{Critical} > 0 ) && ( $actual_severity < 2 ) ) {
          $actual_severity                      = 2;
          $cluster_health{$health_alias}{name}  = "Critical";
          $cluster_health{$health_alias}{class} = "hs_error";
        }
        if ( ( $healths->{$health_alias}->{summary}->{$health_key}->{Error} > 0 ) && ( $actual_severity < 3 ) ) {
          $actual_severity                      = 3;
          $cluster_health{$health_alias}{name}  = "Error";
          $cluster_health{$health_alias}{class} = "hs_unknown";
        }
      }

      #print "<h4>Health Status: $severity_color[$actual_severity] $severity[$actual_severity]</h4>";
      #print $html_tab_header_center->( 'Type', 'Good', 'Warning', 'Critical',
      #                        'Error', 'Unknown');

      print "<br>";

      print "<div id=\"tabs-1\">\n";

      print $html_tab_header->( 'Cluster', 'Health Status' );

      my $clname = NutanixDataWrapper::get_label( 'cluster', $health_alias );
      print $html_table_row_health->( "<td>$clname</td>", "<td class=\"$cluster_health{$health_alias}{class}\">$cluster_health{$health_alias}{name}</td>" );

      print $html_tab_footer2;

      my @typeArray = ( 'CLUSTER', 'HOST', 'VM', 'STORAGE_POOL', 'CONTAINER', 'VOLUME_GROUP', 'DISK', 'REMOTE_SITE', 'PROTECTION_DOMAIN' );

      for (@typeArray) {
        my $health_type = $_;
        my ( $health_warning, $health_error, $health_critical, $health_good, $health_unknown );
        if ( $healths->{$health_alias}->{summary}->{$health_type}->{Good} > 0 ) {
          $health_good = "<td class=\"hs_good\" style=\"text-align:center;\">$healths->{$health_alias}->{summary}->{$health_type}->{Good}</td>";
        }
        else {
          $health_good = "<td style=\"text-align:center;\">$healths->{$health_alias}->{summary}->{$health_type}->{Good}</td>";
        }
        if ( $healths->{$health_alias}->{summary}->{$health_type}->{Warning} > 0 ) {
          $health_warning = "<td class=\"hs_warning\" style=\"text-align:center;\">$healths->{$health_alias}->{summary}->{$health_type}->{Warning}</td>";
        }
        else {
          $health_warning = "<td style=\"text-align:center;\">$healths->{$health_alias}->{summary}->{$health_type}->{Warning}</td>";
        }
        if ( $healths->{$health_alias}->{summary}->{$health_type}->{Error} > 0 ) {
          $health_error = "<td class=\"hs_error\" style=\"text-align:center;\">$healths->{$health_alias}->{summary}->{$health_type}->{Error}</td>";
        }
        else {
          $health_error = "<td style=\"text-align:center;\">$healths->{$health_alias}->{summary}->{$health_type}->{Error}</td>";
        }
        if ( $healths->{$health_alias}->{summary}->{$health_type}->{Critical} > 0 ) {
          $health_critical = "<td class=\"hs_error\" style=\"text-align:center;\">$healths->{$health_alias}->{summary}->{$health_type}->{Critical}</td>";
        }
        else {
          $health_critical = "<td style=\"text-align:center;\">$healths->{$health_alias}->{summary}->{$health_type}->{Critical}</td>";
        }
        if ( $healths->{$health_alias}->{summary}->{$health_type}->{Unknown} > 0 ) {
          $health_unknown = "<td class=\"hs_unknown\" style=\"text-align:center;\">$healths->{$health_alias}->{summary}->{$health_type}->{Unknown}</td>";
        }
        else {
          $health_unknown = "<td style=\"text-align:center;\">$healths->{$health_alias}->{summary}->{$health_type}->{Unknown}</td>";
        }

        #print $html_table_row_health->( "<td>$health_type</td>" , $health_good , $health_warning , $health_critical , $health_error, $health_unknown );
      }

      #print $html_tab_footer2;
      #print "<br>";

      #print $html_tab_header->( 'Type', 'Name', 'Description', 'Severity','ID');

      my %detail_sorted;
      my $detail_sorted;
      foreach my $test_id ( keys %{ $healths->{$health_alias}->{detail} } ) {
        $detail_sorted->{ $healths->{$health_alias}->{detail}->{$test_id}->{severity} }{$test_id}{type}        = $healths->{$health_alias}->{detail}->{$test_id}->{type};
        $detail_sorted->{ $healths->{$health_alias}->{detail}->{$test_id}->{severity} }{$test_id}{name}        = $healths->{$health_alias}->{detail}->{$test_id}->{name};
        $detail_sorted->{ $healths->{$health_alias}->{detail}->{$test_id}->{severity} }{$test_id}{description} = $healths->{$health_alias}->{detail}->{$test_id}->{description};
        $detail_sorted->{ $healths->{$health_alias}->{detail}->{$test_id}->{severity} }{$test_id}{severity}    = $healths->{$health_alias}->{detail}->{$test_id}->{severity};
      }

      for (@severity_asc) {
        my $detail_severity = $_;
        my $dot;
        foreach my $test_id ( keys %{ $detail_sorted->{$detail_severity} } ) {

          #print $html_table_row->( $detail_sorted->{$detail_severity}->{$test_id}->{type} , $detail_sorted->{$detail_severity}->{$test_id}->{name} , $detail_sorted->{$detail_severity}->{$test_id}->{description} , $detail_sorted->{$detail_severity}->{$test_id}->{severity} , $test_id );
        }
      }

      #print $html_tab_footer;

      print "<br>";

      my $hs_hash = { "Error" => "hs_unknown", "Warning" => "hs_warning", "Critical" => "hs_error" };
      my @errors_array;
      my %errors_hash;

      print $html_tab_header->( 'Severity', 'Type', 'Name', 'Error', 'Description', 'ID' );

      foreach my $health_type ( keys %{ $healths->{$health_alias}->{health} } ) {
        foreach my $health_uuid ( keys %{ $healths->{$health_alias}->{health}->{$health_type} } ) {
          if ( $healths->{$health_alias}->{health}->{$health_type}->{$health_uuid}->{status} ne "Good" ) {
            foreach my $error_id ( keys %{ $healths->{$health_alias}->{health}->{$health_type}->{$health_uuid}->{errors} } ) {

              my ( $name_in_error, $label_in_error );
              if ( $health_type eq "hosts" ) {
                $name_in_error  = "Host";
                $label_in_error = NutanixDataWrapper::get_label( 'host', $health_uuid );
              }
              elsif ( $health_type eq "vms" ) {
                $name_in_error  = "VM";
                $label_in_error = NutanixDataWrapper::get_label( 'vm', $health_uuid );
              }
              elsif ( $health_type eq "clusters" ) {
                $name_in_error  = "Cluster";
                $label_in_error = NutanixDataWrapper::get_label( 'cluster', $health_uuid );
              }
              elsif ( $health_type eq "containers" ) {
                $name_in_error  = "Containers";
                $label_in_error = NutanixDataWrapper::get_label( 'container', $health_uuid );
              }
              elsif ( $health_type eq "disks" ) {
                $name_in_error  = "Disk";
                $label_in_error = NutanixDataWrapper::get_label( 'disk', $health_uuid );
              }
              elsif ( $health_type eq "storage_pools" ) {
                $name_in_error  = "Storage Pool";
                $label_in_error = NutanixDataWrapper::get_label( 'pool', $health_uuid );
              }
              else {
                $name_in_error  = "undef";
                $label_in_error = "undef";
              }

              my $status_error = $healths->{$health_alias}->{health}->{$health_type}->{$health_uuid}->{errors}->{$error_id}->{status};
              my $error_key;
              if ( $status_error eq "Critical" ) {
                $error_key = 1;
              }
              elsif ( $status_error eq "Warning" ) {
                $error_key = 2;
              }
              elsif ( $status_error eq "Error" ) {
                $error_key = 3;
              }
              else {
                $error_key = 4;
              }

              if ( defined( $errors_hash{$error_key}[0] ) ) {
                push( @{ $errors_hash{$error_key} }, { "status" => $healths->{$health_alias}->{health}->{$health_type}->{$health_uuid}->{errors}->{$error_id}->{status}, "name" => $name_in_error, "label" => $label_in_error, "error" => $healths->{$health_alias}->{health}->{$health_type}->{$health_uuid}->{errors}->{$error_id}->{name}, "description" => $healths->{$health_alias}->{health}->{$health_type}->{$health_uuid}->{errors}->{$error_id}->{description}, "id" => $healths->{$health_alias}->{health}->{$health_type}->{$health_uuid}->{errors}->{$error_id}->{id} } );
              }
              else {
                $errors_hash{$error_key}[0] = { "status" => $healths->{$health_alias}->{health}->{$health_type}->{$health_uuid}->{errors}->{$error_id}->{status}, "name" => $name_in_error, "label" => $label_in_error, "error" => $healths->{$health_alias}->{health}->{$health_type}->{$health_uuid}->{errors}->{$error_id}->{name}, "description" => $healths->{$health_alias}->{health}->{$health_type}->{$health_uuid}->{errors}->{$error_id}->{description}, "id" => $healths->{$health_alias}->{health}->{$health_type}->{$health_uuid}->{errors}->{$error_id}->{id} };
              }

              #print $html_table_row_health->("<td class=\"$hs_hash->{$healths->{$health_alias}->{health}->{$health_type}->{$health_uuid}->{errors}->{$error_id}->{status}}\">$healths->{$health_alias}->{health}->{$health_type}->{$health_uuid}->{errors}->{$error_id}->{status}</td>", "<td>$name_in_error</td>", "<td>$label_in_error</td>", "<td>$healths->{$health_alias}->{health}->{$health_type}->{$health_uuid}->{errors}->{$error_id}->{name}</td>", "<td>$healths->{$health_alias}->{health}->{$health_type}->{$health_uuid}->{errors}->{$error_id}->{description}</td>", "<td>$healths->{$health_alias}->{health}->{$health_type}->{$health_uuid}->{errors}->{$error_id}->{id}</td>" );
            }
          }
        }
      }

      for ( 1 .. 4 ) {
        my $err_key_loop = $_;
        for ( @{ $errors_hash{$err_key_loop} } ) {
          my $err_act = $_;
          print $html_table_row_health->( "<td class=\"$hs_hash->{$err_act->{status}}\">$err_act->{status}</td>", "<td>$err_act->{name}</td>", "<td>$err_act->{label}</td>", "<td>$err_act->{error}</td>", "<td>$err_act->{description}</td>", "<td>$err_act->{id}</td>" );
        }
      }
      print $html_tab_footer2;

      print "</div>\n";

      print "<div id=\"tabs-2\">\n";

      print $html_tab_header->(
        'Cluster', 'Severity',        'Title', 'Message',
        'Created', 'Last occurrence', 'Resolved'
      );

      my $alerts = NutanixDataWrapper::get_conf_section('alerts');

      if ( !defined $alerts || scalar $alerts == 0 ) {
        print "<tr><td colspan=\"7\" align=\"center\">no alerts found</td></tr>";
      }

      foreach my $key ( keys %{$alerts} ) {
        if ( $alerts->{$key}->{cluster} ne $health_alias ) { next; }
        my $cluster  = NutanixDataWrapper::get_label( 'cluster', $alerts->{$key}->{cluster} );
        my $severity = substr $alerts->{$key}->{severity}, 1;

        my ( $sec, $min, $hour, $mday, $mon, $year, $wday, $yday, $isdst ) = localtime( $alerts->{$key}->{created_time_stamp_in_usecs} / 1000000 );
        $year += 1900;
        my $created = "$mday. $mon. $year $hour:$min";

        ( $sec, $min, $hour, $mday, $mon, $year, $wday, $yday, $isdst ) = localtime( $alerts->{$key}->{last_occurrence_time_stamp_in_usecs} / 1000000 );
        $year += 1900;
        my $last = "$mday. $mon. $year $hour:$min";

        my $resolved;
        if ( $alerts->{$key}->{resolved_time_stamp_in_usecs} == 0 ) {
          $resolved = "NA";
        }
        else {
          ( $sec, $min, $hour, $mday, $mon, $year, $wday, $yday, $isdst ) = localtime( $alerts->{$key}->{resolved_time_stamp_in_usecs} / 1000000 );
          $year += 1900;
          $resolved = "$mday. $mon. $year $hour:$min";
        }

        print $html_table_row->( $cluster, $severity, $alerts->{$key}->{alert_title}, $alerts->{$key}->{message}, $created, $last, $resolved );
      }

      print $html_tab_footer;
      print "</div>\n";

      print "<div id=\"tabs-3\">\n";

      print $html_tab_header->(
        'Cluster', 'Severity', 'Message',
        'Created'
      );

      $alerts = NutanixDataWrapper::get_conf_section('events');

      unless ( defined $alerts && scalar $alerts > 0 ) {
        print "<tr><td colspan=\"4\" align=\"center\">no events found</td></tr>";
      }

      foreach my $key ( keys %{$alerts} ) {
        if ( $alerts->{$key}->{cluster} ne $health_alias ) { next; }
        my $cluster  = NutanixDataWrapper::get_label( 'cluster', $alerts->{$key}->{cluster} );
        my $severity = substr $alerts->{$key}->{severity}, 1;

        my ( $sec, $min, $hour, $mday, $mon, $year, $wday, $yday, $isdst ) = localtime( $alerts->{$key}->{created_time_stamp_in_usecs} / 1000000 );
        $year += 1900;
        my $created = "$mday. $mon. $year $hour:$min";

        print $html_table_row->( $cluster, $severity, $alerts->{$key}->{message}, $created );
      }

      print $html_tab_footer;
      print "</div>\n";

    }

  }
  elsif ( $params{type} =~ m/^health-central$/ ) {
    my $config_update_time = defined NutanixDataWrapper::get_conf_update_time() ? localtime( NutanixDataWrapper::get_conf_update_time() ) : 'undefined';

    my $html_tab_header = sub {
      my @columns = @_;
      my $result  = '';

      $result .= "<center>";
      $result .= "<table class=\"tabconfig tablesorter\">";
      $result .= "<thead><tr>";
      foreach my $item (@columns) {
        $result .= "<th class=\"sortable\">" . $item . "</th>";
      }
      $result .= "</tr></thead>";
      $result .= "<tbody>";

      return $result;
    };

    my $html_table_row = sub {
      my @cells  = @_;
      my $result = '';

      $result .= "<tr>";
      foreach my $cell (@cells) { $result .= "<td>" . $cell . "</td>"; }
      $result .= "</tr>";

      return $result;
    };

    my $html_table_row_health = sub {
      my @cells  = @_;
      my $result = '';

      $result .= "<tr>";
      foreach my $cell (@cells) { $result .= $cell; }
      $result .= "</tr>";

      return $result;
    };

    my $html_tab_footer = "</tbody></table></center>";

    my $red_dot     = "<span style=\"height: 10px; width: 10px; background-color: red; border-radius: 50%; display: inline-block;\"></span>";
    my $orange_dot  = "<span style=\"height: 10px; width: 10px; background-color: orange; border-radius: 50%; display: inline-block;\"></span>";
    my $green_dot   = "<span style=\"height: 10px; width: 10px; background-color: green; border-radius: 50%; display: inline-block;\"></span>";
    my $unknown_dot = "<span style=\"height: 10px; width: 10px; background-color: gray; border-radius: 50%; display: inline-block;\"></span>";

    my $healths = NutanixDataWrapper::get_conf_section('health');

    my $actual_severity = 0;
    my @severity        = ( 'Good',       'Warning',     'Critical', 'Error' );
    my @severity_color  = ( "$green_dot", "$orange_dot", "$red_dot", "$red_dot" );

    my %cluster_health;

    foreach my $health_alias ( keys %{$healths} ) {
      if ( $health_alias eq "central" ) { next; }
      foreach my $health_key ( keys %{ $healths->{$health_alias}->{summary} } ) {
        if ( ( $healths->{$health_alias}->{summary}->{$health_key}->{Warning} > 0 ) && ( $actual_severity < 1 ) ) {
          $actual_severity                      = 1;
          $cluster_health{$health_alias}{name}  = "Warning";
          $cluster_health{$health_alias}{class} = "hs_warning";
        }
        if ( ( $healths->{$health_alias}->{summary}->{$health_key}->{Critical} > 0 ) && ( $actual_severity < 2 ) ) {
          $actual_severity                      = 2;
          $cluster_health{$health_alias}{name}  = "Critical";
          $cluster_health{$health_alias}{class} = "hs_error";
        }
        if ( ( $healths->{$health_alias}->{summary}->{$health_key}->{Error} > 0 ) && ( $actual_severity < 3 ) ) {
          $actual_severity                      = 3;
          $cluster_health{$health_alias}{name}  = "Error";
          $cluster_health{$health_alias}{class} = "hs_unknown";
        }
      }
    }

    my $hs_hash = { "Error" => "hs_unknown", "Warning" => "hs_warning", "Critical" => "hs_error" };
    my @errors_array;
    my %errors_hash;

    print "<div id=\"tabs-1\">\n";

    #print "<h4>Health Status: $severity_color[$actual_severity] $severity[$actual_severity]</h4>";

    print "<br>";

    print $html_tab_header->( 'Cluster', 'Health Status' );

    foreach my $hkey ( keys %cluster_health ) {
      my $clname = NutanixDataWrapper::get_label( 'cluster', $hkey );
      print $html_table_row_health->( "<td>$clname</td>", "<td class=\"$cluster_health{$hkey}{class}\">$cluster_health{$hkey}{name}</td>" );
    }

    print $html_tab_footer;

    print "<br>";

    print $html_tab_header->( 'Severity', 'Type', 'Name', 'Error', 'Description', 'ID' );

    foreach my $health_alias ( keys %{$healths} ) {
      if ( $health_alias eq "central" ) { next; }
      foreach my $health_type ( keys %{ $healths->{$health_alias}->{health} } ) {
        foreach my $health_uuid ( keys %{ $healths->{$health_alias}->{health}->{$health_type} } ) {
          if ( $healths->{$health_alias}->{health}->{$health_type}->{$health_uuid}->{status} ne "Good" ) {
            foreach my $error_id ( keys %{ $healths->{$health_alias}->{health}->{$health_type}->{$health_uuid}->{errors} } ) {

              my ( $name_in_error, $label_in_error );
              if ( $health_type eq "hosts" ) {
                $name_in_error  = "Host";
                $label_in_error = NutanixDataWrapper::get_label( 'host', $health_uuid );
              }
              elsif ( $health_type eq "vms" ) {
                $name_in_error  = "VM";
                $label_in_error = NutanixDataWrapper::get_label( 'vm', $health_uuid );
              }
              elsif ( $health_type eq "clusters" ) {
                $name_in_error  = "Cluster";
                $label_in_error = NutanixDataWrapper::get_label( 'cluster', $health_uuid );
              }
              elsif ( $health_type eq "containers" ) {
                $name_in_error  = "Containers";
                $label_in_error = NutanixDataWrapper::get_label( 'container', $health_uuid );
              }
              elsif ( $health_type eq "disks" ) {
                $name_in_error  = "Disk";
                $label_in_error = NutanixDataWrapper::get_label( 'disk', $health_uuid );
              }
              elsif ( $health_type eq "storage_pools" ) {
                $name_in_error  = "Storage Pool";
                $label_in_error = NutanixDataWrapper::get_label( 'pool', $health_uuid );
              }
              else {
                $name_in_error  = "undef";
                $label_in_error = "undef";
              }

              my $status_error = $healths->{$health_alias}->{health}->{$health_type}->{$health_uuid}->{errors}->{$error_id}->{status};
              my $error_key;
              if ( $status_error eq "Critical" ) {
                $error_key = 1;
              }
              elsif ( $status_error eq "Warning" ) {
                $error_key = 2;
              }
              elsif ( $status_error eq "Error" ) {
                $error_key = 3;
              }
              else {
                $error_key = 4;
              }

              if ( defined( $errors_hash{$error_key}[0] ) ) {
                push( @{ $errors_hash{$error_key} }, { "status" => $healths->{$health_alias}->{health}->{$health_type}->{$health_uuid}->{errors}->{$error_id}->{status}, "name" => $name_in_error, "label" => $label_in_error, "error" => $healths->{$health_alias}->{health}->{$health_type}->{$health_uuid}->{errors}->{$error_id}->{name}, "description" => $healths->{$health_alias}->{health}->{$health_type}->{$health_uuid}->{errors}->{$error_id}->{description}, "id" => $healths->{$health_alias}->{health}->{$health_type}->{$health_uuid}->{errors}->{$error_id}->{id} } );
              }
              else {
                $errors_hash{$error_key}[0] = { "status" => $healths->{$health_alias}->{health}->{$health_type}->{$health_uuid}->{errors}->{$error_id}->{status}, "name" => $name_in_error, "label" => $label_in_error, "error" => $healths->{$health_alias}->{health}->{$health_type}->{$health_uuid}->{errors}->{$error_id}->{name}, "description" => $healths->{$health_alias}->{health}->{$health_type}->{$health_uuid}->{errors}->{$error_id}->{description}, "id" => $healths->{$health_alias}->{health}->{$health_type}->{$health_uuid}->{errors}->{$error_id}->{id} };
              }
            }
          }
        }
      }

      for ( 1 .. 4 ) {
        my $err_key_loop = $_;
        for ( @{ $errors_hash{$err_key_loop} } ) {
          my $err_act = $_;
          print $html_table_row_health->( "<td class=\"$hs_hash->{$err_act->{status}}\">$err_act->{status}</td>", "<td>$err_act->{name}</td>", "<td>$err_act->{label}</td>", "<td>$err_act->{error}</td>", "<td>$err_act->{description}</td>", "<td>$err_act->{id}</td>" );
        }
      }
      print $html_tab_footer;
    }

    print "</div>";

    print "<div id=\"tabs-2\">\n";

    print $html_tab_header->(
      'Cluster', 'Severity',        'Title', 'Message',
      'Created', 'Last occurrence', 'Resolved'
    );

    my $alerts = NutanixDataWrapper::get_conf_section('alerts');

    if ( !defined $alerts || scalar $alerts == 0 ) {
      print "<tr><td colspan=\"7\" align=\"center\">no alerts found</td></tr>";
    }

    foreach my $key ( keys %{$alerts} ) {
      my $cluster  = NutanixDataWrapper::get_label( 'cluster', $alerts->{$key}->{cluster} );
      my $severity = substr $alerts->{$key}->{severity}, 1;

      my ( $sec, $min, $hour, $mday, $mon, $year, $wday, $yday, $isdst ) = localtime( $alerts->{$key}->{created_time_stamp_in_usecs} / 1000000 );
      $year += 1900;
      my $created = "$mday. $mon. $year $hour:$min";

      ( $sec, $min, $hour, $mday, $mon, $year, $wday, $yday, $isdst ) = localtime( $alerts->{$key}->{last_occurrence_time_stamp_in_usecs} / 1000000 );
      $year += 1900;
      my $last = "$mday. $mon. $year $hour:$min";

      my $resolved;
      if ( $alerts->{$key}->{resolved_time_stamp_in_usecs} == 0 ) {
        $resolved = "NA";
      }
      else {
        ( $sec, $min, $hour, $mday, $mon, $year, $wday, $yday, $isdst ) = localtime( $alerts->{$key}->{resolved_time_stamp_in_usecs} / 1000000 );
        $year += 1900;
        $resolved = "$mday. $mon. $year $hour:$min";
      }

      print $html_table_row->( $cluster, $severity, $alerts->{$key}->{alert_title}, $alerts->{$key}->{message}, $created, $last, $resolved );
    }

    print $html_tab_footer;
    print "</div>\n";

    print "<div id=\"tabs-3\">\n";

    print $html_tab_header->(
      'Cluster', 'Severity', 'Message',
      'Created'
    );

    $alerts = NutanixDataWrapper::get_conf_section('events');

    unless ( defined $alerts && scalar $alerts > 0 ) {
      print "<tr><td colspan=\"4\" align=\"center\">no events found</td></tr>";
    }

    foreach my $key ( keys %{$alerts} ) {
      my $cluster  = NutanixDataWrapper::get_label( 'cluster', $alerts->{$key}->{cluster} );
      my $severity = substr $alerts->{$key}->{severity}, 1;

      my ( $sec, $min, $hour, $mday, $mon, $year, $wday, $yday, $isdst ) = localtime( $alerts->{$key}->{created_time_stamp_in_usecs} / 1000000 );
      $year += 1900;
      my $created = "$mday. $mon. $year $hour:$min";

      print $html_table_row->( $cluster, $severity, $alerts->{$key}->{message}, $created );
    }

    print $html_tab_footer;
    print "</div>\n";

  }
  elsif ( $params{type} =~ m/^configuration$/ ) {
    my $mapping_host_pool  = NutanixDataWrapper::get_conf_section('arch-cluster');
    my $mapping_vm_host    = NutanixDataWrapper::get_conf_section('arch-host-vm');
    my $host_config        = NutanixDataWrapper::get_conf_section('spec-host');
    my $vm_config          = NutanixDataWrapper::get_conf_section('spec-vm');
    my $config_update_time = defined NutanixDataWrapper::get_conf_update_time() ? localtime( NutanixDataWrapper::get_conf_update_time() ) : 'undefined';

    my $html_tab_header = sub {
      my @columns = @_;
      my $result  = '';

      $result .= "<center>";
      $result .= "<table class=\"tabconfig tablesorter\">";
      $result .= "<thead><tr>";
      foreach my $item (@columns) {
        $result .= "<th class=\"sortable\">" . $item . "</th>";
      }
      $result .= "</tr></thead>";
      $result .= "<tbody>";

      return $result;
    };

    my $html_table_row = sub {
      my @cells  = @_;
      my $result = '';

      $result .= "<tr>";
      foreach my $cell (@cells) {
        if   ( defined $cell ) { $result .= "<td>" . $cell . "</td>"; }
        else                   { $result .= "<td></td>"; }
      }
      $result .= "</tr>";

      return $result;
    };

    my $html_tab_footer = "</tbody></table><p>Last update time: " . $config_update_time . "</p></center>";

    # Nutanix Wrapper OOP
    my $wrapper = NutanixDataWrapperOOP->new( { conf_labels => 1 } );

    # Host tab
    print "<div id=\"tabs-1\">\n";

    print $html_tab_header->(
      'Cluster',   'Host',         'Address', 'Memory [GiB]',
      'CPU count', 'Socket count', 'CPU model',
      'Version'
    );

    my @hosts = @{ NutanixDataWrapper::get_items( { item_type => 'host' } ) };
    unless ( scalar @hosts > 0 ) {
      print "<tr><td colspan=\"8\" align=\"center\">no hosts found</td></tr>";
    }
    foreach my $host (@hosts) {
      my ( $host_uuid, $host_label ) = each %{$host};

      if ( !defined $host_config->{$host_uuid}{parent_cluster} ) { next; }

      my $host_link = NutanixMenu::get_url( { type => 'host', host => $host_uuid } );
      my $cell_host = "<a href=\"${host_link}\" class=\"backlink\">${host_label}</a>";

      my $address      = exists $host_config->{$host_uuid}{address}      ? $host_config->{$host_uuid}{address}                   : 'NA';
      my $memory       = exists $host_config->{$host_uuid}{memory}       ? sprintf( "%.2f", $host_config->{$host_uuid}{memory} ) : 'NA';
      my $cpu_count    = exists $host_config->{$host_uuid}{cpu_count}    ? $host_config->{$host_uuid}{cpu_count}                 : 'NA';
      my $socket_count = exists $host_config->{$host_uuid}{socket_count} ? $host_config->{$host_uuid}{socket_count}              : 'NA';
      my $cpu_model    = exists $host_config->{$host_uuid}{cpu_model}    ? $host_config->{$host_uuid}{cpu_model}                 : 'NA';
      my $version      = exists $host_config->{$host_uuid}{version}      ? $host_config->{$host_uuid}{version}                   : 'NA';

      print $html_table_row->( $wrapper->get_label( 'cluster', $host_config->{$host_uuid}{parent_cluster} ), $cell_host, "<div style=\"padding:4px 10px;\">$address</div>", "<div style=\"padding:4px 10px;\">$memory</div>", "<div style=\"padding:4px 10px;\">$cpu_count</div>", "<div style=\"padding:4px 10px;\">$socket_count</div>", "<div style=\"padding:4px 10px;\">$cpu_model</div>", "<div style=\"padding:4px 10px;\">$version</div>" );
    }
    print $html_tab_footer;
    print "</div>\n";

    # VM tab
    print "<div id=\"tabs-2\">\n";

    print $html_tab_header->(
      'Cluster', 'Host', 'VM', 'Memory [GiB]',
      'vCPU',
      'Operating system'
    );

    my @vms = @{ NutanixDataWrapper::get_items( { item_type => 'vm' } ) };
    unless ( scalar @vms > 0 ) {
      print "<tr><td colspan=\"8\" align=\"center\">no VMs found</td></tr>";
    }
    foreach my $vm (@vms) {
      my ( $vm_uuid, $vm_label ) = each %{$vm};
      if ( !defined $vm_label ) { next; }
      my $cell_pool = my $cell_host = 'NA';
      my $vm_link   = NutanixMenu::get_url( { type => 'vm', vm => $vm_uuid } );
      my $cell_vm   = "<a href=\"${vm_link}\" class=\"backlink\">${vm_label}</a>";

      my $memory       = exists $vm_config->{$vm_uuid}{memory}                                                           ? $vm_config->{$vm_uuid}{memory}         : 'NA';
      my $cpu_count    = exists $vm_config->{$vm_uuid}{cpu_count}                                                        ? $vm_config->{$vm_uuid}{cpu_count}      : 'NA';
      my $vm_os        = exists $vm_config->{$vm_uuid}{os} && defined $vm_config->{$vm_uuid}{os}                         ? $vm_config->{$vm_uuid}{os}             : 'NA';
      my $vm_host_uuid = exists $vm_config->{$vm_uuid}{parent_host} && defined $vm_config->{$vm_uuid}{parent_host}       ? $vm_config->{$vm_uuid}{parent_host}    : 'NA';
      my $vm_pool_uuid = exists $vm_config->{$vm_uuid}{parent_cluster} && defined $vm_config->{$vm_uuid}{parent_cluster} ? $vm_config->{$vm_uuid}{parent_cluster} : 'NA';

      my $vm_host_label;
      my $vm_pool_label;

      if ( $vm_host_uuid ne 'NA' ) {
        $vm_host_label = $wrapper->get_label( 'host', $vm_host_uuid );
      }
      else {
        $vm_host_label = $vm_host_uuid;
      }

      if ( $vm_pool_uuid ne 'NA' ) {
        $vm_pool_label = $wrapper->get_label( 'cluster', $vm_pool_uuid );
      }
      else {
        $vm_pool_label = $vm_pool_uuid;
      }

      print $html_table_row->(
        $vm_pool_label, $vm_host_label, $cell_vm, "<div style=\"padding:4px 10px;\">$memory</div>",
        "<div style=\"padding:4px 10px;\">$cpu_count</div>", "<div style=\"padding:4px 10px;\">$vm_os</div>"
      );
    }

    print $html_tab_footer;
    print "</div>\n";

    # Storage tab
    print "<div id=\"tabs-3\">\n";

    print $html_tab_header->(
      'Host',               'Physical Disk',
      'Physical size [GB]', 'Type'
    );

    my $sr_config = NutanixDataWrapper::get_conf_section('spec-disk');
    my @sr_list   = keys %{$sr_config};

    unless ( scalar @sr_list > 0 ) {
      print "<tr><td colspan=\"4\" align=\"center\">no storages found</td></tr>";
    }
    foreach my $sr (@sr_list) {

      # get params
      my $sr_phys_size = exists $sr_config->{$sr}{physical_size} ? $sr_config->{$sr}{physical_size} : 'NA';
      my $sr_type      = exists $sr_config->{$sr}{type}          ? $sr_config->{$sr}{type}          : 'NA';

      my $host_link_url = NutanixMenu::get_url( { type => 'host', host => $sr_config->{$sr}{node_uuid} } );
      my $host_cell     = "<a href=\"$host_link_url\" class=\"backlink\">" . $wrapper->get_label( 'host', $sr_config->{$sr}{node_uuid} ) . "</a>";

      my $disk_link_url = NutanixMenu::get_url( { type => 'sr', sr => $sr } );
      my $disk_cell     = "<a href=\"$disk_link_url\" class=\"backlink\">" . $sr_config->{$sr}{label} . "</a>";

      print $html_table_row->( $host_cell, $disk_cell, "<div style=\"padding:4px 10px;\">$sr_phys_size</div>", "<div style=\"padding:4px 10px;\">$sr_type</div>" );
      next;

    }

    print $html_tab_footer;
    print "</div>\n";

    # VDisk Tab
    print "<div id=\"tabs-4\">\n";

    print $html_tab_header->( 'Virtual Disk', 'Capacity [GB]', 'Cluster', 'Storage Container', 'VM' );

    my $vd_config = NutanixDataWrapper::get_conf_section('spec-vdisk');

    my @vd_list = keys %{$vd_config};

    unless ( scalar @sr_list > 0 ) {
      print "<tr><td colspan=\"5\" align=\"center\">no storages found</td></tr>";
    }

    foreach my $vd (@vd_list) {
      my $vd_label    = exists $vd_config->{$vd}{label}                  ? $vd_config->{$vd}{label}                  : 'NA';
      my $vd_uuid     = exists $vd_config->{$vd}{uuid}                   ? $vd_config->{$vd}{uuid}                   : 'NA';
      my $vd_capacity = exists $vd_config->{$vd}{capacity_mb}            ? $vd_config->{$vd}{capacity_mb}            : 'NA';
      my $vd_vm       = exists $vd_config->{$vd}{attached_vmname}        ? $vd_config->{$vd}{attached_vmname}        : '<div style=\"padding:4px 10px;\">NA</div>';
      my $vd_vm_uuid  = exists $vd_config->{$vd}{attached_vm_uuid}       ? $vd_config->{$vd}{attached_vm_uuid}       : 'NA';
      my $vd_sc       = exists $vd_config->{$vd}{storage_container_uuid} ? $vd_config->{$vd}{storage_container_uuid} : 'NA';
      my $vd_pool     = exists $vd_config->{$vd}{cluster_uuid}           ? $vd_config->{$vd}{cluster_uuid}           : 'NA';

      my $vd_url = NutanixMenu::get_url( { type => 'vd', vd => $vd_uuid } );
      $vd_label = "<a href=\"$vd_url\" class=\"backlink\">$vd_label</a>";

      my $vd_pool_url = NutanixMenu::get_url( { type => 'pool-aggr', pool => $vd_pool } );
      $vd_pool = $wrapper->get_label( 'cluster', $vd_pool );
      $vd_pool = "<a href=\"$vd_pool_url\" class=\"backlink\">$vd_pool</a>";

      if ( defined $vd_sc ) {
        my $vd_sc_url = NutanixMenu::get_url( { type => 'sc', sc => $vd_sc } );
        $vd_sc = $wrapper->get_label( 'container', $vd_sc );
        $vd_sc = "<a href=\"$vd_sc_url\" class=\"backlink\">$vd_sc</a>";
      }
      else {
        $vd_sc = "<div style=\"padding:4px 10px;\">NA</div>";
      }
      if ( defined $vd_vm ) {
        my $vd_vm_url = NutanixMenu::get_url( { type => 'vm', vm => $vd_vm_uuid } );
        $vd_vm = "<a href=\"$vd_vm_url\" class=\"backlink\">$vd_vm</a>";
      }
      else {
        $vd_vm = "<div style=\"padding:4px 10px;\">NA</div>";
      }

      print $html_table_row->( $vd_label, "<div style=\"padding:4px 10px;\">$vd_capacity</div>", $vd_pool, $vd_sc, $vd_vm );

    }

    print $html_tab_footer;
    print "</div>\n";

    # SC Tab
    print "<div id=\"tabs-5\">\n";

    print $html_tab_header->( 'Storage Container', 'Capacity [GB]', 'Used [GB]', 'Free [GB]', 'Compression', 'Nutanix Management' );

    my $sc_config = NutanixDataWrapper::get_conf_section('spec-container');

    my @sc_list = keys %{$sc_config};

    unless ( scalar @sc_list > 0 ) {
      print "<tr><td colspan=\"6\" align=\"center\">no storage containers found</td></tr>";
    }

    foreach my $sc (@sc_list) {
      my $sc_label       = exists $sc_config->{$sc}{label}               ? $sc_config->{$sc}{label}               : 'NA';
      my $sc_uuid        = exists $sc_config->{$sc}{uuid}                ? $sc_config->{$sc}{uuid}                : 'NA';
      my $sc_capacity    = exists $sc_config->{$sc}{capacity_size}       ? $sc_config->{$sc}{capacity_size}       : 'NA';
      my $sc_used        = exists $sc_config->{$sc}{capacity_used}       ? $sc_config->{$sc}{capacity_used}       : 'NA';
      my $sc_free        = exists $sc_config->{$sc}{capacity_free}       ? $sc_config->{$sc}{capacity_free}       : 'NA';
      my $sc_compression = exists $sc_config->{$sc}{compression_enabled} ? $sc_config->{$sc}{compression_enabled} : 'NA';
      my $sc_management  = exists $sc_config->{$sc}{is_nutanix_managed}  ? $sc_config->{$sc}{is_nutanix_managed}  : 'NA';

      my $sc_url = NutanixMenu::get_url( { type => 'sc', sc => $sc_uuid } );
      $sc_label = "<a href=\"$sc_url\" class=\"backlink\">$sc_label</a>";

      if   ( defined $sc_management ) { $sc_management = "True"; }
      else                            { $sc_management = 'False'; }
      if   ( $sc_compression == 1 ) { $sc_compression = "True"; }
      else                          { $sc_compression = 'False'; }

      print $html_table_row->( $sc_label, "<div style=\"padding:4px 10px;\">$sc_capacity</div>", "<div style=\"padding:4px 10px;\">$sc_used</div>", "<div style=\"padding:4px 10px;\">$sc_free</div>", "<div style=\"padding:4px 10px;\">$sc_compression</div>", "<div style=\"padding:4px 10px;\">$sc_management</div>" );

    }

    print $html_tab_footer;
    print "</div>\n";

    # SP Tab
    print "<div id=\"tabs-6\">\n";

    print $html_tab_header->( 'Storage Pool', 'Cluster', 'Capacity [GB]', 'Used [GB]', 'Free [GB]' );

    my $sp_config = NutanixDataWrapper::get_conf_section('spec-pool');

    my @sp_list = keys %{$sp_config};

    unless ( scalar @sp_list > 0 ) {
      print "<tr><td colspan=\"5\" align=\"center\">no storage pools found</td></tr>";
    }

    foreach my $sp (@sp_list) {
      my $sp_label    = exists $sp_config->{$sp}{label}       ? $sp_config->{$sp}{label}       : 'NA';
      my $sp_uuid     = exists $sp_config->{$sp}{uuid}        ? $sp_config->{$sp}{uuid}        : 'NA';
      my $sp_capacity = exists $sp_config->{$sp}{capacity_gb} ? $sp_config->{$sp}{capacity_gb} : 'NA';
      my $sp_used     = exists $sp_config->{$sp}{used_gb}     ? $sp_config->{$sp}{used_gb}     : 'NA';
      my $sp_free     = exists $sp_config->{$sp}{free_gb}     ? $sp_config->{$sp}{free_gb}     : 'NA';
      my $sp_cluster  = exists $sp_config->{$sp}{cluster}     ? $sp_config->{$sp}{cluster}     : 'NA';

      #my $sp_disks       = exists $sp_config->{$sp}{disks}       ? $sp_config->{$sp}{disks}        : 'NA';

      my $cluster_url = NutanixMenu::get_url( { type => 'pool-aggr', pool => $sp_cluster } );
      $sp_cluster = $wrapper->get_label( 'cluster', $sp_cluster );
      $sp_cluster = "<a href=\"$cluster_url\" class=\"backlink\">$sp_cluster</a>";

      my $sp_url = NutanixMenu::get_url( { type => 'sp', sp => $sp_uuid } );
      $sp_label = "<a href=\"$sp_url\" class=\"backlink\">$sp_label</a>";

      my $disks = "";
      my $cc    = 0;

      #foreach (@{$sp_disks}) {
      #  my $disk = $_;
      #  my $disk_label = NutanixDataWrapper::get_label( 'sr', $disk );
      #  my $disk_url = NutanixMenu::get_url({ type => 'storage', storage => $disk });
      #  if ($cc == 0) { $disks .= "<a href=\"$disk_url\" class=\"backlink\" style=\"display:inline; padding:0; important!\">$disk_label</a>"; }
      #  else { $disks .= ", <a href=\"$disk_url\" class=\"backlink\" style=\"display:inline; padding:0; important!\">$disk_label</a>"; }
      #  $cc += 1;
      #}

      print $html_table_row->( $sp_label, $sp_cluster, "<div style=\"padding:4px 10px;\">$sp_capacity</div>", "<div style=\"padding:4px 10px;\">$sp_used</div>", "<div style=\"padding:4px 10px;\">$sp_free</div>" );

    }

    print $html_tab_footer;
    print "</div>\n";

  }
  elsif ( $params{type} =~ m/^topten_nutanix$/ ) {
    ############## LOAD TOPTEN FILE #####################
    my $topten_file_nutanix = "$tmpdir/topten_nutanix.tmp";
    my $last_update         = localtime( ( stat($topten_file_nutanix) )[9] );
    #####################################################
    my $server_pool = "";

    # last day
    print "<div id=\"tabs-1\">\n";
    print "<table align=\"center\" summary=\"Graphs\">\n";
    print "<tr><th align=center>CPU in cores<a class=\"csvfloat\" href=\"/lpar2rrd-cgi/top10_csv.sh?LPAR=$server_pool&host=CSV&type=NUTANIX&table=topten&item=load_cpu&period=1\" title=\"LOAD CPU CSV\"><img src=\"css/images/csv.gif\"></a></th><th align=center>CPU in %<a class=\"csvfloat\" href=\"/lpar2rrd-cgi/top10_csv.sh?LPAR=$server_pool&host=CSV&type=NUTANIX&table=topten&item=cpu_perc&period=1\" title=\"CPU in % CSV\"><img src=\"css/images/csv.gif\"></a></th><th align=center>IOPS<a class=\"csvfloat\" href=\"/lpar2rrd-cgi/top10_csv.sh?LPAR=$server_pool&host=CSV&type=NUTANIX&table=topten&item=iops&period=1\" title=\"IOPS CSV\"><img src=\"css/images/csv.gif\"></a></th><th align=center>NET in MB/sec<a class=\"csvfloat\" href=\"/lpar2rrd-cgi/top10_csv.sh?LPAR=$server_pool&host=CSV&type=NUTANIX&table=topten&item=net&period=1\" title=\"NET CSV\"><img src=\"css/images/csv.gif\"></a></th><th align=center>DATA in MB<a class=\"csvfloat\" href=\"/lpar2rrd-cgi/top10_csv.sh?LPAR=$server_pool&host=CSV&type=NUTANIX&table=topten&item=data&period=1\" title=\"DISK CSV\"><img src=\"css/images/csv.gif\"></a></th></tr>";
    print "<tr style=\"vertical-align:top\">";
    print_top10_to_table_nutanix( "1", "$server_pool", "load_cpu" );
    print_top10_to_table_nutanix( "1", "$server_pool", "cpu_perc" );
    print_top10_to_table_nutanix( "1", "$server_pool", "iops" );
    print_top10_to_table_nutanix( "1", "$server_pool", "net" );
    print_top10_to_table_nutanix( "1", "$server_pool", "data" );
    print "</tr>";
    print "</table>";
    print "<tfoot><tr><td colspan=\"6\">Last update time: $last_update</td></tr></tfoot>";
    print "</div>\n";

    # last week
    print "<div id=\"tabs-2\">\n";
    print "<table align=\"center\" summary=\"Graphs\">\n";
    print "<tr><th align=center>CPU in cores<a class=\"csvfloat\" href=\"/lpar2rrd-cgi/top10_csv.sh?LPAR=$server_pool&host=CSV&type=NUTANIX&table=topten&item=load_cpu&period=4\" title=\"LOAD CPU CSV\"><img src=\"css/images/csv.gif\"></a></th><th align=center>CPU in %<a class=\"csvfloat\" href=\"/lpar2rrd-cgi/top10_csv.sh?LPAR=$server_pool&host=CSV&type=NUTANIX&table=topten&item=cpu_perc&period=2\" title=\"CPU in % CSV\"><img src=\"css/images/csv.gif\"></a></th><th align=center>IOPS<a class=\"csvfloat\" href=\"/lpar2rrd-cgi/top10_csv.sh?LPAR=$server_pool&host=CSV&type=NUTANIX&table=topten&item=iops&period=2\" title=\"IOPS CSV\"><img src=\"css/images/csv.gif\"></a></th><th align=center>NET in MB/sec<a class=\"csvfloat\" href=\"/lpar2rrd-cgi/top10_csv.sh?LPAR=$server_pool&host=CSV&type=NUTANIX&table=topten&item=net&period=2\" title=\"NET CSV\"><img src=\"css/images/csv.gif\"></a></th><th align=center>DATA in MB<a class=\"csvfloat\" href=\"/lpar2rrd-cgi/top10_csv.sh?LPAR=$server_pool&host=CSV&type=NUTANIX&table=topten&item=data&period=2\" title=\"DISK CSV\"><img src=\"css/images/csv.gif\"></a></th></tr>";
    print "<tr style=\"vertical-align:top\">";
    print_top10_to_table_nutanix( "2", "$server_pool", "load_cpu" );
    print_top10_to_table_nutanix( "2", "$server_pool", "cpu_perc" );
    print_top10_to_table_nutanix( "2", "$server_pool", "iops" );
    print_top10_to_table_nutanix( "2", "$server_pool", "net" );
    print_top10_to_table_nutanix( "2", "$server_pool", "data" );
    print "</tr>";
    print "</table>";
    print "<tfoot><tr><td colspan=\"6\">Last update time: $last_update</td></tr></tfoot>";
    print "</div>\n";

    # last month
    print "<div id=\"tabs-3\">\n";
    print "<table align=\"center\" summary=\"Graphs\">\n";
    print "<tr><th align=center>CPU in cores<a class=\"csvfloat\" href=\"/lpar2rrd-cgi/top10_csv.sh?LPAR=$server_pool&host=CSV&type=NUTANIX&table=topten&item=load_cpu&period=4\" title=\"LOAD CPU CSV\"><img src=\"css/images/csv.gif\"></a></th><th align=center>CPU in %<a class=\"csvfloat\" href=\"/lpar2rrd-cgi/top10_csv.sh?LPAR=$server_pool&host=CSV&type=NUTANIX&table=topten&item=cpu_perc&period=3\" title=\"CPU in % CSV\"><img src=\"css/images/csv.gif\"></a></th><th align=center>IOPS<a class=\"csvfloat\" href=\"/lpar2rrd-cgi/top10_csv.sh?LPAR=$server_pool&host=CSV&type=NUTANIX&table=topten&item=iops&period=3\" title=\"IOPS CSV\"><img src=\"css/images/csv.gif\"></a></th><th align=center>NET in MB/sec<a class=\"csvfloat\" href=\"/lpar2rrd-cgi/top10_csv.sh?LPAR=$server_pool&host=CSV&type=NUTANIX&table=topten&item=net&period=3\" title=\"NET CSV\"><img src=\"css/images/csv.gif\"></a></th><th align=center>DATA in MB<a class=\"csvfloat\" href=\"/lpar2rrd-cgi/top10_csv.sh?LPAR=$server_pool&host=CSV&type=NUTANIX&table=topten&item=data&period=3\" title=\"DISK CSV\"><img src=\"css/images/csv.gif\"></a></th></tr>";
    print "<tr style=\"vertical-align:top\">";
    print_top10_to_table_nutanix( "3", "$server_pool", "load_cpu" );
    print_top10_to_table_nutanix( "3", "$server_pool", "cpu_perc" );
    print_top10_to_table_nutanix( "3", "$server_pool", "iops" );
    print_top10_to_table_nutanix( "3", "$server_pool", "net" );
    print_top10_to_table_nutanix( "3", "$server_pool", "data" );
    print "</tr>";
    print "</table>";
    print "<tfoot><tr><td colspan=\"6\">Last update time: $last_update</td></tr></tfoot>";
    print "</div>\n";

    # last year
    print "<div id=\"tabs-4\">\n";
    print "<table align=\"center\" summary=\"Graphs\">\n";
    print "<tr><th align=center>CPU in cores<a class=\"csvfloat\" href=\"/lpar2rrd-cgi/top10_csv.sh?LPAR=$server_pool&host=CSV&type=NUTANIX&table=topten&item=load_cpu&period=4\" title=\"LOAD CPU CSV\"><img src=\"css/images/csv.gif\"></a></th><th align=center>CPU in %<a class=\"csvfloat\" href=\"/lpar2rrd-cgi/top10_csv.sh?LPAR=$server_pool&host=CSV&type=NUTANIX&table=topten&item=cpu_perc&period=4\" title=\"CPU in % CSV\"><img src=\"css/images/csv.gif\"></a></th><th align=center>IOPS<a class=\"csvfloat\" href=\"/lpar2rrd-cgi/top10_csv.sh?LPAR=$server_pool&host=CSV&type=NUTANIX&table=topten&item=iops&period=4\" title=\"IOPS CSV\"><img src=\"css/images/csv.gif\"></a></th><th align=center>NET in MB/sec<a class=\"csvfloat\" href=\"/lpar2rrd-cgi/top10_csv.sh?LPAR=$server_pool&host=CSV&type=NUTANIX&table=topten&item=net&period=4\" title=\"NET CSV\"><img src=\"css/images/csv.gif\"></a></th><th align=center>DATA in MB<a class=\"csvfloat\" href=\"/lpar2rrd-cgi/top10_csv.sh?LPAR=$server_pool&host=CSV&type=NUTANIX&table=topten&item=data&period=4\" title=\"DISK CSV\"><img src=\"css/images/csv.gif\"></a></th></tr>";
    print "<tr style=\"vertical-align:top\">";
    print_top10_to_table_nutanix( "4", "$server_pool", "load_cpu" );
    print_top10_to_table_nutanix( "4", "$server_pool", "cpu_perc" );
    print_top10_to_table_nutanix( "4", "$server_pool", "iops" );
    print_top10_to_table_nutanix( "4", "$server_pool", "net" );
    print_top10_to_table_nutanix( "4", "$server_pool", "data" );
    print "</tr>";
    print "</table>";
    print "<tfoot><tr><td colspan=\"6\">Last update time: $last_update</td></tr></tfoot>";
    print "</div>\n";
  }

  sub print_top10_to_table_nutanix {
    my ( $period, $server_pool, $item_name ) = @_;
    my $topten_file_nutanix = "$tmpdir/topten_nutanix.tmp";
    my $html_tab_header     = sub {
      my @columns = @_;
      my $result  = '';
      $result .= "<center>";
      $result .= "<table style=\"white-space: nowrap;\" class=\"tabconfig tablesorter \" data-sortby='1'>";
      $result .= "<thead><tr>";
      foreach my $item (@columns) {
        $result .= "<th class=\"sortable\">" . $item . "</th>";
      }
      $result .= "</tr></thead>";
      $result .= "<tbody>";
      return $result;
    };
    my $html_table_row = sub {
      my @cells  = @_;
      my $result = '';

      $result .= "<tr>";
      foreach my $cell (@cells) { $result .= "<td>" . $cell . "</td>"; }
      $result .= "</tr>";

      return $result;
    };

    # Table or create CSV file
    my $csv_file;
    if ( $item_name eq "load_cpu" ) {
      $csv_file = "nutanix-load-cpu.csv";
    }
    elsif ( $item_name eq "cpu_perc" ) {
      $csv_file = "nutanix-cpu-perc.csv";
    }
    elsif ( $item_name eq "net" ) {
      $csv_file = "nutanix-net.csv";
    }
    elsif ( $item_name eq "data" ) {
      $csv_file = "nutanix-disk.csv";
    }
    elsif ( $item_name eq "iops" ) {
      $csv_file = "nutanix-iops.csv";
    }
    if ( !$csv ) {
      print "<TD><TABLE class=\"tabconfig tablesorter\" data-sortby=\"1\">";
      if ( $period == 4 ) {    # last year
        print $html_tab_header->( 'Avrg', "VM", 'Cluster' );
      }
      else {
        print $html_tab_header->( 'Avrg', 'Max', "VM", 'Cluster' );
      }
    }
    else {
      print "Content-Disposition: attachment;filename=\"$csv_file\"\n\n";
      my $csv_header;
      if ( $period == 4 ) {    # last year
        $csv_header = "Avrg" . "$sep" . "VM" . "$sep" . "Cluster\n";
      }
      else {
        $csv_header = "Avrg" . "$sep" . "Max" . "$sep" . "VM" . "$sep" . "Cluster\n";
      }
      print "$csv_header";
    }
    my @topten;
    my @topten_not_sorted;
    my @topten_sorted;
    my $topten_limit = 0;
    my @top_values_avrg;
    my @top_values_max;
    if ( -f $topten_file_nutanix ) {
      open( FH, " < $topten_file_nutanix" ) || error( "Cannot open $topten_file_nutanix: $!" . __FILE__ . ":" . __LINE__ );
      @topten = <FH>;
      close FH;
      if ( defined $ENV{TOPTEN} ) {
        $topten_limit = $ENV{TOPTEN};
      }
      $topten_limit = 50 if $topten_limit < 1;
      my @topten_server;
      if ( $item_name eq "load_cpu" ) {
        @topten_server = grep {/load_cpu,/} @topten;
      }
      if ( $item_name eq "cpu_perc" ) {
        @topten_server = grep {/cpu_perc,/} @topten;
      }
      elsif ( $item_name eq "iops" ) {
        @topten_server = grep {/iops,/} @topten;
      }
      elsif ( $item_name eq "net" ) {
        @topten_server = grep {/net,/} @topten;
      }
      elsif ( $item_name eq "data" ) {
        @topten_server = grep {/data,/} @topten;
      }
      @topten = @topten_server;
      foreach my $line (@topten) {
        chomp $line;
        my ( $item, $vm_name, $location );
        ( $item, $vm_name, $location, $top_values_avrg[1], $top_values_max[1], $top_values_avrg[2], $top_values_max[2], $top_values_avrg[3], $top_values_max[3], $top_values_avrg[4], $top_values_max[4] ) = split( ",", $line );
        $top_values_avrg[4] = 0 if !defined $top_values_avrg[4] or $top_values_avrg[4] eq "";    # no year value yet, new file
        $top_values_max[4]  = 0 if !defined $top_values_max[4]  or $top_values_max[4] eq "";     # no year value yet, new file
        if ( $top_values_avrg[1] == 0 && $top_values_max[1] == 0 && $top_values_avrg[2] == 0 && $top_values_max[2] == 0 && $top_values_avrg[3] == 0 && $top_values_max[3] == 0 && $top_values_avrg[4] == 0 && $top_values_max[4] == 0 ) { next; }
        push @topten_not_sorted, "$item,$top_values_avrg[$period],$top_values_max[$period],$vm_name,$location\n";
      }
      {
        no warnings;
        @topten_sorted = sort { $b <=> $a } @topten_not_sorted;
      }
    }
    my @topten_sorted_load_cpu;
    {
      no warnings;
      @topten_sorted_load_cpu = sort {
        my @b = split( /,/, $b );
        my @a = split( /,/, $a );

        #print "$b[4] --- $a[4]\n";
        $b[1] <=> $a[1]
      } @topten_sorted;
    }
    foreach my $line1 (@topten_sorted_load_cpu) {
      my ( $item_a, $load_cpu, $load_peak, $vm_name, $location );
      ( $item_a, $load_cpu, $load_peak, $vm_name, $location ) = split( ",", $line1 );

      #print STDERR"$item_a, $load_cpu, $load_peak, $vm_name, $uuid\n";
      if ( !$csv ) {
        if ( $period == 4 ) {    # last year
          print $html_table_row->( $load_cpu, $vm_name, $location );
        }
        else {
          print $html_table_row->( $load_cpu, $load_peak, $vm_name, $location );
        }
      }
      else {
        if ( $period == 4 ) {    # last year
          print "$load_cpu" . "$sep" . "$vm_name" . "$sep" . "$location";
        }
        else {
          print "$load_cpu" . "$sep" . "$load_peak" . "$sep" . "$vm_name" . "$sep" . "$location";
        }
      }
    }
    if ( !$csv ) {
      print "</TABLE></TD>";
    }
    return 1;
  }

  # closing page contents
  print "</CENTER>";
  print "</div><br>\n";

  exit(0);
}

# AWS
if ($aws) {

  # TODO temporary wrapper for compatibility with legacy subroutines interfacing mainly detail-graph-cgi.pl
  $host_url = 'AWS';

  #print "<script>console.log('type: $params{type}, id: $params{id}');</script>";
  if ( $params{type} =~ m/ec2-aggr/ || $params{type} =~ m/ebs-aggr/ || $params{type} =~ m/rds-aggr/ || $params{type} =~ m/api-aggr/ || $params{type} =~ m/lambda-aggr/ ) {
    $server_url = $params{id};
    $lpar_url   = 'nope';
  }
  elsif ( $params{type} =~ m/ec2/ || $params{type} =~ m/ebs/ || $params{type} =~ m/rds/ || $params{type} =~ m/api/ || $params{type} =~ m/lambda/ ) {
    $server_url = $params{id};
    $lpar_url   = $params{id};
  }
  else {
    $lpar_url   = 'nope';
    $server_url = 'nope';
  }

  # print page contents
  print "<CENTER>";

  # get tabs
  my @tabs = @{ AWSMenu::get_tabs( $params{type} ) };

  if (@tabs) {
    print "<div id=\"tabs\">\n";
    print "<ul>\n";

    my $tab_counter = 1;
    foreach my $tab_header (@tabs) {
      while ( my ( $tab_type, $tab_label ) = each %$tab_header ) {
        print "  <li class=\"$tab_type\"><a href=\"#tabs-$tab_counter\">$tab_label</a></li>\n";
        $tab_counter++;
      }
    }

    print "</ul>\n";
  }

  # print tab contents
  sub print_tab_contents_aws {
    my ( $tab_number, $host_url, $server_url, $lpar_url, $item, $entitle, $detail_yes, $legend ) = @_;

    print "<div id=\"tabs-$tab_number\">\n";
    print "<table border=\"0\">\n";
    print "<tr>";

    print_item( $host_url, $server_url, $lpar_url, $item, "d", "", $entitle, $detail_yes, "norefr", "star", 1, $legend );
    print_item( $host_url, $server_url, $lpar_url, $item, "w", "", $entitle, $detail_yes, "norefr", "star", 1, $legend );
    print "</tr>\n<tr>\n";
    print_item( $host_url, $server_url, $lpar_url, $item, "m", "", $entitle, $detail_yes, "norefr", "star", 1, $legend );
    print_item( $host_url, $server_url, $lpar_url, $item, "y", "", $entitle, $detail_yes, "norefr", "star", 1, $legend );
    print "</tr></table>";
    print "</div>\n";
  }
  my $legend = ( $params{type} =~ m/aggr/ ) ? 'nolegend' : 'legend';
  if ( $params{type} =~ m/^ec2$/ || $params{type} =~ m/^ec2-aggr$/ ) {
    my @aws_items = ( 'aws-ec2-cpu-cores', 'aws-ec2-cpu-percent', 'aws-ec2-data', 'aws-ec2-iops', 'aws-ec2-net' );
    for $tab_number ( 1 .. $#aws_items + 1 ) {
      my $aws_item = $aws_items[ $tab_number - 1 ];
      if ( $params{type} =~ m/-aggr$/ ) { $aws_item .= '-aggr'; }
      print_tab_contents_aws( $tab_number, $host_url, $server_url, $lpar_url, $aws_item, $entitle, $detail_yes, $legend );
    }
  }
  elsif ( $params{type} =~ m/^ebs$/ || $params{type} =~ m/^ebs-aggr$/ ) {
    my @aws_items = ( 'aws-ebs-data', 'aws-ebs-iops' );
    for $tab_number ( 1 .. $#aws_items + 1 ) {
      my $aws_item = $aws_items[ $tab_number - 1 ];
      if ( $params{type} =~ m/-aggr$/ ) { $aws_item .= '-aggr'; }
      print_tab_contents_aws( $tab_number, $host_url, $server_url, $lpar_url, $aws_item, $entitle, $detail_yes, $legend );
    }
  }
  elsif ( $params{type} =~ m/^rds$/ || $params{type} =~ m/^rds-aggr$/ ) {
    my @aws_items = ( 'aws-rds-cpu-percent', 'aws-rds-db-connection', 'aws-rds-mem-free', 'aws-rds-disk-free', 'aws-rds-data', 'aws-rds-iops', 'aws-rds-net', 'aws-rds-latency' );
    for $tab_number ( 1 .. $#aws_items + 1 ) {
      my $aws_item = $aws_items[ $tab_number - 1 ];
      if ( $params{type} =~ m/-aggr$/ ) { $aws_item .= '-aggr'; }
      print_tab_contents_aws( $tab_number, $host_url, $server_url, $lpar_url, $aws_item, $entitle, $detail_yes, $legend );
    }
  }
  elsif ( $params{type} =~ m/^api$/ || $params{type} =~ m/^api-aggr$/ ) {
    my @aws_items = ( 'aws-api-count', 'aws-api-five', 'aws-api-four', 'aws-api-latency', 'aws-api-integration-latency' );
    for $tab_number ( 1 .. $#aws_items + 1 ) {
      my $aws_item = $aws_items[ $tab_number - 1 ];
      if ( $params{type} =~ m/-aggr$/ ) { $aws_item .= '-aggr'; }
      print_tab_contents_aws( $tab_number, $host_url, $server_url, $lpar_url, $aws_item, $entitle, $detail_yes, $legend );
    }
  }
  elsif ( $params{type} =~ m/^lambda$/ || $params{type} =~ m/^lambda-aggr$/ ) {
    my @aws_items = ( 'aws-lambda-invocations', 'aws-lambda-errors', 'aws-lambda-duration', 'aws-lambda-throttles', 'aws-lambda-concurrent-executions' );
    for $tab_number ( 1 .. $#aws_items + 1 ) {
      my $aws_item = $aws_items[ $tab_number - 1 ];
      if ( $params{type} =~ m/-aggr$/ ) { $aws_item .= '-aggr'; }
      print_tab_contents_aws( $tab_number, $host_url, $server_url, $lpar_url, $aws_item, $entitle, $detail_yes, $legend );
    }
  }
  elsif ( $params{type} =~ m/^region-aggr$/ ) {
    my @aws_items = ( 'aws-ec2-overview', 'aws-region-running-aggr', 'aws-region-stopped-aggr' );
    for $tab_number ( 1 .. $#aws_items + 1 ) {
      my $aws_item = $aws_items[ $tab_number - 1 ];
      if ( $aws_item eq "aws-ec2-overview" ) {

        my $html_tab_header = sub {
          my @columns = @_;
          my $result  = '';

          $result .= "<center>";
          $result .= "<table class=\"tabconfig tablesorter\">";
          $result .= "<thead><tr>";
          foreach my $item (@columns) {
            $result .= "<th class=\"sortable\">" . $item . "</th>";
          }
          $result .= "</tr></thead>";
          $result .= "<tbody>";

          return $result;
        };

        my $html_table_row = sub {
          my @cells  = @_;
          my $result = '';

          $result .= "<tr>";
          foreach my $cell (@cells) { $result .= $cell; }
          $result .= "</tr>";

          return $result;
        };
        my $config_update_time = localtime( AWSDataWrapper::get_conf_update_time() );

        my $html_tab_footer = "</tbody></table><p>Last update time: " . $config_update_time . "</p></center>";

        print "<div id=\"tabs-$tab_number\">\n";
        print "<h2>Elastic Compute Cloud Overview</h2>";

        print $html_tab_header->( 'Region', 'Running', 'Stopped' );

        my $config_region = AWSDataWrapper::get_conf_section('spec-region');

        foreach my $regionKey ( %{$config_region} ) {
          if ( !defined $config_region->{$regionKey}->{running} ) {
            next;
          }
          print $html_table_row->( "<td><div style=\"padding:4px 10px;\">$regionKey</div></td>", "<td><div style=\"padding:4px 10px;\">$config_region->{$regionKey}->{running}</div></td>", "<td><div style=\"padding:4px 10px;\">$config_region->{$regionKey}->{stopped}</div></td>" );
        }

        print $html_tab_footer;

        print "</div>";
      }
      else {
        print_tab_contents_aws( $tab_number, $host_url, $server_url, $lpar_url, $aws_item, $entitle, $detail_yes, 'nolegend' );
      }
    }
  }
  elsif ( $params{type} =~ m/^health$/ ) {
    my $config_update_time = localtime( AWSDataWrapper::get_conf_update_time() );

    my $html_tab_header = sub {
      my @columns = @_;
      my $result  = '';

      $result .= "<center>";
      $result .= "<table class=\"tabconfig tablesorter\">";
      $result .= "<thead><tr>";
      foreach my $item (@columns) {
        $result .= "<th class=\"sortable\">" . $item . "</th>";
      }
      $result .= "</tr></thead>";
      $result .= "<tbody>";

      return $result;
    };

    my $html_table_row = sub {
      my @cells  = @_;
      my $result = '';

      $result .= "<tr>";
      foreach my $cell (@cells) { $result .= $cell; }
      $result .= "</tr>";

      return $result;
    };

    my $html_tab_footer = "</tbody></table></center><br>";

    print "<h4>Elastic Compute Cloud</h4>";

    print $html_tab_header->( 'Instance ID', 'Name', 'State', 'Reason' );

    my $config_ec2 = AWSDataWrapper::get_conf_section('spec-ec2');

    my @ec2_list = keys %{$config_ec2};

    my $reason;
    my $state;

    foreach my $ec2 (@ec2_list) {
      if ( defined $config_ec2->{$ec2}{StateReason} ) {
        $reason = $config_ec2->{$ec2}{StateReason};
      }
      else {
        $reason = "-";
      }
      if ( $config_ec2->{$ec2}{State} eq "running" ) {
        $state = "<td class=\"hs_good\"><div style=\"padding:4px 10px;\">$config_ec2->{$ec2}{State}</div></td>";
      }
      elsif ( $config_ec2->{$ec2}{State} eq "stopped" ) {
        $state = "<td class=\"hs_warning\"><div style=\"padding:4px 10px;\">$config_ec2->{$ec2}{State}</div></td>";
      }
      else {
        $state = "<td class=\"hs_error\"><div style=\"padding:4px 10px;\">$config_ec2->{$ec2}{State}</div></td>";
      }
      print $html_table_row->( "<td><div style=\"padding:4px 10px;\">$ec2</div></td>", "<td><div style=\"padding:4px 10px;\">$config_ec2->{$ec2}{Name}</div></td>", "$state", "<td><div style=\"padding:4px 10px;\">$reason</div></td>" );
    }

    print $html_tab_footer;

    print "<h4>Elastic Block Store</h4>";

    print $html_tab_header->( 'Volume ID', 'Name', 'State' );

    my $config_ebs = AWSDataWrapper::get_conf_section('spec-volume');

    my @ebs_list = keys %{$config_ebs};

    foreach my $ebs (@ebs_list) {
      if ( $config_ebs->{$ebs}{State} eq "in-use" ) {
        $state = "<td class=\"hs_good\"><div style=\"padding:4px 10px;\">$config_ebs->{$ebs}{State}</div></td>";
      }
      elsif ( $config_ebs->{$ebs}{State} eq "available" ) {
        $state = "<td class=\"hs_good\"><div style=\"padding:4px 10px;\">$config_ebs->{$ebs}{State}</div></td>";
      }
      else {
        $state = "<td class=\"hs_error\"><div style=\"padding:4px 10px;\">$config_ebs->{$ebs}{State}</div></td>";
      }
      print $html_table_row->( "<td><div style=\"padding:4px 10px;\">$ebs</div></td>", "<td><div style=\"padding:4px 10px;\"> - </div></td>", "$state" );
    }

    print $html_tab_footer;

  }
  elsif ( $params{type} =~ m/^configuration$/ ) {
    my $config_update_time = localtime( AWSDataWrapper::get_conf_update_time() );

    my $html_tab_header = sub {
      my @columns = @_;
      my $result  = '';

      $result .= "<center>";
      $result .= "<table class=\"tabconfig tablesorter\">";
      $result .= "<thead><tr>";
      foreach my $item (@columns) {
        $result .= "<th class=\"sortable\">" . $item . "</th>";
      }
      $result .= "</tr></thead>";
      $result .= "<tbody>";

      return $result;
    };

    my $html_table_row = sub {
      my @cells  = @_;
      my $result = '';

      $result .= "<tr>";
      foreach my $cell (@cells) { $result .= "<td>" . $cell . "</td>"; }
      $result .= "</tr>";

      return $result;
    };

    my $html_tab_footer = "</tbody></table><p>Last update time: " . $config_update_time . "</p></center>";

    #HERE IS CONF

    # EC2 Tab
    print "<div id=\"tabs-1\">\n";

    print "<h2>Elastic Compute Cloud</h2>";

    print $html_tab_header->( 'Region', 'Instance ID', 'Name', 'IP Adress', 'Public DNS', 'Type', 'Hypervisor', 'Virtualization', 'Launch Time' );

    my $config_ec2 = AWSDataWrapper::get_conf_section('spec-ec2');

    my @ec2_list = keys %{$config_ec2};

    unless ( scalar @ec2_list > 0 ) {
      print "<tr><td colspan=\"9\" align=\"center\">no ec2 found</td></tr>";
    }

    foreach my $ec2 (@ec2_list) {
      print $html_table_row->( "<div style=\"padding:4px 10px;\">$config_ec2->{$ec2}{Zone}</div>", "<div style=\"padding:4px 10px;\">$ec2</div>", "<div style=\"padding:4px 10px;\">$config_ec2->{$ec2}{Name}</div>", "<div style=\"padding:4px 10px;\">$config_ec2->{$ec2}{PrivateIpAddress}</div>", "<div style=\"padding:4px 10px;\">$config_ec2->{$ec2}{PublicDnsName}</div>", "<div style=\"padding:4px 10px;\">$config_ec2->{$ec2}{InstanceType}</div>", "<div style=\"padding:4px 10px;\">$config_ec2->{$ec2}{Hypervisor}</div>", "<div style=\"padding:4px 10px;\">$config_ec2->{$ec2}{VirtualizationType}</div>", "<div style=\"padding:4px 10px;\">$config_ec2->{$ec2}{LaunchTime}</div>" );
    }

    print $html_tab_footer;

    print "</div>\n";

    # Volumes Tab
    print "<div id=\"tabs-2\">\n";

    print "<h2>Elastic Block Store</h2>";

    print $html_tab_header->( 'Region', 'Volume ID', 'Size', 'State', 'Type' );

    my $config_volume = AWSDataWrapper::get_conf_section('spec-volume');

    my @volume_list = keys %{$config_volume};

    unless ( scalar @ec2_list > 0 ) {
      print "<tr><td colspan=\"5\" align=\"center\">no volumes found</td></tr>";
    }

    foreach my $volume (@volume_list) {
      print $html_table_row->( "<div style=\"padding:4px 10px;\">$config_volume->{$volume}{Zone}</div>", "<div style=\"padding:4px 10px;\">$volume</div>", "<div style=\"padding:4px 10px;\">$config_volume->{$volume}{Size} GB</div>", "<div style=\"padding:4px 10px;\">$config_volume->{$volume}{State}</div>", "<div style=\"padding:4px 10px;\">$config_volume->{$volume}{VolumeType}</div>" );
    }

    print $html_tab_footer;

    print "</div>\n";

    # RDS Tab
    print "<div id=\"tabs-3\">\n";

    print "<h2>Relational Database Service</h2>";

    print $html_tab_header->( 'Region', 'Instance ID', 'Name', 'Engine', 'Class', 'Storage Type', 'Storage' );

    my $config_rds = AWSDataWrapper::get_conf_section('spec-rds');

    my @rds_list = keys %{$config_rds};

    unless ( scalar @rds_list > 0 ) {
      print "<tr><td colspan=\"7\" align=\"center\">no rds found</td></tr>";
    }

    foreach my $rds (@rds_list) {
      print $html_table_row->( "<div style=\"padding:4px 10px;\">$config_rds->{$rds}{zone}</div>", "<div style=\"padding:4px 10px;\">$rds</div>", "<div style=\"padding:4px 10px;\">$config_rds->{$rds}{name}</div>", "<div style=\"padding:4px 10px;\">$config_rds->{$rds}{engine}</div>", "<div style=\"padding:4px 10px;\">$config_rds->{$rds}{class}</div>", "<div style=\"padding:4px 10px;\">$config_rds->{$rds}{storageType}</div>", "<div style=\"padding:4px 10px;\">$config_rds->{$rds}{storage} GB</div>" );
    }

    print $html_tab_footer;

    print "</div>\n";

    # API Tab
    print "<div id=\"tabs-4\">\n";

    print "<h2>API Gateway</h2>";

    print $html_tab_header->( 'Region', 'API ID', 'Name', 'Source Key', 'Description' );

    my $config_api = AWSDataWrapper::get_conf_section('spec-api');

    my @api_list = keys %{$config_api};

    unless ( scalar @api_list > 0 ) {
      print "<tr><td colspan=\"5\" align=\"center\">no api found</td></tr>";
    }

    foreach my $api (@api_list) {
      print $html_table_row->( "<div style=\"padding:4px 10px;\">$config_api->{$api}{region}</div>", "<div style=\"padding:4px 10px;\">$api</div>", "<div style=\"padding:4px 10px;\">$config_api->{$api}{name}</div>", "<div style=\"padding:4px 10px;\">$config_api->{$api}{sourceKey}</div>", "<div style=\"padding:4px 10px;\">$config_api->{$api}{description}</div>" );
    }

    print $html_tab_footer;

    print "</div>\n";

    # Lambda Tab
    print "<div id=\"tabs-5\">\n";

    print "<h2>Lambda</h2>";

    print $html_tab_header->( 'Region', 'Lambda ID', 'Name', 'Handler', 'Runtime', 'Memory' );

    my $config_lambda = AWSDataWrapper::get_conf_section('spec-lambda');

    my @lambda_list = keys %{$config_lambda};

    unless ( scalar @lambda_list > 0 ) {
      print "<tr><td colspan=\"6\" align=\"center\">no lambda found</td></tr>";
    }

    foreach my $lambda (@lambda_list) {
      print $html_table_row->( "<div style=\"padding:4px 10px;\">$config_lambda->{$lambda}{region}</div>", "<div style=\"padding:4px 10px;\">$lambda</div>", "<div style=\"padding:4px 10px;\">$config_lambda->{$lambda}{name}</div>", "<div style=\"padding:4px 10px;\">$config_lambda->{$lambda}{handler}</div>", "<div style=\"padding:4px 10px;\">$config_lambda->{$lambda}{runtime}</div>", "<div style=\"padding:4px 10px;\">$config_lambda->{$lambda}{memory}</div>" );
    }

    print $html_tab_footer;

    print "</div>\n";

  }

  # closing page contents
  print "</CENTER>";
  print "</div><br>\n";

  exit(0);
}

# GCloud
if ($gcloud) {

  # TODO temporary wrapper for compatibility with legacy subroutines interfacing mainly detail-graph-cgi.pl
  $host_url = 'GCloud';

  #print "<script>console.log('type: $params{type}, id: $params{id}');</script>";
  if ( $params{type} =~ m/compute-aggr/ ) {
    $server_url = $params{id};
    $lpar_url   = 'nope';
  }
  elsif ( $params{type} =~ m/compute/ || $params{type} =~ m/database/ ) {
    $server_url = $params{id};
    $lpar_url   = $params{id};
  }
  elsif ( $params{type} =~ m/running/ || $params{type} =~ m/stopped/ ) {
    $lpar_url   = 'nope';
    $server_url = 'nope';
  }
  else {
    $lpar_url   = 'nope';
    $server_url = 'nope';
  }

  # print page contents
  print "<CENTER>";

  # get tabs
  my @tabs = @{ GCloudMenu::get_tabs( $params{type} ) };

  if (@tabs) {
    print "<div id=\"tabs\">\n";
    print "<ul>\n";

    my $tab_counter = 1;
    foreach my $tab_header (@tabs) {
      while ( my ( $tab_type, $tab_label ) = each %$tab_header ) {
        print "  <li class=\"$tab_type\"><a href=\"#tabs-$tab_counter\">$tab_label</a></li>\n";
        $tab_counter++;
      }
    }

    print "</ul>\n";
  }

  # print tab contents
  sub print_tab_contents_gcloud {
    my ( $tab_number, $host_url, $server_url, $lpar_url, $item, $entitle, $detail_yes, $legend ) = @_;

    print "<div id=\"tabs-$tab_number\">\n";
    print "<table border=\"0\">\n";
    print "<tr>";

    print_item( $host_url, $server_url, $lpar_url, $item, "d", "", $entitle, $detail_yes, "norefr", "star", 1, $legend );
    print_item( $host_url, $server_url, $lpar_url, $item, "w", "", $entitle, $detail_yes, "norefr", "star", 1, $legend );
    print "</tr>\n<tr>\n";
    print_item( $host_url, $server_url, $lpar_url, $item, "m", "", $entitle, $detail_yes, "norefr", "star", 1, $legend );
    print_item( $host_url, $server_url, $lpar_url, $item, "y", "", $entitle, $detail_yes, "norefr", "star", 1, $legend );
    print "</tr></table>";
    print "</div>\n";
  }

  my $config_agent = GCloudDataWrapper::get_conf_section('spec-agent');
  my $show_agent   = 0;

  my $legend = ( $params{type} =~ m/aggr/ ) ? 'nolegend' : 'legend';
  if ( $params{type} =~ m/^compute$/ || $params{type} =~ m/^compute-aggr$/ ) {
    my @gcloud_items;
    if ( $params{type} =~ m/^compute-aggr$/ ) {
      @gcloud_items = ( 'gcloud-compute-cpu-percent', 'gcloud-compute-data', 'gcloud-compute-iops', 'gcloud-compute-net', 'gcloud-compute-mem-free', 'gcloud-compute-mem-used' );
      my @vms = @{ GCloudDataWrapper::get_items( { item_type => 'compute', parent_type => 'region', parent_id => $server_url } ) };
      foreach my $vm (@vms) {
        my ( $vm_uuid, $vm_label ) = each %{$vm};
        if ( exists $config_agent->{$vm_uuid} && $config_agent->{$vm_uuid} eq "1" ) {
          $show_agent = 1;
        }
      }
    }
    else {
      @gcloud_items = ( 'gcloud-compute-cpu-percent', 'gcloud-compute-data', 'gcloud-compute-iops', 'gcloud-compute-net', 'gcloud-compute-mem', 'gcloud-compute-proc' );
    }
    for $tab_number ( 1 .. $#gcloud_items + 1 ) {
      my $gcloud_item = $gcloud_items[ $tab_number - 1 ];
      if ( $params{type} =~ m/-aggr$/ ) { $gcloud_item .= '-aggr'; }
      if ( ( ( !defined $config_agent->{$lpar_url} || $config_agent->{$lpar_url} ne "1" ) && ( $gcloud_item eq "gcloud-compute-mem" || $gcloud_item eq "gcloud-compute-proc" ) ) || ( $show_agent ne "1" && ( $gcloud_item eq "gcloud-compute-mem-free-aggr" || $gcloud_item eq "gcloud-compute-mem-used-aggr" ) ) ) {
        print "<div id=\"tabs-$tab_number\">\n";
        print "<h2>Google Cloud agent is not installed!</h2>";
        print "Link: <a href=\"https://cloud.google.com/monitoring/agent\">Cloud Monitoring agent overview</a>";
        print "</div>";
      }
      else {
        print_tab_contents_gcloud( $tab_number, $host_url, $server_url, $lpar_url, $gcloud_item, $entitle, $detail_yes, $legend );
      }
    }
  }
  elsif ( $params{type} =~ m/^database-mysql$/ || $params{type} =~ m/^database-mysql-aggr$/ ) {
    my @gcloud_items = ( 'gcloud-database-cpu-percent', 'gcloud-database-iops', 'gcloud-database-net', 'gcloud-database-mem', 'gcloud-database-storage', 'gcloud-database-connections', 'gcloud-database-queries', 'gcloud-database-questions', 'gcloud-database-innodb-pages', 'gcloud-database-innodb-buffer', 'gcloud-database-innodb-data', 'gcloud-database-innodb-log' );
    for $tab_number ( 1 .. $#gcloud_items + 1 ) {
      my $gcloud_item = $gcloud_items[ $tab_number - 1 ];
      if ( $params{type} =~ m/-aggr$/ ) { $gcloud_item .= '-aggr'; }
      print_tab_contents_gcloud( $tab_number, $host_url, $server_url, $lpar_url, $gcloud_item, $entitle, $detail_yes, $legend );
    }
  }
  elsif ( $params{type} =~ m/^database-postgres$/ || $params{type} =~ m/^database-postgres-aggr$/ ) {
    my @gcloud_items = ( 'gcloud-database-cpu-percent', 'gcloud-database-iops', 'gcloud-database-net', 'gcloud-database-mem', 'gcloud-database-storage', 'gcloud-database-connections', 'gcloud-database-transactions' );
    for $tab_number ( 1 .. $#gcloud_items + 1 ) {
      my $gcloud_item = $gcloud_items[ $tab_number - 1 ];
      if ( $params{type} =~ m/-aggr$/ ) { $gcloud_item .= '-aggr'; }
      print_tab_contents_gcloud( $tab_number, $host_url, $server_url, $lpar_url, $gcloud_item, $entitle, $detail_yes, $legend );
    }
  }
  elsif ( $params{type} =~ m/^engine-running$/ ) {
    my @gcloud_items = ( 'gcloud-compute-overview', 'gcloud-compute-running-aggr', 'gcloud-compute-stopped-aggr' );
    for $tab_number ( 1 .. $#gcloud_items + 1 ) {
      my $gcloud_item = $gcloud_items[ $tab_number - 1 ];
      if ( $gcloud_item eq "gcloud-compute-overview" ) {

        my $html_tab_header = sub {
          my @columns = @_;
          my $result  = '';

          $result .= "<center>";
          $result .= "<table class=\"tabconfig tablesorter\">";
          $result .= "<thead><tr>";
          foreach my $item (@columns) {
            $result .= "<th class=\"sortable\">" . $item . "</th>";
          }
          $result .= "</tr></thead>";
          $result .= "<tbody>";

          return $result;
        };

        my $html_table_row = sub {
          my @cells  = @_;
          my $result = '';

          $result .= "<tr>";
          foreach my $cell (@cells) { $result .= $cell; }
          $result .= "</tr>";

          return $result;
        };

        my $config_update_time = localtime( GCloudDataWrapper::get_conf_update_time() );

        my $html_tab_footer = "</tbody></table><p>Last update time: " . $config_update_time . "</p></center>";

        print "<div id=\"tabs-$tab_number\">\n";
        print "<h2>Compute Engine Overview</h2>";

        print $html_tab_header->( 'Region', 'Running', 'Stopped' );

        my $config_region = GCloudDataWrapper::get_conf_section('spec-region');

        foreach my $regionKey ( %{$config_region} ) {
          if ( !defined $config_region->{$regionKey}->{running} ) {
            next;
          }
          print $html_table_row->( "<td><div style=\"padding:4px 10px;\">$regionKey</div></td>", "<td><div style=\"padding:4px 10px;\">$config_region->{$regionKey}->{running}</div></td>", "<td><div style=\"padding:4px 10px;\">$config_region->{$regionKey}->{stopped}</div></td>" );
        }

        print $html_tab_footer;

        print "</div>";
      }
      else {
        print_tab_contents_gcloud( $tab_number, $host_url, $server_url, $lpar_url, $gcloud_item, $entitle, $detail_yes, 'nolegend' );
      }
    }
  }
  elsif ( $params{type} =~ m/^configuration$/ ) {
    my $config_update_time = localtime( GCloudDataWrapper::get_conf_update_time() );

    my $html_tab_header = sub {
      my @columns = @_;
      my $result  = '';

      $result .= "<center>";
      $result .= "<table class=\"tabconfig tablesorter\">";
      $result .= "<thead><tr>";
      foreach my $item (@columns) {
        $result .= "<th class=\"sortable\">" . $item . "</th>";
      }
      $result .= "</tr></thead>";
      $result .= "<tbody>";

      return $result;
    };

    my $html_table_row = sub {
      my @cells  = @_;
      my $result = '';

      $result .= "<tr>";
      foreach my $cell (@cells) { $result .= $cell; }
      $result .= "</tr>";

      return $result;
    };

    my $html_tab_footer = "</tbody></table><p>Last update time: " . $config_update_time . "</p></center>";

    # Compute
    print "<div id=\"tabs-1\">\n";

    print "<h2>Compute Engine</h2>";

    print $html_tab_header->( 'Instance ID', 'Name', 'Region', 'State', 'Agent', 'CPU Platform', 'IP', 'Instance Size', 'Disks Size', 'Created' );

    my $config_compute = GCloudDataWrapper::get_conf_section('spec-compute');
    my $config_agent   = GCloudDataWrapper::get_conf_section('spec-agent');
    my @compute_list   = keys %{$config_compute};

    my $state;
    foreach my $compute (@compute_list) {
      if ( $config_compute->{$compute}{status} eq "RUNNING" ) {
        $state = "<td class=\"hs_good\"><div style=\"padding:4px 10px;\">$config_compute->{$compute}{status}</div></td>";
      }
      elsif ( $config_compute->{$compute}{status} eq "stopped" ) {
        $state = "<td class=\"hs_warning\"><div style=\"padding:4px 10px;\">$config_compute->{$compute}{status}</div></td>";
      }
      else {
        $state = "<td class=\"hs_error\"><div style=\"padding:4px 10px;\">$config_compute->{$compute}{status}</div></td>";
      }

      my $agent;
      if ( defined $config_agent->{$compute} && $config_agent->{$compute} eq "1" ) {
        $agent = "<td><div style=\"padding:4px 10px;\">Installed</div></td>";
      }
      else {
        $agent = "<td class=\"hs_warning\"><div style=\"padding:4px 10px;\">Not installed</div></td>";
      }

      my $ip = "undef";
      if ( defined $config_compute->{$compute}{ip} ) {
        $ip = $config_compute->{$compute}{ip};
      }

      print $html_table_row->( "<td><div style=\"padding:4px 10px;\">$compute</div></td>", "<td><div style=\"padding:4px 10px;\">$config_compute->{$compute}{name}</div></td>", "<td><div style=\"padding:4px 10px;\">$config_compute->{$compute}{region}</div></td>", "$state", "$agent", "<td><div style=\"padding:4px 10px;\">$config_compute->{$compute}{cpuPlatform}</div></td>", "<td><div style=\"padding:4px 10px;\">$ip</div></td>", "<td><div style=\"padding:4px 10px;\">$config_compute->{$compute}{size}</div></td>", "<td><div style=\"padding:4px 10px;\">$config_compute->{$compute}{diskSize} GB</div></td>", "<td><div style=\"padding:4px 10px;\">$config_compute->{$compute}{creationTimestamp}</div></td>" );

    }

    print $html_tab_footer;

    print "</div>\n";

    # Database
    print "<div id=\"tabs-2\">\n";

    print "<h2>Google SQL</h2>";

    print $html_tab_header->( 'Name', 'Engine', 'Status', 'IP', 'Disk size [GB]', 'Disk type', 'Instance size' );

    my $config_database = GCloudDataWrapper::get_conf_section('spec-database');
    my @database_list   = keys %{$config_database};

    foreach my $database (@database_list) {

      my $state = "<td class=\"hs_unknown\">undef</td>";
      if ( $config_database->{$database}{status} eq "RUNNABLE" ) {
        $state = "<td class=\"hs_good\"><div style=\"padding:4px 10px;\">$config_database->{$database}{status}</div></td>";
      }
      else {
        $state = "<td class=\"hs_warning\"><div style=\"padding:4px 10px;\">$config_database->{$database}{status}</div></td>";
      }

      print $html_table_row->( "<td><div style=\"padding:4px 10px;\">$config_database->{$database}{name}</div></td>", "<td><div style=\"padding:4px 10px;\">$config_database->{$database}{databaseVersion}</div></td>", $state, "<td><div style=\"padding:4px 10px;\">$config_database->{$database}{ip}</div></td>", "<td><div style=\"padding:4px 10px;\">$config_database->{$database}{dataDiskSizeGb}</div></td>", "<td><div style=\"padding:4px 10px;\">$config_database->{$database}{dataDiskType}</div></td>", "<td><div style=\"padding:4px 10px;\">$config_database->{$database}{size}</div></td>" );

    }

    print $html_tab_footer;

    print "</div>\n";
  }

  # closing page contents
  print "</CENTER>";
  print "</div><br>\n";

  exit(0);
}

# Azure
if ($azure) {

  # TODO temporary wrapper for compatibility with legacy subroutines interfacing mainly detail-graph-cgi.pl
  $host_url = 'Azure';

  #print "<script>console.log('type: $params{type}, id: $params{id}');</script>";
  if ( $params{type} =~ m/vm-aggr/ ) {
    $server_url = $params{id};
    $lpar_url   = 'nope';
  }
  elsif ( $params{type} =~ m/vm/ || $params{type} =~ m/appService/ ) {
    $server_url = $params{id};
    $lpar_url   = $params{id};
  }
  else {
    $lpar_url   = 'nope';
    $server_url = 'nope';
  }

  # print page contents
  print "<CENTER>";

  # get tabs
  my @tabs = @{ AzureMenu::get_tabs( $params{type} ) };

  if (@tabs) {
    print "<div id=\"tabs\">\n";
    print "<ul>\n";

    my $tab_counter = 1;
    foreach my $tab_header (@tabs) {
      while ( my ( $tab_type, $tab_label ) = each %$tab_header ) {
        print "  <li class=\"$tab_type\"><a href=\"#tabs-$tab_counter\">$tab_label</a></li>\n";
        $tab_counter++;
      }
    }
    print "</ul>\n";
  }

  # print tab contents
  sub print_tab_contents_azure {
    my ( $tab_number, $host_url, $server_url, $lpar_url, $item, $entitle, $detail_yes, $legend ) = @_;

    print "<div id=\"tabs-$tab_number\">\n";
    print "<table border=\"0\">\n";
    print "<tr>";

    print_item( $host_url, $server_url, $lpar_url, $item, "d", "", $entitle, $detail_yes, "norefr", "star", 1, $legend );
    print_item( $host_url, $server_url, $lpar_url, $item, "w", "", $entitle, $detail_yes, "norefr", "star", 1, $legend );
    print "</tr>\n<tr>\n";
    print_item( $host_url, $server_url, $lpar_url, $item, "m", "", $entitle, $detail_yes, "norefr", "star", 1, $legend );
    print_item( $host_url, $server_url, $lpar_url, $item, "y", "", $entitle, $detail_yes, "norefr", "star", 1, $legend );
    print "</tr></table>";
    print "</div>\n";
  }

  my $config_vm_agent = AzureDataWrapper::get_conf_section('spec-vm');
  my $agent           = $config_vm_agent->{$lpar_url}{agent};
  my $show_agent      = 0;

  my $legend = ( $params{type} =~ m/aggr/ ) ? 'nolegend' : 'legend';
  if ( $params{type} =~ m/^appService$/ ) {
    my @azure_items = ( 'azure-app-cpu-time', 'azure-app-data', 'azure-app-iops', 'azure-app-net', 'azure-app-http', 'azure-app-response', 'azure-app-connections' );
    for $tab_number ( 1 .. $#azure_items + 1 ) {
      my $azure_item = $azure_items[ $tab_number - 1 ];
      print_tab_contents_azure( $tab_number, $host_url, $server_url, $lpar_url, $azure_item, $entitle, $detail_yes, 'legend' );
    }
  }
  elsif ( $params{type} =~ m/^vm$/ || $params{type} =~ m/^vm-aggr$/ || $params{type} =~ m/^vm-aggr-res$/ ) {
    my @azure_items;
    if ( $params{type} =~ m/^vm-aggr$/ ) {
      @azure_items = ( 'azure-vm-cpu-percent', 'azure-vm-data', 'azure-vm-iops', 'azure-vm-net', 'azure-vm-mem-free', 'azure-vm-mem-used' );
      my @vms = @{ AzureDataWrapper::get_items( { item_type => 'vm', parent_type => 'location', parent_id => $server_url } ) };
      foreach my $vm (@vms) {
        my ( $vm_uuid, $vm_label ) = each %{$vm};
        if ( $config_vm_agent->{$vm_uuid}{agent} eq "1" ) {
          $show_agent = 1;
          print "<script>console.log(\"agent!\");</script>";
        }
      }
    }
    elsif ( $params{type} =~ m/^vm-aggr-res$/ ) {
      @azure_items = ( 'azure-vm-cpu-percent', 'azure-vm-data', 'azure-vm-iops', 'azure-vm-net', 'azure-vm-mem-free', 'azure-vm-mem-used' );
      my @vms = @{ AzureDataWrapper::get_items( { item_type => 'vm', parent_type => 'resource', parent_id => $server_url } ) };
      foreach my $vm (@vms) {
        my ( $vm_uuid, $vm_label ) = each %{$vm};
        if ( $config_vm_agent->{$vm_uuid}{agent} eq "1" ) {
          $show_agent = 1;
          print "<script>console.log(\"agent!\");</script>";
        }
      }
    }
    else {
      $show_agent  = 1;
      @azure_items = ( 'azure-vm-cpu-percent', 'azure-vm-data', 'azure-vm-iops', 'azure-vm-net', 'azure-vm-mem' );
    }
    for $tab_number ( 1 .. $#azure_items + 1 ) {
      my $azure_item = $azure_items[ $tab_number - 1 ];
      if    ( $params{type} =~ m/-aggr$/ )     { $azure_item .= '-aggr'; }
      elsif ( $params{type} =~ m/-aggr-res$/ ) { $azure_item .= '-aggr-res'; }
      if    ( ( $azure_item eq "azure-vm-mem" && $agent eq "0" ) || ( $show_agent eq "0" && ( $azure_item eq "azure-vm-mem-free-aggr" || $azure_item eq "azure-vm-mem-used-aggr" ) ) ) {
        print "<div id=\"tabs-$tab_number\">\n";
        print "<h2>Azure agent is not installed!</h2>";
        print "Link: <a href=\"https://docs.microsoft.com/en-us/azure/azure-monitor/platform/agents-overview#azure-diagnostics-extension\">Azure Diagnostic Extension</a>";
        print "</div>";
      }
      else {
        print_tab_contents_azure( $tab_number, $host_url, $server_url, $lpar_url, $azure_item, $entitle, $detail_yes, $legend );
      }
    }
  }
  elsif ( $params{type} =~ m/^region-aggr$/ ) {
    my @azure_items = ( 'azure-instance-overview', 'azure-region-running-aggr', 'azure-region-stopped-aggr' );
    for $tab_number ( 1 .. $#azure_items + 1 ) {
      my $azure_item = $azure_items[ $tab_number - 1 ];
      if ( $azure_item eq "azure-instance-overview" ) {

        my $html_tab_header = sub {
          my @columns = @_;
          my $result  = '';

          $result .= "<center>";
          $result .= "<table class=\"tabconfig tablesorter\">";
          $result .= "<thead><tr>";
          foreach my $item (@columns) {
            $result .= "<th class=\"sortable\">" . $item . "</th>";
          }
          $result .= "</tr></thead>";
          $result .= "<tbody>";

          return $result;
        };

        my $html_table_row = sub {
          my @cells  = @_;
          my $result = '';

          $result .= "<tr>";
          foreach my $cell (@cells) { $result .= $cell; }
          $result .= "</tr>";

          return $result;
        };
        my $config_update_time = localtime( AzureDataWrapper::get_conf_update_time() );

        my $html_tab_footer = "</tbody></table><p>Last update time: " . $config_update_time . "</p></center>";

        print "<div id=\"tabs-$tab_number\">\n";
        print "<h2>Instance Overview</h2>";

        print $html_tab_header->( 'Location', 'Running', 'Stopped' );

        my $config_region = AzureDataWrapper::get_conf_section('spec-region');

        foreach my $regionKey ( %{$config_region} ) {
          if ( !defined $config_region->{$regionKey}->{running} ) {
            next;
          }
          print $html_table_row->( "<td><div style=\"padding:4px 10px;\">$regionKey</div></td>", "<td><div style=\"padding:4px 10px;\">$config_region->{$regionKey}->{running}</div></td>", "<td><div style=\"padding:4px 10px;\">$config_region->{$regionKey}->{stopped}</div></td>" );
        }

        print $html_tab_footer;

        print "</div>";
      }
      else {
        print_tab_contents_azure( $tab_number, $host_url, $server_url, $lpar_url, $azure_item, $entitle, $detail_yes, 'nolegend' );
      }
    }

  }
  elsif ( $params{type} =~ m/^configuration$/ ) {
    my $config_update_time = localtime( AzureDataWrapper::get_conf_update_time() );

    my $html_tab_header = sub {
      my @columns = @_;
      my $result  = '';
      $result .= "<center>";
      $result .= "<table class=\"tabconfig tablesorter\">";
      $result .= "<thead><tr>";
      foreach my $item (@columns) {
        $result .= "<th class=\"sortable\">" . $item . "</th>";
      }
      $result .= "</tr></thead>";
      $result .= "<tbody>";

      return $result;
    };

    my $html_table_row = sub {
      my @cells  = @_;
      my $result = '';

      $result .= "<tr>";
      foreach my $cell (@cells) { $result .= $cell; }
      $result .= "</tr>";

      return $result;
    };

    my $html_tab_footer  = "</tbody></table><p>Last update time: " . $config_update_time . "</p></center>";
    my $html_tab_footer2 = "</tbody></table></center>";

    # Compute
    print "<div id=\"tabs-1\">\n";

    print "<h2>Virtual Machine</h2>";

    print $html_tab_header->( 'Virtual Machine ID', 'Name', 'Location', 'State', 'Agent', 'IP', 'Instance Size', 'Disk Size', 'OS' );

    my $config_vm = AzureDataWrapper::get_conf_section('spec-vm');
    my $statuses  = AzureDataWrapper::get_conf_section('statuses');
    my @vm_list   = keys %{$config_vm};

    my $state;
    foreach my $vm (@vm_list) {
      if ( !defined $config_vm->{$vm}{status} ) {
        $state = "<td class=\"hs_error\"><div style=\"padding:4px 10px;\">undef</div></td>";
      }
      elsif ( $config_vm->{$vm}{status} eq "VM running" ) {
        $state = "<td class=\"hs_good\"><div style=\"padding:4px 10px;\">$config_vm->{$vm}{status}</div></td>";
      }
      else {
        $state = "<td class=\"hs_warning\"><div style=\"padding:4px 10px;\">$config_vm->{$vm}{status}</div></td>";
      }

      my $agent;
      if ( $config_vm->{$vm}{agent} eq "1" ) {
        $agent = "<td><div style=\"padding:4px 10px;\">Installed</div></td>";
      }
      else {
        $agent = "<td class=\"hs_warning\"><div style=\"padding:4px 10px;\">Not installed</div></td>";
      }

      my $ip = "undef";
      if ( defined $config_vm->{$vm}{network}[0]{ip} ) {
        $ip = "$config_vm->{$vm}{network}[0]{ip} ($config_vm->{$vm}{network}[0]{type})";
      }

      my $disk = "undef";
      if ( defined $config_vm->{$vm}{osDisk}{diskSizeGB} ) {
        $disk = "$config_vm->{$vm}{osDisk}{diskSizeGB} GB";
      }

      my $os     = "undef";
      my $os_ver = "undef";
      if ( defined $config_vm->{$vm}{osVersion} ) {
        $os     = $config_vm->{$vm}{osName};
        $os_ver = $config_vm->{$vm}{osVersion};
      }

      print $html_table_row->( "<td><div style=\"padding:4px 10px;\">$vm</div></td>", "<td><div style=\"padding:4px 10px;\">$config_vm->{$vm}{name}</div></td>", "<td><div style=\"padding:4px 10px;\">$config_vm->{$vm}{location}</div></td>", "$state", "$agent", "<td><div style=\"padding:4px 10px;\">$ip</div></td>", "<td><div style=\"padding:4px 10px;\">$config_vm->{$vm}{vmSize}</div></td>", "<td><div style=\"padding:4px 10px;\">$disk</div></td>", "<td><div style=\"padding:4px 10px;\">$os ($os_ver)</div></td>" );

    }

    print $html_tab_footer;

    print "</div>\n";

    # Compute
    print "<div id=\"tabs-2\">\n";

    print "<h2>SQL Databases</h2>";

    print "<br><h3>Database servers</h3>";

    print $html_tab_header->( 'Name', 'Domain', 'Location', 'State', 'Type', 'Version', 'Admin login', 'Public' );

    my $config_databaseServer = AzureDataWrapper::get_conf_section('spec-databaseServer');
    my @databaseServer_list   = keys %{$config_databaseServer};

    foreach my $databaseServer (@databaseServer_list) {
      if ( !defined $config_databaseServer->{$databaseServer}{state} ) {
        $state = "<td class=\"hs_error\"><div style=\"padding:4px 10px;\">undef</div></td>";
      }
      elsif ( $config_databaseServer->{$databaseServer}{state} eq "Ready" ) {
        $state = "<td class=\"hs_good\"><div style=\"padding:4px 10px;\">$config_databaseServer->{$databaseServer}{state}</div></td>";
      }
      else {
        $state = "<td class=\"hs_warning\"><div style=\"padding:4px 10px;\">$config_databaseServer->{$databaseServer}{state}</div></td>";
      }

      print $html_table_row->( "<td><div style=\"padding:4px 10px;\">$config_databaseServer->{$databaseServer}{name}</div></td>", "<td><div style=\"padding:4px 10px;\">$config_databaseServer->{$databaseServer}{domain}</div></td>", "<td><div style=\"padding:4px 10px;\">$config_databaseServer->{$databaseServer}{location}</div></td>", $state, "<td><div style=\"padding:4px 10px;\">$config_databaseServer->{$databaseServer}{type}</div></td>", "<td><div style=\"padding:4px 10px;\">$config_databaseServer->{$databaseServer}{version}</div></td>", "<td><div style=\"padding:4px 10px;\">$config_databaseServer->{$databaseServer}{login}</div></td>", "<td><div style=\"padding:4px 10px;\">$config_databaseServer->{$databaseServer}{public}</div></td>" );
    }

    print $html_tab_footer2;

    print "<br><h3>Databases</h3>";

    print $html_tab_header->( 'Name', 'Status', 'Collation', 'Max Size [GB]', 'Database Server' );

    my $config_database = AzureDataWrapper::get_conf_section('spec-database');
    my @database_list   = keys %{$config_database};

    foreach my $database (@database_list) {
      if ( !defined $config_database->{$database}{status} ) {
        $state = "<td class=\"hs_error\"><div style=\"padding:4px 10px;\">undef</div></td>";
      }
      elsif ( $config_database->{$database}{status} eq "Online" ) {
        $state = "<td class=\"hs_good\"><div style=\"padding:4px 10px;\">$config_database->{$database}{status}</div></td>";
      }
      else {
        $state = "<td class=\"hs_warning\"><div style=\"padding:4px 10px;\">$config_database->{$database}{status}</div></td>";
      }

      my $maxSize = "undef";
      if ( defined $config_database->{$database}{maxSizeBytes} ) {
        $maxSize = $config_database->{$database}{maxSizeBytes} / 1024 / 1024 / 1024;
      }

      print $html_table_row->( "<td><div style=\"padding:4px 10px;\">$config_database->{$database}{name}</div></td>", $state, "<td><div style=\"padding:4px 10px;\">$config_database->{$database}{collation}</div></td>", "<td><div style=\"padding:4px 10px;\">$maxSize</div></td>", "<td><div style=\"padding:4px 10px;\">$config_database->{$database}{server}</div></td>" );

    }

    print $html_tab_footer;

    print "</div>\n";

  }
  elsif ( $params{type} =~ m/^statuses$/ ) {
    my $config_update_time = localtime( AzureDataWrapper::get_conf_update_time() );

    my $html_tab_header = sub {
      my @columns = @_;
      my $result  = '';
      $result .= "<center>";
      $result .= "<table class=\"tabconfig tablesorter\">";
      $result .= "<thead><tr>";
      foreach my $item (@columns) {
        $result .= "<th class=\"sortable\">" . $item . "</th>";
      }
      $result .= "</tr></thead>";
      $result .= "<tbody>";

      return $result;
    };

    my $html_table_row = sub {
      my @cells  = @_;
      my $result = '';

      $result .= "<tr>";
      foreach my $cell (@cells) { $result .= $cell; }
      $result .= "</tr>";

      return $result;
    };
    my $html_tab_footer = "</tbody></table><p>Last update time: " . $config_update_time . "</p></center>";

    # Compute
    print "<div id=\"tabs-1\">\n";

    print "<h2>Virtual Machine</h2>";

    print $html_tab_header->( 'VM', 'Level', 'Code', 'Status' );

    my $statuses = AzureDataWrapper::get_conf_section('statuses');

    for ( @{ $statuses->{vm} } ) {
      my $status = $_;

      print $html_table_row->( "<td><div style=\"padding:4px 10px;\">$status->{vm}</div></td>", "<td><div style=\"padding:4px 10px;\">$status->{level}</div></td>", "<td><div style=\"padding:4px 10px;\">$status->{code}</div></td>", "<td><div style=\"padding:4px 10px;\">$status->{status}</div></td>" );

    }

    print $html_tab_footer;

    print "</div>\n";
  }
  elsif ( $params{type} =~ m/^topten_azure$/ ) {
    ############## LOAD TOPTEN FILE #####################
    my $topten_file_azure = "$tmpdir/topten_azure.tmp";
    my $last_update       = localtime( ( stat($topten_file_azure) )[9] );
    #####################################################
    my $server_pool = "";

    # last day
    print "<div id=\"tabs-1\">\n";
    print "<table align=\"center\" summary=\"Graphs\">\n";
    print "<tr><th align=center>CPU in %<a class=\"csvfloat\" href=\"/lpar2rrd-cgi/top10_csv.sh?LPAR=$server_pool&host=CSV&type=AZURE&table=topten&item=cpu_perc&period=1\" title=\"LOAD CPU CSV\"><img src=\"css/images/csv.gif\"></a></th><th align=center>IOPS<a class=\"csvfloat\" href=\"/lpar2rrd-cgi/top10_csv.sh?LPAR=$server_pool&host=CSV&type=AZURE&table=topten&item=iops&period=1\" title=\"IOPS CSV\"><img src=\"css/images/csv.gif\"></a></th><th align=center>NET in MB/sec<a class=\"csvfloat\" href=\"/lpar2rrd-cgi/top10_csv.sh?LPAR=$server_pool&host=CSV&type=AZURE&table=topten&item=net&period=1\" title=\"NET CSV\"><img src=\"css/images/csv.gif\"></a></th><th align=center>DISK in MB/sec<a class=\"csvfloat\" href=\"/lpar2rrd-cgi/top10_csv.sh?LPAR=$server_pool&host=CSV&type=AZURE&table=topten&item=disk&period=1\" title=\"DISK CSV\"><img src=\"css/images/csv.gif\"></a></th></tr>";
    print "<tr style=\"vertical-align:top\">";
    print_top10_to_table_azure( "1", "$server_pool", "cpu_perc" );
    print_top10_to_table_azure( "1", "$server_pool", "iops" );
    print_top10_to_table_azure( "1", "$server_pool", "net" );
    print_top10_to_table_azure( "1", "$server_pool", "disk" );
    print "</tr>";
    print "</table>";
    print "<tfoot><tr><td colspan=\"6\">Last update time: $last_update</td></tr></tfoot>";
    print "</div>\n";

    # last week
    print "<div id=\"tabs-2\">\n";
    print "<table align=\"center\" summary=\"Graphs\">\n";
    print "<tr><th align=center>CPU in %<a class=\"csvfloat\" href=\"/lpar2rrd-cgi/top10_csv.sh?LPAR=$server_pool&host=CSV&type=AZURE&table=topten&item=cpu_perc&period=2\" title=\"LOAD CPU CSV\"><img src=\"css/images/csv.gif\"></a></th><th align=center>IOPS<a class=\"csvfloat\" href=\"/lpar2rrd-cgi/top10_csv.sh?LPAR=$server_pool&host=CSV&type=AZURE&table=topten&item=iops&period=2\" title=\"IOPS CSV\"><img src=\"css/images/csv.gif\"></a></th><th align=center>NET in MB/sec<a class=\"csvfloat\" href=\"/lpar2rrd-cgi/top10_csv.sh?LPAR=$server_pool&host=CSV&type=AZURE&table=topten&item=net&period=2\" title=\"NET CSV\"><img src=\"css/images/csv.gif\"></a></th><th align=center>DISK in MB/sec<a class=\"csvfloat\" href=\"/lpar2rrd-cgi/top10_csv.sh?LPAR=$server_pool&host=CSV&type=AZURE&table=topten&item=disk&period=2\" title=\"DISK CSV\"><img src=\"css/images/csv.gif\"></a></th></tr>";
    print "<tr style=\"vertical-align:top\">";
    print_top10_to_table_azure( "2", "$server_pool", "cpu_perc" );
    print_top10_to_table_azure( "2", "$server_pool", "iops" );
    print_top10_to_table_azure( "2", "$server_pool", "net" );
    print_top10_to_table_azure( "2", "$server_pool", "disk" );
    print "</tr>";
    print "</table>";
    print "<tfoot><tr><td colspan=\"6\">Last update time: $last_update</td></tr></tfoot>";
    print "</div>\n";

    # last month
    print "<div id=\"tabs-3\">\n";
    print "<table align=\"center\" summary=\"Graphs\">\n";
    print "<tr><th align=center>CPU in %<a class=\"csvfloat\" href=\"/lpar2rrd-cgi/top10_csv.sh?LPAR=$server_pool&host=CSV&type=AZURE&table=topten&item=cpu_perc&period=3\" title=\"LOAD CPU CSV\"><img src=\"css/images/csv.gif\"></a></th><th align=center>IOPS<a class=\"csvfloat\" href=\"/lpar2rrd-cgi/top10_csv.sh?LPAR=$server_pool&host=CSV&type=AZURE&table=topten&item=iops&period=3\" title=\"IOPS CSV\"><img src=\"css/images/csv.gif\"></a></th><th align=center>NET in MB/sec<a class=\"csvfloat\" href=\"/lpar2rrd-cgi/top10_csv.sh?LPAR=$server_pool&host=CSV&type=AZURE&table=topten&item=net&period=3\" title=\"NET CSV\"><img src=\"css/images/csv.gif\"></a></th><th align=center>DISK in MB/sec<a class=\"csvfloat\" href=\"/lpar2rrd-cgi/top10_csv.sh?LPAR=$server_pool&host=CSV&type=AZURE&table=topten&item=disk&period=3\" title=\"DISK CSV\"><img src=\"css/images/csv.gif\"></a></th></tr>";
    print "<tr style=\"vertical-align:top\">";
    print_top10_to_table_azure( "3", "$server_pool", "cpu_perc" );
    print_top10_to_table_azure( "3", "$server_pool", "iops" );
    print_top10_to_table_azure( "3", "$server_pool", "net" );
    print_top10_to_table_azure( "3", "$server_pool", "disk" );
    print "</tr>";
    print "</table>";
    print "<tfoot><tr><td colspan=\"6\">Last update time: $last_update</td></tr></tfoot>";
    print "</div>\n";

    # last year
    print "<div id=\"tabs-4\">\n";
    print "<table align=\"center\" summary=\"Graphs\">\n";
    print "<tr><th align=center>CPU in %<a class=\"csvfloat\" href=\"/lpar2rrd-cgi/top10_csv.sh?LPAR=$server_pool&host=CSV&type=AZURE&table=topten&item=cpu_perc&period=4\" title=\"LOAD CPU CSV\"><img src=\"css/images/csv.gif\"></a></th><th align=center>IOPS<a class=\"csvfloat\" href=\"/lpar2rrd-cgi/top10_csv.sh?LPAR=$server_pool&host=CSV&type=AZURE&table=topten&item=iops&period=4\" title=\"IOPS CSV\"><img src=\"css/images/csv.gif\"></a></th><th align=center>NET in MB/sec<a class=\"csvfloat\" href=\"/lpar2rrd-cgi/top10_csv.sh?LPAR=$server_pool&host=CSV&type=AZURE&table=topten&item=net&period=4\" title=\"NET CSV\"><img src=\"css/images/csv.gif\"></a></th><th align=center>DISK in MB/sec<a class=\"csvfloat\" href=\"/lpar2rrd-cgi/top10_csv.sh?LPAR=$server_pool&host=CSV&type=AZURE&table=topten&item=disk&period=4\" title=\"DISK CSV\"><img src=\"css/images/csv.gif\"></a></th></tr>";
    print "<tr style=\"vertical-align:top\">";
    print_top10_to_table_azure( "4", "$server_pool", "cpu_perc" );
    print_top10_to_table_azure( "4", "$server_pool", "iops" );
    print_top10_to_table_azure( "4", "$server_pool", "net" );
    print_top10_to_table_azure( "4", "$server_pool", "disk" );
    print "</tr>";
    print "</table>";
    print "<tfoot><tr><td colspan=\"6\">Last update time: $last_update</td></tr></tfoot>";
    print "</div>\n";
  }

  sub print_top10_to_table_azure {
    my ( $period, $server_pool, $item_name ) = @_;
    my $topten_file_ovirt = "$tmpdir/topten_azure.tmp";
    my $html_tab_header   = sub {
      my @columns = @_;
      my $result  = '';
      $result .= "<center>";
      $result .= "<table style=\"white-space: nowrap;\" class=\"tabconfig tablesorter \" data-sortby='1'>";
      $result .= "<thead><tr>";
      foreach my $item (@columns) {
        $result .= "<th class=\"sortable\">" . $item . "</th>";
      }
      $result .= "</tr></thead>";
      $result .= "<tbody>";
      return $result;
    };
    my $html_table_row = sub {
      my @cells  = @_;
      my $result = '';

      $result .= "<tr>";
      foreach my $cell (@cells) { $result .= "<td>" . $cell . "</td>"; }
      $result .= "</tr>";

      return $result;
    };

    # Table or create CSV file
    my $csv_file;
    if ( $item_name eq "load_cpu" ) {
      $csv_file = "azure-load-cpu.csv";
    }
    elsif ( $item_name eq "cpu_perc" ) {
      $csv_file = "azure-cpu-perc.csv";
    }
    elsif ( $item_name eq "net" ) {
      $csv_file = "azure-net.csv";
    }
    elsif ( $item_name eq "disk" ) {
      $csv_file = "azure-disk.csv";
    }
    if ( !$csv ) {
      print "<TD><TABLE class=\"tabconfig tablesorter\" data-sortby=\"1\">";
      if ( $period == 4 ) {    # last year
        print $html_tab_header->( 'Avrg', "VM", 'Location' );
      }
      else {
        print $html_tab_header->( 'Avrg', 'Max', "VM", 'Location' );
      }
    }
    else {
      print "Content-Disposition: attachment;filename=\"$csv_file\"\n\n";
      my $csv_header = "";
      if ( $period == 4 ) {    # last year
        $csv_header = "Avrg" . "$sep" . "VM" . "$sep" . "Location\n";
      }
      else {
        $csv_header = "Avrg" . "$sep" . "Max" . "$sep" . "VM" . "$sep" . "Location\n";
      }
      print "$csv_header";
    }
    my @topten;
    my @topten_not_sorted;
    my @topten_sorted;
    my $topten_limit = 0;
    my @top_values_avrg;
    my @top_values_max;
    if ( -f $topten_file_ovirt ) {
      open( FH, " < $topten_file_ovirt" ) || error( "Cannot open $topten_file_ovirt: $!" . __FILE__ . ":" . __LINE__ );
      @topten = <FH>;
      close FH;
      if ( defined $ENV{TOPTEN} ) {
        $topten_limit = $ENV{TOPTEN};
      }
      $topten_limit = 50 if $topten_limit < 1;
      my @topten_server;
      if ( $item_name eq "cpu_perc" ) {
        @topten_server = grep {/cpu_perc,/} @topten;
      }
      elsif ( $item_name eq "iops" ) {
        @topten_server = grep {/iops,/} @topten;
      }
      elsif ( $item_name eq "net" ) {
        @topten_server = grep {/net,/} @topten;
      }
      elsif ( $item_name eq "disk" ) {
        @topten_server = grep {/disk,/} @topten;
      }
      @topten = @topten_server;
      foreach my $line (@topten) {
        chomp $line;
        my ( $item, $vm_name, $location );
        ( $item, $vm_name, $location, $top_values_avrg[1], $top_values_max[1], $top_values_avrg[2], $top_values_max[2], $top_values_avrg[3], $top_values_max[3], $top_values_avrg[4], $top_values_max[4] ) = split( ",", $line );
        $top_values_avrg[4] = 0 if !defined $top_values_avrg[4] or $top_values_avrg[4] eq "";    # no year value yet, new file
        $top_values_max[4]  = 0 if !defined $top_values_max[4]  or $top_values_max[4] eq "";     # no year value yet, new file
        if ( $top_values_avrg[1] == 0 && $top_values_max[1] == 0 && $top_values_avrg[2] == 0 && $top_values_max[2] == 0 && $top_values_avrg[3] == 0 && $top_values_max[3] == 0 && $top_values_avrg[4] == 0 && $top_values_max[4] == 0 ) { next; }
        push @topten_not_sorted, "$item,$top_values_avrg[$period],$top_values_max[$period],$vm_name,$location\n";
      }
      {
        no warnings;
        @topten_sorted = sort { $b <=> $a } @topten_not_sorted;
      }
    }
    my @topten_sorted_load_cpu;
    {
      no warnings;
      @topten_sorted_load_cpu = sort {
        my @b = split( /,/, $b );
        my @a = split( /,/, $a );

        #print "$b[4] --- $a[4]\n";
        $b[1] <=> $a[1]
      } @topten_sorted;
    }
    foreach my $line1 (@topten_sorted_load_cpu) {
      my ( $item_a, $load_cpu, $load_peak, $vm_name, $location );
      ( $item_a, $load_cpu, $load_peak, $vm_name, $location ) = split( ",", $line1 );

      #print STDERR"$item_a, $load_cpu, $load_peak, $vm_name, $uuid\n";
      if ( !$csv ) {
        if ( $period == 4 ) {    # last year
          print $html_table_row->( $load_cpu, $vm_name, $location );
        }
        else {
          print $html_table_row->( $load_cpu, $load_peak, $vm_name, $location );
        }
      }
      else {
        if ( $period == 4 ) {    # last year
          print "$load_cpu" . "$sep" . "$vm_name" . "$sep" . "$location";
        }
        else {
          print "$load_cpu" . "$sep" . "$load_peak" . "$sep" . "$vm_name" . "$sep" . "$location";
        }
      }
    }
    if ( !$csv ) {
      print "</TABLE></TD>";
    }
    return 1;
  }

  # closing page contents
  print "</CENTER>";
  print "</div><br>\n";

  exit(0);
}

# Kubernetes
if ($kubernetes) {

  # TODO temporary wrapper for compatibility with legacy subroutines interfacing mainly detail-graph-cgi.pl
  $host_url = 'Kubernetes';

  #print "<script>console.log('type: $params{type}, id: $params{id}');</script>";
  if ( $params{type} =~ m/node-aggr/ || $params{type} =~ m/pod-aggr/ || $params{type} =~ m/container-aggr/ || $params{type} =~ m/namespace-aggr/ ) {
    $server_url = $params{id};
    $lpar_url   = 'nope';
  }
  elsif ( $params{type} =~ m/node/ || $params{type} =~ m/pod/ || $params{type} =~ m/container/ || $params{type} =~ m/namespace/ ) {
    $server_url = $params{id};
    $lpar_url   = $params{id};
  }
  else {
    $lpar_url   = 'nope';
    $server_url = 'nope';
  }

  # print page contents
  print "<CENTER>";

  # get tabs
  my @tabs = @{ KubernetesMenu::get_tabs( $params{type} ) };

  if (@tabs) {
    print "<div id=\"tabs\">\n";
    print "<ul>\n";

    my $tab_counter = 1;
    foreach my $tab_header (@tabs) {
      while ( my ( $tab_type, $tab_label ) = each %$tab_header ) {
        print "  <li class=\"$tab_type\"><a href=\"#tabs-$tab_counter\">$tab_label</a></li>\n";
        $tab_counter++;
      }
    }
    print "</ul>\n";
  }

  # print tab contents
  sub print_tab_contents_kubernetes {
    my ( $tab_number, $host_url, $server_url, $lpar_url, $item, $entitle, $detail_yes, $legend ) = @_;

    print "<div id=\"tabs-$tab_number\">\n";
    print "<table border=\"0\">\n";
    print "<tr>";

    print_item( $host_url, $server_url, $lpar_url, $item, "d", "", $entitle, $detail_yes, "norefr", "star", 1, $legend );
    print_item( $host_url, $server_url, $lpar_url, $item, "w", "", $entitle, $detail_yes, "norefr", "star", 1, $legend );
    print "</tr>\n<tr>\n";
    print_item( $host_url, $server_url, $lpar_url, $item, "m", "", $entitle, $detail_yes, "norefr", "star", 1, $legend );
    print_item( $host_url, $server_url, $lpar_url, $item, "y", "", $entitle, $detail_yes, "norefr", "star", 1, $legend );
    print "</tr></table>";
    print "</div>\n";
  }

  my $legend = ( $params{type} =~ m/aggr/ ) ? 'nolegend' : 'legend';
  if ( $params{type} =~ m/^node$/ ) {
    my @kubernetes_items = ( 'kubernetes-node-cpu-percent', 'kubernetes-node-cpu', 'kubernetes-node-memory', 'kubernetes-node-pods', 'kubernetes-node-data', 'kubernetes-node-iops', 'kubernetes-node-latency', 'kubernetes-node-net' );
    for $tab_number ( 1 .. $#kubernetes_items + 1 ) {
      $legend = ( $kubernetes_items[ $tab_number - 1 ] =~ m/aggr/ ) ? 'nolegend' : 'legend';
      print_tab_contents_kubernetes( $tab_number, $host_url, $server_url, $lpar_url, $kubernetes_items[ $tab_number - 1 ], $entitle, $detail_yes, $legend );
    }
  }
  elsif ( $params{type} =~ m/^node-aggr$/ ) {
    my @kubernetes_items = ( 'kubernetes-node-cpu-percent-aggr', 'kubernetes-node-cpu-aggr', 'kubernetes-node-memory-aggr', 'kubernetes-node-pods-aggr', 'kubernetes-node-data-aggr', 'kubernetes-node-iops-aggr', 'kubernetes-node-latency-aggr', 'kubernetes-node-net-aggr' );
    for $tab_number ( 1 .. $#kubernetes_items + 1 ) {
      $legend = ( $kubernetes_items[ $tab_number - 1 ] =~ m/aggr/ ) ? 'nolegend' : 'legend';
      print_tab_contents_kubernetes( $tab_number, $host_url, $server_url, $lpar_url, $kubernetes_items[ $tab_number - 1 ], $entitle, $detail_yes, $legend );
    }
  }
  elsif ( $params{type} =~ m/^pod$/ ) {
    my @kubernetes_items = ( 'kubernetes-pod-cpu', 'kubernetes-pod-container-cpu-aggr', 'kubernetes-pod-memory', 'kubernetes-pod-container-memory-aggr', 'kubernetes-pod-net', 'kubernetes-pod-container-data-aggr', 'kubernetes-pod-container-iops-aggr', 'kubernetes-pod-container-latency-aggr' );
    for $tab_number ( 1 .. $#kubernetes_items + 1 ) {
      $legend = ( $kubernetes_items[ $tab_number - 1 ] =~ m/aggr/ ) ? 'nolegend' : 'legend';
      print_tab_contents_kubernetes( $tab_number, $host_url, $server_url, $lpar_url, $kubernetes_items[ $tab_number - 1 ], $entitle, $detail_yes, $legend );
    }
  }
  elsif ( $params{type} =~ m/^pod-aggr$/ ) {
    my @kubernetes_items = ( 'kubernetes-pod-cpu-aggr', 'kubernetes-pod-memory-aggr', 'kubernetes-pod-network-aggr' );
    for $tab_number ( 1 .. $#kubernetes_items + 1 ) {
      $legend = ( $kubernetes_items[ $tab_number - 1 ] =~ m/aggr/ ) ? 'nolegend' : 'legend';
      print_tab_contents_kubernetes( $tab_number, $host_url, $server_url, $lpar_url, $kubernetes_items[ $tab_number - 1 ], $entitle, $detail_yes, $legend );
    }
  }
  elsif ( $params{type} =~ m/^namespace$/ ) {
    my @kubernetes_items = ( 'kubernetes-namespace-cpu', 'kubernetes-namespace-memory' );
    for $tab_number ( 1 .. $#kubernetes_items + 1 ) {
      $legend = ( $kubernetes_items[ $tab_number - 1 ] =~ m/aggr/ ) ? 'nolegend' : 'legend';
      print_tab_contents_kubernetes( $tab_number, $host_url, $server_url, $lpar_url, $kubernetes_items[ $tab_number - 1 ], $entitle, $detail_yes, $legend );
    }
  }
  elsif ( $params{type} =~ m/^namespace-aggr$/ ) {
    my @kubernetes_items = ( 'kubernetes-namespace-cpu-aggr', 'kubernetes-namespace-memory-aggr' );
    for $tab_number ( 1 .. $#kubernetes_items + 1 ) {
      $legend = ( $kubernetes_items[ $tab_number - 1 ] =~ m/aggr/ ) ? 'nolegend' : 'legend';
      print_tab_contents_kubernetes( $tab_number, $host_url, $server_url, $lpar_url, $kubernetes_items[ $tab_number - 1 ], $entitle, $detail_yes, $legend );
    }
  }
  elsif ( $params{type} =~ m/^container$/ ) {
    my @kubernetes_items = ( 'kubernetes-container-cpu', 'kubernetes-container-memory', 'kubernetes-container-data', 'kubernetes-container-iops', 'kubernetes-container-latency' );
    for $tab_number ( 1 .. $#kubernetes_items + 1 ) {
      $legend = ( $kubernetes_items[ $tab_number - 1 ] =~ m/aggr/ ) ? 'nolegend' : 'legend';
      print_tab_contents_kubernetes( $tab_number, $host_url, $server_url, $lpar_url, $kubernetes_items[ $tab_number - 1 ], $entitle, $detail_yes, $legend );
    }
  }
  elsif ( $params{type} =~ m/^configuration$/ ) {
    my $kubernetesWrapper  = KubernetesDataWrapperOOP->new();
    my $config_update_time = localtime( $kubernetesWrapper->{updated} );

    my $html_tab_header = sub {
      my @columns = @_;
      my $result  = '';
      $result .= "<center>";
      $result .= "<table class=\"tabconfig tablesorter\">";
      $result .= "<thead><tr>";
      foreach my $item (@columns) {
        $result .= "<th class=\"sortable\">" . $item . "</th>";
      }
      $result .= "</tr></thead>";
      $result .= "<tbody>";

      return $result;
    };

    my $html_table_row = sub {
      my @cells  = @_;
      my $result = '';

      $result .= "<tr>";
      foreach my $cell (@cells) { $result .= $cell; }
      $result .= "</tr>";

      return $result;
    };

    my $html_tab_footer  = "</tbody></table><p>Last update time: " . $config_update_time . "</p></center>";
    my $html_tab_footer2 = "</tbody></table></center>";

    # Node
    print "<div id=\"tabs-1\">\n";

    print "<h2>Node</h2>";

    print $html_tab_header->( 'UUID', 'Cluster', 'Name', 'OS Image', 'Container Runtime Version', 'Operating System', 'Architecture' );

    my $config_node = $kubernetesWrapper->get_conf_section('spec-node');
    my @node_list   = keys %{$config_node};

    foreach my $node (@node_list) {
      print $html_table_row->( "<td><div style=\"padding:4px 10px;\">$node</div></td>", "<td><div style=\"padding:4px 10px;\">$config_node->{$node}{cluster}</div></td>", "<td><div style=\"padding:4px 10px;\">$config_node->{$node}{name}</div></td>", "<td><div style=\"padding:4px 10px;\">$config_node->{$node}{nodeInfo}{osImage}</div></td>", "<td><div style=\"padding:4px 10px;\">$config_node->{$node}{nodeInfo}{containerRuntimeVersion}</div></td>", "<td><div style=\"padding:4px 10px;\">$config_node->{$node}{nodeInfo}{operatingSystem}</div></td>", "<td><div style=\"padding:4px 10px;\">$config_node->{$node}{nodeInfo}{architecture}</div></td>" );
    }

    print $html_tab_footer;

    print "</div>\n";

    # Pods
    print "<div id=\"tabs-2\">\n";

    print "<h2>Pods</h2>";

    print $html_tab_header->( 'UUID', 'Cluster', 'Name', 'IP' );

    my $config_pod = $kubernetesWrapper->get_conf_section('spec-pod');
    my @pod_list   = keys %{$config_pod};

    foreach my $pod (@pod_list) {
      my $url    = KubernetesMenu::get_url( { type => 'pod', pod => $pod } );
      my $pod_ip = ( defined $config_pod->{$pod}{podIP} ) ? $config_pod->{$pod}{podIP} : " - ";
      print $html_table_row->( "<td><div style=\"padding:4px 10px;\">$pod</div></td>", "<td><div style=\"padding:4px 10px;\">$config_pod->{$pod}{cluster}</div></td>", "<td><div style=\"padding:4px 10px;\"><a href=\"$url\" class=\"backlink\">$config_pod->{$pod}{name}</a></div></td>", "<td><div style=\"padding:4px 10px;\">$pod_ip</div></td>" );
    }

    print $html_tab_footer;

    print "</div>\n";

  }
  elsif ( $params{type} =~ m/^top$/ ) {
    my $kubernetesWrapper  = KubernetesDataWrapperOOP->new();
    my $config_update_time = localtime( $kubernetesWrapper->{updated} );

    my $html_tab_header = sub {
      my @columns = @_;
      my $result  = '';
      $result .= "<center>";
      $result .= "<table class=\"tabconfig tablesorter\">";
      $result .= "<thead><tr>";
      foreach my $item (@columns) {
        $result .= "<th class=\"sortable\">" . $item . "</th>";
      }
      $result .= "</tr></thead>";
      $result .= "<tbody>";

      return $result;
    };

    my $html_table_row = sub {
      my @cells  = @_;
      my $result = '';

      $result .= "<tr>";
      foreach my $cell (@cells) { $result .= $cell; }
      $result .= "</tr>";

      return $result;
    };

    my $html_tab_footer  = "</tbody></table><p>Last update time: " . $config_update_time . "</p></center>";
    my $html_tab_footer2 = "</tbody></table></center>";

    # Pods
    print "<div id=\"tabs-1\">\n";

    print "<h2>Pods TOP</h2>";
    print "<b style=\"text-align: center;\">20 minutes average</b><br><br>";

    print $html_tab_header->( 'UUID', 'Name', 'CPU [cores]', 'Memory [MiB]' );

    my $config_pod = $kubernetesWrapper->get_conf_section('spec-pod');
    my $top_pod    = KubernetesDataWrapper::get_top();
    my @pod_list   = keys %{ $top_pod->{pod} };

    #foreach my $pod (@pod_list) {
    foreach my $pod ( sort { $top_pod->{pod}{$b}{cpu} <=> $top_pod->{pod}{$a}{cpu} } keys %{ $top_pod->{pod} } ) {
      my $url = KubernetesMenu::get_url( { type => 'pod', pod => $pod } );

      my $cpu    = defined $top_pod->{pod}->{$pod}->{cpu}    && defined $top_pod->{pod}->{$pod}->{counter} ? sprintf( "%.3f", $top_pod->{pod}->{$pod}->{cpu} / $top_pod->{pod}->{$pod}->{counter} )    : "undef";
      my $memory = defined $top_pod->{pod}->{$pod}->{memory} && defined $top_pod->{pod}->{$pod}->{counter} ? sprintf( "%.0f", $top_pod->{pod}->{$pod}->{memory} / $top_pod->{pod}->{$pod}->{counter} ) : "undef";

      print $html_table_row->( "<td><div style=\"padding:4px 10px;\">$pod</div></td>", "<td><div style=\"padding:4px 10px;\"><a href=\"$url\" class=\"backlink\">$config_pod->{$pod}{name}</a></div></td>", "<td><div style=\"padding:4px 10px;\">$cpu</div></td>", "<td><div style=\"padding:4px 10px;\">$memory</div></td>" );
    }

    print $html_tab_footer;

    print "</div>\n";

  }
  elsif ( $params{type} =~ m/^pods-overview$/ ) {
    my $kubernetesWrapper  = KubernetesDataWrapperOOP->new();
    my $config_update_time = localtime( $kubernetesWrapper->{updated} );

    my $html_tab_header = sub {
      my @columns = @_;
      my $result  = '';
      $result .= "<center>";
      $result .= "<table class=\"tabconfig tablesorter\">";
      $result .= "<thead><tr>";
      foreach my $item (@columns) {
        $result .= "<th class=\"sortable\">" . $item . "</th>";
      }
      $result .= "</tr></thead>";
      $result .= "<tbody>";

      return $result;
    };

    my $html_table_row = sub {
      my @cells  = @_;
      my $result = '';

      $result .= "<tr>";
      foreach my $cell (@cells) { $result .= $cell; }
      $result .= "</tr>";

      return $result;
    };

    my $html_tab_footer  = "</tbody></table><p>Last update time: " . $config_update_time . "</p></center>";
    my $html_tab_footer2 = "</tbody></table></center>";

    # Overview
    print "<div id=\"tabs-1\">\n";

    my $config_pod = $kubernetesWrapper->get_conf_section('spec-pod');
    my @pod_list   = keys %{$config_pod};

    print "<h2>Overview</h2>";

    print $html_tab_header->( 'Cluster', 'Running', 'Pending', 'Succeeded', 'Failed' );

    my %status;
    foreach my $pod (@pod_list) {
      if ( !defined $status{ $config_pod->{$pod}{cluster} }{ $config_pod->{$pod}{status} } ) {
        $status{ $config_pod->{$pod}{cluster} }{ $config_pod->{$pod}{status} } = 1;
      }
      else {
        $status{ $config_pod->{$pod}{cluster} }{ $config_pod->{$pod}{status} } += 1;
      }
    }

    foreach my $status_key ( keys %status ) {
      my $runnig    = defined $status{$status_key}{Running}   ? "<td class=\"hs_good\"><div style=\"padding:4px 10px;\">$status{$status_key}{Running}</div></td>"   : "<td><div style=\"padding:4px 10px;\">0</div></td>";
      my $pending   = defined $status{$status_key}{Pending}   ? "<td><div style=\"padding:4px 10px;\">$status{$status_key}{Pending}</div></td>"                     : "<td><div style=\"padding:4px 10px;\">0</div></td>";
      my $succeeded = defined $status{$status_key}{Succeeded} ? "<td><div style=\"padding:4px 10px;\">$status{$status_key}{Succeeded}</div></td>"                   : "<td><div style=\"padding:4px 10px;\">0</div></td>";
      my $failed    = defined $status{$status_key}{Failed}    ? "<td class=\"hs_warning\"><div style=\"padding:4px 10px;\">$status{$status_key}{Failed}</div></td>" : "<td><div style=\"padding:4px 10px;\">0</div></td>";

      print $html_table_row->( "<td><div style=\"padding:4px 10px;\">$status_key</div></td>", $runnig, $pending, $succeeded, $failed );

    }

    print $html_tab_footer2;

    print "<h3>All Pods</h3>";

    print $html_tab_header->( 'Name', 'Cluster', 'State' );

    my $state;
    my %resorter;
    foreach my $pod ( keys %{$config_pod} ) {
      my $url = KubernetesMenu::get_url( { type => 'pod', pod => $pod } );
      $state = $config_pod->{$pod}{status} eq "Running" ? "<td class=\"hs_good\"><div style=\"padding:4px 10px;\">Running</div></td>" : "<td class=\"hs_warning\"><div style=\"padding:4px 10px;\">$config_pod->{$pod}{status}</div></td>";
      my $table_print = $html_table_row->( "<td><div style=\"padding:4px 10px;\"><a href=\"$url\" class=\"backlink\">$config_pod->{$pod}{name}</a></div></td>", "<td><div style=\"padding:4px 10px;\">$config_pod->{$pod}{cluster}</div></td>", $state );
      if ( defined $resorter{ $config_pod->{$pod}{status} }[0] ) {
        push( @{ $resorter{ $config_pod->{$pod}{status} } }, $table_print );
      }
      else {
        $resorter{ $config_pod->{$pod}{status} }[0] = $table_print;
      }
    }

    foreach my $status_array ( sort { lc $b cmp lc $a } keys %resorter ) {
      foreach my $to_print ( @{ $resorter{$status_array} } ) {
        print $to_print;
      }
    }

    print $html_tab_footer;

    print "</div>\n";

  }
  elsif ( $params{type} =~ m/^conditions/ ) {
    my $config_update_time = localtime( KubernetesDataWrapper::get_conf_update_time() );

    my $html_tab_header = sub {
      my @columns = @_;
      my $result  = '';
      $result .= "<center>";
      $result .= "<table class=\"tabconfig tablesorter\">";
      $result .= "<thead><tr>";
      foreach my $item (@columns) {
        $result .= "<th class=\"sortable\">" . $item . "</th>";
      }
      $result .= "</tr></thead>";
      $result .= "<tbody>";

      return $result;
    };

    my $html_table_row = sub {
      my @cells  = @_;
      my $result = '';

      $result .= "<tr>";
      foreach my $cell (@cells) { $result .= $cell; }
      $result .= "</tr>";

      return $result;
    };

    my $html_tab_footer  = "</tbody></table><p>Last update time: " . $config_update_time . "</p></center>";
    my $html_tab_footer2 = "</tbody></table></center>";

    print "<h2>Conditions</h2>";
    my @pods;

    #cluster conditions
    if ( $params{type} =~ m/^conditions-cluster/ ) {
      my @pods2 = @{ KubernetesDataWrapper::get_items( { item_type => 'pod', parent_type => 'cluster', parent_id => $params{id} } ) };
      foreach my $pod2 (@pods2) {
        my ( $pod_uuid, $pod_label ) = each %{$pod2};
        push( @pods, $pod_uuid );
      }

      #single pod conditions
    }
    elsif ( $params{type} =~ m/^conditions-pod/ ) {
      push( @pods, $params{id} );
    }

    my $config_pods = KubernetesDataWrapper::get_pods();
    for (@pods) {
      my $pod = $_;
      my $url = KubernetesMenu::get_url( { type => 'pod', pod => $pod } );
      print "<p><a href=\"$url\" class=\"backlink\">$config_pods->{$pod}{name}</a></p>";
      print $html_tab_header->( 'Type', 'Status', 'lastProbeTime', 'lastTransitionTime' );
      for ( @{ $config_pods->{$pod}{conditions} } ) {
        my $condition          = $_;
        my $state              = $condition->{status} eq "True"           ? "<td class=\"hs_good\"><div style=\"padding:4px 10px;\">$condition->{status}</div></td>" : "<td class=\"hs_warning\"><div style=\"padding:4px 10px;\">$condition->{status}</div></td>";
        my $lastProbeTime      = defined $condition->{lastProbeTime}      ? $condition->{lastProbeTime}                                                              : "-";
        my $lastTransitionTime = defined $condition->{lastTransitionTime} ? $condition->{lastTransitionTime}                                                         : "-";
        print $html_table_row->( "<td><div style=\"padding:4px 10px;\">$condition->{type}</div></td>", $state, "<td><div style=\"padding:4px 10px;\">$lastProbeTime</div></td>", "<td><div style=\"padding:4px 10px;\">$lastTransitionTime</div></td>" );
      }
      print $html_tab_footer2;
    }

  }
  elsif ( $params{type} =~ m/^containers-info/ ) {
    my $config_update_time = localtime( KubernetesDataWrapper::get_conf_update_time() );

    my $html_tab_header = sub {
      my @columns = @_;
      my $result  = '';
      $result .= "<center>";
      $result .= "<table class=\"tabconfig tablesorter\">";
      $result .= "<thead><tr>";
      foreach my $item (@columns) {
        $result .= "<th class=\"sortable\">" . $item . "</th>";
      }
      $result .= "</tr></thead>";
      $result .= "<tbody>";

      return $result;
    };

    my $html_table_row = sub {
      my @cells  = @_;
      my $result = '';

      $result .= "<tr>";
      foreach my $cell (@cells) { $result .= $cell; }
      $result .= "</tr>";

      return $result;
    };

    my $html_tab_footer  = "</tbody></table><p>Last update time: " . $config_update_time . "</p></center>";
    my $html_tab_footer2 = "</tbody></table></center>";

    print "<h2>Containers info</h2>";
    my $pod_hash = KubernetesDataWrapper::get_pod( $params{id} );

    for ( @{ $pod_hash->{containers} } ) {
      my $container = $_;
      my $commands;
      if ( defined $container->{command} && scalar @{ $container->{command} } >= 1 ) {
        for ( @{ $container->{command} } ) {
          my $command = $_;
          $commands .= "$command <br>";
        }
      }
      else {
        $commands .= "no command set";
      }
      my $volumeMounts;
      if ( defined $container->{volumeMounts} && scalar @{ $container->{volumeMounts} } >= 1 ) {
        for ( @{ $container->{volumeMounts} } ) {
          my $volumeMount = $_;
          $volumeMounts .= "Name: $volumeMount->{name} <br>Path: $volumeMount->{mountPath}<br><br>";
        }
      }
      else {
        $volumeMounts .= "no volume mounts set";
      }
      print "<h4>$container->{name}</h4>";
      print "<table style=\"border:solid 1px #000;\">";
      print "<tr>";
      print "<td style=\"padding:10px; vertical-align: top; min-width:384px; padding-right:10px;\"><b>Image:</b> $container->{image}<br><br><b>terminationMessagePath:</b> $container->{terminationMessagePath}<br><br><b>Volume Mounts:</b><br>$volumeMounts</td>";
      print "<td style=\"padding:10px; min-width:384px; vertical-align: top;\"><b>Command</b><br>$commands</td>";
      print "</tr>";
      print "</table>";
    }

  }
  elsif ( $params{type} =~ m/^services/ ) {
    my $config_update_time = localtime( KubernetesDataWrapper::get_conf_update_time() );

    my $html_tab_header = sub {
      my @columns = @_;
      my $result  = '';
      $result .= "<center>";
      $result .= "<table class=\"tabconfig tablesorter\">";
      $result .= "<thead><tr>";
      foreach my $item (@columns) {
        $result .= "<th class=\"sortable\">" . $item . "</th>";
      }
      $result .= "</tr></thead>";
      $result .= "<tbody>";

      return $result;
    };

    my $html_table_row = sub {
      my @cells  = @_;
      my $result = '';

      $result .= "<tr>";
      foreach my $cell (@cells) { $result .= $cell; }
      $result .= "</tr>";

      return $result;
    };

    my $html_tab_footer  = "</tbody></table><p>Last update time: " . $config_update_time . "</p></center>";
    my $html_tab_footer2 = "</tbody></table></center>";

    print "<h2>Services</h2>";

    print $html_tab_header->( 'UUID', 'Name', 'Namespace', 'Labels', 'Cluster IP', 'Ports' );

    my $config_services = KubernetesDataWrapper::get_conf_section('spec-service');
    my @services        = @{ KubernetesDataWrapper::get_items( { item_type => 'service', parent_type => 'cluster', parent_id => $params{id} } ) };

    foreach my $service_item (@services) {
      my ( $service, $label ) = each %{$service_item};
      my $ports = "";
      if ( defined $config_services->{$service}{ports} ) {
        for ( @{ $config_services->{$service}{ports} } ) {
          my $port     = $_;
          my $portName = defined $port->{name} ? $port->{name} : "-";
          $ports .= "Name: $portName ($port->{protocol}), Port: $port->{port}, Target: $port->{targetPort}<br>";
        }
      }
      else {
        $ports .= "no port specified";
      }

      my $labels = "";
      if ( defined $config_services->{$service}{labels} ) {
        foreach my $key ( keys %{ $config_services->{$service}{labels} } ) {
          $labels .= "$key: $config_services->{$service}{labels}{$key}<br>";
        }
      }
      else {
        $labels .= "no labels specified";
      }

      print $html_table_row->( "<td><div style=\"padding:4px 10px;\">$config_services->{$service}{uid}</div></td>", "<td><div style=\"padding:4px 10px;\">$config_services->{$service}{name}</div></td>", "<td><div style=\"padding:4px 10px;\">$config_services->{$service}{namespace}</div></td>", "<td><div style=\"padding:4px 10px;\">$labels</div></td>", "<td><div style=\"padding:4px 10px;\">$config_services->{$service}{clusterIP}</div></td>", "<td><div style=\"padding:4px 10px;\">$ports</div></td>" );
    }

    print $html_tab_footer;

  }
  elsif ( $params{type} =~ m/^endpoints/ ) {
    my $config_update_time = localtime( KubernetesDataWrapper::get_conf_update_time() );

    my $html_tab_header = sub {
      my @columns = @_;
      my $result  = '';
      $result .= "<center>";
      $result .= "<table class=\"tabconfig tablesorter\">";
      $result .= "<thead><tr>";
      foreach my $item (@columns) {
        $result .= "<th class=\"sortable\">" . $item . "</th>";
      }
      $result .= "</tr></thead>";
      $result .= "<tbody>";

      return $result;
    };

    my $html_table_row = sub {
      my @cells  = @_;
      my $result = '';

      $result .= "<tr>";
      foreach my $cell (@cells) { $result .= $cell; }
      $result .= "</tr>";

      return $result;
    };

    my $html_tab_footer  = "</tbody></table><p>Last update time: " . $config_update_time . "</p></center>";
    my $html_tab_footer2 = "</tbody></table></center>";

    print "<h2>Endpoints</h2>";

    my $config_endpoints = KubernetesDataWrapper::get_conf_section('spec-endpoint');
    my @endpoints        = @{ KubernetesDataWrapper::get_items( { item_type => 'endpoint', parent_type => 'cluster', parent_id => $params{id} } ) };

    foreach my $endpoint_item (@endpoints) {
      my ( $endpoint, $label ) = each %{$endpoint_item};

      print "<h4>$label</h4>";

      if ( defined $config_endpoints->{$endpoint} ) {

        print $html_tab_header->( 'IP', 'Node Name', 'Target Ref' );

        for ( @{ $config_endpoints->{$endpoint} } ) {
          my $subset = $_;

          for ( @{ $subset->{addresses} } ) {
            my $adress = $_;

            if ( !defined $adress->{nodeName} )          { $adress->{nodeName}          = " - "; }
            if ( !defined $adress->{targetRef}->{name} ) { $adress->{targetRef}->{name} = " - "; }
            if ( !defined $adress->{targetRef}->{kind} ) { $adress->{targetRef}->{kind} = " - "; }

            print $html_table_row->( "<td><div style=\"padding:4px 10px;\">$adress->{ip}</div></td>", "<td><div style=\"padding:4px 10px;\">$adress->{nodeName}</div></td>", "<td><div style=\"padding:4px 10px;\">$adress->{targetRef}->{name} ($adress->{targetRef}->{kind})</div></td>" );
          }
        }

        print $html_tab_footer2;

        print $html_tab_header->( 'Name', 'Port', 'Protocol' );

        for ( @{ $config_endpoints->{$endpoint} } ) {
          my $subset = $_;

          for ( @{ $subset->{ports} } ) {
            my $port = $_;

            if ( !defined $port->{name} ) { $port->{name} = " - "; }

            print $html_table_row->( "<td><div style=\"padding:4px 10px;\">$port->{name}</div></td>", "<td><div style=\"padding:4px 10px;\">$port->{port}</div></td>", "<td><div style=\"padding:4px 10px;\">$port->{protocol}</div></td>" );
          }
        }

        print $html_tab_footer2;

      }
      else {
        print "<i>No adresses set in this endpoint</i><br>";
      }

      print "<br>";

    }
  }

  # closing page contents
  print "</CENTER>";
  print "</div><br>\n";

  exit(0);
}

# Openshift
if ($openshift) {

  # TODO temporary wrapper for compatibility with legacy subroutines interfacing mainly detail-graph-cgi.pl
  $host_url = 'Openshift';

  #print "<script>console.log('type: $params{type}, id: $params{id}');</script>";
  if ( $params{type} =~ m/node-aggr/ || $params{type} =~ m/pod-aggr/ || $params{type} =~ m/container-aggr/ || $params{type} =~ m/namespace-aggr/ ) {
    $server_url = $params{id};
    $lpar_url   = 'nope';
  }
  elsif ( $params{type} =~ m/node/ || $params{type} =~ m/pod/ || $params{type} =~ m/container/ || $params{type} =~ m/project/ || $params{type} =~ m/namespace/ ) {
    $server_url = $params{id};
    $lpar_url   = $params{id};
  }
  else {
    $lpar_url   = 'nope';
    $server_url = 'nope';
  }

  # print page contents
  print "<CENTER>";

  # get tabs
  my @tabs = @{ OpenshiftMenu::get_tabs( $params{type} ) };

  if (@tabs) {
    print "<div id=\"tabs\">\n";
    print "<ul>\n";

    my $tab_counter = 1;
    foreach my $tab_header (@tabs) {
      while ( my ( $tab_type, $tab_label ) = each %$tab_header ) {
        print "  <li class=\"$tab_type\"><a href=\"#tabs-$tab_counter\">$tab_label</a></li>\n";
        $tab_counter++;
      }
    }
    print "</ul>\n";
  }

  # print tab contents
  sub print_tab_contents_openshift {
    my ( $tab_number, $host_url, $server_url, $lpar_url, $item, $entitle, $detail_yes, $legend ) = @_;

    print "<div id=\"tabs-$tab_number\">\n";
    print "<table border=\"0\">\n";
    print "<tr>";

    print_item( $host_url, $server_url, $lpar_url, $item, "d", "", $entitle, $detail_yes, "norefr", "star", 1, $legend );
    print_item( $host_url, $server_url, $lpar_url, $item, "w", "", $entitle, $detail_yes, "norefr", "star", 1, $legend );
    print "</tr>\n<tr>\n";
    print_item( $host_url, $server_url, $lpar_url, $item, "m", "", $entitle, $detail_yes, "norefr", "star", 1, $legend );
    print_item( $host_url, $server_url, $lpar_url, $item, "y", "", $entitle, $detail_yes, "norefr", "star", 1, $legend );
    print "</tr></table>";
    print "</div>\n";
  }

  my $legend = ( $params{type} =~ m/aggr/ ) ? 'nolegend' : 'legend';
  if ( $params{type} =~ m/^node$/ ) {
    my @openshift_items = ( 'openshift-node-cpu-percent', 'openshift-node-cpu', 'openshift-node-memory', 'openshift-node-pods', 'openshift-node-data', 'openshift-node-iops', 'openshift-node-latency', 'openshift-node-net' );
    for $tab_number ( 1 .. $#openshift_items + 1 ) {
      $legend = ( $openshift_items[ $tab_number - 1 ] =~ m/aggr/ ) ? 'nolegend' : 'legend';
      print_tab_contents_openshift( $tab_number, $host_url, $server_url, $lpar_url, $openshift_items[ $tab_number - 1 ], $entitle, $detail_yes, $legend );
    }
  }
  elsif ( $params{type} =~ m/^node-aggr$/ ) {
    my @openshift_items = ( 'openshift-node-cpu-percent-aggr', 'openshift-node-cpu-aggr', 'openshift-node-memory-aggr', 'openshift-node-pods-aggr', 'openshift-node-data-aggr', 'openshift-node-iops-aggr', 'openshift-node-latency-aggr', 'openshift-node-net-aggr' );
    for $tab_number ( 1 .. $#openshift_items + 1 ) {
      $legend = ( $openshift_items[ $tab_number - 1 ] =~ m/aggr/ ) ? 'nolegend' : 'legend';
      print_tab_contents_openshift( $tab_number, $host_url, $server_url, $lpar_url, $openshift_items[ $tab_number - 1 ], $entitle, $detail_yes, $legend );
    }
  }
  elsif ( $params{type} =~ m/^pod$/ ) {
    my @openshift_items = ( 'openshift-pod-cpu', 'openshift-pod-container-cpu-aggr', 'openshift-pod-memory', 'openshift-pod-container-memory-aggr', 'openshift-pod-net', 'openshift-pod-container-data-aggr', 'openshift-pod-container-iops-aggr', 'openshift-pod-container-latency-aggr' );
    for $tab_number ( 1 .. $#openshift_items + 1 ) {
      $legend = ( $openshift_items[ $tab_number - 1 ] =~ m/aggr/ ) ? 'nolegend' : 'legend';
      print_tab_contents_openshift( $tab_number, $host_url, $server_url, $lpar_url, $openshift_items[ $tab_number - 1 ], $entitle, $detail_yes, $legend );
    }
  }
  elsif ( $params{type} =~ m/^project-pod-aggr$/ ) {
    my @openshift_items = ( 'openshift-project-pod-cpu-aggr', 'openshift-project-container-cpu-aggr', 'openshift-project-pod-memory-aggr', 'openshift-project-container-memory-aggr', 'openshift-project-container-data-aggr', 'openshift-project-container-iops-aggr', 'openshift-project-container-latency-aggr', 'openshift-project-pod-network-aggr' );
    for $tab_number ( 1 .. $#openshift_items + 1 ) {
      $legend = ( $openshift_items[ $tab_number - 1 ] =~ m/aggr/ ) ? 'nolegend' : 'legend';
      print_tab_contents_openshift( $tab_number, $host_url, $server_url, $lpar_url, $openshift_items[ $tab_number - 1 ], $entitle, $detail_yes, $legend );
    }
  }
  elsif ( $params{type} =~ m/^container$/ ) {
    my @openshift_items = ( 'openshift-container-cpu', 'openshift-container-memory', 'openshift-container-data', 'openshift-container-iops', 'openshift-container-latency' );
    for $tab_number ( 1 .. $#openshift_items + 1 ) {
      $legend = ( $openshift_items[ $tab_number - 1 ] =~ m/aggr/ ) ? 'nolegend' : 'legend';
      print_tab_contents_openshift( $tab_number, $host_url, $server_url, $lpar_url, $openshift_items[ $tab_number - 1 ], $entitle, $detail_yes, $legend );
    }
  }
  elsif ( $params{type} =~ m/^namespace$/ ) {
    my @openshift_items = ( 'openshift-namespace-cpu', 'openshift-namespace-memory' );
    for $tab_number ( 1 .. $#openshift_items + 1 ) {
      $legend = ( $openshift_items[ $tab_number - 1 ] =~ m/aggr/ ) ? 'nolegend' : 'legend';
      print_tab_contents_openshift( $tab_number, $host_url, $server_url, $lpar_url, $openshift_items[ $tab_number - 1 ], $entitle, $detail_yes, $legend );
    }
  }
  elsif ( $params{type} =~ m/^namespace-aggr$/ ) {
    my @openshift_items = ( 'openshift-namespace-cpu-aggr', 'openshift-namespace-memory-aggr' );
    for $tab_number ( 1 .. $#openshift_items + 1 ) {
      $legend = ( $openshift_items[ $tab_number - 1 ] =~ m/aggr/ ) ? 'nolegend' : 'legend';
      print_tab_contents_openshift( $tab_number, $host_url, $server_url, $lpar_url, $openshift_items[ $tab_number - 1 ], $entitle, $detail_yes, $legend );
    }
  }
  elsif ( $params{type} =~ m/^configuration$/ ) {
    my $openshiftWrapper   = OpenshiftDataWrapperOOP->new();
    my $config_update_time = localtime( $openshiftWrapper->{updated} );

    my $html_tab_header = sub {
      my @columns = @_;
      my $result  = '';
      $result .= "<center>";
      $result .= "<table class=\"tabconfig tablesorter\">";
      $result .= "<thead><tr>";
      foreach my $item (@columns) {
        $result .= "<th class=\"sortable\">" . $item . "</th>";
      }
      $result .= "</tr></thead>";
      $result .= "<tbody>";

      return $result;
    };

    my $html_table_row = sub {
      my @cells  = @_;
      my $result = '';

      $result .= "<tr>";
      foreach my $cell (@cells) { $result .= $cell; }
      $result .= "</tr>";

      return $result;
    };

    my $html_tab_footer  = "</tbody></table><p>Last update time: " . $config_update_time . "</p></center>";
    my $html_tab_footer2 = "</tbody></table></center>";

    # Node
    print "<div id=\"tabs-1\">\n";

    print "<h2>Node</h2>";

    print $html_tab_header->( 'Cluster', 'Name', 'OS Image', 'Container Runtime Version', 'Operating System', 'Architecture' );

    my $config_node = $openshiftWrapper->get_conf_section('spec-node');
    my @node_list   = keys %{$config_node};

    foreach my $node (@node_list) {
      print $html_table_row->( "<td><div>$config_node->{$node}{cluster}</div></td>", "<td><div>$config_node->{$node}{name}</div></td>", "<td><div>$config_node->{$node}{nodeInfo}{osImage}</div></td>", "<td><div>$config_node->{$node}{nodeInfo}{containerRuntimeVersion}</div></td>", "<td><div>$config_node->{$node}{nodeInfo}{operatingSystem}</div></td>", "<td><div>$config_node->{$node}{nodeInfo}{architecture}</div></td>" );
    }

    print $html_tab_footer;

    print "</div>\n";

    # Pods
    print "<div id=\"tabs-2\">\n";

    print "<h2>Pods</h2>";

    print $html_tab_header->( 'Cluster', 'Name', 'IP' );

    my $config_pod = $openshiftWrapper->get_conf_section('spec-pod');
    my @pod_list   = keys %{$config_pod};

    foreach my $pod (@pod_list) {
      my $url = OpenshiftMenu::get_url( { type => 'pod', pod => $pod } );
      print $html_table_row->( "<td><div>$config_pod->{$pod}{cluster}</div></td>", "<td><div><a href=\"$url\">$config_pod->{$pod}{name}</a></div></td>", "<td><div>$config_pod->{$pod}{podIP}</div></td>" );
    }

    print $html_tab_footer;

    print "</div>\n";

  }
  elsif ( $params{type} =~ m/^top$/ || $params{type} =~ m/^top-cluster$/ ) {
    my $openshiftWrapper   = OpenshiftDataWrapperOOP->new();
    my $config_update_time = localtime( $openshiftWrapper->{updated} );

    my $html_tab_header = sub {
      my @columns = @_;
      my $result  = '';
      $result .= "<center>";
      $result .= "<table class=\"tabconfig tablesorter\">";
      $result .= "<thead><tr>";
      foreach my $item (@columns) {
        $result .= "<th class=\"sortable\">" . $item . "</th>";
      }
      $result .= "</tr></thead>";
      $result .= "<tbody>";

      return $result;
    };

    my $html_table_row = sub {
      my @cells  = @_;
      my $result = '';

      $result .= "<tr>";
      foreach my $cell (@cells) { $result .= $cell; }
      $result .= "</tr>";

      return $result;
    };

    my $html_tab_footer  = "</tbody></table><p>Last update time: " . $config_update_time . "</p></center>";
    my $html_tab_footer2 = "</tbody></table></center>";

    # Pods
    print "<div id=\"tabs-1\">\n";

    print "<h2>Pods TOP</h2>";
    print "<b>20 minutes average</b><br><br>";

    print $html_tab_header->( 'Name', 'CPU [cores]', 'Memory [MiB]' );

    my $config_pod = $openshiftWrapper->get_conf_section('spec-pod');
    my $top_pod    = OpenshiftDataWrapper::get_top();
    my @pod_list   = keys %{ $top_pod->{pod} };

    my $pods_filter;
    if ( $params{type} =~ m/^top-cluster$/ ) {
      my @pods_tmp = @{ $openshiftWrapper->get_items( { item_type => 'pod', parent_type => 'cluster', parent_id => $params{id} } ) };
      foreach my $pod2 (@pods_tmp) {
        my ( $pod_uuid, $pod_label ) = each %{$pod2};
        $pods_filter->{$pod_uuid} = $pod_label;
      }
    }

    foreach my $pod ( sort { $top_pod->{pod}{$b}{cpu} <=> $top_pod->{pod}{$a}{cpu} } keys %{ $top_pod->{pod} } ) {

      if ( $params{type} =~ m/^top-cluster$/ && !defined $pods_filter->{$pod} ) { next; }

      my $url    = OpenshiftMenu::get_url( { type => 'pod', pod => $pod } );
      my $cpu    = defined $top_pod->{pod}->{$pod}->{cpu}    && defined $top_pod->{pod}->{$pod}->{counter} ? sprintf( "%.3f", $top_pod->{pod}->{$pod}->{cpu} / $top_pod->{pod}->{$pod}->{counter} )    : "undef";
      my $memory = defined $top_pod->{pod}->{$pod}->{memory} && defined $top_pod->{pod}->{$pod}->{counter} ? sprintf( "%.0f", $top_pod->{pod}->{$pod}->{memory} / $top_pod->{pod}->{$pod}->{counter} ) : "undef";

      print $html_table_row->( "<td><div><a href=\"$url\">$config_pod->{$pod}{name}</a></div></td>", "<td><div>$cpu</div></td>", "<td><div>$memory</div></td>" );
    }

    print $html_tab_footer;

    print "</div>\n";

  }
  elsif ( $params{type} =~ m/^pods-overview$/ || $params{type} =~ m/^pods-overview-cluster$/ ) {
    my $openshiftWrapper   = OpenshiftDataWrapperOOP->new();
    my $config_update_time = localtime( $openshiftWrapper->{updated} );

    my $html_tab_header = sub {
      my @columns = @_;
      my $result  = '';
      $result .= "<center>";
      $result .= "<table class=\"tabconfig tablesorter\">";
      $result .= "<thead><tr>";
      foreach my $item (@columns) {
        $result .= "<th class=\"sortable\">" . $item . "</th>";
      }
      $result .= "</tr></thead>";
      $result .= "<tbody>";

      return $result;
    };

    my $html_table_row = sub {
      my @cells  = @_;
      my $result = '';

      $result .= "<tr>";
      foreach my $cell (@cells) { $result .= $cell; }
      $result .= "</tr>";

      return $result;
    };
    my $html_tab_footer  = "</tbody></table><p>Last update time: " . $config_update_time . "</p></center>";
    my $html_tab_footer2 = "</tbody></table></center>";

    # Overview
    print "<div id=\"tabs-1\">\n";

    my $config_pod = $openshiftWrapper->get_conf_section('spec-pod');
    my @pod_list   = keys %{$config_pod};

    print "<h2>Overview</h2>";

    print $html_tab_header->( 'Cluster', 'Running', 'Pending', 'Succeeded', 'Failed' );

    my $pods_filter;
    if ( $params{type} =~ m/^pods-overview-cluster$/ ) {
      my @pods_tmp = @{ $openshiftWrapper->get_items( { item_type => 'pod', parent_type => 'cluster', parent_id => $params{id} } ) };
      foreach my $pod2 (@pods_tmp) {
        my ( $pod_uuid, $pod_label ) = each %{$pod2};
        $pods_filter->{$pod_uuid} = $pod_label;
      }
    }

    my %status;
    foreach my $pod (@pod_list) {
      if ( $params{type} =~ m/^pods-overview-cluster$/ && !defined $pods_filter->{$pod} ) { next; }

      if ( !defined $status{ $config_pod->{$pod}{cluster} }{ $config_pod->{$pod}{status} } ) {
        $status{ $config_pod->{$pod}{cluster} }{ $config_pod->{$pod}{status} } = 1;
      }
      else {
        $status{ $config_pod->{$pod}{cluster} }{ $config_pod->{$pod}{status} } += 1;
      }
    }

    foreach my $status_key ( keys %status ) {
      my $runnig    = defined $status{$status_key}{Running}   ? "<td class=\"hs_good\"><div>$status{$status_key}{Running}</div></td>"   : "<td><div>0</div></td>";
      my $pending   = defined $status{$status_key}{Pending}   ? "<td><div>$status{$status_key}{Pending}</div></td>"                     : "<td><div>0</div></td>";
      my $succeeded = defined $status{$status_key}{Succeeded} ? "<td><div>$status{$status_key}{Succeeded}</div></td>"                   : "<td><div>0</div></td>";
      my $failed    = defined $status{$status_key}{Failed}    ? "<td class=\"hs_warning\"><div>$status{$status_key}{Failed}</div></td>" : "<td><div>0</div></td>";

      print $html_table_row->( "<td><div>$status_key</div></td>", $runnig, $pending, $succeeded, $failed );

    }

    print $html_tab_footer2;

    print "<h3>All Pods</h3>";

    print $html_tab_header->( 'Name', 'Cluster', 'State' );

    my $state;
    my %resorter;
    foreach my $pod ( keys %{$config_pod} ) {
      if ( $params{type} =~ m/^pods-overview-cluster$/ && !defined $pods_filter->{$pod} ) { next; }
      my $url = OpenshiftMenu::get_url( { type => 'pod', pod => $pod } );
      $state = $config_pod->{$pod}{status} eq "Running" ? "<td class=\"hs_good\"><div style=\"padding:4px 10px;\">Running</div></td>" : "<td class=\"hs_warning\"><div style=\"padding:4px 10px;\">$config_pod->{$pod}{status}</div></td>";
      my $table_print = $html_table_row->( "<td><div style=\"padding:4px 10px;\"><a href=\"$url\" class=\"backlink\">$config_pod->{$pod}{name}</a></div></td>", "<td><div style=\"padding:4px 10px;\">$config_pod->{$pod}{cluster}</div></td>", $state );
      if ( defined $resorter{ $config_pod->{$pod}{status} }[0] ) {
        push( @{ $resorter{ $config_pod->{$pod}{status} } }, $table_print );
      }
      else {
        $resorter{ $config_pod->{$pod}{status} }[0] = $table_print;
      }
    }

    foreach my $status_array ( sort { lc $a cmp lc $b } keys %resorter ) {
      foreach my $to_print ( @{ $resorter{$status_array} } ) {
        print $to_print;
      }
    }

    print $html_tab_footer;

    print "</div>\n";
  }
  elsif ( $params{type} =~ m/^conditions/ ) {
    my $openshiftWrapper   = OpenshiftDataWrapperOOP->new();
    my $config_update_time = localtime( $openshiftWrapper->{updated} );

    my $html_tab_header = sub {
      my @columns = @_;
      my $result  = '';
      $result .= "<center>";
      $result .= "<table class=\"tabconfig tablesorter\">";
      $result .= "<thead><tr>";
      foreach my $item (@columns) {
        $result .= "<th class=\"sortable\">" . $item . "</th>";
      }
      $result .= "</tr></thead>";
      $result .= "<tbody>";

      return $result;
    };

    my $html_table_row = sub {
      my @cells  = @_;
      my $result = '';

      $result .= "<tr>";
      foreach my $cell (@cells) { $result .= $cell; }
      $result .= "</tr>";

      return $result;
    };

    my $html_tab_footer  = "</tbody></table><p>Last update time: " . $config_update_time . "</p></center>";
    my $html_tab_footer2 = "</tbody></table></center>";

    print "<h2>Conditions</h2>";
    my @pods;

    #cluster conditions
    if ( $params{type} =~ m/^conditions-cluster/ ) {
      my @pods2 = @{ $openshiftWrapper->get_items( { item_type => 'pod', parent_type => 'cluster', parent_id => $params{id} } ) };
      foreach my $pod2 (@pods2) {
        my ( $pod_uuid, $pod_label ) = each %{$pod2};
        push( @pods, $pod_uuid );
      }

      #single pod conditions
    }
    elsif ( $params{type} =~ m/^conditions-pod/ ) {
      push( @pods, $params{id} );
    }
    my $config_pods = OpenshiftDataWrapper::get_pods();
    for (@pods) {
      my $pod = $_;
      my $url = OpenshiftMenu::get_url( { type => 'pod', pod => $pod } );
      print "<p><a href=\"$url\" class=\"backlink\">$config_pods->{$pod}{name}</a></p>";
      print $html_tab_header->( 'Type', 'Status', 'lastProbeTime', 'lastTransitionTime' );
      for ( @{ $config_pods->{$pod}{conditions} } ) {
        my $condition          = $_;
        my $state              = $condition->{status} eq "True"           ? "<td class=\"hs_good\"><div style=\"padding:4px 10px;\">$condition->{status}</div></td>" : "<td class=\"hs_warning\"><div style=\"padding:4px 10px;\">$condition->{status}</div></td>";
        my $lastProbeTime      = defined $condition->{lastProbeTime}      ? $condition->{lastProbeTime}                                                              : "-";
        my $lastTransitionTime = defined $condition->{lastTransitionTime} ? $condition->{lastTransitionTime}                                                         : "-";
        print $html_table_row->( "<td><div style=\"padding:4px 10px;\">$condition->{type}</div></td>", $state, "<td><div style=\"padding:4px 10px;\">$lastProbeTime</div></td>", "<td><div style=\"padding:4px 10px;\">$lastTransitionTime</div></td>" );
      }
      print $html_tab_footer2;
    }

  }
  elsif ( $params{type} =~ m/^services/ ) {
    my $openshiftWrapper   = OpenshiftDataWrapperOOP->new();
    my $config_update_time = localtime( $openshiftWrapper->{updated} );

    my $html_tab_header = sub {
      my @columns = @_;
      my $result  = '';
      $result .= "<center>";
      $result .= "<table class=\"tabconfig tablesorter\">";
      $result .= "<thead><tr>";
      foreach my $item (@columns) {
        $result .= "<th class=\"sortable\">" . $item . "</th>";
      }
      $result .= "</tr></thead>";
      $result .= "<tbody>";

      return $result;
    };

    my $html_table_row = sub {
      my @cells  = @_;
      my $result = '';

      $result .= "<tr>";
      foreach my $cell (@cells) { $result .= $cell; }
      $result .= "</tr>";

      return $result;
    };
    my $html_tab_footer  = "</tbody></table><p>Last update time: " . $config_update_time . "</p></center>";
    my $html_tab_footer2 = "</tbody></table></center>";

    print "<h2>Services</h2>";

    print $html_tab_header->( 'Name', 'Namespace', 'Labels', 'Cluster IP', 'Ports' );

    my $config_services = $openshiftWrapper->get_conf_section('spec-service');
    my @services        = @{ $openshiftWrapper->get_items( { item_type => 'service', parent_type => 'cluster', parent_id => $params{id} } ) };

    foreach my $service_item (@services) {
      my ( $service, $label ) = each %{$service_item};
      my $ports = "";
      if ( defined $config_services->{$service}{spec}{ports} ) {
        for ( @{ $config_services->{$service}{spec}{ports} } ) {
          my $port     = $_;
          my $portName = defined $port->{name} ? $port->{name} : "-";
          $ports .= "Name: $portName ($port->{protocol}), Port: $port->{port}, Target: $port->{targetPort}<br>";
        }
      }
      else {
        $ports .= "no port specified";
      }

      my $labels = "";
      if ( defined $config_services->{$service}{metadata}{labels} ) {
        foreach my $key ( keys %{ $config_services->{$service}{metadata}{labels} } ) {
          $labels .= "$key: $config_services->{$service}{metadata}{labels}{$key}<br>";
        }
      }
      else {
        $labels .= "no labels specified";
      }

      print $html_table_row->( "<td><div>$config_services->{$service}{metadata}{name}</div></td>", "<td><div>$config_services->{$service}{metadata}{namespace}</div></td>", "<td><div>$labels</div></td>", "<td><div>$config_services->{$service}{spec}{clusterIP}</div></td>", "<td><div>$ports</div></td>" );
    }

    print $html_tab_footer;

  }
  elsif ( $params{type} =~ m/^infrastructure/ ) {
    my $openshiftWrapper   = OpenshiftDataWrapperOOP->new();
    my $config_update_time = localtime( $openshiftWrapper->{updated} );

    my $html_tab_header = sub {
      my @columns = @_;
      my $result  = '';
      $result .= "<center>";
      $result .= "<table class=\"tabconfig tablesorter\">";
      $result .= "<thead><tr>";
      foreach my $item (@columns) {
        $result .= "<th class=\"sortable\">" . $item . "</th>";
      }
      $result .= "</tr></thead>";
      $result .= "<tbody>";

      return $result;
    };

    my $html_table_row = sub {
      my @cells  = @_;
      my $result = '';

      $result .= "<tr>";
      foreach my $cell (@cells) { $result .= $cell; }
      $result .= "</tr>";

      return $result;
    };
    my $html_tab_footer  = "</tbody></table><p>Last update time: " . $config_update_time . "</p></center>";
    my $html_tab_footer2 = "</tbody></table></center>";

    print "<h2>Infrastructure</h2>";

    print $html_tab_header->( 'Name', 'Domain', 'Platform', 'Internal API', 'External API' );

    my $config_infrastructure = $openshiftWrapper->get_conf_section('spec-infrastructure');
    my @infrastructure_list   = keys %{$config_infrastructure};

    foreach my $infrastructure (@infrastructure_list) {
      print $html_table_row->( "<td><div>$config_infrastructure->{$infrastructure}{name}</div></td>", "<td><div>$config_infrastructure->{$infrastructure}{domain}</div></td>", "<td><div>$config_infrastructure->{$infrastructure}{platform}</div></td>", "<td><div>$config_infrastructure->{$infrastructure}{internalApi}</div></td>", "<td><div>$config_infrastructure->{$infrastructure}{api}</div></td>" );
    }

    print $html_tab_footer;

  }

  # closing page contents
  print "</CENTER>";
  print "</div><br>\n";

  exit(0);
}

# Cloudstack
if ($cloudstack) {

  # TODO temporary wrapper for compatibility with legacy subroutines interfacing mainly detail-graph-cgi.pl
  $host_url = 'Cloudstack';

  #print "<script>console.log('type: $params{type}, id: $params{id}');</script>";
  if ( $params{type} =~ m/host-aggr/ || $params{type} =~ m/instance-aggr/ || $params{type} =~ m/volume-aggr/ || $params{type} =~ m/primaryStorage-aggr/ ) {
    $server_url = $params{id};
    $lpar_url   = 'nope';
  }
  elsif ( $params{type} =~ m/host/ || $params{type} =~ m/instance/ || $params{type} =~ m/volume/ || $params{type} =~ m/primaryStorage/ ) {
    $server_url = $params{id};
    $lpar_url   = $params{id};
  }
  else {
    $lpar_url   = 'nope';
    $server_url = 'nope';
  }

  # print page contents
  print "<CENTER>";

  # get tabs
  my @tabs = @{ CloudstackMenu::get_tabs( $params{type} ) };

  if (@tabs) {
    print "<div id=\"tabs\">\n";
    print "<ul>\n";

    my $tab_counter = 1;
    foreach my $tab_header (@tabs) {
      while ( my ( $tab_type, $tab_label ) = each %$tab_header ) {
        print "  <li class=\"$tab_type\"><a href=\"#tabs-$tab_counter\">$tab_label</a></li>\n";
        $tab_counter++;
      }
    }
    print "</ul>\n";
  }

  # print tab contents
  sub print_tab_contents_cloudstack {
    my ( $tab_number, $host_url, $server_url, $lpar_url, $item, $entitle, $detail_yes, $legend ) = @_;

    print "<div id=\"tabs-$tab_number\">\n";
    print "<table border=\"0\">\n";
    print "<tr>";

    print_item( $host_url, $server_url, $lpar_url, $item, "d", "", $entitle, $detail_yes, "norefr", "star", 1, $legend );
    print_item( $host_url, $server_url, $lpar_url, $item, "w", "", $entitle, $detail_yes, "norefr", "star", 1, $legend );
    print "</tr>\n<tr>\n";
    print_item( $host_url, $server_url, $lpar_url, $item, "m", "", $entitle, $detail_yes, "norefr", "star", 1, $legend );
    print_item( $host_url, $server_url, $lpar_url, $item, "y", "", $entitle, $detail_yes, "norefr", "star", 1, $legend );
    print "</tr></table>";
    print "</div>\n";
  }

  my $legend = ( $params{type} =~ m/aggr/ ) ? 'nolegend' : 'legend';
  if ( $params{type} =~ m/^host$/ ) {
    my @cloudstack_items = ( 'cloudstack-host-cpu-cores', 'cloudstack-host-cpu', 'cloudstack-host-memory', 'cloudstack-host-net' );
    for $tab_number ( 1 .. $#cloudstack_items + 1 ) {
      $legend = ( $cloudstack_items[ $tab_number - 1 ] =~ m/aggr/ ) ? 'nolegend' : 'legend';
      print_tab_contents_cloudstack( $tab_number, $host_url, $server_url, $lpar_url, $cloudstack_items[ $tab_number - 1 ], $entitle, $detail_yes, $legend );
    }
  }
  elsif ( $params{type} =~ m/^instance$/ ) {
    my @cloudstack_items = ( 'cloudstack-instance-cpu', 'cloudstack-instance-memory', 'cloudstack-instance-iops', 'cloudstack-instance-data', 'cloudstack-instance-net' );
    for $tab_number ( 1 .. $#cloudstack_items + 1 ) {
      $legend = ( $cloudstack_items[ $tab_number - 1 ] =~ m/aggr/ ) ? 'nolegend' : 'legend';
      print_tab_contents_cloudstack( $tab_number, $host_url, $server_url, $lpar_url, $cloudstack_items[ $tab_number - 1 ], $entitle, $detail_yes, $legend );
    }
  }
  elsif ( $params{type} =~ m/^volume$/ ) {
    my @cloudstack_items = ( 'cloudstack-volume-size', 'cloudstack-volume-iops', 'cloudstack-volume-data' );
    for $tab_number ( 1 .. $#cloudstack_items + 1 ) {
      $legend = ( $cloudstack_items[ $tab_number - 1 ] =~ m/aggr/ ) ? 'nolegend' : 'legend';
      print_tab_contents_cloudstack( $tab_number, $host_url, $server_url, $lpar_url, $cloudstack_items[ $tab_number - 1 ], $entitle, $detail_yes, $legend );
    }
  }
  elsif ( $params{type} =~ m/^primaryStorage$/ ) {
    my @cloudstack_items = ( 'cloudstack-primaryStorage-size', 'cloudstack-primaryStorage-allocated' );
    for $tab_number ( 1 .. $#cloudstack_items + 1 ) {
      $legend = ( $cloudstack_items[ $tab_number - 1 ] =~ m/aggr/ ) ? 'nolegend' : 'legend';
      print_tab_contents_cloudstack( $tab_number, $host_url, $server_url, $lpar_url, $cloudstack_items[ $tab_number - 1 ], $entitle, $detail_yes, $legend );
    }
  }
  elsif ( $params{type} =~ m/^host-aggr/ ) {
    my @cloudstack_items = ( 'cloudstack-host-cpu-cores-aggr', 'cloudstack-host-cpu-aggr', 'cloudstack-host-memory-used-aggr', 'cloudstack-host-memory-free-aggr', 'cloudstack-host-net-aggr' );
    for $tab_number ( 1 .. $#cloudstack_items + 1 ) {
      $legend = ( $cloudstack_items[ $tab_number - 1 ] =~ m/aggr/ ) ? 'nolegend' : 'legend';
      print_tab_contents_cloudstack( $tab_number, $host_url, $server_url, $lpar_url, $cloudstack_items[ $tab_number - 1 ], $entitle, $detail_yes, $legend );
    }
  }
  elsif ( $params{type} =~ m/^instance-aggr$/ ) {
    my @cloudstack_items = ( 'cloudstack-instance-cpu-aggr', 'cloudstack-instance-memory-used-aggr', 'cloudstack-instance-memory-free-aggr', 'cloudstack-instance-iops-aggr', 'cloudstack-instance-data-aggr', 'cloudstack-instance-net-aggr' );
    for $tab_number ( 1 .. $#cloudstack_items + 1 ) {
      $legend = ( $cloudstack_items[ $tab_number - 1 ] =~ m/aggr/ ) ? 'nolegend' : 'legend';
      print_tab_contents_cloudstack( $tab_number, $host_url, $server_url, $lpar_url, $cloudstack_items[ $tab_number - 1 ], $entitle, $detail_yes, $legend );
    }
  }
  elsif ( $params{type} =~ m/^volume-aggr$/ ) {
    my @cloudstack_items = ( 'cloudstack-volume-size-free-aggr', 'cloudstack-volume-size-used-aggr', 'cloudstack-volume-iops-aggr', 'cloudstack-volume-data-aggr' );
    for $tab_number ( 1 .. $#cloudstack_items + 1 ) {
      $legend = ( $cloudstack_items[ $tab_number - 1 ] =~ m/aggr/ ) ? 'nolegend' : 'legend';
      print_tab_contents_cloudstack( $tab_number, $host_url, $server_url, $lpar_url, $cloudstack_items[ $tab_number - 1 ], $entitle, $detail_yes, $legend );
    }
  }
  elsif ( $params{type} =~ m/^primaryStorage-aggr$/ ) {
    my @cloudstack_items = ( 'cloudstack-primaryStorage-size-free-aggr', 'cloudstack-primaryStorage-size-used-aggr', 'cloudstack-primaryStorage-size-allocated-aggr' );
    for $tab_number ( 1 .. $#cloudstack_items + 1 ) {
      $legend = ( $cloudstack_items[ $tab_number - 1 ] =~ m/aggr/ ) ? 'nolegend' : 'legend';
      print_tab_contents_cloudstack( $tab_number, $host_url, $server_url, $lpar_url, $cloudstack_items[ $tab_number - 1 ], $entitle, $detail_yes, $legend );
    }
  }
  elsif ( $params{type} =~ m/^configuration$/ ) {
    my $config_update_time = localtime( CloudstackDataWrapper::get_conf_update_time() );

    my $html_tab_header = sub {
      my @columns = @_;
      my $result  = '';
      $result .= "<center>";
      $result .= "<table class=\"tabconfig tablesorter\">";
      $result .= "<thead><tr>";
      foreach my $item (@columns) {
        $result .= "<th class=\"sortable\">" . $item . "</th>";
      }
      $result .= "</tr></thead>";
      $result .= "<tbody>";

      return $result;
    };

    my $html_table_row = sub {
      my @cells  = @_;
      my $result = '';

      $result .= "<tr>";
      foreach my $cell (@cells) { $result .= $cell; }
      $result .= "</tr>";

      return $result;
    };

    my $html_tab_footer  = "</tbody></table><p>Last update time: " . $config_update_time . "</p></center>";
    my $html_tab_footer2 = "</tbody></table></center>";

    # Host
    print "<div id=\"tabs-1\">\n";

    print "<h2>Host</h2>";

    print $html_tab_header->( 'Name', 'Cluster', 'State', 'IP', 'CPU', 'Hypervisor' );

    my $config_host = CloudstackDataWrapper::get_conf_section('spec-host');
    my @host_list   = keys %{$config_host};

    foreach my $host (@host_list) {
      my $url   = CloudstackMenu::get_url( { type => 'host', host => $host } );
      my $state = ( $config_host->{$host}{state} eq "Up" ) ? "<td class=\"hs_good\"><div>$config_host->{$host}{state}</div></td>" : "<td class=\"hs_warning\"><div>$config_host->{$host}{state}</div></td>";
      print $html_table_row->( "<td><div><a href=\"$url\">$config_host->{$host}{name}</a></div></td>", "<td><div>$config_host->{$host}{clustername}</div></td>", $state, "<td><div>$config_host->{$host}{ip}</div></td>", "<td><div>$config_host->{$host}{cpunumber}</div></td>", "<td><div>$config_host->{$host}{hypervisor}</div></td>" );
    }

    print $html_tab_footer;

    print "</div>\n";

    # Instance
    print "<div id=\"tabs-2\">\n";

    print "<h2>Instance</h2>";

    print $html_tab_header->( 'Name', 'State', 'Cpu', 'Memory', 'Template', 'Hypervisor' );

    my $config_instance = CloudstackDataWrapper::get_conf_section('spec-instance');
    my @instance_list   = keys %{$config_instance};

    foreach my $instance (@instance_list) {
      my $url   = CloudstackMenu::get_url( { type => 'instance', instance => $instance } );
      my $state = ( $config_instance->{$instance}{state} eq "Running" ) ? "<td class=\"hs_good\"><div>$config_instance->{$instance}{state}</div></td>" : "<td class=\"hs_warning\"><div>$config_instance->{$instance}{state}</div></td>";
      print $html_table_row->( "<td><div>$config_instance->{$instance}{name}</div></td>", $state, "<td><div>$config_instance->{$instance}{cpunumber}</div></td>", "<td><div>$config_instance->{$instance}{memory}</div></td>", "<td><div>$config_instance->{$instance}{templatename}</div></td>", "<td><div>$config_instance->{$instance}{hypervisor}</div></td>" );
    }

    print $html_tab_footer;

    print "</div>\n";

    # Volume
    print "<div id=\"tabs-3\">\n";

    print "<h2>Volume</h2>";

    print $html_tab_header->( 'Name', 'State', 'Size' );

    my $config_volume = CloudstackDataWrapper::get_conf_section('spec-volume');
    my @volume_list   = keys %{$config_volume};

    foreach my $volume (@volume_list) {
      my $url   = CloudstackMenu::get_url( { type => 'volume', volume => $volume } );
      my $state = ( $config_volume->{$volume}{state} eq "Ready" ) ? "<td class=\"hs_good\"><div>$config_volume->{$volume}{state}</div></td>" : "<td><div>$config_volume->{$volume}{state}</div></td>";
      my $size  = $config_volume->{$volume}{size} / 1024 / 1024 / 1024;
      print $html_table_row->( "<td><div>$config_volume->{$volume}{name}</div></td>", $state, "<td><div>" . $size . " GB</div></td>" );
    }

    print $html_tab_footer;

    print "</div>\n";

    # PrimaryStorage
    print "<div id=\"tabs-4\">\n";

    print "<h2>Primary Storage</h2>";

    print $html_tab_header->( 'Name', 'State', 'Type', 'Scope', 'Total size', 'Used' );

    my $config_primaryStorage = CloudstackDataWrapper::get_conf_section('spec-primaryStorage');
    my @primaryStorage_list   = keys %{$config_primaryStorage};

    foreach my $primaryStorage (@primaryStorage_list) {
      my $state = ( $config_primaryStorage->{$primaryStorage}{state} eq "Up" ) ? "<td class=\"hs_good\"><div>$config_primaryStorage->{$primaryStorage}{state}</div></td>" : "<td><div>$config_primaryStorage->{$primaryStorage}{state}</div></td>";
      print $html_table_row->( "<td><div>$config_primaryStorage->{$primaryStorage}{name}</div></td>", $state, "<td><div>$config_primaryStorage->{$primaryStorage}{type}</div></td>", "<td><div>$config_primaryStorage->{$primaryStorage}{scope}</div></td>", "<td><div>$config_primaryStorage->{$primaryStorage}{disksizetotalgb}</div></td>", "<td><div>$config_primaryStorage->{$primaryStorage}{disksizeusedgb}</div></td>" );
    }

    print $html_tab_footer;

    print "</div>\n";

    # SecondaryStorage
    print "<div id=\"tabs-5\">\n";

    print "<h2>Secondary Storage</h2>";

    print $html_tab_header->( 'Name', 'Protocol', 'Total size', 'Used' );

    my $config_secondaryStorage = CloudstackDataWrapper::get_conf_section('spec-secondaryStorage');
    my @secondaryStorage_list   = keys %{$config_secondaryStorage};

    foreach my $secondaryStorage (@secondaryStorage_list) {
      print $html_table_row->( "<td><div>$config_secondaryStorage->{$secondaryStorage}{name}</div></td>", "<td><div>$config_secondaryStorage->{$secondaryStorage}{protocol}</div></td>", "<td><div>" . sprintf( "%.2f", $config_secondaryStorage->{$secondaryStorage}{disksizetotal} / ( 1024 * 1024 * 1024 ) ) . " GB</div></td>", "<td><div>" . sprintf( "%.2f", $config_secondaryStorage->{$secondaryStorage}{disksizeused} / ( 1024 * 1024 * 1024 ) ) . " GB</div></td>" );
    }

    print $html_tab_footer;

    print "</div>\n";

    # SystemVMs
    print "<div id=\"tabs-6\">\n";

    print "<h2>System VMs</h2>";

    print $html_tab_header->( 'Name', 'State', 'Agent state', 'Type', 'IP' );

    my $config_systemVM = CloudstackDataWrapper::get_conf_section('spec-systemVM');
    my @systemVM_list   = keys %{$config_systemVM};

    foreach my $systemVM (@systemVM_list) {
      my $state      = ( $config_systemVM->{$systemVM}{state} eq "Running" ) ? "<td class=\"hs_good\"><div>$config_systemVM->{$systemVM}{state}</div></td>"      : "<td><div>$config_systemVM->{$systemVM}{state}</div></td>";
      my $agentState = ( $config_systemVM->{$systemVM}{agentstate} eq "Up" ) ? "<td class=\"hs_good\"><div>$config_systemVM->{$systemVM}{agentstate}</div></td>" : "<td><div>$config_systemVM->{$systemVM}{agentstate}</div></td>";
      print $html_table_row->( "<td><div>$config_systemVM->{$systemVM}{name}</div></td>", $state, $agentState, "<td><div>$config_systemVM->{$systemVM}{systemvmtype}</div></td>", "<td><div>$config_systemVM->{$systemVM}{privateip}</div></td>" );
    }

    print $html_tab_footer;

    print "</div>\n";

  }
  elsif ( $params{type} =~ m/^alert$/ ) {
    my $config_update_time = localtime( CloudstackDataWrapper::get_conf_update_time() );

    my $html_tab_header = sub {
      my @columns = @_;
      my $result  = '';
      $result .= "<center>";
      $result .= "<table class=\"tabconfig tablesorter\">";
      $result .= "<thead><tr>";
      foreach my $item (@columns) {
        $result .= "<th class=\"sortable\">" . $item . "</th>";
      }
      $result .= "</tr></thead>";
      $result .= "<tbody>";

      return $result;
    };

    my $html_table_row = sub {
      my @cells  = @_;
      my $result = '';

      $result .= "<tr>";
      foreach my $cell (@cells) { $result .= $cell; }
      $result .= "</tr>";

      return $result;
    };

    my $html_tab_footer  = "</tbody></table><p>Last update time: " . $config_update_time . "</p></center>";
    my $html_tab_footer2 = "</tbody></table></center>";

    # Alerts
    print "<div id=\"tabs-1\">\n";

    print "<h2>Alerts</h2>";

    print $html_tab_header->( 'Cloud', 'Name', 'Description', 'Time' );

    my $alerts = CloudstackDataWrapper::get_alert();

    foreach my $cloud_alert ( keys %{ $alerts->{alert} } ) {
      foreach my $alert ( keys %{ $alerts->{alert}{$cloud_alert} } ) {
        print $html_table_row->( "<td><div>$alerts->{alert}{$cloud_alert}{$alert}{cloud}</div></td>", "<td><div>$alerts->{alert}{$cloud_alert}{$alert}{name}</div></td>", "<td><div>$alerts->{alert}{$cloud_alert}{$alert}{description}</div></td>", "<td><div>$alerts->{alert}{$cloud_alert}{$alert}{sent}</div></td>" );
      }
    }

    print $html_tab_footer;

    print "</div>\n";

  }

  # closing page contents
  print "</CENTER>";
  print "</div><br>\n";

  exit(0);
}

# Proxmox
if ($proxmox) {

  # TODO temporary wrapper for compatibility with legacy subroutines interfacing mainly detail-graph-cgi.pl
  $host_url = 'Proxmox';

  #print "<script>console.log('type: $params{type}, id: $params{id}');</script>";
  if ( $params{type} =~ m/node-aggr/ || $params{type} =~ m/vm-aggr/ || $params{type} =~ m/storage-aggr/ || $params{type} =~ m/lxc-aggr/ ) {
    $server_url = $params{id};
    $lpar_url   = 'nope';
  }
  elsif ( $params{type} =~ m/node/ || $params{type} =~ m/vm/ || $params{type} =~ m/storage/ || $params{type} =~ m/lxc/ ) {
    $server_url = $params{id};
    $lpar_url   = $params{id};
  }
  elsif ( $params{type} eq 'topten_proxmox' ) {
    $lpar_url = $params{type};
  }
  else {
    $lpar_url   = 'nope';
    $server_url = 'nope';
  }

  # print page contents
  print "<CENTER>";

  # get tabs
  my @tabs = @{ ProxmoxMenu::get_tabs( $params{type} ) };

  if (@tabs) {
    print "<div id=\"tabs\">\n";
    print "<ul>\n";

    my $tab_counter = 1;
    foreach my $tab_header (@tabs) {
      while ( my ( $tab_type, $tab_label ) = each %$tab_header ) {
        print "  <li class=\"$tab_type\"><a href=\"#tabs-$tab_counter\">$tab_label</a></li>\n";
        $tab_counter++;
      }
    }
    print "</ul>\n";
  }

  # print tab contents
  sub print_tab_contents_proxmox {
    my ( $tab_number, $host_url, $server_url, $lpar_url, $item, $entitle, $detail_yes, $legend ) = @_;

    print "<div id=\"tabs-$tab_number\">\n";
    print "<table border=\"0\">\n";
    print "<tr>";

    print_item( $host_url, $server_url, $lpar_url, $item, "d", "", $entitle, $detail_yes, "norefr", "star", 1, $legend );
    print_item( $host_url, $server_url, $lpar_url, $item, "w", "", $entitle, $detail_yes, "norefr", "star", 1, $legend );
    print "</tr>\n<tr>\n";
    print_item( $host_url, $server_url, $lpar_url, $item, "m", "", $entitle, $detail_yes, "norefr", "star", 1, $legend );
    print_item( $host_url, $server_url, $lpar_url, $item, "y", "", $entitle, $detail_yes, "norefr", "star", 1, $legend );
    print "</tr></table>";
    print "</div>\n";
  }
  my $legend = ( $params{type} =~ m/aggr/ ) ? 'nolegend' : 'legend';
  if ( $params{type} =~ m/^node$/ ) {
    my @proxmox_items = ( 'proxmox-node-cpu-percent', 'proxmox-node-cpu', 'proxmox-node-memory', 'proxmox-node-swap', 'proxmox-node-io', 'proxmox-node-net', 'proxmox-node-disk' );
    for $tab_number ( 1 .. $#proxmox_items + 1 ) {
      $legend = ( $proxmox_items[ $tab_number - 1 ] =~ m/aggr/ ) ? 'nolegend' : 'legend';
      print_tab_contents_proxmox( $tab_number, $host_url, $server_url, $lpar_url, $proxmox_items[ $tab_number - 1 ], $entitle, $detail_yes, $legend );
    }
  }
  elsif ( $params{type} =~ m/^vm$/ ) {
    my @proxmox_items = ( 'proxmox-vm-cpu-percent', 'proxmox-vm-cpu', 'proxmox-vm-memory', 'proxmox-vm-data', 'proxmox-vm-net' );
    for $tab_number ( 1 .. $#proxmox_items + 1 ) {
      $legend = ( $proxmox_items[ $tab_number - 1 ] =~ m/aggr/ ) ? 'nolegend' : 'legend';
      print_tab_contents_proxmox( $tab_number, $host_url, $server_url, $lpar_url, $proxmox_items[ $tab_number - 1 ], $entitle, $detail_yes, $legend );
    }
  }
  elsif ( $params{type} =~ m/^lxc$/ ) {
    my @proxmox_items = ( 'proxmox-lxc-cpu-percent', 'proxmox-lxc-cpu', 'proxmox-lxc-memory', 'proxmox-lxc-data', 'proxmox-lxc-net' );
    for $tab_number ( 1 .. $#proxmox_items + 1 ) {
      $legend = ( $proxmox_items[ $tab_number - 1 ] =~ m/aggr/ ) ? 'nolegend' : 'legend';
      print_tab_contents_proxmox( $tab_number, $host_url, $server_url, $lpar_url, $proxmox_items[ $tab_number - 1 ], $entitle, $detail_yes, $legend );
    }
  }
  elsif ( $params{type} =~ m/^storage$/ ) {
    my @proxmox_items = ('proxmox-storage-size');
    for $tab_number ( 1 .. $#proxmox_items + 1 ) {
      $legend = ( $proxmox_items[ $tab_number - 1 ] =~ m/aggr/ ) ? 'nolegend' : 'legend';
      print_tab_contents_proxmox( $tab_number, $host_url, $server_url, $lpar_url, $proxmox_items[ $tab_number - 1 ], $entitle, $detail_yes, $legend );
    }
  }
  elsif ( $params{type} =~ m/^node-aggr/ ) {
    my @proxmox_items = ( 'proxmox-node-cpu-percent-aggr', 'proxmox-node-cpu-aggr', 'proxmox-node-memory-used-aggr', 'proxmox-node-memory-free-aggr', 'proxmox-node-swap-used-aggr', 'proxmox-node-swap-free-aggr', 'proxmox-node-io-aggr', 'proxmox-node-net-aggr', 'proxmox-node-disk-used-aggr', 'proxmox-node-disk-free-aggr' );
    for $tab_number ( 1 .. $#proxmox_items + 1 ) {
      $legend = ( $proxmox_items[ $tab_number - 1 ] =~ m/aggr/ ) ? 'nolegend' : 'legend';
      print_tab_contents_proxmox( $tab_number, $host_url, $server_url, $lpar_url, $proxmox_items[ $tab_number - 1 ], $entitle, $detail_yes, $legend );
    }
  }
  elsif ( $params{type} =~ m/^vm-aggr$/ ) {
    my @proxmox_items = ( 'proxmox-vm-cpu-percent-aggr', 'proxmox-vm-cpu-aggr', 'proxmox-vm-memory-used-aggr', 'proxmox-vm-memory-free-aggr', 'proxmox-vm-data-aggr', 'proxmox-vm-net-aggr' );
    for $tab_number ( 1 .. $#proxmox_items + 1 ) {
      $legend = ( $proxmox_items[ $tab_number - 1 ] =~ m/aggr/ ) ? 'nolegend' : 'legend';
      print_tab_contents_proxmox( $tab_number, $host_url, $server_url, $lpar_url, $proxmox_items[ $tab_number - 1 ], $entitle, $detail_yes, $legend );
    }
  }
  elsif ( $params{type} =~ m/^lxc-aggr$/ ) {
    my @proxmox_items = ( 'proxmox-lxc-cpu-percent-aggr', 'proxmox-lxc-cpu-aggr', 'proxmox-lxc-memory-used-aggr', 'proxmox-lxc-memory-free-aggr', 'proxmox-lxc-data-aggr', 'proxmox-lxc-net-aggr' );
    for $tab_number ( 1 .. $#proxmox_items + 1 ) {
      $legend = ( $proxmox_items[ $tab_number - 1 ] =~ m/aggr/ ) ? 'nolegend' : 'legend';
      print_tab_contents_proxmox( $tab_number, $host_url, $server_url, $lpar_url, $proxmox_items[ $tab_number - 1 ], $entitle, $detail_yes, $legend );
    }
  }
  elsif ( $params{type} =~ m/^storage-aggr$/ ) {
    my @proxmox_items = ( 'proxmox-storage-size-free-aggr', 'proxmox-storage-size-used-aggr' );
    for $tab_number ( 1 .. $#proxmox_items + 1 ) {
      $legend = ( $proxmox_items[ $tab_number - 1 ] =~ m/aggr/ ) ? 'nolegend' : 'legend';
      print_tab_contents_proxmox( $tab_number, $host_url, $server_url, $lpar_url, $proxmox_items[ $tab_number - 1 ], $entitle, $detail_yes, $legend );
    }
  }
  elsif ( $params{type} =~ m/^configuration$/ ) {
    my $config_update_time = localtime( ProxmoxDataWrapper::get_conf_update_time() );
    my $html_tab_header    = sub {
      my @columns = @_;
      my $result  = '';
      $result .= "<center>";
      $result .= "<table class=\"tabconfig tablesorter\">";
      $result .= "<thead><tr>";
      foreach my $item (@columns) {
        $result .= "<th class=\"sortable\">" . $item . "</th>";
      }
      $result .= "</tr></thead>";
      $result .= "<tbody>";

      return $result;
    };

    my $html_table_row = sub {
      my @cells  = @_;
      my $result = '';

      $result .= "<tr>";
      foreach my $cell (@cells) { $result .= $cell; }
      $result .= "</tr>";

      return $result;
    };

    my $html_tab_footer  = "</tbody></table><p>Last update time: " . $config_update_time . "</p></center>";
    my $html_tab_footer2 = "</tbody></table></center>";

    # Node
    print "<div id=\"tabs-1\">\n";

    print "<h2>Node</h2>";

    print $html_tab_header->( 'Name', 'Cluster', 'State', 'Uptime', 'CPU', 'Disk', 'Memory' );

    my $config_node = ProxmoxDataWrapper::get_conf_section('spec-node');
    my @node_list   = keys %{$config_node};

    foreach my $node (@node_list) {
      my $url    = ProxmoxMenu::get_url( { type => 'node', node => $node } );
      my $state  = ( $config_node->{$node}{status} eq "online" ) ? "<td class=\"hs_good\"><div>$config_node->{$node}{status}</div></td>" : "<td class=\"hs_warning\"><div>$config_node->{$node}{status}</div></td>";
      my $disk   = sprintf( "%.1f", $config_node->{$node}{maxdisk} / 1024 / 1024 / 1024 );
      my $mem    = sprintf( "%.1f", $config_node->{$node}{maxmem} / 1024 / 1024 / 1024 );
      my $uptime = sprintf( "%.0f", $config_node->{$node}{uptime} / 60 / 60 / 24 );
      print $html_table_row->( "<td><div><a href=\"$url\">$config_node->{$node}{name}</a></div></td>", "<td><div>$config_node->{$node}{cluster}</div></td>", $state, "<td><div>$uptime days</div></td>", "<td><div>$config_node->{$node}{maxcpu}</div></td>", "<td><div>$disk GB</div></td>", "<td><div>$mem GB</div></td>" );
    }

    print $html_tab_footer;

    print "</div>\n";

    # VM
    print "<div id=\"tabs-2\">\n";

    print "<h2>VM</h2>";
    print $html_tab_header->( 'Name', 'Cluster', 'Node', 'State', 'Uptime', 'CPU', 'Disk', 'Memory' );

    my $config_vm = ProxmoxDataWrapper::get_conf_section('spec-vm');
    my @vm_list   = keys %{$config_vm};

    foreach my $vm (@vm_list) {
      my $url    = ProxmoxMenu::get_url( { type => 'vm', vm => $vm } );
      my $state  = ( $config_vm->{$vm}{status} eq "running" ) ? "<td class=\"hs_good\"><div>$config_vm->{$vm}{status}</div></td>" : "<td class=\"hs_warning\"><div>$config_vm->{$vm}{status}</div></td>";
      my $uptime = sprintf( "%.0f", $config_vm->{$vm}{uptime} / 60 / 60 / 24 );
      my $disk   = sprintf( "%.1f", $config_vm->{$vm}{maxdisk} / 1024 / 1024 / 1024 );
      my $mem    = sprintf( "%.1f", $config_vm->{$vm}{maxmem} / 1024 / 1024 / 1024 );
      print $html_table_row->( "<td><div><a href=\"$url\">$config_vm->{$vm}{name}</a></div></td>", "<td><div>$config_vm->{$vm}{cluster}</div></td>", "<td><div>$config_vm->{$vm}{node}</div></td>", $state, "<td><div>$uptime days</div></td>", "<td><div>$config_vm->{$vm}{cpus}</div></td>", "<td><div>$disk GB</div></td>", "<td><div>$mem GB</div></td>" );
    }

    print $html_tab_footer;

    print "</div>\n";

    # LXC
    print "<div id=\"tabs-3\">\n";

    print "<h2>LXC</h2>";
    print $html_tab_header->( 'Name', 'Cluster', 'Node', 'State', 'Uptime', 'CPU', 'Disk', 'Memory' );

    my $config_lxc = ProxmoxDataWrapper::get_conf_section('spec-lxc');
    my @lxc_list   = keys %{$config_lxc};

    foreach my $lxc (@lxc_list) {
      my $url    = ProxmoxMenu::get_url( { type => 'lxc', lxc => $lxc } );
      my $state  = ( $config_lxc->{$lxc}{status} eq "running" ) ? "<td class=\"hs_good\"><div>$config_lxc->{$lxc}{status}</div></td>" : "<td class=\"hs_warning\"><div>$config_lxc->{$lxc}{status}</div></td>";
      my $uptime = sprintf( "%.0f", $config_lxc->{$lxc}{uptime} / 60 / 60 / 24 );
      my $disk   = sprintf( "%.1f", $config_lxc->{$lxc}{maxdisk} / 1024 / 1024 / 1024 );
      my $mem    = sprintf( "%.1f", $config_lxc->{$lxc}{maxmem} / 1024 / 1024 / 1024 );
      print $html_table_row->( "<td><div><a href=\"$url\">$config_lxc->{$lxc}{name}</a></div></td>", "<td><div>$config_lxc->{$lxc}{cluster}</div></td>", "<td><div>$config_lxc->{$lxc}{node}</div></td>", $state, "<td><div>$uptime days</div></td>", "<td><div>$config_lxc->{$lxc}{cpus}</div></td>", "<td><div>$disk GB</div></td>", "<td><div>$mem GB</div></td>" );
    }

    print $html_tab_footer;

    print "</div>\n";

    # Storage
    print "<div id=\"tabs-4\">\n";

    print "<h2>Storage</h2>";

    print $html_tab_header->( 'Name', 'Cluster', 'Node', 'Active', 'Enabled', 'Shared', 'Type', 'Size', 'Used', 'Content' );

    my $config_storage = ProxmoxDataWrapper::get_conf_section('spec-storage');
    my @storage_list   = keys %{$config_storage};

    foreach my $storage (@storage_list) {
      my $url     = ProxmoxMenu::get_url( { type => 'storage', storage => $storage } );
      my $active  = ( $config_storage->{$storage}{active} eq "1" )  ? "<td class=\"hs_good\"><div>$config_storage->{$storage}{active}</div></td>"  : "<td><div>$config_storage->{$storage}{active}</div></td>";
      my $enabled = ( $config_storage->{$storage}{enabled} eq "1" ) ? "<td class=\"hs_good\"><div>$config_storage->{$storage}{enabled}</div></td>" : "<td><div>$config_storage->{$storage}{enabled}</div></td>";
      my $size    = sprintf( "%.1f", $config_storage->{$storage}{total} / 1024 / 1024 / 1024 );
      my $used    = ( $config_storage->{$storage}{total} ne "0" ) ? sprintf( "%.0f", ( $config_storage->{$storage}{used} / ( $config_storage->{$storage}{total} / 100 ) ) ) : 0;
      print $html_table_row->( "<td><div>$config_storage->{$storage}{name}</div></td>", "<td><div>$config_storage->{$storage}{cluster}</div></td>", "<td><div>$config_storage->{$storage}{node}</div></td>", $active, $enabled, "<td><div>$config_storage->{$storage}{shared}</div></td>", "<td><div>$config_storage->{$storage}{type}</div></td>", "<td><div>" . $size . " GB</div></td>", "<td><div>" . $used . " %</div></td>", "<td><div>$config_storage->{$storage}{content}</div></td>" );
    }

    print $html_tab_footer;

    print "</div>\n";

  }
  elsif ( $params{type} =~ m/^topten_proxmox$/ ) {
    ############## LOAD TOPTEN FILE #####################
    my $topten_file_proxmox = "$tmpdir/topten_proxmox.tmp";
    my $last_update         = localtime( ( stat($topten_file_proxmox) )[9] );
    #####################################################
    my $server_pool = "";

    # last day
    print "<div id=\"tabs-1\">\n";
    print "<table align=\"center\" summary=\"Graphs\">\n";
    print "<tr><th align=center>CPU in cores<a class=\"csvfloat\" href=\"/lpar2rrd-cgi/top10_csv.sh?LPAR=$server_pool&host=CSV&type=PROXMOX&table=topten&item=load_cpu&period=1\" title=\"LOAD CPU CSV\"><img src=\"css/images/csv.gif\"></a></th><th align=center>CPU %<a class=\"csvfloat\" href=\"/lpar2rrd-cgi/top10_csv.sh?LPAR=$server_pool&host=CSV&type=PROXMOX&table=topten&item=cpu_perc&period=1\" title=\"CPU % CSV\"><img src=\"css/images/csv.gif\"></a></th><th align=center>NET in MB/sec<a class=\"csvfloat\" href=\"/lpar2rrd-cgi/top10_csv.sh?LPAR=$server_pool&host=CSV&type=PROXMOX&table=topten&item=net&period=1\" title=\"NET CSV\"><img src=\"css/images/csv.gif\"></a></th><th align=center>DISK in MB/sec<a class=\"csvfloat\" href=\"/lpar2rrd-cgi/top10_csv.sh?LPAR=$server_pool&host=CSV&type=PROXMOX&table=topten&item=disk&period=1\" title=\"DISK CSV\"><img src=\"css/images/csv.gif\"></a></th></tr>";
    print "<tr style=\"vertical-align:top\">";
    print_top10_to_table_proxmox( "1", "$server_pool", "load_cpu" );
    print_top10_to_table_proxmox( "1", "$server_pool", "cpu_perc" );
    print_top10_to_table_proxmox( "1", "$server_pool", "net" );
    print_top10_to_table_proxmox( "1", "$server_pool", "disk" );
    print "</tr>";
    print "</table>";
    print "<tfoot><tr><td colspan=\"6\">Last update time: $last_update</td></tr></tfoot>";
    print "</div>\n";

    # last week
    print "<div id=\"tabs-2\">\n";
    print "<table align=\"center\" summary=\"Graphs\">\n";
    print "<tr><th align=center>CPU in cores<a class=\"csvfloat\" href=\"/lpar2rrd-cgi/top10_csv.sh?LPAR=$server_pool&host=CSV&type=PROMOX&table=topten&item=load_cpu&period=2\" title=\"LOAD CPU CSV\"><img src=\"css/images/csv.gif\"></a></th><th align=center>CPU %<a class=\"csvfloat\" href=\"/lpar2rrd-cgi/top10_csv.sh?LPAR=$server_pool&host=CSV&type=PROXMOX&table=topten&item=cpu_perc&period=2\" title=\"CPU % CSV\"><img src=\"css/images/csv.gif\"></a></th><th align=center>NET in MB/sec<a class=\"csvfloat\" href=\"/lpar2rrd-cgi/top10_csv.sh?LPAR=$server_pool&host=CSV&type=PROXMOX&table=topten&item=net&period=2\" title=\"NET CSV\"><img src=\"css/images/csv.gif\"></a></th><th align=center>DISK in MB/sec<a class=\"csvfloat\" href=\"/lpar2rrd-cgi/top10_csv.sh?LPAR=$server_pool&host=CSV&type=PROXMOX&table=topten&item=disk&period=2\" title=\"DISK CSV\"><img src=\"css/images/csv.gif\"></a></th></tr>";
    print "<tr style=\"vertical-align:top\">";
    print_top10_to_table_proxmox( "2", "$server_pool", "load_cpu" );
    print_top10_to_table_proxmox( "2", "$server_pool", "cpu_perc" );
    print_top10_to_table_proxmox( "2", "$server_pool", "net" );
    print_top10_to_table_proxmox( "2", "$server_pool", "disk" );
    print "</tr>";
    print "</table>";
    print "<tfoot><tr><td colspan=\"6\">Last update time: $last_update</td></tr></tfoot>";
    print "</div>\n";

    # last month
    print "<div id=\"tabs-3\">\n";
    print "<table align=\"center\" summary=\"Graphs\">\n";
    print "<tr><th align=center>CPU in cores<a class=\"csvfloat\" href=\"/lpar2rrd-cgi/top10_csv.sh?LPAR=$server_pool&host=CSV&type=PROXMOX&table=topten&item=load_cpu&period=3\" title=\"LOAD CPU CSV\"><img src=\"css/images/csv.gif\"></a></th><th align=center>CPU %<a class=\"csvfloat\" href=\"/lpar2rrd-cgi/top10_csv.sh?LPAR=$server_pool&host=CSV&type=PROXMOX&table=topten&item=cpu_perc&period=3\" title=\"CPU % CSV\"><img src=\"css/images/csv.gif\"></a></th><th align=center>NET in MB/sec<a class=\"csvfloat\" href=\"/lpar2rrd-cgi/top10_csv.sh?LPAR=$server_pool&host=CSV&type=PROXMOX&table=topten&item=net&period=3\" title=\"NET CSV\"><img src=\"css/images/csv.gif\"></a></th><th align=center>DISK in MB/sec<a class=\"csvfloat\" href=\"/lpar2rrd-cgi/top10_csv.sh?LPAR=$server_pool&host=CSV&type=PROXMOX&table=topten&item=disk&period=3\" title=\"DISK CSV\"><img src=\"css/images/csv.gif\"></a></th></tr>";
    print "<tr style=\"vertical-align:top\">";
    print_top10_to_table_proxmox( "3", "$server_pool", "load_cpu" );
    print_top10_to_table_proxmox( "3", "$server_pool", "cpu_perc" );
    print_top10_to_table_proxmox( "3", "$server_pool", "net" );
    print_top10_to_table_proxmox( "3", "$server_pool", "disk" );
    print "</tr>";
    print "</table>";
    print "<tfoot><tr><td colspan=\"6\">Last update time: $last_update</td></tr></tfoot>";
    print "</div>\n";

    # last year
    print "<div id=\"tabs-4\">\n";
    print "<table align=\"center\" summary=\"Graphs\">\n";
    print "<tr><th align=center>CPU in cores<a class=\"csvfloat\" href=\"/lpar2rrd-cgi/top10_csv.sh?LPAR=$server_pool&host=CSV&type=PROXMOX&table=topten&item=load_cpu&period=4\" title=\"LOAD CPU CSV\"><img src=\"css/images/csv.gif\"></a></th><th align=center>CPU %<a class=\"csvfloat\" href=\"/lpar2rrd-cgi/top10_csv.sh?LPAR=$server_pool&host=CSV&type=PROXMOX&table=topten&item=cpu_perc&period=4\" title=\"CPU % CSV\"><img src=\"css/images/csv.gif\"></a></th><th align=center>NET in MB/sec<a class=\"csvfloat\" href=\"/lpar2rrd-cgi/top10_csv.sh?LPAR=$server_pool&host=CSV&type=PROXMOX&table=topten&item=net&period=4\" title=\"NET CSV\"><img src=\"css/images/csv.gif\"></a></th><th align=center>DISK in MB/sec<a class=\"csvfloat\" href=\"/lpar2rrd-cgi/top10_csv.sh?LPAR=$server_pool&host=CSV&type=PROXMOX&table=topten&item=disk&period=4\" title=\"DISK CSV\"><img src=\"css/images/csv.gif\"></a></th></tr>";
    print "<tr style=\"vertical-align:top\">";
    print_top10_to_table_proxmox( "4", "$server_pool", "load_cpu" );
    print_top10_to_table_proxmox( "4", "$server_pool", "cpu_perc" );
    print_top10_to_table_proxmox( "4", "$server_pool", "net" );
    print_top10_to_table_proxmox( "4", "$server_pool", "disk" );
    print "</tr>";
    print "</table>";
    print "<tfoot><tr><td colspan=\"6\">Last update time: $last_update</td></tr></tfoot>";
    print "</div>\n";
  }

  sub print_top10_to_table_proxmox {
    my ( $period, $server_pool, $item_name ) = @_;
    my $topten_file_proxmox = "$tmpdir/topten_proxmox.tmp";
    my $html_tab_header     = sub {
      my @columns = @_;
      my $result  = '';
      $result .= "<center>";
      $result .= "<table style=\"white-space: nowrap;\" class=\"tabconfig tablesorter \" data-sortby='1'>";
      $result .= "<thead><tr>";
      foreach my $item (@columns) {
        $result .= "<th class=\"sortable\">" . $item . "</th>";
      }
      $result .= "</tr></thead>";
      $result .= "<tbody>";
      return $result;
    };
    my $html_table_row = sub {
      my @cells  = @_;
      my $result = '';

      $result .= "<tr>";
      foreach my $cell (@cells) { $result .= "<td>" . $cell . "</td>"; }
      $result .= "</tr>";

      return $result;
    };

    # Table or create CSV file
    my $csv_file;
    if ( $item_name eq "load_cpu" ) {
      $csv_file = "proxmox-load-cpu.csv";
    }
    elsif ( $item_name eq "cpu_perc" ) {
      $csv_file = "proxmox-cpu-perc.csv";
    }
    elsif ( $item_name eq "net" ) {
      $csv_file = "proxmox-net.csv";
    }
    elsif ( $item_name eq "disk" ) {
      $csv_file = "proxmox-disk.csv";
    }
    if ( !$csv ) {
      if ( $item_name eq "load_cpu" or $item_name eq "cpu_perc" ) {
        print "<TD><TABLE class=\"tabconfig tablesorter\" data-sortby=\"1\">";
        if ( $period == 4 ) {    # last year
          print $html_tab_header->( 'Avrg', "VM", 'Cluster' );
        }
        else {
          print $html_tab_header->( 'Avrg', 'Max', "VM", 'Cluster' );
        }
      }
      elsif ( $item_name eq "net" ) {
        print "<TD><TABLE class=\"tabconfig tablesorter\" data-sortby=\"1\">";
        if ( $period == 4 ) {    # last year
          print $html_tab_header->( 'Avrg', "VM", 'Cluster' );
        }
        else {
          print $html_tab_header->( 'Avrg', 'Max', "VM", 'Cluster' );
        }
      }
      elsif ( $item_name eq "disk" ) {
        print "<TD><TABLE class=\"tabconfig tablesorter\" data-sortby=\"1\">";
        if ( $period == 4 ) {    # last year
          print $html_tab_header->( 'Avrg', "VM", 'Cluster' );
        }
        else {
          print $html_tab_header->( 'Avrg', 'Max', "VM", 'Cluster' );
        }
      }
    }
    else {
      print "Content-Disposition: attachment;filename=\"$csv_file\"\n\n";
      my $csv_header = "";
      if ( $period == 4 ) {    # last year
        $csv_header = "Avrg" . "$sep" . "VM" . "$sep" . "Cluster\n";
      }
      else {
        $csv_header = "Avrg" . "$sep" . "Max" . "$sep" . "VM" . "$sep" . "Cluster\n";
      }
      print "$csv_header";
    }
    my @topten;
    my @topten_not_sorted;
    my @topten_sorted;
    my $topten_limit = 0;
    my @top_values_avrg;
    my @top_values_max;
    if ( -f $topten_file_proxmox ) {
      open( FH, " < $topten_file_proxmox" ) || error( "Cannot open $topten_file_proxmox: $!" . __FILE__ . ":" . __LINE__ );
      @topten = <FH>;
      close FH;
      if ( defined $ENV{TOPTEN} ) {
        $topten_limit = $ENV{TOPTEN};
      }
      $topten_limit = 50 if $topten_limit < 1;
      my @topten_server;
      if ( $item_name eq "load_cpu" ) {
        @topten_server = grep {/cpu_util,/} @topten;
      }
      elsif ( $item_name eq "cpu_perc" ) {
        @topten_server = grep {/cpu_perc,/} @topten;
      }
      elsif ( $item_name eq "net" ) {
        @topten_server = grep {/net,/} @topten;
      }
      elsif ( $item_name eq "disk" ) {
        @topten_server = grep {/disk,/} @topten;
      }
      @topten = @topten_server;
      foreach my $line (@topten) {
        chomp $line;
        my ( $item, $vm_name, $cluster_name );
        ( $item, $vm_name, $cluster_name, $top_values_avrg[1], $top_values_max[1], $top_values_avrg[2], $top_values_max[2], $top_values_avrg[3], $top_values_max[3], $top_values_avrg[4], $top_values_max[4] ) = split( ",", $line );
        $top_values_avrg[4] = 0 if !defined $top_values_avrg[4] or $top_values_avrg[4] eq "";    # no year value yet, new file
        $top_values_max[4]  = 0 if !defined $top_values_max[4]  or $top_values_max[4] eq "";     # no year value yet, new file
        if ( $top_values_avrg[1] == 0 && $top_values_max[1] == 0 && $top_values_avrg[2] == 0 && $top_values_max[2] == 0 && $top_values_avrg[3] == 0 && $top_values_max[3] == 0 && $top_values_avrg[4] == 0 && $top_values_max[4] == 0 ) { next; }
        push @topten_not_sorted, "$item,$top_values_avrg[$period],$top_values_max[$period],$vm_name,$cluster_name\n";
      }
      {
        no warnings;
        @topten_sorted = sort { $b <=> $a } @topten_not_sorted;
      }
    }
    my @topten_sorted_load_cpu;
    {
      no warnings;
      @topten_sorted_load_cpu = sort {
        my @b = split( /,/, $b );
        my @a = split( /,/, $a );

        #print "$b[4] --- $a[4]\n";
        $b[1] <=> $a[1]
      } @topten_sorted;
    }
    foreach my $line1 (@topten_sorted_load_cpu) {
      my ( $item_a, $load_cpu, $load_peak, $vm_name, $cluster_name );
      ( $item_a, $load_cpu, $load_peak, $vm_name, $cluster_name ) = split( ",", $line1 );
      if ( !$csv ) {
        if ( $period == 4 ) {    # last year
          print $html_table_row->( $load_cpu, $vm_name, $cluster_name );
        }
        else {
          print $html_table_row->( $load_cpu, $load_peak, $vm_name, $cluster_name );
        }
      }
      else {
        if ( $period == 4 ) {    # last year
          print "$load_cpu" . "$sep" . "$vm_name" . "$sep" . "$cluster_name";
        }
        else {
          print "$load_cpu" . "$sep" . "$load_peak" . "$sep" . "$vm_name" . "$sep" . "$cluster_name";
        }
      }
    }
    if ( !$csv ) {
      print "</TABLE></TD>";
    }
    return 1;
  }

  # closing page contents
  print "</CENTER>";
  print "</div><br>\n";

  exit(0);
}

# Docker
if ($docker) {

  # TODO temporary wrapper for compatibility with legacy subroutines interfacing mainly detail-graph-cgi.pl
  $host_url = 'Docker';
  if ( $params{type} =~ m/container-aggr/ || $params{type} =~ m/volume-aggr/ || $params{type} =~ m/host-aggr/ ) {
    $server_url = $params{id};
    $lpar_url   = 'nope';
  }
  elsif ( $params{type} =~ m/container/ || $params{type} =~ m/volume/ ) {
    $server_url = $params{id};
    $lpar_url   = $params{id};
  }
  else {
    $lpar_url   = 'nope';
    $server_url = 'nope';
  }

  # print page contents
  print "<CENTER>";

  # get tabs
  my @tabs = @{ DockerMenu::get_tabs( $params{type} ) };

  if (@tabs) {
    print "<div id=\"tabs\">\n";
    print "<ul>\n";

    my $tab_counter = 1;
    foreach my $tab_header (@tabs) {
      while ( my ( $tab_type, $tab_label ) = each %$tab_header ) {
        print "  <li class=\"$tab_type\"><a href=\"#tabs-$tab_counter\">$tab_label</a></li>\n";
        $tab_counter++;
      }
    }
    print "</ul>\n";
  }

  # print tab contents
  sub print_tab_contents_docker {
    my ( $tab_number, $host_url, $server_url, $lpar_url, $item, $entitle, $detail_yes, $legend ) = @_;

    print "<div id=\"tabs-$tab_number\">\n";
    print "<table border=\"0\">\n";
    print "<tr>";

    if ( $item =~ m/cpu/ ) {
      print '<div id="hiw"><a href="https://lpar2rrd.com/Docker_CPU.php" target="_blank" class="nowrap"><img src="css/images/help-browser.gif" alt="View metric information" title="View metric information"></img></a></div>';
    }

    print_item( $host_url, $server_url, $lpar_url, $item, "d", "", $entitle, $detail_yes, "norefr", "star", 1, $legend );
    print_item( $host_url, $server_url, $lpar_url, $item, "w", "", $entitle, $detail_yes, "norefr", "star", 1, $legend );
    print "</tr>\n<tr>\n";
    print_item( $host_url, $server_url, $lpar_url, $item, "m", "", $entitle, $detail_yes, "norefr", "star", 1, $legend );
    print_item( $host_url, $server_url, $lpar_url, $item, "y", "", $entitle, $detail_yes, "norefr", "star", 1, $legend );
    print "</tr></table>";
    if ( $item =~ m/docker-container-size-rw/ ) {
      print "<div id='hiw'><a href='https://www.lpar2rrd.com/docker_metrics.php' target='_blank'><img src='css/images/help-browser.gif' alt='What is Size RW metric?' title='What is Size RW metric?'></a></div>";
    }
    print "</div>\n";
  }

  my $legend = ( $params{type} =~ m/aggr/ ) ? 'nolegend' : 'legend';
  if ( $params{type} =~ m/^container$/ ) {
    my @docker_items = ( 'docker-container-cpu-cores', 'docker-container-cpu-real', 'docker-container-cpu', 'docker-container-memory', 'docker-container-data', 'docker-container-io', 'docker-container-net', 'docker-container-size', 'docker-container-size-rw' );
    for $tab_number ( 1 .. $#docker_items + 1 ) {
      $legend = ( $docker_items[ $tab_number - 1 ] =~ m/aggr/ ) ? 'nolegend' : 'legend';
      print_tab_contents_docker( $tab_number, $host_url, $server_url, $lpar_url, $docker_items[ $tab_number - 1 ], $entitle, $detail_yes, $legend );
    }
  }
  elsif ( $params{type} =~ m/^volume$/ ) {
    my @docker_items = ('docker-volume-size');
    for $tab_number ( 1 .. $#docker_items + 1 ) {
      $legend = ( $docker_items[ $tab_number - 1 ] =~ m/aggr/ ) ? 'nolegend' : 'legend';
      print_tab_contents_docker( $tab_number, $host_url, $server_url, $lpar_url, $docker_items[ $tab_number - 1 ], $entitle, $detail_yes, $legend );
    }
  }
  elsif ( $params{type} =~ m/^host-aggr$/ ) {
    my @docker_items = ( 'docker-container-cpu-aggr', 'docker-container-memory-aggr', 'docker-container-data-aggr', 'docker-container-io-aggr', 'docker-container-net-aggr', 'docker-container-size-aggr', 'docker-container-size-rw-aggr', 'docker-volume-size-aggr' );
    for $tab_number ( 1 .. $#docker_items + 1 ) {
      $legend = ( $docker_items[ $tab_number - 1 ] =~ m/aggr/ ) ? 'nolegend' : 'legend';
      print_tab_contents_docker( $tab_number, $host_url, $server_url, $lpar_url, $docker_items[ $tab_number - 1 ], $entitle, $detail_yes, $legend );
    }
  }
  elsif ( $params{type} =~ m/^hosts-aggr$/ ) {
    my @docker_items = ( 'docker-total-container-cpu-aggr', 'docker-total-container-memory-aggr', 'docker-total-container-data-aggr', 'docker-total-container-io-aggr', 'docker-total-container-net-aggr', 'docker-total-container-size-aggr', 'docker-total-container-size-rw-aggr', 'docker-total-volume-size-aggr' );
    for $tab_number ( 1 .. $#docker_items + 1 ) {
      $legend = ( $docker_items[ $tab_number - 1 ] =~ m/aggr/ ) ? 'nolegend' : 'legend';
      print_tab_contents_docker( $tab_number, $host_url, $server_url, $lpar_url, $docker_items[ $tab_number - 1 ], $entitle, $detail_yes, $legend );
    }
  }
  elsif ( $params{type} =~ m/^volume-aggr$/ ) {
    my @docker_items = ('docker-volume-size-aggr');
    for $tab_number ( 1 .. $#docker_items + 1 ) {
      $legend = ( $docker_items[ $tab_number - 1 ] =~ m/aggr/ ) ? 'nolegend' : 'legend';
      print_tab_contents_docker( $tab_number, $host_url, $server_url, $lpar_url, $docker_items[ $tab_number - 1 ], $entitle, $detail_yes, $legend );
    }
  }

  # closing page contents
  print "</CENTER>";
  print "</div><br>\n";

  exit(0);
}

# FusionCompute
if ($fusioncompute) {

  # TODO temporary wrapper for compatibility with legacy subroutines interfacing mainly detail-graph-cgi.pl
  $host_url = 'FusionCompute';

  #print "<script>console.log('type: $params{type}, id: $params{id}');</script>";
  if ( $params{type} =~ m/host-aggr/ || $params{type} =~ m/vm-aggr/ || $params{type} =~ m/cluster-aggr/ || $params{type} =~ m/site-aggr/ || $params{type} =~ m/datastore-aggr/ ) {
    $server_url = $params{id};
    $lpar_url   = 'nope';
  }
  elsif ( $params{type} =~ m/host/ || $params{type} =~ m/vm/ || $params{type} =~ m/cluster/ || $params{type} =~ m/site/ || $params{type} =~ m/datastore/ ) {
    $server_url = $params{id};
    $lpar_url   = $params{id};
  }
  else {
    $lpar_url   = 'nope';
    $server_url = 'nope';
  }

  my $mapping;
  if ( $params{type} eq 'vm' ) {
    $mapping = FusionComputeDataWrapper::get_mapping( $params{id} );
  }

  # print page contents
  print "<CENTER>";

  # get tabs
  my @tabs = @{ FusionComputeMenu::get_tabs( $params{type} ) };

  $tab_number = 1;
  if (@tabs) {
    print "<div id=\"tabs\">\n";
    print "<ul>\n";

    my $tab_counter = 1;
    foreach my $tab_header (@tabs) {
      while ( my ( $tab_type, $tab_label ) = each %$tab_header ) {
        print "  <li class=\"$tab_type\"><a href=\"#tabs-$tab_number\">$tab_label</a></li>\n";
        $tab_counter++;
        $tab_number++;
      }
    }

    if ($mapping) {
      @item_agent      = ();
      @item_agent_tab  = ();
      $item_agent_indx = $tab_number;
      $os_agent        = 0;
      $nmon_agent      = 0;
      $iops            = "IOPS";

      build_agents_tabs( "Linux", "no_hmc", $mapping );
    }

    print "</ul>\n";
  }

  # print tab contents
  sub print_tab_contents_fusioncompute {
    my ( $tab_number, $host_url, $server_url, $lpar_url, $item, $entitle, $detail_yes, $legend ) = @_;

    print "<div id=\"tabs-$tab_number\">\n";
    print "<table border=\"0\">\n";
    print "<tr>";

    print_item( $host_url, $server_url, $lpar_url, $item, "d", "", $entitle, $detail_yes, "norefr", "star", 1, $legend );
    print_item( $host_url, $server_url, $lpar_url, $item, "w", "", $entitle, $detail_yes, "norefr", "star", 1, $legend );
    print "</tr>\n<tr>\n";
    print_item( $host_url, $server_url, $lpar_url, $item, "m", "", $entitle, $detail_yes, "norefr", "star", 1, $legend );
    print_item( $host_url, $server_url, $lpar_url, $item, "y", "", $entitle, $detail_yes, "norefr", "star", 1, $legend );
    print "</tr></table>";
    print "</div>\n";
  }
  my $legend = ( $params{type} =~ m/aggr/ ) ? 'nolegend' : 'legend';
  if ( $params{type} =~ m/^vm$/ ) {
    my @fusioncompute_items = ( 'fusioncompute-vm-cpu-percent', 'fusioncompute-vm-cpu', 'fusioncompute-vm-mem-percent', 'fusioncompute-vm-mem', 'fusioncompute-vm-data', 'fusioncompute-vm-disk-req', 'fusioncompute-vm-disk-ios', 'fusioncompute-vm-disk-ticks', 'fusioncompute-vm-disk-sectors', 'fusioncompute-vm-disk-usage', 'fusioncompute-vm-net', 'fusioncompute-vm-net-packet-drop' );
    for $tab_number ( 1 .. $#fusioncompute_items + 1 ) {
      $legend = ( $fusioncompute_items[ $tab_number - 1 ] =~ m/aggr/ ) ? 'nolegend' : 'legend';
      print_tab_contents_fusioncompute( $tab_number, $host_url, $server_url, $lpar_url, $fusioncompute_items[ $tab_number - 1 ], $entitle, $detail_yes, $legend );
    }
    if ($mapping) {
      my $start = $#fusioncompute_items + 2;
      my $break;

      $server = 'Linux';
      $host   = 'no_hmc';
      $lpar   = $mapping;
      build_agents_html( "Linux", "no_hmc", $mapping, $start );

    }
  }
  elsif ( $params{type} =~ m/^vm-aggr$/ ) {
    my @fusioncompute_items = ( 'fusioncompute-vm-cpu-percent-aggr', 'fusioncompute-vm-cpu-aggr', 'fusioncompute-vm-mem-percent-aggr', 'fusioncompute-vm-mem-used-aggr', 'fusioncompute-vm-mem-free-aggr', 'fusioncompute-vm-data-aggr', 'fusioncompute-vm-disk-req-aggr', 'fusioncompute-vm-disk-ios-aggr', 'fusioncompute-vm-disk-ticks-aggr', 'fusioncompute-vm-disk-sectors-aggr', 'fusioncompute-vm-disk-usage-aggr', 'fusioncompute-vm-net-aggr', 'fusioncompute-vm-net-packet-drop-aggr' );
    for $tab_number ( 1 .. $#fusioncompute_items + 1 ) {
      $legend = ( $fusioncompute_items[ $tab_number - 1 ] =~ m/aggr/ ) ? 'nolegend' : 'legend';
      print_tab_contents_fusioncompute( $tab_number, $host_url, $server_url, $lpar_url, $fusioncompute_items[ $tab_number - 1 ], $entitle, $detail_yes, $legend );
    }
  }
  elsif ( $params{type} =~ m/^host$/ ) {
    my @fusioncompute_items = ( 'fusioncompute-host-cpu-percent', 'fusioncompute-host-vm-cpu-percent-aggr', 'fusioncompute-host-cpu', 'fusioncompute-host-vm-cpu-aggr', 'fusioncompute-host-mem-percent', 'fusioncompute-host-vm-mem-percent-aggr', 'fusioncompute-host-mem', 'fusioncompute-host-vm-mem-used-aggr', 'fusioncompute-host-vm-mem-free-aggr', 'fusioncompute-host-data', 'fusioncompute-host-iops', 'fusioncompute-host-net', 'fusioncompute-host-net-usage', 'fusioncompute-host-packets', 'fusioncompute-host-packets-drop', 'fusioncompute-host-disk-usage' );
    for $tab_number ( 1 .. $#fusioncompute_items + 1 ) {
      $legend = ( $fusioncompute_items[ $tab_number - 1 ] =~ m/aggr/ ) ? 'nolegend' : 'legend';
      print_tab_contents_fusioncompute( $tab_number, $host_url, $server_url, $lpar_url, $fusioncompute_items[ $tab_number - 1 ], $entitle, $detail_yes, $legend );
    }
  }
  elsif ( $params{type} =~ m/^host-aggr$/ ) {
    my @fusioncompute_items = ( 'fusioncompute-host-cpu-percent-aggr', 'fusioncompute-host-cpu-aggr', 'fusioncompute-host-mem-percent-aggr', 'fusioncompute-host-mem-used-aggr', 'fusioncompute-host-mem-free-aggr', 'fusioncompute-host-data-aggr', 'fusioncompute-host-iops-aggr', 'fusioncompute-host-net-aggr', 'fusioncompute-host-net-usage-aggr', 'fusioncompute-host-packets-aggr', 'fusioncompute-host-packets-drop-aggr', 'fusioncompute-host-disk-usage-aggr' );
    for $tab_number ( 1 .. $#fusioncompute_items + 1 ) {
      $legend = ( $fusioncompute_items[ $tab_number - 1 ] =~ m/aggr/ ) ? 'nolegend' : 'legend';
      print_tab_contents_fusioncompute( $tab_number, $host_url, $server_url, $lpar_url, $fusioncompute_items[ $tab_number - 1 ], $entitle, $detail_yes, $legend );
    }
  }
  elsif ( $params{type} =~ m/^cluster$/ ) {
    my @fusioncompute_items = ( 'fusioncompute-cluster-cpu-percent', 'fusioncompute-cluster-mem-percent', 'fusioncompute-cluster-data', 'fusioncompute-cluster-disk-usage', 'fusioncompute-cluster-net', 'fusioncompute-cluster-net-usage' );
    for $tab_number ( 1 .. $#fusioncompute_items + 1 ) {
      $legend = ( $fusioncompute_items[ $tab_number - 1 ] =~ m/aggr/ ) ? 'nolegend' : 'legend';
      print_tab_contents_fusioncompute( $tab_number, $host_url, $server_url, $lpar_url, $fusioncompute_items[ $tab_number - 1 ], $entitle, $detail_yes, $legend );
    }
  }
  elsif ( $params{type} =~ m/^cluster-aggr$/ ) {
    my @fusioncompute_items = ( 'fusioncompute-cluster-cpu-percent-aggr', 'fusioncompute-cluster-mem-percent-aggr', 'fusioncompute-cluster-data-aggr', 'fusioncompute-cluster-disk-usage-aggr', 'fusioncompute-cluster-net-aggr', 'fusioncompute-cluster-net-usage-aggr' );
    for $tab_number ( 1 .. $#fusioncompute_items + 1 ) {
      $legend = ( $fusioncompute_items[ $tab_number - 1 ] =~ m/aggr/ ) ? 'nolegend' : 'legend';
      print_tab_contents_fusioncompute( $tab_number, $host_url, $server_url, $lpar_url, $fusioncompute_items[ $tab_number - 1 ], $entitle, $detail_yes, $legend );
    }
  }
  elsif ( $params{type} =~ m/^datastore$/ ) {
    my @fusioncompute_items = ('fusioncompute-datastore-capacity');
    for $tab_number ( 1 .. $#fusioncompute_items + 1 ) {
      $legend = ( $fusioncompute_items[ $tab_number - 1 ] =~ m/aggr/ ) ? 'nolegend' : 'legend';
      print_tab_contents_fusioncompute( $tab_number, $host_url, $server_url, $lpar_url, $fusioncompute_items[ $tab_number - 1 ], $entitle, $detail_yes, $legend );
    }
  }
  elsif ( $params{type} =~ m/^datastore-aggr$/ ) {
    my @fusioncompute_items = ( 'fusioncompute-datastore-used-aggr', 'fusioncompute-datastore-free-aggr' );
    for $tab_number ( 1 .. $#fusioncompute_items + 1 ) {
      $legend = ( $fusioncompute_items[ $tab_number - 1 ] =~ m/aggr/ ) ? 'nolegend' : 'legend';
      print_tab_contents_fusioncompute( $tab_number, $host_url, $server_url, $lpar_url, $fusioncompute_items[ $tab_number - 1 ], $entitle, $detail_yes, $legend );
    }
  }
  elsif ( $params{type} =~ m/^configuration$/ ) {
    my $config_update_time = localtime( FusionComputeDataWrapper::get_conf_update_time() );
    my $html_tab_header    = sub {
      my @columns = @_;
      my $result  = '';
      $result .= "<center>";
      $result .= "<table class=\"tabconfig tablesorter\">";
      $result .= "<thead><tr>";
      foreach my $item (@columns) {
        $result .= "<th class=\"sortable\">" . $item . "</th>";
      }
      $result .= "</tr></thead>";
      $result .= "<tbody>";

      return $result;
    };

    my $html_table_row = sub {
      my @cells  = @_;
      my $result = '';

      $result .= "<tr align=\"center\">";
      foreach my $cell (@cells) { $result .= $cell; }
      $result .= "</tr>";

      return $result;
    };

    my $html_tab_footer  = "</tbody></table><p>Last update time: " . $config_update_time . "</p></center>";
    my $html_tab_footer2 = "</tbody></table></center>";

    # host
    print "<div id=\"tabs-1\">\n";

    print "<h2>Host</h2>";

    print $html_tab_header->( 'Name', 'Cluster', 'Maintaining', 'CPU', 'Mem' );

    my $config_host = FusionComputeDataWrapper::get_conf_section('spec-host');
    my @host_list   = keys %{$config_host};

    foreach my $host (@host_list) {
      my $url = FusionComputeMenu::get_url( { type => 'host', host => $host } );

      #my $state = ( $config_host->{$host}{status} eq "normal" ) ? "<td class=\"hs_good\"><div>$config_host->{$host}{status}</div></td>" : "<td class=\"hs_warning\"><div>$config_host->{$host}{status}</div></td>";
      my $cpu = sprintf( "%.1f", ( $config_host->{$host}{cpuMHz} * $config_host->{$host}{cpuQuantity} ) / 1000 );
      my $mem = sprintf( "%.1f", $config_host->{$host}{memQuantityMB} / 1024 );
      print $html_table_row->( "<td><div><a style=\"padding:0px !important;\" href=\"$url\">$config_host->{$host}{name}</a></div></td>", "<td><div>$config_host->{$host}{clusterName}</div></td>", "<td><div>$config_host->{$host}{isMaintaining}</div></td>", "<td><div>$cpu GHz</div></td>", "<td><div>$mem GB</div></td>" );
    }

    print $html_tab_footer;

    print "</div>\n";

    # vm
    print "<div id=\"tabs-2\">\n";

    print "<h2>VM</h2>";

    print $html_tab_header->( 'Name', 'Cluster', 'Host', 'cdRomStatus', 'createTime' );

    my $config_vm = FusionComputeDataWrapper::get_conf_section('spec-vm');
    my @vm_list   = keys %{$config_vm};

    foreach my $vm (@vm_list) {
      my $url      = FusionComputeMenu::get_url( { type => 'vm',   vm   => $vm } );
      my $host_url = FusionComputeMenu::get_url( { type => 'host', host => $config_vm->{$vm}{hostUuid} } );

      #my $state = ( $config_vm->{$vm}{status} eq "running" ) ? "<td class=\"hs_good\"><div>$config_vm->{$vm}{status}</div></td>" : "<td class=\"hs_warning\"><div>$config_vm->{$vm}{status}</div></td>";
      print $html_table_row->( "<td><div><a style=\"padding:0px !important;\" href=\"$url\">$config_vm->{$vm}{name}</a></div></td>", "<td><div>$config_vm->{$vm}{clusterName}</div></td>", "<td><div><a style=\"padding:0px !important;\" href=\"$host_url\">$config_vm->{$vm}{hostName}</a></div></td>", "<td><div>$config_vm->{$vm}{cdRomStatus}</div></td>", "<td><div>$config_vm->{$vm}{createTime}</div></td>" );
    }

    print $html_tab_footer;

    print "</div>\n";

    # datastores
    print "<div id=\"tabs-3\">\n";

    print "<h2>Datastore</h2>";

    print $html_tab_header->( 'Name', 'Storage type', 'isThin', 'Thin rate', 'Capacity [GB]', 'Description' );

    my $config_ds = FusionComputeDataWrapper::get_conf_section('spec-datastore');
    my @ds_list   = keys %{$config_ds};

    foreach my $ds (@ds_list) {
      my $url = FusionComputeMenu::get_url( { type => 'datastore', datastore => $ds } );
      print $html_table_row->( "<td><div><a style=\"padding:0px !important;\" href=\"$url\">$config_ds->{$ds}{name}</a></div></td>", "<td><div>$config_ds->{$ds}{storageType}</div></td>", "<td><div>$config_ds->{$ds}{isThin}</div></td>", "<td><div>$config_ds->{$ds}{thinRate}</div></td>", "<td><div>$config_ds->{$ds}{capacityGB}</div></td>", "<td><div>$config_ds->{$ds}{description}</div></td>" );
    }

    print $html_tab_footer;

    print "</div>\n";

  }
  elsif ( $params{type} =~ m/^health$/ ) {
    my $config_update_time = localtime( FusionComputeDataWrapper::get_conf_update_time() );
    my $html_tab_header    = sub {
      my @columns = @_;
      my $result  = '';
      $result .= "<center>";
      $result .= "<table class=\"tabconfig tablesorter\">";
      $result .= "<thead><tr>";
      foreach my $item (@columns) {
        $result .= "<th class=\"sortable\">" . $item . "</th>";
      }
      $result .= "</tr></thead>";
      $result .= "<tbody>";

      return $result;
    };

    my $html_table_row = sub {
      my @cells  = @_;
      my $result = '';

      $result .= "<tr align=\"center\">";
      foreach my $cell (@cells) { $result .= $cell; }
      $result .= "</tr>";

      return $result;
    };

    my $html_tab_footer  = "</tbody></table><p>Last update time: " . $config_update_time . "</p></center>";
    my $html_tab_footer2 = "</tbody></table></center>";

    print "<div id=\"tabs-1\">\n";

    print "<h2>Health Status</h2>";

    print "<h3>Host</h3>";

    print $html_tab_header->( 'Name', 'Cluster', 'Status' );

    my $config_host = FusionComputeDataWrapper::get_conf_section('spec-host');
    my @host_list   = keys %{$config_host};

    foreach my $host (@host_list) {
      my $url   = FusionComputeMenu::get_url( { type => 'host', host => $host } );
      my $state = ( $config_host->{$host}{status} eq "normal" ) ? "<td class=\"hs_good\">$config_host->{$host}{status}</td>" : "<td class=\"hs_warning\">$config_host->{$host}{status}</td>";
      print $html_table_row->( "<td><a style=\"padding:0px !important;\" href=\"$url\">$config_host->{$host}{name}</a></td>", "<td>$config_host->{$host}{clusterName}</td>", $state );
    }

    print $html_tab_footer2;

    print "<h3>VM</h3>";

    print $html_tab_header->( 'Name', 'Cluster', 'Host', 'Status' );

    my $config_vm = FusionComputeDataWrapper::get_conf_section('spec-vm');
    my @vm_list   = keys %{$config_vm};

    foreach my $vm (@vm_list) {
      my $url      = FusionComputeMenu::get_url( { type => 'vm',   vm   => $vm } );
      my $host_url = FusionComputeMenu::get_url( { type => 'host', host => $config_vm->{$vm}{hostUuid} } );
      my $state    = ( $config_vm->{$vm}{status} eq "running" ) ? "<td class=\"hs_good\"><div>$config_vm->{$vm}{status}</div></td>" : "<td class=\"hs_warning\"><div>$config_vm->{$vm}{status}</div></td>";
      print $html_table_row->( "<td><div><a style=\"padding:0px !important;\" href=\"$url\">$config_vm->{$vm}{name}</a></div></td>", "<td><div>$config_vm->{$vm}{clusterName}</div></td>", "<td><div><a style=\"padding:0px !important;\" href=\"$host_url\">$config_vm->{$vm}{hostName}</a></div></td>", $state );
    }

    print $html_tab_footer;

    print "</div>\n";

  }
  elsif ( $params{type} =~ m/^alerts$/ ) {
    my $config_update_time = localtime( FusionComputeDataWrapper::get_conf_update_time() );
    my $html_tab_header    = sub {
      my @columns = @_;
      my $result  = '';
      $result .= "<center>";
      $result .= "<table class=\"tabconfig tablesorter\">";
      $result .= "<thead><tr>";
      foreach my $item (@columns) {
        $result .= "<th class=\"sortable\">" . $item . "</th>";
      }
      $result .= "</tr></thead>";
      $result .= "<tbody>";

      return $result;
    };

    my $html_table_row = sub {
      my @cells  = @_;
      my $result = '';

      $result .= "<tr>";
      foreach my $cell (@cells) { $result .= $cell; }
      $result .= "</tr>";

      return $result;
    };

    my $html_tab_footer  = "</tbody></table><p>Last update time: " . $config_update_time . "</p></center>";
    my $html_tab_footer2 = "</tbody></table></center>";

    my $alerts = FusionComputeDataWrapper::get_conf_section('alerts');
    my $urn    = FusionComputeDataWrapper::get_conf_section('urn');
    my %summary;
    my $table_content = '';
    foreach my $site ( keys %{$alerts} ) {
      $summary{$site} = {
        'Critical' => 0,
        'Major'    => 0,
        'Minor'    => 0,
        'Warning'  => 0
      };
      for my $alert ( @{ $alerts->{$site} } ) {
        my $object        = $urn->{ $alert->{objectUrn} } ? $urn->{ $alert->{objectUrn} } : ();
        my $object_column = "<td><div>$alert->{urnByName}</div></td>";
        if ( defined $object->{label} ) {
          my $url = FusionComputeMenu::get_url( { type => $object->{subsystem}, $object->{subsystem} => $object->{uuid} } );
          $object_column = "<td><a style=\"padding:0px !important;\" href=\"$url\">$object->{label} ($object->{subsystem})</a></td>";
        }
        $table_content .= $html_table_row->( "<td><div>$site</div></td>", "<td><div>$alert->{iAlarmLevel}</div></td>", $object_column, "<td><div>$alert->{iAlarmCategory}</div></td>", "<td><div>$alert->{svAlarmName}</div></td>", "<td><div>$alert->{svAlarmCause}</div></td>", "<td><div>$alert->{dtArrivedTime}</div></td>" );
        $summary{$site}{ $alert->{iAlarmLevel} }++;
      }
    }

    print "<div id=\"tabs-1\">\n";

    print "<h2>Summary</h2>";

    print $html_tab_header->( 'Site', 'Critical', 'Major', 'Minor', 'Warning' );

    foreach my $site ( keys %summary ) {
      print $html_table_row->( "<td><div>$site</div></td>", "<td align=\"center\"><div>$summary{$site}{Critical}</div></td>", "<td align=\"center\"><div>$summary{$site}{Major}</div></td>", "<td align=\"center\"><div>$summary{$site}{Minor}</div></td>", "<td align=\"center\"><div>$summary{$site}{Warning}</div></td>" );
    }

    print $html_tab_footer2;

    print "<h2>Alerts</h2>";

    print $html_tab_header->( 'Site', 'Level', 'Object', 'Category', 'Name', 'Cause', 'Time' );
    print $table_content;
    print $html_tab_footer;

    print "</div>\n";

  }
  elsif ( $params{type} =~ m/^topten_fusioncompute$/ ) {
    ############## LOAD TOPTEN FILE #####################
    my $topten_file_fusion = "$tmpdir/topten_fusion.tmp";
    my $last_update        = localtime( ( stat($topten_file_fusion) )[9] );
    #####################################################
    my $server_pool = "";

    # last day
    print "<div id=\"tabs-1\">\n";
    print "<table align=\"center\" summary=\"Graphs\">\n";
    print "<tr><th align=center>CPU in cores<a class=\"csvfloat\" href=\"/lpar2rrd-cgi/top10_csv.sh?LPAR=$server_pool&host=CSV&type=FUSIONCOMPUTE&table=topten&item=load_cpu&period=1\" title=\"LOAD CPU CSV\"><img src=\"css/images/csv.gif\"></a></th><th align=center>CPU in %<a class=\"csvfloat\" href=\"/lpar2rrd-cgi/top10_csv.sh?LPAR=$server_pool&host=CSV&type=FUSIONCOMPUTE&table=topten&item=cpu_perc&period=1\" title=\"CPU % CSV\"><img src=\"css/images/csv.gif\"></a></th><th align=center>IOPS<a class=\"csvfloat\" href=\"/lpar2rrd-cgi/top10_csv.sh?LPAR=$server_pool&host=CSV&type=FUSIONCOMPUTE&table=topten&item=iops&period=1\" title=\"IOPS CSV\"><img src=\"css/images/csv.gif\"></a></th><th align=center>NET in MB/sec<a class=\"csvfloat\" href=\"/lpar2rrd-cgi/top10_csv.sh?LPAR=$server_pool&host=CSV&type=FUSIONCOMPUTE&table=topten&item=net&period=1\" title=\"NET CSV\"><img src=\"css/images/csv.gif\"></a></th><th align=center>DATA in MB<a class=\"csvfloat\" href=\"/lpar2rrd-cgi/top10_csv.sh?LPAR=$server_pool&host=CSV&type=FUSIONCOMPUTE&table=topten&item=data&period=1\" title=\"DISK CSV\"><img src=\"css/images/csv.gif\"></a></th><th align=center>DISK Usage in %<a class=\"csvfloat\" href=\"/lpar2rrd-cgi/top10_csv.sh?LPAR=$server_pool&host=CSV&type=FUSIONCOMPUTE&table=topten&item=disk_usage&period=1\" title=\"DISK USAGE CSV\"><img src=\"css/images/csv.gif\"></a></th></tr>";
    print "<tr style=\"vertical-align:top\">";
    print_top10_to_table_fusion( "1", "$server_pool", "load_cpu" );
    print_top10_to_table_fusion( "1", "$server_pool", "cpu_perc" );
    print_top10_to_table_fusion( "1", "$server_pool", "iops" );
    print_top10_to_table_fusion( "1", "$server_pool", "net" );
    print_top10_to_table_fusion( "1", "$server_pool", "data" );
    print_top10_to_table_fusion( "1", "$server_pool", "disk_usage" );
    print "</tr>";
    print "</table>";
    print "<tfoot><tr><td colspan=\"6\">Last update time: $last_update</td></tr></tfoot>";
    print "</div>\n";

    # last week
    print "<div id=\"tabs-2\">\n";
    print "<table align=\"center\" summary=\"Graphs\">\n";
    print "<tr><th align=center>CPU in cores<a class=\"csvfloat\" href=\"/lpar2rrd-cgi/top10_csv.sh?LPAR=$server_pool&host=CSV&type=FUSIONCOMPUTE&table=topten&item=load_cpu&period=4\" title=\"LOAD CPU CSV\"><img src=\"css/images/csv.gif\"></a></th><th align=center>CPU in %<a class=\"csvfloat\" href=\"/lpar2rrd-cgi/top10_csv.sh?LPAR=$server_pool&host=CSV&type=FUSIONCOMPUTE&table=topten&item=cpu_perc&period=2\" title=\"CPU % CSV\"><img src=\"css/images/csv.gif\"></a></th><th align=center>IOPS<a class=\"csvfloat\" href=\"/lpar2rrd-cgi/top10_csv.sh?LPAR=$server_pool&host=CSV&type=FUSIONCOMPUTE&table=topten&item=iops&period=2\" title=\"IOPS CSV\"><img src=\"css/images/csv.gif\"></a></th><th align=center>NET in MB/sec<a class=\"csvfloat\" href=\"/lpar2rrd-cgi/top10_csv.sh?LPAR=$server_pool&host=CSV&type=FUSIONCOMPUTE&table=topten&item=net&period=2\" title=\"NET CSV\"><img src=\"css/images/csv.gif\"></a></th><th align=center>DATA in MB<a class=\"csvfloat\" href=\"/lpar2rrd-cgi/top10_csv.sh?LPAR=$server_pool&host=CSV&type=FUSIONCOMPUTE&table=topten&item=disk&period=2\" title=\"DISK CSV\"><img src=\"css/images/csv.gif\"></a></th><th align=center>DISK Usage in %<a class=\"csvfloat\" href=\"/lpar2rrd-cgi/top10_csv.sh?LPAR=$server_pool&host=CSV&type=FUSIONCOMPUTE&table=topten&item=disk_usage&period=2\" title=\"DISK USAGE CSV\"><img src=\"css/images/csv.gif\"></a></th></tr>";
    print "<tr style=\"vertical-align:top\">";
    print_top10_to_table_fusion( "2", "$server_pool", "load_cpu" );
    print_top10_to_table_fusion( "2", "$server_pool", "cpu_perc" );
    print_top10_to_table_fusion( "2", "$server_pool", "iops" );
    print_top10_to_table_fusion( "2", "$server_pool", "net" );
    print_top10_to_table_fusion( "2", "$server_pool", "data" );
    print_top10_to_table_fusion( "2", "$server_pool", "disk_usage" );
    print "</tr>";
    print "</table>";
    print "<tfoot><tr><td colspan=\"6\">Last update time: $last_update</td></tr></tfoot>";
    print "</div>\n";

    # last month
    print "<div id=\"tabs-3\">\n";
    print "<table align=\"center\" summary=\"Graphs\">\n";
    print "<tr><th align=center>CPU in cores<a class=\"csvfloat\" href=\"/lpar2rrd-cgi/top10_csv.sh?LPAR=$server_pool&host=CSV&type=FUSIONCOMPUTE&table=topten&item=load_cpu&period=4\" title=\"LOAD CPU CSV\"><img src=\"css/images/csv.gif\"></a></th><th align=center>CPU in %<a class=\"csvfloat\" href=\"/lpar2rrd-cgi/top10_csv.sh?LPAR=$server_pool&host=CSV&type=FUSIONCOMPUTE&table=topten&item=cpu_perc&period=3\" title=\"CPU % CSV\"><img src=\"css/images/csv.gif\"></a></th><th align=center>IOPS<a class=\"csvfloat\" href=\"/lpar2rrd-cgi/top10_csv.sh?LPAR=$server_pool&host=CSV&type=FUSIONCOMPUTE&table=topten&item=iops&period=3\" title=\"IOPS CSV\"><img src=\"css/images/csv.gif\"></a></th><th align=center>NET in MB/sec<a class=\"csvfloat\" href=\"/lpar2rrd-cgi/top10_csv.sh?LPAR=$server_pool&host=CSV&type=FUSIONCOMPUTE&table=topten&item=net&period=3\" title=\"NET CSV\"><img src=\"css/images/csv.gif\"></a></th><th align=center>DATA in MB<a class=\"csvfloat\" href=\"/lpar2rrd-cgi/top10_csv.sh?LPAR=$server_pool&host=CSV&type=FUSIONCOMPUTE&table=topten&item=disk&period=3\" title=\"DISK CSV\"><img src=\"css/images/csv.gif\"></a></th><th align=center>DISK Usage in %<a class=\"csvfloat\" href=\"/lpar2rrd-cgi/top10_csv.sh?LPAR=$server_pool&host=CSV&type=FUSIONCOMPUTE&table=topten&item=disk_usage&period=3\" title=\"DISK USAGE CSV\"><img src=\"css/images/csv.gif\"></a></th></tr>";
    print "<tr style=\"vertical-align:top\">";
    print_top10_to_table_fusion( "3", "$server_pool", "load_cpu" );
    print_top10_to_table_fusion( "3", "$server_pool", "cpu_perc" );
    print_top10_to_table_fusion( "3", "$server_pool", "iops" );
    print_top10_to_table_fusion( "3", "$server_pool", "net" );
    print_top10_to_table_fusion( "3", "$server_pool", "data" );
    print_top10_to_table_fusion( "3", "$server_pool", "disk_usage" );
    print "</tr>";
    print "</table>";
    print "<tfoot><tr><td colspan=\"6\">Last update time: $last_update</td></tr></tfoot>";
    print "</div>\n";

    # last year
    print "<div id=\"tabs-4\">\n";
    print "<table align=\"center\" summary=\"Graphs\">\n";
    print "<tr><th align=center>CPU in cores<a class=\"csvfloat\" href=\"/lpar2rrd-cgi/top10_csv.sh?LPAR=$server_pool&host=CSV&type=FUSIONCOMPUTE&table=topten&item=load_cpu&period=4\" title=\"LOAD CPU CSV\"><img src=\"css/images/csv.gif\"></a></th><th align=center>CPU in %<a class=\"csvfloat\" href=\"/lpar2rrd-cgi/top10_csv.sh?LPAR=$server_pool&host=CSV&type=FUSIONCOMPUTE&table=topten&item=cpu_perc&period=4\" title=\"CPU % CSV\"><img src=\"css/images/csv.gif\"></a></th><th align=center>IOPS<a class=\"csvfloat\" href=\"/lpar2rrd-cgi/top10_csv.sh?LPAR=$server_pool&host=CSV&type=FUSIONCOMPUTE&table=topten&item=iops&period=4\" title=\"IOPS CSV\"><img src=\"css/images/csv.gif\"></a></th><th align=center>NET in MB/sec<a class=\"csvfloat\" href=\"/lpar2rrd-cgi/top10_csv.sh?LPAR=$server_pool&host=CSV&type=FUSIONCOMPUTE&table=topten&item=net&period=4\" title=\"NET CSV\"><img src=\"css/images/csv.gif\"></a></th><th align=center>DATA in MB<a class=\"csvfloat\" href=\"/lpar2rrd-cgi/top10_csv.sh?LPAR=$server_pool&host=CSV&type=FUSIONCOMPUTE&table=topten&item=data&period=4\" title=\"DISK CSV\"><img src=\"css/images/csv.gif\"></a></th><th align=center>DISK Usage in %<a class=\"csvfloat\" href=\"/lpar2rrd-cgi/top10_csv.sh?LPAR=$server_pool&host=CSV&type=FUSIONCOMPUTE&table=topten&item=disk_usage&period=4\" title=\"DISK USAGE CSV\"><img src=\"css/images/csv.gif\"></a></th></tr>";
    print "<tr style=\"vertical-align:top\">";
    print_top10_to_table_fusion( "4", "$server_pool", "load_cpu" );
    print_top10_to_table_fusion( "4", "$server_pool", "cpu_perc" );
    print_top10_to_table_fusion( "4", "$server_pool", "iops" );
    print_top10_to_table_fusion( "4", "$server_pool", "net" );
    print_top10_to_table_fusion( "4", "$server_pool", "data" );
    print_top10_to_table_fusion( "4", "$server_pool", "disk_usage" );
    print "</tr>";
    print "</table>";
    print "<tfoot><tr><td colspan=\"6\">Last update time: $last_update</td></tr></tfoot>";
    print "</div>\n";

  }

  sub print_top10_to_table_fusion {
    my ( $period, $server_pool, $item_name ) = @_;
    my $topten_file_fusion = "$tmpdir/topten_fusion.tmp";
    my $html_tab_header    = sub {
      my @columns = @_;
      my $result  = '';
      $result .= "<center>";
      $result .= "<table style=\"white-space: nowrap;\" class=\"tabconfig tablesorter \" data-sortby='1'>";
      $result .= "<thead><tr>";
      foreach my $item (@columns) {
        $result .= "<th class=\"sortable\">" . $item . "</th>";
      }
      $result .= "</tr></thead>";
      $result .= "<tbody>";
      return $result;
    };
    my $html_table_row = sub {
      my @cells  = @_;
      my $result = '';

      $result .= "<tr>";
      foreach my $cell (@cells) { $result .= "<td>" . $cell . "</td>"; }
      $result .= "</tr>";

      return $result;
    };

    # Table or create CSV file
    my $csv_file;
    if ( $item_name eq "load_cpu" ) {
      $csv_file = "fusion-load-cpu.csv";
    }
    elsif ( $item_name eq "cpu_perc" ) {
      $csv_file = "fusion-cpu-perc.csv";
    }
    elsif ( $item_name eq "net" ) {
      $csv_file = "fusion-net.csv";
    }
    elsif ( $item_name eq "data" ) {
      $csv_file = "fusion-disk.csv";
    }
    elsif ( $item_name eq "iops" ) {
      $csv_file = "fusion-iops.csv";
    }
    elsif ( $item_name eq "disk_usage" ) {
      $csv_file = "fusion-disk-usage.csv";
    }
    if ( !$csv ) {
      print "<TD><TABLE class=\"tabconfig tablesorter\" data-sortby=\"1\">";
      if ( $period == 4 ) {    # last year
        print $html_tab_header->( 'Avrg', "VM", "Host", 'Cluster' );
      }
      else {
        print $html_tab_header->( 'Avrg', 'Max', "VM", "Host", 'Cluster' );
      }
    }
    else {
      print "Content-Disposition: attachment;filename=\"$csv_file\"\n\n";
      my $csv_header = "";
      if ( $period == 4 ) {    # last year
        $csv_header = "Avrg" . "$sep" . "VM" . "$sep" . "Host" . "$sep" . "Cluster\n";
      }
      else {
        $csv_header = "Avrg" . "$sep" . "Max" . "$sep" . "VM" . "$sep" . "Host" . "$sep" . "Cluster\n";
      }
      print "$csv_header";
    }
    my @topten;
    my @topten_not_sorted;
    my @topten_sorted;
    my $topten_limit = 0;
    my @top_values_avrg;
    my @top_values_max;
    if ( -f $topten_file_fusion ) {
      open( FH, " < $topten_file_fusion" ) || error( "Cannot open $topten_file_fusion: $!" . __FILE__ . ":" . __LINE__ );
      @topten = <FH>;
      close FH;
      if ( defined $ENV{TOPTEN} ) {
        $topten_limit = $ENV{TOPTEN};
      }
      $topten_limit = 50 if $topten_limit < 1;
      my @topten_server;
      if ( $item_name eq "load_cpu" ) {
        @topten_server = grep {/load_cpu,/} @topten;
      }
      if ( $item_name eq "cpu_perc" ) {
        @topten_server = grep {/cpu_perc,/} @topten;
      }
      elsif ( $item_name eq "iops" ) {
        @topten_server = grep {/iops,/} @topten;
      }
      elsif ( $item_name eq "net" ) {
        @topten_server = grep {/net,/} @topten;
      }
      elsif ( $item_name eq "data" ) {
        @topten_server = grep {/data,/} @topten;
      }
      elsif ( $item_name eq "disk_usage" ) {
        @topten_server = grep {/disk_usage,/} @topten;
      }
      @topten = @topten_server;
      foreach my $line (@topten) {
        chomp $line;
        my ( $item, $vm_name, $location, $host_name );
        ( $item, $vm_name, $location, $host_name, $top_values_avrg[1], $top_values_max[1], $top_values_avrg[2], $top_values_max[2], $top_values_avrg[3], $top_values_max[3], $top_values_avrg[4], $top_values_max[4] ) = split( ",", $line );
        $top_values_avrg[4] = 0 if !defined $top_values_avrg[4] or $top_values_avrg[4] eq "";    # no year value yet, new file
        $top_values_max[4]  = 0 if !defined $top_values_max[4]  or $top_values_max[4] eq "";     # no year value yet, new file
        if ( $top_values_avrg[1] == 0 && $top_values_max[1] == 0 && $top_values_avrg[2] == 0 && $top_values_max[2] == 0 && $top_values_avrg[3] == 0 && $top_values_max[3] == 0 && $top_values_avrg[4] == 0 && $top_values_max[4] == 0 ) { next; }
        push @topten_not_sorted, "$item,$top_values_avrg[$period],$top_values_max[$period],$vm_name,$location,$host_name\n";
      }
      {
        no warnings;
        @topten_sorted = sort { $b <=> $a } @topten_not_sorted;
      }
    }
    my @topten_sorted_load_cpu;
    {
      no warnings;
      @topten_sorted_load_cpu = sort {
        my @b = split( /,/, $b );
        my @a = split( /,/, $a );

        #print "$b[4] --- $a[4]\n";
        $b[1] <=> $a[1]
      } @topten_sorted;
    }
    foreach my $line1 (@topten_sorted_load_cpu) {
      chomp $line1;
      my ( $item_a, $load_cpu, $load_peak, $vm_name, $location, $host_name );
      ( $item_a, $load_cpu, $load_peak, $vm_name, $location, $host_name ) = split( ",", $line1 );
      if ( !$csv ) {
        if ( $period == 4 ) {    # last year
          print $html_table_row->( $load_cpu, $vm_name, $host_name, $location );
        }
        else {
          print $html_table_row->( $load_cpu, $load_peak, $vm_name, $host_name, $location );
        }
      }
      else {
        if ( $period == 4 ) {    # last year
          print "$load_cpu" . "$sep" . "$vm_name" . "$sep" . "$host_name" . "$sep" . "$location\n";
        }
        else {
          print "$load_cpu" . "$sep" . "$load_peak" . "$sep" . "$vm_name" . "$sep" . "$host_name" . "$sep" . "$location\n";
        }
      }
    }
    if ( !$csv ) {
      print "</TABLE></TD>";
    }
    return 1;
  }

  # closing page contents
  print "</CENTER>";
  print "</div><br>\n";

  exit(0);
}

if ($oracledb) {
  my $mapping;
  if ( $params{id} and !$params{host} ) {
    my $arc = OracleDBDataWrapper::get_arc();

    #return if ($use_sql && ! isGranted($params{id}));
    $params{id} =~ s/_totals//g;
    $params{id} =~ s/_gcache//g;
    $host_url   = $arc->{ $params{id} }->{host};
    $server_url = $arc->{ $params{id} }->{server};
    if ( $params{type} =~ /hosts_Total/ ) {
      $host_url   = "not_needed";
      $server_url = "hostname";
    }
    elsif ( $params{type} =~ /configuration_Multitenant/ ) {
      $host_url = OracleDBDataWrapper::basename( $host_url, "_" );
    }
    if ( $params{id} =~ /__DBTotal/ ) {
      my $par = $params{id};
      $par =~ s/DBTotal//g;
      my $group = OracleDBDataWrapper::basename( $par, "__" );
      $host_url   = "groups_$group";
      $server_url = "not_needed";
    }
  }
  else {
    if ( ( $params{type} =~ /configuration_Total/ ) and ( !$params{host} or $params{host} eq "" or $params{server} eq "" ) ) {
      $host_url   = "groups__OracleDB";
      $server_url = "not_needed";
    }
    ### TOP10 ORACLE DB
    elsif ( $params{type} =~ m/^topten_oracledb$/ ) {

      # get tabs
      my @tabs  = @{ OracleDBMenu::get_tabs( $params{type} ) };
      my @items = ();

      $tab_number = 1;
      if (@tabs) {
        print "<div id=\"tabs\">\n";
        print "<ul>\n";

        foreach my $tab_header (@tabs) {
          while ( my ( $tab_type, $tab_label ) = each %$tab_header ) {
            print "  <li class=\"$tab_type\"><a href=\"#tabs-$tab_number\">$tab_label</a></li>\n";
            $tab_number++;
            push @items, "oracledb_$lpar_url\_$tab_type";
          }
        }
        print "</ul>\n";
      }
      ############## LOAD TOPTEN FILE #####################
      my $topten_file_ordb = "$tmpdir/topten_oracledb.tmp";
      my $last_update      = localtime( ( stat($topten_file_ordb) )[9] );
      #####################################################
      my $server_pool = "";

      # last day
      print "<div id=\"tabs-1\">\n";
      print "<table align=\"center\" summary=\"Graphs\">\n";
      print "<tr><th align=center>CPU Usage Per Sec<a class=\"csvfloat\" href=\"/lpar2rrd-cgi/top10_csv.sh?LPAR=$server_pool&host=CSV&type=ORACLEDB&table=topten&item=load_cpu&period=1\" title=\"LOAD CPU CSV\"><img src=\"css/images/csv.gif\"></a></th><th align=center>Logons count<a class=\"csvfloat\" href=\"/lpar2rrd-cgi/top10_csv.sh?LPAR=$server_pool&host=CSV&type=ORACLEDB&table=topten&item=session&period=1\" title=\"CPU % CSV\"><img src=\"css/images/csv.gif\"></a></th><th align=center>IOPS/sec<a class=\"csvfloat\" href=\"/lpar2rrd-cgi/top10_csv.sh?LPAR=$server_pool&host=CSV&type=ORACLEDB&table=topten&item=io&period=1\" title=\"IOPS CSV\"><img src=\"css/images/csv.gif\"></a></th><th align=center>DATA in MB<a class=\"csvfloat\" href=\"/lpar2rrd-cgi/top10_csv.sh?LPAR=$server_pool&host=CSV&type=ORACLEDB&table=topten&item=data&period=1\" title=\"DISK CSV\"><img src=\"css/images/csv.gif\"></a></th></tr>";
      print "<tr style=\"vertical-align:top\">";
      print_top10_to_table_ordb( "1", "$server_pool", "load_cpu" );
      print_top10_to_table_ordb( "1", "$server_pool", "session" );
      print_top10_to_table_ordb( "1", "$server_pool", "io" );
      print_top10_to_table_ordb( "1", "$server_pool", "data" );
      print "</tr>";
      print "</table>";
      print "<tfoot><tr><td colspan=\"6\">Last update time: $last_update</td></tr></tfoot>";
      print "</div>\n";

      # last week
      print "<div id=\"tabs-2\">\n";
      print "<table align=\"center\" summary=\"Graphs\">\n";
      print "<tr><th align=center>CPU Usage Per Sec<a class=\"csvfloat\" href=\"/lpar2rrd-cgi/top10_csv.sh?LPAR=$server_pool&host=CSV&type=ORACLEDB&table=topten&item=load_cpu&period=2\" title=\"LOAD CPU CSV\"><img src=\"css/images/csv.gif\"></a></th><th align=center>Logons count<a class=\"csvfloat\" href=\"/lpar2rrd-cgi/top10_csv.sh?LPAR=$server_pool&host=CSV&type=ORACLEDB&table=topten&item=session&period=2\" title=\"CPU % CSV\"><img src=\"css/images/csv.gif\"></a></th><th align=center>IOPS/sec<a class=\"csvfloat\" href=\"/lpar2rrd-cgi/top10_csv.sh?LPAR=$server_pool&host=CSV&type=ORACLEDB&table=topten&item=io&period=2\" title=\"IOPS CSV\"><img src=\"css/images/csv.gif\"></a></th><th align=center>DATA in MB<a class=\"csvfloat\" href=\"/lpar2rrd-cgi/top10_csv.sh?LPAR=$server_pool&host=CSV&type=ORACLEDB&table=topten&item=data&period=2\" title=\"DISK CSV\"><img src=\"css/images/csv.gif\"></a></th></tr>";
      print "<tr style=\"vertical-align:top\">";
      print_top10_to_table_ordb( "2", "$server_pool", "load_cpu" );
      print_top10_to_table_ordb( "2", "$server_pool", "session" );
      print_top10_to_table_ordb( "2", "$server_pool", "io" );
      print_top10_to_table_ordb( "2", "$server_pool", "data" );
      print "</tr>";
      print "</table>";
      print "<tfoot><tr><td colspan=\"6\">Last update time: $last_update</td></tr></tfoot>";
      print "</div>\n";

      # last month
      print "<div id=\"tabs-3\">\n";
      print "<table align=\"center\" summary=\"Graphs\">\n";
      print "<tr><th align=center>CPU Usage Per Sec<a class=\"csvfloat\" href=\"/lpar2rrd-cgi/top10_csv.sh?LPAR=$server_pool&host=CSV&type=ORACLEDB&table=topten&item=load_cpu&period=3\" title=\"LOAD CPU CSV\"><img src=\"css/images/csv.gif\"></a></th><th align=center>Logons count<a class=\"csvfloat\" href=\"/lpar2rrd-cgi/top10_csv.sh?LPAR=$server_pool&host=CSV&type=ORACLEDB&table=topten&item=session&period=3\" title=\"CPU % CSV\"><img src=\"css/images/csv.gif\"></a></th><th align=center>IOPS/sec<a class=\"csvfloat\" href=\"/lpar2rrd-cgi/top10_csv.sh?LPAR=$server_pool&host=CSV&type=ORACLEDB&table=topten&item=io&period=3\" title=\"IOPS CSV\"><img src=\"css/images/csv.gif\"></a></th><th align=center>DATA in MB<a class=\"csvfloat\" href=\"/lpar2rrd-cgi/top10_csv.sh?LPAR=$server_pool&host=CSV&type=ORACLEDB&table=topten&item=data&period=3\" title=\"DISK CSV\"><img src=\"css/images/csv.gif\"></a></th></tr>";
      print "<tr style=\"vertical-align:top\">";
      print_top10_to_table_ordb( "3", "$server_pool", "load_cpu" );
      print_top10_to_table_ordb( "3", "$server_pool", "session" );
      print_top10_to_table_ordb( "3", "$server_pool", "io" );
      print_top10_to_table_ordb( "3", "$server_pool", "data" );
      print "</tr>";
      print "</table>";
      print "<tfoot><tr><td colspan=\"6\">Last update time: $last_update</td></tr></tfoot>";
      print "</div>\n";

      # last year
      print "<div id=\"tabs-4\">\n";
      print "<table align=\"center\" summary=\"Graphs\">\n";
      print "<tr><th align=center>CPU Usage Per Sec<a class=\"csvfloat\" href=\"/lpar2rrd-cgi/top10_csv.sh?LPAR=$server_pool&host=CSV&type=ORACLEDB&table=topten&item=load_cpu&period=4\" title=\"LOAD CPU CSV\"><img src=\"css/images/csv.gif\"></a></th><th align=center>Logons count<a class=\"csvfloat\" href=\"/lpar2rrd-cgi/top10_csv.sh?LPAR=$server_pool&host=CSV&type=ORACLEDB&table=topten&item=session&period=4\" title=\"CPU % CSV\"><img src=\"css/images/csv.gif\"></a></th><th align=center>IOPS/sec<a class=\"csvfloat\" href=\"/lpar2rrd-cgi/top10_csv.sh?LPAR=$server_pool&host=CSV&type=ORACLEDB&table=topten&item=io&period=4\" title=\"IOPS CSV\"><img src=\"css/images/csv.gif\"></a></th><th align=center>DATA in MB<a class=\"csvfloat\" href=\"/lpar2rrd-cgi/top10_csv.sh?LPAR=$server_pool&host=CSV&type=ORACLEDB&table=topten&item=data&period=4\" title=\"DISK CSV\"><img src=\"css/images/csv.gif\"></a></th></tr>";
      print "<tr style=\"vertical-align:top\">";
      print_top10_to_table_ordb( "4", "$server_pool", "load_cpu" );
      print_top10_to_table_ordb( "4", "$server_pool", "session" );
      print_top10_to_table_ordb( "4", "$server_pool", "io" );
      print_top10_to_table_ordb( "4", "$server_pool", "data" );
      print "</tr>";
      print "</table>";
      print "<tfoot><tr><td colspan=\"6\">Last update time: $last_update</td></tr></tfoot>";
      print "</div>\n";
    }
    else {
      $host_url   = $params{host};
      $server_url = $params{server};
    }
  }

  my %creds = %{ HostCfg::getHostConnections("OracleDB") };
  if ( ( $server_url ne "not_needed" and $server_url ne "hostname" ) and ( $server_url eq "nope" or !$creds{$server_url} ) ) {
    exit(0);
  }

  my $t_result = OracleDBDataWrapper::does_type_exist( $params{type} );
  if ($t_result) {

    #$lpar_url = OracleDBDataWrapper::remove_subs($params{type});
    $lpar_url = $params{type};
  }
  else {
    exit(0);
  }

  print "<CENTER>";

  # get tabs
  my @tabs  = @{ OracleDBMenu::get_tabs( $params{type} ) };
  my @items = ();

  $tab_number = 1;
  if (@tabs) {
    print "<div id=\"tabs\">\n";
    print "<ul>\n";

    foreach my $tab_header (@tabs) {
      while ( my ( $tab_type, $tab_label ) = each %$tab_header ) {
        print "  <li class=\"$tab_type\"><a href=\"#tabs-$tab_number\">$tab_label</a></li>\n";
        $tab_number++;
        push @items, "oracledb_$lpar_url\_$tab_type";
      }
    }

    #    if ( $mapping ) {
    #      @item_agent      = ();
    #      @item_agent_tab  = ();
    #      $item_agent_indx = $tab_number;
    #      $os_agent        = 0;
    #      $nmon_agent      = 0;
    #      $iops            = "IOPS";
    #
    #      build_agents_tabs( "Linux", "no_hmc", $mapping );
    #    }

    print "</ul>\n";
  }

  for ( $tab_number = 1; $tab_number <= $#items + 1; $tab_number++ ) {
    if ( $t_result eq "conf" ) {
      my @conf_files = @{ OracleDBDataWrapper::conf_files( $wrkdir, $lpar_url, $server_url, $host_url ) };
      my @file;
      my $conf_file = $conf_files[ $tab_number - 1 ];

      if ( $conf_file eq " " ) {
        my $odb_item = $items[ $tab_number - 1 ];
        my $legend   = "legend";                    #$odb_item =~ /oracledb_Wait_class_Main|oracledb_Services/ ? 'nolegend' : 'legend';
        if ( $odb_item =~ /oracledb_(Wait_class_Main|Services|configuration_Total|configuration_DBTotal)/ or $host_url =~ m/^aggregated/ ) {
          $legend = 'nolegend';
        }
        else {
          $legend = 'legend';
        }

        #        my $legend     = $odb_item =~ /aggr/ ? 'nolegend' : 'legend';

        print_tab_content_oracledb(
          $tab_number, $host_url, $server_url, $lpar_url, $odb_item, $entitle,
          $detail_yes, $legend
        );
      }

      if ( -f $conf_file ) {
        open( CFGH, '<', $conf_file ) || Xorux_lib::error( "Couldn't open file $conf_file $!" . __FILE__ . ":" . __LINE__ );
        @file = <CFGH>;
        close(CFGH);
      }

      print "<div id=\"tabs-$tab_number\">\n";

      if ( scalar @file ) {
        print @file;
      }
      else {
        unless ( $conf_file eq " " ) {
          print "<p>Configuration is generated during first load each day.</p>";
        }
      }

      print "</div>\n";
    }
    else {
      my $odb_item = $items[ $tab_number - 1 ];
      my $legend   = "legend";                    #$odb_item =~ /oracledb_Wait_class_Main|oracledb_Services/ ? 'nolegend' : 'legend';
      if ( $odb_item =~ /oracledb_(Wait_class_Main|Services|host_metrics|hosts_Total)/ or $host_url =~ m/^aggregated/ ) {
        $legend = 'nolegend';
      }
      else {
        $legend = 'legend';
      }
      if ( $odb_item =~ /oracledb_Overview/ ) {
        print_tab_content_oracledb_overview(
          $tab_number, $host_url, $server_url, $lpar_url, $odb_item, $entitle,
          $detail_yes, $legend
        );
      }
      else {
        print_tab_content_oracledb(
          $tab_number, $host_url, $server_url, $lpar_url, $odb_item, $entitle,
          $detail_yes, $legend
        );
      }
    }
  }

  sub print_tab_content_oracledb_overview {
    my ( $tab_number, $host_url, $server_url, $lpar_url, $item, $entitle, $detail_yes, $legend ) = @_;
    my $inputdir = $ENV{INPUTDIR};
    my $tmp_dir  = "$inputdir/tmp";
    my $hs_dir   = "$tmp_dir/health_status_summary/OracleDB";
    my %creds    = %{ HostCfg::getHostConnections("OracleDB") };
    my @files;
    if ( -e $hs_dir ) {
      opendir( DH, $hs_dir ) || Xorux_lib::error("Could not open '$hs_dir' for reading '$!'\n");
      @files = grep /.*$server_url.*\.nok/, readdir DH;
      closedir(DH);
    }

    if ( $files[0] ) {
      print "<div class='oracledb_status fas fa-lock' title='Status: CLOSED'>\n";
      print "</div>\n";
    }
    else {
      print "<div class='oracledb_status fas fa-unlock' title='Status: OPEN'>\n";
      print "</div>\n";
    }
    #
    print "<div id=\"tabs-$tab_number\">\n";
    print "<table border=\"0\">\n";
    print "<tr>";

    #print "<pOPEN</p>";
    if ( $creds{$server_url}{type} eq "RAC" ) {
      print_item( $host_url, $server_url, "oracledb_aggr_CPU_info", "oracledb_aggr_CPU_info__CPU_Usage_Per_Sec", "d", "", $entitle, $detail_yes, "norefr", "star", 1, $legend );
      print_item( $host_url, $server_url, "aggr_Session_info",      "oracledb_aggr_Session_info_Session_info",   "d", "", $entitle, $detail_yes, "norefr", "star", 1, $legend );
      print "</tr>\n<tr>\n";
      print_item( $host_url, $server_url, "Disk_latency", "oracledb_Disk_latency_db_file_read", "d", "", $entitle, $detail_yes, "norefr", "star", 1, $legend );
      print_item( $host_url, $server_url, "Disk_latency", "oracledb_Disk_latency_log_write",    "d", "", $entitle, $detail_yes, "norefr", "star", 1, $legend );
      print "</tr>\n<tr>\n";
      print_item( $host_url, $server_url, "oracledb_aggr_Data_rate", "oracledb_aggr_Data_rate__IO_Requests_per_Second", "d", "", $entitle, $detail_yes, "norefr", "star", 1, $legend );
      print_item( $host_url, $server_url, "oracledb_aggr_Datarate",  "oracledb_aggr_Datarate__IO_Megabytes_per_Second", "d", "", $entitle, $detail_yes, "norefr", "star", 1, $legend );
    }
    elsif ( $creds{$server_url}{type} eq "Multitenant" ) {
      print_item( $host_url, $server_url, "Disk_latency", "oracledb_Disk_latency_db_file_read", "d", "", $entitle, $detail_yes, "norefr", "star", 1, "legend" );
      print_item( $host_url, $server_url, "Disk_latency", "oracledb_Disk_latency_log_write",    "d", "", $entitle, $detail_yes, "norefr", "star", 1, "legend" );
      print "</tr>\n<tr>\n";
      print_item( $host_url, $server_url, "oracledb_Data_rate", "oracledb_Data_rate__IO_Requests_per_Second", "d", "", $entitle, $detail_yes, "norefr", "star", 1, "legend" );
      print_item( $host_url, $server_url, "oracledb_Datarate",  "oracledb_Datarate__IO_Megabytes_per_Second", "d", "", $entitle, $detail_yes, "norefr", "star", 1, "legend" );
      print "</tr>\n<tr>\n";
      print_item( $host_url, $server_url, "oracledb_CPU_info", "oracledb_CPU_info__CPU_Usage_Per_Sec", "d", "", $entitle, $detail_yes, "norefr", "star", 1, "legend" );
    }
    elsif ( $creds{$server_url}{type} eq "RAC_Multitenant" ) {
      print_item( $host_url, $server_url, "Disk_latency", "oracledb_Disk_latency_db_file_read", "d", "", $entitle, $detail_yes, "norefr", "star", 1, "$legend" );
      print_item( $host_url, $server_url, "Disk_latency", "oracledb_Disk_latency_log_write",    "d", "", $entitle, $detail_yes, "norefr", "star", 1, "$legend" );
      print "</tr>\n<tr>\n";
      print_item( $host_url, $server_url, "oracledb_Data_rate", "oracledb_Data_rate__IO_Requests_per_Second", "d", "", $entitle, $detail_yes, "norefr", "star", 1, "$legend" );
      print_item( $host_url, $server_url, "oracledb_Datarate",  "oracledb_Datarate__IO_Megabytes_per_Second", "d", "", $entitle, $detail_yes, "norefr", "star", 1, "$legend" );
      print "</tr>\n<tr>\n";
      print_item( $host_url, $server_url, "oracledb_CPU_info", "oracledb_CPU_info__CPU_Usage_Per_Sec", "d", "", $entitle, $detail_yes, "norefr", "star", 1, "$legend" );
    }
    else {
      print_item( $host_url, $server_url, "oracledb_CPU_info", "oracledb_CPU_info__CPU_Usage_Per_Sec", "d", "", $entitle, $detail_yes, "norefr", "star", 1, "legend" );
      print_item( $host_url, $server_url, "Session_info",      "oracledb_Session_info_info",           "d", "", $entitle, $detail_yes, "norefr", "star", 1, "legend" );
      print "</tr>\n<tr>\n";
      print_item( $host_url, $server_url, "Disk_latency", "oracledb_Disk_latency_db_file_read", "d", "", $entitle, $detail_yes, "norefr", "star", 1, "legend" );
      print_item( $host_url, $server_url, "Disk_latency", "oracledb_Disk_latency_log_write",    "d", "", $entitle, $detail_yes, "norefr", "star", 1, "legend" );
      print "</tr>\n<tr>\n";
      print_item( $host_url, $server_url, "oracledb_Data_rate", "oracledb_Data_rate__IO_Requests_per_Second", "d", "", $entitle, $detail_yes, "norefr", "star", 1, "legend" );
      print_item( $host_url, $server_url, "oracledb_Datarate",  "oracledb_Datarate__IO_Megabytes_per_Second", "d", "", $entitle, $detail_yes, "norefr", "star", 1, "legend" );
    }
    print "</tr></table>";
    print "</div>\n";
  }

  sub print_tab_content_oracledb {
    my ( $tab_number, $host_url, $server_url, $lpar_url, $item, $entitle, $detail_yes, $legend ) = @_;

    print "<div id=\"tabs-$tab_number\">\n";
    print "<table border=\"0\">\n";
    print "<tr>";

    print_item( $host_url, $server_url, $lpar_url, $item, "d", "", $entitle, $detail_yes, "norefr", "star", 1, $legend );
    print_item( $host_url, $server_url, $lpar_url, $item, "w", "", $entitle, $detail_yes, "norefr", "star", 1, $legend );
    print "</tr>\n<tr>\n";
    print_item( $host_url, $server_url, $lpar_url, $item, "m", "", $entitle, $detail_yes, "norefr", "star", 1, $legend );
    print_item( $host_url, $server_url, $lpar_url, $item, "y", "", $entitle, $detail_yes, "norefr", "star", 1, $legend );
    print "</tr></table>";
    print "</div>\n";
  }

  sub print_top10_to_table_ordb {
    my ( $period, $server_pool, $item_name ) = @_;
    my $topten_file_ordb = "$tmpdir/topten_oracledb.tmp";
    my $html_tab_header  = sub {
      my @columns = @_;
      my $result  = '';
      $result .= "<center>";
      $result .= "<table style=\"white-space: nowrap;\" class=\"tabconfig tablesorter \" data-sortby='1'>";
      $result .= "<thead><tr>";
      foreach my $item (@columns) {
        $result .= "<th class=\"sortable\">" . $item . "</th>";
      }
      $result .= "</tr></thead>";
      $result .= "<tbody>";
      return $result;
    };
    my $html_table_row = sub {
      my @cells  = @_;
      my $result = '';

      $result .= "<tr>";
      foreach my $cell (@cells) { $result .= "<td>" . $cell . "</td>"; }
      $result .= "</tr>";

      return $result;
    };

    # Table or create CSV file
    my $csv_file;
    if ( $item_name eq "load_cpu" ) {
      $csv_file = "ordb-load-cpu.csv";
    }
    elsif ( $item_name eq "session" ) {
      $csv_file = "ordb-session.csv";
    }
    elsif ( $item_name eq "io" ) {
      $csv_file = "ordb-io.csv";
    }
    elsif ( $item_name eq "data" ) {
      $csv_file = "ordb-data.csv";
    }
    if ( !$csv ) {
      print "<TD><TABLE class=\"tabconfig tablesorter\" data-sortby=\"1\">";
      if ( $period == 4 ) {    # last year
        print $html_tab_header->( 'Avrg', "IP", 'DB name', 'LPAR2RRD alias' );
      }
      else {
        print $html_tab_header->( 'Avrg', 'Max', "IP", 'DB name', 'LPAR2RRD alias' );
      }
    }
    else {
      print "Content-Disposition: attachment;filename=\"$csv_file\"\n\n";
      my $csv_header = "";
      if ( $period == 4 ) {    # last year
        $csv_header = "Avrg" . "$sep" . "IP" . "$sep" . "DB name" . "$sep" . "LPAR2RRD alias\n";
      }
      else {
        $csv_header = "Avrg" . "$sep" . "Max" . "$sep" . "IP" . "$sep" . "DB name" . "$sep" . "LPAR2RRD alias\n";
      }
      print "$csv_header";
    }
    my @topten;
    my @topten_not_sorted;
    my @topten_sorted;
    my $topten_limit = 0;
    my @top_values_avrg;
    my @top_values_max;
    if ( -f $topten_file_ordb ) {
      open( FH, " < $topten_file_ordb" ) || error( "Cannot open $topten_file_ordb: $!" . __FILE__ . ":" . __LINE__ );
      @topten = <FH>;
      close FH;
      if ( defined $ENV{TOPTEN} ) {
        $topten_limit = $ENV{TOPTEN};
      }
      $topten_limit = 50 if $topten_limit < 1;
      my @topten_server;
      if ( $item_name eq "load_cpu" ) {
        @topten_server = grep {/cpu_cores,/} @topten;
      }
      elsif ( $item_name eq "session" ) {
        @topten_server = grep {/session,/} @topten;
      }
      elsif ( $item_name eq "io" ) {
        @topten_server = grep {/^io,/} @topten;
      }
      elsif ( $item_name eq "data" ) {
        @topten_server = grep {/data,/} @topten;
      }
      @topten = @topten_server;
      foreach my $line (@topten) {
        chomp $line;
        my ( $item, $ip, $db_name, $db_alias );
        ( $item, $ip, $db_name, $db_alias, $top_values_avrg[1], $top_values_max[1], $top_values_avrg[2], $top_values_max[2], $top_values_avrg[3], $top_values_max[3], $top_values_avrg[4], $top_values_max[4] ) = split( ",", $line );
        $top_values_avrg[4] = 0 if !defined $top_values_avrg[4] or $top_values_avrg[4] eq "";    # no year value yet, new file
        $top_values_max[4]  = 0 if !defined $top_values_max[4]  or $top_values_max[4] eq "";     # no year value yet, new file
        if ( $top_values_avrg[1] == 0 && $top_values_max[1] == 0 && $top_values_avrg[2] == 0 && $top_values_max[2] == 0 && $top_values_avrg[3] == 0 && $top_values_max[3] == 0 && $top_values_avrg[4] == 0 && $top_values_max[4] == 0 ) { next; }
        push @topten_not_sorted, "$item,$top_values_avrg[$period],$top_values_max[$period],$ip,$db_name,$db_alias\n";
      }
      {
        no warnings;
        @topten_sorted = sort { $b <=> $a } @topten_not_sorted;
      }
    }
    my @topten_sorted_load_cpu;
    {
      no warnings;
      @topten_sorted_load_cpu = sort {
        my @b = split( /,/, $b );
        my @a = split( /,/, $a );

        #print "$b[4] --- $a[4]\n";
        $b[1] <=> $a[1]
      } @topten_sorted;
    }
    foreach my $line1 (@topten_sorted_load_cpu) {
      my ( $item_a, $load_cpu, $load_peak, $ip, $db_name, $db_alias );
      ( $item_a, $load_cpu, $load_peak, $ip, $db_name, $db_alias ) = split( ",", $line1 );
      if ( !$csv ) {
        if ( $period == 4 ) {    # last year
          print $html_table_row->( $load_cpu, $ip, $db_name, $db_alias );
        }
        else {
          print $html_table_row->( $load_cpu, $load_peak, $ip, $db_name, $db_alias );
        }
      }
      else {
        if ( $period == 4 ) {    # last year
          print "$load_cpu" . "$sep" . "$ip" . "$sep" . "$db_name" . "$sep" . "$db_alias";
        }
        else {
          print "$load_cpu" . "$sep" . "$load_peak" . "$sep" . "$ip" . "$sep" . "$db_name" . "$sep" . "$db_alias";
        }
      }
    }
    if ( !$csv ) {
      print "</TABLE></TD>";
    }
    return 1;
  }
}

if ($postgres) {
  my $mapping;
  $server_url = "$params{id}";
  $host_url   = "PostgreSQL";
  $lpar_url   = $params{type};
  print "<CENTER>";

  # get tabs
  my @tabs  = @{ PostgresMenu::get_tabs( $params{type} ) };
  my @items = ();

  $tab_number = 1;
  if (@tabs) {
    print "<div id=\"tabs\">\n";
    print "<ul>\n";

    foreach my $tab_header (@tabs) {
      while ( my ( $tab_type, $tab_label ) = each %$tab_header ) {
        print "  <li class=\"$tab_type\"><a href=\"#tabs-$tab_number\">$tab_label</a></li>\n";
        $tab_number++;
        push @items, "postgres_$lpar_url\_$tab_type";
      }
    }

    print "</ul>\n";
  }
  if ( $params{type} =~ m/^topten_postgres$/ ) {
    ############## LOAD TOPTEN FILE #####################
    my $topten_file_postgres = "$tmpdir/topten_postgresql.tmp";
    my $last_update          = localtime( ( stat($topten_file_postgres) )[9] );
    #####################################################
    my $server_pool = "";

    # last day
    print "<div id=\"tabs-1\">\n";
    print "<table align=\"center\" summary=\"Graphs\">\n";
    print "<tr><th align=center>Blocks read<a class=\"csvfloat\" href=\"/lpar2rrd-cgi/top10_csv.sh?LPAR=$server_pool&host=CSV&type=POSTGRES&table=topten&item=read_blocks&period=1\" title=\"BLOCKS READ CSV\"><img src=\"css/images/csv.gif\"></a></th><th align=center>Tuples returned<a class=\"csvfloat\" href=\"/lpar2rrd-cgi/top10_csv.sh?LPAR=$server_pool&host=CSV&type=POSTGRES&table=topten&item=tuples_return&period=1\" title=\"TUPLES RETURNED CSV\"><img src=\"css/images/csv.gif\"></a></th><th align=center>Sessions active<a class=\"csvfloat\" href=\"/lpar2rrd-cgi/top10_csv.sh?LPAR=$server_pool&host=CSV&type=POSTGRES&table=topten&item=session_active&period=1\" title=\"SESSIONS ACTIVE CSV\"><img src=\"css/images/csv.gif\"></a></th></tr>";
    print "<tr style=\"vertical-align:top\">";
    print_top10_to_table_postgres( "1", "$server_pool", "read_blocks" );
    print_top10_to_table_postgres( "1", "$server_pool", "tuples_return" );
    print_top10_to_table_postgres( "1", "$server_pool", "session_active" );
    print "</tr>";
    print "</table>";
    print "<tfoot><tr><td colspan=\"6\">Last update time: $last_update</td></tr></tfoot>";
    print "</div>\n";

    # last week
    print "<div id=\"tabs-2\">\n";
    print "<table align=\"center\" summary=\"Graphs\">\n";
    print "<tr><th align=center>Blocks read<a class=\"csvfloat\" href=\"/lpar2rrd-cgi/top10_csv.sh?LPAR=$server_pool&host=CSV&type=POSTGRES&table=topten&item=read_blocks&period=2\" title=\"BLOCKS READ CSV\"><img src=\"css/images/csv.gif\"></a></th><th align=center>Tuples returned<a class=\"csvfloat\" href=\"/lpar2rrd-cgi/top10_csv.sh?LPAR=$server_pool&host=CSV&type=POSTGRES&table=topten&item=tuples_return&period=2\" title=\"TUPLES RETURNED CSV\"><img src=\"css/images/csv.gif\"></a></th><th align=center>Sessions active<a class=\"csvfloat\" href=\"/lpar2rrd-cgi/top10_csv.sh?LPAR=$server_pool&host=CSV&type=POSTGRES&table=topten&item=session_active&period=2\" title=\"SESSIONS ACTIVE CSV\"><img src=\"css/images/csv.gif\"></a></th></tr>";
    print "<tr style=\"vertical-align:top\">";
    print_top10_to_table_postgres( "2", "$server_pool", "read_blocks" );
    print_top10_to_table_postgres( "2", "$server_pool", "tuples_return" );
    print_top10_to_table_postgres( "2", "$server_pool", "session_active" );
    print "</tr>";
    print "</table>";
    print "<tfoot><tr><td colspan=\"6\">Last update time: $last_update</td></tr></tfoot>";
    print "</div>\n";

    # last month
    print "<div id=\"tabs-3\">\n";
    print "<table align=\"center\" summary=\"Graphs\">\n";
    print "<tr><th align=center>Blocks read<a class=\"csvfloat\" href=\"/lpar2rrd-cgi/top10_csv.sh?LPAR=$server_pool&host=CSV&type=POSTGRES&table=topten&item=read_blocks&period=3\" title=\"BLOCKS READ CSV\"><img src=\"css/images/csv.gif\"></a></th><th align=center>Tuples returned<a class=\"csvfloat\" href=\"/lpar2rrd-cgi/top10_csv.sh?LPAR=$server_pool&host=CSV&type=POSTGRES&table=topten&item=tuples_return&period=3\" title=\"TUPLES RETURNED CSV\"><img src=\"css/images/csv.gif\"></a></th><th align=center>Sessions active<a class=\"csvfloat\" href=\"/lpar2rrd-cgi/top10_csv.sh?LPAR=$server_pool&host=CSV&type=POSTGRES&table=topten&item=session_active&period=3\" title=\"SESSIONS ACTIVE CSV\"><img src=\"css/images/csv.gif\"></a></th></tr>";
    print "<tr style=\"vertical-align:top\">";
    print_top10_to_table_postgres( "3", "$server_pool", "read_blocks" );
    print_top10_to_table_postgres( "3", "$server_pool", "tuples_return" );
    print_top10_to_table_postgres( "3", "$server_pool", "session_active" );
    print "</tr>";
    print "</table>";
    print "<tfoot><tr><td colspan=\"6\">Last update time: $last_update</td></tr></tfoot>";
    print "</div>\n";

    # last year
    print "<div id=\"tabs-4\">\n";
    print "<table align=\"center\" summary=\"Graphs\">\n";
    print "<tr><th align=center>Blocks read<a class=\"csvfloat\" href=\"/lpar2rrd-cgi/top10_csv.sh?LPAR=$server_pool&host=CSV&type=POSTGRES&table=topten&item=read_blocks&period=4\" title=\"BLOCKS READ CSV\"><img src=\"css/images/csv.gif\"></a></th><th align=center>Tuples returned<a class=\"csvfloat\" href=\"/lpar2rrd-cgi/top10_csv.sh?LPAR=$server_pool&host=CSV&type=POSTGRES&table=topten&item=tuples_return&period=4\" title=\"TUPLES RETURNED CSV\"><img src=\"css/images/csv.gif\"></a></th><th align=center>Sessions active<a class=\"csvfloat\" href=\"/lpar2rrd-cgi/top10_csv.sh?LPAR=$server_pool&host=CSV&type=POSTGRES&table=topten&item=session_active&period=4\" title=\"SESSIONS ACTIVE CSV\"><img src=\"css/images/csv.gif\"></a></th></tr>";
    print "<tr style=\"vertical-align:top\">";
    print_top10_to_table_postgres( "4", "$server_pool", "read_blocks" );
    print_top10_to_table_postgres( "4", "$server_pool", "tuples_return" );
    print_top10_to_table_postgres( "4", "$server_pool", "session_active" );
    print "</tr>";
    print "</table>";
    print "<tfoot><tr><td colspan=\"6\">Last update time: $last_update</td></tr></tfoot>";
    print "</div>\n";

  }
  else {
    for ( $tab_number = 1; $tab_number <= $#items + 1; $tab_number++ ) {
      if ( $lpar_url =~ /configuration/ ) {
        my $hst = PostgresDataWrapper::get_alias($server_url);

        my @conf_files = @{ PostgresDataWrapper::conf_files( $wrkdir, $lpar_url, $hst, $server_url ) };
        my @file;
        my $conf_file = $conf_files[ $tab_number - 1 ];

        if ( $conf_file eq " " ) {
          my $pstgr_item = $items[ $tab_number - 1 ];
          my $legend     = 'nolegend';

          print_tab_content_postgres(
            $tab_number, $host_url, $server_url, $lpar_url, $pstgr_item, $entitle,
            $detail_yes, $legend
          );
        }

        if ( -f $conf_file ) {
          open( CFGH, '<', $conf_file ) || Xorux_lib::error( "Couldn't open file $conf_file $!" . __FILE__ . ":" . __LINE__ );
          @file = <CFGH>;
          close(CFGH);
        }

        print "<div id=\"tabs-$tab_number\">\n";

        if ( scalar @file ) {
          print @file;
        }
        else {
          unless ( $conf_file eq " " ) {
            print "<p>Configuration is generated during first load each day.</p>";
          }
        }

        print "</div>\n";
      }
      else {
        my $pstgr_item = $items[ $tab_number - 1 ];
        my $legend     = "legend";
        $legend = 'nolegend';
        print_tab_content_postgres(
          $tab_number, $host_url, $server_url, $lpar_url, $pstgr_item, $entitle,
          $detail_yes, $legend
        );
      }
    }
  }

  sub print_tab_content_postgres {
    my ( $tab_number, $host_url, $server_url, $lpar_url, $item, $entitle, $detail_yes, $legend ) = @_;

    print "<div id=\"tabs-$tab_number\">\n";
    print "<table border=\"0\">\n";
    print "<tr>";

    print_item( $host_url, $server_url, $lpar_url, $item, "d", "", $entitle, $detail_yes, "norefr", "star", 1, $legend );
    print_item( $host_url, $server_url, $lpar_url, $item, "w", "", $entitle, $detail_yes, "norefr", "star", 1, $legend );
    print "</tr>\n<tr>\n";
    print_item( $host_url, $server_url, $lpar_url, $item, "m", "", $entitle, $detail_yes, "norefr", "star", 1, $legend );
    print_item( $host_url, $server_url, $lpar_url, $item, "y", "", $entitle, $detail_yes, "norefr", "star", 1, $legend );
    print "</tr></table>";
    print "</div>\n";
  }

  sub print_top10_to_table_postgres {
    my ( $period, $server_pool, $item_name ) = @_;
    my $topten_file_postgres = "$tmpdir/topten_postgresql.tmp";
    my $html_tab_header      = sub {
      my @columns = @_;
      my $result  = '';
      $result .= "<center>";
      $result .= "<table style=\"white-space: nowrap;\" class=\"tabconfig tablesorter \" data-sortby='1'>";
      $result .= "<thead><tr>";
      foreach my $item (@columns) {
        $result .= "<th class=\"sortable\">" . $item . "</th>";
      }
      $result .= "</tr></thead>";
      $result .= "<tbody>";
      return $result;
    };
    my $html_table_row = sub {
      my @cells  = @_;
      my $result = '';

      $result .= "<tr>";
      foreach my $cell (@cells) { $result .= "<td>" . $cell . "</td>"; }
      $result .= "</tr>";

      return $result;
    };

    # Table or create CSV file
    my $csv_file;
    if ( $item_name eq "read_blocks" ) {
      $csv_file = "postgres-read-blocks.csv";
    }
    elsif ( $item_name eq "tuples_return" ) {
      $csv_file = "postgres-tuples-return.csv";
    }
    elsif ( $item_name eq "session_active" ) {
      $csv_file = "postgres-session-active.csv";
    }
    if ( !$csv ) {
      print "<TD><TABLE class=\"tabconfig tablesorter\" data-sortby=\"1\">";
      if ( $period == 4 ) {    # last year
        print $html_tab_header->( 'Avrg', "Server", 'DB name' );
      }
      else {
        print $html_tab_header->( 'Avrg', 'Max', "Server", 'DB name' );
      }
    }
    else {
      print "Content-Disposition: attachment;filename=\"$csv_file\"\n\n";
      my $csv_header = "";
      if ( $period == 4 ) {    # last year
        $csv_header = "Avrg" . "$sep" . "Server" . "$sep" . "DB name\n";
      }
      else {
        $csv_header = "Avrg" . "$sep" . "Max" . "$sep" . "Server" . "$sep" . "DB name\n";
      }
      print "$csv_header";
    }
    my @topten;
    my @topten_not_sorted;
    my @topten_sorted;
    my $topten_limit = 0;
    my @top_values_avrg;
    my @top_values_max;
    if ( -f $topten_file_postgres ) {
      open( FH, " < $topten_file_postgres" ) || error( "Cannot open $topten_file_postgres: $!" . __FILE__ . ":" . __LINE__ );
      @topten = <FH>;
      close FH;
      if ( defined $ENV{TOPTEN} ) {
        $topten_limit = $ENV{TOPTEN};
      }
      $topten_limit = 50 if $topten_limit < 1;
      my @topten_server;
      if ( $item_name eq "read_blocks" ) {
        @topten_server = grep {/read_blocks,/} @topten;
      }
      elsif ( $item_name eq "tuples_return" ) {
        @topten_server = grep {/tuples_return,/} @topten;
      }
      elsif ( $item_name eq "session_active" ) {
        @topten_server = grep {/session_active,/} @topten;
      }
      @topten = @topten_server;
      foreach my $line (@topten) {
        chomp $line;
        my ( $item, $vm_name, $location );
        ( $item, $vm_name, $location, $top_values_avrg[1], $top_values_max[1], $top_values_avrg[2], $top_values_max[2], $top_values_avrg[3], $top_values_max[3], $top_values_avrg[4], $top_values_max[4] ) = split( ",", $line );
        $top_values_avrg[4] = 0 if !defined $top_values_avrg[4] or $top_values_avrg[4] eq "";    # no year value yet, new file
        $top_values_max[4]  = 0 if !defined $top_values_max[4]  or $top_values_max[4] eq "";     # no year value yet, new file
        if ( $top_values_avrg[1] == 0 && $top_values_max[1] == 0 && $top_values_avrg[2] == 0 && $top_values_max[2] == 0 && $top_values_avrg[3] == 0 && $top_values_max[3] == 0 && $top_values_avrg[4] == 0 && $top_values_max[4] == 0 ) { next; }
        push @topten_not_sorted, "$item,$top_values_avrg[$period],$top_values_max[$period],$vm_name,$location\n";
      }
      {
        no warnings;
        @topten_sorted = sort { $b <=> $a } @topten_not_sorted;
      }
    }
    my @topten_sorted_load_cpu;
    {
      no warnings;
      @topten_sorted_load_cpu = sort {
        my @b = split( /,/, $b );
        my @a = split( /,/, $a );

        #print "$b[4] --- $a[4]\n";
        $b[1] <=> $a[1]
      } @topten_sorted;
    }
    foreach my $line1 (@topten_sorted_load_cpu) {
      my ( $item_a, $load_cpu, $load_peak, $vm_name, $location );
      ( $item_a, $load_cpu, $load_peak, $vm_name, $location ) = split( ",", $line1 );

      #print STDERR"$item_a, $load_cpu, $load_peak, $vm_name, $uuid\n";
      if ( !$csv ) {
        if ( $period == 4 ) {    # last year
          print $html_table_row->( $load_cpu, $vm_name, $location );
        }
        else {
          print $html_table_row->( $load_cpu, $load_peak, $vm_name, $location );
        }
      }
      else {
        if ( $period == 4 ) {    # last year
          print "$load_cpu" . "$sep" . "$vm_name" . "$sep" . "$location";
        }
        else {
          print "$load_cpu" . "$sep" . "$load_peak" . "$sep" . "$vm_name" . "$sep" . "$location";
        }
      }
    }
    if ( !$csv ) {
      print "</TABLE></TD>";
    }
    return 1;
  }

}

if ($powercmc) {
  my $mapping;

  # GLOBAL: $server_url, $host_url, $lpar_url
  # LOCAL, implementation structure
  #         %console_section_id_name
  # LOCAL, situation specific:
  #         %console_section_id_name

  #------------------------------------------------------------------------------
  #print Dumper \%params;
  # $VAR1 = { 'console' => 'cm_console_2', '_' => '1684392238386', 'id' => '0254', 'platform' => 'PowerCMC', 'type' => 'pep2_pool' };

  #print "<br>  ITEM:: host=$host_url&server=$server_url&lpar=$lpar_url&item=$item&detail=1&none=none <br>";
  # ITEM:: host=&server=&lpar=&item=powercmc&detail=1&none=none

  my $filename = "${wrkdir}/PEP2/console_section_id_name.json";
  my $json;
  if ( defined $params{id} ) {
    $server_url = "$params{id}";
  }
  else {
    $server_url = "";
  }
  $host_url = "PowerCMC";
  $lpar_url = $params{type};

  my $type_lpar = $params{type};

  # ADD
  my $page_id   = $params{id};
  
  my $id_server = $params{id};
  my $console_name = $params{console};

  my $parse_delimiter = '____';

  if ("$type_lpar" eq 'pep2_cmc_overview'){
    $console_name = $params{id};
  }
  if (defined $page_id){
    if ($page_id =~ /^(.*)$parse_delimiter(.*)$/){
      $console_name = $2;
      $id_server    = $1;
    }
  }

  # FOR NOW: type <-> section translator:
  my %type_section = (
    "pep2_tags"   => "Tags",
    "pep2_pool"   => "Pools",
    "pep2_system" => "Systems"

  );

  my $section;

  if ( defined $type_section{$type_lpar} ) {
    $section = $type_section{$type_lpar};
  }
  else {
    #print "Undefined section.";
    $section = "";
  }

  # NOTE: List of module-calls:
  # %console_section_id_name = PowercmcDataWrapper::console_structure($wrkdir);
  # my @tabs  = @{ Db2Menu::get_tabs( $params{type} ) };

  # CONSOLE STRUCTURE
  my %console_section_id_name;

  # %console_section_id_name = PowercmcDataWrapper::console_structure($wrkdir);

  #----------------------------------------------------------------
  # TAB DEFINITION AND PRINT
  #----------------------------------------------------------------
  # print Dumper @tabs;
  # $VAR1 = { '_cmc_system' => 'System CPU', '_cmc_pools_c' => 'CPU', '_cmc_pools' => 'Memory' };
  #----------------------------------------------------------------
  my @tabs = @{ PowercmcMenu::get_tabs( $params{type} ) };

  $tab_number = 1;

  print "<CENTER>";

  if (@tabs) {
    print "<div id=\"tabs\">\n";
    print "<ul>\n";

    foreach my $tab_header (@tabs) {
      while ( my ( $tab_type, $tab_label ) = each %$tab_header ) {
        print "  <li class=\"$tab_type\"><a href=\"#tabs-$tab_number\">$tab_label</a></li>\n";
        $tab_number++;
      }
    }

    print "</ul>\n";
  }

  #----------------------------------------------------------------
  # MAKE ITEMS
  #----------------------------------------------------------------
  # NOTE:  global variable $item
  #        local @items
  #        local $item2use

  my @use_items = ();

  if (@tabs) {
    foreach my $tab_header (@tabs) {
      while ( my ( $tab_type, $tab_label ) = each %$tab_header ) {
        push @use_items, "powercmc_${type_lpar}_${tab_type}";
      }
    }
  }

  #----------------------------------------------------------------
  # CONSOLE -> Pools/Systems/Partitions/HMC
  #my %console_section_id_name;
  #----------------------------------------------------------------
  for ( $tab_number = 1; $tab_number <= $#use_items + 1; $tab_number++ ) {
    my $item2use = $use_items[ $tab_number - 1 ];

    if ( $type_lpar =~ /overview/ ) {
      cmc_overview_page();
    }
    elsif ( $type_lpar =~ /tags/ ) {
      print "Tags";
    }
    elsif ( $type_lpar =~ /total/ ) {
      print_tab_content_cmc(
        $tab_number, $console_name, $host_url, $console_name, $type_lpar, $item, $entitle,
        $detail_yes, 'nolegend'
      );
    }
    else {
      # quick solution to undef if pep2_all: !!! change
      if (! defined $id_server){
        $id_server = "";
      }
      if (! defined $console_name){
        $console_name  = "";
      }
      print_tab_content_cmc(
        $tab_number, $console_name, $host_url, "${console_name}___$id_server", $type_lpar, $item2use, $entitle,
        $detail_yes, 'nolegend'
      );
    }
  }

  #----------------------------------------------------------------
  #print "<br> tab_number $tab_number, host_url $host_url ,server_url $server_url, type_lpar $lpar_url,item  powercmc_total__$console_name,entitle $entitle,       detyes $detail_yes,legend $legend <br>";
  # tab_number 1, host_url PowerCMC ,server_url 0254, lpar_url pep2_pool,item powercmc_total__cm_console_2,entitle 0, detyes 1
  #----------------------------------------------------------------
  sub cmc_overview_page {
    # uses out of scope variable: $console_name
    %console_section_id_name = PowercmcDataWrapper::console_structure($wrkdir);
    if ( !%console_section_id_name ) {
      print ' <div id="tabs-1"> ';
      print 'IBM Power Enterprise Pools 2.0 are not configured.<br><a href="https://lpar2rrd.com/IBM-Power-Systems-performance-monitoring-installation.php?5.0#PEP2">Installation docu</a><br>';
      print " </div> </div> ";
    }

    my @console_list = keys %console_section_id_name;

    # checks if consoles match: TODO: inspect if this problem remains
    if ( !defined $console_name ) {

      #------------------------------------------------------------------
      # GLOBAL OVERVIEW
      #------------------------------------------------------------------
      #print "</CENTER>\n";
      print ' <div id="tabs-1"> ';
      
      my $final_print;
      
      for my $console ( sort @console_list ) {
        
        # TITLE
        my $console_alias = "$console_section_id_name{$console}{Alias}";
        my $print_string  = "<h4> Console: $console_alias ($console)</h4>\n";
        #print "$print_string";
        $final_print .= $print_string;

        # TABLE
        my %console_data = %{ $console_section_id_name{$console} };
        my ( $ref_table_keys, $ref_table_header, $ref_table_body ) = PowercmcDataWrapper::table_pep_configuration($console);
        my $table = PowercmcDataWrapper::make_html_table( $ref_table_keys, $ref_table_header, $ref_table_body, '-1' );
        #print $table;
        $final_print .= $table;      

      }
      print $final_print;
      print " </div> </div> ";
    }
    elsif ( defined $console_section_id_name{$console_name} ) {
      #print "</CENTER>\n";

      # TITLE
      my $console_alias = "$console_section_id_name{$console_name}{Alias}";

      print ' <div id="tabs-1"> ';
      print "\n";
      #my $print_string = "<h4> Console: $console_alias ($console_name)</h4>\n";
      #print "$print_string";

      # TABLE
      my %console_data = %{ $console_section_id_name{$console_name} };

      #my ($ref_table_keys, $ref_table_header, $ref_table_body) = PowercmcDataWrapper::table_data_console_overview($console_name);
      my ( $ref_table_keys, $ref_table_header, $ref_table_body ) = PowercmcDataWrapper::table_data_console_overview($console_name);
      my $table = PowercmcDataWrapper::make_html_table( $ref_table_keys, $ref_table_header, $ref_table_body, '-2' );
      print $table;
      print " </div> </div>";
    }
    else {
      print " CONSOLE DOES NOT MATCH ";
    }

  }
  #---------------------------------------------------------------------------------------------------------

  sub print_tab_content_cmc {
    my ( $tab_number, $console_name, $host_url, $server_url, $lpar_url, $item, $entitle, $detail_yes, $legend ) = @_;

    #my ( $tab_number, $host_url, $server_url, $lpar_url, $item, $entitle, $detail_yes, $legend ) = @_;
    # seemingly unused: tab_number
    #print "<br> host=$host_url&server=$server_url&lpar=$lpar_url&item=$item&entitle=$entitle&none=none <br>";
    print "<div id=\"tabs-$tab_number\">\n";

    if ( $item =~ /cmc_system/ && $section eq "Pools" ) {
      %console_section_id_name = PowercmcDataWrapper::console_structure($wrkdir);

      if ( !$console_section_id_name{$console_name}{$section}{$id_server}{Systems} ) {
        print "<br><br> Pool has no tagged systems. ";
        print '<br><a href="https://lpar2rrd.com/IBM-Power-Systems-performance-monitoring-installation.php?5.0#PEP2">Installation docu</a><br>';
      }
      else {
        #print "Graphs contain only tagged systems in pools.";

        print "<table border=\"0\">\n";
        print "<tr>";

        print_item( $host_url, $server_url, $lpar_url, $item, "d", "", $entitle, $detail_yes, "norefr", "star", 1, $legend );
        print_item( $host_url, $server_url, $lpar_url, $item, "w", "", $entitle, $detail_yes, "norefr", "star", 1, $legend );
        print "</tr>\n<tr>\n";
        print_item( $host_url, $server_url, $lpar_url, $item, "m", "", $entitle, $detail_yes, "norefr", "star", 1, $legend );
        print_item( $host_url, $server_url, $lpar_url, $item, "y", "", $entitle, $detail_yes, "norefr", "star", 1, $legend );
        print "</tr></table>";

      }

    }
    else {

      print "<table border=\"0\">\n";
      print "<tr>";

      print_item( $host_url, $server_url, $lpar_url, $item, "d", "", $entitle, $detail_yes, "norefr", "star", 1, $legend );
      print_item( $host_url, $server_url, $lpar_url, $item, "w", "", $entitle, $detail_yes, "norefr", "star", 1, $legend );
      print "</tr>\n<tr>\n";
      print_item( $host_url, $server_url, $lpar_url, $item, "m", "", $entitle, $detail_yes, "norefr", "star", 1, $legend );
      print_item( $host_url, $server_url, $lpar_url, $item, "y", "", $entitle, $detail_yes, "norefr", "star", 1, $legend );
      print "</tr></table>";

    }

    print "</div>\n";
  }
}

if ($db2) {
  my $mapping;

  $server_url = "$params{id}";
  $host_url   = "Db2";
  $lpar_url   = $params{type};
  print "<CENTER>";

  # get tabs
  my @tabs  = @{ Db2Menu::get_tabs( $params{type} ) };
  my @items = ();

  $tab_number = 1;
  if (@tabs) {
    print "<div id=\"tabs\">\n";
    print "<ul>\n";

    foreach my $tab_header (@tabs) {
      while ( my ( $tab_type, $tab_label ) = each %$tab_header ) {
        print "  <li class=\"$tab_type\"><a href=\"#tabs-$tab_number\">$tab_label</a></li>\n";
        $tab_number++;
        push @items, "db2_$lpar_url\_$tab_type";
      }
    }

    print "</ul>\n";
  }

  for ( $tab_number = 1; $tab_number <= $#items + 1; $tab_number++ ) {
    if ( $lpar_url =~ /configuration/ ) {
      my $hst        = Db2DataWrapper::get_alias( $server_url, "_dbs" );
      my @conf_files = @{ Db2DataWrapper::conf_files( $wrkdir, $lpar_url, $hst, $server_url ) };
      my @file;
      my $conf_file = $conf_files[ $tab_number - 1 ];

      if ( $conf_file eq " " ) {
        my $pstgr_item = $items[ $tab_number - 1 ];
        my $legend     = 'nolegend';

        print_tab_content_db2(
          $tab_number, $host_url, $server_url, $lpar_url, $pstgr_item, $entitle,
          $detail_yes, $legend
        );
      }

      if ( -f $conf_file ) {
        open( CFGH, '<', $conf_file ) || Xorux_lib::error( "Couldn't open file $conf_file $!" . __FILE__ . ":" . __LINE__ );
        @file = <CFGH>;
        close(CFGH);
      }

      print "<div id=\"tabs-$tab_number\">\n";

      if ( scalar @file ) {
        print @file;
      }
      else {
        unless ( $conf_file eq " " ) {
          print "<p>Configuration is generated during first load each day.</p>";
        }
      }

      print "</div>\n";
    }
    else {
      my $pstgr_item = $items[ $tab_number - 1 ];
      my $legend     = "legend";
      $legend = 'nolegend';
      print_tab_content_db2(
        $tab_number, $host_url, $server_url, $lpar_url, $pstgr_item, $entitle,
        $detail_yes, $legend
      );
    }
  }

  sub print_tab_content_db2 {
    my ( $tab_number, $host_url, $server_url, $lpar_url, $item, $entitle, $detail_yes, $legend ) = @_;

    print "<div id=\"tabs-$tab_number\">\n";
    print "<table border=\"0\">\n";
    print "<tr>";

    print_item( $host_url, $server_url, $lpar_url, $item, "d", "", $entitle, $detail_yes, "norefr", "star", 1, $legend );
    print_item( $host_url, $server_url, $lpar_url, $item, "w", "", $entitle, $detail_yes, "norefr", "star", 1, $legend );
    print "</tr>\n<tr>\n";
    print_item( $host_url, $server_url, $lpar_url, $item, "m", "", $entitle, $detail_yes, "norefr", "star", 1, $legend );
    print_item( $host_url, $server_url, $lpar_url, $item, "y", "", $entitle, $detail_yes, "norefr", "star", 1, $legend );
    print "</tr></table>";
    print "</div>\n";
  }
}

if ($sqlserver) {
  my $mapping;

  $server_url = "$params{id}";
  $host_url   = "SQLServer";
  $lpar_url   = $params{type};
  print "<CENTER>";

  # get tabs
  my @tabs  = @{ SQLServerMenu::get_tabs( $params{type} ) };
  my @items = ();

  $tab_number = 1;
  if (@tabs) {
    print "<div id=\"tabs\">\n";
    print "<ul>\n";

    foreach my $tab_header (@tabs) {
      while ( my ( $tab_type, $tab_label ) = each %$tab_header ) {
        print "  <li class=\"$tab_type\"><a href=\"#tabs-$tab_number\">$tab_label</a></li>\n";
        $tab_number++;
        push @items, "sqlserver_$lpar_url\_$tab_type";
      }
    }

    print "</ul>\n";
  }
  if ( $params{type} =~ m/^topten_microsql$/ ) {
    ############## LOAD TOPTEN FILE #####################
    my $topten_file_microsql = "$tmpdir/topten_microsql.tmp";
    my $last_update          = localtime( ( stat($topten_file_microsql) )[9] );
    #####################################################
    my $server_pool = "";

    # last day
    print "<div id=\"tabs-1\">\n";
    print "<table align=\"center\" summary=\"Graphs\">\n";
    print "<tr><th align=center>IOPS<a class=\"csvfloat\" href=\"/lpar2rrd-cgi/top10_csv.sh?LPAR=$server_pool&host=CSV&type=SQLSERVER&table=topten&item=iops&period=1\" title=\"LOAD CPU CSV\"><img src=\"css/images/csv.gif\"></a></th><th align=center>DATA in MB<a class=\"csvfloat\" href=\"/lpar2rrd-cgi/top10_csv.sh?LPAR=$server_pool&host=CSV&type=SQLSERVER&table=topten&item=data&period=1\" title=\"DATA CSV\"><img src=\"css/images/csv.gif\"></a></th><th align=center>User connections<a class=\"csvfloat\" href=\"/lpar2rrd-cgi/top10_csv.sh?LPAR=$server_pool&host=CSV&type=SQLSERVER&table=topten&item=user_connect&period=1\" title=\"USER CONNECTIONS CSV\"><img src=\"css/images/csv.gif\"></a></th></tr>";
    print "<tr style=\"vertical-align:top\">";
    print_top10_to_table_microsql( "1", "$server_pool", "iops" );
    print_top10_to_table_microsql( "1", "$server_pool", "data" );
    print_top10_to_table_microsql( "1", "$server_pool", "user_connect" );
    print "</tr>";
    print "</table>";
    print "<tfoot><tr><td colspan=\"6\">Last update time: $last_update</td></tr></tfoot>";
    print "</div>\n";

    # last week
    print "<div id=\"tabs-2\">\n";
    print "<table align=\"center\" summary=\"Graphs\">\n";
    print "<tr><th align=center>IOPS<a class=\"csvfloat\" href=\"/lpar2rrd-cgi/top10_csv.sh?LPAR=$server_pool&host=CSV&type=SQLSERVER&table=topten&item=iops&period=2\" title=\"LOAD CPU CSV\"><img src=\"css/images/csv.gif\"></a></th><th align=center>DATA in MB<a class=\"csvfloat\" href=\"/lpar2rrd-cgi/top10_csv.sh?LPAR=$server_pool&host=CSV&type=SQLSERVER&table=topten&item=data&period=2\" title=\"DATA CSV\"><img src=\"css/images/csv.gif\"></a></th><th align=center>User connections<a class=\"csvfloat\" href=\"/lpar2rrd-cgi/top10_csv.sh?LPAR=$server_pool&host=CSV&type=SQLSERVER&table=topten&item=user_connect&period=2\" title=\"USER CONNECTIONS CSV\"><img src=\"css/images/csv.gif\"></a></th></tr>";
    print "<tr style=\"vertical-align:top\">";
    print_top10_to_table_microsql( "2", "$server_pool", "iops" );
    print_top10_to_table_microsql( "2", "$server_pool", "data" );
    print_top10_to_table_microsql( "2", "$server_pool", "user_connect" );
    print "</tr>";
    print "</table>";
    print "<tfoot><tr><td colspan=\"6\">Last update time: $last_update</td></tr></tfoot>";
    print "</div>\n";

    # last month
    print "<div id=\"tabs-3\">\n";
    print "<table align=\"center\" summary=\"Graphs\">\n";
    print "<tr><th align=center>IOPS<a class=\"csvfloat\" href=\"/lpar2rrd-cgi/top10_csv.sh?LPAR=$server_pool&host=CSV&type=SQLSERVER&table=topten&item=iops&period=3\" title=\"LOAD CPU CSV\"><img src=\"css/images/csv.gif\"></a></th><th align=center>DATA in MB<a class=\"csvfloat\" href=\"/lpar2rrd-cgi/top10_csv.sh?LPAR=$server_pool&host=CSV&type=SQLSERVER&table=topten&item=data&period=3\" title=\"DATA CSV\"><img src=\"css/images/csv.gif\"></a></th><th align=center>User connections<a class=\"csvfloat\" href=\"/lpar2rrd-cgi/top10_csv.sh?LPAR=$server_pool&host=CSV&type=SQLSERVER&table=topten&item=user_connect&period=3\" title=\"USER CONNECTIONS CSV\"><img src=\"css/images/csv.gif\"></a></th></tr>";
    print "<tr style=\"vertical-align:top\">";
    print_top10_to_table_microsql( "3", "$server_pool", "iops" );
    print_top10_to_table_microsql( "3", "$server_pool", "data" );
    print_top10_to_table_microsql( "3", "$server_pool", "user_connect" );
    print "</tr>";
    print "</table>";
    print "<tfoot><tr><td colspan=\"6\">Last update time: $last_update</td></tr></tfoot>";
    print "</div>\n";

    # last year
    print "<div id=\"tabs-4\">\n";
    print "<table align=\"center\" summary=\"Graphs\">\n";
    print "<tr><th align=center>IOPS<a class=\"csvfloat\" href=\"/lpar2rrd-cgi/top10_csv.sh?LPAR=$server_pool&host=CSV&type=SQLSERVER&table=topten&item=iops&period=4\" title=\"LOAD CPU CSV\"><img src=\"css/images/csv.gif\"></a></th><th align=center>DATA in MB<a class=\"csvfloat\" href=\"/lpar2rrd-cgi/top10_csv.sh?LPAR=$server_pool&host=CSV&type=SQLSERVER&table=topten&item=data&period=4\" title=\"DATA CSV\"><img src=\"css/images/csv.gif\"></a></th><th align=center>User connections<a class=\"csvfloat\" href=\"/lpar2rrd-cgi/top10_csv.sh?LPAR=$server_pool&host=CSV&type=SQLSERVER&table=topten&item=user_connect&period=4\" title=\"USER CONNECTIONS CSV\"><img src=\"css/images/csv.gif\"></a></th></tr>";
    print "<tr style=\"vertical-align:top\">";
    print_top10_to_table_microsql( "4", "$server_pool", "iops" );
    print_top10_to_table_microsql( "4", "$server_pool", "data" );
    print_top10_to_table_microsql( "4", "$server_pool", "user_connect" );
    print "</tr>";
    print "</table>";
    print "<tfoot><tr><td colspan=\"6\">Last update time: $last_update</td></tr></tfoot>";
    print "</div>\n";

  }
  else {

    for ( $tab_number = 1; $tab_number <= $#items + 1; $tab_number++ ) {
      if ( $lpar_url =~ /configuration/ ) {
        my $hst = SQLServerDataWrapper::get_alias($server_url);

        my @conf_files = @{ SQLServerDataWrapper::conf_files( $wrkdir, $lpar_url, $hst, $server_url ) };
        my @file;
        my $conf_file = $conf_files[ $tab_number - 1 ];

        if ( $conf_file eq " " ) {
          my $pstgr_item = $items[ $tab_number - 1 ];
          my $legend     = 'nolegend';

          print_tab_content_sqlserver(
            $tab_number, $host_url, $server_url, $lpar_url, $pstgr_item, $entitle,
            $detail_yes, $legend
          );
        }

        if ( -f $conf_file ) {
          open( CFGH, '<', $conf_file ) || Xorux_lib::error( "Couldn't open file $conf_file $!" . __FILE__ . ":" . __LINE__ );
          @file = <CFGH>;
          close(CFGH);
        }

        print "<div id=\"tabs-$tab_number\">\n";

        if ( scalar @file ) {
          print @file;
        }
        else {
          unless ( $conf_file eq " " ) {
            print "<p>Configuration is generated during first load each day.</p>";
          }
        }

        print "</div>\n";
      }
      else {
        my $pstgr_item = $items[ $tab_number - 1 ];
        my $legend     = "legend";
        $legend = 'nolegend';
        print_tab_content_sqlserver(
          $tab_number, $host_url, $server_url, $lpar_url, $pstgr_item, $entitle,
          $detail_yes, $legend
        );
      }
    }
  }

  sub print_tab_content_sqlserver {
    my ( $tab_number, $host_url, $server_url, $lpar_url, $item, $entitle, $detail_yes, $legend ) = @_;

    print "<div id=\"tabs-$tab_number\">\n";
    print "<table border=\"0\">\n";
    print "<tr>";

    print_item( $host_url, $server_url, $lpar_url, $item, "d", "", $entitle, $detail_yes, "norefr", "star", 1, $legend );
    print_item( $host_url, $server_url, $lpar_url, $item, "w", "", $entitle, $detail_yes, "norefr", "star", 1, $legend );
    print "</tr>\n<tr>\n";
    print_item( $host_url, $server_url, $lpar_url, $item, "m", "", $entitle, $detail_yes, "norefr", "star", 1, $legend );
    print_item( $host_url, $server_url, $lpar_url, $item, "y", "", $entitle, $detail_yes, "norefr", "star", 1, $legend );
    print "</tr></table>";
    print "</div>\n";
  }

  sub print_top10_to_table_microsql {
    my ( $period, $server_pool, $item_name ) = @_;
    my $topten_file_microsql = "$tmpdir/topten_microsql.tmp";
    my $html_tab_header      = sub {
      my @columns = @_;
      my $result  = '';
      $result .= "<center>";
      $result .= "<table style=\"white-space: nowrap;\" class=\"tabconfig tablesorter \" data-sortby='1'>";
      $result .= "<thead><tr>";
      foreach my $item (@columns) {
        $result .= "<th class=\"sortable\">" . $item . "</th>";
      }
      $result .= "</tr></thead>";
      $result .= "<tbody>";
      return $result;
    };
    my $html_table_row = sub {
      my @cells  = @_;
      my $result = '';

      $result .= "<tr>";
      foreach my $cell (@cells) { $result .= "<td>" . $cell . "</td>"; }
      $result .= "</tr>";

      return $result;
    };

    # Table or create CSV file
    my $csv_file;
    if ( $item_name eq "iops" ) {
      $csv_file = "microsql-iops.csv";
    }
    elsif ( $item_name eq "data" ) {
      $csv_file = "microsql-data.csv";
    }
    elsif ( $item_name eq "user_connect" ) {
      $csv_file = "microsql-user-connect.csv";
    }
    if ( !$csv ) {
      print "<TD><TABLE class=\"tabconfig tablesorter\" data-sortby=\"1\">";
      if ( $period == 4 ) {    # last year
        print $html_tab_header->( 'Avrg', "Server", 'DB name' );
      }
      else {
        print $html_tab_header->( 'Avrg', 'Max', "Server", 'DB name' );
      }
    }
    else {
      print "Content-Disposition: attachment;filename=\"$csv_file\"\n\n";
      my $csv_header = "";
      if ( $period == 4 ) {    # last year
        $csv_header = "Avrg" . "$sep" . "Server" . "$sep" . "DB name\n";
      }
      else {
        $csv_header = "Avrg" . "$sep" . "Max" . "$sep" . "Server" . "$sep" . "DB name\n";
      }
      print "$csv_header";
    }
    my @topten;
    my @topten_not_sorted;
    my @topten_sorted;
    my $topten_limit = 0;
    my @top_values_avrg;
    my @top_values_max;
    if ( -f $topten_file_microsql ) {
      open( FH, " < $topten_file_microsql" ) || error( "Cannot open $topten_file_microsql: $!" . __FILE__ . ":" . __LINE__ );
      @topten = <FH>;
      close FH;
      if ( defined $ENV{TOPTEN} ) {
        $topten_limit = $ENV{TOPTEN};
      }
      $topten_limit = 50 if $topten_limit < 1;
      my @topten_server;
      if ( $item_name eq "iops" ) {
        @topten_server = grep {/iops,/} @topten;
      }
      elsif ( $item_name eq "data" ) {
        @topten_server = grep {/data,/} @topten;
      }
      elsif ( $item_name eq "user_connect" ) {
        @topten_server = grep {/user_connect,/} @topten;
      }
      @topten = @topten_server;
      foreach my $line (@topten) {
        chomp $line;
        my ( $item, $vm_name, $location );
        ( $item, $vm_name, $location, $top_values_avrg[1], $top_values_max[1], $top_values_avrg[2], $top_values_max[2], $top_values_avrg[3], $top_values_max[3], $top_values_avrg[4], $top_values_max[4] ) = split( ",", $line );
        $top_values_avrg[4] = 0 if !defined $top_values_avrg[4] or $top_values_avrg[4] eq "";    # no year value yet, new file
        $top_values_max[4]  = 0 if !defined $top_values_max[4]  or $top_values_max[4] eq "";     # no year value yet, new file
        if ( $top_values_avrg[1] == 0 && $top_values_max[1] == 0 && $top_values_avrg[2] == 0 && $top_values_max[2] == 0 && $top_values_avrg[3] == 0 && $top_values_max[3] == 0 && $top_values_avrg[4] == 0 && $top_values_max[4] == 0 ) { next; }
        push @topten_not_sorted, "$item,$top_values_avrg[$period],$top_values_max[$period],$vm_name,$location\n";
      }
      {
        no warnings;
        @topten_sorted = sort { $b <=> $a } @topten_not_sorted;
      }
    }
    my @topten_sorted_load_cpu;
    {
      no warnings;
      @topten_sorted_load_cpu = sort {
        my @b = split( /,/, $b );
        my @a = split( /,/, $a );

        #print "$b[4] --- $a[4]\n";
        $b[1] <=> $a[1]
      } @topten_sorted;
    }
    foreach my $line1 (@topten_sorted_load_cpu) {
      my ( $item_a, $load_cpu, $load_peak, $vm_name, $location );
      ( $item_a, $load_cpu, $load_peak, $vm_name, $location ) = split( ",", $line1 );

      #print STDERR"$item_a, $load_cpu, $load_peak, $vm_name, $uuid\n";
      if ( !$csv ) {
        if ( $period == 4 ) {    # last year
          print $html_table_row->( $load_cpu, $vm_name, $location );
        }
        else {
          print $html_table_row->( $load_cpu, $load_peak, $vm_name, $location );
        }
      }
      else {
        if ( $period == 4 ) {    # last year
          print "$load_cpu" . "$sep" . "$vm_name" . "$sep" . "$location";
        }
        else {
          print "$load_cpu" . "$sep" . "$load_peak" . "$sep" . "$vm_name" . "$sep" . "$location";
        }
      }
    }
    if ( !$csv ) {
      print "</TABLE></TD>";
    }
    return 1;
  }

}

if ($orvm) {
  my $mapping;
  my ( $code1, $linux_uuids ) = -f $agents_uuid_file ? Xorux_lib::read_json($agents_uuid_file) : ( 0, 0 );

  #print STDERR Dumper $linux_uuids;
  #print STDERR"===\n";
  #print STDERR Dumper $code1;
  #print STDERR"===\n";
  #print STDERR Dumper \%params;
  #print STDERR"===\n";
  $host_url   = 'OracleVM';
  $server_url = 'nope';
  $tab_number = 1;
  my $csv_config_serverpools = "orvm_serverpool.csv";
  my $csv_config_vms         = "orvm_vm.csv";
  my $lpar_agent_name        = "";

  if ( $params{type} eq 'vm' ) {
    $lpar_url = $params{id};
  }
  elsif ( $params{type} eq 'server' ) {
    $lpar_url = $params{id};
  }
  elsif ( $params{type} eq 'total_server' ) {
    $lpar_url = $params{id};
  }
  elsif ( $params{type} eq 'total_serverpools' ) {
    $lpar_url = $params{id};
  }
  elsif ( $params{type} eq 'configuration' ) {
    $lpar_url = $params{configuration};
  }
  elsif ( $params{type} eq 'topten_oraclevm' ) {
    $lpar_url = $params{topten_oraclevm};
  }

  print "<CENTER>";
  print "<CENTER>";

  # get tabs
  my @tabs  = @{ OracleVmMenu::get_tabs( $params{type} ) };
  my @items = ();

  #print STDERR Dumper \%params;
  #print STDERR Dumper @tabs;
  my $oraclevm_dir = "$basedir/data/OracleVM";

  $tab_number = 1;
  if (@tabs) {
    print "<div id=\"tabs\">\n";
    print "<ul>\n";
    foreach my $tab_header (@tabs) {
      while ( my ( $tab_type, $tab_label ) = each %$tab_header ) {
        my $vmorserver    = "";
        my $linux_vm_name = "none";
        ### LINUX VMs running under OracleVM
        if ( $tab_type =~ /oscpu|queue_cpu|^mem$|jobs|pg1|pg2|^lan$|^file_sys$/ && $params{type} =~ /^vm$/ ) {
          if ($code1) {
            for my $linux_uuid ( keys %{$linux_uuids} ) {
              chomp $linux_uuid;
              $lpar_agent_name = $linux_uuids->{$linux_uuid};
              $linux_uuid =~ s/-//g;
              $linux_uuid = lc $linux_uuid;
              if ( $linux_uuid eq $lpar_url ) {
                $linux_vm_name = $lpar_agent_name;
                $linux_vm_name = urlencode($linux_vm_name);
                last;
              }
            }
          }
          if ( $linux_vm_name =~ /none/ && $params{type} =~ /^vm$/ ) { next; }
        }
        ###
        if ( $tab_type =~ /disk_used/ && $params{type} =~ /^server|^vm$/ ) {    #### Server and VM disk tab
          if ( $params{type} =~ /total_server|server/ ) {
            $vmorserver = "server";
          }
          else {
            $vmorserver = "vm";
          }
          opendir( DIR1, "$oraclevm_dir/$vmorserver/$lpar_url" );
          my @uuids_disk1 = grep /^disk-/, readdir(DIR1);
          if ( !@uuids_disk1 ) { next; }
          print "  <li class=\"$tab_type\"><a href=\"#tabs-$tab_number\">$tab_label</a></li>\n";
          $tab_number++;

          #print "ovm_$params{type}\_$tab_type\n";
          push @items, "ovm_$params{type}\_$tab_type";
        }
        if ( $tab_type =~ /net_used/ && $params{type} =~ /^server$|^vm$/ ) {    #### Server and VM net tab
          if ( $params{type} =~ /total_server|server/ ) {
            $vmorserver = "server";
          }
          else {
            $vmorserver = "vm";
          }
          opendir( DIR2, "$oraclevm_dir/$vmorserver/$lpar_url" );
          my @uuids_disk2 = grep /^lan-/, readdir(DIR2);
          if ( !@uuids_disk2 ) { next; }
          print "  <li class=\"$tab_type\"><a href=\"#tabs-$tab_number\">$tab_label</a></li>\n";
          $tab_number++;

          #print "ovm_$params{type}\_$tab_type\n";
          push @items, "ovm_$params{type}\_$tab_type";
        }
        if ( $tab_type =~ /disk_used/ && $params{type} =~ /^total_server$/ ) {
          my $mapping_server_pool = OracleVmDataWrapper::get_conf_section('arch-server_pool');
          my @servers             = @{ OracleVmDataWrapper::get_items( { item_type => 'server' } ) };
          my $uuids_disk3         = "";
          foreach my $server_uuid (@servers) {

            #print STDERR"$server_uuid--$lpar_url\n";
            if ( grep( /$server_uuid/, @{ $mapping_server_pool->{$lpar_url} } ) ) {
              opendir( DIR3, "$oraclevm_dir/server/$server_uuid" );
              $uuids_disk3 = grep /^disk-/, readdir(DIR3);
              if ( $uuids_disk3 == 0 ) { next; }
            }
          }
          if ( $uuids_disk3 == 0 ) { next; }
          print "  <li class=\"$tab_type\"><a href=\"#tabs-$tab_number\">$tab_label</a></li>\n";
          $tab_number++;
          push @items, "ovm_$params{type}\_$tab_type";
        }
        if ( $tab_type =~ /net_used/ && $params{type} =~ /^total_server$/ ) {
          my $mapping_server_pool = OracleVmDataWrapper::get_conf_section('arch-server_pool');
          my @servers             = @{ OracleVmDataWrapper::get_items( { item_type => 'server' } ) };
          foreach my $server_uuid (@servers) {
            if ( grep( /$server_uuid/, @{ $mapping_server_pool->{$lpar_url} } ) ) {
              opendir( DIR4, "$oraclevm_dir/server/$server_uuid" );
              my $uuids_disk4 = grep /^lan-/, readdir(DIR4);
              if ( $uuids_disk4 == 0 ) { next; }
            }
          }
          print "  <li class=\"$tab_type\"><a href=\"#tabs-$tab_number\">$tab_label</a></li>\n";
          $tab_number++;

          #print "ovm_$params{type}\_$tab_type\n";
          push @items, "ovm_$params{type}\_$tab_type";
        }
        if ( $tab_type !~ /net_used|disk_used/ && $params{type} =~ /^total_serverpools$|^server$|^vm$|^total_server$|configuration|^topten_oraclevm/ ) {
          print "  <li class=\"$tab_type\"><a href=\"#tabs-$tab_number\">$tab_label</a></li>\n";
          $tab_number++;

          #print "ovm_$params{type}\_$tab_type\n";
          push @items, "ovm_$params{type}\_$tab_type";
        }
        if ( $tab_type =~ /net_used|disk_used/ && $params{type} =~ /^total_serverpools$/ ) {
          print "  <li class=\"$tab_type\"><a href=\"#tabs-$tab_number\">$tab_label</a></li>\n";
          $tab_number++;

          #print "ovm_$params{type}\_$tab_type\n";
          push @items, "ovm_$params{type}\_$tab_type";
        }
      }
    }

    print "</ul>\n";
  }

  my $legend = ( $params{type} =~ m/aggr/ ) ? "nolegend" : "legend";

  if ( $params{type} =~ m/^vm$/ ) {

    #my @vm_items = ("ovm_vm_cpu_core","ovm_vm_cpu_percent","ovm_vm_mem","ovm_vm_aggr_net","ovm_vm_aggr_disk_used");
    my @vm_items      = ( "ovm_vm_cpu_core", "ovm_vm_cpu_percent", "ovm_vm_mem", "ovm_vm_aggr_net", "ovm_vm_aggr_disk_used", "oscpu", "queue_cpu", "jobs", "mem", "pg1", "pg2", "lan", "file_sys" );
    my $linux_vm_name = "none";
    my $no_hmc        = "no_hmc";
    $no_hmc = urlencode($no_hmc);
    ### LINUX VMs running under OracleVM
    if ( $#vm_items + 1 =~ /oscpu|queue_cpu|jobs|^mem$|pg1|pg2|^lan$|file_sys/ ) {
      if ($code1) {
        for my $linux_uuid ( keys %{$linux_uuids} ) {
          chomp $linux_uuid;
          $lpar_agent_name = $linux_uuids->{$linux_uuid};
          $linux_uuid =~ s/-//g;
          $linux_uuid = lc $linux_uuid;
          if ( $linux_uuid eq $lpar_url ) {
            $linux_vm_name = $lpar_agent_name;
            $linux_vm_name = urlencode($linux_vm_name);
            last;
          }
        }
      }
    }
    ###
    elsif ( $#vm_items + 1 =~ /ovm_vm_aggr_net|ovm_vm_aggr_disk_used/ && $params{type} =~ /vm/ ) {
      my @vms       = @{ OracleVmDataWrapper::get_items( { item_type => 'vm' } ) };
      my $grep_disk = 0;
      my $grep_net  = 0;
      foreach my $vm_uuid (@vms) {
        opendir( DIR3, "$oraclevm_dir/vm/$lpar_url" );
        my @files = readdir(DIR3);
        closedir(DIR3);
        $grep_disk = grep /^disk-/, @files;
        opendir( DIR4, "$oraclevm_dir/vm/$lpar_url" );
        $grep_net = grep /^lan-/, @files;
        closedir(DIR4);
      }
      if ( $grep_disk == 0 && $grep_net == 0 ) {
        @vm_items = ( "ovm_vm_cpu_core", "ovm_vm_cpu_percent", "ovm_vm_mem" );
      }
      elsif ( $grep_disk == 0 && $grep_net != 0 ) {
        @vm_items = ( "ovm_vm_cpu_core", "ovm_vm_cpu_percent", "ovm_vm_mem", "ovm_vm_aggr_net" );
      }
      elsif ( $grep_disk != 0 && $grep_net == 0 ) {
        @vm_items = ( "ovm_vm_cpu_core", "ovm_vm_cpu_percent", "ovm_vm_mem", "ovm_vm_aggr_disk_used" );
      }
    }
    for $tab_number ( 1 .. $#vm_items + 1 ) {
      if ( $vm_items[ $tab_number - 1 ] =~ /ovm_vm_aggr_net|ovm_vm_aggr_disk_used/ ) { $legend = "nolegend"; }
      if ( $vm_items[ $tab_number - 1 ] =~ /oscpu|queue_cpu|jobs|^mem$|pg1|pg2|^lan$|san|^file_sys$/ ) {
        $host_url   = "$no_hmc";
        $server_url = "Linux--unknown";
        $lpar_url   = $linux_vm_name;
        if ( $lpar_url =~ "none" ) { next; }
      }
      print_tab_contents_ovm( $tab_number, $host_url, $server_url, $lpar_url, $vm_items[ $tab_number - 1 ], $entitle, $detail_yes, $legend );
    }
  }
  elsif ( $params{type} =~ m/^server$/ ) {
    my @server_items = ( "ovm_server_cpu_core", "ovm_server_cpu_percent", "ovm_server_mem_server", "ovm_server_mem_percent", "ovm_server_aggr_net", "ovm_server_aggr_disk_used" );
    if ( $#server_items + 1 =~ /ovm_server_aggr_disk_used/ && $params{type} =~ /^server$/ ) {
      my $mapping_server_pool = OracleVmDataWrapper::get_conf_section('arch-server_pool');
      my @servers             = @{ OracleVmDataWrapper::get_items( { item_type => 'server' } ) };
      my $uuids_disk3         = "";
      foreach my $server_uuid (@servers) {
        if ( $server_uuid eq $lpar_url ) {
          opendir( DIR3, "$oraclevm_dir/server/$server_uuid" );
          $uuids_disk3 = grep /^disk-/, readdir(DIR3);
        }
      }
      if ( $uuids_disk3 == 0 ) {
        @server_items = ( "ovm_server_cpu_core", "ovm_server_cpu_percent", "ovm_server_mem_server", "ovm_server_mem_percent", "ovm_server_aggr_net" );
      }
    }
    for $tab_number ( 1 .. $#server_items + 1 ) {
      if ( $server_items[ $tab_number - 1 ] =~ /ovm_server_aggr_net|ovm_server_aggr_disk_used/ ) { $legend = "nolegend"; }
      print_tab_contents_ovm( $tab_number, $host_url, $server_url, $lpar_url, $server_items[ $tab_number - 1 ], $entitle, $detail_yes, $legend );
    }
  }
  elsif ( $params{type} =~ m/^total_server$/ ) {
    my @serverpool_items = ( "ovm_server_total_cpu", "ovm_server_total_mem", "ovm_vm_aggr_cpu_server", "ovm_server_total_net", "ovm_server_total_disk" );
    if ( $#serverpool_items + 1 =~ /ovm_server_total_disk/ && $params{type} =~ /^total_server$/ ) {
      my $mapping_server_pool = OracleVmDataWrapper::get_conf_section('arch-server_pool');
      my @servers             = @{ OracleVmDataWrapper::get_items( { item_type => 'server' } ) };
      my $uuids_disk3         = "";
      foreach my $server_uuid (@servers) {

        #print STDERR"$server_uuid--$lpar_url\n";
        if ( grep( /$server_uuid/, @{ $mapping_server_pool->{$lpar_url} } ) ) {
          opendir( DIR3, "$oraclevm_dir/server/$server_uuid" );
          $uuids_disk3 = grep /^disk-/, readdir(DIR3);
        }
      }
      if ( $uuids_disk3 == 0 ) {
        @serverpool_items = ( "ovm_server_total_cpu", "ovm_server_total_mem", "ovm_vm_aggr_cpu_server", "ovm_server_total_net" );
      }
    }
    for $tab_number ( 1 .. $#serverpool_items + 1 ) {
      $legend = "nolegend";
      print_tab_contents_ovm( $tab_number, $host_url, $server_url, $lpar_url, $serverpool_items[ $tab_number - 1 ], $entitle, $detail_yes, $legend );
    }
  }
  elsif ( $params{type} =~ m/^total_serverpools$/ ) {
    my @serverpool_items = ( "ovm_serverpools_total_cpu", "ovm_serverpools_total_mem", "ovm_vm_aggr_cpu_serverpool", "ovm_serverpools_total_net", "ovm_serverpools_total_disk" );
    for $tab_number ( 1 .. $#serverpool_items + 1 ) {
      $legend = "nolegend";
      print_tab_contents_ovm( $tab_number, $host_url, $server_url, $lpar_url, $serverpool_items[ $tab_number - 1 ], $entitle, $detail_yes, $legend );
    }
  }
  elsif ( $params{type} =~ m/^configuration$/ ) {
    my $mapping_server_pool = OracleVmDataWrapper::get_conf_section('arch-server_pool');
    my $mapping_server_vm   = OracleVmDataWrapper::get_conf_section('arch-vm_server');
    my $server_config       = OracleVmDataWrapper::get_conf_section('spec-server');
    my $vm_config           = OracleVmDataWrapper::get_conf_section('spec-vm');
    my $conf_file           = "$wrkdir/OracleVM/conf.json";
    my $time                = ( stat("$conf_file") )[9];
    $time = localtime($time);

    print "<a href=\"$csv_config_serverpools\"><div class=\"csvexport\">CSV Server Pool</div></a>";

    my $html_tab_header = sub {
      my @columns = @_;
      my $result  = '';

      $result .= "<center>";
      $result .= "<table style=\"white-space: nowrap;\" class=\"tabconfig tablesorter \" data-sortby='1'>";
      $result .= "<thead><tr>";
      foreach my $item (@columns) {
        $result .= "<th class=\"sortable\">" . $item . "</th>";
      }
      $result .= "</tr></thead>";
      $result .= "<tbody>";

      return $result;
    };

    my $html_table_row = sub {
      my @cells  = @_;
      my $result = '';

      $result .= "<tr>";
      foreach my $cell (@cells) { $result .= "<td>" . $cell . "</td>"; }
      $result .= "</tr>";

      return $result;
    };

    my $html_tab_footer = "</tbody></table><p>Last update time: " . $time . "</p></center>";

    # Server pool tab
    print "<div id=\"tabs-1\">\n";

    print $html_tab_header->(
      'Server Pool',  'Server',    "Hostname", 'Address', 'Total Memory [GiB]',
      'Socket count', 'CPU model', 'Hypervisor type', 'Hypervisor name', 'Product name', 'Bios version'
    );

    my @servers = @{ OracleVmDataWrapper::get_items( { item_type => 'server' } ) };
    unless ( scalar @servers > 0 ) {
      print "<tr><td colspan=\"8\" align=\"center\">no server_pools found</td></tr>";
    }
    foreach my $server_uuid (@servers) {
      my $cell_server_pool = 'NA';
      foreach my $server_pool ( sort keys %{$mapping_server_pool} ) {
        if ( grep( /$server_uuid/, @{ $mapping_server_pool->{$server_pool} } ) ) {
          my $server_pool_label = OracleVmDataWrapper::get_label( 'server_pool', $server_pool );
          my $server_pool_link  = OracleVmMenu::get_url( { type => 'total_server', server_pool => $server_pool } );
          $cell_server_pool = "<a style=\"padding:0px;\" href=\"${server_pool_link}\" class=\"backlink\">${server_pool_label}</a>";
        }
      }
      my $server_label = OracleVmDataWrapper::get_label( 'server', $server_uuid );
      my $server_link  = OracleVmMenu::get_url( { type => 'server', server => $server_uuid } );
      my $cell_server  = "<a style=\"padding:0px;\" href=\"${server_link}\" class=\"backlink\">${server_label}</a>";

      my $hostname     = exists $server_config->{$server_uuid}{hostname}        ? $server_config->{$server_uuid}{hostname}        : 'NA';
      my $address      = exists $server_config->{$server_uuid}{ip_address}      ? $server_config->{$server_uuid}{ip_address}      : 'NA';
      my $total_memory = exists $server_config->{$server_uuid}{total_memory}    ? $server_config->{$server_uuid}{total_memory}    : 'NA';
      my $socket_count = exists $server_config->{$server_uuid}{cpu_sockets}     ? $server_config->{$server_uuid}{cpu_sockets}     : 'NA';
      my $cpu_type     = exists $server_config->{$server_uuid}{cpu_type}        ? $server_config->{$server_uuid}{cpu_type}        : 'NA';
      my $hyp_type     = exists $server_config->{$server_uuid}{hypervisor_type} ? $server_config->{$server_uuid}{hypervisor_type} : 'NA';
      my $hyp_name     = exists $server_config->{$server_uuid}{hypervisor_name} ? $server_config->{$server_uuid}{hypervisor_name} : 'NA';
      my $prod_name    = exists $server_config->{$server_uuid}{product_name}    ? $server_config->{$server_uuid}{product_name}    : 'NA';
      my $bios_version = exists $server_config->{$server_uuid}{bios_version}    ? $server_config->{$server_uuid}{bios_version}    : 'NA';

      print $html_table_row->( $cell_server_pool, $cell_server, $hostname, $address, $total_memory, $socket_count, $cpu_type, $hyp_type, $hyp_name, $prod_name, $bios_version );
    }

    print $html_tab_footer;
    print "</div>\n";

    # VM tab
    print "<div id=\"tabs-2\">\n";
    print "<a href=\"$csv_config_vms\"><div class=\"csvexport\">VM CSV</div></a>";

    print $html_tab_header->(
      'Server Pool', 'Server',           'VM', 'Memory [GiB]',
      'Cpu Count',   'Operating system', 'Domain type'
    );

    my @vms = @{ OracleVmDataWrapper::get_items( { item_type => 'vm' } ) };
    unless ( scalar @vms > 0 ) {
      print "<tr><td colspan=\"8\" align=\"center\">no VMs found</td></tr>";
    }
    foreach my $vm_uuid (@vms) {
      my $cell_server_pool = my $cell_server = 'NA';
      foreach my $server ( keys %{$mapping_server_vm} ) {
        if ( grep( /$vm_uuid/, @{ $mapping_server_vm->{$server} } ) ) {
          my $server_label = OracleVmDataWrapper::get_label( 'server', $server );
          my $server_link  = OracleVmMenu::get_url( { type => "server", server => $server } );
          $cell_server = "<a style=\"padding:0px;\" href=\"${server_link}\" class=\"backlink\">${server_label}</a>";

          foreach my $server_pool ( sort keys %{$mapping_server_pool} ) {
            if ( grep( /$server/, @{ $mapping_server_pool->{$server_pool} } ) ) {
              my $server_pool_label = OracleVmDataWrapper::get_label( 'server_pool', $server_pool );
              my $server_pool_link  = OracleVmMenu::get_url( { type => "total_server", server_pool => $server_pool } );
              $cell_server_pool = "<a style=\"padding:0px;\" href=\"${server_pool_link}\" class=\"backlink\">${server_pool_label}</a>";
            }
          }
        }
      }

      my $vm_label = OracleVmDataWrapper::get_label( 'vm', $vm_uuid );
      my $vm_link  = OracleVmMenu::get_url( { type => 'vm', vm => $vm_uuid } );
      my $cell_vm  = "<a style=\"padding:0px;\" href=\"${vm_link}\" class=\"backlink\">${vm_label}</a>";

      my $memory      = exists $vm_config->{$vm_uuid}{memory}      ? $vm_config->{$vm_uuid}{memory}      : 'NA';
      my $cpu_count   = exists $vm_config->{$vm_uuid}{cpu_count}   ? $vm_config->{$vm_uuid}{cpu_count}   : 'NA';
      my $os_type     = exists $vm_config->{$vm_uuid}{os_type}     ? $vm_config->{$vm_uuid}{os_type}     : 'NA';
      my $domain_type = exists $vm_config->{$vm_uuid}{domain_type} ? $vm_config->{$vm_uuid}{domain_type} : 'NA';

      print $html_table_row->( $cell_server_pool, $cell_server, $cell_vm, $memory, $cpu_count, $os_type, $domain_type );
    }

    print $html_tab_footer;
    print "</div>\n";

  }

  ### TOP10 ORACLE VM
  elsif ( $params{type} =~ m/^topten_oraclevm$/ ) {
    ############## LOAD TOPTEN FILE #####################
    my $topten_file_orvm = "$tmpdir/topten_oraclevm.tmp";
    my $last_update      = localtime( ( stat($topten_file_orvm) )[9] );
    #####################################################
    my $server_pool = "";

    # last day
    print "<div id=\"tabs-1\">\n";
    print "<table align=\"center\" summary=\"Graphs\">\n";
    print "<tr><th align=center>CPU in cores<a class=\"csvfloat\" href=\"/lpar2rrd-cgi/top10_csv.sh?LPAR=$server_pool&host=CSV&type=ORACLEVM&table=topten&item=load_cpu&period=1\" title=\"LOAD CPU CSV\"><img src=\"css/images/csv.gif\"></a></th><th align=center>CPU %<a class=\"csvfloat\" href=\"/lpar2rrd-cgi/top10_csv.sh?LPAR=$server_pool&host=CSV&type=ORACLEVM&table=topten&item=cpu_perc&period=1\" title=\"CPU % CSV\"><img src=\"css/images/csv.gif\"></a></th><th align=center>NET in MB/sec<a class=\"csvfloat\" href=\"/lpar2rrd-cgi/top10_csv.sh?LPAR=$server_pool&host=CSV&type=ORACLEVM&table=topten&item=net&period=1\" title=\"NET CSV\"><img src=\"css/images/csv.gif\"></a></th><th align=center>DISK in MB/sec<a class=\"csvfloat\" href=\"/lpar2rrd-cgi/top10_csv.sh?LPAR=$server_pool&host=CSV&type=ORACLEVM&table=topten&item=disk&period=1\" title=\"DISK CSV\"><img src=\"css/images/csv.gif\"></a></th></tr>";
    print "<tr style=\"vertical-align:top\">";
    print_top10_to_table_orvm( "1", "$server_pool", "load_cpu" );
    print_top10_to_table_orvm( "1", "$server_pool", "cpu_perc" );
    print_top10_to_table_orvm( "1", "$server_pool", "net" );
    print_top10_to_table_orvm( "1", "$server_pool", "disk" );
    print "</tr>";
    print "</table>";
    print "<tfoot><tr><td colspan=\"6\">Last update time: $last_update</td></tr></tfoot>";
    print "</div>\n";

    # last week
    print "<div id=\"tabs-2\">\n";
    print "<table align=\"center\" summary=\"Graphs\">\n";
    print "<tr><th align=center>CPU in cores<a class=\"csvfloat\" href=\"/lpar2rrd-cgi/top10_csv.sh?LPAR=$server_pool&host=CSV&type=ORACLEVM&table=topten&item=load_cpu&period=2\" title=\"LOAD CPU CSV\"><img src=\"css/images/csv.gif\"></a></th><th align=center>CPU %<a class=\"csvfloat\" href=\"/lpar2rrd-cgi/top10_csv.sh?LPAR=$server_pool&host=CSV&type=ORACLEVM&table=topten&item=cpu_perc&period=2\" title=\"CPU % CSV\"><img src=\"css/images/csv.gif\"></a></th><th align=center>NET in MB/sec<a class=\"csvfloat\" href=\"/lpar2rrd-cgi/top10_csv.sh?LPAR=$server_pool&host=CSV&type=ORACLEVM&table=topten&item=net&period=2\" title=\"NET CSV\"><img src=\"css/images/csv.gif\"></a></th><th align=center>DISK in MB/sec<a class=\"csvfloat\" href=\"/lpar2rrd-cgi/top10_csv.sh?LPAR=$server_pool&host=CSV&type=ORACLEVM&table=topten&item=disk&period=2\" title=\"DISK CSV\"><img src=\"css/images/csv.gif\"></a></th></tr>";
    print "<tr style=\"vertical-align:top\">";
    print_top10_to_table_orvm( "2", "$server_pool", "load_cpu" );
    print_top10_to_table_orvm( "2", "$server_pool", "cpu_perc" );
    print_top10_to_table_orvm( "2", "$server_pool", "net" );
    print_top10_to_table_orvm( "2", "$server_pool", "disk" );
    print "</tr>";
    print "</table>";
    print "<tfoot><tr><td colspan=\"6\">Last update time: $last_update</td></tr></tfoot>";
    print "</div>\n";

    # last month
    print "<div id=\"tabs-3\">\n";
    print "<table align=\"center\" summary=\"Graphs\">\n";
    print "<tr><th align=center>CPU in cores<a class=\"csvfloat\" href=\"/lpar2rrd-cgi/top10_csv.sh?LPAR=$server_pool&host=CSV&type=ORACLEVM&table=topten&item=load_cpu&period=3\" title=\"LOAD CPU CSV\"><img src=\"css/images/csv.gif\"></a></th><th align=center>CPU %<a class=\"csvfloat\" href=\"/lpar2rrd-cgi/top10_csv.sh?LPAR=$server_pool&host=CSV&type=ORACLEVM&table=topten&item=cpu_perc&period=3\" title=\"CPU % CSV\"><img src=\"css/images/csv.gif\"></a></th><th align=center>NET in MB/sec<a class=\"csvfloat\" href=\"/lpar2rrd-cgi/top10_csv.sh?LPAR=$server_pool&host=CSV&type=ORACLEVM&table=topten&item=net&period=3\" title=\"NET CSV\"><img src=\"css/images/csv.gif\"></a></th><th align=center>DISK in MB/sec<a class=\"csvfloat\" href=\"/lpar2rrd-cgi/top10_csv.sh?LPAR=$server_pool&host=CSV&type=ORACLEVM&table=topten&item=disk&period=3\" title=\"DISK CSV\"><img src=\"css/images/csv.gif\"></a></th></tr>";
    print "<tr style=\"vertical-align:top\">";
    print_top10_to_table_orvm( "3", "$server_pool", "load_cpu" );
    print_top10_to_table_orvm( "3", "$server_pool", "cpu_perc" );
    print_top10_to_table_orvm( "3", "$server_pool", "net" );
    print_top10_to_table_orvm( "3", "$server_pool", "disk" );
    print "</tr>";
    print "</table>";
    print "<tfoot><tr><td colspan=\"6\">Last update time: $last_update</td></tr></tfoot>";
    print "</div>\n";

    # last year
    print "<div id=\"tabs-4\">\n";
    print "<table align=\"center\" summary=\"Graphs\">\n";
    print "<tr><th align=center>CPU in cores<a class=\"csvfloat\" href=\"/lpar2rrd-cgi/top10_csv.sh?LPAR=$server_pool&host=CSV&type=ORACLEVM&table=topten&item=load_cpu&period=4\" title=\"LOAD CPU CSV\"><img src=\"css/images/csv.gif\"></a></th><th align=center>CPU %<a class=\"csvfloat\" href=\"/lpar2rrd-cgi/top10_csv.sh?LPAR=$server_pool&host=CSV&type=ORACLEVM&table=topten&item=cpu_perc&period=4\" title=\"CPU % CSV\"><img src=\"css/images/csv.gif\"></a></th><th align=center>NET in MB/sec<a class=\"csvfloat\" href=\"/lpar2rrd-cgi/top10_csv.sh?LPAR=$server_pool&host=CSV&type=ORACLEVM&table=topten&item=net&period=4\" title=\"NET CSV\"><img src=\"css/images/csv.gif\"></a></th><th align=center>DISK in MB/sec<a class=\"csvfloat\" href=\"/lpar2rrd-cgi/top10_csv.sh?LPAR=$server_pool&host=CSV&type=ORACLEVM&table=topten&item=disk&period=4\" title=\"DISK CSV\"><img src=\"css/images/csv.gif\"></a></th></tr>";
    print "<tr style=\"vertical-align:top\">";
    print_top10_to_table_orvm( "4", "$server_pool", "load_cpu" );
    print_top10_to_table_orvm( "4", "$server_pool", "cpu_perc" );
    print_top10_to_table_orvm( "4", "$server_pool", "net" );
    print_top10_to_table_orvm( "4", "$server_pool", "disk" );
    print "</tr>";
    print "</table>";
    print "<tfoot><tr><td colspan=\"6\">Last update time: $last_update</td></tr></tfoot>";
    print "</div>\n";
  }

  sub print_top10_to_table_orvm {
    my ( $period, $server_pool, $item_name ) = @_;
    my $topten_file_orvm = "$tmpdir/topten_oraclevm.tmp";
    my $html_tab_header  = sub {
      my @columns = @_;
      my $result  = '';
      $result .= "<center>";
      $result .= "<table style=\"white-space: nowrap;\" class=\"tabconfig tablesorter \" data-sortby='1'>";
      $result .= "<thead><tr>";
      foreach my $item (@columns) {
        $result .= "<th class=\"sortable\">" . $item . "</th>";
      }
      $result .= "</tr></thead>";
      $result .= "<tbody>";
      return $result;
    };
    my $html_table_row = sub {
      my @cells  = @_;
      my $result = '';

      $result .= "<tr>";
      foreach my $cell (@cells) { $result .= "<td>" . $cell . "</td>"; }
      $result .= "</tr>";

      return $result;
    };

    # Table or create CSV file
    my $csv_file;
    if ( $item_name eq "load_cpu" ) {
      $csv_file = "orvm-load-cpu.csv";
    }
    elsif ( $item_name eq "cpu_perc" ) {
      $csv_file = "orvm-cpu-perc.csv";
    }
    elsif ( $item_name eq "net" ) {
      $csv_file = "orvm-net.csv";
    }
    elsif ( $item_name eq "disk" ) {
      $csv_file = "orvm-disk.csv";
    }
    if ( !$csv ) {
      if ( $item_name eq "load_cpu" or $item_name eq "cpu_perc" ) {
        print "<TD><TABLE class=\"tabconfig tablesorter\" data-sortby=\"1\">";
        if ( $period == 4 ) {    # last year
          print $html_tab_header->( 'Avrg', "VM", 'Server pool', 'Manager name' );
        }
        else {
          print $html_tab_header->( 'Avrg', 'Max', "VM", 'Server pool', 'Manager name' );
        }
      }
      elsif ( $item_name eq "net" ) {
        print "<TD><TABLE class=\"tabconfig tablesorter\" data-sortby=\"1\">";
        if ( $period == 4 ) {    # last year
          print $html_tab_header->( 'Avrg', "VM", "Name", 'Server pool', 'Manager name' );
        }
        else {
          print $html_tab_header->( 'Avrg', 'Max', "VM", "Name", 'Server pool', 'Manager name' );
        }
      }
      elsif ( $item_name eq "disk" ) {
        print "<TD><TABLE class=\"tabconfig tablesorter\" data-sortby=\"1\">";
        if ( $period == 4 ) {    # last year
          print $html_tab_header->( 'Avrg', "VM", "Name", 'Server pool', 'Manager name' );
        }
        else {
          print $html_tab_header->( 'Avrg', 'Max', "VM", "Name", 'Server pool', 'Manager name' );
        }
      }
    }
    else {
      print "Content-Disposition: attachment;filename=\"$csv_file\"\n\n";
      my $csv_header;
      if ( $item_name eq "load_cpu" or $item_name eq "cpu_perc" ) {
        if ( $period == 4 ) {    # last year
          $csv_header = "Avrg" . "$sep" . "VM" . "$sep" . "Server pool" . "$sep" . "Manager name\n";
        }
        else {
          $csv_header = "Avrg" . "$sep" . "Max" . "$sep" . "VM" . "$sep" . "Server pool" . "$sep" . "Manager name\n";
        }
      }
      elsif ( $item_name eq "net" ) {
        if ( $period == 4 ) {    # last year
          $csv_header = "Avrg" . "$sep" . "VM" . "$sep" . "Name" . "$sep" . "Server pool" . "$sep" . "Manager name\n";
        }
        else {
          $csv_header = "Avrg" . "$sep" . "Max" . "$sep" . "VM" . "$sep" . "Name" . "$sep" . "Server pool" . "$sep" . "Manager name\n";
        }
      }
      elsif ( $item_name eq "disk" ) {
        if ( $period == 4 ) {    # last year
          $csv_header = "Avrg" . "$sep" . "VM" . "$sep" . "Name" . "$sep" . "Server pool" . "$sep" . "Manager name\n";
        }
        else {
          $csv_header = "Avrg" . "$sep" . "Max" . "$sep" . "VM" . "$sep" . "Name" . "$sep" . "Server pool" . "$sep" . "Manager name\n";
        }
      }
      print "$csv_header";
    }
    my @topten;
    my @topten_not_sorted;
    my @topten_sorted;
    my $topten_limit = 0;
    my @top_values_avrg;
    my @top_values_max;
    if ( -f $topten_file_orvm ) {
      open( FH, " < $topten_file_orvm" ) || error( "Cannot open $topten_file_orvm: $!" . __FILE__ . ":" . __LINE__ );
      @topten = <FH>;
      close FH;
      if ( defined $ENV{TOPTEN} ) {
        $topten_limit = $ENV{TOPTEN};
      }
      $topten_limit = 50 if $topten_limit < 1;
      my @topten_server;
      if ( $item_name eq "load_cpu" ) {
        @topten_server = grep {/cpu_util,/} @topten;
      }
      elsif ( $item_name eq "cpu_perc" ) {
        @topten_server = grep {/cpu_perc,/} @topten;
      }
      elsif ( $item_name eq "net" ) {
        @topten_server = grep {/net,/} @topten;
      }
      elsif ( $item_name eq "disk" ) {
        @topten_server = grep {/disk,/} @topten;
      }
      @topten = @topten_server;
      foreach my $line (@topten) {
        chomp $line;
        my ( $item, $vm_name, $server_pool_name, $manager_name, $net_name, $disk_name );
        if ( $item_name eq "load_cpu" or $item_name eq "cpu_perc" ) {
          ( $item, $vm_name, $server_pool_name, $manager_name, $top_values_avrg[1], $top_values_max[1], $top_values_avrg[2], $top_values_max[2], $top_values_avrg[3], $top_values_max[3], $top_values_avrg[4], $top_values_max[4] ) = split( ",", $line );
          $top_values_avrg[4] = 0 if !defined $top_values_avrg[4] or $top_values_avrg[4] eq "";    # no year value yet, new file
          $top_values_max[4]  = 0 if !defined $top_values_max[4]  or $top_values_max[4] eq "";     # no year value yet, new file
                                                                                                   #if ( $top_values_avrg[1] == 0 && $top_values_max[1] == 0 && $top_values_avrg[2] == 0 && $top_values_max[2] == 0 && $top_values_avrg[3] == 0 && $top_values_max[3] == 0 && $top_values_avrg[4] == 0 && $top_values_max[4] == 0 ) { next; }
          push @topten_not_sorted, "$item,$top_values_avrg[$period],$top_values_max[$period],$vm_name,$server_pool_name,$manager_name\n";
        }
        elsif ( $item_name eq "net" ) {
          ( $item, $vm_name, $net_name, $server_pool_name, $manager_name, $top_values_avrg[1], $top_values_max[1], $top_values_avrg[2], $top_values_max[2], $top_values_avrg[3], $top_values_max[3], $top_values_avrg[4], $top_values_max[4] ) = split( ",", $line );
          $top_values_avrg[4] = 0 if !defined $top_values_avrg[4] or $top_values_avrg[4] eq "";    # no year value yet, new file
          $top_values_max[4]  = 0 if !defined $top_values_max[4]  or $top_values_max[4] eq "";     # no year value yet, new file
          $net_name =~ s/===double-col===/:/g;
          $net_name =~ s/\.rrd//g;
          $net_name =~ s/^lan-//g;

          #if ( $top_values_avrg[1] == 0 && $top_values_max[1] == 0 && $top_values_avrg[2] == 0 && $top_values_max[2] == 0 && $top_values_avrg[3] == 0 && $top_values_max[3] == 0 && $top_values_avrg[4] == 0 && $top_values_max[4] == 0 ) { next; }
          push @topten_not_sorted, "$item,$top_values_avrg[$period],$top_values_max[$period],$vm_name,$net_name,$server_pool_name,$manager_name\n";
        }
        elsif ( $item_name eq "disk" ) {
          ( $item, $vm_name, $disk_name, $server_pool_name, $manager_name, $top_values_avrg[1], $top_values_max[1], $top_values_avrg[2], $top_values_max[2], $top_values_avrg[3], $top_values_max[3], $top_values_avrg[4], $top_values_max[4] ) = split( ",", $line );
          $top_values_avrg[4] = 0 if !defined $top_values_avrg[4] or $top_values_avrg[4] eq "";    # no year value yet, new file
          $top_values_max[4]  = 0 if !defined $top_values_max[4]  or $top_values_max[4] eq "";     # no year value yet, new file
                                                                                                   #if ( $top_values_avrg[1] == 0 && $top_values_max[1] == 0 && $top_values_avrg[2] == 0 && $top_values_max[2] == 0 && $top_values_avrg[3] == 0 && $top_values_max[3] == 0 && $top_values_avrg[4] == 0 && $top_values_max[4] == 0 ) { next; }
          push @topten_not_sorted, "$item,$top_values_avrg[$period],$top_values_max[$period],$vm_name,$disk_name,$server_pool_name,$manager_name\n";
        }
      }
      {
        no warnings;
        @topten_sorted = sort { $b <=> $a } @topten_not_sorted;
      }
    }
    my @topten_sorted_load_cpu;
    {
      no warnings;
      @topten_sorted_load_cpu = sort {
        my @b = split( /,/, $b );
        my @a = split( /,/, $a );

        #print "$b[4] --- $a[4]\n";
        $b[1] <=> $a[1]
      } @topten_sorted;
    }
    foreach my $line1 (@topten_sorted_load_cpu) {
      my ( $item_a, $load_cpu, $load_peak, $vm_name, $server_pool_name, $manager_name, $net_name, $disk_name );
      if ( $item_name eq "load_cpu" or $item_name eq "cpu_perc" ) {
        ( $item_a, $load_cpu, $load_peak, $vm_name, $server_pool_name, $manager_name ) = split( ",", $line1 );
      }
      elsif ( $item_name eq "net" ) {
        ( $item_a, $load_cpu, $load_peak, $vm_name, $net_name, $server_pool_name, $manager_name ) = split( ",", $line1 );
      }
      elsif ( $item_name eq "disk" ) {
        ( $item_a, $load_cpu, $load_peak, $vm_name, $disk_name, $server_pool_name, $manager_name ) = split( ",", $line1 );
      }

      #print STDERR"$item_a, $load_cpu, $load_peak, $vm_name, $uuid\n";
      if ( !$csv ) {
        if ( $item_name eq "load_cpu" or $item_name eq "cpu_perc" ) {
          if ( $period == 4 ) {    # last year
            print $html_table_row->( $load_cpu, $vm_name, $server_pool_name, $manager_name );
          }
          else {
            print $html_table_row->( $load_cpu, $load_peak, $vm_name, $server_pool_name, $manager_name );
          }
        }
        elsif ( $item_name eq "net" ) {
          if ( $period == 4 ) {    # last year
            print $html_table_row->( $load_cpu, $vm_name, $net_name, $server_pool_name, $manager_name );
          }
          else {
            print $html_table_row->( $load_cpu, $load_peak, $vm_name, $net_name, $server_pool_name, $manager_name );
          }
        }
        elsif ( $item_name eq "disk" ) {
          if ( $period == 4 ) {    # last year
            print $html_table_row->( $load_cpu, $vm_name, $disk_name, $server_pool_name, $manager_name );
          }
          else {
            print $html_table_row->( $load_cpu, $load_peak, $vm_name, $disk_name, $server_pool_name, $manager_name );
          }
        }
      }
      else {
        if ( $item_name eq "load_cpu" or $item_name eq "cpu_perc" ) {
          if ( $period == 4 ) {    # last year
            print "$load_cpu" . "$sep" . "$vm_name" . "$sep" . "$server_pool_name" . "$sep" . "$manager_name";
          }
          else {
            print "$load_cpu" . "$sep" . "$load_peak" . "$sep" . "$vm_name" . "$sep" . "$server_pool_name" . "$sep" . "$manager_name";
          }
        }
        elsif ( $item_name eq "net" ) {
          if ( $period == 4 ) {    # last year
            print "$load_cpu" . "$sep" . "$vm_name" . "$sep" . "$server_pool_name" . "$sep" . "$manager_name";
          }
          else {
            print "$load_cpu" . "$sep" . "$load_peak" . "$sep" . "$vm_name" . "$sep" . "$net_name" . "$sep" . "$server_pool_name" . "$sep" . "$manager_name";
          }
        }
        elsif ( $item_name eq "disk" ) {
          if ( $period == 4 ) {    # last year
            print "$load_cpu" . "$sep" . "$vm_name" . "$sep" . "$server_pool_name" . "$sep" . "$manager_name";
          }
          else {
            print "$load_cpu" . "$sep" . "$load_peak" . "$sep" . "$vm_name" . "$sep" . "$disk_name" . "$sep" . "$server_pool_name" . "$sep" . "$manager_name";
          }
        }
      }
    }
    if ( !$csv ) {
      print "</TABLE></TD>";
    }
    return 1;
  }

  sub print_tab_contents_ovm {
    my ( $tab_number, $host_url, $server_url, $lpar_url, $item, $entitle, $detail_yes, $legend ) = @_;

    #print STDERR"line5526-$tab_number, $host_url, $server_url, $lpar_url, $item, $entitle, $detail_yes, $legend\n";
    my $oraclevm_dir = "$basedir/data/OracleVM";
    if ( $item =~ /ovm_server_total_disk|ovm_server_aggr_disk_used/ && $params{type} =~ /^total_server$/ ) {
      my $mapping_server_pool = OracleVmDataWrapper::get_conf_section('arch-server_pool');
      my @servers             = @{ OracleVmDataWrapper::get_items( { item_type => 'server' } ) };
      my $uuids_disk3         = 0;
      foreach my $server_uuid (@servers) {

        #print STDERR"$server_uuid--$lpar_url\n";
        if ( grep( /$server_uuid/, @{ $mapping_server_pool->{$lpar_url} } ) ) {
          opendir( DIR3, "$oraclevm_dir/server/$server_uuid" );
          $uuids_disk3 = grep /^disk-/, readdir(DIR3);
        }
      }
      if ( $uuids_disk3 == 0 ) { next; }
    }
    if ( $item =~ /disk_used/ && $params{type} =~ /^server|^vm$/ ) {    #### Server and VM disk tab
      my $vmorserver = "";
      if ( $params{type} =~ /total_server|server/ ) {
        $vmorserver = "server";
      }
      else {
        $vmorserver = "vm";
      }
      opendir( DIR1, "$oraclevm_dir/$vmorserver/$lpar_url" );
      my $uuids_disk1 = grep /^disk-/, readdir(DIR1);
      if ( $uuids_disk1 == 0 ) { next; }
    }
    if ( $item =~ /aggr_net/ && $params{type} =~ /^server|^vm$/ ) {     #### Server and VM disk tab
      my $vmorserver = "";
      if ( $params{type} =~ /total_server|server/ ) {
        $vmorserver = "server";
      }
      else {
        $vmorserver = "vm";
      }
      opendir( DIR1, "$oraclevm_dir/$vmorserver/$lpar_url" );
      my $uuids_disk1 = grep /^lan-/, readdir(DIR1);
      if ( $uuids_disk1 == 0 ) { next; }
    }
    if ( $item =~ /oscpu|queue_cpu|^mem$|pg1|pg2/ )   { $legend = "legend"; }
    if ( $item =~ /jobs|lan|aggr|^ovm_server_total/ ) { $legend = "nolegend"; }
    if ( $item =~ m/file_sys/ ) {

      #print STDERR "1366 JCOM: \$vmware $vmware \$item $item path:$wrkdir/$server/$host/$lpar/FS.csv\n";
      $server_url = urldecode($server_url);
      $lpar_url   = urldecode($lpar_url);
      $host_url   = urldecode($host_url);
      my $file = "$wrkdir/$server_url/$host_url/$lpar_url/FS.csv";
      print "<div id =\"tabs-$tab_number\">
      <center>
      <h4>Filesystem usage</h4>
      <tbody>
      <tr>
      <table class =\"tabconfig tablesorter\"data-sortby=\"5\">
      <thead>
      <tr><th class = \"sortable\">Filesystem&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;</th>
      <th class = \"sortable\">Total [GB]&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;</th>
      <th class = \"sortable\">Used [GB]&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;</th>
      <th class = \"sortable\">Available [GB]&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;</th>
      <th class = \"sortable\">Usage [%]&nbsp;&nbsp;</th>
      <th class = \"sortable\">Mounted on&nbsp;&nbsp;</th>
      </tr></thead>\n\n";
      my $last_update = "not detected";

      if ( -f "$file" ) {
        open( FH, "< $file" ) || error( "Cannot open $file: $!" . __FILE__ . ":" . __LINE__ );
        my @file_sys_arr = <FH>;
        close(FH);
        foreach my $line (@file_sys_arr) {
          chomp($line);
          ( my $filesystem, my $blocks, my $used, my $avaliable, my $usage, my $mounted ) = split( " ", $line );
          $filesystem =~ s/=====double-colon=====/:/g;
          $mounted    =~ s/=====double-colon=====/:/g;
          print "<tr><td>$filesystem</td>
          <td>$blocks</td>
          <td>$used</td>
          <td>$avaliable</td>
          <td>$usage</td>
          <td>$mounted</td></tr>";
        }
        $last_update = localtime( ( stat($file) )[9] );
      }
      print "<tfoot><tr><td colspan=\"6\">Last update time: $last_update</td></tr></tfoot>";
      print "</tr>
      </tbody>
      </table>
      <div><p>You can exclude filesystem for alerting in $basedir/etc/alert_filesystem_exclude.cfg</p></div>
      </center>
      </div>\n";
      $tab_number++;
    }
    else {
      print "<div id=\"tabs-$tab_number\">\n";
      print "<table border=\"0\">\n";
      print "<tr>";
      print_item( $host_url, $server_url, $lpar_url, $item, "d", "m", $entitle, $detail_yes, "norefr", "star", 1, "$legend" );
      print_item( $host_url, $server_url, $lpar_url, $item, "w", "m", $entitle, $detail_yes, "norefr", "star", 1, "$legend" );
      print "</tr>\n<tr>\n";
      print_item( $host_url, $server_url, $lpar_url, $item, "m", "m", $entitle, $detail_yes, "norefr", "star", 1, "$legend" );
      print_item( $host_url, $server_url, $lpar_url, $item, "y", "m", $entitle, $detail_yes, "norefr", "star", 1, "$legend" );
      print "</tr></table>";
      print "</div>\n";
    }
  }
}

# POWER
# TABs
# basic CPU
$tab_number = 0;
print "\n<div  id=\"tabs\"> <ul>\n";

# basic CPU from the HMC
my $cpu = 0;

if ( -f "$wrkdir/$server/$host/$lpar_slash.rr$type_sam" ) {
  my $filesize = -s "$wrkdir/$server/$host/$lpar_slash.rr$type_sam";

  # OS agent based lpars without the HMC does have only touched .rrh file
  if ( $filesize > 0 ) {
    $tab_number++;
    $cpu = $tab_number;
    print "  <li class=\"tabhmc\"><a href=\"#tabs-$tab_number\">CPU</a></li>\n";

    #$tab_number++;
    #print "  <li class=\"tabhmc\"><a href=\"#tabs-$tab_number\">vCPU</a></li>\n";

    $upper = rrd_upper( $wrkdir, $server, $host, $lpar, $type_sam, $type_sam_year, $item, $lpar_slash );
  }
}

my $lpm        = 0;
my $is_premium = premium();
if ( $is_premium !~ m/free/ ) {
  $lpm = is_lpm( $host, $server, $lpar, $lpm_env );
  if ( $lpm > 0 ) {
    $tab_number++;
    $lpm = $tab_number;
    print "  <li class=\"tabhmc\"><a href=\"#tabs-$tab_number\">LPM</a></li>\n";
  }
}

my $ams = 0;
if ( $entitle == 0 && -f "$wrkdir/$server/$host/$lpar_slash.rm$type_sam" ) {
  $tab_number++;
  $ams = $tab_number;
  print "  <li class=\"tabhmc\"><a href=\"#tabs-$tab_number\">AMS</a></li>\n";
}

my $wpar_cpu  = 0;
my $wpar_name = find_wpar( "$wrkdir/$server/$host/$lpar_slash", $wpar );
if ( $entitle == 0 && test_file_in_directory( "$wrkdir/$server/$host/$lpar_slash/$wpar_name", "cpu" ) ) {
  $tab_number++;
  $wpar_cpu = $tab_number;
  print "  <li class=\"tabhmc\"><a href=\"#tabs-$tab_number\">WPAR_CPU</a></li>\n";
}

my $wpar_mem = 0;
if ( $entitle == 0 && test_file_in_directory( "$wrkdir/$server/$host/$lpar_slash/$wpar_name", "mem" ) ) {
  $tab_number++;
  $wpar_mem = $tab_number;
  print "  <li class=\"tabhmc\"><a href=\"#tabs-$tab_number\">WPAR_MEM</a></li>\n";
}

@item_agent      = "";
@item_agent_tab  = "";
$item_agent_indx = 0;
$os_agent        = 0;
$nmon_agent      = 0;
$iops            = "IOPS";

if ( $server !~ /Solaris|Solaris--unknown|Solaris\d+--unknown/ ) {
  build_agents_tabs( $server, $host, $lpar_slash );
}

# TABs header end
print "   </ul> \n";
$tab_number = 1;

if ( $cpu > 0 ) {

  # lpar without HMC use only agents --> so no cpu graphs
  print "<div id=\"tabs-$tab_number\"><br><br>\n";

  my $refresh = "";
  $refresh = "<div class=\"refresh fas fa-sync-alt\"><A HREF=\"/lpar2rrd-cgi/lpar2rrd-realt.sh?source=$lpar_url&hmc=$host_url&mname=$server_url&new_gui=$gui\"></A></div>\n";
  print "<table align=\"center\" summary=\"Graphs\">\n";
  print "<tr>\n";
  print_item( $host_url, $server_url, $lpar_url, $item, "d", $type_sam, $entitle, $detail_yes, $refresh, "star", 1, "legend" );
  print_item( $host_url, $server_url, $lpar_url, $item, "w", $type_sam, $entitle, $detail_yes, "norefr", "star", 1, "legend" );
  print "</tr>\n<tr>\n";
  print_item( $host_url, $server_url, $lpar_url, $item, "m", $type_sam,      $entitle, $detail_yes, "norefr", "star", 1, "legend" );
  print_item( $host_url, $server_url, $lpar_url, $item, "y", $type_sam_year, $entitle, $detail_yes, "norefr", "star", 1, "legend" );
  print "</tr>\n";

  # Trend graph
  print "<tr>\n";
  if ( !$vmware && !$hyperv ) {
    print_item( $host_url, $server_url, $lpar_url, "trend", "y", $type_sam_year, $entitle, $detail_yes, "norefr", "nostar", 2, "legend" );
  }
  print "</tr>\n";
  print "<tr><td align=\"left\" colspan=\"2\"><br>\n";
  if ( !$vmware && !$hyperv ) {
    print_lpar_cfg( $host_url, $server_url, $lpar_url, $wrkdir, $server, $host, $lpar_slash, $lpar );
  }
  print "</td></tr></table>\n";
  print "</div>\n\n";

  # lpar virtual processors
  #$tab_number++;
  #print "<div id=\"tabs-$tab_number\"><br><br>\n";

  #$refresh = "<div class=\"refresh fas fa-sync-alt\"><A HREF=\"/lpar2rrd-cgi/lpar2rrd-realt.sh?source=$lpar_url&hmc=$host_url&mname=$server_url&new_gui=$gui\"></A></div>\n";
  #print "<table align=\"center\" summary=\"Graphs\">\n";
  #print "<tr>\n";
  #print_item( $host_url, $server_url, $lpar_url, "power_vcpu", "d", $type_sam, $entitle, $detail_yes, "norefr", "star", 1, "legend" );
  #print_item( $host_url, $server_url, $lpar_url, "power_vcpu", "w", $type_sam, $entitle, $detail_yes, "norefr", "star", 1, "legend" );
  #print "</tr>\n<tr>\n";
  #print_item( $host_url, $server_url, $lpar_url, "power_vcpu", "m", $type_sam,      $entitle, $detail_yes, "norefr", "star", 1, "legend" );
  #print_item( $host_url, $server_url, $lpar_url, "power_vcpu", "y", $type_sam_year, $entitle, $detail_yes, "norefr", "star", 1, "legend" );
  #print "</tr>\n";

  # Trend graph
  #print "<tr>\n";
  #if ( !$vmware && !$hyperv ) {
  #  print_item( $host_url, $server_url, $lpar_url, "power_vcpu_trend", "y", $type_sam_year, $entitle, $detail_yes, "norefr", "nostar", 2, "legend" );
  #}
  #print "</tr>\n";
  #print "<tr><td align=\"left\" colspan=\"2\"><br>\n";
  #print "</td></tr></table>\n";
  #print "</div>\n\n";

}

# LPM
print OUT "002 LPM : $host,$server,$lpar,$lpm : $lpm \n" if $DEBUG == 2;
if ( $lpm > 0 ) {
  print "<div id=\"tabs-$lpm\"><br><br>\n";
  print "<center>\n";
  print "\n<table align=\"center\" summary=\"Graphs\">\n";
  $item = "lpm";
  print "<tr>\n";
  print_item( $host_url, $server_url, $lpar_url, $item, "d", $type_sam, $entitle, $detail_no, "norefr", "star", 1, "legend" );
  print_item( $host_url, $server_url, $lpar_url, $item, "w", $type_sam, $entitle, $detail_no, "norefr", "star", 1, "legend" );
  print "</tr>\n<tr>\n";
  print_item( $host_url, $server_url, $lpar_url, $item, "m", $type_sam,      $entitle, $detail_no, "norefr", "star", 1, "legend" );
  print_item( $host_url, $server_url, $lpar_url, $item, "y", $type_sam_year, $entitle, $detail_no, "norefr", "star", 1, "legend" );
  print "</tr></table>\n";
  print "</center></div>\n\n";
}

# AMS
if ( $ams > 0 ) {
  print "<div id=\"tabs-$ams\"><br><br>\n";
  print "<center>\n";
  print OUT "003 AMS : $wrkdir/$server/$host/$lpar_slash.rm$type_sam \n" if $DEBUG == 2;
  print "\n<table align=\"center\" summary=\"Graphs\">\n";
  $item = "ams";
  print "<tr>\n";
  print_item( $host_url, $server_url, $lpar_url, $item, "d", $type_sam, $entitle, $detail_yes, "norefr", "star", 1, "legend" );
  print_item( $host_url, $server_url, $lpar_url, $item, "w", $type_sam, $entitle, $detail_yes, "norefr", "star", 1, "legend" );
  print "</tr>\n<tr>\n";
  print_item( $host_url, $server_url, $lpar_url, $item, "m", $type_sam,      $entitle, $detail_yes, "norefr", "star", 1, "legend" );
  print_item( $host_url, $server_url, $lpar_url, $item, "y", $type_sam_year, $entitle, $detail_yes, "norefr", "star", 1, "legend" );
  print "</tr></table>\n";
  print "</center></div>\n\n";
}

# WPAR-CPU
if ( $wpar_cpu > 0 ) {
  print "<div id=\"tabs-$wpar_cpu\"><br><br>\n";
  print "<center>\n";
  print OUT "003 WPAR-CPU : $wrkdir/$server/$host/$lpar_slash.rm$type_sam \n" if $DEBUG == 2;
  print "\n<table align=\"center\" summary=\"Graphs\">\n";
  $item = "wpar_cpu";
  print "<tr>\n";
  print_item( $host_url, $server_url, $lpar_url, $item, "d", $type_sam, $entitle, $detail_yes, "norefr", "star", 1, "nolegend" );
  print_item( $host_url, $server_url, $lpar_url, $item, "w", $type_sam, $entitle, $detail_yes, "norefr", "star", 1, "nolegend" );
  print "</tr>\n<tr>\n";
  print_item( $host_url, $server_url, $lpar_url, $item, "m", $type_sam,      $entitle, $detail_yes, "norefr", "star", 1, "nolegend" );
  print_item( $host_url, $server_url, $lpar_url, $item, "y", $type_sam_year, $entitle, $detail_yes, "norefr", "star", 1, "nolegend" );
  print "</tr></table>\n";
  print "</center></div>\n\n";
}

# WPAR-MEM
if ( $wpar_mem > 0 ) {
  print "<div id=\"tabs-$wpar_mem\"><br><br>\n";
  print "<center>\n";
  print OUT "003 WPAR-MEM : $wrkdir/$server/$host/$lpar_slash.rm$type_sam \n" if $DEBUG == 2;
  print "\n<table align=\"center\" summary=\"Graphs\">\n";
  $item = "wpar_mem";
  print "<tr>\n";
  print_item( $host_url, $server_url, $lpar_url, $item, "d", $type_sam, $entitle, $detail_yes, "norefr", "star", 1, "nolegend" );
  print_item( $host_url, $server_url, $lpar_url, $item, "w", $type_sam, $entitle, $detail_yes, "norefr", "star", 1, "nolegend" );
  print "</tr>\n<tr>\n";
  print_item( $host_url, $server_url, $lpar_url, $item, "m", $type_sam,      $entitle, $detail_yes, "norefr", "star", 1, "nolegend" );
  print_item( $host_url, $server_url, $lpar_url, $item, "y", $type_sam_year, $entitle, $detail_yes, "norefr", "star", 1, "nolegend" );
  print "</tr></table>\n";
  print "</center></div>\n\n";
}
build_agents_html( $server_url, $host_url, $lpar_url, 0 );

print "</div><br>\n";
exit(0);

sub build_agents_html {
  my $server_url = shift;
  my $host_url   = shift;
  my $lpar_url   = shift;
  my $tab_number = shift;
  if ( $os_agent > 0 || $nmon_agent > 0 ) {
    my $lpar_url_save = $lpar_url;
    foreach my $item (@item_agent) {
      if ( !defined $item ) {
        next;
      }
      if ( $item =~ m/file_sys/ ) {

        #print STDERR "1366 JCOM: \$vmware $vmware \$item $item path:$wrkdir/$server/$host/$lpar/FS.csv\n";
        my $file = "$wrkdir/$server/$host/$lpar/FS.csv";
        print "<div id =\"tabs-$item_agent_tab[$tab_number]\">
        <a class=\"csvfloat\" href=\"/lpar2rrd-cgi/top10_csv.sh?SERVER=$server&HMC=$host&LPAR=$lpar&host=CSV_filesystem&item=filesystem\" style=\"display: block; margin-left: auto; margin-right: 0px; max-width: fit-content;title=\"FS CSV\"><img src=\"css/images/csv.gif\"></a>
        <center>
        <h4>Filesystem usage</h4>
        <tbody>
        <tr>
        <table class =\"tabconfig tablesorter\"data-sortby=\"5\">
        <thead>
        <tr><th class = \"sortable\">Filesystem&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;</th>
        <th class = \"sortable\">Total [GB]&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;</th>
        <th class = \"sortable\">Used [GB]&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;</th>
        <th class = \"sortable\">Available [GB]&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;</th>
        <th class = \"sortable\">Usage [%]&nbsp;&nbsp;</th>
        <th class = \"sortable\">Mounted on&nbsp;&nbsp;</th>
        </tr></thead>\n\n";
        my $last_update = "not detected";
        if ( -f "$file" ) {
          open( FH, "< $file" ) || error( "Cannot open $file: $!" . __FILE__ . ":" . __LINE__ );
          my @file_sys_arr = <FH>;
          close(FH);
          foreach my $line (@file_sys_arr) {
            chomp($line);
            ( my $filesystem, my $blocks, my $used, my $avaliable, my $usage, my $mounted ) = split( " ", $line );
            $filesystem =~ s/=====double-colon=====/:/g;
            $mounted    =~ s/=====double-colon=====/:/g;
            print "<tr><td>$filesystem</td>
            <td>$blocks</td>
            <td>$used</td>
            <td>$avaliable</td>
            <td>$usage</td>
            <td>$mounted</td></tr>";
          }
          $last_update = localtime( ( stat($file) )[9] );
        }
        print "<tfoot><tr><td colspan=\"6\">Last update time: $last_update</td></tr></tfoot>";
        print "</tr>
        </tbody>
        </table>
        <div><p>You can exclude filesystem for alerting in $basedir/etc/alert_filesystem_exclude.cfg</p></div>
        </center>
        </div>\n";
        $tab_number++;
        next;
      }

      my %hash_aix      = ();
      my %hash_aix_size = ();

      if ( $item =~ m/lsdisk/ ) {

        #print STDERR "1366 JCOM: \$vmware $vmware \$item $item path:$wrkdir/$server/$host/$lpar/FS.csv\n";
        my $file = "$wrkdir/$server/$host/$lpar/aix_multipathing.txt";
        $file = rrd_from_active_hmc( "$server", "$lpar/aix_multipathing.txt", "$file" );
        print "<div id =\"tabs-$item_agent_tab[$tab_number]\">
        <tr><a class=\"csvfloat\" href=\"/lpar2rrd-cgi/top10_csv.sh?SERVER=$server&HMC=$host&LPAR=$lpar&host=CSV_multi&item=aix_multipath\" style=\"display: block; margin-left: auto; margin-right: 0px; max-width: fit-content;title=\"MULTIPATH CSV\"><img src=\"css/images/csv.gif\"></a></tr>
        <center>
        <tbody>
        <tr>
        <table class =\"tabconfig tablesorter\"data-sortby=\"5\">
        <thead>
        <tr><th class = \"sortable\">Disk name&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;</th>
        <th class = \"sortable\">Disk size [MB]&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;</th>
        <th class = \"sortable\">Path properties&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;</th>
        <th class = \"sortable\">Path info&nbsp;&nbsp;</th>
        <th class = \"sortable\">Path status&nbsp;&nbsp;</th>
        <th class = \"sortable\">Status&nbsp;&nbsp;</th>
        </tr></thead>\n\n";
        my $last_update = "not detected";
        if ( -f "$file" ) {
          open( FH, "< $file" ) || error( "Cannot open $file: $!" . __FILE__ . ":" . __LINE__ );
          my @lsdisk_arr = <FH>;
          close(FH);
          my @list_of_disk;
          foreach my $line (@lsdisk_arr) {
            chomp($line);
            my ( $namedisk, $path_id, $connection, $parent, $path_status, $status, $disk_size ) = split( /:/, $line );
            $connection  =~ s/=====double-colon=====/:/g;
            $parent      =~ s/=====double-colon=====/:/g;
            $path_status =~ s/=====double-colon=====/:/g;
            my $values   = "$path_status:$status";
            my $parent_c = "$parent , $connection";
            push @{ $hash_aix{$namedisk}{$parent_c} }, $values;

            if ( isdigit($disk_size) ) {
              $hash_aix_size{$namedisk}{disk_size} = $disk_size;
            }
          }
          $last_update = localtime( ( stat($file) )[9] );
        }
        foreach my $namedisk ( keys %hash_aix ) {
          my $color_ok       = "#d3f9d3";                        ##### GREEN
          my $color_crit     = "#ffb8b8";                        ##### RED
          my $color_warn     = "#ffe6b8";                        ##### ORANGE
          my $color_ok_text  = "";
          my $status_text_ok = "OK";
          my $count          = keys %{ $hash_aix{$namedisk} };
          my $disk_size      = "-";
          if ( defined $hash_aix_size{$namedisk}{disk_size} ) {
            $disk_size = $hash_aix_size{$namedisk}{disk_size};
          }
          print "<td>$namedisk</td>";
          print "<td>$disk_size</td>";
          if ( $count > 1 ) {
            print "<td>";
          }
          my @string_test1;
          my @string_test2;
          foreach my $parent ( sort keys %{ $hash_aix{$namedisk} } ) {
            my ( $path_status, $status ) = split( /:/, $hash_aix{$namedisk}{$parent}[0] );
            push @string_test1, $path_status . "\n";    ### last value status to array, because <td> problem / print at the end foreach
            push @string_test2, $status . "\n";         ### last value status to array, because <td> problem / print at the end foreach
                                                        #print "$count\n";
            if ( $count > 1 ) {
              print "$parent<br>";
            }
            else {
              if ( $path_status !~ /Available/ ) {
                $color_ok       = "hs_error";
                $status_text_ok = "Critical";
                $color_ok_text  = "#ED3027";    ##### RED
              }
              else {
                $color_ok       = "hs_good";    ##### GREEN
                $status_text_ok = "OK";
                $color_ok_text  = "#36B236";    ##### GREEN
              }
              print "<td>$parent</td>";
              print "<td style=\"color:$color_ok_text;\">$path_status</td>";
              print "<td>$status</td>";
              print "<td class=\"$color_ok\">$status_text_ok</td>";
            }
          }
          if ( $count > 1 ) {
            print "</td>";
            print "<td>";
            my $status_text = "";
            my $grep_ok     = grep {/^Available$/} @string_test1;
            my $grep_nok    = grep {/^Defined$|^Missing/} @string_test1;
            my $grep_nok1   = grep {/Failed|Disabled|N\/A/} @string_test2;
            foreach my $status_a (@string_test1) {
              if ( $status_a !~ /Available/ ) {
                $color_ok = "#ED3027";
              }
              else {
                $color_ok = "#36B236";
              }
              print "<font color=$color_ok>$status_a</font><br>";
            }
            print "</td>";
            print "<td>";
            foreach my $status_b (@string_test2) {
              print "$status_b<br>";
            }
            print "</td>";
            if ( $grep_ok >= 1 && $grep_nok == 0 && $grep_nok1 == 0 ) {    ##### OK
              $status_text = "OK";
              print "<td class=\"hs_good\">$status_text</p></td>";
            }
            elsif ( $grep_ok >= 1 && $grep_nok >= 1 && $grep_nok1 >= 1 ) {    ##### WARNING
              $status_text = "Warning";
              print "<td class=\"hs_warning\">$status_text</p></td>";
            }
            elsif ( $grep_ok >= 1 && $grep_nok == 0 && $grep_nok1 >= 1 ) {    ##### WARNING
              $status_text = "Warning";
              print "<td class=\"hs_warning\">$status_text</p></td>";
            }
            elsif ( $grep_ok >= 1 && $grep_nok == 1 && $grep_nok1 == 0 ) {    ##### WARNING
              $status_text = "Critical";
              print "<td class=\"hs_error\">$status_text</p></td>";
            }
            elsif ( $grep_ok == 0 && $grep_nok >= 1 && $grep_nok1 >= 1 ) {    ##### CRITICAL
              $status_text = "Critical";
              print "<td class=\"hs_error\">$status_text</p></td>";
            }
          }
          print "</tr>";
        }

        print "<tfoot><tr><td colspan=\"5\">Last update time: $last_update</td></tr></tfoot>";
        print "</tr>
        </tbody>
        </table>
        </center>
        </div>\n";
        $tab_number++;
        next;
      }

      if ( $item =~ m/path_lin/ ) {

        #print STDERR "1366 JCOM: \$vmware $vmware \$item $item path:$wrkdir/$server/$host/$lpar/FS.csv\n";
        my $file = "$wrkdir/$server/$host/$lpar/linux_multipathing.txt";
        $file = rrd_from_active_hmc( "$server", "$lpar/linux_multipathing.txt", "$file" );
        print "<div id =\"tabs-$item_agent_tab[$tab_number]\">
        <center>
        <tbody>
        <tr>
        <table class =\"tabconfig tablesorter\"data-sortby=\"5\">
        <thead>
        <th>WWID&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;</th>
        <th>Alias&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;</th>
        <th>Attributes&nbsp;&nbsp;</th>
        <th>Paths&nbsp;&nbsp;</th>
        </tr></thead>\n\n";
        my $last_update = "not detected";
        if ( -f "$file" ) {
          open( FH, "< $file" ) || error( "Cannot open $file: $!" . __FILE__ . ":" . __LINE__ );
          my @multi_lin_arr = <FH>;
          close(FH);
          foreach my $line (@multi_lin_arr) {
            chomp($line);
            my ( $string1, $string2, $string3, $string4 ) = split( /:/, $line );
            $string1 =~ s/\\//g;
            $string3 =~ s/\//|/g;
            $string4 =~ s/\//|/g;
            $string4 =~ s/=====double-colon=====/:/g;

            #print "$string3???\n";
            my $alias  = "";
            my $wwid   = "";
            my $split1 = "";
            if ( $string1 =~ /\(/ ) {
              ( $alias, $split1 ) = split( /\(/, $string1 );
              $split1 =~ s/\)//g;
              ($wwid) = split( / /, $split1 );
              unless ( defined $wwid ) { $wwid = ""; }
            }
            else { $alias = $string1 }
            my @path_groups  = split( /\|/, $string3 );
            my @paths        = split( /\|/, $string4 );
            my $rowspan_line = scalar @path_groups;

            print "<tr>";
            print "<td>$wwid</td>";
            print "<td>$alias</td>";
            print "<td>$string2</td>";
            my $i = 0;
            print "<td>";
            foreach (@paths) {
              my $color_text = "";
              if ( $paths[$i] =~ /ghost|ready/ ) {
                $color_text = "#36B236";

              }
              else {
                $color_text = "#ED3027";
              }
              if ( !defined $path_groups[$i] ) {
                print "<br><font color=$color_text>$paths[$i]</font><br>";

              }
              else {
                print "$path_groups[$i]!<br><font color=$color_text>$paths[$i]</font><br>";
                $i++;
              }
            }
            print "</td>";
            print "</tr>";
          }
          $last_update = localtime( ( stat($file) )[9] );
        }
        print "<tfoot><tr><td colspan=\"4\">Last update time: $last_update</td></tr></tfoot>";
        print "</tr>
        </tbody>
        </table>
        </center>
        </div>\n";
        $tab_number++;
        next;
      }
      #
      # KZ: mapping lpar -> volume (stor2rrd)
      #
      if ( $item eq "lpar2volumes" ) {
        print "<div id =\"tabs-$item_agent_tab[$tab_number]\">";
        print "<div id=\"hiw\"><a href=\"http://www.xormon.com/storage-linking.php\" target=\"_blank\" class=\"nowrap\"><img src=\"css/images/help-browser.gif\" alt=\"Storage linking\" title=\"Storage linking\"></img></a></div>";
        print "<ul>\n";
        foreach my $volume_uid (@lpar2volumes) {
          if ( $volume_uid eq '' ) { next; }
          print "<li>$volume_uid</li>\n";
        }
        print "</ul>\n";
        print "</div>\n";

        $tab_number++;
        next;
      }

      my $demo_line = "";

      #Do not use this anymore, we support dsk_latency since 11/2020 at demo. HD
      #if ( defined $ENV{DEMO} && ( $ENV{DEMO} == 1 ) && ($item =~ m/dsk_latency/) ) {
      #  $demo_line = "<br>
      #  Demo site does not actually support this data.<br>
      #  For examples check this: <a href=\"http://www.lpar2rrd.com/as400-ASP_latency-monitoring.htm\" target=\"_blank\">www.lpar2rrd.com/as400-ASP_latency-monitoring.htm</a> <br>
      #  <br>";
      #  $false_picture = "<br>$demo_line<br>";
      #}

      if ( ( $item =~ m/dsk_latency/ ) && ( ( premium() =~ "free" ) || ( !test_file_in_directory( "$wrkdir/$server/$host/$lpar_slash$AS400/LTC", ".*", "mmc" ) ) ) ) {

        # prepare false picture
        $false_picture = "<br>$demo_line<br>

        <table><tr><td>

        You are using free LPAR2RRD IBM i agent edition.<br>

        ASP disk service time and ASP disk wait time are not available in Free Edition.<br>

        This is one of <a href=\"http://www.lpar2rrd.com/support.htm#benefits\" class=\"ulink\" target=\"_blank\"><b>benefits</b></a> of the Enterprise Edition which is distributed to customers under support<br>
        <br>
        For ASP latency examples check this: <a href=\"http://www.lpar2rrd.com/as400-ASP_latency-monitoring.htm\" target=\"_blank\">www.lpar2rrd.com/as400-ASP_latency-monitoring.htm</a> <br>

        </td></tr></table>

        <br><br>";
      }

      my $nmon = "";
      $lpar_url = $lpar_url_save;
      if ( $item =~ m/^nmon-/ ) {
        $nmon = "NMON";
        $lpar_url .= $NMON;
        $item =~ s/^nmon-//;
      }
      $lpar =~ s/--WPAR--/\//g;    # WPAR delimiter replace
      my $legend = "legend";
      if ( $item =~ m/lan/ || $item =~ m/san1/ || $item =~ m/san2/ || $item =~ m/sea/ || $item =~ m/san_resp/ || $item =~ m/size/ || $item =~ m/res/ || $item =~ m/threads/ || $item =~ m/faults/ || $item =~ m/pages/ || $item =~ m/waj/ || $item =~ m/job_cpu/ || $item =~ m/disk_io/ || $item =~ m/cap_/ || $item =~ m/data_as/ || $item =~ m/iops_as/ || $item =~ m/dsk_latency/ || $item =~ m/data_ifcb/ || $item =~ m/disk_busy/ || $item =~ m/jobs/ || $item =~ m/wlm-cpu/ || $item =~ m/wlm-mem/ || $item =~ m/wlm-dkio/ || $item =~ m/error/ ) {
        $legend = "nolegend";
      }
      if ( $item =~ m/waj/ || $item =~ m/job_cpu/ || $item =~ m/disk_io/ ) {
        $legend = "nolegend higher";    #instead of 'm' and 'y' graphs there is 3x longer legends
      }
      print "<div id=\"tabs-$item_agent_tab[$tab_number]\"><br><br><center>\n";

      if ( $item =~ m/^oscpu$/ )                                                 { print "<div id='hiw'><a href=\"http://www.lpar2rrd.com/os_cpu_monitoring.html\">How it works</a></div>\n"; }
      if ( $item =~ m/^job_cpu$/ || $item =~ m/^waj$/ || $item =~ m/^disk_io$/ ) { print "<div id='hiw'><a href=\"http://www.lpar2rrd.com/wrkactjob.htm\">How it works</a></div>\n"; }
      if ( $item =~ m/disk_busy/ )                                               { print "<div id='hiw'><a href=\"http://www.lpar2rrd.com/as400_help.htm\">How it works</a></div>\n"; }
      if ( $item =~ m/^jobs$/ )                                                  { print "<div id='hiw'><a href=\"http://www.lpar2rrd.com/job-top.htm\">How it works</a></div>\n"; }
      if ( $item =~ m/^queue_cpu$/ )                                             { print "<div id='hiw'><a href=\"https://www.lpar2rrd.com/CPU-queue.php\">How it works</a></div>\n"; }
      if ( $item =~ m/^error$/ )                                                 { print "<div id='hiw'><a href=\"https://www.lpar2rrd.com/FC-errors.php\">How it works</a></div>\n"; }

      print OUT "005 OS : $item \n" if $DEBUG == 2;
      print "\n<table align=\"center\" summary=\"Graphs\">\n";
      print "<h4>Disk Busy</h4>" if $item =~ m/disk_busy/;
      my $star_db = "star";
      if ( $item =~ m/jobs/ ) {
        print '<tr><td colspan="2" align="center"><h4>JOB CPU</h4></td></tr>';
        $star_db = "nostar";
      }
      print "<tr>\n";
      print_item( $host_url, $server_url, $lpar_url, $item, "d", $type_sam, $entitle, $detail_yes, "norefr", "star", 1, $legend );
      $false_picture = "do not print" if $false_picture ne "";
      my $week_or_month = "w";
      if ( defined $ENV{CUSTOMER} && $ENV{CUSTOMER} eq "PPF" && $item =~ m/job_cpu/ ) {
        $week_or_month = "m";
      }
      print_item( $host_url, $server_url, $lpar_url, $item, $week_or_month, $type_sam, $entitle, $detail_yes, "norefr", "$star_db", 1, $legend );
      print "</tr>\n";

      if ( $item !~ m/waj/ && $item !~ m/job_cpu/ && $item !~ m/disk_io/ && $item !~ m/disk_busy/ && $item !~ m/jobs/ ) {    # for this item do not prepare 'm' or 'y' graphs
        print "<tr>\n";

        #print STDERR "LINUX:$host_url, $server_url, $lpar_url, $item, d, m, $type_sam, $entitle, $detail_yes, norefr, star, 1, $legend\n";
        print_item( $host_url, $server_url, $lpar_url, $item, "m", $type_sam,      $entitle, $detail_yes, "norefr", "star", 1, $legend );
        print_item( $host_url, $server_url, $lpar_url, $item, "y", $type_sam_year, $entitle, $detail_yes, "norefr", "star", 1, $legend );
        print "</tr>\n";
      }
      if ( $item eq "mem" ) {                                                                                                # trend for memory from OS agent
        print_item( $host_url, $server_url, $lpar_url, "mem_trend", "y", $type_sam_year, $entitle, $detail_yes, "norefr", "nostar", 2, "legend" );
      }
      if ( $item eq "jobs" ) {
        print "</table>";
        print "<table align=\"center\" summary=\"Graphs\">\n";
        $item = "jobs_mem";
        print "<tr><td colspan=\"2\" align=\"center\"><h4>JOB MEM</h4></td></tr>\n";
        print "<tr>\n";
        print_item( $host_url, $server_url, $lpar_url, $item, "d", $type_sam,      $entitle, $detail_yes, "norefr", "star", 1, $legend );
        print_item( $host_url, $server_url, $lpar_url, $item, "w", $type_sam_year, $entitle, $detail_yes, "norefr", "star", 1, $legend );
        print "</tr>\n";
      }
      if ( $item =~ m/disk_busy/ ) {    # AS400 disk: upper graphs are 'busy', lower graphs are IOPS
        print "</table>";
        print "<table align=\"center\" summary=\"Graphs\">\n";
        $item = "disks";
        print "<tr><td colspan=\"2\" align=\"center\"><h4>Disk IO aggregated</h4></td></tr>\n";
        print "<tr>\n";
        print_item( $host_url, $server_url, $lpar_url, $item, "d", $type_sam,      $entitle, $detail_yes, "norefr", "star", 1, $legend );
        print_item( $host_url, $server_url, $lpar_url, $item, "w", $type_sam_year, $entitle, $detail_yes, "norefr", "star", 1, $legend );
        print "</tr>\n";
      }
      if ( $item =~ m/data_ifcb/ ) {
        print "</table>";
        print "<table align=\"center\" summary=\"Graphs\">\n";
        print "<tr><td colspan=\"2\" align=\"center\"><h4>Packets IFCB</h4></td></tr>\n";
        $item = "paket_ifcb";
        print "<tr>\n";
        print_item( $host_url, $server_url, $lpar_url, $item, "d", $type_sam, $entitle, $detail_yes, "norefr", "star", 1, "$legend" );
        print_item( $host_url, $server_url, $lpar_url, $item, "w", $type_sam, $entitle, $detail_yes, "norefr", "star", 1, "$legend" );
        print "</tr>\n<tr>\n";
        print_item( $host_url, $server_url, $lpar_url, $item, "m", $type_sam,      $entitle, $detail_yes, "norefr", "star", 1, "$legend" );
        print_item( $host_url, $server_url, $lpar_url, $item, "y", $type_sam_year, $entitle, $detail_yes, "norefr", "star", 1, "$legend" );
        print "</tr>\n";

        print "<tr><td colspan=\"2\" align=\"center\"><h4>Packets Discarded IFCB</h4></td></tr>\n";
        $item = "dpaket_ifcb";
        print "<tr>\n";
        print_item( $host_url, $server_url, $lpar_url, $item, "d", $type_sam, $entitle, $detail_yes, "norefr", "star", 1, "$legend" );
        print_item( $host_url, $server_url, $lpar_url, $item, "w", $type_sam, $entitle, $detail_yes, "norefr", "star", 1, "$legend" );
        print "</tr>\n<tr>\n";
        print_item( $host_url, $server_url, $lpar_url, $item, "m", $type_sam,      $entitle, $detail_yes, "norefr", "star", 1, "$legend" );
        print_item( $host_url, $server_url, $lpar_url, $item, "y", $type_sam_year, $entitle, $detail_yes, "norefr", "star", 1, "$legend" );
        print "</tr>\n";
      }
      if ( $item =~ m/dsk_latency/ && $false_picture eq "" ) {
        print "</table>";
        print "<table align=\"center\" summary=\"Graphs\">\n";
        print "<tr><td colspan=\"2\" align=\"center\"><h4>DSK SERVICE</h4></td></tr>\n";
        $item = "dsk_svc_as";
        print "<tr>\n";
        print_item( $host_url, $server_url, $lpar_url, $item, "d", $type_sam, $entitle, $detail_yes, "norefr", "star", 1, "$legend" );
        print_item( $host_url, $server_url, $lpar_url, $item, "w", $type_sam, $entitle, $detail_yes, "norefr", "star", 1, "$legend" );
        print "</tr>\n<tr>\n";
        print_item( $host_url, $server_url, $lpar_url, $item, "m", $type_sam,      $entitle, $detail_yes, "norefr", "star", 1, "$legend" );
        print_item( $host_url, $server_url, $lpar_url, $item, "y", $type_sam_year, $entitle, $detail_yes, "norefr", "star", 1, "$legend" );
        print "</tr>\n";

        print "<tr><td colspan=\"2\" align=\"center\"><h4>DSK WAIT</h4></td></tr>\n";
        $item = "dsk_wait_as";
        print "<tr>\n";
        print_item( $host_url, $server_url, $lpar_url, $item, "d", $type_sam, $entitle, $detail_yes, "norefr", "star", 1, "$legend" );
        print_item( $host_url, $server_url, $lpar_url, $item, "w", $type_sam, $entitle, $detail_yes, "norefr", "star", 1, "$legend" );
        print "</tr>\n<tr>\n";
        print_item( $host_url, $server_url, $lpar_url, $item, "m", $type_sam,      $entitle, $detail_yes, "norefr", "star", 1, "$legend" );
        print_item( $host_url, $server_url, $lpar_url, $item, "y", $type_sam_year, $entitle, $detail_yes, "norefr", "star", 1, "$legend" );
        print "</tr>\n";
      }
      if ( $item =~ m/cap_used/ ) {
        print "</table>";
        print "<table align=\"center\" summary=\"Graphs\">\n";
        print "<tr><td colspan=\"2\" align=\"center\"><h4>ASP % used</h4></td></tr>\n";
        $item = "cap_proc";
        print "<tr>\n";
        print_item( $host_url, $server_url, $lpar_url, $item, "d", $type_sam, $entitle, $detail_yes, "norefr", "star", 1, "$legend" );
        print_item( $host_url, $server_url, $lpar_url, $item, "w", $type_sam, $entitle, $detail_yes, "norefr", "star", 1, "$legend" );
        print "</tr>\n<tr>\n";
        print_item( $host_url, $server_url, $lpar_url, $item, "m", $type_sam,      $entitle, $detail_yes, "norefr", "star", 1, "$legend" );
        print_item( $host_url, $server_url, $lpar_url, $item, "y", $type_sam_year, $entitle, $detail_yes, "norefr", "star", 1, "$legend" );
        print "</tr>\n";
      }

      print "</table>\n";

      # summary graphs
      if ( $item =~ m/lan/ || $item eq "san1" || $item eq "san2" || $item =~ m/sea/ ) {
        my $sitem    = "s" . $item;
        my $text_sum = "Summary of transferred Bytes a Day";
        if ( $item =~ m/san2/ ) { $text_sum = "Summary of $iops a Day" }

        # print STDERR "1394 detail-cgi.pl $item,$sitem,$server_url\n";
        print "<br><table align=\"center\" summary=\"Graphs\">\n";
        print "<tr><td colspan=\"2\"><hr></td></tr>\n";
        print "<tr><td colspan=\"2\" align=\"center\"><h4>$text_sum</h4></td></tr>\n";
        print "<tr>\n";

        # no details, no zoom, no problem
        print_item( $host_url, $server_url, $lpar_url, $sitem, "m", $type_sam,      $entitle, $detail_yes, "norefr", "star", 1, "legend" );
        print_item( $host_url, $server_url, $lpar_url, $sitem, "y", $type_sam_year, $entitle, $detail_yes, "norefr", "star", 1, "legend" );
        print "</tr>\n";
        print "</table>\n";
      }
      if ( $item =~ m/lan/ || $item =~ m/sea/ ) {
        my $sitem = "packets_" . "$item";
        print "<br><table align=\"center\" summary=\"Graphs\">\n";
        print "<tr><td colspan=\"2\"><hr></td></tr>\n";
        print "<tr><td colspan=\"2\" align=\"center\"><h4>Packets</h4></td></tr>\n";
        print "<tr>\n";
        print_item( $host_url, $server_url, $lpar_url, $sitem, "d", $type_sam,      $entitle, $detail_yes, "norefr", "star", 1, "nolegend" );
        print_item( $host_url, $server_url, $lpar_url, $sitem, "w", $type_sam_year, $entitle, $detail_yes, "norefr", "star", 1, "nolegend" );
        print "</tr>\n<tr>\n";
        print_item( $host_url, $server_url, $lpar_url, $sitem, "m", $type_sam,      $entitle, $detail_yes, "norefr", "star", 1, "nolegend" );
        print_item( $host_url, $server_url, $lpar_url, $sitem, "y", $type_sam_year, $entitle, $detail_yes, "norefr", "star", 1, "nolegend" );
        print "</tr>\n";
        print "</table>\n";
      }
      print "</center></div>\n\n";
      $tab_number++;
      $false_picture = "";
    }
  }
}

sub rrd_from_active_hmc {
  my $server              = shift;
  my $rrd_path            = shift;
  my $rrd_old             = shift;
  my $active_rrd          = $rrd_old;
  my $active_rrd_last_upd = ( stat("$active_rrd") )[9];

  # find all hmcs
  opendir( DIR, "$wrkdir/$server" ) || error( "can't opendir $wrkdir/$server: $! :" . __FILE__ . ":" . __LINE__ ) && exit;
  my @hmc_list = grep !/^\.\.?$/, readdir(DIR);
  closedir(DIR);
  chomp @hmc_list;

  foreach my $hmc (@hmc_list) {
    if ( -f "$wrkdir/$server/$hmc/$rrd_path" && $active_rrd ne "$wrkdir/$server/$hmc/$rrd_path" ) {
      my $rrd_last_upd = ( stat("$wrkdir/$server/$hmc/$rrd_path") )[9];
      if ( defined $active_rrd_last_upd && $rrd_last_upd > $active_rrd_last_upd ) {
        $active_rrd          = "$wrkdir/$server/$hmc/$rrd_path";
        $active_rrd_last_upd = $rrd_last_upd;
      }
    }
  }

  return $active_rrd;
}

sub build_agents_tabs {

  my $server     = shift;
  my $host       = shift;
  my $lpar_slash = shift;
  if ( $entitle == 0 && test_file_in_directory( "$wrkdir/$server/$host/$lpar_slash", "cpu" ) ) {
    $item_agent[$item_agent_indx] = "oscpu";
    $tab_number++;
    $os_agent = $tab_number;
    print "  <li class='tabagent'><a href=\"#tabs-$tab_number\">CPU OS</a></li>\n";
    $item_agent_tab[$item_agent_indx] = $tab_number;
    $item_agent_indx++;
  }
  if ( $entitle == 0 && -f "$wrkdir/$server/$host/$lpar_slash/linux_cpu.mmm" ) {
    $item_agent[$item_agent_indx] = "cpu-linux";
    $tab_number++;
    $os_agent = $tab_number;
    print "  <li class='tabagent'><a href=\"#tabs-$tab_number\">CPU Core</a></li>\n";
    $item_agent_tab[$item_agent_indx] = $tab_number;
    $item_agent_indx++;
  }
  if ( $entitle == 0 && test_file_in_directory( "$wrkdir/$server/$host/$lpar_slash", "queue_cpu" ) || test_file_in_directory( "$wrkdir/$server/$host/$lpar_slash", "queue_cpu_aix" ) ) {
    $item_agent[$item_agent_indx] = "queue_cpu";
    $tab_number++;
    $os_agent = $tab_number;
    print "  <li class='tabagent'><a href=\"#tabs-$tab_number\">CPU Queue</a></li>\n";
    $item_agent_tab[$item_agent_indx] = $tab_number;
    $item_agent_indx++;
  }
  if ( $entitle == 0 && -f "$wrkdir/$server/$host/$lpar_slash/JOB/cputop0.mmc" ) {
    $item_agent[$item_agent_indx] = "jobs";
    $tab_number++;
    $os_agent = $tab_number;
    print "  <li class='tabagent'><a href=\"#tabs-$tab_number\">JOB</a></li>\n";
    $item_agent_tab[$item_agent_indx] = $tab_number;
    $item_agent_indx++;
  }
  if ( test_file_in_directory( "$wrkdir/$server/$host/$lpar_slash", "mem" ) ) {
    $item_agent[$item_agent_indx] = "mem";
    $tab_number++;
    $os_agent = $tab_number;
    my $name_m = "Memory";
    if ( $server =~ /Solaris--unknown|Solaris\d+--unknown/ ) { $name_m = "Memory OS"; }
    print "  <li class='tabagent'><a href=\"#tabs-$tab_number\">$name_m</a></li>\n";
    $item_agent_tab[$item_agent_indx] = $tab_number;
    $item_agent_indx++;
  }
  #
  # KZ: mapping lpar -> volume (stor2rrd)
  #
  if ( exists $ENV{HTTP_XORUX_APP} && $ENV{HTTP_XORUX_APP} eq "Xormon" ) {
    my $lpar_uid = PowerDataWrapper::get_item_uid( { type => "VM", label => $lpar_slash } );

    if ( defined $lpar_uid && $lpar_uid ne "" ) {
      my $prop = SQLiteDataWrapper::getItemProperties( { item_id => $lpar_uid } );
      if ( exists $prop->{disk_uids} && $prop->{disk_uids} ne '' ) {
        @lpar2volumes = split( /\s+/, $prop->{disk_uids} );

        $item_agent[$item_agent_indx] = "lpar2volumes";
        $tab_number++;
        $os_agent = $tab_number;
        print "  <li class='tabagent lpar2volumes'><a href=\"#tabs-$tab_number\">Volumes</a></li>\n";
        $item_agent_tab[$item_agent_indx] = $tab_number;
        $item_agent_indx++;
      }
    }
  }
  if ( $entitle == 0 && test_file_in_directory( "$wrkdir/$server/$host/$lpar_slash", "pgs" ) ) {
    $item_agent[$item_agent_indx] = "pg1";
    $tab_number++;
    $os_agent = $tab_number;
    print "  <li class='tabagent'><a href=\"#tabs-$tab_number\">Paging 1</a></li>\n";
    $item_agent_tab[$item_agent_indx] = $tab_number;
    $item_agent_indx++;
    if ( $wpar == 0 ) {

      # exclude that from WPARs as it is exactly same as on hosted LPAR
      $item_agent[$item_agent_indx] = "pg2";
      $tab_number++;
      $os_agent = $tab_number;
      print "  <li class='tabagent'><a href=\"#tabs-$tab_number\">Paging 2</a></li>\n";
      $item_agent_tab[$item_agent_indx] = $tab_number;
      $item_agent_indx++;
    }
  }
  if ( $entitle == 0 && test_file_in_directory( "$wrkdir/$server/$host/$lpar_slash", "lan" ) ) {
    $item_agent[$item_agent_indx] = "lan";
    $tab_number++;
    $os_agent = $tab_number;
    print "  <li class='tabagent'><a href=\"#tabs-$tab_number\">LAN</a></li>\n";
    $item_agent_tab[$item_agent_indx] = $tab_number;
    $item_agent_indx++;
  }
  if ( $entitle == 0 && test_file_in_directory( "$wrkdir/$server/$host/$lpar_slash", "lan_error" ) ) {
    $item_agent[$item_agent_indx] = "error_lan";
    $tab_number++;
    $os_agent = $tab_number;
    print "  <li class='tabagent'><a href=\"#tabs-$tab_number\">LAN ERROR</a></li>\n";
    $item_agent_tab[$item_agent_indx] = $tab_number;
    $item_agent_indx++;
  }
  if ( $entitle == 0 && test_file_in_directory( "$wrkdir/$server/$host/$lpar_slash", "san-" ) ) {
    $item_agent[$item_agent_indx] = "san1";
    $tab_number++;
    $os_agent = $tab_number;
    print "  <li class='tabagent'><a href=\"#tabs-$tab_number\">SAN</a></li>\n";
    $item_agent_tab[$item_agent_indx] = $tab_number;
    $item_agent_indx++;
    $item_agent[$item_agent_indx] = "san2";
    $tab_number++;
    $os_agent = $tab_number;
    my $iops_type = "IOPS";

    if ( !-f "$wrkdir/$server/$host/$lpar_slash/cpu.txt" ) {

      # Linux --> there are not IOPS but SAN Frames
      $iops_type = "Frames";
    }
    print "  <li class='tabagent'><a href=\"#tabs-$tab_number\">SAN $iops_type</a></li>\n";
    $item_agent_tab[$item_agent_indx] = $tab_number;
    $item_agent_indx++;
  }
  if ( $entitle == 0 && test_file_in_directory( "$wrkdir/$server/$host/$lpar_slash", "san_resp" ) ) {
    $item_agent[$item_agent_indx] = "san_resp";
    $tab_number++;
    $os_agent = $tab_number;
    print "  <li class='tabagent'><a href=\"#tabs-$tab_number\">SAN RESP</a></li>\n";
    $item_agent_tab[$item_agent_indx] = $tab_number;
    $item_agent_indx++;
  }
  if ( $entitle == 0 && test_file_in_directory( "$wrkdir/$server/$host/$lpar_slash", "san_error" ) ) {
    $item_agent[$item_agent_indx] = "error_san";
    $tab_number++;
    $os_agent = $tab_number;
    print "  <li class='tabagent'><a href=\"#tabs-$tab_number\">SAN ERROR</a></li>\n";
    $item_agent_tab[$item_agent_indx] = $tab_number;
    $item_agent_indx++;
  }
  if ( $entitle == 0 && test_file_in_directory( "$wrkdir/$server/$host/$lpar_slash", "ame" ) ) {
    $item_agent[$item_agent_indx] = "ame";
    $tab_number++;
    $os_agent = $tab_number;
    print "  <li class='tabagent'><a href=\"#tabs-$tab_number\">AME</a></li>\n";
    $item_agent_tab[$item_agent_indx] = $tab_number;
    $item_agent_indx++;
  }
  if ( $entitle == 0 && test_file_in_directory( "$wrkdir/$server/$host/$lpar_slash", "sea" ) ) {
    $item_agent[$item_agent_indx] = "sea";
    $tab_number++;
    $os_agent = $tab_number;
    print "  <li class='tabagent'><a href=\"#tabs-$tab_number\">SEA</a></li>\n";
    $item_agent_tab[$item_agent_indx] = $tab_number;
    $item_agent_indx++;
  }
  if ( $entitle == 0 && test_file_in_directory( "$wrkdir/$server/$host/$lpar_slash", "disk-total" ) ) {
    $item_agent[$item_agent_indx] = "total_iops";
    $tab_number++;
    $os_agent = $tab_number;
    print "  <li class='tabagent'><a href=\"#tabs-$tab_number\">IOPS</a></li>\n";
    $item_agent_tab[$item_agent_indx] = $tab_number;
    $item_agent_indx++;
  }
  if ( $entitle == 0 && test_file_in_directory( "$wrkdir/$server/$host/$lpar_slash", "disk-total" ) ) {
    $item_agent[$item_agent_indx] = "total_data";
    $tab_number++;
    $os_agent = $tab_number;
    print "  <li class='tabagent'><a href=\"#tabs-$tab_number\">DATA</a></li>\n";
    $item_agent_tab[$item_agent_indx] = $tab_number;
    $item_agent_indx++;
  }
  if ( $entitle == 0 && test_file_in_directory( "$wrkdir/$server/$host/$lpar_slash", "disk-total" ) ) {
    $item_agent[$item_agent_indx] = "total_latency";
    $tab_number++;
    $os_agent = $tab_number;
    print "  <li class='tabagent'><a href=\"#tabs-$tab_number\">Latency</a></li>\n";
    $item_agent_tab[$item_agent_indx] = $tab_number;
    $item_agent_indx++;
  }
  if ( $entitle == 0 && test_file_in_directory( "$wrkdir/$server/$host/$lpar_slash", "wlm" ) ) {

    #my $is_nusage    = test_metric_in_rrd( "vmware_VMs", "", "$lpar.rrm", $item, "Network_usage" );
    my $wlm_cpu  = "";
    my $wlm_mem  = "";
    my $wlm_dkio = "";
    opendir( DIR, "$wrkdir/$server/$host/$lpar_slash" ) || error( "Error in opening dir \"$wrkdir/$server/$host/$lpar_slash\" $! :" . __FILE__ . ":" . __LINE__ ) && return 0;
    my @wlm_files = readdir(DIR);
    closedir(DIR);
    foreach my $each (@wlm_files) {
      next if ( $each !~ /wlm-/ );
      my $lpar_slash_file = $lpar_slash;
      $lpar_slash_file .= "/$each";

      #$wlm_cpu = test_metric_in_rrd ( $server, $host, $lpar_slash_file, "wlm", "wlm_cpu" );
      #$wlm_mem = test_metric_in_rrd ( $server, $host, $lpar_slash_file, "wlm", "wlm_mem" );
      #$wlm_cpu = test_metric_in_rrd ( $server, $host, $lpar_slash_file, "wlm", "wlm_dkio");
      if ( test_metric_in_rrd( $server, $host, $lpar_slash_file, "wlm", "wlm_cpu" ) ) {
        $wlm_cpu = 1;
      }
      if ( test_metric_in_rrd( $server, $host, $lpar_slash_file, "wlm", "wlm_mem" ) ) {
        $wlm_mem = 1;
      }
      if ( test_metric_in_rrd( $server, $host, $lpar_slash_file, "wlm", "wlm_dkio" ) ) {
        $wlm_dkio = 1;
      }

      #my ( $server, $host, $lpar, $item, $ds ) = @_;
    }

    #return $found;
    if ( ( !$wlm_cpu eq "" && isdigit($wlm_cpu) && $wlm_cpu == 1 ) || $lpar_slash !~ /\// ) {
      $item_agent[$item_agent_indx] = "wlm-cpu";
      $tab_number++;
      $os_agent = $tab_number;
      print "  <li class='tabagent'><a href=\"#tabs-$tab_number\">WLM-CPU</a></li>\n";
      $item_agent_tab[$item_agent_indx] = $tab_number;
      $item_agent_indx++;
    }
    if ( ( !$wlm_mem eq "" && isdigit($wlm_mem) && $wlm_mem == 1 ) || $lpar_slash !~ /\// ) {
      $item_agent[$item_agent_indx] = "wlm-mem";
      $tab_number++;
      $os_agent = $tab_number;
      print "  <li class='tabagent'><a href=\"#tabs-$tab_number\">WLM-MEM</a></li>\n";
      $item_agent_tab[$item_agent_indx] = $tab_number;
      $item_agent_indx++;
    }
    if ( ( !$wlm_dkio eq "" && isdigit($wlm_dkio) && $wlm_dkio == 1 ) || $lpar_slash !~ /\// ) {
      $item_agent[$item_agent_indx] = "wlm-dkio";
      $tab_number++;
      $os_agent = $tab_number;
      print "  <li class='tabagent'><a href=\"#tabs-$tab_number\">WLM-DKIO</a></li>\n";
      $item_agent_tab[$item_agent_indx] = $tab_number;
      $item_agent_indx++;
    }
  }
  if ( $entitle == 0 && test_file_in_directory( "$wrkdir/$server/$host/$lpar_slash", "FS", "csv" ) ) {
    $item_agent[$item_agent_indx] = "file_sys";
    $tab_number++;
    $os_agent = $tab_number;
    print "  <li class='tabagent'><a href=\"#tabs-$tab_number\">FS</a></li>\n";
    $item_agent_tab[$item_agent_indx] = $tab_number;
    $item_agent_indx++;
  }
  if ( $entitle == 0 && $item eq "lpar" && test_file_in_directory( "$wrkdir/Solaris/$lpar_slash", "san-c" ) ) {
    $item_agent[$item_agent_indx] = "solaris_ldom_san1";
    $tab_number++;
    $os_agent = $tab_number;
    print "  <li class='tabagent'><a href=\"#tabs-$tab_number\">SAN</a></li>\n";
    $item_agent_tab[$item_agent_indx] = $tab_number;    #### without ldoms
    $item_agent_indx++;
  }
  if ( $entitle == 0 && $item eq "lpar" && test_file_in_directory( "$wrkdir/Solaris/$lpar_slash", "san-c" ) ) {
    $item_agent[$item_agent_indx] = "solaris_ldom_san2";    #### without ldoms
    $tab_number++;
    $os_agent = $tab_number;
    print "  <li class='tabagent'><a href=\"#tabs-$tab_number\">SAN IOPS</a></li>\n";
    $item_agent_tab[$item_agent_indx] = $tab_number;
    $item_agent_indx++;
  }
  if ( $entitle == 0 && $item eq "lpar" && test_file_in_directory( "$wrkdir/Solaris/$lpar_slash", "san_tresp" ) ) {
    $item_agent[$item_agent_indx] = "solaris_ldom_san_resp";    #### without ldoms
    $tab_number++;
    $os_agent = $tab_number;
    print "  <li class='tabagent'><a href=\"#tabs-$tab_number\">SAN RESP</a></li>\n";
    $item_agent_tab[$item_agent_indx] = $tab_number;
    $item_agent_indx++;
  }
  if ( $entitle == 0 && test_file_in_directory( "$wrkdir/$server/$host/$lpar_slash", "aix_multipathing", "txt" ) ) {
    $item_agent[$item_agent_indx] = "lsdisk";
    $tab_number++;
    $os_agent = $tab_number;
    print "  <li class='tabagent'><a href=\"#tabs-$tab_number\">MULTIPATH</a></li>\n";
    $item_agent_tab[$item_agent_indx] = $tab_number;
    $item_agent_indx++;
  }
  if ( $entitle == 0 && test_file_in_directory( "$wrkdir/$server/$host/$lpar_slash", "linux_multipathing", "txt" ) ) {
    $item_agent[$item_agent_indx] = "path_lin";
    $tab_number++;
    $os_agent = $tab_number;
    print "  <li class='tabagent'><a href=\"#tabs-$tab_number\">MULTIPATH</a></li>\n";
    $item_agent_tab[$item_agent_indx] = $tab_number;
    $item_agent_indx++;
  }

  # NMON
  if ( -d "$wrkdir/$server/$host/$lpar_slash$NMON" ) {
    if ( $entitle == 0 && test_file_in_directory( "$wrkdir/$server/$host/$lpar_slash$NMON", "cpu" ) ) {
      $item_agent[$item_agent_indx] = "nmon-oscpu";
      $tab_number++;
      $nmon_agent = $tab_number;
      print "  <li class='tabnmon'><a href=\"#tabs-$tab_number\">CPU OS [N]</a></li>\n";
      $item_agent_tab[$item_agent_indx] = $tab_number;
      $item_agent_indx++;
    }
    if ( $entitle == 0 && test_file_in_directory( "$wrkdir/$server/$host/$lpar_slash$NMON", "queue_cpu" ) || test_file_in_directory( "$wrkdir/$server/$host/$lpar_slash$NMON", "queue_cpu_aix" ) ) {
      $item_agent[$item_agent_indx] = "nmon-queue_cpu";
      $tab_number++;
      $nmon_agent = $tab_number;
      print "  <li class='tabagent'><a href=\"#tabs-$tab_number\">CPU Queue [N]</a></li>\n";
      $item_agent_tab[$item_agent_indx] = $tab_number;
      $item_agent_indx++;
    }
    if ( test_file_in_directory( "$wrkdir/$server/$host/$lpar_slash$NMON", "mem" ) ) {
      $item_agent[$item_agent_indx] = "nmon-mem";
      $tab_number++;
      $nmon_agent = $tab_number;
      print "  <li class='tabnmon'><a href=\"#tabs-$tab_number\">Memory [N]</a></li>\n";
      $item_agent_tab[$item_agent_indx] = $tab_number;
      $item_agent_indx++;
    }
    if ( $entitle == 0 && test_file_in_directory( "$wrkdir/$server/$host/$lpar_slash$NMON", "pgs" ) ) {
      $item_agent[$item_agent_indx] = "nmon-pg1";
      $tab_number++;
      $nmon_agent = $tab_number;
      print "  <li class='tabnmon'><a href=\"#tabs-$tab_number\">Paging [N]</a></li>\n";
      $item_agent_tab[$item_agent_indx] = $tab_number;
      $item_agent_indx++;
      if ( $wpar == 0 ) {

        # exclude that from WPARs as it is exactly same as on hosted LPAR
        $item_agent[$item_agent_indx] = "nmon-pg2";
        $tab_number++;
        $nmon_agent = $tab_number;
        print "  <li class='tabnmon'><a href=\"#tabs-$tab_number\">Paging 2 [N]</a></li>\n";
        $item_agent_tab[$item_agent_indx] = $tab_number;
        $item_agent_indx++;
      }
    }
    if ( $entitle == 0 && test_file_in_directory( "$wrkdir/$server/$host/$lpar_slash$NMON", "lan" ) ) {
      $item_agent[$item_agent_indx] = "nmon-lan";
      $tab_number++;
      $nmon_agent = $tab_number;
      print "  <li class='tabnmon'><a href=\"#tabs-$tab_number\">LAN [N]</a></li>\n";
      $item_agent_tab[$item_agent_indx] = $tab_number;
      $item_agent_indx++;
    }
    if ( $entitle == 0 && test_file_in_directory( "$wrkdir/$server/$host/$lpar_slash$NMON", "san-" ) ) {
      $item_agent[$item_agent_indx] = "nmon-san1";
      $tab_number++;
      $nmon_agent = $tab_number;
      print "  <li class='tabnmon'><a href=\"#tabs-$tab_number\">SAN [N]</a></li>\n";
      $item_agent_tab[$item_agent_indx] = $tab_number;
      $item_agent_indx++;
      $item_agent[$item_agent_indx] = "nmon-san2";
      $tab_number++;
      $nmon_agent = $tab_number;

      if ( test_file_in_directory( "$wrkdir/$server/$host/$lpar_slash$NMON", "san-host" ) ) {

        # Linux --> there are not IOPS but SAN Frames
        $iops = "Frames";
      }
      print "  <li class='tabnmon'><a href=\"#tabs-$tab_number\">SAN $iops [N]</a></li>\n";
      $item_agent_tab[$item_agent_indx] = $tab_number;
      $item_agent_indx++;
    }
    if ( $entitle == 0 && test_file_in_directory( "$wrkdir/$server/$host/$lpar_slash$NMON", "ame" ) ) {
      $item_agent[$item_agent_indx] = "nmon-ame";
      $tab_number++;
      $nmon_agent = $tab_number;
      print "  <li class='tabnmon'><a href=\"#tabs-$tab_number\">AME [N]</a></li>\n";
      $item_agent_tab[$item_agent_indx] = $tab_number;
      $item_agent_indx++;
    }
    if ( $entitle == 0 && test_file_in_directory( "$wrkdir/$server/$host/$lpar_slash$NMON", "sea" ) ) {
      $item_agent[$item_agent_indx] = "nmon-sea";
      $tab_number++;
      $nmon_agent = $tab_number;
      print "  <li class='tabnmon'><a href=\"#tabs-$tab_number\">SEA [N]</a></li>\n";
      $item_agent_tab[$item_agent_indx] = $tab_number;
      $item_agent_indx++;
    }
  }

  # NMON end

  # AS400 agent tabs
  # print STDERR "testing AS400 $wrkdir/$server/$host/$lpar_slash$AS400\n";
  if ( -d "$wrkdir/$server/$host/$lpar_slash$AS400" ) {
    if ( $entitle == 0 && test_file_in_directory( "$wrkdir/$server/$host/$lpar_slash$AS400", "S0200ASPJOB" ) ) {

      # print STDERR "detail-cgi.pl 573 $wrkdir/$server/$host/$lpar_slash, S0200ASPJOB\n";

      $item_agent[$item_agent_indx] = "job_cpu";
      $tab_number++;
      $os_agent = $tab_number;
      print "  <li class='tabagent'><a href=\"#tabs-$tab_number\">WRKACTJOB</a></li>\n";
      $item_agent_tab[$item_agent_indx] = $tab_number;
      $item_agent_indx++;

      $item_agent[$item_agent_indx] = "waj";
      $tab_number++;
      $os_agent = $tab_number;
      print "  <li class='tabagent'><a href=\"#tabs-$tab_number\">CPUTOP</a></li>\n";
      $item_agent_tab[$item_agent_indx] = $tab_number;
      $item_agent_indx++;

      $item_agent[$item_agent_indx] = "disk_io";
      $tab_number++;
      $os_agent = $tab_number;
      print "  <li class='tabagent'><a href=\"#tabs-$tab_number\">IOTOP</a></li>\n";
      $item_agent_tab[$item_agent_indx] = $tab_number;
      $item_agent_indx++;

      if ( $entitle == 0 && test_file_in_directory( "$wrkdir/$server/$host/$lpar_slash$AS400/DSK", ".*", "mmc" ) ) {
        $item_agent[$item_agent_indx] = "disk_busy";
        $tab_number++;
        $os_agent = $tab_number;
        print "  <li class='tabagent'><a href=\"#tabs-$tab_number\">DISKTOP</a></li>\n";
        $item_agent_tab[$item_agent_indx] = $tab_number;
        $item_agent_indx++;
      }

      $item_agent[$item_agent_indx] = "S0200ASPJOB";
      $tab_number++;
      $os_agent = $tab_number;
      print "  <li class='tabagent'><a href=\"#tabs-$tab_number\">JOBS</a></li>\n";
      $item_agent_tab[$item_agent_indx] = $tab_number;
      $item_agent_indx++;

      #$item_agent[$item_agent_indx] = "ASP" ;
      #$tab_number++;
      #$os_agent = $tab_number;
      #print "  <li class='tabagent'><a href=\"#tabs-$tab_number\">ASP</a></li>\n";
      #$item_agent_tab[$item_agent_indx] = $tab_number;
      #$item_agent_indx++;

      $item_agent[$item_agent_indx] = "size";
      $tab_number++;
      $os_agent = $tab_number;
      print "  <li class='tabagent'><a href=\"#tabs-$tab_number\">POOL SIZE</a></li>\n";
      $item_agent_tab[$item_agent_indx] = $tab_number;
      $item_agent_indx++;

      # excluded - not interesting metric
      #$item_agent[$item_agent_indx] = "res" ;
      #$tab_number++;
      #$os_agent = $tab_number;
      #print "  <li class='tabagent'><a href=\"#tabs-$tab_number\">POOL RES</a></li>\n";
      #$item_agent_tab[$item_agent_indx] = $tab_number;
      #$item_agent_indx++;

      $item_agent[$item_agent_indx] = "threads";
      $tab_number++;
      $os_agent = $tab_number;
      print "  <li class='tabagent'><a href=\"#tabs-$tab_number\">THREADS</a></li>\n";
      $item_agent_tab[$item_agent_indx] = $tab_number;
      $item_agent_indx++;

      $item_agent[$item_agent_indx] = "faults";
      $tab_number++;
      $os_agent = $tab_number;
      print "  <li class='tabagent'><a href=\"#tabs-$tab_number\">FAULTS</a></li>\n";
      $item_agent_tab[$item_agent_indx] = $tab_number;
      $item_agent_indx++;

      $item_agent[$item_agent_indx] = "pages";
      $tab_number++;
      $os_agent = $tab_number;
      print "  <li class='tabagent'><a href=\"#tabs-$tab_number\">PAGES</a></li>\n";
      $item_agent_tab[$item_agent_indx] = $tab_number;
      $item_agent_indx++;

      # excluded - not interesting metric
      #$item_agent[$item_agent_indx] = "ADDR" ;
      #$tab_number++;
      #$os_agent = $tab_number;
      #print "  <li class='tabagent'><a href=\"#tabs-$tab_number\">ADDR</a></li>\n";
      #$item_agent_tab[$item_agent_indx] = $tab_number;
      #$item_agent_indx++;

      $item_agent[$item_agent_indx] = "cap_used";
      $tab_number++;
      $os_agent = $tab_number;
      print "  <li class='tabagent'><a href=\"#tabs-$tab_number\">ASP USED</a></li>\n";
      $item_agent_tab[$item_agent_indx] = $tab_number;
      $item_agent_indx++;

      $item_agent[$item_agent_indx] = "cap_free";
      $tab_number++;
      $os_agent = $tab_number;
      print "  <li class='tabagent'><a href=\"#tabs-$tab_number\">ASP FREE</a></li>\n";
      $item_agent_tab[$item_agent_indx] = $tab_number;
      $item_agent_indx++;

      $item_agent[$item_agent_indx] = "data_as";
      $tab_number++;
      $os_agent = $tab_number;
      print "  <li class='tabagent'><a href=\"#tabs-$tab_number\">ASP DATA</a></li>\n";
      $item_agent_tab[$item_agent_indx] = $tab_number;
      $item_agent_indx++;

      $item_agent[$item_agent_indx] = "iops_as";
      $tab_number++;
      $os_agent = $tab_number;
      print "  <li class='tabagent'><a href=\"#tabs-$tab_number\">ASP IOPS</a></li>\n";
      $item_agent_tab[$item_agent_indx] = $tab_number;
      $item_agent_indx++;

      if ( $entitle == 0 ) {    # && test_file_in_directory( "$wrkdir/$server/$host/$lpar_slash$AS400/LTC", ".*", "mmc" ) ) left_curly  # always prepare tabs
        $item_agent[$item_agent_indx] = "dsk_latency";
        $tab_number++;
        $os_agent = $tab_number;
        print "  <li class='tabagent'><a href=\"#tabs-$tab_number\">ASP LATENCY</a></li>\n";
        $item_agent_tab[$item_agent_indx] = $tab_number;
        $item_agent_indx++;
      }

      if ( $entitle == 0 && test_file_in_directory( "$wrkdir/$server/$host/$lpar_slash$AS400/IFC", ".*", "mmc" ) ) {
        $item_agent[$item_agent_indx] = "data_ifcb";
        $tab_number++;
        $os_agent = $tab_number;
        print "  <li class='tabagent'><a href=\"#tabs-$tab_number\">LAN</a></li>\n";
        $item_agent_tab[$item_agent_indx] = $tab_number;
        $item_agent_indx++;
      }
    }
  }
}

sub is_lpm {
  my $host      = shift;
  my $server    = shift;
  my $lpar      = shift;
  my $lpm       = shift;
  my $lpm_count = 0;

  if ( $lpm == 1 ) {
    my $lpm_suff = "rrl";

    # never use function "grab", grrrr ...
    my $server_space = $server;
    if ( $server =~ m/ / ) {    # workaround for server name with a space inside, nothing else works, grrr
      $server_space = "\"" . $server . "\"";
    }
    my $host_space = $host;
    if ( $host =~ m/ / ) {      # workaround for server name with a space inside, nothing else works, grrr
      $host_space = "\"" . $host . "\"";
    }
    my $lpar_space = $lpar;
    if ( $lpar =~ m/ / ) {      # workaround for server name with a space inside, nothing else works, grrr
      $lpar_space = "\"" . $lpar . "\"";
    }
    $lpar_space =~ s/\//&&1/g;

    foreach my $trash (<$wrkdir/$server_space/$host_space/$lpar_space=====*=====*.$lpm_suff>) {
      $lpm_count++;
    }
    $lpm_suff = "rrk";
    foreach my $trash (<$wrkdir/$server_space/$host_space/$lpar_space=====*=====*.$lpm_suff>) {
      $lpm_count++;
    }
    $lpm_suff = "rri";
    foreach my $trash (<$wrkdir/$server_space/$host_space/$lpar_space=====*=====*.$lpm_suff>) {
      $lpm_count++;
    }

    # print STDERR "001 $host,$server,$lpar,$lpm : $lpm_count\n";

    if ( !-f "$wrkdir/$server/$host/lpm-exclude.txt" ) {
      return $lpm_count;
    }

    # if it is a VIO server then do not go for LPM
    # it is already being exlcuded in install-html.sh, this is just for sure
    my $lpm_excl = "$wrkdir/$server/$host/lpm-exclude.txt";
    open( FH, "< $lpm_excl" ) || return $lpm_count;
    my @lpm_excl_vio = <FH>;
    close(FH);

    foreach my $lpm_line (@lpm_excl_vio) {
      chomp($lpm_line);
      if ( "$lpm_line" =~ m/$lpar/ && length($lpm_line) == length($lpar) ) {

        #print STDERR "LPM VIO exclude: $host:$server:$lpar: - $lpm_line\n" if $DEBUG ;
        $lpm_count = 0;
        last;
      }
    }
  }

  #print STDERR "002 $host,$server,$lpar,$lpm : $lpm_count\n";

  return $lpm_count;
}

sub type_sam {
  my $host       = shift;
  my $server     = shift;
  my $lpar       = shift;
  my $yearly     = shift;
  my $lpar_slash = shift;

  if ( $yearly == 1 ) {
    if ( -f "$wrkdir/$server/$host/$lpar_slash.rrd" ) {
      return "d";
    }
    return "m";
  }

  if ( -f "$wrkdir/$server/$host/$lpar_slash.rrm" ) {
    return "m";
  }

  if ( -f "$wrkdir/$server/$host/$lpar_slash.rrh" ) {
    return "h";
  }

  return "m";
}

# find out max value to get fixed upper limit for all 4 graphs
sub rrd_upper {
  my $wrkdir        = shift;
  my $server        = shift;
  my $host          = shift;
  my $lpar          = shift;
  my $type_sam      = shift;
  my $type_sam_year = shift;
  my $item          = shift;
  my $lpar_slash    = shift;
  my $rrd           = "$wrkdir/$server/$host/$lpar_slash.rr$type_sam";

  if ( !-f "$rrd" || $item =~ m/^codused$/ || $item =~ m/^pagingagg$/ ) {

    # Capacity on demad also does not go here
    return 0;
  }

  my $rrdtool = $ENV{RRDTOOL};

  # start RRD via a pipe
  RRDp::start "$rrdtool";

  # print STDERR "------ rrd_upper 2 $wrkdir/$server/$host/$lpar_slash.rr$type_sam\n";

  my $ret   = find_rrd_upper( $rrd, "now-1d" );
  my $ret_w = find_rrd_upper( $rrd, "now-1w" );
  my $ret_m = find_rrd_upper( $rrd, "now-1m" );

  $rrd = "$wrkdir/$server/$host/$lpar_slash.rr$type_sam_year";
  if ( !-f "$rrd" ) {
    $rrd = "$wrkdir/$server/$host/$lpar_slash.rr$type_sam";
  }
  my $ret_y = find_rrd_upper( $rrd, "now-1y" );

  if ( $ret_w > $ret ) { $ret = $ret_w; }
  if ( $ret_m > $ret ) { $ret = $ret_m; }
  if ( $ret_y > $ret ) { $ret = $ret_y; }

  # close RRD pipe
  RRDp::end;

  return $ret;

}

sub find_rrd_upper {
  my $rrd        = shift;
  my $start_time = shift;

  $rrd =~ s/:/\\:/g;

  if ($vmware) {
    RRDp::cmd qq(graph "tmp/name.png"
    "--start" "$start_time"
    "--end" "now"
      "DEF:utl=$rrd:CPU_usage:AVERAGE"
    "PRINT:utl:MAX: %3.3lf"
  );
  }
  else {
    RRDp::cmd qq(graph "tmp/name.png"
      "--start" "$start_time"
      "--end" "now"
      "DEF:cur=$rrd:curr_proc_units:AVERAGE"
      "DEF:ent=$rrd:entitled_cycles:AVERAGE"
      "DEF:cap_peak=$rrd:capped_cycles:AVERAGE"
      "DEF:uncap=$rrd:uncapped_cycles:AVERAGE"
      "CDEF:cap=cap_peak,ent,/,1,GT,UNKN,cap_peak,IF"
      "CDEF:tot=cap,uncap,+"
      "CDEF:util=tot,ent,/,$cpu_max_filter,GT,UNKN,tot,ent,/,IF"
      "CDEF:utiltot=util,cur,*"
      "PRINT:utiltot:MAX: %3.3lf"
    );
  }
  my $answer = RRDp::read;

  if ( $$answer =~ m/NaN/ || $$answer =~ m/nan/ ) {
    return 0;
  }
  ( my $addr, my $max ) = split( / +/, $$answer );
  chomp($max);

  if ( isdigit($max) == 1 ) {
    return $max;
  }
  return 0;
}

# CoD  codunreport
sub print_cod {
  my ( $host_url, $server_url, $lpar_url, $item, $type_sam, $entitle, $upper ) = @_;

  print "<table align=\"center\" summary=\"Graphs\">\n";
  print OUT "006 CoD : $item \n" if $DEBUG == 2;

  #print "<tr><td colspan=\"2\" align=\"center\"><A NAME=COD></A> <H3>Capacity on Demand</H3> <BR></td></tr>\n";
  $item = "codunreport";
  print "<tr>";
  print_item( $host_url, $server_url, $lpar_url, $item, "d", $type_sam, $entitle, $detail_yes, "norefr", "nostar", 1, "legend" );
  print_item( $host_url, $server_url, $lpar_url, $item, "w", $type_sam, $entitle, $detail_yes, "norefr", "nostar", 1, "legend" );
  print "</tr>\n<tr>\n";
  print_item( $host_url, $server_url, $lpar_url, $item, "m", $type_sam,      $entitle, $detail_yes, "norefr", "nostar", 1, "legend" );
  print_item( $host_url, $server_url, $lpar_url, $item, "y", $type_sam_year, $entitle, $detail_yes, "norefr", "nostar", 1, "legend" );
  print "</tr></table>";

  return 1;
}

# print Lpar cfg table
sub print_lpar_cfg {
  my ( $host_url, $server_url, $lpar_url, $wrkdir, $server, $host, $lpar_slash, $lpar ) = @_;

  my $cfg = "$wrkdir/$server/$host/cpu.cfg-$lpar_slash";
  if ( -f "$cfg" ) {
    open( FH, " < $cfg" ) || error( "Cannot open $cfg: $!" . __FILE__ . ":" . __LINE__ ) && return 0;
    foreach my $line (<FH>) {
      if ( $line =~ m/logical_serial_num/ ) {    #exclude serial info
        next;
      }
      else {
        print $line;
      }
    }
  }

  #print "LPAR configuration: <A HREF=\"$host_url/$server_url/config.html#$lpar_url\"><b>$lpar</b></A>\n";
  return 1;
}

# print a link with detail
sub print_item {
  my ( $host_url, $server_url, $lpar_url, $item, $time_graph, $type_sam, $entitle, $detail, $refresh, $nostar, $colspan, $legend, $others ) = @_;

  my $overview_string = "";
  my $overview_power  = 0;
  if ( defined $others->{overview_power} ) {
    $overview_power  = 1;
    $overview_string = "&overview_power=$overview_power" if ($overview_power);
  }

  my $dplatform = "";

  # print STDERR "2869 detail-cgi.pl ".$params{platform}."\n";
  if ( $params{d_platform} ) {
    $dplatform = "&d_platform=$params{d_platform}";
  }

  #  if (defined $params{platform}){
  #    if ($params{platform} eq "VMware") {
  #      $params{d_platform} = "VMware";
  #    }
  #  }

  return if $false_picture eq "do not print";

  my $legend_class = "";
  if ( $legend =~ m/nolegend/ ) {
    $legend_class = "nolegend";
  }
  my $legend_higher = "legend";
  if ( $legend =~ m/higher/ ) {
    $legend_higher = "legend higher";
  }

  my $favs_favoff = "<div class=\"favs favoff\"></div>";    # dash-board-able
  if ( $nostar =~ m/nostar/ ) {
    $favs_favoff = "";
  }
  if ( $refresh =~ m/norefr/ ) {
    $refresh = "";
  }
  my $colspan_text = "";
  if ( $colspan == 2 ) {
    $colspan_text = "colspan=\"2\"";
  }
  my $xdetail = 9;

  my $u_time = time * (-1);
  if ($rest_api) { $refresh = ""; }
  if ( $detail > 0 ) {
    if ( $item =~ m/^trend|trend$/ ) {

      #show prediction graph
      if ( defined $prediction && $prediction eq "prediction" && ( $item eq 'trendpool-total' || $item eq 'trendpool-total-max' || $item eq 'trendpool' || $item eq 'trendpool-max' ) ) {
        print "<td colspan=\"2\" class=\"trend $prediction\">
              <div class='preddiv' style='500px; height: 320px' data-loader='predictionLoader' data-title= '$server : CPU usage prediction' data-src='/lpar2rrd-cgi/prediction.sh?host=$host&server=$server&item=$item&lpar=$lpar'>
              </div>";
        print "<div align='center'> The <a href='https://www.lpar2rrd.com/smart_trends.php' target='blank'>Smart trend</a> graph does not correspond to the demo data. Note this is only an example of how it might look in your environment. </div>" if ( $ENV{DEMO} );
        print "</td><tr></tr>\n";
      }
      if ( $item eq 'trendpool' || $item eq 'trendpool-max' || $item eq "trendshpool" || $item eq "trendshpool-max" || $item eq "trend" ) {
        print "          <td colspan=\"2\" class=\"trend\">
              <div>";
        if ( $false_picture ne "" ) {
          print "$false_picture";
        }
        else {
          print "  <div class=\"g_title\">
                  $favs_favoff
                  $refresh
                  <div class=\"popdetail\"></div>
                  <div class=\"g_text\" data-server=\"$server_url\"data-lpar=\"$lpar_url\" data-item=\"$item\" data-time=\"$time_graph\"><span class=\"tt_span\"></span></div>
                </div>
                <a class=\"detail\" href=\"/lpar2rrd-cgi/$detail_graph.sh?host=$host_url&server=$server_url&lpar=$lpar_url&item=$item&time=$time_graph&type_sam=$type_sam&detail=1&entitle=${entitle}${dplatform}&none=none\">
                  <div title=\"Click to show detail\"><img class=\"$legend_class lazy\" border=\"0\" data-src=\"/lpar2rrd-cgi/$detail_graph.sh?host=$host_url&server=$server_url&lpar=$lpar_url&item=$item&time=$time_graph&type_sam=$type_sam&detail=$xdetail&entitle=${entitle}${dplatform}&none=$u_time\" src=\"css/images/sloading.gif\">
                  </div>
                </a>";
        }
        print " </div>
            </td>\n";
      }
    }
    else {
      print "          <td$colspan_text class=\"relpos\">
              <div>";
      if ( $false_picture ne "" ) {
        print "$false_picture";
      }
      else {
        my $limited = "";
        if ( $item =~ /kubernetes/ ) {
          $limited = "limited_graph_title_width";
        }

        print "  <div class=\"g_title\">
                  $favs_favoff
                  $refresh
                  <div class=\"popdetail\"></div>
                  <div class=\"g_text $limited\" data-server=\"$server_url\"data-lpar=\"$lpar_url\" data-item=\"$item\" data-time=\"$time_graph\"><span class=\"tt_span\"></span></div>
                </div>
                <a class=\"detail\" href=\"/lpar2rrd-cgi/$detail_graph.sh?host=$host_url&server=$server_url&lpar=$lpar_url&item=$item&time=$time_graph&type_sam=$type_sam&detail=1&entitle=${entitle}${dplatform}$overview_string&none=none\">
                  <div title=\"Click to show detail\"><img class=\"$legend_class lazy\" border=\"0\" data-src=\"/lpar2rrd-cgi/$detail_graph.sh?host=$host_url&server=$server_url&lpar=$lpar_url&item=$item&time=$time_graph&type_sam=$type_sam&detail=$xdetail&entitle=${entitle}${dplatform}$overview_string&none=$u_time\" src=\"css/images/sloading.gif\">
                    <div class=\"zoom\" title=\"Click and drag to select range\"></div>
                  </div>
                </a>
                <div class=\"$legend_higher\"></div>
                <div class=\"updated\"></div>";
      }
      print " </div>
            </td>\n";
    }
  }
  else {
    print "<td $colspan_text align=\"center\"><div><img class=\"$legend_class lazy\" border=\"0\" data-src=\"/lpar2rrd-cgi/$detail_graph.sh?host=$host_url&server=$server_url&lpar=$lpar_url&item=$item&time=$time_graph&type_sam=$type_sam&detail=0&entitle=${entitle}${dplatform}$overview_string&none=$u_time\" src=\"css/images/sloading.gif\"></div></td>\n";
  }
  return 1;
}

# print a link with detail into $tab_exe
sub print_item_tab_exe {
  my ( $host_url, $server_url, $lpar_url, $item, $time_graph, $type_sam, $entitle, $detail, $refresh, $nostar ) = @_;

  my $favs_favoff = "<div class=\"favs favoff\"></div>";    # dash-board-able
  if ( $nostar =~ m/nostar/ ) {
    $favs_favoff = "";
  }
  if ( $refresh =~ m/norefr/ ) {
    $refresh = "";
  }

  my $u_time = time * (-1);
  if ( $detail > 0 ) {
    $tab_exe .= "<td valign=\"top\" class=\"relpos\"><div>$favs_favoff<div class=\"popdetail\"></div>$refresh<a class=\"detail\" href=\"/lpar2rrd-cgi/$detail_graph.sh?host=$host_url&server=$server_url&lpar=$lpar_url&item=$item&time=$time_graph&type_sam=$type_sam&detail=1&upper=$upper&entitle=$entitle&none=none\"><font color=\"#C8C8C8\" title=\"Click to show detail\"><img class=\"lazy\" border=\"0\" data-src=\"/lpar2rrd-cgi/$detail_graph.sh?host=$host_url&server=$server_url&lpar=$lpar_url&item=$item&time=$time_graph&type_sam=$type_sam&detail=0&upper=$upper&entitle=$entitle&none=$u_time&none=$u_time\" src=\"css/images/loading.gif\"><div class=\"zoom\" title=\"Click and drag to select range\"></div></font></a></div></td>\n";
  }
  else {
    $tab_exe .= "<td align=\"center\" valign=\"top\" colspan=\"2\"><font color=\"#C8C8C8\"><img class=\"lazy\" border=\"0\" data-src=\"/lpar2rrd-cgi/$detail_graph.sh?host=$host_url&server=$server_url&lpar=$lpar_url&item=$item&time=$time_graph&type_sam=$type_sam&detail=0&upper=$upper&entitle=$entitle&none=$u_time&none=$u_time\" src=\"css/images/loading.gif\"></td>\n";
  }
  return 1;
}

sub test_file_in_directory {

  # same sub in lpar-list-cgi.pl
  # Use a regular expression to find files
  #    beginning by $fpn
  #    ending by .mmm or ending is 3rd param - if used
  #    returns 0 (zero) or first filename found i.e. non zero
  #    special care for san- sea-

  my $dir    = shift;
  my $fpn    = shift;
  my $ending = shift;

  $ending = "mmm" if !defined $ending;

  # searching OS agent file
  my $found = 0;
  if ( !-d $dir ) { return $found; }
  opendir( DIR, $dir ) || error( "Error in opening dir $dir $! :" . __FILE__ . ":" . __LINE__ ) && return 0;
  while ( my $file = readdir(DIR) ) {
    if ( $file =~ m/^$fpn.*\.$ending$/ ) {
      $found = "$dir/$file";
      last;
    }
  }
  closedir(DIR);
  return $found;
}

# paging aggregated
sub print_pagingagg {
  my ( $host_url, $server_url, $lpar_url, $item, $type_sam, $bmax, $upper ) = @_;

  # print STDERR "2056 bmax $bmax\n";
  #my $bmax = $entitle; # entitle passes max of paging peak when lpar is displayed then
  $bmax =~ s/MAX=//;
  if ( !isdigit($bmax) ) {
    $bmax = 10;
  }
  if ( $bmax <= 0 ) { $bmax = 10; }    # default

  print "<form method=\"GET\" action=\"/lpar2rrd-cgi/detail.sh\">\n";
  $server_url = urldecode($server_url);

  # print STDERR "2068 \$host_url $host_url \$server_url $server_url \$lpar_url $lpar_url\n";
  print "<INPUT type=\"hidden\" name=\"host\" value=\"$host_url\">\n";
  print "<INPUT type=\"hidden\" name=\"server\" value=\"$server_url\">\n";
  print "<INPUT type=\"hidden\" name=\"lpar\" value=\"$lpar_url\">\n";
  print "<INPUT type=\"hidden\" name=\"item\" value=\"pagingagg\">\n";
  print "<p style=\"text-align: right\"><font size=-1>\n";
  print "Displayed are only LPARs with MAX above ";
  print "<INPUT TYPE=\"TEXT\" TITLE=\"Write new Max\" onblur=\"this.style.color='#f00'\" size=\"2\" NAME=\"MAX\" VALUE=\"$bmax\">\n";
  print "<INPUT type=\"hidden\" name=\"gui\" value=\"$gui\">\n";
  print "<INPUT TYPE=\"SUBMIT\" NAME=\"peak\" VALUE=\"kB/sec\" ALT=\"MAX peak\">\n";
  print "</font></p>\n";
  print "</form>\n";
  print "<table align=\"center\" summary=\"Graphs\">\n";
  print OUT "006 CoD : $item \n" if $DEBUG == 2;
  print "<tr>";
  print_item( $host_url, $server_url, $lpar_url, $item, "d", $type_sam, $bmax, $detail_yes, "norefr", "star", 1, "nolegend" );
  print_item( $host_url, $server_url, $lpar_url, $item, "w", $type_sam, $bmax, $detail_yes, "norefr", "star", 1, "nolegend" );
  print "</tr>\n<tr>\n";
  print_item( $host_url, $server_url, $lpar_url, $item, "m", $type_sam,      $bmax, $detail_yes, "norefr", "star", 1, "nolegend" );
  print_item( $host_url, $server_url, $lpar_url, $item, "y", $type_sam_year, $bmax, $detail_yes, "norefr", "star", 1, "nolegend" );
  print "</tr></table>\n";
  print "<ul style=\"display: none\"><li class=\"tabagent\"></li></ul>\n";    # to add the data source icon

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

sub print_hea {
  my ( $host_url, $server_url, $lpar_url, $item, $entitle ) = @_;

  my $cfg             = "$wrkdir/$server/$host/config.cfg";
  my $first           = 0;
  my $act_time        = time();
  my $port_group      = 0;
  my $phys_port_id    = 0;
  my $port            = "";
  my $type_sam        = "";
  my $last_adapter_id = 0;
  my $adapter_count   = 0;
  my $tab_count       = 0;
  my $adapter_id;

  $tab_exe = "";    # must be global

  # could be none or up to 4 adapters (more ?), each up to 4 ports
  # each port has its own database
  opendir( DIR, "$wrkdir/$server/$host" ) || error( " directory does not exists : $wrkdir/$server/$host" . __FILE__ . ":" . __LINE__ ) && return 0;
  my @files_not_sorted = grep( /.*-.*\.db$/, readdir(DIR) );
  closedir(DIR);
  my $file  = "";
  my @files = sort @files_not_sorted;

  print "<div  id=\"tabs\">\n";    # prepare tab declarative
  print "<ul>\n";

  foreach $file (@files) {
    if ( $file =~ "HSCL" || $file =~ "VIOSE0" ) {
      unlink($file);
      next;    # some error
    }
    $tab_count++;
    chomp($file);
    ( undef, $adapter_id, my $port ) = split( /-/, $file );
    $port =~ s/\.db//;
    my $port_whole = $port;
    $port =~ s/port//g;

    #print "-- $file $port\n";
    if ( $last_adapter_id ne $adapter_id ) {
      $adapter_count++;
      $last_adapter_id = $adapter_id;
    }
    print "  <li class=\"tabhmc\"><a href=\"#tabs-$tab_count\">HEA$adapter_count-$port</a></li>\n";
    my $rrd = "$wrkdir/$server/$host/$file";

    # prepare tab executive
    $tab_exe .= "<div id=\"tabs-$tab_count\">\n";
    $tab_exe .= "<center>";

    $tab_exe .= "<table align=\"center\" summary=\"Graphs\">\n";
    $tab_exe .= "<tr><td colspan=\"2\" align=\"center\"><A NAME=HEA></A> <H3>$adapter_id-$port_whole</H3> <BR></td></tr>\n";

    $tab_exe .= "<tr>";
    $item = $file;
    print_item_tab_exe( $host_url, $server_url, $lpar_url, $item, "d", $type_sam, $entitle, $detail_yes, "norefr", "nostar", 1, "legend" );
    print_item_tab_exe( $host_url, $server_url, $lpar_url, $item, "w", $type_sam, $entitle, $detail_yes, "norefr", "nostar", 1, "legend" );
    $tab_exe .= "</tr>\n<tr>\n";
    print_item_tab_exe( $host_url, $server_url, $lpar_url, $item, "m", $type_sam,      $entitle, $detail_yes, "norefr", "nostar", 1, "legend" );
    print_item_tab_exe( $host_url, $server_url, $lpar_url, $item, "y", $type_sam_year, $entitle, $detail_yes, "norefr", "nostar", 1, "legend" );
    $tab_exe .= "</tr></table>";

    my $lpar_logical_port_table = "";
    $first = 0;
    if ( -f "$cfg" ) {
      my $port_id = $port;
      my $line    = "";
      $port_id =~ s/port//g;
      my $ret = substr( $port_id, 0, 1 );
      if ( $ret =~ /\D/ ) {
        error( "Error $host: Wrong input data, HEA port : $port" . __FILE__ . ":" . __LINE__ ) && return 0;
        return 1;
      }

      if ( $port_id == 1 ) { $phys_port_id = 0; $port_group = 1; }
      if ( $port_id == 2 ) { $phys_port_id = 1; $port_group = 1; }
      if ( $port_id == 3 ) { $phys_port_id = 0; $port_group = 2; }
      if ( $port_id == 4 ) { $phys_port_id = 1; $port_group = 2; }

      my @hea_ports = `grep $adapter_id "$cfg" |grep phys_port_id=$phys_port_id|grep " port_group=$port_group"|grep " lpar_name="|sort|uniq|awk -F= '{print \$4,"%",\$8}'|sed -e 's/port_group//g' -e 's/drc_index//g'`;

      foreach $line (@hea_ports) {
        chomp($line);
        if ( $first == 0 ) {
          $lpar_logical_port_table .= "<BR><TABLE class=\"tabconfig\">\n";
          $lpar_logical_port_table .= "<TR> <TD><font size=-1><B>LPAR&nbsp;&nbsp;&nbsp;&nbsp;</B></font></TD> <TD align=\"center\"><font size=-1><B>Logical port</font></B></TD></TR>\n";

          $first = 1;
        }
        ( my $lpar, my $lport ) = split( /%/, $line );
        $lpar =~ s/ state //;
        $lpar_logical_port_table .= "<TR> <TD><font size=-1>$lpar</font></TD> <TD align=\"center\"><font size=-1>$lport</font></TD></TR>\n";

      }
      if ( $first == 1 ) {
        $lpar_logical_port_table .= "</table><BR>\n";
      }
    }

    $tab_exe .= "$lpar_logical_port_table";
    $tab_exe .= "</div>\n";

  }
  print "</ul>\n";
  print "$tab_exe";

  return 1;
}

sub print_power_adapters {

  #host=vhmc&server=P02DR__9117-MMC-SN44K8102&item=power_lan&entitle=0&gui=1&none=none
  my @array = @_;
  foreach my $item (@array) {
    if ( $item =~ m/=/ ) {

      #(undef, $item) = split ("=", $item);
    }
  }
  my $upper = -1;
  my ( $host_url, $server_url, $lpar_url, $item, $entitle ) = ( $params{host}, $params{server}, $params{lpar}, $params{item}, $params{entitle} );
  my $legend;
  if   ( $item =~ m/power_sri/ ) { $legend = "nolegend"; }    #one item is aggregated graph, so need nolegend in graph
  else                           { $legend = "legend"; }
  print "<CENTER>\n";
  print "<div  id=\"tabs\">\n";
  print "<ul>\n";
  print "  <li ><a href=\"#tabs-1\">Data</a></li>\n";
  if    ( $item =~ m/lan/ ) { print "  <li ><a href=\"#tabs-2\">Packets</a></li>\n"; }
  elsif ( $item =~ m/hea/ ) { print "  <li ><a href=\"#tabs-2\">Packets</a></li>\n"; }
  elsif ( $item =~ m/sri/ ) { print "  <li ><a href=\"#tabs-2\">Packets</a></li>\n"; }
  elsif ( $item =~ m/san/ ) { print "  <li ><a href=\"#tabs-2\">IOPS</a></li>\n"; }
  elsif ( $item =~ m/sas/ ) { print "  <li ><a href=\"#tabs-2\">IOPS</a></li>\n"; }
  print "</ul>\n";

  my $item1 = "$item\_data";
  print "<div id=\"tabs-1\">\n";
  print "<table border=\"0\">\n";
  print "<tr>";
  print_item( $host_url, $server_url, $lpar_url, $item1, "d", "m", 0, 1, "norefr", "nostar", 1, "$legend" );
  print_item( $host_url, $server_url, $lpar_url, $item1, "w", "m", 0, 1, "norefr", "nostar", 1, "$legend" );
  print "</tr>\n<tr>\n";
  print_item( $host_url, $server_url, $lpar_url, $item1, "m", "m", 0, 1, "norefr", "nostar", 1, "$legend" );
  print_item( $host_url, $server_url, $lpar_url, $item1, "y", "m", 0, 1, "norefr", "nostar", 1, "$legend" );
  print "</tr>";
  print "</table>";
  print "</div>";

  my $item2 = "$item\_io";
  print "<div id=\"tabs-2\">\n";
  print "<table border=\"0\">\n";
  print "<tr>";
  print_item( $host_url, $server_url, $lpar_url, $item2, "d", "m", 0, 1, "norefr", "nostar", 1, "$legend" );
  print_item( $host_url, $server_url, $lpar_url, $item2, "w", "m", 0, 1, "norefr", "nostar", 1, "$legend" );
  print "</tr>\n<tr>\n";
  print_item( $host_url, $server_url, $lpar_url, $item2, "m", "m", 0, 1, "norefr", "nostar", 1, "$legend" );
  print_item( $host_url, $server_url, $lpar_url, $item2, "y", "m", 0, 1, "norefr", "nostar", 1, "$legend" );
  print "</tr>";
  print "</table>";
  print "</div>";

  print "</div>\n";
  return 1;
}

sub print_power_adapters_agg {

  #host=vhmc&server=P02DR__9117-MMC-SN44K8102&item=power_lan&entitle=0&gui=1&none=none
  my @array = @_;
  my ( $host_url, $server_url, $lpar_url, $item, $entitle, $hash_params ) = @_;

  my $overview_power = 0;
  if ( defined $hash_params->{overview_power} ) {
    $overview_power = 1;
  }

  print "<CENTER>\n";
  print "<div  id=\"tabs\">\n";
  print "<ul>\n";
  print "  <li ><a href=\"#tabs-1\">Data</a></li>\n";
  if    ( $item =~ m/power_lan/ ) { print "  <li ><a href=\"#tabs-2\">Packets</a></li>\n"; }
  elsif ( $item =~ m/power_sri/ ) { print "  <li ><a href=\"#tabs-2\">Packets</a></li>\n"; }
  elsif ( $item =~ m/power_hea/ ) { print "  <li ><a href=\"#tabs-2\">Packets</a></li>\n"; }
  elsif ( $item =~ m/power_san/ ) { print "  <li ><a href=\"#tabs-2\">IOPS</a></li>\n"; }
  elsif ( $item =~ m/power_sas/ ) { print "  <li ><a href=\"#tabs-2\">IOPS</a></li>\n"; }
  print "</ul>\n";

  my $item1 = "$item\_data";
  print "<div id=\"tabs-1\">\n";
  print "<table border=\"0\">\n";
  print "<tr>";
  print_item( $host_url, $server_url, $lpar_url, $item1, "d", $type_sam, $entitle, $detail_yes, "norefr", "nostar", 1, "nolegend" );
  print_item( $host_url, $server_url, $lpar_url, $item1, "w", $type_sam, $entitle, $detail_yes, "norefr", "nostar", 1, "nolegend" );
  print "</tr>\n<tr>\n";
  print_item( $host_url, $server_url, $lpar_url, $item1, "m", $type_sam,      $entitle, $detail_yes, "norefr", "nostar", 1, "nolegend" );
  print_item( $host_url, $server_url, $lpar_url, $item1, "y", $type_sam_year, $entitle, $detail_yes, "norefr", "nostar", 1, "nolegend" );
  print "</tr>";
  print "</table>";
  print "</div>";

  my $item2 = "$item\_io";
  print "<div id=\"tabs-2\">\n";
  print "<table border=\"0\">\n";
  print "<tr>";
  print_item( $host_url, $server_url, $lpar_url, $item2, "d", $type_sam, $entitle, $detail_yes, "norefr", "nostar", 1, "nolegend" );
  print_item( $host_url, $server_url, $lpar_url, $item2, "w", $type_sam, $entitle, $detail_yes, "norefr", "nostar", 1, "nolegend" );
  print "</tr>\n<tr>\n";
  print_item( $host_url, $server_url, $lpar_url, $item2, "m", $type_sam,      $entitle, $detail_yes, "norefr", "nostar", 1, "nolegend" );
  print_item( $host_url, $server_url, $lpar_url, $item2, "y", $type_sam_year, $entitle, $detail_yes, "norefr", "nostar", 1, "nolegend" );
  print "</tr>";
  print "</table>";
  print "</div>";
  print "</div>\n";
  return 1;
}

sub print_power_total_servers {
  my @array = @_;
  my ( $host_url, $server_url, $lpar_url, $item, $entitle, $hash_params ) = @_;

  print "<CENTER>\n";

  print "<div  id=\"tabs\">\n";
  print "<ul>\n";
  print "  <li ><a href=\"#tabs-1\">Total</a></li>\n";
  print "  <li ><a href=\"#tabs-2\">Total Max</a></li>\n";
  print "</ul>\n";

  $item = 'power-total';
  print "<div id=\"tabs-1\">\n";
  print "<table border=\"0\">\n";
  print "<tr>";
  print_item( $host_url, $server_url, $lpar_url, $item, "d", $type_sam, $entitle, $detail_yes, "norefr", "nostar", 1, "nolegend" );
  print_item( $host_url, $server_url, $lpar_url, $item, "w", $type_sam, $entitle, $detail_yes, "norefr", "nostar", 1, "nolegend" );
  print "</tr>\n<tr>\n";
  print_item( $host_url, $server_url, $lpar_url, $item, "m", $type_sam,      $entitle, $detail_yes, "norefr", "nostar", 1, "nolegend" );
  print_item( $host_url, $server_url, $lpar_url, $item, "y", $type_sam_year, $entitle, $detail_yes, "norefr", "nostar", 1, "nolegend" );
  print "</tr>";
  print "</table>";
  print "</div>";

  $item = 'power-total-max';
  print "<div id=\"tabs-2\">\n";
  print "<table border=\"0\">\n";
  print "<tr>";
  print_item( $host_url, $server_url, $lpar_url, $item, "d", $type_sam, $entitle, $detail_yes, "norefr", "nostar", 1, "nolegend" );
  print_item( $host_url, $server_url, $lpar_url, $item, "w", $type_sam, $entitle, $detail_yes, "norefr", "nostar", 1, "nolegend" );
  print "</tr>\n<tr>\n";
  print_item( $host_url, $server_url, $lpar_url, $item, "m", $type_sam,      $entitle, $detail_yes, "norefr", "nostar", 1, "nolegend" );
  print_item( $host_url, $server_url, $lpar_url, $item, "y", $type_sam_year, $entitle, $detail_yes, "norefr", "nostar", 1, "nolegend" );
  print "</tr>";
  print "</table>";
  print "</div>";

  print "</div>\n";
  return 1;
}

sub print_solaris {
  my ( $host_url, $server_url, $lpar_url, $item, $type_sam ) = @_;
  my $tabs      = 1;
  my $zone_name = $item;
  $zone_name =~ s/sol11-//g;

  #print STDERR"line(7251)-$host_url,$server_url,$lpar_url,$item,$type_sam\n $wrkdir/Solaris--unknown/no_hmc/$zone_name/cpu.mmm\n";
  $params{d_platform} = "solaris";
  if ( $server_url =~ /%3A/ && $item !~ /sol11$|sol_zone_c_xor|sol_zone_l_xor11/ ) {
    my $server_split = "$server_url";
    $server_split =~ s/%3A/:/g;
    my ( $server_url1, undef ) = split( /:/, $server_split );
    if ( $item ne "sol_zone_c_xor" ) {
      $zone_name = "$server_url1:zone:$zone_name";
      $lpar_url  = "$zone_name";
    }
    else {
      $zone_name = "$server_url1:$server_url1";
    }
  }
  else {
    $zone_name = "$server_url:zone:$zone_name";
  }

  print "<CENTER>";
  print "<div  id=\"tabs\">\n";
  print "<ul>\n";
  print "  <li class=\"\"><a href=\"#tabs-$tabs\">CPU</a></li>\n";
  $tabs++;
  print "  <li class=\"\"><a href=\"#tabs-$tabs\">CPU percent</a></li>\n";
  $tabs++;
  print "  <li class=\"\"><a href=\"#tabs-$tabs\">Memory</a></li>\n";
  $tabs++;
  print "  <li class=\"\"><a href=\"#tabs-$tabs\">Net</a></li>\n";
  $tabs++;

  if ( -f "$wrkdir/Solaris--unknown/no_hmc/$zone_name/cpu.mmm" ) {
    print "  <li class=\"\"><a href=\"#tabs-$tabs\">CPU OS</a></li>\n";
    $tabs++;
  }
  if ( -f "$wrkdir/Solaris--unknown/no_hmc/$zone_name/queue_cpu.mmm" ) {
    print "  <li class=\"\"><a href=\"#tabs-$tabs\">CPU QUEUE</a></li>\n";
    $tabs++;
  }
  if ( -d "$wrkdir/Solaris--unknown/no_hmc/$zone_name/JOB/" ) {
    opendir( DIR, "$wrkdir/Solaris--unknown/no_hmc/$zone_name/JOB/" ) || error( "can't opendir $wrkdir/Solaris--unknown/$zone_name/JOB/: $! :" . __FILE__ . ":" . __LINE__ );
    my @job_path = grep /mmc/, readdir(DIR);
    if (@job_path) {
      print "  <li class=\"\"><a href=\"#tabs-$tabs\">JOB</a></li>\n";
      $tabs++;
    }
  }
  if ( -f "$wrkdir/Solaris--unknown/no_hmc/$zone_name/mem.mmm" ) {
    print "  <li class=\"\"><a href=\"#tabs-$tabs\">Memory OS</a></li>\n";
    $tabs++;
  }
  if ( -f "$wrkdir/Solaris--unknown/no_hmc/$zone_name/pgs.mmm" ) {
    print "  <li class=\"\"><a href=\"#tabs-$tabs\">Paging 1</a></li>\n";
    $tabs++;
    print "  <li class=\"\"><a href=\"#tabs-$tabs\">Paging 2</a></li>\n";
    $tabs++;
  }

  my @lan_path;
  if ( -d "$wrkdir/Solaris--unknown/no_hmc/$zone_name/" ) {
    opendir( DIR, "$wrkdir/Solaris--unknown/no_hmc/$zone_name/" ) || error( "can't opendir $wrkdir/Solaris--unknown/no_hmc/$zone_name/: $! :" . __FILE__ . ":" . __LINE__ );
    @lan_path = grep !/^\.\.?$/, readdir(DIR);
    my $i = 0;
    foreach my $lan_name (@lan_path) {
      if ( $lan_name =~ /lan/ ) {
        if ( $i == 0 ) {
          $i++;
          print "  <li class=\"\"><a href=\"#tabs-$tabs\">LAN</a></li>\n";
          $tabs++;
        }
      }
    }
  }
  my $file_fs = "$wrkdir/Solaris--unknown/no_hmc/$lpar/FS.csv";
  if ( -f $file_fs ) {
    print "  <li class=\"\"><a href=\"#tabs-$tabs\">FS</a></li>\n";
    $tabs++;
  }

  print "</ul>\n";

  my $s_item1 = "";

  #if ($item =~ /sol11-global|system|total/){
  #  $s_item1 = "s_s";
  #}
  #else{
  #  $s_item1 = "s_z";
  #}
  $tabs = 1;
  $s_item1 .= "solaris_zone_cpu";
  print "<div id=\"tabs-$tabs\">\n";
  $tabs++;
  print "<table border=\"0\">\n";
  print "<tr>";
  print_item( $host_url, $server_url, $lpar_url, $s_item1, "d", $type_sam, $entitle, $detail_yes, "norefr", "star", 1, "legend" );
  print_item( $host_url, $server_url, $lpar_url, $s_item1, "w", $type_sam, $entitle, $detail_yes, "norefr", "star", 1, "legend" );
  print "</tr>\n<tr>\n";
  print_item( $host_url, $server_url, $lpar_url, $s_item1, "m", $type_sam,      $entitle, $detail_yes, "norefr", "star", 1, "legend" );
  print_item( $host_url, $server_url, $lpar_url, $s_item1, "y", $type_sam_year, $entitle, $detail_yes, "norefr", "star", 1, "legend" );
  print "</tr></table>";
  print "</div>\n";

  my $s_item2 = "";

  #if ($item =~ /sol11-global|system|total/){
  #  $s_item2 = "s_s";
  #}
  #else{
  #  $s_item2 = "s_z";
  #}
  $s_item2 .= "solaris_zone_os_cpu";
  print "<div id=\"tabs-$tabs\">\n";
  $tabs++;
  print "<table border=\"0\">\n";
  print "<tr>";
  print_item( $host_url, $server_url, $lpar_url, $s_item2, "d", $type_sam, $entitle, $detail_yes, "norefr", "star", 1, "legend" );
  print_item( $host_url, $server_url, $lpar_url, $s_item2, "w", $type_sam, $entitle, $detail_yes, "norefr", "star", 1, "legend" );
  print "</tr>\n<tr>\n";
  print_item( $host_url, $server_url, $lpar_url, $s_item2, "m", $type_sam,      $entitle, $detail_yes, "norefr", "star", 1, "legend" );
  print_item( $host_url, $server_url, $lpar_url, $s_item2, "y", $type_sam_year, $entitle, $detail_yes, "norefr", "star", 1, "legend" );
  print "</tr></table>";
  print "</div>\n";

  my $s_item3 = "";

  #if ($item =~ /sol11-global|system|total/){
  #  $s_item3 = "s_s";
  #}
  #else{
  #  $s_item3 = "s_z";
  #}
  $s_item3 .= "solaris_zone_mem";

  # $item="pool";
  print "<div id=\"tabs-$tabs\">\n";
  $tabs++;
  print "<table border=\"0\">\n";
  print "<tr>";
  print_item( $host_url, $server_url, $lpar_url, $s_item3, "d", $type_sam, $entitle, $detail_yes, "norefr", "star", 1, "legend" );
  print_item( $host_url, $server_url, $lpar_url, $s_item3, "w", $type_sam, $entitle, $detail_yes, "norefr", "star", 1, "legend" );
  print "</tr>\n<tr>\n";
  print_item( $host_url, $server_url, $lpar_url, $s_item3, "m", $type_sam,      $entitle, $detail_yes, "norefr", "star", 1, "legend" );
  print_item( $host_url, $server_url, $lpar_url, $s_item3, "y", $type_sam_year, $entitle, $detail_yes, "norefr", "star", 1, "legend" );
  print "</tr></table>";
  print "</div>\n";

  my $s_item4 = "";

  #if ($item =~ /sol11-global|system|total/){
  #  $s_item4 = "s_s";
  #}
  #else{
  #  $s_item4 = "s_z";
  #}
  $s_item4 .= "solaris_zone_net";

  # $item="pool";
  print "<div id=\"tabs-$tabs\">\n";
  $tabs++;
  print "<table border=\"0\">\n";
  print "<tr>";
  print_item( $host_url, $server_url, $lpar_url, $s_item4, "d", $type_sam, $entitle, $detail_yes, "norefr", "star", 1, "legend" );
  print_item( $host_url, $server_url, $lpar_url, $s_item4, "w", $type_sam, $entitle, $detail_yes, "norefr", "star", 1, "legend" );
  print "</tr>\n<tr>\n";
  print_item( $host_url, $server_url, $lpar_url, $s_item4, "m", $type_sam,      $entitle, $detail_yes, "norefr", "star", 1, "legend" );
  print_item( $host_url, $server_url, $lpar_url, $s_item4, "y", $type_sam_year, $entitle, $detail_yes, "norefr", "star", 1, "legend" );
  print "</tr></table>";
  print "</div>\n";

  if ( -f "$wrkdir/Solaris--unknown/no_hmc/$zone_name/cpu.mmm" ) {
    my $s_item5 = "oscpu";
    $host_url   = "no_hmc";
    $server_url = "Solaris--unknown";
    $lpar_url   = "$zone_name";
    print "<div id=\"tabs-$tabs\">\n";
    $tabs++;
    print "<table border=\"0\">\n";
    print "<tr>";
    print_item( $host_url, $server_url, $lpar_url, $s_item5, "d", $type_sam, $entitle, $detail_yes, "norefr", "star", 1, "legend" );
    print_item( $host_url, $server_url, $lpar_url, $s_item5, "w", $type_sam, $entitle, $detail_yes, "norefr", "star", 1, "legend" );
    print "</tr>\n<tr>\n";
    print_item( $host_url, $server_url, $lpar_url, $s_item5, "m", $type_sam,      $entitle, $detail_yes, "norefr", "star", 1, "legend" );
    print_item( $host_url, $server_url, $lpar_url, $s_item5, "y", $type_sam_year, $entitle, $detail_yes, "norefr", "star", 1, "legend" );
    print "</tr></table>";
    print "</div>\n";
  }
  if ( -f "$wrkdir/Solaris--unknown/no_hmc/$zone_name/queue_cpu.mmm" ) {
    my $s_item_cpu_queue = "queue_cpu";
    $host_url   = "no_hmc";
    $server_url = "Solaris--unknown";
    $lpar_url   = "$zone_name";
    print "<div id=\"tabs-$tabs\">\n";
    $tabs++;
    print "<table border=\"0\">\n";
    print "<tr>";
    print_item( $host_url, $server_url, $lpar_url, $s_item_cpu_queue, "d", $type_sam, $entitle, $detail_yes, "norefr", "star", 1, "legend" );
    print_item( $host_url, $server_url, $lpar_url, $s_item_cpu_queue, "w", $type_sam, $entitle, $detail_yes, "norefr", "star", 1, "legend" );
    print "</tr>\n<tr>\n";
    print_item( $host_url, $server_url, $lpar_url, $s_item_cpu_queue, "m", $type_sam,      $entitle, $detail_yes, "norefr", "star", 1, "legend" );
    print_item( $host_url, $server_url, $lpar_url, $s_item_cpu_queue, "y", $type_sam_year, $entitle, $detail_yes, "norefr", "star", 1, "legend" );
    print "</tr></table>";
    print "</div>\n";
  }

  if ( -d "$wrkdir/Solaris--unknown/no_hmc/$zone_name/JOB/" ) {
    opendir( DIR, "$wrkdir/Solaris--unknown/no_hmc/$zone_name/JOB/" ) || error( "can't opendir $wrkdir/Solaris--unknown/$zone_name/JOB/: $! :" . __FILE__ . ":" . __LINE__ );
    my @job_path = grep /mmc/, readdir(DIR);
    my $o = 0;
    foreach my $job_name (@job_path) {
      if ( $o == 0 ) {
        my $s_item_job1 = "jobs";
        my $s_item_job2 = "jobs_mem";
        my $server_url  = "Solaris--unknown";
        my $lpar_url    = "$zone_name";
        print "<div id=\"tabs-$tabs\">\n";
        $tabs++;
        $o++;
        print "<table border=\"0\">\n";
        print "<tr>";
        print_item( $host_url, $server_url, $lpar_url, $s_item_job1, "d", $type_sam, $entitle, $detail_yes, "norefr", "star", 1, "nolegend" );
        print_item( $host_url, $server_url, $lpar_url, $s_item_job1, "w", $type_sam, $entitle, $detail_yes, "norefr", "star", 1, "nolegend" );
        print "</tr>\n<tr>\n";
        print_item( $host_url, $server_url, $lpar_url, $s_item_job2, "d", $type_sam,      $entitle, $detail_yes, "norefr", "star", 1, "nolegend" );
        print_item( $host_url, $server_url, $lpar_url, $s_item_job2, "w", $type_sam_year, $entitle, $detail_yes, "norefr", "star", 1, "nolegend" );
        print "</tr></table>";
        print "</div>\n";
      }
    }
  }

  if ( -f "$wrkdir/Solaris--unknown/no_hmc/$zone_name/mem.mmm" ) {
    my $s_item6 = "mem";
    $host_url   = "no_hmc";
    $server_url = "Solaris--unknown";
    $lpar_url   = "$zone_name";
    print "<div id=\"tabs-$tabs\">\n";
    $tabs++;
    print "<table border=\"0\">\n";
    print "<tr>";
    print_item( $host_url, $server_url, $lpar_url, $s_item6, "d", $type_sam, $entitle, $detail_yes, "norefr", "star", 1, "legend" );
    print_item( $host_url, $server_url, $lpar_url, $s_item6, "w", $type_sam, $entitle, $detail_yes, "norefr", "star", 1, "legend" );
    print "</tr>\n<tr>\n";
    print_item( $host_url, $server_url, $lpar_url, $s_item6, "m", $type_sam,      $entitle, $detail_yes, "norefr", "star", 1, "legend" );
    print_item( $host_url, $server_url, $lpar_url, $s_item6, "y", $type_sam_year, $entitle, $detail_yes, "norefr", "star", 1, "legend" );
    print "</tr></table>";
    print "</div>\n";
  }
  if ( -f "$wrkdir/Solaris--unknown/no_hmc/$zone_name/pgs.mmm" ) {
    my $s_item7 = "pg1";
    $host_url   = "no_hmc";
    $server_url = "Solaris--unknown";
    $lpar_url   = "$zone_name";
    print "<div id=\"tabs-$tabs\">\n";
    $tabs++;
    print "<table border=\"0\">\n";
    print "<tr>";
    print_item( $host_url, $server_url, $lpar_url, $s_item7, "d", $type_sam, $entitle, $detail_yes, "norefr", "star", 1, "legend" );
    print_item( $host_url, $server_url, $lpar_url, $s_item7, "w", $type_sam, $entitle, $detail_yes, "norefr", "star", 1, "legend" );
    print "</tr>\n<tr>\n";
    print_item( $host_url, $server_url, $lpar_url, $s_item7, "m", $type_sam,      $entitle, $detail_yes, "norefr", "star", 1, "legend" );
    print_item( $host_url, $server_url, $lpar_url, $s_item7, "y", $type_sam_year, $entitle, $detail_yes, "norefr", "star", 1, "legend" );
    print "</tr></table>";
    print "</div>\n";
    my $s_item8 = "pg2";
    print "<div id=\"tabs-$tabs\">\n";
    $tabs++;
    print "<table border=\"0\">\n";
    print "<tr>";
    print_item( $host_url, $server_url, $lpar_url, $s_item8, "d", $type_sam, $entitle, $detail_yes, "norefr", "star", 1, "legend" );
    print_item( $host_url, $server_url, $lpar_url, $s_item8, "w", $type_sam, $entitle, $detail_yes, "norefr", "star", 1, "legend" );
    print "</tr>\n<tr>\n";
    print_item( $host_url, $server_url, $lpar_url, $s_item8, "m", $type_sam,      $entitle, $detail_yes, "norefr", "star", 1, "legend" );
    print_item( $host_url, $server_url, $lpar_url, $s_item8, "y", $type_sam_year, $entitle, $detail_yes, "norefr", "star", 1, "legend" );
    print "</tr></table>";
    print "</div>\n";
  }
  my $j = 0;
  foreach my $lan_name (@lan_path) {
    if ( $lan_name =~ /lan/ ) {
      if ( $j == 0 ) {
        my $s_item9 = "lan";
        $host_url   = "no_hmc";
        $server_url = "Solaris--unknown";
        $lpar_url   = "$zone_name";
        print "<div id=\"tabs-$tabs\">\n";

        #$tabs++;
        print "<table border=\"0\">\n";
        print "<tr>";
        print_item( $host_url, $server_url, $lpar_url, $s_item9, "d", $type_sam, $entitle, $detail_yes, "norefr", "star", 1, "nolegend" );
        print_item( $host_url, $server_url, $lpar_url, $s_item9, "w", $type_sam, $entitle, $detail_yes, "norefr", "star", 1, "nolegend" );
        print "</tr>\n<tr>\n";
        print_item( $host_url, $server_url, $lpar_url, $s_item9, "m", $type_sam,      $entitle, $detail_yes, "norefr", "star", 1, "nolegend" );
        print_item( $host_url, $server_url, $lpar_url, $s_item9, "y", $type_sam_year, $entitle, $detail_yes, "norefr", "star", 1, "nolegend" );
        print "</tr></table>";
        $j++;

        my $text_sum = "Summary of transferred Bytes a Day";
        $s_item9 = "slan";
        print "<table align=\"center\" summary=\"Graphs\">\n";
        print "<tr><td colspan=\"2\"><hr></td></tr>\n";
        print "<tr><td colspan=\"2\" align=\"center\"><h4>$text_sum</h4></td></tr>\n";
        print "<tr>\n";
        print_item( $host_url, $server_url, $lpar_url, $s_item9, "m", $type_sam,      $entitle, $detail_yes, "norefr", "star", 1, "legend" );
        print_item( $host_url, $server_url, $lpar_url, $s_item9, "y", $type_sam_year, $entitle, $detail_yes, "norefr", "star", 1, "legend" );
        print "</tr>\n";
        print "</table>\n";

        $s_item9 = "packets_lan";
        print "<table align=\"center\" summary=\"Graphs\">\n";
        print "<tr><td colspan=\"2\"><hr></td></tr>\n";
        print "<tr><td colspan=\"2\" align=\"center\"><h4>Packets</h4></td></tr>\n";
        print "<tr>\n";
        print_item( $host_url, $server_url, $lpar_url, $s_item9, "d", $type_sam,      $entitle, $detail_yes, "norefr", "star", 1, "nolegend" );
        print_item( $host_url, $server_url, $lpar_url, $s_item9, "w", $type_sam_year, $entitle, $detail_yes, "norefr", "star", 1, "nolegend" );
        print "</tr>\n<tr>\n";
        print_item( $host_url, $server_url, $lpar_url, $s_item9, "m", $type_sam,      $entitle, $detail_yes, "norefr", "star", 1, "nolegend" );
        print_item( $host_url, $server_url, $lpar_url, $s_item9, "y", $type_sam_year, $entitle, $detail_yes, "norefr", "star", 1, "nolegend" );
        print "</tr>\n";
        print "</table>\n";
        print "</div>\n";
        $tabs++;
      }
    }
  }
  if ( -f $file_fs ) {
    print "<div id =\"tabs-$tabs\">
    <center>
    <h4>Filesystem usage</h4>
    <tbody>
    <tr>
    <table class =\"tabconfig tablesorter\"data-sortby=\"5\">
    <thead>
    <tr><th class = \"sortable\">Filesystem&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;</th>
    <th class = \"sortable\">Total [GB]&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;</th>
    <th class = \"sortable\">Used [GB]&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;</th>
    <th class = \"sortable\">Available [GB]&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;</th>
    <th class = \"sortable\">Usage [%]&nbsp;&nbsp;</th>
    <th class = \"sortable\">Mounted on&nbsp;&nbsp;</th>
    </tr></thead>\n\n";
    if ( -f "$file_fs" ) {
      open( FH, "< $file_fs" ) || error( "Cannot open $file_fs: $!" . __FILE__ . ":" . __LINE__ );
      my @file_sys_arr = <FH>;
      close(FH);
      foreach my $line (@file_sys_arr) {
        chomp($line);
        ( my $filesystem, my $blocks, my $used, my $avaliable, my $usage, my $mounted ) = split( " ", $line );
        print "<tr><td>$filesystem</td>
        <td>$blocks</td>
        <td>$used</td>
        <td>$avaliable</td>
        <td>$usage</td>
        <td>$mounted</td></tr>";
      }
    }
    my $last_update = localtime( ( stat($file_fs) )[9] );
    print "<tfoot><tr><td colspan=\"6\">Last update time: $last_update</td></tr></tfoot>";
    print "</tr>
    </tbody>
    </table>
    <div><p>You can exclude filesystem for alerting in $basedir/etc/alert_filesystem_exclude.cfg</p></div>
    </center>
    </div>\n";
    $tab_number++;
  }

  #print "</div><br>\n";
  return 1;

}

sub print_solaris10 {
  my ( $host_url, $server_url, $lpar_url, $item, $type_sam ) = @_;
  my $tabs = 1;
  $params{d_platform} = "solaris";
  my $server_zone = "$server_url";
  ($server_zone) = split( /%3A/, $server_zone );
  my $zone_exist = "$server_zone:zone:$lpar_url";
  print STDERR "==$zone_exist==\n";
  print "<CENTER>";
  print "<div  id=\"tabs\">\n";
  print "<ul>\n";
  print "  <li class=\"\"><a href=\"#tabs-$tabs\">CPU</a></li>\n";
  $tabs++;
  print "  <li class=\"\"><a href=\"#tabs-$tabs\">MEM</a></li>\n";
  $tabs++;

  if ( -f "$wrkdir/Solaris--unknown/no_hmc/$zone_exist/cpu.mmm" ) {
    print "  <li class=\"\"><a href=\"#tabs-$tabs\">CPU OS</a></li>\n";
    $tabs++;
  }
  if ( -f "$wrkdir/Solaris--unknown/no_hmc/$zone_exist/queue_cpu.mmm" ) {
    print "  <li class=\"\"><a href=\"#tabs-$tabs\">CPU QUEUE</a></li>\n";
    $tabs++;
  }
  if ( -f "$wrkdir/Solaris--unknown/no_hmc/$zone_exist/pgs.mmm" ) {
    print "  <li class=\"\"><a href=\"#tabs-$tabs\">Paging 1</a></li>\n";
    $tabs++;
    print "  <li class=\"\"><a href=\"#tabs-$tabs\">Paging 2</a></li>\n";
    $tabs++;
  }
  my $file_fs = "$wrkdir/Solaris--unknown/no_hmc/$zone_exist/FS.csv";
  if ( -f $file_fs ) {
    print "  <li class=\"\"><a href=\"#tabs-$tabs\">FS</a></li>\n";
    $tabs++;
  }

  print "</ul>\n";

  my $s_item1 = "";
  if ( $item =~ /sol11-global|system|total/ ) {
    $s_item1 = "s10_s";
  }
  else {
    $s_item1 = "s10_z";
  }
  $tabs = 1;
  $s_item1 .= "_cpu";
  print "<div id=\"tabs-$tabs\">\n";
  $tabs++;
  print "<table border=\"0\">\n";
  print "<tr>";
  print_item( $host_url, $server_url, $lpar_url, $s_item1, "d", $type_sam, $entitle, $detail_yes, "norefr", "star", 1, "legend" );
  print_item( $host_url, $server_url, $lpar_url, $s_item1, "w", $type_sam, $entitle, $detail_yes, "norefr", "star", 1, "legend" );
  print "</tr>\n<tr>\n";
  print_item( $host_url, $server_url, $lpar_url, $s_item1, "m", $type_sam,      $entitle, $detail_yes, "norefr", "star", 1, "legend" );
  print_item( $host_url, $server_url, $lpar_url, $s_item1, "y", $type_sam_year, $entitle, $detail_yes, "norefr", "star", 1, "legend" );
  print "</tr></table>";
  print "</div><br>\n";

  my $s_item2 = "";
  if ( $item =~ /sol11-global|system|total/ ) {
    $s_item2 = "s10_s";
  }
  else {
    $s_item2 = "s10_z";
  }
  $s_item2 .= "_mem";
  print "<div id=\"tabs-$tabs\">\n";
  $tabs++;
  print "<table border=\"0\">\n";
  print "<tr>";
  print_item( $host_url, $server_url, $lpar_url, $s_item2, "d", $type_sam, $entitle, $detail_yes, "norefr", "star", 1, "legend" );
  print_item( $host_url, $server_url, $lpar_url, $s_item2, "w", $type_sam, $entitle, $detail_yes, "norefr", "star", 1, "legend" );
  print "</tr>\n<tr>\n";
  print_item( $host_url, $server_url, $lpar_url, $s_item2, "m", $type_sam,      $entitle, $detail_yes, "norefr", "star", 1, "legend" );
  print_item( $host_url, $server_url, $lpar_url, $s_item2, "y", $type_sam_year, $entitle, $detail_yes, "norefr", "star", 1, "legend" );
  print "</tr></table>";
  print "</div><br>\n";

  if ( -f "$wrkdir/Solaris--unknown/no_hmc/$zone_exist/cpu.mmm" ) {
    my $s_item5 = "oscpu";
    $host_url   = "no_hmc";
    $server_url = "Solaris--unknown";
    $lpar_url   = "$zone_exist";
    print "<div id=\"tabs-$tabs\">\n";
    $tabs++;
    print "<table border=\"0\">\n";
    print "<tr>";
    print_item( $host_url, $server_url, $lpar_url, $s_item5, "d", $type_sam, $entitle, $detail_yes, "norefr", "star", 1, "legend" );
    print_item( $host_url, $server_url, $lpar_url, $s_item5, "w", $type_sam, $entitle, $detail_yes, "norefr", "star", 1, "legend" );
    print "</tr>\n<tr>\n";
    print_item( $host_url, $server_url, $lpar_url, $s_item5, "m", $type_sam,      $entitle, $detail_yes, "norefr", "star", 1, "legend" );
    print_item( $host_url, $server_url, $lpar_url, $s_item5, "y", $type_sam_year, $entitle, $detail_yes, "norefr", "star", 1, "legend" );
    print "</tr></table>";
    print "</div>\n";
  }
  if ( -f "$wrkdir/Solaris--unknown/no_hmc/$zone_exist/queue_cpu.mmm" ) {
    my $s_item_cpu_queue = "queue_cpu";
    $host_url   = "no_hmc";
    $server_url = "Solaris--unknown";
    $lpar_url   = "$zone_exist";
    print "<div id=\"tabs-$tabs\">\n";
    $tabs++;
    print "<table border=\"0\">\n";
    print "<tr>";
    print_item( $host_url, $server_url, $lpar_url, $s_item_cpu_queue, "d", $type_sam, $entitle, $detail_yes, "norefr", "star", 1, "legend" );
    print_item( $host_url, $server_url, $lpar_url, $s_item_cpu_queue, "w", $type_sam, $entitle, $detail_yes, "norefr", "star", 1, "legend" );
    print "</tr>\n<tr>\n";
    print_item( $host_url, $server_url, $lpar_url, $s_item_cpu_queue, "m", $type_sam,      $entitle, $detail_yes, "norefr", "star", 1, "legend" );
    print_item( $host_url, $server_url, $lpar_url, $s_item_cpu_queue, "y", $type_sam_year, $entitle, $detail_yes, "norefr", "star", 1, "legend" );
    print "</tr></table>";
    print "</div>\n";
  }
  if ( -f "$wrkdir/Solaris--unknown/no_hmc/$zone_exist/pgs.mmm" ) {
    my $s_item7 = "pg1";
    $host_url   = "no_hmc";
    $server_url = "Solaris--unknown";
    $lpar_url   = "$zone_exist";
    print "<div id=\"tabs-$tabs\">\n";
    $tabs++;
    print "<table border=\"0\">\n";
    print "<tr>";
    print_item( $host_url, $server_url, $lpar_url, $s_item7, "d", $type_sam, $entitle, $detail_yes, "norefr", "star", 1, "legend" );
    print_item( $host_url, $server_url, $lpar_url, $s_item7, "w", $type_sam, $entitle, $detail_yes, "norefr", "star", 1, "legend" );
    print "</tr>\n<tr>\n";
    print_item( $host_url, $server_url, $lpar_url, $s_item7, "m", $type_sam,      $entitle, $detail_yes, "norefr", "star", 1, "legend" );
    print_item( $host_url, $server_url, $lpar_url, $s_item7, "y", $type_sam_year, $entitle, $detail_yes, "norefr", "star", 1, "legend" );
    print "</tr></table>";
    print "</div>\n";
    my $s_item8 = "pg2";
    print "<div id=\"tabs-$tabs\">\n";
    $tabs++;
    print "<table border=\"0\">\n";
    print "<tr>";
    print_item( $host_url, $server_url, $lpar_url, $s_item8, "d", $type_sam, $entitle, $detail_yes, "norefr", "star", 1, "legend" );
    print_item( $host_url, $server_url, $lpar_url, $s_item8, "w", $type_sam, $entitle, $detail_yes, "norefr", "star", 1, "legend" );
    print "</tr>\n<tr>\n";
    print_item( $host_url, $server_url, $lpar_url, $s_item8, "m", $type_sam,      $entitle, $detail_yes, "norefr", "star", 1, "legend" );
    print_item( $host_url, $server_url, $lpar_url, $s_item8, "y", $type_sam_year, $entitle, $detail_yes, "norefr", "star", 1, "legend" );
    print "</tr></table>";
    print "</div>\n";
  }
  if ( -f $file_fs ) {
    print "<div id =\"tabs-$tabs\">
    <center>
    <h4>Filesystem usage</h4>
    <tbody>
    <tr>
    <table class =\"tabconfig tablesorter\"data-sortby=\"5\">
    <thead>
    <tr><th class = \"sortable\">Filesystem&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;</th>
    <th class = \"sortable\">Total [GB]&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;</th>
    <th class = \"sortable\">Used [GB]&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;</th>
    <th class = \"sortable\">Available [GB]&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;</th>
    <th class = \"sortable\">Usage [%]&nbsp;&nbsp;</th>
    <th class = \"sortable\">Mounted on&nbsp;&nbsp;</th>
    </tr></thead>\n\n";
    if ( -f "$file_fs" ) {
      open( FH, "< $file_fs" ) || error( "Cannot open $file_fs: $!" . __FILE__ . ":" . __LINE__ );
      my @file_sys_arr = <FH>;
      close(FH);
      foreach my $line (@file_sys_arr) {
        chomp($line);
        ( my $filesystem, my $blocks, my $used, my $avaliable, my $usage, my $mounted ) = split( " ", $line );
        print "<tr><td>$filesystem</td>
        <td>$blocks</td>
        <td>$used</td>
        <td>$avaliable</td>
        <td>$usage</td>
        <td>$mounted</td></tr>";
      }
    }
    my $last_update = localtime( ( stat($file_fs) )[9] );
    print "<tfoot><tr><td colspan=\"6\">Last update time: $last_update</td></tr></tfoot>";
    print "</tr>
    </tbody>
    </table>
    <div><p>You can exclude filesystem for alerting in $basedir/etc/alert_filesystem_exclude.cfg</p></div>
    </center>
    </div>\n";
    $tab_number++;
  }

  print "</div><br>\n";
  return 1;
}

sub print_solaris_ldom {
  my ( $host_url, $server_url, $lpar_url, $item, $type_sam ) = @_;
  my $tabs      = 1;
  my $ldom_uuid = urldecode("$lpar_url");
  $params{d_platform} = "solaris";

  #print "detail-cgi.pl(line7676)-$host_url,$server_url,$lpar_url,$item,$type_sam\n";
  print "<CENTER>";
  print "<div  id=\"tabs\">\n";
  print "<ul>\n";
  my @solaris_ldoms;
  my @net_path;
  my @solaris_vnet;
  if ( -d "$wrkdir/Solaris/$ldom_uuid/" ) {
    opendir( DIR, "$wrkdir/Solaris/$ldom_uuid/" ) || error( "can't opendir $wrkdir/Solaris/$ldom_uuid/: $! :" . __FILE__ . ":" . __LINE__ );
    @solaris_ldoms = grep /_ldom\.mmm$/, readdir(DIR);
    foreach my $solaris_ldom_file (@solaris_ldoms) {
      print "  <li class=\"\"><a href=\"#tabs-$tabs\">CPU</a></li>\n";
      $tabs++;
      print "  <li class=\"\"><a href=\"#tabs-$tabs\">MEM</a></li>\n";
      $tabs++;
    }
  }
  if ( -f "$wrkdir/Solaris--unknown/no_hmc/$ldom_uuid/cpu.mmm" ) {
    print "  <li class=\"\"><a href=\"#tabs-$tabs\">CPU OS</a></li>\n";
    $tabs++;
  }
  if ( -f "$wrkdir/Solaris--unknown/no_hmc/$ldom_uuid/queue_cpu.mmm" ) {
    print "  <li class=\"\"><a href=\"#tabs-$tabs\">CPU QUEUE</a></li>\n";
    $tabs++;
  }

  if ( -d "$wrkdir/Solaris--unknown/no_hmc/$ldom_uuid/JOB/" ) {
    opendir( DIR, "$wrkdir/Solaris--unknown/no_hmc/$ldom_uuid/JOB/" ) || error( "can't opendir $wrkdir/Solaris--unknown/$ldom_uuid/JOB/: $! :" . __FILE__ . ":" . __LINE__ );
    my @job_path = grep /mmc/, readdir(DIR);
    if (@job_path) {
      print "  <li class=\"\"><a href=\"#tabs-$tabs\">JOB</a></li>\n";
      $tabs++;
    }
  }

  if ( -f "$wrkdir/Solaris--unknown/no_hmc/$ldom_uuid/mem.mmm" ) {
    print "  <li class=\"\"><a href=\"#tabs-$tabs\">Memory OS</a></li>\n";
    $tabs++;
  }
  if ( -f "$wrkdir/Solaris--unknown/no_hmc/$ldom_uuid/pgs.mmm" ) {
    print "  <li class=\"\"><a href=\"#tabs-$tabs\">Paging 1</a></li>\n";
    $tabs++;
    print "  <li class=\"\"><a href=\"#tabs-$tabs\">Paging 2</a></li>\n";
    $tabs++;
  }

  my @solaris_lan_old;
  if ( -d "$wrkdir/Solaris--unknown/no_hmc/$ldom_uuid/" ) {
    opendir( DIR, "$wrkdir/Solaris--unknown/no_hmc/$ldom_uuid/" ) || error( "can't opendir $wrkdir/Solaris--unknown/no_hmc/$ldom_uuid/: $! :" . __FILE__ . ":" . __LINE__ );
    @solaris_lan_old = grep /^lan-/, readdir(DIR);
    my $k1 = 0;
    foreach my $solaris_lan_file (@solaris_lan_old) {
      if ( $k1 == 0 ) {
        $k1++;
        print "  <li class=\"\"><a href=\"#tabs-$tabs\">LAN</a></li>\n";
        $tabs++;
      }
    }
  }
  my @san_path;
  my @san_resp_path1;
  if ( -d "$wrkdir/Solaris/$ldom_uuid/" ) {
    opendir( DIR, "$wrkdir/Solaris/$ldom_uuid/" ) || error( "can't opendir $wrkdir/Solaris/$ldom_uuid/: $! :" . __FILE__ . ":" . __LINE__ );
    @san_path = grep /^san-c*/, readdir(DIR);
    my $i1 = 0;
    foreach my $san_name (@san_path) {
      if ( $san_name =~ /san/ ) {
        if ( $i1 == 0 ) {
          $i1++;
          print "  <li class=\"\"><a href=\"#tabs-$tabs\">SAN</a></li>\n";
          $tabs++;
          print "  <li class=\"\"><a href=\"#tabs-$tabs\">SAN IOPS</a></li>\n";
          $tabs++;
        }
      }
    }
    opendir( DIR, "$wrkdir/Solaris/$ldom_uuid/" ) || error( "can't opendir $wrkdir/Solaris/$ldom_uuid/: $! :" . __FILE__ . ":" . __LINE__ );
    @san_resp_path1 = grep /^san_tresp/, readdir(DIR);
    my $j1 = 0;
    foreach my $san_resp_name (@san_resp_path1) {
      if ( $san_resp_name =~ /san_tresp/ ) {
        if ( $j1 == 0 ) {
          $j1++;
          print "  <li class=\"\"><a href=\"#tabs-$tabs\">SAN RESP</a></li>\n";
          $tabs++;
        }
      }
    }
  }

  # SAN - NMON
  if ( -d "$wrkdir/Solaris--unknown/no_hmc/$ldom_uuid/" ) {
    opendir( DIR, "$wrkdir/Solaris--unknown/no_hmc/$ldom_uuid/" ) || error( "can't opendir $wrkdir/Solaris/$ldom_uuid/: $! :" . __FILE__ . ":" . __LINE__ );
    my $san_test = grep /^total-san\.mmm$/, readdir(DIR);
    if ( $san_test == 1 ) {
      print "  <li class=\"\"><a href=\"#tabs-$tabs\">SAN</a></li>\n";
      $tabs++;
      print "  <li class=\"\"><a href=\"#tabs-$tabs\">SAN IOPS</a></li>\n";
      $tabs++;
      print "  <li class=\"\"><a href=\"#tabs-$tabs\">SAN RESP</a></li>\n";
      $tabs++;
    }
  }
  if ( -d "$wrkdir/Solaris/$ldom_uuid/" ) {
    opendir( DIR, "$wrkdir/Solaris/$ldom_uuid/" ) || error( "can't opendir $wrkdir/Solaris/$ldom_uuid/: $! :" . __FILE__ . ":" . __LINE__ );
    @net_path = grep !/^\.\.?$|ZONE|_ldom\.mmm$|uuid|solaris11|solaris10|^san|pool|id|no_ldom|SUNW|ldom/, readdir(DIR);
    my $o1 = 0;
    foreach my $solaris_net_file (@net_path) {
      if ( $o1 == 0 ) {
        $o1++;
        print "  <li class=\"\"><a href=\"#tabs-$tabs\">NET</a></li>\n";
        $tabs++;
      }
    }
    opendir( DIR, "$wrkdir/Solaris/$ldom_uuid/" ) || error( "can't opendir $wrkdir/Solaris/$ldom_uuid/: $! :" . __FILE__ . ":" . __LINE__ );
    @solaris_vnet = grep /^vlan-/, readdir(DIR);
    my $p1 = 0;
    foreach my $solaris_vnet_file (@solaris_vnet) {
      if ( $p1 == 0 ) {
        $p1++;
        print "  <li class=\"\"><a href=\"#tabs-$tabs\">VNET</a></li>\n";
        $tabs++;
      }
    }
  }

  #print STDERR "1366 JCOM: \$vmware $vmware \$item $item path:$wrkdir/$server/$host/$lpar/FS.csv\n";
  my $file_fs = "$wrkdir/$server/no_hmc/$lpar/FS.csv";
  if ( -f $file_fs ) {
    print "  <li class=\"\"><a href=\"#tabs-$tabs\">FS</a></li>\n";
    $tabs++;
  }
  my @pool_path;
  if ( -d "$wrkdir/Solaris/$ldom_uuid/" ) {
    opendir( DIR, "$wrkdir/Solaris/$ldom_uuid/" ) || error( "can't opendir $wrkdir/Solaris/$ldom_uuid/: $! :" . __FILE__ . ":" . __LINE__ );
    @pool_path = grep /pool/, readdir(DIR);
    foreach my $pool_name (@pool_path) {
      if ( $pool_name =~ /pool/ ) {
        $pool_name =~ s/\.mmm//g;
        print "  <li class=\"\"><a href=\"#tabs-$tabs\">POOL: $pool_name</a></li>\n";
        $tabs++;
      }
    }
  }
  my $file_multi = "$wrkdir/Solaris/$ldom_uuid/solaris_multipathing.txt";
  if ( -f $file_multi ) {
    print "  <li class=\"\"><a href=\"#tabs-$tabs\">MULTIPATH</a></li>\n";
    $tabs++;
  }
  print "</ul>\n";

  $tabs = 1;
  foreach my $solaris_ldom_file (@solaris_ldoms) {
    my $s_item1 = "solaris_ldom_cpu";
    print "<div id=\"tabs-$tabs\">\n";
    $tabs++;
    print "<table border=\"0\">\n";
    print "<tr>";
    print_item( $host_url, $server_url, $lpar_url, $s_item1, "d", $type_sam, $entitle, $detail_yes, "norefr", "star", 1, "legend" );
    print_item( $host_url, $server_url, $lpar_url, $s_item1, "w", $type_sam, $entitle, $detail_yes, "norefr", "star", 1, "legend" );
    print "</tr>\n<tr>\n";
    print_item( $host_url, $server_url, $lpar_url, $s_item1, "m", $type_sam,      $entitle, $detail_yes, "norefr", "star", 1, "legend" );
    print_item( $host_url, $server_url, $lpar_url, $s_item1, "y", $type_sam_year, $entitle, $detail_yes, "norefr", "star", 1, "legend" );
    print "</tr></table>";
    print "</div>\n";

    my $s_item2 = "solaris_ldom_mem";
    print "<div id=\"tabs-$tabs\">\n";
    $tabs++;
    print "<table border=\"0\">\n";
    print "<tr>";
    print_item( $host_url, $server_url, $lpar_url, $s_item2, "d", $type_sam, $entitle, $detail_yes, "norefr", "star", 1, "legend" );
    print_item( $host_url, $server_url, $lpar_url, $s_item2, "w", $type_sam, $entitle, $detail_yes, "norefr", "star", 1, "legend" );
    print "</tr>\n<tr>\n";
    print_item( $host_url, $server_url, $lpar_url, $s_item2, "m", $type_sam,      $entitle, $detail_yes, "norefr", "star", 1, "legend" );
    print_item( $host_url, $server_url, $lpar_url, $s_item2, "y", $type_sam_year, $entitle, $detail_yes, "norefr", "star", 1, "legend" );
    print "</tr></table>";
    print "</div>\n";
  }
  if ( -f "$wrkdir/Solaris--unknown/no_hmc/$ldom_uuid/cpu.mmm" ) {
    my $s_item7 = "oscpu";
    $host_url   = "no_hmc";
    $server_url = "Solaris--unknown";
    $lpar_url   = "$ldom_uuid";
    print "<div id=\"tabs-$tabs\">\n";
    $tabs++;
    print "<table border=\"0\">\n";
    print "<tr>";
    print_item( $host_url, $server_url, $lpar_url, $s_item7, "d", $type_sam, $entitle, $detail_yes, "norefr", "star", 1, "legend" );
    print_item( $host_url, $server_url, $lpar_url, $s_item7, "w", $type_sam, $entitle, $detail_yes, "norefr", "star", 1, "legend" );
    print "</tr>\n<tr>\n";
    print_item( $host_url, $server_url, $lpar_url, $s_item7, "m", $type_sam,      $entitle, $detail_yes, "norefr", "star", 1, "legend" );
    print_item( $host_url, $server_url, $lpar_url, $s_item7, "y", $type_sam_year, $entitle, $detail_yes, "norefr", "star", 1, "legend" );
    print "</tr></table>";
    print "</div>\n";
  }
  if ( -f "$wrkdir/Solaris--unknown/no_hmc/$ldom_uuid/queue_cpu.mmm" ) {
    my $s_item7 = "queue_cpu";
    $host_url   = "no_hmc";
    $server_url = "Solaris--unknown";
    $lpar_url   = "$ldom_uuid";
    print "<div id=\"tabs-$tabs\">\n";
    $tabs++;
    print "<table border=\"0\">\n";
    print "<tr>";
    print_item( $host_url, $server_url, $lpar_url, $s_item7, "d", $type_sam, $entitle, $detail_yes, "norefr", "star", 1, "legend" );
    print_item( $host_url, $server_url, $lpar_url, $s_item7, "w", $type_sam, $entitle, $detail_yes, "norefr", "star", 1, "legend" );
    print "</tr>\n<tr>\n";
    print_item( $host_url, $server_url, $lpar_url, $s_item7, "m", $type_sam,      $entitle, $detail_yes, "norefr", "star", 1, "legend" );
    print_item( $host_url, $server_url, $lpar_url, $s_item7, "y", $type_sam_year, $entitle, $detail_yes, "norefr", "star", 1, "legend" );
    print "</tr></table>";
    print "</div>\n";
  }

  if ( -d "$wrkdir/Solaris--unknown/no_hmc/$ldom_uuid/JOB/" ) {
    opendir( DIR, "$wrkdir/Solaris--unknown/no_hmc/$ldom_uuid/JOB/" ) || error( "can't opendir $wrkdir/Solaris--unknown/$ldom_uuid/JOB/: $! :" . __FILE__ . ":" . __LINE__ );
    my @job_path = grep /mmc/, readdir(DIR);
    my $o = 0;
    foreach my $job_name (@job_path) {
      if ( $o == 0 ) {
        my $s_item_job1 = "jobs";
        my $s_item_job2 = "jobs_mem";
        my $server_url  = "Solaris--unknown";
        print "<div id=\"tabs-$tabs\">\n";
        $tabs++;
        $o++;
        print "<table border=\"0\">\n";
        print "<tr>";
        print_item( $host_url, $server_url, $lpar_url, $s_item_job1, "d", $type_sam, $entitle, $detail_yes, "norefr", "star", 1, "nolegend" );
        print_item( $host_url, $server_url, $lpar_url, $s_item_job1, "w", $type_sam, $entitle, $detail_yes, "norefr", "star", 1, "nolegend" );
        print "</tr>\n<tr>\n";
        print_item( $host_url, $server_url, $lpar_url, $s_item_job2, "d", $type_sam,      $entitle, $detail_yes, "norefr", "star", 1, "nolegend" );
        print_item( $host_url, $server_url, $lpar_url, $s_item_job2, "w", $type_sam_year, $entitle, $detail_yes, "norefr", "star", 1, "nolegend" );
        print "</tr></table>";
        print "</div>\n";
      }
    }
  }

  if ( -f "$wrkdir/Solaris--unknown/no_hmc/$ldom_uuid/mem.mmm" ) {
    my $s_item8 = "mem";
    $host_url   = "no_hmc";
    $server_url = "Solaris--unknown";
    $lpar_url   = "$ldom_uuid";
    print "<div id=\"tabs-$tabs\">\n";
    $tabs++;
    print "<table border=\"0\">\n";
    print "<tr>";
    print_item( $host_url, $server_url, $lpar_url, $s_item8, "d", $type_sam, $entitle, $detail_yes, "norefr", "star", 1, "legend" );
    print_item( $host_url, $server_url, $lpar_url, $s_item8, "w", $type_sam, $entitle, $detail_yes, "norefr", "star", 1, "legend" );
    print "</tr>\n<tr>\n";
    print_item( $host_url, $server_url, $lpar_url, $s_item8, "m", $type_sam,      $entitle, $detail_yes, "norefr", "star", 1, "legend" );
    print_item( $host_url, $server_url, $lpar_url, $s_item8, "y", $type_sam_year, $entitle, $detail_yes, "norefr", "star", 1, "legend" );
    print "</tr></table>";
    print "</div>\n";
  }
  if ( -f "$wrkdir/Solaris--unknown/no_hmc/$ldom_uuid/pgs.mmm" ) {
    my $s_item9 = "pg1";
    $host_url   = "no_hmc";
    $server_url = "Solaris--unknown";
    $lpar_url   = "$ldom_uuid";
    print "<div id=\"tabs-$tabs\">\n";
    $tabs++;
    print "<table border=\"0\">\n";
    print "<tr>";
    print_item( $host_url, $server_url, $lpar_url, $s_item9, "d", $type_sam, $entitle, $detail_yes, "norefr", "star", 1, "legend" );
    print_item( $host_url, $server_url, $lpar_url, $s_item9, "w", $type_sam, $entitle, $detail_yes, "norefr", "star", 1, "legend" );
    print "</tr>\n<tr>\n";
    print_item( $host_url, $server_url, $lpar_url, $s_item9, "m", $type_sam,      $entitle, $detail_yes, "norefr", "star", 1, "legend" );
    print_item( $host_url, $server_url, $lpar_url, $s_item9, "y", $type_sam_year, $entitle, $detail_yes, "norefr", "star", 1, "legend" );
    print "</tr></table>";
    print "</div>\n";
    my $s_item10 = "pg2";
    print "<div id=\"tabs-$tabs\">\n";
    $tabs++;
    print "<table border=\"0\">\n";
    print "<tr>";
    print_item( $host_url, $server_url, $lpar_url, $s_item10, "d", $type_sam, $entitle, $detail_yes, "norefr", "star", 1, "legend" );
    print_item( $host_url, $server_url, $lpar_url, $s_item10, "w", $type_sam, $entitle, $detail_yes, "norefr", "star", 1, "legend" );
    print "</tr>\n<tr>\n";
    print_item( $host_url, $server_url, $lpar_url, $s_item10, "m", $type_sam,      $entitle, $detail_yes, "norefr", "star", 1, "legend" );
    print_item( $host_url, $server_url, $lpar_url, $s_item10, "y", $type_sam_year, $entitle, $detail_yes, "norefr", "star", 1, "legend" );
    print "</tr></table>";
    print "</div>\n";
  }

  my $l = 0;
  foreach my $lan_name (@solaris_lan_old) {
    if ( $lan_name =~ /lan/ ) {
      if ( $l == 0 ) {
        my $s_item11 = "lan";
        $host_url   = "no_hmc";
        $server_url = "Solaris--unknown";
        $lpar_url   = "$ldom_uuid";
        print "<div id=\"tabs-$tabs\">\n";
        $tabs++;
        print "<table border=\"0\">\n";
        print "<tr>";
        print_item( $host_url, $server_url, $lpar_url, $s_item11, "d", $type_sam, $entitle, $detail_yes, "norefr", "star", 1, "nolegend" );
        print_item( $host_url, $server_url, $lpar_url, $s_item11, "w", $type_sam, $entitle, $detail_yes, "norefr", "star", 1, "nolegend" );
        print "</tr>\n<tr>\n";
        print_item( $host_url, $server_url, $lpar_url, $s_item11, "m", $type_sam,      $entitle, $detail_yes, "norefr", "star", 1, "nolegend" );
        print_item( $host_url, $server_url, $lpar_url, $s_item11, "y", $type_sam_year, $entitle, $detail_yes, "norefr", "star", 1, "nolegend" );
        print "</tr></table>";
        $l++;

        my $text_sum = "Summary of transferred Bytes a Day";
        $s_item11 = "slan";
        print "<table align=\"center\" summary=\"Graphs\">\n";
        print "<tr><td colspan=\"2\"><hr></td></tr>\n";
        print "<tr><td colspan=\"2\" align=\"center\"><h4>$text_sum</h4></td></tr>\n";
        print "<tr>\n";
        print_item( $host_url, $server_url, $lpar_url, $s_item11, "m", $type_sam,      $entitle, $detail_yes, "norefr", "star", 1, "legend" );
        print_item( $host_url, $server_url, $lpar_url, $s_item11, "y", $type_sam_year, $entitle, $detail_yes, "norefr", "star", 1, "legend" );
        print "</tr>\n";
        print "</table>\n";

        $s_item11 = "packets_lan";
        print "<table align=\"center\" summary=\"Graphs\">\n";
        print "<tr><td colspan=\"2\"><hr></td></tr>\n";
        print "<tr><td colspan=\"2\" align=\"center\"><h4>Packets</h4></td></tr>\n";
        print "<tr>\n";
        print_item( $host_url, $server_url, $lpar_url, $s_item11, "d", $type_sam,      $entitle, $detail_yes, "norefr", "star", 1, "nolegend" );
        print_item( $host_url, $server_url, $lpar_url, $s_item11, "w", $type_sam_year, $entitle, $detail_yes, "norefr", "star", 1, "nolegend" );
        print "</tr>\n<tr>\n";
        print_item( $host_url, $server_url, $lpar_url, $s_item11, "m", $type_sam,      $entitle, $detail_yes, "norefr", "star", 1, "nolegend" );
        print_item( $host_url, $server_url, $lpar_url, $s_item11, "y", $type_sam_year, $entitle, $detail_yes, "norefr", "star", 1, "nolegend" );
        print "</tr>\n";
        print "</table>\n";
        print "</div>\n";
      }
    }
  }
  my $m = 0;
  foreach my $san_name (@san_path) {
    if ( $san_name =~ /san-/ ) {
      if ( $m == 0 ) {
        $m++;
        my $s_item4 = "solaris_ldom_san1";
        $san_name =~ s/\.mmm//g;
        print "<div id=\"tabs-$tabs\">\n";
        $server_url = "$ldom_uuid";
        $tabs++;
        print "<table border=\"0\">\n";
        print "<tr>";
        print_item( $host_url, $server_url, $lpar_url, $s_item4, "d", $type_sam, $entitle, $detail_yes, "norefr", "star", 1, "nolegend" );
        print_item( $host_url, $server_url, $lpar_url, $s_item4, "w", $type_sam, $entitle, $detail_yes, "norefr", "star", 1, "nolegend" );
        print "</tr>\n<tr>\n";
        print_item( $host_url, $server_url, $lpar_url, $s_item4, "m", $type_sam,      $entitle, $detail_yes, "norefr", "star", 1, "nolegend" );
        print_item( $host_url, $server_url, $lpar_url, $s_item4, "y", $type_sam_year, $entitle, $detail_yes, "norefr", "star", 1, "nolegend" );
        print "</tr></table>";
        print "</div>\n";
        my $s_item5 = "solaris_ldom_san2";
        print "<div id=\"tabs-$tabs\">\n";
        $tabs++;
        print "<table border=\"0\">\n";
        print "<tr>";
        print_item( $host_url, $server_url, $lpar_url, $s_item5, "d", $type_sam, $entitle, $detail_yes, "norefr", "star", 1, "nolegend" );
        print_item( $host_url, $server_url, $lpar_url, $s_item5, "w", $type_sam, $entitle, $detail_yes, "norefr", "star", 1, "nolegend" );
        print "</tr>\n<tr>\n";
        print_item( $host_url, $server_url, $lpar_url, $s_item5, "m", $type_sam,      $entitle, $detail_yes, "norefr", "star", 1, "nolegend" );
        print_item( $host_url, $server_url, $lpar_url, $s_item5, "y", $type_sam_year, $entitle, $detail_yes, "norefr", "star", 1, "nolegend" );
        print "</tr></table>";
        print "</div>\n";
      }
    }
  }
  my @san_resp_path2;
  if ( -d "$wrkdir/Solaris/$ldom_uuid/" ) {
    opendir( DIR, "$wrkdir/Solaris/$ldom_uuid/" ) || error( "can't opendir $wrkdir/Solaris/$ldom_uuid/: $! :" . __FILE__ . ":" . __LINE__ );
    @san_resp_path2 = grep /^san_tresp/, readdir(DIR);
    my $n = 0;
    foreach my $san_resp_name (@san_resp_path2) {
      if ( $san_resp_name =~ /san_tresp/ ) {
        if ( $n == 0 ) {
          my $s_item6 = "solaris_ldom_san_resp";
          print "<div id=\"tabs-$tabs\">\n";
          $tabs++;
          $n++;
          print "<table border=\"0\">\n";
          print "<tr>";
          print_item( $host_url, $server_url, $lpar_url, $s_item6, "d", $type_sam, $entitle, $detail_yes, "norefr", "star", 1, "nolegend" );
          print_item( $host_url, $server_url, $lpar_url, $s_item6, "w", $type_sam, $entitle, $detail_yes, "norefr", "star", 1, "nolegend" );
          print "</tr>\n<tr>\n";
          print_item( $host_url, $server_url, $lpar_url, $s_item6, "m", $type_sam,      $entitle, $detail_yes, "norefr", "star", 1, "nolegend" );
          print_item( $host_url, $server_url, $lpar_url, $s_item6, "y", $type_sam_year, $entitle, $detail_yes, "norefr", "star", 1, "nolegend" );
          print "</tr></table>";
          print "</div>\n";
        }
      }
    }
  }

  my $a1 = 0;
  foreach my $solaris_net_file (@net_path) {
    if ( $a1 == 0 ) {
      $a1++;
      my $s_item3 = "solaris_ldom_net";
      print "<div id=\"tabs-$tabs\">\n";
      $tabs++;
      print "<table border=\"0\">\n";
      print "<tr>";
      print_item( $host_url, $server_url, $lpar_url, $s_item3, "d", $type_sam, $entitle, $detail_yes, "norefr", "star", 1, "nolegend" );
      print_item( $host_url, $server_url, $lpar_url, $s_item3, "w", $type_sam, $entitle, $detail_yes, "norefr", "star", 1, "nolegend" );
      print "</tr>\n<tr>\n";
      print_item( $host_url, $server_url, $lpar_url, $s_item3, "m", $type_sam,      $entitle, $detail_yes, "norefr", "star", 1, "nolegend" );
      print_item( $host_url, $server_url, $lpar_url, $s_item3, "y", $type_sam_year, $entitle, $detail_yes, "norefr", "star", 1, "nolegend" );
      print "</tr></table>";

      my $text_sum = "Summary of transferred Bytes a Day";
      $s_item3 = "solaris_ldom_sum";
      print "<table align=\"center\" summary=\"Graphs\">\n";
      print "<tr><td colspan=\"2\"><hr></td></tr>\n";
      print "<tr><td colspan=\"2\" align=\"center\"><h4>$text_sum</h4></td></tr>\n";
      print "<tr>\n";
      print_item( $host_url, $server_url, $lpar_url, $s_item3, "m", $type_sam,      $entitle, $detail_yes, "norefr", "star", 1, "legend" );
      print_item( $host_url, $server_url, $lpar_url, $s_item3, "y", $type_sam_year, $entitle, $detail_yes, "norefr", "star", 1, "legend" );
      print "</tr>\n";
      print "</table>\n";

      $s_item3 = "solaris_ldom_pack";
      print "<table align=\"center\" summary=\"Graphs\">\n";
      print "<tr><td colspan=\"2\"><hr></td></tr>\n";
      print "<tr><td colspan=\"2\" align=\"center\"><h4>Packets</h4></td></tr>\n";
      print "<tr>\n";
      print_item( $host_url, $server_url, $lpar_url, $s_item3, "d", $type_sam,      $entitle, $detail_yes, "norefr", "star", 1, "nolegend" );
      print_item( $host_url, $server_url, $lpar_url, $s_item3, "w", $type_sam_year, $entitle, $detail_yes, "norefr", "star", 1, "nolegend" );
      print "</tr>\n<tr>\n";
      print_item( $host_url, $server_url, $lpar_url, $s_item3, "m", $type_sam,      $entitle, $detail_yes, "norefr", "star", 1, "nolegend" );
      print_item( $host_url, $server_url, $lpar_url, $s_item3, "y", $type_sam_year, $entitle, $detail_yes, "norefr", "star", 1, "nolegend" );
      print "</tr></table>";
      print "</div>\n";
    }
  }
  my $q1 = 0;
  foreach my $solaris_vnet_file (@solaris_vnet) {
    if ( $q1 == 0 ) {
      my $s_item12 = "solaris_ldom_vnet";
      $host_url = "no_hmc";

      #$server_url ="Solaris--unknown";
      $lpar_url = "$ldom_uuid";
      print "<div id=\"tabs-$tabs\">\n";
      $tabs++;
      $q1++;
      print "<table border=\"0\">\n";
      print "<tr>";
      print_item( $host_url, $server_url, $lpar_url, $s_item12, "d", $type_sam, $entitle, $detail_yes, "norefr", "star", 1, "nolegend" );
      print_item( $host_url, $server_url, $lpar_url, $s_item12, "w", $type_sam, $entitle, $detail_yes, "norefr", "star", 1, "nolegend" );
      print "</tr>\n<tr>\n";
      print_item( $host_url, $server_url, $lpar_url, $s_item12, "m", $type_sam,      $entitle, $detail_yes, "norefr", "star", 1, "nolegend" );
      print_item( $host_url, $server_url, $lpar_url, $s_item12, "y", $type_sam_year, $entitle, $detail_yes, "norefr", "star", 1, "nolegend" );
      print "</tr></table>";
      print "</div>\n";
    }
  }

  # SAN NMON
  if ( -f "$wrkdir/Solaris--unknown/no_hmc/$ldom_uuid/total-san.mmm" ) {
    my $s_item1 = "sarmon_san";
    print "<div id=\"tabs-$tabs\">\n";
    $server_url = "$ldom_uuid";
    $tabs++;
    print "<table border=\"0\">\n";
    print "<tr>";
    print_item( $host_url, $server_url, $lpar_url, $s_item1, "d", $type_sam, $entitle, $detail_yes, "norefr", "star", 1, "legend" );
    print_item( $host_url, $server_url, $lpar_url, $s_item1, "w", $type_sam, $entitle, $detail_yes, "norefr", "star", 1, "legend" );
    print "</tr>\n<tr>\n";
    print_item( $host_url, $server_url, $lpar_url, $s_item1, "m", $type_sam,      $entitle, $detail_yes, "norefr", "star", 1, "legend" );
    print_item( $host_url, $server_url, $lpar_url, $s_item1, "y", $type_sam_year, $entitle, $detail_yes, "norefr", "star", 1, "legend" );
    print "</tr></table>";
    print "</div>\n";
    my $s_item2 = "sarmon_iops";
    print "<div id=\"tabs-$tabs\">\n";
    $tabs++;
    print "<table border=\"0\">\n";
    print "<tr>";
    print_item( $host_url, $server_url, $lpar_url, $s_item2, "d", $type_sam, $entitle, $detail_yes, "norefr", "star", 1, "legend" );
    print_item( $host_url, $server_url, $lpar_url, $s_item2, "w", $type_sam, $entitle, $detail_yes, "norefr", "star", 1, "legend" );
    print "</tr>\n<tr>\n";
    print_item( $host_url, $server_url, $lpar_url, $s_item2, "m", $type_sam,      $entitle, $detail_yes, "norefr", "star", 1, "legend" );
    print_item( $host_url, $server_url, $lpar_url, $s_item2, "y", $type_sam_year, $entitle, $detail_yes, "norefr", "star", 1, "legend" );
    print "</tr></table>";
    print "</div>\n";
    my $s_item3 = "sarmon_latency";
    print "<div id=\"tabs-$tabs\">\n";
    $tabs++;
    print "<table border=\"0\">\n";
    print "<tr>";
    print_item( $host_url, $server_url, $lpar_url, $s_item3, "d", $type_sam, $entitle, $detail_yes, "norefr", "star", 1, "legend" );
    print_item( $host_url, $server_url, $lpar_url, $s_item3, "w", $type_sam, $entitle, $detail_yes, "norefr", "star", 1, "legend" );
    print "</tr>\n<tr>\n";
    print_item( $host_url, $server_url, $lpar_url, $s_item3, "m", $type_sam,      $entitle, $detail_yes, "norefr", "star", 1, "legend" );
    print_item( $host_url, $server_url, $lpar_url, $s_item3, "y", $type_sam_year, $entitle, $detail_yes, "norefr", "star", 1, "legend" );
    print "</tr></table>";
    print "</div>\n";
  }
  if ( -f $file_fs ) {
    print "<div id =\"tabs-$tabs\">
    <center>
    <h4>Filesystem usage</h4>
    <tbody>
    <tr>
    <table class =\"tabconfig tablesorter\"data-sortby=\"5\">
    <thead>
    <tr><th class = \"sortable\">Filesystem&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;</th>
    <th class = \"sortable\">Total [GB]&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;</th>
    <th class = \"sortable\">Used [GB]&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;</th>
    <th class = \"sortable\">Available [GB]&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;</th>
    <th class = \"sortable\">Usage [%]&nbsp;&nbsp;</th>
    <th class = \"sortable\">Mounted on&nbsp;&nbsp;</th>
    </tr></thead>\n\n";
    if ( -f "$file_fs" ) {
      open( FH, "< $file_fs" ) || error( "Cannot open $file_fs: $!" . __FILE__ . ":" . __LINE__ );
      my @file_sys_arr = <FH>;
      close(FH);
      foreach my $line (@file_sys_arr) {
        chomp($line);
        ( my $filesystem, my $blocks, my $used, my $avaliable, my $usage, my $mounted ) = split( " ", $line );
        print "<tr><td>$filesystem</td>
        <td>$blocks</td>
        <td>$used</td>
        <td>$avaliable</td>
        <td>$usage</td>
        <td>$mounted</td></tr>";
      }
    }
    my $last_update = localtime( ( stat($file_fs) )[9] );
    print "<tfoot><tr><td colspan=\"6\">Last update time: $last_update</td></tr></tfoot>";
    print "</tr>
    </tbody>
    </table>
    <div><p>You can exclude filesystem for alerting in $basedir/etc/alert_filesystem_exclude.cfg</p></div>
    </center>
    </div>\n";
    $tab_number++;
    $tabs++;
  }

  $host_url   = $server_url;
  $server_url = "Solaris";
  my @pool_path1;
  if ( -d "$wrkdir/Solaris/$ldom_uuid/" ) {
    opendir( DIR, "$wrkdir/Solaris/$ldom_uuid/" ) || error( "can't opendir $wrkdir/Solaris/$ldom_uuid/: $! :" . __FILE__ . ":" . __LINE__ );
    @pool_path1 = grep /pool/, readdir(DIR);
    foreach my $pool_name (@pool_path1) {
      if ( $pool_name =~ /pool/ ) {
        my $s_item13 = "solaris_pool";
        print "<div id=\"tabs-$tabs\">\n";
        $pool_name =~ s/\.mmm//g;
        $tabs++;
        $host_url = $ldom_uuid;

        #$server_url = "Solaris";
        my $lpar_url = $pool_name;
        print "<table border=\"0\">\n";
        print "<tr>";
        print_item( $host_url, $server_url, $lpar_url, $s_item13, "d", $type_sam, $entitle, $detail_yes, "norefr", "star", 1, "legend" );
        print_item( $host_url, $server_url, $lpar_url, $s_item13, "w", $type_sam, $entitle, $detail_yes, "norefr", "star", 1, "legend" );
        print "</tr>\n<tr>\n";
        print_item( $host_url, $server_url, $lpar_url, $s_item13, "m", $type_sam,      $entitle, $detail_yes, "norefr", "star", 1, "legend" );
        print_item( $host_url, $server_url, $lpar_url, $s_item13, "y", $type_sam_year, $entitle, $detail_yes, "norefr", "star", 1, "legend" );
        print "</tr></table>";
        print "</div>\n";
      }
    }
  }
  if ( -f $file_multi ) {
    my $last_update = localtime( ( stat($file_multi) )[9] );
    print "<div id =\"tabs-$tabs\">
    <center>
    <tbody>
    <tr>
    <table class =\"tabconfig tablesorter\"data-sortby=\"5\">
    <thead>
    <tr><th class = \"sortable\">Disk name&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;</th>
    <th class = \"sortable\">Disk alias&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;</th>
    <th class = \"sortable\">Path properties&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;</th>
    <th class = \"sortable\">Path info&nbsp;&nbsp;</th>
    <th class = \"sortable\">Path status&nbsp;&nbsp;</th>
    </tr></thead>\n\n";
    open( FH, "< $file_multi" ) || error( "Cannot open $file_multi: $!" . __FILE__ . ":" . __LINE__ );
    my @multi_lin_arr = <FH>;
    close(FH);
    my @solaris_lines;
    foreach my $line (@multi_lin_arr) {
      chomp($line);
      my ( $string1, $string2, $string3, $string4, $string5, $string6, $string7 ) = split( /:/, $line );
      my $line_to_push = "$string1,$string2,$string3,$string4,$string5,$string6,$string7\n";
      push @solaris_lines, $line_to_push;
    }
    foreach my $line (@solaris_lines) {
      chomp($line);
      my ( $info_about, $string1, $string2, $string3, $string4 ) = split( /,/, $line );
      my ( $disk_id, $disk_alias, $vendor, $product, $revision, $name_type, $asymmetric, $curr_load_balance ) = split( /\//, $info_about );

      #print "$disk_id,$disk_alias,$vendor,$product,$revision,$name_type,$asymmetric,$curr_load_balance\n";
      $string1 =~ s/\//|/g;
      $string2 =~ s/\//|/g;
      $string3 =~ s/\//|/g;
      $string4 =~ s/\//|/g;
      my $color_ok      = "#d3f9d3";    ##### GREEN
      my $status_text   = "OK";
      my @relative_id   = split( /\|/, $string1 );
      my @disabled_info = split( /\|/, $string2 );
      my @path_states   = split( /\|/, $string3 );
      my @access_states = split( /\|/, $string4 );

      #print STDERR "$solaris_name,$disk_alias,$vendor,$product,$revision,$name_type,$asymmetric,$curr_load_balance---$relative_id[0]\n";
      #print STDERR "$disk_id,$disk_alias,$vendor,$product,$revision,$name_type,$asymmetric,$curr_load_balance\n";
      #print STDERR "$disk_id?@path_states---@access_states\n";
      print "<tr>";
      print "<td>$disk_id</td>";
      print "<td>$disk_alias</td>";
      print "<td>$vendor,$product,$revision,$name_type";
      print "<br>Asymmetric: $asymmetric,Load Balance: $curr_load_balance</br>";
      print "</td>";
      my $j = 0;
      print "<td>";
      my @ok_lines;

      foreach (@relative_id) {
        my $path_ok = "";

        #my $grep_ok = grep {/OK/} @path_states;
        #print STDERR"$grep_ok\n";
        push @ok_lines, $path_states[$j] . "\n";
        if ( $path_states[$j] eq "OK" ) {
          $path_ok = "#36B236";    ##### GREEN
        }
        else {
          $path_ok  = "#ED3027";
          $color_ok = "#ffe6b8";
        }
        if ( $access_states[$j] ) {
          print "ID:$relative_id[$j],Disabled:$disabled_info[$j],Path:<font color=$path_ok>$path_states[$j]</font>,Access:$access_states[$j]</br>";
        }
        else {
          print "ID:$relative_id[$j],Disabled:$disabled_info[$j],Path:<font color=$path_ok>$path_states[$j]</font></br>";
        }
        $j++;
      }
      print "</td>";
      my $grep_ok  = grep {/^OK$/} @ok_lines;
      my $grep_nok = grep {/^NOK$/} @ok_lines;
      if ( $grep_ok >= 1 && $grep_nok == 0 ) {    ##### OK
        $status_text = "OK";
        print "<td class=\"hs_good\" data-text='1'>$status_text</p></td>";
      }
      elsif ( $grep_ok >= 1 && $grep_nok >= 1 ) {    ##### WARNING
        $status_text = "Warning";
        print "<td class=\"hs_warning\" data-text='2'>$status_text</p></td>";
      }
      elsif ( $grep_ok == 0 && $grep_nok >= 1 ) {    ##### CRITICAL
        $status_text = "Critical";
        print "<td class=\"hs_error\" data-text='3'>$status_text</p></td>";
      }
    }
    print "<tfoot><tr><td colspan=\"5\">Last update time: $last_update</td></tr></tfoot>";
    print "</tr>
    </tbody>
    </table>
    </center>
    </div>\n";
  }

  print "</div><br>\n";
  return 1;
}

sub print_ldom_agg {

  my ( $host_url, $server_url, $lpar_url, $item, $type_sam ) = @_;
  my $tabs = 1;
  $params{d_platform} = "solaris";
  print "<CENTER>";
  print "<div  id=\"tabs\">\n";
  print "<ul>\n";
  print "  <li class=\"\"><a href=\"#tabs-$tabs\">CPU</a></li>\n";
  $tabs++;
  print "  <li class=\"\"><a href=\"#tabs-$tabs\">MEM</a></li>\n";
  print "</ul>\n";

  my $s_item1 = "solaris_ldom_agg_c";
  $tabs = 1;
  print "<div id=\"tabs-$tabs\">\n";
  $tabs++;
  print "<table border=\"0\">\n";
  print "<tr>";
  print_item( $host_url, $server_url, $lpar_url, $s_item1, "d", $type_sam, $entitle, $detail_yes, "norefr", "star", 1, "nolegend" );
  print_item( $host_url, $server_url, $lpar_url, $s_item1, "w", $type_sam, $entitle, $detail_yes, "norefr", "star", 1, "nolegend" );
  print "</tr>\n<tr>\n";
  print_item( $host_url, $server_url, $lpar_url, $s_item1, "m", $type_sam,      $entitle, $detail_yes, "norefr", "star", 1, "nolegend" );
  print_item( $host_url, $server_url, $lpar_url, $s_item1, "y", $type_sam_year, $entitle, $detail_yes, "norefr", "star", 1, "nolegend" );
  print "</tr></table>";
  print "</div><br>\n";

  my $s_item2 = "solaris_ldom_agg_m";
  print "<div id=\"tabs-$tabs\">\n";
  $tabs++;
  print "<table border=\"0\">\n";
  print "<tr>";
  print_item( $host_url, $server_url, $lpar_url, $s_item2, "d", $type_sam, $entitle, $detail_yes, "norefr", "star", 1, "nolegend" );
  print_item( $host_url, $server_url, $lpar_url, $s_item2, "w", $type_sam, $entitle, $detail_yes, "norefr", "star", 1, "nolegend" );
  print "</tr>\n<tr>\n";
  print_item( $host_url, $server_url, $lpar_url, $s_item2, "m", $type_sam,      $entitle, $detail_yes, "norefr", "star", 1, "nolegend" );
  print_item( $host_url, $server_url, $lpar_url, $s_item2, "y", $type_sam_year, $entitle, $detail_yes, "norefr", "star", 1, "nolegend" );
  print "</tr></table>";
  print "</div><br>\n";

  print "</div><br>\n";
  return 1;
}

sub print_hyperv_disk_total {
  my ( $host_url, $server_url, $lpar_url, $item, $type_sam ) = @_;
  my $tabs   = 1;
  my $my_tab = "nothing";
  $my_tab = "DATA" if ( $item =~ "hdt_data" );
  $my_tab = "IO"   if ( $item =~ "hdt_io" );

  # print STDERR "2665 $host_url, $server_url, $lpar_url, $item, $type_sam\n";
  print "<CENTER>";
  print "<div  id=\"tabs\">\n";
  print "<ul>\n";
  print "  <li class=\"\"><a href=\"#tabs-$tabs\">$my_tab</a></li>\n";
  print "</ul>\n";

  # $item="pool";
  print "<div id=\"tabs-$tabs\">\n";
  print "<table border=\"0\">\n";
  print "<tr>";
  print_item( $host_url, $server_url, $lpar_url, $item, "d", $type_sam, $entitle, $detail_yes, "norefr", "star", 1, "legend" );
  print_item( $host_url, $server_url, $lpar_url, $item, "w", $type_sam, $entitle, $detail_yes, "norefr", "star", 1, "legend" );
  print "</tr>\n<tr>\n";
  print_item( $host_url, $server_url, $lpar_url, $item, "m", $type_sam,      $entitle, $detail_yes, "norefr", "star", 1, "legend" );
  print_item( $host_url, $server_url, $lpar_url, $item, "y", $type_sam_year, $entitle, $detail_yes, "norefr", "star", 1, "legend" );
  print "</tr></table>";
  print "</div>\n";

  print "</div><br>\n";
  return 1;

}

sub print_hyperv_disk_lfd {
  my ( $host_url, $server_url, $lpar_url, $item, $type_sam ) = @_;
  my $tabs = 1;

  # print STDERR "2696 $host_url, $server_url, $lpar_url, $item, $type_sam\n";
  print "<CENTER>";
  print "<div  id=\"tabs\">\n";
  print "<ul>\n";
  print "  <li class=\"\"><a href=\"#tabs-$tabs\">Capacity</a></li>\n";
  $tabs++;
  print "  <li class=\"\"><a href=\"#tabs-$tabs\">Data</a></li>\n";
  $tabs++;
  print "  <li class=\"\"><a href=\"#tabs-$tabs\">IOPS</a></li>\n";
  $tabs++;
  print "  <li class=\"\"><a href=\"#tabs-$tabs\">Latency</a></li>\n";
  print "</ul>\n";

  $tabs = 1;

  # my $item_l = "$item"."_cat_$lpar";
  my $item_l = "$item" . "_cat_";
  print "<div id=\"tabs-$tabs\">\n";
  print "<table border=\"0\">\n";
  print "<tr>";
  print_item( $host_url, $server_url, $lpar_url, $item_l, "d", $type_sam, $entitle, $detail_yes, "norefr", "star", 1, "legend" );
  print_item( $host_url, $server_url, $lpar_url, $item_l, "w", $type_sam, $entitle, $detail_yes, "norefr", "star", 1, "legend" );
  print "</tr>\n<tr>\n";
  print_item( $host_url, $server_url, $lpar_url, $item_l, "m", $type_sam,      $entitle, $detail_yes, "norefr", "star", 1, "legend" );
  print_item( $host_url, $server_url, $lpar_url, $item_l, "y", $type_sam_year, $entitle, $detail_yes, "norefr", "star", 1, "legend" );
  print "</tr></table>";
  print "</div>\n";

  # $item_l = "$item"."_dat_$lpar";
  $item_l = "$item" . "_dat_";
  $tabs++;
  print "<div id=\"tabs-$tabs\">\n";
  print "<table border=\"0\">\n";
  print "<tr>";
  print_item( $host_url, $server_url, $lpar_url, $item_l, "d", $type_sam, $entitle, $detail_yes, "norefr", "star", 1, "legend" );
  print_item( $host_url, $server_url, $lpar_url, $item_l, "w", $type_sam, $entitle, $detail_yes, "norefr", "star", 1, "legend" );
  print "</tr>\n<tr>\n";
  print_item( $host_url, $server_url, $lpar_url, $item_l, "m", $type_sam,      $entitle, $detail_yes, "norefr", "star", 1, "legend" );
  print_item( $host_url, $server_url, $lpar_url, $item_l, "y", $type_sam_year, $entitle, $detail_yes, "norefr", "star", 1, "legend" );
  print "</tr></table>";
  print "</div>\n";

  # $item_l = "$item"."_io_$lpar";
  $item_l = "$item" . "_io_";
  $tabs++;
  print "<div id=\"tabs-$tabs\">\n";
  print "<table border=\"0\">\n";
  print "<tr>";
  print_item( $host_url, $server_url, $lpar_url, $item_l, "d", $type_sam, $entitle, $detail_yes, "norefr", "star", 1, "legend" );
  print_item( $host_url, $server_url, $lpar_url, $item_l, "w", $type_sam, $entitle, $detail_yes, "norefr", "star", 1, "legend" );
  print "</tr>\n<tr>\n";
  print_item( $host_url, $server_url, $lpar_url, $item_l, "m", $type_sam,      $entitle, $detail_yes, "norefr", "star", 1, "legend" );
  print_item( $host_url, $server_url, $lpar_url, $item_l, "y", $type_sam_year, $entitle, $detail_yes, "norefr", "star", 1, "legend" );
  print "</tr></table>";
  print "</div>\n";

  # $item_l = "$item"."_lat_$lpar";
  $item_l = "$item" . "_lat_";
  $tabs++;
  print "<div id=\"tabs-$tabs\">\n";
  print "<table border=\"0\">\n";
  print "<tr>";
  print_item( $host_url, $server_url, $lpar_url, $item_l, "d", $type_sam, $entitle, $detail_yes, "norefr", "star", 1, "legend" );
  print_item( $host_url, $server_url, $lpar_url, $item_l, "w", $type_sam, $entitle, $detail_yes, "norefr", "star", 1, "legend" );
  print "</tr>\n<tr>\n";
  print_item( $host_url, $server_url, $lpar_url, $item_l, "m", $type_sam,      $entitle, $detail_yes, "norefr", "star", 1, "legend" );
  print_item( $host_url, $server_url, $lpar_url, $item_l, "y", $type_sam_year, $entitle, $detail_yes, "norefr", "star", 1, "legend" );
  print "</tr></table>";
  print "</div>\n";

  print "</div><br>\n";
  return 1;

}

sub print_vmw_disk {
  my ( $host_url, $server_url, $lpar_url, $item, $type_sam ) = @_;
  my $tabs = 1;

  print "<CENTER>";
  print "<div  id=\"tabs\">\n";
  print "<ul>\n";
  my $tab_head = ucfirst($item);
  if ( $item =~ /^vmnet/ ) {
    $tab_head = "LAN";
  }
  print "  <li class=\"\"><a href=\"#tabs-$tabs\">$tab_head</a></li>\n";
  $tabs++;
  if ( $hyperv && $item =~ "vmdisk" ) {
    print "  <li class=\"\"><a href=\"#tabs-$tabs\">disk IO</a></li>\n";
    $tabs++;

    # print STDERR "1963 detail-cgi.pl $host_url, $server_url, $lpar_url\n";
    foreach my $local_disk (<$wrkdir/$server/$host/Local_Fixed_Disk_*>) {

      # print STDERR "1965 $local_disk\n";
      ( undef, $local_disk ) = split( "Local_Fixed_", $local_disk );
      $local_disk =~ s/\.rrm$//;
      print "  <li class=\"\"><a href=\"#tabs-$tabs\">$local_disk</a></li>\n";
      $tabs++;
    }
  }
  if ( $vmware && $item =~ "vmdisk" ) {
    print "  <li class=\"\"><a href=\"#tabs-$tabs\">Space</a></li>\n";
  }
  print "</ul>\n";

  $tabs = 1;

  # $item="pool";
  print "<div id=\"tabs-$tabs\">\n";
  $tabs++;
  print "<table border=\"0\">\n";
  print "<tr>";
  print_item( $host_url, $server_url, $lpar_url, $item, "d", $type_sam, $entitle, $detail_yes, "norefr", "star", 1, "legend" );
  print_item( $host_url, $server_url, $lpar_url, $item, "w", $type_sam, $entitle, $detail_yes, "norefr", "star", 1, "legend" );
  print "</tr>\n<tr>\n";
  print_item( $host_url, $server_url, $lpar_url, $item, "m", $type_sam,      $entitle, $detail_yes, "norefr", "star", 1, "legend" );
  print_item( $host_url, $server_url, $lpar_url, $item, "y", $type_sam_year, $entitle, $detail_yes, "norefr", "star", 1, "legend" );
  print "</tr></table>";
  print "</div>\n";

  if ( $hyperv && $item =~ "vmdisk" ) {
    my $item = "hdisk_io";
    print "<div id=\"tabs-$tabs\">\n";
    $tabs++;
    print "<table border=\"0\">\n";
    print "<tr>";
    print_item( $host_url, $server_url, $lpar_url, $item, "d", $type_sam, $entitle, $detail_yes, "norefr", "star", 1, "legend" );
    print_item( $host_url, $server_url, $lpar_url, $item, "w", $type_sam, $entitle, $detail_yes, "norefr", "star", 1, "legend" );
    print "</tr>\n<tr>\n";
    print_item( $host_url, $server_url, $lpar_url, $item, "m", $type_sam,      $entitle, $detail_yes, "norefr", "star", 1, "legend" );
    print_item( $host_url, $server_url, $lpar_url, $item, "y", $type_sam_year, $entitle, $detail_yes, "norefr", "star", 1, "legend" );
    print "</tr></table>";
    print "</div>\n";

    foreach my $local_disk (<$wrkdir/$server/$host/Local_Fixed_Disk_*>) {
      ( undef, $local_disk ) = split( "Local_Fixed_", $local_disk );
      $local_disk =~ s/\.rrm$//;
      my $item = "hdisk_$local_disk";
      print "<div id=\"tabs-$tabs\">\n";
      $tabs++;
      print "<table border=\"0\">\n";
      print "<tr>";
      print_item( $host_url, $server_url, $lpar_url, $item, "d", $type_sam, $entitle, $detail_yes, "norefr", "star", 1, "legend" );
      print_item( $host_url, $server_url, $lpar_url, $item, "w", $type_sam, $entitle, $detail_yes, "norefr", "star", 1, "legend" );
      print "</tr>\n<tr>\n";
      print_item( $host_url, $server_url, $lpar_url, $item, "m", $type_sam,      $entitle, $detail_yes, "norefr", "star", 1, "legend" );
      print_item( $host_url, $server_url, $lpar_url, $item, "y", $type_sam_year, $entitle, $detail_yes, "norefr", "star", 1, "legend" );
      print "</tr></table>";
      print "</div>\n";
    }
  }

  if ( $vmware && $item =~ "vmdisk" ) {
    my $file_html_disk = "$wrkdir/$server/$host/disk.html";
    $file_html_disk =~ s/%3A/:/g;    # host can have port vmware:444"
    my $disk_html;
    if ( -f "$file_html_disk" ) {
      my $file_timestamp = localtime( ( stat($file_html_disk) )[9] );
      open( FH, "< $file_html_disk" );
      $disk_html = do { local $/; <FH> };
      close(FH);
      print "<div id=\"tabs-$tabs\">\n";
      print "<table border=\"0\">\n";
      print "<tr><td>\n";
      print "$disk_html";
      print "</td></tr>\n";
      print "<tr><td>\n";
      print "The table is updated every run, last time:$file_timestamp<br>";
      print "</td></tr>\n";
      print "</table>\n";
      print "</div><br>\n";
    }
  }

  print "</div><br>\n";
  return 1;

}

sub print_pool {
  my ( $host_url, $server_url, $lpar_url, $item, $type_sam ) = @_;

  my $power = $vmware + $hitachi + $hyperv;
  if   ( !$power ) { $power = 1; }
  else             { $power = 0; }

  my $cpu_pool    = "CPU";
  my $lpar_vm_agg = "LPARs aggregated";
  if ( $vmware || $hyperv ) {
    $lpar_vm_agg = "VMs aggregated";
    $cpu_pool    = "CPU";
  }
  print "<CENTER>";
  print "<div  id=\"tabs\">\n";
  print "<ul>\n";
  if ($vmware) {
    print "  <li class=\"$tab_type\"><a href=\"#tabs-1\">$cpu_pool</a></li>\n";
    print "  <li class=\"$tab_type\"><a href=\"#tabs-3\">$lpar_vm_agg</a></li>\n";
    print "  <li class=\"$tab_type\"><a href=\"#tabs-31\">Power usage</a></li>\n";
    print "  <li class=\"$tab_type\"><a href=\"#tabs-4\">Configuration</a></li>\n";
  }
  elsif ($hitachi) {    # specific tabs for hitachi
    print "  <li class=\"$tab_type\"><a href=\"#tabs-1\">$cpu_pool</a></li>\n";
    print "  <li class=\"$tab_type\"><a href=\"#tabs-2\">System</a></li>\n";
    print "  <li class=\"$tab_type\"><a href=\"#tabs-3\">$lpar_vm_agg</a></li>\n";
  }
  elsif ($power) {
    my $server_path = "$basedir/data/$server_url/$host_url";
    $server_path =~ s/%([a-fA-F0-9][a-fA-F0-9])/pack("C", hex($1))/seg;    #decode from url format and check if pool/pool_total rrd files exists
                                                                           #print STDERR "Does this file exist? $server_path/pool_total.rrt or $server_path/pool_total.rxm? <br>";
                                                                           #print STDERR "ls -l $server_path/pool_total.rrt <br>";
    if ( -e "$server_path/pool_total.rrt" ) {
    }
    else {
      print STDERR "File $server_path/pool_total.rrt does not exist or something wrong<br>\n";
    }
    print "  <li class=\"$tab_type\"><a href=\"#tabs-5\">Total</a></li>\n";
    print "  <li class=\"$tab_type\"><a href=\"#tabs-6\">Total Max</a></li>\n" if ( -e "$server_path/pool_total.rxm" || 1 );
    print "  <li class=\"$tab_type\"><a href=\"#tabs-1\">Pool</a></li>\n"      if ( -e "$server_path/pool.rrm"       || 1 );
    print "  <li class=\"$tab_type\"><a href=\"#tabs-2\">Pool Max</a></li>\n"  if ( -e "$server_path/pool.xrm"       || 1 );
    print "  <li class=\"$tab_type\"><a href=\"#tabs-3\">LPARs aggregated</a></li>\n";
    my @files;
    opendir( DIR, "$server_path" ) || error( " directory does not exists : $server_path " . __FILE__ . ":" . __LINE__ ) && return 0;
    my @lpar_names = grep !/^\.\.?$/, readdir(DIR);
    closedir(DIR);

    foreach my $lpar_name (@lpar_names) {
      chomp $lpar_name;
      if ( -d "$server_path/$lpar_name" ) {
        opendir( DIR, "$server_path/$lpar_name/" ) || error( " directory does not exists : $server_path/$lpar_name/ " . __FILE__ . ":" . __LINE__ ) && return 0;
        my @error_fcs = grep /^san_error/, readdir(DIR);
        closedir(DIR);
        foreach my $error_fc (@error_fcs) {
          if ( -f "$server_path/$lpar_name/$error_fc" ) {
            push @files, "$server_path/$lpar_name/$error_fc\n";
          }
        }
      }
    }
    if (@files) {
      print "  <li class=\"$tab_type\"><a href=\"#tabs-7\">FC errors aggregated</a></li>\n";
    }
    print "  <li class=\"$tab_type\"><a href=\"#tabs-4\">Configuration</a></li>\n";
  }
  elsif ($hyperv) {
    print "  <li class=\"$tab_type\"><a href=\"#tabs-1\">$cpu_pool</a></li>\n";
    if ( -f "$wrkdir/$server/$host/VM_hosting.vmh" ) {
      print "  <li class=\"$tab_type\"><a href=\"#tabs-3\">$lpar_vm_agg</a></li>\n";
    }
    print "  <li class=\"$tab_type\"><a href=\"#tabs-4\">Configuration</a></li>\n";

    # here come all other hyperv tabs mem + net + data + io
    print "  <li class=\"$tab_type\"><a href=\"#tabs-5\">Allocation</a></li>\n";
    print "  <li class=\"$tab_type\"><a href=\"#tabs-6\">Paging</a></li>\n";
    print "  <li class=\"$tab_type\"><a href=\"#tabs-7\">LAN</a></li>\n";
    print "  <li class=\"$tab_type\"><a href=\"#tabs-8\">Data</a></li>\n";
    print "  <li class=\"$tab_type\"><a href=\"#tabs-9\">IOPS</a></li>\n";
  }
  print "</ul>\n";

  # Main server pool
  my $refresh_name = "CPU%20pool";
  my $refresh      = "<div class=\"refresh fas fa-sync-alt\"><A HREF=\"/lpar2rrd-cgi/lpar2rrd-realt.sh?source=$refresh_name&hmc=$host_url&mname=$server_url&new_gui=$gui\"></A></div>\n";
  $item = "pool";
  print "<div id=\"tabs-1\">\n";
  print "<table border=\"0\">\n";
  print "<tr>";
  print_item( $host_url, $server_url, $lpar_url, $item, "d", $type_sam, $entitle, $detail_yes, $refresh, "star", 1, "legend" );
  print_item( $host_url, $server_url, $lpar_url, $item, "w", $type_sam, $entitle, $detail_yes, "norefr", "star", 1, "legend" );
  print "</tr>\n<tr>\n";
  print_item( $host_url, $server_url, $lpar_url, $item, "m", $type_sam, $entitle, $detail_yes, "norefr", "star", 1, "legend" );
  print_item( $host_url, $server_url, $lpar_url, $item, "y", $type_sam, $entitle, $detail_yes, "norefr", "star", 1, "legend" );
  print "</tr>";
  print "<tr>";
  $item = "trendpool";

  if ( !$vmware && !$hyperv ) {
    print_item( $host_url, $server_url, $lpar_url, $item, "y", $type_sam, $entitle, $detail_yes, "norefr", "nostar", 2, "legend" );
  }
  print "</tr></table>";
  print "</div>";

  if ($power) {    # do not use on our DEMO site

    # Main server pool - MAX
    $item = "pool-max";
    print "<div id=\"tabs-2\">\n";
    print "<div id=\"hiw\"><a href=\"http://www.lpar2rrd.com/max_vrs_average.html\" target=\"_blank\" class=\"nowrap\"><img src=\"css/images/help-browser.gif\" alt=\"Maximum versus Average\" title=\"Maximum versus Average\"></img></a></div>";
    print "<table border=\"0\">\n";
    print "<tr>";
    print_item( $host_url, $server_url, $lpar_url, $item, "d", $type_sam, $entitle, $detail_yes, "norefr", "star", 1, "legend" );
    print_item( $host_url, $server_url, $lpar_url, $item, "w", $type_sam, $entitle, $detail_yes, "norefr", "star", 1, "legend" );
    print "</tr>\n<tr>\n";
    print_item( $host_url, $server_url, $lpar_url, $item, "m", $type_sam, $entitle, $detail_yes, "norefr", "star", 1, "legend" );
    print_item( $host_url, $server_url, $lpar_url, $item, "y", $type_sam, $entitle, $detail_yes, "norefr", "star", 1, "legend" );
    print "</tr>";
    print "<tr>";
    $item = "trendpool-max";

    if ( !$vmware ) {
      print_item( $host_url, $server_url, $lpar_url, $item, "y", $type_sam, $entitle, $detail_yes, "norefr", "nostar", 2, "legend" );
    }
    print "</tr></table>";
    print "</div>";

    # Main server pool total
    $item = "pool-total";
    print "<div id=\"tabs-5\">\n";
    print "<div id=\"hiw\"><a href=\"https://www.lpar2rrd.com/IBM-Power-Total.php\" target=\"_blank\" class=\"nowrap\"><img src=\"css/images/help-browser.gif\" alt=\"CPU Total info\" title=\"CPU Total info\"></img></a></div>";
    print "<table border=\"0\">\n";
    print "<tr>";
    print_item( $host_url, $server_url, $lpar_url, $item, "d", $type_sam, $entitle, $detail_yes, "norefr", "star", 1, "legend" );
    print_item( $host_url, $server_url, $lpar_url, $item, "w", $type_sam, $entitle, $detail_yes, "norefr", "star", 1, "legend" );
    print "</tr>\n<tr>\n";
    print_item( $host_url, $server_url, $lpar_url, $item, "m", $type_sam, $entitle, $detail_yes, "norefr", "star", 1, "legend" );
    print_item( $host_url, $server_url, $lpar_url, $item, "y", $type_sam, $entitle, $detail_yes, "norefr", "star", 1, "legend" );
    print "</tr>";
    print "<tr>";
    $item = "trendpool-total";
    print_item( $host_url, $server_url, $lpar_url, $item, "y", $type_sam, $entitle, $detail_yes, "norefr", "nostar", 2, "legend" );

    print "</tr></table>";
    print "</div>";

    $item = "pool-total-max";
    print "<div id=\"tabs-6\">\n";
    print "<div id=\"hiw\"><a href=\"http://www.lpar2rrd.com/max_vrs_average.html\" target=\"_blank\" class=\"nowrap\"><img src=\"css/images/help-browser.gif\" alt=\"Maximum versus Average\" title=\"Maximum versus Average\"></img></a></div>";
    print "<table border=\"0\">\n";
    print "<tr>";
    print_item( $host_url, $server_url, $lpar_url, $item, "d", $type_sam, $entitle, $detail_yes, "norefr", "star", 1, "legend" );
    print_item( $host_url, $server_url, $lpar_url, $item, "w", $type_sam, $entitle, $detail_yes, "norefr", "star", 1, "legend" );
    print "</tr>\n<tr>\n";
    print_item( $host_url, $server_url, $lpar_url, $item, "m", $type_sam, $entitle, $detail_yes, "norefr", "star", 1, "legend" );
    print_item( $host_url, $server_url, $lpar_url, $item, "y", $type_sam, $entitle, $detail_yes, "norefr", "star", 1, "legend" );
    print "</tr>";
    print "<tr>";
    $item = "trendpool-total-max";
    print_item( $host_url, $server_url, $lpar_url, $item, "y", $type_sam, $entitle, $detail_yes, "norefr", "nostar", 2, "legend" );

    print "</tr></table>";
    print "</div>";

  }

  if ($hitachi) {
    $item = "system";

    print "<div id=\"tabs-2\">\n";
    print "<table border=\"0\">\n";
    print "<tr>";
    print_item( $host_url, $server_url, $lpar_url, $item, "d", $type_sam, $entitle, $detail_yes, $refresh, "star", 1, "legend" );
    print_item( $host_url, $server_url, $lpar_url, $item, "w", $type_sam, $entitle, $detail_yes, "norefr", "star", 1, "legend" );
    print "</tr>\n<tr>\n";
    print_item( $host_url, $server_url, $lpar_url, $item, "m", $type_sam,      $entitle, $detail_yes, "norefr", "star", 1, "legend" );
    print_item( $host_url, $server_url, $lpar_url, $item, "y", $type_sam_year, $entitle, $detail_yes, "norefr", "star", 1, "legend" );
    print "</tr>";
    print "<tr>";
    print "</tr></table>";
    print "</div><br>\n";
  }

  # Main pool - aggregated
  my $updated_date = "";
  if ( $hyperv && !-f "$wrkdir/$server/$host/VM_hosting.vmh" ) {

    # nothing
  }
  else {
    $item     = "lparagg";
    $lpar_url = "pool-multi";
    print "<div id=\"tabs-3\">\n";
    if ($vmware) {
      print "$question_mark";
    }
    print "<table border=\"0\">\n";
    print "<tr>";
    print_item( $host_url, $server_url, $lpar_url, $item, "d", $type_sam, $entitle, $detail_yes, "norefr", "star", 1, "nolegend" );
    print_item( $host_url, $server_url, $lpar_url, $item, "w", $type_sam, $entitle, $detail_yes, "norefr", "star", 1, "nolegend" );
    print "</tr>\n<tr>\n";
    print_item( $host_url, $server_url, $lpar_url, $item, "m", $type_sam, $entitle, $detail_yes, "norefr", "star", 1, "nolegend" );
    print_item( $host_url, $server_url, $lpar_url, $item, "y", $type_sam, $entitle, $detail_yes, "norefr", "star", 1, "nolegend" );
    print "</tr></table>";
    print "</div>";

    if ($vmware) {
      print "<div id=\"tabs-31\">\n";
      print "<table border=\"0\">\n";
      print "<tr>";

      $item = "esxipow";
      print_item( $host_url, $server_url, $lpar_url, $item, "d", $type_sam, $entitle, $detail_yes, "norefr", "nostar", 1, "legend" );
      print_item( $host_url, $server_url, $lpar_url, $item, "w", $type_sam, $entitle, $detail_yes, "norefr", "nostar", 1, "legend" );
      print "</tr>\n<tr>\n";
      print_item( $host_url, $server_url, $lpar_url, $item, "m", $type_sam,      $entitle, $detail_yes, "norefr", "nostar", 1, "legend" );
      print_item( $host_url, $server_url, $lpar_url, $item, "y", $type_sam_year, $entitle, $detail_yes, "norefr", "nostar", 1, "legend" );
      print "</tr>";

      # print "<tr><td colspan=\"2\" align=\"left\">";
      # print "</td>";
      print "</tr></table>";
      print "</div>";
    }
    print "<div id=\"tabs-7\">\n";
    if ($vmware) {
      print "$question_mark";
    }
    else {
      $item     = "error_aggr";
      $lpar_url = "error-aggr";
      print "<table border=\"0\">\n";
      print "<tr>";
      print_item( $host_url, $server_url, $lpar_url, $item, "d", $type_sam, $entitle, $detail_yes, "norefr", "star", 1, "nolegend" );
      print_item( $host_url, $server_url, $lpar_url, $item, "w", $type_sam, $entitle, $detail_yes, "norefr", "star", 1, "nolegend" );
      print "</tr>\n<tr>\n";
      print_item( $host_url, $server_url, $lpar_url, $item, "m", $type_sam, $entitle, $detail_yes, "norefr", "star", 1, "nolegend" );
      print_item( $host_url, $server_url, $lpar_url, $item, "y", $type_sam, $entitle, $detail_yes, "norefr", "star", 1, "nolegend" );
      print "</tr></table>";
      print "</div>";
    }
  }

  if ( !$hitachi ) {
    my $file_html_cpu = "$wrkdir/$server/$host/cpu.html";

    # print STDERR "2627 \$hyperv $hyperv \$file_html_cpu $file_html_cpu\n";
    if ($hyperv) {
      my $file_html_server = "$wrkdir/$server/$host/server.html";
      $file_html_server =~ s/%3A/:/g;    # host can have port vmware:444"
      my $server_html;
      if ( -f "$file_html_server" ) {

        # print "The table is updated every run, last time:$file_timestamp<br>";
        $updated_date = localtime( ( stat($file_html_server) )[9] );
        open( FH, "< $file_html_server" );
        $server_html = do { local $/; <FH> };
        close(FH);
        print "<div id=\"tabs-4\">\n";
        print "<table border=\"0\">\n";
        print "<tr><td>\n";
        print "$server_html";
        print "</td></tr>\n";
      }
      $file_html_server = "$wrkdir/$server/$host/NetworkAdapterConfiguration.html";

      # $server_html;
      if ( -f "$file_html_server" ) {
        open( FH, "<:encoding(UTF-8)", "$file_html_server" );
        $server_html = do { local $/; <FH> };
        close(FH);
        print "<td>\n";
        print "$server_html";
        print "</td>\n";
      }
    }
    if ( -f "$file_html_cpu" ) {
      open( FH, "< $file_html_cpu" );
      my $cpu_html = do { local $/; <FH> };
      close(FH);
      print "<div id=\"tabs-4\">\n";
      print "<table border=\"0\">\n";
      print "<tr><td>\n";
      print "$cpu_html";
      print "</td></tr>\n";

      if ($hyperv) {
        my $file_html_vhd_list = "$wrkdir/$server/$host/vhd_list.html";
        $file_html_vhd_list =~ s/%3A/:/g;    # host can have port vmware:444"
        my $vhd_list_html;
        if ( -f "$file_html_vhd_list" ) {
          open( FH, "< $file_html_vhd_list" );
          $vhd_list_html = do { local $/; <FH> };
          close(FH);
          print "<tr><td>\n";
          print "$vhd_list_html";
          print "</td></tr>\n";
        }
      }
      print "<tr><td>\n";

      if ( !$vmware && !$hyperv ) {
        print "The table is updated once a day<br>";

        #print "<A HREF=\"$host_url/$server_url/config.html#CPU_pool\">Detailed configuration</A>";
      }
      elsif ($vmware) {
        print "The table is updated every run<br>";
      }
      elsif ($hyperv) {

        # print "Tables are updated every run<br>";
        print "Tables are updated every run, last time:$updated_date<br>";
      }
      print "</td></tr>\n";
      print "</table>\n";
      print "</div>";
      if ($hyperv) {

        # Memory allocation
        print "<div id=\"tabs-5\">\n";
        print "<table border=\"0\">\n";
        print "<tr>";

        $item = "memalloc";
        print_item( $host_url, $server_url, $lpar_url, $item, "d", $type_sam, $entitle, $detail_yes, "norefr", "star", 1, "legend" );
        print_item( $host_url, $server_url, $lpar_url, $item, "w", $type_sam, $entitle, $detail_yes, "norefr", "star", 1, "legend" );
        print "</tr>\n<tr>\n";
        print_item( $host_url, $server_url, $lpar_url, $item, "m", $type_sam,      $entitle, $detail_yes, "norefr", "star", 1, "legend" );
        print_item( $host_url, $server_url, $lpar_url, $item, "y", $type_sam_year, $entitle, $detail_yes, "norefr", "star", 1, "legend" );
        print "</tr>";
        print "<tr>";
        $item = "trendmemalloc";

        #maybe later
        print "</tr></table>";
        print "</div>\n";

        # paging
        print "<div id=\"tabs-6\">\n";
        print "<table border=\"0\">\n";
        print "<tr>";
        $item = "hyppg1";
        print_item( $host_url, $server_url, $lpar_url, $item, "d", $type_sam, $entitle, $detail_yes, "norefr", "star", 1, "legend" );
        print_item( $host_url, $server_url, $lpar_url, $item, "w", $type_sam, $entitle, $detail_yes, "norefr", "star", 1, "legend" );
        print "</tr>\n<tr>\n";
        print_item( $host_url, $server_url, $lpar_url, $item, "m", $type_sam,      $entitle, $detail_yes, "norefr", "star", 1, "legend" );
        print_item( $host_url, $server_url, $lpar_url, $item, "y", $type_sam_year, $entitle, $detail_yes, "norefr", "star", 1, "legend" );
        print "</tr></table>";
        print "</div>\n";

        #LAN
        print "<div id=\"tabs-7\">\n";
        print "<table border=\"0\">\n";
        print "<tr>";
        $item = "vmnetrw";
        print_item( $host_url, $server_url, $lpar_url, $item, "d", $type_sam, $entitle, $detail_yes, "norefr", "star", 1, "legend" );
        print_item( $host_url, $server_url, $lpar_url, $item, "w", $type_sam, $entitle, $detail_yes, "norefr", "star", 1, "legend" );
        print "</tr>\n<tr>\n";
        print_item( $host_url, $server_url, $lpar_url, $item, "m", $type_sam,      $entitle, $detail_yes, "norefr", "star", 1, "legend" );
        print_item( $host_url, $server_url, $lpar_url, $item, "y", $type_sam_year, $entitle, $detail_yes, "norefr", "star", 1, "legend" );
        print "</tr></table>";
        print "</div>\n";

        $item = "hdt_data";

        # print STDERR "2665 $host_url, $server_url, $lpar_url, $item, $type_sam\n";

        print "<div id=\"tabs-8\">\n";
        print "<table border=\"0\">\n";
        print "<tr>";
        print_item( $host_url, $server_url, $lpar_url, $item, "d", $type_sam, $entitle, $detail_yes, "norefr", "star", 1, "legend" );
        print_item( $host_url, $server_url, $lpar_url, $item, "w", $type_sam, $entitle, $detail_yes, "norefr", "star", 1, "legend" );
        print "</tr>\n<tr>\n";
        print_item( $host_url, $server_url, $lpar_url, $item, "m", $type_sam,      $entitle, $detail_yes, "norefr", "star", 1, "legend" );
        print_item( $host_url, $server_url, $lpar_url, $item, "y", $type_sam_year, $entitle, $detail_yes, "norefr", "star", 1, "legend" );
        print "</tr></table>";
        print "</div>\n";

        $item = "hdt_io";

        # print STDERR "2665 $host_url, $server_url, $lpar_url, $item, $type_sam\n";

        print "<div id=\"tabs-9\">\n";
        print "<table border=\"0\">\n";
        print "<tr>";
        print_item( $host_url, $server_url, $lpar_url, $item, "d", $type_sam, $entitle, $detail_yes, "norefr", "star", 1, "legend" );
        print_item( $host_url, $server_url, $lpar_url, $item, "w", $type_sam, $entitle, $detail_yes, "norefr", "star", 1, "legend" );
        print "</tr>\n<tr>\n";
        print_item( $host_url, $server_url, $lpar_url, $item, "m", $type_sam,      $entitle, $detail_yes, "norefr", "star", 1, "legend" );
        print_item( $host_url, $server_url, $lpar_url, $item, "y", $type_sam_year, $entitle, $detail_yes, "norefr", "star", 1, "legend" );
        print "</tr></table>";
        print "</div>\n";

      }
    }
  }

  print "</div><br>\n";
  return 1;
}

sub print_hyperv_pool_html {
  my ( $host_url, $server_url, $lpar_url, $item, $type_sam, $tab_num ) = @_;
  my $tab_num_orig = $tab_num;
  my $server       = urldecode($server_url);
  my $host         = urldecode($host_url);

  # Main server pool
  my $refresh_name = "CPU%20pool";
  my $refresh      = "<div class=\"refresh fas fa-sync-alt\"><A HREF=\"/lpar2rrd-cgi/lpar2rrd-realt.sh?source=$refresh_name&hmc=$host_url&mname=$server_url&new_gui=$gui\"></A></div>\n";
  $item = "pool";
  print "<CENTER>";
  print "<div id=\"tabs-$tab_num\">\n";
  $tab_num++;
  print "<table border=\"0\">\n";
  print "<tr>";
  print_item( $host_url, $server_url, $lpar_url, $item, "d", $type_sam, $entitle, $detail_yes, $refresh, "star", 1, "legend" );
  print_item( $host_url, $server_url, $lpar_url, $item, "w", $type_sam, $entitle, $detail_yes, "norefr", "star", 1, "legend" );
  print "</tr>\n<tr>\n";
  print_item( $host_url, $server_url, $lpar_url, $item, "m", $type_sam, $entitle, $detail_yes, "norefr", "star", 1, "legend" );
  print_item( $host_url, $server_url, $lpar_url, $item, "y", $type_sam, $entitle, $detail_yes, "norefr", "star", 1, "legend" );
  print "</tr>";
  print "<tr>";
  $item = "trendpool";

  print "</tr></table>";
  print "</div>";

  # CPU queue
  if ( -f "$wrkdir/$server/$host/CPUqueue.rrm" ) {
    $item = "cpuqueue";
    print "<CENTER>";
    print "<div id=\"tabs-$tab_num\">\n";
    $tab_num++;
    print "<table border=\"0\">\n";
    print "<tr>";
    print_item( $host_url, $server_url, $lpar_url, $item, "d", $type_sam, $entitle, $detail_yes, "norefr", "star", 1, "legend" );
    print_item( $host_url, $server_url, $lpar_url, $item, "w", $type_sam, $entitle, $detail_yes, "norefr", "star", 1, "legend" );
    print "</tr>\n<tr>\n";
    print_item( $host_url, $server_url, $lpar_url, $item, "m", $type_sam, $entitle, $detail_yes, "norefr", "star", 1, "legend" );
    print_item( $host_url, $server_url, $lpar_url, $item, "y", $type_sam, $entitle, $detail_yes, "norefr", "star", 1, "legend" );
    print "</tr>";
    print "<tr>";

    print "</tr></table>";
    print "</div>";
  }

  # CPU processes and threads
  if ( -f "$wrkdir/$server/$host/CPUqueue.rrm" ) {
    $item = "cpu_process";
    print "<CENTER>";
    print "<div id=\"tabs-$tab_num\">\n";
    $tab_num++;
    print "<table border=\"0\">\n";
    print "<tr>";
    print_item( $host_url, $server_url, $lpar_url, $item, "d", $type_sam, $entitle, $detail_yes, "norefr", "star", 1, "legend" );
    print_item( $host_url, $server_url, $lpar_url, $item, "w", $type_sam, $entitle, $detail_yes, "norefr", "star", 1, "legend" );
    print "</tr>\n<tr>\n";
    print_item( $host_url, $server_url, $lpar_url, $item, "m", $type_sam, $entitle, $detail_yes, "norefr", "star", 1, "legend" );
    print_item( $host_url, $server_url, $lpar_url, $item, "y", $type_sam, $entitle, $detail_yes, "norefr", "star", 1, "legend" );
    print "</tr>";

    print "</tr></table>";
    print "</div>";
  }

  if ( job_dir_lives("$wrkdir/$server/$host") ) {
    print "<div id=\"tabs-$tab_num\">\n";
    $tab_num++;

    print "<table align=\"center\" summary=\"Graphs\">\n";
    print "<CENTER>";
    print '<tr><td colspan="2" align="center"><h4>JOB CPU</h4></td></tr>';

    # print STDERR "12486 $host_url, $server_url, $lpar_url ,$false_picture,\n";
    my $server   = "windows";
    my $computer = $server_url;
    $computer =~ s/.*domain//;
    $computer = "domain$computer";

    # print STDERR "12491 \$host_url $host_url \$server $server \$computer $computer\n";
    my $legend = "nolegend";
    print "<tr>\n";

    $item = "jobs";
    print_item( $computer, $server, $host_url, $item, "d", $type_sam, $entitle, $detail_yes, "norefr", "star", 1, $legend );
    $false_picture = "do not print" if $false_picture ne "";
    print_item( $computer, $server, $host_url, $item, "w", $type_sam, $entitle, $detail_yes, "norefr", "star", 1, $legend );
    print "</tr>\n";

    print "</table>";
    print "<table align=\"center\" summary=\"Graphs\">\n";
    $item = "jobs_mem";
    print "<tr><td colspan=\"2\" align=\"center\"><h4>JOB MEM</h4></td></tr>\n";
    print "<tr>\n";
    print_item( $computer, $server, $host_url, $item, "d", $type_sam,      $entitle, $detail_yes, "norefr", "star", 1, $legend );
    print_item( $computer, $server, $host_url, $item, "w", $type_sam_year, $entitle, $detail_yes, "norefr", "star", 1, $legend );
    print "</tr>\n";
    print "<tr>";

    print "</tr></table>";
    print "</div>";
  }

  # Main pool - aggregated
  my $updated_date = "";

  # print STDERR "4641 $wrkdir/$server/$host/VM_hosting.vmh\n";

  if ( !-f "$wrkdir/$server/$host/VM_hosting.vmh" ) {

    # nothing
  }
  else {
    $item     = "lparagg";
    $lpar_url = "pool-multi";
    print "<div id=\"tabs-$tab_num\">\n";
    $tab_num++;
    print "$question_mark";
    print "<table border=\"0\">\n";
    print "<tr>";
    print_item( $host_url, $server_url, $lpar_url, $item, "d", $type_sam, $entitle, $detail_yes, "norefr", "star", 1, "nolegend" );
    print_item( $host_url, $server_url, $lpar_url, $item, "w", $type_sam, $entitle, $detail_yes, "norefr", "star", 1, "nolegend" );
    print "</tr>\n<tr>\n";
    print_item( $host_url, $server_url, $lpar_url, $item, "m", $type_sam, $entitle, $detail_yes, "norefr", "star", 1, "nolegend" );
    print_item( $host_url, $server_url, $lpar_url, $item, "y", $type_sam, $entitle, $detail_yes, "norefr", "star", 1, "nolegend" );
    print "</tr></table>";
    print "</div>";
  }

  my $file_html_cpu = "$wrkdir/$server/$host/cpu.html";

  # print STDERR "2627 \$hyperv $hyperv \$file_html_cpu $file_html_cpu\n";
  print "<div id=\"tabs-$tab_num\">\n";
  $tab_num++;

  my $file_html_server = "$wrkdir/$server/$host/server.html";
  $file_html_server =~ s/%3A/:/g;    # host can have port vmware:444"
  my $server_html;
  if ( -f "$file_html_server" ) {

    # print "The table is updated every run, last time:$file_timestamp<br>";
    $updated_date = localtime( ( stat($file_html_server) )[9] );
    open( FH, '<:encoding(UTF-8)', $file_html_server );
    $server_html = do { local $/; <FH> };
    close(FH);

    # print "<div id=\"tabs-$tab_num\">\n";
    # $tab_num++;
    print "<table border=\"0\">\n";
    print "<tr><td>\n";
    print "$server_html";
    print "</td></tr>\n";
  }
  $file_html_server = "$wrkdir/$server/$host/NetworkAdapterConfiguration.html";

  # $server_html;
  if ( -f "$file_html_server" ) {
    open( FH, "<:encoding(UTF-8)", "$file_html_server" );
    $server_html = do { local $/; <FH> };
    close(FH);
    print "<td>\n";
    print "$server_html";
    print "</td>\n";
  }

  if ( -f "$file_html_cpu" ) {
    open( FH, '<:encoding(UTF-8)', $file_html_cpu );
    my $cpu_html = do { local $/; <FH> };
    close(FH);

    # print "<div id=\"tabs-$tab_num\">\n";
    # $tab_num++;
    print "<table border=\"0\">\n";
    print "<tr><td>\n";
    print "$cpu_html";
    print "</td></tr>\n";
    if ($hyperv) {
      my $file_html_vhd_list = "$wrkdir/$server/$host/vhd_list.html";
      $file_html_vhd_list =~ s/%3A/:/g;    # host can have port vmware:444"
      my $vhd_list_html;
      if ( -f "$file_html_vhd_list" ) {
        open( FH, '<:encoding(UTF-8)', $file_html_vhd_list );
        $vhd_list_html = do { local $/; <FH> };
        close(FH);
        print "<tr><td>\n";
        print "$vhd_list_html";
        print "</td></tr>\n";
      }
    }
    print "<tr><td>\n";

    print "Tables are updated every run, last time:$updated_date<br>";

    print "</td></tr>\n";
    print "</table>\n";
    print "</div>";

    # Memory allocation
    print "<div id=\"tabs-$tab_num\">\n";
    $tab_num++;
    print "<table border=\"0\">\n";
    print "<tr>";

    $item = "memalloc";
    print_item( $host_url, $server_url, $lpar_url, $item, "d", $type_sam, $entitle, $detail_yes, "norefr", "star", 1, "legend" );
    print_item( $host_url, $server_url, $lpar_url, $item, "w", $type_sam, $entitle, $detail_yes, "norefr", "star", 1, "legend" );
    print "</tr>\n<tr>\n";
    print_item( $host_url, $server_url, $lpar_url, $item, "m", $type_sam,      $entitle, $detail_yes, "norefr", "star", 1, "legend" );
    print_item( $host_url, $server_url, $lpar_url, $item, "y", $type_sam_year, $entitle, $detail_yes, "norefr", "star", 1, "legend" );
    print "</tr>";
    print "<tr>";
    $item = "trendmemalloc";

    #maybe later
    print "</tr></table>";
    print "</div>\n";

    # paging
    print "<div id=\"tabs-$tab_num\">\n";
    $tab_num++;
    print "<table border=\"0\">\n";
    print "<tr>";
    $item = "hyppg1";
    print_item( $host_url, $server_url, $lpar_url, $item, "d", $type_sam, $entitle, $detail_yes, "norefr", "star", 1, "legend" );
    print_item( $host_url, $server_url, $lpar_url, $item, "w", $type_sam, $entitle, $detail_yes, "norefr", "star", 1, "legend" );
    print "</tr>\n<tr>\n";
    print_item( $host_url, $server_url, $lpar_url, $item, "m", $type_sam,      $entitle, $detail_yes, "norefr", "star", 1, "legend" );
    print_item( $host_url, $server_url, $lpar_url, $item, "y", $type_sam_year, $entitle, $detail_yes, "norefr", "star", 1, "legend" );
    print "</tr></table>";
    print "</div>\n";

    # paging 2
    if ( -f "$wrkdir/$server/$host/page_file_name.txt" ) {
      print "<div id=\"tabs-$tab_num\">\n";
      $tab_num++;
      print "<table border=\"0\">\n";
      print "<tr>";
      $item = "hyppg2";
      print_item( $host_url, $server_url, $lpar_url, $item, "d", $type_sam, $entitle, $detail_yes, "norefr", "star", 1, "legend" );
      print_item( $host_url, $server_url, $lpar_url, $item, "w", $type_sam, $entitle, $detail_yes, "norefr", "star", 1, "legend" );
      print "</tr>\n<tr>\n";
      print_item( $host_url, $server_url, $lpar_url, $item, "m", $type_sam,      $entitle, $detail_yes, "norefr", "star", 1, "legend" );
      print_item( $host_url, $server_url, $lpar_url, $item, "y", $type_sam_year, $entitle, $detail_yes, "norefr", "star", 1, "legend" );
      print "</tr></table>";
      print "</div>\n";
    }

    #LAN
    print "<div id=\"tabs-$tab_num\">\n";
    $tab_num++;
    print "<table border=\"0\">\n";
    print "<tr>";
    $item = "vmnetrw";
    print_item( $host_url, $server_url, $lpar_url, $item, "d", $type_sam, $entitle, $detail_yes, "norefr", "star", 1, "legend" );
    print_item( $host_url, $server_url, $lpar_url, $item, "w", $type_sam, $entitle, $detail_yes, "norefr", "star", 1, "legend" );
    print "</tr>\n<tr>\n";
    print_item( $host_url, $server_url, $lpar_url, $item, "m", $type_sam,      $entitle, $detail_yes, "norefr", "star", 1, "legend" );
    print_item( $host_url, $server_url, $lpar_url, $item, "y", $type_sam_year, $entitle, $detail_yes, "norefr", "star", 1, "legend" );
    print "</tr></table>";
    print "</div>\n";

    $item = "hdt_data";

    #Data
    # print STDERR "2665 $host_url, $server_url, $lpar_url, $item, $type_sam\n";

    print "<div id=\"tabs-$tab_num\">\n";
    $tab_num++;
    print "<table border=\"0\">\n";
    print "<tr>";
    print_item( $host_url, $server_url, $lpar_url, $item, "d", $type_sam, $entitle, $detail_yes, "norefr", "star", 1, "legend" );
    print_item( $host_url, $server_url, $lpar_url, $item, "w", $type_sam, $entitle, $detail_yes, "norefr", "star", 1, "legend" );
    print "</tr>\n<tr>\n";
    print_item( $host_url, $server_url, $lpar_url, $item, "m", $type_sam,      $entitle, $detail_yes, "norefr", "star", 1, "legend" );
    print_item( $host_url, $server_url, $lpar_url, $item, "y", $type_sam_year, $entitle, $detail_yes, "norefr", "star", 1, "legend" );
    print "</tr></table>";
    print "</div>\n";

    $item = "hdt_io";

    #IOPS
    # print STDERR "2665 $host_url, $server_url, $lpar_url, $item, $type_sam\n";

    print "<div id=\"tabs-$tab_num\">\n";
    $tab_num++;
    print "<table border=\"0\">\n";
    print "<tr>";
    print_item( $host_url, $server_url, $lpar_url, $item, "d", $type_sam, $entitle, $detail_yes, "norefr", "star", 1, "legend" );
    print_item( $host_url, $server_url, $lpar_url, $item, "w", $type_sam, $entitle, $detail_yes, "norefr", "star", 1, "legend" );
    print "</tr>\n<tr>\n";
    print_item( $host_url, $server_url, $lpar_url, $item, "m", $type_sam,      $entitle, $detail_yes, "norefr", "star", 1, "legend" );
    print_item( $host_url, $server_url, $lpar_url, $item, "y", $type_sam_year, $entitle, $detail_yes, "norefr", "star", 1, "legend" );
    print "</tr></table>";
    print "</div>\n";

    $item = "hdt_latency";

    #Storage Latency C: D: etc
    # print STDERR "13668 $host_url, $server_url, $lpar_url, $item, $type_sam\n";

    print "<div id=\"tabs-$tab_num\">\n";
    $tab_num++;
    print "<table border=\"0\">\n";
    print "<tr>";
    print_item( $host_url, $server_url, $lpar_url, $item, "d", $type_sam, $entitle, $detail_yes, "norefr", "star", 1, "nolegend" );
    print_item( $host_url, $server_url, $lpar_url, $item, "w", $type_sam, $entitle, $detail_yes, "norefr", "star", 1, "nolegend" );
    print "</tr>\n<tr>\n";
    print_item( $host_url, $server_url, $lpar_url, $item, "m", $type_sam,      $entitle, $detail_yes, "norefr", "star", 1, "nolegend" );
    print_item( $host_url, $server_url, $lpar_url, $item, "y", $type_sam_year, $entitle, $detail_yes, "norefr", "star", 1, "nolegend" );
    print "</tr></table>";
    print "</div>\n";

  }

  if ( $tab_num_orig < 2 ) {
    print "</div><br>\n";
  }
  return 1;
}

sub print_hyperv_pool_tabs {
  my ( $host_url, $server_url, $lpar_url, $item, $type_sam, $tab_num ) = @_;
  my $server = urldecode($server_url);
  my $host   = urldecode($host_url);

  my $cpu_pool    = "CPU POOL";
  my $lpar_vm_agg = "LPARs aggregated";
  $lpar_vm_agg = "VMs aggregated";
  $cpu_pool    = "CPU";

  if ( $tab_num < 2 ) {
    print "<CENTER>";
    print "<div  id=\"tabs\">\n";
    print "<ul>\n";
  }
  my $tab_num_orig = $tab_num;

  print "  <li class=\"$tab_type\"><a href=\"#tabs-$tab_num\">$cpu_pool</a></li>\n";
  $tab_num++;

  # print STDERR "4954 path $wrkdir/$server/$host/VM_hosting.vmh\n";
  if ( -f "$wrkdir/$server/$host/CPUqueue.rrm" ) {
    print "  <li class=\"$tab_type\"><a href=\"#tabs-$tab_num\">CPU queue</a></li>\n";
    $tab_num++;
  }
  if ( -f "$wrkdir/$server/$host/CPUqueue.rrm" ) {
    print "  <li class=\"$tab_type\"><a href=\"#tabs-$tab_num\">Process</a></li>\n";
    $tab_num++;
  }
  if ( job_dir_lives("$wrkdir/$server/$host") ) {
    print "  <li class=\"$tab_type\"><a href=\"#tabs-$tab_num\">JOB</a></li>\n";
    $tab_num++;
  }

  # print STDERR "4954 path $wrkdir/$server/$host/VM_hosting.vmh\n";
  if ( -f "$wrkdir/$server/$host/VM_hosting.vmh" ) {
    print "  <li class=\"$tab_type\"><a href=\"#tabs-$tab_num\">$lpar_vm_agg</a></li>\n";
    $tab_num++;
  }
  print "  <li class=\"$tab_type\"><a href=\"#tabs-$tab_num\">Configuration</a></li>\n";
  $tab_num++;

  # here come all other hyperv tabs mem + net + data + io
  print "  <li class=\"$tab_type\"><a href=\"#tabs-$tab_num\">Memory</a></li>\n";
  $tab_num++;
  print "  <li class=\"$tab_type\"><a href=\"#tabs-$tab_num\">Paging</a></li>\n";
  $tab_num++;

  # print STDERR "13673 $wrkdir/$server/$host/page_file_name.txt\n";
  if ( -f "$wrkdir/$server/$host/page_file_name.txt" ) {
    print "  <li class=\"$tab_type\"><a href=\"#tabs-$tab_num\">Paging 2</a></li>\n";
    $tab_num++;
  }
  print "  <li class=\"$tab_type\"><a href=\"#tabs-$tab_num\">LAN</a></li>\n";
  $tab_num++;
  print "  <li class=\"$tab_type\"><a href=\"#tabs-$tab_num\">Data</a></li>\n";
  $tab_num++;
  print "  <li class=\"$tab_type\"><a href=\"#tabs-$tab_num\">IOPS</a></li>\n";
  $tab_num++;
  print "  <li class=\"$tab_type\"><a href=\"#tabs-$tab_num\">Latency</a></li>\n";

  if ( $tab_num_orig < 2 ) {
    print "</ul>\n";
  }
}

sub job_dir_lives {
  my $path = shift;

  # returns 1 if cputop0.mmc file in JOB dir is not older 7 days
  return 0 if ( !-d "$path/JOB" );
  return 0 if ( !-f "$path/JOB/cputop0.mmc" );
  return 0 if ( -M "$path/JOB/cputop0.mmc" > 7 );
  return 1;
}

sub print_s2dvol_tabs {
  my ( $host_url, $server_url, $lpar_url, $item, $type_sam, $tab_num ) = @_;
  my $server = urldecode($server_url);
  my $host   = urldecode($host_url);

  if ( $tab_num < 2 ) {
    print "<CENTER>";
    print "<div  id=\"tabs\">\n";
    print "<ul>\n";
  }
  my $tab_num_orig = $tab_num;

  print "  <li class=\"$tab_type\"><a href=\"#tabs-$tab_num\">IOPS</a></li>\n";
  $tab_num++;
  print "  <li class=\"$tab_type\"><a href=\"#tabs-$tab_num\">Data</a></li>\n";
  $tab_num++;
  print "  <li class=\"$tab_type\"><a href=\"#tabs-$tab_num\">Latency</a></li>\n";
  $tab_num++;
  print "  <li class=\"$tab_type\"><a href=\"#tabs-$tab_num\">Capacity</a></li>\n";

  if ( $tab_num_orig < 2 ) {
    print "</ul>\n";
  }
}

sub print_s2dvol_html {
  my ( $host_url, $server_url, $lpar_url, $item, $type_sam, $tab_num ) = @_;
  my $tab_num_orig = $tab_num;
  my $server       = urldecode($server_url);
  my $host         = urldecode($host_url);

  # io
  $item = "s2dvol_io";
  print "<CENTER>";
  print "<div id=\"tabs-$tab_num\">\n";
  $tab_num++;
  print "<table border=\"0\">\n";
  print "<tr>";
  print_item( $host_url, $server_url, $lpar_url, $item, "d", $type_sam, $entitle, $detail_yes, "norefr", "star", 1, "legend" );
  print_item( $host_url, $server_url, $lpar_url, $item, "w", $type_sam, $entitle, $detail_yes, "norefr", "star", 1, "legend" );
  print "</tr>\n<tr>\n";
  print_item( $host_url, $server_url, $lpar_url, $item, "m", $type_sam, $entitle, $detail_yes, "norefr", "star", 1, "legend" );
  print_item( $host_url, $server_url, $lpar_url, $item, "y", $type_sam, $entitle, $detail_yes, "norefr", "star", 1, "legend" );
  print "</tr>";
  print "</table>";
  print "</div>";

  # data
  $item = "s2dvol_data";
  print "<CENTER>";
  print "<div id=\"tabs-$tab_num\">\n";
  $tab_num++;
  print "<table border=\"0\">\n";
  print "<tr>";
  print_item( $host_url, $server_url, $lpar_url, $item, "d", $type_sam, $entitle, $detail_yes, "norefr", "star", 1, "legend" );
  print_item( $host_url, $server_url, $lpar_url, $item, "w", $type_sam, $entitle, $detail_yes, "norefr", "star", 1, "legend" );
  print "</tr>\n<tr>\n";
  print_item( $host_url, $server_url, $lpar_url, $item, "m", $type_sam, $entitle, $detail_yes, "norefr", "star", 1, "legend" );
  print_item( $host_url, $server_url, $lpar_url, $item, "y", $type_sam, $entitle, $detail_yes, "norefr", "star", 1, "legend" );
  print "</tr>";
  print "</table>";
  print "</div>";

  # latency
  $item = "s2dvol_latency";
  print "<CENTER>";
  print "<div id=\"tabs-$tab_num\">\n";
  $tab_num++;
  print "<table border=\"0\">\n";
  print "<tr>";
  print_item( $host_url, $server_url, $lpar_url, $item, "d", $type_sam, $entitle, $detail_yes, "norefr", "star", 1, "legend" );
  print_item( $host_url, $server_url, $lpar_url, $item, "w", $type_sam, $entitle, $detail_yes, "norefr", "star", 1, "legend" );
  print "</tr>\n<tr>\n";
  print_item( $host_url, $server_url, $lpar_url, $item, "m", $type_sam, $entitle, $detail_yes, "norefr", "star", 1, "legend" );
  print_item( $host_url, $server_url, $lpar_url, $item, "y", $type_sam, $entitle, $detail_yes, "norefr", "star", 1, "legend" );
  print "</tr>";
  print "</table>";
  print "</div>";

  # capacity
  $item = "s2dvol_capacity";
  print "<CENTER>";
  print "<div id=\"tabs-$tab_num\">\n";
  $tab_num++;
  print "<table border=\"0\">\n";
  print "<tr>";
  print_item( $host_url, $server_url, $lpar_url, $item, "d", $type_sam, $entitle, $detail_yes, "norefr", "star", 1, "legend" );
  print_item( $host_url, $server_url, $lpar_url, $item, "w", $type_sam, $entitle, $detail_yes, "norefr", "star", 1, "legend" );
  print "</tr>\n<tr>\n";
  print_item( $host_url, $server_url, $lpar_url, $item, "m", $type_sam, $entitle, $detail_yes, "norefr", "star", 1, "legend" );
  print_item( $host_url, $server_url, $lpar_url, $item, "y", $type_sam, $entitle, $detail_yes, "norefr", "star", 1, "legend" );
  print "</tr>";
  print "</table>";
  print "</div>";

  if ( $tab_num_orig < 2 ) {
    print "</div><br>\n";
  }
  return 1;

}

sub print_phys_disk_tabs {
  my ( $host_url, $server_url, $lpar_url, $item, $type_sam, $tab_num ) = @_;
  my $server = urldecode($server_url);
  my $host   = urldecode($host_url);

  if ( $tab_num < 2 ) {
    print "<CENTER>";
    print "<div  id=\"tabs\">\n";
    print "<ul>\n";
  }
  my $tab_num_orig = $tab_num;

  print "  <li class=\"$tab_type\"><a href=\"#tabs-$tab_num\">IOPS</a></li>\n";
  $tab_num++;
  print "  <li class=\"$tab_type\"><a href=\"#tabs-$tab_num\">Data</a></li>\n";
  $tab_num++;
  print "  <li class=\"$tab_type\"><a href=\"#tabs-$tab_num\">Latency</a></li>\n";

  if ( $tab_num_orig < 2 ) {
    print "</ul>\n";
  }
}

sub print_phys_disk_html {
  my ( $host_url, $server_url, $lpar_url, $item, $type_sam, $tab_num ) = @_;
  my $tab_num_orig = $tab_num;
  my $server       = urldecode($server_url);
  my $host         = urldecode($host_url);

  # io
  $item = "phys_disk_io";
  print "<CENTER>";
  print "<div id=\"tabs-$tab_num\">\n";
  $tab_num++;
  print "<table border=\"0\">\n";
  print "<tr>";
  print_item( $host_url, $server_url, $lpar_url, $item, "d", $type_sam, $entitle, $detail_yes, "norefr", "star", 1, "legend" );
  print_item( $host_url, $server_url, $lpar_url, $item, "w", $type_sam, $entitle, $detail_yes, "norefr", "star", 1, "legend" );
  print "</tr>\n<tr>\n";
  print_item( $host_url, $server_url, $lpar_url, $item, "m", $type_sam, $entitle, $detail_yes, "norefr", "star", 1, "legend" );
  print_item( $host_url, $server_url, $lpar_url, $item, "y", $type_sam, $entitle, $detail_yes, "norefr", "star", 1, "legend" );
  print "</tr>";
  print "</table>";
  print "</div>";

  # data
  $item = "phys_disk_data";
  print "<CENTER>";
  print "<div id=\"tabs-$tab_num\">\n";
  $tab_num++;
  print "<table border=\"0\">\n";
  print "<tr>";
  print_item( $host_url, $server_url, $lpar_url, $item, "d", $type_sam, $entitle, $detail_yes, "norefr", "star", 1, "legend" );
  print_item( $host_url, $server_url, $lpar_url, $item, "w", $type_sam, $entitle, $detail_yes, "norefr", "star", 1, "legend" );
  print "</tr>\n<tr>\n";
  print_item( $host_url, $server_url, $lpar_url, $item, "m", $type_sam, $entitle, $detail_yes, "norefr", "star", 1, "legend" );
  print_item( $host_url, $server_url, $lpar_url, $item, "y", $type_sam, $entitle, $detail_yes, "norefr", "star", 1, "legend" );
  print "</tr>";
  print "</table>";
  print "</div>";

  # latency
  $item = "phys_disk_latency";
  print "<CENTER>";
  print "<div id=\"tabs-$tab_num\">\n";
  $tab_num++;
  print "<table border=\"0\">\n";
  print "<tr>";
  print_item( $host_url, $server_url, $lpar_url, $item, "d", $type_sam, $entitle, $detail_yes, "norefr", "star", 1, "legend" );
  print_item( $host_url, $server_url, $lpar_url, $item, "w", $type_sam, $entitle, $detail_yes, "norefr", "star", 1, "legend" );
  print "</tr>\n<tr>\n";
  print_item( $host_url, $server_url, $lpar_url, $item, "m", $type_sam, $entitle, $detail_yes, "norefr", "star", 1, "legend" );
  print_item( $host_url, $server_url, $lpar_url, $item, "y", $type_sam, $entitle, $detail_yes, "norefr", "star", 1, "legend" );
  print "</tr>";
  print "</table>";
  print "</div>";

  if ( $tab_num_orig < 2 ) {
    print "</div><br>\n";
  }
  return 1;

}

sub print_shpool {
  my ( $host_url, $server_url, $lpar_url, $item, $type_sam ) = @_;

  # `echo "$host_url,$server_url,$lpar_url,$item,$type_sam" >> /tmp/xx333`;

  print "<CENTER>";
  print "<div  id=\"tabs\">\n";
  print "<ul>\n";
  print "  <li class=\"tabhmc\"><a href=\"#tabs-1\">CPU</a></li>\n";

  if ( !$vmware ) {    # do not use on our DEMO site
    print "  <li class=\"tabhmc\"><a href=\"#tabs-2\">CPU max</a></li>\n";
  }

  print "  <li class=\"tabhmc\"><a href=\"#tabs-3\">LPARs aggregated</a></li>\n";
  print "  <li class=\"tabhmc\"><a href=\"#tabs-4\">Configuration</a></li>\n";
  print "</ul>\n";

  # shared pool
  my $pool_id = $lpar_url;
  $pool_id =~ s/SharedPool//;
  my $refresh_name = "CPU%20pool%20$pool_id";
  my $refresh      = "<div class=\"refresh fas fa-sync-alt\"><A HREF=\"/lpar2rrd-cgi/lpar2rrd-realt.sh?source=$refresh_name&hmc=$host_url&mname=$server_url&new_gui=$gui\"></A></div>\n";
  print "<div id=\"tabs-1\">\n";
  print "<table border=\"0\">\n";
  print "<tr>";
  print_item( $host_url, $server_url, $lpar_url, $item, "d", $type_sam, $entitle, $detail_yes, $refresh, "star", 1, "legend" );
  print_item( $host_url, $server_url, $lpar_url, $item, "w", $type_sam, $entitle, $detail_yes, "norefr", "star", 1, "legend" );
  print "</tr>\n<tr>\n";
  print_item( $host_url, $server_url, $lpar_url, $item, "m", $type_sam,      $entitle, $detail_yes, "norefr", "star", 1, "legend" );
  print_item( $host_url, $server_url, $lpar_url, $item, "y", $type_sam_year, $entitle, $detail_yes, "norefr", "star", 1, "legend" );
  print "</tr>";
  print "<tr>";
  $item = "trendshpool";

  # next line should work with $detail_yes, but is bad when adding html_heading
  print_item( $host_url, $server_url, $lpar_url, $item, "y", $type_sam_year, $entitle, $detail_yes, "norefr", "nostar", 2, "legend" );
  print "</tr></table>";
  print "</div>";

  # shared pool max
  if ( !$vmware ) {    # do not use on our DEMO site
    $item = "shpool-max";
    print "<div id=\"tabs-2\">\n";
    print "<div id=\"hiw\"><a href=\"http://www.lpar2rrd.com/max_vrs_average.html\" target=\"_blank\" class=\"nowrap\"><img src=\"css/images/help-browser.gif\" alt=\"Maximum versus Average\" title=\"Maximum versus Average\"></img></a></div>";
    print "<table border=\"0\">\n";
    print "<tr>";
    print_item( $host_url, $server_url, $lpar_url, $item, "d", $type_sam, $entitle, $detail_yes, "norefr", "star", 1, "legend" );
    print_item( $host_url, $server_url, $lpar_url, $item, "w", $type_sam, $entitle, $detail_yes, "norefr", "star", 1, "legend" );
    print "</tr>\n<tr>\n";
    print_item( $host_url, $server_url, $lpar_url, $item, "m", $type_sam,      $entitle, $detail_yes, "norefr", "star", 1, "legend" );
    print_item( $host_url, $server_url, $lpar_url, $item, "y", $type_sam_year, $entitle, $detail_yes, "norefr", "star", 1, "legend" );
    print "</tr>";
    print "<tr>";
    $item = "trendshpool-max";
    print_item( $host_url, $server_url, $lpar_url, $item, "y", $type_sam_year, $entitle, $detail_yes, "norefr", "nostar", 2, "legend" );
    print "</tr></table>";
    print "</div>";
  }

  # shared pool - aggregated
  $item = "poolagg";
  print "<div id=\"tabs-3\">\n";

  print "<table border=\"0\">\n";
  print "<tr><td align=\"left\" colspan=\"2\">";
  print "<font size=-1>Note that aggregated graphs here are only informative. <br>\n";
  print "LPAR list in the pool is actual and if it is different than it was in the past then historical graphs might not be accurate. <br>They might not contain proper LPAR list<br><br>\n";
  print "</td></tr>";
  print "<tr>\n";
  print_item( $host_url, $server_url, $lpar_url, $item, "d", $type_sam, $entitle, $detail_yes, "norefr", "star", 1, "nolegend" );
  print_item( $host_url, $server_url, $lpar_url, $item, "w", $type_sam, $entitle, $detail_yes, "norefr", "star", 1, "nolegend" );
  print "</tr>\n";
  print_item( $host_url, $server_url, $lpar_url, $item, "m", $type_sam,      $entitle, $detail_yes, "norefr", "star", 1, "nolegend" );
  print_item( $host_url, $server_url, $lpar_url, $item, "y", $type_sam_year, $entitle, $detail_yes, "norefr", "star", 1, "nolegend" );
  print "</tr></table>";
  print "</div>";

  # Configuration
  if ( $rest_api == 1 ) {
    my $file_html_cpu = "$wrkdir/$server/$host/cpu_pool_$pool_id.html";
    $file_html_cpu =~ s/%3A/:/g;    # host can have port vmware:444"
    my $cpu_html;

    # print STDERR "\$file_html_cpu $file_html_cpu\n";
    if ( -f "$file_html_cpu" ) {
      open( FH, "< $file_html_cpu" );
      $cpu_html = do { local $/; <FH> };
      close(FH);
      print "<div id=\"tabs-4\">\n";
      print "<table border=\"0\">\n";
      print "<tr><td>\n";
      print "$cpu_html";
      print "</td></tr>\n";
      print "<tr><td>\n";
    }
  }
  else {
    my $file_html_cpu = "$wrkdir/$server/$host/cpu.html";
    if ( -f "$file_html_cpu" ) {
      open( FH, "< $file_html_cpu" );
      my @cpu_html = <FH>;
      close(FH);

      my $lpar_pool_alias = "";
      my $pool_id         = $lpar_url;
      $pool_id =~ s/SharedPool//g;
      open( FR, "<$wrkdir/$server/$host/cpu-pools-mapping.txt" ) || error( "Can't open $wrkdir/$server/$host/cpu-pools-mapping.txt : $!" . __FILE__ . ":" . __LINE__ ) && return 0;
      foreach my $linep (<FR>) {
        chomp($linep);
        ( my $id, my $pool_name ) = split( /,/, $linep );
        if ( $id == $pool_id ) {
          $lpar_pool_alias = "$pool_name";
          last;
        }
      }
      close(FR);

      print "<div id=\"tabs-4\">\n";
      print "<table border=\"0\">\n";
      print "<tr><td>";
      my @cpu_html_choice = grep /<TABLE|TABLE>|thead>|>$lpar_pool_alias</, @cpu_html;
      print "@cpu_html_choice";
      print "</td></tr>";
      print "<tr><td>";
      print "The table is updated once a day<br>";

      #print "<A HREF=\"$host_url/$server_url/config.html#CPU_pools\">Detailed configuration</A>";
      print "</td></tr>";
      print "</table>";
      print "</div>";
    }
  }

  print "</div><br>\n";
  return 1;
}

sub print_memory {
  my ( $host_url, $server_url, $lpar_url, $item, $entitle ) = @_;

  # print STDERR "2255 detail-cgi.pl memalloc $host_url,$server_url,$lpar_url,$item,$type_sam \$vmware $vmware \$hyperv $hyperv \n" ;
  # test if AMS
  opendir( DIR, "$wrkdir/$server/$host" ) || error( " directory does not exists : $wrkdir/$server/$host" . __FILE__ . ":" . __LINE__ ) && return 0;
  my @files_not_sorted = grep( /.*\.rm.$/, readdir(DIR) );
  closedir(DIR);
  my $ams = @files_not_sorted;

  print "<CENTER>";
  print "<div  id=\"tabs\">\n";
  print "<ul>\n";
  print "  <li class=\"$tab_type\"><a href=\"#tabs-1\">Allocation</a></li>\n";
  if ( !$hyperv && !$hitachi ) {
    print "  <li class=\"$tab_type\"><a href=\"#tabs-2\">Aggregated</a></li>\n";
  }
  if ($hyperv) {
    print "  <li class=\"$tab_type\"><a href=\"#tabs-3\">Paging</a></li>\n";
  }
  if ( !$vmware && !$hyperv && !$hitachi ) {
    if ( $ams == 0 ) {
      print "  <li class=\"$tab_type\"><a href=\"#tabs-3\">Configuration</a></li>\n";
    }
    else {
      print "  <li class=\"$tab_type\"><a href=\"#tabs-3\">AMS</a></li>\n";
      print "  <li class=\"$tab_type\"><a href=\"#tabs-4\">Configuration</a></li>\n";
    }
  }
  print "</ul>\n";

  # Memory allocation
  print "<div id=\"tabs-1\">\n";
  print "<table border=\"0\">\n";
  print "<tr>";

  $item = "memalloc";
  print_item( $host_url, $server_url, $lpar_url, $item, "d", $type_sam, $entitle, $detail_yes, "norefr", "star", 1, "legend" );
  print_item( $host_url, $server_url, $lpar_url, $item, "w", $type_sam, $entitle, $detail_yes, "norefr", "star", 1, "legend" );
  print "</tr>\n<tr>\n";
  print_item( $host_url, $server_url, $lpar_url, $item, "m", $type_sam,      $entitle, $detail_yes, "norefr", "star", 1, "legend" );
  print_item( $host_url, $server_url, $lpar_url, $item, "y", $type_sam_year, $entitle, $detail_yes, "norefr", "star", 1, "legend" );
  print "</tr>";
  print "<tr>";
  $item = "trendmemalloc";

  if ( !$vmware && !$hyperv ) {
    print_item( $host_url, $server_url, $lpar_url, $item, "y", $type_sam_year, $entitle, $detail_yes, "norefr", "nostar", 2, "legend" );
  }
  print "</tr></table>";
  print "</div>\n";

  if ( !$hyperv && !$hitachi ) {

    # Memory aggregation
    print "<div id=\"tabs-2\">\n";
    print "<table border=\"0\">\n";
    print "<tr>";

    $item = "memaggreg";
    print_item( $host_url, $server_url, $lpar_url, $item, "d", $type_sam, $entitle, $detail_yes, "norefr", "star", 1, "nolegend" );
    print_item( $host_url, $server_url, $lpar_url, $item, "w", $type_sam, $entitle, $detail_yes, "norefr", "star", 1, "nolegend" );
    print "</tr>\n<tr>\n";
    print_item( $host_url, $server_url, $lpar_url, $item, "m", $type_sam,      $entitle, $detail_yes, "norefr", "star", 1, "nolegend" );
    print_item( $host_url, $server_url, $lpar_url, $item, "y", $type_sam_year, $entitle, $detail_yes, "norefr", "star", 1, "nolegend" );
    print "</tr></table>";
    print "</div>\n";
  }

  if ($hyperv) {

    # paging
    print "<div id=\"tabs-3\">\n";
    print "<table border=\"0\">\n";
    print "<tr>";
    $item = "hyppg1";
    print_item( $host_url, $server_url, $lpar_url, $item, "d", $type_sam, $entitle, $detail_yes, "norefr", "star", 1, "legend" );
    print_item( $host_url, $server_url, $lpar_url, $item, "w", $type_sam, $entitle, $detail_yes, "norefr", "star", 1, "legend" );
    print "</tr>\n<tr>\n";
    print_item( $host_url, $server_url, $lpar_url, $item, "m", $type_sam,      $entitle, $detail_yes, "norefr", "star", 1, "legend" );
    print_item( $host_url, $server_url, $lpar_url, $item, "y", $type_sam_year, $entitle, $detail_yes, "norefr", "star", 1, "legend" );
    print "</tr></table>";
    print "</div>\n";
  }

  my $tab_count = 3;
  if ( $ams ne 0 ) {
    $tab_count = 4;

    # Memory AMS
    print "<div id=\"tabs-3\">\n";
    print "<table border=\"0\">\n";
    print "<tr>";
    $item = "memams";
    print_item( $host_url, $server_url, $lpar_url, $item, "d", $type_sam, $entitle, $detail_yes, "norefr", "star", 1, "nolegend" );
    print_item( $host_url, $server_url, $lpar_url, $item, "w", $type_sam, $entitle, $detail_yes, "norefr", "star", 1, "nolegend" );
    print "</tr>\n<tr>\n";
    print_item( $host_url, $server_url, $lpar_url, $item, "m", $type_sam,      $entitle, $detail_yes, "norefr", "star", 1, "nolegend" );
    print_item( $host_url, $server_url, $lpar_url, $item, "y", $type_sam_year, $entitle, $detail_yes, "norefr", "star", 1, "nolegend" );
    print "</tr></table>";
    print "</div>\n";
  }

  # Memory configuration
  my $file_html_mem = "$wrkdir/$server/$host/mem.html";
  my $mem_html;
  if ( -f "$file_html_mem" ) {
    my $last_upd_time = ( stat($file_html_mem) )[9];
    open( FH, "< $file_html_mem" );
    $mem_html = do { local $/; <FH> };
    close(FH);
    print "<div id=\"tabs-$tab_count\">\n";
    print "<table border=\"0\">\n";
    print "<tr><td align=\"center\">\n";
    print "$mem_html";
    print "</td></tr>";
    print "<tr><td>\n";
    print "<center>The table is updated once a day<br>" . "Last update: " . localtime($last_upd_time) . "</center>";

    #print "<A HREF=\"$host_url/$server_url/config.html#Memory\">Detailed configuration</A>";
    print "</td></tr>";
    print "</table>\n";
    print "</div><br>\n";
  }

  print "</div><br>\n";
  return 1;
}

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

sub print_hmctotals {
  my ( $host_url, $server, $lpar_url, $item, $entitle ) = @_;

  my $lpar_tab_name = "LPAR";
  if ($vmware) {
    $lpar_tab_name = "CPU VMs";
  }
  my $hmc_pref = "--HMC--";

  print "<CENTER>";
  print "<div  id=\"tabs\">\n";
  print "<ul>\n";
  if ( !$vmware ) {
    print "  <li class=\"$tab_type\"><a href=\"#tabs-7\">Server Total</a></li>\n";
    print "  <li class=\"$tab_type\"><a href=\"#tabs-1\">Server Pool</a></li>\n";
    print "  <li class=\"tabhmc\"><a href=\"#tabs-3\">Server Count</a></li>\n";
  }
  else {
    print "  <li class=\"$tab_type\"><a href=\"#tabs-1\">Server</a></li>\n";
  }
  print "  <li class=\"$tab_type\"><a href=\"#tabs-2\">$lpar_tab_name</a></li>\n";

  # find if there are more clusters
  my $server_dec   = urldecode($server_url);
  my $file_cluster = "$wrkdir/$server_dec/*/cluster.rrc";

  #$file_cluster =~ s/ /\\ /g;
  my $no_name       = "";
  my @cluster_arr   = <$file_cluster$no_name>;
  my $cluster_count = scalar @cluster_arr;

  # print STDERR "\$cluster_count $cluster_count \@cluster_arr @cluster_arr \$host $host \$server $server \$lpar_url $lpar_url\n";
  if ( $cluster_count > 1 ) {
    print "  <li class=\"$tab_type\"><a href=\"#tabs-3\">CPU CLUSTERS</a></li>\n";
  }
  if ($vmware) {
    print "  <li class=\"$tab_type\"><a href=\"#tabs-31\">Power</a></li>\n";
    print "  <li class=\"$tab_type\"><a href=\"#tabs-4\">Configuration</a></li>\n";
  }

  my $host_decoded = urldecode("$host_url");
  if ( -f "$wrkdir/$hmc_pref$host_decoded/cpu.mmx" ) {
    print "  <li class=\"tabhmc\"><a href=\"#tabs-4\">CPU</a></li>\n";
  }
  if ( -f "$wrkdir/$hmc_pref$host_decoded/mem.mmx" ) {
    print "  <li class=\"tabhmc\"><a href=\"#tabs-5\">Memory</a></li>\n";
  }
  if ( -f "$wrkdir/$hmc_pref$host_decoded/pgs.mmx" ) {
    print "  <li class=\"tabhmc\"><a href=\"#tabs-6\">Paging</a></li>\n";
  }
  print "</ul>\n";

  #hmctotals SERVER
  print "<div id=\"tabs-1\">\n";
  print "<table border=\"0\">\n";
  print "<tr>";

  $item = "multihmc";
  print_item( $host_url, $server_url, $lpar_url, $item, "d", $type_sam, $entitle, $detail_yes, "norefr", "nostar", 1, "nolegend" );
  print_item( $host_url, $server_url, $lpar_url, $item, "w", $type_sam, $entitle, $detail_yes, "norefr", "nostar", 1, "nolegend" );
  print "</tr>\n<tr>\n";
  print_item( $host_url, $server_url, $lpar_url, $item, "m", $type_sam,      $entitle, $detail_yes, "norefr", "nostar", 1, "nolegend" );
  print_item( $host_url, $server_url, $lpar_url, $item, "y", $type_sam_year, $entitle, $detail_yes, "norefr", "nostar", 1, "nolegend" );
  print "</tr>";
  if ( !$vmware ) {
    print "<tr><td colspan=\"2\" align=\"left\">";
    print "Graphs do not take into consideration CPU dedicated partitions which have pre-allocated CPUs.<br>";
    print "</td></tr>";
  }
  print "</table>";
  print "</div>\n";

  #hmctotals LPAR
  print "<div id=\"tabs-2\">\n";
  if ($vmware) {
    print "$question_mark";
  }
  print "<table border=\"0\">\n";
  print "<tr>";

  $item = "multihmclpar";
  print_item( $host_url, $server_url, $lpar_url, $item, "d", $type_sam, $entitle, $detail_yes, "norefr", "nostar", 1, "nolegend" );
  print_item( $host_url, $server_url, $lpar_url, $item, "w", $type_sam, $entitle, $detail_yes, "norefr", "nostar", 1, "nolegend" );
  print "</tr>\n<tr>\n";
  print_item( $host_url, $server_url, $lpar_url, $item, "m", $type_sam,      $entitle, $detail_yes, "norefr", "nostar", 1, "nolegend" );
  print_item( $host_url, $server_url, $lpar_url, $item, "y", $type_sam_year, $entitle, $detail_yes, "norefr", "nostar", 1, "nolegend" );
  print "</tr>";
  if ( !$vmware ) {
    print "<tr><td colspan=\"2\" align=\"left\">";
    print "Note that CPU utilization of CPU dedicated partitions is included in the graphs so result can be different from the server graphs in the first tab.<BR>";
    print "</td></tr>";
  }
  print "</table>";
  print "</div>\n";

  # for more vmware clusters
  if ( $cluster_count > 1 ) {
    print "<div id=\"tabs-3\">\n";
    print "<table border=\"0\">\n";
    print "<tr>";

    $item = "multicluster";
    print_item( $host_url, $server_url, "$lpar_url", "$item", "d", $type_sam, $entitle, $detail_yes, "norefr", "nostar", 1, "nolegend" );
    print_item( $host_url, $server_url, $lpar_url,   $item,   "w", $type_sam, $entitle, $detail_yes, "norefr", "nostar", 1, "nolegend" );
    print "</tr>\n<tr>\n";
    print_item( $host_url, $server_url, $lpar_url, $item, "m", $type_sam,      $entitle, $detail_yes, "norefr", "nostar", 1, "nolegend" );
    print_item( $host_url, $server_url, $lpar_url, $item, "y", $type_sam_year, $entitle, $detail_yes, "norefr", "nostar", 1, "nolegend" );
    print "</tr>";
    print "<tr><td colspan=\"2\" align=\"left\">";
    print "</td></tr></table>";

    print "</div>\n";
  }

  if ($vmware) {

    print "<div id=\"tabs-31\">\n";
    print "<table border=\"0\">\n";
    print "<tr>";

    #$item = "clustpow";
    $item = "vcenter_power";    # since 7.5
    print_item( $host_url, $server_url, $lpar_url, $item, "d", $type_sam, $entitle, $detail_yes, "norefr", "nostar", 1, "nolegend" );
    print_item( $host_url, $server_url, $lpar_url, $item, "w", $type_sam, $entitle, $detail_yes, "norefr", "nostar", 1, "nolegend" );
    print "</tr>\n<tr>\n";
    print_item( $host_url, $server_url, $lpar_url, $item, "m", $type_sam,      $entitle, $detail_yes, "norefr", "nostar", 1, "nolegend" );
    print_item( $host_url, $server_url, $lpar_url, $item, "y", $type_sam_year, $entitle, $detail_yes, "norefr", "nostar", 1, "nolegend" );
    print "</tr>";
    print "<tr><td colspan=\"2\" align=\"left\">";
    print "</td></tr></table>";

    print "</div>\n";
    print "<tr>\n";

    # here ESXi Configuration
    print "<div id=\"tabs-4\">\n";
    print "<table border=\"0\">\n";
    print "<tr><td>";

    # print STDERR "12475 $host_url, $server_url, $server, $lpar_url, $item, $wrkdir\n";
    print_html_file( urldecode("$wrkdir/$server_url/vcenter_config.html") );
    print_html_file( urldecode("$wrkdir/$server_url/esxis_config.html") );
    print "</td></tr></table>";
    print "</div>\n";
  }

  #hmctotals COUNT
  if ( !$vmware ) {
    print "<div id=\"tabs-3\">\n";
    print "<table border=\"0\">\n";
    print "<tr>";

    $item = "hmccount";
    print_item( $host_url, $server_url, $lpar_url, $item, "m", $type_sam,      $entitle, $detail_yes, "norefr", "nostar", 1, "legend" );
    print_item( $host_url, $server_url, $lpar_url, $item, "y", $type_sam_year, $entitle, $detail_yes, "norefr", "nostar", 1, "legend" );
    print "</tr></table>";

    print "</div>\n";
  }

  if ( -f "$wrkdir/$hmc_pref$host_decoded/cpu.mmx" ) {
    print "<div id=\"tabs-4\">\n";
    print "<table border=\"0\">\n";
    print "<tr>";

    $item = "hmccpu";
    print_item( $host_url, $server_url, $lpar_url, $item, "d", $type_sam, $entitle, $detail_yes, "norefr", "nostar", 1, "legend" );
    print_item( $host_url, $server_url, $lpar_url, $item, "w", $type_sam, $entitle, $detail_yes, "norefr", "nostar", 1, "legend" );
    print "</tr>\n<tr>\n";
    print_item( $host_url, $server_url, $lpar_url, $item, "m", $type_sam,      $entitle, $detail_yes, "norefr", "nostar", 1, "legend" );
    print_item( $host_url, $server_url, $lpar_url, $item, "y", $type_sam_year, $entitle, $detail_yes, "norefr", "nostar", 1, "legend" );
    print "</tr></table>";

    print "</div>\n";
  }
  if ( -f "$wrkdir/$hmc_pref$host_decoded/mem.mmx" ) {
    print "<div id=\"tabs-5\">\n";
    print "<table border=\"0\">\n";
    print "<tr>";

    $item = "hmcmem";
    print_item( $host_url, $server_url, $lpar_url, $item, "d", $type_sam, $entitle, $detail_yes, "norefr", "nostar", 1, "legend" );
    print_item( $host_url, $server_url, $lpar_url, $item, "w", $type_sam, $entitle, $detail_yes, "norefr", "nostar", 1, "legend" );
    print "</tr>\n<tr>\n";
    print_item( $host_url, $server_url, $lpar_url, $item, "m", $type_sam,      $entitle, $detail_yes, "norefr", "nostar", 1, "legend" );
    print_item( $host_url, $server_url, $lpar_url, $item, "y", $type_sam_year, $entitle, $detail_yes, "norefr", "nostar", 1, "legend" );
    print "</tr></table>";

    print "</div>\n";
  }
  if ( -f "$wrkdir/$hmc_pref$host_decoded/pgs.mmx" ) {
    print "<div id=\"tabs-6\">\n";
    print "<table border=\"0\">\n";
    print "<tr>";

    $item = "hmcpgs";
    print_item( $host_url, $server_url, $lpar_url, $item, "d", $type_sam, $entitle, $detail_yes, "norefr", "nostar", 1, "legend" );
    print_item( $host_url, $server_url, $lpar_url, $item, "w", $type_sam, $entitle, $detail_yes, "norefr", "nostar", 1, "legend" );
    print "</tr>\n<tr>\n";
    print_item( $host_url, $server_url, $lpar_url, $item, "m", $type_sam,      $entitle, $detail_yes, "norefr", "nostar", 1, "legend" );
    print_item( $host_url, $server_url, $lpar_url, $item, "y", $type_sam_year, $entitle, $detail_yes, "norefr", "nostar", 1, "legend" );
    print "</tr></table>";

    print "</div>\n";
  }
  if ( !$vmware ) {
    print "<div id=\"tabs-7\">\n";
    print "<table border=\"0\">\n";
    print "<tr>";

    $item = "multihmc_tot";
    print_item( $host_url, $server_url, $lpar_url, $item, "d", $type_sam, $entitle, $detail_yes, "norefr", "nostar", 1, "nolegend" );
    print_item( $host_url, $server_url, $lpar_url, $item, "w", $type_sam, $entitle, $detail_yes, "norefr", "nostar", 1, "nolegend" );
    print "</tr>\n<tr>\n";
    print_item( $host_url, $server_url, $lpar_url, $item, "m", $type_sam,      $entitle, $detail_yes, "norefr", "nostar", 1, "nolegend" );
    print_item( $host_url, $server_url, $lpar_url, $item, "y", $type_sam_year, $entitle, $detail_yes, "norefr", "nostar", 1, "nolegend" );
    print "</tr>";
    print "<tr><td colspan=\"2\" align=\"left\">";
    print "</td></tr></table>";
    print "</div>\n";
  }

  print "</div><br>\n";

  return 1;
}

sub print_datastore {
  my ( $host_url, $server_url, $lpar_url, $item, $entitle ) = @_;

  # print STDERR "2385 detail-cgi.pl datastore $host_url,$server_url,$lpar_url,$item,$entitle,\n";

  my $full_ds_name = "$wrkdir/$server/$host/$lpar";
  if ( ( !-f "$full_ds_name.rrt" || ( -s "$full_ds_name.rrt" == 0 ) ) && ( !-f "$full_ds_name.rrs" || ( -s "$full_ds_name.rrs" == 0 ) ) ) {
    error( "datastore $wrkdir/$server/$host/$lpar has no data " . __FILE__ . ":" . __LINE__ );
    return 0;
  }

  # soliter ESXi has no data rw or avr
  my $data_exist = 0;
  if ( -f "$wrkdir/$server/$host/$lpar.rrt" ) {
    $data_exist = -s "$wrkdir/$server/$host/$lpar.rrt";
  }
  my $is_iopsr = test_metric_in_rrd( $host, $server, $lpar, "datastore", "Datastore_ReadAvg" );

  print "<div  id=\"tabs\">\n";
  print "<ul>\n";
  print "  <li class=\"\"><a href=\"#tabs-1\">Space</a></li>\n";
  if ($data_exist) {
    print "  <li class=\"\"><a href=\"#tabs-2\">Data</a></li>\n";
    print "  <li class=\"\"><a href=\"#tabs-3\">IOPS</a></li>\n"    if $is_iopsr;
    print "  <li class=\"\"><a href=\"#tabs-4\">IOPS/VM</a></li>\n" if ( -d "$wrkdir/$server/$host/$lpar" );
  }
  if ( -s "$wrkdir/$server/$host/$lpar.rru" ) {
    print "  <li class=\"\"><a href=\"#tabs-5\">Latency</a></li>\n";
  }
  print "  <li class=\"\"><a href=\"#tabs-6\">VM list</a></li>\n";
  #
  # KZ: mapping datastore -> volume (stor2rrd)
  #
  if ( exists $ENV{HTTP_XORUX_APP} && $ENV{HTTP_XORUX_APP} eq "Xormon" ) {
    my $lpar_uid = VmwareDataWrapper::get_item_uid( "datastore", $lpar_url );

    if ( defined $lpar_uid && $lpar_uid ne "" ) {
      my $prop = SQLiteDataWrapper::getItemProperties( { item_id => $lpar_uid } );
      if ( exists $prop->{disk_uids} && $prop->{disk_uids} ne '' ) {
        @lpar2volumes = split( /\s+/, $prop->{disk_uids} );

        print "  <li class='lpar2volumes'><a href=\"#tabs-7\">Volumes</a></li>\n";
      }
    }
  }
  print "</ul>\n";

  print "<CENTER>";

  # datastore MEM
  print "<div id=\"tabs-1\">\n";
  print "<table border=\"0\">\n";
  print "<tr>";

  $item = "dsmem";
  print_item( $host_url, $server_url, $lpar_url, $item, "d", $type_sam, $entitle, $detail_yes, "norefr", "nostar", 1, "legend" );
  print_item( $host_url, $server_url, $lpar_url, $item, "w", $type_sam, $entitle, $detail_yes, "norefr", "nostar", 1, "legend" );
  print "</tr>\n<tr>\n";
  print_item( $host_url, $server_url, $lpar_url, $item, "m", $type_sam,      $entitle, $detail_yes, "norefr", "nostar", 1, "legend" );
  print_item( $host_url, $server_url, $lpar_url, $item, "y", $type_sam_year, $entitle, $detail_yes, "norefr", "nostar", 1, "legend" );
  print "</tr>";
  print "<tr><td colspan=\"2\" align=\"left\">";
  print "</td></tr></table>";
  print "</div>\n";

  if ($data_exist) {

    # datastore Read-Write
    print "<div id=\"tabs-2\">\n";
    print "<table border=\"0\">\n";
    print "<tr>";

    $item = "dsrw";
    print_item( $host_url, $server_url, $lpar_url, $item, "d", $type_sam, $entitle, $detail_yes, "norefr", "nostar", 1, "legend" );
    print_item( $host_url, $server_url, $lpar_url, $item, "w", $type_sam, $entitle, $detail_yes, "norefr", "nostar", 1, "legend" );
    print "</tr>\n<tr>\n";
    print_item( $host_url, $server_url, $lpar_url, $item, "m", $type_sam,      $entitle, $detail_yes, "norefr", "nostar", 1, "legend" );
    print_item( $host_url, $server_url, $lpar_url, $item, "y", $type_sam_year, $entitle, $detail_yes, "norefr", "nostar", 1, "legend" );
    print "</tr>";
    print "<tr><td colspan=\"2\" align=\"left\">";
    print "</td></tr></table>";
    print "</div>\n";

    if ($is_iopsr) {

      # datastore Averaged-R-W
      print "<div id=\"tabs-3\">\n";
      print "<table border=\"0\">\n";
      print "<tr>";

      $item = "dsarw";
      print_item( $host_url, $server_url, $lpar_url, $item, "d", $type_sam, $entitle, $detail_yes, "norefr", "nostar", 1, "legend" );
      print_item( $host_url, $server_url, $lpar_url, $item, "w", $type_sam, $entitle, $detail_yes, "norefr", "nostar", 1, "legend" );
      print "</tr>\n<tr>\n";
      print_item( $host_url, $server_url, $lpar_url, $item, "m", $type_sam,      $entitle, $detail_yes, "norefr", "nostar", 1, "legend" );
      print_item( $host_url, $server_url, $lpar_url, $item, "y", $type_sam_year, $entitle, $detail_yes, "norefr", "nostar", 1, "legend" );
      print "</tr>";
      print "<tr><td colspan=\"2\" align=\"left\">";
      print "</td></tr></table>";
      print "</div>\n";

      # print "</div><br>\n";

      # datastore IOPS/VM
      if ( -d "$wrkdir/$server/$host/$lpar" ) {
        print "<div id=\"tabs-4\">\n";
        print "<table border=\"0\">\n";
        print "<tr>";

        $item = "ds-vmiops";
        print_item( $host_url, $server_url, $lpar_url, $item, "d", $type_sam, $entitle, $detail_yes, "norefr", "nostar", 1, "nolegend" );
        print_item( $host_url, $server_url, $lpar_url, $item, "w", $type_sam, $entitle, $detail_yes, "norefr", "nostar", 1, "nolegend" );
        print "</tr>\n<tr>\n";
        print_item( $host_url, $server_url, $lpar_url, $item, "m", $type_sam,      $entitle, $detail_yes, "norefr", "nostar", 1, "nolegend" );
        print_item( $host_url, $server_url, $lpar_url, $item, "y", $type_sam_year, $entitle, $detail_yes, "norefr", "nostar", 1, "nolegend" );
        print "</tr>";
        print "<tr><td colspan=\"2\" align=\"left\">";
        print "</td></tr></table>";
        print "</div>\n";
      }
    }
  }
  if ( -s "$wrkdir/$server/$host/$lpar.rru" ) {

    # datastore Latency
    print "<div id=\"tabs-5\">\n";
    print "<table border=\"0\">\n";
    print "<tr>";

    $item = "dslat";
    print_item( $host_url, $server_url, $lpar_url, $item, "d", $type_sam, $entitle, $detail_yes, "norefr", "nostar", 1, "legend" );
    print_item( $host_url, $server_url, $lpar_url, $item, "w", $type_sam, $entitle, $detail_yes, "norefr", "nostar", 1, "legend" );
    print "</tr>\n<tr>\n";
    print_item( $host_url, $server_url, $lpar_url, $item, "m", $type_sam,      $entitle, $detail_yes, "norefr", "nostar", 1, "legend" );
    print_item( $host_url, $server_url, $lpar_url, $item, "y", $type_sam_year, $entitle, $detail_yes, "norefr", "nostar", 1, "legend" );
    print "</tr>";
    print "<tr><td colspan=\"2\" align=\"left\">";
    print "</td></tr></table>";
    print "</div>\n";
  }

  print "<div id=\"tabs-6\">\n";
  my $file_html_disk = "$wrkdir/$server/$host/$lpar.html";
  $file_html_disk =~ s/%3A/:/g;    # host can have port vmware:444"
  my $disk_html;

  # print STDERR "detail-cgi.pl 1886 $file_html_disk\n";
  if ( -f "$file_html_disk" ) {
    open( FH, '<:encoding(UTF-8)', "$file_html_disk" );
    $disk_html = do { local $/; <FH> };
    close(FH);
    my $last_mod_time = ( stat($file_html_disk) )[9];
    print "<div id=\"tabs-2\">\n";
    print "<table border=\"0\">\n";
    print "<tr><td>\n";
    print "$disk_html";
    print "</td></tr>\n";
    print "<tr><td>\n";
    print "Updated: ";
    print scalar localtime $last_mod_time;
    print "<br>";
    print "</td></tr>\n";
    print "</table>\n";
    print "</div><br>\n";
  }
  print "</div>\n";
  print "</CENTER>";

  #
  # KZ: mapping lpar -> volume (stor2rrd)
  #
  if ( scalar(@lpar2volumes) > 0 ) {
    print "<div id =\"tabs-7\">";
    print "<div id=\"hiw\"><a href=\"http://www.xormon.com/storage-linking.php\" target=\"_blank\" class=\"nowrap\"><img src=\"css/images/help-browser.gif\" alt=\"Storage linking\" title=\"Storage linking\"></img></a></div>";
    print "<ul>\n";
    foreach my $volume_uid (@lpar2volumes) {
      if ( $volume_uid eq '' ) { next; }
      print "<li>$volume_uid</li>\n";
    }
    print "</ul>\n";
    print "</div>\n";
  }

  print "</div><br>\n";
  return 1;

}

sub print_resourcepool {
  my ( $host_url, $server_url, $lpar_url, $item, $entitle ) = @_;
  print "<div  id=\"tabs\">\n";
  print "<ul>\n";
  if ( $lpar_url ne "Resources" ) {
    print "  <li class=\"\"><a href=\"#tabs-2\">CPU</a></li>\n";
  }
  print "  <li class=\"\"><a href=\"#tabs-3\">CPU VMs</a></li>\n";
  if ( $lpar_url ne "Resources" ) {
    print "  <li class=\"\"><a href=\"#tabs-4\">Memory</a></li>\n";
  }
  print "</ul>\n";

  print "<CENTER>";

  if ( $lpar_url ne "Resources" ) {

    # resourcepool CPU
    print "<div id=\"tabs-2\">\n";
    print "<table border=\"0\">\n";
    print "<tr>";

    $item = "rpcpu";
    print_item( $host_url, $server_url, $lpar_url, $item, "d", $type_sam, $entitle, $detail_yes, "norefr", "nostar", 1, "legend" );
    print_item( $host_url, $server_url, $lpar_url, $item, "w", $type_sam, $entitle, $detail_yes, "norefr", "nostar", 1, "legend" );
    print "</tr>\n<tr>\n";
    print_item( $host_url, $server_url, $lpar_url, $item, "m", $type_sam,      $entitle, $detail_yes, "norefr", "nostar", 1, "legend" );
    print_item( $host_url, $server_url, $lpar_url, $item, "y", $type_sam_year, $entitle, $detail_yes, "norefr", "nostar", 1, "legend" );
    print "</tr>";

    print_item( $host_url, $server_url, $lpar_url, "trendrp", "y", $type_sam_year, $entitle, $detail_yes, "norefr", "nostar", 2, "legend" );

    print "<tr><td colspan=\"2\" align=\"left\">";
    print "</td></tr></table>";

    print "</div>\n";
  }

  # resourcepool LPAR
  print "<div id=\"tabs-3\">\n";
  print "$question_mark";
  print "<table border=\"0\">\n";
  print "<tr>";

  $item = "rplpar";
  print_item( $host_url, $server_url, $lpar_url, $item, "d", $type_sam, $entitle, $detail_yes, "norefr", "nostar", 1, "nolegend" );
  print_item( $host_url, $server_url, $lpar_url, $item, "w", $type_sam, $entitle, $detail_yes, "norefr", "nostar", 1, "nolegend" );
  print "</tr>\n<tr>\n";
  print_item( $host_url, $server_url, $lpar_url, $item, "m", $type_sam,      $entitle, $detail_yes, "norefr", "nostar", 1, "nolegend" );
  print_item( $host_url, $server_url, $lpar_url, $item, "y", $type_sam_year, $entitle, $detail_yes, "norefr", "nostar", 1, "nolegend" );
  print "</tr>";
  print "<tr><td colspan=\"2\" align=\"left\">";
  print "</td></tr></table>";

  print "</div>\n";

  if ( $lpar_url ne "Resources" ) {

    # resourcepool MEM
    print "<div id=\"tabs-4\">\n";
    print "<table border=\"0\">\n";
    print "<tr>";

    $item = "rpmem";
    print_item( $host_url, $server_url, $lpar_url, $item, "d", $type_sam, $entitle, $detail_yes, "norefr", "nostar", 1, "legend" );
    print_item( $host_url, $server_url, $lpar_url, $item, "w", $type_sam, $entitle, $detail_yes, "norefr", "nostar", 1, "legend" );
    print "</tr>\n<tr>\n";
    print_item( $host_url, $server_url, $lpar_url, $item, "m", $type_sam,      $entitle, $detail_yes, "norefr", "nostar", 1, "legend" );
    print_item( $host_url, $server_url, $lpar_url, $item, "y", $type_sam_year, $entitle, $detail_yes, "norefr", "nostar", 1, "legend" );

    print "</tr>\n";
    print "<tr>\n";
    print_item( $host_url, $server_url, $lpar_url, "trendrpmem", "y", $type_sam_year, $entitle, $detail_yes, "norefr", "nostar", 2, "legend" );
    print "</tr>\n";
    print "<tr><td align=\"left\" colspan=\"2\"><br>\n";
    print "</td></tr></table>\n";
    print "</div>\n";
  }

  print "</div><br>\n";

  return 1;
}

#my $question_mark = "<div id=\"hiw\"><a href=\"http://www.lpar2rrd.com/VMware-GHz-vrs-real_CPU.htm\" target=\"_blank\" class=\"nowrap\"><img src=\"css/images/help-browser.gif\" alt=\"How it works?\" title=\"How it works?\"></img></a></div>";

sub print_cluster {
  my ( $host_url, $server_url, $lpar_url, $item, $entitle ) = @_;

  # print STDERR "3581 detail-cgi.pl ($host_url,$server_url,$lpar_url,$item,$entitle)\n";

  if ($hyperv) {
    my $file_html_s2d = "$wrkdir/$server/$host/s2d_list.html";

    # print STDERR "3581 cluster hyperv\n";
    print "<div  id=\"tabs\">\n";
    print "<ul>\n";
    print "  <li class=\"\"><a href=\"#tabs-1\">CPU</a></li>\n";
    print "  <li class=\"\"><a href=\"#tabs-2\">CPU VMs</a></li>\n";
    print "  <li class=\"\"><a href=\"#tabs-3\">Memory</a></li>\n";
    print "  <li class=\"\"><a href=\"#tabs-4\">Nodes</a></li>\n";
    print "  <li class=\"\"><a href=\"#tabs-5\">IO</a></li>\n"       if ( -f "$file_html_s2d" );
    print "  <li class=\"\"><a href=\"#tabs-6\">Data</a></li>\n"     if ( -f "$file_html_s2d" );
    print "  <li class=\"\"><a href=\"#tabs-7\">Latency</a></li>\n"  if ( -f "$file_html_s2d" );
    print "  <li class=\"\"><a href=\"#tabs-8\">Capacity</a></li>\n" if ( -f "$file_html_s2d" );
    print "  <li class=\"\"><a href=\"#tabs-9\">Config</a></li>\n";
    print "  <li class=\"\"><a href=\"#tabs-10\">CFG-S2D</a></li>\n" if ( -f "$file_html_s2d" );
    print "</ul>\n";

    print "<CENTER>";

    #cluster CPU
    print "<div id=\"tabs-1\">\n";
    print "<table border=\"0\">\n";
    print "<tr>";

    $item = "hyp_clustsercpu";
    print_item( $host_url, $server_url, $lpar_url, $item, "d", $type_sam, $entitle, $detail_yes, "norefr", "star", 1, "legend" );
    print_item( $host_url, $server_url, $lpar_url, $item, "w", $type_sam, $entitle, $detail_yes, "norefr", "star", 1, "legend" );
    print "</tr>\n<tr>\n";
    print_item( $host_url, $server_url, $lpar_url, $item, "m", $type_sam,      $entitle, $detail_yes, "norefr", "star", 1, "legend" );
    print_item( $host_url, $server_url, $lpar_url, $item, "y", $type_sam_year, $entitle, $detail_yes, "norefr", "star", 1, "legend" );
    print "</tr>";

    # print_item( $host_url, $server_url, $lpar_url, "trendcluster", "y", $type_sam_year, $entitle, $detail_no, "norefr", "nostar", 2, "legend" );

    print "<tr><td colspan=\"2\" align=\"left\">";
    print "</td></tr></table>";

    print "</div>\n";

    #clusterCPU VMs
    print "<div id=\"tabs-2\">\n";
    print "<table border=\"0\">\n";
    print "<tr>";

    $item = "hyp_clustservms";
    print_item( $host_url, $server_url, $lpar_url, $item, "d", $type_sam, $entitle, $detail_yes, "norefr", "star", 1, "nolegend" );
    print_item( $host_url, $server_url, $lpar_url, $item, "w", $type_sam, $entitle, $detail_yes, "norefr", "star", 1, "nolegend" );
    print "</tr>\n<tr>\n";
    print_item( $host_url, $server_url, $lpar_url, $item, "m", $type_sam,      $entitle, $detail_yes, "norefr", "star", 1, "nolegend" );
    print_item( $host_url, $server_url, $lpar_url, $item, "y", $type_sam_year, $entitle, $detail_yes, "norefr", "star", 1, "nolegend" );
    print "</tr>";

    print "<tr><td colspan=\"2\" align=\"left\">";
    print "</td></tr></table>";

    print "</div>\n";

    #cluster MEMORY
    print "<div id=\"tabs-3\">\n";
    print "<table border=\"0\">\n";
    print "<tr>";

    $item = "hyp_clustsermem";
    print_item( $host_url, $server_url, $lpar_url, $item, "d", $type_sam, $entitle, $detail_yes, "norefr", "star", 1, "legend" );
    print_item( $host_url, $server_url, $lpar_url, $item, "w", $type_sam, $entitle, $detail_yes, "norefr", "star", 1, "legend" );
    print "</tr>\n<tr>\n";
    print_item( $host_url, $server_url, $lpar_url, $item, "m", $type_sam,      $entitle, $detail_yes, "norefr", "star", 1, "legend" );
    print_item( $host_url, $server_url, $lpar_url, $item, "y", $type_sam_year, $entitle, $detail_yes, "norefr", "star", 1, "legend" );
    print "</tr>";

    print "<tr><td colspan=\"2\" align=\"left\">";
    print "</td></tr></table>";

    print "</div>\n";

    #cluster SERVER
    print "<div id=\"tabs-4\">\n";
    print "<table border=\"0\">\n";
    print "<tr>";

    $item = "hyp_clustser";
    print_item( $host_url, $server_url, $lpar_url, $item, "d", $type_sam, $entitle, $detail_yes, "norefr", "star", 1, "nolegend" );
    print_item( $host_url, $server_url, $lpar_url, $item, "w", $type_sam, $entitle, $detail_yes, "norefr", "star", 1, "nolegend" );
    print "</tr>\n<tr>\n";
    print_item( $host_url, $server_url, $lpar_url, $item, "m", $type_sam,      $entitle, $detail_yes, "norefr", "star", 1, "nolegend" );
    print_item( $host_url, $server_url, $lpar_url, $item, "y", $type_sam_year, $entitle, $detail_yes, "norefr", "star", 1, "nolegend" );
    print "</tr>";

    print "<tr><td colspan=\"2\" align=\"left\">";
    print "</td></tr></table>";

    print "</div>\n";

    # volume_agr_IOPS
    if ( -f $file_html_s2d ) {
      print "<div id=\"tabs-5\">\n";
      print "<table border=\"0\">\n";
      print "<tr>";

      $item = "s2d_volume_agr_iops";
      print_item( $host_url, $server_url, $lpar_url, $item, "d", $type_sam, $entitle, $detail_yes, "norefr", "star", 1, "nolegend" );
      print_item( $host_url, $server_url, $lpar_url, $item, "w", $type_sam, $entitle, $detail_yes, "norefr", "star", 1, "nolegend" );
      print "</tr>\n<tr>\n";
      print_item( $host_url, $server_url, $lpar_url, $item, "m", $type_sam,      $entitle, $detail_yes, "norefr", "star", 1, "nolegend" );
      print_item( $host_url, $server_url, $lpar_url, $item, "y", $type_sam_year, $entitle, $detail_yes, "norefr", "star", 1, "nolegend" );
      print "</tr>";

      print "<tr><td colspan=\"2\" align=\"left\">";
      print "</td></tr></table>";

      print "</div>\n";
    }

    # volume_agr_data
    if ( -f $file_html_s2d ) {
      print "<div id=\"tabs-6\">\n";
      print "<table border=\"0\">\n";
      print "<tr>";

      $item = "s2d_volume_agr_data";
      print_item( $host_url, $server_url, $lpar_url, $item, "d", $type_sam, $entitle, $detail_yes, "norefr", "star", 1, "nolegend" );
      print_item( $host_url, $server_url, $lpar_url, $item, "w", $type_sam, $entitle, $detail_yes, "norefr", "star", 1, "nolegend" );
      print "</tr>\n<tr>\n";
      print_item( $host_url, $server_url, $lpar_url, $item, "m", $type_sam,      $entitle, $detail_yes, "norefr", "star", 1, "nolegend" );
      print_item( $host_url, $server_url, $lpar_url, $item, "y", $type_sam_year, $entitle, $detail_yes, "norefr", "star", 1, "nolegend" );
      print "</tr>";

      print "<tr><td colspan=\"2\" align=\"left\">";
      print "</td></tr></table>";

      print "</div>\n";
    }

    # volume_agr_latency
    if ( -f $file_html_s2d ) {
      print "<div id=\"tabs-7\">\n";
      print "<table border=\"0\">\n";
      print "<tr>";

      $item = "s2d_volume_agr_latency";
      print_item( $host_url, $server_url, $lpar_url, $item, "d", $type_sam, $entitle, $detail_yes, "norefr", "star", 1, "nolegend" );
      print_item( $host_url, $server_url, $lpar_url, $item, "w", $type_sam, $entitle, $detail_yes, "norefr", "star", 1, "nolegend" );
      print "</tr>\n<tr>\n";
      print_item( $host_url, $server_url, $lpar_url, $item, "m", $type_sam,      $entitle, $detail_yes, "norefr", "star", 1, "nolegend" );
      print_item( $host_url, $server_url, $lpar_url, $item, "y", $type_sam_year, $entitle, $detail_yes, "norefr", "star", 1, "nolegend" );
      print "</tr>";

      print "<tr><td colspan=\"2\" align=\"left\">";
      print "</td></tr></table>";

      print "</div>\n";
    }

    # volume_agr_capacity
    if ( -f $file_html_s2d ) {
      print "<div id=\"tabs-8\">\n";
      print "<table border=\"0\">\n";
      print "<tr>";

      $item = "s2d_volume_capagr";
      print_item( $host_url, $server_url, $lpar_url, $item, "d", $type_sam, $entitle, $detail_yes, "norefr", "star", 1, "nolegend" );
      print_item( $host_url, $server_url, $lpar_url, $item, "w", $type_sam, $entitle, $detail_yes, "norefr", "star", 1, "nolegend" );
      print "</tr>\n<tr>\n";
      print_item( $host_url, $server_url, $lpar_url, $item, "m", $type_sam,      $entitle, $detail_yes, "norefr", "star", 1, "nolegend" );
      print_item( $host_url, $server_url, $lpar_url, $item, "y", $type_sam_year, $entitle, $detail_yes, "norefr", "star", 1, "nolegend" );
      print "</tr>";

      print "<tr><td colspan=\"2\" align=\"left\">";
      print "</td></tr></table>";

      print "</div>\n";
    }

    print "<div id=\"tabs-9\">\n";
    my $file_html_nodes = "$wrkdir/$server/$host/cluster_list.html";
    my $nodes_html;

    # print STDERR "detail-cgi.pl 3818 $file_html_nodes\n";
    if ( -f "$file_html_nodes" ) {
      open( FH, "< $file_html_nodes" );
      $nodes_html = do { local $/; <FH> };
      close(FH);

      #print "<div id=\"tabs-2\">\n";
      print "<table border=\"0\">\n";
      print "<tr><td>\n";
      print "$nodes_html";
      print "</td></tr>\n";
      print "<tr><td>\n";
      my $last_mod_time = ( stat($file_html_nodes) )[9];
      print "The table is updated: ";
      print scalar localtime $last_mod_time;
      print "<br>";
      print "</td></tr>\n";
      print "</table>\n";
    }

    $file_html_nodes = "$wrkdir/$server/$host/node_list.html";

    #$file_html_nodes =~ s/%3A/:/g;    # host can have port vmware:444"

    # print STDERR "detail-cgi.pl 3841 $file_html_nodes\n";
    if ( -f "$file_html_nodes" ) {
      open( FH, "< $file_html_nodes" );
      $nodes_html = do { local $/; <FH> };
      close(FH);

      #print "<div id=\"tabs-2\">\n";
      print "<table border=\"0\">\n";
      print "<tr><td>\n";
      print "$nodes_html";
      print "</td></tr>\n";
      print "<tr><td>\n";
      my $last_mod_time = ( stat($file_html_nodes) )[9];
      print "The table is updated: ";
      print scalar localtime $last_mod_time;
      print "<br>";
      print "</td></tr>\n";
      print "</table>\n";
    }

    print "</div>\n";

    ## s2d_list
    my $s2d_html;

    if ( -f "$file_html_s2d" ) {
      print "<div id=\"tabs-10\">\n";
      open( my $FH, "< $file_html_s2d" );
      $s2d_html = do { local $/; <$FH> };
      close($FH);

      print "<table border=\"0\">\n";
      print "<tr><td>\n";
      print "$s2d_html";
      print "</td></tr>\n";
      print "<tr><td>\n";
      my $last_mod_time = ( stat($file_html_s2d) )[9];
      print "Last update: ";
      print scalar localtime $last_mod_time;
      print "<br>";
      print "</td></tr>\n";
      print "</table>\n";
    }
    ## end of s2d_list

    print "</div><br>\n";

    return 1;
  }

  # my $is_power = test_metric_in_rrd( $host, $server, $lpar, $item, "Power_usage_Watt" );
  # my $is_power = 0;    # since 4.95-7 do not print power
  my $is_power = 1;    # since 7.5 print Power_usage_Watt as an aggregate from esxi pool.rrm data
  $params{d_platform} = "VMware";
  my $rp_html_file = "$wrkdir/$server/$host/rp_config.html";

  print "<div  id=\"tabs\">\n";
  print "<ul>\n";
  print "  <li class=\"\"><a href=\"#tabs-2\">CPU</a></li>\n";
  print "  <li class=\"\"><a href=\"#tabs-3\">CPU VMs</a></li>\n";
  print "  <li class=\"\"><a href=\"#tabs-4\">Memory</a></li>\n";
  print "  <li class=\"\"><a href=\"#tabs-5\">Server</a></li>\n";
  print "  <li class=\"\"><a href=\"#tabs-6\">CPU Ready</a></li>\n";
  print "  <li class=\"\"><a href=\"#tabs-7\">LAN</a></li>\n";
  print "  <li class=\"\"><a href=\"#tabs-8\">Power</a></li>\n" if $is_power;
  print "  <li class=\"\"><a href=\"#tabs-9\">VM Space</a></li>\n";
  print "  <li class=\"\"><a href=\"#tabs-10\">Configuration</a></li>\n" if -f $rp_html_file;
  print "</ul>\n";

  print "<CENTER>";

  #cluster CPU
  print "<div id=\"tabs-2\">\n";
  print "<table border=\"0\">\n";
  print "<tr>";

  $item = "clustcpu";
  print_item( $host_url, $server_url, $lpar_url, $item, "d", $type_sam, $entitle, $detail_yes, "norefr", "star", 1, "legend" );
  print_item( $host_url, $server_url, $lpar_url, $item, "w", $type_sam, $entitle, $detail_yes, "norefr", "star", 1, "legend" );
  print "</tr>\n<tr>\n";
  print_item( $host_url, $server_url, $lpar_url, $item, "m", $type_sam,      $entitle, $detail_yes, "norefr", "star", 1, "legend" );
  print_item( $host_url, $server_url, $lpar_url, $item, "y", $type_sam_year, $entitle, $detail_yes, "norefr", "star", 1, "legend" );
  print "</tr>";

  print_item( $host_url, $server_url, $lpar_url, "trendcluster", "y", $type_sam_year, $entitle, $detail_yes, "norefr", "nostar", 2, "legend" );

  print "<tr><td colspan=\"2\" align=\"left\">";
  print "</td></tr></table>";

  print "</div>\n";

  #hmctotals LPAR
  print "<div id=\"tabs-3\">\n";
  print "$question_mark";
  print "<table border=\"0\">\n";
  print "<tr>";

  $item = "clustlpar";
  print_item( $host_url, $server_url, $lpar_url, $item, "d", $type_sam, $entitle, $detail_yes, "norefr", "star", 1, "nolegend" );
  print_item( $host_url, $server_url, $lpar_url, $item, "w", $type_sam, $entitle, $detail_yes, "norefr", "star", 1, "nolegend" );
  print "</tr>\n<tr>\n";
  print_item( $host_url, $server_url, $lpar_url, $item, "m", $type_sam,      $entitle, $detail_yes, "norefr", "star", 1, "nolegend" );
  print_item( $host_url, $server_url, $lpar_url, $item, "y", $type_sam_year, $entitle, $detail_yes, "norefr", "star", 1, "nolegend" );
  print "</tr>";
  print "<tr><td colspan=\"2\" align=\"left\">";
  print "</td></tr></table>";

  print "</div>\n";

  #cluster MEM
  print "<div id=\"tabs-4\">\n";
  print "<table border=\"0\">\n";
  print "<tr>";

  $item = "clustmem";
  print_item( $host_url, $server_url, $lpar_url, $item, "d", $type_sam, $entitle, $detail_yes, "norefr", "star", 1, "legend" );
  print_item( $host_url, $server_url, $lpar_url, $item, "w", $type_sam, $entitle, $detail_yes, "norefr", "star", 1, "legend" );
  print "</tr>\n<tr>\n";
  print_item( $host_url, $server_url, $lpar_url, $item, "m", $type_sam,      $entitle, $detail_yes, "norefr", "star", 1, "legend" );
  print_item( $host_url, $server_url, $lpar_url, $item, "y", $type_sam_year, $entitle, $detail_yes, "norefr", "star", 1, "legend" );

  print "</tr>\n";
  print "<tr>\n";
  print_item( $host_url, $server_url, $lpar_url, "trendclmem", "y", $type_sam_year, $entitle, $detail_yes, "norefr", "nostar", 2, "legend" );
  print "</tr>\n";
  print "<tr><td align=\"left\" colspan=\"2\"><br>\n";
  print "</td></tr></table>\n";
  print "</div>\n";

  #cluster SERVER
  print "<div id=\"tabs-5\">\n";
  print "<table border=\"0\">\n";
  print "<tr>";

  $item = "clustser";
  print_item( $host_url, $server_url, $lpar_url, $item, "d", $type_sam, $entitle, $detail_yes, "norefr", "star", 1, "nolegend" );
  print_item( $host_url, $server_url, $lpar_url, $item, "w", $type_sam, $entitle, $detail_yes, "norefr", "star", 1, "nolegend" );
  print "</tr>\n<tr>\n";
  print_item( $host_url, $server_url, $lpar_url, $item, "m", $type_sam,      $entitle, $detail_yes, "norefr", "star", 1, "nolegend" );
  print_item( $host_url, $server_url, $lpar_url, $item, "y", $type_sam_year, $entitle, $detail_yes, "norefr", "star", 1, "nolegend" );
  print "</tr>";

  print "<tr><td colspan=\"2\" align=\"left\">";
  print "</td></tr></table>";

  print "</div>\n";

  #cluster RDY
  print "<div id=\"tabs-6\">\n";
  print "<table border=\"0\">\n";
  print "<tr>";

  $item = "clustlpardy";
  print_item( $host_url, $server_url, $lpar_url, $item, "d", $type_sam, $entitle, $detail_yes, "norefr", "star", 1, "nolegend" );
  print_item( $host_url, $server_url, $lpar_url, $item, "w", $type_sam, $entitle, $detail_yes, "norefr", "star", 1, "nolegend" );
  print "</tr>\n<tr>\n";
  print_item( $host_url, $server_url, $lpar_url, $item, "m", $type_sam,      $entitle, $detail_yes, "norefr", "star", 1, "nolegend" );
  print_item( $host_url, $server_url, $lpar_url, $item, "y", $type_sam_year, $entitle, $detail_yes, "norefr", "star", 1, "nolegend" );
  print "</tr>";
  print "<tr><td colspan=\"2\" align=\"left\">";
  print "</td></tr></table>";

  print "</div>\n";

  #cluster LAN
  print "<div id=\"tabs-7\">\n";
  print "<table border=\"0\">\n";
  print "<tr>";

  $item = "clustlan";
  print_item( $host_url, $server_url, $lpar_url, $item, "d", $type_sam, $entitle, $detail_yes, "norefr", "star", 1, "nolegend" );
  print_item( $host_url, $server_url, $lpar_url, $item, "w", $type_sam, $entitle, $detail_yes, "norefr", "star", 1, "nolegend" );
  print "</tr>\n<tr>\n";
  print_item( $host_url, $server_url, $lpar_url, $item, "m", $type_sam,      $entitle, $detail_yes, "norefr", "star", 1, "nolegend" );
  print_item( $host_url, $server_url, $lpar_url, $item, "y", $type_sam_year, $entitle, $detail_yes, "norefr", "star", 1, "nolegend" );
  print "</tr>";
  print "<tr><td colspan=\"2\" align=\"left\">";
  print "</td></tr></table>";

  print "</div>\n";

  #cluster POWER
  if ($is_power) {
    print "<div id=\"tabs-8\">\n";
    print "<table border=\"0\">\n";
    print "<tr>";

    #$item = "clustpow";
    $item = "clustser_power";    # since 7.5
    print_item( $host_url, $server_url, $lpar_url, $item, "d", $type_sam, $entitle, $detail_yes, "norefr", "nostar", 1, "nolegend" );
    print_item( $host_url, $server_url, $lpar_url, $item, "w", $type_sam, $entitle, $detail_yes, "norefr", "nostar", 1, "nolegend" );
    print "</tr>\n<tr>\n";
    print_item( $host_url, $server_url, $lpar_url, $item, "m", $type_sam,      $entitle, $detail_yes, "norefr", "nostar", 1, "nolegend" );
    print_item( $host_url, $server_url, $lpar_url, $item, "y", $type_sam_year, $entitle, $detail_yes, "norefr", "nostar", 1, "nolegend" );
    print "</tr>";
    print "<tr><td colspan=\"2\" align=\"left\">";
    print "</td></tr></table>";

    print "</div>\n";
    print "<tr>\n";
  }

  #cluster VM SPACE
  # print STDERR "5416 detail-cgi.pl ($host_url,$server_url,$lpar_url,$item,$entitle,$wrkdir/$server/$host)\n";

  # merge html tables from all servers in cluster

  print "<div id=\"tabs-9\">\n";
  print "<table border=\"0\">\n";
  print "<tr>";

  # print "VM SPACE table";
  my $file_hosts_in_cluster = "$wrkdir/$server/$host/hosts_in_cluster";
  $file_hosts_in_cluster =~ s/%3A/:/g;    # host can have port vmware:444"
  if ( -f "$file_hosts_in_cluster" ) {
    open( FH, "<", "$file_hosts_in_cluster" );
    chomp( my @hosts_in_cluster = <FH> );
    close(FH);

    # print STDERR "5428 $hosts_in_cluster[0], $hosts_in_cluster[1],$hosts_in_cluster[2]\n";
    my @disk_html_cluster = ();
    foreach (@hosts_in_cluster) {    #10.22.11.14XORUX10.22.11.10
      ( my $esxi, my $esxi_host ) = split "XORUX", $_;
      next if !defined $esxi or !defined $esxi_host or $esxi eq "" or $esxi_host eq "";
      my $file_html_disk = "$wrkdir/$esxi/$esxi_host/disk.html";
      $file_html_disk =~ s/%3A/:/g;    # host can have port vmware:444"
                                       # print STDERR "5435 $esxi $esxi_host $file_html_disk\n";
      if ( -f "$file_html_disk" ) {
        open( FH, "<", "$file_html_disk" );
        my @disk_html = <FH>;
        close(FH);
        if ( !defined $disk_html_cluster[0] ) {

          # first time here -> prepare table heading, add first SERVER column
          $disk_html_cluster[0] = $disk_html[0];    # <BR><CENTER><TABLE class="tabconfig tablesorter">
          $disk_html_cluster[1] = $disk_html[1];    # <thead><TR> <TH class="sortable" valign="center">VM&nbsp;&nbsp;&nbsp;&nbsp;</TH>
          $disk_html_cluster[1] =~ s/<TH/<TH class="sortable" valign="center">SERVER&nbsp;&nbsp;&nbsp;&nbsp;<\/TH><TH/;
          $disk_html_cluster[2] = $disk_html[2];
          $disk_html_cluster[3] = $disk_html[3];
          $disk_html_cluster[4] = $disk_html[4];
        }
        shift @disk_html;
        shift @disk_html;
        shift @disk_html;
        shift @disk_html;
        shift @disk_html;
        pop @disk_html;                                                   # remove 5 first lines & last one
        s/<TR> <TD>/<TR> <TD><B>$esxi<\/B><\/TD> <TD>/ for @disk_html;    # <TR> <TD><B>TSM</B></TD> <TD align="right" nowrap>112.0</TD> <TD align="right" nowrap>66.0</TD></TR>
        push( @disk_html_cluster, @disk_html );
      }
    }

    # open( FH, ">", "/tmp/aa_log.html" );
    # print FH "@disk_html_cluster\n";
    # close FH;
    # print STDERR "5454 \@disk_html_cluster @disk_html_cluster\n";

    print "@disk_html_cluster\n";

  }

  print "</tr></table>";

  if ( -f "$file_hosts_in_cluster" ) {
    my $last_mod_time = ( stat($file_hosts_in_cluster) )[9];
    print "The table is updated: ";
    print scalar localtime $last_mod_time;
  }

  print "</div>\n";

  # resource pool config
  if ( -f $rp_html_file ) {
    print "<div id=\"tabs-10\">\n";
    print "<table border=\"0\">\n";
    print "<tr>";

    print "</tr>";
    print_html_file( urldecode("$rp_html_file") );
    print "</div>\n";
  }

  print "</div><br>\n";

  return 1;
}

# testing: if metric in rrd is during last year or month active = has average value -> returns true, if NaN -> returns false
sub test_metric_in_rrd {
  my ( $server, $host, $lpar, $item, $ds ) = @_;

  my $rrd = "$wrkdir/$server/$host/$lpar";

  if ( $item eq "cluster" ) {
    $rrd = "$wrkdir/$host/$server/cluster.rrc";
  }

  if ( $item eq "datastore" ) {
    $rrd = "$wrkdir/$host/$server/$lpar.rrt";
  }
  if ( !-f $rrd ) {
    error( "Cannot open $rrd: item:$item datastream:$ds " . __FILE__ . ":" . __LINE__ );
    return 0;
  }
  if ( -s $rrd == 0 ) {    # no data ?
    return 0;
  }

  my $rrdtool = $ENV{RRDTOOL};

  # start RRD via a pipe
  RRDp::start "$rrdtool";

  $rrd =~ s/:/\\:/g;
  my $answer = "";
  eval {
    RRDp::cmd qq(graph "tmp/name.png"
      "--start" "-1m"
      "--end" "now"
      "DEF:val=$rrd:$ds:AVERAGE"
      "PRINT:val:AVERAGE: %3.3lf"
      );

    $answer = RRDp::read;
  };
  if ($@) {
    error( "Rrdtool error : $@ " . __FILE__ . ":" . __LINE__ );
    RRDp::end;
    return 0;
  }

  #my $answer = RRDp::read;

  #  print STDERR "----- testing $rrd - $ds ->res = $answer-$$answer\n";
  if ( $$answer !~ m/NaN/ && $$answer !~ m/nan/ ) {

    # close RRD pipe
    RRDp::end;
    return 1;
  }

  eval {
    RRDp::cmd qq(graph "tmp/name.png"
      "--start" "-1y"
      "--end" "now"
      "DEF:val=$rrd:$ds:AVERAGE"
      "PRINT:val:AVERAGE: %3.3lf"
      );
    $answer = RRDp::read;
  };
  if ($@) {
    error( "Rrdtool error : $@ " . __FILE__ . ":" . __LINE__ );
    RRDp::end;
    return 0;
  }

  # print STDERR "----- testing $rrd - $ds ->res = $answer-$$answer\n";
  if ( $$answer !~ m/NaN/ && $$answer !~ m/nan/ ) {

    # close RRD pipe
    RRDp::end;
    return 1;
  }

  # close RRD pipe
  RRDp::end;
  return 0;
}

# specific to Custom groups, where the platform/host is "Power"
sub print_custom_lpar_details {
  my (@list_rrd) = @_;                                                    #one array parameter can be passed this way
  my $rest_api   = is_any_host_rest();
  my $table_head = "<BR><CENTER><TABLE class=\"tabconfig tablesorter\">
<thead><TR><TH class=\"sortable\" >LPAR name</TH><TH class=\"sortable\" align=\"center\">Mode</TH><TH class=\"sortable\" align=\"center\">Min</TH> <TH class=\"sortable\" align=\"center\">Assigned</TH><TH class=\"sortable\" align=\"center\">Max</TH><TH align=\"center\" class=\"sortable\" valign=\"center\">min VP</TH><TH class=\"sortable\" align=\"center\">Virtual</TH><TH align=\"center\" class=\"sortable\" valign=\"center\">max VP</TH> <TH class=\"sortable\" align=\"center\">Sharing mode</TH><TH class=\"sortable\" align=\"center\">Uncap weight</TH><TH class=\"sortable\" align=\"center\">Pool</B></font></TH><TH class=\"sortable\" align=\"center\">OS</TH></TR></thead><tbody>";

  my $head_printed = 0;
  my @choice       = grep /\.rr[a-z]$/, @list_rrd;
  my $C;
  my $o;
  my $done_conf;
  foreach my $line (@choice) {
    return if index( $line, "\/vmware_VMs\/" ) != -1;    # not for VMWARE
    chomp $line;
    $line =~ s/\.rr[a-z]$//;
    my $lpar = basename($line);
    $line =~ s/(.*)\/.*$/$1/;                            #give me path
    if ($rest_api) {
      if ( !( defined $done_conf->{$line} || $done_conf->{$line} ) ) {
        if ( -e "$line/CONFIG.json" ) {
          $C = Xorux_lib::read_json("$line/CONFIG.json");
          if ( ref( $C->{lpar} ) eq "HASH" ) {
            foreach my $key ( keys %{ $C->{lpar} } ) {
              $o->{$key} = $C->{lpar}{$key};
            }
          }
        }
      }
      $done_conf->{$line} = "true";
    }
    my $cpu_html = "$line" . "/cpu.html";
    open( FH, " < $cpu_html" ) || error( "Cannot open $cpu_html: $!" . __FILE__ . ":" . __LINE__ ) && next;
    my @cpu = <FH>;
    close FH;
    $lpar =~ s/\&\&1/\//g;
    my @lpar_line = grep /<B>$lpar</, @cpu;
    my $lpl       = @lpar_line;

    #`echo "print custom det lpar_line ,$lpar,@lpar_line,$lpl,\n,@choice, " >> /tmp/xpcd`;
    next if $lpl == 0;    # nothing to show
    if ( $head_printed == 0 ) {
      print "$table_head";
      $head_printed++;
    }
    if ( !$rest_api ) {
      print @lpar_line;
    }
    else {
      my $mode = "";
      if ( defined $o->{$lpar}{SharedProcessorPoolID} ) {
        $mode = "shared";
      }
      else {
        if ( defined $o->{$lpar}{CurrentSharingMode} ) {
          $mode = "ded";
        }
      }
      my $MinimumProcessingUnits = "";
      $MinimumProcessingUnits = $o->{$lpar}{MinimumProcessingUnits} if defined( $o->{$lpar}{MinimumProcessingUnits} );
      my $CurrentProcessingUnits = "";
      $CurrentProcessingUnits = $o->{$lpar}{CurrentProcessingUnits} if defined( $o->{$lpar}{CurrentProcessingUnits} );
      my $MaximumProcessingUnits = "";
      $MaximumProcessingUnits = $o->{$lpar}{MaximumProcessingUnits} if defined( $o->{$lpar}{MaximumProcessingUnits} );
      my $AllocatedVirtualProcessors = "";
      $AllocatedVirtualProcessors = $o->{$lpar}{AllocatedVirtualProcessors} if defined( $o->{$lpar}{AllocatedVirtualProcessors} );
      my $MinimumVirtualProcessors = "";
      $MinimumVirtualProcessors = $o->{$lpar}{MinimumVirtualProcessors} if defined( $o->{$lpar}{MinimumVirtualProcessors} );
      my $MaximumVirtualProcessors = "";
      $MaximumVirtualProcessors = $o->{$lpar}{MaximumVirtualProcessors} if defined( $o->{$lpar}{MaximumVirtualProcessors} );
      my $CurrentSharingMode = "";
      $CurrentSharingMode = $o->{$lpar}{CurrentSharingMode} if defined( $o->{$lpar}{CurrentSharingMode} );
      my $CurrentUncappedWeight = "";
      $CurrentUncappedWeight = $o->{$lpar}{CurrentUncappedWeight} if defined( $o->{$lpar}{CurrentUncappedWeight} );
      my $SharedProcessorPoolID = "";
      $SharedProcessorPoolID = $o->{$lpar}{SharedProcessorPoolID} if defined( $o->{$lpar}{SharedProcessorPoolID} );
      my $OperatingSystemVersion = "";
      $OperatingSystemVersion = $o->{$lpar}{OperatingSystemVersion} if defined( $o->{$lpar}{OperatingSystemVersion} );
      print "<TR>
          <TD><B>$lpar</B></TD>
          <TD align=\"center\">$mode</TD>
          <TD align=\"center\">$MinimumProcessingUnits</TD>
          <TD align=\"center\">$CurrentProcessingUnits</TD>
          <TD align=\"center\">$MaximumProcessingUnits</TD>
          <TD align=\"center\">$MinimumVirtualProcessors</TD>
          <TD align=\"center\">$AllocatedVirtualProcessors</TD>
          <TD align=\"center\">$MaximumVirtualProcessors</TD>
          <TD align=\"center\">$CurrentSharingMode</TD>
          <TD align=\"center\">$CurrentUncappedWeight</TD>
          <TD align=\"center\">$SharedProcessorPoolID</TD>
          <TD align=\"center\" nowrap>$OperatingSystemVersion</TD>
        </TR>\n";
    }
  }
  if ( $head_printed != 0 ) {
    print "</tbody></TABLE></CENTER><BR><BR>";
  }
}

# Custom groups for XenServer (XENVM)
sub print_custom_xenserver {
  my ( $host_url, $server_url, $lpar_url, $item, $entitle ) = @_;

  # print page contents
  print "<CENTER>";
  print "<div id=\"tabs\">\n";

  # get tabs
  #my @tabs = @{ XenServerMenu::get_tabs( 'vm' ) };
  my @tabs = (
    { cpu_cores   => "CPU" },
    { cpu_percent => "CPU %" },
    { memory_used => "MEM used" },
    { memory_free => "MEM free" },
    { storage     => "Data" },
    { iops        => "IOPS" },
    { latency     => "Latency" },
    { net         => "Net" }
  );

  if (@tabs) {
    print "<ul>\n";

    my $tab_counter = 1;
    foreach my $tab_header (@tabs) {
      while ( my ( $tab_type, $tab_label ) = each %$tab_header ) {
        print "  <li><a href=\"#tabs-$tab_counter\">$tab_label</a></li>\n";
        $tab_counter++;
      }
    }

    print "</ul>\n";
  }

  sub print_tab_contents_custom {
    my ( $tab_number, $host_url, $server_url, $lpar_url, $item, $entitle, $detail_yes ) = @_;

    my $lpar_url_dec = $lpar_url;
    $lpar_url_dec =~ s/%([a-fA-F0-9][a-fA-F0-9])/pack("C", hex($1))/seg;
    my $notice_file  = "$tmpdir/.custom-group-$lpar_url_dec-n.cmd";
    my @final_notice = "";
    if ( -f $notice_file ) {
      open( FH, "$notice_file" ) || error( "Cannot open $notice_file: $!" . __FILE__ . ":" . __LINE__ ) && return 0;
      @final_notice = <FH>;
      close(FH);
    }

    print "<div id=\"tabs-$tab_number\">\n";
    print "<table border=\"0\">\n";
    print "<tr>";

    print_item( $host_url, $server_url, $lpar_url, $item, "d", $type_sam, $entitle, $detail_yes, "norefr", "star", 1, "nolegend" );
    print_item( $host_url, $server_url, $lpar_url, $item, "w", $type_sam, $entitle, $detail_yes, "norefr", "star", 1, "nolegend" );
    print "</tr>\n<tr>\n";
    print_item( $host_url, $server_url, $lpar_url, $item, "m", $type_sam,      $entitle, $detail_yes, "norefr", "star", 1, "nolegend" );
    print_item( $host_url, $server_url, $lpar_url, $item, "y", $type_sam_year, $entitle, $detail_yes, "norefr", "star", 1, "nolegend" );
    print "<tr><td align=\"center\" colspan=\"2\">@final_notice </td></tr>\n";

    # TODO year trend
    #print "</tr><tr>\n";
    #print_item( $host_url, $server_url, $lpar_url, "custom_cpu_trend", "y", $type_sam_year, $entitle, $detail_no, "norefr", "nostar", 2, "legend" );
    print "</tr></table>\n";
    print "</div>\n";
  }

  my @xen_items = ( "custom-xenvm-cpu-cores", "custom-xenvm-cpu-percent", "custom-xenvm-memory-used", "custom-xenvm-memory-free", "custom-xenvm-vbd", "custom-xenvm-vbd-iops", "custom-xenvm-vbd-latency", "custom-xenvm-lan" );
  for $tab_number ( 1 .. $#xen_items + 1 ) {
    print_tab_contents_custom( $tab_number, $host_url, $server_url, $lpar_url, $xen_items[ $tab_number - 1 ], $entitle, $detail_yes );
  }

  # end page contents
  print "</div><br>\n";
  print "</CENTER>\n";
}

# Custom groups for Ntuanix (NUTANIXVM)
sub print_custom_nutanix {
  my ( $host_url, $server_url, $lpar_url, $item, $entitle ) = @_;

  # print page contents
  print "<CENTER>";
  print "<div id=\"tabs\">\n";

  # get tabs
  my @tabs = (
    { cpu_cores   => "CPU" },
    { cpu_percent => "CPU %" },
    { memory_used => "MEM used" },
    { memory_free => "MEM free" },
    { storage     => "Data" },
    { iops        => "IOPS" },
    { latency     => "Latency" }
  );

  if (@tabs) {
    print "<ul>\n";

    my $tab_counter = 1;
    foreach my $tab_header (@tabs) {
      while ( my ( $tab_type, $tab_label ) = each %$tab_header ) {
        print "  <li><a href=\"#tabs-$tab_counter\">$tab_label</a></li>\n";
        $tab_counter++;
      }
    }

    print "</ul>\n";
  }

  sub print_tab_contents_custom_nutanix {
    my ( $tab_number, $host_url, $server_url, $lpar_url, $item, $entitle, $detail_yes ) = @_;

    my $lpar_url_dec = $lpar_url;
    $lpar_url_dec =~ s/%([a-fA-F0-9][a-fA-F0-9])/pack("C", hex($1))/seg;
    my $notice_file  = "$tmpdir/.custom-group-$lpar_url_dec-n.cmd";
    my @final_notice = "";
    if ( -f $notice_file ) {
      open( FH, "$notice_file" ) || error( "Cannot open $notice_file: $!" . __FILE__ . ":" . __LINE__ ) && return 0;
      @final_notice = <FH>;
      close(FH);
    }

    print "<div id=\"tabs-$tab_number\">\n";
    print "<table border=\"0\">\n";
    print "<tr>";

    print_item( $host_url, $server_url, $lpar_url, $item, "d", $type_sam, $entitle, $detail_yes, "norefr", "star", 1, "nolegend" );
    print_item( $host_url, $server_url, $lpar_url, $item, "w", $type_sam, $entitle, $detail_yes, "norefr", "star", 1, "nolegend" );
    print "</tr>\n<tr>\n";
    print_item( $host_url, $server_url, $lpar_url, $item, "m", $type_sam,      $entitle, $detail_yes, "norefr", "star", 1, "nolegend" );
    print_item( $host_url, $server_url, $lpar_url, $item, "y", $type_sam_year, $entitle, $detail_yes, "norefr", "star", 1, "nolegend" );
    print "<tr><td align=\"center\" colspan=\"2\">@final_notice </td></tr>\n";

    # TODO year trend
    #print "</tr><tr>\n";
    #print_item( $host_url, $server_url, $lpar_url, "custom_cpu_trend", "y", $type_sam_year, $entitle, $detail_no, "norefr", "nostar", 2, "legend" );
    print "</tr></table>\n";
    print "</div>\n";
  }

  my @nutanix_items = ( "custom-nutanixvm-cpu-cores", "custom-nutanixvm-cpu-percent", "custom-nutanixvm-memory-used", "custom-nutanixvm-memory-free", "custom-nutanixvm-vbd", "custom-nutanixvm-vbd-iops", "custom-nutanixvm-vbd-latency" );
  for $tab_number ( 1 .. $#nutanix_items + 1 ) {
    print_tab_contents_custom_nutanix( $tab_number, $host_url, $server_url, $lpar_url, $nutanix_items[ $tab_number - 1 ], $entitle, $detail_yes );
  }

  # end page contents
  print "</div><br>\n";
  print "</CENTER>\n";
}

# Custom groups for Proxmox (PROXMOXVM)
sub print_custom_proxmox {
  my ( $host_url, $server_url, $lpar_url, $item, $entitle ) = @_;

  # print page contents
  print "<CENTER>";
  print "<div id=\"tabs\">\n";

  # get tabs
  my @tabs = (
    { cpu_cores   => "CPU" },
    { cpu_percent => "CPU %" },
    { memory_used => "MEM used" },
    { memory_free => "MEM free" },
    { data        => "Data" },
    { net         => "Net" }
  );

  if (@tabs) {
    print "<ul>\n";

    my $tab_counter = 1;
    foreach my $tab_header (@tabs) {
      while ( my ( $tab_type, $tab_label ) = each %$tab_header ) {
        print "  <li><a href=\"#tabs-$tab_counter\">$tab_label</a></li>\n";
        $tab_counter++;
      }
    }

    print "</ul>\n";
  }

  sub print_tab_contents_custom_proxmox {
    my ( $tab_number, $host_url, $server_url, $lpar_url, $item, $entitle, $detail_yes ) = @_;

    my $lpar_url_dec = $lpar_url;
    $lpar_url_dec =~ s/%([a-fA-F0-9][a-fA-F0-9])/pack("C", hex($1))/seg;
    my $notice_file  = "$tmpdir/.custom-group-$lpar_url_dec-n.cmd";
    my @final_notice = "";
    if ( -f $notice_file ) {
      open( FH, "$notice_file" ) || error( "Cannot open $notice_file: $!" . __FILE__ . ":" . __LINE__ ) && return 0;
      @final_notice = <FH>;
      close(FH);
    }

    print "<div id=\"tabs-$tab_number\">\n";
    print "<table border=\"0\">\n";
    print "<tr>";

    print_item( $host_url, $server_url, $lpar_url, $item, "d", $type_sam, $entitle, $detail_yes, "norefr", "star", 1, "nolegend" );
    print_item( $host_url, $server_url, $lpar_url, $item, "w", $type_sam, $entitle, $detail_yes, "norefr", "star", 1, "nolegend" );
    print "</tr>\n<tr>\n";
    print_item( $host_url, $server_url, $lpar_url, $item, "m", $type_sam,      $entitle, $detail_yes, "norefr", "star", 1, "nolegend" );
    print_item( $host_url, $server_url, $lpar_url, $item, "y", $type_sam_year, $entitle, $detail_yes, "norefr", "star", 1, "nolegend" );
    print "<tr><td align=\"center\" colspan=\"2\">@final_notice </td></tr>\n";

    # TODO year trend
    #print "</tr><tr>\n";
    #print_item( $host_url, $server_url, $lpar_url, "custom_cpu_trend", "y", $type_sam_year, $entitle, $detail_no, "norefr", "nostar", 2, "legend" );
    print "</tr></table>\n";
    print "</div>\n";
  }

  my @proxmox_items = ( "custom-proxmoxvm-cpu", "custom-proxmoxvm-cpu-percent", "custom-proxmoxvm-memory-used", "custom-proxmoxvm-memory-free", "custom-proxmoxvm-data", "custom-proxmoxvm-net" );
  for $tab_number ( 1 .. $#proxmox_items + 1 ) {
    print_tab_contents_custom_proxmox( $tab_number, $host_url, $server_url, $lpar_url, $proxmox_items[ $tab_number - 1 ], $entitle, $detail_yes );
  }

  # end page contents
  print "</div><br>\n";
  print "</CENTER>\n";
}

# Custom groups for Kubernetes (KUBERNETESNODE)
sub print_custom_kubernetes {
  my ( $host_url, $server_url, $lpar_url, $item, $entitle ) = @_;

  # print page contents
  print "<CENTER>";
  print "<div id=\"tabs\">\n";

  # get tabs
  my @tabs = (
    { cpu_cores   => "CPU" },
    { cpu_percent => "CPU %" },
    { memory_used => "MEM used" },
    { data        => "Data" },
    { iops        => "IOPS" },
    { net         => "Net" },
  );

  if (@tabs) {
    print "<ul>\n";

    my $tab_counter = 1;
    foreach my $tab_header (@tabs) {
      while ( my ( $tab_type, $tab_label ) = each %$tab_header ) {
        print "  <li><a href=\"#tabs-$tab_counter\">$tab_label</a></li>\n";
        $tab_counter++;
      }
    }

    print "</ul>\n";
  }

  sub print_tab_contents_custom_kubernetes {
    my ( $tab_number, $host_url, $server_url, $lpar_url, $item, $entitle, $detail_yes ) = @_;

    my $lpar_url_dec = $lpar_url;
    $lpar_url_dec =~ s/%([a-fA-F0-9][a-fA-F0-9])/pack("C", hex($1))/seg;
    my $notice_file  = "$tmpdir/.custom-group-$lpar_url_dec-n.cmd";
    my @final_notice = "";
    if ( -f $notice_file ) {
      open( FH, "$notice_file" ) || error( "Cannot open $notice_file: $!" . __FILE__ . ":" . __LINE__ ) && return 0;
      @final_notice = <FH>;
      close(FH);
    }

    print "<div id=\"tabs-$tab_number\">\n";
    print "<table border=\"0\">\n";
    print "<tr>";

    print_item( $host_url, $server_url, $lpar_url, $item, "d", $type_sam, $entitle, $detail_yes, "norefr", "star", 1, "nolegend" );
    print_item( $host_url, $server_url, $lpar_url, $item, "w", $type_sam, $entitle, $detail_yes, "norefr", "star", 1, "nolegend" );
    print "</tr>\n<tr>\n";
    print_item( $host_url, $server_url, $lpar_url, $item, "m", $type_sam,      $entitle, $detail_yes, "norefr", "star", 1, "nolegend" );
    print_item( $host_url, $server_url, $lpar_url, $item, "y", $type_sam_year, $entitle, $detail_yes, "norefr", "star", 1, "nolegend" );
    print "<tr><td align=\"center\" colspan=\"2\">@final_notice </td></tr>\n";

    # TODO year trend
    #print "</tr><tr>\n";
    #print_item( $host_url, $server_url, $lpar_url, "custom_cpu_trend", "y", $type_sam_year, $entitle, $detail_no, "norefr", "nostar", 2, "legend" );
    print "</tr></table>\n";
    print "</div>\n";
  }

  my @kubernetes_items = ( "custom-kubernetesnode-cpu", "custom-kubernetesnode-cpu-percent", "custom-kubernetesnode-memory", "custom-kubernetesnode-data", "custom-kubernetesnode-iops", "custom-kubernetesnode-net" );
  for $tab_number ( 1 .. $#kubernetes_items + 1 ) {
    print_tab_contents_custom_kubernetes( $tab_number, $host_url, $server_url, $lpar_url, $kubernetes_items[ $tab_number - 1 ], $entitle, $detail_yes );
  }

  # end page contents
  print "</div><br>\n";
  print "</CENTER>\n";
}

# Custom groups for openshift (OPENSHIFTNODE)
sub print_custom_openshift {
  my ( $host_url, $server_url, $lpar_url, $item, $entitle ) = @_;

  # print page contents
  print "<CENTER>";
  print "<div id=\"tabs\">\n";

  # get tabs
  my @tabs = (
    { cpu_cores   => "CPU" },
    { cpu_percent => "CPU %" },
    { memory_used => "MEM used" },
    { data        => "Data" },
    { iops        => "IOPS" },
    { net         => "Net" },
  );

  if (@tabs) {
    print "<ul>\n";

    my $tab_counter = 1;
    foreach my $tab_header (@tabs) {
      while ( my ( $tab_type, $tab_label ) = each %$tab_header ) {
        print "  <li><a href=\"#tabs-$tab_counter\">$tab_label</a></li>\n";
        $tab_counter++;
      }
    }

    print "</ul>\n";
  }

  sub print_tab_contents_custom_openshift {
    my ( $tab_number, $host_url, $server_url, $lpar_url, $item, $entitle, $detail_yes ) = @_;

    my $lpar_url_dec = $lpar_url;
    $lpar_url_dec =~ s/%([a-fA-F0-9][a-fA-F0-9])/pack("C", hex($1))/seg;
    my $notice_file  = "$tmpdir/.custom-group-$lpar_url_dec-n.cmd";
    my @final_notice = "";
    if ( -f $notice_file ) {
      open( FH, "$notice_file" ) || error( "Cannot open $notice_file: $!" . __FILE__ . ":" . __LINE__ ) && return 0;
      @final_notice = <FH>;
      close(FH);
    }

    print "<div id=\"tabs-$tab_number\">\n";
    print "<table border=\"0\">\n";
    print "<tr>";

    print_item( $host_url, $server_url, $lpar_url, $item, "d", $type_sam, $entitle, $detail_yes, "norefr", "star", 1, "nolegend" );
    print_item( $host_url, $server_url, $lpar_url, $item, "w", $type_sam, $entitle, $detail_yes, "norefr", "star", 1, "nolegend" );
    print "</tr>\n<tr>\n";
    print_item( $host_url, $server_url, $lpar_url, $item, "m", $type_sam,      $entitle, $detail_yes, "norefr", "star", 1, "nolegend" );
    print_item( $host_url, $server_url, $lpar_url, $item, "y", $type_sam_year, $entitle, $detail_yes, "norefr", "star", 1, "nolegend" );
    print "<tr><td align=\"center\" colspan=\"2\">@final_notice </td></tr>\n";

    # TODO year trend
    #print "</tr><tr>\n";
    #print_item( $host_url, $server_url, $lpar_url, "custom_cpu_trend", "y", $type_sam_year, $entitle, $detail_no, "norefr", "nostar", 2, "legend" );
    print "</tr></table>\n";
    print "</div>\n";
  }

  my @openshift_items = ( "custom-openshiftnode-cpu", "custom-openshiftnode-cpu-percent", "custom-openshiftnode-memory", "custom-openshiftnode-data", "custom-openshiftnode-iops", "custom-openshiftnode-net" );
  for $tab_number ( 1 .. $#openshift_items + 1 ) {
    print_tab_contents_custom_openshift( $tab_number, $host_url, $server_url, $lpar_url, $openshift_items[ $tab_number - 1 ], $entitle, $detail_yes );
  }

  # end page contents
  print "</div><br>\n";
  print "</CENTER>\n";
}

# Custom groups for Kubernetes (KUBERNETESNAMESPACE)
sub print_custom_kubernetes_namespace {
  my ( $host_url, $server_url, $lpar_url, $item, $entitle ) = @_;

  # print page contents
  print "<CENTER>";
  print "<div id=\"tabs\">\n";

  # get tabs
  my @tabs = (
    { cpu_cores   => "CPU" },
    { memory_used => "MEM used" }
  );

  if (@tabs) {
    print "<ul>\n";

    my $tab_counter = 1;
    foreach my $tab_header (@tabs) {
      while ( my ( $tab_type, $tab_label ) = each %$tab_header ) {
        print "  <li><a href=\"#tabs-$tab_counter\">$tab_label</a></li>\n";
        $tab_counter++;
      }
    }

    print "</ul>\n";
  }

  sub print_tab_contents_custom_kubernetes_namespace {
    my ( $tab_number, $host_url, $server_url, $lpar_url, $item, $entitle, $detail_yes ) = @_;

    my $lpar_url_dec = $lpar_url;
    $lpar_url_dec =~ s/%([a-fA-F0-9][a-fA-F0-9])/pack("C", hex($1))/seg;
    my $notice_file  = "$tmpdir/.custom-group-$lpar_url_dec-n.cmd";
    my @final_notice = "";
    if ( -f $notice_file ) {
      open( FH, "$notice_file" ) || error( "Cannot open $notice_file: $!" . __FILE__ . ":" . __LINE__ ) && return 0;
      @final_notice = <FH>;
      close(FH);
    }

    print "<div id=\"tabs-$tab_number\">\n";
    print "<table border=\"0\">\n";
    print "<tr>";

    print_item( $host_url, $server_url, $lpar_url, $item, "d", $type_sam, $entitle, $detail_yes, "norefr", "star", 1, "nolegend" );
    print_item( $host_url, $server_url, $lpar_url, $item, "w", $type_sam, $entitle, $detail_yes, "norefr", "star", 1, "nolegend" );
    print "</tr>\n<tr>\n";
    print_item( $host_url, $server_url, $lpar_url, $item, "m", $type_sam,      $entitle, $detail_yes, "norefr", "star", 1, "nolegend" );
    print_item( $host_url, $server_url, $lpar_url, $item, "y", $type_sam_year, $entitle, $detail_yes, "norefr", "star", 1, "nolegend" );
    print "<tr><td align=\"center\" colspan=\"2\">@final_notice </td></tr>\n";

    # TODO year trend
    #print "</tr><tr>\n";
    #print_item( $host_url, $server_url, $lpar_url, "custom_cpu_trend", "y", $type_sam_year, $entitle, $detail_no, "norefr", "nostar", 2, "legend" );
    print "</tr></table>\n";
    print "</div>\n";
  }

  my @kubernetes_items = ( "custom-kubernetesnamespace-cpu", "custom-kubernetesnamespace-memory" );
  for $tab_number ( 1 .. $#kubernetes_items + 1 ) {
    print_tab_contents_custom_kubernetes_namespace( $tab_number, $host_url, $server_url, $lpar_url, $kubernetes_items[ $tab_number - 1 ], $entitle, $detail_yes );
  }

  # end page contents
  print "</div><br>\n";
  print "</CENTER>\n";
}

# Custom groups for Openshift (OPENSHIFTNAMESPACE)
sub print_custom_openshift_namespace {
  my ( $host_url, $server_url, $lpar_url, $item, $entitle ) = @_;

  # print page contents
  print "<CENTER>";
  print "<div id=\"tabs\">\n";

  # get tabs
  my @tabs = (
    { cpu_cores   => "CPU" },
    { memory_used => "MEM used" }
  );

  if (@tabs) {
    print "<ul>\n";

    my $tab_counter = 1;
    foreach my $tab_header (@tabs) {
      while ( my ( $tab_type, $tab_label ) = each %$tab_header ) {
        print "  <li><a href=\"#tabs-$tab_counter\">$tab_label</a></li>\n";
        $tab_counter++;
      }
    }

    print "</ul>\n";
  }

  sub print_tab_contents_custom_openshift_namespace {
    my ( $tab_number, $host_url, $server_url, $lpar_url, $item, $entitle, $detail_yes ) = @_;

    my $lpar_url_dec = $lpar_url;
    $lpar_url_dec =~ s/%([a-fA-F0-9][a-fA-F0-9])/pack("C", hex($1))/seg;
    my $notice_file  = "$tmpdir/.custom-group-$lpar_url_dec-n.cmd";
    my @final_notice = "";
    if ( -f $notice_file ) {
      open( FH, "$notice_file" ) || error( "Cannot open $notice_file: $!" . __FILE__ . ":" . __LINE__ ) && return 0;
      @final_notice = <FH>;
      close(FH);
    }

    print "<div id=\"tabs-$tab_number\">\n";
    print "<table border=\"0\">\n";
    print "<tr>";

    print_item( $host_url, $server_url, $lpar_url, $item, "d", $type_sam, $entitle, $detail_yes, "norefr", "star", 1, "nolegend" );
    print_item( $host_url, $server_url, $lpar_url, $item, "w", $type_sam, $entitle, $detail_yes, "norefr", "star", 1, "nolegend" );
    print "</tr>\n<tr>\n";
    print_item( $host_url, $server_url, $lpar_url, $item, "m", $type_sam,      $entitle, $detail_yes, "norefr", "star", 1, "nolegend" );
    print_item( $host_url, $server_url, $lpar_url, $item, "y", $type_sam_year, $entitle, $detail_yes, "norefr", "star", 1, "nolegend" );
    print "<tr><td align=\"center\" colspan=\"2\">@final_notice </td></tr>\n";

    # TODO year trend
    #print "</tr><tr>\n";
    #print_item( $host_url, $server_url, $lpar_url, "custom_cpu_trend", "y", $type_sam_year, $entitle, $detail_no, "norefr", "nostar", 2, "legend" );
    print "</tr></table>\n";
    print "</div>\n";
  }

  my @openshift_items = ( "custom-openshiftnamespace-cpu", "custom-openshiftnamespace-memory" );
  for $tab_number ( 1 .. $#openshift_items + 1 ) {
    print_tab_contents_custom_openshift_namespace( $tab_number, $host_url, $server_url, $lpar_url, $openshift_items[ $tab_number - 1 ], $entitle, $detail_yes );
  }

  # end page contents
  print "</div><br>\n";
  print "</CENTER>\n";
}

# Custom groups for FusionCompute (FUSIONCOMPUTEVM)
sub print_custom_fusioncompute {
  my ( $host_url, $server_url, $lpar_url, $item, $entitle ) = @_;

  # print page contents
  print "<CENTER>";
  print "<div id=\"tabs\">\n";

  # get tabs
  my @tabs = (
    { cpu_percent => "CPU %" },
    { cpu         => "CPU" },
    { mem         => "MEM%" },
    { mem_used    => "MEM used" },
    { mem_free    => "MEM free" },
    { data        => "Data" },
    { disk_ios    => "IOPS" },
    { disk_ticks  => "Latency" },
    { net         => "Net" }
  );

  if (@tabs) {
    print "<ul>\n";

    my $tab_counter = 1;
    foreach my $tab_header (@tabs) {
      while ( my ( $tab_type, $tab_label ) = each %$tab_header ) {
        print "  <li><a href=\"#tabs-$tab_counter\">$tab_label</a></li>\n";
        $tab_counter++;
      }
    }

    print "</ul>\n";
  }

  sub print_tab_contents_custom_fusioncompute {
    my ( $tab_number, $host_url, $server_url, $lpar_url, $item, $entitle, $detail_yes ) = @_;

    my $lpar_url_dec = $lpar_url;
    $lpar_url_dec =~ s/%([a-fA-F0-9][a-fA-F0-9])/pack("C", hex($1))/seg;
    my $notice_file  = "$tmpdir/.custom-group-$lpar_url_dec-n.cmd";
    my @final_notice = "";
    if ( -f $notice_file ) {
      open( FH, "$notice_file" ) || error( "Cannot open $notice_file: $!" . __FILE__ . ":" . __LINE__ ) && return 0;
      @final_notice = <FH>;
      close(FH);
    }

    print "<div id=\"tabs-$tab_number\">\n";
    print "<table border=\"0\">\n";
    print "<tr>";

    print_item( $host_url, $server_url, $lpar_url, $item, "d", $type_sam, $entitle, $detail_yes, "norefr", "star", 1, "nolegend" );
    print_item( $host_url, $server_url, $lpar_url, $item, "w", $type_sam, $entitle, $detail_yes, "norefr", "star", 1, "nolegend" );
    print "</tr>\n<tr>\n";
    print_item( $host_url, $server_url, $lpar_url, $item, "m", $type_sam,      $entitle, $detail_yes, "norefr", "star", 1, "nolegend" );
    print_item( $host_url, $server_url, $lpar_url, $item, "y", $type_sam_year, $entitle, $detail_yes, "norefr", "star", 1, "nolegend" );
    print "<tr><td align=\"center\" colspan=\"2\">@final_notice </td></tr>\n";

    # TODO year trend
    #print "</tr><tr>\n";
    #print_item( $host_url, $server_url, $lpar_url, "custom_cpu_trend", "y", $type_sam_year, $entitle, $detail_no, "norefr", "nostar", 2, "legend" );
    print "</tr></table>\n";
    print "</div>\n";
  }

  my @fusioncompute_items = ( "custom-fusioncomputevm-cpu-percent", "custom-fusioncomputevm-cpu", "custom-fusioncomputevm-mem-percent", "custom-fusioncomputevm-mem-free", "custom-fusioncomputevm-mem-used", "custom-fusioncomputevm-data", "custom-fusioncomputevm-disk-ios", "custom-fusioncomputevm-disk-ticks", "custom-fusioncomputevm-net" );
  for $tab_number ( 1 .. $#fusioncompute_items + 1 ) {
    print_tab_contents_custom_fusioncompute( $tab_number, $host_url, $server_url, $lpar_url, $fusioncompute_items[ $tab_number - 1 ], $entitle, $detail_yes );
  }

  # end page contents
  print "</div><br>\n";
  print "</CENTER>\n";
}

# Custom groups for oVirt (OVIRTVM)
sub print_custom_ovirt {
  my ( $host_url, $server_url, $lpar_url, $item, $entitle ) = @_;

  # print page contents
  print "<CENTER>";
  print "<div id=\"tabs\">\n";

  # get tabs
  my @tabs = (
    { cpu_core    => "CPU cores" },
    { cpu_percent => "CPU %" },
    { memory_used => "MEM used" },
    { memory_free => "MEM free" },

    # { data => "Data" },
    # { latency => "Latency" },
    # { net => "Net" }
  );

  if (@tabs) {
    print "<ul>\n";

    my $tab_counter = 1;
    foreach my $tab_header (@tabs) {
      while ( my ( $tab_type, $tab_label ) = each %$tab_header ) {
        print "  <li><a href=\"#tabs-$tab_counter\">$tab_label</a></li>\n";
        $tab_counter++;
      }
    }

    print "</ul>\n";
  }

  sub print_tab_content_custom {
    my ( $tab_number, $host_url, $server_url, $lpar_url, $item, $entitle, $detail_yes ) = @_;

    my $lpar_url_dec = $lpar_url;
    $lpar_url_dec =~ s/%([a-fA-F0-9][a-fA-F0-9])/pack("C", hex($1))/seg;
    my $notice_file  = "$tmpdir/.custom-group-$lpar_url_dec-n.cmd";
    my @final_notice = "";
    if ( -f $notice_file ) {
      open( FH, "$notice_file" ) || error( "Cannot open $notice_file: $!" . __FILE__ . ":" . __LINE__ ) && return 0;
      @final_notice = <FH>;
      close(FH);
    }

    print "<div id=\"tabs-$tab_number\">\n";
    print "<table border=\"0\">\n";
    print "<tr>";

    print_item( $host_url, $server_url, $lpar_url, $item, "d", $type_sam, $entitle, $detail_yes, "norefr", "star", 1, "nolegend" );
    print_item( $host_url, $server_url, $lpar_url, $item, "w", $type_sam, $entitle, $detail_yes, "norefr", "star", 1, "nolegend" );
    print "</tr>\n<tr>\n";
    print_item( $host_url, $server_url, $lpar_url, $item, "m", $type_sam,      $entitle, $detail_yes, "norefr", "star", 1, "nolegend" );
    print_item( $host_url, $server_url, $lpar_url, $item, "y", $type_sam_year, $entitle, $detail_yes, "norefr", "star", 1, "nolegend" );
    print "<tr><td align=\"center\" colspan=\"2\">@final_notice </td></tr>\n";

    # TODO year trend
    #print "</tr><tr>\n";
    #print_item( $host_url, $server_url, $lpar_url, "custom_cpu_trend", "y", $type_sam_year, $entitle, $detail_no, "norefr", "nostar", 2, "legend" );
    print "</tr></table>\n";
    print "</div>\n";
  }

  my @ovirt_items = (
    "custom_ovirt_vm_cpu_core",    "custom_ovirt_vm_cpu_percent",
    "custom_ovirt_vm_memory_used", "custom_ovirt_vm_memory_free"
  );

  # my @ovirt_items = ( "custom-ovirtvm-cpu-percent", "custom-ovirtvm-cpu-core", "custom-ovirtvm-memory-used",
  #                   "custom-ovirtvm-memory-free", "custom-ovirtvm-lan", "custom-ovirtvm-latency",
  #                   "custom-ovirtvm-data" );
  for $tab_number ( 1 .. $#ovirt_items + 1 ) {
    print_tab_content_custom( $tab_number, $host_url, $server_url, $lpar_url, $ovirt_items[ $tab_number - 1 ], $entitle, $detail_yes );
  }

  # end page contents
  print "</div><br>\n";
  print "</CENTER>\n";
}

# Custom groups for Solaris Zone (SOLARISZONE)
sub print_custom_solaris {
  my ( $host_url, $server_url, $lpar_url, $item, $entitle ) = @_;

  # print page contents
  print "<CENTER>";
  print "<div id=\"tabs\">\n";

  # get tabs
  my @tabs = (
    { cpu_used   => "CPU cores" },
    { phy_mem_us => "MEM used" },
  );

  if (@tabs) {
    print "<ul>\n";

    my $tab_counter = 1;
    foreach my $tab_header (@tabs) {
      while ( my ( $tab_type, $tab_label ) = each %$tab_header ) {
        print "  <li><a href=\"#tabs-$tab_counter\">$tab_label</a></li>\n";
        $tab_counter++;
      }
    }

    print "</ul>\n";
  }

  sub print_tab_content_custom_sol {
    my ( $tab_number, $host_url, $server_url, $lpar_url, $item, $entitle, $detail_yes ) = @_;

    my $lpar_url_dec = $lpar_url;
    $lpar_url_dec =~ s/%([a-fA-F0-9][a-fA-F0-9])/pack("C", hex($1))/seg;
    my $notice_file  = "$tmpdir/.custom-group-$lpar_url_dec-n.cmd";
    my @final_notice = "";
    if ( -f $notice_file ) {
      open( FH, "$notice_file" ) || error( "Cannot open $notice_file: $!" . __FILE__ . ":" . __LINE__ ) && return 0;
      @final_notice = <FH>;
      close(FH);
    }

    print "<div id=\"tabs-$tab_number\">\n";
    print "<table border=\"0\">\n";
    print "<tr>";

    print_item( $host_url, $server_url, $lpar_url, $item, "d", $type_sam, $entitle, $detail_yes, "norefr", "star", 1, "nolegend" );
    print_item( $host_url, $server_url, $lpar_url, $item, "w", $type_sam, $entitle, $detail_yes, "norefr", "star", 1, "nolegend" );
    print "</tr>\n<tr>\n";
    print_item( $host_url, $server_url, $lpar_url, $item, "m", $type_sam,      $entitle, $detail_yes, "norefr", "star", 1, "nolegend" );
    print_item( $host_url, $server_url, $lpar_url, $item, "y", $type_sam_year, $entitle, $detail_yes, "norefr", "star", 1, "nolegend" );
    print "<tr><td align=\"center\" colspan=\"2\">@final_notice </td></tr>\n";

    # TODO year trend
    #print "</tr><tr>\n";
    #print_item( $host_url, $server_url, $lpar_url, "custom_cpu_trend", "y", $type_sam_year, $entitle, $detail_no, "norefr", "nostar", 2, "legend" );
    print "</tr></table>\n";
    print "</div>\n";
  }

  my @solaris_items = ( "custom_solaris_cpu", "custom_solaris_mem" );
  for $tab_number ( 1 .. $#solaris_items + 1 ) {
    print_tab_content_custom_sol( $tab_number, $host_url, $server_url, $lpar_url, $solaris_items[ $tab_number - 1 ], $entitle, $detail_yes );
  }

  # end page contents
  print "</div><br>\n";
  print "</CENTER>\n";
}

# Custom groups for OracleVM (ORVM)
sub print_custom_orvm {
  my ( $host_url, $server_url, $lpar_url, $item, $entitle ) = @_;

  # print page contents
  print "<CENTER>";
  print "<div id=\"tabs\">\n";

  # get tabs
  #my @tabs = @{ XenServerMenu::get_tabs( 'vm' ) };
  my @tabs = (
    { cpu_cores   => "CPU" },
    { memory_used => "MEM Allocated" }
  );

  if (@tabs) {
    print "<ul>\n";

    my $tab_counter = 1;
    foreach my $tab_header (@tabs) {
      while ( my ( $tab_type, $tab_label ) = each %$tab_header ) {
        print "  <li><a href=\"#tabs-$tab_counter\">$tab_label</a></li>\n";
        $tab_counter++;
      }
    }

    print "</ul>\n";
  }

  sub print_tab_contents_custom_orvm {
    my ( $tab_number, $host_url, $server_url, $lpar_url, $item, $entitle, $detail_yes ) = @_;

    my $lpar_url_dec = $lpar_url;
    $lpar_url_dec =~ s/%([a-fA-F0-9][a-fA-F0-9])/pack("C", hex($1))/seg;
    my $notice_file  = "$tmpdir/.custom-group-$lpar_url_dec-n.cmd";
    my @final_notice = "";
    if ( -f $notice_file ) {
      open( FH, "$notice_file" ) || error( "Cannot open $notice_file: $!" . __FILE__ . ":" . __LINE__ ) && return 0;
      @final_notice = <FH>;
      close(FH);
    }

    print "<div id=\"tabs-$tab_number\">\n";
    print "<table border=\"0\">\n";
    print "<tr>";

    print_item( $host_url, $server_url, $lpar_url, $item, "d", $type_sam, $entitle, $detail_yes, "norefr", "star", 1, "nolegend" );
    print_item( $host_url, $server_url, $lpar_url, $item, "w", $type_sam, $entitle, $detail_yes, "norefr", "star", 1, "nolegend" );
    print "</tr>\n<tr>\n";
    print_item( $host_url, $server_url, $lpar_url, $item, "m", $type_sam,      $entitle, $detail_yes, "norefr", "star", 1, "nolegend" );
    print_item( $host_url, $server_url, $lpar_url, $item, "y", $type_sam_year, $entitle, $detail_yes, "norefr", "star", 1, "nolegend" );
    print "<tr><td align=\"center\" colspan=\"2\">@final_notice </td></tr>\n";

    # TODO year trend
    #print "</tr><tr>\n";
    #print_item( $host_url, $server_url, $lpar_url, "custom_cpu_trend", "y", $type_sam_year, $entitle, $detail_no, "norefr", "nostar", 2, "legend" );
    print "</tr></table>\n";
    print "</div>\n";
  }

  my @orvm_items = ( "custom_orvm_vm_cpu", "custom_orvm_vm_mem" );
  for $tab_number ( 1 .. $#orvm_items + 1 ) {
    print_tab_contents_custom_orvm( $tab_number, $host_url, $server_url, $lpar_url, $orvm_items[ $tab_number - 1 ], $entitle, $detail_yes );
  }

  # end page contents
  print "</div><br>\n";
  print "</CENTER>\n";
}

# Custom groups for Hyperv
sub print_custom_hyperv {
  my ( $host_url, $server_url, $lpar_url, $item, $entitle ) = @_;

  # print page contents
  print "<CENTER>";
  print "<div id=\"tabs\">\n";

  # get tabs
  my @tabs = (
    { cpu_used => "CPU cores" },
  );

  if (@tabs) {
    print "<ul>\n";

    my $tab_counter = 1;
    foreach my $tab_header (@tabs) {
      while ( my ( $tab_type, $tab_label ) = each %$tab_header ) {
        print "  <li><a href=\"#tabs-$tab_counter\">$tab_label</a></li>\n";
        $tab_counter++;
      }
    }

    print "</ul>\n";
  }

  sub print_tab_content_custom_hyperv {
    my ( $tab_number, $host_url, $server_url, $lpar_url, $item, $entitle, $detail_yes ) = @_;

    my $lpar_url_dec = $lpar_url;
    $lpar_url_dec =~ s/%([a-fA-F0-9][a-fA-F0-9])/pack("C", hex($1))/seg;
    my $notice_file  = "$tmpdir/.custom-group-$lpar_url_dec-n.cmd";
    my @final_notice = "";
    if ( -f $notice_file ) {
      open( FH, "$notice_file" ) || error( "Cannot open $notice_file: $!" . __FILE__ . ":" . __LINE__ ) && return 0;
      @final_notice = <FH>;
      close(FH);
    }

    print "<div id=\"tabs-$tab_number\">\n";
    print "<table border=\"0\">\n";
    print "<tr>";

    print_item( $host_url, $server_url, $lpar_url, $item, "d", $type_sam, $entitle, $detail_yes, "norefr", "star", 1, "nolegend" );
    print_item( $host_url, $server_url, $lpar_url, $item, "w", $type_sam, $entitle, $detail_yes, "norefr", "star", 1, "nolegend" );
    print "</tr>\n<tr>\n";
    print_item( $host_url, $server_url, $lpar_url, $item, "m", $type_sam,      $entitle, $detail_yes, "norefr", "star", 1, "nolegend" );
    print_item( $host_url, $server_url, $lpar_url, $item, "y", $type_sam_year, $entitle, $detail_yes, "norefr", "star", 1, "nolegend" );
    print "<tr><td align=\"center\" colspan=\"2\">@final_notice </td></tr>\n";

    # TODO year trend
    #print "</tr><tr>\n";
    #print_item( $host_url, $server_url, $lpar_url, "custom_cpu_trend", "y", $type_sam_year, $entitle, $detail_no, "norefr", "nostar", 2, "legend" );
    print "</tr></table>\n";
    print "</div>\n";
  }

  my @tab_items = ("custom_hyperv_cpu");
  for $tab_number ( 1 .. $#tab_items + 1 ) {
    print_tab_content_custom_hyperv( $tab_number, $host_url, $server_url, $lpar_url, $tab_items[ $tab_number - 1 ], $entitle, $detail_yes );
  }

  # end page contents
  print "</div><br>\n";
  print "</CENTER>\n";
}

# Custom groups for ESXI
sub print_custom_esxi {
  my ( $host_url, $server_url, $lpar_url, $item, $entitle ) = @_;

  $params{d_platform} = "VMware";

  # print page contents
  print "<CENTER>";
  print "<div id=\"tabs\">\n";

  # get tabs
  my @tabs = (
    { cpu_used => "CPU cores" },
  );

  if (@tabs) {
    print "<ul>\n";

    my $tab_counter = 1;
    foreach my $tab_header (@tabs) {
      while ( my ( $tab_type, $tab_label ) = each %$tab_header ) {
        print "  <li><a href=\"#tabs-$tab_counter\">$tab_label</a></li>\n";
        $tab_counter++;
      }
    }

    print "</ul>\n";
  }

  sub print_tab_content_custom_esxi {
    my ( $tab_number, $host_url, $server_url, $lpar_url, $item, $entitle, $detail_yes ) = @_;

    my $lpar_url_dec = $lpar_url;
    $lpar_url_dec =~ s/%([a-fA-F0-9][a-fA-F0-9])/pack("C", hex($1))/seg;
    my $notice_file  = "$tmpdir/.custom-group-$lpar_url_dec-n.cmd";
    my @final_notice = "";
    if ( -f $notice_file ) {
      open( FH, "$notice_file" ) || error( "Cannot open $notice_file: $!" . __FILE__ . ":" . __LINE__ ) && return 0;
      @final_notice = <FH>;
      close(FH);
    }

    print "<div id=\"tabs-$tab_number\">\n";
    print "<table border=\"0\">\n";
    print "<tr>";

    print_item( $host_url, $server_url, $lpar_url, $item, "d", $type_sam, $entitle, $detail_yes, "norefr", "star", 1, "nolegend" );
    print_item( $host_url, $server_url, $lpar_url, $item, "w", $type_sam, $entitle, $detail_yes, "norefr", "star", 1, "nolegend" );
    print "</tr>\n<tr>\n";
    print_item( $host_url, $server_url, $lpar_url, $item, "m", $type_sam,      $entitle, $detail_yes, "norefr", "star", 1, "nolegend" );
    print_item( $host_url, $server_url, $lpar_url, $item, "y", $type_sam_year, $entitle, $detail_yes, "norefr", "star", 1, "nolegend" );
    print "<tr><td align=\"center\" colspan=\"2\">@final_notice </td></tr>\n";

    # TODO year trend
    #print "</tr><tr>\n";
    #print_item( $host_url, $server_url, $lpar_url, "custom_cpu_trend", "y", $type_sam_year, $entitle, $detail_no, "norefr", "nostar", 2, "legend" );
    print "</tr></table>\n";
    print "</div>\n";
  }

  my @tab_items = ("custom_esxi_cpu");
  for $tab_number ( 1 .. $#tab_items + 1 ) {
    print_tab_content_custom_esxi( $tab_number, $host_url, $server_url, $lpar_url, $tab_items[ $tab_number - 1 ], $entitle, $detail_yes );
  }

  # end page contents
  print "</div><br>\n";
  print "</CENTER>\n";
}

# Custom groups for Linux
sub print_custom_linux {
  my ( $host_url, $server_url, $lpar_url, $item, $entitle ) = @_;

  $lpar_url =~ s/%([a-fA-F0-9][a-fA-F0-9])/pack("C", hex($1))/seg;
  my $list        = "$webdir/custom/$lpar_url/list.txt";
  my $tmp_cmd     = "$tmpdir/custom-group-mem-$lpar_url-d.cmd";
  my $notice_file = "$tmpdir/.custom-group-$lpar_url-n.cmd";

  open( FH, " < $list" ) || error( "Cannot open $list: $!" . __FILE__ . ":" . __LINE__ ) && return 0;
  my @list_rrd = <FH>;
  close FH;
  my @final_notice = "";
  if ( -f $notice_file ) {
    open( FH, "$notice_file" ) || error( "Cannot open $notice_file: $!" . __FILE__ . ":" . __LINE__ ) && return 0;
    @final_notice = <FH>;
    close(FH);
  }
  my @choice;

  print "<div  id=\"tabs\">\n";
  print "<ul>\n";

  print "  <li class=\"tabhmc\"><a href=\"#tabs-1\">CPU</a></li>\n";

  # print STDERR "6500 detail-cgi.pl $host_url, $server_url, $lpar_url, $item, $entitle, \@list_rrd @list_rrd\n";

  @choice = grep /\/mem\.mmm$/, @list_rrd;
  if ( scalar @choice > 0 ) {
    print "  <li class=\"tabagent\"><a href=\"#tabs-2\">MEM</a></li>\n";
  }
  @choice = grep /\/lan-.*\.mmm$/, @list_rrd;
  if ( scalar @choice > 0 ) {
    print "  <li class=\"tabagent\"><a href=\"#tabs-3\">LAN</a></li>\n";
  }
  @choice = grep /\/san-.*\.mmm$/, @list_rrd;
  if ( scalar @choice > 0 ) {
    print "  <li class=\"tabagent\"><a href=\"#tabs-4\">SAN</a></li>\n";

    # @choice = grep /\/san-host.*\.mmm$/, @list_rrd;
    #if ( scalar @choice > 0 ) {

    #  # Linux agent reports frames instead of IOPS
    #  print "  <li class=\"tabagent\"><a href=\"#tabs-6\">Frames</a></li>\n";
    #}
    #else {
    #  print "  <li class=\"tabagent\"><a href=\"#tabs-6\">IOPS</a></li>\n";
    #}
  }

  print "</ul>\n";

  #custom groups CPU
  print "<CENTER>";
  print "<div id=\"tabs-1\">\n";
  print "<table border=\"0\">\n";
  print "<tr>";

  $type_sam = "na";
  $item     = "custom_linux_cpu";
  print_item( $host_url, $server_url, $lpar_url, $item, "d", $type_sam, $entitle, $detail_yes, "norefr", "star", 1, "nolegend" );
  print_item( $host_url, $server_url, $lpar_url, $item, "w", $type_sam, $entitle, $detail_yes, "norefr", "star", 1, "nolegend" );
  print "</tr>\n<tr>\n";
  print_item( $host_url, $server_url, $lpar_url, $item, "m", $type_sam,      $entitle, $detail_yes, "norefr", "star", 1, "nolegend" );
  print_item( $host_url, $server_url, $lpar_url, $item, "y", $type_sam_year, $entitle, $detail_yes, "norefr", "star", 1, "nolegend" );
  print "</tr>\n";
  print "<tr><td align=\"center\" colspan=\"2\">@final_notice </td></tr>\n";

  #print "<tr>\n";
  #print_item( $host_url, $server_url, $lpar_url, "custom_cpu_trend", "y", $type_sam_year, $entitle, $detail_yes, "norefr", "nostar", 2, "legend" );
  #print "</tr>\N";
  print "</table>\n";

  # print_custom_lpar_details(@list_rrd);

  print "</div>\n";

  @choice = grep /\/mem\.mmm$/, @list_rrd;
  if ( scalar @choice > 0 ) {

    #custom groups OS MEM
    print "<div id=\"tabs-2\">\n";
    print "<table border=\"0\">\n";
    print "<tr>";

    $type_sam = "na";
    $item     = "custom_linux_mem";
    print_item( $host_url, $server_url, $lpar_url, $item, "d", $type_sam, $entitle, $detail_yes, "norefr", "star", 1, "nolegend" );
    print_item( $host_url, $server_url, $lpar_url, $item, "w", $type_sam, $entitle, $detail_yes, "norefr", "star", 1, "nolegend" );
    print "</tr>\n<tr>\n";
    print_item( $host_url, $server_url, $lpar_url, $item, "m", $type_sam,      $entitle, $detail_yes, "norefr", "star", 1, "nolegend" );
    print_item( $host_url, $server_url, $lpar_url, $item, "y", $type_sam_year, $entitle, $detail_yes, "norefr", "star", 1, "nolegend" );
    print "</tr></table>@final_notice";

    #print_custom_lpar_details(@list_rrd);
    print "</div>\n";
  }

  @choice = grep /\/lan-.*\.mmm$/, @list_rrd;
  if ( scalar @choice > 0 ) {

    #custom groups OS LAN
    print "<div id=\"tabs-3\">\n";
    print "<table border=\"0\">\n";
    print "<tr>";

    $type_sam = "na";
    $item     = "custom_linux_lan";
    print_item( $host_url, $server_url, $lpar_url, $item, "d", $type_sam, $entitle, $detail_yes, "norefr", "star", 1, "nolegend" );
    print_item( $host_url, $server_url, $lpar_url, $item, "w", $type_sam, $entitle, $detail_yes, "norefr", "star", 1, "nolegend" );
    print "</tr>\n<tr>\n";
    print_item( $host_url, $server_url, $lpar_url, $item, "m", $type_sam,      $entitle, $detail_yes, "norefr", "star", 1, "nolegend" );
    print_item( $host_url, $server_url, $lpar_url, $item, "y", $type_sam_year, $entitle, $detail_yes, "norefr", "star", 1, "nolegend" );
    print "</tr></table>@final_notice";

    # print_custom_lpar_details(@list_rrd);
    print "</div>\n";
  }

  @choice = grep /\/san-.*\.mmm$/, @list_rrd;
  if ( scalar @choice > 0 ) {

    #custom groups OS SAN1
    print "<div id=\"tabs-4\">\n";
    print "<table border=\"0\">\n";
    print "<tr>";

    $type_sam = "na";
    $item     = "custom_linux_san1";
    print_item( $host_url, $server_url, $lpar_url, $item, "d", $type_sam, $entitle, $detail_yes, "norefr", "star", 1, "nolegend" );
    print_item( $host_url, $server_url, $lpar_url, $item, "w", $type_sam, $entitle, $detail_yes, "norefr", "star", 1, "nolegend" );
    print "</tr>\n<tr>\n";
    print_item( $host_url, $server_url, $lpar_url, $item, "m", $type_sam,      $entitle, $detail_yes, "norefr", "star", 1, "nolegend" );
    print_item( $host_url, $server_url, $lpar_url, $item, "y", $type_sam_year, $entitle, $detail_yes, "norefr", "star", 1, "nolegend" );
    print "</tr></table>@final_notice";

    # print_custom_lpar_details(@list_rrd);
    print "</div>\n";

    #custom groups OS SAN2 IOPS
    #print "<div id=\"tabs-6\">\n";
    #print "<table border=\"0\">\n";
    #print "<tr>";

    #$type_sam = "na";
    #$item     = "customossan2";
    #print_item( $host_url, $server_url, $lpar_url, $item, "d", $type_sam, $entitle, $detail_yes, "norefr", "star", 1, "nolegend" );
    #print_item( $host_url, $server_url, $lpar_url, $item, "w", $type_sam, $entitle, $detail_yes, "norefr", "star", 1, "nolegend" );
    #print "</tr>\n<tr>\n";
    #print_item( $host_url, $server_url, $lpar_url, $item, "m", $type_sam,      $entitle, $detail_yes, "norefr", "star", 1, "nolegend" );
    #print_item( $host_url, $server_url, $lpar_url, $item, "y", $type_sam_year, $entitle, $detail_yes, "norefr", "star", 1, "nolegend" );
    #print "</tr></table>@final_notice";
    #print_custom_lpar_details(@list_rrd);
    #print "</div>\n";
  }

  print "</div><br>\n";

  return 1;
}

sub print_custom_oracledb {
  my ( $host_url, $server_url, $lpar_url, $item, $entitle ) = @_;

  # print page contents
  print "<CENTER>";
  print "<div id=\"tabs\">\n";

  # get tabs
  my @tabs = (
    { _CPU_Usage_Per_Sec => "CPU Core/Host" },
    { _CPU_Usage_Per_Sec => "CPU Core/DB" },

    #              { memory_used => "MEM used" },
    #              { memory_free => "MEM free" },
    #              { storage => "Data" },
    #              { iops => "IOPS" },
    #              { latency => "Latency" },
    #              { net => "Net" }
  );

  if (@tabs) {
    print "<ul>\n";

    my $tab_counter = 1;
    foreach my $tab_header (@tabs) {
      while ( my ( $tab_type, $tab_label ) = each %$tab_header ) {
        print "  <li><a href=\"#tabs-$tab_counter\">$tab_label</a></li>\n";
        $tab_counter++;
      }
    }

    print "</ul>\n";
  }

  sub print_tab_contents_custom_oracledb {
    my ( $tab_number, $host_url, $server_url, $lpar_url, $item, $entitle, $detail_yes ) = @_;

    my $lpar_url_dec = $lpar_url;
    $lpar_url_dec =~ s/%([a-fA-F0-9][a-fA-F0-9])/pack("C", hex($1))/seg;
    my $notice_file  = "$tmpdir/.custom-group-$lpar_url_dec-n.cmd";
    my @final_notice = "";
    if ( -f $notice_file ) {
      open( FH, "$notice_file" ) || error( "Cannot open $notice_file: $!" . __FILE__ . ":" . __LINE__ ) && return 0;
      @final_notice = <FH>;
      close(FH);
    }

    print "<div id=\"tabs-$tab_number\">\n";
    print "<table border=\"0\">\n";
    print "<tr>";

    print_item( $host_url, $server_url, $lpar_url, $item, "d", $type_sam, $entitle, $detail_yes, "norefr", "star", 1, "nolegend" );
    print_item( $host_url, $server_url, $lpar_url, $item, "w", $type_sam, $entitle, $detail_yes, "norefr", "star", 1, "nolegend" );
    print "</tr>\n<tr>\n";
    print_item( $host_url, $server_url, $lpar_url, $item, "m", $type_sam,      $entitle, $detail_yes, "norefr", "star", 1, "nolegend" );
    print_item( $host_url, $server_url, $lpar_url, $item, "y", $type_sam_year, $entitle, $detail_yes, "norefr", "star", 1, "nolegend" );
    print "<tr><td align=\"center\" colspan=\"2\">@final_notice </td></tr>\n";

    # TODO year trend
    #print "</tr><tr>\n";
    #print_item( $host_url, $server_url, $lpar_url, "custom_cpu_trend", "y", $type_sam_year, $entitle, $detail_no, "norefr", "nostar", 2, "legend" );
    print "</tr></table>\n";
    print "</div>\n";
  }

  my @oracledb_items = ( "oracledb_configuration_Total__CPU_Usage_Per_Sec_Total", "oracledb_configuration_DBTotal__CPU_Usage_Per_Sec_DBTotal" );
  for $tab_number ( 1 .. $#oracledb_items + 1 ) {
    print_tab_contents_custom_oracledb( $tab_number, "groups__$lpar_url", "custom", "configuration_Total", $oracledb_items[ $tab_number - 1 ], $entitle, $detail_yes );

    #print_tab_contents_custom_oracledb( $tab_number, $host_url, $server_url, $lpar_url, $oracledb_items[$tab_number - 1], $entitle, $detail_yes);
  }

  # end page contents
  print "</div><br>\n";
  print "</CENTER>\n";
}

# Custom groups for Power and VMware
sub print_custom {
  my ( $host_url, $server_url, $lpar_url, $item, $entitle ) = @_;

  $lpar_url =~ s/%([a-fA-F0-9][a-fA-F0-9])/pack("C", hex($1))/seg;
  my $list        = "$webdir/custom/$lpar_url/list.txt";
  my $tmp_cmd     = "$tmpdir/custom-group-mem-$lpar_url-d.cmd";
  my $notice_file = "$tmpdir/.custom-group-$lpar_url-n.cmd";

  open( FH, " < $list" ) || error( "Cannot open $list: $!" . __FILE__ . ":" . __LINE__ ) && return 0;
  my @list_rrd = <FH>;
  close FH;
  my @final_notice = "";
  if ( -f $notice_file ) {
    open( FH, "$notice_file" ) || error( "Cannot open $notice_file: $!" . __FILE__ . ":" . __LINE__ ) && return 0;
    @final_notice = <FH>;
    close(FH);
  }
  my @choice;

  print "<div  id=\"tabs\">\n";
  print "<ul>\n";
  print "  <li class=\"tabhmc\"><a href=\"#tabs-1\">CPU</a></li>\n";
  @choice = grep /\.rsm$/, @list_rrd;
  if ( ( scalar @choice > 0 ) || ( -f $tmp_cmd ) ) {

    #  if (scalar (grep /\.rsm$/, @list_rrd) >0) left_curly
    print "  <li class=\"tabhmc\"><a href=\"#tabs-2\">MEM allocated</a></li>\n";
  }
  @choice = grep /\/mem\.mmm$/, @list_rrd;
  if ( scalar @choice > 0 ) {
    print "  <li class=\"tabagent\"><a href=\"#tabs-3\">MEM</a></li>\n";
  }
  @choice = grep /\/lan-.*\.mmm$/, @list_rrd;
  if ( scalar @choice > 0 ) {
    print "  <li class=\"tabagent\"><a href=\"#tabs-4\">LAN</a></li>\n";
  }
  @choice = grep /\/san-.*\.mmm$/, @list_rrd;
  if ( scalar @choice > 0 ) {
    print "  <li class=\"tabagent\"><a href=\"#tabs-5\">SAN</a></li>\n";
    @choice = grep /\/san-host.*\.mmm$/, @list_rrd;
    if ( scalar @choice > 0 ) {

      # Linux agent reports frames instead of IOPS
      print "  <li class=\"tabagent\"><a href=\"#tabs-6\">Frames</a></li>\n";
    }
    else {
      print "  <li class=\"tabagent\"><a href=\"#tabs-6\">IOPS</a></li>\n";
    }
  }

  # VMWare custom group
  # CPU is above
  if ( index( $list_rrd[0], "vmware_VMs" ) > -1 ) {

    $params{d_platform} = "VMware";

    print "  <li class=\"tabhmc\"><a href=\"#tabs-2\">MEM Active</a></li>\n";

    print "  <li class=\"tabhmc\"><a href=\"#tabs-3\">MEM Granted</a></li>\n";

    print "  <li class=\"tabhmc\"><a href=\"#tabs-4\">DISK</a></li>\n";

    print "  <li class=\"tabhmc\"><a href=\"#tabs-5\">LAN</a></li>\n";
  }
  print "</ul>\n";

  #custom groups CPU
  print "<CENTER>";
  print "<div id=\"tabs-1\">\n";
  print "<table border=\"0\">\n";
  print "<tr>";

  $type_sam = "na";
  $item     = "custom";
  print_item( $host_url, $server_url, $lpar_url, $item, "d", $type_sam, $entitle, $detail_yes, "norefr", "star", 1, "nolegend" );
  print_item( $host_url, $server_url, $lpar_url, $item, "w", $type_sam, $entitle, $detail_yes, "norefr", "star", 1, "nolegend" );
  print "</tr>\n<tr>\n";
  print_item( $host_url, $server_url, $lpar_url, $item, "m", $type_sam,      $entitle, $detail_yes, "norefr", "star", 1, "nolegend" );
  print_item( $host_url, $server_url, $lpar_url, $item, "y", $type_sam_year, $entitle, $detail_yes, "norefr", "star", 1, "nolegend" );
  print "</tr>\n";
  print "<tr><td align=\"center\" colspan=\"2\">@final_notice </td></tr>\n";
  print "<tr>\n";
  print_item( $host_url, $server_url, $lpar_url, "custom_cpu_trend", "y", $type_sam_year, $entitle, $detail_yes, "norefr", "nostar", 2, "legend" );
  print "</tr></table>\n";

  #print STDERR "@list_rrd\n";
  print_custom_lpar_details(@list_rrd);

  print "</div>\n";

  @choice = grep /\.rsm$/, @list_rrd;
  if ( ( scalar @choice > 0 ) || ( -f $tmp_cmd ) ) {

    #custom groups MEM
    print "<div id=\"tabs-2\">\n";
    print "<table border=\"0\">\n";
    print "<tr>";

    $type_sam = "na";
    $item     = "custommem";
    print_item( $host_url, $server_url, $lpar_url, $item, "d", $type_sam, $entitle, $detail_yes, "norefr", "star", 1, "nolegend" );
    print_item( $host_url, $server_url, $lpar_url, $item, "w", $type_sam, $entitle, $detail_yes, "norefr", "star", 1, "nolegend" );
    print "</tr>\n<tr>\n";
    print_item( $host_url, $server_url, $lpar_url, $item, "m", $type_sam,      $entitle, $detail_yes, "norefr", "star", 1, "nolegend" );
    print_item( $host_url, $server_url, $lpar_url, $item, "y", $type_sam_year, $entitle, $detail_yes, "norefr", "star", 1, "nolegend" );
    print "</tr></table>@final_notice";
    print_custom_lpar_details(@list_rrd);
    print "</div>\n";
  }

  @choice = grep /\/mem\.mmm$/, @list_rrd;
  if ( scalar @choice > 0 ) {

    #custom groups OS MEM
    print "<div id=\"tabs-3\">\n";
    print "<table border=\"0\">\n";
    print "<tr>";

    $type_sam = "na";
    $item     = "customosmem";
    print_item( $host_url, $server_url, $lpar_url, $item, "d", $type_sam, $entitle, $detail_yes, "norefr", "star", 1, "nolegend" );
    print_item( $host_url, $server_url, $lpar_url, $item, "w", $type_sam, $entitle, $detail_yes, "norefr", "star", 1, "nolegend" );
    print "</tr>\n<tr>\n";
    print_item( $host_url, $server_url, $lpar_url, $item, "m", $type_sam,      $entitle, $detail_yes, "norefr", "star", 1, "nolegend" );
    print_item( $host_url, $server_url, $lpar_url, $item, "y", $type_sam_year, $entitle, $detail_yes, "norefr", "star", 1, "nolegend" );
    print "</tr></table>@final_notice";
    print_custom_lpar_details(@list_rrd);
    print "</div>\n";
  }

  @choice = grep /\/lan-.*\.mmm$/, @list_rrd;
  if ( scalar @choice > 0 ) {

    #custom groups OS LAN
    print "<div id=\"tabs-4\">\n";
    print "<table border=\"0\">\n";
    print "<tr>";

    $type_sam = "na";
    $item     = "customoslan";
    print_item( $host_url, $server_url, $lpar_url, $item, "d", $type_sam, $entitle, $detail_yes, "norefr", "star", 1, "nolegend" );
    print_item( $host_url, $server_url, $lpar_url, $item, "w", $type_sam, $entitle, $detail_yes, "norefr", "star", 1, "nolegend" );
    print "</tr>\n<tr>\n";
    print_item( $host_url, $server_url, $lpar_url, $item, "m", $type_sam,      $entitle, $detail_yes, "norefr", "star", 1, "nolegend" );
    print_item( $host_url, $server_url, $lpar_url, $item, "y", $type_sam_year, $entitle, $detail_yes, "norefr", "star", 1, "nolegend" );
    print "</tr></table>@final_notice";
    print_custom_lpar_details(@list_rrd);
    print "</div>\n";
  }

  @choice = grep /\/san-.*\.mmm$/, @list_rrd;
  if ( scalar @choice > 0 ) {

    #custom groups OS SAN1
    print "<div id=\"tabs-5\">\n";
    print "<table border=\"0\">\n";
    print "<tr>";

    $type_sam = "na";
    $item     = "customossan1";
    print_item( $host_url, $server_url, $lpar_url, $item, "d", $type_sam, $entitle, $detail_yes, "norefr", "star", 1, "nolegend" );
    print_item( $host_url, $server_url, $lpar_url, $item, "w", $type_sam, $entitle, $detail_yes, "norefr", "star", 1, "nolegend" );
    print "</tr>\n<tr>\n";
    print_item( $host_url, $server_url, $lpar_url, $item, "m", $type_sam,      $entitle, $detail_yes, "norefr", "star", 1, "nolegend" );
    print_item( $host_url, $server_url, $lpar_url, $item, "y", $type_sam_year, $entitle, $detail_yes, "norefr", "star", 1, "nolegend" );
    print "</tr></table>@final_notice";
    print_custom_lpar_details(@list_rrd);
    print "</div>\n";

    #custom groups OS SAN2 IOPS
    print "<div id=\"tabs-6\">\n";
    print "<table border=\"0\">\n";
    print "<tr>";

    $type_sam = "na";
    $item     = "customossan2";
    print_item( $host_url, $server_url, $lpar_url, $item, "d", $type_sam, $entitle, $detail_yes, "norefr", "star", 1, "nolegend" );
    print_item( $host_url, $server_url, $lpar_url, $item, "w", $type_sam, $entitle, $detail_yes, "norefr", "star", 1, "nolegend" );
    print "</tr>\n<tr>\n";
    print_item( $host_url, $server_url, $lpar_url, $item, "m", $type_sam,      $entitle, $detail_yes, "norefr", "star", 1, "nolegend" );
    print_item( $host_url, $server_url, $lpar_url, $item, "y", $type_sam_year, $entitle, $detail_yes, "norefr", "star", 1, "nolegend" );
    print "</tr></table>@final_notice";
    print_custom_lpar_details(@list_rrd);
    print "</div>\n";
  }

  # VMWare custom group
  # CPU is above
  if ( index( $list_rrd[0], "vmware_VMs" ) > -1 ) {

    #custom groups VMWare MEM Active
    print "<div id=\"tabs-2\">\n";
    print "<table border=\"0\">\n";
    print "<tr>";

    $type_sam = "na";
    $item     = "customvmmemactive";
    print_item( $host_url, $server_url, $lpar_url, $item, "d", $type_sam, $entitle, $detail_yes, "norefr", "star", 1, "nolegend" );
    print_item( $host_url, $server_url, $lpar_url, $item, "w", $type_sam, $entitle, $detail_yes, "norefr", "star", 1, "nolegend" );
    print "</tr>\n<tr>\n";
    print_item( $host_url, $server_url, $lpar_url, $item, "m", $type_sam,      $entitle, $detail_yes, "norefr", "star", 1, "nolegend" );
    print_item( $host_url, $server_url, $lpar_url, $item, "y", $type_sam_year, $entitle, $detail_yes, "norefr", "star", 1, "nolegend" );
    print "</tr></table>@final_notice";
    print_custom_lpar_details(@list_rrd);
    print "</div>\n";

    #custom groups VMWare MEM Consumed
    print "<div id=\"tabs-3\">\n";
    print "<table border=\"0\">\n";
    print "<tr>";

    $type_sam = "na";
    $item     = "customvmmemconsumed";
    print_item( $host_url, $server_url, $lpar_url, $item, "d", $type_sam, $entitle, $detail_yes, "norefr", "star", 1, "nolegend" );
    print_item( $host_url, $server_url, $lpar_url, $item, "w", $type_sam, $entitle, $detail_yes, "norefr", "star", 1, "nolegend" );
    print "</tr>\n<tr>\n";
    print_item( $host_url, $server_url, $lpar_url, $item, "m", $type_sam,      $entitle, $detail_yes, "norefr", "star", 1, "nolegend" );
    print_item( $host_url, $server_url, $lpar_url, $item, "y", $type_sam_year, $entitle, $detail_yes, "norefr", "star", 1, "nolegend" );
    print "</tr></table>@final_notice";
    print_custom_lpar_details(@list_rrd);
    print "</div>\n";

    #custom groups VMWare DISK
    print "<div id=\"tabs-4\">\n";
    print "<table border=\"0\">\n";
    print "<tr>";

    $type_sam = "na";
    $item     = "customdisk";
    print_item( $host_url, $server_url, $lpar_url, $item, "d", $type_sam, $entitle, $detail_yes, "norefr", "star", 1, "nolegend" );
    print_item( $host_url, $server_url, $lpar_url, $item, "w", $type_sam, $entitle, $detail_yes, "norefr", "star", 1, "nolegend" );
    print "</tr>\n<tr>\n";
    print_item( $host_url, $server_url, $lpar_url, $item, "m", $type_sam,      $entitle, $detail_yes, "norefr", "star", 1, "nolegend" );
    print_item( $host_url, $server_url, $lpar_url, $item, "y", $type_sam_year, $entitle, $detail_yes, "norefr", "star", 1, "nolegend" );
    print "</tr></table>@final_notice";
    print_custom_lpar_details(@list_rrd);
    print "</div>\n";

    #custom groups VMWare LAN
    print "<div id=\"tabs-5\">\n";
    print "<table border=\"0\">\n";
    print "<tr>";

    $type_sam = "na";
    $item     = "customnet";
    print_item( $host_url, $server_url, $lpar_url, $item, "d", $type_sam, $entitle, $detail_yes, "norefr", "star", 1, "nolegend" );
    print_item( $host_url, $server_url, $lpar_url, $item, "w", $type_sam, $entitle, $detail_yes, "norefr", "star", 1, "nolegend" );
    print "</tr>\n<tr>\n";
    print_item( $host_url, $server_url, $lpar_url, $item, "m", $type_sam,      $entitle, $detail_yes, "norefr", "star", 1, "nolegend" );
    print_item( $host_url, $server_url, $lpar_url, $item, "y", $type_sam_year, $entitle, $detail_yes, "norefr", "star", 1, "nolegend" );
    print "</tr></table>@final_notice";
    print_custom_lpar_details(@list_rrd);
    print "</div>\n";
  }

  print "</div><br>\n";

  return 1;
}

sub print_view {
  my ( $host_url, $server_url, $lpar_url, $item_url, $entitle ) = @_;
  my $power = 0;

  my $hmc_list     = `\$PERL $basedir/bin/hmc_list.pl --all --no-test`;
  my $host_decoded = urldecode($host_url);
  if ( $hmc_list =~ m/$host_decoded/ ) {
    $power = 1;
  }

  #print "<pre> HMC_LIST :  $hmc_list, $host_decoded , POWER : $power</pre>\n";

  my $SERV;
  my $CONF;
  ( $SERV, $CONF ) = PowerDataWrapper::init() if ($power);
  my $width = "800px";

  print "<div  id=\"tabs\">\n";

  print "<ul>\n";
  print "  <li class=\"$tab_type\"><a href=\"#tabs-1\">Daily</a></li>\n";
  print "  <li class=\"$tab_type\"><a href=\"#tabs-2\">Weekly</a></li>\n";
  print "  <li class=\"$tab_type\"><a href=\"#tabs-3\">Monthly</a></li>\n";
  print "  <li class=\"$tab_type\"><a href=\"#tabs-4\">Yearly</a></li>\n";
  print "</ul>\n";
  print "<CENTER>";

=begin test
  #print "<pre>\n";
  #print Dumper $CONF;
  #print "</pre>\n";

  #configuration
  my $hmc_uid = PowerDataWrapper::get_item_uid( { type => "HMC", label => $host_url } );
  my $hmc_label = $host_url;
  my $server_uid = PowerDataWrapper::get_item_uid( { type => "SERVER", label => $server_url } );
  print "<h4>Configuration</h4>";
  print "<table class=\"tablesorter nofilter\" style=\"width:$width\">\n";
  print "<thead>\n";
  print "<tr>\n";
  print "  <th class='sortable'>Metric</th>\n";
  print "  <th class='sortable'>Value</th>\n";
  print "</tr>\n";
  print "</thead>\n";
  print "<tbody>\n";
  my $conf_metrics = {
    "SerialNumber" => "Serial Number",
    "ConfigurableSystemProcessorUnits" => "Configurable System Processor Units",
    "InstalledSystemProcessorUnits" => "Installed System Processor Units",
    "CurrentAvailableSystemProcessorUnits" => "Current Available System Processor Units",
    "ConfigurableSystemMemory" => "Configurable System Memory",
    "InstalledSystemMemory" => "Installed System Memory",
    "CurrentAvailableSystemMemory" => "Current Available System Memory",
    "MemoryUsedByHypervisor" => "Memory Used By Hypervisor"
  };

  foreach my $conf_metric (keys %{$conf_metrics}){
    print "<tr>\n";
    print   "<td align=\"center\"> $conf_metrics->{$conf_metric} </th>\n";
    if (defined $CONF->{servers}{$server_uid}{$conf_metric}){
      print   "<td align=\"center\"> $CONF->{servers}{$server_uid}{$conf_metric} </th>\n";
    } else {
      print   "<td align=\"center\"> not defined</th>\n";
    }
    print "</tr>\n";
}
  print "</tbody></table>";

  #performance
  print "<h4>Performance</h4>";

  print "<table class=\"tablesorter nofilter\" style=\"width:$width\">\n";
  print "<thead>\n";
  print "<tr>\n";
  #print "  <th rowspan='2' class='sortable'>Storage</th>\n";
  print "  <th rowspan='2' class='sortable'>$server</th>\n";
  print "  <th colspan='2' style='text-align:center'>CPU [Cores]</th>\n";
  print "  <th colspan='2' style='text-align:center'>Memory [GB]</th>\n";
  print "</tr>\n";
  print "<tr>\n";
  print "  <th class='sortable'>avg</th>\n";
  print "  <th class='sortable'>max</th>\n";
  print "  <th class='sortable'>avg</th>\n";
  print "  <th class='sortable'>max</th>\n";
  print "</tr>\n";
  print "</thead><tbody>\n";


  my @servers = @{ PowerDataWrapper::get_items("SERVER") };
  foreach my $server_hash (@servers){
    #print Dumper $server_hash;
    my $uid = (keys %{$server_hash})[0];
    my $server = $server_hash->{$uid};
    my $hmc_uid = PowerDataWrapper::get_server_parent($uid);
    my $hmc_label = PowerDataWrapper::get_label("HMC", $hmc_uid);
    my $rrd_file_path = "$basedir/data/$server/$hmc_label/";
    my $file_pth = "$basedir/data/$server/*/";

    my $params;
    $params->{eunix} = time;
    $params->{sunix} = $params->{eunix} - (86400*365);
    $params->{host} = urldecode($host_url);
    $params->{server} = urldecode($server_url);
    #$params->{lpar} = urldecode($lpar_url);
    #$params->{item} = urldecode($item_url);

    my @pool_data     = @{ Overview::get_something ($rrd_file_path, "pool",     $file_pth, "pool.rrm", $params) };
    my @pool_max_data = @{ Overview::get_something ($rrd_file_path, "pool-max", $file_pth, "pool.xrm", $params) };
    my @mem_data      = @{ Overview::get_something ($rrd_file_path, "mem",      $file_pth, "mem.rrm", $params) };
    my @mem_max_data  = @{ Overview::get_something ($rrd_file_path, "mem-max",  $file_pth, "mem.rrm", $params) };

    my $format_mem_avg = $mem_data[0];
    my $format_mem_max = $mem_max_data[0];

    print "<TR>
          <TD><B>$server</B></TD>
          <TD align=\"center\">$pool_data[0]</TD>
          <TD align=\"center\">$pool_max_data[0]</TD>
          <TD align=\"center\">$format_mem_avg GB</TD>
          <TD align=\"center\">$format_mem_max GB</TD>
        </TR>\n";
  }
  print "</tr></tbody></table>";
  #end performance
=cut

  my $inx = 0;
  foreach my $period ( 'd', 'w', 'm', 'y' ) {
    my $pict_count = 0;
    $inx++;
    print "<div id=\"tabs-$inx\">\n";
    print "<a class='pdffloat' href='/lpar2rrd-cgi/overview.sh?platform=power&source=$server_url&srctype=server&timerange=$period&format=pdf' title='PDF' style='position: fixed; top: 70px; right: 16px;'><img src='css/images/pdf.png'></a>" if ($power);

    print_power_overview_server( { 'host' => $host_url, 'server' => $server_url, 'lpar' => $lpar_url, 'item' => $item, 'entitle' => $entitle, 'i' => $inx } ) if ($power);

    print "<table border=\"0\">\n";

    print "<tr>";
    print_item( $host_url, $server_url, "pool_total", "pool-total",     $period, $type_sam, $entitle, $detail_yes, "norefr", "star", 1, "legend" ) if ($power);
    print_item( $host_url, $server_url, "pool_total", "pool-total-max", $period, $type_sam, $entitle, $detail_yes, "norefr", "star", 1, "legend" ) if ($power);
    print "</tr>\n";

    print "<tr>";
    print_item( $host_url, $server_url, "pool",    "pool",     $period, $type_sam, $entitle, $detail_yes, "norefr", "star", 1, "legend" );
    print_item( $host_url, $server_url, $lpar_url, "memalloc", $period, $type_sam, $entitle, $detail_yes, "norefr", "star", 1, "legend" );
    print "</tr>\n<tr>\n";
    print_item( $host_url, $server_url, "pool-multi", "lparagg",   $period, $type_sam, $entitle, $detail_yes, "norefr", "star", 1, "nolegend" );
    print_item( $host_url, $server_url, $lpar_url,    "memaggreg", $period, $type_sam, $entitle, $detail_yes, "norefr", "star", 1, "nolegend" );
    print "</tr>\n";

    #  test if AMS
    opendir( DIR, "$wrkdir/$server/$host" ) || error( " directory does not exists : $wrkdir/$server/$host" . __FILE__ . ":" . __LINE__ ) && return 0;
    my @files_not_sorted = grep( /.*\.rm.$/, readdir(DIR) );
    closedir(DIR);
    my $ams = @files_not_sorted;

    if ( $ams > 0 ) {
      print_item( $host_url, $server_url, $lpar_url, "memams", $period, $type_sam, $entitle, $detail_yes, "norefr", "star", 1, "nolegend" );
      $pict_count++;
    }

    # how many SharedPools
    opendir( DIR, "$wrkdir/$server/$host" ) || error( " directory does not exists : $wrkdir/$server_url/$host_url" . __FILE__ . ":" . __LINE__ ) && return 0;
    my @share_pools_not_sorted = grep( /SharedPool\d{1,2}\.rr[m,h]/, readdir(DIR) );
    closedir(DIR);
    my @share_pools = sort @share_pools_not_sorted;
    foreach my $sh_pool (@share_pools) {
      $sh_pool =~ s/\.rrm$//;
      $sh_pool =~ s/\.rrh$//;
      print_item( $host_url, $server_url, $sh_pool, "shpool", $period, $type_sam, $entitle, $detail_yes, "norefr", "star", 1, "legend" );
      $pict_count++;
      print "</tr>\n<tr>\n" if ( !( $pict_count % 2 ) );
    }

    # how many lpars
    # 1st try to use cpu.csv, if not then use cpu.html

    my $cpu_html = "$wrkdir/$server/$host/cpu.csv";
    my $lpars_ok = 0;
    my @cpu_array;
    if ( -f $cpu_html && $vmware ) {
      if ( open( FC, "< $cpu_html" ) ) {
        @cpu_array = <FC>;
        close(FC);
        my $item_view = "lpar";
        foreach my $lpar_line (@cpu_array) {
          my ( undef, $v_cpu, $reser_mhz, undef, $shares, $shares_value, $os, $power_state, $tools_status, undef, $vm_uuid, $memorySizeMB ) = split /,/, $lpar_line;
          chomp $vm_uuid;            # if old version table
          my $star      = "star";    # power lpars in view are dashboard-able
          my $lpar_name = "";

          # print STDERR "5115 \$lpar_line $lpar_line\n";
          if ($vmware) {
            if ( $lpar_line !~ "poweredOn" ) {next}
            $lpar_name = $vm_uuid;
            $star      = "nostar";    # vmware VMs in view are NOT dashboard-able
          }

          # here may come later hyperv

          $lpar_name =~ s/\//\&\&1/g;    # replace for "/"
          my $lpar_url = $lpar_name;

          $lpar_url =~ s/([^a-zA-Z0-9_.!~*()'\''-])/sprintf("%%%02X", ord($1))/ge;
          print_item( $host_url, $server_url, "$lpar_url", $item_view, $period, $type_sam, $entitle, $detail_yes, "norefr", "$star", 1, "legend" );
          $pict_count++;
          print "</tr>\n<tr>\n" if ( !( $pict_count % 2 ) );
          $lpars_ok = 1;
        }
      }
      else {
        error( "Cannot open $cpu_html: $!" . __FILE__ . ":" . __LINE__ );
      }

      # $cmd .= " COMMENT:\"   Memory Count     $mem_count_gb\"";
    }
    if ( !$lpars_ok ) {    # probably not cpu.csv
      $cpu_html = "$wrkdir/$server/$host/cpu.html";

      # print STDERR "3135 detail-cgi.pl ,$server_url,$lpar_url,$item,$type_sam, link $wrkdir/$server/$host/cpu.html\n";
      open( FH, " < $cpu_html" ) || error( "Cannot open $cpu_html: $!" . __FILE__ . ":" . __LINE__ ) && return 0;
      my @cpu_html = <FH>;
      close FH;
      my $item_view  = "lpar";
      my @lpar_lines = grep {/<B>.+<\/B>/} @cpu_html;
      foreach my $lpar_line (@lpar_lines) {
        ( undef, $lpar_line ) = split( "<B>", $lpar_line );
        ( my $lpar_name, undef ) = split( "</B>", $lpar_line );
        my $star = "star";    # power lpars in view are dashboard-able
        if ($vmware) {
          if ( $lpar_line !~ "poweredOn" ) {next}
          $lpar_name = human_vmware_name( $lpar_name, "neg" );
          $star      = "nostar";                                 # vmware VMs in view are NOT dashboard-able
        }
        if ($hyperv) {
          if ( $lpar_line !~ ">ON<" ) {next}
          $lpar_name = human_vmware_name( $lpar_name, "neg" );
          $star      = "nostar";                                 # hyperv VMs in view are NOT dashboard-able
          $item_view = "hyp-cpu";
        }
        $lpar_name =~ s/\//\&\&1/g;                              # replace for "/"
        my $lpar_url = $lpar_name;

        #$lpar_url =~ s/([^A-Za-z0-9\+-_])/sprintf("%%%02X", ord($1))/seg; # PH: keep it is it is exactly!!!
        $lpar_url =~ s/([^a-zA-Z0-9_.!~*()'\''-])/sprintf("%%%02X", ord($1))/ge;

        #$lpar_url =~ s/ /+/g;
        #$lpar_url =~ s/\#/%23/g;
        print_item( $host_url, $server_url, "$lpar_url", $item_view, $period, $type_sam, $entitle, $detail_yes, "norefr", "$star", 1, "legend" );
        $pict_count++;
        print "</tr>\n<tr>\n" if ( !( $pict_count % 2 ) );
      }
    }
    print "</tr></table>";
    print "</div>\n";
  }
  print "</div><br>\n";

  return 1;
}

sub human_vmware_name {
  my $lpar  = shift;
  my $arrow = shift;
  if ( !$vmware && !$hyperv ) { return "$lpar" }

  # only for vmware
  # read file and find human lpar name from uuid or
  # if 'neg' then find uuid from name
  # my $trans_file = "$wrkdir/vmware_VMs/vm_uuid_name.txt";
  my $vms_dir = "vmware_VMs";
  $vms_dir = "hyperv_VMs" if $hyperv;
  if ( -f "$wrkdir/$vms_dir/vm_uuid_name.txt" ) {
    open( FR, "< $wrkdir/$vms_dir/vm_uuid_name.txt" );
    foreach my $linep (<FR>) {
      chomp($linep);
      ( my $id, my $name ) = split( /,/, $linep );
      if ( defined($arrow) && "$arrow" eq "neg" ) {
        ( $name, $id ) = split( /,/, $linep );
      }
      if ( "$id" eq "$lpar" ) {
        $lpar = "$name";

        # last; # let it run until end, in case there are more lines for one VM then take the last line
      }
    }
    close(FR);
  }
  return "$lpar";    #human name - if found, or original
}

sub print_topten_head {
  my ( $server_url, $host_act ) = @_;

  my $lpars  = "LPARs";
  my $server = "server";

  if ( $item eq "topten_vm" ) {
    $lpars  = "VMs";
    $server = "vCenter";
  }
  if ( $server_url eq "" ) {

    #global one
    print "<center><h3>Top $lpars per average CPU load </h3></center>";
  }
  else {
    if ( $host_act eq "" ) {
      print "<center><h3>Top $lpars per average CPU load for $server : $server_url</h3></center>";
    }
    else {
      if ( -f "$wrkdir/$server_url/$host_act/IVM" ) {
        print "<center><h3>Top LPARs per average CPU load for server : $host_act</h3></center>";
      }
      else {
        print "<center><h3>Top $lpars per average CPU load for $server : $server_url</h3></center>";
      }
    }
  }
  return 1;
}

sub print_topten_net {
  my ( $period, $server_url ) = @_;

  my $topten_file = "";
  my $csv_file    = "";
  if ( $item eq "topten_vm" && $server_url eq "" ) {
    $csv_file = "lan_all_vms.csv";
  }
  else {
    $csv_file = "lan_$server_url.csv";
  }

  if ( !$csv ) {
    print "<TD><TABLE class=\"tabconfig tablesorter\" data-sortby=\"1\">";
    print "<thead>";
    if ( $period == 4 ) {    #last year
      print "<TR><TD nowrap ><B>Avrg</B></TD><TD nowrap><B>VM</B></TD><TD nowrap><B>vCenter</B></TD></TR>";
    }
    else {
      print "<TR><TD nowrap ><B>Avrg</B></TD><TD nowrap ><B>Max</B></TD><TD nowrap><B>VM</B></TD><TD nowrap><B>vCenter</B></TD></TR>";
    }
    print "</thead>";
  }
  else {
    print "Content-Disposition: attachment;filename=\"$csv_file\"\n\n";
    my $csv_header = "";
    if ( $period == 4 ) {    #last year
      $csv_header = "Avrg" . "$sep" . "VM" . "$sep" . "vCenter\n";
    }
    else {
      $csv_header = "Avrg" . "$sep" . "Max" . "$sep" . "VM" . "$sep" . "vCenter\n";
    }
    print "$csv_header";
  }
  $topten_file = "$tmpdir/topten_vm.tmp";

  my $topten_limit = 0;
  my @top_values_load;
  my @top_values_max;
  my @topten_not_sorted;
  my @topten_sorted;
  my @topten = "";
  if ( $server_url ne "" ) {
    $server = urldecode($server_url);
  }
  else { $server = ""; }
  if ( -f $topten_file ) {
    open( FH, " < $topten_file" ) || error( "Cannot open $topten_file: $!" . __FILE__ . ":" . __LINE__ );
    @topten = <FH>;
    close FH;
    if ( defined $ENV{TOPTEN} ) {
      $topten_limit = $ENV{TOPTEN};
    }
    $topten_limit = 50 if $topten_limit < 1;
    if ( "$server_url" ne "" ) {

      #local one
      my @topten_server = grep {/vm_net,$server,/} @topten;
      @topten = @topten_server;
    }
    else {
      my @topten_server = grep {/vm_net/} @topten;
      @topten = @topten_server;
    }
    foreach my $line (@topten) {
      chomp $line;
      ( my $item_a, my $server_t, my $lpar_t, my $hmc_t, $top_values_load[1], $top_values_max[1], $top_values_load[2], $top_values_max[2], $top_values_load[3], $top_values_max[3], $top_values_load[4], $top_values_max[4], my $vm_uuid, my $vcenter_uuid ) = split( ",", $line );
      $vm_uuid            = "" if !defined $vm_uuid;
      $vcenter_uuid       = "" if !defined $vcenter_uuid;
      $top_values_load[4] = 0  if !defined $top_values_load[4] or $top_values_load[4] eq "";    # no year value yet, new file
      $top_values_max[4]  = 0  if !defined $top_values_max[4]  or $top_values_max[4] eq "";     # no year value yet, new file
      push @topten_not_sorted, "$item_a,$top_values_load[$period],$top_values_max[$period],$server_t,$lpar_t,$hmc_t,$vm_uuid,$vcenter_uuid";
    }
    {
      no warnings;
      @topten_sorted = sort { $b <=> $a } @topten_not_sorted;
    }
  }
  my $time_sec = 2 * 86400;
  $time_sec = 8 * 86400   if $period == 2;
  $time_sec = 30 * 86400  if $period == 3;
  $time_sec = 365 * 86400 if $period == 4;
  my $top_count = 0;

  my @topten_sorted_load_cpu;
  {
    no warnings;
    @topten_sorted_load_cpu = sort {
      my @b = split( /,/, $b );
      my @a = split( /,/, $a );

      #print "$b[4] --- $a[4]\n";
      $b[1] <=> $a[1]
    } @topten_sorted;
  }
  foreach my $line1 (@topten_sorted_load_cpu) {
    my ( $item_a, $load, $load_peak, $server_t, $lpar_t, $hmc_t, $vm_uuid, $vcenter_uuid, $polo ) = split( ",", $line1 );

    # avoid old files which do not exist in the period
    #print STDERR "$item_a,$load,$server_t,$lpar_t,$hmc_t,$vm_uuid,$vcenter_uuid\n";
    if ( $item eq "topten_vm" ) {
      my $rrd_upd_time = ( stat("$wrkdir/vmware_VMs/$vm_uuid.rrm") )[9];
      if ( $rrd_upd_time < ( time() - $time_sec ) ) {
        next;
      }
    }
    my $lpar = $lpar_t;
    $lpar =~ s/\.rrm$//;
    $lpar =~ s/\.rrh$//;
    $lpar =~ s/%20/ /g;
    $lpar =~ s/\&\&1/\//g;
    my $lpar_urlx = $lpar;

    #$lpar_urlx =~ s/ /+/g;
    $lpar_urlx =~ s/([^a-zA-Z0-9_.!~*()'\''-])/sprintf("%%%02X", ord($1))/ge;

    if ( defined $vcenter_uuid && $vcenter_uuid =~ /vmware_/ ) {
      $top_count++;
      last if $top_count > $topten_limit;

      # in case of UTF8 names in VMWARE take encoded name from vm_uuid_name file
      #      my @names = grep {/$vm_uuid,/} @vm_uuid_names;
      #      if ( defined $names[0] && $names[0] ne "" ) {
      #        chomp $names[0];
      #
      #        # print STDERR "2793 detail-cgi.pl \$names[0] $names[0]\n";
      #        $lpar = ( split( ",", $names[0] ) )[1];
      #      } ## end if ( defined $names[0]...)
      $lpar = $vm_uuid_names{$vm_uuid};

      if ( !$xormon ) {
        if ( !$csv ) {
          if ( $period == 4 ) {    #last year
            print "<TR><TD  align=\"center\" style=\"padding:0px;\" nowrap><a>$load</a></TD><TD style=\"padding:0px;\" nowrap><A HREF=\"/lpar2rrd-cgi/detail.sh?host=$hmc_t&server=$server_t&lpar=$lpar_urlx&item=lpar&entitle=0&none=none\">$lpar</A></TD><TD style=\"padding:0px;\" nowrap><A HREF=\"/lpar2rrd-cgi/detail.sh?vcenter=$server_t&item=vtop10&d_platform=VMware&platform=VMware\">$server_t</A></TD></TR>";
          }
          else {
            print "<TR><TD  align=\"center\" style=\"padding:0px;\" nowrap><a>$load</a></TD><TD  align=\"center\" style=\"padding:0px;\" nowrap><a>$load_peak</a></TD><TD style=\"padding:0px;\" nowrap><A HREF=\"/lpar2rrd-cgi/detail.sh?host=$hmc_t&server=$server_t&lpar=$lpar_urlx&item=lpar&entitle=0&none=none\">$lpar</A></TD><TD style=\"padding:0px;\" nowrap><A HREF=\"/lpar2rrd-cgi/detail.sh?vcenter=$server_t&item=vtop10&d_platform=VMware&platform=VMware\">$server_t</A></TD></TR>";
          }
        }
        else {
          if ( $period == 4 ) {    #last year
            print "$load" . "$sep" . "$lpar_t" . "$sep" . "$server_t\n";
          }
          else {
            print "$load" . "$sep" . "$load_peak" . "$sep" . "$lpar_t" . "$sep" . "$server_t\n";
          }
        }
      }
      else {
        read_menu_vmware( \@menu_vmware ) if !@menu_vmware;
        my @matches = grep { /^L/ && /$vm_uuid/ } @menu_vmware;

        # print STDERR "1529 @matches\n";
        if ( !@matches || scalar @matches < 1 ) {
          error( "no menu item for uuid $vm_uuid $lpar_t: $!" . __FILE__ . ":" . __LINE__ );
          next;
        }

        # L:cluster_New Cluster:10.22.11.9:501cb14b-47b3-eb98-a53b-8cc8ec99296e:old-demo:/lpar2rrd-cgi/detail.sh?host=10.22.11.10&server=10.22.11.9&lpar=501cb14b-47b3-eb98-a53b-8cc8ec99296e&item=lpar&entitle=0&gui=1&none=none::Hosting:V:M::
        ( undef, my $server_vm ) = split( "server=", $matches[0] );
        $server_vm =~ s/&lpar=.*//;
        chomp $server_vm;
        if ( !$csv ) {
          $vcenter_uuid =~ s/^vmware_//;
          if ( $period == 4 ) {    #last year
            print "<TR><TD  align=\"center\" style=\"padding:0px;\" nowrap><a>$load</a></TD><TD style=\"padding:0px;\" nowrap><A HREF=\"/lpar2rrd-cgi/detail.sh?host=$hmc_t&server=$server_vm&lpar=$lpar_urlx&item=lpar&entitle=0&none=none&d_platform=VMware&platform=VMware\">$lpar</A></TD><TD style=\"padding:0px;\" nowrap><A HREF=\"/lpar2rrd-cgi/detail.sh?platform=Vmware&type=hmctotals&id=$vcenter_uuid\">$server_t</A></TD></TR>";
          }
          else {
            print "<TR><TD  align=\"center\" style=\"padding:0px;\" nowrap><a>$load</a></TD><TD  align=\"center\" style=\"padding:0px;\" nowrap><a>$load_peak</a></TD><TD style=\"padding:0px;\" nowrap><A HREF=\"/lpar2rrd-cgi/detail.sh?host=$hmc_t&server=$server_vm&lpar=$lpar_urlx&item=lpar&entitle=0&none=none&d_platform=VMware&platform=VMware\">$lpar</A></TD><TD style=\"padding:0px;\" nowrap><A HREF=\"/lpar2rrd-cgi/detail.sh?platform=Vmware&type=hmctotals&id=$vcenter_uuid\">$server_t</A></TD></TR>";
          }
        }
        else {
          if ( $period == 4 ) {    #last year
            print "$load" . "$sep" . "$lpar_t" . "$sep" . "$server_t\n";
          }
          else {
            print "$load" . "$sep" . "$load_peak" . "$sep" . "$lpar_t" . "$sep" . "$server_t\n";
          }
        }
      }
    }
    else {
      if ( $item_a =~ /load_cpu/ ) {
        $top_count++;
        last if $top_count > $topten_limit;
        $lpar_t =~ s/\.rrm//g;
        if ( !$csv ) {
          if ( $period == 4 ) {    #last year
            print "<TR><TD  align=\"center\" style=\"padding:0px;\" nowrap><a>$load</a></TD><TD style=\"padding:0px;\" nowrap><A HREF=\"/lpar2rrd-cgi/detail.sh?host=$hmc_t&server=$server_t&lpar=$lpar_urlx&item=lpar&entitle=0&none=none\">$lpar</A></TD><TD style=\"padding:0px;\" nowrap><A HREF=\"/lpar2rrd-cgi/detail.sh?host=$hmc_t&server=$server_t&lpar=pool&item=pool&entitle=0&none=none\">$server_t</A></TD></TR>";
          }
          else {
            print "<TR><TD  align=\"center\" style=\"padding:0px;\" nowrap><a>$load</a></TD><TD  align=\"center\" style=\"padding:0px;\" nowrap><a>$load_peak</a></TD><TD style=\"padding:0px;\" nowrap><A HREF=\"/lpar2rrd-cgi/detail.sh?host=$hmc_t&server=$server_t&lpar=$lpar_urlx&item=lpar&entitle=0&none=none\">$lpar</A></TD><TD style=\"padding:0px;\" nowrap><A HREF=\"/lpar2rrd-cgi/detail.sh?host=$hmc_t&server=$server_t&lpar=pool&item=pool&entitle=0&none=none\">$server_t</A></TD></TR>";
          }
        }
        else {
          if ( $period == 4 ) {    #last year
            print "$load" . "$sep" . "$lpar_t" . "$sep" . "$server_t\n";
          }
          else {
            print "$load" . "$sep" . "$load_peak" . "$sep" . "$lpar_t" . "$sep" . "$server_t\n";
          }
        }
      }
    }
  }

  if ( !$csv ) {
    print "<ul style=\"display: none\"><li class=\"tabhmc\"></li></ul>";    # to add the data source icon
    print "</TABLE></TD>";
  }
  return 1;
}

sub print_topten_iops {
  my ( $period, $server_url ) = @_;

  my $csv_file = "";
  if ( $item eq "topten_vm" && $server_url eq "" ) {
    $csv_file = "san_iops_all_vms.csv";
  }
  else {
    $csv_file = "san_iops_$server_url.csv";
  }

  if ( !$csv ) {
    print "<TD><TABLE class=\"tabconfig tablesorter\" data-sortby=\"1\">";
    print "<thead>";
    if ( $period == 4 ) {    # last year
      print "<TR><TD nowrap ><B>Avrg</B></TD><TD nowrap><B>VM</B></TD><TD nowrap><B>vCenter</B></TD></TR>";
    }
    else {
      print "<TR><TD nowrap ><B>Avrg</B></TD><TD nowrap ><B>Max</B></TD><TD nowrap><B>VM</B></TD><TD nowrap><B>vCenter</B></TD></TR>";
    }
    print "</thead>";
  }
  else {
    print "Content-Disposition: attachment;filename=\"$csv_file\"\n\n";
    my $csv_header = "";
    if ( $period == 4 ) {    # last year
      $csv_header = "Avrg" . "$sep" . "VM" . "$sep" . "vCenter\n";
    }
    else {
      $csv_header = "Avrg" . "$sep" . "Max" . "$sep" . "VM" . "$sep" . "vCenter\n";
    }
    print "$csv_header";
  }
  my $topten_file = "";
  $topten_file = "$tmpdir/topten_vm.tmp";

  my @top_values_load;
  my @top_values_max;
  my @topten_not_sorted;
  my @topten_sorted;
  my @topten       = "";
  my $topten_limit = 0;
  if ( $server_url ne "" ) {
    $server = urldecode($server_url);
  }
  else { $server = ""; }
  if ( -f $topten_file ) {
    open( FH, " < $topten_file" ) || error( "Cannot open $topten_file: $!" . __FILE__ . ":" . __LINE__ );
    @topten = <FH>;
    close FH;
    if ( defined $ENV{TOPTEN} ) {
      $topten_limit = $ENV{TOPTEN};
    }
    $topten_limit = 50 if $topten_limit < 1;
    if ( "$server_url" ne "" ) {

      #local one
      my @topten_server = grep {/vm_iops,$server,/} @topten;
      @topten = @topten_server;
    }
    else {
      my @topten_server = grep {/vm_iops/} @topten;
      @topten = @topten_server;
    }
    foreach my $line (@topten) {
      chomp $line;
      ( my $item_a, my $server_t, my $lpar_t, my $hmc_t, $top_values_load[1], $top_values_max[1], $top_values_load[2], $top_values_max[2], $top_values_load[3], $top_values_max[3], $top_values_load[4], $top_values_max[4], my $vm_uuid, my $vcenter_uuid ) = split( ",", $line );

      $vm_uuid            = "" if !defined $vm_uuid;
      $vcenter_uuid       = "" if !defined $vcenter_uuid;
      $top_values_load[4] = 0  if !defined $top_values_load[4] or $top_values_load[4] eq "";    # no year value yet, new file
      $top_values_max[4]  = 0  if !defined $top_values_max[4]  or $top_values_max[4] eq "";     # no year value yet, new file
      push @topten_not_sorted, "$item_a,$top_values_load[$period],$top_values_max[$period],$server_t,$lpar_t,$hmc_t,$vm_uuid,$vcenter_uuid";
    }
    {
      no warnings;
      @topten_sorted = sort { $b <=> $a } @topten_not_sorted;
    }
  }

  my $time_sec = 2 * 86400;
  $time_sec = 8 * 86400   if $period == 2;
  $time_sec = 30 * 86400  if $period == 3;
  $time_sec = 365 * 86400 if $period == 4;
  my $top_count = 0;
  my @topten_sorted_load_cpu;
  {
    no warnings;
    @topten_sorted_load_cpu = sort {
      my @b = split( /,/, $b );

      #print "@b!!\n";
      my @a = split( /,/, $a );
      $b[1] <=> $a[1]
    } @topten_sorted;
  }

  foreach my $line1 (@topten_sorted_load_cpu) {
    my ( $item_a, $load, $load_peak, $server_t, $lpar_t, $hmc_t, $vm_uuid, $vcenter_uuid ) = split( ",", $line1 );

    my $lpar = $lpar_t;
    $lpar =~ s/\.rrm$//;
    $lpar =~ s/\.rrh$//;
    $lpar =~ s/%20/ /g;
    $lpar =~ s/\&\&1/\//g;
    my $lpar_urlx = $lpar;

    #$lpar_urlx =~ s/ /+/g;
    $lpar_urlx =~ s/([^a-zA-Z0-9_.!~*()'\''-])/sprintf("%%%02X", ord($1))/ge;

    if ( defined $item_a && $item_a =~ /vm_iops/ ) {
      $top_count++;
      last if $top_count > $topten_limit;

      if ( !$xormon ) {
        if ( !$csv ) {
          if ( $period == 4 ) {    # last year
            print "<TR><TD  align=\"center\" style=\"padding:0px;\" nowrap><a>$load</a></TD><TD style=\"padding:0px;\" nowrap><A HREF=\"/lpar2rrd-cgi/detail.sh?host=$hmc_t&server=&lpar=$lpar_urlx&item=vmw-iops&entitle=0&none=none\">$lpar</A></TD><TD style=\"padding:0px;\" nowrap><A HREF=\"/lpar2rrd-cgi/detail.sh?vcenter=$server_t&item=vtop10\">$server_t</A></TD></TR>";
          }
          else {
            print "<TR><TD  align=\"center\" style=\"padding:0px;\" nowrap><a>$load</a></TD><TD  align=\"right\" style=\"padding:0px;\" nowrap><a>$load_peak</a></TD><TD style=\"padding:0px;\" nowrap><A HREF=\"/lpar2rrd-cgi/detail.sh?host=$hmc_t&server=&lpar=$lpar_urlx&item=vmw-iops&entitle=0&none=none\">$lpar</A></TD><TD style=\"padding:0px;\" nowrap><A HREF=\"/lpar2rrd-cgi/detail.sh?vcenter=$server_t&item=vtop10\">$server_t</A></TD></TR>";
          }

        }
        else {
          if ( $period == 4 ) {    # last year
            print "$load" . "$sep" . "$lpar_t" . "$sep" . "$server_t\n";
          }
          else {
            print "$load" . "$sep" . "$load_peak" . "$sep" . "$lpar_t" . "$sep" . "$server_t\n";
          }
        }
      }
      else {
        read_menu_vmware( \@menu_vmware ) if !@menu_vmware;
        my @matches = grep { /^L/ && /$vm_uuid/ } @menu_vmware;

        # print STDERR "1529 @matches\n";
        if ( !@matches || scalar @matches < 1 ) {
          error( "no menu item for uuid $vm_uuid $lpar_t: $!" . __FILE__ . ":" . __LINE__ );
          next;
        }

        # L:cluster_New Cluster:10.22.11.9:501cb14b-47b3-eb98-a53b-8cc8ec99296e:old-demo:/lpar2rrd-cgi/detail.sh?host=10.22.11.10&server=10.22.11.9&lpar=501cb14b-47b3-eb98-a53b-8cc8ec99296e&item=lpar&entitle=0&gui=1&none=none::Hosting:V:M::
        ( undef, my $server_vm ) = split( "server=", $matches[0] );
        $server_vm =~ s/&lpar=.*//;
        chomp $server_vm;
        if ( !$csv ) {
          $vcenter_uuid =~ s/^vmware_//;
          if ( $period == 4 ) {    # last year
            print "<TR><TD  align=\"center\" style=\"padding:0px;\" nowrap><a>$load</a></TD><TD style=\"padding:0px;\" nowrap><A HREF=\"/lpar2rrd-cgi/detail.sh?host=$hmc_t&server=$server_vm&lpar=$lpar_urlx&item=vmw-iops&entitle=0&none=none&d_platform=VMware&platform=VMware\">$lpar</A></TD><TD style=\"padding:0px;\" nowrap><A HREF=\"/lpar2rrd-cgi/detail.sh?platform=Vmware&type=hmctotals&id=$vcenter_uuid\">$server_t</A></TD></TR>";
          }
          else {
            print "<TR><TD  align=\"center\" style=\"padding:0px;\" nowrap><a>$load</a></TD><TD  align=\"right\" style=\"padding:0px;\" nowrap><a>$load_peak</a></TD><TD style=\"padding:0px;\" nowrap><A HREF=\"/lpar2rrd-cgi/detail.sh?host=$hmc_t&server=$server_vm&lpar=$lpar_urlx&item=vmw-iops&entitle=0&none=none&d_platform=VMware&platform=VMware\">$lpar</A></TD><TD style=\"padding:0px;\" nowrap><A HREF=\"/lpar2rrd-cgi/detail.sh?platform=Vmware&type=hmctotals&id=$vcenter_uuid\">$server_t</A></TD></TR>";
          }
        }
        else {
          if ( $period == 4 ) {    # last year
            print "$load" . "$sep" . "$lpar_t" . "$sep" . "$server_t\n";
          }
          else {
            print "$load" . "$sep" . "$load_peak" . "$sep" . "$lpar_t" . "$sep" . "$server_t\n";
          }
        }
      }
    }
  }

  if ( !$csv ) {
    print "<ul style=\"display: none\"><li class=\"tabhmc\"></li></ul>";    # to add the data source icon
    print "</TABLE></TD>";
  }
  return 1;
}

sub print_topten_disk {
  my ( $period, $server_url ) = @_;

  my $topten_file = "";
  my $csv_file    = "";
  if ( $item eq "topten_vm" && $server_url eq "" ) {
    $csv_file = "disk_all_vms.csv";
  }
  else {
    $csv_file = "disk_$server_url.csv";
  }

  if ( !$csv ) {
    print "<TD><TABLE class=\"tabconfig tablesorter\" data-sortby=\"1\">";
    print "<thead>";
    if ( $period == 4 ) {    # last year
      print "<TR><TD nowrap ><B>Avrg</B></TD><TD nowrap><B>VM</B></TD><TD nowrap><B>vCenter</B></TD></TR>";
    }
    else {
      print "<TR><TD nowrap ><B>Avrg</B></TD><TD nowrap ><B>Max</B></TD><TD nowrap><B>VM</B></TD><TD nowrap><B>vCenter</B></TD></TR>";
    }
    print "</thead>";
  }
  else {
    print "Content-Disposition: attachment;filename=\"$csv_file\"\n\n";
    my $csv_header = "";
    if ( $period == 4 ) {    # last year
      $csv_header = "Avrg" . "$sep" . "VM" . "$sep" . "vCenter\n";
    }
    else {
      $csv_header = "Avrg" . "$sep" . "Max" . "$sep" . "VM" . "$sep" . "vCenter\n";
    }
    print "$csv_header";
  }
  $topten_file = "$tmpdir/topten_vm.tmp";

  my @top_values_load;
  my @top_values_max;
  my @topten_not_sorted;
  my @topten_sorted;
  my @topten       = ();
  my $topten_limit = 0;
  if ( $server_url ne "" ) {
    $server = urldecode($server_url);
  }
  else { $server = ""; }
  if ( -f $topten_file ) {
    open( FH, " < $topten_file" ) || error( "Cannot open $topten_file: $!" . __FILE__ . ":" . __LINE__ );
    my @topten = <FH>;
    close FH;
    if ( defined $ENV{TOPTEN} ) {
      $topten_limit = $ENV{TOPTEN};
    }
    $topten_limit = 50 if $topten_limit < 1;
    if ( "$server_url" ne "" ) {

      #local one
      @topten = grep {/vm_disk,$server,/} @topten;
    }
    else {
      @topten = grep {/vm_disk/} @topten;
    }

    foreach my $line (@topten) {
      chomp $line;
      ( my $item_a, my $server_t, my $lpar_t, my $hmc_t, $top_values_load[1], $top_values_max[1], $top_values_load[2], $top_values_max[2], $top_values_load[3], $top_values_max[3], $top_values_load[4], $top_values_max[4], my $vm_uuid, my $vcenter_uuid ) = split( ",", $line );
      $vm_uuid            = "" if !defined $vm_uuid;
      $vcenter_uuid       = "" if !defined $vcenter_uuid;
      $top_values_load[4] = 0  if !defined $top_values_load[4] or $top_values_load[4] eq "";    # no year value yet, new file
      $top_values_max[4]  = 0  if !defined $top_values_max[4]  or $top_values_max[4] eq "";     # no year value yet, new file
      $vm_uuid            = "" if !defined $vm_uuid;
      $vcenter_uuid       = "" if !defined $vcenter_uuid;
      push @topten_not_sorted, "$item_a,$top_values_load[$period],$top_values_max[$period],$server_t,$lpar_t,$hmc_t,$vm_uuid,$vcenter_uuid";
    }
    {
      no warnings;
      @topten_sorted = sort { $b <=> $a } @topten_not_sorted;
    }
  }

  my $time_sec = 2 * 86400;
  $time_sec = 8 * 86400   if $period == 2;
  $time_sec = 30 * 86400  if $period == 3;
  $time_sec = 365 * 86400 if $period == 4;
  my $top_count = 0;

  my @topten_sorted_load_cpu;
  {
    no warnings;
    @topten_sorted_load_cpu = sort {
      my @b = split( /,/, $b );
      my @a = split( /,/, $a );

      #print "$b[1] --- $a[1]\n";
      $b[1] <=> $a[1]
    } @topten_sorted;
  }
  foreach my $line1 (@topten_sorted_load_cpu) {
    my ( $item_a, $load, $load_peak, $server_t, $lpar_t, $hmc_t, $vm_uuid, $vcenter_uuid, $polo ) = split( ",", $line1 );

    # avoid old files which do not exist in the period
    #print STDERR "$item_a,$load,$server_t,$lpar_t,$hmc_t,$vm_uuid,$vcenter_uuid\n";
    if ( $item eq "topten_vm" ) {
      my $rrd_upd_time = ( stat("$wrkdir/vmware_VMs/$vm_uuid.rrm") )[9];
      if ( $rrd_upd_time < ( time() - $time_sec ) ) {
        next;
      }
    }
    my $lpar = $lpar_t;
    $lpar =~ s/\.rrm$//;
    $lpar =~ s/\.rrh$//;
    $lpar =~ s/%20/ /g;
    $lpar =~ s/\&\&1/\//g;
    my $lpar_urlx = $lpar;

    #$lpar_urlx =~ s/ /+/g;
    $lpar_urlx =~ s/([^a-zA-Z0-9_.!~*()'\''-])/sprintf("%%%02X", ord($1))/ge;

    if ( defined $vcenter_uuid && $vcenter_uuid =~ /vmware_/ ) {
      $top_count++;
      last if $top_count > $topten_limit;

      # in case of UTF8 names in VMWARE take encoded name from vm_uuid_name file
      #      my @names = grep {/$vm_uuid,/} @vm_uuid_names;
      #      if ( defined $names[0] && $names[0] ne "" ) {
      #        chomp $names[0];
      #
      #        # print STDERR "5648 detail-cgi.pl \$names[0] $names[0] \$lpar $lpar\n";
      #        $lpar = ( split( ",", $names[0] ) )[1];
      #      } ## end if ( defined $names[0]...)
      $lpar = $vm_uuid_names{$vm_uuid};

      if ( !$xormon ) {
        if ( !$csv ) {
          if ( $period == 4 ) {    # last year
            print "<TR><TD  align=\"center\" style=\"padding:0px;\" nowrap><a>$load</a></TD><TD style=\"padding:0px;\" nowrap><A HREF=\"/lpar2rrd-cgi/detail.sh?host=$hmc_t&server=$server_t&lpar=$lpar_urlx&item=lpar&entitle=0&none=none\">$lpar</A></TD><TD style=\"padding:0px;\" nowrap><A HREF=\"/lpar2rrd-cgi/detail.sh?vcenter=$server_t&item=vtop10&d_platform=VMware&platform=VMware\">$server_t</A></TD></TR>";
          }
          else {
            print "<TR><TD  align=\"center\" style=\"padding:0px;\" nowrap><a>$load</a></TD><TD  align=\"center\" style=\"padding:0px;\" nowrap><a>$load_peak</a></TD><TD style=\"padding:0px;\" nowrap><A HREF=\"/lpar2rrd-cgi/detail.sh?host=$hmc_t&server=$server_t&lpar=$lpar_urlx&item=lpar&entitle=0&none=none\">$lpar</A></TD><TD style=\"padding:0px;\" nowrap><A HREF=\"/lpar2rrd-cgi/detail.sh?vcenter=$server_t&item=vtop10&d_platform=VMware&platform=VMware\">$server_t</A></TD></TR>";
          }
        }
        else {
          if ( $period == 4 ) {    # last year
            print "$load" . "$sep" . "$lpar_t" . "$sep" . "$server_t\n";
          }
          else {
            print "$load" . "$sep" . "$load_peak" . "$sep" . "$lpar_t" . "$sep" . "$server_t\n";
          }
        }
      }
      else {
        read_menu_vmware( \@menu_vmware ) if !@menu_vmware;
        my @matches = grep { /^L/ && /$vm_uuid/ } @menu_vmware;

        # print STDERR "1529 @matches\n";
        if ( !@matches || scalar @matches < 1 ) {
          error( "no menu item for uuid $vm_uuid $lpar_t: $!" . __FILE__ . ":" . __LINE__ );
          next;
        }

        # L:cluster_New Cluster:10.22.11.9:501cb14b-47b3-eb98-a53b-8cc8ec99296e:old-demo:/lpar2rrd-cgi/detail.sh?host=10.22.11.10&server=10.22.11.9&lpar=501cb14b-47b3-eb98-a53b-8cc8ec99296e&item=lpar&entitle=0&gui=1&none=none::Hosting:V:M::
        ( undef, my $server_vm ) = split( "server=", $matches[0] );
        $server_vm =~ s/&lpar=.*//;
        chomp $server_vm;
        if ( !$csv ) {
          $vcenter_uuid =~ s/^vmware_//;
          if ( $period == 4 ) {    # last year
            print "<TR><TD  align=\"center\" style=\"padding:0px;\" nowrap><a>$load</a></TD><TD style=\"padding:0px;\" nowrap><A HREF=\"/lpar2rrd-cgi/detail.sh?host=$hmc_t&server=$server_vm&lpar=$lpar_urlx&item=lpar&entitle=0&none=none&d_platform=VMware&platform=VMware\">$lpar</A></TD><TD style=\"padding:0px;\" nowrap><A HREF=\"/lpar2rrd-cgi/detail.sh?platform=Vmware&type=hmctotals&id=$vcenter_uuid\">$server_t</A></TD></TR>";
          }
          else {
            print "<TR><TD  align=\"center\" style=\"padding:0px;\" nowrap><a>$load</a></TD><TD  align=\"center\" style=\"padding:0px;\" nowrap><a>$load_peak</a></TD><TD style=\"padding:0px;\" nowrap><A HREF=\"/lpar2rrd-cgi/detail.sh?host=$hmc_t&server=$server_vm&lpar=$lpar_urlx&item=lpar&entitle=0&none=none&d_platform=VMware&platform=VMware\">$lpar</A></TD><TD style=\"padding:0px;\" nowrap><A HREF=\"/lpar2rrd-cgi/detail.sh?platform=Vmware&type=hmctotals&id=$vcenter_uuid\">$server_t</A></TD></TR>";
          }
        }
        else {
          if ( $period == 4 ) {    # last year
            print "$load" . "$sep" . "$lpar_t" . "$sep" . "$server_t\n";
          }
          else {
            print "$load" . "$sep" . "$load_peak" . "$sep" . "$lpar_t" . "$sep" . "$server_t\n";
          }
        }
      }
    }
    else {
      if ( $item_a =~ /load_cpu/ ) {
        $top_count++;
        last if $top_count > $topten_limit;
        $lpar_t =~ s/\.rrm//g;
        if ( !$csv ) {
          if ( $period == 4 ) {    # last year
            print "<TR><TD align=\"right\"><a>$load</a></TD><TD><A HREF=\"/lpar2rrd-cgi/detail.sh?host=$hmc_t&server=$server_t&lpar=$lpar_urlx&item=vmw-diskrw&entitle=0&none=none\">$lpar</A></TD><TD><A HREF=\"/lpar2rrd-cgi/detail.sh?host=$hmc_t&server=$server_t&lpar=pool&item=pool&entitle=0&none=none\">$server_t</A></TD></TR>";
          }
          else {
            print "<TR><TD align=\"right\"><a>$load</a></TD><TD align=\"right\"><a>$load_peak</a></TD><TD><A HREF=\"/lpar2rrd-cgi/detail.sh?host=$hmc_t&server=$server_t&lpar=$lpar_urlx&item=vmw-diskrw&entitle=0&none=none\">$lpar</A></TD><TD><A HREF=\"/lpar2rrd-cgi/detail.sh?host=$hmc_t&server=$server_t&lpar=pool&item=pool&entitle=0&none=none\">$server_t</A></TD></TR>";
          }
        }
        else {
          if ( $period == 4 ) {    # last year
            print "$load" . "$sep" . "$lpar_t" . "$sep" . "$server_t\n";
          }
          else {
            print "$load" . "$sep" . "$load_peak" . "$sep" . "$lpar_t" . "$sep" . "$server_t\n";
          }
        }
      }
    }
  }

  if ( !$csv ) {
    print "<ul style=\"display: none\"><li class=\"tabhmc\"></li></ul>";    # to add the data source icon
    print "</TABLE></TD>";
  }
  return 1;
}

sub print_topten {
  my ( $period, $server_url ) = @_;

  my $csv_file = "";
  if ( $item eq "topten" && $server_url eq "" ) {
    $csv_file = "load_cpu_all_lpars.csv";
  }
  elsif ( $item eq "topten_vm" && $server_url eq "" ) {
    $csv_file = "load_cpu_all_vms.csv";
  }
  else {
    $csv_file = "load_cpu_$server_url.csv";
  }

  my $topten_file = "$tmpdir/topten.tmp";
  if ( $item eq "topten_vm" ) {
    if ( !$csv ) {
      print "<TD><TABLE class=\"tabconfig tablesorter\" style=\"80%\" data-sortby=\"1\" role=\"grid\">";
      print "<thead>";
      if ( $period == 4 ) {    # last year
        print "<TR><TD align=\"left\" class=\"sortable\"><B>Avrg</B></TD><TD><B>VM</B></TD><TD><B>vCenter</B></TD></TR>";
      }
      else {
        print "<TR><TD align=\"left\" class=\"sortable\"><B>Avrg</B></TD><TD nowrap class=\"sortable\"><B>Max</B></TD><TD><B>VM</B></TD><TD><B>vCenter</B></TD></TR>";
      }
      print "</thead>";
    }
    else {
      print "Content-Disposition: attachment;filename=\"$csv_file\"\n\n";
      my $csv_header = "";
      if ( $period == 4 ) {    # last year
        $csv_header = "Avrg" . "$sep" . "VM" . "$sep" . "vCenter\n";
      }
      else {
        $csv_header = "Avrg" . "$sep" . "Max" . "$sep" . "VM" . "$sep" . "vCenter\n";
      }
      print "$csv_header";
    }
    $topten_file = "$tmpdir/topten_vm.tmp";
  }
  else {
    if ( !$csv ) {
      print "<TD><TABLE class=\"tabconfig tablesorter\" style=\"80%\" data-sortby=\"1\" role=\"grid\">";
      print "<thead>";
      if ( $period == 4 ) {    # last year
        print "<TR><TD align=\"left\" nowrap class=\"sortable\"><B>Avrg</B></TD><TD nowrap><B>LPAR</B></TH><TD nowrap><B>Server</B></TD></TR>";
      }
      else {
        print "<TR><TD align=\"left\" nowrap class=\"sortable\"><B>Avrg</B></TD><TD nowrap class=\"sortable\"><B>Max</B></TD><TD nowrap><B>LPAR</B></TH><TD nowrap><B>Server</B></TD></TR>";
      }
      print "</thead>";
    }
    else {
      print "Content-Disposition: attachment;filename=\"$csv_file\"\n\n";
      my $csv_header = "";
      if ( $period == 4 ) {    # last year
        $csv_header = "Avrg" . "$sep" . "LPAR" . "$sep" . "Server\n";
      }
      else {
        $csv_header = "Avrg" . "$sep" . "Max" . "$sep" . "LPAR" . "$sep" . "Server\n";
      }
      print "$csv_header";
    }
  }
  my @topten = "";
  my @top_values_load_cpu;
  my @top_values_load_peak;
  my @topten_not_sorted;
  my @topten_sorted;
  my $topten_limit = 0;
  if ( $server_url ne "" ) {
    $server = urldecode($server_url);
  }
  else { $server = ""; }
  if ( -f $topten_file ) {
    open( FH, " < $topten_file" ) || error( "Cannot open $topten_file: $!" . __FILE__ . ":" . __LINE__ );
    @topten = <FH>;
    close FH;
    if ( defined $ENV{TOPTEN} ) {
      $topten_limit = $ENV{TOPTEN};
    }
    $topten_limit = 50 if $topten_limit < 1;
    if ( "$server_url" ne "" && "$item" eq "topten_vm" ) {

      #for local top 10
      my @topten_server = grep {/vm_cpu,$server,/} @topten;
      @topten = @topten_server;
    }
    elsif ( "$server_url" ne "" && "$item" eq "topten" ) {

      #for local top 10
      my @topten_server_load_cpu  = grep {/load_cpu,$server,/} @topten;
      my @topten_server_load_peak = grep {/load_peak,$server,/} @topten;
      @topten = "";
      push @topten, @topten_server_load_cpu;
      push @topten, @topten_server_load_peak;
    }
    elsif ( "$server_url" eq "" && "$item" eq "topten_vm" ) {

      #for global top 10
      my @topten_server = grep {/vm_cpu,/} @topten;
      @topten = @topten_server;
    }
    elsif ( "$server_url" eq "" && "$item" eq "topten" ) {

      #for global top 10
      my @topten_server = grep {/load_cpu,/} @topten;
      @topten = @topten_server;
    }
    else {
      error( "Bad params for topten call period $period server $server_url item $item " . __FILE__ . ":" . __LINE__ ) && return 0;
    }
    foreach my $line (@topten) {
      chomp $line;
      next if !defined $line || $line eq "";
      my ( $vm_uuid, $vcenter_uuid );
      ( my $item_a, my $server_t, my $lpar_t, my $hmc_t ) = split( ",", $line );
      if ( $item_a eq "load_cpu" ) {
        ( undef, undef, undef, undef, $top_values_load_cpu[1], $top_values_load_peak[1], $top_values_load_cpu[2], $top_values_load_peak[2], $top_values_load_cpu[3], $top_values_load_peak[3], $top_values_load_cpu[4], $top_values_load_peak[4] ) = split( ",", $line );
      }
      else {
        ( undef, undef, undef, undef, $top_values_load_cpu[1], $top_values_load_peak[1], $top_values_load_cpu[2], $top_values_load_peak[2], $top_values_load_cpu[3], $top_values_load_peak[3], $top_values_load_cpu[4], $top_values_load_peak[4], $vm_uuid, $vcenter_uuid ) = split( ",", $line );
      }
      $vm_uuid                 = "" if !defined $vm_uuid;
      $vcenter_uuid            = "" if !defined $vcenter_uuid;
      $server_t                = "" if !defined $server_t;
      $lpar_t                  = "" if !defined $lpar_t;
      $hmc_t                   = "" if !defined $hmc_t;
      $top_values_load_cpu[4]  = 0  if !defined $top_values_load_cpu[4]  or $top_values_load_cpu[4] eq "";     # no year value yet, new file
      $top_values_load_peak[4] = 0  if !defined $top_values_load_peak[4] or $top_values_load_peak[4] eq "";    # no year value yet, new file
      push @topten_not_sorted, "$item_a,$top_values_load_cpu[$period],$top_values_load_peak[$period],$server_t,$lpar_t,$hmc_t,$vm_uuid,$vcenter_uuid";
    }
    {
      no warnings;
      @topten_sorted = sort { $b <=> $a } @topten_not_sorted;
    }
  }
  my $time_sec = 2 * 86400;
  $time_sec = 8 * 86400   if $period == 2;
  $time_sec = 30 * 86400  if $period == 3;
  $time_sec = 365 * 86400 if $period == 4;
  my $top_count = 0;

  my @topten_sorted_load_cpu;
  {
    no warnings;
    @topten_sorted_load_cpu = sort {
      my @b = split( /,/, $b );
      my @a = split( /,/, $a );

      #print "$b[4] --- $a[4]\n";
      $b[1] <=> $a[1]
    } @topten_sorted;
  }
  foreach my $line1 (@topten_sorted_load_cpu) {
    my ( $item_a, $load_cpu, $load_peak, $server_t, $lpar_t, $hmc_t, $vm_uuid, $vcenter_uuid, $polo );
    ($item_a) = split( ",", $line1 );
    if ( $item_a eq "load_cpu" ) {
      ( undef, $load_cpu, $load_peak, $server_t, $lpar_t, $hmc_t ) = split( ",", $line1 );
    }
    else {
      ( undef, $load_cpu, $load_peak, $server_t, $lpar_t, $hmc_t, $vm_uuid, $vcenter_uuid ) = split( ",", $line1 );    # last param , $polo ?
                                                                                                                       # print STDERR"$load_cpu, $load_peak, $server_t, $lpar_t, $hmc_t, $vm_uuid, $vcenter_uuid\n"; # last param , $polo ?
    }

    # avoid old files which do not exist in the period
    #print STDERR "$item_a,$load,$server_t,$lpar_t,$hmc_t,$vm_uuid,$vcenter_uuid\n";
    if ( $item eq "topten_vm" ) {

      # print STDERR "13969 $wrkdir/vmware_VMs/$vm_uuid.rrm\n" if $period eq 1;
      my $rrd_upd_time = ( stat("$wrkdir/vmware_VMs/$vm_uuid.rrm") )[9];
      my $rrd_test     = "$wrkdir/vmware_VMs/$vm_uuid.rrm";
      if ( $rrd_upd_time < ( time() - $time_sec ) ) {
        next;
      }
    }
    my $lpar = $lpar_t;
    $lpar =~ s/\.rrm$//;
    $lpar =~ s/\.rrh$//;
    $lpar =~ s/%20/ /g;
    $lpar =~ s/\&\&1/\//g;
    my $lpar_urlx = $lpar;

    #$lpar_urlx =~ s/ /+/g;
    $lpar_urlx =~ s/([^a-zA-Z0-9_.!~*()'\''-])/sprintf("%%%02X", ord($1))/ge;

    # print STDERR "13985 $lpar_urlx\n" if $period eq 1;
    if ( defined $vcenter_uuid && $vcenter_uuid =~ /vmware_/ ) {
      $top_count++;
      last if $top_count > $topten_limit;

      # in case of UTF8 names in VMWARE take encoded name from vm_uuid_name file
      #      my @names = grep {/$vm_uuid,/} @vm_uuid_names;
      #      if ( defined $names[0] && $names[0] ne "" ) {
      #        chomp $names[0];
      #
      #        # print STDERR "2793 detail-cgi.pl \$names[0] $names[0]\n";
      #        $lpar = ( split( ",", $names[0] ) )[1];
      #      } ## end if ( defined $names[0]...)
      $lpar = $vm_uuid_names{$vm_uuid};

      if ( !$xormon ) {
        if ( !$csv ) {
          if ( $period == 4 ) {    # last year
            print "<TR><TD  align=\"center\" style=\"padding:0px;\" nowrap><a>$load_cpu</a><TD style=\"padding:0px;\" nowrap><A HREF=\"/lpar2rrd-cgi/detail.sh?host=$hmc_t&server=$server_t&lpar=$lpar_urlx&item=lpar&entitle=0&none=none\">$lpar</A></TD><TD style=\"padding:0px;\" nowrap><A HREF=\"/lpar2rrd-cgi/detail.sh?vcenter=$server_t&item=vtop10&d_platform=VMware&platform=VMware\">$server_t</A></TD></TR>";
          }
          else {
            print "<TR><TD  align=\"center\" style=\"padding:0px;\" nowrap><a>$load_cpu</a></TD><TD  align=\"center\" style=\"padding:0px;\" nowrap><a>$load_peak</a></TD><TD style=\"padding:0px;\" nowrap><A HREF=\"/lpar2rrd-cgi/detail.sh?host=$hmc_t&server=$server_t&lpar=$lpar_urlx&item=lpar&entitle=0&none=none\">$lpar</A></TD><TD style=\"padding:0px;\" nowrap><A HREF=\"/lpar2rrd-cgi/detail.sh?vcenter=$server_t&item=vtop10&d_platform=VMware&platform=VMware\">$server_t</A></TD></TR>";
          }
        }
        else {
          if ( $period == 4 ) {    # last year
            print "$load_cpu" . "$sep" . "$lpar_t" . "$sep" . "$server_t\n";
          }
          else {
            print "$load_cpu" . "$sep" . "$load_peak" . "$sep" . "$lpar_t" . "$sep" . "$server_t\n";
          }
        }
      }
      else {    ## for xormon
        read_menu_vmware( \@menu_vmware ) if !@menu_vmware;
        my @matches = grep { /^L/ && /$vm_uuid/ } @menu_vmware;

        # print STDERR "10732 @matches\n";
        if ( !@matches || scalar @matches < 1 ) {
          error( "no menu item for uuid $vm_uuid $lpar_t: $!" . __FILE__ . ":" . __LINE__ );
          next;
        }

        # L:cluster_New Cluster:10.22.11.9:501cb14b-47b3-eb98-a53b-8cc8ec99296e:old-demo:/lpar2rrd-cgi/detail.sh?host=10.22.11.10&server=10.22.11.9&lpar=501cb14b-47b3-eb98-a53b-8cc8ec99296e&item=lpar&entitle=0&gui=1&none=none::Hosting:V:M::
        ( undef, my $server_vm ) = split( "server=", $matches[0] );
        $server_vm =~ s/&lpar=.*//;
        chomp $server_vm;
        if ( !$csv ) {
          $vcenter_uuid =~ s/^vmware_//;
          if ( $period == 4 ) {    # last year
            print "<TR><TD  align=\"center\" style=\"padding:0px;\" nowrap><a>$load_cpu</a></TD><TD style=\"padding:0px;\" nowrap><A HREF=\"/lpar2rrd-cgi/detail.sh?host=$hmc_t&server=$server_vm&lpar=$lpar_urlx&item=lpar&entitle=0&none=none&d_platform=VMware&platform=VMware\">$lpar</A></TD><TD style=\"padding:0px;\" nowrap><A HREF=\"/lpar2rrd-cgi/detail.sh?platform=Vmware&type=hmctotals&id=$vcenter_uuid\">$server_t</A></TD></TR>";
          }
          else {
            print "<TR><TD  align=\"center\" style=\"padding:0px;\" nowrap><a>$load_cpu</a></TD><TD  align=\"center\" style=\"padding:0px;\" nowrap><a>$load_peak</a></TD><TD style=\"padding:0px;\" nowrap><A HREF=\"/lpar2rrd-cgi/detail.sh?host=$hmc_t&server=$server_vm&lpar=$lpar_urlx&item=lpar&entitle=0&none=none&d_platform=VMware&platform=VMware\">$lpar</A></TD><TD style=\"padding:0px;\" nowrap><A HREF=\"/lpar2rrd-cgi/detail.sh?platform=Vmware&type=hmctotals&id=$vcenter_uuid\">$server_t</A></TD></TR>";
          }
        }
        else {
          if ( $period == 4 ) {    # last year
            print "$load_cpu" . "$sep" . "$lpar_t" . "$sep" . "$server_t\n";
          }
          else {
            print "$load_cpu" . "$sep" . "$load_peak" . "$sep" . "$lpar_t" . "$sep" . "$server_t\n";
          }
        }
      }
    }
    else {
      if ( $item_a =~ /load_cpu/ ) {
        $top_count++;
        last if $top_count > $topten_limit;
        $lpar_t =~ s/\.rrm//g;
        if ( !$csv ) {
          if ( $period == 4 ) {    # last year
            print "<TR><TD  align=\"center\" style=\"padding:0px;\" nowrap><a>$load_cpu</a></TD><TD style=\"padding:0px;\" nowrap><A HREF=\"/lpar2rrd-cgi/detail.sh?host=$hmc_t&server=$server_t&lpar=$lpar_urlx&item=lpar&entitle=0&none=none\">$lpar</A></TD><TD style=\"padding:0px;\" nowrap><A HREF=\"/lpar2rrd-cgi/detail.sh?host=$hmc_t&server=$server_t&lpar=pool&item=pool&entitle=0&none=none\">$server_t</A></TD></TR>";
          }
          else {
            print "<TR><TD  align=\"center\" style=\"padding:0px;\" nowrap><a>$load_cpu</a></TD><TD  align=\"center\" style=\"padding:0px;\" nowrap><a>$load_peak</a></TD><TD style=\"padding:0px;\" nowrap><A HREF=\"/lpar2rrd-cgi/detail.sh?host=$hmc_t&server=$server_t&lpar=$lpar_urlx&item=lpar&entitle=0&none=none\">$lpar</A></TD><TD style=\"padding:0px;\" nowrap><A HREF=\"/lpar2rrd-cgi/detail.sh?host=$hmc_t&server=$server_t&lpar=pool&item=pool&entitle=0&none=none\">$server_t</A></TD></TR>";
          }
        }
        else {
          if ( $period == 4 ) {    # last year
            print "$load_cpu" . "$sep" . "$lpar_t" . "$sep" . "$server_t\n";
          }
          else {
            print "$load_cpu" . "$sep" . "$load_peak" . "$sep" . "$lpar_t" . "$sep" . "$server_t\n";
          }
        }
      }
    }
  }

  if ( !$csv ) {
    print "<ul style=\"display: none\"><li class=\"tabhmc\"></li></ul>";    # to add the data source icon
    print "</TABLE></TD>";
  }
  return 1;
}

sub print_aix_multipath_to_csv {

  my ( $server_url, $hmc_url, $lpar_url, $item ) = @_;
  my $csv_file = "multipath_$lpar_url.csv";
  print "Content-Disposition: attachment;filename=\"$csv_file\"\n\n";

  #my $csv_header = "Disk name" . "$sep" . "Disk size" . "$sep" . "Path properties" . "$sep" . "Path info" . "$sep" . "Path status" . "$sep" . "Status\n";
  my $csv_header = "Disk name" . "$sep" . "Disk size" . "$sep" . "Status\n";
  print "$csv_header";

  my %hash_aix      = ();
  my %hash_aix_size = ();

  my $file = "$wrkdir/$server_url/$hmc_url/$lpar_url/aix_multipathing.txt";
  if ( -f "$file" ) {
    open( FH, "< $file" ) || error( "Cannot open $file: $!" . __FILE__ . ":" . __LINE__ );
    my @lsdisk_arr = <FH>;
    close(FH);
    my @list_of_disk;
    foreach my $line (@lsdisk_arr) {
      chomp($line);
      my ( $namedisk, $path_id, $connection, $parent, $path_status, $status, $disk_size ) = split( /:/, $line );
      $parent =~ s/=====double-colon=====/:/g;
      my $values  = "$path_status:$status";
      my $values2 = "$parent,$path_status,$status";
      push @{ $hash_aix{$lpar}{$namedisk}{$parent} }, $values;
      if ( Xorux_lib::isdigit($disk_size) ) {
        $hash_aix_size{$namedisk}{disk_size} = $disk_size;
        push @{ $hash_aix_size{$namedisk}{status} }, $values2;
      }
      else {
        push @{ $hash_aix_size{$namedisk}{status} }, $values2;
      }
    }
  }
  foreach my $disk_name ( keys %hash_aix_size ) {
    my $disk_size    = "-";
    my $final_status = "OK";
    if ( defined $hash_aix_size{$disk_name}{disk_size} ) {
      $disk_size = $hash_aix_size{$disk_name}{disk_size};
    }
    if ( defined $hash_aix_size{$disk_name}{status} ) {
      $final_status = "OK";
      foreach my $line ( @{ $hash_aix_size{$disk_name}{status} } ) {
        ( undef, my $path_status, my $status ) = split( /,/, $line );
        if ( $status !~ /Available|Enabled/ ) {
          $final_status = "Critical";
        }
        if ( $path_status !~ /Available/ ) {
          $final_status = "Critical";
        }
      }
    }
    my $csv_line = "$disk_name" . "$sep" . "$disk_size" . "$sep" . "$final_status\n";
    print "$csv_line";
  }

  exit;
}

sub print_fs_to_csv {

  my ( $server_url, $hmc_url, $lpar_url, $item ) = @_;
  my $csv_file = "FS_$lpar_url.csv";
  print "Content-Disposition: attachment;filename=\"$csv_file\"\n\n";
  my $csv_header = "Filesystem" . "$sep" . "Total [GB]" . "$sep" . "Used [GB]" . "$sep" . "Available [GB]" . "$sep" . "Usage [%]" . "$sep" . "Mounted_on\n";
  print "$csv_header";

  my $file = "$wrkdir/$server_url/$hmc_url/$lpar_url/FS.csv";
  if ( -f "$file" ) {
    open( FH, "< $file" ) || error( "Cannot open $file: $!" . __FILE__ . ":" . __LINE__ );
    my @file_sys_arr = <FH>;
    close(FH);
    foreach my $line (@file_sys_arr) {
      chomp($line);
      ( my $filesystem, my $blocks, my $used, my $avaliable, my $usage, my $mounted ) = split( " ", $line );
      my $csv_line = "$filesystem" . "$sep" . "$blocks" . "$sep" . "$used" . "$sep" . "$avaliable" . "$sep" . "$usage" . "$sep" . "$mounted\n";
      print "$csv_line";
    }
  }

  exit;
}

sub print_topten_cpu_per {
  my ( $period, $server_url ) = @_;

  my $csv_file = "";
  if ( $item eq "topten" && $server_url eq "" ) {
    $csv_file = "load_cpu_inpercent_all_lpars.csv";
  }
  elsif ( $item eq "topten_vm" && $server_url eq "" ) {
    $csv_file = "load_cpu_inpercent_all_vms.csv";
  }
  else {
    $csv_file = "load_cpu_inpercent_$server_url.csv";
  }

  my $topten_file = "$tmpdir/topten.tmp";
  if ( $item eq "topten_vm" ) {
    if ( !$csv ) {
      print "<TD><TABLE class=\"tabconfig tablesorter\" data-sortby=\"1\">";
      print "<thead>";
      if ( $period == 4 ) {    # last year
        print "<TR><TD><B>Avrg</B></TD><TD><B>VM</B></TD><TD><B>vCenter</B></TD></TR>";
      }
      else {
        print "<TR><TD><B>Avrg</B></TD><TD><B>Max</B></TD><TD><B>VM</B></TD><TD><B>vCenter</B></TD></TR>";
      }
      print "</thead>";
    }
    else {
      print "Content-Disposition: attachment;filename=\"$csv_file\"\n\n";
      my $csv_header = "";
      if ( $period == 4 ) {    # last year
        $csv_header = "Avrg" . "$sep" . "VM" . "$sep" . "Server\n";
      }
      else {
        $csv_header = "Avrg" . "$sep" . "Max" . "$sep" . "VM" . "$sep" . "vCenter\n";
      }
      print "$csv_header";
    }
    $topten_file = "$tmpdir/topten_vm.tmp";
  }
  else {
    if ( !$csv ) {
      print "<TD><TABLE class=\"tabconfig tablesorter\" data-sortby=\"1\">";
      print "<thead>";
      if ( $period == 4 ) {    # last year
        print "<TR><TD><B>Avrg</B></TD><TD><B>LPAR</B></TD><TD><B>Server</B></TD></TR>";
      }
      else {
        print "<TR><TD><B>Avrg</B></TD><TD><B>Max</B></TD><TD><B>LPAR</B></TD><TD><B>Server</B></TD></TR>";
      }
      print "</thead>";
    }
    else {
      print "Content-Disposition: attachment;filename=\"$csv_file\"\n\n";
      my $csv_header = "";
      if ( $period == 4 ) {    # last year
        $csv_header = "Avrg" . "$sep" . "LPAR" . "$sep" . "Server\n";
      }
      else {
        $csv_header = "Avrg" . "$sep" . "Max" . "$sep" . "LPAR" . "$sep" . "Server\n";
      }
      print "$csv_header";
    }
  }
  my @topten = "";
  my @top_values_load;
  my @top_values_max;
  my @topten_not_sorted;
  my @topten_sorted;
  my $topten_limit = 0;
  if ( $server_url ne "" ) {
    $server = urldecode($server_url);
  }
  else { $server = ""; }
  if ( -f $topten_file ) {
    open( FH, " < $topten_file" ) || error( "Cannot open $topten_file: $!" . __FILE__ . ":" . __LINE__ );
    @topten = <FH>;
    close FH;
    if ( defined $ENV{TOPTEN} ) {
      $topten_limit = $ENV{TOPTEN};
    }
    $topten_limit = 50 if $topten_limit < 1;
    my @topten_server;
    if ( $server_url ne "" && $item eq "topten_vm" ) {
      @topten_server = grep {/vm_perc_cpu,$server/} @topten;
    }
    elsif ( $server_url eq "" && $item eq "topten_vm" ) {
      @topten_server = grep {/vm_perc_cpu,/} @topten;
    }
    elsif ( $server_url eq "" && $item eq "topten" ) {
      @topten_server = grep {/util_cpu_perc,/} @topten;
    }
    else {
      @topten_server = grep {/util_cpu_perc,$server/} @topten;
    }
    @topten = @topten_server;

    foreach my $line (@topten) {
      chomp $line;
      ( my $item_a, my $server_t, my $lpar_t, my $hmc_t, $top_values_load[1], $top_values_max[1], $top_values_load[2], $top_values_max[2], $top_values_load[3], $top_values_max[3], $top_values_load[4], $top_values_max[4], my $vm_uuid, my $vcenter_uuid ) = split( ",", $line );
      $vm_uuid            = "" if !defined $vm_uuid;
      $vcenter_uuid       = "" if !defined $vcenter_uuid;
      $top_values_load[4] = 0  if !defined $top_values_load[4] or $top_values_load[4] eq "";    # no year value yet, new file
      $top_values_max[4]  = 0  if !defined $top_values_max[4]  or $top_values_max[4] eq "";     # no year value yet, new file
      push @topten_not_sorted, "$item_a,$top_values_load[$period],$top_values_max[$period],$server_t,$lpar_t,$hmc_t,$vm_uuid,$vcenter_uuid";
    }
    {
      no warnings;
      @topten_sorted = sort { $b <=> $a } @topten_not_sorted;
    }
  }
  my $time_sec = 2 * 86400;
  $time_sec = 8 * 86400   if $period == 2;
  $time_sec = 30 * 86400  if $period == 3;
  $time_sec = 365 * 86400 if $period == 4;
  my $top_count = 0;

  my @topten_sorted_load_cpu;
  {
    no warnings;
    @topten_sorted_load_cpu = sort {
      my @b = split( /,/, $b );
      my @a = split( /,/, $a );

      #print "$b[4] --- $a[4]\n";
      $b[1] <=> $a[1]
    } @topten_sorted;
  }
  foreach my $line1 (@topten_sorted_load_cpu) {
    my ( $item_a, $load, $load_peak, $server_t, $lpar_t, $hmc_t, $vm_uuid, $vcenter_uuid, $polo ) = split( ",", $line1 );

    # avoid old files which do not exist in the period
    #print STDERR "$item_a,$load,$server_t,$lpar_t,$hmc_t,$vm_uuid,$vcenter_uuid\n";
    if ( $item eq "topten_vm" ) {
      my $rrd_upd_time = ( stat("$wrkdir/vmware_VMs/$vm_uuid.rrm") )[9];
      if ( $rrd_upd_time < ( time() - $time_sec ) ) {
        next;
      }
    }
    my $lpar = $lpar_t;
    $lpar =~ s/\.rrm$//;
    $lpar =~ s/\.rrh$//;
    $lpar =~ s/%20/ /g;
    $lpar =~ s/\&\&1/\//g;
    my $lpar_urlx = $lpar;

    #$lpar_urlx =~ s/ /+/g;
    $lpar_urlx =~ s/([^a-zA-Z0-9_.!~*()'\''-])/sprintf("%%%02X", ord($1))/ge;

    if ( defined $vcenter_uuid && $vcenter_uuid =~ /vmware_/ ) {
      $top_count++;
      last if $top_count > $topten_limit;

      # in case of UTF8 names in VMWARE take encoded name from vm_uuid_name file
      #      my @names = grep {/$vm_uuid,/} @vm_uuid_names;
      #      if ( defined $names[0] && $names[0] ne "" ) {
      #        chomp $names[0];

      # print STDERR "2793 detail-cgi.pl \$names[0] $names[0]\n";
      #        $lpar = ( split( ",", $names[0] ) )[1];
      #      } ## end if ( defined $names[0]...)
      $lpar = $vm_uuid_names{$vm_uuid};

      if ( !$xormon ) {
        if ( !$csv ) {
          if ( $period == 4 ) {    # last year
            print "<TR><TD  align=\"center\" style=\"padding:0px;\" nowrap><a>$load</a></TD><TD style=\"padding:0px;\" nowrap><A HREF=\"/lpar2rrd-cgi/detail.sh?host=$hmc_t&server=$server_t&lpar=$lpar_urlx&item=lpar&entitle=0&none=none\">$lpar</A></TD><TD style=\"padding:0px;\" nowrap><A HREF=\"/lpar2rrd-cgi/detail.sh?vcenter=$server_t&item=vtop10&d_platform=VMware&platform=VMware\">$server_t</A></TD></TR>";
          }
          else {
            print "<TR><TD  align=\"center\" style=\"padding:0px;\" nowrap><a>$load</a></TD><TD  align=\"center\" style=\"padding:0px;\" nowrap><a>$load_peak</a></TD><TD style=\"padding:0px;\" nowrap><A HREF=\"/lpar2rrd-cgi/detail.sh?host=$hmc_t&server=$server_t&lpar=$lpar_urlx&item=lpar&entitle=0&none=none\">$lpar</A></TD><TD style=\"padding:0px;\" nowrap><A HREF=\"/lpar2rrd-cgi/detail.sh?vcenter=$server_t&item=vtop10&d_platform=VMware&platform=VMware\">$server_t</A></TD></TR>";

          }
        }
        else {
          if ( $period == 4 ) {    # last year
            print "$load" . "$sep" . "$lpar_t" . "$sep" . "$server_t\n";
          }
          else {
            print "$load" . "$sep" . "$load_peak" . "$sep" . "$lpar_t" . "$sep" . "$server_t\n";
          }
        }
      }
      else {    ## for xormon
        read_menu_vmware( \@menu_vmware ) if !@menu_vmware;
        my @matches = grep { /^L/ && /$vm_uuid/ } @menu_vmware;

        # print STDERR "10732 @matches\n";
        if ( !@matches || scalar @matches < 1 ) {
          error( "no menu item for uuid $vm_uuid $lpar_t: $!" . __FILE__ . ":" . __LINE__ );
          next;
        }

        # L:cluster_New Cluster:10.22.11.9:501cb14b-47b3-eb98-a53b-8cc8ec99296e:old-demo:/lpar2rrd-cgi/detail.sh?host=10.22.11.10&server=10.22.11.9&lpar=501cb14b-47b3-eb98-a53b-8cc8ec99296e&item=lpar&entitle=0&gui=1&none=none::Hosting:V:M::
        ( undef, my $server_vm ) = split( "server=", $matches[0] );
        $server_vm =~ s/&lpar=.*//;
        chomp $server_vm;
        if ( !$csv ) {
          $vcenter_uuid =~ s/^vmware_//;
          print "<TR><TD  align=\"center\" style=\"padding:0px;\" nowrap><a>$load</a></TD><TD  align=\"center\" style=\"padding:0px;\" nowrap><a>$load_peak</a></TD><TD style=\"padding:0px;\" nowrap><A HREF=\"/lpar2rrd-cgi/detail.sh?host=$hmc_t&server=$server_vm&lpar=$lpar_urlx&item=lpar&entitle=0&none=none&d_platform=VMware&platform=VMware\">$lpar</A></TD><TD style=\"padding:0px;\" nowrap><A HREF=\"/lpar2rrd-cgi/detail.sh?platform=Vmware&type=hmctotals&id=$vcenter_uuid\">$server_t</A></TD></TR>";
        }
        else {
          if ( $period == 4 ) {    # last year
            print "$load" . "$sep" . "$lpar_t" . "$sep" . "$server_t\n";
          }
          else {
            print "$load" . "$sep" . "$load_peak" . "$sep" . "$lpar_t" . "$sep" . "$server_t\n";
          }
        }
      }
    }
    else {
      #if ( $item_a =~ /load_cpu/ ) {
      $top_count++;
      last if $top_count > $topten_limit;
      $lpar_t =~ s/\.rrm//g;
      if ( !$csv ) {
        if ( $period == 4 ) {    # last year
          print "<TR><TD  align=\"center\" style=\"padding:0px;\" nowrap><a>$load</a></TD><TD style=\"padding:0px;\" nowrap><A HREF=\"/lpar2rrd-cgi/detail.sh?host=$hmc_t&server=$server_t&lpar=$lpar_urlx&item=lpar&entitle=0&none=none\">$lpar</A></TD><TD style=\"padding:0px;\" nowrap><A HREF=\"/lpar2rrd-cgi/detail.sh?host=$hmc_t&server=$server_t&lpar=pool&item=pool&entitle=0&none=none\">$server_t</A></TD></TR>";
        }
        else {
          print "<TR><TD  align=\"center\" style=\"padding:0px;\" nowrap><a>$load</a></TD><TD  align=\"center\" style=\"padding:0px;\" nowrap><a>$load_peak</a></TD><TD style=\"padding:0px;\" nowrap><A HREF=\"/lpar2rrd-cgi/detail.sh?host=$hmc_t&server=$server_t&lpar=$lpar_urlx&item=lpar&entitle=0&none=none\">$lpar</A></TD><TD style=\"padding:0px;\" nowrap><A HREF=\"/lpar2rrd-cgi/detail.sh?host=$hmc_t&server=$server_t&lpar=pool&item=pool&entitle=0&none=none\">$server_t</A></TD></TR>";
        }
      }
      else {
        if ( $period == 4 ) {    # last year
          print "$load" . "$sep" . "$lpar_t" . "$sep" . "$server_t\n";
        }
        else {
          print "$load" . "$sep" . "$load_peak" . "$sep" . "$lpar_t" . "$sep" . "$server_t\n";
        }
      }

      #} ## end if ( $item_a =~ /load_cpu/)
    }
  }

  if ( !$csv ) {
    print "<ul style=\"display: none\"><li class=\"tabhmc\"></li></ul>";    # to add the data source icon
    print "</TABLE></TD>";
  }
  return 1;
}

sub print_topten_san_iops {
  my ( $period, $server_url ) = @_;

  my $csv_file = "";
  if ( $item eq "topten" && $server_url eq "" ) {
    $csv_file = "san_iops_all_lpars.csv";
  }
  else {
    $csv_file = "san_iops_$server_url.csv";
  }

  my $topten_file = "$tmpdir/topten.tmp";
  if ( !$csv ) {
    print "<TD><TABLE class=\"tabconfig tablesorter\" data-sortby=\"1\">";
    print "<thead>";
    if ( $period == 4 ) {    # last year
      print "<TR><TD nowrap ><B>Avrg</B></TD><TD nowrap><B>LPAR</B></TD><TD nowrap><B>SERVER</B></TD></TR>";
    }
    else {
      print "<TR><TD nowrap ><B>Avrg</B></TD><TD nowrap ><B>Max</B></TD><TD nowrap><B>LPAR</B></TD><TD nowrap><B>SERVER</B></TD></TR>";
    }
    print "</thead>";
  }
  else {
    print "Content-Disposition: attachment;filename=\"$csv_file\"\n\n";
    my $csv_header = "";
    if ( $period == 4 ) {    # last year
      $csv_header = "Avrg" . "$sep" . "LPAR" . "$sep" . "Server\n";
    }
    else {
      $csv_header = "Avrg" . "$sep" . "Max" . "$sep" . "LPAR" . "$sep" . "Server\n";
    }
    print "$csv_header";
  }

  my @top_values_load;
  my @top_values_max;
  my @topten_not_sorted;
  my @topten_sorted;
  my $topten_limit = 0;
  my @topten       = "";
  if ( $server_url ne "" ) {
    $server = urldecode($server_url);
  }
  else { $server = ""; }
  if ( -f $topten_file ) {
    open( FH, " < $topten_file" ) || error( "Cannot open $topten_file: $!" . __FILE__ . ":" . __LINE__ );
    @topten = <FH>;
    close FH;
    if ( defined $ENV{TOPTEN} ) {
      $topten_limit = $ENV{TOPTEN};
    }
    $topten_limit = 50 if $topten_limit < 1;

    #print STDERR "2741 detail-cgi.pl \$period $period \$server_url $server_url \$server $server \@topten @topten\n";
    if ( "$server_url" ne "" ) {

      #local one
      my @topten_server = grep {/,$server,/} @topten;
      @topten = @topten_server;
    }
    foreach my $line (@topten) {
      chomp $line;
      ( my $item_a, my $server_t, my $lpar_t, my $hmc_t, $top_values_load[1], $top_values_max[1], $top_values_load[2], $top_values_max[2], $top_values_load[3], $top_values_max[3], $top_values_load[4], $top_values_max[4], my $vm_uuid, my $vcenter_uuid ) = split( ",", $line );
      $vm_uuid      = "" if !defined $vm_uuid;
      $vcenter_uuid = "" if !defined $vcenter_uuid;
      push @topten_not_sorted, "$item_a,$top_values_load[$period],$top_values_max[$period],$server_t,$lpar_t,$hmc_t,$vm_uuid,$vcenter_uuid";
    }

    {
      no warnings;
      @topten_sorted = sort { $b <=> $a } @topten_not_sorted;
    }
  }
  my $time_sec = 2 * 86400;
  $time_sec = 8 * 86400   if $period == 2;
  $time_sec = 30 * 86400  if $period == 3;
  $time_sec = 365 * 86400 if $period == 4;
  my $top_count = 0;

  #print "@topten_sorted\n";
  my @topten_sorted_os_san = sort {
    my @b = split( /,/, $b );
    my @a = split( /,/, $a );
    $b[1] <=> $a[1]
  } @topten_sorted;
  foreach my $line1 (@topten_sorted_os_san) {
    ( my $item_a, my $load, my $load_peak, my $server_t, my $lpar_t, my $hmc_t, my $vm_uuid, my $vcenter_uuid, undef ) = split( ",", $line1 );
    my $lpar = $lpar_t;
    $lpar =~ s/\.rrm$//;
    $lpar =~ s/\.rrh$//;
    $lpar =~ s/%20/ /g;
    $lpar =~ s/\&\&1/\//g;
    my $lpar_urlx = $lpar;

    #$lpar_urlx =~ s/ /+/g;
    $lpar_urlx =~ s/([^a-zA-Z0-9_.!~*()'\''-])/sprintf("%%%02X", ord($1))/ge;
    if ( $item_a =~ /^os_san_iops$/ ) {
      $top_count++;
      last if $top_count > $topten_limit;
      if ( !$csv ) {
        if ( $period == 4 ) {    # last year
          print "<TR><TD  align=\"center\" style=\"padding:0px;\" nowrap><a>$load</a></TD><TD style=\"padding:0px;\" nowrap>$lpar</A></TD><TD style=\"padding:0px;\" nowrap><A HREF=\"/lpar2rrd-cgi/detail.sh?host=$hmc_t&server=$server_t&lpar=pool&item=pool&entitle=0&none=none\">$server_t</A></TD></TR>";
        }
        else {
          print "<TR><TD  align=\"center\" style=\"padding:0px;\" nowrap><a>$load</a></TD><TD  align=\"center\" style=\"padding:0px;\" nowrap><a>$load_peak</a></TD><TD style=\"padding:0px;\" nowrap><A HREF=\"/lpar2rrd-cgi/detail.sh?host=$hmc_t&server=$server_t&lpar=$lpar_urlx&item=lpar&entitle=0&none=none\">$lpar</A></TD><TD style=\"padding:0px;\" nowrap><A HREF=\"/lpar2rrd-cgi/detail.sh?host=$hmc_t&server=$server_t&lpar=pool&item=pool&entitle=0&none=none\">$server_t</A></TD></TR>";
        }
      }
      else {
        if ( $period == 4 ) {    # last year
          print "$load" . "$sep" . "$sep" . "$lpar" . "$sep" . "$server_t\n";
        }
        else {
          print "$load" . "$sep" . "$load_peak" . "$sep" . "$lpar" . "$sep" . "$server_t\n";
        }
      }
    }
  }

  if ( !$csv ) {
    print "<ul style=\"display: none\"><li class=\"tabhmc\"></li></ul>";    # to add the data source icon
    print "</TABLE></TD>";
  }
  return 1;
}

sub print_topten_san {
  my ( $period, $server_url ) = @_;
  my $topten_file = "$tmpdir/topten.tmp";

  my $csv_file = "";
  if ( $item eq "topten" && $server_url eq "" ) {
    $csv_file = "san_all_lpars.csv";
  }
  else {
    $csv_file = "san_$server_url.csv";
  }

  if ( !$csv ) {
    print "<TD><TABLE class=\"tabconfig tablesorter\" data-sortby=\"1\">";
    print "<thead>";
    if ( $period == 4 ) {    # last year
      print "<TR><TD nowrap ><B>Avrg</B></TD><TD nowrap><B>LPAR</B></TD><TD nowrap><B>SERVER</B></TD></TR>";
    }
    else {
      print "<TR><TD nowrap ><B>Avrg</B></TD><TD nowrap ><B>Max</B></TD><TD nowrap><B>LPAR</B></TD><TD nowrap><B>SERVER</B></TD></TR>";
    }
    print "</thead>";
  }
  else {
    print "Content-Disposition: attachment;filename=\"$csv_file\"\n\n";
    my $csv_header = "";
    if ( $period == 4 ) {    # last year
      $csv_header = "Avrg" . "$sep" . "LPAR" . "$sep" . "Server\n";
    }
    else {
      $csv_header = "Avrg" . "$sep" . "Max" . "$sep" . "LPAR" . "$sep" . "Server\n";
    }
    print "$csv_header";
  }
  my @top_values_load;
  my @top_values_max;
  my @topten_not_sorted;
  my @topten_sorted;
  my $topten_limit = 0;
  my @topten       = "";
  if ( $server_url ne "" ) {
    $server = urldecode($server_url);
  }
  else { $server = ""; }
  if ( -f $topten_file ) {
    open( FH, " < $topten_file" ) || error( "Cannot open $topten_file: $!" . __FILE__ . ":" . __LINE__ );
    @topten = <FH>;
    close FH;
    if ( defined $ENV{TOPTEN} ) {
      $topten_limit = $ENV{TOPTEN};
    }
    $topten_limit = 50 if $topten_limit < 1;

    #print STDERR "2741 detail-cgi.pl \$period $period \$server_url $server_url \$server $server \@topten @topten\n";
    if ( "$server_url" ne "" ) {

      #local one
      my @topten_server = grep {/,$server,/} @topten;
      @topten = @topten_server;
    }
    foreach my $line (@topten) {
      chomp $line;
      ( my $item_a, my $server_t, my $lpar_t, my $hmc_t, $top_values_load[1], $top_values_max[1], $top_values_load[2], $top_values_max[2], $top_values_load[3], $top_values_max[3], $top_values_load[4], $top_values_max[4], my $vm_uuid, my $vcenter_uuid ) = split( ",", $line );
      $vm_uuid      = "" if !defined $vm_uuid;
      $vcenter_uuid = "" if !defined $vcenter_uuid;
      push @topten_not_sorted, "$item_a,$top_values_load[$period],$top_values_max[$period],$server_t,$lpar_t,$hmc_t,$vm_uuid,$vcenter_uuid";
    }

    {
      no warnings;
      @topten_sorted = sort { $b <=> $a } @topten_not_sorted;
    }
  }

  my $time_sec = 2 * 86400;
  $time_sec = 8 * 86400   if $period == 2;
  $time_sec = 30 * 86400  if $period == 3;
  $time_sec = 365 * 86400 if $period == 4;
  my $top_count = 0;

  #print "@topten_sorted\n";
  my @topten_sorted_os_san = sort {
    my @b = split( /,/, $b );
    my @a = split( /,/, $a );
    $b[1] <=> $a[1]
  } @topten_sorted;
  foreach my $line1 (@topten_sorted_os_san) {
    ( my $item_a, my $load, my $load_peak, my $server_t, my $lpar_t, my $hmc_t, my $vm_uuid, my $vcenter_uuid, undef ) = split( ",", $line1 );
    my $lpar = $lpar_t;
    $lpar =~ s/\.rrm$//;
    $lpar =~ s/\.rrh$//;
    $lpar =~ s/%20/ /g;
    $lpar =~ s/\&\&1/\//g;
    my $lpar_urlx = $lpar;

    #$lpar_urlx =~ s/ /+/g;
    $lpar_urlx =~ s/([^a-zA-Z0-9_.!~*()'\''-])/sprintf("%%%02X", ord($1))/ge;
    if ( $item_a =~ /^os_san1$/ ) {
      $top_count++;
      last if $top_count > $topten_limit;
      if ( !$csv ) {
        if ( $period == 4 ) {    # last year
          print "<TR><TD  align=\"center\" style=\"padding:0px;\" nowrap><a>$load</a></TD><TD style=\"padding:0px;\" nowrap><A HREF=\"/lpar2rrd-cgi/detail.sh?host=$hmc_t&server=$server_t&lpar=$lpar_urlx&item=lpar&entitle=0&none=none\">$lpar</A></TD><TD style=\"padding:0px;\" nowrap><A HREF=\"/lpar2rrd-cgi/detail.sh?host=$hmc_t&server=$server_t&lpar=pool&item=pool&entitle=0&none=none\">$server_t</A></TD></TR>";
        }
        else {
          print "<TR><TD  align=\"center\" style=\"padding:0px;\" nowrap><a>$load</a></TD><TD  align=\"center\" style=\"padding:0px;\" nowrap><a>$load_peak</a></TD><TD style=\"padding:0px;\" nowrap><A HREF=\"/lpar2rrd-cgi/detail.sh?host=$hmc_t&server=$server_t&lpar=$lpar_urlx&item=lpar&entitle=0&none=none\">$lpar</A></TD><TD style=\"padding:0px;\" nowrap><A HREF=\"/lpar2rrd-cgi/detail.sh?host=$hmc_t&server=$server_t&lpar=pool&item=pool&entitle=0&none=none\">$server_t</A></TD></TR>";
        }
      }
      else {
        if ( $period == 4 ) {    # last year
          print "$load" . "$sep" . "$lpar" . "$sep" . "$server_t\n";
        }
        else {
          print "$load" . "$sep" . "$load_peak" . "$sep" . "$lpar" . "$sep" . "$server_t\n";
        }
      }
    }

  }

  if ( !$csv ) {
    print "</TABLE></TD>";
  }
  return 1;
}

sub print_topten_lan {
  my ( $period, $server_url ) = @_;

  my $topten_file = "$tmpdir/topten.tmp";
  my $csv_file    = "";
  if ( $item eq "topten" && $server_url eq "" ) {
    $csv_file = "lan_all_lpars.csv";
  }
  else {
    $csv_file = "lan_$server_url.csv";
  }

  if ( !$csv ) {
    print "<TD><TABLE class=\"tabconfig tablesorter\" data-sortby=\"1\">";
    print "<thead>";
    print "<TR><TD nowrap ><B>Avrg</B></TD><TD nowrap ><B>Max</B></TD><TD nowrap><B>LPAR</B></TD><TD nowrap><B>SERVER</B></TD></TR>";
    print "</thead>";
  }
  else {
    print "Content-Disposition: attachment;filename=\"$csv_file\"\n\n";
    my $csv_header = "Avrg" . "$sep" . "Max" . "$sep" . "LPAR" . "$sep" . "Server\n";
    print "$csv_header";
  }
  my @topten = "";
  my @top_values_load;
  my @top_values_max;
  my @topten_not_sorted;
  my @topten_sorted;
  my $topten_limit = 0;
  if ( $server_url ne "" ) {
    $server = urldecode($server_url);
  }
  else { $server = ""; }
  if ( -f $topten_file ) {
    open( FH, " < $topten_file" ) || error( "Cannot open $topten_file: $!" . __FILE__ . ":" . __LINE__ );
    @topten = <FH>;
    close FH;
    if ( defined $ENV{TOPTEN} ) {
      $topten_limit = $ENV{TOPTEN};
    }
    $topten_limit = 50 if $topten_limit < 1;

    #print STDERR "2741 detail-cgi.pl \$period $period \$server_url $server_url \$server $server \@topten @topten\n";
    if ( "$server_url" ne "" ) {

      #local one
      my @topten_server = grep {/,$server,/} @topten;
      @topten = @topten_server;
    }
    foreach my $line (@topten) {
      chomp $line;
      ( my $item_a, my $server_t, my $lpar_t, my $hmc_t, $top_values_load[1], $top_values_max[1], $top_values_load[2], $top_values_max[2], $top_values_load[3], $top_values_max[3], $top_values_load[4], $top_values_max[4], my $vm_uuid, my $vcenter_uuid ) = split( ",", $line );
      $vm_uuid      = "" if !defined $vm_uuid;
      $vcenter_uuid = "" if !defined $vcenter_uuid;
      push @topten_not_sorted, "$item_a,$top_values_load[$period],$top_values_max[$period],$server_t,$lpar_t,$hmc_t,$vm_uuid,$vcenter_uuid";
    }

    {
      no warnings;
      @topten_sorted = sort { $b <=> $a } @topten_not_sorted;
    }
  }
  my $time_sec = 2 * 86400;
  $time_sec = 8 * 86400   if $period == 2;
  $time_sec = 30 * 86400  if $period == 3;
  $time_sec = 365 * 86400 if $period == 4;
  my $top_count = 0;

  #print "@topten_sorted\n";
  my @topten_sorted_os_san = sort {
    my @b = split( /,/, $b );
    my @a = split( /,/, $a );
    $b[1] <=> $a[1]
  } @topten_sorted;
  foreach my $line1 (@topten_sorted_os_san) {
    ( my $item_a, my $load, my $load_peak, my $server_t, my $lpar_t, my $hmc_t, my $vm_uuid, my $vcenter_uuid, undef ) = split( ",", $line1 );
    my $lpar = $lpar_t;
    $lpar =~ s/\.rrm$//;
    $lpar =~ s/\.rrh$//;
    $lpar =~ s/%20/ /g;
    $lpar =~ s/\&\&1/\//g;
    my $lpar_urlx = $lpar;

    #$lpar_urlx =~ s/ /+/g;
    $lpar_urlx =~ s/([^a-zA-Z0-9_.!~*()'\''-])/sprintf("%%%02X", ord($1))/ge;
    if ( $item_a =~ /^os_lan$/ ) {
      $top_count++;
      last if $top_count > $topten_limit;
      if ( !$csv ) {
        print "<TR><TD  align=\"center\" style=\"padding:0px;\" nowrap><a>$load</a></TD><TD  align=\"center\" style=\"padding:0px;\" nowrap><a>$load_peak</a></TD><TD style=\"padding:0px;\" nowrap><A HREF=\"/lpar2rrd-cgi/detail.sh?host=$hmc_t&server=$server_t&lpar=$lpar_urlx&item=lpar&entitle=0&none=none\">$lpar</A></TD><TD style=\"padding:0px;\" nowrap><A HREF=\"/lpar2rrd-cgi/detail.sh?host=$hmc_t&server=$server_t&lpar=pool&item=pool&entitle=0&none=none\">$server_t</A></TD></TR>";
      }
      else {
        print "$load" . "$sep" . "$load_peak" . "$sep" . "$lpar" . "$sep" . "$server_t\n";
      }
    }
  }

  #print "<ul style=\"display: none\"><li class=\"tabhmc\"></li></ul>"; # to add the data source icon
  if ( !$csv ) {
    print "</TABLE></TD>";
  }
  return 1;
}

sub print_topten_vm {
  my ( $host_url, $server_url, $lpar_url, $item, $entitle ) = @_;
  my $topten_limit = 0;
  if ( defined $ENV{TOPTEN} ) {
    $topten_limit = $ENV{TOPTEN};
  }
  $topten_limit = 50 if $topten_limit < 1;

  # print STDERR "11547 ".localtime()."\n";
  my $vm_uuid_name_file = "$wrkdir/vmware_VMs/vm_uuid_name.txt";
  open( FH, " < $vm_uuid_name_file" ) || error( "Cannot open $vm_uuid_name_file: $!" . __FILE__ . ":" . __LINE__ );
  while (<FH>) {
    ( my $uuid, my $name, undef ) = split( ",", $_ );
    $vm_uuid_names{$uuid} = $name;
  }
  close FH;

  print "<div  id=\"tabs\">\n";
  print "<CENTER>";

  print "<ul>\n";
  print "  <li class=\"tabhmc\"><a href=\"#tabs-1\">Last Day</a></li>\n";

  print "  <li class=\"tabhmc\"><a href=\"#tabs-2\">Last Week</a></li>\n";

  print "  <li class=\"tabhmc\"><a href=\"#tabs-3\">Last Month</a></li>\n";

  print "  <li class=\"tabhmc\"><a href=\"#tabs-4\">Last Year</a></li>\n";

  print "</ul>\n";

  # print STDERR "\n11565 ".localtime()."\n";
  print "<div id=\"tabs-1\" class='vm_top'>\n";
  print "<table align=\"center\" summary=\"Graphs\">\n";
  print "<tr><th align=center>CPU in GHz<a class=\"csvfloat\" href=\"/lpar2rrd-cgi/top10_csv.sh?LPAR=$server_url&host=CSV&type=VMWARE&table=topten_vm&item=load_cpu&period=1\" title=\"LOAD CPU CSV\"></a></th><th align=center>CPU %<a class=\"csvfloat\" href=\"/lpar2rrd-cgi/top10_csv.sh?LPAR=$server_url&host=CSV&type=VMWARE&table=topten_vm&item=cpu_perc&period=1\" title=\"LOAD CPU in % CSV\"></a></th><th align=center>IOPS<a class=\"csvfloat\" href=\"/lpar2rrd-cgi/top10_csv.sh?LPAR=$server_url&host=CSV&type=VMWARE&table=topten_vm&item=san_iops&period=1\" title=\"SAN IOPS CSV\"></a></th></th></th><th align=center>DISK in MB/sec<a class=\"csvfloat\" href=\"/lpar2rrd-cgi/top10_csv.sh?LPAR=$server_url&host=CSV&type=VMWARE&table=topten_vm&item=disk_data&period=1\" title=\"DISK CSV\"></a></th><th align=center>LAN in MB<a class=\"csvfloat\" href=\"/lpar2rrd-cgi/top10_csv.sh?LPAR=$server_url&host=CSV&type=VMWARE&table=topten_vm&item=lan&period=1\" title=\"LAN CSV\"></a></th></tr>";
  print "<tr style=\"vertical-align:top\">";
  print_topten( "1", "$server_url" );    #day
  print_topten_cpu_per( "1", "$server_url" );
  print_topten_iops( "1", "$server_url" );
  print_topten_disk( "1", "$server_url" );
  print_topten_net( "1", "$server_url" );
  print "</tr>";
  print "</table>";
  print "</div>\n";

  # print STDERR "11580 ".localtime()."\n";
  print "<div id=\"tabs-2\" class='vm_top'>\n";
  print "<table align=\"center\" summary=\"Graphs\">\n";
  print "<tr><th align=center>CPU in GHz<a class=\"csvfloat\" href=\"/lpar2rrd-cgi/top10_csv.sh?LPAR=$server_url&host=CSV&type=VMWARE&table=topten_vm&item=load_cpu&period=2\" title=\"LOAD CPU CSV\"></a></th><th align=center>CPU %<a class=\"csvfloat\" href=\"/lpar2rrd-cgi/top10_csv.sh?LPAR=$server_url&host=CSV&type=VMWARE&table=topten_vm&item=cpu_perc&period=2\" title=\"LOAD CPU in % CSV\"></a></th><th align=center>IOPS<a class=\"csvfloat\" href=\"/lpar2rrd-cgi/top10_csv.sh?LPAR=$server_url&host=CSV&type=VMWARE&table=topten_vm&item=san_iops&period=2\" title=\"SAN IOPS CSV\"></a></th></th></th><th align=center>DISK in MB/sec<a class=\"csvfloat\" href=\"/lpar2rrd-cgi/top10_csv.sh?LPAR=$server_url&host=CSV&type=VMWARE&table=topten_vm&item=disk_data&period=2\" title=\"DISK CSV\"></a></th><th align=center>LAN in MB<a class=\"csvfloat\" href=\"/lpar2rrd-cgi/top10_csv.sh?LPAR=$server_url&host=CSV&type=VMWARE&table=topten_vm&item=lan&period=2\" title=\"LAN CSV\"></a></th></tr>";
  print "<tr style=\"vertical-align:top\">";
  print_topten( "2", "$server_url" );    #week
  print_topten_cpu_per( "2", "$server_url" );
  print_topten_iops( "2", "$server_url" );
  print_topten_disk( "2", "$server_url" );
  print_topten_net( "2", "$server_url" );
  print "</tr>";
  print "</table>";
  print "</div>\n";

  # print STDERR "11592 ".localtime()."\n";
  print "<div id=\"tabs-3\" class='vm_top'>\n";
  print "<table align=\"center\" summary=\"Graphs\">\n";
  print "<tr><th align=center>CPU in GHz<a class=\"csvfloat\" href=\"/lpar2rrd-cgi/top10_csv.sh?LPAR=$server_url&host=CSV&type=VMWARE&table=topten_vm&item=load_cpu&period=3\" title=\"LOAD CPU CSV\"></a></th><th align=center>CPU %<a class=\"csvfloat\" href=\"/lpar2rrd-cgi/top10_csv.sh?LPAR=$server_url&host=CSV&type=VMWARE&table=topten_vm&item=cpu_perc&period=3\" title=\"LOAD CPU in % CSV\"></a></th><th align=center>IOPS<a class=\"csvfloat\" href=\"/lpar2rrd-cgi/top10_csv.sh?LPAR=$server_url&host=CSV&type=VMWARE&table=topten_vm&item=san_iops&period=3\" title=\"SAN IOPS CSV\"></a></th></th></th><th align=center>DISK in MB/sec<a class=\"csvfloat\" href=\"/lpar2rrd-cgi/top10_csv.sh?LPAR=$server_url&host=CSV&type=VMWARE&table=topten_vm&item=disk_data&period=3\" title=\"DISK CSV\"></a></th><th align=center>LAN in MB<a class=\"csvfloat\" href=\"/lpar2rrd-cgi/top10_csv.sh?LPAR=$server_url&host=CSV&type=VMWARE&table=topten_vm&item=lan&period=3\" title=\"LAN CSV\"></a></th></tr>";
  print "<tr style=\"vertical-align:top\">";
  print_topten( "3", "$server_url" );    #month
  print_topten_cpu_per( "3", "$server_url" );
  print_topten_iops( "3", "$server_url" );
  print_topten_disk( "3", "$server_url" );
  print_topten_net( "3", "$server_url" );
  print "</tr>";
  print "</table>";
  print "</div>\n";

  # print STDERR "11604 ".localtime()."\n";
  print "<div id=\"tabs-4\" class='vm_top'>\n";
  print "<table align=\"center\" summary=\"Graphs\">\n";
  print "<tr><th align=center>CPU in GHz<a class=\"csvfloat\" href=\"/lpar2rrd-cgi/top10_csv.sh?LPAR=$server_url&host=CSV&type=VMWARE&table=topten_vm&item=load_cpu&period=4\" title=\"LOAD CPU CSV\"></a></th><th align=center>CPU %<a class=\"csvfloat\" href=\"/lpar2rrd-cgi/top10_csv.sh?LPAR=$server_url&host=CSV&type=VMWARE&table=topten_vm&item=cpu_perc&period=4\" title=\"LOAD CPU in % CSV\"></a></th><th align=center>IOPS<a class=\"csvfloat\" href=\"/lpar2rrd-cgi/top10_csv.sh?LPAR=$server_url&host=CSV&type=VMWARE&table=topten_vm&item=san_iops&period=4\" title=\"SAN IOPS CSV\"></a></th></th></th><th align=center>DISK in MB/sec<a class=\"csvfloat\" href=\"/lpar2rrd-cgi/top10_csv.sh?LPAR=$server_url&host=CSV&type=VMWARE&table=topten_vm&item=disk_data&period=4\" title=\"DISK CSV\"></a></th><th align=center>LAN in MB<a class=\"csvfloat\" href=\"/lpar2rrd-cgi/top10_csv.sh?LPAR=$server_url&host=CSV&type=VMWARE&table=topten_vm&item=lan&period=4\" title=\"LAN CSV\"></a></th></tr>";
  print "<tr style=\"vertical-align:top\">";
  print_topten( "4", "$server_url" );    #year
  print_topten_cpu_per( "4", "$server_url" );
  print_topten_iops( "4", "$server_url" );
  print_topten_disk( "4", "$server_url" );
  print_topten_net( "4", "$server_url" );
  print "</tr>";
  print "</table>";
  print "</div>\n";

  # print STDERR "11200 ".localtime()."\n";

  print "<div><br>Note that this page is refreshed once a day, the first LPAR2RRD run after midnight";
  print "<br>If you want to have different number of lpars here like top 100 etc, then modify parameter TOPTEN=$topten_limit in etc/lpar2rrd.cfg";
  my $file = "$tmpdir/topten_vm.tmp";
  if ( !-f $file ) {
    error("File $file does not exists(first run after midnight creates it)") && return;
  }
  my $last_mod_time = ( stat($file) )[9];
  print "<br>Included are only VMs having data";
  print "<br>Updated: ";
  print scalar localtime $last_mod_time;
  print "<br></div>";

  print "</div><br>\n";

  return 1;
}

sub print_topten_all {
  my ( $host_url, $server_url, $lpar_url, $item, $entitle ) = @_;
  my $topten_limit = 0;
  if ( defined $ENV{TOPTEN} ) {
    $topten_limit = $ENV{TOPTEN};
  }
  $topten_limit = 50 if $topten_limit < 1;

  #print_topten_head ($server_url,$host_url);
  #print_topten_head ($server,$host_url);

  print "<div  id=\"tabs\">\n";
  print "<CENTER>";

  print "<ul>\n";
  print "  <li class=\"tabhmc\"><a href=\"#tabs-1\">Last Day</a></li>\n";

  print "  <li class=\"tabhmc\"><a href=\"#tabs-2\">Last Week</a></li>\n";

  print "  <li class=\"tabhmc\"><a href=\"#tabs-3\">Last Month</a></li>\n";

  print "  <li class=\"tabhmc\"><a href=\"#tabs-4\">Last Year</a></li>\n";

  print "  <li class=\"tabhmc\"><a href=\"#tabs-5\">CPU - All Periods</a></li>\n";

  print "</ul>\n";

  print "<div id=\"tabs-1\">\n";
  print "<table align=\"center\" summary=\"Graphs\">\n";
  print "<tr><th align=center>Load in CPU cores<a class=\"csvfloat\" href=\"/lpar2rrd-cgi/top10_csv.sh?LPAR=$server_url&host=CSV&type=POWER&table=topten&item=load_cpu&period=1\" title=\"LOAD CPU CORES CSV\"><img src=\"css/images/csv.gif\"></a></th></th><th align=center>CPU in %<a class=\"csvfloat\" href=\"/lpar2rrd-cgi/top10_csv.sh?LPAR=$server_url&host=CSV&type=POWER&table=topten&item=cpu_perc&period=1\" title=\"LOAD CPU in % CSV\"><img src=\"css/images/csv.gif\"></a></th></th><th align=center>SAN IOPS<a class=\"csvfloat\" href=\"/lpar2rrd-cgi/top10_csv.sh?LPAR=$server_url&host=CSV&type=POWER&table=topten&item=san_iops&period=1\" title=\"SAN IOPS CSV\"><img src=\"css/images/csv.gif\"></a></th></th><th align=center>SAN in MB<a class=\"csvfloat\" href=\"/lpar2rrd-cgi/top10_csv.sh?LPAR=$server_url&host=CSV&type=POWER&table=topten&item=san&period=1\" title=\"SAN CSV\"><img src=\"css/images/csv.gif\"></a></th></th><th align=center>LAN in MB<a class=\"csvfloat\" href=\"/lpar2rrd-cgi/top10_csv.sh?LPAR=$server_url&host=CSV&type=POWER&table=topten&item=lan&period=1\" title=\"LAN CSV\"><img src=\"css/images/csv.gif\"></a></th></th></tr>";
  print "<tr style=\"vertical-align:top\">";
  print_topten( "1", "$server_url" );             #day
  print_topten_cpu_per( "1", "$server_url" );     #day
  print_topten_san_iops( "1", "$server_url" );    #day
  print_topten_san( "1", "$server_url" );         #day
  print_topten_lan( "1", "$server_url" );         #day
  print "</tr>";
  print "</table>";
  print "</div>\n";

  print "<div id=\"tabs-2\">\n";
  print "<table align=\"center\" summary=\"Graphs\">\n";
  print "<tr><th align=center>Load in CPU cores<a class=\"csvfloat\" href=\"/lpar2rrd-cgi/top10_csv.sh?LPAR=$server_url&host=CSV&type=POWER&table=topten&item=load_cpu&period=2\" title=\"LOAD CPU CORES CSV\"><img src=\"css/images/csv.gif\"></a></th></th><th align=center>CPU in %<a class=\"csvfloat\" href=\"/lpar2rrd-cgi/top10_csv.sh?LPAR=$server_url&host=CSV&type=POWER&table=topten&item=cpu_perc&period=2\" title=\"LOAD CPU in % CSV\"><img src=\"css/images/csv.gif\"></a></th></th><th align=center>SAN IOPS<a class=\"csvfloat\" href=\"/lpar2rrd-cgi/top10_csv.sh?LPAR=$server_url&host=CSV&type=POWER&table=topten&item=san_iops&period=2\" title=\"SAN IOPS CSV\"><img src=\"css/images/csv.gif\"></a></th></th><th align=center>SAN in MB<a class=\"csvfloat\" href=\"/lpar2rrd-cgi/top10_csv.sh?LPAR=$server_url&host=CSV&type=POWER&table=topten&item=san&period=2\" title=\"SAN CSV\"><img src=\"css/images/csv.gif\"></a></th></th><th align=center>LAN in MB<a class=\"csvfloat\" href=\"/lpar2rrd-cgi/top10_csv.sh?LPAR=$server_url&host=CSV&type=POWER&table=topten&item=lan&period=2\" title=\"LAN CSV\"><img src=\"css/images/csv.gif\"></a></th></th></tr>";
  print "<tr style=\"vertical-align:top\">";
  print_topten( "2", "$server_url" );             #week
  print_topten_cpu_per( "2", "$server_url" );     #week
  print_topten_san_iops( "2", "$server_url" );    #week
  print_topten_san( "2", "$server_url" );         #week
  print_topten_lan( "2", "$server_url" );         #week
  print "</tr>";
  print "</table>";
  print "</div>\n";

  print "<div id=\"tabs-3\">\n";
  print "<table align=\"center\" summary=\"Graphs\">\n";
  print "<tr><th align=center>Load in CPU cores<a class=\"csvfloat\" href=\"/lpar2rrd-cgi/top10_csv.sh?LPAR=$server_url&host=CSV&type=POWER&table=topten&item=load_cpu&period=3\" title=\"LOAD CPU CORES CSV\"><img src=\"css/images/csv.gif\"></a></th></th><th align=center>CPU in %<a class=\"csvfloat\" href=\"/lpar2rrd-cgi/top10_csv.sh?LPAR=$server_url&host=CSV&type=POWER&table=topten&item=cpu_perc&period=3\" title=\"LOAD CPU in % CSV\"><img src=\"css/images/csv.gif\"></a></th></tr>";
  print "<tr style=\"vertical-align:top\">";
  print_topten( "3", "$server_url" );             #month
  print_topten_cpu_per( "3", "$server_url" );     #month
  print "</tr>";
  print "</table>";
  print "</div>\n";

  print "<div id=\"tabs-4\">\n";
  print "<table align=\"center\" summary=\"Graphs\">\n";
  print "<tr><th align=center>Load in CPU cores<a class=\"csvfloat\" href=\"/lpar2rrd-cgi/top10_csv.sh?LPAR=$server_url&host=CSV&type=POWER&table=topten&item=load_cpu&period=4\" title=\"LOAD CPU CORES CSV\"><img src=\"css/images/csv.gif\"></a></th></th><th align=center>CPU in %<a class=\"csvfloat\" href=\"/lpar2rrd-cgi/top10_csv.sh?LPAR=$server_url&host=CSV&type=POWER&table=topten&item=cpu_perc&period=4\" title=\"LOAD CPU in % CSV\"><img src=\"css/images/csv.gif\"></a></th></tr>";
  print "<tr style=\"vertical-align:top\">";
  print_topten( "4", "$server_url" );             #year
  print_topten_cpu_per( "4", "$server_url" );     #year
  print "</tr>";
  print "</table>";
  print "</div>\n";

  print "<div id=\"tabs-5\">\n";

  print "<CENTER>";
  print "<TABLE class=\"tabtop10\">";
  print "<TR><TD align=\"center\"> <b>Last day</b> </TD><TD  align=\"center\"> <b>Last week</b> </TD></TR>";

  print "<TR style=\"vertical-align:top\">";
  print_topten( "1", "$server_url" );             #day
  print_topten( "2", "$server_url" );             #week
  print "<TR>";
  print "<TR><TD align=\"center\"> <br><br><b>Last month</b> </TD><TD  align=\"center\"> <br><br><b>Last year</b> </TD></TR>";
  print "<TR style=\"vertical-align:top\">";
  print_topten( "3", "$server_url" );             #month
  print_topten( "4", "$server_url" );             #year
  print "</TR></TABLE>";
  print "</center>";
  print "</div>\n";
  print "</center>";

  print "<div><br>Note that this page is refreshed once a day, the first LPAR2RRD run after midnight";
  print "<br>If you want to have different number of lpars here like top 100 etc, then modify parameter TOPTEN=$topten_limit in etc/lpar2rrd.cfg";
  my $file = "$tmpdir/topten.tmp";
  if ( !-f $file ) {
    error("File $file does not exists(first run after midnight create it)") && return;
  }
  my $last_mod_time = ( stat($file) )[9];
  print "<br>Updated: ";
  print scalar localtime $last_mod_time;
  print "<br></div>";

  print "</div><br>\n";

  return 1;
}

sub print_topten_hyperv {
  my ( $host_url, $server_url, $lpar_url, $item, $entitle ) = @_;
  my $topten_limit = 0;
  if ( defined $ENV{TOPTEN} ) {
    $topten_limit = $ENV{TOPTEN};
  }
  $topten_limit = 50 if $topten_limit < 1;
  my $file_hyperv = "$tmpdir/topten_hyperv.tmp";
  my $last_update = localtime( ( stat($file_hyperv) )[9] );

  #print_topten_head ($server_url,$host_url);
  #print_topten_head ($server,$host_url);

  print "<div  id=\"tabs\">\n";
  print "<CENTER>";

  print "<ul>\n";
  print "  <li class=\"tabhmc\"><a href=\"#tabs-1\">Last Day</a></li>\n";

  print "  <li class=\"tabhmc\"><a href=\"#tabs-2\">Last Week</a></li>\n";

  print "  <li class=\"tabhmc\"><a href=\"#tabs-3\">Last Month</a></li>\n";

  print "  <li class=\"tabhmc\"><a href=\"#tabs-4\">Last Year</a></li>\n";

  print "</ul>\n";

  # last day
  print "<div id=\"tabs-1\">\n";
  print "<table align=\"center\" summary=\"Graphs\">\n";
  print "<tr><th align=center>CPU in cores<a class=\"csvfloat\" href=\"/lpar2rrd-cgi/top10_csv.sh?LPAR=$server_url&host=CSV&type=HYPERV&table=topten&item=load_cpu&period=1\" title=\"LOAD CPU CSV\"><img src=\"css/images/csv.gif\"></a></th><th align=center>NET in MB/sec<a class=\"csvfloat\" href=\"/lpar2rrd-cgi/top10_csv.sh?LPAR=$server_url&host=CSV&type=HYPERV&table=topten&item=net&period=1\" title=\"NET CSV\"><img src=\"css/images/csv.gif\"></a></th><th align=center>DISK in MB/sec<a class=\"csvfloat\" href=\"/lpar2rrd-cgi/top10_csv.sh?LPAR=$server_url&host=CSV&type=HYPERV&table=topten&item=disk&period=1\" title=\"DISK CSV\"><img src=\"css/images/csv.gif\"></a></th></tr>";
  print "<tr style=\"vertical-align:top\">";
  print_top10_to_table_hyperv( "1", "$server_url", "load_cpu" );
  print_top10_to_table_hyperv( "1", "$server_url", "net" );
  print_top10_to_table_hyperv( "1", "$server_url", "disk" );
  print "</tr>";
  print "</table>";
  print "<tfoot><tr><td colspan=\"6\">Last update time: $last_update</td></tr></tfoot>";
  print "</div>\n";

  # last week
  print "<div id=\"tabs-2\">\n";
  print "<table align=\"center\" summary=\"Graphs\">\n";
  print "<tr><th align=center>CPU in cores<a class=\"csvfloat\" href=\"/lpar2rrd-cgi/top10_csv.sh?LPAR=$server_url&host=CSV&type=HYPERV&table=topten&item=load_cpu&period=2\" title=\"LOAD CPU CSV\"><img src=\"css/images/csv.gif\"></a></th><th align=center>NET in MB/sec<a class=\"csvfloat\" href=\"/lpar2rrd-cgi/top10_csv.sh?LPAR=$server_url&host=CSV&type=HYPERV&table=topten&item=net&period=2\" title=\"NET CSV\"><img src=\"css/images/csv.gif\"></a></th><th align=center>DISK in MB/sec<a class=\"csvfloat\" href=\"/lpar2rrd-cgi/top10_csv.sh?LPAR=$server_url&host=CSV&type=HYPERV&table=topten&item=disk&period=2\" title=\"DISK CSV\"><img src=\"css/images/csv.gif\"></a></th></tr>";
  print "<tr style=\"vertical-align:top\">";
  print_top10_to_table_hyperv( "2", "$server_url", "load_cpu" );
  print_top10_to_table_hyperv( "2", "$server_url", "net" );
  print_top10_to_table_hyperv( "2", "$server_url", "disk" );
  print "</tr>";
  print "</table>";
  print "<tfoot><tr><td colspan=\"6\">Last update time: $last_update</td></tr></tfoot>";
  print "</div>\n";

  # last month
  print "<div id=\"tabs-3\">\n";
  print "<table align=\"center\" summary=\"Graphs\">\n";
  print "<tr><th align=center>CPU in cores<a class=\"csvfloat\" href=\"/lpar2rrd-cgi/top10_csv.sh?LPAR=$server_url&host=CSV&type=HYPERV&table=topten&item=load_cpu&period=3\" title=\"LOAD CPU CSV\"><img src=\"css/images/csv.gif\"></a></th><th align=center>NET in MB/sec<a class=\"csvfloat\" href=\"/lpar2rrd-cgi/top10_csv.sh?LPAR=$server_url&host=CSV&type=HYPERV&table=topten&item=net&period=3\" title=\"NET CSV\"><img src=\"css/images/csv.gif\"></a></th><th align=center>DISK in MB/sec<a class=\"csvfloat\" href=\"/lpar2rrd-cgi/top10_csv.sh?LPAR=$server_url&host=CSV&type=HYPERV&table=topten&item=disk&period=3\" title=\"DISK CSV\"><img src=\"css/images/csv.gif\"></a></th></tr>";
  print "<tr style=\"vertical-align:top\">";
  print_top10_to_table_hyperv( "3", "$server_url", "load_cpu" );
  print_top10_to_table_hyperv( "3", "$server_url", "net" );
  print_top10_to_table_hyperv( "3", "$server_url", "disk" );
  print "</tr>";
  print "</table>";
  print "<tfoot><tr><td colspan=\"6\">Last update time: $last_update</td></tr></tfoot>";
  print "</div>\n";

  # last year
  print "<div id=\"tabs-4\">\n";
  print "<table align=\"center\" summary=\"Graphs\">\n";
  print "<tr><th align=center>CPU in cores<a class=\"csvfloat\" href=\"/lpar2rrd-cgi/top10_csv.sh?LPAR=$server_url&host=CSV&type=HYPERV&table=topten&item=load_cpu&period=4\" title=\"LOAD CPU CSV\"><img src=\"css/images/csv.gif\"></a></th><th align=center>NET in MB/sec<a class=\"csvfloat\" href=\"/lpar2rrd-cgi/top10_csv.sh?LPAR=$server_url&host=CSV&type=HYPERV&table=topten&item=net&period=4\" title=\"NET CSV\"><img src=\"css/images/csv.gif\"></a></th><th align=center>DISK in MB/sec<a class=\"csvfloat\" href=\"/lpar2rrd-cgi/top10_csv.sh?LPAR=$server_url&host=CSV&type=HYPERV&table=topten&item=disk&period=4\" title=\"DISK CSV\"><img src=\"css/images/csv.gif\"></a></th></tr>";
  print "<tr style=\"vertical-align:top\">";
  print_top10_to_table_hyperv( "4", "$server_url", "load_cpu" );
  print_top10_to_table_hyperv( "4", "$server_url", "net" );
  print_top10_to_table_hyperv( "4", "$server_url", "disk" );
  print "</tr>";
  print "</table>";
  print "<tfoot><tr><td colspan=\"6\">Last update time: $last_update</td></tr></tfoot>";
  print "</div>\n";
}

sub print_top10_to_table_hyperv {
  my ( $period, $server_pool, $item_name ) = @_;
  my $topten_file_hyperv = "$tmpdir/topten_hyperv.tmp";
  my $html_tab_header    = sub {
    my @columns = @_;
    my $result  = '';
    $result .= "<center>";
    $result .= "<table style=\"white-space: nowrap;\" class=\"tabconfig tablesorter \" data-sortby='1'>";
    $result .= "<thead><tr>";
    foreach my $item (@columns) {
      $result .= "<th class=\"sortable\">" . $item . "</th>";
    }
    $result .= "</tr></thead>";
    $result .= "<tbody>";
    return $result;
  };
  my $html_table_row = sub {
    my @cells  = @_;
    my $result = '';

    $result .= "<tr>";
    foreach my $cell (@cells) { $result .= "<td>" . $cell . "</td>"; }
    $result .= "</tr>";

    return $result;
  };

  # Table or create CSV file
  my $csv_file;
  if ( $item_name eq "load_cpu" ) {
    $csv_file = "hyperv-load-cpu.csv";
  }
  elsif ( $item_name eq "cpu_perc" ) {
    $csv_file = "hyperv-cpu-perc.csv";
  }
  elsif ( $item_name eq "net" ) {
    $csv_file = "hyperv-net.csv";
  }
  elsif ( $item_name eq "disk" ) {
    $csv_file = "hyperv-disk.csv";
  }
  if ( !$csv ) {
    if ( $item_name eq "load_cpu" or $item_name eq "cpu_perc" ) {
      print "<TD><TABLE class=\"tabconfig tablesorter\" data-sortby=\"1\">";
      if ( $period == 4 ) {    # last year
        print $html_tab_header->( 'Avrg', "VM", 'Domain name' );
      }
      else {
        print $html_tab_header->( 'Avrg', 'Max', "VM", 'Domain name' );
      }
    }
    elsif ( $item_name eq "net" ) {
      print "<TD><TABLE class=\"tabconfig tablesorter\" data-sortby=\"1\">";
      if ( $period == 4 ) {    # last year
        print $html_tab_header->( 'Avrg', "VM", 'Domain name' );
      }
      else {
        print $html_tab_header->( 'Avrg', 'Max', "VM", 'Domain name' );
      }
    }
    elsif ( $item_name eq "disk" ) {
      print "<TD><TABLE class=\"tabconfig tablesorter\" data-sortby=\"1\">";
      if ( $period == 4 ) {    # last year
        print $html_tab_header->( 'Avrg', "VM", 'Domain name' );
      }
      else {
        print $html_tab_header->( 'Avrg', 'Max', "VM", 'Domain name' );
      }
    }
  }
  else {
    print "Content-Disposition: attachment;filename=\"$csv_file\"\n\n";
    my $csv_header = "";
    if ( $period == 4 ) {    # last year
      $csv_header = "Avrg" . "$sep" . "VM" . "$sep" . "Domain name\n";
    }
    else {
      $csv_header = "Avrg" . "$sep" . "Max" . "$sep" . "VM" . "$sep" . "Domain name\n";
    }
    print "$csv_header";
  }
  my @topten;
  my @topten_not_sorted;
  my @topten_sorted;
  my $topten_limit = 0;
  my @top_values_avrg;
  my @top_values_max;
  if ( -f $topten_file_hyperv ) {
    open( FH, " < $topten_file_hyperv" ) || error( "Cannot open $topten_file_hyperv: $!" . __FILE__ . ":" . __LINE__ );
    @topten = <FH>;
    close FH;
    if ( defined $ENV{TOPTEN} ) {
      $topten_limit = $ENV{TOPTEN};
    }
    $topten_limit = 50 if $topten_limit < 1;
    my @topten_server;
    if ( $item_name eq "load_cpu" ) {
      @topten_server = grep {/cpu_util,/} @topten;
    }
    elsif ( $item_name eq "cpu_perc" ) {
      @topten_server = grep {/cpu_perc,/} @topten;
    }
    elsif ( $item_name eq "net" ) {
      @topten_server = grep {/net,/} @topten;
    }
    elsif ( $item_name eq "disk" ) {
      @topten_server = grep {/disk,/} @topten;
    }
    @topten = @topten_server;
    foreach my $line (@topten) {
      chomp $line;
      my ( $item, $vm_name, $domain_name );
      ( $item, $vm_name, $domain_name, $top_values_avrg[1], $top_values_max[1], $top_values_avrg[2], $top_values_max[2], $top_values_avrg[3], $top_values_max[3], $top_values_avrg[4], $top_values_max[4] ) = split( ",", $line );
      $top_values_avrg[4] = 0 if !defined $top_values_avrg[4] or $top_values_avrg[4] eq "";    # no year value yet, new file
      $top_values_max[4]  = 0 if !defined $top_values_max[4]  or $top_values_max[4] eq "";     # no year value yet, new file
                                                                                               #if ( $top_values_avrg[1] == 0 && $top_values_max[1] == 0 && $top_values_avrg[2] == 0 && $top_values_max[2] == 0 && $top_values_avrg[3] == 0 && $top_values_max[3] == 0 && $top_values_avrg[4] == 0 && $top_values_max[4] == 0 ) { next; }
      push @topten_not_sorted, "$item,$top_values_avrg[$period],$top_values_max[$period],$vm_name,$domain_name\n";
    }
    {
      no warnings;
      @topten_sorted = sort { $b <=> $a } @topten_not_sorted;
    }
  }
  my @topten_sorted_load_cpu;
  {
    no warnings;
    @topten_sorted_load_cpu = sort {
      my @b = split( /,/, $b );
      my @a = split( /,/, $a );

      #print "$b[4] --- $a[4]\n";
      $b[1] <=> $a[1]
    } @topten_sorted;
  }
  foreach my $line1 (@topten_sorted_load_cpu) {
    my ( $item_a, $load_cpu, $load_peak, $vm_name, $domain_name );
    ( $item_a, $load_cpu, $load_peak, $vm_name, $domain_name ) = split( ",", $line1 );
    if ( !$csv ) {
      if ( $period == 4 ) {    # last year
        print $html_table_row->( $load_cpu, $vm_name, $domain_name );
      }
      else {
        print $html_table_row->( $load_cpu, $load_peak, $vm_name, $domain_name );
      }
    }
    else {
      if ( $period == 4 ) {    # last year
        print "$load_cpu" . "$sep" . "$vm_name" . "$sep" . "$domain_name";
      }
      else {
        print "$load_cpu" . "$sep" . "$load_peak" . "$sep" . "$vm_name" . "$sep" . "$domain_name";
      }
    }
  }
  if ( !$csv ) {
    print "</TABLE></TD>";
  }
  return 1;
}

sub print_data_check {
  my ( $host_url, $server_url, $lpar_url, $item, $entitle ) = @_;
  my $vmotion_config = "$tmpdir/lpar_start_counter.txt";
  my $hyptmp         = "$tmpdir/HYPERV";

  print "<div  id=\"tabs\">\n";
  print "<CENTER>";

  print "<ul>\n";
  print "  <li ><a href=\"/lpar2rrd-cgi/detail.sh?host=&server=&lpar=&item=data_check_div1\">OS agent check</a></li>\n";
  print "  <li ><a href=\"/lpar2rrd-cgi/detail.sh?host=&server=&lpar=&item=data_check_div2\">Data check</a></li>\n";
  print "  <li ><a href=\"/lpar2rrd-cgi/detail.sh?host=&server=&lpar=&item=data_check_div3\">IBM i</a></li>\n";
  if ( -f $vmotion_config ) {
    print "  <li ><a href=\"/lpar2rrd-cgi/detail.sh?host=&server=&lpar=&item=data_check_div4\">VMotion TOP</a></li>\n";
  }
  if ( -d $hyptmp ) {
    print "  <li ><a href=\"/lpar2rrd-cgi/detail.sh?host=&server=&lpar=&item=data_check_div5\">WIN Agent</a></li>\n";
  }
  print "</ul>\n";

  print "</div><br>\n";
  return 1;
}

sub print_data_check_div {
  my $vmotion_config = "$tmpdir/lpar_start_counter.txt";

  if ( $item eq "data_check_div2" ) {
    print "<div id=\"tabs-2\">\n";
    my $file_html = "$webdir/daily_lpar_check.html";
    if ( -f "$file_html" ) {
      open( FH, "< $file_html" );
      my $dlch_html = do { local $/; <FH> };
      close(FH);
      print "$dlch_html";
    }
    print "</div>\n";
  }
  elsif ( $item eq "data_check_div1" ) {
    print "<div id=\"tabs-1\">\n";
    my $file_html = "$webdir/daily_agent_check.html";
    if ( -f "$file_html" ) {
      open( FH, "< $file_html" );
      my $dlch_html = do { local $/; <FH> };
      close(FH);
      print "$dlch_html";
    }
    print "</div>\n";
  }
  elsif ( $item eq "data_check_div3" ) {
    print "<div id=\"tabs-3\">\n";
    print "<center><h4>Table IBM i</h4>
    <table><tbody><tr><td><table class =\"tabconfig tablesorter\">
    <thead><tr><th class = \"sortable\">Server&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;</th>
             <th class = \"sortable\">LPAR&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;</th>
             <th class = \"sortable\">Agent status&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;</th>
             <th class = \"sortable\">Version&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;</th>
             <th class = \"sortable\">License expiration&nbsp;&nbsp;</th></tr></thead><tbody>";
    print "</td></tr>\n";

    # read tmp/daily_lpar_check.txt for agent i status
    my @daily_lpar_check      = ();
    my $daily_lpar_check_file = "$tmpdir/daily_lpar_check.txt";
    open( FH, "< $daily_lpar_check_file" ) || error( "Cannot open $daily_lpar_check_file: $!" . __FILE__ . ":" . __LINE__ );
    @daily_lpar_check = <FH>;
    close(FH);
    my $upd_time     = ( stat("$daily_lpar_check_file") )[9];
    my $upd_time_txt = localtime($upd_time);

    my %servers_lpars = ();
    my @files         = bsd_glob "$wrkdir/*/*/*--AS400--/license.cfg";
    my $act_time_u    = time();

    foreach my $file (@files) {
      my @dirs   = split( "\/", $file );
      my $lpar   = $dirs[-2];
      my $hmc    = $dirs[-3];
      my $server = $dirs[-4];
      next if -l "$wrkdir/$server";    # skip server sym link
      $lpar =~ s/--AS400--//;

      if ( -f "$wrkdir/$server/$hmc/cpu.cfg" ) {
        my $cpu_cfg_file = "$wrkdir/$server/$hmc/cpu.cfg";
        open( FH, "< $cpu_cfg_file" ) || error( "Cannot open $cpu_cfg_file: $!" . __FILE__ . ":" . __LINE__ ) && next;
        my @cpu_cfg = <FH>;
        close(FH);

        # looks like lpar_name=as400,lpar_id=6,curr_proc_mode=ded...
        my $test_string = "lpar_name=" . "$lpar" . ",";
        my @lpar_line   = grep {/^$test_string/} @cpu_cfg;
        next if !defined $lpar_line[0];
      }

      my $string_to_find = $server . "," . $hmc . "," . $lpar . ",agent";
      $server =~ s/--unknown//;
      next if exists $servers_lpars{ $server . $lpar };

      my $status = "not running";
      if ( ( $act_time_u - ( stat($file) )[9] ) < 86400 ) {
        $status = "running";
      }

      # read licence
      open( FH, "< $file" ) || error( "Cannot open $file: $!" . __FILE__ . ":" . __LINE__ ) && next;
      my $line = do { local $/; <FH> };
      close(FH);
      chomp $line;

      # read version
      $file =~ s/license\.cfg$/agent.cfg/;
      open( FH, "< $file" ) || error( "Cannot open $file: $!" . __FILE__ . ":" . __LINE__ ) && next;
      my $line_version = do { local $/; <FH> };
      close(FH);
      chomp $line_version;

      # older agent had bug in time - it looked: '43.940 version 1.1.5'
      if ( $line_version =~ /version/ ) {
        ( undef, $line_version ) = split( "version ", $line_version );
      }
      $line_version =~ s/\d\d\d\d.*$//;    # sometimes it contains date

      # my $status = "not updated";
      # my @agent_status = grep /$string_to_find/, @daily_lpar_check;

      # # print STDERR "2987 detail-cgi.pl \$agent_status[0] $agent_status[0]\n";
      # if ( defined $agent_status[0] && $agent_status[0] ne "" ) {
      #   if ( $agent_status[0] =~ "OK" ) {
      #     $status = "running";
      #   }
      #   else {
      #     $status = "not updated";
      #   }
      # } ## end if ( defined $agent_status...)

      print "<tr><td>$server</td><td>$lpar</td><td>$status</td><td>$line_version</td><td>$line</td></tr>\n";
      $servers_lpars{ $server . $lpar } = 1;
    }
    print "</tbody></table></table>\n";
    print "<center>\"not running\" is when agent data is older 24 hours<br></center>";
    print "The table has been updated at: $upd_time_txt<br></center>";
    print "</div>\n";
  }
  elsif ( $item eq "data_check_div4" ) {
    ### print VMOTION table
    if ( -f $vmotion_config ) {
      print "<div id=\"tabs-4\">\n";
      open( FC, "< $vmotion_config" ) || error( "Cannot read $vmotion_config: $!" . __FILE__ . ":" . __LINE__ );
      my @start = <FC>;
      close(FC);

      # remove first & last signal date line
      pop @start;
      shift @start;

      my $vmotion_limit = 100;
      if ( defined $ENV{VMOTION_TOPTEN} ) {
        $vmotion_limit = $ENV{VMOTION_TOPTEN};
      }

      # sort on total vmotions
      my @start_x      = sort { ( split( ';', $b ) )[3] <=> ( split( ';', $a ) )[3] } @start;
      my @chosen_lines = @start_x[ 0 .. $vmotion_limit - 1 ];

      # sort on daily vmotions
      @start_x      = ();
      @start_x      = sort { ( split( ';', $b ) )[4] <=> ( split( ';', $a ) )[4] } @start;
      @chosen_lines = ( @chosen_lines, @start_x[ 0 .. $vmotion_limit - 1 ] );

      # sort on weekly vmotions
      @start_x      = ();
      @start_x      = sort { ( split( ';', $b ) )[5] <=> ( split( ';', $a ) )[5] } @start;
      @chosen_lines = ( @chosen_lines, @start_x[ 0 .. $vmotion_limit - 1 ] );

      # sort on monthly vmotions
      @start_x      = ();
      @start_x      = sort { ( split( ';', $b ) )[6] <=> ( split( ';', $a ) )[6] } @start;
      @chosen_lines = ( @chosen_lines, @start_x[ 0 .. $vmotion_limit - 1 ] );

      # remove duplicate items
      my %hash = map { $_, 1 } @chosen_lines;
      @start = ();
      @start = keys %hash;

      print "<table><tbody><tr><td><table class =\"tablesorter\" data-sortby='3'>
      <thead><tr><th class= \"sortable\">vCenter</th>
               <th class= \"sortable\">VM</th>
               <th class= \"sortable\">VMotion total</th>
               <th class= \"sortable\">VMotion last day</th>
               <th class= \"sortable\">VMotion last week</th>
               <th class= \"sortable\">VMotion last month</th>
               </tr></thead>";

      #  print to html table
      foreach my $line (@start) {
        next if $line =~ /^\#/;
        ( my $vcenter_name, my $lpar, my $final_ahref, my $starts, my $last_day, my $last_week, my $last_month ) = split( /;/, $line );

        # print STDERR "9567 \$line ,$line,\$lpar ,$lpar,\n";
        # print STDERR "9568 $final_ahref<br>";
        my $lpar_item = "lpar=";
        ( my $start, undef ) = split( /lpar=/, $final_ahref );
        ( undef, my $end ) = split( /&item=/, $final_ahref );
        my $name_lpar = "$start$lpar_item$lpar&item=$end";
        print "<tr><td>$vcenter_name</td><td><a href=\"$name_lpar\">$lpar</a></td><td>$starts</td><td>$last_day</td><td>$last_week</td><td>$last_month</td></tr>";
      }
      print "</tbody></td></tr></table></table>";
      my $last_mod_time = localtime( ( stat($vmotion_config) )[9] );
      print "The table summarizes start-stops (vmotions) of VMs. Last week is without last day, last month is without last week. Updated: $last_mod_time";
      print "<br>If you want to have different number of VMs here like top 100 etc, then modify parameter VMOTION_TOPTEN=$vmotion_limit in etc/lpar2rrd.cfg";
      print "</div>\n";
    }
  }
  elsif ( $item eq "data_check_div5" ) {
    print "<div id=\"tabs-5\">\n";
    my $create_html = `\$PERL $basedir/bin/windows_gentable.pl`;
    my $file_html   = "$tmpdir/win_check.html";
    if ( -f "$file_html" ) {
      open( FH, "< $file_html" );
      my $dlch_html = do { local $/; <FH> };
      close(FH);
      print "$dlch_html";
    }
    print "</div>\n";
  }
  return 1;
}

sub print_data_servers {
  $rest_api = is_any_host_rest();
  if ( !$rest_api ) {    #use old config page
    my ( $host_url, $server_url, $lpar_url, $item, $entitle ) = @_;
    my @hmc_list  = <$webdir/*\/gui-config-high-sum.html>;
    my $hmc_count = @hmc_list;
    return 0 if !$hmc_count;    # no hmc ?

    my $cvs_lpar   = "lpar-config.csv";
    my $cvs_server = "server-config.csv";

    print "<div  id=\"tabs\">\n";
    print "<CENTER>";

    print "<ul>\n";
    print "  <li ><a href=\"#tabs-1\">Servers</a></li>\n";
    print "  <li ><a href=\"#tabs-2\">LPARs</a></li>\n";

    for ( my $i = 0; $i < $hmc_count; $i++ ) {
      my $hmc_path = $hmc_list[$i];
      my @hmcx     = split( "/", $hmc_path );
      my $my_hmc   = @hmcx[ @hmcx - 2 ];
      my $index    = $i + 1;
      print "  <li class=\"hmcsum\"><a href=\"#tabs-$index-a\">$my_hmc</a></li>\n";
      print "  <li class=\"hmcdet\"><a href=\"#tabs-$index-b\">$my_hmc</a></li>\n";
    }

    print "</ul>\n";

    print "<div id=\"tabs-1\">\n";
    my $file_html = "$webdir/cfg_summary.html";
    my $print_html;
    if ( -f "$file_html" ) {
      open( FH, "< $file_html" );
      $print_html = do { local $/; <FH> };
      close(FH);
      print "$print_html";
    }
    my $host = "";
    print "<a href=\"$cvs_lpar\"><div class=\"csvexport\">CSV LPAR</div></a>";
    print "<a href=\"$cvs_server\"><div class=\"csvexport csvexport_down\">CSV Server</div></a>";
    print "</div>\n";

    #VM table
    print "<div id=\"tabs-2\">\n";
    lpars_table();
    print "</div>\n";

=begin comment table
  #VM table
  print "<div id=\"tabs-2\">\n";
  print "<h4> LPARs Table </h4>\n";
  my $metrics = ['lpar_name','lpar_id','curr_sharing_mode','curr_proc_mode','curr_procs','curr_min_procs','curr_max_procs','curr_proc_units','mem_mode','curr_mem','curr_min_mem','curr_max_mem','run_mem','run_min_mem','curr_shared_proc_pool_name'];
  my @files_lpars_per_server = <$basedir/tmp/restapi/HMC_LPARS*.json>;
      print '<table style="width:90%;" class="tablesorter" data-sortby="1 2">
  <thead>
   <TR>
     <TH align="center" class="sortable" valign="center">server</TH>';
     for (@{$metrics}){
       print '<TH align="center" class="sortable" valign="center">'.$_.'</TH>';
     }
  print' </TR>
  </thead>
  <tbody>';
  for (@files_lpars_per_server){
    my $file = $_;
    my $ftd = Xorux_lib::file_time_diff ($file);
    my $server_name = basename($file);
    $server_name =~ s/^.*LPARS_//g;
    $server_name =~ s/_conf\.json$//g;
    if ($ftd <= 86400){
      my $content = Xorux_lib::read_json("$file") if ( -e "$file");
      for (keys %{ $content }){
        my $lpar_name = $_;
        if (!defined $server_name) { $server_name = ""; }
        for (@{$metrics}){
          if (!defined $content->{$lpar_name}{$_}) { $content->{$lpar_name}{$_} = ""; }
        }
        print '<TR>';
        print '  <TH align="center" valign="center">'.$server_name.' </TH>';
        for (@{$metrics}){
          print '    <TH align="center" valign="center">'.$content->{$lpar_name}{$_} . ' </TH>';
        }
        print '  </TR>';
      }
    }
  }
  print "</tbody>\n";
  print "</table>\n";
  print "</div>\n";
=cut

    for ( my $i = 0; $i < $hmc_count; $i++ ) {

      my $hmc_path = $hmc_list[$i];
      my @hmcx     = split( "/", $hmc_path );
      my $my_hmc   = @hmcx[ @hmcx - 2 ];
      my $index    = $i + 1;

      print "<div id=\"tabs-$index-a\">\n";
      if ( -f "$hmc_path" ) {
        open( FH, "< $hmc_path" );
        my $print_html = do { local $/; <FH> };
        close(FH);
        print "$print_html";
      }
      print "<a href=\"$my_hmc/$my_hmc-$cvs_server\"><div class=\"csvexport\">CSV Server</div></a>";
      print "</div>\n";

      print "<div id=\"tabs-$index-b\">\n";
      $hmc_path =~ s/-sum//;
      if ( -f "$hmc_path" ) {
        open( FH, "< $hmc_path" );
        my $print_html = do { local $/; <FH> };
        close(FH);
        print "$print_html";
      }
      print "<a href=\"$my_hmc/$my_hmc-$cvs_lpar\"><div class=\"csvexport\">CSV LPAR</div></a>";

      print "</div>\n";
    }

    print "</div><br>\n";

    return 1;
  }
  else {    #use new config page - wip
    my $cli_conf = 0;
    my ( $host_url, $server_url, $lpar_url, $item, $entitle ) = @_;

    my $hmc_list_new = `\$PERL $basedir/bin/hmc_list.pl --all`;
    my @hmc_list_new = split( " ", $hmc_list_new );
    my $hmc_count    = @hmc_list_new;

    return 0 if !$hmc_count;    # no hmc ?

    my $cvs_lpar            = "lpar-config.csv";
    my $cvs_server          = "server-config.csv";
    my $cvs_lpar_rest       = "lpar-config-rest.csv";
    my $cvs_server_rest     = "server-config-rest.csv";
    my $cvs_npiv_rest       = "npiv-config-rest.csv";
    my $cvs_vscsi_rest      = "vscsi-config-rest.csv";
    my $cvs_interfaces_rest = "interfaces-config-rest.csv";

    print "<div  id=\"tabs\">\n";
    print "<CENTER>";
    print "<ul>\n";
    my $tab_index = 1;
    print "  <li ><a href=\"#tabs-$tab_index\">Servers</a></li>\n";
    $tab_index++;
    print "  <li ><a href=\"#tabs-$tab_index\">LPARs</a></li>\n";
    $tab_index++;

    if ( -e "$webdir/enterprise_pool.html" ) {
      print "  <li ><a href=\"#tabs-$tab_index\">Enterprise Pool</a></li>\n";
      $tab_index++;
    }

    print "  <li ><a href=\"#tabs-$tab_index\">Volume ID</a></li>\n";
    $tab_index++;

    #my @files_interfaces = <$webdir/interfaces*.html>;
    #if (defined $files_interfaces[0]){
    #  print "  <li ><a href=\"#tabs-$tab_index\">Interfaces</a></li>\n"; $tab_index++;
    #}
    my @files_env_conf = <$basedir/tmp/restapi/env_conf_*.json>;
    if ( defined $files_env_conf[0] ) {
      print "  <li ><a href=\"#tabs-$tab_index\">Interfaces</a></li>\n";
      $tab_index++;
    }

    my $show_cli = 0;
    if ( -e "$webdir/cfg_summary.html" ) {
      $show_cli = `grep -i 'href' $webdir/cfg_summary.html | wc | sed -e 's/^ *//g' | sed -e 's/ .*//g'`;
      chomp $show_cli;

      if ($show_cli) {
        my $act_time    = time();
        my $last_update = ( stat("$webdir/cfg_summary.html") )[9];

        #   my $last_update = stat("$webdir/cfg_summary.html");
        $cli_conf = $act_time - $last_update;
        if ( $cli_conf <= 86400 ) {
          print "  <li ><a href=\"#tabs-$tab_index\">CLI Config</a></li>\n";
          $tab_index++;
        }
      }
    }

    my $file_net_conf = "$basedir/tmp/restapi/net_conf.json";
    if ( -e "$file_net_conf" ) {
      print "  <li ><a href=\"#tabs-$tab_index\">Network Configuration</a></li>\n";
      $tab_index++;
    }
    my @files_vscsi_conf = <$basedir/tmp/restapi/vscsi_conf_*.json>;
    if ( defined $files_vscsi_conf[0] && $files_vscsi_conf[0] ne "" ) {
      print "  <li ><a href=\"#tabs-$tab_index\">VSCSI</a></li>\n";
      $tab_index++;
    }
    my $file_npiv_conf = "$basedir/tmp/restapi/npiv_conf.json";
    if ( -e "$file_npiv_conf" || $ENV{DEMO} ) {
      print "  <li ><a href=\"#tabs-$tab_index\">NPIV</a></li>\n";
      $tab_index++;
    }
    my @files_vlan_conf = <$basedir/tmp/restapi/*__vnet__*.json>;
    if ( defined $files_vlan_conf[0] && $files_vlan_conf[0] ne "" ) {
      print "  <li ><a href=\"#tabs-$tab_index\">VLAN</a></li>\n";
      $tab_index++;
    }
    my @files_sea_conf = <$basedir/tmp/restapi/*__sea__*.json>;
    if ( defined $files_sea_conf[0] && $files_sea_conf[0] ne "" ) {
      print "  <li ><a href=\"#tabs-$tab_index\">SEA</a></li>\n";
      $tab_index++;
    }
    my @files_loadgroups_conf = <$basedir/tmp/restapi/*__loadgroups__*.json>;
    if ( defined $files_loadgroups_conf[0] && $files_loadgroups_conf[0] ne "" ) {
      print "  <li ><a href=\"#tabs-$tab_index\">Load Groups</a></li>\n";
      $tab_index++;
    }

    my @details = <$webdir/*\/*\/detail.html>;
    my @servers;

=begin config tabs
  foreach my $det (@details){
    my ($host, $server) = split ("www/", $det);
    ($server, undef) = split ('/detail.html',$server);
    ($host,$server) = split ('/', $server);
    if ( grep( /^$server$/, @servers )) {
      next;
    }
    push(@servers, $server);
    print "  <li ><a href=\"#tabs-$tab_index\">$server</a></li>\n"; $tab_index++;
  }
=cut

    print "</ul>\n";
    $tab_index = 1;
    print "<div id=\"tabs-$tab_index\">\n";
    $tab_index++;

    #my $file_html_rest = "$webdir/config_servers.html";
    my $file_html_rest = "$webdir/config_table_main.html";
    my $print_html;
    if ( -f "$file_html_rest" ) {
      open( FH, "< $file_html_rest" );
      $print_html = do { local $/; <FH> };
      close(FH);
      print "$print_html";
    }
    my $test = 0;
    my $host = "";
    if ( is_all_host_rest() ) {

      #print "<a href=\"$cvs_lpar_rest\"><div class=\"csvexport\">CSV LPAR Rest</div></a>"                              if ( -e "$webdir/$cvs_lpar_rest" );
      print "<a href=\"$cvs_server_rest\"><div class=\"csvexport\">CSV Server Rest</div></a>" if ( -e "$webdir/$cvs_server_rest" );

      #print "<a href=\"$cvs_npiv_rest\"><div class=\"csvexport csvexport_down_3\">CSV npiv Rest</div></a>"             if ( -e "$webdir/$cvs_npiv_rest" );
      #print "<a href=\"$cvs_vscsi_rest\"><div class=\"csvexport csvexport_down_4\">CSV vscsi Rest</div></a>"           if ( -e "$webdir/$cvs_vscsi_rest" );
      #print "<a href=\"$cvs_interfaces_rest\"><div class=\"csvexport csvexport_down_5\">CSV interfaces Rest</div></a>" if ( -e "$webdir/$cvs_interfaces_rest" );
    }
    elsif ( is_any_host_rest() && !is_all_host_rest() ) {
      print "<a href=\"$cvs_lpar\"><div class=\"csvexport\">CSV LPAR</div></a>"                    if ( -e "$webdir/$cvs_lpar" );
      print "<a href=\"$cvs_server\"><div class=\"csvexport csvexport_down\">CSV Server</div></a>" if ( -e "$webdir/$cvs_server" );

      #print "<a href=\"$cvs_lpar_rest\"><div class=\"csvexport csvexport_down_3\">CSV LPAR Rest</div></a>"             if ( -e "$webdir/$cvs_lpar_rest" );
      print "<a href=\"$cvs_server_rest\"><div class=\"csvexport csvexport_down_3\">CSV Server Rest</div></a>" if ( -e "$webdir/$cvs_server_rest" );

      #print "<a href=\"$cvs_npiv_rest\"><div class=\"csvexport csvexport_down_5\">CSV npiv Rest</div></a>"             if ( -e "$webdir/$cvs_npiv_rest" );
      #print "<a href=\"$cvs_vscsi_rest\"><div class=\"csvexport csvexport_down_6\">CSV vscsi Rest</div></a>"           if ( -e "$webdir/$cvs_vscsi_rest" );
      #print "<a href=\"$cvs_interfaces_rest\"><div class=\"csvexport csvexport_down_7\">CSV interfaces Rest</div></a>" if ( -e "$webdir/$cvs_interfaces_rest" );
    }
    else {
      print "<a href=\"$cvs_lpar_rest\"><div class=\"csvexport csvexport\">CSV LPAR Rest</div></a>" if ( -e "$webdir/$cvs_lpar_rest" );

      #print "<a href=\"$cvs_server_rest\"><div class=\"csvexport csvexport_down\">CSV Server Rest</div></a>" if ( -e "$webdir/$cvs_server_rest" );
    }
    print "</CENTER>\n";

    #VM table
    print "<div id=\"tabs-$tab_index\">\n";
    print "<a href=\"$cvs_lpar_rest\"><div class=\"csvexport\">CSV LPAR Rest</div></a>" if ( -e "$webdir/$cvs_lpar_rest" );
    $tab_index++;
    lpars_table();
    print "</div>\n";

    #Enterprise pool tab
    my $file_html_enterprise = "$webdir/enterprise_pool.html";
    if ( -f "$file_html_enterprise" ) {
      print "<center>";
      print "<div id=\"tabs-$tab_index\">\n";
      $tab_index++;
      open( FH, "< $file_html_enterprise" );
      $print_html = do { local $/; <FH> };
      close(FH);
      print "$print_html";
      print "</div>\n";
      print "</center>";
    }

    ( my $SRV, my $CNF ) = PowerDataWrapper::init();

    my $lpars;
    my $hdisks = {};
    my $tested = {};
    foreach my $vm_uid ( keys %{ $CNF->{vms} } ) {
      my $name  = $CNF->{vms}{$vm_uid}{name};
      my @ids   = defined $CNF->{vms}{$vm_uid}{disk_uids}  ? split( " ", $CNF->{vms}{$vm_uid}{disk_uids} )  : ();
      my @types = defined $CNF->{vms}{$vm_uid}{disk_types} ? split( " ", $CNF->{vms}{$vm_uid}{disk_types} ) : ();
      my $index = 0;
      foreach my $id (@ids) {
        my %disk;
        $disk{type} = $types[$index];
        $disk{id}   = $ids[$index];
        if ( $disk{type} =~ m/hdisk/ ) {
          push @{ $hdisks->{ $disk{type} } }, \%disk;
        }
        if ( !defined $tested->{ $disk{id} } ) {
          push @{ $lpars->{$name} }, \%disk;
          $tested->{ $disk{id} } = 1;
        }
        $index++;
      }
    }

    my $env_conf         = "$ENV{INPUTDIR}/tmp/restapi/env_conf.json";
    my $env_conf_content = Xorux_lib::read_json($env_conf);

    #Server;VIOS;VIOSAdapter;ServerSlot;ClientLPAR;ClientSlot;BackingDevice;VirtualDiskName;Partition;Capacity[GB];Label;VolumeName;Capacity[GB];State;LocationCode;

    my $csv = "$ENV{INPUTDIR}/www/vscsi-config-rest.csv";
    open( my $fh, "<", $csv ) || warn "Cannot open file $csv\n";
    readline $fh;
    my $vioses;
    while ( !eof($fh) ) {
      defined( $_ = readline $fh ) or warn "cannot read line $!\n" && last;
      my @record = split( ";", $_ );
      my $name   = $record[1];
      my $item   = {
        'vios_name'      => $name,
        'lpar_name'      => $record[4],
        'backing_device' => $record[6],
        'disk_name'      => $record[7],
        'partition'      => $record[8],
        'disk_capacity'  => $record[9]
      };

      push @{ $vioses->{$name} }, $item if (1);
    }

    my $out;

    $out->{lpars}  = $lpars;
    $out->{vioses} = $vioses;
    $out->{hdisks} = $hdisks;

    my $out2;

    for ( keys %{$vioses} ) {
      my $vios_key = $_;
      for ( @{ $vioses->{$vios_key} } ) {
        my $vio = $_;
        $out2->{lpars}{ $vio->{lpar_name} } = $vio;
        for ( keys %{$lpars} ) {
          push @{ $out2->{lpars}{ $vio->{lpar_name} }{disks} }, $lpars->{$_} if ( $vio->{lpar_name} eq $_ );
        }
      }
    }

    if ( defined $files_env_conf[0] ) {

      print "<CENTER>\n";
      print "<div id=\"tabs-$tab_index\">\n";
      $tab_index++;
      print '<TABLE style="width:90%;" class="tabconfig tablesorter" data-sortby="1">
      <thead>
      <TR>
        <TH align="center" class="sortable" valign="center">LPAR</TH>
        <TH align="center" class="sortable" valign="center">Disk</TH>
        <TH align="center" class="sortable" valign="center">Volume ID</TH>
      </TR>
      </thead>
      <tbody>';

      foreach my $lpar ( keys %{ $out2->{lpars} } ) {
        my $data = $out2->{lpars}{$lpar};
        if ( !( defined $data->{disks}->[0] && scalar @{ $data->{disks}->[0] } > 0 ) ) {
          next;
        }
        print "<tr>";
        print "<td>$lpar</td>";
        print "<td>";
        for ( @{ $data->{disks}->[0] } ) {
          my $disk = $_;
          print "$disk->{type}<br>\n";
        }
        print "</td>";
        print "<td>";

        for ( @{ $data->{disks}->[0] } ) {
          my $disk = $_;
          print "$disk->{id}<br>\n";
        }
        print "</td>";
        print "</tr>";
      }

      print '</tbody>';
      print '</TABLE>';

      print "<pre>";

      #print Dumper $out2;
      print "</pre>";
      print "</div>\n";
      print "</CENTER>\n";

      print "<CENTER>\n";
      print "<div id=\"tabs-$tab_index\">\n";
      print "<a href=\"$cvs_interfaces_rest\"><div class=\"csvexport \">CSV interfaces Rest</div></a>" if ( -e "$webdir/$cvs_interfaces_rest" );
      $tab_index++;
      if ( $ENV{DEMO} ) {
        print_html_file("$webdir/interfaces-formatted-demo.html");
      }
      else {
        print '<TABLE style="width:90%;" class="tabconfig tablesorter" data-sortby="1">
      <thead>
      <TR>
        <TH align="center" class="sortable" valign="center">Server</TH>
        <TH align="center" class="sortable" valign="center">Device Name</TH>
        <TH align="center" class="sortable" valign="center">Partition</TH>
        <TH align="center" class="sortable" valign="center">Ports</TH>
        <TH align="center" class="sortable" valign="center">WWPN</TH>
        <TH align="center" class="sortable" valign="center">Description</TH>
      </TR>
      </thead>
      <tbody>';
        my $done;
        foreach my $file_env_conf (@files_env_conf) {
          if ( -f "$file_env_conf" ) {
            my $env_conf = Xorux_lib::read_json("$file_env_conf");
            foreach my $server ( keys %{$env_conf} ) {
              foreach my $server_loc ( keys %{ $env_conf->{$server} } ) {
                foreach my $c ( keys %{ $env_conf->{$server}{$server_loc} } ) {
                  my $item = $env_conf->{$server}{$server_loc}{$c};
                  if ( !$done->{"$server_loc-$c"} ) {
                    if ( !defined $item->{'PartitionName'} ) { $item->{'PartitionName'} = ""; }
                    if ( !defined $item->{'WWPN'} )          { $item->{'WWPN'}          = ""; }
                    if ( !defined $item->{'Description'} )   { $item->{'Description'}   = ""; }
                    print "<TR>
                <TD>$server</TD>
                <TD>$server_loc-$c</TD>
                <TD>$item->{'PartitionName'}</TD>";
                    print "<TD>";

                    #                $item->{'Trunk'} = undef;
                    foreach my $Trunk ( sort keys %{ $item->{'Trunk'} } ) {
                      print "$Trunk";
                      print " / $item->{'Trunk'}{$Trunk}{'en_name'}" if ( defined $item->{'Trunk'}{$Trunk}{'en_name'} );
                      print "</br>\n";
                    }
                    print "</TD>";
                    print "<TD>$item->{'WWPN'}</TD>";
                    print "<TD>$item->{'Description'}</TD>";
                    print "</TR>\n";
                  }
                  $done->{"$server_loc-$c"} = 1;
                }
              }
            }

=pod
  foreach my $f (@files_interfaces){
    my $file_html_interfaces = $f;
    if ( -f "$file_html_interfaces") {
      open( FH, "< $file_html_interfaces" );
      (undef, $f) = split ("interfaces_", $f);
      ($f,undef) = split ('\.', $f);
      print "<h4>$f</h4>\n";
      $print_html = do { local $/; <FH> };
      close(FH);
      print "$print_html";
    } ## end if ( -f "$file_html_interfaces" )
  }
=cut

          }
        }
        print "
     </tbody>
    </TABLE>";
        print "</div>\n";
      }
      print "</CENTER>\n";
    }

    if ($show_cli) {
      my $file_html_cli_config = "$webdir/cfg_summary.html";
      if ( -f "$file_html_cli_config" && $cli_conf <= 86400 ) {
        print "<CENTER>\n";
        print "<div id=\"tabs-$tab_index\">\n";
        $tab_index++;
        open( FH, "< $file_html_cli_config" );
        $print_html = do { local $/; <FH> };
        close(FH);
        print "$print_html";
        print "</div>\n";
        print "</CENTER>\n";
      }
    }

    if ( -f "$file_net_conf" ) {
      my $net_json = Xorux_lib::read_json($file_net_conf);
      print "<CENTER>\n";
      print "<div id=\"tabs-$tab_index\">\n";
      $tab_index++;

      #Virtual Networks
      print '<TABLE style="width:90%;" class="tabconfig tablesorter" data-sortby="1">
  <thead>
   <TR>
     <TH align="center" class="sortable" valign="center">Server</TH>
     <TH align="center" class="sortable" valign="center">Vlan</TH>
     <TH align="center" class="sortable" valign="center">Tagged</TH>
     <TH align="center" class="sortable" valign="center">Switch UUID</TH>
     <TH align="center" class="sortable" valign="center">Vswitch ID</TH>
     <TH align="center" class="sortable" valign="center">Vlan ID</TH>
   </TR>
  </thead>
  <tbody>';
      print "<h3>VirtualNetwork</h3>\n";
      foreach my $s ( keys %{$net_json} ) {
        foreach my $vlan ( keys %{ $net_json->{$s}{VirtualNetwork} } ) {
          print "<TR>
              <TD>$s</TD>
              <TD>$vlan</TD>
              <TD>$net_json->{$s}{VirtualNetwork}{$vlan}{TaggedNetwork}</TD>
              <TD>$net_json->{$s}{VirtualNetwork}{$vlan}{AssociatedSwitchUUID}</TD>
              <TD>$net_json->{$s}{VirtualNetwork}{$vlan}{VswitchID}</TD>
              <TD>$net_json->{$s}{VirtualNetwork}{$vlan}{NetworkVLANID}</TD>
              </TR>\n";
        }
      }
      print "
     </tbody>
    </TABLE>";

      #end Virtual Networks

      #SEA
      print '<TABLE style="width:90%;" class="tabconfig tablesorter" data-sortby="1">
  <thead>
   <TR>
     <TH align="center" class="sortable" valign="center">Server</TH>
     <TH align="center" class="sortable" valign="center">Ent</TH>
     <TH align="center" class="sortable" valign="center">UniqueDeviceID</TH>
     <TH align="center" class="sortable" valign="center">ThreadModeEnabled</TH>
     <TH align="center" class="sortable" valign="center">LargeSend</TH>
     <TH align="center" class="sortable" valign="center">PortVLANID</TH>
     <TH align="center" class="sortable" valign="center">ConfigurationState</TH>
     <TH align="center" class="sortable" valign="center">JumboFramesEnabled</TH>
     <TH align="center" class="sortable" valign="center">QueueSize</TH>
     <TH align="center" class="sortable" valign="center">QualityOfServiceMode</TH>
     <TH align="center" class="sortable" valign="center">HighAvailabilityMode</TH>
     <TH align="center" class="sortable" valign="center">IPInterface</TH>
     <TH align="center" class="sortable" valign="center">IsPrimary</TH>
   </TR>
  </thead>
  <tbody>';
      print "<h3>SEA</h3>\n";
      foreach my $s ( keys %{$net_json} ) {
        foreach my $ent ( keys %{ $net_json->{$s}{SEA} } ) {
          print "<TR>
              <TD>$s</TD>
              <TD>$ent</TD>
              <TD>$net_json->{$s}{SEA}{$ent}{UniqueDeviceID}</TD>
              <TD>$net_json->{$s}{SEA}{$ent}{ThreadModeEnabled}</TD>
              <TD>$net_json->{$s}{SEA}{$ent}{LargeSend}</TD>
              <TD>$net_json->{$s}{SEA}{$ent}{PortVLANID}</TD>
              <TD>$net_json->{$s}{SEA}{$ent}{ConfigurationState}</TD>
              <TD>$net_json->{$s}{SEA}{$ent}{JumboFramesEnabled}</TD>
              <TD>$net_json->{$s}{SEA}{$ent}{QueueSize}</TD>
              <TD>$net_json->{$s}{SEA}{$ent}{QualityOfServiceMode}</TD>
              <TD>$net_json->{$s}{SEA}{$ent}{HighAvailabilityMode}</TD>
              <TD>$net_json->{$s}{SEA}{$ent}{IPInterface}</TD>
              <TD>$net_json->{$s}{SEA}{$ent}{IsPrimary}</TD>
            </TR>\n";
        }
      }
      print "
     </tbody>
    </TABLE>";

      #end SEA

      #Virtual Switch
      print '<TABLE style="width:90%;" class="tabconfig tablesorter" data-sortby="1">
  <thead>
   <TR>
     <TH align="center" class="sortable" valign="center">Server</TH>
     <TH align="center" class="sortable" valign="center">Switch</TH>
     <TH align="center" class="sortable" valign="center">SwitchID</TH>
     <TH align="center" class="sortable" valign="center">VlanIDs</TH>
   </TR>
  </thead>
  <tbody>';
      print "<h3>Virtual Switch</h3>\n";
      foreach my $s ( keys %{$net_json} ) {
        foreach my $switch_name ( keys %{ $net_json->{$s}{VirtualSwitch} } ) {
          print "<TR>
              <TD>$s</TD>
              <TD>$switch_name</TD>
              <TD>$net_json->{$s}{VirtualSwitch}{$switch_name}{SwitchID}</TD>";
          my $vlan_ids_string = "";
          foreach my $vlan ( keys %{ $net_json->{$s}{VirtualSwitch}{$switch_name}{SwitchVlans} } ) {
            $vlan_ids_string .= "$net_json->{$s}{VirtualSwitch}{$switch_name}{SwitchVlans}{$vlan}{NetworkVLANID},";
          }
          $vlan_ids_string =~ s/,$//g;
          print "<TD>$vlan_ids_string</TD>
            </TR>\n";
        }
      }
      print "
     </tbody>
    </TABLE>";

      #end VirtualSwitch

      #Trunk
      print '<TABLE style="width:90%;" class="tabconfig tablesorter" data-sortby="1">
  <thead>
   <TR>
     <TH align="center" class="sortable" valign="center">Server</TH>
     <TH align="center" class="sortable" valign="center">Ent</TH>
     <TH align="center" class="sortable" valign="center">MACAddress</TH>
     <TH align="center" class="sortable" valign="center">Location</TH>
     <TH align="center" class="sortable" valign="center">DynamicReconfigurationConnectorName</TH>
     <TH align="center" class="sortable" valign="center">VirtualSwitchID</TH>
     <TH align="center" class="sortable" valign="center">TrunkPriority</TH>
     <TH align="center" class="sortable" valign="center">PortVLANID</TH>
     <TH align="center" class="sortable" valign="center">VirtualSlotNumber</TH>
   </TR>
  </thead>
  <tbody>';
      print "<h3>Trunk</h3>\n";
      foreach my $s ( keys %{$net_json} ) {
        foreach my $ent ( keys %{ $net_json->{$s}{Trunk} } ) {
          print "<TR>
              <TD>$s</TD>
              <TD>$ent</TD>
              <TD>$net_json->{$s}{Trunk}{$ent}{MACAddress}</TD>
              <TD>$net_json->{$s}{Trunk}{$ent}{LocationCode}</TD>
              <TD>$net_json->{$s}{Trunk}{$ent}{DynamicReconfigurationConnectorName}</TD>
              <TD>$net_json->{$s}{Trunk}{$ent}{VirtualSwitchID}</TD>
              <TD>$net_json->{$s}{Trunk}{$ent}{TrunkPriority}</TD>
              <TD>$net_json->{$s}{Trunk}{$ent}{PortVLANID}</TD>
              <TD>$net_json->{$s}{Trunk}{$ent}{VirtualSlotNumber}</TD>
            </TR>\n";
        }
      }
      print "
     </tbody>
    </TABLE>";

      #end VirtualSwitch

      print "</div>\n";
      print "</CENTER>\n";
    }

    if ( defined $files_vscsi_conf[0] && $files_vscsi_conf[0] ne "" || $ENV{DEMO} ) {
      print "<center>";
      print "<div id=\"tabs-$tab_index\">\n";
      print "<a href=\"$cvs_vscsi_rest\"><div class=\"csvexport\">CSV vscsi Rest</div></a>" if ( -e "$webdir/$cvs_vscsi_rest" );
      $tab_index++;
      foreach my $file_vscsi_conf (@files_vscsi_conf) {
        if ( Xorux_lib::file_time_diff($file_vscsi_conf) > 90000 && !defined $ENV{DEMO} ) { next; }
        my $vscsi = Xorux_lib::read_json($file_vscsi_conf);
        ( undef, my $hmc ) = split( "vscsi_conf_", $file_vscsi_conf );
        ( $hmc, undef ) = split( "\.json", $hmc );

        #       print "<h4>$hmc servers</h4>\n";
        print '<TABLE style="width:90%;" class="tabconfig tablesorter" data-sortby="1 2">
  <thead>
   <TR>
     <TH align="center" class="sortable" valign="center">Server ' . "($hmc)" . '</TH>
     <TH align="center" class="sortable" valign="center">VIOS</TH>
     <TH align="center" class="sortable" valign="center">VIOS Adapter</TH>
     <TH align="center" class="sortable" valign="center">Server Slot</TH>
     <TH align="center" class="sortable" valign="center">Client LPAR</TH>
     <TH align="center" class="sortable" valign="center">Client Slot</TH>
     <TH align="center" class="sortable" valign="center">Backing Device</TH>
     <TH align="center" class="sortable" valign="center">Virtual Disk Name</TH>
     <TH align="center" class="sortable" valign="center">Partition [GB]</TH>
     <TH align="center" class="sortable" valign="center">Capacity [GB]</TH>
     <TH align="center" class="sortable" valign="center">Label</TH>
     <TH align="center" class="sortable" valign="center">Volume Name</TH>
     <TH align="center" class="sortable" valign="center">Capacity [GB]</TH>
     <TH align="center" class="sortable" valign="center">State</TH>
     <TH align="center" class="sortable" valign="center">Location Code</TH>
   </TR>
  </thead>
  <tbody>';
        if ( $ENV{DEMO} ) {
          print_html_file("$webdir/vscsi-demo.html");
        }
        else {
          foreach my $server_uid ( keys %{$vscsi} ) {
            if ( $server_uid eq "" ) { next; }
            if ( ref( $vscsi->{$server_uid} ) eq "ARRAY" ) {
              foreach my $map ( @{ $vscsi->{$server_uid} } ) {
                $map->{Storage}{VirtualDisk}{PartitionSize}     = sprintf( "%.1f", $map->{Storage}{VirtualDisk}{PartitionSize} )            if defined $map->{Storage}{VirtualDisk}{PartitionSize};
                $map->{Storage}{VirtualDisk}{DiskCapacity}      = sprintf( "%.1f", $map->{Storage}{VirtualDisk}{DiskCapacity} )             if defined $map->{Storage}{VirtualDisk}{DiskCapacity};
                $map->{Storage}{PhysicalVolume}{VolumeCapacity} = sprintf( "%.1f", $map->{Storage}{PhysicalVolume}{VolumeCapacity} / 1024 ) if defined $map->{Storage}{PhysicalVolume}{VolumeCapacity};
                if ( !defined $map->{Storage}{VirtualDisk}{DiskLabel} ) {
                  $map->{Storage}{VirtualDisk}{DiskLabel} = "";
                }
                print "<tr>";
                if   ( !defined $map->{ServerAdapter}{SystemName} ) { print "<TD></TD>\n"; }
                else                                                { print "<TD>$map->{ServerAdapter}{SystemName}</TD>\n"; }
                if   ( !defined $map->{ServerAdapter}{RemoteLogicalPartitionName} ) { print "<TD></TD>\n"; }
                else                                                                { print "<TD>$map->{ServerAdapter}{RemoteLogicalPartitionName}</TD>\n"; }
                if   ( !defined $map->{ServerAdapter}{AdapterName} ) { print "<TD></TD>\n"; }
                else                                                 { print "<TD>$map->{ServerAdapter}{AdapterName}</TD>\n"; }
                if   ( !defined $map->{ServerAdapter}{VirtualSlotNumber} ) { print "<TD></TD>\n"; }
                else                                                       { print "<TD>$map->{ServerAdapter}{VirtualSlotNumber}</TD>\n"; }
                if   ( !defined $map->{Partition} ) { print "<TD></TD>\n"; }
                else                                { print "<TD>$map->{Partition}</TD>\n"; }
                if   ( !defined $map->{ClientAdapter}{VirtualSlotNumber} ) { print "<TD></TD>\n"; }
                else                                                       { print "<TD>$map->{ClientAdapter}{VirtualSlotNumber}</TD>\n"; }
                if   ( !defined $map->{ServerAdapter}{BackingDeviceName} ) { print "<TD></TD>\n"; }
                else                                                       { print "<TD>$map->{ServerAdapter}{BackingDeviceName}</TD>\n"; }
                if   ( !defined $map->{Storage}{VirtualDisk}{DiskName} ) { print "<TD></TD>\n"; }
                else                                                     { print "<TD>$map->{Storage}{VirtualDisk}{DiskName}</TD>\n"; }
                if   ( !defined $map->{Storage}{VirtualDisk}{PartitionSize} ) { print "<TD></TD>\n"; }
                else                                                          { print "<TD>$map->{Storage}{VirtualDisk}{PartitionSize}</TD>\n"; }
                if   ( !defined $map->{Storage}{VirtualDisk}{DiskCapacity} ) { print "<TD></TD>\n"; }
                else                                                         { print "<TD>$map->{Storage}{VirtualDisk}{DiskCapacity}</TD>\n"; }
                if   ( !defined $map->{Storage}{VirtualDisk}{DiskLabel} ) { print "<TD></TD>\n"; }
                else                                                      { print "<TD>$map->{Storage}{VirtualDisk}{DiskLabel}</TD>\n"; }
                if   ( !defined $map->{Storage}{PhysicalVolume}{VolumeName} ) { print "<TD></TD>\n"; }
                else                                                          { print "<TD>$map->{Storage}{PhysicalVolume}{VolumeName}</TD>\n"; }
                if   ( !defined $map->{Storage}{PhysicalVolume}{VolumeCapacity} ) { print "<TD></TD>\n"; }
                else                                                              { print "<TD>$map->{Storage}{PhysicalVolume}{VolumeCapacity}</TD>\n"; }
                if   ( !defined $map->{Storage}{PhysicalVolume}{VolumeState} ) { print "<TD></TD>\n"; }
                else                                                           { print "<TD>$map->{Storage}{PhysicalVolume}{VolumeState}</TD>\n"; }
                if   ( !defined $map->{Storage}{PhysicalVolume}{LocationCode} ) { print "<TD></TD>\n"; }
                else                                                            { print "<TD>$map->{Storage}{PhysicalVolume}{LocationCode}</TD>\n"; }
              }
            }
          }
        }

        print "
     </tbody>
    </TABLE>";
      }
      print "</div>\n";
      print "</center>";
    }

    if ( -f "$file_npiv_conf" || $ENV{DEMO} ) {
      print "<center>";
      print "<div id=\"tabs-$tab_index\">\n";
      print "<a href=\"$cvs_npiv_rest\"><div class=\"csvexport\">CSV npiv Rest</div></a>" if ( -e "$webdir/$cvs_npiv_rest" );
      $tab_index++;

      my $npiv = Xorux_lib::read_json($file_npiv_conf);
      print '<TABLE style="width:90%;" class="tabconfig tablesorter" data-sortby="1 2">
     <thead>
     <TR>
     <TH align="center" class="sortable" valign="center">Server</TH>
     <TH align="center" class="sortable" valign="center">MapPort</TH>
     <TH align="center" class="sortable" valign="center">Local Partition</TH>
     <TH align="center" class="sortable" valign="center">Conn  Partition</TH>
     <TH align="center" class="sortable" valign="center">Conn<br>Virtual<br>Slot<br>Number</TH>
     <TH align="center" class="sortable" valign="center">Server<br>Virtual<br>Slot<br>Number</TH>
     <TH align="center" class="sortable" valign="center">Location<br>Code</TH>

     <TH align="center" class="sortable" valign="center">WWPNs</TH>

     <TH align="center" class="sortable" valign="center">Phys<br>Port<br>Available<br>Ports</TH>
     <TH align="center" class="sortable" valign="center">Phys<br>Port<br>Total<br>Ports</TH>
     <TH align="center" class="sortable" valign="center">Phys<br>Port<br>Port<br>Name</TH>
     <TH align="center" class="sortable" valign="center">Phys<br>Port<br>WWPN</TH>
     <TH align="center" class="sortable" valign="center">Phys<br>Port<br>Location<br>Code</TH>
    </TR>
  </thead>
  <tbody>';
      if ( $ENV{DEMO} ) {
        print_html_file("$webdir/npiv-demo.html");
      }
      else {
        foreach my $server_uid ( keys %{$npiv} ) {
          my $server_uid_short = substr( $server_uid, 0, 5 );
          if ( $server_uid eq "" ) { next; }
          if ( ref( $npiv->{$server_uid} ) eq "ARRAY" ) {
            foreach my $map ( @{ $npiv->{$server_uid} } ) {
              print "<tr>";
              if   ( defined $map->{SystemName} ) { print "<TD>$map->{SystemName}</TD>\n"; }
              else                                { print "<TD></TD>\n"; }
              if   ( defined $map->{ServerAdapter}{MapPort} ) { print "<TD>$map->{ServerAdapter}{MapPort}</TD>\n"; }
              else                                            { print "<TD></TD>\n"; }
              if   ( defined $map->{ServerAdapter}{LocalPartition} ) { print "<TD>$map->{ServerAdapter}{LocalPartition}</TD>\n"; }
              else                                                   { print "<TD></TD>\n"; }
              if   ( defined $map->{ServerAdapter}{ConnectingPartition} ) { print "<TD>$map->{ServerAdapter}{ConnectingPartition}</TD>\n"; }
              else                                                        { print "<TD></TD>\n"; }
              if   ( defined $map->{ServerAdapter}{ConnectingVirtualSlotNumber} ) { print "<TD>$map->{ServerAdapter}{ConnectingVirtualSlotNumber}</TD>\n"; }
              else                                                                { print "<TD></TD>\n"; }
              if   ( defined $map->{ServerAdapter}{VirtualSlotNumber} ) { print "<TD>$map->{ServerAdapter}{VirtualSlotNumber}</TD>\n"; }
              else                                                      { print "<TD></TD>\n"; }
              if   ( defined $map->{ServerAdapter}{LocationCode} ) { print "<TD>$map->{ServerAdapter}{LocationCode}</TD>\n"; }
              else                                                 { print "<TD></TD>\n"; }
              if   ( defined $map->{ClientAdapter}{WWPNs} ) { print "<TD>$map->{ClientAdapter}{WWPNs}</TD>\n"; }
              else                                          { print "<TD></TD>\n"; }
              if   ( defined $map->{Port}{AvailablePorts} ) { print "<TD>$map->{Port}{AvailablePorts}</TD>\n"; }
              else                                          { print "<TD></TD>\n"; }
              if   ( defined $map->{Port}{TotalPorts} ) { print "<TD>$map->{Port}{TotalPorts}</TD>\n"; }
              else                                      { print "<TD></TD>\n"; }
              if   ( defined $map->{Port}{PortName} ) { print "<TD>$map->{Port}{PortName}</TD>\n"; }
              else                                    { print "<TD></TD>\n"; }
              if   ( defined $map->{Port}{WWPN} ) { print "<TD>$map->{Port}{WWPN}</TD>\n"; }
              else                                { print "<TD></TD>\n"; }
              if   ( defined $map->{Port}{LocationCode} ) { print "<TD>$map->{Port}{LocationCode}</TD>\n"; }
              else                                        { print "<TD></TD>\n"; }
              print "</tr>\n";

            }
          }
        }
      }
      print "</tbody></TABLE>";
      print "</div>\n";
      print "</center>";
    }

    #VLANs
    if ( defined $files_vlan_conf[0] && $files_vlan_conf[0] ne "" || $ENV{DEMO} ) {
      print "<center>";
      print "<div id=\"tabs-$tab_index\">\n";
      $tab_index++;
      my $metrics = [ "NetworkVLANID", "TaggedNetwork", "VswitchID" ];
      print '<TABLE style="width:90%;" class="tabconfig tablesorter" data-sortby="1 2">
     <thead>
     <TR>
     <TH align="center" class="sortable" valign="center">Server</TH>
     <TH align="center" class="sortable" valign="center">VLAN</TH>
     <TH align="center" class="sortable" valign="center">VLAN ID</TH>
     <TH align="center" class="sortable" valign="center">Tagged Network</TH>
     <TH align="center" class="sortable" valign="center">Vswich ID</TH>
    </TR>
  </thead>
  <tbody>';

      #VLANs
      my $server_ok;
      foreach my $file (@files_vlan_conf) {
        my ( $server, undef, $hmc ) = split( "__", $file );
        $server = basename($server);
        $hmc =~ s/\.json//g;
        if ( defined $server_ok->{$server} ) { next; }
        my $vlans = Xorux_lib::read_json($file);
        foreach my $vlan ( keys %{$vlans} ) {
          print "<TR>\n";
          print "<TD>$server</TD>\n";
          print "<TD>$vlan</TD>\n";
          foreach my $m ( @{$metrics} ) {
            if ( defined $vlans->{$vlan}{$m}{content} ) {
              print "<TD>$vlans->{$vlan}{$m}{content}</TD>\n";
            }
            else {
              print "<TD></TD>\n";
            }
          }
          print "</TR>\n";
        }
        $server_ok->{$server} = 1;
      }

      print "</tbody></TABLE>";
      print "</div>";
      print "</center>";
    }

    #SEA
    if ( defined $files_sea_conf[0] && $files_sea_conf[0] ne "" || $ENV{DEMO} ) {
      print "<center>";
      print "<div id=\"tabs-$tab_index\">\n";
      $tab_index++;
      my $metrics = [ "ThreadModeEnabled", "LargeSend", "PortVLANID", "HighAvailabilityMode", "UniqueDeviceID", "ConfigurationState", "JumboFramesEnabled", "QueueSize", "QualityOfServiceMode", "IsPrimary" ];
      print '<TABLE style="width:90%;" class="tabconfig tablesorter" data-sortby="1 2">
     <thead>
     <TR>
     <TH align="center" class="sortable" valign="center">Server</TH>
     <TH align="center" class="sortable" valign="center">Device name</TH>
     <TH align="center" class="sortable" valign="center">Interface</TH>
     <TH align="center" class="sortable" valign="center">ThreadMode</TH>
     <TH align="center" class="sortable" valign="center">Large Send</TH>
     <TH align="center" class="sortable" valign="center">Port VLAN ID</TH>
     <TH align="center" class="sortable" valign="center">High Av. Mode</TH>
     <TH align="center" class="sortable" valign="center">DeviceID</TH>
     <TH align="center" class="sortable" valign="center">State</TH>
     <TH align="center" class="sortable" valign="center">JumboFrames</TH>
     <TH align="center" class="sortable" valign="center">Queue Size</TH>
     <TH align="center" class="sortable" valign="center">QoS Mode</TH>
     <TH align="center" class="sortable" valign="center">Primary</TH>
     <TH align="center" class="sortable" valign="center">Backing Device</TH>
     <TH align="center" class="sortable" valign="center">Name</TH>
     <TH align="center" class="sortable" valign="center">Int</TH>
     <TH align="center" class="sortable" valign="center">Type</TH>
     <TH align="center" class="sortable" valign="center">State</TH>
     <TH align="center" class="sortable" valign="center">Unique ID</TH>
    </TR>
  </thead>
  <tbody>';
      my $server_ok;
      foreach my $file (@files_sea_conf) {
        my ( $server, undef, $hmc ) = split( "__", $file );
        $server = basename($server);
        $hmc =~ s/\.json//g;
        if ( defined $server_ok->{$server} ) { next; }
        my $seas = Xorux_lib::read_json($file);
        foreach my $sea ( keys %{$seas} ) {
          print "<TR>\n";
          print "<TD>$server</TD>\n";
          print "<TD>$seas->{$sea}{DeviceName}{content}</TD>\n";
          print "<TD>$seas->{$sea}{IPInterface}{InterfaceName}{content}</TD>\n";
          foreach my $m ( @{$metrics} ) {
            if ( defined $seas->{$sea}{$m}{content} ) {
              print "<TD>$seas->{$sea}{$m}{content}</TD>\n";
            }
            else {
              print "<TD></TD>\n";
            }
          }
          my $ebd = $seas->{$sea}{BackingDeviceChoice}{EthernetBackingDevice};
          if ( defined $ebd->{UniqueDeviceID}{content} ) {
            print "<TD>$ebd->{UniqueDeviceID}{content}</TD>\n";
          }
          else { print "<TD></TD>\n"; }
          if ( defined $ebd->{DeviceName}{content} ) {
            print "<TD>$ebd->{DeviceName}{content}</TD>\n";
          }
          else { print "<TD></TD>\n"; }
          if ( defined $ebd->{IPInterface}{InterfaceName}{content} ) {
            print "<TD>$ebd->{IPInterface}{InterfaceName}{content}</TD>\n";
          }
          else { print "<TD></TD>\n"; }
          if ( defined $ebd->{DeviceType}{content} ) {
            print "<TD>$ebd->{DeviceType}{content}</TD>\n";
          }
          else { print "<TD></TD>\n"; }
          if ( defined $ebd->{IPInterface}{State}{content} ) {
            print "<TD>$ebd->{IPInterface}{State}{content}</TD>\n";
          }
          else { print "<TD></TD>\n"; }
          if ( defined $sea ) {
            print "<TD>$sea</TD>\n";
          }
          else { print "<TD></TD>\n"; }
          print "</TR>\n";
        }
        $server_ok->{$server} = 1;
      }

      print "</tbody></TABLE>";
      print "</div>";
      print "</center>";
    }

    #Load Groups
    if ( defined $files_loadgroups_conf[0] && $files_loadgroups_conf[0] ne "" || $ENV{DEMO} ) {
      print "<center>";
      print "<div id=\"tabs-$tab_index\">\n";
      $tab_index++;
      my $metrics = [ "MACAddress", "DynamicReconfigurationConnectorName", "PortVLANID", "LocationCode", "TrunkPriority", "VirtualSwitchID", "VirtualSlotNumber", "TaggedVLANSupported", "RequiredAdapter", "AllowedOperatingSystemMACAddresses", "QualityOfServicePriorityEnabled" ];
      print '<TABLE style="width:90%;" class="tabconfig tablesorter" data-sortby="1 2">
     <thead>
     <TR>
     <TH align="center" class="sortable" valign="center">Server</TH>
     <TH align="center" class="sortable" valign="center">Device name</TH>
     <TH align="center" class="sortable" valign="center">MAC</TH>
     <TH align="center" class="sortable" valign="center">Connector Name</TH>
     <TH align="center" class="sortable" valign="center">Port VLAN ID</TH>
     <TH align="center" class="sortable" valign="center">Location Code</TH>
     <TH align="center" class="sortable" valign="center">Trunk Priority</TH>
     <TH align="center" class="sortable" valign="center">Virtual Switch ID</TH>
     <TH align="center" class="sortable" valign="center">Virtual Slot Number</TH>
     <TH align="center" class="sortable" valign="center">Tagged VLAN Supported</TH>
     <TH align="center" class="sortable" valign="center">Required Adapter</TH>
     <TH align="center" class="sortable" valign="center">Allowed Operating System MAC Addresses</TH>
     <TH align="center" class="sortable" valign="center">QoS Priority Enabled</TH>
    </TR>
  </thead>
  <tbody>';
      my $server_ok;
      foreach my $file (@files_loadgroups_conf) {
        my ( $server, undef, $hmc ) = split( "__", $file );
        $server = basename($server);
        $hmc =~ s/\.json//g;
        if ( defined $server_ok->{$server} ) { next; }
        my $loadgroups = Xorux_lib::read_json($file);
        foreach my $loadgroup ( keys %{$loadgroups} ) {
          print "<TR>\n";
          print "<TD>$server</TD>\n";
          print "<TD>$loadgroup</TD>\n";
          foreach my $m ( @{$metrics} ) {
            print "<TD>$loadgroups->{$loadgroup}{$m}{content}</TD>\n";
          }
          print "</TR>\n";
        }
        $server_ok->{$server} = 1;
      }

      print "</tbody></TABLE>";
      print "</div>";
      print "</center>";
    }

    #Server tabs, show each server ant its config from $det
    @servers = ();

=begin config tabs
  foreach my $det (@details){
   my ($host, $server) = split ("www/", $det);
    ($server, undef) = split ('/detail.html',$server);
    ($host,$server) = split ('/', $server);
    if ( grep( /^$server$/, @servers )) {
      next;
    }
    push(@servers, $server);
    print "<div id=\"tabs-$tab_index\">\n"; $tab_index++;
    my $print_html;
    if ( -f "$det" ) {
      open( FH, "< $det" );
      $print_html = do { local $/; <FH> };
      close(FH);
      print "$print_html";
    }
    print "</div>\n";
  }
=cut

    #  print "</div>\n";
    print "</div><br>\n";
    return 1;
  }
}

sub print_data_serversvm {    # general vcenters configuration

  print "<div  id=\"tabs\">\n";
  print "<CENTER>";

  print "<ul>\n";
  print "  <li ><a href=\"#tabs-1\">Configuration</a></li>\n";
  print "  <li ><a href=\"#tabs-2\">VM</a></li>\n";
  print "  <li ><a href=\"#tabs-3\">Datastore</a></li>\n";
  print "</ul>\n";

  print "<div id=\"tabs-1\">\n";

  print "<table border=\"0\">\n";
  print "<tr><td>";

  # print STDERR "12475 $host_url, $server_url, $server, $lpar_url, $item, $wrkdir\n";
  #             print "</td></tr></table>"

  # read all vcenter_config.txt files
  # these files are prepared in vmw2rrd.pl

  my $pth = "$wrkdir/vmware_*/vcenter_config.txt";
  $pth =~ s/ /\\ /g;
  my $no_name              = "";
  my @vcenter_config_files = (<$pth$no_name>);    # unsorted, workaround for space in names
                                                  # print STDERR "\@vcenter_config_files @vcenter_config_files\n";

  # my @vcenter_config_files_new = grep  { (-M) *24*60 < 1 } @vcenter_config_files; # younger than 1 minute
  my @vcenter_config_files_new = grep { (-M) < 1 } @vcenter_config_files;    # younger than 1 day
                                                                             # print STDERR "\@vcenter_config_files_new @vcenter_config_files_new\n";

  my @vcenter_config_html = ();
  my @vcenters_configs    = ();
  foreach (@vcenter_config_files_new) {
    if ( open( my $FH, "< $_" ) ) {
      push @vcenters_configs, <$FH>;
      close $FH;
      if ( scalar @vcenter_config_html eq 0 ) {
        my $html_file = $_;
        $html_file =~ s/\.txt$/\.html/;

        # print STDERR "\$html_file $html_file\n";
        if ( open( my $FH, "< $html_file" ) ) {
          push @vcenter_config_html, <$FH>;
          close $FH;
        }
        else {
          error( "Cannot open file $html_file: $!" . __FILE__ . ":" . __LINE__ );
        }
      }
    }
    else {
      error( "Cannot open file $_: $!" . __FILE__ . ":" . __LINE__ );
    }
  }

  # print STDERR "\@vcenters_configs @vcenters_configs\n";
  # print STDERR "@vcenter_config_html";
  foreach (@vcenter_config_html) {    # print html heading
    print "$_";
    last if index( $_, "<tbody>" ) > -1;
  }
  print FormatResults(@vcenters_configs);    # print data

  print "</td></tr></table>";

  #print "<div><br>Clusters</div>";
  print "<div><br><h3 id=\"title\" style=\"display: block;\">Clusters</h3></div>";

  # print clusters table

  @vcenters_configs = ();
  my $html_file = "$tmpdir/vcenters_clusters_config.html";
  if ( open( my $FH, "< $html_file" ) ) {
    push @vcenters_configs, <$FH>;
    close $FH;
  }
  else {
    error( "Cannot open file $html_file: $!" . __FILE__ . ":" . __LINE__ );
  }

  print @vcenters_configs;    # print html data

  print "</center></td></tr></tbody></table>";
  print "</div>\n";

  print "<div id=\"tabs-2\">\n";

  # get live servers from menu
  # in cluster
  # S:cluster_2nd Cluster:10.22.11.8:view:VIEW:/lpar2rrd-cgi/detail.sh?host=10.22.11.10&server=10.22.11.8&lpar=cod&item=view&entitle=0&gui=1&none=none::1646035380:V:
  # no cluster
  # S:ef81e113-3f75-4e78-bc8c-a86df46a4acb_12:10.22.111.18:view:VIEW:/lpar2rrd-cgi/detail.sh?host=10.22.111.4&server=10.22.111.18&lpar=cod&item=view&entitle=0&gui=1&none=none::1646035360:V:
  # here also could be possible to add columns vcenter, cluster, esxi (Jindra)
  read_menu_vmware( \@menu_vmware ) if !@menu_vmware;
  my @matches   = grep { /^S/ && /view:VIEW/ && /:V:/ } @menu_vmware;
  my $heading   = "";
  my $all_lines = "";
  foreach (@matches) {
    my $server = $_;

    # print "$server<br>"; # you can see it in GUI
    ( undef, my $cluster, $server, undef, undef, my $host, undef ) = split ":", $server;
    ( undef, $host ) = split "host=", $host;
    $host =~ s/&.*//;

    # print "\$host $host \$server $server";
    my $file_html_cpu = "$wrkdir/$server/$host/cpu.html";
    next if !-f $file_html_cpu;

    # print "$file_html_cpu<br>";
    open( FH, "< $file_html_cpu" );
    my $cpu_html = do { local $/; <FH> };
    close(FH);
    if ( $heading eq "" ) {
      print "<table border=\"0\">\n";
      print "<tr><td>\n";
      $heading = $cpu_html;
      ( $heading, undef ) = split "<tbody>", $heading;
      $heading .= "<tbody>";
    }

    # $cpu_html =~ s/^[\s\S]*<tbody>//;
    ( undef, $cpu_html ) = split "<tbody>", $cpu_html;
    $cpu_html =~ s/<\/tbody><\/TABLE><\/CENTER>//;
    $all_lines .= $cpu_html;
  }
  print "$heading$all_lines";
  if ( open( FH, ">", "$tmpdir/vmware_vm_config.txt" ) ) {
    print FH "$heading$all_lines";
    close FH;
  }
  else {
    error( "can't open file $basedir/logs/vmware_vm_config.txt : $! :" . __FILE__ . ":" . __LINE__ );
  }

  print "</tbody></TABLE></CENTER></td></tr></table>\n";
  print "</div>\n";

  print "<div id=\"tabs-3\">\n";
  print_datastore_config();
  print "</div>\n";

  print "</div>\n";

}

sub FormatResults {
  my @results_unsort = @_;
  my $line           = "";
  my $formated       = "";
  my @items1         = "";
  my $item           = "";

  my @results = sort { lc $a cmp lc $b } @results_unsort;
  foreach $line (@results) {
    chomp $line;
    @items1   = split /,/, $line;
    $formated = $formated . "<TR>";
    my $col = 0;
    foreach $item (@items1) {
      if ( $col == 0 ) {
        $formated = sprintf( "%s <TD><B>%s</B></TD>", $formated, $item );
      }
      else {
        $formated = sprintf( "%s <TD align=\"center\">%s</TD>", $formated, $item );
      }
      $col++;
    }
    $formated = $formated . "</TR>\n";
  }
  return $formated;
}

sub print_datastore_table_top {
  $params{d_platform} = "VMware";
  print "<div  id=\"tabs\">\n";

  print "<ul>\n";
  print "  <li class=\"$tab_type\"><a href=\"#tabs-1\">TOP</a></li>\n";
  print "  <li class=\"$tab_type\"><a href=\"#tabs-2\">IOPS Read</a></li>\n";
  print "  <li class=\"$tab_type\"><a href=\"#tabs-3\">IOPS Write</a></li>\n";
  print "  <li class=\"$tab_type\"><a href=\"#tabs-4\">Data Read</a></li>\n";
  print "  <li class=\"$tab_type\"><a href=\"#tabs-5\">Data Write</a></li>\n";
  print "  <li class=\"$tab_type\"><a href=\"#tabs-6\">Used Space</a></li>\n";
  print "</ul>\n";
  print "<CENTER>";

  print "<div id=\"tabs-1\">\n";
  print "
  <div >
    <center>
      <div style='font-size: 0.8rem; margin-top: 1em'>
      <form method='get' action='/lpar2rrd-cgi/detail.sh' id='dstr-top'>
        <label for='from'>From</label>
        <input type='text' id='fromTime' size='16' name='fromTime'>
        <label for='to'>to</label>
        <input type='text' id='toTime' size='16' name='toTime'>
        <input type='submit' style='font-weight: bold;' id='showvolumes' value='Show top datastores'>
    <input type='hidden' name='dstr-top' value='12'>
      </form>
      </div>
    <div id='volresults'></div>
    </center>
  </div>
  ";
  print "</div>\n";

  $host_url   = "nope";
  $server_url = "nope";
  $lpar_url   = "nope";

  print "<div id=\"tabs-2\">\n";
  print "<table border=\"0\">\n";
  print "<tr>";
  $item = "dstrag_iopsr";
  print_item( $host_url, $server_url, $lpar_url, $item, "d", $type_sam, $entitle, $detail_yes, "norefr", "star", 1, "nolegend" );
  print_item( $host_url, $server_url, $lpar_url, $item, "w", $type_sam, $entitle, $detail_yes, "norefr", "star", 1, "nolegend" );
  print "</tr>\n<tr>\n";
  print_item( $host_url, $server_url, $lpar_url, $item, "m", $type_sam,      $entitle, $detail_yes, "norefr", "star", 1, "nolegend" );
  print_item( $host_url, $server_url, $lpar_url, $item, "y", $type_sam_year, $entitle, $detail_yes, "norefr", "star", 1, "nolegend" );
  print "</tr></table>";
  print "</div>\n";

  print "<div id=\"tabs-3\">\n";
  print "<table border=\"0\">\n";
  print "<tr>";
  $item = "dstrag_iopsw";
  print_item( $host_url, $server_url, $lpar_url, $item, "d", $type_sam, $entitle, $detail_yes, "norefr", "star", 1, "nolegend" );
  print_item( $host_url, $server_url, $lpar_url, $item, "w", $type_sam, $entitle, $detail_yes, "norefr", "star", 1, "nolegend" );
  print "</tr>\n<tr>\n";
  print_item( $host_url, $server_url, $lpar_url, $item, "m", $type_sam,      $entitle, $detail_yes, "norefr", "star", 1, "nolegend" );
  print_item( $host_url, $server_url, $lpar_url, $item, "y", $type_sam_year, $entitle, $detail_yes, "norefr", "star", 1, "nolegend" );
  print "</tr></table>";
  print "</div>\n";

  print "<div id=\"tabs-4\">\n";
  print "<table border=\"0\">\n";
  print "<tr>";
  $item = "dstrag_datar";
  print_item( $host_url, $server_url, $lpar_url, $item, "d", $type_sam, $entitle, $detail_yes, "norefr", "star", 1, "nolegend" );
  print_item( $host_url, $server_url, $lpar_url, $item, "w", $type_sam, $entitle, $detail_yes, "norefr", "star", 1, "nolegend" );
  print "</tr>\n<tr>\n";
  print_item( $host_url, $server_url, $lpar_url, $item, "m", $type_sam,      $entitle, $detail_yes, "norefr", "star", 1, "nolegend" );
  print_item( $host_url, $server_url, $lpar_url, $item, "y", $type_sam_year, $entitle, $detail_yes, "norefr", "star", 1, "nolegend" );
  print "</tr></table>";
  print "</div>\n";

  print "<div id=\"tabs-5\">\n";
  print "<table border=\"0\">\n";
  print "<tr>";
  $item = "dstrag_dataw";
  print_item( $host_url, $server_url, $lpar_url, $item, "d", $type_sam, $entitle, $detail_yes, "norefr", "star", 1, "nolegend" );
  print_item( $host_url, $server_url, $lpar_url, $item, "w", $type_sam, $entitle, $detail_yes, "norefr", "star", 1, "nolegend" );
  print "</tr>\n<tr>\n";
  print_item( $host_url, $server_url, $lpar_url, $item, "m", $type_sam,      $entitle, $detail_yes, "norefr", "star", 1, "nolegend" );
  print_item( $host_url, $server_url, $lpar_url, $item, "y", $type_sam_year, $entitle, $detail_yes, "norefr", "star", 1, "nolegend" );
  print "</tr></table>";
  print "</div>\n";

  print "<div id=\"tabs-6\">\n";

  # datastore USED aggregation
  print "<table border=\"0\">\n";
  print "<tr>";
  $item = "dstrag_used";
  print_item( $host_url, $server_url, $lpar_url, $item, "d", $type_sam, $entitle, $detail_yes, "norefr", "star", 1, "nolegend" );
  print_item( $host_url, $server_url, $lpar_url, $item, "w", $type_sam, $entitle, $detail_yes, "norefr", "star", 1, "nolegend" );
  print "</tr>\n<tr>\n";
  print_item( $host_url, $server_url, $lpar_url, $item, "m", $type_sam,      $entitle, $detail_yes, "norefr", "star", 1, "nolegend" );
  print_item( $host_url, $server_url, $lpar_url, $item, "y", $type_sam_year, $entitle, $detail_yes, "norefr", "star", 1, "nolegend" );
  print "</tr></table>";
  print "</div>\n";

  print "</div><br>\n";
  return;
}

sub print_datastore_config {

  # this sub is prepared on base of sub print_datastore_top

  my @all_cluster_name_files = <$wrkdir/*/*/my_cluster_name>;

  print "<center><table class=\"tbl2leftotherright tablesorter\" data-sortby=\"-1 -2\"><thead><tr> \n
  <th class=\"sortable\" align=\"center\">   VMware alias   </th> \n
  <th class=\"sortable\" align=\"center\">   datastore   </th> \n
  <th class=\"sortable\" align=\"center\">   used   <br>   <span>GB</span>   </th> \n
  <th class=\"sortable\" align=\"center\">   free   <br>   <span>GB</span>   </th> \n
  <th class=\"sortable\" align=\"center\">   provisioned   <br>   <span>GB</span>   </th> \n
  <th class=\"sortable\" align=\"left\">   Volume ID   </th> \n
  </tr></thead><tbody>\n";

  my $rrdtool = $ENV{RRDTOOL};

  # start RRD via a pipe
  RRDp::start "$rrdtool";

  # find all datastores
  my @files = <$wrkdir/vmware_*/datastore_datacenter*/*.rrs>;
  foreach my $file (@files) {

    # avoid older 2 days files
    next if ( -f $file and ( -M $file > 2 ) );

    # $human_ds_name = find_human_ds_name($server,$host,$lpar); # this is in detail_graph_cgi.pl
    my $file_name      = basename($file);
    my $datastore_uuid = $file_name;
    $datastore_uuid =~ s/\.rrs//;
    my $datastore_path = $file;
    $datastore_path =~ s/$file_name//;

    # print STDERR "\$file $file \$datastore_uuid $datastore_uuid\n";

    # print STDERR "20175 ,$datastore_path/$datastore_uuid.disk_uids,\n";
    my $disk_uids = "";
    if ( open( FH, "<", "$datastore_path/$datastore_uuid.disk_uids" ) ) {
      $disk_uids = <FH>;
      close FH;
    }

    my $datastore_name = $datastore_uuid;
    my @names          = <$datastore_path*.$datastore_uuid>;

    # print STDERR "\@names ,@names, $datastore_path*.$datastore_uuid\n";
    if ( @names > 0 && $names[0] ne "" ) {
      $datastore_name = basename( $names[0] );

      # remove extension
      $datastore_name =~ s/\.[^.]+$//;
    }

    # print STDERR "\$datastore_name $datastore_name\n";

    my $datacenter_name = "";
    my @dc_name         = <$datastore_path*.dcname>;

    # print STDERR "3440 detail-cgi.pl \@dc_name @dc_name ,$dc_name[0],\n";
    if ( defined $dc_name[0] && $dc_name[0] ne "" ) {
      $datacenter_name = basename( $dc_name[0] );
      $datacenter_name =~ s/\.dcname//;
    }

    # to get cluster name: get datastore VM list table > get ESXi mounted > from ESXI get my cluster name

    my @vm_table = <$datastore_path/$datastore_uuid.html>;

    # print STDERR "7028 \@vm_table @vm_table\n";
    my $cluster_name = "";
    if ( defined $vm_table[0] && $vm_table[0] ne "" && open( FH, "< $vm_table[0]" ) ) {
      my @table = <FH>;
      my $esxi  = $table[2];
      close FH;
      if ( defined $esxi && $esxi ne "" ) {

        # (undef,$esxi) = split ("server=",$esxi);
        ( undef, $esxi ) = split( "_esxi_", $esxi );
        if ( defined $esxi && $esxi ne "" ) {    # not actively used datastore
          ( $esxi, undef ) = split( "\"", $esxi );

          #$esxi = substr $esxi, 0, -1;
          # print STDERR "7037 \$esxi $esxi\n";
          my @cluster_name_file = grep {/$esxi/} @all_cluster_name_files;
          if ( defined $cluster_name_file[0] && $cluster_name_file[0] ne "" && open( FH, "< $cluster_name_file[0]" ) ) {
            my $clust_name = <FH>;
            close FH;

            # cluster_New Cluster|Hosting
            ( $clust_name, undef ) = split( /\|/, $clust_name );
            chomp $clust_name;
            $clust_name =~ s/cluster_//;
            if ( defined $clust_name && $clust_name ne "" ) {
              $cluster_name = $clust_name;

              # print STDERR "15954 \$datastore_name $datastore_name \$esxi $esxi \$cluster_name $cluster_name\n";
            }
          }
        }
      }
    }

    # vmware alias name
    my $vmware_alias = "no VMware alias";
    my $alias_file   = $datastore_path;
    $alias_file =~ s/[^\/]*\/$//;

    # print STDERR "\$alias_file $alias_file\n";
    $alias_file .= "vmware_alias_name";
    if ( -f $alias_file && open( FH, "< $alias_file" ) ) {
      my $name = <FH>;
      close FH;
      chomp $name;
      ( undef, $name ) = split( /\|/, $name );
      $vmware_alias = $name if $name ne "";
    }

    #print STDERR "\$vmware_alias $vmware_alias\n";

    my $rrd = $file;
    $rrd =~ s/:/\\:/g;
    RRDp::cmd qq(graph "tmp/name.png"
     "--start" "now-1d"
     "--end" "now+1d";
     "DEF:used=$rrd:Disk_used:AVERAGE"
     "DEF:free=$rrd:freeSpace:AVERAGE"
     "DEF:prov=$rrd:Disk_provisioned:AVERAGE"
     "PRINT:used:AVERAGE: %3.2lf"
     "PRINT:free:AVERAGE: %3.2lf"
     "PRINT:prov:AVERAGE: %3.2lf"
    );
    my $answer = RRDp::read;
    if ( $$answer =~ "ERROR" ) {
      error("Rrdtool error : $$answer");
      next;
    }
    my $aaa = $$answer;

    # print "$answer\n";
    # print "$$answer\n";
    $aaa =~ s/NaNQ|NaN|nan/0/g;
    ( undef, my $used, my $free, my $prov ) = split( "\n", $aaa );
    chomp $used;
    chomp $free;
    chomp $prov;
    $used = sprintf( '%.0f', $used / 1024 / 1024 );
    $free = sprintf( '%.0f', $free / 1024 / 1024 );
    $prov = sprintf( '%.0f', $prov / 1024 / 1024 );

    # my @d_path = split("\/",$file);
    print "<tr><td>$vmware_alias</td><td><A HREF=\"/lpar2rrd-cgi/detail.sh?host=$datacenter_name&server=$vmware_alias&lpar=$datastore_name&item=datastore&entitle=0&none=none&d_platform=VMware&datastore_uuid=$datastore_uuid\">$datastore_name</td><td>$used</td><td>$free</td><td>$prov</td><td align=\"left\">$disk_uids</td></tr>\n";

  }
  print "</tbody></table>\n";

  # close RRD pipe
  RRDp::end;
}

sub print_datastore_top {
  my ( $sunix, $eunix ) = @_;

  my @all_cluster_name_files = <$wrkdir/*/*/my_cluster_name>;

  # print join("\n",@files)."\n";
  # /home/lpar2rrd/lpar2rrd/data/10.22.11.9/10.22.11.10/my_cluster_name
  # /home/lpar2rrd/lpar2rrd/data/192.168.1.124/pavel.lpar2rrd.com/my_cluster_name

  $sunix =~ s/sunix=//;
  $eunix =~ s/eunix=//;
  print "<br><center><table class=\"tbl2leftotherright tablesorter\" data-sortby=\"4\"><thead><tr> \n
  <th class=\"sortable\" align=\"center\">   VMware alias   </th> \n
  <th class=\"sortable\" align=\"center\">   datastore   </th> \n
  <th class=\"sortable\" align=\"center\">   cluster   </th> \n
  <th class=\"sortable\" align=\"center\">   IO read   <br>   <span>IOps</span>   </th> \n
  <th class=\"sortable\" align=\"center\">   IO write   <br>   <span>IOps</span>   </th> \n
  <th class=\"sortable\" align=\"center\">   read   <br><span>MB/sec</span></th> \n
  <th class=\"sortable\" align=\"center\">   write   <br>   <span>MB/sec</span>   </th> \n
  <th class=\"sortable\" align=\"center\">   latency read<br>   <span>ms</span>   </th> \n
  <th class=\"sortable\" align=\"center\">   latency write<br>   <span>ms</span>   </th> \n
  <th class=\"sortable\" align=\"center\">   used   <br>   <span>GB</span>   </th> \n
  <th class=\"sortable\" align=\"center\">   free   <br>   <span>GB</span>   </th> \n
  <th class=\"sortable\" align=\"center\">   provisioned   <br>   <span>GB</span>   </th> \n
  </tr></thead><tbody>\n";

  my $rrdtool = $ENV{RRDTOOL};

  # start RRD via a pipe
  RRDp::start "$rrdtool";

  # find all datastores
  my @files = <$wrkdir/vmware_*/datastore_datacenter*/*.rrs>;
  foreach my $file (@files) {

    # avoid old files which do not exist in the period
    my $rrd_upd_time = ( stat("$file") )[9];

    # print STDERR "\$file $file $rrd_upd_time $sunix\n";
    if ( $rrd_upd_time < $sunix ) {

      #if ( $type_sam !~ m/x/ ) {
      next;    # avoid that for historical reports
               # --> not necessary as $req_time = 0
               #}
    }

    # $human_ds_name = find_human_ds_name($server,$host,$lpar); # this is in detail_graph_cgi.pl
    my $file_name      = basename($file);
    my $datastore_uuid = $file_name;
    $datastore_uuid =~ s/\.rrs//;
    my $datastore_path = $file;
    $datastore_path =~ s/$file_name//;

    # print STDERR "\$file $file \$datastore_uuid $datastore_uuid\n";

    my $datastore_name = $datastore_uuid;
    my @names          = <$datastore_path*.$datastore_uuid>;

    # print STDERR "\@names ,@names, $datastore_path*.$datastore_uuid\n";
    if ( @names > 0 && $names[0] ne "" ) {
      $datastore_name = basename( $names[0] );

      # remove extension
      $datastore_name =~ s/\.[^.]+$//;
    }

    # print STDERR "\$datastore_name $datastore_name\n";

    my $datacenter_name = "";
    my @dc_name         = <$datastore_path*.dcname>;

    # print STDERR "3440 detail-cgi.pl \@dc_name @dc_name ,$dc_name[0],\n";
    if ( defined $dc_name[0] && $dc_name[0] ne "" ) {
      $datacenter_name = basename( $dc_name[0] );
      $datacenter_name =~ s/\.dcname//;
    }

    # to get cluster name: get datastore VM list table > get ESXi mounted > from ESXI get my cluster name

    my @vm_table = <$datastore_path/$datastore_uuid.html>;

    # print STDERR "7028 \@vm_table @vm_table\n";
    my $cluster_name = "";
    if ( defined $vm_table[0] && $vm_table[0] ne "" && open( FH, "< $vm_table[0]" ) ) {
      my @table = <FH>;
      my $esxi  = $table[2];
      close FH;
      if ( defined $esxi && $esxi ne "" ) {

        # (undef,$esxi) = split ("server=",$esxi);
        ( undef, $esxi ) = split( "_esxi_", $esxi );
        if ( defined $esxi && $esxi ne "" ) {    # not actively used datastore
          ( $esxi, undef ) = split( "\"", $esxi );

          #$esxi = substr $esxi, 0, -1;
          # print STDERR "7037 \$esxi $esxi\n";
          my @cluster_name_file = grep {/$esxi/} @all_cluster_name_files;
          if ( defined $cluster_name_file[0] && $cluster_name_file[0] ne "" && open( FH, "< $cluster_name_file[0]" ) ) {
            my $clust_name = <FH>;
            close FH;

            # cluster_New Cluster|Hosting
            ( $clust_name, undef ) = split( /\|/, $clust_name );
            chomp $clust_name;
            $clust_name =~ s/cluster_//;
            if ( defined $clust_name && $clust_name ne "" ) {
              $cluster_name = $clust_name;

              # print STDERR "15954 \$datastore_name $datastore_name \$esxi $esxi \$cluster_name $cluster_name\n";
            }
          }
        }
      }
    }

    # vmware alias name
    my $vmware_alias = "no VMware alias";
    my $alias_file   = $datastore_path;
    $alias_file =~ s/[^\/]*\/$//;

    # print STDERR "\$alias_file $alias_file\n";
    $alias_file .= "vmware_alias_name";
    if ( -f $alias_file && open( FH, "< $alias_file" ) ) {
      my $name = <FH>;
      close FH;
      chomp $name;
      ( undef, $name ) = split( /\|/, $name );
      $vmware_alias = $name if $name ne "";
    }

    #print STDERR "\$vmware_alias $vmware_alias\n";

    my $rrd = $file;
    $rrd =~ s/:/\\:/g;
    RRDp::cmd qq(graph "tmp/name.png"
     "--start" "$sunix"
     "--end" "$eunix"
     "DEF:used=$rrd:Disk_used:AVERAGE"
     "DEF:free=$rrd:freeSpace:AVERAGE"
     "DEF:prov=$rrd:Disk_provisioned:AVERAGE"
     "PRINT:used:AVERAGE: %3.2lf"
     "PRINT:free:AVERAGE: %3.2lf"
     "PRINT:prov:AVERAGE: %3.2lf"
    );
    my $answer = RRDp::read;
    if ( $$answer =~ "ERROR" ) {
      error("Rrdtool error : $$answer");
      next;
    }
    my $aaa = $$answer;

    # print "$answer\n";
    # print "$$answer\n";
    $aaa =~ s/NaNQ|NaN|nan/0/g;
    ( undef, my $used, my $free, my $prov ) = split( "\n", $aaa );
    chomp $used;
    chomp $free;
    chomp $prov;
    $used = sprintf( '%.0f', $used / 1024 / 1024 );
    $free = sprintf( '%.0f', $free / 1024 / 1024 );
    $prov = sprintf( '%.0f', $prov / 1024 / 1024 );

    # read, write, IOps
    $rrd =~ s/rrs$/rrt/;
    next if !-f $rrd || ( stat $rrd )[7] == 0;    # no exist -> no care
    RRDp::cmd qq(graph "tmp/name.png"
     "--start" "$sunix"
     "--end" "$eunix"
     "DEF:read=$rrd:Datastore_read:AVERAGE"
     "DEF:writ=$rrd:Datastore_write:AVERAGE"
     "DEF:reav=$rrd:Datastore_ReadAvg:AVERAGE"
     "DEF:wrav=$rrd:Datastore_WriteAvg:AVERAGE"
     "PRINT:read:AVERAGE: %3.2lf"
     "PRINT:writ:AVERAGE: %3.2lf"
     "PRINT:reav:AVERAGE: %3.2lf"
     "PRINT:wrav:AVERAGE: %3.2lf"
    );
    $answer = RRDp::read;
    if ( $$answer =~ "ERROR" ) {
      error("Rrdtool error : $$answer");
      next;
    }
    $aaa = $$answer;

    # print "$answer\n";
    # print "$$answer\n";
    $aaa =~ s/NaNQ|NaN|nan/0/g;
    ( undef, my $read, my $writ, my $reav, my $wrav ) = split( "\n", $aaa );
    chomp $read;
    chomp $writ;
    chomp $reav;
    chomp $wrav;
    $read = sprintf( '%.2f', $read / 1024 );
    $writ = sprintf( '%.2f', $writ / 1024 );
    $reav = sprintf( '%.0f', $reav );
    $wrav = sprintf( '%.0f', $wrav );

    # latency
    my $lat_read = "-";
    my $lat_writ = "-";
    $rrd =~ s/rrt$/rru/;
    if ( -f $rrd && ( stat $rrd )[7] > 0 ) {    # no exist -> no care
      RRDp::cmd qq(graph "tmp/name.png"
       "--start" "$sunix"
       "--end" "$eunix"
       "DEF:read=$rrd:Dstore_readLatency:AVERAGE"
       "DEF:write=$rrd:Dstore_writeLatency:AVERAGE"
       "PRINT:read:AVERAGE: %3.2lf"
       "PRINT:write:AVERAGE: %3.2lf"
      );
      $answer = RRDp::read;
      if ( $$answer =~ "ERROR" ) {
        error("Rrdtool error : $$answer");
        next;
      }
      $aaa = $$answer;

      # print "$answer\n";
      # print "$$answer\n";
      $aaa =~ s/NaNQ|NaN|nan/0/g;
      ( undef, $lat_read, $lat_writ ) = split( "\n", $aaa );
      chomp $lat_read;
      chomp $lat_writ;
      $lat_read = sprintf( '%.2f', $lat_read );
      $lat_writ = sprintf( '%.2f', $lat_writ );
    }

    # my @d_path = split("\/",$file);
    print "<tr><td>$vmware_alias</td><td><A HREF=\"/lpar2rrd-cgi/detail.sh?host=$datacenter_name&server=$vmware_alias&lpar=$datastore_name&item=datastore&entitle=0&none=none&d_platform=VMware&datastore_uuid=$datastore_uuid\">$datastore_name</td><td>$cluster_name</td><td>$reav</td><td>$wrav</td><td>$read</td><td>$writ</td><td>$lat_read</td><td>$lat_writ</td><td>$used</td><td>$free</td><td>$prov</td></tr>\n";

  }
  print "</tbody></table>\n";

  # close RRD pipe
  RRDp::end;
}

# it returns first wpar if there is more than 1 wpar on that lpar
# for 1 wpar makes no sense to create aggregated graph

sub find_wpar {
  my $lpar_path = shift;
  my $wpar      = shift;

  if ( $wpar == 1 ) {

    # it is only for global LPARs, not for WPARs itself
    return " ";
  }

  opendir( DIR, $lpar_path ) || return " ";
  my @lpar_dir = readdir(DIR);
  closedir(DIR);

  my $number = 0;
  foreach my $lpar_item (@lpar_dir) {
    chomp($lpar_item);
    if ( -d "$lpar_path/$lpar_item" && -f "$lpar_path/$lpar_item/cpu.mmm" ) {
      $number++;
      if ( $number == 2 ) {
        return $lpar_item;
      }
    }
  }
  return " ";
}

sub timing_debug {
  my $text = shift;

  if ( defined $ENV{LPAR2RRD_UI_TIME_DEBUG} ) {
    my $act_time = localtime();
    print STDERR "DEBUG: $0 : $$ : $act_time : $text\n";
  }
  return 1;
}

sub print_hitachi_adapters {
  my ( $host_url, $server_url, $lpar_url, $item, $entitle ) = @_;

  print "<CENTER>";
  print "<div id=\"tabs\">\n";
  print "<ul>\n";
  print "  <li class=\"$tab_type\"><a href=\"#tabs-1\">IO</a></li>\n";
  print "</ul>\n";

  print "<div id=\"tabs-1\">\n";
  print "<table border=\"0\">\n";
  print "<tr>";

  print_item( $host_url, $server_url, $lpar_url, $item, "d", $type_sam, $entitle, $detail_yes, "norefr", "star", 1, "legend" );
  print_item( $host_url, $server_url, $lpar_url, $item, "w", $type_sam, $entitle, $detail_yes, "norefr", "star", 1, "legend" );
  print "</tr>\n<tr>\n";
  print_item( $host_url, $server_url, $lpar_url, $item, "m", $type_sam,      $entitle, $detail_yes, "norefr", "star", 1, "legend" );
  print_item( $host_url, $server_url, $lpar_url, $item, "y", $type_sam_year, $entitle, $detail_yes, "norefr", "star", 1, "legend" );
  print "</tr>";
  print "</table>";
  print "</div>\n";

  print "</div><br>\n";

  return 1;
}

sub print_hitachi_adapters_totals {
  my ( $host_url, $server_url, $lpar_url, $item, $entitle ) = @_;

  print "<CENTER>";
  print "<div id=\"tabs\">\n";
  print "<ul>\n";
  print "  <li class=\"$tab_type\"><a href=\"#tabs-1\">Data</a></li>\n";
  print "</ul>\n";

  print "<div id=\"tabs-1\">\n";
  print "<table border=\"0\">\n";
  print "<tr>";

  print_item( $host_url, $server_url, $lpar_url, $item, "d", $type_sam, $entitle, $detail_yes, "norefr", "star", 1, "nolegend" );
  print_item( $host_url, $server_url, $lpar_url, $item, "w", $type_sam, $entitle, $detail_yes, "norefr", "star", 1, "nolegend" );
  print "</tr>\n<tr>\n";
  print_item( $host_url, $server_url, $lpar_url, $item, "m", $type_sam,      $entitle, $detail_yes, "norefr", "star", 1, "nolegend" );
  print_item( $host_url, $server_url, $lpar_url, $item, "y", $type_sam_year, $entitle, $detail_yes, "norefr", "star", 1, "nolegend" );

  print "</tr>";
  print "</table>";
  print "</div>\n";

  print "</div><br>\n";

  return 1;
}

sub print_this_html_file {
  my ( $host_url, $server_url, $lpar_url, $item, $entitle ) = @_;
  my $file = shift;
  my $html;
  if ( -f "$file" ) {
    open( FH, "< $file" );
    $html = do { local $/; <FH> };
    close(FH);
    print "$html";
  }
}

sub is_host_rest {
  my $host  = shift;
  my %hosts = %{ HostCfg::getHostConnections("IBM Power Systems") };
  foreach my $alias ( keys %hosts ) {
    if ( $host eq $hosts{$alias}{host} ) {
      if ( defined $hosts{$alias}{auth_api} && $hosts{$alias}{auth_api} ) {
        return 1;
      }
      else {
        return 0;
      }
      return $hosts{$alias}{auth_api};
    }
  }
}

sub is_any_host_rest {
  if ( defined $ENV{DEMO} && $ENV{DEMO} == 1 ) {
    return 1;
  }
  my %hosts  = %{ HostCfg::getHostConnections("IBM Power Systems") };
  my $result = 0;
  foreach my $alias ( keys %hosts ) {
    if ( defined $hosts{$alias}{auth_api} && $hosts{$alias}{auth_api} ) {
      $result = 1;
    }
  }
  return $result;
}

sub is_all_host_rest {
  if ( defined $ENV{DEMO} && $ENV{DEMO} == 1 ) {
    return 1;
  }
  my %hosts = %{ HostCfg::getHostConnections("IBM Power Systems") };
  foreach my $alias ( keys %hosts ) {
    if ( defined $hosts{$alias}{auth_ssh} && $hosts{$alias}{auth_ssh} ) {
      return 0;
    }
  }
  return 1;
}

sub print_power_overview {
  my $params = shift;

  my $width = "800px";
  RRDp::start "$ENV{RRDTOOL}";
  ( my $CONF, my $SERV ) = PowerDataWrapper::init();
  my @servers = @{ PowerDataWrapper::get_items("SERVER") };

  #table start
  print "<center>";

  #first table

  print_html_file("$webdir/config_table_main.html");

  #servers table
  foreach my $server_hash (@servers) {
    next;
    my $uid    = ( keys %{$server_hash} )[0];
    my $server = $server_hash->{$uid};
    print "<TABLE style=\"width:$width;\" class=\"tabconfig tablesorter\" data-sortby=\"1\">
      <thead>
      <TR>
        <TH colspan=\"6\" align=\"center\" class=\"\" valign=\"center\">$server</TH>
      </TR>
      </thead>
      <tbody>";
    my $metrics = [ "jedna", "druha", "treti" ];
    foreach my $metric ( @{$metrics} ) {
      print "<TR>
          <TD><B>metrika $metric</B></TD>
          <TD align=\"center\">$CONF->{servers}{$uid}{InstalledSystemProcessorUnits}</TD>
          <TD align=\"center\">$CONF->{servers}{$uid}{CurrentProcessingUnitsTotal}</TD>
          <TD align=\"center\">$CONF->{servers}{$uid}{CurrentProcessors}</TD>
          <TD align=\"center\">$CONF->{servers}{$uid}{CurrentProcessors}</TD>
          <TD align=\"center\">$CONF->{servers}{$uid}{CurrentProcessors}</TD>
        </TR>\n";
    }
  }

  print "</tbody></TABLE>";

  #end of servers table

  #performance
  print "<h4>Performance</h4>";
  print "<table class=\"tablesorter nofilter\" style=\"width:$width\">\n";
  print "<thead>\n";
  print "<tr>\n";

  #print "  <th rowspan='2' class='sortable'>Storage</th>\n";
  print "  <th rowspan='2' class='sortable'>$server</th>\n";
  print "  <th colspan='2' style='text-align:center'>CPU</th>\n";
  print "  <th colspan='2' style='text-align:center'>Memory</th>\n";
  print "</tr>\n";
  print "<tr>\n";
  print "  <th class='sortable'>average</th>\n";
  print "  <th class='sortable'>maximum</th>\n";
  print "  <th class='sortable'>average</th>\n";
  print "  <th class='sortable'>maximum</th>\n";
  print "</tr>\n";
  print "</thead><tbody>\n";

  foreach my $server_hash (@servers) {
    my $uid           = ( keys %{$server_hash} )[0];
    my $server        = $server_hash->{$uid};
    my $hmc_uid       = PowerDataWrapper::get_server_parent($uid);
    my $hmc_label     = PowerDataWrapper::get_label( "HMC", $hmc_uid );
    my $rrd_file_path = "$basedir/data/$server/$hmc_label/";
    my $file_pth      = "$basedir/data/$server/*/";

    my $params;
    $params->{eunix} = time;
    $params->{sunix} = $params->{eunix} - ( 86400 * 365 );

    my @pool_data     = @{ Overview::get_something( $rrd_file_path, "pool",     $file_pth, "pool.rrm", $params ) };
    my @pool_max_data = @{ Overview::get_something( $rrd_file_path, "pool-max", $file_pth, "pool.xrm", $params ) };
    my @mem_data      = @{ Overview::get_something( $rrd_file_path, "mem",      $file_pth, "mem.rrm",  $params ) };
    my @mem_max_data  = @{ Overview::get_something( $rrd_file_path, "mem-max",  $file_pth, "mem.rrm",  $params ) };

    print "<TR>
          <TD><B>$server</B></TD>
          <TD align=\"center\">$pool_data[0]</TD>
          <TD align=\"center\">$pool_max_data[0]</TD>
          <TD align=\"center\">$mem_data[0]</TD>
          <TD align=\"center\">$mem_max_data[0]</TD>
        </TR>\n";
  }
  print "</tr></tbody></table>";

  #end performance

=begin traffic
  #start traffic
  foreach my $server_hash (@servers){
    my $uid = (keys %{$server_hash})[0];
    my $server = $server_hash->{$uid};
    my $hmc_uid = PowerDataWrapper::get_server_parent($uid);
    my $hmc_label = PowerDataWrapper::get_label("HMC", $hmc_uid);
    my $rrd_file_path = "$basedir/data/$server/$hmc_label/";
    my $file_pth = "$basedir/data/$server/*/adapters/";

    my @lan_data     = @{ Overview::get_something ($rrd_file_path, "lan",     $file_pth, "") };

    print "<TR>
          <TD><B>$server</B></TD>
          <TD align=\"center\">A</TD>
          <TD align=\"center\">A-max</TD>
          <TD align=\"center\">b</TD>
          <TD align=\"center\">b-max</TD>
          <TD align=\"center\">c</TD>
          <TD align=\"center\">c-max</TD>
          <TD align=\"center\">d</TD>
          <TD align=\"center\">d-max</TD>
        </TR>\n";
    #}
  }
  print "</tr></tbody></table>";
  #end interfaces
=cut

  #cast grafu
  my $hash_params = { 'overview_power' => 1, 'test' => '111' };
  my $item        = $lpar = "";
  foreach my $server_hash (@servers) {
    my $uid       = ( keys %{$server_hash} )[0];
    my $server    = $server_hash->{$uid};
    my $hmc_uid   = $CONF->{servers}{$uid}{parent}->[0];
    my $hmc_label = PowerDataWrapper::get_label( "HMC", $hmc_uid );

    print "<div>\n";
    print "<table border=\"0\">\n";

    $item = "pool";
    $lpar = "pool";
    my $host_url   = urlencode("$hmc_label");
    my $server_url = urlencode("$server");
    my $lpar_url   = urlencode("$lpar");
    print "<tr>";
    print_item( $host_url, $server_url, $lpar_url, $item, "d", $type_sam, $entitle, $detail_yes, "norefr", "nostar", 1, "legend", $hash_params );
    print "</tr>";

    $item       = "pool-total";
    $lpar       = "pool";
    $host_url   = urlencode("$hmc_label");
    $server_url = urlencode("$server");
    $lpar_url   = urlencode("$lpar");
    print "<tr>";
    print_item( $host_url, $server_url, $lpar_url, $item, "d", $type_sam, $entitle, $detail_yes, "norefr", "nostar", 1, "legend", $hash_params );
    print "</tr>";

    $item       = "memalloc";
    $lpar       = "cod";
    $host_url   = urlencode("$hmc_label");
    $server_url = urlencode("$server");
    $lpar_url   = urlencode("$lpar");
    print "<tr>";
    print_item( $host_url, $server_url, $lpar_url, $item, "d", $type_sam, $entitle, $detail_yes, "norefr", "nostar", 1, "legend", $hash_params );
    print "</tr>";

    print "</div>";
  }

  #print "</center>\n\n";
  #konec casti grafu
  #  print "</center>";
  RRDp::end;
  return 0;
}

sub print_power_overview_server {

  my $params = shift;
  my $params_dec;

  foreach my $p ( keys %{$params} ) {
    $params_dec->{$p} = urldecode( $params->{$p} );
  }

  my $width = "800px";
  RRDp::start "$ENV{RRDTOOL}";

  ( my $SERV, my $CONF ) = PowerDataWrapper::init();
  my @servers = @{ PowerDataWrapper::get_items("SERVER") };

  my $uid = "0";
  foreach my $s (@servers) {
    my $s_uid = ( keys %{$s} )[0];
    if ( $s->{$s_uid} eq $params_dec->{server} ) {
      $uid = $s_uid;
    }
  }
  if ( $uid eq "0" || ( defined $ENV{DEMO} && $ENV{DEMO} == 0 ) ) {
    exit;
  }

  my $server               = $params_dec->{server};
  my $interfaces_available = {};
  $interfaces_available = Xorux_lib::read_json("$basedir/tmp/restapi/servers_interface_ind.json") if ( -e "$basedir/tmp/restapi/servers_interface_ind.json" );

  #table start
  print "<center>";

  #configuration
  my $hmc_uid   = PowerDataWrapper::get_server_parent($uid);
  my $hmc_label = PowerDataWrapper::get_label( "HMC", $hmc_uid );
  $hmc_label = "hmc1" if ( $ENV{DEMO} );

  print "<h4>Configuration (current)</h4>";
  if ( $ENV{DEMO} && $params->{server} eq "Power-E880" ) { print "<h5>Configuration might not be accurate to the rest of demo data</h5>\n"; }
  print "<table class=\"tablesorter nofilter\" style=\"width:$width\">\n";
  print "<thead>\n";
  print "<tr>\n";
  print "  <th class='sortable'>Metric</th>\n";
  print "  <th class='sortable'>Value</th>\n";
  print "</tr>\n";
  print "</thead>\n";
  print "<tbody>\n";

  my $conf_metrics_dictionary = {
    "SerialNumber"                         => "Serial Number",
    "ConfigurableSystemProcessorUnits"     => "Configurable System Processor Units",
    "InstalledSystemProcessorUnits"        => "Installed System Processor Units",
    "CurrentAvailableSystemProcessorUnits" => "Current Available System Processor Units",
    "ConfigurableSystemMemory"             => "Configurable System Memory",
    "InstalledSystemMemory"                => "Installed System Memory",
    "CurrentAvailableSystemMemory"         => "Current Available System Memory",
    "MemoryUsedByHypervisor"               => "Memory Used By Hypervisor"
  };

  my $conf_metrics = [
    "SerialNumber",
    "ConfigurableSystemProcessorUnits",
    "InstalledSystemProcessorUnits",
    "CurrentAvailableSystemProcessorUnits",
    "ConfigurableSystemMemory",
    "InstalledSystemMemory",
    "CurrentAvailableSystemMemory",
    "MemoryUsedByHypervisor"
  ];

  if ( $ENV{DEMO} && $params->{server} eq "Power770" )   { $uid = "371933c39f93b112d4088aba69e9933c"; }
  if ( $ENV{DEMO} && $params->{server} eq "Power-E880" ) { $uid = "371933c39f93b112d4088aba69e9933c"; }

  print "<tr>\n";
  print "<td align=\"left\"> Model - machine type </td>\n";
  print "<td align=\"left\"> $CONF->{servers}{$uid}{Model}-$CONF->{servers}{$uid}{MachineType} </td>\n" if ( defined $CONF->{servers}{$uid}{Model} && defined $CONF->{servers}{$uid}{MachineType} );
  print "</tr>\n";
  foreach my $conf_metric ( @{$conf_metrics} ) {
    my $metric_label = ucfirst( lc( $conf_metrics_dictionary->{$conf_metric} ) );
    if ( !defined $CONF->{servers}{$uid}{$conf_metric} || $CONF->{servers}{$uid}{$conf_metric} eq "not defined" ) { next; }
    print "<tr>\n";
    print "<td align=\"left\"> $metric_label </td>\n";
    if ( defined $CONF->{servers}{$uid}{$conf_metric} ) {
      if ( $metric_label =~ m/[mM]emory/ ) {
        my $value_mem = sprintf( "%.0f", $CONF->{servers}{$uid}{$conf_metric} / 1000 );
        $value_mem = "$value_mem GB";
        print "<td align=\"left\"> $value_mem </td>\n";
      }
      else {
        print "<td align=\"left\"> $CONF->{servers}{$uid}{$conf_metric} </td>\n";
      }
    }
    else {
      print "<td align=\"left\"> not defined</td>\n";
    }
    print "</tr>\n";
  }
  print "</tbody></table>";

  #end configuration

  ##### performance table
  #for (my $i=1; $i<=4; $i++){
  print "<div id=\"tabs-$params->{i}\">\n";

  my $rrd_file_path = "$basedir/data/$server/$hmc_label/";
  my $file_pth      = "$basedir/data/$server/*/";

  print "<h4>Performance</h4>";

  print "<table class=\"tablesorter nofilter\" style=\"width:$width\">\n";
  print "<thead>\n";
  print "  <th class='sortable'>$server - CPU</th>\n";
  print "  <th class='sortable'>average</th>\n";
  print "  <th class='sortable'>maximum</th>\n";
  print "</thead><tbody>\n";

  $params->{eunix} = time;

  $params->{sunix} = $params->{eunix} - ( 86400 * 1 )   if ( $params->{i} == 1 );
  $params->{sunix} = $params->{eunix} - ( 86400 * 7 )   if ( $params->{i} == 2 );
  $params->{sunix} = $params->{eunix} - ( 86400 * 30 )  if ( $params->{i} == 3 );
  $params->{sunix} = $params->{eunix} - ( 86400 * 365 ) if ( $params->{i} == 4 );

  ( $params->{sunix}, $params->{eunix} ) = set_report_timerange( $params->{timerange} ) if ( defined $params->{timerange} );

  my $data;
  $data->{cpu}{avg} = Overview::get_something( $rrd_file_path, "pool",     $file_pth, "pool.rrm", $params );
  $data->{cpu}{max} = Overview::get_something( $rrd_file_path, "pool-max", $file_pth, "pool.xrm", $params );
  $data->{mem}{avg} = Overview::get_something( $rrd_file_path, "mem",      $file_pth, "mem.rrm",  $params );
  $data->{mem}{max} = Overview::get_something( $rrd_file_path, "mem-max",  $file_pth, "mem.rrm",  $params );

  my @pool_total_data     = @{ Overview::get_something( $rrd_file_path, "pool-total",     $file_pth, "pool_total.rrt", $params ) };
  my @pool_total_max_data = @{ Overview::get_something( $rrd_file_path, "pool-total-max", $file_pth, "pool_total.rxm", $params ) };

  my $metrics = {
    "cpu" => "CPU",
    "mem" => "Memory"
  };

  my $mem_avg = sprintf( "%.0f", $data->{mem}{avg}[0] );
  my $mem_max = sprintf( "%.0f", $data->{mem}{max}[0] );

  my $cores_avg = sprintf( "%.1f", $data->{cpu}{avg}[0] );
  my $cores_max = sprintf( "%.1f", $data->{cpu}{max}[0] );

  my $cores_total_avg = sprintf( "%.1f", $pool_total_data[0] );
  my $cores_total_max = sprintf( "%.1f", $pool_total_max_data[0] );

  print "<TD><B>CPU Total [Cores]</B></TD>";
  print "<TD align=\"left\">$cores_total_avg</TD>";
  print "<TD align=\"left\">$cores_total_max</TD>";
  print "</TR>\n";

  print "<TD><B>CPU Pool [Cores]</B></TD>";
  print "<TD align=\"left\">$cores_avg</TD>";
  print "<TD align=\"left\">$cores_max</TD>";
  print "</TR>\n";

  print "<TD><B>Memory [GB]</B></TD>";
  print "<TD align=\"left\">$mem_avg</TD>";
  print "<TD align=\"left\">$mem_max</TD>";
  print "</TR>\n";

  print "</tr></tbody></table>";

  print "<table class=\"tablesorter nofilter\" style=\"width:$width\">\n";
  print "<thead>\n";
  print "<tr>\n";
  print "  <th class='sortable'>Shared CPU Pools [Cores]</th>\n";
  print "  <th class='sortable'>average</th>\n";
  print "  <th class='sortable'>maximum</th>\n";
  print "</tr>\n";
  print "</thead><tbody>\n";

  $params->{eunix} = time;

  foreach my $shp_uid ( keys %{ $CONF->{pools} } ) {

    if ( $CONF->{pools}{$shp_uid}{parent} ne $uid ) {
      next;
    }

    my $data     = Overview::get_something( $rrd_file_path, "shpool-cpu",     $file_pth, "$CONF->{pools}{$shp_uid}{label}.rrm", $params );
    my $data_max = Overview::get_something( $rrd_file_path, "shpool-cpu-max", $file_pth, "$CONF->{pools}{$shp_uid}{label}.xrm", $params );

    my $cpu_shpool_avg = sprintf( "%.1f", $data->[0] );
    my $cpu_shpool_max = sprintf( "%.1f", $data_max->[0] );

    #print "<pre> $rrd_file_path, shpool,     $file_pth, $CONF->{pools}{$shp_uid}{label}.rrm  </pre>\n";
    my $metrics = {
      "cpu" => "CPU",
    };

    print "<TD><B>$CONF->{pools}{$shp_uid}{name}</B></TD>";
    print "<TD align=\"left\">$cpu_shpool_avg</TD>";
    print "<TD align=\"left\">$cpu_shpool_max</TD>";
    print "</TR>\n";

  }
  print "</tr></tbody></table>";

  print "</div>\n";

  #}
  ##### end performance

=begin traffic
  #start interfaces
  my $rrd_file_path = "$basedir/data/$server/$hmc_label/";
  my $file_pth = "$basedir/data/$server/*/adapters/";

  my @lan_data     = @{ Overview::get_something ($rrd_file_path, "lan",     $file_pth, "") };

  print "<TR>
          <TD><B>$server</B></TD>
          <TD align=\"center\">A</TD>
          <TD align=\"center\">A-max</TD>
          <TD align=\"center\">b</TD>
          <TD align=\"center\">b-max</TD>
          <TD align=\"center\">c</TD>
          <TD align=\"center\">c-max</TD>
          <TD align=\"center\">d</TD>
          <TD align=\"center\">d-max</TD>
        </TR>\n";
#  }
  print "</tr></tbody></table>";
  #end interfaces
=cut

  # server graphs
  my $hash_params = { 'overview_power' => 1 };
  my $item        = $lpar = "";
  if (0) {    #graphs

    print "<div>\n";
    print "<table border=\"0\">\n";

    $item       = "pool";
    $lpar       = "pool";
    $host_url   = urlencode("$hmc_label");
    $server_url = urlencode("$server");
    $lpar_url   = urlencode("$lpar");
    print "<tr>";
    print_item( $host_url, $server_url, $lpar_url, $item, "d", $type_sam, $entitle, $detail_yes, "norefr", "nostar", 1, "legend", $hash_params );
    print "</tr>";

    $item       = "pool-total";
    $lpar       = "pool";
    $host_url   = urlencode("$hmc_label");
    $server_url = urlencode("$server");
    $lpar_url   = urlencode("$lpar");
    print "<tr>";
    print_item( $host_url, $server_url, $lpar_url, $item, "d", $type_sam, $entitle, $detail_yes, "norefr", "nostar", 1, "legend", $hash_params );
    print "</tr>";

    $item       = "memalloc";
    $lpar       = "cod";
    $host_url   = urlencode("$hmc_label");
    $server_url = urlencode("$server");
    $lpar_url   = urlencode("$lpar");
    print "<tr>";
    print_item( $host_url, $server_url, $lpar_url, $item, "d", $type_sam, $entitle, $detail_yes, "norefr", "nostar", 1, "legend", $hash_params );
    print "</tr>";

    if ( $interfaces_available->{$server}{lan} ) {
      $item       = "power_lan_data";
      $lpar       = "lan-totals";
      $host_url   = urlencode("$hmc_label");
      $server_url = urlencode("$server");
      $lpar_url   = urlencode("$lpar");
      print "<tr>";
      print_item( $host_url, $server_url, $lpar_url, $item, "d", $type_sam, $entitle, $detail_yes, "norefr", "nostar", 1, "nolegend", $hash_params );
      print "</tr>";
    }

    if ( $interfaces_available->{$server}{san} ) {
      $item       = "power_san_data";
      $lpar       = "san-totals";
      $host_url   = urlencode("$hmc_label");
      $server_url = urlencode("$server");
      $lpar_url   = urlencode("$lpar");
      print "<tr>";
      print_item( $host_url, $server_url, $lpar_url, $item, "d", $type_sam, $entitle, $detail_yes, "norefr", "nostar", 1, "nolegend", $hash_params );
      print "</tr>";
    }

    if ( $interfaces_available->{$server}{sas} ) {
      $item       = "power_sas_data";
      $lpar       = "sas-totals";
      $host_url   = urlencode("$hmc_label");
      $server_url = urlencode("$server");
      $lpar_url   = urlencode("$lpar");
      print "<tr>";
      print_item( $host_url, $server_url, $lpar_url, $item, "d", $type_sam, $entitle, $detail_yes, "norefr", "nostar", 1, "nolegend", $hash_params );
      print "</tr>";
    }

    if ( $interfaces_available->{$server}{sri} ) {
      $item       = "power_sri_data";
      $lpar       = "sri-totals";
      $host_url   = urlencode("$hmc_label");
      $server_url = urlencode("$server");
      $lpar_url   = urlencode("$lpar");
      print "<tr>";
      print_item( $host_url, $server_url, $lpar_url, $item, "d", $type_sam, $entitle, $detail_yes, "norefr", "nostar", 1, "nolegend", $hash_params );
      print "</tr>";
    }

    if ( $interfaces_available->{$server}{hea} ) {
      $item       = "power_hea_data";
      $lpar       = "hea-totals";
      $host_url   = urlencode("$hmc_label");
      $server_url = urlencode("$server");
      $lpar_url   = urlencode("$lpar");
      print "<tr>";
      print_item( $host_url, $server_url, $lpar_url, $item, "d", $type_sam, $entitle, $detail_yes, "norefr", "nostar", 1, "nolegend", $hash_params );
      print "</tr>";
    }

    print "</div>";

  }

  #  }
  #print "</center>\n\n";
  #konec casti grafu
  #  print "</center>";
  RRDp::end;
  return 0;
}

sub print_topten_to_csv {
  my $sort_order     = shift;
  my $item           = shift;
  my $item_a         = shift;
  my $period         = shift;
  my $server_url_csv = shift;
  if ( $sort_order =~ /POWER|VMWARE/ && $item =~ /^topten$|^topten_vm$/ && $item_a eq "load_cpu" ) {
    print_topten( "$period", "$server_url_csv" );
    exit;
  }

  # TOP 10 - CPU cores - POWER/VMWARE
  if ( $sort_order =~ /POWER|VMWARE/ && $item =~ /^topten$|^topten_vm$/ && $item_a eq "load_cpu" ) {
    print_topten( "$period", "$server_url_csv" );
    exit;
  }

  # TOP 10 - CPU percent - POWER/VMWARE
  elsif ( $sort_order =~ /POWER|VMWARE/ && $item =~ /^topten$|^topten_vm$/ && $item_a eq "cpu_perc" ) {
    print_topten_cpu_per( "$period", "$server_url_csv" );
    exit;
  }

  # TOP 10 - POWER - SAN,SAN_IOPS,LAN,DISK
  elsif ( $sort_order =~ /POWER/ && $item =~ /^topten$/ && $item_a eq "san_iops" ) {
    print_topten_san_iops( "$period", "$server_url_csv" );
    exit;
  }
  elsif ( $sort_order =~ /POWER/ && $item =~ /^topten$/ && $item_a eq "san" ) {
    print_topten_san( "$period", "$server_url_csv" );
    exit;
  }
  elsif ( $sort_order =~ /POWER/ && $item =~ /^topten$/ && $item_a eq "lan" ) {
    print_topten_lan( "$period", "$server_url_csv" );
    exit;
  }

  # TOP 10 - VMWARE - SAN_IOPS,LAN,DISK
  elsif ( $sort_order =~ /VMWARE/ && $item =~ /^topten_vm$/ && $item_a eq "san_iops" ) {
    print_topten_iops( "$period", "$server_url_csv" );
    exit;
  }
  elsif ( $sort_order =~ /VMWARE/ && $item =~ /^topten_vm$/ && $item_a eq "disk_data" ) {
    print_topten_disk( "$period", "$server_url_csv" );
    exit;
  }
  elsif ( $sort_order =~ /VMWARE/ && $item =~ /^topten_vm$/ && $item_a eq "lan" ) {
    print_topten_net( "$period", "$server_url_csv" );
    exit;
  }

  # TOP 10 - ORACLE VM - CPU cores, CPU %, NET, DISK
  elsif ( $sort_order =~ /ORACLEVM/ && $item_a =~ /load_cpu/ ) {
    print_top10_to_table_orvm( "$period", "$server_url_csv", "load_cpu" );
    exit;
  }
  elsif ( $sort_order =~ /ORACLEVM/ && $item_a =~ /cpu_perc/ ) {
    print_top10_to_table_orvm( "$period", "$server_url_csv", "cpu_perc" );
    exit;
  }
  elsif ( $sort_order =~ /ORACLEVM/ && $item_a =~ /net/ ) {
    print_top10_to_table_orvm( "$period", "$server_url_csv", "net" );
    exit;
  }
  elsif ( $sort_order =~ /ORACLEVM/ && $item_a =~ /disk/ ) {
    print_top10_to_table_orvm( "$period", "$server_url_csv", "disk" );
    exit;
  }

  # TOP 10 - OVIRT - CPU cores, CPU %, NET, DISK
  elsif ( $sort_order =~ /OVIRT/ && $item_a =~ /load_cpu/ ) {
    print_top10_to_table_ovirt( "$period", "$server_url_csv", "load_cpu" );
    exit;
  }
  elsif ( $sort_order =~ /OVIRT/ && $item_a =~ /cpu_perc/ ) {
    print_top10_to_table_ovirt( "$period", "$server_url_csv", "cpu_perc" );
    exit;
  }
  elsif ( $sort_order =~ /OVIRT/ && $item_a =~ /net/ ) {
    print_top10_to_table_ovirt( "$period", "$server_url_csv", "net" );
    exit;
  }
  elsif ( $sort_order =~ /OVIRT/ && $item_a =~ /disk/ ) {
    print_top10_to_table_ovirt( "$period", "$server_url_csv", "disk" );
    exit;
  }

  # TOP 10 - Proxmox - CPU cores, CPU %, NET, DISK
  elsif ( $sort_order =~ /PROXMOX/ && $item_a =~ /load_cpu/ ) {
    print_top10_to_table_proxmox( "$period", "$server_url_csv", "load_cpu" );
    exit;
  }
  elsif ( $sort_order =~ /PROXMOX/ && $item_a =~ /cpu_perc/ ) {
    print_top10_to_table_proxmox( "$period", "$server_url_csv", "cpu_perc" );
    exit;
  }
  elsif ( $sort_order =~ /PROXMOX/ && $item_a =~ /net/ ) {
    print_top10_to_table_proxmox( "$period", "$server_url_csv", "net" );
    exit;
  }
  elsif ( $sort_order =~ /PROXMOX/ && $item_a =~ /disk/ ) {
    print_top10_to_table_proxmox( "$period", "$server_url_csv", "disk" );
    exit;
  }

  # TOP 10 - Hyper-V- CPu cores, NET, DISK
  elsif ( $sort_order =~ /HYPERV/ && $item_a =~ /load_cpu/ ) {
    print_top10_to_table_hyperv( "$period", "$server_url_csv", "load_cpu" );
    exit;
  }
  elsif ( $sort_order =~ /HYPERV/ && $item_a =~ /net/ ) {
    print_top10_to_table_hyperv( "$period", "$server_url_csv", "net" );
    exit;
  }
  elsif ( $sort_order =~ /HYPERV/ && $item_a =~ /disk/ ) {
    print_top10_to_table_hyperv( "$period", "$server_url_csv", "disk" );
    exit;
  }

  # TOP 10 - XenServer - CPu cores, IOPS, DISK, NET
  elsif ( $sort_order =~ /XENSERVER/ && $item_a =~ /load_cpu/ ) {
    print_top10_to_table_xenserver( "$period", "$server_url_csv", "load_cpu" );
    exit;
  }
  elsif ( $sort_order =~ /XENSERVER/ && $item_a =~ /cpu_perc/ ) {
    print_top10_to_table_xenserver( "$period", "$server_url_csv", "cpu_perc" );
    exit;
  }
  elsif ( $sort_order =~ /XENSERVER/ && $item_a =~ /net/ ) {
    print_top10_to_table_xenserver( "$period", "$server_url_csv", "net" );
    exit;
  }
  elsif ( $sort_order =~ /XENSERVER/ && $item_a =~ /iops/ ) {
    print_top10_to_table_xenserver( "$period", "$server_url_csv", "iops" );
    exit;
  }
  elsif ( $sort_order =~ /XENSERVER/ && $item_a =~ /disk/ ) {
    print_top10_to_table_xenserver( "$period", "$server_url_csv", "disk" );
    exit;
  }

  # TOP 10 - OracleDB - CPU per SEC, Logons count, IOPS, DATA
  elsif ( $sort_order =~ /ORACLEDB/ && $item_a =~ /load_cpu/ ) {
    print_top10_to_table_ordb( "$period", "$server_url_csv", "load_cpu" );
    exit;
  }
  elsif ( $sort_order =~ /ORACLEDB/ && $item_a =~ /session/ ) {
    print_top10_to_table_ordb( "$period", "$server_url_csv", "session" );
    exit;
  }
  elsif ( $sort_order =~ /ORACLEDB/ && $item_a =~ /io/ ) {
    print_top10_to_table_ordb( "$period", "$server_url_csv", "io" );
    exit;
  }
  elsif ( $sort_order =~ /ORACLEDB/ && $item_a =~ /data/ ) {
    print_top10_to_table_ordb( "$period", "$server_url_csv", "data" );
    exit;
  }

  # TOP 10 - Nutanix -CPU cores, CPU per, IOPS, DATA, NET
  elsif ( $sort_order =~ /NUTANIX/ && $item_a =~ /load_cpu/ ) {
    print_top10_to_table_nutanix( "$period", "$server_url_csv", "load_cpu" );
    exit;
  }
  elsif ( $sort_order =~ /NUTANIX/ && $item_a =~ /cpu_perc/ ) {
    print_top10_to_table_nutanix( "$period", "$server_url_csv", "cpu_perc" );
    exit;
  }
  elsif ( $sort_order =~ /NUTANIX/ && $item_a =~ /net/ ) {
    print_top10_to_table_nutanix( "$period", "$server_url_csv", "net" );
    exit;
  }
  elsif ( $sort_order =~ /NUTANIX/ && $item_a =~ /data/ ) {
    print_top10_to_table_nutanix( "$period", "$server_url_csv", "data" );
    exit;
  }
  elsif ( $sort_order =~ /NUTANIX/ && $item_a =~ /iops/ ) {
    print_top10_to_table_nutanix( "$period", "$server_url_csv", "iops" );
    exit;
  }

  # TOP 10 - PostgreSQL - READ blocks, TUPLES return, SESSION active
  elsif ( $sort_order =~ /POSTGRES/ && $item_a =~ /read_blocks/ ) {
    print_top10_to_table_postgres( "$period", "$server_url_csv", "read_blocks" );
    exit;
  }
  elsif ( $sort_order =~ /POSTGRES/ && $item_a =~ /tuples_return/ ) {
    print_top10_to_table_postgres( "$period", "$server_url_csv", "tuples_return" );
    exit;
  }
  elsif ( $sort_order =~ /POSTGRES/ && $item_a =~ /session_active/ ) {
    print_top10_to_table_postgres( "$period", "$server_url_csv", "session_active" );
    exit;
  }

  # TOP 10 - SQL servr - IOPS,Data,User connect
  elsif ( $sort_order =~ /SQLSERVER/ && $item_a =~ /iops/ ) {
    print_top10_to_table_microsql( "$period", "$server_url_csv", "iops" );
    exit;
  }
  elsif ( $sort_order =~ /SQLSERVER/ && $item_a =~ /data/ ) {
    print_top10_to_table_microsql( "$period", "$server_url_csv", "data" );
    exit;
  }
  elsif ( $sort_order =~ /SQLSERVER/ && $item_a =~ /user_connect/ ) {
    print_top10_to_table_microsql( "$period", "$server_url_csv", "user_connect" );
    exit;
  }

  # TOP 10 - FusionCompute -CPU cores, CPU per, IOPS, DATA, NET, Disk usage
  elsif ( $sort_order =~ /FUSIONCOMPUTE/ && $item_a =~ /load_cpu/ ) {
    print_top10_to_table_fusion( "$period", "$server_url_csv", "load_cpu" );
    exit;
  }
  elsif ( $sort_order =~ /FUSIONCOMPUTE/ && $item_a =~ /cpu_perc/ ) {
    print_top10_to_table_fusion( "$period", "$server_url_csv", "cpu_perc" );
    exit;
  }
  elsif ( $sort_order =~ /FUSIONCOMPUTE/ && $item_a =~ /net/ ) {
    print_top10_to_table_fusion( "$period", "$server_url_csv", "net" );
    exit;
  }
  elsif ( $sort_order =~ /FUSIONCOMPUTE/ && $item_a =~ /data/ ) {
    print_top10_to_table_fusion( "$period", "$server_url_csv", "data" );
    exit;
  }
  elsif ( $sort_order =~ /FUSIONCOMPUTE/ && $item_a =~ /iops/ ) {
    print_top10_to_table_fusion( "$period", "$server_url_csv", "iops" );
    exit;
  }
  elsif ( $sort_order =~ /FUSIONCOMPUTE/ && $item_a =~ /disk_usage/ ) {
    print_top10_to_table_fusion( "$period", "$server_url_csv", "disk_usage" );
    exit;
  }
}

sub lpars_table {
  my $table_conf = [
    { title          => 'HMC REST API',
      identify       => 'PartitionName',
      metrics        => [ 'hostname', 'profile_name', 'PartitionID', 'PartitionState', 'CurrentSharingMode', 'CurrentProcessors', 'AllocatedVirtualProcessors', 'DesiredVirtualProcessors', 'MinimumProcessors', 'MaximumProcessors', 'MinimumProcessingUnits', 'MaximumProcessingUnits', 'CurrentProcessingUnits', 'CurrentMemory', 'CurrentMinimumMemory', 'CurrentMaximumMemory', 'RuntimeMemory', 'RuntimeMinimumMemory', 'SharedProcessorPoolName' ],
      metrics_labels => [ 'Hostname', 'Profile',      'ID',          'State',          'SharingMode',        'CPUs',              'vCPUs',                      'Desired vCPUs',            'MinCPUs',           'MaxCPUs',           'MinProcUnits',           'MaxProcUnits',           'CPU Units',              'Mem',           'MinMem',               'MaxMem',               'RunMem',        'RunMinMem',            'Pool' ]
    },
    { title          => 'HMC CLI',
      identify       => 'lpar_name',
      metrics        => [ 'hostname', 'profile_name', 'lpar_id', 'curr_sharing_mode', 'curr_procs', 'curr_min_procs', 'curr_max_procs', 'curr_proc_units', 'mem_mode', 'curr_mem', 'curr_min_mem', 'curr_max_mem', 'run_mem', 'run_min_mem', 'curr_shared_proc_pool_name' ],
      metrics_labels => [ 'Hostname', 'Profile',      'ID',      'SharingMode',       'CPUs',       'MinCPUs',        'MaxCPUs',        'CPU Units',       'MemMode',  'Mem',      'MinMem',       'MaxMem',       'RunMem',  'RunMinMem',   'Pool' ]
    }
  ];

  for ( my $i = 0; $i < 2; $i++ ) {
    print "<h4> LPARs - $table_conf->[$i]->{title}</h4>\n";
    my $metrics                = $table_conf->[$i]->{metrics};
    my $metrics_label          = $table_conf->[$i]->{metrics_labels};
    my @files_lpars_per_server = <$basedir/tmp/restapi/HMC_LPARS*.json>;
    print '<table class="tabconfig tablesorter powersrvcfg" data-sortby="-2" >
  <thead>
   <TR>
     <TH align="left" class="sortable" valign="center">Server</TH>
     <TH align="left" class="sortable" valign="center">PartitionName</TH>';
    my $index = 0;
    for ( @{$metrics} ) {
      print '<TH align="center" class="sortable" valign="center">' . $metrics_label->[$index] . '</TH>';
      $index++;
    }
    print ' </TR>
    </thead>
    <tbody>';
    my $lpars_done;
    for (@files_lpars_per_server) {
      my $file        = $_;
      my $ftd         = Xorux_lib::file_time_diff($file);
      my $server_name = basename($file);
      $server_name =~ s/^.*LPARS_//g;
      $server_name =~ s/_conf\.json$//g;
      if ( $ftd <= 86400 ) {
        my $content = Xorux_lib::read_json("$file") if ( -e "$file" );
        for ( keys %{$content} ) {
          my $lpar_name = $_;
          if ( !defined $content->{$lpar_name}{ $table_conf->[$i]->{identify} } || $lpars_done->{$lpar_name} ) { next; }
          if ( !defined $server_name )                                                                         { $server_name = ""; }
          for ( @{$metrics} ) {
            if ( !defined $content->{$lpar_name}{$_} ) { $content->{$lpar_name}{$_} = ""; }
          }
          print '<TR role="row">';
          print '  <TD align="left" valign="center">' . $server_name . ' </TD>';
          print '  <TD align="left" valign="center">' . $content->{$lpar_name}{ $table_conf->[$i]->{identify} } . ' </TD>';
          for ( @{$metrics} ) {
            if ( $_ =~ m/Memory/ || ( $_ =~ m/mem/ && $_ ne "mem_mode" ) ) {
              if ( $content->{$lpar_name}{$_} eq "" ) { $content->{$lpar_name}{$_} = 0; }
              print '    <TD align="center" valign="center">' . sprintf( "%.1f", $content->{$lpar_name}{$_} / 1024 ) . '&nbspGB </TD>';
            }
            else {
              print '    <TD align="center" valign="center">' . $content->{$lpar_name}{$_} . ' </TD>';
            }
          }
          print '  </TR>';
          $lpars_done->{$lpar_name} = 1;
        }
      }
    }
    print "</tbody>\n";
    print "</table>\n";
  }
}

sub isdigit {
  my $digit = shift;
  my $text  = shift;

  unless ( defined $digit ) {
    return 0;
  }
  if ( $digit eq '' ) {
    return 0;
  }
  if ( $digit eq 'U' ) {
    return 1;
  }

  my $digit_work = $digit;
  $digit_work =~ s/[0-9]//g;
  $digit_work =~ s/\.//;
  $digit_work =~ s/^-//;
  $digit_work =~ s/e//;
  $digit_work =~ s/\+//;
  $digit_work =~ s/\-//;

  if ( length($digit_work) == 0 ) {

    # is a number
    return 1;
  }

  #if (($digit * 1) eq $digit){
  #  # is a number
  #  return 1;
  #}

  # NOT a number
  return 0;
}
