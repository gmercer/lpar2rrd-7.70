# SolarisMenu.pm
# page types and associated tools for generating front-end menu and tabs for Solaris

package SolarisMenu;

use strict;
use warnings;

use JSON;
use Data::Dumper;
use Xorux_lib;
use VmwareDataWrapper;
use PowerDataWrapper;
my @page_types = ();

my $basedir = $ENV{INPUTDIR};
my $wrkdir  = $basedir . "/data";

################################################################################

if ( defined $ENV{XORMON} && $ENV{XORMON} ) {
  my $file = "$basedir/etc/links_solaris.json";
  @page_types = @{ Xorux_lib::read_json($file) if ( -e $file ) };

  #require "$basedir/bin/SQLiteDataWrapper.pm";
  require SQLiteDataWrapper;
}

sub create_folder {
  my $title  = shift;
  my %folder = ( "folder" => "true", "title" => $title, children => [] );

  return \%folder;
}

sub create_page {
  my $title = shift;
  my $url   = shift;
  my %page  = ( "title" => $title, "str" => $title, "href" => $url );

  if ( $title eq 'Heatmap' ) {
    $page{extraClasses} = 'boldmenu';
  }

  return \%page;
}

sub get_url {

  # accepts a hash with named parameters: type, and respective url_params
  my ($args) = @_;
  my $url;
  foreach my $page_type (@page_types) {
    $args->{type} = lc( $args->{type} );
    if ( $page_type->{type} eq $args->{type} ) {
      $url =
          $page_type->{url_base} =~ /\.html$/
        ? $page_type->{url_base}
        : "$page_type->{url_base}?platform=$page_type->{platform}&type=$page_type->{type}";

      foreach my $param ( @{ $page_type->{url_params} } ) {
        $url .= "&$param=$args->{$param}";
      }
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
  return ();
}

################################################################################

# expects hash as parameter : { type => "page_type", uid => "abcd1234_uid" }
sub url_new_to_old {
  my $out       = "";
  my $in        = shift;
  my $page_type = "";
  my $uid       = "";
  my $zone_name = "";
  $page_type = $in->{type} if defined $in->{type};
  $uid       = $in->{id}   if defined $in->{id};

  my @uuid_files = <$wrkdir/Solaris/*/uuid.txt>;    #### /
                                                    #print STDERR "@uuid_files\n";
  if ( $page_type =~ /^CDOM$|^LDOM$|ZONE_.$|STANDALONE_ZONE_L10|STANDALONE_ZONE_L11/ ) {
    if ( $page_type =~ /ZONE_.$|STANDALONE_ZONE_L10|STANDALONE_ZONE_L11/ ) {
      ( $uid, $zone_name ) = split( "_", $uid );
    }
    foreach my $uuid_file (@uuid_files) {
      my $uuid_ldom_in_file = "";
      chomp $uuid_file;
      if ( -f "$uuid_file" ) {
        open( FC, "< $uuid_file" ) || error( "cannot read $uuid_file: $!" . __FILE__ . ":" . __LINE__ );
        $uuid_ldom_in_file = <FC>;
        chomp $uuid_ldom_in_file;
        close(FC);
      }
      if ( $uid ne $uuid_ldom_in_file ) { next; }
      if ( $page_type =~ /^LDOM$/ ) {
        my $ldom_name = ( split( "\/", $uuid_file ) )[6];
        return {
          url_base => '',
          params   => {
            host   => $uid,
            server => $ldom_name,
            lpar   => $ldom_name,
            item   => 'sol_ldom_xor'
          }
        };
      }
      elsif ( $page_type =~ /^CDOM$/ ) {
        my $ldom_name = ( split( "\/", $uuid_file ) )[6];
        return {
          url_base => '',
          params   => {
            host   => $uid,
            server => $ldom_name,
            lpar   => $ldom_name,
            item   => 'sol_cdom_xor'
          }
        };
      }
      elsif ( $page_type =~ /^ZONE_C$/ ) {
        my $ldom_name = ( split( "\/", $uuid_file ) )[6];
        my $zone_path = "$wrkdir/Solaris/$ldom_name/ZONE/";
        if ( -d "$zone_path" ) {
          return {
            url_base => '',
            params   => {
              host   => $uid,
              server => $ldom_name,
              lpar   => $zone_name,
              item   => 'sol_zone_c_xor'
            }
          };
        }
      }
      elsif ( $page_type =~ /^ZONE_L$|STANDALONE_ZONE_L11/ ) {
        my $ldom_name = ( split( "\/", $uuid_file ) )[6];
        my $zone_path = "$wrkdir/Solaris/$ldom_name/ZONE/";
        if ( -d "$zone_path" ) {
          return {
            url_base => '',
            params   => {
              host   => $uid,
              server => $ldom_name,
              lpar   => $zone_name,
              item   => 'sol_zone_l_xor11'
            }
          };
        }
      }
      elsif ( $page_type =~ /STANDALONE_ZONE_L10/ ) {
        my $ldom_name = ( split( "\/", $uuid_file ) )[6];
        my $zone_path = "$wrkdir/Solaris/$ldom_name/ZONE/";
        if ( -d "$zone_path" ) {
          return {
            url_base => '',
            params   => {
              host   => $uid,
              server => $ldom_name,
              lpar   => $zone_name,
              item   => 'sol_zone_l_xor10'
            }
          };
        }
      }
    }
  }
  elsif ( $page_type =~ /SOLARIS_TOTAL/ ) {
    return {
      url_base => '',
      params   => {
        host   => 'no_hmc',
        server => 'Solaris',
        lpar   => 'cod',
        item   => 'sol_ldom_agg_c'
      }
    };
  }
  elsif ( $page_type =~ /STANDALONE_LDOM/ ) {
    foreach my $uuid_file (@uuid_files) {
      my $uuid_ldom_in_file = "";
      chomp $uuid_file;
      if ( -f "$uuid_file" ) {
        open( FC, "< $uuid_file" ) || error( "cannot read $uuid_file: $!" . __FILE__ . ":" . __LINE__ );
        $uuid_ldom_in_file = <FC>;
        chomp $uuid_ldom_in_file;
        close(FC);
      }
      if ( $uid ne $uuid_ldom_in_file ) { next; }
      my $ldom_name = ( split( "\/", $uuid_file ) )[6];
      return {
        url_base => '',
        params   => {
          host   => $uid,
          server => $ldom_name,
          lpar   => $ldom_name,
          item   => 'sol_ldom_xor'
        }
      };
    }
  }
}

1;
