# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation.

# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.

# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 675 Mass Ave, Cambridge, MA 02139, USA.

use strict;
use warnings;
use Date::Parse;
use File::Compare;
use File::Copy;
use File::Basename;
use Data::Dumper;
use XoruxEdition;

use XenServerDataWrapperOOP;
use XenServerGraph;

use NutanixDataWrapper;
use NutanixGraph;

use ProxmoxDataWrapper;
use ProxmoxGraph;

use FusionComputeDataWrapper;
use FusionComputeGraph;

use OpenshiftDataWrapperOOP;
use OpenshiftDataWrapper;
use OpenshiftGraph;

use KubernetesDataWrapperOOP;
use KubernetesDataWrapper;
use KubernetesGraph;

use OVirtDataWrapper;
use OVirtGraph;

use OracleVmDataWrapper;
use OracleVmGraph;

# set unbuffered stdout
$| = 1;

#
### for debug purpose just run
# . etc/lpar2rrd.cfg ; $PERL bin/custom.pl
#

# get cmd line params
my $version = "$ENV{version}";
my $hea     = $ENV{HEA};

#use from host config 23.11.18 HD
#my $hmc_user = $ENV{HMC_USER};
my $webdir  = $ENV{WEBDIR};
my $bindir  = $ENV{BINDIR};
my $basedir = $ENV{INPUTDIR};
my $tmpdir  = "$basedir/tmp";
if ( defined $ENV{TMPDIR} ) {
  $tmpdir = $ENV{TMPDIR};
}
my $rrdtool                 = $ENV{RRDTOOL};
my $DEBUG                   = $ENV{DEBUG};
my $pic_col                 = $ENV{PICTURE_COLOR};
my $STEP                    = $ENV{SAMPLE_RATE};
my $HWINFO                  = $ENV{HWINFO};
my $managed_systems_exclude = $ENV{MANAGED_SYSTEMS_EXCLUDE};
my $SYS_CHANGE              = $ENV{SYS_CHANGE};
my $STEP_HEA                = $ENV{STEP_HEA};
my $upgrade                 = $ENV{UPGRADE};
my $new_change              = "$tmpdir/$version-run";
my $filter_max_lansan       = 1000000000000;                   # 1TB/sec, filter values above as this is most probably caused by a counter reset (lpar restart)
if ( defined $ENV{FILTER_MAX_LANSAN} ) { $filter_max_lansan = $ENV{FILTER_MAX_LANSAN} }
my $filter_max_iops = 1000000;                                 # 100k IOPS filter values above as this is most probably caused by a counter reset (lpar restart)
if ( defined $ENV{FILTER_MAX_IOPS} ) { $filter_max_iops = $ENV{FILTER_MAX_IOPS} }
my $filter_max_paging = 100000000;                             # 100MB/sec, filter values above as this is most probably caused by a counter reset (lpar restart)
if ( defined $ENV{FILTER_MAX_PAGING} ) { $filter_max_paging = $ENV{FILTER_MAX_PAGING} }
my $cpu_max_filter = 100;                                      # my $cpu_max_filter = 100;  # max 10k peak in % is allowed (in fact it cannot by higher than 1k now when 1 logical CPU == 0.1 entitlement)

my $YEAR_REFRESH  = 86400;                                     # 24 hour, minimum time in sec when yearly graphs are updated (refreshed)
my $MONTH_REFRESH = 64800;                                     # 16 hour, minimum time in sec when monthly graphs are updated (refreshed)
my $WEEK_REFRESH  = 43200;                                     # 12 hour, minimum time in sec when weekly  graphs are updated (refreshed)

if ( defined $ENV{CPU_MAX_FILTER} ) {
  $cpu_max_filter = $ENV{CPU_MAX_FILTER};
}

my $wrkdir = "$basedir/data";

# write PID file to do not allow run it more times concurrently
open( FF, ">$basedir/tmp/custom.pid" ) || error( "can't open $basedir/tmp/custom.pid: $! :" . __FILE__ . ":" . __LINE__ );
print FF "$$\n";
close(FF);

# test of rrdtool version
# used to shorten legends (error RRDTOOL legend too long) in version < 1.5
my $ans_rrdtool = `$rrdtool`;
my $test_legend = 0;
( undef, my $rrdtool_version ) = split( " ", $ans_rrdtool );
$rrdtool_version =~ s/\.\d+$//;    # not miner version (1.4).8
if ( $rrdtool_version < 1.5 ) {

  # print "$rrdtool_version < 1.5\n";
  $test_legend = 1;
}
my $max_alias_length = 80;

# Global definitions
my $type_sam        = "";
my $step            = "";
my $PARALLELIZATION = 5;
my @lpar_trans      = "";                  # lpar translation names/ids for IVM systems
my $width           = 400;
my $width_trend     = $width * 2 + 128;    # 93 pixels for 1 X axiss legend and Tobi promo + 50 table space

my $delimiter = "XORUX";                   # this is for rrdtool print lines for clickable legend

my @menu;                                  # is used by hyperv

# disable Tobi's promo
#my $disable_rrdtool_tag = "COMMENT: ";
#my $disable_rrdtool_tag_agg = "COMMENT:\" \"";
my $disable_rrdtool_tag     = "--interlaced";    # just nope string, it is deprecated anyway
my $disable_rrdtool_tag_agg = "--interlaced";    # just nope string, it is deprecated anyway
my $rrd_ver                 = $RRDp::VERSION;
if ( isdigit($rrd_ver) && $rrd_ver > 1.35 ) {
  $disable_rrdtool_tag     = "--disable-rrdtool-tag";
  $disable_rrdtool_tag_agg = "--disable-rrdtool-tag";
}

# keep here green - yellow - red - blue ...
my @color     = ( "#FF0000", "#0000FF", "#8fcc66", "#00FFFF", "#FFA500", "#00FF00", "#808080", "#FF00FF", "#800080", "#FDD017", "#0000A0", "#3BB9FF", "#008000", "#800000", "#C0C0C0", "#ADD8E6", "#F778A1", "#800517", "#736F6E", "#F52887", "#C11B17", "#5CB3FF", "#A52A2A", "#FF8040", "#2B60DE", "#736AFF", "#1589FF", "#98AFC7", "#8D38C9", "#307D7E", "#F6358A", "#151B54", "#6D7B8D", "#33cc33", "#FF0080", "#F88017", "#2554C7", "#00a900", "#D4A017", "#306EFF", "#151B8D", "#9E7BFF", "#EAC117", "#99cc00", "#15317E", "#6C2DC7", "#FBB917", "#86b300", "#15317E", "#254117", "#FAAFBE", "#357EC7", "#4AA02C", "#38ACEC" );
my $color_max = 53;                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                     # 0 - 53 is 54 colors

my @color_lpar = "";
my $color_indx = 0;

my $lpar_v = premium();
print "LPAR2RRD custom $lpar_v version $version\n" if $DEBUG;

my $act_time_txt = localtime();
my $act_time     = time();
my $step_new     = 60;                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                  # -PH solve it somehow

if ( !-d "$webdir" ) {
  error( "Pls set correct path to Web server pages, it does not exist here: $webdir" . __FILE__ . ":" . __LINE__ ) && return 0;
}

# defining global variables
my $pool_suffix             = "__pool__";
my @cfg_list                = "";
my @groups                  = "";                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                       # uniq list of group
my @groups_type             = "";                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                       # LPAR/POOL
my @groups_server           = "";
my @groups_lpar             = "";
my @groups_pool             = "";
my @groups_name             = "";
my @lpar_all_list           = "";                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                       # list of all lpars under data/*
my @lpar_all_list_org       = "";                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                       # list of all lpars under data/*, complete path include suffix
my @pool_all_list           = "";                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                       # list of all pools under data/*
my @pool_all_list_org       = "";                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                       # list of all pools under data/*
my @vims_all_list           = "";                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                       # list of all VMs under data/*
my @vims_all_list_org       = "";                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                       # list of all VMs under data/*, complete path include suffix
my @server_list_all         = "";                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                       # list of all server
my @server_list_solaris_all = "";                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                       # list of Solaris servers
my @solaris_zone_list       = "";                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                       # list of all zone name
my @solaris_zone_list_org   = "";                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                       # list of all zone name with mmm
my @solaris_ldom_list       = "";                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                       # list of ldom(total) name
my @solaris_ldom_list_org   = "";                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                       # list of all ldom(total) name with mmm
my @lpars_graph             = "";
my @lpars_graph_name        = "";
my @lpars_graph_server      = "";
my @lpars_graph_type        = "";                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                       # LPAR/POOL
my $lpar_graph_indx         = 0;
my $search_all_lpars        = 0;
my $search_all_solaris      = 0;
my $all_vmware_VMs          = "vmware_VMs";
my $all_vm_uuid_names       = "vm_uuid_name.txt";
my $server                  = "";
my $host                    = "";
my $type_edt_filep          = "$basedir/html/.p";
my $type_edt_filev          = "$basedir/html/.v";
my $type_edt_fileo          = "$basedir/html/.o";
my $type_edt_filex          = "$basedir/html/.x";
my $type_edt_fileh          = "$basedir/html/.h";
my $type_edt_files          = "$basedir/html/.s";
my $type_edt_filel          = "$basedir/html/.l";

#my $type_edt_filey     = "$basedir/html/.y";

my $cfg_update_time = cfg_update();

my $ret = cfg_load($basedir);
if ( $ret == 0 ) {

  # no groups are configured, exiting
  print "No custom groups configured\n";
  exit(0);
}

# start RRD via a pipe
use RRDp;
RRDp::start "$rrdtool";

# run for Power and VMware custom groups
find_rrd_files();

# run for XenServer custom groups
process_xenserver_custom_groups();

# run for Nutanix custom groups
process_nutanix_custom_groups();

# run for Proxmox custom groups
process_proxmox_custom_groups();

# run for FusionCompute custom groups
process_fusioncompute_custom_groups();

# run for OpenShift custom groups
process_openshift_custom_groups();

# run for Kubernetes custom groups
process_kubernetes_custom_groups();

# run for oVirt custom groups
process_ovirt_custom_groups();

# run for Solaris zone
process_solaris_zone_custom_groups();

# run for OracleVM custom groups
process_oraclevm_custom_groups();

# run for HYPERV custom groups
process_hyperv_custom_groups();

# run for HYPERV custom groups
process_linux_custom_groups();

# run for ESXi custom groups
process_esxi_custom_groups();

#process for OracleDB is in detail graph

# close RRD pipe
RRDp::end;

exit(0);

sub cfg_update {
  my $cfg = "$basedir/etc/custom_groups.cfg";
  if ( -f "$basedir/etc/web_config/custom_groups.cfg" ) {
    $cfg = "$basedir/etc/web_config/custom_groups.cfg";
  }

  if ( !-f $cfg ) {

    # cfg does not exist
    print "Custom group not configured yet\n";
    exit(0);
  }

  my $png_time = ( stat("$cfg") )[9];

  return $png_time;
}

sub cfg_load {
  my $basedir = shift;
  my $cfg     = "$basedir/etc/custom_groups.cfg";
  if ( -f "$basedir/etc/web_config/custom_groups.cfg" ) {
    $cfg = "$basedir/etc/web_config/custom_groups.cfg";
  }
  my $cfg_indx         = 0;
  my $groups_indx      = 0;
  my $groups_name_indx = 0;

  if ( !-f $cfg ) {

    # cfg does not exist
    error( "custom : custom cfg files does not exist: $cfg " . __FILE__ . ":" . __LINE__ );
    exit 1;
  }

  my $group_prev = "";

  open( FHR, "< $cfg" );

  foreach my $line (<FHR>) {
    chomp($line);
    $line =~ s/\\:/===========doublecoma=========/g;    # workround for lpars/pool/groups with double coma inside the name
    $line =~ s/ *$//g;                                  # delete spaces at the end
    if ( $line =~ m/^$/ || $line !~ m/^(POOL|LPAR|VM|XENVM|OVIRTVM|NUTANIXVM|PROXMOXVM|FUSIONCOMPUTEVM|OPENSHIFTNODE|OPENSHIFTPROJECT|KUBERNETESNODE|KUBERNETESNAMESPACE|SOLARISZONE|SOLARISLDOM|HYPERVM|LINUX|ESXI|ORVM)/ || $line =~ m/^#/ || $line !~ m/:/ || $line =~ m/:$/ || $line =~ m/: *$/ ) {
      next;
    }

    #print "99 $line\n";
    # place cfg into an array
    $cfg_list[$cfg_indx] = $line;
    $cfg_indx++;

    # --> list of groups here
    ( my $type, my $server, my $name, my $group_act ) = split( /:/, $line );
    if ( $type eq '' || $server eq '' || $name eq '' || $group_act eq '' ) {
      error( "custom : syntax issue in $cfg: $line " . __FILE__ . ":" . __LINE__ );
      next;
    }
    $server    =~ s/===========doublecoma=========/:/g;
    $name      =~ s/===========doublecoma=========/:/g;
    $name      =~ s/\//\&\&1/g;
    $group_act =~ s/ *$//g;                               # delete spaces at the end
    $group_act =~ s/===========doublecoma=========/:/g;
    if ( $group_prev eq '' || $group_prev !~ m/^$group_act$/ ) {

      # create list of groups
      my $exist = 0;
      foreach my $gr (@groups) {
        if ( $gr =~ m/^$group_act$/ ) {
          $exist = 1;
          last;
        }
      }
      if ( $exist == 0 ) {
        $groups[$groups_name_indx] = $group_act;
        $group_prev = $group_act;
        $groups_name_indx++;
      }
    }
    $groups_type[$groups_indx]   = $type;
    $groups_server[$groups_indx] = $server;
    $groups_lpar[$groups_indx]   = $name;
    $groups_name[$groups_indx]   = $group_act;
    $groups_indx++;
  }
  close(FHR);

  #print STDERR "247 custom.pl\n \@groups_type @groups_type\n \@groups_server @groups_server\n \@groups_lpar @groups_lpar\n \@groups_name @groups_name\n";

  return $cfg_indx;
}

sub load_all_lpars {
  my $lpar_indx   = 0;
  my $pool_indx   = 0;
  my $server_indx = 0;
  my $vims_indx   = 0;

  # goes through all hmc/server and find all lpars
  foreach my $server (<$wrkdir/*>) {

    # print STDERR "258 custom.pl \$server ,$server,\n";
    if ( -l "$server" ) {

      # avoid symlinks
      next;
    }
    if ( -f "$server" ) {

      # avoid regular files
      next;
    }
    if ( $server =~ /\/--HMC--/ ) {

      # avoid special --HMC-- dir
      next;
    }

    my $server_space = $server;
    if ( $server =~ m/ / ) {    # workaround for server name with a space inside, nothing else works, grrr
      $server_space = "\"" . $server . "\"";
    }

    # working with hyperv files
    my $hyperv_found = 0;
    foreach my $hyperv_file (<$server_space/*/hyperv.txt>) {
      next if !-f "$hyperv_file";

      # not supported yet
      $hyperv_found = 1;
    }
    next if $hyperv_found;

    # working with VMware files
    my $vmware_found = 0;
    foreach my $vmware_file (<$server_space/*/vmware.txt>) {
      next if !-f "$vmware_file";
      $vmware_found = 1;
      my $server_vm_path = $vmware_file;
      $server_vm_path =~ s/\/vmware.txt//;    # dirname

      # --- for VM_hosting.vmh
      my $VM_hosting = "$server_vm_path/VM_hosting.vmh";
      next if !-f $VM_hosting;
      open( FF, "<$VM_hosting" ) || error( "can't open $VM_hosting: $! :" . __FILE__ . ":" . __LINE__ ) && next;
      my @vm_lines_all = (<FF>);
      close(FF);

      # print STDERR "281 custom.pl \@vm_lines_all @vm_lines_all\n";
      my @vm_lines = grep {/start=\d\d\d\d\d\d\d\d\d\d$/} @vm_lines_all;

      # print STDERR "284 custom.pl \@vm_lines @vm_lines\n";
      next if scalar @vm_lines eq 0;    # there are no live VMs in this server
                                        # --- end for VM_hosting.vmh

      # --- for lpar_trans.txt
      # my $lpar_trans = "$server_vm_path/lpar_trans.txt";
      my $lpar_trans = "$server_vm_path/cpu.csv";
      next if !-f $lpar_trans;
      open( FF, "<$lpar_trans" ) || error( "can't open $lpar_trans: $! :" . __FILE__ . ":" . __LINE__ ) && next;
      my @vm_names_all = (<FF>);
      close(FF);

      # print STDERR "303 custom.pl \@vm_names_all @vm_names_all\n";
      next if scalar @vm_names_all eq 0;    # there are no VMs in this server
                                            # --- end for lpar_trans

      # if lpar_trans.txt
      # $find_uuid[0] 502a7728-9916-34fb-4832-e1039ad423a5,VM12-CZSI-00-01,vm-4756
      # if cpu.csv
      # $find_uuid[0] Ceph-client1,2,0,-1,normal,2000,CentOS 4/5 or later (64-bit),poweredOff,guestToolsNotRunning,501c4d06-0b08-38da-85ef-3044893f3975,6144,group-v3

      foreach my $vm_uuid (@vm_lines) {
        chomp($vm_uuid);

        # print STDERR "373 \$vm_uuid $vm_uuid\n";
        $vm_uuid =~ s/:.*//g;

        # my @find_uuid = grep {/^$vm_uuid/} @vm_names_all;
        my @find_uuid = grep {/$vm_uuid/} @vm_names_all;
        next if scalar @find_uuid == 0;

        # print STDERR "379 custom.pl \$vm_uuid $vm_uuid \$find_uuid[0] $find_uuid[0]\n";
        chomp $find_uuid[0];
        ( my $vm_name, undef, undef, undef, undef, undef, undef, undef, undef, undef, my $vm_uuid, undef, my $vm_group ) = split( /,/, $find_uuid[0] );
        if ( !defined $vm_group ) {    # old version
          if ( $ENV{DEMO} ) {

            # do not test
          }
          else {
            ( $vm_name, undef, undef, undef, undef, undef, undef, undef, undef, $vm_uuid, undef, $vm_group ) = split( /,/, $find_uuid[0] );
          }
        }

        # print STDERR "419 \$vm_uuid $vm_uuid\n";
        $vm_group = "" if !defined $vm_group;
        $find_uuid[0] = "$vm_uuid,$vm_name,$vm_group";

        $vims_all_list_org[$vims_indx] = "$server_vm_path/$find_uuid[0]";
        $vims_all_list_org[$vims_indx] =~ s/$wrkdir//g;
        $vims_all_list[$vims_indx] = "$server_vm_path/$find_uuid[0]";
        $vims_all_list[$vims_indx] =~ s/$wrkdir//g;
        $vims_indx++;
      }
      $server_list_all[$server_indx] = basename($server);    #lpar name, basename from $file
      $server_indx++;
      last;
    }
    if ( $vmware_found == 1 || -f "$server/vmware.txt" || -f "$server/vmware_alias_name.txt" ) {
      next;
    }

    # open first available pool mapping file
    my @map             = "";
    my $map_file        = "";
    my $map_file_final  = "";
    my $map_file_tstamp = 0;

    foreach my $map_file (<$server_space/*/cpu-pools-mapping.txt>) {
      if ( !-s "$map_file" ) {
        next;    # ignore emty files
      }
      my $tstamp = ( stat("$map_file") )[9];

      # print STDERR "299 custom.pl \$map_file $map_file \$tstamp $tstamp\n";
      if ( $tstamp > $map_file_tstamp ) {
        $map_file_tstamp = $tstamp;
        $map_file_final  = $map_file;
      }
    }
    if ( $map_file_tstamp > 0 ) {
      open( FHP, "< $map_file_final" ) || error( "Can't open $map_file_final : $!" . __FILE__ . ":" . __LINE__ ) && next;
      @map = <FHP>;
      close(FHP);
    }

    foreach my $lpar_fullp (<$server_space/*/*rrm>) {

      # print STDERR "314 custom.pl \$lpar_fullp $lpar_fullp\n";
      my $pool           = 0;
      my $lpar_fullp_org = $lpar_fullp;    # keep original path
      $lpar_fullp =~ s/\.rrm//;
      $lpar_fullp =~ s/\.rrh//;

      if ( $lpar_fullp =~ m/\/mem$/ || $lpar_fullp =~ m/\/mem-pool$/ || $lpar_fullp =~ m/\/cod$/ ) {

        #if ( $lpar_fullp =~ m/SharedPool0$/ || $lpar_fullp =~ m/\/mem$/ || $lpar_fullp =~ m/\/mem-pool$/ || $lpar_fullp =~ m/\/cod$/ ) left_curly
        next;    #exclude SharedPool0 and memory and CoD
      }

      # translate shared pool names
      if ( $lpar_fullp =~ m/SharedPool[0-9]/ ) {

        # shared pools
        $pool = 1;

        # basename without direct function
        my $sh_pool_in = $lpar_fullp;
        my @link_base  = split( /\//, $sh_pool_in );
        foreach my $m (@link_base) {
          $sh_pool_in = $m;
        }
        $lpar_fullp =~ s/$sh_pool_in$//;    # dirname
        $sh_pool_in =~ s/^SharedPool//;

        if ( -f "$lpar_fullp/vmware.txt" ) {
          next;                             # skip VMware  - just to be sure
        }

        my $found    = 0;
        my $map_rows = 0;
        foreach my $line (@map) {
          chomp($line);
          $map_rows++;
          if ( $line !~ m/^[0-9].*,/ ) {

            #something wrong , ignoring
            next;
          }
          ( my $pool_indx_new, my $pool_name_new ) = split( /,/, $line );
          if ( $pool_indx_new == $sh_pool_in ) {
            $lpar_fullp .= $pool_name_new;
            $found++;
            last;
          }
        }
        if ( $found == 0 ) {
          if ( $map_rows > 0 ) {
            print "cgraph error   : could not found name for shared pool : $lpar_fullp/SharedPool$sh_pool_in in $map_file_final\n";
            $lpar_fullp .= "SharedPool$sh_pool_in";
          }
          else {
            print "cgraph error   : Pool mapping table is either empty or does not exist : $map_file_final\n";
            $lpar_fullp .= "SharedPool$sh_pool_in";
          }
        }
      }

      # translate default pool
      if ( $lpar_fullp =~ m/\/pool$/ ) {
        $lpar_fullp =~ s/\/pool$/\/CPU pool/;
        $pool = 1;
      }

      #print "564 $lpar_fullp\n";

      if ( $pool == 1 ) {

        # it is a pool
        $pool_all_list[$pool_indx] = $lpar_fullp;
        $pool_all_list[$pool_indx] =~ s/$wrkdir//g;
        $pool_all_list_org[$pool_indx] = $lpar_fullp_org;
        $pool_all_list_org[$pool_indx] =~ s/$wrkdir//g;
        $pool_indx++;

        # print "575 custom.pl \$lpar_fullp $lpar_fullp \$lpar_fullp_org $lpar_fullp_org\n";
      }
      else {
        # place lpars into an array
        #print "099 $lpar_indx: $lpar_fullp_org - $lpar_fullp\n";
        $lpar_all_list_org[$lpar_indx] = $lpar_fullp_org;
        $lpar_all_list_org[$lpar_indx] =~ s/$wrkdir//g;
        $lpar_all_list[$lpar_indx] = $lpar_fullp;
        $lpar_all_list[$lpar_indx] =~ s/$wrkdir//g;
        $lpar_indx++;
      }

      #print "587 $lpar_fullp\n";
    }
    $server_list_all[$server_indx] = $server;

    # basename without direct function
    my @link_l = split( /\//, $server_list_all[$server_indx] );
    foreach my $m (@link_l) {
      $server_list_all[$server_indx] = $m;    #lpar name, basename from $file
    }

    $server_indx++;

  }

  # sorting lpars/pools per lpar/pool due to dual HMC ....
  @lpar_all_list     = sort { ( split '/', $a )[3] cmp( split '/', $b )[3] } @lpar_all_list;
  @lpar_all_list_org = sort { ( split '/', $a )[3] cmp( split '/', $b )[3] } @lpar_all_list_org;
  @pool_all_list     = sort { ( split '/', $a )[3] cmp( split '/', $b )[3] } @pool_all_list;
  @pool_all_list_org = sort { ( split '/', $a )[3] cmp( split '/', $b )[3] } @pool_all_list_org;
  @server_list_all   = sort { lc $a cmp lc $b } @server_list_all;
  @vims_all_list     = sort { ( split '/', $a )[3] cmp( split '/', $b )[3] } @vims_all_list;
  @vims_all_list_org = sort { ( split '/', $a )[3] cmp( split '/', $b )[3] } @vims_all_list_org;

  #print "610 custom.pl\n \@lpar_all_list @lpar_all_list\n \@lpar_all_list_org @lpar_all_list_org\n \@pool_all_list @pool_all_list\n \@pool_all_list_org @pool_all_list_org\n \@server_list_all @server_list_all\n \@vims_all_list @vims_all_list \@vims_all_list_org @vims_all_list_org\n";
  return 1;
}

sub load_all_sol_zones {
  my $sol_indx        = 0;
  my $sol_server_indx = 0;
  my $sol_ldom_indx   = 0;
  foreach my $server (<$wrkdir/*>) {
    if ( -l "$server" ) {

      # avoid symlinks
      next;
    }
    if ( -f "$server" ) {

      # avoid regular files
      next;
    }
    my $server_space = $server;
    if ( $server =~ m/ / ) {    # workaround for server name with a space inside, nothing else works, grrr
      $server_space = "\"" . $server . "\"";
    }
    if ( $server_space =~ /Solaris$/ ) {
      if ( -d "$wrkdir/Solaris" ) {
        opendir( DIR, "$wrkdir/Solaris" ) || error( "can't opendir $wrkdir/Solaris: $! :" . __FILE__ . ":" . __LINE__ ) && next;
        my @solaris_all = grep !/^\.\.?$/, readdir(DIR);
        closedir(DIR);
        foreach my $solaris_name (@solaris_all) {
          if ( -d "$wrkdir/Solaris/$solaris_name/ZONE" ) {
            if ( -f "$wrkdir/Solaris/$solaris_name/solaris10.txt" ) {next}
            opendir( DIR, "$wrkdir/Solaris/$solaris_name/ZONE" ) || error( "can't opendir $wrkdir/Solaris/$solaris_name/ZONE: $! :" . __FILE__ . ":" . __LINE__ ) && next;
            my @solaris_zone_file = grep !/^\.\.?$|^total|^global|^system/, readdir(DIR);
            rewinddir(DIR);
            my @solaris_ldom_file = grep /^total/, readdir(DIR);
            closedir(DIR);
            foreach my $solaris_zone_name (@solaris_zone_file) {
              $solaris_zone_name =~ s/\.mmm//g;
              $solaris_zone_list_org[$sol_indx] = "$wrkdir/Solaris/$solaris_name/ZONE/$solaris_zone_name.mmm";
              $solaris_zone_list_org[$sol_indx] =~ s/$wrkdir//g;
              $solaris_zone_list[$sol_indx] = "$wrkdir/Solaris/$solaris_name/ZONE/$solaris_zone_name";
              $solaris_zone_list[$sol_indx] =~ s/$wrkdir//g;
              $sol_indx++;
            }
            foreach my $solaris_ldom_name (@solaris_ldom_file) {
              $solaris_ldom_name =~ s/\.mmm//g;
              $solaris_ldom_list_org[$sol_ldom_indx] = "$wrkdir/Solaris/$solaris_name/ZONE/$solaris_ldom_name.mmm";
              $solaris_ldom_list_org[$sol_ldom_indx] =~ s/$wrkdir//g;
              $solaris_ldom_list[$sol_ldom_indx] = "$wrkdir/Solaris/$solaris_name/ZONE/$solaris_ldom_name";
              $solaris_ldom_list[$sol_ldom_indx] =~ s/$wrkdir//g;
              $sol_ldom_indx++;
            }
          }
          $server_list_solaris_all[$sol_server_indx] = $solaris_name;    #lpar name, basename from $file
          $sol_server_indx++;
        }
      }
    }
  }
  @solaris_zone_list       = sort { ( split '/', $a )[3] cmp( split '/', $b )[3] } @solaris_zone_list;
  @solaris_zone_list_org   = sort { ( split '/', $a )[3] cmp( split '/', $b )[3] } @solaris_zone_list_org;
  @solaris_ldom_list       = sort { ( split '/', $a )[3] cmp( split '/', $b )[3] } @solaris_ldom_list;
  @solaris_ldom_list_org   = sort { ( split '/', $a )[3] cmp( split '/', $b )[3] } @solaris_ldom_list_org;
  @server_list_solaris_all = sort { lc $a cmp lc $b } @server_list_solaris_all;
  return 1;
}

sub find_rrd_files {
  my $group_type_prev = "";
  read_menu( \@menu );    # used for power CG

  # if the flag is set for a group, don't create graphs
  my $unsupported_group_type = 0;

  foreach my $group (@groups) {

    # print "445 custom.pl G: $group\n";
    my $indx = 0;
    @lpars_graph        = "";
    @lpars_graph_name   = "";
    @lpars_graph_server = "";
    $lpar_graph_indx    = 0;    #must be global
    $group_type_prev    = "";
    my @all_list     = "";
    my @all_list_org = "";
    $unsupported_group_type = 0;

    foreach my $group_act (@groups_name) {
      if ( $group_act !~ m/^$group$/ ) {
        $indx++;
        next;
      }

      # check if it is the same type LPAR/POOL, if not then return
      if ( !$group_type_prev eq '' && $group_type_prev !~ m/$groups_type[$indx]/ ) {
        print "creating cgraph: " . scalar localtime() . " group mismatch $group_act contains LPAR and POOL directives\n";
        my $indx_prev = $indx;
        $indx_prev--;
        error( "custom : group mismatch $group_act contains LPAR ($groups_lpar[$indx])and POOL ($groups_lpar[$indx]) directives " . __FILE__ . ":" . __LINE__ );
        last;
      }
      $group_type_prev = $groups_type[$indx];

      # skip custom-group types unsupported by this subroutine (e.g., XENVM)
      if ( $groups_type[$indx] !~ m/^(LPAR|POOL|VM)/ ) {
        $indx++;
        $unsupported_group_type++;
        next;
      }

      #if ( $groups_server[$indx] =~ m/\*/ ) left_curly
      # here it must find all servers where particular lpar is running
      # and fill in lpar_graph table by them
      my @server_list = "";

      # goes through all data and put into memory list of all rrm/h $lpar_all_list[] and $pool_all_list[]
      # do it just once!!!
      if ( $search_all_lpars == 0 ) {
        $search_all_lpars++;
        load_all_lpars();
      }

      # print "43 $group_act\n";
      # goes through all servers
      foreach my $server (@server_list_all) {

        # print STDERR "44 $group_act : $server testing $groups_server[$indx]\n";
        # in case VMWARE test if server is in the chosen vCenter
        my $is_vmware_server = 0;

        my $server_space = $server;
        if ( $server =~ m/ / ) {    # workaround for server name with a space inside, nothing else works, grrr
          $server_space = "\"" . $server . "\"";
        }
        my @vcenter_name = (<$wrkdir/$server_space/*/my_vcenter_name>);
        if ( scalar @vcenter_name > 0 ) {
          open( FF, "<$vcenter_name[0]" ) || error( "can't open $vcenter_name[0]: $! :" . __FILE__ . ":" . __LINE__ ) && next;
          my $vc_line = (<FF>);
          close(FF);
          chomp $vc_line;

          # print STDERR "668 custom.pl \$vcenter_name[0] $vcenter_name[0] \$vc_line $vc_line\n";
          ( undef, my $vc_name ) = split( /\|/, $vc_line );
          next if $vc_name !~ /^$groups_server[$indx]$/;
          $is_vmware_server = 1;
        }

        # here is tested regex (for POWERs e.g. '.*')
        if ( $server =~ m/^$groups_server[$indx]$/ || $is_vmware_server ) {

          # print "45 $group_act : $server $groups_type[$indx]\n";
          my $lpar_prev = "";

          # set the source, pool or lpar
          if ( $groups_type[$indx] =~ m/POOL/ ) {
            @all_list     = @pool_all_list;
            @all_list_org = @pool_all_list_org;
          }
          elsif ( $groups_type[$indx] =~ m/LPAR/ ) {
            @all_list     = @lpar_all_list;
            @all_list_org = @lpar_all_list_org;
          }
          else {
            @all_list     = @vims_all_list;
            @all_list_org = @vims_all_list_org;
          }

          # goes through all lpars/pools
          my $server_prev    = "";    # dual HMC exclude ...
          my $lpar_line_prev = "";
          my $index_org      = -1;

          if ($is_vmware_server) {
            foreach my $lpar_line_part (@all_list) {
              $index_org++;
              my $lpar_line     = $wrkdir . $lpar_line_part;
              my $lpar_line_all = $lpar_line;

              # print STDERR "46 VMWARE  $lpar_line - $wrkdir/$server/*/$groups_lpar[$indx] - $group_act : $server\n";

              if ( $lpar_line =~ m/^$wrkdir\/$server\/.*\/.*,$groups_lpar[$indx],.*$/ ) {

                # print STDERR "47 VMWARE $lpar_line : $groups_server[$indx] ; $groups_lpar[$indx]\n";

                my $lpar_a      = "lpar_a";
                my $lpar_prev   = "lpar_prev";
                my $server_prev = "server_prev";
                my $server_a    = "server_a";

                #fill_in_lpar_table($indx,$group_type_prev,$server_a,$lpar_a);
                # fill in the array with list of lpars/pools prepared for graphing
                $lpars_graph[$lpar_graph_indx]        = $lpar_line;
                $lpars_graph_name[$lpar_graph_indx]   = $lpar_a;
                $lpars_graph_server[$lpar_graph_indx] = $server_a;
                $lpars_graph_type[$lpar_graph_indx]   = $groups_type[$indx];
                $lpar_graph_indx++;

                $lpar_line_prev = $all_list_org[$index_org];    # full original path
                $lpar_prev      = $lpar_a;
                $server_prev    = $server_a;
              }
            }
          }
          else {    # POWER

            foreach my $lpar_line_part (@all_list) {

              $index_org++;
              my $lpar_line     = $wrkdir . $lpar_line_part;
              my $lpar_line_all = $lpar_line;

              # print "821 \$lpar_line_part $lpar_line_part \$lpar_line $lpar_line \$wrkdir $wrkdir \$server $server \$indx $indx $groups_lpar[$indx]\n";
              if ( $lpar_line =~ m/^$wrkdir\/$server\/.*\/$groups_lpar[$indx]$/ ) {

                my $name_full = $lpar_line;

                # print "824 \$name_full $name_full \$indx $indx $groups_type[$indx]\n";   #if ( $groups_type[$indx] =~ m/POOL/ ) left_curly
                # basename without direct function
                my $lpar_a = $name_full;
                my @base   = split( /\//, $lpar_a );
                foreach my $m (@base) {
                  $lpar_a = $m;    #lpar name, basename from $file
                }

                # $name_full =~ s/\/$lpar_a$//;
                $name_full = dirname $name_full;

                # print "831 \$name_full $name_full \@base ,@base, \$lpar_a $lpar_a\n";

                # basename without direct function
                my $hmc_a = $name_full;
                @base = split( /\//, $hmc_a );
                foreach my $m (@base) {
                  $hmc_a = $m;    #lpar name, basename from $file
                }
                $name_full =~ s/\/$hmc_a$//;

                # print "840 \$name_full $name_full \$server_prev $server_prev\n";

                # basename without direct function
                my $server_a = $name_full;
                @base = split( /\//, $server_a );
                foreach my $m (@base) {
                  $server_a = $m;    #lpar name, basename from $file
                }

                # print "849 \$name_full $name_full \@base ,@base, \$server_a $server_a\n";
                # dual HMC exclude
                # for POWER shared pools
                if ( $groups_type[$indx] eq 'POOL' ) {

                  # print "854 \$server_prev $server_prev \$server_a $server_a \$lpar_prev $lpar_prev \$lpar_a $lpar_a\n";
                  # 854 $server_prev  $server_a Power770 $lpar_prev  $lpar_a CPU pool
                  next if ( ( $server_prev eq $server_a ) && ( $lpar_prev eq $lpar_a ) );

                  # test if this server & pool is in menu_power.txt
                  # S:hmc:Power770:CPUpool-SharedPool0:CPU pool 0 ===double-col=== DefaultPool:/lpar2rrd-cgi/detail.sh
                  my @matches = ();
                  if ( $lpar_a eq "CPU pool" ) {
                    @matches = grep { /^S:/ && /:$server_a:/ && /:CPUpool-SharedPool/ } @menu;
                  }
                  else {
                    @matches = grep { /^S:/ && /:$server_a:/ && /:CPUpool-SharedPool/ && / \Q$lpar_a\E/ } @menu;
                  }
                  next if ( !@matches or ( scalar @matches < 1 ) );

                  # print "875 here matches\n";
                }
                if ( $server_prev ne '' && ( $groups_type[$indx] ne 'POOL' ) ) {

                  # print "853 $group : $server_a - $server_prev - $hmc_a - $lpar_a \n";
                  # L:hmc:Power770:Accept%2Ftest:Accept/test:/lpar2rrd-cgi/detail.sh?host=hmc&server=Power770&lpar=Accept%2Ftest&item=lpar&entitle=0&gui=1&none=none:::P:C
                  # take only LPARs active in menu 'menu_power.txt'
                  my $lpar_a_slash = $lpar_a;    # can be like Accept&&1test
                  $lpar_a_slash =~ s/&&1/\//g;
                  my @matches = grep { /^L:$hmc_a:$server_a:/ && /:$lpar_a_slash:/ } @menu;

                  # print "860 @matches\n";
                  next if ( !@matches or ( scalar @matches < 1 ) );

                  if ( !$server_prev eq '' && $server_prev =~ m/^$server_a$/ && $lpar_prev =~ m/^$lpar_a$/ ) {

                    #                  if ( !$server_prev eq '' && ($server_prev eq $server_a) && ($lpar_prev eq $lpar_a) ) left_curly

                    # *_org keep original full path of the .rrm file
                    my $rrd_lpar_time      = rrd_last("$wrkdir/$all_list_org[$index_org]");
                    my $rrd_lpar_prev_time = rrd_last("$wrkdir/$lpar_line_prev");

                    # print "869 $index_org: $lpar_line_prev : $rrd_lpar_prev_time : $all_list_org[$index_org] : $rrd_lpar_time \n";

                    # find out the HMC with most recent data, if it is the second one listed then change the previous record
                    if ( $rrd_lpar_time > $rrd_lpar_prev_time ) {

                      #print "001 change $lpar_line $lpar_line_prev : $lpar_a $server_a\n";
                      # replace previous record for dual HMC with the fresh one
                      $lpar_graph_indx--;
                      $lpars_graph[$lpar_graph_indx]        = $lpar_line;
                      $lpars_graph_name[$lpar_graph_indx]   = $lpar_a;
                      $lpars_graph_server[$lpar_graph_indx] = $server_a;
                      $lpars_graph_type[$lpar_graph_indx]   = $groups_type[$indx];
                      $lpar_graph_indx++;

                      $lpar_line_prev = $all_list_org[$index_org];    # full original path
                      $lpar_prev      = $lpar_a;
                      $server_prev    = $server_a;
                    }
                    next;                                             # dual HMC??
                  }
                }

                #fill_in_lpar_table($indx,$group_type_prev,$server_a,$lpar_a);
                # fill in the array with list of lpars/pools prepared for graphing
                $lpars_graph[$lpar_graph_indx]        = $lpar_line;
                $lpars_graph_name[$lpar_graph_indx]   = $lpar_a;
                $lpars_graph_server[$lpar_graph_indx] = $server_a;
                $lpars_graph_type[$lpar_graph_indx]   = $groups_type[$indx];
                $lpar_graph_indx++;

                $lpar_line_prev = $all_list_org[$index_org];    # full original path
                $lpar_prev      = $lpar_a;
                $server_prev    = $server_a;
              }
            }
          }
        }
      }
      $indx++;
    }
    if ( !$group_type_prev eq '' ) {
      if ($unsupported_group_type) {

        # neither create graphs, nor fail, if the group type isn't supported by this subroutine
        next;
      }
      elsif ( $lpar_graph_indx == 0 ) {

        # nothing has been found
        print "cgraph no found: could not identify any lpar or pool for group: \"$group\"\n";
        error( "custom group: could not identify any lpar or pool for group: \"$group\" " . __FILE__ . ":" . __LINE__ );

        # exit;
      }
      else {
        # print "77 $group: $lpar_graph_indx\n";
        graph_it($group);
      }
    }
  }
  return 0;
}

sub process_xenserver_custom_groups {

  # trivia
  # information about XenServer is stored in `data/XEN_iostats/conf.json` (accessible through XenServerDataWrapper)
  # thus, it is unnecessary to explicitly crawl the filesystem to find RRDs
  # thus, this subroutine skips the `find_rrd_files` and `load_all_lpars` phases
  # hopefully, the other subroutines don't find any XenServer RRDs or attempt to graph them either
  # why? because the XenServer-support implementation uses UUIDs in file hierarchy and does not contain TXT files either, thus `load_all_lpars` hopefully skips them
  # what does this replacement do instead?
  # 1. go through @groups* as parsed by `cfg_load`
  # 2. for each group (of the "XENVM" type), use XenServerDataWrapper to get both VM/pool list and labels, and RRD filepaths from the filesystem
  # 3. fill @lpars_graph* right there and `graph_it`

  # because each group may have multiple entries in @groups*, processing runs in two nested loops
  # thus, keep record of already processed groups in order to avoid processing them multiple times
  my %processed_groups;

  my $xenserver_metadata = XenServerDataWrapperOOP->new();

  # note: @groups contains only unique group names, whereas @groups_name can be redundant
  # thus, iterate over @groups_name, which is the same length as @groups_type
  for my $i ( 0 .. $#groups_name ) {
    if ( $groups_type[$i] =~ m/XENVM/ && !exists( $processed_groups{ $groups_name[$i] } ) ) {

      # clear @lpars_graph* (as done in `find_rrd_files`)
      @lpars_graph        = '';
      @lpars_graph_name   = '';
      @lpars_graph_server = '';
      @lpars_graph_type   = '';

      # position in the @lpars_graph* table
      my $k = 0;

      for my $j ( 0 .. $#groups_name ) {
        if ( $groups_type[$j] =~ m/XENVM/ && $groups_name[$i] eq $groups_name[$j] ) {
          my $pool_mask = $groups_server[$j];
          my $vm_mask   = $groups_lpar[$j];

          # filter pools
          my @pools = @{ $xenserver_metadata->get_items( { item_type => 'pool' } ) };
          foreach my $pool (@pools) {
            my ( $pool_uuid, $pool_label ) = each %{$pool};
            if ( $pool_label =~ m/^$pool_mask$/ ) {
              my @vms_in_pool = @{ $xenserver_metadata->get_items( { item_type => 'vm', parent_type => 'pool', parent_uuid => $pool_uuid } ) };

              # filter VMs in this particular pool
              foreach my $vm (@vms_in_pool) {
                my ( $vm_uuid, $vm_label ) = each %{$vm};
                if ( $vm_label =~ m/^$vm_mask$/ ) {
                  my $vm_filepath = $xenserver_metadata->get_filepath_rrd( { type => 'vm', uuid => $vm_uuid, skip_acl => 1 } );
                  next unless ($vm_filepath);

                  # print STDERR "custom.pl DEBUG add to lpars_graph* at $j\n\t$vm_filepath\t$vm_label\t$pool_label\t$groups_type[$i]\n";

                  # add the VM to the @lpars_graph* table
                  $lpars_graph[$k]        = $vm_filepath;
                  $lpars_graph_name[$k]   = $vm_label;
                  $lpars_graph_server[$k] = $pool_label;
                  $lpars_graph_type[$k]   = $groups_type[$i];
                  $k++;
                }
              }
            }
          }
        }
      }

      # call graph command generation, if any VMs have been selected
      if ( $k > 0 ) {
        graph_it( $groups_name[$i] );

        # skip this group on future iterations
        $processed_groups{ $groups_name[$i] } = 1;
      }
    }
  }

  return 0;
}

sub process_nutanix_custom_groups {

  # information about Nutanix is stored in `data/NUTANIX/conf.json`, it is unnecessary to explicitly crawl the filesystem to find RRDs
  my %processed_groups;

  # note: @groups contains only unique group names, whereas @groups_name can be redundant
  # thus, iterate over @groups_name, which is the same length as @groups_type
  for my $i ( 0 .. $#groups_name ) {
    if ( $groups_type[$i] =~ m/NUTANIXVM/ && !exists( $processed_groups{ $groups_name[$i] } ) ) {

      # clear @lpars_graph* (as done in `find_rrd_files`)
      @lpars_graph        = '';
      @lpars_graph_name   = '';
      @lpars_graph_server = '';
      @lpars_graph_type   = '';

      # position in the @lpars_graph* table
      my $k = 0;

      for my $j ( 0 .. $#groups_name ) {
        if ( $groups_type[$j] =~ m/NUTANIXVM/ && $groups_name[$i] eq $groups_name[$j] ) {
          my $pool_mask = $groups_server[$j];
          my $vm_mask   = $groups_lpar[$j];

          # filter pools
          my @pools = @{ NutanixDataWrapper::get_items( { item_type => 'cluster' } ) };
          foreach my $pool (@pools) {
            my ( $pool_uuid, $pool_label ) = each %{$pool};
            if ( $pool_label =~ m/^$pool_mask$/ ) {
              my @vms_in_pool = @{ NutanixDataWrapper::get_items( { item_type => 'vm', parent_type => 'cluster', parent_uuid => $pool_uuid } ) };

              # filter VMs in this particular pool
              foreach my $vm (@vms_in_pool) {
                my ( $vm_uuid, $vm_label ) = each %{$vm};
                if ( $vm_label =~ m/^$vm_mask$/ ) {
                  my $vm_filepath = NutanixDataWrapper::get_filepath_rrd( { type => 'vm', uuid => $vm_uuid, skip_acl => 1 } );

                  # print STDERR "custom.pl DEBUG add to lpars_graph* at $j\n\t$vm_filepath\t$vm_label\t$pool_label\t$groups_type[$i]\n";

                  # add the VM to the @lpars_graph* table
                  $lpars_graph[$k]        = $vm_filepath;
                  $lpars_graph_name[$k]   = $vm_label;
                  $lpars_graph_server[$k] = $pool_label;
                  $lpars_graph_type[$k]   = $groups_type[$i];
                  $k++;
                }
              }
            }
          }
        }
      }

      # call graph command generation, if any VMs have been selected
      if ( $k > 0 ) {
        graph_it( $groups_name[$i] );

        # skip this group on future iterations
        $processed_groups{ $groups_name[$i] } = 1;
      }
    }
  }

  return 0;
}

sub process_proxmox_custom_groups {
  my %processed_groups;

  # note: @groups contains only unique group names, whereas @groups_name can be redundant
  # thus, iterate over @groups_name, which is the same length as @groups_type
  for my $i ( 0 .. $#groups_name ) {
    if ( $groups_type[$i] =~ m/PROXMOXVM/ && !exists( $processed_groups{ $groups_name[$i] } ) ) {

      # clear @lpars_graph* (as done in `find_rrd_files`)
      @lpars_graph        = '';
      @lpars_graph_name   = '';
      @lpars_graph_server = '';
      @lpars_graph_type   = '';

      # position in the @lpars_graph* table
      my $k = 0;

      for my $j ( 0 .. $#groups_name ) {
        if ( $groups_type[$j] =~ m/PROXMOXVM/ && $groups_name[$i] eq $groups_name[$j] ) {
          my $cluster_mask = $groups_server[$j];
          my $vm_mask      = $groups_lpar[$j];

          # filter clusters
          my @clusters = @{ ProxmoxDataWrapper::get_items( { item_type => 'cluster' } ) };
          foreach my $cluster (@clusters) {
            my ( $cluster_uuid, $cluster_label ) = each %{$cluster};
            if ( $cluster_label =~ m/^$cluster_mask$/ ) {
              my @vms_in_cluster = @{ ProxmoxDataWrapper::get_items( { item_type => 'vm', parent_type => 'cluster', parent_uuid => $cluster_uuid } ) };

              # filter VMs in this particular cluster
              foreach my $vm (@vms_in_cluster) {
                my ( $vm_uuid, $vm_label ) = each %{$vm};
                if ( $vm_label =~ m/^$vm_mask$/ ) {
                  my $vm_filepath = ProxmoxDataWrapper::get_filepath_rrd( { type => 'vm', uuid => $vm_uuid, skip_acl => 1 } );

                  # print STDERR "custom.pl DEBUG add to lpars_graph* at $j\n\t$vm_filepath\t$vm_label\t$pool_label\t$groups_type[$i]\n";

                  # add the VM to the @lpars_graph* table
                  $lpars_graph[$k]        = $vm_filepath;
                  $lpars_graph_name[$k]   = $vm_label;
                  $lpars_graph_server[$k] = $cluster_label;
                  $lpars_graph_type[$k]   = $groups_type[$i];
                  $k++;
                }
              }
            }
          }
        }
      }

      # call graph command generation, if any VMs have been selected
      if ( $k > 0 ) {
        graph_it( $groups_name[$i] );

        # skip this group on future iterations
        $processed_groups{ $groups_name[$i] } = 1;
      }
    }
  }

  return 0;
}

sub process_fusioncompute_custom_groups {
  my %processed_groups;

  for my $i ( 0 .. $#groups_name ) {
    if ( $groups_type[$i] =~ m/FUSIONCOMPUTEVM/ && !exists( $processed_groups{ $groups_name[$i] } ) ) {

      # clear @lpars_graph* (as done in `find_rrd_files`)
      @lpars_graph        = '';
      @lpars_graph_name   = '';
      @lpars_graph_server = '';
      @lpars_graph_type   = '';

      # position in the @lpars_graph* table
      my $k = 0;

      for my $j ( 0 .. $#groups_name ) {
        if ( $groups_type[$j] =~ m/FUSIONCOMPUTEVM/ && $groups_name[$i] eq $groups_name[$j] ) {
          my $cluster_mask = $groups_server[$j];
          my $vm_mask      = $groups_lpar[$j];

          # filter clusters
          my @clusters = @{ FusionComputeDataWrapper::get_items( { item_type => 'cluster' } ) };
          foreach my $cluster (@clusters) {
            my ( $cluster_uuid, $cluster_label ) = each %{$cluster};
            if ( $cluster_label =~ m/^$cluster_mask$/ ) {
              my @vms_in_cluster = @{ FusionComputeDataWrapper::get_items( { item_type => 'vm', parent_type => 'cluster', parent_uuid => $cluster_uuid } ) };

              # filter VMs in this particular cluster
              foreach my $vm (@vms_in_cluster) {
                my ( $vm_uuid, $vm_label ) = each %{$vm};
                if ( $vm_label =~ m/^$vm_mask$/ ) {
                  my $vm_filepath = FusionComputeDataWrapper::get_filepath_rrd( { type => 'vm', uuid => $vm_uuid, skip_acl => 1 } );

                  # print STDERR "custom.pl DEBUG add to lpars_graph* at $j\n\t$vm_filepath\t$vm_label\t$pool_label\t$groups_type[$i]\n";

                  # add the VM to the @lpars_graph* table
                  $lpars_graph[$k]        = $vm_filepath;
                  $lpars_graph_name[$k]   = $vm_label;
                  $lpars_graph_server[$k] = $cluster_label;
                  $lpars_graph_type[$k]   = $groups_type[$i];
                  $k++;
                }
              }
            }
          }
        }
      }

      # call graph command generation, if any VMs have been selected
      if ( $k > 0 ) {
        graph_it( $groups_name[$i] );

        # skip this group on future iterations
        $processed_groups{ $groups_name[$i] } = 1;
      }
    }
  }

  return 0;
}

sub process_openshift_custom_groups {
  my %processed_groups;

  my $openshiftWrapper = OpenshiftDataWrapperOOP->new();

  # note: @groups contains only unique group names, whereas @groups_name can be redundant
  # thus, iterate over @groups_name, which is the same length as @groups_type
  for my $i ( 0 .. $#groups_name ) {
    if ( $groups_type[$i] =~ m/OPENSHIFTNODE/ && !exists( $processed_groups{ $groups_name[$i] } ) ) {

      # clear @lpars_graph* (as done in `find_rrd_files`)
      @lpars_graph        = '';
      @lpars_graph_name   = '';
      @lpars_graph_server = '';
      @lpars_graph_type   = '';

      # position in the @lpars_graph* table
      my $k = 0;

      for my $j ( 0 .. $#groups_name ) {
        if ( $groups_type[$j] =~ m/OPENSHIFTNODE/ && $groups_name[$i] eq $groups_name[$j] ) {
          my $cluster_mask = $groups_server[$j];
          my $node_mask    = $groups_lpar[$j];

          # filter clusters
          my @clusters = @{ $openshiftWrapper->get_items( { item_type => 'cluster' } ) };
          foreach my $cluster (@clusters) {
            my ( $cluster_uuid, $cluster_label ) = each %{$cluster};
            if ( $cluster_label =~ m/^$cluster_mask$/ ) {
              my @nodes_in_cluster = @{ $openshiftWrapper->get_items( { item_type => 'node', parent_type => 'cluster', parent_id => $cluster_uuid } ) };

              # filter Nodes in this particular cluster
              foreach my $node (@nodes_in_cluster) {
                my ( $node_uuid, $node_label ) = each %{$node};
                if ( $node_label =~ m/^$node_mask$/ ) {
                  my $node_filepath = OpenshiftDataWrapper::get_filepath_rrd( { type => 'node', uuid => $node_uuid, skip_acl => 1 } );

                  # print STDERR "custom.pl DEBUG add to lpars_graph* at $j\n\t$vm_filepath\t$vm_label\t$pool_label\t$groups_type[$i]\n";

                  # add the VM to the @lpars_graph* table
                  $lpars_graph[$k]        = $node_filepath;
                  $lpars_graph_name[$k]   = $node_label;
                  $lpars_graph_server[$k] = $cluster_label;
                  $lpars_graph_type[$k]   = $groups_type[$i];
                  $k++;
                }
              }
            }
          }
        }
      }

      # call graph command generation, if any VMs have been selected
      if ( $k > 0 ) {
        graph_it( $groups_name[$i] );

        # skip this group on future iterations
        $processed_groups{ $groups_name[$i] } = 1;
      }
    }

    if ( $groups_type[$i] =~ m/OPENSHIFTPROJECT/ && !exists( $processed_groups{ $groups_name[$i] } ) ) {

      # clear @lpars_graph* (as done in `find_rrd_files`)
      @lpars_graph        = '';
      @lpars_graph_name   = '';
      @lpars_graph_server = '';
      @lpars_graph_type   = '';

      # position in the @lpars_graph* table
      my $k = 0;

      for my $j ( 0 .. $#groups_name ) {
        if ( $groups_type[$j] =~ m/OPENSHIFTPROJECT/ && $groups_name[$i] eq $groups_name[$j] ) {
          my $cluster_mask   = $groups_server[$j];
          my $namespace_mask = $groups_lpar[$j];

          # filter clusters
          my @clusters = @{ $openshiftWrapper->get_items( { item_type => 'cluster' } ) };
          foreach my $cluster (@clusters) {
            my ( $cluster_uuid, $cluster_label ) = each %{$cluster};
            if ( $cluster_label =~ m/^$cluster_mask$/ ) {
              my @namespaces_in_cluster = @{ $openshiftWrapper->get_items( { item_type => 'namespace', parent_type => 'cluster', parent_id => $cluster_uuid } ) };

              # filter Nodes in this particular cluster
              foreach my $namespace (@namespaces_in_cluster) {
                my ( $namespace_uuid, $namespace_label ) = each %{$namespace};
                if ( $namespace_label =~ m/^$namespace_mask$/ ) {
                  my $namespace_filepath = OpenshiftDataWrapper::get_filepath_rrd( { type => 'namespace', uuid => $namespace_uuid, skip_acl => 1 } );

                  # print STDERR "custom.pl DEBUG add to lpars_graph* at $j\n\t$vm_filepath\t$vm_label\t$pool_label\t$groups_type[$i]\n";

                  # add the VM to the @lpars_graph* table
                  $lpars_graph[$k]        = $namespace_filepath;
                  $lpars_graph_name[$k]   = $namespace_label;
                  $lpars_graph_server[$k] = $cluster_label;
                  $lpars_graph_type[$k]   = $groups_type[$i];
                  $k++;
                }
              }
            }
          }
        }
      }

      # call graph command generation, if any VMs have been selected
      if ( $k > 0 ) {
        graph_it( $groups_name[$i] );

        # skip this group on future iterations
        $processed_groups{ $groups_name[$i] } = 1;
      }
    }
  }

  return 0;
}

sub process_kubernetes_custom_groups {
  my %processed_groups;

  my $kubernetesWrapper = KubernetesDataWrapperOOP->new();

  # note: @groups contains only unique group names, whereas @groups_name can be redundant
  # thus, iterate over @groups_name, which is the same length as @groups_type
  for my $i ( 0 .. $#groups_name ) {
    if ( $groups_type[$i] =~ m/KUBERNETESNODE/ && !exists( $processed_groups{ $groups_name[$i] } ) ) {

      # clear @lpars_graph* (as done in `find_rrd_files`)
      @lpars_graph        = '';
      @lpars_graph_name   = '';
      @lpars_graph_server = '';
      @lpars_graph_type   = '';

      # position in the @lpars_graph* table
      my $k = 0;

      for my $j ( 0 .. $#groups_name ) {
        if ( $groups_type[$j] =~ m/KUBERNETESNODE/ && $groups_name[$i] eq $groups_name[$j] ) {
          my $cluster_mask = $groups_server[$j];
          my $node_mask    = $groups_lpar[$j];

          # filter clusters
          my @clusters = @{ $kubernetesWrapper->get_items( { item_type => 'cluster' } ) };
          foreach my $cluster (@clusters) {
            my ( $cluster_uuid, $cluster_label ) = each %{$cluster};
            if ( $cluster_label =~ m/^$cluster_mask$/ ) {
              my @nodes_in_cluster = @{ $kubernetesWrapper->get_items( { item_type => 'node', parent_type => 'cluster', parent_id => $cluster_uuid } ) };

              # filter Nodes in this particular cluster
              foreach my $node (@nodes_in_cluster) {
                my ( $node_uuid, $node_label ) = each %{$node};
                if ( $node_label =~ m/^$node_mask$/ ) {
                  my $node_filepath = KubernetesDataWrapper::get_filepath_rrd( { type => 'node', uuid => $node_uuid, skip_acl => 1 } );

                  # print STDERR "custom.pl DEBUG add to lpars_graph* at $j\n\t$vm_filepath\t$vm_label\t$pool_label\t$groups_type[$i]\n";

                  # add the VM to the @lpars_graph* table
                  $lpars_graph[$k]        = $node_filepath;
                  $lpars_graph_name[$k]   = $node_label;
                  $lpars_graph_server[$k] = $cluster_label;
                  $lpars_graph_type[$k]   = $groups_type[$i];
                  $k++;
                }
              }
            }
          }
        }
      }

      # call graph command generation, if any VMs have been selected
      if ( $k > 0 ) {
        graph_it( $groups_name[$i] );

        # skip this group on future iterations
        $processed_groups{ $groups_name[$i] } = 1;
      }
    }

    if ( $groups_type[$i] =~ m/KUBERNETESNAMESPACE/ && !exists( $processed_groups{ $groups_name[$i] } ) ) {

      # clear @lpars_graph* (as done in `find_rrd_files`)
      @lpars_graph        = '';
      @lpars_graph_name   = '';
      @lpars_graph_server = '';
      @lpars_graph_type   = '';

      # position in the @lpars_graph* table
      my $k = 0;

      for my $j ( 0 .. $#groups_name ) {
        if ( $groups_type[$j] =~ m/KUBERNETESNAMESPACE/ && $groups_name[$i] eq $groups_name[$j] ) {
          my $cluster_mask   = $groups_server[$j];
          my $namespace_mask = $groups_lpar[$j];

          # filter clusters
          my @clusters = @{ $kubernetesWrapper->get_items( { item_type => 'cluster' } ) };
          foreach my $cluster (@clusters) {
            my ( $cluster_uuid, $cluster_label ) = each %{$cluster};
            if ( $cluster_label =~ m/^$cluster_mask$/ ) {
              my @namespaces_in_cluster = @{ $kubernetesWrapper->get_items( { item_type => 'namespace', parent_type => 'cluster', parent_id => $cluster_uuid } ) };

              # filter Nodes in this particular cluster
              foreach my $namespace (@namespaces_in_cluster) {
                my ( $namespace_uuid, $namespace_label ) = each %{$namespace};
                if ( $namespace_label =~ m/^$namespace_mask$/ ) {
                  my $namespace_filepath = KubernetesDataWrapper::get_filepath_rrd( { type => 'namespace', uuid => $namespace_uuid, skip_acl => 1 } );

                  # print STDERR "custom.pl DEBUG add to lpars_graph* at $j\n\t$vm_filepath\t$vm_label\t$pool_label\t$groups_type[$i]\n";

                  # add the VM to the @lpars_graph* table
                  $lpars_graph[$k]        = $namespace_filepath;
                  $lpars_graph_name[$k]   = $namespace_label;
                  $lpars_graph_server[$k] = $cluster_label;
                  $lpars_graph_type[$k]   = $groups_type[$i];
                  $k++;
                }
              }
            }
          }
        }
      }

      # call graph command generation, if any VMs have been selected
      if ( $k > 0 ) {
        graph_it( $groups_name[$i] );

        # skip this group on future iterations
        $processed_groups{ $groups_name[$i] } = 1;
      }
    }
  }

  return 0;
}

sub process_ovirt_custom_groups {
  my %processed_groups;

  for my $i ( 0 .. $#groups_name ) {
    if ( $groups_type[$i] =~ m/OVIRTVM/ && !exists( $processed_groups{ $groups_name[$i] } ) ) {
      @lpars_graph        = "";
      @lpars_graph_name   = "";
      @lpars_graph_server = "";
      @lpars_graph_type   = "";

      # position in @lpars_graph* table
      my $k = 0;

      for my $j ( 0 .. $#groups_name ) {
        if ( $groups_type[$j] =~ m/OVIRTVM/ && $groups_name[$i] eq $groups_name[$j] ) {
          my $cluster_mask = $groups_server[$j];
          my $vm_mask      = $groups_lpar[$j];

          # filter clusters
          foreach my $cluster_uuid ( @{ OVirtDataWrapper::get_uuids('cluster') } ) {
            my $cluster_label = OVirtDataWrapper::get_label( 'cluster', $cluster_uuid );

            if ( $cluster_label =~ m/^$cluster_mask$/ ) {
              my @vms_in_cluster = @{ OVirtDataWrapper::get_arch( $cluster_uuid, 'cluster', 'vm' ) };

              # filter VMs in this particular pool
              foreach my $vm_uuid (@vms_in_cluster) {
                my $vm_label = OVirtDataWrapper::get_label( 'vm', $vm_uuid );

                if ( $vm_label =~ m/^$vm_mask$/ ) {
                  my $vm_filepath = OVirtDataWrapper::get_filepath_rrd( { type => 'vm', uuid => $vm_uuid, skip_acl => 1 } );

                  # print "## custom.pl DEBUG add to lpars_graph* at $j\n\t$vm_filepath\t$vm_label\t$cluster_label\t$groups_type[$i]\n";

                  # add the VM to the @lpars_graph* table
                  $lpars_graph[$k]        = $vm_filepath;
                  $lpars_graph_name[$k]   = $vm_label;
                  $lpars_graph_server[$k] = $cluster_label;
                  $lpars_graph_type[$k]   = $groups_type[$i];
                  $k++;
                }
              }
            }
          }
        }
      }

      # print "##d " . Dumper( \%processed_groups ) . "\n";
      # print "##e " . Dumper( \@lpars_graph ) . "\n";

      # call graph command generation, if any VMs have been selected
      if ( $k > 0 ) {
        graph_it( $groups_name[$i] );
        $processed_groups{ $groups_name[$i] } = 1;
      }
    }
  }

  return 0;
}    ## sub process_ovirt_custom_groups

sub process_oraclevm_custom_groups {

  my %processed_groups;

  for my $i ( 0 .. $#groups_name ) {

    #print" $groups_type[$i]\n";
    if ( $groups_type[$i] =~ m/ORVM/ && !exists( $processed_groups{ $groups_name[$i] } ) ) {

      # clear @lpars_graph* (as done in `find_rrd_files`)
      @lpars_graph        = '';
      @lpars_graph_name   = '';
      @lpars_graph_server = '';
      @lpars_graph_type   = '';

      # position in the @lpars_graph* table
      my $k = 0;
      for my $j ( 0 .. $#groups_name ) {
        if ( $groups_type[$j] =~ m/ORVM/ && $groups_name[$i] eq $groups_name[$j] ) {
          my $pool_mask = $groups_server[$j];
          my $vm_mask   = $groups_lpar[$j];

          # filter server_pools
          my @server_pools = @{ OracleVmDataWrapper::get_items( { item_type => 'server_pool' } ) };

          #print "server_pools-@server_pools\n";
          foreach my $server_pool (@server_pools) {
            my ( $server_pool_uuid, $server_pool_label ) = each %{$server_pool};

            #print "server_pool_uuid-$server_pool_uuid,$server_pool_label--VYBRANY SERVER_POOL:$pool_mask,VYBRANE VM: $vm_mask\n";
            if ( $server_pool_label =~ m/^$pool_mask$/ ) {

              #my $mapping_server_pool  = OracleVmDataWrapper::get_conf_section('vms_server_pool');
              my @vms_in_pool = @{ OracleVmDataWrapper::get_items( { item_type => 'vm', parent_type => 'server_pool', parent_uuid => $server_pool_uuid } ) };

              # filter VMs in this particular pool
              foreach my $vm (@vms_in_pool) {
                my ( $vm_uuid, $vm_label ) = each %{$vm};
                if ( $vm_label =~ m/^$vm_mask$/ ) {
                  my $vm_filepath = OracleVmDataWrapper::get_filepath_rrd( { type => 'vm', uuid => $vm_uuid, skip_acl => 1 } );

                  #print STDERR "custom.pl DEBUG add to lpars_graph* at $j\n\t$vm_filepath\t$vm_label\t$server_pool_label\t$groups_type[$i]\n";
                  # add the VM to the @lpars_graph* table
                  $lpars_graph[$k]        = $vm_filepath;
                  $lpars_graph_name[$k]   = $vm_label;
                  $lpars_graph_server[$k] = $server_pool_label;
                  $lpars_graph_type[$k]   = $groups_type[$i];
                  $k++;
                }
              }
            }
          }
        }
      }

      # call graph command generation, if any VMs have been selected
      if ( $k > 0 ) {
        graph_it( $groups_name[$i] );

        # skip this group on future iterations
        $processed_groups{ $groups_name[$i] } = 1;
      }
    }
  }

  return 0;
}

# read tmp/menu.txt
sub read_menu {
  my $menu_ref = shift;
  open( FF, "<$tmpdir/menu.txt" ) || error( "can't open $tmpdir!menu.txt: $! :" . __FILE__ . ":" . __LINE__ ) && return 0;
  @$menu_ref = (<FF>);
  close(FF);
  return;
}

sub process_hyperv_custom_groups {
  my %processed_groups;

  # my @menu; # should be global
  read_menu( \@menu );

  # print "984 menu.txt @menu\n";
  # L:merlin.cz:HVA02:D5827A0C-804D-43BC-8F5F-550F3B4FD28F:OBS09:/lpar2rrd-cgi/detail.sh?host=HVA02&server=windows/domain_merlin.cz&lpar=D5827A0C-804D-43BC-8F5F-550F3B4FD28F&item=lpar&entitle=0&gui=1&none=none:cluster_merlin::H

  my @matches = grep { /^L/ && /server=windows/ } @menu;

  # print "986 @matches\n";

  for my $i ( 0 .. $#groups_name ) {

    # print "1006 \$i $i \$groups_type $groups_type[$i] \$processed_groups $groups_name[$i] ".$processed_groups{ $groups_name[$i] }." \n";
    if ( $groups_type[$i] =~ m/HYPERVM/ && !exists( $processed_groups{ $groups_name[$i] } ) ) {
      @lpars_graph        = "";
      @lpars_graph_name   = "";
      @lpars_graph_server = "";
      @lpars_graph_type   = "";

      # position in @lpars_graph* table
      my $k = 0;

      for my $j ( 0 .. $#groups_name ) {

        # print "1017 \$i $i \$j $j \$groups_type $groups_type[$j] \$groups_name $groups_name[$i] $groups_name[$j] \n";
        if ( $groups_type[$j] =~ m/HYPERVM/ && $groups_name[$i] eq $groups_name[$j] ) {
          my $domain_mask = $groups_server[$j];
          my $vm_mask     = $groups_lpar[$j];

          # print "1021 \$domain_mask $domain_mask \$vm_mask $vm_mask\n";
          # next;
          # filter HYPERV menu lines
          foreach (@matches) {
            ( undef, my $domain_label, my $hyp_server, my $vm_uuid, my $vm_label, undef, my $hyp_cluster, undef ) = split ":", $_;

            if ( ( $domain_label =~ m/^$domain_mask$/ || $hyp_cluster =~ m/^$domain_mask$/ ) && $vm_label =~ m/^$vm_mask$/ ) {

              my $vm_filepath = "$wrkdir/windows/domain_$domain_label/hyperv_VMs/$vm_uuid.rrm";

              # print "1031 ## custom.pl DEBUG add to lpars_graph* at $j\n\t$vm_filepath\t$vm_label\t$domain_label\t$groups_type[$i]\n";

              # add the VM to the @lpars_graph* table
              $lpars_graph[$k]      = $vm_filepath;
              $lpars_graph_name[$k] = $vm_label;

              # $lpars_graph_server[$k] = $domain_label;
              $lpars_graph_server[$k] = $hyp_server;
              $lpars_graph_type[$k]   = $groups_type[$i];
              $k++;
            }
          }
        }
      }

      # print "##d " . Dumper( \%processed_groups ) . "\n";
      # print "##e " . Dumper( \@lpars_graph ) . "\n";
      # print "1014 \$k $k\n";
      # next;
      # call graph command generation, if any VMs have been selected
      if ( $k > 0 ) {
        graph_it( $groups_name[$i] );
        $processed_groups{ $groups_name[$i] } = 1;
      }
    }
  }
  return 0;
}    ## sub process_hyperv_custom_groups

sub process_esxi_custom_groups {
  my %processed_groups;

  # my @menu; # should be global
  read_menu( \@menu );

  # print "1149 menu.txt @menu\n";
  # S:cluster_ClusterOL:10.22.111.13:CPUpool-pool:CPU pool:/lpar2rrd-cgi/detail.sh?host=10.22.111.4&server=10.22.111.13&lpar=pool&item=pool&entitle=0&gui=1&none=none::1592517780:V:
  my @matches = grep { /^S:/ && /CPUpool-pool/ && /:V:/ } @menu;

  # print "1152 @matches\n";

  for my $i ( 0 .. $#groups_name ) {

    # print "1155 \$i $i \$groups_type $groups_type[$i] \$processed_groups $groups_name[$i] ".$processed_groups{ $groups_name[$i] }." \n";
    if ( $groups_type[$i] =~ m/ESXI/ && !exists( $processed_groups{ $groups_name[$i] } ) ) {
      @lpars_graph        = "";
      @lpars_graph_name   = "";
      @lpars_graph_server = "";
      @lpars_graph_type   = "";

      # position in @lpars_graph* table
      my $k = 0;

      for my $j ( 0 .. $#groups_name ) {

        # print "1166 \$i $i \$j $j \$groups_type $groups_type[$j] \$groups_name $groups_name[$i] $groups_name[$j] \n";
        if ( $groups_type[$j] =~ m/ESXI/ && $groups_name[$i] eq $groups_name[$j] ) {
          my $domain_mask = $groups_server[$j];
          my $vm_mask     = $groups_lpar[$j];

          # print "1170 \$domain_mask $domain_mask \$vm_mask $vm_mask\n";
          # next;
          # filter menu lines
          foreach (@matches) {

            # (undef,my $domain_label,my $hyp_server,my $vm_uuid, my $vm_label,undef, my $hyp_cluster,undef) = split ":",$_;
            ( undef, my $cluster_name, my $server, undef, undef, my $q_string, undef ) = split ":", $_;

            if ( $server =~ m/^$vm_mask$/ ) {
              ( undef, my $host ) = split( "host=", $q_string );
              ( $host, undef ) = split( "\&", $host );
              my $filepath = "$wrkdir/$server/$host/pool.rrm";

              # print "1182 ## custom.pl ESXI DEBUG add to lpars_graph* at $j\n\t$filepath\t$groups_type[$i]\n";

              # add to the @lpars_graph* table
              $lpars_graph[$k]      = $filepath;
              $lpars_graph_name[$k] = $server;

              # $lpars_graph_server[$k] = $domain_label;
              $lpars_graph_server[$k] = "ESXI";             #$hyp_server;
              $lpars_graph_type[$k]   = $groups_type[$i];
              $k++;
            }
          }
        }
      }

      # print "##d " . Dumper( \%processed_groups ) . "\n";
      # print "##e " . Dumper( \@lpars_graph ) . "\n";
      # print "1014 \$k $k\n";
      # next;
      # call graph command generation, if any item has been selected
      if ( $k > 0 ) {

        # print "1202 graph_it( $groups_name[$i], $groups_type[$i] )\n";
        graph_it( $groups_name[$i] );
        $processed_groups{ $groups_name[$i] } = 1;
      }
    }
  }
  return 0;
}    ## sub process_esxi_custom_groups

sub process_linux_custom_groups {
  my %processed_groups;

  # my @menu; # should be global
  read_menu( \@menu );

  # print "1075 menu.txt @menu\n";
  # L:no_hmc:Linux:pahampl:pahampl [muj]:/lpar2rrd-cgi/detail.sh?host=no_hmc&server=Linux--unknown&lpar=pahampl&item=lpar&entitle=0&gui=1&none=none:::P:M

  my @matches = grep {/^L:no_hmc:Linux:/} @menu;

  # print "1079 @matches\n";

  for my $i ( 0 .. $#groups_name ) {

    # print "1082 \$i $i \$groups_type $groups_type[$i] \$processed_groups $groups_name[$i] ".$processed_groups{ $groups_name[$i] }." \n";
    if ( $groups_type[$i] =~ m/LINUX/ && !exists( $processed_groups{ $groups_name[$i] } ) ) {
      @lpars_graph        = "";
      @lpars_graph_name   = "";
      @lpars_graph_server = "";
      @lpars_graph_type   = "";

      # position in @lpars_graph* table
      my $k = 0;

      for my $j ( 0 .. $#groups_name ) {

        # print "1093 \$i $i \$j $j \$groups_type $groups_type[$j] \$groups_name $groups_name[$i] $groups_name[$j] \n";
        if ( $groups_type[$j] =~ m/LINUX/ && $groups_name[$i] eq $groups_name[$j] ) {
          my $domain_mask = $groups_server[$j];
          my $vm_mask     = $groups_lpar[$j];

          # print "1097 \$domain_mask $domain_mask \$vm_mask $vm_mask\n";
          # next;
          # filter LINUX menu lines
          foreach (@matches) {

            # (undef,my $domain_label,my $hyp_server,my $vm_uuid, my $vm_label,undef, my $hyp_cluster,undef) = split ":",$_;
            ( undef, my $no_hmc, my $Linux, my $linux_name, my $linux_name_with_alias, undef ) = split ":", $_;

            if ( $linux_name =~ m/^$vm_mask$/ ) {

              my $vm_filepath = "$wrkdir/Linux/no_hmc/$linux_name";

              # print "1108 ## custom.pl Linux DEBUG add to lpars_graph* at $j\n\t$vm_filepath\t$groups_type[$i]\n";

              # add the VM to the @lpars_graph* table
              $lpars_graph[$k]      = $vm_filepath;
              $lpars_graph_name[$k] = $linux_name;

              # $lpars_graph_server[$k] = $domain_label;
              $lpars_graph_server[$k] = "Linux";            #$hyp_server;
              $lpars_graph_type[$k]   = $groups_type[$i];
              $k++;
            }
          }
        }
      }

      # print "##d " . Dumper( \%processed_groups ) . "\n";
      # print "##e " . Dumper( \@lpars_graph ) . "\n";
      # print "1014 \$k $k\n";
      # next;
      # call graph command generation, if any VMs have been selected
      if ( $k > 0 ) {

        # print "1128 graph_it( $groups_name[$i], $groups_type[$i] )\n";
        graph_it( $groups_name[$i] );
        $processed_groups{ $groups_name[$i] } = 1;
      }
    }
  }
  return 0;
}    ## sub process_linux_custom_groups

sub process_solaris_zone_custom_groups {
  my $group_type_prev = "";

  # if the flag is set for a group, don't create graphs
  my $unsupported_group_type = 0;
  foreach my $group (@groups) {

    # print STDERR "445 custom.pl G: $group\n";
    my $indx = 0;
    @lpars_graph        = "";
    @lpars_graph_name   = "";
    @lpars_graph_server = "";
    $lpar_graph_indx    = 0;    #must be global
    $group_type_prev    = "";
    my @all_list     = "";
    my @all_list_org = "";
    $unsupported_group_type = 0;

    foreach my $group_act (@groups_name) {
      if ( $group_act !~ m/^$group$/ ) {
        $indx++;
        next;
      }
      if ( !$group_type_prev eq '' && $group_type_prev !~ m/$groups_type[$indx]/ ) {
        print "creating cgraph: " . scalar localtime() . " group mismatch $group_act contains LPAR and POOL directives\n";
        my $indx_prev = $indx;
        $indx_prev--;
        error( "custom : group mismatch $group_act contains LPAR ($groups_lpar[$indx])and POOL ($groups_lpar[$indx]) directives " . __FILE__ . ":" . __LINE__ );
        last;
      }
      $group_type_prev = $groups_type[$indx];

      # skip custom-group types unsupported by this subroutine (e.g., XENVM)
      if ( $groups_type[$indx] !~ m/^(SOLARISZONE|^SOLARISLDOM)/ ) {
        $indx++;
        $unsupported_group_type++;
        next;
      }
      my @server_list = "";

      # goes through all data and put into memory list of all rrm/h $lpar_all_list[] and $pool_all_list[]
      # do it just once!!!
      if ( $search_all_solaris == 0 ) {
        $search_all_solaris++;
        load_all_sol_zones();
      }
      foreach my $server (@server_list_solaris_all) {
        if ( $server =~ m/^$groups_server[$indx]$/ ) {
          my $lpar_prev = "";
          if ( $groups_type[$indx] =~ m/SOLARISZONE/ ) {
            @all_list     = @solaris_zone_list;
            @all_list_org = @solaris_zone_list_org;
          }
          elsif ( $groups_type[$indx] =~ m/SOLARISLDOM/ ) {
            @all_list     = @solaris_ldom_list;
            @all_list_org = @solaris_ldom_list_org;
          }
          my $server_prev    = "";    # dual HMC exclude ...
          my $lpar_line_prev = "";
          my $index_org      = -1;

          #print "@all_list --- @all_list_org\n";
          foreach my $lpar_line_part (@all_list) {
            my $lpar_line     = $wrkdir . $lpar_line_part;
            my $lpar_line_all = $lpar_line;
            if ( $lpar_line =~ m/^$wrkdir\/Solaris\/$server\/.*\/$groups_lpar[$indx]$/ ) {
              $index_org++;
              my $name_full = $lpar_line;

              # basename without direct function
              my $lpar_a = $name_full;
              my @base   = split( /\//, $lpar_a );
              foreach my $m (@base) {
                $lpar_a = $m;    #lpar name, basename from $file
              }

              $name_full =~ s/\/$lpar_a$//;

              # basename without direct function
              my $hmc_a = $name_full;
              @base = split( /\//, $hmc_a );
              foreach my $m (@base) {
                $hmc_a = $m;     #lpar name, basename from $file
              }

              $name_full =~ s/\/$hmc_a$//;

              # basename without direct function
              my $server_a = $name_full;
              @base = split( /\//, $server_a );
              foreach my $m (@base) {
                $server_a = $m;    #lpar name, basename from $file
              }

              #fill_in_lpar_table($indx,$group_type_prev,$server_a,$lpar_a);
              # fill in the array with list of lpars/pools prepared for graphing
              $lpars_graph[$lpar_graph_indx]        = $lpar_line;
              $lpars_graph_name[$lpar_graph_indx]   = $lpar_a;
              $lpars_graph_server[$lpar_graph_indx] = $server_a;
              $lpars_graph_type[$lpar_graph_indx]   = $groups_type[$indx];
              $lpar_graph_indx++;

              $lpar_line_prev = $all_list_org[$index_org];    # full original path
              $lpar_prev      = $lpar_a;
              $server_prev    = $server_a;

            }
          }
        }
      }
      $indx++;
    }
    if ( !$group_type_prev eq '' ) {
      if ($unsupported_group_type) {

        # neither create graphs, nor fail, if the group type isn't supported by this subroutine
        next;
      }
      elsif ( $lpar_graph_indx == 0 ) {

        # nothing has been found
        print "cgraph no found: could not identify any lpar or pool for group: \"$group\"\n";
        error( "custom group: could not identify any lpar or pool for group: \"$group\" " . __FILE__ . ":" . __LINE__ );
      }
      else {
        # print STDERR "77 $group: $lpar_graph_indx\n";
        graph_it($group);
      }
    }
  }
  return 0;
}

sub graph_it {
  my $group    = shift;
  my $type_sam = "m";     # temp
  if ( $type_sam =~ "d" ) {
    draw_graph( $group, "year", "y", "MONTH:1:MONTH:1:MONTH:1:0:%b", $type_sam );
  }
  else {
    draw_graph( $group, "day",   "d", "MINUTE:60:HOUR:2:HOUR:4:0:%H", $type_sam );
    draw_graph( $group, "week",  "w", "HOUR:8:DAY:1:DAY:1:86400:%a",  $type_sam );
    draw_graph( $group, "month", "m", "DAY:1:DAY:2:DAY:2:0:%d",       $type_sam );
    draw_graph( $group, "year",  "y", "MONTH:1:MONTH:1:MONTH:1:0:%b", $type_sam );
  }
  return 0;
}

sub draw_graph {
  my $group           = shift;
  my $text            = shift;
  my $type            = shift;
  my $xgrid           = shift;
  my $type_sam        = shift;
  my $name            = "$webdir/custom/$group/$type";
  my $last_cfg_update = "$tmpdir/cust-group-last-update";

  if ( !-d "$webdir/custom" ) {
    print "mkdir          : custom $webdir/custom\n" if $DEBUG;
    mkdir( "$webdir/custom", 0755 ) || error( "Cannot mkdir $webdir/custom: $!" . __FILE__ . ":" . __LINE__ ) && return 0;
    touch("$webdir/custom");
  }
  if ( !-d "$webdir/custom/$group" ) {
    print "mkdir          : custom $webdir/custom/$group\n" if $DEBUG;
    mkdir( "$webdir/custom/$group", 0755 ) || error( "Cannot mkdir $webdir/custom/$group: $!" . __FILE__ . ":" . __LINE__ ) && return 0;
    touch("$webdir/custom/$group");
  }

  my $cfg_time = 0;
  if ( -f "$last_cfg_update" ) {
    $cfg_time = ( stat("$last_cfg_update") )[9];
  }
  else {
    `touch $last_cfg_update`;    # automatical refresh as cfg_time == 0
  }

  if ( $cfg_update_time > $cfg_time ) {

    # cfg has been changed since last actualization, refresh everything to keep custom page up-to-date
    print "cgraph         : custom graph cfg change, redraw everything\n" if $DEBUG;
    `touch $last_cfg_update`;
    touch("custom:draw_graph $cfg_update_time > $cfg_time");
    $cfg_time = 0;               # this does the job
  }

  # update cmd files every time, LPAR list can be changed (LPM ...)
  # no further is created graphs, just cmds

  # do not update charts if there is not new data in RRD DB
  #if ( $type =~ "y" && -f "$name.png" && $upgrade == 0 ) {
  #  if ( ($act_time - $cfg_time) < $YEAR_REFRESH ) {
  #    print "creating cgraph: " . scalar localtime() . " custom:$group:$type_sam:$type no update\n" if $DEBUG ;
  #    return 0;
  #  }
  #}

  # do not update charts if there is not new data in RRD DB
  #if ( $type =~ "m" && -f "$name.png" && $upgrade == 0 ) {
  #  if ( ($act_time - $cfg_time) < $MONTH_REFRESH ) {
  #    print "creating cgraph: " . scalar localtime() . " custom:$group:$type_sam:$type no update\n" if $DEBUG ;
  #    return 0;
  #  }
  #}

  # do not update charts if there is not new data in RRD DB
  #if ( $type =~ "w" && -f "$name.png" && $upgrade == 0 ) {
  #  if ( ($act_time - $cfg_time) < $WEEK_REFRESH ) {
  #    print "creating cgraph: " . scalar localtime() . " custom:$group:$type_sam:$type no update\n" if $DEBUG ;
  #    return 0;
  #  }
  #}

  # Multiview chart CPU
  print "creating cgraph: " . scalar localtime() . " custom:$group:$type_sam:$type\n" if $DEBUG;

  # print "761 custom.pl creating cgraph: " . scalar localtime() . " custom:$group:$type_sam:$type \$lpars_graph_type[0] $lpars_graph_type[0]\n";
  # print STDERR "761 custom.pl creating cgraph: " . scalar localtime() . " custom:$group:$type_sam:$type \$lpars_graph_type[0] $lpars_graph_type[0]\n";

  # create commands for VMware custom groups
  if ( $lpars_graph_type[0] eq "VM" ) {

    multiview_vims( $group, $name, $type, $type_sam, $act_time, $step_new, $text, $xgrid );

    if ( $type eq "y" ) {
      print "creating cgraph: " . scalar localtime() . " custom cpu VM trend:$group:$type_sam:$type\n" if $DEBUG;
      multiview_cpu_vims_trend( $group, $name, $type, $type_sam, $act_time, $step_new, $text, $xgrid );
    }

    print "creating cgraph: " . scalar localtime() . " custom memory:$group:$type_sam:$type\n" if $DEBUG;
    multiview_vims( $group, $name, $type, $type_sam, $act_time, $step_new, $text, $xgrid, "mem" );

    print "creating cgraph: " . scalar localtime() . " custom disk:$group:$type_sam:$type\n" if $DEBUG;
    multiview_disk( $group, $name, $type, $type_sam, $act_time, $step_new, $text, $xgrid, "disk" );

    print "creating cgraph: " . scalar localtime() . " custom net:$group:$type_sam:$type\n" if $DEBUG;
    multiview_disk( $group, $name, $type, $type_sam, $act_time, $step_new, $text, $xgrid, "net" );

    return 0;
  }
  elsif ( $lpars_graph_type[0] eq 'XENVM' ) {

    # create commands for XenServer custom groups
    #print "custom.pl DEBUG calling multiview_xenvm\n";
    #print "\t$group\t$name\t$type\t$type_sam\t$act_time\t$text\n";
    multiview_xenvm( $group, $name, $type, $type_sam, $act_time, $step_new, $text, $xgrid, 'cpu-percent' );
    multiview_xenvm( $group, $name, $type, $type_sam, $act_time, $step_new, $text, $xgrid, 'cpu-cores' );
    multiview_xenvm( $group, $name, $type, $type_sam, $act_time, $step_new, $text, $xgrid, 'memory-used' );
    multiview_xenvm( $group, $name, $type, $type_sam, $act_time, $step_new, $text, $xgrid, 'memory-free' );
    multiview_xenvm( $group, $name, $type, $type_sam, $act_time, $step_new, $text, $xgrid, 'vbd' );
    multiview_xenvm( $group, $name, $type, $type_sam, $act_time, $step_new, $text, $xgrid, 'vbd-iops' );
    multiview_xenvm( $group, $name, $type, $type_sam, $act_time, $step_new, $text, $xgrid, 'vbd-latency' );
    multiview_xenvm( $group, $name, $type, $type_sam, $act_time, $step_new, $text, $xgrid, 'lan' );

    # TODO later add (1) Data, IOPS, Latency, and (2) CPU trend

    return 0;

  }
  elsif ( $lpars_graph_type[0] eq 'NUTANIXVM' ) {
    multiview_nutanixvm( $group, $name, $type, $type_sam, $act_time, $step_new, $text, $xgrid, 'cpu-percent' );
    multiview_nutanixvm( $group, $name, $type, $type_sam, $act_time, $step_new, $text, $xgrid, 'cpu-cores' );
    multiview_nutanixvm( $group, $name, $type, $type_sam, $act_time, $step_new, $text, $xgrid, 'memory-used' );
    multiview_nutanixvm( $group, $name, $type, $type_sam, $act_time, $step_new, $text, $xgrid, 'memory-free' );
    multiview_nutanixvm( $group, $name, $type, $type_sam, $act_time, $step_new, $text, $xgrid, 'vbd' );
    multiview_nutanixvm( $group, $name, $type, $type_sam, $act_time, $step_new, $text, $xgrid, 'vbd-iops' );
    multiview_nutanixvm( $group, $name, $type, $type_sam, $act_time, $step_new, $text, $xgrid, 'vbd-latency' );

    return 0;

  }
  elsif ( $lpars_graph_type[0] eq 'PROXMOXVM' ) {
    multiview_proxmoxvm( $group, $name, $type, $type_sam, $act_time, $step_new, $text, $xgrid, 'cpu-percent' );
    multiview_proxmoxvm( $group, $name, $type, $type_sam, $act_time, $step_new, $text, $xgrid, 'cpu' );
    multiview_proxmoxvm( $group, $name, $type, $type_sam, $act_time, $step_new, $text, $xgrid, 'memory-used' );
    multiview_proxmoxvm( $group, $name, $type, $type_sam, $act_time, $step_new, $text, $xgrid, 'memory-free' );
    multiview_proxmoxvm( $group, $name, $type, $type_sam, $act_time, $step_new, $text, $xgrid, 'data' );
    multiview_proxmoxvm( $group, $name, $type, $type_sam, $act_time, $step_new, $text, $xgrid, 'net' );

    return 0;

  }
  elsif ( $lpars_graph_type[0] eq 'FUSIONCOMPUTEVM' ) {
    multiview_fusioncomputevm( $group, $name, $type, $type_sam, $act_time, $step_new, $text, $xgrid, 'cpu-percent' );
    multiview_fusioncomputevm( $group, $name, $type, $type_sam, $act_time, $step_new, $text, $xgrid, 'cpu' );
    multiview_fusioncomputevm( $group, $name, $type, $type_sam, $act_time, $step_new, $text, $xgrid, 'mem-percent' );
    multiview_fusioncomputevm( $group, $name, $type, $type_sam, $act_time, $step_new, $text, $xgrid, 'mem-used' );
    multiview_fusioncomputevm( $group, $name, $type, $type_sam, $act_time, $step_new, $text, $xgrid, 'mem-free' );
    multiview_fusioncomputevm( $group, $name, $type, $type_sam, $act_time, $step_new, $text, $xgrid, 'data' );
    multiview_fusioncomputevm( $group, $name, $type, $type_sam, $act_time, $step_new, $text, $xgrid, 'disk-ios' );
    multiview_fusioncomputevm( $group, $name, $type, $type_sam, $act_time, $step_new, $text, $xgrid, 'disk-ticks' );
    multiview_fusioncomputevm( $group, $name, $type, $type_sam, $act_time, $step_new, $text, $xgrid, 'net' );

    return 0;

  }
  elsif ( $lpars_graph_type[0] eq 'OPENSHIFTNODE' ) {
    multiview_openshiftnode( $group, $name, $type, $type_sam, $act_time, $step_new, $text, $xgrid, 'cpu-percent' );
    multiview_openshiftnode( $group, $name, $type, $type_sam, $act_time, $step_new, $text, $xgrid, 'cpu' );
    multiview_openshiftnode( $group, $name, $type, $type_sam, $act_time, $step_new, $text, $xgrid, 'memory' );
    multiview_openshiftnode( $group, $name, $type, $type_sam, $act_time, $step_new, $text, $xgrid, 'data' );
    multiview_openshiftnode( $group, $name, $type, $type_sam, $act_time, $step_new, $text, $xgrid, 'iops' );
    multiview_openshiftnode( $group, $name, $type, $type_sam, $act_time, $step_new, $text, $xgrid, 'net' );

    return 0;

  }
  elsif ( $lpars_graph_type[0] eq 'KUBERNETESNODE' ) {
    multiview_kubernetesnode( $group, $name, $type, $type_sam, $act_time, $step_new, $text, $xgrid, 'cpu-percent' );
    multiview_kubernetesnode( $group, $name, $type, $type_sam, $act_time, $step_new, $text, $xgrid, 'cpu' );
    multiview_kubernetesnode( $group, $name, $type, $type_sam, $act_time, $step_new, $text, $xgrid, 'memory' );
    multiview_kubernetesnode( $group, $name, $type, $type_sam, $act_time, $step_new, $text, $xgrid, 'data' );
    multiview_kubernetesnode( $group, $name, $type, $type_sam, $act_time, $step_new, $text, $xgrid, 'iops' );
    multiview_kubernetesnode( $group, $name, $type, $type_sam, $act_time, $step_new, $text, $xgrid, 'net' );

    return 0;

  }
  elsif ( $lpars_graph_type[0] eq 'KUBERNETESNAMESPACE' ) {
    multiview_kubernetesnamespace( $group, $name, $type, $type_sam, $act_time, $step_new, $text, $xgrid, 'cpu' );
    multiview_kubernetesnamespace( $group, $name, $type, $type_sam, $act_time, $step_new, $text, $xgrid, 'memory' );

    return 0;

  }
  elsif ( $lpars_graph_type[0] eq 'OPENSHIFTPROJECT' ) {
    multiview_openshiftnamespace( $group, $name, $type, $type_sam, $act_time, $step_new, $text, $xgrid, 'cpu' );
    multiview_openshiftnamespace( $group, $name, $type, $type_sam, $act_time, $step_new, $text, $xgrid, 'memory' );

    return 0;

  }
  elsif ( $lpars_graph_type[0] eq "OVIRTVM" ) {
    multiview_ovirt( $group, $name, $type, $type_sam, $act_time, $step_new, $text, $xgrid, 'cpu-percent' );
    multiview_ovirt( $group, $name, $type, $type_sam, $act_time, $step_new, $text, $xgrid, 'cpu-core' );
    multiview_ovirt( $group, $name, $type, $type_sam, $act_time, $step_new, $text, $xgrid, 'memory-used' );
    multiview_ovirt( $group, $name, $type, $type_sam, $act_time, $step_new, $text, $xgrid, 'memory-free' );

    # create commands for oVirt custom groups
    # TODO

    return 0;

  }
  elsif ( $lpars_graph_type[0] eq "HYPERVM" ) {
    multiview_hyperv( $group, $name, $type, $type_sam, $act_time, $step_new, $text, $xgrid, 'cpu' );

    return 0;

  }
  elsif ( $lpars_graph_type[0] eq "ESXI" ) {
    multiview_esxi_cpu( $group, $name, $type, $type_sam, $act_time, $step_new, $text, $xgrid, 'cpu' );

    return 0;

  }
  elsif ( $lpars_graph_type[0] eq "LINUX" ) {
    multiview_linux_cpu( $group, $name, $type, $type_sam, $act_time, $step_new, $text, $xgrid, 'cpu' );

    print "creating cgraph: " . scalar localtime() . " custom memory:$group:$type_sam:$type\n" if $DEBUG;
    multiview_linux( $group, $name, $type, $type_sam, $act_time, $step_new, $text, $xgrid, 'mem' );

    print "creating cgraph: " . scalar localtime() . " custom lan:$group:$type_sam:$type\n" if $DEBUG;
    $name = 'san1-os';
    multiview_linux_lan( $group, $name, $type, $type_sam, $act_time, $step_new, $text, $xgrid, 'lan' );

    print "creating cgraph: " . scalar localtime() . " custom san:$group:$type_sam:$type\n" if $DEBUG;
    $name = 'san2-os';
    multiview_linux_lan( $group, $name, $type, $type_sam, $act_time, $step_new, $text, $xgrid, 'san1' );

    return 0;

  }
  elsif ( $lpars_graph_type[0] eq "ORVM" ) {
    multiview_orvm( $group, $name, $type, $type_sam, $act_time, $step_new, $text, $xgrid, 'cpu-cores' );
    multiview_orvm( $group, $name, $type, $type_sam, $act_time, $step_new, $text, $xgrid, 'mem-used' );
    return 0;

  }
  elsif ( $lpars_graph_type[0] =~ /SOLARISZONE|SOLARISLDOM/ ) {
    multiview_solaris_zone( $group, $name, $type, $type_sam, $act_time, $step_new, $text, $xgrid, 'cpu_used' );
    multiview_solaris_zone( $group, $name, $type, $type_sam, $act_time, $step_new, $text, $xgrid, 'phy_mem_us' );
    return 0;
  }

  # create commands for Power custom groups
  multiview( $group, $name, $type, $type_sam, $act_time, $step_new, $text, $xgrid );

  # CPU trend
  if ( $type eq "y" ) {
    print "creating cgraph: " . scalar localtime() . " custom cpu trend:$group:$type_sam:$type\n" if $DEBUG;
    multiview_cpu_trend( $group, $name, $type, $type_sam, $act_time, $step_new, $text, $xgrid );
  }

  print "creating cgraph: " . scalar localtime() . " custom memory:$group:$type_sam:$type\n" if $DEBUG;
  $name .= "-mem";
  my $item = "mem";
  multiview_mem( $group, $name, $type, $type_sam, $act_time, $step_new, $text, $xgrid, $item );

  print "creating cgraph: " . scalar localtime() . " custom memory os :$group:$type_sam:$type\n" if $DEBUG;
  $name .= "-os";
  $item = "os";
  multiview_mem( $group, $name, $type, $type_sam, $act_time, $step_new, $text, $xgrid, $item );

  print "creating cgraph: " . scalar localtime() . " custom IO os :$group:$type_sam:$type\n" if $DEBUG;
  $name =~ s/-mem-os/-san1-os/;
  $item = "san1";
  multiview_san1( $group, $name, $type, $type_sam, $act_time, $step_new, $text, $xgrid, $item );

  print "creating cgraph: " . scalar localtime() . " custom IO os :$group:$type_sam:$type\n" if $DEBUG;
  $name =~ s/-san1-os/-san2-os/;
  $item = "san2";
  multiview_san1( $group, $name, $type, $type_sam, $act_time, $step_new, $text, $xgrid, $item );

  print "creating cgraph: " . scalar localtime() . " custom IO os :$group:$type_sam:$type\n" if $DEBUG;
  $name =~ s/-san2-os/-lan-os/;
  $item = "lan";
  multiview_san1( $group, $name, $type, $type_sam, $act_time, $step_new, $text, $xgrid, $item );

  return 0;
}

sub multiview {
  my $group    = shift;
  my $name     = shift;
  my $type     = shift;
  my $type_sam = shift;
  my $act_time = shift;
  my $step_new = shift;
  my $text     = shift;
  my $xgrid    = shift;
  my $req_time = 0;
  my $comm     = "COMM ";
  $color_indx = 0;                                                  # clear color index
  my $list              = "$webdir/custom/$group/list.txt";
  my $lim               = ".li";
  my $updated           = "";
  my $color_file_change = 0;
  my $file_color_save   = "$basedir/tmp/custom-group-$group.col";
  my $lparno            = 0;
  my $alias_file        = "$basedir/etc/alias.cfg";
  my @alias             = ();                                       # alias LPAR names

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
    $req_time  = $act_time - 31536000;
    $skip_time = $YEAR_REFRESH;
  }

  my $tmp_file = "$tmpdir/custom-group-$group-$type.cmd";

  # do not update weekly/monthly/yearly command files each run
  if ( -f "$tmp_file" ) {
    my $tmp_time = ( stat("$tmp_file") )[9];
    if ( ( $act_time - $tmp_time ) < $skip_time ) {
      print "                        skipped this time : ( $act_time - $tmp_time ) < $skip_time \n";
      return 0;
    }
  }

  # read aliases
  if ( -f "$alias_file" && open( FHC, "< $alias_file" ) ) {
    while (<FHC>) {
      next if $_ !~ /^LPAR:/;
      my $line = $_;
      $line =~ s/^LPAR://;
      chomp $line;
      push @alias, $line;
    }
    close(FHC);
  }

  # print "905 aliases read \@alias @alias\n";

  # open a file with stored colours
  my @color_save = "";
  if ( -f "$file_color_save" ) {
    open( FHC, "< $file_color_save" ) || error( "file cannot be opened : $file_color_save " . __FILE__ . ":" . __LINE__ ) && return 0;
    @color_save = <FHC>;
    close(FHC);
  }

  my $type_edt = 0;
  if ( -f $type_edt_filep ) {
    $type_edt = 1;
  }

  # open file for writing list of lpars
  open( FHL, "> $list" ) || error( "Can't open $list : $!" . __FILE__ . ":" . __LINE__ ) && return 0;

  my $header = "CPU Custom group $group: last $text";

  my $file    = "";
  my $i       = 0;
  my $y       = -1;
  my $lpar    = "";
  my $lparn   = "";
  my $cmd     = "";
  my $cmd_xpo = "";
  my $j       = 0;

  $cmd_xpo = "xport ";
  if ( -f "$basedir/tmp/rrdtool-xport-showtime" ) {
    $cmd_xpo .= " --showtime";
  }
  $cmd_xpo .= " --start now-1$type";
  $cmd_xpo .= " --end now-1$type+1$type";
  $cmd_xpo .= " --step $step_new";
  $cmd_xpo .= " --maxrows 65000";

  my $lim_org = $lim;
  $lim =~ s/\.//;
  $lim =~ s/i/l/;

  $cmd .= "graph \\\"$name.png\\\"";
  $cmd .= " --title \\\"$header\\\"";
  $cmd .= " --start now-1$type";
  $cmd .= " --end now-1$type+1$type";
  $cmd .= " --imgformat PNG";
  $cmd .= " $disable_rrdtool_tag_agg";
  $cmd .= " --slope-mode";
  $cmd .= " --width=400";
  $cmd .= " --height=150";
  $cmd .= " --step=$step_new";
  $cmd .= " --lower-limit=0.00";
  $cmd .= " --color=BACK#$pic_col";
  $cmd .= " --color=SHADEA#$pic_col";
  $cmd .= " --color=SHADEB#$pic_col";
  $cmd .= " --color=CANVAS#$pic_col";
  $cmd .= " --alt-autoscale-max";
  $cmd .= " --upper-limit=0.1";
  $cmd .= " --vertical-label=\\\"CPU cores\\\"";
  $cmd .= " --units-exponent=1.00";
  $cmd .= " --alt-y-grid";
  $cmd .= " --x-grid=$xgrid";
  $cmd .= " COMMENT:\\\"Utilization in CPU cores                       \\l\\\"";

  if ( $lpars_graph_type[0] =~ /POOL/ ) {
    $cmd .= " COMMENT:\\\"  Server                       Pool       Max pool     avrg     max\\l\\\"";
  }
  else {
    $cmd .= " COMMENT:\\\"  Server                       LPAR                  Entitled   avrg      max\\l\\\"";
  }

  my $gtype     = "AREA";
  my $index     = 0;
  my $sh_pools  = 0;        # identificator of shared pool
  my $pool_indx = 0;

  my @lpars_graph_local = @lpars_graph;

  my $summ_shp = "";        # summ averages as vdef values- not yet we'll see
  my $summ_cur = "";
  my $summ_v;               # summ averages as vdef values
  my %uniq_files;
  my $newest_file_timestamp = 0;

  # print "2361 \@lpars_graph_local @lpars_graph_local\n";
  # do not sort it HERE!! there is several arrays, sorting lpars_graph is not enough!!! --PH
  foreach my $file (@lpars_graph_local) {
    if ( $file eq '' ) {
      $index++;
      next;    #some trash
    }

    if ( $file !~ m/\.rr[m,h,d]$/ ) {

      # if pool then translate back to full path rrm
      if ( $lpars_graph_type[$index] =~ /POOL/ ) {

        # print "2373 \$file $file -.-.-.-.-.-.-.-.-.-\n";
        #        if ( $file =~ m/\/CPU pool$/ ) {    # do not graph it TODO develop new group type POWER for these pools - pool.rrm
        #          $index++;
        #          next;
        #        }

        # translate default pool
        if ( $file =~ m/\/all_pools$/ || $file =~ m/\/CPU pool$/ ) {
          $file =~ s/\/all_pools$/\/pool/;
          $file =~ s/\/CPU pool$/\/pool/;
        }
        else {    # shared pools
                  # translate shared pool names
                  # basename without direct function
          my $sh_pool_in = $file;
          my @link_base  = split( /\//, $sh_pool_in );
          foreach my $m (@link_base) {
            $sh_pool_in = $m;
          }

          #$file =~ s/\/$sh_pool_in$//;    # dirname
          $file = dirname $file;

          #$sh_pool_in =~ s/^SharedPool//; #--> must be commented out otherwise do not work cust groups names like SharedPool02 etc, fixed in 5.01-2

          # open available pool mapping file, the most actual one
          my @map             = "";
          my $map_file_final  = "";
          my $map_file_tstamp = 0;

          my $file_space = dirname($file);
          if ( $file =~ m/ / ) {    # workaround for server name with a space inside, nothing else works, grrr
                                    #$file_space = "\"".$file."\"";
            $file_space =~ s/ /\\ /g;
          }

          my $file_dirname = dirname($file);
          foreach my $map_file (<$file_space/*/cpu-pools-mapping.txt>) {

            # print "2402 \$map_file $map_file - - - - - - - - - - \n";
            if ( !-s "$map_file" ) {
              next;    # ignore emty files
            }
            my $tstamp = ( stat("$map_file") )[9];
            if ( $tstamp > $map_file_tstamp ) {
              $map_file_tstamp = $tstamp;
              $map_file_final  = $map_file;
            }
          }
          if ( $map_file_tstamp > 0 ) {
            open( FHP, "< $map_file_final" ) || error( "Can't open $map_file_final : $!" . __FILE__ . ":" . __LINE__ ) && next;
            @map = <FHP>;
            close(FHP);
          }

          my $found    = 0;
          my $map_rows = 0;
          foreach my $line (@map) {
            chomp($line);
            $map_rows++;

            # print "2422 \$map_rows $map_rows \$line $line \$map_file_final $map_file_final \@map @map \$sh_pool_in $sh_pool_in  ------------\n";
            if ( $line !~ m/^[0-9].*,/ ) {

              #something wrong , ignoring
              next;
            }
            ( my $pool_indx_new, my $pool_name_new ) = split( /,/, $line );

            #            if ( $pool_name_new =~ m/^$sh_pool_in$/ ) {
            if ( $pool_name_new eq $sh_pool_in ) {
              $file .= "/SharedPool" . $pool_indx_new;
              $found++;
              last;
            }
          }
          if ( $found == 0 ) {
            if ( $map_rows > 0 ) {
              print "cgraph error 1 : could not found name for shared pool : $file/SharedPool$sh_pool_in\n";

              # no error logging
              #error ("custom 1: could not found name for shared pool : $file/SharedPool$sh_pool_in ".__FILE__.":".__LINE__);
              next;
            }
            else {
              print "cgraph error 1 : Pool mapping table is either empty or does not exist : $map_file_final\n";
              error( "custom 1: Pool mapping table is either empty or does not exist : $map_file_final " . __FILE__ . ":" . __LINE__ );
              next;
            }
          }
        }
      }

      my $file_org = $file;
      $file .= ".rrm";
      if ( !-f $file ) {
        $file = $file_org;
        $file =~ s/\.rrm$/\.rrh/;

        #$file .= ".rrh";
      }
    }
    if ( "$type" =~ "d" ) {
      my $file_org = $file;
      if ( $file !~ m/\.rr[m,d]$/ ) {
        $file .= ".rrd";
        if ( !-f $file ) {
          $file = $file_org;
          $file =~ s/\.rrd$/\.rrm/;
          $file =~ s/\.rrh$/\.rrm/;

          #$file .= ".rrm";
        }
      }
    }

    if ( !-f $file ) {
      $index++;
      next;
    }

    # avoid old lpars which do not exist in the period
    # --> no, no, it mus be done in LPM_easy otherwise it exclude even live data (when old HMC is listed here)
    #my $rrd_upd_time = (stat("$file"))[9];
    #if ( $rrd_upd_time < $req_time ) {
    #  $index++;
    #  next;
    #}

    # add spaces to lpar name to have 25 chars total (for formating graph legend)
    $lpar = $lpars_graph_server[$index];

    # add alias to lpar name if exists
    my @choice = grep {/^$lpars_graph_name[$index]:/} @alias;

    # print "1121 \$lpar $lpars_graph_name[$index] \@choice @choice\n";
    if ( scalar @choice > 1 ) {
      error( "LPAR $lpars_graph_name[$index] has more aliases @choice " . __FILE__ . ":" . __LINE__ );
    }
    my $my_alias = "";
    if ( defined $choice[0] && $choice[0] ne "" ) {
      $choice[0] =~ s/\\//g;                            # if any colon is backslashed
      $choice[0] =~ s/^$lpars_graph_name[$index]://;    # only alias
      if ($test_legend) {
        $choice[0] = substr( $choice[0], 1, $max_alias_length );
      }
      $my_alias = "[" . "$choice[0]" . "]";
    }

    my $lpar_proc = "$lpar $delimiter " . "$lpars_graph_name[$index]$my_alias";    # for html legend
    $lpar_proc =~ s/%/%%/g;
    $lpar_proc =~ s/:/\\:/g;
    $lpar_proc =~ s/\&\&1/\//g;

    $lpar =~ s/\&\&1/\//g;
    for ( my $k = length($lpar); $k < 25; $k++ ) {
      $lpar .= " ";
    }
    $lpar .= "   ";
    $lpar .= $lpars_graph_name[$index] . $my_alias;
    $lpar =~ s/\&\&1/\//g;

    # to keep same count of characters
    $lpar =~ s/\\:/:/g;
    $lpar = sprintf( "%-50s", $lpar );
    $lpar =~ s/:/\\:/g;
    if ( exists $uniq_files{"$file"} ) {    # check duplicities
      $index++;
      next;
    }
    $uniq_files{"$file"} = 1;
    $lparn .= " ";
    print FHL "$file\n";

    #print "11 $file $rrd_upd_time $req_time $act_time\n" if ( $DEBUG == 1);

    if ( $type =~ "d" ) {
      RRDp::cmd qq(last "$file");
      my $last_tt = RRDp::read;
      chomp($$last_tt);
      $newest_file_timestamp = $$last_tt if $$last_tt > $newest_file_timestamp;
    }

    # $file =~ s/:/\\:/g;  # must be in LPM_easy
    my $file_legend = $file;
    $file_legend =~ s/%/%%/g;
    $file_legend =~ s/:/\\:/g;

    # preparing file name for multi hmc LPM_easy
    # should be like: my $file_pth = "$wrkdir/$server/*/$lpar.rr$type_sam";
    my $file_pth = basename($file);
    my $dir_pth  = dirname($file);
    $dir_pth  = dirname($dir_pth);
    $file_pth = "$dir_pth/*/$file_pth";

    # Exclude items (lpars/pool) if there is no data for last year for all HMCs
    if ( LPM_easy_exclude( $file_pth, $act_time - 31622400 ) == 0 ) {
      $index++;
      next;    # there is not updated rrd file for last year, skip that item
    }

    if ( ( length($lpar_v) + 1 ) == length($comm) && length($lparn) == length($comm) ) {
      copy_source_org( $webdir, $tmpdir, $basedir, $lim_org, $lim, $group );
      last;
    }

    # Found out stored color index to keep same color for the volume across all graphs
    my $file_color = $file;
    $file_color =~ s/\.r..$//;
    $file_color =~ s/\\//g;
    $file_color =~ s/:/===========doublecoma=========/g;
    my $color_indx_found = -1;
    $color_indx = 0;
    foreach my $line_col (@color_save) {
      chomp($line_col);
      if ( $line_col eq '' || $line_col !~ m/ : / ) {
        next;
      }
      $color_indx++;
      ( my $color_indx_found_act, my $volume_name_save ) = split( / : /, $line_col );

      # do not use here $volume_name_save '' as this does not work when volume id is zero!
      if ( $volume_name_save =~ m/^$file_color$/ ) {
        $color_indx_found = $color_indx_found_act;
        $color_indx       = $color_indx_found;
        last;
      }
    }
    if ( $color_indx_found == -1 ) {
      $color_file_change = 1;
      $color_save[$color_indx] = $color_indx . " : " . $file_color;
    }
    while ( $color_indx > $color_max ) {
      $color_indx = $color_indx - $color_max;
    }

    # end color

    if ( $type_edt == 0 && $lparno == 4 ) {
      copy_source_org( $webdir, $tmpdir, $basedir, $lim_org, $lim, $group );
      last;
    }
    $lparno++;

    # bulid RRDTool cmd
    if ( $lpars_graph_type[$index] =~ /LPAR/ ) {

      my ( $result_cmd, $capped_cycles, $uncapped_cycles, $entitled_cycles, $curr_proc_units ) = LPM_easy( $file_pth, $i, $req_time, "capped_cycles", "uncapped_cycles", "entitled_cycles", "curr_proc_units" );

      $cmd .= $result_cmd;
      $cmd .= " CDEF:cap${i}=$capped_cycles";
      $cmd .= " CDEF:uncap${i}=$uncapped_cycles";
      $cmd .= " CDEF:ent${i}=$entitled_cycles";
      $cmd .= " CDEF:cur${i}=$curr_proc_units";
      $cmd .= " CDEF:cur_num${i}=cur${i},UN,0,cur${i},IF";

      $cmd .= " CDEF:tot${i}=cap${i},uncap${i},+";
      $cmd .= " CDEF:util${i}=tot${i},ent${i},/,$cpu_max_filter,GT,UNKN,tot${i},ent${i},/,IF";
      $cmd .= " CDEF:utiltotu${i}=util${i},cur${i},*";
      $cmd .= " CDEF:utiltot${i}=utiltotu${i},UN,0,utiltotu${i},IF,100,*,0.5,+,FLOOR,100,/";
      $cmd .= " $gtype:utiltot${i}$color[$color_indx]:\\\"$lpar\\\"";
      $cmd .= " PRINT:utiltot${i}:AVERAGE:\\\"%5.2lf $delimiter multiview-lpar $delimiter $lpar_proc\\\"";    # for html legend

      $cmd_xpo .= $result_cmd;
      $cmd_xpo .= " CDEF:cap${i}=$capped_cycles";
      $cmd_xpo .= " CDEF:uncap${i}=$uncapped_cycles";
      $cmd_xpo .= " CDEF:ent${i}=$entitled_cycles";
      $cmd_xpo .= " CDEF:cur${i}=$curr_proc_units";

      $cmd_xpo .= " \\\"CDEF:tot${i}=cap${i},uncap${i},+\\\"";
      $cmd_xpo .= " \\\"CDEF:util${i}=tot${i},ent${i},/\\\"";
      $cmd_xpo .= " \\\"CDEF:utiltotu${i}=util${i},cur${i},*\\\"";
      $cmd_xpo .= " \\\"CDEF:utiltot${i}=utiltotu${i},UN,0,utiltotu${i},IF\\\"";
      $cmd_xpo .= " \\\"XPORT:utiltot${i}:$lpar\\\"";

      if ( $i == 0 ) {
        $cmd .= " CDEF:tot_cur${i}=cur${i}";
      }
      else {
        $cmd .= " CDEF:pom${i}=tot_cur${y},UN,0,tot_cur${y},IF,cur${i},UN,0,cur${i},IF,+";
        $cmd .= " CDEF:tot_cur${i}=tot_cur${y},UN,cur${i},UN,UNKN,pom${i},IF,pom${i},IF";
      }
      $summ_cur = 1;
    }
    else {
      # POOLs
      $lpar     = substr( $lpar, 0, 35 );
      $sh_pools = 1;
      if ( $file =~ /SharedPool[0-9]/ ) {

        # Shared pools 1 - X + even DefaultPool (ID 0) works here

        my ( $result_cmd, $total_pool_cycles, $utilized_pool_cyc, $max_pool_units ) = LPM_easy( $file_pth, $i, $req_time, "total_pool_cycles", "utilized_pool_cyc", "max_pool_units" );

        $cmd .= $result_cmd;
        $cmd .= " CDEF:max_nan${i}=$max_pool_units";
        $cmd .= " CDEF:max${i}=max_nan${i},UN,0,max_nan${i},IF";
        $cmd .= " VDEF:maxv${i}=max${i},MAXIMUM";                  # for html legend
        $cmd .= " CDEF:totcyc${i}=$total_pool_cycles";
        $cmd .= " CDEF:uticyc${i}=$utilized_pool_cyc";

        $cmd .= " CDEF:cpuutil${i}=uticyc${i},totcyc${i},GT,UNKN,uticyc${i},totcyc${i},/,IF";
        $cmd .= " CDEF:utiltotu${i}=cpuutil${i},max${i},*";
        $cmd .= " CDEF:utiltot${i}=utiltotu${i},UN,0,utiltotu${i},IF";

        $cmd_xpo .= " $result_cmd";
        $cmd_xpo .= " CDEF:max_nan${i}=$max_pool_units";
        $cmd_xpo .= " CDEF:max${i}=max_nan${i},UN,0,max_nan${i},IF";
        $cmd_xpo .= " CDEF:totcyc${i}=$total_pool_cycles";
        $cmd_xpo .= " CDEF:uticyc${i}=$utilized_pool_cyc";

        $cmd_xpo .= " \\\"CDEF:cpuutil${i}=uticyc${i},totcyc${i},/\\\"";
        $cmd_xpo .= " \\\"CDEF:utiltotu${i}=cpuutil${i},max${i},*\\\"";
        $cmd_xpo .= " \\\"CDEF:utiltot${i}=utiltotu${i},UN,0,utiltotu${i},IF\\\"";
        $cmd_xpo .= " \\\"XPORT:utiltot${i}:$lpar\\\"";

        # this must be here!!!
        #print "001 $lpar - $lpar_cut\n";
        $cmd .= " $gtype:utiltot${i}$color[$color_indx]:\\\"$lpar    \\\"";
        $cmd .= " GPRINT:max${i}:AVERAGE:\\\"%3.0lf      \\\"";

        $cmd .= " PRINT:utiltot${i}:AVERAGE:\\\"%5.2lf $delimiter multiview-shpool $delimiter $lpar_proc\\\"";    # for html legend
        $cmd .= " PRINT:max${i}:AVERAGE:\\\"%3.0lf $delimiter \\\"";                                              # for html legend
        if ( $i == 0 ) {                                                                                          # prepare line for summ
          $summ_shp = "maxv${i}";
        }
        else {
          $summ_shp .= "," . "maxv${i},+";
        }
      }
      else {

        # pool.rrm
        my ( $result_cmd, $total_pool_cycles, $utilized_pool_cyc, $conf_proc_units, $bor_proc_units ) = LPM_easy( $file_pth, $i, $req_time, "total_pool_cycles", "utilized_pool_cyc", "conf_proc_units", "bor_proc_units" );

        # print "$result_cmd,$total_pool_cycles,$utilized_pool_cyc,$conf_proc_units,$bor_proc_units\n";
        $cmd .= $result_cmd;
        $cmd .= " CDEF:totcyc${i}=$total_pool_cycles";
        $cmd .= " CDEF:uticyc${i}=$utilized_pool_cyc";
        $cmd .= " CDEF:cpu${i}=$conf_proc_units";
        $cmd .= " CDEF:cpubor${i}=$bor_proc_units";

        $cmd .= " CDEF:totcpu_nan${i}=cpu${i},cpubor${i},+";
        $cmd .= " CDEF:totcpu${i}=totcpu_nan${i},UN,0,totcpu_nan${i},IF";
        $cmd .= " VDEF:totcpuv${i}=totcpu${i},MAXIMUM";                                         # for html legend
        $cmd .= " CDEF:cpuutil${i}=uticyc${i},totcyc${i},GT,UNKN,uticyc${i},totcyc${i},/,IF";
        $cmd .= " CDEF:utiltotu${i}=cpuutil${i},totcpu${i},*";
        $cmd .= " CDEF:utiltot${i}=utiltotu${i},UN,0,utiltotu${i},IF";

        $cmd_xpo .= " $result_cmd";
        $cmd_xpo .= " \\\"CDEF:totcyc${i}=$total_pool_cycles\\\"";
        $cmd_xpo .= " \\\"CDEF:uticyc${i}=$utilized_pool_cyc\\\"";
        $cmd_xpo .= " \\\"CDEF:cpu${i}=$conf_proc_units\\\"";
        $cmd_xpo .= " \\\"CDEF:cpubor${i}=$bor_proc_units\\\"";

        $cmd_xpo .= " \\\"CDEF:totcpu${i}=cpu${i},cpubor${i},+\\\"";
        $cmd_xpo .= " \\\"CDEF:cpuutil${i}=uticyc${i},totcyc${i},/\\\"";
        $cmd_xpo .= " \\\"CDEF:utiltotu${i}=cpuutil${i},totcpu${i},*\\\"";
        $cmd_xpo .= " \\\"CDEF:utiltot${i}=utiltotu${i},UN,0,utiltotu${i},IF\\\"";
        $cmd_xpo .= " \\\"XPORT:utiltot${i}:$lpar\\\"";                              # MAX allocated

        $cmd .= " $gtype:utiltot${i}$color[$color_indx]:\\\"$lpar    \\\"";                                       # MAX allocated
        $cmd .= " GPRINT:totcpu${i}:AVERAGE:\\\"%3.0lf      \\\"";
        $cmd .= " PRINT:utiltot${i}:AVERAGE:\\\"%5.2lf $delimiter multiview-shpool $delimiter $lpar_proc\\\"";    # for html legend
        $cmd .= " PRINT:totcpu${i}:AVERAGE:\\\"%3.0lf $delimiter \\\"";                                           # for html legend
        if ( $i == 0 ) {                                                                                          # prepare line for summ
          $summ_shp = "totcpuv${i}";
        }
        else {
          $summ_shp .= "," . "totcpuv${i},+";
        }
      }
    }
    $cmd .= " PRINT:utiltot${i}:AVERAGE:\\\"%5.2lf $delimiter $color[$color_indx] $delimiter $file_legend\\\"";    # for html legend
    $cmd .= " PRINT:utiltot${i}:MAX:\\\"%5.2lf $delimiter\\\"";                                                    # for html legend
    if ( $lpars_graph_type[$index] =~ /LPAR/ ) {
      $cmd .= " PRINT:cur_num${i}:AVERAGE:\\\"%5.2lf $delimiter\\\"";
    }
    $cmd .= " VDEF:utilv${i}=utiltot${i},AVERAGE";

    # put carriage return after each second lpar in the legend
    if ( $j == 1 ) {
      if ( $lpars_graph_type[$index] =~ /LPAR/ ) {
        $cmd .= " GPRINT:cur_num${i}:AVERAGE:\\\"%5.2lf  \\\"";
      }
      $cmd .= " GPRINT:utiltot${i}:AVERAGE:\\\"%5.2lf  \\\"";
      $cmd .= " GPRINT:utiltot${i}:MAX:\\\"%5.2lf \\l\\\"";
      $j = 0;
    }
    else {
      if ( $lpars_graph_type[$index] =~ /LPAR/ ) {
        $cmd .= " GPRINT:cur_num${i}:AVERAGE:\\\"%5.2lf  \\\"";
      }
      $cmd .= " GPRINT:utiltot${i}:AVERAGE:\\\"%5.2lf  \\\"";
      $cmd .= " GPRINT:utiltot${i}:MAX:\\\"%5.2lf \\l\\\"";

      # --> it does not work ideally with newer RRDTOOL (1.2.30 --> it needs to be separated by cariage return here)
      $j++;
    }

    if ( $i == 0 ) {    # prepare line for summ
      $summ_v = "utilv${i},100,*,0.5,-,CEIL,100,/";
    }
    else {
      $summ_v .= "," . "utilv${i},100,*,0.5,-,CEIL,100,/,+";
    }

    $gtype = "STACK";
    $i++;
    $y++;
    $color_indx = ++$color_indx % ( $color_max + 1 );
    $index++;
    if ( !get_lpar_num() && $index > 5 ) {
      last;
    }

  }

  #  $cmd_sum =~ s/\\"/"/g;
  $cmd_xpo =~ s/\\"/"/g;

  close(FHL);
  my $FH;

  # store XPORT for future usage in Hist reports (detail-graph-cgi.pl)
  if ( "$type" =~ "d" ) {

    # only daily one
    my $tmp_file_xpo = "$tmpdir/custom-group-$group-$type-xpo.cmd";
    open( FH, "> $tmp_file_xpo" ) || error( "Can't open $tmp_file_xpo : $!" . __FILE__ . ":" . __LINE__ ) && return 0;
    print FH "$cmd_xpo\n";
    close(FH);
  }

  # print out total value only for shared pools
  if ( $summ_shp ne "" ) {
    $cmd .= " CDEF:recv_shp=utiltot0,POP,$summ_shp";                                                        # for run time summ
    $cmd .= " PRINT:recv_shp:AVERAGE:\\\"%5.0lf $delimiter Total max pool units                   \\\"";    # for html legend
    $cmd .= " LINE2:recv_shp#000000:\\\"Total max pool units                   \\\"";
    $cmd .= " GPRINT:recv_shp:AVERAGE:\\\"%3.0lf\\l\\\"";
  }

  # lpar Total max entitled processor cores
  if ( $summ_cur eq "1" ) {
    $cmd .= " PRINT:tot_cur${y}:MAX:\\\"%5.2lf $delimiter Total entitled processor cores                    \\\"";    # for html legend
    $cmd .= " LINE2:tot_cur${y}#000000:\\\"Total entitled processor cores                     \\\"";
    $cmd .= " GPRINT:tot_cur${y}:MAX:\\\"%3.2lf\\l\\\"";
  }
  if ($summ_v) {                                                                                                      # $summ_v is uninitialized in some case
    $cmd .= " CDEF:recv_v=utiltot0,POP,$summ_v";                                                                      # for run time summ - trick with vdef values
  }
  $cmd .= " GPRINT:recv_v:AVERAGE:\\\"  Total average                                                 %5.2lf\\\"";
  $cmd .= " PRINT:recv_v:AVERAGE:\\\"%5.2lf $delimiter Total average\\\"";                                            # for html legend
  $cmd .= " COMMENT:\\\"\\l\\\"";

  if ( $newest_file_timestamp > 0 ) {
    my $l = localtime($newest_file_timestamp);

    # following must be for RRD 1.2+
    $l =~ s/:/\\:/g;
    $updated = " COMMENT:\\\"  Updated\\\: $l \\\"";
  }

  $cmd .= " $updated";

  if ( "$type" =~ "d" ) {
    if ( $j == 1 ) {
      $cmd .= " COMMENT:\\\" \\l\\\"";
    }
  }
  $cmd .= " HRULE:0#000000";

  # $cmd .= " VRULE:0#000000";  --> it is causing sigsegv on linuxeS
  $cmd =~ s/\\"/"/g;

  open( FH, "> $tmp_file" ) || error( "Can't open $tmp_file : $!" . __FILE__ . ":" . __LINE__ ) && return 0;
  print FH "$cmd\n";
  close(FH);

  if ( !get_lpar_num() ) {
    if ( $index > 4 ) {
      if ( !-f "$webdir/custom/$group/$lim" ) {
        copy_source_org( $webdir, $tmpdir, $basedir, $lim_org, $lim, $group );
      }
    }
  }

  # write colors into a file
  if ( $color_file_change == 1 ) {
    open( FHC, "> $file_color_save" ) || error( "file cannot be created :  $file_color_save " . __FILE__ . ":" . __LINE__ ) && return 0;
    foreach my $line_cs (@color_save) {
      chomp($line_cs);    # it must be there, somehow appear there \n ...
      if ( $line_cs eq '' ) {
        next;
      }
      if ( $line_cs =~ m/ : / ) {
        print FHC "$line_cs\n";
      }
    }
    close(FHC);
  }

  # colours

  #
  # do not execute it here
  # execute it in the run time based on cmd stored in $tmp_file
  #

  return 1;
}

sub multiview_mem {
  my $group    = shift;
  my $name     = shift;
  my $type     = shift;
  my $type_sam = shift;
  my $act_time = shift;
  my $step_new = shift;
  my $text     = shift;
  my $xgrid    = shift;
  my $item     = shift;
  my $req_time = 0;
  my $comm     = "COMM ";
  $color_indx = 0;                                                        # clear color index
  my $list              = "$webdir/custom/$group/list.txt";
  my $lim               = ".li";
  my $color_file_change = 0;
  my $file_color_save   = "$basedir/tmp/custom-group-$group-$item.col";
  my $lparno            = 0;
  my $alias_file        = "$basedir/etc/alias.cfg";
  my @alias             = ();                                             # alias LPAR names

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
    $req_time  = $act_time - 31536000;
    $skip_time = $YEAR_REFRESH;
  }

  my $tmp_file = "$tmpdir/custom-group-mem-$group-$type.cmd";
  if ( $name =~ m/-os$/ ) {
    $tmp_file = "$tmpdir/custom-group-mem-os-$group-$type.cmd";
  }

  # do not update weekly/monthly/yearly command files each run
  if ( -f "$tmp_file" ) {
    my $tmp_time = ( stat("$tmp_file") )[9];
    if ( ( $act_time - $tmp_time ) < $skip_time ) {
      print "                        skipped this time : ( $act_time - $tmp_time ) < $skip_time \n";
      return 0;
    }
  }

  # read aliases
  if ( -f "$alias_file" && open( FHC, "< $alias_file" ) ) {
    while (<FHC>) {
      next if $_ !~ /^LPAR:/;
      my $line = $_;
      $line =~ s/^LPAR://;
      chomp $line;
      push @alias, $line;
    }
    close(FHC);
  }

  # open a file with stored colours
  my @color_save = "";
  if ( -f "$file_color_save" ) {
    open( FHC, "< $file_color_save" ) || error( "file cannot be opened : $file_color_save " . __FILE__ . ":" . __LINE__ ) && return 0;
    @color_save = <FHC>;
    close(FHC);
  }

  my $type_edt = 0;
  if ( -f $type_edt_filep ) {
    $type_edt = 1;
  }

  # open file for writing list of lpars
  open( FHL, ">> $list" ) || error( "Can't open $list : $!" . __FILE__ . ":" . __LINE__ ) && return 0;

  my $header = "MEM Alloc Custom group $group: last $text";
  $header = "MEM Custom group OS $group: last $text" if $item eq "os";

  my $file  = "";
  my $i     = 0;
  my $lpar  = "";
  my $lparn = "";
  my $cmd   = "";
  my $j     = 0;

  my $index = 0;

  my $lim_org = $lim;
  $lim =~ s/\.//;
  $lim =~ s/i/l/;

  $cmd .= "graph \\\"$name.png\\\"";
  $cmd .= " --title \\\"$header\\\"";
  $cmd .= " --start now-1$type";
  $cmd .= " --end now-1$type+1$type";
  $cmd .= " --imgformat PNG";
  $cmd .= " $disable_rrdtool_tag_agg";
  $cmd .= " --slope-mode";
  $cmd .= " --width=400";
  $cmd .= " --height=150";
  $cmd .= " --step=$step_new";
  $cmd .= " --lower-limit=0.00";
  $cmd .= " --color=BACK#$pic_col";
  $cmd .= " --color=SHADEA#$pic_col";
  $cmd .= " --color=SHADEB#$pic_col";
  $cmd .= " --color=CANVAS#$pic_col";
  $cmd .= " --alt-autoscale-max";
  $cmd .= " --upper-limit=0.1";
  $cmd .= " --vertical-label=\\\"GB\\\"";
  $cmd .= " --units-exponent=1.00";
  $cmd .= " --alt-y-grid";
  $cmd .= " --x-grid=$xgrid";

  if ( $name =~ m/-os$/ ) {
    $cmd .= " COMMENT:\\\"Used memory in GBytes                          \\l\\\"";
  }
  else {
    $cmd .= " COMMENT:\\\"Allocation in GBytes                          \\l\\\"";
  }
  if ( $lpars_graph_type[$index] =~ /POOL/ ) {
    $cmd .= " COMMENT:\\\"  Server                       Pool        Max pool     avrg     max\\l\\\"";
  }
  else {
    $cmd .= " COMMENT:\\\"  Server                       LPAR                     avrg     max\\l\\\"";
  }

  my $gtype             = "AREA";
  my $sh_pools          = 0;              # identificator of shared pool
  my @lpars_graph_local = @lpars_graph;
  my $updated           = " ";

  my $summ_r;
  my $summ_t = "";

  my %uniq_files;
  my $newest_file_timestamp = 0;

  # do not sort it HERE!! there is several arrays, sorting lpars_graph is not enough!!! --PH
  foreach my $file_tmp (@lpars_graph_local) {
    my $file = $file_tmp;    # must be here to allocate new space and do not make changes in @lpars_graph

    if ( $file eq '' ) {
      $index++;
      next;                  #some trash
    }

    # note there is already no suffix, but do below to be sure
    $file =~ s/\.rrm$//;
    $file =~ s/\.rrd$//;
    $file =~ s/\.rrh$//;
    $file =~ s/all_pools$/pool/;
    $file =~ s/CPU pool$/pool/;

    if ( $lpars_graph_type[$index] =~ /POOL/ && $name =~ m/-os$/ ) {
      return 1;              # no OS pool based graphs
    }

    # pool names are already translated here!!!
    if ( $lpars_graph_type[$index] =~ /POOL/ && $file !~ m/\/pool$/ ) {
      $index++;
      next;                  # include only real lpars
    }

    if ( $file =~ m/\/mem$/ ) {
      $index++;
      next;                  # include only real lpars
    }

    if ( $lpars_graph_type[$index] =~ /LPAR/ ) {
      if ( $name =~ m/-os$/ ) {

        # OS mem graphs
        # fix for 4.0 OS agent structures!!!
        $file =~ s/$/\/mem\.mmm/;

        if ( !-f $file ) {
          $index++;
          next;
        }
        if ( $file =~ m/\/pool\.r/ || $file =~ m/\/pool$/ ) {

          # exclude pool memory from OS memory
          $index++;
          next;
        }
      }
      else {
        # note there is already no suffix, but do bellow to be sure
        $file =~ s/$/\.rmm/;
        if ( !-f $file ) {
          $file =~ s/\.rmm$/\.rsm/;
          if ( !-f $file ) {
            $index++;
            next;
          }
        }
      }
    }
    else {
      if ( $name =~ m/-os$/ ) {

        # exlude for mem OS agent
        $index++;
        next;
      }

      # conversion to memory db files
      # pools : just default pool ann mem allocation
      $file =~ s/\/pool$/\/mem/;
      $file =~ s/$/\.rrm/;

      if ( !-f $file ) {
        $file =~ s/\.rrm/\.rrh/;
        if ( !-f $file ) {
          $index++;
          next;
        }
      }
    }

    # avoid old lpars which do not exist in the period
    # --> no, no, it mus be done in LPM_easy otherwise it exclude even live data (when old HMC is listed here)
    #my $rrd_upd_time = (stat("$file"))[9];
    #if ( $rrd_upd_time < $req_time ) {
    #  $index++;
    #  next;
    #}

    # add spaces to lpar name to have 25 chars total (for formating graph legend)
    $lpar = $lpars_graph_server[$index];

    # add alias to lpar name if exists
    my @choice = grep {/^$lpars_graph_name[$index]:/} @alias;

    # print "1121 \$lpar $lpars_graph_name[$index] \@choice @choice\n";
    if ( scalar @choice > 1 ) {
      error( "LPAR $lpars_graph_name[$index] has more aliases @choice " . __FILE__ . ":" . __LINE__ );
    }
    my $my_alias = "";
    if ( defined $choice[0] && $choice[0] ne "" ) {
      $choice[0] =~ s/\\//g;                            # if any colon is backslashed
      $choice[0] =~ s/^$lpars_graph_name[$index]://;    # only alias
      if ($test_legend) {
        $choice[0] = substr( $choice[0], 1, $max_alias_length );
      }
      $my_alias = "[" . "$choice[0]" . "]";
    }

    my $lpar_proc = "$lpar $delimiter " . "$lpars_graph_name[$index]$my_alias";    # for html legend

    $lpar_proc =~ s/%/%%/g;
    $lpar_proc =~ s/:/\\:/g;
    $lpar_proc =~ s/\&\&1/\//g;

    $lpar =~ s/\&\&1/\//g;
    for ( my $k = length($lpar); $k < 25; $k++ ) {
      $lpar .= " ";
    }
    $lpar .= "   ";
    $lpar .= $lpars_graph_name[$index] . $my_alias;
    $lpar =~ s/\&\&1/\//g;

    # to keep same count of characters
    $lpar =~ s/\\:/:/g;
    $lpar = sprintf( "%-50s", $lpar );
    $lpar =~ s/:/\\:/g;

    for ( my $k = length($lpar); $k < 50; $k++ ) {
      $lpar .= " ";
    }

    if ( exists $uniq_files{"$file"} ) {    # check duplicities
      $index++;
      next;
    }
    $uniq_files{"$file"} = 1;
    $lparn .= " ";
    print FHL "$file\n";

    #print "11 $file $rrd_upd_time $req_time $act_time\n" if ( $DEBUG == 1);

    if ( $type =~ "d" ) {
      RRDp::cmd qq(last "$file");
      my $last_tt = RRDp::read;
      chomp($$last_tt);
      $newest_file_timestamp = $$last_tt if $$last_tt > $newest_file_timestamp;
    }
    $file =~ s/:/\\:/g;
    my $os_mem = "mem";

    my $file_legend = $file;
    $file_legend =~ s/%/%%/g;

    # preparing file name for multi hmc LPM_easy
    # should be like: my $file_pth = "$wrkdir/$server/*/$lpar.rr$type_sam";
    my $file_pth = basename($file);
    my $dir_pth  = dirname($file);
    $dir_pth  = dirname($dir_pth);
    $file_pth = "$dir_pth/*/$file_pth";

    # Exclude items (lpars/pool) if there is no data for last year for all HMCs
    if ( LPM_easy_exclude( $file_pth, $act_time - 31622400 ) == 0 ) {
      $index++;
      next;    # there is not updated rrd file for last year, skipt that item
    }

    if ( ( length($lpar_v) + 1 ) == length($comm) && length($lparn) == length($comm) ) {
      copy_source_org( $webdir, $tmpdir, $basedir, $lim_org, $lim, $group );
      last;
    }

    # Found out stored color index to keep same color for the volume across all graphs
    my $file_color = $file;
    $file_color =~ s/\.r..$//;
    $file_color =~ s/\\//g;
    $file_color =~ s/:/===========doublecoma=========/g;
    my $color_indx_found = -1;
    $color_indx = 0;
    foreach my $line_col (@color_save) {
      chomp($line_col);
      if ( $line_col eq '' || $line_col !~ m/ : / ) {
        next;
      }
      $color_indx++;
      ( my $color_indx_found_act, my $volume_name_save ) = split( / : /, $line_col );

      # do not use here $volume_name_save '' as this does not work when volume id is zero!
      if ( $volume_name_save =~ m/^$file_color$/ ) {
        $color_indx_found = $color_indx_found_act;
        $color_indx       = $color_indx_found;
        last;
      }
    }
    if ( $color_indx_found == -1 ) {
      $color_file_change = 1;
      $color_save[$color_indx] = $color_indx . " : " . $file_color;
    }
    while ( $color_indx > $color_max ) {
      $color_indx = $color_indx - $color_max;
    }

    # end color

    if ( $type_edt == 0 && $lparno == 4 ) {
      copy_source_org( $webdir, $tmpdir, $basedir, $lim_org, $lim, $group );
      last;
    }
    $lparno++;

    # bulid RRDTool cmd
    if ( $lpars_graph_type[$index] =~ /LPAR/ ) {
      if ( $name =~ m/-os$/ ) {

        # OS memory - agent
        $os_mem = "osmem";
        $cmd .= " DEF:cur${i}=\\\"$file\\\":nuse:AVERAGE";
        $cmd .= " DEF:in_use_clnt${i}=\\\"$file\\\":in_use_clnt:AVERAGE";
        $cmd .= " CDEF:cur_real${i}=cur${i},in_use_clnt${i},-";
        $cmd .= " CDEF:curg${i}=cur_real${i},1048576,/";
      }
      else {
        my ( $result_cmd, $MEM_cur ) = LPM_easy( $file_pth, $i, $req_time, "curr_mem" );

        $cmd .= $result_cmd;
        $cmd .= " CDEF:cur${i}=$MEM_cur";

        #$cmd .= " DEF:cur${i}=\\\"$file\\\":curr_mem:AVERAGE";
        $cmd .= " CDEF:curg${i}=cur${i},1024,/";
      }
      $cmd .= " $gtype:curg${i}$color[$color_indx]:\\\"$lpar\\\"";
    }
    else {
      # POOLs
      # default pool only
      my ( $result_cmd, $MEM_tot, $MEM_free ) = LPM_easy( $file_pth, $i, $req_time, "conf_sys_mem", "curr_avail_mem" );

      $cmd .= $result_cmd;
      $cmd .= " CDEF:tot${i}=$MEM_tot";
      $cmd .= " CDEF:free${i}=$MEM_free";

      #$cmd .= " DEF:tot${i}=\\\"$file\\\":conf_sys_mem:AVERAGE";
      #$cmd .= " DEF:free${i}=\\\"$file\\\":curr_avail_mem:AVERAGE";
      $cmd .= " CDEF:totg${i}=tot${i},1024,/";
      $cmd .= " CDEF:freeg${i}=free${i},1024,/";
      $cmd .= " CDEF:curg${i}=totg${i},freeg${i},-";
      $cmd .= " $gtype:curg${i}$color[$color_indx]:\\\"$lpar\\\"";
    }

    $cmd .= " GPRINT:curg${i}:AVERAGE:\\\"%5.2lf\\\"";
    $cmd .= " GPRINT:curg${i}:MAX:\\\"%5.2lf\\l\\\"";

    $cmd .= " PRINT:curg${i}:AVERAGE:\\\"%5.2lf $delimiter multiview-$os_mem $delimiter $lpar_proc\\\"";        # for html legend
    $cmd .= " PRINT:curg${i}:AVERAGE:\\\"%5.2lf $delimiter $color[$color_indx] $delimiter $file_legend\\\"";    # for html legend
    $cmd .= " PRINT:curg${i}:MAX:\\\"%5.2lf $delimiter\\\"";                                                    # for html legend

    $cmd .= " VDEF:curg_s${i}=curg${i},AVERAGE";
    $cmd .= " CDEF:curg_ss${i}=curg0,POP,curg_s${i},UN,0,curg_s${i},IF";

    if ( $lpars_graph_type[$index] !~ /LPAR/ ) {
      $cmd .= " VDEF:totg_s${i}=totg${i},AVERAGE";
      $cmd .= " CDEF:totg_ss${i}=totg0,POP,totg_s${i},UN,0,totg_s${i},IF";
    }

    if ( $i == 0 ) {                                                                                            # prepare line for summ
      $summ_r = "curg_ss${i}";
      $summ_t = "totg_ss${i}" if ( $lpars_graph_type[$index] !~ /LPAR/ );
    }
    else {
      $summ_r .= "," . "curg_ss${i},+";
      $summ_t .= "," . "totg_ss${i},+" if ( $lpars_graph_type[$index] !~ /LPAR/ );
    }

    $gtype = "STACK";
    $i++;
    $color_indx = ++$color_indx % ( $color_max + 1 );
    $index++;
    if ( !get_lpar_num() && $index == 5 ) {
      last;
    }

  }
  close(FHL);

  if ( $i == 0 && $type =~ m/^d$/ ) {
    if ( $lpars_graph_type[0] !~ /POOL/ && $name !~ m/-os$/ ) {    # $index = 0 on purpose
      error( "creating cgraph: " . scalar localtime() . " custom memory:$group:$type_sam:$type - not identified any source " . __FILE__ . ":" . __LINE__ );
    }
    return 0;                                                      # nothing has been found
  }
  if ( $i == 0 ) {
    print "creating cgraph: " . scalar localtime() . " custom:$group $item-os $type: no any source found, skipping\n";
    return 0;                                                      # nothing has been found
  }

  $cmd .= " CDEF:recv=curg0,POP,$summ_r";                                                                    # for run time summ
  $cmd .= " GPRINT:recv:AVERAGE:\\\"  Total average                                        %5.2lf\\l\\\"";
  $cmd .= " PRINT:recv:AVERAGE:\\\"%5.2lf $delimiter Total average\\\"";                                     # for html legend

  if ( $summ_t ne "" ) {
    $cmd .= " CDEF:sum_m=curg0,POP,$summ_t";                                                                 # for run time summ
    $cmd .= " LINE2:sum_m#000000:\\\"Total available                                    \\\"";
    $cmd .= " GPRINT:sum_m:AVERAGE:\\\"%5.2lf\\l\\\"";
    $cmd .= " PRINT:sum_m:AVERAGE:\\\"%5.2lf $delimiter Total available\\\"";                                # for html legend
  }

  if ( $newest_file_timestamp > 0 ) {
    my $l = localtime($newest_file_timestamp);

    # following must be for RRD 1.2+
    $l =~ s/:/\\:/g;
    $updated = " COMMENT:\\\"  Updated\\\: $l \\\"";
  }

  $cmd .= " $updated";
  $cmd .= " HRULE:0#000000";

  # $cmd .= " VRULE:0#000000";  --> it is causing sigsegv on linuxeS
  $cmd =~ s/\\"/"/g;

  open( FH, "> $tmp_file" ) || error( "Can't open $tmp_file : $!" . __FILE__ . ":" . __LINE__ ) && return 0;
  print FH "$cmd\n";
  close(FH);

  #
  # do not execute it here
  # execute it in the run time based on cmd stored in $tmp_file
  #

  # write colors into a file
  if ( $color_file_change == 1 ) {
    open( FHC, "> $file_color_save" ) || error( "file cannot be created :  $file_color_save " . __FILE__ . ":" . __LINE__ ) && return 0;
    foreach my $line_cs (@color_save) {
      chomp($line_cs);    # it must be there, somehow appear there \n ...
      if ( $line_cs eq '' ) {
        next;
      }
      if ( $line_cs =~ m/ : / ) {
        print FHC "$line_cs\n";
      }
    }
    close(FHC);
  }

  # colours

  return 1;
}

# error handling
sub error {
  my $text     = shift;
  my $act_time = localtime();
  chomp($text);

  print "ERROR          : $text \n";
  print STDERR "$act_time: $text \n";

  return 1;
}

sub touch {
  my $text = shift;

  my $version    = "$ENV{version}";
  my $basedir    = $ENV{INPUTDIR};
  my $new_change = "$tmpdir/$version-run";
  my $DEBUG      = $ENV{DEBUG};

  if ( !-f $new_change ) {
    `touch $new_change`;    # say install_html.sh that there was any change
    if ( $text eq '' ) {
      print "touch          : custom groups $new_change\n" if $DEBUG;
    }
    else {
      print "touch          : custom groups $new_change : $text\n" if $DEBUG;
    }
  }

  return 0;
}

sub isdigit {
  my $digit = shift;

  if ( !defined $digit || $digit eq '' ) {
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

#sub isdigit
#{
#  my $digit = shift;
#
#  if ( $digit eq '' ) { return 0; }
#
#  my $digit_work = $digit;
#  $digit_work =~ s/[0-9]//g;
#  $digit_work =~ s/\.//;
#
#  if (length($digit_work) == 0) {
#    # is a number
#    return 1;
#  }
#  return 0;
#}

sub multiview_san1 {
  my $group    = shift;
  my $name     = shift;
  my $type     = shift;
  my $type_sam = shift;
  my $act_time = shift;
  my $step_new = shift;
  my $text     = shift;
  my $xgrid    = shift;
  my $item     = shift;
  my $req_time = 0;
  my $comm     = "COMM ";
  $color_indx = 0;                                                        # prepare color index
  my $list              = "$webdir/custom/$group/list.txt";
  my $lim               = ".li";
  my $color_file_change = 0;
  my $file_color_save   = "$basedir/tmp/custom-group-$group-$item.col";
  my $lparno            = 0;
  my $alias_file        = "$basedir/etc/alias.cfg";
  my @alias             = ();                                             # alias LPAR names

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
    $req_time  = $act_time - 31536000;
    $skip_time = $YEAR_REFRESH;
  }

  my $tmp_file = "$tmpdir/custom-group-$item-os-$group-$type.cmd";

  # do not update weekly/monthly/yearly command files each run
  if ( -f "$tmp_file" ) {
    my $tmp_time = ( stat("$tmp_file") )[9];
    if ( ( $act_time - $tmp_time ) < $skip_time ) {
      print "                        skipped this time : ( $act_time - $tmp_time ) < $skip_time \n";
      return 0;
    }
  }

  # from detail-graph.pl
  # read aliases
  if ( -f "$alias_file" && open( FHC, "< $alias_file" ) ) {
    while (<FHC>) {
      next if $_ !~ /^LPAR:/;
      my $line = $_;
      $line =~ s/^LPAR://;
      chomp $line;
      push @alias, $line;
    }
    close(FHC);
  }

  # open a file with stored colours
  my @color_save = "";
  if ( -f "$file_color_save" ) {
    open( FHC, "< $file_color_save" ) || error( "file cannot be opened : $file_color_save " . __FILE__ . ":" . __LINE__ ) && return 0;
    @color_save = <FHC>;
    close(FHC);
  }

  my $type_edt = 0;
  if ( -f $type_edt_filep ) {
    $type_edt = 1;
  }

  open( FHL, ">> $list" ) || error( "Can't open $list : $!" . __FILE__ . ":" . __LINE__ ) && return 0;

  if ( $lpars_graph_type[0] !~ /LPAR/ ) {
    return 0;    # only for LPARs
  }

  my $header = "LAN Custom group $group: last $text";
  $header = "SAN Custom group $group: last $text"         if $item eq "san1";
  $header = "IOPS/Frames Custom group $group: last $text" if $item eq "san2";

  my $file  = "";
  my $i     = 0;
  my $j     = 0;
  my $lpar  = "";
  my $lparn = "";
  my $cmd   = "";
  my $cmdx  = "";

  my $filter = $filter_max_lansan;

  my $ds_name1 = "recv_bytes";
  my $ds_name2 = "trans_bytes";
  my $fpn      = "lan-";          # according to $item

  my $g_format = "6.2lf";
  my $divider  = 1000000;
  if ( $item =~ "^lan" ) {
    $ds_name2 = "recv_bytes";
    $ds_name1 = "trans_bytes";
  }
  my $vertical_label = "Read - Bytes/sec - Write";

  if ( $item =~ m/^san/ ) {
    $fpn = "san-";
  }
  if ( $item =~ m/^lan/ ) {
    $fpn = "lan-";
  }

  if ( $item =~ m/^san2/ ) {
    $g_format       = "6.0lf";
    $divider        = 1;
    $fpn            = "san-";
    $ds_name1       = "iops_in";
    $ds_name2       = "iops_out";
    $vertical_label = "Read - IOPS - Write";
    $filter         = $filter_max_iops;
  }

  if ( $type =~ m/y/ ) {

    # lower limits for yearly graphs as they are averaged ....
    $filter = $filter / 10;
  }
  if ( $type =~ m/m/ ) {

    # lower limits for monthly graphs as they are averaged ....
    $filter = $filter / 2;
  }

  my $index = 0;

  my $lim_org = $lim;
  $lim =~ s/\.//;
  $lim =~ s/i/l/;

  $cmd .= "graph \\\"$name.png\\\"";
  $cmd .= " --title \\\"$header\\\"";
  $cmd .= " --start now-1$type";
  $cmd .= " --end now-1$type+1$type";
  $cmd .= " --imgformat PNG";
  $cmd .= " $disable_rrdtool_tag_agg";
  $cmd .= " --slope-mode";
  $cmd .= " --width=400";
  $cmd .= " --height=150";
  $cmd .= " --step=$step_new";
  $cmd .= " --lower-limit=0";
  $cmd .= " --color=BACK#$pic_col";
  $cmd .= " --color=SHADEA#$pic_col";
  $cmd .= " --color=SHADEB#$pic_col";
  $cmd .= " --color=CANVAS#$pic_col";

  #$cmd .= " --alt-autoscale-max";
  $cmd .= " --vertical-label=\\\"$vertical_label\\\"";

  #$cmd .= " --units-exponent=1.00";
  $cmd .= " --alt-y-grid";
  $cmd .= " --x-grid=$xgrid";

  #$cmd .= " --base=1024";

  if ( $item =~ m/^san1$/ || $item =~ m/^lan$/ ) {
    $cmd .= " COMMENT:\\\"[MB/sec]\\l\\\"";
  }
  if ( $item =~ m/^san2$/ ) {
    $cmd .= " COMMENT:\\\"[IO per sec]\\l\\\"";
  }
  $cmd .= " COMMENT:\\\"  Server                       LPAR int                   avrg     max\\l\\\"";

  my @gtype;
  $gtype[0] = "AREA";
  $gtype[1] = "STACK";
  my $sh_pools          = 0;              # identificator of shared pool
  my @lpars_graph_local = @lpars_graph;
  my $updated           = " ";

  my ( @recb, @trab, @avgx, @avgy );
  my $lnx     = 0;
  my $index_l = 0;
  my %uniq_files;
  my $newest_file_timestamp = 0;

  # do not sort it HERE!! there is several arrays, sorting lpars_graph is not enough!!! --PH
  foreach my $file_tmp (@lpars_graph_local) {
    my $file = $file_tmp;    # must be here to allocate new space and do not make changes in @lpars_graph

    if ( $file eq '' ) {
      $index++;
      next;                  #some trash
    }

    if ( $file =~ m/\/mem.rr/ || $file =~ m/\/pool.rr/ ) {
      $index++;
      next;                  # include only real lpars
    }

    #print "001 $file\n";
    if ( !-f "$file/mem.mmm" ) {
      $index++;
      next;
    }
    if ( exists $uniq_files{"$file"} ) {    # check duplicities
      $index++;
      next;
    }
    $uniq_files{"$file"} = 1;
    $lparn .= " ";

    if ( ( length($lpar_v) + 1 ) == length($comm) && length($lparn) == length($comm) ) {
      copy_source_org( $webdir, $tmpdir, $basedir, $lim_org, $lim, $group );
      last;
    }
    $index_l++;

    my $item_tmp = $item;
    $item_tmp =~ s/[1,2]$//;

    my $file_space = $file;
    if ( $file_space =~ m/ / ) {    # workaround for name with a space inside, nothing else works, grrr
      $file_space = "\"" . $file . "\"";
    }

    # print "005 $file/$item_tmp-*.mmm\n \$file,\$item_tmp,\n@lpars_graph_local,\n";
    my @files_adapter = <$file_space/$item_tmp-*.mmm>;

    # print "005x @files_adapter,\n";

    if ( $type_edt == 0 && $lparno == 4 ) {
      copy_source_org( $webdir, $tmpdir, $basedir, $lim_org, $lim, $group );
      last;
    }
    $lparno++;

    foreach my $file_adapter (@files_adapter) {

      #print "002 $file_adapter\n";
      if ( !-f "$file_adapter" ) {
        next;
      }

      # avoid old lpars which do not exist in the period
      my $rrd_upd_time = ( stat("$file_adapter") )[9];
      if ( $rrd_upd_time < $req_time ) {

        #$index++;
        next;
      }

      my $adapter_name = basename($file_adapter);
      $adapter_name =~ s/^san-//;
      $adapter_name =~ s/^lan-//;
      $adapter_name =~ s/\.mmm$//;

      # add spaces to lpar name to have 25 chars total (for formating graph legend)
      $lpar = $lpars_graph_server[$index];

      # add alias to lpar name if exists
      my @choice = grep {/^$lpars_graph_name[$index]:/} @alias;

      # print "1121 \$lpar $lpars_graph_name[$index] \@choice @choice\n";
      if ( scalar @choice > 1 ) {
        error( "LPAR $lpars_graph_name[$index] has more aliases @choice " . __FILE__ . ":" . __LINE__ );
      }
      my $my_alias = "";
      if ( defined $choice[0] && $choice[0] ne "" ) {
        $choice[0] =~ s/\\//g;                            # if any colon is backslashed
        $choice[0] =~ s/^$lpars_graph_name[$index]://;    # only alias
        if ($test_legend) {
          $choice[0] = substr( $choice[0], 1, $max_alias_length );
        }
        $my_alias = "[" . "$choice[0]" . "]";
      }

      my $lpar_proc = "$lpar $delimiter " . "$lpars_graph_name[$index]$my_alias $delimiter $adapter_name";    # for html legend
      $lpar_proc =~ s/%/%%/g;
      $lpar_proc =~ s/:/\\:/g;
      $lpar_proc =~ s/\&\&1/\//g;

      $lpar =~ s/\&\&1/\//g;
      for ( my $k = length($lpar); $k < 25; $k++ ) {
        $lpar .= " ";
      }
      $lpar .= "   ";
      $lpar .= "$lpars_graph_name[$index]$my_alias $adapter_name";
      $lpar =~ s/\&\&1/\//g;

      # to keep same count of characters
      $lpar =~ s/\\:/:/g;
      $lpar = sprintf( "%-48s", $lpar );
      $lpar =~ s/:/\\:/g;

      for ( my $k = length($lpar); $k < 50; $k++ ) {
        $lpar .= " ";
      }

      #print "11 $file_adapter $rrd_upd_time $req_time $act_time\n" if ( $DEBUG == 1);

      if ( $type =~ "d" ) {
        RRDp::cmd qq(last "$file_adapter");
        my $last_tt = RRDp::read;
        chomp($$last_tt);
        $newest_file_timestamp = $$last_tt if $$last_tt > $newest_file_timestamp;
      }

      # Found out stored color index to keep same color for the volume across all graphs
      my $file_color = $file_adapter;
      $file_color =~ s/\.r..$//;
      $file_color =~ s/\\//g;
      $file_color =~ s/:/===========doublecoma=========/g;
      my $color_indx_found = -1;
      $color_indx = 0;
      foreach my $line_col (@color_save) {
        chomp($line_col);
        if ( $line_col eq '' || $line_col !~ m/ : / ) {
          next;
        }
        $color_indx++;
        ( my $color_indx_found_act, my $volume_name_save ) = split( / : /, $line_col );

        # do not use here $volume_name_save '' as this does not work when volume id is zero!
        if ( $volume_name_save =~ m/^$file_color$/ ) {
          $color_indx_found = $color_indx_found_act;
          $color_indx       = $color_indx_found;
          last;
        }
      }
      if ( $color_indx_found == -1 ) {
        $color_file_change = 1;
        $color_save[$color_indx] = $color_indx . " : " . $file_color;
      }
      while ( $color_indx > $color_max ) {
        $color_indx = $color_indx - $color_max;
      }

      # end color

      print FHL "$file_adapter\n";
      $file_adapter =~ s/:/\\:/g;

      my $file_legend = $file_adapter;
      $file_legend =~ s/%/%%/g;

      # bulid RRDTool cmd
      $recb[$i] = "rcb${i}";
      $trab[$i] = "trb${i}";
      $avgx[$i] = "avg${i}";
      $avgy[$i] = "avgy${i}";
      $cmd .= " DEF:$recb[$i]_nf=\\\"$file_adapter\\\":$ds_name1:AVERAGE";
      $cmd .= " DEF:$trab[$i]_nf=\\\"$file_adapter\\\":$ds_name2:AVERAGE";
      $cmd .= " CDEF:$recb[$i]=$recb[$i]_nf,$filter,GT,UNKN,$recb[$i]_nf,IF";
      $cmd .= " CDEF:$trab[$i]=$trab[$i]_nf,$filter,GT,UNKN,$trab[$i]_nf,IF";
      $cmd .= " CDEF:$recb[$i]-neg=$recb[$i],-1,*";
      $cmd .= " CDEF:$recb[$i]-mil=$recb[$i],$divider,/";
      $cmd .= " CDEF:$trab[$i]-mil=$trab[$i],$divider,/";
      $cmd .= " $gtype[$i>0]:$recb[$i]-neg$color[++$color_indx % ($color_max +1)]:\\\"R $lpar\\\"";
      $cmd .= " GPRINT:$recb[$i]-mil:AVERAGE:%$g_format";
      $cmd .= " GPRINT:$recb[$i]-mil:MAX:%$g_format\\l";

      $cmd .= " PRINT:$recb[$i]-mil:AVERAGE:\\\"%$g_format $delimiter multiview-ent-$item $delimiter R $lpar_proc\\\"";                      # for html legend
      $cmd .= " PRINT:$recb[$i]-mil:AVERAGE:\\\"%$g_format $delimiter $color[$color_indx % ($color_max +1)] $delimiter $file_legend\\\"";    # for html legend
      $cmd .= " PRINT:$recb[$i]-mil:MAX:\\\"%$g_format $delimiter\\\"";                                                                      # for html legend

      $cmd .= " STACK:$lnx$color[++$color_indx % ($color_max +1)]:\\\"W $lpar\\\"";

      $cmd .= " GPRINT:$trab[$i]-mil:AVERAGE:%$g_format";
      $cmd .= " GPRINT:$trab[$i]-mil:MAX:%$g_format\\l";

      $cmd .= " PRINT:$trab[$i]-mil:AVERAGE:\\\"%$g_format $delimiter multiview-ent-$item $delimiter W $lpar_proc\\\"";                      # for html legend
      $cmd .= " PRINT:$trab[$i]-mil:AVERAGE:\\\"%$g_format $delimiter $color[$color_indx % ($color_max +1)] $delimiter $file_legend\\\"";    # for html legend
      $cmd .= " PRINT:$trab[$i]-mil:MAX:\\\"%$g_format $delimiter\\\"";                                                                      # for html legend

      if ( $i == 0 ) {
        $cmdx .= " LINE1:$lnx:";
      }
      $cmdx .= " $gtype[$i>0]:$trab[$i++]$color[$color_indx % ($color_max +1)]:";
    }
    $index++;
    if ( !get_lpar_num() && $index_l > 4 ) {
      last;
    }
  }
  $cmd .= $cmdx;

  close(FHL);

  if ( $i == 0 ) {
    print "creating cgraph: " . scalar localtime() . " custom:$group $item-os $type: no any source found, skipping\n";
    return 0;    # nothing has been found
  }
  if ( $newest_file_timestamp > 0 ) {
    my $l = localtime($newest_file_timestamp);

    # following must be for RRD 1.2+
    $l =~ s/:/\\:/g;
    $updated = " COMMENT:\\\"  Updated\\\: $l \\\"";
  }

  $cmd .= " $updated";
  $cmd .= " HRULE:0#000000";

  # $cmd .= " VRULE:0#000000";  --> it is causing sigsegv on linuxeS
  $cmd =~ s/\\"/"/g;

  open( FH, "> $tmp_file" ) || error( "Can't open $tmp_file : $!" . __FILE__ . ":" . __LINE__ ) && return 0;
  print FH "$cmd\n";
  close(FH);

  #
  # do not execute it here
  # execute it in the run time based on cmd stored in $tmp_file
  #

  # write colors into a file
  if ( $color_file_change == 1 ) {
    open( FHC, "> $file_color_save" ) || error( "file cannot be created :  $file_color_save " . __FILE__ . ":" . __LINE__ ) && return 0;
    foreach my $line_cs (@color_save) {
      chomp($line_cs);    # it must be there, somehow appear there \n ...
      if ( $line_cs eq '' ) {
        next;
      }
      if ( $line_cs =~ m/ : / ) {
        print FHC "$line_cs\n";
      }
    }
    close(FHC);
  }

  # colours

  return 1;
}

sub rrd_last {
  my $rrd_file = shift;
  my $last_rec = 0;

  chomp($rrd_file);

  if ( !-f "$rrd_file" ) {
    return 0;
  }

  eval {
    RRDp::cmd qq(last "$rrd_file" );
    my $last_rec_rrd = RRDp::read;
    chomp($$last_rec_rrd);
    $last_rec = $$last_rec_rrd;
  };
  if ($@) {
    return 0;
  }
  return $last_rec;
}

# Note!!
# this function is defined in detail-graph-cgi.pl as LPM_easy and in XoruxEdition.pm as LPM_easy_premium
# when you make any change then replicate it in both files!!
#

sub LPM_easy {

  # this is for case e.g. HMC change, similar to LPM
  # join data streams from rrd files in one data_stream
  # call:
  #  my ($result_cmd,$result_stream_1,...,$result_stream_x) = LPM_easy($path_to_find_files,$var_indx,$req_time,$data_stream_1,...,$data_stream_x);
  # no limit for x
  # $result_cmd is CMD string for RRD

  my $file_pth = shift @_;    # path to find files
  my $var_indx = shift @_;    # to make variables unique in aggregated graphs
  my $req_time = shift @_;    # only files with newer timestamp are taken into consideration
  $file_pth =~ s/ /\\ /g;
  my $no_name = "";

  my @files = (<$file_pth$no_name>);    # unsorted, workaround for space in names
                                        # print STDERR "found pool files: @files\n";

  my @ds = @_;

  #print STDERR "000 in sub LPM_easy \@ds @ds\n";

  # prepare help variables
  my $prep_names = "";
  for ( my $x = 0; $x < @ds; $x++ ) { $prep_names .= "var" . $var_indx . $x . "," }
  my @ids = split( ",", "$prep_names" );
  $prep_names = "";
  for ( my $x = 0; $x < @ds; $x++ ) { $prep_names .= "var_r" . $var_indx . $x . "," }
  my @rids = split( ",", "$prep_names" );

  my $i = -1;
  my $j;
  my $rrd = "";
  my $cmd = "";

  foreach my $rrd (@files) {    # LPM alias cycle
    chomp($rrd);

    if ( $req_time > 0 ) {
      my $rrd_upd_time = ( stat("$rrd") )[9];
      if ( $rrd_upd_time < $req_time ) {
        next;
      }
    }
    $i++;
    $j = $i - 1;
    $rrd =~ s/:/\\:/g;

    for ( my $k = 0; $k < @ds; $k++ ) { $cmd .= " DEF:$ids[$k]${i}=\"$rrd\":$ds[$k]:AVERAGE"; }

    if ( $i == 0 ) {
      for ( my $k = 0; $k < @ds; $k++ ) { $cmd .= " CDEF:$rids[$k]${i}=$ids[$k]${i}"; }
      next;
    }
    for ( my $k = 0; $k < @ds; $k++ ) { $cmd .= " CDEF:$rids[$k]${i}=$rids[$k]${j},UN,$ids[$k]${i},$rids[$k]${j},IF"; }
  }

  if ( $i == -1 ) {

    # no fresh file has been found, do it once more qithout restriction to show at least the empty graph
    foreach my $rrd (@files) {    # LPM alias cycle
      chomp($rrd);

      $i++;
      $j = $i - 1;
      $rrd =~ s/:/\\:/g;

      for ( my $k = 0; $k < @ds; $k++ ) { $cmd .= " DEF:$ids[$k]${i}=\"$rrd\":$ds[$k]:AVERAGE"; }

      if ( $i == 0 ) {
        for ( my $k = 0; $k < @ds; $k++ ) { $cmd .= " CDEF:$rids[$k]${i}=$ids[$k]${i}"; }
        next;
      }
      for ( my $k = 0; $k < @ds; $k++ ) { $cmd .= " CDEF:$rids[$k]${i}=$rids[$k]${j},UN,$ids[$k]${i},$rids[$k]${j},IF"; }
    }
  }

  my $ret_string = "";
  for ( my $k = 0; $k < @ds; $k++ ) { $ret_string .= "$rids[$k]${i},"; }

  # print STDERR "\$cmd $cmd \$ret_string $ret_string\n";

  #print STDERR "001 $cmd,split(",",$ret_string)\n";
  return ( $cmd, split( ",", $ret_string ) );
}

# Exclude items (lpars/pool) if there is no data for last year for all HMCs
sub LPM_easy_exclude {
  my $file_pth = shift @_;    # path to find files
  my $req_time = shift @_;    # only files with newer timestamp are taken into consideration
  $file_pth =~ s/ /\\ /g;
  my $no_name = "";

  my @files = (<$file_pth$no_name>);    # unsorted, workaround for space in names
                                        # print STDERR "found pool files: @files\n";

  my $i = 0;

  foreach my $rrd (@files) {            # LPM alias cycle
    chomp($rrd);

    my $rrd_upd_time = ( stat("$rrd") )[9];
    if ( $rrd_upd_time < $req_time ) {
      next;
    }
    $i++;
    last;
  }

  if ( $i > 0 ) {
    return 1;
  }
  else {
    return 0;    # there is not updated rrd file for last year, skipt that item
  }

}

sub multiview_esxi_cpu {
  my $group    = shift;
  my $name     = shift;
  my $type     = shift;
  my $type_sam = shift;
  my $act_time = shift;
  my $step_new = shift;
  my $text     = shift;
  my $xgrid    = shift;
  my $item     = shift;

  $item = "" if !defined $item;

  my $req_time = 0;
  my $comm     = "COMM ";
  $color_indx = 0;    # clear color index
  my $list              = "$webdir/custom/$group/list.txt";
  my $lim               = ".li";
  my $updated           = "";
  my $color_file_change = 0;
  my $file_color_save   = "$basedir/tmp/custom-group-$item-$group.col";

  #  my $all_vmware_VMs    = "vmware_VMs";
  my $lparno = 0;

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

  my $tmp_file = "$tmpdir/custom-group-$item-$group-$type.cmd";

  # $tmp_file = "$tmpdir/custom-group-vmmem-$group-$type.cmd" if $item eq "mem";

  # do not update weekly/monthly/yearly command files each run
  if ( -f "$tmp_file" ) {
    my $tmp_time = ( stat("$tmp_file") )[9];
    if ( ( $act_time - $tmp_time ) < $skip_time ) {
      print "                        skipped this time : ( $act_time - $tmp_time ) < $skip_time \n";
      return 0;
    }
  }

  # open a file with stored colours
  my @color_save = "";
  if ( -f "$file_color_save" ) {
    open( FHC, "< $file_color_save" ) || error( "file cannot be opened : $file_color_save " . __FILE__ . ":" . __LINE__ ) && return 0;
    @color_save = <FHC>;
    close(FHC);
  }

  my $type_edt = 0;
  if ( -f $type_edt_filev ) {
    $type_edt = 1;
  }

  # open file for writing list of lpars
  open( FHL, "> $list" ) || error( "Can't open $list : $!" . __FILE__ . ":" . __LINE__ ) && return 0;

  my $header = "CPU Custom group $group: last $text";
  $header = "MEM Custom group $group: last $text" if $item eq "mem";

  my $file    = "";
  my $i       = 0;
  my $lpar    = "";
  my $lparn   = "";
  my $cmd     = "";
  my $cmd_xpo = "";
  my $cmdq    = "";
  my $j       = 0;

  my $vertical_label = "CPU in cores";
  my $comm_text      = "Utilization CPU in cores";
  if ( $item eq "mem" ) {
    $vertical_label = "Active Memory in GB";
    $comm_text      = "Active Memory in GB    ";
  }
  $cmd_xpo = "xport ";
  if ( -f "$basedir/tmp/rrdtool-xport-showtime" ) {
    $cmd_xpo .= " --showtime";
  }
  $cmd_xpo .= " --start now-1$type";
  $cmd_xpo .= " --end now-1$type+1$type";
  $cmd_xpo .= " --step $step_new";
  $cmd_xpo .= " --maxrows 65000";

  my $lim_org = $lim;
  $lim =~ s/\.//;
  $lim =~ s/i/l/;

  $cmd .= "graph \\\"$name.png\\\"";
  $cmd .= " --title \\\"$header\\\"";
  $cmd .= " --start now-1$type";
  $cmd .= " --end now-1$type+1$type";
  $cmd .= " --imgformat PNG";
  $cmd .= " $disable_rrdtool_tag_agg";
  $cmd .= " --slope-mode";
  $cmd .= " --width=400";
  $cmd .= " --height=150";
  $cmd .= " --step=$step_new";
  $cmd .= " --lower-limit=0.00";
  $cmd .= " --color=BACK#$pic_col";
  $cmd .= " --color=SHADEA#$pic_col";
  $cmd .= " --color=SHADEB#$pic_col";
  $cmd .= " --color=CANVAS#$pic_col";
  $cmd .= " --alt-autoscale-max";
  $cmd .= " --upper-limit=0.1";
  $cmd .= " --vertical-label=\\\"$vertical_label\\\"";
  $cmd .= " --units-exponent=1.00";
  $cmd .= " --alt-y-grid";
  $cmd .= " --x-grid=$xgrid";
  $cmd .= " COMMENT:\\\"$comm_text                         \\l\\\"";
  $cmd .= " COMMENT:\\\"  Server                                               avrg     max\\l\\\"";

  my $gtype = "AREA";
  my $index = 0;

  my @lpars_graph_local = @lpars_graph;

  # print "3557 custom.pl \@lpars_graph @lpars_graph\n";

  my %uniq_files;
  my $newest_file_timestamp = 0;

  # do not sort it HERE!! there is several arrays, sorting lpars_graph is not enough!!! --PH
  foreach my $file_cycl (@lpars_graph_local) {

    # print STDERR "3565 custom.pl \$file_cycl $file_cycl\n";
    # /home/lpar2rrd/lpar2rrd/data/Linux/no_hmc/kvm.xorux.com
    my $server      = ( split( /\//, $file_cycl ) )[-3];
    my $server_name = $server;

    $server = "$server";

    # print "3571 custom.pl \$server $server\n";

    if ( $server eq '' ) {
      $index++;
      next;    #some trash
    }

    #    my $file = "$file_cycl/cpu.mmm";
    my $file = "$file_cycl";

    if ( !-f $file ) {
      $index++;
      next;
    }

    # avoid old lpars which do not exist in the period
    my $rrd_upd_time = ( stat("$file") )[9];
    if ( $rrd_upd_time < $req_time ) {
      $index++;
      next;
    }

    # add spaces to lpar name to have 25 chars total (for formating graph legend)
    #$lpar = $lpars_graph_server[$index];

    $lpar = $server_name;
    my $lpar_orig = $lpar;

    my $lpar_proc = "$lpar";    # for html legend
    $lpar_proc =~ s/%/%%/g;
    $lpar_proc =~ s/:/\\:/g;
    $lpar_proc =~ s/\&\&1/\//g;

    $lpar =~ s/\&\&1/\//g;
    for ( my $k = length($lpar); $k < 25; $k++ ) {
      $lpar .= " ";
    }

    #$lpar .= "   ";
    #$lpar .= $vm_name;
    $lpar =~ s/\&\&1/\//g;

    # to keep same count of characters
    $lpar =~ s/\\:/:/g;
    $lpar = sprintf( "%-50s", $lpar );
    $lpar =~ s/:/\\:/g;

    my $lpar_space = $lpar;

    my $lpar_space_proc = $server_name;
    $lpar_space_proc =~ s/\:/\\:/g;

    if ( exists $uniq_files{"$file"} ) {    # check duplicities
      $index++;
      next;
    }
    $uniq_files{"$file"} = 1;
    $lparn .= " ";
    print FHL "$file\n";

    # print "3630 custom.pl $server $rrd_upd_time $req_time $act_time \$lpar_space_proc $lpar_space_proc \$file $file\n" ; # if ( $DEBUG == 1);

    if ( ( length($lpar_v) + 1 ) == length($comm) && length($lparn) == length($comm) ) {
      copy_source_org( $webdir, $tmpdir, $basedir, $lim_org, $lim, $group );
      last;
    }

    if ( $type =~ "d" ) {
      RRDp::cmd qq(last "$file");
      my $last_tt = RRDp::read;
      chomp($$last_tt);
      $newest_file_timestamp = $$last_tt if $$last_tt > $newest_file_timestamp;
    }

    my $file_legend = $server;
    $file_legend =~ s/%/%%/g;
    $file_legend =~ s/:/\\:/g;

    # Exclude items (lpars/pool) if there is no data for last year for all HMCs
    #if ( LPM_easy_exclude($file_pth,$act_time-31622400) == 0 ) {
    #  $index++;
    #  next;    # there is not updated rrd file for last year, skip that item
    #}

    # Found out stored color index to keep same color for the volume across all graphs
    my $file_color = $server;
    $file_color =~ s/\.mmm$//;
    $file_color =~ s/\\//g;
    $file_color =~ s/:/===========doublecoma=========/g;
    my $color_indx_found = -1;
    $color_indx = 0;
    foreach my $line_col (@color_save) {
      chomp($line_col);
      if ( $line_col eq '' || $line_col !~ m/ : / ) {
        next;
      }
      $color_indx++;
      ( my $color_indx_found_act, my $volume_name_save ) = split( / : /, $line_col );

      # do not use here $volume_name_save '' as this does not work when volume id is zero!
      if ( $volume_name_save =~ m/^$file_color$/ ) {
        $color_indx_found = $color_indx_found_act;
        $color_indx       = $color_indx_found;
        last;
      }
    }
    if ( $color_indx_found == -1 ) {
      $color_file_change = 1;
      $color_save[$color_indx] = $color_indx . " : " . $file_color;
    }
    while ( $color_indx > $color_max ) {
      $color_indx = $color_indx - $color_max;
    }

    # end color

    if ( $type_edt == 0 && $lparno == 4 ) {
      copy_source_org( $webdir, $tmpdir, $basedir, $lim_org, $lim, $group );
      last;
    }
    $lparno++;

    # following part is from vmw2rrd.pl
    my $managedname_space      = $server;
    my $managedname_space_proc = $server;
    my $managedname            = $server;
    $managedname_space_proc =~ s/:/\\:/g;
    $managedname_space_proc =~ s/%/%%/g;    # anti '%

    for ( my $k = length($managedname); $k < 35; $k++ ) {
      $managedname_space .= " ";
    }
    $managedname_space = substr( $managedname_space, 0, 34 );    # not longer

    $managedname_space =~ s/:/\\:/g;                             # anti ':'
    my $wrkdir_managedname_host_file = "$file";

    # print "3749 creating CMD for $wrkdir_managedname_host_file\n" if $DEBUG ;

    $wrkdir_managedname_host_file =~ s/:/\\:/g;
    my $wrkdir_managedname_host_file_legend = $wrkdir_managedname_host_file;
    $wrkdir_managedname_host_file_legend =~ s/%/%%/g;

    # my in_cores = 1;
    # bulid RRDTool cmd
    $cmd .= " DEF:cpu_entitl_mhz${i}=\\\"$wrkdir_managedname_host_file\\\":CPU_Alloc:AVERAGE";
    $cmd .= " DEF:utiltot_mhz${i}=\\\"$wrkdir_managedname_host_file\\\":CPU_usage:AVERAGE";
    $cmd .= " DEF:one_core_hz${i}=\\\"$wrkdir_managedname_host_file\\\":host_hz:AVERAGE";

    #    $cmd .= " COMMENT:\"   Average                   cores      Ghz (right axis)\\n\"";
    #    if ($in_cores) left curly
    $cmd .= " CDEF:cpuutiltot${i}=utiltot_mhz${i},one_core_hz${i},/,1000000,*";
    $cmd .= " CDEF:ncpu${i}=cpu_entitl_mhz${i},one_core_hz${i},/,1000000,*";
    $cmd .= " CDEF:cpu_entitl_ghz${i}=cpu_entitl_mhz${i},1000,/";
    $cmd .= " CDEF:utiltot_ghz${i}=utiltot_mhz${i},1000,/";

    #    $cmd .= " DEF:totcyc${i}=\\\"$wrkdir_managedname_host_file\\\":total_pool_cycles:AVERAGE";
    #    $cmd .= " DEF:uticyc${i}=\\\"$wrkdir_managedname_host_file\\\":utilized_pool_cyc:AVERAGE";
    #    $cmd .= " DEF:ncpu${i}=\\\"$wrkdir_managedname_host_file\\\":conf_proc_units:AVERAGE";
    #    $cmd .= " DEF:ncpubor${i}=\\\"$wrkdir_managedname_host_file\\\":bor_proc_units:AVERAGE";
    # if it does not exist for some time period then put 0 there
    $cmd .= " CDEF:cpu${i}=ncpu${i},UN,0,ncpu${i},IF";

    #    $cmd .= " CDEF:cpubor${i}=ncpubor${i},UN,0,ncpubor${i},IF";
    #    $cmd .= " CDEF:totcpu${i}=cpu${i},cpubor${i},+";
    #    $cmd .= " CDEF:cpuutil${i}=uticyc${i},totcyc${i},GT,UNKN,uticyc${i},totcyc${i},/,IF";
    #    $cmd .= " CDEF:cpuutiltot${i}=cpuutil${i},totcpu${i},*";
    #    $cmd .= " CDEF:utilisa${i}=cpuutil${i},100,*";
    $cmd .= " PRINT:cpuutiltot${i}:AVERAGE:\"%6.2lf $delimiter multihmcframe $delimiter $managedname_space_proc $delimiter $color[$color_indx]\"";
    $cmd .= " PRINT:cpuutiltot${i}:MAX:\" %6.2lf $delimiter $wrkdir_managedname_host_file_legend\"";

    $cmdq .= " $gtype:cpuutiltot${i}$color[$color_indx++]:\\\"$managedname_space\\\"";
    $cmdq .= " GPRINT:cpuutiltot${i}:AVERAGE:\\\"%6.2lf \\\"";
    $cmdq .= " GPRINT:cpuutiltot${i}:MAX:\\\"%6.2lf \\l\\\"";
    if ( $color_indx > $color_max ) {
      $color_indx = 0;
    }

    # put carriage return after each second lpar in the legend
    if ( $j == 1 ) {
      $j = 0;
    }
    else {
      $j++;
    }
    $gtype = "STACK";
    $i++;
    $color_indx = ++$color_indx % ( $color_max + 1 );

  }

  # print "3806 \$i $i \$j $j \$tmp_file $tmp_file \$cmd $cmd\n";
  if ( $i == 0 ) {

    # no available managed system
    #print "UNLINK         :$tmp_file before if\n";
    if ( -f "$tmp_file" ) {
      print "UNLINK         :$tmp_file\n";
      unlink $tmp_file;
    }
    else {
      #      $tmp_file = "$tmpdir/multi-hmc-$cl_managedname-$cl_host-$type.cmd";
      #      if ( -f "$tmp_file" ) {
      #        print "UNLINK         :$tmp_file\n";
      #        unlink $tmp_file;
      #      }
    }
    return 1;
  }

  # add count of all CPU in pools
  for ( $j = 0; $j < $i; $j++ ) {
    if ( $j == 0 ) {
      $cmd .= " CDEF:tcpu${j}=cpu${j}";
    }
    else {
      my $k = $j - 1;

      #      $cmd .= " CDEF:tcpu_tmp${j}=cpu${j},cpubor${j},+";
      $cmd .= " CDEF:tcpu${j}=tcpu${k},cpu${j},+";
    }
  }
  if ( $j > 0 ) {
    $j--;
  }
  my $cpu_pool_total = "CPUs total available in pools";
  for ( my $k = length($cpu_pool_total); $k < 35; $k++ ) {
    $cpu_pool_total .= " ";
  }
  $cmd .= " CDEF:tcpun${j}=tcpu${j},0,EQ,UNKN,tcpu${j},IF";
  $cmd .= " LINE2:tcpun${j}#888888:\\\"$cpu_pool_total\\\"";

  #$cmd .= " GPRINT:tcpu${j}:AVERAGE:\\\"%6.2lf \\\"";
  # excluded as it is a bit misleading there there is any even small data gap
  $cmd .= " GPRINT:tcpun${j}:MAX:\\\"         %6.2lf \\l\\\"";
  $cmd .= $cmdq;
  $cmd .= " PRINT:tcpun${j}:MAX:\\\"         %6.2lf MAXTCPU $delimiter\\\"";
  $cmd .= " HRULE:0#000000";

  # $cmd .= " VRULE:0#000000";  --> it is causing sigsegv on linuxeS
  $cmd =~ s/\\"/"/g;

  #  my $FH;
  #my $tmp_file = "$tmpdir/multi-hmc-$host-$type.cmd";
  #if ( $cluster ne "" ) {
  #  $tmp_file = "$tmpdir/multi-hmc-$cl_managedname-$cl_host-$type.cmd";
  #}

  # print "3862 CMD is in file $tmp_file\n" if $DEBUG;
  open( FH, "> $tmp_file" ) || error( " Can't open $tmp_file : $!" . __FILE__ . ":" . __LINE__ ) && return 0;
  print FH "$cmd\n";
  close(FH);

  #  $cmd_sum =~ s/\\"/"/g;
  $cmd_xpo =~ s/\\"/"/g;

  close(FHL);
  my $FH;

  # store XPORT for future usage in Hist reports (detail-graph-cgi.pl)
  if ( "$type" =~ "d" ) {

    # only daily one
    my $tmp_file_xpo = "$tmpdir/custom-group-$group-$type-xpo.cmd";
    $tmp_file_xpo = "$tmpdir/custom-group-vmmem-$group-$type-xpo.cmd" if $item eq "mem";
    open( FH, "> $tmp_file_xpo" ) || error( "Can't open $tmp_file_xpo : $!" . __FILE__ . ":" . __LINE__ ) && return 0;
    print FH "$cmd_xpo\n";
    close(FH);
  }

  if ( $newest_file_timestamp > 0 ) {
    my $l = localtime($newest_file_timestamp);

    # following must be for RRD 1.2+
    $l =~ s/:/\\:/g;
    $updated = " COMMENT:\\\"  Updated\\\: $l \\\"";
  }

  $cmd .= " $updated";

  if ( "$type" =~ "d" ) {
    if ( $j == 1 ) {
      $cmd .= " COMMENT:\\\" \\l\\\"";
    }
  }
  $cmd .= " HRULE:0#000000";

  # $cmd .= " VRULE:0#000000";  --> it is causing sigsegv on linuxeS
  $cmd =~ s/\\"/"/g;

  # print "3901 custom.pl $tmp_file\n" ;
  open( FH, "> $tmp_file" ) || error( "Can't open $tmp_file : $!" . __FILE__ . ":" . __LINE__ ) && return 0;
  print FH "$cmd\n";
  close(FH);

  if ( !get_lpar_num() ) {
    if ( $index > 4 ) {
      if ( !-f "$webdir/custom/$group/$lim" ) {
        copy_source_org( $webdir, $tmpdir, $basedir, $lim_org, $lim, $group );
      }
    }
  }

  # write colors into a file
  if ( $color_file_change == 1 ) {
    open( FHC, "> $file_color_save" ) || error( "file cannot be created :  $file_color_save " . __FILE__ . ":" . __LINE__ ) && return 0;
    foreach my $line_cs (@color_save) {
      chomp($line_cs);    # it must be there, somehow appear there \n ...
      if ( $line_cs eq '' ) {
        next;
      }
      if ( $line_cs =~ m/ : / ) {
        print FHC "$line_cs\n";
      }
    }
    close(FHC);
  }

  #
  # do not execute it here
  # execute it in the run time based on cmd stored in $tmp_file
  #

  return 1;
}

sub multiview_linux_cpu {
  my $group    = shift;
  my $name     = shift;
  my $type     = shift;
  my $type_sam = shift;
  my $act_time = shift;
  my $step_new = shift;
  my $text     = shift;
  my $xgrid    = shift;
  my $item     = shift;

  $item = "" if !defined $item;

  my $req_time = 0;
  my $comm     = "COMM ";
  $color_indx = 0;    # clear color index
  my $list              = "$webdir/custom/$group/list.txt";
  my $lim               = ".li";
  my $updated           = "";
  my $color_file_change = 0;
  my $file_color_save   = "$basedir/tmp/custom-group-$item-$group.col";
  my $all_vmware_VMs    = "vmware_VMs";
  my $lparno            = 0;

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

  my $tmp_file = "$tmpdir/custom-group-$item-$group-$type.cmd";

  # $tmp_file = "$tmpdir/custom-group-vmmem-$group-$type.cmd" if $item eq "mem";

  # do not update weekly/monthly/yearly command files each run
  if ( -f "$tmp_file" ) {
    my $tmp_time = ( stat("$tmp_file") )[9];
    if ( ( $act_time - $tmp_time ) < $skip_time ) {
      print "                        skipped this time : ( $act_time - $tmp_time ) < $skip_time \n";
      return 0;
    }
  }

  # open a file with stored colours
  my @color_save = "";
  if ( -f "$file_color_save" ) {
    open( FHC, "< $file_color_save" ) || error( "file cannot be opened : $file_color_save " . __FILE__ . ":" . __LINE__ ) && return 0;
    @color_save = <FHC>;
    close(FHC);
  }

  my $type_edt = 0;
  if ( -f $type_edt_filel ) {
    $type_edt = 1;
  }

  # open file for writing list of lpars
  open( FHL, "> $list" ) || error( "Can't open $list : $!" . __FILE__ . ":" . __LINE__ ) && return 0;

  my $header = "CPU Custom group $group: last $text";
  $header = "MEM Custom group $group: last $text" if $item eq "mem";

  my $file    = "";
  my $i       = 0;
  my $lpar    = "";
  my $lparn   = "";
  my $cmd     = "";
  my $cmd_xpo = "";
  my $j       = 0;

  my $vertical_label = "%";
  my $comm_text      = "Utilization in CPU %";
  if ( $item eq "mem" ) {
    $vertical_label = "Active Memory in GB";
    $comm_text      = "Active Memory in GB    ";
  }
  $cmd_xpo = "xport ";
  if ( -f "$basedir/tmp/rrdtool-xport-showtime" ) {
    $cmd_xpo .= " --showtime";
  }
  $cmd_xpo .= " --start now-1$type";
  $cmd_xpo .= " --end now-1$type+1$type";
  $cmd_xpo .= " --step $step_new";
  $cmd_xpo .= " --maxrows 65000";

  my $lim_org = $lim;
  $lim =~ s/\.//;
  $lim =~ s/i/l/;

  $cmd .= "graph \\\"$name.png\\\"";
  $cmd .= " --title \\\"$header\\\"";
  $cmd .= " --start now-1$type";
  $cmd .= " --end now-1$type+1$type";
  $cmd .= " --imgformat PNG";
  $cmd .= " $disable_rrdtool_tag_agg";
  $cmd .= " --slope-mode";
  $cmd .= " --width=400";
  $cmd .= " --height=150";
  $cmd .= " --step=$step_new";
  $cmd .= " --lower-limit=0.00";
  $cmd .= " --color=BACK#$pic_col";
  $cmd .= " --color=SHADEA#$pic_col";
  $cmd .= " --color=SHADEB#$pic_col";
  $cmd .= " --color=CANVAS#$pic_col";
  $cmd .= " --alt-autoscale-max";
  $cmd .= " --upper-limit=0.1";
  $cmd .= " --vertical-label=\\\"$vertical_label\\\"";
  $cmd .= " --units-exponent=1.00";
  $cmd .= " --alt-y-grid";
  $cmd .= " --x-grid=$xgrid";
  $cmd .= " COMMENT:\\\"$comm_text                         \\l\\\"";
  $cmd .= " COMMENT:\\\"  Server                                               avrg     max\\l\\\"";

  my $gtype = "AREA";
  my $index = 0;

  my @lpars_graph_local = @lpars_graph;

  # print STDERR "3399 custom.pl \@lpars_graph @lpars_graph\n";

  my %uniq_files;
  my $newest_file_timestamp = 0;

  # do not sort it HERE!! there is several arrays, sorting lpars_graph is not enough!!! --PH
  foreach my $file_cycl (@lpars_graph_local) {

    # print STDERR "3407 custom.pl \$file_cycl $file_cycl\n";
    # /home/lpar2rrd/lpar2rrd/data/Linux/no_hmc/kvm.xorux.com
    my $server      = ( split( /\//, $file_cycl ) )[-1];
    my $server_name = $server;

    $server = "$server";

    #print STDERR "3413 custom.pl \$server $server\n";

    if ( $server eq '' ) {
      $index++;
      next;    #some trash
    }

    my $file = "$file_cycl/cpu.mmm";

    if ( !-f $file ) {
      $index++;
      next;
    }

    # avoid old lpars which do not exist in the period
    my $rrd_upd_time = ( stat("$file") )[9];
    if ( $rrd_upd_time < $req_time ) {
      $index++;
      next;
    }

    # add spaces to lpar name to have 25 chars total (for formating graph legend)
    #$lpar = $lpars_graph_server[$index];

    $lpar = $server_name;
    my $lpar_orig = $lpar;

    my $lpar_proc = "$lpar";    # for html legend
    $lpar_proc =~ s/%/%%/g;
    $lpar_proc =~ s/:/\\:/g;
    $lpar_proc =~ s/\&\&1/\//g;

    $lpar =~ s/\&\&1/\//g;
    for ( my $k = length($lpar); $k < 25; $k++ ) {
      $lpar .= " ";
    }

    #$lpar .= "   ";
    #$lpar .= $vm_name;
    $lpar =~ s/\&\&1/\//g;

    # to keep same count of characters
    $lpar =~ s/\\:/:/g;
    $lpar = sprintf( "%-50s", $lpar );
    $lpar =~ s/:/\\:/g;

    my $lpar_space = $lpar;

    my $lpar_space_proc = $server_name;
    $lpar_space_proc =~ s/\:/\\:/g;

    if ( exists $uniq_files{"$file"} ) {    # check duplicities
      $index++;
      next;
    }
    $uniq_files{"$file"} = 1;
    $lparn .= " ";
    print FHL "$file\n";

    # print STDERR "3470 custom.pl $server $rrd_upd_time $req_time $act_time \$lpar_space_proc $lpar_space_proc \$file $file\n" ; # if ( $DEBUG == 1);

    if ( ( length($lpar_v) + 1 ) == length($comm) && length($lparn) == length($comm) ) {
      copy_source_org( $webdir, $tmpdir, $basedir, $lim_org, $lim, $group );
      last;
    }

    if ( $type =~ "d" ) {
      RRDp::cmd qq(last "$file");
      my $last_tt = RRDp::read;
      chomp($$last_tt);
      $newest_file_timestamp = $$last_tt if $$last_tt > $newest_file_timestamp;
    }

    my $file_legend = $server;
    $file_legend =~ s/%/%%/g;
    $file_legend =~ s/:/\\:/g;

    # Exclude items (lpars/pool) if there is no data for last year for all HMCs
    #if ( LPM_easy_exclude($file_pth,$act_time-31622400) == 0 ) {
    #  $index++;
    #  next;    # there is not updated rrd file for last year, skip that item
    #}

    # Found out stored color index to keep same color for the volume across all graphs
    my $file_color = $server;
    $file_color =~ s/\.mmm$//;
    $file_color =~ s/\\//g;
    $file_color =~ s/:/===========doublecoma=========/g;
    my $color_indx_found = -1;
    $color_indx = 0;
    foreach my $line_col (@color_save) {
      chomp($line_col);
      if ( $line_col eq '' || $line_col !~ m/ : / ) {
        next;
      }
      $color_indx++;
      ( my $color_indx_found_act, my $volume_name_save ) = split( / : /, $line_col );

      # do not use here $volume_name_save '' as this does not work when volume id is zero!
      if ( $volume_name_save =~ m/^$file_color$/ ) {
        $color_indx_found = $color_indx_found_act;
        $color_indx       = $color_indx_found;
        last;
      }
    }
    if ( $color_indx_found == -1 ) {
      $color_file_change = 1;
      $color_save[$color_indx] = $color_indx . " : " . $file_color;
    }
    while ( $color_indx > $color_max ) {
      $color_indx = $color_indx - $color_max;
    }

    # end color

    if ( $type_edt == 0 && $lparno == 4 ) {
      copy_source_org( $webdir, $tmpdir, $basedir, $lim_org, $lim, $group );
      last;
    }
    $lparno++;

    # new system
    my $wrkdir_managedname_host_file = "$file";
    $wrkdir_managedname_host_file =~ s/:/\\:/g;

    #my $wrkdir_managedname_host_file_legend = $wrkdir_managedname_host_file;
    my $wrkdir_managedname_host_file_legend = "$server";
    $wrkdir_managedname_host_file_legend =~ s/%/%%/g;
    $wrkdir_managedname_host_file_legend =~ s/:/\\:/g;

    my $item_leg = "multihmclpar_linux_cpu";

    # bulid RRDTool cmd
    if ( $item eq "mem" ) {
      $cmd .= " DEF:utiltot_use${i}=\\\"$wrkdir_managedname_host_file\\\":nuse:AVERAGE";
      $cmd .= " CDEF:utiltot${i}=utiltot_use${i},1048576,/";
      $item_leg = "multihmclpar_linux_mem";
    }
    else {
      $cmd .= " DEF:utiltot_mhz_us${i}=\\\"$wrkdir_managedname_host_file\\\":cpu_us:AVERAGE";
      $cmd .= " DEF:utiltot_mhz_sy${i}=\\\"$wrkdir_managedname_host_file\\\":cpu_sy:AVERAGE";
      $cmd .= " CDEF:utiltot_mhz${i}=utiltot_mhz_us${i},utiltot_mhz_sy${i},+";
      $cmd .= " CDEF:utiltot_ghz${i}=utiltot_mhz${i},1,/";
      $cmd .= " CDEF:utiltot${i}=utiltot_mhz${i},1,/";                                          # since 4.74- (u)
    }

    #$cmd .= " $gtype:utiltot${i}$color[$color_indx]:\\\"$lpar_space\\\"";
    $cmd .= " LINE1:utiltot${i}$color[$color_indx]:\\\"$lpar_space\\\"";

    push @color_save, $lpar_orig;

    $cmd .= " PRINT:utiltot${i}:AVERAGE:\"%3.2lf $delimiter $item_leg $delimiter $server_name $delimiter $lpar_space_proc\"";
    $cmd .= " PRINT:utiltot${i}:AVERAGE:\\\"%3.2lf $delimiter $color[$color_indx] $delimiter $wrkdir_managedname_host_file_legend\\\"";
    $cmd .= " PRINT:utiltot${i}:MAX:\" %3.2lf $delimiter\"";

    $cmd .= " GPRINT:utiltot${i}:AVERAGE:\\\"%3.2lf \\\"";
    $cmd .= " GPRINT:utiltot${i}:MAX:\\\" %3.2lf \\l\\\"";

    $cmd_xpo .= " DEF:utiltot_use${i}=\\\"$wrkdir_managedname_host_file\\\":nuse:AVERAGE";

    $cmd_xpo .= " \\\"CDEF:utiltot_ghz${i}=utiltot_use${i},1000,/\\\"";
    $cmd_xpo .= " \\\"CDEF:utiltot${i}=utiltot_mhz${i},1000,/\\\"";
    $cmd_xpo .= " \\\"XPORT:utiltot${i}:$lpar\\\"";

    # put carriage return after each second lpar in the legend
    if ( $j == 1 ) {
      $j = 0;
    }
    else {
      $j++;
    }
    $gtype = "STACK";
    $i++;
    $color_indx = ++$color_indx % ( $color_max + 1 );

  }

  #  $cmd_sum =~ s/\\"/"/g;
  $cmd_xpo =~ s/\\"/"/g;

  close(FHL);
  my $FH;

  # store XPORT for future usage in Hist reports (detail-graph-cgi.pl)
  if ( "$type" =~ "d" ) {

    # only daily one
    my $tmp_file_xpo = "$tmpdir/custom-group-$group-$type-xpo.cmd";
    $tmp_file_xpo = "$tmpdir/custom-group-vmmem-$group-$type-xpo.cmd" if $item eq "mem";
    open( FH, "> $tmp_file_xpo" ) || error( "Can't open $tmp_file_xpo : $!" . __FILE__ . ":" . __LINE__ ) && return 0;
    print FH "$cmd_xpo\n";
    close(FH);
  }

  if ( $newest_file_timestamp > 0 ) {
    my $l = localtime($newest_file_timestamp);

    # following must be for RRD 1.2+
    $l =~ s/:/\\:/g;
    $updated = " COMMENT:\\\"  Updated\\\: $l \\\"";
  }

  $cmd .= " $updated";

  if ( "$type" =~ "d" ) {
    if ( $j == 1 ) {
      $cmd .= " COMMENT:\\\" \\l\\\"";
    }
  }
  $cmd .= " HRULE:0#000000";

  # $cmd .= " VRULE:0#000000";  --> it is causing sigsegv on linuxeS
  $cmd =~ s/\\"/"/g;

  # print STDERR "3525 custom.pl $tmp_file\n" ;
  open( FH, "> $tmp_file" ) || error( "Can't open $tmp_file : $!" . __FILE__ . ":" . __LINE__ ) && return 0;
  print FH "$cmd\n";
  close(FH);

  if ( !get_lpar_num() ) {
    if ( $index > 4 ) {
      if ( !-f "$webdir/custom/$group/$lim" ) {
        copy_source_org( $webdir, $tmpdir, $basedir, $lim_org, $lim, $group );
      }
    }
  }

  # write colors into a file
  if ( $color_file_change == 1 ) {
    open( FHC, "> $file_color_save" ) || error( "file cannot be created :  $file_color_save " . __FILE__ . ":" . __LINE__ ) && return 0;
    foreach my $line_cs (@color_save) {
      chomp($line_cs);    # it must be there, somehow appear there \n ...
      if ( $line_cs eq '' ) {
        next;
      }
      if ( $line_cs =~ m/ : / ) {
        print FHC "$line_cs\n";
      }
    }
    close(FHC);
  }

  # colours

  #
  # do not execute it here
  # execute it in the run time based on cmd stored in $tmp_file
  #

  return 1;
}

sub multiview_linux {
  my $group    = shift;
  my $name     = shift;
  my $type     = shift;
  my $type_sam = shift;
  my $act_time = shift;
  my $step_new = shift;
  my $text     = shift;
  my $xgrid    = shift;
  my $item     = shift;

  $item = "" if !defined $item;

  my $req_time = 0;
  my $comm     = "COMM ";
  $color_indx = 0;    # clear color index
  my $list              = "$webdir/custom/$group/list.txt";
  my $lim               = ".li";
  my $updated           = "";
  my $color_file_change = 0;
  my $file_color_save   = "$basedir/tmp/custom-group-$item-$group.col";
  my $all_vmware_VMs    = "vmware_VMs";
  my $lparno            = 0;

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

  my $tmp_file = "$tmpdir/custom-group-$item-$group-$type.cmd";

  # $tmp_file = "$tmpdir/custom-group-vmmem-$group-$type.cmd" if $item eq "mem";

  # do not update weekly/monthly/yearly command files each run
  if ( -f "$tmp_file" ) {
    my $tmp_time = ( stat("$tmp_file") )[9];
    if ( ( $act_time - $tmp_time ) < $skip_time ) {
      print "                        skipped this time : ( $act_time - $tmp_time ) < $skip_time \n";
      return 0;
    }
  }

  # open a file with stored colours
  my @color_save = "";
  if ( -f "$file_color_save" ) {
    open( FHC, "< $file_color_save" ) || error( "file cannot be opened : $file_color_save " . __FILE__ . ":" . __LINE__ ) && return 0;
    @color_save = <FHC>;
    close(FHC);
  }

  my $type_edt = 0;
  if ( -f $type_edt_filel ) {
    $type_edt = 1;
  }

  # open file for writing list of lpars
  open( FHL, ">> $list" ) || error( "Can't open $list : $!" . __FILE__ . ":" . __LINE__ ) && return 0;

  my $header = "CPU Custom group $group: last $text";
  $header = "MEM Custom group $group: last $text" if $item eq "mem";

  my $file    = "";
  my $i       = 0;
  my $lpar    = "";
  my $lparn   = "";
  my $cmd     = "";
  my $cmd_xpo = "";
  my $j       = 0;

  my $vertical_label = "CPU GHz";
  my $comm_text      = "Utilization in CPU GHz";
  if ( $item eq "mem" ) {
    $vertical_label = "Memory in GB";
    $comm_text      = "Memory in GB    ";
  }
  $cmd_xpo = "xport ";
  if ( -f "$basedir/tmp/rrdtool-xport-showtime" ) {
    $cmd_xpo .= " --showtime";
  }
  $cmd_xpo .= " --start now-1$type";
  $cmd_xpo .= " --end now-1$type+1$type";
  $cmd_xpo .= " --step $step_new";
  $cmd_xpo .= " --maxrows 65000";

  my $lim_org = $lim;
  $lim =~ s/\.//;
  $lim =~ s/i/l/;

  $cmd .= "graph \\\"$name.png\\\"";
  $cmd .= " --title \\\"$header\\\"";
  $cmd .= " --start now-1$type";
  $cmd .= " --end now-1$type+1$type";
  $cmd .= " --imgformat PNG";
  $cmd .= " $disable_rrdtool_tag_agg";
  $cmd .= " --slope-mode";
  $cmd .= " --width=400";
  $cmd .= " --height=150";
  $cmd .= " --step=$step_new";
  $cmd .= " --lower-limit=0.00";
  $cmd .= " --color=BACK#$pic_col";
  $cmd .= " --color=SHADEA#$pic_col";
  $cmd .= " --color=SHADEB#$pic_col";
  $cmd .= " --color=CANVAS#$pic_col";
  $cmd .= " --alt-autoscale-max";
  $cmd .= " --upper-limit=0.1";
  $cmd .= " --vertical-label=\\\"$vertical_label\\\"";
  $cmd .= " --units-exponent=1.00";
  $cmd .= " --alt-y-grid";
  $cmd .= " --x-grid=$xgrid";
  $cmd .= " COMMENT:\\\"$comm_text                         \\l\\\"";
  $cmd .= " COMMENT:\\\"  Server                                               avrg     max\\l\\\"";

  my $gtype = "AREA";
  my $index = 0;

  my @lpars_graph_local = @lpars_graph;

  # print STDERR "3391 custom.pl \@lpars_graph @lpars_graph\n";

  my %uniq_files;
  my $newest_file_timestamp = 0;

  # do not sort it HERE!! there is several arrays, sorting lpars_graph is not enough!!! --PH
  foreach my $file_cycl (@lpars_graph_local) {

    # print STDERR "3399 custom.pl \$file_cycl $file_cycl\n";
    # /home/lpar2rrd/lpar2rrd/data/Linux/no_hmc/kvm.xorux.com
    my $server      = ( split( /\//, $file_cycl ) )[-1];
    my $server_name = $server;

    $server = "$server";

    #print STDERR "3407 custom.pl \$server $server\n";

    if ( $server eq '' ) {
      $index++;
      next;    #some trash
    }

    my $file = "$file_cycl/mem.mmm";

    if ( !-f $file ) {
      $index++;
      next;
    }

    # avoid old lpars which do not exist in the period
    my $rrd_upd_time = ( stat("$file") )[9];
    if ( $rrd_upd_time < $req_time ) {
      $index++;
      next;
    }

    # add spaces to lpar name to have 25 chars total (for formating graph legend)
    #$lpar = $lpars_graph_server[$index];

    $lpar = $server_name;
    my $lpar_orig = $lpar;

    my $lpar_proc = "$lpar";    # for html legend
    $lpar_proc =~ s/%/%%/g;
    $lpar_proc =~ s/:/\\:/g;
    $lpar_proc =~ s/\&\&1/\//g;

    $lpar =~ s/\&\&1/\//g;
    for ( my $k = length($lpar); $k < 25; $k++ ) {
      $lpar .= " ";
    }

    #$lpar .= "   ";
    #$lpar .= $vm_name;
    $lpar =~ s/\&\&1/\//g;

    # to keep same count of characters
    $lpar =~ s/\\:/:/g;
    $lpar = sprintf( "%-50s", $lpar );
    $lpar =~ s/:/\\:/g;

    my $lpar_space = $lpar;

    my $lpar_space_proc = $server_name;
    $lpar_space_proc =~ s/\:/\\:/g;

    if ( exists $uniq_files{"$file"} ) {    # check duplicities
      $index++;
      next;
    }
    $uniq_files{"$file"} = 1;
    $lparn .= " ";
    print FHL "$file\n";

    # print STDERR "3461 custom.pl $server $rrd_upd_time $req_time $act_time \$lpar_space_proc $lpar_space_proc \$file $file\n" ; # if ( $DEBUG == 1);

    if ( ( length($lpar_v) + 1 ) == length($comm) && length($lparn) == length($comm) ) {
      copy_source_org( $webdir, $tmpdir, $basedir, $lim_org, $lim, $group );
      last;
    }

    if ( $type =~ "d" ) {
      RRDp::cmd qq(last "$file");
      my $last_tt = RRDp::read;
      chomp($$last_tt);
      $newest_file_timestamp = $$last_tt if $$last_tt > $newest_file_timestamp;
    }

    my $file_legend = $server;
    $file_legend =~ s/%/%%/g;
    $file_legend =~ s/:/\\:/g;

    # Exclude items (lpars/pool) if there is no data for last year for all HMCs
    #if ( LPM_easy_exclude($file_pth,$act_time-31622400) == 0 ) {
    #  $index++;
    #  next;    # there is not updated rrd file for last year, skip that item
    #}

    # Found out stored color index to keep same color for the volume across all graphs
    my $file_color = $server;
    $file_color =~ s/\.mmm$//;
    $file_color =~ s/\\//g;
    $file_color =~ s/:/===========doublecoma=========/g;
    my $color_indx_found = -1;
    $color_indx = 0;
    foreach my $line_col (@color_save) {
      chomp($line_col);
      if ( $line_col eq '' || $line_col !~ m/ : / ) {
        next;
      }
      $color_indx++;
      ( my $color_indx_found_act, my $volume_name_save ) = split( / : /, $line_col );

      # do not use here $volume_name_save '' as this does not work when volume id is zero!
      if ( $volume_name_save =~ m/^$file_color$/ ) {
        $color_indx_found = $color_indx_found_act;
        $color_indx       = $color_indx_found;
        last;
      }
    }
    if ( $color_indx_found == -1 ) {
      $color_file_change = 1;
      $color_save[$color_indx] = $color_indx . " : " . $file_color;
    }
    while ( $color_indx > $color_max ) {
      $color_indx = $color_indx - $color_max;
    }

    # end color

    if ( $type_edt == 0 && $lparno == 4 ) {
      copy_source_org( $webdir, $tmpdir, $basedir, $lim_org, $lim, $group );
      last;
    }
    $lparno++;

    # new system
    my $wrkdir_managedname_host_file = "$file";
    $wrkdir_managedname_host_file =~ s/:/\\:/g;

    #my $wrkdir_managedname_host_file_legend = $wrkdir_managedname_host_file;
    my $wrkdir_managedname_host_file_legend = "$server";
    $wrkdir_managedname_host_file_legend =~ s/%/%%/g;
    $wrkdir_managedname_host_file_legend =~ s/:/\\:/g;

    my $item_leg = "multihmclpar_linux_mem";

    # bulid RRDTool cmd
    if ( $item eq "mem" ) {
      $cmd .= " DEF:utiltot_use${i}=\\\"$wrkdir_managedname_host_file\\\":nuse:AVERAGE";
      $cmd .= " CDEF:utiltot${i}=utiltot_use${i},1048576,/";
      $item_leg = "multihmclpar_linux_mem";
    }
    else {
      $cmd .= " DEF:utiltot_mhz${i}=\\\"$wrkdir_managedname_host_file\\\":CPU_usage:AVERAGE";
      $cmd .= " CDEF:utiltot_ghz${i}=utiltot_mhz${i},1000,/";
      $cmd .= " CDEF:utiltot${i}=utiltot_mhz${i},1000,/";                                       # since 4.74- (u)
    }

    $cmd .= " $gtype:utiltot${i}$color[$color_indx]:\\\"$lpar_space\\\"";

    push @color_save, $lpar_orig;

    $cmd .= " PRINT:utiltot${i}:AVERAGE:\"%3.2lf $delimiter $item_leg $delimiter $server_name $delimiter $lpar_space_proc\"";
    $cmd .= " PRINT:utiltot${i}:AVERAGE:\\\"%3.2lf $delimiter $color[$color_indx] $delimiter $wrkdir_managedname_host_file_legend\\\"";
    $cmd .= " PRINT:utiltot${i}:MAX:\" %3.2lf $delimiter\"";

    $cmd .= " GPRINT:utiltot${i}:AVERAGE:\\\"%3.2lf \\\"";
    $cmd .= " GPRINT:utiltot${i}:MAX:\\\" %3.2lf \\l\\\"";

    $cmd_xpo .= " DEF:utiltot_use${i}=\\\"$wrkdir_managedname_host_file\\\":nuse:AVERAGE";

    $cmd_xpo .= " \\\"CDEF:utiltot_ghz${i}=utiltot_use${i},1000,/\\\"";
    $cmd_xpo .= " \\\"CDEF:utiltot${i}=utiltot_mhz${i},1000,/\\\"";
    $cmd_xpo .= " \\\"XPORT:utiltot${i}:$lpar\\\"";

    # put carriage return after each second lpar in the legend
    if ( $j == 1 ) {
      $j = 0;
    }
    else {
      $j++;
    }
    $gtype = "STACK";
    $i++;
    $color_indx = ++$color_indx % ( $color_max + 1 );

  }

  #  $cmd_sum =~ s/\\"/"/g;
  $cmd_xpo =~ s/\\"/"/g;

  close(FHL);
  my $FH;

  # store XPORT for future usage in Hist reports (detail-graph-cgi.pl)
  if ( "$type" =~ "d" ) {

    # only daily one
    my $tmp_file_xpo = "$tmpdir/custom-group-$group-$type-xpo.cmd";
    $tmp_file_xpo = "$tmpdir/custom-group-vmmem-$group-$type-xpo.cmd" if $item eq "mem";
    open( FH, "> $tmp_file_xpo" ) || error( "Can't open $tmp_file_xpo : $!" . __FILE__ . ":" . __LINE__ ) && return 0;
    print FH "$cmd_xpo\n";
    close(FH);
  }

  if ( $newest_file_timestamp > 0 ) {
    my $l = localtime($newest_file_timestamp);

    # following must be for RRD 1.2+
    $l =~ s/:/\\:/g;
    $updated = " COMMENT:\\\"  Updated\\\: $l \\\"";
  }

  $cmd .= " $updated";

  if ( "$type" =~ "d" ) {
    if ( $j == 1 ) {
      $cmd .= " COMMENT:\\\" \\l\\\"";
    }
  }
  $cmd .= " HRULE:0#000000";

  # $cmd .= " VRULE:0#000000";  --> it is causing sigsegv on linuxeS
  $cmd =~ s/\\"/"/g;

  # print STDERR "3525 custom.pl $tmp_file\n" ;
  open( FH, "> $tmp_file" ) || error( "Can't open $tmp_file : $!" . __FILE__ . ":" . __LINE__ ) && return 0;
  print FH "$cmd\n";
  close(FH);

  if ( !get_lpar_num() ) {
    if ( $index > 4 ) {
      if ( !-f "$webdir/custom/$group/$lim" ) {
        copy_source_org( $webdir, $tmpdir, $basedir, $lim_org, $lim, $group );
      }
    }
  }

  # write colors into a file
  if ( $color_file_change == 1 ) {
    open( FHC, "> $file_color_save" ) || error( "file cannot be created :  $file_color_save " . __FILE__ . ":" . __LINE__ ) && return 0;
    foreach my $line_cs (@color_save) {
      chomp($line_cs);    # it must be there, somehow appear there \n ...
      if ( $line_cs eq '' ) {
        next;
      }
      if ( $line_cs =~ m/ : / ) {
        print FHC "$line_cs\n";
      }
    }
    close(FHC);
  }

  # colours

  #
  # do not execute it here
  # execute it in the run time based on cmd stored in $tmp_file
  #

  return 1;
}

sub multiview_linux_lan {
  my $group    = shift;
  my $name     = shift;
  my $type     = shift;
  my $type_sam = shift;
  my $act_time = shift;
  my $step_new = shift;
  my $text     = shift;
  my $xgrid    = shift;
  my $item     = shift;
  my $req_time = 0;
  my $comm     = "COMM ";
  $color_indx = 0;                                                        # prepare color index
  my $list              = "$webdir/custom/$group/list.txt";
  my $lim               = ".li";
  my $color_file_change = 0;
  my $file_color_save   = "$basedir/tmp/custom-group-$group-$item.col";
  my $lparno            = 0;
  my $alias_file        = "$basedir/etc/alias.cfg";
  my @alias             = ();                                             # alias LPAR names

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
    $req_time  = $act_time - 31536000;
    $skip_time = $YEAR_REFRESH;
  }

  # print "3694 $group, $name, $type, $type_sam, $item\n";
  # my $tmp_file = "$tmpdir/custom-group-$item-os-$group-$type.cmd";
  my $tmp_file = "$tmpdir/custom-group-$item-os-$group-$type.cmd";

  # do not update weekly/monthly/yearly command files each run
  if ( -f "$tmp_file" ) {
    my $tmp_time = ( stat("$tmp_file") )[9];
    if ( ( $act_time - $tmp_time ) < $skip_time ) {
      print "                        skipped this time : ( $act_time - $tmp_time ) < $skip_time \n";
      return 0;
    }
  }

  # from detail-graph.pl
  # read aliases
  #if ( -f "$alias_file" && open( FHC, "< $alias_file" )) {
  #  while( <FHC> )  {
  #    next if $_ !~ /^LPAR:/;
  #    my $line = $_;
  #    $line =~ s/^LPAR://;
  #    chomp $line;
  #    push @alias, $line;
  #  }
  #  close(FHC);
  #}

  # open a file with stored colours
  my @color_save = "";
  if ( -f "$file_color_save" ) {
    open( FHC, "< $file_color_save" ) || error( "file cannot be opened : $file_color_save " . __FILE__ . ":" . __LINE__ ) && return 0;
    @color_save = <FHC>;
    close(FHC);
  }

  my $type_edt = 0;
  if ( -f $type_edt_filel ) {
    $type_edt = 1;
  }

  open( FHL, ">> $list" ) || error( "Can't open $list : $!" . __FILE__ . ":" . __LINE__ ) && return 0;

  # print "3735 \$lpars_graph_type[0] $lpars_graph_type[0]\n";

  if ( $lpars_graph_type[0] !~ /LINUX/ ) {
    return 0;    # only for LPARs
  }

  my $header = "LAN Custom group $group: last $text";
  $header = "SAN Custom group $group: last $text"         if $item eq "san1";
  $header = "IOPS/Frames Custom group $group: last $text" if $item eq "san2";

  my $file  = "";
  my $i     = 0;
  my $j     = 0;
  my $lpar  = "";
  my $lparn = "";
  my $cmd   = "";
  my $cmdx  = "";

  my $filter = $filter_max_lansan;

  my $ds_name1 = "recv_bytes";
  my $ds_name2 = "trans_bytes";
  my $fpn      = "lan-";          # according to $item

  my $g_format = "6.2lf";
  my $divider  = 1000000;
  if ( $item =~ "^lan" ) {
    $ds_name2 = "recv_bytes";
    $ds_name1 = "trans_bytes";
  }
  my $vertical_label = "Read - Bytes/sec - Write";

  if ( $item =~ m/^san/ ) {
    $fpn = "san-";
  }
  if ( $item =~ m/^lan/ ) {
    $fpn = "lan-";
  }

  if ( $item =~ m/^san2/ ) {
    $g_format       = "6.0lf";
    $divider        = 1;
    $fpn            = "san-";
    $ds_name1       = "iops_in";
    $ds_name2       = "iops_out";
    $vertical_label = "Read - IOPS - Write";
    $filter         = $filter_max_iops;
  }

  if ( $type =~ m/y/ ) {

    # lower limits for yearly graphs as they are averaged ....
    $filter = $filter / 10;
  }
  if ( $type =~ m/m/ ) {

    # lower limits for monthly graphs as they are averaged ....
    $filter = $filter / 2;
  }

  my $index = 0;

  my $lim_org = $lim;
  $lim =~ s/\.//;
  $lim =~ s/i/l/;

  $cmd .= "graph \\\"$name.png\\\"";
  $cmd .= " --title \\\"$header\\\"";
  $cmd .= " --start now-1$type";
  $cmd .= " --end now-1$type+1$type";
  $cmd .= " --imgformat PNG";
  $cmd .= " $disable_rrdtool_tag_agg";
  $cmd .= " --slope-mode";
  $cmd .= " --width=400";
  $cmd .= " --height=150";
  $cmd .= " --step=$step_new";
  $cmd .= " --lower-limit=0";
  $cmd .= " --color=BACK#$pic_col";
  $cmd .= " --color=SHADEA#$pic_col";
  $cmd .= " --color=SHADEB#$pic_col";
  $cmd .= " --color=CANVAS#$pic_col";

  #$cmd .= " --alt-autoscale-max";
  $cmd .= " --vertical-label=\\\"$vertical_label\\\"";

  #$cmd .= " --units-exponent=1.00";
  $cmd .= " --alt-y-grid";
  $cmd .= " --x-grid=$xgrid";

  #$cmd .= " --base=1024";

  if ( $item =~ m/^san1$/ || $item =~ m/^lan$/ ) {
    $cmd .= " COMMENT:\\\"[MB/sec]\\l\\\"";
  }
  if ( $item =~ m/^san2$/ ) {
    $cmd .= " COMMENT:\\\"[IO per sec]\\l\\\"";
  }
  $cmd .= " COMMENT:\\\"  Server                       LPAR int                   avrg     max\\l\\\"";

  my @gtype;
  $gtype[0] = "AREA";
  $gtype[1] = "STACK";
  my $sh_pools          = 0;              # identificator of shared pool
  my @lpars_graph_local = @lpars_graph;
  my $updated           = " ";

  my ( @recb, @trab, @avgx, @avgy );
  my $lnx     = 0;
  my $index_l = 0;
  my %uniq_files;
  my $newest_file_timestamp = 0;

  # print "3847 \@lpars_graph_local @lpars_graph_local\n";

  # do not sort it HERE!! there is several arrays, sorting lpars_graph is not enough!!! --PH
  foreach my $file_tmp (@lpars_graph_local) {
    my $file = $file_tmp;    # must be here to allocate new space and do not make changes in @lpars_graph

    if ( $file eq '' ) {
      $index++;
      next;                  #some trash
    }

    if ( $file =~ m/\/mem.rr/ || $file =~ m/\/pool.rr/ ) {
      $index++;
      next;                  # include only real lpars
    }

    #print "001 $file\n";
    if ( !-f "$file/mem.mmm" ) {
      $index++;
      next;
    }
    if ( exists $uniq_files{"$file"} ) {    # check duplicities
      $index++;
      next;
    }
    $uniq_files{"$file"} = 1;
    $lparn .= " ";

    if ( ( length($lpar_v) + 1 ) == length($comm) && length($lparn) == length($comm) ) {
      copy_source_org( $webdir, $tmpdir, $basedir, $lim_org, $lim, $group );
      last;
    }
    $index_l++;

    my $item_tmp = $item;
    $item_tmp =~ s/[1,2]$//;

    my $file_space = $file;
    if ( $file_space =~ m/ / ) {    # workaround for name with a space inside, nothing else works, grrr
      $file_space = "\"" . $file . "\"";
    }

    # print "005 $file/$item_tmp-*.mmm\n \$file,\$item_tmp,\n@lpars_graph_local,\n";
    my @files_adapter = <$file_space/$item_tmp-*.mmm>;

    # print "005x \@files_adapter @files_adapter,\n";

    if ( $type_edt == 0 && $lparno == 4 ) {
      copy_source_org( $webdir, $tmpdir, $basedir, $lim_org, $lim, $group );
      last;
    }
    $lparno++;

    foreach my $file_adapter (@files_adapter) {

      #print "002 $file_adapter\n";
      if ( !-f "$file_adapter" ) {
        next;
      }

      # avoid old lpars which do not exist in the period
      my $rrd_upd_time = ( stat("$file_adapter") )[9];
      if ( $rrd_upd_time < $req_time ) {

        #$index++;
        next;
      }

      my $adapter_name = basename($file_adapter);
      $adapter_name =~ s/^san-//;
      $adapter_name =~ s/^lan-//;
      $adapter_name =~ s/\.mmm$//;

      # add spaces to lpar name to have 25 chars total (for formating graph legend)
      $lpar = $lpars_graph_server[$index];

      # add alias to lpar name if exists
      my @choice = grep {/^$lpars_graph_name[$index]:/} @alias;

      # print "1121 \$lpar $lpars_graph_name[$index] \@choice @choice\n";
      if ( scalar @choice > 1 ) {
        error( "LPAR $lpars_graph_name[$index] has more aliases @choice " . __FILE__ . ":" . __LINE__ );
      }
      my $my_alias = "";
      if ( defined $choice[0] && $choice[0] ne "" ) {
        $choice[0] =~ s/\\//g;                            # if any colon is backslashed
        $choice[0] =~ s/^$lpars_graph_name[$index]://;    # only alias
        if ($test_legend) {
          $choice[0] = substr( $choice[0], 1, $max_alias_length );
        }
        $my_alias = "[" . "$choice[0]" . "]";
      }

      my $lpar_proc = "$lpar $delimiter " . "$lpars_graph_name[$index]$my_alias $delimiter $adapter_name";    # for html legend
      $lpar_proc =~ s/%/%%/g;
      $lpar_proc =~ s/:/\\:/g;
      $lpar_proc =~ s/\&\&1/\//g;

      $lpar =~ s/\&\&1/\//g;
      for ( my $k = length($lpar); $k < 25; $k++ ) {
        $lpar .= " ";
      }
      $lpar .= "   ";
      $lpar .= "$lpars_graph_name[$index]$my_alias $adapter_name";
      $lpar =~ s/\&\&1/\//g;

      # to keep same count of characters
      $lpar =~ s/\\:/:/g;
      $lpar = sprintf( "%-48s", $lpar );
      $lpar =~ s/:/\\:/g;

      for ( my $k = length($lpar); $k < 50; $k++ ) {
        $lpar .= " ";
      }

      #print "11 $file_adapter $rrd_upd_time $req_time $act_time\n" if ( $DEBUG == 1);

      if ( $type =~ "d" ) {
        RRDp::cmd qq(last "$file_adapter");
        my $last_tt = RRDp::read;
        chomp($$last_tt);
        $newest_file_timestamp = $$last_tt if $$last_tt > $newest_file_timestamp;
      }

      # Found out stored color index to keep same color for the volume across all graphs
      my $file_color = $file_adapter;
      $file_color =~ s/\.r..$//;
      $file_color =~ s/\\//g;
      $file_color =~ s/:/===========doublecoma=========/g;
      my $color_indx_found = -1;
      $color_indx = 0;
      foreach my $line_col (@color_save) {
        chomp($line_col);
        if ( $line_col eq '' || $line_col !~ m/ : / ) {
          next;
        }
        $color_indx++;
        ( my $color_indx_found_act, my $volume_name_save ) = split( / : /, $line_col );

        # do not use here $volume_name_save '' as this does not work when volume id is zero!
        if ( $volume_name_save =~ m/^$file_color$/ ) {
          $color_indx_found = $color_indx_found_act;
          $color_indx       = $color_indx_found;
          last;
        }
      }
      if ( $color_indx_found == -1 ) {
        $color_file_change = 1;
        $color_save[$color_indx] = $color_indx . " : " . $file_color;
      }
      while ( $color_indx > $color_max ) {
        $color_indx = $color_indx - $color_max;
      }

      # end color

      print FHL "$file_adapter\n";
      $file_adapter =~ s/:/\\:/g;

      my $file_legend = $file_adapter;
      $file_legend =~ s/%/%%/g;

      # bulid RRDTool cmd
      $recb[$i] = "rcb${i}";
      $trab[$i] = "trb${i}";
      $avgx[$i] = "avg${i}";
      $avgy[$i] = "avgy${i}";
      $cmd .= " DEF:$recb[$i]_nf=\\\"$file_adapter\\\":$ds_name1:AVERAGE";
      $cmd .= " DEF:$trab[$i]_nf=\\\"$file_adapter\\\":$ds_name2:AVERAGE";
      $cmd .= " CDEF:$recb[$i]=$recb[$i]_nf,$filter,GT,UNKN,$recb[$i]_nf,IF";
      $cmd .= " CDEF:$trab[$i]=$trab[$i]_nf,$filter,GT,UNKN,$trab[$i]_nf,IF";
      $cmd .= " CDEF:$recb[$i]-neg=$recb[$i],-1,*";
      $cmd .= " CDEF:$recb[$i]-mil=$recb[$i],$divider,/";
      $cmd .= " CDEF:$trab[$i]-mil=$trab[$i],$divider,/";
      $cmd .= " $gtype[$i>0]:$recb[$i]-neg$color[++$color_indx % ($color_max +1)]:\\\"R $lpar\\\"";
      $cmd .= " GPRINT:$recb[$i]-mil:AVERAGE:%$g_format";
      $cmd .= " GPRINT:$recb[$i]-mil:MAX:%$g_format\\l";

      $cmd .= " PRINT:$recb[$i]-mil:AVERAGE:\\\"%$g_format $delimiter multiview-ent-$item $delimiter R $lpar_proc\\\"";                      # for html legend
      $cmd .= " PRINT:$recb[$i]-mil:AVERAGE:\\\"%$g_format $delimiter $color[$color_indx % ($color_max +1)] $delimiter $file_legend\\\"";    # for html legend
      $cmd .= " PRINT:$recb[$i]-mil:MAX:\\\"%$g_format $delimiter\\\"";                                                                      # for html legend

      $cmd .= " STACK:$lnx$color[++$color_indx % ($color_max +1)]:\\\"W $lpar\\\"";

      $cmd .= " GPRINT:$trab[$i]-mil:AVERAGE:%$g_format";
      $cmd .= " GPRINT:$trab[$i]-mil:MAX:%$g_format\\l";

      $cmd .= " PRINT:$trab[$i]-mil:AVERAGE:\\\"%$g_format $delimiter multiview-ent-$item $delimiter W $lpar_proc\\\"";                      # for html legend
      $cmd .= " PRINT:$trab[$i]-mil:AVERAGE:\\\"%$g_format $delimiter $color[$color_indx % ($color_max +1)] $delimiter $file_legend\\\"";    # for html legend
      $cmd .= " PRINT:$trab[$i]-mil:MAX:\\\"%$g_format $delimiter\\\"";                                                                      # for html legend

      if ( $i == 0 ) {
        $cmdx .= " LINE1:$lnx:";
      }
      $cmdx .= " $gtype[$i>0]:$trab[$i++]$color[$color_indx % ($color_max +1)]:";
    }
    $index++;
    if ( !get_lpar_num() && $index_l > 4 ) {
      last;
    }
  }
  $cmd .= $cmdx;

  close(FHL);

  if ( $i == 0 ) {
    print "creating cgraph: " . scalar localtime() . " custom:$group $item-os $type: no any source found, skipping\n";
    return 0;    # nothing has been found
  }
  if ( $newest_file_timestamp > 0 ) {
    my $l = localtime($newest_file_timestamp);

    # following must be for RRD 1.2+
    $l =~ s/:/\\:/g;
    $updated = " COMMENT:\\\"  Updated\\\: $l \\\"";
  }

  $cmd .= " $updated";
  $cmd .= " HRULE:0#000000";

  # $cmd .= " VRULE:0#000000";  --> it is causing sigsegv on linuxeS
  $cmd =~ s/\\"/"/g;

  open( FH, "> $tmp_file" ) || error( "Can't open $tmp_file : $!" . __FILE__ . ":" . __LINE__ ) && return 0;
  print FH "$cmd\n";
  close(FH);

  #
  # do not execute it here
  # execute it in the run time based on cmd stored in $tmp_file
  #

  # write colors into a file
  if ( $color_file_change == 1 ) {
    open( FHC, "> $file_color_save" ) || error( "file cannot be created :  $file_color_save " . __FILE__ . ":" . __LINE__ ) && return 0;
    foreach my $line_cs (@color_save) {
      chomp($line_cs);    # it must be there, somehow appear there \n ...
      if ( $line_cs eq '' ) {
        next;
      }
      if ( $line_cs =~ m/ : / ) {
        print FHC "$line_cs\n";
      }
    }
    close(FHC);
  }

  # colours

  return 1;
}

sub multiview_vims {
  my $group    = shift;
  my $name     = shift;
  my $type     = shift;
  my $type_sam = shift;
  my $act_time = shift;
  my $step_new = shift;
  my $text     = shift;
  my $xgrid    = shift;
  my $item     = shift;

  $item = "" if !defined $item;

  my $req_time = 0;
  my $comm     = "COMM ";
  $color_indx = 0;    # clear color index
  my $list              = "$webdir/custom/$group/list.txt";
  my $lim               = ".li";
  my $updated           = "";
  my $color_file_change = 0;
  my $file_color_save   = "$basedir/tmp/custom-group-$group.col";
  my $all_vmware_VMs    = "vmware_VMs";
  my $lparno            = 0;

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

  my $tmp_file = "$tmpdir/custom-group-$group-$type.cmd";
  $tmp_file = "$tmpdir/custom-group-vmmem-$group-$type.cmd" if $item eq "mem";

  # do not update weekly/monthly/yearly command files each run
  if ( -f "$tmp_file" ) {
    my $tmp_time = ( stat("$tmp_file") )[9];
    if ( ( $act_time - $tmp_time ) < $skip_time ) {
      print "                        skipped this time : ( $act_time - $tmp_time ) < $skip_time \n";
      return 0;
    }
  }

  # open a file with stored colours
  my @color_save = "";
  if ( -f "$file_color_save" ) {
    open( FHC, "< $file_color_save" ) || error( "file cannot be opened : $file_color_save " . __FILE__ . ":" . __LINE__ ) && return 0;
    @color_save = <FHC>;
    close(FHC);
  }

  my $type_edt = 0;
  if ( -f $type_edt_filev ) {
    $type_edt = 1;
  }

  # open file for writing list of lpars
  open( FHL, "> $list" ) || error( "Can't open $list : $!" . __FILE__ . ":" . __LINE__ ) && return 0;

  my $header = "CPU Custom group $group: last $text";
  $header = "MEM Custom group $group: last $text" if $item eq "mem";

  my $file    = "";
  my $i       = 0;
  my $lpar    = "";
  my $lparn   = "";
  my $cmd     = "";
  my $cmd_xpo = "";
  my $j       = 0;

  my $vertical_label = "CPU GHz";
  my $comm_text      = "Utilization in CPU GHz";
  if ( $item eq "mem" ) {
    $vertical_label = "Active Memory in GB";
    $comm_text      = "Active Memory in GB    ";
  }
  $cmd_xpo = "xport ";
  if ( -f "$basedir/tmp/rrdtool-xport-showtime" ) {
    $cmd_xpo .= " --showtime";
  }
  $cmd_xpo .= " --start now-1$type";
  $cmd_xpo .= " --end now-1$type+1$type";
  $cmd_xpo .= " --step $step_new";
  $cmd_xpo .= " --maxrows 65000";

  my $lim_org = $lim;
  $lim =~ s/\.//;
  $lim =~ s/i/l/;

  $cmd .= "graph \\\"$name.png\\\"";
  $cmd .= " --title \\\"$header\\\"";
  $cmd .= " --start now-1$type";
  $cmd .= " --end now-1$type+1$type";
  $cmd .= " --imgformat PNG";
  $cmd .= " $disable_rrdtool_tag_agg";
  $cmd .= " --slope-mode";
  $cmd .= " --width=400";
  $cmd .= " --height=150";
  $cmd .= " --step=$step_new";
  $cmd .= " --lower-limit=0.00";
  $cmd .= " --color=BACK#$pic_col";
  $cmd .= " --color=SHADEA#$pic_col";
  $cmd .= " --color=SHADEB#$pic_col";
  $cmd .= " --color=CANVAS#$pic_col";
  $cmd .= " --alt-autoscale-max";
  $cmd .= " --upper-limit=0.1";
  $cmd .= " --vertical-label=\\\"$vertical_label\\\"";
  $cmd .= " --units-exponent=1.00";
  $cmd .= " --alt-y-grid";
  $cmd .= " --x-grid=$xgrid";
  $cmd .= " COMMENT:\\\"$comm_text                         \\l\\\"";
  $cmd .= " COMMENT:\\\"  Server                       VM                      avrg     max\\l\\\"";

  my $gtype = "AREA";
  my $index = 0;

  my @lpars_graph_local = @lpars_graph;

  # print STDERR "2418 custom.pl \@lpars_graph @lpars_graph\n";

  my %uniq_files;
  my $newest_file_timestamp = 0;

  # do not sort it HERE!! there is several arrays, sorting lpars_graph is not enough!!! --PH
  foreach my $file (@lpars_graph_local) {

    # print STDERR "2426 custom.pl \$file $file\n";
    # /home/lpar2rrd/lpar2rrd/data/10.100.1.18/10.100.1.30/502a7728-9916-34fb-4832-e1039ad423a5,VM12-CZSI-00-01,vm-4756
    ( $file, my $vm_name, undef ) = split( /,/, $file );
    my $server      = ( split( /\//, $file ) )[-3];
    my $hmc_vm      = ( split( /\//, $file ) )[-2];
    my $server_name = $server;

    my $file_name = ( split( /\//, $file ) )[-1];
    $file = "$wrkdir/$all_vmware_VMs/$file_name.rrm";

    # print STDERR "2432 custom.pl \$file $file \$server $server \$vm_name $vm_name\n";
    if ( $file eq '' ) {
      $index++;
      next;    #some trash
    }

    if ( !-f $file ) {
      $index++;
      next;
    }

    # avoid old lpars which do not exist in the period
    my $rrd_upd_time = ( stat("$file") )[9];
    if ( $rrd_upd_time < $req_time ) {
      $index++;
      next;
    }

    # add spaces to lpar name to have 25 chars total (for formating graph legend)
    #$lpar = $lpars_graph_server[$index];

    $lpar = $server_name;
    my $lpar_orig = $lpar;

    my $lpar_proc = "$lpar $delimiter " . "$vm_name";    # for html legend
    $lpar_proc =~ s/%/%%/g;
    $lpar_proc =~ s/:/\\:/g;
    $lpar_proc =~ s/\&\&1/\//g;

    $lpar =~ s/\&\&1/\//g;
    for ( my $k = length($lpar); $k < 25; $k++ ) {
      $lpar .= " ";
    }
    $lpar .= "   ";
    $lpar .= $vm_name;
    $lpar =~ s/\&\&1/\//g;

    # to keep same count of characters
    $lpar =~ s/\\:/:/g;
    $lpar = sprintf( "%-50s", $lpar );
    $lpar =~ s/:/\\:/g;

    my $lpar_space = $lpar;

    #my $lpar_space_proc = $lpar_space;
    my $lpar_space_proc = $vm_name;

    $lpar_space_proc =~ s/\:/\\:/g;

    if ( exists $uniq_files{"$file"} ) {    # check duplicities
      $index++;
      next;
    }
    $uniq_files{"$file"} = 1;
    $lparn .= " ";
    print FHL "$file\n";

    # print STDERR "2477 custom.pl $file $rrd_upd_time $req_time $act_time \$lpar_space_proc $lpar_space_proc\n" ; # if ( $DEBUG == 1);

    if ( ( length($lpar_v) + 1 ) == length($comm) && length($lparn) == length($comm) ) {
      copy_source_org( $webdir, $tmpdir, $basedir, $lim_org, $lim, $group );
      last;
    }

    if ( $type =~ "d" ) {
      RRDp::cmd qq(last "$file");
      my $last_tt = RRDp::read;
      chomp($$last_tt);
      $newest_file_timestamp = $$last_tt if $$last_tt > $newest_file_timestamp;
    }

    my $file_legend = $file;
    $file_legend =~ s/%/%%/g;
    $file_legend =~ s/:/\\:/g;

    # Exclude items (lpars/pool) if there is no data for last year for all HMCs
    #if ( LPM_easy_exclude($file_pth,$act_time-31622400) == 0 ) {
    #  $index++;
    #  next;    # there is not updated rrd file for last year, skip that item
    #}

    # Found out stored color index to keep same color for the volume across all graphs
    my $file_color = $file;
    $file_color =~ s/\.r..$//;
    $file_color =~ s/\\//g;
    $file_color =~ s/:/===========doublecoma=========/g;
    my $color_indx_found = -1;
    $color_indx = 0;
    foreach my $line_col (@color_save) {
      chomp($line_col);
      if ( $line_col eq '' || $line_col !~ m/ : / ) {
        next;
      }
      $color_indx++;
      ( my $color_indx_found_act, my $volume_name_save ) = split( / : /, $line_col );

      # do not use here $volume_name_save '' as this does not work when volume id is zero!
      if ( $volume_name_save =~ m/^$file_color$/ ) {
        $color_indx_found = $color_indx_found_act;
        $color_indx       = $color_indx_found;
        last;
      }
    }
    if ( $color_indx_found == -1 ) {
      $color_file_change = 1;
      $color_save[$color_indx] = $color_indx . " : " . $file_color;
    }
    while ( $color_indx > $color_max ) {
      $color_indx = $color_indx - $color_max;
    }

    # end color

    if ( $type_edt == 0 && $lparno == 4 ) {
      copy_source_org( $webdir, $tmpdir, $basedir, $lim_org, $lim, $group );
      last;
    }
    $lparno++;

    # new system
    my $wrkdir_managedname_host_file = "$wrkdir/$all_vmware_VMs/$file_name.rrm";
    $wrkdir_managedname_host_file =~ s/:/\\:/g;

    #my $wrkdir_managedname_host_file_legend = $wrkdir_managedname_host_file;
    my $wrkdir_managedname_host_file_legend = "$wrkdir/$server/$hmc_vm/$file_name.rrm";
    $wrkdir_managedname_host_file_legend =~ s/%/%%/g;
    $wrkdir_managedname_host_file_legend =~ s/:/\\:/g;

    my $item_leg = "multihmclpar_vm";

    # bulid RRDTool cmd
    if ( $item eq "mem" ) {
      $cmd .= " DEF:utiltot_mhz${i}=\\\"$wrkdir_managedname_host_file\\\":Memory_active:AVERAGE";
      $cmd .= " CDEF:utiltot${i}=utiltot_mhz${i},1048576,/";
      $item_leg = "multihmclpar_mem";
    }
    else {
      $cmd .= " DEF:utiltot_mhz${i}=\\\"$wrkdir_managedname_host_file\\\":CPU_usage:AVERAGE";
      $cmd .= " CDEF:utiltot_ghz${i}=utiltot_mhz${i},1000,/";
      $cmd .= " CDEF:utiltot${i}=utiltot_mhz${i},1000,/";                                       # since 4.74- (u)
    }

    $cmd .= " $gtype:utiltot${i}$color[$color_indx]:\\\"$lpar_space\\\"";

    push @color_save, $lpar_orig;

    $cmd .= " PRINT:utiltot${i}:AVERAGE:\"%3.2lf $delimiter $item_leg $delimiter $server_name $delimiter $lpar_space_proc\"";
    $cmd .= " PRINT:utiltot${i}:AVERAGE:\\\"%3.2lf $delimiter $color[$color_indx] $delimiter $wrkdir_managedname_host_file_legend\\\"";
    $cmd .= " PRINT:utiltot${i}:MAX:\" %3.2lf $delimiter\"";

    $cmd .= " GPRINT:utiltot${i}:AVERAGE:\\\"%3.2lf \\\"";
    $cmd .= " GPRINT:utiltot${i}:MAX:\\\" %3.2lf \\l\\\"";

    $cmd_xpo .= " DEF:utiltot_mhz${i}=\\\"$wrkdir_managedname_host_file\\\":CPU_usage:AVERAGE";

    $cmd_xpo .= " \\\"CDEF:utiltot_ghz${i}=utiltot_mhz${i},1000,/\\\"";
    $cmd_xpo .= " \\\"CDEF:utiltot${i}=utiltot_mhz${i},1000,/\\\"";
    $cmd_xpo .= " \\\"XPORT:utiltot${i}:$lpar\\\"";

    # put carriage return after each second lpar in the legend
    if ( $j == 1 ) {
      $j = 0;
    }
    else {
      $j++;
    }
    $gtype = "STACK";
    $i++;
    $color_indx = ++$color_indx % ( $color_max + 1 );

  }

  #  $cmd_sum =~ s/\\"/"/g;
  $cmd_xpo =~ s/\\"/"/g;

  close(FHL);
  my $FH;

  # store XPORT for future usage in Hist reports (detail-graph-cgi.pl)
  if ( "$type" =~ "d" ) {

    # only daily one
    my $tmp_file_xpo = "$tmpdir/custom-group-$group-$type-xpo.cmd";
    $tmp_file_xpo = "$tmpdir/custom-group-vmmem-$group-$type-xpo.cmd" if $item eq "mem";
    open( FH, "> $tmp_file_xpo" ) || error( "Can't open $tmp_file_xpo : $!" . __FILE__ . ":" . __LINE__ ) && return 0;
    print FH "$cmd_xpo\n";
    close(FH);
  }

  if ( $newest_file_timestamp > 0 ) {
    my $l = localtime($newest_file_timestamp);

    # following must be for RRD 1.2+
    $l =~ s/:/\\:/g;
    my $vm_number = scalar keys %uniq_files;
    $updated = " COMMENT:\\\"  Updated\\\: $l $vm_number VMs\\\"";
  }

  $cmd .= " $updated";

  if ( "$type" =~ "d" ) {
    if ( $j == 1 ) {
      $cmd .= " COMMENT:\\\" \\l\\\"";
    }
  }
  $cmd .= " HRULE:0#000000";

  # $cmd .= " VRULE:0#000000";  --> it is causing sigsegv on linuxeS
  $cmd =~ s/\\"/"/g;

  # print STDERR "3525 custom.pl $tmp_file\n" ;
  open( FH, "> $tmp_file" ) || error( "Can't open $tmp_file : $!" . __FILE__ . ":" . __LINE__ ) && return 0;
  print FH "$cmd\n";
  close(FH);

  if ( !get_lpar_num() ) {
    if ( $index > 4 ) {
      if ( !-f "$webdir/custom/$group/$lim" ) {
        copy_source_org( $webdir, $tmpdir, $basedir, $lim_org, $lim, $group );
      }
    }
  }

  # write colors into a file
  if ( $color_file_change == 1 ) {
    open( FHC, "> $file_color_save" ) || error( "file cannot be created :  $file_color_save " . __FILE__ . ":" . __LINE__ ) && return 0;
    foreach my $line_cs (@color_save) {
      chomp($line_cs);    # it must be there, somehow appear there \n ...
      if ( $line_cs eq '' ) {
        next;
      }
      if ( $line_cs =~ m/ : / ) {
        print FHC "$line_cs\n";
      }
    }
    close(FHC);
  }

  # colours

  #
  # do not execute it here
  # execute it in the run time based on cmd stored in $tmp_file
  #

  return 1;
}

sub multiview_cpu_vims_trend {
  my $group             = shift;
  my $name              = shift;
  my $type              = shift;
  my $type_sam          = shift;
  my $act_time          = shift;
  my $step_new          = shift;
  my $text              = shift;
  my $xgrid             = shift;
  my $req_time          = 0;
  my $comm              = "COMM ";
  my $lim               = ".li";
  my $updated           = "";
  my $color_file_change = 0;
  my $all_vmware_VMs    = "vmware_VMs";
  my $group_name        = $group;
  $group_name = sprintf( "%-28s", "$group_name" );
  my $lparno = 0;

  my $header = "Custom group $group: last $text";

  my $file  = "";
  my $i     = 0;
  my $y     = -1;
  my $lpar  = "";
  my $lparn = "";
  my $cmd   = "";
  my $j     = 0;

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

  my $tmp_file = "$tmpdir/custom-group-$group-cpu_trend-$type.cmd";

  # do not update weekly/monthly/yearly command files each run
  if ( -f "$tmp_file" ) {
    my $tmp_time = ( stat("$tmp_file") )[9];
    if ( ( $act_time - $tmp_time ) < $skip_time ) {
      print "                        skipped this time : ( $act_time - $tmp_time ) < $skip_time \n";
      return 0;
    }
  }

  my $type_edt = 0;
  if ( -f $type_edt_filev ) {
    $type_edt = 1;
  }

  my $lim_org = $lim;
  $lim =~ s/\.//;
  $lim =~ s/i/l/;

  $cmd .= "graph \\\"$name.png\\\"";
  $cmd .= " --title \\\"$header\\\"";
  $cmd .= " --start now-1$type";
  $cmd .= " --end now-1$type+1$type";
  $cmd .= " --imgformat PNG";
  $cmd .= " $disable_rrdtool_tag_agg";
  $cmd .= " --slope-mode";
  $cmd .= " --width=$width_trend";
  $cmd .= " --height=150";
  $cmd .= " --step=$step_new";
  $cmd .= " --lower-limit=0.00";
  $cmd .= " --color=BACK#$pic_col";
  $cmd .= " --color=SHADEA#$pic_col";
  $cmd .= " --color=SHADEB#$pic_col";
  $cmd .= " --color=CANVAS#$pic_col";
  $cmd .= " --alt-autoscale-max";
  $cmd .= " --upper-limit=0.1";
  $cmd .= " --vertical-label=\\\"CPU GHz\\\"";
  $cmd .= " --units-exponent=1.00";
  $cmd .= " --alt-y-grid";
  $cmd .= " --x-grid=$xgrid";
  $cmd .= " COMMENT:\\\"Utilization in CPU GHz              avrg         max\\l\\\"";

  my $gtype = "AREA";
  my $index = 0;

  my @lpars_graph_local = @lpars_graph;

  # print STDERR "2787 custom.pl \@lpars_graph @lpars_graph\n";

  my %uniq_files;

  # do not sort it HERE!! there is several arrays, sorting lpars_graph is not enough!!! --PH
  foreach my $file (@lpars_graph_local) {

    # print STDERR "2793 custom.pl \$file $file\n";
    # /home/lpar2rrd/lpar2rrd/data/10.100.1.18/10.100.1.30/502a7728-9916-34fb-4832-e1039ad423a5,VM12-CZSI-00-01,vm-4756
    ( $file, my $vm_name, undef ) = split( /,/, $file );
    my $server      = ( split( /\//, $file ) )[-3];
    my $hmc_vm      = ( split( /\//, $file ) )[-2];
    my $server_name = $server;

    my $file_name = ( split( /\//, $file ) )[-1];
    $file = "$wrkdir/$all_vmware_VMs/$file_name.rrm";

    # print STDERR "2802 custom.pl \$file $file \$server $server\n";
    if ( $file eq '' ) {
      $index++;
      next;    #some trash
    }

    if ( !-f $file ) {
      $index++;
      next;
    }

    # avoid old lpars which do not exist in the period
    my $rrd_upd_time = ( stat("$file") )[9];
    if ( $rrd_upd_time < $req_time ) {
      $index++;
      next;
    }

    $lpar = $server_name;
    my $lpar_orig = $lpar;

    my $lpar_proc = "$lpar $delimiter " . "$vm_name";    # for html legend
    $lpar_proc =~ s/%/%%/g;
    $lpar_proc =~ s/:/\\:/g;
    $lpar_proc =~ s/\&\&1/\//g;

    $lpar =~ s/\&\&1/\//g;
    for ( my $k = length($lpar); $k < 25; $k++ ) {
      $lpar .= " ";
    }
    $lpar .= "   ";
    $lpar .= $vm_name;
    $lpar =~ s/\&\&1/\//g;

    # to keep same count of characters
    $lpar =~ s/\\:/:/g;
    $lpar = sprintf( "%-50s", $lpar );
    $lpar =~ s/:/\\:/g;

    my $lpar_space      = $lpar;
    my $lpar_space_proc = $vm_name;

    if ( exists $uniq_files{"$file"} ) {    # check duplicities
      $index++;
      next;
    }
    $uniq_files{"$file"} = 1;
    $lparn .= " ";

    # print STDERR "2851 custom.pl $file $rrd_upd_time $req_time $act_time\n" ; # if ( $DEBUG == 1);

    if ( ( length($lpar_v) + 1 ) == length($comm) && length($lparn) == length($comm) ) {
      copy_source_org( $webdir, $tmpdir, $basedir, $lim_org, $lim, $group );
      last;
    }

    my $file_legend = $file;
    $file_legend =~ s/%/%%/g;
    $file_legend =~ s/:/\\:/g;

    # Exclude items (lpars/pool) if there is no data for last year for all HMCs
    #if ( LPM_easy_exclude($file_pth,$act_time-31622400) == 0 ) {
    #  $index++;
    #  next;    # there is not updated rrd file for last year, skip that item
    #}

    # new system
    my $wrkdir_managedname_host_file = "$wrkdir/$all_vmware_VMs/$file_name.rrm";
    $wrkdir_managedname_host_file =~ s/:/\\:/g;

    #my $wrkdir_managedname_host_file_legend = $wrkdir_managedname_host_file;
    my $wrkdir_managedname_host_file_legend = "$wrkdir/$server/$hmc_vm/$file_name.rrm";
    $wrkdir_managedname_host_file_legend =~ s/%/%%/g;

    if ( $type_edt == 0 && $lparno == 4 ) {
      copy_source_org( $webdir, $tmpdir, $basedir, $lim_org, $lim, $group );
      last;
    }
    $lparno++;

    # bulid RRDTool cmd
    $cmd .= " DEF:utiltot_mhz${i}=\\\"$wrkdir_managedname_host_file\\\":CPU_usage:AVERAGE";
    $cmd .= " CDEF:utiltot_ghz${i}=utiltot_mhz${i},1000,/";
    $cmd .= " CDEF:utiltot${i}=utiltot_mhz${i},1000,/";                                       # since 4.74- (u)

    $cmd .= " DEF:utiltot_mhzm${i}=\\\"$wrkdir_managedname_host_file\\\":CPU_usage:AVERAGE:start=-1m";
    $cmd .= " CDEF:utiltot_ghzm${i}=utiltot_mhzm${i},1000,/";
    $cmd .= " CDEF:utiltotm${i}=utiltot_mhzm${i},1000,/";                                                # since 4.74- (u)

    $cmd .= " DEF:utiltot_mhzq${i}=\\\"$wrkdir_managedname_host_file\\\":CPU_usage:AVERAGE:start=-3m";
    $cmd .= " CDEF:utiltot_ghzq${i}=utiltot_mhzq${i},1000,/";
    $cmd .= " CDEF:utiltotq${i}=utiltot_mhzq${i},1000,/";                                                # since 4.74- (u)

    $cmd .= " DEF:utiltot_mhzy${i}=\\\"$wrkdir_managedname_host_file\\\":CPU_usage:AVERAGE:start=-1y";
    $cmd .= " CDEF:utiltot_ghzy${i}=utiltot_mhzy${i},1000,/";
    $cmd .= " CDEF:utiltoty${i}=utiltot_mhzy${i},1000,/";                                                # since 4.74- (u)

    if ( $i == 0 ) {
      $cmd .= " CDEF:main_res${i}=utiltot${i}";
      $cmd .= " CDEF:main_res1m${i}=utiltotm${i}";
      $cmd .= " CDEF:main_res3m${i}=utiltotq${i}";
      $cmd .= " CDEF:main_res1y${i}=utiltoty${i}";
    }
    else {
      $cmd .= " CDEF:pom${i}=main_res${y},UN,0,main_res${y},IF,utiltot${i},UN,0,utiltot${i},IF,+";
      $cmd .= " CDEF:main_res${i}=main_res${y},UN,utiltot${i},UN,UNKN,pom${i},IF,pom${i},IF";

      $cmd .= " CDEF:pom1m${i}=main_res1m${y},UN,0,main_res1m${y},IF,utiltotm${i},UN,0,utiltotm${i},IF,+";
      $cmd .= " CDEF:main_res1m${i}=main_res1m${y},UN,utiltotm${i},UN,UNKN,pom1m${i},IF,pom1m${i},IF";

      $cmd .= " CDEF:pom3m${i}=main_res3m${y},UN,0,main_res3m${y},IF,utiltotq${i},UN,0,utiltotq${i},IF,+";
      $cmd .= " CDEF:main_res3m${i}=main_res3m${y},UN,utiltotq${i},UN,UNKN,pom3m${i},IF,pom3m${i},IF";

      $cmd .= " CDEF:pom1y${i}=main_res1y${y},UN,0,main_res1y${y},IF,utiltoty${i},UN,0,utiltoty${i},IF,+";
      $cmd .= " CDEF:main_res1y${i}=main_res1y${y},UN,utiltoty${i},UN,UNKN,pom1y${i},IF,pom1y${i},IF";
    }

    $i++;
    $y++;
  }

  $group_name =~ s/:/\\:/g;

  $cmd .= " LINE1:main_res${y}#FF0000:\\\"$group_name\\\"";
  $cmd .= " GPRINT:main_res${y}:AVERAGE:\\\"%8.1lf \\\"";
  $cmd .= " GPRINT:main_res${y}:MAX:\\\" %8.1lf \\\"";
  $cmd .= " COMMENT:\\\"\\l\\\"";

  $cmd .= " VDEF:Ddy=main_res1y${y},LSLSLOPE";
  $cmd .= " VDEF:Hdy=main_res1y${y},LSLINT";
  $cmd .= " CDEF:cpuutiltottrenddy=main_res1y${y},POP,Ddy,COUNT,*,Hdy,+";
  $cmd .= " LINE2:cpuutiltottrenddy#FF8080:\\\"last 1 year trend\\\"";
  $cmd .= " COMMENT:\\\"\\l\\\"";

  $cmd .= " VDEF:Dd3=main_res3m${y},LSLSLOPE";
  $cmd .= " VDEF:Hd3=main_res3m${y},LSLINT";
  $cmd .= " CDEF:cpuutiltottrendd3=main_res3m${y},POP,Dd3,COUNT,*,Hd3,+";
  $cmd .= " LINE2:cpuutiltottrendd3#80FFFF:\\\"last 3 month trend\\\"";
  $cmd .= " COMMENT:\\\"\\l\\\"";

  $cmd .= " VDEF:Dd=main_res1m${y},LSLSLOPE";
  $cmd .= " VDEF:Hd=main_res1m${y},LSLINT";
  $cmd .= " CDEF:cpuutiltottrendd=main_res1m${y},POP,Dd,COUNT,*,Hd,+";
  $cmd .= " LINE2:cpuutiltottrendd#0088FF:\\\"last 1 month trend\\\"";
  $cmd .= " COMMENT:\\\"\\l\\\"";

  $cmd .= " HRULE:0#000000";

  # $cmd .= " VRULE:0#000000";  --> it is causing sigsegv on linuxeS
  $cmd =~ s/\\"/"/g;

  open( FH, "> $tmp_file" ) || error( "Can't open $tmp_file : $!" . __FILE__ . ":" . __LINE__ ) && return 0;
  print FH "$cmd\n";
  close(FH);

  if ( !get_lpar_num() ) {
    if ( $index > 4 ) {
      if ( !-f "$webdir/custom/$group/$lim" ) {
        copy_source_org( $webdir, $tmpdir, $basedir, $lim_org, $lim, $group );
      }
    }
  }

  #
  # do not execute it here
  # execute it in the run time based on cmd stored in $tmp_file
  #

  return 1;
}

sub multiview_cpu_trend {
  my $group      = shift;
  my $name       = shift;
  my $type       = shift;
  my $type_sam   = shift;
  my $act_time   = shift;
  my $step_new   = shift;
  my $text       = shift;
  my $xgrid      = shift;
  my $req_time   = 0;
  my $comm       = "COMM ";
  my $list       = "$webdir/custom/$group/list.txt";
  my $lim        = ".li";
  my $updated    = "";
  my $group_name = $group;
  $group_name = sprintf( "%-28s", "$group_name" );
  my $lparno = 0;

  my $skip_time = 0;
  if ( "$type" =~ "w" ) {
    $skip_time = $WEEK_REFRESH;
  }
  if ( "$type" =~ "m" ) {
    $skip_time = $MONTH_REFRESH;
  }
  if ( "$type" =~ "y" ) {
    $skip_time = $YEAR_REFRESH;
  }

  my $tmp_file = "$tmpdir/custom-group-$group-cpu_trend-$type.cmd";

  # do not update weekly/monthly/yearly command files each run
  if ( -f "$tmp_file" ) {
    my $tmp_time = ( stat("$tmp_file") )[9];
    if ( ( $act_time - $tmp_time ) < $skip_time ) {
      print "                        skipped this time : ( $act_time - $tmp_time ) < $skip_time \n";
      return 0;
    }
  }

  # open file for writing list of lpars

  my $header = "Custom group $group: last $text - trend";

  my $file  = "";
  my $i     = 0;
  my $y     = -1;
  my $lpar  = "";
  my $lparn = "";
  my $cmd   = "";

  my $type_edt = 0;
  if ( -f $type_edt_filep ) {
    $type_edt = 1;
  }

  my $lim_org = $lim;
  $lim =~ s/\.//;
  $lim =~ s/i/l/;

  my $no_legend = "--interlaced";

  $cmd .= "graph \\\"$name.png\\\"";
  $cmd .= " --title \\\"$header\\\"";
  $cmd .= " --start now-1$type";
  $cmd .= " --end now+1$type";
  $cmd .= " --imgformat PNG";
  $cmd .= " $disable_rrdtool_tag_agg";
  $cmd .= " --slope-mode";
  $cmd .= " --width=$width_trend";
  $cmd .= " --height=150";
  $cmd .= " --step=$step_new";
  $cmd .= " --lower-limit=0.00";
  $cmd .= " --color=BACK#$pic_col";
  $cmd .= " --color=SHADEA#$pic_col";
  $cmd .= " --color=SHADEB#$pic_col";
  $cmd .= " --color=CANVAS#$pic_col";
  $cmd .= " --alt-autoscale-max";
  $cmd .= " --upper-limit=0.1";
  $cmd .= " --vertical-label=\\\"CPU cores\\\"";
  $cmd .= " --units-exponent=1.00";
  $cmd .= " --alt-y-grid";
  $cmd .= " $no_legend";
  $cmd .= " --x-grid=$xgrid";
  $cmd .= " COMMENT:\\\"Utilization in CPU cores            avrg         max\\l\\\"";

  my $index     = 0;
  my $sh_pools  = 0;    # identificator of shared pool
  my $pool_indx = 0;

  my @lpars_graph_local = @lpars_graph;
  my %uniq_files;
  my $files_found = 0;

  # do not sort it HERE!! there is several arrays, sorting lpars_graph is not enough!!! --PH
  foreach my $file (@lpars_graph_local) {
    if ( $file eq '' ) {
      $index++;
      next;    #some trash
    }

    if ( $file !~ m/\.rr[m,h,d]$/ ) {

      # if pool then translate back to full path rrm
      if ( $lpars_graph_type[$index] =~ /POOL/ ) {

        # translate default pool
        if ( $file =~ m/\/all_pools$/ || $file =~ m/\/CPU pool$/ ) {
          $file =~ s/\/all_pools$/\/pool/;
          $file =~ s/\/CPU pool$/\/pool/;
        }
        else {    # shared pools

          # translate shared pool names
          # basename without direct function
          my $sh_pool_in = $file;
          my @link_base  = split( /\//, $sh_pool_in );
          foreach my $m (@link_base) {
            $sh_pool_in = $m;
          }
          $file       =~ s/\/$sh_pool_in$//;    # dirname
          $sh_pool_in =~ s/^SharedPool//;

          # open available pool mapping file, the most actual one
          my @map             = "";
          my $map_file_final  = "";
          my $map_file_tstamp = 0;

          my $file_space = dirname($file);
          if ( $file =~ m/ / ) {                # workaround for server name with a space inside, nothing else works, grrr
                                                # $file_space = "\"".$file."\"";
            $file_space =~ s/ /\\ /g;
          }

          my $file_dirname = dirname($file);
          foreach my $map_file (<$file_space/*/cpu-pools-mapping.txt>) {
            if ( !-s "$map_file" ) {
              next;    # ignore emty files
            }
            my $tstamp = ( stat("$map_file") )[9];
            if ( $tstamp > $map_file_tstamp ) {
              $map_file_tstamp = $tstamp;
              $map_file_final  = $map_file;
            }
          }
          if ( $map_file_tstamp > 0 ) {
            open( FHP, "< $map_file_final" ) || error( "Can't open $map_file_final : $!" . __FILE__ . ":" . __LINE__ ) && next;
            @map = <FHP>;
            close(FHP);
          }
          my $found    = 0;
          my $map_rows = 0;
          foreach my $line (@map) {
            chomp($line);
            $map_rows++;
            if ( $line !~ m/^[0-9].*,/ ) {

              #something wrong , ignoring
              next;
            }
            ( my $pool_indx_new, my $pool_name_new ) = split( /,/, $line );
            if ( $pool_name_new =~ m/^$sh_pool_in$/ ) {
              $file .= "/SharedPool" . $pool_indx_new;
              $found++;
              last;
            }
            elsif ( $pool_name_new =~ m/^SharedPool$sh_pool_in$/ ) {
              $file .= "/SharedPool" . $pool_indx_new;
              $found++;
              last;
            }
          }
          if ( $found == 0 ) {
            if ( $map_rows > 0 ) {
              print "cgraph error 1 : could not found name for shared pool : $file/SharedPool$sh_pool_in\n";

              # no error logging
              #error ("custom 1: could not found name for shared pool : $file/SharedPool$sh_pool_in ".__FILE__.":".__LINE__);
              next;
            }
            else {
              print "cgraph error 1 : Pool mapping table is either empty or does not exist : $map_file_final\n";
              error( "custom 1: Pool mapping table is either empty or does not exist : $map_file_final " . __FILE__ . ":" . __LINE__ );
              next;
            }
          }
        }
      }

      my $file_org = $file;
      $file .= ".rrm";
      if ( !-f $file ) {
        $file = $file_org;
        $file =~ s/\.rrm$/\.rrh/;

        #$file .= ".rrh";
      }
    }
    if ( "$type" =~ "d" ) {
      my $file_org = $file;
      if ( $file !~ m/\.rr[m,d]$/ ) {
        $file .= ".rrd";
        if ( !-f $file ) {
          $file = $file_org;
          $file =~ s/\.rrd$/\.rrm/;
          $file =~ s/\.rrh$/\.rrm/;

          #$file .= ".rrm";
        }
      }
    }

    if ( !-f $file ) {
      $index++;
      next;
    }

    # avoid old lpars which do not exist in the period
    # --> no, no, it mus be done in LPM_easy otherwise it exclude even live data (when old HMC is listed here)
    #my $rrd_upd_time = (stat("$file"))[9];
    #if ( $rrd_upd_time < $req_time ) {
    #  $index++;
    #  next;
    #}

    # add spaces to lpar name to have 25 chars total (for formating graph legend)
    $lpar = $lpars_graph_server[$index];

    my $lpar_proc = "$lpar $delimiter " . "$lpars_graph_name[$index]";    # for html legend
    $lpar_proc =~ s/%/%%/g;
    $lpar_proc =~ s/:/\\:/g;
    $lpar_proc =~ s/\&\&1/\//g;

    $lpar =~ s/\&\&1/\//g;
    for ( my $k = length($lpar); $k < 25; $k++ ) {
      $lpar .= " ";
    }
    $lpar .= "   ";
    $lpar .= $lpars_graph_name[$index];
    $lpar =~ s/\&\&1/\//g;

    # to keep same count of characters
    $lpar =~ s/\\:/:/g;
    $lpar = sprintf( "%-50s", $lpar );
    $lpar =~ s/:/\\:/g;
    if ( exists $uniq_files{"$file"} ) {    # check duplicities
      $index++;
      next;
    }
    $uniq_files{"$file"} = 1;
    $lparn .= " ";

    #print "11 $file $rrd_upd_time $req_time $act_time\n" if ( $DEBUG == 1);

    if ( ( length($lpar_v) + 1 ) == length($comm) && length($lparn) == length($comm) ) {
      copy_source_org( $webdir, $tmpdir, $basedir, $lim_org, $lim, $group );
      last;
    }

    #if ($type =~ "d" && $i == 0 ) {
    #  RRDp::cmd qq(last "$file");
    #  my $last_tt = RRDp::read;
    #  chomp ($$last_tt);
    #  my $l=localtime($$last_tt);
    #  # following must be for RRD 1.2+
    #  $l =~ s/:/\\:/g;
    #  $updated =" COMMENT:\\\"  Updated\\\: $l \\\"";
    #}

    # $file =~ s/:/\\:/g;  # must be in LPM_easy
    my $file_legend = $file;
    $file_legend =~ s/%/%%/g;
    $file_legend =~ s/:/\\:/g;

    # preparing file name for multi hmc LPM_easy
    # should be like: my $file_pth = "$wrkdir/$server/*/$lpar.rr$type_sam";
    my $file_pth = basename($file);
    my $dir_pth  = dirname($file);
    $dir_pth  = dirname($dir_pth);
    $file_pth = "$dir_pth/*/$file_pth";

    # Exclude items (lpars/pool) if there is no data for last year for all HMCs
    if ( LPM_easy_exclude( $file_pth, $act_time - 31622400 ) == 0 ) {
      $index++;
      next;    # there is not updated rrd file for last year, skipt that item
    }

    if ( $type_edt == 0 && $lparno == 4 ) {
      copy_source_org( $webdir, $tmpdir, $basedir, $lim_org, $lim, $group );
      last;
    }
    $lparno++;

    $files_found++;

    # bulid RRDTool cmd
    if ( $lpars_graph_type[$index] =~ /LPAR/ ) {

      my ( $result_cmd, $capped_cycles, $uncapped_cycles, $entitled_cycles, $curr_proc_units ) = LPM_easy( $file_pth, $i, $req_time, "capped_cycles", "uncapped_cycles", "entitled_cycles", "curr_proc_units" );

      $cmd .= $result_cmd;
      $cmd .= " CDEF:cap${i}=$capped_cycles";
      $cmd .= " CDEF:uncap${i}=$uncapped_cycles";
      $cmd .= " CDEF:ent${i}=$entitled_cycles";
      $cmd .= " CDEF:cur${i}=$curr_proc_units";

      $cmd .= " CDEF:tot${i}=cap${i},uncap${i},+";
      $cmd .= " CDEF:util${i}=tot${i},ent${i},/,$cpu_max_filter,GT,UNKN,tot${i},ent${i},/,IF";
      $cmd .= " CDEF:utiltotu${i}=util${i},cur${i},*";
      $cmd .= " CDEF:utiltot${i}=utiltotu${i},100,*,0.5,+,FLOOR,100,/";

      # prepare DEF|CDEF for 1 month, 3 months and 1 year
      my $result_to_parse = $result_cmd;
      $result_to_parse =~ s/^\s+//g;
      $result_to_parse =~ s/\s+$//g;
      $result_to_parse =~ s/ ([C]*DEF:)/\n$1/g;

      my @result_cmd_lines = split( "\n", $result_to_parse );
      my $result_cmd1m;
      my $result_cmd3m;
      my $result_cmd1y;

      foreach my $cmd_line (@result_cmd_lines) {
        chomp $cmd_line;

        #print "$cmd_line\n";
        $cmd_line =~ s/^\s+//g;
        $cmd_line =~ s/\s+$//g;

        my $line1m = $cmd_line;
        my $line3m = $cmd_line;
        my $line1y = $cmd_line;

        if ( $cmd_line =~ "^DEF:" ) {
          $line1m =~ s/^DEF:var/DEF:var1m/;
          $line3m =~ s/^DEF:var/DEF:var3m/;
          $line1y =~ s/^DEF:var/DEF:var1y/;

          $line1m =~ s/:AVERAGE$/:AVERAGE:start=-1m/;
          $line3m =~ s/:AVERAGE$/:AVERAGE:start=-3m/;
          $line1y =~ s/:AVERAGE$/:AVERAGE:start=-1y/;
        }
        if ( $cmd_line =~ "^CDEF:" ) {
          $line1m =~ s/var/var1m/g;
          $line3m =~ s/var/var3m/g;
          $line1y =~ s/var/var1y/g;
        }

        $result_cmd1m .= " $line1m";
        $result_cmd3m .= " $line3m";
        $result_cmd1y .= " $line1y";
      }

      # 1 month
      my $capped_cycles1m   = $capped_cycles;
      my $uncapped_cycles1m = $uncapped_cycles;
      my $entitled_cycles1m = $entitled_cycles;
      my $curr_proc_units1m = $curr_proc_units;

      $capped_cycles1m   =~ s/var/var1m/g;
      $uncapped_cycles1m =~ s/var/var1m/g;
      $entitled_cycles1m =~ s/var/var1m/g;
      $curr_proc_units1m =~ s/var/var1m/g;

      $cmd .= $result_cmd1m;
      $cmd .= " CDEF:cap1m${i}=$capped_cycles1m";
      $cmd .= " CDEF:uncap1m${i}=$uncapped_cycles1m";
      $cmd .= " CDEF:ent1m${i}=$entitled_cycles1m";
      $cmd .= " CDEF:cur1m${i}=$curr_proc_units1m";

      $cmd .= " CDEF:tot1m${i}=cap1m${i},uncap1m${i},+";
      $cmd .= " CDEF:util1m${i}=tot1m${i},ent1m${i},/,$cpu_max_filter,GT,UNKN,tot1m${i},ent1m${i},/,IF";
      $cmd .= " CDEF:utiltotu1m${i}=util1m${i},cur1m${i},*";
      $cmd .= " CDEF:utiltot1m${i}=utiltotu1m${i},100,*,0.5,+,FLOOR,100,/";

      # 3 month
      my $capped_cycles3m   = $capped_cycles;
      my $uncapped_cycles3m = $uncapped_cycles;
      my $entitled_cycles3m = $entitled_cycles;
      my $curr_proc_units3m = $curr_proc_units;

      $capped_cycles3m   =~ s/var/var3m/g;
      $uncapped_cycles3m =~ s/var/var3m/g;
      $entitled_cycles3m =~ s/var/var3m/g;
      $curr_proc_units3m =~ s/var/var3m/g;

      $cmd .= $result_cmd3m;
      $cmd .= " CDEF:cap3m${i}=$capped_cycles3m";
      $cmd .= " CDEF:uncap3m${i}=$uncapped_cycles3m";
      $cmd .= " CDEF:ent3m${i}=$entitled_cycles3m";
      $cmd .= " CDEF:cur3m${i}=$curr_proc_units3m";

      $cmd .= " CDEF:tot3m${i}=cap3m${i},uncap3m${i},+";
      $cmd .= " CDEF:util3m${i}=tot3m${i},ent3m${i},/,$cpu_max_filter,GT,UNKN,tot3m${i},ent3m${i},/,IF";
      $cmd .= " CDEF:utiltotu3m${i}=util3m${i},cur3m${i},*";
      $cmd .= " CDEF:utiltot3m${i}=utiltotu3m${i},100,*,0.5,+,FLOOR,100,/";

      # 1 year
      my $capped_cycles1y   = $capped_cycles;
      my $uncapped_cycles1y = $uncapped_cycles;
      my $entitled_cycles1y = $entitled_cycles;
      my $curr_proc_units1y = $curr_proc_units;

      $capped_cycles1y   =~ s/var/var1y/g;
      $uncapped_cycles1y =~ s/var/var1y/g;
      $entitled_cycles1y =~ s/var/var1y/g;
      $curr_proc_units1y =~ s/var/var1y/g;

      $cmd .= $result_cmd1y;
      $cmd .= " CDEF:cap1y${i}=$capped_cycles1y";
      $cmd .= " CDEF:uncap1y${i}=$uncapped_cycles1y";
      $cmd .= " CDEF:ent1y${i}=$entitled_cycles1y";
      $cmd .= " CDEF:cur1y${i}=$curr_proc_units1y";

      $cmd .= " CDEF:tot1y${i}=cap1y${i},uncap1y${i},+";
      $cmd .= " CDEF:util1y${i}=tot1y${i},ent1y${i},/,$cpu_max_filter,GT,UNKN,tot1y${i},ent1y${i},/,IF";
      $cmd .= " CDEF:utiltotu1y${i}=util1y${i},cur1y${i},*";
      $cmd .= " CDEF:utiltot1y${i}=utiltotu1y${i},100,*,0.5,+,FLOOR,100,/";

      if ( $files_found == 1 ) {
        $cmd .= " CDEF:main_res${i}=utiltot${i}";
        $cmd .= " CDEF:main_res1m${i}=utiltot1m${i}";
        $cmd .= " CDEF:main_res3m${i}=utiltot3m${i}";
        $cmd .= " CDEF:main_res1y${i}=utiltot1y${i}";
      }
      else {
        $cmd .= " CDEF:pom${i}=main_res${y},UN,0,main_res${y},IF,utiltot${i},UN,0,utiltot${i},IF,+";
        $cmd .= " CDEF:main_res${i}=main_res${y},UN,utiltot${i},UN,UNKN,pom${i},IF,pom${i},IF";

        $cmd .= " CDEF:pom1m${i}=main_res1m${y},UN,0,main_res1m${y},IF,utiltot1m${i},UN,0,utiltot1m${i},IF,+";
        $cmd .= " CDEF:main_res1m${i}=main_res1m${y},UN,utiltot1m${i},UN,UNKN,pom1m${i},IF,pom1m${i},IF";

        $cmd .= " CDEF:pom3m${i}=main_res3m${y},UN,0,main_res3m${y},IF,utiltot3m${i},UN,0,utiltot3m${i},IF,+";
        $cmd .= " CDEF:main_res3m${i}=main_res3m${y},UN,utiltot3m${i},UN,UNKN,pom3m${i},IF,pom3m${i},IF";

        $cmd .= " CDEF:pom1y${i}=main_res1y${y},UN,0,main_res1y${y},IF,utiltot1y${i},UN,0,utiltot1y${i},IF,+";
        $cmd .= " CDEF:main_res1y${i}=main_res1y${y},UN,utiltot1y${i},UN,UNKN,pom1y${i},IF,pom1y${i},IF";
      }

    }
    else {
      # POOLs
      $lpar     = substr( $lpar, 0, 35 );
      $sh_pools = 1;
      if ( $file =~ /SharedPool[0-9]/ ) {

        # Shared pools 1 - X + even DefaultPool (ID 0) works here

        my ( $result_cmd, $total_pool_cycles, $utilized_pool_cyc, $max_pool_units ) = LPM_easy( $file_pth, $i, $req_time, "total_pool_cycles", "utilized_pool_cyc", "max_pool_units" );

        $cmd .= $result_cmd;
        $cmd .= " CDEF:max_nan${i}=$max_pool_units";
        $cmd .= " CDEF:max${i}=max_nan${i},UN,0,max_nan${i},IF";
        $cmd .= " VDEF:maxv${i}=max${i},MAXIMUM";                  # for html legend
        $cmd .= " CDEF:totcyc${i}=$total_pool_cycles";
        $cmd .= " CDEF:uticyc${i}=$utilized_pool_cyc";

        $cmd .= " CDEF:cpuutil${i}=uticyc${i},totcyc${i},GT,UNKN,uticyc${i},totcyc${i},/,IF";
        $cmd .= " CDEF:utiltot${i}=cpuutil${i},max${i},*";

        # prepare DEF|CDEF for 1 month, 3 months and 1 year
        my $result_to_parse = $result_cmd;
        $result_to_parse =~ s/^\s+//g;
        $result_to_parse =~ s/\s+$//g;
        $result_to_parse =~ s/ ([C]*DEF:)/\n$1/g;

        my @result_cmd_lines = split( "\n", $result_to_parse );
        my $result_cmd1m;
        my $result_cmd3m;
        my $result_cmd1y;

        foreach my $cmd_line (@result_cmd_lines) {
          chomp $cmd_line;

          #print "$cmd_line\n";
          $cmd_line =~ s/^\s+//g;
          $cmd_line =~ s/\s+$//g;

          my $line1m = $cmd_line;
          my $line3m = $cmd_line;
          my $line1y = $cmd_line;

          if ( $cmd_line =~ "^DEF:" ) {
            $line1m =~ s/^DEF:var/DEF:var1m/;
            $line3m =~ s/^DEF:var/DEF:var3m/;
            $line1y =~ s/^DEF:var/DEF:var1y/;

            $line1m =~ s/:AVERAGE$/:AVERAGE:start=-1m/;
            $line3m =~ s/:AVERAGE$/:AVERAGE:start=-3m/;
            $line1y =~ s/:AVERAGE$/:AVERAGE:start=-1y/;
          }
          if ( $cmd_line =~ "^CDEF:" ) {
            $line1m =~ s/var/var1m/g;
            $line3m =~ s/var/var3m/g;
            $line1y =~ s/var/var1y/g;
          }

          $result_cmd1m .= " $line1m";
          $result_cmd3m .= " $line3m";
          $result_cmd1y .= " $line1y";
        }

        # 1 month
        my $total_pool_cycles1m = $total_pool_cycles;
        my $utilized_pool_cyc1m = $utilized_pool_cyc;
        my $max_pool_units1m    = $max_pool_units;

        $total_pool_cycles1m =~ s/var/var1m/g;
        $utilized_pool_cyc1m =~ s/var/var1m/g;
        $max_pool_units1m    =~ s/var/var1m/g;

        $cmd .= $result_cmd1m;
        $cmd .= " CDEF:max_nan1m${i}=$max_pool_units1m";
        $cmd .= " CDEF:max1m${i}=max_nan1m${i},UN,0,max_nan1m${i},IF";
        $cmd .= " VDEF:maxv1m${i}=max1m${i},MAXIMUM";                    # for html legend
        $cmd .= " CDEF:totcyc1m${i}=$total_pool_cycles1m";
        $cmd .= " CDEF:uticyc1m${i}=$utilized_pool_cyc1m";

        $cmd .= " CDEF:cpuutil1m${i}=uticyc1m${i},totcyc1m${i},GT,UNKN,uticyc1m${i},totcyc1m${i},/,IF";
        $cmd .= " CDEF:utiltot1m${i}=cpuutil1m${i},max1m${i},*";

        # 3 month
        my $total_pool_cycles3m = $total_pool_cycles;
        my $utilized_pool_cyc3m = $utilized_pool_cyc;
        my $max_pool_units3m    = $max_pool_units;

        $total_pool_cycles3m =~ s/var/var3m/g;
        $utilized_pool_cyc3m =~ s/var/var3m/g;
        $max_pool_units3m    =~ s/var/var3m/g;

        $cmd .= $result_cmd3m;
        $cmd .= " CDEF:max_nan3m${i}=$max_pool_units3m";
        $cmd .= " CDEF:max3m${i}=max_nan3m${i},UN,0,max_nan3m${i},IF";
        $cmd .= " VDEF:maxv3m${i}=max3m${i},MAXIMUM";                    # for html legend
        $cmd .= " CDEF:totcyc3m${i}=$total_pool_cycles3m";
        $cmd .= " CDEF:uticyc3m${i}=$utilized_pool_cyc3m";

        $cmd .= " CDEF:cpuutil3m${i}=uticyc3m${i},totcyc3m${i},GT,UNKN,uticyc3m${i},totcyc3m${i},/,IF";
        $cmd .= " CDEF:utiltot3m${i}=cpuutil3m${i},max3m${i},*";

        # 1 year
        my $total_pool_cycles1y = $total_pool_cycles;
        my $utilized_pool_cyc1y = $utilized_pool_cyc;
        my $max_pool_units1y    = $max_pool_units;

        $total_pool_cycles1y =~ s/var/var1y/g;
        $utilized_pool_cyc1y =~ s/var/var1y/g;
        $max_pool_units1y    =~ s/var/var1y/g;

        $cmd .= $result_cmd1y;
        $cmd .= " CDEF:max_nan1y${i}=$max_pool_units1y";
        $cmd .= " CDEF:max1y${i}=max_nan1y${i},UN,0,max_nan1y${i},IF";
        $cmd .= " VDEF:maxv1y${i}=max1y${i},MAXIMUM";                    # for html legend
        $cmd .= " CDEF:totcyc1y${i}=$total_pool_cycles1y";
        $cmd .= " CDEF:uticyc1y${i}=$utilized_pool_cyc1y";

        $cmd .= " CDEF:cpuutil1y${i}=uticyc1y${i},totcyc1y${i},GT,UNKN,uticyc1y${i},totcyc1y${i},/,IF";
        $cmd .= " CDEF:utiltot1y${i}=cpuutil1y${i},max1y${i},*";

        if ( $files_found == 1 ) {
          $cmd .= " CDEF:main_res${i}=utiltot${i}";
          $cmd .= " CDEF:main_res1m${i}=utiltot1m${i}";
          $cmd .= " CDEF:main_res3m${i}=utiltot3m${i}";
          $cmd .= " CDEF:main_res1y${i}=utiltot1y${i}";
        }
        else {
          $cmd .= " CDEF:pom${i}=main_res${y},UN,0,main_res${y},IF,utiltot${i},UN,0,utiltot${i},IF,+";
          $cmd .= " CDEF:main_res${i}=main_res${y},UN,utiltot${i},UN,UNKN,pom${i},IF,pom${i},IF";

          $cmd .= " CDEF:pom1m${i}=main_res1m${y},UN,0,main_res1m${y},IF,utiltot1m${i},UN,0,utiltot1m${i},IF,+";
          $cmd .= " CDEF:main_res1m${i}=main_res1m${y},UN,utiltot1m${i},UN,UNKN,pom1m${i},IF,pom1m${i},IF";

          $cmd .= " CDEF:pom3m${i}=main_res3m${y},UN,0,main_res3m${y},IF,utiltot3m${i},UN,0,utiltot3m${i},IF,+";
          $cmd .= " CDEF:main_res3m${i}=main_res3m${y},UN,utiltot3m${i},UN,UNKN,pom3m${i},IF,pom3m${i},IF";

          $cmd .= " CDEF:pom1y${i}=main_res1y${y},UN,0,main_res1y${y},IF,utiltot1y${i},UN,0,utiltot1y${i},IF,+";
          $cmd .= " CDEF:main_res1y${i}=main_res1y${y},UN,utiltot1y${i},UN,UNKN,pom1y${i},IF,pom1y${i},IF";
        }
      }
      else {

        # pool.rrm
        my ( $result_cmd, $total_pool_cycles, $utilized_pool_cyc, $conf_proc_units, $bor_proc_units ) = LPM_easy( $file_pth, $i, $req_time, "total_pool_cycles", "utilized_pool_cyc", "conf_proc_units", "bor_proc_units" );

        # print "$result_cmd,$total_pool_cycles,$utilized_pool_cyc,$conf_proc_units,$bor_proc_units\n";
        $cmd .= $result_cmd;
        $cmd .= " CDEF:totcyc${i}=$total_pool_cycles";
        $cmd .= " CDEF:uticyc${i}=$utilized_pool_cyc";
        $cmd .= " CDEF:cpu${i}=$conf_proc_units";
        $cmd .= " CDEF:cpubor${i}=$bor_proc_units";

        $cmd .= " CDEF:totcpu_nan${i}=cpu${i},cpubor${i},+";
        $cmd .= " CDEF:totcpu${i}=totcpu_nan${i},UN,0,totcpu_nan${i},IF";
        $cmd .= " VDEF:totcpuv${i}=totcpu${i},MAXIMUM";                                         # for html legend
        $cmd .= " CDEF:cpuutil${i}=uticyc${i},totcyc${i},GT,UNKN,uticyc${i},totcyc${i},/,IF";
        $cmd .= " CDEF:utiltot${i}=cpuutil${i},totcpu${i},*";

        # prepare DEF|CDEF for 1 month, 3 months and 1 year
        my $result_to_parse = $result_cmd;
        $result_to_parse =~ s/^\s+//g;
        $result_to_parse =~ s/\s+$//g;
        $result_to_parse =~ s/ ([C]*DEF:)/\n$1/g;

        my @result_cmd_lines = split( "\n", $result_to_parse );
        my $result_cmd1m;
        my $result_cmd3m;
        my $result_cmd1y;

        foreach my $cmd_line (@result_cmd_lines) {
          chomp $cmd_line;

          #print "$cmd_line\n";
          $cmd_line =~ s/^\s+//g;
          $cmd_line =~ s/\s+$//g;

          my $line1m = $cmd_line;
          my $line3m = $cmd_line;
          my $line1y = $cmd_line;

          if ( $cmd_line =~ "^DEF:" ) {
            $line1m =~ s/^DEF:var/DEF:var1m/;
            $line3m =~ s/^DEF:var/DEF:var3m/;
            $line1y =~ s/^DEF:var/DEF:var1y/;

            $line1m =~ s/:AVERAGE$/:AVERAGE:start=-1m/;
            $line3m =~ s/:AVERAGE$/:AVERAGE:start=-3m/;
            $line1y =~ s/:AVERAGE$/:AVERAGE:start=-1y/;
          }
          if ( $cmd_line =~ "^CDEF:" ) {
            $line1m =~ s/var/var1m/g;
            $line3m =~ s/var/var3m/g;
            $line1y =~ s/var/var1y/g;
          }

          $result_cmd1m .= " $line1m";
          $result_cmd3m .= " $line3m";
          $result_cmd1y .= " $line1y";
        }

        # 1 month
        my $total_pool_cycles1m = $total_pool_cycles;
        my $utilized_pool_cyc1m = $utilized_pool_cyc;
        my $conf_proc_units1m   = $conf_proc_units;
        my $bor_proc_units1m    = $bor_proc_units;

        $total_pool_cycles1m =~ s/var/var1m/g;
        $utilized_pool_cyc1m =~ s/var/var1m/g;
        $conf_proc_units1m   =~ s/var/var1m/g;
        $bor_proc_units1m    =~ s/var/var1m/g;

        $cmd .= $result_cmd1m;
        $cmd .= " CDEF:totcyc1m${i}=$total_pool_cycles1m";
        $cmd .= " CDEF:uticyc1m${i}=$utilized_pool_cyc1m";
        $cmd .= " CDEF:cpu1m${i}=$conf_proc_units1m";
        $cmd .= " CDEF:cpubor1m${i}=$bor_proc_units1m";

        $cmd .= " CDEF:totcpu_nan1m${i}=cpu1m${i},cpubor1m${i},+";
        $cmd .= " CDEF:totcpu1m${i}=totcpu_nan1m${i},UN,0,totcpu_nan1m${i},IF";
        $cmd .= " VDEF:totcpuv1m${i}=totcpu1m${i},MAXIMUM";                                               # for html legend
        $cmd .= " CDEF:cpuutil1m${i}=uticyc1m${i},totcyc1m${i},GT,UNKN,uticyc1m${i},totcyc1m${i},/,IF";
        $cmd .= " CDEF:utiltot1m${i}=cpuutil1m${i},totcpu1m${i},*";

        # 3 month
        my $total_pool_cycles3m = $total_pool_cycles;
        my $utilized_pool_cyc3m = $utilized_pool_cyc;
        my $conf_proc_units3m   = $conf_proc_units;
        my $bor_proc_units3m    = $bor_proc_units;

        $total_pool_cycles3m =~ s/var/var3m/g;
        $utilized_pool_cyc3m =~ s/var/var3m/g;
        $conf_proc_units1m   =~ s/var/var3m/g;
        $bor_proc_units3m    =~ s/var/var3m/g;

        $cmd .= $result_cmd3m;
        $cmd .= " CDEF:totcyc3m${i}=$total_pool_cycles3m";
        $cmd .= " CDEF:uticyc3m${i}=$utilized_pool_cyc3m";
        $cmd .= " CDEF:cpu3m${i}=$conf_proc_units3m";
        $cmd .= " CDEF:cpubor3m${i}=$bor_proc_units3m";

        $cmd .= " CDEF:totcpu_nan3m${i}=cpu3m${i},cpubor3m${i},+";
        $cmd .= " CDEF:totcpu3m${i}=totcpu_nan3m${i},UN,0,totcpu_nan3m${i},IF";
        $cmd .= " VDEF:totcpuv3m${i}=totcpu3m${i},MAXIMUM";                                               # for html legend
        $cmd .= " CDEF:cpuutil3m${i}=uticyc3m${i},totcyc3m${i},GT,UNKN,uticyc3m${i},totcyc3m${i},/,IF";
        $cmd .= " CDEF:utiltot3m${i}=cpuutil3m${i},totcpu3m${i},*";

        # 1 year
        my $total_pool_cycles1y = $total_pool_cycles;
        my $utilized_pool_cyc1y = $utilized_pool_cyc;
        my $conf_proc_units1y   = $conf_proc_units;
        my $bor_proc_units1y    = $bor_proc_units;

        $total_pool_cycles1y =~ s/var/var1y/g;
        $utilized_pool_cyc1y =~ s/var/var1y/g;
        $conf_proc_units1m   =~ s/var/var1y/g;
        $bor_proc_units1y    =~ s/var/var1y/g;

        $cmd .= $result_cmd1y;
        $cmd .= " CDEF:totcyc1y${i}=$total_pool_cycles1y";
        $cmd .= " CDEF:uticyc1y${i}=$utilized_pool_cyc1y";
        $cmd .= " CDEF:cpu1y${i}=$conf_proc_units1y";
        $cmd .= " CDEF:cpubor1y${i}=$bor_proc_units1y";

        $cmd .= " CDEF:totcpu_nan1y${i}=cpu1y${i},cpubor1y${i},+";
        $cmd .= " CDEF:totcpu1y${i}=totcpu_nan1y${i},UN,0,totcpu_nan1y${i},IF";
        $cmd .= " VDEF:totcpuv1y${i}=totcpu1y${i},MAXIMUM";                                               # for html legend
        $cmd .= " CDEF:cpuutil1y${i}=uticyc1y${i},totcyc1y${i},GT,UNKN,uticyc1y${i},totcyc1y${i},/,IF";
        $cmd .= " CDEF:utiltot1y${i}=cpuutil1y${i},totcpu1y${i},*";

        if ( $files_found == 1 ) {
          $cmd .= " CDEF:main_res${i}=utiltot${i}";
          $cmd .= " CDEF:main_res1m${i}=utiltot1m${i}";
          $cmd .= " CDEF:main_res3m${i}=utiltot3m${i}";
          $cmd .= " CDEF:main_res1y${i}=utiltot1y${i}";
        }
        else {
          $cmd .= " CDEF:pom${i}=main_res${y},UN,0,main_res${y},IF,utiltot${i},UN,0,utiltot${i},IF,+";
          $cmd .= " CDEF:main_res${i}=main_res${y},UN,utiltot${i},UN,UNKN,pom${i},IF,pom${i},IF";

          $cmd .= " CDEF:pom1m${i}=main_res1m${y},UN,0,main_res1m${y},IF,utiltot1m${i},UN,0,utiltot1m${i},IF,+";
          $cmd .= " CDEF:main_res1m${i}=main_res1m${y},UN,utiltot1m${i},UN,UNKN,pom1m${i},IF,pom1m${i},IF";

          $cmd .= " CDEF:pom3m${i}=main_res3m${y},UN,0,main_res3m${y},IF,utiltot3m${i},UN,0,utiltot3m${i},IF,+";
          $cmd .= " CDEF:main_res3m${i}=main_res3m${y},UN,utiltot3m${i},UN,UNKN,pom3m${i},IF,pom3m${i},IF";

          $cmd .= " CDEF:pom1y${i}=main_res1y${y},UN,0,main_res1y${y},IF,utiltot1y${i},UN,0,utiltot1y${i},IF,+";
          $cmd .= " CDEF:main_res1y${i}=main_res1y${y},UN,utiltot1y${i},UN,UNKN,pom1y${i},IF,pom1y${i},IF";
        }
      }
    }

    $i++;
    $y++;
    $index++;
    if ( !get_lpar_num() && $index == 5 ) {
      last;
    }

  }

  $group_name =~ s/:/\\:/g;

  $cmd .= " LINE1:main_res${y}#FF0000:\\\"$group_name\\\"";
  $cmd .= " GPRINT:main_res${y}:AVERAGE:\\\"%8.1lf \\\"";
  $cmd .= " GPRINT:main_res${y}:MAX:\\\" %8.1lf \\\"";
  $cmd .= " COMMENT:\\\"\\l\\\"";

  $cmd .= " VDEF:Ddy=main_res1y${y},LSLSLOPE";
  $cmd .= " VDEF:Hdy=main_res1y${y},LSLINT";
  $cmd .= " CDEF:cpuutiltottrenddy=main_res1y${y},POP,Ddy,COUNT,*,Hdy,+";
  $cmd .= " LINE2:cpuutiltottrenddy#FF8080:\\\"last 1 year trend\\\"";
  $cmd .= " COMMENT:\\\"\\l\\\"";

  $cmd .= " VDEF:Dd3=main_res3m${y},LSLSLOPE";
  $cmd .= " VDEF:Hd3=main_res3m${y},LSLINT";
  $cmd .= " CDEF:cpuutiltottrendd3=main_res3m${y},POP,Dd3,COUNT,*,Hd3,+";
  $cmd .= " LINE2:cpuutiltottrendd3#80FFFF:\\\"last 3 month trend\\\"";
  $cmd .= " COMMENT:\\\"\\l\\\"";

  $cmd .= " VDEF:Dd=main_res1m${y},LSLSLOPE";
  $cmd .= " VDEF:Hd=main_res1m${y},LSLINT";
  $cmd .= " CDEF:cpuutiltottrendd=main_res1m${y},POP,Dd,COUNT,*,Hd,+";
  $cmd .= " LINE2:cpuutiltottrendd#0088FF:\\\"last 1 month trend\\\"";
  $cmd .= " COMMENT:\\\"\\l\\\"";

  my $FH;

  # $cmd .= " $updated";
  $cmd .= " HRULE:0#000000";

  # $cmd .= " VRULE:0#000000";  --> it is causing sigsegv on linuxeS
  $cmd =~ s/\\"/"/g;

  open( FH, "> $tmp_file" ) || error( "Can't open $tmp_file : $!" . __FILE__ . ":" . __LINE__ ) && return 0;
  print FH "$cmd\n";
  close(FH);

  if ( !get_lpar_num() ) {
    if ( $index > 4 ) {
      if ( !-f "$webdir/custom/$group/$lim" ) {
        copy_source_org( $webdir, $tmpdir, $basedir, $lim_org, $lim, $group );
      }
    }
  }

  #
  # do not execute it here
  # execute it in the run time based on cmd stored in $tmp_file
  #

  return 1;
}

sub copy_source_org {
  my $webdir  = shift;
  my $tmpdir  = shift;
  my $basedir = shift;
  my $lim_org = shift;
  my $lim     = shift;
  my $group   = shift;
  copy( "$basedir/html/$lim_org", "$webdir/custom/$group/$lim" );
  copy( "$basedir/html/$lim_org", "$tmpdir/.custom-group-$group-n.cmd" );
  return 1;
}

sub multiview_disk {
  my $group    = shift;
  my $name     = shift;
  my $type     = shift;
  my $type_sam = shift;
  my $act_time = shift;
  my $step_new = shift;
  my $text     = shift;
  my $xgrid    = shift;
  my $item     = shift;
  my $req_time = 0;
  my $comm     = "COMM ";
  $color_indx = 0;    # prepare color index
  my $list              = "$webdir/custom/$group/list.txt";
  my $lim               = ".li";
  my $color_file_change = 0;
  my $file_color_save   = "$basedir/tmp/custom-group-$item-$group-$item.col";
  my $lparno            = 0;

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

  my $tmp_file = "$tmpdir/custom-group-$item-$group-$type.cmd";

  # do not update weekly/monthly/yearly command files each run
  if ( -f "$tmp_file" ) {
    my $tmp_time = ( stat("$tmp_file") )[9];
    if ( ( $act_time - $tmp_time ) < $skip_time ) {
      print "                        skipped this time : ( $act_time - $tmp_time ) < $skip_time \n";
      return 0;
    }
  }

  # open a file with stored colours
  my @color_save = "";
  if ( -f "$file_color_save" ) {
    open( FHC, "< $file_color_save" ) || error( "file cannot be opened : $file_color_save " . __FILE__ . ":" . __LINE__ ) && return 0;
    @color_save = <FHC>;
    close(FHC);
  }

  my $type_edt = 0;
  if ( -f $type_edt_filev ) {
    $type_edt = 1;
  }

  open( FHL, ">> $list" ) || error( "Can't open $list : $!" . __FILE__ . ":" . __LINE__ ) && return 0;

  my $header = "DISK Custom group $group: last $text";
  $header = "NET Custom group $group: last $text" if $item eq "net";

  my $file    = "";
  my $i       = 0;
  my $lpar    = "";
  my $lparn   = "";
  my $cmd     = "";
  my $cmdx    = "";
  my $cmd_xpo = "";

  # from detail-graph.pl

  my $ds_name1       = "Disk_read";
  my $ds_name2       = "Disk_write";
  my $vertical_label = "Read-MB/sec-Write";
  my $g_format       = "6.2lf";
  my $divider        = 1000;

  if ( $item eq "net" ) {
    $ds_name1       = "Network_received";
    $ds_name2       = "Network_transmitted";
    $vertical_label = "Read-MB/sec-Write";
    $g_format       = "6.2lf";
    $divider        = 1000;
  }

  $cmd_xpo = "xport ";
  if ( -f "$basedir/tmp/rrdtool-xport-showtime" ) {
    $cmd_xpo .= " --showtime";
  }
  $cmd_xpo .= " --start now-1$type";
  $cmd_xpo .= " --end now-1$type+1$type";
  $cmd_xpo .= " --step $step_new";
  $cmd_xpo .= " --maxrows 65000";

  my $index = 0;

  my $lim_org = $lim;
  $lim =~ s/\.//;
  $lim =~ s/i/l/;

  $cmd .= "graph \\\"$name.png\\\"";
  $cmd .= " --title \\\"$header\\\"";
  $cmd .= " --start now-1$type";
  $cmd .= " --end now-1$type+1$type";
  $cmd .= " --imgformat PNG";
  $cmd .= " $disable_rrdtool_tag_agg";
  $cmd .= " --slope-mode";
  $cmd .= " --width=400";
  $cmd .= " --height=150";
  $cmd .= " --step=$step_new";
  $cmd .= " --lower-limit=0";
  $cmd .= " --color=BACK#$pic_col";
  $cmd .= " --color=SHADEA#$pic_col";
  $cmd .= " --color=SHADEB#$pic_col";
  $cmd .= " --color=CANVAS#$pic_col";

  #$cmd .= " --alt-autoscale-max";
  $cmd .= " --vertical-label=\\\"$vertical_label\\\"";
  $cmd .= " --units-exponent=1.00";
  $cmd .= " --alt-y-grid";
  $cmd .= " --x-grid=$xgrid";

  #$cmd .= " --base=1024";

  if ( $item =~ m/^disk/ ) {
    $cmd .= " COMMENT:\\\"Disk MB/sec\\l\\\"";
  }
  if ( $item =~ m/^net/ ) {
    $cmd .= " COMMENT:\\\"Network MB/sec\\l\\\"";
  }
  $cmd .= " COMMENT:\\\"  Server                        VM                        avrg     max\\l\\\"";

  my @gtype;
  $gtype[0] = "AREA";
  $gtype[1] = "STACK";
  my @lpars_graph_local = @lpars_graph;
  my $updated           = " ";

  my ( @recb, @trab, @avgx, @avgy );
  my $lnx     = 0;
  my $index_l = 0;
  my %uniq_files;
  my $newest_file_timestamp = 0;

  # do not sort it HERE!! there is several arrays, sorting lpars_graph is not enough!!! --PH
  foreach my $file_tmp (@lpars_graph_local) {
    my $file = $file_tmp;    # must be here to allocate new space and do not make changes in @lpars_graph
                             # e.g. $file_tmp /home/lpar2rrd/lpar2rrd/data/192.168.1.186/pavel.lpar2rrd.com/500fef73-b735-1602-88a4-787875fb7d52,RedHat-wrk,vm-87
    ( $file, my $vm_name, undef ) = split( /,/, $file );
    my $server      = ( split( /\//, $file ) )[-3];
    my $hmc_vm      = ( split( /\//, $file ) )[-2];
    my $server_name = $server;

    my $file_name = ( split( /\//, $file ) )[-1];
    $file = "$wrkdir/$all_vmware_VMs/$file_name.rrm";

    # print STDERR "4029 custom.pl \$file $file \$server $server\n";

    if ( $file eq '' ) {
      $index++;
      next;    #some trash
    }
    if ( !-f $file ) {
      $index++;
      next;
    }

    # avoid old lpars which do not exist in the period
    my $rrd_upd_time = ( stat("$file") )[9];
    if ( $rrd_upd_time < $req_time ) {
      $index++;
      next;
    }
    $lpar = $server_name;

    my $lpar_proc = "$lpar $delimiter " . "$vm_name";    # for html legend
    $lpar_proc =~ s/%/%%/g;
    $lpar_proc =~ s/:/\\:/g;
    $lpar_proc =~ s/\&\&1/\//g;

    $lpar =~ s/\&\&1/\//g;
    for ( my $k = length($lpar); $k < 25; $k++ ) {
      $lpar .= " ";
    }
    $lpar .= "   ";

    #$lpar .= $vm_name;
    $lpar =~ s/\&\&1/\//g;

    # to keep same count of characters
    $lpar =~ s/\\:/:/g;
    $lpar = sprintf( "%-25s", $lpar );
    $lpar =~ s/:/\\:/g;

    my $lpar_space_proc = $vm_name;

    my $lpar_space = "$lpar $lpar_space_proc";
    for ( my $k = length($lpar_space); $k < 50; $k++ ) {
      $lpar_space .= " ";
    }

    $lpar_space_proc = "$lpar $delimiter " . "$lpar_space_proc";
    $lpar_space_proc =~ s/\:/\\:/g;

    if ( exists $uniq_files{"$file"} ) {    # check duplicities
      $index++;
      next;
    }
    $uniq_files{"$file"} = 1;
    $lparn .= " ";
    print FHL "$file\n";
    if ( ( length($lpar_v) + 1 ) == length($comm) && length($lparn) == length($comm) ) {
      copy_source_org( $webdir, $tmpdir, $basedir, $lim_org, $lim, $group );
      last;
    }

    if ( $type =~ "d" ) {
      RRDp::cmd qq(last "$file");
      my $last_tt = RRDp::read;
      chomp($$last_tt);
      $newest_file_timestamp = $$last_tt if $$last_tt > $newest_file_timestamp;
    }

    my $file_legend = $file;
    $file_legend =~ s/%/%%/g;
    $file_legend =~ s/:/\\:/g;

    $index_l++;

    my $item_tmp = $item;

    #    $item_tmp =~ s/[1,2]$//;

    my $file_space = $file;
    if ( $file_space =~ m/ / ) {    # workaround for name with a space inside, nothing else works, grrr
      $file_space = "\"" . $file . "\"";
    }

    if ( $type_edt == 0 && $lparno == 4 ) {
      copy_source_org( $webdir, $tmpdir, $basedir, $lim_org, $lim, $group );
      last;
    }
    $lparno++;

    $lpar = $lpars_graph_server[$index];

    $lpar =~ s/\&\&1/\//g;
    for ( my $k = length($lpar); $k < 25; $k++ ) {
      $lpar .= " ";
    }

    # to keep same count of characters
    $lpar =~ s/\\:/:/g;
    $lpar = sprintf( "%-48s", $lpar );
    $lpar =~ s/:/\\:/g;

    for ( my $k = length($lpar); $k < 50; $k++ ) {
      $lpar .= " ";
    }

    # Found out stored color index to keep same color for the volume across all graphs
    my $file_color = $file;
    $file_color =~ s/\.r..$//;
    $file_color =~ s/\\//g;
    $file_color =~ s/:/===========doublecoma=========/g;
    my $color_indx_found = -1;
    $color_indx = 0;
    foreach my $line_col (@color_save) {
      chomp($line_col);
      if ( $line_col eq '' || $line_col !~ m/ : / ) {
        next;
      }
      $color_indx++;
      ( my $color_indx_found_act, my $volume_name_save ) = split( / : /, $line_col );

      # do not use here $volume_name_save '' as this does not work when volume id is zero!
      if ( $volume_name_save =~ m/^$file_color$/ ) {
        $color_indx_found = $color_indx_found_act;
        $color_indx       = $color_indx_found;
        last;
      }
    }
    if ( $color_indx_found == -1 ) {
      $color_file_change = 1;
      $color_save[$color_indx] = $color_indx . " : " . $file_color;
    }
    while ( $color_indx > $color_max ) {
      $color_indx = $color_indx - $color_max;
    }

    # end color

    # new system
    my $wrkdir_managedname_host_file = "$wrkdir/$all_vmware_VMs/$file_name.rrm";
    $wrkdir_managedname_host_file =~ s/:/\\:/g;

    #my $wrkdir_managedname_host_file_legend = $wrkdir_managedname_host_file;
    my $wrkdir_managedname_host_file_legend = "$wrkdir/$server/$hmc_vm/$file_name.rrm";
    $wrkdir_managedname_host_file_legend =~ s/%/%%/g;
    $wrkdir_managedname_host_file_legend =~ s/:/\\:/g;

    # bulid RRDTool cmd
    $recb[$i] = "rcb${i}";
    $trab[$i] = "trb${i}";
    $avgx[$i] = "avg${i}";
    $avgy[$i] = "avgy${i}";

    #      $cmd .= " DEF:$recb[$i]_nf=\\\"$wrkdir_managedname_host_file\\\":$ds_name1:AVERAGE";
    #      $cmd .= " DEF:$trab[$i]_nf=\\\"$wrkdir_managedname_host_file\\\":$ds_name2:AVERAGE";
    $cmd .= " DEF:$recb[$i]=\\\"$wrkdir_managedname_host_file\\\":$ds_name1:AVERAGE";
    $cmd .= " DEF:$trab[$i]=\\\"$wrkdir_managedname_host_file\\\":$ds_name2:AVERAGE";

    #      $cmd .= " CDEF:$recb[$i]=$recb[$i]_nf,$filter,GT,UNKN,$recb[$i]_nf,IF";
    #      $cmd .= " CDEF:$trab[$i]=$trab[$i]_nf,$filter,GT,UNKN,$trab[$i]_nf,IF";
    $cmd .= " CDEF:$recb[$i]-neg=$recb[$i],-1,*,$divider,/";
    $cmd .= " CDEF:$recb[$i]-mil=$recb[$i],$divider,/";
    $cmd .= " CDEF:$trab[$i]-mil=$trab[$i],$divider,/";
    $cmd .= " $gtype[$i>0]:$recb[$i]-neg$color[++$color_indx % ($color_max +1)]:\\\"R $lpar_space\\\"";
    $cmd .= " GPRINT:$recb[$i]-mil:AVERAGE:%$g_format";
    $cmd .= " GPRINT:$recb[$i]-mil:MAX:%$g_format\\l";

    $cmd .= " PRINT:$recb[$i]-mil:AVERAGE:\\\"%$g_format $delimiter multiview-$item $delimiter R $lpar_space_proc\\\"";                                            # for html legend
    $cmd .= " PRINT:$recb[$i]-mil:AVERAGE:\\\"%$g_format $delimiter $color[$color_indx % ($color_max +1)] $delimiter $wrkdir_managedname_host_file_legend\\\"";    # for html legend
    $cmd .= " PRINT:$recb[$i]-mil:MAX:\\\"%$g_format $delimiter\\\"";                                                                                              # for html legend

    $cmd .= " STACK:$lnx$color[++$color_indx % ($color_max +1)]:\\\"W $lpar_space\\\"";

    $cmd .= " GPRINT:$trab[$i]-mil:AVERAGE:%$g_format";
    $cmd .= " GPRINT:$trab[$i]-mil:MAX:%$g_format\\l";

    $cmd .= " PRINT:$trab[$i]-mil:AVERAGE:\\\"%$g_format $delimiter multiview-$item $delimiter W $lpar_space_proc\\\"";                                            # for html legend
    $cmd .= " PRINT:$trab[$i]-mil:AVERAGE:\\\"%$g_format $delimiter $color[$color_indx % ($color_max +1)] $delimiter $wrkdir_managedname_host_file_legend\\\"";    # for html legend
    $cmd .= " PRINT:$trab[$i]-mil:MAX:\\\"%$g_format $delimiter\\\"";                                                                                              # for html legend

    if ( $i == 0 ) {
      $cmdx .= " LINE1:$lnx:";
    }
    $cmdx .= " $gtype[$i>0]:$trab[$i++]-mil$color[$color_indx % ($color_max +1)]:";
    $index++;

    #    if ( ! get_lpar_num() && $index_l > 4 ) {
    #      last;
    #    }
  }
  $cmd .= $cmdx;

  close(FHL);

  if ( $i == 0 ) {
    print "creating cgraph: " . scalar localtime() . " custom:$group $item $type: no any source found, skipping\n";

    # if there is not CMD file, create at least emty graph
    return 0 if -f $tmp_file;    # nothing has been found
  }
  if ( $newest_file_timestamp > 0 ) {
    my $l = localtime($newest_file_timestamp);

    # following must be for RRD 1.2+
    $l =~ s/:/\\:/g;
    $updated = " COMMENT:\\\"  Updated\\\: $l \\\"";
  }

  $cmd .= " $updated";
  $cmd .= " HRULE:0#000000";

  # $cmd .= " VRULE:0#000000";  --> it is causing sigsegv on linuxeS
  $cmd =~ s/\\"/"/g;

  open( FH, "> $tmp_file" ) || error( "Can't open $tmp_file : $!" . __FILE__ . ":" . __LINE__ ) && return 0;
  print FH "$cmd\n";
  close(FH);

  #
  # do not execute it here
  # execute it in the run time based on cmd stored in $tmp_file
  #

  # write colors into a file
  if ( $color_file_change == 1 ) {
    open( FHC, "> $file_color_save" ) || error( "file cannot be created :  $file_color_save " . __FILE__ . ":" . __LINE__ ) && return 0;
    foreach my $line_cs (@color_save) {
      chomp($line_cs);    # it must be there, somehow appear there \n ...
      if ( $line_cs eq '' ) {
        next;
      }
      if ( $line_cs =~ m/ : / ) {
        print FHC "$line_cs\n";
      }
    }
    close(FHC);
  }

  # colours

  return 1;
}

################################################################################

# XENVM
sub multiview_xenvm {
  my $group    = shift;
  my $name     = shift;
  my $type     = shift;
  my $type_sam = shift;
  my $act_time = shift;
  my $step_new = shift;
  my $text     = shift;
  my $xgrid    = shift;
  my $item     = shift;

  # $item toggles graph type (CPU, memory etc.), use CPU by default
  $item = 'cpu-percent' if !defined $item;

  my $req_time = 0;
  my $comm     = "COMM ";
  $color_indx = 0;    # clear color index
  my $list              = "$webdir/custom/$group/list.txt";
  my $lim               = ".li";
  my $updated           = "";
  my $color_file_change = 0;
  my $file_color_save   = "$basedir/tmp/custom-group-$group.col";
  my $lparno            = 0;

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
    $req_time  = $act_time - 31536000;
    $skip_time = $YEAR_REFRESH;
  }

  # modified filename for XENVM
  my $tmp_file = "$tmpdir/custom-group-xenvm-${item}-$group-$type.cmd";

  # do not update weekly/monthly/yearly command files each run
  if ( -f "$tmp_file" ) {
    my $tmp_time = ( stat("$tmp_file") )[9];
    if ( ( $act_time - $tmp_time ) < $skip_time ) {
      print "                        skipped this time : ( $act_time - $tmp_time ) < $skip_time \n";
      return 0;
    }
  }

  # open a file with stored colours
  my @color_save = "";
  if ( -f "$file_color_save" ) {
    open( FHC, "< $file_color_save" ) || error( "file cannot be opened : $file_color_save " . __FILE__ . ":" . __LINE__ ) && return 0;
    @color_save = <FHC>;
    close(FHC);
  }

  my $type_edt = 0;
  if ( -f $type_edt_filex ) {
    $type_edt = 1;
  }

  if ( $item eq 'cpu-percent' ) {
    open( FHL, "> $list" ) || error( "Can't open $list : $!" . __FILE__ . ":" . __LINE__ ) && return 0;
  }
  else {
    open( FHL, ">> $list" ) || error( "Can't open $list : $!" . __FILE__ . ":" . __LINE__ ) && return 0;
  }

  # header adjusted for XenServer (eventually switch to XenServerGraph::get_header)
  my $header = "XenServer VM custom group $group";
  $header .= " : last $text";

  my $file    = "";
  my $i       = 0;
  my $lpar    = "";
  my $lparn   = "";
  my $cmd     = "";
  my $cmdx    = "";
  my $cmdx2   = "";
  my $cmd_xpo = "";    # unused here, unlike in multiview_vims (VMware)
  my $j       = 0;

  my $lim_org = $lim;
  $lim =~ s/\.//;
  $lim =~ s/i/l/;

  # get rrdtool params for XenServer metrics (based on $item)
  my $cmd_params;
  if ( $item =~ m/^cpu-percent$/ ) {
    $cmd_params = XenServerGraph::get_params_cpu('percent');
  }
  elsif ( $item =~ m/^cpu-cores$/ ) {
    $cmd_params = XenServerGraph::get_params_cpu('cores');
  }
  elsif ( $item =~ m/^memory/ ) {
    $cmd_params = XenServerGraph::get_params_memory();
  }
  elsif ( $item =~ m/^vbd/ ) {
    if ( $item =~ m/^vbd$/ ) {
      $cmd_params = XenServerGraph::get_params_storage();
    }
    elsif ( $item =~ m/^vbd-latency$/ ) {
      $cmd_params = XenServerGraph::get_params_storage('latency');
    }
    elsif ( $item =~ m/^vbd-iops$/ ) {
      $cmd_params = XenServerGraph::get_params_storage('iops');
    }
  }
  elsif ( $item =~ m/^lan$/ ) {
    $cmd_params = XenServerGraph::get_params_lan();
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
  $cmd .= " --step=$step_new";
  $cmd .= " --color=BACK#$pic_col";
  $cmd .= " --color=SHADEA#$pic_col";
  $cmd .= " --color=SHADEB#$pic_col";
  $cmd .= " --color=CANVAS#$pic_col";
  $cmd .= " --units-exponent=1.00";
  $cmd .= " --alt-y-grid";
  $cmd .= " --x-grid=$xgrid";
  $cmd .= $cmd_params;

  # legends adjusted for XenServer (based on oVirt)
  if ( $item =~ m/^cpu-percent$/ ) {
    $cmd .= " COMMENT:\"[%]\"";
  }
  elsif ( $item =~ m/^cpu-cores$/ ) {
    $cmd .= " COMMENT:\"[cores]\"";
  }
  elsif ( $item =~ m/^memory/ ) {
    $cmd .= " COMMENT:\"[GB]\\n\"";
  }
  elsif ( $item =~ m/^vbd$/ ) {
    $cmd .= " COMMENT:\"[MiB/s]\\n\"";
  }
  elsif ( $item =~ m/^vbd-latency$/ ) {
    $cmd .= " COMMENT:\"[millisec]\\n\"";
  }
  elsif ( $item =~ m/^vbd-iops$/ ) {
    $cmd .= " COMMENT:\"[iops]\\n\"";
  }
  elsif ( $item =~ m/^lan$/ ) {
    $cmd .= " COMMENT:\"[MB/s]\\n\"";
  }

  if ( $item =~ m/(vbd|lan)/ ) {
    $cmd .= " COMMENT:\"Pool                  VM                                     Read      Avrg       Max    Write      Avrg      Max\\n\"";
  }
  else {
    $cmd .= " COMMENT:\"Pool                  VM                                     Avrg     Max\\n\"";
  }

  my $index             = 0;
  my @lpars_graph_local = @lpars_graph;

  my %uniq_files;
  my $newest_file_timestamp = 0;

  # do not sort it HERE!! there is several arrays, sorting lpars_graph is not enough!!! --PH
  foreach my $file_tmp (@lpars_graph_local) {

    # filename
    my $file = $file_tmp;    # must be here to allocate new space and do not make changes in @lpars_graph

    # load labels
    my $vm_name     = $lpars_graph_name[$index];      # VM label
    my $server      = $lpars_graph_server[$index];    # pool label
    my $server_name = $server;                        # pool label

    # TODO debug print
    # print "custom.pl DEBUG pre-graph\n\t$file\t$vm_name\t$server\t$server_name\n";

    if ( $file eq '' ) {
      $index++;
      next;    #some trash
    }
    if ( !-f $file ) {
      $index++;
      next;
    }

    # avoid old lpars which do not exist in the period
    my $rrd_upd_time = ( stat("$file") )[9];
    if ( $rrd_upd_time < $req_time ) {
      $index++;
      next;
    }

    $lpar = $server_name;

    my $lpar_proc = "$lpar $delimiter " . "$vm_name";    # for html legend
    $lpar_proc =~ s/%/%%/g;
    $lpar_proc =~ s/:/\\:/g;
    $lpar_proc =~ s/\&\&1/\//g;

    $lpar =~ s/\&\&1/\//g;
    for ( my $k = length($lpar); $k < 25; $k++ ) {
      $lpar .= " ";
    }
    $lpar .= "   ";
    $lpar .= $vm_name;
    $lpar =~ s/\&\&1/\//g;

    # to keep same count of characters
    $lpar =~ s/\\:/:/g;
    $lpar = sprintf( "%-25s", $lpar );
    $lpar =~ s/:/\\:/g;

    # TODO copied from VMware, could be simplified
    my $lpar_space_proc = $vm_name;
    my $lpar_space      = "$lpar $lpar_space_proc";
    for ( my $k = length($lpar_space); $k < 50; $k++ ) {
      $lpar_space .= " ";
    }

    $lpar_space_proc = "$lpar $delimiter " . "$lpar_space_proc";
    $lpar_space_proc =~ s/\:/\\:/g;

    if ( exists $uniq_files{"$file"} ) {    # check duplicities
      $index++;
      next;
    }
    $uniq_files{"$file"} = 1;
    $lparn .= " ";
    print FHL "$file\n";

    if ( ( length($lpar_v) + 1 ) == length($comm) && length($lparn) == length($comm) ) {
      copy_source_org( $webdir, $tmpdir, $basedir, $lim_org, $lim, $group );
      last;
    }

    if ( $type =~ "d" ) {
      RRDp::cmd qq(last "$file");
      my $last_tt = RRDp::read;
      chomp($$last_tt);
      $newest_file_timestamp = $$last_tt if $$last_tt > $newest_file_timestamp;
    }

    if ( $type_edt == 0 && $lparno == 4 ) {
      copy_source_org( $webdir, $tmpdir, $basedir, $lim_org, $lim, $group );
      last;
    }
    $lparno++;

    # Found out stored color index to keep same color for the volume across all graphs
    my $file_color = $file;
    $file_color =~ s/\.r..$//;
    $file_color =~ s/\\//g;
    $file_color =~ s/:/===========doublecoma=========/g;
    my $color_indx_found = -1;
    $color_indx = 0;

    foreach my $line_col (@color_save) {
      chomp($line_col);
      if ( $line_col eq '' || $line_col !~ m/ : / ) {
        next;
      }
      $color_indx++;
      ( my $color_indx_found_act, my $volume_name_save ) = split( / : /, $line_col );

      # do not use here $volume_name_save '' as this does not work when volume id is zero!
      if ( $volume_name_save =~ m/^$file_color$/ ) {
        $color_indx_found = $color_indx_found_act;
        $color_indx       = $color_indx_found;
        last;
      }
    }
    if ( $color_indx_found == -1 ) {
      $color_file_change = 1;
      $color_save[$color_indx] = $color_indx . " : " . $file_color;
    }
    while ( $color_indx > $color_max ) {
      $color_indx = $color_indx - $color_max;
    }

    # end color

    # note: replace colons in VM label
    my $vm_name_escaped = $vm_name;
    $vm_name_escaped =~ s/:/\\:/g;

    # create the graph command itself
    $color_indx = ++$color_indx % ( $color_max + 1 );
    my $itemcolor = $color[ $color_indx % ( $color_max + 1 ) ];
    my $itemlabel = "$vm_name_escaped";                           # $lpar_space_proc
    my $poollabel = "$server_name";

    my $graph_info;
    if ( $item =~ m/^cpu-percent/ ) {
      $graph_info = XenServerGraph::graph_cpu_aggr( 'vm', 'percent', $file, $i, $itemcolor, $itemlabel, $poollabel, 'pool' );
    }
    elsif ( $item =~ m/^cpu-cores/ ) {
      $graph_info = XenServerGraph::graph_cpu_aggr( 'vm', 'cores', $file, $i, $itemcolor, $itemlabel, $poollabel, 'pool' );
    }
    elsif ( $item =~ m/^memory-used/ ) {
      $graph_info = XenServerGraph::graph_memory_aggr( 'vm', 'used', $file, $i, $itemcolor, $itemlabel, $poollabel, 'pool' );
    }
    elsif ( $item =~ m/^memory-free/ ) {
      $graph_info = XenServerGraph::graph_memory_aggr( 'vm', 'free', $file, $i, $itemcolor, $itemlabel, $poollabel, 'pool' );
    }
    elsif ( $item =~ m/^(vbd|lan)/ ) {

      # need second color
      $color_indx = ++$color_indx % ( $color_max + 1 );
      my $itemcolor2 = $color[ $color_indx % ( $color_max + 1 ) ];
      if ( $item =~ m/^vbd$/ ) {
        $graph_info = XenServerGraph::graph_storage_aggr( 'vm', 'vbd', $file, $i, $itemcolor, $itemcolor2, $itemlabel, $poollabel );
      }
      elsif ( $item =~ m/^vbd-latency$/ ) {
        $graph_info = XenServerGraph::graph_storage_aggr( 'vm', 'latency', $file, $i, $itemcolor, $itemcolor2, $itemlabel, $poollabel );
      }
      elsif ( $item =~ m/^vbd-iops$/ ) {
        $graph_info = XenServerGraph::graph_storage_aggr( 'vm', 'iops', $file, $i, $itemcolor, $itemcolor2, $itemlabel, $poollabel );
      }
      elsif ( $item =~ m/^lan$/ ) {
        $graph_info = XenServerGraph::graph_lan_aggr( 'vm', $file, $i, $itemcolor, $itemcolor2, $itemlabel, $poollabel );
      }
    }
    else {
      error("multiview_xenvm unsupported item $item");
    }
    $cmd .= $graph_info->{cmd_def};
    $cmd .= $graph_info->{cmd_cdef};
    if ( $item =~ m/^(cpu|memory)/ ) {
      $cmdx .= $graph_info->{cmd_legend};
    }
    else {
      $cmdx  .= $graph_info->{cmd_legend_lower};
      $cmdx2 .= $graph_info->{cmd_legend_upper};
    }

    $i++;

    # done

    $index++;

    #    if ( ! get_lpar_num() && $index_l > 4 ) {
    #      last;
    #    }
  }
  $cmd .= $cmdx;
  $cmd .= $cmdx2;

  close(FHL);

  if ( $i == 0 ) {
    print "creating cgraph: " . scalar localtime() . " custom:$group $item $type: no any source found, skipping\n";

    # if there is not CMD file, create at least emty graph
    return 0 if -f $tmp_file;    # nothing has been found
  }
  if ( $newest_file_timestamp > 0 ) {
    my $l = localtime($newest_file_timestamp);

    # following must be for RRD 1.2+
    $l =~ s/:/\\:/g;
    $updated = " COMMENT:\\\"  Updated\\\: $l \\\"";
  }

  $cmd .= " $updated";
  $cmd .= " HRULE:0#000000";

  # $cmd .= " VRULE:0#000000";  --> it is causing sigsegv on linuxeS
  $cmd =~ s/\\"/"/g;

  open( FH, "> $tmp_file" ) || error( "Can't open $tmp_file : $!" . __FILE__ . ":" . __LINE__ ) && return 0;
  print FH "$cmd\n";
  close(FH);

  #
  # do not execute it here
  # execute it in the run time based on cmd stored in $tmp_file
  #

  # write colors into a file
  if ( $color_file_change == 1 ) {
    open( FHC, "> $file_color_save" ) || error( "file cannot be created :  $file_color_save " . __FILE__ . ":" . __LINE__ ) && return 0;
    foreach my $line_cs (@color_save) {
      chomp($line_cs);    # it must be there, somehow appear there \n ...
      if ( $line_cs eq '' ) {
        next;
      }
      if ( $line_cs =~ m/ : / ) {
        print FHC "$line_cs\n";
      }
    }
    close(FHC);
  }

  # colours

  return 1;
}

# NUTANIXVM
sub multiview_nutanixvm {
  my $group    = shift;
  my $name     = shift;
  my $type     = shift;
  my $type_sam = shift;
  my $act_time = shift;
  my $step_new = shift;
  my $text     = shift;
  my $xgrid    = shift;
  my $item     = shift;

  # $item toggles graph type (CPU, memory etc.), use CPU by default
  $item = 'cpu-percent' if !defined $item;

  my $req_time = 0;
  my $comm     = "COMM ";
  $color_indx = 0;    # clear color index
  my $list              = "$webdir/custom/$group/list.txt";
  my $lim               = ".li";
  my $updated           = "";
  my $color_file_change = 0;
  my $file_color_save   = "$basedir/tmp/custom-group-$group.col";
  my $lparno            = 0;

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
    $req_time  = $act_time - 31536000;
    $skip_time = $YEAR_REFRESH;
  }

  # modified filename for NUTANIXVM
  my $tmp_file = "$tmpdir/custom-group-nutanixvm-${item}-$group-$type.cmd";

  # do not update weekly/monthly/yearly command files each run
  if ( -f "$tmp_file" ) {
    my $tmp_time = ( stat("$tmp_file") )[9];
    if ( ( $act_time - $tmp_time ) < $skip_time ) {
      print "                        skipped this time : ( $act_time - $tmp_time ) < $skip_time \n";
      return 0;
    }
  }

  # open a file with stored colours
  my @color_save = "";
  if ( -f "$file_color_save" ) {
    open( FHC, "< $file_color_save" ) || error( "file cannot be opened : $file_color_save " . __FILE__ . ":" . __LINE__ ) && return 0;
    @color_save = <FHC>;
    close(FHC);
  }

  my $type_edt = 0;
  if ( -f $type_edt_filex ) {
    $type_edt = 1;
  }

  if ( $item eq 'cpu-percent' ) {
    open( FHL, "> $list" ) || error( "Can't open $list : $!" . __FILE__ . ":" . __LINE__ ) && return 0;
  }
  else {
    open( FHL, ">> $list" ) || error( "Can't open $list : $!" . __FILE__ . ":" . __LINE__ ) && return 0;
  }

  # header adjusted for Nutanix
  my $header = "Nutanix VM custom group $group";
  $header .= " : last $text";

  my $file    = "";
  my $i       = 0;
  my $lpar    = "";
  my $lparn   = "";
  my $cmd     = "";
  my $cmdx    = "";
  my $cmdx2   = "";
  my $cmd_xpo = "";    # unused here, unlike in multiview_vims (VMware)
  my $j       = 0;

  my $lim_org = $lim;
  $lim =~ s/\.//;
  $lim =~ s/i/l/;

  # get rrdtool params for Nutanix metrics (based on $item)
  my $cmd_params;
  if ( $item =~ m/^cpu-percent$/ ) {
    $cmd_params = NutanixGraph::get_params_cpu('percent');
  }
  elsif ( $item =~ m/^cpu-cores$/ ) {
    $cmd_params = NutanixGraph::get_params_cpu('cores');
  }
  elsif ( $item =~ m/^memory/ ) {
    $cmd_params = NutanixGraph::get_params_memory();
  }
  elsif ( $item =~ m/^vbd/ ) {
    if ( $item =~ m/^vbd$/ ) {
      $cmd_params = NutanixGraph::get_params_storage();
    }
    elsif ( $item =~ m/^vbd-latency$/ ) {
      $cmd_params = NutanixGraph::get_params_storage('latency');
    }
    elsif ( $item =~ m/^vbd-iops$/ ) {
      $cmd_params = NutanixGraph::get_params_storage('iops');
    }
  }
  elsif ( $item =~ m/^lan$/ ) {
    $cmd_params = NutanixGraph::get_params_lan();
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
  $cmd .= " --step=$step_new";
  $cmd .= " --color=BACK#$pic_col";
  $cmd .= " --color=SHADEA#$pic_col";
  $cmd .= " --color=SHADEB#$pic_col";
  $cmd .= " --color=CANVAS#$pic_col";
  $cmd .= " --units-exponent=1.00";
  $cmd .= " --alt-y-grid";
  $cmd .= " --x-grid=$xgrid";
  $cmd .= $cmd_params;

  # legends adjusted for Nutanix (based on XenServer)
  if ( $item =~ m/^cpu-percent$/ ) {
    $cmd .= " COMMENT:\"[%]\"";
  }
  elsif ( $item =~ m/^cpu-cores$/ ) {
    $cmd .= " COMMENT:\"[cores]\"";
  }
  elsif ( $item =~ m/^memory/ ) {
    $cmd .= " COMMENT:\"[GB]\\n\"";
  }
  elsif ( $item =~ m/^vbd$/ ) {
    $cmd .= " COMMENT:\"[MiB/s]\\n\"";
  }
  elsif ( $item =~ m/^vbd-latency$/ ) {
    $cmd .= " COMMENT:\"[millisec]\\n\"";
  }
  elsif ( $item =~ m/^vbd-iops$/ ) {
    $cmd .= " COMMENT:\"[iops]\\n\"";
  }
  elsif ( $item =~ m/^lan$/ ) {
    $cmd .= " COMMENT:\"[MB/s]\\n\"";
  }

  if ( $item =~ m/(vbd|lan)/ ) {
    $cmd .= " COMMENT:\"Pool                  VM                                     Read      Avrg       Max    Write      Avrg      Max\\n\"";
  }
  else {
    $cmd .= " COMMENT:\"Pool                  VM                                     Avrg     Max\\n\"";
  }

  my $index             = 0;
  my @lpars_graph_local = @lpars_graph;

  my %uniq_files;
  my $newest_file_timestamp = 0;

  # do not sort it HERE!! there is several arrays, sorting lpars_graph is not enough!!! --PH
  foreach my $file_tmp (@lpars_graph_local) {

    # filename
    my $file = $file_tmp;    # must be here to allocate new space and do not make changes in @lpars_graph

    # load labels
    my $vm_name     = $lpars_graph_name[$index];      # VM label
    my $server      = $lpars_graph_server[$index];    # pool label
    my $server_name = $server;                        # pool label

    # TODO debug print
    # print "custom.pl DEBUG pre-graph\n\t$file\t$vm_name\t$server\t$server_name\n";

    if ( $file eq '' ) {
      $index++;
      next;    #some trash
    }
    if ( !-f $file ) {
      $index++;
      next;
    }

    # avoid old lpars which do not exist in the period
    my $rrd_upd_time = ( stat("$file") )[9];
    if ( $rrd_upd_time < $req_time ) {
      $index++;
      next;
    }

    $lpar = $server_name;

    my $lpar_proc = "$lpar $delimiter " . "$vm_name";    # for html legend
    $lpar_proc =~ s/%/%%/g;
    $lpar_proc =~ s/:/\\:/g;
    $lpar_proc =~ s/\&\&1/\//g;

    $lpar =~ s/\&\&1/\//g;
    for ( my $k = length($lpar); $k < 25; $k++ ) {
      $lpar .= " ";
    }
    $lpar .= "   ";
    $lpar .= $vm_name;
    $lpar =~ s/\&\&1/\//g;

    # to keep same count of characters
    $lpar =~ s/\\:/:/g;
    $lpar = sprintf( "%-25s", $lpar );
    $lpar =~ s/:/\\:/g;

    # TODO copied from VMware, could be simplified
    my $lpar_space_proc = $vm_name;
    my $lpar_space      = "$lpar $lpar_space_proc";
    for ( my $k = length($lpar_space); $k < 50; $k++ ) {
      $lpar_space .= " ";
    }

    $lpar_space_proc = "$lpar $delimiter " . "$lpar_space_proc";
    $lpar_space_proc =~ s/\:/\\:/g;

    if ( exists $uniq_files{"$file"} ) {    # check duplicities
      $index++;
      next;
    }
    $uniq_files{"$file"} = 1;
    $lparn .= " ";
    print FHL "$file\n";

    if ( ( length($lpar_v) + 1 ) == length($comm) && length($lparn) == length($comm) ) {
      copy_source_org( $webdir, $tmpdir, $basedir, $lim_org, $lim, $group );
      last;
    }
    if ( $type =~ "d" ) {
      RRDp::cmd qq(last "$file");
      my $last_tt = RRDp::read;
      chomp($$last_tt);
      $newest_file_timestamp = $$last_tt if $$last_tt > $newest_file_timestamp;
    }

    if ( $type_edt == 0 && $lparno == 4 ) {
      copy_source_org( $webdir, $tmpdir, $basedir, $lim_org, $lim, $group );
      last;
    }
    $lparno++;

    # Found out stored color index to keep same color for the volume across all graphs
    my $file_color = $file;
    $file_color =~ s/\.r..$//;
    $file_color =~ s/\\//g;
    $file_color =~ s/:/===========doublecoma=========/g;
    my $color_indx_found = -1;
    $color_indx = 0;

    foreach my $line_col (@color_save) {
      chomp($line_col);
      if ( $line_col eq '' || $line_col !~ m/ : / ) {
        next;
      }
      $color_indx++;
      ( my $color_indx_found_act, my $volume_name_save ) = split( / : /, $line_col );

      # do not use here $volume_name_save '' as this does not work when volume id is zero!
      if ( $volume_name_save =~ m/^$file_color$/ ) {
        $color_indx_found = $color_indx_found_act;
        $color_indx       = $color_indx_found;
        last;
      }
    }
    if ( $color_indx_found == -1 ) {
      $color_file_change = 1;
      $color_save[$color_indx] = $color_indx . " : " . $file_color;
    }
    while ( $color_indx > $color_max ) {
      $color_indx = $color_indx - $color_max;
    }

    # end color
    # note: replace colons in VM label
    my $vm_name_escaped = $vm_name;
    $vm_name_escaped =~ s/:/\\:/g;

    # create the graph command itself
    $color_indx = ++$color_indx % ( $color_max + 1 );
    my $itemcolor = $color[ $color_indx % ( $color_max + 1 ) ];
    my $itemlabel = "$vm_name_escaped";                           # $lpar_space_proc
    my $poollabel = "$server_name";
    my $graph_info;
    if ( $item =~ m/^cpu-percent/ ) {
      $graph_info = NutanixGraph::graph_cpu_aggr( 'vm', 'percent', $file, $i, $itemcolor, $itemlabel, $poollabel, 'pool' );
    }
    elsif ( $item =~ m/^cpu-cores/ ) {
      $graph_info = NutanixGraph::graph_cpu_aggr( 'vm', 'cores', $file, $i, $itemcolor, $itemlabel, $poollabel, 'pool' );
    }
    elsif ( $item =~ m/^memory-used/ ) {
      $graph_info = NutanixGraph::graph_memory_aggr( 'vm', 'used', $file, $i, $itemcolor, $itemlabel, $poollabel, 'pool' );
    }
    elsif ( $item =~ m/^memory-free/ ) {
      $graph_info = NutanixGraph::graph_memory_aggr( 'vm', 'free', $file, $i, $itemcolor, $itemlabel, $poollabel, 'pool' );
    }
    elsif ( $item =~ m/^(vbd|lan)/ ) {

      # need second color
      $color_indx = ++$color_indx % ( $color_max + 1 );
      my $itemcolor2 = $color[ $color_indx % ( $color_max + 1 ) ];
      if ( $item =~ m/^vbd$/ ) {
        $graph_info = NutanixGraph::graph_storage_aggr( 'vm', 'vbd', $file, $i, $itemcolor, $itemcolor2, $itemlabel, $poollabel );
      }
      elsif ( $item =~ m/^vbd-latency$/ ) {
        $graph_info = NutanixGraph::graph_storage_aggr( 'vm', 'latency', $file, $i, $itemcolor, $itemcolor2, $itemlabel, $poollabel );
      }
      elsif ( $item =~ m/^vbd-iops$/ ) {
        $graph_info = NutanixGraph::graph_storage_aggr( 'vm', 'iops', $file, $i, $itemcolor, $itemcolor2, $itemlabel, $poollabel );
      }
      elsif ( $item =~ m/^lan$/ ) {
        $graph_info = NutanixGraph::graph_lan_aggr( 'vm', $file, $i, $itemcolor, $itemcolor2, $itemlabel, $poollabel );
      }
    }
    else {
      error("multiview_nutanixvm unsupported item $item");
    }
    $cmd .= $graph_info->{cmd_def};
    $cmd .= $graph_info->{cmd_cdef};
    if ( $item =~ m/^(cpu|memory)/ ) {
      $cmdx .= $graph_info->{cmd_legend};
    }
    else {
      $cmdx  .= $graph_info->{cmd_legend_lower};
      $cmdx2 .= $graph_info->{cmd_legend_upper};
    }

    $i++;

    # done

    $index++;

    #    if ( ! get_lpar_num() && $index_l > 4 ) {
    #      last;
    #    }
  }
  $cmd .= $cmdx;
  $cmd .= $cmdx2;

  close(FHL);

  if ( $i == 0 ) {
    print "creating cgraph: " . scalar localtime() . " custom:$group $item $type: no any source found, skipping\n";

    # if there is not CMD file, create at least emty graph
    return 0 if -f $tmp_file;    # nothing has been found
  }
  if ( $newest_file_timestamp > 0 ) {
    my $l = localtime($newest_file_timestamp);

    # following must be for RRD 1.2+
    $l =~ s/:/\\:/g;
    $updated = " COMMENT:\\\"  Updated\\\: $l \\\"";
  }

  $cmd .= " $updated";
  $cmd .= " HRULE:0#000000";

  # $cmd .= " VRULE:0#000000";  --> it is causing sigsegv on linuxeS
  $cmd =~ s/\\"/"/g;

  open( FH, "> $tmp_file" ) || error( "Can't open $tmp_file : $!" . __FILE__ . ":" . __LINE__ ) && return 0;
  print FH "$cmd\n";
  close(FH);
  #
  # do not execute it here
  # execute it in the run time based on cmd stored in $tmp_file
  #

  # write colors into a file
  if ( $color_file_change == 1 ) {
    open( FHC, "> $file_color_save" ) || error( "file cannot be created :  $file_color_save " . __FILE__ . ":" . __LINE__ ) && return 0;
    foreach my $line_cs (@color_save) {
      chomp($line_cs);    # it must be there, somehow appear there \n ...
      if ( $line_cs eq '' ) {
        next;
      }
      if ( $line_cs =~ m/ : / ) {
        print FHC "$line_cs\n";
      }
    }
    close(FHC);
  }

  # colours

  return 1;
}

# PROXMOXVM
sub multiview_proxmoxvm {
  my $group    = shift;
  my $name     = shift;
  my $type     = shift;
  my $type_sam = shift;
  my $act_time = shift;
  my $step_new = shift;
  my $text     = shift;
  my $xgrid    = shift;
  my $item     = shift;

  # $item toggles graph type (CPU, memory etc.), use CPU by default
  $item = 'cpu-percent' if !defined $item;

  my $req_time = 0;
  my $comm     = "COMM ";
  $color_indx = 0;    # clear color index
  my $list              = "$webdir/custom/$group/list.txt";
  my $lim               = ".li";
  my $updated           = "";
  my $color_file_change = 0;
  my $file_color_save   = "$basedir/tmp/custom-group-$group.col";
  my $lparno            = 0;

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
    $req_time  = $act_time - 31536000;
    $skip_time = $YEAR_REFRESH;
  }

  # modified filename for PROXMOXVM
  my $tmp_file = "$tmpdir/custom-group-proxmoxvm-${item}-$group-$type.cmd";

  # do not update weekly/monthly/yearly command files each run
  if ( -f "$tmp_file" ) {
    my $tmp_time = ( stat("$tmp_file") )[9];
    if ( ( $act_time - $tmp_time ) < $skip_time ) {
      print "                        skipped this time : ( $act_time - $tmp_time ) < $skip_time \n";
      return 0;
    }
  }

  # open a file with stored colours
  my @color_save = "";
  if ( -f "$file_color_save" ) {
    open( FHC, "< $file_color_save" ) || error( "file cannot be opened : $file_color_save " . __FILE__ . ":" . __LINE__ ) && return 0;
    @color_save = <FHC>;
    close(FHC);
  }

  my $type_edt = 0;
  if ( -f $type_edt_filex ) {
    $type_edt = 1;
  }

  if ( $item eq 'cpu-percent' ) {
    open( FHL, "> $list" ) || error( "Can't open $list : $!" . __FILE__ . ":" . __LINE__ ) && return 0;
  }
  else {
    open( FHL, ">> $list" ) || error( "Can't open $list : $!" . __FILE__ . ":" . __LINE__ ) && return 0;
  }

  # header adjusted for Proxmox
  my $header = "Proxmox VM custom group $group";
  $header .= " : last $text";

  my $file    = "";
  my $i       = 0;
  my $lpar    = "";
  my $lparn   = "";
  my $cmd     = "";
  my $cmdx    = "";
  my $cmdx2   = "";
  my $cmd_xpo = "";    # unused here, unlike in multiview_vims (VMware)
  my $j       = 0;

  my $lim_org = $lim;
  $lim =~ s/\.//;
  $lim =~ s/i/l/;

  # get rrdtool params for Proxmox metrics (based on $item)
  my $cmd_params;
  if ( $item =~ m/^cpu-percent$/ ) {
    $cmd_params = ProxmoxGraph::get_params_custom('CPU usage in [%]');
  }
  elsif ( $item =~ m/^cpu$/ ) {
    $cmd_params = ProxmoxGraph::get_params_custom('CPU usage in [cores]');
  }
  elsif ( $item =~ m/^memory/ ) {
    $cmd_params = ProxmoxGraph::get_params_custom('Memory in [GB]');
  }
  elsif ( $item =~ m/^net$/ || $item =~ m/^data$/ ) {
    $cmd_params = ProxmoxGraph::get_params_custom('Read - MB/sec - Write');
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
  $cmd .= " --step=$step_new";
  $cmd .= " --color=BACK#$pic_col";
  $cmd .= " --color=SHADEA#$pic_col";
  $cmd .= " --color=SHADEB#$pic_col";
  $cmd .= " --color=CANVAS#$pic_col";
  $cmd .= " --units-exponent=1.00";
  $cmd .= " --alt-y-grid";
  $cmd .= " --x-grid=$xgrid";
  $cmd .= $cmd_params;

  # legends adjusted for Proxmox
  if ( $item =~ m/^cpu-percent$/ || $item =~ m/^mem-percent$/ ) {
    $cmd .= " COMMENT:\"[%]\"";
  }
  elsif ( $item =~ m/^cpu$/ ) {
    $cmd .= " COMMENT:\"[cores]\"";
  }
  elsif ( $item =~ m/^mem/ ) {
    $cmd .= " COMMENT:\"[GB]\\n\"";
  }
  elsif ( $item =~ m/^data$/ || $item =~ m/^net$/ ) {
    $cmd .= " COMMENT:\"[MB/s]\\n\"";
  }
  elsif ( $item =~ m/^ticks$/ ) {
    $cmd .= " COMMENT:\"[millisec]\\n\"";
  }
  elsif ( $item =~ m/^ios$/ ) {
    $cmd .= " COMMENT:\"[iops]\\n\"";
  }

  if ( $item =~ m/(data|net|ios|ticks)/ ) {
    $cmd .= " COMMENT:\"Cluster                  VM                                     Read      Avrg       Max    Write      Avrg      Max\\n\"";
  }
  else {
    $cmd .= " COMMENT:\"Cluster                  VM                                     Avrg     Max\\n\"";
  }

  my $index             = 0;
  my @lpars_graph_local = @lpars_graph;

  my %uniq_files;
  my $newest_file_timestamp = 0;

  foreach my $file_tmp (@lpars_graph_local) {

    # filename
    my $file = $file_tmp;    # must be here to allocate new space and do not make changes in @lpars_graph

    # load labels
    my $vm_name     = $lpars_graph_name[$index];      # VM label
    my $server      = $lpars_graph_server[$index];    # pool label
    my $server_name = $server;                        # pool label

    # TODO debug print
    # print "custom.pl DEBUG pre-graph\n\t$file\t$vm_name\t$server\t$server_name\n";

    if ( $file eq '' ) {
      $index++;
      next;    #some trash
    }

    if ( !-f $file ) {
      $index++;
      next;
    }

    # avoid old lpars which do not exist in the period
    my $rrd_upd_time = ( stat("$file") )[9];
    if ( $rrd_upd_time < $req_time ) {
      $index++;
      next;
    }

    $lpar = $server_name;

    my $lpar_proc = "$lpar $delimiter " . "$vm_name";    # for html legend
    $lpar_proc =~ s/%/%%/g;
    $lpar_proc =~ s/:/\\:/g;
    $lpar_proc =~ s/\&\&1/\//g;

    $lpar =~ s/\&\&1/\//g;
    for ( my $k = length($lpar); $k < 25; $k++ ) {
      $lpar .= " ";
    }
    $lpar .= "   ";
    $lpar .= $vm_name;
    $lpar =~ s/\&\&1/\//g;

    # to keep same count of characters
    $lpar =~ s/\\:/:/g;
    $lpar = sprintf( "%-25s", $lpar );
    $lpar =~ s/:/\\:/g;

    # TODO copied from VMware, could be simplified
    my $lpar_space_proc = $vm_name;
    my $lpar_space      = "$lpar $lpar_space_proc";
    for ( my $k = length($lpar_space); $k < 50; $k++ ) {
      $lpar_space .= " ";
    }

    $lpar_space_proc = "$lpar $delimiter " . "$lpar_space_proc";
    $lpar_space_proc =~ s/\:/\\:/g;

    if ( exists $uniq_files{"$file"} ) {    # check duplicities
      $index++;
      next;
    }
    $uniq_files{"$file"} = 1;
    $lparn .= " ";
    print FHL "$file\n";

    if ( ( length($lpar_v) + 1 ) == length($comm) && length($lparn) == length($comm) ) {
      copy_source_org( $webdir, $tmpdir, $basedir, $lim_org, $lim, $group );
      last;
    }
    if ( $type =~ "d" ) {
      RRDp::cmd qq(last "$file");
      my $last_tt = RRDp::read;
      chomp($$last_tt);
      $newest_file_timestamp = $$last_tt if $$last_tt > $newest_file_timestamp;
    }

    if ( $type_edt == 0 && $lparno == 4 ) {
      copy_source_org( $webdir, $tmpdir, $basedir, $lim_org, $lim, $group );
      last;
    }
    $lparno++;

    # Found out stored color index to keep same color for the volume across all graphs
    my $file_color = $file;
    $file_color =~ s/\.r..$//;
    $file_color =~ s/\\//g;
    $file_color =~ s/:/===========doublecoma=========/g;
    my $color_indx_found = -1;
    $color_indx = 0;

    foreach my $line_col (@color_save) {
      chomp($line_col);
      if ( $line_col eq '' || $line_col !~ m/ : / ) {
        next;
      }
      $color_indx++;
      ( my $color_indx_found_act, my $volume_name_save ) = split( / : /, $line_col );

      # do not use here $volume_name_save '' as this does not work when volume id is zero!
      if ( $volume_name_save =~ m/^$file_color$/ ) {
        $color_indx_found = $color_indx_found_act;
        $color_indx       = $color_indx_found;
        last;
      }
    }
    if ( $color_indx_found == -1 ) {
      $color_file_change = 1;
      $color_save[$color_indx] = $color_indx . " : " . $file_color;
    }
    while ( $color_indx > $color_max ) {
      $color_indx = $color_indx - $color_max;
    }

    # end color
    # note: replace colons in VM label
    my $vm_name_escaped = $vm_name;
    $vm_name_escaped =~ s/:/\\:/g;

    # create the graph command itself
    $color_indx = ++$color_indx % ( $color_max + 1 );
    my $itemcolor = $color[ $color_indx % ( $color_max + 1 ) ];
    my $itemlabel = "$vm_name_escaped";                           # $lpar_space_proc
    my $poollabel = "$server_name";
    my $graph_info;
    my $itemcolor2;
    if ( $item =~ m/data/ || $item =~ m/net/ ) {
      $color_indx = ++$color_indx % ( $color_max + 1 );
      $itemcolor2 = $color[ $color_indx % ( $color_max + 1 ) ];
    }
    if ( $item =~ m/^cpu-percent/ ) {
      $graph_info = ProxmoxGraph::graph_cpu_percent_aggr( 'vm', $file, $i, $itemcolor, $itemlabel, $poollabel, 'cluster', 'custom-proxmoxvm-cpu-percent' );
    }
    elsif ( $item =~ m/^cpu/ ) {
      $graph_info = ProxmoxGraph::graph_cpu_aggr( 'vm', $file, $i, $itemcolor, $itemlabel, $poollabel, 'cluster', 'custom-proxmoxvm-cpu' );
    }
    elsif ( $item =~ m/^memory-free/ ) {
      $graph_info = ProxmoxGraph::graph_memory_aggr( 'vm', $file, $i, $itemcolor, $itemlabel, $poollabel, 'cluster', 'free', 'custom-proxmoxvm-memory-free' );
    }
    elsif ( $item =~ m/^memory-used/ ) {
      $graph_info = ProxmoxGraph::graph_memory_aggr( 'vm', $file, $i, $itemcolor, $itemlabel, $poollabel, 'cluster', 'used', 'custom-proxmoxvm-memory-used' );
    }
    elsif ( $item =~ m/^data/ ) {
      $graph_info = ProxmoxGraph::graph_data_aggr( 'vm', $file, $i, $itemcolor, $itemcolor2, $itemlabel, $poollabel, 'cluster', 'custom-proxmoxvm-data' );
    }
    elsif ( $item =~ m/^net/ ) {
      $graph_info = ProxmoxGraph::graph_net_aggr( 'vm', $file, $i, $itemcolor, $itemcolor2, $itemlabel, $poollabel, 'cluster', 'custom-proxmoxvm-data' );
    }
    else {
      error("multiview_proxmoxvm unsupported item $item");
    }
    $cmd .= $graph_info->{cmd_def};
    $cmd .= $graph_info->{cmd_cdef};
    if ( $item =~ m/^(cpu|mem)/ ) {
      $cmdx .= $graph_info->{cmd_legend};
    }
    else {
      $cmdx  .= $graph_info->{cmd_legend_lower};
      $cmdx2 .= $graph_info->{cmd_legend_upper};
    }

    $i++;

    # done

    $index++;

    #    if ( ! get_lpar_num() && $index_l > 4 ) {
    #      last;
    #    }
  }
  $cmd .= $cmdx;
  $cmd .= $cmdx2;

  close(FHL);

  if ( $i == 0 ) {
    print "creating cgraph: " . scalar localtime() . " custom:$group $item $type: no any source found, skipping\n";

    # if there is not CMD file, create at least emty graph
    return 0 if -f $tmp_file;    # nothing has been found
  }
  if ( $newest_file_timestamp > 0 ) {
    my $l = localtime($newest_file_timestamp);

    # following must be for RRD 1.2+
    $l =~ s/:/\\:/g;
    $updated = " COMMENT:\\\"  Updated\\\: $l \\\"";
  }

  $cmd .= " $updated";
  $cmd .= " HRULE:0#000000";

  # $cmd .= " VRULE:0#000000";  --> it is causing sigsegv on linuxeS
  $cmd =~ s/\\"/"/g;

  open( FH, "> $tmp_file" ) || error( "Can't open $tmp_file : $!" . __FILE__ . ":" . __LINE__ ) && return 0;
  print FH "$cmd\n";
  close(FH);

  #
  # do not execute it here
  # execute it in the run time based on cmd stored in $tmp_file
  #

  # write colors into a file
  if ( $color_file_change == 1 ) {
    open( FHC, "> $file_color_save" ) || error( "file cannot be created :  $file_color_save " . __FILE__ . ":" . __LINE__ ) && return 0;
    foreach my $line_cs (@color_save) {
      chomp($line_cs);    # it must be there, somehow appear there \n ...
      if ( $line_cs eq '' ) {
        next;
      }
      if ( $line_cs =~ m/ : / ) {
        print FHC "$line_cs\n";
      }
    }
    close(FHC);
  }

  # colours

  return 1;
}

# FUSIONCOMPUTEVM
sub multiview_fusioncomputevm {
  my $group    = shift;
  my $name     = shift;
  my $type     = shift;
  my $type_sam = shift;
  my $act_time = shift;
  my $step_new = shift;
  my $text     = shift;
  my $xgrid    = shift;
  my $item     = shift;

  # $item toggles graph type (CPU, memory etc.), use CPU by default
  $item = 'cpu-percent' if !defined $item;

  my $req_time = 0;
  my $comm     = "COMM ";
  $color_indx = 0;    # clear color index
  my $list              = "$webdir/custom/$group/list.txt";
  my $lim               = ".li";
  my $updated           = "";
  my $color_file_change = 0;
  my $file_color_save   = "$basedir/tmp/custom-group-$group.col";
  my $lparno            = 0;

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
    $req_time  = $act_time - 31536000;
    $skip_time = $YEAR_REFRESH;
  }

  # modified filename for FUSIONCOMPUTEVM
  my $tmp_file = "$tmpdir/custom-group-fusioncomputevm-${item}-$group-$type.cmd";

  # do not update weekly/monthly/yearly command files each run
  if ( -f "$tmp_file" ) {
    my $tmp_time = ( stat("$tmp_file") )[9];
    if ( ( $act_time - $tmp_time ) < $skip_time ) {
      print "                        skipped this time : ( $act_time - $tmp_time ) < $skip_time \n";
      return 0;
    }
  }

  # open a file with stored colours
  my @color_save = "";
  if ( -f "$file_color_save" ) {
    open( FHC, "< $file_color_save" ) || error( "file cannot be opened : $file_color_save " . __FILE__ . ":" . __LINE__ ) && return 0;
    @color_save = <FHC>;
    close(FHC);
  }

  my $type_edt = 0;
  if ( -f $type_edt_filex ) {
    $type_edt = 1;
  }

  if ( $item eq 'cpu-percent' ) {
    open( FHL, "> $list" ) || error( "Can't open $list : $!" . __FILE__ . ":" . __LINE__ ) && return 0;
  }
  else {
    open( FHL, ">> $list" ) || error( "Can't open $list : $!" . __FILE__ . ":" . __LINE__ ) && return 0;
  }

  # header adjusted for FusionCompute
  my $header = "FusionCompute VM custom group $group";
  $header .= " : last $text";

  my $file    = "";
  my $i       = 0;
  my $lpar    = "";
  my $lparn   = "";
  my $cmd     = "";
  my $cmdx    = "";
  my $cmdx2   = "";
  my $cmd_xpo = "";    # unused here, unlike in multiview_vims (VMware)
  my $j       = 0;

  my $lim_org = $lim;
  $lim =~ s/\.//;
  $lim =~ s/i/l/;

  # get rrdtool params for FusionCompute metrics (based on $item)
  my $cmd_params;
  if ( $item =~ m/^cpu-percent$/ ) {
    $cmd_params = FusionComputeGraph::get_params_custom('CPU usage in [%]');
  }
  elsif ( $item =~ m/^cpu$/ ) {
    $cmd_params = FusionComputeGraph::get_params_custom('CPU usage in [cores]');
  }
  elsif ( $item =~ m/^mem-percent/ ) {
    $cmd_params = FusionComputeGraph::get_params_custom('Memory usage in [%]');
  }
  elsif ( $item =~ m/^mem-free/ || $item =~ m/^mem-used/ ) {
    $cmd_params = FusionComputeGraph::get_params_custom('Memory in [GB]');
  }
  elsif ( $item =~ m/^net$/ || $item =~ m/^data$/ ) {
    $cmd_params = FusionComputeGraph::get_params_custom('Read - MB/sec - Write');
  }
  elsif ( $item =~ m/^disk-ticks$/ ) {
    $cmd_params = FusionComputeGraph::get_params_custom('Read - ms - Write');
  }
  elsif ( $item =~ m/^disk-ios$/ ) {
    $cmd_params = FusionComputeGraph::get_params_custom('Read - IOPS - Write');
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
  $cmd .= " --step=$step_new";
  $cmd .= " --color=BACK#$pic_col";
  $cmd .= " --color=SHADEA#$pic_col";
  $cmd .= " --color=SHADEB#$pic_col";
  $cmd .= " --color=CANVAS#$pic_col";
  $cmd .= " --units-exponent=1.00";
  $cmd .= " --alt-y-grid";
  $cmd .= " --x-grid=$xgrid";
  $cmd .= $cmd_params;

  # legends adjusted for FusionCompute
  if ( $item =~ m/^cpu-percent$/ || $item =~ m/^mem-percent$/ ) {
    $cmd .= " COMMENT:\"[%]\"";
  }
  elsif ( $item =~ m/^cpu$/ ) {
    $cmd .= " COMMENT:\"[cores]\"";
  }
  elsif ( $item =~ m/^mem/ ) {
    $cmd .= " COMMENT:\"[GB]\\n\"";
  }
  elsif ( $item =~ m/^data$/ || $item =~ m/^net$/ ) {
    $cmd .= " COMMENT:\"[MB/s]\\n\"";
  }
  elsif ( $item =~ m/^ticks$/ ) {
    $cmd .= " COMMENT:\"[millisec]\\n\"";
  }
  elsif ( $item =~ m/^ios$/ ) {
    $cmd .= " COMMENT:\"[iops]\\n\"";
  }

  if ( $item =~ m/(data|net|ios|ticks)/ ) {
    $cmd .= " COMMENT:\"Cluster                  VM                                     Read      Avrg       Max    Write      Avrg      Max\\n\"";
  }
  else {
    $cmd .= " COMMENT:\"Cluster                  VM                                     Avrg     Max\\n\"";
  }

  my $index             = 0;
  my @lpars_graph_local = @lpars_graph;

  my %uniq_files;
  my $newest_file_timestamp = 0;

  foreach my $file_tmp (@lpars_graph_local) {

    # filename
    my $file = $file_tmp;    # must be here to allocate new space and do not make changes in @lpars_graph

    # load labels
    my $vm_name     = $lpars_graph_name[$index];      # VM label
    my $server      = $lpars_graph_server[$index];    # pool label
    my $server_name = $server;                        # pool label

    # TODO debug print
    # print "custom.pl DEBUG pre-graph\n\t$file\t$vm_name\t$server\t$server_name\n";

    if ( $file eq '' ) {
      $index++;
      next;    #some trash
    }

    if ( !-f $file ) {
      $index++;
      next;
    }

    # avoid old lpars which do not exist in the period
    my $rrd_upd_time = ( stat("$file") )[9];
    if ( $rrd_upd_time < $req_time ) {
      $index++;
      next;
    }

    $lpar = $server_name;

    my $lpar_proc = "$lpar $delimiter " . "$vm_name";    # for html legend
    $lpar_proc =~ s/%/%%/g;
    $lpar_proc =~ s/:/\\:/g;
    $lpar_proc =~ s/\&\&1/\//g;

    $lpar =~ s/\&\&1/\//g;
    for ( my $k = length($lpar); $k < 25; $k++ ) {
      $lpar .= " ";
    }
    $lpar .= "   ";
    $lpar .= $vm_name;
    $lpar =~ s/\&\&1/\//g;

    # to keep same count of characters
    $lpar =~ s/\\:/:/g;
    $lpar = sprintf( "%-25s", $lpar );
    $lpar =~ s/:/\\:/g;

    # TODO copied from VMware, could be simplified
    my $lpar_space_proc = $vm_name;
    my $lpar_space      = "$lpar $lpar_space_proc";
    for ( my $k = length($lpar_space); $k < 50; $k++ ) {
      $lpar_space .= " ";
    }

    $lpar_space_proc = "$lpar $delimiter " . "$lpar_space_proc";
    $lpar_space_proc =~ s/\:/\\:/g;

    if ( exists $uniq_files{"$file"} ) {    # check duplicities
      $index++;
      next;
    }
    $uniq_files{"$file"} = 1;
    $lparn .= " ";
    print FHL "$file\n";

    if ( ( length($lpar_v) + 1 ) == length($comm) && length($lparn) == length($comm) ) {
      copy_source_org( $webdir, $tmpdir, $basedir, $lim_org, $lim, $group );
      last;
    }
    if ( $type =~ "d" ) {
      RRDp::cmd qq(last "$file");
      my $last_tt = RRDp::read;
      chomp($$last_tt);
      $newest_file_timestamp = $$last_tt if $$last_tt > $newest_file_timestamp;
    }

    if ( $type_edt == 0 && $lparno == 4 ) {
      copy_source_org( $webdir, $tmpdir, $basedir, $lim_org, $lim, $group );
      last;
    }
    $lparno++;

    # Found out stored color index to keep same color for the volume across all graphs
    my $file_color = $file;
    $file_color =~ s/\.r..$//;
    $file_color =~ s/\\//g;
    $file_color =~ s/:/===========doublecoma=========/g;
    my $color_indx_found = -1;
    $color_indx = 0;

    foreach my $line_col (@color_save) {
      chomp($line_col);
      if ( $line_col eq '' || $line_col !~ m/ : / ) {
        next;
      }
      $color_indx++;
      ( my $color_indx_found_act, my $volume_name_save ) = split( / : /, $line_col );

      # do not use here $volume_name_save '' as this does not work when volume id is zero!
      if ( $volume_name_save =~ m/^$file_color$/ ) {
        $color_indx_found = $color_indx_found_act;
        $color_indx       = $color_indx_found;
        last;
      }
    }
    if ( $color_indx_found == -1 ) {
      $color_file_change = 1;
      $color_save[$color_indx] = $color_indx . " : " . $file_color;
    }
    while ( $color_indx > $color_max ) {
      $color_indx = $color_indx - $color_max;
    }

    # end color
    # note: replace colons in VM label
    my $vm_name_escaped = $vm_name;
    $vm_name_escaped =~ s/:/\\:/g;

    # create the graph command itself
    $color_indx = ++$color_indx % ( $color_max + 1 );
    my $itemcolor = $color[ $color_indx % ( $color_max + 1 ) ];
    my $itemlabel = "$vm_name_escaped";                           # $lpar_space_proc
    my $poollabel = "$server_name";
    my $graph_info;
    my $itemcolor2;

    if ( $item =~ m/data/ || $item =~ m/net/ || $item =~ m/disk-ios/ || $item =~ m/disk-ticks/ ) {
      $color_indx = ++$color_indx % ( $color_max + 1 );
      $itemcolor2 = $color[ $color_indx % ( $color_max + 1 ) ];
    }

    if ( $item =~ m/^cpu-percent/ ) {
      $graph_info = FusionComputeGraph::graph_percent_aggr( 'vm', $file, $i, $itemcolor, $itemlabel, $poollabel, 'cluster', 'cpu_usage', 'custom-fusioncomputevm-cpu-percent' );
    }
    elsif ( $item =~ m/^cpu/ ) {
      $graph_info = FusionComputeGraph::graph_cpu_aggr( 'vm', $file, $i, $itemcolor, $itemlabel, $poollabel, 'cluster', 'custom-fusioncomputevm-cpu' );
    }
    elsif ( $item =~ m/^mem-percent/ ) {
      $graph_info = FusionComputeGraph::graph_percent_aggr( 'vm', $file, $i, $itemcolor, $itemlabel, $poollabel, 'cluster', 'mem_usage', 'custom-fusioncomputevm-mem-percent' );
    }
    elsif ( $item =~ m/^mem-free/ ) {
      $graph_info = FusionComputeGraph::graph_memory_aggr( 'vm', $file, $i, $itemcolor, $itemlabel, $poollabel, 'cluster', 'free', 'custom-fusioncomputevm-mem-free' );
    }
    elsif ( $item =~ m/^mem-used/ ) {
      $graph_info = FusionComputeGraph::graph_memory_aggr( 'vm', $file, $i, $itemcolor, $itemlabel, $poollabel, 'cluster', 'used', 'custom-fusioncomputevm-mem-used' );
    }
    elsif ( $item =~ m/^data/ ) {
      $graph_info = FusionComputeGraph::graph_read_write_aggr( 'vm', $file, $i, $itemcolor, $itemcolor2, $itemlabel, $poollabel, 'cluster', 'data', 'custom-fusioncomputevm-data' );
    }
    elsif ( $item =~ m/^net/ ) {
      $graph_info = FusionComputeGraph::graph_read_write_aggr( 'vm', $file, $i, $itemcolor, $itemcolor2, $itemlabel, $poollabel, 'cluster', 'net', 'custom-fusioncomputevm-data' );
    }
    elsif ( $item =~ m/^disk-ios/ ) {
      $graph_info = FusionComputeGraph::graph_iops_aggr( 'vm', $file, $i, $itemcolor, $itemcolor2, $itemlabel, $poollabel, 'cluster', 'disk_ios', 'custom-fusioncomputevm-disk-ios' );
    }
    elsif ( $item =~ m/^disk-ticks/ ) {
      $graph_info = FusionComputeGraph::graph_latency_aggr( 'vm', $file, $i, $itemcolor, $itemcolor2, $itemlabel, $poollabel, 'cluster', 'disk_ticks', 'custom-fusioncomputevm-disk-ticks' );
    }
    else {
      error("multiview_fusioncomputevm unsupported item $item");
    }
    $cmd .= $graph_info->{cmd_def};
    $cmd .= $graph_info->{cmd_cdef};
    if ( $item =~ m/^(cpu|mem)/ ) {
      $cmdx .= $graph_info->{cmd_legend};
    }
    else {
      $cmdx  .= $graph_info->{cmd_legend_lower};
      $cmdx2 .= $graph_info->{cmd_legend_upper};
    }

    $i++;

    # done

    $index++;

    #    if ( ! get_lpar_num() && $index_l > 4 ) {
    #      last;
    #    }
  }
  $cmd .= $cmdx;
  $cmd .= $cmdx2;

  close(FHL);

  if ( $i == 0 ) {
    print "creating cgraph: " . scalar localtime() . " custom:$group $item $type: no any source found, skipping\n";

    # if there is not CMD file, create at least emty graph
    return 0 if -f $tmp_file;    # nothing has been found
  }
  if ( $newest_file_timestamp > 0 ) {
    my $l = localtime($newest_file_timestamp);

    # following must be for RRD 1.2+
    $l =~ s/:/\\:/g;
    $updated = " COMMENT:\\\"  Updated\\\: $l \\\"";
  }

  $cmd .= " $updated";
  $cmd .= " HRULE:0#000000";

  # $cmd .= " VRULE:0#000000";  --> it is causing sigsegv on linuxeS
  $cmd =~ s/\\"/"/g;

  open( FH, "> $tmp_file" ) || error( "Can't open $tmp_file : $!" . __FILE__ . ":" . __LINE__ ) && return 0;
  print FH "$cmd\n";
  close(FH);

  #
  # do not execute it here
  # execute it in the run time based on cmd stored in $tmp_file
  #

  # write colors into a file
  if ( $color_file_change == 1 ) {
    open( FHC, "> $file_color_save" ) || error( "file cannot be created :  $file_color_save " . __FILE__ . ":" . __LINE__ ) && return 0;
    foreach my $line_cs (@color_save) {
      chomp($line_cs);    # it must be there, somehow appear there \n ...
      if ( $line_cs eq '' ) {
        next;
      }
      if ( $line_cs =~ m/ : / ) {
        print FHC "$line_cs\n";
      }
    }
    close(FHC);
  }

  # colours

  return 1;
}

# OPENSHIFTNODE
sub multiview_openshiftnode {
  my $group    = shift;
  my $name     = shift;
  my $type     = shift;
  my $type_sam = shift;
  my $act_time = shift;
  my $step_new = shift;
  my $text     = shift;
  my $xgrid    = shift;
  my $item     = shift;

  # $item toggles graph type (CPU, memory etc.), use CPU by default
  $item = 'cpu-percent' if !defined $item;

  my $req_time = 0;
  my $comm     = "COMM ";
  $color_indx = 0;    # clear color index
  my $list              = "$webdir/custom/$group/list.txt";
  my $lim               = ".li";
  my $updated           = "";
  my $color_file_change = 0;
  my $file_color_save   = "$basedir/tmp/custom-group-$group.col";
  my $lparno            = 0;

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
    $req_time  = $act_time - 31536000;
    $skip_time = $YEAR_REFRESH;
  }

  # modified filename for OPENSHIFTNODE
  my $tmp_file = "$tmpdir/custom-group-openshiftnode-${item}-$group-$type.cmd";

  # do not update weekly/monthly/yearly command files each run
  if ( -f "$tmp_file" ) {
    my $tmp_time = ( stat("$tmp_file") )[9];
    if ( ( $act_time - $tmp_time ) < $skip_time ) {
      print "                        skipped this time : ( $act_time - $tmp_time ) < $skip_time \n";
      return 0;
    }
  }

  # open a file with stored colours
  my @color_save = "";
  if ( -f "$file_color_save" ) {
    open( FHC, "< $file_color_save" ) || error( "file cannot be opened : $file_color_save " . __FILE__ . ":" . __LINE__ ) && return 0;
    @color_save = <FHC>;
    close(FHC);
  }

  my $type_edt = 0;
  if ( -f $type_edt_filex ) {
    $type_edt = 1;
  }

  if ( $item eq 'cpu-percent' ) {
    open( FHL, "> $list" ) || error( "Can't open $list : $!" . __FILE__ . ":" . __LINE__ ) && return 0;
  }
  else {
    open( FHL, ">> $list" ) || error( "Can't open $list : $!" . __FILE__ . ":" . __LINE__ ) && return 0;
  }

  # header adjusted for Openshift
  my $header = "Openshift node custom group $group";
  $header .= " : last $text";

  my $file    = "";
  my $i       = 0;
  my $lpar    = "";
  my $lparn   = "";
  my $cmd     = "";
  my $cmdx    = "";
  my $cmdx2   = "";
  my $cmd_xpo = "";    # unused here, unlike in multiview_vims (VMware)
  my $j       = 0;

  my $lim_org = $lim;
  $lim =~ s/\.//;
  $lim =~ s/i/l/;

  # get rrdtool params for Openshift metrics (based on $item)
  my $cmd_params;
  if ( $item =~ m/^cpu-percent$/ ) {
    $cmd_params = OpenshiftGraph::get_params_custom('CPU usage in [%]');
    $cmd_params .= " --units-exponent=1.00";
  }
  elsif ( $item =~ m/^cpu$/ ) {
    $cmd_params = OpenshiftGraph::get_params_custom('CPU usage in [cores]');
    $cmd_params .= " --units-exponent=1.00";
  }
  elsif ( $item =~ m/^memory/ ) {
    $cmd_params = OpenshiftGraph::get_params_custom('Memory used in [GB]');
    $cmd_params .= " --units-exponent=1.00";
  }
  elsif ( $item =~ m/^data$/ ) {
    $cmd_params = KubernetesGraph::get_params_custom('Read - Data - Write');
  }
  elsif ( $item =~ m/^net$/ ) {
    $cmd_params = KubernetesGraph::get_params_custom('Read - Net - Write');
  }
  elsif ( $item =~ m/^iops$/ ) {
    $cmd_params = OpenshiftGraph::get_params_custom('Read - IOPS - Write');
    $cmd_params .= " --units-exponent=1.00";
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
  $cmd .= " --step=$step_new";
  $cmd .= " --color=BACK#$pic_col";
  $cmd .= " --color=SHADEA#$pic_col";
  $cmd .= " --color=SHADEB#$pic_col";
  $cmd .= " --color=CANVAS#$pic_col";

  #$cmd .= " --units-exponent=1.00";
  $cmd .= " --alt-y-grid";
  $cmd .= " --x-grid=$xgrid";
  $cmd .= $cmd_params;

  # legends adjusted for Openshift
  if ( $item =~ m/^cpu-percent$/ || $item =~ m/^mem-percent$/ ) {
    $cmd .= " COMMENT:\"[%]\"";
  }
  elsif ( $item =~ m/^cpu$/ ) {
    $cmd .= " COMMENT:\"[cores]\"";
  }
  elsif ( $item =~ m/^mem/ ) {
    $cmd .= " COMMENT:\"[GB]\\n\"";
  }
  elsif ( $item =~ m/^data$/ || $item =~ m/^net$/ ) {
    $cmd .= " COMMENT:\"[MB/s]\\n\"";
  }
  elsif ( $item =~ m/^ticks$/ ) {
    $cmd .= " COMMENT:\"[millisec]\\n\"";
  }
  elsif ( $item =~ m/^ios$/ ) {
    $cmd .= " COMMENT:\"[iops]\\n\"";
  }

  if ( $item =~ m/(data|net|ios|ticks)/ ) {
    $cmd .= " COMMENT:\"Cluster                  VM                                     Read      Avrg       Max    Write      Avrg      Max\\n\"";
  }
  else {
    $cmd .= " COMMENT:\"Cluster                  VM                                     Avrg     Max\\n\"";
  }

  my $index             = 0;
  my @lpars_graph_local = @lpars_graph;

  my %uniq_files;
  my $newest_file_timestamp = 0;

  foreach my $file_tmp (@lpars_graph_local) {

    # filename
    my $file = $file_tmp;    # must be here to allocate new space and do not make changes in @lpars_graph

    # load labels
    my $vm_name     = $lpars_graph_name[$index];      # VM label
    my $server      = $lpars_graph_server[$index];    # pool label
    my $server_name = $server;                        # pool label

    # TODO debug print
    # print "custom.pl DEBUG pre-graph\n\t$file\t$vm_name\t$server\t$server_name\n";

    if ( $file eq '' ) {
      $index++;
      next;    #some trash
    }

    if ( !-f $file ) {
      $index++;
      next;
    }

    # avoid old lpars which do not exist in the period
    my $rrd_upd_time = ( stat("$file") )[9];
    if ( $rrd_upd_time < $req_time ) {
      $index++;
      next;
    }

    $lpar = $server_name;

    my $lpar_proc = "$lpar $delimiter " . "$vm_name";    # for html legend
    $lpar_proc =~ s/%/%%/g;
    $lpar_proc =~ s/:/\\:/g;
    $lpar_proc =~ s/\&\&1/\//g;

    $lpar =~ s/\&\&1/\//g;
    for ( my $k = length($lpar); $k < 25; $k++ ) {
      $lpar .= " ";
    }
    $lpar .= "   ";
    $lpar .= $vm_name;
    $lpar =~ s/\&\&1/\//g;

    # to keep same count of characters
    $lpar =~ s/\\:/:/g;
    $lpar = sprintf( "%-25s", $lpar );
    $lpar =~ s/:/\\:/g;

    # TODO copied from VMware, could be simplified
    my $lpar_space_proc = $vm_name;
    my $lpar_space      = "$lpar $lpar_space_proc";
    for ( my $k = length($lpar_space); $k < 50; $k++ ) {
      $lpar_space .= " ";
    }

    $lpar_space_proc = "$lpar $delimiter " . "$lpar_space_proc";
    $lpar_space_proc =~ s/\:/\\:/g;

    if ( exists $uniq_files{"$file"} ) {    # check duplicities
      $index++;
      next;
    }
    $uniq_files{"$file"} = 1;
    $lparn .= " ";
    print FHL "$file\n";

    if ( ( length($lpar_v) + 1 ) == length($comm) && length($lparn) == length($comm) ) {
      copy_source_org( $webdir, $tmpdir, $basedir, $lim_org, $lim, $group );
      last;
    }
    if ( $type =~ "d" ) {
      RRDp::cmd qq(last "$file");
      my $last_tt = RRDp::read;
      chomp($$last_tt);
      $newest_file_timestamp = $$last_tt if $$last_tt > $newest_file_timestamp;
    }

    if ( $type_edt == 0 && $lparno == 4 ) {
      copy_source_org( $webdir, $tmpdir, $basedir, $lim_org, $lim, $group );
      last;
    }
    $lparno++;

    # Found out stored color index to keep same color for the volume across all graphs
    my $file_color = $file;
    $file_color =~ s/\.r..$//;
    $file_color =~ s/\\//g;
    $file_color =~ s/:/===========doublecoma=========/g;
    my $color_indx_found = -1;
    $color_indx = 0;

    foreach my $line_col (@color_save) {
      chomp($line_col);
      if ( $line_col eq '' || $line_col !~ m/ : / ) {
        next;
      }
      $color_indx++;
      ( my $color_indx_found_act, my $volume_name_save ) = split( / : /, $line_col );

      # do not use here $volume_name_save '' as this does not work when volume id is zero!
      if ( $volume_name_save =~ m/^$file_color$/ ) {
        $color_indx_found = $color_indx_found_act;
        $color_indx       = $color_indx_found;
        last;
      }
    }
    if ( $color_indx_found == -1 ) {
      $color_file_change = 1;
      $color_save[$color_indx] = $color_indx . " : " . $file_color;
    }
    while ( $color_indx > $color_max ) {
      $color_indx = $color_indx - $color_max;
    }

    # end color
    # note: replace colons in VM label
    my $vm_name_escaped = $vm_name;
    $vm_name_escaped =~ s/:/\\:/g;

    # create the graph command itself
    $color_indx = ++$color_indx % ( $color_max + 1 );
    my $itemcolor = $color[ $color_indx % ( $color_max + 1 ) ];
    my $itemlabel = "$vm_name_escaped";                           # $lpar_space_proc
    my $poollabel = "$server_name";
    my $graph_info;
    my $itemcolor2;
    if ( $item =~ m/data/ || $item =~ m/net/ || $item =~ m/iops/ ) {
      $color_indx = ++$color_indx % ( $color_max + 1 );
      $itemcolor2 = $color[ $color_indx % ( $color_max + 1 ) ];
    }
    if ( $item =~ m/^cpu-percent/ ) {
      $graph_info = OpenshiftGraph::graph_cpu_percent_aggr( 'node', $file, $i, $itemcolor, $itemlabel, $poollabel, 'cluster', 'custom-openshiftnode-cpu-percent' );
    }
    elsif ( $item =~ m/^cpu/ ) {
      $graph_info = OpenshiftGraph::graph_cpu_aggr( 'node', 'cpu', $file, $i, $itemcolor, $itemlabel, $poollabel, 'cluster', 'custom-openshiftnode-cpu' );
    }
    elsif ( $item =~ m/^memory/ ) {
      $graph_info = OpenshiftGraph::graph_memory_aggr( 'node', 'memory', $file, $i, $itemcolor, $itemlabel, $poollabel, 'cluster', 'free', 'custom-openshiftnode-memory-free' );
    }
    elsif ( $item =~ m/^data/ ) {
      $graph_info = OpenshiftGraph::graph_cadvisor_aggr( 'node', 'data', $file, $i, $itemcolor, $itemcolor2, $itemlabel, $poollabel, 'cluster', 'custom-openshiftnode-data' );
    }
    elsif ( $item =~ m/^net/ ) {
      $graph_info = OpenshiftGraph::graph_cadvisor_aggr( 'node', 'net', $file, $i, $itemcolor, $itemcolor2, $itemlabel, $poollabel, 'cluster', 'custom-openshiftnode-data' );
    }
    elsif ( $item =~ m/^iops/ ) {
      $graph_info = OpenshiftGraph::graph_cadvisor_aggr( 'node', 'iops', $file, $i, $itemcolor, $itemcolor2, $itemlabel, $poollabel, 'cluster', 'custom-openshiftnode-data' );
    }
    else {
      error("multiview_openshiftnode unsupported item $item");
    }
    $cmd .= $graph_info->{cmd_def};
    $cmd .= $graph_info->{cmd_cdef};
    if ( $item =~ m/^(cpu|mem)/ ) {
      $cmdx .= $graph_info->{cmd_legend};
    }
    else {
      $cmdx  .= $graph_info->{cmd_legend_lower};
      $cmdx2 .= $graph_info->{cmd_legend_upper};
    }

    $i++;

    # done

    $index++;

    #    if ( ! get_lpar_num() && $index_l > 4 ) {
    #      last;
    #    }
  }
  $cmd .= $cmdx;
  $cmd .= $cmdx2;

  close(FHL);

  if ( $i == 0 ) {
    print "creating cgraph: " . scalar localtime() . " custom:$group $item $type: no any source found, skipping\n";

    # if there is not CMD file, create at least emty graph
    return 0 if -f $tmp_file;    # nothing has been found
  }
  if ( $newest_file_timestamp > 0 ) {
    my $l = localtime($newest_file_timestamp);

    # following must be for RRD 1.2+
    $l =~ s/:/\\:/g;
    $updated = " COMMENT:\\\"  Updated\\\: $l \\\"";
  }

  $cmd .= " $updated";
  $cmd .= " HRULE:0#000000";

  # $cmd .= " VRULE:0#000000";  --> it is causing sigsegv on linuxeS
  $cmd =~ s/\\"/"/g;

  open( FH, "> $tmp_file" ) || error( "Can't open $tmp_file : $!" . __FILE__ . ":" . __LINE__ ) && return 0;
  print FH "$cmd\n";
  close(FH);

  #
  # do not execute it here
  # execute it in the run time based on cmd stored in $tmp_file
  #

  # write colors into a file
  if ( $color_file_change == 1 ) {
    open( FHC, "> $file_color_save" ) || error( "file cannot be created :  $file_color_save " . __FILE__ . ":" . __LINE__ ) && return 0;
    foreach my $line_cs (@color_save) {
      chomp($line_cs);    # it must be there, somehow appear there \n ...
      if ( $line_cs eq '' ) {
        next;
      }
      if ( $line_cs =~ m/ : / ) {
        print FHC "$line_cs\n";
      }
    }
    close(FHC);
  }

  # colours

  return 1;
}

# KUBERNETESNODE
sub multiview_kubernetesnode {
  my $group    = shift;
  my $name     = shift;
  my $type     = shift;
  my $type_sam = shift;
  my $act_time = shift;
  my $step_new = shift;
  my $text     = shift;
  my $xgrid    = shift;
  my $item     = shift;

  # $item toggles graph type (CPU, memory etc.), use CPU by default
  $item = 'cpu-percent' if !defined $item;

  my $req_time = 0;
  my $comm     = "COMM ";
  $color_indx = 0;    # clear color index
  my $list              = "$webdir/custom/$group/list.txt";
  my $lim               = ".li";
  my $updated           = "";
  my $color_file_change = 0;
  my $file_color_save   = "$basedir/tmp/custom-group-$group.col";
  my $lparno            = 0;

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
    $req_time  = $act_time - 31536000;
    $skip_time = $YEAR_REFRESH;
  }

  # modified filename for KUBERNETESNODE
  my $tmp_file = "$tmpdir/custom-group-kubernetesnode-${item}-$group-$type.cmd";

  # do not update weekly/monthly/yearly command files each run
  if ( -f "$tmp_file" ) {
    my $tmp_time = ( stat("$tmp_file") )[9];
    if ( ( $act_time - $tmp_time ) < $skip_time ) {
      print "                        skipped this time : ( $act_time - $tmp_time ) < $skip_time \n";
      return 0;
    }
  }

  # open a file with stored colours
  my @color_save = "";
  if ( -f "$file_color_save" ) {
    open( FHC, "< $file_color_save" ) || error( "file cannot be opened : $file_color_save " . __FILE__ . ":" . __LINE__ ) && return 0;
    @color_save = <FHC>;
    close(FHC);
  }

  my $type_edt = 0;
  if ( -f $type_edt_filex ) {
    $type_edt = 1;
  }

  if ( $item eq 'cpu-percent' ) {
    open( FHL, "> $list" ) || error( "Can't open $list : $!" . __FILE__ . ":" . __LINE__ ) && return 0;
  }
  else {
    open( FHL, ">> $list" ) || error( "Can't open $list : $!" . __FILE__ . ":" . __LINE__ ) && return 0;
  }

  # header adjusted for Kubernetes
  my $header = "Kubernetes node custom group $group";
  $header .= " : last $text";

  my $file    = "";
  my $i       = 0;
  my $lpar    = "";
  my $lparn   = "";
  my $cmd     = "";
  my $cmdx    = "";
  my $cmdx2   = "";
  my $cmd_xpo = "";    # unused here, unlike in multiview_vims (VMware)
  my $j       = 0;

  my $lim_org = $lim;
  $lim =~ s/\.//;
  $lim =~ s/i/l/;

  # get rrdtool params for Kubernetes metrics (based on $item)
  my $cmd_params;
  if ( $item =~ m/^cpu-percent$/ ) {
    $cmd_params = KubernetesGraph::get_params_custom('CPU usage in [%]');
    $cmd_params .= " --units-exponent=1.00";
  }
  elsif ( $item =~ m/^cpu$/ ) {
    $cmd_params = KubernetesGraph::get_params_custom('CPU usage in [cores]');
    $cmd_params .= " --units-exponent=1.00";
  }
  elsif ( $item =~ m/^memory/ ) {
    $cmd_params = KubernetesGraph::get_params_custom('Memory used in [GB]');
    $cmd_params .= " --units-exponent=1.00";
  }
  elsif ( $item =~ m/^data$/ ) {
    $cmd_params = KubernetesGraph::get_params_custom('Read - Data - Write');
  }
  elsif ( $item =~ m/^net$/ ) {
    $cmd_params = KubernetesGraph::get_params_custom('Read - Net - Write');
  }
  elsif ( $item =~ m/^iops$/ ) {
    $cmd_params = KubernetesGraph::get_params_custom('Read - IOPS - Write');
    $cmd_params .= " --units-exponent=1.00";
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
  $cmd .= " --step=$step_new";
  $cmd .= " --color=BACK#$pic_col";
  $cmd .= " --color=SHADEA#$pic_col";
  $cmd .= " --color=SHADEB#$pic_col";
  $cmd .= " --color=CANVAS#$pic_col";

  #$cmd .= " --units-exponent=1.00";
  $cmd .= " --alt-y-grid";
  $cmd .= " --x-grid=$xgrid";
  $cmd .= $cmd_params;

  # legends adjusted for Kubernetes
  if ( $item =~ m/^cpu-percent$/ || $item =~ m/^mem-percent$/ ) {
    $cmd .= " COMMENT:\"[%]\"";
  }
  elsif ( $item =~ m/^cpu$/ ) {
    $cmd .= " COMMENT:\"[cores]\"";
  }
  elsif ( $item =~ m/^mem/ ) {
    $cmd .= " COMMENT:\"[GB]\\n\"";
  }
  elsif ( $item =~ m/^data$/ || $item =~ m/^net$/ ) {
    $cmd .= " COMMENT:\"[MB/s]\\n\"";
  }
  elsif ( $item =~ m/^ticks$/ ) {
    $cmd .= " COMMENT:\"[millisec]\\n\"";
  }
  elsif ( $item =~ m/^ios$/ ) {
    $cmd .= " COMMENT:\"[iops]\\n\"";
  }

  if ( $item =~ m/(data|net|ios|ticks)/ ) {
    $cmd .= " COMMENT:\"Cluster                  VM                                     Read      Avrg       Max    Write      Avrg      Max\\n\"";
  }
  else {
    $cmd .= " COMMENT:\"Cluster                  VM                                     Avrg     Max\\n\"";
  }

  my $index             = 0;
  my @lpars_graph_local = @lpars_graph;

  my %uniq_files;
  my $newest_file_timestamp = 0;

  foreach my $file_tmp (@lpars_graph_local) {

    # filename
    my $file = $file_tmp;    # must be here to allocate new space and do not make changes in @lpars_graph

    # load labels
    my $vm_name     = $lpars_graph_name[$index];      # VM label
    my $server      = $lpars_graph_server[$index];    # pool label
    my $server_name = $server;                        # pool label

    # TODO debug print
    # print "custom.pl DEBUG pre-graph\n\t$file\t$vm_name\t$server\t$server_name\n";

    if ( $file eq '' ) {
      $index++;
      next;    #some trash
    }

    if ( !-f $file ) {
      $index++;
      next;
    }

    # avoid old lpars which do not exist in the period
    my $rrd_upd_time = ( stat("$file") )[9];
    if ( $rrd_upd_time < $req_time ) {
      $index++;
      next;
    }

    $lpar = $server_name;

    my $lpar_proc = "$lpar $delimiter " . "$vm_name";    # for html legend
    $lpar_proc =~ s/%/%%/g;
    $lpar_proc =~ s/:/\\:/g;
    $lpar_proc =~ s/\&\&1/\//g;

    $lpar =~ s/\&\&1/\//g;
    for ( my $k = length($lpar); $k < 25; $k++ ) {
      $lpar .= " ";
    }
    $lpar .= "   ";
    $lpar .= $vm_name;
    $lpar =~ s/\&\&1/\//g;

    # to keep same count of characters
    $lpar =~ s/\\:/:/g;
    $lpar = sprintf( "%-25s", $lpar );
    $lpar =~ s/:/\\:/g;

    # TODO copied from VMware, could be simplified
    my $lpar_space_proc = $vm_name;
    my $lpar_space      = "$lpar $lpar_space_proc";
    for ( my $k = length($lpar_space); $k < 50; $k++ ) {
      $lpar_space .= " ";
    }

    $lpar_space_proc = "$lpar $delimiter " . "$lpar_space_proc";
    $lpar_space_proc =~ s/\:/\\:/g;

    if ( exists $uniq_files{"$file"} ) {    # check duplicities
      $index++;
      next;
    }
    $uniq_files{"$file"} = 1;
    $lparn .= " ";
    print FHL "$file\n";

    if ( ( length($lpar_v) + 1 ) == length($comm) && length($lparn) == length($comm) ) {
      copy_source_org( $webdir, $tmpdir, $basedir, $lim_org, $lim, $group );
      last;
    }
    if ( $type =~ "d" ) {
      RRDp::cmd qq(last "$file");
      my $last_tt = RRDp::read;
      chomp($$last_tt);
      $newest_file_timestamp = $$last_tt if $$last_tt > $newest_file_timestamp;
    }

    if ( $type_edt == 0 && $lparno == 4 ) {
      copy_source_org( $webdir, $tmpdir, $basedir, $lim_org, $lim, $group );
      last;
    }
    $lparno++;

    # Found out stored color index to keep same color for the volume across all graphs
    my $file_color = $file;
    $file_color =~ s/\.r..$//;
    $file_color =~ s/\\//g;
    $file_color =~ s/:/===========doublecoma=========/g;
    my $color_indx_found = -1;
    $color_indx = 0;

    foreach my $line_col (@color_save) {
      chomp($line_col);
      if ( $line_col eq '' || $line_col !~ m/ : / ) {
        next;
      }
      $color_indx++;
      ( my $color_indx_found_act, my $volume_name_save ) = split( / : /, $line_col );

      # do not use here $volume_name_save '' as this does not work when volume id is zero!
      if ( $volume_name_save =~ m/^$file_color$/ ) {
        $color_indx_found = $color_indx_found_act;
        $color_indx       = $color_indx_found;
        last;
      }
    }
    if ( $color_indx_found == -1 ) {
      $color_file_change = 1;
      $color_save[$color_indx] = $color_indx . " : " . $file_color;
    }
    while ( $color_indx > $color_max ) {
      $color_indx = $color_indx - $color_max;
    }

    # end color
    # note: replace colons in VM label
    my $vm_name_escaped = $vm_name;
    $vm_name_escaped =~ s/:/\\:/g;

    # create the graph command itself
    $color_indx = ++$color_indx % ( $color_max + 1 );
    my $itemcolor = $color[ $color_indx % ( $color_max + 1 ) ];
    my $itemlabel = "$vm_name_escaped";                           # $lpar_space_proc
    my $poollabel = "$server_name";
    my $graph_info;
    my $itemcolor2;
    if ( $item =~ m/data/ || $item =~ m/net/ || $item =~ m/iops/ ) {
      $color_indx = ++$color_indx % ( $color_max + 1 );
      $itemcolor2 = $color[ $color_indx % ( $color_max + 1 ) ];
    }
    if ( $item =~ m/^cpu-percent/ ) {
      $graph_info = KubernetesGraph::graph_cpu_percent_aggr( 'node', $file, $i, $itemcolor, $itemlabel, $poollabel, 'cluster', 'custom-kubernetesnode-cpu-percent' );
    }
    elsif ( $item =~ m/^cpu/ ) {
      $graph_info = KubernetesGraph::graph_cpu_aggr( 'node', 'cpu', $file, $i, $itemcolor, $itemlabel, $poollabel, 'cluster', 'custom-okubernetesnode-cpu' );
    }
    elsif ( $item =~ m/^memory/ ) {
      $graph_info = KubernetesGraph::graph_memory_aggr( 'node', 'memory', $file, $i, $itemcolor, $itemlabel, $poollabel, 'cluster', 'free', 'custom-kubernetesnode-memory-free' );
    }
    elsif ( $item =~ m/^data/ ) {
      $graph_info = KubernetesGraph::graph_cadvisor_aggr( 'node', 'data', $file, $i, $itemcolor, $itemcolor2, $itemlabel, $poollabel, 'cluster', 'custom-kubernetesnode-data' );
    }
    elsif ( $item =~ m/^net/ ) {
      $graph_info = KubernetesGraph::graph_cadvisor_aggr( 'node', 'net', $file, $i, $itemcolor, $itemcolor2, $itemlabel, $poollabel, 'cluster', 'custom-kubernetesnode-data' );
    }
    elsif ( $item =~ m/^iops/ ) {
      $graph_info = KubernetesGraph::graph_cadvisor_aggr( 'node', 'iops', $file, $i, $itemcolor, $itemcolor2, $itemlabel, $poollabel, 'cluster', 'custom-kubernetesnode-data' );
    }
    else {
      error("multiview_kubernetesnode unsupported item $item");
    }
    $cmd .= $graph_info->{cmd_def};
    $cmd .= $graph_info->{cmd_cdef};
    if ( $item =~ m/^(cpu|mem)/ ) {
      $cmdx .= $graph_info->{cmd_legend};
    }
    else {
      $cmdx  .= $graph_info->{cmd_legend_lower};
      $cmdx2 .= $graph_info->{cmd_legend_upper};
    }

    $i++;

    # done

    $index++;

    #    if ( ! get_lpar_num() && $index_l > 4 ) {
    #      last;
    #    }
  }
  $cmd .= $cmdx;
  $cmd .= $cmdx2;

  close(FHL);

  if ( $i == 0 ) {
    print "creating cgraph: " . scalar localtime() . " custom:$group $item $type: no any source found, skipping\n";

    # if there is not CMD file, create at least emty graph
    return 0 if -f $tmp_file;    # nothing has been found
  }
  if ( $newest_file_timestamp > 0 ) {
    my $l = localtime($newest_file_timestamp);

    # following must be for RRD 1.2+
    $l =~ s/:/\\:/g;
    $updated = " COMMENT:\\\"  Updated\\\: $l \\\"";
  }

  $cmd .= " $updated";
  $cmd .= " HRULE:0#000000";

  # $cmd .= " VRULE:0#000000";  --> it is causing sigsegv on linuxeS
  $cmd =~ s/\\"/"/g;

  open( FH, "> $tmp_file" ) || error( "Can't open $tmp_file : $!" . __FILE__ . ":" . __LINE__ ) && return 0;
  print FH "$cmd\n";
  close(FH);

  #
  # do not execute it here
  # execute it in the run time based on cmd stored in $tmp_file
  #

  # write colors into a file
  if ( $color_file_change == 1 ) {
    open( FHC, "> $file_color_save" ) || error( "file cannot be created :  $file_color_save " . __FILE__ . ":" . __LINE__ ) && return 0;
    foreach my $line_cs (@color_save) {
      chomp($line_cs);    # it must be there, somehow appear there \n ...
      if ( $line_cs eq '' ) {
        next;
      }
      if ( $line_cs =~ m/ : / ) {
        print FHC "$line_cs\n";
      }
    }
    close(FHC);
  }

  # colours

  return 1;
}

# KUBERNETESNAMESPACE
sub multiview_kubernetesnamespace {
  my $group    = shift;
  my $name     = shift;
  my $type     = shift;
  my $type_sam = shift;
  my $act_time = shift;
  my $step_new = shift;
  my $text     = shift;
  my $xgrid    = shift;
  my $item     = shift;

  # $item toggles graph type (CPU, memory etc.), use CPU by default
  $item = 'cpu-percent' if !defined $item;

  my $req_time = 0;
  my $comm     = "COMM ";
  $color_indx = 0;    # clear color index
  my $list              = "$webdir/custom/$group/list.txt";
  my $lim               = ".li";
  my $updated           = "";
  my $color_file_change = 0;
  my $file_color_save   = "$basedir/tmp/custom-group-$group.col";
  my $lparno            = 0;

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
    $req_time  = $act_time - 31536000;
    $skip_time = $YEAR_REFRESH;
  }

  # modified filename for KUBERNETESNAMESPACE
  my $tmp_file = "$tmpdir/custom-group-kubernetesnamespace-${item}-$group-$type.cmd";

  # do not update weekly/monthly/yearly command files each run
  if ( -f "$tmp_file" ) {
    my $tmp_time = ( stat("$tmp_file") )[9];
    if ( ( $act_time - $tmp_time ) < $skip_time ) {
      print "                        skipped this time : ( $act_time - $tmp_time ) < $skip_time \n";
      return 0;
    }
  }

  # open a file with stored colours
  my @color_save = "";
  if ( -f "$file_color_save" ) {
    open( FHC, "< $file_color_save" ) || error( "file cannot be opened : $file_color_save " . __FILE__ . ":" . __LINE__ ) && return 0;
    @color_save = <FHC>;
    close(FHC);
  }

  my $type_edt = 0;
  if ( -f $type_edt_filex ) {
    $type_edt = 1;
  }

  if ( $item eq 'cpu-percent' ) {
    open( FHL, "> $list" ) || error( "Can't open $list : $!" . __FILE__ . ":" . __LINE__ ) && return 0;
  }
  else {
    open( FHL, ">> $list" ) || error( "Can't open $list : $!" . __FILE__ . ":" . __LINE__ ) && return 0;
  }

  # header adjusted for Kubernetes
  my $header = "Kubernetes namespace custom group $group";
  $header .= " : last $text";

  my $file    = "";
  my $i       = 0;
  my $lpar    = "";
  my $lparn   = "";
  my $cmd     = "";
  my $cmdx    = "";
  my $cmdx2   = "";
  my $cmd_xpo = "";    # unused here, unlike in multiview_vims (VMware)
  my $j       = 0;

  my $lim_org = $lim;
  $lim =~ s/\.//;
  $lim =~ s/i/l/;

  # get rrdtool params for Kubernetes metrics (based on $item)
  my $cmd_params;
  if ( $item =~ m/^cpu$/ ) {
    $cmd_params = KubernetesGraph::get_params_custom('CPU usage in [cores]');
    $cmd_params .= " --units-exponent=1.00";
  }
  elsif ( $item =~ m/^memory/ ) {
    $cmd_params = KubernetesGraph::get_params_custom('Memory used in [GB]');
    $cmd_params .= " --units-exponent=1.00";
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
  $cmd .= " --step=$step_new";
  $cmd .= " --color=BACK#$pic_col";
  $cmd .= " --color=SHADEA#$pic_col";
  $cmd .= " --color=SHADEB#$pic_col";
  $cmd .= " --color=CANVAS#$pic_col";

  #$cmd .= " --units-exponent=1.00";
  $cmd .= " --alt-y-grid";
  $cmd .= " --x-grid=$xgrid";
  $cmd .= $cmd_params;

  # legends adjusted for Kubernetes
  if ( $item =~ m/^cpu$/ ) {
    $cmd .= " COMMENT:\"[cores]\"";
  }
  elsif ( $item =~ m/^mem/ ) {
    $cmd .= " COMMENT:\"[GB]\\n\"";
  }

  $cmd .= " COMMENT:\"Cluster                  Namespace                            Avrg     Max\\n\"";

  my $index             = 0;
  my @lpars_graph_local = @lpars_graph;

  my %uniq_files;
  my $newest_file_timestamp = 0;

  foreach my $file_tmp (@lpars_graph_local) {

    # filename
    my $file = $file_tmp;    # must be here to allocate new space and do not make changes in @lpars_graph

    # load labels
    my $vm_name     = $lpars_graph_name[$index];      # VM label
    my $server      = $lpars_graph_server[$index];    # pool label
    my $server_name = $server;                        # pool label

    # TODO debug print
    # print "custom.pl DEBUG pre-graph\n\t$file\t$vm_name\t$server\t$server_name\n";

    if ( $file eq '' ) {
      $index++;
      next;    #some trash
    }

    if ( !-f $file ) {
      $index++;
      next;
    }

    # avoid old lpars which do not exist in the period
    my $rrd_upd_time = ( stat("$file") )[9];
    if ( $rrd_upd_time < $req_time ) {
      $index++;
      next;
    }

    $lpar = $server_name;

    my $lpar_proc = "$lpar $delimiter " . "$vm_name";    # for html legend
    $lpar_proc =~ s/%/%%/g;
    $lpar_proc =~ s/:/\\:/g;
    $lpar_proc =~ s/\&\&1/\//g;

    $lpar =~ s/\&\&1/\//g;
    for ( my $k = length($lpar); $k < 25; $k++ ) {
      $lpar .= " ";
    }
    $lpar .= "   ";
    $lpar .= $vm_name;
    $lpar =~ s/\&\&1/\//g;

    # to keep same count of characters
    $lpar =~ s/\\:/:/g;
    $lpar = sprintf( "%-25s", $lpar );
    $lpar =~ s/:/\\:/g;

    # TODO copied from VMware, could be simplified
    my $lpar_space_proc = $vm_name;
    my $lpar_space      = "$lpar $lpar_space_proc";
    for ( my $k = length($lpar_space); $k < 50; $k++ ) {
      $lpar_space .= " ";
    }

    $lpar_space_proc = "$lpar $delimiter " . "$lpar_space_proc";
    $lpar_space_proc =~ s/\:/\\:/g;

    if ( exists $uniq_files{"$file"} ) {    # check duplicities
      $index++;
      next;
    }
    $uniq_files{"$file"} = 1;
    $lparn .= " ";
    print FHL "$file\n";

    if ( ( length($lpar_v) + 1 ) == length($comm) && length($lparn) == length($comm) ) {
      copy_source_org( $webdir, $tmpdir, $basedir, $lim_org, $lim, $group );
      last;
    }
    if ( $type =~ "d" ) {
      RRDp::cmd qq(last "$file");
      my $last_tt = RRDp::read;
      chomp($$last_tt);
      $newest_file_timestamp = $$last_tt if $$last_tt > $newest_file_timestamp;
    }

    if ( $type_edt == 0 && $lparno == 4 ) {
      copy_source_org( $webdir, $tmpdir, $basedir, $lim_org, $lim, $group );
      last;
    }
    $lparno++;

    # Found out stored color index to keep same color for the volume across all graphs
    my $file_color = $file;
    $file_color =~ s/\.r..$//;
    $file_color =~ s/\\//g;
    $file_color =~ s/:/===========doublecoma=========/g;
    my $color_indx_found = -1;
    $color_indx = 0;

    foreach my $line_col (@color_save) {
      chomp($line_col);
      if ( $line_col eq '' || $line_col !~ m/ : / ) {
        next;
      }
      $color_indx++;
      ( my $color_indx_found_act, my $volume_name_save ) = split( / : /, $line_col );

      # do not use here $volume_name_save '' as this does not work when volume id is zero!
      if ( $volume_name_save =~ m/^$file_color$/ ) {
        $color_indx_found = $color_indx_found_act;
        $color_indx       = $color_indx_found;
        last;
      }
    }
    if ( $color_indx_found == -1 ) {
      $color_file_change = 1;
      $color_save[$color_indx] = $color_indx . " : " . $file_color;
    }

    while ( $color_indx > $color_max ) {
      $color_indx = $color_indx - $color_max;
    }

    # end color
    # note: replace colons in VM label
    my $vm_name_escaped = $vm_name;
    $vm_name_escaped =~ s/:/\\:/g;

    # create the graph command itself
    $color_indx = ++$color_indx % ( $color_max + 1 );
    my $itemcolor = $color[ $color_indx % ( $color_max + 1 ) ];
    my $itemlabel = "$vm_name_escaped";                           # $lpar_space_proc
    my $poollabel = "$server_name";
    my $graph_info;
    my $itemcolor2;
    if ( $item =~ m/data/ || $item =~ m/net/ || $item =~ m/iops/ ) {
      $color_indx = ++$color_indx % ( $color_max + 1 );
      $itemcolor2 = $color[ $color_indx % ( $color_max + 1 ) ];
    }
    if ( $item =~ m/^cpu/ ) {
      $graph_info = KubernetesGraph::graph_cpu_aggr( 'namespace', 'cpu', $file, $i, $itemcolor, $itemlabel, $poollabel, 'cluster', 'custom-kubernetesnamespace-cpu' );
    }
    elsif ( $item =~ m/^memory/ ) {
      $graph_info = KubernetesGraph::graph_memory_aggr( 'namespace', 'memory', $file, $i, $itemcolor, $itemlabel, $poollabel, 'cluster', 'custom-kubernetesnamespace-memory' );
    }
    else {
      error("multiview_kubernetesnamespace unsupported item $item");
    }
    $cmd .= $graph_info->{cmd_def};
    $cmd .= $graph_info->{cmd_cdef};
    if ( $item =~ m/^(cpu|mem)/ ) {
      $cmdx .= $graph_info->{cmd_legend};
    }
    else {
      $cmdx  .= $graph_info->{cmd_legend_lower};
      $cmdx2 .= $graph_info->{cmd_legend_upper};
    }

    $i++;

    # done

    $index++;

    #    if ( ! get_lpar_num() && $index_l > 4 ) {
    #      last;
    #    }
  }
  $cmd .= $cmdx;
  $cmd .= $cmdx2;

  close(FHL);

  if ( $i == 0 ) {
    print "creating cgraph: " . scalar localtime() . " custom:$group $item $type: no any source found, skipping\n";

    # if there is not CMD file, create at least emty graph
    return 0 if -f $tmp_file;    # nothing has been found
  }
  if ( $newest_file_timestamp > 0 ) {
    my $l = localtime($newest_file_timestamp);

    # following must be for RRD 1.2+
    $l =~ s/:/\\:/g;
    $updated = " COMMENT:\\\"  Updated\\\: $l \\\"";
  }

  $cmd .= " $updated";
  $cmd .= " HRULE:0#000000";

  # $cmd .= " VRULE:0#000000";  --> it is causing sigsegv on linuxeS
  $cmd =~ s/\\"/"/g;

  open( FH, "> $tmp_file" ) || error( "Can't open $tmp_file : $!" . __FILE__ . ":" . __LINE__ ) && return 0;
  print FH "$cmd\n";
  close(FH);

  #
  # do not execute it here
  # execute it in the run time based on cmd stored in $tmp_file
  #

  # write colors into a file
  if ( $color_file_change == 1 ) {
    open( FHC, "> $file_color_save" ) || error( "file cannot be created :  $file_color_save " . __FILE__ . ":" . __LINE__ ) && return 0;
    foreach my $line_cs (@color_save) {
      chomp($line_cs);    # it must be there, somehow appear there \n ...
      if ( $line_cs eq '' ) {
        next;
      }
      if ( $line_cs =~ m/ : / ) {
        print FHC "$line_cs\n";
      }
    }
    close(FHC);
  }

  # colours

  return 1;
}

# OPENSHIFTNAMESPACE
sub multiview_openshiftnamespace {
  my $group    = shift;
  my $name     = shift;
  my $type     = shift;
  my $type_sam = shift;
  my $act_time = shift;
  my $step_new = shift;
  my $text     = shift;
  my $xgrid    = shift;
  my $item     = shift;

  # $item toggles graph type (CPU, memory etc.), use CPU by default
  $item = 'cpu-percent' if !defined $item;

  my $req_time = 0;
  my $comm     = "COMM ";
  $color_indx = 0;    # clear color index
  my $list              = "$webdir/custom/$group/list.txt";
  my $lim               = ".li";
  my $updated           = "";
  my $color_file_change = 0;
  my $file_color_save   = "$basedir/tmp/custom-group-$group.col";
  my $lparno            = 0;

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
    $req_time  = $act_time - 31536000;
    $skip_time = $YEAR_REFRESH;
  }

  # modified filename for OPENSHIFTNAMESPACE
  my $tmp_file = "$tmpdir/custom-group-openshiftnamespace-${item}-$group-$type.cmd";

  # do not update weekly/monthly/yearly command files each run
  if ( -f "$tmp_file" ) {
    my $tmp_time = ( stat("$tmp_file") )[9];
    if ( ( $act_time - $tmp_time ) < $skip_time ) {
      print "                        skipped this time : ( $act_time - $tmp_time ) < $skip_time \n";
      return 0;
    }
  }

  # open a file with stored colours
  my @color_save = "";
  if ( -f "$file_color_save" ) {
    open( FHC, "< $file_color_save" ) || error( "file cannot be opened : $file_color_save " . __FILE__ . ":" . __LINE__ ) && return 0;
    @color_save = <FHC>;
    close(FHC);
  }

  my $type_edt = 0;
  if ( -f $type_edt_filex ) {
    $type_edt = 1;
  }

  if ( $item eq 'cpu-percent' ) {
    open( FHL, "> $list" ) || error( "Can't open $list : $!" . __FILE__ . ":" . __LINE__ ) && return 0;
  }
  else {
    open( FHL, ">> $list" ) || error( "Can't open $list : $!" . __FILE__ . ":" . __LINE__ ) && return 0;
  }

  # header adjusted for Openshift
  my $header = "Openshift namespace custom group $group";
  $header .= " : last $text";

  my $file    = "";
  my $i       = 0;
  my $lpar    = "";
  my $lparn   = "";
  my $cmd     = "";
  my $cmdx    = "";
  my $cmdx2   = "";
  my $cmd_xpo = "";    # unused here, unlike in multiview_vims (VMware)
  my $j       = 0;

  my $lim_org = $lim;
  $lim =~ s/\.//;
  $lim =~ s/i/l/;

  # get rrdtool params for Openshift metrics (based on $item)
  my $cmd_params;
  if ( $item =~ m/^cpu$/ ) {
    $cmd_params = OpenshiftGraph::get_params_custom('CPU usage in [cores]');
    $cmd_params .= " --units-exponent=1.00";
  }
  elsif ( $item =~ m/^memory/ ) {
    $cmd_params = OpenshiftGraph::get_params_custom('Memory used in [GB]');
    $cmd_params .= " --units-exponent=1.00";
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
  $cmd .= " --step=$step_new";
  $cmd .= " --color=BACK#$pic_col";
  $cmd .= " --color=SHADEA#$pic_col";
  $cmd .= " --color=SHADEB#$pic_col";
  $cmd .= " --color=CANVAS#$pic_col";

  #$cmd .= " --units-exponent=1.00";
  $cmd .= " --alt-y-grid";
  $cmd .= " --x-grid=$xgrid";
  $cmd .= $cmd_params;

  # legends adjusted for Openshift
  if ( $item =~ m/^cpu$/ ) {
    $cmd .= " COMMENT:\"[cores]\"";
  }
  elsif ( $item =~ m/^mem/ ) {
    $cmd .= " COMMENT:\"[GB]\\n\"";
  }

  $cmd .= " COMMENT:\"Cluster                  Namespace                            Avrg     Max\\n\"";

  my $index             = 0;
  my @lpars_graph_local = @lpars_graph;

  my %uniq_files;
  my $newest_file_timestamp = 0;

  foreach my $file_tmp (@lpars_graph_local) {

    # filename
    my $file = $file_tmp;    # must be here to allocate new space and do not make changes in @lpars_graph

    # load labels
    my $vm_name     = $lpars_graph_name[$index];      # VM label
    my $server      = $lpars_graph_server[$index];    # pool label
    my $server_name = $server;                        # pool label

    # TODO debug print
    # print "custom.pl DEBUG pre-graph\n\t$file\t$vm_name\t$server\t$server_name\n";

    if ( $file eq '' ) {
      $index++;
      next;    #some trash
    }

    if ( !-f $file ) {
      $index++;
      next;
    }

    # avoid old lpars which do not exist in the period
    my $rrd_upd_time = ( stat("$file") )[9];
    if ( $rrd_upd_time < $req_time ) {
      $index++;
      next;
    }

    $lpar = $server_name;

    my $lpar_proc = "$lpar $delimiter " . "$vm_name";    # for html legend
    $lpar_proc =~ s/%/%%/g;
    $lpar_proc =~ s/:/\\:/g;
    $lpar_proc =~ s/\&\&1/\//g;

    $lpar =~ s/\&\&1/\//g;
    for ( my $k = length($lpar); $k < 25; $k++ ) {
      $lpar .= " ";
    }
    $lpar .= "   ";
    $lpar .= $vm_name;
    $lpar =~ s/\&\&1/\//g;

    # to keep same count of characters
    $lpar =~ s/\\:/:/g;
    $lpar = sprintf( "%-25s", $lpar );
    $lpar =~ s/:/\\:/g;

    # TODO copied from VMware, could be simplified
    my $lpar_space_proc = $vm_name;
    my $lpar_space      = "$lpar $lpar_space_proc";
    for ( my $k = length($lpar_space); $k < 50; $k++ ) {
      $lpar_space .= " ";
    }

    $lpar_space_proc = "$lpar $delimiter " . "$lpar_space_proc";
    $lpar_space_proc =~ s/\:/\\:/g;

    if ( exists $uniq_files{"$file"} ) {    # check duplicities
      $index++;
      next;
    }
    $uniq_files{"$file"} = 1;
    $lparn .= " ";
    print FHL "$file\n";

    if ( ( length($lpar_v) + 1 ) == length($comm) && length($lparn) == length($comm) ) {
      copy_source_org( $webdir, $tmpdir, $basedir, $lim_org, $lim, $group );
      last;
    }
    if ( $type =~ "d" ) {
      RRDp::cmd qq(last "$file");
      my $last_tt = RRDp::read;
      chomp($$last_tt);
      $newest_file_timestamp = $$last_tt if $$last_tt > $newest_file_timestamp;
    }

    if ( $type_edt == 0 && $lparno == 4 ) {
      copy_source_org( $webdir, $tmpdir, $basedir, $lim_org, $lim, $group );
      last;
    }
    $lparno++;

    # Found out stored color index to keep same color for the volume across all graphs
    my $file_color = $file;
    $file_color =~ s/\.r..$//;
    $file_color =~ s/\\//g;
    $file_color =~ s/:/===========doublecoma=========/g;
    my $color_indx_found = -1;
    $color_indx = 0;

    foreach my $line_col (@color_save) {
      chomp($line_col);
      if ( $line_col eq '' || $line_col !~ m/ : / ) {
        next;
      }
      $color_indx++;
      ( my $color_indx_found_act, my $volume_name_save ) = split( / : /, $line_col );

      # do not use here $volume_name_save '' as this does not work when volume id is zero!
      if ( $volume_name_save =~ m/^$file_color$/ ) {
        $color_indx_found = $color_indx_found_act;
        $color_indx       = $color_indx_found;
        last;
      }
    }
    if ( $color_indx_found == -1 ) {
      $color_file_change = 1;
      $color_save[$color_indx] = $color_indx . " : " . $file_color;
    }

    while ( $color_indx > $color_max ) {
      $color_indx = $color_indx - $color_max;
    }

    # end color
    # note: replace colons in VM label
    my $vm_name_escaped = $vm_name;
    $vm_name_escaped =~ s/:/\\:/g;

    # create the graph command itself
    $color_indx = ++$color_indx % ( $color_max + 1 );
    my $itemcolor = $color[ $color_indx % ( $color_max + 1 ) ];
    my $itemlabel = "$vm_name_escaped";                           # $lpar_space_proc
    my $poollabel = "$server_name";
    my $graph_info;
    my $itemcolor2;
    if ( $item =~ m/data/ || $item =~ m/net/ || $item =~ m/iops/ ) {
      $color_indx = ++$color_indx % ( $color_max + 1 );
      $itemcolor2 = $color[ $color_indx % ( $color_max + 1 ) ];
    }
    if ( $item =~ m/^cpu/ ) {
      $graph_info = OpenshiftGraph::graph_cpu_aggr( 'namespace', 'cpu', $file, $i, $itemcolor, $itemlabel, $poollabel, 'cluster', 'custom-openshiftnamespace-cpu' );
    }
    elsif ( $item =~ m/^memory/ ) {
      $graph_info = OpenshiftGraph::graph_memory_aggr( 'namespace', 'memory', $file, $i, $itemcolor, $itemlabel, $poollabel, 'cluster', 'custom-openshiftnamespace-memory' );
    }
    else {
      error("multiview_openshiftnamespace unsupported item $item");
    }
    $cmd .= $graph_info->{cmd_def};
    $cmd .= $graph_info->{cmd_cdef};
    if ( $item =~ m/^(cpu|mem)/ ) {
      $cmdx .= $graph_info->{cmd_legend};
    }
    else {
      $cmdx  .= $graph_info->{cmd_legend_lower};
      $cmdx2 .= $graph_info->{cmd_legend_upper};
    }

    $i++;

    # done

    $index++;

    #    if ( ! get_lpar_num() && $index_l > 4 ) {
    #      last;
    #    }
  }
  $cmd .= $cmdx;
  $cmd .= $cmdx2;

  close(FHL);

  if ( $i == 0 ) {
    print "creating cgraph: " . scalar localtime() . " custom:$group $item $type: no any source found, skipping\n";

    # if there is not CMD file, create at least emty graph
    return 0 if -f $tmp_file;    # nothing has been found
  }
  if ( $newest_file_timestamp > 0 ) {
    my $l = localtime($newest_file_timestamp);

    # following must be for RRD 1.2+
    $l =~ s/:/\\:/g;
    $updated = " COMMENT:\\\"  Updated\\\: $l \\\"";
  }

  $cmd .= " $updated";
  $cmd .= " HRULE:0#000000";

  # $cmd .= " VRULE:0#000000";  --> it is causing sigsegv on linuxeS
  $cmd =~ s/\\"/"/g;

  open( FH, "> $tmp_file" ) || error( "Can't open $tmp_file : $!" . __FILE__ . ":" . __LINE__ ) && return 0;
  print FH "$cmd\n";
  close(FH);

  #
  # do not execute it here
  # execute it in the run time based on cmd stored in $tmp_file
  #

  # write colors into a file
  if ( $color_file_change == 1 ) {
    open( FHC, "> $file_color_save" ) || error( "file cannot be created :  $file_color_save " . __FILE__ . ":" . __LINE__ ) && return 0;
    foreach my $line_cs (@color_save) {
      chomp($line_cs);    # it must be there, somehow appear there \n ...
      if ( $line_cs eq '' ) {
        next;
      }
      if ( $line_cs =~ m/ : / ) {
        print FHC "$line_cs\n";
      }
    }
    close(FHC);
  }

  # colours

  return 1;
}

sub multiview_ovirt {
  my $group    = shift;
  my $name     = shift;
  my $type     = shift;
  my $type_sam = shift;
  my $act_time = shift;
  my $step_new = shift;
  my $text     = shift;
  my $xgrid    = shift;
  my $item     = shift;

  # $item toggles graph type (CPU, memory etc.), use CPU by default
  $item = 'cpu-percent' if !defined $item;

  my $req_time = 0;
  my $comm     = "COMM ";
  $color_indx = 0;    # clear color index
  my $list              = "$webdir/custom/$group/list.txt";
  my $lim               = ".li";
  my $updated           = "";
  my $color_file_change = 0;
  my $file_color_save   = "$basedir/tmp/custom-group-$group.col";
  my $lparno            = 0;

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
    $req_time  = $act_time - 31536000;
    $skip_time = $YEAR_REFRESH;
  }

  # modified filename for OVIRTVM
  my $tmp_file = "$tmpdir/custom-group-ovirtvm-${item}-$group-$type.cmd";

  # do not update weekly/monthly/yearly command files each run
  if ( -f "$tmp_file" ) {
    my $tmp_time = ( stat("$tmp_file") )[9];
    if ( ( $act_time - $tmp_time ) < $skip_time ) {
      print "                        skipped this time : ( $act_time - $tmp_time ) < $skip_time \n";
      return 0;
    }
  }

  # open a file with stored colours
  my @color_save = "";
  if ( -f "$file_color_save" ) {
    open( FHC, "< $file_color_save" ) || error( "file cannot be opened : $file_color_save " . __FILE__ . ":" . __LINE__ ) && return 0;
    @color_save = <FHC>;
    close(FHC);
  }

  my $type_edt = 0;
  if ( -f $type_edt_fileo ) {
    $type_edt = 1;
  }

  if ( $item eq 'cpu-percent' ) {
    open( FHL, "> $list" ) || error( "Can't open $list : $!" . __FILE__ . ":" . __LINE__ ) && return 0;
  }
  else {
    open( FHL, ">> $list" ) || error( "Can't open $list : $!" . __FILE__ . ":" . __LINE__ ) && return 0;
  }

  # header adjusted for oVirt
  my $header = "oVirt VM custom group $group";
  $header .= " : last $text";

  my $file    = "";
  my $i       = 0;
  my $lpar    = "";
  my $lparn   = "";
  my $cmd     = "";
  my $cmdx    = "";
  my $cmdx2   = "";
  my $cmd_xpo = "";    # unused here, unlike in multiview_vims (VMware)
  my $j       = 0;

  my $lim_org = $lim;
  $lim =~ s/\.//;
  $lim =~ s/i/l/;

  # get rrdtool params for oVirt metrics (based on $item)
  my $itemcount      = 0;
  my $cmd_params     = '';
  my $vertical_label = '';
  my $cmd_def        = '';
  my $cmd_cdef       = '';
  my $cmd_legend     = '';

  if ( $item =~ /cpu-core/ ) {
    $cmd_params     = " --lower-limit=0.00";
    $vertical_label = " --vertical-label=\"CPU in cores\"";
    $cmd_legend     = " COMMENT:\"[cores]\\n\"";
  }
  elsif ( $item =~ /cpu-percent/ ) {
    $cmd_params = " --upper-limit=100.0";
    $cmd_params .= " --lower-limit=0.00";
    $vertical_label = " --vertical-label=\"CPU load in [%]\"";
    $cmd_legend     = " COMMENT:\"[%]\\n\"";
  }
  elsif ( $item =~ /memory-free|memory-used/ ) {
    $cmd_params = " --lower-limit=0.00";
    $cmd_params .= " --base=1024";
    $vertical_label = " --vertical-label=\"Memory in GBytes\"";
    $cmd_legend     = " COMMENT:\"[GB]\\n\"";
  }

  $cmd_legend .= " COMMENT:\"     Cluster               VM                         Avrg     Max\\n\"";

  $cmd .= "graph \\\"$name.png\\\"";
  $cmd .= " --title \\\"$header\\\"";
  $cmd .= " --start now-1$type";
  $cmd .= " --end now-1$type+1$type";
  $cmd .= " --imgformat PNG";
  $cmd .= " $disable_rrdtool_tag_agg";
  $cmd .= " --slope-mode";
  $cmd .= " --width=400";
  $cmd .= " --height=150";
  $cmd .= " --step=$step_new";
  $cmd .= " --color=BACK#$pic_col";
  $cmd .= " --color=SHADEA#$pic_col";
  $cmd .= " --color=SHADEB#$pic_col";
  $cmd .= " --color=CANVAS#$pic_col";
  $cmd .= " --units-exponent=1.00";
  $cmd .= " --alt-y-grid";
  $cmd .= " --x-grid=$xgrid";
  $cmd .= " $vertical_label";
  $cmd .= $cmd_params;
  $cmd .= $cmd_legend;

  my $index             = 0;
  my @lpars_graph_local = @lpars_graph;

  my %uniq_files;
  my $newest_file_timestamp = 0;

  # do not sort it HERE!! there is several arrays, sorting lpars_graph is not enough!!! --PH
  foreach my $file_tmp (@lpars_graph_local) {

    # filename
    my $file = $file_tmp;    # must be here to allocate new space and do not make changes in @lpars_graph

    # load labels
    my $vm_name     = $lpars_graph_name[$index];      # VM label
    my $server      = $lpars_graph_server[$index];    # cluster label
    my $server_name = $server;                        # cluster label

    # TODO debug print
    #    print "## custom.pl DEBUG pre-graph\n\t$file\t$vm_name\t$server\t$server_name\n";

    if ( $file eq '' ) {
      $index++;
      next;    #some trash
    }
    if ( !-f $file ) {
      $index++;
      next;
    }

    # avoid old lpars which do not exist in the period
    my $rrd_upd_time = ( stat("$file") )[9];
    if ( $rrd_upd_time < $req_time ) {
      $index++;
      next;
    }

    $lpar = $server_name;

    my $lpar_proc = "$lpar $delimiter " . "$vm_name";    # for html legend
    $lpar_proc =~ s/%/%%/g;
    $lpar_proc =~ s/:/\\:/g;
    $lpar_proc =~ s/\&\&1/\//g;

    $lpar =~ s/\&\&1/\//g;
    for ( my $k = length($lpar); $k < 25; $k++ ) {
      $lpar .= " ";
    }
    $lpar .= "   ";
    $lpar .= $vm_name;
    $lpar =~ s/\&\&1/\//g;

    # to keep same count of characters
    $lpar =~ s/\\:/:/g;
    $lpar = sprintf( "%-25s", $lpar );
    $lpar =~ s/:/\\:/g;

    # TODO copied from VMware, could be simplified
    my $lpar_space_proc = $vm_name;
    my $lpar_space      = "$lpar $lpar_space_proc";
    for ( my $k = length($lpar_space); $k < 50; $k++ ) {
      $lpar_space .= " ";
    }

    $lpar_space_proc = "$lpar $delimiter " . "$lpar_space_proc";
    $lpar_space_proc =~ s/\:/\\:/g;

    if ( exists $uniq_files{"$file"} ) {    # check duplicities
      $index++;
      next;
    }
    $uniq_files{"$file"} = 1;
    $lparn .= " ";
    print FHL "$file\n";

    if ( ( length($lpar_v) + 1 ) == length($comm) && length($lparn) == length($comm) ) {
      copy_source_org( $webdir, $tmpdir, $basedir, $lim_org, $lim, $group );
      last;
    }

    if ( $type =~ "d" ) {
      RRDp::cmd qq(last "$file");
      my $last_tt = RRDp::read;
      chomp($$last_tt);
      $newest_file_timestamp = $$last_tt if $$last_tt > $newest_file_timestamp;
    }

    if ( $type_edt == 0 && $lparno == 4 ) {
      copy_source_org( $webdir, $tmpdir, $basedir, $lim_org, $lim, $group );
      last;
    }
    $lparno++;

    # Found out stored color index to keep same color for the volume across all graphs
    my $file_color = $file;
    $file_color =~ s/\.r..$//;
    $file_color =~ s/\\//g;
    $file_color =~ s/:/===========doublecoma=========/g;
    my $color_indx_found = -1;
    $color_indx = 0;

    foreach my $line_col (@color_save) {
      chomp($line_col);
      if ( $line_col eq '' || $line_col !~ m/ : / ) {
        next;
      }
      $color_indx++;
      ( my $color_indx_found_act, my $volume_name_save ) = split( / : /, $line_col );

      # do not use here $volume_name_save '' as this does not work when volume id is zero!
      if ( $volume_name_save =~ m/^$file_color$/ ) {
        $color_indx_found = $color_indx_found_act;
        $color_indx       = $color_indx_found;
        last;
      }
    }
    if ( $color_indx_found == -1 ) {
      $color_file_change = 1;
      $color_save[$color_indx] = $color_indx . " : " . $file_color;
    }
    while ( $color_indx > $color_max ) {
      $color_indx = $color_indx - $color_max;
    }

    # end color

    # note: replace colons in VM label
    my $vm_name_escaped = $vm_name;
    $vm_name_escaped =~ s/:/\\:/g;

    # create the graph command itself
    $color_indx = ++$color_indx % ( $color_max + 1 );
    my $itemcolor = $color[ $color_indx % ( $color_max + 1 ) ];
    my $itemlabel = "$vm_name_escaped";                           # $lpar_space_proc
    my $graph_info;

    if ( $item =~ m/^cpu-percent/ ) {
      $graph_info = OVirtGraph::graph_custom_cpu( 'percent', $file, $i, $itemcolor, $itemlabel, $server );
    }
    elsif ( $item =~ m/^cpu-core/ ) {
      $graph_info = OVirtGraph::graph_custom_cpu( 'core', $file, $i, $itemcolor, $itemlabel, $server );
    }
    elsif ( $item =~ m/^memory-used/ ) {
      $graph_info = OVirtGraph::graph_custom_memory( 'mem_used', $file, $i, $itemcolor, $itemlabel, $server );
    }
    elsif ( $item =~ m/^memory-free/ ) {
      $graph_info = OVirtGraph::graph_custom_memory( 'mem_free', $file, $i, $itemcolor, $itemlabel, $server );
    }

    # elsif ( $item =~ m/^lan$/ ) {
    #   # need second color
    #   $color_indx = ++$color_indx % ( $color_max + 1 );
    #   my $itemcolor2 = $color[$color_indx % ($color_max +1)];
    #   $graph_info = XenServerGraph::graph_lan_aggr( 'vm', $file, $i, $itemcolor, $itemcolor2, $itemlabel );
    # } else {
    #   error("multiview_xenvm unsupported item $item");
    # }

    $cmd .= $graph_info->{cmd_def};
    $cmd .= $graph_info->{cmd_cdef};

    if ( $item =~ m/^(cpu|memory)/ ) {
      $cmdx .= $graph_info->{cmd_legend};
    }

    # else {
    #   $cmdx  .= $graph_info->{cmd_legend_lower};
    #   $cmdx2 .= $graph_info->{cmd_legend_upper};
    # }

    $i++;

    # done

    $index++;

    # if ( ! get_lpar_num() && $index_l > 4 ) {
    #   last;
    # }
  }
  $cmd .= $cmdx;
  $cmd .= $cmdx2;

  close(FHL);

  if ( $i == 0 ) {
    print "creating cgraph: " . scalar localtime() . " custom:$group $item $type: no any source found, skipping\n";

    # if there is not CMD file, create at least emty graph
    return 0 if -f $tmp_file;    # nothing has been found
  }
  if ( $newest_file_timestamp > 0 ) {
    my $l = localtime($newest_file_timestamp);

    # following must be for RRD 1.2+
    $l =~ s/:/\\:/g;
    $updated = " COMMENT:\\\"  Updated\\\: $l \\\"";
  }

  $cmd .= " $updated";
  $cmd .= " HRULE:0#000000";

  # $cmd .= " VRULE:0#000000";  --> it is causing sigsegv on linuxeS
  $cmd =~ s/\\"/"/g;

  open( FH, "> $tmp_file" ) || error( "Can't open $tmp_file : $!" . __FILE__ . ":" . __LINE__ ) && return 0;
  print FH "$cmd\n";
  close(FH);

  #
  # do not execute it here
  # execute it in the run time based on cmd stored in $tmp_file
  #

  # write colors into a file
  if ( $color_file_change == 1 ) {
    open( FHC, "> $file_color_save" ) || error( "file cannot be created :  $file_color_save " . __FILE__ . ":" . __LINE__ ) && return 0;
    foreach my $line_cs (@color_save) {
      chomp($line_cs);    # it must be there, somehow appear there \n ...
      if ( $line_cs eq '' ) {
        next;
      }
      if ( $line_cs =~ m/ : / ) {
        print FHC "$line_cs\n";
      }
    }
    close(FHC);
  }

  # colours

  return 1;
}    ## sub multiview_ovirt

sub multiview_solaris_zone {
  my $group      = shift;
  my $name       = shift;
  my $type       = shift;
  my $type_sam   = shift;
  my $act_time   = shift;
  my $step_new   = shift;
  my $text       = shift;
  my $xgrid      = shift;
  my $item       = shift;
  my $req_time   = 0;
  my $comm       = "COMM ";
  my $line_items = 2;
  $color_indx = 0;    # clear color index
  my $list              = "$webdir/custom/$group/list.txt";
  my $lim               = ".li";
  my $color_file_change = 0;
  my $file_color_save   = "$basedir/tmp/custom-group-solaris-zone-$group-$item.col";
  my $lparno            = 0;

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
    $req_time  = $act_time - 31536000;
    $skip_time = $YEAR_REFRESH;
  }

  my $tmp_file = "$tmpdir/custom-group-solaris-zone-${item}-$group-$type.cmd";

  # do not update weekly/monthly/yearly command files each run
  if ( -f "$tmp_file" ) {
    my $tmp_time = ( stat("$tmp_file") )[9];
    if ( ( $act_time - $tmp_time ) < $skip_time ) {
      print "                        skipped this time : ( $act_time - $tmp_time ) < $skip_time \n";
      return 0;
    }
  }

  # open a file with stored colours
  my @color_save = "";
  if ( -f "$file_color_save" ) {
    open( FHC, "< $file_color_save" ) || error( "file cannot be opened : $file_color_save " . __FILE__ . ":" . __LINE__ ) && return 0;
    @color_save = <FHC>;
    close(FHC);
  }

  my $type_edt = 0;
  if ( -f $type_edt_files ) {
    $type_edt = 1;
  }

  if ( $item eq 'cpu_used' ) {
    open( FHL, "> $list" ) || error( "Can't open $list : $!" . __FILE__ . ":" . __LINE__ ) && return 0;
  }
  else {
    open( FHL, ">> $list" ) || error( "Can't open $list : $!" . __FILE__ . ":" . __LINE__ ) && return 0;
  }

  # header adjusted for oVirt
  my $header = "Solaris zone custom group $group";
  $header .= " : last $text";

  my $file    = "";
  my $i       = 0;
  my $lpar    = "";
  my $lparn   = "";
  my $cmd     = "";
  my $cmdx    = "";
  my $cmdx2   = "";
  my $cmd_xpo = "";
  my $j       = 0;

  my $lim_org = $lim;
  $lim =~ s/\.//;
  $lim =~ s/i/l/;

  # get rrdtool params for oVirt metrics (based on $item)
  my $itemcount      = 0;
  my $cmd_params     = '';
  my $vertical_label = '';
  my $cmd_def        = '';
  my $cmd_cdef       = '';
  my $cmd_legend     = '';

  if ( $item =~ /cpu_used/ ) {
    $cmd_params     = " --lower-limit=0.00";
    $vertical_label = " --vertical-label=\"CPU in cores\"";
    $cmd_legend     = " COMMENT:\"[cores]\\n\"";
  }
  elsif ( $item =~ /phy_mem_us/ ) {
    $cmd_params     = " --lower-limit=0.00";
    $vertical_label = " --vertical-label=\"MEM used in GB\"";
    $cmd_legend     = " COMMENT:\"[GB]\\n\"";
  }

  $cmd_legend .= " COMMENT:\" Zone                     Solaris                       Avrg     Max\\n\"";

  $cmd .= "graph \\\"$name.png\\\"";
  $cmd .= " --title \\\"$header\\\"";
  $cmd .= " --start now-1$type";
  $cmd .= " --end now-1$type+1$type";
  $cmd .= " --imgformat PNG";
  $cmd .= " $disable_rrdtool_tag_agg";
  $cmd .= " --slope-mode";
  $cmd .= " --width=400";
  $cmd .= " --height=150";
  $cmd .= " --step=$step_new";
  $cmd .= " --color=BACK#$pic_col";
  $cmd .= " --color=SHADEA#$pic_col";
  $cmd .= " --color=SHADEB#$pic_col";
  $cmd .= " --color=CANVAS#$pic_col";
  $cmd .= " --units-exponent=1.00";
  $cmd .= " --alt-y-grid";
  $cmd .= " --x-grid=$xgrid";
  $cmd .= " $vertical_label";
  $cmd .= $cmd_params;
  $cmd .= $cmd_legend;

  my $gtype             = "AREA";
  my $updated           = " ";
  my $index             = 0;
  my @lpars_graph_local = @lpars_graph;
  my $line_indx         = 0;              # place enter every 3rd line

  my %uniq_files;
  my $newest_file_timestamp = 0;

  # do not sort it HERE!! there is several arrays, sorting lpars_graph is not enough!!! --PH

  foreach my $file_tmp (@lpars_graph_local) {

    # filename
    my $file                = "$file_tmp.mmm";                # must be here to allocate new space and do not make changes in @lpars_graph
                                                              # load labels
    my $solaris_zone_name   = $lpars_graph_name[$index];      # name zone of Solaris
    my $solaris_server      = $lpars_graph_server[$index];    # Solaris server name
    my $solaris_server_name = $server;                        # Solaris server name
                                                              #print "$solaris_zone_name-$solaris_server\n";
                                                              # TODO debug print
                                                              #print "## custom.pl DEBUG pre-graph\n\t$file\t$solaris_server\t$solaris_zone_name\n";

    if ( $file eq '' ) {
      $index++;
      next;                                                   #some trash
    }
    if ( !-f $file ) {
      $index++;
      next;
    }

    # avoid old lpars which do not exist in the period
    my $rrd_upd_time = ( stat("$file") )[9];
    if ( $rrd_upd_time < $req_time ) {
      $index++;
      next;
    }
    $lpar = $solaris_server_name;

    my $lpar_proc = "$lpar $delimiter " . "$solaris_zone_name";    # for html legend
    $lpar_proc =~ s/%/%%/g;
    $lpar_proc =~ s/:/\\:/g;
    $lpar_proc =~ s/\&\&1/\//g;

    $lpar =~ s/\&\&1/\//g;
    for ( my $k = length($lpar); $k < 25; $k++ ) {
      $lpar .= " ";
    }
    $lpar .= "   ";
    $lpar .= $solaris_zone_name;
    $lpar =~ s/\&\&1/\//g;

    # to keep same count of characters
    $lpar =~ s/\\:/:/g;
    $lpar = sprintf( "%-25s", $lpar );
    $lpar =~ s/:/\\:/g;

    # TODO copied from VMware, could be simplified
    my $lpar_space_proc = $solaris_zone_name;
    my $lpar_space      = "$lpar $lpar_space_proc";
    for ( my $k = length($lpar_space); $k < 50; $k++ ) {
      $lpar_space .= " ";
    }

    $lpar_space_proc = "$lpar $delimiter " . "$lpar_space_proc";
    $lpar_space_proc =~ s/\:/\\:/g;

    if ( exists $uniq_files{"$file"} ) {    # check duplicities
      $index++;
      next;
    }
    $uniq_files{"$file"} = 1;
    $lparn .= " ";
    print FHL "$file\n";

    if ( ( length($lpar_v) + 1 ) == length($comm) && length($lparn) == length($comm) ) {
      copy_source_org( $webdir, $tmpdir, $basedir, $lim_org, $lim, $group );
      last;
    }

    if ( $type =~ "d" ) {
      RRDp::cmd qq(last "$file");
      my $last_tt = RRDp::read;
      chomp($$last_tt);
      $newest_file_timestamp = $$last_tt if $$last_tt > $newest_file_timestamp;
    }

    # Found out stored color index to keep same color for the volume across all graphs
    my $file_color = $file;
    $file_color =~ s/\.r..$//;
    $file_color =~ s/\\//g;
    $file_color =~ s/:/===========doublecoma=========/g;
    my $color_indx_found = -1;
    $color_indx = 0;
    foreach my $line_col (@color_save) {
      chomp($line_col);
      if ( $line_col eq '' || $line_col !~ m/ : / ) {
        next;
      }
      $color_indx++;
      ( my $color_indx_found_act, my $volume_name_save ) = split( / : /, $line_col );

      # do not use here $volume_name_save '' as this does not work when volume id is zero!
      if ( $volume_name_save =~ m/^$file_color$/ ) {
        $color_indx_found = $color_indx_found_act;
        $color_indx       = $color_indx_found;
        last;
      }
    }
    if ( $color_indx_found == -1 ) {
      $color_file_change = 1;
      $color_save[$color_indx] = $color_indx . " : " . $file_color;
    }
    while ( $color_indx > $color_max ) {
      $color_indx = $color_indx - $color_max;
    }

    # end color

    if ( $type_edt == 0 && $lparno == 4 ) {
      copy_source_org( $webdir, $tmpdir, $basedir, $lim_org, $lim, $group );
      last;
    }
    $lparno++;

    # note: replace colons in VM label
    my $vm_name_escaped = $solaris_zone_name;
    $vm_name_escaped =~ s/:/\\:/g;

    # add spaces to lpar name to have 25 chars total (for formating graph legend)
    $vm_name_escaped =~ s/\&\&1/\//g;
    for ( my $k = length($vm_name_escaped); $k < 25; $k++ ) {
      $vm_name_escaped .= " ";
    }
    chomp $vm_name_escaped;
    for ( my $l = length($solaris_server); $l < 25; $l++ ) {
      $solaris_server .= " ";
    }
    chomp $solaris_server;

    # create the graph command itself
    my $itemcolor    = $color[ $color_indx % ( $color_max + 1 ) ];
    my $itemlabel    = "$vm_name_escaped";                           # $lpar_space_proc
    my $ds_name1     = "";
    my $ds_name2     = "";
    my $ds_name3     = "";
    my $ds_name4     = "";
    my $lf_format    = "";
    my $item_to_html = "";

    if ( $item eq "cpu_used" ) {
      $ds_name1     = "cpu_used";
      $lf_format    = "%5.2lf";
      $item_to_html = "custom_solaris_cpu";
      $file            =~ s/:/\\:/g;
      $vm_name_escaped =~ s/:/\\:/g;
      $solaris_server  =~ s/:/\\:/g;
    }
    elsif ( $item eq "phy_mem_us" ) {
      $ds_name1     = "phy_mem_us";
      $ds_name2     = "cap_used_in_perc";
      $ds_name3     = "allocated_memory";
      $ds_name4     = "phy_mem_us_in_perc";
      $lf_format    = "%3.1lf";
      $item_to_html = "custom_solaris_mem";
      $file            =~ s/:/\\:/g;
      $vm_name_escaped =~ s/:/\\:/g;
      $solaris_server  =~ s/:/\\:/g;
    }
    my $index_to_display = $color_indx;

    #if ( $lpar_color_index > -1 ) {
    #  $index_to_display = $lpar_color_index;
    #}
    if ( $item eq "cpu_used" ) {
      if ( $vm_name_escaped eq "total" ) { $vm_name_escaped = "-"; }
      $cmd .= " DEF:utiltot${i}=\"$file\":$ds_name1:AVERAGE";
      $cmd .= " $gtype:utiltot${i}$color[$color_indx]:\\\"$vm_name_escaped $solaris_server\\\"";    #### LEGEND WHEN YOU CLICK ON THE GRAPH
      $cmd .= " GPRINT:utiltot${i}:AVERAGE:\"$lf_format\"";
      $cmd .= " GPRINT:utiltot${i}:MAX:\"$lf_format \"";

      $cmd .= " PRINT:utiltot${i}:AVERAGE:\"$lf_format $delimiter $item_to_html $delimiter $vm_name_escaped $delimiter $color[$index_to_display] $delimiter $file\"";    #### HTML LEGEND to detail-graph.cgi !!!
      $cmd .= " PRINT:utiltot${i}:MAX:\" $lf_format $delimiter\"";
      $cmd .= " COMMENT:\\\"\\l\\\"";
    }
    elsif ( $item eq "phy_mem_us" ) {
      $cmd .= " DEF:utiltot${i}=\"$file\":$ds_name1:AVERAGE";
      $cmd .= " CDEF:utiltot_res${i}=utiltot${i},1000,/,1000,/";

      $cmd .= " $gtype:utiltot_res${i}$color[$color_indx]:\\\"$vm_name_escaped  $solaris_server\\\"";                                                                    #### LEGEND WHEN YOU CLICK ON THE GRAPH
      $cmd .= " GPRINT:utiltot_res${i}:AVERAGE:\"$lf_format \"";
      $cmd .= " GPRINT:utiltot_res${i}:MAX:\"$lf_format \"";

      $cmd .= " PRINT:utiltot_res${i}:AVERAGE:\"$lf_format $delimiter $item_to_html $delimiter $vm_name_escaped $delimiter $color[$index_to_display] $delimiter $file\"";
      $cmd .= " PRINT:utiltot_res${i}:MAX:\" $lf_format $delimiter\"";
      $cmd .= " COMMENT:\\\"\\l\\\"";
    }
    $gtype = "STACK";

    $i++;
    $color_indx = ++$color_indx % ( $color_max + 1 );
    $index++;

    if ( !get_lpar_num() && $index == 5 ) {
      last;
    }
    if ( $line_indx == $line_items ) {

      # put carriage return after each second lpar in the legend
      $cmd .= " COMMENT:\"\\l\"";
      $line_indx = 0;
    }
    else {
      $line_indx++;
    }

  }
  $cmd .= $cmdx;
  $cmd .= $cmdx2;

  close(FHL);

  if ( $i == 0 ) {
    print "creating cgraph: " . scalar localtime() . " custom:$group $item $type: no any source found, skipping\n";

    # if there is not CMD file, create at least emty graph
    return 0 if -f $tmp_file;    # nothing has been found
  }
  if ( $newest_file_timestamp > 0 ) {
    my $l = localtime($newest_file_timestamp);

    # following must be for RRD 1.2+
    $l =~ s/:/\\:/g;
    $updated = " COMMENT:\\\"  Updated\\\: $l \\\"";
  }

  $cmd .= " $updated";
  $cmd .= " HRULE:0#000000";

  # $cmd .= " VRULE:0#000000";  --> it is causing sigsegv on linuxeS
  $cmd =~ s/\\"/"/g;

  open( FH, "> $tmp_file" ) || error( "Can't open $tmp_file : $!" . __FILE__ . ":" . __LINE__ ) && return 0;
  print FH "$cmd\n";
  close(FH);

  #
  # do not execute it here
  # execute it in the run time based on cmd stored in $tmp_file
  #

  # write colors into a file
  if ( $color_file_change == 1 ) {
    open( FHC, "> $file_color_save" ) || error( "file cannot be created :  $file_color_save " . __FILE__ . ":" . __LINE__ ) && return 0;
    foreach my $line_cs (@color_save) {
      chomp($line_cs);    # it must be there, somehow appear there \n ...
      if ( $line_cs eq '' ) {
        next;
      }
      if ( $line_cs =~ m/ : / ) {
        print FHC "$line_cs\n";
      }
    }
    close(FHC);
  }

  # colours

  return 1;
}    ## sub multiview_solaris_zone

sub multiview_hyperv {
  my $group    = shift;
  my $name     = shift;
  my $type     = shift;
  my $type_sam = shift;
  my $act_time = shift;
  my $step_new = shift;
  my $text     = shift;
  my $xgrid    = shift;
  my $item     = shift;

  my $req_time   = 0;
  my $comm       = "COMM ";
  my $line_items = 2;
  $color_indx = 0;    # clear color index
  my $list              = "$webdir/custom/$group/list.txt";
  my $lim               = ".li";
  my $color_file_change = 0;
  my $file_color_save   = "$basedir/tmp/custom-group-hyperv-$group-$item.col";
  my $lparno            = 0;

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
    $req_time  = $act_time - 31536000;
    $skip_time = $YEAR_REFRESH;
  }

  my $tmp_file = "$tmpdir/custom-group-hyperv-${item}-$group-$type.cmd";

  # do not update weekly/monthly/yearly command files each run
  if ( -f "$tmp_file" ) {
    my $tmp_time = ( stat("$tmp_file") )[9];
    if ( ( $act_time - $tmp_time ) < $skip_time ) {
      print "                        skipped this time : ( $act_time - $tmp_time ) < $skip_time \n";
      return 0;
    }
  }

  # open a file with stored colours
  my @color_save = "";
  if ( -f "$file_color_save" ) {
    open( FHC, "< $file_color_save" ) || error( "file cannot be opened : $file_color_save " . __FILE__ . ":" . __LINE__ ) && return 0;
    @color_save = <FHC>;
    close(FHC);
  }

  my $type_edt = 0;

  # lately change to $type_edt_filey
  if ( -f $type_edt_fileh ) {
    $type_edt = 1;
  }

  open( FHL, "> $list" ) || error( "Can't open $list : $!" . __FILE__ . ":" . __LINE__ ) && return 0;

  # header adjusted for HYPERV
  my $header = "CPU Custom group $group";
  $header .= " : last $text";

  my $file    = "";
  my $i       = 0;
  my $lpar    = "";
  my $lparn   = "";
  my $cmd     = "";
  my $cmdx    = "";
  my $cmdx2   = "";
  my $cmd_xpo = "";
  my $j       = 0;

  my $lim_org = $lim;
  $lim =~ s/\.//;
  $lim =~ s/i/l/;

  # get rrdtool params for metrics (based on $item)
  my $itemcount      = 0;
  my $cmd_params     = '';
  my $vertical_label = '';
  my $cmd_def        = '';
  my $cmd_cdef       = '';
  my $cmd_legend     = '';

  if ( $item =~ /cpu/ ) {
    $cmd_params     = " --lower-limit=0.00";
    $vertical_label = " --vertical-label=\"CPU in cores\"";
    $cmd_legend     = " COMMENT:\"[cores]\\n\"";
  }
  elsif ( $item =~ /phy_mem_us/ ) {
    $cmd_params     = " --lower-limit=0.00";
    $vertical_label = " --vertical-label=\"MEM used in GB\"";
    $cmd_legend     = " COMMENT:\"[GB]\\n\"";
  }

  $cmd_legend .= " COMMENT:\" server                     VM                       Avrg     Max\\n\"";

  $cmd .= "graph \\\"$name.png\\\"";
  $cmd .= " --title \\\"$header\\\"";
  $cmd .= " --start now-1$type";
  $cmd .= " --end now-1$type+1$type";
  $cmd .= " --imgformat PNG";
  $cmd .= " $disable_rrdtool_tag_agg";
  $cmd .= " --slope-mode";
  $cmd .= " --width=400";
  $cmd .= " --height=150";
  $cmd .= " --step=$step_new";
  $cmd .= " --color=BACK#$pic_col";
  $cmd .= " --color=SHADEA#$pic_col";
  $cmd .= " --color=SHADEB#$pic_col";
  $cmd .= " --color=CANVAS#$pic_col";
  $cmd .= " --units-exponent=1.00";
  $cmd .= " --alt-y-grid";
  $cmd .= " --x-grid=$xgrid";
  $cmd .= " $vertical_label";
  $cmd .= $cmd_params;
  $cmd .= $cmd_legend;

  my $gtype             = "AREA";
  my $updated           = " ";
  my $index             = 0;
  my @lpars_graph_local = @lpars_graph;
  my $line_indx         = 0;              # place enter every 3rd line

  my %uniq_files;
  my $newest_file_timestamp = 0;

  # do not sort it HERE!! there is several arrays, sorting lpars_graph is not enough!!! --PH

  foreach my $file_tmp (@lpars_graph_local) {

    # filename
    my $file                = "$file_tmp";                    # must be here to allocate new space and do not make changes in @lpars_graph
                                                              # load labels
    my $solaris_zone_name   = $lpars_graph_name[$index];      # name zone of Solaris
    my $solaris_server      = $lpars_graph_server[$index];    # Solaris server name
    my $solaris_server_name = $server;                        # Solaris server name
                                                              # print "6347 ,$solaris_zone_name-$solaris_server,\n";
                                                              # TODO debug print
                                                              # print "## custom.pl DEBUG pre-graph\n\t$file\t$solaris_server\t$solaris_zone_name\n";

    if ( $file eq '' ) {
      $index++;
      next;                                                   #some trash
    }
    if ( !-f $file ) {
      $index++;
      next;
    }

    # avoid old lpars which do not exist in the period
    my $rrd_upd_time = ( stat("$file") )[9];
    if ( $rrd_upd_time < $req_time ) {
      $index++;
      next;
    }
    $lpar = $solaris_server_name;

    my $lpar_proc = "$solaris_server $delimiter " . "$solaris_zone_name";    # for html legend
    $lpar_proc =~ s/%/%%/g;
    $lpar_proc =~ s/:/\\:/g;
    $lpar_proc =~ s/\&\&1/\//g;

    $lpar =~ s/\&\&1/\//g;
    for ( my $k = length($lpar); $k < 25; $k++ ) {
      $lpar .= " ";
    }
    $lpar .= "   ";
    $lpar .= $solaris_zone_name;
    $lpar =~ s/\&\&1/\//g;

    # to keep same count of characters
    $lpar =~ s/\\:/:/g;
    $lpar = sprintf( "%-25s", $lpar );
    $lpar =~ s/:/\\:/g;

    # TODO copied from VMware, could be simplified
    my $lpar_space_proc = $solaris_zone_name;
    my $lpar_space      = "$lpar $lpar_space_proc";
    for ( my $k = length($lpar_space); $k < 50; $k++ ) {
      $lpar_space .= " ";
    }

    $lpar_space_proc = "$lpar $delimiter " . "$lpar_space_proc";
    $lpar_space_proc =~ s/\:/\\:/g;

    if ( exists $uniq_files{"$file"} ) {    # check duplicities
      $index++;
      next;
    }
    $uniq_files{"$file"} = 1;
    $lparn .= " ";
    print FHL "$file\n";

    if ( ( length($lpar_v) + 1 ) == length($comm) && length($lparn) == length($comm) ) {
      copy_source_org( $webdir, $tmpdir, $basedir, $lim_org, $lim, $group );
      last;
    }

    if ( $type =~ "d" ) {
      RRDp::cmd qq(last "$file");
      my $last_tt = RRDp::read;
      chomp($$last_tt);
      $newest_file_timestamp = $$last_tt if $$last_tt > $newest_file_timestamp;
    }

    # Found out stored color index to keep same color for the volume across all graphs
    my $file_color = $file;
    $file_color =~ s/\.r..$//;
    $file_color =~ s/\\//g;
    $file_color =~ s/:/===========doublecoma=========/g;
    my $color_indx_found = -1;
    $color_indx = 0;
    foreach my $line_col (@color_save) {
      chomp($line_col);
      if ( $line_col eq '' || $line_col !~ m/ : / ) {
        next;
      }
      $color_indx++;
      ( my $color_indx_found_act, my $volume_name_save ) = split( / : /, $line_col );

      # do not use here $volume_name_save '' as this does not work when volume id is zero!
      if ( $volume_name_save =~ m/^$file_color$/ ) {
        $color_indx_found = $color_indx_found_act;
        $color_indx       = $color_indx_found;
        last;
      }
    }
    if ( $color_indx_found == -1 ) {
      $color_file_change = 1;
      $color_save[$color_indx] = $color_indx . " : " . $file_color;
    }
    while ( $color_indx > $color_max ) {
      $color_indx = $color_indx - $color_max;
    }

    # end color

    if ( $type_edt == 0 && $lparno == 4 ) {
      copy_source_org( $webdir, $tmpdir, $basedir, $lim_org, $lim, $group );
      last;
    }
    $lparno++;

    # note: replace colons in VM label
    my $vm_name_escaped = $solaris_zone_name;
    $vm_name_escaped =~ s/:/\\:/g;

    # add spaces to lpar name to have 25 chars total (for formating graph legend)
    $vm_name_escaped =~ s/\&\&1/\//g;
    for ( my $k = length($vm_name_escaped); $k < 25; $k++ ) {
      $vm_name_escaped .= " ";
    }
    chomp $vm_name_escaped;
    for ( my $l = length($solaris_server); $l < 25; $l++ ) {
      $solaris_server .= " ";
    }
    chomp $solaris_server;

    # create the graph command itself
    my $itemcolor    = $color[ $color_indx % ( $color_max + 1 ) ];
    my $itemlabel    = "$vm_name_escaped";                           # $lpar_space_proc
    my $ds_name1     = "";
    my $ds_name2     = "";
    my $ds_name3     = "";
    my $ds_name4     = "";
    my $lf_format    = "";
    my $item_to_html = "";

    if ( $item eq "cpu" ) {
      $ds_name1     = "PercentTotalRunTime";
      $ds_name2     = "Timestamp_PerfTime";
      $ds_name3     = "Frequency_PerfTime";
      $lf_format    = "%5.2lf";
      $item_to_html = "custom_hyperv_cpu";
    }
    elsif ( $item eq "phy_mem_us" ) {
      $ds_name1     = "phy_mem_us";
      $ds_name2     = "cap_used_in_perc";
      $ds_name3     = "allocated_memory";
      $ds_name4     = "phy_mem_us_in_perc";
      $lf_format    = "%3.1lf";
      $item_to_html = "custom_solaris_mem";
    }
    my $index_to_display = $color_indx;

    #if ( $lpar_color_index > -1 ) {
    #  $index_to_display = $lpar_color_index;
    #}
    if ( $item eq "cpu" ) {
      $cmd .= " DEF:cpu_perc${i}=\"$file\":$ds_name1:AVERAGE";
      $cmd .= " DEF:cpu_time${i}=\"$file\":$ds_name2:AVERAGE";
      $cmd .= " DEF:cpu_freq${i}=\"$file\":$ds_name3:AVERAGE";
      $cmd .= " CDEF:utiltot${i}=cpu_perc${i},cpu_time${i},/,cpu_freq${i},*,100000,/,100,/";    # to be in cores

      $cmd .= " $gtype:utiltot${i}$color[$color_indx]:\\\"$solaris_server $vm_name_escaped\\\"";    #### LEGEND WHEN YOU CLICK ON THE GRAPH
      $cmd .= " GPRINT:utiltot${i}:AVERAGE:\"$lf_format\"";
      $cmd .= " GPRINT:utiltot${i}:MAX:\"$lf_format \"";

      $cmd .= " PRINT:utiltot${i}:AVERAGE:\"$lf_format $delimiter $item_to_html $delimiter $lpar_proc $delimiter $color[$index_to_display] $delimiter some_cluster\"";    #### HTML LEGEND to detail-graph.cgi !!!
      $cmd .= " PRINT:utiltot${i}:MAX:\" $lf_format $delimiter $color[$index_to_display] $delimiter $file\"";
      $cmd .= " PRINT:utiltot${i}:MAX:\" $lf_format $delimiter some_legend\"";
      $cmd .= " COMMENT:\\\"\\l\\\"";
    }
    elsif ( $item eq "phy_mem_us" ) {
      $cmd .= " DEF:utiltot${i}=\"$file\":$ds_name1:AVERAGE";
      $cmd .= " CDEF:utiltot_res${i}=utiltot${i},1000,/,1000,/";

      $cmd .= " $gtype:utiltot_res${i}$color[$color_indx]:\\\"$vm_name_escaped  $solaris_server\\\"";                                                                     #### LEGEND WHEN YOU CLICK ON THE GRAPH
      $cmd .= " GPRINT:utiltot_res${i}:AVERAGE:\"$lf_format \"";
      $cmd .= " GPRINT:utiltot_res${i}:MAX:\"$lf_format \"";

      $cmd .= " PRINT:utiltot_res${i}:AVERAGE:\"$lf_format $delimiter $item_to_html $delimiter $vm_name_escaped $delimiter $color[$index_to_display] $delimiter $file\"";
      $cmd .= " PRINT:utiltot_res${i}:MAX:\" $lf_format $delimiter\"";
      $cmd .= " COMMENT:\\\"\\l\\\"";
    }
    $gtype = "STACK";

    $i++;
    $color_indx = ++$color_indx % ( $color_max + 1 );
    $index++;

    if ( !get_lpar_num() && $index == 5 ) {
      last;
    }
    if ( $line_indx == $line_items ) {

      # put carriage return after each second lpar in the legend
      $cmd .= " COMMENT:\"\\l\"";
      $line_indx = 0;
    }
    else {
      $line_indx++;
    }

  }
  $cmd .= $cmdx;
  $cmd .= $cmdx2;

  close(FHL);

  if ( $i == 0 ) {
    print "creating cgraph: custom:$group $item $type: no any source found, skipping\n";

    # if there is not CMD file, create at least emty graph
    return 0 if -f $tmp_file;    # nothing has been found
  }
  if ( $newest_file_timestamp > 0 ) {
    my $l = localtime($newest_file_timestamp);

    # following must be for RRD 1.2+
    $l =~ s/:/\\:/g;
    $updated = " COMMENT:\\\"  Updated\\\: $l \\\"";
  }

  $cmd .= " $updated";
  $cmd .= " HRULE:0#000000";

  # $cmd .= " VRULE:0#000000";  --> it is causing sigsegv on linuxeS
  $cmd =~ s/\\"/"/g;

  open( FH, "> $tmp_file" ) || error( "Can't open $tmp_file : $!" . __FILE__ . ":" . __LINE__ ) && return 0;
  print FH "$cmd\n";
  close(FH);

  #
  # do not execute it here
  # execute it in the run time based on cmd stored in $tmp_file
  #

  # write colors into a file
  if ( $color_file_change == 1 ) {
    open( FHC, "> $file_color_save" ) || error( "file cannot be created :  $file_color_save " . __FILE__ . ":" . __LINE__ ) && return 0;
    foreach my $line_cs (@color_save) {
      chomp($line_cs);    # it must be there, somehow appear there \n ...
      if ( $line_cs eq '' ) {
        next;
      }
      if ( $line_cs =~ m/ : / ) {
        print FHC "$line_cs\n";
      }
    }
    close(FHC);
  }

  # colours

  return 1;
}    ## sub multiview_hyperv

# ORVM
sub multiview_orvm {
  my $group    = shift;
  my $name     = shift;
  my $type     = shift;
  my $type_sam = shift;
  my $act_time = shift;
  my $step_new = shift;
  my $text     = shift;
  my $xgrid    = shift;
  my $item     = shift;

  # $item toggles graph type (CPU, memory etc.), use CPU by default
  $item = 'cpu-percent' if !defined $item;

  my $req_time = 0;
  my $comm     = "COMM ";
  $color_indx = 0;    # clear color index
  my $list              = "$webdir/custom/$group/list.txt";
  my $lim               = ".li";
  my $updated           = "";
  my $color_file_change = 0;
  my $file_color_save   = "$basedir/tmp/custom-group-$group.col";
  my $lparno            = 0;

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
    $req_time  = $act_time - 31536000;
    $skip_time = $YEAR_REFRESH;
  }

  # modified filename for ORVM
  my $tmp_file = "$tmpdir/custom-group-orvm-${item}-$group-$type.cmd";

  # do not update weekly/monthly/yearly command files each run
  if ( -f "$tmp_file" ) {
    my $tmp_time = ( stat("$tmp_file") )[9];
    if ( ( $act_time - $tmp_time ) < $skip_time ) {
      print "                        skipped this time : ( $act_time - $tmp_time ) < $skip_time \n";
      return 0;
    }
  }

  # open a file with stored colours
  my @color_save = "";
  if ( -f "$file_color_save" ) {
    open( FHC, "< $file_color_save" ) || error( "file cannot be opened : $file_color_save " . __FILE__ . ":" . __LINE__ ) && return 0;
    @color_save = <FHC>;
    close(FHC);
  }

  my $type_edt = 0;
  if ( -f $type_edt_filex ) {
    $type_edt = 1;
  }

  if ( $item eq 'cpu-percent' ) {
    open( FHL, "> $list" ) || error( "Can't open $list : $!" . __FILE__ . ":" . __LINE__ ) && return 0;
  }
  else {
    open( FHL, ">> $list" ) || error( "Can't open $list : $!" . __FILE__ . ":" . __LINE__ ) && return 0;
  }

  # header adjusted for OracleVM (eventually switch to XenServerGraph::get_header)
  my $header = "OracleVM custom group $group";
  $header .= " : last $text";

  my $file    = "";
  my $i       = 0;
  my $lpar    = "";
  my $lparn   = "";
  my $cmd     = "";
  my $cmdx    = "";
  my $cmdx2   = "";
  my $cmd_xpo = "";    # unused here, unlike in multiview_vims (VMware)
  my $j       = 0;

  my $lim_org = $lim;
  $lim =~ s/\.//;
  $lim =~ s/i/l/;

  # get rrdtool params for OracleVM metrics (based on $item)
  my $cmd_params;
  if ( $item =~ m/^cpu-cores$/ ) {
    $cmd_params = OracleVmGraph::get_params_cpu('cores');
  }
  elsif ( $item =~ m/^mem-used$/ ) {
    $cmd_params = OracleVmGraph::get_params_mem('mem-used');
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
  $cmd .= " --step=$step_new";
  $cmd .= " --color=BACK#$pic_col";
  $cmd .= " --color=SHADEA#$pic_col";
  $cmd .= " --color=SHADEB#$pic_col";
  $cmd .= " --color=CANVAS#$pic_col";
  $cmd .= " --units-exponent=1.00";
  $cmd .= " --alt-y-grid";
  $cmd .= " --x-grid=$xgrid";
  $cmd .= $cmd_params;

  # legends adjusted for OracleVM (based on oVirt)
  if ( $item =~ m/^cpu-cores$/ ) {

    #$cmd .= " COMMENT:\"[cores]\"";
    $cmd .= " COMMENT:\"ServerPool                  VM                                     Avrg     Max\\n\"";
  }
  elsif ( $item =~ m/^mem-used/ ) {
    $cmd .= " COMMENT:\"[GB]\\n\"";
  }
  elsif ( $item =~ m/^vbd$/ ) {
    $cmd .= " COMMENT:\"[MiB/s]\\n\"";
  }
  elsif ( $item =~ m/^vbd-latency$/ ) {
    $cmd .= " COMMENT:\"[millisec]\\n\"";
  }
  elsif ( $item =~ m/^vbd-iops$/ ) {
    $cmd .= " COMMENT:\"[iops]\\n\"";
  }
  elsif ( $item =~ m/^lan$/ ) {
    $cmd .= " COMMENT:\"[MB/s]\\n\"";
  }

  #if ($item =~ m/^cpu-cores$/){
  #  $cmd .= " COMMENT:\"ServerPool                  VM                                     Avrg     Max\\n\"";
  #}

  my $index             = 0;
  my @lpars_graph_local = @lpars_graph;

  my %uniq_files;
  my $newest_file_timestamp = 0;

  # do not sort it HERE!! there is several arrays, sorting lpars_graph is not enough!!! --PH
  foreach my $file_tmp (@lpars_graph_local) {

    # filename
    my $file = $file_tmp;    # must be here to allocate new space and do not make changes in @lpars_graph

    # load labels
    my $vm_name     = $lpars_graph_name[$index];      # VM label
    my $server      = $lpars_graph_server[$index];    # pool label
    my $server_name = $server;                        # pool label

    # TODO debug print
    # print "custom.pl DEBUG pre-graph\n\t$file\t$vm_name\t$server\t$server_name\n";

    if ( $file eq '' ) {
      $index++;
      next;    #some trash
    }
    if ( !-f $file ) {
      $index++;
      next;
    }

    # avoid old lpars which do not exist in the period
    my $rrd_upd_time = ( stat("$file") )[9];
    if ( $rrd_upd_time < $req_time ) {
      $index++;
      next;
    }

    $lpar = $server_name;

    my $lpar_proc = "$lpar $delimiter " . "$vm_name";    # for html legend
    $lpar_proc =~ s/%/%%/g;
    $lpar_proc =~ s/:/\\:/g;
    $lpar_proc =~ s/\&\&1/\//g;

    $lpar =~ s/\&\&1/\//g;
    for ( my $k = length($lpar); $k < 25; $k++ ) {
      $lpar .= " ";
    }
    $lpar .= "   ";
    $lpar .= $vm_name;
    $lpar =~ s/\&\&1/\//g;

    # to keep same count of characters
    $lpar =~ s/\\:/:/g;
    $lpar = sprintf( "%-25s", $lpar );
    $lpar =~ s/:/\\:/g;

    # TODO copied from VMware, could be simplified
    my $lpar_space_proc = $vm_name;
    my $lpar_space      = "$lpar $lpar_space_proc";
    for ( my $k = length($lpar_space); $k < 50; $k++ ) {
      $lpar_space .= " ";
    }

    $lpar_space_proc = "$lpar $delimiter " . "$lpar_space_proc";
    $lpar_space_proc =~ s/\:/\\:/g;

    if ( exists $uniq_files{"$file"} ) {    # check duplicities
      $index++;
      next;
    }
    $uniq_files{"$file"} = 1;
    $lparn .= " ";
    print FHL "$file\n";

    if ( ( length($lpar_v) + 1 ) == length($comm) && length($lparn) == length($comm) ) {
      copy_source_org( $webdir, $tmpdir, $basedir, $lim_org, $lim, $group );
      last;
    }

    if ( $type =~ "d" ) {
      RRDp::cmd qq(last "$file");
      my $last_tt = RRDp::read;
      chomp($$last_tt);
      $newest_file_timestamp = $$last_tt if $$last_tt > $newest_file_timestamp;
    }

    if ( $type_edt == 0 && $lparno == 4 ) {
      copy_source_org( $webdir, $tmpdir, $basedir, $lim_org, $lim, $group );
      last;
    }
    $lparno++;

    # Found out stored color index to keep same color for the volume across all graphs
    my $file_color = $file;
    $file_color =~ s/\.r..$//;
    $file_color =~ s/\\//g;
    $file_color =~ s/:/===========doublecoma=========/g;
    my $color_indx_found = -1;
    $color_indx = 0;

    foreach my $line_col (@color_save) {
      chomp($line_col);
      if ( $line_col eq '' || $line_col !~ m/ : / ) {
        next;
      }
      $color_indx++;
      ( my $color_indx_found_act, my $volume_name_save ) = split( / : /, $line_col );

      # do not use here $volume_name_save '' as this does not work when volume id is zero!
      if ( $volume_name_save =~ m/^$file_color$/ ) {
        $color_indx_found = $color_indx_found_act;
        $color_indx       = $color_indx_found;
        last;
      }
    }
    if ( $color_indx_found == -1 ) {
      $color_file_change = 1;
      $color_save[$color_indx] = $color_indx . " : " . $file_color;
    }
    while ( $color_indx > $color_max ) {
      $color_indx = $color_indx - $color_max;
    }

    # end color

    # note: replace colons in VM label
    my $vm_name_escaped = $vm_name;
    $vm_name_escaped =~ s/:/\\:/g;

    # create the graph command itself
    $color_indx = ++$color_indx % ( $color_max + 1 );
    my $itemcolor = $color[ $color_indx % ( $color_max + 1 ) ];
    my $itemlabel = "$vm_name_escaped";                           # $lpar_space_proc
    my $poollabel = "$server_name";

    my $graph_info;
    if ( $item =~ m/^cpu-cores/ ) {
      $graph_info = OracleVmGraph::graph_cpu_aggr( 'vm', 'cores', $file, $i, $itemcolor, $itemlabel, $poollabel, 'pool' );
    }
    elsif ( $item =~ m/^mem-used/ ) {
      $graph_info = OracleVmGraph::graph_memory_aggr( 'vm', 'mem-used', $file, $i, $itemcolor, $itemlabel, $poollabel, 'pool' );
    }
    elsif ( $item =~ m/^(vbd|lan)/ ) {

      # need second color
      $color_indx = ++$color_indx % ( $color_max + 1 );
      my $itemcolor2 = $color[ $color_indx % ( $color_max + 1 ) ];
      if ( $item =~ m/^vbd$/ ) {
        $graph_info = XenServerGraph::graph_storage_aggr( 'vm', 'vbd', $file, $i, $itemcolor, $itemcolor2, $itemlabel, $poollabel );
      }
      elsif ( $item =~ m/^vbd-latency$/ ) {
        $graph_info = XenServerGraph::graph_storage_aggr( 'vm', 'latency', $file, $i, $itemcolor, $itemcolor2, $itemlabel, $poollabel );
      }
      elsif ( $item =~ m/^vbd-iops$/ ) {
        $graph_info = XenServerGraph::graph_storage_aggr( 'vm', 'iops', $file, $i, $itemcolor, $itemcolor2, $itemlabel, $poollabel );
      }
      elsif ( $item =~ m/^lan$/ ) {
        $graph_info = XenServerGraph::graph_lan_aggr( 'vm', $file, $i, $itemcolor, $itemcolor2, $itemlabel, $poollabel );
      }
    }
    else {
      error("multiview_orvm unsupported item $item");
    }
    $cmd .= $graph_info->{cmd_def};
    $cmd .= $graph_info->{cmd_cdef};
    if ( $item =~ m/^(cpu|mem)/ ) {
      $cmdx .= $graph_info->{cmd_legend};
    }
    else {
      $cmdx  .= $graph_info->{cmd_legend_lower};
      $cmdx2 .= $graph_info->{cmd_legend_upper};
    }

    $i++;

    # done

    $index++;

    #    if ( ! get_lpar_num() && $index_l > 4 ) {
    #      last;
    #    }
  }
  $cmd .= $cmdx;
  $cmd .= $cmdx2;

  close(FHL);

  if ( $i == 0 ) {
    print "creating cgraph: custom:$group $item $type: no any source found, skipping\n";

    # if there is not CMD file, create at least emty graph
    return 0 if -f $tmp_file;    # nothing has been found
  }
  if ( $newest_file_timestamp > 0 ) {
    my $l = localtime($newest_file_timestamp);

    # following must be for RRD 1.2+
    $l =~ s/:/\\:/g;
    $updated = " COMMENT:\\\"  Updated\\\: $l \\\"";
  }

  $cmd .= " $updated";
  $cmd .= " HRULE:0#000000";

  # $cmd .= " VRULE:0#000000";  --> it is causing sigsegv on linuxeS
  $cmd =~ s/\\"/"/g;

  open( FH, "> $tmp_file" ) || error( "Can't open $tmp_file : $!" . __FILE__ . ":" . __LINE__ ) && return 0;
  print FH "$cmd\n";
  close(FH);

  #
  # do not execute it here
  # execute it in the run time based on cmd stored in $tmp_file
  #

  # write colors into a file
  if ( $color_file_change == 1 ) {
    open( FHC, "> $file_color_save" ) || error( "file cannot be created :  $file_color_save " . __FILE__ . ":" . __LINE__ ) && return 0;
    foreach my $line_cs (@color_save) {
      chomp($line_cs);    # it must be there, somehow appear there \n ...
      if ( $line_cs eq '' ) {
        next;
      }
      if ( $line_cs =~ m/ : / ) {
        print FHC "$line_cs\n";
      }
    }
    close(FHC);
  }

  # colours

  return 1;
}

