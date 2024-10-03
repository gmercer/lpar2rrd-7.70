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
use Date::Parse;
use File::Compare;
use LoadDataModuleHyperV;
use File::Copy;
use POSIX qw(strftime);
use POSIX ":sys_wait_h";

#use File::Glob ':glob';

use Data::Dumper;
use Time::Local;
use File::Glob qw(bsd_glob GLOB_TILDE);
use XoruxEdition;

#use lib qw (/opt/freeware/lib/perl/5.8.0);
# no longer need to use "use lib qw" as the library PATH is already in PERL5LIB env var (lpar2rrd.cfg)

# touch tmp/hyperv-debug to have debug info in load output

# set unbuffered stdout
$| = 1;

# get cmd line params
my $version = "$ENV{version}";

#my $host    = "$ENV{HMC_SPACE}";    # contains username

# example: $tmpdir/HYPERV_X/Notebook   or  $tmpdir/HYPERV/Notebook
# take only basedir
#$host = ( split( "\/", $host ) )[-1];

# exit if $host !~ "444"; # my home debug
my $alias;
my $username;
my $hmc_user = $ENV{HMC_USER};
my $webdir   = $ENV{WEBDIR};
my $bindir   = $ENV{BINDIR};
my $basedir  = $ENV{INPUTDIR};
my $tmpdir   = "$basedir/tmp";

if ( defined $ENV{TMPDIR_LPAR} ) {
  $tmpdir = $ENV{TMPDIR_LPAR};
}
my $rrdtool = $ENV{RRDTOOL};
my $DEBUG   = $ENV{DEBUG};
$DEBUG = 2 if ( -f "$tmpdir/hyperv-debug" );    # for extensive debug prints

#print_hyperv_debug("HYPDIR in perl $host\n") if $DEBUG == 2;

my $pic_col                 = $ENV{PICTURE_COLOR};
my $STEP                    = $ENV{SAMPLE_RATE};
my $managed_systems_exclude = $ENV{MANAGED_SYSTEMS_EXCLUDE};
my $upgrade                 = $ENV{UPGRADE};
my $SSH                     = $ENV{SSH} . " -q ";              # doubles -q from lpar2rrd.cfg, just to be sure ...

###  HYPER-V def section

my $command_date;                                              # server time when starting this script

my $et_VirtualMachine         = "VirtualMachine";
my $et_HostSystem             = "HostSystem";
my $et_Datastore              = "Datastore";
my $et_ResourcePool           = "ResourcePool";
my $et_Datacenter             = "Datacenter";
my $et_ClusterComputeResource = "ClusterComputeResource";

my $no_inserted                = 66;
my $real_sampling_period_limit = 900;
my %vm_name_uuid;
my %vm_uuid_mac;
my %vm_uuid_mem;
my %vm_name_powerstat;
my %vm_name_vcpu;
my %vm_id_path = ();    # contains vm_id : $wrkdir/$server/host/vm_uuid.rrm
my $samples_number;
my @vm_view = ();       # VM names

# longer line to omit - possible error sub hyperv_load
my $max_line_length = 10000;

my $pth = "";           # keeps actual path to WIN data files

# hyperv VM EnabledState
my %enabledstate = (
  1     => "OTHER",
  2     => "ON",
  3     => "OFF",
  4     => "STOPPING",
  5     => "NA",
  6     => "OFFLINE",
  7     => "TEST",
  8     => "DEFERRED",
  9     => "QUIESCE",
  32768 => "PAUSED",
  32769 => "SUSPENDED",
  32770 => "STARTING",
  32771 => "SNAPSHOTTING",
  32773 => "SAVING",
  32774 => "STOPPING",
  32776 => "PAUSINIG",
  32777 => "RESUMING"
);

my %cpu_status = (
  0 => "Unknown (0)",
  1 => "CPU Enabled (1)",
  2 => "CPU Disabled by User via BIOS Setup (2)",
  3 => "CPU Disabled By BIOS (POST Error) (3)",
  4 => "CPU is Idle (4)",
  5 => "Reserved (5)",
  6 => "Reserved (6)",
  7 => "Other (7)"
);

my $UnDeF = "UnDeFiNeD";    # const for testing data

#   perf values Hostsystem or VM HYPER-V
my @vm_PercentTotalRunTime;
my @vm_Timestamp_PerfTime;
my @vm_Frequency_PerfTime;
my @vm_AvailableMBytes;
my @vm_CacheBytes;
my @vm_MemoryAvailable;
my @vm_TotalPhysicalMemory;
my @vm_DiskBytesPersec;
my @vm_DiskReadBytesPersec;
my @vm_DiskReadsPersec;
my @vm_DiskTransfersPersec;
my @vm_DiskWriteBytesPerse;
my @vm_DiskWritesPersec;
my @vm_BytesReceivedPersec;
my @vm_BytesSentPersec;
my @vm_BytesTotalPersec;
my @vm_PagesInputPersec;
my @vm_PagesOutputPersec;
my @vm_vCPU;

my @vm_Memory_active_KB;
my @vm_Memory_granted_KB;
my @vm_Memory_baloon_MB;
my @vm_Disk_usage_KBps;
my @vm_Disk_read_KBps;
my @vm_Disk_write_KBps;
my @vm_Network_usage_KBps;
my @vm_Network_received_KBps;
my @vm_Network_transmitted_KBps;
my @vm_Memory_swapin_KBps;
my @vm_Memory_swapout_KBps;
my @vm_Memory_compres_KBps;
my @vm_Memory_decompres_KBps;
my @vm_CPU_usage_Percent;
my @Host_memory_size;
my @Host_processes;
my @Host_threads;
my @Host_SystemCallsPersec;
my @vm_CPU_ready_ms;

my @arr_pointers;
my $pointer_arr = \@arr_pointers;

#   perf values cluster, some also for resourcepool
my @cl_CPU_usage_Proc;
my @cl_CPU_usage_MHz;
my @cl_CPU_reserved_MHz;
my @cl_Memory_usage_Proc;
my @cl_Memory_reserved_MB;
my @cl_Memory_granted_KB;
my @cl_Memory_active_KB;
my @cl_Memory_shared_KB;
my @cl_Memory_zero_KB;
my @cl_Memory_swap_KB;
my @cl_Memory_baloon_KB;
my @cl_Memory_consumed_KB;
my @cl_Memory_overhead_KB;
my @cl_Memory_compressed_KB;
my @cl_Memory_compression_KBps;
my @cl_Memory_decompress_KBps;
my @cl_Power_usage_Watt;
my @cl_Power_cup_Watt;
my @cl_Power_energy_usage_Joule;
my @cl_Cluster_eff_CPU_MHz;
my @cl_Cluster_eff_memory_MB;
my @cl_CPU_total_MHz;
my @cl_Memory_total_MB;

my @cl_cpu_limit;
my @cl_cpu_reservation;
my @cl_mem_limit;
my @cl_mem_reservation;
my $cluster_effectiveMemory;
my $cluster_effectiveCpu;

my $rp_cpu_reservation = 0;
my $rp_mem_reservation = 0;
my $rp_cpu_limit       = 0;
my $rp_mem_limit       = 0;

#   perf values datastore
my @ds_Datastore_freeSpace_KB;
my @ds_Datastore_used_KB;
my @ds_Datastore_provision_KB;
my @ds_Datastore_capacity_KB;
my @ds_Datastore_read_KBps;
my @ds_Datastore_write_KBps;
my @ds_Datastore_numberReadAveraged;
my @ds_Datastore_numberWriteAveraged;

my $ds_accessible;    # true/false 1/0
my $ds_freeSpace;
my $ds_used;
my $ds_provisioned;
my $ds_capacity;
my $ds_type = "";     # or 'NFS' when NFS type

my $service_instance; # vmware TOP
my $apiType_top;
my $fullName_top;
my $do_fork;          # 1 means do!, 0 do not!
my @managednamelist_un;

my $host_hz;
my $host_cpuAlloc;
my $host_memorySize;

my $server;
my $command_unix;        # holds server UTC unix time - integer
my $vm_host;             # host hash
my $h_name;              # host name
my $fail_entity_type;    # for error printing
my $fail_entity_name;    # for error printing
my $numCpu;

# keeps all VMs: $wrkdir/$all_hyperv_VMs
#  NO, prepare it per domain
my $all_hyperv_VMs = "hyperv_VMs";
my $vm_uuid_active = "";
my $wrkdir_windows = "";

# in the beginning of file can be GLOBAL INFO
# GLOBAL INFO BEGIN
# any lines of info, e.g. cluster nodes, agent mode or ...:6500
# GLOBAL INFO END
my @global_info = ();
my @local_info  = ();

# keeps server domain until end of script for possible cluster
my %server_domain = ();

# skipped computers - probably clusters
my %skipped_computers = ();

# keeps uuid{name} for all hyperv VMs
my $all_vm_uuid_names = "vm_uuid_name.txt";

# keeps all Cluster Storages UUID
my %all_clusterstorage = ();

# keeps computer names in a cluster
my %cluster_computers = ();

# function xerror if main: appends notice to following file
#                 if fork: just prints XERROR text
#        XERROR text is appended when reading forks' output
my $counters_info_file = "$basedir/logs/counter-info.txt";
my $i_am_fork          = "main";                             # in fork is 'fork'

my $lpm        = $ENV{LPM};
my $h          = $ENV{HOSTNAME};
my $new_change = "$tmpdir/$version-run";

my $delimiter = "XORUX";                                     # this is for rrdtool print lines for clickable legend

#print "++ $host $hmc_user $basedir $webdir $STEP\n";
my $wrkdir = "$basedir/data";

# Global definitions
my $loadhours        = "";
my $loadmins         = "";
my $loadsec_vm       = "";
my $type_sam         = "";
my $managedname      = "";
my $step             = "";
my $NO_TIME_MULTIPLY = 60;                                   # just for windows
my $no_time          = $STEP * $NO_TIME_MULTIPLY;            # says the time interval when RRDTOOL consideres a gap in input data 60 mins now!

my $INIT_LOAD_IN_HOURS_BACK = "18";                          # not need more as 1 minute samples are no longer there, daily are not more used since 4.60

my $PARALLELIZATION = 5;

#   $PARALLELIZATION = 1;

my @pool_list = "";

# my @managednamelist_un=();
my @managednamelist     = ();
my @managednamelist_vmw = ();
my $HMC                 = 1;                                 # if HMC then 1, if IVM/SDMC then 0
my $SDMC                = 0;
my $IVM                 = 0;
my $FSM                 = 0;                                 # so far only for setting lslparutil AMS parames
my @lpar_trans          = "";                                # lpar translation names/ids for IVM systems

# last timestamp files --> must be for each load separated
my $last_file = "last.txt";                                  # for ESXi server

# last file for every resource pool is 'rp_name.last'
my $last_rec     = "";
my $sec          = "";
my $ivmmin       = "";
my $ivmh         = "";
my $ivmd         = "";
my $ivmm         = "";
my $ivmy         = "";
my $wday         = "";
my $yday         = "";
my $isdst        = "";
my $timeout_save = 600;    # timeout for downloading whole server/lpar cfg from the HMC (per 1 server), it prevents hanging

# my $timeout=120; # timeout for vcenter operations

my @returns;               # for forking
my $server_count = 0;
my @pid          = "";
my $cycle_count  = 1;

my @lpm_excl_vio = "";

my $rrd_ver = $RRDp::VERSION;

rrdtool_graphv();

my $prem = premium();
print "LPAR2RRD $prem version $version\n" if $DEBUG;
print "Host           : $h\n"             if $DEBUG;
my $date     = "";
my $act_time = localtime();

# print "Hyper-V   start: $host $act_time\n" if $DEBUG;

my %hyp_data     = ();    # structure with all data of last (newer) date
my %hyp_data_one = ();    # structure with all data of last but one date

my $hyperv_host = "";

if ( !-d "$webdir" ) {
  error( " Pls set correct path to Web server pages, it does not exist here: $webdir" . __FILE__ . ":" . __LINE__ ) && return 0;
}

### get tmp/HYPERV/comp_uuid containing more than one data files "1234567890.txt"
my $tmp_hypdir               = "$tmpdir/HYPERV";
my $host                     = "";
my @tmphypdir_folders        = ();
my @active_tmphypdir_folders = ();
my $total_file_count         = 0;
my %active_comps             = ();

my $fork_limit = 10000;    # not more perf files in one fork, good for average file size 20 kB
if ( defined $ENV{WINDOWS_FORK_LIMIT} && $ENV{WINDOWS_FORK_LIMIT} > 0 ) {
  $fork_limit = $ENV{WINDOWS_FORK_LIMIT};
}

opendir my $tmphypdirFH, $tmp_hypdir || error("Cannot open $tmp_hypdir") && exit 1;
@tmphypdir_folders = grep { -d "$tmp_hypdir/$_" && !/^..?$/ } readdir($tmphypdirFH);

# print "490 @tmphypdir_folders\n";
close $tmphypdirFH;

# choose the active ones
foreach (@tmphypdir_folders) {

  #my $comp_folder = "$tmp_hypdir/$_";
  my $comp_folder = "$_";

  # print "496 \$comp_folder $comp_folder\n";
  if ( opendir my $tmphypdirFH, "$tmp_hypdir/$comp_folder" ) {
    my $file_count = scalar grep {/^\d\d\d\d\d\d\d\d\d\d\.txt$/} readdir($tmphypdirFH);
    close $tmphypdirFH;

    # print "500 $comp_folder has $file_count files\n";
    if ( $file_count > 1 ) {
      $total_file_count += $file_count;
      push @active_tmphypdir_folders, $comp_folder;
      $active_comps{$comp_folder} = $file_count;
      print "               : 508 $comp_folder has $file_count files\n";
    }
  }
  else {
    error("Cannot open $comp_folder");
  }
}

# print Dumper %active_comps;
if ( $total_file_count < 2 ) {
  print "perf files     : not detected > exit\n";
  exit;
}
if ( $total_file_count < $fork_limit ) {
  print "perf files     : $total_file_count/limit=$fork_limit > no fork\n";
  win_pef_data_parse_engine( \@active_tmphypdir_folders );
  exit;
}
else {
  print "perf files     : $total_file_count/limit=$fork_limit > start fork\n";
  my $end_index = 100;
  my $pid;

  while ( scalar @active_tmphypdir_folders > 0 ) {
    $end_index--;
    my @perf_group = ();
    $perf_group[0] = $active_tmphypdir_folders[0];
    my $file_count_in_group = $active_comps{ $perf_group[0] };
    shift @active_tmphypdir_folders;
    while ( scalar @active_tmphypdir_folders > 0 ) {
      if ( ( $file_count_in_group + $active_comps{ $active_tmphypdir_folders[0] } ) > $fork_limit ) {
        last;
      }
      $file_count_in_group += $active_comps{ $active_tmphypdir_folders[0] };
      push @perf_group, $active_tmphypdir_folders[0];
      shift @active_tmphypdir_folders;
    }
    print "               : 540 forking with group \@perf_group @perf_group\n";
    local *FH;

    #$pid[$server_count] = open( FH, "-|" );
    $pid = open( FH, "-|" );

    if ( not defined $pid ) {
      error("could not fork");
    }
    elsif ( $pid == 0 ) {
      print "Fork           :  child pid $$\n" if $DEBUG;
      win_pef_data_parse_engine( \@perf_group );
      print "Fork       exit:  child pid $$\n" if $DEBUG;
      exit(0);
    }
    print "Parent continue: parent pid $$ \$end_index $end_index\n";
    push @returns, *FH;
    last if !$end_index;
  }
  print_fork_output();
}
exit;

### ----------------------- exit main --------------------------

sub print_fork_output {
  return if ( scalar @returns == 0 );

  # print output of all forks
  foreach my $fh (@returns) {
    while (<$fh>) {

      #if ( $_ =~ 'XERROR' ) {
      #  ( undef, my $text ) = split( ":", $_, 2 );
      #  print $FH "$text";
      #}
      #elsif ( $_ =~ "^update_line" ) {
      #  push @all_vcenter_perf_data, $_;
      #}
      #else {
      print $_;

      #}
    }
    close($fh);
  }
  @returns = ();    # clear the filehandle list

  waitpid( -1, WNOHANG );
  print "All chld finish: WINDOWS $host \n" if $DEBUG;
}

sub win_pef_data_parse_engine {
  my $active_comps_ref = shift;

  # start RRD via a pipe
  use RRDp;
  RRDp::start "$rrdtool";

  my $rrdtool_version = 'Unknown';
  $_ = `$rrdtool`;
  if (/^RRDtool ([1-9]*\.[0-9]*(\.[0-9]*)?)/) {
    $rrdtool_version = $1;
  }
  print "RRDp    version: $RRDp::VERSION \n";
  print "RRDtool version: $rrdtool_version\n";

  print "Perl version   : $] \n";

  foreach (@$active_comps_ref) {

    # in the beginning of file can be GLOBAL INFO
    # GLOBAL INFO BEGIN
    # any lines of info, e.g. cluster nodes, agent mode or ...:6500
    # GLOBAL INFO END
    @global_info = ();
    @local_info  = ();

    # keeps server domain until end of script for possible cluster
    %server_domain = ();

    # skipped computers - probably clusters
    %skipped_computers = ();

    # keeps uuid{name} for all hyperv VMs
    $all_vm_uuid_names = "vm_uuid_name.txt";

    # keeps all Cluster Storages UUID
    %all_clusterstorage = ();

    # keeps computer names in a cluster
    %cluster_computers = ();

    $date     = "";
    $act_time = localtime();

    %hyp_data     = ();    # structure with all data of last (newer) date
    %hyp_data_one = ();    # structure with all data of last but one date

    $hyperv_host = "";

    $host = $_;
    print "\n#####          : start parsing \$host  $host\n\n";
    load_hmc();
  }

  # close RRD pipe
  RRDp::end;

  $date = localtime();
  print "date end       : $hyperv_host $date\n" if $DEBUG;
}

sub delta_get_hyp_val {    # creates delta value from actual and last but one values
  my ( $class, $item, $hyp_data_comp_act, $hyp_data_comp_last, $line_contains ) = @_;

  my $values_act = get_hyp_val( $class, $item, $hyp_data_comp_act,  $line_contains );
  my $values_one = get_hyp_val( $class, $item, $hyp_data_comp_last, $line_contains );
  if ( $item =~ "ReadBytesPersec" || $item =~ "WriteBytesPerse" ) {
    print "485 \$values_act $values_act \$values_one $values_one \$line_contains $line_contains\n" if $DEBUG == 2;
  }
  if ( $item =~ "PercentTotalRunTime" ) {
    print_hyperv_debug("467000 \$values_act $values_act \$values_one $values_one\n") if $DEBUG == 2;
  }
  if ( $values_act eq "UnDeFiNeD" ) {
    print_hyperv_debug("467001 \$class $class \$item $item \$line_contains $line_contains\n") if $DEBUG == 2;
  }

  # result is one or more values delimited by ','
  my @values_act_arr = split( /,/, $values_act );
  my @values_one_arr = split( /,/, $values_one );
  my $ret_str        = "";
  print_hyperv_debug("469 hyp2rrd.pl \@values_act_arr @values_act_arr \@values_one_arr @values_one_arr\n") if $DEBUG == 2;

  my $i = 0;
  while ( defined $values_act_arr[$i] && defined $values_one_arr[$i] && isdigit( $values_act_arr[$i] ) && isdigit( $values_one_arr[$i] ) ) {
    my $diff = $values_act_arr[$i] - $values_one_arr[$i];
    $diff = 0 if $diff < 0;
    if ( $ret_str eq "" ) {
      $ret_str = $diff;
    }
    else {
      $ret_str .= ",$diff";
    }
    $i++;
  }
  if ( $item =~ "PercentTotalRunTime" ) {
    print_hyperv_debug("487 \$ret_str $ret_str\n") if $DEBUG == 2;
  }
  if ( $values_act eq "UnDeFiNeD" && $values_one eq "UnDeFiNeD" ) {
    $ret_str = "UnDeFiNeD";
  }
  return $ret_str;
}

sub get_hyp_val {
  my ( $class, $item, $ref_data, $line_contains ) = @_;

  # data example
  # 'Msvm_ComputerSystem' => [
  #                             'Caption|CreationClassName|Description|ElementName|EnabledState|HealthState|Name|NumberOfNumaNodes|OperatingStatus|Status|StatusDescriptions|Hyperv_UTC',
  #                             'Hosting Computer System|Msvm_ComputerSystem|Microsoft Hosting Computer System|HYPERV01|2|5|HYPERV01|1|0|OK|(OK)|1508229032',
  #                             'Virtual Machine|Msvm_ComputerSystem|Microsoft Virtual Machine|XoruX|3|5|143E4B15-1E45-4D7B-B352-ECE54359A778|1|0|OK|(Operating normally)|1508229032',
  #                             'Virtual Machine|Msvm_ComputerSystem|Microsoft Virtual Machine|XoruX-master|2|5|3138F59F-11AD-46FB-951C-9C147C98896C|1|0|OK|(Operating normally)|150822903
  #                             'Virtual Machine|Msvm_ComputerSystem|Microsoft Virtual Machine|WinXP|2|5|8E3AB390-A112-4DCB-AAB4-CE51042A7A4A|1|0|OK|(Operating normally)|1508229032'
  #                          ],
  # format $line_contains is either a string or special string starting with 'ITEM='
  # $line_contains = "ITEM=Name=\"$csv_number\"";

  my $line_contains_or     = "";
  my $line_contains_bslash = "";
  my $item_name            = "";
  my $item_contain         = "";

  if ( not defined $line_contains ) {
    $line_contains = "";
  }
  elsif ( $line_contains =~ "^ITEM=" ) {
    ( undef, $item_name, $item_contain ) = split( "=", $line_contains );
  }
  else {
    #  # $line_contains = "\"$line_contains";
    #
    $line_contains_or     = $line_contains . "\"" if $line_contains ne "";    # differ two strings having same beginning
    $line_contains_bslash = $line_contains . "\\" if $line_contains ne "";    # differ two strings having same beginning
  }

  # $ref_data is a pointer to hash of computer data

  #  print "get_hyp_val, \$class $class \$line_contains $line_contains \$line_contains_bslash $line_contains_bslash\n";

  my $ret_val = $UnDeF;    # return it when any error
                           # print "524XX \$class ,$class,\n";

  if ( !defined $$ref_data->{$class}[0] ) {
    error( "not defined \$ref_data { $class } [0]" . __FILE__ . ":" . __LINE__ );
    return $ret_val;
  }
  my $hyp_line = $$ref_data->{$class}[0];

  my @os_arr     = split( /,/, $hyp_line );
  my $index      = -1;                        # the last one is Hyperv_UTC
  my $item_index = "";

  if ( $item ne "Hyperv_UTC" ) {              #&& $item ne "computerdomain" ) left_curly                       # always the last
                                              # what is index of item?
    ($index) = grep { $os_arr[$_] eq "\"$item\"" } 0 .. $#os_arr;
    if ( !defined $index ) {
      error( "not defined \$item $item in \$hyp_line $hyp_line" . __FILE__ . ":" . __LINE__ );
      return $ret_val;
    }
    if ( $item_name ne "" ) {
      ($item_index) = grep { $os_arr[$_] eq "\"$item_name\"" } 0 .. $#os_arr;
      if ( !defined $item_index ) {
        error( "not defined \$item_name $item_name in \$hyp_line $hyp_line" . __FILE__ . ":" . __LINE__ );
        return $ret_val;
      }
    }
  }

  # print "\$index $index\n";
  $ret_val = "";
  my $line_x = 1;
  my $coma   = "";
  while ( defined $$ref_data->{$class}[$line_x] ) {
    $hyp_line = $$ref_data->{$class}[$line_x];
    $line_x++;
    print_hyperv_debug("531 \$hyp_line ,$hyp_line, \$line_contains ,$line_contains, \$item_name ,$item_name, \$item_index ,$item_index,\n") if $DEBUG == 2;
    if ( $item_name eq "" ) {

      # next if $line_contains ne "" && index($hyp_line, $line_contains_or) == -1 && index($hyp_line, $line_contains_bslash) == -1 && index($hyp_line, $line_contains.":") == -1 && index($hyp_line, $line_contains.".") == -1 && index($hyp_line, $line_contains."_") == -1; # exact test
      next if lc($line_contains) ne "" && index( lc($hyp_line), lc($line_contains_or) ) == -1 && index( lc($hyp_line), lc($line_contains_bslash) ) == -1 && index( lc($hyp_line), lc($line_contains) . ":" ) == -1 && index( lc($hyp_line), lc($line_contains) . "." ) == -1 && index( lc($hyp_line), lc($line_contains) . "_" ) == -1 && index( lc($hyp_line), lc($line_contains) . "-" ) == -1;    # exact test
    }
    else {
      # next if ( split( /,/, $hyp_line ) )[$item_index] ne $item_contain;
      next if lc( ( split( /,/, $hyp_line ) )[$item_index] ) ne lc($item_contain);
    }
    $ret_val .= $coma;
    my $atom = ( split( /,/, $hyp_line ) )[$index];

    # remove quotes in the beginning and end
    $atom =~ s/^\"//;
    $atom =~ s/\"$//;
    $ret_val .= $atom;
    $coma = ",";
  }
  $ret_val = $UnDeF if $ret_val eq "";
  return $ret_val;
}

sub load_hmc {

  # take sorted <<files>> from dir $tmpdir/HYPERV/$HYPDIR
  # for every two timely consecutive files call load_hmc_one
  # finished file mv to dir lpar2rrd/tmp/hyperv_uuid... so that there are always two latest files

  $hyperv_host = $host;
  $host =~ s/\//&&1/g;    # general replacement for slash
  my $comp_uuid = $host;

  $pth = "$tmpdir/HYPERV/$host";    # real data # is global var
                                    # my $pth = "$tmpdir/HYPERV_X/$host"; # debug data
                                    # my $pth = $host;
  $pth =~ s/\&\&1/\//g;

  # reading & working with data txt files in HYPERV
  # print "615 \$pth $pth\n";

  my $dirios;
  if ( !opendir( $dirios, "$pth" ) ) {
    error("cannot open dir $pth, exiting");
    return;
  }
  my @files_iostats = grep /\d{10}.txt$/, ( grep !/^\.\.?$/, readdir($dirios) );
  closedir($dirios);

  my @sorted_files       = sort @files_iostats;
  my $sorted_files_count = scalar @sorted_files;

  # print "\@sorted_files  : @sorted_files\n";
  print "\@sorted_files  : $sorted_files_count files prepared for pushing to RRD ";
  print "$sorted_files[0] is the 1st one"        if $sorted_files_count > 0;
  print " and $sorted_files[-1] is the last one" if $sorted_files_count > 1;
  print "\n";
  return if scalar @sorted_files < 2;    # at least two files
  my $indx = 1;
  while ( defined $sorted_files[$indx] ) {

    # 1504012098 1504012998 limit max 3600 sec
    my $old_time = $sorted_files[ $indx - 1 ];
    $old_time =~ s/\.txt$//;

    #$old_time =~ /_(\d+)\.prf/;
    #$old_time =$1;
    my $new_time = $sorted_files[$indx];
    $new_time =~ s/\.txt$//;

    #$new_time =~ /_(\d+)\.prf/;
    #$new_time =$1;

    # clean for every run
    %hyp_data     = ();    # structure with all data of last (newer) date
    %hyp_data_one = ();    # structure with all data of last but one date

    if ( ( $new_time - $old_time ) < 3601 ) {    # only when lower time diff
      load_hmc_all_comps( "$pth/$sorted_files[$indx]", "$pth/$sorted_files[$indx-1]" );
    }

    # save files to lpar2rrd/tmp/hyperv_$host_[last & act]
    my $file_last = $sorted_files[ $indx - 1 ];
    $file_last =~ s/$old_time.txt/hyperv_/;
    $file_last = "$file_last$comp_uuid" . "_last.txt";
    my $file_act = $sorted_files[$indx];
    $file_act =~ s/$new_time.txt/hyperv_/;
    $file_act = "$file_act$comp_uuid" . "_act.txt";
    print "598 move $pth/$sorted_files[$indx-1] to $tmpdir/$file_last & copy $pth/$sorted_files[$indx] to $tmpdir/$file_act\n" if $DEBUG == 2;

    if ( !move "$pth/$sorted_files[$indx-1]", "$tmpdir/$file_last" ) {
      error("cannot move $pth/$sorted_files[$indx-1] to $wrkdir/$tmpdir/$file_last");
    }
    if ( !copy "$pth/$sorted_files[$indx]", "$tmpdir/$file_act" ) {
      error("cannot copy $pth/$sorted_files[$indx] to $wrkdir/$tmpdir/$file_act");
    }
    $indx++;
  }

  return;
}

