use warnings;
use strict;
use Date::Parse;
use RRDp;
use JSON;
use Xorux_lib qw(read_json write_json uuid_big_endian_format parse_url_params);
use Data::Dumper;
use HostCfg;
use OracleVmDataWrapper;
use OVirtDataWrapper;
use ProxmoxDataWrapper;
use XenServerDataWrapper;
use AzureDataWrapper;
use NutanixDataWrapper;
use FusionComputeDataWrapperJSON;

# get cmd line params
my $version = "$ENV{version}";
my $webdir  = $ENV{WEBDIR};
my $bindir  = $ENV{BINDIR};
my $basedir = $ENV{INPUTDIR};
my $tmpdir  = "$basedir/tmp";
my $wrkdir  = "$basedir/data";
if ( defined $ENV{TMPDIR_LPAR} ) {
  $tmpdir = $ENV{TMPDIR_LPAR};
}
my $cpu_max_filter = 100;       # max 10k peak in % is allowed (in fact it can be higher than 1k now when 1 logical CPU == 0.1 entitlement)
my $pow2           = 1000**2;
if ( defined $ENV{CPU_MAX_FILTER} ) {
  $cpu_max_filter = $ENV{CPU_MAX_FILTER};
}
my $rrdtool = $ENV{RRDTOOL};
my $DEBUG   = $ENV{DEBUG};

#   start RRD via a pipe
if ( !-f "$rrdtool" ) {
  error( "Set correct path to rrdtool binary, it does not exist here: $rrdtool " . __FILE__ . ":" . __LINE__ );
  exit;
}
RRDp::start "$rrdtool";
print "============================== TOPTEN start ==============================\n";
###################
#     ORACLE VM   #
###################
my $orvm;
my $conf_orvm;
my $conf_orvm_json;
if ( keys %{ HostCfg::getHostConnections('OracleVM') } >= 1 ) {
  $orvm           = "$wrkdir/OracleVM";
  $conf_orvm      = "$orvm/conf.json";
  $conf_orvm_json = OracleVmDataWrapper::get_conf();
  if ( -d $orvm ) {
    print "topten file OracleVM: started " . localtime() . "\n";
    print_topten_oraclevm();
  }
}
else { print "OracleVM is not configured\n"; }

#print Dumper $conf_orvm_json;
###################
#      OVIRT      #
###################
my $ovirt;
my $conf_ovirt;
my $conf_ovirt_json;
if ( keys %{ HostCfg::getHostConnections('RHV (oVirt)') } >= 1 ) {
  $ovirt           = "$wrkdir/oVirt";
  $conf_ovirt      = "$ovirt/conf.json";
  $conf_ovirt_json = OVirtDataWrapper::get_conf();
  if ( -d $ovirt ) {
    print "topten file oVirt: started " . localtime() . "\n";
    print_topten_ovirt();
  }
}
else { print "oVirt is not configured\n"; }

#print Dumper $conf_ovirt_json;
###################
#     Proxmox     #
###################
my $proxmox;
my $conf_proxmox;
my $conf_proxmox_json;
if ( keys %{ HostCfg::getHostConnections('Proxmox') } >= 1 ) {
  $proxmox           = "$wrkdir/Proxmox";
  $conf_proxmox      = "$proxmox/conf.json";
  $conf_proxmox_json = ProxmoxDataWrapper::get_conf();
  if ( -d $proxmox ) {
    print "topten file Proxmox: started " . localtime() . "\n";
    print_topten_proxmox();
  }
}
else { print "Proxmox is not configured\n"; }

#print Dumper $conf_proxmox_json;
###################
#     Hyper-V     #
###################
my $hyperv = "$wrkdir/windows";
if ( -d $hyperv ) {
  print "topten file Hyper-V: started " . localtime() . "\n";
  print_topten_hyperv();
}
###################
#    XenServer    #
###################
my $xenserver;
my $xenserver_dir1;
my $xenserver_dir2;
my $conf_xenserver;
my $conf_xenserver_json;
if ( keys %{ HostCfg::getHostConnections('XenServer') } >= 1 ) {
  $xenserver           = "$wrkdir/XEN_iostats";
  $xenserver_dir1      = "$wrkdir/XEN";
  $xenserver_dir2      = "$wrkdir/XEN_VMs";
  $conf_xenserver      = "$xenserver/conf.json";
  $conf_xenserver_json = XenServerDataWrapper::get_conf();
  if ( -d $xenserver && -d $xenserver_dir1 && -d $xenserver_dir2 ) {
    print "topten file XenServer: started " . localtime() . "\n";
    print_topten_xenserver();
  }
}
else { print "XenServer is not configured\n"; }

#print Dumper $conf_xenserver_json;
###################
# Azure files     #
###################
my $azure;
my $conf_azure;
my $conf_azure_json;
if ( keys %{ HostCfg::getHostConnections('Azure') } >= 1 ) {
  $azure           = "$wrkdir/Azure";
  $conf_azure      = "$azure/conf/conf.json";
  $conf_azure_json = AzureDataWrapper::get_conf();
  if ( -d $azure ) {
    print "topten file Azure: started " . localtime() . "\n";
    print_topten_azure();
  }
}
else { print "Azure is not configured\n"; }

#print Dumper $conf_azure_json;
###################
# Oracle DB files #
###################
my $ordb;
my $instance_names;
if ( keys %{ HostCfg::getHostConnections('OracleDB') } >= 1 ) {
  $ordb = "$wrkdir/OracleDB";
  my ( $can_read, $ref ) = Xorux_lib::read_json("$ordb/Totals/instance_names_total.json");
  if ($can_read) {
    $instance_names = $ref;
  }
  else {
    warn "Couldn't open $ordb/Totals/instance_names_total.json";
  }
  if ( -d $ordb ) {
    print "topten file OracleDB: started " . localtime() . "\n";
    print_topten_oracledb();
  }
}
else { print "OracleDB is not configured\n"; }

#print Dumper $ref;
###################
# Nutanix files   #
###################
my $nutanix;
my $conf_nutanix;
my $conf_nutanix_json;
if ( keys %{ HostCfg::getHostConnections('Nutanix') } >= 1 ) {
  $nutanix           = "$wrkdir/NUTANIX";
  $conf_nutanix      = "$nutanix/specification.json";
  $conf_nutanix_json = NutanixDataWrapper::get_spec();
  if ( -d $nutanix ) {
    print "topten file Nutanix: started " . localtime() . "\n";
    print_topten_nutanix();
  }
}
else { print "Nutanix is not configured\n"; }

#print Dumper $conf_nutanix_json;
###################
# PostgreSQL files #
###################
my $postgres;
my $instance_names_postgres;
if ( keys %{ HostCfg::getHostConnections('PostgreSQL') } >= 1 ) {
  $postgres = "$wrkdir/PostgreSQL";
  my ( $can_read1, $ref1 ) = Xorux_lib::read_json("$postgres/_Totals/Configuration/arc_total.json");
  if ($can_read1) {
    $instance_names_postgres = $ref1;
  }
  else {
    warn "Couldn't open $postgres/_Totals/Configuration/arc_total.json";
  }
  if ( -d $postgres ) {
    print "topten file PostgreSQL: started " . localtime() . "\n";
    print_topten_postgresql();
  }
}
else { print "PostgreSQL is not configured\n"; }

#print Dumper $ref1;
###################
# Microsoft SQL   #
###################
my $microsql;
my $instance_names_microsql;
if ( keys %{ HostCfg::getHostConnections('SQLServer') } >= 1 ) {
  $microsql = "$wrkdir/SQLServer";
  my ( $can_read2, $ref2 ) = Xorux_lib::read_json("$microsql/_Totals/Configuration/arc_total.json");
  if ($can_read2) {
    $instance_names_microsql = $ref2;
  }
  else {
    warn "Couldn't open $microsql/_Totals/Configuration/arc_total.json";
  }
  if ( -d $microsql ) {
    print "topten file Microsoft SQL: started " . localtime() . "\n";
    print_topten_microsql();
  }
}
else { print "SQLServer is not configured\n"; }

#print Dumper $ref2;
###################
# FusionCompute   #
###################
my $fusion;
my $conf_fusion;
my $conf_fusion_json;
if ( keys %{ HostCfg::getHostConnections('FusionCompute') } >= 1 ) {
  $fusion           = "$wrkdir/FusionCompute";
  $conf_fusion      = "$fusion/specification.json";
  $conf_fusion_json = FusionComputeDataWrapperJSON::get_specification();
  if ( -d $fusion ) {
    print "topten file FusionCompute: started " . localtime() . "\n";
    print_topten_fusion();
  }
}
else { print "FusionCompute is not configured\n"; }

#print Dumper $conf_fusion_json;

print "============================== TOPTEN end ==============================\n";

