# KubernetesDataWrapper.pm
# interface for accessing Kubernetes data:

package KubernetesDataWrapper;

use strict;
use warnings;

use Data::Dumper;
use JSON;
use Xorux_lib;

# TODO introduce toggle between JSON and SQLite backends
my $use_sql = 0;    # defined $ENV{XORMON};
require KubernetesDataWrapperJSON;

#use AWSDataWrapperSQLite;

# XorMon-only (ACL, TODO add KubernetesDataWrapperSQLite as metadata source)
my $acl;
if ( defined $ENV{XORMON} && $ENV{XORMON} ) {
  $use_sql = 1;

  require ACLx;
  $acl = ACLx->new();

  sub isGranted {
    my $uuid = shift;
    return $acl->isGranted( { hw_type => 'KUBERNETES', item_id => $uuid, match => 'granted' } );
  }
}

defined $ENV{INPUTDIR} || warn( localtime() . ': INPUTDIR undefined, config etc/lpar2rrd.cfg probably has not been loaded ' . __FILE__ . ':' . __LINE__ ) && exit 1;

my $inputdir       = $ENV{INPUTDIR};
my $wrkdir         = "$inputdir/data/Kubernetes";
my $pod_path       = "$wrkdir/Pod";
my $node_path      = "$wrkdir/Node";
my $container_path = "$wrkdir/Container";
my $network_path   = "$wrkdir/Network";
my $namespace_path = "$wrkdir/Namespace";

################################################################################

sub get_filepath_rrd_pod {
  my $uuid     = shift;
  my $filepath = "$pod_path/" . $uuid . ".rrd";

  return if ( $use_sql && !isGranted($uuid) );
  return $filepath;
}

sub get_filepath_rrd_pod_network {
  my $pod      = shift;
  my $uuid     = shift;
  my $filepath = "$network_path/$pod/" . $uuid . ".rrd";

  return $filepath;
}

sub get_filepath_rrd_node {
  my $uuid     = shift;
  my $filepath = "$node_path/" . $uuid . ".rrd";

  return if ( $use_sql && !isGranted($uuid) );
  return $filepath;
}

sub get_filepath_rrd_container {
  my $uuid     = shift;
  my $filepath = "$container_path/" . $uuid . ".rrd";

  return if ( $use_sql && !isGranted($uuid) );
  return $filepath;
}

sub get_filepath_rrd {

  # params: { type => '(node|pod|container|network)', uuid => 'DEADBEEF' }
  #     optional flag skip_acl, optional legacy param id
  my $params = shift;

  return unless ( defined $params->{type} && defined $params->{uuid} );
  my ( $type, $uuid, $skip_acl );
  $type     = $params->{type};
  $uuid     = $params->{uuid};
  $skip_acl = ( defined $params->{skip_acl} ) ? $params->{skip_acl} : 0;

  my $filepath;
  if ( $type eq 'pod' ) {
    $filepath = "${pod_path}/$uuid.rrd";
  }
  elsif ( $type eq 'node' ) {
    $filepath = "${node_path}/$uuid.rrd";
  }
  elsif ( $type eq 'namespace' ) {
    $filepath = "${namespace_path}/$uuid.rrd";
  }
  elsif ( $type eq 'container' ) {
    $filepath = "${container_path}/$uuid.rrd";
  }
  elsif ( $type eq 'network' && defined $params->{parent} ) {
    $filepath = "${network_path}/$params->{parent}/$uuid.rrd";
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

  $result = KubernetesDataWrapperJSON::get_items( \%params );

  return $result;
}

sub get_conf {
  my $result = KubernetesDataWrapperJSON::get_conf(@_);
  return $result;
}

sub get_conf_label {
  my $result = KubernetesDataWrapperJSON::get_conf_label(@_);
  return $result;
}

sub get_conf_architecture {
  my $result = KubernetesDataWrapperJSON::get_conf_architecture(@_);
  return $result;
}

sub get_conf_section {
  my $result = KubernetesDataWrapperJSON::get_conf_section(@_);
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
    $result = KubernetesDataWrapperJSON::get_label(@_);
  }
  return $result;
}

sub get_pod {
  my $result = KubernetesDataWrapperJSON::get_pod(@_);

  return $result;
}

sub get_pods {
  my $result = KubernetesDataWrapperJSON::get_pods();

  return $result;
}

sub get_top {
  my $result = KubernetesDataWrapperJSON::get_top();

  return $result;
}

sub get_service {
  my $result = KubernetesDataWrapperJSON::get_service(@_);

  return $result;
}

sub get_conf_update_time {
  my $result = KubernetesDataWrapperJSON::get_conf_update_time(@_);
  return $result;
}

################################################################################

1;
