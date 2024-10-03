# SolarisDataWrapper.pm
# interface for accessing Solaris data:

package SolarisDataWrapper;

use strict;
use warnings;
use JSON;
use Data::Dumper;
use Xorux_lib qw(error read_json write_json);
use HostCfg;
use Digest::MD5 qw(md5 md5_hex md5_base64);

defined $ENV{INPUTDIR} || Xorux_lib::error( "INPUTDIR undefined, config etc/lpar2rrd.cfg probably has not been loaded " . __FILE__ . ":" . __LINE__ ) && exit 1;
my $basedir = $ENV{INPUTDIR};
my $tmpdir  = "$basedir/tmp";
if ( defined $ENV{TMPDIR_LPAR} ) {
  $tmpdir = $ENV{TMPDIR_LPAR};
}
my $wrkdir     = "$basedir/data";
my $solarisdir = "$wrkdir/Solaris--unknown/no_hmc";

my $acl;
my $use_sql = 0;

if ( defined $ENV{XORMON} && $ENV{XORMON} ) {
  $use_sql = 1;

  require ACLx;
  $acl = ACLx->new();

  sub isGranted {
    my $uuid = shift;
    return $acl->isGranted( { hw_type => 'SOLARIS', item_id => $uuid, match => 'granted' } );
  }
}

sub get_item_uid {
  my $params = shift;
  my $result;

  my $type          = $params->{type};
  my $sol_name      = $params->{label};
  my $sol_uuid_file = "$solarisdir/$sol_name/uuid.txt";
  my $uuid;
  if ( -f $sol_uuid_file ) {
    open( FH, "< $sol_uuid_file" ) || error( "Cannot read $sol_uuid_file: $!" . __FILE__ . ":" . __LINE__ ) && next;
    $uuid = <FH>;
    close(FH);
  }
  else {
    Xorux_lib::error( "SolarisDataWrapper does not exist uuid.txt for $sol_uuid_file " . __FILE__ . ":" . __LINE__ );
    return;
  }

  ( undef, $result ) = split( "/", $uuid );
  chomp $result;
  return $result;
}

# read tmp/menu.txt
sub read_menu {
  my $menu_ref = shift;
  open( FF, "<$tmpdir/menu.txt" ) || error( "can't open $tmpdir!menu.txt: $! :" . __FILE__ . ":" . __LINE__ ) && return 0;
  @$menu_ref = (<FF>);
  close(FF);
  return;
}

1;
