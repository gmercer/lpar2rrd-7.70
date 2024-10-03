
use warnings;
use strict;
my $time = time();
my $const;

# data updates for day ahead

while ( my $line = <> ) {
  chomp $line;
  if ( $line =~ /<lastupdate>/ ) {
    my $last_line = $line;
    $line =~ s/<lastupdate>//g;
    $line =~ s/<\/lastupdate>.*//g;
    $line =~ s/^\s+//g;
    if ( $line > $time ) {
      print $last_line . "\n";
      next;
    }
    else {
      $const = ( $time - $line ) + 86400;
      my $lastupdate = $const + $line;
      $last_line =~ s/<lastupdate>\d*<\/lastupdate>/<lastupdate>$lastupdate<\/lastupdate>/g;
      print "$last_line\n";
      next;
    }

  }
  if ( $line =~ /<row>/ && defined($const) ) {
    my @array_line = split( / /, $line );

    #$line =~ s/-->.*//g;
    #$line =~ s/.*\///g;
    #$line =~ s/^\s+//g;
    my $last_timestamp = $const + $array_line[5];
    $array_line[5] = $last_timestamp;
    print "@array_line\n";

  }
  else {
    print $line . "\n";
  }
}

