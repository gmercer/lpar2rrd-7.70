# CloudstackDataWrapperJSON.pm
# interface for accessing Cloudstack data:

package CloudstackDataWrapperJSON;

use strict;
use warnings;

use Data::Dumper;
use JSON;

defined $ENV{INPUTDIR} || warn( localtime() . ': INPUTDIR undefined, config etc/lpar2rrd.cfg probably has not been loaded ' . __FILE__ . ':' . __LINE__ ) && exit 1;

my $inputdir = $ENV{INPUTDIR};
my $wrkdir   = "$inputdir/data/Cloudstack";

my $host_dir          = "$wrkdir/Host";
my $instance_dir      = "$wrkdir/Instance";
my $volume_dir        = "$wrkdir/Volume";
my $conf_file         = "$wrkdir/conf.json";
my $label_file        = "$wrkdir/labels.json";
my $architecture_file = "$wrkdir/architecture.json";
my $alert_file        = "$wrkdir/alert.json";

################################################################################

sub get_items {
  my %params = %{ shift() };
  my @result;

  unless ( defined $params{item_type} ) {
    return;    # return error code
  }

  my $labels = get_labels();

  if ( $params{item_type} eq 'host' ) {
    if ( defined $params{parent_type} && defined $params{parent_id} ) {
      if ( $params{parent_type} eq 'cloud' ) {
        my $cloud          = $params{parent_id};
        my $clouds         = get_conf_section('arch-cloud-host');
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
        my $clouds             = get_conf_section('arch-cloud-instance');
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
        my $clouds           = get_conf_section('arch-cloud-volume');
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
        my $clouds            = get_conf_section('arch-cloud-primaryStorage');
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
    my $clouds = get_conf_section('arch-cloud-host');
    foreach my $cloud ( keys %{$clouds} ) {
      push @result, { $cloud => $labels->{cloud}->{$cloud} };
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

sub get_alert {
  my %dictionary = ();
  {
    my $content;
    local $/;
    if ( open( my $fh, '<', "$alert_file" ) ) {
      $content = <$fh>;
      close($fh);
      %dictionary = %{ decode_json($content) };
    }
  }
  return \%dictionary;
}

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
    $dictionary = get_conf();
  }

  if ( $section eq 'labels' ) {
    return $dictionary->{label};
  }
  elsif ( $section eq 'arch' ) {
    return $dictionary->{architecture};
  }
  elsif ( $section eq 'arch-cloud-host' ) {
    return $dictionary->{architecture}{cloud_host};
  }
  elsif ( $section eq 'arch-cloud-instance' ) {
    return $dictionary->{architecture}{cloud_instance};
  }
  elsif ( $section eq 'arch-cloud-volume' ) {
    return $dictionary->{architecture}{cloud_volume};
  }
  elsif ( $section eq 'arch-cloud-primaryStorage' ) {
    return $dictionary->{architecture}{cloud_primaryStorage};
  }
  elsif ( $section eq 'spec-host' ) {
    return $dictionary->{specification}{host};
  }
  elsif ( $section eq 'spec-instance' ) {
    return $dictionary->{specification}{instance};
  }
  elsif ( $section eq 'spec-volume' ) {
    return $dictionary->{specification}{volume};
  }
  elsif ( $section eq 'spec-primaryStorage' ) {
    return $dictionary->{specification}{primaryStorage};
  }
  elsif ( $section eq 'spec-secondaryStorage' ) {
    return $dictionary->{specification}{secondaryStorage};
  }
  elsif ( $section eq 'spec-systemVM' ) {
    return $dictionary->{specification}{systemVM};
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

sub get_conf_update_time {
  return ( stat($conf_file) )[9];
}

################################################################################

1;