sub load_hmc_all_comps {
  my $file_act          = shift;
  my $file_last_but_one = shift;

  %cluster_computers = ();

  print_hyperv_debug("641 $file_act $file_last_but_one\n") if $DEBUG == 2;

  hyperv_load( $file_act, $file_last_but_one );

  # print "715 result from hyperv_load.pl\n";
  # print Dumper (\%hyp_data);
  # print Dumper (\%hyp_data_one);

  # cycle on comp in actual data hash
  # if the same comp in last but one hash then load data

  foreach my $comp ( keys %hyp_data ) {
    if ( exists $hyp_data_one{$comp} ) {
      print_hyperv_debug("653 loading data for computer $comp\n") if $DEBUG == 2;
      load_hmc_one_comp( \$hyp_data{$comp}, \$hyp_data_one{$comp} );
    }
  }
  print Dumper ( "728 cluster computers:", \%cluster_computers );
  print Dumper ( "729 skipped computers:", \%skipped_computers );
  print Dumper ( "730 cluster storage:",   \%all_clusterstorage );

  if ( keys %cluster_computers ) {

    # as you can see: cluster CLUSTER_XY has 2 nodes COMP026 & COMP028 cus they have common Volumes
    #   $VAR1 = '728 cluster computers:'; from %cluster_computers
    #   $VAR2 = {
    #     'CLUSTER_XY' => 'COMP026'
    #   };
    #   $VAR1 = '730 cluster storage:'; from %all_clusterstorage
    #   $VAR2 = {
    #     'COMP028' => {
    #     '?Volume{a51424c5-ae85-43c8-9bea-8d882f8a716a}' => 'ahojte',
    #     '?Volume{e0612b02-f45e-4489-b108-9d54be3f1b16}' => 'ahojte'
    #     },
    #     'COMP026' => {
    #     '?Volume{a51424c5-ae85-43c8-9bea-8d882f8a716a}' => 'ahojte',
    #     '?Volume{e0612b02-f45e-4489-b108-9d54be3f1b16}' => 'ahojte'
    #     }
    #   }

    foreach my $cluster_name ( keys %cluster_computers ) {
      my %cluster_nodes   = ();
      my $comp_in_cluster = $cluster_computers{$cluster_name};
      print "756 \$cluster_name $cluster_name \$comp_in_cluster $comp_in_cluster\n";
      if ( !exists $all_clusterstorage{$comp_in_cluster} ) {
        error("cluster $cluster_name has no nodes");
        next;
      }
      my $storage_hash = $all_clusterstorage{$comp_in_cluster};    #test only 1st storage volume
                                                                   # print Dumper ("storage_hash",\$storage_hash);
      my $storage      = each %$storage_hash;

      # print "761 \$cluster_name $cluster_name \$comp_in_cluster $comp_in_cluster \$storage $storage\n";
      # print Dumper ("762 ",$storage);

      # get all nodes containing the volume
      foreach my $cmp ( keys %all_clusterstorage ) {
        if ( exists $all_clusterstorage{$cmp}{$storage} ) {
          $cluster_nodes{$cmp} = "cluster_node";
        }
      }
      print "cluster nodes  : for cluster $cluster_name\n";
      print Dumper( \%cluster_nodes );

      # prepare table cluster nodes  !!!! see MSCluster node to node
      my @node_list = ();
      foreach ( keys %cluster_nodes ) {
        my $node_name = $_;
        print_hyperv_debug("745 \$node_name $node_name\n") if $DEBUG == 2;
        my $RoleOfNode  = "UnDeFiNeD";
        my $StateOfNode = "UnDeFiNeD";
        my $domain_name = "UnDeFiNeD";
        if ( exists $server_domain{$node_name} ) {
          $domain_name = $server_domain{$node_name};
        }

        my $line = $cluster_name . "," . $domain_name . "," . $node_name . "," . $RoleOfNode . "," . $StateOfNode . "\n";
        push @node_list, $line;
      }

      # if does not exist cluster dir, prepare it
      my $cluster_dir = "$wrkdir_windows/cluster_$cluster_name";

      if ( !-d "$cluster_dir" ) {
        print "mkdir          : $cluster_dir\n";
        mkdir( "$cluster_dir", 0755 ) || error( " Cannot mkdir $cluster_dir: $!" . __FILE__ . ":" . __LINE__ ) && return 0;
      }

      #prepare node_list table
      my $res_ret = FormatResults(@node_list);

      open my $FH_node, '>:encoding(UTF-8)', "$cluster_dir/node_list.html" or error( "can't open $cluster_dir/node_list.html: $!" . __FILE__ . ":" . __LINE__ ) && return 0;
      binmode( $FH_node, ":utf8" );

      print $FH_node "<BR><CENTER><TABLE class=\"tabconfig tablesorter\">";
      print $FH_node "<thead><TR> <TH class=\"sortable\" valign=\"center\">CLUSTER&nbsp;&nbsp;&nbsp;&nbsp;</TH>
            <TH align=\"center\" class=\"sortable\" valign=\"center\">&nbsp;&nbsp;&nbsp;DOMAIN&nbsp;&nbsp;&nbsp;</TH>
            <TH align=\"center\" class=\"sortable\" valign=\"center\">&nbsp;&nbsp;&nbsp;Node&nbsp;&nbsp;&nbsp;</TH>
            <TH align=\"center\" class=\"sortable\" valign=\"center\">&nbsp;&nbsp;&nbsp;RoleOfNode&nbsp;&nbsp;&nbsp;</TH>
  			    <TH align=\"center\" class=\"sortable\" valign=\"center\">&nbsp;&nbsp;&nbsp;StateOfNode&nbsp;&nbsp;&nbsp;</TH>
            </TR></thead><tbody>\n";
      print $FH_node "$res_ret";

      print $FH_node "</tbody></TABLE></CENTER>\n";
      close $FH_node;

    }
  }
  elsif ( !( !keys %skipped_computers ) ) {
    print "skipped comps  :\n";
    print Dumper( \%skipped_computers );

    # try to find nodes of possible cluster
    # cluster storage:
    # $VAR1 = {
    #           'HVNODE01' => {
    #                          '?Volume{b994eb5b-844f-45a7-86ea-6116e3175653}' => 'ahojte',
    #                          '?Volume{1d2ac989-641d-4fa0-9ee0-6a391c8be0da}' => 'ahojte'
    #                         },
    #           'HVNODE02' => {
    #                           '?Volume{1d2ac989-641d-4fa0-9ee0-6a391c8be0da}' => 'ahojte',
    #                           '?Volume{b994eb5b-844f-45a7-86ea-6116e3175653}' => 'ahojte'
    #                         }
    #         };
    # skipped comps  :
    # $VAR1 = {
    #           'HVNODE01' => 'MSNET-HVCL'
    #         };
    # looking for cluster nodes
    # $VAR1 = {
    #          'HVNODE01' => 'cluster_node',
    #          'HVNODE02' => 'cluster_node'
    #         };

    if ( !( !keys %all_clusterstorage ) ) {

      # seems there is cluster here
      foreach my $comp ( keys %skipped_computers ) {
        my $cluster_name  = $skipped_computers{$comp};
        my %cluster_nodes = ();
        if ( exists $all_clusterstorage{$comp} && $cluster_name ne "" ) {
          $cluster_nodes{$comp} = "cluster_node";
          foreach my $storage ( keys %{ $all_clusterstorage{$comp} } ) {
            foreach my $cmp ( keys %all_clusterstorage ) {
              if ( exists $all_clusterstorage{$cmp}{$storage} ) {
                $cluster_nodes{$cmp} = "cluster_node";
              }
            }
          }
          print "cluster nodes  : for cluster $cluster_name\n";
          print Dumper( \%cluster_nodes );

          # prepare table cluster nodes  !!!! see MSCluster node to node
          my @node_list = ();
          foreach ( keys %cluster_nodes ) {
            my $node_name = $_;
            print_hyperv_debug("745 \$node_name $node_name\n") if $DEBUG == 2;
            my $RoleOfNode  = "UnDeFiNeD";
            my $StateOfNode = "UnDeFiNeD";
            my $domain_name = "UnDeFiNeD";
            if ( exists $server_domain{$node_name} ) {
              $domain_name = $server_domain{$node_name};
            }

            my $line = $cluster_name . "," . $domain_name . "," . $node_name . "," . $RoleOfNode . "," . $StateOfNode . "\n";
            push @node_list, $line;
          }

          # if does not exist cluster dir, prepare it
          my $cluster_dir = "$wrkdir_windows/cluster_$cluster_name";

          if ( !-d "$cluster_dir" ) {
            print "mkdir          : $cluster_dir\n";
            mkdir( "$cluster_dir", 0755 ) || error( " Cannot mkdir $cluster_dir: $!" . __FILE__ . ":" . __LINE__ ) && return 0;
          }

          #prepare node_list table
          my $res_ret = FormatResults(@node_list);

          open my $FH_node, '>:encoding(UTF-8)', "$cluster_dir/node_list.html" or error( "can't open $cluster_dir/node_list.html: $!" . __FILE__ . ":" . __LINE__ ) && return 0;
          binmode( $FH_node, ":utf8" );

          print $FH_node "<BR><CENTER><TABLE class=\"tabconfig tablesorter\">";
          print $FH_node "<thead><TR> <TH class=\"sortable\" valign=\"center\">CLUSTER&nbsp;&nbsp;&nbsp;&nbsp;</TH>
            <TH align=\"center\" class=\"sortable\" valign=\"center\">&nbsp;&nbsp;&nbsp;DOMAIN&nbsp;&nbsp;&nbsp;</TH>
            <TH align=\"center\" class=\"sortable\" valign=\"center\">&nbsp;&nbsp;&nbsp;Node&nbsp;&nbsp;&nbsp;</TH>
            <TH align=\"center\" class=\"sortable\" valign=\"center\">&nbsp;&nbsp;&nbsp;RoleOfNode&nbsp;&nbsp;&nbsp;</TH>
  			    <TH align=\"center\" class=\"sortable\" valign=\"center\">&nbsp;&nbsp;&nbsp;StateOfNode&nbsp;&nbsp;&nbsp;</TH>
            </TR></thead><tbody>\n";
          print $FH_node "$res_ret";

          print $FH_node "</tbody></TABLE></CENTER>\n";
          close $FH_node;
        }
        else {
          print "skipped comp   : $comp ,$cluster_name,\n";
        }
      }
    }
    else {
      print "skipped comps  :\n";
      print Dumper( \%skipped_computers );
    }
  }
}

sub load_hmc_one_comp {
  my $hyp_data_comp_act  = shift;    # hash pointer
  my $hyp_data_comp_last = shift;    # hash pointer

  # get system time

  $command_date = get_hyp_val( "Win32_OperatingSystem", "LocalDateTime", $hyp_data_comp_act );
  chomp($command_date);

  $command_unix = get_hyp_val( "Win32_OperatingSystem", "Hyperv_UTC", $hyp_data_comp_act );

  print "system UTC     : $command_date : $command_unix";

  # fetch server SW Type
  $apiType_top  = get_hyp_val( "Win32_OperatingSystem", "Caption", $hyp_data_comp_act );
  $fullName_top = "";
  print "system      UTC: $apiType_top $fullName_top UTC:$command_date : $command_unix\n";

  # system SW type test
  # if ( $apiType_top ne "Microsoft Windows Server 2012 R2 Datacenter Evaluation" ) {
  #  error("Unknown server SW type $apiType_top\n");

  #    return
  # }

  # fetch HostSystem   'Win32_ComputerSystemProduct' UUID  'Win32_OperatingSystem' CSName
  my %pole = ();
  $pole{'name'}              = get_hyp_val( 'Win32_OperatingSystem',       'CSName',            $hyp_data_comp_act );
  $pole{'UUID'}              = get_hyp_val( 'Win32_ComputerSystemProduct', 'UUID',              $hyp_data_comp_act );
  $pole{'IdentifyingNumber'} = get_hyp_val( 'Win32_ComputerSystemProduct', 'IdentifyingNumber', $hyp_data_comp_act );

  my @spole = ();
  $spole[0]              = \%pole;
  $managednamelist_un[0] = \@spole;

  if ( !defined $managednamelist_un[0] || $managednamelist_un[0] eq '' ) {
    error("hyperv name: $host either has not been resolved or ssh key based access is not allowed or other communication error");
    exit(1);
  }
  if ( !defined $managednamelist_un[0] ) {
    error("hyperv name: $host has not array of hosts ?!?");
    print Dumper( $managednamelist_un[0] );
    exit(1);
  }

  if ( $managednamelist_un[0] =~ "no address associated with hostname" || $managednamelist_un[0] =~ "Could not resolve hostname" ) {
    error("vmware : $managednamelist_un[0]");
    exit(1);
  }

  hostsystem_perf( $hyp_data_comp_act, $hyp_data_comp_last );    # Host and all Virtual Machines

  return;
}

