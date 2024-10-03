# DockerDataWrapper.pm
# interface for accessing Docker data:

package DockerDataWrapper;

use strict;
use warnings;

use Data::Dumper;
use JSON;
use Xorux_lib;

# TODO introduce toggle between JSON and SQLite backends
my $use_sql = 0;    # defined $ENV{XORMON};
require DockerDataWrapperJSON;

# XorMon-only (ACL, TODO add ProxmoxDataWrapperSQLite as metadata source)
my $acl;
if ( defined $ENV{XORMON} && $ENV{XORMON} ) {
  $use_sql = 1;

  require ACLx;
  $acl = ACLx->new();

  sub isGranted {
    my $uuid = shift;
    return $acl->isGranted( { hw_type => 'DOCKER', item_id => $uuid, match => 'granted' } );
  }
}

defined $ENV{INPUTDIR} || warn( localtime() . ': INPUTDIR undefined, config etc/lpar2rrd.cfg probably has not been loaded ' . __FILE__ . ':' . __LINE__ ) && exit 1;

my $inputdir       = $ENV{INPUTDIR};
my $wrkdir         = "$inputdir/data/Docker";
my $container_path = "$wrkdir/Container";
my $volume_path    = "$wrkdir/Volume";

################################################################################

sub get_filepath_rrd {

  # params: { type => '(container|volume)', uuid => 'DEADBEEF' }
  #     optional flag skip_acl, optional legacy param id
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
  else {
    return;
  }

  # ACL check
  if ( $use_sql && !$skip_acl ) {
    if ( !isGranted($uuid) ) {
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

sub get_items {
  my %params = %{ shift() };
  my $result;

  unless ( defined $params{item_type} ) {
    return;    # return error code
  }

  $result = DockerDataWrapperJSON::get_items( \%params );

  return $result;
}

sub get_conf_label {
  my $result = DockerDataWrapperJSON::get_conf_label(@_);
  return $result;
}

sub get_conf_architecture {
  my $result = DockerDataWrapperJSON::get_conf_architecture(@_);
  return $result;
}

sub get_conf_section {
  my $result = DockerDataWrapperJSON::get_conf_section(@_);
  return $result;
}

sub get_labels {
  return get_conf_section('labels');
}

sub get_label {
  my ( $result, $self, $type, $uuid );

  #OOP
  if ( scalar(@_) == 3 ) {
    ( $self, $type, $uuid ) = @_;
  }

  if ( exists $self->{labels} ) {
    $result = $self->{labels}->{labels}->{$type}->{$uuid};
  }
  else {
    $result = DockerDataWrapperJSON::get_label(@_);
  }
  return $result;
}

################################################################################

1;
