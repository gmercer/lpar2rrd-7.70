# generates JSON data structures
use strict;
use warnings;
use File::Basename;
use RRDp;
use Xorux_lib qw(read_json write_json);

use AWSDataWrapper;
use GCloudDataWrapper;
use AzureDataWrapper;
use NutanixDataWrapper;
use ProxmoxDataWrapper;
use KubernetesDataWrapper;
use OpenshiftDataWrapper;
use FusionComputeDataWrapper;
use PostgresDataWrapper;
use SQLServerDataWrapper;

# use CGI::Carp qw(fatalsToBrowser);
$| = 1;
#
### you can run it from cmd line like: . etc/lpar2rrd.cfg; $PERL bin/heatmap.pl hyperv |tee a__heatmap.txt
#

my $DEBUG         = $ENV{DEBUG};
my $DEBUG_HEATMAP = $ENV{DEBUG_HEATMAP};
if ( !defined $DEBUG_HEATMAP ) { $DEBUG_HEATMAP = 0; }
else {
  $DEBUG_HEATMAP = 1;
}

my $GUIDEBUG        = $ENV{GUIDEBUG};
my $DEMO            = $ENV{DEMO};
my $BETA            = $ENV{BETA};
my $version         = $ENV{version};
my $errlog          = $ENV{ERRLOG};
my $basedir         = $ENV{INPUTDIR};
my $webdir          = $ENV{WEBDIR};
my $inputdir        = $ENV{INPUTDIR};
my $dashb_rrdheight = $ENV{DASHB_RRDHEIGHT};
my $dashb_rrdwidth  = $ENV{DASHB_RRDWIDTH};
my $legend_height   = $ENV{LEGEND_HEIGHT};
my $alturl          = $ENV{WWW_ALTERNATE_URL};
my $alttmp          = $ENV{WWW_ALTERNATE_TMP};
my $rrdtool         = $ENV{RRDTOOL};

my $tmpdir = "$basedir/tmp";
if ( defined $ENV{TMPDIR_LPAR} ) {
  $tmpdir = $ENV{TMPDIR_LPAR};
}
my $xormon = 0;
if ( defined $ENV{XORMON} && $ENV{XORMON} ) {
  $xormon = 1;
}

my $LPAR_HEATMAP_UTIL_TIME = $ENV{LPAR_HEATMAP_UTIL_TIME};
my $HEATMAP_EXCLUDE_CPU    = $ENV{HEATMAP_EXCLUDE_CPU};
my $HEATMAP_MEM_PAGING_MAX;
my $wrkdir = "$basedir/data";
my @pool;
my @test;
my $end_time   = time();
my $start_time = $end_time - 3600;    # last hour
my $count_lpars;
my $count_lpars_vm;
my $height = 150;
my $width  = 600;
my $count_pools;
my $count_pools_vm;
my $count_mem_lpars_power;
my @pool_list;
my %heatmap_exclude;
my %ovirt;
my $count_server_ovirt = 0;
my $count_vm_ovirt     = 0;
my %xen;
my $count_server_xen = 0;
my $count_vm_xen     = 0;
my %nutanix;
my $count_server_nutanix = 0;
my $count_vm_nutanix     = 0;
my %proxmox;
my $count_server_proxmox = 0;
my $count_vm_proxmox     = 0;
my %fusioncompute;
my $count_server_fusioncompute = 0;
my $count_vm_fusioncompute     = 0;
my %class_color;
my %types;
my %oraclevm;
my $count_server_oraclevm = 0;
my $count_vm_oraclevm     = 0;
my $count_lpars_hv;
my $count_pools_hv;

#my $HEATMAP_PANIC = 80;       # Setting a default values for colors
#my $HEATMAP_WARNING = 60;     # you can change setting values in etc/.magic

### set up utilization last x hour from variable LPAR_HEATMAP_UTIL_TIME
if ( defined $LPAR_HEATMAP_UTIL_TIME && isdigit($LPAR_HEATMAP_UTIL_TIME) ) {
  $start_time = $end_time - ( 3600 * $LPAR_HEATMAP_UTIL_TIME );

}
else {
  $LPAR_HEATMAP_UTIL_TIME = 1;
}

###

### in kB/s ###
if ( defined $ENV{HEATMAP_MEM_PAGING_MAX} ) {
  $HEATMAP_MEM_PAGING_MAX = $ENV{HEATMAP_MEM_PAGING_MAX};
}
else {
  $HEATMAP_MEM_PAGING_MAX = 50;
}

my %vmware;
my %vcenter_ids;
my %server_in_vcenter;
my %cluster_ids;
my %cluster_info;
my %lpars_in_cluster;
my %clusters_vms;
my %respools_in_clusters;

##########
my $managedname = "";
my $host;                   #  = $vcenter_key;
my @managednamelist_vmw;    #  = @files;
my $multiview_hmc_count;
my $vcenter_key;
my @files;
my $rp_moref;
my $cluster_moref;
my $rp_name;
my $pic_col                 = $ENV{PICTURE_COLOR};
my $STEP                    = $ENV{SAMPLE_RATE};
my $managed_systems_exclude = $ENV{MANAGED_SYSTEMS_EXCLUDE};

# keeps all VMs: $wrkdir/$all_vmware_VMs
my $all_vmware_VMs      = "vmware_VMs";
my %vm_id_path          = ();
my %vm_uuid_name_hash   = ();
my $CPU_ready_time_file = "";
my @rp_vm_morefs        = ();
my $server;
my $cluster;
my @managednamelist = ();
@managednamelist_vmw = ();

# keep here green - yellow - red - blue ...
my @color     = ( "#FF0000", "#0000FF", "#8fcc66", "#00FFFF", "#FFA500", "#00FF00", "#808080", "#FF00FF", "#800080", "#FDD017", "#0000A0", "#3BB9FF", "#008000", "#800000", "#C0C0C0", "#ADD8E6", "#F778A1", "#800517", "#736F6E", "#F52887", "#C11B17", "#5CB3FF", "#A52A2A", "#FF8040", "#2B60DE", "#736AFF", "#1589FF", "#98AFC7", "#8D38C9", "#307D7E", "#F6358A", "#151B54", "#6D7B8D", "#33cc33", "#FF0080", "#F88017", "#2554C7", "#00a900", "#D4A017", "#306EFF", "#151B8D", "#9E7BFF", "#EAC117", "#99cc00", "#15317E", "#6C2DC7", "#FBB917", "#86b300", "#15317E", "#254117", "#FAAFBE", "#357EC7", "#4AA02C", "#38ACEC" );
my $color_max = 53;                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                     # 0 - 53 is 54 colors

my @keep_color_lpar = "";

my $delimiter               = "XORUX";                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                  # this is for rrdtool print lines for clickable legend
my $YEAR_REFRESH            = 86400;                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                    # 24 hour, minimum time in sec when yearly graphs are updated (refreshed)
my $MONTH_REFRESH           = 39600;                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                    # 11 hour, minimum time in sec when monthly graphs are updated (refreshed)
my $WEEK_REFRESH            = 18000;                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                    # 5 hour, minimum time in sec when weekly  graphs are updated (refreshed)
my $disable_rrdtool_tag     = "--interlaced";                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                           # just nope string, it is deprecated anyway
my $disable_rrdtool_tag_agg = "--interlaced";                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                           # just nope string, it is deprecated anyway

my $et_HostSystem             = "HostSystem";
my $et_Datastore              = "Datastore";
my $et_ResourcePool           = "ResourcePool";
my $et_Datacenter             = "Datacenter";
my $et_ClusterComputeResource = "ClusterComputeResource";

### end vmware definition

my $style_html = "td.clr0 {background-color:#737a75;} td.clr1 {background-color:#008000;} td.clr2 {background-color:#29f929;} td.clr3 {background-color:#81fa51;} td.clr4 {background-color:#c9f433;} td.clr5 {background-color:#FFFF66;} td.clr6 {background-color:#ffff00;} td.clr7 {background-color:#FFCC00;} td.clr8 {background-color:#ffa500;} td.clr9 {background-color:#fa610e;} td.clr10 {background-color:#ff0000;}  table.center {margin-left:auto; margin-right:auto;} table {border-spacing: 1px;} .content_legend { height:" . "15" . "px" . "; width:" . "15" . "px" . ";}";

$class_color{clr0}  = "#737a75";
$class_color{clr1}  = "#008000";
$class_color{clr2}  = "#29f929";
$class_color{clr3}  = "#81fa51";
$class_color{clr4}  = "#c9f433";
$class_color{clr5}  = "#FFFF66";
$class_color{clr6}  = "#ffff00";
$class_color{clr7}  = "#FFCC00";
$class_color{clr8}  = "#ffa500";
$class_color{clr9}  = "#fa610e";
$class_color{clr10} = "#ff0000";

my @replace_file;
my %pools;
my %stree;        # Serverr
my %vclusters;    # Servers nested by clusters
my %lstree;       # LPARs by Server
my %lhtree;       # LPARs by HMC
my %vtree;        # VMware vCenter
my %cluster;      # VMware Cluster
my %respool;      # VMware Resource Pool
my @lnames;       # LPAR name (for autocomplete)
my %inventory;    # server / type / name
my %times;        # server timestamps
my $free;         # 1 -> free / 0 -> full
my $hasPower;     # flag for IBM Power presence
my $hasVMware;    # flag for WMware presence

#my @hmc_list = get_hmc_list();

print "heatmap        : start " . localtime() . "\n";

if ( !defined $ENV{INPUTDIR} ) {
  print "Not defined INPUTDIR, probably not read etc/lpar2rrd.cfg\n";
  print STDERR "heatmap Not defined INPUTDIR, probably not read etc/lpar2rrd.cfg\n";
  exit(0);
}

if ( !-f "$rrdtool" ) {
  error("Set correct path to rrdtool binary, it does not exist here: $rrdtool");
  exit;
}

RRDp::start "$rrdtool";

my $cpu_max_filter = 100;    # my $cpu_max_filter = 100;  # max 10k peak in % is allowed (in fact it cannot by higher than 1k now when 1 logical CPU == 0.1 entitlement)
if ( defined $ENV{CPU_MAX_FILTER} ) {
  $cpu_max_filter = $ENV{CPU_MAX_FILTER};
}

# set unbuffered stdout
#$| = 1;

# open( OUT, ">> $errlog" ) if $DEBUG == 2;

# get QUERY_STRING
use Env qw(QUERY_STRING);

# print OUT "-- $QUERY_STRING\n" if $DEBUG == 2;

#`echo "QS $QUERY_STRING " >> /tmp/xx32`;
my ( $type, $par1, $par2 );
if ( defined $QUERY_STRING ) {
  ( $type, $par1, $par2 ) = split( /&/, $QUERY_STRING );
}

if ( !defined $type || $type eq "" ) {
  if (@ARGV) {
    $type = "type=" . $ARGV[0];

    #$basedir  = "..";
  }
  else {
    $type = "type=test";
  }
}

$type =~ s/type=//;
$type = "test";

if ( $type eq "test" ) {

  #$basedir = "..";
  #$wrkdir = "/home/lpar2rrd/lpar2rrd/data";
  &test();
  RRDp::end;    # close RRD pipe
  exit;
}

#if ( $type eq "dump" ) {
#    &dumpHTML();
#    RRDp::end; # close RRD pipe
#    exit;
#}

RRDp::end;    # close RRD pipe

# read menu.txt, omit empty lines, omit lines starting with '*'
sub read_menu {
  my $menu_ref = shift;
  open( my $FF, "<$tmpdir/menu.txt" ) || error( "can't open $tmpdir!menu.txt: $! :" . __FILE__ . ":" . __LINE__ ) && return 0;
  while (<$FF>) {
    next if length($_) < 2;
    next if substr( $_, 0, 1 ) !~ /[A-Z0-9]/;
    push @$menu_ref, $_;
  }
  close($FF);
  return;
}

sub test {

  #print "Content-type: text/plain\n\n";
  use Data::Dumper;

  #print "heatmap        : start ". time() . "\n";
  #	print Dumper @aclServ;
  # print Dumper \%aclLpars;
  &readMenu();

  # print Dumper \%inventory;
  count_vm();

  # print Dumper ("vcenter_ids",\%vcenter_ids);
  # print Dumper ("server_in_vcenter",\%server_in_vcenter);
  # print Dumper ("cluster_ids",\%cluster_ids);
  # print Dumper ("vclusters",\%vclusters);

  # print Dumper \%lhtree;
  # print Dumper \%vtree;
  # print Dumper \%lstree;
  #print Dumper \%pools;
  #print Dumper \%inventory;
  #%vmware = %inventory;

  ### customer requirement
  my $file         = "$basedir/etc/heatmap_exclude.cfg";
  my @data_exclude = ();
  if ( -e $file && !-z $file ) {
    open( my $FH, "< $file" ) || error( "Cannot read $file: $!" . __FILE__ . ":" . __LINE__ ) && next;
    @data_exclude = <$FH>;
    close($FH);
  }
  foreach my $line (@data_exclude) {
    chomp $line;
    $line =~ s/^\s+|\s+$//g;
    if ( $line eq "" ) { next; }
    if ( $line =~ m/^LPAR/i ) {
      $line =~ s/^LPAR://i;
      $line =~ s/^\s+|\s+$//g;
      if ( !defined $line || $line eq "" ) { next; }
      $heatmap_exclude{POWER}{LPAR}{$line} = $line;
    }
    if ( $line =~ m/^CPUPOOL:/i ) {
      $line =~ s/^CPUPOOL://i;
      $line =~ s/^\s+|\s+$//g;
      if ( !defined $line || $line eq "" ) { next; }
      if ( $line eq "cpupool" ) {
        $line = "CPU pool";
      }
      $heatmap_exclude{POWER}{POOL}{$line} = $line;
    }
    if ( $line =~ m/^VM:/i ) {
      $line =~ s/^VM://i;
      $line =~ s/^\s+|\s+$//g;
      if ( !defined $line || $line eq "" ) { next; }
      $heatmap_exclude{VMWARE}{LPAR}{$line} = $line;
    }
    if ( $line =~ m/^ESXI:/i ) {
      $line =~ s/^ESXI://i;
      $line =~ s/^\s+|\s+$//g;
      if ( !defined $line || $line eq "" ) { next; }
      $heatmap_exclude{VMWARE}{SERVER}{$line} = $line;
    }
  }

  #print Dumper \%heatmap_exclude;
  foreach my $server ( keys %inventory ) {
    my $type = $inventory{$server}{TYPE};
    if ( !defined $type || $type ne "P" ) { next; }
    foreach my $pool ( keys %{ $inventory{$server}{POOL} } ) {
      my $name = $inventory{$server}{POOL}{$pool}{NAME};
      if ( !defined $name || $name eq "" ) {
        $name = $pool;
      }
      if ( defined $heatmap_exclude{POWER}{POOL}{$name} ) {
        delete $inventory{$server}{POOL}{$pool};
      }
    }
    foreach my $lpar ( keys %{ $inventory{$server}{LPAR} } ) {
      my $name = $inventory{$server}{LPAR}{$lpar}{NAME};
      if ( !defined $name || $name eq "" ) {
        $name = $lpar;
      }
      if ( defined $heatmap_exclude{POWER}{LPAR}{$name} ) {
        delete $inventory{$server}{LPAR}{$lpar};
      }
    }
  }

  foreach my $server ( keys %inventory ) {
    my $type = $inventory{$server}{TYPE};
    if ( !defined $type || $type ne "V" ) { next; }
    if ( defined $heatmap_exclude{VMWARE}{SERVER}{$server} ) {
      delete $inventory{$server};
      next;
    }
    foreach my $lpar ( keys %{ $inventory{$server}{LPAR} } ) {
      my $name = $inventory{$server}{LPAR}{$lpar}{NAME};
      if ( !defined $name || $name eq "" ) {
        $name = $lpar;
      }
      if ( defined $heatmap_exclude{VMWARE}{LPAR}{$name} ) {
        delete $inventory{$server}{LPAR}{$lpar};
      }
    }
  }

  #print Dumper \%inventory;
  ###
  %vmware = %inventory;

  my $system_machine = "";
  if ( defined $ARGV[0] && $ARGV[0] eq "power" ) {
    $system_machine = "power";
  }
  elsif ( defined $ARGV[0] && $ARGV[0] eq "vmware" ) {
    $system_machine = "vmware";
  }
  elsif ( defined $ARGV[0] && $ARGV[0] eq "ovirt" ) {
    $system_machine = "ovirt";
  }
  elsif ( defined $ARGV[0] && $ARGV[0] eq "hyperv" ) {
    $system_machine = "hyperv";
  }
  else {
    if ( defined $ARGV[0] ) {
      $system_machine = $ARGV[0];
    }
  }

  if ( $system_machine eq "power" ) {
    set_live_inventory();
    set_curr_procs();
    set_utilization_cpu_power();
    set_utilization_pool_power();
    set_utilization_mem_power();
    set_html_power();

    if ( -f "$basedir/tmp/menu_ovirt.json" ) {

      set_structure_ovirt();
      set_utilization_ovirt( "SERVER", "CPU" );
      set_utilization_ovirt( "SERVER", "MEMORY" );
      set_utilization_ovirt( "VM",     "CPU" );
      set_utilization_ovirt( "VM",     "MEMORY" );
      print "heatmap        : (Ovirt) set cpu utilization for $count_vm_ovirt vms\n";
      print "heatmap        : (Ovirt) set memory utilization for $count_vm_ovirt vms\n";
      print "heatmap        : (Ovirt) set cpu utilization for $count_server_ovirt servers\n";
      print "heatmap        : (Ovirt) set memory utilization for $count_server_ovirt servers\n";
      set_html_ovirt();
    }
    if ( -f "$basedir/tmp/menu_xenserver.json" ) {
      set_structure_xen();
      set_utilization_xen( "SERVER", "CPU" );
      set_utilization_xen( "SERVER", "MEMORY" );
      set_utilization_xen( "VM",     "CPU" );
      set_utilization_xen( "VM",     "MEMORY" );
      print "heatmap        : (XEN) set cpu utilization for $count_vm_xen vms\n";
      print "heatmap        : (XEN) set memory utilization for $count_vm_xen vms\n";
      print "heatmap        : (XEN) set cpu utilization for $count_server_xen servers\n";
      print "heatmap        : (XEN) set memory utilization for $count_server_xen servers\n";
      set_html_xen();

    }

    if ( -f "$basedir/tmp/menu_nutanix.json" ) {
      set_structure_nutanix();
      set_utilization_nutanix( "SERVER", "CPU" );
      set_utilization_nutanix( "SERVER", "MEMORY" );
      set_utilization_nutanix( "VM",     "CPU" );
      set_utilization_nutanix( "VM",     "MEMORY" );
      print "heatmap        : (NUTANIX) set cpu utilization for $count_vm_nutanix vms\n";
      print "heatmap        : (NUTANIX) set memory utilization for $count_vm_nutanix vms\n";
      print "heatmap        : (NUTANIX) set cpu utilization for $count_server_nutanix servers\n";
      print "heatmap        : (NUTANIX) set memory utilization for $count_server_nutanix servers\n";
      set_html_nutanix();

    }

    if ( -f "$basedir/tmp/menu_proxmox.json" ) {
      set_structure_proxmox();
      set_utilization_proxmox( "SERVER", "CPU" );
      set_utilization_proxmox( "SERVER", "MEMORY" );
      set_utilization_proxmox( "VM",     "CPU" );
      set_utilization_proxmox( "VM",     "MEMORY" );
      print "heatmap        : (Proxmox) set cpu utilization for $count_vm_proxmox vms\n";
      print "heatmap        : (Proxmox) set memory utilization for $count_vm_proxmox vms\n";
      print "heatmap        : (Proxmox) set cpu utilization for $count_server_proxmox servers\n";
      print "heatmap        : (Proxmox) set memory utilization for $count_server_proxmox servers\n";
      set_html_proxmox();

    }

    if ( -f "$basedir/tmp/menu_fusioncompute.json" ) {
      set_structure_fusioncompute();
      set_utilization_fusioncompute( "SERVER", "CPU" );
      set_utilization_fusioncompute( "SERVER", "MEMORY" );
      set_utilization_fusioncompute( "VM",     "CPU" );
      set_utilization_fusioncompute( "VM",     "MEMORY" );
      print "heatmap        : (FusionCompute) set cpu utilization for $count_vm_fusioncompute vms\n";
      print "heatmap        : (FusionCompute) set memory utilization for $count_vm_fusioncompute vms\n";
      print "heatmap        : (FusionCompute) set cpu utilization for $count_server_fusioncompute servers\n";
      print "heatmap        : (FusionCompute) set memory utilization for $count_server_fusioncompute servers\n";
      set_html_fusioncompute();

    }

    if ( -f "$basedir/tmp/menu_oraclevm.json" ) {
      ### oraclevm
      set_structure_oraclevm();
      set_utilization_oraclevm( "SERVER", "CPU" );
      set_utilization_oraclevm( "SERVER", "MEMORY" );
      set_utilization_oraclevm( "VM",     "CPU" );
      print "heatmap        : (ORACLEVM) set cpu utilization for $count_vm_oraclevm vms\n";
      print "heatmap        : (ORACLEVM) set cpu utilization for $count_server_oraclevm servers\n";
      set_html_oraclevm();
    }
    if ( -d "$basedir/data/windows" ) {
      set_live_hyperv();
      set_utilization_cpu_hv();
      set_html_hv();
    }
  }

  if ( $system_machine eq "vmware" ) {
    set_live_vmware();
    set_utilization_cpu_mem_vm();
    set_utilization_pool_vm();
    set_html_vm();
    gen_vmware_cmd_files();
  }
  if ( $system_machine eq "ovirt" && -f "$basedir/tmp/menu_ovirt.json" ) {
    ### ovirt
    set_structure_ovirt();
    set_utilization_ovirt( "SERVER", "CPU" );
    set_utilization_ovirt( "SERVER", "MEMORY" );
    set_utilization_ovirt( "VM",     "CPU" );
    set_utilization_ovirt( "VM",     "MEMORY" );
    print "heatmap        : (Ovirt) set cpu utilization for $count_vm_ovirt vms\n";
    print "heatmap        : (Ovirt) set memory utilization for $count_vm_ovirt vms\n";
    print "heatmap        : (Ovirt) set cpu utilization for $count_server_ovirt servers\n";
    print "heatmap        : (Ovirt) set memory utilization for $count_server_ovirt servers\n";
    set_html_ovirt();
  }
  if ( $system_machine eq "xen" && -f "$basedir/tmp/menu_xenserver.json" ) {
    set_structure_xen();
    set_utilization_xen( "SERVER", "CPU" );
    set_utilization_xen( "SERVER", "MEMORY" );
    set_utilization_xen( "VM",     "CPU" );
    set_utilization_xen( "VM",     "MEMORY" );
    print "heatmap        : (XEN) set cpu utilization for $count_vm_xen vms\n";
    print "heatmap        : (XEN) set memory utilization for $count_vm_xen vms\n";
    print "heatmap        : (XEN) set cpu utilization for $count_server_xen servers\n";
    print "heatmap        : (XEN) set memory utilization for $count_server_xen servers\n";
    set_html_xen();

  }
  if ( $system_machine eq "oraclevm" && -f "$basedir/tmp/menu_oraclevm.json" ) {
    ### oraclevm
    set_structure_oraclevm();
    set_utilization_oraclevm( "SERVER", "CPU" );
    set_utilization_oraclevm( "SERVER", "MEMORY" );
    set_utilization_oraclevm( "VM",     "CPU" );
    print "heatmap        : (ORACLEVM) set cpu utilization for $count_vm_oraclevm vms\n";
    print "heatmap        : (ORACLEVM) set cpu utilization for $count_server_oraclevm servers\n";
    set_html_oraclevm();
  }
  if ( $system_machine eq "nutanix" && -f "$basedir/tmp/menu_nutanix.json" ) {
    set_structure_nutanix();
    set_utilization_nutanix( "SERVER", "CPU" );
    set_utilization_nutanix( "SERVER", "MEMORY" );
    set_utilization_nutanix( "VM",     "CPU" );
    set_utilization_nutanix( "VM",     "MEMORY" );
    print "heatmap        : (NUTANIX) set cpu utilization for $count_vm_nutanix vms\n";
    print "heatmap        : (NUTANIX) set memory utilization for $count_vm_nutanix vms\n";
    print "heatmap        : (NUTANIX) set cpu utilization for $count_server_nutanix servers\n";
    print "heatmap        : (NUTANIX) set memory utilization for $count_server_nutanix servers\n";
    set_html_nutanix();

  }
  if ( $system_machine eq "proxmox" && -f "$basedir/tmp/menu_proxmox.json" ) {
    set_structure_proxmox();
    set_utilization_proxmox( "SERVER", "CPU" );
    set_utilization_proxmox( "SERVER", "MEMORY" );
    set_utilization_proxmox( "VM",     "CPU" );
    set_utilization_proxmox( "VM",     "MEMORY" );
    print "heatmap        : (Proxmox) set cpu utilization for $count_vm_proxmox vms\n";
    print "heatmap        : (Proxomx) set memory utilization for $count_vm_proxmox vms\n";
    print "heatmap        : (Proxmox) set cpu utilization for $count_server_proxmox servers\n";
    print "heatmap        : (Proxmox) set memory utilization for $count_server_proxmox servers\n";
    set_html_proxmox();

  }
  if ( $system_machine eq "fusioncompute" && -f "$basedir/tmp/menu_fusioncompute.json" ) {
    set_structure_fusioncompute();
    set_utilization_fusioncompute( "SERVER", "CPU" );
    set_utilization_fusioncompute( "SERVER", "MEMORY" );
    set_utilization_fusioncompute( "VM",     "CPU" );
    set_utilization_fusioncompute( "VM",     "MEMORY" );
    print "heatmap        : (FusionCompute) set cpu utilization for $count_vm_fusioncompute vms\n";
    print "heatmap        : (FusionCompute) set memory utilization for $count_vm_fusioncompute vms\n";
    print "heatmap        : (FusionCompute) set cpu utilization for $count_server_fusioncompute servers\n";
    print "heatmap        : (FusionCompute) set memory utilization for $count_server_fusioncompute servers\n";
    set_html_fusioncompute();

  }
  if ( $system_machine eq "hyperv" ) {
    set_live_hyperv();
    set_utilization_cpu_hv();
    set_html_hv();

  }
  if ( $system_machine eq "" ) {

    set_live_inventory();
    set_curr_procs();
    set_utilization_cpu_power();
    set_utilization_pool_power();
    set_utilization_mem_power();
    set_live_vmware();
    set_utilization_cpu_mem_vm();
    set_utilization_pool_vm();
    set_html_power();
    set_html_vm();

    ### ovirt
    set_structure_ovirt();
    set_utilization_ovirt( "SERVER", "CPU" );
    set_utilization_ovirt( "SERVER", "MEMORY" );
    set_utilization_ovirt( "VM",     "CPU" );
    set_utilization_ovirt( "VM",     "MEMORY" );
    print "heatmap        : (Ovirt) set cpu utilization for $count_vm_ovirt vms\n";
    print "heatmap        : (Ovirt) set memory utilization for $count_vm_ovirt vms\n";
    print "heatmap        : (Ovirt) set cpu utilization for $count_server_ovirt servers\n";
    print "heatmap        : (Ovirt) set memory utilization for $count_server_ovirt servers\n";
    set_html_ovirt();
    ###

    set_structure_xen();
    set_utilization_xen( "SERVER", "CPU" );
    set_utilization_xen( "SERVER", "MEMORY" );
    set_utilization_xen( "VM",     "CPU" );
    set_utilization_xen( "VM",     "MEMORY" );
    print "heatmap        : (XEN) set cpu utilization for $count_vm_xen vms\n";
    print "heatmap        : (XEN) set memory utilization for $count_vm_xen vms\n";
    print "heatmap        : (XEN) set cpu utilization for $count_server_xen servers\n";
    print "heatmap        : (XEN) set memory utilization for $count_server_xen servers\n";
    set_html_xen();

    set_structure_nutanix();
    set_utilization_nutanix( "SERVER", "CPU" );
    set_utilization_nutanix( "SERVER", "MEMORY" );
    set_utilization_nutanix( "VM",     "CPU" );
    set_utilization_nutanix( "VM",     "MEMORY" );
    print "heatmap        : (NUTANIX) set cpu utilization for $count_vm_nutanix vms\n";
    print "heatmap        : (NUTANIX) set memory utilization for $count_vm_nutanix vms\n";
    print "heatmap        : (NUTANIX) set cpu utilization for $count_server_nutanix servers\n";
    print "heatmap        : (NUTANIX) set memory utilization for $count_server_nutanix servers\n";
    set_html_nutanix();

    set_structure_proxmox();
    set_utilization_proxmox( "SERVER", "CPU" );
    set_utilization_proxmox( "SERVER", "MEMORY" );
    set_utilization_proxmox( "VM",     "CPU" );
    set_utilization_proxmox( "VM",     "MEMORY" );
    print "heatmap        : (Proxmox) set cpu utilization for $count_vm_proxmox vms\n";
    print "heatmap        : (Proxmox) set memory utilization for $count_vm_proxmox vms\n";
    print "heatmap        : (Proxmox) set cpu utilization for $count_server_proxmox servers\n";
    print "heatmap        : (Proxmox) set memory utilization for $count_server_proxmox servers\n";
    set_html_proxmox();

    set_structure_fusioncompute();
    set_utilization_fusioncompute( "SERVER", "CPU" );
    set_utilization_fusioncompute( "SERVER", "MEMORY" );
    set_utilization_fusioncompute( "VM",     "CPU" );
    set_utilization_fusioncompute( "VM",     "MEMORY" );
    print "heatmap        : (FusionCompute) set cpu utilization for $count_vm_fusioncompute vms\n";
    print "heatmap        : (FusionCompute) set memory utilization for $count_vm_fusioncompute vms\n";
    print "heatmap        : (FusionCompute) set cpu utilization for $count_server_fusioncompute servers\n";
    print "heatmap        : (FusionCompute) set memory utilization for $count_server_fusioncompute servers\n";
    set_html_fusioncompute();

    ### oraclevm
    set_structure_oraclevm();
    set_utilization_oraclevm( "SERVER", "CPU" );
    set_utilization_oraclevm( "SERVER", "MEMORY" );
    set_utilization_oraclevm( "VM",     "CPU" );
    print "heatmap        : (OracleVM) set cpu utilization for $count_vm_oraclevm vms\n";
    print "heatmap        : (OracleVM) set cpu utilization for $count_server_oraclevm servers\n";
    set_html_oraclevm();

  }
  print "heatmap        : end " . localtime() . "\n";

  Xorux_lib::write_json( "$basedir/tmp/total-vm-count.json", \%types );
  if ($DEBUG_HEATMAP) {
    print Dumper \%inventory;
  }

  #print encode_json( \%lstree );
  #	print (@ctree > 0 ? "true" : "false" );
  #print Dumper \%types;

}

sub count_vm {
  my %platform;
  $platform{V}     = "VMware";
  $platform{P}     = "IBM Power System";
  $platform{B}     = "Hitachi";
  $platform{X}     = "XenServer";
  $platform{O}     = "oVirt";
  $platform{H}     = "Hyper-V";
  $platform{"P:M"} = "Linux";

  $platform{N} = "Nutanix";
  $platform{A} = "Amazon Web Services";
  $platform{G} = "Google Cloud";
  $platform{Z} = "Microsoft Azure";
  $platform{M} = "Proxmox";
  $platform{W} = "FusionCompute";

  $platform{C} = "OpenShift";
  $platform{K} = "Kubernetes";

  $platform{T} = "PostgreSQL";
  $platform{D} = "SQL Server";

  #new vm count from {platform}DataWrapper.pm
  my $tmp = AWSDataWrapper::get_items( { 'item_type' => 'ec2' } );
  $types{ $platform{A} } = scalar @{$tmp};

  $tmp = GCloudDataWrapper::get_items( { 'item_type' => 'compute' } );
  $types{ $platform{G} } = scalar @{$tmp};

  $tmp = AzureDataWrapper::get_items( { 'item_type' => 'vm' } );
  $types{ $platform{Z} } = scalar @{$tmp};

  $tmp = NutanixDataWrapper::get_items( { 'item_type' => 'vm' } );
  $types{ $platform{N} } = scalar @{$tmp};

  $tmp = ProxmoxDataWrapper::get_items( { 'item_type' => 'vm' } );
  $types{ $platform{M} } = scalar @{$tmp};

  $tmp = KubernetesDataWrapper::get_items( { 'item_type' => 'pod' } );
  $types{ $platform{K} } = scalar @{$tmp};

  $tmp = OpenshiftDataWrapper::get_items( { 'item_type' => 'pod' } );
  $types{ $platform{C} } = scalar @{$tmp};

  #  $tmp = PostgresDataWrapper::get_items({'item_type' => 'dbs'});
  #  $types{$platform{T}} = scalar @{$tmp};

  $tmp = FusionComputeDataWrapper::get_items( { 'item_type' => 'vm' } );
  $types{ $platform{W} } = scalar @{$tmp};

  #  $tmp = SQLServerDataWrapper::get_items({'item_type' => 'dbs'});
  #  $types{$platform{D}} = scalar @{$tmp};

  foreach my $server ( keys %inventory ) {
    my $type = $inventory{$server}{TYPE};
    if ( !defined $type ) { next; }
    if ( $type eq "L" && defined $inventory{$server}{TYPE2} ) {
      if ( defined $platform{ $inventory{$server}{TYPE2} } ) {
        $type = $platform{ $inventory{$server}{TYPE2} };
      }
    }
    if ( $type eq "L" ) { next; }
    if ( defined $platform{$type} ) {
      $type = $platform{$type};
    }
    if ( !defined $inventory{$server}{LPAR} ) {
      next;
    }
    my $count = keys %{ $inventory{$server}{LPAR} };
    if ( isdigit( $types{$type} ) ) {
      $types{$type} = $types{$type} + $count;
    }
    else {
      $types{$type} = $count;
    }
  }
  foreach my $p ( keys %platform ) {
    if ( !defined $types{ $platform{$p} } ) {
      $types{ $platform{$p} } = 0;
    }
  }

  ### oracle db count
  my @data = ();
  if ( -f "$basedir/tmp/OracleDB_count.txt" ) {
    open( my $FH, "< $basedir/tmp/OracleDB_count.txt" ) || error( "Cannot read $basedir/tmp/OracleDB_count.txt: $!" . __FILE__ . ":" . __LINE__ );
    @data = <$FH>;
    close($FH);
  }
  foreach my $line (@data) {
    chomp $line;
    if ( $line eq "" ) { next; }
    my ( $name, $count ) = split( " : ", $line );
    if ( defined $name && defined $count ) {
      $name  =~ s/^\s+|\s+$//g;
      $count =~ s/^\s+|\s+$//g;
      if ( isdigit($count) ) {
        $types{$name} = int($count);
      }
    }
  }
  ### oracle db count
  #print Dumper \%types;
}

