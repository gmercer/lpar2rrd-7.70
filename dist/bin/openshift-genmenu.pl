# openshift-genmenu.pl
# generate menu tree from Openshift RRDs and print it as JSON

use 5.008_008;

use strict;
use warnings;

use JSON;
use Data::Dumper;
use HostCfg;
use Xorux_lib;
use OpenshiftDataWrapper;
use OpenshiftDataWrapperOOP;
use OpenshiftMenu;

defined $ENV{INPUTDIR} || warn( localtime() . ': INPUTDIR undefined, config etc/lpar2rrd.cfg probably has not been loaded ' . __FILE__ . ':' . __LINE__ ) && exit 1;

my $inputdir = $ENV{INPUTDIR};
my $data_dir = "$inputdir/data/Openshift";
my $tmp_dir  = "$inputdir/tmp";

my %hosts = %{ HostCfg::getHostConnections('Openshift') };

my $menu_tree = OpenshiftMenu::create_folder('Red Hat OpenShift');
my $clusters  = gen_clusters();

if ( scalar @{$clusters} ) {
  my $infrastructure_page_url = OpenshiftMenu::get_url( { type => 'infrastructure' } );
  my $infrastructure_page     = OpenshiftMenu::create_page( 'Infrastructure', $infrastructure_page_url );

  my $configuration_page_url = OpenshiftMenu::get_url( { type => 'configuration' } );
  my $configuration_page     = OpenshiftMenu::create_page( 'Configuration', $configuration_page_url );

  my $top_page_url = OpenshiftMenu::get_url( { type => 'top' } );
  my $top_page     = OpenshiftMenu::create_page( 'Pods Top', $top_page_url );

  my $pods_page_url = OpenshiftMenu::get_url( { type => 'pods-overview' } );
  my $pods_page     = OpenshiftMenu::create_page( 'Pods Overview', $pods_page_url );

  $menu_tree->{children} = [ $infrastructure_page, $configuration_page, $top_page, $pods_page ];
  push @{ $menu_tree->{children} }, @{$clusters};

  # print menu tree as JSON
  my $json      = JSON->new->utf8->pretty;
  my $json_data = $json->encode($menu_tree);

  # save to menu_openshift.json
   open my $fh, ">", $tmp_dir."/menu_openshift.json";
   print $fh $json_data;
   close $fh;

  print $json_data;
}
exit 0;

