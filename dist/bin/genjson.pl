# generates JSON data structures
use strict;
use warnings;

use CGI::Carp qw(fatalsToBrowser);
use Storable;
use Encode qw(encode_utf8);
use Sort::Naturally;

use Data::Dumper;

my $DEBUG           = $ENV{DEBUG}             ||= "";
my $GUIDEBUG        = $ENV{GUIDEBUG}          ||= "";
my $DEMO            = $ENV{DEMO}              ||= "";
my $BETA            = $ENV{BETA}              ||= "";
my $WLABEL          = $ENV{WLABEL}            ||= "";
my $TITLE           = $ENV{CUSTOM_PAGE_TITLE} ||= "";
my $errlog          = $ENV{ERRLOG};
my $basedir         = $ENV{INPUTDIR} ||= "/home/lpar2rrd/lpar2rrd";
my $webdir          = $ENV{WEBDIR};
my $inputdir        = $ENV{INPUTDIR};
my $dashb_rrdheight = $ENV{DASHB_RRDHEIGHT};
my $dashb_rrdwidth  = $ENV{DASHB_RRDWIDTH};
my $legend_height   = $ENV{LEGEND_HEIGHT};
my $alturl          = $ENV{WWW_ALTERNATE_URL};
my $alttmp          = $ENV{WWW_ALTERNATE_TMP};
my $uid;    #             = $ENV{REMOTE_USER} ||= "";
my $listByHMC  = $ENV{LIST_BY_HMC};
my $pic_col    = $ENV{PICTURE_COLOR};
my $grpnames   = "";
my $aclCustAll = 0;
my $isAdmin;
my $isReadonly;
my @aclCust;
my $free = 1;

my $version;
if ( open( VER, "$basedir/etc/version.txt" ) ) {
  my @versions = <VER>;
  close VER;
  $version = pop(@versions);
  $version =~ s/ .*//;
  chomp $version;
}
else {
  $version = $ENV{version};
}
my $prodname = "LPAR2RRD";

if ($WLABEL) {
  $prodname = $WLABEL;
}

print "Content-type: application/json\n\n";

use Digest::MD5 qw(md5_hex);
use JSON qw(encode_json decode_json);

use CustomGroups;
use Alerting;
use Users;
use XoruxEdition;

my $acl;
my $useacl;
my $aclAdminGroup;
my %sections;

if ( $ENV{HTTP_XORUX_APP} && $ENV{HTTP_XORUX_APP} eq "Xormon" ) {
  require ACLx;
  require SQLiteDataWrapper;
  $acl           = ACLx->new();
  $useacl        = 1;
  $uid           = $acl->{uid};
  $isAdmin       = $acl->isAdmin();
  $isReadonly    = $acl->isReadOnly();
  $aclAdminGroup = $acl->getAdminGroup();
}
else {
  use ACL;
  $acl           = ACL->new();
  $useacl        = $acl->useACL();
  $aclAdminGroup = $acl->getAdminGroup();
  %sections      = $acl->getSections();

  if ($useacl) {
    $uid        = $acl->getUser();
    $grpnames   = $acl->getGroupsHtml();
    $isAdmin    = $acl->isAdmin();
    $isReadonly = $acl->isReadOnly();
    @aclCust    = ( $acl->getCustoms() );
    if ( $isAdmin || ( $aclCust[0] && $aclCust[0] eq "*" ) ) {
      $aclCustAll = 1;
    }

  }
  else {
    $uid     = "admin";
    $isAdmin = 1;
  }
}

my @menu;    # array for complete menu json generation
my %idx;     # index file for menu entries
my %pack;    # parsed menu.txt
my %env;     # environment values
$env{free} = 1;
if ( length( premium() ) == 6 ) {
  $free = 0;
  $env{free} = 0;
}

#F,J,Y
my %platform = (
  P => "POWER",
  B => "POWER",
  V => "VMWARE",
  C => "CUSTOM",
  O => "OVIRT",
  X => "XENSERVER",
  H => "HYPERV",
  S => "SOLARIS",
  L => "LINUX",
  N => "NUTANIX",
  A => "AWS",
  G => "GCloud",
  Q => "ORACLEDB",
  Z => "Azure",
  K => "Kubernetes",
  R => "Openshift",
  E => "Cloudstack",
  M => "Proxmox",
  I => "Docker",
  W => "FusionCompute",
  T => "Postgres",
  F => "DB2",
  D => "SQLServer",
  U => "UNMANAGED"
);

# set unbuffered stdout
#$| = 1;

#open( OUT, ">> $errlog" ) if $DEBUG == 2;

# get QUERY_STRING
use Env qw(QUERY_STRING);

#print OUT "-- $QUERY_STRING\n" if $DEBUG == 2;

# `echo "QS $QUERY_STRING " >> /tmp/xx32`;
my ( $jsontype, $par1, $par2, $par3, $par4 ) = split( /&/, $QUERY_STRING );

$par1 = urldecode($par1);
$par2 = urldecode($par2);
$par3 = urldecode($par3);
$par4 = urldecode($par4);

if ( $jsontype eq "" ) {
  if (@ARGV) {
    $jsontype = "jsontype=" . $ARGV[0];

    #$basedir  = "..";
  }
  else {
    $jsontype = "jsontype=dump";
  }
}

$jsontype =~ s/jsontype=//;

if ( $jsontype eq "test" ) {

  #$basedir = "..";
  &test();
  exit;
}

elsif ( $jsontype eq "dump" ) {
  &dumpHTML();
  exit;
}

elsif ( $jsontype eq "menu" ) {
  if ( -r "$basedir/debug/menu.json" ) {
    open( FILE, "<$basedir/debug/menu.json" )
      or die "Can't open file for input: $!";
    while (<FILE>) {
      print;
    }
    close(FILE);
  }
  else {
    &mainMenu(0);
    print JSON->new->utf8(1)->encode( \@menu );
  }

  # print Dumper @menu;
  # print encode_json (\@menu);
  exit;
}
elsif ( $jsontype eq "menuh" ) {
  &mainMenu(1);

  #print Dumper \@menu;
  print JSON->new->utf8(0)->encode( \@menu );
  exit;
}
elsif ( $jsontype eq "defmenu" ) {
  &mainMenu(2);
  exit;
}
elsif ( $jsontype eq "lparsel" ) {
  lparSelect();
  exit;
}
elsif ( $jsontype eq "aclitems" ) {
  &aclSelect();
  exit;
}
elsif ( $jsontype eq "lparselest" ) {
  &lparSelectEst();
  exit;
}
elsif ( $jsontype eq "hmcsel" ) {
  &hmcSelect();
  exit;
}
elsif ( $jsontype eq "powersel" ) {
  &print_all_models();
  exit;
}
elsif ( $jsontype eq "pools" ) {
  &poolsSelect();
  exit;
}
elsif ( $jsontype eq "estpools" ) {
  &poolsSelectEst();
  exit;
}
elsif ( $jsontype eq "lparnames" ) {
  &readMenu();
  $par1 =~ s/term=//;
  &lparNames($par1);
  exit;
}
elsif ( $jsontype eq "histrep" ) {
  &readMenu();
  $par1 =~ s/hmc=//;
  $par2 =~ s/managedname=//;
  $par3 =~ s/type=//;
  $par4 =~ s/hostname=//;
  &histReport( $par1, $par2, $par3, $par4 );
  exit;
}
elsif ( $jsontype eq "env" ) {
  $env{version} = $version;
  readMenu();
  sysInfo();
  exit;
}
elsif ( $jsontype eq "pre" ) {
  &readMenu();
  &genPredefined();
  exit;
}
elsif ( $jsontype eq "cust" ) {
  readMenu();
  custGroupsSelect();
  exit;
}
elsif ( $jsontype eq "custpower" ) {
  readMenu();
  custPowerGroupsSelect();
  exit;
}
elsif ( $jsontype eq "aclgrp" ) {
  &readMenu();
  &aclGroups();
  exit;
}
elsif ( $jsontype eq "fleet" ) {
  &readMenu();
  &genFleet();
  exit;
}
elsif ( $jsontype eq "fleetalrt" ) {
  &readMenu();
  &genFleetAlrt();
  exit;
}
elsif ( $jsontype eq "fleetrpt" ) {
  &readMenu();
  &genFleetReport();
  exit;
}
elsif ( $jsontype eq "fleetree" ) {
  &readMenu();
  &genFleetTree();
  exit;
}
elsif ( $jsontype eq "fleetall" ) {
  &readMenu();
  &genFleetAll();
  exit;
}
elsif ( $jsontype eq "custgrps" ) {
  if ( $ENV{HTTP_XORUX_APP} && $ENV{HTTP_XORUX_APP} eq "Xormon" ) {
    genCustGrpsXormon();
  }
  else {
    genCustGrps();
  }
  exit;
}
elsif ( $jsontype eq "alrttree" ) {
  &readMenu();
  &genAlertTree();
  exit;
}
elsif ( $jsontype eq "alrtgrptree" ) {
  &genAlertGroupTree();
  exit;
}
elsif ( $jsontype eq "alrttimetree" ) {
  &genAlertTimeTree();
  exit;
}
elsif ( $jsontype eq "clusters" ) {
  $par1 =~ s/vc=//;
  &genClusters($par1);
  exit;
}
elsif ( $jsontype eq "datastores" ) {
  $par1 =~ s/vc=//;
  &genDataStores($par1);
  exit;
}
elsif ( $jsontype eq "respools" ) {
  $par1 =~ s/vc=//;
  &genResPools($par1);
  exit;
}
elsif ( $jsontype eq "vms" ) {
  $par1 =~ s/vc=//;
  genVMs($par1);
  exit;
}
elsif ( $jsontype eq "linux" ) {
  &genLinuxHosts();
  exit;
}
elsif ( $jsontype eq "metrics" ) {
  &getMetrics();
  exit;
}
elsif ( $jsontype eq "about" ) {
  about();
  exit;
}
elsif ( $jsontype eq "histrepsrcvm" ) {
  genHistRepSrcVmware();
  exit;
}
elsif ( $jsontype eq "overviewsources" ) {
  readMenu();
  if ( $ENV{HTTP_XORUX_APP} && $ENV{HTTP_XORUX_APP} eq "Xormon" ) {
    overviewSourcesXormon();
  }
  else {
    overviewSources();
  }
  exit;
}
elsif ( $jsontype eq "ibmilist" ) {
  if ( -r "$basedir/tmp/restapi/ibmi_list.json" ) {
    open( my $FILE, "<", "$basedir/tmp/restapi/ibmi_list.json" )
      or die "Can't open file for input: $!";
    while (<$FILE>) {
      print;
    }
    close($FILE);
  }
  exit;
}
elsif ( $jsontype eq "overview_vmware_clusters" ) {
  overview_vmware_clusters();
  exit;
}
elsif ( $jsontype eq "solaris_histrep_ldom" ) {
  readMenu();
  genSolarisHistrepLdom();
  exit;
}
elsif ( $jsontype eq "hyperv_histrep_vms" ) {
  readMenu();
  genHypervHistrepVMs();
  exit;
}
elsif ( $jsontype eq "hyperv_histrep_server" ) {
  readMenu();
  genHypervHistrepServer();
  exit;
}
elsif ( $jsontype eq "oraclevm_histrep_vms" ) {
  readMenu();
  genOraclevmHistrepVMs();
  exit;
}
elsif ( $jsontype eq "oraclevm_histrep_server" ) {
  readMenu();
  genOraclevmHistrepServer();
  exit;
}
elsif ( $jsontype eq "alrtSubmetrics" ) {
  &getAlrtSubmetrics();
  exit;
}

