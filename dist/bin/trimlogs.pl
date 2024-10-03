
use strict;
use warnings;

my $basedir  = $ENV{INPUTDIR};
my $limit    = 10000;
my $logs_dir = "$basedir/logs";
my $tmp_dir  = "$basedir/tmp";

if ( !defined $basedir || $basedir eq '' ) {
  error( "Basedir is not defined!" . __FILE__ . ":" . __LINE__ ) && exit;
}
if ( defined $ENV{KEEPLOGLINES} && $ENV{KEEPLOGLINES} ne '' && isdigit( $ENV{KEEPLOGLINES} ) ) {
  $limit = $ENV{KEEPLOGLINES};
}

my $check_limit = $limit + ( $limit * 0.1 );

# only first run after the midnight
my $trimlogs_run = "$tmp_dir/trimlogs-run";
if ( !-f $trimlogs_run ) {
  `touch $trimlogs_run`;
}
else {
  my $run_time = ( stat("$trimlogs_run") )[9];
  ( my $sec, my $min, my $h, my $aday, my $m, my $y, my $wday, my $yday, my $isdst ) = localtime( time() );
  ( $sec, $min, $h, my $png_day, $m, $y, $wday, $yday, $isdst ) = localtime($run_time);
  if ( $aday == $png_day ) {
    print "trim logs      : not this time $aday == $png_day\n";
    exit(0);
  }
  else {
    `touch $trimlogs_run`;
  }
}
my $act_time = localtime();
print "trim logs      : start $act_time\n";

my @wcs = `wc -l $logs_dir/error.log* $logs_dir/output.log-* $logs_dir/vm_erased.log-* $logs_dir/daemon.out $logs_dir/.nfs* $logs_dir/prediction.out $logs_dir/topten.log $logs_dir/alert_history_service_now.log 2>/dev/null`;

# ./logs/.nfs00000001d107c4ca0000001e  --> when it is installed on NFS, daemon processes have problem with locking

foreach my $line (@wcs) {
  chomp $line;
  $line =~ s/^\s+//g;
  $line =~ s/\s+$//g;

  my ( $size, undef ) = split ' ', $line;
  my $filename = $line;
  $filename =~ s/^$size\s+//;
  my $filename_tmp = "$filename-tmp";

  if ( $filename eq "total" ) { next; }
  if ( !-f $filename )        { next; }

  # remove logs greater than 100 MB
  my $filesize = ( stat($filename) )[7];
  if ( $filesize > 104857600 ) {
    print "trim logs      : filesize $filesize is greater than 100 MB! Remove this file $filename\n";
    error("trim logs      : filesize $filesize is greater than 100 MB! Remove this file $filename\n");
    unlink($filename);
    next;
  }

  if ( $size > $check_limit ) {
    print "trim logs      : file $filename contains $size lines, it will be trimmed to $limit lines\n";
    error("trim logs      : file $filename contains $size lines, it will be trimmed to $limit lines");

    my $keepfrom = $size - $limit;

    open( IN,  "< $filename" )     || error( "Couldn't open file $filename $!" . __FILE__ . ":" . __LINE__ )     && next;
    open( OUT, "> $filename_tmp" ) || error( "Couldn't open file $filename_tmp $!" . __FILE__ . ":" . __LINE__ ) && next;

    my $count = 0;
    while ( my $iline = <IN> ) {
      chomp $iline;
      $count++;
      if ( $count > $keepfrom ) {
        print OUT "$iline\n";
      }
    }
    close IN;
    close OUT;

    # replace "rename", it will not work for daemon files which are open all the time
    open( IN,  "< $filename_tmp" ) || error( "Couldn't open file $filename_tmp $!" . __FILE__ . ":" . __LINE__ ) && next;
    open( OUT, "> $filename" )     || error( "Couldn't open file $filename $!" . __FILE__ . ":" . __LINE__ )     && next;

    $count = 0;
    while ( my $iline = <IN> ) {
      print OUT "$iline";
    }
    close IN;
    close OUT;

    unlink("$filename_tmp");

  }
}
$act_time = localtime();
print "trim logs      : end $act_time\n";
exit(0);

sub isdigit {
  my $digit = shift;

  if ( !defined $digit || $digit eq '' ) {
    return 0;
  }
  if ( $digit eq 'U' ) {
    return 1;
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

  #if (($digit * 1) eq $digit){
  #  # is a number
  #  return 1;
  #}

  # NOT a number
  return 0;
}

# error handling
sub error {
  my $text     = shift;
  my $act_time = localtime();
  chomp($text);

  #print "ERROR          : $text : $!\n";
  print STDERR "$act_time: $text : $!\n";

  #print "$act_time: $text : $!\n" if $DEBUG > 2;;

  return 1;
}

