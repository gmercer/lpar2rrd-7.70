# store WINDOWS data from menu.txt to SQLite database

##### RUN SCRIPT WITHOUT ARGUMENTS:
######
###### . /home/lpar2rrd/lpar2rrd/etc/lpar2rrd.cfg ; $PERL bin/windows_menu2db.pl
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

#my $db_filepath         = "$inputdir/data/data.db";
#my $iostats_dir         = "$inputdir/data/power_iostats";
#my $metadata_file       = "$iostats_dir/conf.json";

################################################################################

my %data_in;
my %data_out;
my $DEBUG = ( exists $ENV{DEBUG} ) ? $ENV{DEBUG} : 0;

################################################################################

# load data source:
my $menu_file = "$tmpdir/menu.txt";
my @menu;

if ( !-f $menu_file ) {
  Xorux_lib::error( "file $menu_file does not exist " . __FILE__ . ":" . __LINE__ ) && exit 1;
}
open FH, "$menu_file" or error( "can't open $menu_file: $! " . __FILE__ . ":" . __LINE__ ) && exit 1;
@menu = <FH>;
close FH;

# print "menu file \n@menu\n";

################################################################################

# fill tables

# save %data_out
#
# my $params = {id => $st_serial, label => $st_name, hw_type => "VIRTUALIZATION TYPE"};
# SQLiteDataWrapper::object2db( $params );
# $params = { id => $st_serial, subsys => "DEVICE", data => $data_out{DEVICE} };
# SQLiteDataWrapper::subsys2db( $params );

# LPAR2RRD:  WINDOWS assignment
# (TODO remove) object: hw_type => "WINDOWS", label => "WINDOWS_Systems", id => "DEADBEEF"
# params: id                    => "DEADBEEF", subsys => "(DOMAIN|VM|SERVER|STORAGE|…)", data => $data_out{(DOMAIN|VM|SERVER|STORAGE|…)}

my $object_hw_type = "WINDOWS";
my $object_label   = "WINDOWS_Systems";
my $object_id      = "WINDOWS";

my $params = { id => $object_id, label => $object_label, hw_type => $object_hw_type };
SQLiteDataWrapper::object2db($params);

########## prepare DOMAIN - SERVER from lines e.g. (if any)

# L:ad.int.xorux.com:HYPERV:3138F59F-11AD-46FB-951C-9C147C98896C:XoruX-master:/lpar2rrd-cgi/detail.sh?host=HYPERV&server=windows/domain_ad.int.xorux.com&lpar=3138F59F-11AD-46FB-951C-9C147C98896C&item=lpar&entitle=0&gui=1&none=none:::H

# in case VM is in hyperv cluster
# L:ad.xorux.com:HVNODE02:55A689CF-BB80-43E4-8C16-7B6EAB059FB3:hvlinux04:/lpar2rrd-cgi/detail.sh?host=HVNODE02&server=windows/domain_ad.xorux.com&lpar=55A689CF-BB80-43E4-8C16-7B6EAB059FB3&item=lpar&entitle=0&gui=1&none=none:MSNET-HVCL::H

# S:ad.int.xorux.com:HYPERV:Totals:Totals:/lpar2rrd-cgi/detail.sh?host=HYPERV&server=windows/domain_ad.int.xorux.com&lpar=pool&item=pool&entitle=0&gui=1&none=none::0:H

my @servers_in_domains = grep { ( $_ =~ /^S:/ ) && ( index( $_, ":Totals:" ) > 0 ) && ( index( $_, "server=windows" ) > 0 ) } @menu;

# print "\@servers_in_domains @servers_in_domains\n";
# exit;

my %domains = ();    # keeps domains & servers under them

