# XenServerMenu.pm
#   XenServer-specific wrapper for Menu.pm (WIP)

package XenServerMenu;

use strict;
use warnings;

use JSON;
use Data::Dumper;

sub create_folder {
  my $title  = shift;
  my %folder = ( folder => 'true', title => $title, children => [] );

  return \%folder;
}

sub create_page {
  my $title = shift;
  my $url   = shift;
  my %page  = ( title => $title, str => $title, href => $url );

  if ( $title eq 'Heatmap' ) {
    $page{extraClasses} = 'boldmenu';
  }

  return \%page;
}

sub get_url {

  # accepts a hash with named parameters: type, and respective url_params
  my $params = shift;

  use Menu;
  my $menu = Menu->new('xenserver');

  my $id = '';
  if ( exists $params->{id} ) {
    $id = $params->{id};
  }
  else {
    foreach my $param ( keys %{$params} ) {
      if ( $param =~ /(pool|vm|storage|net)/ ) {
        $id = $params->{$param};
        last;
      }
      elsif ( $param =~ /host/ && !exists $params->{storage} && !exists $params->{net} ) {
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
  my $menu = Menu->new('xenserver');
  $result = $menu->tabs($type);

  return $result;
}

################################################################################

1;
