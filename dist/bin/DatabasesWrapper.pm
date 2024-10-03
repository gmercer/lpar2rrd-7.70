package DatabasesWrapper;

use strict;
use warnings;

use Data::Dumper;


sub can_update {
  my $file = shift;
  my $time = shift;
  my $reset = shift;

  my $run_conf     = 0;
  my $checkup_file = $file;
  if ( -e $checkup_file ) {
    my $timediff = get_file_timediff($checkup_file);
    if ( $timediff >= $time - 100 ) {
      $run_conf = 1;
      if (defined $reset and $reset eq "1"){
        open my $fh, '>', $checkup_file;
        print $fh "1\n";
        close $fh;
      }
    }
  }
  elsif ( !-e $checkup_file ) {
    $run_conf = 1;
    if (defined $reset and $reset eq "1"){
      open my $fh, '>', $checkup_file;
      print $fh "1\n";
      close $fh;
    }
  }

  return $run_conf;
}

sub get_file_timediff {
  my $file = shift;

  my $modtime  = ( stat($file) )[9];
  my $timediff = time - $modtime;

  return $timediff;
}

1;
