#!/usr/bin/perl
#
use strict;
use warnings;

# use feature qw(switch);

package RRule;
use Data::Dumper;
use POSIX ();

#
# Python-like modulo.
#
# The % operator in PHP returns the remainder of a / b, but differs from
# some other languages in that the result will have the same sign as the
# dividend. For example, -1 % 8 == -1, whereas in some other languages
# (such as Python) the result would be 7. This function emulates the more
# correct modulo behavior, which is useful for certain applications such as
# calculating an offset index in a circular list.
#
# @param int $a The dividend.
# @param int $b The divisor.
#
# @return int $a % $b where the result is between 0 and $b
#   (either 0 <= x < $b
#     or $b < x <= 0, depending on the sign of $b).
#
# @copyright 2006 The Closure Library Authors.
#/
sub pymod {
  my ( $m, $n ) = @_;

  my $x = $m % $n;

  # If $x and $b differ in sign, add $b to wrap the result to the correct sign.
  return ( $x * $n < 0 ) ? $x + $n : $x;
}

#
# Check is a year is a leap year.
#
# @param int $year The year to be checked.
# @return bool
#/
sub is_leap_year {
  my $year = shift;
  if ( $year % 4 != 0 ) {
    return 0;
  }
  if ( $year % 100 != 0 ) {
    return 1;
  }
  if ( $year % 400 != 0 ) {
    return 0;
  }
  return 1;
}

sub trim {
  my $s = shift;
  if ($s) {
    $s =~ s/^\s+|\s+$//g;
  }
  return $s;
}

#
# Implementation of RRULE as defined by RFC 5545 (iCalendar).
# Heavily based on python-dateutil/rrule
#
# Some useful terms to understand the algorithms and variables naming:
#
# - "yearday" = day of the year, from 0 to 365 (on leap years) - `date('z')`
# - "weekday" = day of the week (ISO-8601), from 1 (MO) to 7 (SU) - `date('N')`
# - "monthday" = day of the month, from 1 to 31
# - "wkst" = week start, the weekday (1 to 7) which is the first day of week.
#          Default is Monday (1). In some countries it's Sunday (7).
# - "weekno" = number of the week in the year (ISO-8601)
#
# CAREFUL with this bug: https:#bugs.php.net/bug.php?id=62476
#
# @link https:#tools.ietf.org/html/rfc5545
# @link https:#labix.org/python-dateutil
#/

use constant {
  SECONDLY => 7,
  MINUTELY => 6,
  HOURLY   => 5,
  DAILY    => 4,
  WEEKLY   => 3,
  MONTHLY  => 2,
  YEARLY   => 1,
};

use constant true  => 1;
use constant false => 0;

#
# Frequency names.
# Used internally for conversion but public if a reference list is needed.
#
# @todo should probably be protected, with a static getter instead to avoid
# unintended modification.
#
# @var array The name as the key
#/
our %frequencies = (
  'SECONDLY' => SECONDLY,
  'MINUTELY' => MINUTELY,
  'HOURLY'   => HOURLY,
  'DAILY'    => DAILY,
  'WEEKLY'   => WEEKLY,
  'MONTHLY'  => MONTHLY,
  'YEARLY'   => YEARLY
);

#
# Weekdays numbered from 1 (ISO-8601 or `date('N')`).
# Used internally but public if a reference list is needed.
#
# @todo should probably be protected, with a static getter instead
# to avoid unintended modification
#
# @var array The name as the key
#/
our %week_days = (
  'MO' => 1,
  'TU' => 2,
  'WE' => 3,
  'TH' => 4,
  'FR' => 5,
  'SA' => 6,
  'SU' => 7
);
our %rev_week_days = (
  1 => 'MO',
  2 => 'TU',
  3 => 'WE',
  4 => 'TH',
  5 => 'FR',
  6 => 'SA',
  7 => 'SU'
);

# parsed and validated values
# our ( $dtstart, $freq, $until, $count, $interval, $bysecond, $byminute, $byhour, $byweekday, $byweekday_nth, $bymonthday, $bymonthday_negative, $byyearday, $byweekno, $bymonth, $bysetpos, $wkst, $timeset );

# cache variables
# our $total;
# our $cache = ();

#######################################/
# Public interface

