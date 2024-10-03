# Menu.pm
# page types and associated tools for generating front-end menu and tabs
# derived from XenServerMenu.pm
#
# page types are specified in etc/links_$hwtype.json files

package Menu;

use strict;

use JSON;
use Data::Dumper;
use Xorux_lib qw(error read_json write_json);

defined $ENV{INPUTDIR} || warn( localtime() . ': INPUTDIR undefined, config etc/lpar2rrd.cfg probably has not been loaded ' . __FILE__ . ':' . __LINE__ ) && exit 1;

my $inputdir = $ENV{INPUTDIR};

# VERSION variable

sub new {
  my $class      = shift;
  my $platform   = shift;
  my $filepath   = "$inputdir/etc/links_$platform.json";
  my $page_types = Xorux_lib::read_json($filepath);
  my $self       = { dict => $page_types };
  bless $self, $class;
  return $self;
}

sub dict {
  my $self = shift;
  return $self->{dict};
}

sub page_types {
  my $self       = shift;
  my @page_types = ();
  foreach my $type ( @{ $self->{dict} } ) {
    push @page_types, $type->{type};
  }
  return \@page_types;
}

sub page_type_subsys {
  my $self      = shift;
  my $page_type = shift;
  my $subsys    = '';

  foreach my $type ( @{ $self->{dict} } ) {
    if ( $page_type eq $type->{type} ) {
      $subsys = $type->{subsystem};
    }
  }

  return $subsys;
}

sub is_page_type_singleton {
  my $self      = shift;
  my $page_type = shift;

  foreach my $type ( @{ $self->{dict} } ) {
    if ( $page_type eq $type->{type} ) {
      if ( $type->{singleton} ) {
        return 1;
      }
    }
  }

  return 0;
}

sub is_page_type_folder_frontpage {
  my $self      = shift;
  my $page_type = shift;
  foreach my $type ( @{ $self->{dict} } ) {
    if ( $page_type eq $type->{type} ) {
      if ( exists $type->{folder_frontpage} && $type->{folder_frontpage} ) {
        return 1;
      }
    }
  }
  return 0;
}

sub is_page_type_acl_capable {
  my $self      = shift;
  my $page_type = shift;
  foreach my $type ( @{ $self->{dict} } ) {
    if ( $page_type eq $type->{type} ) {
      if ( exists $type->{acl_capable} && $type->{acl_capable} ) {
        return 1;
      }
    }
  }
  return 0;
}

sub subsys_totals_page_types {
  my $self       = shift;
  my $subsys     = shift;
  my @page_types = ();
  foreach my $type ( @{ $self->{dict} } ) {
    if ( $subsys eq $type->{subsystem} || ( ref $type->{subsystem} eq 'ARRAY' && grep( /^$subsys$/, @{ $type->{subsystem} } ) ) ) {
      if ( $type->{singleton} ) {
        push @page_types, $type->{type};
      }
    }
  }
  return \@page_types;
}

sub subsys_items_page_type {
  my $self      = shift;
  my $subsys    = shift;
  my $page_type = '';
  foreach my $type ( @{ $self->{dict} } ) {
    if ( $subsys eq $type->{subsystem} || ( ref $type->{subsystem} eq 'ARRAY' && grep( /^$subsys$/, @{ $type->{subsystem} } ) ) ) {
      if ( !$type->{singleton} ) {
        $page_type = $type->{type};
      }
    }
  }
  return $page_type;
}

sub page_title {
  my $self  = shift;
  my $type  = shift;
  my $title = '';
  foreach my $page_type ( @{ $self->{dict} } ) {
    if ( $page_type->{type} eq $type ) {
      if ( exists $page_type->{title} ) {
        $title = $page_type->{title};
      }
      last;
    }
  }
  return $title;
}

sub page_url {
  my $self = shift;
  my $type = shift;
  my $uuid = shift;
  my $url  = '';
  foreach my $page_type ( @{ $self->{dict} } ) {
    if ( $page_type->{type} eq $type ) {
      $url =
          $page_type->{url_base} =~ /\.html$/
        ? $page_type->{url_base}
        : "$page_type->{url_base}?platform=$page_type->{platform}&type=$page_type->{type}";

      # simplification that replaces the params array
      # formerly: foreach my $param (@{ $page_type->{url_params} }) { $url .= "&$param=$args->{$param}"; }
      if ( defined $uuid && $page_type->{uuid_in_url} ) {
        $url .= "&id=$uuid";
      }

      last;
    }
  }
  return $url;
}

sub tabs {
  my $self = shift;
  my $type = shift;
  my $tabs = ();
  foreach my $page_type ( @{ $self->{dict} } ) {
    if ( $page_type->{type} eq $type ) {
      $tabs = $page_type->{tabs};
    }
  }
  return $tabs;
}

################################################################################

1;
