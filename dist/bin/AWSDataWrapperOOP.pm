# AWSDataWrapperOOP.pm
# interface for accessing AWS data:

package AWSDataWrapperOOP;

use strict;
use warnings;

use Data::Dumper;
use JSON;
use Xorux_lib;

# TODO introduce toggle between JSON and SQLite backends
my $use_sql = 0;    # defined $ENV{XORMON};

defined $ENV{INPUTDIR} || warn( localtime() . ': INPUTDIR undefined, config etc/lpar2rrd.cfg probably has not been loaded ' . __FILE__ . ':' . __LINE__ ) && exit 1;

my $inputdir = $ENV{INPUTDIR};
my $wrkdir   = "$inputdir/data/AWS";

my $ec2_path    = "$wrkdir/EC2";
my $volume_path = "$wrkdir/EBS";
my $rds_path    = "$wrkdir/RDS";
my $api_path    = "$wrkdir/API";
my $lambda_path = "$wrkdir/Lambda";
my $s3_path     = "$wrkdir/S3";
my $region_path = "$wrkdir/Region";
my $conf_file   = "$wrkdir/conf.json";

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
  if ( $params{item_type} eq 'ec2' ) {
    if ( defined $params{parent_type} && defined $params{parent_id} ) {
      if ( $params{parent_type} eq 'region' ) {
        my $region        = $params{parent_id};
        my $regions       = $self->get_conf_section('arch-region-ec2');
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
        my $regions          = $self->get_conf_section('arch-region-volume');
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
        my $regions      = $self->get_conf_section('arch-region-rds');
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
        my $regions      = $self->get_conf_section('arch-region-api');
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
        my $regions         = $self->get_conf_section('arch-region-lambda');
        my @reported_lambda = ( $regions && exists $regions->{$region} ) ? @{ $regions->{$region} } : ();
        foreach my $lambda (@reported_lambda) {
          push @result, { $lambda => $labels->{lambda}->{$lambda} };
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
  if ( $type eq 'ec2' ) {
    $filepath = "${ec2_path}/$uuid.rrd";
  }
  elsif ( $type eq 'region' ) {
    $filepath = "${region_path}/$uuid.rrd";
  }
  elsif ( $type eq 'volume' || $type eq 'ebs' ) {
    $filepath = "${volume_path}/$uuid.rrd";
  }
  elsif ( $type eq 'api' ) {
    $filepath = "${api_path}/$uuid.rrd";
  }
  elsif ( $type eq 'lambda' ) {
    $filepath = "${lambda_path}/$uuid.rrd";
  }
  elsif ( $type eq 's3' ) {
    $filepath = "${s3_path}/$uuid.rrd";
  }
  elsif ( $type eq 'rds' ) {
    $filepath = "${rds_path}/$uuid.rrd";
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
  elsif ( $section eq 'arch-region' ) {
    return $self->{configuration}{specification}{region};
  }
  elsif ( $section eq 'arch-region-ec2' ) {
    return $self->{configuration}{architecture}{region_ec2};
  }
  elsif ( $section eq 'arch-region-rds' ) {
    return $self->{configuration}{architecture}{region_rds};
  }
  elsif ( $section eq 'arch-region-volume' ) {
    return $self->{configuration}{architecture}{region_volume};
  }
  elsif ( $section eq 'arch-region-api' ) {
    return $self->{configuration}{architecture}{region_api};
  }
  elsif ( $section eq 'arch-region-lambda' ) {
    return $self->{configuration}{architecture}{region_lambda};
  }
  elsif ( $section eq 'spec-ec2' ) {
    return $self->{configuration}{specification}{ec2};
  }
  elsif ( $section eq 'spec-volume' ) {
    return $self->{configuration}{specification}{volume};
  }
  elsif ( $section eq 'spec-rds' ) {
    return $self->{configuration}{specification}{rds};
  }
  elsif ( $section eq 'spec-api' ) {
    return $self->{configuration}{specification}{api};
  }
  elsif ( $section eq 'spec-lambda' ) {
    return $self->{configuration}{specification}{lambda};
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
    return $self->{aclx}->isGranted( { hw_type => 'AWS', item_id => $uuid, match => 'granted' } );
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
