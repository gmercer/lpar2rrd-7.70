use strict;
use warnings;
use POSIX;
use Time::Local;
use Data::Dumper;
use JSON;
use File::Glob qw(bsd_glob GLOB_TILDE);

use Xorux_lib qw(read_json write_json uuid_big_endian_format);
use OVirtDataWrapper;
use NutanixDataWrapper;
use FusionComputeDataWrapper;
use PowerDataWrapper;
use PowerMenu;

#use Time::HiRes qw(time);

binmode( STDOUT, ":utf8" );    # take care about unicode chars

#`. /home/lpar2rrd/lpar2rrd/etc/lpar2rrd.cfg`;

###### RUN SCRIPT WITHOUT ARGUMENTS (PRINT ALL SERVER):
######
###### . /home/lpar2rrd/lpar2rrd/etc/lpar2rrd.cfg ; $PERL ./bin/find_active_lpar.pl
######

###### RUN SCRIPT WITH ARGUMENTS (PRINT ONLY ONE SERVER):
######
###### . /home/lpar2rrd/lpar2rrd/etc/lpar2rrd.cfg ; $PERL ./bin/find_active_lpar.pl name_server
######   (for example - .  /home/lpar2rrd/lpar2rrd/etc/lpar2rrd.cfg ; $PERL ./bin/find_active_lpar.pl Power750_02)
######

###### RUN SCRIPT FOR VMWARE ALL
######
###### . /home/lpar2rrd/lpar2rrd/etc/lpar2rrd.cfg ; $PERL ./bin/find_active_lpar.pl VMWARE
######

###### RUN SCRIPT FOR HITACHI ALL
######
###### . /home/lpar2rrd/lpar2rrd/etc/lpar2rrd.cfg ; $PERL ./bin/find_active_lpar.pl HITACHI
######

###### RUN SCRIPT FOR HYPERV ALL
######
###### . /home/lpar2rrd/lpar2rrd/etc/lpar2rrd.cfg ; $PERL ./bin/find_active_lpar.pl HYPERV
######

###### RUN SCRIPT FOR SOLARIS machines
######
###### . /home/lpar2rrd/lpar2rrd/etc/lpar2rrd.cfg ; $PERL ./bin/find_active_lpar.pl SOLARIS-L
######

###### RUN SCRIPT for linux_uuid table
######
###### export JSON_PRETTY=1;. /home/lpar2rrd/lpar2rrd/etc/lpar2rrd.cfg ; $PERL ./bin/find_active_lpar.pl "AGENT_UUIDS"
######

######################### PRINT HEADER IF PROGRAM STARTED FROM BROWSER
if ( defined $ENV{FROMWEB} && $ENV{FROMWEB} eq "1" ) {
  print "Content-type: text/plain\n\n";
}

# flush after every write
$| = 1;

defined $ENV{INPUTDIR} || error( " Not defined INPUTDIR, probably not read etc/lpar2rrd.cfg " . __FILE__ . ":" . __LINE__ ) && exit 1;
my $basedir              = $ENV{INPUTDIR};
my $actual_unix_time     = time;
my $last_ten_days        = 10 * 86400;                            ### ten days back
my $actual_last_ten_days = $actual_unix_time - $last_ten_days;    ### ten days back with actual unix time-
my $year_back            = time - 31536000;

my $active_days_vm = 30;
if ( defined $ENV{VMWARE_ACTIVE_DAYS} && $ENV{VMWARE_ACTIVE_DAYS} > 1 && $ENV{VMWARE_ACTIVE_DAYS} < 3650 ) {
  $active_days_vm = $ENV{VMWARE_ACTIVE_DAYS};
}
my $last_30_days_vm        = $active_days_vm * 86400;                 ### 30 days back
my $actual_last_30_days_vm = $actual_unix_time - $last_30_days_vm;    ### 30 days back with actual unix time-

my $active_days_power = 30;
if ( defined $ENV{POWER_ACTIVE_DAYS} && $ENV{POWER_ACTIVE_DAYS} > 1 && $ENV{POWER_ACTIVE_DAYS} < 3650 ) {
  $active_days_power = $ENV{POWER_ACTIVE_DAYS};
}
my $last_30_days_power        = $active_days_power * 86400;                 ### 30 days back
my $actual_last_30_days_power = $actual_unix_time - $last_30_days_power;    ### 30 days back with actual unix time-

my $wrkdir             = "$basedir/data";
my $no_hmc_dir         = "$wrkdir/Linux/no_hmc";
my $agents_uuid_file   = "$no_hmc_dir/linux_uuid_name.json";
my $oraclevm_conf_file = "$wrkdir/OracleVM/conf.json";
my %dictionary_orvm    = ();

my $tmpdir = "$basedir/tmp";
if ( defined $ENV{TMPDIR_LPAR} ) {
  $tmpdir = $ENV{TMPDIR_LPAR};
}

opendir( DIR, "$wrkdir" ) || error( " directory does not exists : $wrkdir " . __FILE__ . ":" . __LINE__ ) && exit 1;
my @wrkdir_all = grep !/^\.\.?$/, readdir(DIR);
closedir(DIR);

if ( -f $oraclevm_conf_file ) {
  my ( $code, $ref ) = Xorux_lib::read_json($oraclevm_conf_file);
  %dictionary_orvm = $code ? %{$ref} : ();
}

my $list_of_vm = "$wrkdir/vmware_VMs/vm_uuid_name.txt";
my $vm_dir     = "$wrkdir/vmware_VMs";
my @vm_list;
if ( -e $list_of_vm ) {    ####### ALL VM servers in @vm_list
  open FC, '<:encoding(UTF-8)', "$list_of_vm" || error( "Cannot read $list_of_vm: $!" . __FILE__ . ":" . __LINE__ );
  @vm_list = <FC>;
  close(FC);
}

my $s               = ":";
my $deleted         = "R:";
my $actived         = "L:";
my %hash_lpar       = ();
my %hash_wpar       = ();
my %hash_wlm        = ();
my %hash_vm         = ();
my %hash_timestamp1 = ();
my $wpar_menu       = "W:";
my $wlm_menu        = "WLM:";
my $server_list_cfg = "$basedir/etc/alias.cfg";
my @lines_dualhmc1  = "";

