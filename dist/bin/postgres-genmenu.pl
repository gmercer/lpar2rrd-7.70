use 5.008_008;

use strict;
use warnings;

use JSON;
use Data::Dumper;

use Xorux_lib qw(error read_json);
use PostgresDataWrapper;
use PostgresMenu;
use HostCfg;

defined $ENV{INPUTDIR} || warn "INPUTDIR undefined, config etc/lpar2rrd.cfg probably has not been loaded " && exit 1;
my %creds    = %{ HostCfg::getHostConnections("PostgreSQL") };
my $inputdir = $ENV{INPUTDIR};
my $bindir   = $ENV{BINDIR};
my $home_dir = "$inputdir/data/PostgreSQL";
my $tmp_dir  = "$inputdir/tmp";

if ( !keys %creds ) {
  exit 0;
}

my $menu_tree   = PostgresMenu::create_folder('PostgreSQL');
my $hs          = PostgresMenu::create_page( "Health status", PostgresMenu::get_url( { type => 'healthstatus', id => "not_needed" } ), "Health status" );
my $topten_page = PostgresMenu::create_page( "DB TOP", PostgresMenu::get_url( { type => 'topten_postgres', id => "not_needed" } ), "DB TOP" );

push( @{ $menu_tree->{children} }, $hs );
push( @{ $menu_tree->{children} }, $topten_page );

for my $_alias ( keys %creds ) {
  push( @{ $menu_tree->{children} }, gen_menu_hostname( "$_alias", "$creds{$_alias}{uuid}" ) );
}

#print as JSON
Xorux_lib::write_json( "$tmp_dir/menu_postgres.json", $menu_tree );
print ":)";

#Xorux_lib::write_json( "$totals_dir/arc.json", \%arc);

exit 0;
################################################################################

sub gen_menu_hostname {
  my $hostname = shift;
  my $uuid     = shift;
  my $host     = PostgresMenu::create_folder($hostname);
  my $dbs      = PostgresMenu::create_folder('DBs');

  #my $cluster   = PostgresMenu::create_folder( 'Cluster' );

  my $clstr_db;
  my $arc = "$home_dir/$hostname/Configuration/arc.json";
  my ( $can_read, $ref ) = Xorux_lib::read_json($arc);
  if ($can_read) {
    for my $db ( keys %{ $ref->{hostnames}->{$uuid}->{_dbs} } ) {
      $clstr_db = $db;
      push( @{ $dbs->{children} }, gen_menu_db( $db, $ref->{hostnames}->{$uuid}->{_dbs}->{$db}->{label} ) );
    }
  }

  my $cnf_cl = PostgresMenu::create_page( "Configuration", PostgresMenu::get_url( { type => 'configuration_Cluster', id => "$clstr_db" } ), "Configuration" );
  my $bffrs  = PostgresMenu::create_page( "BG writer",     PostgresMenu::get_url( { type => 'Buffers',               id => "$clstr_db" } ), "Buffers" );

  push( @{ $host->{children} }, $cnf_cl, $bffrs, $dbs );
  return $host;
}

sub gen_menu_db {
  my $id    = shift;
  my $label = shift;
  if ( $label eq "shrdrltn" ) {
    $label = "Shared instance";
  }
  my $one = PostgresMenu::create_folder($label);
  my @array;
  my @menu_items       = ( "configuration", "Throughput", "Sessions", "Locks", "SQL_query", "Wait_event",  "Ratio" );
  my @menu_items_names = ( "Size",          "Throughput", "Sessions", "Locks", "SQL query", "Wait events", "Ratio" );
  for my $i ( 0 .. $#menu_items ) {
    my $url  = PostgresMenu::get_url( { type => $menu_items[$i], id => $id } );
    my $conf = PostgresMenu::create_page( $menu_items_names[$i], $url, $menu_items_names[$i] );

    push( @array, $conf );
  }
  push( @{ $one->{children} }, @array );
  return $one;
}