sub hostsystem_perf {
  my $hyp_data_comp_act  = shift;                                # hash pointer
  my $hyp_data_comp_last = shift;                                # hash pointer

  $do_fork = "0";
  @returns = ();
  my $model  = "";
  my $serial = "";
  my $line   = "";
  my $hmcv   = "";

  # sorting non case sensitive - not for vmware
  #  @managednamelist = sort { lc($a) cmp lc($b) } @managednamelist_un;
  my $managednamelist = $managednamelist_un[0];

  my $managed_ok;
  my $managedname_exl = "";
  my @m_excl          = "";
  my $once            = 0;
  my $hmcv_num        = "";

  # print Dumper ($managednamelist);
  # print Dumper (\$managednamelist);

  #
###     cycle on $managedname_list (on servers)
  #       get data for all managed systems which are connected

  # servers organized under domain incl VMs

  foreach my $vm_host_tmp ( @{ $managednamelist || [] } ) {
    $vm_host = $vm_host_tmp;
    $h_name  = $$vm_host{'name'};

    my $change_vm_uuid_names = 0;    # if changes must be saved

    # some windows do not supply Win23_ComputerSystem
    my $domain = $UnDeF;
    if ( exists $$hyp_data_comp_act->{'Win32_ComputerSystem'} ) {

      # my $part_of_domain = get_hyp_val( "Win32_ComputerSystem", "PartOfDomain", $hyp_data_comp_act );
      $domain = get_hyp_val( "Win32_ComputerSystem", "Domain", $hyp_data_comp_act );
    }

    # trying to get domain from my own created item
    elsif ( exists $$hyp_data_comp_act->{'Win32_OperatingSystem'} ) {

      #print Dumper (1568, $$hyp_data_comp_act->{'Win32_OperatingSystem'});
      $domain = get_hyp_val( "Win32_OperatingSystem", "computerdomain", $hyp_data_comp_act );    # my own created item
      if ( $domain eq $UnDeF ) {
        error( "Not detected domain name ($domain) for $h_name, using this name (anycomp) " . __FILE__ . ":" . __LINE__ );
        $domain = "anycomp";
      }
    }
    if ( $domain eq $UnDeF ) {
      error( "Detected domain name $domain, skipping this computer $h_name " . __FILE__ . ":" . __LINE__ ) && next;
    }
    my $serv_dom = $domain;
    $domain = "domain_$domain";

    $wrkdir = "$basedir/data";
    my $server_path        = "$wrkdir/windows/$domain";
    my %vm_uuid_names      = ();
    my $vm_uuid_names_file = "$server_path/$all_hyperv_VMs/$all_vm_uuid_names";
    if ( -f "$vm_uuid_names_file" ) {
      open FH, '<:encoding(UTF-8)', "$vm_uuid_names_file" or error( "can't open $vm_uuid_names_file: $!" . __FILE__ . ":" . __LINE__ ) && return 0;
      while ( my $line = <FH> ) {
        chomp $line;
        ( my $word1, my $word2 ) = split /,/, $line, 2;
        $vm_uuid_names{$word1} = $word2;
      }
      close FH;
    }

    # keep orig for tracking if there is a change
    my %vm_uuid_names_orig = %vm_uuid_names;

    # print Dumper ($vm_host);
    # print Dumper (\$vm_host);
    # $h_name = $$vm_host{'name'};
    print_hyperv_debug("\$h_name $h_name \$vm_host ,$vm_host, pid $$\n") if $DEBUG == 2;
    $fail_entity_name = $h_name;
    $fail_entity_type = "Host_System";

    $server_domain{$h_name} = $serv_dom;

    push @managednamelist_vmw, $h_name;

    my $o_uuid = $$vm_host{'UUID'};
    if ( exists $$hyp_data_comp_act->{'Win32_ComputerSystem'} ) {
      $host_memorySize = get_hyp_val( 'Win32_ComputerSystem', 'TotalPhysicalMemory', $hyp_data_comp_act );    # in Bytes
    }
    else {
      $host_memorySize = get_hyp_val( 'Win32_OperatingSystem', 'TotalVisibleMemorySize', $hyp_data_comp_act );    # in kB
      $host_memorySize = 0 if !isdigit($host_memorySize);
      $host_memorySize *= 1024;                                                                                   # to be Bytes
    }

    $vm_TotalPhysicalMemory[0] = $host_memorySize;

    $vm_Frequency_PerfTime[0] = $UnDeF;
    if ( exists $$hyp_data_comp_act->{'Win32_PerfRawData_HvStats_HyperVHypervisorLogicalProcessor'} ) {
      $vm_Frequency_PerfTime[0] = get_hyp_val( 'Win32_PerfRawData_HvStats_HyperVHypervisorLogicalProcessor', 'Frequency_PerfTime', $hyp_data_comp_act, '_Total' );
    }
    if ( $vm_Frequency_PerfTime[0] eq $UnDeF ) {
      if ( exists $$hyp_data_comp_act->{'Win32_PerfRawData_PerfOS_Processor'} ) {
        $vm_Frequency_PerfTime[0] = get_hyp_val( 'Win32_PerfRawData_PerfOS_Processor', 'Frequency_PerfTime', $hyp_data_comp_act, '_Total' );
      }
      else {
        # not sufficient data
        print_hyperv_debug("1471 no data for Win32_PerfRawData_PerfOS_Processor - exiting\n");
        error("1471 no data for Win32_PerfRawData_PerfOS_Processor - exiting\n");
        return;
      }
    }
    $vm_Frequency_PerfTime[0] = 1 if !isdigit( $vm_Frequency_PerfTime[0] );

    # print "\$vm_Frequency_PerfTime[0] $vm_Frequency_PerfTime[0]\n";
    my $host_parent = "";

    $line = $h_name . "," . $h_name . "," . $o_uuid;

    chomp($line);

    if ( $line =~ m/Error:/ || $line =~ m/Permission denied/ || $line =~ m/undefined/ ) {
      error( "problem connecting to $vm_host : $line " . __FILE__ . ":" . __LINE__ );
      next;
    }

    if ( $line !~ ".*,.*,.*" ) {

      # it must look like : DESKTOP-ISG7U4Q,DESKTOP-ISG7U4Q,3F757480-66A4-11E5-9D28-5065F325A3E5
      next;
    }

    if ( $line =~ /No results were found/ ) {
      print "$host does not contain any managed system\n" if $DEBUG;
      return 0;
    }
    ( $managedname, $model, $serial ) = split( /,/, $line );

    print "managed system : $host:$managedname (serial : $serial) \n" if $DEBUG;

    #rename_server( $host, $managedname, $serial );    # this is for hyper_v servers, serial is uuid

    # create sym link serial for recognizing of renamed managed systems - not for WINDOWS
    # it must be here due to skipping some server (exclude, not running util collection) and saving cfg
    if ( !-d "$wrkdir" ) {
      print "mkdir          : $host:$managedname $wrkdir\n" if $DEBUG;
      LoadDataModuleHyperV::touch("$host:$managedname $wrkdir");
      mkdir( "$wrkdir", 0755 ) || error( " Cannot mkdir $wrkdir: $!" . __FILE__ . ":" . __LINE__ ) && next;
    }

    #
    ### starting here : change of $wrkdir (only 1st time)
    #
    if ( $wrkdir !~ /windows$/ ) {
      $wrkdir = "$wrkdir/windows";
    }
    $wrkdir_windows = $wrkdir;

    if ( !-d "$wrkdir" ) {
      print "mkdir          : $host:$managedname $wrkdir\n" if $DEBUG;
      LoadDataModuleHyperV::touch("$host:$managedname $wrkdir");
      mkdir( "$wrkdir", 0755 ) || error( " Cannot mkdir $wrkdir: $!" . __FILE__ . ":" . __LINE__ ) && next;
    }

    $wrkdir = "$wrkdir/$domain";

    if ( !-d "$wrkdir" ) {
      print "mkdir          : $host:$managedname $wrkdir\n" if $DEBUG;
      LoadDataModuleHyperV::touch("$host:$managedname $wrkdir");
      mkdir( "$wrkdir", 0755 ) || error( " Cannot mkdir $wrkdir: $!" . __FILE__ . ":" . __LINE__ ) && next;
    }

    # new system all VMs in domain dir
    # it also holds file uuid->name of VMs

    if ( !-d "$wrkdir/$all_hyperv_VMs" ) {
      print "mkdir          : $host: $wrkdir/$all_hyperv_VMs\n" if $DEBUG;
      LoadDataModuleHyperV::touch("$wrkdir/$all_hyperv_VMs");
      mkdir( "$wrkdir/$all_hyperv_VMs", 0755 ) || error( " Cannot mkdir $wrkdir/$all_hyperv_VMs: $!" . __FILE__ . ":" . __LINE__ ) && next;
    }

    if ( !-d "$wrkdir/$managedname" ) {
      print "mkdir          : $host:$managedname $wrkdir/$managedname\n" if $DEBUG;
      LoadDataModuleHyperV::touch("$wrkdir/$managedname");
      mkdir( "$wrkdir/$managedname", 0755 ) || error( " Cannot mkdir $wrkdir/$managedname: $!" . __FILE__ . ":" . __LINE__ ) && next;
    }

    #    if ( !-l "$wrkdir/$serial" ) {    # uuid only
    #      print "ln -s          : $host:$managedname $wrkdir/$managedname $wrkdir/$serial \n" if $DEBUG;
    #      LoadDataModuleHyperV::touch("$wrkdir/$serial");
    #      symlink( "$wrkdir/$managedname", "$wrkdir/$serial" ) || error( " Cannot ln -s $wrkdir/$managedname $wrkdir/$serial: $!" . __FILE__ . ":" . __LINE__ ) && next;
    #    }

    # tohle asi nhradime jen touchnutim  jmena hosta, to je jen smluvene jmeno na posilani dat z windows
    #
    #if ( !-d "$wrkdir/$managedname/$host" ) {
    #  print "mkdir          : $host:$managedname $wrkdir/$managedname/$host\n" if $DEBUG;
    #  LoadDataModuleHyperV::touch("$wrkdir/$managedname/$host");
    #  mkdir( "$wrkdir/$managedname/$host", 0755 ) || error( " Cannot mkdir $wrkdir/$managedname/$host: $!" . __FILE__ . ":" . __LINE__ ) && next;
    #}

    $managed_ok = 1;
    @pool_list  = "";    # clean pool_list for each managed name
    if ( $managed_systems_exclude ne '' ) {
      @m_excl = split( /:/, $managed_systems_exclude );
      foreach $managedname_exl (@m_excl) {
        chomp($managedname_exl);
        if ( $managedname =~ m/^$managedname_exl$/ ) {
          $managed_ok = 0;
        }
      }
    }
    if ( $managed_ok == 0 ) {
      print "managed system : $host:$managedname is excluded in load.sh, continuing with the others ...\n" if $DEBUG;
      next;
    }
    my $vm_names = "";
    if ( exists $$hyp_data_comp_act->{'Msvm_ComputerSystem'} ) {
      $vm_names = get_hyp_val( 'Msvm_ComputerSystem', 'ElementName', $hyp_data_comp_act, 'Virtual Machine' );

      # print "1944 \$vm_names $vm_names\n";
      if ( $vm_names eq $UnDeF ) {    # maybe another language ?
        $vm_names = get_hyp_val( 'Msvm_ComputerSystem', 'ElementName', $hyp_data_comp_act, 'Виртуальная машина' );

        # print "1947 \$vm_names $vm_names\n";
      }
      if ( $vm_names eq $UnDeF ) {    # French Virtual Machine
        $vm_names = get_hyp_val( 'Msvm_ComputerSystem', 'ElementName', $hyp_data_comp_act, 'Ordinateur virtuel' );

        # print "1947 \$vm_names $vm_names\n";
      }

      print_hyperv_debug("---------- \$vm_names $vm_names\n") if $DEBUG == 2;
    }

    @vm_view = split( ",", $vm_names );

    my @lpar_trans        = ();    # original array
    my @lpar_trans_new    = ();    # if there is new VM
    my @lpar_trans_renew  = ();    # if there is change in orig arr
    my $lpar_trans_change = 0;

    # lpar_trans.txt keeps names of all VMS that anytime has/had been registered under this server
    my $lpar_trans_name = "$wrkdir/$managedname/lpar_trans.txt";
    if ( -f "$lpar_trans_name" ) {
      open my $FH, "$lpar_trans_name" or error( "can't open $lpar_trans_name: $!" . __FILE__ . ":" . __LINE__ ) && return 0;
      @lpar_trans = <$FH>;
      close $FH;
    }

    # new system of tracking VM presence in hostsystem
    # for every hostsystem ( resourcepool too)
    # - open VM hosting file
    # - track every VM - active and also non-active
    # - save Vm hosting file
    # during cycle hold hosting info in an array

    my @hosting_arr = ();
    VM_hosting_read( \@hosting_arr, "$wrkdir/$managedname/VM_hosting.vmh" );

    %vm_name_uuid      = ();
    %vm_uuid_mac       = ();
    %vm_name_powerstat = ();
    %vm_uuid_mem       = ();
    %vm_name_vcpu      = ();
    my @cpu_cfg  = ();
    my @disk_cfg = ();
    my @vhd_list = ();

    foreach my $each_vm (@vm_view) {

      next if $each_vm eq $UnDeF;

      #  new lpar will be added to lpar_trans.txt
      my $test_atom    = "ITEM=ElementName=" . "\"" . $each_vm . "\"";
      my $each_vm_uuid = get_hyp_val( 'Msvm_ComputerSystem', 'Name', $hyp_data_comp_act, $test_atom );

      # print "1877 \$each_vm_uuid $each_vm_uuid \$each_vm $each_vm\n";
      if ( index( $each_vm_uuid, "," ) != -1 ) {
        ( $each_vm_uuid, undef ) = split( ",", $each_vm_uuid );    # in case 2 or more uuids returned
      }
      my $each_vm_name = $each_vm;
      my $each_vm_url  = $each_vm_name;

      if ( !defined $each_vm_uuid || $each_vm_uuid eq "" || !uuid_check($each_vm_uuid) ) {
        error( "Bad VM uuid in $wrkdir/$managedname: $!" . __FILE__ . ":" . __LINE__ ) && next;
      }
      if ( !defined $each_vm_name || $each_vm_name eq "" ) {
        error( "Bad VM name in $wrkdir/$managedname: $!" . __FILE__ . ":" . __LINE__ ) && next;
      }

      # for new system, do not test possible uuid collision
      # prepare url name for install-html.sh
      $each_vm_url =~ s/([^A-Za-z0-9\+-_])/sprintf("%%%02X", ord($1))/seg;
      my $new_item = "$each_vm_name" . "," . "$each_vm_url";
      if ( !defined $vm_uuid_names{$each_vm_uuid} || $vm_uuid_names{$each_vm_uuid} ne $new_item ) {
        $vm_uuid_names{$each_vm_uuid} = $new_item;
        $change_vm_uuid_names++;
      }

      VM_hosting_update( \@hosting_arr, $each_vm_uuid, $command_unix );

      #  print "\@hosting_arr @hosting_arr\n";

      my $line_test = $each_vm_uuid;    # do not know if with or without name

      if ( ( defined $line_test ) && ( !uuid_check($line_test) ) ) {
        if ( defined $each_vm_name ) {
          error( "Bad VM uuid for VM:$each_vm_name in $wrkdir/$managedname: $!" . __FILE__ . ":" . __LINE__ ) && next;
        }
        else {
          error( "Bad VM uuid, undef Name in $wrkdir/$managedname: $!" . __FILE__ . ":" . __LINE__ ) && next;
        }
      }
      if ( !defined $line_test ) {
        if ( defined $each_vm_name ) {
          error( "Undefined VM uuid for VM:$each_vm_name in $wrkdir/$managedname: $!" . __FILE__ . ":" . __LINE__ ) && next;
        }
        else {
          error( "Undefined VM uuid nor Name in $wrkdir/$managedname: $!" . __FILE__ . ":" . __LINE__ ) && next;
        }
      }
      if ( !defined $each_vm_name ) {
        error( "Undefined VM name in $wrkdir/$managedname: $!" . __FILE__ . ":" . __LINE__ ) && next;
      }
      my $vm_uuid  = $line_test;
      my $line_upd = $line_test . "," . $each_vm_name;

      # there is no moref in hyperv
      my $vm_mo_ref_id = 'moref_' . $each_vm_name;
      if ( !defined $vm_mo_ref_id ) {
        error( "VM change ID   : not defined mo_ref for VM $each_vm_name " . __FILE__ . ":" . __LINE__ );
        next;
      }
      my $match = grep {/$line_test/} @lpar_trans;
      my ($arr_index) = grep { $lpar_trans[$_] =~ $line_test } 0 .. $#lpar_trans;
      if ( $match < 1 ) {
        push @lpar_trans_new, "$line_upd" . "," . $vm_mo_ref_id . "\n";
        print "VM change ID   : new registration in lpar_trans for $line_upd,$vm_mo_ref_id\n";
      }
      else {
        # print "VM test ID     : VM found index $arr_index in arr lpar_trans\n";
        if ( !defined $lpar_trans[$arr_index] ) {
          error( "VM change ID   : not defined $arr_index in arr lpar_trans, if persist, contact lpar2rrd support " . __FILE__ . ":" . __LINE__ );
        }
        else {
          my $lpar_trans_item = $lpar_trans[$arr_index];
          chomp $lpar_trans_item;
          ( my $uuid, undef, my $old_mo_ref_id ) = split( ",", $lpar_trans_item );
          if ( !defined $old_mo_ref_id ) {
            $old_mo_ref_id = "undefined";
          }
          if ( ( $old_mo_ref_id eq "undefined" ) || ( $old_mo_ref_id ne $vm_mo_ref_id ) ) {
            print "VM change ID   : VM $lpar_trans[$arr_index] changed (or had not set) mo_ref_Id to $vm_mo_ref_id\n";

            # remove all VM-uuid items
            @lpar_trans_renew = grep { $_ !~ $uuid } @lpar_trans;
            @lpar_trans       = @lpar_trans_renew;
            push @lpar_trans, "$line_upd" . "," . $vm_mo_ref_id . "\n";
            $lpar_trans_change++;
          }
        }
      }

      $vm_name_uuid{"$each_vm_name"} = "$line_test";

      my $powerstate = get_hyp_val( 'Msvm_ComputerSystem', 'EnabledState', $hyp_data_comp_act, $test_atom );
      if ( exists $enabledstate{$powerstate} ) {
        $powerstate = $enabledstate{$powerstate};    # from system table
      }
      else {
        $powerstate = "UNKNOWN";
      }
      $vm_name_powerstat{$each_vm} = $powerstate;

      # print "2106 ".$$hyp_data_comp_act->{'Msvm_ComputerSystem'}[0]."\n";
      if ( exists $$hyp_data_comp_act->{'Msvm_ComputerSystem'}
        && ( index( $$hyp_data_comp_act->{'Msvm_ComputerSystem'}[0], 'OnTimeInMilliseconds' ) > -1 ) )
      {

        my $OnTimeInMilliseconds = get_hyp_val( 'Msvm_ComputerSystem', 'OnTimeInMilliseconds', $hyp_data_comp_act, $test_atom );

        # print "2111 \$OnTimeInMilliseconds $OnTimeInMilliseconds\n";
        if ( defined $OnTimeInMilliseconds && $OnTimeInMilliseconds ne "" ) {
          $OnTimeInMilliseconds = int( $OnTimeInMilliseconds / 1000 );    # to be seconds
          my $days  = int( $OnTimeInMilliseconds / 86400 );
          my $hours = ( $OnTimeInMilliseconds / 3600 ) % 24;
          my $mins  = ( $OnTimeInMilliseconds / 60 ) % 60;
          my $secs  = ( $OnTimeInMilliseconds % 60 );
          $powerstate = "$days days " . sprintf( "%02d:%02d:%02d", $hours, $mins, $secs ) . "\n";
        }
      }

      # CLASS: Msvm_ProcessorSettingData
      # InstanceID|Limit|Reservation|VirtualQuantity|Weight
      # Microsoft:09672167-2837-4FFE-97D7-8163745E8AB3\b637f346-6a0e-4dec-af52-bd70cb80a21d\0|100000|0|1|100

      my $max_limit = "U";
      $max_limit = get_hyp_val( 'Msvm_ProcessorSettingData', 'Limit', $hyp_data_comp_act, $each_vm_uuid );
      if ( $max_limit ne $UnDeF ) {
        if ( index( $max_limit, "," ) != -1 ) {
          error( "more data in \$max_limit $max_limit " . __FILE__ . ":" . __LINE__ );
          ( $max_limit, undef ) = split( ",", $max_limit );
        }
        $max_limit /= 1000;
      }

      my $numCpu = get_hyp_val( 'Msvm_ProcessorSettingData', 'VirtualQuantity', $hyp_data_comp_act, $each_vm_uuid );
      $vm_name_vcpu{$each_vm_name} = $numCpu;
      print_hyperv_debug("1799 \$each_vm_uuid $each_vm_uuid \$numCpu $numCpu\n") if $DEBUG == 2;

      my $cpuAllocation_reservation = get_hyp_val( 'Msvm_ProcessorSettingData', 'Reservation', $hyp_data_comp_act, $each_vm_uuid );
      $cpuAllocation_reservation /= 1000 if $cpuAllocation_reservation ne $UnDeF;

      my $cpu_weight = get_hyp_val( 'Msvm_ProcessorSettingData', 'Weight', $hyp_data_comp_act, $each_vm_uuid );

      # looking for MAC addr -> PermanentAddress
      # CLASS: Msvm_SyntheticEthernetPort
      # CreationClassName|DeviceID|Name|PermanentAddress|SystemCreationClassName|SystemName
      # Msvm_SyntheticEthernetPort|Microsoft:DD639889-6BC7-451E-AF48-FBAD2418F7E6|Ethernet Port|00155D01BB01|Msvm_ComputerSystem|3138F59F-11AD-46FB-951C-9C147C98896C

      $vm_uuid_mac{$each_vm_uuid} = $UnDeF;

      if ( exists $$hyp_data_comp_act->{'Msvm_SyntheticEthernetPort'} ) {
        $vm_uuid_mac{$each_vm_uuid} = get_hyp_val( 'Msvm_SyntheticEthernetPort', 'PermanentAddress', $hyp_data_comp_act, $each_vm_uuid );
        $vm_uuid_mac{$each_vm_uuid} =~ s/,/ /g;    # if there are more addresses
      }

      my $dynamic_mem = get_hyp_val( 'Msvm_MemorySettingData', 'DynamicMemoryEnabled', $hyp_data_comp_act, $each_vm_uuid );

      my $heartbeat = $UnDeF;
      if ( exists $$hyp_data_comp_act->{'Msvm_HeartbeatComponent'} ) {
        $heartbeat = get_hyp_val( 'Msvm_HeartbeatComponent', 'StatusDescriptions', $hyp_data_comp_act, $each_vm_uuid );
      }
      my $timesync = $UnDeF;
      if ( exists $$hyp_data_comp_act->{'Msvm_TimeSyncComponent'} ) {
        $timesync = get_hyp_val( 'Msvm_TimeSyncComponent', 'StatusDescriptions', $hyp_data_comp_act, $each_vm_uuid );
      }
      my $vss_status = $UnDeF;
      if ( exists $$hyp_data_comp_act->{'Msvm_VssComponent'} ) {
        $vss_status = get_hyp_val( 'Msvm_VssComponent', 'StatusDescriptions', $hyp_data_comp_act, $each_vm_uuid );
      }
      $heartbeat  =~ s/,/ /g;
      $timesync   =~ s/,/ /g;
      $vss_status =~ s/,/ /g;

      my $guestFullName      = "";
      my $toolsRunningStatus = "";

      my $line = $each_vm_name . "," . $numCpu . "," . $cpuAllocation_reservation . "," . $max_limit . "," . $cpu_weight . "," . $powerstate . "," . $heartbeat . "," . $vm_uuid_mac{$each_vm_uuid} . "," . $dynamic_mem . "," . $timesync . "," . $vss_status . "," . "comment_$each_vm_uuid" . "\n";
      push @cpu_cfg, $line;

      # CLASS: Msvm_Memory
      # "SystemName","BlockSize","NumberOfBlocks","Name"
      # "71ACA269-B7E0-42F7-BCB6-558E042B0CCB","1048576","8192","71ACA269-B7E0-42F7-BCB6-558E042B0CCB"
      # "71ACA269-B7E0-42F7-BCB6-558E042B0CCB","1048576","4096","71ACA269-B7E0-42F7-BCB6-558E042B0CCB"
      # "71ACA269-B7E0-42F7-BCB6-558E042B0CCB","1048576","4096","71ACA269-B7E0-42F7-BCB6-558E042B0CCB"
      # sometimes can be more than 1 line , in this case choose the biggest number

      my $BlockSize      = get_hyp_val( 'Msvm_Memory', 'BlockSize',      $hyp_data_comp_act, $each_vm_uuid );
      my $NumberOfBlocks = get_hyp_val( 'Msvm_Memory', 'NumberOfBlocks', $hyp_data_comp_act, $each_vm_uuid );
      if ( index( $BlockSize, "," ) ne -1 ) {
        my $max;
        my $index     = 0;
        my $max_index = 0;
        my @array     = split( ",", $NumberOfBlocks );
        for (@array) {
          if ( !$max || $_ > $max ) {
            $max       = $_;
            $max_index = $index;
          }
          $index++;
        }

        # print "max: $max index:$max_index $array[$max_index]\n";
        $NumberOfBlocks = $max;
        $BlockSize      = ( split( ",", $BlockSize ) )[$max_index];
        print "1907 \$NumberOfBlocks $NumberOfBlocks \$BlockSize $BlockSize \$each_vm_uuid $each_vm_uuid\n" if $DEBUG == 2;
      }
      my $storage_com = 0;
      if ( $BlockSize ne $UnDeF && $NumberOfBlocks ne $UnDeF ) {
        $storage_com = $BlockSize * $NumberOfBlocks / 1024 / 1024;
      }
      $vm_uuid_mem{$each_vm_uuid} = $storage_com;
      my $storage_total = $storage_com;
      $line = "$each_vm_name,$storage_total,$storage_com\n";
      push @disk_cfg, $line;

      # prepare hash for easy VM pick up (resourcepool)
      $vm_id_path{"$vm_mo_ref_id"} = "$wrkdir/$h_name/$vm_uuid.rrm";

      # print "filling vm_id_path{\"$vm_mo_ref_id\"} = \"$wrkdir/$h_name/$host/$vm_uuid.rrm\n";

      my $vhd_path = get_hyp_val( 'Msvm_StorageAllocationSettingData', 'HostResource', $hyp_data_comp_act, $each_vm_uuid );
      print_hyperv_debug("1780 hyp2rrd.pl for \$each_vm_uuid $each_vm_uuid \$vhd_path $vhd_path\n") if $DEBUG == 2;

      # my @vhd_path_array = split( /\)/,$vhd_path); # do not know why this )
      my @vhd_path_array = split( /,/, $vhd_path );

      #                                   HostResource                                    InstanceID
      # raw line example: Hard Disk Image|(E:\Export\XoruX\Virtual Hard Disks\XoruX.vhdx)|Microsoft:143E4B15-1E45-4D7B-B352-ECE54359A778\83F8638B-8DCA-4152-9EDA-2CA8B33039B4\0\0\L
      my $instance_vhd = get_hyp_val( 'Msvm_StorageAllocationSettingData', 'InstanceId', $hyp_data_comp_act, $each_vm_uuid );
      print_hyperv_debug("1787 hyp2rrd.pl for \$each_vm_uuid $each_vm_uuid \$instance_vhd $instance_vhd \@vhd_path_array @vhd_path_array\n") if $DEBUG == 2;
      my @instance_vhd_array = split /,/, $instance_vhd;

      # can be more than 1 e.g.
      # (C:\Users\netadmin\Desktop\XP\Virtual Hard Disks\WinXP.vhdx)   (C:\Windows\system32\vmguest.iso)

      my $vhd_inx = 0;

      foreach (@vhd_path_array) {
        my $vhd_path_line = $_;

        # $vhd_path_line .= ")";
        $vhd_path_line =~ s/^\s+//;
        $vhd_path_line =~ s/^,//;     # second and other atoms have it

        # find controller type
        my $class      = 'Msvm_IDEController';
        my $i          = 0;
        my $controller = "";
        my $location   = " ";
        print_hyperv_debug("1804 go for IDEController\n") if $DEBUG == 2;

        # Microsoft:83F8638B-8DCA-4152-9EDA-2CA8B33039B4\0,IDE Controller 0,5,37,3138F59F-11AD-46FB-951C-9C147C98896C,1525161659
        while ( defined $$hyp_data_comp_act->{$class}[$i] ) {
          my $hyp_line = $$hyp_data_comp_act->{$class}[$i];
          $hyp_line =~ s/\"//g;
          $i++;
          next                                              if $hyp_line !~ "$each_vm_uuid";
          print_hyperv_debug("1809 hyp2rrd.pl $hyp_line\n") if $DEBUG == 2;
          my @item_arr = split( /,/, $hyp_line );
          my $item_ide = $item_arr[0];
          $item_ide = ( split( /:/, $item_ide ) )[1];
          print_hyperv_debug("1817 ,,,,,,,,,,,,,,,,, \$instance_vhd_array[$vhd_inx] $instance_vhd_array[$vhd_inx] \$item_ide $item_ide\n") if $DEBUG == 2;

          if ( $instance_vhd_array[$vhd_inx] =~ /\Q$item_ide\E/ ) {
            $controller = $item_arr[1];
            $location   = ( split /\\/, $instance_vhd_array[$vhd_inx] )[-2];
          }
        }

        # if not IDE controller try SCSI
        if ( $controller eq "" ) {
          my $class = 'Msvm_SCSIProtocolController';
          my $i     = 0;
          print_hyperv_debug("1829 go for SCSI Controller\n") if $DEBUG == 2;

          # "Microsoft:C3A13785-9C34-449F-AFDF-3F5174FFB28B\0","SCSI Controller","5","3138F59F-11AD-46FB-951C-9C147C98896C,1525161659"
          while ( defined $$hyp_data_comp_act->{$class}[$i] ) {
            my $hyp_line = $$hyp_data_comp_act->{$class}[$i];
            $hyp_line =~ s/\"//g;
            $i++;
            next                                              if $hyp_line !~ "$each_vm_uuid";
            print_hyperv_debug("1835 hyp2rrd.pl $hyp_line\n") if $DEBUG == 2;
            my @item_arr = split( /,/, $hyp_line );
            my $item_ide = $item_arr[0];
            $item_ide = ( split( /:/, $item_ide ) )[1];
            print_hyperv_debug("1839 ,,,,,,,,,,,,,,,,, \$instance_vhd_array[$vhd_inx] $instance_vhd_array[$vhd_inx] \$item_ide $item_ide\n") if $DEBUG == 2;

            if ( $instance_vhd_array[$vhd_inx] =~ /\Q$item_ide\E/ ) {
              $controller = $item_arr[1];
              $location   = ( split /\\/, $instance_vhd_array[$vhd_inx] )[-2];
            }
          }
        }

        print_hyperv_debug("1846 hyp2rrd.pl $instance_vhd_array[$vhd_inx]\n") if $DEBUG == 2;
        $line = $each_vm_name . "," . $controller . "," . $location . "," . $vhd_path_line . "\n";
        push @vhd_list, $line;
        $vhd_inx++;
      }

    }

    # for new system, if change in VM then save
    if ($change_vm_uuid_names) {
      open my $FH, '>:encoding(UTF-8)', "$vm_uuid_names_file" or error( "can't open $vm_uuid_names_file: $!" . __FILE__ . ":" . __LINE__ ) && return 0;
      binmode( $FH, ":utf8" );
      my ( $k, $v );

      # Write key/value pairs from %vm_uuid_names to file, joined by ':'
      while ( ( $k, $v ) = each %vm_uuid_names ) {
        print $FH "$k" . "," . "$v\n";

        # print "2179 vm_uuid_names written: $k" . "," . "$v\n";
      }
      close $FH;
      print "all_vm_uuid    : changed content has been written\n";
    }

    VM_hosting_write( \@hosting_arr, "$wrkdir/$managedname/VM_hosting.vmh", $command_unix );

    # there can be new VM, or VM can possibly change ID

    if ($lpar_trans_change) {    # changed Id > rewrite file

      open my $FH, ">$lpar_trans_name" or error( "can't open $lpar_trans_name: $!" . __FILE__ . ":" . __LINE__ ) && return 0;
      foreach my $new_line (@lpar_trans) {
        chomp($new_line);
        print $FH $new_line . "\n";
      }
      close $FH;
    }

    if ( @lpar_trans_new > 0 ) {    # just add new VM
      open my $FH, ">>$lpar_trans_name" or error( "can't open $lpar_trans_name: $!" . __FILE__ . ":" . __LINE__ ) && return 0;
      foreach my $new_line (@lpar_trans_new) {
        chomp($new_line);
        print $FH $new_line . "\n";
      }
      close $FH;
    }

    my $cpu_cores = $UnDeF;
    if ( exists $$hyp_data_comp_act->{'Win32_PerfRawData_HvStats_HyperVHypervisorLogicalProcessor'} ) {
      $cpu_cores = get_hyp_val( 'Win32_PerfRawData_HvStats_HyperVHypervisorLogicalProcessor', 'Name', $hyp_data_comp_act );    # example Hv LP 3,Hv LP 2,Hv LP 1,Hv LP 0,_Total
    }
    my $c_cores = $cpu_cores =~ tr/,//;                                                                                        # count number of commas
                                                                                                                               # print  "1959 \$cpu_cores $cpu_cores\n";

    # in case of standalone windows
    if ( $cpu_cores eq $UnDeF ) {
      if ( exists $$hyp_data_comp_act->{'Win32_ComputerSystem'} ) {
        $c_cores = get_hyp_val( 'Win32_ComputerSystem', 'NumberOfLogicalProcessors', $hyp_data_comp_act );    #Logical
      }
      else {
        # $c_cores = get_hyp_val( 'Win32_Processor', 'NumberOfCores', $hyp_data_comp_act );
        $c_cores = get_hyp_val( 'Win32_Processor', 'NumberOfLogicalProcessors', $hyp_data_comp_act );

        #  print "2766 \$vm_vCPU[0] $vm_vCPU[0] standalone windows\n";
      }    # for W2008 can be like 8,8
      if ( index( $c_cores, "," ) > -1 ) {
        ( $c_cores, undef ) = split( ",", $c_cores );
      }
    }

    my $res_ret = FormatResults(@cpu_cfg);

    # print STDERR "1714 hyp2rrd.pl \$res_ret $res_ret \@cpu_cfg @cpu_cfg\n";

    # print VMs info if there are some VMs
    my $cpu_file = "$wrkdir/$managedname/cpu.html";

    #    if (scalar @cpu_cfg) {
    open my $FHcpu, '>:encoding(UTF-8)', "$cpu_file" or error( "can't open $cpu_file: $!" . __FILE__ . ":" . __LINE__ ) && return 0;
    binmode( $FHcpu, ":utf8" );

    #            <TH align=\"center\" class=\"sortable\" valign=\"center\">&nbsp;&nbsp;&nbsp;OS&nbsp;&nbsp;&nbsp;</TH>
    #            <TH align=\"center\" class=\"sortable\" valign=\"center\">&nbsp;&nbsp;&nbsp;toolsStatus&nbsp;&nbsp;&nbsp;</TH>

    print $FHcpu "<BR><CENTER><TABLE class=\"tabconfig tablesorter\"><!cores:$c_cores>\n";    # max CPU cores hidden here
    print $FHcpu "<thead><TR> <TH class=\"sortable\" valign=\"center\">VM&nbsp;&nbsp;&nbsp;</TH>
		  	<TH align=\"center\" class=\"sortable\" valign=\"center\">&nbsp;&nbsp;&nbsp;vCPU&nbsp;&nbsp;</TH>
			  <TH align=\"center\" class=\"sortable\" valign=\"center\">&nbsp;&nbsp;&nbsp;Reservation %&nbsp;&nbsp;</TH>
  			<TH align=\"center\" class=\"sortable\" valign=\"center\">&nbsp;&nbsp;&nbsp;Max Limit %&nbsp;&nbsp;</TH>
	  		<TH align=\"center\" class=\"sortable\" valign=\"center\">&nbsp;&nbsp;&nbsp;Weight (0-10000)&nbsp;&nbsp;</TH>
		  	<TH align=\"center\" class=\"sortable\" valign=\"center\">&nbsp;&nbsp;&nbsp;EnabledState or Uptime&nbsp;&nbsp;</TH>
        <TH align=\"center\" class=\"sortable\" valign=\"center\">&nbsp;&nbsp;&nbsp;HeartBeat&nbsp;&nbsp;</TH>
  			<TH align=\"center\" class=\"sortable\" valign=\"center\">&nbsp;&nbsp;&nbsp;MAC addr&nbsp;&nbsp;</TH>
        <TH align=\"center\" class=\"sortable\" valign=\"center\">&nbsp;&nbsp;&nbsp;DynamicMem&nbsp;&nbsp;</TH>
		  	<TH align=\"center\" class=\"sortable\" valign=\"center\">&nbsp;&nbsp;&nbsp;Time Sync&nbsp;&nbsp;</TH>
        <TH align=\"center\" class=\"sortable\" valign=\"center\">&nbsp;&nbsp;&nbsp;Vss status&nbsp;&nbsp;</TH>
  			</TR></thead><tbody>\n";
    if ( scalar @cpu_cfg ) {
      print $FHcpu "$res_ret";
    }
    print $FHcpu "</tbody></TABLE></CENTER><BR><BR>\n";
    close $FHcpu;

    #    }
    #    else {
    #      unlink $cpu_file if (-f $cpu_file);
    #    }

    # CLASS: Win32_NetworkAdapterConfiguration where IPEnabled='True'
    # "Description","DHCPEnabled","DHCPServer","DNSHostName","IPAddress","MACAddress","ServiceName","SettingID"
    # "Microsoft Failover Cluster Virtual Adapter","False",,"hvnode01","169.254.2.246 fe80::fd1f:7e9e:5894:87e","02:66:3A:56:2D:D5","Netft","{06DF9D69-2654-44C3-B5D3-DE25FD09D96F}"
    # "Hyper-V Virtual Ethernet Adapter","True","10.22.88.10","hvnode01","10.22.88.102 10.22.88.100 fe80::70df:4be7:df12:2595","00:50:56:9C:79:E0","VMSMP","{510E9C58-FEDD-436C-A3ED-001433970ABC}"
    if ( exists $$hyp_data_comp_act->{"Win32_NetworkAdapterConfiguration where IPEnabled='True'"} ) {

      # print Dumper $$hyp_data_comp_act->{"Win32_NetworkAdapterConfiguration where IPEnabled='True'"};
      # print "2059 Win32_NetworkAdapterConfiguration\n";
      # problem: can be adapter without MAC address, must be addedd for following script
      # "WireGuard Tunnel #2","False",,"DESKTOP-O79DK45","10.11.12.101",,"wintun","{41F8ADFF-E68B-68DA-E41A-B233337FD3BF}"
      # there can be same Mac addresses ?!
      #my %used_macaddr = ();
      my $i = 0;
      @cpu_cfg = ();

      while ( defined $$hyp_data_comp_act->{"Win32_NetworkAdapterConfiguration where IPEnabled='True'"}[$i] ) {
        my $hyp_line = $$hyp_data_comp_act->{"Win32_NetworkAdapterConfiguration where IPEnabled='True'"}[$i];

        # print "2284 \$hyp_line $hyp_line\n";
        ( my $at1, my $at2, my $at3, my $at4, my $at5, my $at6, my $at7, my $at8, undef ) = split( ",", $hyp_line );
        if ( $at1 eq "\"Description\"" ) {
          $i++;
          next;
        }
        $at6 = "\"not defined\"" if $at6 eq "";

        # print "2390 $at1,$at2,$at3,$at4,$at5,$at6,$at7,$at8\n";
        push @cpu_cfg, "$at1,$at3,$at4,$at5,$at6,$at7,$at8\n";

        #        if ($at6 eq "") {
        #          $at6 = "\"MacAddress$i\"";
        #          $$hyp_data_comp_act->{"Win32_NetworkAdapterConfiguration where IPEnabled='True'"}[$i] = "$at1,$at2,$at3,$at4,$at5,\"MacAddress$i\",$at7";
        #          # print "2288 \$hyp_line $hyp_line\n";
        #        }
        #        if (exists $used_macaddr{$at6}) {
        #          print "same mac addr  : $at6\n";
        #          $at6 =~ s/\"$/x$i\"/;
        #          $$hyp_data_comp_act->{"Win32_NetworkAdapterConfiguration where IPEnabled='True'"}[$i] = "$at1,$at2,$at3,$at4,$at5,$at6,$at7";
        #        }
        #        $used_macaddr{$at6} = 1;
        $i++;
      }

      #      # print Dumper $$hyp_data_comp_act->{"Win32_NetworkAdapterConfiguration where IPEnabled='True'"};
      #      # problem: if there are more adapters, test of MACAddress, how many of them
      #      my $mac_adrs  = get_hyp_val( "Win32_NetworkAdapterConfiguration where IPEnabled='True'", 'MACAddress', $hyp_data_comp_act );
      #      my @mac_adrs_list = split(",",$mac_adrs);
      #      # print "2283 \$mac_adrs $mac_adrs\n";
      #      @cpu_cfg = ();
      #      foreach my $MACAddress (@mac_adrs_list) {
      #        my $adapter     = get_hyp_val( "Win32_NetworkAdapterConfiguration where IPEnabled='True'", 'Description', $hyp_data_comp_act, $MACAddress );
      #        my $DHCPServer  = get_hyp_val( "Win32_NetworkAdapterConfiguration where IPEnabled='True'", 'DHCPServer', $hyp_data_comp_act, $MACAddress );
      #        my $DNSHostName = get_hyp_val( "Win32_NetworkAdapterConfiguration where IPEnabled='True'", 'DNSHostName', $hyp_data_comp_act, $MACAddress );
      #        my $IPAddress   = get_hyp_val( "Win32_NetworkAdapterConfiguration where IPEnabled='True'", 'IPAddress', $hyp_data_comp_act, $MACAddress );
      #        # my $MACAddress  = get_hyp_val( "Win32_NetworkAdapterConfiguration where IPEnabled='True'", 'MACAddress', $hyp_data_comp_act );
      #        print_hyperv_debug("2065 \$MACAddress $MACAddress \$adapter $adapter\n") if $DEBUG == 2;
      #        my $ServiceName = get_hyp_val( "Win32_NetworkAdapterConfiguration where IPEnabled='True'", 'ServiceName', $hyp_data_comp_act, $MACAddress );
      #        my $SettingID   = get_hyp_val( "Win32_NetworkAdapterConfiguration where IPEnabled='True'", 'SettingID', $hyp_data_comp_act, $MACAddress );
      #
      #        my $line = $adapter .",". $DHCPServer .",". $DNSHostName .",". $IPAddress .",". $MACAddress .",". $ServiceName .",". $SettingID . "\n";
      #        push @cpu_cfg,$line;
      #      }
      $res_ret = FormatResults(@cpu_cfg);
      my $file_name = "$wrkdir/$managedname/NetworkAdapterConfiguration.html";
      open my $FHnet, '>:encoding(UTF-8)', "$file_name" or error( "can't open $file_name : $!" . __FILE__ . ":" . __LINE__ ) && return 0;
      binmode( $FHnet, ":utf8" );

      print $FHnet "<BR><CENTER><TABLE class=\"tabconfig tablesorter\">";
      print $FHnet "<thead><TR> <TH class=\"sortable\" valign=\"center\">Description&nbsp;&nbsp;&nbsp;</TH>
        <TH align=\"center\" class=\"sortable\" valign=\"center\">&nbsp;&nbsp;&nbsp;DHCPServer&nbsp;&nbsp;</TH>
  			<TH align=\"center\" class=\"sortable\" valign=\"center\">&nbsp;&nbsp;&nbsp;DNSHostName&nbsp;&nbsp;</TH>
	  		<TH align=\"center\" class=\"sortable\" valign=\"center\">&nbsp;&nbsp;&nbsp;IPAddress&nbsp;&nbsp;</TH>
		  	<TH align=\"center\" class=\"sortable\" valign=\"center\">&nbsp;&nbsp;&nbsp;MACAddress&nbsp;&nbsp;</TH>
  			<TH align=\"center\" class=\"sortable\" valign=\"center\">&nbsp;&nbsp;&nbsp;ServiceName&nbsp;&nbsp;</TH>
	  		<TH align=\"center\" class=\"sortable\" valign=\"center\">&nbsp;&nbsp;&nbsp;SettingID&nbsp;&nbsp;</TH>
  			</TR></thead><tbody>\n";
      print $FHnet "$res_ret";

      print $FHnet "</tbody></TABLE></CENTER><BR><BR>\n";
      close $FHnet;
    }

    # licensing
    # CLASS: SoftwareLicensingProduct where ApplicationID='55c92734-d682-4d71-983e-d6ec3f16059f' AND PartialProductKey IS NOT NULL
    # "Description","LicenseStatus","PartialProductKey"
    # "Windows(R) Operating System, RETAIL channel","1","8HVX7"

    my $licensestatus = "";
    if ( exists $$hyp_data_comp_act->{"SoftwareLicensingProduct where ApplicationID='55c92734-d682-4d71-983e-d6ec3f16059f' AND PartialProductKey IS NOT NULL"} ) {
      $licensestatus = get_hyp_val( "SoftwareLicensingProduct where ApplicationID='55c92734-d682-4d71-983e-d6ec3f16059f' AND PartialProductKey IS NOT NULL", 'LicenseStatus', $hyp_data_comp_act );
    }
    my %lic_statuses = (
      "0" => "Unlicensed",
      "1" => "Licensed",
      "2" => "Out-Of-Box Grace Period",
      "3" => "Out-Of-Tolerance Grace Period",
      "4" => "Non-Genuine Grace Period",
      "5" => "Notification",
      "6" => "Extended Grace"
    );
    if ( exists $lic_statuses{$licensestatus} ) {
      $licensestatus = $lic_statuses{$licensestatus};
    }
    else {
      $licensestatus = "unknown";
    }

    my $LastBootUpTime = "";
    my $uptime         = "";

    if ( index( $$hyp_data_comp_act->{'Win32_OperatingSystem'}[0], 'LastBootUpTime' ) > -1 ) {
      $LastBootUpTime = get_hyp_val( 'Win32_OperatingSystem', 'LastBootUpTime', $hyp_data_comp_act );
      $LastBootUpTime = "" if ( !defined $LastBootUpTime or $LastBootUpTime eq $UnDeF );

      if ( index( $LastBootUpTime, ":" ) > -1 ) {    # ciminstance date format
                                                     # $hyperv_time = str2time( $hyperv_time );
        $uptime = time() - str2time($LastBootUpTime);

        my $days  = int( $uptime / 86400 );
        my $hours = ( $uptime / 3600 ) % 24;
        my $mins  = ( $uptime / 60 ) % 60;
        my $secs  = ( $uptime % 60 );
        $uptime = "$days days " . sprintf( "%02d:%02d:%02d", $hours, $mins, $secs );
      }
      else {
        if ( $LastBootUpTime ne "" ) {
          $LastBootUpTime =~ s/\.\d*//;
          my @arr = unpack '(a2)*', $LastBootUpTime;
          my ( $century, $year, $month, $day, $hour, $min, $sec ) = unpack '(a2)*', $LastBootUpTime;
          $uptime = time() - timelocal( $sec, $min, $hour, $day, $month - 1, $century . $year );

          # print "2500 $sec,$min,$hour,$day,$month-1,".$century.$year." \$uptime $uptime time ".time()."\n";
          my $days  = int( $uptime / 86400 );
          my $hours = ( $uptime / 3600 ) % 24;
          my $mins  = ( $uptime / 60 ) % 60;
          my $secs  = ( $uptime % 60 );

          # $uptime = "$days days " . sprintf( "%02d:%02d:%02d", $hours, $mins, $secs ) . "\n";
          $uptime = "$days days " . sprintf( "%02d:%02d:%02d", $hours, $mins, $secs );
        }
      }
    }

    ### not for standalone workstation

    if ( exists $$hyp_data_comp_act->{'Msvm_VirtualSystemManagementServiceSettingData'} ) {
      my $InstanceID          = get_hyp_val( 'Msvm_VirtualSystemManagementServiceSettingData', 'InstanceID',          $hyp_data_comp_act );
      my $CurrentWWNN         = get_hyp_val( 'Msvm_VirtualSystemManagementServiceSettingData', 'CurrentWWNNAddress',  $hyp_data_comp_act );
      my $MinMacAddress       = get_hyp_val( 'Msvm_VirtualSystemManagementServiceSettingData', 'MinimumMacAddress',   $hyp_data_comp_act );
      my $MaxMacAddress       = get_hyp_val( 'Msvm_VirtualSystemManagementServiceSettingData', 'MaximumMacAddress',   $hyp_data_comp_act );
      my $MinWWPNAddress      = get_hyp_val( 'Msvm_VirtualSystemManagementServiceSettingData', 'MinimumWWPNAddress',  $hyp_data_comp_act );
      my $MaxWWPNAddress      = get_hyp_val( 'Msvm_VirtualSystemManagementServiceSettingData', 'MaximumWWPNAddress',  $hyp_data_comp_act );
      my $NumaSpanningEnabled = get_hyp_val( 'Msvm_VirtualSystemManagementServiceSettingData', 'NumaSpanningEnabled', $hyp_data_comp_act );
      $InstanceID =~ s/Microsoft://;

      my $cs_caption        = get_hyp_val( 'Win32_OperatingSystem',       'Caption',           $hyp_data_comp_act );
      my $cs_version        = get_hyp_val( 'Win32_OperatingSystem',       'Version',           $hyp_data_comp_act );
      my $IdentifyingNumber = get_hyp_val( 'Win32_ComputerSystemProduct', 'IdentifyingNumber', $hyp_data_comp_act );
      if ( !defined $IdentifyingNumber ) {
        $IdentifyingNumber = "";
      }

      my $line_server = $InstanceID . "," . $cs_caption . "," . $cs_version . "," . $LastBootUpTime . "<BR>" . $uptime . "," . $licensestatus . "," . $c_cores . "," . $CurrentWWNN . "," . $MinMacAddress . "," . $MaxMacAddress . "," . $MinWWPNAddress . "," . $MaxWWPNAddress . "," . $NumaSpanningEnabled . "," . $IdentifyingNumber . "\n";
      @cpu_cfg = ();
      push @cpu_cfg, $line_server;
      $res_ret = FormatResults(@cpu_cfg);

      open my $FHserver, '>:encoding(UTF-8)', "$wrkdir/$managedname/server.html" or error( "can't open '$wrkdir/$managedname/server.html': $!" . __FILE__ . ":" . __LINE__ ) && return 0;
      binmode( $FHserver, ":utf8" );

      print $FHserver "<BR><CENTER><TABLE class=\"tabconfig tablesorter\">";
      print $FHserver "<thead><TR> <TH class=\"sortable\" valign=\"center\">InstanceID&nbsp;&nbsp;</TH>
        <TH align=\"center\" class=\"sortable\" valign=\"center\">&nbsp;&nbsp;&nbsp;OS&nbsp;</TH>
        <TH align=\"center\" class=\"sortable\" valign=\"center\">&nbsp;&nbsp;&nbsp;OS-version&nbsp;</TH>
        <TH align=\"center\" class=\"sortable\" valign=\"center\">&nbsp;&nbsp;&nbsp;LastBoot<BR>UpTime&nbsp;</TH>
        <TH align=\"center\" class=\"sortable\" valign=\"center\">&nbsp;&nbsp;&nbsp;License&nbsp;</TH>
        <TH align=\"center\" class=\"sortable\" valign=\"center\">&nbsp;&nbsp;&nbsp;Cores&nbsp;</TH>
  			<TH align=\"center\" class=\"sortable\" valign=\"center\">&nbsp;&nbsp;&nbsp;CurrentWWNN&nbsp;</TH>
	  		<TH align=\"center\" class=\"sortable\" valign=\"center\">&nbsp;&nbsp;&nbsp;Min MacAddress&nbsp;</TH>
		  	<TH align=\"center\" class=\"sortable\" valign=\"center\">&nbsp;&nbsp;&nbsp;Max MacAddress&nbsp;</TH>
  			<TH align=\"center\" class=\"sortable\" valign=\"center\">&nbsp;&nbsp;&nbsp;Min WWPNAddress&nbsp;</TH>
	  		<TH align=\"center\" class=\"sortable\" valign=\"center\">&nbsp;&nbsp;&nbsp;Max WWPNAddress&nbsp;</TH>
		  	<TH align=\"center\" class=\"sortable\" valign=\"center\">&nbsp;&nbsp;&nbsp;Numa Spanning Enabled&nbsp;</TH>
        <TH align=\"center\" class=\"sortable\" valign=\"center\">&nbsp;&nbsp;&nbsp;IdentifyingNumber&nbsp;</TH>
  			</TR></thead><tbody>\n";
      print $FHserver "$res_ret";

      print $FHserver "</tbody></TABLE></CENTER><BR><BR>\n";
      close $FHserver;
    }
    else {    ### for standalone workstation

      my $InstanceID = "";
      my $log_proc   = "";
      my $cores      = "";
      my $status     = "";
      my $cs_caption = get_hyp_val( 'Win32_OperatingSystem', 'Caption', $hyp_data_comp_act );
      my $cs_version = get_hyp_val( 'Win32_OperatingSystem', 'Version', $hyp_data_comp_act );

      my $IdentifyingNumber = get_hyp_val( 'Win32_ComputerSystemProduct', 'IdentifyingNumber', $hyp_data_comp_act );
      if ( !defined $IdentifyingNumber ) {
        $IdentifyingNumber = "";
      }

      # Win32_ComputerSystem sometimes is not presented (Win version < 2012 ?
      if ( exists $$hyp_data_comp_act->{'Win32_ComputerSystem'} ) {
        $InstanceID = get_hyp_val( 'Win32_ComputerSystem', 'Name',                      $hyp_data_comp_act );
        $log_proc   = get_hyp_val( 'Win32_ComputerSystem', 'NumberOfLogicalProcessors', $hyp_data_comp_act );
        $cores      = get_hyp_val( 'Win32_ComputerSystem', 'NumberOfProcessors',        $hyp_data_comp_act );
        $status     = get_hyp_val( 'Win32_ComputerSystem', 'Status',                    $hyp_data_comp_act );
      }
      else {

        # CLASS: Win32_OperatingSystem
        # "CSName","Name","LocalDateTime","Caption","OtherTypeDescription","CSDVersion","Version","LastBootUpTime"
        # "DESKTOP-O79DK45","Microsoft Windows 10 Home|C:\WINDOWS|\Device\Harddisk0\Partition5","20180917082509.846000+120","Microsoft Windows 10 Home",,,"10.0.16299","20210317120455.825023+060"
        $InstanceID = get_hyp_val( 'Win32_OperatingSystem', 'CSName', $hyp_data_comp_act );

        $cores = get_hyp_val( 'Win32_Processor', 'NumberOfCores', $hyp_data_comp_act );
        my @num_cpu = split( ",", $cores );
        my $suma    = 0;
        foreach my $num_proc (@num_cpu) {
          $suma += $num_proc;
        }
        $cores    = $suma;
        $log_proc = get_hyp_val( 'Win32_Processor', 'NumberOfLogicalProcessors', $hyp_data_comp_act );
        @num_cpu  = split( ",", $log_proc );
        $suma     = 0;
        foreach my $num_proc (@num_cpu) {
          $suma += $num_proc;
        }
        $log_proc = $suma;
        $status   = get_hyp_val( 'Win32_Processor', 'CpuStatus', $hyp_data_comp_act );
        $status =~ s/,/ /g;
        if ( isdigit($status) && exists $cpu_status{$status} ) {
          $status = $cpu_status{$status};
        }
      }

      # print "2368 \$status $status\n";

      my $line_server = $InstanceID . "," . $cs_caption . "," . $cs_version . "," . $LastBootUpTime . "<BR>" . $uptime . "," . $licensestatus . "," . $cores . "," . $log_proc . "," . $status . "," . $IdentifyingNumber . "\n";
      @cpu_cfg = ();
      push @cpu_cfg, $line_server;
      $res_ret = FormatResults(@cpu_cfg);

      open my $FHstand, '>:encoding(UTF-8)', "$wrkdir/$managedname/server.html" or error( "can't open '$wrkdir/$managedname/server.html': $!" . __FILE__ . ":" . __LINE__ ) && return 0;
      binmode( $FHstand, ":utf8" );

      print $FHstand "<BR><CENTER><TABLE class=\"tabconfig tablesorter\">";
      print $FHstand "<thead><TR> <TH class=\"sortable\" valign=\"center\">InstanceID&nbsp;&nbsp;</TH>
        <TH align=\"center\" class=\"sortable\" valign=\"center\">&nbsp;&nbsp;&nbsp;OS&nbsp;</TH>
        <TH align=\"center\" class=\"sortable\" valign=\"center\">&nbsp;&nbsp;&nbsp;OS-version&nbsp;</TH>
        <TH align=\"center\" class=\"sortable\" valign=\"center\">&nbsp;&nbsp;&nbsp;LastBoot<BR>UpTime&nbsp;</TH>
        <TH align=\"center\" class=\"sortable\" valign=\"center\">&nbsp;&nbsp;&nbsp;License&nbsp;</TH>
  			<TH align=\"center\" class=\"sortable\" valign=\"center\">&nbsp;&nbsp;&nbsp;Cores&nbsp;</TH>
        <TH align=\"center\" class=\"sortable\" valign=\"center\">&nbsp;&nbsp;&nbsp;Log.processors&nbsp;</TH>
	  		<TH align=\"center\" class=\"sortable\" valign=\"center\">&nbsp;&nbsp;&nbsp;Proc.Status&nbsp;</TH>
        <TH align=\"center\" class=\"sortable\" valign=\"center\">&nbsp;&nbsp;&nbsp;IdentifyingNumber&nbsp;</TH>
  			</TR></thead><tbody>\n";
      print $FHstand "$res_ret";

      print $FHstand "</tbody></TABLE></CENTER><BR><BR>\n";
      close $FHstand;
    }

    #prepare VHD_list table if there are some VMs
    my $vhd_file = "$wrkdir/$managedname/vhd_list.html";
    if ( scalar @vhd_list ) {
      $res_ret = FormatResults(@vhd_list);

      open my $FH, '>:encoding(UTF-8)', "$vhd_file" or error( "can't open $vhd_file: $!" . __FILE__ . ":" . __LINE__ ) && return 0;
      binmode( $FH, ":utf8" );

      print $FH "<BR><CENTER><TABLE class=\"tabconfig tablesorter\">";
      print $FH "<thead><TR> <TH class=\"sortable\" valign=\"center\">VM&nbsp;&nbsp;&nbsp;&nbsp;</TH>
        <TH align=\"center\" class=\"sortable\" valign=\"center\">&nbsp;&nbsp;&nbsp;ControllerType&nbsp;&nbsp;&nbsp;</TH>
        <TH align=\"center\" class=\"sortable\" valign=\"center\">&nbsp;&nbsp;&nbsp;Location&nbsp;&nbsp;&nbsp;</TH>
  			<TH align=\"center\" class=\"sortable\" valign=\"center\">&nbsp;&nbsp;&nbsp;Path&nbsp;&nbsp;&nbsp;</TH>
	  		</TR></thead><tbody>\n";
      print $FH "$res_ret";

      print $FH "</tbody></TABLE></CENTER><BR><BR>\n";
      close $FH;
    }
    else {
      unlink $vhd_file if ( -f $vhd_file );
    }

    #prepare disk config file for host config
    $res_ret = FormatResults(@disk_cfg);
    open my $FHdisk, '>:encoding(UTF-8)', "$wrkdir/$managedname/disk.html" or error( "can't open '$wrkdir/$managedname/disk.html': $!" . __FILE__ . ":" . __LINE__ ) && return 0;
    print $FHdisk "<BR><CENTER><TABLE class=\"tabconfig tablesorter\">\n";
    print $FHdisk "<thead><TR> <TH class=\"sortable\" valign=\"center\">VM&nbsp;&nbsp;&nbsp;&nbsp;</TH>
						<TH align=\"center\" class=\"sortable\" valign=\"right\">&nbsp;&nbsp;&nbsp;Provisioned Space GB&nbsp;&nbsp;&nbsp;</TH>
						<TH align=\"center\" class=\"sortable\" valign=\"right\">&nbsp;&nbsp;&nbsp;Used Space GB&nbsp;&nbsp;&nbsp;</TH>
			</TR></thead><tbody>\n";
    $res_ret =~ s/center/right/g;
    print $FHdisk "$res_ret";

    # print STDERR "1727 hyp2rrd.pl \$res_ret $res_ret \@disk_cfg @disk_cfg\n";
    print $FHdisk "</tbody></TABLE></CENTER><BR><BR>\n";
    close $FHdisk;

    #prepare host config file
    #for Host CPU
    my $host_cpu_shares = "";
    my $host_cpuAlloc   = "";
    my $host_memAlloc   = "";

    my $cpu_res    = $host_cpuAlloc;
    my $cpu_shares = $host_cpu_shares;
    my $comp_res   = $host_parent;

    #print Dumper($comp_res);

    my $l_info1 = "InfO maxUsage reservationUsed unreservedForPool reservationUsedForVm unreservedForVm cpu_res cpu_shares\n";

    #    my $l_info2 = "CPU $maxUsage $reservationUsed $unreservedForPool $reservationUsedForVm $unreservedForVm $cpu_res $cpu_shares\n";
    my $l_info2 = "\n";

    #for Host MEM
    my $mem_res = $host_memAlloc;

    my $maxUsage             = 0;
    my $reservationUsed      = 0;
    my $unreservedForPool    = 0;
    my $reservationUsedForVm = 0;
    my $unreservedForVm      = 0;

    my $l_info3   = "MEM $maxUsage $reservationUsed $unreservedForPool $reservationUsedForVm $unreservedForVm\n";
    my $host_uuid = get_hyp_val( 'Win32_ComputerSystemProduct', 'UUID', $hyp_data_comp_act );
    chomp $host_uuid;
    $host_uuid = "$host_uuid\n";
    my @host_cfg = ( $l_info1, $l_info2, $l_info3, $host_uuid );

    # following has sense only for vmware = only one ESXi, for windows the 4th line '$host_uuid' is OK and then used for mapping with oVirt
    open my $FHhost, ">$wrkdir/$managedname/host.cfg" or error( "can't open '$wrkdir/$managedname/host.cfg': $!" . __FILE__ . ":" . __LINE__ ) && return 0;
    print $FHhost @host_cfg;
    close $FHhost;

    $step = $STEP;    # do not know if vmware will have sometimes other value

    #LoadDataModuleHyperV::smdc_touch ($SDMC,$wrkdir,$managedname,$host,$act_time);

    $type_sam = "m";

    $host = "";       # working directly with domain name

    prepare_last_time( $hyp_data_comp_act, $hyp_data_comp_last, $managedname, $et_HostSystem );

    #print "prepare_last_time($managedname,$et_HostSystem);\n";

    #
    ### what about cluster
    #

    # CLASS: MSCluster_Cluster
    # "Dedicated","Fqdn","MaxNumberOfNodes","Name","SharedVolumesRoot","Status"
    # ,"MSNET-HVCL.ad.xorux.com","64","MSNET-HVCL","C:\ClusterStorage",

    if ( exists $$hyp_data_comp_act->{'MSCluster_Cluster'} ) {
      my $cluster_name = get_hyp_val( 'MSCluster_Cluster', 'Name', $hyp_data_comp_act );
      if ( index( $cluster_name, "," ) != -1 ) {    # just to be sure, it shoudnt be
        print "this is probably ERROR \$cluster_name $cluster_name\n";
        $cluster_name = ( split( ",", $cluster_name ) )[0];
      }
      $cluster_name =~ s/\"//g;
      my $dedicated = get_hyp_val( 'MSCluster_Cluster', 'Dedicated',         $hyp_data_comp_act );
      my $fqdn      = get_hyp_val( 'MSCluster_Cluster', 'Fqdn',              $hyp_data_comp_act );
      my $max_nodex = get_hyp_val( 'MSCluster_Cluster', 'MaxNumberOfNodes',  $hyp_data_comp_act );
      my $sv_root   = get_hyp_val( 'MSCluster_Cluster', 'SharedVolumesRoot', $hyp_data_comp_act );
      my $status    = get_hyp_val( 'MSCluster_Cluster', 'Status',            $hyp_data_comp_act );

      my $line         = $cluster_name . "," . $fqdn . "," . $dedicated . "," . $max_nodex . "," . $sv_root . "," . $status . "\n";
      my @cluster_list = ();
      push @cluster_list, $line;

      print_hyperv_debug("2323 \$cluster_name $cluster_name \$line $line\n") if $DEBUG == 2;

      # if does not exist cluster dir, prepare it
      my $cluster_dir = "$wrkdir_windows/cluster_$cluster_name";

      if ( !-d "$cluster_dir" ) {
        print "mkdir          : $cluster_dir\n";
        mkdir( "$cluster_dir", 0755 ) || error( " Cannot mkdir $cluster_dir: $!" . __FILE__ . ":" . __LINE__ ) && return 0;
      }

      #prepare cluster table
      $res_ret = FormatResults(@cluster_list);

      open my $FHcluster, '>:encoding(UTF-8)', "$cluster_dir/cluster_list.html" or error( "can't open $cluster_dir/cluster_list.html: $!" . __FILE__ . ":" . __LINE__ ) && return 0;
      binmode( $FHcluster, ":utf8" );

      print $FHcluster "<BR><CENTER><TABLE class=\"tabconfig tablesorter\">";
      print $FHcluster "<thead><TR> <TH class=\"sortable\" valign=\"center\">CLUSTER&nbsp;&nbsp;&nbsp;&nbsp;</TH>
        <TH align=\"center\" class=\"sortable\" valign=\"center\">&nbsp;&nbsp;&nbsp;FQDN&nbsp;&nbsp;&nbsp;</TH>
        <TH align=\"center\" class=\"sortable\" valign=\"center\">&nbsp;&nbsp;&nbsp;Dedicated&nbsp;&nbsp;&nbsp;</TH>
        <TH align=\"center\" class=\"sortable\" valign=\"center\">&nbsp;&nbsp;&nbsp;MaxNumberOfNodes&nbsp;&nbsp;&nbsp;</TH>
  			<TH align=\"center\" class=\"sortable\" valign=\"center\">&nbsp;&nbsp;&nbsp;SharedVolumesRoot&nbsp;&nbsp;&nbsp;</TH>
        <TH align=\"center\" class=\"sortable\" valign=\"center\">&nbsp;&nbsp;&nbsp;Status&nbsp;&nbsp;&nbsp;</TH>
	  		</TR></thead><tbody>\n";
      print $FHcluster "$res_ret";

      print $FHcluster "</tbody></TABLE></CENTER>\n";
      close $FHcluster;
    }

    # CLASS: MSCluster_ClusterToNode
    # "Antecedent","Dependent","RoleOfNode","StateOfNode"
    # "MSCluster_Cluster.Name="MSNET-HVCL"","MSCluster_Node.Name="HVNODE02"",,
    # "MSCluster_Cluster.Name="MSNET-HVCL"","MSCluster_Node.Name="HVNODE01"",,

    if ( exists $$hyp_data_comp_act->{'MSCluster_ClusterToNode'} ) {
      my $cluster_name = get_hyp_val( 'MSCluster_ClusterToNode', 'Antecedent', $hyp_data_comp_act );

      # MSCluster_Cluster.Name="MSNET-HVCL",MSCluster_Cluster.Name="MSNET-HVCL"
      $cluster_name = ( split( ",", $cluster_name ) )[0];
      $cluster_name = ( split( "=", $cluster_name ) )[1];
      $cluster_name =~ s/\"//g;
      my $node_names = get_hyp_val( 'MSCluster_ClusterToNode', 'Dependent', $hyp_data_comp_act );

      # MSCluster_Node.Name="HVNODE02",MSCluster_Node.Name="HVNODE01"
      my @nodes       = split( ",", $node_names );
      my @node_list   = ();
      my $domain_name = $domain;
      $domain_name =~ s/^domain_//;
      foreach (@nodes) {
        my $node_name = ( split( "=", $_ ) )[1];
        $node_name =~ s/\"//g;
        print_hyperv_debug("2197 \$node_name $node_name\n") if $DEBUG == 2;
        my $RoleOfNode  = get_hyp_val( 'MSCluster_ClusterToNode', 'RoleOfNode',  $hyp_data_comp_act, $node_name );
        my $StateOfNode = get_hyp_val( 'MSCluster_ClusterToNode', 'StateOfNode', $hyp_data_comp_act, $node_name );

        my $line = $cluster_name . "," . $domain_name . "," . $node_name . "," . $RoleOfNode . "," . $StateOfNode . "\n";
        push @node_list, $line;
      }
      print_hyperv_debug("2188 \$cluster_name $cluster_name \$node_names $node_names\n") if $DEBUG == 2;

      # if does not exist cluster dir, prepare it
      my $cluster_dir = "$wrkdir_windows/cluster_$cluster_name";

      if ( !-d "$cluster_dir" ) {
        print "mkdir          : $cluster_dir\n";
        mkdir( "$cluster_dir", 0755 ) || error( " Cannot mkdir $cluster_dir: $!" . __FILE__ . ":" . __LINE__ ) && return 0;
      }

      #prepare node_list table
      $res_ret = FormatResults(@node_list);

      open my $FHnode, '>:encoding(UTF-8)', "$cluster_dir/node_list.html" or error( "can't open $cluster_dir/node_list.html: $!" . __FILE__ . ":" . __LINE__ ) && return 0;
      binmode( $FHnode, ":utf8" );

      print $FHnode "<BR><CENTER><TABLE class=\"tabconfig tablesorter\">";
      print $FHnode "<thead><TR> <TH class=\"sortable\" valign=\"center\">CLUSTER&nbsp;&nbsp;&nbsp;&nbsp;</TH>
        <TH align=\"center\" class=\"sortable\" valign=\"center\">&nbsp;&nbsp;&nbsp;DOMAIN&nbsp;&nbsp;&nbsp;</TH>
        <TH align=\"center\" class=\"sortable\" valign=\"center\">&nbsp;&nbsp;&nbsp;Node&nbsp;&nbsp;&nbsp;</TH>
        <TH align=\"center\" class=\"sortable\" valign=\"center\">&nbsp;&nbsp;&nbsp;RoleOfNode&nbsp;&nbsp;&nbsp;</TH>
  			<TH align=\"center\" class=\"sortable\" valign=\"center\">&nbsp;&nbsp;&nbsp;StateOfNode&nbsp;&nbsp;&nbsp;</TH>
	  		</TR></thead><tbody>\n";
      print $FHnode "$res_ret";

      print $FHnode "</tbody></TABLE></CENTER>\n";
      close $FHnode;

    }
  }    # end of cycle on $managedname_list (on servers)

  open my $FH, ">>$counters_info_file" or error( "can't open $counters_info_file: $!" . __FILE__ . ":" . __LINE__ );

  # print output of all forks

  foreach my $fh (@returns) {
    while (<$fh>) {
      if ( $_ =~ 'XERROR' ) {
        ( undef, my $text ) = split( ":", $_ );
        print $FH "$text\n";
      }
      else {
        print $_;
      }
    }
    close($fh);
  }

  close $FH;

  print "All chld finish: $host \n" if $DEBUG;

  #  waitpid( -1, "WNOHANG" );    # take stats of all forks

  return 0;
}

