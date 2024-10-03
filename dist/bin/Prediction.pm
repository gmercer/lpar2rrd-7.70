package Prediction;

use strict;
use warnings;

use List::Util qw(sum);
use Data::Dumper;
use POSIX qw(strftime);
use RRDDump;
use Scalar::Util qw(looks_like_number);

my $basedir        = $ENV{INPUTDIR} || Xorux_lib::error("INPUTDIR is not defined") && exit 0;
my $prediction_dir = "$basedir/tmp/prediction";

unless ( -d $prediction_dir ) {
  mkdir( "$prediction_dir", 0755 ) || warn( localtime() . ": Cannot mkdir $prediction_dir: $!" . __FILE__ . ':' . __LINE__ );
}

my $initial_alfa       = 0.269;
my $initial_beta       = 0.019;
my $initial_gamma      = 0.293;
my $initial_iterations = 4200;
my $initial_learn_alg  = 'tabu_search';

sub new {

  #my($self, @data, $slen, $n_preds) = @_;

  my $self    = $_[0];
  my @data    = @{ $_[1] };
  my $slen    = $_[2];
  my $n_preds = $_[3];

  #print Dumper(@data);

  my $o = {};
  $o->{data}    = \@data;
  $o->{slen}    = $slen;
  $o->{n_preds} = $n_preds;

  bless $o;
  return $o;
}

sub set_data {
  my $self = $_[0];
  my @data = @{ $_[1] };

  $self->{data} = \@data;
}

sub set_parameters {
  my ( $self, $alfa, $beta, $gamma ) = @_;
  $self->{alfa}  = $alfa;
  $self->{beta}  = $beta;
  $self->{gamma} = $gamma;
}

sub learn_parameters {
  my ( $self, $algorithm, $iteration, @data ) = @_;

  if ( scalar @data <= 19 || scalar @{ $self->{data} } <= 29 ) {
    return -2;
  }

  #print Dumper(@data);

  if ( $algorithm eq "random_search" ) {
    $self->learning_random_search( $iteration, @data );
  }
  elsif ( $algorithm eq "hill_climbing" ) {
    $self->learning_hill_climbing( $iteration, @data );
  }
  elsif ( $algorithm eq "tabu_search" ) {
    $self->learning_tabu_search( $iteration, @data );
  }

}

sub learning_hill_climbing {

  #my ($self, $iteration, @data) = @_;

  my $self      = $_[0];
  my $iteration = $_[1];
  my @data      = @{ $_[2] };

  #print "\n\n---\n";
  #print Dumper(@data);

  my $alfa  = $self->{alfa};
  my $beta  = $self->{beta};
  my $gamma = $self->{gamma};
  my $value;

  my %best;
  my %best_climb;

  $self->set_parameters( $alfa, $beta, $gamma );
  $value = $self->prediction( \@data );

  $best_climb{value} = $value;
  $best_climb{alfa}  = $alfa;
  $best_climb{beta}  = $beta;
  $best_climb{gamma} = $gamma;

  my $num_climbing = int( $iteration / 12 );
  my $dimension    = 3;
  my $step         = 15;

  for ( 0 .. $num_climbing ) {
    for ( -1 .. 1 ) {
      my $alfa_number = $_;
      $alfa = $alfa + $alfa_number / 100;

      for ( -1 .. 1 ) {
        my $beta_number = $_;
        $beta = $beta + $beta_number / 100;

        for ( -1 .. 1 ) {
          my $gamma_number = $_;
          $gamma = $gamma + $gamma_number / 100;

          $self->set_parameters( $alfa, $beta, $gamma );
          $value = $self->prediction( \@data );

          #print "\nLearning on alfa: $alfa, beta: $beta, gamma: $gamma ---- value: $value";

          if ( $best_climb{value} > $value ) {
            $best_climb{value} = $value;
            $best_climb{alfa}  = $alfa;
            $best_climb{beta}  = $beta;
            $best_climb{gamma} = $gamma;
          }

          if ( !defined $best{value} ) {
            $best{value} = $value;
            $best{alfa}  = $alfa;
            $best{beta}  = $beta;
            $best{gamma} = $gamma;
          }
          else {
            if ( $value < $best{value} ) {
              $best{value} = $value;
              $best{alfa}  = $alfa;
              $best{beta}  = $beta;
              $best{gamma} = $gamma;
            }
          }
        }
      }
    }

    $alfa  = $best_climb{alfa};
    $beta  = $best_climb{beta};
    $gamma = $best_climb{gamma};
  }

  #print "\n\nBest parameters -> alfa: $best{alfa}, beta: $best{beta}, gamma: $best{gamma}\n";
}

