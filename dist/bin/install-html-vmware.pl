use strict;
use warnings;
use Data::Dumper;
use Xorux_lib qw(read_json);
use File::Copy;

#`. /home/lpar2rrd/lpar2rrd/etc/lpar2rrd.cfg`;

###### RUN SCRIPT WITHOUT ARGUMENTS (PRINT ):
######
###### .  /home/lpar2rrd/lpar2rrd/etc/lpar2rrd.cfg ; $PERL ./bin/install-html-vmware.pl
######

# flush after every write
# $| = 1;

my $DEBUG = 1;

defined $ENV{INPUTDIR} || error( " Not defined INPUTDIR, probably not read etc/lpar2rrd.cfg " . __FILE__ . ":" . __LINE__ ) && exit 1;
defined $ENV{WEBDIR}   || error( " Not defined WEBDIR,   probably not read etc/lpar2rrd.cfg " . __FILE__ . ":" . __LINE__ ) && exit 1;
my $ENTITLEMENT_LESS = 0;
if ( defined $ENV{ENTITLEMENT_LESS} ) { $ENTITLEMENT_LESS = $ENV{ENTITLEMENT_LESS} }

my $basedir = $ENV{INPUTDIR};
my $webdir  = $ENV{WEBDIR};
my $CGI_DIR = "lpar2rrd-cgi";
my $RRDTOOL = $ENV{RRDTOOL};

my $tmpdir = "$basedir/tmp";
if ( defined $ENV{TMPDIR_LPAR} ) {
  $tmpdir = $ENV{TMPDIR_LPAR};
}
my $wrkdir = "$basedir/data";

my $managed_systems_exclude = ":" . $ENV{MANAGED_SYSTEMS_EXCLUDE} . ":";    # for easy testing with function 'index'

### datastore with this pattern in name will be excluded
my $ds_name_pattern_to_exclude    = "GX_BACKUP";
my $total_datastore_count_in_menu = 0;

my @proxy_file_names = ();

# refresh files younger than
my $refresh_time = time - ( 90 * 60 );
$refresh_time = 1000000000;                                                 # a time in 2001 is old enough for all files

sub push_younger_than {
  my $file = shift;
  return if !-f $file;
  if ( ( ( stat $file )[9] ) > $refresh_time ) {

    # print "File $file is going to refresh\n";
    # $file =~ s/$wrkdir\///;
    $file =~ s/$basedir\///;
    push @proxy_file_names, $file;
  }
}

my $type_amenu         = "A";    # VMWARE CLUSTER menu
my $type_bmenu         = "B";    # VMWARE RESOURCEPOOL menu
my $type_gmenu         = "G";    # global menu
my $type_dmenu         = "D";    # server menu - already deleted (non active) servers
my $type_smenu         = "S";    # server menu
my $type_qmenu         = "Q";    # tool version
my $type_vmenu         = "V";    # VMWARE total menu
my $type_zmenu         = "Z";    # datastore menu
my $type_server_vmware = "V";    # vmware

my $actual_unix_time     = time;
my $last_ten_days        = 10 * 86400;                            ### ten days back
my $actual_last_ten_days = $actual_unix_time - $last_ten_days;    ### ten days back with actual unix time-

my $active_days = 30;
my $year_back   = time - 31536000;
if ( defined $ENV{VMWARE_ACTIVE_DAYS} && $ENV{VMWARE_ACTIVE_DAYS} > 1 && $ENV{VMWARE_ACTIVE_DAYS} < 3650 ) {
  $active_days = $ENV{VMWARE_ACTIVE_DAYS};
}
my $last_30_days        = $active_days * 86400;                   ### 30 days back
my $actual_last_30_days = $actual_unix_time - $last_30_days;      ### 30 days back with actual unix time-

opendir( DIR, "$wrkdir" ) || error( " directory does not exists : $wrkdir " . __FILE__ . ":" . __LINE__ ) && exit 1;
my @wrkdir_all = grep !/^\.\.?$/, readdir(DIR);
closedir(DIR);
@wrkdir_all = sort @wrkdir_all;

my @menu_lines = ();                                              # appends lines during script

my $result = print_vmware_menu();

# print "@menu_lines\n";

if ( defined $ENV{VMWARE_PROXY_SEND} ) {

  my $tmpdir_vmware = "$tmpdir/VMWARE";                          # here creates files to send by offsite_vmware.sh
  my $file_list     = "$tmpdir_vmware/vmware_proxy_file_list";
  print "preparing      : $file_list(.tmp).txt\n";

  # print join("\n",@proxy_file_names);
  # print "\n";
  # save the list
  if ( open( my $MWP, ">$file_list.tmp" ) ) {
    print $MWP join( "\n", @proxy_file_names );
    close $MWP;
  }
  else {
    error( " cannot write : $file_list.tmp " . __FILE__ . ":" . __LINE__ );
    exit;
  }
  if ( !move( "$file_list.tmp", "$file_list.txt" ) ) {
    error( " cannot rename : $file_list.tmp to $file_list.txt " . __FILE__ . ":" . __LINE__ );
    exit;
  }
  `cd "$basedir"; tar -cvhf "$tmpdir_vmware/vmware_proxy_ball.tmp" -T "$file_list.txt"`;
  if ( !move( "$tmpdir_vmware/vmware_proxy_ball.tmp", "$tmpdir_vmware/vmware_proxy_ball.tar" ) ) {
    error( " cannot rename : $tmpdir_vmware/vmware_proxy_ball.tmp to $tmpdir_vmware/vmware_proxy_ball.tar " . __FILE__ . ":" . __LINE__ );
    exit;
  }
  if ( -f "$tmpdir_vmware/vmware_proxy_ball.tar.gz" ) {
    if ( !unlink "$tmpdir_vmware/vmware_proxy_ball.tar.gz" ) {
      error( " cannot unlink : $tmpdir_vmware/vmware_proxy_ball.tar.gz " . __FILE__ . ":" . __LINE__ );
      exit;
    }
  }
  print "prepared       : $tmpdir_vmware/vmware_proxy_ball.tar\n";
}

