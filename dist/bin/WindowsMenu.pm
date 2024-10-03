# WindowsMenu.pm
# page types and associated tools for generating front-end menu and tabs for Windows

package WindowsMenu;

use strict;
use warnings;

use JSON;
use Data::Dumper;
use Xorux_lib;

#use WindowsDataWrapper;
#use PowerDataWrapper;
my @page_types = ();

my $basedir = $ENV{INPUTDIR};
my $wrkdir  = $basedir . "/data";

################################################################################

if ( defined $ENV{XORMON} && $ENV{XORMON} ) {
  my $file = "$basedir/etc/links_windows.json";
  @page_types = @{ Xorux_lib::read_json($file) if ( -e $file ) };
  require SQLiteDataWrapper;
}

################################################################################

sub create_folder {
  my $title  = shift;
  my %folder = ( "folder" => "true", "title" => $title, children => [] );

  return \%folder;
}

sub create_page {
  my $title = shift;
  my $url   = shift;
  my %page  = ( "title" => $title, "str" => $title, "href" => $url );

  if ( $title eq 'Heatmap' ) {
    $page{extraClasses} = 'boldmenu';
  }

  return \%page;
}

sub get_url {

  # accepts a hash with named parameters: type, and respective url_params
  my ($args) = @_;

  #print STDERR Dumper $args;
  my $url;
  foreach my $page_type (@page_types) {
    $args->{type} = lc( $args->{type} );
    if ( $page_type->{type} eq $args->{type} ) {
      $url =
          $page_type->{url_base} =~ /\.html$/
        ? $page_type->{url_base}
        : "$page_type->{url_base}?platform=$page_type->{platform}&type=$page_type->{type}";

      foreach my $param ( @{ $page_type->{url_params} } ) {
        $url .= "&$param=$args->{$param}";
      }
      last;
    }
  }

  return $url;
}

sub get_tabs {
  my $type = shift;

  for my $page_type (@page_types) {
    if ( $page_type->{type} eq $type ) {
      return $page_type->{tabs};
    }
  }
  return ();
}

sub get_vcenter_host_name {
  my $vcenter_uuid = shift;

  my $vcenter_file_name_path = "$wrkdir/$vcenter_uuid/*/vcenter_name_*";
  my @file_names             = `ls $vcenter_file_name_path`;
  my $vcenter_host_name      = "unknown_host";
  if ( defined $file_names[0] && $file_names[0] ne "" ) {

    # /home/lpar2rrd/lpar2rrd/data/vmware_eb6102a7-1fa0-4376-acbb-f67e34a2212c_28/cluster_domain-c214/vcenter_name_10.22.11.10
    ( undef, $vcenter_host_name ) = split( "vcenter_name_", $file_names[0] );
    chomp $vcenter_host_name;
  }
  else {
    print STDERR "cannot find vcenter name for $vcenter_uuid" . __FILE__ . ":" . __LINE__;
  }
  return $vcenter_host_name;
}

################################################################################