sub VM_hosting_read {
  my $a_ref        = shift;
  my $hosting_file = shift;

  if ( -f "$hosting_file" ) {
    open my $FH, "$hosting_file" or error( "can't open $hosting_file: $!" . __FILE__ . ":" . __LINE__ ) && return 0;
    @$a_ref = <$FH>;
    close $FH;
  }
}

sub VM_hosting_update {
  my $a_ref    = shift;
  my $vm_uuid  = shift;
  my $cmd_time = shift;

  #  if ($vm_uuid eq "522368c5-61e5-a937-b4e7-06bd2f1a3603") {
  #	return
  #  }

  my $found = 0;
  for ( my $i = 0; $i < scalar @$a_ref; $i++ ) {
    my $pos = rindex( @$a_ref[$i], ':' );
    next if $pos < 0;                                         # some trash
    next if ( substr( @$a_ref[$i], 0, 36 ) ne "$vm_uuid" );
    if ( substr( @$a_ref[$i], $pos + 1, 3 ) eq "sta" ) {      # keep item
      substr( @$a_ref[$i], length( @$a_ref[$i] ) - 1, 5 ) = ":act\n";
      $found++;
      last;
    }
    if ( substr( @$a_ref[$i], $pos + 1, 3 ) eq "end" ) {      # restart item
      substr( @$a_ref[$i], length( @$a_ref[$i] ) - 1, 22 ) = ":start=$cmd_time:new\n";
      $found++;
      last;
    }
  }
  if ( !$found ) {                                            # new item
    push @$a_ref, "$vm_uuid" . ":start=$cmd_time" . ":new\n";
  }
}

sub VM_hosting_write {
  my $a_ref        = shift;
  my $hosting_file = shift;
  my $cmd_time     = shift;

  # preparing info
  my $change = 0;                                             # write file only when is change

  for ( my $i = 0; $i < scalar @$a_ref; $i++ ) {
    my $pos = rindex( @$a_ref[$i], ':' );
    next if $pos < 0;                                          # some trash
    next if ( substr( @$a_ref[$i], $pos + 1, 3 ) eq "end" );
    if ( substr( @$a_ref[$i], $pos + 1, 3 ) eq "act" ) {
      substr( @$a_ref[$i], $pos, 4 ) = "";
    }
    if ( substr( @$a_ref[$i], $pos + 1, 3 ) eq "new" ) {
      substr( @$a_ref[$i], $pos, 4 ) = "";
      $change++;
    }
    if ( substr( @$a_ref[$i], $pos + 1, 3 ) eq "sta" ) {       # not registered anymore
      substr( @$a_ref[$i], length( @$a_ref[$i] ) - 1, 16 ) = ":end=$cmd_time\n";
      $change++;
    }

  }

  if ($change) {
    open my $FH, ">$hosting_file" or error( "can't open $hosting_file: $!" . __FILE__ . ":" . __LINE__ ) && return 0;
    print $FH @$a_ref;
    close $FH;
  }
}

sub prepare_last_time {
  my $hyp_data_comp_act  = shift;    # hash pointer
  my $hyp_data_comp_last = shift;    # hash pointer

  my $entity      = shift;
  my $entity_type = shift;
  my $entity_name = shift;
  my $entity_uuid = shift;

  # if ($entity_name eq "CUSTOMER2") { return };

  $step    = $STEP;                       # do not know if vmware will have sometimes other value
  $no_time = $step * $NO_TIME_MULTIPLY;

  $loadhours = 0;                         # must be here before rrd_check

  if ( $entity_type eq $et_ResourcePool ) {

    # print "----------------------------------- getting perf for RP $entity,\$host $host,\$managedname $managedname,\$wrkdir $wrkdir\n";
    $last_file = "$entity_uuid.last";     # RP name
  }
  if ( $entity_type eq $et_Datastore ) {

    # print "----------------------------------- getting perf for datastore $entity,\$host $host,\$managedname $managedname,\$wrkdir $wrkdir\n";
    $last_file = "$entity_uuid.last";     # DS name
  }
  if ( $entity_type eq $et_ClusterComputeResource ) {
    $last_file = "last.txt";
  }

  rrd_check($managedname);                # testing if first load

  print "sample rate    : $host:$managedname $step seconds\n" if $DEBUG;

  #my $t=str2time($date);
  my $t     = $command_unix;
  my $t_int = int($t);

  # print "DATE: $t -- $t_int -- $date\n" ;
  # my $date = $command_date; # can be diff time zone for W10
  my $date = $command_unix;

  my $time_act = strftime "%d/%m/%y %H:%M:%S", localtime( time() );
  print "HyperV date    : $host:$managedname $date (local time: $time_act) \n" if $DEBUG;

  my $last_rec_file = "";

  my $where = "file";
  if ( !$loadhours ) {    # all except the initial load --> check rrd_check
    print_hyperv_debug("checking last file $wrkdir/$managedname/$host/$last_file\n") if $DEBUG == 2;
    if ( -f "$wrkdir/$managedname/$host/$last_file" ) {
      $where = "$last_file";

      # read timestamp of last record
      # this is main loop how to get corectly timestamp of last record!!!

      open( my $FHLT, "< $wrkdir/$managedname/$host/$last_file" ) || error( " Can't open $wrkdir/$managedname/$host/$last_file: $!" . __FILE__ . ":" . __LINE__ ) && return 0;
      foreach my $line1 (<$FHLT>) {
        chomp($line1);
        $last_rec_file = $line1;
      }
      close($FHLT);
      print "last rec 1     : $host:$managedname $last_rec_file $wrkdir/$managedname/$host/$last_file\n";

      my $ret = substr( $last_rec_file, 0, 1 );
      if ( $last_rec_file eq '' || $ret =~ /\D/ ) {

        # in case of an issue with last file, remove it and use default 60 min? for further run ...
        error("Wrong input data, deleting file : $wrkdir/$managedname/$host/$last_file : $last_rec_file");
        unlink("$wrkdir/$managedname/$host/$last_file");

        # place there last 1h when an issue with last.txt
        $loadhours = 1;
        $loadmins  = 60;
        $last_rec  = $t - 3600;
      }
      else {
        $last_rec  = str2time($last_rec_file);
        $loadhours = sprintf( "%.0f", ( $t - $last_rec ) / 3600 );
        $loadhours++;
        $loadmins   = sprintf( "%.0f", ( $t - $last_rec ) / 60 );    # nothing more
        $loadsec_vm = sprintf( "%.0f", ( $t - $last_rec ) );         # for vmware
      }
    }
    else {
      # old not accurate way how to get last time stamp, keeping it here as backup if above temp fails for any reason
      if ( -f "$wrkdir/$managedname/$host/mem.rr$type_sam" ) {
        $where = "mem.rr$type_sam";

        # find out last record in the db (hourly)
        RRDp::cmd qq(last "$wrkdir/$managedname/$host/mem.rr$type_sam" );
        my $last_rec_raw = RRDp::read;
        chomp($$last_rec_raw);
        $last_rec  = $$last_rec_raw;
        $loadhours = sprintf( "%.0f", ( $t - $last_rec ) / 3600 );
        $loadhours++;
        $loadmins = sprintf( "%.0f", ( $t - $last_rec ) / 60 + 5 - 5 );    # +5mins to be sure, not for vmware
        ( my $sec, $ivmmin, $ivmh, $ivmd, $ivmm, $ivmy, my $wday, my $yday, my $isdst ) = localtime($last_rec);
        $ivmy += 1900;
        $ivmm += 1;

        if ( $loadhours < 0 ) {                                            # Do not know why, but it sometimes happens!!!
          if ( -f "$wrkdir/$managedname/$host/pool.rr$type_sam" ) {

            # find out last record in the db (hourly)
            RRDp::cmd qq(last "$wrkdir/$managedname/$host/pool.rr$type_sam" );
            my $last_rec_raw = RRDp::read;
            chomp($$last_rec_raw);
            $last_rec  = $$last_rec_raw;
            $loadhours = sprintf( "%.0f", ( $t - $last_rec ) / 3600 );
            $loadhours++;
            $loadmins   = sprintf( "%.0f", ( $t - $last_rec ) / 60 + 5 - 5 );    # +5mins to be sure, not for vmware
            $loadsec_vm = sprintf( "%.0f", ( $t - $last_rec ) );                 # # for vmware
            error("++2 $loadhours -- $last_rec -- $t");
          }
        }
      }
      else {
        if ( -f "$wrkdir/$managedname/$host/pool.rr$type_sam" ) {
          $where = "pool.rr$type_sam";

          # find out last record in the db (hourly)
          RRDp::cmd qq(last "$wrkdir/$managedname/$host/pool.rr$type_sam" );
          my $last_rec_raw = RRDp::read;
          chomp($$last_rec_raw);
          $last_rec  = $$last_rec_raw;
          $loadhours = sprintf( "%.0f", ( $t - $last_rec ) / 3600 );
          $loadhours++;
          $loadmins = sprintf( "%.0f", ( $t - $last_rec ) / 60 + 5 );    # +5mins to be sure
        }
        else {
          $where     = "init";
          $loadmins  = $INIT_LOAD_IN_HOURS_BACK * 60;
          $loadhours = $INIT_LOAD_IN_HOURS_BACK;
        }
      }
    }
  }
  else {
    $where = "init";
    my $loadsecs = $INIT_LOAD_IN_HOURS_BACK * 3600;
    $last_rec = $t - $loadsecs;
  }

  if ( $loadhours <= 0 || $loadmins <= 0 ) {    # something wrong is here
    error("Last rec issue: $last_file:  $loadhours - $loadmins -  $last_rec -- $last_rec_file : $date : $t : 01");

    # place some reasonable defaults
    $loadhours = 1;
    $loadmins  = 60;
    $last_rec  = time();
    $last_rec  = $last_rec - 3600;
  }

  ( $sec, $ivmmin, $ivmh, $ivmd, $ivmm, $ivmy, $wday, $yday, $isdst ) = localtime($last_rec);
  $ivmy += 1900;
  $ivmm += 1;
  print "last rec 2     : $host:$managedname min:$loadmins , hour:$loadhours, $ivmm/$ivmd/$ivmy $ivmh:$ivmmin : $where\n" if $DEBUG;

  lpm_exclude_vio( $host, $managedname, $wrkdir );

  hmc_load_data( $hyp_data_comp_act, $hyp_data_comp_last, $t, $managedname, $host, $last_rec, $t, $entity, $entity_type, $entity_uuid );
  $date = localtime();
  print "date load      : $host:$managedname $date\n" if $DEBUG;
}

# provides easy uuid check, pays for 1 arg only
sub uuid_check {

  return ( $_[0] =~ m{.{8}-.{4}-.{4}-.{4}-.{12}} );
}

sub hmc_load_data {
  my $hyp_data_comp_act  = shift;    # hash pointer
  my $hyp_data_comp_last = shift;    # hash pointer

  my $hmc_utime = shift;

  #my $loadhours = shift; # it must be GLOBAL variable
  my $managedname = shift;
  my $host        = shift;
  my $last_rec    = shift;
  my $t           = shift;
  my $entity      = shift;
  my $entity_type = shift;
  my $entity_uuid = shift;

  print_hyperv_debug("1905 hyp2rrd.pl \$hmc_utime $hmc_utime \$managedname $managedname \$host $host \$last_rec $last_rec \$t $t \$vm_host ,$vm_host,\n") if $DEBUG == 2;

  if ( $loadhours == $INIT_LOAD_IN_HOURS_BACK ) {

    # just to be sure ....
    $loadmins = $INIT_LOAD_IN_HOURS_BACK * 60;
  }

  if ( $loadhours <= 0 || $loadmins <= 0 ) {    # workaround as this sometimes is negative , need to check it out ...
    if ( !$last_rec eq '' ) {
      error("$act_time: time issue 1   : $host:$managedname hours:$loadhours mins:$loadmins Last saved record (vmware time) : $last_rec ; vmware time : $t");
    }
    $loadhours = 1;
    $loadmins  = 60;
  }

  my $loadsecs        = $loadmins * 60;
  my $hmc_start_utime = $hmc_utime - $loadsecs;

  if ( $loadmins > 0 ) {

    #  if ( $loadmins  > 60 ) { $loadmins = 60 };

    if ( $loadhours != $INIT_LOAD_IN_HOURS_BACK ) {
      print "download data  : $host:$managedname last $loadmins  minute(s) ($loadhours hours) ($loadsec_vm sec VM)\n" if $DEBUG;
    }

    my $pef_time_sec = $loadsec_vm;
    if ( $loadsec_vm eq "" ) {
      $pef_time_sec = $loadmins * 60;
    }

    ###   forking

    if ( !$do_fork || $cycle_count == $PARALLELIZATION ) {
      print "No fork        : $host:$managedname : $server_count\n" if $DEBUG;
      load_data_and_graph( $hyp_data_comp_act, $hyp_data_comp_last, $pef_time_sec, $entity, $entity_type, $entity_uuid );
      $cycle_count = 0;
    }
    else {

      local *FH;
      $pid[$server_count] = open( FH, "-|" );

      #      $pid[$server_count] = fork();
      if ( not defined $pid[$server_count] ) {
        error("$host:$managedname could not fork");
      }
      elsif ( $pid[$server_count] == 0 ) {
        print "Fork           : $host:$managedname : $server_count child pid $$\n" if $DEBUG;
        my $i_am_fork = "fork";
        RRDp::end;
        RRDp::start "$rrdtool";

        eval { Util::connect(); };
        if ($@) {
          my $ret = $@;
          chomp($ret);
          error( "vmw2rrd failed: $ret " . __FILE__ . ":" . __LINE__ );
          exit(1);
        }

        # locale for english
        my $serviceContent = Vim::get_service_content();
        my $sessionManager = Vim::get_view( mo_ref => $serviceContent->sessionManager );
        $sessionManager->SetLocale( locale => "en" );

        #        $sessionManager->SetLocale(locale => "de");

        Opts::assert_usage( defined($sessionManager), "No sessionManager." );

        load_data_and_graph( $hyp_data_comp_act, $hyp_data_comp_last, $pef_time_sec, $entity, $entity_type, $entity_uuid );
        print "Fork exit      : $host:$managedname : $server_count\n" if $DEBUG;
        RRDp::end;
        Util::disconnect();
        exit(0);
      }
      print "Parent continue: $host:$managedname $pid[$server_count ] parent pid $$\n";
      $server_count++;

      push @returns, *FH;

    }
    $cycle_count++;
  }
  else {
    my $t1 = localtime($last_rec);
    my $t2 = localtime($t);
    error("$act_time: time issue 2   : $host:$managedname hours:$loadhours mins:$loadmins Last saved record (HMC lslparutil time) : $last_rec ; HMC time : $t - $t1 - $t2");
  }
}

sub load_data_and_graph {
  my $hyp_data_comp_act  = shift;    # hash pointer
  my $hyp_data_comp_last = shift;    # hash pointer

  my $pef_time_sec = shift;
  my $entity       = shift;
  my $entity_type  = shift;
  my $entity_uuid  = shift;

  if ( !defined $entity_type ) {
    $entity_type = "";
  }

  my $st_date;
  my $end_date;

  ( $st_date, $end_date, $pef_time_sec ) = get_last_date_range( $pef_time_sec, $entity_type );
  print "dates          : \$st_date $st_date \$end_date $end_date total sec $pef_time_sec (F$server_count)\n";

  # print "$entity_type, $st_date, $end_date, $pef_time_sec, $entity_uuid\n";

  if ( $entity_type eq $et_ClusterComputeResource ) {
    get_entity_perf( $entity, $entity_type, $st_date, $end_date, $pef_time_sec );
    return;
  }

  if ( $entity_type eq $et_ResourcePool ) {
    get_entity_perf( $entity, $entity_type, $st_date, $end_date, $pef_time_sec, $entity_uuid );
    return;
  }

  if ( $entity_type eq $et_Datastore ) {
    get_entity_perf( $entity, $entity_type, $st_date, $end_date, $pef_time_sec, $entity_uuid );
    return;
  }

  $entity_type = $et_HostSystem;
  my $entity_host = $vm_host;
  get_entity_perf( $hyp_data_comp_act, $hyp_data_comp_last, $entity_host, $entity_type, $st_date, $end_date, $pef_time_sec );

  $entity_type = $et_VirtualMachine;

  foreach my $entity ( sort { $a cmp $b } @vm_view ) {

    #check if the vm is on to collect stats

    next if $entity eq $UnDeF;    # server has no VMs

    if ( $vm_name_powerstat{$entity} ne "ON" ) {
      print "fetching VM    : " . $entity . " is powered " . $vm_name_powerstat{$entity} . " No stats available. (F$server_count)\n" if $DEBUG;
      next;
    }
    $fail_entity_name = $entity;
    $fail_entity_type = "VM";

    get_entity_perf( $hyp_data_comp_act, $hyp_data_comp_last, $entity, $entity_type, $st_date, $end_date, $pef_time_sec );
  }
}

