# test if all perl modules are in place
# Usage: . etc/lpar2rrd.cfg; $PERL bin/perl_modules_check.pl
#

use strict;
use warnings;
my $basedir = $ENV{INPUTDIR};
my $perl    = $ENV{PERL};
if ( !defined($perl) || $perl eq "" ) {
  $perl = "/usr/bin/perl";
}

my $arg = $ARGV[0];
if ( $#ARGV == -1 ) {
  $arg = "";
}

my @modules = ( "Date::Parse", "RRDp", "XML::Simple", "XML::SAX::PurePerl", "POSIX qw(strftime)", "File::Copy", "File::Compare", "File::Path", "File::Basename", "IO::Socket::INET", "MIME::Base64", "Env", "MIME::Base64", "Time::Local", "Getopt::Std", "Math::BigInt", "Socket", "LWP::UserAgent", "LWP::Protocol::http", "LWP::Protocol::https" );

my $error = 0;
foreach (@modules) {
  my $module     = $_;
  my $module_def = 1;
  eval "use $module; 1" or $module_def = 0;
  if ( !$module_def ) {
    if ( $error == 0 ) {
      print "\n";
    }
    if ( $module =~ m/LWP::Protocol::https/ ) {
      print "ERROR: Perl module has not been found: $module\n";
      print "       It is needed for VMware and IBM Power REST API support \n";
    }
    else {
      print "ERROR: Perl module has not been found: $module\n";
    }
    print "       Check its existence via: $perl -e \'use $module\'\n";
    $error++;
    next;
  }
  if ( $module =~ m/LWP::Protocol::https/ ) {
    my $version = `\$PERL -MLWP -e 'print "\$LWP::VERSION"'`;
    if ( defined $version ) {
      $version =~ s/^\s+|\s+$//g;
    }
    if ( !defined $version || $version !~ m/^6/ ) {
      print "Warning: LWP::Protocol::https should be version 6.x (act version: $version)\n";
      print "VMware and IBM Power REST API support might require that\n";
      print "Upgrade to 6.x: http://www.lpar2rrd.com/https.htm\n";
    }
  }
}

if ( $error > 0 ) {
  print "\n";
  print "Install all missing Perl modules and do this test again, check http://www.lpar2rrd.com/https.htm:\n";
  if ( !defined $basedir ) {
    print "Usage: . etc/lpar2rrd.cfg; \$PERL bin/perl_modules_check.pl \n";
    print "Looks like environment is not se up properly;  . etc/lpar2rrd.cfg\n\n";
  }
  else {
    print "Usage: cd <LPAR2RRD WORK DIR>; . etc/lpar2rrd.cfg; \$PERL bin/perl_modules_check.pl \n\n";
  }
  exit(1);
}
exit(0);