# expects hash as parameter : { type => "page_type", uid => "abcd1234_uid" }
sub url_new_to_old {
  my $out       = "";
  my $in        = shift;
  my $page_type = "";
  my $uid       = "";
  $page_type = $in->{type} if defined $in->{type};
  $uid       = $in->{id}   if defined $in->{id};
  if ( $page_type eq "pool" ) {

    # new $QUERY_STRING platform=Windows&type=pool&id=ad.xorux.com_server_DC
    # old $QUERY_STRING host=DC&server=windows/domain_ad.xorux.com&lpar=pool&item=pool&entitle=0&gui=1&none=none&_=1611133576322
    ( my $server, my $host ) = split "_server_", $uid;
    $server = "windows/domain_" . $server;
    return {
      url_base => '',
      params   => {
        host   => $host,
        server => $server,
        lpar   => 'pool',
        item   => 'pool'
      }
    };
  }
  elsif ( $page_type eq "wstorage" ) {

    #$QUERY_STRING platform=Windows&type=wstorage&id=ad.xorux.com_server_HVNODE01_storage_C:
    ( my $server, my $host ) = split "_server_", $uid;
    ( $host,    my $storage ) = split "_storage_", $host;
    ( $storage, my $item )    = split "_item_",    $storage;

    # host=DC&server=windows%2Fdomain%5Fad%2Exorux%2Ecom&lpar=C%3A&item=lfd_cat_&time=d&type_sam=0&detail=1&entitle=0&none=none
    return {
      url_base => '',
      params   => {
        host   => $host,
        server => "windows/domain_" . $server,
        lpar   => $storage,
        item   => $item
      }
    };
  }
  elsif ( $page_type eq "wvm" ) {

    # 'id' => 'ad.xorux.com_server_HVNODE01_vm_61538264-853B-43A0-99F5-DCFE083864C0',
    # old query
    # $QUERY_STRING host=HYPERV&server=windows/domain_ad.int.xorux.com&lpar=3138F59F-11AD-46FB-951C-9C147C98896C&item=lpar
    ( my $server, my $host ) = split "_server_", $uid;
    ( $host, my $vm_uuid ) = split "_vm_", $host;
    return {
      url_base => '',
      params   => {
        host   => $host,
        server => "windows/domain_" . $server,
        lpar   => "$vm_uuid",
        item   => "lpar"
      }
    };
  }
  elsif ( $page_type eq "s2dvolume" ) {

    # print STDERR "$uid\n";
    # uid s2d_vol_volume01
    # host=cluster_s2d&server=windows&lpar=volume01&item=s2dvolume
    ( my $cluster, my $vol_uuid ) = split "_vol_", $uid;
    return {
      url_base => '',
      params   => {
        host   => "cluster_" . $cluster,
        server => "windows",
        lpar   => "$vol_uuid",
        item   => "s2dvolume"
      }
    };
  }
  elsif ( $page_type eq "physdisk" ) {

    # print STDERR "$uid\n";
    # host=cluster_s2d&server=windows&lpar=volume01&item=s2dvolume
    ( my $cluster, my $pd_uuid ) = split "_pd_", $uid;
    return {
      url_base => '',
      params   => {
        host   => "cluster_" . $cluster,
        server => "windows",
        lpar   => "$pd_uuid",
        item   => "physdisk"
      }
    };
  }
  elsif ( $page_type eq "cluster_totals" ) {

    # 'id' => 'MSNET-HVCL',
    # old query
    # $QUERY_STRING host=cluster_MSNET-HVCL&server=windows&lpar=nope&item=cluster&entitle=0&gui=1&none=none&_=1611736140621
    return {
      url_base => '',
      params   => {
        host   => "cluster_$uid",
        server => "windows",
        lpar   => "nope",
        item   => "cluster"
      }
    };
  }
  elsif ( $page_type eq "topten_windows" ) {
    return {
      url_base => '',
      params   => {
        lpar => 'cod',
        item => 'topten_hyperv'
      }
    };
  }
  elsif ( $page_type eq "hmctotals" ) {
    my $vcenter_uuid      = 'vmware_' . $uid;
    my $vcenter_host_name = get_vcenter_host_name($vcenter_uuid);
    return {
      url_base => '/lpar2rrd-cgi/detail.sh',
      params   => {
        lpar   => 'nope',
        item   => 'hmctotals',
        server => $vcenter_uuid,
        host   => $vcenter_host_name
      }
    };
  }
  elsif ( $page_type eq "historical_reports" ) {
    return {
      url_base => '/lpar2rrd-cgi/histrep.sh?mode=global',
      params   => {}
    };
  }
  elsif ( $page_type eq "topten_vm_vcenter" ) {
    my %uid_hash;
    $uid_hash{'item_id'} = $uid;

    # my $item_name = SQLiteDataWrapper::getItemLabel($uid_hash);
    my $item_name = VmwareDataWrapper::getItemLabel( \%uid_hash );
    return {
      url_base => '',
      params   => {
        server => $item_name,
        lpar   => 'cod',
        item   => 'topten_vm'
      }
    };
  }
  elsif ( $page_type eq "cluster" ) {
    ( my $vcenter_uuid, my $cluster_uuid ) = split( "_cluster_", $uid );
    return {
      url_base => '',
      params   => {
        host   => 'cluster_' . $cluster_uuid,
        server => 'vmware_' . $vcenter_uuid,
        lpar   => 'nope',
        item   => 'cluster'
      }
    };
  }
  elsif ( $page_type eq "esxi-cpu" ) {

    # id=ef81e113-3f75-4e78-bc8c-a86df46a4acb_12_cluster_domain-c7_esxi_10.22.111.2
    ( undef, my $server ) = split( "_esxi_", $uid );
    ( my $vcenter_uuid, undef ) = split( "_cluster_", $uid );
    $vcenter_uuid = 'vmware_' . $vcenter_uuid;
    my $vcenter_host_name = get_vcenter_host_name($vcenter_uuid);
    return {
      url_base => '',
      params   => {
        host   => $vcenter_host_name,
        server => $server,
        lpar   => 'pool',
        item   => 'pool'
      }
    };
  }
  elsif ( $page_type eq "esxi-mem" ) {

    # id=ef81e113-3f75-4e78-bc8c-a86df46a4acb_12_cluster_domain-c7_esxi_10.22.111.2
    ( undef, my $server ) = split( "_esxi_", $uid );
    ( my $vcenter_uuid, undef ) = split( "_cluster_", $uid );
    $vcenter_uuid = 'vmware_' . $vcenter_uuid;
    my $vcenter_host_name = get_vcenter_host_name($vcenter_uuid);
    return {
      url_base => '',
      params   => {
        host   => $vcenter_host_name,
        server => $server,
        lpar   => 'cod',
        item   => 'memalloc'
      }
    };
  }
  elsif ( $page_type eq "esxi-space" ) {

    # id=ef81e113-3f75-4e78-bc8c-a86df46a4acb_12_cluster_domain-c7_esxi_10.22.111.2
    ( undef, my $server ) = split( "_esxi_", $uid );
    ( my $vcenter_uuid, undef ) = split( "_cluster_", $uid );
    $vcenter_uuid = 'vmware_' . $vcenter_uuid;
    my $vcenter_host_name = get_vcenter_host_name($vcenter_uuid);
    return {
      url_base => '',
      params   => {
        host   => $vcenter_host_name,
        server => $server,
        lpar   => 'cod',
        item   => 'vmdiskrw'
      }
    };
  }
  elsif ( $page_type eq "esxi-lan" ) {

    # id=ef81e113-3f75-4e78-bc8c-a86df46a4acb_12_cluster_domain-c7_esxi_10.22.111.2
    ( undef, my $server ) = split( "_esxi_", $uid );
    ( my $vcenter_uuid, undef ) = split( "_cluster_", $uid );
    $vcenter_uuid = 'vmware_' . $vcenter_uuid;
    my $vcenter_host_name = get_vcenter_host_name($vcenter_uuid);
    return {
      url_base => '',
      params   => {
        host   => $vcenter_host_name,
        server => $server,
        lpar   => 'cod',
        item   => 'vmnetrw'
      }
    };
  }
  elsif ( $page_type eq "view" ) {

    # id=ef81e113-3f75-4e78-bc8c-a86df46a4acb_12_cluster_domain-c7_esxi_10.22.111.2
    ( undef, my $server ) = split( "_esxi_", $uid );
    ( my $vcenter_uuid, undef ) = split( "_cluster_", $uid );
    $vcenter_uuid = 'vmware_' . $vcenter_uuid;
    my $vcenter_host_name = get_vcenter_host_name($vcenter_uuid);
    return {
      url_base => '',
      params   => {
        host   => $vcenter_host_name,
        server => $server,
        lpar   => 'cod',
        item   => 'view'
      }
    };
  }
  elsif ( $page_type eq "vm" ) {
    my %uid_hash;

    # id=ef81e113-3f75-4e78-bc8c-a86df46a4acb_12_vm_500cccad-bb91-8286-df96-fe836412c59c
    $uid_hash{'item_id'} = $uid;

    # my $parents = SQLiteDataWrapper::getItemParents($uid_hash);
    my $parents = VmwareDataWrapper::getItemParents( \%uid_hash );

    # print STDERR "267 \$uid $uid\n";
    # print STDERR Dumper(268, $parents);
    my @prnt_keys = ( keys %{ $parents->{'ESXI'} } );

    # eb6102a7-1fa0-4376-acbb-f67e34a2212c_28_cluster_domain-c87_esxi_10.22.11.14
    ( undef, my $server ) = split( "_esxi_", $prnt_keys[0] );
    chomp $server;
    ( my $vcenter_uuid, my $lpar_uuid ) = split( "_vm_", $uid );
    $vcenter_uuid = 'vmware_' . $vcenter_uuid;
    my $vcenter_host_name = get_vcenter_host_name($vcenter_uuid);
    return {
      url_base => '',
      params   => {
        host   => $vcenter_host_name,
        server => $server,
        lpar   => $lpar_uuid,
        item   => 'lpar'
      }
    };
  }
  elsif ( $page_type eq "datastore" ) {

    # id=eb6102a7-1fa0-4376-acbb-f67e34a2212c_28_ds_5d38366c-a5e87bba-02de-001018f45648
    my %uid_hash;
    $uid_hash{'item_id'} = $uid;

    # my $parents = SQLiteDataWrapper::getItemParents($uid_hash);
    my $parents   = VmwareDataWrapper::getItemParents( \%uid_hash );
    my @prnt_keys = ( keys %{ $parents->{'DATACENTER'} } );
    ( undef, my $datacenter ) = split( "_datastore_", $prnt_keys[0] );
    chomp $datacenter;
    $datacenter = "datastore_" . $datacenter;
    ( my $vcenter_uuid, my $lpar_uuid ) = split( "_ds_", $uid );
    $vcenter_uuid = 'vmware_' . $vcenter_uuid;
    return {
      url_base => '',
      params   => {
        host   => $datacenter,
        server => $vcenter_uuid,
        lpar   => $lpar_uuid,
        item   => 'datastore'
      }
    };
  }
  elsif ( $page_type eq "resourcepool" ) {

    # id=eb6102a7-1fa0-4376-acbb-f67e34a2212c_28_resgroup-138
    # host=cluster_domain-c87&server=vmware_eb6102a7-1fa0-4376-acbb-f67e34a2212c_28&lpar=resgroup-138&item=resourcepool
    my %uid_hash;
    $uid_hash{'item_id'} = $uid;

    # my $parents = SQLiteDataWrapper::getItemParents($uid_hash);
    my $parents = VmwareDataWrapper::getItemParents( \%uid_hash );

    # print STDERR Dumper(\$parents);
    my @prnt_keys = ( keys %{ $parents->{'CLUSTER'} } );
    ( undef, my $cluster ) = split( "_cluster_", $prnt_keys[0] );
    chomp $cluster;
    my $host = "cluster_$cluster";
    ( my $vcenter_uuid, my $resgroup_uuid ) = split( "_resgroup", $uid );
    $vcenter_uuid = 'vmware_' . $vcenter_uuid;
    return {
      url_base => '',
      params   => {
        host   => $host,
        server => $vcenter_uuid,
        lpar   => "resgroup$resgroup_uuid",
        item   => 'resourcepool'
      }
    };
  }
  elsif ( $page_type eq "linux" ) {

    #platform=Linux&type=linux&id=infra-mon-tomas-test
    #host=no_hmc&server=Linux--unknown&lpar=internal.int.xorux.com&item=lpar
    return {
      url_base => '',
      params   => {
        host   => 'no_hmc',
        server => 'Linux--unknown',
        lpar   => $uid,
        item   => 'lpar'
      }
    };
  }
}