sub readMenu {
  my $alt     = shift;
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

  my $skel = "$basedir/$tmppath/menu.txt";
  if ( !-f "$skel" ) {
    return;
  }

  #my $skel = "/home/lpar2rrd/lpar2rrd/$tmppath/menu.txt";
  my $last_hmc    = "";
  my $last_server = "";
  my $index       = 1;
  my %hmc_server_del;

  #print "$skel\n";
  #open( my $SKEL, $skel ) or error_die("Cannot open file: $skel : $!");

  # use sub read_menu
  $tmpdir = "$basedir/$tmppath";
  my @menu = ();
  read_menu( \@menu );

  foreach (@menu) {
    my ( $hmc, $srv, $txt, $url );
    my $line = $_;
    chomp $line;
    my @val = split( ':', $line );

    s/===double-col===/:/g for @val;

    {
      "O" eq $val[0] && do {
        $free = ( $val[1] == 1 ) ? 1 : 0;
        next;
      };
      "D" eq $val[0] && do {

        #$server_del = $val[2];
        if ( $val[1] eq $last_hmc && $val[2] eq $last_server ) {
          last;
        }
        $hmc_server_del{$index}{HMC}    = $val[1];
        $hmc_server_del{$index}{SERVER} = $val[2];
        $last_hmc                       = $val[1];
        $last_server                    = $val[2];
        $index++;
        next;
      };

      # prepare hash list of vcenter uuid: used for VMs uuid construction
      #V:10.22.11.10:Totals:/lpar2rrd-cgi/detail.sh?host=10.22.11.10&server=vmware_eb6102a7-1fa0-4376-acbb-f67e34a2212c_28&lpar=nope&item=hmctotals&entitle=0&gui=1&none=none:::Hosting::V:
      "V" eq $val[0] && do {
        if ( $val[2] eq "Totals" ) {

          # $val[1] is vcenter IP
          # print "691 ,$val[3],\n";
          my $vcenter_id = "";
          ( undef, $vcenter_id ) = split "vmware_", $val[3];

          # print "692 ,$val[3], ,$vcenter_id,\n";
          $vcenter_id =~ s/\&lpar=.*//g;

          # print "693 ,$val[3], ,$vcenter_id,\n";
          $vcenter_ids{ $val[1] } = $vcenter_id;    # will be used later for VMs id
        }
        next;
      };

      # prepare hash list of cluster uuid: used for esxi uuid construction
      # there can be same cluster name in more vcenters
      # A:10.22.111.4:cluster_ClusterOL:Totals:/lpar2rrd-cgi/detail.sh?host=cluster_domain-c7&server=vmware_ef81e113-3f75-4e78-bc8c-a86df46a4acb_12&lpar=nope&item=cluster&entitle=0&gui=1&none=none::Olomouc::V:
      # A:10.22.11.10:cluster_ClusterOL:Totals:/lpar2rrd-cgi/detail.sh?host=cluster_domain-c314&server=vmware_eb6102a7-1fa0-4376-acbb-f67e34a2212c_28&lpar=nope&item=cluster&entitle=0&gui=1&none=none::Hosting::V:
      #
      "A" eq $val[0] && do {
        if ( $val[8] eq "V" ) {
          my $cluster_id = "";
          ( undef, my $url_part ) = split "host=", $val[4];
          $cluster_id = $url_part;
          $cluster_id =~ s/\&server=.*//g;

          if ( exists $cluster_ids{ $val[2] } ) {
            error( "Seems more clusters have same name $val[2] $cluster_ids{$val[2]} $cluster_id " . __FILE__ . ":" . __LINE__ );
          }
          $cluster_ids{ $val[2] }             = $cluster_id;    # will be used later for esxi id
          $cluster_info{ $val[1] }{ $val[2] } = $cluster_id;    # as $cluster_info {host} {cluster_name} = cluster_id
          $cluster_info{ $val[1] }{url}       = $url_part;
        }
        next;
      };

      # prepare hash list of respools in clusters
      #B:10.22.11.10:cluster_New Cluster:Development:/lpar2rrd-cgi/detail.sh?host=cluster_domain-c87&server=vmware_eb6102a7-1fa0-4376-acbb-f67e34a2212c_28&lpar=resgroup-139&item=resourcepool&entitle=0&gui=1&none=none::Hosting::V:
      "B" eq $val[0] && do {
        ( undef, my $cluster_moref, undef, my $respool_moref, undef ) = split "=", $val[4];
        $cluster_moref =~ s/&.*//g;
        $respool_moref =~ s/&.*//g;
        $respools_in_clusters{$cluster_moref}{$respool_moref} = $val[3];    # is respool name
      };

      #S:ahmc11:BSRV21:CPUpool-pool:CPU pool:ahmc11/BSRV21/pool/gui-cpu.html::1399967748
      "S" eq $val[0] && do {
        my ( $hmc, $srv, $pool, $txt, $url, $timestamp, $type ) = ( $val[1], $val[2], $val[3], $val[4], $val[5], $val[7], $val[8] );
        if ( !$timestamp ) {
          $timestamp = 999;
        }

        # S:cluster_New Cluster:10.22.11.14:CPUpool-pool:CPU:/lpar2rrd-cgi/detail.sh?host=10.22.11.10&server=10.22.11.14&lpar=pool&item=pool&entitle=0&gui=1&none=none::1615849380:V:
        if ( $type eq "V" ) {
          $hasVMware ||= 1;

          # $vclusters{$hmc}{$srv} = 1;
          $vclusters{$srv} = $hmc;
          if ( $pool eq "hreports" ) {
            $hmc = ( $url =~ /^([^\/]*)/ )[0];
          }
          else {
            $hmc = ( $url =~ /host=([^&]*)/ )[0];
          }
          ( undef, my $vcenter_ip ) = split "host=", $url;
          $vcenter_ip =~ s/\&server=.*//;
          $server_in_vcenter{$srv} = $vcenter_ip;

        }
        elsif ( !exists $times{$srv}{timestamp}{$hmc} ) {
          $times{$srv}{timestamp}{$hmc} = $timestamp;
        }
        if ( $type eq "P" ) {
          $hasPower ||= 1;
        }
        if ( !$times{$srv}{"active"} ) {
          $times{$srv}{"active"} = 1;
        }
        $times{$srv}{"removed"}{$hmc} = 0;
        if ($type) {
          $times{$srv}{type} = $type;
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
        push @{ $stree{$srv}{$hmc} }, [ $txt, $url, $pool ];
        if ( $url =~ /item=(sh)?pool/ ) {
          my $poolname = ( split " : ", $txt )[1];
          $poolname ||= "CPU pool";

          #$pools{$poolname} = $url;
          #my %poolname = $poolname{$url};
          #print "$url\n";
          my $pools = $url;
          $pools =~ s/.*lpar=//g;
          $pools =~ s/&item.*//g;
          $inventory{$srv}{"POOL"}{$pools}{"NAME"} = $poolname;
          $inventory{$srv}{"POOL"}{$pools}{"URL"}  = $url;

          #push @{ $inventory{$srv}{"POOL"} }, %pools;
          #$inventory{$srv}{"POOL"}[-1]{$poolname} = $url;
          $inventory{$srv}{TIMESTAMP}{$timestamp} = $hmc;
          $inventory{$srv}{TYPE} = $type;

          ### total pool
          $inventory{$srv}{"POOL"}{pool_total}{"NAME"} = "Total";
          if ( $poolname eq "CPU pool" ) {
            $inventory{$srv}{"POOL"}{pool_total}{"URL"} = $url;
          }
          $inventory{$srv}{TIMESTAMP}{$timestamp} = $hmc;
          $inventory{$srv}{TYPE} = $type;

        }
        next;
      };
      "L" eq $val[0] && do {
        my ( $hmc, $srv, $atxt, $txt, $url ) =
          ( $val[1], $val[2], $val[3], $val[4], $val[5] );
        my $jump = 0;
        foreach my $i ( keys %hmc_server_del ) {
          if ( $hmc_server_del{$i}{HMC} eq $val[1] && $hmc_server_del{$i}{SERVER} eq $val[2] ) {
            $jump = 1;
            last;
          }
        }
        if ( $jump == 1 ) { next; }
        $atxt = urldecode($atxt);
        push @{ $lstree{$srv}{$hmc} }, [ $txt, $url, $atxt ];
        if ( $hmc eq "no_hmc" ) {
          $times{$srv}{timestamp}{$hmc}    = 999;
          $inventory{$srv}{TIMESTAMP}{999} = $hmc;
          $inventory{$srv}{TYPE}           = 'L';
          if ( defined $val[8] && defined $val[9] ) {
            $inventory{$srv}{TYPE2} = "$val[8]:$val[9]";
          }
        }
        else {
          push @{ $lhtree{$hmc}{$srv} }, [ $txt, $url, $atxt ];
        }
        if ( $hmc eq "no_hmc" && !$times{$srv}{"active"} ) {
          $times{$srv}{"active"} = 1;
        }
        push @lnames, $txt;
        if ( $hmc =~ /cluster_/ ) {

          #print "$hmc\n";
          #print "$url\n";
          $url =~ s/server=.*&lpar/server=$hmc&lpar/g;
        }
        $inventory{$srv}{"LPAR"}{ urldecode( $val[3] ) }{URL}  = $url;
        $inventory{$srv}{"LPAR"}{ urldecode( $val[3] ) }{NAME} = $txt;
        next;
      };
    };
  }

  #close($SKEL);
}

sub urlencode {
  my $s = shift;

  #$s =~ s/ /+/g;
  #$s =~ s/([^A-Za-z0-9\+-_])/sprintf("%%%02X", ord($1))/seg;
  $s =~ s/([^a-zA-Z0-9_.!~*()'\''-])/sprintf("%%%02X", ord($1))/ge;
  return $s;
}

sub urldecode {
  my $s = shift;

  #$s =~ s/\%([A-Fa-f0-9]{2})/pack('C', hex($1))/seg;
  #$s =~ s/\+/ /g;
  $s =~ s/\%([A-Fa-f0-9]{2})/pack('C', hex($1))/seg;
  return $s;
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

###################################################### POWER start !!!

sub get_live_lpars {

  my @wrkdir_all = <$wrkdir/*>;

  #print "@wrkdir_all\n";
  foreach my $server_all (@wrkdir_all) {
    my $server = basename($server_all);
    if ( -l $server_all )        { next; }
    if ( !-d $server_all )       { next; }
    if ( $server =~ /^--HMC--/ ) { next; }
    my $server_space = $server;
    if ( $server =~ m/ / ) {
      $server_space = "\"" . $server . "\"";    # it must be here to support space with server names
    }

    my @hmcdir_all = <$wrkdir/$server_space/*>;

    #print "@hmcdir_all\n";
    foreach my $hmc_all (@hmcdir_all) {

      #my $server_space = $server;
      #if ( $server =~ m/ / ) {
      #$server_space = "\"".$server."\""; # it must be here to support space with server names
      #}
      my $no_name   = "";
      my $hmc       = basename($hmc_all);
      my $hmc_space = $hmc;
      if ( $hmc =~ m/ / ) {
        $hmc_space = "\"" . $hmc . "\"";    # it must be here to support space with server names
      }
      my @lpars_dir_all = <$wrkdir/$server_space/$hmc_space/*>;

      #print "@lpars_dir_all\n";
      my $cpu_cfg = "$hmc_all/cpu.cfg";

      if ( -e "$hmc_all/pool_list.txt" && -e "$hmc_all/cpu-pools-mapping.txt" ) {
        my $find_pool_list = grep {/$hmc_all/} @pool_list;
        if ( !$find_pool_list ) {
          push( @pool_list, "$hmc_all/pool_list.txt,$hmc_all/cpu-pools-mapping.txt,$server\n" );    ### list pool_list.txt
        }
      }

      my @lines_config;
      if ( -e $cpu_cfg ) {
        open( my $FH, "< $cpu_cfg" ) || error( "Cannot read $cpu_cfg: $!" . __FILE__ . ":" . __LINE__ ) && next;
        @lines_config = <$FH>;
        close($FH);
      }
      else { next; }

      if ( -z $cpu_cfg ) { next; }

      foreach my $lpars_dir (@lpars_dir_all) {

        #print $lpars_dir . "\n";
        my $lpar = basename($lpars_dir);
        if ( -l $lpars_dir )                          { next; }
        if ( -d $lpars_dir )                          { next; }
        if ( $lpar !~ /\.rrm$/ && $lpar !~ /\.rrh$/ ) { next; }
        if ( $lpar =~ /^pool\.rrm/ || $lpar =~ /^pool\.rrh/ ) {
          my $lpar_mtimestamp = ( stat("$lpars_dir") )[9];
          my $lpar_name       = $lpar;
          $lpar =~ s/.rrm$//g;
          $lpar =~ s/.rrh$//g;
          push( @pool, "$server_all/XORUX/$lpar/$lpar_mtimestamp, $server, $hmc, $lpar_mtimestamp, $hmc_all, $lpar_name\n" );
          next;
        }
        if ( $lpar =~ /pool/ || $lpar =~ /Pool/ || $lpar =~ /^mem\.rrm$/ ) { next; }
        my $lpar_mtimestamp = ( stat("$lpars_dir") )[9];

        #if ( $lpar_mtimestamp < $start_time ) { next; }    ## last modified time of lpar must be higher then start time of report
        #$lpar =~ s/&&1/\//g;
        my $lpar_name = $lpar;

        #print "$lpar_name\n";
        $lpar =~ s/.rrm$//g;
        $lpar =~ s/.rrh$//g;

        #print "$lpar\n";
        if ( $lpar =~ /&&1/ ) {
          my $replace = $lpar;
          chomp $replace;
          $replace =~ s/^\s+//;
          $replace =~ s/\s+$//;
          $replace =~ s/&&1/\//g;

          #print "$replace\n";
          push( @replace_file, "$replace" );
          $lpar = $replace;
        }

        #print "$lpar\n";
        my $v_cpu = "";    ## virtual cpu
        my $lpar_line;
        if ( ($lpar_line) = grep {/^lpar_name=$lpar,/} @lines_config ) {
          $lpar_line =~ s/.+curr_procs=//g;
          my @curr_procs = split( ",", $lpar_line );
          $v_cpu = $curr_procs[0];
          if ($DEBUG_HEATMAP) { print "DEBUG_HEATMAP: curr_procs : $hmc : $server : $lpar : $v_cpu\n"; }
        }
        else {
          next;
          $v_cpu = "NA";
        }

        #print "$lpar\n";
        my $replace_lpar = $lpar;
        $replace_lpar =~ s/\//&&1/g;
        my $special_name = 0;
        if ( $replace_lpar =~ /&&1/ ) {
          $special_name = 1;
        }
        if ( -f "$wrkdir/$server/$hmc/cpu.cfg-$replace_lpar" ) {
          my $file = "$wrkdir/$server/$hmc/cpu.cfg-$replace_lpar";
          open( my $FH, "< $file" ) || error( "Cannot read $file: $!" . __FILE__ . ":" . __LINE__ ) && next;
          my @data = <$FH>;
          close($FH);

          my $test_running = grep {/[Rr]unning/} @data;
          if ($DEBUG_HEATMAP) { print "DEBUG_HEATMAP: test running : $hmc : $server : $lpar : $test_running\n"; }
          if ( !$test_running ) {
            if ($special_name) {
              pop @replace_file;
            }
            next;    ### rules for version 5.00
          }
        }
        push( @test, "$server_all/XORUX/$lpar/$lpar_mtimestamp, $v_cpu, $server, $hmc, $lpar_mtimestamp, $hmc_all, $lpar_name\n" );

        #print "$lpar\n";
      }
    }
  }
  ##### testing latest rrd file #####
  my @rrd_files_s;
  my @test_s = reverse sort @test;

  #print "@test_s";
  my $last_found = "";

  #print $last_found . "\n";
  #my $test_pom = 0; # test variable

  my $last_ts = 0;
  my $check;
  foreach my $line (@test_s) {
    my ( $rrd_file, $virtual_cpu, $server, $hmc, $timestamp, $hmc_path, $lpar ) = split( ", ", $line );
    $rrd_file =~ s/$timestamp//g;
    my $found = "$rrd_file";

    #print $line ."\n";
    #print "$rrd_file\n";
    if ( $found eq $last_found ) {
      next;
    }

    #if ($test_pom==10){
    #  last;
    #}
    #$test_pom++;
    $last_found = $found;
    push( @rrd_files_s, $line );
    chomp $lpar;

  }
  my @rrd_files = sort @rrd_files_s;
  return @rrd_files;
}

sub set_live_inventory {
  $count_lpars = 0;
  my @name_lpars;
  my @name_servers;
  my @inventory_server;
  my $check = 0;
  foreach my $line ( get_live_lpars() ) {
    chomp $line;

    #print $line . "\n";
    my ( $rrd_file, $virtual_cpu, $server, $hmc, $timestamp, $hmc_path, $lpar ) = split( ", ", $line );
    $rrd_file =~ s/XORUX.+/$hmc\/$lpar/g;
    my $rrd_name = basename($rrd_file);
    $rrd_name =~ s/.rrm$//g;
    $rrd_name =~ s/.rrh$//g;
    push( @name_servers, $server );

    #$count_lpars++;
    #print "$rrd_name\n";
    push( @name_lpars, "$rrd_name,$server\n" );
  }

  #if ($count_lpars == 0){
  #  error("Set correct path to rrdtool binary, it does not exist here: $rrdtool");
  #  exit;

  #}
  foreach my $server ( keys %inventory ) {
    foreach my $name (@name_servers) {
      if ( "$name" eq "$server" ) {

        #print $server . "\n";
        $check = 1;
        last;
      }

    }
    if ( $check == 0 ) {
      delete $inventory{$server};
      next;
    }

    foreach my $lpar ( keys %{ $inventory{$server}{LPAR} } ) {
      foreach my $name (@name_lpars) {
        my ( $lpar_name, $server_name ) = split( ",", $name );
        chomp $lpar_name;
        chomp $server_name;

        #print "$inventory{$server}{LPAR}{$lpar}{NAME}\n";
        #print $name . "\n";
        if ( "$lpar" eq "$lpar_name" ) {

          #print $lpar. " " .$lpar_name . "\n";
          #print "$server a $server_name\n";
          if ( "$server" eq "$server_name" ) {

            #print "$lpar\n";
            #print "$name\n";
            $check = 2;
            last;
          }
        }
      }
      foreach my $special_name (@replace_file) {
        if ( "$lpar" eq "$special_name" ) {
          $check = 2;
          last;
        }
      }
      if ( !( $check == 2 ) ) {
        delete( $inventory{$server}{LPAR}{$lpar} );

        #$check = 0;
        next;
      }
      $check = 0;
    }
    $check = 0;
  }
}

sub get_table_cpu_lpar_power {
  use POSIX qw(ceil);

  #my $const = 2.6;
  my $count_row = 1;
  my $nasob     = 1;
  if ( $count_lpars == 0 ) { return "" }
  my $cell_size    = ( $height * $width ) / $count_lpars;
  my $table_values = "<table class =\" lparsearch tablesorter\" data-sortby=\"3\">";
  $table_values = $table_values . "<thead><tr><th class = \"sortable\" title=\"Server\" nowrap=\"\">Server</th>\n";
  $table_values = $table_values . "<th class = \"sortable\" title=\"Lpar\" nowrap=\"\">Lpar</th>\n";
  $table_values = $table_values . "<th class = \"sortable\" title=\"Utilization %\" nowrap=\"\">Utilization %</th>\n";
  $table_values = $table_values . "<th class = \"sortable\" title=\"Color\" nowrap=\"\"><center>Color</center></th></tr></thead><tbody>\n";

  #my $td_height = ceil(sqrt($cell_size/$const));
  #my $td_width = ceil($td_height * $const);
  my $td_width     = ceil( sqrt($cell_size) );
  my $td_height    = $td_width;
  my $new_row      = 0;
  my $count_column = 1;

  if ( $td_width < 10 ) {
    $td_width  = 10;
    $td_height = 10;
  }
  if ( $td_width > 42 ) {
    $td_width  = 42;
    $td_height = 42;
  }

  $td_height = $td_height - 2;
  ################
  #my $i = 0;
  my $style = " .content_power { height:" . "$td_height" . "px" . "; width:" . "$td_height" . "px" . ";} h3 {text-align:center;}";
  my $table = "<table>\n<tbody>\n<tr>\n";

  foreach my $server ( sort keys %inventory ) {
    foreach my $lpar ( sort { lc $inventory{$server}{LPAR}{$a}{NAME} cmp lc $inventory{$server}{LPAR}{$b}{NAME} || $inventory{$server}{LPAR}{$a}{NAME} cmp $inventory{$server}{LPAR}{$b}{NAME} } keys %{ $inventory{$server}{LPAR} } ) {
      if ( defined $inventory{$server}{LPAR}{$lpar}{CPU} && defined $inventory{$server}{LPAR}{$lpar}{CURR_PROCS} ) {
        if ( ( $new_row + $td_width ) > $width ) {
          $table   = $table . "</tr>\n<tr>\n";
          $new_row = 0;
        }
        my $percent_util;
        my $util = $inventory{$server}{LPAR}{$lpar}{CPU};
        my $curr = $inventory{$server}{LPAR}{$lpar}{CURR_PROCS};
        if ($DEBUG_HEATMAP) { print "DEBUG_HEATMAP: CPU&CURR_PROCS $server : $lpar : CPU $util : CURR_PROCS $curr\n"; }
        if ( "$util" eq "-nan" || "$util" eq "nan" || $util =~ /nan/ || "$util" eq "NaNQ" || $util =~ /NAN/ || $util =~ /NaN/ || $curr eq 0 || !isdigit($util) || !isdigit($curr) ) {
          $percent_util = "nan";
        }
        else {
          $percent_util = ceil( ( $util / $inventory{$server}{LPAR}{$lpar}{CURR_PROCS} ) * 100 ) . "%";
        }
        my $class = get_class( $inventory{$server}{LPAR}{$lpar}{CPU}, $inventory{$server}{LPAR}{$lpar}{CURR_PROCS} );
        my $color = $class_color{$class};
        $table = $table . "<td class=\"$class\">\n<a href=" . '"' . "$inventory{$server}{LPAR}{$lpar}{URL}" . '"' . "><div title =" . '"' . "$server : $inventory{$server}{LPAR}{$lpar}{NAME}" . " : " . $percent_util . '"' . "class=" . '"' . "content_power" . '"' . "></div>\n</a>\n</td>\n";
        my $val = "";
        if ( $percent_util eq "nan" ) {
          $val = $percent_util;
        }
        else {
          $val = ceil( ( $util / $inventory{$server}{LPAR}{$lpar}{CURR_PROCS} ) * 100 );
        }
        $table_values = $table_values . "<tr><td>$server</td><td>" . "<a href=" . '"' . "$inventory{$server}{LPAR}{$lpar}{URL}" . '"' . ">" . $inventory{$server}{LPAR}{$lpar}{NAME} . "</a></td><td>$val</td><td><div style=\"height:15px;width:15px;background-color:$color; margin: auto;\"></div></td></tr>\n";
        $new_row      = $td_width + $new_row;
      }
      else {
        next;
      }
    }
  }

  #print $table_power . "\n";
  $table_values = $table_values . "</tbody></table>";
  $table        = $table . "</tr>\n</tbody>\n</table><br>\n";

  #$print "$table_power\n";
  #print "$count_lpars\n";
  my $tb_and_style = "$table" . "@" . "$style" . "@" . $table_values;
  return "$tb_and_style";
}

sub get_table_mem_lpar_power {
  use POSIX qw(ceil);
  my $count_row = 1;
  my $nasob     = 1;
  if ( $count_mem_lpars_power == 0 ) { return "" }
  $count_mem_lpars_power = $count_lpars;
  my $cell_size    = ( $height * $width ) / $count_mem_lpars_power;
  my $td_width     = ceil( sqrt($cell_size) );
  my $td_height    = $td_width;
  my $new_row      = 0;
  my $count_column = 1;

  if ( $td_width < 10 ) {
    $td_width  = 10;
    $td_height = 10;
  }
  if ( $td_width > 42 ) {
    $td_width  = 42;
    $td_height = 42;
  }

  $td_height = $td_height - 2;
  my $table        = "<table>\n<tbody>\n<tr>\n";
  my $table_values = "<table class =\"lparsearch tablesorter\" data-sortby=\"5\">";
  $table_values = $table_values . "<thead><tr><th class = \"sortable\" title=\"Server\" nowrap=\"\">Server</th>\n";
  $table_values = $table_values . "<th class = \"sortable\" title=\"Lpar\" nowrap=\"\">Lpar</th>\n";
  $table_values = $table_values . "<th class = \"sortable\" title=\"Paging IN kb/s\" nowrap=\"\">Paging IN kb/s</th>\n";
  $table_values = $table_values . "<th class = \"sortable\" title=\"Paging OUT kb/s\" nowrap=\"\">Paging OUT kb/s</th>\n";
  $table_values = $table_values . "<th class = \"sortable\" title=\"Utilization %\" nowrap=\"\">Utilization %</th>\n";
  $table_values = $table_values . "<th class = \"sortable\" title=\"Color\" nowrap=\"\"><center>Color</center></th></tr></thead><tbody>\n";

  foreach my $server ( sort keys %inventory ) {
    foreach my $lpar ( sort { lc $inventory{$server}{LPAR}{$a}{NAME} cmp lc $inventory{$server}{LPAR}{$b}{NAME} || $inventory{$server}{LPAR}{$a}{NAME} cmp $inventory{$server}{LPAR}{$b}{NAME} } keys %{ $inventory{$server}{LPAR} } ) {
      if ( defined $inventory{$server}{LPAR}{$lpar}{MEMORY} ) {
        if ( ( $new_row + $td_width ) > $width ) {
          $table   = $table . "</tr>\n<tr>\n";
          $new_row = 0;
        }
        my $percent_util;
        my $paging     = "";
        my $util       = $inventory{$server}{LPAR}{$lpar}{MEMORY};
        my $url        = $inventory{$server}{LPAR}{$lpar}{URL};
        my $paging_in  = "";
        my $paging_out = "";
        my $paging_red = "";

        #$url =~ s/item=lpar/item=mem/g;
        if ( "$util" eq "-nan" || "$util" eq "nan" || $util =~ /nan/ || "$util" eq "NaNQ" || $util =~ /NAN/ || $util =~ /NaN/ || !isdigit($util) ) {
          $percent_util = "nan";
          $inventory{$server}{LPAR}{$lpar}{MEMORY} = "nan";
        }

        else {
          $percent_util = ceil( $inventory{$server}{LPAR}{$lpar}{MEMORY} ) . "%";
          if ( defined $inventory{$server}{LPAR}{$lpar}{PAGING_IN} && defined $inventory{$server}{LPAR}{$lpar}{PAGING_OUT} ) {
            if ( $inventory{$server}{LPAR}{$lpar}{MEMORY} >= 91 && ( $inventory{$server}{LPAR}{$lpar}{PAGING_IN} > $HEATMAP_MEM_PAGING_MAX || $inventory{$server}{LPAR}{$lpar}{PAGING_OUT} > $HEATMAP_MEM_PAGING_MAX ) ) {
              $paging_red = 1;
            }
            elsif ( $inventory{$server}{LPAR}{$lpar}{MEMORY} >= 91 ) {
              $paging_red = 0;
            }
            else {
              $paging_red = "";
            }
            $paging_in  = "paging in ";
            $paging_in  = "$paging_in" . "$inventory{$server}{LPAR}{$lpar}{PAGING_IN}" . "kB/s";
            $paging_out = "paging out ";
            $paging_out = "$paging_out" . "$inventory{$server}{LPAR}{$lpar}{PAGING_OUT}" . "kB/s";
            $paging     = " : $paging_in : $paging_out";
          }
        }
        if ( !defined $inventory{$server}{LPAR}{$lpar}{PAGING_IN} )  { $inventory{$server}{LPAR}{$lpar}{PAGING_IN}  = ""; }
        if ( !defined $inventory{$server}{LPAR}{$lpar}{PAGING_OUT} ) { $inventory{$server}{LPAR}{$lpar}{PAGING_OUT} = ""; }
        my $class = get_percent_to_color( $inventory{$server}{LPAR}{$lpar}{MEMORY}, $paging_red );
        my $color = $class_color{$class};
        $table = $table . "<td class=\"$class\">\n<a href=" . '"' . "$url" . '"' . "><div title =" . '"' . "$server : $inventory{$server}{LPAR}{$lpar}{NAME}" . " : " . $percent_util . "$paging" . '"' . "class=" . '"' . "content_power" . '"' . "></div>\n</a>\n</td>\n";

        $percent_util =~ s/\%//g;
        $table_values = $table_values . "<tr><td>$server</td><td>" . "<a href=" . '"' . "$inventory{$server}{LPAR}{$lpar}{URL}" . '"' . ">" . $inventory{$server}{LPAR}{$lpar}{NAME} . "</a></td><td>$inventory{$server}{LPAR}{$lpar}{PAGING_IN}</td><td>$inventory{$server}{LPAR}{$lpar}{PAGING_OUT}</td><td>$percent_util</td><td><div style=\"height:15px;width:15px;background-color:$color; margin: auto;\"></div></td></tr>\n";

        $new_row = $td_width + $new_row;
      }
      else { next; }
    }
  }
  $table        = $table . "</tr>\n</tbody>\n</table><br>\n";
  $table_values = $table_values . "</tbody></table>";
  return "$table" . "@" . "$table_values";
}

sub get_table_cpu_pool_power {
  use POSIX qw(ceil);
  my $count_row = 1;
  my $nasob     = 1;

  #print "$count_pools\n";
  if ( $count_pools == 0 ) { return "" }
  my $cell_size    = ( $height * $width ) / $count_pools;
  my $td_width     = ceil( sqrt($cell_size) );
  my $td_height    = $td_width;
  my $new_row      = 0;
  my $count_column = 1;

  if ( $td_width < 10 ) {
    $td_width  = 10;
    $td_height = 10;
  }
  if ( $td_width > 42 ) {
    $td_width  = 42;
    $td_height = 42;
  }

  $td_height = $td_height - 2;
  ################
  #my $i = 0;

  ## check NAME POOL EMPTY
  foreach my $server ( keys %inventory ) {
    foreach my $pool ( keys %{ $inventory{$server}{POOL} } ) {
      if ( !defined $inventory{$server}{POOL}{$pool}{NAME} ) {
        $inventory{$server}{POOL}{$pool}{NAME} = "$pool";
      }
    }
  }

  my $table        = "<table>\n<tbody>\n<tr>\n";
  my $style        = " .content_pool_power { height:" . "$td_height" . "px" . "; width:" . "$td_height" . "px" . ";} h3 {text-align:center;}";
  my $table_values = "<table class =\"lparsearch tablesorter\" data-sortby=\"3\">";
  $table_values = $table_values . "<thead><tr><th class = \"sortable\" title=\"Server\" nowrap=\"\">Server</th>\n";
  $table_values = $table_values . "<th class = \"sortable\" title=\"Pool\" nowrap=\"\">Pool</th>\n";
  $table_values = $table_values . "<th class = \"sortable\" title=\"Utilization %\" nowrap=\"\">Utilization %</th>\n";
  $table_values = $table_values . "<th class = \"sortable\" title=\"Color\" nowrap=\"\"><center>Color</center></th></tr></thead><tbody>\n";

  foreach my $server ( sort keys %inventory ) {
    foreach my $pool ( sort { lc $inventory{$server}{POOL}{$a}{NAME} cmp lc $inventory{$server}{POOL}{$b}{NAME} || $inventory{$server}{POOL}{$a}{NAME} cmp $inventory{$server}{POOL}{$b}{NAME} } keys %{ $inventory{$server}{POOL} } ) {
      if ( defined $inventory{$server}{POOL}{$pool}{CPU} && defined $inventory{$server}{POOL}{$pool}{URL} ) {
        if ( ( $new_row + $td_width ) > $width ) {
          $table   = $table . "</tr>\n<tr>\n";
          $new_row = 0;
        }
        my $percent_util;
        my $util = $inventory{$server}{POOL}{$pool}{CPU};
        if ( "$util" eq "-nan" || "$util" eq "nan" || $util =~ /nan/ || "$util" eq "NaNQ" || $util =~ /NAN/ || $util =~ /NaN/ || !isdigit($util) ) {
          $percent_util = "nan";
        }
        else {
          $percent_util = ceil( $inventory{$server}{POOL}{$pool}{CPU} ) . "%";
        }
        my $class = get_percent_to_color($util);
        my $color = $class_color{$class};
        $table = $table . "<td class=\"$class\">\n<a href=" . '"' . "$inventory{$server}{POOL}{$pool}{URL}" . '"' . "><div title =" . '"' . "$server : $inventory{$server}{POOL}{$pool}{NAME}" . " : " . $percent_util . '"' . "class=" . '"' . "content_pool_power" . '"' . "></div>\n</a>\n</td>\n";

        $percent_util =~ s/\%//g;
        $table_values = $table_values . "<tr><td>$server</td><td>" . "<a href=" . '"' . "$inventory{$server}{POOL}{$pool}{URL}" . '"' . ">" . $inventory{$server}{POOL}{$pool}{NAME} . "</a></td><td>$percent_util</td><td><div style=\"height:15px;width:15px;background-color:$color; margin: auto;\"></div></td></tr>\n";

        $new_row = $td_width + $new_row;
      }
      else { next; }
    }
  }
  $table        = $table . "</tr>\n</tbody>\n</table><br>\n";
  $table_values = $table_values . "</tbody></table>";
  my $tb_and_style = "$table" . "@" . "$style" . "@" . "$table_values";
  return "$tb_and_style";
}

sub set_curr_procs {
  foreach my $line ( get_live_lpars() ) {
    chomp $line;

    #print "$line\n";
    if ($DEBUG_HEATMAP) { print "DEBUG_HEATMAP: set_curr_procs $line\n"; }
    my ( $rrd_file, $virtual_cpu, $server, $hmc, $timestamp, $hmc_path, $lpar ) = split( ", ", $line );
    $rrd_file =~ s/XORUX.+/$hmc\/$lpar/g;
    my $rrd_name = basename($rrd_file);
    $rrd_name =~ s/.rrm$//g;
    $rrd_name =~ s/.rrh$//g;
    $rrd_name =~ s/&&1/\//g;

    #print "$rrd_name\n";
    foreach my $Server ( keys %inventory ) {
      if ( "$server" eq "$Server" ) {
        foreach my $Lpar ( keys %{ $inventory{$Server}{LPAR} } ) {
          if ( "$rrd_name" eq "$Lpar" ) {

            #print "$rrd_name\n";
            if ($DEBUG_HEATMAP) { print "DEBUG_HEATMAP: set_curr_procs $Server : $Lpar : $virtual_cpu\n"; }
            $inventory{$Server}{LPAR}{$Lpar}{CURR_PROCS} = $virtual_cpu;
          }

          #foreach my $special_name (@replace_file){
          #  if ("$Lpar" eq "$special_name"){
          #    $inventory{$Server}{LPAR}{$Lpar}{CURR_PROCS} = $virtual_cpu;
          #    last;
          #  }
          #}
        }
      }
    }
  }
}

sub set_utilization_cpu_power {

  #print get_live_lpars();
  #print Dumper \%inventory;
  foreach my $line ( get_live_lpars() ) {
    chomp $line;
    my $exclude = 0;
    my ( $rrd_file, $virtual_cpu, $server, $hmc, $timestamp, $hmc_path, $lpar ) = split( ", ", $line );

    #print "$rrd_file\n";
    #print "$rrd_file\n";
    $rrd_file =~ s/XORUX.+/$hmc\/$lpar/g;
    my $rrd_name = basename($rrd_file);
    $rrd_name =~ s/.rrm$//;
    $rrd_name =~ s/.rrh$//;
    $rrd_name =~ s/&&1/\//g;
    if ( defined $HEATMAP_EXCLUDE_CPU ) {
      my @exlude_lpar = split( ":", $HEATMAP_EXCLUDE_CPU );
      foreach my $exludes_lpar (@exlude_lpar) {
        chomp $exludes_lpar;
        $exludes_lpar =~ s/^\s+|\s+$//g;
        if ( $rrd_name eq $exludes_lpar && defined $inventory{$server}{LPAR}{$rrd_name} ) {

          #$inventory{$server}{LPAR}{$rrd_name}{CPU} = "NaN";
          $exclude = 1;
          last;
        }
      }
    }
    if ( $exclude == 1 ) { next; }

    #print $rrd_name . "\n";
    my $orginal_file = $rrd_file;
    $rrd_file =~ s/:/\\:/g;
    my $rrd_out_name = "graph.png";
    my $answer;
    if ($DEBUG_HEATMAP) { print "DEBUG_HEATMAP: set utilization lpar cpu: $rrd_name : $rrd_file : $rrd_out_name : $start_time : $end_time\n"; }
    eval {
      RRDp::cmd qq(graph "$rrd_out_name"
    "--start" "$start_time"
    "--end" "$end_time"
    "--step=60"
    "DEF:cur=$rrd_file:curr_proc_units:AVERAGE"
    "DEF:ent=$rrd_file:entitled_cycles:AVERAGE"
    "DEF:cap=$rrd_file:capped_cycles:AVERAGE"
    "DEF:uncap=$rrd_file:uncapped_cycles:AVERAGE"
    "CDEF:tot=cap,uncap,+"
    "CDEF:util=tot,ent,/,$cpu_max_filter,GT,UNKN,tot,ent,/,IF"
    "CDEF:utiltot=util,cur,*"
    "PRINT:utiltot:AVERAGE:Utilization in CPU cores %2.2lf"
    );
      $answer = RRDp::read;
    };
    if ($@) {
      if ( $@ =~ "ERROR" ) {
        error("Rrrdtool error : $@");
        next;
      }
    }
    my $aaa = $$answer;

    #if ( $aaa =~ /NaNQ/ ) { next; }
    ( undef, my $utilization_in_cores ) = split( "\n", $aaa );
    $utilization_in_cores =~ s/Utilization in CPU cores\s+//;

    #$utilization_in_cores = "-nan";
    #if (!isdigit($utilization_in_cores)){
    #  foreach my $hmc_act (@hmc_list){
    #    if ($hmc_act eq $hmc){next;}
    #    $utilization_in_cores = get_value_from_rrd("LPAR", $start_time, $end_time, $orginal_file, $rrd_out_name,$hmc,$hmc_act,$utilization_in_cores);
    #    if (isdigit($utilization_in_cores)){
    #      last;
    #    }
    #  }
    #}
    if ($DEBUG_HEATMAP) { print "DEBUG_HEATMAP: set utilization lpar cpu: $rrd_name : $rrd_file $utilization_in_cores\n"; }

    #print $utilization_in_cores . "\n";
    foreach my $Server ( keys %inventory ) {
      if ( $server eq $Server ) {
        foreach my $Lpar ( keys %{ $inventory{$Server}{LPAR} } ) {
          if ( "$Lpar" eq "$rrd_name" ) {
            $inventory{$Server}{LPAR}{$Lpar}{CPU} = $utilization_in_cores;
            $count_lpars++;
          }

          #foreach my $special_name (@replace_file){
          #  if ("$Lpar" eq "$special_name"){
          #    if (defined $inventory{$Server}{LPAR}{$Lpar}{CPU}){next;}
          #    $inventory{$Server}{LPAR}{$Lpar}{CPU} = $utilization_in_cores;
          #    $count_lpars++;
          #    last;
          #  }
          #}
        }
      }
    }
  }
  print "heatmap        : (Power) set cpu utilization for $count_lpars lpars\n";
}

sub get_live_mem_lpars_power {
  my @wrkdir_all = <$wrkdir/*>;
  my @mem;    # os agent
  my @test_mem;
  my $last_lpar      = "";
  my $last_server    = "";
  my $last_timestamp = 0;
  foreach my $server_all (@wrkdir_all) {
    my $server = basename($server_all);

    #print "$server\n";
    if ( -l $server_all )        { next; }
    if ( !-d $server_all )       { next; }
    if ( $server =~ /^--HMC--/ ) { next; }
    my $server_space = $server;
    if ( $server =~ m/ / ) {
      $server_space = "\"" . $server . "\"";    # it must be here to support space with server names
    }
    my @hmcdir_all = <$wrkdir/$server_space/*>;
    foreach my $hmc_all (@hmcdir_all) {
      my $hmc = basename($hmc_all);

      #print "$hmc_all\n";
      my $hmc_space = $hmc;
      if ( $hmc =~ m/ / ) {
        $hmc_space = "\"" . $hmc . "\"";    # it must be here to support space with server names
      }
      my @lpars_dir_all = <$wrkdir/$server_space/$hmc_space/*>;
      foreach my $lpars_dir (@lpars_dir_all) {
        if ( -d $lpars_dir && !( $lpars_dir =~ /NMON/ ) ) {

          #print $lpars_dir . "\n";
          my $lpar = basename($lpars_dir);

          #print "$lpar\n";
          $lpar =~ s/ /\\ /g;

          #print "$lpar\n";
          my @os_agent = <$wrkdir/$server_space/$hmc_space/$lpar/*>;

          #print "@os_agent\n";
          my $find_file = grep {/mem.mmm/} @os_agent;
          if ($find_file) {
            foreach my $file (@os_agent) {

              #print "$file\n";
              my $mem_file = basename($file);
              if ( "$mem_file" eq "mem.mmm" ) {
                my $mem_timestamp = ( stat("$file") )[9];
                $lpar =~ s/&&1/\//g;

                #print "$file\n";
                push( @mem, "$server,$lpar,$mem_file,$mem_timestamp,$file" );
              }
            }
          }
          else {
            my $nmon = "";
            $nmon = "$lpars_dir--NMON--";

            #print $nmon . "\n";
            my $name_nmon = basename($nmon);
            $name_nmon =~ s/ /\\ /g;

            #print $name_nmon . "\n";
            my @os_agent_nmon = <$wrkdir/$server_space/$hmc_space/$name_nmon/*>;
            my $test          = grep {/mem.mmm/} @os_agent_nmon;
            if ($test) {

              #my $name_nmon = basename($nmon);
              #$name_nmon =~ s/ /\\ /g;
              #my @os_agent_nmon = <$wrkdir/$server/$hmc/$name_nmon/*>;
              #print "ahoj\n";
              foreach my $file (@os_agent_nmon) {
                my $mem_file = basename($file);

                #print $mem_file . "\n";
                if ( "$mem_file" eq "mem.mmm" ) {
                  my $mem_timestamp = ( stat("$file") )[9];
                  $name_nmon =~ s/&&1/\//g;
                  $name_nmon =~ s/--NMON--//g;
                  push( @mem, "$server,$name_nmon,$mem_file,$mem_timestamp,$file" );
                }
              }
            }

          }
        }
      }
    }
  }
  my @sort_array = sort @mem;
  foreach my $line (@sort_array) {

    #print "$line\n";
    my ( $server, $lpar, $mem, $mem_timestamp, $path ) = split( ",", $line );

    #print "$server a $mem a $mem_timestamp a $path\n";
    if ( $server eq $last_server ) {
      if ( $last_lpar eq $lpar ) {

        #print "$last_mem $last_timestamp a $mem $mem_timestamp\n";
        if ( $last_timestamp == $mem_timestamp ) {

          #print "$server a $path\n";
          #print "odstranil\n";
          pop(@test_mem);
        }
        else {
          next;
        }
      }
    }
    $last_lpar      = $lpar;
    $last_server    = $server;
    $last_timestamp = $mem_timestamp;

    #print "$path,$server,$mem pridal\n";
    push( @test_mem, "$path,$server,$mem,$lpar" );
  }
  return @test_mem;
}

sub set_utilization_mem_power {
  $count_mem_lpars_power = 0;
  my @lpar = get_live_mem_lpars_power();
  foreach my $line (@lpar) {
    my ( $path, $server_name, $mem, $lpar ) = split( ",", $line );
    my $mem_name = $mem;

    #print $path . "\n";
    #my $lpar = $line;
    $mem_name =~ s/.mmm//g;

    #print $server_name . "\n";
    $lpar =~ s/\\//g;
    foreach my $server ( keys %inventory ) {
      if ( "$server_name" eq "$server" ) {
        foreach my $lpar_name ( keys %{ $inventory{$server}{LPAR} } ) {

          #print "$lpar_name a $lpar\n";
          if ( "$lpar_name" eq "$lpar" ) {
            $path =~ s/:/\\:/g;

            #print $path . "\n";
            my $rrd_out_name = "graph.png";
            my $answer;
            eval {
              RRDp::cmd qq(graph "$rrd_out_name"
            "--start" "$start_time"
            "--end" "$end_time"
            "--step=60"
            "DEF:used=$path:nuse:AVERAGE"
            "DEF:free=$path:free:AVERAGE"
            "DEF:in_use_clnt=$path:in_use_clnt:AVERAGE"
            "CDEF:usedg=used,1048576,/"
            "CDEF:in_use_clnt_g=in_use_clnt,1048576,/"
            "CDEF:used_realg=usedg,in_use_clnt_g,-"
            "CDEF:free_g=free,1048576,/"
            "CDEF:sum=used_realg,in_use_clnt_g,+,free_g,+"
            "CDEF:memper=used_realg,sum,/,100,*"
            "PRINT:memper:AVERAGE:Utilization MEM in percent  %2.2lf"
            );
              $answer = RRDp::read;
            };
            if ($@) {
              if ( $@ =~ "ERROR" ) {
                error("Rrrdtool error : $@");
                next;
              }
            }
            my $aaa = $$answer;

            #if ( $aaa =~ /NaNQ/ ) { next; }
            ( undef, my $utilization_in_per ) = split( "\n", $aaa );
            $utilization_in_per =~ s/Utilization MEM in percent\s+//g;
            $count_mem_lpars_power++;

            #print "$utilization_in_per\n";
            #print "$lpar_name\n";
            my $check = check_mem_lpar_red($utilization_in_per);

            #print "$check\n";
            if ($check) {
              my $paging = get_paging_in_out($line);
              if ( $paging eq 0 ) {
                $inventory{$server}{LPAR}{$lpar_name}{MEMORY} = $utilization_in_per;
              }
              else {
                ( my $paging_in, my $paging_out ) = split( ",", $paging );

                #$paging_in = 130;
                #$paging_out = 120;
                $inventory{$server}{LPAR}{$lpar_name}{MEMORY}     = $utilization_in_per;
                $inventory{$server}{LPAR}{$lpar_name}{PAGING_IN}  = $paging_in;
                $inventory{$server}{LPAR}{$lpar_name}{PAGING_OUT} = $paging_out;
              }
            }
            else {
              $inventory{$server}{LPAR}{$lpar_name}{MEMORY} = $utilization_in_per;
            }
          }
        }
      }
    }
  }

  print "heatmap        : (Power) set memory utilization for $count_mem_lpars_power lpars\n";
}

sub check_mem_lpar_red {
  return 1;
  my $percent = shift;
  if ( "$percent" eq "-nan" || "$percent" eq "nan" || $percent =~ /nan/ || "$percent" eq "NaNQ" || $percent =~ /NAN/ || $percent =~ /NaN/ || !isdigit($percent) ) {
    return 0;
  }
  my $rounded = ceil($percent);
  $percent = $rounded;
  if ( $percent >= 91 ) {
    return 1;
  }
  else {
    return 0;
  }

}

sub get_paging_in_out {
  my $line       = shift;
  my $filter_max = 100000000;
  my ( $path, $server_name, $mem, $lpar ) = split( ",", $line );
  $path =~ s/mem.mmm/pgs.mmm/g;
  $mem = "mem.mmm";
  my $mem_name = $mem;

  #print $path . "\n";
  #my $lpar = $line;
  $mem_name =~ s/.mmm//g;

  #print $server_name . "\n";
  $lpar =~ s/\\//g;
  $path =~ s/:/\\:/g;

  #print $path . "\n";
  my $answer;
  eval {
    RRDp::cmd qq(graph "$mem_name"
    "--start" "$start_time"
    "--end" "$end_time"
    "--step=60"
    "DEF:pagein=$path:page_in:AVERAGE"
    "DEF:pageout=$path:page_out:AVERAGE"
    "DEF:percent=$path:percent:AVERAGE"
    "DEF:paging_space=$path:paging_space:AVERAGE"
    "CDEF:pagein_b_nf=pagein,4096,*"
    "CDEF:pageout_b_nf=pageout,4096,*"
    "CDEF:pagein_b=pagein_b_nf,$filter_max,GT,UNKN,pagein_b_nf,IF"
    "CDEF:pageout_b=pageout_b_nf,$filter_max,GT,UNKN,pageout_b_nf,IF"
    "CDEF:pagein_kb=pagein_b,1024,/"
    "CDEF:pageout_kb=pageout_b,1024,/"
    "PRINT:pagein_kb:AVERAGE:Pagein MEM in kb  %4.2lf"
    "PRINT:pageout_kb:AVERAGE:Pageout MEM in kb  %4.2lf"
    );
    $answer = RRDp::read;
  };
  if ($@) {
    if ( $@ =~ "ERROR" ) {
      error("Rrrdtool error : $@");
      return 0;
    }
  }
  my $aaa = $$answer;

  #if ( $aaa =~ /NaNQ/ ) { next; }
  ( undef, my $pagein, my $pageout ) = split( "\n", $aaa );
  $pagein  =~ s/Pagein MEM in kb\s+//g;
  $pageout =~ s/Pageout MEM in kb\s+//g;

  return "$pagein,$pageout";
}

sub get_dead_pool_power {
  my @dead_pool;
  my %mapping_pool;

  foreach my $list (@pool_list) {
    chomp $list;
    $list =~ s/^\s+|\s+$//g;
    ( my $file, my $file_map, my $server ) = split( ",", $list );
    chomp $file;
    $file =~ s/^\s+|\s+$//g;
    chomp $server;
    $server =~ s/^\s+|\s+$//g;
    chomp $file_map;
    $file_map =~ s/^\s+|\s+$//g;

    open( my $FH, "< $file_map" ) || error( "Cannot read $file: $!" . __FILE__ . ":" . __LINE__ ) && next;
    my @mapping_cpu_pool = <$FH>;
    close($FH);

    foreach my $line (@mapping_cpu_pool) {
      chomp $line;
      if ( $line eq "" ) { next; }
      $line =~ s/^\s+|\s+$//g;
      ( my $num, my $name ) = split( ",", $line );
      if ( defined $num && defined $name && $name ne "DefaultPool" ) {
        $mapping_pool{$num} = $name;
      }
    }

    #print Dumper \%mapping_pool;

    open( my $FHf, "< $file" ) || error( "Cannot read $file: $!" . __FILE__ . ":" . __LINE__ ) && next;
    my @lines_config = <$FHf>;
    close($FHf);
    foreach my $line (@lines_config) {
      chomp $line;
      if ( $line eq "" ) { next; }
      $line =~ s/^\s+|\s+$//g;
      my @check_dead = split( ",", $line );
      my $size       = scalar @check_dead;
      if ( $size == 1 ) {
        if ( defined $mapping_pool{ $check_dead[0] } ) {
          push( @dead_pool, "$server,$mapping_pool{$check_dead[0]}\n" );
        }
      }
    }

  }

  return @dead_pool;

}

sub set_live_pool_power {

  #remove sharedpool0
  my @dead_pool = get_dead_pool_power();

  foreach my $server ( keys %inventory ) {
    foreach my $pool ( keys %{ $inventory{$server}{POOL} } ) {
      if ( "$pool" eq "SharedPool0" ) {
        delete $inventory{$server}{POOL}{SharedPool0};
      }
      else {
        foreach my $line (@dead_pool) {
          chomp $line;
          if ( $line eq "" ) { next; }
          $line =~ s/^\s+|\s+$//g;
          ( my $srv, my $name ) = split( ",", $line );
          chomp $name;
          $name =~ s/^\s+|\s+$//g;
          chomp $srv;
          $srv =~ s/^\s+|\s+$//g;

          if ( defined $inventory{$server}{POOL}{$pool}{NAME} ) {
            if ( $inventory{$server}{POOL}{$pool}{NAME} eq "$name" && "$server" eq "$srv" ) {
              delete $inventory{$server}{POOL}{$pool};
            }
          }
          else {
            delete $inventory{$server}{POOL}{$pool};
          }
        }
      }

    }
  }

  #print Dumper \%inventory;
}

sub get_live_pool_power {
  my @test_pool;
  my $last_pool      = "";
  my $last_server    = "";
  my $last_timestamp = 0;
  set_live_pool_power();
  my @pool;
  my @wrkdir_all = <$wrkdir/*>;
  foreach my $server_all (@wrkdir_all) {
    my $server = basename($server_all);
    if ( -l $server_all )        { next; }
    if ( !-d $server_all )       { next; }
    if ( $server =~ /^--HMC--/ ) { next; }
    my $server_space = $server;
    if ( $server =~ m/ / ) {
      $server_space = "\"" . $server . "\"";    # it must be here to support space with server names
    }
    my @hmcdir_all = <$wrkdir/$server_space/*>;
    foreach my $hmc_all (@hmcdir_all) {
      my $hmc       = basename($hmc_all);
      my $hmc_space = $hmc;
      if ( $hmc =~ m/ / ) {
        $hmc_space = "\"" . $hmc . "\"";    # it must be here to support space with server names
      }
      my @lpars_dir_all = <$wrkdir/$server_space/$hmc_space/*>;
      foreach my $lpars_dir (@lpars_dir_all) {
        my $pool = basename($lpars_dir);

        #print "$lpar\n";
        if ( -l $lpars_dir )                                               { next; }
        if ( -d $lpars_dir )                                               { next; }
        if ( $pool !~ /\.rrm$/ && $pool !~ /\.rrh$/ && $pool !~ /\.rrt$/ ) { next; }
        if ( $pool =~ /^pool\.rrm|^pool_total\.rrt$/ || $pool =~ /^pool\.rrh/ || $pool =~ /^SharedPool[1-9]+\.rrh/ || $pool =~ /^SharedPool[1-9]+\.rrm/ ) {
          my $pool_timestamp = ( stat("$lpars_dir") )[9];
          if ( $pool =~ /^pool\.rrm|^SharedPool[1-9]+\.rrm|^pool_total\.rrt$/ ) {
            my $time_update_check = time();
            my $diff              = $time_update_check - $pool_timestamp;
            my $ten_days          = 3600 * 24 * 10;
            if ( $diff > $ten_days ) { next; }
          }
          push( @pool, "$server,$pool,$pool_timestamp,$lpars_dir" );
        }
      }
    }
  }
  my @sort_array = sort @pool;
  foreach my $line (@sort_array) {

    #print "$line\n";
    my ( $server, $pool, $pool_timestamp, $path ) = split( ",", $line );
    if ( $server eq $last_server ) {
      if ( $last_pool eq $pool ) {

        #print "$last_pool $last_timestamp a $pool $pool_timestamp\n";
        if ( $last_timestamp < $pool_timestamp ) {

          #print "$server a $pool\n";
          pop(@test_pool);
        }
        else {
          next;
        }
      }
    }
    $last_pool      = $pool;
    $last_server    = $server;
    $last_timestamp = $pool_timestamp;
    push( @test_pool, "$path,$server,$pool" );
  }
  return @test_pool;
}

sub set_utilization_pool_power {
  $count_pools = 0;
  my @pool = get_live_pool_power();

  #print Dumper \@pool;
  foreach my $line (@pool) {

    #print $line . "\n";
    my ( $path, $server_name, $pool ) = split( ",", $line );
    my $pool_name = $pool;
    $pool_name =~ s/.rrm//g;
    $pool_name =~ s/.rrh//g;
    $pool_name =~ s/.rrt//g;
    $path      =~ s/:/\\:/g;

    #print $server_name . "\n";
    foreach my $server ( keys %inventory ) {
      if ( "$server_name" eq "$server" ) {
        foreach my $pool ( keys %{ $inventory{$server}{POOL} } ) {
          if ( "$pool_name" eq "$pool" ) {
            if ( $pool_name =~ /SharedPool/ ) {
              my $answer;

              #"CDEF:cpurange=cpuutil,max,/"
              eval {
                RRDp::cmd qq(graph "$pool_name"
              "--start" "$start_time"
              "--end" "$end_time"
              "--step=60"
              "DEF:max=$path:max_pool_units:AVERAGE"
              "DEF:totcyc=$path:total_pool_cycles:AVERAGE"
              "DEF:uticyc=$path:utilized_pool_cyc:AVERAGE"
              "CDEF:cpuutil=uticyc,totcyc,GT,UNKN,uticyc,totcyc,/,IF"
              "CDEF:cpuutilper=cpuutil,100,*"
              "PRINT:cpuutilper:AVERAGE:Utilization POOL in percent  %2.2lf"
              );
                $answer = RRDp::read;
              };
              if ($@) {
                if ( $@ =~ "ERROR" ) {
                  error("Rrrdtool error : $@");
                  next;
                }
              }
              my $aaa = $$answer;

              #if ( $aaa =~ /NaNQ/ ) { next; }
              ( undef, my $utilization_in_per ) = split( "\n", $aaa );
              $utilization_in_per =~ s/Utilization POOL in percent\s+//g;
              $inventory{$server}{POOL}{$pool}{CPU} = $utilization_in_per;
              $count_pools++;
            }
            elsif ( $pool_name =~ m/pool_total/ ) {
              my $answer;

              #print "$pool_name\n";
              eval {
                RRDp::cmd qq(graph "$pool_name"
              "--start" "$start_time"
              "--end" "$end_time"
              "--step=60"
              "DEF:uncapped_cycles=$path:uncapped_cycles:AVERAGE"
              "DEF:capped_cycles=$path:capped_cycles:AVERAGE"
              "DEF:entitled_cycles=$path:entitled_cycles:AVERAGE"
              "DEF:curr_proc_units=$path:curr_proc_units:AVERAGE"
              "DEF:configured=$path:configured:AVERAGE"
              "CDEF:cpuutil=uncapped_cycles,capped_cycles,+,entitled_cycles,/,curr_proc_units,*"
              "CDEF:cpuutilper=cpuutil,configured,/,100,*"
              "PRINT:cpuutilper:AVERAGE:Utilization POOL in percent  %2.2lf"
              );
                $answer = RRDp::read;
              };
              if ($@) {
                if ( $@ =~ "ERROR" ) {
                  error("Rrrdtool error : $@");
                  next;
                }
              }
              my $aaa = $$answer;
              ( undef, my $utilization_in_per ) = split( "\n", $aaa );
              $utilization_in_per =~ s/Utilization POOL in percent\s+//g;
              $inventory{$server}{POOL}{$pool}{CPU} = $utilization_in_per;
              $count_pools++;
            }
            else {
              my $answer;

              #print "$pool_name\n";
              eval {
                RRDp::cmd qq(graph "$pool_name"
              "--start" "$start_time"
              "--end" "$end_time"
              "--step=60"
              "DEF:cpu=$path:conf_proc_units:AVERAGE"
              "DEF:totcyc=$path:total_pool_cycles:AVERAGE"
              "DEF:uticyc=$path:utilized_pool_cyc:AVERAGE"
              "DEF:cpubor=$path:bor_proc_units:AVERAGE"
              "CDEF:totcpu=cpu,cpubor,+"
              "CDEF:cpuutil=uticyc,totcyc,GT,UNKN,uticyc,totcyc,/,IF"
              "CDEF:cpuutilper=cpuutil,100,*"
              "PRINT:cpuutilper:AVERAGE:Utilization POOL in percent  %2.2lf"
              );
                $answer = RRDp::read;
              };
              if ($@) {
                if ( $@ =~ "ERROR" ) {
                  error("Rrrdtool error : $@");
                  next;
                }
              }
              my $aaa = $$answer;
              ( undef, my $utilization_in_per ) = split( "\n", $aaa );
              $utilization_in_per =~ s/Utilization POOL in percent\s+//g;
              $inventory{$server}{POOL}{$pool}{CPU} = $utilization_in_per;
              $count_pools++;
            }
          }
        }
      }
    }
  }

  print "heatmap        : (Power) set cpu utilization for $count_pools pools\n";
}

sub get_class {
  my $utilization = shift;
  my $curr_procs  = shift;

  #print $utilization . "\n";
  if ( "$utilization" eq "-nan" || "$utilization" eq "NaNQ" || "$utilization" eq "nan" || $utilization =~ /nan/ || $utilization =~ /NAN/ || $utilization =~ /NaN/ || $curr_procs eq 0 || !isdigit($utilization) || !isdigit($curr_procs) ) {
    return "clr0";
  }

  else {
    my $utilization_percent = ( $utilization / $curr_procs ) * 100;
    return get_percent_to_color($utilization_percent);
  }
}

sub get_percent_to_color {
  use POSIX qw(ceil);
  my $percent      = shift;
  my $mem_pading   = shift;
  my $ready_string = shift;
  my $cpu_ready    = 0;
  if ( "$percent" eq "-nan" || "$percent" eq "nan" || $percent =~ /nan/ || "$percent" eq "NaNQ" || $percent =~ /NAN/ || $percent =~ /NaN/ || !isdigit($percent) ) {
    return "clr0";
  }
  my $pom = ceil($percent);
  $percent = $pom;
  if ( defined $mem_pading && $mem_pading eq 1 && !defined $ready_string ) {
    return "clr10";
  }
  if ( defined $mem_pading && $mem_pading eq 0 && !defined $ready_string ) {
    return "clr9";
  }
  if ( defined $ready_string && $ready_string eq "ready" ) {
    if ( defined $mem_pading && isdigit($mem_pading) && $mem_pading > 5 ) {
      return "clr10";
    }
  }
  if ( $percent >= 0 && $percent <= 10 ) {
    return "clr1";
  }
  if ( $percent >= 11 && $percent <= 20 ) {
    return "clr2";
  }
  if ( $percent >= 21 && $percent <= 30 ) {
    return "clr3";
  }
  if ( $percent >= 31 && $percent <= 40 ) {
    return "clr4";
  }
  if ( $percent >= 41 && $percent <= 50 ) {
    return "clr5";
  }
  if ( $percent >= 51 && $percent <= 60 ) {
    return "clr6";
  }
  if ( $percent >= 61 && $percent <= 70 ) {
    return "clr7";
  }
  if ( $percent >= 71 && $percent <= 80 ) {
    return "clr8";
  }
  if ( $percent >= 81 && $percent <= 90 ) {
    return "clr9";
  }
  if ( $percent >= 91 ) {
    return "clr10";
  }
  return "clr0";
}

sub isdigit {

  my $digit = shift;
  if ( !defined($digit) ) {
    return 0;
  }

  if ( $digit eq '' ) {
    return 0;
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

  # NOT a number
  return 0;
}

####################################################################### Power end
#
#
#
#
######################################################################## VMWARE start

# select only VM

sub set_live_vmware {
  foreach my $server ( keys %vmware ) {
    if ( defined $vmware{$server}{TYPE} ) {
      if ( "$vmware{$server}{TYPE}" eq "V" ) {
      }
      else {
        delete $vmware{$server};
      }
    }
  }
}

sub set_utilization_cpu_mem_vm {
  $count_lpars_vm = 0;
  my $vm_path = "$wrkdir/vmware_VMs/";

  foreach my $server ( keys %vmware ) {
    foreach my $Lpar ( keys %{ $vmware{$server}{LPAR} } ) {

      #print "$vmware{$server}{LPAR}{$Lpar}\n";
      # chomp $lpar;
      my $vm_full_name = $vm_path . $Lpar . ".rrm";
      next if !-f $vm_full_name;    # in case old menu or so

      # print "2178 \$vm_full_name $vm_full_name\n";
      my $answer;

      my $cmd = "graph anything";
      $cmd .= " --start \"$start_time\"";
      $cmd .= " --end \"$end_time\"";
      $cmd .= " --step=60";
      $cmd .= " DEF:cpu_usage_pric=\"$vm_full_name\":CPU_usage_Proc:AVERAGE";
      $cmd .= " DEF:host_hz=\"$vm_full_name\":host_hz:AVERAGE";
      $cmd .= " DEF:vCPU=\"$vm_full_name\":vCPU:AVERAGE";
      $cmd .= " DEF:CPU_usage=\"$vm_full_name\":CPU_usage:AVERAGE";
      $cmd .= " DEF:CPU_ready_ms=\"$vm_full_name\":CPU_ready_ms:AVERAGE";
      $cmd .= " DEF:memory_granted=\"$vm_full_name\":Memory_granted:AVERAGE";
      $cmd .= " DEF:memory_active=\"$vm_full_name\":Memory_active:AVERAGE";
      $cmd .= " DEF:memory_baloon=\"$vm_full_name\":Memory_baloon:AVERAGE";
      $cmd .= " CDEF:cpu_usage_proc=cpu_usage_pric,100,/";
      $cmd .= " CDEF:host_MHz=host_hz,1000,/,1000,/";
      $cmd .= " CDEF:CPU_usage_res=CPU_usage,host_MHz,/,vCPU,/,100,*";
      $cmd .= " CDEF:pagein_b_raw=cpu_usage_proc,UN,CPU_usage_res,cpu_usage_proc,IF";
      $cmd .= " CDEF:pagein_b=pagein_b_raw,UN,pagein_b_raw,pagein_b_raw,100,GT,100,pagein_b_raw,IF,IF";
      $cmd .= " CDEF:CPU_ready_leg=CPU_ready_ms,200,/,vCPU,/";
      $cmd .= " CDEF:ratio=memory_active,memory_granted,/";
      $cmd .= " CDEF:utilization_mem=ratio,100,*";
      $cmd .= " PRINT:pagein_b:AVERAGE:\"Utilization CPU in percent %2.2lf\"";
      $cmd .= " PRINT:CPU_ready_leg:AVERAGE:\"CPU ready %2.2lf\"";
      $cmd .= " PRINT:utilization_mem:AVERAGE:\"Utilization Memory in percent %2.2lf\"";
      $cmd .= " PRINT:memory_baloon:AVERAGE:\"Memory Baloon in GB %2.2lf\"";

      eval {
        RRDp::cmd qq($cmd);
        $answer = RRDp::read;
      };
      if ($@) {
        my $err = $@;
        error( "Rrrdtool error $vm_full_name : $@ " . __FILE__ . ":" . __LINE__ );
        next if ( index( $err, 'could not lock' ) == -1 );
        print "sleep 1\n";
        sleep 1;
        eval {
          RRDp::cmd qq($cmd);
          $answer = RRDp::read;
        };
        if ($@) {
          error( "Rrrdtool error : $@ " . __FILE__ . ":" . __LINE__ );
          next;
        }
      }
      my $aaa = $$answer;

      #if ( $aaa =~ /NaNQ/ ) { next; }
      ( undef, my $utilization_in_per, my $cpu_ready, my $utilization_mem, my $mem_baloon ) = split( "\n", $aaa );

      $utilization_in_per =~ s/Utilization CPU in percent\s+//;
      $cpu_ready          =~ s/CPU ready\s+//;
      $utilization_mem    =~ s/Utilization Memory in percent\s+//;
      $mem_baloon         =~ s/Memory Baloon in GB\s+//;

      # attention to this: Argument "NaNQ" isn't numeric in division
      if ( index( lc($mem_baloon), 'nan' ) > -1 ) { $mem_baloon = 0 }
      $mem_baloon = sprintf( "%.1f", $mem_baloon / 1024 / 1024 );    #my $bb = sprintf("%.1f", $aa);
      $mem_baloon = "0" if $mem_baloon == 0;

      # print "2207 \$lpar_name $lpar_name\n";
      $count_lpars_vm++;
      $vmware{$server}{LPAR}{$Lpar}{CPU}       = $utilization_in_per;
      $vmware{$server}{LPAR}{$Lpar}{CPU_READY} = $cpu_ready;
      $vmware{$server}{LPAR}{$Lpar}{MEMORY}    = $utilization_mem;
      $vmware{$server}{LPAR}{$Lpar}{BALOON}    = $mem_baloon;
    }
  }

  print "heatmap        : (VMware) set cpu utilization for $count_lpars_vm vm\n";
  print "heatmap        : (VMware) set memory utilization for $count_lpars_vm vm\n";
}

sub set_utilization_pool_vm {
  $count_pools_vm = 0;
  my $answer;

  foreach my $server ( keys %vmware ) {

    #print Dumper $vmware{$server}{POOL};
    if ( !defined $vmware{$server}{POOL}{pool}{URL} ) {
      next;
    }
    my $host = $vmware{$server}{POOL}{pool}{URL};

    #'URL' => '/lpar2rrd-cgi/detail.sh?host=10.22.11.10&server=10.22.11.9&lpar=pool&item=pool&entitle=0&gui=1&none=none'
    ( undef, $host ) = split "host=", $host;
    ( $host, undef ) = split "\&server", $host;
    my $path = "$wrkdir/$server/$host/pool.rrm";
    my $cmd  = "graph anything";
    $cmd .= " --start \"$start_time\"";
    $cmd .= " --end \"$end_time\"";
    $cmd .= " --step=60";
    $cmd .= " DEF:ent=\"$path\":CPU_Alloc:AVERAGE";
    $cmd .= " DEF:utl=\"$path\":CPU_usage:AVERAGE";
    $cmd .= " DEF:hz=\"$path\":host_hz:AVERAGE";
    $cmd .= " DEF:memory_granted=\"$path\":Memory_granted:AVERAGE";
    $cmd .= " DEF:memory_size_B=\"$path\":Memory_Host_Size:AVERAGE";
    $cmd .= " CDEF:utiltot=utl,hz,/,1000000,*";
    $cmd .= " CDEF:total=ent,hz,/,1000000,*";
    $cmd .= " CDEF:utilper=utiltot,total,/,100,*";
    $cmd .= " CDEF:ratio=memory_granted,memory_size_B,/,1024,*";
    $cmd .= " CDEF:utilization_mem=ratio,100,*";
    $cmd .= " PRINT:utilper:AVERAGE:\"Utilization POOL in percent  %2.2lf\"";
    $cmd .= " PRINT:utilization_mem:AVERAGE:\"Utilization Memory in percent %2.2lf\"";

    eval {
      RRDp::cmd qq($cmd);
      $answer = RRDp::read;
    };
    if ($@) {
      my $err = $@;
      error( "Rrrdtool error : $@ " . __FILE__ . ":" . __LINE__ );
      next if ( index( $err, 'could not lock' ) == -1 );
      print "sleep 1\n";
      sleep 1;
      eval {
        RRDp::cmd qq($cmd);
        $answer = RRDp::read;
      };
      if ($@) {
        error( "Rrrdtool error : $@ " . __FILE__ . ":" . __LINE__ );
        next;
      }
    }

    my $aaa = $$answer;

    #if ( $aaa =~ /NaNQ/ ) { next; }
    ( undef, my $utilization_in_per, my $utilization_mem ) = split( "\n", $aaa );
    $utilization_in_per =~ s/Utilization POOL in percent\s+//g;
    $utilization_mem    =~ s/Utilization Memory in percent\s+//g;
    $vmware{$server}{POOL}{pool}{MEMORY} = $utilization_mem;
    $vmware{$server}{POOL}{pool}{CPU}    = $utilization_in_per;
    $count_pools_vm++;

  }

  print "heatmap        : (VMware) set cpu utilization for $count_pools_vm pools\n";
  print "heatmap        : (VMware) set memory utilization for $count_pools_vm pools\n";
  if ( open( my $XFR, "< $tmpdir/vmware_datastore_count_file.txt" ) ) {
    my $firstLine = <$XFR>;    # datastores     : (VMware) 36 active in menu
    close $XFR;
    print "$firstLine\n";
  }
}

sub get_table_cpu_lpar_vm {
  use POSIX qw(ceil);
  my $count_row = 1;
  my $nasob     = 0;

  #print "$count_lpars_vm\n";
  #$count_lpars_vm = $count_lpars_vm*20;
  #print "$count_lpars_vm\n";
  if ( $count_lpars_vm == 0 ) { return "" }
  my $cell_size    = ( $height * $width ) / $count_lpars_vm;
  my $td_width     = ceil( sqrt($cell_size) );
  my $td_height    = $td_width;
  my $new_row      = 0;
  my $count_column = 1;

  if ( $td_width < 10 ) {
    $td_width  = 10;
    $td_height = 10;
  }
  if ( $td_width > 42 ) {
    $td_width  = 42;
    $td_height = 42;
  }

  $td_height = $td_height - 2;
  ################
  my $style_vm = " .content_vm { height:" . "$td_height" . "px" . "; width:" . "$td_height" . "px" . ";} h3 {text-align:center;}";
  my $table    = "<table>\n<tbody>\n<tr>\n";

  my $table_values = "<table class =\"lparsearch tablesorter tablesortercfgsum\" data-sortby=\"4\">";
  $table_values = $table_values . "<thead><tr><th class = \"sortable\" title=\"Server\" nowrap=\"\">Server</th>\n";
  $table_values = $table_values . "<th class = \"sortable\" title=\"VM\" nowrap=\"\">VM</th>\n";
  $table_values = $table_values . "<th class = \"sortable\" title=\"CPU ready\" nowrap=\"\">CPU ready</th>\n";
  $table_values = $table_values . "<th class = \"sortable\" title=\"Utilization %\" nowrap=\"\">Utilization %</th>\n";

  # $table_values = $table_values . "<th class = \"sortable\" title=\"Color\" nowrap=\"\"><center>Color</center></th></tr></thead><tbody>\n";
  $table_values = $table_values . "<th title=\"Color\" nowrap=\"\"><center>Color</center></th></tr></thead><tbody>\n";

  foreach my $server ( sort keys %vmware ) {
    foreach my $lpar ( sort { lc $vmware{$server}{LPAR}{$a}{NAME} cmp lc $vmware{$server}{LPAR}{$b}{NAME} || $vmware{$server}{LPAR}{$a}{NAME} cmp $vmware{$server}{LPAR}{$b}{NAME} } keys %{ $vmware{$server}{LPAR} } ) {
      if ( defined $vmware{$server}{LPAR}{$lpar}{CPU} ) {
        if ( ( $new_row + $td_width ) > $width ) {
          $table   = $table . "</tr>\n<tr>\n";
          $new_row = 0;
        }
        my $percent_util = $vmware{$server}{LPAR}{$lpar}{CPU};
        my $cpu_ready    = $vmware{$server}{LPAR}{$lpar}{CPU_READY};
        if ( !defined $cpu_ready || !isdigit($cpu_ready) ) {
          $cpu_ready = "nan";
        }
        else {
          my $ceil = ceil($cpu_ready);
          $cpu_ready = $ceil;
          $cpu_ready = $cpu_ready . "%";
        }
        if ( "$percent_util" eq "-nan" || "$percent_util" eq "nan" || $percent_util =~ /nan/ || "$percent_util" eq "NaNQ" || $percent_util =~ /NAN/ || $percent_util =~ /NaN/ || !isdigit($percent_util) ) {
          $percent_util = "nan";
        }
        else {
          my $ceil = ceil($percent_util);
          $percent_util = $ceil;
          $percent_util = $percent_util . "%";
        }

        # print "2321 \$server $server \$lpar $lpar\n";
        # 2321 $server 10.22.11.14 $lpar 501cc9e0-a95e-7f86-8e7a-3a38b70e7eeb
        # %server_in_vcenter '10.22.11.14' => '10.22.11.10',
        # %vcenter_ids       '10.22.11.10' => 'eb6102a7-1fa0-4376-acbb-f67e34a2212c_28',
        my $id       = $vcenter_ids{ $server_in_vcenter{$server} } . "_vm_" . $lpar;
        my $url      = $vmware{$server}{LPAR}{$lpar}{URL};
        my $name     = $vmware{$server}{LPAR}{$lpar}{NAME};
        my $url_name = $name;

        #$url_name =~ s/([^A-Za-z0-9\+-_])/sprintf("%%%02X", ord($1))/seg;
        #$url_name =~ s/ /+/g;
        #$url_name =~ s/\#/%23/g;
        $url_name =~ s/([^a-zA-Z0-9_.!~*()'\''-])/sprintf("%%%02X", ord($1))/ge;

        #  print "2480 $url_name\n";

        $url =~ s/lpar=.*&item/lpar=$url_name&item/;
        $url =~ s/item=lpar&/item=lpar&uuid=$lpar&d_platform=VMware&id=$id&/;
        my $class = get_percent_to_color( $vmware{$server}{LPAR}{$lpar}{CPU}, $vmware{$server}{LPAR}{$lpar}{CPU_READY}, "ready" );
        my $color = $class_color{$class};

        $table = $table . "<td class=\"$class\">\n<a href=" . '"' . "$url" . '"' . "><div title =" . '"' . "$server : $name" . " : " . $percent_util . " : CPU ready $cpu_ready" . '"' . "class=" . '"' . "content_vm" . '"' . "></div>\n</a>\n</td>\n";
        $percent_util =~ s/\%//g;
        $cpu_ready    =~ s/\%//g;

        $table_values = $table_values . "<tr><td>$server</td><td>" . "<a href=\"$url\">$name</a></td><td>$cpu_ready</td><td>$percent_util</td><td><div style=\"height:15px;width:15px;background-color:$color; margin: auto;\"></div></td></tr>\n";

        $new_row = $td_width + $new_row;
      }
      else { next; }
    }
  }
  $table        = $table . "</tr>\n</tbody>\n</table><br>\n";
  $table_values = $table_values . "</tbody></table>";
  my $tb_and_styl = "$table" . "@" . "$style_vm" . "@" . "$table_values";
  return ($tb_and_styl);

  #print "$table_vm\n";
  #print "$count_lpars\n";
}

sub get_table_mem_lpar_vm {
  use POSIX qw(ceil);
  my $count_row = 1;

  #my $pom = $count_lpars_vm;
  #$pom = 0;
  if ( $count_lpars_vm == 0 ) { return "" }
  my $cell_size    = ( $height * $width ) / $count_lpars_vm;
  my $td_width     = ceil( sqrt($cell_size) );
  my $td_height    = $td_width;
  my $new_row      = 0;
  my $count_column = 1;

  if ( $td_width < 10 ) {
    $td_width  = 10;
    $td_height = 10;
  }
  if ( $td_width > 42 ) {
    $td_width  = 42;
    $td_height = 42;
  }

  $td_height = $td_height - 2;
  ################
  my $table        = "<table>\n<tbody>\n<tr>\n";
  my $table_values = "<table class =\"lparsearch tablesorter tablesortercfgsum\" data-sortby=\"3\">";
  $table_values = $table_values . "<thead><tr><th class = \"sortable\" title=\"Server\" nowrap=\"\">Server</th>\n";
  $table_values = $table_values . "<th class = \"sortable\" title=\"VM\" nowrap=\"\">VM</th>\n";
  $table_values = $table_values . "<th class = \"sortable\" title=\"Mem Baloon GB\" nowrap=\"\">Mem Baloon GB</th>\n";
  $table_values = $table_values . "<th class = \"sortable\" title=\"Utilization %\" nowrap=\"\">Utilization %</th>\n";

  # $table_values = $table_values . "<th class = \"sortable\" title=\"Color\" nowrap=\"\"><center>Color</center></th></tr></thead><tbody>\n";
  $table_values = $table_values . "<th title=\"Color\" nowrap=\"\"><center>Color</center></th></tr></thead><tbody>\n";

  #my @vm_arr = ();
  foreach my $server ( sort keys %vmware ) {
    foreach my $lpar ( sort { lc $vmware{$server}{LPAR}{$a}{NAME} cmp lc $vmware{$server}{LPAR}{$b}{NAME} || $vmware{$server}{LPAR}{$a}{NAME} cmp $vmware{$server}{LPAR}{$b}{NAME} } keys %{ $vmware{$server}{LPAR} } ) {
      if ( defined $vmware{$server}{LPAR}{$lpar}{MEMORY} ) {
        if ( ( $new_row + $td_width ) > $width ) {
          $table   = $table . "</tr>\n<tr>\n";
          $new_row = 0;
        }
        my $percent_util = $vmware{$server}{LPAR}{$lpar}{MEMORY};
        if ( "$percent_util" eq "-nan" || "$percent_util" eq "nan" || $percent_util =~ /nan/ || "$percent_util" eq "NaNQ" || $percent_util =~ /NAN/ || $percent_util =~ /NaN/ || !isdigit($percent_util) ) {
          $percent_util = "nan";
        }
        else {
          my $ceil = ceil($percent_util);
          $percent_util = $ceil;
          $percent_util = $percent_util . "%";
        }
        my $mem_baloon = $vmware{$server}{LPAR}{$lpar}{BALOON};

        my $id  = $vcenter_ids{ $server_in_vcenter{$server} } . "_vm_" . $lpar;
        my $url = $vmware{$server}{LPAR}{$lpar}{URL};

        #/lpar2rrd-cgi/detail.sh?host=10.22.11.10&server=cluster_New Cluster&lpar=501cb14b-47b3-eb98-a53b-8cc8ec99296e&item=lpar&entitle=0&gui=1&none=none
        ( my $host, my $cluster_name ) = split( "&server=", $url );
        $cluster_name =~ s/&lpar.*//;
        $lpars_in_cluster{$lpar} = $cluster_name;

        $host =~ s/.*host=//;

        # $clusters_vms{$host}{$cluster_name} =  [@vm_arr]; # this is not good
        push @{ $clusters_vms{$host}{$cluster_name} }, $lpar;

        my $name     = $vmware{$server}{LPAR}{$lpar}{NAME};
        my $url_name = $name;

        #$url_name =~ s/([^A-Za-z0-9\+-_])/sprintf("%%%02X", ord($1))/seg;
        #$url_name =~ s/ /+/g;
        #$url_name =~ s/\#/%23/g;
        $url_name =~ s/([^a-zA-Z0-9_.!~*()'\''-])/sprintf("%%%02X", ord($1))/ge;

        # print $name . "\n";
        $url =~ s/lpar=.*&item/lpar=$url_name&item/g;
        $url =~ s/item=lpar&/item=lpar&uuid=$lpar&d_platform=VMware&id=$id&/;
        my $class = get_percent_to_color( $vmware{$server}{LPAR}{$lpar}{MEMORY} );
        my $color = $class_color{$class};

        #$table = $table . "<td class=\"$class\">\n<a href=" . '"' . "$url" . '"' . "><div title =" . '"' . "$server : $name" . " : " . $percent_util . '"' . "class=" . '"' . "content_vm" . '"' . "></div>\n</a>\n</td>\n";
        $table = $table . "<td class=\"$class\">\n<a href=" . '"' . "$url" . '"' . "><div title =" . '"' . "$server : $name : $mem_baloon : $percent_util" . '"' . "class=" . '"' . "content_vm" . '"' . "></div>\n</a>\n</td>\n";

        $percent_util =~ s/\%//g;

        $table_values = $table_values . "<tr><td>$server</td><td>" . "<a href=\"$url\">$name</a></td><td>$mem_baloon</td><td>$percent_util</td><td><div style=\"height:15px;width:15px;background-color:$color; margin: auto;\"></div></td></tr>\n";

        $new_row = $td_width + $new_row;
      }
      else { next; }
    }
  }
  $table        = $table . "</tr>\n</tbody>\n</table><br>\n";
  $table_values = $table_values . "</tbody></table>";
  my $tb = $table . "@" . $table_values;
  return $tb;

  #print "$table_vm\n";
  #print "$count_lpars\n";
}

