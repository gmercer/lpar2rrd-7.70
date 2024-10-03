# kubernetes-json2db.pl
# store Kubernetes metadata in SQLite database

use 5.008_008;

use strict;
use warnings;

use Data::Dumper;
use JSON qw(decode_json encode_json);

use SQLiteDataWrapper;
use KubernetesDataWrapper;
use KubernetesDataWrapperOOP;
use Xorux_lib;
use HostCfg;

defined $ENV{INPUTDIR} || warn( localtime() . ': INPUTDIR undefined, probably have not read etc/lpar2rrd.cfg ' . __FILE__ . ':' . __LINE__ ) && exit 1;

# data file paths
my $inputdir = $ENV{INPUTDIR};

if ( keys %{ HostCfg::getHostConnections('Kubernetes') } == 0 ) {
  SQLiteDataWrapper::deleteItems({ hw_type => 'KUBERNETES'});
  exit(0);
}

################################################################################

my %data_in;
my %data_out;
my $DEBUG = ( exists $ENV{DEBUG} ) ? $ENV{DEBUG} : 0;

################################################################################

# load data source: conf.json

my $conf_json  = KubernetesDataWrapper::get_conf();
my $label_json = KubernetesDataWrapper::get_conf_label();

################################################################################

my $kubernetesWrapper = KubernetesDataWrapperOOP->new();

my $object_hw_type = "KUBERNETES";
my $object_label   = "Kubernetes";
my $object_id      = "KUBERNETES";

my $params = { id => $object_id, label => $object_label, hw_type => $object_hw_type };
SQLiteDataWrapper::object2db($params);

