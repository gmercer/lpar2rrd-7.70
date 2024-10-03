package Db2Menu;

use strict;

use JSON;
use Data::Dumper;
use Xorux_lib qw(error read_json);
use Menu;
use Digest::MD5 qw(md5 md5_hex md5_base64);

my $menu = Menu->new('db2');

my @page_types = @{ Menu::dict($menu) };

sub create_folder {
  my $title = shift;
  my $str   = shift;

  #my $extra  = shift;
  my %folder = ( "folder" => "true", "title" => $title, children => [] );

  #if(!$extra){
  $folder{str} = $str if defined $str;

  #}
  #$folder{href} = $extra if defined $extra;
  return \%folder;
}

sub create_page {
  my $title = shift;
  my $url   = shift;
  my $str   = shift;
  my $agent = shift;

  my $last = substr $url, -6;
  my $hash = substr( md5_hex("db2-$title-$last"), 0, 7 );

  my %page = ( "title" => $title, "str" => defined $str ? $str : $title, "href" => $url, hash => $hash );

  if ( $title eq 'Heatmap' ) {
    $page{extraClasses} = 'boldmenu';
  }

  if ( $title eq 'Overview' ) {
    $page{extraClasses} = 'noregroup jumphere';
  }

  if ( defined $agent ) {
    $page{agent} = $agent;
  }

  return \%page;
}

sub get_url {

  # accepts a hash with named parameters: type, and respective url_params
  my ($args) = @_;
  my $url = "";

  foreach my $page_type (@page_types) {
    my $server = exists $args->{server} ? $args->{server} : "not_spec";
    my $host   = exists $args->{host}   ? $args->{host}   : "not_spec";
    my $id     = exists $args->{id}     ? $args->{id}     : "";
    my $url_id = "";
    $url_id = "&id=$args->{id}";
    if ( $page_type->{type} eq $args->{type} ) {
      $url =
          $page_type->{url_base} =~ /\.html$/
        ? $page_type->{url_base}
        : "$page_type->{url_base}?platform=$page_type->{platform}&type=$page_type->{type}$url_id";
      last;
    }
  }

  return $url;
}

sub get_tabs {
  my $type = shift;

  for my $page_type (@page_types) {
    if ( $page_type->{type} eq $type ) {
      return $page_type->{tabs};
    }
  }
}

sub print_menu {

  #  my $json = JSON->new->utf8->pretty;
  #  return $json->encode( \@page_types );
  return \@page_types;
}

1
