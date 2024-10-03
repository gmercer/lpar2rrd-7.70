# AzureDataWrapperJSON.pm
# interface for accessing Azure data:
# accesses metadata in conf.json
# subroutines defined here should be called only by `AzureDataWrapper.pm`
# alternative backend will be `AzureDataWrapperSQLite`

package AzureDataWrapperJSON;

use strict;
use warnings;

use Data::Dumper;
use JSON;

defined $ENV{INPUTDIR} || warn( localtime() . ': INPUTDIR undefined, config etc/lpar2rrd.cfg probably has not been loaded ' . __FILE__ . ':' . __LINE__ ) && exit 1;

my $inputdir = $ENV{INPUTDIR};
my $wrkdir   = "$inputdir/data/Azure";

my $compute_path       = "$wrkdir/vm";
my $dabase_path        = "$wrkdir/database";
my $dabase_server_path = "$wrkdir/database/server";
my $conf_file          = "$wrkdir/conf.json";

################################################################################

sub get_items {
  my %params = %{ shift() };
  my @result;

  unless ( defined $params{item_type} ) {
    return;    # return error code
  }

  my $labels = get_labels();

  if ( $params{item_type} eq 'vm' ) {
    if ( defined $params{parent_type} && defined $params{parent_id} ) {
      if ( $params{parent_type} eq 'location' ) {
        my $location     = $params{parent_id};
        my $locations    = get_conf_section('arch-location');
        my @reported_vms = ( $locations && exists $locations->{$location} ) ? @{ $locations->{$location} } : ();
        foreach my $vm (@reported_vms) {
          push @result, { $vm => $labels->{vm}->{$vm} };
        }
      }
      elsif ( $params{parent_type} eq 'resource' ) {
        my $resource     = $params{parent_id};
        my $resources    = get_conf_section('arch-resource');
        my @reported_vms = ( $resources && exists $resources->{$resource} ) ? @{ $resources->{$resource} } : ();
        foreach my $vm (@reported_vms) {
          push @result, { $vm => $labels->{vm}->{$vm} };
        }
      }
    }
    else {
      foreach my $vm_uuid ( keys %{ $labels->{vm} } ) {
        push @result, { $vm_uuid => $labels->{vm}->{$vm_uuid} };
      }
    }
  }
  elsif ( $params{item_type} eq 'appService' ) {
    if ( defined $params{parent_type} && defined $params{parent_id} ) {
      if ( $params{parent_type} eq 'resource' ) {
        my $resource      = $params{parent_id};
        my $resources     = get_conf_section('arch-resource-app');
        my @reported_apps = ( $resources && exists $resources->{$resource} ) ? @{ $resources->{$resource} } : ();
        foreach my $app (@reported_apps) {
          push @result, { $app => $labels->{appService}->{$app} };
        }
      }
    }
  }
  elsif ( $params{item_type} eq 'location' ) {
    my $locations = get_conf_section('arch-location');
    foreach my $location ( keys %{$locations} ) {
      push @result, { $location => $location };
    }
  }
  elsif ( $params{item_type} eq 'resource' ) {
    if ( defined $params{parent_type} && defined $params{parent_id} ) {
      if ( $params{parent_type} eq 'subscription' ) {
        my $subscription       = $params{parent_id};
        my $subscriptions      = get_conf_section('arch-subscription');
        my @reported_resources = ( $subscriptions && exists $subscriptions->{$subscription} ) ? @{ $subscriptions->{$subscription} } : ();
        foreach my $resource (@reported_resources) {
          push @result, { $resource => $resource };
        }
      }
    }
  }
  elsif ( $params{item_type} eq 'subscription' ) {
    my $subscriptions = get_conf_section('arch-subscription');
    foreach my $subscription ( keys %{$subscriptions} ) {
      push @result, { $subscription => $labels->{subscription}->{$subscription} };
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
  elsif ( $section eq 'statuses' ) {
    return $dictionary->{statuses};
  }
  elsif ( $section eq 'arch-location' ) {
    return $dictionary->{architecture}{location_vm};
  }
  elsif ( $section eq 'arch-resource' ) {
    return $dictionary->{architecture}{resource_vm};
  }
  elsif ( $section eq 'arch-resource-app' ) {
    return $dictionary->{architecture}{resource_appService};
  }
  elsif ( $section eq 'arch-subscription' ) {
    return $dictionary->{architecture}{subscription_resource};
  }
  elsif ( $section eq 'arch-databaseServer' ) {
    return $dictionary->{architecture}{location_databaseServer};
  }
  elsif ( $section eq 'arch-database' ) {
    return $dictionary->{architecture}{databaseServer_database};
  }
  elsif ( $section eq 'spec-vm' ) {
    return $dictionary->{specification}{vm};
  }
  elsif ( $section eq 'spec-database' ) {
    return $dictionary->{specification}{database};
  }
  elsif ( $section eq 'spec-databaseServer' ) {
    return $dictionary->{specification}{databaseServer};
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
