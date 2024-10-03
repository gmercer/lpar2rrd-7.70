# proxmox-genmenu.pl
# generate menu tree from Proxmox RRDs and print it as JSON

use 5.008_008;

use strict;
use warnings;

use JSON;
use Data::Dumper;
use HostCfg;
use Xorux_lib;
use ProxmoxDataWrapperOOP;
use ProxmoxMenu;

defined $ENV{INPUTDIR} || warn( localtime() . ': INPUTDIR undefined, config etc/lpar2rrd.cfg probably has not been loaded ' . __FILE__ . ':' . __LINE__ ) && exit 1;

my $inputdir = $ENV{INPUTDIR};

if ( keys %{ HostCfg::getHostConnections('Proxmox') } == 0 ) {
  exit(0);
}

my $proxmox_metadata = ProxmoxDataWrapperOOP->new( { conf_labels => 1, conf_arch => 1, acl_check => 0 } );

my $menu_tree = ProxmoxMenu::create_folder('Proxmox');
my $clusters  = gen_clusters();

if ( scalar @{$clusters} ) {
  my $configuration_page_url = ProxmoxMenu::get_url( { type => 'configuration' } );
  my $configuration_page     = ProxmoxMenu::create_page( 'Configuration', $configuration_page_url );
  my $heatmap_page_url       = ProxmoxMenu::get_url( { type => 'heatmap' } );
  my $heatmap_page           = ProxmoxMenu::create_page( 'Heatmap', $heatmap_page_url );
  my $proxmox_topten_url     = ProxmoxMenu::get_url( { type => 'topten_proxmox' } );
  my $proxmox_topten_page    = ProxmoxMenu::create_page( 'VM TOP', $proxmox_topten_url );

  $menu_tree->{children} = [ $heatmap_page, $configuration_page, $proxmox_topten_page ];
  push @{ $menu_tree->{children} }, @{$clusters};

  # print menu tree as JSON
  my $json      = JSON->new->utf8->pretty;
  my $json_data = $json->encode($menu_tree);
  print $json_data;
}
exit 0;

