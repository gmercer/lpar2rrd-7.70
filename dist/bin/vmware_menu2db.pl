# store VMWARE data from menu.txt to SQLite database

# use 5.008_008;

##### RUN SCRIPT WITHOUT ARGUMENTS:
######
###### . /home/lpar2rrd/lpar2rrd/etc/lpar2rrd.cfg ; $PERL bin/vmware_menu2db.pl
######

use strict;
use warnings;

use Data::Dumper;

# use JSON qw(decode_json encode_json);
use DBI;

use SQLiteDataWrapper;
use Xorux_lib;

defined $ENV{INPUTDIR} || Xorux_lib::error( " INPUTDIR undefined, probably have not read etc/lpar2rrd.cfg " . __FILE__ . ":" . __LINE__ ) && exit 1;

# data file paths
my $inputdir = $ENV{INPUTDIR};

my $basedir = $ENV{INPUTDIR};
my $wrkdir  = "$basedir/data";
my $tmpdir  = "$basedir/tmp";
if ( defined $ENV{TMPDIR_LPAR} ) {
  $tmpdir = $ENV{TMPDIR_LPAR};
}
my $etcdir = "$inputdir/etc";

my $host_json_file = "$etcdir/web_config/hosts.json";

#my $db_filepath         = "$inputdir/data/data.db";

# if there is mapped OS agent to vmware VM
# FE251C42-CB44-8248-1F2C-27F9D8817B61,/home/lpar2rrd/lpar2rrd/data/Linux--unknown/no_hmc/vm-honza/uuid.txt
my $linux_uuid_name_file = "$wrkdir/vmware_VMs/linux_uuid_name.txt";
my @linux_names          = ();
if ( -f $linux_uuid_name_file ) {
  if ( open my $FH, "$linux_uuid_name_file" ) {
    @linux_names = <$FH>;
    close $FH;
  }
}

# print "48 @linux_names\n";

################################################################################

my %data_in;
my %data_out;
my $DEBUG = ( exists $ENV{DEBUG} ) ? $ENV{DEBUG} : 0;

################################################################################

# load data source:
my $menu_file = "$tmpdir/menu_vmware.txt";
my @menu;

if ( !-f $menu_file ) {
  Xorux_lib::error( "file $menu_file does not exist " . __FILE__ . ":" . __LINE__ ) && exit 1;
}
open my $FH, "$menu_file" or error( "can't open $menu_file: $! " . __FILE__ . ":" . __LINE__ ) && exit 1;
@menu = <$FH>;
close $FH;

# print "menu file \n@menu\n";

### read config file & prepare hash for vmware uuid to push to db for later removal

my %alias_uuid_hash = ();
if ( -f $host_json_file ) {
  ( my $code, my $ref ) = Xorux_lib::read_json("$host_json_file");
  foreach my $alias ( keys %{ $ref->{'platforms'}{'VMware'}{'aliases'} } ) {

    # print Dumper $alias;
    my $uuid = $ref->{'platforms'}{'VMware'}{'aliases'}{$alias}{'uuid'};
    if ( defined $uuid && $uuid ne "" ) {
      $alias_uuid_hash{$alias} = $uuid;
    }
  }
}

# print Dumper %alias_uuid_hash;
# exit;

################################################################################

# fill tables

# save %data_out
#
# my $params = {id => $st_serial, label => $st_name, hw_type => "VIRTUALIZATION TYPE"};
# SQLiteDataWrapper::object2db( $params );
# $params = { id => $st_serial, subsys => "DEVICE", data => $data_out{DEVICE} };
# SQLiteDataWrapper::subsys2db( $params );

# LPAR2RRD: VCENTER assignment
# (TODO remove) object: hw_type => "VMWARE", label => "VMWARE_Systems", id => "DEADBEEF"
# params: id                    => "DEADBEEF", subsys => "(VCENTER|VM|CLUSTER|…)", data => $data_out{(VCENTER|VM|CLUSTER|…)}

my $object_hw_type = "VMWARE";
my $object_label   = "VMWARE_Systems";
my $object_id      = "VMWARE";

my $params = { id => $object_id, label => $object_label, hw_type => $object_hw_type };
SQLiteDataWrapper::object2db($params);

########## prepare VCENTER from lines e.g. (if any)

# V:10.22.11.10:Totals:/lpar2rrd-cgi/detail.sh?host=10.22.11.10&server=vmware_eb6102a7-1fa0-4376-acbb-f67e34a2212c_28&lpar=nope&item=hmctotals&entitle=0&gui=1&none=none:::Hosting::V:
my @vcenters = grep { $_ =~ /^V:/ && index( $_, ":Totals:" ) > 0 } @menu;

