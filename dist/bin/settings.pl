use strict;
use warnings;

use CGI::Carp qw(fatalsToBrowser);
use Data::Dumper;

#use File::Touch;

use JSON 'decode_json';
use Xorux_lib qw(parse_url_params);
use ACL;

my $basedir = $ENV{INPUTDIR} ||= "/home/lpar2rrd/lpar2rrd";

use constant {
  OK              => 'OK',
  ERROR           => 'ERROR',
  DISABLE_UI_FILE => '/etc/web_config/xormonUIonly'
};

my %result;
if ( $ENV{'REQUEST_METHOD'} && lc $ENV{'REQUEST_METHOD'} eq "put" ) {
  my $acl = ACL->new;
  if ( !$acl->isAdmin() ) {
    print "Status: 403 Forbidden\n\n";
    exit;
  }
  my $buffer;
  read STDIN, $buffer, $ENV{'CONTENT_LENGTH'};
  my $params = decode_json($buffer);
  if ( exists $params->{disableUI} ) {
    my $filePath = $basedir . DISABLE_UI_FILE;
    if ( $params->{disableUI} ) {

      #create file
      open my $fh, '>', $filePath;
      if ($fh) {
        $result{status} = OK;
        $result{detail} = 'UI disabled';
        close $fh;
      }
      else {
        $result{status} = ERROR;
        $result{detail} = 'Failed to disable UI';
      }
    }
    else {
      #delete file
      if ( -e $filePath ) {
        my $removed = unlink $filePath;
        if ( $removed == 1 ) {
          $result{status} = OK;
          $result{detail} = 'UI re-enabled';
        }
        else {
          $result{status} = ERROR;
          $result{detail} = 'Failed to enable UI';
        }
      }
      else {
        $result{status} = OK;
        $result{detail} = 'UI enabled already';
      }
    }
  }
  else {
    $result{status} = ERROR;
    $result{detail} = 'No settings set';
  }

}
else {
  $result{status} = ERROR;
  $result{detail} = "Unsupported method $ENV{'REQUEST_METHOD'}";
}
print "Content-type: application/json\n\n";
print JSON->new->utf8(0)->pretty()->encode( \%result );
