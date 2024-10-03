# nutanix-genmenu.pl
# generate menu tree from Nutanix RRDs and print it as JSON
# replacement for an older equivalent to `find_active_lpar.pl` that generated `menu.txt`

use 5.008_008;

use strict;
use warnings;

use JSON;
use Data::Dumper;
use HostCfg;
use Xorux_lib;
use NutanixDataWrapperOOP;
use NutanixMenu;

defined $ENV{INPUTDIR} || warn( localtime() . ': INPUTDIR undefined, config etc/lpar2rrd.cfg probably has not been loaded ' . __FILE__ . ':' . __LINE__ ) && exit 1;

my $inputdir = $ENV{INPUTDIR};
my $host_dir = "$inputdir/data/NUTANIX/HOST";
my $vm_dir   = "$inputdir/data/NUTANIX/VM";

unless ( -d $host_dir || -d $vm_dir ) {
  exit;
}

if ( keys %{ HostCfg::getHostConnections('Nutanix') } == 0 ) {
  exit(0);
}

my $nutanix_metadata = NutanixDataWrapperOOP->new( { conf_labels => 1, conf_arch => 1, acl_check => 0 } );

my $menu_tree = NutanixMenu::create_folder('Nutanix');
my $clusters  = gen_clusters();

if ( scalar @{$clusters} ) {
  my $configuration_page_url = NutanixMenu::get_url( { type => 'configuration' } );
  my $configuration_page     = NutanixMenu::create_page( 'Configuration', $configuration_page_url );
  my $heatmap_page_url       = NutanixMenu::get_url( { type => 'heatmap' } );
  my $heatmap_page           = NutanixMenu::create_page( 'Heatmap', $heatmap_page_url );
  my $alerts_page_url        = NutanixMenu::get_url( { type => 'alerts' } );

  #my $alerts_page            = NutanixMenu::create_page( 'Alerts', $alerts_page_url );

  my $health_page_url = NutanixMenu::get_url( { type => "health-central", health => 'central' } );
  my $health_page     = NutanixMenu::create_page( 'Health Status', $health_page_url );
  my $topten_page_url = NutanixMenu::get_url( { type => 'topten_nutanix' } );
  my $topten_page     = NutanixMenu::create_page( 'VM TOP', $topten_page_url );
  $menu_tree->{children} = [ $heatmap_page, $configuration_page, $health_page, $topten_page ];

  push @{ $menu_tree->{children} }, @{$clusters};

  # print menu tree as JSON
  my $json      = JSON->new->utf8->pretty;
  my $json_data = $json->encode($menu_tree);
  print $json_data;
}
exit 0;

