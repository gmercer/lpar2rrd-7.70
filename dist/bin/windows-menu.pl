# windows-menu.pl
use 5.008_008;
$| = 1;

use strict;
use warnings;

use JSON;
use Data::Dumper;
use HostCfg;
use File::Copy;
use File::Path;

use Xorux_lib;

# you can try it from cmd line like:
# . etc/lpar2rrd.cfg ; $PERL bin/windows-menu.pl

defined $ENV{INPUTDIR} || Xorux_lib::error( "INPUTDIR undefined, config etc/lpar2rrd.cfg probably has not been loaded " . __FILE__ . ":" . __LINE__ ) && exit 1;
print "windows menu   : start at " . localtime() . "\n";
my $inputdir = $ENV{INPUTDIR};
my $webdir   = $ENV{WEBDIR};
my $cgidir   = 'lpar2rrd-cgi';
my $tmpdir   = "$inputdir/tmp";

if ( defined $ENV{TMPDIR_LPAR} ) {
  $tmpdir = $ENV{TMPDIR_LPAR};
}

my $type_server = "H";

my $gmenu_created = 0;    # global Power  menu is created only once
my $smenu_created = 0;    # super menu is created only once -favorites and customs groups

my $type_cmenu    = "C";      # custom group menu
my $type_fmenu    = "F";      # favourites menu
my $type_gmenu    = "G";      # global menu
my $type_smenu    = "S";      # server menu
my $type_dmenu    = "D";      # server menu - already deleted (non active) servers
my $type_tmenu    = "T";      # tail menu
my $type_qmenu    = "Q";      # tool version
my $type_hdt_menu = "HDT";    # hyperv disk global
my $type_hdi_menu = "HDI";    # hyperv disk item

# my $type_version = "O";       # free(open)/full version (1/0)

my @menu_lines = ();          # appends lines during script

my @servers;

#print "power-menu.pl skip 1 $ms : " . (defined $ENV{MANAGED_SYSTEMS_EXCLUDE}) . "\n\n";
#print "power-menu.pl skip 2 $ms : " . ($ENV{MANAGED_SYSTEMS_EXCLUDE} =~ /$ms/) . "\n$ms  =~ m/$ENV{MANAGED_SYSTEMS_EXCLUDE}/\n";
#print "power-menu.pl skip 3 $ms : " . ($ENV{MANAGED_SYSTEMS_EXCLUDE} ne "") . "\n\n";

#if ( defined $ENV{MANAGED_SYSTEMS_EXCLUDE} && $ENV{MANAGED_SYSTEMS_EXCLUDE} =~ /$ms/ && $ENV{MANAGED_SYSTEMS_EXCLUDE} ne "" ) {
#  print "Skip $ms due to exlude $ENV{MANAGED_SYSTEMS_EXCLUDE}\n\n";
#  next;
#}

#windows
my $ms = "windows";

my $win_uuid_file = "$inputdir/tmp/win_uuid.txt";
if ( open( my $fh, ">", $win_uuid_file ) ) {
  print $fh "";
  close($fh);
}
else {
  Xorux_lib::error( " cannot write to file : $win_uuid_file " . __FILE__ . ":" . __LINE__ );
}
my $win_host_uuid_file = "$inputdir/tmp/win_host_uuid.txt";
if ( open( my $fh, ">", $win_host_uuid_file ) ) {
  print $fh "";
  close($fh);
}
else {
  Xorux_lib::error( " cannot write to file : $win_host_uuid_file " . __FILE__ . ":" . __LINE__ );
}
my $win_host_uuid_file_json = "$inputdir/tmp/win_host_uuid.json";
if ( open( my $fh, ">", $win_host_uuid_file_json ) ) {
  print $fh "";
  close($fh);
}
else {
  Xorux_lib::error( " cannot write to file : $win_host_uuid_file_json " . __FILE__ . ":" . __LINE__ );
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
      Xorux_lib::error( "can't open $server_config_file: $! :" . __FILE__ . ":" . __LINE__ );
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
          Xorux_lib::error( "Cannot append to file $win_uuid_file " . __FILE__ . ":" . __LINE__ );
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
          Xorux_lib::error( "Cannot append to file $win_uuid_file " . __FILE__ . ":" . __LINE__ );
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
      Xorux_lib::error( "Cannot open $server_config_file: $! :" . __FILE__ . ":" . __LINE__ );
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
        Xorux_lib::error( "Cannot append to file $win_host_uuid_file " . __FILE__ . ":" . __LINE__ );
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
    if ( opendir( DIR, "$inputdir/data/$ms/$dir1/$server_name_space" ) ) {    # || warn("no dir $server_name_space");
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
    }
    else {
      Xorux_lib::error( "Cannot open dir $inputdir/data/$ms/$dir1/$server_name_space " . __FILE__ . ":" . __LINE__ );
    }

    #working with Cluster_Storage
    if ( opendir( DIR, "$inputdir/data/$ms/$dir1/$server_name_space" ) ) {    # || warn("no dir $server_name_space");
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
    else {
      Xorux_lib::error( "Cannot open dir $inputdir/data/$ms/$dir1/$server_name_space " . __FILE__ . ":" . __LINE__ );
    }
  }
}
if (%host_uuid_json) {
  Xorux_lib::write_json( "$win_host_uuid_file_json", \%host_uuid_json );
}

#power global menu
#menu( $type_gmenu,   "cgroups",     "CUSTOM GROUPS",                  "custom/group_first/gui-index.html",                     "", "", "", "", "" );
#menu( "$type_gmenu", "heatmaplpar", "Heatmap",                        "/lpar2rrd-cgi/heatmap-xormon.sh?platform=power&tabs=1", "", "", "", "", "" );
#menu( "$type_gmenu", "ghreports",   "Historical reports",             "/lpar2rrd-cgi/histrep.sh?mode=global",                  "", "", "", "", "" );
#menu( $type_gmenu,   "advisor",     "Resource Configuration Advisor", "gui-cpu_max_check.html",                                "", "", "", "", "" );
#menu( $type_gmenu,   "estimator",   "CPU Workload Estimator",         "cpu_workload_estimator.html",                           "", "", "", "", "" );
#menu( "$type_gmenu", "alert",       "Alerting",                       "/lpar2rrd-cgi/alcfg.sh?cmd=form",                       "", "", "", "", "" );

#menu( "$type_gmenu", "gcfg", "Configuration", "/$cgidir/detail.sh?host=&server=&lpar=cod&item=servers&entitle=0&none=none", "", "", "", "", "" );

#print Dumper \@menu_lines;

#print "@menu_lines\n";

# save menu

my $file_menu = "$tmpdir/menu_windows_pl.txt-tmp";
if ( open( MWP, ">$file_menu" ) ) {
  print MWP join( "", @menu_lines );
  close MWP;
}
else {
  Xorux_lib::error( " cannot write menu to file : $file_menu " . __FILE__ . ":" . __LINE__ );
}

`grep -v '^\$' $tmpdir/menu_windows_pl.txt-tmp > $tmpdir/menu_windows_pl.txt`;

print "windows menu   : finish at " . localtime() . "\n";

exit(0);

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
  print "windows-menu.pl - add menu string : $menu_string\n";
  push @menu_lines, "$menu_string\n";
}

sub basename {
  my $full = shift;

  # basename without direct function
  my @base = split( /\//, $full );
  return $base[-1];
}

