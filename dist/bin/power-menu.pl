# power-menu.pl
use 5.008_008;
$| = 1;

use strict;
use warnings;

use JSON;
use Data::Dumper;
use HostCfg;
use PowerDataWrapper;
use File::Copy;
use File::Path;

use Xorux_lib;

# you can try it from cmd line like:
# . etc/lpar2rrd.cfg ; $PERL bin/power-menu.pl

defined $ENV{INPUTDIR} || Xorux_lib::error( "INPUTDIR undefined, config etc/lpar2rrd.cfg probably has not been loaded " . __FILE__ . ":" . __LINE__ ) && exit 1;
print "---------- power-menu.pl start\n";
my $inputdir = $ENV{INPUTDIR};
my $webdir   = $ENV{WEBDIR};
my $cgidir   = 'lpar2rrd-cgi';
my $rrdtool  = $ENV{RRDTOOL};
use RRDp;
RRDp::start "$rrdtool";
my $tmpdir = "$inputdir/tmp";

if ( defined $ENV{TMPDIR_LPAR} ) {
  $tmpdir = $ENV{TMPDIR_LPAR};
}
my $ENTITLEMENT_LESS     = $ENV{ENTITLEMENT_LESS};
my $hmc                  = $ARGV[0];
my $managedname          = $ARGV[1];
my $rest_api             = 0;
my $ivm                  = $ARGV[3];
my $hmc_space            = $hmc;
my $managedname_url_hash = $managedname;

#$managedname_url_hash    =~s/([^a-zA-Z0-9_.!:~*()'\''-])/sprintf("%%%02X", ord($1))/ge;
#$managedname_url_hash    =~s/#/\%23/ge;

my $hmc_url_hash = $hmc;

#$hmc_url_hash    =~s/([^a-zA-Z0-9_.!:~*()'\''-])/sprintf("%%%02X", ord($1))/ge;
#$hmc_url_hash    =~s/#/\%23/ge;

my $type_server       = "P";
my $type_server_power = "P";
my $power             = 1;

my $gmenu_created = 0;    # global Power  menu is created only once
my $vmenu_created = 0;    # global VMWare menu is created only once
my $smenu_created = 0;    # super menu is created only once -favorites and customs groups

my $type_amenu    = "A";      # VMWARE CLUSTER menu
my $type_bmenu    = "B";      # VMWARE RESOURCEPOOL menu
my $type_cmenu    = "C";      # custom group menu
my $type_fmenu    = "F";      # favourites menu
my $type_gmenu    = "G";      # global menu
my $type_hmenu    = "H";      # HMC menu
my $type_zmenu    = "Z";      # datastore menu
my $type_smenu    = "S";      # server menu
my $type_dmenu    = "D";      # server menu - already deleted (non active) servers
my $type_tmenu    = "T";      # tail menu
my $type_vmenu    = "V";      # VMWARE total menu
my $type_qmenu    = "Q";      # tool version
my $type_hdt_menu = "HDT";    # hyperv disk global
my $type_hdi_menu = "HDI";    # hyperv disk item

my $type_version = "O";       # free(open)/full version (1/0)
my $type_ent     = "E";       # ENTITLEMENT_LESS for DTE

my $type_server_vmware     = "V";    # vmware
my $type_server_kvm        = "K";    # KVM
my $type_server_hyperv     = "H";    # Hyper-V
my $type_server_hitachi    = "B";    # Hitachi blade
my $type_server_xenserver  = "X";    # XenServer
my $type_server_ovirt      = "O";    # oVirt
my $type_server_oracle     = "Q";    # OracleDB
my $type_server_postgres   = "T";    # PostgreSQL
my $type_server_sqlserver  = "D";    # SQL Server
my $type_server_db2        = "F";    # DB2
my $type_server_oraclevm   = "U";    # OracleVM
my $type_server_nutanix    = "N";    # Nutanix
my $type_server_aws        = "A";    # AWS
my $type_server_gcloud     = "G";    # GCloud
my $type_server_azure      = "Z";    # Azure
my $type_server_kubernetes = "K";    # Kubernetes
my $type_server_openshift  = "R";    # RedHat Openshift

my @menu_lines = ();                                   # appends lines during script
my $hmcs       = `\$PERL $inputdir/bin/hmc_list.pl`;
my @hmcs       = split( " ", $hmcs );

# print "\@hmcs @hmcs\n\n \$hmcs $hmcs\n\n";
opendir( DIR, "$inputdir/data" ) || error( " directory does not exists : $inputdir/data" . __FILE__ . ":" . __LINE__ ) && exit 1;
my @server_all = grep !/^\.\.?$/, readdir(DIR);
closedir(DIR);

@server_all = grep !/XEN_iostats/, @server_all;
@server_all = grep !/_DB/,         @server_all;
@server_all = grep !/oVirt/,       @server_all;
@server_all = grep !/vm_/,         @server_all;

my @servers;
my $result;
for my $s (@server_all) {
  if ( !-d "$inputdir/data/$s" || -l "$inputdir/data/$s" ) {
    next;
  }
  push @servers, $s;
}