sub gen_clusters {

  my $openshiftWrapper = OpenshiftDataWrapperOOP->new();

  debug_new("START GENMENU OPENSHIFT\n");

  my @cluster_folders = ();
  my @clusters        = @{ $openshiftWrapper->get_items( { item_type => 'cluster' } ) };

  foreach my $cluster (@clusters) {
    my ( $cluster_id, $cluster_label ) = each %{$cluster};

    if ( !defined $hosts{$cluster_label} ) {
      next;
    }

    my ( $totals_url_namespace, %totals_page_namespace, $node_folder, $totals_url_node, %totals_page_node, $pod_folder, $project_folder, $projects_folder, $totals_url_pod, %totals_page_pod, $container_folder, $totals_url_container, %totals_page_container );

    my @nodes = @{ $openshiftWrapper->get_items( { item_type => 'node', parent_type => 'cluster', parent_id => $cluster_id, menu => 1 } ) };

    my $conditions_cluster_url = OpenshiftMenu::get_url({ type => 'conditions-cluster', cluster => $cluster_id });
    my %conditions_cluster_page = %{ OpenshiftMenu::create_page('Conditions', $conditions_cluster_url) };

    #my $services_url  = OpenshiftMenu::get_url( { type => 'services', cluster => $cluster_id } );
    #my %services_page = %{ OpenshiftMenu::create_page( 'Services', $services_url ) };

    if ( scalar @nodes >= 1 ) {
      $node_folder      = OpenshiftMenu::create_folder('Nodes');
      $totals_url_node  = OpenshiftMenu::get_url( { type => 'node-aggr', cluster => $cluster_id } );
      %totals_page_node = %{ OpenshiftMenu::create_page( 'Node Totals', $totals_url_node ) };

      foreach my $node (@nodes) {
        my ( $node_uuid, $node_label ) = each %{$node};

        debug( "$cluster_label -> add node $node_label - " . localtime() . "\n" );

        my $url       = OpenshiftMenu::get_url( { type => 'node', node => $node_uuid } );
        my %node_page = %{ OpenshiftMenu::create_page( $node_label, $url ) };
        push @{ $node_folder->{children} }, \%node_page;

      }
    }

    my @projects = @{ $openshiftWrapper->get_items( { item_type => 'project', parent_type => 'cluster', parent_id => $cluster_id } ) };
    if ( scalar @projects >= 1 ) {

      $totals_url_namespace  = OpenshiftMenu::get_url( { type => 'namespace-aggr', cluster => $cluster_id } );
      %totals_page_namespace = %{ OpenshiftMenu::create_page( 'Namespace Totals', $totals_url_namespace ) };

      $projects_folder = OpenshiftMenu::create_folder('Projects');
      foreach my $project (@projects) {
        my ( $project_uuid, $project_label ) = each %{$project};

	my $n_filepath = $openshiftWrapper->get_filepath_rrd( { type => 'namespace', uuid => $project_uuid } );

        if ( !-f $n_filepath ) {
          next;
        }

	$project_folder = OpenshiftMenu::create_folder($project_label);

	my $n_url  = OpenshiftMenu::get_url( { type => 'namespace', namespace => $project_uuid } );
        my %n_page = %{ OpenshiftMenu::create_page( "Totals", $n_url ) };
        push @{ $project_folder->{children} }, \%n_page;

        my @project_pods = @{ $openshiftWrapper->get_items( { item_type => 'pod', parent_type => 'namespace', parent_id => $project_uuid, cluster => $cluster_id } ) };
        if ( scalar @project_pods >= 1 ) {
          
	  my $totals_url_project_pods  = OpenshiftMenu::get_url( { type => 'project-pod-aggr', project => $project_uuid } );
          my %totals_page_project_pods = %{ OpenshiftMenu::create_page( 'Pods Aggregated', $totals_url_project_pods ) };
          push @{ $project_folder->{children} }, \%totals_page_project_pods;

          foreach my $pod (@project_pods) {
            my ( $pod_uuid, $pod_label ) = each %{$pod};

            debug( "$cluster_label -> add pod $pod_label - " . localtime() . "\n" );

            $pod_folder = OpenshiftMenu::create_folder($pod_label);

            my $url      = OpenshiftMenu::get_url( { type => 'pod', pod => $pod_uuid } );
            my %pod_page = %{ OpenshiftMenu::create_page( "Totals", $url ) };
            push @{ $pod_folder->{children} }, \%pod_page;

            my $conditions_url  = OpenshiftMenu::get_url( { type => 'conditions-pod', pod => $pod_uuid } );
            my %conditions_page = %{ OpenshiftMenu::create_page( "Conditions", $conditions_url ) };
            push @{ $pod_folder->{children} }, \%conditions_page;

            my @containers = @{ $openshiftWrapper->get_items( { item_type => 'container', parent_type => 'pod', parent_id => $pod_uuid } ) };
            if ( scalar @containers >= 1 ) {
              $container_folder = OpenshiftMenu::create_folder('Containers');
              foreach my $container (@containers) {
                my ( $container_uuid, $container_label ) = each %{$container};

                debug( "$cluster_label -> add container $container_label - " . localtime() . "\n" );

                my $url            = OpenshiftMenu::get_url( { type => 'container', container => $container_uuid } );
                my %container_page = %{ OpenshiftMenu::create_page( $container_label, $url ) };
                push @{ $container_folder->{children} }, \%container_page;
              }
              push @{ $pod_folder->{children} }, $container_folder;
            }

            push @{ $project_folder->{children} }, $pod_folder;

          }
        }
	push @{ $projects_folder->{children} }, $project_folder;
      }
    }

    my $cluster_folder = OpenshiftMenu::create_folder($cluster_label);

    #push @{$cluster_folder->{children}}, \%conditions_cluster_page;
    #push @{ $cluster_folder->{children} }, \%services_page;

    my $top_url      = OpenshiftMenu::get_url( { type => 'top-cluster', cluster => $cluster_id } );
    my %top_pod_page = %{ OpenshiftMenu::create_page( "Pods Top", $top_url ) };

    my $overview_url      = OpenshiftMenu::get_url( { type => 'pods-overview-cluster', cluster => $cluster_id } );
    my %overview_pod_page = %{ OpenshiftMenu::create_page( "Pods Overview", $overview_url ) };

    if ( scalar @nodes >= 1 ) {
      push @{ $cluster_folder->{children} }, \%top_pod_page;
      push @{ $cluster_folder->{children} }, \%overview_pod_page;
      push @{ $cluster_folder->{children} }, \%totals_page_node;
    }
    if ( scalar @projects >= 1 ) {
      push @{ $cluster_folder->{children} }, \%totals_page_namespace;
    }
    if ( scalar @nodes >= 1 ) {
      push @{ $cluster_folder->{children} }, $node_folder;
    }

    if ( scalar @projects >= 1 ) {
      @{ $projects_folder->{children} } = sort { $a->{title} cmp $b->{title} } @{ $projects_folder->{children} };
      push @{ $cluster_folder->{children} }, $projects_folder;
    }

    push @cluster_folders, $cluster_folder;
  }

  return \@cluster_folders;

}

sub debug {
  my $text = shift;

  if ($text) {
    open my $fh, ">>", $data_dir . "/debug.log";
    print $fh $text;
    close $fh;
  }
}

sub debug_new {
  my $text = shift;

  if ($text) {
    open my $fh, ">", $data_dir . "/debug.log";
    print $fh $text;
    close $fh;
  }
}