#sub start
#
# ORACLEVM
#
sub print_topten_oraclevm {
  opendir( DIR, "$orvm/vm/" ) || error( "can't opendir $orvm/vm/: $! :" . __FILE__ . ":" . __LINE__ ) && return;
  my @all_vms_orvm = grep !/^\.\.?$/, readdir(DIR);
  closedir(DIR);
  my @topten_orvm;
  foreach my $vm_dir (@all_vms_orvm) {
    my $vm_name = OracleVmDataWrapper::get_label( 'vm', $vm_dir );
    my ( $server_pool_uuid, $server_pool_name, $manager_uuid, $manager_name );
    if ( exists $conf_orvm_json->{specification}->{vm}->{$vm_dir}->{parent_server_pool} ) {
      $server_pool_uuid = $conf_orvm_json->{specification}->{vm}->{$vm_dir}->{parent_server_pool};
      $server_pool_name = OracleVmDataWrapper::get_label( 'server_pool', $server_pool_uuid );
      $manager_uuid     = $conf_orvm_json->{architecture}->{server_pool}->{$server_pool_uuid}->{parent};
      $manager_name     = OracleVmDataWrapper::get_label( 'manager', $manager_uuid );
    }
    ########################
    # CPU cores / percent  #
    ########################
    my $vm_rrd = "$orvm/vm/$vm_dir/sys.rrd";
    if ( -f $vm_rrd ) {
      print "$vm_rrd(vm_name:$vm_name) - found\n";
      $vm_rrd =~ s/:/\\:/g;
      next if ( -f $vm_rrd and ( -M $vm_rrd > 365 ) );    # not older 1 year
      my $line_cpu_to_tmp      = "";
      my $line_cpu_perc_to_tmp = "";
      if ( defined $server_pool_name && $server_pool_name ne '' && defined $manager_name && $manager_name ne '' ) {
        $line_cpu_to_tmp      = "cpu_util,$vm_name,$server_pool_name,$manager_name";    # cpu cores
        $line_cpu_perc_to_tmp = "cpu_perc,$vm_name,$server_pool_name,$manager_name";
      }
      else {
        $line_cpu_to_tmp      = "cpu_util,$vm_name,,";                                  # cpu cores
        $line_cpu_perc_to_tmp = "cpu_perc,$vm_name,,";                                  # cpu percent
      }
      foreach my $type ( "d", "w", "m", "y" ) {
        my $start_time = "now-1$type";
        my $end_time   = "now-1$type+1$type";
        my $name_out   = "test";
        RRDp::cmd qq(graph "$name_out"
        "--start" "$start_time"
        "--end" "$end_time"
        "DEF:cpu_util=$vm_rrd:CPU_UTILIZATION:AVERAGE"
        "DEF:cpu_count=$vm_rrd:CPU_COUNT:AVERAGE"
        "CDEF:cpu_perc=cpu_util,100,*"
        "CDEF:cpu_res=cpu_count,cpu_util,*"
        "PRINT:cpu_res:AVERAGE: %3.1lf"
        "PRINT:cpu_res:MAX: %3.1lf"
        "PRINT:cpu_perc:AVERAGE: %3.0lf"
        "PRINT:cpu_perc:MAX: %3.0lf"
        );
        my $answer = RRDp::read;
        if ( $$answer =~ "ERROR" ) {
          error("Rrdtool error : $$answer");
          next;
        }
        my $aaa = $$answer;
        ( undef, my $utiltot, my $utiltot_max, my $util_perc, my $util_perc_max ) = split( "\n", $aaa );
        $utiltot       = nan_to_null($utiltot);
        $utiltot_max   = nan_to_null($utiltot_max);
        $util_perc     = nan_to_null($util_perc);
        $util_perc_max = nan_to_null($util_perc_max);
        chomp($utiltot);
        chomp($utiltot_max);
        chomp($util_perc);
        chomp($util_perc_max);
        $line_cpu_to_tmp      .= ",$utiltot,$utiltot_max";
        $line_cpu_perc_to_tmp .= ",$util_perc,$util_perc_max";
      }
      push @topten_orvm, "$line_cpu_to_tmp";
      push @topten_orvm, "$line_cpu_perc_to_tmp";
    }
    else {
      print "$vm_rrd(vm_name:$vm_name) - not found\n";
    }
    ########################
    #        NET           #
    ########################
    opendir( DIR, "$orvm/vm/$vm_dir" ) || error( "can't opendir $orvm/vm/$vm_dir: $! :" . __FILE__ . ":" . __LINE__ ) && next;
    my @all_nets = grep /^lan/, readdir(DIR);
    closedir(DIR);
    foreach my $net_name (@all_nets) {
      my $net_rrd         = "$orvm/vm/$vm_dir/$net_name";
      my $net_without_col = $net_rrd;
      $net_without_col =~ s/===double-col===/:/g;
      if ( -f $net_rrd ) {
        $net_rrd =~ s/:/\\:/g;
        next if ( -f $net_rrd and ( -M $net_rrd > 365 ) );    # not older 1 year
        print "$net_without_col(vm_name:$vm_name) - found\n";

        # cpu cores
        my $line_net_to_tmp = "";
        if ( defined $server_pool_name && $server_pool_name ne '' && defined $manager_name && $manager_name ne '' ) {
          $line_net_to_tmp = "net,$vm_name,$net_name,$server_pool_name,$manager_name";
        }
        else {
          $line_net_to_tmp = "net,$vm_name,,";
        }
        foreach my $type ( "d", "w", "m", "y" ) {
          my $start_time = "now-1$type";
          my $end_time   = "now-1$type+1$type";
          my $name_out   = "test";
          RRDp::cmd qq(graph "$name_out"
          "--start" "$start_time"
          "--end" "$end_time"
          "DEF:read=$net_rrd:NETWORK_SENT:AVERAGE"
          "DEF:write=$net_rrd:NETWORK_RECEIVED:AVERAGE"
          "CDEF:read_mb=read,$pow2,/"
          "CDEF:write_mb=write,$pow2,/"
          "CDEF:result_net=write_mb,read_mb,+"
          "PRINT:result_net:AVERAGE: %3.2lf"
          "PRINT:result_net:MAX: %3.2lf"
          );
          my $answer = RRDp::read;
          if ( $$answer =~ "ERROR" ) {
            error("Rrdtool error : $$answer");
            next;
          }
          my $aaa = $$answer;
          ( undef, my $net, my $net_max ) = split( "\n", $aaa );
          $net = nan_to_null($net);
          chomp($net);
          $net_max = nan_to_null($net_max);
          chomp($net_max);
          $line_net_to_tmp .= ",$net,$net_max";
        }
        push @topten_orvm, "$line_net_to_tmp";
      }
    }
    ########################
    #        DISK           #
    ########################
    opendir( DIR, "$orvm/vm/$vm_dir" ) || error( "can't opendir $orvm/vm/$vm_dir: $! :" . __FILE__ . ":" . __LINE__ ) && next;
    my @all_disks = grep /^disk/, readdir(DIR);
    closedir(DIR);
    foreach my $disk_name (@all_disks) {
      my $disk_rrd = "$orvm/vm/$vm_dir/$disk_name";
      if ( -f $disk_rrd ) {
        $disk_rrd =~ s/:/\\:/g;
        next if ( -f $disk_rrd and ( -M $disk_rrd > 365 ) );    # not older 1 year
        print "$disk_rrd(vm_name:$disk_name) - found\n";
        my $disk_uuid = "$disk_name";
        $disk_uuid =~ s/\.rrd//g;
        $disk_uuid =~ s/^disk-//g;
        my $disk_human_name = OracleVmDataWrapper::get_label( 'repos', $disk_uuid );

        # disk
        my $line_disk_to_tmp = "";
        if ( defined $server_pool_name && $server_pool_name ne '' && defined $manager_name && $manager_name ne '' ) {
          $line_disk_to_tmp = "disk,$vm_name,$disk_human_name,$server_pool_name,$manager_name";
        }
        else {
          $line_disk_to_tmp = "disk,$vm_name,,";
        }
        foreach my $type ( "d", "w", "m", "y" ) {
          my $start_time = "now-1$type";
          my $end_time   = "now-1$type+1$type";
          my $name_out   = "test";
          RRDp::cmd qq(graph "$name_out"
          "--start" "$start_time"
          "--end" "$end_time"
          "DEF:read=$disk_rrd:DISK_READ:AVERAGE"
          "DEF:write=$disk_rrd:DISK_WRITE:AVERAGE"
          "CDEF:read_mb=read,$pow2,/"
          "CDEF:write_mb=write,$pow2,/"
          "CDEF:result_disk=write_mb,read_mb,+"
          "PRINT:result_disk:AVERAGE: %3.2lf"
          "PRINT:result_disk:MAX: %3.2lf"
          );
          my $answer = RRDp::read;
          if ( $$answer =~ "ERROR" ) {
            error("Rrdtool error : $$answer");
            next;
          }
          my $aaa = $$answer;
          ( undef, my $disk, my $disk_max ) = split( "\n", $aaa );
          $disk = nan_to_null($disk);
          chomp($disk);
          $disk_max = nan_to_null($disk_max);
          chomp($disk_max);
          $line_disk_to_tmp .= ",$disk,$disk_max";
        }
        push @topten_orvm, "$line_disk_to_tmp";
      }
    }
  }
  #
  # Example of OracleVM top10
  #
  #   item  ,     vm_name    ,   server_pool_name,    manager_name      data-period(daily,weekly,monthly,yearly)
  # cpu_util,  solaris11-vm01,   sparc-cluster,       ovm-manager,     0.12,0.14,0.12,0.13,0.12,0.13,1.21,2.00
  # cpu_perc,  solaris11-vm01,   sparc-cluster,       ovm-manager,     6.07,7.11,6.06,6.74,5.96,6.46,60.52,100.00

  ### PUSH ALL TO FILE
  my $topten_orvm = "$tmpdir/topten_oraclevm.tmp";
  open( TOP_ORVM, "> $topten_orvm" ) || error( "Cannot open $topten_orvm: $!" . __FILE__ . ":" . __LINE__ ) && next;
  foreach my $line (@topten_orvm) {
    print TOP_ORVM "$line\n";
  }
  close TOP_ORVM;
  print "topten file OracleVM : updated " . localtime() . "\n";
}
#
# OVIRT
#
sub print_topten_ovirt {
  opendir( DIR, "$ovirt/vm/" ) || error( "can't opendir $ovirt/vm/: $! :" . __FILE__ . ":" . __LINE__ ) && return;
  my @all_vms_ovirt = grep !/^\.\.?$/, readdir(DIR);
  closedir(DIR);
  my @topten_ovirt;
  foreach my $vm_dir (@all_vms_ovirt) {
    my $vm_name = OVirtDataWrapper::get_label( 'vm', $vm_dir );
    my ( $server_pool_name, $server_pool_uuid, $datacenter_uuid, $datacenter_name ) = "";
    if ( exists $conf_ovirt_json->{architecture}->{vm}->{$vm_dir}->{parent} ) {
      $server_pool_uuid = $conf_ovirt_json->{architecture}->{vm}->{$vm_dir}->{parent};
      $server_pool_name = OVirtDataWrapper::get_label( 'cluster', $server_pool_uuid );
      if ( $server_pool_name && $server_pool_uuid ) {
        $datacenter_uuid = $conf_ovirt_json->{architecture}->{cluster}->{$server_pool_uuid}->{parent};
        $datacenter_name = OVirtDataWrapper::get_label( 'datacenter', $datacenter_uuid );
      }
    }
    else {next}
    ########################################
    # OVIRT      -    CPU cores / percent  #
    ########################################
    my $vm_rrd = "$ovirt/vm/$vm_dir/sys.rrd";
    if ( -f $vm_rrd ) {
      $vm_rrd =~ s/:/\\:/g;
      next if ( -f $vm_rrd and ( -M $vm_rrd > 365 ) );    # not older 1 year
      print "$vm_rrd(vm_name:$vm_name) - found\n";
      my $line_cpu_to_tmp      = "cpu_util,$vm_name,$server_pool_name,$datacenter_name";
      my $line_cpu_perc_to_tmp = "cpu_perc,$vm_name,$server_pool_name,$datacenter_name";
      foreach my $type ( "d", "w", "m", "y" ) {
        my $start_time = "now-1$type";
        my $end_time   = "now-1$type+1$type";
        my $name_out   = "test";
        RRDp::cmd qq(graph "$name_out"
        "--start" "$start_time"
        "--end" "$end_time"
        "DEF:cpu_c=$vm_rrd:cpu_usage_c:AVERAGE"
        "DEF:user_p=$vm_rrd:user_cpu_usage_p:AVERAGE"
        "DEF:system_p=$vm_rrd:system_cpu_usage_p:AVERAGE"
        "CDEF:util_perc=user_p,system_p,+"
        "PRINT:cpu_c:AVERAGE: %6.1lf"
        "PRINT:cpu_c:MAX: %6.1lf"
        "PRINT:util_perc:AVERAGE: %6.0lf"
        "PRINT:util_perc:MAX: %6.0lf"
        );
        my $answer = RRDp::read;
        if ( $$answer =~ "ERROR" ) {
          error("Rrdtool error : $$answer");
          next;
        }
        my $aaa = $$answer;
        ( undef, my $utiltot, my $utiltot_max, my $util_perc, my $util_perc_max ) = split( "\n", $aaa );
        $utiltot       = nan_to_null($utiltot);
        $utiltot_max   = nan_to_null($utiltot_max);
        $util_perc     = nan_to_null($util_perc);
        $util_perc_max = nan_to_null($util_perc_max);
        chomp($utiltot);
        chomp($utiltot_max);
        chomp($util_perc);
        chomp($util_perc_max);
        $line_cpu_to_tmp      .= ",$utiltot,$utiltot_max";
        $line_cpu_perc_to_tmp .= ",$util_perc,$util_perc_max";
      }
      push @topten_ovirt, "$line_cpu_to_tmp";
      push @topten_ovirt, "$line_cpu_perc_to_tmp";
    }
    ########################
    #   OVIRT   -     NET  #
    ########################
    $vm_dir =~ s/\.rrm|\.rrd//g;
    my @all_nets = "";
    if ( -d "$ovirt/vm/$vm_dir" ) {
      opendir( DIR, "$ovirt/vm/$vm_dir" ) || error( "can't opendir $ovirt/vm/$vm_dir: $! :" . __FILE__ . ":" . __LINE__ ) && next;
      @all_nets = grep /^nic/, readdir(DIR);
      closedir(DIR);
    }
    if (@all_nets) {
      foreach my $net_rrd (@all_nets) {
        my $net_uuid = $net_rrd;
        $net_uuid =~ s/\.rrd//g;
        $net_uuid =~ s/^nic-//g;
        my $net_name = OVirtDataWrapper::get_label( 'vm_nic', $net_uuid );
        $net_rrd = "$ovirt/vm/$vm_dir/$net_rrd";
        if ( -f $net_rrd ) {
          $net_rrd =~ s/:/\\:/g;
          next if ( -f $net_rrd and ( -M $net_rrd > 365 ) );    # not older 1 year
          print "$net_rrd(net_name:$net_name) - found\n";
          my $line_net_to_tmp = "net,$net_name,$vm_name,$server_pool_name,$datacenter_name";
          foreach my $type ( "d", "w", "m", "y" ) {
            my $start_time = "now-1$type";
            my $end_time   = "now-1$type+1$type";
            my $name_out   = "test";
            RRDp::cmd qq(graph "$name_out"
            "--start" "$start_time"
            "--end" "$end_time"
            "DEF:read=$net_rrd:received_byte:AVERAGE"
            "DEF:write=$net_rrd:transmitted_byte:AVERAGE"
            "CDEF:read_res=read,$pow2,/,60,/"
            "CDEF:write_res=write,$pow2,/,60,/"
            "CDEF:result_net=write_res,read_res,+"
            "PRINT:result_net:AVERAGE: %6.2lf"
            "PRINT:result_net:MAX: %6.2lf"
            );
            my $answer = RRDp::read;
            if ( $$answer =~ "ERROR" ) {
              error("Rrdtool error : $$answer");
              next;
            }
            my $aaa = $$answer;
            ( undef, my $net, my $net_max ) = split( "\n", $aaa );
            $net     = nan_to_null($net);
            $net_max = nan_to_null($net_max);
            chomp($net);
            chomp($net_max);
            $line_net_to_tmp .= ",$net,$net_max";
          }
          push @topten_ovirt, "$line_net_to_tmp";
        }
      }
    }
  }
  ########################
  #   OVIRT   -     DISK #
  ########################
  opendir( DIR, "$ovirt/storage" ) || error( "can't opendir $ovirt/storage : $! :" . __FILE__ . ":" . __LINE__ ) && next;
  my @all_disks = grep /^disk-/, readdir(DIR);
  closedir(DIR);
  foreach my $disk_rrd (@all_disks) {
    next if ( -f "$ovirt/storage/$disk_rrd" and ( -M "$ovirt/storage/$disk_rrd" > 10 ) );    # not older 10 days
    my $disk_uuid = $disk_rrd;
    $disk_uuid =~ s/\.rrd//g;
    $disk_uuid =~ s/^disk-//g;
    opendir( DIR, "$ovirt/vm/" ) || error( "can't opendir $ovirt/vm/: $! :" . __FILE__ . ":" . __LINE__ ) && next;
    my @all_vms = grep !/^\.\.?$/, readdir(DIR);
    closedir(DIR);
    if ( defined $disk_uuid && $disk_uuid eq "" ) {next}
    my $storage_domain_uuid = OVirtDataWrapper::get_parent( 'disk',           $disk_uuid );
    my $datacenter_uuid     = OVirtDataWrapper::get_parent( 'storage_domain', $storage_domain_uuid );
    my $datacenter_name = OVirtDataWrapper::get_label( 'datacenter', $datacenter_uuid );
    my @cluster_uuids = @{ OVirtDataWrapper::get_arch( $datacenter_uuid, 'datacenter', 'cluster' ) };
    my $cluster_name;
    my $cluster_uuid;

    foreach $cluster_uuid (@cluster_uuids) {
      $cluster_name = OVirtDataWrapper::get_label( 'cluster', $cluster_uuid );
    }
    my $vm_uuid;
    foreach my $vm ( keys( %{ $conf_ovirt_json->{architecture}->{vm} } ) ) {
      foreach my $uuid_disk ( @{ $conf_ovirt_json->{architecture}->{vm}->{$vm}->{disk} } ) {
        if ( $uuid_disk eq "$disk_uuid" ) {
          $vm_uuid = $vm;
        }
      }
    }
    my $disk_name = OVirtDataWrapper::get_label( 'disk', $disk_uuid );
    if ( $disk_uuid eq "$disk_name" ) {next}    # disk is not in config - so only some old disk data in directory
    my $vm_name = OVirtDataWrapper::get_label( 'vm', $vm_uuid );
    $disk_rrd = "$ovirt/storage/$disk_rrd";
    if ( -f $disk_rrd ) {
      $disk_rrd =~ s/:/\\:/g;
      next if ( -f $disk_rrd and ( -M $disk_rrd > 365 ) );    # not older 1 year
      print "$disk_rrd(disk_name:$disk_name) - found\n";
      my $line_disk_to_tmp = "disk,$disk_name,$vm_name,$cluster_name,$datacenter_name";
      foreach my $type ( "d", "w", "m", "y" ) {
        my $start_time = "now-1$type";
        my $end_time   = "now-1$type+1$type";
        my $name_out   = "test";
        RRDp::cmd qq(graph "$name_out"
        "--start" "$start_time"
        "--end" "$end_time"
        "DEF:data_read=$disk_rrd:data_current_read:AVERAGE"
        "DEF:data_write=$disk_rrd:data_current_write:AVERAGE"
        "CDEF:read_res=data_read,$pow2,/"
        "CDEF:write_res=data_write,$pow2,/"
        "CDEF:result_data=write_res,read_res,+"
        "PRINT:result_data:AVERAGE: %6.2lf"
        "PRINT:result_data:MAX: %6.2lf"
        );
        my $answer = RRDp::read;
        if ( $$answer =~ "ERROR" ) {
          error("Rrdtool error : $$answer");
          next;
        }
        my $aaa = $$answer;
        ( undef, my $disk, my $disk_max ) = split( "\n", $aaa );
        $disk     = nan_to_null($disk);
        $disk_max = nan_to_null($disk_max);
        chomp($disk);
        chomp($disk_max);
        $line_disk_to_tmp .= ",$disk,$disk_max";
      }
      push @topten_ovirt, "$line_disk_to_tmp";
    }
  }

  ### PUSH ALL TO FILE
  my $topten_ovirt = "$tmpdir/topten_ovirt.tmp";
  open( TOP_OVIRT, "> $topten_ovirt" ) || error( "Cannot open $topten_ovirt: $!" . __FILE__ . ":" . __LINE__ ) && next;
  foreach my $line (@topten_ovirt) {
    print TOP_OVIRT "$line\n";
  }
  close TOP_OVIRT;
  print "topten file oVirt : updated " . localtime() . "\n";
}
#
# Proxmox
#
sub print_topten_proxmox {
  opendir( DIR, "$proxmox/VM/" ) || error( "can't opendir $ovirt/VM/: $! :" . __FILE__ . ":" . __LINE__ ) && return;
  my @all_vms_proxmox = grep !/^\.\.?$/, readdir(DIR);
  closedir(DIR);
  my @topten_proxmox;
  foreach my $vm_dir (@all_vms_proxmox) {
    my $vm_rrd  = "$proxmox/VM/$vm_dir";
    my $vm_uuid = $vm_dir;
    $vm_uuid =~ s/\.rrd//g;
    my $vm_name = ProxmoxDataWrapper::get_label( 'vm', $vm_uuid );
    my $cluster_name;
    my $status = "";
    if ( exists $conf_proxmox_json->{specification}->{vm}->{$vm_uuid} ) {
      $cluster_name = $conf_proxmox_json->{specification}->{vm}->{$vm_uuid}->{cluster};
      $status       = $conf_proxmox_json->{specification}->{vm}->{$vm_uuid}->{status};
    }
    if ( -f $vm_rrd ) {
      $vm_rrd =~ s/:/\\:/g;
      next if ( -f $vm_rrd and ( -M $vm_rrd > 365 ) );    # not older 1 year
      if ( $status ne "running" ) {next}
      print "$vm_rrd(vm_name:$vm_name) - found\n";
      my $line_cpu_to_tmp      = "";
      my $line_cpu_perc_to_tmp = "";
      my $line_disk_to_tmp     = "";
      my $line_net_to_tmp      = "";

      if ( defined $cluster_name && $cluster_name ne '' ) {
        $line_cpu_to_tmp      = "cpu_util,$vm_name,$cluster_name";
        $line_cpu_perc_to_tmp = "cpu_perc,$vm_name,$cluster_name";
        $line_disk_to_tmp     = "disk,$vm_name,$cluster_name";
        $line_net_to_tmp      = "net,$vm_name,$cluster_name";
      }
      else {
        $line_cpu_to_tmp      = "cpu_util,$vm_name,";
        $line_cpu_perc_to_tmp = "cpu_perc,$vm_name,";
        $line_disk_to_tmp     = "disk,$vm_name,";
        $line_net_to_tmp      = "net,$vm_name,";
      }
      foreach my $type ( "d", "w", "m", "y" ) {
        my $start_time = "now-1$type";
        my $end_time   = "now-1$type+1$type";
        my $name_out   = "test";
        my $division   = 1000 * 1000;
        RRDp::cmd qq(graph "$name_out"
        "--start" "$start_time"
        "--end" "$end_time"
        "DEF:cpu_used=$vm_rrd:cpu:AVERAGE"
        "DEF:cpu_total=$vm_rrd:maxcpu:AVERAGE"
        "DEF:metric_write=$vm_rrd:diskwrite:AVERAGE"
        "DEF:metric_read=$vm_rrd:diskread:AVERAGE"
        "DEF:metric_write_net=$vm_rrd:netout:AVERAGE"
        "DEF:metric_read_net=$vm_rrd:netin:AVERAGE"
        "CDEF:used=cpu_used,cpu_total,*"
        "CDEF:total=cpu_total,1,/"
        "CDEF:cpu_perc=cpu_used,100,*"
        "CDEF:read=metric_read,$division,/"
        "CDEF:write=metric_write,$division,/"
        "CDEF:read_net=metric_read_net,$division,/"
        "CDEF:write_net=metric_write_net,$division,/"
        "CDEF:result_data=read,write,+"
        "CDEF:result_net=read_net,write_net,+"
        "PRINT:used:AVERAGE: %6.1lf"
        "PRINT:used:MAX: %6.1lf"
        "PRINT:cpu_perc:AVERAGE: %6.0lf"
        "PRINT:cpu_perc:MAX: %6.0lf"
        "PRINT:result_data:AVERAGE: %6.2lf"
        "PRINT:result_data:MAX: %6.2lf"
        "PRINT:result_net:AVERAGE: %6.2lf"
        "PRINT:result_net:MAX: %6.2lf"
        );
        my $answer = RRDp::read;
        if ( $$answer =~ "ERROR" ) {
          error("Rrdtool error : $$answer");
          next;
        }
        my $aaa = $$answer;
        ( undef, my $cpu, my $cpu_max, my $cpu_perc, my $cpu_perc_max, my $disk, my $disk_max, my $net, my $net_max ) = split( "\n", $aaa );
        $cpu          = nan_to_null($cpu);
        $cpu_max      = nan_to_null($cpu_max);
        $cpu_perc     = nan_to_null($cpu_perc);
        $cpu_perc_max = nan_to_null($cpu_perc_max);
        $disk         = nan_to_null($disk);
        $disk_max     = nan_to_null($disk_max);
        $net          = nan_to_null($net);
        $net_max      = nan_to_null($net_max);
        chomp($cpu);
        chomp($cpu_max);
        chomp($cpu_perc);
        chomp($cpu_perc_max);
        chomp($disk);
        chomp($disk_max);
        chomp($net);
        chomp($net_max);
        $line_cpu_to_tmp      .= ",$cpu,$cpu_max";
        $line_cpu_perc_to_tmp .= ",$cpu_perc,$cpu_perc_max";
        $line_disk_to_tmp     .= ",$disk,$disk_max";
        $line_net_to_tmp      .= ",$net,$net_max";
      }
      push @topten_proxmox, "$line_cpu_to_tmp";
      push @topten_proxmox, "$line_cpu_perc_to_tmp";
      push @topten_proxmox, "$line_disk_to_tmp";
      push @topten_proxmox, "$line_net_to_tmp";
    }
  }
  ### PUSH ALL TO FILE
  my $topten_proxmox = "$tmpdir/topten_proxmox.tmp";
  open( TOP_PROXMOX, "> $topten_proxmox" ) || error( "Cannot open $topten_proxmox: $!" . __FILE__ . ":" . __LINE__ ) && next;
  foreach my $line (@topten_proxmox) {
    print TOP_PROXMOX "$line\n";
  }
  close TOP_PROXMOX;
  print "topten file Proxmox : updated " . localtime() . "\n";
}
#
# Hyper-V
#
sub print_topten_hyperv {
  opendir( DIR, "$hyperv" ) || error( "can't opendir $hyperv: $! :" . __FILE__ . ":" . __LINE__ ) && return;
  my @all_domains_hyperv = grep /^domain_/, readdir(DIR);
  closedir(DIR);
  my @topten_hyperv;
  foreach my $domain (@all_domains_hyperv) {
    my $hyperv_vms = "$hyperv/$domain/hyperv_VMs";
    opendir( DIR, "$hyperv_vms" ) || error( "can't opendir $hyperv_vms: $! :" . __FILE__ . ":" . __LINE__ ) && next;
    my @all_vms = grep /\.rrm$/, readdir(DIR);
    closedir(DIR);
    if ( -d $hyperv_vms ) {
      my $vm_uuid_cfg = "$hyperv/$domain/hyperv_VMs/vm_uuid_name.txt";
      my @vm_list_config;
      if ( -f "$vm_uuid_cfg" ) {
        open( FC, "< $vm_uuid_cfg" ) || error( "Cannot read $vm_uuid_cfg: $!" . __FILE__ . ":" . __LINE__ );
        @vm_list_config = <FC>;
        close(FC);
      }
      foreach my $vm_uuid (@all_vms) {
        my $vm_rrd = "$hyperv/$domain/hyperv_VMs/$vm_uuid";
        next if ( -f $vm_rrd and ( -M $vm_rrd > 365 ) );    # not older 1 year
        $vm_uuid =~ s/\.rrm//g;
        my ($vm_line_pattern) = grep /$vm_uuid,/, @vm_list_config;
        my ( undef, $vm_name ) = split /,/, $vm_line_pattern;
        if ( -f $vm_rrd ) {
          $vm_rrd =~ s/:/\\:/g;
          my $domain_name = $domain;
          $domain_name =~ s/^domain_//g;
          print "$vm_rrd(vm_name:$vm_name) - found\n";
          my $line_cpu_to_tmp  = "cpu_util,$vm_name,$domain_name";
          my $line_disk_to_tmp = "disk,$vm_name,$domain_name";
          my $line_net_to_tmp  = "net,$vm_name,$domain_name";
          foreach my $type ( "d", "w", "m", "y" ) {
            my $start_time = "now-1$type";
            my $end_time   = "now-1$type+1$type";
            my $name_out   = "test";
            my $kbmb       = 1024;
            $kbmb *= 1000 * 1000;
            RRDp::cmd qq(graph "$name_out"
            "--start" "$start_time"
            "--end" "$end_time"
            "DEF:cpu1=$vm_rrd:PercentTotalRunTime:AVERAGE"
            "DEF:cpu2=$vm_rrd:Timestamp_PerfTime:AVERAGE"
            "DEF:cpu3=$vm_rrd:Frequency_PerfTime:AVERAGE"
            "DEF:cpu4=$vm_rrd:vCPU:AVERAGE"
            "DEF:disk_read1=$vm_rrd:DiskReadBytesPersec:AVERAGE"
            "DEF:disk_write1=$vm_rrd:DiskWriteBytesPerse:AVERAGE"
            "DEF:net_read1=$vm_rrd:BytesReceivedPersec:AVERAGE"
            "DEF:net_write1=$vm_rrd:BytesSentPersec:AVERAGE"
            "CDEF:cpu_usage=cpu1,cpu2,/,cpu3,*,100000,/,100,/,cpu4,*"
            "CDEF:disk_read2=disk_read1,$kbmb,/"
            "CDEF:disk_write2=disk_write1,$kbmb,/"
            "CDEF:net_read2=net_read1,$kbmb,/"
            "CDEF:net_write2=net_write1,$kbmb,/"
            "CDEF:result_disk=disk_read2,disk_write2,+"
            "CDEF:result_net=net_read2,net_write2,+"
            "PRINT:cpu_usage:AVERAGE: %6.1lf"
            "PRINT:cpu_usage:MAX: %6.1lf"
            "PRINT:result_disk:AVERAGE: %6.2lf"
            "PRINT:result_disk:MAX: %6.2lf"
            "PRINT:result_net:AVERAGE: %6.2lf"
            "PRINT:result_net:MAX: %6.2lf"
            );
            my $answer = RRDp::read;

            if ( $$answer =~ "ERROR" ) {
              error("Rrdtool error : $$answer");
              next;
            }
            my $aaa = $$answer;
            ( undef, my $cpu, my $cpu_max, my $disk, my $disk_max, my $net, my $net_max ) = split( "\n", $aaa );
            $cpu      = nan_to_null($cpu);
            $cpu_max  = nan_to_null($cpu_max);
            $disk     = nan_to_null($disk);
            $disk_max = nan_to_null($disk_max);
            $net      = nan_to_null($net);
            $net_max  = nan_to_null($net_max);
            chomp($cpu);
            chomp($cpu_max);
            chomp($disk);
            chomp($disk_max);
            chomp($net);
            chomp($net_max);
            $line_cpu_to_tmp  .= ",$cpu,$cpu_max";
            $line_disk_to_tmp .= ",$disk,$disk_max";
            $line_net_to_tmp  .= ",$net,$net_max";
          }
          push @topten_hyperv, "$line_cpu_to_tmp";
          push @topten_hyperv, "$line_disk_to_tmp";
          push @topten_hyperv, "$line_net_to_tmp";
        }
      }
      ### PUSH ALL TO FILE
      my $topten_hyperv = "$tmpdir/topten_hyperv.tmp";
      open( TOP_HYPERV, "> $topten_hyperv" ) || error( "Cannot open $topten_hyperv: $!" . __FILE__ . ":" . __LINE__ ) && next;
      foreach my $line (@topten_hyperv) {
        print TOP_HYPERV "$line\n";
      }
      close TOP_HYPERV;
    }
  }
  print "topten file Hyper-V : updated " . localtime() . "\n";
}
#
# XenServer
#
sub print_topten_xenserver {
  opendir( DIR, "$wrkdir/XEN_VMs" ) || error( "can't opendir $wrkdir/XEN_VMs: $! :" . __FILE__ . ":" . __LINE__ ) && return;
  my @all_vms_xenserver = grep /\.rrd$/, readdir(DIR);
  closedir(DIR);
  my @topten_xenserver;
  foreach my $rrd_file (@all_vms_xenserver) {
    my $vm_rrd  = "$wrkdir/XEN_VMs/$rrd_file";
    my $vm_uuid = "$rrd_file";
    $vm_uuid =~ s/\.rrd$//g;
    my $vm_name = XenServerDataWrapper::get_label( 'vm', $vm_uuid );
    my $server_pool_uuid;
    if ( exists $conf_xenserver_json->{specification}->{vm}->{$vm_uuid} ) {
      $server_pool_uuid = $conf_xenserver_json->{specification}->{vm}->{$vm_uuid}->{parent_pool};
    }
    my $server_pool = XenServerDataWrapper::get_label( 'pool', $server_pool_uuid );
    if ( -f $vm_rrd ) {
      $vm_rrd =~ s/:/\\:/g;
      next if ( -f $vm_rrd and ( -M $vm_rrd > 365 ) );    # not older 1 year
      print "$vm_rrd(vm_name:$vm_name) - found\n";
      my $line_cpu_to_tmp      = "cpu_util,$vm_name,$server_pool";
      my $line_cpu_perc_to_tmp = "cpu_perc,$vm_name,$server_pool";
      my $line_disk_to_tmp     = "disk,$vm_name,$server_pool";
      my $line_iops_to_tmp     = "iops,$vm_name,$server_pool";
      my $line_net_to_tmp      = "net,$vm_name,$server_pool";

      foreach my $type ( "d", "w", "m", "y" ) {
        my $start_time = "now-1$type";
        my $end_time   = "now-1$type+1$type";
        my $name_out   = "test";
        my $b2mib      = 1024**2;
        my $b2mb       = 1000**2;
        RRDp::cmd qq(graph "$name_out"
        "--start" "$start_time"
        "--end" "$end_time"
        "DEF:cpu_used_cores=$vm_rrd:cpu_cores:AVERAGE"
        "DEF:cpu_used_perc=$vm_rrd:cpu:AVERAGE"
        "DEF:iops_read=$vm_rrd:vbd_iops_read:AVERAGE"
        "DEF:iops_write=$vm_rrd:vbd_iops_write:AVERAGE"
        "DEF:data_read1=$vm_rrd:vbd_read:AVERAGE"
        "DEF:data_write1=$vm_rrd:vbd_write:AVERAGE"
        "DEF:net_read1=$vm_rrd:net_transmitted:AVERAGE"
        "DEF:net_write1=$vm_rrd:net_received:AVERAGE"
        "CDEF:cpu_perc=cpu_used_perc,100,*"
        "CDEF:data_read2=data_read1,$b2mib,/"
        "CDEF:data_write2=data_write1,$b2mib,/"
        "CDEF:net_read2=net_read1,$b2mb,/"
        "CDEF:net_write2=net_write1,$b2mb,/"
        "CDEF:result_iops=iops_read,iops_write,+"
        "CDEF:result_data=data_read2,data_write2,+"
        "CDEF:result_net=net_read2,net_write2,+"
        "PRINT:cpu_used_cores:AVERAGE: %6.1lf"
        "PRINT:cpu_used_cores:MAX: %6.1lf"
        "PRINT:cpu_perc:AVERAGE: %6.0lf"
        "PRINT:cpu_perc:MAX: %6.0lf"
        "PRINT:result_data:AVERAGE: %6.2lf"
        "PRINT:result_data:MAX: %6.2lf"
        "PRINT:result_iops:AVERAGE: %6.0lf"
        "PRINT:result_iops:MAX: %6.0lf"
        "PRINT:result_net:AVERAGE: %6.2lf"
        "PRINT:result_net:MAX: %6.2lf"
        );
        my $answer = RRDp::read;

        if ( $$answer =~ "ERROR" ) {
          error("Rrdtool error : $$answer");
          next;
        }
        my $aaa = $$answer;
        ( undef, my $cpu, my $cpu_max, my $cpu_perc, my $cpu_perc_max, my $iops, my $iops_max, my $disk, my $disk_max, my $net, my $net_max ) = split( "\n", $aaa );
        $cpu          = nan_to_null($cpu);
        $cpu_max      = nan_to_null($cpu_max);
        $cpu_perc     = nan_to_null($cpu_perc);
        $cpu_perc_max = nan_to_null($cpu_perc_max);
        $disk         = nan_to_null($disk);
        $disk_max     = nan_to_null($disk_max);
        $iops         = nan_to_null($iops);
        $iops_max     = nan_to_null($iops_max);
        $net          = nan_to_null($net);
        $net_max      = nan_to_null($net_max);
        chomp($cpu);
        chomp($cpu_max);
        chomp($cpu_perc);
        chomp($cpu_perc_max);
        chomp($disk);
        chomp($disk_max);
        chomp($iops);
        chomp($iops_max);
        chomp($net);
        chomp($net_max);
        $line_cpu_to_tmp      .= ",$cpu,$cpu_max";
        $line_cpu_perc_to_tmp .= ",$cpu_perc,$cpu_perc_max";
        $line_disk_to_tmp     .= ",$disk,$disk_max";
        $line_iops_to_tmp     .= ",$iops,$iops_max";
        $line_net_to_tmp      .= ",$net,$net_max";
      }
      push @topten_xenserver, "$line_cpu_to_tmp";
      push @topten_xenserver, "$line_cpu_perc_to_tmp";
      push @topten_xenserver, "$line_disk_to_tmp";
      push @topten_xenserver, "$line_iops_to_tmp";
      push @topten_xenserver, "$line_net_to_tmp";
    }
  }
  ### PUSH ALL TO FILE
  my $topten_xenserver_file = "$tmpdir/topten_xenserver.tmp";
  open( TOP_XEN, "> $topten_xenserver_file" ) || error( "Cannot open $topten_xenserver_file: $!" . __FILE__ . ":" . __LINE__ ) && next;
  foreach my $line (@topten_xenserver) {
    print TOP_XEN "$line\n";
  }
  close TOP_XEN;
  print "topten file XenServer : updated " . localtime() . "\n";
}
#
# Azure
#
sub print_topten_azure {
  opendir( DIR, "$azure/vm/" ) || error( "can't opendir $azure/vm: $! :" . __FILE__ . ":" . __LINE__ ) && return;
  my @all_vms_azure = grep /\.rrd$/, readdir(DIR);
  closedir(DIR);
  my @topten_azure;
  foreach my $rrd_file (@all_vms_azure) {
    my $vm_rrd  = "$azure/vm/$rrd_file";
    my $vm_uuid = "$rrd_file";
    $vm_uuid =~ s/\.rrd$//g;
    my $vm_name = AzureDataWrapper::get_label( 'vm', $vm_uuid );
    my $location;
    if ( exists $conf_azure_json->{specification}->{vm}->{$vm_uuid} ) {
      $location = $conf_azure_json->{specification}->{vm}->{$vm_uuid}->{location};
    }
    if ( -f $vm_rrd ) {
      $vm_rrd =~ s/:/\\:/g;
      next if ( -f $vm_rrd and ( -M $vm_rrd > 365 ) );    # not older 1 year
      print "$vm_rrd(vm_name:$vm_name) - found\n";
      $location = "-" if not defined $location;
      my $line_cpu_perc_to_tmp = "cpu_perc,$vm_name,$location";
      my $line_disk_to_tmp     = "disk,$vm_name,$location";
      my $line_iops_to_tmp     = "iops,$vm_name,$location";
      my $line_net_to_tmp      = "net,$vm_name,$location";

      foreach my $type ( "d", "w", "m", "y" ) {
        my $start_time = "now-1$type";
        my $end_time   = "now-1$type+1$type";
        my $name_out   = "test";
        my $b2mib      = 1024**2;
        my $b2mb       = 1000**2;
        RRDp::cmd qq(graph "$name_out"
        "--start" "$start_time"
        "--end" "$end_time"
        "DEF:cpu_used_perc=$vm_rrd:cpu_percent:AVERAGE"
        "DEF:iops_read=$vm_rrd:disk_read_ops:AVERAGE"
        "DEF:iops_write=$vm_rrd:disk_write_ops:AVERAGE"
        "DEF:data_read1=$vm_rrd:disk_read_bytes:AVERAGE"
        "DEF:data_write1=$vm_rrd:disk_write_bytes:AVERAGE"
        "DEF:net_read1=$vm_rrd:network_in:AVERAGE"
        "DEF:net_write1=$vm_rrd:network_out:AVERAGE"
        "CDEF:cpu_perc=cpu_used_perc,100,*"
        "CDEF:data_read2=data_read1,$b2mib,/"
        "CDEF:data_write2=data_write1,$b2mib,/"
        "CDEF:net_read2=net_read1,$b2mb,/"
        "CDEF:net_write2=net_write1,$b2mb,/"
        "CDEF:result_iops=iops_read,iops_write,+"
        "CDEF:result_data=data_read2,data_write2,+"
        "CDEF:result_net=net_read2,net_write2,+"
        "PRINT:cpu_perc:AVERAGE: %6.0lf"
        "PRINT:cpu_perc:MAX: %6.0lf"
        "PRINT:result_data:AVERAGE: %6.1lf"
        "PRINT:result_data:MAX: %6.1lf"
        "PRINT:result_iops:AVERAGE: %6.0lf"
        "PRINT:result_iops:MAX: %6.0lf"
        "PRINT:result_net:AVERAGE: %6.2lf"
        "PRINT:result_net:MAX: %6.2lf"
        );
        my $answer = RRDp::read;

        if ( $$answer =~ "ERROR" ) {
          error("Rrdtool error : $$answer");
          next;
        }
        my $aaa = $$answer;
        ( undef, my $cpu_perc, my $cpu_perc_max, my $iops, my $iops_max, my $disk, my $disk_max, my $net, my $net_max ) = split( "\n", $aaa );
        $cpu_perc     = nan_to_null($cpu_perc);
        $cpu_perc_max = nan_to_null($cpu_perc_max);
        $disk         = nan_to_null($disk);
        $disk_max     = nan_to_null($disk_max);
        $iops         = nan_to_null($iops);
        $iops_max     = nan_to_null($iops_max);
        $net          = nan_to_null($net);
        $net_max      = nan_to_null($net_max);
        chomp($cpu_perc);
        chomp($cpu_perc_max);
        chomp($disk);
        chomp($disk_max);
        chomp($iops);
        chomp($iops_max);
        chomp($net);
        chomp($net_max);
        $line_cpu_perc_to_tmp .= ",$cpu_perc,$cpu_perc_max";
        $line_disk_to_tmp     .= ",$disk,$disk_max";
        $line_iops_to_tmp     .= ",$iops,$iops_max";
        $line_net_to_tmp      .= ",$net,$net_max";
      }
      push @topten_azure, "$line_cpu_perc_to_tmp";
      push @topten_azure, "$line_disk_to_tmp";
      push @topten_azure, "$line_iops_to_tmp";
      push @topten_azure, "$line_net_to_tmp";
    }
  }
  ### PUSH ALL TO FILE
  my $topten_azure_file = "$tmpdir/topten_azure.tmp";
  open( TOP_AZUR, "> $topten_azure_file" ) || error( "Cannot open $topten_azure_file: $!" . __FILE__ . ":" . __LINE__ ) && next;
  foreach my $line (@topten_azure) {
    print TOP_AZUR "$line\n";
  }
  close TOP_AZUR;
  print "topten file Azure : updated " . localtime() . "\n";
}
#
# OracleDB
#
sub print_topten_oracledb {
  my @topten_oracledb;
  foreach my $db_alias ( keys %{$instance_names} ) {
    my @dbs = keys %{ $instance_names->{$db_alias} };
    foreach my $db_ip (@dbs) {
      my $cpu_rrd = "$ordb/$db_alias/CPU_info/$db_ip-CPU_info.rrd";
      my $db_name = $instance_names->{$db_alias}{$db_ip};
      if ( -f $cpu_rrd ) {
        $cpu_rrd =~ s/:/\\:/g;
        next if ( -f $cpu_rrd and ( -M $cpu_rrd > 365 ) );    # not older 1 year
        print "$cpu_rrd(db_name:$db_name) - found\n";
        my $line_cpu_to_tmp = "cpu_cores,$db_ip,$db_name,$db_alias";
        foreach my $type ( "d", "w", "m", "y" ) {
          my $start_time = "now-1$type";
          my $end_time   = "now-1$type+1$type";
          my $name_out   = "test";
          RRDp::cmd qq(graph "$name_out"
          "--start" "$start_time"
          "--end" "$end_time"
          "DEF:CPUusgPT=$cpu_rrd:CPUusgPT:AVERAGE"
          "DEF:CPUusgPS=$cpu_rrd:CPUusgPS:AVERAGE"
          "CDEF:CPUusgPT_v=CPUusgPT,100,/"
          "CDEF:CPUusgPS_v=CPUusgPS,100,/"
          "PRINT:CPUusgPS_v:AVERAGE: %6.1lf"
          "PRINT:CPUusgPS_v:MAX: %6.1lf"
          );
          my $answer = RRDp::read;
          if ( $$answer =~ "ERROR" ) {
            error("Rrdtool error : $$answer");
            next;
          }
          my $aaa = $$answer;
          ( undef, my $cpu, my $cpu_max ) = split( "\n", $aaa );
          $cpu     = nan_to_null($cpu);
          $cpu_max = nan_to_null($cpu_max);
          chomp($cpu);
          chomp($cpu_max);
          $line_cpu_to_tmp .= ",$cpu,$cpu_max";
        }
        push @topten_oracledb, "$line_cpu_to_tmp";
      }
      my $session_rrd = "$ordb/$db_alias/Session_info/$db_ip-Session_info.rrd";
      if ( -f $session_rrd ) {
        $session_rrd =~ s/:/\\:/g;
        print "$session_rrd(db_alias:$db_alias) - found\n";
        my $line_currlog_to_tmp = "session,$db_ip,$db_name,$db_alias";
        foreach my $type ( "d", "w", "m", "y" ) {
          my $start_time = "now-1$type";
          my $end_time   = "now-1$type+1$type";
          my $name_out   = "test";
          RRDp::cmd qq(graph "$name_out"
          "--start" "$start_time"
          "--end" "$end_time"
          "DEF:CrntLgnsCnt=$session_rrd:CrntLgnsCnt:AVERAGE"
          "PRINT:CrntLgnsCnt:AVERAGE: %6.0lf"
          "PRINT:CrntLgnsCnt:MAX: %6.0lf"
          );
          my $answer = RRDp::read;
          if ( $$answer =~ "ERROR" ) {
            error("Rrdtool error : $$answer");
            next;
          }
          my $aaa = $$answer;
          ( undef, my $curr_log, my $curr_log_max ) = split( "\n", $aaa );
          $curr_log     = nan_to_null($curr_log);
          $curr_log_max = nan_to_null($curr_log_max);
          chomp($curr_log);
          chomp($curr_log_max);
          $line_currlog_to_tmp .= ",$curr_log,$curr_log_max";
        }
        push @topten_oracledb, "$line_currlog_to_tmp";
      }
      my $io_rrd = "$ordb/$db_alias/Data_rate/$db_ip-Data_rate.rrd";
      if ( -f $io_rrd ) {
        $io_rrd =~ s/:/\\:/g;
        next if ( -f $io_rrd and ( -M $io_rrd > 365 ) );    # not older 1 year
        print "$io_rrd(db_alias:$db_alias) - found\n";
        my $line_io_to_tmp   = "io,$db_ip,$db_name,$db_alias";
        my $line_data_to_tmp = "data,$db_ip,$db_name,$db_alias";
        foreach my $type ( "d", "w", "m", "y" ) {
          my $start_time = "now-1$type";
          my $end_time   = "now-1$type+1$type";
          my $name_out   = "test";
          RRDp::cmd qq(graph "$name_out"
          "--start" "$start_time"
          "--end" "$end_time"
          "DEF:IORqstPS=$io_rrd:IORqstPS:AVERAGE"
          "DEF:IOMbPS=$io_rrd:IOMbPS:AVERAGE"
          "PRINT:IORqstPS:AVERAGE: %6.0lf"
          "PRINT:IORqstPS:MAX: %6.0lf"
          "PRINT:IOMbPS:AVERAGE: %6.2lf"
          "PRINT:IOMbPS:MAX: %6.2lf"
          );
          my $answer = RRDp::read;
          if ( $$answer =~ "ERROR" ) {
            error("Rrdtool error : $$answer");
            next;
          }
          my $aaa = $$answer;
          ( undef, my $io, my $io_max, my $data, my $data_max ) = split( "\n", $aaa );
          $io       = nan_to_null($io);
          $io_max   = nan_to_null($io_max);
          $data     = nan_to_null($data);
          $data_max = nan_to_null($data_max);
          chomp($io);
          chomp($io_max);
          chomp($data);
          chomp($data_max);
          $line_io_to_tmp   .= ",$io,$io_max";
          $line_data_to_tmp .= ",$data,$data_max";
        }
        push @topten_oracledb, "$line_io_to_tmp";
        push @topten_oracledb, "$line_data_to_tmp";
      }
    }
  }
  ### PUSH ALL TO FILE
  my $topten_oracledb_file = "$tmpdir/topten_oracledb.tmp";
  open( TOP_ORDB, "> $topten_oracledb_file" ) || error( "Cannot open $topten_oracledb_file: $!" . __FILE__ . ":" . __LINE__ ) && next;
  foreach my $line (@topten_oracledb) {
    print TOP_ORDB "$line\n";
  }
  close TOP_ORDB;
  print "topten file OracleDB : updated " . localtime() . "\n";
}
#
# Nutanix
#
sub print_topten_nutanix {
  opendir( DIR, "$nutanix/VM/" ) || error( "can't opendir $nutanix/VM/: $! :" . __FILE__ . ":" . __LINE__ ) && return;
  my @all_vms_nutanix = grep !/^\.\.?$/, readdir(DIR);
  closedir(DIR);
  my @topten_nutanix;
  foreach my $vm_dir (@all_vms_nutanix) {
    my $vm_rrd  = "$nutanix/VM/$vm_dir";
    my $vm_uuid = "$vm_dir";
    $vm_uuid =~ s/\.rrd$//g;
    my $vm_name      = NutanixDataWrapper::get_label( 'vm', $vm_uuid );
    my $cluster_uuid = "";
    my $cluster_name = "";
    if ( exists $conf_nutanix_json->{specification}->{vm}->{$vm_uuid} ) {
      $cluster_uuid = $conf_nutanix_json->{specification}->{vm}->{$vm_uuid}->{parent_cluster};
      $cluster_name = NutanixDataWrapper::get_label( 'cluster', $cluster_uuid );
    }
    if ( $cluster_name eq "" ) {next}
    if ( -f $vm_rrd ) {
      $vm_rrd =~ s/:/\\:/g;
      next if ( -f $vm_rrd and ( -M $vm_rrd > 365 ) );    # not older 1 year
      print "$vm_rrd(vm_name:$vm_name) - found\n";
      my $line_cpu_to_tmp      = "load_cpu,$vm_name,$cluster_name";
      my $line_cpu_perc_to_tmp = "cpu_perc,$vm_name,$cluster_name";
      my $line_data_to_tmp     = "data,$vm_name,$cluster_name";
      my $line_iops_to_tmp     = "iops,$vm_name,$cluster_name";
      my $line_net_to_tmp      = "net,$vm_name,$cluster_name";

      foreach my $type ( "d", "w", "m", "y" ) {
        my $start_time = "now-1$type";
        my $end_time   = "now-1$type+1$type";
        my $name_out   = "test";
        my $b2mib      = 1024**2;
        my $b2mb       = 1000**2;
        RRDp::cmd qq(graph "$name_out"
        "--start" "$start_time"
        "--end" "$end_time"
        "DEF:cpu_util=$vm_rrd:cpu:AVERAGE"
        "DEF:cpu_perc=$vm_rrd:cpu:AVERAGE"
        "DEF:read_iops=$vm_rrd:vbd_iops_read:AVERAGE"
        "DEF:write_iops=$vm_rrd:vbd_iops_write:AVERAGE"
        "DEF:data_total=$vm_rrd:vbd_total:AVERAGE"
        "DEF:net_write=$vm_rrd:net_transmitted:AVERAGE"
        "DEF:net_read=$vm_rrd:net_received:AVERAGE"
        "CDEF:net_read_mbps=net_read,$b2mb,/"
        "CDEF:net_write_mbps=net_write,$b2mb,/"
        "CDEF:data_total_mbps=data_total,$b2mib,/"
        "CDEF:cpu_perc_res=cpu_perc,100,*"
        "CDEF:result_iops=read_iops,write_iops,+"
        "CDEF:result_net=net_read_mbps,net_write_mbps,+"
        "PRINT:cpu_util:AVERAGE: %6.1lf"
        "PRINT:cpu_util:MAX: %6.1lf"
        "PRINT:cpu_perc_res:AVERAGE: %6.0lf"
        "PRINT:cpu_perc_res:MAX: %6.0lf"
        "PRINT:result_iops:AVERAGE: %6.0lf"
        "PRINT:result_iops:MAX: %6.0lf"
        "PRINT:data_total_mbps:AVERAGE: %6.2lf"
        "PRINT:data_total_mbps:MAX: %6.2lf"
        "PRINT:result_net:AVERAGE: %6.2lf"
        "PRINT:result_net:MAX: %6.2lf"
        );
        my $answer = RRDp::read;

        if ( $$answer =~ "ERROR" ) {
          error("Rrdtool error : $$answer");
          next;
        }
        my $aaa = $$answer;
        ( undef, my $cpu, my $cpu_max, my $cpu_perc, my $cpu_perc_max, my $iops, my $iops_max, my $data, my $data_max, my $net, my $net_max ) = split( "\n", $aaa );
        $cpu          = nan_to_null($cpu);
        $cpu_max      = nan_to_null($cpu_max);
        $cpu_perc     = nan_to_null($cpu_perc);
        $cpu_perc_max = nan_to_null($cpu_perc_max);
        $data         = nan_to_null($data);
        $data_max     = nan_to_null($data_max);
        $iops         = nan_to_null($iops);
        $iops_max     = nan_to_null($iops_max);
        $net          = nan_to_null($net);
        $net_max      = nan_to_null($net_max);
        chomp($cpu);
        chomp($cpu_max);
        chomp($cpu_perc);
        chomp($cpu_perc_max);
        chomp($data);
        chomp($data_max);
        chomp($iops);
        chomp($iops_max);
        chomp($net);
        chomp($net_max);
        $line_cpu_to_tmp      .= ",$cpu,$cpu_max";
        $line_cpu_perc_to_tmp .= ",$cpu_perc,$cpu_perc_max";
        $line_data_to_tmp     .= ",$data,$data_max";
        $line_iops_to_tmp     .= ",$iops,$iops_max";
        $line_net_to_tmp      .= ",$net,$net_max";
      }
      push @topten_nutanix, "$line_cpu_to_tmp";
      push @topten_nutanix, "$line_cpu_perc_to_tmp";
      push @topten_nutanix, "$line_data_to_tmp";
      push @topten_nutanix, "$line_iops_to_tmp";
      push @topten_nutanix, "$line_net_to_tmp";
    }
  }
  ### PUSH ALL TO FILE
  my $topten_nutanix_file = "$tmpdir/topten_nutanix.tmp";
  open( TOP_NUT, "> $topten_nutanix_file" ) || error( "Cannot open $topten_nutanix_file: $!" . __FILE__ . ":" . __LINE__ ) && next;
  foreach my $line (@topten_nutanix) {
    print TOP_NUT "$line\n";
  }
  close TOP_NUT;
  print "topten file Nutanix : updated " . localtime() . "\n";
}
#
# PostgreSQL
#
sub print_topten_postgresql {
  my @topten_postgresql;
  foreach my $db_alias ( keys %{$instance_names_postgres} ) {
    my @postgres_servers = keys %{ $instance_names_postgres->{$db_alias} };
    foreach my $db_ip (@postgres_servers) {
      my $server_name = $instance_names_postgres->{$db_alias}{$db_ip}{alias};
      my @dbs         = keys %{ $instance_names_postgres->{$db_alias}{$db_ip}{_dbs} };
      foreach my $db_uuid (@dbs) {
        my $db_name     = $instance_names_postgres->{$db_alias}{$db_ip}{_dbs}{$db_uuid}{label};
        my $file_name   = $instance_names_postgres->{$db_alias}{$db_ip}{_dbs}{$db_uuid}{filename};
        my $stat_rrd    = "$postgres/$server_name/$file_name/Stat/stat.rrd";
        my $session_rrd = "$postgres/$server_name/$file_name/Sessions/sessions.rrd";
        print "$stat_rrd\n";
        if ( -f $stat_rrd ) {
          $stat_rrd =~ s/:/\\:/g;
          next if ( -f $stat_rrd and ( -M $stat_rrd > 365 ) );    # not older 1 year
          print "$stat_rrd(server_name:$server_name) - found\n";
          my $line_read_to_tmp   = "read_blocks,$server_name,$db_name";
          my $line_return_to_tmp = "tuples_return,$server_name,$db_name";
          foreach my $type ( "d", "w", "m", "y" ) {
            my $start_time = "now-1$type";
            my $end_time   = "now-1$type+1$type";
            my $name_out   = "test";
            my $b2mib      = 1024**2;
            my $b2mb       = 1000**2;
            RRDp::cmd qq(graph "$name_out"
            "--start" "$start_time"
            "--end" "$end_time"
            "DEF:read_total=$stat_rrd:blksrd:AVERAGE"
            "DEF:return_total=$stat_rrd:tpretrnd:AVERAGE"
            "PRINT:read_total:AVERAGE: %6.0lf"
            "PRINT:read_total:MAX: %6.0lf"
            "PRINT:return_total:AVERAGE: %6.0lf"
            "PRINT:return_total:MAX: %6.0lf"
            );
            my $answer = RRDp::read;

            if ( $$answer =~ "ERROR" ) {
              error("Rrdtool error : $$answer");
              next;
            }
            my $aaa = $$answer;
            ( undef, my $read, my $read_max, my $return, my $return_max ) = split( "\n", $aaa );
            $read       = nan_to_null($read);
            $read_max   = nan_to_null($read_max);
            $return     = nan_to_null($return);
            $return_max = nan_to_null($return_max);
            chomp($read);
            chomp($read_max);
            chomp($return);
            chomp($return_max);
            $line_read_to_tmp   .= ",$read,$read_max";
            $line_return_to_tmp .= ",$return,$return_max";
          }
          push @topten_postgresql, "$line_read_to_tmp";
          push @topten_postgresql, "$line_return_to_tmp";
        }
        if ( -f $session_rrd ) {
          $session_rrd =~ s/:/\\:/g;
          next if ( -f $session_rrd and ( -M $session_rrd > 365 ) );    # not older 1 year
          my $line_session_to_tmp = "session_active,$server_name,$db_name";
          foreach my $type ( "d", "w", "m", "y" ) {
            my $start_time = "now-1$type";
            my $end_time   = "now-1$type+1$type";
            my $name_out   = "test";
            my $b2mib      = 1024**2;
            my $b2mb       = 1000**2;
            RRDp::cmd qq(graph "$name_out"
            "--start" "$start_time"
            "--end" "$end_time"
            "DEF:active_total=$session_rrd:ctv:AVERAGE"
            "PRINT:active_total:AVERAGE: %6.0lf"
            "PRINT:active_total:MAX: %6.0lf"
            );
            my $answer = RRDp::read;

            if ( $$answer =~ "ERROR" ) {
              error("Rrdtool error : $$answer");
              next;
            }
            my $aaa = $$answer;
            ( undef, my $session_active, my $session_active_max ) = split( "\n", $aaa );
            $session_active     = nan_to_null($session_active);
            $session_active_max = nan_to_null($session_active_max);
            chomp($session_active);
            chomp($session_active_max);
            $line_session_to_tmp .= ",$session_active,$session_active_max";
          }
          push @topten_postgresql, "$line_session_to_tmp";

        }
      }
    }
  }
  ### PUSH ALL TO FILE
  my $topten_postgresql_file = "$tmpdir/topten_postgresql.tmp";
  open( TOP_POST, "> $topten_postgresql_file" ) || error( "Cannot open $topten_postgresql_file: $!" . __FILE__ . ":" . __LINE__ ) && next;
  foreach my $line (@topten_postgresql) {
    print TOP_POST "$line\n";
  }
  close TOP_POST;
  print "topten file Postgre SQL : updated " . localtime() . "\n";
}
#
# Microsoft SQL
#
sub print_topten_microsql {
  my @topten_microsql;
  foreach my $db_alias ( keys %{$instance_names_microsql} ) {
    my @sql_servers = keys %{ $instance_names_microsql->{$db_alias} };
    foreach my $sql_ip (@sql_servers) {
      my $server_name = $instance_names_microsql->{$db_alias}{$sql_ip}{alias};
      my @dbs         = keys %{ $instance_names_microsql->{$db_alias}{$sql_ip}{_dbs} };
      foreach my $db_uuid (@dbs) {
        my $db_name     = $instance_names_microsql->{$db_alias}{$sql_ip}{_dbs}{$db_uuid}{label};
        my $virt_rrd    = "$microsql/$server_name/$db_name/Virtual/virt.rrd";
        my $counter_rrd = "$microsql/$server_name/$db_name/Counters/counters.rrd";
        if ( -f $virt_rrd ) {
          $virt_rrd =~ s/:/\\:/g;
          next if ( -f $virt_rrd and ( -M $virt_rrd > 365 ) );    # not older 1 year
          print "$virt_rrd(server_name:$server_name) - found\n";
          my $line_io_to_tmp   = "iops,$server_name,$db_name";
          my $line_data_to_tmp = "data,$server_name,$db_name";
          foreach my $type ( "d", "w", "m", "y" ) {
            my $start_time = "now-1$type";
            my $end_time   = "now-1$type+1$type";
            my $name_out   = "test";
            my $b2mib      = 1024**2;
            my $b2mb       = 1000**2;
            RRDp::cmd qq(graph "$name_out"
            "--start" "$start_time"
            "--end" "$end_time"
            "DEF:io_total=$virt_rrd:io_t:AVERAGE"
            "DEF:data_total=$virt_rrd:data_t:AVERAGE"
            "CDEF:data_total_mbps=data_total,1000,/"
            "PRINT:io_total:AVERAGE: %6.0lf"
            "PRINT:io_total:MAX: %6.0lf"
            "PRINT:data_total_mbps:AVERAGE: %6.2lf"
            "PRINT:data_total_mbps:MAX: %6.2lf"
            );
            my $answer = RRDp::read;

            if ( $$answer =~ "ERROR" ) {
              error("Rrdtool error : $$answer");
              next;
            }
            my $aaa = $$answer;
            ( undef, my $io, my $io_max, my $data, my $data_max ) = split( "\n", $aaa );
            $data     = sprintf "%.1f", $data;
            $data_max = sprintf "%.1f", $data_max;
            $io       = nan_to_null($io);
            $io_max   = nan_to_null($io_max);
            $data     = nan_to_null($data);
            $data_max = nan_to_null($data_max);
            chomp($io);
            chomp($io_max);
            chomp($data);
            chomp($data_max);
            $line_io_to_tmp   .= ",$io,$io_max";
            $line_data_to_tmp .= ",$data,$data_max";
          }
          push @topten_microsql, "$line_io_to_tmp";
          push @topten_microsql, "$line_data_to_tmp";
        }
        if ( -f $counter_rrd ) {
          $counter_rrd =~ s/:/\\:/g;
          next if ( -f $counter_rrd and ( -M $counter_rrd > 365 ) );    # not older 1 year
          print "$counter_rrd(server_name:$server_name) - found\n";
          my $line_con_to_tmp = "user_connect,$server_name,$db_name";
          foreach my $type ( "d", "w", "m", "y" ) {
            my $start_time = "now-1$type";
            my $end_time   = "now-1$type+1$type";
            my $name_out   = "test";
            my $b2mib      = 1024**2;
            my $b2mb       = 1000**2;
            RRDp::cmd qq(graph "$name_out"
            "--start" "$start_time"
            "--end" "$end_time"
            "DEF:user_connect=$counter_rrd:UsrCons:AVERAGE"
            "PRINT:user_connect:AVERAGE: %6.0lf"
            "PRINT:user_connect:MAX: %6.0lf"
            );
            my $answer = RRDp::read;

            if ( $$answer =~ "ERROR" ) {
              error("Rrdtool error : $$answer");
              next;
            }
            my $aaa = $$answer;
            ( undef, my $connect, my $connect_max ) = split( "\n", $aaa );
            $connect     = nan_to_null($connect);
            $connect_max = nan_to_null($connect_max);
            chomp($connect);
            chomp($connect_max);
            $line_con_to_tmp .= ",$connect,$connect_max";
          }
          push @topten_microsql, "$line_con_to_tmp";
        }
      }
    }
  }
  ### PUSH ALL TO FILE
  my $topten_microsql_file = "$tmpdir/topten_microsql.tmp";
  open( TOP_MICRO, "> $topten_microsql_file" ) || error( "Cannot open $topten_microsql_file: $!" . __FILE__ . ":" . __LINE__ ) && next;
  foreach my $line (@topten_microsql) {
    print TOP_MICRO "$line\n";
  }
  close TOP_MICRO;
  print "topten file Microsoft SQL : updated " . localtime() . "\n";
}
#
# FusionCompute
#
sub print_topten_fusion {
  opendir( DIR, "$fusion/VM/" ) || error( "can't opendir $fusion/VM/: $! :" . __FILE__ . ":" . __LINE__ ) && return;
  my @all_vm_fusion = grep !/^\.\.?$/, readdir(DIR);
  closedir(DIR);
  my @topten_fusion;
  foreach my $vm_dir (@all_vm_fusion) {
    my $vm_uuid = $vm_dir;
    $vm_uuid =~ s/\.rrd$//g;
    my $vm_name = FusionComputeDataWrapper::get_label( 'vm', $vm_uuid );
    my ( $host_name, $cluster_name );
    if ( exists $conf_fusion_json->{specification}->{vm}->{$vm_uuid}->{hostName} ) {
      $host_name = $conf_fusion_json->{specification}->{vm}->{$vm_uuid}->{hostName};
    }
    if ( exists $conf_fusion_json->{specification}->{vm}->{$vm_uuid}->{clusterName} ) {
      $cluster_name = $conf_fusion_json->{specification}->{vm}->{$vm_uuid}->{clusterName};
    }
    my $vm_rrd = "$fusion/VM/$vm_dir";
    if ( -f $vm_rrd ) {
      $vm_rrd =~ s/:/\\:/g;
      next if ( -f $vm_rrd and ( -M $vm_rrd > 365 ) );    # not older 1 year
      my $division = 1024;
      print "$vm_rrd(vm_name:$vm_name) - found\n";
      my $line_cpu_to_tmp        = "load_cpu,$vm_name,$host_name,$cluster_name";
      my $line_cpu_perc_to_tmp   = "cpu_perc,$vm_name,$host_name,$cluster_name";
      my $line_data_to_tmp       = "data,$vm_name,$host_name,$cluster_name";
      my $line_iops_to_tmp       = "iops,$vm_name,$host_name,$cluster_name";
      my $line_net_to_tmp        = "net,$vm_name,$host_name,$cluster_name";
      my $line_disk_usage_to_tmp = "disk_usage,$vm_name,$host_name,$cluster_name";

      foreach my $type ( "d", "w", "m", "y" ) {
        my $start_time = "now-1$type";
        my $end_time   = "now-1$type+1$type";
        my $name_out   = "test";
        my $b2mib      = 1024**2;
        my $b2mb       = 1000**2;
        RRDp::cmd qq(graph "$name_out"
        "--start" "$start_time"
        "--end" "$end_time"
        "DEF:cpu_util=$vm_rrd:cpu_quantity:AVERAGE"
        "DEF:cpu_perc=$vm_rrd:cpu_usage:AVERAGE"
        "DEF:data_write=$vm_rrd:disk_io_out:AVERAGE"
        "DEF:data_read=$vm_rrd:disk_io_in:AVERAGE"
        "DEF:iops_write=$vm_rrd:disk_rd_ios:AVERAGE"
        "DEF:iops_read=$vm_rrd:disk_wr_ios:AVERAGE"
        "DEF:net_write=$vm_rrd:nic_byte_out:AVERAGE"
        "DEF:net_read=$vm_rrd:nic_byte_in:AVERAGE"
        "DEF:disk_used=$vm_rrd:disk_usage:AVERAGE"
        "CDEF:usage=cpu_perc,100,/"
        "CDEF:used=cpu_util,usage,*"
        "CDEF:cpu_perc1=cpu_perc,1,*"
        "CDEF:read=data_read,$division,/"
        "CDEF:write=data_write,$division,/"
        "CDEF:net_read1=net_read,$division,/"
        "CDEF:net_write1=net_write,$division,/"
        "CDEF:usage_disk=disk_used,1,*"
        "CDEF:result_data=read,write,+"
        "CDEF:result_iops=iops_write,iops_read,+"
        "CDEF:result_net=net_write1,net_read1,+"
        "PRINT:used:AVERAGE: %6.1lf"
        "PRINT:used:MAX: %6.1lf"
        "PRINT:cpu_perc1:AVERAGE: %6.0lf"
        "PRINT:cpu_perc1:MAX: %6.0lf"
        "PRINT:result_data:AVERAGE: %6.2lf"
        "PRINT:result_data:MAX: %6.2lf"
        "PRINT:result_iops:AVERAGE: %6.0lf"
        "PRINT:result_iops:MAX: %6.0lf"
        "PRINT:result_net:AVERAGE: %6.2lf"
        "PRINT:result_net:MAX: %6.2lf"
        "PRINT:usage_disk:AVERAGE: %6.2lf"
        "PRINT:usage_disk:MAX: %6.2lf"
        );
        my $answer = RRDp::read;

        if ( $$answer =~ "ERROR" ) {
          error("Rrdtool error : $$answer");
          next;
        }
        my $aaa = $$answer;
        ( undef, my $cpu, my $cpu_max, my $cpu_perc, my $cpu_perc_max, my $data, my $data_max, my $iops, my $iops_max, my $net, my $net_max, my $disk_usage, my $disk_usage_max ) = split( "\n", $aaa );
        $cpu            = nan_to_null($cpu);
        $cpu_max        = nan_to_null($cpu_max);
        $cpu_perc       = nan_to_null($cpu_perc);
        $cpu_perc_max   = nan_to_null($cpu_perc_max);
        $data           = nan_to_null($data);
        $data_max       = nan_to_null($data_max);
        $iops           = nan_to_null($iops);
        $iops_max       = nan_to_null($iops_max);
        $net            = nan_to_null($net);
        $net_max        = nan_to_null($net_max);
        $disk_usage     = nan_to_null($disk_usage);
        $disk_usage_max = nan_to_null($disk_usage_max);
        chomp($cpu);
        chomp($cpu_max);
        chomp($cpu_perc);
        chomp($cpu_perc_max);
        chomp($data);
        chomp($data_max);
        chomp($iops);
        chomp($iops_max);
        chomp($net);
        chomp($net_max);
        chomp($disk_usage);
        chomp($disk_usage_max);
        $line_cpu_to_tmp        .= ",$cpu,$cpu_max";
        $line_cpu_perc_to_tmp   .= ",$cpu_perc,$cpu_perc_max";
        $line_data_to_tmp       .= ",$data,$data_max";
        $line_iops_to_tmp       .= ",$iops,$iops_max";
        $line_net_to_tmp        .= ",$net,$net_max";
        $line_disk_usage_to_tmp .= ",$disk_usage,$disk_usage_max";
      }
      push @topten_fusion, "$line_cpu_to_tmp";
      push @topten_fusion, "$line_cpu_perc_to_tmp";
      push @topten_fusion, "$line_data_to_tmp";
      push @topten_fusion, "$line_iops_to_tmp";
      push @topten_fusion, "$line_net_to_tmp";
      push @topten_fusion, "$line_disk_usage_to_tmp";
    }
  }
  ### PUSH ALL TO FILE
  my $topten_fusion_file = "$tmpdir/topten_fusion.tmp";
  open( TOP_FUS, "> $topten_fusion_file" ) || error( "Cannot open $topten_fusion_file: $!" . __FILE__ . ":" . __LINE__ ) && next;
  foreach my $line (@topten_fusion) {
    print TOP_FUS "$line\n";
  }
  close TOP_FUS;
  print "topten file FusionCompute : updated " . localtime() . "\n";
}

sub error {
  my $text     = shift;
  my $act_time = localtime();
  chomp($text);

  print "ERROR          : $text : $!\n";
  print STDERR "$act_time: $text : $!\n";

  return 1;
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
