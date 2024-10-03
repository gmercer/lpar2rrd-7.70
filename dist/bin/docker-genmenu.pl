# docker-genmenu.pl
# generate menu tree from Docker RRDs and print it as JSON

use 5.008_008;

use strict;
use warnings;

use JSON;
use Data::Dumper;
use HostCfg;
use Xorux_lib;
use DockerDataWrapperOOP;
use DockerMenu;
use DockerLoadDataModule;

defined $ENV{INPUTDIR} || warn( localtime() . ': INPUTDIR undefined, config etc/lpar2rrd.cfg probably has not been loaded ' . __FILE__ . ':' . __LINE__ ) && exit 1;

my $inputdir = $ENV{INPUTDIR};

my $docker_metadata = DockerDataWrapperOOP->new( { conf_labels => 1, conf_arch => 1, acl_check => 0 } );

my $menu_tree = DockerMenu::create_folder('Docker');
my $hosts     = gen_hosts();

if ( scalar @{$hosts} ) {

  my $totals_url_hosts  = DockerMenu::get_url( { type => 'hosts-aggr' } );
  my $totals_page_hosts = DockerMenu::create_page( 'Totals', $totals_url_hosts );
  $menu_tree->{children} = [$totals_page_hosts];

  push @{ $menu_tree->{children} }, @{$hosts};

  # print menu tree as JSON
  my $json      = JSON->new->utf8->pretty;
  my $json_data = $json->encode($menu_tree);
  print $json_data;
}
exit 0;

sub gen_hosts {

  my @host_folders = ();
  my @hosts        = @{ $docker_metadata->get_items( { item_type => 'host' } ) };

  foreach my $host (@hosts) {
    my ( $host_id, $host_label ) = each %{$host};

    my $host_folder = DockerMenu::create_folder($host_label);

    my @containers = @{ $docker_metadata->get_items( { item_type => 'container', parent_type => 'host', parent_id => $host_id } ) };
    my @volumes    = @{ $docker_metadata->get_items( { item_type => 'volume',    parent_type => 'host', parent_id => $host_id } ) };
    if ( scalar @containers >= 1 ) {
      my $totals_url_host  = DockerMenu::get_url( { type => 'host-aggr', host => $host_id } );
      my %totals_page_host = %{ DockerMenu::create_page( 'Totals', $totals_url_host ) };
      push @{ $host_folder->{children} }, \%totals_page_host;
    }

    # containers
    if ( scalar @containers >= 1 ) {

      my $containers_folder = DockerMenu::create_folder('Containers');

      foreach my $container (@containers) {
        my ( $container_uuid, $container_label ) = each %{$container};

        my $filepath = $docker_metadata->get_filepath_rrd( { type => 'container', uuid => $container_uuid } );
        unless ( defined $filepath && -f $filepath ) { next; }

        my $url            = DockerMenu::get_url( { type => 'container', container => $container_uuid } );
        my %container_page = %{ DockerMenu::create_page( $container_label, $url ) };
        push @{ $containers_folder->{children} }, \%container_page;
      }

      push @{ $host_folder->{children} }, $containers_folder;
    }

    # volumes
    if ( scalar @volumes >= 1 ) {

      my $volumes_folder = DockerMenu::create_folder('Volumes');

      foreach my $volume (@volumes) {
        my ( $volume_uuid, $volume_label ) = each %{$volume};

        $volume_label = length($volume_label) >= 12 ? substr( $volume_label, 0, 12 ) : $volume_label;

        my $filepath = $docker_metadata->get_filepath_rrd( { type => 'volume', uuid => $volume_uuid } );
        unless ( defined $filepath && -f $filepath ) { next; }

        my $url         = DockerMenu::get_url( { type => 'volume', volume => $volume_uuid } );
        my %volume_page = %{ DockerMenu::create_page( $volume_label, $url ) };
        push @{ $volumes_folder->{children} }, \%volume_page;
      }

      push @{ $host_folder->{children} }, $volumes_folder;
    }

    if ( scalar @containers >= 1 ) {
      push @host_folders, $host_folder;
    }
  }

  return \@host_folders;

}