my $IVM  = 0;
my $SDMC = 0;
foreach my $ms (@servers) {
  $result = "";    #clean in the beginning of cycle
  print "power-menu.pl working for managed system: $ms\n";

  #print "Hitachi? $ms\n";
  if ( $ms =~ m/^hyperv_VMs/
    || $ms =~ m/^XEN$/
    || $ms =~ m/^XEN_VMs$/
    || $ms =~ m/^XEN_iostats$/
    || $ms =~ m/^Docker$/
    || $ms =~ m/^NUTANIX$/
    || $ms =~ m/^AWS$/
    || $ms =~ m/^GCloud$/
    || $ms =~ m/^Cloudstack$/
    || $ms =~ m/^Azure$/
    || $ms =~ m/^Kubernetes$/
    || $ms =~ m/^oVirt$/
    || $ms =~ m/^Openshift$/
    || $ms =~ m/^OracleDB$/
    || $ms =~ m/^OracleVM$/
    || $ms =~ m/^PostgreSQL$/
    || $ms =~ m/^SQLServer$/
    || $ms =~ m/^DB2$/
    || $ms =~ m/^Proxmox$/
    || $ms =~ m/^FusionCompute$/
    || $ms =~ m/^Solaris$/
    || $ms =~ m/^Solaris--unknown$/
    || $ms =~ m/^Linux$/
    || $ms =~ m/^Linux--unknown$/
    || $ms =~ m/^\-\-HMC/
    || $ms =~ m/^vmware_/ )
  {

    #exclude managedsystems
    print "power-menu.pl skip $ms, do only power, hitachi, windows\n";
    next;
  }
  my $vmw_check = 0;
  my @is_vmware = <$ENV{INPUTDIR}/data/$ms/*\/vmware.txt>;
  foreach (@is_vmware) {
    if ( -e "$_" ) {
      $vmw_check = 1;
      last;
    }
  }
  if ($vmw_check) {
    print "Skip $ms, it is a vmware item\n";
    next;
  }

  #print "power-menu.pl skip 1 $ms : " . (defined $ENV{MANAGED_SYSTEMS_EXCLUDE}) . "\n\n";
  #print "power-menu.pl skip 2 $ms : " . ($ENV{MANAGED_SYSTEMS_EXCLUDE} =~ /$ms/) . "\n$ms  =~ m/$ENV{MANAGED_SYSTEMS_EXCLUDE}/\n";
  #print "power-menu.pl skip 3 $ms : " . ($ENV{MANAGED_SYSTEMS_EXCLUDE} ne "") . "\n\n";

  if ( defined $ENV{MANAGED_SYSTEMS_EXCLUDE} && $ENV{MANAGED_SYSTEMS_EXCLUDE} =~ /$ms/ && $ENV{MANAGED_SYSTEMS_EXCLUDE} ne "" ) {
    print "Skip $ms due to exlude $ENV{MANAGED_SYSTEMS_EXCLUDE}\n\n";
    next;
  }
  if ( $ms =~ m/^Hitachi/ ) {
    $type_server = "B";
    opendir( DIR, "$inputdir/data/$ms/" );
    my @hitachi_hmcs = grep !/^\.\.?$/, readdir(DIR);
    closedir(DIR);
    foreach my $hitachi_hmc (@hitachi_hmcs) {
      my $hitachi_server     = "$inputdir/data/$ms/$hitachi_hmc";
      my $hitachi_server_url = $hitachi_server;
      my $hitachi_hmc_url    = $hitachi_hmc;
      $hitachi_server_url =~ s/([^a-zA-Z0-9_.!:~*()'\''-])/sprintf("%%%02X", ord($1))/ge;
      $hitachi_hmc_url    =~ s/([^a-zA-Z0-9_.!:~*()'\''-])/sprintf("%%%02X", ord($1))/ge;
      if ( !-e "$hitachi_server/SYS-CPU.hrm" ) {
        next;
      }

      my $last_time = rrd_last("$hitachi_server/SYS-CPU.hrm");
      menu( $type_smenu, "Hitachi", $hitachi_hmc, "CPU", "CPU pool", "/lpar2rrd-cgi/detail.sh?host=$hitachi_hmc_url&server=Hitachi&lpar=pool&item=pool&entitle=0&gui=1&none=none",    "", $last_time );
      menu( $type_smenu, "Hitachi", $hitachi_hmc, "MEM", "MEM",      "/lpar2rrd-cgi/detail.sh?host=$hitachi_hmc_url&server=Hitachi&lpar=mem&item=memalloc&entitle=0&gui=1&none=none", "", $last_time );
    }
    next;
  }

  #windows
  if ( $ms =~ m/^windows/ ) {
    next;
    $type_server = "H";
    my $type_server = "hyperv";
    print "\nwindows start  : " . localtime() . "\n";
    my $win_uuid_file = "$inputdir/tmp/win_uuid.txt";
    if ( open( my $fh, ">", $win_uuid_file ) ) {
      print $fh "";
      close($fh);
    }
    else {
      error( " cannot write to file : $win_uuid_file " . __FILE__ . ":" . __LINE__ );
    }
    my $win_host_uuid_file = "$inputdir/tmp/win_host_uuid.txt";
    if ( open( my $fh, ">", $win_host_uuid_file ) ) {
      print $fh "";
      close($fh);
    }
    else {
      error( " cannot write to file : $win_host_uuid_file " . __FILE__ . ":" . __LINE__ );
    }
    my $win_host_uuid_file_json = "$inputdir/tmp/win_host_uuid.json";
    if ( open( my $fh, ">", $win_host_uuid_file_json ) ) {
      print $fh "";
      close($fh);
    }
    else {
      error( " cannot write to file : $win_host_uuid_file_json " . __FILE__ . ":" . __LINE__ );
    }

    #    Xorux_lib::write_json( "$win_host_uuid_file_json", \%host_uuid_json )

    #hyperv global menu
    menu( $type_gmenu, "heatmaphv", "Heatmap", "heatmap-windows.html" );

    opendir( DIR, "$inputdir/data/$ms/" );
    my @dir1s = grep !/^\.\.?$/, readdir(DIR);
    closedir(DIR);
    my %host_uuid_json = ();

    foreach my $dir1 (@dir1s) {
      if ( $dir1 =~ m/cluster_/ ) {

        # test node_list.html, skip if old
        my $server_data_file = "$inputdir/data/$ms/$dir1/node_list.html";
        my $file_diff        = Xorux_lib::file_time_diff($server_data_file);
        if ( $file_diff > 0 && $file_diff > 86400 ) {
          my $diff_days = int( $file_diff / 86400 );
          if ( $diff_days > 10 ) {
            print "testing server : $server_data_file is older than $diff_days days, skipping\n";
            next;
          }
          print "testing server : $server_data_file is older than $diff_days days, NOT skipping\n";
        }
        my $dir1_par = $dir1;
        $dir1_par =~ s/cluster_//g;
        menu( "A", "", $dir1_par, "Totals", "/$cgidir/detail.sh?host=$dir1&server=windows&lpar=nope&item=cluster&entitle=0&gui=1&none=none" );

        #cluster_s2d/volumes
        my $voldir = "$inputdir/data/$ms/$dir1/volumes";
        if ( -d $voldir ) {
          opendir( my $VOL_DIR, $voldir );
          my @volumes = readdir($VOL_DIR);
          closedir($VOL_DIR);

          @volumes = grep {/^vol_.+\.rrm$/} @volumes;

          foreach my $volume (@volumes) {
            $volume =~ s/vol_//g;
            ( $volume, undef ) = split /[.]/, $volume;

            #print "$volume\n";
            menu( "HVOL", "", $dir1_par, $volume, $volume, "/$cgidir/detail.sh?host=$dir1&server=windows&lpar=$volume&item=s2dvolume&entitle=0&gui=1&none=none", "$dir1_par" );
          }
        }

        #cluster_s2d/pdisks
        my $pddir = "$inputdir/data/$ms/$dir1/pdisks";
        if ( -d $pddir ) {
          opendir( my $PD_DIR, $pddir );
          my @pdisks = readdir($PD_DIR);
          closedir($PD_DIR);

          @pdisks = grep {/^pd_.+\.rrm$/} @pdisks;

          foreach my $pdisk (@pdisks) {
            $pdisk =~ s/pd_//g;
            ( $pdisk, undef ) = split /[.]/, $pdisk;

            #print "$pdisk\n";
            menu( "HPD", "", $dir1_par, $pdisk, $pdisk, "/$cgidir/detail.sh?host=$dir1&server=windows&lpar=$pdisk&item=physdisk&entitle=0&gui=1&none=none", "$dir1_par" );
          }
        }
        next;
      }
      if ( $dir1 =~ m/^domain_UnDeFiNeD_/ ) {
        next;
      }
      my @server_name_list;
      opendir( DIR, "$inputdir/data/$ms/$dir1/" );
      @server_name_list = grep !/^\.\.?$/, readdir(DIR);
      closedir(DIR);
      for my $server_name (@server_name_list) {
        my $server_name_space = $server_name;
        $server_name_space =~ s/=====space=====/ /g;
        if ( $server_name_space =~ m/hyperv_VMs$/ ) {
          next;
        }
        my $server_data_file = "$inputdir/data/$ms/$dir1/$server_name/pool.rrm";
        my $domain_id        = $dir1;
        my $domain_id_par    = $domain_id;
        $domain_id_par =~ s/domain_//g;
        my $server_id = $server_name;
        if ( !-e $server_data_file ) {
          print "testing server : $domain_id_par $server_id has no data, skipping\n";
          next;
        }

        my $file_diff = Xorux_lib::file_time_diff($server_data_file);
        if ( $file_diff > 0 && $file_diff > 86400 ) {
          my $diff_days = int( $file_diff / 86400 );
          if ( $diff_days > 10 ) {
            print "testing server : $domain_id_par $server_id is older than $diff_days days, skipping\n";
            next;
          }
          print "testing server : $domain_id_par $server_id is older than $diff_days days, NOT skipping\n";
        }
        print "testing server : $domain_id_par $server_id\n";

        #save IdenfityingNumber for all win servers, good for mapping VMWARE and ?
        my $server_config_file = "$inputdir/data/$ms/$dir1/$server_name/server.html";
        my $my_line            = "";
        if ( open( my $s_config_file, "<", "$server_config_file" ) ) {
          my @server_config_lines = <$s_config_file>;
          close($s_config_file);
          $my_line = $server_config_lines[-2];
        }
        else {
          error( "can't open $server_config_file: $! :" . __FILE__ . ":" . __LINE__ );
        }

        # print "317 \$my_line $my_line\n";
        if ( defined $my_line && $my_line ne "" ) {
          if ( $my_line =~ m/VMware/ ) {
            my $s = $my_line;
            $s =~ s/.*VMware-//;
            $s =~ s/\s//g;
            my $a        = substr( $s, 0, 8 ) . "-" . substr( $s, 8, 4 ) . "-" . substr( $s, 12, 9 ) . "-" . substr( $s, 21, 12 );
            my $win_uuid = $a;
            if ( open( my $fh, ">>", $win_uuid_file ) ) {    # || warn "Cannot open file $win_uuid_file " . __FILE__ . ":" . __LINE__ . "\n";
              print $fh "$win_uuid $server_data_file\n";
              close($fh);
            }
            else {
              error( "Cannot open file $win_uuid_file " . __FILE__ . ":" . __LINE__ );
            }
          }
          else {
            # <TR> <TD><B>OVIRT-WIN1</B></TD> <TD align="center">Microsoft Windows Server 2019 Standard</TD> <TD align="center">10.0.17763</TD> <TD align="center">20221018120222+120<BR>0 days 01:17:40</TD> <TD align="center">Notification</TD> <TD align="center">2</TD> <TD align="center">2</TD> <TD align="center">OK</TD> <TD align="center">0fc80c42-0473-d0fc-af7a-8230a167ee9d</TD></TR>
            ( undef, undef, undef, undef, undef, undef, undef, undef, my $win_uuid ) = split "center\"\>", $my_line;
            $win_uuid =~ s/\<.*//;
            chomp $win_uuid;
            if ( open( my $fh, ">>", $win_uuid_file ) ) {    # || warn "Cannot open file $win_uuid_file " . __FILE__ . ":" . __LINE__ . "\n";
              print $fh "$win_uuid $server_data_file\n";
              close($fh);
            }
            else {
              error( "Cannot open file $win_uuid_file " . __FILE__ . ":" . __LINE__ );
            }
          }
        }

        #save vmware uuid for windows server, good for mapping oVirt and ?
        $server_config_file = "$inputdir/data/$ms/$dir1/$server_name/host.cfg";
        $my_line            = "";
        if ( open( my $s_config_file, "<", "$server_config_file" ) ) {
          my @server_config_lines = <$s_config_file>;
          close($s_config_file);
          $my_line = $server_config_lines[3];
        }
        else {
          error( "can't open $server_config_file: $! :" . __FILE__ . ":" . __LINE__ );
        }

        # print "363 \$my_line $my_line\n";
        if ( defined $my_line && $my_line ne "" ) {
          chomp $my_line;
          $host_uuid_json{$my_line} = $server_data_file;
          if ( open( my $fh, ">>", $win_host_uuid_file ) ) {    # || warn "Cannot open file $win_host_uuid_file " . __FILE__ . ":" . __LINE__ . "\n";
            print $fh "$my_line $server_data_file\n";
            close($fh);
          }
          else {
            error( "Cannot open file $win_host_uuid_file " . __FILE__ . ":" . __LINE__ );
          }
        }

        my $domain_id_url = $domain_id;
        my $server_id_url = $server_id;
        $domain_id_url =~ s/([^a-zA-Z0-9_.!:~*()'\''-])/sprintf("%%%02X", ord($1))/ge;
        $server_id_url =~ s/([^a-zA-Z0-9_.!:~*()'\''-])/sprintf("%%%02X", ord($1))/ge;
        $domain_id_url = "windows/$domain_id_url";
        my $last_time = 0;
        menu( $type_smenu, $domain_id_par, $server_id, "Totals", "Totals", "/lpar2rrd-cgi/detail.sh?host=$server_id_url&server=$domain_id_url&lpar=pool&item=pool&entitle=0&gui=1&none=none", "", $last_time );

        #working with Local_Fixed_Disk
        opendir( DIR, "$inputdir/data/$ms/$dir1/$server_name_space" ) || warn("no dir $server_name_space");
        my @volume_list = grep ( /Local_Fixed_Disk_/, readdir(DIR) );
        closedir(DIR);
        foreach my $csi (@volume_list) {
          my $cso = $csi;
          $cso =~ s/Local_Fixed_Disk_//g;

          my $cs = $cso;
          $cs =~ s/\.rrm//g;

          my $cs_space = $cs;
          $cs_space =~ s/=====space=====/ /g;

          my $cs_id = basename($cs_space);

          my $cs_id_url = $cs_id;
          $cs_id_url =~ s/([^a-zA-Z0-9_.!:~*()'\''-])/sprintf("%%%02X", ord($1))/ge;
          menu( $type_hdi_menu, "$domain_id_par", "$server_id", "$cs_id", "$cs_id_url", "/lpar2rrd-cgi/detail.sh?host=$server_id_url&server=$domain_id_url&lpar=$cs_id&item=lfd&entitle=0&gui=1&none=none", "", $last_time );
        }

        #working with Cluster_Storage
        opendir( DIR, "$inputdir/data/$ms/$dir1/$server_name_space" ) || warn("no dir $server_name_space");
        my @volume_list2 = grep( /Cluster_Storage_/, readdir(DIR) );
        closedir(DIR);
        foreach my $csi (@volume_list2) {
          my $cso = $csi;
          $cso =~ s/Cluster_Storage_//g;

          my $cs = $cso;
          $cs =~ s/\.rrm//g;

          my $cs_space = $cs;
          $cs_space =~ s/=====space=====/ /g;

          my $cs_id = basename($cs_space);

          my $cs_id_url = $cs_id;
          $cs_id_url =~ s/([^a-zA-Z0-9_.!:~*()'\''-])/sprintf("%%%02X", ord($1))/ge;
          menu( $type_hdi_menu, "$domain_id_par", "$server_id", "$cs_id", "$cs_id_url", "/lpar2rrd-cgi/detail.sh?host=$server_id_url&server=$domain_id_url&lpar=$cs_id&item=csv&entitle=0&gui=1&none=none", "", $last_time );
        }
      }
    }
    if (%host_uuid_json) {
      Xorux_lib::write_json( "$win_host_uuid_file_json", \%host_uuid_json );
    }

    print "windows finish : " . localtime() . "\n\n";
    next;
  }
  #
  ## end of windows section
  #

  opendir( DIR, "$inputdir/data/$ms" ) || error( "can't opendir $inputdir/data/$ms: $! :" . __FILE__ . ":" . __LINE__ ) && next;
  my @hmcdir_all = grep !/^\.\.?$/, readdir(DIR);
  closedir(DIR);

  @hmcs = @hmcdir_all;
  my $newest_config_cfg = "";
  my $newest_ts         = -1;
  my $power_hmc_server_done;
  foreach my $h (@hmcs) {

    my @config_cfg_files = <"$inputdir/data/$managedname/*\/config.cfg">;

    foreach my $file (@config_cfg_files) {
      my $file_time_diff = Xorux_lib::file_time_diff("$file");
      if ( $newest_ts == -1 || $newest_ts >= $file_time_diff ) {
        $newest_config_cfg = $file;
        $newest_ts         = $file_time_diff;
      }
    }

    my @ret = split( '/', $newest_config_cfg );
    $hmc = $ret[-2] if ( defined $ret[-2] );

    print "power-menu.pl debug ms: $ms @ hmc:$h\n";
    my $fn           = "$inputdir/data/$ms/$h/pool.rrm";
    my $pool_rrm_age = Xorux_lib::file_time_diff($fn);
    my $dir2         = "$inputdir/$ms/$h";

    # Do not skip the old but put in in menu as D:...
    #if (-e $fn && $pool_rrm_age > 604800 ){
    #  print STDERR "Skip $fn because it is $pool_rrm_age seconds old\n";
    #  next;
    #}
    my $dir2_space = $dir2;
    $dir2_space =~ s/=====space=====/ /g;
    $hmc = basename($dir2_space);
    my $server_menu = $type_smenu;
    my $dead        = is_alive( $hmc, $ms );
    if ($dead) {
      $server_menu = $type_dmenu;    #dead ms
    }
    if ( !-d "$webdir/$hmc" ) {
      mkdir("$webdir/$hmc");
    }
    if ( !-d "$webdir/$hmc/$ms" ) {
      mkdir("$webdir/$hmc/$ms");
    }
    if ( -e "$inputdir/data/$ms/$hmc/config.cfg" ) {

      #copy ("$webdir/$hmc/$ms/config.html", "$inputdir/data/$ms/$hmc/config.cfg");
      copy( "$inputdir/data/$ms/$hmc/config.cfg", "$webdir/$hmc/$ms/config.html" );
    }

    #check ivm
    $IVM = 1 if ( -e "$inputdir/data/$ms/$hmc/IVM" );

    #check sdmc
    $SDMC = 1 if ( -e "$inputdir/data/$ms/$hmc/SDMC" );

    $type_server = $type_server_power;
    if ( -e "$inputdir/data/$ms/$hmc/vmware.txt" || -e "$inputdir/data/$ms/vmware.txt" ) {
      $type_server = $type_server_vmware;
    }
    if ( -e "$inputdir/data/$ms/$hmc/kvm.txt" || -e "$inputdir/data/$ms/kvm.txt" ) {
      $type_server = $type_server_kvm;
    }

    #find sample rate used. 3600 or less
    my $size     = -1;
    my $tmp_size = 0;
    $tmp_size = ( stat "$inputdir/data/$ms/$hmc/pool.rrh" )[7] if ( -e "$inputdir/data/$ms/$hmc/pool.rrh" );
    if ( $tmp_size > 0 ) { $size = $tmp_size; }
    my $rr;
    if ( $size == 0 ) {

      #remove pool.rrh if file size is 0. It comes from old versions < 4.63
      unlink("$inputdir/data/$ms/$hmc/pool.rrh");
    }
    if ( -e "$inputdir/data/$ms/$hmc/pool.rrm" || -e "$inputdir/data/$ms/$hmc/pool.rrh" ) {
      my $rrm_stat = Xorux_lib::file_time_diff("$inputdir/data/$ms/$hmc/pool.rrm");
      my $rrh_stat = Xorux_lib::file_time_diff("$inputdir/data/$ms/$hmc/pool.rrh");
      $rr = "rrm";
      $rr = "rrh" if ( $rrh_stat > $rrm_stat );
    }

    #copy servers log
    if ( $IVM == 0 ) {
      if ( !-e "$inputdir/data/$ms/$hmc/vmware.txt" && !-e "$inputdir/data/$ms/$hmc/hyperv.txt" ) {
        if ( -e "$inputdir/data/$ms/$hmc/gui-change-state.txt" ) {

          #copy ("$webdir/$hmc/$ms/gui-change-state.html", "$inputdir/data/$ms/$hmc/gui-change-state.txt");
          copy( "$webdir/$hmc/$ms/gui-change-state.html", "$inputdir/data/$ms/$hmc/gui-change-state.txt" );
          if ( $ENV{DEBUG} ) { print "copy change sta: $hmc:$ms\n" }
        }
        if ( -e "$inputdir/data/$ms/$hmc/gui-change-config.txt" ) {

          #copy ("$webdir/$hmc/$ms/gui-change-config.html", "$inputdir/data/$ms/$hmc/gui-change-config.txt");
          copy( "$inputdir/data/$ms/$hmc/gui-change-config.txt", "$webdir/$hmc/$ms/gui-change-config.html" );
          if ( $ENV{DEBUG} ) { print "copy change cfg: $hmc:$ms\n" }
        }
      }
    }

    if ( $gmenu_created == 0 && $type_server eq $type_server_power ) {

      #super menu
      #if ($smenu_created == 0){
      #  my $favourite_file = Xorux_lib::file_time_diff("$inputdir/etc/favourites.cfg");
      #  my $f_grep = `grep -v "^#" $inputdir/etc/favourites.cfg 2>/dev/null| wc -l`;
      #  if ($favourite_file && $f_grep > 0){
      #    menu ("$type_gmenu", "fav", "FAVOURITES", "favourites/fav_first/fav_first/gui-index.html");
      #  }
      #}

      #power global menu
      menu( $type_gmenu,   "cgroups",     "CUSTOM GROUPS",                  "custom/group_first/gui-index.html",                     "", "", "", "", "" );
      menu( "$type_gmenu", "heatmaplpar", "Heatmap",                        "/lpar2rrd-cgi/heatmap-xormon.sh?platform=power&tabs=1", "", "", "", "", "" );
      menu( "$type_gmenu", "ghreports",   "Historical reports",             "/lpar2rrd-cgi/histrep.sh?mode=global",                  "", "", "", "", "" );
      menu( $type_gmenu,   "advisor",     "Resource Configuration Advisor", "gui-cpu_max_check.html",                                "", "", "", "", "" );
      menu( $type_gmenu,   "estimator",   "CPU Workload Estimator",         "cpu_workload_estimator.html",                           "", "", "", "", "" );
      menu( "$type_gmenu", "alert",       "Alerting",                       "/lpar2rrd-cgi/alcfg.sh?cmd=form",                       "", "", "", "", "" );

      menu( "$type_gmenu", "gcfg", "Configuration", "/$cgidir/detail.sh?host=&server=&lpar=cod&item=servers&entitle=0&none=none", "", "", "", "", "" );

      #if [ $xormon -eq 0 ]; then
      menu( "$type_gmenu", "gtop10", "LPAR TOP", "/$cgidir/detail.sh?host=&server=&lpar=cod&item=topten&entitle=0&none=none", "", "", "", "", "" );

      #fi
      menu( "$type_gmenu", "nmon", "NMON file grapher", "nmonfile.html", "", "", "", "", "" );

      menu( "$type_gmenu", "rmc", "RMC check", "gui-rmc.html", "", "", "", "", "" );

      #menu( "$type_gmenu", "power-total", "Total", "/$cgidir/detail.sh?platform=Power&item=power-total","","","","","");

      menu( "$type_gmenu", "overview", "Overview", "overview_power.html", "", "", "", "", "" );

      menu( "$type_gmenu", "hmctot", "HMC totals", "", "", "", "", "", "" );

      if ( $ENV{KEEP_VIRTUAL} ) {    # accounting for DHL
        menu( "$type_gmenu", "accounting", "Accounting", "/$cgidir/virtual.sh?sort=server&gui=1", "", "", "", "", "" );
      }

      $gmenu_created = 1             # it will not print global menu items
    }

=begin comment2
    if [ $gmenu_created -eq 0 -a "$type_server" = "$type_server_power" ]; then
      # super menu
      if [ $smenu_created -eq 0 ]; then
        if [ `grep -v "^#" $INPUTDIR/etc/favourites.cfg 2>/dev/null| wc -l` -gt 0 ]; then
          menu "$type_gmenu" "fav" "FAVOURITES" "favourites/$fav_first/$fav_first/gui-index.html"
        fi
        smenu_created=1 # only once
      fi

      # here create Power global menu
      menu "$type_gmenu" "cgroups" "CUSTOM GROUPS" "custom/$group_first/gui-index.html"
      menu "$type_gmenu" "estimator" "CPU Workload Estimator" "cpu_workload_estimator.html"

      if [ ! $ENTITLEMENT_LESS -eq 1 ]; then
        menu "$type_gmenu" "advisor" "Resource Configuration Advisor" "gui-cpu_max_check.html"
      fi
      menu "$type_gmenu" "heatmaplpar" "Heatmap" "heatmap-power.html"
      menu "$type_gmenu" "alert" "Alerting" "/lpar2rrd-cgi/alcfg.sh?cmd=form"

      #if [ $xormon -eq 0 ]; then
        menu "$type_gmenu" "ghreports" "Historical reports" "/lpar2rrd-cgi/histrep.sh?mode=global"
      #fi
      menu "$type_gmenu" "gcfg" "Configuration" "/$CGI_DIR/detail.sh?host=&server=&lpar=cod&item=servers&entitle=0&none=none"
      #if [ $xormon -eq 0 ]; then
        menu "$type_gmenu" "gtop10" "LPAR TOP" "/$CGI_DIR/detail.sh?host=&server=&lpar=cod&item=topten&entitle=0&none=none"
      #fi
      menu "$type_gmenu" "nmon" "NMON file grapher" "nmonfile.html"

      if [ ! $ENTITLEMENT_LESS -eq 1 ]; then
        menu "$type_gmenu" "rmc" "RMC check" "gui-rmc.html"
      fi

      menu "$type_gmenu" "hmctot" "HMC totals" ""

      if [ $KEEP_VIRTUAL -eq 1 ]; then # accounting for DHL
        menu "$type_gmenu" "accounting" "Accounting" "/$CGI_DIR/virtual.sh?sort=server&gui=1"
      fi

      gmenu_created=1 # it will not print global menu items
    fi
=cut

    # Add others managed systems into the menu
    #my @hmcs_new = "";
    #my @config_cfg_files = <"$inputdir/data/$managedname/*\/config.cfg">;

    #my $newest_config_cfg = "";
    #my $newest_ts = -1;

    #foreach my $file ( @config_cfg_files ) {
    #  my $file_time_diff = Xorux_lib::file_time_diff("$file");
    #  if ($newest_ts == -1 || $newest_ts >= $file_time_diff){
    #    $newest_config_cfg = $file;
    #    $newest_ts = $file_time_diff;
    #  }
    #}

    #my @ret = split ('/', $newest_config_cfg);
    #print STDERR Dumper \@ret;

    $managedname          = $ms;
    $managedname_url_hash = $managedname;
    $managedname_url_hash = $managedname;
    $hmc                  = $h;

    #$hmc                  = $ret[-2] if (defined $ret[-2]);
    $hmc          = "hmc1" if ( $ENV{DEMO} );
    $hmc_space    = $hmc;
    $hmc_url_hash = $hmc;
    $managedname_url_hash =~ s/([^a-zA-Z0-9_.!:~*()'\''-])/sprintf("%%%02X", ord($1))/ge;
    $managedname_url_hash =~ s/#/\%23/ge;
    $hmc_url_hash         =~ s/([^a-zA-Z0-9_.!:~*()'\''-])/sprintf("%%%02X", ord($1))/ge;
    $hmc_url_hash         =~ s/#/\%23/ge;

    if ( !defined $power_hmc_server_done->{$hmc}{$managedname} ) {
      print "power-menu.pl ppm start $managedname @@ $hmc: $result\n";
      $result = print_power_menu() if ( !defined $power_hmc_server_done->{$hmc}{$managedname} );
      $power_hmc_server_done->{$hmc}{$managedname} = 1;
      print "power-menu.pl ppm   end $managedname @@ $hmc: $result\n";
    }
  }
}