#clusters
my @clusters = @{ KubernetesDataWrapper::get_items( { item_type => 'cluster' } ) };
foreach my $cluster (@clusters) {
  my ( $cluster_id, $cluster_label ) = each %{$cluster};

  #delete old data
  SQLiteDataWrapper::deleteItemFromConfig( { uuid => $cluster_id } );

  my $fake_pods_folder_uuid = "$cluster_id-pods";
  my $fake_namespaces_folder_uuid = "$cluster_id-namespaces";

  $data_in{$object_hw_type}{$cluster_id}{label} = $cluster_label;

  undef %data_out;
  if ( exists $data_in{$object_hw_type}{$cluster_id}{label} ) { $data_out{$cluster_id}{label} = $data_in{$object_hw_type}{$cluster_id}{label}; }

  my @hostcfg;
  push( @hostcfg, $cluster_id );
  $data_out{$cluster_id}{hostcfg} = \@hostcfg;

  my $params = { id => $object_id, subsys => "CLUSTER", data => \%data_out };
  SQLiteDataWrapper::subsys2db($params);

  #nodes
  my @nodes = @{ $kubernetesWrapper->get_items( { item_type => 'node', parent_type => 'cluster', parent_id => $cluster_id } ) };
  foreach my $node (@nodes) {
    my ( $node_uuid, $node_label ) = each %{$node};

    if ( exists $label_json->{label}{node}{$node_uuid} ) { $data_in{$object_hw_type}{$node_uuid}{label} = $label_json->{label}{node}{$node_uuid}; }

    foreach my $spec_key ( keys %{ $conf_json->{specification}{node}{$node_uuid} } ) {
      if ( !defined $conf_json->{specification}{node}{$node_uuid}{$spec_key} || ref( $conf_json->{specification}{node}{$node_uuid}{$spec_key} ) eq "HASH" || ref( $conf_json->{specification}{node}{$node_uuid}{$spec_key} ) eq "ARRAY" ) {
        $data_in{$object_hw_type}{$node_uuid}{$spec_key} = " ";
      }
      else {
        $data_in{$object_hw_type}{$node_uuid}{$spec_key} = $conf_json->{specification}{node}{$node_uuid}{$spec_key};
      }
    }

    #parent pool
    my @parents;
    push @parents, $cluster_id;
    $data_in{$object_hw_type}{$node_uuid}{parents} = \@parents;

    undef %data_out;

    if ( exists $data_in{$object_hw_type}{$node_uuid}{label} )   { $data_out{$node_uuid}{label}   = $data_in{$object_hw_type}{$node_uuid}{label}; }
    if ( exists $data_in{$object_hw_type}{$node_uuid}{parents} ) { $data_out{$node_uuid}{parents} = $data_in{$object_hw_type}{$node_uuid}{parents}; }

    foreach my $spec_key ( keys %{ $conf_json->{specification}{node}{$node_uuid} } ) {
      if ( exists $data_in{$object_hw_type}{$node_uuid}{$spec_key} ) { $data_out{$node_uuid}{$spec_key} = $data_in{$object_hw_type}{$node_uuid}{$spec_key}; }
    }

    my $params = { id => $object_id, subsys => "NODE", data => \%data_out };
    SQLiteDataWrapper::subsys2db($params);

  }

  #namespaces folder
  undef %data_out;
  my @parents_namespaces;
  push @parents_namespaces, $cluster_id;
  $data_out{$fake_namespaces_folder_uuid}{label}   = "Namespaces";
  $data_out{$fake_namespaces_folder_uuid}{parents} = \@parents_namespaces;
  $params                                          = { id => $object_id, subsys => "NAMESPACES", data => \%data_out };
  SQLiteDataWrapper::subsys2db($params);
  
  #namespaces
  my @namespaces = @{ $kubernetesWrapper->get_items( { item_type => 'namespace', parent_type => 'cluster', parent_id => $cluster_id } ) };
  foreach my $namespace (@namespaces) {
    my ( $namespace_uuid, $namespace_label ) = each %{$namespace};

    my @pods = @{ $kubernetesWrapper->get_items( { item_type => 'pod', parent_type => 'namespace', parent_id => $namespace_uuid } ) };
    if ( !-f $kubernetesWrapper->get_filepath_rrd( { type => 'namespace', uuid => $namespace_uuid } ) ) {
      next;
    }

    $data_in{$object_hw_type}{$namespace_uuid}{label} = $namespace_label;

    #parent pool
    my @parents;
    push @parents, $fake_namespaces_folder_uuid;
    $data_in{$object_hw_type}{$namespace_uuid}{parents} = \@parents;

    undef %data_out;
    if ( exists $data_in{$object_hw_type}{$namespace_uuid}{label} )   { $data_out{$namespace_uuid}{label}   = $data_in{$object_hw_type}{$namespace_uuid}{label}; }
    if ( exists $data_in{$object_hw_type}{$namespace_uuid}{parents} ) { $data_out{$namespace_uuid}{parents} = $data_in{$object_hw_type}{$namespace_uuid}{parents}; }

    my $params = { id => $object_id, subsys => "NAMESPACE", data => \%data_out };
    SQLiteDataWrapper::subsys2db($params);

    # pods
    foreach my $pod (@pods) {
      my ( $pod_uuid, $pod_label ) = each %{$pod};

      $data_in{$object_hw_type}{$pod_uuid}{label} = $pod_label;
      foreach my $spec_key ( keys %{ $conf_json->{specification}{pod}{$pod_uuid} } ) {
        if ( !defined $conf_json->{specification}{pod}{$pod_uuid}{$spec_key} || ref( $conf_json->{specification}{pod}{$pod_uuid}{$spec_key} ) eq "HASH" || ref( $conf_json->{specification}{pod}{$pod_uuid}{$spec_key} ) eq "ARRAY" ) {
          $data_in{$object_hw_type}{$pod_uuid}{$spec_key} = " ";
        }
        else {
          $data_in{$object_hw_type}{$pod_uuid}{$spec_key} = $conf_json->{specification}{pod}{$pod_uuid}{$spec_key};
        }
      }

      #parent pool
      my @parents;
      push @parents, $namespace_uuid;
      $data_in{$object_hw_type}{$pod_uuid}{parents} = \@parents;

      undef %data_out;
      if ( exists $data_in{$object_hw_type}{$pod_uuid}{label} )   { $data_out{$pod_uuid}{label}   = $data_in{$object_hw_type}{$pod_uuid}{label}; }
      if ( exists $data_in{$object_hw_type}{$pod_uuid}{parents} ) { $data_out{$pod_uuid}{parents} = $data_in{$object_hw_type}{$pod_uuid}{parents}; }

      foreach my $spec_key ( keys %{ $conf_json->{specification}{pod}{$pod_uuid} } ) {
        if ( exists $data_in{$object_hw_type}{$pod_uuid}{$spec_key} ) { $data_out{$pod_uuid}{$spec_key} = $data_in{$object_hw_type}{$pod_uuid}{$spec_key}; }
      }

      my $params = { id => $object_id, subsys => "POD", data => \%data_out };
      SQLiteDataWrapper::subsys2db($params);

      #containers under pod
      my @containers = @{ $kubernetesWrapper->get_items( { item_type => 'container', parent_type => 'pod', parent_id => $pod_uuid } ) };
      foreach my $container (@containers) {
        my ( $container_uuid, $container_label ) = each %{$container};

        $data_in{$object_hw_type}{$container_uuid}{label} = defined $container_label ? $container_label : "undef";

        foreach my $spec_key ( keys %{ $conf_json->{specification}{container}{$container_uuid} } ) {
          if ( !defined $conf_json->{specification}{container}{$container_uuid}{$spec_key} || ref( $conf_json->{specification}{container}{$container_uuid}{$spec_key} ) eq "HASH" || ref( $conf_json->{specification}{container}{$container_uuid}{$spec_key} ) eq "ARRAY" ) {
            $data_in{$object_hw_type}{$container_uuid}{$spec_key} = " ";
          }
          else {
            $data_in{$object_hw_type}{$container_uuid}{$spec_key} = $conf_json->{specification}{container}{$container_uuid}{$spec_key};
          }
        }

        #parent pool
        my @parents;
        push @parents, $pod_uuid;
        $data_in{$object_hw_type}{$container_uuid}{parents} = \@parents;

        undef %data_out;
        if ( exists $data_in{$object_hw_type}{$container_uuid}{label} )   { $data_out{$container_uuid}{label}   = $data_in{$object_hw_type}{$container_uuid}{label}; }
        if ( exists $data_in{$object_hw_type}{$container_uuid}{parents} ) { $data_out{$container_uuid}{parents} = $data_in{$object_hw_type}{$container_uuid}{parents}; }

        foreach my $spec_key ( keys %{ $conf_json->{specification}{container}{$container_uuid} } ) {
          if ( exists $data_in{$object_hw_type}{$container_uuid}{$spec_key} ) { $data_out{$container_uuid}{$spec_key} = $data_in{$object_hw_type}{$container_uuid}{$spec_key}; }
        }

        my $params = { id => $object_id, subsys => "CONTAINER", data => \%data_out };
        SQLiteDataWrapper::subsys2db($params);

      }
    }
  }
}