foreach (@servers_in_domains) {
  ( undef, my $domain, my $server, undef ) = split( ':', $_ );

  # next if $domain ne "ad.xorux.com";
  # print "93 $domain,$server\n";

  if ( !exists $domains{$domain} ) {
    undef %data_out;
    $data_out{$domain} = { 'label' => $domain };

    $params = { id => $object_id, subsys => "DOMAIN", data => \%data_out };
    print "windows-menu2db.pl: _DB Inserting $params->{subsys} : $data_out{$domain}{label}\n";
    SQLiteDataWrapper::subsys2db($params);
  }
  my @parents = ();
  my $parent  = $domain;
  push @parents, $parent;

  # print "109 \$parent $parent\n";
  undef %data_out;
  my $server_uuid = "$domain" . "_server_" . "$server";
  $data_out{$server_uuid} = { 'label' => $server, 'parents' => \@parents };
  $params = { id => $object_id, subsys => "SERVER", data => \%data_out };
  print "windows-menu2db.pl: _DB Inserting $params->{subsys} : $data_out{$server_uuid}{label}\n";
  SQLiteDataWrapper::subsys2db($params);

  $domains{$domain}{$server} = 1;

  # cycle on storages of this server
  # HDI:ad.xorux.com:HVNODE01:C===double-col===:C===double-col===:/lpar2rrd-cgi/detail.sh?host=HVNODE01&server=windows/domain_ad.xorux.com&lpar=C===double-col===&item=lfd&entitle=0&gui=1&none=none::0:H
  # HDI:ad.xorux.com:HVNODE01:Volume1:Volume1:/lpar2rrd-cgi/detail.sh?host=HVNODE01&server=windows/domain_ad.xorux.com&lpar=Volume1&item=csv&entitle=0&gui=1&none=none::0:H
  my @storages_in_server = grep { ( $_ =~ /^HDI:/ ) && ( index( $_, ":$server:" ) > 0 ) && ( index( $_, "server=windows/domain_$domain" ) > 0 ) } @menu;

  # print "\@storages_in_server\n@storages_in_server\n";
  foreach (@storages_in_server) {
    ( undef, undef, undef, my $storage, undef, my $path, undef ) = split ":", $_;
    ( undef, my $item, undef ) = split "item=", $path;
    $item =~ s/\&.*//g;

    # print "127 \$storage $storage \$path $path\n";
    $storage =~ s/===double-col===/:/g;
    my $storage_uuid = "$server_uuid" . "_storage_" . "$storage" . "_item_" . "$item";

    my @parents = ();
    my $parent  = $domain;
    push @parents, $parent;
    $parent = $server_uuid;
    push @parents, $parent;

    undef %data_out;
    $data_out{$storage_uuid} = { 'label' => $storage, 'parents' => \@parents };
    $params = { id => $object_id, subsys => "STORAGE", data => \%data_out };
    print "windows-menu2db.pl: _DB Inserting $params->{subsys} : $data_out{$storage_uuid}{label}\n";
    SQLiteDataWrapper::subsys2db($params);
  }

  # exit;
}

# cycle on VMs of server or CLUSTER
# L:ad.int.xorux.com:HYPERV:3138F59F-11AD-46FB-951C-9C147C98896C:XoruX-master:/lpar2rrd-cgi/detail.sh?host=HYPERV&server=windows/domain_ad.int.xorux.com&lpar=3138F59F-11AD-46FB-951C-9C147C98896C&item=lpar&entitle=0&gui=1&none=none:::H

# in case VM is in hyperv cluster
# L:ad.xorux.com:HVNODE02:55A689CF-BB80-43E4-8C16-7B6EAB059FB3:hvlinux04:/lpar2rrd-cgi/detail.sh?host=HVNODE02&server=windows/domain_ad.xorux.com&lpar=55A689CF-BB80-43E4-8C16-7B6EAB059FB3&item=lpar&entitle=0&gui=1&none=none:MSNET-HVCL::H

my %clusters = ();    # keeps hyperv clusters

