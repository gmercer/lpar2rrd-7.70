# CloudstackDataWrapperOOP.pm
# interface for accessing Cloudstack data:

package CloudstackDataWrapperOOP;

use strict;
use warnings;

use Data::Dumper;
use JSON;
use Xorux_lib;

# TODO introduce toggle between JSON and SQLite backends
my $use_sql = 0;    # defined $ENV{XORMON};

defined $ENV{INPUTDIR} || warn( localtime() . ': INPUTDIR undefined, config etc/lpar2rrd.cfg probably has not been loaded ' . __FILE__ . ':' . __LINE__ ) && exit 1;

my $inputdir = $ENV{INPUTDIR};
my $wrkdir   = "$inputdir/data/Cloudstack";

my $host_path           = "$wrkdir/Host";
my $instance_path       = "$wrkdir/Instance";
my $volume_path         = "$wrkdir/Volume";
my $primaryStorage_path = "$wrkdir/PrimaryStorage";
my $conf_file           = "$wrkdir/conf.json";
my $label_file          = "$wrkdir/labels.json";
my $architecture_file   = "$wrkdir/architecture.json";
my $alert_file          = "$wrkdir/alert.json";

################################################################################

sub new {
  my ( $self, $args ) = @_;

  my $o = {};
  $o->{configuration} = get_conf();
  $o->{labels}        = ( defined $args->{conf_labels} && $args->{conf_labels} ) ? get_conf('label') : {};
  $o->{architecture}  = ( defined $args->{conf_arch} && $args->{conf_arch} ) ? get_conf('arch') : {};
  $o->{alerts}        = ( defined $args->{conf_alerts} && $args->{conf_alerts} ) ? get_conf('alert') : {};
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
  if ( $params{item_type} eq 'host' ) {
    if ( defined $params{parent_type} && defined $params{parent_id} ) {
      if ( $params{parent_type} eq 'cloud' ) {
        my $cloud          = $params{parent_id};
        my $clouds         = $self->get_conf_section('arch-cloud-host');
        my @reported_hosts = ( $clouds && exists $clouds->{$cloud} ) ? @{ $clouds->{$cloud} } : ();
        foreach my $host (@reported_hosts) {
          push @result, { $host => $labels->{host}->{$host} };
        }
      }
    }
    else {
      foreach my $host ( keys %{ $labels->{host} } ) {
        push @result, { $host => $labels->{host}->{$host} };
      }
    }
  }
  elsif ( $params{item_type} eq 'instance' ) {
    if ( defined $params{parent_type} && defined $params{parent_id} ) {
      if ( $params{parent_type} eq 'cloud' ) {
        my $cloud              = $params{parent_id};
        my $clouds             = $self->get_conf_section('arch-cloud-instance');
        my @reported_instances = ( $clouds && exists $clouds->{$cloud} ) ? @{ $clouds->{$cloud} } : ();
        foreach my $instance (@reported_instances) {
          push @result, { $instance => $labels->{instance}->{$instance} };
        }
      }
    }
    else {
      foreach my $instance ( keys %{ $labels->{instance} } ) {
        push @result, { $instance => $labels->{instance}->{$instance} };
      }
    }
  }
  elsif ( $params{item_type} eq 'volume' ) {
    if ( defined $params{parent_type} && defined $params{parent_id} ) {
      if ( $params{parent_type} eq 'cloud' ) {
        my $cloud            = $params{parent_id};
        my $clouds           = $self->get_conf_section('arch-cloud-volume');
        my @reported_volumes = ( $clouds && exists $clouds->{$cloud} ) ? @{ $clouds->{$cloud} } : ();
        foreach my $volume (@reported_volumes) {
          push @result, { $volume => $labels->{volume}->{$volume} };
        }
      }
    }
    else {
      foreach my $instance ( keys %{ $labels->{instance} } ) {
        push @result, { $instance => $labels->{instance}->{$instance} };
      }
    }
  }
  elsif ( $params{item_type} eq 'primaryStorage' ) {
    if ( defined $params{parent_type} && defined $params{parent_id} ) {
      if ( $params{parent_type} eq 'cloud' ) {
        my $cloud             = $params{parent_id};
        my $clouds            = $self->get_conf_section('arch-cloud-primaryStorage');
        my @reported_storages = ( $clouds && exists $clouds->{$cloud} ) ? @{ $clouds->{$cloud} } : ();
        foreach my $storage (@reported_storages) {
          push @result, { $storage => $labels->{primaryStorage}->{$storage} };
        }
      }
    }
    else {
      foreach my $storage ( keys %{ $labels->{primaryStorage} } ) {
        push @result, { $storage => $labels->{primaryStorage}->{$storage} };
      }
    }
  }
  elsif ( $params{item_type} eq 'cloud' ) {
    my $clouds = $self->get_conf_section('arch-cloud-host');
    foreach my $cloud ( keys %{$clouds} ) {
      push @result, { $cloud => $labels->{cloud}->{$cloud} };
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

  # params: { type => '(host|instance|volume|primaryStorage)', uuid => 'DEADBEEF' }
  #     optional flag skip_acl, optional legacy param id
  my $self   = shift;
  my $params = shift;

  return unless ( defined $params->{type} && defined $params->{uuid} );
  my ( $type, $uuid, $skip_acl );
  $type     = $params->{type};
  $uuid     = $params->{uuid};
  $skip_acl = ( defined $params->{skip_acl} ) ? $params->{skip_acl} : 0;

  my $filepath;
  if ( $type eq 'host' ) {
    $filepath = "${host_path}/$uuid.rrd";
  }
  elsif ( $type eq 'instance' ) {
    $filepath = "${instance_path}/$uuid.rrd";
  }
  elsif ( $type eq 'volume' ) {
    $filepath = "${volume_path}/$uuid.rrd";
  }
  elsif ( $type eq 'primaryStorage' ) {
    $filepath = "${primaryStorage_path}/$uuid.rrd";
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
    return $self->{labels}{label};
  }
  elsif ( $section eq 'arch' ) {
    return $self->{architecture}{architecture};
  }
  elsif ( $section eq 'arch-cloud-host' ) {
    return $self->{architecture}{architecture}{cloud_host};
  }
  elsif ( $section eq 'arch-cloud-instance' ) {
    return $self->{architecture}{architecture}{cloud_instance};
  }
  elsif ( $section eq 'arch-cloud-volume' ) {
    return $self->{architecture}{architecture}{cloud_volume};
  }
  elsif ( $section eq 'arch-cloud-primaryStorage' ) {
    return $self->{architecture}{architecture}{cloud_primaryStorage};
  }
  elsif ( $section eq 'spec-host' ) {
    return $self->{configuration}{specification}{host};
  }
  elsif ( $section eq 'spec-instance' ) {
    return $self->{configuration}{specification}{instance};
  }
  elsif ( $section eq 'spec-volume' ) {
    return $self->{configuration}{specification}{volume};
  }
  elsif ( $section eq 'spec-primaryStorage' ) {
    return $self->{configuration}{specification}{primaryStorage};
  }
  elsif ( $section eq 'spec-secondaryStorage' ) {
    return $self->{configuration}{specification}{secondaryStorage};
  }
  elsif ( $section eq 'spec-systemVM' ) {
    return $self->{configuration}{specification}{systemVM};
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
  return exists $self->{labels}{label}{$type}{$uuid} ? $self->{labels}{label}{$type}{$uuid} : $uuid;
}

sub get_host_cpu_count {
  my $self = shift;
  my $uuid = shift;
  return exists $self->{configuration}{specification}{host}{$uuid}{cpu_count} ? $self->{configuration}{specification}{host}{$uuid}{cpu_count} : -1;
}

sub shorten_sr_uuid {
  my $self = shift;
  my $uuid = shift;
  return ( split( '-', $uuid ) )[0];
}

sub get_conf_update_time {
  my $self = shift;
  return $self->{updated};
}

sub is_granted {
  my $self = shift;
  my $uuid = shift;

  if ( $self->{aclx} ) {
    return $self->{aclx}->isGranted( { hw_type => 'CLOUDSTACK', item_id => $uuid, match => 'granted' } );
  }

  return;
}

################################################################################

sub get_conf {
  my $type = shift || 'conf';

  my $path;
  if ( $type =~ m/label/ ) {
    $path = $label_file;
  }
  elsif ( $type =~ m/arch/ ) {
    $path = $architecture_file;
  }
  elsif ( $type =~ m/alert/ ) {
    $path = $alert_file;
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
