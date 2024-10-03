# xen-genmenu.pl
# generate menu tree from XenServer RRDs and print it as JSON
# replacement for an older equivalent to `find_active_lpar.pl` that generated `menu.txt`

use 5.008_008;

use strict;
use warnings;

use JSON;
use Data::Dumper;

use Xorux_lib;
use XenServerDataWrapperOOP;
use XenServerMenu;

defined $ENV{INPUTDIR} || warn( localtime() . ': INPUTDIR undefined, config etc/lpar2rrd.cfg probably has not been loaded ' . __FILE__ . ':' . __LINE__ ) && exit 1;

my $inputdir = $ENV{INPUTDIR};
my $host_dir = "$inputdir/data/XEN";
my $vm_dir   = "$inputdir/data/XEN_VMs";

unless ( -d $host_dir || -d $vm_dir ) {
  exit;
}

my $xenserver_metadata = XenServerDataWrapperOOP->new( { acl_check => 0 } );

my $menu_tree = XenServerMenu::create_folder('XenServer');
my $pools     = gen_pools();

if ( scalar @{$pools} ) {
  my $configuration_page_url = XenServerMenu::get_url( { type => 'configuration' } );
  my $configuration_page     = XenServerMenu::create_page( 'Configuration', $configuration_page_url );
  my $heatmap_page_url       = XenServerMenu::get_url( { type => 'heatmap' } );
  my $heatmap_page           = XenServerMenu::create_page( 'Heatmap', $heatmap_page_url );
  my $topten_page_url        = XenServerMenu::get_url( { type => 'topten_xenserver' } );
  my $topten_page            = XenServerMenu::create_page( 'VM TOP', $topten_page_url );

  $menu_tree->{children} = [ $heatmap_page, $configuration_page, $topten_page ];
  push @{ $menu_tree->{children} }, @{$pools};

  # print menu tree as JSON
  my $json      = JSON->new->utf8->pretty;
  my $json_data = $json->encode($menu_tree);
  print $json_data;
}

exit 0;