sub learning_tabu_search {

  #my ($self, $iteration, @data) = @_;

  my $self      = $_[0];
  my $iteration = $_[1];
  my @data      = @{ $_[2] };

  my $slen       = $self->{slen};
  my $slen_count = $slen / 7;

  #print "\n\n---\n";
  #print Dumper(@data);

  my $alfa  = $self->{alfa};
  my $beta  = $self->{beta};
  my $gamma = $self->{gamma};
  my $value;

  my %best;
  my %best_climb;
  my %history;

  $history{$alfa}{$beta}{$gamma} = 1;

  $self->set_parameters( $alfa, $beta, $gamma );
  $value = $self->prediction( \@data );

  my $step = 15;

  my $active            = 1;
  my $current_iteration = 0;

  while ( $active == 1 ) {
    for ( -1 .. 1 ) {
      my $alfa_number = $_;
      $alfa = $alfa + $alfa_number * $step / 1000;

      if ( $alfa < 0 ) {
        next;
      }

      for ( -1 .. 1 ) {
        my $beta_number = $_;
        $beta = $beta + $beta_number * $step / 1000;

        if ( $beta < 0 ) {
          next;
        }

        for ( -1 .. 1 ) {
          my $gamma_number = $_;
          $gamma = $gamma + $gamma_number * $step / 1000;

          if ( $gamma < 0 ) {
            next;
          }

          for ( 1 .. $slen_count ) {
            my $actual_slen = $_ * 7;

            if ( $current_iteration >= $iteration ) {
              $active = 0;
            }
            else {
              $current_iteration = $current_iteration + 1;
            }

            if ( defined $history{$alfa}{$beta}{$gamma} ) {
              next;
            }

            $self->{slen} = $actual_slen;
            $self->set_parameters( $alfa, $beta, $gamma );
            $value = $self->prediction( \@data );

            #print "\nLearning on alfa: $alfa, beta: $beta, gamma: $gamma, slen: $actual_slen ---- value: $value";

            #best climb this iteration
            if ( !defined $best_climb{value} || $best_climb{value} > $value ) {
              $best_climb{value} = $value;
              $best_climb{alfa}  = $alfa;
              $best_climb{beta}  = $beta;
              $best_climb{gamma} = $gamma;
            }

            #global best
            if ( !defined $best{value} ) {
              $best{value} = $value;
              $best{alfa}  = $alfa;
              $best{beta}  = $beta;
              $best{gamma} = $gamma;
              $best{slen}  = $actual_slen;
            }
            else {
              if ( $value < $best{value} ) {
                $best{value} = $value;
                $best{alfa}  = $alfa;
                $best{beta}  = $beta;
                $best{gamma} = $gamma;
                $best{slen}  = $actual_slen;
              }
            }
          }
        }
      }
    }

    $history{$alfa}{$beta}{$gamma} = 1;
    $alfa                          = $best_climb{alfa};
    $beta                          = $best_climb{beta};
    $gamma                         = $best_climb{gamma};
    undef $best_climb{value};
  }

  #set best
  $self->{slen} = $best{slen};
  $self->set_parameters( $best{alfa}, $best{beta}, $best{gamma} );

}