# exit; # when debug

# save menu
my $file_menu = "$tmpdir/menu_vmware_pl.txt";

if ( open( my $MWP, ">$file_menu" ) ) {
  print $MWP join( "", @menu_lines );
  close $MWP;
}
else {
  error( " cannot write menu to file : $file_menu " . __FILE__ . ":" . __LINE__ );
}
exit $result;

sub menu {
  my $type        = shift;
  my $hmc         = shift;
  my $server      = shift;
  my $lpar        = shift;
  my $text        = shift;
  my $url         = shift;
  my $lpar_wpar   = shift;    # lpar name when wpar is passing
  my $last_time   = shift;
  my $type_server = shift;
  my $folder_path = shift;

  $folder_path = "" if !defined $folder_path;

  $text      = "" if !defined $text;
  $url       = "" if !defined $url;
  $lpar_wpar = "" if !defined $lpar_wpar;
  $last_time = "" if !defined $last_time;

  $hmc       =~ s/:/===double-col===/g;
  $server    =~ s/:/===double-col===/g;
  $lpar      =~ s/:/===double-col===/g;
  $text      =~ s/:/===double-col===/g;
  $url       =~ s/:/===double-col===/g;
  $lpar_wpar =~ s/:/===double-col===/g;

  $url =~ s/ /%20/g;

  #print "$type:$hmc:$server:$lpar:$text:$url:$lpar_wpar:$last_time:$type_server\n"; # >> $MENU_OUT

  push @menu_lines, "$type:$hmc:$server:$lpar:$text:$url:$lpar_wpar:$last_time:$type_server:$folder_path\n";
}

