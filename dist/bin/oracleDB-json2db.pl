use 5.008_008;

use strict;
use warnings;

use Data::Dumper;
use JSON qw(decode_json encode_json);

use SQLiteDataWrapper;
use OracleDBDataWrapper;
use Xorux_lib;

defined $ENV{INPUTDIR} || warn( localtime() . ': INPUTDIR undefined, probably have not read etc/lpar2rrd.cfg ' . __FILE__ . ':' . __LINE__ ) && exit 1;

# data file paths
my $inputdir = $ENV{INPUTDIR};

my $odb_dir    = "$inputdir/data/OracleDB";
my $totals_dir = "$odb_dir/Totals";

#my $db_filepath         = "$inputdir/data/data.db";
#my $iostats_dir         = "$inputdir/data/XEN_iostats";
#my $metadata_file       = "$iostats_dir/conf.json";
#my $tmpdir              = "$inputdir/tmp";

################################################################################

my %data_in;
my %data_out;
my $DEBUG      = ( exists $ENV{DEBUG} ) ? $ENV{DEBUG} : 0;
my $arc        = OracleDBDataWrapper::get_arc();
my $groups     = OracleDBDataWrapper::get_groups("act");
my $groups_old = OracleDBDataWrapper::get_groups("old");
my %groups_pa;
if ( !$arc or $arc eq "0" ) {
  warn "couldn't get arc";
  exit;
}

if ( !$groups or $groups eq "0" ) {
  warn "couldn't get groups";
  exit;
}

my $object_hw_type = "ORACLEDB";
my $object_label   = "OracleDB";
my $object_id      = "ORACLEDB";

my $params = { id => $object_id, label => $object_label, hw_type => $object_hw_type };
SQLiteDataWrapper::object2db($params);

my $hostunq = OracleDBDataWrapper::md5_string("unqlhosts");
$data_out{$hostunq}{"label"} = "Hosts";
$params = { id => $object_id, subsys => "HOSTS", data => \%data_out };
SQLiteDataWrapper::subsys2db($params);
print Dumper $params;
undef %data_out;

if ( $groups_old and $groups_old ne "0" ) {
  for my $mgroup_o ( keys %{ $groups_old->{_mgroups} } ) {
    unless ( $mgroup_o eq "_OracleDB" ) {
      my $mgroup_md_o = OracleDBDataWrapper::md5_string($mgroup_o);
      my $ad          = "$mgroup_md_o" . "__DBTotal$mgroup_o";
      SQLiteDataWrapper::deleteItem( { uuid => $ad } );
    }
  }
}

for my $mgroup ( keys %{ $groups->{_mgroups} } ) {
  unless ( $mgroup eq "_OracleDB" ) {
    undef %data_out;
    my $mgroup_md = OracleDBDataWrapper::md5_string($mgroup);
    $data_out{ "$mgroup_md" . "__DBTotal$mgroup" }{"label"}       = "$mgroup";
    $data_out{ "$mgroup_md" . "__DBTotal$mgroup" }{"children"}[0] = "";
    $params                                                       = { id => $object_id, subsys => "ODB_FOLDER", data => \%data_out };
    SQLiteDataWrapper::subsys2db($params);
    print Dumper $params;
    for my $db ( keys %{ $groups->{_mgroups}->{$mgroup}->{_dbs} } ) {
      $groups_pa{$db}{mgroup} = $mgroup_md . "__DBTotal$mgroup";
      $groups_pa{$db}{label}  = "$mgroup";
    }
  }
}

Xorux_lib::write_json( "$totals_dir/groups_pa.json", \%groups_pa );

print "\n\n\n\n\n\n\n\n\n\n";
print Dumper \%groups_pa;

