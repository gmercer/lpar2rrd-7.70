# NutanixMenu.pm
#   Nutanix-specific wrapper for Menu.pm (WIP)

package NutanixMenu;

use strict;
use warnings;

use JSON;
use Data::Dumper;
use Digest::MD5 qw(md5_hex);

sub create_folder {
  my $title  = shift;
  my %folder = ( folder => 'true', title => $title, children => [] );

  return \%folder;
}

sub create_page {
  my $title = shift;
  my $url   = shift;

  my $hash = substr( md5_hex($title), 0, 7 );

  my %page = ( title => $title, str => $title, href => $url, hash => $hash );

  if ( $title eq 'Heatmap' ) {
    $page{extraClasses} = 'boldmenu';
  }

  return \%page;
}

sub get_url {

  # accepts a hash with named parameters: type, and respective url_params
  my $params = shift;

  use Menu;
  my $menu = Menu->new('nutanix');

  my $id = '';
  foreach my $param ( keys %{$params} ) {
    if ( $param =~ /(pool|vm|storage|net|sc|sp|vg|vd|health|health-central)/ ) {
      $id = $params->{$param};
      last;
    }
    elsif ( $param =~ /host/ && !exists $params->{storage} && !exists $params->{net} && !exists $params->{health} && !exists $params->{sc} && !exists $params->{sp} && !exists $params->{vg} && !exists $params->{vd} ) {
      $id = $params->{$param};
      last;
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
  my $menu = Menu->new('nutanix');
  $result = $menu->tabs($type);

  return $result;
}

################################################################################

1;