#
# The constructor needs the entire rule at once.
# There is no setter after the class has been instanciated,
# because in order to validate some BYXXX parts, we need to know
# the value of some other parts (FREQ or other BXXX parts).
#
# @param mixed $parts An assoc array of parts, or a RFC string.
#/
sub new {
  my $self = {};
  bless $self;
  my $this = shift;
  #
  # @var array original rule
  #/
  my $rule = {
    'DTSTART'    => undef,
    'FREQ'       => undef,
    'UNTIL'      => undef,
    'COUNT'      => undef,
    'INTERVAL'   => 1,
    'BYSECOND'   => undef,
    'BYMINUTE'   => undef,
    'BYHOUR'     => undef,
    'BYDAY'      => undef,
    'BYMONTHDAY' => undef,
    'BYYEARDAY'  => undef,
    'BYWEEKNO'   => undef,
    'BYMONTH'    => undef,
    'BYSETPOS'   => undef,
    'WKST'       => 'MO'
  };

  # our ( $dtstart, $freq, $until, $count, $interval, $bysecond, $byminute, $byhour, $byweekday, $byweekday_nth, $bymonthday, $bymonthday_negative, $byyearday, $byweekno, $bymonth, $bysetpos, $wkst, $timeset );
  my ( $freq, $until, $count, $interval, $bysecond, $byminute, $byhour, $byweekday, $byweekday_nth, $bymonthday, $bymonthday_negative, $byyearday, $byweekno, $bymonth, $bysetpos, $wkst, $timeset ) = ();

  # ( $this->{dtstart}, $this->{freq}, $this->{until}, $this->{count}, $this->{interval}, $this->{bysecond}, $this->{byminute}, $this->{byhour}, $this->{byweekday}, $this->{byweekday_nth}, $this->{bymonthday}, $this->{bymonthday_negative}, $this->{byyearday}, $this->{byweekno}, $this->{bymonth}, $this->{bysetpos}, $this->{wkst}, $this->{timeset} ) = ();
  my ( $rstr, $dtstart, $forcecount ) = @_;

  # warn  "$parts, $dtstart";
  my $parts;
  if ($rstr) {
    $rstr  = uc($rstr);
    $parts = parseRRule( $rstr, $dtstart );
  }
  else {
    warn( sprintf( 'The first argument must be a string or an array (%s provided)', gettype($parts) ) );
  }

  # validate extra parts
  ### my $unsupported = array_diff_key( $parts, $rule );
  ### if ( !empty($unsupported) ) {
  ###   InvalidArgumentException( 'Unsupported parameter(s): ' . implode( ',', array_keys($unsupported) ) );
  ### }

  ### $parts = array_merge( $this->rule, $parts );
  @$rule{ keys %$parts } = values %$parts;
  $parts                 = $rule;            # save original rule
                                             #print Dumper $parts;

  # WKST
  $parts->{'WKST'} = uc( $parts->{'WKST'} );
  if ( !exists $week_days{ $parts->{'WKST'} } ) {
    warn( 'The WKST rule part must be one of the following: ' . join( ', ', keys(%week_days) ) );
  }
  $wkst = $week_days{ $parts->{'WKST'} };

  # FREQ
  # warn $parts->{'FREQ'};
  if ( $parts->{'FREQ'} =~ /^-?\d+$/ ) {
    if ( $parts->{'FREQ'} > SECONDLY || $parts->{'FREQ'} < YEARLY ) {
      warn( 'The FREQ rule part must be one of the following: ' . join( ', ', keys(%frequencies) ) );
    }
    $freq = $parts->{'FREQ'};
  }
  else {    # string
    $parts->{'FREQ'} = uc( $parts->{'FREQ'} );
    if ( !exists $frequencies{ $parts->{'FREQ'} } ) {
      warn( 'The FREQ rule part must be one of the following: ' . join( ', ', keys(%frequencies) ) );
    }
    $freq = $frequencies{ $parts->{'FREQ'} };
  }

  # INTERVAL
  # if ( filter_var( $parts->{'INTERVAL'}, FILTER_VALIDATE_INT, ( 'options' => ( 'min_range' => 1 ) ) ) == false ) {
  $parts->{'INTERVAL'} = int $parts->{'INTERVAL'};
  if ( $parts->{'INTERVAL'} < 1 ) {
    warn('The INTERVAL rule part must be a positive integer (> 0)');
  }
  $interval = $parts->{'INTERVAL'};

  # DTSTART
  if ( $parts->{'DTSTART'} ) {
    eval {
      $dtstart = parseDate( $parts->{'DTSTART'} );
      1;
    } or do {
      warn('Failed to parse DTSTART ; it must be a valid date, timestamp or \DateTime object');
    }
  }
  else {
    $dtstart = time;
  }

  # UNTIL (optional)
  if ( $parts->{'UNTIL'} ) {
    eval {
      # warn $parts->{'UNTIL'};
      $until = parseDate( $parts->{'UNTIL'} );
      1;
    } or do {
      warn('Failed to parse UNTIL ; it must be a valid date, timestamp or \DateTime object');
    }
  }

  # COUNT (optional)
  if ( $parts->{'COUNT'} ) {
    $parts->{'COUNT'} = int $parts->{'COUNT'};

    # if ( filter_var( $parts->{'COUNT'}, FILTER_VALIDATE_INT, array( 'options' => array( 'min_range' => 1 ) ) ) == false ) {
    if ( $parts->{'COUNT'} < 1 ) {
      warn('COUNT must be a positive integer (> 0)');
    }
    $count = $parts->{'COUNT'};
  }

  if ( $until && $count ) {
    warn('The UNTIL or COUNT rule parts MUST NOT occur in the same rule');
  }

  # infer necessary BYXXX rules from DTSTART, if not provided
  if ( !( $parts->{'BYWEEKNO'} || $parts->{'BYYEARDAY'} || $parts->{'BYMONTHDAY'} || $parts->{'BYDAY'} ) ) {

    # warn "was here";
    for ($freq) {
      if (YEARLY) {
        if ( !$parts->{'BYMONTH'} ) {
          $parts->{'BYMONTH'} = date( "%m", $dtstart );
        }
        $parts->{'BYMONTHDAY'} = date( "%d", $dtstart );
      }
      elsif (MONTHLY) {
        $parts->{'BYMONTHDAY'} = date( "%d", $dtstart );
      }
      elsif (WEEKLY) {
        my $wday = date( "%w", $dtstart );
        $wday = ( $wday == 0 ? 7 : $wday );
        $parts->{'BYDAY'} = $rev_week_days{$wday};
      }
    }
  }

  # print Dumper $parts;

  # BYDAY (translated to byweekday for convenience)
  if ( $parts->{'BYDAY'} ) {

    # warn "was here";

    # if ( !is_array( $parts->{'BYDAY'} ) ) {
    my @bwd = split( ',', $parts->{'BYDAY'} );

    # ( $parts->{'BYDAY'} ) = split( ',', $parts->{'BYDAY'} );
    # print Dumper $parts->{'BYDAY'};

    # }
    $byweekday     = ();
    $byweekday_nth = ();
    foreach my $value (@bwd) {

      # warn $value;
      $value = trim( uc($value) );
      my @matches = ( $value =~ /^([+-]?[0-9]+)?([A-Z]{2})$/ );

      # print Dumper %week_days; # { $matches[2] };
      #if ( !$valid || ( not_empty( $matches[1] ) && ( $matches[1] == 0 || $matches[1] > 53 || $matches[1] < -53 ) ) || !array_key_exists( $matches[2], %week_days ) ) {
      if ( !@matches || ( $matches[0] && ( $matches[0] == 0 || $matches[0] > 53 || $matches[0] < -53 ) ) || !$week_days{ $matches[1] } ) {
        warn( 'Invalid BYDAY value: ' . $value );
      }

      if ( $matches[0] ) {
        push @{$byweekday_nth}, ( $week_days{ $matches[1] }, $matches[0] );
      }
      else {
        # warn $week_days{ $matches[1] };
        push @{$byweekday}, $week_days{ $matches[1] };
      }
    }

    if ($byweekday_nth) {
      if ( !( $freq == MONTHLY || $freq == YEARLY ) ) {
        warn('The BYDAY rule part MUST NOT be specified with a numeric value when the FREQ rule part is not set to MONTHLY or YEARLY.');
      }
      if ( $freq == YEARLY && $parts->{'BYWEEKNO'} ) {
        warn('The BYDAY rule part MUST NOT be specified with a numeric value with the FREQ rule part set to YEARLY when the BYWEEKNO rule part is specified.');
      }
    }
  }

  # The BYMONTHDAY rule part specifies a COMMA-separated list of days
  # of the month.  Valid values are 1 to 31 or -31 to -1.  For
  # example, -10 represents the tenth to the last day of the month.
  # The BYMONTHDAY rule part MUST NOT be specified when the FREQ rule
  # part is set to WEEKLY.
  if ( $parts->{'BYMONTHDAY'} ) {
    if ( $freq == WEEKLY ) {
      warn('The BYMONTHDAY rule part MUST NOT be specified when the FREQ rule part is set to WEEKLY.');
    }

    my @bmd = split( ',', $parts->{'BYMONTHDAY'} );

    $bymonthday          = ();
    $bymonthday_negative = ();
    foreach my $value (@bmd) {
      if ( $value < -31 || $value > 31 ) {
        warn( 'Invalid BYMONTHDAY value: ' . $value . ' (valid values are 1 to 31 or -31 to -1)' );
      }
      $value = int $value;
      if ( $value < 0 ) {
        push @{$bymonthday_negative}, $value;
      }
      else {
        push @{$bymonthday}, $value;
      }
    }

    # print Dumper $bymonthday_negative;
    if ($bymonthday) {
      @{$bymonthday} = sort { $a <=> $b } @{$bymonthday};
    }
    if ($bymonthday_negative) {
      @{$bymonthday_negative} = sort { $a <=> $b } @{$bymonthday_negative};
    }
  }

  if ( $parts->{'BYYEARDAY'} ) {
    if ( $freq == DAILY || $freq == WEEKLY || $freq == MONTHLY ) {
      warn('The BYYEARDAY rule part MUST NOT be specified when the FREQ rule part is set to DAILY, WEEKLY, or MONTHLY.');
    }
    my @tmp = split( ',', $parts->{'BYYEARDAY'} );

    $byyearday = ();
    foreach my $value (@tmp) {
      if ( $value < -366 || $value > 366 ) {
        warn( 'Invalid BYSETPOS value: ' . $value . ' (valid values are 1 to 366 or -366 to -1)' );
      }

      push @{$byyearday}, $value;
    }
    @{$byyearday} = sort { $a <=> $b } @{$byyearday};
  }

  # BYWEEKNO
  if ( $parts->{'BYWEEKNO'} ) {
    if ( $freq != YEARLY ) {
      warn('The BYWEEKNO rule part MUST NOT be used when the FREQ rule part is set to anything other than YEARLY.');
    }

    my @tmp = split( ',', $parts->{'BYWEEKNO'} );

    $byweekno = ();
    foreach my $value (@tmp) {
      if ( $value < -53 || $value > 53 ) {
        warn( 'Invalid BYWEEKNO value: ' . $value . ' (valid values are 1 to 53 or -53 to -1)' );
      }
      push @{$byweekno}, int $value;
    }
    @{$byweekno} = sort { $a <=> $b } @{$byweekno};
  }

  # The BYMONTH rule part specifies a COMMA-separated list of months
  # of the year.  Valid values are 1 to 12.
  # warn $parts->{'BYMONTH'};
  if ( $parts->{'BYMONTH'} ) {

    # if ( !is_array( $parts->{'BYMONTH'} ) ) {
    my @bm = split( ',', $parts->{'BYMONTH'} );

    # }

    $bymonth = ();
    foreach my $value (@bm) {
      if ( $value < 1 || $value > 12 ) {
        warn( 'Invalid BYMONTH value: ' . $value );
      }
      push @{$bymonth}, int $value;
    }

    # print Dumper $this->{bymonth};
    # print Dumper $parts->{BYMONTH};
    @{$bymonth} = sort { $a <=> $b } @{$bymonth};
  }

  if ( $parts->{'BYSETPOS'} ) {
    if ( !( $parts->{'BYWEEKNO'} || $parts->{'BYYEARDAY'} || $parts->{'BYMONTHDAY'} || $parts->{'BYDAY'} || $parts->{'BYMONTH'} || $parts->{'BYHOUR'} || $parts->{'BYMINUTE'} || $parts->{'BYSECOND'} ) ) {
      warn('The BYSETPOS rule part MUST only be used in conjunction with another BYxxx rule part.');
    }
    my @bsp = split( ',', $parts->{'BYSETPOS'} );

    # $parts->{'BYSETPOS'} = explode( ',', $parts->{'BYSETPOS'} );

    $bysetpos = ();
    foreach my $value (@bsp) {
      if ( $value < -366 || $value > 366 ) {
        warn( 'Invalid BYSETPOS value: ' . $value . ' (valid values are 1 to 366 or -366 to -1)' );
      }

      push @{$bysetpos}, int $value;
    }
    @{$bysetpos} = sort { $a <=> $b } @{$bysetpos};
  }

  # print Dumper $bysetpos;

  if ( $parts->{'BYHOUR'} ) {
    my @tmp = split( ',', $parts->{'BYHOUR'} );

    $byhour = ();
    foreach my $value (@tmp) {
      if ( $value < 0 || $value > 23 ) {
        warn( 'Invalid BYHOUR value: ' . $value );
      }
      push @{$byhour}, int $value;
    }

    @{$byhour} = sort { $a <=> $b } @{$byhour};
  }
  elsif ( $freq < HOURLY ) {
    push @{$byhour}, POSIX::strftime( "%H", localtime($dtstart) );
  }

  if ( $parts->{'BYMINUTE'} ) {
    my @tmp = split( ',', $parts->{'BYMINUTE'} );

    $byminute = ();
    foreach my $value (@tmp) {
      if ( $value < 0 || $value > 59 ) {
        warn( 'Invalid BYMINUTE value: ' . $value );
      }
      push @{$byminute}, int $value;
    }
    @{$byminute} = sort { $a <=> $b } @{$byminute};
  }
  elsif ( $freq < MINUTELY ) {
    push @{$byminute}, POSIX::strftime( "%M", localtime($dtstart) );
  }

  if ( $parts->{'BYSECOND'} ) {
    my @tmp = split( ',', $parts->{'BYSECOND'} );

    $bysecond = ();
    foreach my $value (@tmp) {

      # yes, "60" is a valid value, in (very rare) cases on leap seconds
      #  December 31, 2005 23:59:60 UTC is a valid date...
      # so is 2012-06-30T23:59:60UTC
      if ( $value < 0 || $value > 60 ) {
        warn( 'Invalid BYSECOND value: ' . $value );
      }
      push @{$bysecond}, int $value;
    }
    @{$bysecond} = sort { $a <=> $b } @{$bysecond};
  }
  elsif ( $freq < SECONDLY ) {
    push @{$bysecond}, int POSIX::strftime( "%S", localtime($dtstart) );

    # $this->bysecond = array( int $this->dtstart->format('s') );
  }

  $timeset = ();
  if ( $freq < HOURLY ) {

    # for frequencies DAILY, WEEKLY, MONTHLY AND YEARLY, we can build
    # an array of every time of the day at which there should be an
    # occurrence - default, if no BYHOUR/BYMINUTE/BYSECOND are provided
    # is only one time, and it's the DTSTART time. This is a cached version
    # if you will, since it'll never change at these frequencies
    foreach my $hour ( @{$byhour} ) {
      foreach my $minute ( @{$byminute} ) {
        foreach my $second ( @{$bysecond} ) {

          # warn ( $hour, $minute, $second );
          push @{$timeset}, ( $hour, $minute, $second );
        }
      }
    }
  }

  if ($forcecount) {
    $count = $forcecount;
  }

  # warn $count;
  # print Dumper $this->{bymonth};
  # parts               => $parts,
  my %parsed = (
    "dtstart"             => $dtstart,
    "freq"                => $freq,
    "until"               => $until,
    "count"               => $count,
    "interval"            => $interval,
    "bysecond"            => $bysecond,
    "byminute"            => $byminute,
    "byhour"              => $byhour,
    "byweekday"           => $byweekday,
    "byweekday_nth"       => $byweekday_nth,
    "bymonthday"          => $bymonthday,
    "bymonthday_negative" => $bymonthday_negative,
    "byyearday"           => $byyearday,
    "byweekno"            => $byweekno,
    "bymonth"             => $bymonth,
    "bysetpos"            => $bysetpos,
    "wkst"                => $wkst,
    "timeset"             => $timeset
  );

  return %parsed;
}