sub get_table_cpu_pool_vm {
  use POSIX qw(ceil);
  my $count_row = 1;
  my $nasob     = 1;

  #print "$count_pools\n";
  if ( $count_pools_vm == 0 ) { return "" }
  my $cell_size    = ( $height * $width ) / $count_pools_vm;
  my $td_width     = ceil( sqrt($cell_size) );
  my $td_height    = $td_width;
  my $new_row      = 0;
  my $count_column = 1;

  if ( $td_width < 10 ) {
    $td_width  = 10;
    $td_height = 10;
  }
  if ( $td_width > 42 ) {
    $td_width  = 42;
    $td_height = 42;
  }

  $td_height = $td_height - 2;
  ################
  #my $i = 0;
  my $table = "<table>\n<tbody>\n<tr>\n";
  my $style = " .content_pool_vm { height:" . "$td_height" . "px" . "; width:" . "$td_height" . "px" . ";}  h3 {text-align:center;}";

  my $table_values = "<table class =\"lparsearch tablesorter\" data-sortby=\"3\">";
  $table_values = $table_values . "<thead><tr><th class = \"sortable\" title=\"Server\" nowrap=\"\">Server</th>\n";

  #   $table_values = $table_values . "<th class = \"sortable\" title=\"Pool\" nowrap=\"\">Pool</th>\n"; # remove this column since 7.60
  $table_values = $table_values . "<th class = \"sortable\" title=\"Utilization %\" nowrap=\"\">Utilization %</th>\n";

  # $table_values = $table_values . "<th class = \"sortable\" title=\"Color\" nowrap=\"\"><center>Color</center></th></tr></thead><tbody>\n";
  $table_values = $table_values . "<th title=\"Color\" nowrap=\"\"><center>Color</center></th></tr></thead><tbody>\n";

  foreach my $server ( sort keys %vmware ) {
    foreach my $pool ( sort { lc $vmware{$server}{POOL}{$a}{NAME} cmp lc $vmware{$server}{POOL}{$b}{NAME} || $vmware{$server}{POOL}{$a}{NAME} cmp $vmware{$server}{POOL}{$b}{NAME} } keys %{ $vmware{$server}{POOL} } ) {
      if ( defined $vmware{$server}{POOL}{$pool}{CPU} ) {
        if ( ( $new_row + $td_width ) > $width ) {
          $table   = $table . "</tr>\n<tr>\n";
          $new_row = 0;
        }
        my $percent_util;
        my $util = $vmware{$server}{POOL}{$pool}{CPU};
        if ( "$util" eq "-nan" || "$util" eq "nan" || $util =~ /nan/ || "$util" eq "NaNQ" || $util =~ /NAN/ || $util =~ /NaN/ || !isdigit($util) ) {
          $percent_util = "nan";
        }
        else {
          $percent_util = ceil( $vmware{$server}{POOL}{$pool}{CPU} ) . "%";
        }
        my $class = get_percent_to_color($util);
        my $color = $class_color{$class};
        my $url   = $vmware{$server}{POOL}{$pool}{URL};

        # print "2760 \$server $server \$url $url\n";
        # create esxi id for XORMON ACL purpose
        # eb6102a7-1fa0-4376-acbb-f67e34a2212c_28_cluster_domain-c87_esxi_10.22.11.14
        my $cluster_name  = $vclusters{$server};
        my $cluster_moref = $cluster_ids{$cluster_name};
        $cluster_moref = "" if !defined $cluster_moref;    # probably esxi is not in cluster
        my $vcenter_ip = $server_in_vcenter{$server};
        my $vcenter_id = $vcenter_ids{$vcenter_ip};

        # print "2523 \$vcenter_id $vcenter_id \$server $server \$cluster_name $cluster_name\n";

        my $esxi_id = "probably_old_vcenter_version";
        if ( defined $vcenter_id ) {
          $esxi_id = $vcenter_id . "_" . $cluster_moref . "_esxi_" . $server;
        }

        # print "2503 \$server $server \$pool $pool \$url $url\n";
        $url .= "&d_platform=VMware&id=$esxi_id";

        #        $table = $table . "<td class=\"$class\">\n<a href=" . '"' . "$url" . '"' . "><div title =" . '"' . "$server : CPU" . " : " . $percent_util . '"' . "class=" . '"' . "content_pool_vm" . '"' . "></div>\n</a>\n</td>\n";
        $table = $table . "<td class=\"$class\">\n<a href=\"$url\"><div title=\"$server : CPU : $percent_util class=content_pool_vm\"></div>\n</a>\n</td>\n";
        $percent_util =~ s/\%//g;

        # $table_values = $table_values . "<tr><td>$server</td><td>" . "<a href=" . '"' . "$url" . '"' . ">CPU</a></td><td>$percent_util</td><td><div style=\"height:15px;width:15px;background-color:$color; margin: auto;\"></div></td></tr>\n";
        # $table_values = $table_values . "<tr><td>$server</td><td><a href=\"$url\">CPU</a></td><td>$percent_util</td><td><div style=\"height:15px;width:15px;background-color:$color; margin: auto;\"></div></td></tr>\n";
        # remove column POOL since 7.60
        $table_values = $table_values . "<tr><td><a href=\"$url\">$server</a></td><td>$percent_util</td><td><div style=\"height:15px;width:15px;background-color:$color; margin: auto;\"></div></td></tr>\n";

        $new_row = $td_width + $new_row;
      }
      else { next; }
    }
  }
  $table        = $table . "</tr>\n</tbody>\n</table><br>\n";
  $table_values = $table_values . "</tbody></table>";
  my $tb_and_style = "$table" . "@" . "$style" . "@" . "$table_values";
  return "$tb_and_style";
}

