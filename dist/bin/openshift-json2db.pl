# openshift-json2db.pl
# store Openshift metadata in SQLite database

use 5.008_008;

use strict;
use warnings;

use Data::Dumper;
use JSON qw(decode_json encode_json);
use HostCfg;
use SQLiteDataWrapper;
use OpenshiftDataWrapper;
use OpenshiftDataWrapperOOP;
use Xorux_lib;

defined $ENV{INPUTDIR} || warn( localtime() . ': INPUTDIR undefined, probably have not read etc/lpar2rrd.cfg ' . __FILE__ . ':' . __LINE__ ) && exit 1;

if ( keys %{ HostCfg::getHostConnections('Openshift') } == 0 ) {
  SQLiteDataWrapper::deleteItems({ hw_type => 'OPENSHIFT'});
  exit(0);
}

# data file paths
my $inputdir  = $ENV{INPUTDIR};
my $data_path = "$inputdir/data/Openshift";

#check pid
my $pid_json = '';
my $file     = "json2db-pid.json";
if ( open( my $fh, '<', "$data_path/$file" ) ) {
  while ( my $row = <$fh> ) {
    chomp $row;
    $pid_json .= $row;
  }
  close($fh);

  # decode JSON
  my $pid_data = decode_json($pid_json);
  if ( ref($pid_data) ne "HASH" ) {
    warn( localtime() . ": Error decoding JSON in background file: missing data" );
  }
  else {
    if ( defined $pid_data->{pid} ) {
      my $exists = kill 0, $pid_data->{pid};
      if ($exists) {
        print "Process openshift-json2db exists, exiting...\n";
        exit(0);
      }
    }
  }
}

my $my_pid   = $$;
my %hash_pid = ( 'pid' => $my_pid );
open my $fh2, ">", $data_path . "/" . $file;
print $fh2 JSON->new->pretty->encode( \%hash_pid );
close $fh2;

################################################################################

my %data_in;
my %data_out;
my $DEBUG = ( exists $ENV{DEBUG} ) ? $ENV{DEBUG} : 0;

################################################################################

# OOP

my $openshift = OpenshiftDataWrapperOOP->new();
my $conf      = $openshift->{conf};

################################################################################

my $object_hw_type = "OPENSHIFT";
my $object_label   = "Openshift";
my $object_id      = "OPENSHIFT";

my $params = { id => $object_id, label => $object_label, hw_type => $object_hw_type };
SQLiteDataWrapper::object2db($params);

