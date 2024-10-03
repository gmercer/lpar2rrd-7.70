# GCloudDataWrapperOOP.pm
# interface for accessing GCloud data:

package GCloudDataWrapperOOP;

use strict;
use warnings;

use Data::Dumper;
use JSON;
use Xorux_lib;

# TODO introduce toggle between JSON and SQLite backends
my $use_sql = 0;    # defined $ENV{XORMON};

defined $ENV{INPUTDIR} || warn( localtime() . ': INPUTDIR undefined, config etc/lpar2rrd.cfg probably has not been loaded ' . __FILE__ . ':' . __LINE__ ) && exit 1;

my $inputdir = $ENV{INPUTDIR};
my $wrkdir   = "$inputdir/data/GCloud";

my $compute_path  = "$wrkdir/compute";
my $database_path = "$wrkdir/database";
my $region_path   = "$wrkdir/region";
my $conf_file     = "$wrkdir/conf.json";
my $agent_file    = "$wrkdir/agent.json";

################################################################################

sub new {
  my ( $self, $args ) = @_;

  my $o = {};
  $o->{configuration} = get_conf();
  $o->{agent}         = ( defined $args->{conf_agent} && $args->{conf_agent} ) ? get_conf('agent') : {};
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

  my $labels  = $self->get_conf_section('labels');
  my $engines = $self->get_conf_section('engines');
  if ( $params{item_type} eq 'compute' ) {
    if ( defined $params{parent_type} && defined $params{parent_id} ) {
      if ( $params{parent_type} eq 'region' ) {
        my $region            = $params{parent_id};
        my $regions           = $self->get_conf_section('arch-region');
        my @reported_computes = ( $regions && exists $regions->{$region} ) ? @{ $regions->{$region} } : ();
        foreach my $compute (@reported_computes) {
          my $compute_path = $self->get_filepath_rrd( { type => 'compute', uuid => $compute } );
          if ( defined $compute_path && -f $compute_path ) {
            push @result, { $compute => $self->get_label( 'compute', $compute ) };
          }
        }
      }
    }
    else {
      foreach my $compute_uuid ( keys %{ $labels->{compute} } ) {
        push @result, { $compute_uuid => $self->get_label( 'compute', $compute_uuid ) };
      }
    }
  }
  elsif ( $params{item_type} eq 'database' ) {
    if ( defined $params{parent_type} && defined $params{parent_id} ) {
      if ( $params{parent_type} eq 'region' ) {
        if ( defined $params{engine} ) {
          my $region             = $params{parent_id};
          my $regions            = $self->get_conf_section('arch-database');
          my @reported_databases = ( $regions && exists $regions->{$region} ) ? @{ $regions->{$region} } : ();
          foreach my $database (@reported_databases) {
            if ( !defined $engines->{$database} || $engines->{$database} ne $params{engine} ) {
              next;
            }
            if ( -f $self->get_filepath_rrd( { type => 'database', uuid => $database } ) ) {
              push @result, { $database => $self->get_label( 'database', $database ) };
            }
          }
        }
        else {
          my $region             = $params{parent_id};
          my $regions            = $self->get_conf_section('arch-database');
          my @reported_databases = ( $regions && exists $regions->{$region} ) ? @{ $regions->{$region} } : ();
          foreach my $database (@reported_databases) {
            if ( -f $self->get_filepath_rrd( { type => 'database', uuid => $database } ) ) {
              push @result, { $database => $self->get_label( 'database', $database ) };
            }
          }
        }
      }
    }
  }
  elsif ( $params{item_type} eq 'region' ) {
    my $regions = $self->get_conf_section('arch-region');
    foreach my $region ( keys %{$regions} ) {
      push @result, { $region => $region };
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
  if ( $type eq 'compute' ) {
    $filepath = "${compute_path}/$uuid.rrd";
  }
  elsif ( $type eq 'database' ) {
    $filepath = "${database_path}/$uuid.rrd";
  }
  elsif ( $type eq 'region' ) {
    $filepath = "${region_path}/$uuid.rrd";
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
  elsif ( $section eq 'engines' ) {
    return $self->{configuration}{engines};
  }
  elsif ( $section eq 'arch-region' ) {
    return $self->{configuration}{architecture}{region_compute};
  }
  elsif ( $section eq 'arch-database' ) {
    return $self->{configuration}{architecture}{region_database};
  }
  elsif ( $section eq 'spec-compute' ) {
    return $self->{configuration}{specification}{compute};
  }
  elsif ( $section eq 'spec-database' ) {
    return $self->{configuration}{specification}{database};
  }
  elsif ( $section eq 'spec-region' ) {
    return $self->{configuration}{specification}{region};
  }
  elsif ( $section eq 'spec-agent' ) {
    return $self->{agent};
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

sub get_engines {
  my $self = shift;
  return $self->get_conf_section('engines');
}

sub get_engine {
  my $self       = shift;
  my $uuid       = shift;
  my $dictionary = $self->get_conf_section('engines');

  return exists $dictionary->{$uuid} ? $dictionary->{$uuid} : ();
}

sub get_conf_update_time {
  my $self = shift;
  return $self->{updated};
}

sub is_granted {
  my $self = shift;
  my $uuid = shift;

  if ( $self->{aclx} ) {
    return $self->{aclx}->isGranted( { hw_type => 'GCLOUD', item_id => $uuid, match => 'granted' } );
  }

  return;
}

################################################################################

sub get_conf {
  my $type = shift || 'conf';

  my $path;
  if ( $type =~ m/agent/ ) {
    $path = $agent_file;
  }
  else {
    $path = $conf_file;
  }

  my %dictionary = ();
  {
    my $content;
    local $/;
    if ( open( my $fh, '<', "$path" ) ) {
      $content = <$fh>;
      close($fh);
      %dictionary = %{ decode_json($content) };
    }
  }
  return \%dictionary;
}
################################################################################

1;