sub learning_random_search {
  my ( $self, $iteration, @data ) = @_;

  my $alfa;
  my $beta;
  my $gamma;
  my $value;

  my %best;

  for ( 0 .. $iteration ) {
    $alfa  = int( rand(1000) ) / 1000;
    $beta  = int( rand(1000) ) / 1000;
    $gamma = int( rand(1000) ) / 1000;

    $self->set_parameters( $alfa, $beta, $gamma );
    $value = $self->prediction(@data);

    if ( !defined $best{value} ) {
      $best{value} = $value;
      $best{alfa}  = $alfa;
      $best{beta}  = $beta;
      $best{gamma} = $gamma;
    }
    else {
      if ( $value < $best{value} ) {
        $best{value} = $value;
        $best{alfa}  = $alfa;
        $best{beta}  = $beta;
        $best{gamma} = $gamma;
      }
    }

    #print "\nLearning on alfa: $alfa, beta: $beta, gamma: $gamma ---- value: $value";
  }

  #print "\n\nBest parameters -> alfa: $best{alfa}, beta: $best{beta}, gamma: $best{gamma}\n";

  $self->set_parameters( $best{alfa}, $best{beta}, $best{gamma} );

}

sub find_value {
  my ( $self, $value, $limit ) = @_;

  return self->prediction_find( $value, $limit );
}

sub initial_trend {
  my @series = @{ $_[0] };
  my $slen   = $_[1];

  my $sum = 0;

  for ( 0 .. $slen - 1 ) {
    my $actual_number = $_;
    if ( !defined $series[ $actual_number + $slen ] ) {
      next;
    }
    $sum += ( $series[ $actual_number + $slen ] - $series[$actual_number] ) / $slen;
  }

  my $data = $sum / $slen;

  return $data;
}

sub initial_seasonal_components {
  my @series = @{ $_[0] };
  my $slen   = $_[1];

  my @seasonals;
  my @season_averages;

  my $len       = scalar @series;
  my $n_seasons = int( $len / $slen );

  for ( 0 .. $n_seasons - 1 ) {
    my $actual_number = $_;

    #my $actual_season = sum($series[$slen*$actual_number:$slen*$actual_number+$slen])/$slen;

    my $start_index = $slen * $actual_number;
    my $stop_index  = $slen * $actual_number + $slen;
    my $sum         = 0;

    for ( $start_index .. $stop_index ) {
      my $actual_index = $_;
      if ( defined $series[$actual_index] ) {
        $sum += $series[$actual_index];
      }
    }

    my $actual_season = $sum / $slen;

    push( @season_averages, $actual_season );
  }

  for ( 0 .. $slen - 1 ) {
    my $actual_number        = $_;
    my $sum_of_vals_over_avg = 0;

    for ( 0 .. $n_seasons - 1 ) {
      my $actual_number_2 = $_;
      $sum_of_vals_over_avg += $series[ $slen * $actual_number_2 + $actual_number ] - $season_averages[$actual_number_2];
    }

    $seasonals[$actual_number] = $sum_of_vals_over_avg / $n_seasons;
  }

  return @seasonals;
}

sub prediction {
  my $self    = $_[0];
  my @series  = @{ $self->{data} };
  my $slen    = $self->{slen};
  my $n_preds = $self->{n_preds};

  my @learn;
  my $learn_value;
  if ( $_[1] ) {
    @learn = @{ $_[1] };
  }

  my $alfa  = $self->{alfa};
  my $beta  = $self->{beta};
  my $gamma = $self->{gamma};

  if ( !defined $learn[1] ) {

    #print "\nparameters -> alfa: $alfa, beta: $beta, gamma: $gamma";
  }

  my $trend;
  my $smooth;
  my $last_smooth;
  my $m;
  my $data;
  my $val;
  my $modulo;
  my $debug;

  my @result;
  my @seasonals = initial_seasonal_components( \@series, $slen );

  my $len   = scalar @series;
  my $loops = $len + $n_preds;

  for ( 0 .. $loops - 1 ) {
    my $actual_number = $_;
    if ( $actual_number eq 0 ) {
      $smooth = $series[0];
      $trend  = initial_trend( \@series, $slen );
      push( @result, $series[0] );
    }
    if ( $actual_number >= $len - 1 ) {
      $m     = $actual_number - $len + 1;
      $data  = ( $smooth + $m * $trend ) + ( $seasonals[ $actual_number % $slen ] );
      $debug = ( $smooth + $m * $trend );
      if ( !defined $learn[1] ) {

        #print "\nloop: $actual_number, m: $m, value: $data ($debug,  $seasonals[$actual_number % $slen])";
      }

      if ( defined $learn[$actual_number] ) {
        if ( defined $learn_value ) {
          $learn_value += abs( $learn[$actual_number] - $data );
        }
        else {
          $learn_value = abs( $learn[$actual_number] - $data );
        }
      }

      push( @result, $data );
    }
    else {
      $val = $series[$actual_number];
      if ( !defined $learn[1] ) {

        #print "\nloop: $actual_number, value: $val";
      }
      $last_smooth                         = $smooth;
      $smooth                              = $alfa * ( $val - $seasonals[ $actual_number % $slen ] ) + ( 1 - $alfa ) * ( $smooth + $trend );
      $trend                               = $beta * ( $smooth - $last_smooth ) + ( 1 - $beta ) * $trend;
      $seasonals[ $actual_number % $slen ] = $gamma * ( $val - $smooth ) + ( 1 - $gamma ) * $seasonals[ $actual_number % $slen ];
      push( @result, ( $smooth + $trend + $seasonals[ $actual_number % $slen ] ) );
    }
  }

  if ( defined $learn_value ) {
    return $learn_value;
  }
  else {
    #print "\n";
    return \@result;
  }

}