sub gen_pools {
  my @pool_folders = ();

  my @pools = @{ $xenserver_metadata->get_items( { item_type => 'pool' } ) };
  foreach my $pool (@pools) {
    my %pool_item = %{$pool};
    my ( $pool_uuid, $pool_label ) = each %pool_item;
    my ( @host_entries, $pool_folder, $totals_url );

    # get an array of hosts in the pool
    my @hosts = @{ $xenserver_metadata->get_items( { item_type => 'host', parent_type => 'pool', parent_uuid => $pool_uuid } ) };

    # skip empty pool
    next unless ( scalar @hosts > 0 );

    # keep track of storages in the whole pool
    my $storage_total_count = 0;
    my @storage_pages;

    # get entries for each host in the pool
    foreach my $host (@hosts) {
      my %host_item = %{$host};
      my ( $host_uuid, $host_label ) = each %host_item;
      my ( $filepath, $label, $host_folder, $interface_folder, $url );

      # skip hosts with missing performance data in RRD
      $filepath = $xenserver_metadata->get_filepath_rrd( { type => 'host', uuid => $host_uuid } );
      next unless ( $filepath && -f $filepath );

      # create menu entry
      $host_folder = XenServerMenu::create_folder($host_label);
      $url         = XenServerMenu::get_url( { type => 'host', id => $host_uuid } );
      my %host_page = %{ XenServerMenu::create_page( $host_label, $url ) };
      push @{ $host_folder->{children} }, \%host_page;

      # add storages
      my $storage_config = $xenserver_metadata->get_conf_section('spec-sr');
      my @storages       = @{ $xenserver_metadata->get_items( { item_type => 'storage', parent_type => 'host', parent_uuid => $host_uuid } ) };
      my $storage_count  = scalar @storages;
      $storage_total_count += $storage_count;
      if ( $storage_count > 0 ) {
        my $interface_folder = XenServerMenu::create_folder('Storage');
        $totals_url = XenServerMenu::get_url( { type => 'storage-aggr', id => $host_uuid } );
        my %totals_page = %{ XenServerMenu::create_page( 'Totals', $totals_url ) };
        push @{ $interface_folder->{children} }, \%totals_page;

        my $item_folder = XenServerMenu::create_folder('Items');
        foreach my $item (@storages) {
          my %storage_item = %{$item};
          my ( $storage_uuid, $storage_label ) = each %storage_item;

          # skip certain types (hardware devices, media images)
          if ( exists $storage_config->{$storage_uuid}{type} ) {
            my $storage_type = $storage_config->{$storage_uuid}{type};
            next if ( $storage_type eq 'udev' || $storage_type eq 'iso' );
          }
          my $short_uuid = $xenserver_metadata->shorten_sr_uuid($storage_uuid);
          $label = ( $storage_label ? $storage_label : 'no label' ) . " ${short_uuid}";
          $url   = XenServerMenu::get_url( { type => 'storage', id => $storage_uuid } );
          my %storage_page = %{ XenServerMenu::create_page( $label, $url ) };
          push @{ $item_folder->{children} }, \%storage_page;

          # add the item to the pool-wide list of storages, for 'Storage' folder at pool level
          push @storage_pages, \%storage_page;
        }
        push @{ $interface_folder->{children} }, $item_folder;

        push @{ $host_folder->{children} }, $interface_folder;
      }

      my @networks = @{ $xenserver_metadata->get_items( { item_type => 'network', parent_type => 'host', parent_uuid => $host_uuid } ) };
      if ( scalar @networks > 0 ) {
        my $interface_folder = XenServerMenu::create_folder('LAN');
        $totals_url = XenServerMenu::get_url( { type => 'net-aggr', id => $host_uuid } );
        my %totals_page = %{ XenServerMenu::create_page( 'Totals', $totals_url ) };
        push @{ $interface_folder->{children} }, \%totals_page;

        my $item_folder = XenServerMenu::create_folder('Items');
        foreach my $item (@networks) {
          my %network_item = %{$item};
          my ( $net_uuid, $net_label ) = each %network_item;
          $url = XenServerMenu::get_url( { type => 'net', id => $net_uuid } );
          my %storage_page = %{ XenServerMenu::create_page( $net_label, $url ) };
          push @{ $item_folder->{children} }, \%storage_page;
        }
        push @{ $interface_folder->{children} }, $item_folder;

        push @{ $host_folder->{children} }, $interface_folder;
      }

      push @host_entries, $host_folder;
    }

    # add VMs that reside on hosts in this pool
    my $vms;
    if ( -d $vm_dir ) {
      my @vms = @{ $xenserver_metadata->get_items( { item_type => 'vm', parent_type => 'pool', parent_uuid => $pool_uuid } ) };
      unless ( scalar @vms > 0 ) { last; }

      my @pages;
      my $url;
      foreach my $vm (@vms) {
        my %vm_item = %{$vm};
        my ( $vm_uuid, $vm_label ) = each %vm_item;
        my $filepath = $xenserver_metadata->get_filepath_rrd( { type => 'vm', uuid => $vm_uuid } );
        next unless ( $filepath && -f $filepath );

        $url = XenServerMenu::get_url( { type => 'vm', id => $vm_uuid } );
        my %page = %{ XenServerMenu::create_page( $vm_label, $url ) };
        push @pages, \%page;
      }

      $vms = XenServerMenu::create_folder('VM');
      $vms->{children} = \@pages;
    }

    # add the pool to menu tree
    $pool_folder = XenServerMenu::create_folder($pool_label);
    $totals_url  = XenServerMenu::get_url( { type => 'pool-aggr', id => $pool_uuid } );
    my %totals_page = %{ XenServerMenu::create_page( 'Totals', $totals_url ) };
    unshift @host_entries, \%totals_page;
    $pool_folder->{children} = \@host_entries;
    if ($vms) {
      push @{ $pool_folder->{children} }, $vms;
    }
    push @pool_folders, $pool_folder;
  }

  return \@pool_folders;
}
