# DockerDataWrapperJSON.pm
# interface for accessing Docker data:

package DockerDataWrapperJSON;

use strict;
use warnings;

use Data::Dumper;
use JSON;

require Docker;

defined $ENV{INPUTDIR} || warn( localtime() . ': INPUTDIR undefined, config etc/lpar2rrd.cfg probably has not been loaded ' . __FILE__ . ':' . __LINE__ ) && exit 1;

my $inputdir = $ENV{INPUTDIR};
my $wrkdir   = "$inputdir/data/Docker";

my $container_dir     = "$wrkdir/Container";
my $volume_dir        = "$wrkdir/Volume";
my $label_file        = "$wrkdir/labels.json";
my $architecture_file = "$wrkdir/architecture.json";

################################################################################

sub get_items {
  my %params = %{ shift() };
  my @result;

  unless ( defined $params{item_type} ) {
    return;    # return error code
  }

  my $labels = get_labels();

  if ( $params{item_type} eq 'container' ) {
    if ( defined $params{parent_type} && defined $params{parent_id} ) {
      if ( $params{parent_type} eq 'host' ) {
        my $host                = $params{parent_id};
        my $hosts               = get_conf_section('arch-host-container');
        my @reported_containers = ( $hosts && exists $hosts->{$host} ) ? @{ $hosts->{$host} } : ();
        foreach my $container (@reported_containers) {
          if ( !defined $labels->{container}->{$container} ) {
            Docker::deleteArchitecture( 'container', $container );
            next;
          }
          push @result, { $container => $labels->{container}->{$container} };
        }
      }
    }
    else {
      foreach my $container ( keys %{ $labels->{container} } ) {
        push @result, { $container => $labels->{container}->{$container} };
      }
    }
  }
  elsif ( $params{item_type} eq 'volume' ) {
    if ( defined $params{parent_type} && defined $params{parent_id} ) {
      if ( $params{parent_type} eq 'host' ) {
        my $host             = $params{parent_id};
        my $hosts            = get_conf_section('arch-host-volume');
        my @reported_volumes = ( $hosts && exists $hosts->{$host} ) ? @{ $hosts->{$host} } : ();
        foreach my $volume (@reported_volumes) {
          if ( !defined $labels->{volume}->{$volume} ) {
            Docker::deleteArchitecture( 'volume', $volume );
            next;
          }
          push @result, { $volume => $labels->{volume}->{$volume} };
        }
      }
    }
    else {
      foreach my $volume ( keys %{ $labels->{volume} } ) {
        push @result, { $volume => $labels->{volume}->{$volume} };
      }
    }
  }
  elsif ( $params{item_type} eq 'host' ) {
    my $hosts = get_conf_section('arch-host-container');
    foreach my $host ( keys %{$hosts} ) {
      push @result, { $host => $labels->{host}->{$host} };
    }
  }

  return \@result;
}

################################################################################

sub get_conf_label {
  my %dictionary = ();
  {
    my $content;
    local $/;
    if ( open( my $fh, '<', "$label_file" ) ) {
      $content = <$fh>;
      close($fh);
      %dictionary = %{ decode_json($content) };
    }
  }
  return \%dictionary;
}

sub get_conf_architecture {
  my %dictionary = ();
  {
    my $content;
    local $/;
    if ( open( my $fh, '<', "$architecture_file" ) ) {
      $content = <$fh>;
      close($fh);
      %dictionary = %{ decode_json($content) };
    }
  }
  return \%dictionary;
}

sub get_conf_section {
  my $section = shift;

  my $dictionary;
  if ( $section eq 'labels' ) {
    $dictionary = get_conf_label();
  }
  elsif ( $section =~ m/arch/ ) {
    $dictionary = get_conf_architecture();
  }
  else {
    return ();
  }

  if ( $section eq 'labels' ) {
    return $dictionary;
  }
  elsif ( $section eq 'arch' ) {
    return $dictionary;
  }
  elsif ( $section eq 'arch-host-container' ) {
    return $dictionary->{host_container};
  }
  elsif ( $section eq 'arch-host-volume' ) {
    return $dictionary->{host_volume};
  }
  else {
    return ();
  }

}

sub get_labels {
  return get_conf_section('labels');
}

sub get_label {
  my $type   = shift;
  my $uuid   = shift;
  my $labels = get_labels();

  return exists $labels->{$type}{$uuid} ? $labels->{$type}{$uuid} : $uuid;
}

################################################################################

1;
