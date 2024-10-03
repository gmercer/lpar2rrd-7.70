# power-json2db.pl
use 5.008_008;

use strict;
use warnings;

use Data::Dumper;

use JSON qw(decode_json encode_json);
use DBI;

use SQLiteDataWrapper;
use PowerDataWrapper;
use Xorux_lib;
use Storable;

defined $ENV{INPUTDIR} || Xorux_lib::error( " INPUTDIR undefined, probably have not read etc/lpar2rrd.cfg " . __FILE__ . ":" . __LINE__ ) && exit 1;

# data file paths
my $inputdir = $ENV{INPUTDIR};

#my $db_filepath         = "$inputdir/data/data.db";
#my $iostats_dir         = "$inputdir/data/power_iostats";
#my $metadata_file       = "$iostats_dir/conf.json";
#my $tmpdir              = "$inputdir/tmp";

################################################################################

my %data_in;
my %data_out;
my $DEBUG = ( exists $ENV{DEBUG} ) ? $ENV{DEBUG} : 0;

################################################################################

#my $conf_json = Xorux_lib::read_json("$inputdir/tmp/power_conf.json");
if ( !-e "$inputdir/tmp/power_conf.storable" ) {
  print "Tried to update the database for Xormon but there is no $inputdir/tmp/power_conf.storable. Exiting.\n";
  exit(1);
}
my $conf_json = Storable::retrieve("$inputdir/tmp/power_conf.storable");

################################################################################

# fill tables

# 1. setup %data_in
#
# $data_in{$st_name}{DEVICE}{'Serial'} = …

# 2. put %data_in into %data_out
#
# my $hash_key                                                                                              = $st_serial;
# if ( exists $data_in{$st_name}{DEVICE}{'Version'} )             { $data_out{DEVICE}{$hash_key}{'version'} = $data_in{$st_name}{DEVICE}{'Version'} };

# 3. save %data_out
#
# my $params = {id => $st_serial, label => $st_name, hw_type => "NIMBLE"};
# SQLiteDataWrapper::object2db( $params );
# $params = { id => $st_serial, subsys => "DEVICE", data => $data_out{DEVICE} };
# SQLiteDataWrapper::subsys2db( $params );

my $object_hw_type = "POWER";
my $object_label   = "IBM Power Systems";
my $object_id      = "POWER";

my $params = { id => $object_id, label => $object_label, hw_type => $object_hw_type };
SQLiteDataWrapper::object2db($params);

# VMs

#print Dumper $conf_json->{pools};

foreach my $vm ( keys %{ $conf_json->{vms} } ) {
  if ( exists $conf_json->{vms}{$vm}{label} ) { $data_in{POWER}{$vm}{label} = $conf_json->{vms}{$vm}{label} }

  #check parent(s)
  my @parents;
  if ( exists $conf_json->{vms}{$vm}{parent} ) {
    my $parent = $conf_json->{vms}{$vm}{parent};
    if ($parent) { push @parents, $parent; }
  }
  if ( scalar @parents ) { $data_in{POWER}{$vm}{parents} = \@parents; }

  #create data_out format for SQLiteDataWrapper
  #if ( exists $data_in{POWER}{$vm}{label}            ) { $data_out{$vm}{label}            = $data_in{POWER}{$vm}{label}; }
  #if ( exists $data_in{POWER}{$vm}{parents}          ) { $data_out{$vm}{parents}          = $data_in{POWER}{$vm}{parents}; }

  foreach my $metric ( keys %{ $conf_json->{vms}{$vm} } ) {
    if ( exists $conf_json->{vms}{$vm}{$metric} ) { $data_in{POWER}{$vm}{$metric} = $conf_json->{vms}{$vm}{$metric} }
  }

  undef %data_out;
  foreach my $metric ( keys %{ $data_in{POWER}{$vm} } ) {
    if ( exists $data_in{POWER}{$vm}{$metric} ) { $data_out{$vm}{$metric} = $data_in{POWER}{$vm}{$metric}; }
  }

  my $params = { id => $object_id, subsys => "VM", data => \%data_out };
  print "power-json2db.pl : Inserting $params->{subsys} : $data_out{$vm}{label} into database\n";
  SQLiteDataWrapper::subsys2db($params);
}

