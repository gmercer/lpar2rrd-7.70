package PowercmcLoadDataModule;

use strict;
use warnings;
use Data::Dumper;
use Date::Parse;
use Socket;
use JSON;
use Time::Local;
use LWP::UserAgent;
use HTTP::Request;
use RRDp;

use FindBin;
use lib "$FindBin::Bin";

my $lpar2rrd_dir;
$lpar2rrd_dir = $ENV{"INPUTDIR"} || Xorux_lib::error("INPUTDIR is not defined")     && exit;

my $rrdtool = $ENV{RRDTOOL};

sub collect_hmc {
  
}

#-----------------------------------------------------------------------------------
# REQUEST
# All API calls are automatically rate limited to a maximum of 10 calls per second.
#-----------------------------------------------------------------------------------
#sub general_hash_request {
#  my $method = shift;
#  my $query = shift;
#  my $proxy = shift;
#  print "$method $query\n";
#  my $ua    = LWP::UserAgent->new( ssl_opts => { SSL_cipher_list => 'DEFAULT:!DH',
#                                                 verify_hostname => 0,
#                                                 SSL_verify_mode => 0 } );
#
#  # PROXY is global variable
#  if ($proxy){
#    # expected proxy format: http://host:port
#    $ua->proxy( ['http', 'https', 'ftp'] => $proxy );
#  }
#
#  my $req = HTTP::Request->new( $method => $query );
#
#  $req->header( 'X-CMC-Client-Id'     => "$CMC_client_id" );
#  $req->header( 'X-CMC-Client-Secret' => "$CMC_client_secret" );
#  $req->header( 'Accept'              => 'application/json' );
#
#  my $res = $ua->request($req);
#
#  my %decoded_json;
#
#  eval{
#
#    eval{
#      %decoded_json = %{decode_json($res->{'_content'})};
#    };
#    if($@){
#      my $error_message = "";
#      $error_message .= "PROBLEM OCCURED during decode_json HASH with url $query!" ;
#      $error_message .= "\n --- RESULT->_content --- \n $res->{'_content'} \n";
#      print "$error_message";
#      #Xorux_lib::error($error_message);
#      return ()
#    }
#
#  };
#  if($@){
#    print "\n $res->{'_content'} \n";
#  }
#
#  return %decoded_json;
#}
#-----------------------------------------------------------------------------------
#-----------------------------------------------------------------------------------
use Time::Local;
sub cmc_time2unix{
  # CMC format
  # 2023-04-27T12:00:00.000Z
  # >>
  # UNIX format
  # 1682589600
  my $time_string = shift;

  my $unix_time;

  if ($time_string =~ /(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):(\d{2})/){
    $unix_time = timelocal(0,$5,$4,$3,$2-1,$1);
  }

  return $unix_time;
}

#-----------------------------------------------------------------------------------
#-----------------------------------------------------------------------------------
# TIME HANDLING
# OUT: $StartTS, $EndTS
#-----------------------------------------------------------------------------------
sub time_start_end{
  my ( $sec, $min, $hour, $day, $month, $year, $wday, $yday, $isdst );
  my $use_time = time();
  my $time = $use_time;
  my $secs_delay = 3600 * 4;
  my $start_time = $use_time - $secs_delay;
  ( $sec, $min, $hour, $day, $month, $year, $wday, $yday, $isdst ) = localtime($start_time);
  
  my $StartTS = sprintf( "%4d-%02d-%02dT%02d:%02d:00Z", $year + 1900, $month + 1, $day, $hour, 0 );
  #print $StartTS;
  
  my $end_time = $use_time;
  ( $sec, $min, $hour, $day, $month, $year, $wday, $yday, $isdst ) = localtime($end_time);
  
  my $EndTS = sprintf( "%4d-%02d-%02dT%02d:%02d:00Z", $year + 1900, $month + 1, $day, $hour, 0 );
  #print $EndTS;
  return ($StartTS, $EndTS);
}
#-----------------------------------------------------------------------------------
#-----------------------------------------------------------------------------------
# RRD CREATE AND UPDATE
#-----------------------------------------------------------------------------------
sub rrdLast_timestamp {
  my $rrd   = shift;
  my $ltime;
  my $last_rec = "";
  my $rrd_read;
  my $rrd_state;

  RRDp::start "$rrdtool";

  eval {
    RRDp::cmd qq(last "$rrd" );
    $last_rec = RRDp::read;
  };
  if ($@) {
    RRDp::end;
    return ( "" );
  }
  print "$rrd";
  print "\n last time: ${$last_rec}\n";
  my $last_time = ${$last_rec};
  RRDp::end;
  return ($last_time);
}

sub rrdUpdate {
  my $rrd   = shift;
  my $time  = shift;
  my $stats = shift;
  my $ltime;
  my $last_rec = "";
  my $rrd_read;
  my $rrd_state;
  my $last_time = rrdLast_timestamp($rrd);

  RRDp::start "$rrdtool";


  #if ( Xorux_lib::isdigit($time) && Xorux_lib::isdigit($last_time) && $time > $last_time ) {
  if ( $time > $last_time ) {
    RRDp::cmd qq(update "$rrd" $time:$stats);
    my $answer = RRDp::read;
    RRDp::end;
    return ( $time );
  }

  RRDp::end;
  return ( "" );
}

sub rrdCreate {
  my $rrd     = shift;
  my $time    = shift;
  my @header = @_;

  RRDp::start "$rrdtool";

  my $rrd_time = $time ;
  my $RRD_string;

  my $step    = 300;
  my $prop;
  $prop->{heartbeat}         = 1380;     # says the time interval when RRDTOOL consideres a gap in input data, usually 3 * 5 + 2 = 17mins
  $prop->{first_rra}         = 1;        # 5min
  $prop->{second_rra}        = 12;       # 1h
  $prop->{third_rra}         = 72;       # 5 h
  $prop->{forth_rra}         = 288;      # 1day
  $prop->{five_mins_sample}  = 25920;    # 90 days
  $prop->{one_hour_sample}   = 4320;     # 180 days
  $prop->{five_hours_sample} = 1734;     # 361 days, in fact 6 hours
  $prop->{one_day_sample}    = 1080;     # ~ 3 years


  $RRD_string = "create $rrd --start $rrd_time --step $step ";

  for my $variable_name (@header) {
    $RRD_string .= "DS:$variable_name:GAUGE:$prop->{heartbeat}:0:10000000000 ";
  }

  $RRD_string .= "RRA:AVERAGE:0.5:$prop->{first_rra}:$prop->{five_mins_sample} ";
  $RRD_string .= "RRA:AVERAGE:0.5:$prop->{second_rra}:$prop->{one_hour_sample} ";
  $RRD_string .= "RRA:AVERAGE:0.5:$prop->{third_rra}:$prop->{five_hours_sample} ";
  $RRD_string .= "RRA:AVERAGE:0.5:$prop->{forth_rra}:$prop->{one_day_sample} ";
  #print ("\n $RRD_string \n");
  RRDp::cmd qq($RRD_string);
  #my $answer = RRDp::read;

#  if ( !Xorux_lib::create_check("file: $rrd, $prop->{five_mins_sample}, $prop->{one_hour_sample}, $prop->{five_hours_sample}, $prop->{one_day_sample}") ) {
#    Xorux_lib::error( "create_rrd err : unable to create $rrd (filesystem is full?) at " . __FILE__ . ": line " . __LINE__ );
    RRDp::end;
    return 1;
  #}
 #RRDp::end;
 #return 0;
}


1;