sub prediction_find {
  my $self       = $_[0];
  my @series     = @{ $self->{data} };
  my $slen       = $self->{slen};
  my $find_value = $_[1];
  my $limit      = $_[2];
  my $type       = $_[3];

  my $find_position = -1;

  my $alfa  = $self->{alfa};
  my $beta  = $self->{beta};
  my $gamma = $self->{gamma};

  my $trend;
  my $smooth;
  my $last_smooth;
  my $m;
  my $data;
  my $val;
  my $modulo;
  my $debug;

  my @result;
  my @seasonals = initial_seasonal_components( \@series, $slen );

  my $len   = scalar @series;
  my $loops = $limit + $len;

  for ( 0 .. $loops - 1 ) {
    my $actual_number = $_;
    if ( $actual_number eq 0 ) {
      $smooth = $series[0];
      $trend  = initial_trend( \@series, $slen );
      push( @result, $series[0] );
    }
    if ( $actual_number >= $len ) {
      $m     = $actual_number - $len + 1;
      $data  = ( $smooth + $m * $trend ) + ( $seasonals[ $actual_number % $slen ] );
      $debug = ( $smooth + $m * $trend );

      if ( $type eq "max" ) {
        if ( $data >= $find_value ) {
          $find_position = $m;
          last;
        }
      }
      elsif ( $type eq "min" ) {
        if ( $data <= $find_value ) {
          $find_position = $m;
          last;
        }
      }
      else {
        return 0;
      }

      push( @result, $data );
    }
    else {
      $val                                 = $series[$actual_number];
      $last_smooth                         = $smooth;
      $smooth                              = $alfa * ( $val - $seasonals[ $actual_number % $slen ] ) + ( 1 - $alfa ) * ( $smooth + $trend );
      $trend                               = $beta * ( $smooth - $last_smooth ) + ( 1 - $beta ) * $trend;
      $seasonals[ $actual_number % $slen ] = $gamma * ( $val - $smooth ) + ( 1 - $gamma ) * $seasonals[ $actual_number % $slen ];
      push( @result, ( $smooth + $trend + $seasonals[ $actual_number % $slen ] ) );
    }
  }

  return $find_position;

}

