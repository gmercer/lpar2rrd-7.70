# ovirt-genmenu.pl
# generate menu tree from oVirt RRDs and save it in a JSON file
# replacement for an older equivalent to `find_active_lpar.pl` that generated `menu.txt`

use 5.008_008;

use strict;
use warnings;

use JSON;
use Data::Dumper;

use Xorux_lib qw(error);
use OVirtDataWrapper;
use OVirtMenu;

defined $ENV{INPUTDIR} || warn( ' INPUTDIR undefined, config etc/lpar2rrd.cfg probably has not been loaded ' . __FILE__ . ':' . __LINE__ ) && exit 1;

my $inputdir      = $ENV{INPUTDIR};
my $main_data_dir = "$inputdir/data/oVirt";

################################################################################

unless ( -d $main_data_dir ) {
  exit;
}

my $menu_tree   = OVirtMenu::create_folder('RHV / oVirt');
my $datacenters = gen_datacenters();

if ( scalar @{$datacenters} ) {
  my $configuration_page_url = OVirtMenu::get_url( { type => 'configuration' } );
  my $configuration_page = OVirtMenu::create_page( 'Configuration', $configuration_page_url );
  my $domains_total_page_url = OVirtMenu::get_url( { type => 'storage_domains_total_aggr' } );
  my $domains_total_page = OVirtMenu::create_page( 'Storage domains', $domains_total_page_url );
  my $heatmap_page_url = OVirtMenu::get_url( { type => 'heatmap' } );
  my $heatmap_page = OVirtMenu::create_page( 'Heatmap', $heatmap_page_url );
  my $topten_page_url = OVirtMenu::get_url( { type => 'topten_ovirt' } );
  my $topten_page = OVirtMenu::create_page( 'VM TOP', $topten_page_url );

  $menu_tree->{children} = [ $heatmap_page, $configuration_page, $domains_total_page, $topten_page ];
  push @{ $menu_tree->{children} }, @{$datacenters};

  #print as JSON
  my $json      = JSON->new->utf8->pretty;
  my $json_data = $json->encode($menu_tree);
  print $json_data;
}

exit 0;

################################################################################

sub gen_datacenters {
  my @datacenter_folders = ();

  foreach my $datacenter_uuid ( @{ OVirtDataWrapper::get_uuids('datacenter') } ) {

    # datacenter folder
    my $datacenter_label = OVirtDataWrapper::get_label( 'datacenter', $datacenter_uuid );
    my $datacenter_folder = OVirtMenu::create_folder( $datacenter_label, $datacenter_label );
    $datacenter_folder->{children} = gen_clusters( $datacenter_uuid, "$datacenter_label" );
    push @datacenter_folders, $datacenter_folder;

    # storage domains folder
    my $domain_folder = OVirtMenu::create_folder('Storage domain');
    $domain_folder->{children} = gen_storage_domains( $datacenter_uuid, "$datacenter_label" );
    push @{ $datacenter_folder->{children} }, $domain_folder;
  }

  return \@datacenter_folders;
}

sub gen_clusters {
  my $datacenter_uuid = shift;
  my $search_acc      = shift;
  my @cluster_folders = ();

  foreach my $cluster_uuid ( @{ OVirtDataWrapper::get_arch( $datacenter_uuid, 'datacenter', 'cluster' ) } ) {

    # cluster folder
    my $cluster_label  = OVirtDataWrapper::get_label( 'cluster', $cluster_uuid );
    my $search_string  = "$search_acc $cluster_label";
    my $cluster_folder = OVirtMenu::create_folder( $cluster_label, $search_string );

    # cluster totals page
    my $cluster_total_page_url = OVirtMenu::get_url( { type => 'cluster_aggr', id => $cluster_uuid } );
    my $cluster_total_page = OVirtMenu::create_page( 'Totals', $cluster_total_page_url, $search_string );
    push @{ $cluster_folder->{children} }, $cluster_total_page;

    # hosts of this cluster
    push( @{ $cluster_folder->{children} }, @{ gen_hosts( $cluster_uuid, $search_string ) } );
    push @cluster_folders, $cluster_folder;

    # VMs of this cluster
    my $vms_array_ref = gen_vms( $cluster_uuid, $search_string );

    if ( scalar @{$vms_array_ref} ) {

      # VM folder
      my $vm_folder = OVirtMenu::create_folder( 'VM', $search_string );
      $vm_folder->{children} = $vms_array_ref;
      push @{ $cluster_folder->{children} }, $vm_folder;
    }
  }

  return \@cluster_folders;
}