############### VMWARE
sub print_vmware_menu {
  my $uuid;
  my $name_vm;

  my $type_server_vmware = "V";    #vmware
  my $server_menu        = "";
  my $vcenter_printed    = 0;

  my $type_server   = $type_server_vmware;
  my $vmenu_created = "0";

  # test: if there are more vcenters with same name, put into menu only the newest one (& report it)
  my %vcenter_to_omit = ();
  my %vcenter_name    = ();

  my @wrkdir_all_tmp = @wrkdir_all;

  # proxy part
  push_younger_than("$tmpdir/vcenters_clusters_config.html");

  # proxy part end

  while ( my $server_all = shift(@wrkdir_all_tmp) ) {
    $server_all = "$wrkdir/$server_all";
    if ( !-d $server_all )               { next; }
    if ( -l $server_all )                { next; }
    if ( $server_all =~ /\/vmware_VMs/ ) { next; }
    my $server = basename($server_all);

    if ( $server =~ /^vmware_/ ) {

      # print "testing vcenter: $server\n";
      # vcenter, vmware clusters and resourcepools, datacenters and datastores
      my $name_file = "$wrkdir/$server/vmware_alias_name";
      next if !-f $name_file;    # how it is possible?
      if ( $ENV{DEMO} ) {

        # do not test
      }
      else {
        next if ( stat("$name_file") )[9] < $actual_last_30_days;    # older vCenter is not in menu
      }

      my $alias_name = "fake _alias_name";
      if ( open( FC, "< $name_file" ) ) {
        $alias_name = <FC>;
        close(FC);
        $alias_name =~ s/^[^\|]*\|//;
        chomp $alias_name;
      }
      else {
        error( "Cannot read $name_file: $!" . __FILE__ . ":" . __LINE__ );
        next;
      }
      if ( !exists $vcenter_name{$alias_name} ) {
        $vcenter_name{$alias_name} = $name_file;    # remember it
        next;
      }
      ### !!! more same vcenters with different uuid
      if ( ( stat("$name_file") )[9] > ( stat("$vcenter_name{$alias_name}") )[9] ) {
        $vcenter_to_omit{ $vcenter_name{$alias_name} } = "omit";
      }
      else {
        $vcenter_to_omit{$name_file} = "omit";
      }
      error( "NOTICE: Two vcenters with same name '$alias_name' indicated: $name_file :&: $vcenter_name{$alias_name} : take only newer " . __FILE__ . ":" . __LINE__ );
    }
  }

  # print Dumper ("175 install-html-vmware.pl",%vcenter_to_omit," to be omitted");

  while ( my $server_all = shift(@wrkdir_all) ) {
    if ( $server_all eq "windows" ) { next; }
    $server_all = "$wrkdir/$server_all";
    if ( !-d $server_all ) { next; }
    if ( -l $server_all )  { next; }
    if ( $server_all =~ /\/vmware_VMs/ ) {

      # proxy part
      push_younger_than("$server_all/vmware.txt");
      push_younger_than("$server_all/vm_uuid_name.txt");

      # proxy part end
      next;
    }
    my $server = basename($server_all);

    if ( $server =~ /^vmware_/ ) {

      print "testing vcenter: $server\n";

      # vcenter, vmware clusters and resourcepools, datacenters and datastores
      my $name_file = "$wrkdir/$server/vmware_alias_name";
      next if !-f $name_file;    # how it is possible?
      if ( $ENV{DEMO} ) {

        # do not test
      }
      else {
        next if ( stat("$name_file") )[9] < $actual_last_30_days;    # older vCenter is not in menu
      }

      my $alias_name = "fake _alias_name";
      if ( open( FC, "< $name_file" ) ) {
        $alias_name = <FC>;
        close(FC);
        $alias_name =~ s/^[^\|]*\|//;
        chomp $alias_name;
      }
      else {
        error( "Cannot read $name_file: $!" . __FILE__ . ":" . __LINE__ );
        next;
      }

      # omit vcenter if duplicated
      if ( exists $vcenter_to_omit{$name_file} ) {
        error( "Vcenter '$alias_name' omitted due duplication: $name_file " . __FILE__ . ":" . __LINE__ );
        next;
      }

      $type_server = $type_server_vmware;
      my $hmc_dir = "$wrkdir/$server";
      opendir( DIR, "$hmc_dir" ) || error( " directory does not exists : $hmc_dir " . __FILE__ . ":" . __LINE__ ) && next;
      my @all_clusters = grep /cluster_*/, readdir(DIR);
      rewinddir(DIR);
      my @all_datacenters = grep /datastore_*/, readdir(DIR);
      closedir(DIR);

      # print "879 \@all_clusters @all_clusters \@all_datacenters @all_datacenters\n";

      next if ( stat("$name_file") )[9] < $actual_last_30_days;    # older vcenter is not in menu

      my $vcenter_printed = 0;                                     # not printed yet
      my $v_name          = "fake_vcenter_name";

      # proxy part
      push_younger_than("$name_file");
      push_younger_than("$wrkdir/$server/servers.txt");
      push_younger_than("$wrkdir/$server/esxis_config.html");
      push_younger_than("$wrkdir/$server/esxis_config.txt");
      push_younger_than("$wrkdir/$server/vcenter_config.html");
      push_younger_than("$wrkdir/$server/vcenter_config.txt");

      # proxy part end

      foreach (@all_clusters) {
        my $hmc = $_;

        my $cluster_dir = "$hmc_dir/$_";
        next if !-d $cluster_dir;

        print "testing        : cluster dir $cluster_dir\n";

        # cluster without ESXi server then problem with graphing
        next if ( !-f "$cluster_dir/hosts_in_cluster" );
        next if -s "$cluster_dir/hosts_in_cluster" < 2;    # too short file - no meaning

        opendir( DIR, "$cluster_dir" ) || error( " cant open directory : $cluster_dir " . __FILE__ . ":" . __LINE__ ) && next;
        my @cluster_files = readdir(DIR);
        closedir(DIR);

        my @all_cluster_names       = grep /cluster_name_*/,   @cluster_files;    # should be only one, take the 1st
        my @all_vcenter_names       = grep /vcenter_name_*/,   @cluster_files;    # should be only one, take the 1st
        my @all_resourcepools_files = grep /resgroup.*\.rrc$/, @cluster_files;

        if ( !defined $all_cluster_names[0] || $all_cluster_names[0] eq "" ) {
          print "testing update : cluster cluster_name_xx file does not exist !!! skipping\n";
          next;
        }

        # get the newest file if there are more
        my $c_name = $all_cluster_names[0];
        foreach (@all_cluster_names) {

          # print "$_\n";
          next if -M "$cluster_dir/$_" >= -M "$cluster_dir/$c_name";
          $c_name = $_;
          print "351 --------------------------------------------------------------------- younger cluster name is $c_name\n";
        }

        $c_name =~ s/cluster_name_//;

        # here can be a test, if the cluster name is in table data/vcenter/esxis_config.txt
        # if not, do not show cluster in menu because this cluster is not in vsphere vcenter

        if ( !defined $all_vcenter_names[0] || $all_vcenter_names[0] eq "" ) {
          print "testing update : cluster vcenter_name_xx file does not exist !!! skipping\n";
          next;
        }
        if ( $ENV{DEMO} ) {

          # do not test
        }
        else {
          next if ( stat("$cluster_dir/$all_vcenter_names[0]") )[9] < $actual_last_30_days;    # older cluster is not in menu
        }

        ## proxy part
        foreach (@cluster_files) {
          next if $_ eq "." or $_ eq ".." or $_ eq "last" or $_ eq "rrc";
          if ( index( "vmware.txt,vcenter,hosts_in_cluster,active_rp_paths.txt,rp_config.html,rp_config.txt,vm_folder_path.json,rp_folder_path.json", $_ ) > -1 ) {
            push_younger_than("$cluster_dir/$_");
            next;
          }
          if ( index( $_, "cluster_name_" ) == 0 || index( $_, ".vmr" ) > 0 || index( $_, "rp__vmid__resgroup-" ) == 0 || index( $_, "vcenter_name_" ) == 0 || index( $_, ".resgroup-" ) > 0 ) {
            push_younger_than("$cluster_dir/$_");
            next;
          }
        }
        ## proxy part end

        print "testing update : cluster file $cluster_dir/cluster.rrc\n";
        if ( !-f "$cluster_dir/cluster.rrc" ) {
          print "testing update : cluster file does not exist !!! $cluster_dir/cluster.rrc\n";
          next;
        }
        next if ( stat("$cluster_dir/cluster.rrc") )[9] < $actual_last_30_days;    # older cluster is not in menu

        $v_name = $all_vcenter_names[0];
        $v_name =~ s/vcenter_name_//;

        if ( !$vcenter_printed ) {
          if ( $DEBUG eq 1 ) { print "add to menu $type_vmenu  : $v_name:$server:$alias_name\n"; }
          menu( "$type_vmenu", "$v_name", "Totals", "/$CGI_DIR/detail.sh?host=$v_name&server=$server&lpar=nope&item=hmctotals&entitle=$ENTITLEMENT_LESS&gui=1&none=none", "", "", "$alias_name", "", $type_server );

          # menu "$type_vmenu" "$vn_file_nem" "Totals" "/$CGI_DIR/detail.sh?host=$vn_file_nem&server=$managedname&lpar=nope&item=hmctotals&entitle=$ENTITLEMENT_LESS&gui=1&none=none" "" "" "$alias_name"

          # hist reports & Top10 vcenter
          #if ($DEBUG eq 1) { print "add to menu $type_vmenu  : $v_name:$alias_name:Hist reports\n";}
          #menu ("$type_vmenu","$v_name","Historical reports","/$CGI_DIR/histrep.sh?mode=vcenter","","","$alias_name","",$type_server);

          if ( $DEBUG eq 1 ) { print "add to menu $type_vmenu  : $v_name:$alias_name:VM TOP\n"; }
          menu( "$type_vmenu", "$v_name", "VM TOP", "/$CGI_DIR/detail.sh?host=$hmc&server=$alias_name&lpar=cod&item=topten_vm&entitle=0&none=none", "", "", "$alias_name", "", $type_server );
          $vcenter_printed++;
        }
        my $hmc_url    = urlencode_d($hmc);
        my $server_url = urlencode_d($server);

        if ( $DEBUG eq 1 ) { print "add to menu $type_amenu  : CLUST TOT $v_name:$c_name:$server\n"; }
        menu( "$type_amenu", "$v_name", "$c_name", "Totals", "/$CGI_DIR/detail.sh?host=$hmc_url&server=$server_url&lpar=nope&item=cluster&entitle=0&gui=1&none=none", "", "$alias_name", "", $type_server );

        # cluster has resourcepools
        # print "947 \@all_resourcepools_files @all_resourcepools_files\n";

        my $rp_folder_path_file = "$cluster_dir/rp_folder_path.json";
        my $rp_folder_pathes    = "";

        # print "219 read file $rp_folder_path_file\n";
        if ( defined $rp_folder_path_file && -f $rp_folder_path_file ) {
          $rp_folder_pathes = Xorux_lib::read_json($rp_folder_path_file);

          # print Dumper ("222",$rp_folder_pathes);
        }

        opendir( DIR, "$cluster_dir" ) || error( " directory does not exists : $cluster_dir " . __FILE__ . ":" . __LINE__ ) && next;
        foreach (@all_resourcepools_files) {
          next if index( $_, "Resources" ) != -1;
          print "testing update : resourcepool file $cluster_dir/$_\n";
          next if ( stat("$cluster_dir/$_") )[9] < $actual_last_30_days;    # older resourcepool is not in menu

          # find the name in filename 'name.moref'
          rewinddir(DIR);
          my $respool_name = $_;
          $respool_name =~ s/\.rrc$//;
          my @all_resourcepool_names = grep /.*\.$respool_name$/, readdir(DIR);    # should be only one, take the 1st
                                                                                   # print "958 for $_ \@all_resourcepool_names @all_resourcepool_names\n";
          my $rp_url                 = $all_resourcepool_names[0];
          $rp_url =~ s/\.resgroup.*//;

          # $rp_url = urlencode_d($rp_url);

          # print "242 \$respool_name $respool_name\n";

          #
          ###  RP folders solution
          #
          my $folder_moref = $respool_name;
          my $folder_path  = "";

          # print "1117 \$info_line $info_line\n";
          if ( defined $folder_moref && $folder_moref ne "" && $rp_folder_pathes ne "" ) {    #&& index($folder_moref,"group-")==0) left curly
                                                                                              # print "\$info_line $info_line \$folder_moref $folder_moref\n";
            $folder_path = give_path_to_folder( $folder_moref, \%$rp_folder_pathes, "", 0 );

            # print "\$info_line $info_line \$folder_moref $folder_moref \$folder_path $folder_path\n";
          }
          my $count = $folder_path =~ tr/\///;
          $folder_path = "" if $count < 2;

          # Development/Dev - child/ # remove own rp name - the last part
          $folder_path =~ s/\/[^\/]*\/$/\//;

          if ( $DEBUG eq 1 ) { print "add to menu $type_bmenu  : RESC POOL $v_name:$c_name:$server:$rp_url\n"; }
          menu( "$type_bmenu", "$v_name", "$c_name", "$rp_url", "/$CGI_DIR/detail.sh?host=$hmc&server=$server&lpar=$respool_name&item=resourcepool&entitle=0&gui=1&none=none", "", "$alias_name", "", $type_server, $folder_path );

        }
        closedir(DIR);
      }

      foreach (@all_datacenters) {
        my $datacenter_dir = "$hmc_dir/$_";
        my $hmc            = $_;

        opendir( DIR, "$datacenter_dir" ) || error( " cannot open directory : $datacenter_dir " . __FILE__ . ":" . __LINE__ ) && next;
        my @datacenter_files = readdir(DIR);
        closedir(DIR);

        # find datacenter name in 'datastore_<name>.dcname'
        my @all_datacenter_names = grep /datastore_.*\.dcname/, @datacenter_files;    # should be only one, take the 1st
                                                                                      # print "380 \@all_datacenter_names @all_datacenter_names\n";
        if ( !defined $all_datacenter_names[0] or $all_datacenter_names[0] eq "" ) {
          print "testing update : datacenter file $datacenter_dir/ has not file: xxx.dcname, skipping\n";
          next;
        }
        print "testing update : datacenter file $datacenter_dir/$all_datacenter_names[0]\n";
        next if ( stat("$datacenter_dir/$all_datacenter_names[0]") )[9] < $actual_last_30_days;    # older datacenter is not in menu

        push_younger_than("$datacenter_dir/$all_datacenter_names[0]");

        if ( $v_name eq "fake_vcenter_name" ) {                                                    # probably vCenter without clusters
          $v_name = $alias_name;
          if ( !$vcenter_printed ) {

            # need to get vcenter hostname
            my @all_vcenter_names = grep /vcenter_name_*/, @datacenter_files;    # should be only one, take the 1st
            my $vcenter_hostname  = "fake_vcenter_hostname";
            if ( !defined $all_vcenter_names[0] or $all_vcenter_names[0] eq "" ) {
              print "testing update : datacenter file $datacenter_dir/ has not file: vcenter_name_*, skipping\n";
              next;
            }
            push_younger_than("$datacenter_dir/$all_vcenter_names[0]");

            $vcenter_hostname = $all_vcenter_names[0];
            $vcenter_hostname =~ s/vcenter_name_//;
            $v_name = $vcenter_hostname;

            if ( $DEBUG eq 1 ) { print "add to menu $type_vmenu  : $v_name:$server:$alias_name:$vcenter_hostname\n"; }
            menu( "$type_vmenu", "$v_name", "Totals", "/$CGI_DIR/detail.sh?host=$v_name&server=$server&lpar=nope&item=hmctotals&entitle=$ENTITLEMENT_LESS&gui=1&none=none", "", "", "$alias_name", "", $type_server );

            # hist reports & Top10 vcenter
            #if ($DEBUG eq 1) { print "add to menu $type_vmenu  : $v_name:$alias_name:Hist reports\n";}
            #menu ("$type_vmenu","$v_name","Historical reports","/$CGI_DIR/histrep.sh?mode=vcenter","","","$alias_name","",$type_server);

            if ( $DEBUG eq 1 ) { print "add to menu $type_vmenu  : $v_name:$alias_name:VM TOP\n"; }
            menu( "$type_vmenu", "$v_name", "VM TOP", "/$CGI_DIR/detail.sh?host=$hmc&server=$alias_name&lpar=cod&item=topten_vm&entitle=0&none=none", "", "", "$alias_name", "", $type_server );
            $vcenter_printed++;
          }

          # do not use next line for non cluster vcenter,  so datastores have proper $v_name as vcenter hostname
          # $v_name = $alias_name;
        }

        my $datacenter_name = $all_datacenter_names[0];
        $datacenter_name =~ s/\.dcname$//;

        my @all_datastores = grep /.*\.rrs/, @datacenter_files;

        # datacenter has datastores
        #print "390 \@all_datastores @all_datastores\n";
        # these are UUID names like 52b85c8c359cb741-02f40223f72d51a7.rrs 57e66ae1-aeb8f118-207e-18a90577a87c.rrs

        my $ds_folder_path_file = "$datacenter_dir/ds_folder_path.json";
        my $ds_folder_pathes    = "";

        # print "325 read file $ds_folder_path_file\n";
        if ( -f $ds_folder_path_file ) {
          $ds_folder_pathes = Xorux_lib::read_json($ds_folder_path_file);

          # print Dumper ("328",$ds_folder_pathes);
          push_younger_than("$datacenter_dir/ds_folder_path.json");
        }

        foreach (@all_datastores) {
          my $ds_uuid = $_;
          $ds_uuid =~ s/\.rrs$//;

          # find the name in filename 'name.uuid'
          my @all_ds_names = grep /.*\.$ds_uuid/, @datacenter_files;    # should be only one, take the 1st
          if ( !defined $all_ds_names[0] || $all_ds_names[0] eq "" ) {
            print "testing update : datastore file does not exist !!! for uuid: $ds_uuid\n";
            next;
          }

          print "testing update : datastore file $datacenter_dir/$all_ds_names[0]\n";

          #  datastore to exclude
          if ( index( $all_ds_names[0], $ds_name_pattern_to_exclude ) > -1 ) {
            print "exclude DS     : $all_ds_names[0]\n";
            next;
          }

          # print  "testing update : datastore file $datacenter_dir/$all_ds_names[0]\n";
          next if ( stat("$datacenter_dir/$ds_uuid.rrs") )[9] < $actual_last_30_days;    # older datastore is not in menu
          if ( -f "$datacenter_dir/$ds_uuid.html" ) {
            push_younger_than("$datacenter_dir/$ds_uuid.html");
          }
          if ( -f "$datacenter_dir/$ds_uuid.disk_uids" ) {
            push_younger_than("$datacenter_dir/$ds_uuid.disk_uids");
          }

          my $ds_name = $all_ds_names[0];
          $ds_name =~ s/\.$ds_uuid$//;

          #
          ###  DS folders solution
          #
          my $folder_moref = "";
          if ( open( FC, "< $datacenter_dir/$all_ds_names[0]" ) ) {
            $folder_moref = <FC>;
            close(FC);
            push_younger_than("$datacenter_dir/$all_ds_names[0]");
          }
          else {
            error( "Cannot read $datacenter_dir/$all_ds_names[0]: $!" . __FILE__ . ":" . __LINE__ );
          }

          my $folder_path = "";
          if ( defined $folder_moref && $folder_moref ne "" && $ds_folder_pathes ne "" ) {    #&& index($folder_moref,"group-")==0) left_curly
            $folder_path = give_path_to_folder( $folder_moref, \%$ds_folder_pathes, "", 0 );
            if ( $folder_path ne "" ) {
              $folder_path .= ":$folder_moref:";
            }
          }

          if ( $DEBUG eq 1 ) { print "add to menu $type_zmenu  : DATASTORE $server:$hmc:$ds_name\n"; }
          menu( "$type_zmenu", "$v_name", "$datacenter_name", "$ds_name", "/$CGI_DIR/detail.sh?host=$hmc&server=$server&lpar=$ds_uuid&item=datastore&entitle=0&gui=1&none=none", "", "$alias_name", "", $type_server, $folder_path );
          $total_datastore_count_in_menu++;
        }
        if ( -f "$datacenter_dir/vmware.txt" ) {
          push_younger_than("$datacenter_dir/vmware.txt");
        }
        if ( -f "$datacenter_dir/vcenter" ) {
          push_younger_than("$datacenter_dir/vcenter");
        }
        my @all_vcenter_names = grep /vcenter_name_/, @datacenter_files;    # should be only one, take the 1st
        if ( -f "$datacenter_dir/$all_vcenter_names[0]" ) {
          push_younger_than("$datacenter_dir/$all_vcenter_names[0]");
        }
      }

      next;                                                                 # server (item under data/)
    }
    #
    my $hmc_dir = "$wrkdir/$server";
    opendir( DIR, "$hmc_dir" ) || error( " directory does not exists : $hmc_dir " . __FILE__ . ":" . __LINE__ ) && return 1;
    my @hmc_dir_all = grep !/^\.\.?$/, readdir(DIR);
    closedir(DIR);
    my @all_solo_datastores = grep /datastore_.*/, @hmc_dir_all;
    s/$_/$hmc_dir\/$_/ for @hmc_dir_all;

    foreach (@all_solo_datastores) {
      print "found solo datacenter $_\n";
      my $datacenter_dir = "$hmc_dir/$_";
      my $hmc            = $_;

      # find datacenter name in 'datastore_<name>.dcname'
      opendir( DIR, "$datacenter_dir" ) || error( " cannot open directory : $datacenter_dir " . __FILE__ . ":" . __LINE__ ) && next;
      my @datacenter_files = readdir(DIR);
      closedir(DIR);
      my @all_datacenter_names = grep /datastore_.*\.dcname/, @datacenter_files;    # should be only one, take the 1st
      my @all_datastores       = grep /.*\.rrs/,              @datacenter_files;

      # print "304 \@all_datacenter_names @all_datacenter_names\n";
      print "testing update : solo datacenter file $datacenter_dir/$all_datacenter_names[0]\n";
      next if ( stat("$datacenter_dir/$all_datacenter_names[0]") )[9] < $actual_last_30_days;    # older datacenter is not in menu

      my $datacenter_name = $all_datacenter_names[0];
      $datacenter_name =~ s/\.dcname$//;

      # datacenter has datastores
      #print "312 \@all_datastores @all_datastores\n";
      # these are UUID names like 52b85c8c359cb741-02f40223f72d51a7.rrs 57e66ae1-aeb8f118-207e-18a90577a87c.rrs

      foreach (@all_datastores) {
        my $ds_uuid = $_;
        $ds_uuid =~ s/\.rrs$//;

        # find the name in filename 'name.uuid'
        my @all_ds_names = grep /.*\.$ds_uuid/, @datacenter_files;    # should be only one, take the 1st
        print "testing update : solo datastore file $datacenter_dir/$all_ds_names[0]\n";
        next if ( stat("$datacenter_dir/$ds_uuid.rrs") )[9] < $actual_last_30_days;    # older datastore is not in menu

        my $ds_name = $all_ds_names[0];
        $ds_name =~ s/\.$ds_uuid$//;

        if ( $DEBUG eq 1 ) { print "add to menu $type_zmenu  : solo DATASTORE $server:$hmc:$ds_name\n"; }
        menu( "$type_zmenu", "", "$datacenter_name", "$ds_name", "/$CGI_DIR/detail.sh?host=$datacenter_name&server=$server&lpar=$ds_uuid&item=datastore&entitle=0&gui=1&none=none", "", "", "", $type_server );
        $total_datastore_count_in_menu++;
      }
    }

    # here ESXi servers
    while ( my $hmc_all = shift(@hmc_dir_all) ) {
      next if ( !-f "$hmc_all/vmware.txt" );
      next if ( !-f "$hmc_all/cpu.csv" );      # strange when not present
      my $file_time = ( stat("$hmc_all/cpu.csv") )[9];
      if ( $ENV{DEMO} ) {

        # do not test
      }
      else {
        next if $file_time < $actual_last_30_days;
      }

      # exclude excluded servers
      if ( ( index $managed_systems_exclude, ":$server:" ) ne -1 ) {
        print "managed esxi   : $server is excluded from menu, continuing with the others ...\n";
        next;
      }

      # case: user moved esxi from one cluster/vcenter to another and later returned -> esxi & VMs were printed under both
      # the dir structure was the same as with two hmcs
      # trick to find the newest pool.rrm and only this to print
      # go through this while only once i.e. last; at the end

      my $newer_hmc = "$hmc_all";

      # print "652 ----------------- \@hmc_dir_all @hmc_dir_all ". scalar @hmc_dir_all ." $file_time\n";
      if ( scalar @hmc_dir_all > 0 ) {
        foreach (@hmc_dir_all) {
          next            if !-f "$_/cpu.csv";                         # tresh or solo datacenter
          $newer_hmc = $_ if ( stat("$_/cpu.csv") )[9] > $file_time;
        }
        next if "$newer_hmc" ne "$hmc_all";
      }
      next if ( !-f "$hmc_all/pool.rrm" );    # strange when not present: could be just instal for proxy for other machine

      $server_menu = $type_smenu;             # must be used $server_menu since now instead of $type_smenu as it says if the server is dead or not

      if ( $file_time < $actual_last_ten_days ) {
        if ( $ENV{DEMO} ) {

          # do not test
        }
        else {
          $server_menu = $type_dmenu;    # continue, just sight it as "dead", this brings it into menu.txt and is further used only for global hostorical reporting of already dead servers
        }
      }

      my $host_moref_id = "";            # it is set up in proxy part

      # proxy part
      my $file_path = "$hmc_all";

      opendir( DIR, "$file_path" ) || error( " directory does not exists : $file_path " . __FILE__ . ":" . __LINE__ ) && next;
      my @server_files = readdir(DIR);
      closedir(DIR);

      # print "@server_files\n";
      # . .. vmware.txt my_vcenter_name VM_hosting.vmh lpar_trans.txt cpu.html cpu.csv disk.html host.cfg pool.rrm last.txt my_cluster_name host_moref_id.host-272
      foreach (@server_files) {
        next if $_ eq "." or $_ eq "..";
        if ( index( "vmware.txt,my_vcenter_name,VM_hosting.vmh,lpar_trans.txt,cpu.html,cpu.csv,disk.html,host.cfg,my_cluster_name", $_ ) > -1 ) {
          push_younger_than("$file_path/$_");
          next;
        }
        if ( index( $_, "host_moref_id" ) == 0 ) {
          push_younger_than("$file_path/$_");
          $host_moref_id = $_;
          next;
        }
      }

      # proxy part end

      my $hmc = basename($hmc_all);
      if ( !-d "$webdir/$hmc" ) {
        mkdir "$webdir/$hmc" || error( "Cannot create $webdir/$hmc : $!" . __FILE__ . ":" . __LINE__ );
      }
      if ( !-d "$webdir/$hmc/$server" ) {
        mkdir "$webdir/$hmc/$server" || error( "Cannot create $webdir/$hmc/$server : $!" . __FILE__ . ":" . __LINE__ );
      }
      if ( $vmenu_created eq "0" ) {

        # VMware global menu
        menu( "$type_gmenu", "heatmapvm",     "Heatmap",            "/$CGI_DIR/heatmap-xormon.sh?platform=vmware&tabs=1", "", "", "", "", "$type_server" );
        menu( "$type_gmenu", "overview_vm",   "Overview",           "overview_vmware.html",                               "", "", "", "", "$type_server" );
        menu( "$type_gmenu", "histrepglobvm", "Historical reports", "/$CGI_DIR/histrep.sh?mode=globalvm",                 "", "", "", "", $type_server );

        menu( "$type_gmenu", "advisorvm",    "Resource Configuration Advisor", "gui-cpu_max_check_vm.html",                                                       "", "", "", "", "$type_server" );
        menu( "$type_gmenu", "gcfgvm",       "Configuration",                  "/$CGI_DIR/detail.sh?host=&server=&lpar=&item=serversvm&entitle=0&none=none",      "", "", "", "", "$type_server" );
        menu( "$type_gmenu", "datastoretop", "Datastores TOP",                 "/$CGI_DIR/detail.sh?host=&server=&lpar=&item=dstr-table-top&entitle=0&none=none", "", "", "", "", "$type_server" );
        menu( "$type_gmenu", "gtop10vm",     "VM TOP",                         "/$CGI_DIR/detail.sh?host=&server=&lpar=cod&item=topten_vm&entitle=0&none=none",   "", "", "", "", "$type_server" );

        # here create vmware global menu
        $vmenu_created = 1    # only once
      }

      my $hmc_url      = urlencode_d($hmc);
      my $hmc_url_hash = $hmc_url;
      $hmc_url_hash =~ s/\#/\%23/g;    # for support hashes in the name

      my $server_url      = urlencode_d($server);
      my $server_url_hash = $server_url;
      $server_url_hash =~ s/\#/\%23/g;    # for support hashes in the server name

      # vmware ESXi
      # vmware vcenter server must public its cluster name
      # if not in cluster then public its vcenter name

      my $cluster_name = "";
      my $name_file    = "$wrkdir/$server/$hmc/my_cluster_name";
      if ( -f $name_file ) {
        if ( open( FC, "< $name_file" ) ) {
          $cluster_name = <FC>;
          close(FC);
          $cluster_name =~ s/\|.*//;
        }
        else {
          error( "Cannot read $name_file: $!" . __FILE__ . ":" . __LINE__ );
        }
      }
      else {
        $name_file = "$wrkdir/$server/$hmc/my_vcenter_name";
        if ( -f $name_file ) {
          if ( open( FC, "< $name_file" ) ) {
            $cluster_name = <FC>;
            close(FC);

            #$cluster_name =~ s/\|.*//;# the 1st is host name
            $cluster_name =~ s/.*\|//;    # the 2nd is vcenter name
          }
          else {
            error( "Cannot read $name_file: $!" . __FILE__ . ":" . __LINE__ );
          }
        }
      }

      # vmware server must public its alias name if non vcenter
      my $alias_name = "";
      if ( $cluster_name eq "" ) {
        $name_file = "$wrkdir/$server/$hmc/vmware_alias_name";
        if ( open( FC, "< $name_file" ) ) {
          $cluster_name = <FC>;
          close(FC);
          $cluster_name =~ s/^[^\|]*\|//;
        }
        else {
          error( "Cannot read $name_file: $!" . __FILE__ . ":" . __LINE__ );
        }
      }
      chomp $cluster_name;

      print "testing update : esxi pool file $wrkdir/$server/$hmc/pool.rrm in cluster $cluster_name\n";    # to set the server as $type_smenu or $type_dmenu;

      my $file_pool      = "$wrkdir/$server/$hmc/pool.rrm";
      my $test_file_pool = $file_pool;
      $test_file_pool =~ s/:/\\\:/g;

      if ( $host_moref_id ne "" ) {
        $host_moref_id =~ s/host_moref_id\.//;    #remove 1st part of 'host_moref_id.host-47'
      }

      my $last_time = `$RRDTOOL last "$file_pool"`;
      chomp $last_time;
      if ( $DEBUG eq 1 ) { print "add to menu $server_menu  : ESXi $server:$hmc\n"; }
      menu( "$server_menu", "$cluster_name", "$server", "CPUpool-pool", "CPU", "/$CGI_DIR/detail.sh?host=$hmc_url_hash&server=$server_url_hash&lpar=pool&item=pool&entitle=$ENTITLEMENT_LESS&gui=1&none=none&moref=$host_moref_id", "$alias_name", $last_time, $type_server );

      if ( $DEBUG eq 1 ) { print "add to menu $server_menu  : $hmc:$server:memory\n"; }
      menu( "$server_menu", "$cluster_name", "$server", "mem", "Memory", "/$CGI_DIR/detail.sh?host=$hmc_url_hash&server=$server_url_hash&lpar=cod&item=memalloc&entitle=$ENTITLEMENT_LESS&gui=1&none=none", "$alias_name", $last_time, $type_server );

      # testing rrdtool for disk item
      my $disk_val = `rrdtool graph test.png --start -1d DEF:disk_R="$test_file_pool":Disk_read:AVERAGE PRINT:disk_R:AVERAGE:%lf`;

      # print "978 \$disk_val ,$disk_val,\n";
      my $item = "vmdiskrw";
      $item = "vmdisk" if $disk_val =~ /NaN|NAN|nan/;
      if ( $DEBUG eq 1 ) { print "add to menu $server_menu  : $hmc:$server:$item\n"; }
      menu( "$server_menu", "$cluster_name", "$server", "Disk", "Disk", "/$CGI_DIR/detail.sh?host=$hmc_url_hash&server=$server_url_hash&lpar=cod&item=$item&entitle=$ENTITLEMENT_LESS&gui=1&none=none", "$alias_name", $last_time, $type_server );

      # testing rrdtool for net item
      my $net_val = `rrdtool graph test.png --start -1d DEF:net_R="$test_file_pool":Network_received:AVERAGE PRINT:net_R:AVERAGE:%lf`;
      $item = "vmnetrw";
      $item = "vmnet" if $net_val =~ /NaN|NAN|nan/;
      if ( $DEBUG eq 1 ) { print "add to menu $server_menu  : $hmc:$server:$item\n"; }
      menu( "$server_menu", "$cluster_name", "$server", "LAN", "LAN", "/$CGI_DIR/detail.sh?host=$hmc_url_hash&server=$server_url_hash&lpar=cod&item=$item&entitle=$ENTITLEMENT_LESS&gui=1&none=none", "$alias_name", $last_time, $type_server );

      my $mode = "esxi";
      $mode = "solo_esxi" if $cluster_name eq "";
      if ( $DEBUG eq 1 ) { print "add to menu $server_menu  : $hmc:$server:Hist reports\n"; }
      menu( "$server_menu", "$cluster_name", "$server", "hreports", "Historical reports", "/$CGI_DIR/histrep.sh?mode=$mode&host=$hmc_url_hash", "", "", $type_server );

      # add VIEWs
      if ( $DEBUG eq 1 ) { print "add to menu $server_menu  : $hmc:$server:Views\n"; }
      menu( "$server_menu", "$cluster_name", "$server", "view", "VIEW", "/$CGI_DIR/detail.sh?host=$hmc_url_hash&server=$server_url_hash&lpar=cod&item=view&entitle=$ENTITLEMENT_LESS&gui=1&none=none", "", $last_time, $type_server );

      # even soliter ESXi can have datacenters & datastores
      my $hmc_dir = "$wrkdir/$server";
      opendir( DIR, "$hmc_dir" ) || error( " directory does not exists : $hmc_dir " . __FILE__ . ":" . __LINE__ ) && next;
      my @all_datacenters = grep /datastore_*/, readdir(DIR);
      closedir(DIR);

      #
      #
      #
      #
      last;
    }
  }

  # save datastore count to a file for later info print
  my $vmware_datastore_count_file = "$tmpdir/vmware_datastore_count_file.txt";
  if ( open( WDC, ">$vmware_datastore_count_file" ) ) {
    print WDC "datastores     : (VMware) $total_datastore_count_in_menu active in menu";
    close WDC;
  }
  else {
    error( " cannot write datastore count to file : $vmware_datastore_count_file " . __FILE__ . ":" . __LINE__ );
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
sub urlencode_d {    # here is ':' for not to be processed
  my $s = shift;

  # $s =~ s/ /+/g;
  $s =~ s/([^a-zA-Z0-9_.!:~*()'\''-])/sprintf("%%%02X", ord($1))/ge;

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
