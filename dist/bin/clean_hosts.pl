use 5.008_008;

use strict;
use warnings;

use JSON;
use Data::Dumper;
use HostCfg;
use JSON qw(decode_json encode_json);
use File::Copy;
use File::Temp qw/ tempfile/;




my $basedir    = $ENV{INPUTDIR} ||= "/home/lpar2rrd/lpar2rrd";
my $perl       = $ENV{PERL};
my $cfgdir     = "$basedir/etc/web_config";
my $realcfgdir = "$basedir/etc";
my $tmpdir     = "$basedir/tmp";
my $cfgbname   = "hosts";
my $cfgfile    = "$cfgdir/$cfgbname.json";
my $json       = JSON->new->utf8->pretty;

if (@ARGV) {
  my $hwtype = $ARGV[0];

  my %oldcfg = HostCfg::getConfig();


  #print Dumper $oldcfg;
  print $hwtype;
  delete $oldcfg{platforms}{$hwtype}{aliases};
  $oldcfg{platforms}{$hwtype}{aliases} = {};
  #print Dumper \%oldcfg;
  my ( $newcfg, $newcfgfilename ) = tempfile( UNLINK => 0 );
  my $pretty_json = $json->encode(\%oldcfg);
  print $newcfg $pretty_json;
  close $newcfg;
  my $json_c = eval { $json->decode($pretty_json) };
  if ($@){
    warn "Created file is corrupted, won't continue";
  }else{
    copy( $cfgfile, "$realcfgdir/.web_config/$cfgbname.json.cleanup.bak" );
    warn "Created backup of $cfgbname.json: '$basedir/etc/.web_config/$cfgbname.json-cleanup.bak'";
    unlink $cfgfile;
    move( $newcfgfilename, $cfgfile );
    chmod 0644, $cfgfile;
    warn "Added multiple Oracle DBs, writing new $cfgbname file...";
  }
}else{
  print "No arguments found, add hwtype";
}