sub prediction_find_and_export {
  my $self       = $_[0];
  my @series     = @{ $self->{data} };
  my $slen       = $self->{slen};
  my $find_value = $_[1];
  my $limit      = $_[2];
  my $type       = $_[3];

  my $multiplication = 1;
  if ( defined $_[4] ) {
    $multiplication = $_[4];
  }

  my $find_position;

  my $alfa  = $self->{alfa};
  my $beta  = $self->{beta};
  my $gamma = $self->{gamma};

  my %output;
  $output{parameters}{alfa}           = $alfa;
  $output{parameters}{beta}           = $beta;
  $output{parameters}{gamma}          = $gamma;
  $output{parameters}{multiplication} = $multiplication;
  $output{parameters}{find_value}     = $find_value;
  $output{parameters}{limit}          = $limit;
  $output{parameters}{s_len}          = $self->{slen};
  $output{parameters}{series_len}     = scalar @series;
  $output{parameters}{type}           = $type;

  my $trend;
  my $smooth;
  my $last_smooth;
  my $m;
  my $data;
  my $val;
  my $modulo;
  my $debug;

  my @result;
  my @seasonals = initial_seasonal_components( \@series, $slen );

  my $len   = scalar @series;
  my $loops = $limit + $len;

  my $next_exit = 0;
  my $under     = 0;
  my $last_day;

  my $timestamp = time();
  my $timestamp_now;
  my ( $sec, $min, $hour, $mday, $mon, $year, $wday, $yday, $isdst );

  for ( 0 .. $loops - 1 ) {
    my $actual_number = $_;

    if ( $next_exit == 1 || $under == 1 ) {
      last;
    }

    if ( $actual_number eq 0 ) {
      $smooth = $series[0];
      $trend  = initial_trend( \@series, $slen );
      push( @result, $series[0] );

      $timestamp_now = $timestamp - ( ( $len - $actual_number ) * 86400 );

      ( $sec, $min, $hour, $mday, $mon, $year, $wday, $yday, $isdst ) = localtime($timestamp_now);
      $year += 1900;
      $mon  += 1;

      $mon  = sprintf( "%02d", $mon );
      $mday = sprintf( "%02d", $mday );

      $last_day = "$year-$mon-$mday";
      $output{data}{real}{"$year-$mon-$mday"} = sprintf( "%.3f", ( $series[0] * $multiplication ) ) * 1;

      #$output{data}{real}{"$year-$mon-$mday"} = int($series[0]);
    }
    if ( $actual_number >= $len ) {
      $m = $actual_number - $len + 1;

      $data  = ( $smooth + $m * $trend ) + ( $seasonals[ $actual_number % $slen ] );
      $debug = ( $smooth + $m * $trend );

      if ( $type eq "max" ) {
        if ( $data >= $find_value ) {
          if ( !defined $find_position ) {
            $find_position = $m;
          }
          $next_exit = 1;
        }
      }
      elsif ( $type eq "min" ) {
        if ( $data <= $find_value ) {
          if ( !defined $find_position ) {
            $find_position = $m;
          }
          $next_exit = 1;
        }
      }
      else {
        return 0;
      }

      if ( $data <= 0 ) {
        $under = 1;
      }

      push( @result, $data );

      $timestamp_now = $timestamp + ( $m * 86400 ) - 86400;

      ( $sec, $min, $hour, $mday, $mon, $year, $wday, $yday, $isdst ) = localtime($timestamp_now);
      $year += 1900;
      $mon  += 1;

      $mon  = sprintf( "%02d", $mon );
      $mday = sprintf( "%02d", $mday );

      if ( $m eq "1" ) {

        #$output{data}{prediction}{$last_day} = int($output{data}{real}{$last_day});
        $output{data}{prediction}{$last_day} = sprintf( "%.3f", $output{data}{real}{$last_day} ) * 1;
      }

      if ( $next_exit == 1 ) {
        $output{data}{prediction}{"$year-$mon-$mday"} = $find_value * $multiplication;
      }
      else {
        $output{data}{prediction}{"$year-$mon-$mday"} = sprintf( "%.3f", ( ( $smooth + $m * $trend ) + ( $seasonals[ $actual_number % $slen ] ) ) * $multiplication ) * 1;

        #$output{data}{prediction}{"$year-$mon-$mday"} = int(($smooth + $m * $trend)+($seasonals[$actual_number % $slen]));
      }

    }
    else {
      $val                                 = $series[$actual_number];
      $last_smooth                         = $smooth;
      $smooth                              = $alfa * ( $val - $seasonals[ $actual_number % $slen ] ) + ( 1 - $alfa ) * ( $smooth + $trend );
      $trend                               = $beta * ( $smooth - $last_smooth ) + ( 1 - $beta ) * $trend;
      $seasonals[ $actual_number % $slen ] = $gamma * ( $val - $smooth ) + ( 1 - $gamma ) * $seasonals[ $actual_number % $slen ];
      push( @result, ( $smooth + $trend + $seasonals[ $actual_number % $slen ] ) );

      $timestamp_now = $timestamp - ( ( $len - $actual_number ) * 86400 );

      ( $sec, $min, $hour, $mday, $mon, $year, $wday, $yday, $isdst ) = localtime($timestamp_now);
      $year += 1900;
      $mon  += 1;

      $mon  = sprintf( "%02d", $mon );
      $mday = sprintf( "%02d", $mday );

      $last_day = "$year-$mon-$mday";

      #$output{data}{real}{$timestamp_now} = $series[$actual_number];
      $output{data}{real}{"$year-$mon-$mday"} = sprintf( "%.3f", ( $series[$actual_number] * $multiplication ) ) * 1;

      #$output{data}{real}{"$year-$mon-$mday"} = int($series[$actual_number]);
    }
  }

  if ( defined $find_position ) {
    $timestamp_now = $timestamp + ( $find_position * 86400 ) - 86400;
    ( $sec, $min, $hour, $mday, $mon, $year, $wday, $yday, $isdst ) = localtime($timestamp_now);
    $year += 1900;
    $mon  += 1;

    $mon  = sprintf( "%02d", $mon );
    $mday = sprintf( "%02d", $mday );

    $output{time} = "$year-$mon-$mday";
  }
  else {
    $output{time} = 0;
  }

  #sorting
  #my %sorted;
  #foreach my $time_value (sort {$a <=> $b} keys %{$output{data}{real}}) {
  #  $sorted{data}{real}{$time_value} = $output{data}{real}{$time_value};
  #}

  #print Dumper(%sorted);

  #my @path_splitted = split(/\//, $path);
  #my $path_count = scalar @path_splitted;
  #my @name_splitted = split(/\./, $path_splitted[$path_count-1]);

  if (%output) {

    #open my $hl, ">", $prediction_dir."/".$name_splitted[0].".json";
    #print $hl JSON->new->pretty->encode(\%output);;
    #close $hl;
    return JSON->new->pretty->encode( \%output );
  }
  else {
    return 0;
  }

}

