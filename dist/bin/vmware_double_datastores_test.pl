# testing double datastores i menu.txt

##### RUN SCRIPT WITHOUT ARGUMENTS:
######
###### . /home/lpar2rrd/lpar2rrd/etc/lpar2rrd.cfg ; $PERL bin/vmware_double_datastores_test.pl
######

use strict;
use warnings;

use Data::Dumper;
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

################################################################################

my $DEBUG = ( exists $ENV{DEBUG} ) ? $ENV{DEBUG} : 0;

################################################################################

# load data source:
my $menu_file = "$tmpdir/menu_vmware.txt";
my @menu;

if ( !-f $menu_file ) {
  Xorux_lib::error( "file $menu_file does not exist " . __FILE__ . ":" . __LINE__ ) && exit 1;
}
open FH, "$menu_file" or error( "can't open $menu_file: $! " . __FILE__ . ":" . __LINE__ ) && exit 1;
@menu = <FH>;
close FH;

# print "menu file \n@menu\n";

# one datastore name & two different uuid (lpar=)

# menu_vmware.txt:Z:10.92.212.200:datastore_SGDDCCLD01:sgddccldent03_2n_22_2a22:/lpar2rrd-cgi/detail.sh?host=datastore_datacenter-21&server=vmware_affbbfaa-6915-4950-95de-19dd5e75e4d1_48&lpar=5efe8c3b-1ec206a4-0e91-48df370e8270&item=datastore&entitle=0&gui=1&none=none::SGDDCCLD::V:sgddccldent03_G934_2n_02/:group-p431316:
# menu_vmware.txt:Z:10.92.212.200:datastore_SGDDCCLD01:sgddccldent03_2n_22_2a22:/lpar2rrd-cgi/detail.sh?host=datastore_datacenter-21&server=vmware_affbbfaa-6915-4950-95de-19dd5e75e4d1_48&lpar=5bfe309f-4b564e3a-f3d4-f4034343b75c&item=datastore&entitle=0&gui=1&none=none::SGDDCCLD::V:sgddccldent03_G934_2n_02/:group-p431316:

my %datastore_names = ();
my $d_count         = 0;
for my $line (@menu) {
  next if $line !~ /^Z:/;
  $d_count++;
  ( undef, undef, undef, my $d_name, my $query_string ) = split( ":", $line, 5 );
  if ( exists $datastore_names{$d_name} ) {
    print "Double datastore: $d_name $query_string " . $datastore_names{$d_name} . "\n";
    next;
  }
  $datastore_names{$d_name} = $query_string;
}
print "Double datastore: $d_count datastores tested\n";