sub get_entity_perf {
  my ( $hyp_data_comp_act, $hyp_data_comp_last, $entity, $entity_type, $st_date, $end_date, $pef_time_sec, $entity_uuid ) = @_;

  my $entity_nick = "VM    : ";
  $entity_nick = "HS    : " if $entity_type eq $et_HostSystem;
  $entity_nick = "clust : " if $entity_type eq $et_ClusterComputeResource;
  $entity_nick = "RP    : " if $entity_type eq $et_ResourcePool;
  $entity_nick = "DS    : " if $entity_type eq $et_Datastore;

  print_hyperv_debug("in sub get_entity_perf \$entity_type $entity_type \$entity ,$entity, \$vm_host ,$vm_host, \$st_date $st_date \$end_date $end_date \$pef_time_sec $pef_time_sec\n") if $DEBUG == 2;

  # return if $entity_type eq "VirtualMachine";

  my $intervals;
  my $refreshRate = "-1";    # for any case

  my @fake_arr = ();         # just for DS ESXi using
  $fake_arr[0]{'sample'} = 'ahoj';
  my $perf_metric_ids = \@fake_arr;

  my $intervalId;

  my $maxsample;
  my $perf_query_spec;

  my $real_sampling_period = "Nothing";
  my $time_stamps;
  my $perf_data;

  my $spec_routine = 0;

  $vm_vCPU[0]            = "U";    # in any case
  $vm_MemoryAvailable[0] = "U";    # in any case, only for VMs under 2016

  if ( $entity_type eq $et_VirtualMachine ) {

    # $DEBUG = 2; # just for VMs debug; see end of this if (

    # number of vcpu is in $vm_name_vcpu{$entity};

    # print "2443 hyp2rrd.pl computing for $entity\n" if $DEBUG ==2;

    #return if $entity eq "CentOS01";
    #return if $entity eq "WinXP";
    #return if $entity eq "XoruX-image";
    #return if $entity eq "XoruX-master";

    $vm_uuid_active = $vm_name_uuid{$entity};
    $last_file      = "$vm_uuid_active.last";
    if ( !-f "$wrkdir/$all_hyperv_VMs/$last_file" ) {
      `touch "$wrkdir/$all_hyperv_VMs/$last_file"`;
    }
    #
    ### data digging from Virtual Machine
    #

    # Memory
    #
    $vm_TotalPhysicalMemory[0] = $vm_uuid_mem{$vm_uuid_active};

    # there are no these counters for VM
    $vm_AvailableMBytes[0]   = "U";
    $vm_CacheBytes[0]        = "U";
    $vm_PagesInputPersec[0]  = "U";
    $vm_PagesOutputPersec[0] = "U";

    $vm_MemoryAvailable[0] = "U";

    if ( exists $$hyp_data_comp_act->{'Msvm_SummaryInformation'} ) {
      $vm_MemoryAvailable[0] = get_hyp_val( 'Msvm_SummaryInformation', 'MemoryAvailable', $hyp_data_comp_act, $vm_uuid_active );    # not name but UUID
                                                                                                                                    # print "3409 \$vm_MemoryAvailable[0] $vm_MemoryAvailable[0]\n";
                                                                                                                                    # if 0-100 it is %, or >100 is Bytes or <0 when memory deficit

      if ( $vm_MemoryAvailable[0] eq $UnDeF || $vm_MemoryAvailable[0] < 0 ) {
        $vm_MemoryAvailable[0] = "U";
      }
      elsif ( $vm_MemoryAvailable[0] > 100 && $vm_TotalPhysicalMemory[0] > 0 ) {
        $vm_MemoryAvailable[0] = ( 1 - ( $vm_MemoryAvailable[0] / 1024 / 1024 / $vm_TotalPhysicalMemory[0] ) ) * 100;               # means used memory
      }
      else {
        # let % used goes to be saved
      }
    }

    # print "3420 \$vm_MemoryAvailable[0] $vm_MemoryAvailable[0] \$vm_TotalPhysicalMemory[0] $vm_TotalPhysicalMemory[0]\n";

    # sometimes the VM name in Msvm_ComputerSystem is not the same as in other classes
    # e.g. difference: cl00242_isoc-etu-cl2 X cl00242-isoc-etu-cl2 hyphen or undescore
    # the diff name can be in CLASS: Msvm_LANEndpoint
    # "Name","MacAddress","ElementName","SystemName"
    # "Microsoft:89A2D2DE-6EC9-49D0-9059-48F7E6096B20","001DD8B71D0F","cl00242-isoc-etu-cl2","349484D8-6FD1-40F9-A5CF-51218221BEF7"
    # CLASS: Msvm_ComputerSystem
    # "Name","Caption","Description","ElementName","EnabledState","HealthState","NumberOfNumaNodes","OnTimeInMilliseconds","OperatingStatus","Status","StatusDescriptions"
    # "349484D8-6FD1-40F9-A5CF-51218221BEF7","Virtual Machine","Microsoft Virtual Machine","cl00242_isoc-etu-cl2","2","5","1","6112203228",,"OK","Operating normally"
    my $vm_name_diff = "";    # different VM name
    if ( exists $$hyp_data_comp_act->{'Msvm_LANEndpoint'} ) {
      $vm_name_diff = get_hyp_val( 'Msvm_LANEndpoint', 'ElementName', $hyp_data_comp_act, $vm_uuid_active );
      if ( defined $vm_name_diff && $vm_name_diff ne $UnDeF && $vm_name_diff ne "" && $vm_name_diff ne 'Network Adapter' && $vm_name_diff ne 'Síťový adaptér' ) {

        # can be more adapters result like: Síťový adaptér,JDS2-VM_ELANOR_JDS_ARCHIVE
        if ( index( $vm_name_diff, "," ) ne -1 ) {
          $vm_name_diff =~ s/Síťový adaptér,//;

          # other possibilities?
        }
        if ( $vm_name_diff ne $entity ) {
          print "VM name diff   : $entity X $vm_name_diff\n";
        }
        else {
          $vm_name_diff = "";    # as a signal for no diff VM name
        }
      }
    }

    # Disk
    #
    # CLASS: Win32_PerfRawData_Counters_HyperVVirtualStorageDevice
    # Frequency_PerfTime|Name|ReadBytesPersec|Timestamp_PerfTime|WriteBytesPersec
    # 3117912|C:-Users-Public-Documents-Hyper-V-Virtual hard disks-XoruX-master.vhdx|200728064|6790638553965|883835904
    # entity name BRNEO343
    # "C:-ClusterStorage-Volume1-BRNEO343-BRNEO928_disk_1.vhdx","4132664320","2248264625084","2922823","520192"

    #$DEBUG = 2;

    $vm_DiskBytesPersec[0] = "U";

    # "
    $vm_DiskReadBytesPersec[0] = delta_get_hyp_val( 'Win32_PerfRawData_Counters_HyperVVirtualStorageDevice', 'ReadBytesPersec', $hyp_data_comp_act, $hyp_data_comp_last, $entity );
    print "2965 for \$entity $entity \$vm_DiskReadBytesPersec[0] $vm_DiskReadBytesPersec[0]\n" if $DEBUG == 2;
    if ( $vm_DiskReadBytesPersec[0] eq "" ) {
      if ( index( $entity, "(" ) ne -1 or index( $entity, ")" ) ne -1 ) {
        my $entity_ch = $entity;
        $entity_ch =~ s/\(/\[/g;
        $entity_ch =~ s/\)/\]/g;
        $vm_DiskReadBytesPersec[0] = delta_get_hyp_val( 'Win32_PerfRawData_Counters_HyperVVirtualStorageDevice', 'ReadBytesPersec', $hyp_data_comp_act, $hyp_data_comp_last, $entity_ch );
      }
    }
    if ( $vm_DiskReadBytesPersec[0] eq "" && $vm_name_diff ne "" ) {
      $vm_DiskReadBytesPersec[0] = delta_get_hyp_val( 'Win32_PerfRawData_Counters_HyperVVirtualStorageDevice', 'ReadBytesPersec', $hyp_data_comp_act, $hyp_data_comp_last, $vm_name_diff );
    }
    if ( $vm_DiskReadBytesPersec[0] eq "" || $vm_DiskReadBytesPersec[0] eq $UnDeF ) {
      $vm_DiskReadBytesPersec[0] = "U";
    }
    else {    # sum if more numbers like "0,1,2"
      my @narr = split( ",", $vm_DiskReadBytesPersec[0] );
      $vm_DiskReadBytesPersec[0] = 0;
      foreach (@narr) { $vm_DiskReadBytesPersec[0] += $_; }
    }

    $vm_DiskReadsPersec[0]     = "U";
    $vm_DiskTransfersPersec[0] = "U";
    $vm_DiskWriteBytesPerse[0] = delta_get_hyp_val( 'Win32_PerfRawData_Counters_HyperVVirtualStorageDevice', 'WriteBytesPersec', $hyp_data_comp_act, $hyp_data_comp_last, $entity );
    print "2979 for \$entity $entity \$vm_DiskWriteBytesPerse[0] $vm_DiskWriteBytesPerse[0]\n" if $DEBUG == 2;
    if ( $vm_DiskWriteBytesPerse[0] eq "" ) {
      if ( index( $entity, "(" ) ne -1 or index( $entity, ")" ) ne -1 ) {
        my $entity_ch = $entity;
        $entity_ch =~ s/\(/\[/g;
        $entity_ch =~ s/\)/\]/g;
        $vm_DiskWriteBytesPerse[0] = delta_get_hyp_val( 'Win32_PerfRawData_Counters_HyperVVirtualStorageDevice', 'WriteBytesPersec', $hyp_data_comp_act, $hyp_data_comp_last, $entity_ch );
      }
    }
    if ( $vm_DiskWriteBytesPerse[0] eq "" && $vm_name_diff ne "" ) {
      $vm_DiskWriteBytesPerse[0] = delta_get_hyp_val( 'Win32_PerfRawData_Counters_HyperVVirtualStorageDevice', 'WriteBytesPersec', $hyp_data_comp_act, $hyp_data_comp_last, $vm_name_diff );
    }
    if ( $vm_DiskWriteBytesPerse[0] eq "" || $vm_DiskWriteBytesPerse[0] eq $UnDeF ) {
      $vm_DiskWriteBytesPerse[0] = "U";
    }
    else {    # sum if more numbers like "0,1,2"
      my @narr = split( ",", $vm_DiskWriteBytesPerse[0] );
      $vm_DiskWriteBytesPerse[0] = 0;
      foreach (@narr) { $vm_DiskWriteBytesPerse[0] += $_; }
    }
    print "2986 for \$entity $entity \$vm_DiskReadBytesPersec[0] $vm_DiskReadBytesPersec[0] \$vm_DiskWriteBytesPerse[0] $vm_DiskWriteBytesPerse[0]\n" if $DEBUG == 2;

    # $DEBUG = 0;

    # Net

    # CLASS: Win32_PerfRawData_NvspNicStats_HyperVVirtualNetworkAdapter
    # "Name","BytesPersec","Timestamp_PerfTime","Frequency_PerfTime","BytesReceivedPersec","BytesSentPersec"
    # "hvlinux02_Network Adapter_61538264-853b-43a0-99f5-dcfe083864c0--d599bf62-f009-4ef2-add6-1d5892df4f3b","60712415","29903862368223","2994772","53888216","6824199"
    # "hvlinux01_Network Adapter_cbd9d469-a221-4228-816f-3860110150ad--77392ce0-a661-4e13-8249-60c765b43746","66790581","29903862368223","2994772","60484772","6305809"
    # "Intel[R] 82574L Gigabit Network Connection__DEVICE_{BFEF4FE9-43CC-47AC-8097-E0B4BD66CC80}","239408559995","29903862368223","2994772","181198964451","58209595544"
    # "Virtual Switch_D576DFFB-56B1-4997-897E-0942AEBF39BB","238969981569","29903862368223","2994772","57784427572","181185553997"

    # there are two possibilities to find NET for VM
    $vm_BytesReceivedPersec[0] = "U";
    $vm_BytesSentPersec[0]     = "U";
    $vm_BytesTotalPersec[0]    = "U";

    # prepare time coeff, hmm: do not know if it would be more precise to get it directly from Timestamp_PerfTime ?
    my $vm_time_step        = delta_get_hyp_val( 'Win32_PerfRawData_PerfOS_Memory', 'Hyperv_UTC', $hyp_data_comp_act, $hyp_data_comp_last );
    my $vm_time_coefficient = $vm_time_step / 300;                                                                                             #  adjusted to 5 minutes base
    if ( $vm_time_coefficient < 1 ) {                                                                                                          # can happen when another (debug) load from cmd line or so
      $vm_time_coefficient = 1;
    }

    if ( exists $$hyp_data_comp_act->{'Win32_PerfRawData_NvspNicStats_HyperVVirtualNetworkAdapter'} ) {

      # one VM can have more adapters, add counters to one sum
      # CLASS: Win32_PerfRawData_NvspNicStats_HyperVVirtualNetworkAdapter
      # "Name","BytesPersec","Timestamp_PerfTime","Frequency_PerfTime","BytesReceivedPersec","BytesSentPersec"
      # "SRV-SQL-DEV-N02_SRV-SQL-DEV-N02_b053d289-110c-499e-98a4-6dff50bc93bd--c14392fb-3d89-440e-a56b-44a7e072a3cd","89636251572","37027116702875","2539067","89544667302","91584270"
      # "SRV-SQL-DEV-N02_SRV-SQL-DEV-N02_b053d289-110c-499e-98a4-6dff50bc93bd--11ca85b9-839d-4368-b9c6-eb7998d2d7d9","628113439","37027116702875","2539067","549465020","78648419"

      $vm_BytesReceivedPersec[0] = delta_get_hyp_val( 'Win32_PerfRawData_NvspNicStats_HyperVVirtualNetworkAdapter', 'BytesReceivedPersec', $hyp_data_comp_act, $hyp_data_comp_last, $entity );
      if ( $vm_BytesReceivedPersec[0] eq $UnDeF ) {
        if ( index( $entity, "(" ) ne -1 or index( $entity, ")" ) ne -1 ) {
          my $entity_ch = $entity;
          $entity_ch =~ s/\(/\[/g;
          $entity_ch =~ s/\)/\]/g;

          # print "3331 \$entity $entity \$entity_ch $entity_ch ,$vm_BytesReceivedPersec[0],\n";
          $vm_BytesReceivedPersec[0] = delta_get_hyp_val( 'Win32_PerfRawData_NvspNicStats_HyperVVirtualNetworkAdapter', 'BytesReceivedPersec', $hyp_data_comp_act, $hyp_data_comp_last, $entity_ch );
        }
      }
      if ( $vm_BytesReceivedPersec[0] eq $UnDeF && $vm_name_diff ne "" ) {
        $vm_BytesReceivedPersec[0] = delta_get_hyp_val( 'Win32_PerfRawData_NvspNicStats_HyperVVirtualNetworkAdapter', 'BytesReceivedPersec', $hyp_data_comp_act, $hyp_data_comp_last, $vm_name_diff );
      }
      if ( $vm_BytesReceivedPersec[0] ne $UnDeF ) {
        my @narr = split( ",", $vm_BytesReceivedPersec[0] );
        $vm_BytesReceivedPersec[0] = 0;
        foreach (@narr) { $vm_BytesReceivedPersec[0] += $_; }
        $vm_BytesReceivedPersec[0] /= $vm_time_coefficient;
      }

      $vm_BytesSentPersec[0] = delta_get_hyp_val( 'Win32_PerfRawData_NvspNicStats_HyperVVirtualNetworkAdapter', 'BytesSentPersec', $hyp_data_comp_act, $hyp_data_comp_last, $entity );
      if ( $vm_BytesSentPersec[0] eq $UnDeF ) {
        if ( index( $entity, "(" ) ne -1 or index( $entity, ")" ) ne -1 ) {
          my $entity_ch = $entity;
          $entity_ch =~ s/\(/\[/g;
          $entity_ch =~ s/\)/\]/g;
          $vm_BytesSentPersec[0] = delta_get_hyp_val( 'Win32_PerfRawData_NvspNicStats_HyperVVirtualNetworkAdapter', 'BytesSentPersec', $hyp_data_comp_act, $hyp_data_comp_last, $entity_ch );
        }
      }
      if ( $vm_BytesSentPersec[0] eq $UnDeF && $vm_name_diff ne "" ) {
        $vm_BytesSentPersec[0] = delta_get_hyp_val( 'Win32_PerfRawData_NvspNicStats_HyperVVirtualNetworkAdapter', 'BytesSentPersec', $hyp_data_comp_act, $hyp_data_comp_last, $vm_name_diff );
      }
      if ( $vm_BytesSentPersec[0] ne $UnDeF ) {
        my @narr = split( ",", $vm_BytesSentPersec[0] );
        $vm_BytesSentPersec[0] = 0;
        foreach (@narr) { $vm_BytesSentPersec[0] += $_; }
        $vm_BytesSentPersec[0] /= $vm_time_coefficient;
      }

      $vm_BytesTotalPersec[0] = delta_get_hyp_val( 'Win32_PerfRawData_NvspNicStats_HyperVVirtualNetworkAdapter', 'BytesPersec', $hyp_data_comp_act, $hyp_data_comp_last, $entity );
      if ( $vm_BytesTotalPersec[0] eq $UnDeF ) {
        if ( index( $entity, "(" ) ne -1 or index( $entity, ")" ) ne -1 ) {
          my $entity_ch = $entity;
          $entity_ch =~ s/\(/\[/g;
          $entity_ch =~ s/\)/\]/g;
          $vm_BytesTotalPersec[0] = delta_get_hyp_val( 'Win32_PerfRawData_NvspNicStats_HyperVVirtualNetworkAdapter', 'BytesPersec', $hyp_data_comp_act, $hyp_data_comp_last, $entity_ch );
        }
      }
      if ( $vm_BytesTotalPersec[0] eq $UnDeF && $vm_name_diff ne "" ) {
        $vm_BytesTotalPersec[0] = delta_get_hyp_val( 'Win32_PerfRawData_NvspNicStats_HyperVVirtualNetworkAdapter', 'BytesPersec', $hyp_data_comp_act, $hyp_data_comp_last, $vm_name_diff );
      }
      if ( $vm_BytesTotalPersec[0] ne $UnDeF ) {
        my @narr = split( ",", $vm_BytesTotalPersec[0] );
        $vm_BytesTotalPersec[0] = 0;
        foreach (@narr) { $vm_BytesTotalPersec[0] += $_; }
        $vm_BytesTotalPersec[0] /= $vm_time_coefficient;
      }

      # print "3032 $vm_BytesReceivedPersec[0] $vm_BytesSentPersec[0] $vm_BytesTotalPersec[0]  $entity\n";
    }
    if ( $vm_BytesReceivedPersec[0] eq $UnDeF && exists $$hyp_data_comp_act->{'Win32_PerfRawData_NvspPortStats_HyperVVirtualSwitchPort'} && exists $$hyp_data_comp_act->{'Msvm_ElementSettingData'} ) {

      $entity_uuid = get_hyp_val( 'Msvm_ComputerSystem', 'Name', $hyp_data_comp_act, $entity );
      print "Note           : (F$server_count) no data from Win32_PerfRawData_NvspNicStats_HyperVVirtualNetworkAdapter for entity $entity $entity_uuid\n";

      # way to identify switch port to VM, which is using it
      # CLASS: Msvm_ElementSettingData
      # "ManagedElement","SettingData"
      # "\\HVNODE01\root\virtualization\v2:Msvm_EthernetSwitchPort.CreationClassName="Msvm_EthernetSwitchPort",DeviceID="Microsoft:D71D793B-0D88-43E9-A66A-453C98082258",SystemCreationClassName="Msvm_VirtualEthernetSwitch",SystemName="6EB18D68-71D3-46AD-B6FF-CF1FD5256D8E"","\\HVNODE01\root\virtualization\v2:Msvm_EthernetPortAllocationSettingData.InstanceID="Microsoft:61538264-853B-43A0-99F5-DCFE083864C0\\d599bf62-f009-4ef2-add6-1d5892df4f3b\\C""
      # "\\HVNODE01\root\virtualization\v2:Msvm_EthernetSwitchPort.CreationClassName="Msvm_EthernetSwitchPort",DeviceID="Microsoft:D266985C-51AC-4C00-81E9-91A17B7E08AC",SystemCreationClassName="Msvm_VirtualEthernetSwitch",SystemName="6EB18D68-71D3-46AD-B6FF-CF1FD5256D8E"","\\HVNODE01\root\virtualization\v2:Msvm_EthernetPortAllocationSettingData.InstanceID="Microsoft:CBD9D469-A221-4228-816F-3860110150AD\\77392ce0-a661-4e13-8249-60c765b43746\\C""

      # CLASS: Win32_PerfRawData_NvspPortStats_HyperVVirtualSwitchPort
      # "Name","BytesPersec","Timestamp_PerfTime","Frequency_PerfTime","BytesReceivedPersec","BytesSentPersec"
      # "6EB18D68-71D3-46AD-B6FF-CF1FD5256D8E_D71D793B-0D88-43E9-A66A-453C98082258","23934152268","61482940656805","2994772","101419968","23832732300"
      # "6EB18D68-71D3-46AD-B6FF-CF1FD5256D8E_D266985C-51AC-4C00-81E9-91A17B7E08AC","170350118","61482940656805","2994772","13672846","156677272"

      # CLASS: Msvm_ComputerSystem
      # "Name","Caption","Description","ElementName","EnabledState","HealthState","NumberOfNumaNodes","OperatingStatus","Status","StatusDescriptions"
      # "HVNODE01","Hosting Computer System","Microsoft Hosting Computer System","HVNODE01","2","5","1",,"OK","OK"
      # "61538264-853B-43A0-99F5-DCFE083864C0","Virtual Machine","Microsoft Virtual Machine","hvlinux02","2","5","1",,"OK","Operating normally"
      # "CBD9D469-A221-4228-816F-3860110150AD","Virtual Machine","Microsoft Virtual Machine","hvlinux01","2","5","1",,"OK","Operating normally"

      my @vm_ports_m_e = split( ",", get_hyp_val( 'Msvm_ElementSettingData', 'ManagedElement', $hyp_data_comp_act, 'Msvm_EthernetSwitchPort' ) );
      my @vm_ports_s_d = split( ",", get_hyp_val( 'Msvm_ElementSettingData', 'SettingData',    $hyp_data_comp_act, 'Msvm_EthernetSwitchPort' ) );

      # print "3057 \@vm_ports_s_d       : (F$server_count) @vm_ports_s_d\n @vm_ports_m_e\n";
      my ($index) = grep { $vm_ports_s_d[$_] =~ $entity_uuid } 0 .. $#vm_ports_s_d;    # is it  ?
      print "3059 \$index $index found $entity_uuid\n";
      my $vm_port = $vm_ports_m_e[$index];
      print "3061 \$vm_port $vm_port\n";
      $vm_port =~ s/.*.DeviceID="Microsoft://;
      $vm_port =~ s/".SystemCreation.*//;
      print "3064 \$vm_port $vm_port\n";
      $vm_BytesReceivedPersec[0] = delta_get_hyp_val( 'Win32_PerfRawData_NvspPortStats_HyperVVirtualSwitchPort', 'BytesSentPersec', $hyp_data_comp_act, $hyp_data_comp_last, $vm_port );
      $vm_BytesReceivedPersec[0] /= $vm_time_coefficient;
      $vm_BytesSentPersec[0] = delta_get_hyp_val( 'Win32_PerfRawData_NvspPortStats_HyperVVirtualSwitchPort', 'BytesReceivedPersec', $hyp_data_comp_act, $hyp_data_comp_last, $vm_port );
      $vm_BytesSentPersec[0] /= $vm_time_coefficient;
      $vm_BytesTotalPersec[0] = $vm_BytesReceivedPersec[0] + $vm_BytesSentPersec[0];

      # print "3068 $vm_BytesReceivedPersec[0] $vm_BytesSentPersec[0] $vm_BytesTotalPersec[0]\n";

    }
    else {
      print "Note           : (F$server_count) no data from Win32_PerfRawData_NvspPortStats_HyperVVirtualSwitchPort or Msvm_ElementSettingData\n";
      $vm_BytesReceivedPersec[0] = "U" if $vm_BytesReceivedPersec[0] eq $UnDeF;
      $vm_BytesSentPersec[0]     = "U" if $vm_BytesSentPersec[0] eq $UnDeF;
      $vm_BytesTotalPersec[0]    = "U" if $vm_BytesTotalPersec[0] eq $UnDeF;
    }

    $vm_vCPU[0] = "$vm_name_vcpu{$entity}";

    # CPU
    #
    # class: Win32_PerfRawData_HvStats_HyperVHypervisorVirtualProcessor
    # Frequency_PerfTime|Name|PercentTotalRunTime|Timestamp_PerfTime
    # 3117912|WinXP:Hv VP 1|3272009389048|6220968390660
    # 3117912|WinXP:Hv VP 0|3283077517400|6220968390660
    # 3117912|XoruX-master:Hv VP 1|9806837924|6220968390660
    # 3117912|XoruX-master:Hv VP 0|14282384764|6220968390660
    # 3117912|CentOS01:Hv VP 0|57059017497|6220968390660
    # 3117912|_Total|6636235146633|6220968390660

    my $summ      = 0;
    my @value_arr = "";

    my $values = delta_get_hyp_val( 'Win32_PerfRawData_HvStats_HyperVHypervisorVirtualProcessor', 'PercentTotalRunTime', $hyp_data_comp_act, $hyp_data_comp_last, $entity );

    # print "2893 \$values ,$values, \$entity $entity\n";
    if ( $values eq "" || $values eq $UnDeF ) {    # something wrong, if Name contains '(' or ')' try againg with '[' or ']'
      if ( index( $entity, "(" ) ne -1 or index( $entity, ")" ) ne -1 ) {
        my $entity_ch = $entity;
        $entity_ch =~ s/\(/\[/g;
        $entity_ch =~ s/\)/\]/g;
        $values = delta_get_hyp_val( 'Win32_PerfRawData_HvStats_HyperVHypervisorVirtualProcessor', 'PercentTotalRunTime', $hyp_data_comp_act, $hyp_data_comp_last, $entity_ch );
      }
    }
    if ( ( $values eq "" || $values eq $UnDeF ) && $vm_name_diff ne "" ) {
      $values = delta_get_hyp_val( 'Win32_PerfRawData_HvStats_HyperVHypervisorVirtualProcessor', 'PercentTotalRunTime', $hyp_data_comp_act, $hyp_data_comp_last, $vm_name_diff );
    }
    if ( $values eq "" || $values eq $UnDeF ) {
      error( "(F$server_count) not valid vm_Timestamp_PerfTime[0] for entity $entity " . __FILE__ . ":" . __LINE__ );
      $vm_PercentTotalRunTime[0] = "U";
    }
    else {
      @value_arr = split( /,/, $values );
      $summ      = 0;
      if ( $vm_name_vcpu{$entity} ne $UnDeF ) {
        for ( my $i = 0; $i < $vm_name_vcpu{$entity}; $i++ ) {
          $summ += $value_arr[$i] if defined $value_arr[$i] && $value_arr[$i] ne $UnDeF;
        }
        $vm_PercentTotalRunTime[0] = int( $summ / $vm_name_vcpu{$entity} );    # in case of 2012
                                                                               # $vm_PercentTotalRunTime[0] = int ($summ);
      }
    }

    # print "2917 \$values ,$values, \$entity $entity\n";
    $values = delta_get_hyp_val( 'Win32_PerfRawData_HvStats_HyperVHypervisorVirtualProcessor', 'Timestamp_PerfTime', $hyp_data_comp_act, $hyp_data_comp_last, $entity );
    if ( $values eq "" || $values eq $UnDeF ) {    # something wrong, if Name contains '(' or ')' try againg with '[' or ']'
      if ( index( $entity, "(" ) ne -1 or index( $entity, ")" ) ne -1 ) {
        my $entity_ch = $entity;
        $entity_ch =~ s/\(/\[/g;
        $entity_ch =~ s/\)/\]/g;
        $values = delta_get_hyp_val( 'Win32_PerfRawData_HvStats_HyperVHypervisorVirtualProcessor', 'Timestamp_PerfTime', $hyp_data_comp_act, $hyp_data_comp_last, $entity_ch );
      }
    }
    if ( ( $values eq "" || $values eq $UnDeF ) && $vm_name_diff ne "" ) {
      $values = delta_get_hyp_val( 'Win32_PerfRawData_HvStats_HyperVHypervisorVirtualProcessor', 'Timestamp_PerfTime', $hyp_data_comp_act, $hyp_data_comp_last, $vm_name_diff );
    }
    if ( $values eq "" || $values eq $UnDeF ) {
      error( "(F$server_count) not valid vm_Timestamp_PerfTime[0] for entity $entity " . __FILE__ . ":" . __LINE__ );
      $vm_Timestamp_PerfTime[0] = "U";
    }
    else {
      # $vm_Timestamp_PerfTime[0] = int ($summ / $vm_name_vcpu{$entity});
      # $vm_Timestamp_PerfTime[0] = int($summ);  # no, you cannot make summ here, get only one time difference e.g. 1st
      $vm_Timestamp_PerfTime[0] = ( split( /,/, $values ) )[0];
      if ( $vm_Timestamp_PerfTime[0] eq "" ) {
        print "Note           : (F$server_count) not valid vm_Timestamp_PerfTime[0]\n";
        $vm_Timestamp_PerfTime[0] = "U";
      }
    }
    print "\$entity $entity \$vm_PercentTotalRunTime[0] $vm_PercentTotalRunTime[0] \$vm_Timestamp_PerfTime[0] $vm_Timestamp_PerfTime[0]\n" if $DEBUG == 2;

    # $DEBUG = 0;
    # return;
  }
  else {    # host_system
            #
    ### data digging
    #

    # in case of standalone windows
    if ( $vm_vCPU[0] eq "U" ) {
      if ( exists $$hyp_data_comp_act->{'Win32_ComputerSystem'} ) {
        $vm_vCPU[0] = get_hyp_val( 'Win32_ComputerSystem', 'NumberOfProcessors', $hyp_data_comp_act );
      }
      if ( $vm_vCPU[0] eq $UnDeF || $vm_vCPU[0] eq "U" ) {
        $vm_vCPU[0] = get_hyp_val( 'Win32_Processor', 'NumberOfCores', $hyp_data_comp_act );
        if ( $vm_vCPU[0] ne $UnDeF ) {
          my @num_cpu = split( ",", $vm_vCPU[0] );
          my $suma    = 0;
          foreach my $num_proc (@num_cpu) {
            $suma += $num_proc;
          }
          $vm_vCPU[0] = $suma;

          # print "3440 \$vm_vCPU[0] $vm_vCPU[0] \@num_cpu @num_cpu\n";
        }
      }
      if ( not isdigit( $vm_vCPU[0] ) ) {
        $vm_vCPU[0] = "U";
        error( "(F$server_count) cannot get vm_vCPU[0] for standalone windows" . __FILE__ . ":" . __LINE__ );
      }

      # print "3362 \$vm_vCPU[0] $vm_vCPU[0]\n";
      # print Dumper($$hyp_data_comp_act->{'Win32_Processor'});
      print_hyperv_debug("2766 \$vm_vCPU[0] $vm_vCPU[0] standalone windows ?\n") if $DEBUG == 2;
    }

    $vm_PercentTotalRunTime[0] = "";

    my $standalone = 0;

    # comment following 'if clause' for using PerfOS counter - i.e. without hyperv counter
    if ( exists $$hyp_data_comp_act->{'Win32_PerfRawData_HvStats_HyperVHypervisorLogicalProcessor'} ) {
      $vm_PercentTotalRunTime[0] = delta_get_hyp_val( 'Win32_PerfRawData_HvStats_HyperVHypervisorLogicalProcessor', 'PercentTotalRunTime', $hyp_data_comp_act, $hyp_data_comp_last, '_Total' );
      unlink "$wrkdir/$managedname/standalone";
    }

    # print "3528 \$vm_PercentTotalRunTime[0] $vm_PercentTotalRunTime[0]\n";
    my $source_vm_PercentTotalRunTime = "source_vm_PercentTotalRunTime";
    my $source_vm_Timestamp_PerfTime  = "source_vm_Timestamp_PerfTime";
    if ( $vm_PercentTotalRunTime[0] eq "" ) {

      # probably standalone windows !!! use PercentProcessorTime
      # old win e.g. 2008 does not have PercentProcessorTime and Timestamp_Sys100NS so use PercentUserTime and Timestamp_PerfTime
      if ( exists $$hyp_data_comp_act->{'Win32_PerfRawData_PerfOS_Processor'} && exists $$hyp_data_comp_last->{'Win32_PerfRawData_PerfOS_Processor'} ) {
        if ( index( $$hyp_data_comp_act->{'Win32_PerfRawData_PerfOS_Processor'}[0], "PercentProcessorTime" ) != -1 ) {
          $vm_PercentTotalRunTime[0] = delta_get_hyp_val( 'Win32_PerfRawData_PerfOS_Processor', 'PercentProcessorTime', $hyp_data_comp_act, $hyp_data_comp_last, '_Total' );
          $source_vm_PercentTotalRunTime = "PercentProcessorTime";
        }
        else {
          $vm_PercentTotalRunTime[0] = delta_get_hyp_val( 'Win32_PerfRawData_PerfOS_Processor', 'PercentUserTime', $hyp_data_comp_act, $hyp_data_comp_last, '_Total' );
          $source_vm_PercentTotalRunTime = "PercentUserTime";
        }
        if ( $vm_PercentTotalRunTime[0] eq $UnDeF ) {    # || ($managedname eq "DESKTOP-ISG7U4Q" || $managedname eq "DESKTOP-O79DK45")) l_curly # probably old win agent
                                                         # not sufficient data
          print_hyperv_debug("3740 no data for Win32_PerfRawData_PerfOS_Processor - exiting\n");
          return;
        }
        system("touch $wrkdir/$managedname/standalone");
        $standalone = 1;
        print "standalone     : file $wrkdir/$managedname/standalone has been touched\n";
      }
      else {
        # not sufficient data
        print_hyperv_debug("3749 no data for Win32_PerfRawData_PerfOS_Processor - exiting\n");
        return;
      }
    }

    # print "3540 \$vm_PercentTotalRunTime[0] $vm_PercentTotalRunTime[0]\n";
    $vm_Timestamp_PerfTime[0] = "";

    # comment following 'if clause' for using PerfOS counter - i.e. without hyperv counter (debug purpose)
    if ( exists $$hyp_data_comp_act->{'Win32_PerfRawData_HvStats_HyperVHypervisorLogicalProcessor'} ) {
      $vm_Timestamp_PerfTime[0] = delta_get_hyp_val( 'Win32_PerfRawData_HvStats_HyperVHypervisorLogicalProcessor', 'Timestamp_PerfTime', $hyp_data_comp_act, $hyp_data_comp_last, '_Total' );
    }

    # print "3547 \$vm_Timestamp_PerfTime[0] $vm_Timestamp_PerfTime[0]\n";
    if ( $vm_Timestamp_PerfTime[0] eq "" ) {    # !!! use Timestamp_Sys100NS
      if ( exists $$hyp_data_comp_act->{'Win32_PerfRawData_PerfOS_Processor'} && exists $$hyp_data_comp_last->{'Win32_PerfRawData_PerfOS_Processor'} ) {
        if ( index( $$hyp_data_comp_act->{'Win32_PerfRawData_PerfOS_Processor'}[0], "Timestamp_Sys100NS" ) != -1 ) {
          $vm_Timestamp_PerfTime[0] = delta_get_hyp_val( 'Win32_PerfRawData_PerfOS_Processor', 'Timestamp_Sys100NS', $hyp_data_comp_act, $hyp_data_comp_last, '_Total' );
          $source_vm_Timestamp_PerfTime = "Timestamp_Sys100NS";
        }
        else {
          $vm_Timestamp_PerfTime[0] = delta_get_hyp_val( 'Win32_PerfRawData_PerfOS_Processor', 'Timestamp_PerfTime', $hyp_data_comp_act, $hyp_data_comp_last, '_Total' );
          $source_vm_Timestamp_PerfTime = "Timestamp_PerfTime";
        }
      }
      if ( ( $vm_Timestamp_PerfTime[0] eq $UnDeF ) or ( $vm_Timestamp_PerfTime[0] eq "" ) ) {    # || ($managedname eq "DESKTOP-ISG7U4Q" || $managedname eq "DESKTOP-O79DK45")) l_curly # probably old win agent
        print_hyperv_debug("3772 no data for Win32_PerfRawData_PerfOS_Processor - exiting\n");
        return;
      }
    }

    # print "3557 \$vm_Timestamp_PerfTime[0] $vm_Timestamp_PerfTime[0] \$vm_Frequency_PerfTime[0] $vm_Frequency_PerfTime[0] \$vm_PercentTotalRunTime[0] $vm_PercentTotalRunTime[0]\n";

    # special case ERR DATA from Win32_PerfRawData_PerfOS_Processor','PercentProcessorTime' delta is < 0, delta_get_hyp_val returns 0 # no, it is not err
    # print "3758 \$vm_PercentTotalRunTime[0] ,$vm_PercentTotalRunTime[0],\n";
    if ( $standalone && ( $vm_PercentTotalRunTime[0] > $vm_Timestamp_PerfTime[0] ) ) {
      error( "Win32_PerfRawData_PerfOS_Processor',$source_vm_PercentTotalRunTime ($vm_PercentTotalRunTime[0]) > $source_vm_Timestamp_PerfTime ($vm_Timestamp_PerfTime[0]), BAD DATA (corrected)" . __FILE__ . ":" . __LINE__ );
      $vm_PercentTotalRunTime[0] = $vm_Timestamp_PerfTime[0];
    }

    # if ($vm_PercentTotalRunTime[0] == 0) {
    #  # $vm_PercentTotalRunTime[0] = $vm_Timestamp_PerfTime[0];
    #  error( "delta Win32_PerfRawData_PerfOS_Processor','PercentProcessorTime' is 0, BAD DATA ($vm_PercentTotalRunTime[0]) " . __FILE__ . ":" . __LINE__ );
    # }
    # print "3763 \$vm_Timestamp_PerfTime[0] $vm_Timestamp_PerfTime[0] \$vm_Frequency_PerfTime[0] $vm_Frequency_PerfTime[0] \$vm_PercentTotalRunTime[0] $vm_PercentTotalRunTime[0]\n";

    $vm_AvailableMBytes[0] = get_hyp_val( 'Win32_PerfRawData_PerfOS_Memory', 'AvailableMbytes', $hyp_data_comp_act );
    $vm_CacheBytes[0]      = get_hyp_val( 'Win32_PerfRawData_PerfOS_Memory', 'CacheBytes',      $hyp_data_comp_act );
    my $vm_time_step        = delta_get_hyp_val( 'Win32_PerfRawData_PerfOS_Memory', 'Hyperv_UTC', $hyp_data_comp_act, $hyp_data_comp_last );
    my $vm_time_coefficient = $vm_time_step / 300;                                                                                             #  adjusted to 5 minutes base
    if ( $vm_time_coefficient < 1 ) {                                                                                                          # can happen when another (debug) load from cmd line or so
      $vm_time_coefficient = 1;
    }
    print_hyperv_debug("3012 \$vm_AvailableMBytes[0] $vm_AvailableMBytes[0] \$vm_CacheBytes[0] $vm_CacheBytes[0] \$vm_time_step $vm_time_step\n") if $DEBUG == 2;
    $vm_PagesInputPersec[0] = delta_get_hyp_val( 'Win32_PerfRawData_PerfOS_Memory', 'PagesInputPersec', $hyp_data_comp_act, $hyp_data_comp_last );
    $vm_PagesInputPersec[0] /= $vm_time_coefficient;
    $vm_PagesOutputPersec[0] = delta_get_hyp_val( 'Win32_PerfRawData_PerfOS_Memory', 'PagesOutputPersec', $hyp_data_comp_act, $hyp_data_comp_last );
    $vm_PagesOutputPersec[0] /= $vm_time_coefficient;

    # CLASS: Win32_PageFileUsage
    # "AllocatedBaseSize","CurrentUsage","Name","Status"
    # "9729","1312","C:\pagefile.sys",
    # there can be more pagefiles in different discs
    if ( exists $$hyp_data_comp_act->{'Win32_PageFileUsage'} ) {
      $vm_DiskBytesPersec[0] = get_hyp_val( 'Win32_PageFileUsage', 'AllocatedBaseSize', $hyp_data_comp_act );
      if ( index( $vm_DiskBytesPersec[0], "," ) ne -1 ) {
        my $sum   = 0;
        my @array = split( ",", $vm_DiskBytesPersec[0] );
        for (@array) {
          $sum += $_;
        }
        $vm_DiskBytesPersec[0] = $sum;
      }
      $vm_DiskTransfersPersec[0] = get_hyp_val( 'Win32_PageFileUsage', 'CurrentUsage', $hyp_data_comp_act );
      if ( index( $vm_DiskTransfersPersec[0], "," ) ne -1 ) {
        my $sum   = 0;
        my @array = split( ",", $vm_DiskTransfersPersec[0] );
        for (@array) {
          $sum += $_;
        }
        $vm_DiskTransfersPersec[0] = $sum;
      }
      my $page_file_path      = get_hyp_val( 'Win32_PageFileUsage', 'Name', $hyp_data_comp_act );
      my $page_file_name_save = "$wrkdir/$managedname/$host/page_file_name.txt";
      if ( open my $FH, ">", "$page_file_name_save" ) {
        print $FH "$page_file_path";
        close FH;
      }
      else {
        error( "can't open $page_file_name_save: $!" . __FILE__ . ":" . __LINE__ );
      }

      # print "3078 \$vm_DiskBytesPersec[0] $vm_DiskBytesPersec[0] \$vm_DiskTransfersPersec[0] $vm_DiskTransfersPersec[0]\n";
      # print Dumper (3079, $$hyp_data_comp_act->{'Win32_PageFileUsage'});

      # necessary to cleanup old data
      $$hyp_data_comp_act->{'Win32_PageFileUsage'} = ();

      # print STDERR "3078 server page file is $page_file_path in $page_file_name_save\n";
      # in case more page files
      # 3078 $vm_DiskBytesPersec[0] 1280,4096 $vm_DiskTransfersPersec[0] 21,86
      # $VAR1 = 3079;
      # $VAR2 = [
      #           '"AllocatedBaseSize","CurrentUsage","Name","Status",Hyperv_UTC',
      #           '"1280","21","C:\\pagefile.sys",,1662638175',
      #           '"4096","86","D:\\pagefile.sys",,1662638175'
      #         ];
    }
    else {
      $vm_DiskBytesPersec[0]     = "U";
      $vm_DiskTransfersPersec[0] = "U";
    }

    # CLASS: Win32_PerfRawData_PerfDisk_PhysicalDisk

    $vm_DiskReadBytesPersec[0] = "U";
    $vm_DiskReadsPersec[0]     = "U";
    $vm_DiskWriteBytesPerse[0] = "U";
    $vm_DiskWritesPersec[0]    = "U";

    if ( exists $$hyp_data_comp_act->{'Win32_PerfRawData_PerfDisk_PhysicalDisk'} && exists $$hyp_data_comp_last->{'Win32_PerfRawData_PerfDisk_PhysicalDisk'} ) {

      #    $vm_DiskBytesPersec[0] = delta_get_hyp_val('Win32_PerfRawData_PerfDisk_PhysicalDisk','DiskBytesPersec', $hyp_data_comp_act, $hyp_data_comp_last,'_Total');
      $vm_DiskReadBytesPersec[0] = delta_get_hyp_val( 'Win32_PerfRawData_PerfDisk_PhysicalDisk', 'DiskReadBytesPersec', $hyp_data_comp_act, $hyp_data_comp_last, '_Total' );
      $vm_DiskReadBytesPersec[0] = "U" if !defined $vm_DiskReadBytesPersec[0] or $vm_DiskReadBytesPersec[0] eq $UnDeF;

      $vm_DiskReadsPersec[0] = delta_get_hyp_val( 'Win32_PerfRawData_PerfDisk_PhysicalDisk', 'DiskReadsPersec', $hyp_data_comp_act, $hyp_data_comp_last, '_Total' );
      $vm_DiskReadsPersec[0] = "U" if !defined $vm_DiskReadsPersec[0] or $vm_DiskReadsPersec[0] eq $UnDeF;

      #    $vm_DiskTransfersPersec[0] = delta_get_hyp_val('Win32_PerfRawData_PerfDisk_PhysicalDisk','DiskTransfersPersec', $hyp_data_comp_act, $hyp_data_comp_last,'_Total');
      $vm_DiskWriteBytesPerse[0] = delta_get_hyp_val( 'Win32_PerfRawData_PerfDisk_PhysicalDisk', 'DiskWriteBytesPersec', $hyp_data_comp_act, $hyp_data_comp_last, '_Total' );
      $vm_DiskWriteBytesPerse[0] = "U" if !defined $vm_DiskWriteBytesPerse[0] or $vm_DiskWriteBytesPerse[0] eq $UnDeF;

      $vm_DiskWritesPersec[0] = delta_get_hyp_val( 'Win32_PerfRawData_PerfDisk_PhysicalDisk', 'DiskWritesPersec', $hyp_data_comp_act, $hyp_data_comp_last, '_Total' );
      $vm_DiskWritesPersec[0] = "U" if !defined $vm_DiskWritesPersec[0] or $vm_DiskWritesPersec[0] eq $UnDeF;
    }

    # CLASS: Win32_PerfRawData_Tcpip_NetworkInterface

    my @values = split( ",", delta_get_hyp_val( 'Win32_PerfRawData_Tcpip_NetworkInterface', 'BytesReceivedPersec', $hyp_data_comp_act, $hyp_data_comp_last ) );

    # prepare summ
    # example 16038813212 0 501059 0 0 0
    # print stderr "2452, hyp2rrd.pl \@values @values\n";
    $vm_BytesReceivedPersec[0] = eval join '+', @values;
    @values                    = split( ",", delta_get_hyp_val( 'Win32_PerfRawData_Tcpip_NetworkInterface', 'BytesSentPersec', $hyp_data_comp_act, $hyp_data_comp_last ) );
    $vm_BytesSentPersec[0]     = eval join '+', @values;
    @values                    = split( ",", delta_get_hyp_val( 'Win32_PerfRawData_Tcpip_NetworkInterface', 'BytesTotalPersec', $hyp_data_comp_act, $hyp_data_comp_last ) );
    $vm_BytesTotalPersec[0]    = eval join '+', @values;

    # win processes: JOB graphs
    #
    if ( exists $$hyp_data_comp_act->{'Win32_Process'} ) {

      # print "3790 Process -----------------------------------start\n";
      # print Dumper $$hyp_data_comp_act->{'Win32_Process'};

      my $line = $$hyp_data_comp_act->{'Win32_Process'}[1];

      # $line "System Idle Process","0","0","8192",1630567256
      ( undef, undef, undef, undef, my $hyp_utc, undef ) = split ",", $line;

      # print "3794 Process \$line $line \$hyp_utc $hyp_utc for data in $pth for \$managedname $managedname\n";
      my $managedname_dir     = "$pth/$managedname";
      my $job_managedname_dir = "$pth/$managedname/JOB/";

      # create JOB dir if it is not
      my $dirs_ok = 1;
      if ( ( -e $managedname_dir or mkdir $managedname_dir ) and ( -e $job_managedname_dir or mkdir $job_managedname_dir ) ) {

      }
      else {
        error( "cannot create job dir " . __FILE__ . ":" . __LINE__ );
        $dirs_ok = 0;
      }
      my $dirios;
      my @process_files = ();
      if ( opendir( $dirios, "$job_managedname_dir" ) ) {
        @process_files = grep /\d{10}\.txt$/, readdir($dirios);
      }
      else {
        error("cannot open dir $job_managedname_dir");
        @process_files = ();
      }
      if ( !scalar @process_files ) {

        # 1st file always save
        my $file_name = "$job_managedname_dir/$hyp_utc" . ".txt";
        if ( open FH, ">$file_name" ) {
          print FH join "\n", @{ $$hyp_data_comp_act->{'Win32_Process'} };
          print FH "\n";
          close FH;
        }
        else {
          error( "can't open $file_name: $!" . __FILE__ . ":" . __LINE__ );
        }
      }
      else {    # save only if time is in new half_hour since latest file
                # take the time from latest file name
        my $latest_file_name = ( sort @process_files )[-1];
        $latest_file_name =~ s/\.txt//;
        my $latest_time = $latest_file_name;
        if ( $latest_time !~ /\d\d\d\d\d\d\d\d\d\d/ ) {
          error( "bad file name \$latest_file_name $latest_file_name, skip processes lines " . __FILE__ . ":" . __LINE__ );
        }
        else {
          # get next half_time time
          $latest_time = ( int( $latest_time / 1800 ) + 1 ) * 1800;
          $latest_time = $latest_time + 100;                          # it seems to be better, it must be more than half hour
          if ( $hyp_utc > $latest_time ) {

            # print "3846 \$latest_file_name $latest_file_name \$latest_time $latest_time \$hyp_utc $hyp_utc\n";
            my $file_name = "$job_managedname_dir/$hyp_utc" . ".txt";
            if ( open FH, ">$file_name" ) {
              print FH join "\n", @{ $$hyp_data_comp_act->{'Win32_Process'} };
              print FH "\n";
              close FH;
              push @process_files, "$hyp_utc" . ".txt";
            }
            else {
              error( "can't open $file_name: $!" . __FILE__ . ":" . __LINE__ );
            }
          }
        }
      }

      # print "3862 \@process_files ,@process_files,\n";
      print "Process        : process files count = " . scalar @process_files . "\n";

      # saving process' data to rrd files
      my @process_files_sorted = sort @process_files;
      for ( my $i = 0; $i < ( scalar @process_files_sorted ) - 1; $i++ ) {
        my $file1 = "$job_managedname_dir/$process_files_sorted[$i]";
        my $file2 = "$job_managedname_dir/$process_files_sorted[$i+1]";
        print "Process        : files for reading data $file1 $file2\n";

        # remove files older 7 days
        if ( -M $file1 > 7 ) {
          print "- - - - - - file is older 7 days $file1, removing it\n";
          unlink $file1;
          next;
        }

        # test files time diff - must be less 1 hour
        my $low = $process_files_sorted[$i];
        $low =~ s/\.txt//;
        my $hig = $process_files_sorted[ $i + 1 ];
        $hig =~ s/\.txt//;
        my $time_diff_update = $hig - $low;

        # round time to lower half  hour border
        $hig = int( $hig / 1800 ) * 1800;
        if ( $time_diff_update > 3600 ) {    # will be removed after 7 days
          print "- - - - - - files time diff is $time_diff_update, skipping it\n";
          next;
        }

        my %pok1 = ();
        my %pok2 = ();

        open( my $file_d, "<", $file1 );
        while (<$file_d>) {
          my $line = $_;
          chomp $line;
          next if $line eq "" or $line eq " ";

          # "RuntimeBroker.exe","8996","156250","6516736"
          $line =~ s/\"//g;
          ( my $name, my $job_no, my $cpu_sec, my $mem_byte ) = split( ",", $line );
          next if $cpu_sec  !~ /^\d*$/;    # only digits
          next if $mem_byte !~ /^\d*$/;
          my $ident = "$name" . "_XORUX_" . "$job_no";
          $pok1{$ident}{CPU} = $cpu_sec;
          $pok1{$ident}{MEM} = $mem_byte / 1024;
        }
        close $file_d;
        open( $file_d, "<", $file2 );
        while (<$file_d>) {
          my $line = $_;
          chomp $line;
          next if $line eq "";

          # "RuntimeBroker.exe","8996","156250","6516736"
          $line =~ s/\"//g;
          ( my $name, my $job_no, my $cpu_sec, my $mem_byte ) = split( ",", $line );
          next if $cpu_sec  !~ /^\d*$/;    # only digits
          next if $mem_byte !~ /^\d*$/;
          my $ident = "$name" . "_XORUX_" . "$job_no";
          $pok2{$ident}{CPU} = $cpu_sec;
          $pok2{$ident}{MEM} = $mem_byte;
        }
        close $file_d;

        #print Dumper \%pok1, \%pok2;
        my %result = ();
        keys %pok1;    # reset the internal iterator so a prior each() doesn't affect the loop
        while ( my ( $k, $v ) = each %pok1 ) {

          # print Dumper($k, $v);
          if ( !exists $pok2{$k} ) {

            # print "3913 ! exists key $k\n";
            next;
          }
          my $diff = $pok2{$k}{CPU} - $pok1{$k}{CPU};

          # next if $diff <1;
          # for CPU prepare the difference, time is the newer
          $result{$k}{CPU} = $diff / 10000000;    # Time in user mode, in 100 nanosecond units > to be in seconds
          $result{$k}{MEM} = $pok2{$k}{MEM};
        }

        # print Dumper \%result;
        # sort hash according CPU values, only top ten
        my $top            = 0;
        my $top_ten        = 15;
        my @update_strings = ();

        # prepare top ten jobs with time_diff > 1 sec, or at least 2 jobs if there are not those
        foreach my $name ( sort { $result{$b}{CPU} <=> $result{$a}{CPU} } keys %result ) {

          # print "$name $result{$name}{CPU} $result{$name}{MEM}\n";
          $name =~ s/:/===colon===/g;
          if ( $top > 1 ) {
            last if ( $result{$name}{CPU} < 1 );
          }
          push @update_strings, "$name:$result{$name}{CPU}:" . $result{$name}{MEM} / 1024;    # MEM to be in GB
          last if ++$top >= $top_ten;
        }
        $top = 0;
        foreach (@update_strings) {

          # Discord.exe_XORUX_10288:123:456
          ( my $job_name_pid, my $cpu, my $mem ) = split ":", $_;
          ( my $job_name, my $pid ) = split "_XORUX_", $job_name_pid;
          my $type_sam         = "c";
          my $no_time          = 1800;
          my $input_vm_uuid    = "JOB/CPUTOP$top";
          my $managedname_save = $managedname;
          my $host_save        = $host;

          my $update_string = "$hig,$pid,$cpu,$mem,U";

          # print "3964 \$update_string = $update_string for \$input_vm_uuid $input_vm_uuid\n";
          # 3964 $update_string = 1635426053 5020:1732.25:18694144:U for $input_vm_uuid JOB/CPUTOP0

          # print "$managedname_save, $host_save, $wrkdir, \$update_string, $type_sam, $act_time, \$job_name, $IVM, $SDMC, $step, $DEBUG, \@lpar_trans, $last_file, $no_time, $SSH, $hmc_user, $input_vm_uuid, $entity_type\n";
          # DESKTOP-O79DK45, , /home/lpar2rrd/lpar2rrd/data/windows/domain_WORKGROUP, $update_string, , Thu Nov  4 13:27:46 2021, 1, 0, 0, 60, 1, @lpar_trans, last.txt, 1800, ssh -q -o ConnectTimeout=80 -o StrictHostKeyChecking=no -o PreferredAuthentications=publickey  -q , lpar2rrd, JOB/CPUTOP0, HostSystem

          my $res_update = LoadDataModuleHyperV::load_data( $managedname_save, $host_save, $wrkdir, \$update_string, $type_sam, $act_time, \$job_name, $IVM, $SDMC, $step, $DEBUG, \@lpar_trans, $last_file, $no_time, $SSH, $hmc_user, $input_vm_uuid, $entity_type, "(F$server_count)" );

          $top++;
        }
        #
        if ( -f "$job_managedname_dir/keep_files" ) {
          rename( "$file1", "$file1.snd" ) || error( " Cannot mv $file1 $file1.snd: $!" . __FILE__ . ":" . __LINE__ );
        }
        else {
          unlink $file1;
          unlink glob("$job_managedname_dir/*.snd");    # unlink glob('path/to/folder/*.trg');

        }

        #last; # if debug
      }
    }
  }

  my $samples_number_must = 1;

  my $values;

  $samples_number = 1;
  my $entity_name = $entity;
  $entity_name = $entity->{'name'} if $entity_nick =~ /HS/;
  print "fetching " . $entity_nick . $entity_name . " refreshRate=$refreshRate real_sampling_period=$real_sampling_period samples_expected X real=$samples_number_must X $samples_number (F$server_count)\n" if $DEBUG;

  my $first_time_stamp_unix = $UnDeF;
  if ( exists $$hyp_data_comp_act->{'Win32_PerfRawData_HvStats_HyperVHypervisorLogicalProcessor'} ) {
    $first_time_stamp_unix = get_hyp_val( 'Win32_PerfRawData_HvStats_HyperVHypervisorLogicalProcessor', 'Hyperv_UTC', $hyp_data_comp_act, '_Total' );
  }
  if ( !defined $first_time_stamp_unix || $first_time_stamp_unix eq $UnDeF ) {

    # error( "(F$server_count) not valid data timestamp $first_time_stamp_unix, use \$command_unix $command_unix instead " . __FILE__ . ":" . __LINE__ ) ; # && return 0;
    print "Note           : (F$server_count) not valid data timestamp $first_time_stamp_unix, use \$command_unix $command_unix instead\n";

    # could be stand alone windows > use original machine time
    $first_time_stamp_unix = $command_unix;
  }

  my @vm_time_stamps = ();
  $vm_time_stamps[0] = $first_time_stamp_unix;

  # prepare other metrics array with 'U'

  if ( ( $entity_type eq $et_HostSystem ) || ( $entity_type eq $et_VirtualMachine ) ) {

    #          @vm_Frequency_PerfTime       = ($host_hz)x $samples_number;
    #          @vm_PercentTotalRunTime      = ($PercentTotalRunTime)x $samples_number;
    #          @vm_Timestamp_PerfTime       = ($Timestamp_PerfTime)x $samples_number;
    #          @vm_Memory_active_KB         = ('U')x $samples_number;
    #          @vm_Memory_granted_KB        = ('U')x $samples_number;
    #          @vm_Memory_baloon_MB         = ('U')x $samples_number;
    #          @vm_Disk_usage_KBps          = ('U')x $samples_number;
    #          @vm_Disk_read_KBps           = ('U')x $samples_number;
    #          @vm_Disk_write_KBps          = ('U')x $samples_number;
    #          @vm_Network_usage_KBps       = ('U')x $samples_number;
    #          @vm_Network_received_KBps    = ('U')x $samples_number;
    #          @vm_Network_transmitted_KBps = ('U')x $samples_number;
    #          @vm_Memory_swapin_KBps       = ('U')x $samples_number;
    #          @vm_Memory_swapout_KBps      = ('U')x $samples_number;
    #          @vm_Memory_compres_KBps      = ('U')x $samples_number;
    #          @vm_Memory_decompres_KBps    = ('U')x $samples_number;
    #          @vm_CPU_usage_Percent        = ('U')x $samples_number;
    #          @vm_CPU_ready_ms             = ('U')x $samples_number;

    if ( $entity_type eq $et_HostSystem ) {

      #             @Host_memory_size         = ($host_memorySize)x $samples_number;
    }

    # rank is according to @counter_hsvm_eng(ger1,ger2) used in sub prepare_vm_metric(), see global definitions
    #          $arr_pointers[0]  = \@vm_CPU_usage_MHz;
    $arr_pointers[1]  = \@vm_Disk_usage_KBps;
    $arr_pointers[2]  = \@vm_Disk_read_KBps;
    $arr_pointers[3]  = \@vm_Disk_write_KBps;
    $arr_pointers[4]  = \@vm_Network_usage_KBps;
    $arr_pointers[5]  = \@vm_Network_received_KBps;
    $arr_pointers[6]  = \@vm_Network_transmitted_KBps;
    $arr_pointers[7]  = \@vm_Memory_active_KB;
    $arr_pointers[8]  = \@vm_Memory_granted_KB;
    $arr_pointers[9]  = \@vm_Memory_swapin_KBps;
    $arr_pointers[11] = \@vm_Memory_swapout_KBps;
    $arr_pointers[12] = \@vm_Memory_decompres_KBps;
    $arr_pointers[13] = \@vm_Memory_compres_KBps;
    $arr_pointers[10] = \@vm_Memory_baloon_MB;
    $arr_pointers[14] = \@vm_CPU_usage_Percent;
    $arr_pointers[15] = \@vm_CPU_ready_ms;
  }
  elsif ( $entity_type eq $et_ClusterComputeResource ) {
    @cl_CPU_usage_Proc          = ('U') x $samples_number;
    @cl_CPU_usage_MHz           = ('U') x $samples_number;
    @cl_CPU_reserved_MHz        = ('U') x $samples_number;
    @cl_Memory_usage_Proc       = ('U') x $samples_number;
    @cl_Memory_reserved_MB      = ('U') x $samples_number;
    @cl_Memory_granted_KB       = ('U') x $samples_number;
    @cl_Memory_active_KB        = ('U') x $samples_number;
    @cl_Memory_shared_KB        = ('U') x $samples_number;
    @cl_Memory_zero_KB          = ('U') x $samples_number;
    @cl_Memory_swap_KB          = ('U') x $samples_number;
    @cl_Memory_baloon_KB        = ('U') x $samples_number;
    @cl_Memory_consumed_KB      = ('U') x $samples_number;
    @cl_Memory_overhead_KB      = ('U') x $samples_number;
    @cl_Memory_compressed_KB    = ('U') x $samples_number;
    @cl_Memory_compression_KBps = ('U') x $samples_number;
    @cl_Memory_decompress_KBps  = ('U') x $samples_number;
    @cl_Power_usage_Watt        = ('U') x $samples_number;
    @cl_Power_cup_Watt          = ('U') x $samples_number;
    @cl_Cluster_eff_CPU_MHz     = ('U') x $samples_number;
    @cl_Cluster_eff_memory_MB   = ('U') x $samples_number;
    @cl_CPU_total_MHz           = ($cluster_effectiveCpu) x $samples_number;
    @cl_Memory_total_MB         = ($cluster_effectiveMemory) x $samples_number;

    # rank is according to @counter_cl_eng(ger1,ger2) used in sub prepare_vm_metric(), see global definitions
    $arr_pointers[0]  = \@cl_CPU_usage_MHz;
    $arr_pointers[1]  = \@cl_CPU_usage_Proc;
    $arr_pointers[2]  = \@cl_CPU_reserved_MHz;
    $arr_pointers[3]  = \@cl_CPU_total_MHz;
    $arr_pointers[4]  = \@cl_Cluster_eff_CPU_MHz;
    $arr_pointers[5]  = \@cl_Cluster_eff_memory_MB;
    $arr_pointers[6]  = \@cl_Memory_total_MB;
    $arr_pointers[7]  = \@cl_Memory_shared_KB;
    $arr_pointers[8]  = \@cl_Memory_zero_KB;
    $arr_pointers[9]  = \@cl_Memory_baloon_KB;
    $arr_pointers[10] = \@cl_Memory_consumed_KB;
    $arr_pointers[11] = \@cl_Memory_overhead_KB;
    $arr_pointers[12] = \@cl_Memory_active_KB;
    $arr_pointers[13] = \@cl_Memory_granted_KB;
    $arr_pointers[14] = \@cl_Memory_compressed_KB;
    $arr_pointers[15] = \@cl_Memory_reserved_MB;
    $arr_pointers[16] = \@cl_Memory_swap_KB;
    $arr_pointers[17] = \@cl_Memory_compression_KBps;
    $arr_pointers[18] = \@cl_Memory_decompress_KBps;
    $arr_pointers[19] = \@cl_Memory_usage_Proc;
    $arr_pointers[20] = \@cl_Power_cup_Watt;
    $arr_pointers[21] = \@cl_Power_usage_Watt;
  }
  elsif ( $entity_type eq $et_ResourcePool ) {
    @cl_CPU_usage_MHz           = ('U') x $samples_number;
    @cl_Memory_granted_KB       = ('U') x $samples_number;
    @cl_Memory_active_KB        = ('U') x $samples_number;
    @cl_Memory_shared_KB        = ('U') x $samples_number;
    @cl_Memory_zero_KB          = ('U') x $samples_number;
    @cl_Memory_swap_KB          = ('U') x $samples_number;
    @cl_Memory_baloon_KB        = ('U') x $samples_number;
    @cl_Memory_consumed_KB      = ('U') x $samples_number;
    @cl_Memory_overhead_KB      = ('U') x $samples_number;
    @cl_Memory_compressed_KB    = ('U') x $samples_number;
    @cl_Memory_compression_KBps = ('U') x $samples_number;
    @cl_Memory_decompress_KBps  = ('U') x $samples_number;
    @cl_cpu_limit               = ($rp_cpu_limit) x $samples_number;
    @cl_cpu_reservation         = ($rp_cpu_reservation) x $samples_number;
    @cl_mem_limit               = ($rp_mem_limit) x $samples_number;
    @cl_mem_reservation         = ($rp_mem_reservation) x $samples_number;

    # rank is according to @counter_rp_eng(ger1,ger2) used in sub prepare_vm_metric(), see global definitions
    $arr_pointers[0]  = \@cl_CPU_usage_MHz;
    $arr_pointers[1]  = \@cl_Memory_shared_KB;
    $arr_pointers[2]  = \@cl_Memory_zero_KB;
    $arr_pointers[3]  = \@cl_Memory_baloon_KB;
    $arr_pointers[4]  = \@cl_Memory_consumed_KB;
    $arr_pointers[5]  = \@cl_Memory_overhead_KB;
    $arr_pointers[6]  = \@cl_Memory_active_KB;
    $arr_pointers[7]  = \@cl_Memory_granted_KB;
    $arr_pointers[8]  = \@cl_Memory_compressed_KB;
    $arr_pointers[9]  = \@cl_Memory_swap_KB;
    $arr_pointers[10] = \@cl_Memory_compression_KBps;
    $arr_pointers[11] = \@cl_Memory_decompress_KBps;
    $arr_pointers[12] = \@cl_cpu_limit;
    $arr_pointers[13] = \@cl_cpu_reservation;
    $arr_pointers[14] = \@cl_mem_limit;
    $arr_pointers[15] = \@cl_mem_reservation;
  }
  elsif ( $entity_type eq $et_Datastore ) {
    @ds_Datastore_freeSpace_KB        = ($ds_freeSpace) x $samples_number;
    @ds_Datastore_used_KB             = ($ds_used) x $samples_number;
    @ds_Datastore_provision_KB        = ($ds_provisioned) x $samples_number;
    @ds_Datastore_capacity_KB         = ($ds_capacity) x $samples_number;
    @ds_Datastore_read_KBps           = ('U') x $samples_number;
    @ds_Datastore_write_KBps          = ('U') x $samples_number;
    @ds_Datastore_numberReadAveraged  = ('U') x $samples_number;
    @ds_Datastore_numberWriteAveraged = ('U') x $samples_number;

    # rank is according to @counter_ds_eng(ger1,ger2) used in sub prepare_vm_metric(), see global definitions
    $arr_pointers[0] = \@ds_Datastore_used_KB;
    $arr_pointers[1] = \@ds_Datastore_provision_KB;
    $arr_pointers[2] = \@ds_Datastore_capacity_KB;
    $arr_pointers[3] = \@ds_Datastore_read_KBps;
    $arr_pointers[4] = \@ds_Datastore_write_KBps;
    $arr_pointers[5] = \@ds_Datastore_numberReadAveraged;
    $arr_pointers[6] = \@ds_Datastore_numberWriteAveraged;
  }
  else {
    error( "(F$server_count) unknown entity_type $entity_type " . __FILE__ . ":" . __LINE__ ) && exit 0;
  }
  my $ts_size = $samples_number;

  # print "Number of samples : $ts_size \n";
  # print "time stamps array @vm_time_stamps\n\n";

  my $success_metric = 0;

  # if ($entity_type eq $et_Datastore) {
  #  	print Dumper(@$values);
  #}

  $samples_number = 1;
  my $first_update_time = $vm_time_stamps[0];
  my $last_update_time  = $vm_time_stamps[ $samples_number - 1 ];

  my $update_string     = "";
  my $two_update_string = "";
  my $one_update;
  my $two_update;
  for ( my $i = 0; $i < $samples_number; $i++ ) {
    $update_string .= "$vm_time_stamps[$i],";

    #          $two_update_string .= "$vm_time_stamps[$i],";

    my $diff_item = "U";
    if ( ( $entity_type eq $et_HostSystem ) || ( $entity_type eq $et_VirtualMachine ) ) {

      #            if ($entity_type eq $et_HostSystem) {
      #              $diff_item = $Host_memory_size[$i];
      #            };
      #            if ($entity_type eq $et_VirtualMachine) {
      #              $diff_item = $numCpu;
      #            };
      $one_update = "$vm_PercentTotalRunTime[$i],$vm_Timestamp_PerfTime[$i],$vm_Frequency_PerfTime[$i],$vm_TotalPhysicalMemory[$i],$vm_AvailableMBytes[$i],$vm_MemoryAvailable[$i],$vm_CacheBytes[$i],";

      # $one_update .= "U,"; #DiskBytesPersec
      $one_update .= "$vm_DiskBytesPersec[$i],";

      # $one_update .= "$vm_DiskReadBytesPersec[$i],$vm_DiskReadsPersec[$i],U,"; #DiskTransfersPersec
      $one_update .= "$vm_DiskReadBytesPersec[$i],$vm_DiskReadsPersec[$i],$vm_DiskTransfersPersec[$i],";
      $one_update .= "$vm_DiskWriteBytesPerse[$i],$vm_DiskWritesPersec[$i],";
      $one_update .= "$vm_BytesReceivedPersec[$i],$vm_BytesSentPersec[$i],$vm_BytesTotalPersec[$i],$vm_PagesInputPersec[$i],$vm_PagesOutputPersec[$i],$vm_vCPU[$i]";

      #            $one_update .= "$vm_Memory_active_KB[$i],$vm_Memory_granted_KB[$i],$vm_Memory_baloon_MB[$i],";
      #            $one_update .= "$vm_Disk_usage_KBps[$i],$vm_Disk_read_KBps[$i],$vm_Disk_write_KBps[$i],";
      #            $one_update .= "$vm_Network_usage_KBps[$i],$vm_Network_received_KBps[$i],$vm_Network_transmitted_KBps[$i],";
      #            $one_update .= "$vm_Memory_swapin_KBps[$i],$vm_Memory_swapout_KBps[$i],";
      #            $one_update .= "$vm_Memory_compres_KBps[$i],$vm_Memory_decompres_KBps[$i],$vm_CPU_usage_Percent[$i],$diff_item,$vm_CPU_ready_ms[$i] ";
      $update_string .= "$one_update";
    }
    elsif ( $entity_type eq $et_ClusterComputeResource ) {
      $one_update = "$cl_CPU_usage_MHz[$i],$cl_CPU_usage_Proc[$i],$cl_CPU_reserved_MHz[$i],";
      $one_update    .= "$cl_CPU_total_MHz[$i],$cl_Cluster_eff_CPU_MHz[$i],$cl_Cluster_eff_memory_MB[$i],";
      $one_update    .= "$cl_Memory_total_MB[$i],$cl_Memory_shared_KB[$i],$cl_Memory_zero_KB[$i],";
      $one_update    .= "$cl_Memory_baloon_KB[$i],$cl_Memory_consumed_KB[$i],$cl_Memory_overhead_KB[$i],";
      $one_update    .= "$cl_Memory_active_KB[$i],$cl_Memory_granted_KB[$i],$cl_Memory_compressed_KB[$i],";
      $one_update    .= "$cl_Memory_reserved_MB[$i],$cl_Memory_swap_KB[$i],$cl_Memory_compression_KBps[$i],";
      $one_update    .= "$cl_Memory_decompress_KBps[$i],$cl_Memory_usage_Proc[$i],";
      $one_update    .= "$cl_Power_cup_Watt[$i],$cl_Power_usage_Watt[$i] ";
      $update_string .= "$one_update";
    }    # do not take $cl_Power_energy_usage_Joule[$i]
    elsif ( $entity_type eq $et_ResourcePool ) {
      $one_update = "$cl_CPU_usage_MHz[$i],";
      $one_update    .= "$cl_Memory_shared_KB[$i],$cl_Memory_zero_KB[$i],";
      $one_update    .= "$cl_Memory_baloon_KB[$i],$cl_Memory_consumed_KB[$i],$cl_Memory_overhead_KB[$i],";
      $one_update    .= "$cl_Memory_active_KB[$i],$cl_Memory_granted_KB[$i],$cl_Memory_compressed_KB[$i],";
      $one_update    .= "$cl_Memory_swap_KB[$i],$cl_Memory_compression_KBps[$i],";
      $one_update    .= "$cl_Memory_decompress_KBps[$i],$cl_cpu_limit[$i],$cl_cpu_reservation[$i],";
      $one_update    .= "$cl_mem_limit[$i],$cl_mem_reservation[$i],'U' ";                                     # U for added CPU proc
      $update_string .= "$one_update";
    }
    elsif ( $entity_type eq $et_Datastore ) {

      # cus 30 minutes getting data for used/provisioned/capacity/(freeSpace) there are two data files
      # datastore.rrs - for mentioned above
      # datastore.rrt - for the rest ds's (regular update)
      # example for load time = 10 minutes
      # 1442308800,3697908121600,-1,-1,-1,559,2570,34,116 1442309100,3697908121600,1757208576,4664769308,5368446976,501,4631,36,121
      # 1442326200,2587793293312,U,U,U,43,2736,4,293 1442326500,2587793293312,U,U,U,156,2499,4,270

      $one_update = "$ds_Datastore_read_KBps[$i],$ds_Datastore_write_KBps[$i],";
      $one_update    .= "$ds_Datastore_numberReadAveraged[$i],$ds_Datastore_numberWriteAveraged[$i] ";
      $update_string .= "$one_update";

      $two_update = "$ds_Datastore_freeSpace_KB[$i],$ds_Datastore_used_KB[$i],";
      $two_update .= "$ds_Datastore_provision_KB[$i],$ds_Datastore_capacity_KB[$i] ";
      if ( ( index( $two_update, '-1,-1,-1' ) < 0 ) && ( index( $two_update, 'U,U,U' ) < 0 ) ) {
        $two_update_string .= "$vm_time_stamps[$i],$two_update";
      }
    }
    else {
      error( "(F$server_count) unknown entity type $entity_type $fail_entity_type: $fail_entity_name " . __FILE__ . ":" . __LINE__ ) && exit 0;
    }
  }
  print_hyperv_debug("string for RRD file update is:\n$update_string\n---------------------------------------------------\n\n") if $DEBUG == 2;

  my $input_vm_uuid = $vm_name_uuid{$entity};

  if ( $entity_type eq 'HostSystem' ) {
    $input_vm_uuid = 'pool';
  }
  if ( $entity_type eq $et_ClusterComputeResource ) {
    $input_vm_uuid = 'cluster';
    $type_sam      = "c";
  }
  if ( $entity_type eq $et_ResourcePool ) {
    $input_vm_uuid = $entity_uuid;
    $type_sam      = "c";
  }
  if ( $entity_type eq $et_Datastore ) {
    $input_vm_uuid = $entity_uuid;
    $type_sam      = "t";            # regular update
  }

  $SSH = "";

  my $managedname_save = $managedname;
  my $host_save        = $host;
  if ( $entity_type eq $et_VirtualMachine ) {
    $managedname_save = "hyperv_VMs";
    $host_save        = "";
  }

  if ( $entity_type ne $et_Datastore ) {
    my $res_update = LoadDataModuleHyperV::load_data( $managedname_save, $host_save, $wrkdir, \$update_string, $type_sam, $act_time, $HMC, $IVM, $SDMC, $step, $DEBUG, \@lpar_trans, $last_file, $no_time, $SSH, $hmc_user, $input_vm_uuid, $entity_type, "(F$server_count)" );

    #          return
  }

  print_hyperv_debug("2885 LoadDataModuleHyperV::load_data ($managedname_save,$host_save,$wrkdir,\$update_string,$type_sam,$act_time,$HMC,$IVM,$SDMC,$step,$DEBUG,\@lpar_trans,$last_file,$no_time,$SSH,$hmc_user,$input_vm_uuid,$entity_type,(F$server_count));\n") if $DEBUG == 2;

  if ( $entity_type eq 'HostSystem' ) {    # go for fixed disks
                                           # CLASS: Win32_LogicalDisk
                                           # "Description","DeviceID","FreeSpace","Size"
                                           # "3 1/2 Inch Floppy Drive","A:",,
                                           # "Local Fixed Disk","C:","26691719168","42423283712"
                                           # "CD-ROM Disc","D:",,
                                           # "Local Fixed Disk","E:","10691956736","10737414144"
                                           # "Local Fixed Disk","F:","10555826176","10601099264"
                                           #
                                           #  other languages
                                           # "Místní pevný disk","C:","809388072960","955295649792"
                                           #
                                           #CLASS: Win32_PerfRawData_PerfDisk_LogicalDisk
                                           #"Name","Timestamp_PerfTime","Frequency_PerfTime","DiskReadBytesPersec","DiskWriteBytesPersec","DiskReadsPersec","DiskWritesPersec",
                                           #                                                 "AvgDisksecPerRead","AvgDisksecPerRead_Base","AvgDisksecPerWrite","AvgDisksecPerWrite_Base"
                                           #"E:","46731001377229","3117921","85475017216","118810357760","310433","1252304","1725749165","310433","804897803","1252304"
                                           #"HarddiskVolume3","46731001377229","3117921","0","0","0","0","0","0","0","0"
                                           #"C:","46731001377229","3117921","417952291328","715197595648","8757488","52200515","2497936692","8757488","499778004","52200515"
                                           # this is special case not in Win32_LogicalDisk
                                           # "C:\Users\jihampl","52696736742916","3117921","3332608","119705088","207","7148","16523598","207","2179586129","7148"
                                           # but in Win32_Volume
                                           # "C:\Users\jihampl\","3","21472735232","21327249408","User Disk"
                                           #
                                           #"_Total","46731001377229","3117921","503427308544","834007953408","9067921","53452819","4223685857","9067921","1304675807","53452819"
                                           # CLASS: Win32_Volume
                                           # "Name","DriveType","Capacity","FreeSpace","Label"
                                           # "\\?\Volume{e57611ae-0000-0000-0000-100000000000}\","3","524283904","177479680","System Reserved"
                                           # "E:\","3","10737414144","10691956736","FreeNAS 1st half"
                                           # "F:\","3","10601099264","10555826176","FreeNAS 2nd half"
                                           # "C:\","3","42423283712","26691719168",
                                           # "D:\","5",,,

    # my $ref_data = \%hyp_data;
    my $class = 'Win32_LogicalDisk';
    my $i     = 0;
    print_hyperv_debug("3296 go for fixed disks\n") if $DEBUG == 2;
    while ( defined $$hyp_data_comp_act->{$class}[$i] ) {
      my $hyp_line = $$hyp_data_comp_act->{$class}[$i];
      $i++;
      next                                              if $hyp_line !~ "\"Local Fixed Disk\"" && $hyp_line !~ "\"Místní pevný disk\"" && $hyp_line !~ "\"Локальный несъемный диск\"" && $hyp_line !~ "\"Lokale Festplatte\"";
      print_hyperv_debug("3301 hyp2rrd.pl $hyp_line\n") if $DEBUG == 2;
      $hyp_line =~ s/\"//g;
      my @disk_arr = split( /,/, $hyp_line );
      next if scalar @disk_arr < 5;    # sometimes can happen
      $update_string = "$first_update_time,$disk_arr[-3],$disk_arr[-2]";
      $input_vm_uuid = "Local_Fixed_Disk_$disk_arr[-4]";
      $type_sam      = "m";
      $last_file     = "";
      my ( $Timestamp_PerfTime, $Frequency_PerfTime, $DiskReadBytesPersec, $DiskWriteBytesPerse, $DiskReadsPersec, $DiskWritesPersec, $AvgDisksecPerRead, $AvgDisksecPerReadB, $AvgDisksecPerWrite, $AvgDisksecPerWriteB ) = (0) x 10;

      if ( exists $$hyp_data_comp_act->{'Win32_PerfRawData_PerfDisk_LogicalDisk'} && exists $$hyp_data_comp_last->{'Win32_PerfRawData_PerfDisk_LogicalDisk'} ) {
        $Timestamp_PerfTime = delta_get_hyp_val( 'Win32_PerfRawData_PerfDisk_LogicalDisk', 'Timestamp_PerfTime', $hyp_data_comp_act, $hyp_data_comp_last, $disk_arr[-4] );
        $Timestamp_PerfTime = "U" if !defined $Timestamp_PerfTime or $Timestamp_PerfTime eq $UnDeF;
        ( $Timestamp_PerfTime, undef ) = split( ",", $Timestamp_PerfTime );      # in case more values -> take only the 1st
        $Frequency_PerfTime = get_hyp_val( 'Win32_PerfRawData_PerfDisk_LogicalDisk', 'Frequency_PerfTime', $hyp_data_comp_act, $disk_arr[-4] );
        $Frequency_PerfTime = "U" if !defined $Frequency_PerfTime or $Frequency_PerfTime eq $UnDeF;
        ( $Frequency_PerfTime, undef ) = split( ",", $Frequency_PerfTime );      # in case more values -> take only the 1st
        $DiskReadBytesPersec = delta_get_hyp_val( 'Win32_PerfRawData_PerfDisk_LogicalDisk', 'DiskReadBytesPersec', $hyp_data_comp_act, $hyp_data_comp_last, $disk_arr[-4] );
        $DiskReadBytesPersec = "U" if !defined $DiskReadBytesPersec or $DiskReadBytesPersec eq $UnDeF;
        ( $DiskReadBytesPersec, undef ) = split( ",", $DiskReadBytesPersec );    # in case more values -> take only the 1st
        $DiskWriteBytesPerse = delta_get_hyp_val( 'Win32_PerfRawData_PerfDisk_LogicalDisk', 'DiskWriteBytesPersec', $hyp_data_comp_act, $hyp_data_comp_last, $disk_arr[-4] );
        $DiskWriteBytesPerse = "U" if !defined $DiskWriteBytesPerse or $DiskWriteBytesPerse eq $UnDeF;
        ( $DiskWriteBytesPerse, undef ) = split( ",", $DiskWriteBytesPerse );    # in case more values -> take only the 1st
        $DiskReadsPersec = delta_get_hyp_val( 'Win32_PerfRawData_PerfDisk_LogicalDisk', 'DiskReadsPersec', $hyp_data_comp_act, $hyp_data_comp_last, $disk_arr[-4] );
        $DiskReadsPersec = "U" if !defined $DiskReadsPersec or $DiskReadsPersec eq $UnDeF;
        ( $DiskReadsPersec, undef ) = split( ",", $DiskReadsPersec );            # in case more values -> take only the 1st
        $DiskWritesPersec = delta_get_hyp_val( 'Win32_PerfRawData_PerfDisk_LogicalDisk', 'DiskWritesPersec', $hyp_data_comp_act, $hyp_data_comp_last, $disk_arr[-4] );
        $DiskWritesPersec = "U" if !defined $DiskWritesPersec or $DiskWritesPersec eq $UnDeF;
        ( $DiskWritesPersec, undef ) = split( ",", $DiskWritesPersec );          # in case more values -> take only the 1st
        $AvgDisksecPerRead = delta_get_hyp_val( 'Win32_PerfRawData_PerfDisk_LogicalDisk', 'AvgDisksecPerRead', $hyp_data_comp_act, $hyp_data_comp_last, $disk_arr[-4] );
        $AvgDisksecPerRead = "U" if !defined $AvgDisksecPerRead or $AvgDisksecPerRead eq $UnDeF;
        ( $AvgDisksecPerRead, undef ) = split( ",", $AvgDisksecPerRead );        # in case more values -> take only the 1st
        $AvgDisksecPerReadB = delta_get_hyp_val( 'Win32_PerfRawData_PerfDisk_LogicalDisk', 'AvgDisksecPerRead_Base', $hyp_data_comp_act, $hyp_data_comp_last, $disk_arr[-4] );
        $AvgDisksecPerReadB = "U" if !defined $AvgDisksecPerReadB or $AvgDisksecPerReadB eq $UnDeF;
        ( $AvgDisksecPerReadB, undef ) = split( ",", $AvgDisksecPerReadB );      # in case more values -> take only the 1st
        $AvgDisksecPerWrite = delta_get_hyp_val( 'Win32_PerfRawData_PerfDisk_LogicalDisk', 'AvgDisksecPerWrite', $hyp_data_comp_act, $hyp_data_comp_last, $disk_arr[-4] );
        $AvgDisksecPerWrite = "U" if !defined $AvgDisksecPerWrite or $AvgDisksecPerWrite eq $UnDeF;
        ( $AvgDisksecPerWrite, undef ) = split( ",", $AvgDisksecPerWrite );      # in case more values -> take only the 1st
        $AvgDisksecPerWriteB = delta_get_hyp_val( 'Win32_PerfRawData_PerfDisk_LogicalDisk', 'AvgDisksecPerWrite_Base', $hyp_data_comp_act, $hyp_data_comp_last, $disk_arr[-4] );
        $AvgDisksecPerWriteB = "U" if !defined $AvgDisksecPerWriteB or $AvgDisksecPerWriteB eq $UnDeF;
        ( $AvgDisksecPerWriteB, undef ) = split( ",", $AvgDisksecPerWriteB );    # in case more values -> take only the 1st
      }
      print_hyperv_debug("3331 $Timestamp_PerfTime,$Frequency_PerfTime,$DiskReadBytesPersec $DiskWriteBytesPerse $DiskReadsPersec $DiskWritesPersec $AvgDisksecPerRead $AvgDisksecPerReadB $AvgDisksecPerWrite $AvgDisksecPerWriteB\n") if $DEBUG == 2;
      $update_string .= ",$Timestamp_PerfTime,$Frequency_PerfTime,$DiskReadBytesPersec,$DiskWriteBytesPerse,$DiskReadsPersec,$DiskWritesPersec,$AvgDisksecPerRead,$AvgDisksecPerReadB,$AvgDisksecPerWrite,$AvgDisksecPerWriteB";
      print_hyperv_debug("3332 LoadDataModuleHyperV::load_data ($managedname_save,$host_save,$wrkdir,\$update_string,$type_sam,$act_time,$HMC,$IVM,$SDMC,$step,$DEBUG,\@lpar_trans,$last_file,$no_time,$SSH,$hmc_user,$input_vm_uuid,$entity_type,(F$server_count)); \$update_string $update_string\n") if $DEBUG == 2;
      my $res_update = LoadDataModuleHyperV::load_data( $managedname_save, $host_save, $wrkdir, \$update_string, $type_sam, $act_time, $HMC, $IVM, $SDMC, $step, $DEBUG, \@lpar_trans, $last_file, $no_time, $SSH, $hmc_user, $input_vm_uuid, $entity_type, "(F$server_count)" );
    }

    # get Cluster Shared Storage if exists, it is in nodes, in cluster is same data as in coordinating node, do not take this data
    # Get-wmiobject -Query select Name,DriveType,Capacity,FreeSpace,Label from Win32_Volume -cn CN=HVNODE02,CN=Computers,DC=ad,DC=xorux,DC=com.Name -EA silentlyContinue |Select-Object Name DriveType Capacity FreeSpace Label
    # CLASS: Win32_Volume
    # "Name","DriveType","Capacity","FreeSpace","Label","DeviceID"
    # "\\?\Volume{22ef4fe2-0000-0000-0000-100000000000}\","3","524283904","162037760","System Reserved","\\?\Volume{22ef4fe2-0000-0000-0000-100000000000}\"
    # "C:\","3","42423283712","34396155904",,"\\?\Volume{22ef4fe2-0000-0000-0000-501f00000000}\"
    # "C:\ClusterStorage\Volume2\","3","32209104896","32110993408","CLVOL02","\\?\Volume{b994eb5b-844f-45a7-86ea-6116e3175653}\"
    # "C:\ClusterStorage\Volume1\","3","69790068736","63375728640","CLVOL01","\\?\Volume{1d2ac989-641d-4fa0-9ee0-6a391c8be0da}\"
    # "D:\","5",,,,"\\?\Volume{770da79b-8ac9-11e8-9d58-806e6f6e6963}\"

    # nonitoring data for CSV is in _PhysicalDisk under Name "1" resp. "2" and so on
    # CLASS: Win32_PerfRawData_PerfDisk_PhysicalDisk
    # "Name","Timestamp_PerfTime","Frequency_PerfTime","DiskReadBytesPersec","DiskWriteBytesPersec","DiskReadsPersec","DiskWritesPersec",
    #                                                  "AvgDisksecPerRead","AvgDisksecPerRead_Base","AvgDisksecPerWrite","AvgDisksecPerWrite_Base"
    # "0 C:","11479970095690","2994772","9944602112","44117474816","203855","3165451","193855528","203855","1699987602","3165451"
    # "1","11479970095690","2994772","96223707648","107430872064","2949239","371297","3609052217","2949239","3791159777","371297"
    # "2","11479970095690","2994772","49052672","68931584","1391","901","2442905","1391","2112507","901"
    # "_Total","11479970095690","2994772","106217362432","151617278464","3154485","3537649","3805350650","3154485","1198292590","3537649"

    # $DEBUG = 2;
    my %name_hash = ();
    $class = 'Win32_Volume';
    $i     = 0;
    my $freespace = "\"FreeSpace\"";
    my $capacity  = "\"Capacity\"";
    my $name      = "\"Name\"";
    my $deviceid  = "\"DeviceID\"";
    print_hyperv_debug("3345 go for cluster shared volumes\n") if $DEBUG == 2;

    while ( defined $$hyp_data_comp_act->{$class}[$i] ) {
      my $hyp_line = $$hyp_data_comp_act->{$class}[$i];
      if ( $hyp_line =~ /Name/ && $hyp_line =~ /DeviceID/ ) {

        # this is the 1st line "Name","DriveType","Capacity","FreeSpace","Label","DeviceID", prepare hash with indexes
        my @name_arr = split( ",", $hyp_line );
        my $name_ind = 0;
        while ( defined $name_arr[$name_ind] ) {
          $name_hash{ $name_arr[$name_ind] } = $name_ind;
          $name_ind++;
        }
      }

      # print "3717 from class $class ---------------------\n";
      # print Dumper (%name_hash);
      $i++;
      next if $hyp_line !~ "ClusterStorage";
      next if !keys %name_hash;                # older agent does not send DeviceID

      print_hyperv_debug("3350 hyp2rrd.pl $hyp_line\n") if $DEBUG == 2;
      $hyp_line =~ s/\"//g;
      $hyp_line =~ s/\\//g;
      my @disk_arr = split( /,/, $hyp_line );

      #$update_string = "$first_update_time,$disk_arr[-4],$disk_arr[-5]";
      $update_string = "$first_update_time,$disk_arr[$name_hash{$freespace}],$disk_arr[$name_hash{$capacity}]";

      # $input_vm_uuid = "Local_Fixed_Disk_$disk_arr[-5]";
      $input_vm_uuid = "$disk_arr[$name_hash{$name}]";

      # keeps all cluster storages
      $all_clusterstorage{$h_name}{ $disk_arr[ $name_hash{$deviceid} ] } = "ahojte";    #computer name
      ( undef, $input_vm_uuid ) = split( "ClusterStorage", $input_vm_uuid );
      if ( $input_vm_uuid eq "" ) {
        error( "can't find ClusterStorage name in line $hyp_line " . __FILE__ . ":" . __LINE__ ) && next;
      }
      my $csv_number = $input_vm_uuid;
      $input_vm_uuid = "Cluster_Storage_$input_vm_uuid";
      $type_sam      = "m";
      $last_file     = "";

      # here can be different type of texts
      $csv_number =~ s/VM-VOLUME-//;
      $csv_number =~ s/Volume//;

      if ( !isdigit($csv_number) ) {    # try to get last number from end of string eg 'V5030E-LUN08' gives '8'
        $csv_number = ( $csv_number =~ /(\d+)/g )[-1];
        if ( defined $csv_number and $csv_number ne "" ) {
          $csv_number *= 1;
        }
      }

      my ( $Timestamp_PerfTime, $Frequency_PerfTime, $DiskReadBytesPersec, $DiskWriteBytesPerse, $DiskReadsPersec, $DiskWritesPersec, $AvgDisksecPerRead, $AvgDisksecPerReadB, $AvgDisksecPerWrite, $AvgDisksecPerWriteB ) = (0) x 10;
      if ( defined $csv_number && $csv_number ne "" && isdigit($csv_number) ) {
        my $item_contains = "ITEM=Name=\"$csv_number\"";

        # work out data for cluster shared volumes
        if ( exists $$hyp_data_comp_act->{'Win32_PerfRawData_PerfDisk_PhysicalDisk'} && exists $$hyp_data_comp_last->{'Win32_PerfRawData_PerfDisk_PhysicalDisk'} ) {
          $Timestamp_PerfTime  = delta_get_hyp_val( 'Win32_PerfRawData_PerfDisk_PhysicalDisk', 'Timestamp_PerfTime', $hyp_data_comp_act, $hyp_data_comp_last, $item_contains );
          $Timestamp_PerfTime  = "U" if !defined $Timestamp_PerfTime or $Timestamp_PerfTime eq $UnDeF;
          $Frequency_PerfTime  = get_hyp_val( 'Win32_PerfRawData_PerfDisk_PhysicalDisk', 'Frequency_PerfTime', $hyp_data_comp_act, $item_contains );
          $Frequency_PerfTime  = "U" if !defined $Frequency_PerfTime or $Frequency_PerfTime eq $UnDeF;
          $DiskReadBytesPersec = delta_get_hyp_val( 'Win32_PerfRawData_PerfDisk_PhysicalDisk', 'DiskReadBytesPersec', $hyp_data_comp_act, $hyp_data_comp_last, $item_contains );
          $DiskReadBytesPersec = "U" if !defined $DiskReadBytesPersec or $DiskReadBytesPersec eq $UnDeF;
          $DiskWriteBytesPerse = delta_get_hyp_val( 'Win32_PerfRawData_PerfDisk_PhysicalDisk', 'DiskWriteBytesPersec', $hyp_data_comp_act, $hyp_data_comp_last, $item_contains );
          $DiskWriteBytesPerse = "U" if !defined $DiskWriteBytesPerse or $DiskWriteBytesPerse eq $UnDeF;
          $DiskReadsPersec     = delta_get_hyp_val( 'Win32_PerfRawData_PerfDisk_PhysicalDisk', 'DiskReadsPersec', $hyp_data_comp_act, $hyp_data_comp_last, $item_contains );
          $DiskReadsPersec     = "U" if !defined $DiskReadsPersec or $DiskReadsPersec eq $UnDeF;
          $DiskWritesPersec    = delta_get_hyp_val( 'Win32_PerfRawData_PerfDisk_PhysicalDisk', 'DiskWritesPersec', $hyp_data_comp_act, $hyp_data_comp_last, $item_contains );
          $DiskWritesPersec    = "U" if !defined $DiskWritesPersec or $DiskWritesPersec eq $UnDeF;
          $AvgDisksecPerRead   = delta_get_hyp_val( 'Win32_PerfRawData_PerfDisk_PhysicalDisk', 'AvgDisksecPerRead', $hyp_data_comp_act, $hyp_data_comp_last, $item_contains );
          $AvgDisksecPerRead   = "U" if !defined $AvgDisksecPerRead or $AvgDisksecPerRead eq $UnDeF;
          $AvgDisksecPerReadB  = delta_get_hyp_val( 'Win32_PerfRawData_PerfDisk_PhysicalDisk', 'AvgDisksecPerRead_Base', $hyp_data_comp_act, $hyp_data_comp_last, $item_contains );
          $AvgDisksecPerReadB  = "U" if !defined $AvgDisksecPerReadB or $AvgDisksecPerReadB eq $UnDeF;
          $AvgDisksecPerWrite  = delta_get_hyp_val( 'Win32_PerfRawData_PerfDisk_PhysicalDisk', 'AvgDisksecPerWrite', $hyp_data_comp_act, $hyp_data_comp_last, $item_contains );
          $AvgDisksecPerWrite  = "U" if !defined $AvgDisksecPerWrite or $AvgDisksecPerWrite eq $UnDeF;
          $AvgDisksecPerWriteB = delta_get_hyp_val( 'Win32_PerfRawData_PerfDisk_PhysicalDisk', 'AvgDisksecPerWrite_Base', $hyp_data_comp_act, $hyp_data_comp_last, $item_contains );
          $AvgDisksecPerWriteB = "U" if !defined $AvgDisksecPerWriteB or $AvgDisksecPerWriteB eq $UnDeF;
        }
      }
      else {
        print "4244 not number for Cluster Shared Volume ,$input_vm_uuid, ,$csv_number,\n";
      }
      print "4038 $DiskReadBytesPersec $DiskWriteBytesPerse $DiskReadsPersec $DiskWritesPersec $AvgDisksecPerRead $AvgDisksecPerReadB $AvgDisksecPerWrite $AvgDisksecPerWriteB\n"               if $csv_number eq "18";
      print_hyperv_debug("3404 $DiskReadBytesPersec $DiskWriteBytesPerse $DiskReadsPersec $DiskWritesPersec $AvgDisksecPerRead $AvgDisksecPerReadB $AvgDisksecPerWrite $AvgDisksecPerWriteB\n") if $DEBUG == 2;
      $update_string .= ",$Timestamp_PerfTime,$Frequency_PerfTime,$DiskReadBytesPersec,$DiskWriteBytesPerse,$DiskReadsPersec,$DiskWritesPersec,$AvgDisksecPerRead,$AvgDisksecPerReadB,$AvgDisksecPerWrite,$AvgDisksecPerWriteB";
      print_hyperv_debug("3406 LoadDataModuleHyperV::load_data ($managedname_save,$host_save,$wrkdir,\$update_string,$type_sam,$act_time,$HMC,$IVM,$SDMC,$step,$DEBUG,\@lpar_trans,$last_file,$no_time,$SSH,$hmc_user,$input_vm_uuid,$entity_type,(F$server_count));$update_string\n") if $DEBUG == 2;
      my $res_update = LoadDataModuleHyperV::load_data( $managedname_save, $host_save, $wrkdir, \$update_string, $type_sam, $act_time, $HMC, $IVM, $SDMC, $step, $DEBUG, \@lpar_trans, $last_file, $no_time, $SSH, $hmc_user, $input_vm_uuid, $entity_type, "(F$server_count)" );
    }

    print_hyperv_debug("3410 finito end of cluster shared volumes\n") if $DEBUG == 2;

    #my @host_disks = ();

    # CPU queue, processes, threads, calls

    #date 11/01/2021 10:22:03  Unix 1635758523
    #Get-wmiobject -Query select ProcessorQueueLength,Processes,Threads,SystemCallsPersec,Timestamp_PerfTime from Win32_PerfRawData_PerfOS_System -cn @{Name=s2d}.Name -EA silentlyContinue |
    #Select-Object ProcessorQueueLength Processes Threads SystemCallsPersec Timestamp_PerfTime
    #CLASS: Win32_PerfRawData_PerfOS_System
    #"ProcessorQueueLength","Processes","Threads","SystemCallsPersec","Timestamp_PerfTime"
    #"0","129","1961","3127817546","23314349945129"

    $class = 'Win32_PerfRawData_PerfOS_System';
    $i     = 0;
    print_hyperv_debug("4336 go for PerfOS_System\n") if $DEBUG == 2;
    while ( defined $$hyp_data_comp_act->{$class}[$i] ) {
      my $hyp_line = $$hyp_data_comp_act->{$class}[$i];
      $i++;
      print_hyperv_debug("4340 hyp2rrd.pl $hyp_line\n") if $DEBUG == 2;
      $hyp_line =~ s/\"//g;
      $update_string = "$first_update_time";
      $input_vm_uuid = "CPUqueue";
      $type_sam      = "m";
      $last_file     = "";
      my ( $CPU_ProcessorQueueLength, $CPU_processes, $CPU_threads, $CPU_SystemCallsPersec, $Timestamp_PerfTime ) = (0) x 5;

      if ( exists $$hyp_data_comp_act->{'Win32_PerfRawData_PerfOS_System'} && exists $$hyp_data_comp_last->{'Win32_PerfRawData_PerfOS_System'} ) {
        $CPU_ProcessorQueueLength = get_hyp_val( 'Win32_PerfRawData_PerfOS_System', 'ProcessorQueueLength', $hyp_data_comp_act );
        $CPU_ProcessorQueueLength = "U" if !defined $CPU_ProcessorQueueLength or $CPU_ProcessorQueueLength eq $UnDeF;
        ( $CPU_ProcessorQueueLength, undef ) = split( ",", $CPU_ProcessorQueueLength );    # in case more values -> take only the 1st
        $CPU_processes = get_hyp_val( 'Win32_PerfRawData_PerfOS_System', 'Processes', $hyp_data_comp_act );
        $CPU_processes = "U" if !defined $CPU_processes or $CPU_processes eq $UnDeF;
        ( $CPU_processes, undef ) = split( ",", $CPU_processes );                          # in case more values -> take only the 1st
        $CPU_threads = get_hyp_val( 'Win32_PerfRawData_PerfOS_System', 'Threads', $hyp_data_comp_act );
        $CPU_threads = "U" if !defined $CPU_threads or $CPU_threads eq $UnDeF;
        ( $CPU_threads, undef ) = split( ",", $CPU_threads );                              # in case more values -> take only the 1st
        $CPU_SystemCallsPersec = delta_get_hyp_val( 'Win32_PerfRawData_PerfOS_System', 'SystemCallsPersec', $hyp_data_comp_act, $hyp_data_comp_last );
        $CPU_SystemCallsPersec = "U" if !defined $CPU_SystemCallsPersec or $CPU_SystemCallsPersec eq $UnDeF;
        ( $CPU_SystemCallsPersec, undef ) = split( ",", $CPU_SystemCallsPersec );          # in case more values -> take only the 1st
        $Timestamp_PerfTime = delta_get_hyp_val( 'Win32_PerfRawData_PerfOS_System', 'Timestamp_PerfTime', $hyp_data_comp_act, $hyp_data_comp_last );
        $Timestamp_PerfTime = "U" if !defined $Timestamp_PerfTime or $Timestamp_PerfTime eq $UnDeF;
        ( $Timestamp_PerfTime, undef ) = split( ",", $Timestamp_PerfTime );                # in case more values -> take only the 1st
      }
      print_hyperv_debug("4374 $CPU_ProcessorQueueLength $CPU_processes $CPU_threads $CPU_SystemCallsPersec $Timestamp_PerfTime\n") if $DEBUG == 2;

      # U instead of SystemCalls because of big numbers
      $update_string .= ",$CPU_ProcessorQueueLength,$CPU_processes,$CPU_threads,$CPU_SystemCallsPersec,$Timestamp_PerfTime";
      print_hyperv_debug("3332 LoadDataModuleHyperV::load_data ($managedname_save,$host_save,$wrkdir,\$update_string,$type_sam,$act_time,$HMC,$IVM,$SDMC,$step,$DEBUG,\@lpar_trans,$last_file,$no_time,$SSH,$hmc_user,$input_vm_uuid,$entity_type,(F$server_count)); \$update_string $update_string\n") if $DEBUG == 2;
      my $res_update = LoadDataModuleHyperV::load_data( $managedname_save, $host_save, $wrkdir, \$update_string, $type_sam, $act_time, $HMC, $IVM, $SDMC, $step, $DEBUG, \@lpar_trans, $last_file, $no_time, $SSH, $hmc_user, $input_vm_uuid, $entity_type, "(F$server_count)" );

    }
  }
  print_hyperv_debug("3413 finito tuti of Host system\n") if $DEBUG == 2;
}