sub create_learn_data {
  my @data = @{ $_[0] };

  my @learn_data;
  my $learn_count = int( scalar @data / 3 * 2 );
  my $all_count   = scalar @data;

  #print "\nlearn_count = $learn_count";
  #print Dumper(@data);

  my $i = 0;
  for my $data_value (@data) {
    $learn_data[$i] = $data_value;
    if ( $i >= $learn_count ) {
      last;
    }
    $i++;
  }

  return @learn_data;

}

sub get_seasons {
  my $count = shift;
  my $seasons;

  if ( $count <= 30 ) {
    $seasons = 2;
  }
  else {
    $seasons = 30;
  }

  return $seasons;
}

#delete this method in future, now for backward compatibility
sub get_days_to_zero {
  my ( $rrd, $metric ) = @_;

  my $dump      = RRDDump->new($rrd);
  my @dump_data = $dump->get_metric( $metric, 180 );

  my @learn_data = create_learn_data( \@dump_data );

  if ( scalar @learn_data <= 19 ) {
    return -2;
  }

  my $seasons = get_seasons( scalar @learn_data );

  my $prediction = Prediction->new( \@learn_data, $seasons, '365' );
  $prediction->set_parameters( $initial_alfa, $initial_beta, $initial_gamma );
  $prediction->learn_parameters( $initial_learn_alg, $initial_iterations, \@dump_data );
  $prediction->set_data( \@dump_data );

  #find value under (= min) 0, max 365 days in future
  my $find = $prediction->prediction_find( 0, 365, 'min' );

  return $find;

  #return -1 = the value is not exceeded in 365 days
  #return -2 = less than 90 values (days in the past)
}

sub get_days_to_value {
  my ( $rrd, $metric, $value, $type ) = @_;

  my $dump      = RRDDump->new($rrd);
  my @dump_data = $dump->get_metric( $metric, 180 );

  my @learn_data = create_learn_data( \@dump_data );

  if ( scalar @learn_data <= 19 ) {
    return -2;
  }

  my $seasons = get_seasons( scalar @learn_data );

  my $prediction = Prediction->new( \@learn_data, $seasons, '365' );
  $prediction->set_parameters( $initial_alfa, $initial_beta, $initial_gamma );
  $prediction->learn_parameters( $initial_learn_alg, $initial_iterations, \@dump_data );
  $prediction->set_data( \@dump_data );

  #find value under (= min) 0, max 365 days in future
  my $find = $prediction->prediction_find( $value, 365, $type );

  return $find;

  #return -1 = the value is not exceeded in 365 days
  #return -2 = less than 90 values (days in the past)
}