sub sysInfo {
  my @files;
  my $ostype;
  my $sideMenuWidth = "";
  my $vmImage;
  if ( $^O eq "aix" ) {
    @files  = grep { !/\.xh$/ } <$basedir/agent/*aix*>;
    $ostype = "AIX";
  }
  elsif ( $^O eq "linux" ) {
    @files  = grep { !/\.xh$/ } <$basedir/agent/*noarch*>;
    $ostype = "Linux";
  }
  elsif ( $^O eq "linux" ) {
    @files  = grep { !/\.xh$/ } <$basedir/agent/*Linux.ppc*>;
    $ostype = "Linux PPC";
  }
  if ( exists $ENV{'SIDE_MENU_WIDTH'} ) {
    $sideMenuWidth = $ENV{'SIDE_MENU_WIDTH'};
  }
  if ( $ENV{'VM_IMAGE'} ) {
    $vmImage = 1;
  }
  my $technologies = getTechnologies();
  my $variant      = $free ? "" : join( ":", @{ $technologies->{shorts} } );

  my $sshcmd       = $ENV{SSH} ||= "";
  my $xormonUIonly = ( -f "$basedir/etc/web_config/xormonUIonly" );
  no warnings 'uninitialized';
  print "{\n";    # envelope begin
  print "\"version\":\"$env{version}\",\n";
  print "\"free\":\"$env{free}\",\n";
  print "\"variant\":\"$variant\",\n";
  print "\"entitle\":\"$env{entitle}\",\n";
  print "\"dashb_rrdheight\":\"$dashb_rrdheight\",\n";
  print "\"dashb_rrdwidth\":\"$dashb_rrdwidth\",\n";
  print "\"legend_height\":\"$legend_height\",\n";
  print "\"picture_color\":\"$pic_col\",\n";
  print "\"guidebug\":\"$GUIDEBUG\",\n";
  print "\"demo\":" . &boolean($DEMO) . ",\n";
  print "\"beta\":\"$BETA\",\n";
  print "\"custom_page_title\":\"$TITLE\",\n";
  print "\"rpm\":\"$files[0]\",\n";
  print "\"ostype\":\"$ostype\",\n";
  print "\"basedir\":\"$basedir\",\n";
  print "\"wlabel\":\"$WLABEL\",\n";
  print "\"basename\":" . &boolean( $env{free} eq "1" ? 1 : 0 ) . ",\n";
  print "\"listbyhmc\":" . &boolean($listByHMC) . ",\n";
  print "\"hasPower\":" . &boolean( $env{platform}{power} ) . ",\n";
  print "\"hasVMware\":" . &boolean( $env{platform}{vmware} && !$ENV{EXCLUDE_VMWARE} ) . ",\n";
  print "\"useRestAPIExclusion\":" . &boolean( $ENV{USE_RESTAPI_EXCLUSION} ) . ",\n";
  print "\"useOldDashboard\":" . &boolean( $ENV{USE_OLD_DASHBOARD} ) . ",\n";
  print "\"hasVMwareAgent\":" . &boolean( $env{hasVMwareAgent} ) . ",\n";
  print "\"hasSolaris\":" . &boolean( $env{platform}{solaris} ) . ",\n";
  print "\"hasXen\":" . &boolean( $env{platform}{xen} ) . ",\n";
  print "\"hasNutanix\":" . &boolean( $env{platform}{nutanix} ) . ",\n";
  print "\"hasAWS\":" . &boolean( $env{platform}{aws} ) . ",\n";
  print "\"hasGCloud\":" . &boolean( $env{platform}{gcloud} ) . ",\n";
  print "\"hasAzure\":" . &boolean( $env{platform}{azure} ) . ",\n";
  print "\"hasKubernetes\":" . &boolean( $env{platform}{kubernetes} ) . ",\n";
  print "\"hasOpenshift\":" . &boolean( $env{platform}{openshift} ) . ",\n";
  print "\"hasCloudstack\":" . &boolean( $env{platform}{cloudstack} ) . ",\n";
  print "\"hasProxmox\":" . &boolean( $env{platform}{proxmox} ) . ",\n";
  print "\"hasDocker\":" . &boolean( $env{platform}{docker} ) . ",\n";
  print "\"hasFusionCompute\":" . &boolean( $env{platform}{fusioncompute} ) . ",\n";
  print "\"hasOVirt\":" . &boolean( $env{platform}{ovirt} ) . ",\n";
  print "\"hasLinux\":" . &boolean( $env{platform}{linux} ) . ",\n";
  print "\"hasUnmanaged\":" . &boolean( $env{platform}{unmanaged} ) . ",\n";
  print "\"hasHyperV\":" . &boolean( $env{platform}{hyperv} ) . ",\n";
  print "\"hasOracleVM\":" . &boolean( $env{platform}{orvm} ) . ",\n";
  print "\"hasOracleDB\":" . &boolean( $env{platform}{odb} ) . ",\n";
  print "\"hasPostgreSQL\":" . &boolean( $env{platform}{postgres} ) . ",\n";
  print "\"hasSQLServer\":" . &boolean( $env{platform}{sqlserver} ) . ",\n";
  print "\"hasDB2\":" . &boolean( $env{platform}{db2} ) . ",\n";
  print "\"vmImage\":" . &boolean($vmImage) . ",\n";
  print "\"XorMon\":" . &boolean( $ENV{XORMON} ) . ",\n";
  print "\"xormonUIonly\":" . &boolean($xormonUIonly) . ",\n";
  print "\"oracleEnabled\":" . &boolean( $ENV{ORACLE_ENABLED} ) . ",\n";
  print "\"useOVirtRestAPI\":" . &boolean( $ENV{USE_OVIRT_RESTAPI} ) . ",\n";
  print "\"uid\":\"$uid\",\n";
  print "\"gid\":\"$grpnames\",\n";
  print "\"sideMenuWidth\":\"$sideMenuWidth\",\n";
  print "\"isAdmin\":" . &boolean($isAdmin) . ",\n";
  print "\"useACL\":" . &boolean($useacl) . ",\n";
  print "\"aclAdminGroup\":\"$aclAdminGroup\",\n";

  if ( -f "$basedir/html/.b" ) {
    print "\"unlimitedRAC\": true,\n";
  }
  print "\"vmImage\":" . &boolean($vmImage) . ",\n";
  print "\"sshcmd\":\"$sshcmd\"\n";
  print "}\n";    # envelope end
}

sub dumpHTML {

  #use Data::Dumper;
  print "Content-type: application/octet-stream\n";
  print("Content-Disposition:attachment;filename=debug.txt\n\n");
  my $buffer;
  if ( $ENV{'CONTENT_LENGTH'} ) {
    read( STDIN, $buffer, $ENV{'CONTENT_LENGTH'} );
    if ($buffer) {
      my @pairs = split( /&/, $buffer );

      my @q    = split( /=/, $pairs[1] );
      my $html = urldecode( $q[1] );
      print $html;
    }
  }
  mainMenu(0);

  # print encode_json ( \@menu );

  # print Dumper @menu;

  #use CGI;
  #use CGI('header');
  #print header(-type=>'application/octet-stream',
  #       -attachment=>'debug.txt');
  #my $q = new CGI;
  #print $q->param('tosave');

}

sub test {
  print "Content-type: text/plain\n\n";

  use Data::Dumper;

  # my $Dumper = new Data::Dumper;
  # Data::Dumper->import();
  # import Data::Dumper qw(Dumper);

  #print Dumper @aclServ;
  #print Dumper @aclCust;
  #print Dumper \%aclLpars;
  #print Dumper $acl->{cfg}{groups};
  #print $acl->canShow("POWER", "SERVER", "chst3m05"); # . " " . $acl->canShow("POWER", "POOL", $s, @$_[2]);
  readMenu();

  #print $acl->canShow("POWER", "SERVER", "chst3m05"); # . " " . $acl->canShow("POWER", "POOL", $s, @$_[2]);
  #print Dumper $acl->{cfg}{groups};
  #print Dumper \%env;
  #print Dumper \$pack{datastore};
  print Dumper \%pack;

  #my %alerts = Alerting::getAlerts();
  #print Dumper \%alerts;
  #print Dumper $acl->getGroups();
  #print $acl->canShow("POWER", "SERVER", "chst3m08"); # . " " . $acl->canShow("POWER", "POOL", $s, @$_[2]);
  #my $d = Data::Dumper->new(*$pack{lstree});
  #print $d->Dump();
  #print $Dumper->Dump( \$pack{lhmc} );
  #print Dumper $pack{stree};
  # print Dumper \$pack{lnames};
  #print Dumper $pack{cluster};
  #print Dumper $pack{vtree};
  #print Dumper $pack{soltree};

  #print Dumper \$pack{times};
  #print Dumper \$pack{vclusters};
  #print Dumper $pack{hyperv};

  #print Dumper $pack{fleet};
  #  &mainMenu(0);
  #  print Dumper \@menu;
  # &genHMCs;
  # print encode_json( \$pack{lstree} );
  #	print ($pack{ctreeh} > 0 ? "true" : "false" );
}

sub mainMenu {

  # local *STDOUT;
  # open STDOUT, ">", \$x or die "Can't open STDOUT: $!\n";
  my $showHMC = shift;
  &readMenu( 0, $showHMC );
  my $variant = $env{variant} eq "p" ? "<span style='font-weight: normal'>(free)</span>" : "";
  my $hash    = substr( md5_hex("DASHBOARD"), 0, 7 );
  ### Generate JSON
  push @menu, { "title" => "DASHBOARD", "extraClasses" => "boldmenu", "href" => "dashboard.html", "hash" => "$hash" };
  &custs();
  $hash = substr( md5_hex("Reporter"), 0, 7 );
  push @menu, { "title" => "Reporter", "extraClasses" => "boldmenu", "href" => "/lpar2rrd-cgi/reporter.sh?cmd=form", "hash" => "$hash" };

  ##### Global overview disabled for now
  $hash = substr( md5_hex("global_overview"), 0, 7 );

  #push @menu, { "title" => "Overview", "extraClasses" => "boldmenu", "href" => "global_overview.html", "hash" => "$hash" };

  #if ( !$useacl || $isAdmin ) {
  #$hash = substr( md5_hex("alert"), 0, 7 );
  #push @menu, { "title" => "Alerting", "extraClasses" => "boldmenu", "href" => "/lpar2rrd-cgi/alcfg.sh?cmd=form", "hash" => "$hash" };
  #}
  if ( !$useacl || $isAdmin || $isReadonly ) {
    globalWoTitle();
  }
  if ( $env{platform}{power} ) {
    if ( scalar keys %{ $env{platform} } > 1 ) {
      $idx{psrv} = push @menu, { "title" => "IBM Power Systems", "folder" => "true", "children" => [] };
      $idx{psrv}--;

      #$hash = substr( md5_hex("overview_power"), 0, 7 );
      #push @{ $menu[ $idx{psrv} ]{children} }, { "title" => "Overview", "extraClasses" => "boldmenu", "href" => "overview_power.html", "hash" => "$hash" };
      for ( sort keys %{ $pack{global}{P} } ) {
        my $t  = $pack{global}{P}{$_}{text};
        my $u  = $pack{global}{P}{$_}{url};
        my $id = $pack{global}{P}{$_}{id};
        if ( lc $t eq "custom groups" || lc $t eq "alerting" ) {
          next;
        }
        push @{ $menu[ $idx{psrv} ]{children} }, pushmenu( $t, $u, $id );
      }
      globalHmcTotals();
    }
    else {
      if ($showHMC) {
        $idx{psrv} = push @menu, { "title" => "HMC", "folder" => "true", "children" => [] };
        $idx{psrv}--;
      }
      else {
        $idx{psrv} = push @menu, { "title" => "SERVER", "folder" => "true", "children" => [] };
        $idx{psrv}--;
      }
      if ( $pack{cmc} ) {
        if ( 1 || $acl->canShow("CMC") ) {
          $idx{psrv} = push @menu, $pack{cmc};
          $idx{psrv}--;
        }
      }
    }
    if ($showHMC) {
      &genHMCs();    # List by HMCs
    }
    else {
      &genServers();    # List by Servers
    }
  }
  if ( $env{platform}{vmware} && !$ENV{EXCLUDE_VMWARE} ) {
    if ( !$idx{vmware} ) {
      $idx{vmware} = push @menu, { "title" => "VMware", "folder" => "true", "children" => [] };
      $idx{vmware}--;
    }
    if ( scalar keys %{ $env{platform} } > 1 ) {
      for ( sort keys %{ $pack{global}{V} } ) {
        my $t  = $pack{global}{V}{$_}{text};
        my $u  = $pack{global}{V}{$_}{url};
        my $id = $pack{global}{V}{$_}{id};
        push @{ $menu[ $idx{vmware} ]{children} }, pushmenu( $t, $u, $id );
      }

    }

    # print STDERR "XXXXX\n";
    &genVMware;
  }
  if ( !$env{platform} ) {
    for ( sort keys %{ $pack{global}{P} } ) {
      my $t  = $pack{global}{P}{$_}{text};
      my $u  = $pack{global}{P}{$_}{url};
      my $id = $pack{global}{P}{$_}{id};
      if ( lc $t eq "custom groups" || lc $t eq "alerting" ) {
        next;
      }
      push @menu, pushmenu( $t, $u, $id );
    }
  }
  if ( $pack{nutanix} ) {
    if ( $acl->canShow("NUTANIX") ) {
      $idx{nutanix} = push @menu, $pack{nutanix};
      $idx{nutanix}--;
    }
  }
  if ( $pack{proxmox} ) {
    if ( $acl->canShow("PROXMOX") ) {
      $idx{proxmox} = push @menu, $pack{proxmox};
      $idx{proxmox}--;
    }
  }
  if ( $pack{fusioncompute} ) {
    if ( $acl->canShow("FUSIONCOMPUTE") ) {
      $idx{fusioncompute} = push @menu, $pack{fusioncompute};
      $idx{fusioncompute}--;
    }
  }
  if ( $pack{ovirt} ) {
    if ( $acl->canShow("OVIRT") ) {
      $idx{ovirt} = push @menu, $pack{ovirt};
      $idx{ovirt}--;
    }
  }
  if ( $pack{xen} ) {
    if ( $acl->canShow("XENSERVER") ) {
      $idx{xen} = push @menu, $pack{xen};
      $idx{xen}--;
    }
  }
  if ( $env{platform}{hyperv} ) {
    if ( $acl->canShow("HYPERV") ) {
      genHyperV(1);
    }
  }
  if ( $env{platform}{solaris} ) {
    if ( $acl->canShow("SOLARIS") ) {
      genSolaris(1);
    }
  }
  if ( $pack{orvm} ) {
    if ( $acl->canShow("ORACLEVM") ) {
      $idx{orvm} = push @menu, $pack{orvm};
      $idx{orvm}--;
    }
  }
  if ( $env{platform}{blade} ) {
    genHitachi(1);
  }
  if ( $pack{aws} ) {
    if ( $acl->canShow("AWS") ) {
      $idx{aws} = push @menu, $pack{aws};
      $idx{aws}--;
    }
  }
  if ( $pack{azure} ) {
    if ( $acl->canShow("AZURE") ) {
      $idx{azure} = push @menu, $pack{azure};
      $idx{azure}--;
    }
  }
  if ( $pack{gcloud} ) {
    if ( $acl->canShow("GCLOUD") ) {
      $idx{gcloud} = push @menu, $pack{gcloud};
      $idx{gcloud}--;
    }
  }
  if ( $pack{cloudstack} ) {
    if ( $acl->canShow("CLOUDSTACK") ) {
      $idx{cloudstack} = push @menu, $pack{cloudstack};
      $idx{cloudstack}--;
    }
  }
  if ( $pack{kubernetes} ) {
    if ( $acl->canShow("KUBERNETES") ) {
      $idx{kubernetes} = push @menu, $pack{kubernetes};
      $idx{kubernetes}--;
    }
  }
  if ( $pack{openshift} ) {
    if ( $acl->canShow("OPENSHIFT") ) {
      $idx{openshift} = push @menu, $pack{openshift};
      $idx{openshift}--;
    }
  }
  if ( $pack{docker} ) {
    if ( $acl->canShow("DOCKER") ) {
      $idx{docker} = push @menu, $pack{docker};
      $idx{docker}--;
    }
  }
  if ( $pack{odb} ) {
    if ( $acl->canShow("ORACLEDB") ) {
      $idx{odb} = push @menu, $pack{odb};
      $idx{odb}--;
    }
  }
  if ( $pack{postgres} ) {
    if ( $acl->canShow("POSTGRES") ) {
      $idx{postgres} = push @menu, $pack{postgres};
      $idx{postgres}--;
    }
  }
  if ( $pack{sqlserver} ) {
    if ( $acl->canShow("SQLSERVER") ) {
      $idx{sqlserver} = push @menu, $pack{sqlserver};
      $idx{sqlserver}--;
    }
  }
  if ( $pack{db2} ) {
    if ( $acl->canShow("DB2") ) {
      $idx{db2} = push @menu, $pack{db2};
      $idx{db2}--;
    }
  }
  if ( $env{platform}{linux} ) {
    genLinux(1);
  }
  if ( $env{platform}{unmanaged} ) {
    &genStandalone(1);    # List by Servers
  }

  #	&genHMCs ();  # List by HMCs

  # &tail();
  ### End of JSON
}

sub lparSelect {
  &readMenu();
  ### Generate JSON
  print "[\n";      # envelope begin
  genLpars();       # List by Servers
  print "\n]\n";    # envelope end
  ### End of JSON
}

sub lparSelectEst {
  &readMenu();
  ### Generate JSON
  print "[\n";       # envelope begin
  &genLparsEst();    # List by Servers
  print "\n]\n";     # envelope end
  ### End of JSON
}

sub hmcSelect {
  &readMenu();
  ### Generate JSON
  print "[\n";        # envelope begin
  &genHmcSelect();    # List by HMCs
  print "\n]\n";      # envelope end
  ### End of JSON
}

sub poolsSelect {
  &readMenu();
  ### Generate JSON
  print "[\n";        # envelope begin
  &genPools();        # generate list of Pools
  print "\n]\n";      # envelope end
  ### End of JSON
}

sub poolsSelectEst {
  &readMenu();
  ### Generate JSON
  print "[\n";        # envelope begin
  &genPoolsEst();     # generate list of Pools
  print "\n]\n";      # envelope end
  ### End of JSON
}

sub custGroupsSelect {
  ### Generate JSON
  print "[\n";        # envelope begin
  genCusts();         #
  print "\n]\n";      # envelope end
  ### End of JSON
}

sub custPowerGroupsSelect {
  ### Generate JSON
  print "[\n";          # envelope begin
  genCusts("Power");    #
  print "\n]\n";        # envelope end
  ### End of JSON
}

sub aclGroups {
  ### Generate JSON
  print "[\n";          # envelope begin
  if ($useacl) {
    my $delim = '';
    for ( $acl->getCfgGroups() ) {
      if ( $_ ne $aclAdminGroup ) {
        print $delim . "{\"title\":\"$_\"}";
        $delim = ",\n";
      }
    }
  }
  print "\n]\n";        # envelope end
  ### End of JSON
}

sub readMenu {
  my $alt     = shift;
  my $defmenu = shift;
  my $tmppath = "tmp";
  if ($alturl) {
    my @parts = split( /\//, $ENV{HTTP_REFERER} );
    if ( $ENV{HTTP_REFERER}
      && ( $parts[-1] ne $alturl )
      && ( $parts[-2] ne $alturl ) )
    {    # URL doesn't match WWW_ALTERNATE_URL
      $tmppath = $alttmp;    # use menu from WWW_ALTERNATE_TMP
    }
    if ($alt) {
      $tmppath = $alttmp;
    }
  }

  my $skel;
  if ( -r "$basedir/debug/menu.txt" ) {
    $skel = file_read("$basedir/debug/menu.txt");
  }
  elsif ( !-r "$basedir/$tmppath/menu.txt" || defined $defmenu && $defmenu == 2 ) {
    $skel = file_read("$basedir/html/menu_default.txt");
  }
  else {
    $skel = file_read("$basedir/$tmppath/menu.txt");
  }

  foreach my $line ( split /^/, $skel ) {
    my ( $hmc, $srv, $txt, $url );
    chomp $line;
    next if length($line) < 2;
    next if substr( $line, 0, 1 ) !~ /[A-Za-z0-9]/;

    my @val = split( ':', $line );
    for (@val) {
      &collons($_);
    }
    {
      "O" eq $val[0] && do {
        $env{variant} = $val[2] ||= "";
        last;
      };
      "E" eq $val[0] && do {
        $env{entitle} = ( $val[1] == 1 ) ? 1 : 0;
        last;
      };
      "G" eq $val[0] && do {
        my ( $id, $txt, $url, $type ) = ( $val[1], $val[2], $val[3], $val[8] );
        if ( $txt eq "HMC totals" ) { last; }
        if ( $txt eq "FAVOURITES" ) {
          $type = "";
        }
        my $cnt = keys %{ $pack{global}{$type} };
        $pack{global}{$type}{$cnt}{text} = $txt;
        $pack{global}{$type}{$cnt}{url}  = $url;
        $pack{global}{$type}{$cnt}{id}   = $id;
        last;
      };
      "F" eq $val[0] && do {
        my ( $txt, $url ) = ( $val[2], $val[3] );
        push @{ $pack{ftreeh} }, [ $txt, $url ];
        last;
      };
      "C" eq $val[0] && do {
        my ( $txt, $url, $type ) = ( $val[2], $val[3], $val[8] );
        if ( !$useacl || $isAdmin || $isReadonly || $acl->canShow( "", "CUSTOM", $txt ) ) {
          if ( $txt ne "<b>Configuration</b>" ) {
            push @{ $pack{ctree} }, [ $txt, $url, $type ];
            $pack{ctreeh}{$txt} = $url;
          }
        }
        last;
      };
      "H" eq $val[0] && do {
        my ( $id, $txt, $url, $type ) = ( $val[1], $val[2], $val[3], $val[8] );
        $pack{hmc}{$txt}{url} = $url;
        $pack{hmc}{$txt}{id}  = $id;
        if ($type) {
          $pack{hmc}{$txt}{type} = $type;
        }
        last;
      };

      #S:ahmc11:BSRV21:CPUpool-pool:CPU pool:ahmc11/BSRV21/pool/gui-cpu.html::1399967748
      "S" eq $val[0] && do {
        my ( $hmc, $srv, $pool, $txt, $url, $alias, $timestamp, $type ) = ( $val[1], $val[2], $val[3], $val[4], $val[5], $val[6], $val[7], $val[8] );
        my $onList = 0;
        if ( $ENV{HTTP_XORUX_APP} && $ENV{HTTP_XORUX_APP} eq "Xormon" ) {
          if ( $pool =~ /^CPUpool/ ) {
            my $url_new     = '';
            my $url_new_tmp = Xorux_lib::url_old_to_new($url);
            $url_new = $url_new_tmp if ( defined $url_new_tmp );
            ( undef, $url_new ) = split( "\\?", $url_new ) if ( $url_new =~ m/\?/ );
            my $url_params = Xorux_lib::parse_url_params($url_new);
            if ( $url_params->{id} && $url_params->{id} ne "not_found" ) {
              my $hw_type = uc $url_params->{platform};
              my $aclitem = { hw_type => $hw_type, subsys => "Shared Pool", id => $url_params->{id}, match => 'granted' };
              if ( $acl->isGranted($aclitem) ) {

                #warn "uid: $acl->{uid}, acl: {hw_type => $hw_type, subsys => 'Shared Pool', id => $url_params->{id}, match => 'granted'}";
                $onList = 1;
              }
            }
          }
        }
        else {
          $onList = $acl->canShow( $platform{$type}, "SERVER", $srv, "" ) || ( $type eq "P" && $acl->hasItems( "O", $srv ) );
        }

        # my $onList = 1;
        if ( !$useacl || $isAdmin || $isReadonly || $onList ) {
          $pack{fleet}{$srv}{platform} ||= $type;

          if ($timestamp) {
            if ( !exists $pack{times}{$srv}{timestamp}{$hmc} || $pack{times}{$srv}{timestamp}{$hmc} == 999 ) {
              $pack{times}{$srv}{timestamp}{$hmc} = $timestamp;
            }
          }
          if ( $type eq "X" ) {
            $env{platform}{xen} ||= 1;
            $hmc                                      = $pool;
            $srv                                      = $val[1];
            $pack{xen}{pool}{$srv}{label}{$hmc}{text} = $txt;
            $pack{xen}{pool}{$srv}{label}{$hmc}{url}  = $url;
          }
          elsif ( $type eq "V" ) {
            $env{platform}{vmware} ||= 1;
            my $cluster = $hmc;
            $hmc = ( $url =~ /host=([^&]*)/ )[0];
            if ( !$cluster ) {
            }
            elsif ( $cluster =~ /^cluster_/ ) {
              push @{ $pack{vtree}{vc}{$hmc}{cluster}{$cluster}{host}{$srv}{menu} }, { $txt => $url };
            }
            else {
              push @{ $pack{vtree}{vc}{$hmc}{host}{$srv}{menu} }, { $txt => $url };
            }
          }
          elsif ( $type eq "P" ) {
            $env{platform}{power} ||= 1;
          }
          elsif ( $type eq "B" ) {
            $env{platform}{blade} ||= 1;
          }
          elsif ( $type eq "H" ) {
            $env{platform}{hyperv} ||= 1;
            $pack{hyperv}{dom}{$hmc}{server}{$srv}{totals}{$txt} = $url;
          }
          if ( !$pack{times}{$srv}{"active"} ) {
            $pack{times}{$srv}{"active"} = 1;
          }
          $pack{times}{$srv}{"removed"}{$hmc} = 0;
          if ($type) {
            $pack{times}{$srv}{type} = $type;
          }
          if ($alias) {
            $pack{times}{$srv}{alias} = $alias;
          }
          if ( $pool =~ /^CPUpool/ ) {
            $pool = substr( $pool, 8 );
          }
          elsif ( $pool eq "pagingagg" || $pool eq "mem" ) {
            $pool = "cod";
          }
          elsif ( $pool eq "hea" ) {
            $pool = "hea";
          }
          else {
            $pool = "";
          }
          push @{ $pack{stree}{$srv}{$hmc} }, [ $txt, $url, $pool ];
          if ( $url =~ /item=pool/ ) {
            my $poolname = "CPU pool";
            $pack{fleet}{$srv}{subsys}{POOL}{$poolname}{value} = $pool;
            $pack{fleet}{$srv}{subsys}{POOL}{$poolname}{type}  = "pool";
          }
          elsif ( $url =~ /item=shpool/ ) {
            my $type     = ( $url =~ /item=([^&]*)/ )[0];
            my $poolname = ( split " : ", $txt )[1];
            $poolname ||= $pool;
            $pack{fleet}{$srv}{subsys}{POOL}{$poolname}{value} = $pool;
            $pack{fleet}{$srv}{subsys}{POOL}{$poolname}{type}  = "shpool";
          }
        }
        last;
      };
      "D" eq $val[0] && do {
        my ( $hmc, $srv, $pool, $txt, $url, $timestamp, $type ) = ( $val[1], $val[2], $val[3], $val[4], $val[5], $val[7], $val[8] );
        if ( !$useacl || $isAdmin || $isReadonly ) {
          if ($timestamp) {
            if ( $type ne "V" && (!exists $pack{times}{$srv}{timestamp}{$hmc} || $pack{times}{$srv}{timestamp}{$hmc} == 999 )) {
              $pack{times}{$srv}{timestamp}{$hmc} = $timestamp;
            }
          }
          if ( !$pack{times}{$srv}{active} ) {
            $pack{times}{$srv}{"active"} = 0;
          }
          $pack{times}{$srv}{"removed"}{$hmc} = 1;
          if ($type) {
            $pack{times}{$srv}{type} = $type;
          }
          if ( $type eq "V" ) {
            $env{platform}{vmware} ||= 1;
            my $cluster = $hmc;
            $hmc = ( $url =~ /host=([^&]*)/ )[0];
            if ( !$cluster ) {
            }
            elsif ( $cluster =~ /^cluster_/ ) {
              $pack{vtree}{vc}{$hmc}{cluster}{$cluster}{host}{$srv}{removed} ||= 1;
              $pack{vtree}{vc}{$hmc}{cluster}{$cluster}{removed} ||= 1;
            }
            else {
              $pack{vtree}{vc}{$hmc}{host}{$srv}{removed} ||= 1;
            }
          }
          if ( $pool =~ /^CPUpool/ ) {
            $pool = substr( $pool, 8 );
          }
          else {
            $pool = "";
          }
          push @{ $pack{stree}{$srv}{$hmc} }, [ $txt, $url, $pool ];
        }
        last;
      };
      "L" eq $val[0] && do {
        my ( $hmc, $srv, $atxt, $txt, $url, $valias, $type, $mset, $folder ) = ( $val[1], $val[2], $val[3], $val[4], $val[5], $val[7], $val[8], $val[9], $val[10] );
        my $onList = 0;
        if ( $ENV{HTTP_XORUX_APP} && $ENV{HTTP_XORUX_APP} eq "Xormon" ) {
          my $url_new     = '';
          my $url_new_tmp = Xorux_lib::url_old_to_new($url);
          $url_new = $url_new_tmp if ( defined $url_new_tmp );
          ( undef, $url_new ) = split( "\\?", $url_new ) if ( $url_new =~ m/\?/ );
          my $url_params = Xorux_lib::parse_url_params($url_new);
          if ( $url_params->{id} && $url_params->{id} ne "not_found" ) {
            my $aclitem = { hw_type => uc $url_params->{platform}, item_id => $url_params->{id}, match => 'granted' };
            if ( $acl->isGranted($aclitem) ) {

              #warn "uid: $acl->{uid} $aclitem";
              $onList = 1;
            }
          }
        }
        else {
          if ( $type eq "P" ) {
            if ( $hmc eq "no_hmc" ) {
              if ( $srv ne "Linux" ) {
                $onList = $acl->canShow( $platform{$type}, "SERVER", $srv, $txt );
              }
              else {
                $onList = $acl->canShow( "LINUX", "SERVER", "", $txt );
              }
            }
            else {
              #warn "$platform{$type}, LPAR, $srv, $atxt";
              $onList = $acl->canShow( $platform{$type}, "LPAR", $srv, $atxt );

              #warn "HERE $onList";
            }
          }
          elsif ( $type eq "V" ) {
            $onList = $acl->canShow( $platform{$type}, "VM", $hmc, $txt );
          }

          # elsif ( $type eq "S" || $type eq "B" || $type eq "X" ) {
          else {
            $onList = $acl->canShow( $platform{$type} );

            # $hmc = "";
          }
        }
        if ( $hmc eq "no_hmc" && $type eq "P" ) {
          $type = "U";
        }
        if ( $type eq "X" ) {
          $hmc = "XEN";
          $srv = "XEN";
        }
        if ( $type eq "N" ) {
          $hmc = "NUTANIX";
          $srv = "NUTANIX";
        }
        if ( $type eq "A" ) {
          $hmc = "AWS";
          $srv = "AWS";
        }
        if ( $type eq "G" ) {
          $hmc = "GCloud";
          $srv = "GCloud";
        }
        if ( $type eq "Q" ) {
          $hmc = "ORACLEDB";
          $srv = "ORACLEDB";
        }
        if ( $type eq "Z" ) {
          $hmc = "Azure";
          $srv = "Azure";
        }
        if ( $type eq "K" ) {
          $hmc = "Kubernetes";
          $srv = "Kubernetes";
        }
        if ( $type eq "R" ) {
          $hmc = "Openshift";
          $srv = "Openshift";
        }
        if ( $type eq "E" ) {
          $hmc = "Cloudstack";
          $srv = "Cloudstack";
        }
        if ( $type eq "M" ) {
          $hmc = "Proxmox";
          $srv = "Proxmox";
        }
        if ( $type eq "I" ) {
          $hmc = "Docker";
          $srv = "Docker";
        }
        if ( $type eq "W" ) {
          $hmc = "FusionCompute";
          $srv = "FusionCompute";
        }
        if ( $type eq "T" ) {
          $hmc = "Postgres";
          $srv = "Postgres";
        }
        if ( $type eq "D" ) {
          $hmc = "SQLServer";
          $srv = "SQLServer";
        }
        if ( $type eq "F" ) {
          $hmc = "DB2";
          $srv = "DB2";
        }

             #if (! exists $pack{hmc}{$hmc}) {
             #if ($type) {
             #$pack{hmc}{$hmc}{type} = $type;
             #}
             #}
        if ( !$useacl || $isAdmin || $isReadonly || $onList ) {
          $atxt = urldecode($atxt);
          if ( $type ne "S" && $type ne "H" ) {
            if ( $type ne "P" ) {
              push @{ $pack{lstree}{$srv}{$hmc} }, [ $txt, $url, $atxt ];
            }
            push @{ $pack{lhmc}{$hmc}{$srv} }, [ $txt, $url, $atxt ];
          }
          if ( ( $hmc eq "no_hmc" )
            or ( !exists $pack{times}{$srv}{timestamp}{$hmc} ) )
          {
            if ( $srv ne "Linux" ) {
              $pack{times}{$srv}{timestamp}{$hmc} = 999;
            }
          }
          if ( $hmc eq "no_hmc" && !$pack{times}{$srv}{active} ) {
            if ( $srv ne "Linux" && $type eq "U" ) {
              $pack{times}{$srv}{"active"} = 1;
              $env{platform}{unmanaged} ||= 1;
            }
          }
          if ( !exists $pack{times}{$srv}{active} ) {
            $pack{times}{$srv}{"active"} = 1;
          }
          if ( !exists $pack{times}{$srv}{type} ) {
            $pack{times}{$srv}{type} = $type;
          }
          if ( $hmc eq "no_hmc" && $mset eq "I" ) {
            $pack{fleet}{$srv}{platform} ||= "P";
          }
          else {
            $pack{fleet}{$srv}{platform} ||= $type;
          }
          if ( $type eq "P" ) {
            $pack{lnames}{$type}{$srv}{$txt}  = $atxt;
            $pack{lpartree}{$srv}{$atxt}{url} = $url;
            $pack{lpartree}{$srv}{$atxt}{alt} = $txt;
            $env{platform}{power} ||= 1;
            $pack{fleet}{$srv}{subsys}{LPAR}{ urldecode($atxt) }{type} = $mset;
          }
          elsif ( $type eq "V" ) {
            $env{platform}{vmware} ||= 1;
            $pack{lnames}{$type}{$valias}{$txt} = $atxt;
            my $vc = $pack{vtree}{alias}{$valias};
            if ( !$pack{vtree}{vc}{$vc}{cluster}{$hmc}{vms} ) {
              $pack{vtree}{vc}{$vc}{cluster}{$hmc}{vms} = {};
            }
            my $hash_ref = $pack{vtree}{vc}{$vc}{cluster}{$hmc}->{vms};
            if ($folder) {
              $folder =~ s/\/$//;
              my @path = split( "/", $folder );
              if ( !$hash_ref->{folders} ) {
                $hash_ref->{folders} = {};
              }
              my $level;
              foreach $level (@path) {
                if ( !$hash_ref->{folders}{$level} ) {
                  $hash_ref->{folders}{$level} = {};
                }
                $hash_ref = $hash_ref->{folders}{$level};
              }
            }
            if ( !$hash_ref->{items} ) {
              $hash_ref->{items} = {};
            }
            $hash_ref->{items}{$txt} = 1;
            if ($mset) {
              $env{hasVMwareAgent} ||= 1;
              ( my $cls = $hmc ) =~ s/cluster_//;
              $pack{fleet}{$cls}{subsys}{LPAR}{$txt}{type} = $mset;

              # $pack{fleet}{$cls}{subsys}{LPAR}{$txt}{uuid} = $atxt;
              $pack{fleet}{$cls}{platform} ||= $type;
              $pack{fleet}{$cls}{uuid}{$txt}    = $atxt;
              $pack{fleet}{$cls}{cluster}{$txt} = $cls;
            }
          }
          elsif ( $type eq "S" ) {
            $env{platform}{solaris}      ||= 1;
            $pack{times}{$srv}{type}     ||= $type;
            $pack{times}{$srv}{"active"} ||= 1;
            if ( $mset eq "T" ) {
              push @{ $pack{stree}{$srv}{solaris} }, [ $txt, $url ];
            }
            elsif ( $mset eq "Z" ) {
              $pack{lnames}{$type}{$valias}{$txt} = $atxt;
              push @{ $pack{lstree}{$srv}{$hmc} }, [ $txt, $url, $atxt ];
              $pack{soltree}{host}{$srv}{zone}{$txt}{url} = $url;
              if ( $txt ne $atxt ) {
                $pack{soltree}{host}{$srv}{zone}{$txt}{alt} = $atxt;
              }
              if ($valias) {
              }
            }
            elsif ( $mset eq "L" ) {
              $pack{soltree}{host}{$srv}{ldom}{Totals}{url} = $url;
              $pack{stree}{$srv}{soltotal}{txt}             = "Totals";
              $pack{stree}{$srv}{soltotal}{url}             = $url;
              if ($valias) {
                if ( $valias ne $srv ) {
                  $pack{soltree}{host}{$srv}{parent} = $valias;
                  $pack{soltree}{host}{$valias}{children}{$srv} = 1;
                }
              }
            }
            elsif ( $mset eq "G" ) {
              $pack{soltree}{host}{$srv}{globzone}{Totals}{url} = $url;
              $pack{stree}{$srv}{soltotal}{txt}                 = "Totals";
              $pack{stree}{$srv}{soltotal}{url}                 = $url;
            }
            elsif ( $mset eq "P" ) {
              $pack{soltree}{totals} = $url;
            }

            #my $host = ( $url =~ /host=([^&]*)/ )[0];
            #if ($host) {
            #$srv = $host;
            #}
          }
          elsif ( $type eq "U" ) {
            if ( $mset eq "S" ) {

              # $env{platform}{solaris} ||= 1;
              $pack{fleet}{$srv}{subsys}{LPAR}{$txt}{type} = "S";
            }
            elsif ( $srv eq "Linux" ) {
              $env{platform}{linux} ||= 1;
              $pack{fleet}{$srv}{platform} = "L";
              $pack{fleet}{$srv}{subsys}{LPAR}{$txt}{type} = "L";
            }
            else {
              $pack{fleet}{$srv}{subsys}{LPAR}{$txt}{type} = "U";
            }
          }
          elsif ( $type eq "B" ) {
            $env{platform}{blade} ||= 1;
            $pack{fleet}{$srv}{subsys}{LPAR}{$txt}{type} = "S";
          }
          elsif ( $type eq "X" ) {
            $env{platform}{xen} ||= 1;
            $pack{fleet}{$srv}{subsys}{LPAR}{$txt}{type} = "X";
          }
          elsif ( $type eq "N" ) {
            $env{platform}{nutanix} ||= 1;
            $pack{fleet}{$srv}{subsys}{LPAR}{$txt}{type} = "N";
          }
          elsif ( $type eq "A" ) {
            $env{platform}{aws} ||= 1;
            $pack{fleet}{$srv}{subsys}{LPAR}{$txt}{type} = "A";
          }
          elsif ( $type eq "G" ) {
            $env{platform}{gcloud} ||= 1;
            $pack{fleet}{$srv}{subsys}{LPAR}{$txt}{type} = "G";
          }
          elsif ( $type eq "Z" ) {
            $env{platform}{azure} ||= 1;
            $pack{fleet}{$srv}{subsys}{LPAR}{$txt}{type} = "Z";
          }
          elsif ( $type eq "K" ) {
            $env{platform}{kubernetes} ||= 1;
            $pack{fleet}{$srv}{subsys}{LPAR}{$txt}{type} = "K";
          }
          elsif ( $type eq "R" ) {
            $env{platform}{openshift} ||= 1;
            $pack{fleet}{$srv}{subsys}{LPAR}{$txt}{type} = "R";
          }
          elsif ( $type eq "E" ) {
            $env{platform}{cloudstack} ||= 1;
            $pack{fleet}{$srv}{subsys}{LPAR}{$txt}{type} = "E";
          }
          elsif ( $type eq "M" ) {
            $env{platform}{proxmox} ||= 1;
            $pack{fleet}{$srv}{subsys}{LPAR}{$txt}{type} = "M";
          }
          elsif ( $type eq "I" ) {
            $env{platform}{docker} ||= 1;
            $pack{fleet}{$srv}{subsys}{LPAR}{$txt}{type} = "I";
          }
          elsif ( $type eq "W" ) {
            $env{platform}{fusioncompute} ||= 1;
            $pack{fleet}{$srv}{subsys}{LPAR}{$txt}{type} = "W";
          }
          elsif ( $type eq "H" ) {
            $env{platform}{hyperv} ||= 1;
            if ( $val[6] ) {
              $pack{hyperv}{cluster}{ $val[6] }{vm}{$txt} = $url;
            }
            else {
              $pack{hyperv}{dom}{$hmc}{server}{$srv}{vm}{$txt} = $url;
            }
          }
          elsif ( $type eq "Q" ) {
            $env{platform}{odb} ||= 1;
            $pack{fleet}{$srv}{subsys}{LPAR}{$txt}{type} = "Q";
          }
          elsif ( $type eq "D" ) {
            $env{platform}{sqlserver} ||= 1;
            $pack{fleet}{$srv}{subsys}{LPAR}{$txt}{type} = "D";
          }
          elsif ( $type eq "T" ) {
            $env{platform}{postgres} ||= 1;
            $pack{fleet}{$srv}{subsys}{LPAR}{$txt}{type} = "T";
          }
          elsif ( $type eq "F" ) {
            $env{platform}{db2} ||= 1;
            $pack{fleet}{$srv}{subsys}{LPAR}{$txt}{type} = "F";
          }
        }
        last;
      };

      #R:ahmc11:BSRV21:BSRV21LPAR5:BSRV21LPAR5:/lpar2rrd-cgi/detail.sh?host=ahmc11&server=BSRV21&lpar=BSRV21LPAR5&item=lpar&entitle=0&gui=1&none=none::
      "R" eq $val[0] && do {
        my ( $hmc, $srv, $atxt, $txt, $url, $valias, $type, $mset, $folder ) = ( $val[1], $val[2], $val[3], $val[4], $val[5], $val[7], $val[8], $val[9], $val[10] );
        if ( !$useacl || $isAdmin || $isReadonly ) {
          push @{ $pack{rtree}{$srv} }, [ $txt, $url, $atxt ];
          if ( !exists $pack{times}{$srv}{timestamp}{$hmc} ) {
            $pack{times}{$srv}{timestamp}{$hmc} = 999;
          }
          if ( $type eq "P" ) {
            $pack{fleet}{$srv}{subsys}{OUTDATED}{$txt}{type} = $mset;
          }

          # push @lnames, $txt;
        }
        last;
      };
      "RR" eq $val[0] && do {
        my ( $hmc, $srv, $atxt, $txt, $url, $valias, $type, $mset, $folder ) = ( $val[1], $val[2], $val[3], $val[4], $val[5], $val[7], $val[8], $val[9], $val[10] );
        if ( !$useacl || $isAdmin || $isReadonly ) {
          if ( $type eq "P" ) {
            $pack{fleet}{$srv}{subsys}{OUTDATED}{$txt}{type} = $mset;
          }

          # push @lnames, $txt;
        }
        last;
      };
      "W" eq $val[0] && do {
        my ( $hmc, $srv, $txt, $url, $wparparent, $mset ) = ( $val[1], $val[2], $val[4], $val[5], $val[6], $val[9] );
        if ( !$useacl || $isAdmin || $isReadonly ) {
          push @{ $pack{wtree}{$srv}{$wparparent} }, [ $txt => $url ];
          $pack{fleet}{$srv}{subsys}{WPAR}{ urldecode( $val[3] ) }{type} = $mset;
        }
        last;
      };
      "WLM" eq $val[0] && do {
        my ( $hmc, $srv, $txt, $url, $wparparent, $mset ) = ( $val[1], $val[2], $val[4], $val[5], $val[6], $val[9] );
        if ( !$useacl || $isAdmin || $isReadonly ) {
          push @{ $pack{wlmtree}{$srv}{$wparparent} }, [ $txt => $url ];
          $pack{fleet}{$srv}{subsys}{WLM}{ urldecode( $val[3] ) }{type} = $mset;
        }
        last;
      };
      "T" eq $val[0] && do {
        my ( $id, $txt, $url ) = ( $val[1], $val[2], $val[3] );

        #if ($txt ne "ACL" || $aclServAll) {
        push @{ $pack{tail} }, [ $txt, $url, $id ];

        #}
        last;
      };
      "V" eq $val[0] && do {
        my ( $vcenter, $txt, $url, $alias ) = ( $val[1], $val[2], $val[3], $val[6] );

        #if ($txt ne "ACL" || $aclServAll) {
        my $uuid = ( $url =~ /server=([^&]*)/ )[0];
        if ( $alias && !exists $pack{vtree}{vc}{$vcenter}{alias} ) {
          $pack{vtree}{vc}{$vcenter}{alias} = $alias;
          $pack{vtree}{alias}{$alias} = $vcenter;
        }
        if ( $uuid && !exists $pack{vtree}{vc}{$vcenter}{uuid} ) {
          $pack{vtree}{vc}{$vcenter}{uuid} = $uuid;
        }
        if ( !exists $pack{vtree}{vc}{$vcenter}{menu} ) {
          $pack{vtree}{vc}{$vcenter}{menu} = [];
        }
        push @{ $pack{vtree}{vc}{$vcenter}{menu} }, [ $txt, $url ];

        # $pack{vtree}{$vcenter}{menu}{$txt} = $url;

        #}
        last;
      };
      "A" eq $val[0] && do {    # VMware clusters
        my ( $vcenter, $cluster, $name, $url, $type ) = ( $val[1], $val[2], $val[3], $val[4], $val[8] );

        #if ($txt ne "ACL" || $aclServAll) {
        if ( $type eq "V" ) {
          $pack{cluster}{$vcenter}{$cluster}{$name} = $url;
        }
        elsif ( $type eq "H" ) {
          $pack{hyperv}{cluster}{ $val[2] }{totals}{ $val[3] } = $url;
        }

        #}
        last;
      };
      "B" eq $val[0] && do {
        my ( $vc, $cluster, $name, $url, $folder ) = ( $val[1], $val[2], $val[3], $val[4], $val[9] );

        #if ($txt ne "ACL" || $aclServAll) {
        if ( $name ne "Resources" ) {
          $pack{respool}{$vc}{$cluster}{$name} = $url;
        }
        else {
          $pack{respool}{$vc}{$name} = $url;
        }
        if ( !$pack{vtree}{vc}{$vc}{cluster}{$cluster}{respools} ) {
          $pack{vtree}{vc}{$vc}{cluster}{$cluster}{respools} = {};
        }
        my $hash_ref = $pack{vtree}{vc}{$vc}{cluster}{$cluster}->{respools};
        if ($folder) {
          $folder =~ s/\/$//;
          my @path = split( "/", $folder );
          if ( !$hash_ref->{folders} ) {
            $hash_ref->{folders} = {};
          }
          my $level;
          foreach $level (@path) {
            if ( !$hash_ref->{folders}{$level} ) {
              $hash_ref->{folders}{$level} = {};
              if ( $hash_ref->{items}{$level} ) {
                $hash_ref->{folders}{$level}{url} = $hash_ref->{items}{$level};
                delete $hash_ref->{items}{$level};
              }
            }
            $hash_ref = $hash_ref->{folders}{$level};
          }
        }
        if ( !$hash_ref->{items} ) {
          $hash_ref->{items} = {};
        }
        $hash_ref->{items}{$name} = $url;

        #}
        last;
      };
      "Z" eq $val[0] && do {    # VMware datastores
        my ( $vc, $dc, $name, $url, $folder ) = ( $val[1], $val[2], $val[3], $val[4], $val[9] );
        if ($vc) {
          $pack{datastore}{$vc}{$dc}{$name} = $url;
        }
        else {
          $vc = ( $url =~ /server=([^&]*)/ )[0];
          $pack{datastore}{$vc}{$dc}{$name} = $url;
        }
        if ( !$pack{vtree}{vc}{$vc}{datastores} ) {
          $pack{vtree}{vc}{$vc}{datastores} = {};
        }
        if ( !$pack{vtree}{vc}{$vc}{datastores}{$dc} ) {
          $pack{vtree}{vc}{$vc}{datastores}{$dc} = {};
        }
        my $hash_ref = $pack{vtree}{vc}{$vc}{datastores}->{$dc};
        if ($folder) {
          $folder =~ s/\/$//;
          my @path = split( "/", $folder );
          if ( !$hash_ref->{folders} ) {
            $hash_ref->{folders} = {};
          }
          my $level;
          foreach $level (@path) {
            if ( !$hash_ref->{folders}{$level} ) {
              $hash_ref->{folders}{$level} = {};
            }
            $hash_ref = $hash_ref->{folders}{$level};
          }
        }
        if ( !$hash_ref->{items} ) {
          $hash_ref->{items} = {};
        }
        $hash_ref->{items}{$name} = $url;
        last;
      };
      "Q" eq $val[0] && do {    # product version
        $env{version} = $version ? $version : $val[1];
        last;
      };
      "N" eq $val[0] && do {
        my ( $hmc, $srv, $atxt, $txt, $url, $valias, $type, $mset ) = ( $val[1], $val[2], $val[3], $val[4], $val[5], $val[7], $val[8], $val[9] );
        if ( $type eq "X" ) {
          $hmc = $atxt;
          $srv = $val[1];
        }
        if ( !$useacl || $isAdmin || $isReadonly ) {
          $atxt = urldecode($atxt);
          push @{ $pack{lantree}{$srv}{$hmc} }, [ $txt, $url, $atxt ];
        }
        last;
      };
      "Y" eq $val[0] && do {
        my ( $hmc, $srv, $atxt, $txt, $url, $valias, $type, $mset ) = ( $val[1], $val[2], $val[3], $val[4], $val[5], $val[7], $val[8], $val[9] );
        if ( $type eq "X" ) {
          $hmc = $atxt;
          $srv = $val[1];
        }
        if ( !$useacl || $isAdmin || $isReadonly ) {
          $atxt = urldecode($atxt);
          push @{ $pack{santree}{$srv}{$hmc} }, [ $txt, $url, $atxt ];
        }
        last;
      };
      "s" eq $val[0] && do {
        my ( $hmc, $srv, $atxt, $txt, $url, $valias, $type, $mset ) = ( $val[1], $val[2], $val[3], $val[4], $val[5], $val[7], $val[8], $val[9] );

        if ( !$useacl || $isAdmin || $isReadonly ) {
          $atxt = urldecode($atxt);
          push @{ $pack{sastree}{$srv}{$hmc} }, [ $txt, $url, $atxt ];
        }
        last;
      };
      "r" eq $val[0] && do {
        my ( $hmc, $srv, $atxt, $txt, $url, $valias, $type, $mset ) = ( $val[1], $val[2], $val[3], $val[4], $val[5], $val[7], $val[8], $val[9] );

        if ( !$useacl || $isAdmin || $isReadonly ) {
          $atxt = urldecode($atxt);
          push @{ $pack{sriovtree}{$srv}{$hmc} }, [ $txt, $url, $atxt ];
        }
        last;
      };
      "HEA" eq $val[0] && do {
        my ( $hmc, $srv, $atxt, $txt, $url, $valias, $type, $mset ) = ( $val[1], $val[2], $val[3], $val[4], $val[5], $val[7], $val[8], $val[9] );

        if ( !$useacl || $isAdmin || $isReadonly ) {
          $atxt = urldecode($atxt);
          push @{ $pack{heatree}{$srv}{$hmc} }, [ $txt, $url, $atxt ];
        }
        last;
      };
      "ST" eq $val[0] && do {
        my ( $hmc, $srv, $atxt, $txt, $url, $valias, $type, $mset ) = ( $val[1], $val[2], $val[3], $val[4], $val[5], $val[7], $val[8], $val[9] );
        $pack{xen}{pool}{$hmc}{total}{$txt}{url} = $url;
        last;
      };
      "NT" eq $val[0] && do {
        my ( $hmc, $srv, $atxt, $txt, $url, $valias, $type, $mset ) = ( $val[1], $val[2], $val[3], $val[4], $val[5], $val[7], $val[8], $val[9] );
        $pack{xen}{pool}{$hmc}{label}{$atxt}{lan}{txt} = $txt;
        $pack{xen}{pool}{$hmc}{label}{$atxt}{lan}{url} = $url;
        last;
      };
      "YT" eq $val[0] && do {
        my ( $hmc, $srv, $atxt, $txt, $url, $valias, $type, $mset ) = ( $val[1], $val[2], $val[3], $val[4], $val[5], $val[7], $val[8], $val[9] );
        $pack{xen}{pool}{$hmc}{label}{$atxt}{san}{txt} = $txt;
        $pack{xen}{pool}{$hmc}{label}{$atxt}{san}{url} = $url;
        last;
      };
      "HDT" eq $val[0] && do {
        my ( $hmc, $srv, $atxt, $txt, $url, $valias, $type, $mset ) = ( $val[1], $val[2], $val[3], $val[4], $val[5], $val[7], $val[8], $val[9] );
        $pack{hyperv}{dom}{$hmc}{server}{$srv}{drive}{total}{$txt} = $url;
        last;
      };
      "HDI" eq $val[0] && do {
        my ( $hmc, $srv, $atxt, $txt, $url, $valias, $type, $mset ) = ( $val[1], $val[2], $val[3], $val[4], $val[5], $val[7], $val[8], $val[9] );
        $pack{hyperv}{dom}{$hmc}{server}{$srv}{drive}{item}{$txt} = $url;
        last;
      };
      "HPD" eq $val[0] && do {
        my ( $hmc, $srv, $atxt, $txt, $url, $valias, $type, $mset ) = ( $val[1], $val[2], $val[3], $val[4], $val[5], $val[7], $val[8], $val[9] );
        if ( $val[6] ) {
          $pack{hyperv}{cluster}{ $val[6] }{pd}{$txt} = $url;
        }
        last;
      };
      "HVOL" eq $val[0] && do {
        my ( $hmc, $srv, $atxt, $txt, $url, $valias, $type, $mset ) = ( $val[1], $val[2], $val[3], $val[4], $val[5], $val[7], $val[8], $val[9] );
        if ( $val[6] ) {
          $pack{hyperv}{cluster}{ $val[6] }{vol}{$txt} = $url;
        }
        last;
      };
    };
  }

  includeMenu( "menu_nutanix",       "nutanix" );
  includeMenu( "menu_proxmox",       "proxmox" );
  includeMenu( "menu_fusioncompute", "fusioncompute" );
  includeMenu( "menu_ovirt",         "ovirt" );
  includeMenu( "menu_xenserver",     "xen" );
  includeMenu( "menu_oraclevm",      "orvm" );

  includeMenu( "menu_aws",        "aws" );
  includeMenu( "menu_azure",      "azure" );
  includeMenu( "menu_gcloud",     "gcloud" );
  includeMenu( "menu_cloudstack", "cloudstack" );

  includeMenu( "menu_kubernetes", "kubernetes" );
  includeMenu( "menu_openshift",  "openshift" );
  includeMenu( "menu_docker",     "docker" );

  includeMenu( "menu_oracledb",  "odb" );
  includeMenu( "menu_postgres",  "postgres" );
  includeMenu( "menu_sqlserver", "sqlserver" );
  includeMenu( "menu_db2",       "db2" );
  includeMenu( "menu_powercmc",  "cmc" );

  # for debugging only - simulate no Power / VMware menu
  # $env{platform}{power} = 0;
  # $env{platform}{vmware} = 0;
  # $env{cached} = 0;
}

sub includeMenu {
  my $inc_json_name = shift;
  my $hash_key_name = shift;
  my $inc_menu_file = -r "$basedir/debug/$inc_json_name.json" ? "$basedir/debug/$inc_json_name.json" : "$basedir/tmp/$inc_json_name.json";
  if ( -e $inc_menu_file && -f _ && -r _ ) {
    my ( $code, $incmenu ) = Xorux_lib::read_json($inc_menu_file);
    if ($code) {
      $env{platform}{$hash_key_name} = 1;
      $pack{$hash_key_name} = $incmenu;
    }
  }
}

### Generate SERVERs submenu (no HMC parents)
sub genServers {
  for my $srv ( sort keys %{ $pack{times} } ) {
    if ( $pack{times}{$srv}{"active"}
      && $pack{times}{$srv}{type}
      && $pack{times}{$srv}{type} eq "P"
      && ( !$useacl || $isAdmin || $isReadonly || $acl->hasItems( "P", $srv, keys %{ $pack{lpartree}{$srv} } ) || $acl->hasItems( "O", $srv ) )
      && !( exists $pack{times}{$srv}{timestamp}{no_hmc} && ( scalar keys %{ $pack{times}{$srv}{timestamp} } == 1 ) ) )
    {
      $idx{csrv} = push @{ $menu[ $idx{psrv} ]{children} }, { "title" => "$srv", "folder" => "true", "children" => [] };
      $idx{csrv}--;

      my ($hmc) = sort { $pack{times}{$srv}{timestamp}{$b} <=> $pack{times}{$srv}{timestamp}{$a} } keys %{ $pack{times}{$srv}{timestamp} };

      # my ($hmc) = keys %{ $pack{stree}{$srv} };
      if ( exists $pack{stree}{$srv}->{$hmc} && ( !$useacl || $isAdmin || $acl->canShow( "POWER", "SERVER", $srv ) || $acl->hasItems( "O", $srv ) ) ) {
        &serverMenu( $hmc, $srv );
      }
      if ( exists $pack{lpartree}{$srv} && $acl->hasItems( "P", $srv ) ) {
        $idx{lpars} = push @{ $menu[ $idx{psrv} ]{children}[ $idx{csrv} ]{children} }, { "title" => "LPAR", "folder" => "true", "children" => [] };
        $idx{lpars}--;
        for my $lpar ( nsort keys %{ $pack{lpartree}{$srv} } ) {
          if ( exists $pack{wtree}{$srv}{$lpar} && exists $pack{wlmtree}{$srv}{$lpar} ) {
            $idx{lparchld} = push @{ $menu[ $idx{psrv} ]{children}[ $idx{csrv} ]{children}[ $idx{lpars} ]{children} }, pushFullNodewChild( $pack{lpartree}{$srv}{$lpar}{alt}, $pack{lpartree}{$srv}{$lpar}{url}, $hmc, $srv, 1, $lpar, $pack{hmc}{$hmc}{type}, undef, "L" );
            $idx{lparchld}--;
            $idx{wpars} = push @{ $menu[ $idx{psrv} ]{children}[ $idx{csrv} ]{children}[ $idx{lpars} ]{children}[ $idx{lparchld} ]{children} }, { "title" => "WPAR", "folder" => "true", "children" => [] };
            $idx{wpars}--;
            for my $wpar ( sort @{ $pack{wtree}{$srv}{$lpar} } ) {
              push @{ $menu[ $idx{psrv} ]{children}[ $idx{csrv} ]{children}[ $idx{lpars} ]{children}[ $idx{lparchld} ]{children}[ $idx{wpars} ]{children} }, pushFullNode( @$wpar[0], @$wpar[1], $hmc, $srv, 1, $lpar . "/" . @$wpar[0], undef, undef, "W" );
            }
            $idx{wlm} = push @{ $menu[ $idx{psrv} ]{children}[ $idx{csrv} ]{children}[ $idx{lpars} ]{children}[ $idx{lparchld} ]{children} }, { "title" => "WLM", "folder" => "true", "children" => [] };
            $idx{wlm}--;
            for my $wpar ( sort @{ $pack{wlmtree}{$srv}{$lpar} } ) {
              push @{ $menu[ $idx{psrv} ]{children}[ $idx{csrv} ]{children}[ $idx{lpars} ]{children}[ $idx{lparchld} ]{children}[ $idx{wlm} ]{children} }, pushFullNode( @$wpar[0], @$wpar[1], $hmc, $srv, 1, $lpar . "/" . @$wpar[0], undef, undef, "W" );
            }
          }
          elsif ( exists $pack{wtree}{$srv}{$lpar} ) {
            $idx{wpars} = push @{ $menu[ $idx{psrv} ]{children}[ $idx{csrv} ]{children}[ $idx{lpars} ]{children} }, pushFullNodewChild( $pack{lpartree}{$srv}{$lpar}{alt}, $pack{lpartree}{$srv}{$lpar}{url}, $hmc, $srv, 1, $lpar, $pack{hmc}{$hmc}{type}, undef, "L" );
            $idx{wpars}--;
            for my $wpar ( sort @{ $pack{wtree}{$srv}{$lpar} } ) {
              push @{ $menu[ $idx{psrv} ]{children}[ $idx{csrv} ]{children}[ $idx{lpars} ]{children}[ $idx{wpars} ]{children} }, pushFullNode( @$wpar[0], @$wpar[1], $hmc, $srv, 1, $lpar . "/" . @$wpar[0], undef, undef, "W" );
            }
          }
          elsif ( exists $pack{wlmtree}{$srv}{$lpar} ) {
            $idx{wlm} = push @{ $menu[ $idx{psrv} ]{children}[ $idx{csrv} ]{children}[ $idx{lpars} ]{children} }, pushFullNodewChild( $pack{lpartree}{$srv}{$lpar}{alt}, $pack{lpartree}{$srv}{$lpar}{url}, $hmc, $srv, 1, $lpar, $pack{hmc}{$hmc}{type}, undef, "L" );
            $idx{wlm}--;
            for my $wpar ( sort @{ $pack{wlmtree}{$srv}{$lpar} } ) {
              push @{ $menu[ $idx{psrv} ]{children}[ $idx{csrv} ]{children}[ $idx{lpars} ]{children}[ $idx{wlm} ]{children} }, pushFullNode( @$wpar[0], @$wpar[1], $hmc, $srv, 1, $lpar . "/" . @$wpar[0], undef, undef, "W" );
            }
          }
          else {
            push @{ $menu[ $idx{psrv} ]{children}[ $idx{csrv} ]{children}[ $idx{lpars} ]{children} }, pushFullNode( $pack{lpartree}{$srv}{$lpar}{alt}, $pack{lpartree}{$srv}{$lpar}{url}, $hmc, $srv, 1, $lpar, $pack{hmc}{$hmc}{type}, undef, "L" );
          }
        }    # L3 END
        if ( exists $pack{rtree}{$srv} ) {
          $idx{removed} = push @{ $menu[ $idx{psrv} ]{children}[ $idx{csrv} ]{children}[ $idx{lpars} ]{children} }, { "title" => "Removed", "folder" => "true", "children" => [] };
          $idx{removed}--;
          for my $removed ( sort @{ $pack{rtree}{$srv} } ) {
            push @{ $menu[ $idx{psrv} ]{children}[ $idx{csrv} ]{children}[ $idx{lpars} ]{children}[ $idx{removed} ]{children} }, pushFullNode( @$removed[0], @$removed[1], $hmc, $srv, 1, undef, undef, undef, "R" );
          }
        }
      }
      my $ref = $menu[ $idx{psrv} ]{children}[ $idx{csrv} ]{children};
      if ( exists $pack{lantree}{$srv}{$hmc} ) {
        sub_tree_ref( $srv, $hmc, "lan", $ref, "LAN", "N" );
      }
      if ( exists $pack{santree}{$srv}{$hmc} ) {
        sub_tree_ref( $srv, $hmc, "san", $ref, "SAN", "Y" );
      }
      if ( exists $pack{sastree}{$srv}{$hmc} ) {
        sub_tree_ref( $srv, $hmc, "sas", $ref, "SAS", "s" );
      }
      if ( exists $pack{sriovtree}{$srv}{$hmc} ) {
        sub_tree_ref( $srv, $hmc, "sriov", $ref, "SR-IOV", "r" );
      }
      if ( exists $pack{heatree}{$srv}{$hmc} ) {
        sub_tree_ref( $srv, $hmc, "hea", $ref, "HEA", "HEA" );
      }
    }
  }
  if ( $env{platform}{unmanaged} && scalar keys %{ $env{platform} } == 1 ) {
    &genStandalone(0);    # List by Servers
  }
}

### Generate standalone SERVERs submenu
sub genStandalone {
  my $toplevel = shift;
  if ($toplevel) {
    $idx{solo} = push @menu, { title => "Unmanaged", folder => "true", children => [] };
    $idx{solo}--;
  }
  else {
    $idx{solo} = $idx{psrv};
  }

  # for my $srv ( sort keys $pack{lstree} ) {
  for my $srv ( sort keys %{ $pack{times} } ) {
    if ( $pack{times}{$srv}{"active"}
      && exists $pack{times}{$srv}{timestamp}{no_hmc}
      && ( !$pack{times}{$srv}{type} || $pack{times}{$srv}{type} ne "S" )
      && scalar keys %{ $pack{times}{$srv}{timestamp} } == 1
      && ( !$useacl || $isAdmin || $isReadonly || $acl->hasItems( "U", $srv ) ) )
    {
      $idx{csrv} = push @{ $menu[ $idx{solo} ]{children} }, { title => $srv, folder => "true", children => [] };
      $idx{csrv}--;
      my $hmc = "no_hmc";
      if ( exists $pack{lstree}{$srv}->{$hmc} ) {
        for my $lpar ( sort { "\L$a->[0]" cmp "\L$b->[0]" } @{ $pack{lstree}{$srv}->{$hmc} } ) {
          if ( !$useacl || $isAdmin || $isReadonly || $acl->canShow( "UNMANAGED", "VM", $srv, @$lpar[0] ) ) {
            push @{ $menu[ $idx{solo} ]{children}[ $idx{csrv} ]{children} }, pushFullNode( @$lpar[0], @$lpar[1], $hmc, $srv, 1, @$lpar[2], $pack{hmc}{$hmc}{type}, undef, "U" );
          }
        }    # L3 END
      }
    }
  }
}

sub genLinux {
  my $toplevel = shift;
  if ($toplevel) {
    $idx{linux} = push @menu, { title => "Linux", folder => "true", children => [] };
    $idx{linux}--;
  }
  else {
    $idx{linux} = $idx{psrv};
  }

  # for my $srv ( sort keys $pack{lstree} ) {
  my $hmc = "no_hmc";
  push @{ $menu[ $idx{linux} ]{children} }, pushFullNode( "Historical reports", "/lpar2rrd-cgi/histrep.sh?mode=linux", "histrep-linux", "Linux", 1, "", "L", undef, "L", "boldmenu" );
  for my $srv ( sort { "\L$a->[0]" cmp "\L$b->[0]" } @{ $pack{lhmc}{no_hmc}{Linux} } ) {
    if ( !$useacl || $isAdmin || $isReadonly || $acl->canShow( "LINUX", "SERVER", "", @$srv[0] ) ) {
      push @{ $menu[ $idx{linux} ]{children} }, pushFullNode( @$srv[0], @$srv[1], $hmc, "Linux", 1, @$srv[2], $pack{hmc}{$hmc}{type}, undef, "X" );
    }
  }
}

### Generate Solaris submenu
sub genSolaris {
  my $toplevel = shift;
  if ($toplevel) {
    $idx{solaris} = push @menu, { title => "Solaris", folder => "true", children => [] };
    $idx{solaris}--;
    if ( $pack{soltree}{totals} ) {
      push @{ $menu[ $idx{solaris} ]{children} }, pushFullNode( "Totals", "/lpar2rrd-cgi/detail.sh?host=no_hmc&server=Solaris&lpar=cod&item=cpuagg-sol&entitle=0&gui=1&none=none", "cpuagg-sol", "Solaris", 1, "", "S", undef, "S" );
    }
    push @{ $menu[ $idx{solaris} ]{children} }, pushFullNode( "Historical reports", "/lpar2rrd-cgi/histrep.sh?mode=solaris", "histrep-solaris", "Solaris", 1, "", "S", undef, "S" );
  }
  else {
    $idx{solaris} = $idx{psrv};
  }

  # for my $srv ( sort keys $pack{lstree} ) {
  for my $srv ( sort keys %{ $pack{soltree}{host} } ) {
    if ( $pack{soltree}{host}{$srv}{parent} ) {
      next;
    }
    $idx{csrv} = push @{ $menu[ $idx{solaris} ]{children} }, { title => $srv, folder => "true", children => [] };
    $idx{csrv}--;
    if ( exists $pack{soltree}{host}{$srv}{ldom}{Totals} ) {
      push @{ $menu[ $idx{solaris} ]{children}[ $idx{csrv} ]{children} }, pushFullNode( "Totals", $pack{soltree}{host}{$srv}{ldom}{Totals}{url}, "Totals", $srv, 1, "", "S", undef, "S" );
    }
    if ( exists $pack{soltree}{host}{$srv}{globzone}{Totals} ) {
      push @{ $menu[ $idx{solaris} ]{children}[ $idx{csrv} ]{children} }, pushFullNode( "Totals", $pack{soltree}{host}{$srv}{globzone}{Totals}{url}, "Totals", $srv, 1, "", "S", undef, "S" );
    }
    if ( exists $pack{soltree}{host}{$srv}{children} ) {
      for my $child ( sort keys %{ $pack{soltree}{host}{$srv}{children} } ) {
        $idx{child} = push @{ $menu[ $idx{solaris} ]{children}[ $idx{csrv} ]{children} }, { title => $child, folder => "true", children => [] };
        $idx{child}--;
        if ( exists $pack{soltree}{host}{$child}{ldom}{Totals} ) {
          push @{ $menu[ $idx{solaris} ]{children}[ $idx{csrv} ]{children}[ $idx{child} ]{children} }, pushFullNode( "Totals", $pack{soltree}{host}{$child}{ldom}{Totals}{url}, "Totals", $child, 1, "", "S", undef, "S" );
        }
        if ( exists $pack{soltree}{host}{$child}{globzone}{Totals} ) {
          push @{ $menu[ $idx{solaris} ]{children}[ $idx{csrv} ]{children}[ $idx{child} ]{children} }, pushFullNode( "Totals", $pack{soltree}{host}{$child}{globzone}{Totals}{url}, "Totals", $child, 1, "", "S", undef, "S" );
        }
        if ( exists $pack{soltree}{host}{$child}{zone} ) {
          $idx{lpars} = push @{ $menu[ $idx{solaris} ]{children}[ $idx{csrv} ]{children}[ $idx{child} ]{children} }, { "title" => "ZONE", "folder" => "true", "children" => [] };
          $idx{lpars}--;
          for my $lpar ( @{ $pack{lstree}{$child}{no_hmc} } ) {
            push @{ $menu[ $idx{solaris} ]{children}[ $idx{csrv} ]{children}[ $idx{child} ]{children}[ $idx{lpars} ]{children} }, pushFullNode( @$lpar[0], @$lpar[1], "Solaris", $child, 1, @$lpar[2], "S", undef, "S" );
          }    # L3 END
        }
      }
    }
    if ( exists $pack{soltree}{host}{$srv}{zone} ) {
      $idx{lpars} = push @{ $menu[ $idx{solaris} ]{children}[ $idx{csrv} ]{children} }, { "title" => "ZONE", "folder" => "true", "children" => [] };
      $idx{lpars}--;
      for my $lpar ( @{ $pack{lstree}{$srv}{no_hmc} } ) {
        push @{ $menu[ $idx{solaris} ]{children}[ $idx{csrv} ]{children}[ $idx{lpars} ]{children} }, pushFullNode( @$lpar[0], @$lpar[1], "Solaris", $srv, 1, @$lpar[2], "S", undef, "S" );
      }    # L3 END
    }
  }
}

sub genSolarisHistrepLdom {

  # for my $srv ( sort keys $pack{lstree} ) {
  my @menu;
  my %idx;
  for my $srv ( sort keys %{ $pack{soltree}{host} } ) {
    if ( $pack{soltree}{host}{$srv}{parent} ) {
      next;
    }
    my $key = "Solaris--unknown|$srv";
    $idx{csrv} = push @menu, { title => $srv, folder => "true", children => [], key => $key };
    $idx{csrv}--;
    if ( exists $pack{soltree}{host}{$srv}{children} ) {
      for my $child ( sort keys %{ $pack{soltree}{host}{$srv}{children} } ) {
        $key = "Solaris--unknown|$srv|$child";
        push @{ $menu[ $idx{csrv} ]{children} }, { title => $child, key => $key };
      }
    }
  }
  print JSON->new->utf8(1)->encode( \@menu );
}

sub genHypervHistrepVMs {

  # for my $srv ( sort keys $pack{lstree} ) {
  my @menu;
  my %idx;
  for my $dom ( nsort keys %{ $pack{hyperv}{dom} } ) {
    my $has_vm = 0;
    my $key    = "hyperv-domain|$dom";
    if ( exists $pack{hyperv}{dom}{$dom}{server} ) {
      $idx{dom} = push @menu, { title => $dom, folder => "true", children => [] };
      $idx{dom}--;
      for my $srv ( nsort keys %{ $pack{hyperv}{dom}{$dom}{server} } ) {
        $idx{srv} = push @{ $menu[ $idx{dom} ]{children} }, { title => $srv };
        $idx{srv}--;
        if ( exists $pack{hyperv}{dom}{$dom}{server}{$srv}{vm} ) {
          $has_vm ||= 1;
          $menu[ $idx{dom} ]{children}[ $idx{srv} ]{folder}   = "true";
          $menu[ $idx{dom} ]{children}[ $idx{srv} ]{children} = [];
          for my $vm ( nsort keys %{ $pack{hyperv}{dom}{$dom}{server}{$srv}{vm} } ) {
            my $url = $pack{hyperv}{dom}{$dom}{server}{$srv}{vm}{$vm};
            my $id  = ( $url =~ /lpar=([^&]*)/ )[0];
            my $key = "hyperv-vm|$id";
            push @{ $menu[ $idx{dom} ]{children}[ $idx{srv} ]{children} }, { title => $vm, key => $key };
          }
        }
      }
    }
    if ( !$has_vm ) {
      pop @menu;
    }
  }
  for my $cluster ( nsort keys %{ $pack{hyperv}{cluster} } ) {
    my $key = "hyperv-cluster|$cluster";
    if ( exists $pack{hyperv}{cluster}{$cluster}{vm} ) {
      $idx{cluster} = push @menu, { title => $cluster, folder => "true", children => [] };
      $idx{cluster}--;
      for my $vm ( nsort keys %{ $pack{hyperv}{cluster}{$cluster}{vm} } ) {
        my $url = $pack{hyperv}{cluster}{$cluster}{vm}{$vm};
        my $id  = ( $url =~ /lpar=([^&]*)/ )[0];
        my $key = "hyperv-vm|$id";
        push @{ $menu[ $idx{cluster} ]{children} }, { title => $vm, key => $key };
      }
    }
  }
  print JSON->new->utf8(1)->encode( \@menu );
}

sub genHypervHistrepServer {

  # for my $srv ( sort keys $pack{lstree} ) {
  my @menu;
  my %idx;
  for my $dom ( nsort keys %{ $pack{hyperv}{dom} } ) {
    my $key = "hyperv-domain|$dom";
    if ( exists $pack{hyperv}{dom}{$dom}{server} ) {
      $idx{dom} = push @menu, { title => $dom, folder => "true", children => [] };
      $idx{dom}--;
      for my $srv ( nsort keys %{ $pack{hyperv}{dom}{$dom}{server} } ) {
        $key = "hyperv-server|$srv";
        push @{ $menu[ $idx{dom} ]{children} }, { title => $srv, key => $key };
      }
    }
  }
  print JSON->new->utf8(1)->encode( \@menu );
}

sub genOraclevmHistrepVMs {
  my $metadata_file   = "$inputdir/data/OracleVM/conf.json";
  if ( -f $metadata_file ) {
    my ( $code, $ref ) = Xorux_lib::read_json($metadata_file);
    if ($code) {
      #print JSON->new->utf8(1)->encode( $ref );
      #return;
      my @menu;
      my %idx;
      while ( my ( $pool_uuid, $pool_label ) = each %{ $ref->{labels}{server_pool} } ) {
        my $key = "oraclevm-pool|$pool_label";
        if ( exists $ref->{architecture}{server_pool}{$pool_uuid}{vm} ) {
          $idx{pool} = push @menu, { title => $pool_label, folder => "true", children => [] };
          $idx{pool}--;
          for my $vm ( @{ $ref->{architecture}{server_pool}{$pool_uuid}{vm} } ) {
            my $label = $ref->{labels}{vm}{$vm};
            $key = "oraclevm-vm|$vm";
            push @{ $menu[ $idx{pool} ]{children} }, { title => $label, key => $key };
          }
        }
      }
       print JSON->new->utf8(1)->encode( \@menu );
    }
    else {
      print "[]";
    }
  }
  else {
    print "[]";
  }

}

sub genOraclevmHistrepServer {
  my $metadata_file   = "$inputdir/data/OracleVM/conf.json";
  if ( -f $metadata_file ) {
    my ( $code, $ref ) = Xorux_lib::read_json($metadata_file);
    if ($code) {
      #print JSON->new->utf8(1)->encode( $ref );
      #return;
      my @menu;
      my %idx;
      while ( my ( $pool_uuid, $pool_label ) = each %{ $ref->{labels}{server_pool} } ) {
        my $key = "oraclevm-pool|$pool_label";
        if ( exists $ref->{architecture}{server_pool}{$pool_uuid}{server} ) {
          $idx{pool} = push @menu, { title => $pool_label, folder => "true", children => [] };
          $idx{pool}--;
          for my $srv ( @{ $ref->{architecture}{server_pool}{$pool_uuid}{server} } ) {
            my $label = $ref->{labels}{server}{$srv};
            $key = "oraclevm-server|$srv";
            push @{ $menu[ $idx{pool} ]{children} }, { title => $label, key => $key };
          }
        }
      }
       print JSON->new->utf8(1)->encode( \@menu );
    }
    else {
      print "[]";
    }
  }
  else {
    print "[]";
  }
}

### Generate Hitachi Blade submenu
sub genHitachi {
  my $toplevel = shift;
  if ($toplevel) {
    $idx{hitachi} = push @menu, { title => "Hitachi", folder => "true", children => [] };
    $idx{hitachi}--;
  }
  else {
    $idx{hitachi} = $idx{psrv};
  }

  # for my $srv ( sort keys $pack{lstree} ) {
  for my $srv ( sort keys %{ $pack{times} } ) {
    if ( $pack{times}{$srv}{"active"}
      && $pack{times}{$srv}{type}
      && $pack{times}{$srv}{type} eq "B" )
    {
      $idx{csrv} = push @{ $menu[ $idx{hitachi} ]{children} }, { title => $srv, folder => "true", children => [] };
      $idx{csrv}--;
      my $hmc = "Hitachi";

      # if ( exists $pack{stree}{$srv}->{$hmc} && ( !$useacl || $aclServAll || $acl->canShow("P", "", $srv, "") ) ) {
      &serverMenu( "Hitachi", $srv );

      # }
      if ( exists $pack{lstree}{$srv}->{$hmc} ) {
        $idx{lpars} = push @{ $menu[ $idx{hitachi} ]{children}[ $idx{csrv} ]{children} }, { "title" => "LPAR", "folder" => "true", "children" => [] };
        $idx{lpars}--;
        for my $lpar ( sort { "\L$a->[0]" cmp "\L$b->[0]" } @{ $pack{lstree}{$srv}->{$hmc} } ) {
          push @{ $menu[ $idx{hitachi} ]{children}[ $idx{csrv} ]{children}[ $idx{lpars} ]{children} }, pushFullNode( @$lpar[0], @$lpar[1], $hmc, $srv, 1, @$lpar[2], $pack{hmc}{$hmc}{type}, undef, "B" );
        }    # L3 END
      }
      my $ref = $menu[ $idx{hitachi} ]{children}[ $idx{csrv} ]{children};
      if ( exists $pack{lantree}{$srv}{$hmc} ) {
        sub_tree_ref( $srv, $hmc, "lan", $ref, "LAN", "N" );
      }
      if ( exists $pack{santree}{$srv}{$hmc} ) {
        sub_tree_ref( $srv, $hmc, "san", $ref, "SAN", "Y" );
      }
      if ( exists $pack{sastree}{$srv}{$hmc} ) {
        sub_tree_ref( $srv, $hmc, "sas", $ref, "SAS", "s" );
      }
      if ( exists $pack{sriovtree}{$srv}{$hmc} ) {
        sub_tree_ref( $srv, $hmc, "sriov", $ref, "SR-IOV", "r" );
      }
    }
  }
}

sub sub_tree_ref {
  my ( $srv, $hmc, $subsys, $node, $title, $obj ) = @_;
  $idx{$subsys} = push @{$node}, { "title" => $title, "folder" => "true", "children" => [] };
  $idx{$subsys}--;
  $idx{ $subsys . "totals" } = push @{ $$node[ $idx{$subsys} ]{children} }, { "title" => "Totals" };
  $idx{ $subsys . "totals" }--;
  $idx{ $subsys . "items" } = push @{ $$node[ $idx{$subsys} ]{children} }, { "title" => "Items", "folder" => "true", "children" => [] };
  $idx{ $subsys . "items" }--;
  for my $lpar ( sort { "\L$a->[0]" cmp "\L$b->[0]" } @{ $pack{ $subsys . "tree" }{$srv}->{$hmc} } ) {
    if ( @$lpar[0] eq "$subsys-totals" ) {
      @{ $$node[ $idx{$subsys} ]{children} }[ $idx{ $subsys . "totals" } ] = pushFullNode( "Totals", @$lpar[1], $hmc, $srv, 1, @$lpar[0], $pack{hmc}{$hmc}{type}, undef, $obj );
    }
    else {
      push @{ $$node[ $idx{$subsys} ]{children}[ $idx{ $subsys . "items" } ]{children} }, pushFullNode( @$lpar[0], @$lpar[1], $hmc, $srv, 1, @$lpar[2], $pack{hmc}{$hmc}{type}, undef, $obj );
    }
  }
}

sub genHyperV {
  my $toplevel = shift;
  if ($toplevel) {
    $idx{hyperv} = push @menu, { title => "Windows / Hyper-V", folder => "true", children => [] };
    $idx{hyperv}--;
  }
  else {
    $idx{hyperv} = $idx{psrv};
  }
  push @{ $menu[ $idx{hyperv} ]{children} }, { title => "Heatmap", href => "heatmap-windows.html", key => "heatmaphv" };

  # HyperV Top VM:
  push @{ $menu[ $idx{hyperv} ]{children} }, { title => "VM TOP",             href => "/lpar2rrd-cgi/detail.sh?host=&server=&lpar=cod&item=topten_hyperv&entitle=0", key => "topten_hv" };
  push @{ $menu[ $idx{hyperv} ]{children} }, { title => "Historical reports", href => "/lpar2rrd-cgi/histrep.sh?mode=hyperv",                                        key => "histrep-hyperv" };

  for my $dom ( sort keys %{ $pack{hyperv}{dom} } ) {
    $idx{dom} = push @{ $menu[ $idx{hyperv} ]{children} }, { title => $dom, folder => "true", children => [] };
    $idx{dom}--;
    for my $srv ( sort keys %{ $pack{hyperv}{dom}{$dom}{server} } ) {
      $idx{hsrv} = push @{ $menu[ $idx{hyperv} ]{children}[ $idx{dom} ]{children} }, { title => $srv, folder => "true", children => [] };
      $idx{hsrv}--;

      # if ( exists $pack{stree}{$srv}->{$hmc} && ( !$useacl || $aclServAll || $acl->canShow("P", "", $srv, "") ) ) {
      foreach my $total ( 'Totals', 'CPU', 'Memory', 'Disk', 'Net' ) {
        if ( exists $pack{hyperv}{dom}{$dom}{server}{$srv}{totals}{$total} ) {
          push @{ $menu[ $idx{hyperv} ]{children}[ $idx{dom} ]{children}[ $idx{hsrv} ]{children} }, pushFullNode( $total, $pack{hyperv}{dom}{$dom}{server}{$srv}{totals}{$total}, $dom, $srv, 0 );
        }
      }

      # }
      if ( exists $pack{hyperv}{dom}{$dom}{server}{$srv}{vm} ) {
        $idx{lpars} = push @{ $menu[ $idx{hyperv} ]{children}[ $idx{dom} ]{children}[ $idx{hsrv} ]{children} }, { "title" => "VM", "folder" => "true", "children" => [] };
        $idx{lpars}--;
        for my $lpar ( sort keys %{ $pack{hyperv}{dom}{$dom}{server}{$srv}{vm} } ) {
          push @{ $menu[ $idx{hyperv} ]{children}[ $idx{dom} ]{children}[ $idx{hsrv} ]{children}[ $idx{lpars} ]{children} }, pushFullNode( $lpar, $pack{hyperv}{dom}{$dom}{server}{$srv}{vm}{$lpar}, $dom, $srv, 1, "", "H", undef, "H" );
        }
      }
      if ( exists $pack{hyperv}{dom}{$dom}{server}{$srv}{drive} ) {
        $idx{drive} = push @{ $menu[ $idx{hyperv} ]{children}[ $idx{dom} ]{children}[ $idx{hsrv} ]{children} }, { "title" => "Storage", "folder" => "true", "children" => [] };
        $idx{drive}--;
        for my $lpar ( sort keys %{ $pack{hyperv}{dom}{$dom}{server}{$srv}{drive}{item} } ) {
          push @{ $menu[ $idx{hyperv} ]{children}[ $idx{dom} ]{children}[ $idx{hsrv} ]{children}[ $idx{drive} ]{children} }, pushFullNode( $lpar, $pack{hyperv}{dom}{$dom}{server}{$srv}{drive}{item}{$lpar}, $dom, $srv, 1, "", "H", undef, "H" );
        }
      }
    }
  }
  for my $clstr ( sort keys %{ $pack{hyperv}{cluster} } ) {
    $idx{hclstr} = push @{ $menu[ $idx{hyperv} ]{children} }, { title => "Cluster: $clstr", folder => "true", children => [] };
    $idx{hclstr}--;
    for my $ctot ( keys %{ $pack{hyperv}{cluster}{$clstr}{totals} } ) {
      push @{ $menu[ $idx{hyperv} ]{children}[ $idx{hclstr} ]{children} }, pushFullNode( $ctot, $pack{hyperv}{cluster}{$clstr}{totals}{$ctot}, "", $clstr, 0 );
    }
    if ( exists $pack{hyperv}{cluster}{$clstr}{vm} ) {
      $idx{lpars} = push @{ $menu[ $idx{hyperv} ]{children}[ $idx{hclstr} ]{children} }, { "title" => "VM", "folder" => "true", "children" => [] };
      $idx{lpars}--;
      for my $lpar ( sort keys %{ $pack{hyperv}{cluster}{$clstr}{vm} } ) {
        push @{ $menu[ $idx{hyperv} ]{children}[ $idx{hclstr} ]{children}[ $idx{lpars} ]{children} }, pushFullNode( $lpar, $pack{hyperv}{cluster}{$clstr}{vm}{$lpar}, "cluster", $clstr, 1, "", "H", undef, "H" );
      }
    }
    if ( exists $pack{hyperv}{cluster}{$clstr}{vol} ) {
      $idx{lpars} = push @{ $menu[ $idx{hyperv} ]{children}[ $idx{hclstr} ]{children} }, { "title" => "VOLUME", "folder" => "true", "children" => [] };
      $idx{lpars}--;
      for my $lpar ( sort keys %{ $pack{hyperv}{cluster}{$clstr}{vol} } ) {
        push @{ $menu[ $idx{hyperv} ]{children}[ $idx{hclstr} ]{children}[ $idx{lpars} ]{children} }, pushFullNode( $lpar, $pack{hyperv}{cluster}{$clstr}{vol}{$lpar}, "cluster", $clstr, 1, "", "H", undef, "H" );
      }
    }
    if ( exists $pack{hyperv}{cluster}{$clstr}{pd} ) {
      $idx{lpars} = push @{ $menu[ $idx{hyperv} ]{children}[ $idx{hclstr} ]{children} }, { "title" => "DRIVES", "folder" => "true", "children" => [] };
      $idx{lpars}--;
      for my $lpar ( sort keys %{ $pack{hyperv}{cluster}{$clstr}{pd} } ) {
        push @{ $menu[ $idx{hyperv} ]{children}[ $idx{hclstr} ]{children}[ $idx{lpars} ]{children} }, pushFullNode( $lpar, $pack{hyperv}{cluster}{$clstr}{pd}{$lpar}, "cluster", $clstr, 1, "", "H", undef, "H" );
      }
    }
  }
}

sub genVMware {
  if ( !$env{platform}{vmware} ) {
    return;
  }
  if ( $pack{vtree} ) {
    for my $vc ( sort keys %{ $pack{vtree}{vc} } ) {
      if ( $vc eq "" ) {
        next;
      }
      my $vcAlias = $pack{vtree}{vc}{$vc}{alias} ||= $vc;
      $idx{vc} = push @{ $menu[ $idx{vmware} ]{children} }, { "title" => "$vcAlias", "altname" => $vc, "uuid" => $pack{vtree}{vc}{$vc}{uuid}, "folder" => "true", "children" => [] };
      $idx{vc}--;
      my $delim = "";

      if ( !$useacl || $isAdmin || $isReadonly || $sections{vmware} ) {
        $delim = vcTotals($vc);
      }
      if ( exists $pack{respool}{$vc}{Resources} ) {
        push @{ $menu[ $idx{vmware} ]{children}[ $idx{vc} ]{children} }, pushFullNode( "Unregistered VMs", $pack{respool}{$vc}{Resources}, $vc, $vc, 1 );
      }
      if ( exists $pack{cluster}{$vc} ) {

        # print "{\"title\":\"Cluster\",\"folder\":\"true\",\"children\":[\n";
        foreach my $cl ( sort keys %{ $pack{cluster}{$vc} } ) {
          if ( !$useacl || $isAdmin || $isReadonly || $acl->hasItems( "V", $cl ) ) {

            $cl =~ /cluster_(.*)/;
            my $tcl = "Cluster: $1";
            $idx{cl} = push @{ $menu[ $idx{vmware} ]{children}[ $idx{vc} ]{children} }, { "title" => $tcl, "altname" => $cl, "folder" => "true", "children" => [] };
            $idx{cl}--;

            # print $n2 . "{\"title\":\"$cl\",\"folder\":\"true\",\"children\":[\n";
            if ( !$useacl || $isAdmin || $isReadonly || $acl->canShow( "VMWARE", "CLUSTER", "$cl" ) ) {
              clTotals( $vc, $cl );
            }

            # Resource Pools submenu
            if ( !$useacl || $isAdmin || $isReadonly ) {
              if ( exists $pack{respool}{$vc}{$cl} ) {
                $idx{rp} = push @{ $menu[ $idx{vmware} ]{children}[ $idx{vc} ]{children}[ $idx{cl} ]{children} }, { "title" => "Resource Pool", "folder" => "true", "children" => [] };
                $idx{rp}--;
                my $menuref = $menu[ $idx{vmware} ]{children}[ $idx{vc} ]{children}[ $idx{cl} ]{children}[ $idx{rp} ]->{children};
                if ( $pack{vtree}{vc}{$vc}{cluster}{$cl}{respools} ) {
                  my $folderref = $pack{vtree}{vc}{$vc}{cluster}{$cl}{respools};
                  genSubFolderRP( $folderref, $menuref, $vc, $cl );
                }

                # foreach my $rp ( sort keys %{ $pack{respool}{$vc}{$cl} } ) {
                #   if ( $rp ne "Resources" ) {
                #     push @{ $menu[ $idx{vmware} ]{children}[ $idx{vc} ]{children}[ $idx{cl} ]{children}[ $idx{rp} ]{children} }, pushFullNode( $rp, $pack{respool}{$vc}{$cl}{$rp}, $vc, $cl, 1, undef, undef, undef, "RP" );
                #   }
                # }
              }

              # ESXi submenu
              if ( exists $pack{vtree}{vc}{$vc}{cluster}{$cl}{host} ) {
                push @{ $menu[ $idx{vmware} ]{children}[ $idx{vc} ]{children}[ $idx{cl} ]{children} }, genESXi( $pack{vtree}{vc}{$vc}{cluster}{$cl}{host}, "ESXi", $vc, $cl, 0 );
              }
            }

            # VM submenu
            if ( exists $pack{lhmc}{$cl} ) {
              $idx{lpar} = push @{ $menu[ $idx{vmware} ]{children}[ $idx{vc} ]{children}[ $idx{cl} ]{children} }, { "title" => "VM", "folder" => "true", "children" => [] };
              $idx{lpar}--;
              my $allVMs;
              foreach my $srv ( keys %{ $pack{lhmc}{$cl} } ) {
                foreach my $vm ( @{ $pack{lhmc}{$cl}{$srv} } ) {
                  $allVMs->{ @$vm[0] }{url} = @$vm[1];
                  $allVMs->{ @$vm[0] }{alt} = @$vm[2];
                  $allVMs->{ @$vm[0] }{srv} = $srv;
                }
              }
              my $menuref = $menu[ $idx{vmware} ]{children}[ $idx{vc} ]{children}[ $idx{cl} ]{children}[ $idx{lpar} ]->{children};
              if ( $pack{vtree}{vc}{$vc}{cluster}{$cl} && $pack{vtree}{vc}{$vc}{cluster}{$cl}{vms} ) {
                my $folderref = $pack{vtree}{vc}{$vc}{cluster}{$cl}->{vms};
                genSubFolder( $folderref, $menuref, $allVMs, $vc, $cl );
              }
            }
          }
        }

        # print "]}\n";
      }
      if ( !$useacl || $isAdmin || $isReadonly ) {
        if ( $pack{datastore}{$vc} ) {
          for my $dc ( sort keys %{ $pack{datastore}{$vc} } ) {
            $dc =~ /datastore_(.*)/;
            my $tdc = "Datastores: $1";
            $idx{dc} = push @{ $menu[ $idx{vmware} ]{children}[ $idx{vc} ]{children} }, { title => $tdc, altname => $dc, folder => "true", children => [] };
            $idx{dc}--;

            my $menuref = $menu[ $idx{vmware} ]{children}[ $idx{vc} ]{children}[ $idx{dc} ]->{children};
            if ( $pack{vtree}{vc}{$vc}{datastores}{$dc} ) {
              my $folderref = $pack{vtree}{vc}{$vc}{datastores}{$dc};
              genSubFolderDS( $folderref, $menuref, $vc, $dc );
            }
          }
        }
      }
      if ( exists $pack{vtree}{vc}{$vc}{host} ) {
        push @{ $menu[ $idx{vmware} ]{children}[ $idx{vc} ]{children} }, genESXi( $pack{vtree}{vc}{$vc}{host}, "ESXi", $vc, "", 1 );

        #genESXi( $vc, "ESXi nocl", $vc, 1 );
      }
    }
  }
  if ( exists $pack{vtree}{esxi} ) {
    push @{ $menu[ $idx{vmware} ]{children} }, genESXi( $pack{vtree}{esxi}, "ESXi", "", "", 1 );

    #genESXi( "", "ESXi no VC", "", 1 );
  }
}

### Generate ESXi SERVERs submenu
sub genESXi {
  my ( $ref, $title, $vcntr, $clstr, $listVMs ) = @_;

  # for my $srv ( sort keys $pack{lstree} ) {
  my $hesxi = { "title" => $title, "folder" => "true", "children" => [] };
  for my $host ( sort keys %{$ref} ) {
    my $hhost = { "title" => $host, "altname" => $host, "folder" => "true", "children" => [] };
    foreach my $total ( @{ $ref->{$host}{menu} } ) {
      while ( my ( $key, $value ) = each %{$total} ) {
        my $alt = ( $key eq "CPU" ) ? "pool" : ( $key eq "Memory" || $key eq "Disk" || $key eq "LAN" ) ? "cod" : "";
        push @{ $hhost->{children} }, pushFullNode( $key, $value, $clstr, $host, 0, $alt, "V", $vcntr );
      }
    }
    if ($listVMs) {
      my $hvm = { "title" => "VM", "folder" => "true", "children" => [] };
      if ( exists $pack{lstree}{$host}->{$clstr} ) {
        for my $lpar ( sort { ncmp("\L$a->[0]", "\L$b->[0]") } @{ $pack{lstree}{$host}->{$clstr} } ) {
          my $thost;
          if ( !$vcntr ) {
            @$lpar[1] =~ /host=([^&]*)/;
            $thost = $1;
          }
          push @{ $hvm->{children} }, pushFullNode( @$lpar[0], @$lpar[1], ( $vcntr ? $vcntr : $thost ), $host, 1, @$lpar[2], "V", "", "VM" );
        }

        if ( exists $pack{rtree}{$host} ) {
          ## print "\n{\"title\":\"Removed\",\"folder\":\"true\",\"children\":[\n";
          for my $removed ( @{ $pack{rtree}{$host} } ) {
            ## print &fullNode( @$removed[0], @$removed[1], $vcntr, $srv, 1 );
          }
        }
        push @{ $hhost->{children} }, $hvm;
      }
    }
    push @{ $hesxi->{children} }, $hhost;
  }
  return $hesxi;
}

### Generate ESXi SERVERs submenu
sub genESXiServers {
  my ( $clstr, $title, $vcntr, $listVMs ) = @_;
  my $vcenterWoClusters = ( $vcntr eq $clstr );
  if ( !exists $pack{vtree}{vc}{$vcntr}{cluster}{$clstr} && !exists $pack{vtree}{vc}{$vcntr}{host} ) {
    return;
  }
  if ($clstr) {
    if ($vcenterWoClusters) {
      $idx{esxi} = push @{ $menu[ $idx{vmware} ]{children}[ $idx{vc} ]{children} }, { "title" => $title, "folder" => "true", "children" => [] };
    }
    else {
      $idx{esxi} = push @{ $menu[ $idx{vmware} ]{children}[ $idx{vc} ]{children}[ $idx{cl} ]{children} }, { "title" => $title, "folder" => "true", "children" => [] };
    }
  }
  else {
    $idx{esxi} = push @{ $menu[ $idx{vmware} ]{children} }, { "title" => $title, "folder" => "true", "children" => [] };
  }
  $idx{esxi}--;

  # for my $srv ( sort keys $pack{lstree} ) {
  for my $srv ( sort keys %{ $pack{times} } ) {
    if ( exists $pack{vtree}{$clstr}{$srv} && $pack{times}{$srv}{"active"} && $pack{times}{$srv}{type} eq "V" ) {
      my $tsrv = $pack{times}{$srv}{"alias"} ||= $srv;
      if ($clstr) {
        if ($vcenterWoClusters) {
          $idx{csrv} = push @{ $menu[ $idx{vmware} ]{children}[ $idx{vc} ]{children}[ $idx{esxi} ]{children} }, { "title" => $tsrv, "altname" => $srv, "folder" => "true", "children" => [] };
        }
        else {
          $idx{csrv} = push @{ $menu[ $idx{vmware} ]{children}[ $idx{vc} ]{children}[ $idx{cl} ]{children}[ $idx{esxi} ]{children} }, { "title" => $tsrv, "altname" => $srv, "folder" => "true", "children" => [] };
        }
      }
      else {
        $idx{csrv} = push @{ $menu[ $idx{vmware} ]{children}[ $idx{esxi} ]{children} }, { "title" => $tsrv, "altname" => $srv, "folder" => "true", "children" => [] };
      }
      $idx{csrv}--;
      for my $hmc (
        sort { $pack{times}{$srv}{timestamp}{$b} <=> $pack{times}{$srv}{timestamp}{$a} }
        keys %{ $pack{times}{$srv}{timestamp} }
        )
      {
        if ($clstr) {
          if ($vcenterWoClusters) {
            &serverMenu( $vcntr, $srv, $clstr, 1, 1 );
          }
          elsif ( exists $pack{stree}{$srv}{$vcntr} ) {
            &serverMenu( $vcntr, $srv, $clstr, 1 );
          }
        }
        else {
          my $host = ( keys %{ $pack{stree}{$srv} } )[0];
          if ( exists $pack{stree}{$srv}{$host} ) {
            &serverMenu( $host, $srv, undef, 1 );
          }
        }
        if ($listVMs) {
          if ($vcenterWoClusters) {
            $hmc = "";
          }
          if ( exists $pack{lstree}{$srv}->{$hmc} ) {
            if ($clstr) {
              if ($vcenterWoClusters) {
                $idx{lpar} = push @{ $menu[ $idx{vmware} ]{children}[ $idx{vc} ]{children}[ $idx{esxi} ]{children}[ $idx{csrv} ]{children} }, { "title" => "VM", "folder" => "true", "children" => [] };
              }
              else {
                $idx{lpar} = push @{ $menu[ $idx{vmware} ]{children}[ $idx{vc} ]{children}[ $idx{cl} ]{children} }, { "title" => "VM", "folder" => "true", "children" => [] };
              }
            }
            else {
              $idx{lpar} = push @{ $menu[ $idx{vmware} ]{children}[ $idx{esxi} ]{children}[ $idx{csrv} ]{children} }, { "title" => "VM", "folder" => "true", "children" => [] };
            }
            $idx{lpar}--;
            for my $lpar ( sort { "\L$a->[0]" cmp "\L$b->[0]" } @{ $pack{lstree}{$srv}->{$hmc} } ) {
              my $thost;
              if ( !$vcntr ) {
                @$lpar[1] =~ /host=([^&]*)/;
                $thost = $1;
              }

              if ($clstr) {
                if ($vcenterWoClusters) {
                  push @{ $menu[ $idx{vmware} ]{children}[ $idx{vc} ]{children}[ $idx{esxi} ]{children}[ $idx{csrv} ]{children}[ $idx{lpar} ]{children} }, pushFullNode( @$lpar[0], @$lpar[1], ( $vcntr ? $vcntr : $thost ), $srv, 1, @$lpar[2], "VM" );
                }

                # push @{ $menu[$idx{vmware}]{children}[$idx{vc}]{children}[$idx{cl}]{children}[$idx{lpar}]{children} }, pushFullNode( @$lpar[0], @$lpar[1], ($vcntr ? $vcntr : $thost), $srv, 1, @$lpar[2] );
              }
              else {
                push @{ $menu[ $idx{vmware} ]{children}[ $idx{esxi} ]{children}[ $idx{csrv} ]{children}[ $idx{lpar} ]{children} }, pushFullNode( @$lpar[0], @$lpar[1], ( $vcntr ? $vcntr : $thost ), $srv, 1, @$lpar[2], "VM" );
              }

            }    # L3 END
            if ( exists $pack{rtree}{$srv} ) {
              ## print "\n{\"title\":\"Removed\",\"folder\":\"true\",\"children\":[\n";
              for my $removed ( @{ $pack{rtree}{$srv} } ) {
                ## print &fullNode( @$removed[0], @$removed[1], $vcntr, $srv, 1 );
              }
            }
          }
        }
        last;
      }    # L2 END
    }
  }
}

sub genPredefined {
  print "[\n";    # envelope begin
  my $delim = "";
  for my $srv ( sort keys %{ $pack{times} } ) {
    for my $hmc (
      sort { $pack{times}{$srv}{timestamp}{$b} <=> $pack{times}{$srv}{timestamp}{$a} }
      keys %{ $pack{times}{$srv}{timestamp} }
      )
    {
      if ( $pack{times}{$srv}{type} eq "P" ) {
        my $hash = substr( md5_hex_uc( $hmc . $srv . "pool" ), 0, 7 );
        print $delim . "\"" . $hash . "xkdma\"";
        $delim = ",\n";

        # print $delim . "\"" . $hash . "xldma\""; # aggregated
        last;
      }
    }
  }
  for my $vc ( keys %{ $pack{cluster} } ) {
    for my $cl ( keys %{ $pack{cluster}{$vc} } ) {
      my $url   = $pack{cluster}{$vc}{$cl}{'Totals'};
      my $cl_id = ( $url =~ /host=([^&]*)/ )[0];
      my $vc_id = ( $url =~ /server=([^&]*)/ )[0];
      my $hash  = substr( md5_hex_uc( $cl_id . $vc_id . "nope" ), 0, 7 );
      print $delim . "\"" . $hash . "amdma\"";
      $delim = ",\n";
    }
  }
  for ( @{ $pack{ctree} } ) {
    my $grp = @$_[0];

    # $egrp = @$_[1];
    my $hash = substr( md5_hex_uc( "nana" . $grp ), 0, 7 );
    print $delim . "\"" . $hash . "xodna\"";
    $delim = ",\n";
  }
  print "\n]\n";    # envelope end
}

### Generate HMCs submenu
sub genHMCs {

  # print "{\"title\":\"HMC\",\"folder\":\"true\",\"children\":[\n";
  for my $hmc ( sort keys %{ $pack{hmc} } ) {
    if ( $pack{hmc}{$hmc}{type} ne 'P' ) {
      next;
    }
    $idx{hmc} = push @{ $menu[ $idx{psrv} ]{children} }, { "title" => "$hmc", "folder" => "true", "children" => [] };
    $idx{hmc}--;
    if ( exists $pack{hmc}{$hmc} ) {
      if ( !$useacl || $isAdmin || $isReadonly ) {
        hmcTotals($hmc);
      }
    }
    for my $srv ( sort keys %{ $pack{lhmc}{$hmc} } ) {
      if ( !$pack{times}{$srv}{"removed"}{$hmc} ) {
        $idx{csrv} = push @{ $menu[ $idx{psrv} ]{children}[ $idx{hmc} ]{children} }, { "title" => "$srv", "folder" => "true", "children" => [] };
        $idx{csrv}--;
        if ( exists $pack{stree}{$srv}->{$hmc} && ( !$useacl || $isAdmin || $isReadonly ) ) {
          serverByHmc( $hmc, $srv );
        }
        if ( exists $pack{lhmc}{$hmc}->{$srv} ) {
          $idx{lpars} = push @{ $menu[ $idx{psrv} ]{children}[ $idx{hmc} ]{children}[ $idx{csrv} ]{children} }, { "title" => "LPAR", "folder" => "true", "children" => [] };
          $idx{lpars}--;
          for my $lpar ( sort { "\L$a->[0]" cmp "\L$b->[0]" } @{ $pack{lhmc}{$hmc}->{$srv} } ) {
            if ( exists $pack{wtree}{$srv}->{$hmc}->{ @$lpar[2] } ) {
              $idx{wpars} = push @{ $menu[ $idx{psrv} ]{children}[ $idx{hmc} ]{children}[ $idx{csrv} ]{children}[ $idx{lpars} ]{children} }, pushFullNodewChild( @$lpar[0], @$lpar[1], $hmc, $srv, 1, @$lpar[2], $pack{hmc}{$hmc}{type} );
              $idx{wpars}--;
              for my $wpar ( @{ $pack{wtree}{$srv}->{$hmc}->{ @$lpar[2] } } ) {
                push @{ $menu[ $idx{psrv} ]{children}[ $idx{hmc} ]{children}[ $idx{csrv} ]{children}[ $idx{lpars} ]{children}[ $idx{wpars} ]{children} }, pushFullNode( @$wpar[0], @$wpar[1], $hmc, $srv, 1, @$lpar[0] . "/" . @$wpar[0] );
              }
            }
            else {
              push @{ $menu[ $idx{psrv} ]{children}[ $idx{hmc} ]{children}[ $idx{csrv} ]{children}[ $idx{lpars} ]{children} }, pushFullNode( @$lpar[0], @$lpar[1], $hmc, $srv, 1, @$lpar[2], $pack{hmc}{$hmc}{type} );
            }
          }    # L3 END
          if ( exists $pack{rtree}{$srv} ) {
            $idx{removed} = push @{ $menu[ $idx{psrv} ]{children}[ $idx{hmc} ]{children}[ $idx{csrv} ]{children}[ $idx{lpars} ]{children} }, { "title" => "Removed", "folder" => "true", "children" => [] };
            $idx{removed}--;
            for my $removed ( @{ $pack{rtree}{$srv} } ) {
              push @{ $menu[ $idx{psrv} ]{children}[ $idx{hmc} ]{children}[ $idx{csrv} ]{children}[ $idx{lpars} ]{children}[ $idx{removed} ]{children} }, pushFullNode( @$removed[0], @$removed[1], $hmc, $srv, 1 );
            }
          }
        }
        my $ref = $menu[ $idx{psrv} ]{children}[ $idx{hmc} ]{children}[ $idx{csrv} ]{children};
        if ( exists $pack{lantree}{$srv}{$hmc} ) {
          sub_tree_ref( $srv, $hmc, "lan", $ref, "LAN", "N" );
        }
        if ( exists $pack{santree}{$srv}{$hmc} ) {
          sub_tree_ref( $srv, $hmc, "san", $ref, "SAN", "Y" );
        }
        if ( exists $pack{sastree}{$srv}{$hmc} ) {
          sub_tree_ref( $srv, $hmc, "sas", $ref, "SAS", "s" );
        }
        if ( exists $pack{sriovtree}{$srv}{$hmc} ) {
          sub_tree_ref( $srv, $hmc, "sriov", $ref, "SR-IOV", "r" );
        }
        if ( exists $pack{heatree}{$srv}{$hmc} ) {
          sub_tree_ref( $srv, $hmc, "hea", $ref, "HEA", "HEA" );
        }
      }
    }
  }
}

sub globalHmcTotals {
  if ( !$useacl || $isAdmin || $acl->canShow("POWER") ) {
    if ( $pack{lhmc} ) {
      if ( $idx{psrv} ) {
        if ( $pack{cmc} ) {
          if ( 1 || $acl->canShow("CMC") ) {
            push @{ $menu[ $idx{psrv} ]{children} }, $pack{cmc};
          }
        }
        $idx{hmc} = push @{ $menu[ $idx{psrv} ]{children} }, { "title" => "HMC Totals", "folder" => "true", "children" => [] };
      }
      else {
        if ( $pack{cmc} ) {
          if ( 1 || $acl->canShow("CMC") ) {
            push @menu, $pack{cmc};
          }
        }
        $idx{hmc} = push @menu, { "title" => "HMC Totals", "folder" => "true", "children" => [] };
      }
      $idx{hmc}--;
      for my $hmc ( sort keys %{ $pack{hmc} } ) {
        if ( $pack{hmc}{$hmc}{type} eq "P" ) {
          if ( $idx{psrv} ) {
            push @{ $menu[ $idx{psrv} ]{children}[ $idx{hmc} ]{children} }, pushmenu( $hmc, $pack{hmc}{$hmc}{url}, $pack{hmc}{$hmc}{id} );
          }
          else {
            push @{ $menu[ $idx{hmc} ]{children} }, pushmenu( $hmc, $pack{hmc}{$hmc}{url}, $pack{hmc}{$hmc}{id} );
          }
        }
      }
    }
  }
}

### Generate HMC select tree
sub genHmcSelect {
  my $n1 = "";
  for my $hmc ( sort keys %{ $pack{lhmc} } ) {
    if ( ( !$pack{hmc}{$hmc} || $pack{hmc}{$hmc}{type} && $pack{hmc}{$hmc}{type} ne "P" ) || $hmc eq "no_hmc" ) {
      next;
    }
    print $n1 . "{\"title\":\"$hmc\",\"folder\":\"true\",\"children\":[\n";
    $n1 = ",";
    my $n2 = "";
    for my $srv ( sort keys %{ $pack{lhmc}{$hmc} } ) {
      my $extra = "";
      if ( !$pack{times}{$srv}{"active"} ) {
        $extra = "\"extraClasses\":\"removed\",";
      }
      print $n2 . "{\"title\":\"$srv\",$extra\"folder\":\"true\",\"children\":[\n";
      $n2 = ",";

      # print "{\"title\":\"LPAR\",\"folder\":\"true\",\"children\":[\n";
      my $n3 = "";
      for my $lpar ( @{ $pack{lhmc}{$hmc}->{$srv} } ) {
        my $noalias = @$lpar[0];
        $noalias =~ s/ \[.*\]//g;
        my $value = "$hmc|$srv|$noalias";
        print $n3 . "{\"title\":\"@$lpar[0]\",\"key\":\"$value\"}";
        $n3 = ",";
      }    # L3 END
      if ( exists $pack{rtree}{$srv} ) {
        for my $removed ( @{ $pack{rtree}{$srv} } ) {
          my $value  = "$hmc|$srv|@$removed[0]";
          my $lextra = $extra ? "" : "\"extraClasses\":\"removed\",";
          print $n3 . "\n" . "{\"title\":\"@$removed[0]\",$lextra\"key\":\"$value\"}";
        }
      }
      print "]}";
    }    # L2 END
    print "]}\n";
  }
}

### Generate lpar list for select inputs
sub genLpars {
  my $n1 = "";
  for my $srv ( sort keys %{ $pack{times} } ) {
    if ( !exists $pack{times}{$srv}{type} || $pack{times}{$srv}{type} ne "P" ) {
      next;
    }
    my $extra = "";
    if ( !$pack{times}{$srv}{"active"} ) {
      $extra = "\"extraClasses\":\"removed\",";
    }
    print $n1 . "{\"title\":\"$srv\",\"folder\":\"true\",$extra\"key\":\"_$srv\",\"children\":[\n";
    $n1 = ",";
    my $n2 = "";
    for my $hmc (
      sort { $pack{times}{$srv}{timestamp}{$b} <=> $pack{times}{$srv}{timestamp}{$a} }
      keys %{ $pack{times}{$srv}{timestamp} }
      )
    {

      #		print $n2 . "{\"title\":\"$hmc\",\"folder\":\"true\",\"children\":[\n";
      #			$n2 = ",";
      my $n3 = "";
      for my $lpar ( sort keys %{ $pack{lpartree}{$srv} } ) {
        my $noalias = $lpar;
        $noalias =~ s/ \[.*\]//g;
        my $value = "$hmc|$srv|$noalias";
        print $n3 . "{\"title\":\"$lpar\",\"key\":\"$value\"}";
        $n3 = ",";
      }    # L3 END
      if ( exists $pack{rtree}{$srv} ) {
        for my $removed ( @{ $pack{rtree}{$srv} } ) {
          my $value  = "$hmc|$srv|@$removed[0]";
          my $lextra = $extra ? "" : "\"extraClasses\":\"removed\",";
          print $n3 . "\n" . "{\"title\":\"@$removed[0]\",$lextra\"key\":\"$value\"}";
          $n3 = ",";
        }
      }
      last;
    }    # L2 END
    print "]}";
  }
}

### Generate lpar list for CPU Workload Estimator (just POWER servers)
sub genLparsEst {
  my $n1 = "";
  for my $srv ( sort keys %{ $pack{times} } ) {
    if ( ( exists $pack{times}{$srv}{type} && $pack{times}{$srv}{type} ne "P" ) || exists $pack{lhmc}{no_hmc}{$srv} ) {
      next;
    }
    my $extra = "";
    if ( !$pack{times}{$srv}{"active"} ) {
      $extra = "\"extraClasses\":\"removed\",";
    }
    print $n1 . "{\"title\":\"$srv\",\"folder\":\"true\",$extra\"key\":\"_$srv\",\"children\":[\n";
    $n1 = ",";
    my $n2 = "";
    for my $hmc (
      sort { $pack{times}{$srv}{timestamp}{$b} <=> $pack{times}{$srv}{timestamp}{$a} }
      keys %{ $pack{times}{$srv}{timestamp} }
      )
    {

      #		print $n2 . "{\"title\":\"$hmc\",\"folder\":\"true\",\"children\":[\n";
      #			$n2 = ",";
      my $n3 = "";
      for my $lpar ( sort keys %{ $pack{lpartree}{$srv} } ) {
        my $noalias = $lpar;
        $noalias =~ s/ \[.*\]//g;
        my $value = "$hmc|$srv|$noalias";
        print $n3 . "{\"title\":\"$lpar\",\"key\":\"$value\"}";
        $n3 = ",";
      }    # L3 END
      if ( exists $pack{rtree}{$srv} ) {
        for my $removed ( @{ $pack{rtree}{$srv} } ) {
          my $value  = "$hmc|$srv|@$removed[0]";
          my $lextra = $extra ? "" : "\"extraClasses\":\"removed\",";
          print $n3 . "\n" . "{\"title\":\"@$removed[0]\",$lextra\"key\":\"$value\"}";
          $n3 = ",";
        }
      }
      last;
    }    # L2 END
    print "]}";
  }
}

### Generate lpar list for select inputs
sub aclSelect {
  &readMenu();
  ### Generate JSON
  print "[\n";    # envelope begin
  my $n1 = "";
  for my $srv ( sort keys %{ $pack{times} } ) {
    if ( $pack{times}{$srv}{type} ne "P" ) {
      next;
    }
    my $extra = "";
    if ( !$pack{times}{$srv}{"active"} ) {
      $extra = "\"extraClasses\":\"removed\",";
    }
    print $n1 . "{\"title\":\"$srv\",\"folder\":\"true\",$extra\"key\":\"_$srv\",\"children\":[\n";
    $n1 = ",";
    my $n2 = "";
    for my $hmc (
      sort { $pack{times}{$srv}{timestamp}{$b} <=> $pack{times}{$srv}{timestamp}{$a} }
      keys %{ $pack{times}{$srv}{timestamp} }
      )
    {

      #		print $n2 . "{\"title\":\"$hmc\",\"folder\":\"true\",\"children\":[\n";
      #			$n2 = ",";
      my $n3 = "";
      for my $lpar ( keys %{ $pack{lpartree}{$srv} } ) {
        my $noalias = @$lpar;
        $noalias =~ s/ \[.*\]//g;
        my $value = "$hmc|$srv|$noalias";
        print $n3 . "{\"title\":\"$lpar\",\"key\":\"$value\"}";
        $n3 = ",";
      }    # L3 END
      if ( exists $pack{rtree}{$srv} ) {
        for my $removed ( @{ $pack{rtree}{$srv} } ) {
          my $value  = "$hmc|$srv|@$removed[0]";
          my $lextra = $extra ? "" : "\"extraClasses\":\"removed\",";
          print $n3 . "\n" . "{\"title\":\"@$removed[0]\",$lextra\"key\":\"$value\"}";
          $n3 = ",";
        }
      }
      print "]}";
      last;
    }    # L2 END
  }
  print "\n]\n";    # envelope end
}

### Generate pool list for select inputs
sub genPools {
  my $n1 = "";
  for my $srv ( sort keys %{ $pack{lstree} } ) {
    if ( exists $pack{times}{$srv}{type} && $pack{times}{$srv}{type} eq "V" ) {
      next;
    }
    my $extra = "";
    if ( !$pack{times}{$srv}{"active"} ) {
      $extra = "\"extraClasses\":\"removed\",";
    }
    print $n1 . "{\"title\":\"$srv\",\"folder\":\"true\",$extra\"key\":\"_$srv\",\"children\":[\n";
    $n1 = ",";
    my $n2 = "";
    for my $hmc ( sort keys %{ $pack{lstree}{$srv} } ) {

      #		print $n2 . "{\"title\":\"$hmc\",\"folder\":\"true\",\"children\":[\n";
      #			$n2 = ",";
      my $n3 = "";
      for my $lpar ( @{ $pack{stree}{$srv}->{$hmc} } ) {
        if ( @$lpar[0] =~ /pool/ ) {
          my $value = "$hmc|$srv|@$lpar[2]";
          print $n3 . "{\"title\":\"@$lpar[0]\",\"key\":\"$value\"}";
          $n3 = ",";
        }
      }    # L3 END
      last;
    }    # L2 END
    print "]}";
  }
}

### Generate pool list for Estimator
sub genPoolsEst {
  my $n1 = "";
  for my $srv ( sort keys %{ $pack{lpartree} } ) {
    if ( exists $pack{times}{$srv}{type} && $pack{times}{$srv}{type} ne "P" ) {
      next;
    }
    my $extra = "";
    if ( !$pack{times}{$srv}{"active"} ) {
      $extra = "\"extraClasses\":\"removed\",";
    }
    print $n1 . "{\"title\":\"$srv\",\"folder\":\"true\",$extra\"key\":\"_$srv\",\"children\":[\n";
    $n1 = ",";
    my $n2 = "";

    # for my $hmc ( sort keys %{ $pack{lstree}{$srv} } ) {
    for my $hmc (
      sort { $pack{times}{$srv}{timestamp}{$b} <=> $pack{times}{$srv}{timestamp}{$a} }
      keys %{ $pack{times}{$srv}{timestamp} }
      )
    {
      #		print $n2 . "{\"title\":\"$hmc\",\"folder\":\"true\",\"children\":[\n";
      # print STDERR "HMC: $hmc\n";
      #			$n2 = ",";
      #$hmc = $hmc[0];
      my $n3 = "";
      for my $lpar ( @{ $pack{stree}{$srv}->{$hmc} } ) {

        #if ( @$lpar[0] eq "CPU" ) {
        #  my $value = "$hmc|$srv|pool-total";
        #  print $n3 . "{\"title\":\"@$lpar[0]\",\"key\":\"$value\"}";
        #  $n3 = ",";
        #}
        if ( @$lpar[0] =~ /pool/ || @$lpar[0] eq 'CPU' ) {    #HD - added CPU Total, hist.reports 06/18/2020 - not in menu.txt so if CPU (pool) is there (always)
          if ( @$lpar[0] eq 'CPU' ) {
            my $value = "$hmc|$srv|total";
            print $n3 . "{\"title\":\"CPU Total\",\"key\":\"$value\"}";
            $n3    = ",";
            $value = "$hmc|$srv|pool";
            print $n3 . "{\"title\":\"CPU Pool\",\"key\":\"$value\"}";
            $n3 = ",";
          }
          elsif ( !( @$lpar[0] =~ /DefaultPool/ ) ) {
            my $value = "$hmc|$srv|@$lpar[2]";
            print $n3 . "{\"title\":\"@$lpar[0]\",\"key\":\"$value\"}";
            $n3 = ",";
          }
        }
      }    # L3 END
      last;
    }    # L2 END
    print "]}";
  }
}

### Generate pool list for non-global historical reports
sub genServerPools {
  my ( $hmc, $srv ) = @_;
  my $n3 = "";
  for my $lpar ( @{ $pack{stree}{$srv}->{$hmc} } ) {
    if ( @$lpar[2] =~ /pool/i ) {
      my $value = "@$lpar[2]";
      if ( $value eq "pool" ) {
        print $n3 . txtkeysel( @$lpar[0], $value );
      }
      else {
        print $n3 . txtkey( @$lpar[0], $value );
      }
      $n3 = ",";
    }
  }
  print $n3;
}

### Generate Custom groups list for select inputs
sub genCusts {
  my $filter = shift;
  my $delim  = '';
  foreach my $cgroup ( sort keys %{ $pack{ctreeh} } ) {
    if ( $cgroup ne "Custom groups" && $cgroup ne "<b>Configuration</b>" ) {
      if ($filter) {
        my $cgrptype = ( $pack{ctreeh}{$cgroup} =~ /host=([^&]*)/ )[0];
        if ( $filter ne $cgrptype ) {
          next;
        }
      }
      my $egrp = urlencode($cgroup);
      print $delim . "{\"title\":\"$cgroup\",\"obj\":\"C\",\"key\":\"$egrp\"}";
      $delim = ",\n";
    }
  }
}

### Generate VMware Clusters list for select inputs
sub genClusters {
  my $vc = shift;
  &readMenu;
  print "[\n";                              # envelope begin
  if ( !exists $pack{vtree}{vc}{$vc} ) {    # if not hostname then test vcenter id
    $vc = get_vcenter_hostname_from_id($vc);
  }
  my $delim = '';
  foreach my $cl ( keys %{ $pack{cluster}{$vc} } ) {
    ( my $cls = $cl ) =~ s/cluster_//;
    print $delim . "{\"title\":\"$cls\",\"key\":\"$cl\"}";
    $delim = ",\n";
  }
  print "\n]\n";                            # envelope end
}
### Generate VMware DataStores list for select inputs
sub genDataStores {
  my $vc = shift;
  &readMenu;
  print "[\n";                              # envelope begin
  if ( !exists $pack{vtree}{vc}{$vc} ) {    # if not hostname then test vcenter id
    $vc = get_vcenter_hostname_from_id($vc);
  }
  my $delim = '';
  if ( exists $pack{datastore}{$vc} ) {
    foreach my $dc ( keys %{ $pack{datastore}{$vc} } ) {
      ( my $dcs = $dc ) =~ s/datastore_//;
      print $delim . "{\"title\":\"$dcs\",\"folder\":\"true\",\"key\":\"_$dc\",\"children\":[\n";
      $delim = ",\n";
      my $delim1 = '';
      foreach my $ds ( keys %{ $pack{datastore}{$vc}{$dc} } ) {
        my $key = "$dc:$ds";
        print $delim1 . "{\"title\":\"$ds\",\"key\":\"$key\"}";
        $delim1 = ",\n";
      }
      print "]}";
    }
  }
  print "\n]\n";    # envelope end
}
### Generate VMware resPools list for select inputs
sub genResPools {
  my $vc = shift;
  &readMenu;
  print "[\n";                              # envelope begin
  if ( !exists $pack{vtree}{vc}{$vc} ) {    # if not hostname then test vcenter id
    $vc = get_vcenter_hostname_from_id($vc);
  }
  my $delim = '';
  if ( exists $pack{respool}{$vc} ) {
    foreach my $cl ( keys %{ $pack{respool}{$vc} } ) {
      ( my $cls = $cl ) =~ s/cluster_//;
      print $delim . "{\"title\":\"$cls\",\"folder\":\"true\",\"key\":\"_$cl\",\"children\":[\n";
      $delim = ",\n";
      if ( ref( $pack{respool}{$vc}{$cl} ) eq "HASH" ) {
        my $delim1 = '';
        foreach my $rp ( keys %{ $pack{respool}{$vc}{$cl} } ) {
          my $key = "$cl:$rp";
          print $delim1 . "{\"title\":\"$rp\",\"key\":\"$key\"}";
          $delim1 = ",\n";
        }
      }
      print "]}";
    }
  }
  print "\n]\n";    # envelope end
}

### input param vc can be vcenter hostname or vcenter id
### hostname is OK but id has to be looked for
sub get_vcenter_hostname_from_id {
  my $vc = shift;    # is id

  #  my ($key) =  grep{$pack{vtree}{vc}{$_}{uuid} eq '*eb6102a7-1fa0-4376-acbb-f67e34a2212c_28*' } keys %{$pack{vtree}{vc}};
  foreach my $subject ( keys %{ $pack{vtree}{vc} } ) {

    # print STDERR "2479 $subject $pack{vtree}{vc}{$subject}{uuid}\n";
    if ( $pack{vtree}{vc}{$subject}{uuid} eq "vmware_$vc" ) {    # like vmware_eb6102a7-1fa0-4376-acbb-f67e34a2212c_28
                                                                 # print STDERR "2481 found hostname $subject for id $vc\n";
      $vc = $subject;
      last;
    }
  }
  return $vc;
}

### Generate VMware VM list for select inputs
sub genVMs {
  my $vc = shift;

  if ( $ENV{HTTP_XORUX_APP} && $ENV{HTTP_XORUX_APP} eq "Xormon" ) {
    my $sources = {};
    my @vmlist;
    $vc = get_vcenter_hostname_from_id($vc);
    my $vclist = SQLiteDataWrapper::getSubsysItems( { hw_type => 'VMWARE', subsys => 'VCENTER' } );
    for my $vcenter (@$vclist) {
      # push @vmlist, { vc => $vc, item_id => $vcenter->{item_id} };
      if ( $vc eq $vcenter->{item_id} ) {
        my $vc_children = SQLiteDataWrapper::getItemChildren( { item_id => $vcenter->{item_id} } );
        for my $cluster ( values %{ $vc_children->{CLUSTER} } ) {
          my $cl_children = SQLiteDataWrapper::getItemChildren( { item_id => $cluster->{item_id} } );

          for my $vm ( values %{ $cl_children->{VM} } ) {
            my $aclitem = {
              hw_type => 'VMWARE',
              item_id => $vm->{item_id},
              match   => 'granted'
            };
            if ( $acl->isGranted($aclitem) ) {
              $sources->{ $cluster->{label} }{ $vm->{label} } = $vm->{item_id};
            }
          }
        }
      }
    }
    for my $clkey ( nsort keys %{ $sources } ) {
      my $vms;
      for my $vmkey ( nsort keys %{ $sources->{$clkey} } ) {
        push @$vms, { title => $vmkey, key => $sources->{$clkey}{$vmkey} };
      }
      ( my $cls = $clkey ) =~ s/cluster_//;
      push @vmlist, { title => $cls, folder => 1, children => $vms };

    }

    print JSON->new->utf8(1)->pretty()->encode(\@vmlist);
  }
  else {
    binmode( STDOUT, "encoding(UTF-8)" );
    &readMenu;

    if ( !exists $pack{vtree}{vc}{$vc} ) {    # if not hostname then test vcenter id
      $vc = get_vcenter_hostname_from_id($vc);
    }

    print "[\n";    # envelope begin

    # print STDERR Dumper("2475 genjson.pl", "\$vc",$vc,$pack{vtree}{vc}{$vc}{uuid});
    my $delim = '';
    foreach my $cl ( keys %{ $pack{cluster}{$vc} } ) {
      if ( exists $pack{lhmc}{$cl} ) {
        ( my $cls = $cl ) =~ s/cluster_//;
        my $n3 = "";
        print $delim . "{\"title\":\"$cls\",\"folder\":\"true\",\"children\":[\n";
        $delim = ",";
        my %allVMs;
        foreach my $srv ( keys %{ $pack{lhmc}{$cl} } ) {
          foreach my $vm ( @{ $pack{lhmc}{$cl}{$srv} } ) {
            $allVMs{ @$vm[0] }{url} = @$vm[1];
            $allVMs{ @$vm[0] }{alt} = @$vm[2];
            $allVMs{ @$vm[0] }{srv} = $srv;
          }
        }
        for my $lpar ( sort { lc($a) cmp lc($b) } keys %allVMs ) {
          print $n3 . "{\"title\":\"$lpar\",\"key\":\"$allVMs{$lpar}{alt}\"}";

          # print $n3 . &fullNode( $lpar, $allVMs{$lpar}{url}, $vc, $allVMs{$lpar}{srv}, 1, $allVMs{$lpar}{alt}, "V", $cl );
          $n3 = ",";
        }    # L3 END
        print "]}\n";
      }
    }
    print "\n]\n";    # envelope end
  }
}

### Generate Linux host list for select inputs
sub genLinuxHosts {
  my $vc = shift;
  &readMenu;
  print "[\n";      # envelope begin
  my $delim = '';
  my $n3    = "";
  for my $lpar ( @{ $pack{lstree}{Linux}->{no_hmc} } ) {
    my $value = "@$lpar[2]";
    print $n3 . "{\"title\":\"@$lpar[0]\",\"key\":\"$value\"}";
    $n3 = ",";
  }
  print "\n]\n";    # envelope end
}

sub histReport {
  my ( $hmc, $srv, $type, $hostname ) = @_;
  print "[\n";
  $type ||= "power";

  #print txtkeysel("All CPU pools", "pool") . ",\n";
  my $vmname = "LPAR";
  if ( $type eq "vmware" ) {
    $vmname = "VM";
    if ( $hmc eq "solo_esxi" ) {
      $hmc = "";
    }
    &genServerPools( $hostname, $srv );
  }
  elsif ( $type eq "power" ) {
    &genServerPools( $hmc, $srv );
    print txtkeysel( $vmname . "s aggregated", "multiview" ) . ",\n";
  }

  print txtkey( "Memory", "mem" ) . "\n";

  if ( $type eq "vmware" ) {
    print "," . txtkey( "Disk", "disk" ) . "\n";
    print "," . txtkey( "Net",  "net" ) . "\n";
  }

  # if ($type ne "vmware") {
  print ",{\"title\":\"$vmname\",\"folder\":\"true\",\"key\":\"_$hmc-$srv\",\"expanded\":true,\"children\":[\n";
  my $n3 = "";
  if ( $type eq "power" ) {
    for my $lpar ( sort keys %{ $pack{lpartree}{$srv} } ) {
      print $n3 . "{\"title\":\"$lpar\",\"key\":\"$lpar\"}";
      $n3 = ",\n";
    }
  }
  else {
    for my $lpar ( @{ $pack{lstree}{$srv}->{$hmc} } ) {
      my $value = ( $type ne "vmware" ) ? "@$lpar[0]" : "@$lpar[2]";
      print $n3 . "{\"title\":\"@$lpar[0]\",\"key\":\"$value\"}";
      $n3 = ",\n";
    }
  }
  if ( exists $pack{rtree}{$srv} ) {
    for my $removed ( @{ $pack{rtree}{$srv} } ) {
      print $n3 . "\n" . "{\"title\":\"@$removed[0]\",\"extraClasses\":\"removed\",\"key\":\"@$removed[0]\"}";
    }
  }
  print "]}";

  # }

  print "]";

}

sub urlencode {
  my $s = shift;

  # $s =~ s/ /+/g;
  $s =~ s/([^a-zA-Z0-9_.!~*()'\''-])/sprintf("%%%02X", ord($1))/ge;

  # $s =~ s/([^A-Za-z0-9\+-_])/sprintf("%%%02X", ord($1))/seg;
  return $s;
}

sub urldecode {
  my $s = shift;
  if ($s) {
    $s =~ s/\%([A-Fa-f0-9]{2})/pack('C', hex($1))/seg;
  }
  return $s;
}

# encode
# $string =~ s/([^^A-Za-z0-9\-_.!~*'()])/ sprintf "%%%0x", ord $1 /eg;
#
# #decode
# $string =~ s/%([A-Fa-f\d]{2})/chr hex $1/eg;

### Global section without Title
sub globalWoTitle {
  my $fsub    = "";
  my $csub    = "";
  my $hsub    = "";
  my $variant = $env{variant} eq "p" ? "<span style='font-weight: normal'>(free)</span>" : "";

  if ( $pack{ftreeh} ) {
    $fsub = 1;
  }
  if ( $pack{ctreeh} ) {
    $csub = 1;
  }

  #for ( sort keys %{ $pack{global}{""} } ) {
  #  my $t = $pack{global}{""}{$_}{text};
  # if ( ( lc $t eq "favourites" ) && $fsub ) {
  if ($fsub) {
    &favs();
  }

  #} ## end for ( sort keys %{ $pack...
  if ( $env{platform}{power} && scalar keys %{ $env{platform} } == 1 ) {
    for ( sort keys %{ $pack{global}{P} } ) {
      my $t  = $pack{global}{P}{$_}{text};
      my $u  = $pack{global}{P}{$_}{url};
      my $id = $pack{global}{P}{$_}{id};
      if ( lc $t eq "custom groups" || lc $t eq "alerting" ) {
        next;
      }
      push @menu, pushmenu( $t, $u, $id );
    }
    globalHmcTotals();
  }
  elsif ( $env{platform}{vmware} && scalar keys %{ $env{platform} } == 1 ) {
    for ( sort keys %{ $pack{global}{V} } ) {
      my $t  = $pack{global}{V}{$_}{text};
      my $u  = $pack{global}{V}{$_}{url};
      my $id = $pack{global}{V}{$_}{id};
      push @menu, pushmenu( $t, $u, $id );
    }
    $idx{vmware} = push @menu, { "title" => "VMware", "folder" => "true", "children" => [] };
    $idx{vmware}--;

    #  push @{ $menu[ $idx{vmware} ]{children} }, pushFullNode( "<b>Configure</b>", "/lpar2rrd-cgi/vmwcfg.sh?cmd=getlist", "VMware", "VMware", 0 );
  }
}

### Favourites
sub favs {
  if ( $pack{ftreeh} ) {
    $idx{favs} = push @menu, { title => "FAVOURITES", folder => "true", children => [] };
    $idx{favs}--;
    for my $fav ( @{ $pack{ftreeh} } ) {
      push @{ $menu[ $idx{favs} ]{children} }, pushmenu( @$fav[0], @$fav[1] );
    }
  }
}
### Custom Groups
sub custs {
  my %coll = CustomGroups::getCollections();
  if (%coll) {
    $idx{custom} = push @menu, { title => "CUSTOM GROUPS", folder => "true", children => [] };
    $idx{custom}--;
    if ( $env{free} ne 1 ) {
      push @{ $menu[ $idx{custom} ]{children} }, { title => "Historical reports", href => "/lpar2rrd-cgi/histrep.sh?mode=custom", key => "histrep-custom", extraClasses => "boldmenu" };
    }

    # my $delim = ",\n";
    if ( $coll{collection} ) {
      for my $collname ( sort keys %{ $coll{collection} } ) {

        #$idx{cfav} = push @{ $menu[ $idx{custom} ]{children} }, { title => $collname, folder => "true", children => [] };
        #$idx{cfav}--;
        my $cfav = { title => $collname, folder => "true", children => [] };
        for my $cgrp ( nsort keys %{ $coll{collection}{$collname} } ) {
          if ( $pack{ctreeh}{$cgrp} ) {
            push @{ $cfav->{children} }, pushFullNode( $cgrp, $pack{ctreeh}{$cgrp}, "na", "na", 0, undef, undef, undef, "C" );
          }
        }
        if ( @{ $cfav->{children} } ) {
          push @{ $menu[ $idx{custom} ]{children} }, $cfav;
        }

      }
    }
    if ( $coll{nocollection} ) {

      # print Dumper \%ctreeh;
      for my $cgrp ( nsort keys %{ $coll{nocollection} } ) {
        if ( $pack{ctreeh}{$cgrp} ) {
          push @{ $menu[ $idx{custom} ]{children} }, pushFullNode( $cgrp, $pack{ctreeh}{$cgrp}, "na", "na", 0, undef, undef, undef, "C" );
        }
      }
    }
  }
  else {
    $idx{custom} = push @menu, pushmenub( "CUSTOM GROUPS", "empty_cgrps.html" );
  }
}

### HMC submenu
sub hmcs {
  print "{\"title\":\"HMC totals\",\"folder\":\"true\",\"children\":[\n";
  my $delim = '';
  for ( $pack{hmc} ) {
    print $delim . &txthref( @$_[0], @$_[1] );
    $delim = ",\n";
  }
  print "]}";
}

### single HMC Totals
sub hmcTotals {
  my ($hmc) = @_;
  if ( exists $pack{hmc}{$hmc} ) {
    push @{ $menu[ $idx{psrv} ]{children}[ $idx{hmc} ]{children} }, pushmenu( "Totals", $pack{hmc}{$hmc}{url} );
  }
}

### single vCenter Totals
sub vcTotals {
  my ($vc) = @_;
  if ( exists $pack{vtree}{vc}{$vc}{menu} ) {
    foreach ( @{ $pack{vtree}{vc}{$vc}{menu} } ) {
      push @{ $menu[ $idx{vmware} ]{children}[ $idx{vc} ]{children} }, pushmenu( @$_[0], @$_[1], @$_[0] . $vc );
    }
  }
}
### single cluster Totals
sub clTotals {
  my ( $vc, $cl ) = @_;
  if ( exists $pack{cluster}{$vc}{$cl} ) {
    foreach my $title ( keys %{ $pack{cluster}{$vc}{$cl} } ) {
      my $url   = $pack{cluster}{$vc}{$cl}{$title};
      my $cl_id = ( $url =~ /host=([^&]*)/ )[0];
      my $vc_id = ( $url =~ /server=([^&]*)/ )[0];

      # warn "$vc, $cl, $cl_id";
      push @{ $menu[ $idx{vmware} ]{children}[ $idx{vc} ]{children}[ $idx{cl} ]{children} }, pushFullNode( $title, $url, $cl_id, $vc_id, 1, "nope", "V", $cl );
    }
  }
}
### Tail menu section
sub tail {
  my $freeOrFull = ( $env{free} eq 1 ? "free" : "full" );
  push @menu, { "title" => "LPAR2RRD <span style='font-weight: normal'>($env{version} $freeOrFull)</span>", "folder" => "true", "children" => [] };
  my $delim = '';
  for ( @{ $pack{tail} } ) {
    if ( @$_[0] ne "Access Control" ) {
      if ( !$useacl || @$_[0] eq "Documentation" || @$_[0] eq "User management" ) {
        push @{ $menu[$#menu]{children} }, pushmenu( @$_[0], @$_[1] );
      }
    }
  }

  # push @{ $menu[$#menu]{children} }, pushmenu( "Host configuration", "/lpar2rrd-cgi/hosts.sh?cmd=form" );
  # push @{ $menu[$#menu]{children} }, pushmenu( "User management", "/lpar2rrd-cgi/users.sh?cmd=form" );

  # if ($useacl) {
  #    print $delim . &txthref( "Access Control", "/lpar2rrd-cgi/acl.sh" );
  #}
  #    print $delim . &txthref( "Custom Groups config", "/lpar2rrd-cgi/cgrps.sh" );
  if ($GUIDEBUG) {
    print $delim . &txthref( "Load debug content", "debug.txt" );
  }
}

### Single Server menu
# params: (hmc, srv)
sub serverMenu {
  my ( $h, $s, $c, $v, $vcwocl ) = @_;
  my @sharedPools;
  for ( @{ $pack{stree}{$s}->{$h} } ) {
    if ( defined $v ) {
      if ( defined $c ) {
        if ($vcwocl) {
          push @{ $menu[ $idx{vmware} ]{children}[ $idx{vc} ]{children}[ $idx{esxi} ]{children}[ $idx{csrv} ]{children} }, pushFullNode( @$_[0], @$_[1], $c, $s, 0, @$_[2], $pack{times}{$s}{type}, $h );
        }
        else {
          push @{ $menu[ $idx{vmware} ]{children}[ $idx{vc} ]{children}[ $idx{cl} ]{children}[ $idx{esxi} ]{children}[ $idx{csrv} ]{children} }, pushFullNode( @$_[0], @$_[1], $c, $s, 0, @$_[2], $pack{times}{$s}{type}, $h );
        }
      }
      else {
        push @{ $menu[ $idx{vmware} ]{children}[ $idx{esxi} ]{children}[ $idx{csrv} ]{children} }, pushFullNode( @$_[0], @$_[1], $h, $s, 0, @$_[2], $pack{times}{$s}{type}, $h );
      }
    }
    else {
      if ( $h eq "solaris" ) {
        push @{ $menu[ $idx{solaris} ]{children}[ $idx{csrv} ]{children} }, pushFullNode( @$_[0], @$_[1], $h, $s, 0, @$_[2], $pack{times}{$s}{type}, $h );
      }
      elsif ( $h eq "Hitachi" ) {
        push @{ $menu[ $idx{hitachi} ]{children}[ $idx{csrv} ]{children} }, pushFullNode( @$_[0], @$_[1], $h, $s, 0, @$_[2], $pack{times}{$s}{type}, $h );
      }
      elsif ( $pack{times}{$s}{type} eq "X" ) {
        push @{ $menu[ $idx{xen} ]{children}[ $idx{csrv} ]{children}[ $idx{xlabel} ]{children} }, pushFullNode( @$_[0], @$_[1], $h, $s, 0, @$_[2], $pack{times}{$s}{type}, $h );
      }
      elsif ( $pack{times}{$s}{type} eq "N" ) {
        push @{ $menu[ $idx{nutanix} ]{children}[ $idx{csrv} ]{children}[ $idx{xlabel} ]{children} }, pushFullNode( @$_[0], @$_[1], $h, $s, 0, @$_[2], $pack{times}{$s}{type}, $h );
      }
      elsif ( $pack{times}{$s}{type} eq "A" ) {
        push @{ $menu[ $idx{aws} ]{children}[ $idx{csrv} ]{children}[ $idx{xlabel} ]{children} }, pushFullNode( @$_[0], @$_[1], $h, $s, 0, @$_[2], $pack{times}{$s}{type}, $h );
      }
      elsif ( $pack{times}{$s}{type} eq "G" ) {
        push @{ $menu[ $idx{gcloud} ]{children}[ $idx{csrv} ]{children}[ $idx{xlabel} ]{children} }, pushFullNode( @$_[0], @$_[1], $h, $s, 0, @$_[2], $pack{times}{$s}{type}, $h );
      }
      elsif ( $pack{times}{$s}{type} eq "Z" ) {
        push @{ $menu[ $idx{azure} ]{children}[ $idx{csrv} ]{children}[ $idx{xlabel} ]{children} }, pushFullNode( @$_[0], @$_[1], $h, $s, 0, @$_[2], $pack{times}{$s}{type}, $h );
      }
      elsif ( $pack{times}{$s}{type} eq "K" ) {
        push @{ $menu[ $idx{kubernetes} ]{children}[ $idx{csrv} ]{children}[ $idx{xlabel} ]{children} }, pushFullNode( @$_[0], @$_[1], $h, $s, 0, @$_[2], $pack{times}{$s}{type}, $h );
      }
      elsif ( $pack{times}{$s}{type} eq "R" ) {
        push @{ $menu[ $idx{openshift} ]{children}[ $idx{csrv} ]{children}[ $idx{xlabel} ]{children} }, pushFullNode( @$_[0], @$_[1], $h, $s, 0, @$_[2], $pack{times}{$s}{type}, $h );
      }
      elsif ( $pack{times}{$s}{type} eq "E" ) {
        push @{ $menu[ $idx{cloudstack} ]{children}[ $idx{csrv} ]{children}[ $idx{xlabel} ]{children} }, pushFullNode( @$_[0], @$_[1], $h, $s, 0, @$_[2], $pack{times}{$s}{type}, $h );
      }
      elsif ( $pack{times}{$s}{type} eq "M" ) {
        push @{ $menu[ $idx{proxmox} ]{children}[ $idx{csrv} ]{children}[ $idx{xlabel} ]{children} }, pushFullNode( @$_[0], @$_[1], $h, $s, 0, @$_[2], $pack{times}{$s}{type}, $h );
      }
      elsif ( $pack{times}{$s}{type} eq "I" ) {
        push @{ $menu[ $idx{docker} ]{children}[ $idx{csrv} ]{children}[ $idx{xlabel} ]{children} }, pushFullNode( @$_[0], @$_[1], $h, $s, 0, @$_[2], $pack{times}{$s}{type}, $h );
      }
      elsif ( $pack{times}{$s}{type} eq "W" ) {
        push @{ $menu[ $idx{fusioncompute} ]{children}[ $idx{csrv} ]{children}[ $idx{xlabel} ]{children} }, pushFullNode( @$_[0], @$_[1], $h, $s, 0, @$_[2], $pack{times}{$s}{type}, $h );
      }
      elsif ( $pack{times}{$s}{type} eq "Q" ) {
        push @{ $menu[ $idx{odb} ]{children}[ $idx{csrv} ]{children}[ $idx{xlabel} ]{children} }, pushFullNode( @$_[0], @$_[1], $h, $s, 0, @$_[2], $pack{times}{$s}{type}, $h );
      }
      elsif ( $pack{times}{$s}{type} eq "D" ) {
        push @{ $menu[ $idx{sqlserver} ]{children}[ $idx{csrv} ]{children}[ $idx{xlabel} ]{children} }, pushFullNode( @$_[0], @$_[1], $h, $s, 0, @$_[2], $pack{times}{$s}{type}, $h );
      }
      elsif ( $pack{times}{$s}{type} eq "T" ) {
        push @{ $menu[ $idx{postgres} ]{children}[ $idx{csrv} ]{children}[ $idx{xlabel} ]{children} }, pushFullNode( @$_[0], @$_[1], $h, $s, 0, @$_[2], $pack{times}{$s}{type}, $h );
      }
      elsif ( $pack{times}{$s}{type} eq "F" ) {
        push @{ $menu[ $idx{db2} ]{children}[ $idx{csrv} ]{children}[ $idx{xlabel} ]{children} }, pushFullNode( @$_[0], @$_[1], $h, $s, 0, @$_[2], $pack{times}{$s}{type}, $h );
      }
      else {
        my $obj = "";
        if ( @$_[1] =~ "SharedPool" ) {
          $obj = "SP";
        }
        elsif ( @$_[2] eq "pool" ) {
          $obj = "P";
        }
        if ( !$useacl || $isAdmin || $acl->canShow( "POWER", "SERVER", $s ) || $acl->canShow( "POWER", "POOL", $s, @$_[2] ) ) {
          my $node = pushFullNode( @$_[0], @$_[1], $h, $s, 0, @$_[2], $pack{times}{$s}{type}, $h, $obj );
          if ( @$_[0] eq "VIEW" || @$_[0] eq "Historical reports" ) {
            $node->{extraClasses} = "noregroup";
          }
          if ( $obj ne "SP" ) {
            push @{ $menu[ $idx{psrv} ]{children}[ $idx{csrv} ]{children} }, $node;
          }
          else {
            my $poolname = ( split " : ", $node->{title} )[1];
            if ( !$poolname ) {
              $poolname = $node->{title};
            }
            $node->{title} = $poolname;
            push @sharedPools, $node;
          }
        }
      }
    }
  }
  if (@sharedPools) {
    my $spsubmenu = { title => "Shared CPU Pool", folder => \1, children => [] };
    foreach my $node (@sharedPools) {
      push @{ $spsubmenu->{children} }, $node;
    }
    push @{ $menu[ $idx{psrv} ]{children}[ $idx{csrv} ]{children} }, $spsubmenu;
  }

  # print $delim;
}

### Single Server menu
# params: (hmc, srv)
sub serverByHmc {
  my ( $h, $s, $c ) = @_;
  for ( @{ $pack{stree}{$s}->{$h} } ) {
    if ( defined $c ) {
      push @{ $menu[ $idx{psrv} ]{children}[ $idx{hmc} ]{children}[ $idx{csrv} ]{children} }, pushFullNode( @$_[0], @$_[1], $c, $s, 0, @$_[2], $pack{times}{$s}{type}, $h );
    }
    else {
      push @{ $menu[ $idx{psrv} ]{children}[ $idx{hmc} ]{children}[ $idx{csrv} ]{children} }, pushFullNode( @$_[0], @$_[1], $h, $s, 0, @$_[2], $pack{times}{$s}{type}, $h );
    }
  }
}

sub lparNames {
  my @unique = sort( do {
      my %seen;
      grep { !$seen{$_}++ } keys %{ $pack{lnames}{P} };
    }
  );
  print "[";
  if (@_) {
    @unique = grep( {/@_/i} @unique );
  }
  my $delim = '';
  for (@unique) {

    #		print Dumper $_;
    print $delim . "{\"value\":\"$_\"}";
    $delim = ",\n";
  }
  print "]";
}

sub genFleetTree {
  print "[";
  my $n1 = "";
  for my $srv ( sort keys %{ $pack{fleet} } ) {
    if ( !$pack{times}{$srv}{"active"} ) {
      next;
    }
    print $n1 . "{\"title\":\"$srv\",\"folder\":\"true\",\"children\":[\n";
    $n1 = ",\n";
    my $n2 = "";
    for my $type ( sort keys %{ $pack{fleet}{$srv}{subsys} } ) {
      print $n2 . "{\"title\":\"$type\",\"folder\":\"true\",\"children\":[";
      $n2 = ",\n";
      my $n3 = "";

      # my @uni = uniq( @{ $pack{fleet}{$srv}{$type} } );
      foreach my $name ( sort keys %{ $pack{fleet}{$srv}{subsys}{$type} } ) {
        print $n3 . "{\"title\":\"$name\"}";
        $n3 = ",";
      }    # L3 END
      print "]}";
    }    # L2 END
    print "]}";
  }
  print "]\n";
}

sub genFleet {
  print "{";
  my $n1 = "";
  for my $srv ( sort keys %{ $pack{fleet} } ) {
    if ( !$pack{times}{$srv}{"active"} || !$pack{times}{$srv}{type} || $pack{times}{$srv}{type} ne "P" ) {
      next;
    }
    print $n1 . "\"$srv\":{";
    $n1 = ",\n";
    my $n2 = "";
    for my $type ( sort keys %{ $pack{fleet}{$srv}{subsys} } ) {
      print $n2 . "\"$type\":[";
      $n2 = ",\n";
      my $n3 = "";

      # my @uni = uniq( @{ $pack{fleet}{$srv}{$type} } );

      # print Dumper \@uni;
      foreach my $name ( keys %{ $pack{fleet}{$srv}{subsys}{$type} } ) {
        print $n3 . "\"$name\"";
        $n3 = ",";
      }    # L3 END
      print "]";
    }    # L2 END
    print "}";
  }
  print "}\n";
}

sub genFleetAlrt {
  print "{";
  my $n1 = "";
  foreach my $srv ( sort keys %{ $pack{fleet} } ) {
    if ( !$pack{fleet}{$srv}{platform} ) {
      next;
    }
    if ( $pack{fleet}{$srv}{platform} eq "P" && ( !exists $pack{fleet}{$srv}{subsys}{LPAR} ) ) {
      next;
    }
    if ( $pack{fleet}{$srv}{platform} eq "V" && !exists $pack{fleet}{$srv}{subsys}{LPAR} ) {
      next;
    }
    print $n1 . "\"$srv\":{\"platform\":\"$pack{fleet}{$srv}{platform}\",\"subsys\":{";
    $n1 = ",\n";
    my $n2 = "";
    foreach my $subsys ( sort keys %{ $pack{fleet}{$srv}{subsys} } ) {
      print $n2 . "\"$subsys\":[";
      $n2 = ",\n";
      my $n3 = "";

      # my @uni = uniq( @{ $pack{fleet}{$srv}{$type} } );

      # print Dumper \@uni;
      foreach my $name ( sort keys %{ $pack{fleet}{$srv}{subsys}{$subsys} } ) {
        my $uuid    = "";
        my $cluster = "";

        if ( $pack{fleet}{$srv}{uuid}{$name} ) {
          $uuid = $pack{fleet}{$srv}{uuid}{$name};
        }
        if ( $pack{fleet}{$srv}{cluster}{$name} ) {
          $cluster = $pack{fleet}{$srv}{cluster}{$name};
        }
        print $n3 . "[\"$name\",\"$pack{fleet}{$srv}{subsys}{$subsys}{$name}{type}\",\"$uuid\",\"$cluster\"]";
        $n3 = ",";
      }    # L3 END
      print "]";
    }    # L2 END
    print "}}";
  }

  my $odbmenu = "$basedir/tmp/menu_oracledb.json";
  if ( -r "$basedir/debug/menu.txt" ) {
    $odbmenu = "$basedir/debug/menu_oracledb.json";
  }
  if ( -e $odbmenu && -f _ && -r _ ) {

    #print ',"Multitenant":{"platform":"Q","subsys":{"ODB":[["XE","C","",""]]}}';
    require Xorux_lib;
    my $odb_dir = "$inputdir/data/OracleDB";
    my ( $instance_names, $can_read, $ref );
    ( $can_read, $ref ) = Xorux_lib::read_json("$odb_dir/Totals/instance_names_total.json");
    if ($can_read) {
      $instance_names = $ref;
    }
    else {
      warn "Couldn't open $odb_dir/Totals/instance_names_total.json";
    }
    my $message = "";
    for my $server ( keys %{$instance_names} ) {
      $message .= $n1 . "\"$server\":\{\"platform\":\"Q\",\"subsys\":\{\"ODB\":\[";
      $n1 = ",\n";
      for my $ip ( keys %{ $instance_names->{$server} } ) {
        $message .= "\[\"$instance_names->{$server}->{$ip}\",\"Q\",\"\",\"\"\],";
      }
      $message = substr( $message, 0, -1 );
      $message .= "\]\}\}";
    }
    if ($can_read) {
      print $message;
    }
  }
  print "}\n";
}

sub genFleetReport {
  my %abbr = (
    P => "POWER",
    V => "VMWARE",
    U => "UNMANAGED"
  );
  my %subsystems = (
    CLUSTER          => "Cluster totals",
    RESPOOL          => "Resource pool",
    VM               => "Virtual machine",
    DATASTORE        => "Datastore",
    STORAGEDOMAIN    => "Storage Domain",
    ESXI             => "Host (ESXi)",
    HOST             => "Host",
    DISK             => "Disk",
    LDOM             => "LDOM",
    SERVERTOTALS     => "Server totals",
    STORAGETOTALS    => "Storage totals",
    VMTOTALS         => "VM totals",
    SERVER           => "Server",
    STORAGEPOOL      => "Storage pools",
    STORAGECONTAINER => "Storage Containers",
    VIRTUALDISK      => "Virtual disks",
    PHYSICALDISK     => "Physical disks"
  );
  my %fl;
  foreach my $srv ( sort keys %{ $pack{fleet} } ) {
    my $platform = $pack{fleet}{$srv}{platform};
    my $hmc;
    if ( $pack{stree}{$srv} ) {
      $hmc = ( keys %{ $pack{stree}{$srv} } )[0];
    }
    if ( !$platform || $platform ne "P" || ( $platform eq "P" && ( !$pack{times}{$srv}{"active"} || !$pack{times}{$srv}{type} ) ) ) {
      next;
    }
    $fl{POWER}{$srv}{subsys}{SERVER} = [];
    push @{ $fl{POWER}{$srv}{subsys}{SERVER} }, { hmc => $hmc, name => "Memory", value => "pool", type => "pool" };
    foreach my $subsys ( sort keys %{ $pack{fleet}{$srv}{subsys} } ) {
      $fl{POWER}{$srv}{subsys}{$subsys} = [];
      foreach my $name ( sort keys %{ $pack{fleet}{$srv}{subsys}{$subsys} } ) {
        my %item = ( name => $name );
        if ( $pack{fleet}{$srv}{subsys}{$subsys}{$name}{type} ) {
          $item{type} = $pack{fleet}{$srv}{subsys}{$subsys}{$name}{type};
        }
        if ( $pack{fleet}{$srv}{subsys}{$subsys}{$name}{value} ) {
          $item{value} = $pack{fleet}{$srv}{subsys}{$subsys}{$name}{value};
        }
        if ( $pack{fleet}{$srv}{uuid}{$name} ) {
          $item{uuid} = $pack{fleet}{$srv}{uuid}{$name};
        }
        if ( $pack{fleet}{$srv}{cluster}{$name} ) {
          $item{cluster} = $pack{fleet}{$srv}{cluster}{$name};
        }
        if ($hmc) {
          $item{hmc} = $hmc;
        }
        push @{ $fl{POWER}{$srv}{subsys}{$subsys} }, \%item;
      }    # L3 END
    }    # L2 END
  }
  foreach my $srv ( nsort keys %{ $pack{vtree}{vc} } ) {
    my $srvalias = $pack{vtree}{vc}{$srv}{alias};
    my %vcss;
    if ( $pack{vtree}{vc}{$srv}{cluster} ) {
      $vcss{CLUSTER} ||= 1;
      foreach my $cname ( nsort keys %{ $pack{vtree}{vc}{$srv}{cluster} } ) {
        my %item = ();
        ( my $cls = $cname ) =~ s/cluster_//;
        if ( $pack{vtree}{vc}{$srv}{cluster}{$cname}{host} ) {
          $vcss{ESXI} ||= 1;
          $item{ESXI} = ();
          foreach my $name ( nsort keys %{ $pack{vtree}{vc}{$srv}{cluster}{$cname}{host} } ) {
            push @{ $item{ESXI} }, { name => $name };
          }
        }
        if ( $pack{respool}{$srv}{$cname} ) {
          $vcss{RESPOOL} ||= 1;
          $item{RESPOOL} = ();
          foreach my $name ( nsort keys %{ $pack{respool}{$srv}{$cname} } ) {
            push @{ $item{RESPOOL} }, { name => $name };
          }
        }
        if ( $pack{lhmc}{$cname} ) {
          $vcss{VM} ||= 1;
          my @vms;
          foreach my $esxi ( keys %{ $pack{lhmc}{$cname} } ) {
            foreach my $name ( @{ $pack{lhmc}{$cname}{$esxi} } ) {
              push @vms, { name => @{$name}[0], uuid => @{$name}[2] };
            }
          }
          @vms = sort { ncmp( $a->{name}, $b->{name} ) } @vms;
          $item{VM} = \@vms;
        }
        $fl{VMWARE}{$srvalias}{inventory}{CLUSTER}{$cls} = \%item;
      }
    }
    if ( $pack{datastore}{$srv} ) {
      $vcss{DATASTORE} ||= 1;
      foreach my $dname ( nsort keys %{ $pack{datastore}{$srv} } ) {
        my %item = ();
        ( my $dc = $dname ) =~ s/datastore_//;
        if ( $pack{datastore}{$srv}{$dname} ) {
          $item{DATASTORE} = ();
          foreach my $name ( nsort keys %{ $pack{datastore}{$srv}{$dname} } ) {
            push @{ $item{DATASTORE} }, { name => $name };
          }
        }
        $fl{VMWARE}{$srvalias}{inventory}{DATACENTER}{$dc} = \%item;
      }    # l3 end
    }
    $vcss{subsys} = ();
    foreach my $ss (qw/CLUSTER RESPOOL VM DATASTORE ESXI/) {
      if ( $vcss{$ss} ) {
        push @{ $vcss{subsys} }, { value => $ss, text => $subsystems{$ss} };
      }
    }
    $fl{VMWARE}{$srvalias}{subsys} = $vcss{subsys};
  }

  # build oVirt structures
  my $omenu = "$basedir/data/oVirt/metadata.json";
  if ( -e $omenu && -f _ && -r _ ) {
    use OVirtDataWrapper;
    foreach my $datacenter_uuid ( @{ OVirtDataWrapper::get_uuids('datacenter') } ) {
      my %vcss;
      my $datacenter_label = OVirtDataWrapper::get_label( 'datacenter', $datacenter_uuid );
      my %item             = ();
      foreach my $cluster_uuid ( @{ OVirtDataWrapper::get_arch( $datacenter_uuid, 'datacenter', 'cluster' ) } ) {
        $vcss{CLUSTER} ||= 1;
        my $cluster_label = OVirtDataWrapper::get_label( 'cluster', $cluster_uuid );
        $item{CLUSTER}{$cluster_uuid}{label} = $cluster_label;
        foreach my $host_uuid ( @{ OVirtDataWrapper::get_arch( $cluster_uuid, 'cluster', 'host' ) } ) {
          $vcss{HOST} ||= 1;
          my $host_label = OVirtDataWrapper::get_label( 'host', $host_uuid );
          push @{ $item{CLUSTER}{$cluster_uuid}{HOST} }, { name => $host_label, uuid => $host_uuid };
        }
        foreach my $vm_uuid ( @{ OVirtDataWrapper::get_arch( $cluster_uuid, 'cluster', 'vm' ) } ) {
          $vcss{VM} ||= 1;
          my $vm_label = OVirtDataWrapper::get_label( 'vm', $vm_uuid );
          push @{ $item{CLUSTER}{$cluster_uuid}{VM} }, { name => $vm_label, uuid => $vm_uuid };
        }
      }
      foreach my $storage_domain_uuid ( @{ OVirtDataWrapper::get_arch( $datacenter_uuid, 'datacenter', 'storage_domain' ) } ) {
        $vcss{STORAGEDOMAIN} ||= 1;
        my $storage_domain_label = OVirtDataWrapper::get_label( 'storage_domain', $storage_domain_uuid );
        $item{STORAGEDOMAIN}{$storage_domain_uuid}{label} = $storage_domain_label;
        foreach my $disk_uuid ( @{ OVirtDataWrapper::get_arch( $storage_domain_uuid, 'storage_domain', 'disk' ) } ) {
          $vcss{DISK} ||= 1;
          my $disk_label = OVirtDataWrapper::get_label( 'disk', $disk_uuid );
          push @{ $item{STORAGEDOMAIN}{$storage_domain_uuid}{DISK} }, { name => $disk_label, uuid => $disk_uuid };
        }
      }
      $fl{OVIRT}{$datacenter_uuid}{inventory} = \%item;
      $vcss{subsys} = ();
      foreach my $ss (qw/CLUSTER RESPOOL VM STORAGEDOMAIN DISK HOST/) {
        if ( $vcss{$ss} ) {
          push @{ $vcss{subsys} }, { value => $ss, text => $subsystems{$ss} };
        }
      }
      $fl{OVIRT}{$datacenter_uuid}{label}  = $datacenter_label;
      $fl{OVIRT}{$datacenter_uuid}{subsys} = $vcss{subsys};
    }
  }
  foreach my $srv ( sort keys %{ $pack{soltree}{host} } ) {
    if ( $pack{soltree}{host}{$srv}{ldom} || $pack{soltree}{host}{$srv}{globzone} ) {
      my @zones;
      foreach my $zone ( keys %{ $pack{soltree}{host}{$srv}{zone} } ) {
        push @zones, $zone;
      }
      my $ldom = { name => $srv };
      if (@zones) {
        $ldom->{zones} = \@zones;
      }
      push @{ $fl{SOLARIS}{LDOM} }, $ldom;
    }
  }
  foreach my $domain ( sort keys %{ $pack{hyperv}{dom} } ) {
    my @domcontent;
    foreach my $srv ( sort keys %{ $pack{hyperv}{dom}{$domain}{server} } ) {
      my $srvcontent;
      foreach my $vm ( sort keys %{ $pack{hyperv}{dom}{$domain}{server}{$srv}{vm} } ) {
        push @{ $srvcontent->{$srv}{VM} }, $vm;
      }
      foreach my $drive ( sort keys %{ $pack{hyperv}{dom}{$domain}{server}{$srv}{drive}{item} } ) {
        push @{ $srvcontent->{$srv}{STORAGE} }, $drive;
      }
      push @domcontent, $srvcontent;
    }
    push @{ $fl{HYPERV}{DOMAIN}{$domain} }, @domcontent;
  }
  foreach my $cluster ( sort keys %{ $pack{hyperv}{cluster} } ) {
    my $clstrcontent;
    foreach my $vm ( sort keys %{ $pack{hyperv}{cluster}{$cluster}{vm} } ) {
      push @{$clstrcontent}, $vm;
    }
    $fl{HYPERV}{CLUSTER}{$cluster}{VM} = $clstrcontent;
  }

  # build Nutanix structures
  my $numenu = "$basedir/tmp/menu_nutanix.json";
  if ( -e $numenu && -f _ && -r _ ) {
    use NutanixDataWrapper;
    my %vcss;
    my %item  = ();
    my @clusters = @{ NutanixDataWrapper::get_items( { item_type => 'cluster' } ) };
    foreach my $cluster (@clusters) {
      my ( $cluster_uuid, $cluster_label ) = each %{$cluster};

      # get an array of hosts in the pool
      my @hosts = @{ NutanixDataWrapper::get_items( { item_type => 'host', parent_type => 'cluster', parent_uuid => $cluster_uuid } ) };

=pod
      # subsystems disabled for now, not implemented on backend
      foreach my $host ( @hosts) {
        $vcss{SERVER} ||= 1;
        my ($host_uuid, $host_label) = each %{$host};
        push @{ $item{SERVER} }, {name => $host_label, uuid => $host_uuid};
      }
      foreach my $vm ( @{ NutanixDataWrapper::get_items( {item_type => 'vm' , parent_type => 'cluster', parent_uuid => $cluster_uuid } ) } ) {
        $vcss{VM} ||= 1;
        my ($vm_uuid, $vm_label) = each %{$vm};
        push @{ $item{VM} }, {name => $vm_label, uuid => $vm_uuid};
      }
=cut

      $fl{NUTANIX}{$cluster_uuid}{label}     = $cluster_label;
      $fl{NUTANIX}{$cluster_uuid}{inventory} = \%item;
      $vcss{subsys}                       = ();
      foreach my $ss (qw/SERVERTOTALS STORAGETOTALS VMTOTALS/) {
        push @{ $vcss{subsys} }, { value => $ss, text => $subsystems{$ss} };
      }
      foreach my $ss (qw/SERVER VM STORAGEPOOL STORAGECONTAINER VIRTUALDISK PHYSICALDISK/) {
        if ( $vcss{$ss} ) {
          push @{ $vcss{subsys} }, { value => $ss, text => $subsystems{$ss} };
        }
      }
      $fl{NUTANIX}{$cluster_uuid}{subsys} = $vcss{subsys};
    }

    #foreach my $storage_domain_uuid ( @{ NutanixDataWrapper::get_arch( $datacenter_uuid, 'datacenter', 'storage_domain' ) } ) {
    #  $vcss{STORAGEDOMAIN} ||= 1;
    #  my $storage_domain_label = NutanixDataWrapper::get_label( 'storage_domain', $storage_domain_uuid );
    #  $item{STORAGEDOMAIN}{$storage_domain_uuid}{label} = $storage_domain_label;
    #  foreach my $disk_uuid ( @{ NutanixDataWrapper::get_arch( $storage_domain_uuid, 'storage_domain', 'disk' ) } ) {
    #    $vcss{DISK} ||= 1;
    #    my $disk_label  = NutanixDataWrapper::get_label( 'disk', $disk_uuid );
    #    push @{ $item{STORAGEDOMAIN}{$storage_domain_uuid}{DISK} }, {name => $disk_label, uuid => $disk_uuid};
    #  }
    #}
    #$fl{NUTANIX}{$datacenter_uuid}{inventory} = \%item;
    #$vcss{subsys} = ();
    #foreach my $ss ( qw/CLUSTER RESPOOL VM STORAGEDOMAIN DISK HOST/ ) {
    #  if ( $vcss{$ss} ) {
    #    push @{ $vcss{subsys} }, { value => $ss, text => $subsystems{$ss} };
    #  }
    #}
    #$fl{NUTANIX}{$datacenter_uuid}{label} = $datacenter_label;
    #$fl{NUTANIX}{$datacenter_uuid}{subsys} = $vcss{subsys};
  }

  print JSON->new->utf8(1)->pretty()->encode( \%fl );
}

sub tobeerased {
  my %fl;
  my $omenu = "$basedir/data/oVirt/metadata.json";
  if ( -e $omenu && -f _ && -r _ ) {
    open( CFG, $omenu );
    {
      local $/ = undef;    # required for re-read of encode_json pretty output
      my $rawcfg = <CFG>;
      if ($rawcfg) {
        my %config = %{ decode_json($rawcfg) };
        my %vcss;
        foreach my $dc ( sort keys %{ $config{architecture}{datacenter} } ) {
          my $dcname = $config{labels}{datacenter}{$dc};
          foreach my $cl (
            sort $config{architecture}{datacenter}{$dc}
            {cluster}
            )
          {
            $vcss{CLUSTER} ||= 1;
            my $clname = $config{labels}{cluster}{$cl};
            my %item   = ();
            $item{$clname} = ();
            if ( exists $config{architecture}{cluster}{$cl}{host} ) {
              $vcss{HOST} ||= 1;
              $item{$clname}{HOST} = ();
              foreach my $name ( sort @{ $config{architecture}{cluster}{$cl}{host} } ) {
                my $lname = $config{labels}{host}{$name};
                push @{ $item{$clname}{HOST} }, { name => $lname };
              }
            }
            if ( exists $config{architecture}{cluster}{$cl}{vm} ) {
              $vcss{VM} ||= 1;
              $item{$clname}{VM} = ();
              foreach my $name ( sort @{ $config{architecture}{cluster}{$cl}{vm} } ) {
                my $lname = $config{labels}{host}{$name};
                push @{ $item{$clname}{VM} }, { name => $lname, uuid => $name };
              }
            }
            $fl{OVIRT}{$dcname}{inventory}{CLUSTER} = \%item;
          }
        }

        # $fl{OVIRT} = \%config;
      }
    }
    close CFG;
  }
}

sub genFleetAll {
  print "{";
  my $n1 = "";
  for my $srv ( sort keys %{ $pack{lnames}{P} } ) {
    if ( !$pack{times}{$srv}{"active"} ) {
      next;
    }
    if ( !$pack{fleet}{$srv}{subsys}{LPAR} ) {
      next;
    }
    my @tkeys = keys %{ $pack{fleet}{$srv}{subsys}{LPAR} };
    if ( $pack{fleet}{$srv}{subsys}{LPAR}{ $tkeys[0] } =~ /^(M|S|L)$/ ) {
      next;
    }
    print $n1 . "\"$srv\":{";
    $n1 = ",\n";
    my $n2 = "";
    for my $type ( sort keys %{ $pack{fleet}{$srv}{subsys} } ) {
      print $n2 . "\"$type\":[";
      $n2 = ",\n";
      my $n3 = "";

      # print Dumper \@uni;
      foreach my $name ( keys %{ $pack{fleet}{$srv}{subsys}{$type} } ) {
        print $n3 . "\"$name\"";
        $n3 = ",";
      }    # L3 END
      print "]";
    }    # L2 END
    print "}";
  }
  foreach my $vckey ( keys %{ $pack{vtree}{vc} } ) {
    my $vc = $pack{vtree}{vc}{$vckey};

    # print Dumper $vc;
    my $vcalias = $vc->{alias};
    print $n1 . "\"$vcalias\":{";
    $n1 = ",\n";
    my @vms;
    my @hosts;

    #foreach my $cluster ( keys %{ $vc->{cluster} } ) {
    #  push @hosts, keys %{ $vc->{cluster}{$cluster}{host} };
    #  push @vms, keys %{ $vc->{cluster}{$cluster}{vms}{items} };
    #}
    sub scan_folders {
      my $node_ref = shift;
      my $vms      = shift;
      if ( $node_ref->{items} ) {
        push @$vms, keys %{ $node_ref->{items} };
      }
      if ( $node_ref->{folders} ) {
        foreach my $folder ( values %{ $node_ref->{folders} } ) {
          scan_folders( $folder, $vms );
        }
      }
    }
    foreach my $cluster ( values %{ $vc->{cluster} } ) {

      # print Dumper $cluster;
      if ( $cluster->{host} ) {
        push @hosts, keys %{ $cluster->{host} };
      }
      if ( $cluster->{vms} ) {
        scan_folders( $cluster->{vms}, \@vms );
      }
    }
    my $n2 = "";
    if (@hosts) {
      print $n2 . "\"ESXI\":[";
      $n2 = ",\n";
      my $n3  = "";
      my @uni = uniq(@hosts);

      # print Dumper \@uni;
      foreach my $name ( nsort @uni ) {
        print $n3 . "\"$name\"";
        $n3 = ",";
      }    # L3 END
      print "]";
    }
    if (@vms) {
      print $n2 . "\"VM\":[";
      $n2 = ",\n";
      my $n3  = "";
      my @uni = uniq(@vms);

      # print Dumper \@uni;
      foreach my $name ( nsort @uni ) {
        print $n3 . "\"$name\"";
        $n3 = ",";
      }    # L3 END
      print "]";
    }
    print "}";
  }
  if ( $pack{lhmc}{no_hmc}{Linux} ) {
    print $n1 . "\"Linux\":{";
    $n1 = ",\n";
    print "\"LINUX\":[";
    my $n3 = "";

    # print Dumper \@uni;
    foreach my $name ( @{ $pack{lhmc}{no_hmc}{Linux} } ) {
      print $n3 . "\"@$name[0]\"";
      $n3 = ",";
    }    # L3 END
    print "]";
    print "}";
  }
  if ( $pack{ovirt} && $acl->canShow("OVIRT") ) {
    use OVirtDataWrapper;
    foreach my $datacenter_uuid ( @{ OVirtDataWrapper::get_uuids('datacenter') } ) {
      foreach my $cluster_uuid ( @{ OVirtDataWrapper::get_arch( $datacenter_uuid, 'datacenter', 'cluster' ) } ) {
        my $cluster_label = OVirtDataWrapper::get_label( 'cluster', $cluster_uuid );
        print $n1 . "\"$cluster_label\":{";
        $n1 = ",\n";
        print "\"OVIRTVM\":[";
        my $n3 = "";
        foreach my $vm_uuid ( @{ OVirtDataWrapper::get_arch( $cluster_uuid, 'cluster', 'vm' ) } ) {
          my $vm_label = OVirtDataWrapper::get_label( 'vm', $vm_uuid );
          print $n3 . "\"$vm_label\"";
          $n3 = ",";
        }
        print "]";
        print "}";
      }
    }
  }
  if ( $pack{xen} && $acl->canShow("XEN") ) {
    for my $srv ( sort @{ $pack{xen}{children} } ) {
      if ( $srv->{children} ) {
        print $n1 . "\"$srv->{title}\":{";
        $n1 = ",\n";
        print "\"XENVM\":[";
        my $n3 = "";
        foreach my $child ( @{ $srv->{children} } ) {

          # print Dumper \@uni;
          if ( $child->{title} && $child->{title} eq "VM" ) {
            foreach my $name ( @{ $child->{children} } ) {
              print $n3 . "\"$name->{title}\"";
              $n3 = ",";
            }    # L3 END
          }
        }
        print "]";
        print "}";
      }
    }
  }
  if ( $pack{nutanix} && $acl->canShow("NUTANIX") ) {
    for my $srv ( sort @{ $pack{nutanix}{children} } ) {
      if ( $srv->{children} ) {
        print $n1 . "\"$srv->{title}\":{";
        $n1 = ",\n";
        print "\"NUTANIXVM\":[";
        my $n3 = "";
        foreach my $child ( @{ $srv->{children} } ) {

          # print Dumper \@uni;
          if ( $child->{title} && $child->{title} eq "VM" ) {
            foreach my $name ( @{ $child->{children} } ) {
              print $n3 . "\"$name->{title}\"";
              $n3 = ",";
            }    # L3 END
          }
        }
        print "]";
        print "}";
      }
    }
  }
  if ( $pack{proxmox} && $acl->canShow("PROXMOX") ) {
    for my $srv ( sort @{ $pack{proxmox}{children} } ) {
      if ( $srv->{children} ) {
        print $n1 . "\"$srv->{title}\":{";
        $n1 = ",\n";
        print "\"PROXMOXVM\":[";
        my $n3 = "";
        foreach my $child ( @{ $srv->{children} } ) {

          # print Dumper \@uni;
          if ( $child->{title} && $child->{title} eq "VM" ) {
            foreach my $name ( @{ $child->{children} } ) {
              print $n3 . "\"$name->{title}\"";
              $n3 = ",";
            }    # L3 END
          }
        }
        print "]";
        print "}";
      }
    }
  }
  if ( $pack{openshift} && $acl->canShow("OPENSHIFT") ) {
    for my $srv ( sort @{ $pack{openshift}{children} } ) {
      if ( $srv->{children} ) {
        print $n1 . "\"$srv->{title}\":{";
        $n1 = ",\n";
        print "\"OPENSHIFTNODE\":[";
        my $n3 = "";
        foreach my $child ( @{ $srv->{children} } ) {

          # print Dumper \@uni;
          if ( $child->{title} && $child->{title} eq "Nodes" ) {
            foreach my $name ( @{ $child->{children} } ) {
              print $n3 . "\"$name->{title}\"";
              $n3 = ",";
            }    # L3 END
          }
        }
        print "],";
	print "\"OPENSHIFTPROJECT\":[";
        $n3 = "";
        foreach my $child ( @{ $srv->{children} } ) {

          # print Dumper \@uni;
          if ( $child->{title} && $child->{title} eq "Projects" ) {
            foreach my $name ( @{ $child->{children} } ) {
              print $n3 . "\"$name->{title}\"";
              $n3 = ",";
            }    # L3 END
          }
        }
        print "]";
        print "}";
      }
    }
  }
  if ( $pack{kubernetes} && $acl->canShow("KUBERNETES") ) {
    for my $srv ( sort @{ $pack{kubernetes}{children} } ) {
      if ( $srv->{children} ) {
        print $n1 . "\"$srv->{title}\":{";
        $n1 = ",\n";
        print "\"KUBERNETESNODE\":[";
        my $n3 = "";
        foreach my $child ( @{ $srv->{children} } ) {

          # print Dumper \@uni;
          if ( $child->{title} && $child->{title} eq "Nodes" ) {
            foreach my $name ( @{ $child->{children} } ) {
              print $n3 . "\"$name->{title}\"";
              $n3 = ",";
            }    # L3 END
          }
        }
        print "],";
	print "\"KUBERNETESNAMESPACE\":[";
        $n3 = "";
        foreach my $child ( @{ $srv->{children} } ) {

          # print Dumper \@uni;
          if ( $child->{title} && $child->{title} eq "Namespaces" ) {
            foreach my $name ( @{ $child->{children} } ) {
              print $n3 . "\"$name->{title}\"";
              $n3 = ",";
            }    # L3 END
          }
        }
	print "]";

        print "}";
      }
    }
  }
  if ( $pack{fusioncompute} && $acl->canShow("FUSIONCOMPUTE") ) {
    for my $srv ( sort @{ $pack{fusioncompute}{children} } ) {
      if ( $srv->{children} ) {
        for my $site_child ( @{ $srv->{children} } ) {
          if ( $site_child->{title} eq "Cluster" ) {
            for my $cluster ( @{ $site_child->{children} } ) {
              print $n1 . "\"$cluster->{title}\":{";
              $n1 = ",\n";
              print "\"FUSIONCOMPUTEVM\":[";
              my $n3 = "";
              foreach my $child ( @{ $cluster->{children} } ) {

                # print Dumper \@uni;
                if ( $child->{title} && $child->{title} eq "VM" ) {
                  foreach my $name ( @{ $child->{children} } ) {
                    print $n3 . "\"$name->{title}\"";
                    $n3 = ",";
                  }    # L3 END
                }
              }
              print "]";
              print "}";
            }
          }
        }
      }
    }
  }
  if ( $pack{soltree} && $acl->canShow("SOLARIS") ) {
    for my $srv ( sort keys %{ $pack{soltree}{host} } ) {
      if ( $pack{soltree}{host}{$srv}{zone} ) {
        if ( exists $pack{soltree}{host}{$srv}{parent} ) {
          my $parent = $pack{soltree}{host}{$srv}{parent};
          print $n1 . "\"$parent:$srv\":{";
        }
        else {
          print $n1 . "\"$srv\":{";
        }
        $n1 = ",\n";
        my $n2 = "";
        if ( $pack{soltree}{host}{$srv}{zone}{total} ) {
          print "\"SOLARISLDOM\":[\"total\"]";
          $n2 = ",\n";
        }
        print $n2 . "\"SOLARISZONE\":[";
        my $n3 = "";
        foreach my $zone ( sort keys %{ $pack{soltree}{host}{$srv}{zone} } ) {
          if ( $zone ne "global" && $zone ne "total" && $zone ne "system" ) {
            print $n3 . "\"$zone\"";
            $n3 = ",";
          }
        }
        print "]";
        print "}";
      }
    }
  }
  if ( $pack{hyperv} && $acl->canShow("HYPERV") ) {
    for my $dom ( sort keys %{ $pack{hyperv}{dom} } ) {
      for my $srv ( sort keys %{ $pack{hyperv}{dom}{$dom}{server} } ) {
        if ( $pack{hyperv}{dom}{$dom}{server}{$srv}{vm} ) {
          print $n1 . "\"$srv\":{";
          $n1 = ",\n";
          my $n2 = "";
          print $n2 . "\"HYPERVM\":[";
          my $n3 = "";
          foreach my $vm ( sort keys %{ $pack{hyperv}{dom}{$dom}{server}{$srv}{vm} } ) {
            print $n3 . "\"$vm\"";
            $n3 = ",";
          }
          print "]";
          print "}";
        }
      }
    }
    for my $clstr ( sort keys %{ $pack{hyperv}{cluster} } ) {
      if ( $pack{hyperv}{cluster}{$clstr}{vm} ) {
        print $n1 . "\"$clstr\":{";
        $n1 = ",\n";
        my $n2 = "";
        print $n2 . "\"HYPERVM\":[";
        my $n3 = "";
        foreach my $vm ( sort keys %{ $pack{hyperv}{cluster}{$clstr}{vm} } ) {
          print $n3 . "\"$vm\"";
          $n3 = ",";
        }
        print "]";
        print "}";
      }
    }
  }
  if ( $pack{orvm} && $acl->canShow("ORACLEVM") ) {
    for my $cluster ( sort @{ $pack{orvm}{children} } ) {
      if ( $cluster->{children} ) {
        for my $srv ( sort @{ $cluster->{children} } ) {
          if ( $srv->{children} ) {
            print $n1 . "\"$srv->{title}\":{";
            $n1 = ",\n";
            print "\"ORVM\":[";
            my $n3 = "";
            foreach my $child ( @{ $srv->{children} } ) {

              # print Dumper \@uni;
              if ( $child->{title} && $child->{title} eq "VM" ) {
                foreach my $name ( @{ $child->{children} } ) {
                  print $n3 . "\"$name->{title}\"";
                  $n3 = ",";
                }    # L3 END
              }
            }
            print "]";
            print "}";
          }
        }
      }
    }
  }
  if ( $pack{odb} && $acl->canShow("ORACLEDB") ) {
    require Xorux_lib;
    my $odb_dir = "$inputdir/data/OracleDB";
    my ( $instance_names, $can_read, $ref );
    ( $can_read, $ref ) = Xorux_lib::read_json("$odb_dir/Totals/instance_names_total.json");
    if ($can_read) {
      $instance_names = $ref;
    }
    else {
      warn "Couldn't open $odb_dir/Totals/instance_names_total.json";
    }
    my $message = "";
    for my $server ( keys %{$instance_names} ) {
      $message .= $n1 . "\"$server\":{\"ODB\":\[";
      $n1 = ",\n";
      for my $ip ( keys %{ $instance_names->{$server} } ) {
        $message .= "\"$instance_names->{$server}->{$ip}\",";
      }
      $message = substr( $message, 0, -1 );
      $message .= "\]\}";
    }
    if ($can_read) {
      print $message;
    }
  }
  print "}\n";
}

sub genCustGrps {
  my %cgrps = CustomGroups::getGrp();
  my @cgtree;
  for my $cgrp ( nsort keys %cgrps ) {
    my $hcg    = { title => $cgrp, folder => \1, cgtype => $cgrps{$cgrp}{'type'}, loaded => \1, children => [] };
    my $onList = $acl->canShow( undef, "CUSTOM", $cgrp );
    if ( $useacl && !$isAdmin && !$isReadonly && !$onList ) {
      next;
    }
    if ( $cgrps{$cgrp}{'collection'} ) {
      $hcg->{collection} = $cgrps{$cgrp}{'collection'};
    }
    for my $src ( nsort keys %{ $cgrps{$cgrp}{'children'} } ) {
      my $hsrc = { title => $src, folder => \1, children => [] };
      if ( $cgrps{$cgrp}{'type'} eq "ODB" ) {
        $hsrc->{title} = "OracleDB";
      }
      for my $name ( @{ $cgrps{$cgrp}{'children'}{$src} } ) {
        push @{ $hsrc->{children} }, { title => $name };
      }
      push @{ $hcg->{children} }, $hsrc;
    }

    push @cgtree, $hcg;
  }
  print JSON->new->pretty(1)->utf8(1)->encode( \@cgtree );
}

sub genCustGrpsXormon {

  #if ( !$acl->{useracl}->{grantAll} ) {
  my %cgrps = CustomGroups::getGrp();
  my @cgtree;
  for my $cgrp ( sort keys %cgrps ) {
    my $hcg     = { title   => $cgrp, folder => \1, cgtype => $cgrps{$cgrp}{'type'}, loaded => \1, children => [] };
    my $aclitem = { hw_type => 'CUSTOM GROUPS', item_id => $cgrp, match => 'is_granted' };

    #print "{ hw_type => 'CUSTOM GROUPS', item_id => $cgrp, match => 'is_granted' }";
    if ( !$acl->isGranted($aclitem) ) {
      next;
    }
    if ( $cgrps{$cgrp}{'collection'} ) {
      $hcg->{collection} = $cgrps{$cgrp}{'collection'};
    }
    for my $src ( sort keys %{ $cgrps{$cgrp}{'children'} } ) {
      my $hsrc = { title => $src, folder => \1, children => [] };
      for my $name ( @{ $cgrps{$cgrp}{'children'}{$src} } ) {
        push @{ $hsrc->{children} }, { title => $name };
      }
      push @{ $hcg->{children} }, $hsrc;
    }
    push @cgtree, $hcg;
  }
  print JSON->new->pretty(1)->utf8(1)->encode( \@cgtree );
}

sub genHistRepSrcVmware {
  my @srclist;
  if ( $ENV{HTTP_XORUX_APP} && $ENV{HTTP_XORUX_APP} eq "Xormon" ) {
    my $vclist = SQLiteDataWrapper::getSubsysItems( { hw_type => 'VMWARE', subsys => 'VCENTER' } );
    for my $vc (@$vclist) {
      my $vchost  = get_vcenter_hostname_from_id( $vc->{item_id} );
      my $aclitem = { hw_type => 'VMWARE', item_id => $vc->{item_id}, match => 'granted' };
      if ( $acl->isGranted($aclitem) ) {
        push @srclist, { vcenter => $vchost, alias => $vc->{label} };
      }
    }
  }
  else {
    readMenu();
    if ( $pack{vtree} && $pack{vtree}{vc} ) {
      my $onList = $acl->canShow("VMWARE");
      if ( !$useacl || $isAdmin || $isReadonly || $onList ) {
        for my $vc ( sort keys %{ $pack{vtree}{vc} } ) {
          if ( $vc eq "" ) {
            next;
          }
          my $vcAlias = $pack{vtree}{vc}{$vc}{alias} ||= $vc;
          push @srclist, { vcenter => $vc, alias => $vcAlias };
        }
      }
    }
  }
  print JSON->new->pretty(1)->utf8(1)->encode( \@srclist );
}

sub overviewSources {

  # power only
  my $sources = {};
  if ( $pack{lpartree} ) {
    my @srvarr;
    my @lpararr;
    foreach my $srv ( nsort keys %{ $pack{lpartree} } ) {
      push @srvarr, { name => $srv, srctype => "server" };
      foreach my $lpar ( nsort keys %{ $pack{lpartree}{$srv} } ) {
        push @lpararr, { name => $lpar, srctype => "lpar", server => $srv };
      }
    }
    if (@srvarr) {
      push @{ $sources->{groups} }, { name => "SERVERS", members => \@srvarr };
    }
    if (@lpararr) {
      push @{ $sources->{groups} }, { name => "LPARS", members => \@lpararr };
    }
  }
  print JSON->new->utf8(1)->pretty()->encode($sources);

=pod
  my @excludes = qw/ECS HCP STORAGEGRID VDC SITE/;
  my $storages;
  $storages->{groups} = ();
  if ( $pack{storage_group} ) {
    foreach my $sgroup ( sort keys %{ $pack{storage_group}{bygroup} } ) {
      my @sgrouparr;
      foreach my $st ( sort keys %{ $pack{storage_group}{bygroup}{$sgroup} } ) {
        if ( exists $types{$st} ) {
          for my $storage ( sort keys %{ $pack{storage_group}{bygroup}{$sgroup} } ) {
            if ( exists $sstree{$storage} || exists $pack{lan}{switch}{$storage} ) {
              next;
            }
            if ( ! ACL::canShow( "S", "", $storage  ) ) {
              next;
            }
            if ( exists $types{$storage} ) {
              my $hwtype = getType( $storage );
              if ( ! grep { $_ eq $hwtype } @excludes ) {
                push @sgrouparr, { name => $storage, hwtype => $hwtype };
              }
            }
          }
          last;
        }
      }
      if (@sgrouparr) {
        push @{ $storages->{groups} }, { name => $sgroup, members => \@sgrouparr };
      }
    }
  }
  for my $storage ( sort keys $pack{fleet} ) {
    if ( ! ACL::canShow( "S", "", $storage  ) ) {
      next;
    }
    if (! $storages->{nogroup} ) {
      $storages->{nogroup} = ();
    }
    my $hwtype = getType( $storage );
    if ( ! grep { $_ eq $hwtype } @excludes ) {
      push @{ $storages->{nogroup} }, { name => $storage, hwtype => $hwtype };
    }
  } ## end for my $hmc ( sort keys...)
  print JSON->new->utf8(1)->pretty()->encode( $storages );
=cut

}

sub overviewSourcesXormon {
  my $sources = {};
  my @srvarr;
  my @lpararr;
  my $srvlist = SQLiteDataWrapper::getSubsysItems( { hw_type => 'POWER', subsys => 'SERVER' } );
  for my $srv (@$srvlist) {
    my $aclitem = { hw_type => 'POWER', item_id => $srv->{item_id}, match => 'granted' };
    if ( $acl->isGranted($aclitem) ) {
      push @srvarr, { name => $srv->{label}, srctype => "server" };
    }
  }
  my $lparlist = SQLiteDataWrapper::getSubsysItems( { hw_type => 'POWER', subsys => 'VM' } );
  for my $lpar (@$lparlist) {
    my $aclitem = { hw_type => 'POWER', item_id => $lpar->{item_id}, match => 'granted' };
    if ( $acl->isGranted($aclitem) ) {
      push @lpararr, { name => $lpar->{label}, srctype => "lpar" };
    }
  }
  if (@srvarr) {
    push @{ $sources->{groups} }, { name => "SERVERS", members => \@srvarr };
  }
  if (@lpararr) {
    push @{ $sources->{groups} }, { name => "LPARS", members => \@lpararr };
  }
  print JSON->new->utf8(1)->pretty()->encode($sources);
}

sub genAlertTree {
  print "[";
  my $n1     = "";
  my %alerts = Alerting::getAlerts();

  #print Dumper \%alerts;
  foreach my $srv ( sort keys %alerts ) {
    if ( $srv eq "" ) {
      print $n1 . "{\"title\":\"IBM Power - all servers\",\"folder\":\"true\",\"children\":[\n";
    }
    else {
      print $n1 . "{\"title\":\"$srv\",\"folder\":\"true\",\"children\":[\n";
    }
    $n1 = "\n,";
    my $n2 = "";
    foreach my $subsys ( sort keys %{ $alerts{$srv} } ) {
      foreach my $name ( sort keys %{ $alerts{$srv}{$subsys} } ) {
        my $type = "";
        if ( $subsys eq "LPAR" ) {
          if ( $pack{fleet}{$srv}{subsys}{$subsys}{$name} ) {
            $type = $pack{fleet}{$srv}{subsys}{$subsys}{$name}{type};
          }
          else {
            $type = findObjType( undef, $subsys, $name );
          }
        }
        if ( $subsys eq "LPAR" && !$name ) {
          print $n2 . "{\"title\":\"--- ALL LPARS ---\",\"subsys\":\"$subsys\",\"folder\":\"true\",\"children\":[\n";
          $type = "L";
        }
        else {
          print $n2 . "{\"title\":" . JSON->new->allow_nonref->encode($name) . ",\"subsys\":\"$subsys\",\"folder\":\"true\",\"children\":[\n";
        }
        $n2 = "\n,";
        my $n3      = "";
        my $ruleidx = 1;
        foreach my $metric ( %{ $alerts{$srv}{$subsys}{$name} } ) {
          foreach my $vals ( @{ $alerts{$srv}{$subsys}{$name}{$metric} } ) {
            my $percent = "false";
            if ( $metric eq "OSCPU" ) {
              $percent = "true";
            }
            if ( $metric eq "CPU" && $vals->{limit} =~ /%/ ) {
              $percent = "true";
              $vals->{limit} =~ s/%//;
            }

            # print $vals->{limit};
            # $my ( $limit, $peak, $repeat, $exclude, $mailgrp ) = (%{\$val{limit}, \$val{limit}, \$val{limit}, \$val{limit}, \$val{limit});
            #print $n3 . "{\"title\":\"Rule #$ruleidx\",\"metrics\":\"$metric\",\"limit\":\"$vals->{limit}\",\"peak\":\"$vals->{peak}\",\"repeat\":\"$vals->{repeat}\",\"exclude\":\"$vals->{exclude}\",\"mailgrp\":\"$vals->{mailgrp}\"}";
            my $fake;
            my $cluster;
            if ( $vals->{uuid} ) {
              if ( $type eq "M" ) {
                $fake    = "Linux";
                $cluster = $srv;
              }
              elsif ( $type eq "S" ) {
                $fake = "Solaris";
              }
            }
            if ( $srv eq "OracleDB" and $name eq "DB" ) {
              $type = "Q";
            }
            no warnings 'uninitialized';
            print $n3 . "{\"title\":\"\",\"metric\":\"$metric\",\"limit\":\"$vals->{limit}\",\"percent\":$percent,\"peak\":\"$vals->{peak}\",\"repeat\":\"$vals->{repeat}\",\"exclude\":\"$vals->{exclude}\",\"mailgrp\":\"$vals->{mailgrp}\",\"hwtype\":\"$type\",\"uuid\":\"$vals->{uuid}\",\"fakeserver\":\"$fake\",\"cluster\":\"$cluster\",\"user\":\"$vals->{user}\",\"instance\":
\"$subsys\"}";
            $n3 = "\n,";
            $ruleidx++;
          }
        }
        print "]}\n";
      }
    }
    print "]}\n";
  }
  print "]\n";
}

sub overview_vmware_clusters {
  my @clstr_arrray;

  if ( $ENV{HTTP_XORUX_APP} && $ENV{HTTP_XORUX_APP} eq "Xormon" ) {
    my $sources = {};
    my @srvarr;
    my @lpararr;
    my $clist = SQLiteDataWrapper::getSubsysItems( { hw_type => 'VMWARE', subsys => 'CLUSTER' } );
    for my $cluster (@$clist) {
      my $aclitem = {
        hw_type => 'VMWARE',
        item_id => $cluster->{item_id},
        match   => 'granted'
      };
      if ( $acl->isGranted($aclitem) ) {
        my $parents = SQLiteDataWrapper::getItemParents( { item_id => $cluster->{item_id} } );
        my $vc_label;
        foreach my $vc ( values %{ $parents->{VCENTER} } ) {
          $vc_label = $vc->{label};
          last;
        }
        ( my $cls = $cluster->{label} ) =~ s/cluster_//;

        #print Dumper $vc;
        push @clstr_arrray, { name => $cls, vcenter => $vc_label, srctype => "vcluster" };
      }
    }
  }
  else {
    readMenu();
    if ( $pack{vtree} ) {
      foreach my $vc ( values %{ $pack{vtree}{vc} } ) {
        foreach my $cluster ( keys %{ $vc->{cluster} } ) {
          ( my $cls = $cluster ) =~ s/cluster_//;
          push @clstr_arrray, { name => $cls, vcenter => $vc->{alias}, srctype => "vcluster" };
        }
      }
    }
  }
  print JSON->new->utf8(1)->pretty()->encode( \@clstr_arrray );
}

sub genAlertGroupTree {
  print "[";
  my $n1 = "";

  foreach my $grp ( Alerting::getDefinedGroups() ) {
    print $n1 . "{\"title\":\"$grp\",\"folder\":\"true\",\"children\":[\n";
    $n1 = "\n,";
    my $n2 = "";

    # my @members = Alerting::getGroupMembers($grp);
    # print Dumper @members;
    foreach ( @{ Alerting::getGroupMembers($grp) } ) {

      # my $user = Alerting::getUserDetails($grp, $_);
      print $n2 . "{\"title\":\"$_\"}";
      $n2 = "\n,";
    }
    print "]}\n";
  }
  print "]\n";
}

sub getAlertConfig {
  print "[";
  my $n1  = "";
  my %cfg = Alerting::getConfig();

  # print Dumper %cfg;
  while ( my ( $key, $val ) = each %cfg ) {
    print $n1 . "{\"$key\":\"$val\"}";
    $n1 = "\n,";
  }
  print "]\n";
}

sub getMetrics {
  my $cfgdir = "$basedir/etc";
  my $rawcfg;
  if ( !open( CFG, "$cfgdir/metrics.json" ) ) {
    die "Cannot open file: $!\n";
  }
  else {
    local $/ = undef;    # required for re-read of encode_json pretty output
    $rawcfg = <CFG>;
    close CFG;
    print $rawcfg;
  }
}

sub getAlrtSubmetrics {
  my $tbs_total = "$basedir/data/OracleDB/Totals/tablespaces_total.json";
  my $rawcfg;
  if ( !open( CFG, $tbs_total ) ) {
    die "Cannot open file: $!\n";
  }
  else {
    local $/ = undef;    # required for re-read of encode_json pretty output
    $rawcfg = <CFG>;
    close CFG;
    print $rawcfg;
  }
}

sub about {

  my %about;

  $about{RRDp_version}    = 'n/a';
  $about{RRDs_version}    = 'n/a';
  $about{rrdtool_version} = 'n/a';
  $about{perl_version}    = 'n/a';
  $about{os_info}         = 'n/a';
  $about{tool_version}    = "$version";
  $about{edition}         = "n/a";
  $about{sqlite_version}  = "n/a";

  eval {
    use RRDp;
    $about{RRDp_version} = "$RRDp::VERSION";
  };

  #eval {
  #use RRDs;
  #$about{RRDs_version} = "$RRDs::VERSION";
  #};

  my $rrdtoolv = $ENV{RRDTOOL};
  $_ = `$rrdtoolv`;

  if (/^RRDtool ([1-9]*\.[0-9]*(\.[0-9]*)?)/) {
    $about{rrdtool_version} = $1;
  }

  $about{perl_version} = sprintf "%vd", $^V;

  if ( $ENV{XORMON} ) {
    require SQLiteDataWrapper;
    $about{sqlite_version} = SQLiteDataWrapper::getSqliteVersion();
  }

  $_ = `uname`;
  chomp;
  $about{os_info} = $_;
  $about{edition} = "free";
  if ( !$free ) {
    $about{edition} = "Enterprise";
    my $technology = getTechnologies();
    if ( $technology->{platforms} ) {
      $about{edition} .= " (" . join( ", ", @{ $technology->{platforms} } ) . ")";
    }
  }
  if ( -r "$basedir/tmp/total-vm-count.json" ) {
    open( CFG, "$basedir/tmp/total-vm-count.json" );
    {
      local $/ = undef;    # required for re-read of encode_json pretty output
      my $rawcfg = <CFG>;
      if ($rawcfg) {
        $about{vmcount} = decode_json($rawcfg);
      }
    }
    close CFG;
  }

  # my %about = (rrdp_version => "$rrdp_version", rrds_version => "$rrds_version", rrdtool_version => "$rrdtool_version");
  print JSON->new->utf8(0)->encode( \%about );
}

sub getTechnologies {
  my @technology;
  my @techshorts;
  if ( -f "$basedir/html/.p" ) {
    push @technology, "IBM Power Systems";
    push @techshorts, "p";
  }
  if ( -f "$basedir/html/.v" ) {
    push @technology, "VMware";
    push @techshorts, "v";
  }
  if ( -f "$basedir/html/.s" ) {
    push @technology, "Solaris";
    push @techshorts, "s";
  }
  if ( -f "$basedir/html/.x" ) {
    push @technology, "XenServer";
    push @techshorts, "x";
  }
  if ( -f "$basedir/html/.o" ) {
    push @technology, "oVirt / RHV";
    push @techshorts, "o";
  }
  if ( -f "$basedir/html/.h" ) {
    push @technology, "HyperV";
    push @techshorts, "h";
  }
  if ( -f "$basedir/html/.m" ) {
    push @technology, "OracleVM";
    push @techshorts, "m";
  }
  if ( -f "$basedir/html/.b" ) {
    push @technology, "OracleDB";
    push @techshorts, "b";
  }
  if ( -f "$basedir/html/.l" ) {
    push @technology, "Linux";
    push @techshorts, "l";
  }
  if ( -f "$basedir/html/.n" ) {
    push @technology, "Nutanix";
    push @techshorts, "n";
  }
  if ( -f "$basedir/html/.f" ) {
    push @technology, "FusionCompute";
    push @techshorts, "f";
  }
  if ( -f "$basedir/html/.t" ) {
    push @technology, "OpenShift / Kubernetes";
    push @techshorts, "t";
  }
  if ( -f "$basedir/html/.q" ) {
    push @technology, "MS SQL";
    push @techshorts, "q";
  }
  if ( -f "$basedir/html/.g" ) {
    push @technology, "PostgreSQL";
    push @techshorts, "g";
  }
  if ( -f "$basedir/html/.i" ) {
    push @technology, "IBM Db2";
    push @techshorts, "i";
  }
  if ( -f "$basedir/html/.r" ) {
    push @technology, "Docker";
    push @techshorts, "r";
  }
  if ( -f "$basedir/html/.a" ) {
    push @technology, "Proxmox";
    push @techshorts, "a";
  }
  return { platforms => \@technology, shorts => \@techshorts };
}

sub txthref {
  my $hash = substr( md5_hex_uc( $_[0] . $_[1] ), 0, 7 );
  return "{\"title\":\"$_[0]\",\"href\":\"$_[1]\",\"hash\":\"$hash\"}";
}

sub fullNode {
  my ( $title, $href, $hmc, $srv, $islpar, $altname, $type, $parent ) = @_;
  $href ||= "";
  my $key     = ( $srv eq "na" ? "" : $srv ) . " " . $title;
  my $srvType = "";
  if ($type) {
    $srvType = lc $platform{$type};
  }
  my $parentKey = "";
  if ($parent) {
    $parentKey = ",\"parent\":\"$parent\"";
  }
  if ( !$altname ) {
    my $hashstr = $hmc . $srv . $title;
    my $hash    = substr( md5_hex_uc($hashstr), 0, 7 );
    return "{\"title\":\"$title\",\"href\":\"$href\",\"hash\":\"$hash\",\"hmc\":\"$hmc\",\"srv\":\"$srv\",\"str\":\"$key\",\"hwtype\":\"$srvType\"$parentKey,\"hashstr\":\"$hashstr\"}";
  }
  else {
    my $hashstr = $hmc . $srv . $altname;
    my $hash    = substr( md5_hex_uc($hashstr), 0, 7 );
    return "{\"title\":\"$title\",\"href\":\"$href\",\"hash\":\"$hash\",\"hmc\":\"$hmc\",\"srv\":\"$srv\",\"altname\":\"$altname\",\"str\":\"$key\",\"hwtype\":\"$srvType\"$parentKey,\"hashstr\":\"$hashstr\"}";
  }
}

sub fullNode_wchild {
  my ( $title, $href, $hmc, $srv, $islpar, $altname, $type, $parent ) = @_;
  my $key = ( $srv eq "na" ? "" : $srv ) . " " . $title;
  my $srvType;
  if ($type) {
    $srvType = lc $platform{$type};
  }
  my $parentKey = "";
  if ($parent) {
    $parentKey = ",\"parent\":\"$parent\"";
  }

  if ( !$altname ) {
    my $hash = substr( md5_hex_uc( $hmc . $srv . $title ), 0, 7 );
    return "{\"title\":\"$title\",\"href\":\"$href\",\"hash\":\"$hash\",\"hmc\":\"$hmc\",\"srv\":\"$srv\",\"str\":\"$key\",\"hwtype\":\"$srvType\"$parentKey,\"children\":[";
  }
  else {
    my $hash = substr( md5_hex_uc( $hmc . $srv . $altname ), 0, 7 );
    return "{\"title\":\"$title\",\"href\":\"$href\",\"hash\":\"$hash\",\"hmc\":\"$hmc\",\"srv\":\"$srv\",\"altname\":\"$altname\",\"str\":\"$key\",\"hwtype\":\"$srvType\"$parentKey,\"children\":[";
  }
}

sub pushFullNode {
  my ( $title, $href, $hmc, $srv, $islpar, $altname, $type, $parent, $obj, $extra ) = @_;
  my $key     = ( $srv eq "na" ? "" : $srv ) . " " . $title;
  my $srvType = "";
  if ($type) {
    if ( !$platform{$type} ) {
      warn "$type,$title,$hmc,$srv,";
    }
    $srvType = lc $platform{$type};
  }

  my $hashstr = $hmc . $srv . $title;
  if ($altname) {
    $hashstr = $hmc . $srv . $altname;
  }

  my $hash = substr( md5_hex_uc($hashstr), 0, 7 );

  # $hashstr = undef;
  #my $ret = { title => $title, href => $href, hash => $hash, hmc => $hmc, srv => $srv, altname => $altname, str => $key, type => $srvType, parent => $parent, obj => $obj, hashstr => $hashstr };
  my $ret = { title => $title, href => $href, hash => $hash, hmc => $hmc, srv => $srv, altname => $altname, str => $key, hwtype => $srvType, parent => $parent, obj => $obj, extraClasses => $extra };
  while ( my ( $key, $val ) = each %{$ret} ) {
    delete $ret->{$key} if ( not defined $val );
  }
  return $ret;
}

sub pushFullNodewChild {
  my ( $title, $href, $hmc, $srv, $islpar, $altname, $type, $parent, $obj ) = @_;
  my $key     = ( $srv eq "na" ? "" : $srv ) . " " . $title;
  my $srvType = "";
  if ($type) {
    $srvType = lc $platform{$type};
  }

  my $hashstr = $hmc . $srv . $title;
  if ($altname) {
    $hashstr = $hmc . $srv . $altname;
  }

  my $hash = substr( md5_hex_uc($hashstr), 0, 7 );
  $hashstr = undef;

  #my $ret = { title => $title, href => $href, hash => $hash, hmc => $hmc, srv => $srv, altname => $altname, str => $key, type => $srvType, parent => $parent, obj => $obj, hashstr => $hashstr, children => [] };
  my $ret = { title => $title, href => $href, hash => $hash, hmc => $hmc, srv => $srv, altname => $altname, str => $key, hwtype => $srvType, parent => $parent, obj => $obj, children => [], folder => \1 };
  while ( my ( $key, $val ) = each %{$ret} ) {
    delete $ret->{$key} if ( not defined $val );
  }
  return $ret;
}

sub pushFullNodewChil {
  my ( $title, $href, $hmc, $srv, $islpar, $altname, $type, $parent, $obj ) = @_;
  my $key     = ( $srv eq "na" ? "" : $srv ) . " " . $title;
  my $srvType = "";
  if ($type) {
    $srvType = lc $platform{$type};
  }
  if ( !$altname ) {
    my $hashstr = $hmc . $srv . $title;
    my $hash    = substr( md5_hex_uc($hashstr), 0, 7 );
    if ($parent) {

      #return { title => $title, href => $href, hash => $hash, hmc => $hmc, srv => $srv, str => $key, type => $srvType, parent => $parent, obj => $obj, hashstr => $hashstr, children => [] };
      return { title => $title, href => $href, hash => $hash, hmc => $hmc, srv => $srv, str => $key, hwtype => $srvType, parent => $parent, obj => $obj, children => [] };
    }
    else {
      #return { title => $title, href => $href, hash => $hash, hmc => $hmc, srv => $srv, str => $key, type => $srvType, obj => $obj, hashstr => $hashstr, children => [] };
      return { title => $title, href => $href, hash => $hash, hmc => $hmc, srv => $srv, str => $key, hwtype => $srvType, obj => $obj, children => [] };
    }
  }
  else {
    my $hashstr = $hmc . $srv . $altname;
    my $hash    = substr( md5_hex_uc($hashstr), 0, 7 );
    if ($parent) {

      #return { title => $title, href => $href, hash => $hash, hmc => $hmc, srv => $srv, altname => $altname, str => $key, type => $srvType, parent => $parent, obj => $obj, hashstr => $hashstr, children => [] };
      return { title => $title, href => $href, hash => $hash, hmc => $hmc, srv => $srv, altname => $altname, str => $key, hwtype => $srvType, parent => $parent, obj => $obj, children => [] };
    }
    else {
      #return { title => $title, href => $href, hash => $hash, hmc => $hmc, srv => $srv, altname => $altname, str => $key, type => $srvType, obj => $obj, hashstr => $hashstr, children => [] };
      return { title => $title, href => $href, hash => $hash, hmc => $hmc, srv => $srv, altname => $altname, str => $key, hwtype => $srvType, obj => $obj, children => [] };
    }
  }
}

sub txthrefbold {
  my $hash = substr( md5_hex_uc( $_[0] ), 0, 7 );
  return "{\"title\":\"$_[0]\",\"extraClasses\":\"boldmenu\",\"href\":\"$_[1]\",\"hash\":\"$hash\"}";
}

sub pushmenub {
  my ( $txt, $url, $id ) = @_;
  if ( !$id ) {
    $id = $txt;
  }
  my $hash = substr( md5_hex_uc($id), 0, 7 );
  return { "title" => $txt, "extraClasses" => "boldmenu", "href" => $url, "hash" => $hash };
}

sub pushmenu {
  my ( $txt, $url, $id ) = @_;
  if ( !$id ) {
    $id = $txt;
  }
  my $hash = substr( md5_hex_uc($id), 0, 7 );
  return { "title" => $txt, "href" => $url, "hash" => $hash };
}

sub txthref_wchld {
  return "{\"title\":\"$_[0]\",\"href\":\"$_[1]\",\"children\":[";
}

sub txtkey {
  return "{\"title\":\"$_[0]\",\"key\":\"$_[1]\"}";
}

sub txtkeysel {
  return "{\"title\":\"$_[0]\",\"selected\":true,\"key\":\"$_[1]\"}";
}

sub collons {
  return s/===double-col===/:/g;
}

sub genSubFolder {
  my ( $folderref, $menuref, $allVMs, $vc, $cl ) = @_;
  if ( exists $folderref->{folders} ) {
    foreach my $folder ( sort keys %{ $folderref->{folders} } ) {
      push @{$menuref}, { "title" => $folder, "folder" => "true", "children" => [] };
      my $newmenuref   = @$menuref[-1]->{children};
      my $newfolderref = $folderref->{folders}{$folder};
      genSubFolder( $newfolderref, $newmenuref, $allVMs, $vc, $cl );
    }
  }
  if ( exists $folderref->{items} ) {
    foreach my $item ( nsort keys %{ $folderref->{items} } ) {
      if ( $allVMs->{$item} ) {
        push @{$menuref}, pushFullNode( $item, $allVMs->{$item}{url}, $vc, $allVMs->{$item}{srv}, 1, $allVMs->{$item}{alt}, "V", $cl, "VM" );
      }
    }
  }
}

sub genSubFolderRP {
  my ( $folderref, $menuref, $vc, $cl ) = @_;
  if ( exists $folderref->{folders} ) {
    foreach my $folder ( sort keys %{ $folderref->{folders} } ) {

      # push @{ $menuref }, { "title" => $folder, "folder" => "true", "children" => [] };
      push @{$menuref}, pushFullNodewChild( $folder, $folderref->{folders}{$folder}{url}, $vc, $cl, 1, undef, undef, undef, "RP" );
      my $newmenuref   = @$menuref[-1]->{children};
      my $newfolderref = $folderref->{folders}{$folder};
      genSubFolderRP( $newfolderref, $newmenuref, $vc, $cl );
    }
  }
  if ( exists $folderref->{items} ) {
    foreach my $item ( sort keys %{ $folderref->{items} } ) {
      push @{$menuref}, pushFullNode( $item, $pack{respool}{$vc}{$cl}{$item}, $vc, $cl, 1, undef, undef, undef, "RP" );
    }
  }
}

sub genSubFolderDS {
  my ( $folderref, $menuref, $vc, $dc ) = @_;
  if ( exists $folderref->{folders} ) {
    foreach my $folder ( sort keys %{ $folderref->{folders} } ) {
      push @{$menuref}, { "title" => $folder, "folder" => "true", "children" => [] };
      my $newmenuref   = @$menuref[-1]->{children};
      my $newfolderref = $folderref->{folders}{$folder};
      genSubFolderDS( $newfolderref, $newmenuref, $vc, $dc );
    }
  }
  if ( exists $folderref->{items} ) {
    foreach my $item ( sort keys %{ $folderref->{items} } ) {
      push @{$menuref}, pushFullNode( $item, $pack{datastore}{$vc}{$dc}{$item}, $vc, $dc, 1, undef, undef, undef, "DS" );
    }
  }
}

sub print_all_models {
  if ( -f "$inputdir/etc/rperf_table.txt" ) {
    open( FALL, "< $inputdir/etc/rperf_table.txt" )
      || error( "$inputdir/etc/rperf_table.txt $! :" . __FILE__ . ":" . __LINE__ ) && return 1;
  }
  else {
    open( FALL, "< $inputdir/etc/free_rperf_table.txt" )
      || error( "$inputdir/etc/free_rperf_table.txt $! :" . __FILE__ . ":" . __LINE__ ) && return 1;
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
  no warnings 'uninitialized';
  my @lines_sort = sort { ( split ':', $a )[1] cmp( split ':', $b )[1] } @lines;

  #  print Dumper @lines_sort;

  # sort
  # 8284-22A : S822 :  P8/6		:  3.89		:  120.8		:
  # P8, P7+, P7, P6+, P6, P5+, P5

  print "[";

  # print_new_server ("P8\\+/",\@lines_sort, 0, 0);
  print_new_server( "P10/",   \@lines_sort, 1, 0 );
  print_new_server( "P9/",    \@lines_sort, 0, 0 );
  print_new_server( "P8/",    \@lines_sort, 0, 0 );
  print_new_server( "P7\\+/", \@lines_sort, 0, 0 );
  print_new_server( "P7/",    \@lines_sort, 0, 0 );
  print_new_server( "P6\\+/", \@lines_sort, 0, 0 );
  print_new_server( "P6/",    \@lines_sort, 0, 0 );
  print_new_server( "P5\\+/", \@lines_sort, 0, 0 );
  print_new_server( "P5/",    \@lines_sort, 0, 1 );
  print "]";

  return 0;
}

sub print_new_server {
  my ( $cpu_filter, $lines_sort_tmp, $expanded, $last ) = @_;
  my @lines_sort = @{$lines_sort_tmp};
  my ($class) = split( /\//, $cpu_filter );
  $class =~ s/\\//;
  $class = substr( $class, 1 );
  my $expandedstr = ( $expanded ? '"expanded":true,' : "" );
  if ( exists $lines_sort[0] ) {
    print "{\"title\":\"Power$class\",\"folder\":\"true\",$expandedstr\"children\":[\n";
    my $delim = "";
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
      ( my $model, my $type, my $cpu, my $ghz, $rperf, my $rperf_st, my $rperf_smt2, my $rperf_stm4, my $rperf_smt8, $cpw, my $fix ) = split( /:/, $line );

      if ( $cpu !~ m/^$cpu_filter/ ) {
        next;
      }
      no warnings "uninitialized";

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

      my $value = "$model|$type|$cpu|$ghz|$rperf|$rperf_st|$rperf_smt2|$rperf_stm4|$rperf_smt8|$cpw|$fix";

      print "$delim\{\"title\":\"$model\",\"hwtype\":\"$type\",\"cpu\":\"$cpu\",\"ghz\":\"$ghz\",\"fix\":\"$fix\",\"key\":\"$value\"}";
      $delim = ",\n";
    }
    if ($last) {
      print "]}\n";
    }
    else {
      print "]},\n";
    }
  }

  return 0;
}

sub uniq {
  my %seen;
  return grep { !$seen{$_}++ } @_;
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

sub boolean {
  my $val = shift;
  if ($val) {
    return "true";
  }
  else {
    return "false";
  }
}

sub findObjType {
  my ( $srv, $subsys, $name ) = @_;
  if ($srv) {
    foreach my $obj ( @{ $pack{fleet}{$srv}{subsys}{$subsys} } ) {
      if ( $obj->{k} eq $name ) {
        return $obj->{t};
      }
    }
  }
  else {
    foreach $srv ( keys %{ $pack{fleet} } ) {
      if ( $pack{fleet}{$srv}{subsys}{$subsys}{$name} ) {

        # print "$name\n";
        return $pack{fleet}{$srv}{subsys}{$subsys}{$name}{type};
      }
    }
  }
  return "";
}

sub file_read {
  my $file = shift;
  my $IO;
  if ( !open $IO, '<:encoding(UTF-8)', $file ) {
    print STDERR "Cannot open $file for input: $!\n";
    exit;
  }
  my @data = <$IO>;
  close $IO;
  wantarray ? @data : join( '' => @data );
}

# unicode proof version of md5_hex
sub md5_hex_uc {
  my $txt = shift;
  if ( defined $txt ) {
    return md5_hex( encode_utf8($txt) );
  }
  else {
    return md5_hex("");
  }
}
