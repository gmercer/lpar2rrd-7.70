# GCloudDataWrapperJSON.pm
# interface for accessing GCloud data:
# accesses metadata in conf.json
# subroutines defined here should be called only by `GCloudDataWrapper.pm`
# alternative backend will be `GCloudDataWrapperSQLite`

package GCloudDataWrapperJSON;

use strict;
use warnings;

use Data::Dumper;
use JSON;

require GCloudDataWrapper;

defined $ENV{INPUTDIR} || warn( localtime() . ': INPUTDIR undefined, config etc/lpar2rrd.cfg probably has not been loaded ' . __FILE__ . ':' . __LINE__ ) && exit 1;

my $inputdir = $ENV{INPUTDIR};
my $wrkdir   = "$inputdir/data/GCloud";

my $compute_path = "$wrkdir/compute";
my $conf_file    = "$wrkdir/conf.json";
my $agent_file   = "$wrkdir/agent.json";

################################################################################

sub get_items {
  my %params = %{ shift() };
  my @result;

  unless ( defined $params{item_type} ) {
    return;    # return error code
  }

  my $labels  = get_labels();
  my $engines = get_engines();

  if ( $params{item_type} eq 'compute' ) {
    if ( defined $params{parent_type} && defined $params{parent_id} ) {
      if ( $params{parent_type} eq 'region' ) {
        my $region            = $params{parent_id};
        my $regions           = get_conf_section('arch-region');
        my @reported_computes = ( $regions && exists $regions->{$region} ) ? @{ $regions->{$region} } : ();
        foreach my $compute (@reported_computes) {
          my $compute_path = GCloudDataWrapper::get_filepath_rrd_compute($compute);
          if ( defined $compute_path && -f $compute_path ) {
            push @result, { $compute => $labels->{compute}->{$compute} };
          }
        }
      }
    }
    else {
      foreach my $compute_uuid ( keys %{ $labels->{compute} } ) {
        push @result, { $compute_uuid => $labels->{compute}->{$compute_uuid} };
      }
    }
  }
  elsif ( $params{item_type} eq 'database' ) {
    if ( defined $params{parent_type} && defined $params{parent_id} ) {
      if ( $params{parent_type} eq 'region' ) {
        if ( defined $params{engine} ) {
          my $region             = $params{parent_id};
          my $regions            = get_conf_section('arch-database');
          my @reported_databases = ( $regions && exists $regions->{$region} ) ? @{ $regions->{$region} } : ();
          foreach my $database (@reported_databases) {
            if ( !defined $engines->{$database} || $engines->{$database} ne $params{engine} ) {
              next;
            }
            if ( -f GCloudDataWrapper::get_filepath_rrd_database($database) ) {
              push @result, { $database => $labels->{database}->{$database} };
            }
          }
        }
        else {
          my $region             = $params{parent_id};
          my $regions            = get_conf_section('arch-database');
          my @reported_databases = ( $regions && exists $regions->{$region} ) ? @{ $regions->{$region} } : ();
          foreach my $database (@reported_databases) {
            if ( -f GCloudDataWrapper::get_filepath_rrd_database($database) ) {
              push @result, { $database => $labels->{database}->{$database} };
            }
          }
        }
      }
    }

  }
  elsif ( $params{item_type} eq 'region' ) {
    my $regions = get_conf_section('arch-region');
    foreach my $region ( keys %{$regions} ) {
      push @result, { $region => $region };
    }
  }

  return \@result;
}

################################################################################

sub get_conf {
  my %dictionary = ();
  {
    my $content;
    local $/;
    if ( open( my $fh, '<', "$conf_file" ) ) {
      $content = <$fh>;
      close($fh);
      %dictionary = %{ decode_json($content) };
    }
  }
  return \%dictionary;
}

sub get_agent {
  my %dictionary = ();
  {
    my $content;
    local $/;
    if ( open( my $fh, '<', "$agent_file" ) ) {
      $content = <$fh>;
      close($fh);
      %dictionary = %{ decode_json($content) };
    }
  }
  return \%dictionary;
}

sub get_conf_section {
  my $section = shift;

  my $dictionary = get_conf();
  my $agent      = get_agent();

  if ( $section eq 'labels' ) {
    return $dictionary->{label};
  }
  elsif ( $section eq 'arch' ) {
    return $dictionary->{architecture};
  }
  elsif ( $section eq 'engines' ) {
    return $dictionary->{engines};
  }
  elsif ( $section eq 'arch-region' ) {
    return $dictionary->{architecture}{region_compute};
  }
  elsif ( $section eq 'arch-database' ) {
    return $dictionary->{architecture}{region_database};
  }
  elsif ( $section eq 'spec-compute' ) {
    return $dictionary->{specification}{compute};
  }
  elsif ( $section eq 'spec-database' ) {
    return $dictionary->{specification}{database};
  }
  elsif ( $section eq 'spec-region' ) {
    return $dictionary->{specification}{region};
  }
  elsif ( $section eq 'spec-agent' ) {
    return $agent;
  }
  else {
    return ();
  }

}

sub get_labels {
  return get_conf_section('labels');
}

sub get_engines {
  return get_conf_section('engines');
}

sub get_engine {
  my $uuid    = shift;
  my $engines = get_engines();

  return exists $engines->{$uuid} ? $engines->{$uuid} : ();
}

sub get_label {
  my $type   = shift;
  my $uuid   = shift;
  my $labels = get_labels();

  if ( $type eq 'network' ) {
    my $device = get_network_device($uuid);
    return $device ? $device : $uuid;
  }

  return exists $labels->{$type}{$uuid} ? $labels->{$type}{$uuid} : $uuid;
}

sub get_conf_update_time {
  return ( stat($conf_file) )[9];
}

################################################################################

1;
