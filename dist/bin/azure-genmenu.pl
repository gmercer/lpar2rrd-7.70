# azure-genmenu.pl
# generate menu tree from Azure RRDs and print it as JSON
# replacement for an older equivalent to `find_active_lpar.pl` that generated `menu.txt`

use 5.008_008;

use strict;
use warnings;

use JSON;
use Data::Dumper;
use HostCfg;
use Xorux_lib;
use AzureDataWrapperOOP;
use AzureMenu;

defined $ENV{INPUTDIR} || warn( localtime() . ': INPUTDIR undefined, config etc/lpar2rrd.cfg probably has not been loaded ' . __FILE__ . ':' . __LINE__ ) && exit 1;

if ( keys %{ HostCfg::getHostConnections('Azure') } == 0 ) {
  exit(0);
}

my $inputdir = $ENV{INPUTDIR};
my $vm_dir   = "$inputdir/data/Azure/vm";

my $azure_metadata = AzureDataWrapperOOP->new( { acl_check => 0 } );

my $menu_tree = AzureMenu::create_folder('Microsoft Azure');
my $locations = gen_locations();

if ( scalar @{$locations} ) {
  my $statuses_page_url = AzureMenu::get_url( { type => 'statuses' } );
  my $statuses_page     = AzureMenu::create_page( 'Statuses', $statuses_page_url );

  my $configuration_page_url = AzureMenu::get_url( { type => 'configuration' } );
  my $configuration_page     = AzureMenu::create_page( 'Configuration', $configuration_page_url );

  my $instance_page_url = AzureMenu::get_url( { type => 'region-aggr' } );
  my $instance_page     = AzureMenu::create_page( 'Instance Overview', $instance_page_url );

  $menu_tree->{children} = [ $statuses_page, $configuration_page, $instance_page ];
  push @{ $menu_tree->{children} }, @{$locations};

  # print menu tree as JSON
  my $json      = JSON->new->utf8->pretty;
  my $json_data = $json->encode($menu_tree);
  print $json_data;
}
exit 0;

sub gen_locations {
  my ( @folders, @location_folders, $loc_folder, $sub_folder ) = ();
  my @locations = @{ $azure_metadata->get_items( { item_type => 'location' } ) };

  #by location
  if ( scalar @locations >= 1 ) {
    $loc_folder = AzureMenu::create_folder('Locations');
  }

  foreach my $location (@locations) {
    my ( $location_id, $location_label ) = each %{$location};
    my ( $vm_folder, $totals_url_vm, %totals_page_vm );

    my @vms = @{ $azure_metadata->get_items( { item_type => 'vm', parent_type => 'location', parent_id => $location_id } ) };
    if ( scalar @vms >= 1 ) {
      $vm_folder      = AzureMenu::create_folder('Virtual Machines');
      $totals_url_vm  = AzureMenu::get_url( { type => 'vm-aggr', location => $location_id } );
      %totals_page_vm = %{ AzureMenu::create_page( 'Virtual Machines Totals', $totals_url_vm ) };

      foreach my $vm (@vms) {
        my ( $vm_uuid, $vm_label ) = each %{$vm};

        my $filepath = $azure_metadata->get_filepath_rrd( { type => 'vm', uuid => $vm_uuid } );
        unless ( -f $filepath ) { next; }

        my $url     = AzureMenu::get_url( { type => 'vm', vm => $vm_uuid } );
        my %vm_page = %{ AzureMenu::create_page( $vm_label, $url ) };
        push @{ $vm_folder->{children} }, \%vm_page;
      }
    }

    my $location_folder = AzureMenu::create_folder($location_label);
    if ( scalar @vms >= 1 ) {
      push @{ $location_folder->{children} }, \%totals_page_vm;
    }
    if ( scalar @vms >= 1 ) {
      push @{ $location_folder->{children} }, $vm_folder;
    }

    push @{ $loc_folder->{children} }, $location_folder;
  }

  if ( scalar @locations >= 1 ) {
    push @folders, $loc_folder;
  }

  #by subscription
  my @subscriptions = @{ $azure_metadata->get_items( { item_type => 'subscription' } ) };

  if ( scalar @subscriptions >= 1 ) {
    $sub_folder = AzureMenu::create_folder('Subscriptions');

    foreach my $subscription (@subscriptions) {
      my ( $subscription_id, $subscription_label ) = each %{$subscription};

      my $subscription_folder = AzureMenu::create_folder($subscription_label);

      my @resources = @{ $azure_metadata->get_items( { item_type => 'resource', parent_type => 'subscription', parent_id => $subscription_id } ) };
      foreach my $resource (@resources) {
        my ( $resource_id, $resource_label ) = each %{$resource};
        my ( $vm_folder, $totals_url_vm, %totals_page_vm, $app_folder );

        my $resource_folder = AzureMenu::create_folder($resource_label);

        my @vms = @{ $azure_metadata->get_items( { item_type => 'vm', parent_type => 'resource', parent_id => $resource_id } ) };
        if ( scalar @vms >= 1 ) {
          $vm_folder      = AzureMenu::create_folder('Virtual Machines');
          $totals_url_vm  = AzureMenu::get_url( { type => 'vm-aggr-res', resource => $resource_id } );
          %totals_page_vm = %{ AzureMenu::create_page( 'Virtual Machines Totals', $totals_url_vm ) };

          foreach my $vm (@vms) {
            my ( $vm_uuid, $vm_label ) = each %{$vm};

            my $url     = AzureMenu::get_url( { type => 'vm', vm => $vm_uuid } );
            my %vm_page = %{ AzureMenu::create_page( $vm_label, $url ) };
            push @{ $vm_folder->{children} }, \%vm_page;
          }

          push @{ $resource_folder->{children} }, \%totals_page_vm;
          push @{ $resource_folder->{children} }, $vm_folder;
        }

        my @apps = @{ $azure_metadata->get_items( { item_type => 'appService', parent_type => 'resource', parent_id => $resource_id } ) };
        if ( scalar @apps >= 1 ) {
          $app_folder = AzureMenu::create_folder('App Services');

          foreach my $app (@apps) {
            my ( $app_uuid, $app_label ) = each %{$app};

            my $url      = AzureMenu::get_url( { type => 'appService', appService => $app_uuid } );
            my %app_page = %{ AzureMenu::create_page( $app_label, $url ) };
            push @{ $app_folder->{children} }, \%app_page;
          }

          push @{ $resource_folder->{children} }, $app_folder;
        }

        if ( defined $resource_folder->{children}[0] ) {
          push @{ $subscription_folder->{children} }, $resource_folder;
        }
      }

      if ( defined $subscription_folder->{children}[0] ) {
        push @{ $sub_folder->{children} }, $subscription_folder;
      }
    }

    if ( defined $sub_folder->{children}[0] ) {
      push @folders, $sub_folder;
    }
  }

  return \@folders;

}
