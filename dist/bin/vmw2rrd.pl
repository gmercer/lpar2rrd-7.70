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
use LoadDataModuleVMWare;
use File::Copy;
use POSIX qw(strftime);
use Time::HiRes qw(sleep);

#use File::Glob ':glob';

require VMware::VIRuntime;
require VMware::VILib;

use Data::Dumper;
use Time::Local;
use POSIX ":sys_wait_h";
use File::Glob qw(bsd_glob GLOB_TILDE);
use Xorux_lib qw(error read_json write_json);
use XoruxEdition;

#use lib qw (/opt/freeware/lib/perl/5.8.0);
# no longer need to use "use lib qw" as the library PATH is already in PERL5LIB env var (lpar2rrd.cfg)

# set unbuffered stdout
$| = 1;

my $simulate_esxi_fork  = 0;
my $multiview_hmc_count = 0;    #do not let it run more than twice

# get cmd line params
my $version = "$ENV{version}";
my $host    = $ENV{HMC};         # contains alias and username
my $host_orig;                   # later keeps host name

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

# Next Generation
my $NG = ( defined $ENV{NG} ) ? 1 : 0;

my $actprogsize = -s "$basedir/bin/vmw2rrd.pl";

#my $rrdtool                 = $ENV{RRDTOOL};
my $DEBUG = $ENV{DEBUG};
$DEBUG = 1;
my $problem_server_name = "";    # for debug purpose

my $pic_col                 = $ENV{PICTURE_COLOR};
my $STEP                    = $ENV{SAMPLE_RATE};
my $CONFIG_HISTORY          = $basedir . "/data";              # do not change that as subdir tree is not created automatically here but via main loop
my $managed_systems_exclude = $ENV{MANAGED_SYSTEMS_EXCLUDE};
my $upgrade                 = $ENV{UPGRADE};
my $SSH                     = $ENV{SSH} . " -q ";              # doubles -q from lpar2rrd.cfg, just to be sure ...

my $YEAR_REFRESH  = 86400;                                     # 24 hour, minimum time in sec when yearly graphs are updated (refreshed)
my $MONTH_REFRESH = 39600;                                     # 11 hour, minimum time in sec when monthly graphs are updated (refreshed)
my $WEEK_REFRESH  = 18000;                                     # 5 hour, minimum time in sec when weekly  graphs are updated (refreshed)

###  VMWARE def section

my $all_esxi_vm = 1;                                           # get perf data from all VMs in one cmd, if 0 then problem with datastore counter values from VMs
my @esxi_vm_entities;
my @all_vcenter_perf_data = ();

my $command_date;                                              # vmware server time when starting this script

my $et_VirtualMachine         = "VirtualMachine";
my $et_HostSystem             = "HostSystem";
my $et_Datastore              = "Datastore";
my $et_ResourcePool           = "ResourcePool";
my $et_Datacenter             = "Datacenter";
my $et_ClusterComputeResource = "ClusterComputeResource";

my $st_date              = "first time";
my $end_date             = "";
my $pef_time_sec         = "";
my @vm_dstr_counter_data = ();

# my @vm_counter_data      = ();
my %vm_hash               = ();    # for VMs counter data
my %vm_uuid_name_hash     = ();    # using later when generating cmd rrd aggregated files
my %esxi_dbi_uuid_hash    = ();    # key moref, use later
my $first_vm_counter_data = "";

my $no_inserted                = 66;
my $real_sampling_period_limit = 900;
my %vm_name_uuid;
my %vm_id_path            = ();    # contains vm_id : $wrkdir/$server/host/vm_uuid.rrm
my %vm_moref_uuid         = ();    # easy conversion used for IOPS VM perf data
my %host_moref_name       = ();
my $vcenter_vm_views      = ();
my %vcenter_vm_views_hash = ();    # holds pointers to array items (VMs)
my $samples_number;

### VM with this pattern in name will be excluded
# my @vm_name_patterns_to_exclude = ( "GX_BACKUP", ".copy.shadow" );
my @vm_name_patterns_to_exclude = ( "GX_BACKUP", ".copy.shadow", "cp-replica-", "cp-parent-" );

sub exclude_vm {
  my $vm_name = shift;
  my $print_t = shift;

  my $exclude = 0;
  foreach my $pattern (@vm_name_patterns_to_exclude) {
    $exclude = 1 if ( index( $vm_name, $pattern ) > -1 );
  }
  if ($exclude) {
    print "exclude VM     : $vm_name\n" if $print_t;
    return $exclude;
  }
  if ( defined $ENV{VM_NAME_REGEX_PATTERNS_TO_EXCLUDE} ) {    # comma delimited
    foreach my $pattern ( split ",", $ENV{VM_NAME_REGEX_PATTERNS_TO_EXCLUDE} ) {

      # print "124 \$pattern ,$pattern, \$vm_name $vm_name\n";
      $exclude = 1 if ( $vm_name =~ /$pattern/ );
    }
    if ($exclude) {
      print "exclude VM     : $vm_name\n" if $print_t;
      return $exclude;
    }
  }
  return $exclude;
}

### datastore with this pattern in name will be excluded
my @ds_name_patterns_to_exclude = ( "GX_BACKUP", ".copy.shadow" );

#@ds_name_patterns_to_exclude = ("ISO");

#    my @vm_CPU_usage_percent;   # not used

#   perf values Hostsystem or VM
my @vm_CPU_Alloc_reservation;
my @vm_CPU_usage_MHz;
my @vm_host_hz;
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
my @vm_CPU_ready_ms;
my @vm_Memory_consumed_KB;    # for cluster & resourcepool metric
my @vm_Power_usage_Watt;      # for cluster metric

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
my $rp_cpu_limit       = 0;
my $rp_cpu_alloc_type  = 0;
my $rp_cpu_shares      = 0;
my $rp_cpu_value       = 0;

my $rp_mem_reservation = 0;
my $rp_mem_limit       = 0;
my $rp_mem_alloc_type  = 0;
my $rp_mem_shares      = 0;
my $rp_mem_value       = 0;

#   perf values datastore
my @ds_Datastore_freeSpace_KB;
my @ds_Datastore_used_KB;
my @ds_Datastore_provision_KB;
my @ds_Datastore_capacity_KB;
my @ds_Datastore_read_KBps;
my @ds_Datastore_write_KBps;
my @ds_Datastore_numberReadAveraged;
my @ds_Datastore_numberWriteAveraged;
my @ds_Datastore_totalReadLatency;
my @ds_Datastore_totalWriteLatency;
my $ds_totalReadLatency_limit  = 10000;    # millisec
my $ds_totalWriteLatency_limit = 10000;    # millisec

my $ds_accessible;                         # true/false 1/0
my $ds_freeSpace;
my $ds_used;
my $ds_provisioned;
my $ds_capacity;
my $ds_type = "";                          # or 'NFS' when NFS type

my $service_instance;                      # vmware TOP
my $apiType_top;
my $fullName_top;
my $vmware_uuid;
my $vmware_id = "";
my $do_fork;                               # 1 means do!, 0 do not!
my $managednamelist_un;
my @rp_vm_morefs = ();

my $datacenter_list;
my $global_datacenter_name;
my $datastore_list;
my $cluster_list;
my $resourcepool_list;
my $datacenter;
my $latency_peak_reached_count = 0;

my $perfmgr_view;
my $now_counters;
my $all_counters;
my $cpu_counters;
my $memory_counters;
my $disk_counters;
my $system_counters;
my $net_counters;

# selected_counters set up in sub init_perf_counter_info
my $selected_counters;    # number of counters to retrieve from entity
my $error_select_counters = 0;
my $host_hz;
my $host_cpuAlloc;
my $host_memorySize;

my $server;
my $command_unix;         # holds server UTC unix time - integer
my $vm_host;              # host hash
my $h_name;               # host name
my $fail_entity_type;     # for error printing
my $fail_entity_name;     # for error printing
my $rp_name;
my $rp_moref;
my $rp_parent;
my $ds_name;
my $ds_parent_folder;
my $historical_level0 = 0;
my $numCpu;
my %rp_group_path = ();    # keeps RP path for RP folder structure

# keeps all VMs: $wrkdir/$all_vmware_VMs
my $all_vmware_VMs = "vmware_VMs";

# change key only first time - when setting counters by first VM
my $vm_dstr_readAveraged_key  = "9999";
my $vm_dstr_writeAveraged_key = "9999";
my $vm_dstr_read_key          = "9999";
my $vm_dstr_write_key         = "9999";
my $vm_dstr_readLatency_key   = "9999";
my $vm_dstr_writeLatency_key  = "9999";

my $vm_uuid_active = "";
my @counter_arr_levels;
my %vm_group_path = ();    # keeps VM path for Vm folder structure
my %ds_group_path = ();    # keeps DS path for DS folder structure

# keeps uuid{name} for all vmware VMs
my $all_vm_uuid_names = "vm_uuid_name.txt";

# VM_hosting.vmh keeps presence of VMs in a Host system (esxi server)
# res_pool_name.vmr keeps presence of VMs in a ResourcePool

# function xerror if main: appends notice to following file
#                 if fork: just prints XERROR text
#        XERROR text is appended when reading forks' output
my $counters_info_file = "$basedir/logs/counter-info.txt";
my $i_am_fork          = "main";                             # in fork is 'fork'

my @counter_presence = ();                                   # indicates real counter presence

#  testing real counters
#  VirtualMachine
my @counter_vm_eng  = ( 'CPU:usagemhz:MHz', 'Disk:usage:KBps',         'Disk:read:KBps',         'Disk:write:KBps',         'Network:usage:KBps',    'Network:received:KBps',    'Network:transmitted:KBps',    'Memory:active:KB',          'Memory:granted:KB',          'Memory:swapinRate:KBps',            'Memory:vmmemctl:KB',                 'Memory:swapoutRate:KBps',                  'Memory:decompressionRate:KBps', 'Memory:compressionRate:KBps', 'CPU:usage:Percent', 'CPU:ready:Millisecond', 'Memory:consumed:KB', 'Datastore:numberReadAveraged:Number', 'Datastore:numberWriteAveraged:Number', 'Datastore:read:KBps', 'Datastore:write:KBps', 'Datastore:totalReadLatency:Millisecond', 'Datastore:totalWriteLatency:Millisecond' );
my @counter_vm_eng6 = ( 'CPU:usagemhz:MHz', 'Disk:usage:KBps',         'Disk:read:KBps',         'Disk:write:KBps',         'Network:usage:KBps',    'Network:received:KBps',    'Network:transmitted:KBps',    'Memory:active:KB',          'Memory:granted:KB',          'Memory:swapinRate:KBps',            'Memory:vmmemctl:KB',                 'Memory:swapoutRate:KBps',                  'Memory:decompressionRate:KBps', 'Memory:compressionRate:KBps', 'CPU:usage:%',       'CPU:ready:ms', );
my @counter_vm_ger1 = ( 'CPU:usagemhz:MHz', 'Festplatte:usage:KB/s',   'Festplatte:read:KB/s',   'Festplatte:write:KB/s',   'Netzwerk:usage:KB/s',   'Netzwerk:received:KB/s',   'Netzwerk:transmitted:KB/s',   'Arbeitsspeicher:active:KB', 'Arbeitsspeicher:granted:KB', 'Arbeitsspeicher:swapinRate:KB/s',   'Arbeitsspeicher:vmmemctl:KB',        'Arbeitsspeicher:swapoutRate:KB/s',         'Arbeitsspeicher:decompressionRate:KB/s', 'Arbeitsspeicher:compressionRate:KB/s', 'CPU:usage:Prozent', 'CPU:ready:Millisekunde', 'Festplatte:numberRead:Anzahl', 'Festplatte:numberWrite:Anzahl' );
my @counter_vm_ger2 = ( 'CPU:usagemhz:MHz', 'Festplatte:usage:KBit/s', 'Festplatte:read:KBit/s', 'Festplatte:write:KBit/s', 'Netzwerk:usage:KBit/s', 'Netzwerk:received:KBit/s', 'Netzwerk:transmitted:KBit/s', 'Arbeitsspeicher:active:KB', 'Arbeitsspeicher:granted:KB', 'Arbeitsspeicher:swapinRate:KBit/s', 'Arbeitsspeicher:swapoutRate:KBit/s', 'Arbeitsspeicher:decompressionRate:KBit/s', 'Arbeitsspeicher:compressionRate:KBit/s' );
my $memfr           = "M" . "\xe9" . "moire";
my $resfr           = "R" . "\xe9" . "seau";
my @counter_vm_fr   = ( 'CPU:usagemhz:MHz', 'Disque:usage:Ko/s', 'Disque:read:Ko/s', 'Disque:write:Ko/s', "$resfr:usage:Ko/s", "$resfr:received:Ko/s", "$resfr:transmitted:Ko/s", "$memfr:active:Ko",  "$memfr:granted:Ko",  "$memfr:swapinRate:Ko/s",  "$memfr:vmmemctl:Ko",  "$memfr:swapoutRate:Ko/s",  "$memfr:decompressionRate:Ko/s",  "$memfr:compressionRate:Ko/s",  'CPU:usage:Pourcent', 'CPU:ready:Milliseconde', );
my @counter_vm_esp  = ( 'CPU:usagemhz:MHz', 'Disco:usage:KBps',  'Disco:read:KBps',  'Disco:write:KBps',  'Red:usage:KBps',    'Red:received:KBps',    'Red:transmitted:KBps',    'Memoria:active:KB', 'Memoria:granted:KB', 'Memoria:swapinRate:KBps', 'Memoria:vmmemctl:KB', 'Memoria:swapoutRate:KBps', 'Memoria:decompressionRate:KBps', 'Memoria:compressionRate:KBps', 'CPU:usage:Percent',  'CPU:ready:Millisecond', 'Memoria:consumed:KB', 'Datastore:numberReadAveraged:Number', 'Datastore:numberWriteAveraged:Number', 'Datastore:read:KBps', 'Datastore:write:KBps', 'Datastore:totalReadLatency:Millisecond', 'Datastore:totalWriteLatency:Millisecond' );

#  HostSystem
my @counter_hs_eng  = ( 'CPU:usagemhz:MHz', 'Disk:usage:KBps',         'Disk:read:KBps',         'Disk:write:KBps',         'Network:usage:KBps',    'Network:received:KBps',    'Network:transmitted:KBps',    'Memory:active:KB',          'Memory:granted:KB',          'Memory:swapinRate:KBps',            'Memory:vmmemctl:KB',                 'Memory:swapoutRate:KBps',                  'Memory:decompressionRate:KBps', 'Memory:compressionRate:KBps', 'CPU:usage:Percent', 'CPU:ready:Millisecond', 'Power:power:Watt' );
my @counter_hs_eng6 = ( 'CPU:usagemhz:MHz', 'Disk:usage:KBps',         'Disk:read:KBps',         'Disk:write:KBps',         'Network:usage:KBps',    'Network:received:KBps',    'Network:transmitted:KBps',    'Memory:active:KB',          'Memory:granted:KB',          'Memory:swapinRate:KBps',            'Memory:vmmemctl:KB',                 'Memory:swapoutRate:KBps',                  'Memory:decompressionRate:KBps', 'Memory:compressionRate:KBps', 'CPU:usage:%',       'CPU:ready:ms',          'Power:power:W' );
my @counter_hs_ger1 = ( 'CPU:usagemhz:MHz', 'Festplatte:usage:KB/s',   'Festplatte:read:KB/s',   'Festplatte:write:KB/s',   'Netzwerk:usage:KB/s',   'Netzwerk:received:KB/s',   'Netzwerk:transmitted:KB/s',   'Arbeitsspeicher:active:KB', 'Arbeitsspeicher:granted:KB', 'Arbeitsspeicher:swapinRate:KB/s',   'Arbeitsspeicher:vmmemctl:KB',        'Arbeitsspeicher:swapoutRate:KB/s',         'Arbeitsspeicher:decompressionRate:KB/s', 'Arbeitsspeicher:compressionRate:KB/s', 'CPU:usage:Prozent', 'CPU:ready:Millisekunde', );
my @counter_hs_ger2 = ( 'CPU:usagemhz:MHz', 'Festplatte:usage:KBit/s', 'Festplatte:read:KBit/s', 'Festplatte:write:KBit/s', 'Netzwerk:usage:KBit/s', 'Netzwerk:received:KBit/s', 'Netzwerk:transmitted:KBit/s', 'Arbeitsspeicher:active:KB', 'Arbeitsspeicher:granted:KB', 'Arbeitsspeicher:swapinRate:KBit/s', 'Arbeitsspeicher:swapoutRate:KBit/s', 'Arbeitsspeicher:decompressionRate:KBit/s', 'Arbeitsspeicher:compressionRate:KBit/s' );
my @counter_hs_fr   = ( 'CPU:usagemhz:MHz', 'Disque:usage:Ko/s',       'Disque:read:Ko/s',       'Disque:write:Ko/s',       "$resfr:usage:Ko/s",     "$resfr:received:Ko/s",     "$resfr:transmitted:Ko/s",     "$memfr:active:Ko",          "$memfr:granted:Ko",          "$memfr:swapinRate:Ko/s",            "$memfr:vmmemctl:Ko",                 "$memfr:swapoutRate:Ko/s",                  "$memfr:decompressionRate:Ko/s",  "$memfr:compressionRate:Ko/s",  'CPU:usage:Pourcent', 'CPU:ready:Milliseconde', );
my @counter_hs_esp  = ( 'CPU:usagemhz:MHz', 'Disco:usage:KBps',        'Disco:read:KBps',        'Disco:write:KBps',        'Red:usage:KBps',        'Red:received:KBps',        'Red:transmitted:KBps',        'Memoria:active:KB',         'Memoria:granted:KB',         'Memoria:swapinRate:KBps',           'Memoria:vmmemctl:KB',                'Memoria:swapoutRate:KBps',                 'Memoria:decompressionRate:KBps', 'Memoria:compressionRate:KBps', 'CPU:usage:Percent',  'CPU:ready:Millisecond', );

#  cluster
my @counter_cl_eng  = ( 'CPU:usagemhz:MHz', 'CPU:usage:Percent',  'CPU:reservedCapacity:MHz', 'CPU:totalmhz:MHz', 'Cluster services:effectivecpu:MHz', 'Cluster services:effectivemem:MB', 'Memory:totalmb:MB',          'Memory:shared:KB',          'Memory:zero:KB',          'Memory:vmmemctl:KB',          'Memory:consumed:KB',          'Memory:overhead:KB',          'Memory:active:KB',          'Memory:granted:KB',          'Memory:compressed:KB',          'Memory:reservedCapacity:MB',          'Memory:swapused:KB',          'Memory:compressionRate:KBps',          'Memory:decompressionRate:KBps',          'Memory:usage:Percent',          'Power:powerCap:Watt',        'Power:power:Watt' );           # do not take 'Power:energy:Joule'
my @counter_cl_eng6 = ( 'CPU:usagemhz:MHz', 'CPU:usage:%',        'CPU:reservedCapacity:MHz', 'CPU:totalmhz:MHz', 'Cluster services:effectivecpu:MHz', 'Cluster services:effectivemem:MB', 'Memory:totalmb:MB',          'Memory:shared:KB',          'Memory:zero:KB',          'Memory:vmmemctl:KB',          'Memory:consumed:KB',          'Memory:overhead:KB',          'Memory:active:KB',          'Memory:granted:KB',          'Memory:compressed:KB',          'Memory:reservedCapacity:MB',          'Memory:swapused:KB',          'Memory:compressionRate:KBps',          'Memory:decompressionRate:KBps',          'Memory:usage:%',                'Power:powerCap:W',           'Power:power:W' );              # do not take 'Power:energy:Joule'
my @counter_cl_ger  = ( 'CPU:usagemhz:MHz', 'CPU:usage:Prozent',  'CPU:reservedCapacity:MHz', 'CPU:totalmhz:MHz', 'Clusterdienste:effectivecpu:MHz',   'Clusterdienste:effectivemem:MB',   'Arbeitsspeicher:totalmb:MB', 'Arbeitsspeicher:shared:KB', 'Arbeitsspeicher:zero:KB', 'Arbeitsspeicher:vmmemctl:KB', 'Arbeitsspeicher:consumed:KB', 'Arbeitsspeicher:overhead:KB', 'Arbeitsspeicher:active:KB', 'Arbeitsspeicher:granted:KB', 'Arbeitsspeicher:compressed:KB', 'Arbeitsspeicher:reservedCapacity:MB', 'Arbeitsspeicher:swapused:KB', 'Arbeitsspeicher:compressionRate:KB/s', 'Arbeitsspeicher:decompressionRate:KB/s', 'Arbeitsspeicher:usage:Prozent', 'Betrieb:powerCap:Watt',      'Betrieb:power:Watt' );         # do not take 'Power:energy:Joule'
my @counter_cl_ger6 = ( 'CPU:usagemhz:MHz', 'CPU:usage:%',        'CPU:reservedCapacity:MHz', 'CPU:totalmhz:MHz', 'Clusterdienste:effectivecpu:MHz',   'Clusterdienste:effectivemem:MB',   'Arbeitsspeicher:totalmb:MB', 'Arbeitsspeicher:shared:KB', 'Arbeitsspeicher:zero:KB', 'Arbeitsspeicher:vmmemctl:KB', 'Arbeitsspeicher:consumed:KB', 'Arbeitsspeicher:overhead:KB', 'Arbeitsspeicher:active:KB', 'Arbeitsspeicher:granted:KB', 'Arbeitsspeicher:compressed:KB', 'Arbeitsspeicher:reservedCapacity:MB', 'Arbeitsspeicher:swapused:KB', 'Arbeitsspeicher:compressionRate:KB/s', 'Arbeitsspeicher:decompressionRate:KB/s', 'Arbeitsspeicher:usage:%',       'Betrieb:powerCap:Watt',      'Betrieb:power:Watt' );         # do not take 'Power:energy:Joule'
my @counter_cl_fr   = ( 'CPU:usagemhz:MHz', 'CPU:usage:Pourcent', 'CPU:reservedCapacity:MHz', 'CPU:totalmhz:MHz', 'Cluster services:effectivecpu:MHz', 'Cluster services:effectivemem:MB', "$memfr:totalmb:Mo",          "$memfr:shared:Ko",          "$memfr:zero:Ko",          "$memfr:vmmemctl:Ko",          "$memfr:consumed:Ko",          "$memfr:overhead:Ko",          "$memfr:active:Ko",          "$memfr:granted:Ko",          "$memfr:compressed:Ko",          "$memfr:reservedCapacity:Mo",          "$memfr:swapused:Ko",          "$memfr:compressionRate:Ko/s",          "$memfr:decompressionRate:Ko/s",          "$memfr:usage:Pourcent",         'Alimentation:powerCap:Watt', 'Alimentation:power:Watt' );    # do not take 'Power:energy:Joule'

#  resource pool
my @counter_rp_eng = ( 'CPU:usagemhz:MHz', 'Memory:shared:KB',          'Memory:zero:KB',          'Memory:vmmemctl:KB',          'Memory:consumed:KB',          'Memory:overhead:KB',          'Memory:active:KB',          'Memory:granted:KB',          'Memory:compressed:KB',          'Memory:swapped:KB',          'Memory:compressionRate:KBps',          'Memory:decompressionRate:KBps' );
my @counter_rp_ger = ( 'CPU:usagemhz:MHz', 'Arbeitsspeicher:shared:KB', 'Arbeitsspeicher:zero:KB', 'Arbeitsspeicher:vmmemctl:KB', 'Arbeitsspeicher:consumed:KB', 'Arbeitsspeicher:overhead:KB', 'Arbeitsspeicher:active:KB', 'Arbeitsspeicher:granted:KB', 'Arbeitsspeicher:compressed:KB', 'Arbeitsspeicher:swapped:KB', 'Arbeitsspeicher:compressionRate:KB/s', 'Arbeitsspeicher:decompressionRate:KB/s' );
my @counter_rp_fr  = ( 'CPU:usagemhz:MHz', "$memfr:shared:Ko",          "$memfr:zero:Ko",          "$memfr:vmmemctl:Ko",          "$memfr:consumed:Ko",          "$memfr:overhead:Ko",          "$memfr:active:Ko",          "$memfr:granted:Ko",          "$memfr:compressed:Ko",          "$memfr:swapped:Ko",          "$memfr:compressionRate:Ko/s",          "$memfr:decompressionRate:Ko/s" );

#  datastore
my @counter_ds_eng  = ( 'Disk:used:KB',       'Disk:provisioned:KB',       'Disk:capacity:KB',       'Datastore:read:KBps',     'Datastore:write:KBps',     'Datastore:numberReadAveraged:Number',     'Datastore:numberWriteAveraged:Number' );
my @counter_ds_eng6 = ( 'Disk:used:KB',       'Disk:provisioned:KB',       'Disk:capacity:KB',       'Datastore:read:KBps',     'Datastore:write:KBps',     'Datastore:numberReadAveraged:num',        'Datastore:numberWriteAveraged:num' );
my @counter_ds_ger  = ( 'Festplatte:used:KB', 'Festplatte:provisioned:KB', 'Festplatte:capacity:KB', 'Datenspeicher:read:KB/s', 'Datenspeicher:write:KB/s', 'Datenspeicher:numberReadAveraged:Anzahl', 'Datenspeicher:numberWriteAveraged:Anzahl' );
my $banfr           = "Banque de donn" . "\xe9" . "es";
my @counter_ds_fr   = ( 'Disk:used:KB', 'Disk:provisioned:KB', 'Disk:capacity:KB', "$banfr:read:Ko/s", "$banfr:write:Ko/s", "$banfr:numberReadAveraged:Nombre", "$banfr:numberWriteAveraged:Nombre" );

my $lpm = $ENV{LPM};

#  my $h = $ENV{HOSTNAME};

my $cpu_max_filter = 100;    # my $cpu_max_filter = 100;  # max 10k peak in % is allowed (in fact it cannot be higher than 1k now when 1 logical CPU == 0.1 entitlement)
if ( defined $ENV{CPU_MAX_FILTER} ) {
  $cpu_max_filter = $ENV{CPU_MAX_FILTER};
}
my $load_daily = 0;          # do not load daily data from the HMC as default since 4.60
if ( defined $ENV{LOAD_DAILY} ) {
  $load_daily = $ENV{LOAD_DAILY};
}

my $delimiter = "XORUX";     # this is for rrdtool print lines for clickable legend

#print "++ $host $hmc_user $basedir $webdir $STEP\n";
my $wrkdir = "$basedir/data";

# if this file exists & contains UNIX time, graph CPU_ready from this time, otherwise not limited
my $CPU_ready_time_file = "$wrkdir/" . "$all_vmware_VMs/" . "CPU_ready_time.txt";

# Global definitions
my $loadhours               = "";
my $loadmins                = "";
my $loadsec_vm              = "";
my $type_sam                = "";
my $managedname             = "";
my $step                    = "";
my $NO_TIME_MULTIPLY        = 18;                           # increased since 4.x?
my $no_time                 = $STEP * $NO_TIME_MULTIPLY;    # says the time interval when RRDTOOL consideres a gap in input data 18 mins now!
                                                            # INIT_LOAD_IN_HOURS_BACK should be generally high enough  (one year back =~ 9000 hours), it is in hours!!!
                                                            #my $INIT_LOAD_IN_HOURS_BACK="9000";
my $INIT_LOAD_IN_HOURS_BACK = "18";                         # not need more as 1 minute samples are no longer there, daily are not more used since 4.60
                                                            #my $INIT_LOAD_IN_HOURS_BACK="1"; # for VMWARE

my $PARALLELIZATION = 10;

# $PARALLELIZATION = 2;
my $datastores_in_fork = 200;
my $clusters_in_fork   = 60;

# $clusters_in_fork   = 5;

#
### MAGIC CHANGE
#
if ( defined $ENV{VMWARE_PARALLEL_RUN} ) {
  $PARALLELIZATION = $ENV{VMWARE_PARALLEL_RUN};
}
if ( defined $ENV{DATASTORES_IN_FORK} ) {
  $datastores_in_fork = $ENV{DATASTORES_IN_FORK};
}
if ( defined $ENV{CLUSTERS_IN_FORK} ) {
  $clusters_in_fork = $ENV{CLUSTERS_IN_FORK};
}

print "\$wrkdir is     : $wrkdir\n";
print "Parallelization: ESXi:$PARALLELIZATION Cluster:$clusters_in_fork Datastore:$datastores_in_fork\n";

# problems with the same cluster name in more vcenters, it is used later in this script
#     if ( defined $ENV{VMWARE_SAME_CLUSTER_NAMES} ) {

# problems with the same cluster name in more datacenters in one vcenter, it is used later in this script
#     if ( defined $ENV{VMWARE_DATACENTERS_SAME_CLUSTER_NAMES} ) {

# Random colors for disk charts
my @managednamelist     = ();
my @managednamelist_vmw = ();
my $HMC                 = 1;     # if HMC then 1, if IVM/SDMC then 0
my $SDMC                = 0;
my $IVM                 = 0;
my @lpar_trans          = "";    # lpar translation names/ids for IVM systems

# last timestamp files --> must be for each load separated
my $last_file    = "last.txt";    # for ESXi server
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
my $timeout_save = 600;           # timeout for downloading whole server/lpar cfg from the HMC (per 1 server), it prevents hanging

# my $timeout=120; # timeout for vcenter operations

my %fork_handles = ();
my @returns;                      # filehandles for forking
my @returns_pipes = ();           # filehandles of forks reading & saving pipes from esxi forks

# temporary files with forks outputs in /home/lpar2rd/lpar2rrd/tmp/vcenter_host_name/file_x
my @returns_file_names       = ();
my $returns_file_names_count = 0;
my $read_pipes_pid_count;
my @read_pipes_pid;

my $server_count = 0;
my @pid          = "";
my $cycle_count  = 1;

my $DELETED_LPARS_TIME = 8640000;    # 10 days
my @lpm_excl_vio       = "";
my $run_topten         = 0;

# disable Tobi's promo
# my $disable_rrdtool_tag = "COMMENT: ";
# my $disable_rrdtool_tag_agg = "COMMENT:\" \"";
my $disable_rrdtool_tag     = "--interlaced";    # just nope string, it is deprecated anyway
my $disable_rrdtool_tag_agg = "--interlaced";    # just nope string, it is deprecated anyway

#my $rrd_ver                 = $RRDp::VERSION;
#if ( isdigit($rrd_ver) && $rrd_ver > 1.35 ) {
#  $disable_rrdtool_tag     = "--disable-rrdtool-tag";
#  $disable_rrdtool_tag_agg = "--disable-rrdtool-tag";
#}

# keep here green - yellow - red - blue ...
my @color     = ( "#FF0000", "#0000FF", "#8fcc66", "#00FFFF", "#FFA500", "#00FF00", "#808080", "#FF00FF", "#800080", "#FDD017", "#0000A0", "#3BB9FF", "#008000", "#800000", "#C0C0C0", "#ADD8E6", "#F778A1", "#800517", "#736F6E", "#F52887", "#C11B17", "#5CB3FF", "#A52A2A", "#FF8040", "#2B60DE", "#736AFF", "#1589FF", "#98AFC7", "#8D38C9", "#307D7E", "#F6358A", "#151B54", "#6D7B8D", "#33cc33", "#FF0080", "#F88017", "#2554C7", "#00a900", "#D4A017", "#306EFF", "#151B8D", "#9E7BFF", "#EAC117", "#99cc00", "#15317E", "#6C2DC7", "#FBB917", "#86b300", "#15317E", "#254117", "#FAAFBE", "#357EC7", "#4AA02C", "#38ACEC" );
my $color_max = 53;                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                     # 0 - 53 is 54 colors

my @keep_color_lpar = "";

#rrdtool_graphv();

my $prem = premium();
print "LPAR2RRD $prem version $version\n" if $DEBUG;
my $date     = "";
my $act_time = localtime();
print "Vmware    start: $host $act_time PID " . $$ . " ScriptSize $actprogsize\n" if $DEBUG;

if ( !-d "$webdir" ) {
  error( " Pls set correct path to Web server pages, it does not exist here: $webdir" . __FILE__ . ":" . __LINE__ ) && return 0;
}

# run touch tmp/menu_vmware.txt once a day to force recreation of the GUI
once_a_day("$basedir/tmp/menu_vmware.txt");

# start RRD via a pipe
#use RRDp;
#RRDp::start "$rrdtool";

#my $rrdtool_version = 'Unknown';
#$_ = `$rrdtool`;
#if ( /^RRDtool ([1-9]*\.[0-9]*(\.[0-9]*)?)/ ) {
#    $rrdtool_version = $1;
#}
#print "RRDp    version: $RRDp::VERSION \n";
#print "RRDtool version: $rrdtool_version\n";

print "Perl version   : $] \n";

# $host looks like atom from VMWARE_LIST="XoruX|vmware|lpar2rrd"
( $alias, $host, $username ) = split( /\|/, $host );
$host_orig = $host;
my $vcenter_last_update = "";

load_hmc();

my $line_count = scalar @all_vcenter_perf_data;
print "--------------------------------- line_count $line_count\n";

# prepare folder & file name for perf data output to files
my $tmp_output_file_name_dir = "$tmpdir/VMWARE";
if ( !-d $tmp_output_file_name_dir ) {
  print "mkdir          : $tmp_output_file_name_dir\n" if $DEBUG;
  mkdir( "$tmp_output_file_name_dir", 0755 ) || error( " Cannot mkdir $tmp_output_file_name_dir: $!" . __FILE__ . ":" . __LINE__ ) && exit;
}

my $tmp_output_file_name = "$tmpdir/VMWARE/" . time() . "_" . $host . ".tmp";
my $output_file_name     = "$tmpdir/VMWARE/" . time() . "_" . $host . ".txt";

# NG
if ($NG) {
  $output_file_name = "$tmpdir/VMWARE/" . time() . "_" . $host . ".txt.NG";
}
open( my $FHLT, ">", "$tmp_output_file_name" ) || error( " Can't open $tmp_output_file_name : $!" . __FILE__ . ":" . __LINE__ ) && exit;
print $FHLT $_ for (@all_vcenter_perf_data);
close($FHLT);
move( "$tmp_output_file_name", "$output_file_name" ) || error( " Cannot move $tmp_output_file_name to $output_file_name: $!" . __FILE__ . ":" . __LINE__ );

# close RRD pipe
#RRDp::end;

print "date end       : $host " . localtime() . "\n" if $DEBUG;

exit(0);

### ----------------------- exit main --------------------------

sub load_hmc {

  # prepare folder & file name for forks output to files
  #  $tmp_output_file_name_dir = "$tmpdir/$host_orig";
  #if (-d $tmp_output_file_name_dir) {
  #  rmdir( "$tmp_output_file_name_dir" ) || error( " Cannot rmdir $tmp_output_file_name_dir: $!" . __FILE__ . ":" . __LINE__ ) && exit;
  #}

  #  if (!-d $tmp_output_file_name_dir) {
  #    print "mkdir          : $host $tmp_output_file_name_dir\n" if $DEBUG;
  #    mkdir( "$tmp_output_file_name_dir", 0755 ) || error( " Cannot mkdir $tmp_output_file_name_dir: $!" . __FILE__ . ":" . __LINE__ ) && exit;
  #  }

  if ( !defined $username or $username eq "" ) {
    error( "vmw2rrd failed during connect: not defined username " . __FILE__ . ":" . __LINE__ );
    exit(1);
  }

  # return if $alias eq "<your alias>"; # testing purposes
  # return if $alias eq "cl_test"; # testing purposes

  eval {
    # 1st connect

    Opts::set_option( 'username', "$username" );
    $ENV{VI_SERVER} = "$host";

    Opts::parse();
    Opts::validate();
    Util::connect();
  };
  if ($@) {
    my $ret = $@;
    chomp($ret);
    error( "vmw2rrd failed during connect for username='$username', host='$host' : $ret " . __FILE__ . ":" . __LINE__ );
    exit(1);
  }

  $service_instance = Vim::get_service_instance();
  $vmware_uuid      = $service_instance->content->about->instanceUuid;

  if ( defined($VMware::VIRuntime::VERSION) ) {
    print "SDK            : $alias($vmware_uuid), vSphere SDK for Perl version-a: $VMware::VIRuntime::VERSION\n";
  }
  else {
    if ( defined($Util::version) ) {
      print "SDK            : $alias($vmware_uuid), vSphere SDK for Perl version-b: $Util::version\n";
    }
    else {
      print "SDK            : $alias($vmware_uuid), vSphere SDK for Perl NO VERSION\n";
    }
  }

=for comment usernames can be of variable syntax, does sometimes weird errors

  my $auth_mgr = Vim::get_view(mo_ref => Vim::get_service_content()->authorizationManager);
  #print Dumper ($auth_mgr);
  my %role_hash;
  my $role_list = $auth_mgr->roleList;
  # print Dumper ($role_list);
  # Get all roles and put them in a hash so we can easily get the name corresponding to a roleId
  foreach (@$role_list) {
    $role_hash{$_->roleId} = $_->name;
  }
  my ($short_username, undef) = split ("@",$username);
  $short_username = lc($short_username);

  # for each type of managed entity run one object of that type
  # and test permissions of used user
  # print result
  my @obj_types = ('HostSystem', 'VirtualMachine', 'Datacenter', 'Folder', 'ComputeResource', 'ResourcePool');
  foreach my $this_type (@obj_types){
    my $obj_views = Vim::find_entity_view(view_type => $this_type);
      my $obj_name = $obj_views->name;
      my $perm_array = $auth_mgr->RetrieveEntityPermissions(entity => $obj_views, inherited => 1);
      my $perm_detected = 0;
      foreach(@$perm_array) {
        $perm_detected = 1 if lc($_->principal) =~ /$short_username$/;
      }
      if ($perm_detected) {
        print "permission     : $alias: user $short_username has access to $this_type ($obj_name)\n";
      }
      else {
        print "permission     : $alias: user $short_username has NOT access to $this_type ($obj_name)\n";
      }
  }
=cut

  # locale for english
  my $serviceContent = Vim::get_service_content();
  my $sessionManager = Vim::get_view( mo_ref => $serviceContent->sessionManager );

  # print Dumper ($sessionManager);
  $sessionManager->SetLocale( locale => "en" );

  #      $sessionManager->SetLocale(locale => "de");
  #       $sessionManager->SetLocale(locale => "de_DE");
  #      $sessionManager->SetLocale(locale => "es"); # tohle nejspis nemame

  Opts::assert_usage( defined($sessionManager), "No sessionManager." );

  # get system time

  $command_date = $service_instance->CurrentTime();
  chomp($command_date);
  my $command_utc = str2time($command_date);
  $command_unix = int($command_utc);

  # print "system UTC     : $command_date : $command_unix\n";

  # fetch apiType (vcenter or hostSystem)
  $apiType_top         = $service_instance->content->about->apiType;
  $fullName_top        = $service_instance->content->about->fullName;
  $vcenter_last_update = $service_instance->serverClock;
  print "system UTC updt: $alias, $apiType_top $fullName_top UTC:$command_date : $command_unix Vcenter last update:$vcenter_last_update\n";

  # print "serverClock    : $last_update";

  # get vCenter database config
  if ( $apiType_top =~ "VirtualCenter" ) {

    # my $opt_manager = Vim::get_view( mo_ref => $serviceContent->setting);
    my $opt_manager = Vim::get_view( mo_ref => Vim::get_service_content()->setting );

    #my $opt_manager = $serviceContent->setting);
    # print Dumper($opt_manager);
    my @setting = $opt_manager->setting;

    # print Dumper (@setting);
    my $point         = $setting[0];
    my $info_to_print = "";
    foreach my $item (@$point) {

      # print Dumper ($item) ; no interest in "event.maxAge" "event.maxAgeEnabled" "task.maxAge" "task.maxAgeEnabled"
      if ( $item->key eq "Perf.Stats.MaxCollectionThreads" || $item->key eq "VirtualCenter.MaxDBConnection" || $item->key eq "config.vpxd.stats.maxQueryMetrics" || $item->key eq "config.vpxd.stats.MaxQueryMetrics" ) {
        $info_to_print .= $item->key . ":" . $item->value . "  ";
      }
      if ( $item->key eq "instance.id" ) {
        $vmware_id = $item->value;

        # print "vmware instance.id $vmware_id\n";
      }
    }
    if ( $info_to_print eq "" ) {
      print "vC DB config   : $alias, not found - probably limited permission user !! try go on\n";

      # print Dumper (@setting);
      # exit;
    }
    if ( $info_to_print !~ "vpxd" ) {
      $info_to_print .= "config.vpxd.stats.maxQueryMetrics: not detected";
    }
    print "vC DB config   : $alias, $info_to_print\n";
  }

  # since version 5.08 "instance.id" is appended to vCenter UUID to differ cloned vCenter
  # it is up to lpar2rrd user to set up instance.id to be different
  # see 'Conflicting vCenter Server Unique IDs'
  #
  if ( $vmware_id ne "" ) {
    my $existing_dir = "$wrkdir/vmware_$vmware_uuid";
    $vmware_uuid .= "_" . $vmware_id;
    if ( -d "$existing_dir" ) {

      # existing must be renamed
      my $new_dir = "$wrkdir/vmware_$vmware_uuid";
      print "renaming vmware vcenter dir $existing_dir to $new_dir\n";
      rename $existing_dir, $new_dir or error("vmware : cannot rename $existing_dir to $new_dir");
    }
  }

  # fetch all HostSystems limiting the property set
  $managednamelist_un = Vim::find_entity_views(
    view_type  => "HostSystem",
    properties => [ 'name', 'parent', 'hardware.systemInfo.uuid', 'systemResources.config.cpuAllocation.reservation' ]
  );
  if ( !defined $managednamelist_un || $managednamelist_un eq '' ) {
    error("vmware name: $host either has not been resolved or ssh key based access is not allowed or other communication error");
    exit(1);
  }
  if ( !defined @$managednamelist_un[0] ) {
    error("vmware name: $host has not array of hosts ?!?");
    print Dumper($managednamelist_un);
    exit(1);
  }

  if ( @$managednamelist_un[0] =~ "no address associated with hostname" || @$managednamelist_un[0] =~ "Could not resolve hostname" ) {
    error("vmware : @$managednamelist_un[0]");
    exit(1);
  }

  # if use of global once find_entity_views of resourcepools for the whole vcenter
  # you should work then with 'owner'
  #  'owner' => bless( {
  #                    'value' => 'domain-c8',
  #                    'type' => 'ClusterComputeResource'
  #                    }, 'ManagedObjectReference' ),
  # because owner can differ from parent & owner is actual manager of resource pool
  # eval {
  #   $resourcepool_list = Vim::find_entity_views(
  #   view_type    => "ResourcePool",
  #   properties   => [ 'name', 'vm', 'config', 'parent', 'owner' ]
  #   );
  # };
  # print Dumper ("743",\$resourcepool_list);

  my $perfmgr_view = Vim::get_view( mo_ref => Vim::get_service_content()->perfManager );

  # print Dumper($perfmgr_view);

  if ( $apiType_top =~ "VirtualCenter" ) {
    my @historical_intervals = $perfmgr_view->historicalInterval;

    if ( defined $historical_intervals[0] ) {

      # print Dumper(@historical_intervals);
      $historical_level0 = $historical_intervals[0][0]->level;
      my $hist_int_name    = $historical_intervals[0][0]->name;
      my $hist_int_enabled = $historical_intervals[0][0]->enabled;
      print "hist_interval0 : $alias, $historical_level0 for '$hist_int_name' for VI_SERVER $host enabled:$hist_int_enabled\n";
      if ( $hist_int_name ne "Past day" && $hist_int_name ne "Past Day" && $hist_int_name ne "Letzter Tag" && $hist_int_name !~ "Jour pr" && $hist_int_name !~ "ltimo d" ) {
        error("no 'Past day/Letzter Tag/Jour précédent' but lowest historical interval name: ,$hist_int_name, ");    # trouble with Jour précédent
      }
    }
    else {
      print "hist intervals : $alias, not defined\n";
    }
  }
  else {
    print "hist intervals : $alias, not defined cus not VirtualCenter\n";
  }
  my $host_number = scalar(@$managednamelist_un);
  if ( $host_number > 109 ) {
    $PARALLELIZATION = int( $host_number / 10 );
  }
  print "Hosts number   : $alias $host_number \$PARALLELIZATION $PARALLELIZATION\n";

  print "get all VMs    : $alias, start at " . localtime() . "\n";
  eval {
    $vcenter_vm_views = Vim::find_entity_views(
      view_type  => 'VirtualMachine',
      properties => [ 'name', 'parent', 'config.instanceUuid', 'summary.config.instanceUuid', 'summary.config.guestFullName', 'summary.storage.committed', 'summary.storage.uncommitted', 'summary.config.numCpu', 'summary.config.memorySizeMB', 'runtime.powerState', 'config.cpuAllocation.reservation', 'config.cpuAllocation.shares.shares', 'config.cpuAllocation.shares.level', 'config.cpuAllocation.limit', 'guest.toolsRunningStatus', 'guest.ipAddress', 'summary.config.uuid', 'storage', 'summary.guest.guestFullName', 'config.hardware' ]
    );
  };
  print "get all VMs    : $alias, done at " . localtime() . "\n";

  # create pointers to individual VMs (those are items in array)
  for (@$vcenter_vm_views) {
    my $vm_moref = $_->{'mo_ref'}->value;
    my $vm_uuid  = $_->{'summary.config.instanceUuid'};

    # print "803 \$vm_moref $vm_moref \$vm_uuid $vm_uuid\n";
    $vcenter_vm_views_hash{$vm_moref} = $_;
    $vcenter_vm_views_hash{$vm_uuid}  = $_->{name};

    # print "805 ".$vcenter_vm_views_hash{$vm_uuid}."\n";

    # get RDM VirtualDiskRawDiskMappingVer1BackingInfo
    my $each_vm_config_hardware = $vcenter_vm_views_hash{$vm_moref}->{'config.hardware'};

    # print Dumper("3592",$each_vm_config_hardware);

    my $each_vm_config_hardware_device = $each_vm_config_hardware->{'device'};

    # print Dumper("3594",$each_vm_config_hardware_device);
    my $lunUuid_count = 0;
    my @new_arr       = ();
    foreach my $device (@$each_vm_config_hardware_device) {

      # print Dumper("3596",$device);
      if ( exists $device->{'backing'} ) {
        my $device_backing = $device->{'backing'};

        # print Dumper("3596",$device_backing);
        if ( exists $device_backing->{'lunUuid'} ) {
          $lunUuid_count++;
          push @new_arr, $device;
        }
      }
    }
    if ( $lunUuid_count == 0 ) {

      # remove hash to save memory
      #print "834 delete hash for $vm_moref\n";
      delete $vcenter_vm_views_hash{$vm_moref}{'config.hardware'};
    }
    else {    # remove other devices except those containing lunUuid
      $vcenter_vm_views_hash{$vm_moref}{'config.hardware'}{device} = \@new_arr;
    }
  }

  #print Dumper ("806",$vcenter_vm_views);
  #print Dumper ("807",\%vcenter_vm_views_hash);

  # delete $vcenter_vm_views-> whole hash to save operational memory
  $vcenter_vm_views = "";

  hostsystem_perf();    # all Hosts and all Virtual Machines

  # print "659 vmw2rrd.pl %vm_hash\n";

  # return; # when debugging

  # get datacenter list for later use
  if ( $fullName_top =~ 'vCenter Server 5' || $fullName_top =~ 'vCenter Server 6' || $fullName_top =~ 'vCenter Server 7' || $fullName_top =~ 'vCenter Server 8' || $apiType_top =~ 'HostAgent' ) {
    $datacenter_list = Vim::find_entity_views( view_type => "Datacenter", properties => [ 'name', 'vmFolder', 'datastoreFolder' ] );
    if ( !defined $datacenter_list || ( $datacenter_list eq "" ) ) {
      error( "Undefined datacenter_list in vmware $host: " . __FILE__ . ":" . __LINE__ ) && exit(1);
    }
  }

  # fetch datacenters only for VC version higher than 4
  # print "702 \$apiType_top ,$apiType_top, \$fullName_top ,$fullName_top,\n";

  if ( $apiType_top =~ 'xxxHostAgent' ) {

    #print Dumper ($datacenter_list);
    foreach $datacenter (@$datacenter_list) {

      # print Dumper($datacenter);

      # fetch datastores
      $datastore_list = Vim::find_entity_views( view_type => "Datastore", properties => [ 'name', 'summary', 'vm', 'info' ], begin_entity => $datacenter );
      if ( !defined $datastore_list || ( $datastore_list eq "" ) ) {
        error( "Undefined datastore_list in vmware $host:datacenter $datacenter: " . __FILE__ . ":" . __LINE__ ) && next;
      }
      print Dumper($datastore_list);

      # $datastore_list = $datastore_list->datastore; # this is the difference from vCenter
      if ( !defined $datastore_list || ( $datastore_list eq "" ) ) {
        error( "Undefined datastore_list in vmware $host:datacenter $datacenter: " . __FILE__ . ":" . __LINE__ ) && next;
      }
      my $datacenter_moref = $datacenter->{'mo_ref'}->value;

      # my $denter_moref = $dcl->{'mo_ref'}->value;
      print "\$datacenter_moref $datacenter_moref\n";

      # my $dlist = $dcl->datastore;
      # print Dumper($dlist);
      foreach my $datastore (@$datastore_list) {
        my $ds_name = $datastore->name;
        print "----------- \$ds_name $ds_name \$managedname $managedname\n";
      }
    }
  }

  if ( $fullName_top =~ 'vCenter Server 5' || $fullName_top =~ 'vCenter Server 6' || $fullName_top =~ 'vCenter Server 7' || $fullName_top =~ 'vCenter Server 8' || $apiType_top =~ 'HostAgent' ) {

    if ( $apiType_top =~ "VirtualCenter" ) {
      $managedname = "vmware_$vmware_uuid";
    }
    else {    # for non vcenter should be already set up
              # $managedname = "";
    }

    # until 4.81-004 datacenter dir had own user name, but came problem with Marne-La-Vallée
    # since then datacenter dir name = mo_ref and inside is touched file <datacenter name>.dcname

    foreach $datacenter (@$datacenter_list) {

      # print Dumper($datacenter);

      # fetch datastores
      $datastore_list = Vim::find_entity_views( view_type => "Datastore", properties => [ 'name', 'summary', 'vm', 'host', 'info', 'parent' ], begin_entity => $datacenter );
      if ( !@$datastore_list ) {
        error( "Undefined datastore_list in vmware $host: datacenter " . $datacenter->name . __FILE__ . ":" . __LINE__ ) && next;
      }

      my $datacenter_moref = $datacenter->{'mo_ref'}->value;
      $h_name = "datastore_" . $datacenter->name;    # cus contains only datastores

      # new solution
      my $datacenter_name = $h_name;
      my $moref_name      = "datastore_" . $datacenter_moref;
      if ( -d "$wrkdir/$managedname/$h_name" ) {

        # existing must be renamed
        move( "$wrkdir/$managedname/$h_name", "$wrkdir/$managedname/$moref_name" ) || error( " Cannot move $wrkdir/$managedname/$h_name to $moref_name: $!" . __FILE__ . ":" . __LINE__ ) && next;
      }
      $h_name = $moref_name;

      print "retrieving perf: datacenter $datacenter_name mo_ref $h_name for $managedname at " . localtime(time) . "\n";

      #  if ($apiType_top =~ 'HostAgent') {
      #      foreach my $datastore (@$datastore_list) {
      #        my $ds_name        = $datastore->name;
      #        print "----------- \$ds_name $ds_name\n";
      #      }
      #      next;
      #  }
      # prepare dir datacenter

      if ( !-d "$wrkdir/$managedname/$h_name" ) {

        # in case there is no cluster create also $managedname dir
        if ( !-d "$wrkdir/$managedname" ) {
          print "mkdir          : $h_name:$managedname $wrkdir/$managedname\n" if $DEBUG;
          LoadDataModuleVMWare::touch("$wrkdir/$managedname");
          mkdir( "$wrkdir/$managedname", 0755 ) || error( " Cannot mkdir $wrkdir/$managedname: $!" . __FILE__ . ":" . __LINE__ ) && next;

          # vcenter must know its alias
          my $my_alias_file_name = "$wrkdir/$managedname/vmware_alias_name";
          open my $FH, ">$my_alias_file_name" or error( "can't open $my_alias_file_name: $!" . __FILE__ . ":" . __LINE__ );
          print $FH "$h_name|$alias\n";    # save cluster name and alias, ! when there are more clusters, you store the last $h_name
          close $FH;
        }
        print "mkdir          : $h_name:$managedname $wrkdir/$managedname/$h_name\n" if $DEBUG;
        LoadDataModuleVMWare::touch("$wrkdir/$managedname/$h_name");
        mkdir( "$wrkdir/$managedname/$h_name", 0755 ) || error( " Cannot mkdir $wrkdir/$managedname/$h_name: $!" . __FILE__ . ":" . __LINE__ ) && next;
      }
      if ( $apiType_top !~ 'HostAgent' ) {
        if ( !-f "$wrkdir/$managedname/$h_name/vcenter" ) {
          `touch "$wrkdir/$managedname/$h_name/vcenter"`;    # say install_html.sh that it is vcenter
          LoadDataModuleVMWare::touch("$wrkdir/$managedname/$h_name/vcenter");
        }
      }
      if ( $apiType_top !~ 'HostAgent' ) {
        my @files = bsd_glob("$wrkdir/$managedname/$h_name/vcenter_name_*");
        if ( !defined $files[0] || scalar @files > 1 || $files[0] ne "$wrkdir/$managedname/$h_name/vcenter_name_$host" ) {
          `rm -f "$wrkdir/$managedname/$h_name"/vcenter_name_*`;        # in case there are more names
          `touch "$wrkdir/$managedname/$h_name/vcenter_name_$host"`;    # say install_html.sh that it is vcenter name
          LoadDataModuleVMWare::touch("$wrkdir/$managedname/$h_name/vcenter_name_$host");
        }
      }

      # new solution after 4.81-004
      # touch user datacenter name
      my $datacenter_name_file = "$datacenter_name.dcname";
      if ( !-f "$wrkdir/$managedname/$h_name/$datacenter_name_file" ) {
        `rm -f "$wrkdir/$managedname/$h_name"/*.dcname`;                 # in case there are more names
        `touch "$wrkdir/$managedname/$h_name/$datacenter_name_file"`;    # save user datacenter name
        LoadDataModuleVMWare::touch("$wrkdir/$managedname/$h_name/$datacenter_name_file");
      }
      `touch "$wrkdir/$managedname/$h_name/$datacenter_name_file"`;      # touch every load, not touched 30 days ? -> not taken to menu.txt

      #
      ### datastore folder solution
      #
      my $global_dsfolder = $datacenter->datastoreFolder;

      # print Dumper ($global_dsfolder);
      my $global_dsfolder_moref = $global_dsfolder->value;

      # print "822 \$global_datacenter_name $global_datacenter_name \$global_dsfolder_moref $global_dsfolder_moref \n";
      # 822 $global_datacenter_name Datacenter 2 $global_dsfolder_moref group-s5

      my $group_list;
      eval {
        $group_list = Vim::find_entity_views(
          view_type    => "Folder",
          properties   => [ 'name', 'parent' ],
          begin_entity => $global_dsfolder
        );
      };
      if ($@) {
        error( "vmw2rrd failed: $@ " . __FILE__ . ":" . __LINE__ );

        # exit(1);
      }

      # properties => [ 'name', 'parent', 'childEntity' ], # we do not need childEntity here
      if ( !defined $group_list || ( $group_list eq "" ) ) {
        error( "Undefined DS group_list in vmware $host: " . __FILE__ . ":" . __LINE__ );    # && exit(1);
      }
      else {
        # print Dumper ("836",$group_list);
        %ds_group_path = ();

        foreach my $group (@$group_list) {
          my $parent = $group->parent->value;
          my $moref  = $group->{'mo_ref'}->value;
          my $name   = $group->name;

          if ( $moref ne $global_dsfolder_moref ) {
            $ds_group_path{$moref} = "$parent,$name";
          }
        }

        # print Dumper ("848",\%ds_group_path);
        #$VAR1 = {
        #'group-s326' => 'group-s237,SAN dev pro',
        #'group-s236' => 'group-s5,3PAR',
        #'group-s237' => 'group-s5,Compellent'
        #};
        # time to save DS pathes
        my $file_to_save = "$wrkdir/$managedname/$h_name/ds_folder_path.json";

        # print "923 $file_to_save\n";
        if ( !Xorux_lib::write_json( $file_to_save, \%ds_group_path ) ) {
          error( "Cannot save $file_to_save: " . __FILE__ . ":" . __LINE__ );
        }
      }

      $host = $h_name;

      init_perf_counter_info($et_VirtualMachine);    # get counter IDS
                                                     # print Dumper (@$all_counters); # this for some reason blocked next line and made finish of script
      datastore_perf();
      $host = $host_orig;
    }
  }
  else {
    error( "Not known \$fullName_top $fullName_top in vmware $host: " . __FILE__ . ":" . __LINE__ ) && exit(1);
  }

  # fetch clusters if exist (only for vcenter)
  if ( $apiType_top =~ "VirtualCenter" ) {
    foreach $datacenter (@$datacenter_list) {
      $global_datacenter_name = $datacenter->name;

      my $global_vmfolder = $datacenter->vmFolder;

      # print Dumper ($global_vmfolder);
      my $global_vmfolder_moref = $global_vmfolder->value;

      # print "630 \$global_datacenter_name $global_datacenter_name \$global_vmfolder_moref $global_vmfolder_moref \n";
      # 630 $global_datacenter_name Datacenter 2 $global_vmfolder_moref group-v3

      my $group_list;
      eval {
        $group_list = Vim::find_entity_views(
          view_type    => "Folder",
          properties   => [ 'name', 'parent' ],
          begin_entity => $global_vmfolder
        );
      };
      if ($@) {
        error( "vmw2rrd failed: $@ " . __FILE__ . ":" . __LINE__ );

        # exit(1);
      }

      # properties => [ 'name', 'parent', 'childEntity' ], # we do not need childEntity here
      if ( !defined $group_list || ( $group_list eq "" ) ) {
        error( "Undefined VM group_list in vmware $host: " . __FILE__ . ":" . __LINE__ );    # && exit(1);
      }
      else {
        # print Dumper $group_list;
        %vm_group_path = ();

        foreach my $group (@$group_list) {
          my $parent = $group->parent->value;
          my $moref  = $group->{'mo_ref'}->value;
          my $name   = $group->name;

          if ( $moref ne $global_vmfolder_moref ) {
            $vm_group_path{$moref} = "$parent,$name";
          }
        }

        # print Dumper (\%vm_group_path);
        #$VAR1 = {
        #    'group-v281' => 'group-v3,AD',
        #    'group-v132' => 'group-v3,NetApp',
        #    'group-v133' => 'group-v3,Development',
        #    'group-v327' => 'group-v133,Devel Jesk',
        #    'group-v9' => 'group-v3,Discovered virtual machine'
        #  };
        # it is saved in every cluster, used in find_active_lpar
      }

      eval {
        # get cluster info
        $cluster_list = Vim::find_entity_views(
          view_type    => "ClusterComputeResource",
          properties   => [ 'name', 'summary', 'host', 'resourcePool' ],
          begin_entity => $datacenter
        );
      };
      if ($@) {
        error( "vmw2rrd failed: $@ " . __FILE__ . ":" . __LINE__ );

        # exit(1);
      }
      if ( !defined $cluster_list || ( $cluster_list eq "" ) ) {
        error( "Undefined cluster in vmware $host datacenter $global_datacenter_name: " . __FILE__ . ":" . __LINE__ ) && next;
      }

      cluster_perf();
    }
  }

  return;    # from load_hmc
}

#### ----- #########

sub cluster_perf {
  return if ( ( !defined $cluster_list ) || ( $cluster_list eq "" ) );

  $do_fork = "0";

  # my $Resources_once = 0; # only once print in menu.txt for Unregistered VMs
  my $Resources_once = 1;    # since 4.95-7 do not care about Resources

  # $host_orig keeps vmware connect name
  # my $host_orig = $host; # necessary to know for host in cluster

  my $cluster_number = scalar @$cluster_list;
  return if ( $cluster_number < 0 );

  print "Clusters #     : $host $global_datacenter_name $cluster_number start " . localtime() . "\n";

  if ( $cluster_number <= $clusters_in_fork ) {    # no fork
    my $index_from = 0;
    my $index_to   = $cluster_number - 1;

    cluster_perf_engine( $cluster_list, $index_from, $index_to );

    # finish all clusters
    # if there file im_in_cluster left, must reload menu
    #my $file_pth = "$wrkdir/*/$h_name/im_in_cluster"; # path to find files
    #$file_pth =~ s/ /\\ /g;
    #my $no_name = "";
    #my @files = (<$file_pth$no_name>); # unsorted, workaround for space in names
    my @files = bsd_glob("$wrkdir/*/$h_name/im_in_cluster");
    if ( @files > 0 ) {
      LoadDataModuleVMWare::touch("$wrkdir/$managedname/$h_name/im_in_cluster");
    }

    create_vcenter_config_file();

    $host = $host_orig;
    print "Clusters #     : $host $global_datacenter_name $cluster_number finish " . localtime() . "\n";
    return;
  }

  # cycle of forks
  my $index_from = 0;
  my $index_to   = $clusters_in_fork - 1;

  while ( $cluster_number > 0 ) {

    local *FH;
    $pid[$server_count] = open( FH, "-|" );

    # $pid[$server_count] = fork();
    if ( not defined $pid[$server_count] ) {
      error("$host:$managedname clusters could not fork");
    }
    elsif ( $pid[$server_count] == 0 ) {
      print "Fork CLSTR     : $host:$managedname : $server_count child pid $$\n" if $DEBUG;

      #my $i_am_fork = "fork";
      $i_am_fork = "fork";

      #      RRDp::end;
      #      RRDp::start "$rrdtool";

      eval { Util::connect(); };
      if ($@) {
        my $ret = $@;
        chomp($ret);
        error( "vmw2rrd failed: $ret " . __FILE__ . ":" . __LINE__ );

        #        RRDp::end;
        exit(1);
      }

      # locale for english
      my $serviceContent = Vim::get_service_content();
      my $sessionManager = Vim::get_view( mo_ref => $serviceContent->sessionManager );
      $sessionManager->SetLocale( locale => "en" );

      #        $sessionManager->SetLocale(locale => "de");

      Opts::assert_usage( defined($sessionManager), "No sessionManager." );

      $service_instance = Vim::get_service_instance();
      cluster_perf_engine( $cluster_list, $index_from, $index_to );

      #      RRDp::end;
      eval { Util::disconnect(); };
      if ($@) {
        my $ret = $@;
        chomp($ret);
        error( "vmw2rrd failed: $ret " . __FILE__ . ":" . __LINE__ );
      }

      print "Fork CLSTR exit: $host:$managedname : $server_count\n" if $DEBUG;
      exit(0);
    }
    $cluster_number = $cluster_number - $clusters_in_fork;
    $index_from     = $index_to + 1;
    $index_to       = $index_from + $clusters_in_fork - 1;
    if ( $cluster_number < $clusters_in_fork ) {
      $index_to = $index_from + $cluster_number - 1;
    }
    print "Parent continue: CLSTR $host:$managedname $pid[$server_count ] parent pid $$ from $index_from to $index_to\n";
    $server_count++;

    push @returns, *FH;

    $cycle_count++;
  }

  # this operation should clear all finished forks 'defunct'
  print_fork_dstr_output();

  create_vcenter_config_file();

  $host = $host_orig;
  print "Clusters #     : $host $global_datacenter_name $cluster_number finish " . localtime() . "\n";
}

sub create_vcenter_config_file {

  # save html clusters table for later use or in detail_cgi.pl

  my $pth = "$wrkdir/vmware_*/esxis_config.html";
  $pth =~ s/ /\\ /g;
  my $no_name                  = "";
  my @vcenter_config_files_new = grep { (-M) < 1 } (<$pth$no_name>);    # unsorted, workaround for space in names, younger than 1 day
                                                                        # print "1148 \@vcenter_config_files_new @vcenter_config_files_new\n";

  my @vcenter_config_html = ();
  my @vcenters_configs    = ();
  my $first               = 1;
  foreach (@vcenter_config_files_new) {
    if ( open( my $FH, "< $_" ) ) {
      if ($first) {    # take the whole file incl. headings
        push @vcenters_configs, <$FH>;
        pop @vcenters_configs;    #remove last line which closes the html table </TABLE></CENTER><BR><BR>
        close $FH;
        $first = 0;
      }
      else {                      # omit headings
        my $tbody = 1;
        foreach (<$FH>) {

          # print "1165 $_\n";
          if ( $tbody && ( index( $_, "<tbody>" ) == -1 ) ) {
            next;
          }
          else {
            $tbody = 0;
            push @vcenters_configs, $_;
          }
        }
        pop @vcenters_configs;    #remove last line which closes the html table </TABLE></CENTER><BR><BR>
        close $FH;
      }
    }
    else {
      error( "Cannot open file $_: $!" . __FILE__ . ":" . __LINE__ );
    }
  }

  push @vcenters_configs, "</TABLE></CENTER>";    # add end of html table

  my $vcenter_config_html_file = "$tmpdir/vcenters_clusters_config.html";

  # print "1186 \@vcenters_configs @vcenters_configs\n";
  if ( open my $FH_vc_conf, ">$vcenter_config_html_file" ) {
    print $FH_vc_conf @vcenters_configs;          # print html data
    close $FH_vc_conf;
  }
  else {
    error( "can't open $vcenter_config_html_file: $!" . __FILE__ . ":" . __LINE__ );
  }
}

sub cluster_perf_engine {
  my $cluster_list = shift;
  my $index_from   = shift;
  my $index_to     = shift;

  foreach my $cluster ( @$cluster_list[ $index_from .. $index_to ] ) {

    my $cluster_moref      = $cluster->{'mo_ref'}->value;
    my $cluster_moref_name = "cluster_" . $cluster_moref;
    $cluster_effectiveMemory = 0;
    $cluster_effectiveCpu    = 0;
    eval {
      $cluster_effectiveMemory = $cluster->summary->effectiveMemory if defined $cluster->summary->effectiveMemory;
      $cluster_effectiveCpu    = $cluster->summary->effectiveCpu    if defined $cluster->summary->effectiveCpu;
    };
    if ( $cluster_effectiveMemory eq 0 or $cluster_effectiveCpu eq 0 ) {
      error_noerr( "Undefined \$cluster_effectiveMemory $cluster_effectiveMemory or \$cluster_effectiveCpu $cluster_effectiveCpu in cluster $cluster_moref_name: " . __FILE__ . ":" . __LINE__ );
    }

    $h_name = "cluster_" . $cluster->name;

    # problems with the same cluster name in more vcenters
    if ( defined $ENV{VMWARE_SAME_CLUSTER_NAMES} ) {
      $h_name = "cluster_" . $cluster->name . "-" . $alias;
    }
    elsif ( defined $ENV{VMWARE_DATACENTERS_SAME_CLUSTER_NAMES} ) {
      if ( $global_datacenter_name ne "" ) {
        $h_name = "cluster_" . $global_datacenter_name . "-" . $cluster->name;
      }
    }

    $fail_entity_name = $h_name;
    $fail_entity_type = "cluster";

    $managedname = "vmware_$vmware_uuid";

    # $host = $h_name ;  # new host as a second dir name under data/

    # since >4.81-004 to enable renaming of clusters
    $host = $cluster_moref_name;
    print "retrieving perf: cluster $h_name mo_ref $cluster_moref for $managedname\n";

    if ( !-d "$wrkdir" ) {
      print "mkdir          : $host:$managedname $wrkdir\n" if $DEBUG;
      LoadDataModuleVMWare::touch("$host:$managedname $wrkdir");
      mkdir( "$wrkdir", 0755 ) || error( " Cannot mkdir $wrkdir: $!" . __FILE__ . ":" . __LINE__ ) && next;
    }

    if ( !-d "$wrkdir/$managedname" ) {
      print "mkdir          : $host:$managedname $wrkdir/$managedname\n" if $DEBUG;
      LoadDataModuleVMWare::touch("$wrkdir/$managedname");
      mkdir( "$wrkdir/$managedname", 0755 ) || error( " Cannot mkdir $wrkdir/$managedname: $!" . __FILE__ . ":" . __LINE__ ) && next;
    }

    # vcenter must know its alias, alias can be changed anytime
    my $my_alias_file_name = "$wrkdir/$managedname/vmware_alias_name";
    open my $FH_alias, ">$my_alias_file_name" or error( "can't open $my_alias_file_name: $!" . __FILE__ . ":" . __LINE__ );
    print $FH_alias "$h_name|$alias\n";    # save cluster name and alias, ! when there are more clusters, you store the last $h_name
    close $FH_alias;

    if ( !-d "$wrkdir/$managedname/$host" && -d "$wrkdir/$managedname/$h_name" ) {    # rename from name to moref (new system)
      print "rename  cluster: $wrkdir/$managedname/$h_name to $wrkdir/$managedname/$host\n";
      move( "$wrkdir/$managedname/$h_name", "$wrkdir/$managedname/$host" ) || error( " Cannot move $wrkdir/$managedname/$h_name to $cluster_moref: $!" . __FILE__ . ":" . __LINE__ ) && next;
    }
    if ( !-d "$wrkdir/$managedname/$host" ) {                                         # new cluster
      print "mkdir          : $host:$managedname $wrkdir/$managedname/$host\n" if $DEBUG;
      LoadDataModuleVMWare::touch("$wrkdir/$managedname/$host");
      mkdir( "$wrkdir/$managedname/$host", 0755 ) || error( " Cannot mkdir $wrkdir/$managedname/$host: $!" . __FILE__ . ":" . __LINE__ ) && next;

      if ( !-f "$wrkdir/$managedname/$host/vcenter" ) {
        `touch "$wrkdir/$managedname/$host/vcenter"`;    # say install_html.sh that it is vcenter
      }
    }
    if ( !-f "$wrkdir/$managedname/$host/vcenter" ) {
      `touch "$wrkdir/$managedname/$host/vcenter"`;      # say install_html.sh that it is vcenter
    }
    my @files_vname = bsd_glob("$wrkdir/$managedname/$h_name/vcenter_name_*");
    if ( !defined $files_vname[0] || scalar @files_vname > 1 || $files_vname[0] ne "$wrkdir/$managedname/$host/vcenter_name_$host_orig" ) {
      `rm -f "$wrkdir/$managedname/$host"/vcenter_name_*`;             # in case there are more names
      `touch "$wrkdir/$managedname/$host/vcenter_name_$host_orig"`;    # say install_html.sh vcenter name
    }
    if ( !-f "$wrkdir/$managedname/$host/cluster_name_$h_name" ) {
      `rm -f "$wrkdir/$managedname/$host"/cluster_name_*`;             # in case there are more names
      `touch "$wrkdir/$managedname/$host/cluster_name_$h_name"`;       # say install_html.sh cluster name
    }
    my $vmware_signal_file = "$wrkdir/$managedname/$host/vmware.txt";
    if ( !-f "$vmware_signal_file" ) {
      `touch "$vmware_signal_file"`;                                   # say install_html.sh that it is vmware
    }

    # time to save VM pathes (to all clusters)
    my $file_to_save = "$wrkdir/$managedname/$host/vm_folder_path.json";

    # print "923 $file_to_save\n";
    if ( !Xorux_lib::write_json( $file_to_save, \%vm_group_path ) ) {
      error( "Cannot save $file_to_save: " . __FILE__ . ":" . __LINE__ );
    }

    # construct cluster counters from VM counters
    # example of data line of VM metrics, data rank is according to $vm_metrics .= "$one_update,... see script, 0th item is timestamp
    # 500f3775-9b2d-f0e3-8f36-6799f3e70d79 1485355840,0,1258,3292376040,817888,2097152,0,13,0,13,323,315,8,0,0,0,0,1911,2,454,2085132,U 1485355860,0,867,
    #  VM-uuid,                            timestamp,data                                                                               timestamp,data

    # for the case there are more clusters, use cluster_active_VMs

    my $entity_type = $et_ClusterComputeResource;

    # reconstruction timestamps from 1st data line

    my @vm_time_stamps = ();

    # my @arrt = split( " ", $vm_counter_data[0] );
    # print "1005 \$first_vm_counter_data $first_vm_counter_data\n";

    my @arrt = split( " ", $first_vm_counter_data );
    for ( my $i = 1; $i <= $#arrt; $i++ ) {
      $vm_time_stamps[ $i - 1 ] = ( split( ",", $arrt[$i] ) )[0];    # timestamp
    }
    $samples_number = ( scalar @arrt ) - 1;

    # print "1011 vmw2rrd.pl @vm_time_stamps\n";
    # @vm_time_stamps = (); # when enabling historical data retrieving
    my $samples_number_spare = $samples_number + 10;

    @cl_CPU_usage_Proc          = ('U') x $samples_number_spare;
    @cl_CPU_usage_MHz           = ('U') x $samples_number_spare;
    @cl_CPU_reserved_MHz        = ('U') x $samples_number_spare;
    @cl_Memory_usage_Proc       = ('U') x $samples_number_spare;
    @cl_Memory_reserved_MB      = ('U') x $samples_number_spare;
    @cl_Memory_granted_KB       = ('U') x $samples_number_spare;
    @cl_Memory_active_KB        = ('U') x $samples_number_spare;
    @cl_Memory_shared_KB        = ('U') x $samples_number_spare;
    @cl_Memory_zero_KB          = ('U') x $samples_number_spare;
    @cl_Memory_swap_KB          = ('U') x $samples_number_spare;
    @cl_Memory_baloon_KB        = ('U') x $samples_number_spare;
    @cl_Memory_consumed_KB      = ('U') x $samples_number_spare;
    @cl_Memory_overhead_KB      = ('U') x $samples_number_spare;
    @cl_Memory_compressed_KB    = ('U') x $samples_number_spare;
    @cl_Memory_compression_KBps = ('U') x $samples_number_spare;
    @cl_Memory_decompress_KBps  = ('U') x $samples_number_spare;
    @cl_Power_usage_Watt        = ('U') x $samples_number_spare;
    @cl_Power_cup_Watt          = ('U') x $samples_number_spare;
    @cl_Cluster_eff_CPU_MHz     = ('U') x $samples_number_spare;
    @cl_Cluster_eff_memory_MB   = ('U') x $samples_number_spare;
    @cl_CPU_total_MHz           = ($cluster_effectiveCpu) x $samples_number;
    @cl_Memory_total_MB         = ($cluster_effectiveMemory) x $samples_number;

    # print "943 vmw2rrd.pl %vm_hash\n";
    # print "926 @vm_time_stamps \n";

    my @active_VMs = ();
    cluster_active_VMs( $wrkdir, "$managedname/$host", \@active_VMs );    # for test for VMs in this cluster

    # my %vm_hash = ();
    # print Dumper(%vm_hash);
    # my $ind     = 0;
    # while ( $ind <= $#vm_counter_data ) left_curly
    while (@active_VMs) {
      my $act_vm  = shift @active_VMs;
      my $vm_uuid = basename($act_vm);
      $vm_uuid =~ s/\.rrm$//;

      # print "1049 vmw2rrd.pl \$act_vm $act_vm \$vm_uuid $vm_uuid\n";
      my @arrt = "";
      if ( exists $vm_hash{$vm_uuid} ) {
        @arrt = split( " ", $vm_hash{$vm_uuid} );
      }
      else {
        # error( "active vm $act_vm has no data " . __FILE__ . ":" . __LINE__ ); # no interest
        next;
      }

      # my @arrt = split( " ", $vm_counter_data[$ind] );

      # my @choice = grep {/$arrt[0]/} @active_VMs;
      # if ( !( defined $choice[0] && $choice[0] ne "" ) ) {                # VM is not in this cluster
      #   $ind++;
      #   next;
      # }

      # cus the last sample from ESXi servers ( means VMs) can differ e.g.
      # 1485501780,2000,876,3292376040,2097152,8382464,0,64,0,64,5,4,0,0,0,0,0,1331,2,276,8313168,U
      # 1485501760,0,294,2400084926,335544,2095104,0,11,0,11,10188,126,10061,0,0,0,0,614,2,119,2093868,U
      # above example differs in 20 secs
      $samples_number = ( scalar @arrt ) - 1 if ( ( scalar @arrt ) - 1 ) < $samples_number;

      # print "1075 \$samples_number $samples_number\n";
      # prepare vm_hash for resource pools metric
      # $vm_hash{ $arrt[0] } = $vm_counter_data[$ind];

      for ( my $i = 1; $i <= $#arrt; $i++ ) {

        # print "1423 \$arrt[$i] $arrt[$i]\n";
        my $i_1 = $i - 1;
        ( undef, undef, my $xval, undef, my $xval4, my $xval5, my $xval6, undef, undef, undef, undef, undef, undef, my $xval13, my $xval14, undef, undef, undef, undef, undef, my $xval20 ) = split( ",", $arrt[$i] );    # utilization GHz is 2
        if ( $xval ne "U" && $xval > 0 ) {
          if ( !defined $cl_CPU_usage_MHz[$i_1] ) {
            my $scalar_arrt = scalar @arrt;
            print "985 vmw2rrd.pl \$samples_number $samples_number \$scalar_arrt $scalar_arrt\n";
          }
          if ( $cl_CPU_usage_MHz[$i_1] eq 'U' ) {
            $cl_CPU_usage_MHz[$i_1] = $xval;
          }
          else {
            $cl_CPU_usage_MHz[$i_1] += $xval;
          }
        }

        # $xval = ( split( ",", $arrt[$i] ) )[4];    # mem active
        if ( $xval4 ne "U" && $xval4 > 0 ) {
          if ( $cl_Memory_active_KB[$i_1] eq 'U' ) {
            $cl_Memory_active_KB[$i_1] = $xval4;
          }
          else {
            $cl_Memory_active_KB[$i_1] += $xval4;
          }
        }

        # $xval = ( split( ",", $arrt[$i] ) )[5];    # mem granted
        if ( $xval5 ne "U" && $xval5 > 0 ) {
          if ( $cl_Memory_granted_KB[$i_1] eq 'U' ) {
            $cl_Memory_granted_KB[$i_1] = $xval5;
          }
          else {
            $cl_Memory_granted_KB[$i_1] += $xval5;
          }
        }

        # $xval = ( split( ",", $arrt[$i] ) )[6];    # mem baloon
        if ( $xval6 ne "U" && $xval6 >= 0 ) {
          if ( $cl_Memory_baloon_KB[$i_1] eq 'U' ) {
            $cl_Memory_baloon_KB[$i_1] = $xval6;
          }
          else {
            $cl_Memory_baloon_KB[$i_1] += $xval6;
          }
        }

        # $xval = ( split( ",", $arrt[$i] ) )[13];    # mem swap - both in one item
        if ( $xval13 ne "U" && $xval13 >= 0 ) {
          if ( $cl_Memory_swap_KB[$i_1] eq 'U' ) {
            $cl_Memory_swap_KB[$i_1] = $xval13;
          }
          else {
            $cl_Memory_swap_KB[$i_1] += $xval13;
          }
        }

        # $xval = ( split( ",", $arrt[$i] ) )[14];    # mem swap
        if ( $xval14 ne "U" && $xval14 >= 0 ) {
          if ( $cl_Memory_swap_KB[$i_1] eq 'U' ) {
            $cl_Memory_swap_KB[$i_1] = $xval14;
          }
          else {
            $cl_Memory_swap_KB[$i_1] += $xval14;
          }
        }

        # $xval = ( split( ",", $arrt[$i] ) )[20];    # mem consumed
        if ( $xval20 ne "U" && $xval20 > 0 ) {
          if ( $cl_Memory_consumed_KB[$i_1] eq 'U' ) {
            $cl_Memory_consumed_KB[$i_1] = $xval20;
          }
          else {
            $cl_Memory_consumed_KB[$i_1] += $xval20;
          }
        }
      }

      # $ind++;
    }

    if ( defined $vm_time_stamps[0] ) {    # real data

      my $update_string = "";
      my $one_update;
      my $mil = "1000000";
      my $kb  = "1024";
      my $mb  = 1024 * 1024;

      for ( my $i = 0; $i < $samples_number; $i++ ) {
        $update_string .= "$vm_time_stamps[$i],";
        if ($NG) {

          #$one_update = "$cl_CPU_usage_MHz[$i],$cl_CPU_usage_Proc[$i],$cl_CPU_reserved_MHz[$i],";
          $one_update = "$cl_CPU_usage_MHz[$i],$cl_CPU_usage_Proc[$i],";
          $one_update .= ( ( $cl_CPU_reserved_MHz[$i] ne "U" ) ? $cl_CPU_reserved_MHz[$i] / $mil : $cl_CPU_reserved_MHz[$i] ) . ",";

          #$one_update    .= "$cl_CPU_total_MHz[$i],$cl_Cluster_eff_CPU_MHz[$i],$cl_Cluster_eff_memory_MB[$i],";
          $one_update .= ( ( $cl_CPU_total_MHz[$i] ne "U" )         ? $cl_CPU_total_MHz[$i] / $mil        : $cl_CPU_total_MHz[$i] ) . ",";
          $one_update .= ( ( $cl_Cluster_eff_CPU_MHz[$i] ne "U" )   ? $cl_Cluster_eff_CPU_MHz[$i] / $mil  : $cl_Cluster_eff_CPU_MHz[$i] ) . ",";
          $one_update .= ( ( $cl_Cluster_eff_memory_MB[$i] ne "U" ) ? $cl_Cluster_eff_memory_MB[$i] * $mb : $cl_Cluster_eff_memory_MB[$i] ) . ",";

          #$one_update    .= "$cl_Memory_total_MB[$i],$cl_Memory_shared_KB[$i],$cl_Memory_zero_KB[$i],";
          $one_update .= ( ( $cl_Memory_total_MB[$i] ne "U" )  ? $cl_Memory_total_MB[$i] * $mb  : $cl_Memory_total_MB[$i] ) . ",";
          $one_update .= ( ( $cl_Memory_shared_KB[$i] ne "U" ) ? $cl_Memory_shared_KB[$i] * $kb : $cl_Memory_shared_KB[$i] ) . ",";
          $one_update .= ( ( $cl_Memory_zero_KB[$i] ne "U" )   ? $cl_Memory_zero_KB[$i] * $kb   : $cl_Memory_zero_KB[$i] ) . ",";

          #$one_update    .= "$cl_Memory_baloon_KB[$i],$cl_Memory_consumed_KB[$i],$cl_Memory_overhead_KB[$i],";
          $one_update .= "$cl_Memory_baloon_KB[$i],$cl_Memory_consumed_KB[$i],";
          $one_update .= ( ( $cl_Memory_overhead_KB[$i] ne "U" ) ? $cl_Memory_overhead_KB[$i] * $kb : $cl_Memory_overhead_KB[$i] ) . ",";

          #$one_update    .= "$cl_Memory_active_KB[$i],$cl_Memory_granted_KB[$i],$cl_Memory_compressed_KB[$i],";
          $one_update .= "$cl_Memory_active_KB[$i],$cl_Memory_granted_KB[$i],";
          $one_update .= ( ( $cl_Memory_compressed_KB[$i] ne "U" ) ? $cl_Memory_compressed_KB[$i] * $kb : $cl_Memory_compressed_KB[$i] ) . ",";

          #$one_update    .= "$cl_Memory_reserved_MB[$i],$cl_Memory_swap_KB[$i],$cl_Memory_compression_KBps[$i],";
          $one_update .= ( ( $cl_Memory_reserved_MB[$i] ne "U" ) ? $cl_Memory_reserved_MB[$i] * $mb : $cl_Memory_reserved_MB[$i] ) . ",";
          $one_update .= "$cl_Memory_swap_KB[$i],";
          $one_update .= ( ( $cl_Memory_compression_KBps[$i] ne "U" ) ? $cl_Memory_compression_KBps[$i] * $kb : $cl_Memory_compression_KBps[$i] ) . ",";

          #$one_update    .= "$cl_Memory_decompress_KBps[$i],$cl_Memory_usage_Proc[$i],";
          $one_update    .= ( ( $cl_Memory_decompress_KBps[$i] ne "U" ) ? $cl_Memory_decompress_KBps[$i] * $kb : $cl_Memory_decompress_KBps[$i] ) . ",";
          $one_update    .= "$cl_Memory_usage_Proc[$i],$cl_Power_cup_Watt[$i],$cl_Power_usage_Watt[$i] ";
          $update_string .= "$one_update";
        }
        else {
          $one_update = "$cl_CPU_usage_MHz[$i],$cl_CPU_usage_Proc[$i],$cl_CPU_reserved_MHz[$i],";
          $one_update    .= "$cl_CPU_total_MHz[$i],$cl_Cluster_eff_CPU_MHz[$i],$cl_Cluster_eff_memory_MB[$i],";
          $one_update    .= "$cl_Memory_total_MB[$i],$cl_Memory_shared_KB[$i],$cl_Memory_zero_KB[$i],";
          $one_update    .= "$cl_Memory_baloon_KB[$i],$cl_Memory_consumed_KB[$i],$cl_Memory_overhead_KB[$i],";
          $one_update    .= "$cl_Memory_active_KB[$i],$cl_Memory_granted_KB[$i],$cl_Memory_compressed_KB[$i],";
          $one_update    .= "$cl_Memory_reserved_MB[$i],$cl_Memory_swap_KB[$i],$cl_Memory_compression_KBps[$i],";
          $one_update    .= "$cl_Memory_decompress_KBps[$i],$cl_Memory_usage_Proc[$i],";
          $one_update    .= "$cl_Power_cup_Watt[$i],$cl_Power_usage_Watt[$i] ";
          $update_string .= "$one_update";
        }
      }

      # print "string for RRD file update is:\n$update_string,xorux_sentinel\n";
      # print "---------------------------------------------------\n\n";

      my $input_vm_uuid = 'cluster';
      my $type_sam      = "c";
      $last_file = "last.txt";

      $SSH = "";

      my $managedname_save = $managedname;
      my $host_save        = $host;

      #      my $res_update = LoadDataModuleVMWare::load_data( $managedname_save, $host_save, $wrkdir, \$update_string, $type_sam, $act_time, $HMC, $IVM, $SDMC, $step, $DEBUG, \@lpar_trans, $last_file, $no_time, $SSH, $hmc_user, $input_vm_uuid, $entity_type, "(".$$."F$server_count)" );
      if ( $i_am_fork eq "fork" ) {
        print "update_line,$managedname_save,$host_save,$wrkdir,\$update_string,$type_sam,$act_time,$HMC,$IVM,$SDMC,$step,$DEBUG,\@lpar_trans,$last_file,$no_time,$SSH,$hmc_user,$input_vm_uuid,$entity_type,(" . $$ . "F$server_count),$update_string,xorux_sentinel\n";
      }
      else {
        push @all_vcenter_perf_data, "update_line,$managedname_save,$host_save,$wrkdir,\$update_string,$type_sam,$act_time,$HMC,$IVM,$SDMC,$step,$DEBUG,\@lpar_trans,$last_file,$no_time,$SSH,$hmc_user,$input_vm_uuid,$entity_type,(" . $$ . "F$server_count),$update_string,xorux_sentinel\n";
      }

    }
    else {    # or historical data
      prepare_last_time( $cluster, $et_ClusterComputeResource );
    }

    # print "# prepare list of Hosts in this cluster\n";

    my $cluster_hosts = $cluster->host;
    my $host_morefs   = "";

    # print Dumper ($cluster_hosts);
    foreach my $host_c (@$cluster_hosts) {

      #print Dumper ($host_c);
      my $host_value = $host_c->value;
      $host_morefs = $host_morefs . " $host_value" . "host";

      #print "1046 \$host_value $host_value\n";
    }

    my @manag_list       = ();
    my $hosts_in_cluster = $managednamelist_un;

    #    eval {
    #      $hosts_in_cluster = Vim::find_entity_views(
    #        view_type  => "HostSystem",
    #        properties => [ 'name', 'parent' ]
    #      );
    #    };
    #    if ($@) {
    #      my $ret = $@;
    #      chomp($ret);
    #      error( "vmware asking hosts_in_cluster failed: $ret " . __FILE__ . ":" . __LINE__ );
    #    }

    # print Dumper($hosts_in_cluster);

    # print "# prepare for frame_multi & multiview_hmc\n";
    my $number_of_hosts = 0;
    foreach my $host_c (@$hosts_in_cluster) {
      my $host_name  = $host_c->get_property('name');
      my $host_moref = $host_c->{'mo_ref'}->value;

      # print "1066 \$host_morefs $host_morefs \$host_moref $host_moref\n";
      if ( index( $host_morefs, "$host_moref" . "host" ) == -1 ) {
        next;
      }

      #my $items_path = "$host_name" . "XORUX" . "$host_orig";    # original $host
      push @manag_list, "$host_name" . "XORUX" . "$host_orig";
      $number_of_hosts++;

      # server must know its cluster and alias
      my $my_cluster_file_name = "$wrkdir/$host_name/$host_orig/my_cluster_name";
      my $cluster_name         = "";
      if ( -f $my_cluster_file_name ) {
        open my $FH, "$my_cluster_file_name" or error( "can't open $my_cluster_file_name: $!" . __FILE__ . ":" . __LINE__ ) && next;
        $cluster_name = <$FH>;
        chomp $cluster_name;
        close $FH;
      }
      if ( $cluster_name eq "" || $cluster_name ne "$h_name|$alias" ) {
        open my $FH, ">$my_cluster_file_name" or error( "can't open $my_cluster_file_name: $!" . __FILE__ . ":" . __LINE__ ) && next;

        # print FH "$host|$alias\n"; # save host name and alias
        print $FH "$h_name|$alias\n";    # save host name and alias
        close $FH;
        LoadDataModuleVMWare::touch("$my_cluster_file_name");
      }
      unlink "$wrkdir/$host_name/$host_orig/im_in_cluster";    # this esxi is in cluster
    }

    # print "hosts in cluster $cluster_moref\n";
    # print Dumper(@manag_list);
    # for event debug > save it

    my $hosts_in_cluster_file = "$wrkdir/$managedname/$host/hosts_in_cluster";
    open my $FH_cls, ">$hosts_in_cluster_file" or error( "can't open $hosts_in_cluster_file: $!" . __FILE__ . ":" . __LINE__ ) && next;
    foreach my $new_line (@manag_list) {
      chomp($new_line);
      print $FH_cls $new_line . "\n";
    }
    close $FH_cls;
    print "writing hosts  : $number_of_hosts in $hosts_in_cluster_file\n";

    @managednamelist_vmw = @manag_list;
    make_cmd_frame_multiview( $managedname, $host, $et_ClusterComputeResource );

    #
    ###  resourcepools
    #

    eval {
      $resourcepool_list = Vim::find_entity_views(
        view_type    => "ResourcePool",
        properties   => [ 'name', 'vm', 'config', 'parent' ],
        begin_entity => $cluster
      );

      #       properties => ['name','vm','config.cpuAllocation.reservation','config.memoryAllocation.reservation',
      #                                  'config.cpuAllocation.limit','config.memoryAllocation.limit' ],begin_entity=>$cluster);
    };
    if ($@) {
      my $ret = $@;
      chomp($ret);
      error( "vmware asking ResourcePool failed: $ret " . __FILE__ . ":" . __LINE__ );
    }

    if ( !defined $resourcepool_list || ( $resourcepool_list eq "" ) ) {
      error( "Undefined resourcepool list in vmware $host:cluster $cluster " . __FILE__ . ":" . __LINE__ ) && next;
    }
    $managedname = "vmware_$vmware_uuid";

    $do_fork = "0";
    my @all_paths      = ();
    my $all_paths_file = "$wrkdir/$managedname/$host/active_rp_paths.txt";

    # print Dumper (%vm_id_path);

    my $cluster_rpfolder       = $cluster->resourcePool;
    my $cluster_rpfolder_moref = $cluster_rpfolder->value;

    # print Dumper ("1216 \$cluster_rpfolder \$cluster_rpfolder_moref", $cluster_rpfolder,$cluster_rpfolder_moref);
    my $rp_path_file_to_save = "$wrkdir/$managedname/$host/rp_folder_path.json";
    my %rp_group_path        = ();
    my @rp_setting           = ();

    foreach my $resourcepool (@$resourcepool_list) {
      $rp_name   = $resourcepool->name;
      $rp_parent = $resourcepool->parent->value;

      # resourcepool does not have uuid  --  !!!!!! ???? !!!!!
      $rp_moref = $resourcepool->{'mo_ref'}->value;

      # print "starting retrieving rp $rp_name $rp_moref ---------------------\n";
      if ( !defined $rp_name || ( $rp_name eq "" ) ) {
        error( "not defined or empty name of resourcepool in cluster $h_name  " . __FILE__ . ":" . __LINE__ ) && next;
      }

      if ( $rp_moref ne $cluster_rpfolder_moref ) {    # && $rp_parent ne $cluster_rpfolder_moref
        $rp_group_path{$rp_moref} = "$rp_parent,$rp_name";
      }

      # print Dumper (\%vm_group_path);

      #if ( ( $rp_name eq "Resources" ) && ($Resources_once) ) {next}
      #;    # can be only once
      #$Resources_once++ if ( $rp_name eq "Resources" );
      if ( $rp_name eq "Resources" ) {next}

      $rp_cpu_reservation = 0;
      $rp_cpu_limit       = 0;
      $rp_cpu_alloc_type  = 0;
      $rp_cpu_shares      = 0;
      $rp_cpu_value       = 0;

      $rp_mem_reservation = 0;
      $rp_mem_limit       = 0;
      $rp_mem_alloc_type  = 0;
      $rp_mem_shares      = 0;
      $rp_mem_value       = 0;

      eval {
        $rp_cpu_reservation = $resourcepool->config->cpuAllocation->reservation           if defined $resourcepool->config->cpuAllocation->reservation;
        $rp_cpu_limit       = $resourcepool->config->cpuAllocation->limit                 if defined $resourcepool->config->cpuAllocation->limit;
        $rp_cpu_alloc_type  = $resourcepool->config->cpuAllocation->expandableReservation if defined $resourcepool->config->cpuAllocation->expandableReservation;
        $rp_cpu_shares      = $resourcepool->config->cpuAllocation->shares->level->val    if defined $resourcepool->config->cpuAllocation->shares->level->val;
        $rp_cpu_value       = $resourcepool->config->cpuAllocation->shares->shares        if defined $resourcepool->config->cpuAllocation->shares->shares;

        $rp_mem_reservation = $resourcepool->config->memoryAllocation->reservation           if defined $resourcepool->config->memoryAllocation->reservation;
        $rp_mem_limit       = $resourcepool->config->memoryAllocation->limit                 if defined $resourcepool->config->memoryAllocation->limit;
        $rp_mem_alloc_type  = $resourcepool->config->memoryAllocation->expandableReservation if defined $resourcepool->config->memoryAllocation->expandableReservation;
        $rp_mem_shares      = $resourcepool->config->memoryAllocation->shares->level->val    if defined $resourcepool->config->memoryAllocation->shares->level->val;
        $rp_mem_value       = $resourcepool->config->memoryAllocation->shares->shares        if defined $resourcepool->config->memoryAllocation->shares->shares;
      };
      if ($@) {
        my $ret = $@;
        chomp($ret);
        error( "vmware asking ResourcePool $rp_name $rp_moref failed: $ret " . __FILE__ . ":" . __LINE__ );
        print Dumper($resourcepool);

        # next;
      }

      # print "1231 ::::::::::::::: cpu_res $rp_cpu_reservation mem_res $rp_mem_reservation cpu_lim $rp_cpu_limit mem_lim $rp_mem_limit\n";
      $rp_cpu_reservation = 0 if $rp_cpu_reservation == -1;
      $rp_mem_reservation = 0 if $rp_mem_reservation == -1;
      $rp_cpu_limit       = 0 if $rp_cpu_limit == -1;
      $rp_mem_limit       = 0 if $rp_mem_limit == -1;

      $rp_cpu_alloc_type = "Expandable" if $rp_cpu_alloc_type eq 1;
      $rp_mem_alloc_type = "Expandable" if $rp_mem_alloc_type eq 1;

      push @rp_setting, "$rp_name,$rp_cpu_reservation,$rp_cpu_limit,$rp_cpu_alloc_type,$rp_cpu_shares,$rp_cpu_value,$rp_mem_reservation,$rp_mem_limit,$rp_mem_alloc_type,$rp_mem_shares,$rp_mem_value";

      $fail_entity_name = $rp_name;
      $fail_entity_type = "resourcepool";

      @rp_vm_morefs = ();
      my @rp_vm_morefs_old = ();

      $managedname = "vmware_$vmware_uuid";

      my $rp_vm_morefs_file = "$wrkdir/$managedname/$host/rp__vmid__$rp_moref.txt";

      # since > 4.81-004
      if ( -f "$wrkdir/$managedname/$host/rp__vmid__$rp_name.txt" ) {    # old name
        print "rename respool : $wrkdir/$managedname/$host/rp__vmid__$rp_name.txt to $rp_vm_morefs_file\n";
        move( "$wrkdir/$managedname/$host/rp__vmid__$rp_name.txt", "$rp_vm_morefs_file" ) || error( " Cannot move rp__vmid__$rp_name.txt to $rp_vm_morefs_file: $!" . __FILE__ . ":" . __LINE__ ) && next;
      }

      # print "looking for file $rp_vm_morefs_file\n";
      if ( -f "$rp_vm_morefs_file" ) {
        open my $FH, "$rp_vm_morefs_file" or error( "can't open $rp_vm_morefs_file: $!" . __FILE__ . ":" . __LINE__ ) && next;
        @rp_vm_morefs_old = <$FH>;
        close $FH;
      }

      # new system of tracking VM presence in hostsystem
      # for every hostsystem ( resourcepool too)
      # - open VM hosting file
      # - track every VM - active and also non-active
      # - save Vm hosting file
      # during cycle hold hosting info in an array

      my @hosting_arr = ();

      # since > 4.81-004
      my $vmr_file = "$wrkdir/$managedname/$host/$rp_moref.vmr";
      if ( -f "$wrkdir/$managedname/$host/$rp_name.vmr" ) {    # old name
        print "rename respool : $wrkdir/$managedname/$host/$rp_name.vmr to $vmr_file\n";
        move( "$wrkdir/$managedname/$host/$rp_name.vmr", "$vmr_file" ) || error( " Cannot move $rp_name.vmr to $vmr_file: $!" . __FILE__ . ":" . __LINE__ ) && next;
      }
      VM_hosting_read( \@hosting_arr, "$vmr_file" );

      my $vm                     = $resourcepool->vm;
      my @respool_active_vm_uuid = ();                         # keep it for metrics construction

      foreach my $vmsp (@$vm) {
        my $vm_mo_ref_id = $vmsp->value;

        # print "VM value $vm_mo_ref_id";
        if ( ( defined $vm_mo_ref_id ) && ( $vm_mo_ref_id ne "" ) ) {

          # get VM_name
          my $vm_uuid = $vm_id_path{"$vm_mo_ref_id"};    # is already prepared
          if ( !defined $vm_uuid ) {
            error( "vm_id_path does not exist for vm mo_ref $vm_mo_ref_id or is PoweredOff $fail_entity_type $fail_entity_name " . __FILE__ . ":" . __LINE__ ) && next;
          }
          $vm_uuid = basename($vm_uuid);
          $vm_uuid =~ s/\.rrm$//;
          if ( !uuid_check($vm_uuid) ) {
            error( "cannot find uuid for mo_ref $vm_mo_ref_id " . __FILE__ . ":" . __LINE__ ) && next;
          }
          push @respool_active_vm_uuid, $vm_uuid;        # keep it for metrics construction

          push @rp_vm_morefs, $vm_mo_ref_id . "\n";
          VM_hosting_update( \@hosting_arr, $vm_uuid, $command_unix );

          #  print "\@hosting_arr @hosting_arr\n";
        }
        else {
          error( "not defined vm moref in $fail_entity_type $fail_entity_name in cluster $h_name  " . __FILE__ . ":" . __LINE__ ) && next;
        }
      }

      VM_hosting_write( \@hosting_arr, "$vmr_file", $command_unix );

      # print "@rp_vm_morefs\n";
      push @all_paths, $rp_vm_morefs_file;

      open my $FH_moref, ">$rp_vm_morefs_file" or error( "can't open $rp_vm_morefs_file: $!" . __FILE__ . ":" . __LINE__ ) && next;
      foreach my $new_line (@rp_vm_morefs) {
        chomp($new_line);
        print $FH_moref $new_line . "\n";
      }
      close $FH_moref;

      # print "writing respool: $rp_name $rp_vm_morefs_file\n";
      print "writing respool: $rp_name \$wrkdir/$managedname/$host/rp__vmid__$rp_moref.txt\n";

      # get perf
      # existing must be renamed
      my $rp_path = "$wrkdir/$managedname/$h_name";
      if ( -f "$rp_path/$rp_name.rrc" ) {
        print "rename respool : $rp_path/$rp_name.rrc to $rp_path/$rp_moref.rrc\n";
        move( "$rp_path/$rp_name.rrc", "$rp_path/$rp_moref.rrc" ) || error( " Cannot move $rp_path/$rp_name.rrc to $rp_path/$rp_moref.rrc: $!" . __FILE__ . ":" . __LINE__ ) && next;

        if ( -f "$rp_path/$rp_name.last" ) {
          print "rename respool : $rp_path/$rp_name.last to $rp_path/$rp_moref.last\n";
          move( "$rp_path/$rp_name.last", "$rp_path/$rp_moref.last" ) || error( " Cannot move $rp_path/$rp_name.last to $rp_path/$rp_moref.last: $!" . __FILE__ . ":" . __LINE__ ) && next;
        }
      }

      # construct resource pool counters from VM counters
      # example of data line of VM metrics, data rank is according to $vm_metrics .= "$one_update,... see script, 0th item is timestamp
      # 500f3775-9b2d-f0e3-8f36-6799f3e70d79 1485355840,0,1258,3292376040,817888,2097152,0,13,0,13,323,315,8,0,0,0,0,1911,2,454,2085132,U 1485355860,0,867,
      #  VM-uuid,                            timestamp,data                                                                               timestamp,data

      my $entity_type = $et_ResourcePool;

      # reconstruction timestamps from 1st data line

      my @vm_time_stamps = ();

      # my @arrt = split( " ", $vm_counter_data[0] );
      my @arrt = split( " ", $first_vm_counter_data );
      for ( my $i = 1; $i <= $#arrt; $i++ ) {
        $vm_time_stamps[ $i - 1 ] = ( split( ",", $arrt[$i] ) )[0];    # timestamp
      }
      $samples_number = ( scalar @arrt ) - 1;

      # print "1472 vmw2rrd.pl \@vm_time_stamps @vm_time_stamps\n";

      # @vm_time_stamps = (); # when enabling historical data retrieving

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

      # count metrics for respool active VMs
      foreach my $uuid (@respool_active_vm_uuid) {
        chomp $uuid;

        # print "1496 \$uuid $uuid\n";
        next if !exists $vm_hash{$uuid};

        # print "1499 vmw2rrd.pl $vm_hash{$uuid}\n";
        my @arrt = split( " ", $vm_hash{$uuid} );

        # cus the last sample from ESXi servers ( means VMs) can differ e.g.
        # 1485501780,2000,876,3292376040,2097152,8382464,0,64,0,64,5,4,0,0,0,0,0,1331,2,276,8313168,U
        # 1485501760,0,294,2400084926,335544,2095104,0,11,0,11,10188,126,10061,0,0,0,0,614,2,119,2093868,U
        # above example differs in 20 secs
        $samples_number = ( scalar @arrt ) - 1 if ( ( scalar @arrt ) - 1 ) < $samples_number;

        for ( my $i = 1; $i <= $#arrt; $i++ ) {

          # print "1509 \$arrt[$i] $arrt[$i]\n";
          my $xval = ( split( ",", $arrt[$i] ) )[2];    # utilization GHz
          if ( $xval ne "U" && $xval > 0 ) {
            if ( !defined $cl_CPU_usage_MHz[ $i - 1 ] || $cl_CPU_usage_MHz[ $i - 1 ] eq 'U' ) {
              $cl_CPU_usage_MHz[ $i - 1 ] = $xval;
            }
            else {
              $cl_CPU_usage_MHz[ $i - 1 ] += $xval;
            }
          }
          $xval = ( split( ",", $arrt[$i] ) )[4];       # mem active
          if ( $xval ne "U" && $xval > 0 ) {
            if ( !defined $cl_Memory_active_KB[ $i - 1 ] || $cl_Memory_active_KB[ $i - 1 ] eq 'U' ) {
              $cl_Memory_active_KB[ $i - 1 ] = $xval;
            }
            else {
              $cl_Memory_active_KB[ $i - 1 ] += $xval;
            }
          }
          $xval = ( split( ",", $arrt[$i] ) )[5];       # mem granted
          if ( $xval ne "U" && $xval > 0 ) {
            if ( !defined $cl_Memory_granted_KB[ $i - 1 ] || $cl_Memory_granted_KB[ $i - 1 ] eq 'U' ) {
              $cl_Memory_granted_KB[ $i - 1 ] = $xval;
            }
            else {
              $cl_Memory_granted_KB[ $i - 1 ] += $xval;
            }
          }
          $xval = ( split( ",", $arrt[$i] ) )[6];       # mem baloon
          if ( $xval ne "U" && $xval >= 0 ) {
            if ( !defined $cl_Memory_baloon_KB[ $i - 1 ] || $cl_Memory_baloon_KB[ $i - 1 ] eq 'U' ) {
              $cl_Memory_baloon_KB[ $i - 1 ] = $xval;
            }
            else {
              $cl_Memory_baloon_KB[ $i - 1 ] += $xval;
            }
          }
          $xval = ( split( ",", $arrt[$i] ) )[13];      # mem swap - both in one item
          if ( $xval ne "U" && $xval >= 0 ) {
            if ( !defined $cl_Memory_swap_KB[ $i - 1 ] || $cl_Memory_swap_KB[ $i - 1 ] eq 'U' ) {
              $cl_Memory_swap_KB[ $i - 1 ] = $xval;
            }
            else {
              $cl_Memory_swap_KB[ $i - 1 ] += $xval;
            }
          }
          $xval = ( split( ",", $arrt[$i] ) )[14];      # mem swap
          if ( $xval ne "U" && $xval >= 0 ) {
            if ( !defined $cl_Memory_swap_KB[ $i - 1 ] || $cl_Memory_swap_KB[ $i - 1 ] eq 'U' ) {
              $cl_Memory_swap_KB[ $i - 1 ] = $xval;
            }
            else {
              $cl_Memory_swap_KB[ $i - 1 ] += $xval;
            }
          }
          $xval = ( split( ",", $arrt[$i] ) )[20];      # mem consumed
          if ( $xval ne "U" && $xval > 0 ) {
            if ( !defined $cl_Memory_consumed_KB[ $i - 1 ] || $cl_Memory_consumed_KB[ $i - 1 ] eq 'U' ) {
              $cl_Memory_consumed_KB[ $i - 1 ] = $xval;
            }
            else {
              $cl_Memory_consumed_KB[ $i - 1 ] += $xval;
            }
          }
        }
      }

      if ( defined $vm_time_stamps[0] ) {    # real data

        my $update_string = "";
        my $one_update;
        my $kb = "1024";

        for ( my $i = 0; $i < $samples_number; $i++ ) {
          $update_string .= "$vm_time_stamps[$i],";
          if ($NG) {
            $one_update = "$cl_CPU_usage_MHz[$i],";

            # $one_update    .= "$cl_Memory_shared_KB[$i],$cl_Memory_zero_KB[$i],";
            $one_update .= ( ( $cl_Memory_shared_KB[$i] ne "U" ) ? $cl_Memory_shared_KB[$i] * $kb : $cl_Memory_shared_KB[$i] ) . ",";
            $one_update .= ( ( $cl_Memory_zero_KB[$i] ne "U" )   ? $cl_Memory_zero_KB[$i] * $kb   : $cl_Memory_zero_KB[$i] ) . ",";

            # $one_update    .= "$cl_Memory_baloon_KB[$i],$cl_Memory_consumed_KB[$i],$cl_Memory_overhead_KB[$i],";
            $one_update .= "$cl_Memory_baloon_KB[$i],$cl_Memory_consumed_KB[$i],";
            $one_update .= ( ( $cl_Memory_overhead_KB[$i] ne "U" ) ? $cl_Memory_overhead_KB[$i] * $kb : $cl_Memory_overhead_KB[$i] ) . ",";

            # $one_update    .= "$cl_Memory_active_KB[$i],$cl_Memory_granted_KB[$i],$cl_Memory_compressed_KB[$i],";
            $one_update .= "$cl_Memory_active_KB[$i],$cl_Memory_granted_KB[$i],";
            $one_update .= ( ( $cl_Memory_compressed_KB[$i] ne "U" ) ? $cl_Memory_compressed_KB[$i] * $kb : $cl_Memory_compressed_KB[$i] ) . ",";

            # $one_update    .= "$cl_Memory_swap_KB[$i],$cl_Memory_compression_KBps[$i],";
            $one_update .= "$cl_Memory_swap_KB[$i],";
            $one_update .= ( ( $cl_Memory_compression_KBps[$i] ne "U" ) ? $cl_Memory_compression_KBps[$i] * $kb : $cl_Memory_compression_KBps[$i] ) . ",";

            # $one_update    .= "$cl_Memory_decompress_KBps[$i],$cl_cpu_limit[$i],$cl_cpu_reservation[$i],";
            $one_update    .= ( ( $cl_Memory_decompress_KBps[$i] ne "U" ) ? $cl_Memory_decompress_KBps[$i] * $kb : $cl_Memory_decompress_KBps[$i] ) . ",";
            $one_update    .= "$cl_cpu_limit[$i],$cl_cpu_reservation[$i],";
            $one_update    .= "$cl_mem_limit[$i],$cl_mem_reservation[$i],U ";                                                                                # U for added CPU proc
            $update_string .= "$one_update";
          }
          else {
            $one_update = "$cl_CPU_usage_MHz[$i],";
            $one_update    .= "$cl_Memory_shared_KB[$i],$cl_Memory_zero_KB[$i],";
            $one_update    .= "$cl_Memory_baloon_KB[$i],$cl_Memory_consumed_KB[$i],$cl_Memory_overhead_KB[$i],";
            $one_update    .= "$cl_Memory_active_KB[$i],$cl_Memory_granted_KB[$i],$cl_Memory_compressed_KB[$i],";
            $one_update    .= "$cl_Memory_swap_KB[$i],$cl_Memory_compression_KBps[$i],";
            $one_update    .= "$cl_Memory_decompress_KBps[$i],$cl_cpu_limit[$i],$cl_cpu_reservation[$i],";
            $one_update    .= "$cl_mem_limit[$i],$cl_mem_reservation[$i],U ";                                                                                # U for added CPU proc
            $update_string .= "$one_update";
          }
        }

        # print "string for RRD file update is:\n$update_string,xorux_sentinel\n";
        # print "---------------------------------------------------\n\n";

        my $input_vm_uuid = $rp_moref;
        $type_sam = "c";

        $SSH = "";

        my $managedname_save = $managedname;
        my $host_save        = $host;

        #        my $res_update = LoadDataModuleVMWare::load_data( $managedname_save, $host_save, $wrkdir, \$update_string, $type_sam, $act_time, $HMC, $IVM, $SDMC, $step, $DEBUG, \@lpar_trans, $last_file, $no_time, $SSH, $hmc_user, $input_vm_uuid, $entity_type, "(".$$."F$server_count)" );
        if ( $i_am_fork eq "fork" ) {
          print "update_line,$managedname_save,$host_save,$wrkdir,\$update_string,$type_sam,$act_time,$HMC,$IVM,$SDMC,$step,$DEBUG,\@lpar_trans,$last_file,$no_time,$SSH,$hmc_user,$input_vm_uuid,$entity_type,(" . $$ . "F$server_count),$update_string,xorux_sentinel\n";
        }
        else {
          push @all_vcenter_perf_data, "update_line,$managedname_save,$host_save,$wrkdir,\$update_string,$type_sam,$act_time,$HMC,$IVM,$SDMC,$step,$DEBUG,\@lpar_trans,$last_file,$no_time,$SSH,$hmc_user,$input_vm_uuid,$entity_type,(" . $$ . "F$server_count),$update_string,xorux_sentinel\n";
        }

      }
      else {    # or historical data
                # print "----- before \$h_name $h_name \$host $host\n";
        prepare_last_time( $resourcepool, $et_ResourcePool, $rp_name, $rp_moref );    # hash, type, name, moref
                                                                                      # print "----- after \$h_name $h_name \$host $host\n";
      }

      # touch user resourcepool name <user name>.uuid
      my $rp_name_file = "$rp_name.$rp_moref";
      if ( !-f "$wrkdir/$managedname/$host/$rp_name_file" ) {
        `rm -f "$wrkdir/$managedname/$host"/*."$rp_moref"`;                           # in case there are more names
        `touch "$wrkdir/$managedname/$host/$rp_name_file"`;                           # save user rp name
        LoadDataModuleVMWare::touch("$wrkdir/$managedname/$host/$rp_name_file");
      }
      if ( !-f "$wrkdir/$managedname/$host/$rp_moref.rrc" ) {                         # if resourcepool has no data
        `touch "$wrkdir/$managedname/$host/$rp_moref.rrc"`;

        # print "signal file : $wrkdir/$managedname/$host/$rp_moref.rrc touched as resourcepool\n";
        LoadDataModuleVMWare::touch("$wrkdir/$managedname/$host/$rp_moref.rrc");

        # just to say install-html.sh to create item in menu.txt
        # signal file will be overwritten by creating real rrd file in LoadDataModuleVmware.pm after data coming
      }

      make_cmd_frame_multiview( $managedname, $host, $et_ResourcePool );
    }

    # print Dumper ("1551",\%rp_group_path);
    # time to save RP folder pathes
    # print "1555 $rp_path_file_to_save\n";
    if ( !Xorux_lib::write_json( $rp_path_file_to_save, \%rp_group_path ) ) {
      error( "Cannot save $rp_path_file_to_save: " . __FILE__ . ":" . __LINE__ );
    }

    open my $FH_path, ">$all_paths_file" or error( "can't open $all_paths_file: $!" . __FILE__ . ":" . __LINE__ ) && next;
    foreach my $new_line (@all_paths) {
      chomp($new_line);
      print $FH_path $new_line . "\n";
    }
    close $FH_path;

    # write rp config
    open $FH_path, ">$wrkdir/$managedname/$host/rp_config.txt" or error( "can't open $wrkdir/$managedname/$host/rp_config.txt: $!" . __FILE__ . ":" . __LINE__ ) && next;
    foreach my $new_line (@rp_setting) {
      chomp($new_line);
      print $FH_path $new_line . "\n";
    }
    close $FH_path;

    # write rp config html
    my $res_ret        = FormatResults( \@rp_setting );
    my $html_file_name = "$wrkdir/$managedname/$host/rp_config.html";
    if ( open my $FHe, '>:encoding(UTF-8)', "$html_file_name" ) {
      print $FHe "<CENTER><TABLE class=\"tabconfig tablesorter tablesorter-ice\">\n";
      print $FHe "<thead><TR> <TH class=\"sortable\" valign=\"center\">Resource Pool</TH>
        <TH align=\"center\" class=\"sortable\" valign=\"right\">CPU Reservation (MHz)</TH>
        <TH align=\"center\" class=\"sortable\" valign=\"right\">CPU Limit (MHz)</TH>
        <TH align=\"center\" class=\"sortable\" valign=\"right\">CPU Allocation Type</TH>
        <TH align=\"center\" class=\"sortable\" valign=\"right\">CPU Shares</TH>
        <TH align=\"center\" class=\"sortable\" valign=\"left\">CPU Shares Value</TH>
        <TH align=\"center\" class=\"sortable\" valign=\"right\">MEM Reservation (MB)</TH>
        <TH align=\"center\" class=\"sortable\" valign=\"left\">MEM Limit (MB)</TH>
        <TH align=\"center\" class=\"sortable\" valign=\"right\">MEM Allocation Type</TH>
        <TH align=\"center\" class=\"sortable\" valign=\"right\">MEM Shares</TH>
        <TH align=\"center\" class=\"sortable\" valign=\"left\">MEM Shares Value</TH>
        </TR></thead><tbody>\n";
      print $FHe "$res_ret";
      print $FHe "</tbody></TABLE></CENTER>\n";
      close $FHe;
    }
    else {
      error( "can't open '$html_file_name': $!" . __FILE__ . ":" . __LINE__ );
    }

    print "writing respool: $all_paths_file\n";
  }
}

sub datastore_perf {

  # global var
  # $h_name  datastore_'datacenter name'
  # $datastore_list
  # dir for saving perf is $wrkdir/$managedname/$h_name
  # my @datastore_VM = ();    # active VM list
  $latency_peak_reached_count = 0;

  $do_fork      = "0";    # do not use 1 @Jindra_K
  %fork_handles = ();
  @returns      = ();
  @pid          = ();
  $cycle_count  = 1;

  # until 4.81-004 datastore files had own user name, but problem with renaming
  # since then datastore files are uuid and there is touched file <datastore name>.uuid
  my $datastore_number = scalar @$datastore_list;
  if ( ( !defined $datastore_number ) || ( $datastore_number eq "" ) || ( $datastore_number < 1 ) ) {
    error( "no datastores in $host $host_orig: " . __FILE__ . ":" . __LINE__ );
    return;
  }
  print "Datastores #   : $host $host_orig $datastore_number start " . localtime() . "\n";

  if ( $datastore_number <= $datastores_in_fork ) {    # no fork
    my $index_from = 0;
    my $index_to   = $datastore_number - 1;

    datastore_perf_engine( $datastore_list, $index_from, $index_to );

    if ( $latency_peak_reached_count > 0 ) {
      print "Notice         : total Read/Write Latency_limit peak reached: $latency_peak_reached_count times for datacenter $h_name for $alias for $host_orig\n";
    }
    print "Datastores #   : $host $host_orig $datastore_number finish " . localtime() . "\n";
    return;
  }

  # cycle of forks
  my $index_from = 0;
  my $index_to   = $datastores_in_fork - 1;

  while ( $datastore_number > 0 ) {

    local *FH;
    $pid[$server_count] = open( FH, "-|" );

    # $pid[$server_count] = fork();
    if ( not defined $pid[$server_count] ) {
      error("$host:$managedname datastores could not fork");
    }
    elsif ( $pid[$server_count] == 0 ) {
      print "Fork DSTR      : $host:$managedname : $server_count " . localtime() . " child pid $$\n" if $DEBUG;

      #my $i_am_fork = "fork";
      $i_am_fork = "fork";

      #      RRDp::end;
      #      RRDp::start "$rrdtool";

      eval { Util::connect(); };
      if ($@) {
        my $ret = $@;
        chomp($ret);
        error( "vmw2rrd failed: $ret " . __FILE__ . ":" . __LINE__ );

        #        RRDp::end;
        exit(1);
      }

      # locale for english
      my $serviceContent = Vim::get_service_content();
      my $sessionManager = Vim::get_view( mo_ref => $serviceContent->sessionManager );
      $sessionManager->SetLocale( locale => "en" );

      #        $sessionManager->SetLocale(locale => "de");

      Opts::assert_usage( defined($sessionManager), "No sessionManager." );

      $service_instance = Vim::get_service_instance();
      datastore_perf_engine( $datastore_list, $index_from, $index_to );

      #      RRDp::end;
      eval { Util::disconnect(); };
      if ($@) {
        my $ret = $@;
        chomp($ret);
        error( "vmw2rrd failed: $ret " . __FILE__ . ":" . __LINE__ );
      }

      if ( $latency_peak_reached_count > 0 ) {
        print "Notice         : total Read/Write Latency_limit peak reached: $latency_peak_reached_count times for datacenter $h_name for $alias for $host_orig\n";
      }
      print "Fork DSTR exit : $host:$managedname : $server_count " . localtime() . "\n" if $DEBUG;
      exit(0);
    }
    $datastore_number = $datastore_number - $datastores_in_fork;
    $index_from       = $index_to + 1;
    $index_to         = $index_from + $datastores_in_fork - 1;
    if ( $datastore_number < $datastores_in_fork ) {
      $index_to = $index_from + $datastore_number - 1;
    }
    print "Parent continue: DSTR $host:$managedname $pid[$server_count ] parent pid $$ from $index_from to $index_to\n";
    $server_count++;

    push @returns, *FH;

    $cycle_count++;
  }

  # this operation should clear all finished forks 'defunct'
  print_fork_dstr_output();

  print "Datastores #   : $host $host_orig $datastore_number finish " . localtime() . "\n";

}

sub datastore_perf_engine {
  my $datastore_list = shift;
  my $index_from     = shift;
  my $index_to       = shift;

  print "Datastory      : \$index_from $index_from \$index_to $index_to\n";
  foreach my $datastore ( @$datastore_list[ $index_from .. $index_to ] ) {
    if ( !defined $datastore ) {
      print "! defined \$datastore $index_from - $index_to\n";
      next;
    }
    $ds_type = "";
    $ds_name = $datastore->name;

    #  datastore to exclude
    my $exclude = 0;
    foreach my $pattern (@ds_name_patterns_to_exclude) {
      $exclude = 1 if ( index( $ds_name, $pattern ) > -1 );
    }
    if ($exclude) {
      print "exclude DS : $ds_name\n";
      next;
    }

    $ds_parent_folder = $datastore->parent->value;
    $ds_accessible    = $datastore->summary->accessible;    # 1=true/0=false
                                                            # print "datastore \$ds_name $ds_name \$ds_accessible ,$ds_accessible,\n";
    $ds_freeSpace     = $datastore->summary->freeSpace;
    $ds_freeSpace     = $ds_freeSpace / 1024 if !$NG;       # to be in KB
    $ds_capacity      = $datastore->summary->capacity;
    $ds_capacity      = $ds_capacity / 1024 if !$NG;        # to be in KB
    $ds_used          = $ds_capacity - $ds_freeSpace;
    $ds_provisioned   = $datastore->summary->uncommitted;
    if ( !defined $ds_provisioned ) { $ds_provisioned = 0 }
    $ds_provisioned = $ds_provisioned / 1024 if !$NG;       # to be in KB
    $ds_provisioned = $ds_used + $ds_provisioned;
    my $ds_uuid;

    # getting volume ID for STOR2RRD
    my $disk_uids = "";

    # vcenter must know its alias, alias can be changed anytime, this is necessary for non cluster vcenter
    my $my_alias_file_name = "$wrkdir/$managedname/vmware_alias_name";
    open my $FH_ali, ">$my_alias_file_name" or error( "can't open $my_alias_file_name: $!" . __FILE__ . ":" . __LINE__ );
    print $FH_ali "$h_name|$alias\n";                       # save cluster name and alias, ! when there is no cluster, you store the last $h_name
    close $FH_ali;

    # check if it is usual VMFS datastore
    if ( exists $datastore->info->{"vmfs"} ) {
      $ds_uuid = $datastore->info->vmfs->uuid;
      if ( exists $datastore->info->{"vmfs"}->{"extent"} ) {

        # print Dumper ("2051", $datastore->info->{"vmfs"}->{"extent"} );
        my $extent = $datastore->info->{"vmfs"}->{"extent"};
        foreach my $partition (@$extent) {
          my $volume_id = $partition->diskName;
          if ( $volume_id ne "" ) {
            $volume_id =~ s/^naa\.//;    # remove unnecessary chars
            $disk_uids .= $volume_id;
            $disk_uids .= " ";
          }
        }

        # print "2053 \$disk_uids $disk_uids\n";
      }
    }

    # check if it is NFS
    elsif ( exists $datastore->info->{"nas"} ) {

      # print Dumper ($datastore->info);
      if ( $datastore->info->{"nas"}->type !~ "^NFS" || !exists $datastore->info->{"url"} ) {
        error( "bad NFS datastore info $ds_name " . __FILE__ . ":" . __LINE__ );
        print Dumper ( $datastore->info );
      }
      else {
        my $url = $datastore->info->{"url"};

        # 'url' => 'ds:///vmfs/volumes/5e336b5d-d04e4379/'
        # print "\$datastore info- url $url\n";
        ( undef, $url ) = split( "volume", $url );    # intentionally not volumes
        ( undef, $url, undef ) = split( "\/", $url );

        # print "1498 \$datastore info- url $url \$ds_freeSpace $ds_freeSpace \$ds_capacity $ds_capacity \$ds_used $ds_used \$ds_provisioned $ds_provisioned\n";
        $ds_uuid = $url;
        $ds_type = "NFS";
      }
    }
    else {
      # check if it is VSAN
      if ( exists $datastore->info->{"url"} ) {

        # 'url' => 'ds:///vmfs/volumes/vsan:5255e2a818d36446-b66c11540e875700/',
        my $url_vsan = $datastore->info->{"url"};

        # print "\$datastore info- url $url\n";
        ( undef, my $url ) = split( "vsan:", $url_vsan );    # intentionally not volumes
        if ( !defined $url || $url eq "" ) {
          error( "not known url $url_vsan for VSAN datastore $ds_name " . __FILE__ . ":" . __LINE__ ) && next;
        }

        ( $url, undef ) = split( "\/", $url );

        # print "\$datastore info- url $url\n";
        $ds_uuid = $url;
        $ds_type = "VSAN";
      }
      else {
        print Dumper ( $datastore->info );
        print STDERR Dumper( $datastore->info );
        error( "cannot find uuid for datastore (no type vmfs nor nfs nor vsan) $ds_name " . __FILE__ . ":" . __LINE__ ) && next;
      }
    }

    # print "\$ds_freeSpace $ds_freeSpace \$ds_capacity $ds_capacity \$ds_used $ds_used \$ds_provisioned $ds_provisioned\n" if ($apiType_top =~ "HostAgent" );

    if ( !defined $ds_uuid || ( !uuid_check_ds($ds_uuid) && !uuid_check_ds_nfs($ds_uuid) && !uuid_check_ds_vsan($ds_uuid) ) ) {
      error( "cannot find uuid for datastore $ds_name " . __FILE__ . ":" . __LINE__ ) && next;
    }

    print "retrieving perf: datastore $ds_name (" . $$ . "F$server_count)\n";
    $fail_entity_name = $ds_name;
    $fail_entity_type = $et_Datastore;

    # existing must be renamed
    my $ds_path = "$wrkdir/$managedname/$h_name";
    if ( -f "$ds_path/$ds_name.rrt" ) {
      move( "$ds_path/$ds_name.rrt", "$ds_path/$ds_uuid.rrt" ) || error( " Cannot move $ds_path/$ds_name.rrt to $ds_path/$ds_uuid.rrt: $!" . __FILE__ . ":" . __LINE__ ) && next;

      if ( -f "$ds_path/$ds_name.rrs" ) {
        move( "$ds_path/$ds_name.rrs", "$ds_path/$ds_uuid.rrs" ) || error( " Cannot move $ds_path/$ds_name.rrs to $ds_path/$ds_uuid.rrs: $!" . __FILE__ . ":" . __LINE__ ) && next;
      }
      if ( -f "$ds_path/$ds_name.last" ) {
        move( "$ds_path/$ds_name.last", "$ds_path/$ds_uuid.last" ) || error( " Cannot move $ds_path/$ds_name.last to $ds_path/$ds_uuid.last: $!" . __FILE__ . ":" . __LINE__ );
      }
      if ( -f "$ds_path/$ds_name.html" ) {
        move( "$ds_path/$ds_name.html", "$ds_path/$ds_uuid.html" ) || error( " Cannot move $ds_path/$ds_name.html to $ds_path/$ds_uuid.html: $!" . __FILE__ . ":" . __LINE__ );
      }
      print "renamed d-stor : $ds_path/$ds_name to $ds_path/$ds_uuid\n";
    }

    # new solution after 4.81-004

    # touch user datastore name <user name>.uuid
    my $datastore_name_file = "$ds_name.$ds_uuid";
    if ( !-f "$wrkdir/$managedname/$h_name/$datastore_name_file" ) {
      `rm -f "$wrkdir/$managedname/$h_name"/*."$ds_uuid"`;            # in case there are more names
      `touch "$wrkdir/$managedname/$h_name/$datastore_name_file"`;    # save user datacenter name
      LoadDataModuleVMWare::touch("$wrkdir/$managedname/$h_name/$datastore_name_file");
    }

    # save to that file datastore parent folder group
    if ( open my $FH_dst, ">$wrkdir/$managedname/$h_name/$datastore_name_file" ) {
      print $FH_dst $ds_parent_folder;
      close $FH_dst;
    }
    else {
      error( "can't write to '$wrkdir/$managedname/$h_name/$datastore_name_file': $!" . __FILE__ . ":" . __LINE__ );
    }

    if ( !-f "$wrkdir/$managedname/$h_name/$ds_uuid.rrt" ) {    # if datastore has no data
      `touch "$wrkdir/$managedname/$h_name/$ds_uuid.rrt"`;

      # print "signal file : $wrkdir/$managedname/$h_name/$ds_uuid.rrt touched\n";
      LoadDataModuleVMWare::touch("$wrkdir/$managedname/$h_name/$ds_uuid.rrt");

      # just to say install-html.sh to create item in menu.txt
      # signal file will be overwritten by creating real rrd file in LoadDataModuleVmware.pm after data coming
    }

    # storing volume ID for STOR2RRD
    if ( $disk_uids ne "" ) {
      if ( open my $fhide, ">$wrkdir/$managedname/$h_name/$ds_uuid.disk_uids" ) {
        print $fhide $disk_uids;
        close $fhide;
      }
      else {
        error( "can't write to '$wrkdir/$managedname/$h_name/$ds_uuid.disk_uids': $!" . __FILE__ . ":" . __LINE__ );
      }
    }
    else {
      unlink "$wrkdir/$managedname/$h_name/$ds_uuid.disk_uids";
    }

    # create html list of active VMs & list of mounted ESXi

    my @datastore_VM          = ();                 # active VM list
    my $host_mounted          = 0;
    my $hosts_mounted         = $datastore->host;
    my $html_table_esxi_lines = "";

    # print Dumper ("2205",\%esxi_dbi_uuid_hash);
    # $esxi_dbi_uuid_hash{'host-37'} = 'eb6102a7-1fa0-4376-acbb-f67e34a2212c_28_cluster_domain-c87_esxi_10.22.11.8';

    # print Dumper ($hosts_mounted);
    if ( defined $hosts_mounted ) {
      $host_mounted = scalar @$hosts_mounted;
      foreach (@$hosts_mounted) {

        # prepare host name (or moref)
        my $moref      = $_->{'key'}->value;
        my $moref_name = $host_moref_name{$moref};
        $moref_name = $moref if !defined $moref_name;
        if ( exists $esxi_dbi_uuid_hash{$moref} ) {
          my $access_mode = $_->mountInfo->accessMode;
          my $accessible  = $_->mountInfo->accessible;

          #print "2510 \$access_mode $access_mode \$accessible $accessible\n";

          # print "2219 \$moref $moref ".$esxi_dbi_uuid_hash{$moref}."\n";
          # 2219 $moref host-37 eb6102a7-1fa0-4376-acbb-f67e34a2212c_28_cluster_domain-c87_esxi_10.22.11.8
          # for XORMON prepare esxi uuid # eb6102a7-1fa0-4376-acbb-f67e34a2212c_28_cluster_domain-c87_esxi_10.22.11.14
          # $esxi_dbi_uuid = "$managedname"."_esxi_"."$esxi_uuid";
          # $esxi_dbi_uuid =~ s/vmware_//;
          $html_table_esxi_lines .= "<TR> <TD><A HREF=\"/lpar2rrd-cgi/detail.sh?host=10.22.11.10&server=10.22.11.14&lpar=pool&item=pool&entitle=0&none=none&d_platform=VMware&esxi_dbi_uuid=" . $esxi_dbi_uuid_hash{$moref} . "\"><B>$moref_name</B></A></TD> <TD align=\"right\" nowrap>$accessible</TD><TD align=\"right\" nowrap>$access_mode</TD></TR>\n";
        }
        else {
          error( "no esxi_dbi_uuid for \$moref $moref" . __FILE__ . ":" . __LINE__ );
        }
      }
    }
    else {
      $host_mounted = 0;
      print "Notice         : datastore $ds_name ($ds_uuid) has 0 mounted ESXi (" . $$ . "F$server_count)\n";

      # error("datastore $ds_name ($ds_uuid) has 0 mounted ESXi ".__FILE__.":".__LINE__);
      # xerror("datastore $ds_name ($ds_uuid) has 0 mounted ESXi ".__FILE__.":".__LINE__);
    }

    my $active_VMs          = 0;
    my $html_table_vm_lines = "";

    my $datastore_moref_id = $datastore->{'mo_ref'}->value;

    my $dstr_vm_moref_list = $datastore->{'vm'};

    foreach my $each_vmm (@$dstr_vm_moref_list) {
      my $vm_moref = $each_vmm->{'value'};
      my $this_vm  = $vcenter_vm_views_hash{$vm_moref};

      # print "2537 ".$this_vm->{name}."\n";

      # print Dumper ("2506 $datastore_moref_id",$_->{'storage'});
      #$VAR2 = bless( {
      #    'timestamp' => '2022-12-09T12:25:15.865999Z',
      #    'perDatastoreUsage' =>
      #   [
      #    bless( {
      #      'committed' => '4853261861',
      #      'datastore' => bless( {
      #        'value' => 'datastore-1083',
      #        'type' => 'Datastore'
      #        }, 'ManagedObjectReference' ),
      #      'unshared' => '13358858240',
      #      'uncommitted' => '18853397561'
      #      }, 'VirtualMachineUsageOnDatastore' ),
      #    bless( {
      #      'committed' => '0',
      #      'datastore' => bless( {
      #        'value' => 'datastore-1070',
      #        'type' => 'Datastore'
      #        }, 'ManagedObjectReference' ),
      #      'unshared' => '0',
      #      'uncommitted' => '32212255273'
      #      }, 'VirtualMachineUsageOnDatastore' )
      #   ]
      #}, 'VirtualMachineStorageInfo' );

      # my $vm_mo_ref_id = this_vm->{'mo_ref'}->value;
      my $vm_name_without_comma = $this_vm->{'name'};
      $vm_name_without_comma =~ s/,//g;

      # for XORMON prepare vm uuid
      my $vm_dbi_uuid = $this_vm->{'config.instanceUuid'};
      $vm_dbi_uuid = "undefined_uuid" if !defined $vm_dbi_uuid;
      my $vm_uuid = $vm_dbi_uuid;
      $vm_dbi_uuid = "$managedname" . "_vm_" . "$vm_dbi_uuid";
      $vm_dbi_uuid =~ s/vmware_//;
      my $a_href = "<A HREF=\"/lpar2rrd-cgi/detail.sh?host=$host_orig&server=&lpar=$vm_name_without_comma&item=lpar&entitle=0&none=none&d_platform=VMware&vm_dbi_uuid=$vm_dbi_uuid\">";

      # print "2254 $wrkdir/vmware_VMs/$vm_uuid.rrm\n";
      if ( !-f "$wrkdir/vmware_VMs/$vm_uuid.rrm" ) {
        $a_href = "";
        next;
      }

      # powered off VMs are in menu only for 30 days, then there is not possible to backling (see find_active_lpar.pl)
      my $last_timestamp = ( stat("$wrkdir/vmware_VMs/$vm_uuid.rrm") )[9];
      if ( $last_timestamp < ( time() - ( 30 * 86400 ) ) ) {    #$actual_last_30_days
        $a_href = "";
      }

      my $power_state = $this_vm->{'runtime.powerState'}->{val};

      my $storage_com   = sprintf( "%.1f", ( ( $this_vm->{'summary.storage.committed'} ) / 1024 / 1024 / 1024 ) );
      my $storage_uncom = sprintf( "%.1f", ( ( $this_vm->{'summary.storage.uncommitted'} ) / 1024 / 1024 / 1024 ) );
      my $storage_total = sprintf( "%.1f", $storage_com + $storage_uncom );

      # it is necessary to look for VM storage for that exact datastore, there can be more datastores
      foreach my $poi ( $this_vm->{'storage'}{'perDatastoreUsage'} ) {
        foreach my $dstr ( @{$poi} ) {
          my $xhash  = { %{$dstr} };
          my $ds_mor = $xhash->{'datastore'}{'value'};

          # warn Dumper $xhash;
          next if $ds_mor ne $datastore_moref_id;    # filtr just for this datastore
                                                     # warn Dumper $xhash;
          $storage_com   = sprintf( "%.1f", ( ( $xhash->{'committed'} ) / 1024 / 1024 / 1024 ) );
          $storage_total = sprintf( "%.1f", ( ( $xhash->{'committed'} + $xhash->{'uncommitted'} ) / 1024 / 1024 / 1024 ) );

          # warn "2570 \$storage_com $storage_com \$storage_total $storage_total\n";
        }
      }

      # warn "2572 \$storage_com $storage_com \$storage_total $storage_total \$ds_name $ds_name \$vm_name_without_comma $vm_name_without_comma\n";
      # print "VM: ".$_->{'name'}."\t".$_->{'config.instanceUuid'}."\t".$_->{'runtime.powerState'}->{val}."\n";
      # $html_table_vm_lines .= "<TR> <TD><A HREF=\"/lpar2rrd-cgi/detail.sh?host=$host_orig&server=&lpar=$vm_name_without_comma&item=lpar&entitle=0&none=none&d_platform=VMware&vm_dbi_uuid=$vm_dbi_uuid\"><B>".$vm_name_without_comma."</B></A></TD> <TD align=\"right\" nowrap>".$power_state."</TD></TR>\n";
      $html_table_vm_lines .= "<TR> <TD>$a_href<B>" . $vm_name_without_comma . "</B></A></TD> <TD align=\"right\" nowrap>" . $power_state . "</TD> <TD align=\"right\" nowrap>" . $storage_total . "</TD> <TD align=\"right\" nowrap>" . $storage_com . "</TD></TR>\n";
      push @datastore_VM, $vm_name_without_comma . ',' . $power_state;
      $active_VMs++ if $power_state eq 'poweredOn';
    }

    # if ( !$active_VMs ) { # not necessary to print it
    #   print "Notice         : datastore $ds_name ($ds_uuid) has 0 active VMs (".$$."F$server_count)\n";

    #  # error("datastore $ds_name ($ds_uuid) has 0 active VMs ".__FILE__.":".__LINE__);
    #  # xerror("datastore $ds_name ($ds_uuid) has 0 active VMs ".__FILE__.":".__LINE__);
    # } ## end if ( !$active_VMs )

    # print Mounted ESXI table
    open my $FH_enc, '>:encoding(UTF-8)', "$wrkdir/$managedname/$h_name/$ds_uuid.html" or error( "can't open '$wrkdir/$managedname/$h_name/$ds_uuid.html': $!" . __FILE__ . ":" . __LINE__ ) && next;
    print $FH_enc "<CENTER><TABLE class=\"lparsearch tablesorter\">\n";
    print $FH_enc "<thead><TH class=\"sortable\">Mounted ESXi name</TH><TH class=\"sortable\">accessible&nbsp;&nbsp;</TH><TH class=\"sortable\">access mode&nbsp;&nbsp;</TH></thead>\n";

    # print $FH_enc "<tbody>$res_ret</tbody>";
    print $FH_enc "<tbody>$html_table_esxi_lines</tbody>";
    print $FH_enc "</TABLE></CENTER>";

    # print Mounted VM table
    print $FH_enc "<BR><CENTER><TABLE class=\"lparsearch tablesorter\" class=\"tbl2leftotherright tablesorter\" data-sortby=\"-1\">\n";
    print $FH_enc "<thead><TH class=\"sortable\">VM name&nbsp;&nbsp;&nbsp;&nbsp;</TH><TH class=\"sortable\">VM status&nbsp;&nbsp;&nbsp;&nbsp;</TH><TH class=\"sortable\">Provisioned space GB&nbsp;&nbsp;&nbsp;&nbsp;</TH><TH class=\"sortable\">Used space GB&nbsp;&nbsp;&nbsp;&nbsp;</TH></thead>\n";

    #print $FH_enc "<tbody>$res_ret</tbody>";
    print $FH_enc "<tbody>$html_table_vm_lines</tbody>";
    print $FH_enc "</TABLE></CENTER><BR>\n";
    close $FH_enc;

    my $vm_count = scalar @datastore_VM;
    print "VM list        : written \$wrkdir/$managedname/$h_name/$ds_uuid.html($ds_name) $vm_count/$active_VMs Total/Active VMs\n";    # @datastore_VM $res_ret\n";

    # can we test if a datastore has any living VM ? If not so there is no IO data for datastore from VMs side
    # but there can be some IO data on datastore cus vCenter communicates with datastores
    #
    # construct datastore counters IOPS, Read/Write and Latency from VM counters
    # example of data line
    #  vm_dstr_counter_data,500f3bb6-f151-1c05-92ab-4555a8013a19,591c40de-576c4922-9ce2-e4115bd41b18,178,60,1497974600 1497974620,2,2,0,7,2,1,3,3,2 total 60 numbers
    #  identification,      vm_uuid,                             datastore_uuid,              counter_id, num_of_samples, 1st timestamp, 2nd timestamp, data

    my $entity_uuid         = $ds_uuid;
    my $entity_type         = $et_Datastore;
    my $entity              = $datastore;
    my @vm_time_stamps      = ();
    my @vm_time_stamps_temp = ();
    my $samples_number_temp = 0;
    my $samples_number      = 0;
    @ds_Datastore_totalWriteLatency = ();
    @ds_Datastore_totalReadLatency  = ();

    my @dstr_uuid            = grep {/$entity_uuid,$vm_dstr_readAveraged_key/} @vm_dstr_counter_data;
    my @dstr_vm_readAveraged = @dstr_uuid;                                                              # for individual datastore VM IOPS & for Latency computation
                                                                                                        # print "1642 ,$entity_uuid,$vm_dstr_readAveraged_key,\n";
                                                                                                        # print "1643 read IOPS \@dstr_uuid @dstr_uuid\n";

    if ( defined $dstr_uuid[0] ) {
      $samples_number_temp = prepare_datastore_counter_values( \@dstr_uuid, \@vm_time_stamps_temp, \@ds_Datastore_numberReadAveraged );
      if ( $samples_number_temp > $samples_number ) {                                                   # test if realtime data or longer interval data
        $samples_number = $samples_number_temp;
        @vm_time_stamps = @vm_time_stamps_temp;
      }

      # print "1666 $vm_dstr_readAveraged_key @ds_Datastore_numberReadAveraged \$samples_number_temp $samples_number_temp $vm_time_stamps[0],$vm_time_stamps[1]\n";
    }

    @dstr_uuid = grep {/$entity_uuid,$vm_dstr_writeAveraged_key/} @vm_dstr_counter_data;
    my @dstr_vm_writAveraged = @dstr_uuid;    # for individual datastore VM IOPS & for Latency computation

    # print "1658 write IOPS \@dstr_uuid @dstr_uuid\n";

    if ( defined $dstr_uuid[0] ) {
      $samples_number_temp = prepare_datastore_counter_values( \@dstr_uuid, \@vm_time_stamps_temp, \@ds_Datastore_numberWriteAveraged );
      if ( $samples_number_temp > $samples_number ) {
        $samples_number = $samples_number_temp;
        @vm_time_stamps = @vm_time_stamps_temp;
      }
    }

    @dstr_uuid = grep {/$entity_uuid,$vm_dstr_read_key/} @vm_dstr_counter_data;

    # print "1667 \@dstr_uuid @dstr_uuid\n";
    if ( defined $dstr_uuid[0] ) {
      $samples_number_temp = prepare_datastore_counter_values( \@dstr_uuid, \@vm_time_stamps_temp, \@ds_Datastore_read_KBps );
      if ( $samples_number_temp > $samples_number ) {
        $samples_number = $samples_number_temp;
        @vm_time_stamps = @vm_time_stamps_temp;
      }
    }

    @dstr_uuid = grep {/$entity_uuid,$vm_dstr_write_key/} @vm_dstr_counter_data;

    # print "1676 \@dstr_uuid @dstr_uuid\n";
    if ( defined $dstr_uuid[0] ) {
      $samples_number_temp = prepare_datastore_counter_values( \@dstr_uuid, \@vm_time_stamps_temp, \@ds_Datastore_write_KBps );
      if ( $samples_number_temp > $samples_number ) {
        $samples_number = $samples_number_temp;
        @vm_time_stamps = @vm_time_stamps_temp;
      }
    }

    @dstr_uuid = grep {/$entity_uuid,$vm_dstr_readLatency_key/} @vm_dstr_counter_data;
    my @dstr_vm_readLatency = @dstr_uuid;    # for Latency computation & possible individual datastore VM Latency saving (not implemented yet)

    # print "1685 read Latency \@dstr_uuid @dstr_uuid\n";
    if ( defined $dstr_uuid[0] && scalar @dstr_uuid == 1 ) {
      $samples_number_temp = prepare_datastore_counter_values( \@dstr_uuid, \@vm_time_stamps_temp, \@ds_Datastore_totalReadLatency );
      if ( $samples_number_temp > $samples_number ) {
        $samples_number = $samples_number_temp;
        @vm_time_stamps = @vm_time_stamps_temp;
      }

      # remove peaks higher than $ds_totalReadLatency_limit
      foreach (@ds_Datastore_totalReadLatency) {
        if ( $_ ne "U" && $_ > $ds_totalReadLatency_limit ) {
          $_ = "U";

          # error("totalReadLatency_limit peak in @dstr_uuid ".__FILE__.":".__LINE__);
          $latency_peak_reached_count++;
        }
      }
    }
    elsif ( defined $dstr_uuid[0] && scalar @dstr_uuid > 1 ) {
      $samples_number_temp = prepare_datastore_latency_counter_values( \@dstr_uuid, \@dstr_vm_readAveraged, \@vm_time_stamps_temp, \@ds_Datastore_totalReadLatency );
      if ( $samples_number_temp > $samples_number ) {
        $samples_number = $samples_number_temp;
        @vm_time_stamps = @vm_time_stamps_temp;
      }
    }

    @dstr_uuid = grep {/$entity_uuid,$vm_dstr_writeLatency_key/} @vm_dstr_counter_data;
    my @dstr_vm_writLatency = @dstr_uuid;    # for Latency computation & possible individual datastore VM Latency saving (not implemented yet)

    # print "1701 write Latency \@dstr_uuid @dstr_uuid\n";
    if ( defined $dstr_uuid[0] && scalar @dstr_uuid == 1 ) {
      $samples_number_temp = prepare_datastore_counter_values( \@dstr_uuid, \@vm_time_stamps_temp, \@ds_Datastore_totalWriteLatency );
      if ( $samples_number_temp > $samples_number ) {
        $samples_number = $samples_number_temp;
        @vm_time_stamps = @vm_time_stamps_temp;
      }

      # remove peaks higher than $ds_totalWriteLatency_limit
      foreach (@ds_Datastore_totalWriteLatency) {
        if ( $_ ne "U" && $_ > $ds_totalWriteLatency_limit ) {
          $_ = "U";

          # error("totalReadLatency_limit peak in @dstr_uuid ".__FILE__.":".__LINE__);
          $latency_peak_reached_count++;
        }
      }
    }
    elsif ( defined $dstr_uuid[0] && scalar @dstr_uuid > 1 ) {
      $samples_number_temp = prepare_datastore_latency_counter_values( \@dstr_uuid, \@dstr_vm_writAveraged, \@vm_time_stamps_temp, \@ds_Datastore_totalWriteLatency );
      if ( $samples_number_temp > $samples_number ) {
        $samples_number = $samples_number_temp;
        @vm_time_stamps = @vm_time_stamps_temp;
      }
    }

    if ( defined $vm_time_stamps[0] ) {

      # print "1724 \@ds_Datastore_totalReadLatency @ds_Datastore_totalReadLatency\n";
      # print "1725 \@ds_Datastore_totalWriteLatency @ds_Datastore_totalWriteLatency\n";

      # print "1722 VM data for datastore $ds_name\n";
      @ds_Datastore_freeSpace_KB = ($ds_freeSpace) x $samples_number;
      @ds_Datastore_used_KB      = ($ds_used) x $samples_number;
      @ds_Datastore_provision_KB = ($ds_provisioned) x $samples_number;
      @ds_Datastore_capacity_KB  = ($ds_capacity) x $samples_number;

      # recreate time stamps
      for ( my $i = 2; $i < ($samples_number); $i++ ) {
        $vm_time_stamps[$i] = $vm_time_stamps[ $i - 1 ] + ( $vm_time_stamps[1] - $vm_time_stamps[0] );
      }

      # print "1728 vmw2rrd.pl @vm_time_stamps\n";

      my $update_string     = "";
      my $update_stri_NG    = "";
      my $two_update_string = "";
      my $one_update;
      my $two_update;
      my $tri_update = "";
      my $kb         = 1024;

      my $error_U_U = 0;    # catch ,read:U,write:U, errors and print only one protocol line
      for ( my $i = 0; $i < $samples_number; $i++ ) {
        $vm_time_stamps[$i] = int( $vm_time_stamps[$i] );
        $update_string  .= "$vm_time_stamps[$i],";
        $update_stri_NG .= "$vm_time_stamps[$i],";

        #          $two_update_string .= "$vm_time_stamps[$i],";

        # cus 30 minutes getting data for used/provisioned/capacity/(freeSpace) there are two data files
        # datastore.rrs - for mentioned above
        # datastore.rrt - for the rest ds's (regular update)
        # example for load time = 10 minutes
        # 1442308800,3697908121600,-1,-1,-1,559,2570,34,116 1442309100,3697908121600,1757208576,4664769308,5368446976,501,4631,36,121
        # 1442326200,2587793293312,U,U,U,43,2736,4,293 1442326500,2587793293312,U,U,U,156,2499,4,270

        $two_update = "$ds_Datastore_freeSpace_KB[$i],$ds_Datastore_used_KB[$i],";
        $two_update .= "$ds_Datastore_provision_KB[$i],$ds_Datastore_capacity_KB[$i] ";
        if ( ( index( $two_update, '-1,-1,-1' ) < 0 ) && ( index( $two_update, 'U,U,U' ) < 0 ) ) {
          $two_update_string .= "$vm_time_stamps[$i],$two_update";
          $update_stri_NG    .= "$ds_Datastore_freeSpace_KB[$i],$ds_Datastore_used_KB[$i],$ds_Datastore_provision_KB[$i],$ds_Datastore_capacity_KB[$i]";
        }
        else {
          $update_stri_NG .= "U,U,U,U";
        }

        if ( !defined $ds_Datastore_read_KBps[$i] or !defined $ds_Datastore_write_KBps[$i] ) {
          error( "not defined index $i for datastore $ds_name " . __FILE__ . ":" . __LINE__ );
          $update_string  .= "U,U,U,U ";
          $update_stri_NG .= ",U,U,U,U";
        }
        else {
          $one_update = "$ds_Datastore_read_KBps[$i],$ds_Datastore_write_KBps[$i],";
          $one_update    .= "$ds_Datastore_numberReadAveraged[$i],$ds_Datastore_numberWriteAveraged[$i] ";
          $update_string .= "$one_update";

          if ( $ds_Datastore_read_KBps[$i] eq "U" or $ds_Datastore_write_KBps[$i] eq "U" ) {

            # error( ",read:$ds_Datastore_read_KBps[$i],write:$ds_Datastore_write_KBps[$i], for datastore ($ds_name)$ds_uuid " . __FILE__ . ":" . __LINE__ );
            $error_U_U++;
          }
          if ( $ds_Datastore_read_KBps[$i] eq "U" ) {
            $update_stri_NG .= "," . $ds_Datastore_read_KBps[$i];
          }
          else {
            $update_stri_NG .= "," . $ds_Datastore_read_KBps[$i] * $kb;
          }
          if ( $ds_Datastore_write_KBps[$i] eq "U" ) {
            $update_stri_NG .= "," . $ds_Datastore_write_KBps[$i];
          }
          else {
            $update_stri_NG .= "," . $ds_Datastore_write_KBps[$i] * $kb;
          }
          $update_stri_NG .= "," . "$ds_Datastore_numberReadAveraged[$i],$ds_Datastore_numberWriteAveraged[$i]";

          # $update_stri_NG .= "," . $ds_Datastore_read_KBps[$i] * $kb . "," . $ds_Datastore_write_KBps[$i] * $kb . "," . "$ds_Datastore_numberReadAveraged[$i],$ds_Datastore_numberWriteAveraged[$i]";
        }

        #        $two_update = "$ds_Datastore_freeSpace_KB[$i],$ds_Datastore_used_KB[$i],";
        #        $two_update .= "$ds_Datastore_provision_KB[$i],$ds_Datastore_capacity_KB[$i] ";
        #        if ( ( index( $two_update, '-1,-1,-1' ) < 0 ) && ( index( $two_update, 'U,U,U' ) < 0 ) ) {
        #          $two_update_string .= "$vm_time_stamps[$i],$two_update";
        #        }

        $tri_update     .= "$vm_time_stamps[$i],$ds_Datastore_totalReadLatency[$i],$ds_Datastore_totalWriteLatency[$i],U ";    # instead of U later datastore queue depth
        $update_stri_NG .= ",$ds_Datastore_totalReadLatency[$i],$ds_Datastore_totalWriteLatency[$i],U ";
      }
      if ( $error_U_U > 0 ) {
        error( ",read:U,write:U, ($error_U_U X from $samples_number)for datastore ($ds_name)$ds_uuid " . __FILE__ . ":" . __LINE__ );
      }

      # print "string for RRD file update is:\n$update_string,xorux_sentinel\n";
      # print "---------------------------------------------------\n\n";

      my $input_vm_uuid = $vm_name_uuid{ $entity->name };
      $input_vm_uuid = $entity_uuid;
      $type_sam      = "t";            # regular update

      $SSH = "";

      my $managedname_save = $managedname;
      my $host_save        = $host;
      $last_file = "$ds_uuid.last";

      # here only datastore
      if ( ( $entity_type eq $et_Datastore ) && ( $apiType_top =~ "HostAgent" ) ) {    # only for DA by ESXi 4
                                                                                       # not prepared for NG yet @jindraK 2022-05-10
        $type_sam      = "s";
        $update_string = $two_update_string;

        #        my $res_update = LoadDataModuleVMWare::load_data( $managedname_save, $host_save, $wrkdir, \$update_string, $type_sam, $act_time, $HMC, $IVM, $SDMC, $step, $DEBUG, \@lpar_trans, $last_file, $no_time * 5, $SSH, $hmc_user, $input_vm_uuid, $entity_type, "(".$$."F$server_count)" );
        if ( $i_am_fork eq "fork" ) {
          print "update_line,$managedname_save,$host_save,$wrkdir,\$update_string,$type_sam,$act_time,$HMC,$IVM,$SDMC,$step,$DEBUG,\@lpar_trans,$last_file,$no_time,$SSH,$hmc_user,$input_vm_uuid,$entity_type,(" . $$ . "F$server_count),$update_string,xorux_sentinel\n";
        }
        else {
          push @all_vcenter_perf_data, "update_line,$managedname_save,$host_save,$wrkdir,\$update_string,$type_sam,$act_time,$HMC,$IVM,$SDMC,$step,$DEBUG,\@lpar_trans,$last_file,$no_time,$SSH,$hmc_user,$input_vm_uuid,$entity_type,(" . $$ . "F$server_count),$update_string,xorux_sentinel\n";
        }
      }
      else {
        if ( ( $entity_type eq $et_Datastore ) && ( $two_update_string ne "" ) ) {

          # print "1784 vmw2rrd.pl result update string $update_string 2 upd $two_update_string 3 upd $tri_update\n";
          #          my $res_update = LoadDataModuleVMWare::load_data( $managedname_save, $host_save, $wrkdir, \$update_string, $type_sam, $act_time, $HMC, $IVM, $SDMC, $step, $DEBUG, \@lpar_trans, $last_file, $no_time, $SSH, $hmc_user, $input_vm_uuid, $entity_type, "(".$$."F$server_count)" );
          #          if ( !$NG ) {
          if ( $i_am_fork eq "fork" ) {
            print "update_line,$managedname_save,$host_save,$wrkdir,\$update_string,$type_sam,$act_time,$HMC,$IVM,$SDMC,$step,$DEBUG,\@lpar_trans,$last_file,$no_time,$SSH,$hmc_user,$input_vm_uuid,$entity_type,(" . $$ . "F$server_count),$update_string,xorux_sentinel\n";
          }
          else {
            push @all_vcenter_perf_data, "update_line,$managedname_save,$host_save,$wrkdir,\$update_string,$type_sam,$act_time,$HMC,$IVM,$SDMC,$step,$DEBUG,\@lpar_trans,$last_file,$no_time,$SSH,$hmc_user,$input_vm_uuid,$entity_type,(" . $$ . "F$server_count),$update_string,xorux_sentinel\n";
          }

          #          if ( $res_update != $no_inserted ) left_curly    # go on only when success
          $type_sam      = "s";                  # irregular update - usually once in 30 mins
                                                 # using very long heartbeat time !!!
          $update_string = $two_update_string;

          #            $res_update    = LoadDataModuleVMWare::load_data( $managedname_save, $host_save, $wrkdir, \$update_string, $type_sam, $act_time, $HMC, $IVM, $SDMC, $step, $DEBUG, \@lpar_trans, $last_file, $no_time * 5, $SSH, $hmc_user, $input_vm_uuid, $entity_type, "(".$$."F$server_count)" );
          my $long_time = $no_time * 5;
          if ( $i_am_fork eq "fork" ) {
            print "update_line,$managedname_save,$host_save,$wrkdir,\$update_string,$type_sam,$act_time,$HMC,$IVM,$SDMC,$step,$DEBUG,\@lpar_trans,$last_file,$long_time,$SSH,$hmc_user,$input_vm_uuid,$entity_type,(" . $$ . "F$server_count),$update_string,xorux_sentinel\n";
          }
          else {
            push @all_vcenter_perf_data, "update_line,$managedname_save,$host_save,$wrkdir,\$update_string,$type_sam,$act_time,$HMC,$IVM,$SDMC,$step,$DEBUG,\@lpar_trans,$last_file,$long_time,$SSH,$hmc_user,$input_vm_uuid,$entity_type,(" . $$ . "F$server_count),$update_string,xorux_sentinel\n";
          }

          # third
          $type_sam      = "u";
          $update_string = $tri_update;

          #            $res_update    = LoadDataModuleVMWare::load_data( $managedname_save, $host_save, $wrkdir, \$update_string, $type_sam, $act_time, $HMC, $IVM, $SDMC, $step, $DEBUG, \@lpar_trans, $last_file, $no_time * 5, $SSH, $hmc_user, $input_vm_uuid, $entity_type, "(".$$."F$server_count)" );
          if ( $i_am_fork eq "fork" ) {
            print "update_line,$managedname_save,$host_save,$wrkdir,\$update_string,$type_sam,$act_time,$HMC,$IVM,$SDMC,$step,$DEBUG,\@lpar_trans,$last_file,$long_time,$SSH,$hmc_user,$input_vm_uuid,$entity_type,(" . $$ . "F$server_count),$update_string,xorux_sentinel\n";
          }
          else {
            push @all_vcenter_perf_data, "update_line,$managedname_save,$host_save,$wrkdir,\$update_string,$type_sam,$act_time,$HMC,$IVM,$SDMC,$step,$DEBUG,\@lpar_trans,$last_file,$long_time,$SSH,$hmc_user,$input_vm_uuid,$entity_type,(" . $$ . "F$server_count),$update_string,xorux_sentinel\n";
          }

          # implementing datastore VM read/write IOPS
          # vm_dstr_counter_data,500f3bb6-f151-1c05-92ab-4555a8013a19,591c40de-576c4922-9ce2-e4115bd41b18,178,60,1497974600 1497974620,2,2,0,7,2,1,3,3,2 total 60 numbers
          #          }
          #          else {
          if ($NG) {
            $type_sam = "NG";
            my $long_time = $no_time * 5;
            $update_string = $update_stri_NG;
            if ( $i_am_fork eq "fork" ) {
              print "update_line,$managedname_save,$host_save,$wrkdir,\$update_string,$type_sam,$act_time,$HMC,$IVM,$SDMC,$step,$DEBUG,\@lpar_trans,$last_file,$long_time,$SSH,$hmc_user,$input_vm_uuid,$entity_type,(" . $$ . "F$server_count),$update_string,xorux_sentinel\n";
            }
            else {
              push @all_vcenter_perf_data, "update_line,$managedname_save,$host_save,$wrkdir,\$update_string,$type_sam,$act_time,$HMC,$IVM,$SDMC,$step,$DEBUG,\@lpar_trans,$last_file,$long_time,$SSH,$hmc_user,$input_vm_uuid,$entity_type,(" . $$ . "F$server_count),$update_string,xorux_sentinel\n";
            }

            #          }
          }

          foreach (@dstr_vm_readAveraged) {
            my $long_time = $no_time * 5;
            my $line      = $_;
            chomp $line;

            # print "2964 \$line $line\n";
            # 2964 $line vm_dstr_counter_data,5009fec0-9380-a87a-6808-edd91854f09c,6225ab1d-24200554-7d3d-3ca82a231f18,185,21,1687177220 1687177240,9,10,8,9,7,11,26,11,27,10,10,12,10,3,3,3,4,4,3,3,17
            ( undef, my $vm_uuid, my $dstr_uuid, undef, undef, undef, undef, my $data_read ) = split( ",", $line, 8 );
            if ( !uuid_check($vm_uuid) ) {
              error( "Bad VM uuid ,$vm_uuid,: " . __FILE__ . ":" . __LINE__ ) && next;
            }

            # find respective line from write
            ( my $line_w ) = grep {/$vm_uuid/} @dstr_vm_writAveraged;
            next if !defined $line_w;
            chomp $line_w;
            ( undef, undef, undef, undef, undef, undef, undef, my $data_writ ) = split( ",", $line_w, 8 );

            # print "1824 for dstr $dstr_uuid from VM $vm_uuid readAv $data_read & writAv $data_writ\n";
            $update_string = "";
            my @readAveraged = split( ",", $data_read );
            my @writAveraged = split( ",", $data_writ );
            for ( my $i = 0; $i < $samples_number; $i++ ) {
              next if !defined $readAveraged[$i] || !defined $writAveraged[$i];
              if ( $readAveraged[$i] < 0 ) {
                print "minus detected : \$i $i \$readAveraged $readAveraged[$i] for $dstr_uuid $vm_uuid\n";
                $readAveraged[$i] = "U";
              }
              if ( $writAveraged[$i] < 0 ) {
                print "minus detected : \$i $i \$writAveraged $writAveraged[$i] for $dstr_uuid $vm_uuid\n";
                $writAveraged[$i] = "U";
              }
              next if ( $readAveraged[$i] eq "U" and $writAveraged[$i] ) eq "U";    # not necessary to send to rrd file
              $update_string .= "$vm_time_stamps[$i],$readAveraged[$i],$writAveraged[$i] ";
            }

            # print "1832 for dstr $dstr_uuid from VM $vm_uuid \$update_string $update_string,xorux_sentinel\n";
            $type_sam  = "v";
            $last_file = "";
            my $vm_name = "inoname";
            if ( exists $vcenter_vm_views_hash{$vm_uuid} ) {
              $vm_name = $vcenter_vm_views_hash{$vm_uuid};
            }

            # print "3000 \$vm_uuid $vm_uuid \$vm_name $vm_name\n";
            # in case NG
            # $IVM = $vm_name

            #              $res_update = LoadDataModuleVMWare::load_data( $managedname_save, $host_save, $wrkdir, \$update_string, $type_sam, $act_time, $HMC, $IVM, $SDMC, $step, $DEBUG, \@lpar_trans, $last_file, $no_time * 5, $vm_uuid, $hmc_user, $input_vm_uuid, $entity_type, "(".$$."F$server_count)" );
            if ( $i_am_fork eq "fork" ) {
              print "update_line,$managedname_save,$host_save,$wrkdir,\$update_string,$type_sam,$act_time,$HMC,$IVM,$SDMC,$step,$DEBUG,\@lpar_trans,$last_file,$long_time,$vm_uuid,$hmc_user,$input_vm_uuid,$entity_type,(" . $$ . "F$server_count),$update_string,xorux_sentinel\n";
            }
            else {
              push @all_vcenter_perf_data, "update_line,$managedname_save,$host_save,$wrkdir,\$update_string,$type_sam,$act_time,$HMC,$IVM,$SDMC,$step,$DEBUG,\@lpar_trans,$last_file,$long_time,$vm_uuid,$hmc_user,$input_vm_uuid,$entity_type,(" . $$ . "F$server_count),$update_string,xorux_sentinel\n";
            }
          }
        }
      }

      #         print "LoadDataModuleVMWare::load_data ($managedname_save,$host_save,$wrkdir,\$update_string,$type_sam,$act_time,$HMC,$IVM,$SDMC,$step,$DEBUG,\@lpar_trans,$last_file,$no_time,$SSH,$hmc_user,$input_vm_uuid,$entity_type,(".$$."F$server_count));\n";
      next;    # datastore
    }
    else {     # this is for datastores without real-time data
      print "               : NO VM data for datastore $ds_name\n";
      if ( !$active_VMs ) {

        # write at least basic datastore values
        my $time_a        = time;
        my $update_string = "$time_a,$ds_freeSpace,$ds_used,$ds_provisioned,$ds_capacity";
        if ( ( index( $update_string, '-1,-1,-1' ) < 0 ) && ( index( $update_string, 'U,U,U' ) < 0 ) ) {
          my $input_vm_uuid = $vm_name_uuid{ $entity->name };
          $input_vm_uuid = $entity_uuid;
          $SSH           = "";
          my $managedname_save = $managedname;
          my $host_save        = $host;
          $last_file = "$ds_uuid.last";
          my $type_sam  = "s";
          my $long_time = $no_time * 5;

          #          my $res_update = LoadDataModuleVMWare::load_data( $managedname_save, $host_save, $wrkdir, \$update_string, $type_sam, $act_time, $HMC, $IVM, $SDMC, $step, $DEBUG, \@lpar_trans, $last_file, $no_time * 5, $SSH, $hmc_user, $input_vm_uuid, $entity_type, "(".$$."F$server_count)" );
          if ( $i_am_fork eq "fork" ) {
            print "update_line,$managedname_save,$host_save,$wrkdir,\$update_string,$type_sam,$act_time,$HMC,$IVM,$SDMC,$step,$DEBUG,\@lpar_trans,$last_file,$long_time,$SSH,$hmc_user,$input_vm_uuid,$entity_type,(" . $$ . "F$server_count),$update_string,xorux_sentinel\n";
          }
          else {
            push @all_vcenter_perf_data, "update_line,$managedname_save,$host_save,$wrkdir,\$update_string,$type_sam,$act_time,$HMC,$IVM,$SDMC,$step,$DEBUG,\@lpar_trans,$last_file,$long_time,$SSH,$hmc_user,$input_vm_uuid,$entity_type,(" . $$ . "F$server_count),$update_string,xorux_sentinel\n";
          }
        }
        else {
          print "no update      : datastore $ds_name ($ds_uuid) (" . $$ . "F$server_count)\n";
        }
      }
      else {
        # print "2872 skip prepare_last_time\n";
        prepare_last_time( $datastore, $et_Datastore, $ds_name, $ds_uuid );
      }
    }
  }
}

sub hostsystem_perf {
  $do_fork = "1";
  @returns = ();
  my $model  = "";
  my $serial = "";
  my $line   = "";
  my $hmcv   = "";

  if ( @$managednamelist_un[0] =~ "no address associated with hostname" || @$managednamelist_un[0] =~ "Could not resolve hostname" ) {
    error("vmware : @$managednamelist_un[0]");
    exit(1);
  }

  # sorting non case sensitive - not for vmware
  #  @managednamelist = sort { lc($a) cmp lc($b) } @managednamelist_un;
  my $managednamelist = $managednamelist_un;

  my $managed_ok;
  my $managedname_exl = "";
  my @m_excl          = "";
  my $once            = 0;
  my $hmcv_num        = "";

  my %vm_uuid_names      = ();
  my $vm_uuid_names_file = "$wrkdir/$all_vmware_VMs/$all_vm_uuid_names";
  if ( -f "$vm_uuid_names_file" ) {
    open my $FH, "$vm_uuid_names_file" or error( "can't open $vm_uuid_names_file: $!" . __FILE__ . ":" . __LINE__ ) && return 0;
    while ( my $line = <$FH> ) {
      chomp $line;
      ( my $word1, my $word2 ) = split /,/, $line, 2;
      $vm_uuid_names{$word1} = $word2;
    }
    close $FH;
  }

  # keep orig for tracking if there is a change
  my %vm_uuid_names_orig   = %vm_uuid_names;
  my %vm_uuid_names_append = ();

  my @all_esxi_config               = ();
  my $vcenter_ghz                   = 0;
  my $vcenter_overallCpuUsage_ghz   = 0;
  my $vcenter_memorySize_gb         = 0;
  my $vcenter_overallMemoryUsage_gb = 0;
  my %vcenter_clusters              = ();
  my $vcenter_vms_count             = 0;

  #
###     cycle on $managedname_list (on servers)
  #       get data for all managed systems which are connected to vcenter

  foreach my $vm_host_tmp ( @{ $managednamelist || [] } ) {

    my $host_moref_id = $vm_host_tmp->{'mo_ref'}->value;
    $vm_host = $vm_host_tmp;

    my $change_vm_uuid_names = 0;    # if changes must be saved

    $h_name = $vm_host->get_property('name');
    my $esxi_parent_moref = $vm_host->get_property('parent.value');                                   # domain-cxx
    my $dbi_esxi_uuid     = $vmware_uuid . "_cluster_" . $esxi_parent_moref . "_esxi_" . "$h_name";
    $esxi_dbi_uuid_hash{$host_moref_id} = $dbi_esxi_uuid;

    # print Dumper ("2643",$dbi_esxi_uuid);

    # print "\$h_name $h_name \$vm_host ,$vm_host, pid $$\n";
    $host_moref_name{$host_moref_id} = $h_name;    # later use for convert

    $fail_entity_name = $h_name;
    $fail_entity_type = "Host_System";

    push @managednamelist_vmw, $h_name;
    my $vmx_view = Vim::find_entity_view(
      view_type  => 'HostSystem',
      filter     => { 'name' => "$h_name" },
      properties => [ 'hardware.systemInfo.uuid', 'hardware.memorySize', 'hardware.cpuInfo.hz', 'hardware.systemInfo.vendor', 'hardware.systemInfo.model', 'summary.hardware.cpuModel', 'summary.hardware.numCpuCores', 'summary.hardware.numCpuPkgs', 'summary.hardware.numCpuThreads', 'systemResources.config.cpuAllocation.reservation', 'systemResources.config.cpuAllocation.limit', 'systemResources.config.cpuAllocation.shares.shares', 'parent', 'systemResources.config.memoryAllocation.reservation', 'summary.config.product', 'summary.quickStats.overallCpuUsage', 'summary.quickStats.overallMemoryUsage', 'summary.quickStats.uptime', 'vm' ]
    );

    # print Dumper ("2817",$vmx_view);

    #    my $o_uuid = $vmx_view->get_property('hardware.systemInfo.uuid');
    my $o_uuid = $vmx_view->{'hardware.systemInfo.uuid'};

    #    $host_memorySize = $vmx_view->get_property('hardware.memorySize');
    $host_memorySize = $vmx_view->{'hardware.memorySize'};
    my $host_memorySize_gb = sprintf "%.1f", $host_memorySize / 1024 / 1024 / 1024;

    #    $host_hz         = $vmx_view->get_property('hardware.cpuInfo.hz');
    $host_hz = $vmx_view->{'hardware.cpuInfo.hz'};

    #    $host_cpuAlloc   = $vmx_view->get_property('systemResources.config.cpuAllocation.reservation');
    $host_cpuAlloc = $vmx_view->{'systemResources.config.cpuAllocation.reservation'};

    #    my $host_limit      = $vmx_view->get_property('systemResources.config.cpuAllocation.limit');
    my $host_limit = $vmx_view->{'systemResources.config.cpuAllocation.limit'};

    #    my $host_cpu_shares = $vmx_view->get_property('systemResources.config.cpuAllocation.shares.shares');
    my $host_cpu_shares = $vmx_view->{'systemResources.config.cpuAllocation.shares.shares'};
    my $host_parent     = $vmx_view->{parent};

    #    my $host_memAlloc   = $vmx_view->get_property('systemResources.config.memoryAllocation.reservation');
    my $host_memAlloc = $vmx_view->{'systemResources.config.memoryAllocation.reservation'};

    #    my $hw_vendor        = $vmx_view->get_property('hardware.systemInfo.vendor');
    my $hw_vendor = $vmx_view->{'hardware.systemInfo.vendor'};
    $hw_vendor =~ s/,/./g;

    #    my $hw_model         = $vmx_view->get_property('hardware.systemInfo.model');
    my $hw_model = $vmx_view->{'hardware.systemInfo.model'};
    $hw_model =~ s/,/./g;

    #    my $hw_numCpuPkgs    = $vmx_view->get_property('summary.hardware.numCpuPkgs');
    my $hw_numCpuPkgs = $vmx_view->{'summary.hardware.numCpuPkgs'};

    #    my $hw_cpuModel      = $vmx_view->get_property('summary.hardware.cpuModel');
    my $hw_cpuModel = $vmx_view->{'summary.hardware.cpuModel'};

    #    my $hw_numCpuCores   = $vmx_view->get_property('summary.hardware.numCpuCores');
    my $hw_numCpuCores = $vmx_view->{'summary.hardware.numCpuCores'};

    #    my $hw_numCpuThreads = $vmx_view->get_property('summary.hardware.numCpuThreads');
    my $hw_numCpuThreads = $vmx_view->{'summary.hardware.numCpuThreads'};

    #    my $sw_apiType       = $vmx_view->get_property('summary.config.product.apiType');
    my $sw_apiType = $vmx_view->{'summary.config.product'}->apiType;

    #    my $sw_apiVersion    = $vmx_view->get_property('summary.config.product.apiVersion');
    my $sw_apiVersion = $vmx_view->{'summary.config.product'}->apiVersion;

    #    my $sw_build         = $vmx_view->get_property('summary.config.product.build');
    my $sw_build = $vmx_view->{'summary.config.product'}->build;

    #    my $sw_fullName      = $vmx_view->get_property('summary.config.product.fullName');
    my $sw_fullName = $vmx_view->{'summary.config.product'}->fullName;

    #    my $sw_localeBuild   = $vmx_view->get_property('summary.config.product.localeBuild');
    my $sw_localeBuild = $vmx_view->{'summary.config.product'}->localeBuild;

    #    my $sw_localeVersion = $vmx_view->get_property('summary.config.product.localeVersion');
    my $sw_localeVersion = $vmx_view->{'summary.config.product'}->localeVersion;

    #    my $overallCpuUsage  = $vmx_view->get_property('summary.quickStats.overallCpuUsage');
    my $overallCpuUsage = 0;
    $overallCpuUsage = $vmx_view->{'summary.quickStats.overallCpuUsage'} if exists $vmx_view->{'summary.quickStats.overallCpuUsage'};

    #    my $overallMemoryUsage= $vmx_view->get_property('summary.quickStats.overallMemoryUsage');
    my $overallMemoryUsage = 0;
    $overallMemoryUsage = $vmx_view->{'summary.quickStats.overallMemoryUsage'} if exists $vmx_view->{'summary.quickStats.overallMemoryUsage'};

    #    my $esxi_uptime_days = sprintf "%.1f",$vmx_view->get_property('summary.quickStats.uptime')/86400;
    my $esxi_uptime_days_orig = 0;
    $esxi_uptime_days_orig = $vmx_view->{'summary.quickStats.uptime'} if exists $vmx_view->{'summary.quickStats.uptime'};
    my $esxi_uptime_days = sprintf "%.1f", $esxi_uptime_days_orig / 86400;

    my $host_ghz              = sprintf "%.1f", $host_hz / 1000 / 1000 / 1000 * $hw_numCpuCores;
    my $overallCpuUsage_ghz   = sprintf "%.1f", $overallCpuUsage / 1000;
    my $overallMemoryUsage_gb = sprintf "%.1f", $overallMemoryUsage / 1024;

    my $esxi_parent_name = "";                               # will be found later
    my $host_name        = $vm_host->get_property('name');

    # push @all_esxi_config,"$host_name,$h_name,$host_memorySize,$host_hz,$host_parent,$hw_vendor,$hw_model,$hw_cpuModel,$hw_numCpuCores,$hw_numCpuThreads,$sw_apiVersion,$sw_build,$sw_fullName,$sw_localeBuild,$sw_localeVersion,$overallCpuUsage,$overallMemoryUsage,$esxi_uptime,$esxi_parent_name";

    # print "1926 vmw2rrd.pl \$hw_vendor $hw_vendor \$hw_model $hw_model \$hw_cpuModel $hw_cpuModel \$hw_numCpuCores $hw_numCpuCores \$hw_numCpuPkgs $hw_numCpuPkgs \$hw_numCpuThreads $hw_numCpuThreads\n";
    # print "1927 vmw2rrd.pl \$o_uuid $o_uuid \$host_hz $host_hz\n";

    $line = "$host_name,$host_name," . $vm_host->get_property('hardware.systemInfo.uuid');

    chomp($line);

    if ( $line =~ m/Error:/ || $line =~ m/Permission denied/ ) {
      error( "problem connecting to $vm_host : $line " . __FILE__ . ":" . __LINE__ );
      next;
    }

    if ( $line !~ ".*,.*,.*" ) {

      # it must look like : PWR6A-9117-MMA-SN103A4B0,9117-MMA,103A4B0, --> exclude banners
      next;
    }

    if ( $line =~ /No results were found/ ) {
      print "$host does not contain any managed system\n" if $DEBUG;
      return 0;
    }
    ( $managedname, $model, $serial ) = split( /,/, $line );

    # in case more standalone ESXi servers have same managedname
    if ( defined $ENV{VMWARE_SAME_STANDALONE_ESXI_NAMES} && $apiType_top =~ 'HostAgent' ) {
      $managedname = $managedname . "-" . $alias;
    }

    print "managed system : $host:$managedname (serial : $serial) ,$sw_apiType ,$sw_apiVersion ,$sw_build ,$sw_fullName ,$sw_localeBuild ,$sw_localeVersion\n" if $DEBUG;

    #  rename_server($host,$managedname,$model,$serial);  # this is for IBM servers
    rename_server( $host, $managedname, $serial );    # this is for VMWARE servers, serial is uuid

    # create sym link serial for recognizing of renamed managed systems
    # it must be here due to skipping some server (exclude, not running util collection) and saving cfg
    if ( !-d "$wrkdir" ) {
      print "mkdir          : $host:$managedname $wrkdir\n" if $DEBUG;
      LoadDataModuleVMWare::touch("$host:$managedname $wrkdir");
      mkdir( "$wrkdir", 0755 ) || error( " Cannot mkdir $wrkdir: $!" . __FILE__ . ":" . __LINE__ ) && next;
    }

    # new system all VMs in one dir
    # it also holds file uuid->name of VMs

    if ( !-d "$wrkdir/vmware_VMs" ) {
      print "mkdir          : $host: $wrkdir/$all_vmware_VMs\n" if $DEBUG;
      LoadDataModuleVMWare::touch("$wrkdir/$all_vmware_VMs");
      mkdir( "$wrkdir/$all_vmware_VMs", 0755 ) || error( " Cannot mkdir $wrkdir/$all_vmware_VMs: $!" . __FILE__ . ":" . __LINE__ ) && next;
    }
    else {
      # remove *.last files from this dir as they are not needed anymore
      unlink glob "$wrkdir/vmware_VMs/*.last";
    }

    if ( !-d "$wrkdir/$managedname" ) {
      print "mkdir          : $host:$managedname $wrkdir/$managedname\n" if $DEBUG;
      LoadDataModuleVMWare::touch("$wrkdir/$managedname");
      mkdir( "$wrkdir/$managedname", 0755 ) || error( " Cannot mkdir $wrkdir/$managedname: $!" . __FILE__ . ":" . __LINE__ ) && next;
    }

    if ( !-l "$wrkdir/$serial" ) {    # uuid only
      print "ln -s          : $host:$managedname $wrkdir/$managedname $wrkdir/$serial \n" if $DEBUG;
      LoadDataModuleVMWare::touch("$wrkdir/$serial");
      symlink( "$wrkdir/$managedname", "$wrkdir/$serial" ) || error( " Cannot ln -s $wrkdir/$managedname $wrkdir/$serial: $!" . __FILE__ . ":" . __LINE__ ) && next;
    }

    if ( !-d "$wrkdir/$managedname/$host" ) {
      print "mkdir          : $host:$managedname $wrkdir/$managedname/$host\n" if $DEBUG;
      LoadDataModuleVMWare::touch("$wrkdir/$managedname/$host");
      mkdir( "$wrkdir/$managedname/$host", 0755 ) || error( " Cannot mkdir $wrkdir/$managedname/$host: $!" . __FILE__ . ":" . __LINE__ ) && next;
    }
    unlink bsd_glob "$wrkdir/$managedname/$host/host_moref_id.*";
    `touch "$wrkdir/$managedname/$host/host_moref_id.$host_moref_id"`;

    my $vmware_signal_file = "$wrkdir/$managedname/$host/vmware.txt";
    if ( !-f "$vmware_signal_file" ) {
      `touch "$vmware_signal_file"`;    # say install_html.sh that it is vmware
      LoadDataModuleVMWare::touch("$wrkdir/$managedname/$host/vmware.txt");
    }

    unlink "$wrkdir/$managedname/$host/im_in_cluster";    # if left from last load

    # server must know its alias if non vCenter
    if ( $apiType_top !~ "VirtualCenter" ) {
      my $my_alias_file_name = "$wrkdir/$managedname/$host/vmware_alias_name";
      my $alias_name         = "";
      if ( -f $my_alias_file_name ) {
        open my $FH, "$my_alias_file_name" or error( "can't open $my_alias_file_name: $!" . __FILE__ . ":" . __LINE__ );
        $alias_name = <$FH>;
        chomp $alias_name;
        close $FH;
      }
      if ( $alias_name eq "" || $alias_name ne "$host|$alias" ) {
        open my $FH, ">$my_alias_file_name" or error( "can't open $my_alias_file_name: $!" . __FILE__ . ":" . __LINE__ );
        print $FH "$host|$alias\n";    # save host name and alias
        close $FH;
        LoadDataModuleVMWare::touch("$my_alias_file_name");
      }

      # this is very improbable but ...
      if ( -f "$wrkdir/$managedname/$host/my_vcenter_name" ) {
        unlink "$wrkdir/$managedname/$host/my_vcenter_name";
        LoadDataModuleVMWare::touch("$wrkdir/$managedname/$host/my_vcenter_name");
      }
      if ( -f "$wrkdir/$managedname/$host/my_cluster_name" ) {
        unlink "$wrkdir/$managedname/$host/my_cluster_name";
        LoadDataModuleVMWare::touch("$wrkdir/$managedname/$host/my_cluster_name");
      }
    }
    else {
      # server must know its vcenter name
      my $my_vcenter_file_name = "$wrkdir/$managedname/$host/my_vcenter_name";
      my $vcenter_name         = "";
      if ( -f $my_vcenter_file_name ) {
        open my $FH, "$my_vcenter_file_name" or error( "can't open $my_vcenter_file_name: $!" . __FILE__ . ":" . __LINE__ );
        $vcenter_name = <$FH>;
        chomp $vcenter_name;
        close $FH;
      }
      if ( $vcenter_name eq "" || $vcenter_name ne "$host|$alias|$vmware_uuid" ) {
        open my $FH, ">$my_vcenter_file_name" or error( "can't open $my_vcenter_file_name: $!" . __FILE__ . ":" . __LINE__ );
        print $FH "$host|$alias|$vmware_uuid\n";    # save host name and alias
        close $FH;
        LoadDataModuleVMWare::touch("$my_vcenter_file_name");
        print "\$host|\$alias\$vmware_uuid $host|$alias|$vmware_uuid\n";
      }

      # this is very improbable but ...
      if ( -f "$wrkdir/$managedname/$host/vmware_alias_name" ) {
        unlink "$wrkdir/$managedname/$host/vmware_alias_name";
        LoadDataModuleVMWare::touch("$wrkdir/$managedname/$host/vmware_alias_name");
      }

      # prepare for situation when ESXi is removed from cluster
      if ( -f "$wrkdir/$managedname/$host/my_cluster_name" ) {
        `touch "$wrkdir/$managedname/$host/im_in_cluster"`;
        open my $FH, "$wrkdir/$managedname/$host/my_cluster_name" or error( "can't open $wrkdir/$managedname/$host/my_cluster_name: $!" . __FILE__ . ":" . __LINE__ );
        $esxi_parent_name = <$FH>;
        close $FH;
        chomp $esxi_parent_name;
        $esxi_parent_name =~ s/^cluster_//;
      }
    }

    $managed_ok = 1;
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
      save_cfg_data( $managedname, localtime(), $upgrade );    # it is necessary to have all server in cfg page
      next;
    }

    # Check whether utilization data collection is enabled
    # what about maintenanceMode ??

    # get uuid, name and other config params of VM for lpar_trans.txt

    # VM uptime Seconds is in 'summary.quickStats.uptimeSeconds'
    # updated once in a minute

    my @lpar_trans        = ();    # original array
    my @lpar_trans_new    = ();    # if there is new VM
    my @lpar_trans_renew  = ();    # if there is change in orig arr
    my $lpar_trans_change = 0;

    # lpar_trans.txt keeps names of all VMS that anytime has/had been registered under this server
    my $lpar_trans_name = "$wrkdir/$managedname/$host/lpar_trans.txt";
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
    VM_hosting_read( \@hosting_arr, "$wrkdir/$managedname/$host/VM_hosting.vmh" );

    %vm_name_uuid  = ();
    %vm_moref_uuid = ();
    my @cpu_cfg     = ();
    my @cpu_cfg_csv = ();    # save for other use (advisor ...)
    my @disk_cfg    = ();

    #architecture
    my @rdm_architecture = ();

    my $esxi_vm_moref_list = $vmx_view->{'vm'};

    foreach my $each_vmm (@$esxi_vm_moref_list) {
      my $vm_moref = $each_vmm->{'value'};

      # my $name = $vcenter_vm_views_hash{$vm_moref}->{'name'};
      # my $name = $vcenter_vm_views_hash{$vm_moref}{'name'};
      # print "3425 $vm_moref $name\n";
      my $each_vm = $vcenter_vm_views_hash{$vm_moref};

      # $name = $each_vm->{'name'};
      # print "3432 $vm_moref $name\n";

      #  new lpar will be added to lpar_trans.txt
      my $each_vm_uuid     = $each_vm->{'summary.config.instanceUuid'};
      my $each_vm_uuid_old = $each_vm->{'summary.config.uuid'};

      my $vm_mo_ref_id = $each_vm->{'mo_ref'}->value;
      my $each_vm_name = $each_vm->{'name'};
      if ( !defined $vm_mo_ref_id ) {
        error( "VM change ID   : not defined mo_ref for VM $each_vm_name " . __FILE__ . ":" . __LINE__ ) && next;
      }
      $vm_moref_uuid{$vm_mo_ref_id} = $each_vm_uuid;    # filling

      # vm to exclude
      next if exclude_vm( $each_vm_name, "print" );

      # remove comma ',' because we use it as field separator
      if ( index( $each_vm_name, "," ) > 0 ) {
        print "VM name        : $each_vm_name contains comma , which has been removed\n";
        $each_vm_name =~ s/,//g;
      }
      my $each_vm_url = $each_vm_name;

      if ( !defined $each_vm_name || $each_vm_name eq "" ) {
        error( "Bad VM name in $wrkdir/$managedname/$host: $!" . __FILE__ . ":" . __LINE__ ) && next;
      }

      # if necessary to include orphaned VMs into ESXi configuration table

      #      my $powerstate = $each_vm->{'runtime.powerState'}->{val};
      #
      #      my $sh_level = $each_vm->{'config.cpuAllocation.shares.level'}->{val};
      #      print STDERR "2300 uninitialised $each_vm_name summary.config.numCpu\n" if !defined $each_vm->{'summary.config.numCpu'};
      #      print STDERR "2300 uninitialised $each_vm_name config.cpuAllocation.reservation\n" if !defined $each_vm->{'config.cpuAllocation.reservation'};
      #      print STDERR "2300 uninitialised $each_vm_name config.cpuAllocation.limit\n" if !defined $each_vm->{'config.cpuAllocation.limit'};
      #      print STDERR "2300 uninitialised $each_vm_name config.cpuAllocation.shares.shares\n" if !defined $each_vm->{'config.cpuAllocation.shares.shares'};
      #      print STDERR "2300 uninitialised $each_vm_name summary.config.guestFullName\n" if !defined $each_vm->{'summary.config.guestFullName'};
      #      my $tools_status = "undefined";
      #      $tools_status = $each_vm->{'guest.toolsRunningStatus'} if defined $each_vm->{'guest.toolsRunningStatus'};
      #
      #      my $vm_parent_folder = "undefined";
      #      $vm_parent_folder    = $each_vm->{'parent'} if defined $each_vm->{'parent'};
      #      my $vm_parent_folder_moref = "moref";
      #      $vm_parent_folder_moref    = $vm_parent_folder->value if $vm_parent_folder ne "undefined";
      #
      #      my $line = $each_vm_name . "," . $each_vm->{'summary.config.numCpu'} . "," . $each_vm->{'config.cpuAllocation.reservation'} . "," . $each_vm->{'config.cpuAllocation.limit'} . "," . $sh_level . "," . $each_vm->{'config.cpuAllocation.shares.shares'} . "," . $each_vm->{'summary.config.guestFullName'} . "," . $powerstate . "," . $tools_status;
      #      push @cpu_cfg, "$line\n";
      #      my $each_vm_uuid_now = "";
      #      $each_vm_uuid_now = $each_vm_uuid if defined $each_vm_uuid;
      #      $line .= ",$each_vm_uuid_now," . $each_vm->{'summary.config.memorySizeMB'} .",".$vm_parent_folder_moref. "\n";
      #      push @cpu_cfg_csv, $line;
      #
      #      my $storage_com   = sprintf( "%.1f", ( ( $each_vm->{'summary.storage.committed'} ) / 1024 / 1024 / 1024 ) );
      #      my $storage_uncom = sprintf( "%.1f", ( ( $each_vm->{'summary.storage.uncommitted'} ) / 1024 / 1024 / 1024 ) );
      #      my $storage_total = sprintf( "%.1f", $storage_com + $storage_uncom );
      #      $line = "$each_vm_name,$storage_total,$storage_com\n";
      #      push @disk_cfg, $line;

      if ( !defined $each_vm_uuid ) {
        error( "Not defined VM uuid in $wrkdir/$managedname/$host: VM name:$each_vm_name " . __FILE__ . ":" . __LINE__ ) && next;
      }
      if ( $each_vm_uuid eq 'UNSET' ) {
        error( "UNSET VM uuid in $wrkdir/$managedname/$host: VM name:$each_vm_name " . __FILE__ . ":" . __LINE__ ) && next;
      }
      if ( !uuid_check($each_vm_uuid) ) {
        error( "Bad VM uuid ($each_vm_uuid) in $wrkdir/$managedname/$host: VM name:$each_vm_name " . __FILE__ . ":" . __LINE__ ) && next;
      }

      # for new system, do not test possible uuid collision
      # prepare url name for install-html.sh
      $each_vm_url =~ s/([^A-Za-z0-9\+-_])/sprintf("%%%02X", ord($1))/seg;
      my $new_item = "$each_vm_name" . "," . "$each_vm_url" . "," . "$each_vm_uuid_old";
      if ( !defined $vm_uuid_names{$each_vm_uuid} ) {    # new VM
        $vm_uuid_names{$each_vm_uuid} = $new_item;
        $change_vm_uuid_names++;
        $vm_uuid_names_append{$each_vm_uuid} = $new_item;
      }

      # elsif ( $vm_uuid_names{$each_vm_uuid} ne $new_item ) left_curly    # is it renamed VM ? or added new info e.g. old uuid since 5.01-3
      elsif ( index( $vm_uuid_names{$each_vm_uuid}, $new_item ) == -1 ) {    # is it renamed VM ? or added new info e.g. old uuid since 5.01-3
                                                                             # try to compare url version of name
                                                                             #  ( undef, my $substr_url ) = split( ",", $vm_uuid_names{$each_vm_uuid} );
                                                                             #  if ( $substr_url ne $each_vm_url ) {
        $vm_uuid_names{$each_vm_uuid} = $new_item;
        $change_vm_uuid_names++;
        $vm_uuid_names_append{$each_vm_uuid} = $new_item;                    # not solved if VM is renamed, must be special routine after whole VMWARE load (reduce_vm_names.pl)
                                                                             # print "this string ,$substr_url, differs from ,$each_vm_url,\n";
                                                                             #  } ## end if ( $substr_url ne $each_vm_url)
      }

      VM_hosting_update( \@hosting_arr, $each_vm_uuid, $command_unix );

      my $line_test = $each_vm_uuid;                                         # do not know if with or without name

      if ( ( defined $line_test ) && ( !uuid_check($line_test) ) ) {
        if ( defined $each_vm_name ) {
          error( "Bad VM uuid for VM:$each_vm_name in $wrkdir/$managedname/$host: $!" . __FILE__ . ":" . __LINE__ ) && next;
        }
        else {
          error( "Bad VM uuid, undef Name in $wrkdir/$managedname/$host: $!" . __FILE__ . ":" . __LINE__ ) && next;
        }
      }
      if ( !defined $line_test ) {
        if ( defined $each_vm_name ) {
          error( "Undefined VM uuid for VM:$each_vm_name in $wrkdir/$managedname/$host: $!" . __FILE__ . ":" . __LINE__ ) && next;
        }
        else {
          error( "Undefined VM uuid nor Name in $wrkdir/$managedname/$host: $!" . __FILE__ . ":" . __LINE__ ) && next;
        }
      }
      if ( !defined $each_vm_name ) {
        error( "Undefined VM name in $wrkdir/$managedname/$host: $!" . __FILE__ . ":" . __LINE__ ) && next;
      }
      my $vm_uuid  = $line_test;
      my $line_upd = $line_test . "," . $each_vm_name;

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

      #      print "----------------------------- ".$each_vm->{'summary.config.instanceUuid'}.",".$each_vm->{'name'}.",".$each_vm->{'mo_ref'}->value."\n";
      #      print FH $each_vm->{'summary.config.instanceUuid'}."_cpuAllocReservation,".$each_vm->{'config.cpuAllocation.reservation'}."\n";
      #      print FH $each_vm->{'summary.config.instanceUuid'}."_cpuInfo_hz,".$host_hz."\n";

      $vm_name_uuid{"$each_vm_name"} = "$line_test";

      my $powerstate = $each_vm->{'runtime.powerState'}->{val};

      my $sh_level = $each_vm->{'config.cpuAllocation.shares.level'}->{val};
      print STDERR "2300 uninitialised $each_vm_name summary.config.numCpu\n"              if !defined $each_vm->{'summary.config.numCpu'};
      print STDERR "2300 uninitialised $each_vm_name config.cpuAllocation.reservation\n"   if !defined $each_vm->{'config.cpuAllocation.reservation'};
      print STDERR "2300 uninitialised $each_vm_name config.cpuAllocation.limit\n"         if !defined $each_vm->{'config.cpuAllocation.limit'};
      print STDERR "2300 uninitialised $each_vm_name config.cpuAllocation.shares.shares\n" if !defined $each_vm->{'config.cpuAllocation.shares.shares'};
      print STDERR "2300 uninitialised $each_vm_name summary.config.guestFullName\n"       if !defined $each_vm->{'summary.config.guestFullName'};

      my $tools_status = "undefined";
      $tools_status = $each_vm->{'guest.toolsRunningStatus'} if defined $each_vm->{'guest.toolsRunningStatus'};

      my $guestFullName = "undefined";
      $guestFullName = $each_vm->{'summary.config.guestFullName'} if defined $each_vm->{'summary.config.guestFullName'};
      if ( $guestFullName ne "undefined" ) {
        if ( $tools_status eq "guestToolsRunning" ) {
          my $guest_full_name = "undefined";
          $guest_full_name = $each_vm->{'summary.guest.guestFullName'} if defined $each_vm->{'summary.guest.guestFullName'};

          # print "3490 $each_vm_name \$guestFullName $guestFullName ".length($guestFullName)." \$guest_full_name $guest_full_name ".length($guest_full_name)."\n";
          #print "3490 $each_vm_name old:$guestFullName ".length($guestFullName)." new:$guest_full_name ".length($guest_full_name)."\n";
          # if (length($guest_full_name) > length($guestFullName)) {
          $guestFullName = $guest_full_name if $guest_full_name ne "undefined" && $guest_full_name ne "";

          # }
        }
      }

      my $vm_ipaddress = "undefined";
      $vm_ipaddress = $each_vm->{'guest.ipAddress'} if defined $each_vm->{'guest.ipAddress'};

      # https://vdc-download.vmware.com/vmwb-repository/dcr-public/98d63b35-d822-47fe-a87a-ddefd469df06/2e3c7b58-f2bd-486e-8bb1-a75eb0640bee/doc/vim.vm.Summary.StorageSummary.html
      my $storage_com   = sprintf( "%.1f", ( ( $each_vm->{'summary.storage.committed'} ) / 1024 / 1024 / 1024 ) );
      my $storage_uncom = sprintf( "%.1f", ( ( $each_vm->{'summary.storage.uncommitted'} ) / 1024 / 1024 / 1024 ) );
      my $storage_total = sprintf( "%.1f", $storage_com + $storage_uncom );
      $line = "$each_vm_name,$storage_total,$storage_com\n";
      push @disk_cfg, $line;

      # https://vdc-repo.vmware.com/vmwb-repository/dcr-public/fa5d1ee7-fad5-4ebf-b150-bdcef1d38d35/a5e46da1-9b96-4f0c-a1d0-7b8f3ebfd4f5/doc/vim.vm.StorageInfo.UsageOnDatastore.html
      # not used yet
      #my $perDatastoreUsage = "undefined";
      #$perDatastoreUsage = $each_vm->{'storage.perDatastoreUsage'} if defined $each_vm->{'storage.perDatastoreUsage'};
      # print Dumper \$perDatastoreUsage;

      my $vm_parent_folder = "undefined";
      $vm_parent_folder = $each_vm->{'parent'} if defined $each_vm->{'parent'};
      my $vm_parent_folder_moref = "moref";
      $vm_parent_folder_moref = $vm_parent_folder->value if $vm_parent_folder ne "undefined";

      ### !!! Attention! lines in cpu.csv & cpu.html are different
      #      my $line = $each_vm_name . "," . $each_vm->{'summary.config.numCpu'} . "," . $each_vm->{'config.cpuAllocation.reservation'} . "," . $each_vm->{'config.cpuAllocation.limit'} . "," . $sh_level . "," . $each_vm->{'config.cpuAllocation.shares.shares'} . "," . $storage_total . "," . $storage_com . "," . $vm_ipaddress . "," . $powerstate . "," . $tools_status . "," . $each_vm->{'summary.config.guestFullName'};
      my $line = $each_vm_name . "," . $each_vm->{'summary.config.numCpu'} . "," . $each_vm->{'config.cpuAllocation.reservation'} . "," . $each_vm->{'config.cpuAllocation.limit'} . "," . $sh_level . "," . $each_vm->{'config.cpuAllocation.shares.shares'} . "," . $storage_total . "," . $storage_com . "," . $vm_ipaddress . "," . $powerstate . "," . $tools_status . "," . $guestFullName;
      push @cpu_cfg, "$line\n";

      # $line .= ",$each_vm_uuid," . $each_vm->{'summary.config.memorySizeMB'} . "," . $vm_parent_folder_moref . "\n";
      $line = $each_vm_name . "," . $each_vm->{'summary.config.numCpu'} . "," . $each_vm->{'config.cpuAllocation.reservation'} . "," . $each_vm->{'config.cpuAllocation.limit'} . "," . $sh_level . "," . $each_vm->{'config.cpuAllocation.shares.shares'} . "," . $vm_ipaddress . "," . $powerstate . "," . $tools_status . "," . $guestFullName . "," . $each_vm_uuid . "," . $each_vm->{'summary.config.memorySizeMB'} . "," . $vm_parent_folder_moref . "\n";
      push @cpu_cfg_csv, $line;

      # prepare hash for easy VM pick up (resourcepool)
      $vm_id_path{"$vm_mo_ref_id"} = "$wrkdir/$h_name/$host/$vm_uuid.rrm";

      # print "filling vm_id_path{\"$vm_mo_ref_id\"} = \"$wrkdir/$h_name/$host/$vm_uuid.rrm\n";

      # get RDM VirtualDiskRawDiskMappingVer1BackingInfo
      my $each_vm_config_hardware = $each_vm->{'config.hardware'};

      # print Dumper("3592",$each_vm_config_hardware);
      my $each_vm_config_hardware_device = $each_vm_config_hardware->{'device'};

      # print Dumper("3594",$each_vm_config_hardware_device);
      foreach my $device (@$each_vm_config_hardware_device) {

        # print Dumper("3596",$device);
        if ( exists $device->{'backing'} ) {
          my $device_backing = $device->{'backing'};

          # print Dumper("3596",$device_backing);
          if ( exists $device_backing->{'lunUuid'} ) {
            my $device_backing_lunUuid = $device_backing->{'lunUuid'};

            #print Dumper("3602",$device_backing_lunUuid);
            my %vm_rdm_info = (
              "vm_id"           => $each_vm_uuid,
              "vm_name"         => $each_vm_name,
              "lunUuid"         => $device_backing_lunUuid,
              "fileName"        => $device_backing->{'fileName'},
              "capacityInBytes" => $device->{'capacityInBytes'}
            );
            push( @rdm_architecture, \%vm_rdm_info );
          }
        }
      }
    }
    my $file_to_save_arch = "$tmpdir/arch_rdm_" . "$managedname" . "_" . "$host" . "_devices.json";

    # print "1400 $file_to_save_arch\n";
    if ( !Xorux_lib::write_json( $file_to_save_arch, \@rdm_architecture ) ) {
      error( "Cannot save $file_to_save_arch: " . __FILE__ . ":" . __LINE__ );
    }

    # for new system, if change in VM then save
    if ($change_vm_uuid_names) {
      open my $FH, ">>$vm_uuid_names_file" or error( "can't open $vm_uuid_names_file: $!" . __FILE__ . ":" . __LINE__ ) && return 0;
      binmode( $FH, ":utf8" );
      my ( $k, $v );
      my $ind = 0;

      # Append key/value pairs from %vm_uuid_names to file, joined by ','
      while ( ( $k, $v ) = each %vm_uuid_names_append ) {
        print $FH "$k" . "," . "$v\n";
        $ind++;
      }
      close $FH;
      print "all_vm_uuid    : total $ind VMs has/have been appended from ESXi $managedname\n";

      # print Dumper (%vm_uuid_names_append);
      %vm_uuid_names_append = ();
    }

    VM_hosting_write( \@hosting_arr, "$wrkdir/$managedname/$host/VM_hosting.vmh", $command_unix );

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

    # fill the esxi config table
    if ( $esxi_parent_name eq "" ) {
      $esxi_parent_name = "|$alias";
    }
    else {
      if ( exists $vcenter_clusters{$esxi_parent_name} ) {
        $vcenter_clusters{$esxi_parent_name} += scalar @cpu_cfg;
      }
      else {
        $vcenter_clusters{$esxi_parent_name} = scalar @cpu_cfg;
      }
    }
    ( my $vcente_name, my $cluste_name ) = split /\|/, $esxi_parent_name;
    $vcente_name = "" if not defined $vcente_name;
    $cluste_name = "" if not defined $cluste_name;
    push @all_esxi_config, "$cluste_name,$vcente_name,$host_name,$host_ghz,$overallCpuUsage_ghz,$host_memorySize_gb,$overallMemoryUsage_gb,$hw_numCpuCores,$hw_numCpuThreads,$sw_fullName,$esxi_uptime_days,$hw_vendor,$hw_model,$hw_cpuModel";

    # print "3315 \$vcente_name $cluste_name \$cluste_name $vcente_name \$managedname $managedname \$host $host\n";
    $vcenter_ghz                   += $host_ghz;
    $vcenter_overallCpuUsage_ghz   += $overallCpuUsage_ghz;
    $vcenter_memorySize_gb         += $host_memorySize_gb;
    $vcenter_overallMemoryUsage_gb += $overallMemoryUsage_gb;

    my $res_ret = FormatResults( \@cpu_cfg );

    # $vcenter_vms_count += scalar @cpu_cfg;

    # print "\$res_ret $res_ret\n";
    open my $FHx, '>:encoding(UTF-8)', "$wrkdir/$managedname/$host/cpu.html" or error( "can't open '$wrkdir/$managedname/$host/cpu.html': $!" . __FILE__ . ":" . __LINE__ ) && return 0;
    binmode( $FHx, ":utf8" );
    print $FHx "<CENTER><TABLE class=\"tabconfig tablesorter\"><thead><TR>
<TH class=\"sortable\" valign=\"center\">VM</TH>
<TH align=\"center\" class=\"sortable\" valign=\"center\">vCPU</TH>
<TH align=\"center\" class=\"sortable\" valign=\"center\">Reserved MHz</TH>
<TH align=\"center\" class=\"sortable\" valign=\"center\">Limit MHz</TH>
<TH align=\"center\" class=\"sortable\" valign=\"center\">Shares</TH>
<TH align=\"center\" class=\"sortable\" valign=\"center\">Shares value</TH>
<TH align=\"center\" class=\"sortable\" valign=\"center\">Provisioned Space GB</TH>
<TH align=\"center\" class=\"sortable\" valign=\"center\">Used Space GB</TH>
<TH align=\"center\" class=\"sortable\" valign=\"center\">IpAddress</TH>
<TH align=\"center\" class=\"sortable\" valign=\"center\">powerState</TH>
<TH align=\"center\" class=\"sortable\" valign=\"center\">toolsStatus</TH>
<TH align=\"center\" class=\"sortable\" valign=\"center\">OS</TH>
</TR></thead><tbody>\n";
    print $FHx "$res_ret";
    print $FHx "</tbody></TABLE></CENTER>\n";
    close $FHx;

    # save for other use
    open my $FHy, '>:encoding(UTF-8)', "$wrkdir/$managedname/$host/cpu.csv" or error( "can't open '$wrkdir/$managedname/$host/cpu.csv': $!" . __FILE__ . ":" . __LINE__ ) && return 0;
    binmode( $FHy, ":utf8" );
    foreach (@cpu_cfg_csv) {
      print $FHy "$_";
    }
    close $FHy;

    #prepare disk config file for host config
    $res_ret = FormatResults( \@disk_cfg, "right" );
    open my $FHz, '>:encoding(UTF-8)', "$wrkdir/$managedname/$host/disk.html" or error( "can't open '$wrkdir/$managedname/$host/disk.html': $!" . __FILE__ . ":" . __LINE__ ) && return 0;
    print $FHz "<BR><CENTER><TABLE class=\"tabconfig tablesorter\">\n";
    print $FHz "<thead><TR> <TH class=\"sortable\" valign=\"center\">VM&nbsp;&nbsp;&nbsp;&nbsp;</TH>
						<TH align=\"center\" class=\"sortable\" valign=\"right\">&nbsp;&nbsp;&nbsp;Provisioned Space GB&nbsp;&nbsp;&nbsp;</TH>
						<TH align=\"center\" class=\"sortable\" valign=\"right\">&nbsp;&nbsp;&nbsp;Used Space GB&nbsp;&nbsp;&nbsp;</TH>
			</TR></thead><tbody>\n";
    print $FHz "$res_ret";
    print $FHz "</tbody></TABLE></CENTER><BR><BR>\n";
    close $FHz;

    #prepare host config file
    #for Host CPU
    my $cpu_res    = $host_cpuAlloc;
    my $cpu_shares = $host_cpu_shares;
    my $comp_res   = $host_parent;

    #print Dumper($comp_res);

    my $comp_res_w = Vim::find_entity_view( view_type => 'ComputeResource', begin_entity => $comp_res, properties => ['resourcePool'] );

    # print Dumper($comp_res_w);
    my $res_pool = $comp_res_w->resourcePool;

    #print Dumper($res_pool);

    my $res_pool_w = Vim::find_entity_view( view_type => 'ResourcePool', begin_entity => $res_pool, properties => ['runtime'] );

    #    my $res_pool_w = Vim::find_entity_views(view_type => 'ResourcePool',begin_entity=>$res_pool,properties=>['runtime']);
    # print Dumper($res_pool_w);
    my $maxUsage             = $res_pool_w->runtime->cpu->maxUsage;
    my $reservationUsed      = $res_pool_w->runtime->cpu->reservationUsed;
    my $unreservedForPool    = $res_pool_w->runtime->cpu->unreservedForPool;
    my $reservationUsedForVm = $res_pool_w->runtime->cpu->reservationUsedForVm;
    my $unreservedForVm      = $res_pool_w->runtime->cpu->unreservedForVm;

    #    if (($reservationUsed + $unreservedForPool) != ($reservationUsedForVm + $unreservedForVm)) {
    #      error("diff in ha-root-pool cpu, maybe expandable pool? ".__FILE__.":".__LINE__)
    #    }

    my $l_info1 = "InfO maxUsage reservationUsed unreservedForPool reservationUsedForVm unreservedForVm cpu_res cpu_shares hw_numCpuThreads host_limit\n";
    my $l_info2 = "CPU $maxUsage $reservationUsed $unreservedForPool $reservationUsedForVm $unreservedForVm $cpu_res $cpu_shares $hw_numCpuThreads $host_limit\n";

    # print "\$maxUsage $maxUsage $reservationUsed $unreservedForPool\n";
    # print "\$refreshRate $refreshRate \$cpu_res $cpu_res \$cpu_shares $cpu_shares\n";

    #for Host MEM
    my $mem_res = $host_memAlloc;

    $maxUsage             = $res_pool_w->runtime->memory->maxUsage / 1024 / 1024;
    $reservationUsed      = $res_pool_w->runtime->memory->reservationUsed / 1024 / 1024;
    $unreservedForPool    = $res_pool_w->runtime->memory->unreservedForPool / 1024 / 1024;
    $reservationUsedForVm = $res_pool_w->runtime->memory->reservationUsedForVm / 1024 / 1024;
    $unreservedForVm      = $res_pool_w->runtime->memory->unreservedForVm / 1024 / 1024;

    #    if (($reservationUsed + $unreservedForPool) != ($reservationUsedForVm + $unreservedForVm)) {
    #      error("diff in ha-root-pool mem, maybe expandable pool? ".__FILE__.":".__LINE__);
    #    }

    my $l_info3 = "MEM $maxUsage $reservationUsed $unreservedForPool $reservationUsedForVm $unreservedForVm\n";

    # print "\$maxUsage $maxUsage $reservationUsed $unreservedForPool\n";
    # print "\$refreshRate $refreshRate \$cpu_res $cpu_res \$mem_res $mem_res\n";
    #print "after writing lpar_trans.txt $step != $STEP\n";

    # following has sense only for vmware = only one ESXi
    open my $FHost, ">$wrkdir/$managedname/$host/host.cfg" or error( "can't open '$wrkdir/$managedname/$host/host.cfg': $!" . __FILE__ . ":" . __LINE__ ) && return 0;
    print $FHost "$l_info1$l_info2$l_info3";
    close $FHost;

    $step = $STEP;    # do not know if vmware will have sometimes other value
    if ( $step != $STEP ) {
      print "*****WARNING*****WARNING*****WARNING*****\n";
      if ( $step == 0 ) {
        print "Utilization data collection is disabled for managed system : $host:$managedname to enable it run : \n";
        print "ssh hscroot\@$host \"chlparutil -r config -m $managedname -s $STEP\"\n";
        print "*****WARNING*****WARNING*****WARNING*****\n";

        # go for next managed system / hmc server
        save_cfg_data( $managedname, localtime(), $upgrade );    # it is necessary to have all server in cfg page
        next;
      }
      else {

        if ( $hmcv_num >= 733 ) {
          print "Utilization data collection is set to \"$step\" for managed system : $host:$managedname\n";
          print "lpar2rrd tool is configured for $STEP seconds interval\n";
          print "Your HMC supports it as its version is higher than 7.3.3\n";
          print "Ignore this message if you want to use 3600s sample rate anyway\n";
          print "ssh hscroot\@$host \"chlparutil -r config -m $managedname -s $STEP\"\n";
          print "*****WARNING*****WARNING*****WARNING*****\n";

          # go for next managed system / hmc server
          #next;
        }
      }
    }

    # for 1hour sample rate --> suffix "h", for 1min and other suffix "m"
    if ( $step == 3600 ) {
      $type_sam = "h";
    }
    else {
      $type_sam = "m";
    }

    prepare_last_time( $managedname, $et_HostSystem );
  }    # end of cycle on $managedname_list (on servers)

  # save esxi config @all_esxi_config
  chomp @all_esxi_config;
  my @all_esxi_config_sorted = sort @all_esxi_config;

  #  my $all_esxi_config_file_name = "$wrkdir/vmware_$vmware_uuid/esxis_config.txt";
  #  if (open my $FHcfg, ">$all_esxi_config_file_name") {
  #    foreach (@all_esxi_config_sorted) {
  #      print $FHcfg "$_\n";
  #    }
  #    close $FHcfg;
  #  }
  #  else {
  #    error( "can't open \$all_esxi_config_file_name $all_esxi_config_file_name (1st run after fresh install is OK) : $!" . __FILE__ . ":" . __LINE__);
  #  }
  # prepare html esxi config @all_esxi_config
  #  my $res_ret = FormatResults( \@all_esxi_config_sorted );
  my $all_esxi_config_file_name = "$wrkdir/vmware_$vmware_uuid/esxis_config.html";
  if ( open my $FHe, '>:encoding(UTF-8)', "$all_esxi_config_file_name" ) {
    print $FHe "<CENTER><TABLE class=\"tabconfig tablesorter tablesorter-ice\">\n";    # print "<CENTER><table class=\"tablesorter tablesorter-ice nofilter\" style=\"width:$table_width\">\n";
    print $FHe "<thead><TR>
        <TH align=\"center\" class=\"sortable\" valign=\"left\">Vcenter</TH>
        <TH align=\"center\" class=\"sortable\" valign=\"left\">Cluster</TH>
        <TH class=\"sortable\" valign=\"center\">ESXi</TH>
				<TH align=\"center\" class=\"sortable\" valign=\"right\">GHz total</TH>
				<TH align=\"center\" class=\"sortable\" valign=\"right\">GHz used</TH>
        <TH align=\"center\" class=\"sortable\" valign=\"right\">MEM GB total</TH>
        <TH align=\"center\" class=\"sortable\" valign=\"right\">MEM GB used</TH>
        <TH align=\"center\" class=\"sortable\" valign=\"right\">Cores</TH>
        <TH align=\"center\" class=\"sortable\" valign=\"right\">Threads</TH>
        <TH align=\"center\" class=\"sortable\" valign=\"left\">Version</TH>
        <TH align=\"center\" class=\"sortable\" valign=\"right\">Uptime (days)</TH>
        <TH align=\"center\" class=\"sortable\" valign=\"left\">Vendor</TH>
        <TH align=\"center\" class=\"sortable\" valign=\"left\">Model</TH>
        <TH align=\"center\" class=\"sortable\" valign=\"left\">Processor</TH>
			</TR></thead>\n";

    #    print $FHe "$res_ret";
    #    print $FHe "</tbody></TABLE></CENTER><BR><BR>\n";
    #    close $FHe;
    my %esxi_cfg = ();

    # create hash of arrays of (vcenter) clusters
    foreach (@all_esxi_config_sorted) {
      my $line = $_;
      ( my $vcenter, my $cluster, undef ) = split ",", $line;
      push @{ $esxi_cfg{ "$vcenter" . "_" . "$cluster" } }, $line;
    }

    #print "---------------------------------------------------------------- config\n";
    # print Dumper(%esxi_cfg);
    #print "---------------------------------------------------------------- config\n";

    # creating subtitles - subtitle sums for clusters

    my @new_arr = ();
    foreach ( keys %esxi_cfg ) {    # cycle on clusters
      my $my_key = $_;
      print $FHe "<tbody><!$my_key>\n";
      my $ghz_totl = 0;
      my $ghz_used = 0;
      my $mem_totl = 0;
      my $mem_used = 0;
      my $cores    = 0;
      my $threads  = 0;
      my $res_ret  = FormatResults( \@{ $esxi_cfg{$my_key} } );
      print $FHe "$res_ret";
      print $FHe "</tbody><!$my_key>\n";

      foreach ( @{ $esxi_cfg{$my_key} } ) {    # cycle on esxis
        my $esxi = $_;
        push @new_arr, $esxi;

        # print "\$esxi $esxi\n";
        ( undef, undef, undef, my $ghz_t, my $ghz_u, my $mem_t, my $mem_u, my $cors, my $thrds, undef ) = split ",", $esxi;
        $ghz_totl += $ghz_t;
        $ghz_used += $ghz_u;
        $mem_totl += $mem_t;
        $mem_used += $mem_u;
        $cores    += $cors;
        $threads  += $thrds;
      }
      my @esxi_arr = ",,TOTAL,$ghz_totl,$ghz_used,$mem_totl,$mem_used,$cores,$threads, , , , , ";
      push @new_arr, @esxi_arr;

      #my $bgcolor = "#80FF80"; #green
      my $bgcolor = "#D3D3D3";    #LightGrey
      print $FHe "<tbody class=\"tablesorter-no-sort\" bgcolor=\"$bgcolor\"><!$my_key>\n";
      $res_ret = FormatResults( \@esxi_arr );
      chomp $res_ret;
      print $FHe "$res_ret<!$my_key>";
      print $FHe "</tbody><!$my_key>\n";

      # cprint "--- end of array of esxis in cluster\n";
    }
    print $FHe "</TABLE></CENTER>\n";
    close $FHe;

    # print "3487 \@new_arr @new_arr\n";

    my $all_esxi_config_file_name = "$wrkdir/vmware_$vmware_uuid/esxis_config.txt";
    if ( open my $FHcfg, ">$all_esxi_config_file_name" ) {
      foreach (@new_arr) {
        print $FHcfg "$_\n";
      }
      close $FHcfg;
    }
    else {
      error( "can't open \$all_esxi_config_file_name $all_esxi_config_file_name (1st run after fresh install is OK) : $!" . __FILE__ . ":" . __LINE__ );
    }
  }
  else {
    error( "can't open '$all_esxi_config_file_name': $!" . __FILE__ . ":" . __LINE__ );
  }

  # vcenter config
  $vcenter_vms_count = 0;    # get VMs total number
  foreach my $key ( keys %vcenter_clusters ) {
    $vcenter_vms_count += $vcenter_clusters{$key};
  }
  my @vcenter_config = "$alias,$host,$vcenter_ghz,$vcenter_overallCpuUsage_ghz,$vcenter_memorySize_gb,$vcenter_overallMemoryUsage_gb,$fullName_top,$vcenter_last_update," . ( keys %vcenter_clusters ) . "," . ( scalar @all_esxi_config ) . ",$vcenter_vms_count";

  my $vcenter_config_file_name = "$wrkdir/vmware_$vmware_uuid/vcenter_config.txt";
  if ( open my $FH_vc, '>:encoding(UTF-8)', "$vcenter_config_file_name" ) {
    print $FH_vc $vcenter_config[0];
    close $FH_vc;
  }
  else {
    error( "can't open '$vcenter_config_file_name': $!" . __FILE__ . ":" . __LINE__ );
  }

  my $res_ret = FormatResults( \@vcenter_config );
  $vcenter_config_file_name = "$wrkdir/vmware_$vmware_uuid/vcenter_config.html";
  if ( open my $FHe, '>:encoding(UTF-8)', "$vcenter_config_file_name" ) {
    print $FHe "<CENTER><TABLE class=\"tabconfig tablesorter\">\n";
    print $FHe "<thead><TR> <TH class=\"sortable\" valign=\"center\">Alias</TH>
				<TH align=\"center\" class=\"sortable\" valign=\"right\">Host</TH>
        <TH align=\"center\" class=\"sortable\" valign=\"right\">GHz total</TH>
				<TH align=\"center\" class=\"sortable\" valign=\"right\">GHz used</TH>
        <TH align=\"center\" class=\"sortable\" valign=\"right\">MEM GB total</TH>
        <TH align=\"center\" class=\"sortable\" valign=\"right\">MEM GB used</TH>
        <TH align=\"center\" class=\"sortable\" valign=\"left\">Version</TH>
        <TH align=\"center\" class=\"sortable\" valign=\"right\">Last updated</TH>
        <TH align=\"center\" class=\"sortable\" valign=\"left\">Clusters</TH>
        <TH align=\"center\" class=\"sortable\" valign=\"right\">ESXi</TH>
        <TH align=\"center\" class=\"sortable\" valign=\"right\">VMs</TH>
			</TR></thead><tbody>\n";
    print $FHe "$res_ret";
    print $FHe "</tbody></TABLE></CENTER>\n";
    close $FHe;
  }
  else {
    error( "can't open '$vcenter_config_file_name': $!" . __FILE__ . ":" . __LINE__ );
  }

  print_fork_output();

  # save @managednamelist_vmw for later use e.g. detail_graph_cgi
  # print "3118 \$managedname $managedname \$host $host $wrkdir/vmware_$vmware_uuid\n";
  my $all_server_names_file_name = "$wrkdir/vmware_$vmware_uuid/servers.txt";

  if ( open my $FHserv, ">$all_server_names_file_name" ) {
    chomp @managednamelist_vmw;
    foreach (@managednamelist_vmw) {
      print $FHserv "$_" . "XORUX" . "$host\n";
    }
    close $FHserv;
  }
  else {
    error( "can't open \$all_server_names_file_name $all_server_names_file_name (1st run after fresh install is OK) : $!" . __FILE__ . ":" . __LINE__ );
  }

  # prepare hash having all VMs' uuid->name used inside next call
  my $lpar_trans_file = "$wrkdir/$all_vmware_VMs/$all_vm_uuid_names";
  %vm_uuid_name_hash = ();

  if ( -f "$lpar_trans_file" ) {
    if ( open( my $FR, "< $lpar_trans_file" ) ) {
      foreach my $linep (<$FR>) {
        chomp($linep);
        ( my $id, my $name, undef ) = split( /,/, $linep );
        $vm_uuid_name_hash{$id} = $name;
      }
      close($FR);
    }
    else {
      error( " Can't open $lpar_trans_file : $!" . __FILE__ . ":" . __LINE__ );
    }
  }

  make_cmd_frame_multiview( $managedname, $host, $et_HostSystem );    # for ESXi servers

  return 0;
}

sub print_fork_output {
  return if ( scalar @returns == 0 );

  open my $FH, ">>$counters_info_file" or error( "can't open $counters_info_file: $!" . __FILE__ . ":" . __LINE__ );

  # print output of all forks
  foreach my $fh (@returns) {

    # print "$alias jak casto zde jsem IN ".localtime()."\n";
    # print Dumper($fh);

    # my $retezec = `date; ps -ef|grep defu| grep -v auto`;
    # print "### ------ \$retezec $retezec\n";
    while (<$fh>) {
      if ( $_ =~ 'XERROR' ) {
        ( undef, my $text ) = split( ":", $_, 2 );
        print $FH "$text";
      }
      elsif ( $_ =~ "^vm_dstr_counter_data" ) {    # mining datastore IO data
        push @vm_dstr_counter_data, $_;
      }
      elsif ( $_ =~ "^vm_counter_data" ) {         # mining all VM data
                                                   # ( undef, my $line ) = split( " ", $_, 2 );
        ( undef, my $vm_uuid, my $line ) = split( " ", $_, 3 );

        # push @vm_counter_data, $line;
        $vm_hash{$vm_uuid} = $line;
        if ( $first_vm_counter_data eq "" ) {
          $first_vm_counter_data = "$vm_uuid $line";
        }
      }
      elsif ( $_ =~ "^update_line" ) {
        push @all_vcenter_perf_data, $_;
      }
      else {
        print $_;
      }
    }
    close($fh);

    # print "$alias jak casto zde jsem OUT ".localtime()."\n";
  }
  @returns = ();    # clear the filehandle list
  close $FH;

  print "All chld finish: $host " . localtime(time) . "\n" if $DEBUG;

  # print "1876 this is \@vm_dstr_counter_data @vm_dstr_counter_data\n";

  waitpid( -1, WNOHANG );    # take stats of forks and remove 'defunct' processes
}

sub print_fork_dstr_output {
  return if ( scalar @returns == 0 );

  open my $FH, ">>$counters_info_file" or error( "can't open $counters_info_file: $!" . __FILE__ . ":" . __LINE__ );

  # print output of all forks
  foreach my $fh (@returns) {
    while (<$fh>) {
      if ( $_ =~ 'XERROR' ) {
        ( undef, my $text ) = split( ":", $_, 2 );
        print $FH "$text";
      }
      elsif ( $_ =~ "^update_line" ) {
        push @all_vcenter_perf_data, $_;
      }
      else {
        print $_;
      }
    }
    close($fh);
  }
  @returns = ();    # clear the filehandle list
  close $FH;

  waitpid( -1, WNOHANG );
  print "All chld finish: DSTR/CLSTR $host \n" if $DEBUG;
}

#sub safe_forks_output_to_file {
#  my $output_file_name = shift;
#
#  return if ( (! @returns) or (scalar @returns == 0 ) );
#
#  open my $FH, ">$output_file_name" or error( "can't open $output_file_name: $!" . __FILE__ . ":" . __LINE__ ) && return;
#
#  print "Start print   : forks to file $output_file_name ".localtime()."\n" if $DEBUG;
#
#  foreach my $fh (@returns) {
#    # print "$alias jak casto zde jsem IN ".localtime()."\n";
#
#    while (<$fh>) {
#      print $FH $_;
#    } ## end while (<$fh>)
#    close($fh);
#
#    # print "$alias jak casto zde jsem OUT ".localtime()."\n";
#  } ## end foreach my $fh (@returns)
#  close $FH;
#
#  print "Finish print  : forks to file $output_file_name ".localtime()."\n" if $DEBUG;
#
#} ## end sub safe_forks_output_to_file

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

sub make_cmd_frame_multiview {
  my $cl_managedname = shift;
  my $cl_host        = shift;
  my $et_type        = shift;
  return;    # moved to heatmap.pl script by Jindra
}

sub get_unix_last_time {
  my $file     = shift;
  my $upd_time = 0;
  open( my $FHLT, "< $file" ) || error( " Can't open $file: $!" . __FILE__ . ":" . __LINE__ ) && return 0;
  foreach my $line1 (<$FHLT>) {
    chomp($line1);
    $upd_time = $line1;
  }
  close($FHLT);
  $upd_time = str2time($upd_time);    # format in file is e.g. '12/6/2016 13:0:0'
  return $upd_time;
}

sub prepare_last_time {
  my $entity      = shift;
  my $entity_type = shift;
  my $entity_name = shift;
  my $entity_uuid = shift;

  # if ($entity_name eq "CUSTOMER2") { return };
  # if ($entity_name eq "DemoOrgVDC (408f999e-621b-46d5-ba07-377c10b616c9)") { return };

  $step    = $STEP;                       # do not know if vmware will have sometimes other value
  $no_time = $step * $NO_TIME_MULTIPLY;

  $loadhours = 0;                         # must be here before rrd_check

  if ( $entity_type eq $et_ResourcePool ) {
    $last_file = "$entity_uuid.last";                                                           # RP name
    return if ( time - get_unix_last_time("$wrkdir/$managedname/$host/$last_file") ) < 1800;    # at least 30 minutes
  }
  if ( $entity_type eq $et_Datastore ) {

    # print "2015 \@vm_dstr_counter_data @vm_dstr_counter_data\n";
    $last_file = "$entity_uuid.last";                                                           # DS name
    my $file_last_time = get_unix_last_time("$wrkdir/$managedname/$host/$last_file");

    # print "3217 \$last_file $last_file " . time . " \$file_last_time $file_last_time\n";
    return if ( time - get_unix_last_time("$wrkdir/$managedname/$host/$last_file") ) < 1200;    # at least 20 minutes
  }
  if ( $entity_type eq $et_ClusterComputeResource ) {
    $last_file = "last.txt";
    return if ( time - get_unix_last_time("$wrkdir/$managedname/$host/$last_file") ) < 1800;    # at least 30 minutes
  }

  rrd_check($managedname);                                                                      # testing if first load

  print "sample rate    : $host:$managedname $step seconds\n" if $DEBUG;

  # there is always UTC time on VMWARE
  my $date = $service_instance->CurrentTime();

  chomp($date);

  #    my ($c_day, $c_time) = split ("T",$date);
  #    my ($c_hour, $c_min, $c_sec) = split (":",$c_time);
  #    if ($c_min > 29) {
  #        $c_min -= 30
  #    }
  #    else {
  #        $c_min += 30;
  #          $c_hour -= 1;
  #    }
  #    $date = $c_day."T".$c_hour.":".$c_min.":".$c_sec;

  my $t              = str2time($date);
  my $t_int          = int($t);
  my $t_actual_unix  = time();
  my $t_actual_human = localtime($t_actual_unix);

  # print "DATE: $t -- $t_int -- $date\n" ;
  # my $time_act = strftime "%d/%m/%y %H:%M:%S", $t_actual_human );
  print "VMWARE date    : $host:$managedname $date (local time: $t_actual_human) \n" if $DEBUG;

  my $diff = $t_int - $t_actual_unix;
  $diff *= -1 if $diff < 0;

  # print "\$diff $diff\n";
  $diff = $diff % 3600;
  my $diff_min = 5;
  if ( $diff > $diff_min * 60 ) {
    error("INFO Time diff > $diff_min minutes (with TZ respect) $host:$managedname $date (local time: $t_actual_human)\n");
  }

  my $last_rec_file = "";

  my $where = "file";
  if ( !$loadhours ) {    # all except the initial load --> check rrd_check
    if ( -f "$wrkdir/$managedname/$host/$last_file" ) {
      $where = "$last_file";

      # read timestamp of last record
      # this is main loop how to get corectly timestamp of last record!!!

      open( my $FHLT_man, "< $wrkdir/$managedname/$host/$last_file" ) || error( " Can't open $wrkdir/$managedname/$host/$last_file: $!" . __FILE__ . ":" . __LINE__ ) && return 0;
      foreach my $line1 (<$FHLT_man>) {
        chomp($line1);
        $last_rec_file = $line1;
      }
      print "last rec 1     : $host:$managedname $last_rec_file \$wrkdir/$managedname/$host/$last_file\n";
      close($FHLT_man);

      my $ret = substr( $last_rec_file, 0, 1 );
      if ( $last_rec_file eq '' || $ret =~ /\D/ ) {

        # in case of an issue with last file, remove it and use default 60 min? for further run ...
        error("Wrong input data, deleting file : $wrkdir/$managedname/$host/$last_file : $last_rec_file");
        unlink("$wrkdir/$managedname/$host/$last_file");

        # place there last 1h when an issue with last.txt
        $loadhours = 1;
        $loadmins  = 60;
        $last_rec  = $t - 3600;

        # vmware only 59 mins
        $loadmins = 59;
        $last_rec = $t - 3540;
      }
      else {
        $last_rec  = str2time($last_rec_file);
        $loadhours = sprintf( "%.0f", ( $t - $last_rec ) / 3600 );
        $loadhours++;
        $loadmins   = sprintf( "%.0f", ( $t - $last_rec ) / 60 );    # nothing more
        $loadsec_vm = sprintf( "%.0f", ( $t - $last_rec ) );         # for vmware
        $loadmins   = 59   if $loadmins > 59;
        $loadsec_vm = 3540 if $loadsec_vm > 3540;
        $loadsec_vm = 3540 if $loadsec_vm < 0;                       # if anything really awful
      }
    }
    else {                                                           #vmware
      $loadmins = 59;
      $last_rec = $t - 3540;
    }
  }
  else {
    $where = "init";
    my $loadsecs = $INIT_LOAD_IN_HOURS_BACK * 3600;

    #vmware
    $loadmins   = 59;
    $loadsec_vm = 3540;
    $loadsecs   = 3540;

    $last_rec = $t - $loadsecs;
  }

  if ( $loadhours <= 0 || $loadmins <= 0 ) {    # something wrong is here
    error("Last rec issue: $last_file:  $loadhours - $loadmins -  $last_rec -- $last_rec_file : $date : $t : 01");

    # place some reasonable defaults
    $loadhours = 1;
    $loadmins  = 59;
    $last_rec  = time();
    $last_rec  = $last_rec - 3540;
  }

  ( $sec, $ivmmin, $ivmh, $ivmd, $ivmm, $ivmy, $wday, $yday, $isdst ) = localtime($last_rec);
  $ivmy += 1900;
  $ivmm += 1;
  print "last rec 2     : $host:$managedname min:$loadmins , hour:$loadhours, $ivmm/$ivmd/$ivmy $ivmh:$ivmmin : $where\n" if $DEBUG;

  lpm_exclude_vio( $host, $managedname, $wrkdir );
  hmc_load_data( $t, $managedname, $host, $last_rec, $t, $entity, $entity_type, $entity_uuid );
  $date = localtime();
  print "date load      : $host:$managedname $date\n" if $DEBUG;
}

# provides easy uuid check, pays for 1 arg only
sub uuid_check {

  return ( $_[0] =~ m{.{8}-.{4}-.{4}-.{4}-.{12}} );

}

# provides easy uuid check, pays for 1 arg only, for datastore uuid
sub uuid_check_ds {

  return ( $_[0] =~ m{.{8}-.{8}-.{4}-.{12}} );
}

sub uuid_check_ds_nfs {

  return ( $_[0] =~ m{.{8}-.{8}} );
}

sub uuid_check_ds_vsan {

  return ( $_[0] =~ m{.{16}-.{16}} );
}

sub hmc_load_data {
  my $hmc_utime = shift;

  #my $loadhours = shift; # it must be GLOBAL variable
  my $managedname = shift;
  my $host        = shift;
  my $last_rec    = shift;
  my $t           = shift;
  my $entity      = shift;
  my $entity_type = shift;
  my $entity_uuid = shift;

  # print "2727 vmw2rrd.pl \$hmc_utime $hmc_utime \$managedname $managedname \$host $host \$last_rec $last_rec \$t $t \$vm_host ,$vm_host,\n";

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

  if ( !( $loadmins > 0 ) ) {
    my $t1 = localtime($last_rec);
    my $t2 = localtime($t);
    error("$act_time: time issue 2   : $host:$managedname hours:$loadhours mins:$loadmins Last saved record (HMC lslparutil time) : $last_rec ; HMC time : $t - $t1 - $t2");
    return;
  }

  if ( $loadhours != $INIT_LOAD_IN_HOURS_BACK ) {
    print "download data  : $host:$managedname last $loadmins  minute(s) ($loadhours hours) ($loadsec_vm sec VM)\n" if $DEBUG;
  }

  if ( $entity_type ne $et_HostSystem ) {
    $pef_time_sec = $loadsec_vm;
    if ( $loadsec_vm eq "" ) {
      $pef_time_sec = $loadmins * 60;
    }
  }

  # st_date, $end_date only for first esxi server
  # it then pays for all servers and VMs
  # print "2763 \$st_date $st_date\n";
  if ( ( $st_date eq "first time" && $entity_type eq $et_HostSystem ) || ( $loadsec_vm < $pef_time_sec ) ) {
    $pef_time_sec = $loadsec_vm - 5;    # do not take last measurement again
    if ( $loadsec_vm eq "" ) {
      $pef_time_sec = $loadmins * 60;
    }

    # print "2932 \$pef_time_sec $pef_time_sec\n";
    ( $st_date, $end_date, $pef_time_sec ) = get_last_date_range( $pef_time_sec, $entity_type );
  }

  # print "2771 \$pef_time_sec $pef_time_sec \$st_date $st_date \$end_date $end_date (".$$."F$server_count)\n";

  ###   forking

  local *FH;
  $pid[$server_count] = open( FH, "-|" );    # open to pipe
                                             # $pid[$server_count] = fork();

  if ( not defined $pid[$server_count] ) {
    error("$host:$managedname could not fork");
  }
  elsif ( $pid[$server_count] == 0 ) {
    print "Fork           : $host:$managedname : $server_count child pid $$\n" if $DEBUG;

    $i_am_fork = "fork";

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

    #    $sessionManager->SetLocale(locale => "de");

    Opts::assert_usage( defined($sessionManager), "No sessionManager." );

    load_data_and_graph( $pef_time_sec, $entity, $entity_type, $entity_uuid );
    print "Fork exit      : $host:$managedname : $server_count\n" if $DEBUG;
    Util::disconnect();
    exit(0);
  }

  if ( !$do_fork || $cycle_count == $PARALLELIZATION ) {
    print "No fork        : get fork results $host:$managedname : $server_count\n" if $DEBUG;
    $cycle_count = 0;
    $server_count++ if $cycle_count == $PARALLELIZATION;

    push @returns, *FH;

    # this operation should clear all finished forks 'defunct'
    print_fork_output();
  }
  else {
    print "Parent continue: $host:$managedname $pid[$server_count ] parent pid $$\n";
    $server_count++;

    push @returns, *FH;
  }

  $cycle_count++;
}

sub load_data_and_graph {
  my $pef_time_sec = shift;
  my $entity       = shift;
  my $entity_type  = shift;
  my $entity_uuid  = shift;

  if ( !defined $entity_type ) {
    $entity_type = "";
  }

  #my $st_date;
  #my $end_date;

  eval { $perfmgr_view = Vim::get_view( mo_ref => Vim::get_service_content()->perfManager ); };
  if ($@) {
    my $ret = $@;
    chomp($ret);
    error( "vmw2rrd failed during \$perfmgr_view : $ret " . __FILE__ . ":" . __LINE__ );

    # return;
  }
  $error_select_counters = 0;    # next function could set it
  init_perf_counter_info($entity_type);

  if ( $entity_type ne $et_HostSystem && $entity_type ne $et_VirtualMachine ) {
    ( $st_date, $end_date, $pef_time_sec ) = get_last_date_range( $pef_time_sec, $entity_type );
  }

  print "dates          : \$st_date $st_date \$end_date $end_date total sec $pef_time_sec (" . $$ . "F$server_count)\n";

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

  print "before get_entity_perf for HostSystem " . $entity_host->name . "\n" if $entity_host->name eq $problem_server_name;
  get_entity_perf( $entity_host, $entity_type, $st_date, $end_date, $pef_time_sec );

  print "after get_entity_perf for HostSystem " . $entity_host->name . "\n" if $entity_host->name eq $problem_server_name;

  $entity_type = $et_VirtualMachine;
  init_perf_counter_info($entity_type);

  #Get VMs for host
  print "before find_entity_views for HostSystem " . $entity_host->name . "\n" if $entity_host->name eq $problem_server_name;

  my $entity_views = "";
  eval { $entity_views = Vim::find_entity_views( view_type => $entity_type, begin_entity => $vm_host ); };
  if ($@) {
    error( "(" . $$ . "F$server_count) eval error when asking find_entity_views $entity_type from server " . $entity_host->name . " " . __FILE__ . ":" . __LINE__ );

    # error( "(".$$."F$server_count) eval error when asking find_entity_views $entity_type from server ".$entity_host->name." $@\n". __FILE__ . ":" . __LINE__ );
    return;
  }

  print "after find_entity_views for HostSystem " . $entity_host->name . "\n" if $entity_host->name eq $problem_server_name;

  #  print Dumper ("4635", $entity_views);
  @esxi_vm_entities = ();

  foreach my $entity ( sort { $a->name cmp $b->name } @$entity_views ) {

    #check if the vm is on to collect stats

    if ( $entity_type eq $et_VirtualMachine && $entity->runtime->powerState->val eq 'poweredOff' ) {

      # print "fetching VM    : " . $entity->name . " (" . $entity->{'mo_ref'}->value . ") is powered off.  No stats available. (" . $$ . "F$server_count)\n" if $DEBUG;
      print "fetching VM    : " . $entity->name . " (" . $entity->{'mo_ref'}->value . ") is powered off\n" if $DEBUG;
      next;
    }
    if ( $entity_type eq $et_VirtualMachine && $entity->runtime->powerState->val eq 'suspended' ) {
      print "fetching VM    : " . $entity->name . " (" . $entity->{'mo_ref'}->value . ") is suspended\n" if $DEBUG;
      next;
    }
    $fail_entity_name = $entity->name;
    $fail_entity_type = "VM";

    # vm to exclude
    next if exclude_vm( $fail_entity_name, 0 );

    if ($all_esxi_vm) {    # all Esxi VMs in one
      push @esxi_vm_entities, $entity;
    }
    else {
      get_entity_perf( $entity, $entity_type, $st_date, $end_date, $pef_time_sec );
    }
  }

  # print Dumper (@esxi_vm_entities);
  if ($all_esxi_vm) {    # all Esxi VMs in one
    return if not defined $esxi_vm_entities[0];    # server has no active VMs
    get_entity_perf( $esxi_vm_entities[0], $entity_type, $st_date, $end_date, $pef_time_sec );
  }
}

sub get_entity_perf {
  my ( $entity, $entity_type, $st_date, $end_date, $pef_time_sec, $entity_uuid ) = @_;

  my $entity_nick = "VM    : ";
  $entity_nick = "HS    : " if $entity_type eq $et_HostSystem;
  $entity_nick = "clust : " if $entity_type eq $et_ClusterComputeResource;
  $entity_nick = "RP    : " if $entity_type eq $et_ResourcePool;
  $entity_nick = "DS    : " if $entity_type eq $et_Datastore;

  # print "in sub get_entity_perf \$entity_type $entity_type \$st_date $st_date \$end_date $end_date \$pef_time_sec $pef_time_sec\n";
  # print "in sub get_entity_perf $entity_type ".$entity->name. " (".$$."F$server_count) " .localtime()."\n";

  my $cpu_res = $host_cpuAlloc;    # if "HostSystem"

  if ( $entity_type eq $et_VirtualMachine ) {
    $cpu_res = $entity->config->cpuAllocation->reservation;
    $numCpu  = $entity->summary->config->numCpu;

    # print "\$numCpu $numCpu\n";
    $vm_uuid_active = $entity->summary->config->instanceUuid;
    return if not defined $vm_uuid_active;    # there can exist poweredOn VM with UNSET instanceUuid

    $last_file = "$vm_uuid_active.last";

    # if ( !-f "$wrkdir/$all_vmware_VMs/$last_file" ) {
    #`touch "$wrkdir/$all_vmware_VMs/$last_file"`;   #they are not needed anymore
    # }

    #     else {
    #       # from VM last time you can change $st_date
    #       open(FHLT, "< $wrkdir/$all_vmware_VMs/$last_file") || error(" Can't open $wrkdir/$all_vmware_VMs/$last_file : $!".__FILE__.":".__LINE__);
    #        my $line =  <FHLT>;
    #       close(FHLT);
    #       $line = "" if (! defined $line);
    #       chomp($line);
    #       if ($line ne "") {
    #         my $last_rec_utc = str2time($line); # unix
    #         my $str_time_loc = str2time($st_date); # local
    #         # print "working out new \$last_rec_utc $line ($last_rec_utc) \$st_date $st_date ($str_time_loc) for VM\n";
    #         my ($sec,$min,$hour,$day,$month,$year,$wday,$yday,$isdst) = gmtime($last_rec_utc); # gm
    #         my $last_rec_loc = timelocal($sec,$min,$hour,$day,$month,$year);
    #         # print "diff with $last_rec_utc $str_time_loc \$last_rec_loc $last_rec_loc\n";
    #         if (($str_time_loc - $last_rec_loc) > 20) { # not care if short diff
    #           my $time_diff = $str_time_loc - $last_rec_loc;
    #           # print "adjust VM      : start time back for $time_diff sec\n";
    #           my $str_time = $str_time_loc - $time_diff + 5;
    #           ($sec,$min,$hour,$day,$month,$year,$wday,$yday,$isdst) = localtime($str_time);
    #           $year += 1900;
    #           $month++;
    #           my $st_date = $year . "-" . $month . "-" . $day . "T" . $hour . ":" . $min . ":" . $sec;
    #           print "adjust VM      : start time back for $time_diff sec to $st_date\n";
    #         }
    #       }
    #     }
  }

  my $intervals;
  my $refreshRate = "-1";                                                      # for any case
  if ( $entity_type eq $et_Datastore && $apiType_top !~ "VirtualCenter" ) {    # seems datastore produces 'Fault string: A specified parameter was not correct.'
                                                                               # $refreshRate = "20"; # better do nothing
  }
  else {
    eval { $refreshRate = $perfmgr_view->QueryPerfProviderSummary( entity => $entity )->refreshRate; };
    if ($@) {
      my $ret = $@;
      chomp($ret);
      error( "vmw2rrd failed during refreshRate : $ret " . __FILE__ . ":" . __LINE__ );

      # exit(1);
    }
  }

  # print Dumper($refreshRate);

  $intervals = get_available_intervals( perfmgr_view => $perfmgr_view, host => $entity, entity_type => $entity_type );

  # print Dumper($intervals);

  # print "before perf_metric_ids\n";
  # my $qam = $perfmgr_view->QueryAvailablePerfMetric(entity => $entity);
  # print "before perf_metric_ids after qam\n";

  my @fake_arr = ();    # just for DS ESXi using
  $fake_arr[0]{'sample'} = 'ahoj';
  my $perf_metric_ids = \@fake_arr;
  my $perf_metric     = "";
  if ( $apiType_top =~ "HostAgent" && $entity_type eq $et_Datastore ) {

    # nothing #$apiType_top !~ 'HostAgent'
  }
  else {
    $perf_metric = "";
    eval { $perf_metric = $perfmgr_view->QueryAvailablePerfMetric( entity => $entity ); };
    if ($@) {
      my $ret = $@;
      chomp($ret);
      error( "vmw2rrd failed perf_metric : $ret " . __FILE__ . ":" . __LINE__ );

      # exit(1);
    }
    else {
      $perf_metric_ids = filter_metric_ids( $perf_metric, $entity_type );
    }
  }

  #if ( $entity_type eq $et_VirtualMachine) {
  #  print "4053 works for ".$entity->name."\n";
  #  print Dumper $perf_metric;
  #}
  # print "4007 works for ".$entity->name."\n";

  # print Dumper ("2982",$entity);
  # print Dumper("2893",$entity_type,$perf_metric_ids);
  # if ($entity_type eq $et_VirtualMachine) {
  #   print "2074\n";
  #   print Dumper ($perf_metric_ids);
  # }
  # choose intervalId according to interval for download
  my $intervalId;

  #      my $intervalId = "300";
  #      if ($pef_time_sec < 3600) {
  #         $intervalId = "20";
  #      }

  $intervalId = shift @$intervals;
  if ( !defined $intervalId || $intervalId < 0 ) {
    $intervalId = shift @$intervals;
    if ( !defined $intervalId ) {
      if ( !( $apiType_top =~ "HostAgent" && $entity_type eq $et_Datastore ) ) {
        error( "(" . $$ . "F$server_count) not defined intervalId 2xshift @$intervals " . __FILE__ . ":" . __LINE__ );
      }
      $intervalId = 20;
    }
    if ( $intervalId < 0 ) {
      error( "(" . $$ . "F$server_count) unexpected intervalId 2xshift @$intervals " . __FILE__ . ":" . __LINE__ );

      # give realtime
      $intervalId = 20;
    }
  }
  if ( $pef_time_sec > 3600 && ( $entity_type eq $et_VirtualMachine || $entity_type eq $et_HostSystem ) ) {
    $intervalId = shift @$intervals;
    if ( !defined $intervalId ) {    # probably not Vcenter
      $intervalId = 20;
    }
    if ( $intervalId < 0 ) {
      error( "(" . $$ . "F$server_count) unexpected intervalId 2x(<0) @$intervals " . __FILE__ . ":" . __LINE__ );

      # give realtime
      $intervalId = 20;
    }
  }

  # print "3760 \$intervalId $intervalId \$entity_type $entity_type\n";

  my $real_metrics_count = scalar @$perf_metric_ids;

  # print "after perf_metric_ids  \$intervalId=$intervalId \$real_metrics_count=$real_metrics_count\n";

  #      if ($real_metrics_count < $selected_counters) {
  #        error ("(".$$."F$server_count) selected counters > real counters number $selected_counters > $real_metrics_count, taking all real counters ".__FILE__.":".__LINE__);
  #        # take all real counters
  #        $perf_metric_ids = $perfmgr_view->QueryAvailablePerfMetric(entity => $entity);
  #      }

  my $maxsample = ( $pef_time_sec - ( $pef_time_sec % 20 ) ) / 20;
  my $perf_query_spec;

  my @perf_query_spec_array = ();

  if ( $entity_type eq $et_VirtualMachine && $all_esxi_vm ) {
    foreach my $entity_x (@esxi_vm_entities) {
      $perf_query_spec = PerfQuerySpec->new(
        entity     => $entity_x,
        metricId   => $perf_metric_ids,
        startTime  => $st_date . "Z",
        endTime    => $end_date . "Z",
        intervalId => $intervalId,
        format     => 'csv'
      );

      #      $perf_query_spec = PerfQuerySpec->new(entity => $entity_x,
      #                    metricId => $perf_metric_ids,
      #                    maxSample => $maxsample,
      #                    intervalId => $intervalId,
      #                    format => 'csv');
      push @perf_query_spec_array, $perf_query_spec;
    }

    #    print "before print perf_query_spec_array\n";
    #    print Dumper (@perf_query_spec_array);
    #    print "after print perf_query_spec_array\n";
  }
  else {
    $perf_query_spec = PerfQuerySpec->new(
      entity     => $entity,
      metricId   => $perf_metric_ids,
      startTime  => $st_date . "Z",
      endTime    => $end_date . "Z",
      intervalId => $intervalId,
      format     => 'csv'
    );

    # print Dumper (3029,$entity_type,$perf_query_spec);
  }

  # print "Dumper perf_query_spec for resourcepool\n" if $entity_type eq $et_ResourcePool;
  # print Dumper($perf_query_spec) if $entity_type eq $et_VirtualMachine; #$et_ResourcePool;

  my $real_sampling_period;
  my $time_stamps;
  my $perf_data;

  my $spec_routine = 0;

  # special routine workaround gaps
  if ( $entity_type eq $et_ClusterComputeResource || $entity_type eq $et_Datastore || $entity_type eq $et_ResourcePool ) {

    # &&  $fullName_top !~ 'vCenter Server 6') curly left
    $spec_routine = 1;
    if ( $apiType_top =~ "HostAgent" && $entity_type eq $et_Datastore ) {

      # $time_stamps = '300,2016-01-01T13:45:00Z,300,2016-01-01T13:50:00Z,300,2016-01-01T13:55:00Z,300,2016-01-01T14:00:00Z'; # example
      $time_stamps          = "300,$command_date";
      $real_sampling_period = 300;
      $perf_data            = \@fake_arr;
    }
    else {
      $spec_routine = 1;
      my $perf_data_one;
      my @perf_data_all        = ();
      my $shortest_time_stamps = "";

      foreach my $metric_id (@$perf_metric_ids) {
        my @metric_id_arr;
        $metric_id_arr[0] = $metric_id;

        # print "one by one $st_date $end_date $pef_time_sec\n";
        # print Dumper($metric_id);
        my $perf_query_spec_one = PerfQuerySpec->new(
          entity     => $entity,
          metricId   => \@metric_id_arr,
          startTime  => $st_date . "Z",
          endTime    => $end_date . "Z",
          intervalId => $intervalId,
          format     => 'csv'
        );

        my $ret         = "no direct error \$\@";
        my $counter_err = $all_counters->{ $metric_id->counterId };
        eval {
          # get performance data
          $perf_data_one = $perfmgr_view->QueryPerf( querySpec => $perf_query_spec_one );
        };
        if ($@) {
          $ret = $@;
          chomp($ret);

          if ( !defined $counter_err ) {
            error( "(" . $$ . "F$server_count) vmw2rrd has not got perf data: counter_err not defined " . __FILE__ . ":" . __LINE__ );
          }
          else {
            error( "(" . $$ . "F$server_count) vmw2rrd has not got perf data: $entity_nick " . $entity->name . " " . $counter_err->groupInfo->label . " " . $counter_err->nameInfo->key . " " . $counter_err->unitInfo->label . " " . $counter_err->rollupType->val . " " . $counter_err->level . " " . $counter_err->perDeviceLevel . " $ret " . __FILE__ . ":" . __LINE__ );
          }
          if ( index( $ret, "specified parameter was not correct" ) != -1 ) {

            print "3581 $entity_type: startTime  => $st_date Z, endTime => $end_date Z, intervalId => $intervalId\n";

            #print "metricId => ";
            #print Dumper(\@metric_id_arr);
          }

          # exit (1);
        }

        # print "after perfmgr_view\n";
        if ( !defined($perf_data_one) || !@$perf_data_one ) {
          if ( !defined $counter_err ) {
            print "fetching " . $entity_nick . $entity->name . " has no stats available for the given date range & not defined \$counter_err" . " (" . $$ . "F$server_count) " . __FILE__ . ":" . __LINE__ . "\n" if $DEBUG;
            next;
          }
          print "fetching " . $entity_nick . $entity->name . " has no stats available for the given date range " . $counter_err->groupInfo->label . " " . $counter_err->nameInfo->key . " " . $counter_err->unitInfo->label . " " . $counter_err->rollupType->val . " " . $counter_err->level . " " . $counter_err->perDeviceLevel . " (" . $$ . "F$server_count) " . __FILE__ . ":" . __LINE__ . "\n" if $DEBUG;
          next;

          #return 0;
        }

        # print Dumper("2537",$perf_data_one) if $entity_type eq $et_Datastore;
        # print Dumper("2538",$perf_data_one) if $entity_type eq $et_ClusterComputeResource;

        push @perf_data_all, $perf_data_one;

        my $time_stamps_cr = @$perf_data_one[0]->sampleInfoCSV;

        next if $time_stamps_cr eq "";

        # print "\$time_stamps_cr $time_stamps_cr\n";
        # print Dumper($perf_data_one);
        if ( $shortest_time_stamps eq "" ) {
          $shortest_time_stamps = $time_stamps_cr;    # first time
        }
        else {
          $shortest_time_stamps = $time_stamps_cr if length($time_stamps_cr) < length($shortest_time_stamps);
        }
      }

      $time_stamps = $shortest_time_stamps;
      ( $real_sampling_period, undef ) = split( ",", $shortest_time_stamps );
      if ( !defined $real_sampling_period ) {
        error( "(" . $$ . "F$server_count) not defined real_sampling_period time_stamps=$shortest_time_stamps no timestamps for " . $entity->name . " " . __FILE__ . ":" . __LINE__ );    #&& return 0;
                                                                                                                                                                                          # since 4.92
                                                                                                                                                                                          # cus vcenter sometimes gives absolutely no data,
                                                                                                                                                                                          # so we ensure that at least basic DS data are updated

        if ( $entity_type eq $et_Datastore ) {
          $real_sampling_period = 300;
          $time_stamps          = "300,$command_date";
          $perf_data            = \@fake_arr;
        }
        else {
          return 0;
        }
      }

      #if ($entity->name =~ "NFS-Synology-ISO") {
      #  print "4914 ",$entity->name,"\$real_sampling_period $real_sampling_period\n";
      #}
      if ( $real_sampling_period < 20 || $real_sampling_period > $real_sampling_period_limit ) {
        error( "(" . $$ . "F$server_count) real_sampling_period=$real_sampling_period out of limit " . $entity->name . __FILE__ . ":" . __LINE__ ) && return 0;
      }
      $samples_number = 0;
      while ( $time_stamps =~ /$real_sampling_period,/g ) { $samples_number++ }

      # print "$entity_type -------------------------------\n";
      # print Dumper(@perf_data_all);
      # print "item ----------------------\n";
      my $point_perf = \@perf_data_all;
      $perf_data = \@perf_data_all;
      my $success_metric = 0;

      # foreach my $ddata (@perf_data_all) l-curly
      # print Dumper(@$ddata[0]->value);
      # r-curly
      foreach (@$point_perf) {
        my $values = $point_perf;
        foreach (@$values) {
          my $value = @$_[0]->value;

          # print Dumper($value);
          if ( @$value[0]->id->instance eq '' ) {
            if ( prepare_vm_metric( $entity_type, @$value[0] ) ) {
              $success_metric++;

              # print "success_metric ---------\n";
              # print Dumper($_);
            }
          }
          else {
            # print "2225 non empty instance\n";
            # print Dumper($_);
          }
        }
        last;
      }

      # print "Dumper perf_query_spec for cluster\n";
      # print Dumper($perf_query_spec);
      # print Dumper($perf_metric_ids);
    }
  }
  else {
    my $ret = "no direct error \$\@";
    if ( $entity_type eq $et_VirtualMachine && $all_esxi_vm ) {
      eval {
        $perf_data = $perfmgr_view->QueryPerf( querySpec => \@perf_query_spec_array );

        #print Dumper (\@perf_query_spec_array);
        #print Dumper ($perf_data);
        #return;
      };
    }
    else {
      eval {
        # get performance data
        $perf_data = $perfmgr_view->QueryPerf( querySpec => $perf_query_spec );
      };
    }
    if ($@) {
      $ret = $@;
      chomp($ret);
      error( "(" . $$ . "F$server_count) vmw2rrd failed: $ret " . __FILE__ . ":" . __LINE__ );

      #      if ( ( index( $ret, "specified parameter was not correct" ) != -1 ) || ( index( $ret, "especificado no era correcto" ) != -1 ) ) left_curly
      print "startTime  => $st_date Z, endTime => $end_date Z, intervalId => $intervalId\n";
      if ( $entity_type eq $et_VirtualMachine && $all_esxi_vm ) {
        print Dumper( 3212, \@perf_query_spec_array );
      }
      else {
        print Dumper( 3215, $perf_query_spec );
      }

      #      right_curly ## end if ( ( index( $ret, "specified parameter was not correct"...)))

      # exit (1);
    }

    # print "after perfmgr_view\n";
    if ( !defined($perf_data) || !@$perf_data ) {
      print "fetching " . $entity_nick . $entity->name . " has no stats available for the given date range. (" . $$ . "F$server_count)\n" if $DEBUG;

      # return 0;
    }
  }
  if ( $entity_type eq $et_VirtualMachine && $all_esxi_vm ) {
    foreach my $perf_data_one (@$perf_data) {

      # print Dumper ("3158",$perf_data_one);
      my $vm_moref = $perf_data_one->{entity}->{value};
      $entity = "";

      # look for the right entity
      foreach (@esxi_vm_entities) {
        my $moref = $_->{'mo_ref'}->value;
        if ( $vm_moref eq $moref ) {
          $entity = $_;
          last;
        }
      }
      if ( $entity eq "" ) {
        error( "(" . $$ . "F$server_count) cannot find VM entity for moref: $vm_moref " . __FILE__ . ":" . __LINE__ );
        next;
      }
      $cpu_res     = $entity->config->cpuAllocation->reservation;
      $numCpu      = $entity->summary->config->numCpu;
      $entity_uuid = $entity->summary->config->instanceUuid;

      # print "2709 vmw2rrd.pl \$vm_moref $vm_moref $numCpu $cpu_res $entity_uuid\n";
      my @temp_arr = ();
      $temp_arr[0] = $perf_data_one;
      one_entity_perf_data( \@temp_arr, $spec_routine, $entity, $entity_type, $pef_time_sec, $entity_uuid, $entity_nick, $refreshRate, $cpu_res, $time_stamps, $real_sampling_period, $vm_moref );
    }
  }
  else {
    #print Dumper ($perf_data);
    one_entity_perf_data( $perf_data, $spec_routine, $entity, $entity_type, $pef_time_sec, $entity_uuid, $entity_nick, $refreshRate, $cpu_res, $time_stamps, $real_sampling_period );
  }
}

sub prepare_datastore_counter_values {

  # create sum of appropriate position counter values from more (can be also one) lines like:
  # vm_dstr_counter_data,52f7165c-3e27-dceb-b506-e723a8f1bc6a,5665bf85-5b89995a-0d8c-6c0b843c390a,179,6,1484138600 1484138620 1484138640,3,1,1,1,2,0
  #   identification,    vm-uuid,                             datastore_uuid,             ,counter_id,num_of_samples, two consec timestamps,  data
  # either we know $samples_number or take the smallest from num_of_samples from all data lines
  # returns values and time_stamps through array ref !
  # call: $samples_number = prepare_datastore_counter_values(\@dsarr,\@vm_time_stamps,\@values,$samples);
  # take care when vCenter does not have data, it sends minus values eg. -1 or -4 or so
  my $arr_ref            = shift;
  my $vm_time_stamps_ref = shift;
  my $values_ref         = shift;
  my $samples            = shift;    # if undef then work it out

  my $samples_temp = 99999;          # high enough
  my $times;
  my @result;
  @result = ('U') x $samples if defined $samples;
  foreach my $line (@$arr_ref) {
    chomp($line);

    # print "2915 vmw2rrd.pl $line\n";
    # 2915 vmw2rrd.pl vm_dstr_counter_data,501cf893-5a66-46b8-7bb6-4ddd85788438,6307710d-bb7c6a1c-fbe0-2c59e548fcd8,185,25,1682582420 1682582440,0,0,0,-1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
    ( undef, undef, undef, undef, my $samples_imm, $times, my $values ) = split( ',', $line, 7 );
    if ( !defined $samples ) {
      if ( $samples_imm < $samples_temp ) {
        $samples_temp = $samples_imm;
      }
      if ( !defined $result[0] ) {    # only first time cycle
        @result = ('U') x $samples_temp;
      }
    }
    else {
      $samples_temp = $samples;
    }
    my @temp_result = split( ',', $values );
    for ( my $i = 0; $i < $samples_temp; $i++ ) {
      if ( $temp_result[$i] > -1 ) {
        if ( $result[$i] eq 'U' ) {
          $result[$i] = $temp_result[$i];
        }
        else {
          $result[$i] += $temp_result[$i];
        }
      }
    }
  }
  $samples = $samples_temp if !defined $samples;

  # results
  @$values_ref = @result[ 0 .. $samples - 1 ];

  # print "2937 vmw2rrd.pl \$samples $samples \$times $times\n";
  @$vm_time_stamps_ref = ( split( ' ', $times ) )[ 0 .. $samples - 1 ];    #not necessary

  return $samples;
}

sub prepare_datastore_latency_counter_values {

  # create weighted average of appropriate position counter values from more lines like:
  # vm_dstr_counter_data,52f7165c-3e27-dceb-b506-e723a8f1bc6a,5665bf85-5b89995a-0d8c-6c0b843c390a,179,6,1484138600 1484138620 1484138640,3,1,1,1,2,0
  #   identification,    vm-uuid,                             datastore_uuid,             ,counter_id,num_of_samples, two consec timestamps,  data
  # either we know $samples_number or take the smallest from num_of_samples from all data lines
  # returns values and time_stamps through array ref !
  # call: $samples_number = prepare_datastore_counter_latency_values(\@dsarr,\@ds_iops_arr,\@vm_time_stamps,\@values,$samples);
  # take care when vCenter does not have data, it sends minus values eg. -1 or -4 or so
  # take care when latency data is enormous number then substitute with U
  my $arr_ref            = shift;    # latency
  my $arr_iops_ref       = shift;
  my $vm_time_stamps_ref = shift;
  my $values_ref         = shift;    # here comes results
  my $samples            = shift;    # if undef then work it out

  my $samples_temp = 99999;          # high enough
  my $times;
  my @result;
  @result = ('U') x $samples if defined $samples;
  my @iops_sum = @result;

  # my $latency_peak_reached_count;

  foreach my $line (@$arr_ref) {
    chomp($line);

    # print "3494 vmw2rrd.pl $line\n";
    ( undef, my $vm_uuid, undef, undef, my $samples_imm, $times, my $values ) = split( ',', $line, 7 );
    if ( !defined $samples ) {
      if ( $samples_imm < $samples_temp ) {
        $samples_temp = $samples_imm;
      }
      if ( !defined $result[0] ) {    # only first time cycle
        @result   = ('U') x $samples_temp;
        @iops_sum = ('U') x $samples_temp;
      }
    }
    else {
      $samples_temp = $samples;
    }

    # find matching IOPS line
    my ($iops_line) = grep {/$vm_uuid/} @$arr_iops_ref;
    next if !defined $iops_line;

    #print "3515 \$line $line mathing line \$iops_line $iops_line\n";
    ( undef, undef, undef, undef, my $samples_imme, $times, my $iops_values ) = split( ',', $iops_line, 7 );
    if ( !defined $samples ) {
      if ( $samples_imme < $samples_temp ) {
        $samples_temp = $samples_imme;
      }
      if ( !defined $result[0] ) {    # only first time cycle
        @result   = ('U') x $samples_temp;
        @iops_sum = ('U') x $samples_temp;
      }
    }
    else {
      $samples_temp = $samples;
    }

    my @temp_result = split( ',', $values );
    my @temp_iops   = split( ',', $iops_values );

    for ( my $i = 0; $i < $samples_temp; $i++ ) {
      if ( $temp_result[$i] ne "U" && $temp_result[$i] > $ds_totalReadLatency_limit ) {
        $latency_peak_reached_count++;
        next;
      }
      if ( $temp_result[$i] > 0 && $temp_iops[$i] > 0 ) {
        if ( $result[$i] eq 'U' ) {
          $result[$i] = $temp_result[$i] * $temp_iops[$i];

          # print "3540 \$i $i \$temp_result[$i] $temp_result[$i] \$temp_iops[$i] $temp_iops[$i] \$result[$i] $result[$i]\n";
        }
        else {
          $result[$i] += $temp_result[$i] * $temp_iops[$i];
        }

        # print "3546 \$i $i \$temp_result[$i] $temp_result[$i] \$temp_iops[$i] $temp_iops[$i] \$result[$i] $result[$i]\n";
        if ( !defined $iops_sum[$i] || $iops_sum[$i] eq 'U' ) {
          $iops_sum[$i] = $temp_iops[$i];
        }
        else {
          $iops_sum[$i] += $temp_iops[$i];
        }
      }
      if ( $temp_result[$i] == 0 || $temp_iops[$i] == 0 ) {
        $result[$i] = 0 if $result[$i] eq 'U';
      }
    }
  }

  # sum of multiplication is to divide by sum of iops
  #  print "3556 \@result @result \@iops_sum @iops_sum \$samples_temp $samples_temp \n";
  for ( my $i = 0; $i < $samples_temp; $i++ ) {
    if ( $result[$i] ne "U" && defined $iops_sum[$i] && $iops_sum[$i] ne "U" && $iops_sum[$i] > 0 ) {
      $result[$i] = $result[$i] / $iops_sum[$i];
    }
  }

  $samples = $samples_temp if !defined $samples;

  # results
  @$values_ref = @result[ 0 .. $samples - 1 ];

  # print "3561 vmw2rrd.pl \$samples $samples \$times $times\n";
  @$vm_time_stamps_ref = ( split( ' ', $times ) )[ 0 .. $samples - 1 ];    #not necessary

  return $samples;
}

sub one_entity_perf_data {
  my $perf_data            = shift;
  my $spec_routine         = shift;
  my $entity               = shift;
  my $entity_type          = shift;
  my $pef_time_sec         = shift;
  my $entity_uuid          = shift;
  my $entity_nick          = shift;
  my $refreshRate          = shift;
  my $cpu_res              = shift;
  my $time_stamps          = shift;
  my $real_sampling_period = shift;
  my $vm_moref             = shift;

  my $vm_uuid_from_moref;
  if ( !defined $vm_moref ) {    # not probable but ..
    $vm_uuid_from_moref = "";
  }
  else {
    $vm_uuid_from_moref = $vm_moref_uuid{$vm_moref};
    if ( ( !defined $vm_uuid_from_moref ) || ( $vm_uuid_from_moref eq "" ) ) {
      error( "(" . $$ . "F$server_count) not defined \$vm_uuid_from_moref for " . $entity->name . __FILE__ . ":" . __LINE__ ) && return 0;
    }
  }
  foreach (@$perf_data) {
    if ( !$spec_routine ) {
      $time_stamps = $_->sampleInfoCSV;

      # print "\$time_stamps $time_stamps\n";
      ( $real_sampling_period, undef ) = split( ",", $time_stamps );
      if ( !defined $real_sampling_period ) {
        error( "(" . $$ . "F$server_count) not defined real_sampling_period time_stamps=$time_stamps probably no timestamps for " . $entity->name . __FILE__ . ":" . __LINE__ ) && return 0;
      }
      if ( $real_sampling_period < 20 || $real_sampling_period > $real_sampling_period_limit ) {
        error( "(" . $$ . "F$server_count) real_sampling_period=$real_sampling_period out of limit " . $entity->name . __FILE__ . ":" . __LINE__ ) && return 0;
      }
    }
    my $samples_number_must = int( $pef_time_sec / $real_sampling_period );

    my $values;
    $values = $_->value  if !$spec_routine;
    $values = $perf_data if $spec_routine;

    # there can be real sampling period different from 20, e.g. if VCenter -> 300
    # we hold 1 min step (if change in future)
    # there should be ($pef_time_min * 60/$real_sampling_period) samples
    # working out timestamps

    $samples_number = 0;
    while ( $time_stamps =~ /$real_sampling_period,/g ) { $samples_number++ }

    if ( $refreshRate ne 20 || $real_sampling_period ne 20 ) {
      print "fetching " . $entity_nick . $entity->name . " refreshRate=$refreshRate real_sampling_period=$real_sampling_period samples_expected X real=$samples_number_must X $samples_number (" . $$ . "F$server_count)\n" if $DEBUG;
    }
    else {
      if ( $entity_type eq $et_VirtualMachine ) {

        # do not print F$server_count for VMs
        print "fetching " . $entity_nick . $entity->name . " samples_expected X real=$samples_number_must X $samples_number\n" if $DEBUG;
      }
      else {
        print "fetching " . $entity_nick . $entity->name . " samples_expected X real=$samples_number_must X $samples_number (" . $$ . "F$server_count)\n" if $DEBUG;
      }
    }
    $fail_entity_name = $entity->name;
    ( undef, my $first_time_stamp, undef ) = split( ',', $time_stamps );
    my $first_time_stamp_unix = str2time($first_time_stamp);

    if ( !defined $first_time_stamp_unix ) {
      error( "(" . $$ . "F$server_count) not valid data timestamp $first_time_stamp" . __FILE__ . ":" . __LINE__ ) && return 0;
    }

    my @vm_time_stamps = ();
    push( @vm_time_stamps, $_ * $real_sampling_period + $first_time_stamp_unix ) for ( 0 .. ( $samples_number - 1 ) );

    # prepare other metrics array with 'U'
    #   @vm_CPU_usage_percent = ('U')x $samples_number;  # not used anymore

    if ( ( $entity_type eq $et_HostSystem ) || ( $entity_type eq $et_VirtualMachine ) ) {

      @vm_host_hz                  = ($host_hz) x $samples_number;
      @vm_CPU_Alloc_reservation    = ($cpu_res) x $samples_number;
      @vm_CPU_usage_MHz            = ('U') x $samples_number;
      @vm_Memory_active_KB         = ('U') x $samples_number;
      @vm_Memory_granted_KB        = ('U') x $samples_number;
      @vm_Memory_baloon_MB         = ('U') x $samples_number;
      @vm_Disk_usage_KBps          = ('U') x $samples_number;
      @vm_Disk_read_KBps           = ('U') x $samples_number;
      @vm_Disk_write_KBps          = ('U') x $samples_number;
      @vm_Network_usage_KBps       = ('U') x $samples_number;
      @vm_Network_received_KBps    = ('U') x $samples_number;
      @vm_Network_transmitted_KBps = ('U') x $samples_number;
      @vm_Memory_swapin_KBps       = ('U') x $samples_number;
      @vm_Memory_swapout_KBps      = ('U') x $samples_number;
      @vm_Memory_compres_KBps      = ('U') x $samples_number;
      @vm_Memory_decompres_KBps    = ('U') x $samples_number;
      @vm_CPU_usage_Percent        = ('U') x $samples_number;
      @vm_CPU_ready_ms             = ('U') x $samples_number;
      @vm_Memory_consumed_KB       = ('U') x $samples_number;        # for cluster & resourcepool metric
      @vm_Power_usage_Watt         = ('U') x $samples_number;        # for cluster metric

      if ( $entity_type eq $et_HostSystem ) {
        @Host_memory_size = ($host_memorySize) x $samples_number;
      }

      # rank is according to @counter_hsvm_eng(ger1,ger2) used in sub prepare_vm_metric(), see global definitions
      $arr_pointers[0]  = \@vm_CPU_usage_MHz;
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
      $arr_pointers[16] = \@vm_Memory_consumed_KB;
      $arr_pointers[17] = \@vm_Power_usage_Watt;
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
      error( "(" . $$ . "F$server_count) unknown entity_type $entity_type " . __FILE__ . ":" . __LINE__ ) && exit 0;
    }
    my $ts_size = $samples_number;

    # print "Number of samples : $ts_size \n";
    # print "time stamps array @vm_time_stamps\n\n";

    @counter_presence = ();
    my $success_metric = 0;

    # if ($entity_type eq $et_Datastore) {
    #  	print Dumper(@$values);
    #}

    my $dstr_readAveraged  = 0;    # check first time processing
    my $dstr_writeAveraged = 0;
    my $dstr_read          = 0;
    my $dstr_write         = 0;
    my $dstr_readLatency   = 0;
    my $dstr_writeLatency  = 0;

    foreach (@$values) {
      my $value;
      if ($spec_routine) {    # for cluster, res-pool, datastore
        if ( $apiType_top =~ "HostAgent" && $entity_type eq $et_Datastore ) {

          # nothing
        }
        else {
          $value = @$_[0]->value;

          # print Dumper($value);
          if ( @$value[0]->id->instance eq '' ) {
            if ( prepare_vm_metric( $entity_type, @$value[0] ) ) {
              $success_metric++;

              # print Dumper($_);
            }
          }
          else {
            # print "2985 non instance ''\n";
            # print Dumper($_);
          }
        }
      }
      else {
        # if ($server_count ==2) {
        # print Dumper (3632,$entity_type,$_);
        # }
        if ( $_->id->instance eq '' ) {
          if ( prepare_vm_metric( $entity_type, $_ ) ) {

            # seems to divide prepare_vm_metric() to 2 functions, 1) only test counter & set presence, 2) prepare metric : cus of testing

            $success_metric++;

            # print Dumper($_);
          }
        }
        else {
          # print "2998 non '' instances\n";
          # special case for VM
          # print Dumper(3647,$_);

          if ( $_->id->counterId eq $vm_dstr_readAveraged_key
            || $_->id->counterId eq $vm_dstr_writeAveraged_key
            || $_->id->counterId eq $vm_dstr_read_key
            || $_->id->counterId eq $vm_dstr_write_key
            || $_->id->counterId eq $vm_dstr_readLatency_key
            || $_->id->counterId eq $vm_dstr_writeLatency_key )
          {
            if ( $dstr_readAveraged == 0 ) {
              $dstr_readAveraged++;
              $success_metric++;
            }
            if ( $dstr_writeAveraged == 0 ) {
              $dstr_writeAveraged++;
              $success_metric++;
            }
            if ( $dstr_read == 0 ) {
              $dstr_read++;
              $success_metric++;
            }
            if ( $dstr_write == 0 ) {
              $dstr_write++;
              $success_metric++;
            }
            if ( $dstr_readLatency == 0 ) {
              $dstr_readLatency++;
              $success_metric++;
            }
            if ( $dstr_writeLatency == 0 ) {
              $dstr_writeLatency++;
              $success_metric++;
            }

            my $time_stamps_count = scalar @vm_time_stamps;
            my $line              = "vm_dstr_counter_data,$vm_uuid_from_moref," . $_->id->instance . "," . $_->id->counterId . ",$time_stamps_count,$vm_time_stamps[0] $vm_time_stamps[1]," . $_->value;
            if ( $i_am_fork eq 'fork' ) {
              print "$line\n";    # will be collected to @vm_dstr_counter_data when reading forks output
            }
            else {
              push @vm_dstr_counter_data, $line;
            }
          }
          else {
            print Dumper( "3554", $_ );
          }
        }
      }
    }

    # print "3047 \@vm_dstr_counter_data @vm_dstr_counter_data\n";

    # simulation of not presented cluster counter CPU:usagemhz:MHz
    #if ($entity_type eq $et_ClusterComputeResource) {
    #  $success_metric = $selected_counters -1;
    #  undef $counter_presence[0];
    #}

    if ( $success_metric != $selected_counters ) {
      if ( !( $apiType_top =~ "HostAgent" && $entity_type eq $et_Datastore ) ) {
        xerror( "(" . $$ . "F$server_count) metrics problem :selected:$selected_counters retrieved:$success_metric $fail_entity_type: $fail_entity_name " . __FILE__ . ":" . __LINE__ );
        if ( $entity_type eq $et_Datastore && defined $ds_accessible && $ds_accessible != 1 ) {
          xerror( "(" . $$ . "F$server_count) $fail_entity_type: $fail_entity_name is not accessible ,$ds_accessible, " . __FILE__ . ":" . __LINE__ );
          error( "(" . $$ . "F$server_count) $fail_entity_type: $fail_entity_name is not accessible ,$ds_accessible, " . __FILE__ . ":" . __LINE__ );
        }
      }

      # print out not presented metrics
      my @tested_counters = @counter_hs_eng if ( $entity_type eq $et_HostSystem );
      @tested_counters = @counter_vm_eng if ( $entity_type eq $et_VirtualMachine );
      @tested_counters = @counter_cl_eng if ( $entity_type eq $et_ClusterComputeResource );
      @tested_counters = @counter_rp_eng if ( $entity_type eq $et_ResourcePool );
      @tested_counters = @counter_ds_eng if ( $entity_type eq $et_Datastore );

      if ( scalar @counter_presence < 1 ) {
        if ( !( $apiType_top =~ "HostAgent" && $entity_type eq $et_Datastore ) ) {
          error( "(" . $$ . "F$server_count) no real counters for $entity_type " . __FILE__ . ":" . __LINE__ );
        }
      }

      # print "3721 \@tested_counters @tested_counters\n \@counter_presence @counter_presence\n";
      for ( my $i = 0; $i < ( scalar @tested_counters ); $i++ ) {
        if ( !defined $counter_presence[$i] && !( $apiType_top =~ "HostAgent" && $entity_type eq $et_Datastore ) ) {

          # following err will not be printed
          if ( ( $fail_entity_type eq $et_Datastore ) && ( $tested_counters[$i] =~ "^Disk" ) ) {

            # nothing yet
          }
          else {
            if ( !defined $counter_arr_levels[$i] ) {
              $counter_arr_levels[$i] = "not defined levels";
            }
            xerror( "(" . $$ . "F$server_count) no real counter for $tested_counters[$i] $counter_arr_levels[$i]: $fail_entity_type: $fail_entity_name " . __FILE__ . ":" . __LINE__ );
            if ( $entity_type eq $et_ClusterComputeResource ) {
              if ( $tested_counters[$i] =~ "CPU:usagemhz:MHz" ) {
                xerror( "(" . $$ . "F$server_count) CPU:usagemhz:MHz will be reconstructed from VMs for timestamp @vm_time_stamps " . __FILE__ . ":" . __LINE__ );
                next if scalar @vm_time_stamps < 2;    # not for only 1 value
                my @active_VMs = ();

                # my $cluster_path = "vmware_7f812c15-81a6-4dfe-85e3-6c9e973985f7/cluster_domain-c7";
                my $cluster_path = "$managedname/$host";
                xerror( "(" . $$ . "F$server_count) $managedname/$host " . __FILE__ . ":" . __LINE__ );

                cluster_active_VMs( $wrkdir, $cluster_path, \@active_VMs );
                my $resolution = $vm_time_stamps[1] - $vm_time_stamps[0];
                my $start      = $vm_time_stamps[0] - $resolution;
                my $end        = $vm_time_stamps[-1] - $resolution;
                my $steps      = scalar @vm_time_stamps;
                my @values     = ('U') x $steps;

                xerror( "(" . $$ . "F$server_count) \$resolution $resolution \$start $start \$end $end " . __FILE__ . ":" . __LINE__ );

                # foreach (@active_VMs) {
                #   my $vm = $_;
                #   next if !-f $vm;    # is it possible ?
                #   RRDp::cmd qq(fetch "$vm" "AVERAGE" "-r $resolution" "-s $start" "-e $end");
                #   my $row = RRDp::read;
                #   chomp($$row);
                #   my @row_arr = split( /\n/, $$row );

                #print "\@row_arr @row_arr\n";

                #    my $inx = -1;

                #    foreach (@row_arr) {
                #     next if $_ !~ /^\d/;

                #     # choose CPU_usage MHz - it is 2nd number  1468580700: 5.5410000000e+03 1.0506000000e+03 3.2923762660e+09 2.516580...
                #     ( undef, undef, my $CPU_usage_MHz, undef ) = split( " ", $_ );
                #     $inx++;
                #     next if $CPU_usage_MHz !~ /^\d/;
                #     $CPU_usage_MHz += 0;

                # print "$CPU_usage_MHz\n";
                #     if ( $values[$inx] eq "U" ) {
                #       $values[$inx] = $CPU_usage_MHz;
                #     }
                #     else {
                #       $values[$inx] += $CPU_usage_MHz;
                #     }
                #   } ## end foreach (@row_arr)
                # } ## end foreach (@active_VMs)
                xerror( "(" . $$ . "F$server_count) \@values @values \@cl_CPU_usage_MHz @cl_CPU_usage_MHz " . __FILE__ . ":" . __LINE__ );
                @cl_CPU_usage_MHz = @values;

              }
            }
          }
        }
      }
    }

    if ($error_select_counters) {
      print "success_metric : $success_metric (" . $$ . "F$server_count)\n";
    }

    # $real_sampling_period is < 20 .. $real_sampling_period_limit>
    # for counters of 'summation' type it is necessary to divide values, cus we store and graph all values as real-time values - 20 secs
    # e.g. CPU_ready for VMs
    # print "3702 \$real_sampling_period $real_sampling_period\n";
    my $update_time_step_divider = $real_sampling_period / 20;

    my $update_string     = "";
    my $two_update_string = "";
    my $one_update;
    my $two_update;
    my $vm_metrics = "";

    if ( $entity_type eq $et_VirtualMachine ) {
      if ( $update_time_step_divider != 1 ) {
        error( "(" . $$ . "F$server_count) just info \$update_time_step_divider = $update_time_step_divider $fail_entity_type: $fail_entity_name " . __FILE__ . ":" . __LINE__ );
      }
    }

    for ( my $i = 0; $i < $samples_number; $i++ ) {
      $update_string .= "$vm_time_stamps[$i],";
      $vm_metrics    .= "$vm_time_stamps[$i],";

      #          $two_update_string .= "$vm_time_stamps[$i],";

      my $diff_item = "U";
      if ( ( $entity_type eq $et_HostSystem ) || ( $entity_type eq $et_VirtualMachine ) ) {
        if ( $entity_type eq $et_HostSystem ) {
          $diff_item = $Host_memory_size[$i];    #Bytes
        }
        if ( $entity_type eq $et_VirtualMachine ) {
          $diff_item = $numCpu;
          if ( $update_time_step_divider != 1 ) {
            $vm_CPU_ready_ms[$i] /= $update_time_step_divider;
          }
        }
        my $mil = "1000000";
        my $kb  = "1024";
        my $mb  = 1024 * 1024;
        if ($NG) {

          # $one_update = $vm_CPU_Alloc_reservation[$i]/$mil .",". $vm_CPU_usage_MHz[$i]/$mil .",". "$vm_host_hz[$i],";
          $one_update = ( ( $vm_CPU_Alloc_reservation[$i] ne "U" ) ? $vm_CPU_Alloc_reservation[$i] * $mil : $vm_CPU_Alloc_reservation[$i] ) . ",";
          $one_update .= ( ( $vm_CPU_usage_MHz[$i] / $mil ne "U" ) ? $vm_CPU_usage_MHz[$i] * $mil : $vm_CPU_usage_MHz[$i] ) . ",";
          $one_update .= "$vm_host_hz[$i],";

          # $one_update    .= $vm_Memory_active_KB[$i]*$kb .",". $vm_Memory_granted_KB[$i]*$kb .",". $vm_Memory_baloon_MB[$i]*$kb .",";
          $one_update .= ( ( $vm_Memory_active_KB[$i] ne "U" )  ? $vm_Memory_active_KB[$i] * $kb  : $vm_Memory_active_KB[$i] ) . ",";
          $one_update .= ( ( $vm_Memory_granted_KB[$i] ne "U" ) ? $vm_Memory_granted_KB[$i] * $kb : $vm_Memory_granted_KB[$i] ) . ",";
          $one_update .= ( ( $vm_Memory_baloon_MB[$i] ne "U" )  ? $vm_Memory_baloon_MB[$i] * $mb  : $vm_Memory_baloon_MB[$i] ) . ",";

          # $one_update    .= $vm_Disk_usage_KBps[$i]*$kb .",". $vm_Disk_read_KBps[$i]*$kb .",". $vm_Disk_write_KBps[$i]*$kb .",";
          $one_update .= ( ( $vm_Disk_usage_KBps[$i] ne "U" ) ? $vm_Disk_usage_KBps[$i] * $kb : $vm_Disk_usage_KBps[$i] ) . ",";
          $one_update .= ( ( $vm_Disk_read_KBps[$i] ne "U" )  ? $vm_Disk_read_KBps[$i] * $kb  : $vm_Disk_read_KBps[$i] ) . ",";
          $one_update .= ( ( $vm_Disk_write_KBps[$i] ne "U" ) ? $vm_Disk_write_KBps[$i] * $kb : $vm_Disk_write_KBps[$i] ) . ",";

          # $one_update    .= $vm_Network_usage_KBps[$i]*$kb .",". $vm_Network_received_KBps[$i]*$kb .",". $vm_Network_transmitted_KBps[$i]*$kb .",";
          $one_update .= ( ( $vm_Network_usage_KBps[$i] ne "U" )       ? $vm_Network_usage_KBps[$i] * $kb       : $vm_Network_usage_KBps[$i] ) . ",";
          $one_update .= ( ( $vm_Network_received_KBps[$i] ne "U" )    ? $vm_Network_received_KBps[$i] * $kb    : $vm_Network_received_KBps[$i] ) . ",";
          $one_update .= ( ( $vm_Network_transmitted_KBps[$i] ne "U" ) ? $vm_Network_transmitted_KBps[$i] * $kb : $vm_Network_transmitted_KBps[$i] ) . ",";

          # $one_update    .= $vm_Memory_swapin_KBps[$i]*$kb .",". $vm_Memory_swapout_KBps[$i]*$kb .",";
          $one_update .= ( ( $vm_Memory_swapin_KBps[$i] ne "U" )  ? $vm_Memory_swapin_KBps[$i] * $kb  : $vm_Memory_swapin_KBps[$i] ) . ",";
          $one_update .= ( ( $vm_Memory_swapout_KBps[$i] ne "U" ) ? $vm_Memory_swapout_KBps[$i] * $kb : $vm_Memory_swapout_KBps[$i] ) . ",";

          # $one_update    .= $vm_Memory_compres_KBps[$i]*$kb .",". $vm_Memory_decompres_KBps[$i]*$kb .",". "$vm_CPU_usage_Percent[$i],$diff_item," . $vm_CPU_ready_ms[$i]/1000;
          $one_update .= ( ( $vm_Memory_compres_KBps[$i] ne "U" )   ? $vm_Memory_compres_KBps[$i] * $kb   : $vm_Memory_compres_KBps[$i] ) . ",";
          $one_update .= ( ( $vm_Memory_decompres_KBps[$i] ne "U" ) ? $vm_Memory_decompres_KBps[$i] * $kb : $vm_Memory_decompres_KBps[$i] ) . ",";

          # $one_update    .= "$vm_CPU_usage_Percent[$i],$diff_item,";
          $one_update .= ( ( $vm_CPU_usage_Percent[$i] ne "U" ) ? $vm_CPU_usage_Percent[$i] / 100 : $vm_CPU_usage_Percent[$i] ) . ",";
          $one_update .= "$diff_item,";
          $one_update .= ( ( $vm_CPU_ready_ms[$i] ne "U" ) ? $vm_CPU_ready_ms[$i] / 1000 : $vm_CPU_ready_ms[$i] );
          if ( $entity_type eq $et_HostSystem ) {
            $one_update .= ",$vm_Memory_consumed_KB[$i]";    # it is actually Power_usage_Watt[$i]";
          }
          $update_string .= "$one_update ";
          if ( $entity_type eq $et_VirtualMachine ) {
            if ( $vm_Memory_consumed_KB[$i] eq "U" ) {
              $vm_metrics .= "$one_update," . $vm_Memory_consumed_KB[$i] . "," . "$vm_Power_usage_Watt[$i] ";
            }
            else {
              $vm_metrics .= "$one_update," . $vm_Memory_consumed_KB[$i] * $kb . "," . "$vm_Power_usage_Watt[$i] ";
            }
          }
        }
        else {
          $one_update = "$vm_CPU_Alloc_reservation[$i],$vm_CPU_usage_MHz[$i],$vm_host_hz[$i],";
          $one_update .= "$vm_Memory_active_KB[$i],$vm_Memory_granted_KB[$i],$vm_Memory_baloon_MB[$i],";
          $one_update .= "$vm_Disk_usage_KBps[$i],$vm_Disk_read_KBps[$i],$vm_Disk_write_KBps[$i],";
          $one_update .= "$vm_Network_usage_KBps[$i],$vm_Network_received_KBps[$i],$vm_Network_transmitted_KBps[$i],";
          $one_update .= "$vm_Memory_swapin_KBps[$i],$vm_Memory_swapout_KBps[$i],";
          $one_update .= "$vm_Memory_compres_KBps[$i],$vm_Memory_decompres_KBps[$i],$vm_CPU_usage_Percent[$i],$diff_item,$vm_CPU_ready_ms[$i]";
          if ( $entity_type eq $et_HostSystem ) {
            $one_update .= ",$vm_Memory_consumed_KB[$i]";    # it is actually Power_usage_Watt[$i]";
          }
          $update_string .= "$one_update ";
          if ( $entity_type eq $et_VirtualMachine ) {
            $vm_metrics .= "$one_update,$vm_Memory_consumed_KB[$i],$vm_Power_usage_Watt[$i] ";
          }
        }
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
        $one_update    .= "$cl_mem_limit[$i],$cl_mem_reservation[$i],U ";                                       # U for added CPU proc
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
        error( "(" . $$ . "F$server_count) unknown entity type $entity_type $fail_entity_type: $fail_entity_name " . __FILE__ . ":" . __LINE__ ) && exit 0;
      }
    }

    # print "string for RRD file update is:\n$update_string,xorux_sentinel\n";
    # print "---------------------------------------------------\n\n";

    $SSH = "";
    my $entity_name_without_coma = $entity->name;

    # remove coma ',' because we use it as field separator
    $entity_name_without_coma =~ s/,//g;
    my $input_vm_uuid = $vm_name_uuid{$entity_name_without_coma};

    if ( $entity_type eq 'HostSystem' ) {
      $input_vm_uuid = 'pool';
      $SSH           = $entity->{'mo_ref'}->value;
      $SDMC          = $vmware_uuid;
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

    my $managedname_save = $managedname;
    my $host_save        = $host;
    if ( $entity_type eq $et_VirtualMachine ) {
      $managedname_save = "vmware_VMs";
      $host_save        = "";
      $last_file        = "$input_vm_uuid.last";
    }

    if ( $entity_type ne $et_Datastore ) {

      #      my $res_update = LoadDataModuleVMWare::load_data( $managedname_save, $host_save, $wrkdir, \$update_string, $type_sam, $act_time, $HMC, $IVM, $SDMC, $step, $DEBUG, \@lpar_trans, $last_file, $no_time, $SSH, $hmc_user, $input_vm_uuid, $entity_type, "(".$$."F$server_count)" );
      if ( $i_am_fork eq "fork" ) {
        print "update_line,$managedname_save,$host_save,$wrkdir,\$update_string,$type_sam,$act_time,$HMC,$IVM,$SDMC,$step,$DEBUG,\@lpar_trans,$last_file,$no_time,$SSH,$hmc_user,$input_vm_uuid,$entity_type,(" . $$ . "F$server_count),$update_string,xorux_sentinel\n";
      }
      else {
        push @all_vcenter_perf_data, "update_line,$managedname_save,$host_save,$wrkdir,\$update_string,$type_sam,$act_time,$HMC,$IVM,$SDMC,$step,$DEBUG,\@lpar_trans,$last_file,$no_time,$SSH,$hmc_user,$input_vm_uuid,$entity_type,(" . $$ . "F$server_count),$update_string,xorux_sentinel\n";
      }
      if ( $entity_type eq $et_VirtualMachine ) {

        # save VM data for later use
        if ( $i_am_fork eq 'fork' ) {
          print "vm_counter_data $input_vm_uuid $vm_metrics\n";    # will be collected to %vm_hash when reading forks output
        }
        else {
          if ( $first_vm_counter_data eq "" ) {
            $first_vm_counter_data = "$input_vm_uuid $vm_metrics";
            print "4493 filling \$first_vm_counter_data $first_vm_counter_data\n";
          }

          # push @vm_counter_data, "$input_vm_uuid $vm_metrics";
          $vm_hash{$input_vm_uuid} = $vm_metrics;
        }
      }
      return;
    }

    # here only datastore
    my $long_time = $no_time * 5;
    if ( ( $entity_type eq $et_Datastore ) && ( $apiType_top =~ "HostAgent" ) ) {    # only for DA by ESXi 4
      $type_sam      = "s";
      $update_string = $two_update_string;

      #      my $res_update = LoadDataModuleVMWare::load_data( $managedname_save, $host_save, $wrkdir, \$update_string, $type_sam, $act_time, $HMC, $IVM, $SDMC, $step, $DEBUG, \@lpar_trans, $last_file, $no_time * 5, $SSH, $hmc_user, $input_vm_uuid, $entity_type, "(".$$."F$server_count)" );
      if ( $i_am_fork eq "fork" ) {
        print "update_line,$managedname_save,$host_save,$wrkdir,\$update_string,$type_sam,$act_time,$HMC,$IVM,$SDMC,$step,$DEBUG,\@lpar_trans,$last_file,$long_time,$SSH,$hmc_user,$input_vm_uuid,$entity_type,(" . $$ . "F$server_count),$update_string,xorux_sentinel\n";
      }
      else {
        push @all_vcenter_perf_data, "update_line,$managedname_save,$host_save,$wrkdir,\$update_string,$type_sam,$act_time,$HMC,$IVM,$SDMC,$step,$DEBUG,\@lpar_trans,$last_file,$long_time,$SSH,$hmc_user,$input_vm_uuid,$entity_type,(" . $$ . "F$server_count),$update_string,xorux_sentinel\n";
      }
    }
    else {
      if ( ( $entity_type eq $et_Datastore ) && ( $two_update_string ne "" ) ) {

        # print "4764 vmw2rrd.pl result update string $update_string 2 upd $two_update_string,xorux_sentinel\n";
        #        my $res_update = LoadDataModuleVMWare::load_data( $managedname_save, $host_save, $wrkdir, \$update_string, $type_sam, $act_time, $HMC, $IVM, $SDMC, $step, $DEBUG, \@lpar_trans, $last_file, $no_time, $SSH, $hmc_user, $input_vm_uuid, $entity_type, "(".$$."F$server_count)" );
        if ( $i_am_fork eq "fork" ) {
          print "update_line,$managedname_save,$host_save,$wrkdir,\$update_string,$type_sam,$act_time,$HMC,$IVM,$SDMC,$step,$DEBUG,\@lpar_trans,$last_file,$no_time,$SSH,$hmc_user,$input_vm_uuid,$entity_type,(" . $$ . "F$server_count),$update_string,xorux_sentinel\n";
        }
        else {
          push @all_vcenter_perf_data, "update_line,$managedname_save,$host_save,$wrkdir,\$update_string,$type_sam,$act_time,$HMC,$IVM,$SDMC,$step,$DEBUG,\@lpar_trans,$last_file,$no_time,$SSH,$hmc_user,$input_vm_uuid,$entity_type,(" . $$ . "F$server_count),$update_string,xorux_sentinel\n";
        }

        #        if ( $res_update != $no_inserted ) left_curly  # go on only when success
        if (1) {
          $type_sam      = "s";                  # irregular update - usually once in 30 mins
                                                 # using very long heartbeat time !!!
          $update_string = $two_update_string;

          #          eval {
          #            $res_update    = LoadDataModuleVMWare::load_data( $managedname_save, $host_save, $wrkdir, \$update_string, $type_sam, $act_time, $HMC, $IVM, $SDMC, $step, $DEBUG, \@lpar_trans, $last_file, $no_time * 5, $SSH, $hmc_user, $input_vm_uuid, $entity_type, "(".$$."F$server_count)" );
          #          };
          #          if ($@) {
          #            my $ret = $@;
          #            chomp($ret);
          #            error( "vmw2rrd failed during datastore update : $ret " . __FILE__ . ":" . __LINE__ );
          #            # exit(1);
          #          } ## end if ($@)
          if ( $i_am_fork eq "fork" ) {
            print "update_line,$managedname_save,$host_save,$wrkdir,\$update_string,$type_sam,$act_time,$HMC,$IVM,$SDMC,$step,$DEBUG,\@lpar_trans,$last_file,$long_time,$SSH,$hmc_user,$input_vm_uuid,$entity_type,(" . $$ . "F$server_count),$update_string,xorux_sentinel\n";
          }
          else {
            push @all_vcenter_perf_data, "update_line,$managedname_save,$host_save,$wrkdir,\$update_string,$type_sam,$act_time,$HMC,$IVM,$SDMC,$step,$DEBUG,\@lpar_trans,$last_file,$long_time,$SSH,$hmc_user,$input_vm_uuid,$entity_type,(" . $$ . "F$server_count),$update_string,xorux_sentinel\n";
          }
        }
      }
    }

    #         print "LoadDataModuleVMWare::load_data ($managedname_save,$host_save,$wrkdir,\$update_string,$type_sam,$act_time,$HMC,$IVM,$SDMC,$step,$DEBUG,\@lpar_trans,$last_file,$no_time,$SSH,$hmc_user,$input_vm_uuid,$entity_type,(".$$."F$server_count));\n";

    #	      print "ifinish if $entity_type\n";
    #          print "one $update_string two $two_update_string,xorux_sentinel\n";
    #          return
    last if $spec_routine;
  }
}

sub cluster_active_VMs {
  my $wrkdir       = shift;
  my $cluster_path = shift;
  my $VMs_list     = shift;    # external arr to fill

  my $hosts_in_cluster_file = "$wrkdir/$cluster_path/hosts_in_cluster";
  return if !-f $hosts_in_cluster_file;

  open my $FH, "<$hosts_in_cluster_file" or error( "can't open $hosts_in_cluster_file: $!" . __FILE__ . ":" . __LINE__ ) && return;
  my @hosts_in_cluster = <$FH>;
  close $FH;

  foreach (@hosts_in_cluster) {
    my $host_in_cluster = $_;
    chomp $host_in_cluster;
    ( my $server, my $host ) = split( "XORUX", $host_in_cluster );
    ( my $vm_hosting ) = "$wrkdir/$server/$host/VM_hosting.vmh";

    # print "3973 \$host $host \$server $server \$vm_hosting $vm_hosting\n";
    if ( !-f $vm_hosting ) {
      error( "file $vm_hosting not detected " . __FILE__ . ":" . __LINE__ ) && next;
    }
    open my $FH, "<$vm_hosting" or error( "can't open $vm_hosting : $!" . __FILE__ . ":" . __LINE__ ) && next;
    foreach (<$FH>) {
      my $line = $_;
      chomp $line;
      if ( $line =~ /start=\d\d\d\d\d\d\d\d\d\d$/ ) {
        ( $line, undef ) = split( ":", $line );

        # print "3980 \$line $line\n";
        push @$VMs_list, "$wrkdir/vmware_VMs/$line" . ".rrm";
      }
    }
    close $FH;

    # print "\@$VMs_list @$VMs_list\n";
  }
  return 0;
}

sub get_last_date_range {
  my ( $pef_time_sec, $entity_type ) = @_;

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
  print " (" . $$ . "F$server_count)\n";

  if ( $apiType eq "HostAgent" ) {
    if ( $pef_time_sec > 3600 ) {
      $pef_time_sec = 3600 * 18;
    }
  }
  else {
    if ( $apiType ne "VirtualCenter" ) {
      error( "(" . $$ . "F$server_count) unknown apiType $apiType " . $service_instance->about->fullName . __FILE__ . ":" . __LINE__ ) && return 0;
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

    #   if ($pef_time_sec > 3600) {
    #     $pef_time_sec = 3500;
    #   }
  }

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
  my $st_time  = $end_time - $pef_time_sec;

  # print "4374 \$end_time $end_time \$st_time $st_time \$pef_time_sec $pef_time_sec\n";

  my ( $sec, $min, $hour, $day, $month, $year, $wday, $yday, $isdst ) = localtime($st_time);
  $year += 1900;
  $month++;
  $month = "0" . $month if $month < 10;
  $day   = "0" . $day   if $day < 10;
  $hour  = "0" . $hour  if $hour < 10;
  $min   = "0" . $min   if $min < 10;
  $sec   = "0" . $sec   if $sec < 10;

  my $st_date = $year . "-" . $month . "-" . $day . "T" . $hour . ":" . $min . ":" . $sec;

  # print "4387 \$end_date $end_date \$st_date $st_date\n";

  return ( $st_date, $end_date, $pef_time_sec );
}

sub prepare_vm_metric {
  my $entity_type = shift;
  my $perf_metric = shift;

  my $perf_values = $perf_metric->value;

  # print "\$perf_values $perf_values\n";
  my $counter = $all_counters->{ $perf_metric->id->counterId };

  if ( !defined $counter ) {
    print "asking ";
    $counter = $perf_metric->id->counterId;
    $counter = $perfmgr_view->QueryPerfCounter( counterId => $counter );
    print Dumper( "3926", $counter );

    $counter = $counter->[0];
  }

  # print Dumper("2831", $counter);
  my $group_info = $counter->groupInfo->label;
  my $nameInfo   = $counter->nameInfo->key;
  my $unitInfo   = $counter->unitInfo->label;
  my $rollupType = $counter->rollupType->val;

  if ( ( !defined $group_info ) || ( !defined $nameInfo ) || ( !defined $unitInfo ) ) {
    print "counter items \$group_info or \$nameInfo or \$unitInfo not defined (" . $$ . "F$server_count)\n";
    return 0;
  }

  if ( !defined $rollupType ) {
    print "counter $group_info $nameInfo $unitInfo : not defined rollupType (" . $$ . "F$server_count)\n";
    return 0;
  }

  # for the case of all real counters
  if ( $entity_type ne $et_Datastore ) {
    if ( $rollupType eq 'summation' && ( $group_info eq 'CPU' || $group_info eq 'disk' ) ) {

      # let it go
    }
    elsif ( $rollupType ne 'average' ) { return 0 }
  }

  #  print "counter: " . $counter->key . " $group_info $nameInfo $unitInfo $rollupType\n" if $entity_type eq $et_Datastore;
  #       print "2424 counter: " . $counter->key . " $group_info $nameInfo $unitInfo $rollupType\n" if $entity_type eq $et_VirtualMachine;
  #       print "2425 counter: " . $counter->key . " $group_info $nameInfo $unitInfo $rollupType\n" if $entity_type eq $et_HostSystem;
  #       print "2735 counter: " . $counter->key . " $group_info $nameInfo $unitInfo $rollupType\n" if $entity_type eq $et_Datastore;
  #       print "2427 counter: " . $counter->key . " $group_info $nameInfo $unitInfo $rollupType\n" if $entity_type eq $et_ResourcePool;
  #       print "2428 counter: " . $counter->key . " $group_info $nameInfo $unitInfo $rollupType\n" if $entity_type eq $et_ClusterComputeResource;

  # my $factor = 1;   #only used for percent

  my $rep = $samples_number - 1;

  # test if all numbers are OK
  # sometimes, some values are not defined   0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,-1,-1,-1,-1,-1
  # instead -1 prepare U
  # if all items are U then print err, do not update
  my $res = ( $perf_values =~ /([0-9]+,){$rep}[0-9]+/ );

  # print "\$rep $rep \$res $res \n";
  if ( $res != 1 ) {
    my $info_value = "length of value=" . length($perf_values) . " " . $perf_values;
    $perf_values =~ s/\-1$/U/;
    $perf_values =~ s/\-1,/U,/g;
    $res = ( $perf_values =~ /(U,){$rep}U/ );

    #error ( "probably -1 ".$perf_values."\n");
    my $res1 = ( $perf_values =~ /([0-9]+,|U,){$rep}[0-9]+|U/ );
    if ( $res == 1 || $res1 != 1 ) {
      error( "(" . $$ . "F$server_count) error: not numbers for counter: $group_info $nameInfo $unitInfo $info_value $fail_entity_type:$fail_entity_name " . __FILE__ . ":" . __LINE__ ) && return 0;
    }
  }

  # print Dumper($counter);

  my $test_item = $group_info . ":" . $nameInfo . ":" . $unitInfo;

  if ( $entity_type eq $et_VirtualMachine ) {

    # print "......... $test_item\n";
    my ($index) = grep { $counter_vm_eng[$_] eq $test_item } 0 .. $#counter_vm_eng;    # is it needed counter ?

    if ( !defined $index ) {                                                           # try version 6
      ($index) = grep { $counter_vm_eng6[$_] eq $test_item } 0 .. $#counter_vm_eng6;
    }
    if ( !defined $index ) {                                                           # try other languages
      ($index) = grep { $counter_vm_ger1[$_] eq $test_item } 0 .. $#counter_vm_ger1;
    }
    if ( !defined $index ) {                                                           # try other languages
      ($index) = grep { $counter_vm_ger2[$_] eq $test_item } 0 .. $#counter_vm_ger2;
    }
    if ( !defined $index ) {                                                           # try other languages
      ($index) = grep { $counter_vm_fr[$_] eq $test_item } 0 .. $#counter_vm_fr;
    }
    if ( !defined $index ) {                                                           # try other languages
      ($index) = grep { $counter_vm_esp[$_] eq $test_item } 0 .. $#counter_vm_esp;
    }

    if ( defined $index ) {

      #         if ($index == 3) { # as if 'Disk:write:KBps' not present
      #			return;
      #		 }

      my $po_po = $$pointer_arr[$index];
      @$po_po = split( ',', $perf_values );
      $counter_presence[$index] = 1;
      return 1;
    }
  }
  if ( $entity_type eq $et_HostSystem ) {

    # print "......... $test_item\n";
    my ($index) = grep { $counter_hs_eng[$_] eq $test_item } 0 .. $#counter_hs_eng;    # is it needed counter ?

    if ( !defined $index ) {                                                           # try version 6
      ($index) = grep { $counter_hs_eng6[$_] eq $test_item } 0 .. $#counter_hs_eng6;
    }
    if ( !defined $index ) {                                                           # try other languages
      ($index) = grep { $counter_hs_ger1[$_] eq $test_item } 0 .. $#counter_hs_ger1;
    }
    if ( !defined $index ) {                                                           # try other languages
      ($index) = grep { $counter_hs_ger2[$_] eq $test_item } 0 .. $#counter_hs_ger2;
    }
    if ( !defined $index ) {                                                           # try other languages
      ($index) = grep { $counter_hs_fr[$_] eq $test_item } 0 .. $#counter_hs_fr;
    }
    if ( !defined $index ) {                                                           # try other languages
      ($index) = grep { $counter_hs_esp[$_] eq $test_item } 0 .. $#counter_hs_esp;
    }

    if ( defined $index ) {

      #         if ($index == 3) { # as if 'Disk:write:KBps' not present
      #			return;
      #		 }
      #         if (($entity_type eq "HostSystem") && ($index == 10)) { # do not write balloon for HostSystem
      #		   return 1;
      #	     }

      my $po_po = $$pointer_arr[$index];
      @$po_po = split( ',', $perf_values );
      $counter_presence[$index] = 1;
      return 1;
    }
  }

  if ( $entity_type eq $et_ClusterComputeResource ) {
    my ($index) = grep { $counter_cl_eng[$_] eq $test_item } 0 .. $#counter_cl_eng;    # is it needed counter ?

    if ( !defined $index ) {                                                           # try version 6
      ($index) = grep { $counter_cl_eng6[$_] eq $test_item } 0 .. $#counter_cl_eng6;
    }
    if ( !defined $index ) {                                                           # try other languages
      ($index) = grep { $counter_cl_ger[$_] eq $test_item } 0 .. $#counter_cl_ger;
    }
    if ( !defined $index ) {                                                           # try other languages
      ($index) = grep { $counter_cl_ger6[$_] eq $test_item } 0 .. $#counter_cl_ger6;
    }
    if ( !defined $index ) {                                                           # try other languages
      ($index) = grep { $counter_cl_fr[$_] eq $test_item } 0 .. $#counter_cl_fr;
    }

    # print "cluster counter\n";
    if ( defined $index ) {
      my $po_po = $$pointer_arr[$index];
      @$po_po = split( ',', $perf_values );

      # want to print individual counter ?
      # if ($test_item eq "Memory:totalmb:MB") { print Dumper($perf_values); }
      $counter_presence[$index] = 1;
      return 1;
    }
  }
  if ( $entity_type eq $et_ResourcePool ) {
    my ($index) = grep { $counter_rp_eng[$_] eq $test_item } 0 .. $#counter_rp_eng;    # is it needed counter ?

    if ( !defined $index ) {                                                           # try other languages
      ($index) = grep { $counter_rp_ger[$_] eq $test_item } 0 .. $#counter_rp_ger;
    }
    if ( !defined $index ) {                                                           # try other languages
      ($index) = grep { $counter_rp_fr[$_] eq $test_item } 0 .. $#counter_rp_fr;
    }

    # print "resourcepool counter\n";
    if ( defined $index ) {
      my $po_po = $$pointer_arr[$index];
      @$po_po = split( ',', $perf_values );

      # want to print individual counter ?
      # if ($test_item eq "Memory:totalmb:MB") { print Dumper($perf_values); }
      $counter_presence[$index] = 1;
      return 1;
    }
  }
  if ( $entity_type eq $et_Datastore ) {
    my ($index) = grep { $counter_ds_eng[$_] eq $test_item } 0 .. $#counter_ds_eng;    # is it needed counter ?

    if ( !defined $index ) {                                                           # try version 6
      ($index) = grep { $counter_ds_eng6[$_] eq $test_item } 0 .. $#counter_ds_eng6;
    }
    if ( !defined $index ) {                                                           # try other languages
      ($index) = grep { $counter_ds_ger[$_] eq $test_item } 0 .. $#counter_ds_ger;
    }
    if ( !defined $index ) {                                                           # try other languages
      ($index) = grep { $counter_ds_fr[$_] eq $test_item } 0 .. $#counter_ds_fr;
    }

    # print "datastore counter\n";
    if ( defined $index ) {
      my $po_po = $$pointer_arr[$index];
      @$po_po = split( ',', $perf_values );

      # want to print individual counter ?
      # if ($test_item eq "Memory:totalmb:MB") { print Dumper($perf_values); }
      $counter_presence[$index] = 1;
      return 1;
    }
  }

  error( "(" . $$ . "F$server_count) unknown counter: ,$group_info, ,$nameInfo, ,$unitInfo, " . __FILE__ . ":" . __LINE__ ) && return 0;
  return 0;
}

sub init_perf_counter_info {
  my $entity_type = shift;

  %{$now_counters} = ();
  %{$all_counters} = ();

  eval { $perfmgr_view = Vim::get_view( mo_ref => Vim::get_service_content()->perfManager ); };
  if ($@) {
    my $ret = $@;
    chomp($ret);
    error( "vmw2rrd failed \$perfmgr_view : $ret " . __FILE__ . ":" . __LINE__ );

    #  exit(1);
  }

  my $perfCounterInfo = $perfmgr_view->perfCounter;
  my $ci              = 0;                            # how many counters chosen

  # print Dumper "\@$perfCounterInfo\n"; # does not show what you need even without backslash

  # prepare test array of counters for VM
  my @counter_arr = ( 'cpu:usagemhz', 'disk:usage', 'disk:read', 'disk:write', 'net:usage', 'net:received', 'net:transmitted', 'mem:active', 'mem:granted', 'mem:swapinRate', 'mem:vmmemctl', 'mem:swapoutRate', 'mem:decompressionRate', 'mem:compressionRate', 'cpu:usage', 'cpu:ready', 'mem:consumed', 'datastore:numberReadAveraged', 'datastore:numberWriteAveraged', 'datastore:read', 'datastore:write', 'datastore:totalReadLatency', 'datastore:totalWriteLatency' );

  $selected_counters = 23;

  # want to print info $host ?
  # print "init_perf_counter_info \$host $host\n";

  # prepare test array of counters for HS
  if ( $entity_type eq $et_HostSystem ) {
    @counter_arr       = ( 'cpu:usagemhz', 'disk:usage', 'disk:read', 'disk:write', 'net:usage', 'net:received', 'net:transmitted', 'mem:active', 'mem:granted', 'mem:swapinRate', 'mem:vmmemctl', 'mem:swapoutRate', 'mem:decompressionRate', 'mem:compressionRate', 'cpu:usage', 'cpu:ready', 'power:power' );
    $selected_counters = 17;
  }

  if ( $entity_type eq $et_ClusterComputeResource ) {

    # do not take 'power:energy'
    # vmmemctl = balloon

    # since 4.92 only 18 counters
    @counter_arr       = ( 'cpu:usagemhz', 'cpu:usage', 'cpu:reservedCapacity', 'cpu:totalmhz', 'mem:totalmb', 'mem:shared', 'mem:zero', 'mem:vmmemctl', 'mem:consumed', 'mem:active', 'mem:granted', 'mem:compressed', 'mem:reservedCapacity', 'mem:swapused', 'mem:compressionRate', 'mem:decompressionRate', 'power:powerCap', 'power:power' );
    $selected_counters = 18;

    # @counter_arr = ('cpu:usagemhz','cpu:usage','cpu:reservedCapacity','cpu:totalmhz',
    #               'clusterServices:effectivecpu','clusterServices:effectivemem',
    #               'mem:totalmb','mem:shared','mem:zero','mem:vmmemctl','mem:consumed','mem:overhead',
    #               'mem:active','mem:granted','mem:compressed','mem:reservedCapacity',
    #               'mem:swapused','mem:compressionRate','mem:decompressionRate','mem:usage',
    #		           'power:powerCap','power:power'
    #                );
    #$selected_counters = 22;

    # if ( $fullName_top =~ 'vCenter Server 6') {
    #   @counter_arr = ('cpu:usagemhz','cpu:usage','cpu:reservedCapacity',
    #                'mem:shared','mem:zero','mem:consumed','mem:overhead',
    #                'mem:active','mem:granted','mem:compressed','mem:reservedCapacity',
    # 			          'mem:decompressionRate','mem:compressionRate','mem:vmmemctl',
    # 		            'mem:usage',
    #			          'power:power','power:powerCap'
    #                );
    #  $selected_counters = 17;
    # 'cpu:totalmhz',
    # 'clusterServices:effectivecpu','clusterServices:effectivemem',
    # 'mem:totalmb',
    # 'mem:swapused'
    # }
  }

  if ( $entity_type eq $et_ResourcePool ) {

    # do not take 'power:energy'
    # vmmemctl = balloon
    @counter_arr       = ( 'cpu:usagemhz', 'mem:shared', 'mem:zero', 'mem:vmmemctl', 'mem:consumed', 'mem:overhead', 'mem:active', 'mem:granted', 'mem:compressed', 'mem:swapped', 'mem:compressionRate', 'mem:decompressionRate' );
    $selected_counters = 12;

    #if ( $fullName_top =~ 'vCenter Server 6') {
    #  @counter_arr = (
    #                 'mem:shared','mem:zero','mem:consumed','mem:overhead',
    #                 'mem:active','mem:granted','mem:compressed',
    #                 'mem:swapped','mem:decompressionRate','mem:compressionRate','mem:vmmemctl'
    #                );
    #  $selected_counters = 11;
    # }
  }

  if ( $entity_type eq $et_Datastore ) {

    #@counter_arr = ('disk:capacity','disk:provisioned','disk:used',
    #                'datastore:read','datastore:write',
    #                'datastore:numberReadAveraged','datastore:numberWriteAveraged'
    #               );
    # 'virtualDisk:totalReadLatency','virtualDisk:totalWriteLatency'
    #$selected_counters = 7;
    @counter_arr = ( 'datastore:read', 'datastore:write', 'datastore:numberReadAveraged', 'datastore:numberWriteAveraged' );

    # 'virtualDisk:totalReadLatency','virtualDisk:totalWriteLatency'
    $selected_counters = 4;

    if ( $ds_type eq "NFS" ) {    # NFS does not provide Averaged
      @counter_arr       = ( 'datastore:read', 'datastore:write', );
      $selected_counters = 2;
    }
  }

  my @signal_arr = (0) x $selected_counters;

  @counter_arr_levels = ('empty') x $selected_counters;

  my $i_counters = 0;
  foreach (@$perfCounterInfo) {
    $i_counters++;

    # print Dumper (4397,$i_counters, $_);
    # print $i_counters.", $entity_type, "; # there exists about 7 hundred counters
    # if ($entity_type eq $et_VirtualMachine) { # this is not possible take next line
    if ( $entity_type eq '' ) {
      print Dumper( "4342", $_ );
    }

    #if ($entity_type eq $et_Datastore) left_curly
    # no test yet
    #}
    #else {
    if ( $_->rollupType->val =~ /summation/ && ( ( $_->groupInfo->key =~ /cpu/ && $_->nameInfo->key =~ /ready/ ) || ( $_->groupInfo->key =~ /disk/ && $_->nameInfo->key =~ /number/ ) ) ) {

      # print "--------- cpu or disk summation\n";
      # let it go
    }
    elsif ( $_->rollupType->val !~ /average/ ) {
      next;
    }

    # }
    my $key        = $_->key;
    my $group_info = $_->groupInfo;
    my $name_info  = $_->nameInfo;
    my $unitInfo   = $_->unitInfo;

    my $test_item = $group_info->key . ":" . $name_info->key;

    #     if ($test_item eq 'cpu:usagemhz') {  # debug test as if counter not presented
    #         xerror ("(".$$."F$server_count) --- counter cpu:usagemhz ---  ".__FILE__.":".__LINE__);
    #        print " --- counter cpu:usagemhz ---\n";
    #        print Dumper ($_);
    #     }

    #      if ($test_item eq 'net:received') { next } # debug test as if counter not presented
    #      if ($test_item eq 'power:power')  { next } # debug test as if counter not presented

    #       print "2959 \$test_item ,$test_item, " . $unitInfo->key ." \@counter_arr @counter_arr\n" if $entity_type eq $et_ClusterComputeResource;
    #       print "\$test_item ,$test_item, " . $unitInfo->key ." \@counter_arr @counter_arr\n" if $entity_type eq $et_Datastore;
    #       print "\$test_item ,$test_item, " . $unitInfo->key ." \@counter_arr @counter_arr\n" if $entity_type eq $et_VirtualMachine; # do not work !
    my ($index) = grep { $counter_arr[$_] eq $test_item } 0 .. $#counter_arr;    # is it needed counter ?
    if ( !defined $index ) {

      # print "not defined for $test_item in arr @counter_arr\n";
      next;
    }

    # if ($group_info->key eq 'mem' && $unitInfo->key eq 'percent') { next }
    # if ($group_info->key eq 'cpu' && $unitInfo->key eq 'percent') { next } # test for counted % for CPU_usage_percent

    $now_counters->{$key} = $_;
    $all_counters->{$key} = $_;

    # print "4281 \$test_item $test_item\n";
    # print Dumper("4282",$_);

    if ( $entity_type eq $et_VirtualMachine ) {

      # print "3926 testing spec run \$vm_dstr_readAveraged_key $vm_dstr_readAveraged_key \$key $key \$test_item $test_item\n";
      if ( $test_item eq 'datastore:numberReadAveraged' && $vm_dstr_readAveraged_key eq "9999" ) {
        $vm_dstr_readAveraged_key = $key;

        # print "3732 vmw2rrd.pl \$vm_dstr_readAveraged_key $vm_dstr_readAveraged_key\n";
      }
      $vm_dstr_writeAveraged_key = $key if $test_item eq 'datastore:numberWriteAveraged' && $vm_dstr_writeAveraged_key eq "9999";
      $vm_dstr_read_key          = $key if $test_item eq 'datastore:read'                && $vm_dstr_read_key eq "9999";
      $vm_dstr_write_key         = $key if $test_item eq 'datastore:write'               && $vm_dstr_write_key eq "9999";
      $vm_dstr_writeLatency_key  = $key if $test_item eq 'datastore:totalWriteLatency'   && $vm_dstr_writeLatency_key eq "9999";
      $vm_dstr_readLatency_key   = $key if $test_item eq 'datastore:totalReadLatency'    && $vm_dstr_readLatency_key eq "9999";
    }

    $signal_arr[$index]++;

    my $level_info = ",,";
    if ( defined $_->level ) { $level_info = $_->level }
    my $perdevicelevel_info = ",,";
    if ( defined $_->perDeviceLevel ) { $perdevicelevel_info = $_->perDeviceLevel }
    $counter_arr_levels[$index] = "$level_info $perdevicelevel_info";

    $ci++;
  }

  # print Dumper('3195',@counter_arr_levels);
  my $count = keys %$now_counters;
  if ( $count != $selected_counters ) {
    xerror( "(" . $$ . "F$server_count) counter items  :$count ?? should be $selected_counters host: $h_name,$entity_type  " . __FILE__ . ":" . __LINE__ );

    # print Dumper($now_counters);
    # print Dumper(@counter_arr);
    $error_select_counters++;
  }

  # are there more similar counters ?
  if ( $count != $ci ) {
    xerror( "(" . $$ . "F$server_count) more counters  :chosen than expected $ci > $count host: $h_name,$entity_type " . __FILE__ . ":" . __LINE__ );
    $error_select_counters++;
  }

  # each counter must be exactly 1 times
  for ( my $i = 0; $i < $selected_counters; $i++ ) {
    if ( $signal_arr[$i] == 0 ) {
      xerror( "(" . $$ . "F$server_count) counter problem  :$counter_arr[$i] not presented host: $h_name,$entity_type " . __FILE__ . ":" . __LINE__ );
      $error_select_counters++;
    }
    if ( $signal_arr[$i] > 1 ) {
      xerror( "(" . $$ . "F$server_count) counter problem  :$counter_arr[$i] presented $signal_arr[$i] times host: $h_name,$entity_type " . __FILE__ . ":" . __LINE__ );
      $error_select_counters++;
    }
  }

  # print "3183 vmw2rrd.pl ".Dumper($all_counters); # how many is selected?
}

sub filter_metric_ids {
  my ( $perf_metric_ids, $entity_type ) = @_;

  # simulate when there is no counter data, uncomment next line
  # $perf_metric_ids = ();

  # print Dumper("4443",$entity_type,$fail_entity_name,$perf_metric_ids);
  if ( !$now_counters ) {
    error( "(" . $$ . "F$server_count) unknown \$now_counters originally called for unknown init() $fail_entity_type:$fail_entity_name " . __FILE__ . ":" . __LINE__ );
  }
  my $counters = $now_counters;

  my @filtered_list;

  # if ($entity_type eq $et_ResourcePool) { }
  # if ($entity_type eq $et_VirtualMachine) {
  #   print Dumper("3088 $et_VirtualMachine", $perf_metric_ids);
  # }

  my $metric_count = 0;
  foreach (@$perf_metric_ids) {

    #       print "3100 testing ".$_->counterId." ,".$_->instance.",\n";
    if ( exists $counters->{ $_->counterId } ) {

      # test if counter 6 does not exist
      #if ($_->counterId == 6) {
      #  print "counter 6 set up\n";
      #  # $metric_count++;
      #  next;
      #}

      # delete counter we look for for this $entity(_type), and test the rest if vcenter has returned all necessary counters for this $entity(_type)
      delete $counters->{ $_->counterId };

      next if ( ( $_->instance ne '' ) && !( $entity_type eq $et_Datastore || $entity_type eq $et_VirtualMachine ) );

      # print Dumper("4368",$_);
      my @ddd = ();
      if (
        $entity_type eq $et_VirtualMachine
        && ( $_->counterId == $vm_dstr_readAveraged_key
          || $_->counterId == $vm_dstr_writeAveraged_key
          || $_->counterId == $vm_dstr_read_key
          || $_->counterId == $vm_dstr_write_key
          || $_->counterId == $vm_dstr_readLatency_key
          || $_->counterId == $vm_dstr_writeLatency_key )
        )
      {
        # print "3815 $entity_type".$_->counterId." ".$_->instance."\n";
        push @ddd, $_;
        $ddd[0]{'instance'} = '*';

        # print Dumper("4376",$_);
      }

      # filtr all counters for res-pool except 213, 214, ...
      # next if (($entity_type eq $et_ResourcePool) && !($_->counterId == 213 || $_->counterId == 214 || $_->counterId == 6 || $_->counterId == 102 || $_->counterId == 98 || $_->counterId == 29 || $_->counterId == 33 || $_->counterId == 37 || $_->counterId == 41 || $_->counterId == 70 || $_->counterId == 90 || $_->counterId == 157 || $_->counterId == 159));

      $metric_count++;

      if ( defined $ddd[0] ) {
        push @filtered_list, $ddd[0];

        # print Dumper ('4402',$ddd[0]);
      }
      else {
        next if ( $entity_type eq $et_VirtualMachine && $_->instance ne '' );
        push @filtered_list, $_;
      }
    }
  }

  # print Dumper ('4499',$counters);
  keys %$counters;    # reset the internal iterator so a prior each() doesn't affect the loop

  # sometimes cmd: $perf_metric_ids = filter_metric_ids($perfmgr_view->QueryAvailablePerfMetric(entity => $entity), $entity_type);
  # does not return all counters, which we need and which are in vcenter actually prepared
  # so we have to ask for them

  while ( my ( $c_key, $c_val ) = each %$counters ) {
    if ( $entity_type eq $et_VirtualMachine ) {
      if ( $c_key == "$vm_dstr_readLatency_key" || $c_key == "$vm_dstr_writeLatency_key" ) {
        next;    #it is solved later
      }
    }

    # create this counter and add to @filtered_list
    my $instance = "";
    if ( $c_key eq "$vm_dstr_readAveraged_key" || $c_key eq "$vm_dstr_writeAveraged_key" || $c_key eq "$vm_dstr_read_key" || $c_key eq "$vm_dstr_write_key" ) {
      $instance = "*";
    }
    my @ddd;
    $ddd[0] = bless(
      { 'counterId' => "$c_key",
        'instance'  => "$instance"
      },
      'PerfMetricId'
    );
    xerror( "(" . $$ . "F$server_count) not found counter $c_key " . $counters->{$c_key}->{nameInfo}->summary . " from $fail_entity_type:$fail_entity_name: added with instance '$instance' " . __FILE__ . ":" . __LINE__ );

    # add this counter to the list
    # print Dumper ($ddd[0]);
    push @filtered_list, $ddd[0];
    $metric_count++;
  }

  # print "4414 \@filtered_list @filtered_list\n";
  # print "4515 \$metric_count $metric_count \$selected_counters $selected_counters\n";

  if ( $metric_count != $selected_counters ) {

    # sometimes cmd: $perf_metric_ids = filter_metric_ids($perfmgr_view->QueryAvailablePerfMetric(entity => $entity), $entity_type);
    # does not return all counters, which we need and which are in vcenter actually prepared
    # so we have to ask for them
    # test for VM if readLatency and writeLatency are here
    my @ddd = ();

    # print "4426 \$vm_dstr_readLatency_key ,$vm_dstr_readLatency_key,\n";

    if ( $entity_type eq $et_VirtualMachine ) {
      my $counterId_test = grep $_->{counterId} =~ "$vm_dstr_readLatency_key", @filtered_list;
      if ( !defined $counterId_test || $counterId_test == 0 ) {

        # add this counter to the list
        $ddd[0] = bless(
          { 'counterId' => "$vm_dstr_readLatency_key",
            'instance'  => '*'
          },
          'PerfMetricId'
        );
        push @filtered_list, $ddd[0];
        $metric_count++;
        xerror( "(" . $$ . "F$server_count) have not found counter vm_dstr_readLatency_key $vm_dstr_readLatency_key from real $fail_entity_type:$fail_entity_name: counter has been added " . __FILE__ . ":" . __LINE__ );
      }
      $counterId_test = grep $_->{counterId} =~ "$vm_dstr_writeLatency_key", @filtered_list;
      if ( !defined $counterId_test || $counterId_test == 0 ) {

        # add this counter to the list
        $ddd[0] = bless(
          { 'counterId' => "$vm_dstr_writeLatency_key",
            'instance'  => '*'
          },
          'PerfMetricId'
        );
        push @filtered_list, $ddd[0];
        $metric_count++;
        xerror( "(" . $$ . "F$server_count) have not found counter vm_dstr_writeLatency_key $vm_dstr_writeLatency_key from real $fail_entity_type:$fail_entity_name: counter has been added " . __FILE__ . ":" . __LINE__ );
      }
    }

    #     if (($metric_count != $selected_counters) && $error_select_counters) left_curly
    if ( $metric_count != $selected_counters ) {
      xerror( "(" . $$ . "F$server_count) selected counters number differs from real $selected_counters ? $metric_count $fail_entity_type:$fail_entity_name " . __FILE__ . ":" . __LINE__ );
    }
  }

  # print Dumper("4450",$entity_type,$fail_entity_name,\@filtered_list);
  return \@filtered_list;
}

sub get_available_intervals {
  my %args = @_;

  my $perfmgr_view = $args{perfmgr_view};
  my $entity       = $args{host};
  my $entity_type  = $args{entity_type};

  my $historical_intervals = $perfmgr_view->historicalInterval;

  # print Dumper($historical_intervals);
  my @intervals;

  if ( $entity_type eq $et_Datastore && $apiType_top !~ "VirtualCenter" ) {

    # do nothing
  }
  else {

    my $refreshRate = "20";    # for any case
    eval { $refreshRate = $perfmgr_view->QueryPerfProviderSummary( entity => $entity )->refreshRate; };
    if ($@) {
      my $ret = $@;
      chomp($ret);
      error( "vmw2rrd failed during refreshRate : $ret " . __FILE__ . ":" . __LINE__ );

      # exit(1);
    }

    # print Dumper("5733",$refreshRate);

    push @intervals, $refreshRate;

  }
  foreach (@$historical_intervals) {
    push @intervals, $_->samplingPeriod;
  }
  return \@intervals;
}

sub rrd_check {
  my $managedname = shift;

  # Check whether do initial or normal load
  opendir( my $DIR, "$wrkdir/$managedname/$host" ) || error( " directory does not exists : $wrkdir/$managedname/$host" . __FILE__ . ":" . __LINE__ ) && return 0;
  my @files          = ();
  my @files_unsorted = ();

  if ( $type_sam =~ "m" ) {
    @files_unsorted = grep( /\.rrm$/, readdir($DIR) );
    @files          = sort { lc $a cmp lc $b } @files_unsorted;
  }
  if ( scalar @files > 0 ) {
    closedir($DIR);
    return;
  }
  rewinddir($DIR);    # for cluster

  @files_unsorted = grep( /cluster\.rrc$/, readdir($DIR) );
  @files          = sort { lc $a cmp lc $b } @files_unsorted;

  if ( scalar @files_unsorted > 0 ) {
    closedir($DIR);
    return;
  }
  rewinddir($DIR);    # for resourcepools

  @files_unsorted = grep( /\.rrc$/, readdir($DIR) );
  @files          = sort { lc $a cmp lc $b } @files_unsorted;

  if ( scalar @files_unsorted > 0 ) {
    closedir($DIR);
    return;
  }

  rewinddir($DIR);    # for datastore

  @files_unsorted = grep( /\.rrs$/, readdir($DIR) );
  @files          = sort { lc $a cmp lc $b } @files_unsorted;

  if ( scalar @files_unsorted > 0 ) {
    closedir($DIR);
    return;
  }

  closedir($DIR);

  print "There is no RRD: $host:$managedname attempting to do initial load, be patient, it might take some time\n" if $DEBUG;

  # get last 62ays (HMC keeps hourly history data just for 2 months, not more)
  # no idea for shother sampe rates, it is not documented yet
  # it is for initial load
  # daily data it keeps for last 2years and monthly for last 10years
  # let load far enough backward for initial load (value in hours or in days)
  $loadhours = $INIT_LOAD_IN_HOURS_BACK;
  $loadmins  = $INIT_LOAD_IN_HOURS_BACK * 60;

  return 0;
}

sub FormatResults {
  my $results_unsort = shift;              # pointer
  my $align          = shift;
  $align = "center" if !defined $align;    # or let 2nd param
  my $click_through = shift;
  my $click_end     = "";
  $click_end     = "</A>" if defined $click_through;
  $click_through = ""     if !defined $click_through;

  my $line     = "";
  my $formated = "";
  my @items1   = "";
  my $item     = "";

  my @results = sort { lc $a cmp lc $b } @$results_unsort;
  foreach $line (@results) {
    chomp $line;
    @items1   = split /,/, $line;
    $formated = $formated . "<TR>";
    my $col = 0;

    # directive <B> must be here cus menu->server->view needs it
    foreach $item (@items1) {
      if ( $col == 0 ) {
        my $item_urlx = $item;
        $item_urlx =~ s/([^a-zA-Z0-9_.!~*()'\''-])/sprintf("%%%02X", ord($1))/ge;
        my $click_through_temp = $click_through;

        # $click_through_temp =~ s/lpar_fake_name/$item_urlx/;
        $formated = sprintf( "%s <TD>$click_through_temp<B>%s</B>$click_end</TD>", $formated, $item );
        $formated =~ s/fake_name/$item_urlx/;
      }
      else {
        # there can be html comment, let it be as is
        if ( $item =~ /^<!--/ ) {
          $formated .= $item;
        }
        else {
          $formated = sprintf( "%s <TD align=\"$align\" nowrap>%s</TD>", $formated, $item );
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
  my $sub_er = "$!";
  $sub_er = " : $sub_er" if $sub_er ne "";

  print "ERROR          : $text$sub_er\n";
  print STDERR "$act_time: $text$sub_er\n";

  return 1;
}

sub error_noerr {
  my $text     = shift;
  my $act_time = localtime();
  chomp($text);

  print "ERROR          : $text\n";
  print STDERR "$act_time: $text\n";

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
    print $FH " $act_time: $text\n";
    close $FH;
  }
  return 1;
}

sub save_cfg_data {
  my $managedname = shift;
  my $date        = shift;
  my $upgrade     = shift;
  my $ret         = 0;

  # print "save_cfg_data  :   sub cau cau nothing when vmware\n";
  return 0;
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
    LoadDataModuleVMWare::touch("$wrkdir/$managedname");    #must be at the end due to renaming servers
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
#sub rrdtool_graphv {
#  my $graph_cmd   = "graph";
#  my $graphv_file = "$tmpdir/graphv";
#
#  my $ansx = `$rrdtool`;
#
#  if ( index( $ansx, 'graphv' ) != -1 ) {
#
#    # graphv exists, create a file to pass it to cgi-bin commands
#    if ( !-f $graphv_file ) {
#      `touch $graphv_file`;
#    }
#  } ## end if ( index( $ansx, 'graphv'...))
#  else {
#    if ( -f $graphv_file ) {
#      unlink($graphv_file);
##    }
#  }
#
#  $graph_cmd   = "--right-axis";
#  $graphv_file = "$tmpdir/graph-right-axis";
#  $ansx        = `$rrdtool graph $graph_cmd 2>&1`;
#
#  if ( index( $ansx, "$graph_cmd" ) == -1 ) {    # OK when doesn't contain
#                                                 # right-axis exists, create a file to pass it to cgi-bin commands
#    if ( !-f $graphv_file ) {
#      `touch $graphv_file`;
#    }
#  } ## end if ( index( $ansx, "$graph_cmd"...))
#  else {
#    if ( -f $graphv_file ) {
#      unlink($graphv_file);
#    }
#  }
#
#  return 0;
#} ## end sub rrdtool_graphv

sub once_a_day {
  my $version_file = shift;

  # check whether menu-vmware.txt is older 24 hours
  my $run_time = ( stat("$version_file") )[9];
  ( my $sec, my $min, my $h, my $aday, my $m, my $y, my $wday, my $yday, my $isdst ) = localtime( time() );
  ( $sec, $min, $h, my $png_day, $m, $y, $wday, $yday, $isdst ) = localtime($run_time);
  if ( $aday != $png_day ) {
    LoadDataModuleVMWare::touch("vmware first run after the midnight: $aday != $png_day");
  }
  return 1;
}