sub get_table_mem_pool_vm {
  use POSIX qw(ceil);
  my $count_row = 1;
  my $nasob     = 1;

  #print "$count_pools\n";
  if ( $count_pools_vm == 0 ) { return "" }
  my $cell_size    = ( $height * $width ) / $count_pools_vm;
  my $td_width     = ceil( sqrt($cell_size) );
  my $td_height    = $td_width;
  my $new_row      = 0;
  my $count_column = 1;

  if ( $td_width < 10 ) {
    $td_width  = 10;
    $td_height = 10;
  }
  if ( $td_width > 42 ) {
    $td_width  = 42;
    $td_height = 42;
  }

  $td_height = $td_height - 2;
  ################
  #my $i = 0;
  my $table = "<table>\n<tbody>\n<tr>\n";

  my $table_values = "<table class =\"lparsearch tablesorter\" data-sortby=\"3\">";
  $table_values = $table_values . "<thead><tr><th class = \"sortable\" title=\"Server\" nowrap=\"\">Server</th>\n";

  # $table_values = $table_values . "<th class = \"sortable\" title=\"Pool\" nowrap=\"\">Pool</th>\n"; # remove this column since 7.60
  $table_values = $table_values . "<th class = \"sortable\" title=\"Utilization %\" nowrap=\"\">Utilization %</th>\n";

  # $table_values = $table_values . "<th class = \"sortable\" title=\"Color\" nowrap=\"\"><center>Color</center></th></tr></thead><tbody>\n";
  $table_values = $table_values . "<th title=\"Color\" nowrap=\"\"><center>Color</center></th></tr></thead><tbody>\n";

  foreach my $server ( sort keys %vmware ) {
    foreach my $pool ( sort { lc $vmware{$server}{POOL}{$a}{NAME} cmp lc $vmware{$server}{POOL}{$b}{NAME} || $vmware{$server}{POOL}{$a}{NAME} cmp $vmware{$server}{POOL}{$b}{NAME} } keys %{ $vmware{$server}{POOL} } ) {
      if ( defined $vmware{$server}{POOL}{$pool}{MEMORY} ) {
        if ( ( $new_row + $td_width ) > $width ) {
          $table   = $table . "</tr>\n<tr>\n";
          $new_row = 0;
        }
        my $percent_util;
        my $util = $vmware{$server}{POOL}{$pool}{MEMORY};
        if ( "$util" eq "-nan" || "$util" eq "nan" || $util =~ /nan/ || "$util" eq "NaNQ" || $util =~ /NAN/ || $util =~ /NaN/ || !isdigit($util) ) {
          $percent_util = "nan";
        }
        else {
          $percent_util = ceil( $vmware{$server}{POOL}{$pool}{MEMORY} ) . "%";
        }
        my $url = $vmware{$server}{POOL}{$pool}{URL};
        $url =~ s/lpar=pool/lpar=cod/g;
        $url =~ s/item=memalloc/lpar=memalloc/g;

        # create esxi id for XORMON ACL purpose
        # eb6102a7-1fa0-4376-acbb-f67e34a2212c_28_cluster_domain-c87_esxi_10.22.11.14
        my $cluster_name  = $vclusters{$server};
        my $cluster_moref = $cluster_ids{$cluster_name};
        $cluster_moref = "" if !defined $cluster_moref;    # probably esxi is not in cluster
        my $vcenter_ip = $server_in_vcenter{$server};
        my $vcenter_id = $vcenter_ids{$vcenter_ip};
        my $esxi_id    = "probably_old_vcenter_version";
        if ( defined $vcenter_id ) {
          $esxi_id = $vcenter_id . "_" . $cluster_moref . "_esxi_" . $server;
        }

        $url .= "&d_platform=VMware&id=$esxi_id";

        my $class = get_percent_to_color($util);
        my $color = $class_color{$class};

        $table = $table . "<td class=\"$class\">\n<a href=" . '"' . "$url" . '"' . "><div title =" . '"' . "$server : MEM" . " : " . $percent_util . '"' . "class=" . '"' . "content_pool_vm" . '"' . "></div>\n</a>\n</td>\n";

        $percent_util =~ s/\%//g;

        # $table_values = $table_values . "<tr><td>$server</td><td>" . "<a href=" . '"' . "$url" . '"' . ">MEM</a></td><td>$percent_util</td><td><div style=\"height:15px;width:15px;background-color:$color; margin: auto;\"></div></td></tr>\n";
        # remove column POOL since 7.60
        $table_values = $table_values . "<tr><td>" . "<a href=" . '"' . "$url" . '"' . ">$server</a></td><td>$percent_util</td><td><div style=\"height:15px;width:15px;background-color:$color; margin: auto;\"></div></td></tr>\n";

        $new_row = $td_width + $new_row;
      }
      else { next; }
    }
  }
  $table        = $table . "</tr>\n</tbody>\n</table><br>\n";
  $table_values = $table_values . "</tbody></table>";
  return "$table" . "@" . $table_values;
}

sub gen_vmware_cmd_files {

  # print Dumper \%vmware;
  # print "-----------------------------\n";
  # print Dumper \%cluster_ids;
  # print Dumper \%vcenter_ids;
  # print Dumper \%server_in_vcenter;
  # print Dumper \%vclusters;
  # print Dumper \%lpars_in_cluster;
  # print Dumper \%clusters_vms;
  # print Dumper \%respools_in_clusters;
  # print Dumper ("cluster_info",\%cluster_info);

  # create list of VMs for vcenters
  foreach ( keys %vcenter_ids ) {
    $vcenter_key = $_;
    $host        = $vcenter_key;

    # print "2781 \$vcenter_key $vcenter_key\n";
    @files = ();

    foreach ( sort keys %server_in_vcenter ) {
      my $server = $_;
      next if $server_in_vcenter{$server} ne $vcenter_key;

      # print "  \$server $server\n";
      foreach ( sort keys %{ $vmware{$server}{LPAR} } ) {
        my $uuid = $_;

        # print "        \$uuid $uuid\n";
        push @files, $uuid;
        $vm_uuid_name_hash{$uuid}{NAME} = $vmware{$server}{LPAR}{$uuid}{NAME};
        $vm_uuid_name_hash{$uuid}{ESXI} = $server;
      }
    }

    # print "@files\n";
    @managednamelist_vmw = @files;
    make_cmd_frame_multiview( $managedname, $host, $et_HostSystem );    # for ESXi servers
  }

  # create cmd files for clusters
  foreach my $host_ci ( keys %cluster_info ) {
    foreach my $cluster_name ( keys %{ $cluster_info{$host_ci} } ) {
      next if $cluster_name eq "url";
      $cluster_moref = $cluster_info{$host_ci}{$cluster_name};
      $host          = $host_ci;
      my $point = $clusters_vms{$host_ci}{$cluster_name};

      # print Dumper ("2944",$point,$clusters_vms{$host_ci}{$cluster_name});

      @files = "";
      @files = @$point if defined $point && $point ne "";    # cluster can have only esxis without VMs

      # print "2945 \$host_ci $host_ci \$cluster_name $cluster_name \@files @files\n";

      # find vcenter_uuid for cluster name

      my $vcenter_uuid = $cluster_info{$host_ci}{url};

      # print "2961 \$vcenter_uuid $vcenter_uuid\n";
      # cluster_domain-c15&server=vmware_5a19dec4-eb67-427b-8363-1b0e77a54577_17&lpar=nope&item=cluster&entitle=0&gui=1&none=none
      ( undef, $vcenter_uuid, undef ) = split "&", $vcenter_uuid;
      $vcenter_uuid =~ s/server=//;
      $managedname  = $vcenter_uuid;
      $vcenter_uuid = $managedname;

      # print "2962 \$managedname $managedname\n";

      # print "\$cluster_name $cluster_name @files\n";
      make_cmd_frame_multiview( $managedname, $cluster_moref, $et_ClusterComputeResource );    # for clusters

      # respools
      foreach ( keys %{ $respools_in_clusters{$cluster_moref} } ) {
        $rp_moref = $_;
        $rp_name  = $respools_in_clusters{$cluster_moref}{$rp_moref};

        # prepare list of active registered VMs on respool
        my $registered_VM_file = "$wrkdir/$vcenter_uuid/$cluster_moref/$rp_moref.vmr";

        # print "2748 respool moref $rp_moref $wrkdir/$vcenter_uuid/$cluster_moref/$rp_moref.vmr\n";
        next if ( !-f $registered_VM_file );    # respool has no VM

        @files = ();
        open( my $fh, "$registered_VM_file" ) or error( "can't open $registered_VM_file: $!" . __FILE__ . ":" . __LINE__ ) && next;

        # 500f6fb4-69d6-bde0-30aa-c30e5c27dc09:start=1496144582:end=1531744983:start=1531766583
        while ( my $row = <$fh> ) {
          ( my $vm, undef ) = split( ":", $row );

          # $vm .= ".rrm";
          my $pos = rindex( $row, ':' );
          next if $pos < 0;                                  # some trash
          if ( substr( $row, $pos + 1, 5 ) eq "start" ) {    # keep item
            push @files, $vm;
          }
        }
        close $fh;

        # print "2766 respools VMs @files\n";
        make_cmd_frame_multiview( $vcenter_uuid, $cluster_moref, $et_ResourcePool );    # for respools
      }
    }
  }

}

sub make_cmd_frame_multiview {
  my $cl_managedname = shift;
  my $cl_host        = shift;
  my $et_type        = shift;

  my $time = time();

  $multiview_hmc_count = 0;    #reset counter

  multiview_hmc( $host, "lpar-multi", "d", "m", $time, "day",  "MINUTE:60:HOUR:2:HOUR:4:0:%H", $et_type, $cl_managedname, $cl_host );
  multiview_hmc( $host, "lpar-multi", "w", "m", $time, "week", "HOUR:8:DAY:1:DAY:1:86400:%a",  $et_type, $cl_managedname, $cl_host );
  return 0 if $multiview_hmc_count > 1;

  multiview_hmc( $host, "lpar-multi", "m", "m", $time, "month", "DAY:1:DAY:2:DAY:2:0:%d", $et_type, $cl_managedname, $cl_host );
  return 0 if $multiview_hmc_count > 1;

  multiview_hmc( $host, "lpar-multi", "y", "m", $time, "year", "MONTH:1:MONTH:1:MONTH:1:0:%b", $et_type, $cl_managedname, $cl_host );

  return 0;
}

