use 5.008_008;

use strict;
use warnings;

use JSON;
use Data::Dumper;

use Xorux_lib qw(error read_json);
use SQLServerDataWrapper;
use SQLServerMenu;
use HostCfg;

defined $ENV{INPUTDIR} || warn "INPUTDIR undefined, config etc/lpar2rrd.cfg probably has not been loaded " && exit 1;
my %creds    = %{ HostCfg::getHostConnections("SQLServer") };
my $inputdir = $ENV{INPUTDIR};
my $bindir   = $ENV{BINDIR};
my $home_dir = "$inputdir/data/SQLServer";
my $tmp_dir  = "$inputdir/tmp";

if ( !keys %creds ) {
  exit 0;
}

my $menu_tree   = SQLServerMenu::create_folder('Microsoft SQL Server');
my $hs          = SQLServerMenu::create_page( "Health status", SQLServerMenu::get_url( { type => 'healthstatus', id => "not_needed" } ), "Health status" );
my $topten_page = SQLServerMenu::create_page( "DB TOP", SQLServerMenu::get_url( { type => 'topten_microsql', id => "not_needed" } ), "DB TOP" );

push( @{ $menu_tree->{children} }, $hs );
push( @{ $menu_tree->{children} }, $topten_page );

for my $_alias ( keys %creds ) {
  push( @{ $menu_tree->{children} }, gen_menu_hostname( "$_alias", "$creds{$_alias}{uuid}" ) );
}

#print as JSON
my $json      = JSON->new->utf8->pretty;
my $json_data = $json->encode($menu_tree);
print $json_data;
Xorux_lib::write_json( "$tmp_dir/menu_sqlserver.json", $menu_tree );
print ":)";

#Xorux_lib::write_json( "$totals_dir/arc.json", \%arc);

exit 0;

sub gen_menu_hostname {
  my $hostname = shift;
  my $uuid     = shift;
  my $host     = SQLServerMenu::create_folder($hostname);
  my $dbs      = SQLServerMenu::create_folder('DBs');

  #my $cluster   = SQLServerMenu::create_folder( 'Cluster' );

  my $clstr_db;
  my $arc = "$home_dir/$hostname/Configuration/arc.json";
  my ( $can_read, $ref ) = Xorux_lib::read_json($arc);
  if ($can_read) {
    for my $db ( keys %{ $ref->{hostnames}->{$uuid}->{_dbs} } ) {
      $clstr_db = $uuid;
      push( @{ $dbs->{children} }, gen_menu_db( $db, $ref->{hostnames}->{$uuid}->{_dbs}->{$db}->{label} ) );
    }
  }

  my @menu_items = ( "configuration Cluster", "Memory", "Buffers", "Sessions", "Latches", "Wait events" );

  my @array;
  foreach my $menu_item (@menu_items) {
    my $menu_item_ns = $menu_item;
    $menu_item_ns =~ s/ /_/g;
    my $url   = SQLServerMenu::get_url( { type => $menu_item_ns, id => $clstr_db } );
    my $title = $menu_item;
    $title =~ s/configuration //g;
    if ( $title eq "Cluster" ) {
      $title = "Configuration";
    }
    my $conf = SQLServerMenu::create_page( $title, $url, $title );

    push( @array, $conf );
  }
  push( @{ $host->{children} }, @array, $dbs );

  return $host;
}

sub gen_menu_db {
  my $id    = shift;
  my $label = shift;

  my $one = SQLServerMenu::create_folder($label);

  #"Configuration",
  my @menu_items = ( "configuration Capacity", "IO", "Data", "Latency", "SQL query", "Locks", "Ratio" );

  my @array;
  foreach my $menu_item (@menu_items) {
    my $menu_item_ns = $menu_item;
    $menu_item_ns =~ s/ /_/g;
    my $url   = SQLServerMenu::get_url( { type => $menu_item_ns, id => $id } );
    my $title = $menu_item;
    $title =~ s/configuration //g;
    my $conf = SQLServerMenu::create_page( $title, $url, $title );

    push( @array, $conf );
  }

  push( @{ $one->{children} }, @array );

  return $one;
}