sub getOccurrences {
  my $this = shift;
  my ( $rrule, $start, $count ) = @_;
  my %rd = $this->new( $rrule, $start, $count );

  # print Dumper $example->{"rule"}, str2time($example->{"date"});
  # print Dumper \%rd;
  # print $rd;
  #my @dates = $rd->getOccurrences(10);
  my @dat = iterate( \%rd );

  # print Dumper \%rd;
  # print Dumper \@dat;
  return \@dat;
}

sub isThisTheDay {
  my $this  = shift;
  my $rrule = shift;
  my ( $sec, $min, $hour, $mday, $mon, $year, $wday, $yday, $isdst ) = localtime();
  my $tstart = POSIX::mktime( 0, 0, 0, $mday, $mon, $year, $wday, $yday, $isdst );
  my %rd     = $this->new( $rrule, $tstart, 1 );
  if ( $rd{freq} == 4 ) {
    return 1;    # daily freqency: allways true for now
  }
  my @dates = iterate( \%rd );
  if ( @dates && abs( $dates[0] - $tstart ) <= 3600 ) {
    return 1;
  }
  else {
    if ( $dates[0] ) {

      #warn "Next occurrence: " . POSIX::strftime( "%a, %F %T", localtime($dates[0]) );
    }
    else {
      #warn "No future occurrence found";
    }
    return 0;
  }
}

#######################################/
# Internal methods
# where all the magic happens

#
# Convert any date into a DateTime object.
#
# @param mixed $date
# @return \DateTime
#
# @throws \InvalidArgumentException on error
#/
sub parseDate {
  my $date = shift;

  # DateTimeInterface is only on PHP 5.5+, and includes DateTimeImmutable
  # if ( !$date instanceof DateTime && !$date instanceof DateTimeInterface ) {
  if ( $date =~ /^\d+$/ ) {

    # $date = DateTime::createFromFormat( 'U', $date );
    # $date->setTimezone( DateTimeZone('UTC') );    # default is +00:00 (see issue #15)
  }
  else {
    warn("Failed to parse the date");
  }
  return $date;
}

#
# Return an array of days of the year (numbered from 0 to 365)
# of the current timeframe (year, month, week, day) containing the current date
#
# @param int $year
# @param int $month
# @param int $day
# @param array $masks
# @return array
#/
sub getDaySet {
  my $this = shift;
  my ( $year, $month, $day, $masks ) = @_;

  # warn "$this->{freq}, $year, $month, $day";
  for ( $this->{freq} ) {
    if ( $frequencies{YEARLY} ) {
      return ( 0 .. ( $masks->{year_len} - 1 ) );
    }
    elsif ( $frequencies{MONTHLY} ) {

      warn "$this->{freq}, $year, $month, $day";

      # print Dumper $masks;
      my $start = $masks->{last_day_of_month}[ $month - 1 ];
      my $stop  = $masks->{last_day_of_month}[$month];

      #print Dumper $masks->{last_day_of_month};
      # warn "$start .. $stop";
      return ( $start .. ( $stop - 1 ) );
    }

    elsif ( $frequencies{WEEKLY} ) {

      # on first iteration, the first week will not be complete
      # we don't backtrack to the first day of the week, to avoid
      # crossing year boundary in reverse (i.e. if the week started
      # during the previous year), because that would generate
      # negative indexes (which would not work with the masks)
      my @set;

      # my $i = date( "%j", date_create( "${year}-${month}-${day}T00:00:00" ) ) - 1;
      my $i = date( "%j", POSIX::mktime( 0, 0, 0, $day, $month - 1, $year - 1900 ) );

      # warn $i;
      my $start = $i;
      for ( my $j = 0; $j < 7; $j++ ) {
        push @set, $i;
        $i += 1;

        # print Dumper $masks->{yearday_to_weekday};
        # if ($i > 140) {
        #   print Dumper $i, $masks->{yearday_to_weekday}[$i], $this->{wkst};
        #  }
        # die;
        if ( $masks->{yearday_to_weekday} && $masks->{yearday_to_weekday}[$i] == $this->{wkst} ) {
          last;
        }
      }
      return @set;
    }

    elsif ( $frequencies{DAILY} || $frequencies{HOURLY} || $frequencies{MINUTELY} || $frequencies{SECONDLY} ) {

      # my $i = int date( "%j", date_create( $year . '-' . $month . '-' . $day . 'T00:00:00' ) ) - 1;
      my $i = date( "%j", POSIX::mktime( 0, 0, 0, $day, $month - 1, $year - 1900 ) );
      return ($i);
    }
  }
}

#
# Calculate the yeardays corresponding to each Nth weekday
# (in BYDAY rule part).
#
# For example, in Jan 1998, in a MONTHLY interval, "1SU,-1SU" (first Sunday
# and last Sunday) would be transformed into [3=>true,24=>true] because
# the first Sunday of Jan 1998 is yearday 3 (counting from 0) and the
# last Sunday of Jan 1998 is yearday 24 (counting from 0).
#
# @param int $year
# @param int $month
# @param int $day
# @param array $masks
#
# @return null (modifies $mask parameter)
#/
sub buildNthWeekdayMask {
  my $this = shift;
  my ( $year, $month, $day, $masks ) = @_;
  $masks->{yearday_is_nth_weekday} = ();

  if ( $this->{byweekday_nth} ) {
    my @ranges;
    if ( $this->{freq} == YEARLY ) {
      if ( $this->{bymonth} ) {
        foreach my $bymonth ( @{ $this->{bymonth} } ) {
          push @ranges,
            [
            $masks->{last_day_of_month}[ $bymonth - 1 ],
            $masks->{last_day_of_month}[$bymonth] - 1
            ];
        }
      }
      else {
        push @ranges, [ 0, $masks->{year_len} - 1 ];
      }
    }
    elsif ( $this->{freq} == MONTHLY ) {
      push @ranges,
        [
        $masks->{last_day_of_month}[ $month - 1 ],
        $masks->{last_day_of_month}[$month] - 1
        ];
    }

    if (@ranges) {

      # print Dumper \@ranges;
      # print Dumper $this->{byweekday_nth};
      # die;

      # Weekly frequency won't get here, so we may not
      # care about cross-year weekly periods.
      foreach my $tmp (@ranges) {

        # print "TMP: " . Dumper $tmp;
        # die;
        my ( $first, $last ) = @{$tmp};

        # print Dumper "$first, $last";
        # die;
        foreach my $tmp1 ( ( $this->{byweekday_nth} ) ) {
          my ( $weekday, $nth ) = @{$tmp1};

          # print Dumper "$weekday, $nth";
          my $i;
          if ( $nth < 0 ) {
            $i = $last + ( $nth + 1 ) * 7;
            $i = $i - pymod( $masks->{yearday_to_weekday}[$i] - $weekday, 7 );
          }
          else {
            $i = $first + ( $nth - 1 ) * 7;
            $i = $i + ( 7 - $masks->{yearday_to_weekday}[$i] + $weekday ) % 7;
          }

          if ( $i >= $first && $i <= $last ) {
            $masks->{yearday_is_nth_weekday}[$i] = true;
          }
        }
      }
    }
  }
}