sub gen_clusters {

  my @cluster_folders = ();
  my @clusters        = @{ $proxmox_metadata->get_items( { item_type => 'cluster' } ) };

  foreach my $cluster (@clusters) {
    my ( $cluster_id, $cluster_label ) = each %{$cluster};

    my $cluster_folder = ProxmoxMenu::create_folder($cluster_label);

    my ( $node_folder, $totals_url_node, %totals_page_node, $vm_folder, $totals_url_vm, %totals_page_vm, $lxc_folder, $totals_url_lxc, %totals_page_lxc, $storage_folder, $totals_url_storage, %totals_page_storage );

    #nodes
    my @nodes = @{ $proxmox_metadata->get_items( { item_type => 'node', parent_type => 'cluster', parent_id => $cluster_id } ) };
    if ( scalar @nodes >= 1 ) {
      $node_folder      = ProxmoxMenu::create_folder('Node');
      $totals_url_node  = ProxmoxMenu::get_url( { type => 'node-aggr', cluster => $cluster_id } );
      %totals_page_node = %{ ProxmoxMenu::create_page( 'Node Totals', $totals_url_node ) };

      foreach my $node (@nodes) {
        my ( $node_uuid, $node_label ) = each %{$node};

        my $filepath = $proxmox_metadata->get_filepath_rrd( { type => 'node', uuid => $node_uuid } );
        unless ( -f $filepath ) { next; }

        my $url       = ProxmoxMenu::get_url( { type => 'node', node => $node_uuid } );
        my %node_page = %{ ProxmoxMenu::create_page( $node_label, $url ) };
        push @{ $node_folder->{children} }, \%node_page;

      }

      push @{ $cluster_folder->{children} }, \%totals_page_node;

    }

    #vm
    my @vms = @{ $proxmox_metadata->get_items( { item_type => 'vm', parent_type => 'cluster', parent_id => $cluster_id } ) };
    if ( scalar @vms >= 1 ) {
      $vm_folder      = ProxmoxMenu::create_folder('VM');
      $totals_url_vm  = ProxmoxMenu::get_url( { type => 'vm-aggr', cluster => $cluster_id } );
      %totals_page_vm = %{ ProxmoxMenu::create_page( 'VM Totals', $totals_url_vm ) };

      foreach my $vm (@vms) {
        my ( $vm_uuid, $vm_label ) = each %{$vm};

        my $filepath = $proxmox_metadata->get_filepath_rrd( { type => 'vm', uuid => $vm_uuid } );
        unless ( -f $filepath ) { next; }

        my $url     = ProxmoxMenu::get_url( { type => 'vm', vm => $vm_uuid } );
        my %vm_page = %{ ProxmoxMenu::create_page( $vm_label, $url ) };
        push @{ $vm_folder->{children} }, \%vm_page;

      }

      push @{ $cluster_folder->{children} }, \%totals_page_vm;

    }

    #lxc
    my @lxcs = @{ $proxmox_metadata->get_items( { item_type => 'lxc', parent_type => 'cluster', parent_id => $cluster_id } ) };
    if ( scalar @lxcs >= 1 ) {
      $lxc_folder      = ProxmoxMenu::create_folder('LXC');
      $totals_url_lxc  = ProxmoxMenu::get_url( { type => 'lxc-aggr', cluster => $cluster_id } );
      %totals_page_lxc = %{ ProxmoxMenu::create_page( 'LXC Totals', $totals_url_lxc ) };

      foreach my $lxc (@lxcs) {
        my ( $lxc_uuid, $lxc_label ) = each %{$lxc};

        my $filepath = $proxmox_metadata->get_filepath_rrd( { type => 'lxc', uuid => $lxc_uuid } );
        unless ( -f $filepath ) { next; }

        my $url      = ProxmoxMenu::get_url( { type => 'lxc', lxc => $lxc_uuid } );
        my %lxc_page = %{ ProxmoxMenu::create_page( $lxc_label, $url ) };
        push @{ $lxc_folder->{children} }, \%lxc_page;

      }

      push @{ $cluster_folder->{children} }, \%totals_page_lxc;

    }

    #storage
    my @storages = @{ $proxmox_metadata->get_items( { item_type => 'storage', parent_type => 'cluster', parent_id => $cluster_id } ) };
    if ( scalar @storages >= 1 ) {
      $storage_folder      = ProxmoxMenu::create_folder('Storage');
      $totals_url_storage  = ProxmoxMenu::get_url( { type => 'storage-aggr', cluster => $cluster_id } );
      %totals_page_storage = %{ ProxmoxMenu::create_page( 'Storage Totals', $totals_url_storage ) };

      foreach my $storage (@storages) {
        my ( $storage_uuid, $storage_label ) = each %{$storage};

        my $filepath = $proxmox_metadata->get_filepath_rrd( { type => 'storage', uuid => $storage_uuid } );
        unless ( -f $filepath ) { next; }

        my $url          = ProxmoxMenu::get_url( { type => 'storage', storage => $storage_uuid } );
        my %storage_page = %{ ProxmoxMenu::create_page( $storage_label, $url ) };
        push @{ $storage_folder->{children} }, \%storage_page;

      }

      push @{ $cluster_folder->{children} }, \%totals_page_storage;

    }

    if ( scalar @nodes >= 1 ) {
      push @{ $cluster_folder->{children} }, $node_folder;
    }
    if ( scalar @vms >= 1 ) {
      push @{ $cluster_folder->{children} }, $vm_folder;
    }
    if ( scalar @lxcs >= 1 ) {
      push @{ $cluster_folder->{children} }, $lxc_folder;
    }
    if ( scalar @vms >= 1 ) {
      push @{ $cluster_folder->{children} }, $storage_folder;
    }

    push @cluster_folders, $cluster_folder;

  }

  return \@cluster_folders;
}