# LPARs aggregated per a HMC
sub multiview_hmc {
  my ( $host, $name_part, $type, $type_sam, $act_time, $text, $xgrid, $et_type, $cl_managedname, $cl_host ) = @_;

  # e.g.   multiview_hmc( $host, "lpar-multi", "d", "m", $time, "day",   "MINUTE:60:HOUR:2:HOUR:4:0:%H", $et_type, $cl_managedname, $cl_host );
  # print "2877 $host, $name_part, $type, $type_sam, $act_time, $text, $xgrid, $et_type, $cl_managedname, $cl_host\n";

  my $req_time = 0;
  my $file     = "";
  my $i        = 0;
  my $lpar     = "";
  my $cmd      = "";
  my $j        = 0;
  my $name     = "$webdir/$host/$name_part-$type";    # out graph file name, not really used, changed in detail-graph-cgi.pl

  my $DEBUG = 1;

  my $tmp_file = "$tmpdir/multi-hmc-lpar-$host-$type.cmd";

  if ( defined $et_type && $et_type eq $et_ClusterComputeResource ) {
    $tmp_file = "$tmpdir/multi-hmc-lpar-$cl_managedname-$cl_host-$type.cmd";
  }
  if ( ( defined $et_type ) && ( $et_type eq $et_ResourcePool ) ) {
    $tmp_file = "$tmpdir/multi-hmc-lpar-$cl_managedname-$rp_moref-$type.cmd";
  }

  $act_time = time();

  my $skip_time = 0;
  if ( "$type" =~ "d" ) {
    $req_time = $act_time - 86400;
  }
  if ( "$type" =~ "w" ) {
    $req_time  = $act_time - 604800;
    $skip_time = $WEEK_REFRESH;
  }
  if ( "$type" =~ "m" ) {
    $req_time  = $act_time - 2764800;
    $skip_time = $MONTH_REFRESH;
  }
  if ( "$type" =~ "y" ) {

    #$req_time = $act_time - 31536000;
    $req_time  = $act_time - ( 89 * 86400 );    #cus older VMs are regularly deleted
    $skip_time = $YEAR_REFRESH;
  }

  # do not update weekly/monthly/yearly command files each run
  if ( -f "$tmp_file" ) {
    my $tmp_time = ( stat("$tmp_file") )[9];
    if ( ( $act_time - $tmp_time ) < $skip_time ) {
      print "                        skipped this time : ( $act_time - $tmp_time ) < $skip_time \n";
      return 0;
    }
  }
  $multiview_hmc_count++;    # update counter

  if ( $et_type eq $et_HostSystem ) {
    print "creating l_hmc : $host:$type - VMs aggregated per vcenter " . localtime(time) . "\n" if $DEBUG;
  }
  elsif ( $et_type eq $et_ClusterComputeResource ) {
    print "creating l_hmc : $host:$type - VMs aggregated per cluster " . localtime(time) . " $cl_managedname $cl_host\n" if $DEBUG;
  }
  elsif ( $et_type eq $et_ResourcePool ) {
    print "creating l_hmc : $host:$type - VMs aggregated per resourcepool " . localtime(time) . " $cl_managedname $rp_name\n" if $DEBUG;
  }
  else {
    print "creating l_hmc : $host:$type - VMs aggregated per $et_type $cl_managedname $cl_host\n" if $DEBUG;
  }
  my $header = "VMs aggregated : last $text";
  if ( "$type" =~ "d" ) {
    $req_time = $act_time - 86400;
  }
  if ( "$type" =~ "w" ) {
    $req_time = $act_time - 604800;
  }
  if ( "$type" =~ "m" ) {
    $req_time = $act_time - 2764800;
  }

  # for daily, must be even type as for IVM/SDMC it is not in $type_sam =~ "d"
  if ( $type_sam =~ "d" || "$type" =~ "y" ) {
    $req_time = $act_time - 31536000;
  }

  my $gtype = "AREA";

  @managednamelist = @managednamelist_vmw;

  # for ResourcePool -> server is not necessary
  if ( $et_type eq $et_ResourcePool ) {
    @managednamelist = ("resourcepool");
  }

  $cmd .= "graph \\\"$name.png\\\"";
  $cmd .= " --title \\\"$header\\\"";
  $cmd .= " --start now-1$type";
  $cmd .= " --end now-1$type+1$type";
  $cmd .= " --imgformat PNG";
  $cmd .= " $disable_rrdtool_tag_agg";
  $cmd .= " --slope-mode";
  $cmd .= " --width=400";
  $cmd .= " --height=150";
  $cmd .= " --step=$STEP";
  $cmd .= " --lower-limit=0.00";
  $cmd .= " --color=BACK#$pic_col";
  $cmd .= " --color=SHADEA#$pic_col";
  $cmd .= " --color=SHADEB#$pic_col";
  $cmd .= " --color=CANVAS#$pic_col";
  $cmd .= " --alt-autoscale-max";
  $cmd .= " --upper-limit=0.1";
  $cmd .= " --vertical-label=\\\"CPU GHz  \\\"";
  $cmd .= " --units-exponent=1.00";
  $cmd .= " --alt-y-grid";
  $cmd .= " --x-grid=$xgrid";
  $cmd .= " COMMENT:\\\"Utilization in CPU GHz                         \\l\\\"";
  $cmd .= " COMMENT:\\\"  Server                       VM                                   avrg     max\\l\\\"";

  my $cmd_rdy = "";    # cmd for RDY
                       # for cluster VMS it is also prepared cluster lpar RDY
  my $stime   = 0;
  if ( $et_type eq $et_ClusterComputeResource ) {
    $cmd_rdy = $cmd;
    $cmd_rdy =~ s/CPU GHz/CPU-ready-%/;
    $cmd_rdy =~ s/upper-limit=0.1/upper-limit=100/;
    $cmd_rdy =~ s/Utilization in CPU GHz/VM READY in Percent   /;
    $cmd_rdy =~ s/VMs aggregated/CPU VMs READY/;

    # care for start time for CPU_ready
    if ( -f $CPU_ready_time_file ) {
      if ( open( my $FF, "<$CPU_ready_time_file" ) ) {
        $stime = (<$FF>);
        close($FF);

        # print "5193 \$stime $stime\n";
        chomp $stime;
        $stime *= 1;
      }
    }

    #$cmd .= " CDEF:pagein_b=TIME,$stime,LT,0,pagein_bn,IF";
  }

  @keep_color_lpar = ();    # do not take previous colors (e.g. from cluster)

  my @color_save = "";
  my $found      = -1;

  foreach (@files) {
    $file = $_;

    # goes through all lpars of each server
    chomp($file);

    # print "3026 \$file $file\n";
    if ( $file =~ m/^\.rr/ ) {
      next;    # avoid .rrm
    }

    # prepare $managedname/$host/$file from path
    if ( $et_type eq $et_ResourcePool ) {
      $found++;
    }

    # moved later after color choice
    # avoid non existed - suspended or poweredoff VMs - no data saved yet, or removed older 3 months
    $file .= ".rrm";

    # next if !-f "$wrkdir/$all_vmware_VMs/$file";

    # use following test later after colours are chosen, so d,w,m,y colors are ok
    #print "2966 \$file $file\n";
    # # avoid old lpars which do not exist in the period
    # my $rrd_upd_time = ( stat("$wrkdir/$all_vmware_VMs/$file") )[9];    # you can add also ! defined
    # if ( $rrd_upd_time < $req_time ) {
    #   next;
    # }

    $lpar = $file;
    $lpar =~ s/.rrh//;
    $lpar =~ s/.rrm//;
    $lpar =~ s/.rrd//;

    $managedname = $vm_uuid_name_hash{$lpar}{ESXI};

    $server = $managedname;

    # my $lpar_orig = human_vmware_name( $lpar, "", $managedname, $host );
    my $lpar_orig = $vm_uuid_name_hash{$lpar}{NAME};
    if ( !defined $lpar_orig || $lpar_orig eq "" ) {
      $lpar_orig = $lpar;
    }
    $lpar = substr( $lpar_orig, 0, 35 );

    my $lpar_space      = $lpar;
    my $lpar_space_proc = $lpar_orig;

    if ( $lpar eq '' ) {
      next;    # avoid .rrm --> just to be sure :)
    }

    # add spaces to lpar name to have 35 chars total (for formating graph legend)
    $lpar_space =~ s/\&\&1/\//g;
    for ( my $k = length($lpar_space); $k < 35; $k++ ) {
      $lpar_space .= " ";
    }

    # Exclude pools and memory
    if ( $lpar =~ m/^cod$/ || $lpar =~ m/^pool$/ || $lpar =~ m/^mem$/ || $lpar =~ /^SharedPool[0-9]$/ || $lpar =~ m/^SharedPool[1-9][0-9]$/ || $lpar =~ m/^mem-pool$/ ) {
      next;
    }

    # Assure that lpar colors is same for each lpar through daily - yearly charts
    my $l;
    my $l_count = 0;

    if ( ( defined $et_type ) && ( $et_type eq $et_ResourcePool ) ) {

      # nothing yet
    }
    else {
      $found = -1;
      foreach $l (@keep_color_lpar) {
        if ( $l eq '' || $l =~ m/^ $/ ) {
          next;
        }

        #        if ( $l =~ m/^$lpar$/ ) left curly
        if ( $l eq "$lpar" ) {
          $found = $l_count;
          last;
        }
        $l_count++;
      }
    }
    if ( $found == -1 ) {
      $keep_color_lpar[$l_count] = $lpar;
      $found = $l_count;
    }

    # take color from 0 to 53 -- division modulo
    $found = $found % $color_max;

    # avoid non existed - suspended or poweredoff VMs - no data saved yet, or removed older 3 months
    next if !-f "$wrkdir/$all_vmware_VMs/$file";

    # avoid old lpars which do not exist in the period
    my $rrd_upd_time = ( stat("$wrkdir/$all_vmware_VMs/$file") )[9];    # you can add also ! defined
    if ( $rrd_upd_time < $req_time ) {
      next;
    }

    #print "$found $lpar $color[$found]\n";
    print "$wrkdir/$managedname/$host/$file $rrd_upd_time $req_time $act_time\n" if ( $DEBUG == 3 );

    next if !defined $managedname or $managedname eq "";                # can be not refreshed menu and newly started VM
    my $server_name = $managedname;
    $server_name =~ s/\&\&1/\//g;
    my $server_name_space = $server_name;
    for ( my $k = length($server_name_space); $k < 25; $k++ ) {
      $server_name_space .= " ";
    }
    $server_name =~ s/:/\\:/g;
    $server_name =~ s/%/%%/g;

    $lpar_space = $server_name_space . "    " . $lpar_space;

    $lpar_space      =~ s/:/\\:/g;                                      # anti ':'
    $lpar_space_proc =~ s/:/\\:/g;
    $lpar_space_proc =~ s/%/%%/g;                                       # anti '%

    my $wrkdir_managedname_host_file = "$wrkdir/$managedname/$host/$file";
    $wrkdir_managedname_host_file =~ s/:/\\:/g;
    my $wrkdir_managedname_host_file_legend = $wrkdir_managedname_host_file;
    $wrkdir_managedname_host_file_legend =~ s/%/%%/g;

    # new system
    $wrkdir_managedname_host_file = "$wrkdir/$all_vmware_VMs/$file";
    $wrkdir_managedname_host_file =~ s/:/\\:/g;

    # bulid RRDTool cmd
    # $cmd .= " DEF:cpu_entitl_mhz${i}=\\\"$wrkdir_managedname_host_file\\\":CPU_Alloc:AVERAGE";
    $cmd .= " DEF:utiltot_mhz${i}=\\\"$wrkdir_managedname_host_file\\\":CPU_usage:AVERAGE";

    # $cmd .= " DEF:one_core_hz${i}=\\\"$wrkdir_managedname_host_file\\\":host_hz:AVERAGE";
    #    $cmd .= " COMMENT:\"   Average                   cores      Ghz (right axis)\\n\"";
    #    if ($in_cores) left curly
    # $cmd .= " CDEF:utiltotu${i}=utiltot_mhz${i},one_core_hz${i},/,1000000,*";
    # $cmd .= " CDEF:ncpu${i}=cpu_entitl_mhz${i},one_core_hz${i},/,1000000,*";
    # $cmd .= " CDEF:cpu_entitl_ghz${i}=cpu_entitl_mhz${i},1000,/";
    # $cmd .= " CDEF:utiltot_ghz${i}=utiltot_mhz${i},1000,/";
    $cmd .= " CDEF:utiltot_ghz${i}=utiltot_mhz${i},1000,/";
    $cmd .= " CDEF:utiltot${i}=utiltot_mhz${i},1000,/";       # since 4.74- (u)

    # next line not necessary when you start with AREA
    #  $cmd .= " CDEF:utiltot${i}=utiltotu${i},UN,0,utiltotu${i},IF";
    $cmd .= " $gtype:utiltot${i}$color[$found]:\\\"$lpar_space\\\"";

    push @color_save, $lpar_orig;

    # print "3238 \$server_name $server_name \$lpar_space_proc $lpar_space_proc \$wrkdir_managedname_host_file_legend $wrkdir_managedname_host_file_legend\n";

    $cmd .= " PRINT:utiltot${i}:AVERAGE:\"%3.2lf $delimiter multihmclpar_vm $delimiter $server_name $delimiter $lpar_space_proc\"";
    $cmd .= " PRINT:utiltot${i}:AVERAGE:\\\"%3.2lf $delimiter $color[$found] $delimiter $wrkdir_managedname_host_file_legend\\\"";
    $cmd .= " PRINT:utiltot${i}:MAX:\" %3.2lf $delimiter\"";

    $cmd .= " GPRINT:utiltot${i}:AVERAGE:\\\"%3.2lf \\\"";
    $cmd .= " GPRINT:utiltot${i}:MAX:\\\" %3.2lf \\l\\\"";

    if ( $et_type eq $et_ClusterComputeResource ) {
      $cmd_rdy .= " DEF:CPU_ready_msx${i}=\\\"$wrkdir_managedname_host_file\\\":CPU_ready_ms:AVERAGE";
      $cmd_rdy .= " CDEF:CPU_ready_ms${i}=TIME,$stime,LT,0,CPU_ready_msx${i},IF";
      $cmd_rdy .= " DEF:vCPU${i}=\\\"$wrkdir_managedname_host_file\\\":vCPU:AVERAGE";
      $cmd_rdy .= " CDEF:CPU_ready_leg${i}=CPU_ready_ms${i},200,/,vCPU${i},/";
      $cmd_rdy .= " LINE1:CPU_ready_leg${i}$color[$found]:\\\"$lpar_space\\\"";

      $cmd_rdy .= " PRINT:CPU_ready_leg${i}:AVERAGE:\"%6.2lf $delimiter multihmclpardy $delimiter $server_name $delimiter $lpar_space_proc\"";
      $cmd_rdy .= " PRINT:CPU_ready_leg${i}:AVERAGE:\\\"%6.2lf $delimiter $color[$found] $delimiter $wrkdir_managedname_host_file_legend\\\"";
      $cmd_rdy .= " PRINT:CPU_ready_leg${i}:MAX:\" %6.2lf $delimiter\"";

      $cmd_rdy .= " GPRINT:CPU_ready_leg${i}:AVERAGE:\\\"%6.2lf \\\"";
      $cmd_rdy .= " GPRINT:CPU_ready_leg${i}:MAX:\\\" %6.2lf \\l\\\"";
    }

    # put carriage return after each second lpar in the legend
    if ( $j == 1 ) {
      $j = 0;
    }
    else {
      #$cmd .= " GPRINT:utiltot${i}:AVERAGE:\\\"%3.2lf \\t\\\"";
      # --> it does not work ideally with newer RRDTOOL (1.2.30 --> it needs to be separated by cariage return here)
      $j++;
    }
    $gtype = "STACK";
    $i++;
  }

  # write colors into a file for detail-graph-cgi.pl
  if ( ( "$type" =~ "y" ) && ( !defined $et_type ) ) {    # not for resourcepool
    open( my $FHC, "> $wrkdir/$managedname/$host/lpars.col" ) || error( "file does not exists : $wrkdir/$managedname/$host/lpars.col " . __FILE__ . ":" . __LINE__ ) && return 0;
    my $num_col_lpar = 0;
    foreach my $line_cs (@color_save) {
      chomp($line_cs);                                    # it must be there, somehow appear there \n ...
      if ( $line_cs eq '' ) {
        next;
      }
      my $num_col_lpar_write = $num_col_lpar % $color_max;
      print $FHC "$num_col_lpar_write:$line_cs\n";
      $num_col_lpar++;
    }
    close($FHC);
  }

  if ( "$type" =~ "d" ) {
    if ( $j == 1 ) {
      $cmd .= " COMMENT:\\\" \\l\\\"";
      if ( $et_type ne $et_ResourcePool ) {
        $cmd_rdy .= " COMMENT:\\\" \\l\\\"";
      }
    }

    # not for vmware $cmd .= " COMMENT:\\\"\(Note that for CPU dedicated LPARs is always shown their whole entitlement\)\\\"";
  }
  $cmd .= " HRULE:0#000000";

  # $cmd .= " VRULE:0#000000";  --> it is causing sigsegv on linuxeS
  $cmd =~ s/\\"/"/g;
  if ( $et_type eq $et_ClusterComputeResource ) {
    $cmd_rdy .= " HRULE:0#000000";
    $cmd_rdy =~ s/\\"/"/g;
  }

  # print "multihmclpar CMD is in file $tmp_file\n" if $DEBUG;

  open( my $FHt, "> $tmp_file" ) || error( " Can't open $tmp_file : $!" . __FILE__ . ":" . __LINE__ ) && return 0;
  print $FHt "$cmd\n";
  close($FHt);

  if ( $et_type eq $et_ClusterComputeResource ) {
    $tmp_file = "$tmpdir/multi-hmc-lpar-rdy-$cl_managedname-$cl_host-$type.cmd";
    open( my $FH, "> $tmp_file" ) || error( " Can't open $tmp_file : $!" . __FILE__ . ":" . __LINE__ ) && return 0;
    print $FH "$cmd_rdy\n";
    close($FH);
  }

  return 1;    # do not execute the cmd itself

}

#
#
######################################################################## VMWARE end

sub get_html_lpar_power {
  my $memory = "Memory";
  my $check  = get_table_cpu_lpar_power();
  if ( $check eq "" ) {
    return 0;
  }
  else {
    set_wrap_html_power();
    my ( $table_cpu, $style_power, $table_values ) = split( "@", get_table_cpu_lpar_power() );
    my ( $table_mem, $table_values_mem ) = split( "@", get_table_mem_lpar_power() );
    if ( !defined $table_mem ) {
      $table_mem = "";
    }
    if ( !defined $table_values_mem ) {
      $table_values_mem = "";
    }
    if ( $table_mem eq "" ) {
      $memory = "";
    }
    my $style = "<style>" . "$style_power" . "$style_html" . "</style>";

    #print get_legend();
    my $html = "<!DOCTYPE html>\n<html>\n<head>" . $style . "</head><body>\n<table class=" . '"' . "center" . '"' . ">\n<tbody>\n<tr><td><h3>CPU</h3></td></tr><tr>\n<td>" . "$table_cpu" . "</td></tr>\n<tr><td><h3>$memory</h3></td></tr><tr>\n<td>" . "$table_mem" . "</td></tr><tr><td>" . get_report() . "</td>\n</tr><tr><td>&nbsp;</td></tr><tr><td><b>LEGEND</b>:<tr><td>" . get_legend($memory) . "</td></tr>\n</tbody>\n</table>\n</body></html>";
    open( my $DATA, ">$webdir/heatmap-power-cpu.html" ) or error_die("Cannot open file: $webdir/heatmap-power-cpu.html : $!");
    print $DATA $html;
    close $DATA;
    my $html2 = "<!DOCTYPE html>\n<html>\n<head>" . $style . "</head><body><center>$table_values</center></body></html>";
    open( $DATA, ">$webdir/heatmap-power-cpu-lpar-values.html" ) or error_die("Cannot open file: $webdir/heatmap-power-cpu-lpar-values.html : $!");
    print $DATA $html2;
    close $DATA;
    my $html3 = "<!DOCTYPE html>\n<html>\n<head>" . $style . "</head><body><center>$table_values_mem</center></body></html>";
    open( $DATA, ">$webdir/heatmap-power-mem-lpar-values.html" ) or error_die("Cannot open file: $webdir/heatmap-power-mem-lpar-values.html : $!");
    print $DATA $html3;
    close $DATA;

    #print $html . "\n";
  }
}

sub get_html_pool_power {
  my $check = get_table_cpu_pool_power();
  if ( $check eq "" ) {
    return 0;
  }
  else {
    set_wrap_html_power();
    my ( $table_cpu, $style_power, $table_values ) = split( "@", get_table_cpu_pool_power() );

    #my $table_mem = get_table_mem_lpar_power();
    my $style = "<style>" . "$style_power" . "$style_html" . "</style>";
    my $html  = "<!DOCTYPE html>\n<html>\n<head>" . $style . "</head><body>\n<table class=" . '"' . "center" . '"' . ">\n<tbody>\n<tr><td><h3>CPU</h3></td></tr><tr>\n<td>" . "$table_cpu" . "</td></tr>\n<tr><td>" . get_report() . "</td>\n</tr><tr><td>&nbsp;</td></tr><tr><td><b>LEGEND</b>:<tr><td>" . get_legend() . "</td></tr>\n</tbody>\n</table>\n</body></html>";
    open( my $DATA, ">$webdir/heatmap-power-server.html" ) or error_die("Cannot open file: $webdir/heatmap-power-server.html : $!");
    print $DATA $html;
    close $DATA;
    my $html2 = "<!DOCTYPE html>\n<html>\n<head>" . $style . "</head><body><center>$table_values</center></body></html>";
    open( $DATA, ">$webdir/heatmap-power-cpu-pool-values.html" ) or error_die("Cannot open file: $webdir/heatmap-power-cpu-pool-values.html : $!");
    print $DATA $html2;
    close $DATA;

    #print $html . "\n";
  }

}

sub set_html_power {
  get_html_lpar_power();
  get_html_pool_power();

}

sub set_wrap_html_power() {
  my $html = "<div id=" . '"' . "tabs" . '"' . ">\n<ul>\n<li><a href=" . '"' . "heatmap-power-cpu.html" . '"' . ">LPAR</a></li><li><a href=" . '"' . "heatmap-power-server.html" . '"' . ">Server</a></li>\n <li><a href=" . '"' . "heatmap-power-cpu-lpar-values.html" . '"' . ">LPAR CPU Table</a></li>\n <li><a href=" . '"' . "heatmap-power-mem-lpar-values.html" . '"' . ">LPAR MEM Table</a></li>\n  <li><a href=" . '"' . "heatmap-power-cpu-pool-values.html" . '"' . ">Server CPU Table</a></li> \n</ul>\n</div>";
  if ( -e "$webdir/heatmap-power.html" ) {
  }
  else {
    open( my $DATA, ">$webdir/heatmap-power.html" ) or error_die("Cannot open file: $webdir/heatmap-power.html : $!");
    print $DATA $html;
    close $DATA;
  }

}

sub get_html_lpar_vm {
  my $memory = "Memory";
  my $check  = get_table_cpu_lpar_vm();
  if ( $check eq "" ) {
    return 0;
  }
  else {
    set_wrap_html_vm();
    my ( $table_cpu, $style_vm, $table_values ) = split( "@", get_table_cpu_lpar_vm() );
    my ( $table_mem, $table_mem_values ) = split( "@", get_table_mem_lpar_vm() );
    if ( $table_mem eq "" ) {
      $memory = "";
    }
    my $style = "<style>" . "$style_vm" . "$style_html" . "</style>";

    #print $style . "\n";
    my $html = "<!DOCTYPE html>\n<html>\n<head>" . $style . "</head><body>\n<table class=" . '"' . "center" . '"' . ">\n<tbody><tr><td><h3>CPU</h3></td></tr>\n<tr>\n<td>" . $table_cpu . "</td></tr>\n<tr>\n<td>&nbsp;</td>\n</tr><tr><td><h3>$memory</h3></td></tr>\n<tr><td>" . $table_mem . "</td></tr><tr><td>" . get_report() . "\n</td></tr><tr><td>&nbsp;</td></tr><tr><td><b>LEGEND</b>:<tr><td>" . get_legend("cpu_ready") . "</td></tr>\n</tbody>\n</table>\n</body></html>";
    open( my $DATA, ">$webdir/heatmap-vmware-cpu.html" ) or error_die("Cannot open file: $webdir/heatmap-vmware-cpu.html : $!");
    print $DATA $html;
    close $DATA;
    my $html2 = "<!DOCTYPE html>\n<html>\n<head>" . $style . "</head><body><center>$table_values</center></body></html>";
    open( $DATA, ">$webdir/heatmap-vmware-cpu-vm-values.html" ) or error_die("Cannot open file: $webdir/heatmap-vmware-cpu-vm-values.html : $!");
    print $DATA $html2;
    close $DATA;
    my $html3 = "<!DOCTYPE html>\n<html>\n<head>" . $style . "</head><body><center>$table_mem_values</center></body></html>";
    open( $DATA, ">$webdir/heatmap-vmware-mem-vm-values.html" ) or error_die("Cannot open file: $webdir/heatmap-vmware-mem-vm-values.html : $!");
    print $DATA $html3;
    close $DATA;

    #print $html . "\n";
  }
}

sub get_html_pool_vm {
  my $check = get_table_cpu_pool_vm();
  if ( $check eq "" ) {
    return 0;
  }
  else {
    set_wrap_html_vm();
    my ( $table_cpu, $style_vm, $table_values ) = split( "@", get_table_cpu_pool_vm() );
    my ( $table_mem, $table_mem_values ) = split( "@", get_table_mem_pool_vm() );
    my $style = "<style>" . "$style_vm" . "$style_html" . "</style>";

    #print $style . "\n";
    my $html = "<!DOCTYPE html>\n<html>\n<head>" . $style . "</head><body>\n<table class=" . '"' . "center" . '"' . ">\n<tbody><tr><td><h3>CPU</h3></td></tr>\n<tr>\n<td>" . $table_cpu . "</td></tr>\n<tr>\n<td>&nbsp;</td>\n</tr><tr><td><h3>Memory</h3></td></tr>\n<tr><td>" . $table_mem . "</td></tr><tr><td>" . get_report() . "</td></tr><tr><td>&nbsp;</td></tr><tr><td><b>LEGEND</b>:<tr><td>" . get_legend() . "</td></tr>\n</tbody>\n</table>\n</body></html>";
    open( my $DATA, ">$webdir/heatmap-vmware-server.html" ) or error_die("Cannot open file: $webdir/heatmap-vmware-server.html : $!");
    print $DATA $html;
    close $DATA;

    my $html2 = "<!DOCTYPE html>\n<html>\n<head>" . $style . "</head><body><center>$table_values</center></body></html>";
    open( $DATA, ">$webdir/heatmap-vmware-cpu-server-values.html" ) or error_die("Cannot open file: $webdir/heatmap-vmware-cpu-server-values.html : $!");
    print $DATA $html2;
    close $DATA;

    my $html3 = "<!DOCTYPE html>\n<html>\n<head>" . $style . "</head><body><center>$table_mem_values</center></body></html>";
    open( $DATA, ">$webdir/heatmap-vmware-mem-server-values.html" ) or error_die("Cannot open file: $webdir/heatmap-vmware-mem-server-values.html : $!");
    print $DATA $html3;
    close $DATA;

    #print $html . "\n";
  }

}

sub set_html_vm {
  get_html_lpar_vm();
  get_html_pool_vm();

}

sub set_wrap_html_vm {
  my $html = "<div id=" . '"' . "tabs" . '"' . ">\n <ul>\n<li><a href=" . '"' . "heatmap-vmware-cpu.html" . '"' . ">VM</a></li>\n<li><a href=" . '"' . "heatmap-vmware-server.html" . '"' . ">Server</a></li>\n<li><a href=" . '"' . "heatmap-vmware-cpu-vm-values.html" . '"' . ">VM CPU Table</a></li>\n<li><a href=" . '"' . "heatmap-vmware-mem-vm-values.html" . '"' . ">VM MEM Table</a></li>\n<li><a href=" . '"' . "heatmap-vmware-cpu-server-values.html" . '"' . ">Server CPU Table</a></li>\n<li><a href=" . '"' . "heatmap-vmware-mem-server-values.html" . '"' . ">Server MEM Table</a></li>\n </ul>\n</div>";
  if ( -e "$webdir/heatmap-vmware.html" ) {
  }
  else {
    open( my $DATA, ">$webdir/heatmap-vmware.html" ) or error_die("Cannot open file: $webdir/heatmap-vmware.html : $!");
    print $DATA $html;
    close $DATA;
  }

}

sub get_report {
  my $time  = localtime;
  my $table = "<table>\n<tbody>\n<tr>\n<td>Heat map has been created at: " . "$time" . "</td>\n</tr>\n<tr>\n<td>Heat map shows average utilization from last $LPAR_HEATMAP_UTIL_TIME hour.</td>\n</tr>\n</tbody>\n</table>";
  return $table;

}

sub get_note {
  my $table = "<table>\n<tbody>\n<tr>\n<td>It is being developed.</td>\n</tr>\n</tbody>\n</table>";
  return $table;
}

sub get_legend {
  my $memory = shift;
  my $table  = "<table>\n<tbody><tr>";
  my $i      = 0;
  my $from   = 0;
  my $to     = 10;
  my $title  = "";
  my $paging = "";
  while ( $i < 11 ) {

    if ( $i == 0 ) {
      $title = "nan";
    }
    if ( defined $memory && $memory eq "Memory" && $i == 10 ) {
      $title = $title . " and paging in > $HEATMAP_MEM_PAGING_MAX kB/s or paging out > $HEATMAP_MEM_PAGING_MAX kB/s";
    }
    if ( defined $memory && $memory eq "cpu_ready" && $i == 10 ) {
      $title = $title . " or CPU ready > 5%";
    }

    #print "$title\n";
    $table = $table . "\n<td title=" . '"' . "$title" . '"' . "class=" . '"' . "clr$i" . '"' . "><div class =" . '"' . "content_legend" . '"' . "></div></td>";
    $i++;
    $title = "$from-$to " . "%";
    $from  = $to + 1;
    $to    = $to + 10;
  }
  $table = $table . "</tr>\n</tbody>\n</table>";
  return $table;
}

sub error_die {
  my $message = shift;

  print STDERR "$message\n";
  RRDp::end;    # close RRD pipe
  exit(1);
}

#########  HYPERV subs head of section
#########

sub set_live_hyperv {
  foreach my $server ( keys %vmware ) {
    if ( defined $vmware{$server}{TYPE} ) {
      if ( "$vmware{$server}{TYPE}" eq "H" ) {
      }
      else {
        delete $vmware{$server};
      }
    }
  }

  # print Dumper %vmware;
}

sub set_utilization_cpu_hv {
  $count_lpars_hv = 0;
  $count_pools_hv = 0;

  # print Dumper \%vmware;

  foreach my $server ( keys %vmware ) {

    # 'DESKTOP-O79DK45' => {'TYPE' => 'H',
    #                        'POOL' => {'pool' => {'URL' => '/lpar2rrd-cgi/detail.sh?host=DESKTOP-O79DK45&server=windows/domain_WORKGROUP&lpar=pool&item=pool&entitle=0&gui=1&none=none',    }}}
    my $url = $vmware{$server}{POOL}{pool}{URL};
    if ( !defined $url ) { next; }

    # print "\$url $url\n";
    ( my $host, my $lpar ) = split( "server=", $url );
    ( $lpar, undef ) = split( "&lpar=", $lpar );
    ( undef, $host ) = split( "host=", $host );
    $host =~ s/&//;
    my $rrd = "$wrkdir/$lpar/$host/pool.rrm";
    if ( !-f $rrd ) {
      error( "File $rrd does not EXIST, skip server $host " . __FILE__ . ":" . __LINE__ );
      next;
    }

    # print "\$rrd $rrd\n";

    my $answer;
    my $cmd = "";

    # testing standalone
    if ( -f "$wrkdir/$lpar/$host/standalone" ) {

      #               $cmd .= " CDEF:cpuutiltot=1,cpu_perc,cpu_time,/,-,$max_cpu_cores,*";    # to be in cores
      # print "2929 $wrkdir/$lpar/$host/standalone\n";
      $cmd = "graph anything";
      $cmd .= " --start \"$start_time\"";
      $cmd .= " --end \"$end_time\"";
      $cmd .= " --step=60";
      $cmd .= " DEF:PercentTotalRunTime=\"$rrd\":PercentTotalRunTime:AVERAGE";
      $cmd .= " DEF:Timestamp_PerfTime=\"$rrd\":Timestamp_PerfTime:AVERAGE";
      $cmd .= " CDEF:CPU_usage_Proc=1,PercentTotalRunTime,Timestamp_PerfTime,/,-,100,*";
      $cmd .= " DEF:free=\"$rrd\":AvailableMBytes:AVERAGE";
      $cmd .= " DEF:tot=\"$rrd\":TotalPhysMemory:AVERAGE";
      $cmd .= " CDEF:freeg=free,1024,/";
      $cmd .= " CDEF:totg=tot,1024,/,1024,/,1024,/";
      $cmd .= " CDEF:MEM_usage_Proc=freeg,totg,/,100,*";
      $cmd .= " PRINT:CPU_usage_Proc:AVERAGE:\"CPU %2.2lf\"";
      $cmd .= " PRINT:MEM_usage_Proc:AVERAGE:\"MEM %2.2lf\"";

    }
    else {
      # find out max cores of the server from first line of cpu.html im comment
      my $max_cpu_cores = 0;
      if ( open( my $FR, "< $wrkdir/$lpar/$host/cpu.html" ) ) {
        my $firstLine = <$FR>;    # example <BR><CENTER><TABLE class="tabconfig tablesorter"><!cores:8>
        close $FR;
        ( undef, my $m_cpu_cores ) = split( "cores:", $firstLine );
        if ( defined $m_cpu_cores ) {
          $m_cpu_cores =~ s/>//;
          $max_cpu_cores = $m_cpu_cores;
          chomp $max_cpu_cores;

          # print "3543 \$max_cpu_cores,$max_cpu_cores,\n";
        }
      }
      if ( $max_cpu_cores eq 0 ) {
        print "$wrkdir/$lpar/$host/cpu.html \$max_cpu_cores is 0, take 1\n";
        $max_cpu_cores = 1;
      }

      $cmd = "graph anything";
      $cmd .= " --start \"$start_time\"";
      $cmd .= " --end \"$end_time\"";
      $cmd .= " --step=60";
      $cmd .= " DEF:PercentTotalRunTime=\"$rrd\":PercentTotalRunTime:AVERAGE";
      $cmd .= " DEF:Timestamp_PerfTime=\"$rrd\":Timestamp_PerfTime:AVERAGE";
      $cmd .= " DEF:Frequency_PerfTime=\"$rrd\":Frequency_PerfTime:AVERAGE";
      $cmd .= " CDEF:CPU_usage_Proc=PercentTotalRunTime,Timestamp_PerfTime,/,Frequency_PerfTime,*,100000,/,$max_cpu_cores,/";
      $cmd .= " DEF:free=\"$rrd\":AvailableMBytes:AVERAGE";
      $cmd .= " DEF:tot=\"$rrd\":TotalPhysMemory:AVERAGE";
      $cmd .= " CDEF:freeg=free,1024,/";
      $cmd .= " CDEF:totg=tot,1024,/,1024,/,1024,/";
      $cmd .= " CDEF:MEM_usage_Proc=freeg,totg,/,100,*";
      $cmd .= " PRINT:CPU_usage_Proc:AVERAGE:\"CPU %2.2lf\"";
      $cmd .= " PRINT:MEM_usage_Proc:AVERAGE:\"MEM %2.2lf\"";
    }
    eval {
      RRDp::cmd qq($cmd);
      $answer = RRDp::read;
    };
    if ($@) {
      my $err = $@;
      error( "Rrrdtool error : $@ " . __FILE__ . ":" . __LINE__ );
      next if ( index( $err, 'could not lock' ) == -1 );
      print "sleep 1\n";
      sleep 1;
      eval {
        RRDp::cmd qq($cmd);
        $answer = RRDp::read;
      };
      if ($@) {
        error( "Rrrdtool error : $@ " . __FILE__ . ":" . __LINE__ );
        next;
      }
    }

    my $aaa = $$answer;

    # print "\$aaa $aaa\n";
    # if ( $aaa =~ /NaNQ|nan/ ) { next; }
    # do not next, let it create the files in www/ even if CPU or MEM are grey

    ( undef, my $utilization_in_per, my $utilization_mem_per, undef ) = split( "\n", $aaa );
    $utilization_in_per  =~ s/CPU\s+//;
    $utilization_mem_per =~ s/MEM\s+//;
    if ( $utilization_in_per =~ /NaNQ|nan/ && $utilization_mem_per =~ /NaNQ|nan/ ) { next; }

    # when both CPU and MEM are undef then next is ok

    # print "$utilization_in_per, $utilization_mem_per\n";

    # print "$rrd\n";
    $count_pools_hv++;
    $vmware{$server}{POOL}{pool}{CPU}    = $utilization_in_per;
    $vmware{$server}{POOL}{pool}{MEMORY} = 100 - $utilization_mem_per;

    # print "3592 cycle \$server $server\n";
    foreach my $Lpar ( keys %{ $vmware{$server}{LPAR} } ) {

      my $url = $vmware{$server}{LPAR}{$Lpar}{URL};

      # print "3596 \$Lpar $Lpar \$url $url\n";
      # $Lpar 61538264-853B-43A0-99F5-DCFE083864C0
      # $url /lpar2rrd-cgi/detail.sh?host=HVNODE01&server=windows/domain_ad.xorux.com&lpar=61538264-853B-43A0-99F5-DCFE083864C0&item=lpar&entitle=0&gui=1&none=none
      ( undef, my $lpar ) = split( "server=", $url );
      ( $lpar, undef ) = split( "&lpar=", $lpar );
      $lpar = "$wrkdir/$lpar/hyperv_VMs/$Lpar.rrm";
      $lpar =~ s/:/\\:/g;

      # print "\$lpar $lpar\n";

      # @ds = ( "PercentTotalRunTime", "Timestamp_PerfTime", "Frequency_PerfTime", "vCPU" ) if $item eq "hyp-cpu";
      # $cmd .= " CDEF:CPU_usage_Proc=$ids[0],$ids[1],/,$ids[2],*,100000,/,100,/";    # %

      my $answer;
      my $cmd = "graph anything";
      $cmd .= " --start \"$start_time\"";
      $cmd .= " --end \"$end_time\"";
      $cmd .= " --step=60";
      $cmd .= " DEF:PercentTotalRunTime=\"$lpar\":PercentTotalRunTime:AVERAGE";
      $cmd .= " DEF:Timestamp_PerfTime=\"$lpar\":Timestamp_PerfTime:AVERAGE";
      $cmd .= " DEF:Frequency_PerfTime=\"$lpar\":Frequency_PerfTime:AVERAGE";
      $cmd .= " CDEF:CPU_usage_Proc=PercentTotalRunTime,Timestamp_PerfTime,/,Frequency_PerfTime,*,100000,/";
      $cmd .= " DEF:MEM_usage_Proc=\"$lpar\":MemoryAvailable:AVERAGE";
      $cmd .= " PRINT:CPU_usage_Proc:AVERAGE:\"CPU %2.2lf\"";
      $cmd .= " PRINT:MEM_usage_Proc:AVERAGE:\"MEM %2.2lf\"";
      eval {
        RRDp::cmd qq($cmd);
        $answer = RRDp::read;
      };
      if ($@) {
        my $err = $@;
        error( "Rrrdtool error : $@ " . __FILE__ . ":" . __LINE__ );
        next if ( index( $err, 'could not lock' ) == -1 );
        print "sleep 1\n";
        sleep 1;
        eval {
          RRDp::cmd qq($cmd);
          $answer = RRDp::read;
        };
        if ($@) {
          error( "Rrrdtool error : $@ " . __FILE__ . ":" . __LINE__ );
          next;
        }
      }

      my $aaa = $$answer;

      # print "\$aaa $aaa\n";
      #if ( $aaa =~ /NaNQ|nan/ ) { next; }

      ( undef, my $utilization_in_per, my $utilization_mem_per, undef ) = split( "\n", $aaa );
      $utilization_in_per  =~ s/CPU\s+//;
      $utilization_mem_per =~ s/MEM\s+//;
      if ( $utilization_in_per  =~ /NaNQ|nan/ ) { next; }
      if ( $utilization_mem_per =~ /NaNQ|nan/ ) { $utilization_mem_per = 99 }    # so it is shown in heatmap as green

      # my $name     = $vmware{$server}{LPAR}{$Lpar}{NAME};
      # print "3055 $name $Lpar, $lpar, $utilization_in_per, $utilization_mem_per\n";

      #print "$rrd_name\n";
      $count_lpars_hv++;
      $vmware{$server}{LPAR}{$Lpar}{CPU}    = $utilization_in_per;
      $vmware{$server}{LPAR}{$Lpar}{MEMORY} = 100 - $utilization_mem_per;
    }
  }
  print "heatmap        : (WINDOWS) set cpu utilization for $count_lpars_hv vm\n";
  print "heatmap        : (WINDOWS) set cpu utilization for $count_pools_hv pool\n";
}

