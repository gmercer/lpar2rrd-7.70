# DockerDataWrapperOOP.pm
# interface for accessing Docker data:

package DockerDataWrapperOOP;

use strict;
use warnings;

use Data::Dumper;
use JSON;
use Docker;

use Xorux_lib;

# TODO introduce toggle between JSON and SQLite backends
my $use_sql = 0;    # defined $ENV{XORMON};

defined $ENV{INPUTDIR} || warn( localtime() . ': INPUTDIR undefined, config etc/lpar2rrd.cfg probably has not been loaded ' . __FILE__ . ':' . __LINE__ ) && exit 1;

my $inputdir = $ENV{INPUTDIR};
my $wrkdir   = "$inputdir/data/Docker";

my $container_path    = "$wrkdir/Container";
my $volume_path       = "$wrkdir/Volume";
my $label_file        = "$wrkdir/labels.json";
my $architecture_file = "$wrkdir/architecture.json";

################################################################################

sub new {
  my ( $self, $args ) = @_;

  my $o = {};
  $o->{labels}       = ( defined $args->{conf_labels} && $args->{conf_labels} ) ? get_conf('label') : {};
  $o->{architecture} = ( defined $args->{conf_arch}   && $args->{conf_arch} )   ? get_conf('arch')  : {};
  $o->{updated}      = ( stat($label_file) )[9];
  $o->{acl_check}    = ( defined $args->{acl_check} ) ? $args->{acl_check} : 0;
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
  if ( $params{item_type} eq 'container' ) {
    if ( defined $params{parent_type} && defined $params{parent_id} ) {
      if ( $params{parent_type} eq 'host' ) {
        my $host                = $params{parent_id};
        my $hosts               = $self->get_conf_section('arch-host-container');
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
        my $hosts            = $self->get_conf_section('arch-host-volume');
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
    my $hosts = $self->get_conf_section('arch-host-container');
    foreach my $host ( keys %{$hosts} ) {
      push @result, { $host => $labels->{host}->{$host} };
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
  if ( $type eq 'container' ) {
    $filepath = "${container_path}/$uuid.rrd";
  }
  elsif ( $type eq 'volume' ) {
    $filepath = "${volume_path}/$uuid.rrd";
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
    return $self->{labels};
  }
  elsif ( $section eq 'arch' ) {
    return $self->{architecture};
  }
  elsif ( $section eq 'arch-host-container' ) {
    return $self->{architecture}{host_container};
  }
  elsif ( $section eq 'arch-host-volume' ) {
    return $self->{architecture}{host_volume};
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
  return exists $self->{labels}{$type}{$uuid} ? $self->{labels}{$type}{$uuid} : $uuid;
}

sub get_conf_update_time {
  my $self = shift;
  return $self->{updated};
}

sub is_granted {
  my $self = shift;
  my $uuid = shift;

  if ( $self->{aclx} ) {
    return $self->{aclx}->isGranted( { hw_type => 'DOCKER', item_id => $uuid, match => 'granted' } );
  }

  return;
}

################################################################################

sub get_conf {
  my $type = shift;

  my $path;
  if ( $type =~ m/label/ ) {
    $path = $label_file;
  }
  elsif ( $type =~ m/arch/ ) {
    $path = $architecture_file;
  }
  else {
    $path = $architecture_file;
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
