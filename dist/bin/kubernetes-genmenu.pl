# kubernetes-genmenu.pl
# generate menu tree from Kubernetes RRDs and print it as JSON

use 5.008_008;

use strict;
use warnings;

use JSON;
use Data::Dumper;
use HostCfg;
use Xorux_lib;
use KubernetesDataWrapper;
use KubernetesDataWrapperOOP;
use KubernetesMenu;
use KubernetesLoadDataModule;

defined $ENV{INPUTDIR} || warn( localtime() . ': INPUTDIR undefined, config etc/lpar2rrd.cfg probably has not been loaded ' . __FILE__ . ':' . __LINE__ ) && exit 1;

my $inputdir = $ENV{INPUTDIR};

if ( keys %{ HostCfg::getHostConnections('Kubernetes') } == 0 ) {
  exit(0);
}

my %hosts = %{ HostCfg::getHostConnections('Kubernetes') };

my $menu_tree = KubernetesMenu::create_folder('Kubernetes');
my $clusters  = gen_clusters();

if ( scalar @{$clusters} ) {
  my $configuration_page_url = KubernetesMenu::get_url( { type => 'configuration' } );
  my $configuration_page     = KubernetesMenu::create_page( 'Configuration', $configuration_page_url );

  my $top_page_url = KubernetesMenu::get_url( { type => 'top' } );
  my $top_page     = KubernetesMenu::create_page( 'Pods Top', $top_page_url );

  my $pods_page_url = KubernetesMenu::get_url( { type => 'pods-overview' } );
  my $pods_page     = KubernetesMenu::create_page( 'Pods Overview', $pods_page_url );

  $menu_tree->{children} = [ $configuration_page, $top_page, $pods_page ];
  push @{ $menu_tree->{children} }, @{$clusters};

  # print menu tree as JSON
  my $json      = JSON->new->utf8->pretty;
  my $json_data = $json->encode($menu_tree);
  print $json_data;
}
exit 0;

