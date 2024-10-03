# oVirtMenu.pm
# page types and associated tools for generating front-end menu and tabs for OVirtServer

package OVirtMenu;

use strict;
use warnings;

use JSON;
use Data::Dumper;

sub create_folder {
  my $title  = shift;
  my $str    = shift;
  my %folder = ( folder => 'true', title => $title, children => [] );

  $folder{str} = $str if defined $str;

  return \%folder;
}

sub create_page {
  my $title = shift;
  my $url   = shift;
  my $str   = shift;
  my $agent = shift;

  my %page = ( title => $title, str => defined $str ? $str : $title, href => $url );

  if ( $title eq 'Heatmap' ) {
    $page{extraClasses} = 'boldmenu';
  }

  if ( defined $agent ) {
    $page{agent} = $agent;
  }

  return \%page;
}

sub get_url {

  # accepts a hash with named parameters: type, and respective url_params
  my $params = shift;

  use Menu;
  my $menu = Menu->new('ovirt');

  my $id = '';
  if ( exists $params->{id} ) {
    $id = $params->{id};
  }
  else {
    foreach my $param ( keys %{$params} ) {
      if ( $param =~ /(cluster|storage_domain|host|vm|disk|nic$)/ ) {
        $id = $params->{$param};
        last;
      }
    }
  }

  my $url;
  if ($id) {
    $url = $menu->page_url( $params->{type}, $id );
  }
  else {
    $url = $menu->page_url( $params->{type} );
  }

  return $url;
}

sub get_tabs {
  my $type = shift;
  my $result;

  use Menu;
  my $menu = Menu->new('ovirt');
  $result = $menu->tabs($type);

  return $result;
}

################################################################################

1;