#clusters
my @clusters = @{ $openshift->get_items( { item_type => 'cluster' } ) };
foreach my $cluster (@clusters) {
  my ( $cluster_id, $cluster_label ) = each %{$cluster};

  #delete old data
  SQLiteDataWrapper::deleteItemFromConfig( { uuid => $cluster_id } );

  my $fake_pods_folder_uuid     = "$cluster_id-pods";
  my $fake_projects_folder_uuid = "$cluster_id-projects";

  $data_in{$object_hw_type}{$cluster_id}{label} = $cluster_label;

  undef %data_out;
  if ( exists $data_in{$object_hw_type}{$cluster_id}{label} ) { $data_out{$cluster_id}{label} = $data_in{$object_hw_type}{$cluster_id}{label}; }

  my @hostcfg;
  push( @hostcfg, $cluster_id );
  $data_out{$cluster_id}{hostcfg} = \@hostcfg;

  my $params = { id => $object_id, subsys => "CLUSTER", data => \%data_out };
  SQLiteDataWrapper::subsys2db($params);

  #nodes
  my @nodes = @{ $openshift->get_items( { item_type => 'node', parent_type => 'cluster', parent_id => $cluster_id } ) };
  foreach my $node (@nodes) {
    my ( $node_uuid, $node_label ) = each %{$node};

    $data_in{$object_hw_type}{$node_uuid}{label} = $node_label;

    #foreach my $spec_key (keys %{$conf->{specification}{node}{$node_uuid}}) {
    #  if (!defined $conf->{specification}{node}{$node_uuid}{$spec_key} || ref($conf->{specification}{node}{$node_uuid}{$spec_key}) eq "HASH" || ref($conf->{specification}{node}{$node_uuid}{$spec_key}) eq "ARRAY" ) {
    #    $data_in{$object_hw_type}{$node_uuid}{$spec_key} = " ";
    #  } else {
    #    $data_in{$object_hw_type}{$node_uuid}{$spec_key} = $conf->{specification}{node}{$node_uuid}{$spec_key};
    #  }
    #}

    #parent pool
    my @parents;
    push @parents, $cluster_id;
    $data_in{$object_hw_type}{$node_uuid}{parents} = \@parents;

    undef %data_out;

    if ( exists $data_in{$object_hw_type}{$node_uuid}{label} )   { $data_out{$node_uuid}{label}   = $data_in{$object_hw_type}{$node_uuid}{label}; }
    if ( exists $data_in{$object_hw_type}{$node_uuid}{parents} ) { $data_out{$node_uuid}{parents} = $data_in{$object_hw_type}{$node_uuid}{parents}; }

    #foreach my $spec_key (keys %{$conf->{specification}{node}{$node_uuid}}) {
    #  if ( exists $data_in{$object_hw_type}{$node_uuid}{$spec_key} ) { $data_out{$node_uuid}{$spec_key} = $data_in{$object_hw_type}{$node_uuid}{$spec_key}; }
    #}

    my $params = { id => $object_id, subsys => "NODE", data => \%data_out };
    SQLiteDataWrapper::subsys2db($params);

  }

  #projects folder
  undef %data_out;
  my @parents_projects;
  push @parents_projects, $cluster_id;
  $data_out{$fake_projects_folder_uuid}{label}   = "Projects";
  $data_out{$fake_projects_folder_uuid}{parents} = \@parents_projects;
  $params                                        = { id => $object_id, subsys => "PROJECTS", data => \%data_out };
  SQLiteDataWrapper::subsys2db($params);

  #projects
  my @projects = @{ $openshift->get_items( { item_type => 'project', parent_type => 'cluster', parent_id => $cluster_id } ) };
  foreach my $project (@projects) {
    my ( $project_uuid, $project_label ) = each %{$project};

    my @pods = @{ $openshift->get_items( { item_type => 'pod', parent_type => 'namespace', parent_id => $project_uuid, cluster => $cluster_id } ) };

    if (!-f $openshift->get_filepath_rrd( { type => 'namespace', uuid => $project_uuid } )) {
      next;
    }

    #my $pods_count = scalar @pods;
    #if ( $pods_count < 1 ) {
    #  next;
    #}
    #print "json2db: Inserting $pods_count pods under project $project_label \n";

    $data_in{$object_hw_type}{$project_uuid}{label} = $project_label;

    #parent pool
    my @parents;
    push @parents, $fake_projects_folder_uuid;
    $data_in{$object_hw_type}{$project_uuid}{parents} = \@parents;

    undef %data_out;
    if ( exists $data_in{$object_hw_type}{$project_uuid}{label} )   { $data_out{$project_uuid}{label}   = $data_in{$object_hw_type}{$project_uuid}{label}; }
    if ( exists $data_in{$object_hw_type}{$project_uuid}{parents} ) { $data_out{$project_uuid}{parents} = $data_in{$object_hw_type}{$project_uuid}{parents}; }

    my $params = { id => $object_id, subsys => "PROJECT", data => \%data_out };
    SQLiteDataWrapper::subsys2db($params);

    #pods
    foreach my $pod (@pods) {
      my ( $pod_uuid, $pod_label ) = each %{$pod};

      $data_in{$object_hw_type}{$pod_uuid}{label} = $pod_label;

      #foreach my $spec_key (keys %{$conf->{specification}{pod}{$pod_uuid}}) {
      #  if (!defined $conf->{specification}{pod}{$pod_uuid}{$spec_key} || ref($conf->{specification}{pod}{$pod_uuid}{$spec_key}) eq "HASH" || ref($conf->{specification}{pod}{$pod_uuid}{$spec_key}) eq "ARRAY" ) {
      #    $data_in{$object_hw_type}{$pod_uuid}{$spec_key} = " ";
      #  } else {
      #    $data_in{$object_hw_type}{$pod_uuid}{$spec_key} = $conf->{specification}{pod}{$pod_uuid}{$spec_key};
      #  }
      #}

      #parent pool
      my @parents;
      push @parents, $project_uuid;
      $data_in{$object_hw_type}{$pod_uuid}{parents} = \@parents;

      undef %data_out;
      if ( exists $data_in{$object_hw_type}{$pod_uuid}{label} )   { $data_out{$pod_uuid}{label}   = $data_in{$object_hw_type}{$pod_uuid}{label}; }
      if ( exists $data_in{$object_hw_type}{$pod_uuid}{parents} ) { $data_out{$pod_uuid}{parents} = $data_in{$object_hw_type}{$pod_uuid}{parents}; }

      #foreach my $spec_key (keys %{$conf->{specification}{pod}{$pod_uuid}}) {
      #  if ( exists $data_in{$object_hw_type}{$pod_uuid}{$spec_key} ) { $data_out{$pod_uuid}{$spec_key} = $data_in{$object_hw_type}{$pod_uuid}{$spec_key}; }
      #}

      my $params = { id => $object_id, subsys => "POD", data => \%data_out };
      SQLiteDataWrapper::subsys2db($params);

      #containers under pod
      my @containers = @{ $openshift->get_items( { item_type => 'container', parent_type => 'pod', parent_id => $pod_uuid } ) };
      foreach my $container (@containers) {
        my ( $container_uuid, $container_label ) = each %{$container};

        $data_in{$object_hw_type}{$container_uuid}{label} = defined $container_label ? $container_label : "undef";

        #foreach my $spec_key (keys %{$conf->{specification}{container}{$container_uuid}}) {
        #  if (!defined $conf->{specification}{container}{$container_uuid}{$spec_key} || ref($conf->{specification}{container}{$container_uuid}{$spec_key}) eq "HASH" || ref($conf->{specification}{container}{$container_uuid}{$spec_key}) eq "ARRAY" ) {
        #    $data_in{$object_hw_type}{$container_uuid}{$spec_key} = " ";
        #  } else {
        #    $data_in{$object_hw_type}{$container_uuid}{$spec_key} = $conf->{specification}{container}{$container_uuid}{$spec_key};
        #  }
        #}

        #parent pool
        my @parents;
        push @parents, $pod_uuid;
        $data_in{$object_hw_type}{$container_uuid}{parents} = \@parents;

        undef %data_out;
        if ( exists $data_in{$object_hw_type}{$container_uuid}{label} )   { $data_out{$container_uuid}{label}   = $data_in{$object_hw_type}{$container_uuid}{label}; }
        if ( exists $data_in{$object_hw_type}{$container_uuid}{parents} ) { $data_out{$container_uuid}{parents} = $data_in{$object_hw_type}{$container_uuid}{parents}; }

        #foreach my $spec_key (keys %{$conf->{specification}{container}{$container_uuid}}) {
        #  if ( exists $data_in{$object_hw_type}{$container_uuid}{$spec_key} ) { $data_out{$container_uuid}{$spec_key} = $data_in{$object_hw_type}{$container_uuid}{$spec_key}; }
        #}

        my $params = { id => $object_id, subsys => "CONTAINER", data => \%data_out };
        SQLiteDataWrapper::subsys2db($params);

      }

    }

  }

}

