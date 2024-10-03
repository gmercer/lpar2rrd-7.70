
use strict;
use warnings;

#use Data::Dumper;
# use Custom;

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

if ($buffer) {
  my $retstr = "";
  if ( $ENV{'DEMO'} ) {
    $buffer =~ s/\\([^n])/\\\\\$1/g;
    $buffer =~ s/\n/\\n/g;
    $buffer =~ s/\\:/\\\\:/g;
    $retstr = "\"msg\" : \"<div>This demo site does not allow saving any changes you do in the admin GUI panel.<br />";
    $retstr .= "You can only see the preview of custom_groups.cfg to be written.</div>\", \"cfg\" : \"";
    print "{ \"status\" : \"success\", $retstr" . "$buffer\" }";
  }
  elsif ( open( CFG, ">$cfgdir/custom_groups.cfg" ) ) {
    print CFG $buffer;
    close CFG;
    $buffer =~ s/\\([^n])/\\\\\$1/g;
    $buffer =~ s/\n/\\n/g;
    $buffer =~ s/\\:/\\\\:/g;
    $retstr = "\"msg\" : \"<div>Custom Groups configuration file has been successfully saved!<br /><br />" . "Your changes will take effect after regular (cronned) load.sh.<br />" . "If you want to apply changes immediately, enter this command as the user running LPAR2RRD:<br />" . "<pre>$basedir/load.sh custom</pre><br />" . "Refresh the GUI in your web browser (Ctrl-F5) when above command finishes.</div>\", \"cfg\" : \"";
    print "{ \"status\" : \"success\", $retstr" . "$buffer\" }";
  }
  else {
    print "{ \"status\" : \"fail\", \"msg\" : \"<div>File $cfgdir/custom_groups.cfg cannot be written by webserver, check apache user permissions: <span style='color: red'>$!</span></div>\" }";
  }
}
else {
  print "{ \"status\" : \"fail\", \"msg\" : \"<div>No data was written to custom_groups.cfg</div>\" }";
}

sub urldecode {
  my $s = shift;
  $s =~ s/\%([A-Fa-f0-9]{2})/pack('C', hex($1))/seg;
  $s =~ s/\+/ /g;
  return $s;
}