sub gen_hosts {
  my $cluster_uuid = shift;
  my $search_acc   = shift;
  my @host_folders = ();

  foreach my $host_uuid ( @{ OVirtDataWrapper::get_arch( $cluster_uuid, 'cluster', 'host' ) } ) {

    # host folder
    my $host_label    = OVirtDataWrapper::get_label( 'host', $host_uuid );
    my $search_string = "$search_acc $host_label";
    my $host_folder   = OVirtMenu::create_folder( $host_label, $search_string );
    push @host_folders, $host_folder;

    # host data page
    my $host_mapping       = OVirtDataWrapper::get_mapping($host_uuid);
    my $host_data_page_url = OVirtMenu::get_url( { type => 'host', id => $host_uuid } );
    my $host_data_page     = OVirtMenu::create_page( $host_label, $host_data_page_url, $search_string, $host_mapping );
    push @{ $host_folder->{children} }, $host_data_page;

    # NIC interfaces of this host
    my $nics_array_ref = gen_host_nics( $host_uuid, $search_string );

    if ( scalar @{$nics_array_ref} ) {

      # LAN folder
      my $lan_folder = OVirtMenu::create_folder( 'LAN', $search_string );
      push @{ $host_folder->{children} }, $lan_folder;

      # LAN totals page
      my $lan_total_page_url = OVirtMenu::get_url( { type => 'host_nic_aggr', id => $host_uuid } );
      my $lan_total_page = OVirtMenu::create_page( 'Totals', $lan_total_page_url, $search_string );
      push @{ $lan_folder->{children} }, $lan_total_page;

      # LAN folder and items
      my $lan_items_folder = OVirtMenu::create_folder( 'Items', $search_string );
      $lan_items_folder->{children} = $nics_array_ref;
      push @{ $lan_folder->{children} }, $lan_items_folder;
    }
  }

  return \@host_folders;
}

sub gen_storage_domains {
  my $datacenter_uuid = shift;
  my $search_acc      = shift;
  my @domain_folders  = ();

  foreach my $domain_uuid ( @{ OVirtDataWrapper::get_arch( $datacenter_uuid, 'datacenter', 'storage_domain' ) } ) {

    # storage domain folder
    my $domain_label  = OVirtDataWrapper::get_label( 'storage_domain', $domain_uuid );
    my $search_string = "$search_acc $domain_label";
    my $domain_folder = OVirtMenu::create_folder( $domain_label, $search_string );
    push @domain_folders, $domain_folder;

    # storage domain data page
    my $domain_data_page_url = OVirtMenu::get_url( { type => 'storage_domain', id => $domain_uuid } );
    my $domain_data_page = OVirtMenu::create_page( 'Totals', $domain_data_page_url, $search_string );
    push @{ $domain_folder->{children} }, $domain_data_page;

    # disks of this storage domain
    my $disks_array_ref = gen_disks( $domain_uuid, $search_string );

    if ( scalar @{$disks_array_ref} ) {

      # LAN folder and items
      my $disk_items_folder = OVirtMenu::create_folder( 'Items', $search_string );
      $disk_items_folder->{children} = $disks_array_ref;
      push @{ $domain_folder->{children} }, $disk_items_folder;
    }
  }

  return \@domain_folders;
}

sub gen_vms {
  my $cluster_uuid = shift;
  my $search_acc   = shift;
  my @vm_pages     = ();

  foreach my $vm_uuid ( @{ OVirtDataWrapper::get_arch( $cluster_uuid, 'cluster', 'vm' ) } ) {
    my $vm_label      = OVirtDataWrapper::get_label( 'vm', $vm_uuid );
    my $vm_mapping    = OVirtDataWrapper::get_mapping($vm_uuid);
    my $search_string = "$search_acc $vm_label";
    my $vm_page_url   = OVirtMenu::get_url( { type => 'vm', id => $vm_uuid } );
    my $vm_page       = OVirtMenu::create_page( $vm_label, $vm_page_url, $search_string, $vm_mapping );

    push @vm_pages, $vm_page;
  }

  return \@vm_pages;
}

sub gen_disks {
  my $storage_domain_uuid = shift;
  my $search_acc          = shift;
  my @disk_pages          = ();

  foreach my $disk_uuid ( @{ OVirtDataWrapper::get_arch( $storage_domain_uuid, 'storage_domain', 'disk' ) } ) {
    my $disk_label    = OVirtDataWrapper::get_label( 'disk', $disk_uuid );
    my $search_string = "$search_acc $disk_label";
    my $disk_page_url = OVirtMenu::get_url( { type => 'disk', id => $disk_uuid } );
    my $disk_page     = OVirtMenu::create_page( $disk_label, $disk_page_url, $search_string );

    push @disk_pages, $disk_page;
  }

  return \@disk_pages;
}

sub gen_host_nics {
  my $host_uuid  = shift;
  my $search_acc = shift;
  my @nic_pages  = ();

  foreach my $nic_uuid ( @{ OVirtDataWrapper::get_arch( $host_uuid, 'host', 'nic' ) } ) {
    my $nic_label     = OVirtDataWrapper::get_label( 'host_nic', $nic_uuid );
    my $search_string = "$search_acc $nic_label";
    my $nic_page_url  = OVirtMenu::get_url( { type => 'host_nic', id => $nic_uuid } );
    my $nic_page      = OVirtMenu::create_page( $nic_label, $nic_page_url, $search_string );

    push @nic_pages, $nic_page;
  }

  return \@nic_pages;
}
