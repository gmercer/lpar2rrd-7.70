# AzureDataWrapperOOP.pm
# interface for accessing Azure data:

package AzureDataWrapperOOP;

use strict;
use warnings;

use Data::Dumper;
use JSON;
use Xorux_lib;

# TODO introduce toggle between JSON and SQLite backends
my $use_sql = 0;    # defined $ENV{XORMON};

defined $ENV{INPUTDIR} || warn( localtime() . ': INPUTDIR undefined, config etc/lpar2rrd.cfg probably has not been loaded ' . __FILE__ . ':' . __LINE__ ) && exit 1;

my $inputdir = $ENV{INPUTDIR};
my $wrkdir   = "$inputdir/data/Azure";

my $region_path   = "$wrkdir/region";
my $database_path = "$wrkdir/database";
my $vm_path       = "$wrkdir/vm";
my $app_path      = "$wrkdir/app";
my $conf_file     = "$wrkdir/conf.json";

################################################################################

sub new {
  my ( $self, $args ) = @_;

  my $o = {};
  $o->{configuration} = get_conf();
  $o->{updated}       = ( stat($conf_file) )[9];
  $o->{acl_check}     = ( defined $args->{acl_check} ) ? $args->{acl_check} : 0;
  if ( $o->{acl_check} ) {
    require ACLx;
    $o->{aclx} = ACLx->new();
  }
  bless $o;

  return $o;
}

sub get_items {
  my $self   = shift;
  my %params = %{ shift() };
  my @result;

  unless ( defined $params{item_type} ) {
    return;    # return error code
  }

  my $labels = $self->get_labels();
  if ( $params{item_type} eq 'vm' ) {
    if ( defined $params{parent_type} && defined $params{parent_id} ) {
      if ( $params{parent_type} eq 'location' ) {
        my $location     = $params{parent_id};
        my $locations    = $self->get_conf_section('arch-location');
        my @reported_vms = ( $locations && exists $locations->{$location} ) ? @{ $locations->{$location} } : ();
        foreach my $vm (@reported_vms) {
          push @result, { $vm => $labels->{vm}->{$vm} };
        }
      }
      elsif ( $params{parent_type} eq 'resource' ) {
        my $resource     = $params{parent_id};
        my $resources    = $self->get_conf_section('arch-resource');
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
        my $resources     = $self->get_conf_section('arch-resource-app');
        my @reported_apps = ( $resources && exists $resources->{$resource} ) ? @{ $resources->{$resource} } : ();
        foreach my $app (@reported_apps) {
          push @result, { $app => $labels->{appService}->{$app} };
        }
      }
    }
  }
  elsif ( $params{item_type} eq 'location' ) {
    my $locations = $self->get_conf_section('arch-location');
    foreach my $location ( keys %{$locations} ) {
      push @result, { $location => $location };
    }
  }
  elsif ( $params{item_type} eq 'resource' ) {
    if ( defined $params{parent_type} && defined $params{parent_id} ) {
      if ( $params{parent_type} eq 'subscription' ) {
        my $subscription       = $params{parent_id};
        my $subscriptions      = $self->get_conf_section('arch-subscription');
        my @reported_resources = ( $subscriptions && exists $subscriptions->{$subscription} ) ? @{ $subscriptions->{$subscription} } : ();
        foreach my $resource (@reported_resources) {
          push @result, { $resource => $resource };
        }
      }
    }
  }
  elsif ( $params{item_type} eq 'subscription' ) {
    my $subscriptions = $self->get_conf_section('arch-subscription');
    foreach my $subscription ( keys %{$subscriptions} ) {
      push @result, { $subscription => $labels->{subscription}->{$subscription} };
    }
  }

  # ACL check
  if ( $self->{acl_check} ) {
    my @filtered;
    foreach my $item (@result) {
      my %this_item = %{$item};
      my ( $uuid, $label ) = each %this_item;
      if ( $self->is_granted($uuid) ) {
        push @filtered, { $uuid => $label };
      }
    }
    @result = @filtered;
  }

  return \@result;
}

sub get_filepath_rrd {

  # params: { type => '(vm|app|region|database)', uuid => 'DEADBEEF' }
  #     optional flag skip_acl, optional legacy param id
  my $self   = shift;
  my $params = shift;

  return unless ( defined $params->{type} && defined $params->{uuid} );
  my ( $type, $uuid, $skip_acl );
  $type     = $params->{type};
  $uuid     = $params->{uuid};
  $skip_acl = ( defined $params->{skip_acl} ) ? $params->{skip_acl} : 0;

  my $filepath;
  if ( $type eq 'vm' ) {
    $filepath = "${vm_path}/$uuid.rrd";
  }
  elsif ( $type eq 'app' ) {
    $filepath = "${app_path}/$uuid.rrd";
  }
  elsif ( $type eq 'region' ) {
    $filepath = "${region_path}/$uuid.rrd";
  }
  elsif ( $type eq 'database' ) {
    $filepath = "${database_path}/$uuid.rrd";
  }
  else {
    return;
  }

  # ACL check
  if ( $self->{acl_check} && !$skip_acl ) {
    if ( !$self->is_granted($uuid) ) {
      return;
    }
  }

  if ( defined $filepath ) {
    return $filepath;
  }
  else {
    return;
  }
}

sub get_conf_section {
  my $self    = shift;
  my $section = shift;

  if ( $section eq 'labels' ) {
    return $self->{configuration}{label};
  }
  elsif ( $section eq 'arch' ) {
    return $self->{configuration}{architecture};
  }
  elsif ( $section eq 'statuses' ) {
    return $self->{configuration}{statuses};
  }
  elsif ( $section eq 'arch-location' ) {
    return $self->{configuration}{architecture}{location_vm};
  }
  elsif ( $section eq 'arch-resource' ) {
    return $self->{configuration}{architecture}{resource_vm};
  }
  elsif ( $section eq 'arch-resource-app' ) {
    return $self->{configuration}{architecture}{resource_appService};
  }
  elsif ( $section eq 'arch-subscription' ) {
    return $self->{configuration}{architecture}{subscription_resource};
  }
  elsif ( $section eq 'arch-databaseServer' ) {
    return $self->{configuration}{architecture}{location_databaseServer};
  }
  elsif ( $section eq 'arch-database' ) {
    return $self->{configuration}{architecture}{databaseServer_database};
  }
  elsif ( $section eq 'spec-vm' ) {
    return $self->{configuration}{specification}{vm};
  }
  elsif ( $section eq 'spec-database' ) {
    return $self->{configuration}{specification}{database};
  }
  elsif ( $section eq 'spec-databaseServer' ) {
    return $self->{configuration}{specification}{databaseServer};
  }
  elsif ( $section eq 'spec-region' ) {
    return $self->{configuration}{specification}{region};
  }
  else {
    return ();
  }
}

sub get_labels {
  my $self = shift;
  return $self->get_conf_section('labels');
}

sub get_label {
  my $self = shift;
  my $type = shift;
  my $uuid = shift;

  return exists $self->{configuration}{label}{$type}{$uuid} ? $self->{configuration}{label}{$type}{$uuid} : $uuid;
}

sub get_conf_update_time {
  my $self = shift;
  return $self->{updated};
}

sub is_granted {
  my $self = shift;
  my $uuid = shift;

  if ( $self->{aclx} ) {
    return $self->{aclx}->isGranted( { hw_type => 'AZURE', item_id => $uuid, match => 'granted' } );
  }

  return;
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

################################################################################

1;