################ look for hitachi lpars uuid
my @hitachi_uuid_txt = <$wrkdir/Hitachi/*/lpar_uuids.txt>;
my %hitachi_lpar_uuids;
foreach my $file (@hitachi_uuid_txt) {
  if ( open( FH, " < $file" ) ) {
    while ( my $line = <FH> ) {
      my ( $uuid, undef, undef ) = split /,/, $line;
      $hitachi_lpar_uuids{$uuid} = 1;
    }
    close FH;
  }
  else {
    error( "Cannot open $file: $!" . __FILE__ . ":" . __LINE__ );
    next;
  }
}
################ look for ovirt lpars uuid
my %ovirt_uuids;

if ( -f "$wrkdir/oVirt/metadata.json" ) {
  %ovirt_uuids = %{ OVirtDataWrapper::get_conf_section('mapping') };
}

################ look for nutanix lpars uuid
my %nutanix_uuids;

if ( -f "$wrkdir/NUTANIX/mapping.json" ) {
  my $test_exists = NutanixDataWrapper::get_conf_section('mapping');
  if ( defined $test_exists && ref($test_exists) eq "HASH" ) {
    %nutanix_uuids = %{ NutanixDataWrapper::get_conf_section('mapping') };
  }
}

################ look for fusioncompute lpars uuid
my %fusioncompute_uuids;

if ( -f "$wrkdir/FusionCompute/mapping.json" ) {
  my $test_exists = FusionComputeDataWrapper::get_conf_section('mapping');
  if ( defined $test_exists && ref($test_exists) eq "HASH" ) {
    %fusioncompute_uuids = %{ FusionComputeDataWrapper::get_conf_section('mapping') };
  }
}
################ check alias.cfg for VM,WPAR,LPAR
my @alias_vmware;
my @alias_servers;
my @alias_servers_wpar;
if ( -e $server_list_cfg ) {
  open( FC, "< $server_list_cfg" ) || error( "Cannot read $server_list_cfg: $!" . __FILE__ . ":" . __LINE__ );
  my @server_list_config = <FC>;
  close(FC);
  @alias_vmware       = grep {/^VM:/} @server_list_config;      ### grep only "VM:" and save it in array
  @alias_servers      = grep {/^LPAR:/} @server_list_config;    ### grep only "LPAR:" and save it in array
  @alias_servers_wpar = grep {/^WPAR:/} @server_list_config;    ### grep only "WPAR:" and save it in array
}

################ read arguments (ONLY ONE SERVER!)
my ($param_server) = @ARGV;

if ( defined $param_server ) {    ### only for shell if you defined only one server
  if ( $param_server eq "AGENT_UUIDS" ) {
    my $result = uuids();
    exit $result;
  }
  if ( $param_server eq "VMWARE" ) {
    my $result = print_vm_all();
    exit $result;
  }
  if ( $param_server eq "HYPERV" ) {
    my $result = print_hyperv_all();
    exit $result;
  }
  if ( $param_server eq "HITACHI" ) {
    my $result = print_hitachi_all();
    exit $result;
  }
  if ( $param_server eq "SOLARIS-L" ) {
    my $result = print_solaris_all();
    exit $result;
  }
  else {
    @wrkdir_all = ();
    $wrkdir_all[0] = "$wrkdir/$param_server";
    my $result = print_all_server();
    exit $result;
  }
}
else {
  my $result = print_all_server();
  exit $result;
}

sub print_power_interfaces {
  my @int_types = ( "LAN", "SAN", "SAS", "HEA", "SRI" );
  my $translate = {};
  $translate->{LAN}{letter} = "N";
  $translate->{SAN}{letter} = "Y";
  $translate->{SAS}{letter} = "s";
  $translate->{HEA}{letter} = "HEA";
  $translate->{SRI}{letter} = "r";
  $translate->{LAN}{item}   = "lan-totals";
  $translate->{SAN}{item}   = "san-totals";
  $translate->{SAS}{item}   = "sas-totals";
  $translate->{HEA}{item}   = "hea-totals";
  $translate->{SRI}{item}   = "sriov-totals";
  my $int_totals = {};

  foreach my $int_type (@int_types) {

    #    warn "INT TYPE : $int_type\n"; warn Dumper PowerDataWrapper::get_items($int_type);
    my $items_ref = PowerDataWrapper::get_items($int_type);
    my @items     = @{$items_ref} if defined $items_ref;
    foreach my $item (@items) {
      my $uid = ( keys %{$item} )[0];
      my $url = PowerMenu::get_url( { type => $int_type, id => $uid } );
      if ( !defined $url || $url eq "" ) { warn "type => $int_type, id => $uid"; warn Dumper $url; next; }
      my $interface_string = PowerDataWrapper::get_label( $int_type, $uid );
      my $server_uid       = PowerDataWrapper::get_int_parent( $uid, $int_type );
      my $server           = PowerDataWrapper::get_label( "SERVER", $server_uid );

      my $tmp_server = $server;
      $server = urlencode($server);
      $tmp_server =~ s/\:/===double-col===/g;

      my $hmc_uid = PowerDataWrapper::get_server_parent($server_uid);
      my $hmc     = PowerDataWrapper::get_label( "HMC", $hmc_uid );

      #$hmc = $hmc->{label} if defined $hmc->{label};
      print "$translate->{$int_type}{letter}:$hmc:$tmp_server:$interface_string:$interface_string:$url\:::P:\n";
      my $lc_type    = lc($int_type);
      my $url_totals = PowerMenu::get_url( { type => "$lc_type-aggr", id => $server_uid } );
      if ( $lc_type eq 'sri' ) { $lc_type = 'sriov'; }
      print "$translate->{$int_type}{letter}:$hmc:$tmp_server:$server:$translate->{$int_type}{item}:$url_totals\:::P:\n" if ( !$int_totals->{$server}{$int_type} );
      $int_totals->{$server}{$int_type} = 1;
    }
  }
}

sub print_power_vms {
  my $vms_ref = PowerDataWrapper::get_items('VM');
  my @vms     = ();
  my $s       = ':';
  @vms = @{$vms_ref} if defined $vms_ref;
  foreach my $vm (@vms) {
    my $vm_uid  = ( keys %{$vm} )[0];
    my $vm_name = PowerDataWrapper::get_label( 'VM', $vm_uid );

    #    $vm_name =~ s/\//\&\&1/g;
    my $vm_name_alias            = ' [alias]';
    my $server_uid               = PowerDataWrapper::get_vm_parent($vm_uid);
    my $server_name              = PowerDataWrapper::get_label( 'SERVER', $server_uid );
    my $server_name_escape_colon = escape_colon($server_name);
    my $server_name_url          = name_to_url_name($server_name);
    my $vm_name_url              = name_to_url_name($vm_name);
    my $vm_name_escape_colon     = name_to_url_name($vm_name);
    my $hmc_uid                  = PowerDataWrapper::get_server_parent($server_uid);
    my $hmc_name                 = PowerDataWrapper::get_label( 'HMC', $hmc_uid );

    #    $hmc_name = $hmc_name->{label} if (ref($hmc_name) eq "HASH" && defined $hmc_name->{label});
    my $status = PowerDataWrapper::get_status( 'VM', $vm_uid );

    #    print "L:$hmc_name:$server_name_url:$vm_name:$vm_name_url:/lpar2rrd-cgi/detail.sh?host=$hmc_name&server=$server_name_url&lpar=$vm_name_url&item=lpar:::P:C\n"
    $vm_name =~ s/\:/===double-col===/g;
    my $url = PowerMenu::get_url( { type => 'VM', id => $vm_uid } );
    print "$status" . "$s" . "$hmc_name" . "$s" . "$server_name_escape_colon" . "$s" . "$vm_name_url" . "$s" . "$vm_name" . "$s" . "/lpar2rrd-cgi/detail.sh?host=$hmc_name&server=$server_name_url&lpar=$vm_name_url&item=lpar&entitle=0&gui=1&none=none:::P:C\n";    # active/removed lpars from hmc
  }
}

sub print_power_pools {
  my $pools_ref = PowerDataWrapper::get_items('POOL');
  foreach my $pool ( @{$pools_ref} ) {
    my $pool_uid                 = ( keys %{$pool} )[0];
    my $pool_label               = PowerDataWrapper::get_label( 'POOL', $pool_uid );
    my $server_uid               = PowerDataWrapper::get_pool_parent($pool_uid);
    my $server_name              = PowerDataWrapper::get_label( 'SERVER', $server_uid );
    my $server_name_escape_colon = escape_colon($server_name);
    my $server_name_url          = name_to_url_name($server_name);
    my $pool_label_url           = name_to_url_name($pool_label);
    my $pool_label_escape_colon  = name_to_url_name($pool_label);
    my $pool_name                = PowerDataWrapper::get_pool_name($pool_uid);
    my $hmc_uid                  = PowerDataWrapper::get_server_parent($server_uid);
    my $hmc_name                 = PowerDataWrapper::get_label( 'HMC', $hmc_uid );

    #    $hmc_name = $hmc_name->{label} if (defined $hmc_name->{label});
    my $status = PowerDataWrapper::get_status( 'POOL', $pool_uid );
    $pool_label =~ s/\:/===double-col===/g;
    my $url = PowerMenu::get_url( { type => 'SHPOOL', id => $pool_uid } );
    print "S:$hmc_name:$server_name_escape_colon:CPUpool-$pool_label:$pool_name:$url\:::P\n";
  }
}

sub name_to_url_name {
  my $in = shift;
  $in =~ s/\:/===double-col===/g;
  $in = urlencode($in);
  $in =~ s/%3A/===double-col===/g;
  $in =~ s/%3D%3D%3D/===/g;

  #  $in =~ s/%20/ /g;
  return $in;
}

sub escape_colon {
  my $in = shift;
  $in =~ s/\:/===double-col===/g;
  return $in;
}

################### PRINT ALL SERVERS
sub print_all_server {

  #add lan,san,sas,hea,sr-iov to menu.txt
  #print_power_interfaces(); #add adapters to menu.txt
  #print_power_vms();        # add lpars to menu.txt
  #print_power_pools();      # add shared pools to menu.txt

  # this would be case if it is necessary only active HMCs, but because of historical reports, all hmcs are needed
  #my $hmcs = `\$PERL $basedir/bin/hmc_list.pl`;
  #my @hmcs = split( " ", $hmcs );

  my $interface_for_servers;
  foreach my $server_all (@wrkdir_all) {

    #print STDERR "SERVER ALL Wrkdir\n";
    #print STDERR Dumper @wrkdir_all;

    #print "#$server_all ".time()."\n";

    $server_all = "$wrkdir/$server_all";
    my $server = basename($server_all);
    if ( $server =~ /[vV][mM][wW][aA][rR][eE]/ )                    { next; }
    if ( -l $server_all )                                           { next; }
    if ( -f "$server_all" )                                         { next; }
    if ( $server_all =~ /--HMC--|Solaris|Hitachi$|OracleVM|oVirt/ ) { next; }
    chomp $server_all;
    chomp $server;
    opendir( DIR, "$wrkdir/$server" ) || error( "can't opendir $wrkdir/$server: $! :" . __FILE__ . ":" . __LINE__ ) && next;
    my @hmcdir_all = grep !/^\.\.?$/, readdir(DIR);
    closedir(DIR);
    my $last_update_time = 0;

    #print "line 311-@hmcdir_all\n";
    my $newest_hmc  = -1;
    my $current_hmc = "";
    foreach my $hmc_rrx_files (@hmcdir_all) {
      my $curr_hmc_file_time_diff = Xorux_lib::file_time_diff("$wrkdir/$hmc_rrx_files.rrx");
      if ( -e "$wrkdir/$hmc_rrx_files.rrx" ) {
        if ( $curr_hmc_file_time_diff < $newest_hmc || $newest_hmc == -1 ) {
          $newest_hmc  = $curr_hmc_file_time_diff;
          $current_hmc = $hmc_rrx_files;
        }
      }
    }

    #    next if $current_hmc eq ""; # this is for some old or other or tresh dirs # do not know if it is OK

    #@hmcdir_all = @hmcs;
    foreach my $hmc_all_base (@hmcdir_all) {

      #print STDERR "HMC ALL\n";
      #print STDERR Dumper @hmcdir_all;
      my $hmc_all = "$wrkdir/$server/$hmc_all_base";
      my $hmc     = basename($hmc_all);
      if ( $hmc_all =~ /\.rrx/ )    { next; }
      if ( $hmc     =~ /--NMON--/ ) { next; }
      if ( $hmc     =~ /no_hmc/ ) {    ####################### SERVER - NO_HMC !!!
        opendir( DIR, "$wrkdir/$server/$hmc" ) || error( "can't opendir $wrkdir/$server/$hmc: $! :" . __FILE__ . ":" . __LINE__ ) && next;
        my @lpars_dir_nohmc_all = grep !/^\.\.?$/, readdir(DIR);
        closedir(DIR);

        # there can be lpar2rrd server which used vmware before but not now
        # some vmware uuid files remained & that is why some Linux machines are not in menu.txt
        # so test the file tmpdir/menu_vms_pl.txt if exists and is not empty
        my $test_linux_in_vmware = 0;

        # `touch -d "42 hours ago" "$tmpdir/menu_vms_pl.txt"`; # want to see all linuxes ?
        if ( -f "$tmpdir/menu_vms_pl.txt" && -s "$tmpdir/menu_vms_pl.txt" && ( ( -M "$tmpdir/menu_vms_pl.txt" ) < 1 ) ) {
          $test_linux_in_vmware = 1;
        }

        foreach my $lpars_dir_base (@lpars_dir_nohmc_all) {    #################### OS AGENT
          my $lpars_dir  = "$wrkdir/$server/$hmc/$lpars_dir_base";
          my $server_unk = $server;
          my $agent_type = find_agent_type( $wrkdir, $server, $hmc, $lpars_dir_base, "" );
          if ( $lpars_dir =~ /--AS400--$/ ) {                  ################# AS400 ----- NO_HMC
            if ( -f "$lpars_dir/S0200ASPJOB.mmm" ) {
              my $lpar_as = basename($lpars_dir);
              $lpar_as =~ s/--AS400--$//;
              my ($result_lpar_cfg) = grep /:$lpar_as:/, @alias_servers;
              my $lpar_b            = "";
              my $alias_os          = "";
              my $alias             = "";
              if ( defined $result_lpar_cfg && $result_lpar_cfg ne "" ) {
                ( undef, $lpar_b, $alias ) = split( /:/, $result_lpar_cfg );
                chomp $alias;
                $alias_os = " [$alias]";
              }
              if ( $server =~ /--unknown$/ ) {
                $server =~ s/--unknown$//;
                print "$actived" . "$hmc" . "$s" . "$server" . "$s" . "$lpar_as" . "$alias_os" . "$s" . "$lpar_as" . "$s" . "/lpar2rrd-cgi/detail.sh?host=$hmc&server=$server&lpar=$lpar_as&item=lpar&entitle=0&gui=1&none=none:::P:$agent_type\n";
                $server  = "$server--unknown";
                $lpar_as = "$lpar_as--AS400--";
              }
              else {
                print "$actived" . "$hmc" . "$s" . "$server" . "$s" . "$lpar_as" . "$s" . "$lpar_as" . "$alias_os" . "$s" . "/lpar2rrd-cgi/detail.sh?host=$hmc&server=$server&lpar=$lpar_as&item=lpar&entitle=0&gui=1&none=none:::P:$agent_type\n";
                $lpar_as = "$lpar_as--AS400--";
              }
            }
          }
          else {
            if ( -f "$lpars_dir/cpu.mmm" ) {

              #if ($server =~ /--unknown/){next;}
              my $file_cpu       = "$lpars_dir/cpu.mmm";
              my $last_timestamp = ( stat($file_cpu) )[9];
              if ( $last_timestamp > $actual_last_ten_days ) {
                $lpars_dir =~ s/--NMON--$//g;
                my $lpar = basename($lpars_dir);
                if ( !defined $hash_lpar{$lpars_dir} ) {
                  $hash_lpar{$lpars_dir} = "test";
                }
                else {
                  next;
                }

                #server_unk =~ s/--unknown$//;
                my $lpar_name = $lpar;
                $lpar =~ s/&&1/\//g;
                my $server_enc        = urlencode($server_unk);
                my $hmc_enc           = urlencode($hmc);
                my $lpar_name_enc     = urlencode($lpar);
                my ($result_lpar_cfg) = grep /:$lpar:/, @alias_servers;
                my $lpar_b            = "";
                my $alias_os          = "";
                my $alias             = "";
                my $uuid_txt          = "$wrkdir/$server/$hmc/$lpar/uuid.txt";
                my $uuid_old          = "";

                if ( -f $uuid_txt && open( FCD, "< $uuid_txt" ) ) {

                  # if ($server =~ /Solaris/){next;} # it is tested above
                  $uuid_old = <FCD>;
                  close(FCD);

                  # e.g. D2051C42-C469-27DA-3FF6-6E508678C004
                  if ( !defined $uuid_old ) {
                    error( "Bad data in file $wrkdir/$server/$hmc/$lpar/uuid.txt: " . __FILE__ . ":" . __LINE__ );
                  }
                  else {
                    my @uuid_atoms = split( "-", $uuid_old );
                    if ( defined $uuid_atoms[3] && defined $uuid_atoms[4] ) {
                      my $pattern = "-$uuid_atoms[3]-$uuid_atoms[4]";
                      $pattern = lc $pattern;
                      chomp $pattern;

                      # print STDERR "235 $pattern\n";
                      my @matches = grep {/$pattern/} @vm_list;
                      next if ( defined $matches[0] );

                      # print STDERR "237 not found match\n";
                    }
                    chomp $uuid_old;
                    if ( defined $hitachi_lpar_uuids{$uuid_old} || defined $ovirt_uuids{ lc $uuid_old } || defined $nutanix_uuids{ lc $uuid_old } || defined $fusioncompute_uuids{ lc $uuid_old } ) {
                      next;
                    }
                  }
                }
                if ( defined $result_lpar_cfg && $result_lpar_cfg ne "" ) {
                  ( undef, $lpar_b, $alias ) = split( /:/, $result_lpar_cfg );
                  chomp $alias;
                  $alias_os = " [$alias]";
                }
                my @ldom_names      = "";
                my $uuid_minus_dash = $uuid_old;                                       ### uuid without (-)
                $uuid_minus_dash =~ s/-//g;
                $uuid_minus_dash = lc $uuid_minus_dash;
                if ( exists $dictionary_orvm{labels}{vm}{$uuid_minus_dash} ) {next}    ### If Linux server running bellow OracleVM
                if ( $server_unk =~ /--unknown/ ) {                                    ###### SERVER(LINUX) ---unknown
                  $server_unk =~ s/--unknown//;
                  print "$actived" . "$hmc" . "$s" . "$server_unk" . "$s" . "$lpar_name_enc" . "$s" . "$lpar" . "$alias_os" . "$s" . "/lpar2rrd-cgi/detail.sh?host=$hmc_enc&server=$server_enc&lpar=$lpar_name_enc&item=lpar&entitle=0&gui=1&none=none:::P:$agent_type\n";

                  # print "425 this is Linux machine $lpar_name_enc $alias_os\n";
                }
                else {
                  if ( $hmc =~ /no_hmc/ ) { next; }
                  print "$actived" . "$hmc" . "$s" . "$server_unk" . "$s" . "$lpar_name_enc" . "$s" . "$lpar" . "$alias_os" . "$s" . "/lpar2rrd-cgi/detail.sh?host=$hmc_enc&server=$server_enc&lpar=$lpar_name_enc&item=lpar&entitle=0&gui=1&none=none:::P:$agent_type\n";
                }
              }
            }
          }
        }
      }
      my $server_un = $server;
      if ( $server =~ /--unknown$/ ) {    ######## OS AGENT -- SERVER--unknown
        if ( $hmc =~ /no_hmc/ ) { next; }
        opendir( DIR, "$wrkdir/$server/$hmc" ) || error( "can't opendir $wrkdir/$server/$hmc: $! :" . __FILE__ . ":" . __LINE__ ) && next;
        my @lpars_dir_all = grep !/^\.\.?$/, readdir(DIR);
        closedir(DIR);
        foreach my $lpars_dir_base (@lpars_dir_all) {
          my $lpars_dir = "$wrkdir/$server_un/$hmc/$lpars_dir_base";
          if ( -f "$lpars_dir/cpu.mmm" ) {    ##### OS AGENT DATA
            my $file_cpu       = "$lpars_dir/cpu.mmm";
            my $last_timestamp = ( stat($file_cpu) )[9];
            if ( $last_timestamp > $actual_last_ten_days ) {
              my $lpar = basename($lpars_dir);
              if ( $lpar =~ /--NMON--/ ) { next; }
              if ( $server =~ /--unknown$/ ) { $server =~ s/--unknown$//; }
              my $lpar_name         = $lpar;
              my $agent_type        = find_agent_type( $wrkdir, $server, $hmc, $lpar, "" );
              my $server_enc        = urlencode($server);
              my $hmc_enc           = urlencode($hmc);
              my $lpar_name_enc     = urlencode($lpar_name);
              my ($result_lpar_cfg) = grep /:$lpar:/, @alias_servers;
              my $lpar_b            = "";
              my $alias_os          = "";
              my $alias             = "";

              if ( defined $result_lpar_cfg && $result_lpar_cfg ne "" ) {
                ( undef, $lpar_b, $alias ) = split( /:/, $result_lpar_cfg );
                chomp $alias;
                $alias_os = " [$alias]";
              }
              print "$actived" . "$hmc" . "$s" . "$server" . "$s" . "$lpar_name_enc" . "$s" . "$lpar" . "$alias_os" . "$s" . "/lpar2rrd-cgi/detail.sh?host=$hmc_enc&server=$server_enc" . "--unknown" . "&lpar=$lpar_name_enc&item=lpar&entitle=0&gui=1&none=none:::P:$agent_type\n";
            }
          }
        }
      }

      #if (!-d $hmc) {next;}

      $server =~ s/===double-col===/\:/g;
      my $hmc_dir_test = "$wrkdir/$server/$hmc";
      if ( !-d $hmc_dir_test ) { next; }
      my $LAN_interface_file = "$wrkdir/$server/$hmc/LAN_aliases.json";
      my $SAN_interface_file = "$wrkdir/$server/$hmc/SAN_aliases.json";
      my $SAS_interface_file = "$wrkdir/$server/$hmc/SAS_aliases.json";
      my $LAN_interface_aliases;
      my $SAN_interface_aliases;
      my $SAS_interface_aliases;

      if ( -e $LAN_interface_file ) {
        $LAN_interface_aliases = Xorux_lib::read_json($LAN_interface_file);
      }
      if ( -e $SAN_interface_file ) {
        $SAN_interface_aliases = Xorux_lib::read_json($SAN_interface_file);
      }
      if ( -e $SAS_interface_file ) {
        $SAS_interface_aliases = Xorux_lib::read_json($SAS_interface_file);
      }
      opendir( DIR, "$wrkdir/$server/$hmc" ) || error( "can't opendir $wrkdir/$server/$hmc: $! :" . __FILE__ . ":" . __LINE__ ) && next;    #tady if adapters
      my @lpars_dir_all = grep !/^\.\.?$/, readdir(DIR);
      closedir(DIR);
      my $cpu_cfg = "$hmc_all/cpu.cfg";
      my @lines_config;

      if ( -e $cpu_cfg ) {
        open( FH, "< $cpu_cfg" ) || error( "Cannot read $cpu_cfg: $!" . __FILE__ . ":" . __LINE__ ) && next;
        @lines_config = <FH>;
        close(FH);
      }
      ##########
      ## print LPAR/ADAPTERS part
      ##########
      #print "line-488-$server/$hmc,@lpars_dir_all\n";
      foreach my $lpars_dir_base (@lpars_dir_all) {
        if ( $lpars_dir_base eq "adapters" ) {
          my $adapter_dir = "$wrkdir/$server/$hmc/$lpars_dir_base";
          opendir( DIR, "$adapter_dir" ) || error( "can't opendir $adapter_dir: $! :" . __FILE__ . ":" . __LINE__ ) && next;
          my @adapters = grep !/^\.\.?$/, readdir(DIR);
          closedir(DIR);
          if ( !(@adapters) ) {    # if there is not any file in adapters folder
            next;
          }
          else {
            my $lan        = 0;
            my $hea        = 0;
            my $san        = 0;
            my $sas        = 0;
            my $sri        = 0;
            my $tmp_server = $server;
            $server = urlencode($server);
            $tmp_server =~ s/\:/===double-col===/g;
            my @current_sriov_adapters;
            my $to_aggregate;

            foreach my $adapter (@adapters) {

              #if ($adapter =~ m/-V[0-9]*-C[0-9]*/){next;} #hash this if you want Virtual Adapters with XXXXX-V*-C*-T* in name
              if ( $adapter =~ m/rasm/ ) {
                my $act_alias;
                my $act_lpar;

                #print "SAN: $adapter\n";
                ( my $adapter_name, undef ) = split( ".r", $adapter );
                my $interface_string;
                my $interface_string_url;
                foreach my $alias ( keys %{$SAN_interface_aliases} ) {
                  if ( $alias =~ /$adapter_name/ ) {
                    $act_alias            = "$SAN_interface_aliases->{$alias}{alias}";
                    $act_lpar             = "$SAN_interface_aliases->{$alias}{partition}";
                    $interface_string     = "$act_lpar $act_alias";
                    $interface_string_url = "$act_lpar%20$act_alias";
                  }
                }
                if ( !defined $interface_string || $interface_string eq "" ) {
                  $interface_string_url = $interface_string = $adapter_name;
                }
                if ( $interface_string !~ $adapter_name ) {
                  $interface_string = "$interface_string $adapter_name";
                }
                if ( length($adapter_name) <= 7 || !defined $interface_string || $interface_string eq "" ) { next; }
                print "Y:$hmc:$tmp_server:$interface_string_url:$interface_string:/lpar2rrd-cgi/detail.sh?host=$hmc&server=$server&lpar=$adapter&item=power_san&entitle=0&gui=1&none=none:::P:\n";
                $san = 1;
              }
              elsif ( $adapter =~ m/rapm/ ) {
                my $act_alias;
                my $act_lpar;
                ( my $adapter_name, undef ) = split( ".r", $adapter );
                my $interface_string;
                my $interface_string_url;
                foreach my $alias ( keys %{$SAS_interface_aliases} ) {
                  if ( $alias =~ /$adapter_name/ ) {
                    $act_alias            = "$SAS_interface_aliases->{$alias}{alias}";
                    $act_lpar             = "$SAS_interface_aliases->{$alias}{partition}";
                    $interface_string     = "$act_lpar $act_alias";
                    $interface_string_url = "$act_lpar%20$act_alias";
                  }
                }
                if ( !defined $interface_string || $interface_string eq "" ) {
                  $interface_string_url = $interface_string = $adapter_name;
                }
                if ( $interface_string !~ $adapter_name ) {
                  $interface_string = "$interface_string $adapter_name";
                }
                if ( length($adapter_name) <= 7 || !defined $interface_string || $interface_string eq "" ) { next; }
                ### THIS LOOKS THAT IS THE SAME AS ralm ADAPTERS, SO IT'S LAN NOT SAN
                print "s:$hmc:$tmp_server:$interface_string_url:$interface_string:/lpar2rrd-cgi/detail.sh?host=$hmc&server=$server&lpar=$adapter&item=power_sas&entitle=0&gui=1&none=none:::P:\n";
                $sas = 1;
              }
              elsif ( $adapter =~ m/ralm/ ) {
                my $act_alias;
                my $act_lpar;

                #print "LAN: $adapter\n";
                ( my $adapter_name, undef ) = split( ".r", $adapter );
                my $interface_string;
                my $interface_string_url;
                foreach my $alias ( keys %{$LAN_interface_aliases} ) {
                  if ( $alias =~ /$adapter_name/ ) {
                    $act_alias            = "$LAN_interface_aliases->{$alias}{alias}";
                    $act_lpar             = "$LAN_interface_aliases->{$alias}{partition}";
                    $interface_string     = "$act_lpar $act_alias";
                    $interface_string_url = "$act_lpar%20$act_alias";
                  }
                }
                if ( !defined $interface_string || $interface_string eq "" ) {
                  $interface_string_url = $interface_string = $adapter_name;
                }
                if ( $interface_string !~ $adapter_name ) {
                  $interface_string = "$interface_string $adapter_name";
                }
                if ( length($adapter_name) <= 7 || !defined $interface_string || $interface_string eq "" ) { next; }
                print "N:$hmc:$tmp_server:$interface_string_url:$interface_string:/lpar2rrd-cgi/detail.sh?host=$hmc&server=$server&lpar=$adapter&item=power_lan&entitle=0&gui=1&none=none:::P:\n";
                $lan = 1;
              }
              elsif ( $adapter =~ m/rasr/ ) {
                ( my $gui_agg_name, undef ) = split( "-S", $adapter );
                if ( length($adapter) <= 7 || length($gui_agg_name) <= 7 ) { next; }

                # this doesn't work on aix, so linear search nelow is used for now
                #if (!($gui_agg_name ~~ @current_sriov_adapters)){
                #  print "r:$hmc:$tmp_server:$adapter_name:$gui_agg_name:/lpar2rrd-cgi/detail.sh?host=$hmc&server=$server&lpar=$adapter&item=power_sri&entitle=0&gui=1&none=none:::P:\n";
                #  push (@current_sriov_adapters, $gui_agg_name);
                #  $sri = 1;
                #}

                my $is_there = 0;
                foreach my $csa (@current_sriov_adapters) {
                  if ( $gui_agg_name eq $csa ) {
                    $is_there = 1;
                  }
                }
                if ( !($is_there) ) {
                  print "r:$hmc:$tmp_server:$gui_agg_name:$gui_agg_name:/lpar2rrd-cgi/detail.sh?host=$hmc&server=$server&lpar=$gui_agg_name&item=power_sri&entitle=0&gui=1&none=none:::P:\n";
                  push( @current_sriov_adapters, $gui_agg_name );
                  $sri = 1;
                }
                push( @{ $to_aggregate->{$gui_agg_name} }, $adapter );
              }
              elsif ( $adapter =~ m/rahm/ ) {
                ( my $adapter_name, undef ) = split( ".r", $adapter );
                if ( length($adapter_name) <= 7 ) { next; }
                print "HEA:$hmc:$tmp_server:$adapter_name:$adapter_name:/lpar2rrd-cgi/detail.sh?host=$hmc&server=$server&lpar=$adapter&item=power_hea&entitle=0&gui=1&none=none:::P:\n";
                $hea = 1;
              }
            }
            my $server_dec = urldecode($server);
            $interface_for_servers->{$server_dec}{lan} = $lan;
            $interface_for_servers->{$server_dec}{san} = $san;
            $interface_for_servers->{$server_dec}{sas} = $sas;
            $interface_for_servers->{$server_dec}{sri} = $sri;
            $interface_for_servers->{$server_dec}{hea} = $hea;

            Xorux_lib::write_json( "$wrkdir/$server/$hmc/sriov_log_port_list.json", $to_aggregate ) if ( defined $to_aggregate );
            my $server_enc = urlencode($server);
            $server_enc =~ s/%3D%3D%3D/===/g;

            #$server =~ s/%3A/===double-col===/g;
            if ( $hea == 1 ) {
              print "HEA:$hmc:$tmp_server:$server:hea-totals:/lpar2rrd-cgi/detail.sh?host=$hmc&server=$server_enc&lpar=hea-totals&item=power_hea&entitle=0&gui=1&none=none:::P:\n";
            }
            if ( $lan == 1 ) {
              print "N:$hmc:$tmp_server:$server:lan-totals:/lpar2rrd-cgi/detail.sh?host=$hmc&server=$server_enc&lpar=lan-totals&item=power_lan&entitle=0&gui=1&none=none:::P:\n";
            }
            if ( $san == 1 ) {
              print "Y:$hmc:$tmp_server:$server:san-totals:/lpar2rrd-cgi/detail.sh?host=$hmc&server=$server_enc&lpar=san-totals&item=power_san&entitle=0&gui=1&none=none:::P:\n";
            }
            if ( $sas == 1 ) {
              print "s:$hmc:$tmp_server:$server:sas-totals:/lpar2rrd-cgi/detail.sh?host=$hmc&server=$server_enc&lpar=sas-totals&item=power_sas&entitle=0&gui=1&none=none:::P:\n";
            }
            if ( $sri == 1 ) {
              print "r:$hmc:$tmp_server:$server:sriov-totals:/lpar2rrd-cgi/detail.sh?host=$hmc&server=$server_enc&lpar=sri-totals&item=power_sri&entitle=0&gui=1&none=none:::P:\n";
            }
            $server = $tmp_server;
          }
        }
        my $lpars_dir = "$wrkdir/$server/$hmc/$lpars_dir_base";
        my $lpar      = basename($lpars_dir);
        if ( $hmc ne $current_hmc ) {

          #print STDERR "HMC: $hmc ------ && $hmc eq $current_hmc\n";
          #next;
        }
        if ( !-f "$hmc_dir_test/cpu.cfg" ) {    ##### OS AGENT but no cpu.cfg in HMC
          if ( -f $lpars_dir )           { next; }
          if ( $server =~ /--unknown$/ ) { next; }
          if ( -f "$lpars_dir/cpu.mmm" ) {      ###### if exists cpu.mmm in <lpar> dir
            my $file_cpu       = "$lpars_dir/cpu.mmm";
            my $last_timestamp = ( stat($file_cpu) )[9];
            if ( $last_timestamp > $actual_last_ten_days ) {
              $lpars_dir =~ s/--NMON--//;
              if ( !defined $hash_lpar{$lpars_dir} ) {
                $hash_lpar{$lpars_dir} = "test";
              }
              else {
                next;
              }
              $lpar =~ s/--NMON--//;
              $lpar =~ s/&&1/\//g;
              my $lpar_name  = $lpar;
              my $agent_type = find_agent_type( $wrkdir, $server, $hmc, $lpar, "" );
              my $server_enc = urlencode($server);
              if ( $server =~ /--unknown/ ) { next; }
              my $hmc_enc           = urlencode($hmc);
              my $lpar_name_enc     = urlencode($lpar_name);
              my ($result_lpar_cfg) = grep /:$lpar:/, @alias_servers;
              my $lpar_b            = "";
              my $alias_os          = "";
              my $alias             = "";

              if ( defined $result_lpar_cfg && $result_lpar_cfg ne "" ) {
                ( undef, $lpar_b, $alias ) = split( /:/, $result_lpar_cfg );
                chomp $alias;
                $alias_os = " [$alias]";
              }
              print "$actived" . "$hmc" . "$s" . "$server" . "$s" . "$lpar_name_enc" . "$s" . "$lpar" . "$alias_os" . "$s" . "/lpar2rrd-cgi/detail.sh?host=$hmc_enc&server=$server_enc&lpar=$lpar_name_enc&item=lpar&entitle=0&gui=1&none=none:::P:$agent_type\n";
            }
            else {
              # print "R:\n"; # why this is printed ?
            }
          }
        }
        if ( -f "$hmc_all/vmware.txt" ) { next; }
        my $lpar_dir   = $lpar;
        my $lpar_short = $lpar;
        $lpar_short =~ s/\.r..$//;

        #print "line682-$wrkdir/$server/$hmc/$lpar\n";
        if ( ( $lpar =~ /\.rrm$/ ) || ( $lpar =~ /\.rsh$/ && !-f "$wrkdir/$server/$hmc/$lpar_short.rrm" ) ) {
          $server =~ s/===double-col===/:/g;
          my $server_name   = $server;
          my $rrm_file_test = "$wrkdir/$server_name/$hmc/$lpar";

          #print "line688-$rrm_file_test\n";
          $rrm_file_test =~ s///g;
          $lpar          =~ s/.rsh$//g;
          $lpar          =~ s/.rrm$//g;
          $lpar          =~ s/:/\\:/g;
          my $lpar_name = $lpar;
          if ( $lpar_name =~ /SharedPool\d/ ) { next; }
          $lpar =~ s/&&1/\//g;
          my $cpu_cfg          = "$hmc_dir_test/cpu.cfg";
          my $timestamp_cpucfg = ( stat("$cpu_cfg") )[9];
          my $health_status    = "";

          #next if (!defined $timestamp_cpucfg || $timestamp_cpucfg < $actual_last_30_days);
          my $result_cpu_cfg = grep /^lpar_name=$lpar,lpar_id/, @lines_config;
          if ( $result_cpu_cfg == 0 ) {
            $health_status = "R:";
          }
          else {
            $health_status = "L:";
            if ( -f "$wrkdir/$server/$hmc/pool.rrm" ) {
              my $ftd = Xorux_lib::file_time_diff("$wrkdir/$server/$hmc/pool.rrm");
              if ( !defined $timestamp_cpucfg || $timestamp_cpucfg < $actual_last_30_days_power || ( $ftd && $ftd > 86400 ) ) {    #### OLD LPARs but still in old-hmc cpu.cfg
                $health_status = "RR:";
              }
            }
            else {
              if ( -f "$wrkdir/$server/$hmc/pool_total.rrt" ) {
                my $ftd = Xorux_lib::file_time_diff("$wrkdir/$server/$hmc/pool_total.rrt");
                if ( !defined $timestamp_cpucfg || $timestamp_cpucfg < $actual_last_30_days_power || ( $ftd && $ftd > 86400 ) ) {    #### OLD LPARs but still in old-hmc cpu.cfg
                  $health_status = "RR:";
                }
              }
            }
          }
          my $server_enc    = urlencode($server);
          my $hmc_enc       = urlencode($hmc);
          my $lpar_name_enc = urlencode($lpar);
          my $b_lpar        = $lpar;
          my ($lpar_alias)  = grep /^LPAR:\Q$lpar\E/, @alias_servers;
          my $lpar_a        = "";
          my $alias         = "";
          my $alias_lpar    = "";
          if ( $rrm_file_test !~ m/rrm/ ) { $rrm_file_test = "$rrm_file_test.rrm"; }
          my $rrm_stat = ( stat("$rrm_file_test") )[9];

          if ( !defined $rrm_stat || $rrm_stat < $actual_last_30_days_power ) {
            if ( $health_status =~ m/R:/ ) {
              $health_status = "RR:";
            }
          }
          if ( defined $lpar_alias && $lpar_alias ne "" ) {
            chomp $lpar_alias;
            $lpar_alias =~ s/\\:/===backslash-col===/g;

            #print "$lpar_alias\n";
            ( undef, $lpar_a, $alias ) = split( /:/, $lpar_alias, 3 );
            $lpar_a =~ s/===backslash-col===/\\:/g;
            $alias  =~ s/===backslash-col===/\\:/g;

            #print "\n,,$lpar_a,,$alias,,\n";
            chomp $alias;
            $alias =~ s/\:/===double-col===/g;
            $alias_lpar = " [$alias]";
          }
          $lpar_a =~ s/replace/\\:/g;
          chomp $alias;
          $lpar =~ s/\\:/:/g;
          my $agent_type = find_agent_type( $wrkdir, $server, $hmc, $lpar, "" );
          $lpar_name =~ s/\\:/:/g;
          if ( $hmc    =~ /no_hmc/ )    { next; }
          if ( $server =~ /--unknown/ ) { next; }
          $lpar =~ s/\:/===double-col===/g;
          $lpar_name_enc = urlencode($lpar);
          $lpar_name_enc =~ s/%3A/===double-col===/g;
          $lpar_name_enc =~ s/%3D%3D%3D/===/g;
          if ( $lpar eq "mem-pool" ) { next; }
          if ( $lpar eq "mem" )      { next; }
          if ( $lpar eq "pool" )     { next; }

          #if ($rrm_stat > $year_back ){ --PH removed at 6.11-1 to have all active lpars in the menu
          $hash_timestamp1{$server}{$lpar}{$health_status}{$hmc} = $rrm_stat;

          #print "$health_status" . "$hmc" . "$s" . "$server" . "$s" . "$lpar_name_enc" . "$s" . "$lpar" . "$alias_lpar" . "$s" . "/lpar2rrd-cgi/detail.sh?host=$hmc_enc&server=$server_enc&lpar=$lpar_name_enc&item=lpar&entitle=0&gui=1&none=none:::P:$agent_type\n";
          #}
        }
        $lpar_dir =~ s/\.rrd$|\.rrm$|\.rsd$|\.rsm$//;
        if ( !-d "$wrkdir/$server/$hmc/$lpar_dir" ) { next; }
        opendir( DIR, "$wrkdir/$server/$hmc/$lpar_dir" ) || error( "can't opendir $wrkdir/$server/$hmc/$lpar_dir: $! :" . __FILE__ . ":" . __LINE__ ) && next;
        my @lpars_dir_wpar = grep !/^\.\.?$/, readdir(DIR);
        closedir(DIR);

        #my @lpars_dir_wpar = <$wrkdir/$server_space/$hmc/$lpar/*>;
        foreach my $lpars_wpar_base (@lpars_dir_wpar) {
          my $lpars_wpar = "$wrkdir/$server/$hmc/$lpar_dir/$lpars_wpar_base";
          my $wpar       = basename($lpars_wpar);

          #print "$lpars_wpar\n";
          if ( !defined $hash_wpar{$lpars_wpar} ) {
            $hash_wpar{$lpars_wpar} = "test";
          }
          else {
            next;
          }
          if ( -f "$lpars_wpar/cpu.mmm" ) {
            chomp $lpars_wpar;

            #print "$lpars_wpar\n";
            my $agent_type      = find_agent_type( $wrkdir, $server, $hmc, $lpar, $lpars_wpar );
            my $rrm_stat_w      = ( stat("$lpars_wpar/cpu.mmm") )[9];
            my $wpar            = ( split( /\//, $lpars_wpar ) )[-1];
            my $lpar_a          = ( split( /\//, $lpars_wpar ) )[-2];
            my $hmc_wpar        = ( split( /\//, $lpars_wpar ) )[-3];
            my $server_wpar     = ( split( /\//, $lpars_wpar ) )[-4];
            my $server_wpar_enc = urlencode($server_wpar);
            my $hmc_wpar_enc    = urlencode($hmc_wpar);
            my $wpar_name_enc   = urlencode($wpar);
            my $result_wpar_cfg = grep /:$wpar:/, @alias_servers_wpar;
            if ( $hmc =~ /no_hmc/ ) { next; }

            if ( $result_wpar_cfg == 0 ) {
              my $lpars_wpar_hash = "$lpars_wpar";
              $lpars_wpar_hash =~ s/$hmc\///g;
              $hash_timestamp1{$server}{$lpars_wpar_hash}{W}{$hmc} = $rrm_stat_w;

              #print "$wpar_menu" . "$hmc_wpar" . "$s" . "$server_wpar" . "$s" . "$wpar_name_enc" . "$s" . "$wpar" . "$s" . "/lpar2rrd-cgi/detail.sh?host=$hmc_wpar_enc&server=$server_wpar_enc&lpar=$lpar_a--WPAR--$wpar_name_enc&item=lpar&entitle=0&gui=1&none=none:" . "$lpar_a" . "::P:$agent_type??\n";
            }
            else {
              foreach my $lpar_alias_wpar (@alias_servers_wpar) {    ######## FIND LPAR IN ALIAS.cfg
                $lpar_alias_wpar =~ s/\\:/replace/g;
                ( undef, my $lpar_b, my $alias ) = split( /:/, $lpar_alias_wpar );
                chomp $alias;
                if ( $hmc =~ /no_hmc/ ) { next; }
                $lpar_a =~ s/replace/\\:/g;
                if ( $lpar_b eq $wpar ) {                            ############ WPAR WITH ALIAS
                  my $lpars_wpar_hash = "$lpars_wpar";
                  $lpars_wpar_hash =~ s/$hmc\///g;
                  $hash_timestamp1{$server}{$lpars_wpar_hash}{W}{$hmc} = $rrm_stat_w;

                  #print "$wpar_menu" . "$hmc_wpar" . "$s" . "$server_wpar" . "$s" . "$wpar_name_enc" . "$s" . "$wpar" . " [$alias]" . "$s" . "/lpar2rrd-cgi/detail.sh?host=$hmc_wpar_enc&server=$server_wpar_enc&lpar=$lpar_a--WPAR--$wpar_name_enc&item=lpar&entitle=0&gui=1&none=none:" . "$lpar_a" . "::P:$agent_type!!!\n";
                }
              }
            }
          }
        }

        wlmstat( $server, $lpar_dir );

      }
      Xorux_lib::write_json( "$basedir/tmp/restapi/servers_interface_ind.json", $interface_for_servers ) if ( defined $interface_for_servers && $interface_for_servers ne "" );
    }
  }

  #print Dumper \%hash_timestamp1;
  foreach my $server_a ( keys %hash_timestamp1 ) {

    #print "$server_a====\n";
    foreach my $lpar_a ( keys %{ $hash_timestamp1{$server_a} } ) {

      #print "$lpar\n";
      my $last_timestamp = 0;
      my $file           = "";
      foreach my $health_status_a ( keys %{ $hash_timestamp1{$server_a}{$lpar_a} } ) {
        foreach my $hmc_a ( keys %{ $hash_timestamp1{$server_a}{$lpar_a}{$health_status_a} } ) {
          if ( $hash_timestamp1{$server_a}{$lpar_a}{$health_status_a}{$hmc_a} > $last_timestamp ) {
            $file           = "$server_a,$lpar_a,$hmc_a,$health_status_a";
            $last_timestamp = $hash_timestamp1{$server_a}{$lpar_a}{$health_status_a}{$hmc_a};
          }
        }

        #push(@lines_dualhmc1,"$file\n");
      }
      push( @lines_dualhmc1, "$file\n" );
    }
  }
  ########################################## WPAR and LPAR - dual hmc parsing
  foreach my $line (@lines_dualhmc1) {
    chomp $line;
    if ( defined $line && $line eq "" ) {next}
    my ( $server, $lpar, $hmc, $health_status ) = split( /,/, $line );
    $server =~ s/\:/===double-col===/g;
    if ( $health_status eq "W" ) {
      my $lpars_wpar = $lpar;
      my $wpar       = ( split( /\//, $lpars_wpar ) )[-1];
      my $lpar_a     = ( split( /\//, $lpars_wpar ) )[-2];

      #my $hmc_wpar    = ( split( /\//, $lpars_wpar ) )[-3];
      my $server_wpar = ( split( /\//, $lpars_wpar ) )[-3];

      #print "$wpar,$lpar_a,$server_wpar\n";
      my $server_wpar_enc = urlencode($server_wpar);
      my $hmc_wpar_enc    = urlencode($hmc);
      my $wpar_name_enc   = urlencode($wpar);
      my $result_wpar_cfg = grep /:$wpar:/, @alias_servers_wpar;
      my $agent_type      = find_agent_type( $wrkdir, $server, $hmc, $lpar, $lpars_wpar );
      if ( $result_wpar_cfg == 0 ) {
        print "$wpar_menu" . "$hmc" . "$s" . "$server_wpar" . "$s" . "$wpar_name_enc" . "$s" . "$wpar" . "$s" . "/lpar2rrd-cgi/detail.sh?host=$hmc_wpar_enc&server=$server_wpar_enc&lpar=$lpar_a--WPAR--$wpar_name_enc&item=lpar&entitle=0&gui=1&none=none:" . "$lpar_a" . "::P:W\n";
      }
      else {
        foreach my $lpar_alias_wpar (@alias_servers_wpar) {    ######## FIND LPAR IN ALIAS.cfg
          $lpar_alias_wpar =~ s/\\:/replace/g;
          ( undef, my $lpar_b, my $alias ) = split( /:/, $lpar_alias_wpar );
          chomp $alias;
          if ( $hmc =~ /no_hmc/ ) { next; }
          $lpar_a =~ s/replace/\\:/g;
          if ( $lpar_b eq $wpar ) {                            ############ WPAR WITH ALIAS
            print "$wpar_menu" . "$hmc" . "$s" . "$server_wpar" . "$s" . "$wpar_name_enc" . "$s" . "$wpar" . " [$alias]" . "$s" . "/lpar2rrd-cgi/detail.sh?host=$hmc_wpar_enc&server=$server_wpar_enc&lpar=$lpar_a--WPAR--$wpar_name_enc&item=lpar&entitle=0&gui=1&none=none:" . "$lpar_a" . "::P:W\n";
          }
        }
      }
    }
    else {
      #      next; #13.12.2019 HD, testing new print_power_vm()
      my $server_enc    = urlencode($server);
      my $hmc_enc       = urlencode($hmc);
      my $lpar_name_enc = urlencode($lpar);
      my ($lpar_alias)  = grep /^LPAR:\Q$lpar\E/, @alias_servers;
      my $lpar_a        = "";
      my $alias         = "";
      my $alias_lpar    = "";

      if ( defined $lpar_alias && $lpar_alias ne "" ) {
        chomp $lpar_alias;
        $lpar_alias =~ s/\\:/===backslash-col===/g;

        #print "$lpar_alias\n";
        ( undef, $lpar_a, $alias ) = split( /:/, $lpar_alias, 3 );
        $lpar_a =~ s/===backslash-col===/\\:/g;
        $alias  =~ s/===backslash-col===/\\:/g;

        #print "\n,,$lpar_a,,$alias,,\n";
        chomp $alias;
        $alias =~ s/\:/===double-col===/g;
        $alias_lpar = " [$alias]";
      }
      chomp $alias;
      $lpar =~ s/\\:/:/g;
      my $agent_type = find_agent_type( $wrkdir, $server, $hmc, $lpar, "" );
      $lpar =~ s/\:/===double-col===/g;
      $lpar_name_enc = urlencode($lpar);
      $lpar_name_enc =~ s/%3A/===double-col===/g;
      $lpar_name_enc =~ s/%3D%3D%3D/===/g;
      $server_enc    =~ s/%3D%3D%3D/===/g;
      print "$health_status" . "$hmc" . "$s" . "$server" . "$s" . "$lpar_name_enc" . "$s" . "$lpar" . "$alias_lpar" . "$s" . "/lpar2rrd-cgi/detail.sh?host=$hmc_enc&server=$server_enc&lpar=$lpar_name_enc&item=lpar&entitle=0&gui=1&none=none:::P:$agent_type\n";    # active/removed lpars from hmc
                                                                                                                                                                                                                                                                      #print "$server,$lpar,$hmc,$lpar_alias\n";
    }
  }
  return 0;
}

#print "@lines_dualhmc1\n";
print Dumper \%hash_timestamp1;

sub wlmstat {

  my $server   = shift;
  my $lpar_dir = shift;

  if ( $server =~ "windows" || $server =~ "Hitachi" || $server =~ "Solaris" || $server =~ "vmware" || $server =~ "oVirt" || $server =~ "XEN" || $server =~ "NUTANIX" ) {return}
  if ( !-d "$wrkdir/$server" )                                                                                                                                         {return}
  opendir( HMC, "$wrkdir/$server" ) || error( "Can't open $wrkdir/$server: $! :" . __FILE__ . ":" . __LINE__ ) && return;
  my @hmcs = grep !/^\.\.?$/, readdir(HMC);
  closedir(HMC);

  my %sort_hash;
  my @timestamp_arr;

  foreach my $hmc_tmp (@hmcs) {
    if ( -d "$wrkdir/$server/$hmc_tmp" ) {
      my $timestamp = ( stat("$wrkdir/$server/$hmc_tmp") )[9];
      $sort_hash{$timestamp} = $hmc_tmp;
      push @timestamp_arr, $timestamp;
    }
  }

  ## sort timestamps in array -> $timestamp_arr_s[0] == last modified
  @timestamp_arr = sort { $b <=> $a } @timestamp_arr;

  my $hmc = $sort_hash{ $timestamp_arr[0] };

  if ( !-d "$wrkdir/$server/$hmc/$lpar_dir" ) {return}
  opendir( DIR, "$wrkdir/$server/$hmc/$lpar_dir" ) || error( "can't opendir $wrkdir/$server/$hmc/$lpar_dir: $! :" . __FILE__ . ":" . __LINE__ ) && return;
  my @lpars_dir_wlm = grep !/^\.\.?$/, readdir(DIR);
  closedir(DIR);

  foreach my $lpars_wlm_base (@lpars_dir_wlm) {
    my $lpars_wlm = "$wrkdir/$server/$hmc/$lpar_dir/$lpars_wlm_base";
    my $wlm       = basename($lpars_wlm);
    if ( !defined $hash_wlm{$lpars_wlm} ) {
      $hash_wlm{$lpars_wlm} = "test";
    }
    else {
      next;
    }
    if ( -d $lpars_wlm ) {    #same as wpar but test if dir has wlm- files
      if ( !-d "$lpars_wlm" ) {next}
      opendir( DIR, "$lpars_wlm" ) || error( "can't opendir $lpars_wlm: $! :" . __FILE__ . ":" . __LINE__ ) && next;
      my @lpars_dir_wlm = grep !/^\.\.?$/, readdir(DIR);
      closedir(DIR);
      @lpars_dir_wlm = sort @lpars_dir_wlm;
      if ( !defined $lpars_dir_wlm[0] )                                { next; }
      if ( $lpars_dir_wlm[0] !~ "wlm" || $lpars_dir_wlm[-1] !~ "wlm" ) { last; }
      chomp $lpars_wlm;
      my $agent_type     = find_agent_type( $wrkdir, $server, $hmc, $lpar_dir, "" );
      my $wlm            = ( split( /\//, $lpars_wlm ) )[-1];
      my $lpar_a         = ( split( /\//, $lpars_wlm ) )[-2];
      my $hmc_wlm        = ( split( /\//, $lpars_wlm ) )[-3];
      my $server_wlm     = ( split( /\//, $lpars_wlm ) )[-4];
      my $server_wlm_enc = urlencode($server_wlm);
      my $hmc_wlm_enc    = urlencode($hmc_wlm);
      my $wlm_name_enc   = urlencode($wlm);

      #my $result_wlm_cfg = grep /:$wlm:/, @alias_servers_wpar;
      if ( $hmc =~ /no_hmc/ ) { next; }
      print "$wlm_menu" . "$hmc_wlm" . "$s" . "$server_wlm" . "$s" . "$wlm_name_enc" . "$s" . "$wlm" . "$s" . "/lpar2rrd-cgi/detail.sh?host=$hmc_wlm_enc&server=$server_wlm_enc&lpar=$lpar_a--WPAR--$wlm_name_enc&item=lpar&entitle=0&gui=1&none=none:" . "$lpar_a" . "::P:$agent_type\n";
    }
  }
}

sub print_solaris_all {
  my $count_cpu = 0;
  foreach my $server_all (@wrkdir_all) {
    $server_all = "$wrkdir/$server_all";
    my $server = basename($server_all);
    if ( -d "$wrkdir/Solaris/" ) {
      if ( $server eq "Solaris" ) {
        chomp $server_all;
        chomp $server;
        opendir( DIR, "$wrkdir/$server" ) || error( "can't opendir $wrkdir/$server: $! :" . __FILE__ . ":" . __LINE__ ) && next;
        my @hmcdir_all = grep !/^\.\.?$/, readdir(DIR);
        closedir(DIR);
        if ( !@hmcdir_all ) {    ####### if exist only directory Solaris
          if ( -d "$wrkdir/Solaris--unknown/" ) {
            opendir( DIR, "$wrkdir/Solaris--unknown" ) || error( "can't opendir $wrkdir/$server: $! :" . __FILE__ . ":" . __LINE__ ) && next;
            my @hmcdir_all_1 = grep !/^\.\.?$/, readdir(DIR);
            closedir(DIR);
            foreach my $hmc_all_base_1 (@hmcdir_all_1) {
              my $hmc_all = "$wrkdir/Solaris--unknown/$hmc_all_base_1";
              my $hmc     = basename($hmc_all);
              my $item    = "sol-ldom";
              opendir( DIR, "$wrkdir/Solaris--unknown/$hmc" ) || error( "can't opendir $wrkdir/Solaris--unknown/$hmc: $! :" . __FILE__ . ":" . __LINE__ ) && next;
              my @no_ldom = grep !/^\.\.?$/, readdir(DIR);
              foreach my $no_ldom_file (@no_ldom) {
                my $no_ldom = basename($no_ldom_file);
                if ( !-f "$wrkdir/Solaris--unknown/no_hmc/$no_ldom/cpu.mmm" ) {next}    # some empty directories when Solaris directory does not exists
                                                                                        #my $ldom        = "$no_ldom";
                                                                                        #print "$ldom!!\n";
                $no_ldom =~ s/\:/===double-col===/g;                                    # goes to menu.txt
                print "$actived" . "no_hmc" . "$s" . "$no_ldom" . "$s" . "$no_ldom" . "$s" . "$no_ldom" . "$s" . "/lpar2rrd-cgi/detail.sh?host=0&server=Solaris--unknown&lpar=$no_ldom&item=$item&entitle=0&gui=1&none=none:::S:L\n";
              }
            }
          }
        }
        foreach my $hmc_all_base (@hmcdir_all) {
          my $hmc_all = "$wrkdir/$server/$hmc_all_base";
          my $hmc     = basename($hmc_all);
          my $item    = "";
          if ( -f "$hmc_all/solaris11.txt" && -f "$hmc_all/solaris10.txt" ) {
            $item = "sol10";
          }
          elsif ( -f "$hmc_all/solaris11.txt" && !-f "$hmc_all/solaris10.txt" ) {
            $item = "sol11";
          }
          else {
            $item = "sol10";
          }
          my $item_l    = "sol-ldom";
          my $un        = "";
          my $ldom_uuid = basename($hmc_all);
          my $server_a  = $server;
          $server_a =~ s/\:/===double-col===/g;    # goes to menu.txt
          if ( -d "$wrkdir/$server/$ldom_uuid/ZONE" ) {
            opendir( DIR, "$wrkdir/$server/$ldom_uuid/ZONE" ) || error( "can't opendir $wrkdir/$server/$ldom_uuid: $! :" . __FILE__ . ":" . __LINE__ ) && next;
            my @only_zone_path = grep /total|global|system/, readdir(DIR);    ########## ONLY SYSTEM ZONES PRINT
            foreach my $only_zone (@only_zone_path) {
              $only_zone =~ s/\.mmm//g;
              $un        =~ "-$only_zone";
              if ( $only_zone eq "total" && $count_cpu == 0 ) {
                print "$actived" . "no_hmc" . "$s" . "$server_a" . "$s" . "cpuagg-sol" . "$s" . "Total" . "$s" . "/lpar2rrd-cgi/detail.sh?host=no_hmc&server=$server_a&lpar=cod&item=cpuagg-sol&entitle=0&gui=1&none=none:::S:P\n";
                $count_cpu++;

              }
              my $ldom_uuid_a = $ldom_uuid;
              my ( $cdom1, $ldom1 ) = "";
              if ( $ldom_uuid =~ /:/ ) {
                ( $cdom1, $ldom1 ) = split( /:/, $ldom_uuid );
              }
              else {
                $ldom1 = "$ldom_uuid_a";
                $cdom1 = "";
              }
              $ldom_uuid_a =~ s/\:/===double-col===/g;    # goes to menu.txt
              my $file_test = "$wrkdir/$server/$ldom_uuid/ZONE/$only_zone.mmm";
              my $file_time = ( stat("$file_test") )[9];
              if ( $actual_last_30_days_power < $file_time ) {
                print "$actived" . "no_hmc" . "$s" . "$ldom1" . "$s" . "$only_zone" . "$s" . "$only_zone" . "$s" . "/lpar2rrd-cgi/detail.sh?host=$server_a&server=$ldom_uuid_a&lpar=$only_zone&item=$item$un&entitle=0&gui=1&none=none::$cdom1:S:Z\n";
              }

              #print "$actived" . "no_hmc" . "$s" . "$ldom_uuid" . "$s" . "$only_zone" . "$s" . "$only_zone" . "$s" . "/lpar2rrd-cgi/detail.sh?host=$server&server=$ldom_uuid&lpar=$only_zone&item=$item$un$only_zone&entitle=0&gui=1&none=none:::S:Z\n";    old method
            }
          }
          else {
            #print "$ldom_uuid!!!\n";
          }
          if ( -d "$wrkdir/$server/$ldom_uuid/ZONE" ) {    ########## ZONE with other name than system,global,total
            opendir( DIR, "$wrkdir/$server/$ldom_uuid/ZONE" ) || error( "can't opendir $wrkdir/$server/$ldom_uuid: $! :" . __FILE__ . ":" . __LINE__ ) && next;
            my @only_zone_path = grep !/^\.\.?$|total|global|system|^\.mmm$/, readdir(DIR);
            foreach my $only_zone (@only_zone_path) {
              $only_zone =~ s/\.mmm//g;
              $un = "-$only_zone";
              my $ldom_uuid_a = $ldom_uuid;
              my ( $cdom1, $ldom1 ) = "";
              if ( $ldom_uuid =~ /:/ ) {
                ( $cdom1, $ldom1 ) = split( /:/, $ldom_uuid );
              }
              else {
                $ldom1 = "$ldom_uuid_a";
                $cdom1 = "";
              }
              $ldom_uuid_a =~ s/\:/===double-col===/g;    # goes to menu.txt
              my $file_test = "$wrkdir/$server/$ldom_uuid/ZONE/$only_zone.mmm";
              my $file_time = ( stat("$file_test") )[9];
              if ( !-f $file_test ) { next; }
              if ( $actual_last_30_days_power < $file_time ) {
                print "$actived" . "no_hmc" . "$s" . "$ldom1" . "$s" . "$only_zone" . "$s" . "$only_zone" . "$s" . "/lpar2rrd-cgi/detail.sh?host=$server_a&server=$ldom_uuid_a&lpar=$only_zone&item=$item$un&entitle=0&gui=1&none=none::$cdom1:S:Z\n";
              }
            }
          }
          opendir( DIR, "$wrkdir/$server/$ldom_uuid" ) || error( "can't opendir $wrkdir/$server/$ldom_uuid: $! :" . __FILE__ . ":" . __LINE__ ) && next;
          rewinddir(DIR);
          my @ldom_path1 = grep /_ldom|net|san*|solaris/, readdir(DIR);
          closedir(DIR);
          if (@ldom_path1) {

            #my $ldom_name = "";
            my $solaris_type   = "";
            my $ldom_path_test = "";
            my $file_time      = "";

            #print "$wrkdir/$server/$ldom_uuid/$ldom_uuid\n";
            my $string_ldom = "_ldom";
            if ( $ldom_uuid =~ /:/ ) {
              my ( undef, $real_ldom_name ) = split( /:/, $ldom_uuid );
              if ( -f "$wrkdir/$server/$ldom_uuid/$real_ldom_name$string_ldom.mmm" ) {
                $ldom_path_test = "$wrkdir/$server/$ldom_uuid/$real_ldom_name$string_ldom.mmm";
                $file_time      = ( stat("$ldom_path_test") )[9];
                $solaris_type   = "L";
              }
              else {
                $ldom_path_test = "$wrkdir/$server/$ldom_uuid/ZONE/global.mmm";
                $file_time      = ( stat("$ldom_path_test") )[9];
                $solaris_type   = "G";
              }
            }
            else {
              $ldom_path_test = "$wrkdir/$server/$ldom_uuid/ZONE/global.mmm";
              my $no_ldom_test = "$wrkdir/$server/$ldom_uuid/no_ldom";
              if ( !-f $ldom_path_test ) {
                if ( -f "$no_ldom_test" ) {
                  my $ldom_file = $ldom_uuid;
                  $ldom_file =~ s/\.mmm//g;
                  my $ldom_name = "$ldom_file";
                  $ldom_name =~ s/_ldom$//g;
                  $ldom_name =~ s/\s+//g;
                  my $ldom_name_a = $ldom_name;
                  my ( $cdom1, $ldom1 ) = "";
                  if ( $ldom_name =~ /:/ ) {
                    ( $cdom1, $ldom1 ) = split( /:/, $ldom_name );
                  }
                  else {
                    $ldom1 = "$ldom_name_a";
                    $cdom1 = "";
                  }
                  $ldom_name_a =~ s/\:/===double-col===/g;    # goes to menu.txt
                  my $ldom_uuid_a = $ldom_uuid;
                  $ldom_uuid_a =~ s/\:/===double-col===/g;    # goes to menu.txt
                  $solaris_type = "G";

                  #print "===$ldom_uuid===\n";
                  print "$actived" . "no_hmc" . "$s" . "$ldom1" . "$s" . "$ldom_name_a" . "$s" . "$ldom_name_a" . "$s" . "/lpar2rrd-cgi/detail.sh?host=0&server=Solaris--unknown&lpar=$ldom_uuid_a&item=$item_l&entitle=0&gui=1&none=none::$cdom1:S:$solaris_type\n";
                }
                next;
              }
              $file_time    = ( stat("$ldom_path_test") )[9];
              $solaris_type = "G";
            }
            my $menu_txt3 = "";
            my $menu_txt4 = "";
            my $ldom_file = $ldom_uuid;
            $ldom_file =~ s/\.mmm//g;
            my $ldom_name = "$ldom_file";
            $ldom_name =~ s/_ldom$//g;
            $ldom_name =~ s/\s+//g;
            my $ldom_name_a = $ldom_name;
            my ( $cdom1, $ldom1 ) = "";

            if ( $ldom_name =~ /:/ ) {
              ( $cdom1, $ldom1 ) = split( /:/, $ldom_name );
            }
            else {
              $ldom1 = "$ldom_name_a";
              $cdom1 = "";
            }
            $ldom_name_a =~ s/\:/===double-col===/g;                  # goes to menu.txt
            my $ldom_uuid_a = $ldom_uuid;
            $ldom_uuid_a =~ s/\:/===double-col===/g;                  # goes to menu.txt
                                                                      #print "$file_time\n";
            if ( -f "$wrkdir/$server/$ldom_uuid/solaris10.txt" ) {    ### some Solaris10 looks like CDOM/LDOM but can be Global-zone
              if ( $actual_last_30_days_power < $file_time ) {        ### SOLARIS11 LDOM/CDOM or Global zone
                print "$actived" . "no_hmc" . "$s" . "$ldom1" . "$s" . "$ldom_name_a" . "$s" . "$ldom_name_a" . "$s" . "/lpar2rrd-cgi/detail.sh?host=0&server=Solaris--unknown&lpar=$ldom_uuid_a&item=$item_l&entitle=0&gui=1&none=none::$cdom1:S:$solaris_type\n";
              }
            }
            else {
              if ( $actual_last_30_days_power < $file_time ) {        ### SOLARIS11 LDOM/CDOM or Global zone
                print "$actived" . "no_hmc" . "$s" . "$ldom1" . "$s" . "$ldom_name_a" . "$s" . "$ldom_name_a" . "$s" . "/lpar2rrd-cgi/detail.sh?host=0&server=Solaris--unknown&lpar=$ldom_uuid_a&item=$item_l&entitle=0&gui=1&none=none::$cdom1:S:$solaris_type\n";
              }
            }
          }
          else {    ###if exist Solaris directory - but has not some ldom or zones. Only uuid and solaris.txt
            if ( -d "$wrkdir/Solaris--unknown/" ) {
              opendir( DIR, "$wrkdir/Solaris--unknown" ) || error( "can't opendir $wrkdir/$server: $! :" . __FILE__ . ":" . __LINE__ ) && next;
              my @hmcdir_all_1 = grep !/^\.\.?$/, readdir(DIR);
              closedir(DIR);
              foreach my $hmc_all_base_1 (@hmcdir_all_1) {
                my $hmc_all = "$wrkdir/Solaris--unknown/$hmc_all_base_1";
                my $hmc     = basename($hmc_all);
                my $item    = "sol-ldom";
                opendir( DIR, "$wrkdir/Solaris--unknown/$hmc" ) || error( "can't opendir $wrkdir/Solaris--unknown/$hmc: $! :" . __FILE__ . ":" . __LINE__ ) && next;
                my @no_ldom = grep !/^\.\.?$/, readdir(DIR);
                foreach my $no_ldom_file (@no_ldom) {
                  my $no_ldom = basename($no_ldom_file);
                  if ( -d "$wrkdir/Solaris--unknown/$no_ldom" ) {
                    opendir( DIR, "$wrkdir/Solaris/$no_ldom" ) || error( "can't opendir $wrkdir/Solaris/$no_ldom: $! :" . __FILE__ . ":" . __LINE__ ) && next;
                    my @ldom_path = grep /ldom|san|ZONE/, readdir(DIR);
                    if (@ldom_path) {
                      $no_ldom =~ s/\:/===double-col===/g;    # goes to menu.txt
                      print "$actived" . "no_hmc" . "$s" . "$no_ldom" . "$s" . "$no_ldom" . "$s" . "$no_ldom" . "$s" . "/lpar2rrd-cgi/detail.sh?host=0&server=Solaris--unknown&lpar=$no_ldom&item=$item&entitle=0&gui=1&none=none:::S:G\n";
                    }
                  }
                }
              }
            }
          }
        }
      }
      elsif ( $server eq "Solaris--unknown" ) {    ### if exist Solaris and Solaris--unknown too, but Ldom/Zone has data only in Solaris--unknown
        chomp $server_all;
        chomp $server;
        opendir( DIR, "$wrkdir/$server/no_hmc" ) || error( "can't opendir $wrkdir/$server/no_hmc: $! :" . __FILE__ . ":" . __LINE__ ) && next;
        my @solaris_u_all = grep !/^\.\.?$/, readdir(DIR);
        foreach my $solaris_u (@solaris_u_all) {
          if ( !-d "$wrkdir/Solaris/$solaris_u" ) {
            my $item      = "sol-ldom";
            my $file_test = "$wrkdir/Solaris--unknown/no_hmc/$solaris_u/cpu.mmm";
            if ( !-f $file_test ) {next}

            # if zone running only under the CDOM/LDOM, it's already in the menu
            if ( $solaris_u =~ /\:zone\:/ ) {
              my ( $server_sol_test, undef, $solaris_zone ) = split( /\:/, $solaris_u );
              if ( -f "$wrkdir/Solaris/$server_sol_test:$server_sol_test/ZONE/$solaris_zone.mmm" ) {next}
            }
            my $file_time = ( stat("$file_test") )[9];
            if ( $actual_last_30_days_power < $file_time ) {
              $solaris_u =~ s/\:/===double-col===/g;    # goes to menu.txt
              print "$actived" . "no_hmc" . "$s" . "$solaris_u" . "$s" . "$solaris_u" . "$s" . "$solaris_u" . "$s" . "/lpar2rrd-cgi/detail.sh?host=0&server=Solaris--unknown&lpar=$solaris_u&item=$item&entitle=0&gui=1&none=none:::S:L\n";
            }
          }
        }
      }
    }
    elsif ( -d "$wrkdir/Solaris--unknown/" ) {
      if ( $server eq "Solaris--unknown" ) {
        chomp $server_all;
        chomp $server;
        opendir( DIR, "$wrkdir/$server" ) || error( "can't opendir $wrkdir/$server: $! :" . __FILE__ . ":" . __LINE__ ) && next;
        my @hmcdir_all = grep !/^\.\.?$/, readdir(DIR);
        closedir(DIR);
        foreach my $hmc_all_base (@hmcdir_all) {
          my $hmc_all = "$wrkdir/$server/$hmc_all_base";
          my $hmc     = basename($hmc_all);
          my $item    = "sol-ldom";
          opendir( DIR, "$wrkdir/$server/$hmc" ) || error( "can't opendir $wrkdir/$server/$hmc: $! :" . __FILE__ . ":" . __LINE__ ) && next;
          my @no_ldom = grep !/^\.\.?$/, readdir(DIR);
          foreach my $no_ldom_file (@no_ldom) {
            my $no_ldom = basename($no_ldom_file);
            if ( !-f "$wrkdir/$server/$hmc/$no_ldom/cpu.mmm" ) {next}    # some empty directories when Solaris directory does not exists
            $no_ldom =~ s/\:/===double-col===/g;                         # goes to menu.txt
            print "$actived" . "no_hmc" . "$s" . "$no_ldom" . "$s" . "$no_ldom" . "$s" . "$no_ldom" . "$s" . "/lpar2rrd-cgi/detail.sh?host=0&server=Solaris--unknown&lpar=$no_ldom&item=$item&entitle=0&gui=1&none=none:::S:G\n";
          }
        }
      }
    }
  }
}

############### VMWARE
sub print_vm_all {
  my $uuid;
  my $name_vm;
  my $list_of_vm = "$wrkdir/vmware_VMs/vm_uuid_name.txt";
  my $vm_dir     = "$wrkdir/vmware_VMs";
  my ( $code, $linux_uuids ) = -f $agents_uuid_file ? Xorux_lib::read_json($agents_uuid_file) : ( 0, undef );
  my %vm_menu_lines = ();

  opendir( DIR, "$vm_dir" ) || error( " directory does not exists : $vm_dir " . __FILE__ . ":" . __LINE__ ) && return 1;
  my @all_rrm_files = grep {/\.rrm$/} readdir(DIR);
  closedir(DIR);
  s/$_/$vm_dir\/$_/ for @all_rrm_files;
  if ( !defined $vm_list[0] ) {
    error( "Not exists $list_of_vm: $!" . __FILE__ . ":" . __LINE__ ) && return 1;
  }
  while ( my $server_all = shift(@wrkdir_all) ) {
    $server_all = "$wrkdir/$server_all";
    if ( !-d $server_all )               { next; }
    if ( -l $server_all )                { next; }
    if ( $server_all =~ /\/vmware_VMs/ ) { next; }
    my $server  = basename($server_all);
    my $hmc_dir = "$wrkdir/$server";
    opendir( DIR, "$hmc_dir" ) || error( " directory does not exists : $hmc_dir " . __FILE__ . ":" . __LINE__ ) && return 1;
    my @hmc_dir_all = grep !/^\.\.?$/, readdir(DIR);
    closedir(DIR);
    s/$_/$hmc_dir\/$_/ for @hmc_dir_all;

    while ( my $hmc_all = shift(@hmc_dir_all) ) {
      next if ( !-f "$hmc_all/vmware.txt" );
      next if ( !-f "$hmc_all/pool.rrm" );     # strange when not present
      my $file_time = ( stat("$hmc_all/pool.rrm") )[9];
      next if $file_time < $actual_last_30_days_vm;

      # case: user moved esxi from one cluster/vcenter to another and later returned -> esxi & VMs were printed under both
      # the dir structure was the same as with two hmcs
      # trick to find the newest pool.rrm and only this to print
      # go through this while only once i.e. last; at the end

      my $newer_hmc = "$hmc_all";

      # print "652 ----------------- \@hmc_dir_all @hmc_dir_all ". scalar @hmc_dir_all ." $file_time\n";
      if ( scalar @hmc_dir_all > 0 ) {
        foreach (@hmc_dir_all) {
          if ( -f "$_/pool.rrm" ) {
            $newer_hmc = $_ if ( stat("$_/pool.rrm") )[9] > $file_time;
          }
        }
        next if "$newer_hmc" ne "$hmc_all";
      }

      # my $hmc          = basename($hmc_all);
      my $hmc = basename($newer_hmc);

      my $cluster_name = "$wrkdir/$server/$hmc/my_cluster_name";
      my $cluster_a;
      my $cluster;
      if ( -f $cluster_name ) {
        open( FC, "< $cluster_name" ) || error( "Cannot read $cluster_name: $!" . __FILE__ . ":" . __LINE__ );
        $cluster_a = <FC>;
        close(FC);
      }
      if ( defined $cluster_a && $cluster_a ne '' ) {
        ( $cluster, my $alias_vm ) = split( /\|/, $cluster_a );
        chomp $cluster;
      }
      else {
        $cluster = "";
      }
      $cluster =~ s/\:/===double-col===/g;                       # goes to menu.txt
      my $vm_list_info_file = "$wrkdir/$server/$hmc/cpu.csv";    # from here we can test poweredOn or Off
      my @vm_list_info      = "";
      if ( -f "$vm_list_info_file" && open( FC, "< $vm_list_info_file" ) ) {
        @vm_list_info = <FC>;
        close(FC);
      }
      else {
        error( "Cannot read $vm_list_info_file: $!" . __FILE__ . ":" . __LINE__ );
      }

      my $list_server_vm       = "$wrkdir/$server/$hmc/VM_hosting.vmh";
      my $vcenter_name_for_VM  = "";
      my $vcenter_uuid         = "";
      my $my_vcenter_name_file = "$wrkdir/$server/$hmc/my_vcenter_name";
      if ( -f "$my_vcenter_name_file" ) {
        open( FC, "< $my_vcenter_name_file" ) || error( "Cannot read $my_vcenter_name_file: $!" . __FILE__ . ":" . __LINE__ );
        my $my_vcenter_name = <FC>;
        chomp $my_vcenter_name;
        close(FC);
        ( undef, $vcenter_name_for_VM, $vcenter_uuid ) = split( /\|/, $my_vcenter_name );
        if ( !defined $vcenter_name_for_VM ) {
          $vcenter_name_for_VM = "";
        }
        if ( !defined $vcenter_uuid ) {
          $vcenter_uuid = "";
        }
      }

      my @vm_folder_path_files_array = ( bsd_glob "$wrkdir/vmware_$vcenter_uuid/*/vm_folder_path.json" );

      # print "1505 \$cluster $cluster \n ---------------------------------------------------- \@vm_folder_path_files_array @vm_folder_path_files_array\n";
      # 1505 $cluster cluster_ClusterOL
      # and the cluster filename: cluster_name_cluster_ClusterOL
      my $vm_folder_path_file = "";

      if ( scalar @vm_folder_path_files_array > 1 ) {    # more clusters, choose the appropriate one
        foreach my $vm_folder_path_file_test (@vm_folder_path_files_array) {
          $vm_folder_path_file_test =~ s/vm_folder_path.json/cluster_name_$cluster/;

          # print "1514 --------------------- \$vm_folder_path_file_test $vm_folder_path_file_test\n";
          if ( -f $vm_folder_path_file_test ) {
            $vm_folder_path_file = $vm_folder_path_file_test;
            $vm_folder_path_file =~ s/cluster_name_$cluster/vm_folder_path.json/;

            # print "1516 found \$vm_folder_path_file $vm_folder_path_file\n";
            last;
          }
        }
      }
      else {
        $vm_folder_path_file = $vm_folder_path_files_array[0];
      }
      my $vm_folder_pathes = "";

      # print "read file $vm_folder_path_file\n";
      if ( defined $vm_folder_path_file && -f $vm_folder_path_file ) {
        $vm_folder_pathes = Xorux_lib::read_json($vm_folder_path_file);

        # print Dumper ($vm_folder_pathes);
      }

      my @vm_list_server;    ###### START OR END VM
      if ( -e $list_server_vm ) {
        open( FC, "< $list_server_vm" ) || error( "Cannot read $list_server_vm: $!" . __FILE__ . ":" . __LINE__ ) && next;
        @vm_list_server = <FC>;
        close(FC);
      }
      foreach my $vm_servers (@vm_list_server) {
        chomp $vm_servers;
        if ( $vm_servers =~ /end=\d+$/ ) { next; }
        my @startends = split( /:/, $vm_servers );

        # ( my $uuid_server, my $start, my $end ) = split( /:s/, $vm_servers );
        my $uuid_server = $startends[0];
        my $start       = $startends[-1];
        my $uuid_test   = "";
        ($uuid_test) = grep /\Q$uuid_server/, @all_rrm_files;
        next if !defined $uuid_test;
        next if $uuid_test eq "";

        ($uuid_test) = grep /\Q$uuid_server/, @vm_list;
        my $uuid                = "";
        my $vm_name             = "";
        my $linux_yes           = ":";
        my $real_linux_dir_name = "";    # to put real linux directory name
        if ( defined $uuid_test && $uuid_test ne "" ) {
          ( $uuid, $vm_name ) = split( /,/, $uuid_test );
          chomp $vm_name;

          # print "1343 \$vm_name $vm_name\n";
          if ( -f "$wrkdir/Linux--unknown/no_hmc/$vm_name/uuid.txt" ) {
            $linux_yes           = ":M";
            $real_linux_dir_name = $vm_name;

            # print "1362 $wrkdir/Linux--unknown/no_hmc/$vm_name/uuid.txt\n";
          }
          else {
            chomp $uuid_test;

            # print "$uuid_test!!!\n";
            my ( undef, undef, undef, $uuid_old, $vm_name_a ) = split( /,/, $uuid_test );

            # print "1351 $uuid_old ".Xorux_lib::uuid_big_endian_format( $uuid_old, '-' )."\n";
            if ( $code
              && defined $uuid_old
              && $uuid_old ne ''
              && defined $linux_uuids->{ Xorux_lib::uuid_big_endian_format( $uuid_old, '-' ) } )
            {
              $linux_yes           = ":M";
              $real_linux_dir_name = $linux_uuids->{ Xorux_lib::uuid_big_endian_format( $uuid_old, '-' ) };

              # print "1372 \$vm_name $vm_name \$real_linux_dir_name $real_linux_dir_name\n";
            }
            else {    # in case it is not big endian
              if ( $code
                && defined $uuid_old
                && $uuid_old ne ''
                && defined $linux_uuids->{ uc($uuid_old) } )
              {
                $linux_yes           = ":M";
                $real_linux_dir_name = $linux_uuids->{ uc($uuid_old) };

                # print "1378 \$vm_name $vm_name \$real_linux_dir_name $real_linux_dir_name\n";
              }
            }

            #         my ($testV) = grep /\Q$uuid_test/, @linux_uuid_files;
          }
        }
        chomp $start;
        $start =~ s/start=//g;

        # print "1321 \$uuid_server $uuid_server \$start $start\n";

        $hmc =~ s/\:/===double-col===/g;
        if ( $uuid eq $uuid_server ) {
          my $alias_vmware = "";
          my $alias_test   = "";
          my $vm_name_a    = "";
          my $alias_vmw    = "";
          ($alias_test) = grep /\Q$vm_name/, @alias_vmware;
          if ( defined $alias_test && $alias_test ne "" ) {
            ( undef, $vm_name_a, $alias_vmw ) = split( /:/, $alias_test );
            chomp $alias_vmw;
            $alias_vmware = " [$alias_vmw]";
            chomp $alias_vmware;
          }
          my $last_timestamp = ( stat("$wrkdir/vmware_VMs/$uuid_server.rrm") )[9];
          if ( $last_timestamp > $actual_last_30_days_vm ) {

            # there can be same VM, same name, same uuid, in more vCenters but only one is poweredOn and only this should be printed
            # this means if VM is poweredOff and has actual data file timestamp so this should not be printed
            # actual is not older than 60 minutes
            ( my $info_line ) = grep /$uuid/, @vm_list_info;

            # next if !defined $info_line; # in some spec cases - e.g. manual file update
            if ( defined $info_line && $info_line =~ "poweredOff" && ( $last_timestamp + 3600 ) > $actual_unix_time ) {
              print STDERR "ERROR          : poweredOff & actual data file for $info_line: " . __FILE__ . ":" . __LINE__ . "\n";
              next;
            }
            $vm_name =~ s/\:/===double-col===/g;
            #
            ###  VM folders solution
            #
            my $folder_moref = ( split( ",", $info_line ) )[12];
            if ($folder_moref) {
              chomp $folder_moref;
            }
            my $folder_path = "";

            # print "1117 \$info_line $info_line \$folder_moref $folder_moref\n";
            if ( defined $folder_moref && $folder_moref ne "" && $vm_folder_pathes ne "" && index( $folder_moref, "group-" ) == 0 ) {

              # print "\$info_line $info_line \$folder_moref $folder_moref\n";
              $folder_path = give_path_to_folder( $folder_moref, \%$vm_folder_pathes, "", 0 );

              # print "\$info_line $info_line \$folder_moref $folder_moref \$folder_path $folder_path\n";
              if ( $folder_path ne "" ) {
                $folder_path .= ":$folder_moref";
              }
            }

            # $folder_path =~ s/([^a-zA-Z0-9_.!:~*()'\''-])/sprintf("%%%02X", ord($1))/ge;print "$s\n";

            my $linux_dir = "";
            $linux_dir = "&real_linux_dir_name=$real_linux_dir_name" if $real_linux_dir_name ne "";
            my $vm_line = "L:$cluster:$server:$uuid_server:$vm_name$alias_vmware:/lpar2rrd-cgi/detail.sh?host=$hmc&server=$server&lpar=$uuid_server&item=lpar&entitle=0&gui=1&none=none" . $linux_dir . "::$vcenter_name_for_VM:V$linux_yes:$folder_path:";

            # there can be (standard & non standard) move of VM from one vcenter (esxi) to another
            # in this case the =start =end line in VM_hosting.vmh is not properly ended with =end
            # so there are two started lines for the same vm uuid, let us take the newer one
            ## this is not good in case user moved VM between vcenters more than one time and it can be that
            ## the time start= is in both (ESXI) vcenters and the newer one is not the right one we need to show in menu
            ## take the cpu.csv modification time instead

            if ( exists $vm_menu_lines{$uuid_server} ) {
              print STDERR "double line $vm_line $start\nsecond: $vm_menu_lines{$uuid_server}{line} : $vm_menu_lines{$uuid_server}{start}: " . __FILE__ . ":" . __LINE__ . "\n";
              if ( $start <= $vm_menu_lines{$uuid_server}{start} ) {
                next;
              }
            }
            $vm_menu_lines{$uuid_server}{line}  = $vm_line;
            $vm_menu_lines{$uuid_server}{start} = $start;

            # print "$vm_line\n"; # is now printed at the end from hash
          }
        }
      }
      last;
    }
  }

  #foreach my $key (keys %vm_menu_lines) left_curly # this is memory intensive
  while ( my ( $key, $value ) = each(%vm_menu_lines) ) {
    print "$vm_menu_lines{$key}{line}\n";
  }
  return 0;
}

############### print "create folder path for VM in folders\n\n";

sub give_path_to_folder {
  my $moref           = shift;
  my $group_ref       = shift;
  my %group           = %$group_ref;
  my $path            = shift;
  my $recursion_count = shift;
  my $recursion_limit = 15;

  chomp $moref;

  $recursion_count++;

  # print "\$recursion_count $recursion_count\n";
  if ( $recursion_count > $recursion_limit ) {
    print "error recursion limit is over recursion_limit $recursion_limit\n";
    return $path;
  }

  #my $info = $group{$moref};
  #print "inside sub \$info $info \$moref $moref \$recursion_count $recursion_count\n";

  return $path if !exists $group{$moref};
  ( my $parent, my $name ) = split( ",", $group{$moref} );
  $path = $name . "/" . $path;
  if ( !exists $group{$parent} ) {
    return $path;
  }
  else {
    give_path_to_folder( $parent, \%group, $path, $recursion_count );
  }
}

############### URL ENCODING
sub urlencode {
  my $s = shift;

  # $s =~ s/ /+/g;
  $s =~ s/([^a-zA-Z0-9_.!~*()'\''-])/sprintf("%%%02X", ord($1))/ge;

  # $s =~ s/([^A-Za-z0-9\+-_])/sprintf("%%%02X", ord($1))/seg;
  return $s;
}

sub urldecode {
  my $s = shift;
  $s =~ s/\%([A-Fa-f0-9]{2})/pack('C', hex($1))/seg;

  # $s =~ s/\+/ /g;
  return $s;
}

sub error {
  my $text     = shift;
  my $act_time = localtime();
  chomp($text);

  #print "ERROR          : $text : $!\n";
  print STDERR "$act_time:ERROR: $text\n";
  return 1;
}

sub basename {
  return ( split "\/", $_[0] )[-1];
}

### Alerting support, each lpar/VM must have defined
# A: AIX or Linux on Power or VIOS without SEA
# B: AIX or Linux on Power or VIOS without SEA without SAN (well, it should not happen as at least san-sissas0.mmm or san-vscsi should be in place)
# C: AIX or Linux on Power without OS agenta --> only HMC data
# L: Linux OS agent or AIX or WPAR without HMC CPU
# M: Linux OS agent or AIX or Solaris or WPAR without HMC CPU & SAN
# I: AS400
# S: Solaris - no HMC CPU & SAN
# V: VIOS with SEA
# U: VIOS with SEA without SAN (well, it should not happen as at least san-sissas0.mmm should be in place)
# W: WPAR (cpu,mem,pg only)
# Y: AIX or Linux on Power with SAN but without SAN resp time  (especially Linuxes without iostat cmd installed)
# X: VMware

sub find_agent_type {
  my ( $wrkdir, $server, $hmc, $lpar, $wpar ) = @_;
  my $type     = "A";
  my $lpar_dir = "$wrkdir/$server/$hmc/$lpar";

  if ( !-d "$lpar_dir" ) {
    return "C";
  }

  if ( $lpar =~ m/--AS400--$/ ) {
    return "I";
  }

  if ( $server =~ /^Solaris--unknown$/ ) {
    return "S";
  }

  if ( !$wpar eq '' ) {

    # WPAR
    return "W";
  }

  if ( opendir( DIR, "$lpar_dir" ) ) {    # || error( " directory does not exists : $lpar_dir " . __FILE__ . ":" . __LINE__ ) && return 1;
    my @all_files = grep !/^\.\.?$/, readdir(DIR);
    closedir(DIR);

    my @files = grep {/^sea.*mmm/} @all_files;
    if (@files) {
      my @vios_san = grep {/^san.*mmm/} @all_files;
      if (@vios_san) {
        return "V";
      }
      return "U";
    }

    @files = grep {/^san\-.*mmm/} @all_files;
    if (@files) {
      if ( -f "$lpar_dir.rrm" || -f "$lpar_dir.rrh" ) {
        @files = grep {/^san_resp.*mmm/} @all_files;
        if (@files) {

          # AIX with SAN
          return "A";
        }

        # AIX/Linux on Power without installed iostat (no response time)
        return "Y";
      }
      else {
        #Linux (Solaris no as it cannot have SAN)
        @files = grep {/^san_resp.*mmm/} @all_files;
        if (@files) {
          return "L";
        }

        # Linux without installed iostat (no response time)
        return "Y";
      }
    }
  }
  if ( -f "$lpar_dir/cpu.mmm" ) {
    if ( -f "$lpar_dir.rrm" || -f "$lpar_dir.rrh" ) {

      # AIX without SAN
      return "B";
    }
    else {
      #Linux (Solaris no as it cannot have SAN)
      return "M";
    }
  }

  # nothing has been identified, expecting AIX without the agent
  return "C";
}

sub print_hitachi_all {
  my $hitachi_dir = "$wrkdir/Hitachi";

  opendir( DIR, "$hitachi_dir" ) || error( " directory does not exists : $hitachi_dir " . __FILE__ . ":" . __LINE__ ) && return 1;
  my @server_dir = grep !/^\.\.?$/, readdir(DIR);
  closedir(DIR);

  foreach my $server (@server_dir) {
    if ( !-d "$hitachi_dir/$server" ) { next; }
    my $server_col = $server;
    $server_col =~ s /:/===double-col===/g;
    my $server_enc       = urlencode($server_col);
    my $active_lpar_file = "$hitachi_dir/$server/lpar_uuids.json";
    my ( $code, $active_lpars ) = -f $active_lpar_file ? Xorux_lib::read_json($active_lpar_file) : ( 0, undef );

    opendir( DIR, "$hitachi_dir/$server" ) || error( "can't opendir $hitachi_dir/$server: $! :" . __FILE__ . ":" . __LINE__ ) && next;
    my @host_dir = readdir(DIR);
    closedir(DIR);

    my $print_entry = (
      sub {
        my $menu_type      = shift;
        my $item           = shift;
        my $regex          = shift;
        my @filtered_files = grep /$regex/, @host_dir;

        if ( scalar @filtered_files && $item =~ /(hitachi-lan)|(hitachi-san)/ ) {
          my $total_name = $1 ? "lan-totals" : "san-totals";
          my $item_name  = "hitachi-$total_name";
          print "$menu_type:Hitachi:$server_col:$total_name:$total_name:/lpar2rrd-cgi/detail.sh?host=$server_enc&server=Hitachi&lpar=$total_name&item=$item_name&entitle=0&gui=1&none=none:::B\n";
        }

        foreach my $file (@filtered_files) {
          my $filename = $file;
          $filename =~ s/$regex//;

          if ( !-f "$hitachi_dir/$server/$file" || ( $code && !exists $active_lpars->{$filename} ) ) {
            next;
          }

          $filename =~ s/:/===double-col===/g;
          my $filename_enc = urlencode($filename);

          print "$menu_type:Hitachi:$server_col:$filename_enc:$filename:/lpar2rrd-cgi/detail.sh?host=$server_enc&server=Hitachi&lpar=$filename_enc&item=$item&entitle=0&gui=1&none=none:::B\n";
        }    ## foreach my $h_lpar (@san_dir_all)
      }
    );

    $print_entry->( "L", "lpar",        qr/\.hlm$/ );
    $print_entry->( "N", "hitachi-lan", qr/\.hnm$/ );
    $print_entry->( "Y", "hitachi-san", qr/\.hhm$/ );
  }

  return 0;
}

sub print_hyperv_all {
  my $data_dir = "$wrkdir/windows";
  opendir( DIR, "$data_dir" ) || error( " directory does not exists : $data_dir " . __FILE__ . ":" . __LINE__ ) && return 1;
  my @domain_dir = grep !/^\.\.?$/, readdir(DIR);
  closedir(DIR);

  # prepare text for testing nodes in clusters
  # trick to concatenate files for reading
  @ARGV = <"$wrkdir/windows/cluster_*/node_list.html">;

  #   print "found file \@ARGV ,@ARGV, for windows \n";
  # read all files from @ARGV
  my @node_lists = (<>) if defined $ARGV[0] && $ARGV[0] ne "";

  #   print "@text\n";

  foreach my $domain (@domain_dir) {

    # print "993 \$domain $domain\n";
    if ( !-d "$data_dir/$domain" )          { next; }
    if ( "$domain" !~ /^domain_/ )          { next; }
    if ( "$domain" =~ /^domain_UnDeFiNeD/ ) { next; }    # sometimes is created when error in coming data

    #my $server_col = $server;
    #$server_col =~ s /:/===double-col===/g;
    #my $server_enc = urlencode( $server_col );

    # prepare info about all VMs in this domain
    my $domain_vm_uuid_file = "$data_dir/$domain/hyperv_VMs/vm_uuid_name.txt";
    if ( !-f $domain_vm_uuid_file ) {next}
    ;    # standalone workstationes without VMs

    my @domain_vm_list = ();
    if ( open( FC, "< $domain_vm_uuid_file" ) ) {
      @domain_vm_list = <FC>;
      close(FC);
    }
    else {
      error( "Cannot read $domain_vm_uuid_file: $!" . __FILE__ . ":" . __LINE__ );
    }

    opendir( DIR, "$data_dir/$domain" ) || error( "can't opendir $data_dir/$domain: $! :" . __FILE__ . ":" . __LINE__ ) && next;
    my @server_dir = grep !/^\.\.?$/, readdir(DIR);
    closedir(DIR);

    # print "1005 \@server_dir @server_dir\n";

    foreach my $server (@server_dir) {
      if ( !-d "$data_dir/$domain/$server" ) { next; }
      if ( "$server" eq "hyperv_VMs" )       { next; }
      next if ( !-f "$data_dir/$domain/$server/pool.rrm" );    # strange when not present
      my $file_time = ( stat("$data_dir/$domain/$server/pool.rrm") )[9];
      next if $file_time < $actual_last_30_days_vm;

      # print "1009 found $data_dir/$domain/$server\n";

      my $vm_dir = "$data_dir/$domain/hyperv_VMs";
      opendir( DIR, "$vm_dir" ) || error( " directory does not exists : $vm_dir " . __FILE__ . ":" . __LINE__ ) && next;
      my @all_rrm_files = grep {/\.rrm$/} readdir(DIR);
      closedir(DIR);
      s/$_/$vm_dir\/$_/ for @all_rrm_files;

      my $server_path         = "$data_dir/$domain/$server";
      my $list_server_vm      = "$server_path/VM_hosting.vmh";
      my $vcenter_name_for_VM = "";

      # find out if this node is in cluster
      my $this_cluster = "";
      my @matches      = grep {/$server/} @node_lists;

      # print "@matches\n";
      if ( ( scalar @matches ) > 1 ) {
        error( "server $server is in more ??? clusters @matches  : " . __FILE__ . ":" . __LINE__ );
      }
      if ( ( scalar @matches ) > 0 ) {

        # <TR> <TD><B>MSNET-HVCL</B></TD> <TD align="center">domain_ad.xorux.com</TD> <TD align="center">HVNODE01</TD> <TD al ...
        $this_cluster = $matches[0];
        ( undef, $this_cluster, undef ) = split( "\<B\>", $this_cluster );
        ( $this_cluster, undef ) = split( "\<", $this_cluster );
      }

      #my $my_vcenter_name_file = "$wrkdir/$server/$hmc/my_vcenter_name";
      #if ( -f "$my_vcenter_name_file" ) {
      #  open( FC, "< $my_vcenter_name_file" ) || error( "Cannot read $my_vcenter_name_file: $!" . __FILE__ . ":" . __LINE__ );
      #  my $my_vcenter_name = <FC>;
      #  chomp $my_vcenter_name;
      #  close(FC);
      #  ( undef, $vcenter_name_for_VM, undef ) = split( /\|/, $my_vcenter_name );
      #  if ( !defined $vcenter_name_for_VM ) {
      #    $vcenter_name_for_VM = "";
      #  }
      #} ## end if ( -f "$my_vcenter_name_file")

      my @vm_list_server;    ###### START OR END VM
      if ( -f $list_server_vm && open( FC, "< $list_server_vm" ) ) {
        @vm_list_server = <FC>;
        close(FC);
      }
      else {
        # print "Server $domain/$server may not have any VMs\n";
        next;
      }

      # print "1056 \@all_rrm_files @all_rrm_files\n";
      foreach my $vm_servers (@vm_list_server) {
        chomp $vm_servers;

        # print "1059 \$vm_servers $vm_servers\n";
        if ( $vm_servers =~ /end=\d+$/ ) { next; }
        ( my $uuid_server, my $start, my $end ) = split( /:s/, $vm_servers );
        my $uuid_test = "";
        ($uuid_test) = grep /\Q$uuid_server/, @all_rrm_files;
        next if !defined $uuid_test;
        next if $uuid_test eq "";

        ($uuid_test) = grep /\Q$uuid_server/, @domain_vm_list;
        my $uuid    = "";
        my $vm_name = "";

        #my $linux_yes = "";
        #if ( defined $uuid_test && $uuid_test ne "" ) {
        ( $uuid, $vm_name ) = split( /,/, $uuid_test );

        #  chomp $vm_name;
        #  if (-f "$wrkdir/Linux--unknown/no_hmc/$vm_name/uuid.txt") {
        #    $linux_yes = ":M";
        #  }
        #  else{
        #    chomp $uuid_test;
        #    #print "$uuid_test!!!\n";
        #    my (undef,undef,undef,$uuid_old,$vm_name_a) = split (/,/,$uuid_test);
        #    if (defined $uuid_old && $uuid_old ne '') {
        #      my (undef,undef,undef,$first,$second) = split (/-/,$uuid_old);
        #      my $last_two_uuid = "$first-$second";
        #      my $big = uc($last_two_uuid);
        #      my $test = grep /$big/,@linux_uuid_files;
        #      if ($test == 1) { $linux_yes = ":M"; }
        #    }
        #    #         my ($testV) = grep /\Q$uuid_test/, @linux_uuid_files;
        #  }
        #}

        chomp $start;

        #$hmc =~ s/\:/===double-col===/g;
        $start =~ s/\d//g;

        #if ( $uuid eq $uuid_server ) {
        my $alias_vmware = "";
        my $alias_test   = "";
        my $vm_name_a    = "";
        my $alias_vmw    = "";

        #($alias_test) = grep /\Q$vm_name/, @alias_vmware;
        if ( defined $alias_test && $alias_test ne "" ) {
          ( undef, $vm_name_a, $alias_vmw ) = split( /:/, $alias_test );
          chomp $alias_vmw;
          $alias_vmware = " [$alias_vmw]";
          chomp $alias_vmware;
        }
        my $last_timestamp = ( stat("$data_dir/$domain/hyperv_VMs/$uuid_server.rrm") )[9];
        if ( $last_timestamp > $actual_last_30_days_vm ) {

          # there can be same VM, same name, same uuid, in more vCenters but only one is poweredOn and only this should be printed
          # this means if VM is poweredOff and has actual data file timestamp so this should not be printed
          # actual is not older than 60 minutes
          #(my $info_line) = grep /$uuid/,@vm_list_info;
          #if ( defined $info_line && $info_line =~ "poweredOff" && ($last_timestamp + 3600) > $actual_unix_time ) {
          #  print STDERR "ERROR          : poweredOff & actual data file for $info_line: " . __FILE__ . ":" . __LINE__ . "\n" ;
          #  next;
          #}
          $vm_name =~ s/\:/===double-col===/g;
          my $domain_without = $domain;
          $domain_without =~ s/^domain_//;
          print "L:$domain_without:$server:$uuid_server:$vm_name:/lpar2rrd-cgi/detail.sh?host=$server&server=windows/$domain&lpar=$uuid_server&item=lpar&entitle=0&gui=1&none=none:$this_cluster\::H\n";

          # print "L:$cluster:$server:$uuid_server:$vm_name$alias_vmware:/lpar2rrd-cgi/detail.sh?host=$hmc&server=$server&lpar=$uuid_server&item=lpar&entitle=0&gui=1&none=none::$vcenter_name_for_VM:V$linux_yes\n";
        }

        #} ## end if ( $uuid eq $uuid_server)
      }

      # last;
    }

    # L:cluster_New Cluster:10.22.11.8:500f3258-3b89-fcb5-e6cd-ec0258ee9f69:VyOS:/lpar2rrd-cgi/detail.sh?host=10.22.11.10&server=10.22.11.8&lpar=500f3258-3b89-fcb5-e6cd-ec0258ee9f69&item=lpar&entitle=0&gui=1&none=none::Hosting:V

    # print "$menu_type:Hitachi:$server_col:$total_name:$total_name:/lpar2rrd-cgi/detail.sh?host=$server_enc&server=Hitachi&lpar=$total_name&item=$item_name&entitle=0&gui=1&none=none:::B\n";

    # print "$menu_type:Hitachi:$server_col:$file_name_enc:$file_name:/lpar2rrd-cgi/detail.sh?host=$server_enc&server=Hitachi&lpar=$file_name_enc&item=$item&entitle=0&gui=1&none=none:::B\n";

  }

  return 0;
}

################ look for Linux lpars uuid
sub uuids {
  my @linux_uuid_txt = `ls $no_hmc_dir/*/uuid.txt 2>/dev/null`;    #should be changed to pure Perl
  my $uuid_linux;
  my %uuid_to_name;

  # there can be more directories with same uuid ! but different dir name (small or capital letters or so), save the newest one
  my %file_path = ();

  foreach my $file (@linux_uuid_txt) {
    if ( open( FH, " < $file" ) ) {
      $uuid_linux = <FH>;
      close FH;
      next if !defined $uuid_linux || $uuid_linux eq "";
      chomp( $uuid_linux, $file );
      $uuid_linux = uc $uuid_linux;
      if ( exists $file_path{$uuid_linux} ) {

        # print "1880 compare $file ".$file_path{$uuid_linux}."\n";
        if ( ( stat($file) )[9] <= ( stat( $file_path{$uuid_linux} ) )[9] ) {    # take newer one
          next;
        }
      }
      $file =~ /\/no_hmc\/(.*)\/uuid\.txt$/;
      $uuid_to_name{$uuid_linux} = $1;
      $file_path{$uuid_linux}    = $file;
    }
    else {
      error( "Cannot open $file: $!" . __FILE__ . ":" . __LINE__ );
      next;
    }
  }
  if ( -d $no_hmc_dir && scalar keys %uuid_to_name ) {
    Xorux_lib::write_json( $agents_uuid_file, \%uuid_to_name );
  }
  return 0;
}

sub reduce_double_hmc {
  my $server = shift;
  my $lpar   = shift;

}