#
# Calculate the yeardays corresponding to the week number
# (in the WEEKNO rule part).
#
# Because weeks can cross year boundaries (that is, week #1 can start the
# previous year, and week 52/53 can continue till the next year), the
# algorithm is quite long.
#
# @param int $year
# @param int $month
# @param int $day
# @param array $masks
#
# @return null (modifies $mask)
#/
sub buildWeeknoMask {
  my $this = shift;
  my ( $year, $month, $day, $masks ) = @_;
  $masks->{yearday_is_in_weekno} = ();

  # calculate the index of the first wkst day of the year
  # 0 means the first day of the year is the wkst day (e.g. wkst is Monday and Jan 1st is a Monday)
  # n means there is n days before the first wkst day of the year.
  # if n >= 4, this is the first day of the year (even though it started the year before)
  my $first_wkst = ( 7 - $masks->{weekday_of_1st_yearday} + $this->{wkst} ) % 7;
  my ( $nb_days, $first_wkst_offset );
  if ( $first_wkst >= 4 ) {
    $first_wkst_offset = 0;

    # Number of days in the year, plus the days we got from last year.
    $nb_days = $masks->{year_len} + $masks->{weekday_of_1st_yearday} - $this->{wkst};

    # $nb_days = $masks->{year_len} + pymod($masks->{weekday_of_1st_yearday} - $this->wkst,7);
  }
  else {
    $first_wkst_offset = $first_wkst;

    # Number of days in the year, minus the days we left in last year.
    $nb_days = $masks->{year_len} - $first_wkst;
  }
  my $nb_weeks = int( $nb_days / 7 ) + int( ( $nb_days % 7 ) / 4 );

  # alright now we now when the first week starts
  # and the number of weeks of the year
  # so we can generate a map of every yearday that are in the weeks
  # specified in byweekno
  my $i;
  foreach my $n ( $this->{byweekno} ) {
    if ( $n < 0 ) {
      $n = $n + $nb_weeks + 1;
    }
    if ( $n <= 0 || $n > $nb_weeks ) {
      next;
    }
    if ( $n > 1 ) {

      # 7;
      if ( $first_wkst_offset != $first_wkst ) {

        # if week #1 started the previous year
        # realign the start of the week
        $i = $i - ( 7 - $first_wkst );
      }
    }
    else {
      $i = $first_wkst_offset;
    }

    # now add 7 days into the resultset, stopping either at 7 or
    # if we reach wkst before (in the case of short first week of year)
    for ( my $j = 0; $j < 7; $j++ ) {
      $masks->{yearday_is_in_weekno}[$i] = true;
      $i = $i + 1;
      if ( $masks->{yearday_to_weekday}[$i] == $this->{wkst} ) {
        last;
      }
    }
  }

  # if we asked for week #1, it's possible that the week #1 of next year
  # already started this year. Therefore we need to return also the matching
  # days of next year.
  if ( grep( /^1$/, $this->{byweekno} ) ) {

    # Check week number 1 of next year as well
    # TODO: Check -numweeks for next year.
    # 7;
    if ( $first_wkst_offset != $first_wkst ) {
      $i = $i - ( 7 - $first_wkst );
    }
    if ( $i < $masks->{year_len} ) {

      # If week starts in next year, we don't care about it.
      for ( my $j = 0; $j < 7; $j++ ) {
        $masks->{yearday_is_in_weekno}[$i] = true;
        $i += 1;
        if ( $masks->{yearday_to_weekday}[$i] == $this->{wkst} ) {
          last;
        }
      }
    }
  }

  if ($first_wkst_offset) {

    # Check last week number of last year as well.
    # If first_wkst_offset is 0, either the year started on week start,
    # or week number 1 got days from last year, so there are no
    # days from last year's last week number in this year.
    my $nb_weeks_last_year;
    if ( !grep( /^-1$/, $this->{byweekno} ) ) {
      my $wday = date( "%w", date_create( $year - 1 . "0101T000000" ) );

      # warn "WDAY: $wday";
      my $weekday_of_1st_yearday = $wday == 0 ? 7 : $wday;

      # my $weekday_of_1st_yearday      = date_create( ( $year - 1 ) . '-01-01 00:00:00' )->format('N');
      my $first_wkst_offset_last_year = ( 7 - $weekday_of_1st_yearday + $this->{wkst} ) % 7;
      my $last_year_len               = 365 + is_leap_year( $year - 1 );
      if ( $first_wkst_offset_last_year >= 4 ) {
        $first_wkst_offset_last_year = 0;
        $nb_weeks_last_year          = 52 + int( ( ( $last_year_len + ( $weekday_of_1st_yearday - $this->{wkst} ) % 7 ) % 7 ) / 4 );
      }
      else {
        $nb_weeks_last_year = 52 + int( ( ( $masks->{year_len} - $first_wkst_offset ) % 7 ) / 4 );
      }
    }
    else {
      $nb_weeks_last_year = -1;
    }

    if ( grep( /^$nb_weeks_last_year$/, $this->{byweekno} ) ) {
      for ( $i = 0; $i < $first_wkst_offset; $i++ ) {
        $masks->{yearday_is_in_weekno}[$i] = true;
      }
    }
  }
}

#
# Build an array of every time of the day that matches the BYXXX time
# criteria.
#
# It will only process $this->frequency at one time. So:
# - for HOURLY frequencies it builds the minutes and second of the given hour
# - for MINUTELY frequencies it builds the seconds of the given minute
# - for SECONDLY frequencies, it returns an array with one element
#
# This method is called everytime an increment of at least one hour is made.
#
# @param int $hour
# @param int $minute
# @param int $second
#
# @return array
#/
sub getTimeSet {
  my $this = shift;
  my ( $hour, $minute, $second ) = @_;

  # warn "$hour, $minute, $second";
  for ( $this->{freq} ) {
    if (/$frequencies{HOURLY}/) {
      my @set = ();
      foreach my $minute ( @{ $this->{byminute} } ) {
        foreach my $second ( @{ $this->{bysecond} } ) {

          # should we use another type?
          push @set, [ $hour, $minute, $second ];
        }
      }

      # sort ?
      return @set;
    }
    elsif (/$frequencies{MINUTELY}/) {
      my @set = ();
      foreach my $second ( @{ $this->{bysecond} } ) {

        # should we use another type?
        push @set, [ $hour, $minute, $second ];
      }

      # sort ?
      return @set;
    }
    elsif (/$frequencies{SECONDLY}/) {
      return [ $hour, $minute, $second ];
    }
    else {
      warn('getTimeSet called with an invalid frequency');
    }
  }
}

