# store LINUX data from menu.txt to SQLite database

##### RUN SCRIPT WITHOUT ARGUMENTS:
######
###### . /home/lpar2rrd/lpar2rrd/etc/lpar2rrd.cfg ; $PERL bin/linux_menu2db.pl
######

use strict;
use warnings;

use Data::Dumper;

# use JSON qw(decode_json encode_json);
use DBI;

use SQLiteDataWrapper;
use Xorux_lib;

defined $ENV{INPUTDIR} || Xorux_lib::error( " INPUTDIR undefined, probably have not read etc/lpar2rrd.cfg " . __FILE__ . ":" . __LINE__ ) && exit 1;

# data file paths
my $inputdir = $ENV{INPUTDIR};

my $basedir = $ENV{INPUTDIR};
my $wrkdir  = "$basedir/data";
my $tmpdir  = "$basedir/tmp";
if ( defined $ENV{TMPDIR_LPAR} ) {
  $tmpdir = $ENV{TMPDIR_LPAR};
}

#my $db_filepath         = "$inputdir/data/data.db";
#my $iostats_dir         = "$inputdir/data/power_iostats";
#my $metadata_file       = "$iostats_dir/conf.json";

################################################################################

my %data_in;
my %data_out;
my $DEBUG = ( exists $ENV{DEBUG} ) ? $ENV{DEBUG} : 0;

################################################################################

# load data source:
my $menu_file = "$tmpdir/menu.txt";
my @menu;

if ( !-f $menu_file ) {
  Xorux_lib::error( "file $menu_file does not exist " . __FILE__ . ":" . __LINE__ ) && exit 1;
}
open FH, "$menu_file" or error( "can't open $menu_file: $! " . __FILE__ . ":" . __LINE__ ) && exit 1;
@menu = <FH>;
close FH;

# print "menu file \n@menu\n";

################################################################################

# fill tables

# save %data_out
#
# my $params = {id => $st_serial, label => $st_name, hw_type => "VIRTUALIZATION TYPE"};
# SQLiteDataWrapper::object2db( $params );
# $params = { id => $st_serial, subsys => "DEVICE", data => $data_out{DEVICE} };
# SQLiteDataWrapper::subsys2db( $params );

# LPAR2RRD: LINUX assignment
# (TODO remove) object: hw_type => "LINUX", label => "LINUX_Systems", id => "DEADBEEF"
# params: id                    => "DEADBEEF", subsys => "(VCENTER|VM|CLUSTER|…)", data => $data_out{(VCENTER|VM|CLUSTER|…)}

my $object_hw_type = "LINUX";
my $object_label   = "LINUX_Systems";
my $object_id      = "LINUX";

my $params = { id => $object_id, label => $object_label, hw_type => $object_hw_type };
SQLiteDataWrapper::object2db($params);

########## prepare linux servers (VMs) from lines e.g. (if any)

# L:no_hmc:Linux:vm-jindra:vm-jindra:/lpar2rrd-cgi/detail.sh?host=no_hmc&server=Linux--unknown&lpar=vm-jindra&item=lpar&entitle=0&gui=1&none=none:::P:M
my @linuxes = grep { $_ =~ /^L:no_hmc:Linux:/ } @menu;

# print "\@linuxes @linuxes\n";
# exit;

my $linux_uuid;    # is name

foreach (@linuxes) {
  ( undef, undef, undef, $linux_uuid, undef ) = split( ':', $_ );

  #print "$linux_uuid\n";
  undef %data_out;
  $data_out{$linux_uuid} = { 'label' => $linux_uuid };

  $params = { id => $object_id, subsys => "SERVER", data => \%data_out };
  print "linux-menu2db.pl : _DB Inserting $params->{subsys} : $data_out{$linux_uuid}{label}\n";
  SQLiteDataWrapper::subsys2db($params);

}

