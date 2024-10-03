use 5.008_008;

use strict;
use warnings;

use Data::Dumper;
use JSON qw(decode_json encode_json);

use SQLiteDataWrapper;
use Db2DataWrapper;
use Xorux_lib;
use DatabasesWrapper;

defined $ENV{INPUTDIR} || warn('INPUTDIR undefined, probably have not read etc/lpar2rrd.cfg ') && exit 1;

# data file paths
my $inputdir = $ENV{INPUTDIR};

################################################################################

my %data_in;
my %data_out;
my $DEBUG = ( exists $ENV{DEBUG} ) ? $ENV{DEBUG} : 0;
my $arc   = Db2DataWrapper::get_arc();
if ( !$arc or $arc eq "0" ) {
  warn "couldn't get arc";
  exit;
}

my $object_hw_type = "DB2";
my $object_label   = "DB2";
my $object_id      = "DB2";

if (DatabasesWrapper::can_update("$inputdir/tmp/xormon_menu_$object_hw_type", 86400, 1)){
  SQLiteDataWrapper::deleteItems({ hw_type => $object_hw_type});
}

my $params = { id => $object_id, label => $object_label, hw_type => $object_hw_type };
SQLiteDataWrapper::object2db($params);

for my $hostname ( keys %{ $arc->{hostnames} } ) {
  if ( $arc->{hostnames}->{$hostname} ) {
    add_to_db( "HOST", $arc->{hostnames}->{$hostname}->{alias}, $hostname );
    my $prnt    = Db2DataWrapper::md5_string("$hostname-DB_FOLDERS");
    my @parents = ("$hostname");
    add_to_db( "DB_FOLDERS", "Members", $prnt, \@parents );
    @parents = ( "$prnt", "$hostname" );
    for my $uuid ( keys %{ $arc->{hostnames}->{$hostname}->{_dbs} } ) {
      add_to_db( "DB", "filler", $uuid, \@parents, $arc->{hostnames}->{$hostname}->{_dbs} );
    }
    @parents = ( "$hostname" );
    for my $uuid ( keys %{ $arc->{hostnames}->{$hostname}->{_bps} } ) {
      add_to_db( "BUFFERPOOL", $arc->{hostnames}->{$hostname}->{_bps}{$uuid}{label}, $uuid, \@parents, $arc->{hostnames}->{$hostname}->{_bps} );
    }
  }
}

sub add_to_db {
  my $subsys  = shift;
  my $label   = shift;
  my $uuid    = shift;
  my $parents = shift;
  my $_arc    = shift;
  my %data_out;
  $data_out{$uuid} = $_arc->{$uuid};
  if ( $subsys ne "DB" ) {
    $data_out{$uuid}{label} = $label;
  }
  if ( $subsys eq "HOST" ) {
    $data_out{$uuid}{hostcfg} = [$uuid];
  }
  if ( $subsys ne "HOST" ) {
    $data_out{$uuid}{parents} = $parents;
  }
  $params = { id => $object_id, subsys => "$subsys", data => \%data_out };
  print Dumper $params;
  SQLiteDataWrapper::subsys2db($params);
}