# This is the main method, where all of the magic happens.
#
# This method is a generator that works for PHP 5.3/5.4 (using static variables)
#
# The main idea is: a brute force made fast by not relying on date() functions
#
# There is one big loop that examines every interval of the given frequency
# (so every day, every week, every month or every year), constructs an
# array of all the yeardays of the interval (for daily frequencies, the array
# only has one element, for weekly 7, and so on), and then filters out any
# day that do no match BYXXX parts.
#
# The algorithm does not try to be "smart" in calculating the increment of
# the loop. That is, for a rule like "every day in January for 10 years"
# the algorithm will loop through every day of the year, each year, generating
# some 3650 iterations (+ some to account for the leap years).
# This is a bit counter-intuitive, as it is obvious that the loop could skip
# all the days in February till December since they are never going to match.
#
# Fortunately, this approach is still super fast because it doesn't rely
# on date() or DateTime functions, and instead does all the date operations
# manually, either arithmetically or using arrays as converters.
#
# Another quirk of this approach is that because the granularity is by day,
# higher frequencies (hourly, minutely and secondly) have to have
# their own special loops within the main loop, making the whole thing quite
# convoluted.
# Moreover, at such frequencies, the brute-force approach starts to really
# suck. For example, a rule like
# "Every minute, every Jan 1st between 10:00 and 10:59, for 10 years"
# requires a tremendous amount of useless iterations to jump from Jan 1st 10:59
# at year 1 to Jan 1st 10.00 at year 2.
#
# In order to make a "smart jump", we would have to have a way to determine
# the gap between the next occurence arithmetically. I think that would require
# to analyze each "BYXXX" rule part that "Limit" the set (see the RFC page 43)
# at the given frequency. For example, a YEARLY frequency doesn't need "smart
# jump" at all; MONTHLY and WEEKLY frequencies only need to check BYMONTH;
# DAILY frequency needs to check BYMONTH, BYMONTHDAY and BYDAY, and so on.
# The check probably has to be done in reverse order, e.g. for DAILY frequencies
# attempt to jump to the next weekday (BYDAY) or next monthday (BYMONTHDAY)
# (I don't know yet which one first), and then if that results in a change of
# month, attempt to jump to the next BYMONTH, and so on.
#
# @param $reset (bool) Whether to restart the iteration, or keep going
# @return \DateTime|null
#/
sub iterate {
  my $this  = shift;
  my $reset = shift;

  my ( $dtstart, $freq, $until, $count, $interval, $bysecond, $byminute, $byhour, $byweekday, $byweekday_nth, $bymonthday, $bymonthday_negative, $byyearday, $byweekno, $bymonth, $bysetpos, $wkst );
  our ( %REPEAT_CYCLES, @WEEKDAY_MASK, @MONTH_MASK_366, @MONTHDAY_MASK_366, @NEGATIVE_MONTHDAY_MASK_366, @LAST_DAY_OF_MONTH_366, @MONTH_MASK, @MONTHDAY_MASK, @NEGATIVE_MONTHDAY_MASK, @LAST_DAY_OF_MONTH );

  # for readability's sake, and because scope of the variables should be local anyway
  my $year;
  my $month;
  my $day;
  my $hour;
  my $minute;
  my $second;
  my @dayset;
  my $masks;
  my @timeset;
  my @cache;

  # my $dtstart;
  my $total = 0;
  my $use_cache;

  # stop once $total has reached COUNT
  if ( $this->{count} && $total >= $this->{count} ) {
    $this->{total} = $total;
    return @cache;
  }
  if ( !$dtstart ) {
    $dtstart = $this->{dtstart};
  }
  if ( !$year ) {
    if ( $this->{freq} == WEEKLY ) {

      # we align the start date to the WKST, so we can then
      # simply loop by adding +7 days. The Python lib does some
      # calculation magic at the end of the loop (when incrementing)
      # to realign on first pass.
      my $tmp = $dtstart;

      # $tmp->modify( '-' . pymod( $dtstart->format('N') - $this->wkst, 7 ) . 'days' );

      my $twd    = date( "%w", $dtstart ) == 0 ? 7 : date( "%w", $dtstart );
      my $modify = pymod( $twd - $this->{wkst}, 7 ) * 86400;

      # ( $year, $month, $day, $hour, $minute, $second ) = explode( ' ', $tmp->format('Y n j G i s') );
      ( $year, $month, $day, $hour, $minute, $second ) = split( ' ', date( '%Y %m %d %H %M %S', $tmp - $modify ) );
      undef($tmp);
    }
    else {
      ( $year, $month, $day, $hour, $minute, $second ) = split( ' ', date( '%Y %m %d %H %M %S', $dtstart ) );
    }

    # remove leading zeros
    $hour   = int $hour;
    $minute = int $minute;
    $second = int $second;
  }

  # warn "START: $year, $month, $day, $hour, $minute, $second";

  # we initialize the timeset
  if ( !@timeset ) {
    if ( $this->{freq} < HOURLY ) {

      # daily, weekly, monthly or yearly
      # we don't need to calculate a new timeset
      @timeset = $this->{timeset};
    }
    else {
      # initialize empty if it's not going to occurs on the first iteration
      if ( ( $this->{freq} >= HOURLY && $this->{byhour} && !grep( /^$hour$/, @{ $this->{byhour} } ) )
        || ( $this->{freq} >= MINUTELY && $this->{byminute} && !grep( /^$minute$/, @{ $this->{byminute} } ) )
        || ( $this->{freq} >= SECONDLY && $this->{bysecond} && !grep( /^$second$/, @{ $this->{bysecond} } ) ) )
      {
        @timeset = ();
      }
      else {
        @timeset = getTimeSet( $this, $hour, $minute, $second );
      }
    }
  }

  # print "TS: " . Dumper @timeset;

  # while (true) {
  my $max_cycles = $REPEAT_CYCLES{ $this->{freq} <= DAILY ? $this->{freq} : DAILY };

  # print Dumper $REPEAT_CYCLES;
  # print "DS: " .Dumper @dayset;
  # print "FREQ: " . Dumper $this->{freq};
  # warn "$max_cycles    $year, $month, $day, $hour, $minute, $second";
CYCLE: for ( my $i = 0; $i < $max_cycles; $i++ ) {

    # 1. get an array of all days in the next interval (day, month, week, etc.)
    # we filter out from this array all days that do not match the BYXXX conditions
    # to speed things up, we use days of the year (day numbers) instead of date
    # print "BDS: $year, $month, $day, $hour, $minute, $second\n";
    # print "DS: $i " .Dumper @dayset;
    # warn "Index: $i" if ( !@dayset );
    if ( !@dayset ) {

      # print "BEFORE: $year, $month, $day, $hour, $minute, $second\n";

      # rebuild the various masks and converters
      # these arrays will allow fast date operations
      # without relying on date() methods
      if ( !$masks || $masks->{year} ne $year || $masks->{month} ne $month ) {
        $masks = { 'year' => '', 'month' => '' };

        # only if year has changed
        if ( $masks->{year} ne $year ) {

          # warn "$month $year";
          $masks->{'leap_year'}     = is_leap_year($year);
          $masks->{'year_len'}      = 365 + int $masks->{'leap_year'};
          $masks->{'next_year_len'} = 365 + is_leap_year( $year + 1 );
          my $wday = date( "%w", date_create( $year . "0101T000000" ) );

          # warn "WDAY: $wday";
          $masks->{'weekday_of_1st_yearday'} = $wday == 0 ? 7 : $wday;
          my @spl = @WEEKDAY_MASK;

          # print Dumper @spl;
          @spl = splice( @spl, $masks->{'weekday_of_1st_yearday'} - 1 );
          $masks->{'yearday_to_weekday'} = \@spl;

          # $masks->{'yearday_to_weekday'} = @spl;

          # print Dumper $masks->{'weekday_of_1st_yearday'}, splice( \@WEEKDAY_MASK, $masks->{'weekday_of_1st_yearday'} - 1 );
          if ( $masks->{'leap_year'} ) {
            $masks->{'yearday_to_month'}             = \@MONTH_MASK_366;
            $masks->{'yearday_to_monthday'}          = \@MONTHDAY_MASK_366;
            $masks->{'yearday_to_monthday_negative'} = \@NEGATIVE_MONTHDAY_MASK_366;
            $masks->{'last_day_of_month'}            = \@LAST_DAY_OF_MONTH_366;
          }
          else {
            $masks->{'yearday_to_month'}             = \@MONTH_MASK;
            $masks->{'yearday_to_monthday'}          = \@MONTHDAY_MASK;
            $masks->{'yearday_to_monthday_negative'} = \@NEGATIVE_MONTHDAY_MASK;
            $masks->{'last_day_of_month'}            = \@LAST_DAY_OF_MONTH;
          }
          if ( $this->{byweekno} ) {
            buildWeeknoMask( $this, $year, $month, $day, $masks );
          }
        }

        # everytime month or year changes
        if ( $this->{byweekday_nth} ) {
          buildNthWeekdayMask( $this, $year, $month, $day, $masks );
        }
        $masks->{year}  = $year;
        $masks->{month} = $month;
      }

      # print Dumper $masks->{'yearday_to_weekday'};

      # calculate the current set
      # warn "AFTER: $year, $month, $day";
      @dayset = getDaySet( $this, $year, $month, $day, $masks );

      #if ($month == 5) {
      #print "DAYSET: " . Dumper \@dayset;
      ## die ;
      #}

      my @filtered_set;

      # rules
      foreach my $yearday (@dayset) {

        # if ($yearday == 145 ) {
        # warn "BEF Y YD: $year $yearday";
        # print "DAYSET: " . Dumper \@dayset;
        # }
        # warn "Y YD: $year $yearday";

        # print "BM: " . Dumper $this->{bymonth};
        # warn "$masks->{'yearday_to_month'}[$yearday]";
        if ( $this->{bymonth} && !grep( /^$masks->{'yearday_to_month'}[$yearday]$/, @{ $this->{bymonth} } ) ) {

          next;
        }

        if ( $this->{byweekno} && !$masks->{'yearday_is_in_weekno'}[$yearday] ) {
          next;
        }

        if ( $this->{byyearday} ) {
          if ( $yearday < $masks->{'year_len'} ) {

            # if ( !in_array( $yearday + 1, $this->{byyearday} ) && !in_array( -$masks->{'year_len'} + $yearday, $this->{byyearday} ) ) {
            my $yearday1 = $yearday + 1;
            my $tmask    = -$masks->{'year_len'} + $yearday;
            if ( !grep( /^$yearday1$/, @{ $this->{byyearday} } ) && !grep( /^$tmask$/, @{ $this->{byyearday} } ) ) {
              next;
            }
          }
          else {    # if ( ($yearday >= $masks->{year_len}
            if ( !in_array( $yearday + 1 - $masks->{'year_len'}, $this->{byyearday} ) && !in_array( -$masks->{'next_year_len'} + $yearday - $masks->{'year_len'}, $this->{byyearday} ) ) {
              next;
            }
          }
        }

        if (
          ( $this->{bymonthday} || $this->{bymonthday_negative} )

          # && !in_array( $masks->{'yearday_to_monthday'}[$yearday],          $this->{bymonthday} )
          # && !in_array( $masks->{'yearday_to_monthday_negative'}[$yearday], $this->{bymonthday_negative} ) )
          && !grep( /^$masks->{'yearday_to_monthday'}[$yearday]$/,          @{ $this->{bymonthday} } )
          && !grep( /^$masks->{'yearday_to_monthday_negative'}[$yearday]$/, @{ $this->{bymonthday_negative} } )
          )
        {
          next;
        }

        # print "yearday_to_weekday: " . Dumper ($masks->{'yearday_to_weekday'});
        # die;

        if ( ( $this->{byweekday} || $this->{byweekday_nth} )
          && !grep( /^$masks->{'yearday_to_weekday'}[$yearday]$/, @{ $this->{byweekday} } )
          && !$masks->{yearday_is_nth_weekday}[$yearday] )

          #  && ( $this->{byweekday} && $masks->{'yearday_to_weekday'} && ! grep( /^$masks->{'yearday_to_weekday'}[$yearday]$/, @{ $this->{byweekday} } ) )
          #  && ( $this->{byweekday_nth} && !$masks->{yearday_is_nth_weekday}[$yearday] ) )
        {
          # print "BM: " . Dumper $this->{byweekday};
          # die;
          # warn "Y YD: $year $yearday";
          # warn "NEXT BMD Y YD: $year $yearday";
          next;
        }

        # warn "here 1";

        # warn "AFT Y YD: $year $yearday";
        push @filtered_set, $yearday;
      }

      # warn scalar @filtered_set;
      @dayset = @filtered_set;

      # if BYSETPOS is set, we need to expand the timeset to filter by pos
      # so we make a special loop to return while generating
      if ( $this->{bysetpos} && @timeset ) {

        my %filtered_hash;
        foreach my $pos ( @{ $this->{bysetpos} } ) {

          # warn $pos;
          my $n = scalar(@timeset);
          if ( $pos < 0 ) {

            # count($dayset) + $pos;
          }
          else {
            $pos -= 1;
          }

          my $div = int( $pos / $n );    # daypos
          my $mod = $pos % $n;           # timepos
                                         # warn "$div, $mod";
          if ( exists $dayset[$div] && exists $timeset[$mod] ) {
            my $yearday = $dayset[$div];
            my @time    = @{ $timeset[$mod] };

            # print "TIMESET: " . Dumper @time;

            # used as array key to ensure uniqueness
            # warn "$year . ':' . $yearday . ':' . $time[0] . ':' . $time[1] . ':' . $time[2]";
            my $tmp = $year . ':' . $yearday . ':' . $time[0] . ':' . $time[1] . ':' . $time[2];
            if ( !$filtered_hash{$tmp} ) {

              # my $occurrence = $this->createFromFormat( 'Y z', "$year $yearday" );
              # $occurrence->setTime( $time[0], $time[1], $time[2] );
              my $occurrence = POSIX::mktime( $time[2], $time[1], $time[0], $yearday + 1, 0, $year - 1900 );
              $filtered_hash{$tmp} = $occurrence;
            }
          }
        }

        # print "HASH " . Dumper \%filtered_hash;

        @filtered_set = values %filtered_hash;
        @dayset       = sort @filtered_set;
      }
    }

    # print "DAYSET: " . Dumper \@dayset;

    # 2. loop, generate a valid date, and return the result (fake "yield")
    # at the same time, we check the end condition and return null if
    # we need to stop
    if ( $this->{bysetpos} && @timeset ) {
      foreach my $occurrence (@dayset) {

        # consider end conditions
        if ( $this->{until} && ( $occurrence > $this->{until} ) ) {
          $this->{total} = $total;    # save total for count() cache
          last CYCLE;
        }

        if ( $occurrence >= $dtstart ) {    # ignore occurrences before DTSTART
          $total += 1;
          push @cache, $occurrence;
          if ( $this->{count} && ( $total >= $this->{count} ) ) {
            last CYCLE;
          }

          #if ( scalar $this->{cache} >= $this->{count} ) {
          #return;
          #}

          # return; # $occurrence;         # yield
        }
      }
    }
    else {
      # print "FILTERED: " . Dumper \@filtered_set;
      # normal loop, without BYSETPOS
      foreach my $yearday (@dayset) {

        #print "DAYSET: " . Dumper \@dayset;
        # my $occurrence = createFromFormat( 'Y z', "$year $yearday" );

        # warn "$year $yearday";
        # push @{ $this->{cache} }, $occurrence;

        foreach my $time (@timeset) {

          # $occurrence->setTime( $time[0], $time[1], $time[2] );
          my $occurrence = POSIX::mktime( @$time[2], @$time[1], @$time[0], $yearday + 1, 0, $year - 1900 );

          # print "  " . POSIX::strftime( "%a, %F %T", localtime($occurrence) ) . "\n";

          # consider end conditions
          if ( $this->{until} && ( $occurrence > $this->{until} ) ) {
            $this->{total} = $total;    # save total for count() cache
            last CYCLE;
          }

          # next($timeset);
          if ( $occurrence >= $dtstart ) {    # ignore occurrences before DTSTART
                                              # warn $this->{count};
            $total += 1;
            push @cache, $occurrence;
            if ( $this->{count} && ( $total >= $this->{count} ) ) {
              last CYCLE;
            }

            # return $occurrence;         # yield
            # return;
          }
        }

        #reset($timeset);
        #next($dayset);
      }
    }

    # 3. we reset the loop to the next interval
    my $days_increment = 0;
    for ( $this->{freq} ) {
      if (/$frequencies{YEARLY}/) {

        # we do not care about $month or $day not existing,
        # they are not used in yearly frequency
        $year += $this->{interval};
      }
      elsif (/$frequencies{MONTHLY}/) {

        # we do not care about the day of the month not existing
        # it is not used in monthly frequency
        $month = $month + $this->{interval};
        if ( $month > 12 ) {
          my $div = int( $month / 12 );
          my $mod = $month % 12;
          $month = $mod;
          $year  = $year + $div;
          if ( $month == 0 ) {
            $month = 12;
            $year  = $year - 1;
          }
        }
      }
      elsif (/$frequencies{WEEKLY}/) {
        $days_increment = $this->{interval} * 7;
      }
      elsif (/$frequencies{DAILY}/) {
        $days_increment = $this->{interval};
      }

      # For the time frequencies, things are a little bit different.
      # We could just add "$this->interval" hours, minutes or seconds
      # to the current time, and go through the main loop again,
      # but since the frequencies are so high and needs to much iteration
      # it's actually a bit faster to have custom loops and only
      # call the DateTime method at the very end.

      elsif (/$frequencies{HOURLY}/) {
        if ( !@dayset ) {

          # an empty set means that this day has been filtered out
          # by one of the BYXXX rule. So there is no need to
          # examine it any further, we know nothing is going to
          # occur anyway.
          # so we jump to one iteration right before next day
          # $this->interval;
        }

        my $found = false;
        my $hour  = 0;
        for ( my $j = 0; $j < $REPEAT_CYCLES{ HOURLY() }; $j++ ) {
          $hour += $this->{interval};
          my $div = int( $hour / 24 );
          my $mod = $hour % 24;
          if ($div) {
            $hour = $mod;
            $days_increment += $div;
          }
          if ( !$this->{byhour} || grep( /^$hour$/, @{ $this->{byhour} } ) ) {
            $found = true;
            last;
          }
        }

        if ( !$found ) {
          $this->{total} = $total;    # save total for count cache
          last CYCLE;                 # stop the iterator
        }

        @timeset = getTimeSet( $this, $hour, $minute, $second );
      }
      elsif (/$frequencies{MINUTELY}/) {
        if ( !@dayset ) {

          # $this->interval;
        }

        my $found = 0;
        for ( my $j = 0; $j < $REPEAT_CYCLES{ MINUTELY() }; $j++ ) {
          $minute += $this->{interval};
          my $div = int( $minute / 60 );
          my $mod = $minute % 60;
          if ($div) {
            $minute = $mod;
            $hour += $div;
            $div = int( $hour / 24 );
            $mod = $hour % 24;
            if ($div) {
              $hour = $mod;
              $days_increment += $div;
            }
          }
          if ( ( !$this->{byhour} || grep( /^$hour$/, @{ $this->{byhour} } ) )
            && ( !$this->{byminute} || grep( /^$minute$/, @{ $this->{byminute} } ) ) )
          {
            $found = 1;
            last;
          }
        }

        if ( !$found ) {
          $this->{total} = $total;    # save total for count cache
          return undef;               # stop the iterator
        }

        @timeset = getTimeSet( $this, $hour, $minute, $second );
      }
      elsif (/$frequencies{SECONDLY}/) {
        if ( !@dayset ) {

          # $this->interval;
        }

        my $found  = 0;
        my $second = 0;
        for ( my $j = 0; $j < $REPEAT_CYCLES{SECONDLY}; $j++ ) {
          $second += $this->{interval};
          my $div = int( $second / 60 );
          my $mod = $second % 60;
          if ($div) {
            $second = $mod;
            $minute += $div;
            $div = int( $minute / 60 );
            $mod = $minute % 60;
            if ($div) {
              $minute = $mod;
              $hour += $div;
              $div = int( $hour / 24 );
              $mod = $hour % 24;
              if ($div) {
                $hour = $mod;
                $days_increment += $div;
              }
            }
          }
          if ( ( !$this->{byhour} || in_array( $hour, $this->{byhour} ) )
            && ( !$this->{byminute} || in_array( $minute, $this->{byminute} ) )
            && ( !$this->{bysecond} || in_array( $second, $this->{bysecond} ) ) )
          {
            $found = 1;
            last;
          }
        }

        if ( !$found ) {
          $this->{total} = $total;    # save total for count cache
          return;                     # stop the iterator
        }

        @timeset = ( getTimeSet( $this, $hour, $minute, $second ) );
      }
    }

    # print "GTS: " . Dumper \@timeset;

    # here we take a little shortcut from the Python version, by using DateTime
    if ($days_increment) {

      # warn "BEF: $day, $month, $year";
      my $incr = POSIX::mktime( 0, 0, 0, $day + $days_increment, $month, $year );
      ( my $tsec, my $tmin, my $thour, $day, $month, $year ) = localtime($incr);

      # warn "AFT: $day, $month, $year";
      # $month += 1;
      # $year  += 1900;
      #( $year, $month, $day ) = explode( '-', date_create("$year-$month-$day")->modify("+ $days_increment days")->format('Y-n-j') );
      #( $year, $month, $day ) = explode( '-', date_create("$year-$month-$day")->modify("+ $days_increment days")->format('Y-n-j') );
    }

    undef @dayset;    # reset the loop
    if ( $this->{count} && $total >= $this->{count} ) {
      last CYCLE;
    }
  }

  $this->{total} = $total;    # save total for count cache
  return sort @cache;
}

