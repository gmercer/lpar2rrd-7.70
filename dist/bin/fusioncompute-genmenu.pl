# fusioncompute-genmenu.pl
# generate menu tree from FusionCompute RRDs and print it as JSON
# replacement for an older equivalent to `find_active_lpar.pl` that generated `menu.txt`

use 5.008_008;

use strict;
use warnings;

use JSON;
use Data::Dumper;
use HostCfg;
use Xorux_lib;
use FusionComputeDataWrapperOOP;
use FusionComputeMenu;

defined $ENV{INPUTDIR} || warn( localtime() . ': INPUTDIR undefined, config etc/lpar2rrd.cfg probably has not been loaded ' . __FILE__ . ':' . __LINE__ ) && exit 1;

my $inputdir = $ENV{INPUTDIR};
my $host_dir = "$inputdir/data/FusionCompute/Host";

unless ( -d $host_dir ) {
  exit;
}

if ( keys %{ HostCfg::getHostConnections('FusionCompute') } == 0 ) {
  exit(0);
}

my $fc_metadata = FusionComputeDataWrapperOOP->new( { conf_labels => 1, conf_arch => 1, acl_check => 0 } );

my $menu_tree = FusionComputeMenu::create_folder('FusionCompute');
my $sites     = gen_sites();

if ( scalar @{$sites} ) {

  my $heatmap_page_url = FusionComputeMenu::get_url( { type => 'heatmap' } );
  my $heatmap_page     = FusionComputeMenu::create_page( 'Heatmap', $heatmap_page_url );

  my $configuration_page_url = FusionComputeMenu::get_url( { type => 'configuration' } );
  my $configuration_page     = FusionComputeMenu::create_page( 'Configuration', $configuration_page_url );

  my $health_page_url = FusionComputeMenu::get_url( { type => 'health' } );
  my $health_page     = FusionComputeMenu::create_page( 'Health Status', $health_page_url );

  my $alerts_page_url = FusionComputeMenu::get_url( { type => 'alerts' } );
  my $alerts_page     = FusionComputeMenu::create_page( 'Alerts', $alerts_page_url );

  my $topten_page_url = FusionComputeMenu::get_url( { type => 'topten_fusioncompute' } );
  my $topten_page     = FusionComputeMenu::create_page( 'VM TOP', $topten_page_url );

  $menu_tree->{children} = [ $heatmap_page, $configuration_page, $health_page, $alerts_page, $topten_page ];

  push @{ $menu_tree->{children} }, @{$sites};

  # print menu tree as JSON
  my $json      = JSON->new->utf8->pretty;
  my $json_data = $json->encode($menu_tree);
  print $json_data;
}
exit 0;

sub gen_sites {

  my @site_folders = ();

  # sites
  my @sites = @{ $fc_metadata->get_items( { item_type => 'site' } ) };
  foreach my $site (@sites) {
    my ( $site_uuid, $site_label ) = each %{$site};
    my $site_folder = FusionComputeMenu::create_folder($site_label);

    my $site_totals_url  = FusionComputeMenu::get_url( { type => 'cluster-aggr', site => $site_uuid } );
    my %site_totals_page = %{ FusionComputeMenu::create_page( 'Cluster Totals', $site_totals_url ) };
    push @{ $site_folder->{children} }, \%site_totals_page;

    my $datastore_totals_url  = FusionComputeMenu::get_url( { type => 'datastore-aggr', site => $site_uuid } );
    my %datastore_totals_page = %{ FusionComputeMenu::create_page( 'Datastore Totals', $datastore_totals_url ) };
    push @{ $site_folder->{children} }, \%datastore_totals_page;

    # clusters under site
    my $clusters_folder = FusionComputeMenu::create_folder('Cluster');
    my @clusters        = @{ $fc_metadata->get_items( { item_type => 'cluster', parent_type => 'site', parent_uuid => $site_uuid } ) };
    foreach my $cluster (@clusters) {
      my ( $cluster_uuid, $cluster_label ) = each %{$cluster};

      my $cluster_folder = FusionComputeMenu::create_folder($cluster_label);

      my $cluster_totals_url  = FusionComputeMenu::get_url( { type => 'cluster', cluster => $cluster_uuid } );
      my %cluster_totals_page = %{ FusionComputeMenu::create_page( 'Cluster', $cluster_totals_url ) };
      push @{ $cluster_folder->{children} }, \%cluster_totals_page;

      my $host_totals_url  = FusionComputeMenu::get_url( { type => 'host-aggr', cluster => $cluster_uuid } );
      my %host_totals_page = %{ FusionComputeMenu::create_page( 'Host Totals', $host_totals_url ) };
      push @{ $cluster_folder->{children} }, \%host_totals_page;

      my $vm_totals_url  = FusionComputeMenu::get_url( { type => 'vm-aggr', cluster => $cluster_uuid } );
      my %vm_totals_page = %{ FusionComputeMenu::create_page( 'VM Totals', $vm_totals_url ) };
      push @{ $cluster_folder->{children} }, \%vm_totals_page;

      # hosts
      my $hosts_folder = FusionComputeMenu::create_folder('Host');
      my @hosts        = @{ $fc_metadata->get_items( { item_type => 'host', parent_type => 'cluster', parent_uuid => $cluster_uuid } ) };
      foreach my $host (@hosts) {
        my ( $host_uuid, $host_label ) = each %{$host};

        my $url  = FusionComputeMenu::get_url( { type => 'host', host => $host_uuid } );
        my %page = %{ FusionComputeMenu::create_page( $host_label, $url ) };
        push @{ $hosts_folder->{children} }, \%page;

      }
      push @{ $cluster_folder->{children} }, $hosts_folder;

      # vms
      my $vms_folder = FusionComputeMenu::create_folder('VM');
      my @vms        = @{ $fc_metadata->get_items( { item_type => 'vm', parent_type => 'cluster', parent_uuid => $cluster_uuid } ) };
      foreach my $vm (@vms) {
        my ( $vm_uuid, $vm_label ) = each %{$vm};

        my $url  = FusionComputeMenu::get_url( { type => 'vm', vm => $vm_uuid } );
        my %page = %{ FusionComputeMenu::create_page( $vm_label, $url ) };
        push @{ $vms_folder->{children} }, \%page;

      }
      push @{ $cluster_folder->{children} }, $vms_folder;

      push @{ $clusters_folder->{children} }, $cluster_folder;
    }
    push @{ $site_folder->{children} }, $clusters_folder;

    # datastores under site
    my $datastores_folder = FusionComputeMenu::create_folder('Datastore');
    my @datastores        = @{ $fc_metadata->get_items( { item_type => 'datastore', parent_type => 'site', parent_uuid => $site_uuid } ) };
    foreach my $datastore (@datastores) {
      my ( $datastore_uuid, $datastore_label ) = each %{$datastore};

      my $url  = FusionComputeMenu::get_url( { type => 'datastore', datastore => $datastore_uuid } );
      my %page = %{ FusionComputeMenu::create_page( $datastore_label, $url ) };
      push @{ $datastores_folder->{children} }, \%page;
    }
    push @{ $site_folder->{children} }, $datastores_folder;

    push @site_folders, $site_folder;
  }

  return \@site_folders;
}