#print Dumper \@menu_lines;

#print "@menu_lines\n";

# save menu

my $file_menu = "$tmpdir/menu_power_pl.txt-tmp";
if ( open( MWP, ">$file_menu" ) ) {
  print MWP join( "", @menu_lines );
  close MWP;
}
else {
  error( " cannot write menu to file : $file_menu " . __FILE__ . ":" . __LINE__ );
}

`grep -v '^\$' $tmpdir/menu_power_pl.txt-tmp > $tmpdir/menu_power_pl.txt`;

#`cat $tmpdir/menu_power_pl.txt >> $tmpdir/menu.txt`;

print "Exit power-menu.pl " . localtime() . " \n";

if ( $result eq "" ) {
  exit(0);
}
else {
  exit(1);
}

sub print_power_menu {

  # power & not vmware ESXi & not hyperv servers
  #if [ `echo "$managedname"|egrep -- "--unknown$"|wc -l` -eq 0  -a `echo "$hmc"|egrep "^no_hmc$"|wc -l` -eq 0 ]; then
  if ( $managedname !~ m/--unknown$/ ) {

    #print "debug xx 1: $managedname @ $hmc\n";

    # exclude that for non HMC based lpars
    if ( -e "$inputdir/data/$managedname/$hmc/vmware.txt" || -e "$inputdir/data/$managedname/$hmc/hyperv.txt" ) {

      #print "debug xx 2: $managedname @ $hmc\n";
      return 2;
    }

    # exclude that for old vmware esxi servers
    if ( -e "$inputdir/data/$managedname/$hmc/VM_hosting.vmh" ) {

      #print "debug xx 2: $managedname @ $hmc\n";
      return 2;
    }
    if ( -e "$inputdir/data/$managedname/$hmc/pool.rrm" || -e "$inputdir/data/$managedname/$hmc/pool.rrh" ) {

      #print "debug xx 3: $managedname @ $hmc\n";
      $rest_api = is_host_rest($hmc);

      # exclude servers where is not pool.rrm/h --> but include their lpars below
      # CPU pool
      my $last_time = 0;
      if ( -e "$inputdir/data/$managedname/$hmc/pool.rrh" ) {
        $last_time = ( stat("$inputdir/data/$managedname/$hmc/pool.rrh") )[9];
      }
      if ( -e "$inputdir/data/$managedname/$hmc/pool.rrm" ) {
        $last_time = ( stat("$inputdir/data/$managedname/$hmc/pool.rrm") )[9];
      }

      my $server_menu = "S";
      $server_menu = "D" if ( ( time - $last_time ) >= 86400 );

      # do not use overview @ server level, merge with current view as overview
      #menu("$server_menu", "$hmc_space", "$managedname", "overview-server", "Overview", "/$cgidir/detail.sh?host=$hmc_url_hash&server=$managedname_url_hash&lpar=power-overview-server&item=power-overview-server&entitle=&gui=1&none=none", "", $last_time);

      #add server cpu pool
      if ( !-e "$inputdir/data/$managedname/$hmc/vmware.txt" && !-e "$inputdir/data/$managedname/$hmc/hyperv.txt" ) {

        #print "debug xx 4: $managedname @ $hmc\n";
        menu( "$server_menu", "$hmc_space", "$managedname", "CPUpool-pool", "CPU", "/$cgidir/detail.sh?host=$hmc_url_hash&server=$managedname_url_hash&lpar=pool&item=pool&entitle=&gui=1&none=none", "", $last_time );
      }

      open( my $cpu_pools_mapping, "<", "$inputdir/data/$managedname/$hmc/cpu-pools-mapping.txt" );
      my @cpu_pools_mapping_lines = <$cpu_pools_mapping>;
      close($cpu_pools_mapping);
      my $mapping;
      foreach my $item (@cpu_pools_mapping_lines) {

        #print "debug xx 5: $managedname @ $hmc, $item\n";
        chomp($item);
        ( my $pool_id, my $alias ) = split( ",", $item );
        $mapping->{$pool_id} = $alias;
      }

      my $shared_pools     = 0;
      my $shared_pool_path = "$inputdir/data/$managedname/$hmc";
      opendir( my $shp_dir, $shared_pool_path );
      my @shared_pool_files = grep( /SharedPool.*rrm/, readdir($shp_dir) );
      closedir($shp_dir);
      if ( defined $shared_pool_files[0] ) {
        $shared_pools = 1;
      }
      else {
        #print "debug xx 6: $managedname @ $hmc,  NO shared pools detected\n";
      }

      #add server shared pools
      if ($shared_pools) {

        #print "debug xx 7: $managedname @ $hmc\n";
        foreach my $file (@shared_pool_files) {
          my $cpupool = $file;
          $cpupool =~ s/\..*rrm//g;
          my $cpupool_sep = $cpupool;
          $cpupool_sep =~ s/SharedPool/CPU pool /g;

          if ( -e "$inputdir/data/$managedname/$hmc/cpu-pools-mapping.txt" ) {

            #print "debug xx 8: $managedname @ $hmc\n";
            my $pool_id = $file;
            ( undef, $pool_id ) = split( "SharedPool", $pool_id );
            ( $pool_id, undef ) = split( '\.', $pool_id );

            my $pool_alias            = $mapping->{$pool_id};
            my $cpupool_sep_and_alias = $cpupool_sep;
            if ( defined $pool_alias ) {
              $cpupool_sep_and_alias .= " : $pool_alias";
            }

            #print "debug xx 9: $managedname @ $hmc pool\n";
            menu( "$server_menu", "$hmc_space", "$managedname", "CPUpool-$cpupool", "$cpupool_sep_and_alias", "/$cgidir/detail.sh?host=$hmc_url_hash&server=$managedname_url_hash&lpar=$cpupool&item=shpool&entitle=&gui=1&none=none", "", "" );
          }
        }
      }

      #add server memory
      menu( "$server_menu", "$hmc_space", "$managedname", "mem", "Memory", "/$cgidir/detail.sh?host=$hmc_url_hash&server=$managedname_url_hash&lpar=cod&item=memalloc&entitle=&gui=1&none=none", "", "" );

      #paging aggregated do not supoort NMON data till v4.50
      my @files_pgs = <$inputdir/data/$managedname/$hmc/*\/pgs.mmm>;
      if ( scalar(@files_pgs) ) {
        menu( "$server_menu", "$hmc_space", "$managedname", "pagingagg", "Paging aggregated", "/$cgidir/detail.sh?host=$hmc_url_hash&server=$managedname_url_hash&lpar=cod&item=pagingagg&entitle=&gui=1&none=none", "", "" );
      }

      #hist reports
      my $mode;
      if ( $type_server eq $type_server_power ) {
        $mode = "power";
      }
      menu( "$server_menu", "$hmc_space", "$managedname", "hreports", "Historical reports", "/$cgidir/histrep.sh?mode=$mode&host=$hmc_url_hash", "", "" );

      #topten
      if ( !-e "$inputdir/data/$managedname/$hmc/vmware.txt" && !-e "$inputdir/data/$managedname/$hmc/hyperv.txt" ) {
        menu( "$server_menu", "$hmc_space", "$managedname", "top10", "LPAR TOP", "/$cgidir/detail.sh?host=$hmc_url_hash&server=$managedname_url_hash&lpar=cod&item=topten&entitle=&gui=1&none=none", "", "" );

      }

      #server's log
      if ( !$rest_api && !$ivm && -e "$webdir/$hmc/$managedname/gui-sys_log.html" && !-e "$inputdir/data/$managedname/$hmc/vmware.txt" && !-e "$inputdir/data/$managedname/$hmc/hyperv.txt" ) {
        my $sys_log_content = print_sys_log( "$hmc", "$managedname", 1 );
        open( my $gui_sys_log, ">", "$webdir/$hmc/$managedname/gui-sys_log.html" );
        print $gui_sys_log $sys_log_content;
        close($gui_sys_log);
        menu( "$server_menu", "$hmc_space", "$managedname", "syslog", "Server's logs", "$hmc_url_hash/$managedname_url_hash/gui-sys_log.html", "", "" ) if ( !$rest_api );
      }

      #view
      menu( "$server_menu", "$hmc_space", "$managedname", "view", "Overview", "/$cgidir/detail.sh?host=$hmc_url_hash&server=$managedname_url_hash&lpar=cod&item=view&entitle=&gui=1&none=none", "", "" );

      #hea
      my $hea_path = "$inputdir/data/$managedname/$hmc";
      opendir( my $hea_dir, $hea_path );
      my @files_hea = grep( /hea.*db/, readdir($hea_dir) );
      closedir($hea_dir);
      if ( scalar(@files_hea) ) {
        menu( "$server_menu", "$hmc_space", "$managedname", "hea", "HEA", "/$cgidir/detail.sh?host=$hmc_url_hash&server=$managedname_url_hash&lpar=cod&item=hea&entitle=&gui=1&none=none", "", "" );
      }
    }
  }

  return 0;
}

sub menu {
  my $a_type      = shift;
  my $a_hmc       = shift;
  my $a_server    = shift;    # "$3"|sed -e 's/:/===double-col===/g' -e 's/\\\\_/ /g'`
  my $a_lpar      = shift;    # "$4"|sed 's/:/===double-col===/g'`
  my $a_text      = shift;    # "$5"|sed 's/:/===double-col===/g'`
  my $a_url       = shift;    # "$6"|sed -e 's/:/===double-col===/g' -e 's/ /%20/g'`
  my $a_lpar_wpar = shift;    # lpar name when wpar is passing
  my $a_last_time = shift;

  if ( !defined $a_hmc )       { $a_hmc       = ""; }
  if ( !defined $a_server )    { $a_server    = ""; }
  if ( !defined $a_lpar )      { $a_lpar      = ""; }
  if ( !defined $a_text )      { $a_text      = ""; }
  if ( !defined $a_url )       { $a_url       = ""; }
  if ( !defined $a_lpar_wpar ) { $a_lpar_wpar = ""; }
  if ( !defined $a_last_time ) { $a_last_time = ""; }

  $a_hmc =~ s/:/===double-col===/g;
  $a_hmc =~ s/\\\\_/ /g if ( defined $a_hmc && $a_hmc ne "" );

  $a_server =~ s/:/===double-col===/g;
  $a_server =~ s/\\\\_/ /g if ( defined $a_hmc && $a_hmc ne "" );

  $a_lpar =~ s/:/===double-col===/g if ( defined $a_hmc && $a_hmc ne "" );

  $a_text =~ s/:/===double-col===/g if ( defined $a_hmc && $a_hmc ne "" );

  $a_url =~ s/:/===double-col===/g if ( defined $a_hmc && $a_hmc ne "" );
  $a_url =~ s/ /%20/g              if ( defined $a_hmc && $a_hmc ne "" );

  $a_lpar_wpar =~ s/:/===double-col===/g if ( defined $a_hmc && $a_hmc ne "" );

  if ( $ENV{LPARS_EXLUDE} ) {
    if ( $ENV{LPARS_EXCLUDE} =~ m/$a_lpar/ ) {
      print "lpar exclude   : $a_hmc:$a_server:$a_lpar - exclude string: $ENV{LPARS_EXCLUDE}\n";
      return 1;
    }
  }

  #  if ($a_type eq $type_gmenu & $gmenu == 1 ){
  #    return # print global menu once
  #  }
  #if [ "$type_server" = "$type_server_kvm" -a "$a_type" = "$type_gmenu" -a $kmenu_created -eq 1 ]; then
  #  return # print global menu once
  #fi
  #  if [ "$type_server" = "$type_server_vmware" -a  "$a_type" = "$type_gmenu" -a $vmenu_created -eq 1 ]; then
  #    return # print global menu once
  #  fi
  my $menu_string = "$a_type:$a_hmc:$a_server:$a_lpar:$a_text:$a_url:$a_lpar_wpar:$a_last_time:$type_server";
  print "power_menu.pl - add menu string : $menu_string\n";
  push @menu_lines, "$menu_string\n";
}

sub print_sys_log {
  my $hmc     = shift;
  my $server  = shift;
  my $new_gui = shift;
  return "<div  id=\"tabs\"><ul><li class=\"tabhmc\"><a href=\"$hmc/$server/gui-change-state.html\">State change</a></li><li class=\"tabhmc\"><a href=\"$hmc/$server/gui-change-config.html\">Config change</a></li></ul></div>";
}

sub print_cfg {
  my $new_gui = shift;
  return "<div  id=\"tabs\"> <ul><li><a href=\"/$cgidir/log-cgi.sh?name=maincfg&gui=$new_gui\">Global</a></li><li><a href=\"/$cgidir/log-cgi.sh?name=favcfg&gui=$new_gui\">Favourites</a></li> <li><a href=\"/$cgidir/log-cgi.sh?name=custcfg&gui=$new_gui\">Custom Groups</a></li><li><a href=\"/$cgidir/log-cgi.sh?name=alrtcfg&gui=$new_gui\">Alerting</a></li></ul></div>";
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

sub rrd_last {
  my $in = shift;
  eval { RRDp::cmd qq(last $in); };
  if ($@) {
    print STDERR "Error rrdtool : " . __FILE__ . ":" . __LINE__ . "\n";
  }
  my $last_rec_raw = RRDp::read;
  chomp($$last_rec_raw);
  my $last_rec = $$last_rec_raw;
  return $last_rec;
}

sub basename {
  my $full = shift;

  # basename without direct function
  my @base = split( /\//, $full );
  return $base[-1];
}

sub is_alive {

  # never use same name of variable in function as it the program globally!!!!
  #hmcA=`echo "$1"|sed 's/\\\\_/ /g'`
  my $hmcA = shift;

  #managednameA=`echo "$2"|sed 's/\\\\_/ /g'`
  my $managednameA = shift;

  if ( $managednameA =~ m/--unknown\$/ || $hmcA =~ m/no_hmc/ ) {
    my $find = `find $inputdir/data/$managednameA/$hmcA -type f -mtime -10 2>/dev/null | wc -l`;
    if ( $find > 1 ) {
      return 0;
    }
    else {
      return 1;
    }
  }

  # webdir always live so far
  if ( -e "$inputdir/data/$managednameA/$hmcA/vmware.txt" ) {
    return 0;
  }
  if ( !-d "$inputdir/data/$managednameA/$hmcA" ) {
    if ( -d "$webdir/$hmcA/$managednameA" ) {

      #      if ($ENV{DEBUG}) {
      #        print "rm 1 old system  : rmdir $webdir/$hmcA/$managednameA because $inputdir/data/$managednameA/$hmcA doesn't exist (no HMC found)\n";
      #        my $ret = rmtree ( "$webdir/$hmcA/$managednameA", {error => \my $err} ) || print STDERR "Directory couldn't be remove because : $!" . __FILE__.":".__LINE__."\n";
      #      }
      return 1;
    }
  }

  if ( -e "$inputdir/data/$managednameA/$hmcA/pool.rrm" ) {
    my $access_t = Xorux_lib::file_time_diff("$inputdir/data/$managednameA/$hmcA/pool.rrm");
    my $days_old = $access_t / 86400;
    if ( $days_old > 10 ) {

      #      if (-d "$webdir/$hmcA/$managednameA"){
      #        print "rm 2 old system : rmdir $webdir/$hmcA/$managednameA is $days_old old (no HMC found)\n";
      #
      #        my $dir = "$webdir/$hmcA/$managednameA";
      #        my $ret = rmtree ( "$dir", {error => \my $err} ) || print STDERR "Directory couldn't be remove because : $!" . __FILE__.":".__LINE__."\n";
      #      }
      return 1;
    }
  }
  return 0;
}