#######################################/
# constants
# Every mask is 7 days longer to handle cross-year weekly periods.

#
# @var array
#/
our @MONTH_MASK = (
  1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1,
  2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2,
  3,  3,  3,  3,  3,  3,  3,  3,  3,  3,  3,  3,  3,  3,  3,  3,  3,  3,  3,  3,  3,  3,  3,  3,  3,  3,  3,  3,  3,  3, 3,
  4,  4,  4,  4,  4,  4,  4,  4,  4,  4,  4,  4,  4,  4,  4,  4,  4,  4,  4,  4,  4,  4,  4,  4,  4,  4,  4,  4,  4,  4,
  5,  5,  5,  5,  5,  5,  5,  5,  5,  5,  5,  5,  5,  5,  5,  5,  5,  5,  5,  5,  5,  5,  5,  5,  5,  5,  5,  5,  5,  5, 5,
  6,  6,  6,  6,  6,  6,  6,  6,  6,  6,  6,  6,  6,  6,  6,  6,  6,  6,  6,  6,  6,  6,  6,  6,  6,  6,  6,  6,  6,  6,
  7,  7,  7,  7,  7,  7,  7,  7,  7,  7,  7,  7,  7,  7,  7,  7,  7,  7,  7,  7,  7,  7,  7,  7,  7,  7,  7,  7,  7,  7, 7,
  8,  8,  8,  8,  8,  8,  8,  8,  8,  8,  8,  8,  8,  8,  8,  8,  8,  8,  8,  8,  8,  8,  8,  8,  8,  8,  8,  8,  8,  8, 8,
  9,  9,  9,  9,  9,  9,  9,  9,  9,  9,  9,  9,  9,  9,  9,  9,  9,  9,  9,  9,  9,  9,  9,  9,  9,  9,  9,  9,  9,  9,
  10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10,
  11, 11, 11, 11, 11, 11, 11, 11, 11, 11, 11, 11, 11, 11, 11, 11, 11, 11, 11, 11, 11, 11, 11, 11, 11, 11, 11, 11, 11, 11,
  12, 12, 12, 12, 12, 12, 12, 12, 12, 12, 12, 12, 12, 12, 12, 12, 12, 12, 12, 12, 12, 12, 12, 12, 12, 12, 12, 12, 12, 12, 12,
  1, 1, 1, 1, 1, 1, 1
);

#
# @var array
#/
our @MONTH_MASK_366 = (
  1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1,
  2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2,
  3,  3,  3,  3,  3,  3,  3,  3,  3,  3,  3,  3,  3,  3,  3,  3,  3,  3,  3,  3,  3,  3,  3,  3,  3,  3,  3,  3,  3,  3, 3,
  4,  4,  4,  4,  4,  4,  4,  4,  4,  4,  4,  4,  4,  4,  4,  4,  4,  4,  4,  4,  4,  4,  4,  4,  4,  4,  4,  4,  4,  4,
  5,  5,  5,  5,  5,  5,  5,  5,  5,  5,  5,  5,  5,  5,  5,  5,  5,  5,  5,  5,  5,  5,  5,  5,  5,  5,  5,  5,  5,  5, 5,
  6,  6,  6,  6,  6,  6,  6,  6,  6,  6,  6,  6,  6,  6,  6,  6,  6,  6,  6,  6,  6,  6,  6,  6,  6,  6,  6,  6,  6,  6,
  7,  7,  7,  7,  7,  7,  7,  7,  7,  7,  7,  7,  7,  7,  7,  7,  7,  7,  7,  7,  7,  7,  7,  7,  7,  7,  7,  7,  7,  7, 7,
  8,  8,  8,  8,  8,  8,  8,  8,  8,  8,  8,  8,  8,  8,  8,  8,  8,  8,  8,  8,  8,  8,  8,  8,  8,  8,  8,  8,  8,  8, 8,
  9,  9,  9,  9,  9,  9,  9,  9,  9,  9,  9,  9,  9,  9,  9,  9,  9,  9,  9,  9,  9,  9,  9,  9,  9,  9,  9,  9,  9,  9,
  10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10,
  11, 11, 11, 11, 11, 11, 11, 11, 11, 11, 11, 11, 11, 11, 11, 11, 11, 11, 11, 11, 11, 11, 11, 11, 11, 11, 11, 11, 11, 11,
  12, 12, 12, 12, 12, 12, 12, 12, 12, 12, 12, 12, 12, 12, 12, 12, 12, 12, 12, 12, 12, 12, 12, 12, 12, 12, 12, 12, 12, 12, 12,
  1, 1, 1, 1, 1, 1, 1
);

