# cloudstack-genmenu.pl
# generate menu tree from Cloudstack RRDs and print it as JSON

use 5.008_008;

use strict;
use warnings;

use JSON;
use Data::Dumper;
use HostCfg;
use Xorux_lib;
use CloudstackDataWrapperOOP;
use CloudstackMenu;
use CloudstackLoadDataModule;

defined $ENV{INPUTDIR} || warn( localtime() . ': INPUTDIR undefined, config etc/lpar2rrd.cfg probably has not been loaded ' . __FILE__ . ':' . __LINE__ ) && exit 1;

my $inputdir = $ENV{INPUTDIR};

if ( keys %{ HostCfg::getHostConnections('Cloudstack') } == 0 ) {
  exit(0);
}

my %hostsConf = %{ HostCfg::getHostConnections('Cloudstack') };

my $cloudstack_metadata = CloudstackDataWrapperOOP->new( { acl_check => 0 } );

my $menu_tree = CloudstackMenu::create_folder('Apache CloudStack');
my $clouds    = gen_clouds();

if ( scalar @{$clouds} ) {
  my $configuration_page_url = CloudstackMenu::get_url( { type => 'configuration' } );
  my $configuration_page     = CloudstackMenu::create_page( 'Configuration', $configuration_page_url );
  my $alert_page_url         = CloudstackMenu::get_url( { type => 'alert' } );
  my $alert_page             = CloudstackMenu::create_page( 'Alerts', $alert_page_url );

  $menu_tree->{children} = [ $configuration_page, $alert_page ];
  push @{ $menu_tree->{children} }, @{$clouds};

  # print menu tree as JSON
  my $json      = JSON->new->utf8->pretty;
  my $json_data = $json->encode($menu_tree);
  print $json_data;
}
exit 0;

