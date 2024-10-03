use 5.008_008;

use strict;
use warnings;

use JSON;
use Data::Dumper;

use Xorux_lib qw(error read_json);
use Db2Menu;
#use Db2DataWrapper;
use HostCfg;

defined $ENV{INPUTDIR} || warn "INPUTDIR undefined, config etc/lpar2rrd.cfg probably has not been loaded " && exit 1;
my %creds    = %{ HostCfg::getHostConnections("DB2") };
my $inputdir = $ENV{INPUTDIR};
my $bindir   = $ENV{BINDIR};
my $home_dir = "$inputdir/data/DB2";
my $tmp_dir  = "$inputdir/tmp";

if ( !keys %creds ) {
  exit 0;
}
my @menu_items       = ( "IO", "Latency", "Rows", "Session", "Network", "SQL_query", "Waits", "Agents", "Locks", "Ratio" );
my @menu_items_names = ( "IO", "Latency", "Rows", "Session", "Network", "SQL query", "Waits", "Agents", "Locks", "Ratio" );

my $menu_tree   = Db2Menu::create_folder('IBM Db2');
my $hs          = Db2Menu::create_page( "Health status", Db2Menu::get_url( { type => 'healthstatus', id => "not_needed" } ), "Health status" );
#my $topten_page = Db2Menu::create_page( "DB TOP", Db2Menu::get_url( { type => 'topten_db2', id => "not_needed" } ), "DB TOP" );
my @alias;
my %sub_folders;
my %folders;

push( @{ $menu_tree->{children} }, $hs );

for my $_alias ( keys %creds ) {

  my $menu;
  if (defined $creds{$_alias}{menu_subgroup} and $creds{$_alias}{menu_subgroup} ne ""){
    $menu = gen_menu_hostname( "$_alias", "$creds{$_alias}{uuid}","$creds{$_alias}{menu_group} $creds{$_alias}{menu_subgroup}");
    push( @{ $sub_folders{$creds{$_alias}{menu_group}}{$creds{$_alias}{menu_subgroup}} }, $menu);
    $folders{$creds{$_alias}{menu_group}}{_folders2add}{subgroups}{$creds{$_alias}{menu_subgroup}} = 1;
  }elsif((defined $creds{$_alias}{menu_group} and $creds{$_alias}{menu_group} ne "") and (!defined $creds{$_alias}{menu_subgroup} or $creds{$_alias}{menu_subgroup} eq "")){
    $menu = gen_menu_hostname( "$_alias", "$creds{$_alias}{uuid}","$creds{$_alias}{menu_group} $creds{$_alias}{menu_subgroup}" );
    push( @{ $folders{$creds{$_alias}{menu_group}}{alias} }, $menu);
  }else{
    $menu = gen_menu_hostname( "$_alias", "$creds{$_alias}{uuid}","$creds{$_alias}{menu_group} $creds{$_alias}{menu_subgroup}" );
    push(@alias, $menu);
  }
}

for my $main_group (keys %folders){
  my $mf_tree = Db2Menu::create_folder($main_group);
  if(defined $folders{$main_group}{alias}){
    push( @{ $mf_tree->{children} }, @{$folders{$main_group}{alias}} );
  }

  for my $sub_group (keys %{$folders{$main_group}{_folders2add}{subgroups}}){
    my $sf_tree = Db2Menu::create_folder($sub_group);
    push( @{ $sf_tree->{children} }, @{$sub_folders{$main_group}{$sub_group}} ); 
    push( @{ $mf_tree->{children} }, $sf_tree );
  }
  push( @{ $menu_tree->{children} }, $mf_tree );
}
push( @{ $menu_tree->{children} }, @alias );

#print as JSON
Xorux_lib::write_json( "$tmp_dir/menu_db2.json", $menu_tree );
print ":)";

#Xorux_lib::write_json( "$totals_dir/arc.json", \%arc);

exit 0;
################################################################################

sub gen_menu_hostname {
  my $hostname = shift;
  my $uuid     = shift;
  my $path     = shift;
  my $host     = Db2Menu::create_folder($hostname);
  my $dbs      = Db2Menu::create_folder('Members');
  my $bfrp     = Db2Menu::create_folder('Buffer pools');
  $path = defined $path ? $path : " ";

  my $clstr_db;
  my $arc = "$home_dir/$hostname/Configuration/arc.json";
  my ( $can_read, $ref ) = Xorux_lib::read_json($arc);
  if ($can_read) {
    for my $db ( keys %{ $ref->{hostnames}->{$uuid}->{_dbs} } ) {
      $clstr_db = $db;
      push( @{ $dbs->{children} }, gen_menu_db( $db, $ref->{hostnames}->{$uuid}->{_dbs}->{$db}->{label} ));
    }
    for my $pool ( keys %{ $ref->{hostnames}->{$uuid}->{_bps} } ) {
      $clstr_db = $pool;
      my $url  = Db2Menu::get_url( { type => "BUFFERPOOL", id => $pool} );
      my $label = $ref->{hostnames}->{$uuid}->{_bps}->{$pool}->{label};
      my $page = Db2Menu::create_page( $label, $url, "$path $label" );
      push( @{ $bfrp->{children} }, $page);
    }

  }

  my $cnf_cl = Db2Menu::create_page( "Configuration", Db2Menu::get_url( { type => 'configuration_Cluster', id => "$clstr_db" } ), "$path Configuration" );

  my @array;
  for my $i ( 0 .. $#menu_items ) {
    my $url  = Db2Menu::get_url( { type => $menu_items[$i], id => $uuid } );
    my $conf = Db2Menu::create_page( $menu_items_names[$i], $url, "$path $hostname $menu_items_names[$i]" );

    push( @array, $conf );
  }

  push( @{ $host->{children} },$cnf_cl, @array, $dbs, $bfrp );

  return $host;
}

sub gen_menu_db {
  my $id    = shift;
  my $label = shift;
  my $path  = shift;
  $path = defined $path ? $path : " ";

  my $one = Db2Menu::create_folder($label);
  my @array;
  for my $i ( 0 .. $#menu_items ) {
    my $url  = Db2Menu::get_url( { type => $menu_items[$i], id => $id } );
    my $conf = Db2Menu::create_page( $menu_items_names[$i], $url, "$path $label $menu_items_names[$i]" );

    push( @array, $conf );
  }
  push( @{ $one->{children} }, @array );
  return $one;
}