foreach my $pool ( keys %{ $conf_json->{pools} } ) {

  foreach my $metric ( keys %{ $conf_json->{pools}{$pool} } ) {
    if ( exists $conf_json->{pools}{$pool}{$metric} ) { $data_in{POWER}{$pool}{$metric} = $conf_json->{pools}{$pool}{$metric} }
  }

  #check parent(s)
  my @parents;
  if ( exists $conf_json->{pools}{$pool}{parent} ) {
    my $parent = $conf_json->{pools}{$pool}{parent};
    if ($parent) { push @parents, $parent; }
  }
  if ( scalar @parents ) { $data_in{POWER}{$pool}{parents} = \@parents; }

  #create data_out format for SQLiteDataWrapper
  undef %data_out;
  foreach my $metric ( keys %{ $data_in{POWER}{$pool} } ) {
    if ( $metric eq "label" )                                          { next; }
    if ( exists $data_in{POWER}{$pool}{$metric} )                      { $data_out{$pool}{$metric} = $data_in{POWER}{$pool}{$metric}; }
    if ( $metric eq 'name' && exists $data_in{POWER}{$pool}{$metric} ) { $data_out{$pool}{label} = $data_in{POWER}{$pool}{$metric}; }
  }

  my $params = { id => $object_id, subsys => "POOL", data => \%data_out };
  print "power-json2db.pl : Inserting $params->{subsys} : $data_out{$pool}{name} into database\n";
  SQLiteDataWrapper::subsys2db($params);
}

my %hosts = %{ HostCfg::getHostConnections("IBM Power Systems") };

foreach my $server ( keys %{ $conf_json->{servers} } ) {
  my @host_cfgs;
  foreach my $metric ( keys %{ $conf_json->{servers}{$server} } ) {
    if ( exists $conf_json->{servers}{$server}{$metric} ) { $data_in{POWER}{$server}{$metric} = $conf_json->{servers}{$server}{$metric} }
  }

  #  if ( exists $conf_json->{servers}{$server}{label}                         ) { $data_in{POWER}{$server}{label}            = $conf_json->{servers}{$server}{label} };
  #  if ( exists $conf_json->{servers}{$server}{REST_UUID}                         ) { $data_in{POWER}{$server}{REST_UUID}            = $conf_json->{servers}{$server}{REST_UUID} };
  #  if ( exists $conf_json->{servers}{$server}{parent}                         ) { $data_in{POWER}{$server}{parent}            = $conf_json->{servers}{$server}{parent} };

  #check parent(s)
  my @parents;
  my $host_cfg_uid = "";
  if ( exists $conf_json->{servers}{$server}{parent} ) {
    my $parent = $conf_json->{servers}{$server}{parent};
    foreach my $hmc_alias ( keys %hosts ) {
      my $hmc_id_cfg = $hosts{$hmc_alias}{uuid};
      foreach my $p ( @{$parent} ) {
        $host_cfg_uid = $hmc_id_cfg;
        push( @host_cfgs, $host_cfg_uid ) if ( PowerDataWrapper::md5_string( $hosts{$hmc_alias}{host} ) eq $p );
      }
    }

    #if ( $parent ) { push @parents, $parent; }
    @parents = @{$parent};
  }
  if ( scalar @parents )   { $data_in{POWER}{$server}{parents} = \@parents; }
  if ( scalar @host_cfgs ) { $data_in{POWER}{$server}{hostcfg} = \@host_cfgs; }

  #create data_out format for SQLiteDataWrapper
  undef %data_out;
  foreach my $metric ( keys %{ $data_in{POWER}{$server} } ) {
    if ( exists $data_in{POWER}{$server}{$metric} ) { $data_out{$server}{$metric} = $data_in{POWER}{$server}{$metric}; }
  }

  #  if ( exists $data_in{POWER}{$server}{label}                  ) { $data_out{$server}{label}                   = $data_in{POWER}{$server}{label}; }
  #  if ( exists $data_in{POWER}{$server}{REST_UUID}           ) { $data_out{$server}{REST_UUID}            = $data_in{POWER}{$server}{REST_UUID}; }
  #  if ( exists $data_in{POWER}{$server}{parents}                ) { $data_out{$server}{parents}                 = $data_in{POWER}{$server}{parents}; }

  my $params = { id => $object_id, subsys => "SERVER", data => \%data_out };
  print "power-json2db.pl : Inserting $params->{subsys} : $data_out{$server}{label} into database\n";
  SQLiteDataWrapper::subsys2db($params);
}