sub set_html_hv {
  get_html_lpar_hv();
  get_html_pool_hv();
  return;
}

sub get_html_lpar_hv {
  my $memory = "Memory";
  my $check  = get_table_cpu_lpar_hv();

  # $check  = ""; # if debug
  if ( $check eq "" ) {
    my $html = "<!DOCTYPE html>\n<html>\n<head>No VMs detected</head></html>";
    open( my $DATA, ">$webdir/heatmap-windows-cpu.html" ) or error_die("Cannot open file: $webdir/heatmap-windows-cpu.html : $!");
    print $DATA $html;
    close $DATA;

    # my $html2 = "<!DOCTYPE html>\n<html>\n<head>".$style . "</head><body><center>$table_values</center></body></html>";
    open( $DATA, ">$webdir/heatmap-windows-cpu-vm-values.html" ) or error_die("Cannot open file: $webdir/heatmap-windows-cpu-vm-values.html : $!");
    print $DATA $html;
    close $DATA;

    #my $html3 = "<!DOCTYPE html>\n<html>\n<head>".$style . "</head><body><center>$table_mem_values</center></body></html>";
    open( $DATA, ">$webdir/heatmap-windows-mem-vm-values.html" ) or error_die("Cannot open file: $webdir/heatmap-windows-mem-vm-values.html : $!");
    print $DATA $html;
    close $DATA;

    return 0;
  }
  else {
    # print "$webdir/heatmap-windows-cpu.html\n";
    set_wrap_html_vm();
    my ( $table_cpu, $style_vm, $table_values ) = split( "@", get_table_cpu_lpar_hv() );
    my ( $table_mem, $table_mem_values ) = split( "@", get_table_mem_lpar_hv() );
    if ( $table_mem eq "" ) {
      $memory = "";
    }
    my $style = "<style>" . "$style_vm" . "$style_html" . "</style>";

    #print $style . "\n";
    my $html = "<!DOCTYPE html>\n<html>\n<head>" . $style . "</head><body>\n<table class=" . '"' . "center" . '"' . ">\n<tbody><tr><td><h3>CPU</h3></td></tr>\n<tr>\n<td>" . $table_cpu . "</td></tr>\n<tr>\n<td>&nbsp;</td>\n</tr><tr><td><h3>$memory</h3></td></tr>\n<tr><td>" . $table_mem . "</td></tr><tr><td>" . get_report() . "\n</td></tr><tr><td>&nbsp;</td></tr><tr><td><b>LEGEND</b>:<tr><td>" . get_legend("cpu_ready") . "</td></tr>\n</tbody>\n</table>\n</body></html>";
    open( my $DATA, ">$webdir/heatmap-windows-cpu.html" ) or error_die("Cannot open file: $webdir/heatmap-windows-cpu.html : $!");
    print $DATA $html;
    close $DATA;
    my $html2 = "<!DOCTYPE html>\n<html>\n<head>" . $style . "</head><body><center>$table_values</center></body></html>";
    open( $DATA, ">$webdir/heatmap-windows-cpu-vm-values.html" ) or error_die("Cannot open file: $webdir/heatmap-windows-cpu-vm-values.html : $!");
    print $DATA $html2;
    close $DATA;
    my $html3 = "<!DOCTYPE html>\n<html>\n<head>" . $style . "</head><body><center>$table_mem_values</center></body></html>";
    open( $DATA, ">$webdir/heatmap-windows-mem-vm-values.html" ) or error_die("Cannot open file: $webdir/heatmap-windows-mem-vm-values.html : $!");
    print $DATA $html3;
    close $DATA;

    #print $html . "\n";
  }
}

sub get_table_cpu_lpar_hv {
  use POSIX qw(ceil);
  my $count_row = 1;
  my $nasob     = 0;

  #print "$count_lpars_vm\n";
  #$count_lpars_vm = $count_lpars_vm*20;
  #print "$count_lpars_vm\n";
  if ( $count_lpars_hv == 0 ) { return "" }
  my $cell_size    = ( $height * $width ) / $count_lpars_hv;
  my $td_width     = ceil( sqrt($cell_size) );
  my $td_height    = $td_width;
  my $new_row      = 0;
  my $count_column = 1;

  if ( $td_width < 10 ) {
    $td_width  = 10;
    $td_height = 10;
  }
  if ( $td_width > 42 ) {
    $td_width  = 42;
    $td_height = 42;
  }

  $td_height = $td_height - 2;
  ################
  my $style_vm = " .content_vm { height:" . "$td_height" . "px" . "; width:" . "$td_height" . "px" . ";} h3 {text-align:center;}";
  my $table    = "<table>\n<tbody>\n<tr>\n";

  my $table_values = "<table class =\"lparsearch tablesorter tablesortercfgsum\" data-sortby=\"4\">";
  $table_values = $table_values . "<thead><tr><th class = \"sortable\" title=\"Server\" nowrap=\"\">Server</th>\n";
  $table_values = $table_values . "<th class = \"sortable\" title=\"VM\" nowrap=\"\">VM</th>\n";

  # $table_values = $table_values . "<th class = \"sortable\" title=\"CPU ready\" nowrap=\"\">CPU ready</th>\n";
  $table_values = $table_values . "<th class = \"sortable\" title=\"Utilization %\" nowrap=\"\">Utilization %</th>\n";

  #$table_values = $table_values . "<th class = \"sortable\" title=\"Color\" nowrap=\"\"><center>Color</center></th></tr></thead><tbody>\n";
  $table_values = $table_values . "<th title=\"Color\" nowrap=\"\"><center>Color</center></th></tr></thead><tbody>\n";

  # print Dumper(%vmware);

  # do it before cycles
  my @menu;
  read_menu( \@menu );

  foreach my $server ( sort keys %vmware ) {
    foreach my $lpar ( sort { lc $vmware{$server}{LPAR}{$a}{NAME} cmp lc $vmware{$server}{LPAR}{$b}{NAME} || $vmware{$server}{LPAR}{$a}{NAME} cmp $vmware{$server}{LPAR}{$b}{NAME} } keys %{ $vmware{$server}{LPAR} } ) {
      if ( defined $vmware{$server}{LPAR}{$lpar}{CPU} ) {
        if ( ( $new_row + $td_width ) > $width ) {
          $table   = $table . "</tr>\n<tr>\n";
          $new_row = 0;
        }
        my $percent_util = $vmware{$server}{LPAR}{$lpar}{CPU};
        my $cpu_ready    = $vmware{$server}{LPAR}{$lpar}{CPU_READY};
        if ( !defined $cpu_ready || !isdigit($cpu_ready) ) {
          $cpu_ready = "nan";
        }
        else {
          my $ceil = ceil($cpu_ready);
          $cpu_ready = $ceil;
          $cpu_ready = $cpu_ready . "%";
        }
        if ( "$percent_util" eq "-nan" || "$percent_util" eq "nan" || $percent_util =~ /nan/ || "$percent_util" eq "NaNQ" || $percent_util =~ /NAN/ || $percent_util =~ /NaN/ || !isdigit($percent_util) ) {
          $percent_util = "nan";
        }
        else {
          my $ceil = ceil($percent_util);
          $percent_util = $ceil;
          $percent_util = $percent_util . "%";
        }
        my $url      = $vmware{$server}{LPAR}{$lpar}{URL};
        my $name     = $vmware{$server}{LPAR}{$lpar}{NAME};
        my $url_name = $name;

        #$url_name =~ s/([^A-Za-z0-9\+-_])/sprintf("%%%02X", ord($1))/seg;
        #$url_name =~ s/ /+/g;
        #$url_name =~ s/\#/%23/g;
        $url_name =~ s/([^a-zA-Z0-9_.!~*()'\''-])/sprintf("%%%02X", ord($1))/ge;
        my $domain = $url;
        ( undef, $domain ) = split( "domain_", $domain );
        ( $domain, undef ) = split( "\&", $domain );

        # print "3185 \$url_name $url_name \$url $url \$server $server \$lpar $lpar \$domain $domain\n";

        my $id = $domain . "_server_" . $server . "_vm_" . $lpar;
        $url = "?platform=hyperv&item=vm&domain=$domain&host=$server&name=$url_name&vm_uuid=$lpar&id=$id";

        my $class = get_percent_to_color( $vmware{$server}{LPAR}{$lpar}{CPU}, $vmware{$server}{LPAR}{$lpar}{CPU_READY}, "ready" );
        my $color = $class_color{$class};

        my $lpar_id = $lpar;

        # my @menu;
        # read_menu( \@menu );
        my @matches = grep { /^L/ && /$lpar_id/ } @menu;

        # print "4061 @matches\n";
        if ( !@matches || scalar @matches < 1 ) {
          next;

          #error( "no menu.txt item for \$lpar_id $lpar_id " . __FILE__ . ":" . __LINE__ );
          #return;
        }

        # print STDERR "3421 @matches\n";
        # L:ad.xorux.com:HVNODE01:CBD9D469-A221-4228-816F-3860110150AD:hvlinux01:/lpar2rrd-cgi/detail.sh?host=HVNODE01&server=windows/domain_ad.xorux.com&lpar=CBD9D469-A221-4228-816F-3860110150AD&item=lpar&entitle=0&gui=1&none=none:MSNET-HVCL::H
        # L:ad.int.xorux.com:HYPERV:3138F59F-11AD-46FB-951C-9C147C98896C:XoruX-master:/lpar2rrd-cgi/detail.sh?host=HYPERV&server=windows/domain_ad.int.xorux.com&lpar=3138F59F-11AD-46FB-951C-9C147C98896C&item=lpar&entitle=0&gui=1&none=none:::H
        #
        # (undef,$domain,$server,undef,my $x_lpar,undef,my $hyp_cluster,undef) = split(":",$matches[0] );
        ( undef, $domain, $server, undef, my $x_lpar, undef, my $hyp_cluster, undef ) = split( ":", $matches[0] );

        # print "3433 \$hyp_cluster $hyp_cluster\n";
        if ( defined $hyp_cluster && $hyp_cluster ne "" ) {
          $url = "?platform=hyperv&item=vm&cluster=$hyp_cluster&host=$server&name=$url_name&vm_uuid=$lpar_id&id=$id";
        }

        # new wave solution
        #
        # HOST/VM
        # platform=hyperv&item=vm&domain=ad.int.xorux.com&host=HYPERV&name=XoruX-master
        # if vm is in cluster then cluster is instead of domain
        # $table = $table . "<td class=\"$class\">\n<a href=" . '"' . "$url" . '"' . "><div title =" . '"' . "$server : $name" . " : " . $percent_util . " : CPU ready $cpu_ready" . '"' . "class=" . '"' . "content_vm" . '"' . "></div>\n</a>\n</td>\n";

        $table = $table . "<td class=\"$class\">\n<a href=" . '"' . "$url" . '"' . "><div title =" . '"' . "$domain : $server : $name" . " : " . $percent_util . '"' . "class=" . '"' . "content_vm" . '"' . "></div>\n</a>\n</td>\n";
        $percent_util =~ s/\%//g;
        $cpu_ready    =~ s/\%//g;

        # $table_values = $table_values . "<tr><td>$server</td><td>" . "<a href=\"$url\">$name</a></td><td>$cpu_ready</td><td>$percent_util</td><td><div style=\"height:15px;width:15px;background-color:$color; margin: auto;\"></div></td></tr>\n";
        $table_values = $table_values . "<tr><td>$server</td><td>" . "<a href=\"$url\">$name</a></td><td>$percent_util</td><td><div style=\"height:15px;width:15px;background-color:$color; margin: auto;\"></div></td></tr>\n";

        $new_row = $td_width + $new_row;
      }
      else { next; }
    }
  }
  $table        = $table . "</tr>\n</tbody>\n</table><br>\n";
  $table_values = $table_values . "</tbody></table>";
  my $tb_and_styl = "$table" . "@" . "$style_vm" . "@" . "$table_values";
  return ($tb_and_styl);

  #print "$table_vm\n";
  #print "$count_lpars\n";
}

sub set_wrap_html_hv {
  my $html = "<div id=" . '"' . "tabs" . '"' . ">\n <ul>\n<li><a href=" . '"' . "heatmap-windows-cpu.html" . '"' . ">VM</a></li>\n<li><a href=" . '"' . "heatmap-windows-server.html" . '"' . ">Server</a></li>\n<li><a href=" . '"' . "heatmap-windows-cpu-vm-values.html" . '"' . ">VM CPU Table</a></li>\n<li><a href=" . '"' . "heatmap-windows-mem-vm-values.html" . '"' . ">VM MEM Table</a></li>\n<li><a href=" . '"' . "heatmap-windows-cpu-server-values.html" . '"' . ">Server CPU Table</a></li>\n<li><a href=" . '"' . "heatmap-windows-mem-server-values.html" . '"' . ">Server MEM Table</a></li>\n </ul>\n</div>";
  if ( -e "$webdir/heatmap-windows.html" ) {
  }
  else {
    open( my $DATA, ">$webdir/heatmap-windows.html" ) or error_die("Cannot open file: $webdir/heatmap-windows.html : $!");
    print $DATA $html;
    close $DATA;
  }

}

sub get_html_pool_hv {
  my $check = get_table_cpu_pool_hv();

  # print "3176 \$check $check\n";
  if ( $check eq "" ) {
    return 0;
  }
  else {
    set_wrap_html_hv();
    my ( $table_cpu, $style_vm, $table_values ) = split( "@", get_table_cpu_pool_hv() );
    my ( $table_mem, $table_mem_values ) = split( "@", get_table_mem_pool_hv() );
    my $style = "<style>" . "$style_vm" . "$style_html" . "</style>";

    #print $style . "\n";
    my $html = "<!DOCTYPE html>\n<html>\n<head>" . $style . "</head><body>\n<table class=" . '"' . "center" . '"' . ">\n<tbody><tr><td><h3>CPU</h3></td></tr>\n<tr>\n<td>" . $table_cpu . "</td></tr>\n<tr>\n<td>&nbsp;</td>\n</tr><tr><td><h3>Memory</h3></td></tr>\n<tr><td>" . $table_mem . "</td></tr><tr><td>" . get_report() . "</td></tr><tr><td>&nbsp;</td></tr><tr><td><b>LEGEND</b>:<tr><td>" . get_legend() . "</td></tr>\n</tbody>\n</table>\n</body></html>";
    open( my $DATA, ">$webdir/heatmap-windows-server.html" ) or error_die("Cannot open file: $webdir/heatmap-windows-server.html : $!");
    print $DATA $html;
    close $DATA;

    my $html2 = "<!DOCTYPE html>\n<html>\n<head>" . $style . "</head><body><center>$table_values</center></body></html>";
    open( $DATA, ">$webdir/heatmap-windows-cpu-server-values.html" ) or error_die("Cannot open file: $webdir/heatmap-windows-cpu-server-values.html : $!");
    print $DATA $html2;
    close $DATA;

    my $html3 = "<!DOCTYPE html>\n<html>\n<head>" . $style . "</head><body><center>$table_mem_values</center></body></html>";
    open( $DATA, ">$webdir/heatmap-windows-mem-server-values.html" ) or error_die("Cannot open file: $webdir/heatmap-windows-mem-server-values.html : $!");
    print $DATA $html3;
    close $DATA;

    #print $html . "\n";
  }

}

sub get_table_cpu_pool_hv {
  use POSIX qw(ceil);
  my $count_row = 1;
  my $nasob     = 1;

  #print "$count_pools\n";
  if ( $count_pools_hv == 0 ) { return "" }
  my $cell_size    = ( $height * $width ) / $count_pools_hv;
  my $td_width     = ceil( sqrt($cell_size) );
  my $td_height    = $td_width;
  my $new_row      = 0;
  my $count_column = 1;

  if ( $td_width < 10 ) {
    $td_width  = 10;
    $td_height = 10;
  }
  if ( $td_width > 42 ) {
    $td_width  = 42;
    $td_height = 42;
  }

  $td_height = $td_height - 2;
  ################
  #my $i = 0;
  my $table = "<table>\n<tbody>\n<tr>\n";
  my $style = " .content_pool_vm { height:" . "$td_height" . "px" . "; width:" . "$td_height" . "px" . ";}  h3 {text-align:center;}";

  my $table_values = "<table class =\"lparsearch tablesorter\" data-sortby=\"3\">";
  $table_values = $table_values . "<thead><tr><th class = \"sortable\" title=\"Server\" nowrap=\"\">Server</th>\n";
  $table_values = $table_values . "<th class = \"sortable\" title=\"Pool\" nowrap=\"\">Pool</th>\n";
  $table_values = $table_values . "<th class = \"sortable\" title=\"Utilization %\" nowrap=\"\">Utilization %</th>\n";

  # $table_values = $table_values . "<th class = \"sortable\" title=\"Color\" nowrap=\"\"><center>Color</center></th></tr></thead><tbody>\n";
  $table_values = $table_values . "<th title=\"Color\" nowrap=\"\"><center>Color</center></th></tr></thead><tbody>\n";

  foreach my $server ( sort keys %vmware ) {
    foreach my $pool ( sort { lc $vmware{$server}{POOL}{$a}{NAME} cmp lc $vmware{$server}{POOL}{$b}{NAME} || $vmware{$server}{POOL}{$a}{NAME} cmp $vmware{$server}{POOL}{$b}{NAME} } keys %{ $vmware{$server}{POOL} } ) {
      if ( defined $vmware{$server}{POOL}{$pool}{CPU} ) {
        if ( ( $new_row + $td_width ) > $width ) {
          $table   = $table . "</tr>\n<tr>\n";
          $new_row = 0;
        }
        my $percent_util;
        my $util = $vmware{$server}{POOL}{$pool}{CPU};
        if ( "$util" eq "-nan" || "$util" eq "nan" || $util =~ /nan/ || "$util" eq "NaNQ" || $util =~ /NAN/ || $util =~ /NaN/ || !isdigit($util) ) {
          $percent_util = "nan";
        }
        else {
          $percent_util = ceil( $vmware{$server}{POOL}{$pool}{CPU} ) . "%";
        }
        my $class  = get_percent_to_color($util);
        my $color  = $class_color{$class};
        my $domain = $vmware{$server}{POOL}{$pool}{URL};

        # $url_name =~ s/([^a-zA-Z0-9_.!~*()'\''-])/sprintf("%%%02X", ord($1))/ge;
        ( undef, $domain ) = split( "domain_", $domain );
        ( $domain, undef ) = split( "\&", $domain );

        # print "3317 \$url_name $url_name \$url $url \$server $server \$lpar $lpar \$domain $domain\n";

        # id ad.xorux.com_server_HVNODE02
        my $id  = $domain . "_server_" . $server;
        my $url = "?platform=hyperv&item=host&domain=$domain&name=$server&id=$id&host=host";

        $table = $table . "<td class=\"$class\">\n<a href=" . '"' . "$url" . '"' . "><div title =" . '"' . "$domain : $server : CPU" . " : " . $percent_util . '"' . "class=" . '"' . "content_pool_vm" . '"' . "></div>\n</a>\n</td>\n";
        $percent_util =~ s/\%//g;

        $table_values = $table_values . "<tr><td>$server</td><td>" . "<a href=" . '"' . "$url" . '"' . ">CPU</a></td><td>$percent_util</td><td><div style=\"height:15px;width:15px;background-color:$color; margin: auto;\"></div></td></tr>\n";

        $new_row = $td_width + $new_row;
      }
      else { next; }
    }
  }
  $table        = $table . "</tr>\n</tbody>\n</table><br>\n";
  $table_values = $table_values . "</tbody></table>";
  my $tb_and_style = "$table" . "@" . "$style" . "@" . "$table_values";
  return "$tb_and_style";
}

sub get_table_mem_lpar_hv {
  use POSIX qw(ceil);
  my $count_row = 1;

  #my $pom = $count_lpars_vm;
  #$pom = 0;
  if ( $count_lpars_hv == 0 ) { return "" }
  my $cell_size    = ( $height * $width ) / $count_lpars_hv;
  my $td_width     = ceil( sqrt($cell_size) );
  my $td_height    = $td_width;
  my $new_row      = 0;
  my $count_column = 1;

  if ( $td_width < 10 ) {
    $td_width  = 10;
    $td_height = 10;
  }
  if ( $td_width > 42 ) {
    $td_width  = 42;
    $td_height = 42;
  }

  $td_height = $td_height - 2;
  ################
  my $table        = "<table>\n<tbody>\n<tr>\n";
  my $table_values = "<table class =\"lparsearch tablesorter tablesortercfgsum\" data-sortby=\"3\">";
  $table_values = $table_values . "<thead><tr><th class = \"sortable\" title=\"Server\" nowrap=\"\">Server</th>\n";
  $table_values = $table_values . "<th class = \"sortable\" title=\"VM\" nowrap=\"\">VM</th>\n";
  $table_values = $table_values . "<th class = \"sortable\" title=\"Utilization %\" nowrap=\"\">Utilization %</th>\n";

  # $table_values = $table_values . "<th class = \"sortable\" title=\"Color\" nowrap=\"\"><center>Color</center></th></tr></thead><tbody>\n";
  $table_values = $table_values . "<th title=\"Color\" nowrap=\"\"><center>Color</center></th></tr></thead><tbody>\n";

  # do it before cycles
  my @menu;
  read_menu( \@menu );

  foreach my $server ( sort keys %vmware ) {
    foreach my $lpar ( sort { lc $vmware{$server}{LPAR}{$a}{NAME} cmp lc $vmware{$server}{LPAR}{$b}{NAME} || $vmware{$server}{LPAR}{$a}{NAME} cmp $vmware{$server}{LPAR}{$b}{NAME} } keys %{ $vmware{$server}{LPAR} } ) {
      if ( defined $vmware{$server}{LPAR}{$lpar}{MEMORY} ) {
        if ( ( $new_row + $td_width ) > $width ) {
          $table   = $table . "</tr>\n<tr>\n";
          $new_row = 0;
        }
        my $percent_util = $vmware{$server}{LPAR}{$lpar}{MEMORY};
        if ( "$percent_util" eq "-nan" || "$percent_util" eq "nan" || $percent_util =~ /nan/ || "$percent_util" eq "NaNQ" || $percent_util =~ /NAN/ || $percent_util =~ /NaN/ || !isdigit($percent_util) ) {
          $percent_util = "nan";
        }
        else {
          my $ceil = ceil($percent_util);
          $percent_util = $ceil;
          $percent_util = $percent_util . "%";
        }
        my $url      = $vmware{$server}{LPAR}{$lpar}{URL};
        my $name     = $vmware{$server}{LPAR}{$lpar}{NAME};
        my $url_name = $name;

        #$url_name =~ s/([^A-Za-z0-9\+-_])/sprintf("%%%02X", ord($1))/seg;
        #$url_name =~ s/ /+/g;
        #$url_name =~ s/\#/%23/g;
        $url_name =~ s/([^a-zA-Z0-9_.!~*()'\''-])/sprintf("%%%02X", ord($1))/ge;
        my $domain = $url;
        ( undef, $domain ) = split( "domain_", $domain );
        ( $domain, undef ) = split( "\&", $domain );

        # print "3370 \$url_name $url_name \$url $url \$server $server \$lpar $lpar \$domain $domain\n";
        my $id = $domain . "_server_" . $server . "_vm_" . $lpar;

        $url = "?platform=hyperv&item=vm&domain=$domain&host=$server&name=$url_name&vm_uuid=$lpar&id=$id";

        #print $name . "\n";
        #       $url =~ s/lpar=.*&item/lpar=$url_name&item/g;
        my $class = get_percent_to_color( $vmware{$server}{LPAR}{$lpar}{MEMORY} );
        my $color = $class_color{$class};

        my $lpar_id = $lpar;

        # my @menu;
        # read_menu( \@menu );
        my @matches = grep { /^L/ && /$lpar_id/ } @menu;

        # print "4316 @matches\n";
        if ( !@matches || scalar @matches < 1 ) {
          next;

          #error( "no menu.txt item for \$lpar_id $lpar_id " . __FILE__ . ":" . __LINE__ );
          #return;
        }

        # print STDERR "3421 @matches\n";
        # L:ad.xorux.com:HVNODE01:CBD9D469-A221-4228-816F-3860110150AD:hvlinux01:/lpar2rrd-cgi/detail.sh?host=HVNODE01&server=windows/domain_ad.xorux.com&lpar=CBD9D469-A221-4228-816F-3860110150AD&item=lpar&entitle=0&gui=1&none=none:MSNET-HVCL::H
        # L:ad.int.xorux.com:HYPERV:3138F59F-11AD-46FB-951C-9C147C98896C:XoruX-master:/lpar2rrd-cgi/detail.sh?host=HYPERV&server=windows/domain_ad.int.xorux.com&lpar=3138F59F-11AD-46FB-951C-9C147C98896C&item=lpar&entitle=0&gui=1&none=none:::H
        #
        ( undef, $domain, $server, undef, my $x_lpar, undef, my $hyp_cluster, undef ) = split( ":", $matches[0] );

        # print "3433 \$hyp_cluster $hyp_cluster\n";
        if ( defined $hyp_cluster && $hyp_cluster ne "" ) {
          $url = "?platform=hyperv&item=vm&cluster=$hyp_cluster&host=$server&name=$url_name&vm_uuid=$lpar_id&id=$id";
        }

        # new wave solution
        #
        # HOST/VM
        # platform=hyperv&item=vm&domain=ad.int.xorux.com&host=HYPERV&name=XoruX-master
        # if vm is in cluster then cluster is instead of domain

        $table = $table . "<td class=\"$class\">\n<a href=" . '"' . "$url" . '"' . "><div title =" . '"' . "$domain : $server : $name" . " : " . $percent_util . '"' . "class=" . '"' . "content_vm" . '"' . "></div>\n</a>\n</td>\n";

        $percent_util =~ s/\%//g;

        $table_values = $table_values . "<tr><td>$server</td><td>" . "<a href=\"$url\">$name</a></td><td>$percent_util</td><td><div style=\"height:15px;width:15px;background-color:$color; margin: auto;\"></div></td></tr>\n";

        $new_row = $td_width + $new_row;
      }
      else { next; }
    }
  }
  $table        = $table . "</tr>\n</tbody>\n</table><br>\n";
  $table_values = $table_values . "</tbody></table>";
  my $tb = $table . "@" . $table_values;
  return $tb;

  #print "$table_vm\n";
  #print "$count_lpars\n";
}

sub get_table_mem_pool_hv {
  use POSIX qw(ceil);
  my $count_row = 1;
  my $nasob     = 1;

  #print "$count_pools\n";
  if ( $count_pools_hv == 0 ) { return "" }
  my $cell_size    = ( $height * $width ) / $count_pools_hv;
  my $td_width     = ceil( sqrt($cell_size) );
  my $td_height    = $td_width;
  my $new_row      = 0;
  my $count_column = 1;

  if ( $td_width < 10 ) {
    $td_width  = 10;
    $td_height = 10;
  }
  if ( $td_width > 42 ) {
    $td_width  = 42;
    $td_height = 42;
  }

  $td_height = $td_height - 2;
  ################
  #my $i = 0;
  my $table = "<table>\n<tbody>\n<tr>\n";

  my $table_values = "<table class =\"lparsearch tablesorter\" data-sortby=\"3\">";
  $table_values = $table_values . "<thead><tr><th class = \"sortable\" title=\"Server\" nowrap=\"\">Server</th>\n";
  $table_values = $table_values . "<th class = \"sortable\" title=\"Pool\" nowrap=\"\">Pool</th>\n";
  $table_values = $table_values . "<th class = \"sortable\" title=\"Utilization %\" nowrap=\"\">Utilization %</th>\n";

  # $table_values = $table_values . "<th class = \"sortable\" title=\"Color\" nowrap=\"\"><center>Color</center></th></tr></thead><tbody>\n";
  $table_values = $table_values . "<th title=\"Color\" nowrap=\"\"><center>Color</center></th></tr></thead><tbody>\n";

  foreach my $server ( sort keys %vmware ) {
    foreach my $pool ( sort { lc $vmware{$server}{POOL}{$a}{NAME} cmp lc $vmware{$server}{POOL}{$b}{NAME} || $vmware{$server}{POOL}{$a}{NAME} cmp $vmware{$server}{POOL}{$b}{NAME} } keys %{ $vmware{$server}{POOL} } ) {
      if ( defined $vmware{$server}{POOL}{$pool}{MEMORY} ) {
        if ( ( $new_row + $td_width ) > $width ) {
          $table   = $table . "</tr>\n<tr>\n";
          $new_row = 0;
        }
        my $percent_util;
        my $util = $vmware{$server}{POOL}{$pool}{MEMORY};
        if ( "$util" eq "-nan" || "$util" eq "nan" || $util =~ /nan/ || "$util" eq "NaNQ" || $util =~ /NAN/ || $util =~ /NaN/ || !isdigit($util) ) {
          $percent_util = "nan";
        }
        else {
          $percent_util = ceil( $vmware{$server}{POOL}{$pool}{MEMORY} ) . "%";
        }
        my $domain = $vmware{$server}{POOL}{$pool}{URL};

        # $url_name =~ s/([^a-zA-Z0-9_.!~*()'\''-])/sprintf("%%%02X", ord($1))/ge;
        ( undef, $domain ) = split( "domain_", $domain );
        ( $domain, undef ) = split( "\&", $domain );

        # id ad.xorux.com_server_HVNODE02
        my $id  = $domain . "_server_" . $server;
        my $url = "?platform=hyperv&item=host&domain=$domain&name=$server&id=$id&host=host";

        my $class = get_percent_to_color($util);
        my $color = $class_color{$class};

        $table = $table . "<td class=\"$class\">\n<a href=" . '"' . "$url" . '"' . "><div title =" . '"' . "$domain : $server : MEM" . " : " . $percent_util . '"' . "class=" . '"' . "content_pool_vm" . '"' . "></div>\n</a>\n</td>\n";

        $percent_util =~ s/\%//g;

        $table_values = $table_values . "<tr><td>$server</td><td>" . "<a href=" . '"' . "$url" . '"' . ">MEM</a></td><td>$percent_util</td><td><div style=\"height:15px;width:15px;background-color:$color; margin: auto;\"></div></td></tr>\n";

        $new_row = $td_width + $new_row;
      }
      else { next; }
    }
  }
  $table        = $table . "</tr>\n</tbody>\n</table><br>\n";
  $table_values = $table_values . "</tbody></table>";
  return "$table" . "@" . $table_values;
}

