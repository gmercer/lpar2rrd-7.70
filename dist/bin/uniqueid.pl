use warnings;
use strict;
use Data::Dumper;
use File::Copy;
use File::Temp qw/ tempfile/;

use HostCfg;

my $basedir    = $ENV{INPUTDIR} ||= "/home/lpar2rrd/lpar2rrd";
my $cfgdir     = "$basedir/etc/web_config";
my $realcfgdir = "$basedir/etc";
my $cfgbname   = "hosts";
my $cfgfile    = "$cfgdir/$cfgbname.json";

use JSON qw(decode_json encode_json);

my $json = JSON->new->utf8->pretty;

my $oldcfg;
%{$oldcfg} = HostCfg::getConfig();

# print Dumper $oldcfg;
my $cfg_changed;    # flag for missing UUID

if ( $oldcfg->{platforms} ) {
  foreach my $class ( values %{ $oldcfg->{platforms} } ) {
    if ( $class->{aliases} ) {
      while ( my ( $key, $alias ) = each %{ $class->{aliases} } ) {
        if ( !$alias->{uuid} ) {
          warn "Host $key had no UUID, generated new one...";
          $alias->{uuid} = create_v4_uuid();
          $cfg_changed ||= 1;
        }
      }
    }
  }
}

if ($cfg_changed) {
  warn "Missing UUID(s) found, writing new $cfgbname file...";
  my ( $newcfg, $newcfgfilename ) = tempfile( UNLINK => 0 );
  print $newcfg $json->encode($oldcfg);
  close $newcfg;
  copy( $cfgfile, "$realcfgdir/.web_config/$cfgbname.json.missing_uuids.bak" );
  warn "Created backup of $cfgbname.json: '$basedir/etc/.web_config/$cfgbname.json.missing_uuids.bak'";
  unlink $cfgfile;
  move( $newcfgfilename, $cfgfile );
  chmod 0644, $cfgfile;
}

sub rand_32bit {
  my $v1 = int( rand(65536) ) % 65536;
  my $v2 = int( rand(65536) ) % 65536;
  return ( $v1 << 16 ) | $v2;
}

sub create_v4_uuid {
  my $uuid = '';
  for ( 1 .. 4 ) {
    $uuid .= pack 'I', rand_32bit();
  }
  substr $uuid, 6, 1, chr( ord( substr( $uuid, 6, 1 ) ) & 0x0f | 0x40 );
  return join '-',
    map { unpack 'H*', $_ }
    map { substr $uuid, 0, $_, '' } ( 4, 2, 2, 2, 6 );
}