sub gen_url {
  my $url_hash = shift;
  my $url      = "";

  $url = $url_hash->{url_base} . '?';
  my @params = keys %{ $url_hash->{params} };
  foreach my $par (@params) {
    $url .= "$par=$url_hash->{params}{$par}";
    if ( $par ne $params[-1] ) { $url .= '&'; }

    #warn Dumper $url_hash;
  }
  return $url;
}

sub url_old_to_new {
  my $url = shift;
  my $params;
  my %out;
  $url = Xorux_lib::urldecode($url);
  $url =~ s/===double-col===/:/g;
  $url =~ s/%20/ /g;
  $url =~ s/%3A/:/g;
  $url =~ s/%2F/&&1/g;
  $url =~ s/%23/#/g;
  $url =~ s/%3B/;/g;

  my $qs = $url;
  my $type;
  my $id;

  # use Xorux_lib parsing subroutine
  ( undef, $qs ) = split( "\\?", $qs );
  $params = Xorux_lib::parse_url_params($qs);

  #  my @pairs = split ("\\&", $qs);
  #  foreach my $pair (@pairs){
  #    (my $key, my $value) = split ("=", $pair);
  #    $params->{$key} = $value;
  #  }

  #VM
  if ( $params->{item} eq "lpar" ) {
    $type = 'vm';
    $id   = PowerDataWrapper::get_item_uid( { type => $type, label => $params->{lpar} } );
  }
  elsif ( $params->{item} eq "pool" ) {
    $type = "pool";
    $id   = PowerDataWrapper::get_item_uid( { type => $type, label => $params->{server} } );
  }
  elsif ( $params->{item} eq "shpool" ) {
    $type = "shpool";
    $id   = PowerDataWrapper::get_item_uid( { type => $type, label => $params->{lpar} } );
  }
  elsif ( $params->{item} eq "memalloc" ) {
    $type = "memory";
    $id   = PowerDataWrapper::get_item_uid( { type => "server", label => $params->{server} } );

  }
  elsif ( $params->{mode} eq "power" && defined( $params->{host} ) ) {
    $type = "local_historical_reports";
    $id   = "not_supported_anymore";
  }
  elsif ( $params->{mode} eq "global" ) {
    $type = "historical_reports";
    $id   = "";
  }
  elsif ( $params->{item} eq "topten" && defined( $params->{server} ) ) {
    $type = "topten";
    $id   = PowerDataWrapper::get_item_uid( { type => "server", label => $params->{server} } );
  }
  elsif ( $params->{item} eq "view" && defined( $params->{server} ) ) {
    $type = "view";
    $id   = PowerDataWrapper::get_item_uid( { type => "server", label => $params->{server} } );
  }
  elsif ( $params->{item} =~ "power_" && $params->{lpar} !~ m/totals/ ) {
    $type = $params->{item};
    $type =~ s/power_//g;
    my $label = $params->{lpar};
    $label =~ s/\..*//g;
    $id = PowerDataWrapper::get_item_uid( { type => $type, label => $label } );
  }
  elsif ( $params->{item} =~ "power_lan" && $params->{lpar} =~ m/totals/ ) {
    $type = "lan-aggr";
    my $label = $params->{server};
    $id = PowerDataWrapper::get_item_uid( { type => $type, label => $label } );
  }
  elsif ( $params->{item} =~ "power_san" && $params->{lpar} =~ m/totals/ ) {
    $type = "san-aggr";
    my $label = $params->{server};
    $id = PowerDataWrapper::get_item_uid( { type => $type, label => $label } );
  }
  elsif ( $params->{item} =~ "power_sas" && $params->{lpar} =~ m/totals/ ) {
    $type = "sas-aggr";
    my $label = $params->{server};
    $id = PowerDataWrapper::get_item_uid( { type => $type, label => $label } );
  }
  elsif ( $params->{item} =~ "power_hea" && $params->{lpar} =~ m/totals/ ) {
    $type = "hea-aggr";
    my $label = $params->{server};
    $id = PowerDataWrapper::get_item_uid( { type => $type, label => $label } );
  }
  elsif ( $params->{item} =~ "power_sri" && $params->{lpar} =~ m/totals/ ) {
    $type = "sri-aggr";
    my $label = $params->{server};
    $id = PowerDataWrapper::get_item_uid( { type => $type, label => $label } );
  }
  elsif ( $params->{item} =~ "hmctotals" ) {
    $type = "hmc-totals";
    $id   = "";
  }
  else {
    return;
  }

  my $menu = Menu->new( lc 'Power' );

  #my $url;
  if ($id) {
    $url = $menu->page_url( $type, $id );
  }
  else {
    $url = $menu->page_url($type);
  }
  return $url;
}

1;