sub get_last_date_range {
  my ( $pef_time_sec, $entity_type ) = @_;

  return ( "vcera", "dnes", 3600 );

  #return ($st_date,$end_date,$pef_time_sec);

  # ServiceInstance current server time looks like e.g. 2015-04-16T11:12:28.296812Z
  #  my $server_time  = $service_instance->CurrentTime;
  my $server_time   = $command_date;
  my $apiType       = $service_instance->content->about->apiType;
  my $localeBuild   = $service_instance->content->about->localeBuild;
  my $localeVersion = $service_instance->content->about->localeVersion;
  my $fullName      = $service_instance->content->about->fullName;
  my $instanceUuid  = $service_instance->content->about->instanceUuid;
  print "apiType        : $apiType $fullName";
  if ( defined $localeBuild )   { print " locale $localeBuild" }
  if ( defined $localeVersion ) { print " localeversion $localeVersion" }
  if ( defined $instanceUuid )  { print " instanceUuid $instanceUuid" }
  print " (F$server_count)\n";

  if ( $apiType eq "HostAgent" ) {
    if ( $pef_time_sec > 3600 ) {
      $pef_time_sec = 3600 * 18;
    }
  }
  else {
    if ( $apiType ne "VirtualCenter" ) {
      error( "(F$server_count) unknown apiType $apiType " . $service_instance->about->fullName . __FILE__ . ":" . __LINE__ ) && return 0;
    }
    if ( $pef_time_sec > 3600 * 18 ) {
      $pef_time_sec = 3600 * 18;
    }
  }

  my $unix_time = str2time($server_time);

  if ( $entity_type eq $et_ResourcePool || $entity_type eq $et_Datastore || $entity_type eq $et_ClusterComputeResource ) {

    # 23/12/2015 try round low times to dividable 300
    $unix_time    = $unix_time - ( $unix_time % 300 );
    $pef_time_sec = $pef_time_sec - ( $pef_time_sec % 300 );
  }

  #   if ($pef_time_sec > 3600) {
  #     $pef_time_sec = 3500;
  #   }

  # move all 5 minutes back so vCenter has time to get values, does not help
  # $unix_time -= 300;

  my ( $gsec, $gmin, $ghour, $gday, $gmonth, $gyear, $gwday, $gyday, $gisdst ) = gmtime($unix_time);
  $gyear += 1900;
  $gmonth++;
  $gmonth = "0" . $gmonth if $gmonth < 10;
  $gday   = "0" . $gday   if $gday < 10;
  $ghour  = "0" . $ghour  if $ghour < 10;
  $gmin   = "0" . $gmin   if $gmin < 10;
  $gsec   = "0" . $gsec   if $gsec < 10;

  my $end_date = $gyear . "-" . $gmonth . "-" . $gday . "T" . $ghour . ":" . $gmin . ":" . $gsec;

  my $end_time = timelocal( $gsec, $gmin, $ghour, $gday, $gmonth - 1, $gyear - 1900 );
  my $st_time  = $end_time - ( $pef_time_sec - 1 + 1 );                                  #+ 1;  # not now 23/12/2015
                                                                                         # print "\$end_time $end_time \$st_time $st_time\n";

  my ( $sec, $min, $hour, $day, $month, $year, $wday, $yday, $isdst ) = localtime($st_time);
  $year += 1900;
  $month++;
  $month = "0" . $month if $month < 10;
  $day   = "0" . $day   if $day < 10;
  $hour  = "0" . $hour  if $hour < 10;
  $min   = "0" . $min   if $min < 10;
  $sec   = "0" . $sec   if $sec < 10;

  my $st_date = $year . "-" . $month . "-" . $day . "T" . $hour . ":" . $min . ":" . $sec;

  #print "\$end_date $end_date \$st_date $st_date\n";

  return ( $st_date, $end_date, $pef_time_sec );
}