#########
#########  HYPERV subs end of section

sub set_structure_oraclevm {
  my $file = "$basedir/tmp/menu_oraclevm.json";
  if ( !-f $file ) { return 1; }
  my $data = get_json($file);
  if ( !defined $data->{children} || ref( $data->{children} ) ne "ARRAY" ) { return 1; }
  foreach my $element ( @{ $data->{children} } ) {
    if ( !defined $element->{children} || ref( $element->{children} ) ne "ARRAY" ) { next; }
    my $title = $element->{title};
    if ( !defined $title ) { next; }
    $oraclevm{$title}{NAME} = $title;
    foreach my $cluster ( @{ $element->{children} } ) {
      if ( !defined $cluster->{children} || ref( $cluster->{children} ) ne "ARRAY" ) { next; }
      my $title_cluster = $cluster->{title};
      if ( !defined $title_cluster || $title_cluster eq "Totals" || $title_cluster eq "Storage" ) { next; }
      $oraclevm{$title}{CLUSTER}{$title_cluster}{NAME} = $title_cluster;
      foreach my $type_server ( @{ $cluster->{children} } ) {
        my $title_server = $type_server->{title};
        if ( ( $title_server eq "Server" || $title_server eq "VM" ) && defined $type_server->{children} && ref( $type_server->{children} ) eq "ARRAY" ) {
          my $type     = uc($title_server);
          my $type_url = lc($title_server);
          foreach my $server ( @{ $type_server->{children} } ) {
            my $href = $server->{href};
            my $name = $server->{title};
            if ( !defined $href || !defined $name ) { next; }
            my ( undef, undef, $host ) = split( "&", $href );
            if ( defined $host && $host =~ m/^id=/ ) {
              $host =~ s/id=//;
              $oraclevm{$title}{CLUSTER}{$title_cluster}{$type}{$host}{ID}   = $host;
              $oraclevm{$title}{CLUSTER}{$title_cluster}{$type}{$host}{URL}  = $href;
              $oraclevm{$title}{CLUSTER}{$title_cluster}{$type}{$host}{NAME} = $name;
              if ( $title_server eq "VM" ) {
                if ( !defined $types{"OracleVM"} ) {
                  $types{"OracleVM"} = 0;
                }
                $types{"OracleVM"} = $types{"OracleVM"} + 1;
              }
            }
          }
        }
      }
    }
  }
}

sub set_structure_xen {
  my $file = "$basedir/tmp/menu_xenserver.json";
  if ( !-f $file ) { return 1; }
  my $data = get_json($file);
  if ( !defined $data->{children} || ref( $data->{children} ) ne "ARRAY" ) { return 1; }
  foreach my $element ( @{ $data->{children} } ) {
    if ( !defined $element->{children} || ref( $element->{children} ) ne "ARRAY" ) { next; }
    my $title = $element->{title};
    if ( !defined $title ) { next; }
    $xen{$title}{NAME} = $title;
    foreach my $cluster ( @{ $element->{children} } ) {
      if ( !defined $cluster->{children} || ref( $cluster->{children} ) ne "ARRAY" ) { next; }
      my $title_cluster = $cluster->{title};
      if ( !defined $title_cluster || $title_cluster eq "Totals" || $title_cluster eq "Storage" ) { next; }
      if ( $title_cluster ne "VM" ) {
        $xen{$title}{SERVER}{$title_cluster}{NAME} = $title_cluster;
        foreach my $server ( @{ $cluster->{children} } ) {
          my $title_server = $server->{title};
          if ( !defined $title_server || $title_server ne $title_cluster ) { next; }
          my $href = $server->{href};
          if ( !defined $href ) { next; }
          my ( undef, undef, $host ) = split( "&", $href );
          if ( defined $host && $host =~ m/^id=/ ) {
            $host =~ s/id=//g;
            $xen{$title}{SERVER}{$title_cluster}{ID}  = $host;
            $xen{$title}{SERVER}{$title_cluster}{URL} = $href;
          }
        }
      }
      else {
        foreach my $server ( @{ $cluster->{children} } ) {
          my $title_server = $server->{title};
          if ( !defined $title_server ) { next; }
          my $href = $server->{href};
          if ( !defined $href ) { next; }
          my ( undef, undef, $host ) = split( "&", $href );
          if ( defined $host && $host =~ m/^id=/ ) {
            $host =~ s/id=//g;
            $xen{$title}{VM}{$title_server}{ID}   = $host;
            $xen{$title}{VM}{$title_server}{URL}  = $href;
            $xen{$title}{VM}{$title_server}{NAME} = $title_server;
            $types{"XenServer"}                   = $types{"XenServer"} + 1;
          }
        }
      }
    }
  }
}

sub set_structure_nutanix {
  my $file = "$basedir/tmp/menu_nutanix.json";
  if ( !-f $file ) { return 1; }
  my $data = get_json($file);
  if ( !defined $data->{children} || ref( $data->{children} ) ne "ARRAY" ) { return 1; }
  foreach my $element ( @{ $data->{children} } ) {
    if ( !defined $element->{children} || ref( $element->{children} ) ne "ARRAY" ) { next; }
    my $title = $element->{title};
    if ( !defined $title ) { next; }
    $nutanix{$title}{NAME} = $title;
    foreach my $cluster ( @{ $element->{children} } ) {
      if ( !defined $cluster->{children} || ref( $cluster->{children} ) ne "ARRAY" ) { next; }
      my $title_cluster = $cluster->{title};
      if ( !defined $title_cluster || $title_cluster eq "Totals" || $title_cluster eq "Storage" ) { next; }
      if ( $title_cluster ne "VM" ) {
        if ( $title_cluster ne "Storage" ) {
          foreach my $server ( @{ $cluster->{children} } ) {
            my $title_server = $server->{title};
            if ( !defined $title_server || $title_server eq $title_cluster ) { next; }
            my $href = $server->{href};
            if ( !defined $href ) { next; }
            my ( undef, undef, $host ) = split( "&", $href );
            if ( defined $host && $host =~ m/^id=/ ) {
              $host =~ s/id=//g;
              $nutanix{$title}{SERVER}{$title_server}{NAME} = 'Test';
              $nutanix{$title}{SERVER}{$title_server}{ID}   = $host;
              $nutanix{$title}{SERVER}{$title_server}{URL}  = $href;
            }
          }
        }
      }
      else {
        foreach my $server ( @{ $cluster->{children} } ) {
          my $title_server = $server->{title};
          if ( !defined $title_server ) { next; }
          my $href = $server->{href};
          if ( !defined $href ) { next; }
          my ( undef, undef, $host ) = split( "&", $href );
          if ( defined $host && $host =~ m/^id=/ ) {
            $host =~ s/id=//g;
            $nutanix{$title}{VM}{$title_server}{ID}   = $host;
            $nutanix{$title}{VM}{$title_server}{URL}  = $href;
            $nutanix{$title}{VM}{$title_server}{NAME} = $title_server;
          }
        }
      }
    }
  }
}

sub set_structure_proxmox {
  my $file = "$basedir/tmp/menu_proxmox.json";
  if ( !-f $file ) { return 1; }
  my $data = get_json($file);
  if ( !defined $data->{children} || ref( $data->{children} ) ne "ARRAY" ) { return 1; }
  foreach my $element ( @{ $data->{children} } ) {
    if ( !defined $element->{children} || ref( $element->{children} ) ne "ARRAY" ) { next; }
    my $title = $element->{title};
    if ( !defined $title ) { next; }
    $proxmox{$title}{NAME} = $title;
    foreach my $cluster ( @{ $element->{children} } ) {
      if ( !defined $cluster->{children} || ref( $cluster->{children} ) ne "ARRAY" ) { next; }
      my $title_cluster = $cluster->{title};
      if ( !defined $title_cluster || $title_cluster =~ "Totals" || $title_cluster eq "Storage" || $title_cluster eq "LXC" ) { next; }
      if ( $title_cluster ne "VM" ) {
        foreach my $server ( @{ $cluster->{children} } ) {
          my $title_server = $server->{title};
          if ( !defined $title_server || $title_server eq $title_cluster ) { next; }
          my $href = $server->{href};
          if ( !defined $href ) { next; }
          my ( undef, undef, $host ) = split( "&", $href );
          if ( defined $host && $host =~ m/^id=/ ) {
            $host =~ s/id=//g;
            $proxmox{$title}{SERVER}{$title_server}{NAME} = $title_server;
            $proxmox{$title}{SERVER}{$title_server}{ID}   = $host;
            $proxmox{$title}{SERVER}{$title_server}{URL}  = $href;
          }
        }
      }
      else {
        foreach my $server ( @{ $cluster->{children} } ) {
          my $title_server = $server->{title};
          if ( !defined $title_server ) { next; }
          my $href = $server->{href};
          if ( !defined $href ) { next; }
          my ( undef, undef, $host ) = split( "&", $href );
          if ( defined $host && $host =~ m/^id=/ ) {
            $host =~ s/id=//g;
            $proxmox{$title}{VM}{$title_server}{ID}   = $host;
            $proxmox{$title}{VM}{$title_server}{URL}  = $href;
            $proxmox{$title}{VM}{$title_server}{NAME} = $title_server;
          }
        }
      }
    }
  }
}

sub set_structure_fusioncompute {
  my $file = "$basedir/tmp/menu_fusioncompute.json";
  if ( !-f $file ) { return 1; }
  my $data = get_json($file);
  if ( !defined $data->{children} || ref( $data->{children} ) ne "ARRAY" ) { return 1; }
  foreach my $element ( @{ $data->{children} } ) {
    if ( !defined $element->{children} || ref( $element->{children} ) ne "ARRAY" ) { next; }
    my $title = $element->{title};
    if ( !defined $title ) { next; }
    $fusioncompute{$title}{NAME} = $title;
    foreach my $site ( @{ $element->{children} } ) {
      if ( !defined $site->{children} || ref( $site->{children} ) ne "ARRAY" ) { next; }
      my $title_site = $site->{title};
      if ( !defined $title_site || $title_site =~ "Totals" || $title_site eq "Datastore" ) { next; }
      foreach my $cluster_folder ( @{ $site->{children} } ) {
        if ( !defined $cluster_folder->{children} || ref( $cluster_folder->{children} ) ne "ARRAY" ) { next; }
        foreach my $cluster ( @{ $cluster_folder->{children} } ) {
          if ( !defined $cluster->{children} || ref( $cluster->{children} ) ne "ARRAY" ) { next; }
          my $title_cluster = $cluster->{title};
          if ( !defined $title_cluster || $title_cluster =~ "Totals" || $title_cluster eq "Cluster" ) { next; }
          if ( $title_cluster eq "Host" ) {
            foreach my $server ( @{ $cluster->{children} } ) {
              my $title_server = $server->{title};
              if ( !defined $title_server || $title_server eq $title_cluster ) { next; }
              my $href = $server->{href};
              if ( !defined $href ) { next; }
              my ( undef, undef, $host ) = split( "&", $href );
              if ( defined $host && $host =~ m/^id=/ ) {
                $host =~ s/id=//g;
                $fusioncompute{$title}{SERVER}{$title_server}{NAME} = $title_server;
                $fusioncompute{$title}{SERVER}{$title_server}{ID}   = $host;
                $fusioncompute{$title}{SERVER}{$title_server}{URL}  = $href;
              }
            }
          }
          elsif ( $title_cluster eq "VM" ) {
            foreach my $server ( @{ $cluster->{children} } ) {
              my $title_server = $server->{title};
              if ( !defined $title_server ) { next; }
              my $href = $server->{href};
              if ( !defined $href ) { next; }
              my ( undef, undef, $host ) = split( "&", $href );
              if ( defined $host && $host =~ m/^id=/ ) {
                $host =~ s/id=//g;
                $fusioncompute{$title}{VM}{$title_server}{ID}   = $host;
                $fusioncompute{$title}{VM}{$title_server}{URL}  = $href;
                $fusioncompute{$title}{VM}{$title_server}{NAME} = $title_server;
              }
            }
          }
        }
      }
    }
  }
}

sub set_structure_ovirt {
  my $file = "$basedir/tmp/menu_ovirt.json";

  if ( !-f $file ) {
    return 1;
  }
  my $data = get_json($file);

  #print Dumper \$data;
  if ( !defined $data->{children} || ref( $data->{children} ) ne "ARRAY" ) { return 1; }
  foreach my $element ( @{ $data->{children} } ) {
    if ( !defined $element->{children} || ref( $element->{children} ) ne "ARRAY" ) { next; }
    my $title = $element->{title};
    if ( !defined $title ) { next; }
    $ovirt{DATACENTER}{$title}{NAME} = $title;
    foreach my $cluster ( @{ $element->{children} } ) {
      if ( !defined $cluster->{children} || ref( $cluster->{children} ) ne "ARRAY" ) { next; }
      my $title_cluster = $cluster->{title};
      if ( !defined $title_cluster || $title_cluster eq "Storage domain" ) { next; }
      $ovirt{DATACENTER}{$title}{CLUSTER}{$title_cluster}{NAME} = $title_cluster;
      foreach my $server ( @{ $cluster->{children} } ) {
        if ( !defined $server->{children} || ref( $server->{children} ) ne "ARRAY" ) { next; }
        my $title_server = $server->{title};
        if ( !defined $title_server ) { next; }
        foreach my $test ( @{ $server->{children} } ) {
          my $href = $test->{href};
          if ( !defined $href ) { next; }

          #/lpar2rrd-cgi/detail.sh?platform=oVirt&type=host_nic_aggr&id=be4602f0-8548-44c2-ac30-5a81e91cb3d8
          my ( undef, undef, $host ) = split( "&", $href );
          if ( defined $host && $host =~ m/^id=/ ) {
            $ovirt{DATACENTER}{$title}{CLUSTER}{$title_cluster}{SERVER}{$title_server}{NAME} = $title_server;
            $host =~ s/^id=//;
            $ovirt{DATACENTER}{$title}{CLUSTER}{$title_cluster}{SERVER}{$title_server}{ID}  = $host;
            $ovirt{DATACENTER}{$title}{CLUSTER}{$title_cluster}{SERVER}{$title_server}{URL} = $href;
          }
        }
        if ( $title_server eq "VM" ) {
          foreach my $test ( @{ $server->{children} } ) {
            my $href     = $test->{href};
            my $title_vm = $test->{title};
            if ( !defined $href || !defined $title ) { next; }
            my ( undef, undef, $host ) = split( "&", $href );
            $host =~ s/^id=//;
            $ovirt{DATACENTER}{$title}{CLUSTER}{$title_cluster}{VM}{$title_vm}{NAME} = $title_vm;
            $ovirt{DATACENTER}{$title}{CLUSTER}{$title_cluster}{VM}{$title_vm}{ID}   = $host;
            $ovirt{DATACENTER}{$title}{CLUSTER}{$title_cluster}{VM}{$title_vm}{URL}  = $href;
            $types{"oVirt"}                                                          = $types{"oVirt"} + 1;
          }
        }

        #print Dumper \$server;
      }
    }
  }

  #print Dumper \%ovirt;
  return 1;
}

sub set_utilization_oraclevm {

  my $type = shift;
  my $item = shift;

  foreach my $machine ( keys %oraclevm ) {
    foreach my $cluster ( keys %{ $oraclevm{$machine}{CLUSTER} } ) {
      foreach my $element ( keys %{ $oraclevm{$machine}{CLUSTER}{$cluster}{$type} } ) {
        my $id = $oraclevm{$machine}{CLUSTER}{$cluster}{$type}{$element}{ID};
        if ( !defined $id ) { next; }
        my $lc_type = lc($type);
        my $file    = "$basedir/data/OracleVM/$lc_type/$id/sys.rrd";
        if ( -f $file ) {
          my ($cpu_util) = get_utilization_ovirt( $file, $type, $item, "ORACLEVM" );
          if ( defined $cpu_util ) {
            $oraclevm{$machine}{CLUSTER}{$cluster}{$type}{$element}{$item} = $cpu_util;
            if ( $type eq "SERVER" && $item eq "CPU" ) {
              $count_server_oraclevm++;
            }
            if ( $type eq "VM" && $item eq "CPU" ) {
              $count_vm_oraclevm++;
            }
          }
          next;
        }
      }
    }
  }
}

sub set_utilization_nutanix {
  my $type = shift;
  my $item = shift;

  foreach my $cluster ( keys %nutanix ) {
    foreach my $server ( keys %{ $nutanix{$cluster}{$type} } ) {
      my $id = $nutanix{$cluster}{$type}{$server}{ID};
      if ( !defined $id ) { next; }
      my $file = "";
      if ( $type eq "SERVER" ) {
        $file = "$basedir/data/NUTANIX/HOST/$id/sys.rrd";
      }
      if ( $type eq "VM" ) {
        $file = "$basedir/data/NUTANIX/VM/$id.rrd";
      }
      if ( !-f $file ) { next; }
      if ( $item eq "MEMORY" ) {
        my ($cpu_util) = get_utilization_ovirt( $file, $type, "MEMORY-NUTANIX" );
        if ( defined $cpu_util ) {
          $nutanix{$cluster}{$type}{$server}{$item} = $cpu_util;
        }
        next;
      }
      my ($cpu_util) = get_utilization_ovirt( $file, $type, $item, "NUTANIX" );
      if ( defined $cpu_util ) {
        if ( $type eq "SERVER" && $item eq "CPU" ) {
          $count_server_nutanix++;
        }
        if ( $type eq "VM" && $item eq "CPU" ) {
          $count_vm_nutanix++;
        }
        $nutanix{$cluster}{$type}{$server}{$item} = $cpu_util;
      }
    }
  }
}

sub set_utilization_proxmox {
  my $type = shift;
  my $item = shift;

  foreach my $cluster ( keys %proxmox ) {
    foreach my $server ( keys %{ $proxmox{$cluster}{$type} } ) {
      my $id = $proxmox{$cluster}{$type}{$server}{ID};
      if ( !defined $id ) { next; }
      my $file = "";
      if ( $type eq "SERVER" ) {
        $file = "$basedir/data/Proxmox/Node/$id.rrd";
      }
      if ( $type eq "VM" ) {
        $file = "$basedir/data/Proxmox/VM/$id.rrd";
      }
      if ( !-f $file ) { next; }
      if ( $item eq "MEMORY" ) {
        my ($cpu_util) = get_utilization_ovirt( $file, $type, "MEMORY-PROXMOX" );
        if ( defined $cpu_util ) {
          $proxmox{$cluster}{$type}{$server}{$item} = $cpu_util;
        }
        next;
      }
      my ($cpu_util) = get_utilization_ovirt( $file, $type, $item, "PROXMOX" );
      if ( defined $cpu_util ) {
        if ( $type eq "SERVER" && $item eq "CPU" ) {
          $count_server_proxmox++;
        }
        if ( $type eq "VM" && $item eq "CPU" ) {
          $count_vm_proxmox++;
        }
        $proxmox{$cluster}{$type}{$server}{$item} = $cpu_util;
      }
    }
  }
}

sub set_utilization_fusioncompute {
  my $type = shift;
  my $item = shift;

  foreach my $cluster ( keys %fusioncompute ) {
    foreach my $server ( keys %{ $fusioncompute{$cluster}{$type} } ) {
      my $id = $fusioncompute{$cluster}{$type}{$server}{ID};
      if ( !defined $id ) { next; }
      my $file = "";
      if ( $type eq "SERVER" ) {
        $file = "$basedir/data/FusionCompute/Host/$id.rrd";
      }
      if ( $type eq "VM" ) {
        $file = "$basedir/data/FusionCompute/VM/$id.rrd";
      }
      if ( !-f $file ) { next; }
      if ( $item eq "MEMORY" ) {
        my ($cpu_util) = get_utilization_ovirt( $file, $type, "MEMORY-FUSIONCOMPUTE" );
        if ( defined $cpu_util ) {
          $fusioncompute{$cluster}{$type}{$server}{$item} = $cpu_util;
        }
        next;
      }
      my ($cpu_util) = get_utilization_ovirt( $file, $type, $item, "FUSIONCOMPUTE" );
      if ( defined $cpu_util ) {
        if ( $type eq "SERVER" && $item eq "CPU" ) {
          $count_server_fusioncompute++;
        }
        if ( $type eq "VM" && $item eq "CPU" ) {
          $count_vm_fusioncompute++;
        }
        $fusioncompute{$cluster}{$type}{$server}{$item} = $cpu_util;
      }
    }
  }
}

sub set_utilization_xen {
  my $type = shift;
  my $item = shift;

  foreach my $cluster ( keys %xen ) {
    foreach my $server ( keys %{ $xen{$cluster}{$type} } ) {
      my $id = $xen{$cluster}{$type}{$server}{ID};
      if ( !defined $id ) { next; }
      my $file = "";
      if ( $type eq "SERVER" ) {
        $file = "$basedir/data/XEN/$id/sys.rrd";
      }
      if ( $type eq "VM" ) {
        $file = "$basedir/data/XEN_VMs/$id.rrd";
      }
      if ( !-f $file ) { next; }
      if ( $item eq "MEMORY" ) {
        my ($cpu_util) = get_utilization_ovirt( $file, $type, "MEMORY-XEN" );
        if ( defined $cpu_util ) {
          $xen{$cluster}{$type}{$server}{$item} = $cpu_util;
        }
        next;
      }
      my ($cpu_util) = get_utilization_ovirt( $file, $type, $item, "XEN" );
      if ( defined $cpu_util ) {
        if ( $type eq "SERVER" && $item eq "CPU" ) {
          $count_server_xen++;
        }
        if ( $type eq "VM" && $item eq "CPU" ) {
          $count_vm_xen++;
        }
        $xen{$cluster}{$type}{$server}{$item} = $cpu_util;
      }
    }
  }
}

sub set_utilization_ovirt {
  my $type = shift;
  my $item = shift;

  foreach my $datacenter ( keys %{ $ovirt{DATACENTER} } ) {
    foreach my $cluster ( keys %{ $ovirt{DATACENTER}{$datacenter}{CLUSTER} } ) {
      #### server ###
      foreach my $server ( keys %{ $ovirt{DATACENTER}{$datacenter}{CLUSTER}{$cluster}{$type} } ) {
        my $id = $ovirt{DATACENTER}{$datacenter}{CLUSTER}{$cluster}{$type}{$server}{ID};
        if ( !defined $id ) { next; }
        my $file = "";
        if ( $type eq "SERVER" ) {
          $file = "$basedir/data/oVirt/host/$id/sys.rrd";
        }
        if ( $type eq "VM" ) {
          $file = "$basedir/data/oVirt/vm/$id/sys.rrd";
        }
        if ( !-f $file ) { next; }
        my ($cpu_util) = get_utilization_ovirt( $file, $type, $item );
        if ( defined $cpu_util ) {
          $ovirt{DATACENTER}{$datacenter}{CLUSTER}{$cluster}{$type}{$server}{$item} = $cpu_util;
          if ( $type eq "SERVER" && $item eq "CPU" ) {
            $count_server_ovirt++;
          }
          if ( $type eq "VM" && $item eq "CPU" ) {
            $count_vm_ovirt++;
          }
        }
      }
      ####
    }
  }

  #print Dumper \%ovirt;
}

sub set_html_ovirt {

  get_html_ovirt( "SERVER", $count_server_ovirt, "CPU",    "OVIRT" );
  get_html_ovirt( "SERVER", $count_server_ovirt, "MEMORY", "OVIRT" );
  get_html_ovirt( "VM",     $count_vm_ovirt,     "CPU",    "OVIRT" );
  get_html_ovirt( "VM",     $count_vm_ovirt,     "MEMORY", "OVIRT" );

}

sub set_html_xen {

  get_html_ovirt( "SERVER", $count_server_xen, "CPU",    "XEN" );
  get_html_ovirt( "SERVER", $count_server_xen, "MEMORY", "XEN" );
  get_html_ovirt( "VM",     $count_vm_xen,     "CPU",    "XEN" );
  get_html_ovirt( "VM",     $count_vm_xen,     "MEMORY", "XEN" );

}

sub set_html_oraclevm {

  get_html_ovirt( "SERVER", $count_server_oraclevm, "CPU",    "ORACLEVM" );
  get_html_ovirt( "SERVER", $count_server_oraclevm, "MEMORY", "ORACLEVM" );
  get_html_ovirt( "VM",     $count_vm_oraclevm,     "CPU",    "ORACLEVM" );

}

sub set_html_nutanix {

  get_html_ovirt( "SERVER", $count_server_nutanix, "CPU",    "NUTANIX" );
  get_html_ovirt( "SERVER", $count_server_nutanix, "MEMORY", "NUTANIX" );
  get_html_ovirt( "VM",     $count_vm_nutanix,     "CPU",    "NUTANIX" );
  get_html_ovirt( "VM",     $count_vm_nutanix,     "MEMORY", "NUTANIX" );

}

sub set_html_proxmox {

  get_html_ovirt( "SERVER", $count_server_proxmox, "CPU",    "PROXMOX" );
  get_html_ovirt( "SERVER", $count_server_proxmox, "MEMORY", "PROXMOX" );
  get_html_ovirt( "VM",     $count_vm_proxmox,     "CPU",    "PROXMOX" );
  get_html_ovirt( "VM",     $count_vm_proxmox,     "MEMORY", "PROXMOX" );

}

sub set_html_fusioncompute {

  get_html_ovirt( "SERVER", $count_server_fusioncompute, "CPU",    "FUSIONCOMPUTE" );
  get_html_ovirt( "SERVER", $count_server_fusioncompute, "MEMORY", "FUSIONCOMPUTE" );
  get_html_ovirt( "VM",     $count_vm_fusioncompute,     "CPU",    "FUSIONCOMPUTE" );
  get_html_ovirt( "VM",     $count_vm_fusioncompute,     "MEMORY", "FUSIONCOMPUTE" );

}

sub get_html_ovirt {
  my $type    = shift;
  my $count   = shift;
  my $item    = shift;
  my $tech    = shift;
  my $lc_type = lc($type);
  my $lc_tech = lc($tech);

  my $check = "";

  if ( $tech eq "XEN" ) {
    $check = get_table_xen( $type, $count, $item );
  }
  elsif ( $tech eq "NUTANIX" ) {
    $check = get_table_nutanix( $type, $count, $item );
  }
  elsif ( $tech eq "PROXMOX" ) {
    $check = get_table_proxmox( $type, $count, $item );
  }
  elsif ( $tech eq "FUSIONCOMPUTE" ) {
    $check = get_table_fusioncompute( $type, $count, $item );
  }
  elsif ( $tech eq "ORACLEVM" ) {
    $check = get_table_oraclevm( $type, $count, $item );
  }
  else {
    $check = get_table_ovirt( $type, $count, $item );
  }
  if ( $check eq "" ) {
    return 0;
  }
  else {
    set_wrap_html_ovirt($lc_tech);
    my $table        = "";
    my $style        = "";
    my $table_values = "";
    if ( $tech eq "XEN" ) {
      ( $table, $style, $table_values ) = split( "@", get_table_xen( $type, $count, $item ) );
    }
    elsif ( $tech eq "NUTANIX" ) {
      ( $table, $style, $table_values ) = split( "@", get_table_nutanix( $type, $count, $item ) );
    }
    elsif ( $tech eq "PROXMOX" ) {
      ( $table, $style, $table_values ) = split( "@", get_table_proxmox( $type, $count, $item ) );
    }
    elsif ( $tech eq "FUSIONCOMPUTE" ) {
      ( $table, $style, $table_values ) = split( "@", get_table_fusioncompute( $type, $count, $item ) );
    }
    elsif ( $tech eq "ORACLEVM" ) {
      ( $table, $style, $table_values ) = split( "@", get_table_oraclevm( $type, $count, $item ) );
    }
    else {
      ( $table, $style, $table_values ) = split( "@", get_table_ovirt( $type, $count, $item ) );
    }

    #my $table_mem = get_table_mem_lpar_power();
    #if ( $table_mem eq "" ) {
    #  $memory = "";
    #}
    $style = "<style>" . "$style" . "$style_html" . "</style>";

    #print get_legend();
    my $table_mem = "";
    my $memory    = "";

    #my $html = "<!DOCTYPE html>\n<html>\n<head>" . $style . "</head><body>\n<table class=" . '"' . "center" . '"' . ">\n<tbody>\n<tr><td><h3>$item</h3></td></tr><tr>\n<td>" . "$table" . "</td></tr><tr><td>" . get_report() . "</td>\n</tr><tr><td>&nbsp;</td></tr><tr><td><b>LEGEND</b>:<tr><td>" . get_legend() . "</td></tr>\n</tbody>\n</table>\n</body></html>";
    if ( $item eq "CPU" ) {
      my $html = "<!DOCTYPE html>\n<html>\n<head>" . $style . "</head><body>\n<table class=" . '"' . "center" . '"' . ">\n<tbody>\n<tr><td><h3>$item</h3></td></tr><tr>\n<td>" . "$table" . "</td></tr><tr><td>&nbsp;</td></tr>\n";
      open( my $DATA, ">$webdir/heatmap-$lc_tech-$lc_type.html" ) or error_die("Cannot open file: $webdir/heatmap-$lc_tech-$lc_type.html : $!");
      print $DATA $html;
      close $DATA;

      my $html2 = "<!DOCTYPE html>\n<html>\n<head>" . $style . "</head><body><center>$table_values</center></body></html>";
      open( $DATA, ">$webdir/heatmap-$lc_tech-$lc_type-cpu-values.html" ) or error_die("Cannot open file: $webdir/heatmap-$lc_tech-$lc_type-cpu-values.html : $!");
      print $DATA $html2;
      close $DATA;
    }
    else {
      my $html = "<tr><td><h3>$item</h3></td></tr><tr>\n<td>" . "$table" . "</td></tr><tr><td>&nbsp;</td></tr><tr><td>" . get_report() . "</td>\n</tr><tr><td>&nbsp;</td></tr><tr><td><b>LEGEND</b>:<tr><td>" . get_legend() . "</td></tr>\n</tbody>\n</table>\n</body></html>\n";
      open( my $DATA, ">>$webdir/heatmap-$lc_tech-$lc_type.html" ) or error_die("Cannot open file: $webdir/heatmap-$lc_tech-$lc_type.html : $!");
      print $DATA $html;
      close $DATA;

      my $html2 = "<!DOCTYPE html>\n<html>\n<head>" . $style . "</head><body><center>$table_values</center></body></html>";
      open( $DATA, ">$webdir/heatmap-$lc_tech-$lc_type-mem-values.html" ) or error_die("Cannot open file: $webdir/heatmap-$lc_tech-$lc_type-mem-values.html : $!");
      print $DATA $html2;
      close $DATA;

    }

    #print $html . "\n";
  }
}