sub gen_clusters {

  #my $labels = $nutanix_metadata->get_labels();

  my @cluster_folders = ();

  my @clusters = @{ $nutanix_metadata->get_items( { item_type => 'cluster' } ) };
  foreach my $cluster (@clusters) {
    my ( $cluster_uuid, $cluster_label ) = each %{$cluster};
    my ( @host_entries, $cluster_folder, $totals_url );

    my $server_folder = NutanixMenu::create_folder('Servers');

    my @hosts = @{ $nutanix_metadata->get_items( { item_type => 'host', parent_type => 'cluster', parent_uuid => $cluster_uuid } ) };
    foreach my $host (@hosts) {
      my ( $host_uuid, $host_label ) = each %{$host};
      my ( $label, $host_folder, $interface_folder, $url );

      $url = NutanixMenu::get_url( { type => 'host', host => $host_uuid } );
      my %host_page = %{ NutanixMenu::create_page( $host_label, $url ) };
      push @{ $server_folder->{children} }, \%host_page;
    }

    # add VMs that reside on hosts in this cluster
    my $vms;
    if ( -d $vm_dir ) {
      my @vms = @{ $nutanix_metadata->get_items( { item_type => 'vm', parent_type => 'cluster', parent_uuid => $cluster_uuid } ) };
      my @pages;
      my $url;
      my %vm_folder;
      my %vm_folder_storage;
      foreach my $vm (@vms) {
        my ( $vm_uuid, $vm_label ) = each %{$vm};

        $url = NutanixMenu::get_url( { type => 'vm', vm => $vm_uuid } );
        my %page = %{ NutanixMenu::create_page( $vm_label, $url ) };

        push @pages, \%page;
      }

      $vms = NutanixMenu::create_folder('VM');
      $vms->{children} = \@pages;
    }

    # add Storages that are assigned to hosts in this cluster (the same as under hosts, but here they are in one place)
    my $storage_folder = 1;
    my $cluster_storages;
    if ( $storage_folder == 1 ) {
      $cluster_storages = NutanixMenu::create_folder('Storage');
      $totals_url       = NutanixMenu::get_url( { type => 'pool-storage-aggr', pool => $cluster_uuid } );
      my %totals_page = %{ NutanixMenu::create_page( 'Totals', $totals_url ) };

      #Storage Pool
      my $storage_cluster_folder = NutanixMenu::create_folder('Storage Pools');

      #push @{$storage_cluster_folder->{children}}, \%totals_page;

      my @storage_clusters = @{ $nutanix_metadata->get_items( { item_type => 'pool', parent_type => 'cluster', parent_uuid => $cluster_uuid } ) };
      my %sp_folder;
      foreach my $sp (@storage_clusters) {
        my ( $sp_uuid, $sp_label ) = each %{$sp};

        my $short_uuid = $nutanix_metadata->shorten_sr_uuid($sp_uuid);
        my $label      = $sp_label ? $sp_label : "no label - ${short_uuid}";

        #$label = $nutanix_metadata->get_label( 'sp', $sp_uuid );
        my $url     = NutanixMenu::get_url( { type => 'sp', sp => $sp_uuid } );
        my %sp_page = %{ NutanixMenu::create_page( $label, $url ) };
        push @{ $storage_cluster_folder->{children} }, \%sp_page;
      }
      push @{ $cluster_storages->{children} }, $storage_cluster_folder;

      #Storage Container
      my $storage_container_folder = NutanixMenu::create_folder('Storage Containers');

      #push @{$cluster_storages->{children}}, $storage_container_folder;

      my @storage_containers = @{ $nutanix_metadata->get_items( { item_type => 'container', parent_type => 'cluster', parent_uuid => $cluster_uuid } ) };
      foreach my $sc (@storage_containers) {
        my ( $sc_uuid, $sc_label ) = each %{$sc};

        my $short_uuid = $nutanix_metadata->shorten_sr_uuid($sc_uuid);
        my $label      = $sc_label ? $sc_label : "no label - ${short_uuid}";
        my $url        = NutanixMenu::get_url( { type => 'sc', sc => $sc_uuid } );

        #$label = $nutanix_metadata->get_label( 'sc', $sc_uuid );
        my %sc_page = %{ NutanixMenu::create_page( $label, $url ) };
        push @{ $storage_container_folder->{children} }, \%sc_page;
      }
      push @{ $cluster_storages->{children} }, $storage_container_folder;

      #Virtual Disks
      my $virtual_disks_folder = NutanixMenu::create_folder('Virtual disks');
      my @virtual_disks        = @{ $nutanix_metadata->get_items( { item_type => 'vdisk', parent_type => 'cluster', parent_uuid => $cluster_uuid } ) };
      foreach my $vd (@virtual_disks) {
        my ( $vd_uuid, $vd_label ) = each %{$vd};

        if ( !$vd_label ) { next; }

        my $short_uuid = $nutanix_metadata->shorten_sr_uuid($vd_uuid);
        my $label      = $vd_label ? $vd_label : "no label - $short_uuid";
        my $url        = NutanixMenu::get_url( { type => 'vd', vd => $vd_uuid } );

        #$label = $nutanix_metadata->get_label( 'vd', $vd_uuid );
        my %vd_page = %{ NutanixMenu::create_page( $label, $url ) };
        push @{ $virtual_disks_folder->{children} }, \%vd_page;
      }
      push @{ $cluster_storages->{children} }, $virtual_disks_folder;

      #Physical Disks
      my $physical_disks_folder = NutanixMenu::create_folder('Physical disks');
      my @physical_disks        = @{ $nutanix_metadata->get_items( { item_type => 'disk', parent_type => 'cluster', parent_uuid => $cluster_uuid } ) };
      foreach my $sr (@physical_disks) {
        my ( $sr_uuid, $sr_label ) = each %{$sr};

        my $short_uuid = $nutanix_metadata->shorten_sr_uuid($sr_uuid);
        my $label      = $sr_label ? $sr_label : "no label - ${short_uuid}";
        my $url        = NutanixMenu::get_url( { type => 'storage', storage => $sr_uuid } );

        #$label = $nutanix_metadata->get_label( 'sr', $sr_uuid );
        my %sr_page = %{ NutanixMenu::create_page( $label, $url ) };
        push @{ $physical_disks_folder->{children} }, \%sr_page;
      }

      push @{ $cluster_storages->{children} }, $physical_disks_folder;

    }

    # add the cluster to menu tree
    $cluster_folder = NutanixMenu::create_folder($cluster_label);

    my %health_page;
    my $healths = $nutanix_metadata->get_conf_section('health');
    if ( exists $healths->{$cluster_uuid} ) {
      my $health_page_url = NutanixMenu::get_url( { type => "health", health => $cluster_uuid } );
      %health_page = %{ NutanixMenu::create_page( 'Health Status', $health_page_url ) };
    }

    $totals_url = NutanixMenu::get_url( { type => 'pool-aggr', pool => $cluster_uuid } );
    my %totals_page = %{ NutanixMenu::create_page( 'Server totals', $totals_url ) };
    $cluster_folder->{children} = \@host_entries;

    push @{ $cluster_folder->{children} }, $server_folder;

    if ($vms) {
      my $totals_vm_url   = NutanixMenu::get_url( { type => 'vm-aggr', pool => $cluster_uuid } );
      my %totals_vm_page  = %{ NutanixMenu::create_page( 'VM totals', $totals_vm_url ) };
      my %totals_vm_page2 = %{ NutanixMenu::create_page( 'Totals', $totals_vm_url ) };
      unshift @host_entries, \%totals_vm_page;
      push @{ $cluster_folder->{children} }, $vms;
    }
    if ($cluster_storages) {
      my $totals_storage_url  = NutanixMenu::get_url( { type => 'sr-aggr', pool => $cluster_uuid } );
      my %totals_storage_page = %{ NutanixMenu::create_page( 'Storage totals', $totals_storage_url ) };
      unshift @host_entries, \%totals_storage_page;
      push @{ $cluster_folder->{children} }, $cluster_storages;
    }

    unshift @host_entries, \%totals_page;
    if ( exists $healths->{$cluster_uuid} ) {
      unshift @{ $cluster_folder->{children} }, \%health_page;
    }
    push @cluster_folders, $cluster_folder;
  }

  return \@cluster_folders;
}

