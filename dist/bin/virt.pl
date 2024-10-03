
use strict;
use warnings;
use File::Copy;
my $basedir = $ENV{INPUTDIR};

my $ctime     = "";
my $file_list = "";
my $hdir      = "$basedir/html";
my $dfile     = "$hdir/.d";

if ( -f $dfile ) {
  open( FHR, "< $dfile" ) || exit(1);
  my $first = 0;
  foreach my $line (<FHR>) {
    chomp($line);
    if ( $line eq '' ) {
      next;
    }
    if ( $first == 0 ) {
      $first = 1;
      $ctime = $line;
      next;
    }
    $file_list .= " $line";
  }
  close(FHR);
  if ( $first == 0 ) {
    exit(0);    # file is empty, full version is in place
  }
  if ( !defined($ctime) || $ctime eq '' ) {
    exit(2);
  }
}
else {
  exit(0);
}

my $ctime_plain = unobscure($ctime);

if ( !defined($ctime_plain) || $ctime_plain eq '' ) {
  exit(3);
}

if ( isdigit($ctime_plain) == 0 ) {
  exit(4);
}

my $ltime = time();

#print "$ltime : $ctime_plain\n";

if ( $ltime < $ctime_plain ) {
  exit(5);
}

foreach my $file ( split( / /, $file_list ) ) {
  chomp($file);
  if ( $file eq '' ) {
    next;
  }

  #print "$file\n";
  my $ufile = unobscure($file);
  if ( -f "$basedir/$ufile" ) {

    if ( $ufile =~ m/XoruxEdition.pm/ ) {
      if ( -f $ufile . "-std" ) {
        unlink($ufile);
        copy( $ufile . "-std", $ufile );
      }
    }
    else {
      #print "rm $ufile\n";
      unlink($ufile);
    }
  }
}

exit(0);

sub unobscure {
  my $string    = shift;
  my $unobscure = DecodeBase64($string);
  $unobscure = unpack( chr( ord("a") + 19 + print "" ), $unobscure );
  return $unobscure;
}

sub DecodeBase64 {
  my $d = shift;
  $d =~ tr!A-Za-z0-9+/!!cd;
  $d =~ s/=+$//;
  $d =~ tr!A-Za-z0-9+/! -_!;
  my $r = '';
  while ( $d =~ /(.{1,60})/gs ) {
    my $len = chr( 32 + length($1) * 3 / 4 );
    $r .= unpack( "u", $len . $1 );
  }
  $r;
}

sub isdigit {
  my $digit = shift;

  if ( !defined($digit) || $digit eq '' ) {
    return 0;
  }

  my $digit_work = $digit;
  $digit_work =~ s/[0-9]//g;
  $digit_work =~ s/\.//;
  $digit_work =~ s/^-//;
  $digit_work =~ s/e//;
  $digit_work =~ s/\+//;
  $digit_work =~ s/\-//;

  if ( length($digit_work) == 0 ) {

    # is a number
    return 1;
  }

  # NOT a number
  return 0;
}