sub gen_clouds {

  my @cloud_folders = ();
  my @clouds        = @{ $cloudstack_metadata->get_items( { item_type => 'cloud' } ) };

  foreach my $cloud (@clouds) {
    my ( $cloud_id, $cloud_label ) = each %{$cloud};

    if ( !defined $hostsConf{$cloud_label} ) {
      next;
    }

    my $cloud_folder = CloudstackMenu::create_folder($cloud_label);

    my ( $host_folder, $totals_url_host, %totals_page_host, $instance_folder, $totals_url_instance, %totals_page_instance, $volume_folder, $totals_url_volume, %totals_page_volume, $primaryStorage_folder, $totals_url_primaryStorage, %totals_page_primaryStorage );

    #hosts
    my @hosts = @{ $cloudstack_metadata->get_items( { item_type => 'host', parent_type => 'cloud', parent_id => $cloud_id } ) };
    if ( scalar @hosts >= 1 ) {
      $host_folder      = CloudstackMenu::create_folder('Host');
      $totals_url_host  = CloudstackMenu::get_url( { type => 'host-aggr', cloud => $cloud_id } );
      %totals_page_host = %{ CloudstackMenu::create_page( 'Host Totals', $totals_url_host ) };

      foreach my $host (@hosts) {
        my ( $host_uuid, $host_label ) = each %{$host};

        my $filepath = $cloudstack_metadata->get_filepath_rrd( { type => 'host', uuid => $host_uuid } );
        unless ( -f $filepath ) { next; }

        my $url       = CloudstackMenu::get_url( { type => 'host', host => $host_uuid } );
        my %host_page = %{ CloudstackMenu::create_page( $host_label, $url ) };
        push @{ $host_folder->{children} }, \%host_page;

      }

      push @{ $cloud_folder->{children} }, \%totals_page_host;

    }

    #instance
    my @instances = @{ $cloudstack_metadata->get_items( { item_type => 'instance', parent_type => 'cloud', parent_id => $cloud_id } ) };
    if ( scalar @instances >= 1 ) {
      $instance_folder      = CloudstackMenu::create_folder('Instance');
      $totals_url_instance  = CloudstackMenu::get_url( { type => 'instance-aggr', cloud => $cloud_id } );
      %totals_page_instance = %{ CloudstackMenu::create_page( 'Instance Totals', $totals_url_instance ) };

      foreach my $instance (@instances) {
        my ( $instance_uuid, $instance_label ) = each %{$instance};

        my $filepath = $cloudstack_metadata->get_filepath_rrd( { type => 'instance', uuid => $instance_uuid } );
        unless ( -f $filepath ) { next; }

        my $url           = CloudstackMenu::get_url( { type => 'instance', instance => $instance_uuid } );
        my %instance_page = %{ CloudstackMenu::create_page( $instance_label, $url ) };
        push @{ $instance_folder->{children} }, \%instance_page;

      }

      push @{ $cloud_folder->{children} }, \%totals_page_instance;

    }

    #volume
    my @volumes = @{ $cloudstack_metadata->get_items( { item_type => 'volume', parent_type => 'cloud', parent_id => $cloud_id } ) };
    if ( scalar @volumes >= 1 ) {
      $volume_folder      = CloudstackMenu::create_folder('Volume');
      $totals_url_volume  = CloudstackMenu::get_url( { type => 'volume-aggr', cloud => $cloud_id } );
      %totals_page_volume = %{ CloudstackMenu::create_page( 'Volume Totals', $totals_url_volume ) };

      foreach my $volume (@volumes) {
        my ( $volume_uuid, $volume_label ) = each %{$volume};

        my $filepath = $cloudstack_metadata->get_filepath_rrd( { type => 'volume', uuid => $volume_uuid } );
        unless ( -f $filepath ) { next; }

        my $url         = CloudstackMenu::get_url( { type => 'volume', volume => $volume_uuid } );
        my %volume_page = %{ CloudstackMenu::create_page( $volume_label, $url ) };
        push @{ $volume_folder->{children} }, \%volume_page;

      }

      push @{ $cloud_folder->{children} }, \%totals_page_volume;

    }

    #primaryStorage
    my @primaryStorages = @{ $cloudstack_metadata->get_items( { item_type => 'primaryStorage', parent_type => 'cloud', parent_id => $cloud_id } ) };
    if ( scalar @primaryStorages >= 1 ) {
      $primaryStorage_folder      = CloudstackMenu::create_folder('Primary Storage');
      $totals_url_primaryStorage  = CloudstackMenu::get_url( { type => 'primaryStorage-aggr', cloud => $cloud_id } );
      %totals_page_primaryStorage = %{ CloudstackMenu::create_page( 'Primary Storage Totals', $totals_url_primaryStorage ) };

      foreach my $primaryStorage (@primaryStorages) {
        my ( $primaryStorage_uuid, $primaryStorage_label ) = each %{$primaryStorage};

        my $filepath = $cloudstack_metadata->get_filepath_rrd( { type => 'primaryStorage', uuid => $primaryStorage_uuid } );
        unless ( -f $filepath ) { next; }

        my $url                 = CloudstackMenu::get_url( { type => 'primaryStorage', primaryStorage => $primaryStorage_uuid } );
        my %primaryStorage_page = %{ CloudstackMenu::create_page( $primaryStorage_label, $url ) };
        push @{ $primaryStorage_folder->{children} }, \%primaryStorage_page;

      }

      push @{ $cloud_folder->{children} }, \%totals_page_primaryStorage;

    }

    if ( scalar @hosts >= 1 ) {
      push @{ $cloud_folder->{children} }, $host_folder;
    }
    if ( scalar @instances >= 1 ) {
      push @{ $cloud_folder->{children} }, $instance_folder;
    }
    if ( scalar @volumes >= 1 ) {
      push @{ $cloud_folder->{children} }, $volume_folder;
    }
    if ( scalar @primaryStorages >= 1 ) {
      push @{ $cloud_folder->{children} }, $primaryStorage_folder;
    }

    push @cloud_folders, $cloud_folder;

  }

  return \@cloud_folders;

}