my @vms_in_windows = grep { ( $_ =~ /^L:/ )    && ( index( $_, "server=windows" ) > 0 ) } @menu;
my @s2d_volumes    = grep { ( $_ =~ /^HVOL:/ ) && ( index( $_, "server=windows" ) > 0 ) } @menu;
my @s2d_pds        = grep { ( $_ =~ /^HPD:/ )  && ( index( $_, "server=windows" ) > 0 ) } @menu;
foreach (@vms_in_windows) {
  ( undef, my $domain, my $server, my $vm_uuid, my $vm_label, my $path, my $vm_cluster_name, undef ) = split ":", $_;
  if ( $vm_cluster_name ne "" ) {

    # print "166 \$cluster_name $vm_cluster_name\n";
    if ( !exists $clusters{$vm_cluster_name} ) {
      undef %data_out;
      $data_out{$vm_cluster_name} = { 'label' => $vm_cluster_name };

      $params = { id => $object_id, subsys => "WINDOWS_CLUSTER", data => \%data_out };
      print "windows-menu2db.pl: _DB Inserting $params->{subsys} : $data_out{$vm_cluster_name}{label}\n";
      SQLiteDataWrapper::subsys2db($params);
      $clusters{$vm_cluster_name} = 1;
    }
    my @parents = ();
    my $parent  = $domain;
    push @parents, $parent;

    push @parents, $vm_cluster_name;
    my $server_uuid = "$domain" . "_server_" . "$server";

    $vm_uuid = "$server_uuid" . "_vm_" . "$vm_uuid";

    undef %data_out;
    $data_out{$vm_uuid} = { 'label' => $vm_label, 'parents' => \@parents };

    $params = { id => $object_id, subsys => "CLUSTER_VM", data => \%data_out };
    print "windows-menu2db.pl: _DB Inserting $params->{subsys} : $data_out{$vm_uuid}{label} \n";

    # print Dumper ("184", @parents);
    SQLiteDataWrapper::subsys2db($params);
  }
  else {    # VMs under server
    my @parents = ();
    my $parent  = $domain;
    push @parents, $parent;
    my $server_uuid = "$domain" . "_server_" . "$server";
    $parent = $server_uuid;
    push @parents, $parent;

    $vm_uuid = "$server_uuid" . "_vm_" . "$vm_uuid";
    undef %data_out;
    $data_out{$vm_uuid} = { 'label' => $vm_label, 'parents' => \@parents };

    $params = { id => $object_id, subsys => "VM", data => \%data_out };
    print "windows-menu2db.pl: _DB Inserting $params->{subsys} : $data_out{$vm_uuid}{label} \n";

    # print Dumper ("199", @parents);
    SQLiteDataWrapper::subsys2db($params);
  }
}
foreach (@s2d_volumes) {

  #print "$_";
  #HVOL::s2d:volume02:volume02:/lpar2rrd-cgi/detail.sh?host=cluster_s2d&server=windows&lpar=volume02&item=s2dvolume&entitle=0&gui=1&none=none:s2d::H
  ( undef, undef, my $clu_name, my $vol_name, undef, my $path, undef ) = split ":", $_;

  #print "$vol_name\n";

  if ( exists $clusters{$clu_name} ) {
    my @parents = ();
    my $parent  = $clu_name;
    push @parents, $parent;

    my $vol_uuid = "$clu_name" . "_vol_" . "$vol_name";

    undef %data_out;
    $data_out{$vol_uuid} = { 'label' => $vol_name, 'parents' => \@parents };

    $params = { id => $object_id, subsys => "S2D_VOLUME", data => \%data_out };
    print "windows-menu2db.pl: _DB Inserting $params->{subsys} : $data_out{$vol_uuid}{label} \n";
    SQLiteDataWrapper::subsys2db($params);
  }
}
foreach (@s2d_pds) {

  #print "$_";
  #HPD::s2d:2003:2003:/lpar2rrd-cgi/detail.sh?host=cluster_s2d&server=windows&lpar=2003&item=physdisk&entitle=0&gui=1&none=none:s2d::H
  ( undef, undef, my $clu_name, my $pd_id, undef, my $path, undef ) = split ":", $_;

  #print "$pd_id\n";

  if ( exists $clusters{$clu_name} ) {
    my @parents = ();
    my $parent  = $clu_name;
    push @parents, $parent;

    my $pd_uuid = "$clu_name" . "_pd_" . "$pd_id";

    undef %data_out;
    $data_out{$pd_uuid} = { 'label' => $pd_id, 'parents' => \@parents };

    $params = { id => $object_id, subsys => "S2D_PD", data => \%data_out };
    print "windows-menu2db.pl: _DB Inserting $params->{subsys} : $data_out{$pd_uuid}{label} \n";
    SQLiteDataWrapper::subsys2db($params);
  }
}