sub get_days_to_value_by_array {
  my @data  = @{ $_[0] };
  my $value = $_[1];
  my $type  = $_[2];

  @data = check_array_data( \@data );

  my @learn_data = create_learn_data( \@data );

  if ( scalar @learn_data <= 19 || scalar @data <= 29 ) {
    return -2;
  }

  my $seasons = get_seasons( scalar @learn_data );

  my $prediction = Prediction->new( \@learn_data, $seasons, '365' );
  $prediction->set_parameters( $initial_alfa, $initial_beta, $initial_gamma );

  if ( scalar @learn_data >= 60 ) {
    $prediction->learn_parameters( $initial_learn_alg, $initial_iterations, \@data );
  }

  $prediction->set_data( \@data );
  my $find = $prediction->prediction_find( $value, 365, $type );

  return $find;
}

#delete this method in future, now for backward compatibility
sub export_get_days_to_zero {
  my ( $rrd, $metric, $multiplication ) = @_;

  my $dump      = RRDDump->new($rrd);
  my @dump_data = $dump->get_metric( $metric, 180 );

  my @learn_data = create_learn_data( \@dump_data );

  if ( scalar @learn_data <= 19 ) {
    return -2;
  }

  my $seasons = get_seasons( scalar @learn_data );

  my $prediction = Prediction->new( \@learn_data, $seasons, '365' );

  $prediction->set_parameters( $initial_alfa, $initial_beta, $initial_gamma );
  $prediction->learn_parameters( $initial_learn_alg, $initial_iterations, \@dump_data );
  $prediction->set_data( \@dump_data );
  my $rc = $prediction->prediction_find_and_export( 0, 365, 'min', $multiplication );

  return $rc;
}

# value = search value, type = max/min = over/under
sub export_get_days_to_value {
  my ( $rrd, $metric, $multiplication, $value, $type ) = @_;

  my $dump      = RRDDump->new($rrd);
  my @dump_data = $dump->get_metric( $metric, 180 );

  my @learn_data = create_learn_data( \@dump_data );

  if ( scalar @learn_data <= 19 ) {
    return -2;
  }

  my $seasons = get_seasons( scalar @learn_data );

  my $prediction = Prediction->new( \@learn_data, $seasons, '365' );
  $prediction->set_parameters( $initial_alfa, $initial_beta, $initial_gamma );
  $prediction->learn_parameters( $initial_learn_alg, $initial_iterations, \@dump_data );

  $prediction->set_data( \@dump_data );
  my $rc = $prediction->prediction_find_and_export( $value, 365, $type, $multiplication );

  return $rc;
}

sub check_array_data {
  my @data = @{ $_[0] };

  my $array_length = scalar @data;
  for my $i ( 0 .. $array_length - 1 ) {
    if ( ( !defined $data[$i] || !looks_like_number( $data[$i] ) ) && $i >= 1 && ( defined $data[ $i - 1 ] && looks_like_number( $data[ $i - 1 ] ) ) ) {
      $data[$i] = $data[ $i - 1 ];
    }
  }

  return @data;
}

sub export_get_days_to_value_by_array {
  my @data           = @{ $_[0] };
  my $multiplication = $_[1];
  my $value          = $_[2];
  my $type           = $_[3];

  @data = check_array_data( \@data );

  my @learn_data = create_learn_data( \@data );

  if ( scalar @learn_data <= 19 || scalar @data <= 29 ) {
    return -2;
  }

  my $seasons = get_seasons( scalar @learn_data );

  my $prediction = Prediction->new( \@learn_data, $seasons, '365' );

  $prediction->set_parameters( $initial_alfa, $initial_beta, $initial_gamma );

  if ( scalar @learn_data >= 60 ) {
    $prediction->learn_parameters( $initial_learn_alg, $initial_iterations, \@data );
  }

  $prediction->set_data( \@data );
  my $rc = $prediction->prediction_find_and_export( $value, 365, $type, $multiplication );

  return $rc;
}

1;
