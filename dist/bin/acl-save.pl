
use strict;
use warnings;

#use Data::Dumper;
use ACL;

print "Content-type: text/html\n\n";

my $buffer;
read( STDIN, $buffer, $ENV{'CONTENT_LENGTH'} );
$buffer = ( split( /=/, $buffer ) )[1];
$buffer = &urldecode($buffer);

my $basedir = $ENV{INPUTDIR};
$basedir ||= "..";

my $cfgdir = "$basedir/etc/web_config";

my $tmpdir = "$basedir/tmp";
if ( defined $ENV{TMPDIR_LPAR} ) {
  $tmpdir = $ENV{TMPDIR_LPAR};
}

my $acl = ACL->new;

my $isAdmin = ( $acl->isAdmin() );

if ($isAdmin) {
  if ($buffer) {
    if ( open( CFG, ">$cfgdir/acl.cfg" ) ) {
      print CFG $buffer;
      close CFG;
      print "ACL table successfully saved!\n\n";
      print $buffer;
    }
    else {
      if ( $ENV{'SERVER_NAME'} eq "demo.lpar2rrd.com" ) {
        print "This demo site does not allow saving any changes you do in the admin GUI panel.\n\n";
        print "Preview of $cfgdir/acl.cfg to be written:\n\n";
        print $buffer;
      }
      else {
        print "File $cfgdir/acl.cfg cannot be written by webserver, check apache user permissions: $!";
      }
    }
  }
  else {
    print "No data was written to acl.cfg";
  }
}
else {
  print "You are not permitted to save acl.cfg!";
}

sub urldecode {
  my $s = shift;
  $s =~ s/\%([A-Fa-f0-9]{2})/pack('C', hex($1))/seg;
  $s =~ s/\+/ /g;
  return $s;
}