sub rrd_check {
  my $managedname = shift;
  print_hyperv_debug("------------- rrd_check $wrkdir/$managedname/$host\n") if $DEBUG == 2;

  # Check whether do initial or normal load
  opendir( DIR, "$wrkdir/$managedname/$host" ) || error( " directory does not exists : $wrkdir/$managedname/$host" . __FILE__ . ":" . __LINE__ ) && return 0;
  my @files          = ();
  my @files_unsorted = ();

  if ( $type_sam =~ "m" ) {
    @files_unsorted = grep( /\.rrm$/, readdir(DIR) );
    @files          = sort { lc $a cmp lc $b } @files_unsorted;
  }
  if ( scalar @files > 0 ) {
    closedir(DIR);
    return;
  }
  return 0;

  # the rrest of this sub is not used in windows

  rewinddir(DIR);    # for cluster

  @files_unsorted = grep( /cluster\.rrc$/, readdir(DIR) );
  @files          = sort { lc $a cmp lc $b } @files_unsorted;

  if ( scalar @files_unsorted > 0 ) {
    closedir(DIR);
    return;
  }
  rewinddir(DIR);    # for resourcepools

  @files_unsorted = grep( /\.rrc$/, readdir(DIR) );
  @files          = sort { lc $a cmp lc $b } @files_unsorted;

  if ( scalar @files_unsorted > 0 ) {
    closedir(DIR);
    return;
  }

  rewinddir(DIR);    # for datastore

  @files_unsorted = grep( /\.rrs$/, readdir(DIR) );
  @files          = sort { lc $a cmp lc $b } @files_unsorted;

  if ( scalar @files_unsorted > 0 ) {
    closedir(DIR);
    return;
  }

  closedir(DIR);

  print "There is no RRD: $host:$managedname attempting to do initial load, be patient, it might take some time\n" if $DEBUG;

  # it is for initial load
  # daily data it keeps for last 2years and monthly for last 10years
  # let load far enough backward for initial load (value in hours or in days)
  $loadhours = $INIT_LOAD_IN_HOURS_BACK;
  $loadmins  = $INIT_LOAD_IN_HOURS_BACK * 60;

  return 0;
}