sub get_utilization_ovirt {
  my $file       = shift;
  my $type       = shift;
  my $item       = shift;
  my $technology = shift;
  my $item_rrd   = "cpu_usage_p";
  my $b2gib      = 1024**3;
  my $kib2gib    = 1024**2;
  if ( defined $technology && ( $technology eq "XEN" || $technology eq "NUTANIX" ) && $item eq "CPU" ) {
    if ( $type eq "SERVER" ) {
      $item_rrd = "cpu_avg";
    }
    else {
      $item_rrd = "cpu";
    }
  }
  if ( defined $technology && $technology eq "PROXMOX" && $item eq "CPU" ) {
    $item_rrd = "cpu";
  }
  if ( defined $technology && $technology eq "FUSIONCOMPUTE" && $item eq "CPU" ) {
    $item_rrd = "cpu_usage";
  }
  if ( defined $technology && $technology eq "ORACLEVM" && $item eq "CPU" ) {
    $item_rrd = "CPU_UTILIZATION";
  }
  if ( defined $technology && $technology eq "ORACLEVM" && $item eq "MEMORY" ) {
    $item_rrd = "MEMORY_UTILIZATION";
  }

  $file =~ s/:/\\:/g;
  my $rrd_out_name = "graph.png";
  my $answer;

  if ( defined $technology && ( $technology eq "XEN" || $technology eq "ORACLEVM" ) && $item eq "CPU" ) {
    eval {
      RRDp::cmd qq(graph "$rrd_out_name"
      "--start" "$start_time"
      "--end" "$end_time"
      "--step=60"
      "DEF:cpu_usage_p=$file:$item_rrd:AVERAGE"
      "CDEF:cpu_util=cpu_usage_p,100,*"
      "PRINT:cpu_util:AVERAGE:Utilization $type %2.2lf"
    );
      $answer = RRDp::read;
    };
  }
  if ( defined $technology && $technology eq "ORACLEVM" && $item eq "MEMORY" ) {
    eval {
      RRDp::cmd qq(graph "$rrd_out_name"
      "--start" "$start_time"
      "--end" "$end_time"
      "--step=60"
      "DEF:cpu_usage_p=$file:$item_rrd:AVERAGE"
      "CDEF:cpu_util=cpu_usage_p,100,*"
      "PRINT:cpu_util:AVERAGE:Utilization $type %2.2lf"
    );
      $answer = RRDp::read;
    };
  }

  if ( $item eq "CPU" && ( !defined $technology || $technology ne "XEN" || $technology ne "ORACLEVM" || $technology eq "FUSIONCOMPUTE" ) ) {
    eval {
      RRDp::cmd qq(graph "$rrd_out_name"
      "--start" "$start_time"
      "--end" "$end_time"
      "--step=60"
      "DEF:cpu_usage_p=$file:$item_rrd:AVERAGE"
      "PRINT:cpu_usage_p:AVERAGE:Utilization $type %2.2lf"
    );
      $answer = RRDp::read;
    };
  }
  if ( defined $technology && ( $technology eq "NUTANIX" || $technology eq "PROXMOX" ) && $item eq "CPU" ) {
    eval {
      RRDp::cmd qq(graph "$rrd_out_name"
      "--start" "$start_time"
      "--end" "$end_time"
      "--step=60"
      "DEF:cpu_usage_p=$file:$item_rrd:AVERAGE"
      "CDEF:cpu_util=cpu_usage_p,100,*"
      "PRINT:cpu_util:AVERAGE:Utilization $type %2.2lf"
    );
      $answer = RRDp::read;
    };
  }
  if ( $item eq "MEMORY" && ( !defined $technology || $technology ne "ORACLEVM" ) ) {
    eval {
      RRDp::cmd qq(graph "$rrd_out_name"
      "--start" "$start_time"
      "--end" "$end_time"
      "--step=60"
      "DEF:memory_used=$file:memory_used:AVERAGE"
      "DEF:memory_free=$file:memory_free:AVERAGE"
      "CDEF:total=memory_used,memory_free,+"
      "CDEF:util=memory_used,total,/,100,*"
      "PRINT:util:AVERAGE:Utilization $type %2.2lf"
    );
      $answer = RRDp::read;
    };
  }
  if ( $item eq "MEMORY-XEN" && $type eq "SERVER" ) {
    eval {
      RRDp::cmd qq(graph "$rrd_out_name"
      "--start" "$start_time"
      "--end" "$end_time"
      "--step=60"
      "DEF:memory_total=$file:memory_total:AVERAGE"
      "CDEF:mem_total=memory_total,$kib2gib,/"
      "DEF:memory_free=$file:memory_free:AVERAGE"
      "CDEF:free=memory_free,$kib2gib,/"
      "CDEF:used=mem_total,free,-"
      "CDEF:util=used,mem_total,/,100,*"
      "PRINT:util:AVERAGE:Utilization $type %2.2lf"
    );
      $answer = RRDp::read;
    };
  }
  if ( $item eq "MEMORY-XEN" && $type eq "VM" ) {
    eval {
      RRDp::cmd qq(graph "$rrd_out_name"
      "--start" "$start_time"
      "--end" "$end_time"
      "--step=60"
      "DEF:memory_total=$file:memory:AVERAGE"
      "CDEF:mem_total=memory_total,$b2gib,/"
      "DEF:memory_free=$file:memory_int_free:AVERAGE"
      "CDEF:free=memory_free,$kib2gib,/"
      "CDEF:used=mem_total,free,-"
      "CDEF:util=used,mem_total,/,100,*"
      "PRINT:util:AVERAGE:Utilization $type %2.2lf"
    );
      $answer = RRDp::read;
    };
  }
  if ( $item eq "MEMORY-NUTANIX" && $type eq "SERVER" ) {
    eval {
      RRDp::cmd qq(graph "$rrd_out_name"
      "--start" "$start_time"
      "--end" "$end_time"
      "--step=60"
      "DEF:memory_total=$file:memory_total:AVERAGE"
      "CDEF:mem_total=memory_total,$kib2gib,/"
      "DEF:memory_free=$file:memory_free:AVERAGE"
      "CDEF:free=memory_free,$kib2gib,/"
      "CDEF:used=mem_total,free,-"
      "CDEF:util=used,mem_total,/,100,*"
      "PRINT:util:AVERAGE:Utilization $type %2.2lf"
    );
      $answer = RRDp::read;
    };
  }
  if ( $item eq "MEMORY-NUTANIX" && $type eq "VM" ) {
    eval {
      RRDp::cmd qq(graph "$rrd_out_name"
      "--start" "$start_time"
      "--end" "$end_time"
      "--step=60"
      "DEF:memory_total=$file:memory:AVERAGE"
      "CDEF:mem_total=memory_total,$kib2gib,/"
      "DEF:memory_free=$file:memory_int_free:AVERAGE"
      "CDEF:free=memory_free,$kib2gib,/"
      "CDEF:used=mem_total,free,-"
      "CDEF:util=used,mem_total,/,100,*"
      "PRINT:util:AVERAGE:Utilization $type %2.2lf"
    );
      $answer = RRDp::read;
    };
  }
  if ( $item eq "MEMORY-PROXMOX" && $type eq "SERVER" ) {
    eval {
      RRDp::cmd qq(graph "$rrd_out_name"
      "--start" "$start_time"
      "--end" "$end_time"
      "--step=60"
      "DEF:memory_total=$file:memtotal:AVERAGE"
      "CDEF:mem_total=memory_total,$b2gib,/"
      "DEF:memory_used=$file:memused:AVERAGE"
      "CDEF:used=memory_used,$b2gib,/"
      "CDEF:util=used,mem_total,/,100,*"
      "PRINT:util:AVERAGE:Utilization $type %2.2lf"
    );
      $answer = RRDp::read;
    };
  }
  if ( $item eq "MEMORY-PROXMOX" && $type eq "VM" ) {
    eval {
      RRDp::cmd qq(graph "$rrd_out_name"
      "--start" "$start_time"
      "--end" "$end_time"
      "--step=60"
      "DEF:memory_total=$file:maxmem:AVERAGE"
      "CDEF:mem_total=memory_total,$b2gib,/"
      "DEF:memory_used=$file:mem:AVERAGE"
      "CDEF:used=memory_used,$b2gib,/"
      "CDEF:util=used,mem_total,/,100,*"
      "PRINT:util:AVERAGE:Utilization $type %2.2lf"
    );
      $answer = RRDp::read;
    };
  }
  if ( $item eq "MEMORY-FUSIONCOMPUTE" ) {
    eval {
      RRDp::cmd qq(graph "$rrd_out_name"
      "--start" "$start_time"
      "--end" "$end_time"
      "--step=60"
      "DEF:mem_usage=$file:mem_usage:AVERAGE"
      "PRINT:mem_usage:AVERAGE:Utilization $type %2.2lf"
    );
      $answer = RRDp::read;
    };
  }
  if ($@) {
    if ( $@ =~ "ERROR" ) {
      error("Rrrdtool error : $@");
      return;
    }
  }
  my $aaa = $$answer;

  ( undef, my $util ) = split( "\n", $aaa );
  $util =~ s/Utilization $type\s+//;
  return $util;

}

sub get_table_oraclevm {
  my $type  = shift;
  my $count = shift;
  my $item  = shift;
  use POSIX qw(ceil);

  #my $const = 2.6;
  my $count_row = 1;
  my $nasob     = 1;
  if ( $count == 0 ) { return "" }
  my $cell_size = ( $height * $width ) / $count;

  my $td_width     = ceil( sqrt($cell_size) );
  my $td_height    = $td_width;
  my $new_row      = 0;
  my $count_column = 1;

  if ( $td_width < 10 ) {
    $td_width  = 10;
    $td_height = 10;
  }
  if ( $td_width > 42 ) {
    $td_width  = 42;
    $td_height = 42;
  }

  $td_height = $td_height - 2;
  ################
  #my $i = 0;
  my $style = " .content_oraclevm { height:" . "$td_height" . "px" . "; width:" . "$td_height" . "px" . ";} h3 {text-align:center;}";
  my $table = "<table>\n<tbody>\n<tr>\n";

  my $table_values = "<table class =\" lparsearch tablesorter\" data-sortby=\"3\">";
  $table_values = $table_values . "<thead><tr><th class = \"sortable\" title=\"Cluster\" nowrap=\"\">Cluster</th>\n";
  if ( $type eq "VM" ) {
    $table_values = $table_values . "<th class = \"sortable\" title=\"VM\" nowrap=\"\">VM</th>\n";
  }
  else {
    $table_values = $table_values . "<th class = \"sortable\" title=\"Server\" nowrap=\"\">Server</th>\n";
  }
  $table_values = $table_values . "<th class = \"sortable\" title=\"Utilization %\" nowrap=\"\">Utilization %</th>\n";
  $table_values = $table_values . "<th class = \"sortable\" title=\"Color\" nowrap=\"\"><center>Color</center></th></tr></thead><tbody>\n";

  foreach my $machine ( sort keys %oraclevm ) {

    foreach my $cluster ( sort keys %{ $oraclevm{$machine}{CLUSTER} } ) {
      foreach my $server ( sort keys %{ $oraclevm{$machine}{CLUSTER}{$cluster}{$type} } ) {
        if ( defined $oraclevm{$machine}{CLUSTER}{$cluster}{$type}{$server}{$item} ) {
          if ( ( $new_row + $td_width ) > $width ) {
            $table   = $table . "</tr>\n<tr>\n";
            $new_row = 0;
          }
          my $url = $oraclevm{$machine}{CLUSTER}{$cluster}{$type}{$server}{URL};
          if ( !defined $url ) { $url = "#"; }
          my $name = $oraclevm{$machine}{CLUSTER}{$cluster}{$type}{$server}{NAME};
          if ( !defined $name ) { $name = $server; }
          my $percent_util;
          my $util = $oraclevm{$machine}{CLUSTER}{$cluster}{$type}{$server}{$item};
          if ( "$util" eq "-nan" || "$util" eq "nan" || $util =~ /nan/ || "$util" eq "NaNQ" || $util =~ /NAN/ || $util =~ /NaN/ || !isdigit($util) ) {
            $percent_util = "nan";
          }
          else {
            $percent_util = $oraclevm{$machine}{CLUSTER}{$cluster}{$type}{$server}{$item} . "%";
          }
          my $class = get_percent_to_color($util);
          my $color = $class_color{$class};
          $table = $table . "<td class=\"$class\">\n<a href=" . '"' . "$url" . '"' . "><div title =" . '"' . "$cluster : $name" . " : " . $percent_util . '"' . "class=" . '"' . "content_oraclevm" . '"' . "></div>\n</a>\n</td>\n";

          $percent_util =~ s/\%//g;
          $table_values = $table_values . "<tr><td>$cluster</td><td><a href=\"$url\">$name</a></td><td>$percent_util</td><td><div style=\"height:15px;width:15px;background-color:$color; margin: auto;\"></div></td></tr>\n";

          $new_row = $td_width + $new_row;
        }
        else {
          next;
        }
      }
    }
  }

  #print $table_power . "\n";
  $table_values = $table_values . "</tbody></table>";
  $table        = $table . "</tr>\n</tbody>\n</table><br>\n";

  #$print "$table_power\n";
  #print "$count_lpars\n";
  my $tb_and_style = "$table" . "@" . "$style" . "@" . $table_values;
  return "$tb_and_style";
}

sub get_table_xen {
  my $type  = shift;
  my $count = shift;
  my $item  = shift;
  use POSIX qw(ceil);

  #my $const = 2.6;
  my $count_row = 1;
  my $nasob     = 1;
  if ( $count == 0 ) { return "" }
  my $cell_size = ( $height * $width ) / $count;

  my $td_width     = ceil( sqrt($cell_size) );
  my $td_height    = $td_width;
  my $new_row      = 0;
  my $count_column = 1;

  if ( $td_width < 10 ) {
    $td_width  = 10;
    $td_height = 10;
  }
  if ( $td_width > 42 ) {
    $td_width  = 42;
    $td_height = 42;
  }

  $td_height = $td_height - 2;
  ################
  #my $i = 0;
  my $style = " .content_xen { height:" . "$td_height" . "px" . "; width:" . "$td_height" . "px" . ";} h3 {text-align:center;}";
  my $table = "<table>\n<tbody>\n<tr>\n";

  my $table_values = "<table class =\" lparsearch tablesorter\" data-sortby=\"3\">";
  $table_values = $table_values . "<thead><tr><th class = \"sortable\" title=\"Pool\" nowrap=\"\">Pool</th>\n";
  if ( $type eq "VM" ) {
    $table_values = $table_values . "<th class = \"sortable\" title=\"VM\" nowrap=\"\">VM</th>\n";
  }
  else {
    $table_values = $table_values . "<th class = \"sortable\" title=\"Server\" nowrap=\"\">Server</th>\n";
  }
  $table_values = $table_values . "<th class = \"sortable\" title=\"Utilization %\" nowrap=\"\">Utilization %</th>\n";
  $table_values = $table_values . "<th class = \"sortable\" title=\"Color\" nowrap=\"\"><center>Color</center></th></tr></thead><tbody>\n";

  foreach my $cluster ( sort keys %xen ) {
    foreach my $server ( sort keys %{ $xen{$cluster}{$type} } ) {
      if ( defined $xen{$cluster}{$type}{$server}{$item} ) {
        if ( ( $new_row + $td_width ) > $width ) {
          $table   = $table . "</tr>\n<tr>\n";
          $new_row = 0;
        }
        my $url = $xen{$cluster}{$type}{$server}{URL};
        if ( !defined $url ) { $url = "#"; }
        my $percent_util;
        my $util = $xen{$cluster}{$type}{$server}{$item};
        if ( "$util" eq "-nan" || "$util" eq "nan" || $util =~ /nan/ || "$util" eq "NaNQ" || $util =~ /NAN/ || $util =~ /NaN/ || !isdigit($util) ) {
          $percent_util = "nan";
        }
        else {
          $percent_util = $xen{$cluster}{$type}{$server}{$item} . "%";
        }
        my $class = get_percent_to_color($util);
        my $color = $class_color{$class};
        $table = $table . "<td class=\"$class\">\n<a href=" . '"' . "$url" . '"' . "><div title =" . '"' . "$cluster : $server" . " : " . $percent_util . '"' . "class=" . '"' . "content_xen" . '"' . "></div>\n</a>\n</td>\n";

        $percent_util =~ s/\%//g;
        $table_values = $table_values . "<tr><td>$cluster</td><td><a href=\"$url\">$server</a></td><td>$percent_util</td><td><div style=\"height:15px;width:15px;background-color:$color; margin: auto;\"></div></td></tr>\n";

        $new_row = $td_width + $new_row;
      }
      else {
        next;
      }
    }
  }

  #print $table_power . "\n";
  $table_values = $table_values . "</tbody></table>";
  $table        = $table . "</tr>\n</tbody>\n</table><br>\n";

  #$print "$table_power\n";
  #print "$count_lpars\n";
  my $tb_and_style = "$table" . "@" . "$style" . "@" . $table_values;
  return "$tb_and_style";
}

sub get_table_nutanix {
  my $type  = shift;
  my $count = shift;
  my $item  = shift;
  use POSIX qw(ceil);

  #my $const = 2.6;
  my $count_row = 1;
  my $nasob     = 1;
  if ( $count == 0 ) { return "" }
  my $cell_size = ( $height * $width ) / $count;

  my $td_width     = ceil( sqrt($cell_size) );
  my $td_height    = $td_width;
  my $new_row      = 0;
  my $count_column = 1;

  if ( $td_width < 10 ) {
    $td_width  = 10;
    $td_height = 10;
  }
  if ( $td_width > 42 ) {
    $td_width  = 42;
    $td_height = 42;
  }
  $td_height = $td_height - 2;
  ################
  #my $i = 0;
  my $style = " .content_nutanix { height:" . "$td_height" . "px" . "; width:" . "$td_height" . "px" . ";} h3 {text-align:center;}";
  my $table = "<table>\n<tbody>\n<tr>\n";

  my $table_values = "<table class =\" lparsearch tablesorter\" data-sortby=\"3\">";
  $table_values = $table_values . "<thead><tr><th class = \"sortable\" title=\"Pool\" nowrap=\"\">Pool</th>\n";
  if ( $type eq "VM" ) {
    $table_values = $table_values . "<th class = \"sortable\" title=\"VM\" nowrap=\"\">VM</th>\n";
  }
  else {
    $table_values = $table_values . "<th class = \"sortable\" title=\"Server\" nowrap=\"\">Server</th>\n";
  }
  $table_values = $table_values . "<th class = \"sortable\" title=\"Utilization %\" nowrap=\"\">Utilization %</th>\n";
  $table_values = $table_values . "<th class = \"sortable\" title=\"Color\" nowrap=\"\"><center>Color</center></th></tr></thead><tbody>\n";

  foreach my $cluster ( sort keys %nutanix ) {
    foreach my $server ( sort keys %{ $nutanix{$cluster}{$type} } ) {
      if ( defined $nutanix{$cluster}{$type}{$server}{$item} ) {
        if ( ( $new_row + $td_width ) > $width ) {
          $table   = $table . "</tr>\n<tr>\n";
          $new_row = 0;
        }
        my $url = $nutanix{$cluster}{$type}{$server}{URL};
        if ( !defined $url ) { $url = "#"; }
        my $percent_util;
        my $util = $nutanix{$cluster}{$type}{$server}{$item};
        if ( "$util" eq "-nan" || "$util" eq "nan" || $util =~ /nan/ || "$util" eq "NaNQ" || $util =~ /NAN/ || $util =~ /NaN/ || !isdigit($util) ) {
          $percent_util = "nan";
        }
        else {
          $percent_util = $nutanix{$cluster}{$type}{$server}{$item} . "%";
        }
        my $class = get_percent_to_color($util);
        my $color = $class_color{$class};
        $table = $table . "<td class=\"$class\">\n<a href=" . '"' . "$url" . '"' . "><div title =" . '"' . "$cluster : $server" . " : " . $percent_util . '"' . "class=" . '"' . "content_nutanix" . '"' . "></div>\n</a>\n</td>\n";

        $percent_util =~ s/\%//g;
        $table_values = $table_values . "<tr><td>$cluster</td><td><a href=\"$url\">$server</a></td><td>$percent_util</td><td><div style=\"height:15px;width:15px;background-color:$color; margin: auto;\"></div></td></tr>\n";

        $new_row = $td_width + $new_row;
      }
      else {
        next;
      }
    }
  }

  #print $table_power . "\n";
  $table_values = $table_values . "</tbody></table>";
  $table        = $table . "</tr>\n</tbody>\n</table><br>\n";

  #$print "$table_power\n";
  #print "$count_lpars\n";
  my $tb_and_style = "$table" . "@" . "$style" . "@" . $table_values;
  return "$tb_and_style";
}

sub get_table_proxmox {
  my $type  = shift;
  my $count = shift;
  my $item  = shift;
  use POSIX qw(ceil);

  #my $const = 2.6;
  my $count_row = 1;
  my $nasob     = 1;
  if ( $count == 0 ) { return "" }
  my $cell_size = ( $height * $width ) / $count;

  my $td_width     = ceil( sqrt($cell_size) );
  my $td_height    = $td_width;
  my $new_row      = 0;
  my $count_column = 1;

  if ( $td_width < 10 ) {
    $td_width  = 10;
    $td_height = 10;
  }
  if ( $td_width > 42 ) {
    $td_width  = 42;
    $td_height = 42;
  }
  $td_height = $td_height - 2;
  ################
  #my $i = 0;
  my $style = " .content_proxmox { height:" . "$td_height" . "px" . "; width:" . "$td_height" . "px" . ";} h3 {text-align:center;}";
  my $table = "<table>\n<tbody>\n<tr>\n";

  my $table_values = "<table class =\" lparsearch tablesorter\" data-sortby=\"3\">";
  $table_values = $table_values . "<thead><tr><th class = \"sortable\" title=\"Pool\" nowrap=\"\">Pool</th>\n";
  if ( $type eq "VM" ) {
    $table_values = $table_values . "<th class = \"sortable\" title=\"VM\" nowrap=\"\">VM</th>\n";
  }
  else {
    $table_values = $table_values . "<th class = \"sortable\" title=\"Server\" nowrap=\"\">Server</th>\n";
  }
  $table_values = $table_values . "<th class = \"sortable\" title=\"Utilization %\" nowrap=\"\">Utilization %</th>\n";
  $table_values = $table_values . "<th class = \"sortable\" title=\"Color\" nowrap=\"\"><center>Color</center></th></tr></thead><tbody>\n";

  foreach my $cluster ( sort keys %proxmox ) {
    foreach my $server ( sort keys %{ $proxmox{$cluster}{$type} } ) {
      if ( defined $proxmox{$cluster}{$type}{$server}{$item} ) {
        if ( ( $new_row + $td_width ) > $width ) {
          $table   = $table . "</tr>\n<tr>\n";
          $new_row = 0;
        }
        my $url = $proxmox{$cluster}{$type}{$server}{URL};
        if ( !defined $url ) { $url = "#"; }
        my $percent_util;
        my $util = $proxmox{$cluster}{$type}{$server}{$item};
        if ( "$util" eq "-nan" || "$util" eq "nan" || $util =~ /nan/ || "$util" eq "NaNQ" || $util =~ /NAN/ || $util =~ /NaN/ || !isdigit($util) ) {
          $percent_util = "nan";
        }
        else {
          $percent_util = $proxmox{$cluster}{$type}{$server}{$item} . "%";
        }
        my $class = get_percent_to_color($util);
        my $color = $class_color{$class};
        $table = $table . "<td class=\"$class\">\n<a href=" . '"' . "$url" . '"' . "><div title =" . '"' . "$cluster : $server" . " : " . $percent_util . '"' . "class=" . '"' . "content_proxmox" . '"' . "></div>\n</a>\n</td>\n";

        $percent_util =~ s/\%//g;
        $table_values = $table_values . "<tr><td>$cluster</td><td><a href=\"$url\">$server</a></td><td>$percent_util</td><td><div style=\"height:15px;width:15px;background-color:$color; margin: auto;\"></div></td></tr>\n";

        $new_row = $td_width + $new_row;
      }
      else {
        next;
      }
    }
  }

  #print $table_power . "\n";
  $table_values = $table_values . "</tbody></table>";
  $table        = $table . "</tr>\n</tbody>\n</table><br>\n";

  #$print "$table_power\n";
  #print "$count_lpars\n";
  my $tb_and_style = "$table" . "@" . "$style" . "@" . $table_values;
  return "$tb_and_style";
}

sub get_table_fusioncompute {
  my $type  = shift;
  my $count = shift;
  my $item  = shift;
  use POSIX qw(ceil);

  #my $const = 2.6;
  my $count_row = 1;
  my $nasob     = 1;
  if ( $count == 0 ) { return "" }
  my $cell_size = ( $height * $width ) / $count;

  my $td_width     = ceil( sqrt($cell_size) );
  my $td_height    = $td_width;
  my $new_row      = 0;
  my $count_column = 1;

  if ( $td_width < 10 ) {
    $td_width  = 10;
    $td_height = 10;
  }
  if ( $td_width > 42 ) {
    $td_width  = 42;
    $td_height = 42;
  }
  $td_height = $td_height - 2;
  ################
  #my $i = 0;
  my $style = " .content_fusioncompute { height:" . "$td_height" . "px" . "; width:" . "$td_height" . "px" . ";} h3 {text-align:center;}";
  my $table = "<table>\n<tbody>\n<tr>\n";

  my $table_values = "<table class =\" lparsearch tablesorter\" data-sortby=\"3\">";
  $table_values = $table_values . "<thead><tr><th class = \"sortable\" title=\"Pool\" nowrap=\"\">Pool</th>\n";
  if ( $type eq "VM" ) {
    $table_values = $table_values . "<th class = \"sortable\" title=\"VM\" nowrap=\"\">VM</th>\n";
  }
  else {
    $table_values = $table_values . "<th class = \"sortable\" title=\"Server\" nowrap=\"\">Server</th>\n";
  }
  $table_values = $table_values . "<th class = \"sortable\" title=\"Utilization %\" nowrap=\"\">Utilization %</th>\n";
  $table_values = $table_values . "<th class = \"sortable\" title=\"Color\" nowrap=\"\"><center>Color</center></th></tr></thead><tbody>\n";

  foreach my $cluster ( sort keys %fusioncompute ) {
    foreach my $server ( sort keys %{ $fusioncompute{$cluster}{$type} } ) {
      if ( defined $fusioncompute{$cluster}{$type}{$server}{$item} ) {
        if ( ( $new_row + $td_width ) > $width ) {
          $table   = $table . "</tr>\n<tr>\n";
          $new_row = 0;
        }
        my $url = $fusioncompute{$cluster}{$type}{$server}{URL};
        if ( !defined $url ) { $url = "#"; }
        my $percent_util;
        my $util = $fusioncompute{$cluster}{$type}{$server}{$item};
        if ( "$util" eq "-nan" || "$util" eq "nan" || $util =~ /nan/ || "$util" eq "NaNQ" || $util =~ /NAN/ || $util =~ /NaN/ || !isdigit($util) ) {
          $percent_util = "nan";
        }
        else {
          $percent_util = $fusioncompute{$cluster}{$type}{$server}{$item} . "%";
        }
        my $class = get_percent_to_color($util);
        my $color = $class_color{$class};
        $table = $table . "<td class=\"$class\">\n<a href=" . '"' . "$url" . '"' . "><div title =" . '"' . "$cluster : $server" . " : " . $percent_util . '"' . "class=" . '"' . "content_fusioncompute" . '"' . "></div>\n</a>\n</td>\n";

        $percent_util =~ s/\%//g;
        $table_values = $table_values . "<tr><td>$cluster</td><td><a href=\"$url\">$server</a></td><td>$percent_util</td><td><div style=\"height:15px;width:15px;background-color:$color; margin: auto;\"></div></td></tr>\n";

        $new_row = $td_width + $new_row;
      }
      else {
        next;
      }
    }
  }

  #print $table_power . "\n";
  $table_values = $table_values . "</tbody></table>";
  $table        = $table . "</tr>\n</tbody>\n</table><br>\n";

  #$print "$table_power\n";
  #print "$count_lpars\n";
  my $tb_and_style = "$table" . "@" . "$style" . "@" . $table_values;
  return "$tb_and_style";
}

sub get_table_ovirt {
  my $type  = shift;
  my $count = shift;
  my $item  = shift;
  use POSIX qw(ceil);

  #my $const = 2.6;
  my $count_row = 1;
  my $nasob     = 1;
  if ( $count == 0 ) { return "" }
  my $cell_size = ( $height * $width ) / $count;

  my $td_width     = ceil( sqrt($cell_size) );
  my $td_height    = $td_width;
  my $new_row      = 0;
  my $count_column = 1;

  if ( $td_width < 10 ) {
    $td_width  = 10;
    $td_height = 10;
  }
  if ( $td_width > 42 ) {
    $td_width  = 42;
    $td_height = 42;
  }

  $td_height = $td_height - 2;
  ################
  #my $i = 0;
  my $style = " .content_ovirt { height:" . "$td_height" . "px" . "; width:" . "$td_height" . "px" . ";} h3 {text-align:center;}";
  my $table = "<table>\n<tbody>\n<tr>\n";

  my $table_values = "<table class =\" lparsearch tablesorter\" data-sortby=\"4\">";
  $table_values = $table_values . "<thead><tr><th class = \"sortable\" title=\"Datacenter\" nowrap=\"\">Datacenter</th>\n";
  $table_values = $table_values . "<th class = \"sortable\" title=\"Cluster\" nowrap=\"\">Cluster</th>\n";
  if ( $type eq "VM" ) {
    $table_values = $table_values . "<th class = \"sortable\" title=\"VM\" nowrap=\"\">VM</th>\n";
  }
  else {
    $table_values = $table_values . "<th class = \"sortable\" title=\"Server\" nowrap=\"\">Server</th>\n";
  }
  $table_values = $table_values . "<th class = \"sortable\" title=\"Utilization %\" nowrap=\"\">Utilization %</th>\n";
  $table_values = $table_values . "<th class = \"sortable\" title=\"Color\" nowrap=\"\"><center>Color</center></th></tr></thead><tbody>\n";

  foreach my $datacenter ( sort keys %{ $ovirt{DATACENTER} } ) {
    foreach my $cluster ( sort keys %{ $ovirt{DATACENTER}{$datacenter}{CLUSTER} } ) {
      foreach my $server ( sort keys %{ $ovirt{DATACENTER}{$datacenter}{CLUSTER}{$cluster}{$type} } ) {
        if ( defined $ovirt{DATACENTER}{$datacenter}{CLUSTER}{$cluster}{$type}{$server}{$item} ) {
          if ( ( $new_row + $td_width ) > $width ) {
            $table   = $table . "</tr>\n<tr>\n";
            $new_row = 0;
          }
          my $url = $ovirt{DATACENTER}{$datacenter}{CLUSTER}{$cluster}{$type}{$server}{URL};
          if ( !defined $url ) { $url = "#"; }
          my $percent_util;
          my $util = $ovirt{DATACENTER}{$datacenter}{CLUSTER}{$cluster}{$type}{$server}{$item};
          if ( "$util" eq "-nan" || "$util" eq "nan" || $util =~ /nan/ || "$util" eq "NaNQ" || $util =~ /NAN/ || $util =~ /NaN/ || !isdigit($util) ) {
            $percent_util = "nan";
          }
          else {
            $percent_util = $ovirt{DATACENTER}{$datacenter}{CLUSTER}{$cluster}{$type}{$server}{$item} . "%";
          }
          my $class = get_percent_to_color($util);
          my $color = $class_color{$class};
          $table = $table . "<td class=\"$class\">\n<a href=" . '"' . "$url" . '"' . "><div title =" . '"' . "$datacenter : $cluster : $server" . " : " . $percent_util . '"' . "class=" . '"' . "content_ovirt" . '"' . "></div>\n</a>\n</td>\n";

          $percent_util =~ s/\%//g;

          $table_values = $table_values . "<tr><td>$datacenter</td><td>$cluster</td><td><a href=\"$url\">$server</a></td><td>$percent_util</td><td><div style=\"height:15px;width:15px;background-color:$color; margin: auto;\"></div></td></tr>\n";

          $new_row = $td_width + $new_row;
        }
        else {
          next;
        }
      }
    }
  }

  #print $table_power . "\n";
  $table        = $table . "</tr>\n</tbody>\n</table><br>\n";
  $table_values = $table_values . "</tbody></table>";

  #$print "$table_power\n";
  #print "$count_lpars\n";
  my $tb_and_style = "$table" . "@" . "$style" . "@" . "$table_values";
  return "$tb_and_style";
}

sub set_wrap_html_ovirt {
  my $tech = shift;
  my $html = "<div id=" . '"' . "tabs" . '"' . ">\n<ul>\n<li><a href=" . '"' . "heatmap-$tech-vm.html" . '"' . ">VM</a></li>\n<li><a href=" . '"' . "heatmap-$tech-server.html" . '"' . ">Server</a></li>\n<li><a href=" . '"' . "heatmap-$tech-vm-cpu-values.html" . '"' . ">VM CPU Table</a></li>\n<li><a href=" . '"' . "heatmap-$tech-vm-mem-values.html" . '"' . ">VM MEM Table</a></li>\n<li><a href=" . '"' . "heatmap-$tech-server-cpu-values.html" . '"' . ">Server CPU Table</a></li>\n<li><a href=" . '"' . "heatmap-$tech-server-mem-values.html" . '"' . ">Server MEM Table</a></li></ul>\n</div>";
  if ( $tech eq "oraclevm" ) {
    $html = "<div id=" . '"' . "tabs" . '"' . ">\n<ul>\n<li><a href=" . '"' . "heatmap-$tech-vm.html" . '"' . ">VM</a></li>\n<li><a href=" . '"' . "heatmap-$tech-server.html" . '"' . ">Server</a></li>\n<li><a href=" . '"' . "heatmap-$tech-vm-cpu-values.html" . '"' . ">VM CPU Table</a></li>\n<li><a href=" . '"' . "heatmap-$tech-server-cpu-values.html" . '"' . ">Server CPU Table</a></li>\n<li><a href=" . '"' . "heatmap-$tech-server-mem-values.html" . '"' . ">Server MEM Table</a></li>\n</ul>\n</div>";
  }

  if ( -e "$webdir/heatmap-$tech.html" ) {
  }
  else {
    open( my $DATA, ">$webdir/heatmap-$tech.html" ) or error_die("Cannot open file: $webdir/heatmap-$tech.html : $!");
    print $DATA $html;
    close $DATA;
  }

}

sub get_json {
  my $metadata_file = shift;
  my %dictionary;

  if ( -f $metadata_file ) {
    my ( $code, $ref ) = Xorux_lib::read_json($metadata_file);
    %dictionary = $code ? %{$ref} : ();
  }
  else {
    %dictionary = ();
  }
  return \%dictionary;
}

sub get_hmc_list {
  my @hmc_list = ();
  my $hmclist  = $ENV{HMC_LIST} ||= "";
  if ( -e $hmclist && -f _ && -r _ ) {
    $hmclist = `cat $hmclist`;
  }
  elsif ( -e "$basedir/etc/$hmclist" && -f _ && -r _ ) {
    $hmclist = `cat $basedir/etc/$hmclist`;
  }
  if ( $hmclist && $hmclist ne "hmc1 sdmc1 ivm1" ) {
    foreach my $hmc ( split " ", $hmclist ) {
      push( @hmc_list, $hmc );
    }
  }
  return @hmc_list;
}

sub get_value_from_rrd {

  my $type         = shift;
  my $start_time   = shift;
  my $end_time     = shift;
  my $rrd_file     = shift;
  my $rrd_out_name = shift;
  my $hmc_act      = shift;
  my $hmc_future   = shift;
  my $last_value   = shift;

  my $answer;

  $rrd_file =~ s/\/$hmc_act\//\/$hmc_future\//;
  if ( !-f $rrd_file ) {
    if ($DEBUG) { print "DEBUG: File $rrd_file does not exist\n"; }
    return $last_value;
  }
  $rrd_file =~ s/:/\\:/g;

  if ( $type eq "LPAR" ) {

    eval {
      RRDp::cmd qq(graph "$rrd_out_name"
      "--start" "$start_time"
      "--end" "$end_time"
      "--step=60"
      "DEF:cur=$rrd_file:curr_proc_units:AVERAGE"
      "DEF:ent=$rrd_file:entitled_cycles:AVERAGE"
      "DEF:cap=$rrd_file:capped_cycles:AVERAGE"
      "DEF:uncap=$rrd_file:uncapped_cycles:AVERAGE"
      "CDEF:tot=cap,uncap,+"
      "CDEF:util=tot,ent,/,$cpu_max_filter,GT,UNKN,tot,ent,/,IF"
      "CDEF:utiltot=util,cur,*"
      "PRINT:utiltot:AVERAGE:Utilization in CPU cores %2.2lf"
      );
      $answer = RRDp::read;
    };
    if ($@) {
      if ( $@ =~ "ERROR" ) {
        error("Rrrdtool error : $@");
        return $last_value;
      }
    }
    my $aaa = $$answer;

    #if ( $aaa =~ /NaNQ/ ) { next; }
    ( undef, my $utilization_in_cores ) = split( "\n", $aaa );
    $utilization_in_cores =~ s/Utilization in CPU cores\s+//;
    return $utilization_in_cores;
  }
}

