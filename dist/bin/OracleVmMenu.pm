# OracleVmMenu.pm
# page types and associated tools for generating front-end menu and tabs for OracleVM

package OracleVmMenu;

use strict;

use JSON;
use Data::Dumper;
use Xorux_lib qw(error read_json);
use Menu;

my $basedir          = $ENV{INPUTDIR};
my $wrkdir           = $basedir . "/data";
my $agents_uuid_file = "$wrkdir/Linux--unknown/no_hmc/linux_uuid_name.json";

####################################

sub create_folder {
  my $title  = shift;
  my $str    = shift;
  my %folder = ( "folder" => "true", "title" => $title, children => [] );

  $folder{str} = $str if defined $str;

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

  #print Dumper $params;
  use Menu;
  my $menu = Menu->new('oraclevm');

  my $id = '';
  foreach my $param ( keys %{$params} ) {
    if ( $param =~ /(server|serverpool|vm|VM)/ ) {
      $id = $params->{$param};
      last;
    }
  }

  # when LINUX vms running under OracleVM
  my $param_os = "";
  foreach my $param ( keys %{$params} ) {
    if ( $param =~ /(vm)/ ) {
      my ( $code1, $linux_uuids ) = -f $agents_uuid_file ? Xorux_lib::read_json($agents_uuid_file) : ( 0, undef );
      for my $linux_uuid ( keys %{$linux_uuids} ) {
        chomp $linux_uuid;
        my $lpar_agent_name = $linux_uuids->{$linux_uuid};
        $linux_uuid =~ s/-//g;
        $linux_uuid = lc $linux_uuid;
        if ( $id =~ /$linux_uuid/ ) {
          $param_os = "pattern";

          #print "OracleVM:$id,Linux:$linux_uuid\n";
        }
      }
    }
  }
  my $url;
  if ($id) {
    if ( $param_os eq "pattern" ) {    # Linux exist under OracleVM
      $url = $menu->page_url( "vm", $id );
    }
    else {
      $url = $menu->page_url( $params->{type}, $id );
    }
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
  my $menu = Menu->new('oraclevm');
  $result = $menu->tabs($type);

  return $result;
}

sub url_new_to_old {
  my $out       = "";
  my $in        = shift;
  my $page_type = "";
  my $uid       = "";
  $page_type = $in->{type} if defined $in->{type};
  $uid       = $in->{id}   if defined $in->{id};

  #print STDERR"LINE93=out-$out,in-$in,page_type-$page_type,uid-$uid\n";
}

1;