for my $uuid ( keys %{$arc} ) {
  if ( $arc->{$uuid}->{type} and $arc->{$uuid}->{type} eq "Items" ) {
    undef %data_out;
    $data_out{$uuid}             = $arc->{$uuid};
    $data_out{$uuid}{parents}[0] = $hostunq;
    $data_out{$uuid}{label}      = $data_out{$uuid}{host};
    $data_out{$uuid}{hostcfg}    = [$uuid];
    $params                      = { id => $object_id, subsys => "ITEMS", data => \%data_out };
    SQLiteDataWrapper::subsys2db($params);
    print Dumper $params;

  }
  elsif ( $arc->{$uuid}->{type} eq "Standalone" ) {
    undef %data_out;
    $data_out{$uuid} = $arc->{$uuid};
    my $cur_group = $groups_pa{ $data_out{$uuid}{alias} }{mgroup};
    $data_out{$uuid}{parents}[0] = "$cur_group";
    $data_out{$uuid}{label}      = $data_out{$uuid}{server};
    $data_out{$uuid}{hostcfg}    = [$uuid];
    $params                      = { id => $object_id, subsys => "STANDALONE", data => \%data_out };
    SQLiteDataWrapper::subsys2db($params);
    print Dumper $params;
  }
  elsif ( $arc->{$uuid}->{type} eq "RAC" ) {
    undef %data_out;
    $data_out{$uuid} = $arc->{$uuid};
    my $cur_group = $groups_pa{ $data_out{$uuid}{alias} }{mgroup};
    $data_out{$uuid}{parents}[0] = "$cur_group";

    #$data_out{$uuid}{parents}[1] = "$uuid";
    #$data_out{$uuid}{children}[0] = "$uuid-instances";
    $data_out{$uuid}{label}   = $data_out{$uuid}{server};
    $data_out{$uuid}{hostcfg} = [$uuid];
    $params                   = { id => $object_id, subsys => "RAC", data => \%data_out };
    SQLiteDataWrapper::subsys2db($params);
    print Dumper $params;
    undef %data_out;
    $data_out{ "$uuid" . "_gcache" }{"label"}    = "Global Cache";
    $data_out{ "$uuid" . "_gcache" }{parents}[0] = "$uuid";
    $data_out{ "$uuid" . "_gcache" }{parents}[1] = "$cur_group";
    $params                                      = { id => $object_id, subsys => "GLOBAL_CACHE", data => \%data_out };
    SQLiteDataWrapper::subsys2db($params);
    print Dumper $params;
    undef %data_out;
    $data_out{ "$uuid" . "_totals" }{"label"}    = "Totals";
    $data_out{ "$uuid" . "_totals" }{parents}[0] = "$uuid";
    $data_out{ "$uuid" . "_totals" }{parents}[1] = "$cur_group";
    $params                                      = { id => $object_id, subsys => "TOTAL", data => \%data_out };
    SQLiteDataWrapper::subsys2db($params);
    print Dumper $params;
    undef %data_out;

    foreach my $instance ( @{ $arc->{$uuid}->{children} } ) {
      undef %data_out;
      $data_out{$instance}             = $arc->{$instance};
      $data_out{$instance}{parents}[0] = "$uuid";
      $data_out{$instance}{parents}[1] = "$cur_group";

      #$data_out{$instance}{label} = $data_out{$instance}{host};
      $params = { id => $object_id, subsys => "INSTANCE", data => \%data_out };
      SQLiteDataWrapper::subsys2db($params);
      print Dumper $params;
    }
  }
  elsif ( $arc->{$uuid}->{type} eq "Multitenant" ) {
    undef %data_out;
    $data_out{$uuid} = $arc->{$uuid};
    my $cur_group = $groups_pa{ $data_out{$uuid}{alias} }{mgroup};
    $data_out{$uuid}{parents}[0] = "$cur_group";
    $data_out{$uuid}{label}      = $data_out{$uuid}{server};
    $data_out{$uuid}{hostcfg}    = [$uuid];
    $params                      = { id => $object_id, subsys => "MULTITENANT", data => \%data_out };
    SQLiteDataWrapper::subsys2db($params);
    print Dumper $params;
    undef %data_out;

    foreach my $instance ( @{ $arc->{$uuid}->{children} } ) {
      undef %data_out;
      $data_out{$instance}             = $arc->{$instance};
      $data_out{$instance}{parents}[0] = "$uuid";
      $data_out{$instance}{parents}[1] = "$cur_group";

      #$data_out{$instance}{label} = $data_out{$instance}{host};
      $params = { id => $object_id, subsys => "PDBS", data => \%data_out };
      SQLiteDataWrapper::subsys2db($params);
      print Dumper $params;
    }
  }
}