# print "\@vcenters @vcenters\n";
# exit;

my $vcenter_uuid;
my $vcenter_label;
my $vcenter_ip;

# clean VM folders in all vcenters
my $var = { hw_type => 'VMWARE', subsys => 'VM_FOLDER' };
SQLiteDataWrapper::deleteItems($var);

# clean DATASTORE folders in all vcenters
$var = { hw_type => 'VMWARE', subsys => 'DATASTORE_FOLDER' };
SQLiteDataWrapper::deleteItems($var);

# clean RESOURCEPOOL folders in all vcenters
$var = { hw_type => 'VMWARE', subsys => 'RESOURCEPOOL_FOLDER' };
SQLiteDataWrapper::deleteItems($var);

# what else?: VM can have more esxi parents if vmotion
# params: {uuid => 'DEADBEEF', relations => 0} # relations flag optional, if 1 then delete
#SQLiteDataWrapper::deleteItem($var);

foreach (@vcenters) {
  ( undef, $vcenter_ip, undef, $vcenter_uuid, undef, undef, $vcenter_label, undef ) = split( ':', $_ );

  #print "$vcenter_ip,$vcenter_uuid,$vcenter_label\n";
  ( undef, $vcenter_uuid, undef ) = split( '\&', $vcenter_uuid );
  $vcenter_uuid =~ s/server=vmware_//;

  # print "$vcenter_ip,$vcenter_uuid,$vcenter_label\n";
  undef %data_out;
  $data_out{$vcenter_uuid}{label} = $vcenter_label;
  if ( exists $alias_uuid_hash{$vcenter_label} ) {
    my @my_arr = ();
    push @my_arr, $alias_uuid_hash{$vcenter_label};

    # this is probably for later removal
    $data_out{$vcenter_uuid}{hostcfg} = \@my_arr;
  }
  $params = { id => $object_id, subsys => "VCENTER", data => \%data_out };
  print "vmware-menu2db.pl : _DB Inserting $params->{subsys} : $data_out{$vcenter_uuid}{label}\n";
  SQLiteDataWrapper::subsys2db($params);

  ########## prepare CLUSTER from lines e.g. (if any)
  # A:10.22.11.10:cluster_New Cluster:Totals:/lpar2rrd-cgi/detail.sh?host=cluster_domain-c87&server=vmware_eb6102a7-1fa0-4376-acbb-f67e34a2212c_28&lpar=nope&item=cluster&entitle=0&gui=1&none=none::Hosting::V:
  my @clusters = grep { $_ =~ /^A:/ && index( $_, ":Totals:" ) > 0 && index( $_, "$vcenter_uuid" ) > 0 } @menu;

  # print "\@clusters\n @clusters\n";
  #exit;

  my $vcenter_host;
  my $cluster_moref;
  my $cluster_uuid;
  my $cluster_label;

  #my $vcenter_ip;
  # my %folder_uuid = (); # no put it under cluster

  # always read newer file from cluster
  my $last_vm_folders_file = "";

  foreach (@clusters) {
    ( undef, $vcenter_host, $cluster_label, undef, $cluster_moref, undef ) = split( ':', $_ );

    # print "$cluster_moref,$cluster_label\n";
    ( undef, $cluster_moref, undef ) = split( 'host=', $cluster_moref );
    ( $cluster_moref, undef ) = split( '&', $cluster_moref );

    # cluster moref is unique only in vcenter so it must hold vcenter uuid
    $cluster_uuid = "$vcenter_uuid" . "_" . "$cluster_moref";

    my @parents = ();
    my $parent  = $vcenter_uuid;
    push @parents, $parent;

    # print "$cluster_uuid,$cluster_label,$cluster_moref\n";
    undef %data_out;
    $data_out{$cluster_uuid} = { 'label' => $cluster_label, 'parents' => \@parents };
    $params                  = { id => $object_id, subsys => "CLUSTER", data => \%data_out };
    print "vmware-menu2db.pl : _DB Inserting $params->{subsys} : $data_out{$cluster_uuid}{label}\n";
    SQLiteDataWrapper::subsys2db($params);

    ########## prepare ESXi servers in cluster and their VMs

    # S:cluster_New Cluster:10.22.11.14:CPUpool-pool:CPU pool:/lpar2rrd-cgi/detail.sh?host=10.22.11.10&server=10.22.11.14&lpar=pool&item=pool&entitle=0&gui=1&none=none::1567116180:V:
    # next is ESXi non cluster, is directly under vcenter, it is solved later in this script
    # S:e869ceaf-935b-45de-bd56-ff12f835d7a9_3:srv-esxi-vukv.skoda.cz:CPUpool-pool:CPU:/lpar2rrd-cgi/detail.sh?host=srv-vcsa-vukv.skoda.cz&server=srv-esxi-vukv.skoda.cz&lpar=pool&item=pool&entitle=0&gui=1&none=none::1612218680:V:
    #
    #my @esxis = grep { $_ =~ /^S:/ && index($_, ":CPUpool-pool:") >0 && index($_, ":$cluster_label:") >0 && index($_, "host=$vcenter_host&") >0} @menu;
    my @esxis = grep { $_ =~ /^S:$cluster_label:/ && index( $_, ":CPUpool-pool:" ) > 0 && index( $_, "host=$vcenter_host&" ) > 0 } @menu;

    # print "\@esxis\n @esxis\n";
    # next;

    my $esxi_moref;
    my $esxi_uuid;
    my $esxi_label;
    my $esxi_folder_uuid = "esxi_folder_uuid";
    my $vm_folder_uuid   = "vm_folder_uuid";

    ########## prepare ESXI & VM folder for servers

    if (@esxis) {

      # it is just folder ESXI but we define it as subsys
      $esxi_folder_uuid = "$cluster_uuid" . "_" . "ESXI";

      my @parents = ();
      push @parents, $cluster_uuid;
      push @parents, $vcenter_uuid;

      # print "218 $esxi_folder_uuid\n";
      undef %data_out;
      $data_out{$esxi_folder_uuid} = { 'label' => "ESXI", 'parents' => \@parents };
      $params = { id => $object_id, subsys => "ESXI", data => \%data_out };
      print "vmware-menu2db.pl : _DB Inserting $params->{subsys} : $data_out{$esxi_folder_uuid}{label}\n";

      # TODO remove $esxi_folder entirely
      #SQLiteDataWrapper::subsys2db( $params );

      #### prepare folder VM as subsys
      $vm_folder_uuid = "$cluster_uuid" . "_" . "VM";

      @parents = ();
      push @parents, $cluster_uuid;
      push @parents, $vcenter_uuid;

      # print "254 $vm_folder_uuid\n";
      undef %data_out;
      $data_out{$vm_folder_uuid} = { 'label' => "VM", 'parents' => \@parents };
      $params = { id => $object_id, subsys => "VM", data => \%data_out };

      # following is not necessary - especially if there is no VM without own folder
      # print "vmware-menu2db.pl : _DB Inserting $params->{subsys} : $data_out{$vm_folder_uuid}{label}\n";
      # SQLiteDataWrapper::subsys2db( $params );
    }

    ########## prepare VM folders

    my $vm_folder_file   = "$wrkdir/vmware_$vcenter_uuid/$cluster_moref/vm_folder_path.json";
    my $vm_folder_pathes = "";
    my %folder_uuid      = ();                                                                  # to be vcenter level ? NO, still it is organized under cluster but in vSphere is organized totally under datacenter
    my %vm_folder_labels = ();
    my %vm_folder_subsys = ();

    if ( @esxis && -f $vm_folder_file ) {

      # print "147 \$vm_folder_file $vm_folder_file\n";
      # next line is not necessary as we organize VM folders under cluster
      if ( $last_vm_folders_file eq "" || ( stat($vm_folder_file) )[9] > ( stat($last_vm_folders_file) )[9] ) {
        $last_vm_folders_file = $vm_folder_file;
        $vm_folder_pathes     = Xorux_lib::read_json($vm_folder_file);

        # print Dumper($vm_folder_pathes);

        # find label and subsys (VM_FOLDERx) for each folder, except VM i.e. root VM folder

        foreach my $folder_moref ( keys %$vm_folder_pathes ) {
          ( my $parent_moref, my $folder_label ) = split ",", $vm_folder_pathes->{$folder_moref};

          # print "  $folder_moref has $parent_moref_own $folder_label_own\n";
          # group-v133 has parent group-v3,Development # group-v3 is not key in this hash -> is top level, parent is cluster
          # group-v473 has parent group-v133,Devel OL
          my $folder_level_count = 1;
          while ( defined $vm_folder_pathes->{$parent_moref} ) {
            ( $parent_moref, undef ) = split ",", $vm_folder_pathes->{$parent_moref};
            $folder_level_count++;
          }
          $vm_folder_labels{$folder_moref} = $folder_label;
          $vm_folder_subsys{$folder_moref} = "VM_FOLDER$folder_level_count";
        }

        # print Dumper (\%$vm_folder_pathes, \%vm_folder_labels, \%vm_folder_subsys);

        # prepare folders' uuid
        foreach my $folder_moref ( keys %$vm_folder_pathes ) {
          my $value = $vm_folder_pathes->{$folder_moref};

          # print "  $folder_moref has parent $value\n";
          # group-v133 has parent group-v3,Development # group-v3 is not key in this hash -> is top level, parent is cluster
          # group-v473 has parent group-v133,Devel OL
          ( my $parent_moref, my $folder_label ) = split ",", $value;

          #if (exists $vm_folder_pathes->{$parent_moref}) {
          $folder_uuid{$folder_moref} = "$cluster_uuid" . "_folder_" . "$folder_moref";

          #}
          #else {
          # top level folder is cluster
          #  $folder_uuid{$folder_moref} =  "$cluster_uuid";
          #}
        }

        # print Dumper(\%folder_uuid);
        foreach my $folder_moref ( keys %$vm_folder_pathes ) {
          my $folder_label  = "VM";
          my $folder_subsys = $vm_folder_subsys{$folder_moref};
          $folder_subsys = "VM_FOLDER" if !defined $folder_subsys;

          my $value = $vm_folder_pathes->{$folder_moref};
          ( my $parent_moref, $folder_label ) = split ",", $value;
          my $this_folder_uuid = $folder_uuid{$folder_moref};

          my @parents = ();

          # push @parents,$this_folder_uuid; # there must be also its own uuid # DK no
          my $parent = $folder_uuid{$parent_moref};

          # $parent     = "$cluster_uuid" if ! defined $parent; # top level folder is cluster
          # $parent     = "$vm_folder_uuid" if ! defined $parent; # top level folder is VM

          push @parents, $parent if defined $parent;
          push @parents, $cluster_uuid;
          push @parents, $vcenter_uuid;

          # print "186 \$folder_moref $folder_moref \$parent_moref $parent_moref \$folder_label $folder_label \$this_folder_uuid $this_folder_uuid\n";
          undef %data_out;
          $data_out{$this_folder_uuid} = { 'label' => $folder_label, 'parents' => \@parents };

          # $params = { id => $object_id, subsys => "$folder_subsys", data => \%data_out };
          $params = { id => $object_id, subsys => "VM_FOLDER", data => \%data_out };

          my @vms = grep { $_ =~ /^L:/ && index( $_, "host=$vcenter_host&" ) > 0 && index( $_, "$folder_label/" ) > 0 } @menu;
          if (@vms) {    #do not save vm_folder, where is NO vm
            no warnings 'utf8';
            print "vmware-menu2db.pl : _DB Inserting $params->{subsys} : $data_out{$this_folder_uuid}{label} \n";

            # print "329 \@vms @vms\n";
            # print Dumper (@parents);
            SQLiteDataWrapper::subsys2db($params);
          }
        }
      }
    }

    foreach (@esxis) {
      ( undef, undef, $esxi_label, undef ) = split( ':', $_ );
      $esxi_uuid = "$cluster_uuid" . "_esxi_" . "$esxi_label";    # have nothing better
                                                                  # can you rather try host_moref_id.host-10 ???

      my @parents = ();
      push @parents, $cluster_uuid;
      push @parents, $vcenter_uuid;

      # print "$esxi_uuid,$esxi_label\n";
      undef %data_out;
      $data_out{$esxi_uuid} = { 'label' => $esxi_label, 'parents' => \@parents };
      $params               = { id => $object_id, subsys => "ESXI", data => \%data_out };
      print "vmware-menu2db.pl : _DB Inserting $params->{subsys} : $data_out{$esxi_uuid}{label} \n";
      SQLiteDataWrapper::subsys2db($params);

      ########## prepare VM of ESXiserver in cluster

      # L:cluster_New Cluster:10.22.11.8:501c80d4-b12f-d991-8af6-91f0ad5275cb:vm-david:/lpar2rrd-cgi/detail.sh?host=10.22.11.10&server=10.22.11.8&lpar=501c80d4-b12f-d991-8af6-91f0ad5275cb&item=lpar&entitle=0&gui=1&none=none::Hosting:V::Development/Devel OL/:group-v473:
      # my @vms = grep { $_ =~ /^L:/ && index($_, ":$cluster_label:") >0 && index($_, "host=$vcenter_host&") >0 && index($_, "server=$esxi_label&") >0} @menu;
      my @vms = grep { $_ =~ /^L:$cluster_label:/ && index( $_, "host=$vcenter_host&" ) > 0 && index( $_, "server=$esxi_label&" ) > 0 } @menu;

      # print "\@vms\n @vms\n";
      # next;

      my $vm_uuid;
      my $vm_label;
      my $parent_folder_moref;

      foreach (@vms) {
        ( undef, undef, undef, $vm_uuid, $vm_label, undef, undef, undef, undef, undef, undef, $parent_folder_moref, undef ) = split( ':', $_ );
        $vm_uuid = "$vcenter_uuid" . "_vm_" . "$vm_uuid";    # is unique only in vcenter

        my $folder_name = "VM";
        my @parents     = ();

        # push @parents,$vm_uuid; # there must be also its own uuid # DK no

        #print "283 \$parent_folder_moref $parent_folder_moref\n";
        if ( defined $parent_folder_moref && $parent_folder_moref ne "" && exists $vm_folder_subsys{$parent_folder_moref} ) {
          push @parents, $folder_uuid{$parent_folder_moref};
          $folder_name = $vm_folder_subsys{$parent_folder_moref};
        }

        # if not in folder, then parent is cluster
        # if (defined $parent_folder_moref && $parent_folder_moref ne "" && !exists $vm_folder_subsys{$parent_folder_moref}) {
        #   push @parents, $vm_folder_uuid;
        #   $folder_name = "VM";
        # /}

        # print "323 \$parent_folder_moref $parent_folder_moref \$vm_label $vm_label \$parent $parent\n";
        push @parents, $esxi_uuid;
        push @parents, $cluster_uuid;
        push @parents, $vcenter_uuid;

        undef %data_out;
        $data_out{$vm_uuid} = { 'label' => $vm_label, 'parents' => \@parents };

        # print "349 $vm_uuid,$vm_label\n";
        # test if mapped OS agent
        if ( my ($matched) = grep /\/$vm_label\//, @linux_names ) {    # get 1st match
                                                                       # print "368 $matched\n";
          ( my $linux_uuid, undef ) = split( ",", $matched );
          $data_out{$vm_uuid}{mapped_agent} = $linux_uuid;
        }

        # at first remove item and all relations
        my $var = { uuid => $vm_uuid, relations => 1 };
        SQLiteDataWrapper::deleteItem($var);

        $params = { id => $object_id, subsys => "VM", data => \%data_out };
        print "vmware-menu2db.pl : _DB Inserting $params->{subsys} : $data_out{$vm_uuid}{label} \n";

        # print Dumper ("342", @parents);
        SQLiteDataWrapper::subsys2db($params);
      }
    }

    ########## prepare RP folders & RP

    # following file contains info about all RPs in cluster
    my $rp_file = "$wrkdir/vmware_$vcenter_uuid/$cluster_moref/rp_folder_path.json";
    my $rp_pathes;
    my @rpools = ();    # just for easy testing

    if ( -f $rp_file ) {

      # print "267 \$rp_file $rp_file\n";
      $rp_pathes = Xorux_lib::read_json($rp_file);

      # print Dumper($rp_pathes);

      if ( open my $fgrp, "$rp_file" ) {
        @rpools = <$fgrp>;
        close $fgrp;
      }
      else {
        error( "can't open $rp_file: $! " . __FILE__ . ":" . __LINE__ );
      }

      # print Dumper(@rpools);
      #{
      #  "resgroup-423" : "resgroup-139,Dev - child",
      #  "resgroup-141" : "resgroup-88,Test",
      #  "resgroup-140" : "resgroup-88,User-VMs",
      #  "resgroup-422" : "resgroup-88,trash",
      #  "resgroup-285" : "resgroup-141,Test in test",
      #  "resgroup-138" : "resgroup-88,Production",
      #  "resgroup-143" : "resgroup-88,Production-DMZ",
      #  "resgroup-142" : "resgroup-88,DMZ",
      #  "resgroup-139" : "resgroup-88,Development"
      #}  RP-moref         parentRP-moref, name

      # prepare DB definition for RP alone or RP alone & folder (parent)
      foreach my $rp_moref ( keys %$rp_pathes ) {

        # print "  $rp_moref has parent $value\n";
        # group-141 has parent group-88 # group-88 is not key in this hash -> is top level, parent is cluster (rp folder)
        # group-141 is parent of group-285 Test in test
        # group-423 has parent group-139 Development
        # group-423 is not parent for any group

        # rp parent is either cluster or resourcepool-folder
        ( my $parent_moref, my $rp_label ) = split ",", $rp_pathes->{$rp_moref};
        my $parent = $rp_pathes->{$parent_moref};
        if ( !defined $parent ) {
          $parent = "$cluster_uuid";    # if exists $rp_folder_pathes->{$parent_moref};
        }
        else {
          $parent = "$vcenter_uuid" . "_" . "$parent_moref";
        }

        # rp is either alone rp or parent for other rp
        my $rp_type = "RESOURCEPOOL";
        if ( grep /$rp_moref,/, @rpools ) {
          $rp_type = "RESOURCEPOOL_FOLDER";
        }

        my @parents = ();
        push @parents, $vcenter_uuid;
        push @parents, $cluster_uuid;
        push @parents, $parent;

        # print "186 \$folder_moref $folder_moref \$parent_moref $parent_moref \$folder_label $folder_label \$this_folder_uuid $this_folder_uuid\n";
        undef %data_out;
        my $rp_uuid = "$vcenter_uuid" . "_" . "$rp_moref";
        $data_out{$rp_uuid} = { 'label' => $rp_label, 'parents' => \@parents };
        $params             = { id => $object_id, subsys => $rp_type, data => \%data_out };
        print "vmware-menu2db.pl : _DB Inserting $params->{subsys} : $rp_uuid $rp_type $data_out{$rp_uuid}{label} \n";
        SQLiteDataWrapper::subsys2db($params);
      }
    }
  }

  # non cluster ESXi, is directly under vcenter, create fake cluster 'NOCLUSTER'
  # S:e869ceaf-935b-45de-bd56-ff12f835d7a9_3:srv-esxi-vukv.skoda.cz:CPUpool-pool:CPU:/lpar2rrd-cgi/detail.sh?host=srv-vcsa-vukv.skoda.cz&server=srv-esxi-vukv.skoda.cz&lpar=pool&item=pool&entitle=0&gui=1&none=none::1612218680:V:

  my @vc_esxis = grep { $_ =~ /^S:$vcenter_uuid:/ && index( $_, ":CPUpool-pool:" ) > 0 } @menu;

  # print "\@vc_esxis\n @vc_esxis\n";
  if ( (@vc_esxis) && ( scalar @vc_esxis > 0 ) ) {

    my $cluster_moref = "cluster_domain-ccc111";    #fake
    my $cluster_label = "NOCLUSTER";                #fake

    # cluster moref is unique only in vcenter so it must hold vcenter uuid
    $cluster_uuid = "$vcenter_uuid" . "_" . "$cluster_moref";

    my @parents = ();
    my $parent  = $vcenter_uuid;
    push @parents, $parent;

    # print "$cluster_uuid,$cluster_label,$cluster_moref\n";
    undef %data_out;
    $data_out{$cluster_uuid} = { 'label' => $cluster_label, 'parents' => \@parents };
    $params                  = { id => $object_id, subsys => "CLUSTER", data => \%data_out };
    print "vmware-menu2db.pl : _DB Inserting $params->{subsys} : $data_out{$cluster_uuid}{label}\n";
    SQLiteDataWrapper::subsys2db($params);
  }

  foreach (@vc_esxis) {
    ( undef, undef, my $esxi_label, undef ) = split( ':', $_ );
    my $esxi_uuid = "$vcenter_uuid" . "_esxi_" . "$esxi_label";    # have nothing better
                                                                   # can you rather try host_moref_id.host-10 ???

    my @parents = ();
    push @parents, $cluster_uuid;
    push @parents, $vcenter_uuid;

    # print "$esxi_uuid,$esxi_label\n";
    undef %data_out;
    $data_out{$esxi_uuid} = { 'label' => $esxi_label, 'parents' => \@parents };
    $params               = { id => $object_id, subsys => "ESXI", data => \%data_out };
    print "vmware-menu2db.pl : _DB Inserting $params->{subsys} : $data_out{$esxi_uuid}{label} \n";
    SQLiteDataWrapper::subsys2db($params);

    ########## prepare VM of ESXiserver no cluster in vcenter

    # L::srv-esxi-vukv.skoda.cz:500397b9-9e6b-a979-eb36-08a3fd70549d:Win10Matlab2SSD:/lpar2rrd-cgi/detail.sh?host=srv-vcsa-vukv.skoda.cz&server=srv-esxi-vukv.skoda.cz&lpar=500397b9-9e6b-a979-eb36-08a3fd70549d&item=lpar&entitle=0&gui=1&none=none::vcenter_Vukv:V:::
    # my @vms = grep { $_ =~ /^L:/ && index($_, ":$cluster_label:") >0 && index($_, "host=$vcenter_host&") >0 && index($_, "server=$esxi_label&") >0} @menu;
    my @vms = grep { $_ =~ /^L:/ && index( $_, "server=$esxi_label&" ) > 0 } @menu;

    # print "\@vms\n @vms\n";
    # next;

    my $vm_uuid;
    my $vm_label;
    my $parent_folder_moref;
    my %vm_folder_subsys = ();
    my %folder_uuid      = ();
    my $vm_folder_uuid   = "vm_folder_uuid";

    foreach (@vms) {
      ( undef, undef, undef, $vm_uuid, $vm_label, undef, undef, undef, undef, undef, undef, $parent_folder_moref, undef ) = split( ':', $_ );
      $vm_uuid = "$vcenter_uuid" . "_vm_" . "$vm_uuid";    # is unique only in vcenter

      my $folder_name = "VM";
      my @parents     = ();

      # push @parents,$vm_uuid; # there must be also its own uuid # Dd no

      #print "283 \$parent_folder_moref $parent_folder_moref\n";
      if ( defined $parent_folder_moref && $parent_folder_moref ne "" && exists $vm_folder_subsys{$parent_folder_moref} ) {
        push @parents, $folder_uuid{$parent_folder_moref};
        $folder_name = $vm_folder_subsys{$parent_folder_moref};
      }

      # if not in folder, then parent is cluster
      # if (defined $parent_folder_moref && $parent_folder_moref ne "" && !exists $vm_folder_subsys{$parent_folder_moref}) {
      #   push @parents, $vm_folder_uuid;
      #   $folder_name = "VM";
      # }

      # print "323 \$parent_folder_moref $parent_folder_moref \$vm_label $vm_label \$parent $parent\n";
      push @parents, $esxi_uuid;
      push @parents, $cluster_uuid;
      push @parents, $vcenter_uuid;

      undef %data_out;
      $data_out{$vm_uuid} = { 'label' => $vm_label, 'parents' => \@parents };

      # print "349 $vm_uuid,$vm_label\n";
      # test if mapped OS agent
      if ( my ($matched) = grep /\/$vm_label\//, @linux_names ) {    # get 1st match
                                                                     # print "368 $matched\n";
        ( my $linux_uuid, undef ) = split( ",", $matched );
        $data_out{$vm_uuid}{mapped_agent} = $linux_uuid;
      }

      $params = { id => $object_id, subsys => "VM", data => \%data_out };
      print "vmware-menu2db.pl : _DB Inserting $params->{subsys} : $data_out{$vm_uuid}{label} \n";

      # print Dumper ("342", @parents);
      SQLiteDataWrapper::subsys2db($params);
    }
  }

  ########### prepare DATACENTER from lines e.g. (if any)

  # Z:10.22.11.10:datastore_DC:SAN-Comp-development:/lpar2rrd-cgi/detail.sh?host=datastore_datacenter-2&server=vmware_eb6102a7-1fa0-4376-acbb-f67e34a2212c_28&lpar=591c40de-576c4922-9ce2-e4115bd41b18&item=datastore&entitle=0&gui=1&none=none::Hosting::V:Compellent/SAN dev pro/:group-s326:
  my @datastores = grep { $_ =~ /^Z:/ && index( $_, "item=datastore" ) > 0 && index( $_, "$vcenter_uuid" ) > 0 } @menu;

  # print "\@datastores\n @datastores\n";
  # next;

  my $datacenter_uuid;
  my $datacenter_label;
  my $datacenter_folder;
  my $datacenter_moref;

  my %datacenters = ();

  # pick up datacenters
  foreach (@datastores) {
    ( undef, undef, $datacenter_label, undef, $datacenter_moref, undef ) = split ":",     $_;
    ( undef, $datacenter_moref, undef )                                  = split "host=", $datacenter_moref;
    ( $datacenter_moref, undef )                                         = split "&",     $datacenter_moref;
    $datacenters{$datacenter_moref} = $datacenter_label;
  }

  # print Dumper(%datacenters);

  foreach ( keys %datacenters ) {

    # print "key $_\n";
    $datacenter_uuid  = $_;
    $datacenter_uuid  = "$vcenter_uuid" . "_" . "$datacenter_uuid";
    $datacenter_label = $datacenters{$_};

    my @parents = ();
    my $parent  = $vcenter_uuid;
    push @parents, $parent;

    # print "$datacenter_uuid,$datacenter_label\n";
    undef %data_out;
    $data_out{$datacenter_uuid} = { 'label' => $datacenter_label, 'parents' => \@parents };
    $params                     = { id => $object_id, subsys => "DATACENTER", data => \%data_out };
    print "vmware-menu2db.pl : _DB Inserting $params->{subsys} : $data_out{$datacenter_uuid}{label} \n";
    SQLiteDataWrapper::subsys2db($params);

    ########## prepare DS folders

    my $ds_folder_file   = "$wrkdir/vmware_$vcenter_uuid/$datacenter_moref/ds_folder_path.json";
    my $ds_folder_pathes = "";
    my %folder_uuid      = ();

    if ( -f $ds_folder_file ) {

      # print "341 \$ds_folder_file $ds_folder_file\n";
      $ds_folder_pathes = Xorux_lib::read_json($ds_folder_file);

      # print Dumper($ds_folder_pathes);

      # prepare folders' uuid
      foreach my $folder_moref ( keys %$ds_folder_pathes ) {
        my $value = $ds_folder_pathes->{$folder_moref};

        # print "  $folder_moref has parent $value\n";
        # group-s236 has parent group-s5,3PAR # group-s5 is not key in this hash -> is top level, parent is datacenter
        # group-s326 has parent group-s237,SAN dev pro
        # group-s237 has parent group-s5,Compellent
        ( my $parent_moref, my $folder_label ) = split ",", $value;
        $folder_uuid{$folder_moref} = "$datacenter_uuid" . "_folder_" . "$folder_moref";
      }

      # print Dumper(\%folder_uuid);
      foreach my $folder_moref ( keys %$ds_folder_pathes ) {
        my $value = $ds_folder_pathes->{$folder_moref};
        ( my $parent_moref, my $folder_label ) = split ",", $value;
        my $this_folder_uuid = $folder_uuid{$folder_moref};

        my @parents = ();
        my $parent  = $folder_uuid{$parent_moref};
        $parent = "$datacenter_uuid" if !defined $parent;    # top level folder is datacenter
        push @parents, $parent;
        push @parents, $vcenter_uuid;

        # print "365 \$folder_moref $folder_moref \$parent_moref $parent_moref \$folder_label $folder_label \$this_folder_uuid $this_folder_uuid\n";
        undef %data_out;
        $data_out{$this_folder_uuid} = { 'label' => $folder_label, 'parents' => \@parents };
        $params                      = { id => $object_id, subsys => "DATASTORE_FOLDER", data => \%data_out };
        print "vmware-menu2db.pl : _DB Inserting $params->{subsys} : $data_out{$this_folder_uuid}{label} \n";
        SQLiteDataWrapper::subsys2db($params);
      }
    }

    #
    ########## prepare datastores of DATACENTER in vCenter
    #
    foreach (@datastores) {
      next if index( $_, ":$datacenter_label:" ) < 0;

      # Z:10.22.11.10:datastore_DC:SAN-Comp-development:/lpar2rrd-cgi/detail.sh?host=datastore_datacenter-2&server=vmware_eb6102a7-1fa0-4376-acbb-f67e34a2212c_28&lpar=591c40de-576c4922-9ce2-e4115bd41b18&item=datastore&entitle=0&gui=1&none=none::Hosting::V:Compellent/SAN dev pro/:group-s326:
      ( undef, undef, undef, my $datastore_label, my $datastore_uuid, undef, undef, undef, undef, my $folder, my $parent_folder_moref, undef ) = split ":", $_;
      $datastore_label =~ s/===double-col===/:/g;

      ( my $datacenter, undef, $datastore_uuid, undef ) = split "&", $datastore_uuid;
      $datastore_uuid =~ s/lpar=//;
      my $only_datastore_uuid = $datastore_uuid;
      $datastore_uuid = "$vcenter_uuid" . "_ds_" . "$datastore_uuid";
      ( undef, $datacenter, undef ) = split "host=", $datacenter;

      # read volume id for stor2rrd
      my $id_file = "$wrkdir/vmware_$vcenter_uuid/$datacenter/$only_datastore_uuid.disk_uids";

      # print "560 \$id_file $id_file\n";
      my $disk_uids = "";
      if ( -f $id_file ) {
        if ( open my $fhid, "$id_file" ) {
          $disk_uids = <$fhid>;

          # print "565 \$disk_uids $disk_uids\n";
          close $fhid;
        }
        else {
          Xorux_lib::error( "cannot read file $id_file " . __FILE__ . ":" . __LINE__ ) && next;
        }
      }
      my @parents = ();
      my $parent  = $datacenter_uuid;
      if ( defined $parent_folder_moref && $parent_folder_moref ne "" && exists $folder_uuid{$parent_folder_moref} ) {
        $parent = $folder_uuid{$parent_folder_moref};
      }

      push @parents, $parent;
      push @parents, $vcenter_uuid;
      push @parents, $datacenter_uuid;

      # print "$datastore_uuid,$datastore_label,$folder\n";
      undef %data_out;
      $data_out{$datastore_uuid} = { 'label' => $datastore_label, 'parents' => \@parents };
      if ( $disk_uids ne "" ) {
        $data_out{$datastore_uuid}{disk_uids} = $disk_uids;
      }
      $params = { id => $object_id, subsys => "DATASTORE", data => \%data_out };
      print "vmware-menu2db.pl : _DB Inserting $params->{subsys} : $data_out{$datastore_uuid}{label} \n";
      SQLiteDataWrapper::subsys2db($params);
    }
  }
}

# non vcenters: not supported yet