sub FormatResults {
  my @results_unsort = @_;
  my $line           = "";
  my $formated       = "";
  my @items1         = "";
  my $item           = "";

  # if any param except 1st starts "comment_" it is comment in HTML
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
        if ( $item =~ /^comment_/ ) {
          $item =~ s/^comment_//;
          $formated = sprintf( "%s <!%s>", $formated, $item );
        }
        else {
          $formated = sprintf( "%s <TD align=\"center\">%s</TD>", $formated, $item );
        }
      }
      $col++;
    }
    $formated = $formated . "</TR>\n";
  }
  return $formated;
}

# error handling
sub error {
  my $text     = shift;
  my $act_time = localtime();
  chomp($text);

  print "ERROR          : $text : $!\n";
  print STDERR "$act_time: $text : $!\n";

  return 1;
}

sub xerror {
  my $text     = shift;
  my $act_time = localtime();
  chomp($text);

  if ( $i_am_fork eq 'fork' ) {
    print "XERROR         : $act_time: $text\n";
  }
  else {
    open my $FH, ">>$counters_info_file" or error( "can't open $counters_info_file: $!" . __FILE__ . ":" . __LINE__ );
    print $FH "$act_time: $text\n";
    close $FH;
  }
  return 1;
}

sub rename_server {
  my $host        = shift;
  my $managedname = shift;
  my $model       = shift;
  my $serial      = shift;

  # since 4.8 can work for both IBM/VMWARE

  my $mod_ser = $model;
  if ( defined $serial ) {    # in case vmware, there is only uuid
    $mod_ser .= $serial;
  }

  if ( !-d "$wrkdir/$managedname" ) {

    # when managed system is renamed then find the original nale per a sym link with model*serial
    #   and rename it in lpar2rrd as well
    if ( -l "$wrkdir/$mod_ser" ) {
      my $link = readlink("$wrkdir/$mod_ser");

      #my $base = basename($link);
      # basename without direct function
      my @link_l = split( /\//, $link );
      my $base   = "";
      foreach my $m (@link_l) {
        $base = $m;
      }

      print "system renamed : $host:$managedname from $base to $managedname, behave as upgrade \n" if $DEBUG;
      if ( -f "$link" ) {
        rename( "$link", "$wrkdir/$managedname" ) || error( " Cannot mv $link $wrkdir/$managedname: $!" . __FILE__ . ":" . __LINE__ ) && return 0;
      }
      unlink("$wrkdir/$mod_ser") || error( " Cannot rm $wrkdir/$mod_ser: $!" . __FILE__ . ":" . __LINE__ ) && return 0;
      $upgrade = 1;    # must be like upgrade behave due to views
    }
    else {
      print "mkdir          : $host:$managedname $wrkdir/$managedname\n" if $DEBUG;
      mkdir( "$wrkdir/$managedname", 0755 ) || error( " Cannot mkdir $wrkdir/$managedname: $!" . __FILE__ . ":" . __LINE__ ) && return 0;
    }
    LoadDataModuleHyperV::touch("$wrkdir/$managedname");    #must be at the end due to renaming servers
  }

  # check wherher the symlink is linked to the right targed
  # there could be an issue with symlink prior 3.37 ($managedname dirs could be created from HEA stuff without care about renaming)
  my $managedname_linked = "";
  my $link               = "";
  my $link_expected      = "$wrkdir/$mod_ser";
  if ( -l "$link_expected" ) {
    $link = readlink("$link_expected");

    # basename without direct function
    my @link_l             = split( /\//, $link );
    my $managedname_linked = "";
    foreach my $m (@link_l) {
      $managedname_linked = $m;
    }
    if ( $managedname =~ m/^$managedname_linked$/ ) {

      # ok, symlink target is properly linked
      return 1;
    }
    else {
      print "symlink correct: $host:$managedname : $link : $link_expected\n" if $DEBUG;
      unlink($link_expected);
    }
  }

  return 1;
}

# fill in @lpm_excl_vio for server
sub lpm_exclude_vio {
  my $host        = shift;
  my $managedname = shift;
  my $wrkdir      = shift;
  my $lpm_excl    = "$wrkdir/$managedname/$host/lpm-exclude.txt";

  if ( $lpm == 0 ) {
    return 0;    # LPM is switched off
  }
  open( my $FH, "< $lpm_excl" ) || return 1;
  @lpm_excl_vio = <$FH>;
  close($FH);
  return 0;
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
  my $text  = shift;

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
  return 0;
}

# it checks if rrdtool supports graphv --> then zoom is supported
# it checks if rrdtool supports --right-axis (used for vmware cpu graphing - since 1.2015)
sub rrdtool_graphv {
  my $graph_cmd   = "graph";
  my $graphv_file = "$tmpdir/graphv";

  my $ansx = `$rrdtool`;

  if ( index( $ansx, 'graphv' ) != -1 ) {

    # graphv exists, create a file to pass it to cgi-bin commands
    if ( !-f $graphv_file ) {
      `touch $graphv_file`;
    }
  }
  else {
    if ( -f $graphv_file ) {
      unlink($graphv_file);
    }
  }

  $graph_cmd   = "--right-axis";
  $graphv_file = "$tmpdir/graph-right-axis";
  $ansx        = `$rrdtool graph $graph_cmd 2>&1`;

  if ( index( $ansx, "$graph_cmd" ) == -1 ) {    # OK when doesn't contain
                                                 # right-axis exists, create a file to pass it to cgi-bin commands
    if ( !-f $graphv_file ) {
      `touch $graphv_file`;
    }
  }
  else {
    if ( -f $graphv_file ) {
      unlink($graphv_file);
    }
  }

  return 0;
}

sub hyperv_load {
  my $file_act          = shift;
  my $file_last_but_one = shift;

  # analyse of hyperv results actual and last_but_one file
  # - filling global %hyp_data structure with all info from actual file
  # - filling global %hyp_data_one structure with all info from last but one file

  # load actual data
  hyp_load_file( $file_act, \%hyp_data );

  #  print Dumper ("--------------6049----------", \%hyp_data );

  # load last but one data
  hyp_load_file( $file_last_but_one, \%hyp_data_one );

  #  print Dumper ("--------------6053----------", \%hyp_data_one );
}

sub hyp_load_file {
  my $filename = shift;
  my $ref_data = shift;

  my $tool_time       = "";    # this tool time updated before every wmic cmd
  my $hyperv_time     = "";    # from hyperv server
  my $tool_start_time = 0;     # this tool time when hyperv_time is read
  my $delta_time      = "";    # difference = tool_time - $tool_start_time

  my $num_of_keys     = 0;
  my $num_of_lines    = 0;
  my $num_of_comps    = 0;
  my $hyperv_comp     = "";
  my $hyperv_comp_wmi = "";

  my $index      = 0;
  my $time_index = "";
  my $class;
  my $global_info_is_read = 1;
  my $local_info_is_read  = 1;
  my $computer_domain     = "";

  my $cluster_name = "";
  %skipped_computers = ();

  open my $FH, "$filename" or error( "can't open $filename: $!" . __FILE__ . ":" . __LINE__ ) && return;

  while ( my $line = <$FH> ) {
    chomp $line;
    $line =~ s/\r$//;                 # there is one at the end of file
                                      # print "6074 \$line $line\n";
    next if $line eq "" or length($line) < 4;
    if ( $line =~ /^#/ ) { next; }    # omit comments

    if ( length($line) > $max_line_length ) {
      error( "avoid line longer than limit $max_line_length (see 1st 1000 chars) : ", substr( $line, 0, 1000 ) );
      next;
    }
    if ( $line =~ /^GLOBAL INFO BEGIN/ ) {
      $global_info_is_read = 0;
      next;
    }
    if ( $line =~ /^GLOBAL INFO END/ ) {
      $global_info_is_read = 1;
      next;
    }
    if ( !$global_info_is_read ) {
      push @global_info, $line;
      next;
    }
    if ( $line =~ /^LOCAL INFO BEGIN/ ) {
      $local_info_is_read = 0;
      next;
    }
    if ( $line =~ /^LOCAL INFO END/ ) {
      $local_info_is_read = 1;
      next;
    }
    if ( !$local_info_is_read ) {
      push @local_info, $line;
      next;
    }

    if ( $line =~ /^date / ) {
      ( undef, my $r_time ) = split( " Unix ", $line );
      chomp $r_time;
      $tool_time = $r_time if $r_time =~ /\d\d\d\d\d\d\d\d\d\d/;
      next;
    }

    if ( ( $line =~ /^Get-wmiobject / ) or ( $line =~ /^Get-ciminstance / ) ) {
      if ( $line =~ /Win32_OperatingSystem/ ) {    # test if computer is in domain
        $computer_domain = "";                     # contains domain (used then in case of not detected Win32_ComputerSystem data)

        # Get-wmiobject -Query select CSName,Name,LocalDateTime,Caption,OtherTypeDescription,CSDVersion,Version from Win32_OperatingSystem -cn CN=PTEMCZDC02,OU=Domain Controllers,DC=dmz,DC=ecom.Name -EA silentlyContinue |Select-Object CSName Name LocalDateTime Caption OtherTypeDescription CSDVersion Version
        # another type when asking list of comps (not AD)
        # Get-wmiobject -Query select CSName,Name,LocalDateTime,Caption,OtherTypeDescription,CSDVersion,TotalVisibleMemorySize,Version from Win32_OperatingSystem -cn @{Name=DC}.Name -EA silentlyContinue |Select-Object CSName Name LocalDateTime Caption OtherTypeDescription CSDVersion TotalVisibleMemorySize Version
        # Get-wmiobject -Query select CSName,Name,LocalDateTime,Caption,OtherTypeDescription,CSDVersion,TotalVisibleMemorySize,Version from Win32_OperatingSystem -cn @{Name=winhv01.wds.local}.Name -EA silentlyContinue |Select-Object CSName Name LocalDateTime Caption OtherTypeDescription CSDVersion TotalVisibleMemorySize Version
        #
        $hyperv_comp_wmi = "not in domain";    # or contains computer's name
        if ( $line =~ /-cn CN=/ ) {
          ( undef, $hyperv_comp_wmi ) = split( "-cn CN=", $line );
          ( $hyperv_comp_wmi, undef ) = split( ",", $hyperv_comp_wmi );
          print_hyperv_debug("4486 \$hyperv_comp_wmi $hyperv_comp_wmi\n");    # if $DEBUG == 2;
        }
        elsif ( $line =~ /@\{Name=/ && $line !~ /Name=localhost/ ) {          # this is standalone comp, let it be
          ( undef, $hyperv_comp_wmi ) = split( /@\{Name=/, $line );
          ( $hyperv_comp_wmi, undef ) = split( /\}/, $hyperv_comp_wmi );

          # sometimes here is domain name like "Name=ADC1CLU004.Beerdivision.africa.gcn.local" -> this can be computer domain
          $computer_domain = ( split( /\./, $hyperv_comp_wmi, 2 ) )[1] if index( $hyperv_comp_wmi, "." ) ne -1;
          $computer_domain = $hyperv_comp_wmi                          if $computer_domain eq "";

          # print_hyperv_debug("4495 \$hyperv_comp_wmi $hyperv_comp_wmi\n");    # if $DEBUG == 2;
          print "comp domain    : type @\{Name= \$hyperv_comp_wmi ,$hyperv_comp_wmi, \$computer_domain ,$computer_domain,\n";
        }
        if ( $line =~ /DC=/ ) {

          # print "7037 \$line $line\n";
          my @parts = split( "DC=", $line );

          # print "arr1 @parts\n";
          shift @parts;

          # print "arr2 @parts\n";
          $computer_domain = "";
          foreach my $atom (@parts) {
            $atom =~ s/,//;
            if ( $atom =~ /\.Name/ ) {
              $atom =~ s/\.Name.*//;
              if ( $computer_domain eq "" ) {
                $computer_domain = $atom;
              }
              else {
                $computer_domain .= "." . $atom;
              }
              last;
            }
            else {
              if ( $computer_domain eq "" ) {
                $computer_domain = $atom;
              }
              else {
                $computer_domain .= "." . $atom;
              }
            }
          }
          print "comp domain    : type DC= \$hyperv_comp_wmi ,$hyperv_comp_wmi, \$computer_domain ,$computer_domain,\n";
        }
        if ( $computer_domain eq "" ) {
          $computer_domain = $UnDeF;
        }
      }
      next;
    }

    if ( $hyperv_comp_wmi eq "skip_this_comp" ) {    # this is set if cluster
                                                     # do not skip for the case: the comp has agent & is cluster too
                                                     #      next;
    }

    if ( $line =~ /^CLASS: / ) {
      ( undef, $class ) = split( "CLASS: ", $line );
      $index = 0;
      next if $class eq "";
      chomp $class;

      # print "4541 \$class $class\n";
      next if $class !~ "Win32_OperatingSystem";

      # here $class =~ "Win32_OperatingSystem"
      my $hyp_line_names  = <$FH>;
      my $hyp_line_values = <$FH>;

      # e.g.:
      # "PSComputerName","__GENUS","__CLASS","__SUPERCLASS","__DYNASTY","__RELPATH","__PROPERTY_COUNT","__DERIVATION","__SERVER","__NAMESPACE","__PATH","Caption","CSDVersion","CSName","LocalDateTime","Name","OtherTypeDescription","Version"
      #,"2","Win32_OperatingSystem",,,"Win32_OperatingSystem=@","7","System.String[]",,,,"Microsoft Windows Server 2016 Standard",,"HYPERV","20180412153005.744000+120","Microsoft Windows Server 2016 Standard|C:\Windows|\Device\Harddisk0\Partition4",,"10.0.14393"
      #"CSName","Name","LocalDateTime","Caption","OtherTypeDescription","CSDVersion","TotalVisibleMemorySize","Version"
      #"DC","Microsoft Windows Server 2016 Standard|C:\Windows|\Device\Harddisk0\Partition2","20190815145521.829000+120","Microsoft Windows Server 2016 Standard",,,"8388148","10.0.14393"

      ## later on: char "|" is used as delimiter of atoms so it is necessary:
      ## "|" replace with "!" it looks very similar :)
      ## "," or ", or ," replace with | or | or | taking care because "," can be used inside of atom
      ## and then of course remove the " in the beginning and in the end of data line
      chomp $hyp_line_names;
      $hyp_line_names =~ s/\r$//;    # there is one at the end of file, or you get debug files from upload
      chomp $hyp_line_values;
      $hyp_line_values =~ s/\r$//;

      #      print "4563 \$hyp_line_names $hyp_line_names\n";
      #      print "4564 \$hyp_line_values $hyp_line_values\n";
      next if $hyp_line_names eq "";
      next if $hyp_line_names =~ /ERROR/;

      $tool_start_time = $tool_time;    # set in Win32_OperatingSystem as this is beginning of computer data

      # this  $class =~ "Win32_OperatingSystem" starts new computer, $hyperv_comp & $hyperv_time vars must be set
      # prepared computer_domain save as last but one item with this class
      # retrieve hyperv server time immediately and save as last item with every line
      # retrieve computer name and test against name in Get-wmiobject line, this is different for Cluster
      if ( $hyp_line_names =~ /LocalDateTime/ && $hyp_line_names =~ /CSName/ ) {
        my @os_arr = split( /,/, $hyp_line_names );
        ($time_index)  = grep { $os_arr[$_] eq "\"LocalDateTime\"" } 0 .. $#os_arr;
        ($hyperv_comp) = grep { $os_arr[$_] eq "\"CSName\"" } 0 .. $#os_arr;

        #        print "6112 \$time_index $time_index \$hyperv_comp index $hyperv_comp\n";
        @os_arr      = split( /,/, $hyp_line_values );
        $hyperv_comp = $os_arr[$hyperv_comp];

        # test if this computer has already been loaded - in case of cluster, as cluster comp is the same as one of its nodes
        $hyperv_comp =~ s/\"//g;

        # print "7224 \$hyperv_time $hyperv_time comp name \$hyperv_comp $hyperv_comp \$hyperv_comp_wmi $hyperv_comp_wmi \$cluster_name $cluster_name \n";
        #$cluster_name = $hyperv_comp_wmi if lc($hyperv_comp_wmi) ne lc($hyperv_comp);

        if ( ( lc($hyperv_comp_wmi) ne lc($hyperv_comp) ) && ( lc($hyperv_comp_wmi) ne "localhost" ) && ( lc($hyperv_comp) ne "localhost" ) && ( $hyperv_comp_wmi ne "not in domain" ) ) {
          $cluster_name = $hyperv_comp_wmi;

          my $cluster_maybe = $hyperv_comp_wmi;
          $cluster_maybe =~ s/\..*//;
          if ( $cluster_maybe ne $hyperv_comp ) {
            print "diff names may be cluster \$cluster_maybe $cluster_maybe \$hyperv_comp_wmi $hyperv_comp_wmi \$hyperv_comp $hyperv_comp\n";

            #$cluster_computers{$cluster_maybe}{$hyperv_comp} = 1;
            $cluster_computers{$cluster_maybe} = $hyperv_comp;
          }

          # $ref_data->{$hyperv_comp}{cluster_name} = $cluster_name;

          # print "comp $hyperv_comp is skipped\n";
          print "comp $hyperv_comp is NOT skipped\n";
          $skipped_computers{$hyperv_comp} = $cluster_name;
          $hyperv_comp_wmi = "skip_this_comp";

          # do not skip for the case: the comp has agent & is cluster too
          #          next;

          if ( exists $ref_data->{$hyperv_comp} ) {

            # $ref_data->{$hyperv_comp}{cluster_name} = $cluster_name;
            # $ref_data->{$hyperv_comp}{cluster_name} = $cluster_name;
            # print "comp $hyperv_comp is skipped\n";
            print "comp $hyperv_comp is NOT skipped\n";

            # $skipped_computers{$hyperv_comp} = $hyperv_comp_wmi;
            $skipped_computers{$hyperv_comp} = $cluster_name;
            $hyperv_comp_wmi = "skip_this_comp";

            # do not skip for the case: the comp has agent & is cluster too
            #            next;
          }
        }

        $hyperv_time = $os_arr[$time_index];
        print_hyperv_debug("4628 \$hyperv_time $hyperv_time comp name $hyperv_comp $hyperv_comp_wmi \$class ,$class,\n") if $DEBUG == 2;

        #        if (($hyperv_comp_wmi ne "not in domain") && ($hyperv_comp ne "\"$hyperv_comp_wmi\"")) {
        #          # skipped computers can be clusters
        #          $hyperv_comp =~ s/\"//g;
        #          $skipped_computers{$hyperv_comp} = $hyperv_comp_wmi;
        #          $hyperv_comp_wmi = "skip_this_comp";
        #          next;
        #        }

        # write $class info to hash
        $index      = 0;
        $delta_time = $tool_time - $tool_start_time;

        # comma_to_pipe (\$hyp_line_names);
        $ref_data->{$hyperv_comp}{$class}[ $index++ ] = $hyp_line_names . ",\"computerdomain\",Hyperv_UTC";
        $num_of_keys++;

        # in case ciminstance the format is "04/19/2023 09:00:05"
        #        print "6138 ".substr( $hyperv_time, 1, 8 ) . "T" . substr( $hyperv_time, 9, 6 )."\n";
        # print "4648 \$hyperv_time $hyperv_time\n";
        if ( index( $hyperv_time, ":" ) > -1 ) {
          $hyperv_time =~ s/\"//g;
          $hyperv_time = str2time($hyperv_time);
        }
        else {
          $hyperv_time = str2time( substr( $hyperv_time, 1, 8 ) . "T" . substr( $hyperv_time, 9, 6 ) );
        }

        # print "4656 \$hyperv_time $hyperv_time\n";

        # my $hyperv_time_to_save = $hyperv_time + $delta_time;
        # w10 sometimes gives time in diff zones "20180918095509.693000+120" or "20180918094009.309000+060", use direct unix time sent from windows
        my $hyperv_time_to_save = $tool_time;
        $hyp_line_values .= "," . "\"" . $computer_domain . "\"" . ",$hyperv_time_to_save";

        # comma_to_pipe (\$hyp_line_values);
        $ref_data->{$hyperv_comp}{$class}[ $index++ ] = $hyp_line_values;

        # print "4666 \$hyperv_time_to_save $hyperv_time_to_save \$tool_time $tool_time\n";
        $num_of_lines++;
        next;
      }
      else {
        print "can not find LocalDateTime & CSName in Win32_OperatingSystem <$hyp_line_names>\n";
        $hyperv_comp = "";
        $index       = 0;
        $time_index  = "";
        next;
      }
    }
    $delta_time = $tool_time - $tool_start_time;

    #    print "6157 \$tool_time $tool_time \$tool_start_time $tool_start_time\n";
    if ( !defined $hyperv_time ) {
      $hyperv_time = 0;
      print "not defined hyperv_time in CLASS $class \$line $line\n";
      next;
    }
    if ( $index == 0 ) {
      next if $hyperv_comp eq "" || $class eq "";
      $line .= ",Hyperv_UTC";

      # comma_to_pipe (\$line);
      print_hyperv_debug("6716 \$hyperv_time $hyperv_time comp name $hyperv_comp $hyperv_comp_wmi \$class ,$class,\n") if $DEBUG == 2;
      $ref_data->{$hyperv_comp}{$class}[ $index++ ] = $line;
      $num_of_keys++;
    }
    else {
      #my $hyperv_time_to_save = $hyperv_time + $delta_time;
      # w10 sometimes gives time in diff zones "20180918095509.693000+120" or "20180918094009.309000+060", use direct unix time sent from windows
      my $hyperv_time_to_save = $tool_time;

      # print "6620 \$hyperv_time_to_save $hyperv_time_to_save \$tool_time $tool_time\n";
      $line .= ",$hyperv_time_to_save";

      # comma_to_pipe (\$line);
      $line =~ s/,(?!(?:[^"]*"[^"]*")*[^"]*$)/\./g;    # in case "," is inside of atom e.g. "Windows(R) Operating System, RETAIL channel","1","8HVX7"
                                                       # see demo https://regex101.com/r/t5Euq1/1
      $ref_data->{$hyperv_comp}{$class}[ $index++ ] = $line;
      $num_of_lines++;
    }
  }
  close $FH;

  #print Dumper ( \%hyp_data );
  print "Hyper_v data   : hash has keys: $num_of_keys lines: $num_of_lines from file $filename\n";
}

sub comma_to_pipe {
  my $ref_str = shift;
  $$ref_str =~ s/\|/!/g;
  $$ref_str =~ s/\"\,\"/\|/g;
  $$ref_str =~ s/\"\,/\|/g;
  $$ref_str =~ s/\,\"/\|/g;
  $$ref_str =~ s/^\"//;
  $$ref_str =~ s/\$\"//;
  $$ref_str =~ s/\|\,/\|\|/g;
  return;
}

sub print_hyperv_debug {
  my $text = shift;
  print "$text";
}