sub gen_clusters {

  my $kubernetesWrapper = KubernetesDataWrapperOOP->new();

  my @cluster_folders = ();
  my @clusters        = @{ $kubernetesWrapper->get_items( { item_type => 'cluster' } ) };

  foreach my $cluster (@clusters) {
    my ( $cluster_id, $cluster_label ) = each %{$cluster};

    if ( !defined $hosts{$cluster_label} ) {
      next;
    }

    my ( $node_folder, $totals_url_node, %totals_page_node, $pod_folder, $totals_url_pod, %totals_page_pod, $totals_url_namespace, %totals_page_namespace, $container_folder, $totals_url_container, %totals_page_container );

    my @nodes = @{ $kubernetesWrapper->get_items( { item_type => 'node', parent_type => 'cluster', parent_id => $cluster_id } ) };
    my @pods_all = @{ $kubernetesWrapper->get_items( { item_type => 'pod', parent_type => 'cluster', parent_id => $cluster_id } ) };

    #my $conditions_cluster_url  = KubernetesMenu::get_url( { type => 'conditions-cluster', cluster => $cluster_id } );
    #my %conditions_cluster_page = %{ KubernetesMenu::create_page( 'Conditions', $conditions_cluster_url ) };

    if ( scalar @nodes >= 1 ) {
      $node_folder      = KubernetesMenu::create_folder('Nodes');
      $totals_url_node  = KubernetesMenu::get_url( { type => 'node-aggr', cluster => $cluster_id } );
      %totals_page_node = %{ KubernetesMenu::create_page( 'Node Totals', $totals_url_node ) };

      foreach my $node (@nodes) {
        my ( $node_uuid, $node_label ) = each %{$node};

        my $url       = KubernetesMenu::get_url( { type => 'node', node => $node_uuid } );
        my %node_page = %{ KubernetesMenu::create_page( $node_label, $url ) };
        push @{ $node_folder->{children} }, \%node_page;

      }
    }
 
    my @namespaces        = @{ $kubernetesWrapper->get_items( { item_type => 'namespace', parent_type => 'cluster', parent_id => $cluster_id } ) };
    if ( scalar @namespaces >= 1 ) {
      $totals_url_namespace  = KubernetesMenu::get_url( { type => 'namespace-aggr', cluster => $cluster_id } );
      %totals_page_namespace = %{ KubernetesMenu::create_page( 'Namespace Totals', $totals_url_namespace ) };
    }

    my $namespaces_folder = KubernetesMenu::create_folder('Namespaces');

    foreach my $namespace (@namespaces) {
      my ( $namespace_id, $namespace_label ) = each %{$namespace};

      my $n_filepath = $kubernetesWrapper->get_filepath_rrd( { type => 'namespace', uuid => $namespace_id } );

      if ( !-f $n_filepath ) {
        next;
      }

      my $namespace_folder = KubernetesMenu::create_folder($namespace_label);

      my $n_url  = KubernetesMenu::get_url( { type => 'namespace', namespace => $namespace_id } );
      my %n_page = %{ KubernetesMenu::create_page( "Totals", $n_url ) };
      push @{ $namespace_folder->{children} }, \%n_page;

      my @pods = @{ $kubernetesWrapper->get_items( { item_type => 'pod', parent_type => 'namespace', parent_id => $namespace_id } ) };

      if ( scalar @pods >= 1 ) {

        $pod_folder      = KubernetesMenu::create_folder('Pods');
        $totals_url_pod  = KubernetesMenu::get_url( { type => 'pod-aggr', cluster => $cluster_id } );
        %totals_page_pod = %{ KubernetesMenu::create_page( 'Pods Aggregated', $totals_url_pod ) };

        foreach my $pod (@pods) {
          my ( $pod_uuid, $pod_label ) = each %{$pod};

          my $pod_container_folder = KubernetesMenu::create_folder($pod_label);
          my $url                  = KubernetesMenu::get_url( { type => 'pod', pod => $pod_uuid } );
          my %pod_page             = %{ KubernetesMenu::create_page( "Totals", $url ) };
          push @{ $pod_container_folder->{children} }, \%pod_page;

	  #my $conditions_url  = KubernetesMenu::get_url( { type => 'conditions-pod', pod => $pod_uuid } );
	  #my %conditions_page = %{ KubernetesMenu::create_page( "Conditions", $conditions_url ) };
	  #push @{ $pod_container_folder->{children} }, \%conditions_page;

          my $containers_info_url  = KubernetesMenu::get_url( { type => 'containers-info', pod => $pod_uuid } );
          my %containers_info_page = %{ KubernetesMenu::create_page( "Containers Info", $containers_info_url ) };
          push @{ $pod_container_folder->{children} }, \%containers_info_page;

          my @containers = @{ $kubernetesWrapper->get_items( { item_type => 'container', parent_type => 'pod', parent_id => $pod_uuid } ) };

          if ( scalar @containers >= 1 ) {
            $container_folder = KubernetesMenu::create_folder('Containers');
            foreach my $container (@containers) {
              my ( $container_uuid, $container_label ) = each %{$container};

              my $url            = KubernetesMenu::get_url( { type => 'container', container => $container_uuid } );
              my %container_page = %{ KubernetesMenu::create_page( $container_label, $url ) };
              push @{ $container_folder->{children} }, \%container_page;
            }
            push @{ $pod_container_folder->{children} }, $container_folder;
          }

          push @{ $namespace_folder->{children} }, $pod_container_folder;
        }

      }
      push @{ $namespaces_folder->{children} }, $namespace_folder;
    }

    my $cluster_folder = KubernetesMenu::create_folder($cluster_label);

    #if ( scalar @pods_all >= 1 ) {
    #  push @{ $cluster_folder->{children} }, \%conditions_cluster_page;
    #}

    if ( scalar @nodes >= 1 ) {
      push @{ $cluster_folder->{children} }, \%totals_page_node;
    }
    if ( scalar @namespaces >= 1 ) {
      push @{ $cluster_folder->{children} }, \%totals_page_namespace;
    }
    if ( scalar @pods_all >= 1 ) {
      push @{ $cluster_folder->{children} }, \%totals_page_pod;
    }
    if ( scalar @nodes >= 1 ) {
      push @{ $cluster_folder->{children} }, $node_folder;
    }
    if ( scalar @namespaces >= 1 ) {
      push @{ $cluster_folder->{children} }, $namespaces_folder;
    }

    push @cluster_folders, $cluster_folder;
  }

  return \@cluster_folders;

}