#
# @var array
#/
our @MONTHDAY_MASK = (
  1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31,
  1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28,
  1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31,
  1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30,
  1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31,
  1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30,
  1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31,
  1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31,
  1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30,
  1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31,
  1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30,
  1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31,
  1, 2, 3, 4, 5, 6, 7
);

#
# @var array
#/
our @MONTHDAY_MASK_366 = (
  1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31,
  1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29,
  1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31,
  1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30,
  1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31,
  1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30,
  1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31,
  1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31,
  1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30,
  1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31,
  1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30,
  1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31,
  1, 2, 3, 4, 5, 6, 7
);

#
# @var array
#/
our @NEGATIVE_MONTHDAY_MASK = (
  -31, -30, -29, -28, -27, -26, -25, -24, -23, -22, -21, -20, -19, -18, -17, -16, -15, -14, -13, -12, -11, -10, -9, -8, -7, -6, -5, -4, -3, -2, -1,
  -28, -27, -26, -25, -24, -23, -22, -21, -20, -19, -18, -17, -16, -15, -14, -13, -12, -11, -10, -9,  -8,  -7,  -6, -5, -4, -3, -2, -1,
  -31, -30, -29, -28, -27, -26, -25, -24, -23, -22, -21, -20, -19, -18, -17, -16, -15, -14, -13, -12, -11, -10, -9, -8, -7, -6, -5, -4, -3, -2, -1,
  -30, -29, -28, -27, -26, -25, -24, -23, -22, -21, -20, -19, -18, -17, -16, -15, -14, -13, -12, -11, -10, -9,  -8, -7, -6, -5, -4, -3, -2, -1,
  -31, -30, -29, -28, -27, -26, -25, -24, -23, -22, -21, -20, -19, -18, -17, -16, -15, -14, -13, -12, -11, -10, -9, -8, -7, -6, -5, -4, -3, -2, -1,
  -30, -29, -28, -27, -26, -25, -24, -23, -22, -21, -20, -19, -18, -17, -16, -15, -14, -13, -12, -11, -10, -9,  -8, -7, -6, -5, -4, -3, -2, -1,
  -31, -30, -29, -28, -27, -26, -25, -24, -23, -22, -21, -20, -19, -18, -17, -16, -15, -14, -13, -12, -11, -10, -9, -8, -7, -6, -5, -4, -3, -2, -1,
  -31, -30, -29, -28, -27, -26, -25, -24, -23, -22, -21, -20, -19, -18, -17, -16, -15, -14, -13, -12, -11, -10, -9, -8, -7, -6, -5, -4, -3, -2, -1,
  -30, -29, -28, -27, -26, -25, -24, -23, -22, -21, -20, -19, -18, -17, -16, -15, -14, -13, -12, -11, -10, -9,  -8, -7, -6, -5, -4, -3, -2, -1,
  -31, -30, -29, -28, -27, -26, -25, -24, -23, -22, -21, -20, -19, -18, -17, -16, -15, -14, -13, -12, -11, -10, -9, -8, -7, -6, -5, -4, -3, -2, -1,
  -30, -29, -28, -27, -26, -25, -24, -23, -22, -21, -20, -19, -18, -17, -16, -15, -14, -13, -12, -11, -10, -9,  -8, -7, -6, -5, -4, -3, -2, -1,
  -31, -30, -29, -28, -27, -26, -25, -24, -23, -22, -21, -20, -19, -18, -17, -16, -15, -14, -13, -12, -11, -10, -9, -8, -7, -6, -5, -4, -3, -2, -1,
  -31, -30, -29, -28, -27, -26, -25
);

#
# @var array
#/
our @NEGATIVE_MONTHDAY_MASK_366 = (
  -31, -30, -29, -28, -27, -26, -25, -24, -23, -22, -21, -20, -19, -18, -17, -16, -15, -14, -13, -12, -11, -10, -9, -8, -7, -6, -5, -4, -3, -2, -1,
  -29, -28, -27, -26, -25, -24, -23, -22, -21, -20, -19, -18, -17, -16, -15, -14, -13, -12, -11, -10, -9,  -8,  -7, -6, -5, -4, -3, -2, -1,
  -31, -30, -29, -28, -27, -26, -25, -24, -23, -22, -21, -20, -19, -18, -17, -16, -15, -14, -13, -12, -11, -10, -9, -8, -7, -6, -5, -4, -3, -2, -1,
  -30, -29, -28, -27, -26, -25, -24, -23, -22, -21, -20, -19, -18, -17, -16, -15, -14, -13, -12, -11, -10, -9,  -8, -7, -6, -5, -4, -3, -2, -1,
  -31, -30, -29, -28, -27, -26, -25, -24, -23, -22, -21, -20, -19, -18, -17, -16, -15, -14, -13, -12, -11, -10, -9, -8, -7, -6, -5, -4, -3, -2, -1,
  -30, -29, -28, -27, -26, -25, -24, -23, -22, -21, -20, -19, -18, -17, -16, -15, -14, -13, -12, -11, -10, -9,  -8, -7, -6, -5, -4, -3, -2, -1,
  -31, -30, -29, -28, -27, -26, -25, -24, -23, -22, -21, -20, -19, -18, -17, -16, -15, -14, -13, -12, -11, -10, -9, -8, -7, -6, -5, -4, -3, -2, -1,
  -31, -30, -29, -28, -27, -26, -25, -24, -23, -22, -21, -20, -19, -18, -17, -16, -15, -14, -13, -12, -11, -10, -9, -8, -7, -6, -5, -4, -3, -2, -1,
  -30, -29, -28, -27, -26, -25, -24, -23, -22, -21, -20, -19, -18, -17, -16, -15, -14, -13, -12, -11, -10, -9,  -8, -7, -6, -5, -4, -3, -2, -1,
  -31, -30, -29, -28, -27, -26, -25, -24, -23, -22, -21, -20, -19, -18, -17, -16, -15, -14, -13, -12, -11, -10, -9, -8, -7, -6, -5, -4, -3, -2, -1,
  -30, -29, -28, -27, -26, -25, -24, -23, -22, -21, -20, -19, -18, -17, -16, -15, -14, -13, -12, -11, -10, -9,  -8, -7, -6, -5, -4, -3, -2, -1,
  -31, -30, -29, -28, -27, -26, -25, -24, -23, -22, -21, -20, -19, -18, -17, -16, -15, -14, -13, -12, -11, -10, -9, -8, -7, -6, -5, -4, -3, -2, -1,
  -31, -30, -29, -28, -27, -26, -25
);

#
# @var array
#/
our @WEEKDAY_MASK = (
  1, 2, 3, 4, 5, 6, 7, 1, 2, 3, 4, 5, 6, 7, 1, 2, 3, 4, 5, 6, 7, 1, 2, 3, 4, 5, 6, 7, 1, 2, 3, 4, 5, 6, 7,
  1, 2, 3, 4, 5, 6, 7, 1, 2, 3, 4, 5, 6, 7, 1, 2, 3, 4, 5, 6, 7, 1, 2, 3, 4, 5, 6, 7, 1, 2, 3, 4, 5, 6, 7,
  1, 2, 3, 4, 5, 6, 7, 1, 2, 3, 4, 5, 6, 7, 1, 2, 3, 4, 5, 6, 7, 1, 2, 3, 4, 5, 6, 7, 1, 2, 3, 4, 5, 6, 7,
  1, 2, 3, 4, 5, 6, 7, 1, 2, 3, 4, 5, 6, 7, 1, 2, 3, 4, 5, 6, 7, 1, 2, 3, 4, 5, 6, 7, 1, 2, 3, 4, 5, 6, 7,
  1, 2, 3, 4, 5, 6, 7, 1, 2, 3, 4, 5, 6, 7, 1, 2, 3, 4, 5, 6, 7, 1, 2, 3, 4, 5, 6, 7, 1, 2, 3, 4, 5, 6, 7,
  1, 2, 3, 4, 5, 6, 7, 1, 2, 3, 4, 5, 6, 7, 1, 2, 3, 4, 5, 6, 7, 1, 2, 3, 4, 5, 6, 7, 1, 2, 3, 4, 5, 6, 7,
  1, 2, 3, 4, 5, 6, 7, 1, 2, 3, 4, 5, 6, 7, 1, 2, 3, 4, 5, 6, 7, 1, 2, 3, 4, 5, 6, 7, 1, 2, 3, 4, 5, 6, 7,
  1, 2, 3, 4, 5, 6, 7, 1, 2, 3, 4, 5, 6, 7, 1, 2, 3, 4, 5, 6, 7, 1, 2, 3, 4, 5, 6, 7, 1, 2, 3, 4, 5, 6, 7,
  1, 2, 3, 4, 5, 6, 7, 1, 2, 3, 4, 5, 6, 7, 1, 2, 3, 4, 5, 6, 7, 1, 2, 3, 4, 5, 6, 7, 1, 2, 3, 4, 5, 6, 7,
  1, 2, 3, 4, 5, 6, 7, 1, 2, 3, 4, 5, 6, 7, 1, 2, 3, 4, 5, 6, 7, 1, 2, 3, 4, 5, 6, 7, 1, 2, 3, 4, 5, 6, 7,
  1, 2, 3, 4, 5, 6, 7, 1, 2, 3, 4, 5, 6, 7, 1, 2, 3, 4, 5, 6, 7, 1, 2, 3, 4, 5, 6, 7, 1, 2, 3, 4, 5, 6, 7
);

#
# @var array
#/
our @LAST_DAY_OF_MONTH_366 = ( 0, 31, 60, 91, 121, 152, 182, 213, 244, 274, 305, 335, 366 );

#
# @var array
#/
our @LAST_DAY_OF_MONTH = ( 0, 31, 59, 90, 120, 151, 181, 212, 243, 273, 304, 334, 365 );

