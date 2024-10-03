# AWSDataWrapperJSON.pm
# interface for accessing AWS data:
# accesses metadata in conf.json
# subroutines defined here should be called only by `AWSDataWrapper.pm`
# alternative backend will be `AWSDataWrapperSQLite`

package AWSDataWrapperJSON;

use strict;
use warnings;

use Data::Dumper;
use JSON;

defined $ENV{INPUTDIR} || warn( localtime() . ': INPUTDIR undefined, config etc/lpar2rrd.cfg probably has not been loaded ' . __FILE__ . ':' . __LINE__ ) && exit 1;

my $inputdir = $ENV{INPUTDIR};
my $wrkdir   = "$inputdir/data/AWS";

my $ec2_path  = "$wrkdir/EC2";
my $conf_file = "$wrkdir/conf.json";

################################################################################

sub get_items {
  my %params = %{ shift() };
  my @result;

  unless ( defined $params{item_type} ) {
    return;    # return error code
  }

  my $labels = get_labels();

  if ( $params{item_type} eq 'ec2' ) {
    if ( defined $params{parent_type} && defined $params{parent_id} ) {
      if ( $params{parent_type} eq 'region' ) {
        my $region        = $params{parent_id};
        my $regions       = get_conf_section('arch-region');
        my @reported_ec2s = ( $regions && exists $regions->{$region} ) ? @{ $regions->{$region} } : ();
        foreach my $ec2 (@reported_ec2s) {
          push @result, { $ec2 => $labels->{ec2}->{$ec2} };
        }
      }
    }
    else {
      foreach my $ec2_uuid ( keys %{ $labels->{ec2} } ) {
        push @result, { $ec2_uuid => $labels->{ec2}->{$ec2_uuid} };
      }
    }
  }
  elsif ( $params{item_type} eq 'volume' ) {
    if ( defined $params{parent_type} && defined $params{parent_id} ) {
      if ( $params{parent_type} eq 'region' ) {
        my $region           = $params{parent_id};
        my $regions          = get_conf_section('arch-region-volume');
        my @reported_volumes = ( $regions && exists $regions->{$region} ) ? @{ $regions->{$region} } : ();
        foreach my $volume (@reported_volumes) {
          push @result, { $volume => $labels->{volume}->{$volume} };
        }
      }
    }
  }
  elsif ( $params{item_type} eq 'rds' ) {
    if ( defined $params{parent_type} && defined $params{parent_id} ) {
      if ( $params{parent_type} eq 'region' ) {
        my $region       = $params{parent_id};
        my $regions      = get_conf_section('arch-region-rds');
        my @reported_rds = ( $regions && exists $regions->{$region} ) ? @{ $regions->{$region} } : ();
        foreach my $rds (@reported_rds) {
          push @result, { $rds => $labels->{rds}->{$rds} };
        }
      }
    }
  }
  elsif ( $params{item_type} eq 'api' ) {
    if ( defined $params{parent_type} && defined $params{parent_id} ) {
      if ( $params{parent_type} eq 'region' ) {
        my $region       = $params{parent_id};
        my $regions      = get_conf_section('arch-region-api');
        my @reported_api = ( $regions && exists $regions->{$region} ) ? @{ $regions->{$region} } : ();
        foreach my $api (@reported_api) {
          push @result, { $api => $labels->{api}->{$api} };
        }
      }
    }
  }
  elsif ( $params{item_type} eq 'lambda' ) {
    if ( defined $params{parent_type} && defined $params{parent_id} ) {
      if ( $params{parent_type} eq 'region' ) {
        my $region          = $params{parent_id};
        my $regions         = get_conf_section('arch-region-lambda');
        my @reported_lambda = ( $regions && exists $regions->{$region} ) ? @{ $regions->{$region} } : ();
        foreach my $lambda (@reported_lambda) {
          push @result, { $lambda => $labels->{lambda}->{$lambda} };
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

sub get_conf_section {
  my $section = shift;

  my $dictionary = get_conf();

  if ( $section eq 'labels' ) {
    return $dictionary->{label};
  }
  elsif ( $section eq 'arch' ) {
    return $dictionary->{architecture};
  }
  elsif ( $section eq 'arch-region' ) {
    return $dictionary->{architecture}{region_ec2};
  }
  elsif ( $section eq 'arch-region-rds' ) {
    return $dictionary->{architecture}{region_rds};
  }
  elsif ( $section eq 'arch-region-volume' ) {
    return $dictionary->{architecture}{region_volume};
  }
  elsif ( $section eq 'arch-region-api' ) {
    return $dictionary->{architecture}{region_api};
  }
  elsif ( $section eq 'arch-region-lambda' ) {
    return $dictionary->{architecture}{region_lambda};
  }
  elsif ( $section eq 'spec-ec2' ) {
    return $dictionary->{specification}{ec2};
  }
  elsif ( $section eq 'spec-volume' ) {
    return $dictionary->{specification}{volume};
  }
  elsif ( $section eq 'spec-rds' ) {
    return $dictionary->{specification}{rds};
  }
  elsif ( $section eq 'spec-api' ) {
    return $dictionary->{specification}{api};
  }
  elsif ( $section eq 'spec-lambda' ) {
    return $dictionary->{specification}{lambda};
  }
  elsif ( $section eq 'spec-region' ) {
    return $dictionary->{specification}{region};
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
