# gcloud-genmenu.pl
# generate menu tree from Nutanix RRDs and print it as JSON
# replacement for an older equivalent to `find_active_lpar.pl` that generated `menu.txt`

use 5.008_008;

use strict;
use warnings;

use JSON;
use Data::Dumper;
use HostCfg;
use Xorux_lib;
use GCloudDataWrapperOOP;
use GCloudMenu;
use GCloudLoadDataModule;

defined $ENV{INPUTDIR} || warn( localtime() . ': INPUTDIR undefined, config etc/lpar2rrd.cfg probably has not been loaded ' . __FILE__ . ':' . __LINE__ ) && exit 1;

my $inputdir = $ENV{INPUTDIR};

if ( keys %{ HostCfg::getHostConnections('GCloud') } == 0 ) {
  exit(0);
}

my $gcloud_metadata = GCloudDataWrapperOOP->new( { conf_agent => 1, acl_check => 0 } );

my $menu_tree = GCloudMenu::create_folder('Google Cloud');
my $regions   = gen_regions();

if ( scalar @{$regions} ) {
  my $configuration_page_url = GCloudMenu::get_url( { type => 'configuration' } );
  my $configuration_page     = GCloudMenu::create_page( 'Configuration', $configuration_page_url );

  my $compute_engine_running_page_url = GCloudMenu::get_url( { type => 'engine-running' } );
  my $compute_engine_running_page     = GCloudMenu::create_page( 'Instance Overview', $compute_engine_running_page_url );

  $menu_tree->{children} = [ $configuration_page, $compute_engine_running_page ];
  push @{ $menu_tree->{children} }, @{$regions};

  # print menu tree as JSON
  my $json      = JSON->new->utf8->pretty;
  my $json_data = $json->encode($menu_tree);
  print $json_data;
}
exit 0;

sub gen_regions {

  my @region_folders = ();
  my @regions        = @{ $gcloud_metadata->get_items( { item_type => 'region' } ) };

  foreach my $region (@regions) {
    my ( $region_id, $region_label ) = each %{$region};

    my ( $compute_folder, $totals_url_compute, %totals_page_compute, $databases_folder );

    my @computes = @{ $gcloud_metadata->get_items( { item_type => 'compute', parent_type => 'region', parent_id => $region_id } ) };

    if ( scalar @computes >= 1 ) {

      $compute_folder      = GCloudMenu::create_folder('Compute Engine');
      $totals_url_compute  = GCloudMenu::get_url( { type => 'compute-aggr', region => $region_id } );
      %totals_page_compute = %{ GCloudMenu::create_page( 'Compute Engine Totals', $totals_url_compute ) };

      foreach my $compute (@computes) {
        my ( $compute_uuid, $compute_label ) = each %{$compute};

        my $filepath = $gcloud_metadata->get_filepath_rrd( { type => 'compute', uuid => $compute_uuid } );
        unless ( -f $filepath ) { next; }

        my $url          = GCloudMenu::get_url( { type => 'compute', compute => $compute_uuid } );
        my %compute_page = %{ GCloudMenu::create_page( $compute_label, $url ) };
        push @{ $compute_folder->{children} }, \%compute_page;

      }

    }

    my @databases = @{ $gcloud_metadata->get_items( { item_type => 'database', parent_type => 'region', parent_id => $region_id } ) };

    if ( scalar @databases >= 1 ) {
      my ( $databases_folder_mysql, $databases_folder_postgres );
      $databases_folder = GCloudMenu::create_folder('Google SQL');

      my @databases_mysql = @{ $gcloud_metadata->get_items( { item_type => 'database', parent_type => 'region', parent_id => $region_id, engine => 'mysql' } ) };

      if ( scalar @databases_mysql >= 1 ) {

        $databases_folder_mysql = GCloudMenu::create_folder('MySQL');

        foreach my $mysql (@databases_mysql) {
          my ( $mysql_uuid, $mysql_label ) = each %{$mysql};
          my $url        = GCloudMenu::get_url( { type => 'database-mysql', 'database-mysql' => $mysql_uuid } );
          my %mysql_page = %{ GCloudMenu::create_page( $mysql_label, $url ) };
          push @{ $databases_folder_mysql->{children} }, \%mysql_page;
        }

        push @{ $databases_folder->{children} }, $databases_folder_mysql;
      }

      my @databases_postgres = @{ $gcloud_metadata->get_items( { item_type => 'database', parent_type => 'region', parent_id => $region_id, engine => 'postgres' } ) };

      if ( scalar @databases_postgres >= 1 ) {

        $databases_folder_postgres = GCloudMenu::create_folder('Postgres');

        foreach my $postgres (@databases_postgres) {
          my ( $postgres_uuid, $postgres_label ) = each %{$postgres};
          my $url           = GCloudMenu::get_url( { type => 'database-postgres', 'database-postgres' => $postgres_uuid } );
          my %postgres_page = %{ GCloudMenu::create_page( $postgres_label, $url ) };
          push @{ $databases_folder_postgres->{children} }, \%postgres_page;
        }

        push @{ $databases_folder->{children} }, $databases_folder_postgres;
      }

    }

    my $region_folder = GCloudMenu::create_folder($region_label);
    if ( scalar @computes >= 1 ) {
      push @{ $region_folder->{children} }, \%totals_page_compute;
    }
    if ( scalar @computes >= 1 ) {
      push @{ $region_folder->{children} }, $compute_folder;
    }
    if ( scalar @databases >= 1 ) {
      push @{ $region_folder->{children} }, $databases_folder;
    }

    push @region_folders, $region_folder;

  }

  return \@region_folders;
}