#
# @var array
# Maximum number of cycles after which a calendar repeats itself. This
# is used to detect infinite loop: if no occurrence has been found
# after this numbers of cycles, we can abort.
#
# The Gregorian calendar cycle repeat completely every 400 years
# (146,097 days or 20,871 weeks).
# A smaller cycle would be 28 years (1,461 weeks), but it only works
# if there is no dropped leap year in between.
# 2100 will be a dropped leap year, but I'm going to assume it's not
# going to be a problem anytime soon, so at the moment I use the 28 years
# cycle.
#/
our %REPEAT_CYCLES = (

  # self::YEARLY => 400,
  # self::MONTHLY => 4800,
  # self::WEEKLY => 20871,
  # self::DAILY =>  146097, # that's a lot of cycles, it takes a few seconds to detect infinite loop
  RRule::YEARLY  => 28,
  RRule::MONTHLY => 336,
  RRule::WEEKLY  => 1461,
  RRule::DAILY   => 10227,

  #RRule::YEARLY  => 2,
  #RRule::MONTHLY => 24,
  #RRule::WEEKLY  => 104,
  #RRule::DAILY   => 730,

  RRule::HOURLY   => 24,
  RRule::MINUTELY => 1440,
  RRule::SECONDLY => 86400    # that's a lot of cycles too
);

#**
# High level "line".
# Explode a line into property name, property parameters and property value
#/
sub parseLine {
  my ( $line, $default ) = @_;

  # warn $line, $default;
  $line = trim($line);
  my %property = ( 'name' => $default );

  if ( $line !~ /^\w*:/ ) {
    if ( !$property{'name'} ) {
      warn('Failed to parse RFC line, missing property name followed by ":"');
    }
    $property{'value'} = $line;
  }
  else {
    ( $property{'name'}, $property{'value'} ) = split( ':', $line );

    my @tmp = split( ';', $property{'name'} );
    $property{'name'} = $tmp[0];
    splice( @tmp, 0, 1 );
    foreach my $pair (@tmp) {
      if ( !$pair ) {
        next;
      }
      if ( index( $pair, '=' ) == -1 ) {
        warn( 'Failed to parse RFC line, invalid property parameters: ' . $pair );
      }
      my ( $key, $value ) = split( '=', $pair );
      $property{'params'}{$key} = $value;
    }
  }

  return %property;
}

#
# Parse both DTSTART and RRULE (and EXRULE).
#
# It's impossible to accuratly parse a RRULE in isolation (without the DTSTART)
# as some tests depends on DTSTART (notably the date format for UNTIL).
#
# @param string $string The RFC-like string
# @param mixed $dtstart The default dtstart to be used (if not in the string)
# @return array
#
sub parseRRule {
  my $string  = shift;
  my $dtstart = shift;
  $string = trim($string);
  my %parts;
  my $dtstart_type;
  my $rfc_date_regexp = '\d{6}(T\d{6})?Z?';       # regexp to check the date, a bit loose
  my $nb_dtstart      = 0;
  my $nb_rrule        = 0;
  my @lines           = split( "\n", $string );

  if ($dtstart) {
    $nb_dtstart = 1;
    if ($dtstart) {
      if ( length($dtstart) == 10 ) {
        $dtstart_type = 'date';
      }
      else {
        $dtstart_type = 'localtime';
      }
    }
    else {
      $dtstart_type = 'tzid';
    }
    $parts{'DTSTART'} = RRule::parseDate($dtstart);
  }

  foreach my $line (@lines) {
    my %property = RRule::parseLine( $line, ( scalar(@lines) > 1 ) ? undef : 'RRULE' );    # allow missing property name for single-line RRULE
                                                                                           # print "PROP: " . Dumper \%property;

    for ( uc( $property{'name'} ) ) {
      if (/DTSTART/) {
        $nb_dtstart += 1;
        if ( $nb_dtstart > 1 ) {
          warn('Too many DTSTART properties (there can be only one)');
        }
        my $tmp;
        $dtstart_type = 'date';
        if ( !preg_match( $rfc_date_regexp, $property{'value'} ) ) {
          warn('Invalid DTSTART property: date or date time format incorrect');
        }
        if ( isset( $property{'params'}['TZID'] ) ) {
          ## TZID must only be specified if this is a date-time (see section 3.3.4 & 3.3.5 of RFC 5545)
          if ( strpos( $property{'value'}, 'T' ) == false ) {
            warn('Invalid DTSTART property: TZID should not be specified if there is no time component');
          }

          # The "TZID" property parameter MUST NOT be applied to DATE-TIME
          # properties whose time values are specified in UTC.
          if ( strpos( $property{'value'}, 'Z' ) != false ) {
            warn('Invalid DTSTART property: TZID must not be applied when time is specified in UTC');
          }
          $dtstart_type = 'tzid';
          $tmp          = DateTimeZone( $property{'params'}['TZID'] );
        }
        elsif ( strpos( $property{'value'}, 'T' ) != false ) {
          if ( strpos( $property{'value'}, 'Z' ) == false ) {
            $dtstart_type = 'localtime';    # no timezone
          }
          else {
            $dtstart_type = 'utc';
          }
        }
        $parts{'DTSTART'} = new \DateTime( $property{'value'}, $tmp );
      }
      elsif ( /RRULE/ || /EXRULE/ ) {
        $nb_rrule += 1;
        if ( $nb_rrule > 1 ) {
          warn('Too many RRULE properties (there can be only one)');
        }
        foreach my $pair ( split( ';', $property{'value'} ) ) {
          my ( $key, $value ) = split( '=', $pair );
          if ( !$key && !$value ) {
            warn("Failed to parse RFC string, malformed RRULE property: {$property{'value'}}");
          }
          if ( $key eq 'UNTIL' ) {
            if ( $value !~ $rfc_date_regexp ) {
              warn('Invalid UNTIL property: date or date time format incorrect');
              warn $value;
            }
            for ($dtstart_type) {
              if (/date/) {
                if ( index( $value, 'T' ) == -1 ) {
                  warn('Invalid UNTIL property: The value of the UNTIL rule part MUST be a date if DTSTART is a date.');
                }
              }
              elsif (/localtime/) {
                if ( index( $value, 'T' ) == -1 || index( $value, 'Z' ) == -1 ) {
                  warn('Invalid UNTIL property: if the "DTSTART" property is specified as a date with local time, then the UNTIL rule part MUST also be specified as a date with local time');
                }
              }
              elsif ( /tzid/ || /utc/ ) {
                if ( index( $value, 'T' ) == -1 || index( $value, 'Z' ) == -1 ) {
                  warn('Invalid UNTIL property: if the "DTSTART" property is specified as a date with UTC time or a date with local time and time zone reference, then the UNTIL rule part MUST be specified as a date with UTC time.');
                }
              }
            }

            $value = date_create($value);
          }
          elsif ( $key eq 'DTSTART' ) {
            if ( isset( $parts{'DTSTART'} ) ) {
              warn('DTSTART cannot be part of RRULE and has already been defined');
            }

            # this is an invalid rule, however we'll support it since the JS lib is broken
            # see https://github.com/rlanvin/php-rrule/issues/25
            warn("This string is not compliant with the RFC (DTSTART cannot be part of RRULE). It is accepted as is for compability reasons only.");
          }
          $parts{$key} = $value;
        }
      }
      else {
        warn( 'Failed to parse RFC string, unsupported property: ' . $property{'name'} );
      }
    }
  }
  return \%parts;
}

sub date {
  my $format    = shift;
  my $ts        = shift;
  my @timearray = localtime($ts);
  return POSIX::strftime( $format, @timearray );
}

sub createFromFormat {
  my $format = shift;
  my $values = shift;
  my ( $year, $yearday ) = split " ", $values;
  return POSIX::mktime( 0, 0, 0, $yearday + 1, 0, $year - 1900 );
}

sub date_create {
  my $datetime = shift;

  #  warn $datetime;

  #/ first check format
  my @formats;
  push @formats, "/[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]/";
  push @formats, "/[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]T[0-9][0-9][0-9][0-9][0-9][0-9]/";
  push @formats, "/[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]T[0-9][0-9][0-9][0-9][0-9][0-9]Z/";
  push @formats, "/[0-9][0-9][0-9][0-9]\-[0-9][0-9]\-[0-9][0-9]T[0-9][0-9]\-[0-9][0-9]\-[0-9][0-9]/";
  my $ok = 0;
  foreach my $format (@formats) {
    if ( $datetime =~ $format, $datetime ) {
      $ok = 1;
      last;
    }
  }
  if ( !$ok ) {
    return 0;
  }
  $datetime =~ s/\-//g;
  my $year  = substr( $datetime, 0, 4 );
  my $month = substr( $datetime, 4, 2 );
  my $day   = substr( $datetime, 6, 2 );
  my $hour  = 0;
  my $minute = 0;
  my $second = 0;

  if ( length($datetime) > 8 && substr( $datetime, 7, 1 ) eq "T" ) {
    $hour   = substr( $datetime, 9,  2 );
    $minute = substr( $datetime, 11, 2 );
    $second = substr( $datetime, 13, 2 );
  }

  #  warn "$second, $minute, $hour, $day, $month, $year";
  my $ret = POSIX::mktime( $second, $minute, $hour, $day, $month - 1, $year - 1900 );

  #  warn $ret;
  return $ret;
}

sub addDate {
  my $this = shift;
  my ( $date, $hour, $min, $sec, $month, $day, $year, $tzid ) = @_;
  $tzid ||= "UTC";

  # print "($date, $hour, $min, $sec, $month, $day, $year, $tzid)\n";
  my %ts;
  @ts{ "sec", "min", "hour", "day", "month", "year", "wday", "yday", "isdst" } = localtime($date);

  # print Dumper \%ts;
  my $newdate = POSIX::mktime( $ts{sec} + $sec, $ts{min} + $min, $ts{hour} + $hour, $ts{day} + $day, $ts{month} + $month, $ts{year} + $year );

  # print "$ts{year} " . POSIX::strftime( "%F %T", localtime($newdate) ) . "\n";
  return $newdate;
}
1;