my @interfaces_types = ( "LAN", "SAN", "SAS", "HEA", "SRI" );
foreach my $int_type (@interfaces_types) {
  foreach my $interface_id ( keys %{ $conf_json->{$int_type} } ) {

    #  if ( exists $conf_json->{$int_type}{$interface}{label}                         ) { $data_in{POWER}{$interface}{label}            = $conf_json->{$int_type}{$interface}{label} };
    #  if ( exists $conf_json->{$int_type}{$interface}{REST_UUID}                         ) { $data_in{POWER}{$interface}{REST_UUID}            = $conf_json->{$int_type}{$interface}{REST_UUID} };
    #  if ( exists $conf_json->{$int_type}{$interface}{parent}                         ) { $data_in{POWER}{$interface}{parent}            = $conf_json->{$int_type}{$interface}{parent} };
    foreach my $metric ( keys %{ $conf_json->{$int_type}{$interface_id} } ) {
      if ( exists $conf_json->{$int_type}{$interface_id}{$metric} ) { $data_in{POWER}{$interface_id}{$metric} = $conf_json->{$int_type}{$interface_id}{$metric}; }
    }

    #check parent(s)
    my @parents;
    if ( exists $conf_json->{$int_type}{$interface_id}{parent} ) {
      my $parent = $conf_json->{$int_type}{$interface_id}{parent};
      if ($parent) { push @parents, $parent; }
    }
    if ( scalar @parents ) { $data_in{POWER}{$interface_id}{parents} = \@parents; }

    #create data_out format for SQLiteDataWrapper
    undef %data_out;
    foreach my $metric ( keys %{ $data_in{POWER}{$interface_id} } ) {
      if ( exists $data_in{POWER}{$interface_id}{$metric} ) { $data_out{$interface_id}{$metric} = $data_in{POWER}{$interface_id}{$metric}; }
    }

    #  if ( exists $data_in{POWER}{$interface_id}{label}                  ) { $data_out{$interface_id}{label}                   = $data_in{POWER}{$interface_id}{label}; }
    #  if ( exists $data_in{POWER}{$interface_id}{REST_UUID}           ) { $data_out{$interface_id}{REST_UUID}            = $data_in{POWER}{$interface_id}{REST_UUID}; }
    #  if ( exists $data_in{POWER}{$interface_id}{parents}                ) { $data_out{$interface_id}{parents}                 = $data_in{POWER}{$interface_id}{parents}; }

    my $params = { id => $object_id, subsys => "$int_type", data => \%data_out };
    print "power-json2db.pl : Inserting $params->{subsys} : $data_out{$interface_id}{label} into database\n";
    SQLiteDataWrapper::subsys2db($params);
  }
}

foreach my $hmc_uid ( keys %{ $conf_json->{hmcs} } ) {
  if ( exists $conf_json->{hmcs}{$hmc_uid}{label} ) { $data_in{POWER}{$hmc_uid}{label} = $conf_json->{hmcs}{$hmc_uid}{label}; }

  #check parent(s)
  my @parents;
  if ( exists $conf_json->{hmcs}{$hmc_uid}{parent} ) {
    my $parent = $conf_json->{hmcs}{$hmc_uid}{parent};
    if ($parent) { push @parents, $parent; }
  }

  if ( scalar @parents ) { $data_in{POWER}{$hmc_uid}{parents} = \@parents; }

  #create data_out format for SQLiteDataWrapper
  undef %data_out;
  foreach my $metric ( keys %{ $data_in{POWER}{$hmc_uid} } ) {
    if ( exists $data_in{POWER}{$hmc_uid}{$metric} ) { $data_out{$hmc_uid}{$metric} = $data_in{POWER}{$hmc_uid}{$metric}; }
  }
  foreach my $hmc_alias ( keys %hosts ) {
    my $hmc_host        = $hosts{$hmc_alias}{host};
    my $hmc_uid_of_host = PowerDataWrapper::md5_string( $hosts{$hmc_alias}{host} );
    push( @{ $data_out{$hmc_uid}{hostcfg} }, $hosts{$hmc_alias}{uuid} ) if ( $hmc_uid eq $hmc_uid_of_host );
  }
  my $params = { id => $object_id, subsys => 'HMC', data => \%data_out };
  print "power-json2db.pl : Inserting $params->{subsys} : $data_out{$hmc_uid}{label} into database\n";
  SQLiteDataWrapper::subsys2db($params);
}

# finish
