#
# LPAR2RRD agent daemon
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation.

# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.

# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 675 Mass Ave, Cambridge, MA 02139, USA.

#
# set DEBUG=3 in etc/lpar2rrd.cfg to get verbose logging in etc/daemon.out
# touch tmp/as400-debug to have debug info in logs/as400-debug.txt
# touch tmp/solaris-debug to have debug info in logs/solaris-debug.txt

use strict;
use RRDp;
use Date::Parse;
use IO::Socket::INET;
use File::Copy;
use File::Compare;
use File::Basename;
use Xorux_lib;
use XoruxEdition;
use Data::Dumper;
use POSIX ":sys_wait_h";
use Xorux_lib qw(read_json write_json uuid_big_endian_format);
use File::Glob qw(bsd_glob GLOB_TILDE);
use PowerDataWrapper;
use MIME::Base64 qw(encode_base64 decode_base64);

my $timeout = 600;    # timeout for each $transfer_rows_lim_per_alert transfered rows

# --> temporary increased for debiging --PH
my $transfer_rows_lim_per_alert = 100;
my $timeout_glob                = 0;
my $trasfered_rec               = 0;
my $version                     = "$ENV{version}";
my $rrdtool                     = $ENV{RRDTOOL};
my $DEBUG                       = $ENV{DEBUG};

#$DEBUG=2;
my $pic_col = $ENV{PICTURE_COLOR};
my $STEP    = $ENV{SAMPLE_RATE};
my $port    = $ENV{LPAR2RRD_AGENT_DAEMON_PORT};
my $basedir = $ENV{INPUTDIR};
my $tmpdir  = "$basedir/tmp";
my $bindir  = $ENV{BINDIR};
if ( defined $ENV{TMPDIR_LPAR} ) {
  $tmpdir = $ENV{TMPDIR_LPAR};
}
my $actprogsize    = -s "$basedir/bin/lpar2rrd-daemon.pl";
my $wrkdir         = "$basedir/data";
my $error_first    = 0;                                      # report only first error occurence in the data
my $rrdcached      = 0;                                      # RRDTOOL cached global
my $rrdcached_pipe = "unix:$basedir/tmp/.sock-lpar2rrd";
my $cache;

#require SQLiteDataWrapper only if XORMON=1 - cannot use 'use SQLiteDataWrapper.pm' when e.g. not installed DBI module
if ( defined $ENV{XORMON} && $ENV{XORMON} ) {

  #require "$basedir/bin/SQLiteDataWrapper.pm";
  require SQLiteDataWrapper;
}

my $log_err   = "L_ERR";
my $log_err_v = "";

# my $catch_osdata = $ENV{CATCH_OSAGENT_DATA};             # used later in this script
# save raw OS agent data to dir tmp/osagent_data/, if ENV variable is set to '1' - all agents, or to initial agent string e.g. '9117-MMC*44K8102:aix1:5'

my $listen = $ENV{LPAR2RRD_AGENT_DAEMON_IP};
if ( $listen eq '' ) {
  $listen = "0.0.0.0";
}

`echo "$$" > "$basedir/tmp/lpar2rrd-daemon.pid"`;

# standard data retentions
my $one_minute_sample = 86400;
my $five_mins_sample  = 25920;
my $one_hour_sample   = 4320;
my $five_hours_sample = 1734;
my $one_day_sample    = 1080;
load_retentions( $STEP, $basedir );

my $lpar = "";    # global one as well to do not check out cpu.cfg every time for lpar name

if ( $port eq '' ) {
  $port = 8162;    # IANA LPAR2RRD registered port
}

# Input limits for RRDTool files
# It must be there to avoid peaks caused by reseting counters
my $INPUT_LIMIT_PGS     = 500000;         # 500MB/sec
my $INPUT_LIMIT_LAN     = 12500000000;    # 125Gbits/sec
my $INPUT_LIMIT_PCK_LAN = 125000000;      # Packets
my $INPUT_LIMIT_SEA     = 12500000000;    # 125Gbits/sec
my $INPUT_LIMIT_PCK_SEA = 12500000;       # Packets
my $INPUT_LIMIT_SAN1    = 12800000000;    # 128Gbits/sec
my $INPUT_LIMIT_SAN2    = 1000000;        # IOPS

my $first_mem  = 0;
my $first_pgs  = 0;
my $first_lan  = 0;
my $first_san  = 0;
my $first_sea  = 0;
my $first_wlm  = 0;
my $first_ame  = 0;
my $first_cpu  = 0;
my $first_que  = 0;
my $first_lpar = 0;

my %first_update    = ();    # for version 50
my %inventory_alert = ();

# flush after every write
$| = 1;

my ( $socket,      $client_socket );
my ( $peeraddress, $peerport );
my $last_peer_address      = "";    # is changed during first cycle, so it can be tested for first/other run for this peer
                                    # usually it is only one peer during session, but can be some test data
my $ldom_with_uuid_touched = "";    # for avoding not necessary code for Solaris with uuid

# creating object interface of IO::Socket::INET modules which internally does
# socket creation, binding and listening at the specified port address.
$socket = new IO::Socket::INET(
  LocalHost => $listen,
  LocalPort => $port,
  Proto     => 'tcp',
  Listen    => 10000,
  ReuseAddr => 1

    #Reuse     => 1 --> it is not recognized by newer IO::Socket::IP 0.39 , note IO::Socket::IP is used everywhere except AIX (it is replaced during install/upgrade)
) || error( "ERROR in Socket Creation listen:$listen, port:$port: $!\n" . __FILE__ . ":" . __LINE__ ) && exit(1);

setsockopt( $socket, SOL_SOCKET, SO_REUSEADDR, 1 ) || error( "Can't set socket option to SO_REUSEADDR $!" . __FILE__ . ":" . __LINE__ ) && exit(1);

print_it("LPAR2RRD server ($actprogsize) waiting for client connections on $listen:$port");

# start RRD via a pipe
# RRDp::start "$rrdtool"; --> no, start it in fors
#$RRDp::error_mode = 'catch';

my $error_flag       = 0;
my $protocol_version = 0;
my $peer_address     = "";
my $name             = "";
my $peer_port        = "";
my $cpu_hz_glo       = 0;    # keep CPU HZ and save it just once per a run

# $client_socket  is the global variable which has the recent file descriptor
# on which the send/receive operation is tried.
# the daemon exits on SIGPIPE when tries to send data to non existing connection
### Handle the PIPE
$SIG{PIPE} = sub {
  ####If we receieved SIGPIPE signal then call Disconnect this client function
  error("Received SIGPIPE in main , removing a client ...");
  unless ( defined $client_socket ) {
    error("No clients to remove!");
  }
  else {
    #$Select->remove($client_socket);
    $client_socket->close;
  }
};

# run waitpid if process is killed anyhow to do not leave zombies
#$SIG{INT} = 'catch_sig'; # do not use it here
$SIG{TERM} = 'catch_sig';
$SIG{QUIT} = 'catch_sig';
$SIG{SEGV} = 'catch_sig';
$SIG{SYS}  = 'catch_sig';
$SIG{BUS}  = 'catch_sig';

my $fork_no           = 0;
my $LPAR2RRD_FORK_MAX = 50;
if ( defined $ENV{LPAR2RRD_FORK_MAX} && isdigit( $ENV{LPAR2RRD_FORK_MAX} ) ) {
  $LPAR2RRD_FORK_MAX = $ENV{LPAR2RRD_FORK_MAX};
}
my @pid          = "";
my $server_count = $LPAR2RRD_FORK_MAX;
for ( my $j = 0; $j < $LPAR2RRD_FORK_MAX; $j++ ) {
  $pid[$j] = 0;    # initiallize for PID array
}
my $number_cycles = 0;

while (1) {

  # normal behaviour, no error detected
  # waiting for new client connection.
  $client_socket = $socket->accept();

  unless ( defined $client_socket ) {
    error("Accept problem, continuing with other connection ... ");
    next;
  }

  # use alert because of: "getpeername resumed>0x144b4e0, [256]) = -1 ENOTCONN" and crash
  eval {
    # get the host and port number of newly connected client.
    $peer_address = $client_socket->peerhost();

    #$name = gethostbyaddr($peer_address, AF_INET );
    $peer_port = $client_socket->peerport();
  };

  chomp($@);
  if ($@) {
    error( "Client connection crashed after accept : $@ " . __FILE__ . ":" . __LINE__ );
  }

  #print "001 $peer_address - $peer_port ".localtime()."\n";
  #if ($peer_address eq "10.22.33.8") {
  #  print "$peer_address goes next\n";
  #  next;
  #}

  # flush after every write
  $| = $client_socket;

  # waitpid for every fork
  my $fork_active = 0;
  my $act_time    = localtime();
  for ( my $j = 0; $j < $LPAR2RRD_FORK_MAX; $j++ ) {
    if ( $pid[$j] > 1 ) {
      my $res = waitpid( $pid[$j], WNOHANG );
      print "Wait for chld  : $res : $j : $pid[$j] : $act_time\n" if $DEBUG == 3;
      if ( $res == $pid[$j] ) {
        if ( $fork_no > 0 ) {
          $fork_no--;
        }
        $pid[$j] = 0;
      }
      else {
        $fork_active++;
      }
    }
  }
  $fork_no = $fork_active;

  # controll number of forks, do not allow run more than LPAR2RRD_FORK_MAX
  # if it reaches LPAR2RRD_FORK_MAX then wait until some processes finishes
  while ( $fork_no == $LPAR2RRD_FORK_MAX ) {
    $fork_active = 0;
    $act_time    = localtime();
    for ( my $j = 0; $j < $LPAR2RRD_FORK_MAX; $j++ ) {
      if ( $pid[$j] > 1 ) {
        my $res = waitpid( $pid[$j], WNOHANG );
        print "Wait for chld  : $res : $j : $pid[$j] : $act_time \n" if $DEBUG == 3;
        if ( $res > 0 ) {
          if ( $fork_no > 0 ) {
            $fork_no--;
          }
          $pid[$j] = 0;
        }
        else {
          $fork_active++;
        }
      }
      else {
        if ( $fork_no > 0 ) {
          $fork_no--;    # just to be sure that it has never ends up in endless loop
        }
      }
    }
    if ( $fork_no == $LPAR2RRD_FORK_MAX ) {
      sleep(1);    # wait 1 sec and check again if there is not available free slot for fork
    }
  }

  $act_time = localtime();
  print "Active forks   : $fork_active : $act_time\n" if $DEBUG == 3;

  # every 1000 cycles run waitpid just to be sure there are not zombies
  if ( $fork_active == 0 && $number_cycles > 1000 ) {
    my $ret = waitpid( -1, WNOHANG );
    print "waitpid -1     : $fork_active : $number_cycles : $ret\n" if $DEBUG == 3;
    $number_cycles = 0;
  }
  $number_cycles++;

  #print "002 $peer_address : going for fork\n";

  # find free free slot for fork
  my $i = 0;
  while ( $i < $LPAR2RRD_FORK_MAX ) {
    if ( $pid[$i] == 0 ) {
      $server_count = $i;
      last;
    }
    $i++;
  }
  if ( $server_count == $LPAR2RRD_FORK_MAX ) {

    # something went wrong, has not been found any free slot, it should not happen
    error( "Client connection fork error for  client: $name ($peer_address)  : $server_count : $pid[$i] " . __FILE__ . ":" . __LINE__ );
    close($client_socket);
    next;
  }

  #print "003 $peer_address : going for fork : $server_count\n";

  # fork here
  $pid[$server_count] = fork();
  if ( not defined $pid[$server_count] ) {
    error( "Fork failed : $! : client: $name ($peer_address) " . __FILE__ . ":" . __LINE__ );
    close($client_socket);
    next;
  }
  elsif ( $pid[$server_count] == 0 ) {
    my $act_time = localtime();
    print "Fork           : $$ : $act_time : $name ($peer_address) : $server_count \n" if $DEBUG == 3;
    execute_client( $client_socket, $peer_address, $name, $peer_port );
    $act_time = localtime();
    print "Fork exit      : $$ : $act_time : $name ($peer_address) : $server_count\n" if $DEBUG == 3;
    exit(0);
  }
  $fork_no++;
}

exit(0);

sub execute_client {
  my $client_socket = shift;
  my $peer_address  = shift;
  my $name          = shift;
  my $peer_port     = shift;

  # SIGPIPE when tries to send data to non existing connection
  ### forked process must exit on it in compare to the daemon, therefore new rutine with exit at the end
  $SIG{PIPE} = sub {
    ####If we receieved SIGPIPE signal then call Disconnect this client function
    error("Received SIGPIPE in sub execute_client, removing a client ($peer_address) ...");
    unless ( defined $client_socket ) {
      error("No clients to remove!");
    }
    else {
      #$Select->remove($client_socket);
      $client_socket->close;
    }
    exit(1);
  };

  $log_err_v = premium();

  #my $psef = `ps -ef|grep lpar2rrd-daemon|grep -v grep`;
  #print "$psef $peer_address\n\n";

  my $error_flag = 0;
  $cpu_hz_glo    = 0;    # reset it for every connection
  $timeout_glob  = 0;
  $trasfered_rec = 0;

  my $cached_no = 0;
  if ( defined $ENV{LPAR2RRD_CACHE_NO} && isdigit( $ENV{LPAR2RRD_CACHE_NO} ) ) {
    $cached_no = $ENV{LPAR2RRD_CACHE_NO};
  }

  RRDp::start "$rrdtool";    # it must always run to handle cmds like: last, create
  if ( $cached_no == 0 && ( $cache = Xorux_lib->RRD_new("$rrdcached_pipe") ) ) {
    $rrdcached = 1;
  }
  print "RRDcached      : $$ : $rrdcached \n" if $DEBUG == 3;

  while (1) {

    # use alert here to be sure it does not hang due to 1 hanging connection
    eval {
      my $act_time = localtime();
      local $SIG{ALRM} = sub { die "$act_time: died in SIG ALRM: $name ($peer_address)"; };
      alarm($timeout);
      read_client( $client_socket, $peer_address, $name, $peer_port, $error_flag );
      alarm(0);
    };
    alarm(0);

    chomp($@);
    if ($@) {
      if ( $@ =~ m/died in SIG ALRM/ ) {
        error( "Client connection timed out after : $timeout seconds - client: $name ($peer_address) [$timeout_glob:$trasfered_rec] " . __FILE__ . ":" . __LINE__ );
      }
      else {
        if ( $@ =~ m/illegal attempt to update/ ) {

          # when a problem with the insert time then confirm the time as ok
          my $time_err = $@;
          $time_err =~ s/^.*to update using time //;
          $time_err =~ s/ when last update time is.*$//;
          error("Client comunication failed - client: $name ($peer_address): $@ : sending ok time anyway : $time_err :");
          print $client_socket "$time_err\n";
          $error_flag = 1;
          next;    # go to next loop to read same client data until the end
        }
        else {
          error("Client communication failed - client: $name ($peer_address): $@ ");
        }
      }
    }
    close($client_socket);
    if ( $rrdcached == 1 ) {
      $cache->RRD_done();
    }
    RRDp::end;
    return 0;
  }
  RRDp::end;
}

sub read_client {
  my $client_socket        = shift;
  my $peer_address         = shift;
  my $name                 = shift;
  my $peer_port            = shift;
  my $error_flag           = shift;
  my $act_time             = localtime();
  my $protocol_version_org = "";

  if ( $error_flag == 0 ) {

    # normal behaviour where there was not an error and not necessary to read the client data until the end
    # read protocol version
    my $protocol_version_tmp = <$client_socket>;

    chomp($protocol_version_tmp);
    if ( !defined($protocol_version_tmp) || $protocol_version_tmp eq '' ) {
      print $client_socket "Protocol error: not defined or empty protocol_version_tmp\n";
      error( "Received bad conn from:$name ($peer_address) : port:$peer_port : $protocol_version_tmp " . __FILE__ . ":" . __LINE__ );
      return 1;
    }

    chomp($protocol_version_tmp);
    $protocol_version     = substr( $protocol_version_tmp, 0, 3 );    # must be Global one
    $protocol_version_org = $protocol_version;
    print STDERR "$act_time conn from:$name ($peer_address) : port:$peer_port protocol: $protocol_version\n" if $DEBUG == 2;

    if ( !defined($protocol_version) || $protocol_version eq '' ) {
      print $client_socket "Protocol error: $protocol_version\n";
      error( "Received bad conn from:$name ($peer_address) : port:$peer_port : $protocol_version_tmp " . __FILE__ . ":" . __LINE__ );
      return 1;
    }

    if ( isdigit($protocol_version) == 0 ) {
      print $client_socket "Protocol error: $protocol_version\n";
      $protocol_version =~ s/([^A-Za-z0-9\+-_])/sprintf("%%%02X",ord($1))/seg;    # to make it readable in logs
      error( "Received bad conn from:$name ($peer_address) : port:$peer_port : $protocol_version " . __FILE__ . ":" . __LINE__ );
      return 1;
    }
    $protocol_version = $protocol_version * 10;

    print "$act_time: Received conn  : $name ($peer_address) :$peer_port : $protocol_version\n" if $DEBUG == 2;

    # new protocol version handshake, send version of LPAR2RRD server
    if ( $protocol_version >= 50 ) {
      print $client_socket "$protocol_version_org\n";                             # hash when manually debugging as400
    }
  }

  # read data, all records
  my $last_rec     = 0;    # it must be zeroed here for each new connection, but not for each row in the connection
  my $returned_rec = 0;    # it must be zeroed here , it might be different than last_rec
  $lpar = "";              # global one as well to do not check out cpu.cfg every time for lpar name

  my $read_rec = 0;        # counter of read records
  $error_first = 0;        # report only first error occurence in the data

  # zero it for avery client connection
  $first_mem  = 0;
  $first_pgs  = 0;
  $first_lan  = 0;
  $first_san  = 0;
  $first_sea  = 0;
  $first_wlm  = 0;
  $first_ame  = 0;
  $first_cpu  = 0;
  $first_que  = 0;
  $first_lpar = 0;

  # for alerting
  my $type_alr   = "";
  my $server_alr = "";
  my $lpar_alr   = "";
  my $check_nmon = "";
  my $skip_alert = 0;
  #

  while ( my $data = <$client_socket> ) {
    chomp($data);
    $read_rec++;
    $trasfered_rec++;

    # for Solaris this must be zeroed for every data line
    $ldom_with_uuid_touched = "";

    # for alerting
    my @datar = split( /:/, $data );

    # Docker check
    if ( $datar[0] eq "Docker" || $datar[0] eq "Docker-container" || $datar[0] eq "Docker-volume" ) {
      use Docker;

      $skip_alert = 1;
      my @parts      = split( '\|', $data );
      my @line_parts = split( ':',  $parts[0] );
      my $rt         = Docker::save( $line_parts[0], $line_parts[1], $line_parts[2], $line_parts[3], $parts[1], $peer_address );
      print $client_socket "$rt\n";
      next;
    }

    if ( defined $datar[0] && $datar[0] ne "" ) {
      $server_alr = $datar[0];
    }
    if ( defined $datar[1] && $datar[1] ne "" ) {
      $lpar_alr = $datar[1];
    }
    if ( defined $datar[10] && $datar[10] ne "" ) {
      $type_alr = $datar[10];
    }
    $check_nmon = $datar[9];
    #

    if ( $read_rec > $transfer_rows_lim_per_alert ) {

      # set new alarm for comming data to let proccess even big amount of stored data on the client
      $read_rec = 0;
      alarm($timeout);
      $timeout_glob = $timeout_glob + $timeout;
    }

    if ( $data eq '' || length($data) < 20 ) {
      $data             =~ s/([^A-Za-z0-9\+-_])/sprintf("%%%02X",ord($1))/seg;    # to make it readable in logs
      $protocol_version =~ s/([^A-Za-z0-9\+-_])/sprintf("%%%02X",ord($1))/seg;    # to make it readable in logs
      error( "Received bad data from:$name ($peer_address) : port:$peer_port : protocol:$protocol_version : data:$data " . __FILE__ . ":" . __LINE__ );
      last;
    }

    # print "442 lpar2rrd-daemon.pl \$data $data\n";

    my $filename_to_save_osagent_data = "";

    if ( $protocol_version == 63 ) {
      $returned_rec = store_data_63( \$data, $last_rec, $protocol_version, $peer_address );    # data se pointer !!
    }
    elsif ( $protocol_version >= 50 ) {
      $returned_rec                  = store_data_50( $data, $last_rec, $protocol_version, $peer_address );
      $filename_to_save_osagent_data = "$datar[0]:$datar[1]";
    }
    elsif ( $protocol_version < 20 ) {
      $returned_rec = store_data_10( $data, $last_rec, $protocol_version, $peer_address );
    }
    else {
      $returned_rec                  = store_data( $data, $last_rec, $protocol_version, $peer_address );
      $filename_to_save_osagent_data = "$datar[0]:$datar[1]:$datar[2]";
    }

    # save raw OS agent data, if ENV variable is set to 'ALL' - all agents data are logged to logs/daemon.log-daemon
    my $catch_osdata = $ENV{CATCH_OSAGENT_DATA};
    if ( defined $catch_osdata and $catch_osdata eq "ALL" ) {
      my $log_file = "$basedir/logs/daemon.log-daemon";
      my $fh;
      open( $fh, '>>', $log_file ) and print $fh "$data\n" and close $fh or error( "cannot write file $log_file: $! " . __FILE__ . ":" . __LINE__ );
    }

    # save raw OS agent data, if ENV variable is set to '1' - all agents, or to initial agent string e.g. '9117-MMC*44K8102:aix1:5'
    if ( defined $catch_osdata and ( $catch_osdata eq "1" or $catch_osdata eq $filename_to_save_osagent_data ) ) {
      if ( $filename_to_save_osagent_data ne "" ) {
        my $osagent_data_dir = "$tmpdir/osagent_data";
        if ( !-d $osagent_data_dir ) {
          mkdir($osagent_data_dir) || error( "cannot create dir $osagent_data_dir: $! " . __FILE__ . ":" . __LINE__ );
        }
        my $fh;
        my $full_filename = "$osagent_data_dir/$filename_to_save_osagent_data";
        open( $fh, '>>', $full_filename ) and print $fh "$data\n" and close $fh or error( "cannot write file $full_filename: $! " . __FILE__ . ":" . __LINE__ );
      }
    }

    #print "update data $data $last_rec $protocol_version $peer_address\n";

    # write answer (just time as confirmation that it has been stored in the DB)
    # print "Response to the agent: $returned_rec\n" ; #if $DEBUG ==  2;
    print $client_socket "$returned_rec\n";

    if ( $returned_rec == 0 ) {
      last;    # end as a fatal error appeared
    }
  }
  close($client_socket);

  if ( $skip_alert == 1 ) {
    return 1;
  }

  if ( $type_alr eq "N" ) {
    my $type = "NMON";
    alert( $server_alr, $lpar_alr, $type, $check_nmon, $peer_address, $protocol_version );
  }
  elsif ( $protocol_version != 63 ) {
    if ( $type_alr ne "H" ) {
      my $type = "LPAR";
      alert( $server_alr, $lpar_alr, $type, $check_nmon, $peer_address, $protocol_version );
    }
  }
  else {
    # nothing now for protokol 63
  }
  return 1;
}

# returns 0 - fatal error, original $time as OK
# $lpar is global variable where is the lpar name which was found out based on lpar_id
#  --> it is done once per a connection to do not do it for each record

sub store_data {
  my $data             = shift;
  my $last_rec         = shift;
  my $protocol_version = shift;
  my $peer_address     = shift;
  my $en_last_rec      = $last_rec;
  my $act_time         = localtime();
  my $DEBUG            = $ENV{DEBUG};
  $DEBUG = 2 if ( -f "$tmpdir/solaris-debug" );

  $wrkdir = "$basedir/data";    #cause this is changed by external NMON processing

  #example of $data here incl item names for docum purpose ! data is one line !
  # 8233-E8B*5383FP:BSRV21LPAR5-pavel:5:1392202714:Wed Feb 12 11:58:34 2014:::::
  # mem:::3932160:3804576:127584:1267688:2369200:1435376:
  # pgs:::0:0:4096:1:::
  # lan:en2:172.31.241.171:1418275448:444418173:::::
  # lan:en4:172.31.216.135:22069646900:1249033690:::::
  # san:fcs0:0xC050760329FB00C0:24671446454:16462307328:798417:1908861:::
  # san:fcs1:0xC050760329FB00C2:678475916:1048829952:22837:13854::
  # cpu:::1:2:0:0::

  # [server|serial]:lpar:lpar_id:time_stamp_unix:time_stamp_text:  #mandatory
  #      future_usage1:future_usage2:future_usage3:future_usage4:  #mandatory
  # other non-mandatory items depends on machine HW and SW
  # :mem:::$size:$inuse:$free:$pin:$in_use_work:$in_use_clnt
  # :pgs:::$page_in:$page_out:$paging_space:$pg_percent::
  # :lan:$en:$inet:$transb:$recb::::
  # :san:$line:$wwn:$inpb:$outb:$inprq:$outrq::
  # :ame:::$comem:$coratio:$codefic:::
  # :cpu:::$entitled:$cpu_sy:$cpu_us:$cpu_wa::
  # :sea:$back_en:$en:$transb:$recb::::

  # example for wlmstat
  # wlm:Unclassified:0.00:0.57:0.00:::::
  # wlm:Unmanaged:0.00:14.28:0.00:::::
  # wlm:Default:14.22:2.22:0.13:::::
  # wlm:Shared:0.00:0.74:0.00:::::
  # wlm:System:0.23:9.13:1.35:::::
  # wlm:test1lpar2rrd:0.00:0.00:0.00:::::
  # wlm:test2lpar2rrd:0.00:0.00:0.00:::::
  # wlm:test3lpar2rrd:0.00:0.00:0.00:::::
  # wlm:TOTAL:14.45:12.66:1.48::::

  # example of data from VIOS    one line
  # 8233-E8B*53840P:ASRV12VIOS1:1:1392643440:Mon Feb 17 14:24:00 2014:::::
  # mem:::3145728:2038184:1107544:1588236:1921944:116240:
  # pgs:::801001:899921:2048:9:::sea:ent1:ent28:0:4760483564:::::
  # sea:ent2:ent29:0:4760483564:::::sea:ent3:ent30:0:4760473500:::::
  # sea:ent4:ent31:0:4760483684:::::sea:ent5:ent32:0:4751724058:::::
  # sea:ent6:ent33:0:4751717266:::::sea:ent7:ent34:0:4751714234:::::
  # sea:ent8:ent35:0:4751723938:::::sea:ent0:ent36:26874:6254173249:::::
  # lan:en27:172.31.216.71:625267876023:1715959232831:::::
  # san:fcs0:0x20000000C9F0B32A:599641385932:1765316803092:184200748:463211964:::
  # san:fcs1:0x20000000C9F0B32B:8576634954676:281457862563932:146970574:8165833668:::
  # san:fcs2:0x20000000C9F0B3D6:17430139432091:25323018062172:429245470:720164002:::
  # san:fcs3:0x20000000C9F0B3D7:823034884094:3439309033364:310735998:887024242::
  # san_resp:vscsi0:wwn:75:50::::

  #  example for WPAR from OS
  #  8231-E2B*064875R:nim:2:1398844751:Wed Apr 30 09:59:11 2014::nim-wpar1:1::
  #  mem:::1572864:28672:1544192:624:20696:7976:pgs:::0:0:864:1:::lan:en1:192.168.1.4:::::::cpu:::0:68:32:-1::

  # example of HvmSh api
  # HITACHI:LP_17228783:HVM 02-57(00-02):1517209562:Mon Jan 29 08:06:02 2018 version 4.95-3:::::
  # HSYS:CPU::102400:1107:119:1.08:0.12::
  # HSYS:MEM::1048576:169984::16.21:::
  # HCPU:SYS1::16::344:0.34:0.05::
  # HCPU:SYS2::16::97:0.09:0.02::
  # HCPU:SHR_LPAR::16:102400:666:0.65:0.10::
  # HCPU:DED_LPAR::0:0:0:0.00:0.00::
  # HLPAR:oradih1dt1:1:276:4.31:0.04:2.80:88.10:19.49:
  # HLPAR:systst4:2:12:0.38:0.00:10.44:88.40:23.68:
  # HLPAR:sysrma1am1:3:33:0.26:0.01:29.79:52.04:23.08:
  # HLPAR:sysrma1dm1:4:38:0.30:0.01:19.75:70.52:16.67:
  # HLPAR:dmscon2at1:5:98:1.02:0.02:6.72:75.56:14.71:
  # HLPAR:oraext1dt1:6:209:6.53:0.03:1.72:90.82:12.40

  my $server    = "";
  my $lpar_name = "";
  my $lpar_id   = -1;
  my $wpar_name;
  my $wpar_id;
  my $time = "";

  # items count test

  my @datar = split( ":", $data . "sentinel" );
  $datar[-1] =~ s/sentinel$//;
  my $datar_len = @datar;

  #print Dumper \@datar;
  if ( ( $datar_len % 9 ) != 2 ) {
    if ( $protocol_version >= 50 ) {

      # AS400 can send one ":"
      $data =~ s/:$//;
      @datar = split( ":", $data . "sentinel" );
      $datar[-1] =~ s/sentinel$//;
      $datar_len = @datar;
      if ( ( $datar_len % 9 ) != 2 ) {
        if ( $datar_len > 3 && !$datar[3] eq '' && isdigit( $datar[3] ) ) {

          # try to skip over that error and send back right response == saved instead of stucking here for ever
          error( "$peer_address: not correct items count: $datar_len, $data : try return ok ($datar[3])" . __FILE__ . ":" . __LINE__ );
          return $datar[3];
        }
        else {
          error( "$peer_address: not correct items count: $datar_len, $data :" . __FILE__ . ":" . __LINE__ );
          return 0;
        }
      }
    }
    else {
      if ( $datar_len > 3 && !$datar[3] eq '' && isdigit( $datar[3] ) ) {

        # try to skip over that error and send back right response == saved instead of stucking here for ever
        error( "$peer_address: not correct items count: $datar_len, $data : try return ok ($datar[3])" . __FILE__ . ":" . __LINE__ );
        return $datar[3];
      }
      else {
        error( "$peer_address: not correct items count: $datar_len, $data :" . __FILE__ . ":" . __LINE__ );
        return 0;
      }
    }
  }

  return ( store_data_hmc( $data, $last_rec, $protocol_version, $peer_address ) ) if $datar[10] =~ /H/;    # possible hmc data

  # processing mandatory fieds means:
  # find out lpar name from lpar_id
  # db write time is in $time
  # prepare space proof server and lpar names

  $server  = $datar[0];
  $lpar    = $datar[1];
  $lpar_id = $datar[2];
  $time    = $datar[3];
  my $cpu_hz = $datar[7];
  $wpar_name = "none";
  $wpar_id   = 0;

  if ( $protocol_version >= 50 ) {
    chomp($data);
    print STDERR "003 data: $data\n";
    return $time;
  }

  # for EXT NMON there's no rules for Machine Type & Serial number > no test
  # for HMC data and INT NMON strict test for Machine & Serial
  # for INT NMON there are exceptions for standard linux/unix names

  if ( !( ( $datar[10] =~ /N/ ) && ( $datar[9] ne "" ) ) ) {    # not EXT NMON

    if ( ( !defined($server) ) || $server eq '' ) {
      error( "$peer_address: not valid server name: $datar_len, $data :" . __FILE__ . ":" . __LINE__ );
      return $datar[3];
    }
    if ( $server =~ m/NotAvailable$/ ) {

      # OS agent might sometimes report "NotAvailable" as its serial, it is wrong, skip it
      error( "$peer_address: not correct HW serial: $datar_len, $data :" . __FILE__ . ":" . __LINE__ );
      return $datar[3];
    }

    if ( $server =~ m/^SunOS/ || $server =~ m/^LINUX/ || $server =~ m/^UX-Solaris/ || $server =~ m/Linux/ ) {

      # General Linux and Solaris support
      if ( $server =~ m/Linux/ || $server =~ m/LINUX/ ) {
        $server = "Linux";
      }
      if ( $server =~ m/SunOS/ || $server =~ m/Solaris/ || $server =~ m/SOLARIS/ ) {
        $server = "Solaris";
      }
    }

    if ( $server =~ /HITACHI/ ) {
      $server = "Hitachi";
    }

    if ( !defined($server) || $server eq '' ) {    #
      error( "$peer_address: server identification is null: $datar_len, $data :" . __FILE__ . ":" . __LINE__ );
      return $datar[3];
    }
    ( my $machinetype, my $hw_serial ) = split( '\*', $server );

    if ( $server !~ m/Linux/ && $server !~ m/Solaris/ && $server !~ m/Hitachi/ ) {

      # IBM Power only
      if ( !defined($hw_serial) || $hw_serial eq '' ) {    # wrong HW serial
        error( "$peer_address: HW serial is null: $datar_len, $data :" . __FILE__ . ":" . __LINE__ );
        return $datar[3];
      }
      if ( ( length($hw_serial) > 7 ) || ( length($hw_serial) < 6 ) ) {    # old lpar version compatible
        error( "$peer_address: HW serial is longer > 7 or shorter < 6 chars: $datar_len, $data :" . __FILE__ . ":" . __LINE__ );
        return $datar[3];
      }
      if ( ( length($machinetype) > 8 ) || ( length($machinetype) < 8 ) ) {
        error( "$peer_address: Machine Type is longer > 8 or shorter < 8 chars: $datar_len, $data :" . __FILE__ . ":" . __LINE__ );
        return $datar[3];
      }
    }
  }

  # workaround for slash in server name
  my $slash_alias = "∕";    #hexadec 2215 or \342\210\225
  $server =~ s/\//$slash_alias/g;

  if ( ( $datar[10] =~ /N/ ) && ( $datar[9] ne "" ) ) {    # for EXT NMON
                                                           # do not use 'cached' when external NMON (NMON file grapher)
    $rrdcached = 0;
    $wrkdir .= "_all";
    $server .= $datar[9];
    if ( !-d "$wrkdir" ) {
      mkdir( "$wrkdir", 0755 ) || error( " Cannot mkdir $wrkdir: $! " . __FILE__ . ":" . __LINE__ ) && return 0;
    }

    my $f_query = "$tmpdir/ext-nmon-query-$datar[9]";
    open( DF_OUT, ">> $f_query" ) || error( "Cannot open for writing $f_query: $!" . __FILE__ . ":" . __LINE__ ) && return 0;
    print DF_OUT "server=$server--unknown&lpar=$lpar--NMON--&$time\n";
    close(DF_OUT);
    chmod 0777, $f_query || error( "Cannot set 777 for file $f_query: $!" . __FILE__ . ":" . __LINE__ );
  }
  else {
    if ( !$datar[8] eq '' ) {
      $wpar_name = $datar[8];
    }
    if ( !$datar[9] eq '' ) {
      $wpar_id = $datar[9];
    }
  }
  $server =~ s/====double-colon=====/:/g;
  $lpar   =~ s/=====double-colon=====/:/g;

  if ( $server eq '' ) {
    if ( $datar_len > 3 && !$datar[3] eq '' && isdigit( $datar[3] ) ) {

      # try to skip over that error and send back right response == saved instead of stucking here for ever
      error( "server is null: $datar_len, $data : $server : $lpar : $lpar_id : $time : try return ok ($datar[3]) " . __FILE__ . ":" . __LINE__ );
      return $datar[3];
    }
    else {
      error( "server is null: $datar_len, $data : $server : $lpar : $lpar_id : $time " . __FILE__ . ":" . __LINE__ );
      return 0;
    }
  }

  $cpu_hz_glo = save_cpu_ghz( $cpu_hz_glo, $cpu_hz, $server, $wrkdir );

  my $server_a = $server;

  # a bit trick how to find a symlink, there was a bug before 3.70 and agents transfered only 6 chars of serial (instead of 7)
  # in original constructions it is not a problem due to a "*" inside the link and shell usage <>
  my @servers = <$wrkdir/$server_a>;
  my $found   = 0;
  foreach my $file (@servers) {
    if ( -l "$wrkdir/$server_a" ) {
      $found = 1;
      last;
    }
  }

  if ( $server eq "Hitachi" ) {
    if ( !-d "$wrkdir/$server" ) {
      mkdir( "$wrkdir/$server", 0755 ) || error( " Cannot mkdir $wrkdir/$server: $!" . __FILE__ . ":" . __LINE__ ) && return 0;
    }
    $found = 1;
  }

  if ( $found == 0 ) {

    # sym link does not exist --> server is either not registered yet or full lpar without the HMC
    my $NOSERVER_SUFFIX = "--unknown";
    my $NOHMC           = "no_hmc";
    if ( !-d "$wrkdir/$server$NOSERVER_SUFFIX" ) {
      if ( $server !~ /Solaris|Solaris10|Solaris11/ ) {
        mkdir( "$wrkdir/$server$NOSERVER_SUFFIX", 0755 ) || error( " Cannot mkdir $wrkdir/$server: $!" . __FILE__ . ":" . __LINE__ ) && return 0;
        if ( !-e "$wrkdir/$server" ) {
          symlink( "$wrkdir/$server$NOSERVER_SUFFIX", "$wrkdir/$server" ) || error( " Cannot ln -s $wrkdir/$server$NOSERVER_SUFFIX $wrkdir/$server: $!" . __FILE__ . ":" . __LINE__ ) && return 0;
        }
        touch("$wrkdir/$server$NOSERVER_SUFFIX");
      }
    }
    if ( !-d "$wrkdir/$server/$NOHMC" ) {
      if ( $server !~ /Solaris|Solaris10|Solaris11/ ) {
        if ( !-e "$wrkdir/$server" ) {
          symlink( "$wrkdir/$server$NOSERVER_SUFFIX", "$wrkdir/$server" ) || error( " Cannot ln -s $wrkdir/$server$NOSERVER_SUFFIX $wrkdir/$server: $!" . __FILE__ . ":" . __LINE__ ) && return 0;
        }
        mkdir( "$wrkdir/$server/$NOHMC", 0755 ) || error( " Cannot mkdir $wrkdir/$server/$NOHMC: $!" . __FILE__ . ":" . __LINE__ ) && return 0;
        touch("$wrkdir/$server/$NOHMC");
      }
    }
    if ( $server !~ /Solaris|Solaris10|Solaris11/ ) {
      print_it("new server has been found and registered: $server (lpar=$lpar)");
    }
    if ( $server =~ /Solaris10|Solaris11/ ) {
      my $server_a = "Solaris";
      print_solaris_debug("===========================================================================================\n") if $DEBUG == 2;
      print_solaris_debug("DATA FROM AGENT: @datar\n")                                                                     if $DEBUG == 2;
      print_solaris_debug("===========================================================================================\n") if $DEBUG == 2;
      if ( !-d "$wrkdir/$server_a/" ) {
        mkdir( "$wrkdir/$server_a/", 0755 ) || error( " Cannot mkdir $wrkdir/$server_a/ $!" . __FILE__ . ":" . __LINE__ ) && return 0;
        touch("$wrkdir/$server_a/");
      }
      if ( !-d "$wrkdir/$server_a--unknown/" ) {
        mkdir( "$wrkdir/$server_a--unknown/", 0755 ) || error( " Cannot mkdir $wrkdir/$server_a/ $!" . __FILE__ . ":" . __LINE__ ) && return 0;
        touch("$wrkdir/$server_a--unknown/");
      }
    }
  }

  # find out lpar name from lpar_id if it has not been done yet
  # oit is a primary method to get the lpar name
  if ( !$lpar_id eq '' && isdigit($lpar_id) && $lpar_id !~ m/-/ ) {
    if ( $lpar_id != -1 ) {
      my $lpar_name_id = find_lpar_name( $server, $lpar_id );
      if ( !$lpar_name_id eq '' ) {
        $lpar = $lpar_name_id;    # lpar name from lparstat -i --> it does not have to be actual,
                                  # linux on power does not provide lpar name at all, only hostname
      }
    }
  }

  if ( $lpar eq '' && !$lpar_name eq '' && $lpar_id !~ m/-/ ) {

    # just make sure if lpar-id fails somehow then use transferred $lpar_name
    $lpar = $lpar_name;
  }

  if ( $lpar eq '' ) {
    error( "$peer_address: lpar name has not been found for client: $peer_address , server:$server, lpar_id:$lpar_id $datar[0]:$datar[1]:$datar[2]:$datar[3]:$datar[4]:$datar[5]:$datar[6]:$datar[7]" . __FILE__ . ":" . __LINE__ );
    return 0;
  }

  # save SMt info, must be here after lpar name detection
  save_smt( $cpu_hz, $server, $wrkdir, $lpar );

  print "$data\n" if $DEBUG == 2;

  if ( $datar[10] =~ /N/ ) {
    $lpar .= "--NMON--";

  }

  my $agent_version = "";
  ( undef, $agent_version ) = split( /version/, $datar[6] );
  $agent_version =~ s/-.*//g;
  $agent_version =~ s/\.//g;
  $agent_version =~ s/\s+//g;

  my $lpar_real = $lpar;
  $lpar_real =~ s/\//&&1/g;

  if ( $wpar_id > 0 ) {    # Attention wpar is coming
                           # trick is: lpar contains both names lpar/wpar
    $wpar_name =~ s/=====double-colon=====/:/g;
    $lpar .= "/$wpar_name";
    my $wpar_real = $wpar_name;
    $wpar_real =~ s/\//&&1/g;
    $lpar_real .= "/$wpar_real";
  }

  my $lpar_space = $lpar_real;
  if ( $lpar_real =~ m/ / ) {
    $lpar_space = "\"" . $lpar_real . "\"";    # it must be here to support space with lpar names
  }
  my $server_space = $server;
  if ( $server =~ m/ / ) {
    $server_space = "\"" . $server . "\"";     # it must be here to support space with server names
  }
  my $rrd_file = "";

  #
  # cycle for non-mandatory items
  #
  my %hitachi_lpar_uuids = ();
  my $cputop             = 0;     # index for creating & data storing in file '/JOB/cputop$cputop.mmm', same for cfg file
  my $cycle_var          = 11;    # is a pointer to data array

  while ( $datar[$cycle_var] ) {
    load_retentions( $STEP, $basedir );                            # must be here cus some items (CPUTOP) can change  retentions
    if ( $datar[$cycle_var] eq 'lpar' && $wrkdir !~ /_all$/ ) {    # ignore when not external NMON
      $cycle_var = $cycle_var + 9;
      next;
    }
    if ( $datar[$cycle_var] eq 'CPUTOP' ) {

      # print "836 CPUTOP indicated\n";
      #$cycle_var = $cycle_var + 9;
      # next
    }
    my $db_name = $datar[$cycle_var];    #prepare db name
    if ( $db_name eq "lan"
      || $db_name eq "san"
      || $db_name eq "san_resp"
      || $db_name eq "sea"
      || $db_name eq "wlm"
      || $db_name eq "HSYS"
      || $db_name eq "HMEM"
      || $db_name eq "lan_error"
      || $db_name eq "san_error" )
    {
      $db_name .= "-" . $datar[ $cycle_var + 1 ];
    }
    elsif ( $db_name eq 'CPUTOP' ) {
      $db_name = "JOB/cputop$cputop";
    }

    # add correct suffix
    if    ( $db_name =~ /JOB\/cputop/ )    { $db_name .= ".mmc"; }
    elsif ( $db_name =~ /HSYS|HCPU|HMEM/ ) { $db_name .= ".hrm"; }
    elsif ( $db_name =~ /HNIC/ )           { $db_name .= ".hnm"; }
    elsif ( $db_name =~ /HHBA/ )           { $db_name .= ".hhm"; }
    elsif ( $db_name =~ /^FS$/ )           { $db_name .= ".csv"; }
    elsif ( $db_name =~ /HLPAR/ ) {
      $db_name .= ".hlm";
      $hitachi_lpar_uuids{ $datar[ $cycle_var + 1 ] } = Xorux_lib::uuid_big_endian_format( $datar[ $cycle_var + 2 ] );
    }
    else { $db_name .= ".mmm"; }

    # remane Hitachi files
    $db_name =~ s/^HSYS/SYS/                                    if $db_name =~ /HSYS/;
    $db_name =~ s/^HMEM/MEM/                                    if $db_name =~ /HMEM/;
    $db_name =~ s/HCPU|HLPAR|HNIC|HHBA/$datar[$cycle_var + 1]/e if $db_name =~ /HCPU|HLPAR|HNIC|HHBA/;

    my $db_name_space = $db_name;
    $db_name_space =~ s/ /\\ /g;    #it should not be, just for sure

    my $wlm_super     = "";
    my $wlm_super_tmp = "";

    #print "???$datar[$cycle_var]:$datar[$cycle_var+1]:$datar[$cycle_var+2]:$datar[$cycle_var+3]:$datar[$cycle_var+4]:$datar[$cycle_var+5]:$datar[$cycle_var+6]:$datar[$cycle_var+7]\n";

    while ( !$datar[$cycle_var] eq "" && $datar[$cycle_var] =~ "wlm" ) {
      $wlm_super     = $datar[ $cycle_var + 1 ] if ( $datar[ $cycle_var + 5 ] eq "sup" );
      $db_name_space = $db_name;
      if ( $wlm_super && $datar[ $cycle_var + 5 ] eq "sub" ) {
        if ( $lpar_real  !~ $wlm_super ) { $lpar_real  .= "/$wlm_super" }    # if lpar name doesn't contain name of super class and current wlm class is subclass add super class to lpar name
        if ( $lpar_space !~ $wlm_super ) { $lpar_space .= "/$wlm_super" }

        if ( $wlm_super_tmp ne $wlm_super ) {
          $wlm_super_tmp = $wlm_super;
          $first_wlm     = 0;                                                #It will be first time for every superclass! because of colors
        }
      }
      elsif ( $datar[ $cycle_var + 5 ] eq "sup" ) {                          # name of super class will stay in lpar name remove it if current wlm is super class
        $lpar_real  =~ s/\/.*//g;
        $lpar_space =~ s/\/.*//g;
      }
      $rrd_file = "";
      my @files = <$wrkdir/$server_space/*/$lpar_space/$db_name_space>;
      foreach my $rrd_file_tmp (@files) {
        chomp($rrd_file_tmp);
        $rrd_file = $rrd_file_tmp;
        last;
      }
      if ( $rrd_file eq '' ) {
        my $ret2 = create2_rrd( $server, $lpar_real, $time, $server_space, $lpar_space, $db_name, $datar[10], $datar[8] );
        if ( $ret2 == 2 ) {
          return $time;    # when en error in create2_rrd but continue (2) to skip it then go here
        }
        elsif ( $ret2 == 0 ) {
          return $ret2;
        }

        # If rrd_file is created this will create wlm.col file and hard link it
        my $wlm_col_file = "";
        my @files        = <$wrkdir/$server_space/*/$lpar_space/$db_name>;
        foreach my $rrd_file_tmp (@files) {
          chomp($rrd_file_tmp);
          $wlm_col_file = $rrd_file_tmp;
          last;
        }
        unless ( $wlm_col_file =~ s/wlm-.*.mmm/wlm.col/g ) {    # If for some reason regex won't replace .mmm file -> wlm_col_file == 0 -> color wont be written prevent rewriting .mmm file
          $wlm_col_file = "";
        }

        # if file dont exist touch it and link it!
        if ( !-e $wlm_col_file ) {
          touch("$wlm_col_file");
          h_link( $wlm_col_file, $wrkdir );
        }
        @files = <$wrkdir/$server_space/*/$lpar_space/$db_name_space>;
        foreach my $rrd_file_tmp (@files) {
          chomp($rrd_file_tmp);
          $rrd_file = $rrd_file_tmp;
          last;
        }
      }

      if ( $last_rec == 0 ) {

        # construction against crashing daemon Perl code when RRDTool error appears
        # this does not work well in old RRDTOool: $RRDp::error_mode = 'catch';
        # construction is not too costly as it runs once per each load
        eval {
          RRDp::cmd qq(last "$rrd_file" );
          my $last_rec_rrd = RRDp::read;
          chomp($$last_rec_rrd);
          $last_rec = $$last_rec_rrd;
        };
        if ($@) {
          rrd_error( $@ . __FILE__ . ":" . __LINE__, $rrd_file );
          return 0;
        }
      }

      print "$act_time: Updating 2     : $server_space:$lpar_space - $rrd_file - last_rec: $last_rec\n" if $DEBUG == 2;
      my $step_info = $STEP;

      # find rrd database file step
      # print STDERR "find file step for \$rrd_file $rrd_file\n";
      RRDp::cmd qq("info" "$rrd_file");
      my $answer_info = RRDp::read;
      if ( $$answer_info =~ "ERROR" ) {
        error("Rrdtool error : $$answer_info");
      }
      else {
        my ($step_from_rrd) = $$answer_info =~ m/step = (\d+)/;
        if ( $step_from_rrd > 0 ) {
          $step_info = $step_from_rrd;
        }
      }

      if ( ( $last_rec + $step_info / 2 ) >= $time ) {

        #error("$server:$lpar : last rec : $last_rec + $STEP/2 >= $time, ignoring it ...".__FILE__.":".__LINE__);
        print "$act_time: Updating 2     : $last_rec : $time : $rrd_file\n" if $DEBUG == 2;
        return $time;    # returns original time, not last_rec
                         # --> no, no, it is not wrong, just ignore it!
      }

      print "$act_time: Updating 4     : $server_space:$lpar_space - $rrd_file - last_rec: $last_rec\n" if $DEBUG == 2;

      #
      # files update
      #

      # alias case structure
      print "$act_time: case struc : $rrd_file : $cycle_var : $datar[$cycle_var]\n" if $DEBUG == 2;
      my $answer     = "";
      my $nan        = "U";
      my $processed  = 0;
      my $update_ret = 1;

      if ( isdigit( $datar[ $cycle_var + 2 ] ) && isdigit( $datar[ $cycle_var + 3 ] ) && isdigit( $datar[ $cycle_var + 4 ] ) ) {
        $processed = 1;
        my $wlm_col_file = $rrd_file;
        unless ( $wlm_col_file =~ s/wlm-.*.mmm/wlm.col/g ) {    # If for some reason regex won't replace .mmm file -> wlm_col_file == 0 -> color wont be written prevent rewriting .mmm file
          $wlm_col_file = "";
        }
        ## H link color file when its create only!
        if ( $first_wlm == 0 ) {
          if ( $wlm_col_file ne "" ) {
            open( WLM, "> $wlm_col_file " ) || error( "Can't open $wlm_col_file: $! " . __FILE__ . ":" . __LINE__ ) && next;
            my $tmp_wlm = $db_name;
            print WLM "$tmp_wlm:$cycle_var\n";
            close(WLM);
          }

          # first insert through eval to be able to catch nwhatever error, next inserts with issues a new shell (eval)
          $first_wlm = 1;
          eval {
            $update_ret = rrd_update( "$rrd_file", "$time:$datar[$cycle_var+2]:$datar[$cycle_var+3]:$datar[$cycle_var+4]" );
            if ( $rrdcached == 0 ) { $answer = RRDp::read; }
          };
          if ( $update_ret == 0 || $@ ) {

            # error happened, zero the first_wlm to continue with eval
            $first_wlm = 0;
            if ( $error_first == 0 ) {
              error( " updating $server:$lpar : $rrd_file : update_ret=$update_ret : $@ " . __FILE__ . ":" . __LINE__ );    # print it only first time
            }
            $processed = 0;
          }
        }
        else {
          if ( $wlm_col_file ne "" ) {
            open( WLM, "< $wlm_col_file " ) || error( "Can't open $wlm_col_file: $! " . __FILE__ . ":" . __LINE__ ) && next;
            my @wlm_files = <WLM>;
            close(WLM);
            my @wlm_numbers;
            my $decide_num = 0;
            foreach my $wlm_by_one (@wlm_files) {
              my @wlm_splited = split( ":", $wlm_by_one );
              if ( $wlm_splited[1] == $cycle_var ) {
                $decide_num = 1;
              }
            }
            if ( $decide_num == 0 ) {
              open( WLM, ">> $wlm_col_file" ) || error( "Can't open $wlm_col_file: $! " . __FILE__ . ":" . __LINE__ ) && next;
              my $tmp_wlm = $db_name;
              print WLM "$tmp_wlm:$cycle_var\n";
              close(WLM);
            }
          }
          $update_ret = rrd_update( "$rrd_file", "$time:$datar[$cycle_var+2]:$datar[$cycle_var+3]:$datar[$cycle_var+4]" );
          if ( $rrdcached == 0 ) { $answer = RRDp::read; }
        }
      }

      # place item to skip to next line if you need to skip it
      my $item_to_skip = "";

      if ( $datar[$cycle_var] eq $item_to_skip ) {
        print "skip item : $datar[$cycle_var] $cycle_var : $time:$datar[$cycle_var+3]:$datar[$cycle_var+4]:$datar[$cycle_var+5]\n";
      }
      else {

        if ( $processed == 0 && $error_first == 0 ) {
          error( "Unprocessed data from agent : $server:$lpar : $datar[$cycle_var]:$datar[$cycle_var+1]:$datar[$cycle_var+2]:$datar[$cycle_var+3]:$datar[$cycle_var+4]:$datar[$cycle_var+5], only first error occurence is reported ) " . __FILE__ . ":" . __LINE__ );
          $error_first = 1;
        }
        print "000 : $datar[$cycle_var] $cycle_var : $time:$datar[$cycle_var+3]:$datar[$cycle_var+4]:$datar[$cycle_var+5] \n" if $DEBUG == 2;

        #   my $answer = RRDp::read;
        if ( $processed == 1 && $rrdcached == 0 && !$$answer eq '' && $$answer =~ m/ERROR/ ) {
          error( " updating $server:$lpar : $rrd_file : $$answer" . __FILE__ . ":" . __LINE__ );
          if ( $$answer =~ m/is not an RRD file/ ) {
            ( my $err, my $file, my $txt ) = split( /'/, $$answer );
            error( "Removing as it seems to be corrupted: $file" . __FILE__ . ":" . __LINE__ );
            unlink("$file") || error( "Cannot rm $file : $!" . __FILE__ . ":" . __LINE__ );
          }

          # continue here although some error apeared just to do not stuck here for ever
        }
      }

      $cycle_var = $cycle_var + 9;

      if ( $datar[$cycle_var] && $datar[$cycle_var] =~ "wlm" ) {
        $db_name = "$datar[$cycle_var]-$datar[$cycle_var+1].mmm";
      }
      $lpar_space =~ s/\/.*//;
      if ( !defined $db_name ) {    # if not defined or db_name is not FS than return
                                    #print "001 : $datar[$cycle_var] $cycle_var\n" if $DEBUG == 2;
        print "1151 finish storing data from agent\n" if $DEBUG == 2;

        # print "1259 \$time $time\n" if $datar[1] =~ "virtuals";
        return $time;               # return time of last record
      }
      elsif ( $db_name !~ "wlm" ) {

        #print "001 : $datar[$cycle_var] $cycle_var\n" if $DEBUG == 2;
        print "1151 finish storing data from agent\n" if $DEBUG == 2;

        # print "1259 \$time $time\n" if $datar[1] =~ "virtuals";
        return $time;               # return time of last record
      }

    }

    next if ( $db_name =~ "wlm" );                                                 #wlm data should not go further
    $rrd_file = "";
    my $ldom_exist       = "";
    my $ldom_uuid_zone   = "";
    my $host_id          = "";
    my @files            = <$wrkdir/$server_space/*/$lpar_space/$db_name_space>;
    my $hitachi_rrd_path = "$wrkdir/$server_space/$lpar_space/$db_name_space";     # Hitachi has different file structure
    if ( $server eq "Hitachi" ) {
      $rrd_file = -e $hitachi_rrd_path ? $hitachi_rrd_path : "";
      chomp($rrd_file);
    }
    else {
      foreach my $rrd_file_tmp (@files) {
        chomp($rrd_file_tmp);
        $rrd_file = $rrd_file_tmp;
        last;
      }
    }
    ##################### PART RENAME OLD STRUCTURE ################################ SOLARIS LDOM - UUID TXT / HOST ID TXT FOR IDENTIFY RIGHT LDOM
    my ( $cdom_name, $type_dom, $cdom_uuid, $host_id_cdom, $uuid_txt, $hostid_txt ) = "";

    #print "line1292: $datar[1](ip-$peer_address|$datar[$cycle_var]:$datar[$cycle_var+1]:$datar[$cycle_var+2]:$datar[$cycle_var+3]:$datar[$cycle_var+4]:$datar[$cycle_var+5]:$datar[$cycle_var+6]:$datar[$cycle_var+7]\n";
    if ( $datar[0] =~ /Solaris/ ) {

      #print "DATA_ROW:$datar[0],$datar[1],$datar[2],$datar[3],$datar[4],$datar[5],$datar[6],$datar[7]\n";
      #print "DATA_CYCLE VAR: $datar[ $cycle_var + 0 ],$datar[ $cycle_var + 1 ],$datar[ $cycle_var + 2 ],$datar[ $cycle_var + 3 ],$datar[ $cycle_var + 4 ]\n";
      if ( $agent_version >= 611 ) {    ### lpar2rrd-agent version must be higher than 6.11
        if ( $datar[2] =~ /\// ) {
          ( $type_dom, $cdom_uuid, $host_id_cdom ) = split( "\/", $datar[2] );
          chomp( $type_dom, $cdom_uuid );
          if ($host_id_cdom) {
            chomp $host_id_cdom;
          }
        }
        $cdom_name = $datar[1];
        my $old_cdom_name = "";
        if ( $datar[0] =~ /Solaris10/ && $type_dom =~ /cdom/ ) {    ### Solaris10 & cdom
                                                                    #$old_cdom_name = $datar[1];
          $old_cdom_name = $datar[ $cycle_var + 0 ];
        }
        else {
          $old_cdom_name = $datar[ $cycle_var + 0 ];
        }
        $old_cdom_name =~ s/_ldom//g;
        my $double_col = ":";
        ######## NO_LDOM servers - only Global zone #########
        if ( $type_dom eq "no_ldom" ) {
          $lpar_space    = "$cdom_name";
          $double_col    = "";
          $old_cdom_name = "";
          my $uuid_txt_no_ldom = "$wrkdir/Solaris/$lpar_space/uuid.txt";
          $hostid_txt = "$wrkdir/Solaris/$lpar_space/hostid.txt";
          my $no_ldom_touch1 = "$wrkdir/Solaris/$lpar_space/no_ldom";
          my $no_ldom_touch2 = "$wrkdir/Solaris--unknown/no_hmc/$lpar_space/no_ldom";
          if ( !-d "$wrkdir/Solaris/$lpar_space" ) {
            makex_path("$wrkdir/Solaris/$cdom_name$double_col$old_cdom_name") || error( "$peer_address:$server : cannot mkdir $wrkdir/Solaris/$cdom_name$double_col$old_cdom_name $!" . __FILE__ . ":" . __LINE__ ) && return 0;
          }
          if ( -d "$wrkdir/Solaris/$lpar_space/" ) {
            `touch "$no_ldom_touch1"`;
          }
          if ( -d "$wrkdir/Solaris--unknown/no_hmc/$lpar_space/" ) {
            `touch "$no_ldom_touch2"`;
          }
          my $time_file_cdom = 0;
          if ( -f $uuid_txt_no_ldom ) {
            $time_file_cdom = ( ( stat($uuid_txt_no_ldom) )[9] );
          }
          if ( $cdom_uuid && ( ( $time - $time_file_cdom ) > 86400 ) ) {
            open( FW, "> $uuid_txt_no_ldom" ) || error( "Can't open $uuid_txt_no_ldom : $! " . __FILE__ . ":" . __LINE__ ) && return 0;
            print FW "$cdom_uuid\n";
            close(FW);
          }
        }
        elsif ( $type_dom eq "zone" ) {
          $lpar_space = "$cdom_name";
          my $net_name          = "";
          my $uuid_ldom_in_file = "";
          my $hostid_in_file    = "";
          my $uuid_txt1         = "";
          my @uuid_files        = <$wrkdir/Solaris--unknown/no_hmc/*/uuid.txt>;    #### /
          my $real_ldom         = "";
          my ( undef, undef, $hostid ) = split( "\/", $datar[2] );                 #### undef position have host_id in future
          chomp($hostid);
          my $net_exist = 0;

          foreach my $file (@uuid_files) {
            $uuid_txt1 = $file;
            chomp $uuid_txt1;
            if ( -f "$uuid_txt1" ) {
              open( FC, "< $uuid_txt1" ) || error( "$peer_address:$server : cannot read $uuid_txt1: $!" . __FILE__ . ":" . __LINE__ );
              $uuid_ldom_in_file = <FC>;
              ( undef, undef, $hostid_in_file ) = split( "\/", $uuid_ldom_in_file );
              chomp($hostid_in_file);
              close(FC);
            }
            if ( defined $uuid_ldom_in_file && $uuid_ldom_in_file ne "" ) {
              if ( $hostid_in_file eq "$hostid" ) {
                my ( undef, $split_path )         = split( "Solaris--unknown", $uuid_txt1 );
                my ( undef, undef, $split_path1 ) = split( "\/", $split_path );
                my ( $real_ldom, undef )          = split( /:/, $split_path1 );
                $lpar_space = "$real_ldom:zone:$cdom_name";
                $net_exist  = 0;
                last;
              }
              else {
                $net_exist = 1;
              }
            }
          }

          # if zone does not have same hostid like LDOM/CDOM
          if ( $net_exist == 1 ) {

            #print ":$datar[0],$datar[1],$datar[2],$datar[3],$datar[4],$datar[5],$datar[6],$datar[7]-- $datar[ $cycle_var + 0 ],$datar[ $cycle_var + 1 ],$datar[ $cycle_var + 2 ]\n";
            my $zone_touch2 = "$wrkdir/Solaris--unknown/no_hmc/$lpar_space/zone";
            if ( -d "$wrkdir/Solaris--unknown/no_hmc/$lpar_space/" ) {
              `touch "$zone_touch2"`;
            }

            #$cycle_var = $cycle_var + 9;
            #next;
          }
          else {
            if ( -d "$wrkdir/Solaris--unknown/no_hmc/$cdom_name/" ) {
              rename( "$wrkdir/Solaris--unknown/no_hmc/$cdom_name/", "$wrkdir/Solaris--unknown/no_hmc/$lpar_space/" ) || error( " Cannot mv $wrkdir/Solaris--unknown/no_hmc/$cdom_name/ $wrkdir/Solaris--unknown/no_hmc/$lpar_space/: $!" . __FILE__ . ":" . __LINE__ ) && return 0;
            }
            my $zone_touch1 = "$wrkdir/Solaris/$lpar_space/zone";
            my $zone_touch2 = "$wrkdir/Solaris--unknown/no_hmc/$lpar_space/zone";
            if ( -d "$wrkdir/Solaris/$lpar_space/" ) {
              `touch "$zone_touch1"`;
            }
            if ( -d "$wrkdir/Solaris--unknown/no_hmc/$lpar_space/" ) {
              `touch "$zone_touch2"`;
            }
          }
        }
        ######## LDOM ###########
        elsif ( $type_dom eq "ldom" && $cdom_uuid ne "-" ) {    ########### LDOM with UUID !!!
                                                                #print "2) $datar[1]???$datar[$cycle_var]:$datar[$cycle_var+1]:$datar[$cycle_var+2]:$datar[$cycle_var+3]:$datar[$cycle_var+4]:$datar[$cycle_var+5]:$datar[$cycle_var+6]:$datar[$cycle_var+7]\n";
          if ( $ldom_with_uuid_touched eq "" ) {
            $db_name =~ s/\.mmm//g;
            my $net_name          = "";
            my $uuid_ldom_in_file = "";
            my $uuid_txt1         = "";
            my @uuid_files        = <$wrkdir/Solaris/*/uuid.txt>;    #### /
            my $real_ldom         = "";

            #my $grep_ldom_from_path = grep {/$lpar_space|$old_cdom_name/} @uuid_files; ### only LDOM without CDOM yet (first run
            my ( undef, $ldom_uuid_solo, undef ) = split( "\/", $datar[2] );    #### undef position have host_id in future
            chomp($ldom_uuid_solo);
            my $net_exist = 0;
            foreach my $file (@uuid_files) {
              $uuid_txt1 = $file;
              chomp $uuid_txt1;
              if ( -f "$uuid_txt1" ) {
                open( FC, "< $uuid_txt1" ) || error( "$peer_address:$server : cannot read $uuid_txt1: $!" . __FILE__ . ":" . __LINE__ );
                $uuid_ldom_in_file = <FC>;
                close(FC);
                if ( !defined $uuid_ldom_in_file ) {
                  $uuid_ldom_in_file = "";
                }
                chomp $uuid_ldom_in_file;

                #print "1416 \$uuid_ldom_in_file $uuid_ldom_in_file \$file $file \$ldom_uuid_solo $ldom_uuid_solo\n";
              }
              if ( defined $uuid_ldom_in_file && $uuid_ldom_in_file ne "" ) {
                if ( $uuid_ldom_in_file eq "$ldom_uuid_solo" ) {
                  my ( undef, $split_path ) = split( "Solaris", $uuid_txt1 );
                  my ( undef, $real_ldom )  = split( "\/",      $split_path );
                  $lpar_space             = $real_ldom;
                  $ldom_with_uuid_touched = $lpar_space;
                  $net_exist              = 0;
                  last;
                }
                else {
                  $net_exist = 1;
                }
              }
            }
            if ( $net_exist == 1 ) {
              $cycle_var = $cycle_var + 9;

              #print "3) $datar[1]???$datar[$cycle_var]:$datar[$cycle_var+1]:$datar[$cycle_var+2]:$datar[$cycle_var+3]:$datar[$cycle_var+4]:$datar[$cycle_var+5]:$datar[$cycle_var+6]:$datar[$cycle_var+7]\n";
              next;
            }
            else {
              # print "3) $datar[1]???$datar[$cycle_var]:$datar[$cycle_var+1]:$datar[$cycle_var+2]:$datar[$cycle_var+3]:$datar[$cycle_var+4]:$datar[$cycle_var+5]:$datar[$cycle_var+6]:$datar[$cycle_var+7]\n";
              my $cdom_touch1 = "$wrkdir/Solaris/$lpar_space/ldom";
              my $cdom_touch2 = "$wrkdir/Solaris--unknown/no_hmc/$lpar_space/ldom";
              if ( -d "$wrkdir/Solaris/$lpar_space/" ) {
                `touch "$cdom_touch1"`;
              }
              if ( -d "$wrkdir/Solaris--unknown/no_hmc/$lpar_space/" ) {
                `touch "$cdom_touch2"`;
              }
            }
          }
          else {
            $lpar_space = $ldom_with_uuid_touched;
          }
        }
        ############ LDOM without UUID
        elsif ( $type_dom eq "ldom" && $cdom_uuid eq "-" ) {
        }
        ############ CDOM
        else {
          #print "DATA_ROW:$datar[0],$datar[1],$datar[2],$datar[3],$datar[4]\n";
          #print "DATA_CYCLE VAR: $datar[ $cycle_var + 0 ],$datar[ $cycle_var + 1 ],$datar[ $cycle_var + 2 ],$datar[ $cycle_var + 3 ],$datar[ $cycle_var + 4 ],\n";
          if ( $db_name =~ /mem|pgs|cpu|lan-net\d|^JOB\/cputop/ ) {
            $lpar_space = "$cdom_name$double_col$cdom_name";
          }
          elsif ( $db_name !~ /mem|pgs|cpu|lan-net\d|_ldom|netstat/ ) {
            $lpar_space = "$cdom_name$double_col$cdom_name";
          }
          else {
            $lpar_space = "$cdom_name$double_col$old_cdom_name";
          }
          if ( -d "$wrkdir/Solaris/$old_cdom_name/" ) {
            rename( "$wrkdir/Solaris/$old_cdom_name/", "$wrkdir/Solaris/$cdom_name$double_col$old_cdom_name/" ) || error( " Cannot mv $wrkdir/Solaris/$old_cdom_name/ $wrkdir/Solaris/$cdom_name$double_col$old_cdom_name/: $!" . __FILE__ . ":" . __LINE__ ) && return 0;
          }
          elsif ( $datar[ $cycle_var + 0 ] =~ /_ldom/ ) {
            makex_path("$wrkdir/Solaris/$cdom_name$double_col$old_cdom_name") || error( "Cannot mkdir $wrkdir/Solaris/$cdom_name$double_col$old_cdom_name $!" . __FILE__ . ":" . __LINE__ ) && return 0;
          }
          if ( -d "$wrkdir/Solaris--unknown/no_hmc/$old_cdom_name/" ) {
            rename( "$wrkdir/Solaris--unknown/no_hmc/$old_cdom_name/", "$wrkdir/Solaris--unknown/no_hmc/$lpar_space/" ) || error( " Cannot mv $wrkdir/Solaris--unknown/no_hmc/$old_cdom_name/ $wrkdir/Solaris--unknown/no_hmc/$lpar_space/: $!" . __FILE__ . ":" . __LINE__ ) && return 0;
          }
          my $cdom_touch1 = "$wrkdir/Solaris/$lpar_space/ldom";
          my $cdom_touch2 = "$wrkdir/Solaris--unknown/no_hmc/$lpar_space/ldom";
          if ( -d "$wrkdir/Solaris/$lpar_space/" ) {
            `touch "$cdom_touch1"`;
          }
          if ( -d "$wrkdir/Solaris--unknown/no_hmc/$lpar_space/" ) {
            `touch "$cdom_touch2"`;
          }
        }
      }
      else {
        error("!!!WARNING!!! $peer_address:$server : old OS agent version on \"$datar[1]\" - upgrade to 6.11+ to make it work");
      }
    }

    # global path to lpar
    my $path_to_lpar = "";
    my @dir_to_lpar;
    @dir_to_lpar = <$wrkdir/$server_space/*/$lpar_space/>;
    foreach my $dir_lpar (@dir_to_lpar) {
      chomp($dir_lpar);
      $path_to_lpar = $dir_lpar;
    }

    while ( $datar[$cycle_var] =~ /^disk_id/ ) {
      my $id_txt = "";
      my @dir;
      if ( $server =~ /Solaris|Solaris10|Solaris11/ ) {
        @dir = <$wrkdir/Solaris/$lpar_space/>;
      }
      else {
        @dir = <$wrkdir/$server_space/*/$lpar_space/>;
      }
      foreach my $rrd_file_tmp (@dir) {
        chomp($rrd_file_tmp);
        $rrd_file_tmp .= "id.txt";
        $id_txt = $rrd_file_tmp;
      }
      print "$act_time: Updating 0     : name is $db_name rrd is $rrd_file\n" if $DEBUG == 2;
      if ( $datar[ $cycle_var - 9 ] !~ /^disk_id$/ ) {
        open( IDTXT, "> $id_txt" ) || error( "$peer_address:$server : cannot open $id_txt : $! " . __FILE__ . ":" . __LINE__ );
        close(IDTXT);
      }
      my $processed = 0;
      if ( -f $id_txt ) {
        $processed = 1;
        open( IDTXT, ">> $id_txt" ) || error( "$peer_address:$server : cannot open $id_txt: $!" . __FILE__ . ":" . __LINE__ ) && return 0;
        print IDTXT "$datar[$cycle_var+1]:$datar[$cycle_var+2]:$datar[$cycle_var+3]:$datar[$cycle_var+4]\n";
        close(IDTXT);
      }
      else {
        `touch "$id_txt"`;
      }

      $cycle_var = $cycle_var + 9;
      $db_name   = $datar[$cycle_var];
      if ( !defined $db_name ) {    # if not defined or db_name is not disk_id than return
        print "1285 finish storing data from agent\n" if $DEBUG == 2;
        return $time;               # return time of last record
      }
      elsif ( $db_name !~ /disk_id|path_lin|/ ) {
        print "1292 finish storing data from agent\n" if $DEBUG == 2;

        #next;
        return $time;               # return time of last record
      }
    }

    while ( $datar[$cycle_var] =~ /capacity_disk_lin/ ) {
      my $txt = "$path_to_lpar" . "disk.txt";
      print "$act_time: Updating 0     : name is $db_name rrd is $rrd_file\n" if $DEBUG == 2;

      if ( $datar[ $cycle_var - 9 ] !~ /capacity_disk_lin/ ) {
        open( IDTXT, "> $txt" ) || error( "$peer_address:$server : cannot open $txt : $! " . __FILE__ . ":" . __LINE__ );
        close(IDTXT);
      }
      if ( -f $txt ) {

        # print "$datar[$cycle_var+1]:$datar[$cycle_var+2]:$datar[$cycle_var+3]:$datar[$cycle_var+4]\n";
        open( IDTXT, ">> $txt" ) || error( "$peer_address:$server : cannot open $txt: $!" . __FILE__ . ":" . __LINE__ ) && return 0;
        print IDTXT "$datar[$cycle_var+1]:$datar[$cycle_var+2]\n";
        close(IDTXT);
      }
      else {
        `touch "$txt"`;
      }
      $cycle_var = $cycle_var + 9;
      $db_name   = $datar[$cycle_var];
      if ( !defined $db_name ) {    # if not defined or db_name is not disk_id than return
        print "1285 finish storing data from agent\n" if $DEBUG == 2;

        return $time;               # return time of last record
      }
      elsif ( $db_name !~ /capacity_disk_lin|FS/ ) {
        print "1292 finish storing data from agent\n" if $DEBUG == 2;
        return $time;               # return time of last record
      }
    }

    print "$act_time: Updating 0     : name is $db_name rrd is $rrd_file\n" if $DEBUG == 2;
    if ( !$rrd_file eq '' ) {
      my $filesize = -s "$rrd_file";
      if ( $filesize == 0 ) {

        # when a FS is full then it creates 0 Bytes rrdtool files what is a problem, delete it then
        error( "0 size rrd file: $rrd_file  - delete it" . __FILE__ . ":" . __LINE__ );
        unlink("$rrd_file") || error( "Cannot rm $rrd_file : $!" . __FILE__ . ":" . __LINE__ );
        $rrd_file = "";             # force to create a new one
      }
    }

    ####### save uuid for every cdom/ldom to uuid.txt
    if ( $datar[0] =~ /Solaris11|Solaris10/ && $datar[ $cycle_var + 0 ] =~ /_ldom$/ ) {
      my $uuid_txt   = "$wrkdir/Solaris/$lpar_space/uuid.txt";
      my $hostid_txt = "$wrkdir/Solaris/$lpar_space/hostid.txt";
      print_solaris_debug("ldom_name-$lpar_space\n") if $DEBUG == 2;
      my ( $ldom_uuid, $host_id ) = "";
      if ( $datar[ $cycle_var + 1 ] =~ /\// ) {
        ( $ldom_uuid, $host_id ) = split( "\/", $datar[ $cycle_var + 1 ] );
        chomp( $ldom_uuid, $host_id );
        if ($host_id) {
          chomp $host_id;
        }
      }
      if ( -d "$wrkdir/Solaris/$lpar_space/" ) {
        `touch "$uuid_txt"`;
        open( NAME_1, "> $uuid_txt" ) || error( "Cannot open $uuid_txt: $!" . __FILE__ . ":" . __LINE__ ) && return 0;
        print NAME_1 "$ldom_uuid";
        close(NAME_1);
        if ($host_id) {
          `touch "$hostid_txt"`;
          open( NAME_2, "> $hostid_txt" ) || error( "Cannot open $hostid_txt: $!" . __FILE__ . ":" . __LINE__ ) && return 0;
          print NAME_2 "$host_id";
          close(NAME_2);
        }
      }
      my $t_sol = "";
      if ( $datar[0] eq "Solaris11" ) {
        $t_sol = "solaris11";
      }
      else {
        $t_sol = "solaris10";
      }
      my $solaris_txt = "$wrkdir/Solaris/$lpar_space/$t_sol.txt";

      #my $solarisun_txt = "$wrkdir/Solaris--unknown/no_hmc/$lpar_space/$t_sol.txt";
      if ( -d "$wrkdir/Solaris/$lpar_space/" ) {
        `touch "$solaris_txt"`;
      }
    }
    ########################### REMOVED Solaris11/10 (number removed)
    if ( $datar[0] =~ /Solaris/ ) {
      $server =~ s/\d+//;
    }

    # loading old multipath report from linux_multipathing.txt (only through alerting)
    my @lines_multipath_lin = "";
    if ( $datar[$cycle_var] =~ /path_lin/ ) {
      my $txt       = "$path_to_lpar" . "linux_multipathing.txt";
      my $test_file = "$txt";
      if ( -f $test_file ) {
        open( FH, "<$test_file" ) || error( "Couldn't open file $test_file $!" . __FILE__ . ":" . __LINE__ ) && next;    ### TEST_FILE NAHRADIT PATH_FILE
        @lines_multipath_lin = <FH>;
        close(FH);
      }
    }

    if ( $datar[$cycle_var] =~ /path_lin/ ) {
      my $lin_multi_txt = "$path_to_lpar" . "linux_multipathing.txt";
      if ( !-f $lin_multi_txt ) {
        open( IDTXT, ">> $lin_multi_txt" ) || error( "$peer_address:$server : cannot open $lin_multi_txt: $!" . __FILE__ . ":" . __LINE__ ) && next;
      }
      else {
        # unlink $lin_multi_txt; # this is wrong because of hardlink
        # open( IDTXT, ">> $lin_multi_txt" ) || error( "$peer_address:$server : cannot open $lin_multi_txt: $!" . __FILE__ . ":" . __LINE__ ) && next;
        # clear this file
        open( IDTXT, "> $lin_multi_txt" ) || error( "$peer_address:$server : cannot open $lin_multi_txt: $!" . __FILE__ . ":" . __LINE__ ) && next;
      }
      while ( $datar[$cycle_var] =~ /path_lin/ ) {
        print "$act_time: Updating 0     : name is $db_name rrd is $rrd_file\n" if $DEBUG == 2;
        my $os                  = "LINUX";
        my $split_alias_actual  = "$datar[ $cycle_var + 1 ]";
        my ($grep_alias_actual) = split /\(/, $split_alias_actual;
        chomp $grep_alias_actual;
        $grep_alias_actual =~ s/\s+//g;
        my ($grep_match) = grep( /$grep_alias_actual \(/, @lines_multipath_lin );
        if ( !defined $grep_match || $grep_match eq '' ) {
          $grep_match = "no_file";
        }
        my $status_multi = alert_multipath( $os, $grep_match, $datar[ $cycle_var + 1 ], $datar[ $cycle_var + 4 ], $server_space, $lpar_space );
        print IDTXT "$datar[$cycle_var+1]:$datar[$cycle_var+2]:$datar[$cycle_var+3]:$datar[$cycle_var+4]\n";
        $cycle_var = $cycle_var + 9;
        $db_name   = $datar[$cycle_var];
        if ( !defined $db_name ) {    # if not defined or db_name is not disk_id than return
          print "1285 finish storing data from agent\n" if $DEBUG == 2;

          return $time;               # return time of last record
        }
        elsif ( $db_name !~ /path_lin|FS/ ) {
          print "1292 finish storing data from agent\n" if $DEBUG == 2;
          return $time;               # return time of last record
        }
      }
      close(IDTXT);
    }

    if ( $datar[$cycle_var] =~ /path_sol/ ) {
      my $sol_multi_txt = "$wrkdir/Solaris/$lpar_space/solaris_multipathing.txt";
      if ( !-f $sol_multi_txt ) {
        open( IDTXT, ">> $sol_multi_txt" ) || error( "$peer_address:$server : cannot open $sol_multi_txt: $!" . __FILE__ . ":" . __LINE__ ) && next;
      }
      else {
        # unlink $sol_multi_txt; # this is wrong because of hardlink
        # open( IDTXT, ">> $sol_multi_txt" ) || error( "$peer_address:$server : cannot open $sol_multi_txt: $!" . __FILE__ . ":" . __LINE__ ) && next;
        # clear this file
        open( IDTXT, "> $sol_multi_txt" ) || error( "$peer_address:$server : cannot open $sol_multi_txt: $!" . __FILE__ . ":" . __LINE__ ) && next;
      }
      while ( $datar[$cycle_var] =~ /path_sol/ ) {
        print "$act_time: Updating 0     : name is $db_name rrd is $rrd_file\n" if $DEBUG == 2;
        print IDTXT "$datar[$cycle_var+1]:$datar[$cycle_var+2]:$datar[$cycle_var+3]:$datar[$cycle_var+4]:$datar[$cycle_var+5]:$datar[$cycle_var+6]:$datar[$cycle_var+7]\n";
        $cycle_var = $cycle_var + 9;
        $db_name   = $datar[$cycle_var];
        if ( !defined $db_name ) {    # if not defined or db_name is not disk_id than return
          print "1285 finish storing data from agent\n" if $DEBUG == 2;

          return $time;               # return time of last record
        }
        elsif ( $db_name !~ /path_sol|FS/ ) {
          print "1292 finish storing data from agent\n" if $DEBUG == 2;
          return $time;               # return time of last record
        }
      }
      close(IDTXT);
    }

    print "$act_time: Updating 0     : name is $db_name rrd is $rrd_file\n" if $DEBUG == 2;
    if ( !$rrd_file eq '' ) {
      my $filesize = -s "$rrd_file";
      if ( $filesize == 0 ) {

        # when a FS is full then it creates 0 Bytes rrdtool files what is a problem, delete it then
        error( "0 size rrd file: $rrd_file  - delete it" . __FILE__ . ":" . __LINE__ );
        unlink("$rrd_file") || error( "Cannot rm $rrd_file : $!" . __FILE__ . ":" . __LINE__ );
        $rrd_file = "";    # force to create a new one
      }
    }

    # loading old multipath report from aix_multipathing.txt (only through alerting)
    my @lines_multipath = "";
    if ( $datar[$cycle_var] =~ /lsdisk/ ) {
      my $txt       = "$path_to_lpar" . "aix_multipathing.txt";
      my $test_file = "$txt";
      if ( -f $test_file ) {
        open( FH, "<$test_file" ) || error( "Couldn't open file $test_file $!" . __FILE__ . ":" . __LINE__ ) && next;    ### TEST_FILE NAHRADIT PATH_FILE
        @lines_multipath = <FH>;
        close(FH);
      }
    }

    if ( $datar[$cycle_var] =~ /lsdisk/ ) {
      my $aix_multi_txt = "$path_to_lpar" . "aix_multipathing.txt";
      if ( !-f $aix_multi_txt ) {
        open( IDTXT, ">> $aix_multi_txt" ) || error( "$peer_address:$server : cannot open $aix_multi_txt: $!" . __FILE__ . ":" . __LINE__ ) && next;
      }
      else {
        # unlink $aix_multi_txt; #this is wrong because of hardlink
        # open( IDTXT, ">> $aix_multi_txt" ) || error( "$peer_address:$server : cannot open $aix_multi_txt: $!" . __FILE__ . ":" . __LINE__ ) && next;
        # clear this file
        open( IDTXT, "> $aix_multi_txt" ) || error( "$peer_address:$server : cannot open $aix_multi_txt: $!" . __FILE__ . ":" . __LINE__ ) && next;
      }
      while ( $datar[$cycle_var] =~ /lsdisk/ ) {
        my $os           = "AIX";
        my $actual_disk  = "$datar[ $cycle_var + 1 ]";
        my ($grep_match) = grep( /$actual_disk/, @lines_multipath );
        if ( !defined $grep_match || $grep_match eq '' ) {
          $grep_match = "no_file";
        }
        my $status_multi = alert_multipath( $os, $grep_match, $datar[ $cycle_var + 1 ], $datar[ $cycle_var + 6 ], $server_space, $lpar_space );
        print IDTXT "$datar[$cycle_var+1]:$datar[$cycle_var+2]:$datar[$cycle_var+3]:$datar[$cycle_var+4]:$datar[$cycle_var+5]:$datar[$cycle_var+6]:$datar[$cycle_var+7]\n";
        $cycle_var = $cycle_var + 9;
        $db_name   = $datar[$cycle_var];
        if ( !defined $db_name ) {    # if not defined or db_name is not disk_id than return
          print "1285 finish storing data from agent\n" if $DEBUG == 2;

          return $time;               # return time of last record
        }
        elsif ( $db_name !~ /lsdisk|FS/ ) {
          print "1292 finish storing data from agent\n" if $DEBUG == 2;
          return $time;               # return time of last record
        }
      }
      close(IDTXT);
    }

    while ( $datar[$cycle_var] =~ /^FS$/ ) {
      my $FS_file = "";
      my @dir;
      if ( $server =~ /Solaris|Solaris10|Solaris11/ ) {
        @dir = <$wrkdir/Solaris--unknown/*/$lpar_space/>;
      }
      else {
        @dir = <$wrkdir/$server_space/*/$lpar_space/>;
      }
      foreach my $rrd_file_tmp (@dir) {
        chomp($rrd_file_tmp);
        $FS_file = $rrd_file_tmp;
        $FS_file .= "FS.csv";
        if ( !-e $FS_file ) {
          open( FS, ">> $FS_file" ) || error( "$peer_address:$server Cannot open $FS_file : $! " . __FILE__ . ":" . __LINE__ );
          close(FS);
          h_link( $FS_file, $wrkdir );
        }
        last;
      }
      print "$act_time: Updating 0     : name is $db_name rrd is $rrd_file\n" if $DEBUG == 2;

      #print "$\wrkdir  $wrkdir | \$server_space $server_space--unknown | no_hmc | \$lpar_space $lpar_space | \$db_name_space $db_name_space | \$FS_file $FS_file\n";

      # if the previous is not FS remove file so it can apped later!
      if ( $datar[ $cycle_var - 9 ] !~ /^FS$/ ) {
        if ( -f $FS_file ) {
          open( FS, "> $FS_file" ) || error( "$peer_address:$server : cannot open $FS_file : $! " . __FILE__ . ":" . __LINE__ );
          close(FS);
        }

        # instead of unlink just empty it -> for h_link
        # unlink($FS_file);
      }

      # alias case structure
      print "$act_time: case struc : $rrd_file : $cycle_var : $datar[$cycle_var]\n" if $DEBUG == 2;
      my $processed = 0;
      if ( isdigit( $datar[ $cycle_var + 3 ] ) && isdigit( $datar[ $cycle_var + 4 ] ) && isdigit( $datar[ $cycle_var + 5 ] ) && isdigit( $datar[ $cycle_var + 6 ] ) ) {
        $processed = 1;
        if ( -f $FS_file ) {
          open( FS, ">> $FS_file" ) || error( "$peer_address:$server cannot open $FS_file : $! " . __FILE__ . ":" . __LINE__ ) && return 0;
          print FS "$datar[ $cycle_var + 2 ] $datar[ $cycle_var + 3 ] $datar[ $cycle_var + 4 ] $datar[ $cycle_var + 5 ] $datar[ $cycle_var + 6 ] $datar[ $cycle_var +1 ]\n";
          close(FS);
        }
      }
      $cycle_var = $cycle_var + 9;
      $db_name   = $datar[$cycle_var];
      if ( !defined $db_name ) {    # if not defined or db_name is not FS than return
                                    #print "001 : $datar[$cycle_var] $cycle_var\n" if $DEBUG == 2;
        print "1151 finish storing data from agent\n" if $DEBUG == 2;

        # print "1259 \$time $time\n" if $datar[1] =~ "virtuals";
        return $time;               # return time of last record
      }
      elsif ( $db_name !~ /FS/ ) {

        #print "001 : $datar[$cycle_var] $cycle_var\n" if $DEBUG == 2;
        print "1151 finish storing data from agent\n" if $DEBUG == 2;

        # print "1259 \$time $time\n" if $datar[1] =~ "virtuals";
        return $time;               # return time of last record
      }
    }
    ####### ZONE PART #######
    if ( $rrd_file eq '' ) {
      if ( $datar[0] =~ /Solaris/ && $db_name !~ /mem|pgs|cpu|lan-net\d|_ldom|netstat|san_l|san_tresp|pool-sol|disk_id/ ) {
        if ( $protocol_version >= 40 ) {
          $db_name =~ s/\.mmm//g;
          my $db_a      = "";
          my $net_name  = "";
          my $ldom_name = "";
          if ( $db_name =~ /\// ) {
            ( $db_a, $cdom_uuid ) = split( "\/", $db_name );
            $rrd_file = "$wrkdir/Solaris/$lpar_space/ZONE/$db_a.mmm";
          }
          else {
            $db_a     = "$db_name";
            $rrd_file = "$wrkdir/Solaris/$lpar_space/ZONE/$db_a.mmm";
          }
          if ( $datar[10] =~ /N/ ) {
            $db_a     = "$db_name";
            $rrd_file = "$wrkdir/Solaris--unknown/no_hmc/$lpar_space/total-san.mmm";
          }
          print_solaris_debug("ZONE PART: ldom_name/global zone name-$lpar_space,zone_name-$db_a\n") if $DEBUG == 2;
          my $t_sol = "";
          if ( $datar[0] eq "Solaris11" ) {
            $t_sol = "solaris11";
          }
          else {
            $t_sol = "solaris10";
          }
          my $solaris_txt = "$wrkdir/Solaris/$lpar_space/$t_sol.txt";
          `touch "$solaris_txt"`;
          if ( !-f $rrd_file ) {
            my $ret2 = create2_rrd( $server, $lpar_real, $time, $server_space, $lpar_space, $db_name, $datar[10], $datar[8], $cdom_uuid, $net_name, $type_dom, $agent_version );
            if ( $ret2 == 2 ) {
              return $time;    # when en error in create2_rrd but continue (2) to skip it then go here
            }
            if ( $ret2 == 3 ) {
              my $data_skip = "$datar[3]";
              return $data_skip;
            }
            if ( $ret2 == 0 ) {
              return $ret2;
            }
          }
        }
      }
      ###### ORIGINAL AGENT PART ######
      elsif ( $datar[0] =~ /Solaris/ && $db_name =~ /mem|pgs|cpu|lan-net\d/ ) {
        $db_name =~ s/\.mmm//g;
        my $net_name = "";
        if ( $db_name =~ /cputop\d/ ) {
          $rrd_file = "$wrkdir/Solaris--unknown/no_hmc/$lpar_space/$db_name";
        }
        else {
          $rrd_file = "$wrkdir/Solaris--unknown/no_hmc/$lpar_space/$db_name.mmm";
        }
        my $t_sol = "";
        if ( $datar[0] eq "Solaris11" ) {
          $t_sol = "solaris11";
        }
        else {
          $t_sol = "solaris10";
        }
        my $solaris_txt = "$wrkdir/Solaris--unknown/no_hmc/$lpar_space/$t_sol.txt";
        `touch "$solaris_txt"`;
        if ( !-f $rrd_file ) {
          my $ret2 = create2_rrd( $server, $lpar_real, $time, $server_space, $lpar_space, $db_name, $datar[10], $datar[8], $cdom_uuid, $net_name, $type_dom, $agent_version );
          if ( $ret2 == 2 ) {
            return $time;    # when en error in create2_rrd but continue (2) to skip it then go here
          }
          if ( $ret2 == 3 ) {
            my $data_skip = "$datar[3]";
            return $data_skip;
          }
          if ( $ret2 == 0 ) {
            return $ret2;
          }
        }
      }
      elsif ( $datar[0] =~ /Solaris/ && $db_name =~ /san_l|san_tresp/ ) {
        if ( $protocol_version >= 40 ) {
          $db_name =~ s/\.mmm//g;
          my $net_name  = "";
          my $vnet_name = "";
          if ( $db_name =~ /san_l/ ) {
            $net_name = "$datar[ $cycle_var + 2 ]";
            my $char_s = "san-";
            $rrd_file = "$wrkdir/Solaris/$lpar_space/$char_s$net_name.mmm";
          }
          else {
            $net_name = "$datar[ $cycle_var + 2 ]";
            my $char_s = "san_tresp-";
            $rrd_file = "$wrkdir/Solaris/$lpar_space/$char_s$net_name.mmm";
          }
          my $t_sol = "";
          if ( $datar[0] eq "Solaris11" ) {
            $t_sol = "solaris11";
          }
          else {
            $t_sol = "solaris10";
          }
          if ( !-f $rrd_file ) {
            my $ret2 = create2_rrd( $server, $lpar_real, $time, $server_space, $lpar_space, $db_name, $datar[10], $datar[8], $cdom_uuid, $net_name, $type_dom, $agent_version );
            if ( $ret2 == 2 ) {
              return $time;    # when en error in create2_rrd but continue (2) to skip it then go here
            }
            if ( $ret2 == 3 ) {
              my $data_skip = "$datar[3]";
              return $data_skip;
            }
            if ( $ret2 == 0 ) {
              return $ret2;
            }
          }
        }
      }
      elsif ( $datar[0] =~ /Solaris/ && $db_name =~ /pool-sol/ ) {
        $db_name =~ s/\.mmm//g;
        my $pool_name = "$datar[ $cycle_var + 1 ]";
        $rrd_file = "$wrkdir/Solaris/$lpar_space/$datar[ $cycle_var + 1 ].mmm";
        if ( !-f $rrd_file ) {
          my $ret2 = create2_rrd( $server, $lpar_real, $time, $server_space, $lpar_space, $db_name, $datar[10], $datar[8], $cdom_uuid, $pool_name, $type_dom, $agent_version );
          if ( $ret2 == 2 ) {
            return $time;    # when en error in create2_rrd but continue (2) to skip it then go here
          }
          if ( $ret2 == 3 ) {
            my $data_skip = "$datar[3]";
            return $data_skip;
          }
          if ( $ret2 == 0 ) {
            return $ret2;
          }
        }
      }
      elsif ( $datar[0] =~ /Solaris/ && $db_name =~ /_ldom/ ) {
        $db_name =~ s/\.mmm//g;
        my $char_ldom            = "_ldom";
        my $net_name             = "";
        my $db_name_without_ldom = "$db_name";
        $db_name_without_ldom =~ s/_ldom$//g;
        if ( $datar[ $cycle_var + 2 ] =~ /\// ) {
          my ( $ldom_uuid, $host_id ) = split( "\/", $datar[2] );
          chomp($ldom_uuid);
          if ($host_id) {
            chomp $host_id;
          }
        }
        print_solaris_debug("LDOM PART: ldom_name/global zone name-$db_name_without_ldom,zone_name-$db_name_without_ldom$char_ldom\n") if $DEBUG == 2;
        if ( $agent_version >= 611 ) {
          $rrd_file = "$wrkdir/Solaris/$lpar_space/$db_name_without_ldom$char_ldom.mmm";
        }
        else {
          $rrd_file = "$wrkdir/Solaris/$db_name_without_ldom/$db_name_without_ldom$char_ldom.mmm";
        }
        my $t_sol = "";
        if ( $datar[0] eq "Solaris11" ) {
          $t_sol = "solaris11";
        }
        else {
          $t_sol = "solaris10";
        }
        if ( !-f $rrd_file ) {
          my $ret2 = create2_rrd( $server, $lpar_real, $time, $server_space, $lpar_space, $db_name, $datar[10], $datar[8], $cdom_uuid, $net_name, $type_dom, $agent_version );
          if ( $ret2 == 2 ) {
            return $time;    # when en error in create2_rrd but continue (2) to skip it then go here
          }
          if ( $ret2 == 3 ) {
            my $data_skip = "$datar[3]";
            return $data_skip;
          }
          if ( $ret2 == 0 ) {
            return $ret2;
          }
        }
      }
      elsif ( $datar[0] =~ /Solaris/ && $db_name =~ /netstat|vnetstat/ ) {
        $db_name =~ s/\.mmm//g;
        my $net_name          = "";
        my $uuid_ldom_in_file = "";
        my $uuid_txt1         = "";
        my @uuid_files        = <$wrkdir/Solaris/*/uuid.txt>;                       #### /
        my $real_ldom         = "";
        my ( $ldom_uuid_solo, undef ) = split( "\/", $datar[ $cycle_var + 1 ] );    #### undef position have host_id in future
        chomp($ldom_uuid_solo);
        my $net_exist = 0;

        foreach my $file (@uuid_files) {
          $uuid_txt1 = $file;
          chomp $uuid_txt1;
          if ( -f "$uuid_txt1" ) {
            open( FC, "< $uuid_txt1" ) || error( "Cannot read $uuid_txt1: $!" . __FILE__ . ":" . __LINE__ );
            $uuid_ldom_in_file = <FC>;
            close(FC);
          }
          if ( defined $uuid_ldom_in_file && $uuid_ldom_in_file ne "" ) {
            if ( $uuid_ldom_in_file eq "$ldom_uuid_solo" ) {
              my ( undef, $split_path ) = split( "Solaris", $uuid_txt1 );
              my ( undef, $real_ldom )  = split( "\/", $split_path );
              $lpar_space = $real_ldom;
              $net_exist  = 0;
              last;
            }
            else {
              $net_exist = 1;
            }
          }
        }
        if ( $net_exist == 1 ) {
          $cycle_var = $cycle_var + 9;
          next;
        }
        else {
          if ( $db_name eq "netstat" ) {
            $net_name = "$datar[ $cycle_var + 2 ]";
            $net_name =~ s/\//&&1/g;
            $rrd_file = "$wrkdir/Solaris/$lpar_space/$net_name.mmm";
            print_solaris_debug("NETFILE found-$rrd_file\n") if $DEBUG == 2;
          }
          elsif ( $db_name eq "vnetstat" ) {
            $net_name = "$datar[ $cycle_var + 2 ]";
            $net_name =~ s/\//&&1/g;
            my $char_s = "vlan-";
            $rrd_file = "$wrkdir/Solaris/$lpar_space/$char_s$net_name.mmm";
          }
          if ( !-f $rrd_file ) {
            my $ret2 = create2_rrd( $server, $lpar_real, $time, $server_space, $lpar_space, $db_name, $datar[10], $datar[8], $cdom_uuid, $net_name, $type_dom, $agent_version );
            if ( $ret2 == 2 ) {
              return $time;    # when en error in create2_rrd but continue (2) to skip it then go here
            }
            if ( $ret2 == 3 ) {
              my $data_skip = "$datar[3]";
              return $data_skip;
            }
            if ( $ret2 == 0 ) {
              return $ret2;
            }
          }
        }
      }
      ### OS AGENT
      else {
        my $ret2 = create2_rrd( $server, $lpar_real, $time, $server_space, $lpar_space, $db_name, $datar[10], $datar[8] );
        if ( $ret2 == 2 ) {
          return $time;    # when en error in create2_rrd but continue (2) to skip it then go here
        }
        if ( $ret2 == 0 ) {
          return $ret2;
        }
        if ( $server eq "Hitachi" ) {    # Hitachi has different file structure
          $rrd_file = -e $hitachi_rrd_path ? $hitachi_rrd_path : "";
          chomp($rrd_file);
        }
        else {
          @files = <$wrkdir/$server_space/*/$lpar_space/$db_name_space>;
          foreach my $rrd_file_tmp (@files) {
            chomp($rrd_file_tmp);
            $rrd_file = $rrd_file_tmp;
            last;
          }
        }
      }
    }

    print "$act_time: Updating 1     : $server_space:$lpar_space - $rrd_file - last_rec: $last_rec\n" if $DEBUG == 2;
    if ( $last_rec == 0 ) {

      # construction against crashing daemon Perl code when RRDTool error appears
      # this does not work well in old RRDTOool: $RRDp::error_mode = 'catch';
      # construction is not too costly as it runs once per each load
      eval {
        RRDp::cmd qq(last "$rrd_file" );
        my $last_rec_rrd = RRDp::read;
        chomp($$last_rec_rrd);
        $last_rec = $$last_rec_rrd;
      };
      if ($@) {
        rrd_error( $@ . __FILE__ . ":" . __LINE__, $rrd_file );
        return 0;
      }
    }

    print "$act_time: Updating 2     : $server_space:$lpar_space - $rrd_file - last_rec: $last_rec\n" if $DEBUG == 2;
    my $step_info = $STEP;

    # find rrd database file step
    #print STDERR"find file step for \$rrd_file $rrd_file\n";
    RRDp::cmd qq("info" "$rrd_file");
    my $answer_info = RRDp::read;
    if ( $$answer_info =~ "ERROR" ) {
      error("Rrdtool error : $$answer_info");
    }
    else {
      my ($step_from_rrd) = $$answer_info =~ m/step = (\d+)/;
      if ( $step_from_rrd > 0 ) {
        $step_info = $step_from_rrd;
      }
    }

    if ( $datar[$cycle_var] ne 'CPUTOP' ) {    # not following test cus $step is different, see line my $last_rec = 0;
      if ( ( $last_rec + $step_info / 2 ) >= $time ) {

        #error("$server:$lpar : last rec : $last_rec + $STEP/2 >= $time, ignoring it ...".__FILE__.":".__LINE__);
        print "$act_time: Updating 2     : $last_rec : $time : $rrd_file\n" if $DEBUG == 2;
        return $time;    # returns original time, not last_rec
                         # --> no, no, it is not wrong, just ignore it!
      }
    }
    print "$act_time: Updating 4     : $server_space:$lpar_space - $rrd_file - last_rec: $last_rec\n" if $DEBUG == 2;

    #
    # files update
    #
    # alias case structure
    print "$act_time: case struc : $rrd_file : $cycle_var : $datar[$cycle_var]\n" if $DEBUG == 2;
    my $answer     = "";
    my $nan        = "U";
    my $processed  = 0;
    my $update_ret = 1;
    {
      my $t_now = time();
      if ( ( $datar[0] ne "Hitachi" ) && ( $last_peer_address ne $peer_address ) ) {
        $last_peer_address = $peer_address;    # go this if only ones in session
        my @files_lpar = ();
        if ( $datar[0] =~ /Solaris/ ) {
          @files_lpar = <$wrkdir/Solaris--unknown/no_hmc/$lpar_space>;
        }
        else {
          @files_lpar = <$wrkdir/$server_space/*/$lpar_space>;
        }
        foreach my $rrd_dir (@files_lpar) {
          if ( -d $rrd_dir ) {

            # print "2149 \$datar[0] $datar[0] \$peer_address $peer_address \$cycle_var $cycle_var \$datar[\$cycle_var] $datar[$cycle_var]\n";
            if ( defined $peer_address && $peer_address ne '' ) {
              my $ip_txt       = "$rrd_dir/IP.txt";
              my $ip_file_time = ( stat($ip_txt) )[9];
              $t_now = $t_now - 86400;
              if ( -f $ip_txt ) {
                if ( $t_now > $ip_file_time ) {
                  open( IPTXT, "> $ip_txt" ) || error( "$peer_address:$server : cannot open $ip_txt: $!" . __FILE__ . ":" . __LINE__ ) && return 0;
                  print IPTXT "$peer_address\n";
                  close(IPTXT);
                }
              }
              else {    # first run
                `touch "$ip_txt"`;
                if ( -f $ip_txt ) {
                  open( IPTXT, "> $ip_txt" ) || error( "$peer_address:$server : cannot open $ip_txt: $!" . __FILE__ . ":" . __LINE__ ) && return 0;
                  print IPTXT "$peer_address\n";
                  close(IPTXT);
                }
              }
            }
            if ( $datar[$cycle_var] eq "linux_cpu" ) {    # CPU cores & MHz & Model name
              if ( isdigit( $datar[ $cycle_var + 1 ] ) && isdigit( $datar[ $cycle_var + 2 ] ) && defined( $datar[ $cycle_var + 5 ] ) ) {
                my $cpu_txt_file = "$rrd_dir/CPU_info.txt";
                my $cpu_txt_time = ( stat($cpu_txt_file) )[9];
                $t_now = $t_now - 86400;
                if ( -f $cpu_txt_file ) {
                  if ( $t_now > $cpu_txt_time ) {
                    open( CPUTXT, "> $cpu_txt_file" ) || error( "$peer_address:$server : cannot open $cpu_txt_file: $!" . __FILE__ . ":" . __LINE__ ) && return 0;

                    # Model name,CPU cores,CPU mhz
                    $datar[ $cycle_var + 2 ] = sprintf( '%.0f', $datar[ $cycle_var + 2 ] );
                    print CPUTXT "$datar[ $cycle_var + 5 ],$datar[ $cycle_var + 1 ],$datar[ $cycle_var + 2 ]\n";
                    close(CPUTXT);
                  }
                }
                else {    # first run
                  `touch "$cpu_txt_file"`;
                  if ( -f $cpu_txt_file ) {
                    open( CPUTXT, "> $cpu_txt_file" ) || error( "$peer_address:$server : cannot open $cpu_txt_file: $!" . __FILE__ . ":" . __LINE__ ) && return 0;
                    $datar[ $cycle_var + 2 ] = sprintf( '%.0f', $datar[ $cycle_var + 2 ] );
                    print CPUTXT "$datar[ $cycle_var + 5 ],$datar[ $cycle_var + 1 ],$datar[ $cycle_var + 2 ]\n";
                    close(CPUTXT);
                  }
                }
              }
            }
            if ( $datar[0] =~ /Solaris/ ) {
              if ( -d $rrd_dir ) {
                if ( defined $agent_version && $agent_version ne '' ) {
                  my $agent_cfg    = "$rrd_dir/agent.cfg";
                  my $ip_file_time = ( stat($agent_cfg) )[9];
                  $t_now = $t_now - 86400;
                  if ( -f $agent_cfg ) {
                    if ( $t_now > $ip_file_time ) {
                      open( AGENT, "> $agent_cfg " ) || error( "$peer_address:$server : cannot open $agent_cfg : $!" . __FILE__ . ":" . __LINE__ ) && return 0;
                      print AGENT "$agent_version\n";
                      close(AGENT);
                    }
                  }
                  else {    # first run
                    `touch "$agent_cfg"`;
                    if ( -f $agent_cfg ) {
                      open( AGENT, "> $agent_cfg" ) || error( "$peer_address:$server : cannot open $agent_cfg: $!" . __FILE__ . ":" . __LINE__ ) && return 0;
                      print AGENT "$agent_version\n";
                      close(AGENT);
                    }
                  }
                }
              }
            }
            my $hostname_txt       = "$rrd_dir/hostname.txt";
            my $hostname_file_time = ( stat($hostname_txt) )[9];
            if ( defined $datar[8] && $datar[8] ne '' ) {
              my $hostname = $datar[8];
              chomp $hostname;
              if ( -f $hostname_txt ) {
                if ( $t_now > $hostname_file_time ) {
                  open( HOSTXT, "> $hostname_txt" ) || error( "$peer_address:$server : cannot open $hostname_txt: $!" . __FILE__ . ":" . __LINE__ ) && return 0;
                  print HOSTXT "$hostname\n";
                  close(HOSTXT);
                }
              }
              else {    # first run
                `touch "$hostname_txt"`;
                if ( -f $hostname_txt ) {
                  open( HOSTXT, "> $hostname_txt" ) || error( "$peer_address:$server : cannot open $hostname_txt: $!" . __FILE__ . ":" . __LINE__ ) && return 0;
                  print HOSTXT "$hostname\n";
                  close(HOSTXT);
                }
              }
            }
          }
        }
      }

      "mem" eq $datar[$cycle_var] && do {
        if ( isdigit( $datar[ $cycle_var + 3 ] ) && isdigit( $datar[ $cycle_var + 4 ] ) && isdigit( $datar[ $cycle_var + 5 ] ) && isdigit( $datar[ $cycle_var + 6 ] ) && isdigit( $datar[ $cycle_var + 7 ] ) && isdigit( $datar[ $cycle_var + 8 ] ) ) {
          $processed = 1;
          if ( $first_mem == 0 ) {

            # first insert through eval to be able to catch nwhatever error, next inserts with issues a new shell (eval)
            $first_mem = 1;
            eval {
              $update_ret = rrd_update( "$rrd_file", "$time:$datar[$cycle_var+3]:$datar[$cycle_var+4]:$datar[$cycle_var+5]:$datar[$cycle_var+6]:$datar[$cycle_var+7]:$datar[$cycle_var+8]" );
              if ( $rrdcached == 0 ) { $answer = RRDp::read; }
            };
            if ( $update_ret == 0 || $@ ) {

              # error happened, zero the first_mem to continue with eval
              $first_mem = 0;
              if ( $error_first == 0 ) {
                error( " updating $server:$lpar : $rrd_file : update_ret=$update_ret : $@ " . __FILE__ . ":" . __LINE__ );    # print it only first time
              }
              $processed = 0;
            }
          }
          else {
            $update_ret = rrd_update( "$rrd_file", "$time:$datar[$cycle_var+3]:$datar[$cycle_var+4]:$datar[$cycle_var+5]:$datar[$cycle_var+6]:$datar[$cycle_var+7]:$datar[$cycle_var+8]" );
            if ( $rrdcached == 0 ) { $answer = RRDp::read; }
          }
        }
        last;
      };
      "pgs" eq $datar[$cycle_var] && do {
        if ( isdigit( $datar[ $cycle_var + 3 ] ) && isdigit( $datar[ $cycle_var + 4 ] ) && isdigit( $datar[ $cycle_var + 5 ] ) && isdigit( $datar[ $cycle_var + 6 ] ) ) {
          $processed = 1;
          if ( $first_pgs == 0 ) {

            # first insert through eval to be able to catch nwhatever error, next inserts with issues a new shell (eval)
            $first_pgs = 1;
            eval {
              $update_ret = rrd_update( "$rrd_file", "$time:$datar[$cycle_var+3]:$datar[$cycle_var+4]:$datar[$cycle_var+5]:$datar[$cycle_var+6]" );
              if ( $rrdcached == 0 ) { $answer = RRDp::read; }
            };
            if ( $update_ret == 0 || $@ ) {

              # error happened, zero the first_pgs to continue with eval
              $first_pgs = 0;
              if ( $error_first == 0 ) {
                error( " updating $server:$lpar : $rrd_file : update_ret=$update_ret : $@ " . __FILE__ . ":" . __LINE__ );    # print it only first time
              }
              $processed = 0;
            }
          }
          else {
            $update_ret = rrd_update( "$rrd_file", "$time:$datar[$cycle_var+3]:$datar[$cycle_var+4]:$datar[$cycle_var+5]:$datar[$cycle_var+6]" );
            if ( $rrdcached == 0 ) { $answer = RRDp::read; }
          }
        }
        last;
      };
      "lan" eq $datar[$cycle_var] && do {
        if ( isdigit( $datar[ $cycle_var + 3 ] ) && isdigit( $datar[ $cycle_var + 4 ] ) ) {
          $processed = 1;
          my $par5;
          my $par6;
          if ( $first_lan == 0 ) {

            # first insert through eval to be able to catch nwhatever error, next inserts with issues a new shell (eval)
            $first_lan = 1;
            $par5      = $nan;
            $par5      = $datar[ $cycle_var + 5 ] if isdigit( $datar[ $cycle_var + 5 ] );
            $par6      = $nan;
            $par6      = $datar[ $cycle_var + 6 ] if isdigit( $datar[ $cycle_var + 6 ] );
            eval {
              $update_ret = rrd_update( "$rrd_file", "$time:$datar[$cycle_var+3]:$datar[$cycle_var+4]:$par5:$par6" );
              if ( $rrdcached == 0 ) { $answer = RRDp::read; }
            };
            if ( $update_ret == 0 || $@ ) {

              # error happened, zero the first_lan to continue with eval
              $first_lan = 0;
              if ( $error_first == 0 ) {
                error( " updating $server:$lpar : $rrd_file : update_ret=$update_ret : $@ " . __FILE__ . ":" . __LINE__ );    # print it only first time
              }
              $processed = 0;
            }
          }
          else {
            $par5       = $nan;
            $par5       = $datar[ $cycle_var + 5 ] if isdigit( $datar[ $cycle_var + 5 ] );
            $par6       = $nan;
            $par6       = $datar[ $cycle_var + 6 ] if isdigit( $datar[ $cycle_var + 6 ] );
            $update_ret = rrd_update( "$rrd_file", "$time:$datar[$cycle_var+3]:$datar[$cycle_var+4]:$par5:$par6" );
            if ( $rrdcached == 0 ) { $answer = RRDp::read; }
          }
          write_lansancfg( $rrd_file, $datar[ $cycle_var + 2 ], $time );
        }
        last;
      };
      "san" eq $datar[$cycle_var] && do {
        if ( isdigit( $datar[ $cycle_var + 3 ] ) && isdigit( $datar[ $cycle_var + 4 ] ) && isdigit( $datar[ $cycle_var + 5 ] ) && isdigit( $datar[ $cycle_var + 6 ] ) ) {
          $processed = 1;
          if ( $first_san == 0 ) {

            # first insert through eval to be able to catch nwhatever error, next inserts with issues a new shell (eval)
            $first_san = 1;
            eval {
              $update_ret = rrd_update( "$rrd_file", "$time:$datar[$cycle_var+3]:$datar[$cycle_var+4]:$datar[$cycle_var+5]:$datar[$cycle_var+6]" );
              if ( $rrdcached == 0 ) { $answer = RRDp::read; }
            };
            if ( $update_ret == 0 || $@ ) {

              # error happened, zero the first_san to continue with eval
              $first_san = 0;
              if ( $error_first == 0 ) {
                error( " updating $server:$lpar : $rrd_file : update_ret=$update_ret : $@ " . __FILE__ . ":" . __LINE__ );    # print it only first time
              }
              $processed = 0;
            }
          }
          else {
            $update_ret = rrd_update( "$rrd_file", "$time:$datar[$cycle_var+3]:$datar[$cycle_var+4]:$datar[$cycle_var+5]:$datar[$cycle_var+6]" );
            if ( $rrdcached == 0 ) { $answer = RRDp::read; }
          }
          my $item_to_write = $datar[ $cycle_var + 2 ];
          if ( $datar[ $cycle_var + 7 ] eq "full" ) {    # signal for detail-graph.cgi.pl to graph both xferin/xferout
            $item_to_write .= " full";
          }
          write_lansancfg( $rrd_file, $item_to_write, $time );
        }
        last;
      };
      "san_resp" eq $datar[$cycle_var] && do {
        if ( isdigit( $datar[ $cycle_var + 3 ] ) && isdigit( $datar[ $cycle_var + 4 ] ) ) {
          $processed = 1;
          if ( $first_san == 0 ) {

            # first insert through eval to be able to catch nwhatever error, next inserts with issues a new shell (eval)
            $first_san = 1;
            eval {
              $update_ret = rrd_update( "$rrd_file", "$time:$datar[$cycle_var+3]:$datar[$cycle_var+4]" );
              if ( $rrdcached == 0 ) { $answer = RRDp::read; }
            };
            if ( $update_ret == 0 || $@ ) {

              # error happened, zero the first_san to continue with eval
              $first_san = 0;
              if ( $error_first == 0 ) {
                error( " updating $server:$lpar : $rrd_file : update_ret=$update_ret :$@ " . __FILE__ . ":" . __LINE__ );    # print it only first time
              }
              $processed = 0;
            }
          }
          else {
            $update_ret = rrd_update( "$rrd_file", "$time:$datar[$cycle_var+3]:$datar[$cycle_var+4]" );
            if ( $rrdcached == 0 ) { $answer = RRDp::read; }
          }
        }
        last;
      };

      # ERROR-FCS
      "san_error" eq $datar[$cycle_var] && do {
        if ( isdigit( $datar[ $cycle_var + 2 ] ) && ( $datar[ $cycle_var + 2 ] !~ m/-/ ) ) {
          $processed = 1;
          if ( $first_san == 0 ) {

            # first insert through eval to be able to catch nwhatever error, next inserts with issues a new shell (eval)
            $first_san = 1;
            eval {
              $update_ret = rrd_update( "$rrd_file", "$time:$datar[$cycle_var+2]" );
              if ( $rrdcached == 0 ) { $answer = RRDp::read; }
            };
            if ( $update_ret == 0 || $@ ) {

              # error happened, zero the first_san to continue with eval
              $first_san = 0;
              if ( $error_first == 0 ) {
                error( " updating $server:$lpar : $rrd_file : update_ret=$update_ret : $@ " . __FILE__ . ":" . __LINE__ );    # print it only first time
              }
              $processed = 0;
            }
          }
          else {
            $update_ret = rrd_update( "$rrd_file", "$time:$datar[$cycle_var+2]" );
            if ( $rrdcached == 0 ) { $answer = RRDp::read; }
          }
        }
        last;
      };

      # LAN ERRORS AIX

=pod
      "lan_error" eq $datar[$cycle_var] && do {
        if ( isdigit( $datar[ $cycle_var + 3 ] ) && ( $datar[ $cycle_var + 3 ] !~ m/-/ ) ) {
          $processed = 1;
          if ( $first_san == 0 ) {

            # first insert through eval to be able to catch nwhatever error, next inserts with issues a new shell (eval)
            $first_san = 1;
            eval {
              $update_ret = rrd_update( "$rrd_file", "$time:$datar[$cycle_var+3]" );
              if ( $rrdcached == 0 ) { $answer = RRDp::read; }
            };
            if ( $update_ret == 0 || $@ ) {

              # error happened, zero the first_san to continue with eval
              $first_san = 0;
              if ( $error_first == 0 ) {
                error( " updating $server:$lpar : $rrd_file : update_ret=$update_ret : $@ " . __FILE__ . ":" . __LINE__ );    # print it only first time
              }
              $processed = 0;
            }
          }
          else {
            $update_ret = rrd_update( "$rrd_file", "$time:$datar[$cycle_var+3]" );
            if ( $rrdcached == 0 ) { $answer = RRDp::read; }
          }
        }
        last;
      };
=cut

      "ame" eq $datar[$cycle_var] && do {
        if ( isdigit( $datar[ $cycle_var + 3 ] ) && isdigit( $datar[ $cycle_var + 4 ] ) && isdigit( $datar[ $cycle_var + 5 ] ) ) {
          $processed = 1;
          if ( $first_ame == 0 ) {

            # first insert through eval to be able to catch nwhatever error, next inserts with issues a new shell (eval)
            $first_ame = 1;
            eval {
              $update_ret = rrd_update( "$rrd_file", "$time:$datar[$cycle_var+3]:$datar[$cycle_var+4]:$datar[$cycle_var+5]" );
              if ( $rrdcached == 0 ) { $answer = RRDp::read; }
            };
            if ( $update_ret == 0 || $@ ) {

              # error happened, zero the first_ame to continue with eval
              $first_ame = 0;
              if ( $error_first == 0 ) {
                error( " updating $server:$lpar : $rrd_file : update_ret=$update_ret : $@ " . __FILE__ . ":" . __LINE__ );    # print it only first time
              }
              $processed = 0;
            }
          }
          else {
            $update_ret = rrd_update( "$rrd_file", "$time:$datar[$cycle_var+3]:$datar[$cycle_var+4]:$datar[$cycle_var+5]" );
            if ( $rrdcached == 0 ) { $answer = RRDp::read; }
          }
        }
        last;
      };
      "cpu" eq $datar[$cycle_var] && do {
        if ( isdigit( $datar[ $cycle_var + 3 ] ) && isdigit( $datar[ $cycle_var + 4 ] ) && isdigit( $datar[ $cycle_var + 5 ] ) && isdigit( $datar[ $cycle_var + 6 ] ) ) {
          $processed = 1;

          # print "1262 $time:$datar[$cycle_var+3]:$datar[$cycle_var+4]:$datar[$cycle_var+5]:$datar[$cycle_var+6]???CPU\n";
          if ( $first_cpu == 0 ) {

            # first insert through eval to be able to catch nwhatever error, next inserts with issues a new shell (eval)
            $first_cpu = 1;
            eval {
              $update_ret = rrd_update( "$rrd_file", "$time:$datar[$cycle_var+3]:$datar[$cycle_var+4]:$datar[$cycle_var+5]:$datar[$cycle_var+6]" );
              if ( $rrdcached == 0 ) { $answer = RRDp::read; }
            };
            if ( $update_ret == 0 || $@ ) {

              # error happened, zero the first_cpu to continue with eval
              $first_cpu = 0;
              if ( $error_first == 0 ) {
                error( " updating $server:$lpar : $rrd_file : update_ret=$update_ret : $@ " . __FILE__ . ":" . __LINE__ );    # print it only first time
              }
              $processed = 0;
            }
          }
          else {
            $update_ret = rrd_update( "$rrd_file", "$time:$datar[$cycle_var+3]:$datar[$cycle_var+4]:$datar[$cycle_var+5]:$datar[$cycle_var+6]" );
            if ( $rrdcached == 0 ) { $answer = RRDp::read; }
          }

          # since 4.70 there is agent version in human date item - $datar[6], need to save it to agent.cfg
          my $item_to_write = $datar[6];
          if ( $datar[6] !~ /version/ ) {
            $item_to_write .= " version <4.7";
          }
          write_lansancfg( $rrd_file, $item_to_write, $time );

          # since 5.01-3 lpar_id keeps UUID on Linux like partition, need to save it to uuid.txt
          if ( uuid_check($lpar_id) ) {
            write_lansancfg( $rrd_file, $lpar_id, $time );
          }
        }
        last;
      };
      "st-cpu" eq $datar[$cycle_var] && do {
        if ( isdigit( $datar[ $cycle_var + 3 ] ) ) {
          $processed = 1;

          if ( $first_cpu == 0 ) {

            # first insert through eval to be able to catch nwhatever error, next inserts with issues a new shell (eval)
            $first_cpu = 1;
            eval {
              $update_ret = rrd_update( "$rrd_file", "$time:$datar[$cycle_var+3]:U:U:U" );
              if ( $rrdcached == 0 ) { $answer = RRDp::read; }
            };
            if ( $update_ret == 0 || $@ ) {

              # error happened, zero the first_cpu to continue with eval
              $first_cpu = 0;
              if ( $error_first == 0 ) {
                error( " updating $server:$lpar : $rrd_file : update_ret=$update_ret : $@ " . __FILE__ . ":" . __LINE__ );    # print it only first time
              }
              $processed = 0;
            }
          }
          else {
            $update_ret = rrd_update( "$rrd_file", "$time:$datar[$cycle_var+3]:U:U:U" );
            if ( $rrdcached == 0 ) { $answer = RRDp::read; }
          }
        }
        last;
      };
      "linux_cpu" eq $datar[$cycle_var] && do {
        if ( isdigit( $datar[ $cycle_var + 1 ] ) && isdigit( $datar[ $cycle_var + 2 ] ) && isdigit( $datar[ $cycle_var + 3 ] ) && isdigit( $datar[ $cycle_var + 4 ] ) ) {
          $processed = 1;
          if ( $first_cpu == 0 ) {

            # first insert through eval to be able to catch nwhatever error, next inserts with issues a new shell (eval)
            $first_cpu = 1;
            eval {
              $update_ret = rrd_update( "$rrd_file", "$time:$datar[$cycle_var+1]:$datar[$cycle_var+2]:$datar[$cycle_var+3]:$datar[$cycle_var+4]" );
              if ( $rrdcached == 0 ) { $answer = RRDp::read; }
            };
            if ( $update_ret == 0 || $@ ) {

              # error happened, zero the first_cpu to continue with eval
              $first_cpu = 0;
              if ( $error_first == 0 ) {
                error( " updating $server:$lpar : $rrd_file : update_ret=$update_ret : $@ " . __FILE__ . ":" . __LINE__ );    # print it only first time
              }
              $processed = 0;
            }
          }
          else {
            $update_ret = rrd_update( "$rrd_file", "$time:$datar[$cycle_var+1]:$datar[$cycle_var+2]:$datar[$cycle_var+3]:$datar[$cycle_var+4]" );
            if ( $rrdcached == 0 ) { $answer = RRDp::read; }
          }
        }
        last;
      };
      "queue_cpu_aix" eq $datar[$cycle_var] && do {
        if ( isdigit( $datar[ $cycle_var + 3 ] ) && isdigit( $datar[ $cycle_var + 4 ] ) && isdigit( $datar[ $cycle_var + 5 ] ) && isdigit( $datar[ $cycle_var + 6 ] ) && isdigit( $datar[ $cycle_var + 7 ] ) ) {    # AIX part
          $processed = 1;

          # print "1262 $time:$datar[$cycle_var+3]:$datar[$cycle_var+4]:$datar[$cycle_var+5]:$datar[$cycle_var+6]???CPU\n";
          if ( $first_que == 0 ) {

            # first insert through eval to be able to catch nwhatever error, next inserts with issues a new shell (eval)
            $first_que = 1;
            eval {
              $update_ret = rrd_update( "$rrd_file", "$time:$datar[$cycle_var+3]:$datar[$cycle_var+4]:$datar[$cycle_var+5]:$datar[$cycle_var+6]:$datar[$cycle_var+7]" );
              if ( $rrdcached == 0 ) { $answer = RRDp::read; }
            };
            if ( $update_ret == 0 || $@ ) {

              # error happened, zero the first_que to continue with eval
              $first_que = 0;
              if ( $error_first == 0 ) {
                error( " updating $server:$lpar : $rrd_file : update_ret=$update_ret : $@ " . __FILE__ . ":" . __LINE__ );    # print it only first time
              }
              $processed = 0;
            }
          }
          else {
            $update_ret = rrd_update( "$rrd_file", "$time:$datar[$cycle_var+3]:$datar[$cycle_var+4]:$datar[$cycle_var+5]:$datar[$cycle_var+6]:$datar[$cycle_var+7]" );
            if ( $rrdcached == 0 ) { $answer = RRDp::read; }
          }

        }
        last;
      };
      "queue_cpu" eq $datar[$cycle_var] && do {
        if ( isdigit( $datar[ $cycle_var + 3 ] ) && isdigit( $datar[ $cycle_var + 4 ] ) && isdigit( $datar[ $cycle_var + 5 ] ) ) {
          $processed = 1;
          if ( $first_que == 0 ) {

            # first insert through eval to be able to catch nwhatever error, next inserts with issues a new shell (eval)
            $first_que = 1;
            eval {
              $update_ret = rrd_update( "$rrd_file", "$time:$datar[$cycle_var+3]:$datar[$cycle_var+4]:$datar[$cycle_var+5]" );
              if ( $rrdcached == 0 ) { $answer = RRDp::read; }
            };
            if ( $update_ret == 0 || $@ ) {

              # error happened, zero the first_que to continue with eval
              $first_que = 0;
              if ( $error_first == 0 ) {
                error( " updating $server:$lpar : $rrd_file : update_ret=$update_ret : $@ " . __FILE__ . ":" . __LINE__ );    # print it only first time
              }
              $processed = 0;
            }
          }
          else {
            $update_ret = rrd_update( "$rrd_file", "$time:$datar[$cycle_var+3]:$datar[$cycle_var+4]:$datar[$cycle_var+5]" );
            if ( $rrdcached == 0 ) { $answer = RRDp::read; }
          }

        }
        last;
      };
      "sea" eq $datar[$cycle_var] && do {
        if ( isdigit( $datar[ $cycle_var + 3 ] ) && isdigit( $datar[ $cycle_var + 4 ] ) ) {
          my $packet_recv  = $nan;
          my $packet_trans = $nan;
          $packet_recv  = $datar[ $cycle_var + 5 ] if isdigit( $datar[ $cycle_var + 5 ] );
          $packet_trans = $datar[ $cycle_var + 6 ] if isdigit( $datar[ $cycle_var + 6 ] );
          $processed    = 1;
          if ( $first_sea == 0 ) {

            # first insert through eval to be able to catch nwhatever error, next inserts with issues a new shell (eval)
            $first_sea = 1;
            eval {
              $update_ret = rrd_update( "$rrd_file", "$time:$datar[$cycle_var+3]:$datar[$cycle_var+4]:$packet_recv:$packet_trans" );
              if ( $rrdcached == 0 ) { $answer = RRDp::read; }
            };
            if ( $update_ret == 0 || $@ ) {

              # error happened, zero the first_sea to continue with eval
              $first_sea = 0;
              if ( $error_first == 0 ) {
                error( " updating $server:$lpar : $rrd_file : update_ret=$update_ret : $@ " . __FILE__ . ":" . __LINE__ );    # print it only first time
              }
              $processed = 0;
            }
          }
          else {
            $update_ret = rrd_update( "$rrd_file", "$time:$datar[$cycle_var+3]:$datar[$cycle_var+4]:$packet_recv:$packet_trans" );
            if ( $rrdcached == 0 ) { $answer = RRDp::read; }
          }
          write_lansancfg( $rrd_file, $datar[ $cycle_var + 2 ], $time );
        }
        last;
      };
      "lpar" eq $datar[$cycle_var] && do {
        if ( isdigit( $datar[ $cycle_var + 3 ] ) && isdigit( $datar[ $cycle_var + 4 ] ) ) {
          $processed = 1;
          if ( $first_lpar == 0 ) {

            # first insert through eval to be able to catch whatever error, next inserts with issues a new shell (eval)
            $first_lpar = 1;
            eval {
              $update_ret = rrd_update( "$rrd_file", "$time:$datar[$cycle_var+3]:$datar[$cycle_var+4]" );
              if ( $rrdcached == 0 ) { $answer = RRDp::read; }
            };
            if ( $update_ret == 0 || $@ ) {

              # error happened, zero the first_lpar to continue with eval
              $first_lpar = 0;
              if ( $error_first == 0 ) {
                error( " updating $server:$lpar : $rrd_file : update_ret=$update_ret : $@ " . __FILE__ . ":" . __LINE__ );    # print it only first time
              }
              $processed = 0;
            }
          }
          else {
            $update_ret = rrd_update( "$rrd_file", "$time:$datar[$cycle_var+3]:$datar[$cycle_var+4]" );
            if ( $rrdcached == 0 ) { $answer = RRDp::read; }
          }

          #     write_lansancfg ( $rrd_file, $datar[$cycle_var+2], $time);
        }
        last;
      };

      # :CPUTOP:1130:lpar2rrd:yes:226:79:604:107900:
      # :CPUTOP:129965:root:[kworker/01]:48:13:0:0:
      # after 30 minutes
      # :CPUTOP:1130:lpar2rrd:yes:305:79:604:107900:
      # :CPUTOP:125733:root:[kworker/12]:82:18:0:0::
      # every CPUTOP creates one JOB/cputopx.mmc file
      "CPUTOP" eq $datar[$cycle_var] && do {
        if ( isdigit( $datar[ $cycle_var + 1 ] ) && isdigit( $datar[ $cycle_var + 5 ] ) && isdigit( $datar[ $cycle_var + 6 ] ) && isdigit( $datar[ $cycle_var + 7 ] ) ) {
          $processed = 1;

          # my $time_r = $time;
          my $time_r = $time - ( $time % 300 );

          # print "1208 \$time $time\n" if $datar[1] =~ "virtuals";
          if ( $first_lpar == 0 ) {

            # first insert through eval to be able to catch whatever error, next inserts with issues a new shell (eval)
            $first_lpar = 1;
            eval {
              $update_ret = rrd_update( "$rrd_file", "$time_r:$datar[$cycle_var+1]:$datar[$cycle_var+5]:$datar[$cycle_var+6]:$datar[$cycle_var+7]" );
              if ( $rrdcached == 0 ) { $answer = RRDp::read; }
            };
            if ( $update_ret == 0 || $@ ) {

              # error happened, zero the first_lpar to continue with eval
              $first_lpar = 0;
              if ( $error_first == 0 ) {
                error( " updating $server:$lpar : $rrd_file : update_ret=$update_ret : $@ " . __FILE__ . ":" . __LINE__ );    # print it only first time
              }
              $processed = 0;
            }
          }
          else {
            $update_ret = rrd_update( "$rrd_file", "$time_r:$datar[$cycle_var+1]:$datar[$cycle_var+5]:$datar[$cycle_var+6]:$datar[$cycle_var+7]" );
            if ( $rrdcached == 0 ) { $answer = RRDp::read; }
          }
          $cputop++;
          my $rrd_file_cfg = $rrd_file;
          $rrd_file_cfg =~ s/\/cputop.*/\/$datar[$cycle_var+1]\.cfg/;
          write_lansancfg( $rrd_file_cfg, "$datar[$cycle_var+2]:$datar[$cycle_var+3]:$datar[$cycle_var+4]", $time, "1" );
        }

        # print "1234 \$time $time\n" if $datar[1] =~ "virtuals";
        last;
      };
      ############
      #### SOLARIS 10/11 - zones
      ############
      $datar[$cycle_var] !~ /mem|pgs|cpu$|lan-net\d|_ldom|netstat|vnetstat|san_l|san_tresp|pool-sol|sanmon/ && $server =~ /Solaris/ && do {
        if ( -f "$wrkdir/Solaris/$lpar_space/solaris11.txt" or -f "$wrkdir/Solaris/$lpar_space/solaris10.txt" ) {
          if ( isdigit( $datar[ $cycle_var + 1 ] ) && isdigit( $datar[ $cycle_var + 2 ] ) && isdigit( $datar[ $cycle_var + 3 ] ) && isdigit( $datar[ $cycle_var + 4 ] ) && isdigit( $datar[ $cycle_var + 5 ] ) && isdigit( $datar[ $cycle_var + 6 ] ) && isdigit( $datar[ $cycle_var + 7 ] ) && isdigit( $datar[ $cycle_var + 8 ] ) ) {
            $processed = 1;

            # print "1208 \$time $time\n" if $datar[1] =~ "virtuals";
            my $db_a = "";
            if ( $db_name =~ /\// ) {
              ( $db_a, $cdom_uuid ) = split( "\/", $db_name );
            }
            else {
              $db_a      = "$db_name";
              $cdom_uuid = "$lpar_space";
            }
            $rrd_file = "$wrkdir/Solaris/$lpar_space/ZONE/$db_a.mmm";
            if ( $first_lpar == 0 ) {

              # first insert through eval to be able to catch whatever error, next inserts with issues a new shell (eval)
              $first_lpar = 1;
              eval {
                $update_ret = rrd_update( "$rrd_file", "$time:$datar[$cycle_var+3]:$datar[$cycle_var+4]:$datar[$cycle_var+5]:$datar[$cycle_var+6]:$datar[$cycle_var+7]:$datar[$cycle_var+8]:$datar[$cycle_var+1]:$datar[$cycle_var+2]" );
                if ( $rrdcached == 0 ) { $answer = RRDp::read; }
              };
              if ( $update_ret == 0 || $@ ) {

                # error happened, zero the first_lpar to continue with eval
                $first_lpar = 0;
                if ( $error_first == 0 ) {
                  error( " updating $server:$lpar : $rrd_file : update_ret=$update_ret : $@ " . __FILE__ . ":" . __LINE__ );    # print it only first time
                }
                $processed = 0;
              }
            }
            else {
              $update_ret = rrd_update( "$rrd_file", "$time:$datar[$cycle_var+3]:$datar[$cycle_var+4]:$datar[$cycle_var+5]:$datar[$cycle_var+6]:$datar[$cycle_var+7]:$datar[$cycle_var+8]:$datar[$cycle_var+1]:$datar[$cycle_var+2]" );
              if ( $rrdcached == 0 ) { $answer = RRDp::read; }
            }
          }
          elsif ( isdigit( $datar[ $cycle_var + 3 ] ) && isdigit( $datar[ $cycle_var + 4 ] ) && isdigit( $datar[ $cycle_var + 5 ] ) ) {
            $processed = 1;

            # print "1208 \$time $time\n" if $datar[1] =~ "virtuals";
            my $db_a = "";
            if ( $db_name =~ /\// ) {
              ( $db_a, $cdom_uuid ) = split( "\/", $db_name );
            }
            else {
              $db_a      = "$db_name";
              $cdom_uuid = "$lpar_space";
            }
            $rrd_file = "$wrkdir/Solaris/$lpar_space/ZONE/$db_a.mmm";
            if ( $first_lpar == 0 ) {

              # first insert through eval to be able to catch whatever error, next inserts with issues a new shell (eval)
              $first_lpar = 1;
              eval {
                $update_ret = rrd_update( "$rrd_file", "$time:$datar[$cycle_var+3]:$datar[$cycle_var+4]:$datar[$cycle_var+5]" );
                if ( $rrdcached == 0 ) { $answer = RRDp::read; }
              };
              if ( $update_ret == 0 || $@ ) {

                #error happened, zero the first_lpar to continue with eval
                $first_lpar = 0;
                if ( $error_first == 0 ) {
                  error( " updating $server:$lpar : $rrd_file : update_ret=$update_ret : $@ " . __FILE__ . ":" . __LINE__ );    # print it only first time
                }
                $processed = 0;
              }
            }
            else {
              $update_ret = rrd_update( "$rrd_file", "$time:$datar[$cycle_var+3]:$datar[$cycle_var+4]:$datar[$cycle_var+5]" );
              if ( $rrdcached == 0 ) { $answer = RRDp::read; }
            }

          }

          # print "1234 \$time $time\n" if $datar[1] =~ "virtuals";
          last;
        }
      };

      $datar[$cycle_var] =~ /_ldom/ && $server =~ /Solaris/ && do {
        if ( isdigit( $datar[ $cycle_var + 3 ] ) && isdigit( $datar[ $cycle_var + 4 ] ) && isdigit( $datar[ $cycle_var + 5 ] ) ) {
          $processed = 1;

          # print "1208 \$time $time\n" if $datar[1] =~ "virtuals";
          my $char_ldom = "_ldom";

          #my $ldom_uuid_zone = "$datar[ $cycle_var + 1 ]";
          $db_name =~ s/\.mmm//g;
          my $db_name_without_ldom = "$db_name";
          $db_name_without_ldom =~ s/_ldom//g;
          if ( $agent_version >= 611 ) {
            $rrd_file = "$wrkdir/Solaris/$lpar_space/$db_name_without_ldom$char_ldom.mmm";
          }
          else {
            $rrd_file = "$wrkdir/Solaris/$db_name_without_ldom/$db_name_without_ldom$char_ldom.mmm";
          }
          if ( $first_lpar == 0 ) {

            # first insert through eval to be able to catch whatever error, next inserts with issues a new shell (eval)
            $first_lpar = 1;
            eval {
              $update_ret = rrd_update( "$rrd_file", "$time:$datar[$cycle_var+3]:$datar[$cycle_var+4]:$datar[$cycle_var+5]" );
              if ( $rrdcached == 0 ) { $answer = RRDp::read; }
            };
            if ( $update_ret == 0 || $@ ) {

              #error happened, zero the first_lpar to continue with eval
              $first_lpar = 0;
              if ( $error_first == 0 ) {
                error( " updating $server:$lpar : $rrd_file : update_ret=$update_ret : $@ " . __FILE__ . ":" . __LINE__ );    # print it only first time
              }
              $processed = 0;
            }
          }
          else {
            $update_ret = rrd_update( "$rrd_file", "$time:$datar[$cycle_var+3]:$datar[$cycle_var+4]:$datar[$cycle_var+5]" );
            if ( $rrdcached == 0 ) { $answer = RRDp::read; }
          }
        }

        # print "1234 \$time $time\n" if $datar[1] =~ "virtuals";
        last;
      };

      $datar[$cycle_var] =~ /san_l/ && $server =~ /Solaris/ && do {
        if ( isdigit( $datar[ $cycle_var + 3 ] ) && isdigit( $datar[ $cycle_var + 4 ] ) && isdigit( $datar[ $cycle_var + 5 ] && isdigit( $datar[ $cycle_var + 6 ] ) ) ) {
          $processed = 1;

          # print "1208 \$time $time\n" if $datar[1] =~ "virtuals";
          my $char_ldom = "_ldom";
          my $cdom_uuid = "$datar[ $cycle_var + 1 ]";
          $db_name =~ s/\.mmm//g;
          my $char_s = "san-";
          $rrd_file = "$wrkdir/Solaris/$lpar_space/$char_s$datar[ $cycle_var + 2 ].mmm";
          if ( $first_lpar == 0 ) {

            # first insert through eval to be able to catch whatever error, next inserts with issues a new shell (eval)
            $first_lpar = 1;
            eval {
              $update_ret = rrd_update( "$rrd_file", "$time:$datar[$cycle_var+3]:$datar[$cycle_var+4]:$datar[$cycle_var+5]:$datar[ $cycle_var + 6 ]" );
              if ( $rrdcached == 0 ) { $answer = RRDp::read; }
            };
            if ( $update_ret == 0 || $@ ) {

              #error happened, zero the first_lpar to continue with eval
              $first_lpar = 0;
              if ( $error_first == 0 ) {
                error( " updating $server:$lpar : $rrd_file : update_ret=$update_ret : $@ " . __FILE__ . ":" . __LINE__ );    # print it only first time
              }
              $processed = 0;
            }
          }
          else {
            $update_ret = rrd_update( "$rrd_file", "$time:$datar[$cycle_var+3]:$datar[$cycle_var+4]:$datar[$cycle_var+5]:$datar[ $cycle_var + 6 ]" );
            if ( $rrdcached == 0 ) { $answer = RRDp::read; }
          }
        }

        # print "1234 \$time $time\n" if $datar[1] =~ "virtuals";
        last;
      };
      $datar[$cycle_var] =~ /san_tresp/ && $server =~ /Solaris/ && do {
        if ( isdigit( $datar[ $cycle_var + 3 ] ) ) {
          $processed = 1;

          # print "1208 \$time $time\n" if $datar[1] =~ "virtuals";
          my $char_ldom = "_ldom";
          $cdom_uuid = "$datar[ $cycle_var + 1 ]";
          $db_name =~ s/\.mmm//g;
          my $char_s = "san_tresp-";
          $rrd_file = "$wrkdir/Solaris/$lpar_space/$char_s$datar[ $cycle_var + 2 ].mmm";
          if ( $first_lpar == 0 ) {

            # first insert through eval to be able to catch whatever error, next inserts with issues a new shell (eval)
            $first_lpar = 1;
            eval {
              $update_ret = rrd_update( "$rrd_file", "$time:$datar[$cycle_var+3]" );
              if ( $rrdcached == 0 ) { $answer = RRDp::read; }
            };
            if ( $update_ret == 0 || $@ ) {

              #error happened, zero the first_lpar to continue with eval
              $first_lpar = 0;
              if ( $error_first == 0 ) {
                error( " updating $server:$lpar : $rrd_file : update_ret=$update_ret : $@ " . __FILE__ . ":" . __LINE__ );    # print it only first time
              }
              $processed = 0;
            }
          }
          else {
            $update_ret = rrd_update( "$rrd_file", "$time:$datar[$cycle_var+3]" );
            if ( $rrdcached == 0 ) { $answer = RRDp::read; }
          }
        }

        # print "1234 \$time $time\n" if $datar[1] =~ "virtuals";
        last;
      };
      $datar[$cycle_var] eq "netstat" && $server =~ /Solaris/ && do {
        if ( isdigit( $datar[ $cycle_var + 3 ] ) && isdigit( $datar[ $cycle_var + 4 ] ) && isdigit( $datar[ $cycle_var + 5 ] && isdigit( $datar[ $cycle_var + 6 ] ) ) ) {
          $processed = 1;

          # print "1208 \$time $time\n" if $datar[1] =~ "virtuals";
          $cdom_uuid = "$datar[ $cycle_var + 1 ]";
          $datar[ $cycle_var + 2 ] =~ s/\//&&1/;
          $rrd_file = "$wrkdir/Solaris/$lpar_space/$datar[$cycle_var+2].mmm";
          if ( $first_lpar == 0 ) {

            # first insert through eval to be able to catch whatever error, next inserts with issues a new shell (eval)
            $first_lpar = 1;
            eval {
              $update_ret = rrd_update( "$rrd_file", "$time:$datar[$cycle_var+3]:$datar[$cycle_var+4]:$datar[$cycle_var+5]:$datar[$cycle_var+6]" );
              if ( $rrdcached == 0 ) { $answer = RRDp::read; }
            };
            if ( $update_ret == 0 || $@ ) {

              #error happened, zero the first_lpar to continue with eval
              $first_lpar = 0;
              if ( $error_first == 0 ) {
                error( " updating $server:$lpar : $rrd_file : update_ret=$update_ret : $@ " . __FILE__ . ":" . __LINE__ );    # print it only first time
              }
              $processed = 0;
            }
          }
          else {
            $update_ret = rrd_update( "$rrd_file", "$time:$datar[$cycle_var+3]:$datar[$cycle_var+4]:$datar[$cycle_var+5]:$datar[$cycle_var+6]" );
            if ( $rrdcached == 0 ) { $answer = RRDp::read; }
          }
        }
        last;
      };
      $datar[$cycle_var] eq "vnetstat" && $server =~ /Solaris/ && do {
        if ( isdigit( $datar[ $cycle_var + 3 ] ) && isdigit( $datar[ $cycle_var + 4 ] ) && isdigit( $datar[ $cycle_var + 5 ] && isdigit( $datar[ $cycle_var + 6 ] ) ) ) {
          $processed = 1;

          # print "1208 \$time $time\n" if $datar[1] =~ "virtuals";
          $cdom_uuid = "$datar[ $cycle_var + 1 ]";
          $datar[ $cycle_var + 2 ] =~ s/\//&&1/;
          my $char_s = "vlan-";
          $rrd_file = "$wrkdir/Solaris/$lpar_space/$char_s$datar[$cycle_var+2].mmm";
          if ( $first_lpar == 0 ) {

            # first insert through eval to be able to catch whatever error, next inserts with issues a new shell (eval)
            $first_lpar = 1;
            eval {
              $update_ret = rrd_update( "$rrd_file", "$time:$datar[$cycle_var+3]:$datar[$cycle_var+4]:$datar[$cycle_var+5]:$datar[$cycle_var+6]" );
              if ( $rrdcached == 0 ) { $answer = RRDp::read; }
            };
            if ( $update_ret == 0 || $@ ) {

              #error happened, zero the first_lpar to continue with eval
              $first_lpar = 0;
              if ( $error_first == 0 ) {
                error( " updating $server:$lpar : $rrd_file : update_ret=$update_ret : $@ " . __FILE__ . ":" . __LINE__ );    # print it only first time
              }
              $processed = 0;
            }
          }
          else {
            $update_ret = rrd_update( "$rrd_file", "$time:$datar[$cycle_var+3]:$datar[$cycle_var+4]:$datar[$cycle_var+5]:$datar[$cycle_var+6]" );
            if ( $rrdcached == 0 ) { $answer = RRDp::read; }
          }
        }
        last;
      };
      $datar[$cycle_var] eq "pool-sol" && $server =~ /Solaris/ && do {
        if ( isdigit( $datar[ $cycle_var + 3 ] ) && isdigit( $datar[ $cycle_var + 4 ] ) ) {
          $processed = 1;

          # print "1208 \$time $time\n" if $datar[1] =~ "virtuals";
          $datar[ $cycle_var + 1 ] =~ s/\//&&1/;
          $rrd_file = "$wrkdir/Solaris/$lpar_space/$datar[ $cycle_var + 1 ].mmm";
          if ( $first_lpar == 0 ) {

            # first insert through eval to be able to catch whatever error, next inserts with issues a new shell (eval)
            $first_lpar = 1;
            eval {
              $update_ret = rrd_update( "$rrd_file", "$time:$datar[$cycle_var+3]:$datar[$cycle_var+4]" );
              if ( $rrdcached == 0 ) { $answer = RRDp::read; }
            };
            if ( $update_ret == 0 || $@ ) {

              #error happened, zero the first_lpar to continue with eval
              $first_lpar = 0;
              if ( $error_first == 0 ) {
                error( " updating $server:$lpar : $rrd_file : update_ret=$update_ret : $@ " . __FILE__ . ":" . __LINE__ );    # print it only first time
              }
              $processed = 0;
            }
          }
          else {
            $update_ret = rrd_update( "$rrd_file", "$time:$datar[$cycle_var+3]:$datar[$cycle_var+4]" );
            if ( $rrdcached == 0 ) { $answer = RRDp::read; }
          }
        }
        last;
      };
      #
      # Hitachi file updates
      #

      "HSYS" eq $datar[$cycle_var] && "CPU" eq $datar[ $cycle_var + 1 ] && do {
        if ( isdigit( $datar[ $cycle_var + 3 ] ) && isdigit( $datar[ $cycle_var + 4 ] ) && isdigit( $datar[ $cycle_var + 5 ] ) && isdigit( $datar[ $cycle_var + 6 ] ) && isdigit( $datar[ $cycle_var + 7 ] ) ) {
          $processed = 1;

          if ( $first_lpar == 0 ) {

            # first insert through eval to be able to catch whatever error, next inserts with issues a new shell (eval)
            $first_lpar = 1;
            eval {
              $update_ret = rrd_update( "$rrd_file", "$time:$datar[$cycle_var+3]:$datar[$cycle_var+4]:$datar[$cycle_var+5]:$datar[$cycle_var+6]:$datar[$cycle_var+7]" );
              if ( $rrdcached == 0 ) { $answer = RRDp::read; }
            };
            if ( $update_ret == 0 || $@ ) {

              # error happened, zero the first_lpar to continue with eval
              $first_lpar = 0;
              if ( $error_first == 0 ) {
                error( " updating $server:$lpar : $rrd_file : update_ret=$update_ret : $@ " . __FILE__ . ":" . __LINE__ );    # print it only first time
              }
              $processed = 0;
            }
          }
          else {
            $update_ret = rrd_update( "$rrd_file", "$time:$datar[$cycle_var+3]:$datar[$cycle_var+4]:$datar[$cycle_var+5]:$datar[$cycle_var+6]:$datar[$cycle_var+7]" );
            if ( $rrdcached == 0 ) { $answer = RRDp::read; }
          }

        }
        last;
      };

      "HSYS" eq $datar[$cycle_var] && "MEM" eq $datar[ $cycle_var + 1 ] && do {
        if ( isdigit( $datar[ $cycle_var + 3 ] ) && isdigit( $datar[ $cycle_var + 4 ] ) && isdigit( $datar[ $cycle_var + 6 ] ) ) {
          $processed = 1;

          if ( $first_lpar == 0 ) {

            # first insert through eval to be able to catch whatever error, next inserts with issues a new shell (eval)
            $first_lpar = 1;
            eval {
              $update_ret = rrd_update( "$rrd_file", "$time:$datar[$cycle_var+3]:$datar[$cycle_var+4]:$datar[$cycle_var+6]" );
              if ( $rrdcached == 0 ) { $answer = RRDp::read; }
            };
            if ( $update_ret == 0 || $@ ) {

              # error happened, zero the first_lpar to continue with eval
              $first_lpar = 0;
              if ( $error_first == 0 ) {
                error( " updating $server:$lpar : $rrd_file : update_ret=$update_ret : $@ " . __FILE__ . ":" . __LINE__ );    # print it only first time
              }
              $processed = 0;
            }
          }
          else {
            $update_ret = rrd_update( "$rrd_file", "$time:$datar[$cycle_var+3]:$datar[$cycle_var+4]:$datar[$cycle_var+6]" );
            if ( $rrdcached == 0 ) { $answer = RRDp::read; }
          }

        }
        last;
      };

      "HCPU" eq $datar[$cycle_var] && $datar[ $cycle_var + 1 ] =~ /SYS/ && do {
        if ( isdigit( $datar[ $cycle_var + 3 ] ) && isdigit( $datar[ $cycle_var + 5 ] ) && isdigit( $datar[ $cycle_var + 6 ] ) && isdigit( $datar[ $cycle_var + 7 ] ) ) {
          $processed = 1;

          if ( $first_lpar == 0 ) {

            # first insert through eval to be able to catch whatever error, next inserts with issues a new shell (eval)
            $first_lpar = 1;
            eval {
              $update_ret = rrd_update( "$rrd_file", "$time:$datar[$cycle_var+3]:$datar[$cycle_var+5]:$datar[$cycle_var+6]:$datar[$cycle_var+7]" );
              if ( $rrdcached == 0 ) { $answer = RRDp::read; }
            };
            if ( $update_ret == 0 || $@ ) {

              # error happened, zero the first_lpar to continue with eval
              $first_lpar = 0;
              if ( $error_first == 0 ) {
                error( " updating $server:$lpar : $rrd_file : update_ret=$update_ret : $@ " . __FILE__ . ":" . __LINE__ );    # print it only first time
              }
              $processed = 0;
            }
          }
          else {
            $update_ret = rrd_update( "$rrd_file", "$time:$datar[$cycle_var+3]:$datar[$cycle_var+5]:$datar[$cycle_var+6]:$datar[$cycle_var+7]" );
            if ( $rrdcached == 0 ) { $answer = RRDp::read; }
          }

        }
        last;
      };

      "HCPU" eq $datar[$cycle_var] && $datar[ $cycle_var + 1 ] =~ /(SHR_LPAR|DED_LPAR)/ && do {
        if ( isdigit( $datar[ $cycle_var + 3 ] ) && isdigit( $datar[ $cycle_var + 4 ] ) && isdigit( $datar[ $cycle_var + 5 ] ) && isdigit( $datar[ $cycle_var + 6 ] ) && isdigit( $datar[ $cycle_var + 7 ] ) ) {
          $processed = 1;

          if ( $first_lpar == 0 ) {

            # first insert through eval to be able to catch whatever error, next inserts with issues a new shell (eval)
            $first_lpar = 1;
            eval {
              $update_ret = rrd_update( "$rrd_file", "$time:$datar[$cycle_var+3]:$datar[$cycle_var+4]:$datar[$cycle_var+5]:$datar[$cycle_var+6]:$datar[$cycle_var+7]" );
              if ( $rrdcached == 0 ) { $answer = RRDp::read; }
            };
            if ( $update_ret == 0 || $@ ) {

              # error happened, zero the first_lpar to continue with eval
              $first_lpar = 0;
              if ( $error_first == 0 ) {
                error( " updating $server:$lpar : $rrd_file : update_ret=$update_ret : $@ " . __FILE__ . ":" . __LINE__ );    # print it only first time
              }
              $processed = 0;
            }
          }
          else {
            $update_ret = rrd_update( "$rrd_file", "$time:$datar[$cycle_var+3]:$datar[$cycle_var+4]:$datar[$cycle_var+5]:$datar[$cycle_var+6]:$datar[$cycle_var+7]" );
            if ( $rrdcached == 0 ) { $answer = RRDp::read; }
          }

        }
        last;
      };

      ( "HLPAR" eq $datar[$cycle_var] || "HNIC" eq $datar[$cycle_var] || "HHBA" eq $datar[$cycle_var] ) && do {
        if ( isdigit( $datar[ $cycle_var + 3 ] ) && isdigit( $datar[ $cycle_var + 4 ] ) && isdigit( $datar[ $cycle_var + 5 ] ) && isdigit( $datar[ $cycle_var + 6 ] ) && isdigit( $datar[ $cycle_var + 7 ] ) && isdigit( $datar[ $cycle_var + 8 ] ) ) {
          $processed = 1;

          if ( $first_lpar == 0 ) {

            # first insert through eval to be able to catch whatever error, next inserts with issues a new shell (eval)
            $first_lpar = 1;
            eval {
              $update_ret = rrd_update( "$rrd_file", "$time:$datar[$cycle_var+3]:$datar[$cycle_var+4]:$datar[$cycle_var+5]:$datar[$cycle_var+6]:$datar[$cycle_var+7]:$datar[$cycle_var+8]" );
              if ( $rrdcached == 0 ) { $answer = RRDp::read; }
            };
            if ( $update_ret == 0 || $@ ) {

              # error happened, zero the first_lpar to continue with eval
              $first_lpar = 0;
              if ( $error_first == 0 ) {
                error( " updating $server:$lpar : $rrd_file : update_ret=$update_ret : $@ " . __FILE__ . ":" . __LINE__ );    # print it only first time
              }
              $processed = 0;
            }
          }
          else {
            $update_ret = rrd_update( "$rrd_file", "$time:$datar[$cycle_var+3]:$datar[$cycle_var+4]:$datar[$cycle_var+5]:$datar[$cycle_var+6]:$datar[$cycle_var+7]:$datar[$cycle_var+8]" );
            if ( $rrdcached == 0 ) { $answer = RRDp::read; }
          }

        }
        last;
      };

      "HMEM" eq $datar[$cycle_var] && "SYS" eq $datar[ $cycle_var + 1 ] && do {
        if ( isdigit( $datar[ $cycle_var + 3 ] ) && isdigit( $datar[ $cycle_var + 4 ] ) ) {
          $processed = 1;

          if ( $first_lpar == 0 ) {

            # first insert through eval to be able to catch whatever error, next inserts with issues a new shell (eval)
            $first_lpar = 1;
            eval {
              $update_ret = rrd_update( "$rrd_file", "$time:$datar[$cycle_var+3]:$datar[$cycle_var+4]" );
              if ( $rrdcached == 0 ) { $answer = RRDp::read; }
            };
            if ( $update_ret == 0 || $@ ) {

              # error happened, zero the first_lpar to continue with eval
              $first_lpar = 0;
              if ( $error_first == 0 ) {
                error( " updating $server:$lpar : $rrd_file : update_ret=$update_ret : $@ " . __FILE__ . ":" . __LINE__ );    # print it only first time
              }
              $processed = 0;
            }
          }
          else {
            $update_ret = rrd_update( "$rrd_file", "$time:$datar[$cycle_var+3]:$datar[$cycle_var+4]" );
            if ( $rrdcached == 0 ) { $answer = RRDp::read; }
          }

        }
        last;
      };

      "HMEM" eq $datar[$cycle_var] && "LPAR" eq $datar[ $cycle_var + 1 ] && do {
        if ( isdigit( $datar[ $cycle_var + 3 ] ) && isdigit( $datar[ $cycle_var + 4 ] ) && isdigit( $datar[ $cycle_var + 5 ] ) ) {
          $processed = 1;

          if ( $first_lpar == 0 ) {

            # first insert through eval to be able to catch whatever error, next inserts with issues a new shell (eval)
            $first_lpar = 1;
            eval {
              $update_ret = rrd_update( "$rrd_file", "$time:$datar[$cycle_var+3]:$datar[$cycle_var+4]:$datar[$cycle_var+5]" );
              if ( $rrdcached == 0 ) { $answer = RRDp::read; }
            };
            if ( $update_ret == 0 || $@ ) {

              # error happened, zero the first_lpar to continue with eval
              $first_lpar = 0;
              if ( $error_first == 0 ) {
                error( " updating $server:$lpar : $rrd_file : update_ret=$update_ret : $@ " . __FILE__ . ":" . __LINE__ );    # print it only first time
              }
              $processed = 0;
            }
          }
          else {
            $update_ret = rrd_update( "$rrd_file", "$time:$datar[$cycle_var+3]:$datar[$cycle_var+4]:$datar[$cycle_var+5]" );
            if ( $rrdcached == 0 ) { $answer = RRDp::read; }
          }

        }
        last;
      };
      "disk-total" eq $datar[$cycle_var] && do {
        if ( isdigit( $datar[ $cycle_var + 1 ] ) && isdigit( $datar[ $cycle_var + 2 ] ) && isdigit( $datar[ $cycle_var + 3 ] ) && isdigit( $datar[ $cycle_var + 4 ] ) && isdigit( $datar[ $cycle_var + 5 ] ) && isdigit( $datar[ $cycle_var + 6 ] ) ) {
          $processed = 1;
          if ( $first_mem == 0 ) {

            # first insert through eval to be able to catch nwhatever error, next inserts with issues a new shell (eval)
            $first_mem = 1;
            eval {
              $update_ret = rrd_update( "$rrd_file", "$time:$datar[$cycle_var+1]:$datar[$cycle_var+2]:$datar[$cycle_var+3]:$datar[$cycle_var+4]:$datar[$cycle_var+5]:$datar[$cycle_var+6]" );
              if ( $rrdcached == 0 ) { $answer = RRDp::read; }
            };
            if ( $update_ret == 0 || $@ ) {

              # error happened, zero the first_mem to continue with eval
              $first_mem = 0;
              if ( $error_first == 0 ) {
                error( " updating $server:$lpar : $rrd_file : update_ret=$update_ret : $@ " . __FILE__ . ":" . __LINE__ );    # print it only first time
              }
              $processed = 0;
            }
          }
          else {
            $update_ret = rrd_update( "$rrd_file", "$time:$datar[$cycle_var+1]:$datar[$cycle_var+2]:$datar[$cycle_var+3]:$datar[$cycle_var+4]:$datar[$cycle_var+5]:$datar[$cycle_var+6]" );
            if ( $rrdcached == 0 ) { $answer = RRDp::read; }
          }
        }
        last;
      };
      $datar[$cycle_var] =~ /sanmon/ && $server =~ /Solaris/ && do {
        if ( isdigit( $datar[ $cycle_var + 1 ] ) && isdigit( $datar[ $cycle_var + 2 ] ) && isdigit( $datar[ $cycle_var + 3 ] ) && isdigit( $datar[ $cycle_var + 4 ] ) ) {
          $processed = 1;
          $rrd_file  = "$wrkdir/Solaris--unknown/no_hmc/$lpar_space/total-san.mmm";
          if ( $first_lpar == 0 ) {

            # first insert through eval to be able to catch whatever error, next inserts with issues a new shell (eval)
            $first_lpar = 1;
            eval {
              $update_ret = rrd_update( "$rrd_file", "$time:$datar[$cycle_var+1]:$datar[$cycle_var+2]:$datar[$cycle_var+3]:$datar[$cycle_var+4]" );
              if ( $rrdcached == 0 ) { $answer = RRDp::read; }
            };
            if ( $update_ret == 0 || $@ ) {

              #error happened, zero the first_lpar to continue with eval
              $first_lpar = 0;
              if ( $error_first == 0 ) {
                error( " updating $server:$lpar : $rrd_file : update_ret=$update_ret : $@ " . __FILE__ . ":" . __LINE__ );    # print it only first time
              }
              $processed = 0;
            }
          }
          else {
            $update_ret = rrd_update( "$rrd_file", "$time:$datar[$cycle_var+1]:$datar[$cycle_var+2]:$datar[$cycle_var+3]:$datar[$cycle_var+4]" );
            if ( $rrdcached == 0 ) { $answer = RRDp::read; }
          }
        }

        # print "1234 \$time $time\n" if $datar[1] =~ "virtuals";
        last;
      };

      #error ("Unknown item from agent : $server:$lpar : $datar[$cycle_var] ($datar[$cycle_var+1]:$datar[$cycle_var+2]:$datar[$cycle_var+3]:$datar[$cycle_var+4]) ".__FILE__.":".__LINE__);
    }

    # place item to skip to next line if you need to skip it
    my $item_to_skip = "";

    if ( $datar[$cycle_var] eq $item_to_skip ) {
      print "skip item : $datar[$cycle_var] $cycle_var : $time:$datar[$cycle_var+3]:$datar[$cycle_var+4]:$datar[$cycle_var+5]:$datar[$cycle_var+6] \n";
    }
    else {

      if ( $processed == 0 && $error_first == 0 ) {
        error( "Unprocessed data from agent : $server:$lpar : $datar[$cycle_var]:$datar[$cycle_var+1]:$datar[$cycle_var+2]:$datar[$cycle_var+3]:$datar[$cycle_var+4]:$datar[$cycle_var+5]:$datar[$cycle_var+6]:$datar[$cycle_var+7]:$datar[$cycle_var+8], only first error occurence is reported ) " . __FILE__ . ":" . __LINE__ );
        $error_first = 1;
      }
      print "000 : $datar[$cycle_var] $cycle_var : $time:$datar[$cycle_var+3]:$datar[$cycle_var+4]:$datar[$cycle_var+5]:$datar[$cycle_var+6] \n" if $DEBUG == 2;

      #   my $answer = RRDp::read;
      if ( $processed == 1 && $rrdcached == 0 && !$$answer eq '' && $$answer =~ m/ERROR/ ) {
        error( " updating $server:$lpar : $rrd_file : $$answer" . __FILE__ . ":" . __LINE__ );
        if ( $$answer =~ m/is not an RRD file/ ) {
          ( my $err, my $file, my $txt ) = split( /'/, $$answer );
          error( "Removing as it seems to be corrupted: $file" . __FILE__ . ":" . __LINE__ );
          unlink("$file") || error( "Cannot rm $file : $!" . __FILE__ . ":" . __LINE__ );
        }

        # continue here although some error apeared just to do not stuck here for ever
      }
    }

    # prepare next cycle - always skips 9 atoms
    $cycle_var = $cycle_var + 9;
  }

  # save uuids from Hitachi
  if ( $server_space eq "Hitachi" ) {
    hitachi_agent_mapping( $lpar_space, \%hitachi_lpar_uuids );
  }

  #print "001 : $datar[$cycle_var] $cycle_var\n" if $DEBUG == 2;
  print "1151 finish storing data from agent\n" if $DEBUG == 2;

  # print "1259 \$time $time\n" if $datar[1] =~ "virtuals";
  return $time;    # return time of last record
}

# provides easy uuid check, pays for 1 arg only
sub uuid_check {

  return ( $_[0] =~ m{.{8}-.{4}-.{4}-.{4}-.{12}} );

}

sub alert_multipath {
  my $os            = shift;
  my $lines         = shift;
  my $alias_actual  = shift;
  my $status_actual = shift;
  my $server        = shift;
  my $lpar          = shift;

  my $split_alias_actual  = "$alias_actual";
  my ($grep_alias_actual) = split /\(/, $split_alias_actual;
  $grep_alias_actual =~ s/\s+$//g;

  my $server_name = get_name_server_for_alert($server);
  my $lpar_name   = "";

  #my $grep_alias_actual = $alias_actual;
  $alias_actual  =~ s/=====double-colon=====/ /g;
  $status_actual =~ s/=====double-colon=====/ /g;

  #print "===========DATA=============\n";
  #print "starej file (kontrola predesleho reportu): $lines\n";
  #print "AGENT alias:|$alias_actual|\n";
  #print "AGENT status:!$status_actual!\n";

  my $status           = "OK";
  my $old_report_check = "OK";

  # old report multipath
  if ( $os eq "LINUX" ) {

    # file linux_multipathing.txt exists
    if ( $lines ne "no_file" ) {

      # CHECK ERROR IN OLD REPORT
      my ($match) = grep( /$grep_alias_actual \(/, $lines );
      if ( $match =~ /failed|offline/ ) {
        $old_report_check = "NOK";
      }
      if ( $status_actual =~ /failed|offline/ ) {
        $status = "NOK";
      }
    }

    # first run
    else {
      if ( $status_actual =~ /failed|offline/ ) {
        $status = "NOK";
      }
      else {
        $status = "OK";
      }
    }
  }

  if ( $os eq "AIX" ) {

    # file aix_multipathing.txt exists
    if ( $lines ne "no_file" ) {

      # CHECK ERROR IN OLD REPORT
      my ($match) = grep( /$grep_alias_actual/, $lines );
      if ( $match =~ /Missing|Failed/ ) {
        $old_report_check = "NOK";
      }
      if ( $status_actual =~ /Missing|Failed/ ) {
        $status = "NOK";
      }
    }

    # first run
    else {
      if ( $status_actual =~ /Missing|Failed/ ) {
        $status = "NOK";
      }
      else {
        $status = "OK";
      }
    }
  }

  if ( $status eq "OK" ) {
    return $status;    # get out when all is fine
  }

  my $file = "$basedir/etc/web_config/alerting.cfg";

  if ( !-f $file ) {

    #error ("Does not exist $file $!".__FILE__.":".__LINE__);
    return 0;
  }

  # data from config alerting.cfg
  my @data = get_array_data($file);

  ### save data from alert.cfg

  my %groups = ();
  foreach my $line (@data) {
    chomp $line;
    if ( $line eq "" || $line =~ m/^#/ ) { next; }
    $line =~ s/^\s+|\s+$//g;
    if ( $line eq "" || $line =~ m/^#/ ) { next; }
    if ( $line =~ m/^LPAR/ || $line =~ m/^POOL/ ) {
      my $pom_line = $line;
      $pom_line =~ s/\\:/=====doublecoma=====/g;
      ( undef, my $server, my $lpar, my $metric, my $max, my $peek, my $repeat, my $exclude_time, my $email, undef, my $any_name ) = split( ":", $pom_line );
      my $g_key_s = "";
      my $g_key_l = "";
      if ( !defined $server || $server eq "" ) {
        $g_key_s = "nos";
      }
      else {
        $g_key_s = $server;
      }
      if ( !defined $any_name || $any_name eq "" ) {
        $g_key_l = "nol";
      }
      else {
        $g_key_l = $any_name;
      }
      $g_key_s .= $g_key_l;
      $groups{$g_key_s} = 1;

      #print Dumper(\%groups);
      if ( ( scalar keys %groups > ( $one_day_sample / 360 + 0.5 ) ) && ( ( length($log_err_v) + 1 ) == length($log_err) ) ) { last; }
      if ( $line =~ m/^POOL/ )                                                                                               { next; }
      if ( defined $server && $server ne "" ) {
        if ( $server ne $server_name ) { next; }
      }
      if ( ( !defined $lpar || $lpar eq "" ) && ( !defined $server || $server eq "" ) ) {
        push @{ $inventory_alert{DATA_MULTI} }, "$line";    ### new general rule
        next;
      }
      if ( ( !defined $lpar || $lpar eq "" ) && ( defined $server && $server eq $server_name ) ) {
        push @{ $inventory_alert{DATA_MULTI} }, "$line";    ### new general rule
        next;
      }
      $lpar =~ s/=====doublecoma=====/:/g;
      if ( $lpar_name eq $lpar ) {
        push @{ $inventory_alert{DATA_MULTI} }, "$line";
      }
    }
    else {
      push @{ $inventory_alert{INFO_MULTI} }, "$line";
    }
  }

  ### set up global info for alerting

  foreach my $line ( @{ $inventory_alert{"INFO_MULTI"} } ) {
    chomp $line;
    $line =~ s/^\s+|\s+$//g;

    if ( $line =~ m/^ALERT_HISTORY=|^PEAK_TIME_DEFAULT=|^REPEAT_DEFAULT=|^EMAIL_GRAPH=|^NAGIOS=|^EXTERN_ALERT=|^TRAP=|^MAILFROM=/ ) {
      ( my $property, my $value ) = split( /=/, $line );
      if ( defined $property && $property ne "" && defined $value && $value ne "" ) {
        $value =~ s/ //g;
        $value =~ s/>//g;
        $value =~ s/#.*$//g;
        $value =~ s/^\s+|\s+$//g;
        $inventory_alert{GLOBAL}{$property} = $value;
        next;
      }
    }

    # EMAIL section
    if ( $line =~ m/^EMAIL:/ ) {
      ( undef, my $email_group, my $emails ) = split( /:/, $line );
      if ( defined $email_group && $email_group ne "" && defined $emails && $emails ne "" ) {
        $inventory_alert{GLOBAL}{EMAIL}{$email_group} = $emails;
      }
    }

    if ( $line =~ m/^MAILFROM=/ ) {
      my $mail = $line;
      $mail =~ s/^MAILFROM=//;
      if ( defined $mail && $mail ne '' ) {
        $inventory_alert{GLOBAL}{'MAILFROM'} = $mail;
      }
    }
    if ( $line =~ m/^EMAIL_EVENT=/ ) {
      my $mail_send = $line;
      $mail_send =~ s/^EMAIL_EVENT=//;
      if ( defined $mail_send && $mail_send ne '' ) {
        $inventory_alert{GLOBAL}{'EMAIL_EVENT'} = $mail_send;
      }
    }
  }

  #print Dumper \%inventory_alert;

  ### email send to
  my $email_to_log = "";
  my $email        = $inventory_alert{GLOBAL}{EMAIL_EVENT};
  if ( !defined $email || $email eq '' ) {
    $email_to_log = "no email";
  }
  ### email from
  my $mailfrom = $inventory_alert{GLOBAL}{MAILFROM};
  if ( !defined $mailfrom || $mailfrom eq '' ) {
    $mailfrom = "support\@xorux.com";
  }

  my $ltime_str       = localtime();
  my $alert_type_text = "Multipath";
  my $util            = "";
  my $last_type       = "";
  my $unit            = "";
  ### alert history
  my $alert_history_hw = "$basedir/logs/alert_event_history.log";

  #print "STATUS: new-$status || old-$old_report_check\n";
  # ALERT log in GUI
  open( FHL, ">> $alert_history_hw" ) || error( "could not open $alert_history_hw: $!" . __FILE__ . ":" . __LINE__ ) && return 1;

  if ( $status eq "NOK" && $old_report_check eq "OK" ) {

    #print "Alerting disk!!!\n";
    my $status = "ERROR";

    #SUBJECT: Multipath alert for: LPAR
    #BODY: Date, time: Multipath alert for: LPAR: p770-demo: Server: Power770 Disk: compellent-demo02 Status:
    if ( defined $email && $email ne "" ) {
      $email_to_log = "email: $email";
      sendmail( $mailfrom, $email, "$ltime_str: Multipath alert for:\n LPAR: $lpar\n Server: $server_name\n Disk: $grep_alias_actual\n Status: $status", $lpar, $util, $last_type, $alert_type_text, $server_name, "", "", $unit, "MULTI_OK" );
    }

    # Alert log in GUI
    print FHL "$ltime_str; $alert_type_text; $last_type; $server_name; $lpar; Disk: $grep_alias_actual, Status: $status, $email_to_log\n";
    close(FHL);
  }
  return $status;
}

sub write_lansancfg {

  # write cfg files containing IP (for enXX) & WWN (for fcsXX) & name for sea
  # since 4.7 it saves agent version

  my $rrd_file   = shift;
  my $enip       = shift;    # cfg info
  my $time       = shift;
  my $force_save = shift;    # if (1) then save immediatelly

  return if $rrd_file eq ""; # sometimes happens

  if ( !defined $force_save ) {
    $force_save = 0;
  }
  my $DEBUG = 2;

  # print "sub write cfg file, rrd_file  $rrd_file \$enip $enip\n" if $DEBUG == 2;

  if ( $enip =~ /version/ && $rrd_file =~ /cpu\.mmm$/ ) {
    $rrd_file =~ s/cpu\.mmm$/agent\.cfg/;
    if ( $rrd_file !~ /agent\.cfg/ ) {
      print "could not prepare filename agent.cfg in $rrd_file\n";
      return 0;
    }
    ( undef, $enip, undef ) = split( 'version ', $enip );
  }
  elsif ( uuid_check($enip) && $rrd_file =~ /cpu\.mmm$/ ) {
    $rrd_file =~ s/cpu\.mmm$/uuid\.txt/;
    if ( $rrd_file !~ /uuid\.txt/ ) {
      print "could not prepare filename uuid.txt in $rrd_file\n";
      return 0;
    }
  }
  else {
    $rrd_file =~ s/\.mmm$/\.cfg/;
    $rrd_file =~ s/\.mmc$/\.cfg/;
  }

  if ( !-f $rrd_file || -s $rrd_file == 0 ) {
    open( FW, "> $rrd_file" ) || error( "Can't open $rrd_file : $! " . __FILE__ . ":" . __LINE__ ) && return 0;
    print FW "$enip\n";
    close(FW);

    # hard link $rrd_file into the other HMC if there is dual HMC setup
    h_link( $rrd_file, $wrkdir );
  }
  else {
    my $timem = ( ( stat($rrd_file) )[9] );
    if ( $force_save || ( ( $time - $timem ) > 86400 ) ) {
      open( FW, "> $rrd_file" ) || error( "Can't open $rrd_file : $! " . __FILE__ . ":" . __LINE__ ) && return 0;
      print FW "$enip\n";
      close(FW);
    }
  }
}

sub h_link {
  my $file_to_hlink = shift;
  my $wrkdir        = shift;

  my $name_under_wrkdir = substr $file_to_hlink, length($wrkdir) + 1;    # also leading slash
                                                                         #print "\$name_under_wrkdir ,$name_under_wrkdir,\n";

  ( my $server, my $hmc, my $name_under_hmc ) = split( "\/", $name_under_wrkdir, 3 );

  #print "\$server $server \$hmc $hmc \$name_under_hmc $name_under_hmc\n";

  my $w_server = "$wrkdir/$server";
  if ( $w_server =~ m/ / ) {
    $w_server = "\"" . $w_server . "\"";    # it must be here to support space with server names
  }

  my @hmcs = <$w_server/*>;

  foreach (@hmcs) {
    my $hmc_dir_new = $_;
    chomp($hmc_dir_new);
    next if !-d $hmc_dir_new;

    next if index( $file_to_hlink, $hmc_dir_new ) != -1;    # not itself

    my $file_link = "$hmc_dir_new/$name_under_hmc";

    my $base_file_link = dirname($file_link);

    #print "\$base_file_link $base_file_link\n";
    if ( !-d "$base_file_link" ) {
      print_it("mkdir dual     : $base_file_link/") if $DEBUG;
      makex_path("$base_file_link") || error( "Cannot mkdir for $base_file_link: $!" . __FILE__ . ":" . __LINE__ ) && next;
      touch("$base_file_link");
    }
    if ( -f "$file_link" ) {
      next;
    }
    print_it("hard link      : $file_to_hlink --> $file_link\n") if $DEBUG;

    #unlink("$file_link");    # for sure
    link( $file_to_hlink, "$file_link" ) || error( "Cannot link $file_to_hlink:$file_link : $!" . __FILE__ . ":" . __LINE__ ) && next;

  }
}

sub store_data_hmc {
  my $data             = shift;
  my $last_rec         = shift;
  my $protocol_version = shift;
  my $peer_address     = shift;
  my $en_last_rec      = $last_rec;
  my $act_time         = localtime();

  # example data from hmc
  # :ahmc11::1399820175:Sun May 11 16:56:15 2014::::H:
  # cpu:::123456789:22036313:43535299:64833077:::mem:::4128368:4066672:61696:U:U:U:pgs:::U:U:1992:0.0::

  my @datar = split( ":", $data . "sentinel" );
  $datar[-1] =~ s/sentinel$//;
  my $datar_len = @datar;
  my $hmc       = $datar[1];
  my $time      = $datar[3];
  $hmc =~ s/====double-colon=====/:/g;
  my $rrd_file = "";

  #
  # cycle for non-mandatory items
  #

  my $cycle_var = 11;    # is a pointer to data array
  while ( $datar[$cycle_var] ) {
    my $db_name = "$datar[$cycle_var]";    #prepare db name
    $db_name .= "\.mmx";
    $rrd_file = "$wrkdir/--HMC--$hmc/$db_name";
    print "$act_time: Updating 0     : name is $db_name rrd is $rrd_file\n" if $DEBUG == 2;
    if ( -f $rrd_file ) {
      my $filesize = -s "$rrd_file";
      if ( $filesize == 0 ) {

        # when a FS is full then it creates 0 Bytes rrdtool files what is a problem, delete it then
        error( "0 size rrd file: $rrd_file  - delete it" . __FILE__ . ":" . __LINE__ );
        unlink("$rrd_file") || error( "Cannot rm $rrd_file : $!" . __FILE__ . ":" . __LINE__ );
        $rrd_file = "";    # force to create a new one
      }
    }

    if ( !-f $rrd_file ) {
      if ( create_rrd_hmc( $hmc, $time, $db_name ) == 0 ) {
        return 0;
      }
    }
    $rrd_file = "$wrkdir/--HMC--$hmc/$db_name";
    print "$act_time: Updating 1 hmc  : $hmc : - $rrd_file - last_rec: $last_rec\n" if $DEBUG == 2;
    if ( $last_rec == 0 ) {

      # construction against crashing daemon Perl code when RRDTool error appears
      # this does not work well in old RRDTOool: $RRDp::error_mode = 'catch';
      # construction is not too costly as it runs once per each load
      eval {
        RRDp::cmd qq(last "$rrd_file" );
        my $last_rec_rrd = RRDp::read;
        chomp($$last_rec_rrd);
        $last_rec = $$last_rec_rrd;
      };
      if ($@) {
        rrd_error( $@ . __FILE__ . ":" . __LINE__, $rrd_file );
        return 0;
      }
    }
    print "$act_time: Updating 2 hmc : $hmc : - $rrd_file - last_rec: $last_rec\n" if $DEBUG == 2;
    if ( ( $last_rec + $STEP / 2 ) >= $time ) {
      error( "$hmc : last rec : $last_rec + $STEP/2 >= $time, ignoring it ..." . __FILE__ . ":" . __LINE__ );
      print "$act_time: Updating 2 hmc : $last_rec : $time : $rrd_file\n" if $DEBUG == 2;
      return $time;    # returns original time, not last_rec
                       # --> no, no, it is not wrong, just ignore it!
    }
    print "$act_time: Updating 4 hmc : $hmc: - $rrd_file - last_rec: $last_rec\n" if $DEBUG == 2;

    #
    # files update
    #

    # alias case structure
    print "$act_time: case struc : $rrd_file : $cycle_var : $datar[$cycle_var]\n" if $DEBUG == 2;
    my $answer     = "";
    my $processed  = 0;
    my $update_ret = 1;
    {
      "mem" eq $datar[$cycle_var] && do {
        if ( isdigit( $datar[ $cycle_var + 3 ] ) && isdigit( $datar[ $cycle_var + 4 ] ) && isdigit( $datar[ $cycle_var + 5 ] ) && isdigit( $datar[ $cycle_var + 6 ] ) && isdigit( $datar[ $cycle_var + 7 ] ) && isdigit( $datar[ $cycle_var + 8 ] ) ) {
          $update_ret = rrd_update( "$rrd_file", "$time:$datar[$cycle_var+3]:$datar[$cycle_var+4]:$datar[$cycle_var+5]:$datar[$cycle_var+6]:$datar[$cycle_var+7]:$datar[$cycle_var+8]" );
          if ( $rrdcached == 0 ) { $answer = RRDp::read; }
          $processed = 1;
        }
        last;
      };
      "pgs" eq $datar[$cycle_var] && do {
        if ( isdigit( $datar[ $cycle_var + 3 ] ) && isdigit( $datar[ $cycle_var + 4 ] ) && isdigit( $datar[ $cycle_var + 5 ] ) && isdigit( $datar[ $cycle_var + 6 ] ) ) {
          $update_ret = rrd_update( "$rrd_file", "$time:$datar[$cycle_var+3]:$datar[$cycle_var+4]:$datar[$cycle_var+5]:$datar[$cycle_var+6]" );
          if ( $rrdcached == 0 ) { $answer = RRDp::read; }
          $processed = 1;
        }
        last;
      };
      "cpu" eq $datar[$cycle_var] && do {
        if ( isdigit( $datar[ $cycle_var + 3 ] ) && isdigit( $datar[ $cycle_var + 4 ] ) && isdigit( $datar[ $cycle_var + 5 ] ) && isdigit( $datar[ $cycle_var + 6 ] ) ) {

          # print "update data hmc - $rrd_file\n";
          $update_ret = rrd_update( "$rrd_file", "$time:$datar[$cycle_var+3]:$datar[$cycle_var+4]:$datar[$cycle_var+5]:$datar[$cycle_var+6]" );
          if ( $rrdcached == 0 ) { $answer = RRDp::read; }
          $processed = 1;
        }
        last;
      };
    }
    if ( $processed == 0 && $error_first == 0 ) {
      error( "Unprocessed data from agent hmc : $datar[$cycle_var]:$datar[$cycle_var+1]:$datar[$cycle_var+2]:$datar[$cycle_var+3]:$datar[$cycle_var+4]:$datar[$cycle_var+5]:$datar[$cycle_var+6]:$datar[$cycle_var+7]:$datar[$cycle_var+8], only first error occurence is reported ) " . __FILE__ . ":" . __LINE__ );
      $error_first = 1;
    }
    print "000 hmc : $datar[$cycle_var] $cycle_var : $time:$datar[$cycle_var+3]:$datar[$cycle_var+4]:$datar[$cycle_var+5]:$datar[$cycle_var+6] \n" if $DEBUG == 2;
    if ( $processed == 1 && $rrdcached == 0 && !$$answer eq '' && $$answer =~ m/ERROR/ ) {
      error( " updating hmc : $rrd_file : $$answer" . __FILE__ . ":" . __LINE__ );
      if ( $$answer =~ m/is not an RRD file/ ) {
        ( my $err, my $file, my $txt ) = split( /'/, $$answer );
        error( "Removing as it seems to be corrupted: $file" . __FILE__ . ":" . __LINE__ );
        unlink("$file") || error( "Cannot rm $file : $!" . __FILE__ . ":" . __LINE__ );
      }
      return 0;
    }

    # prepare next cycle - always skips 9 atoms
    $cycle_var = $cycle_var + 9;
  }

  #print "001 hmc : $datar[$cycle_var] $cycle_var\n" if $DEBUG == 2;
  print "1369 finish storing data from agent hmc\n" if $DEBUG == 2;
  return $time;    # return time of last record
}

sub create_rrd_hmc {
  my $hmc     = shift;
  my $time    = shift;
  my $db_name = shift;
  my $ds_mode = "COUNTER";

  my $STEP = 300;

  $time = $time - $STEP;    # start time lower than actual one being updated

  my $no_time  = $STEP * 7;               # says the time interval when RRDTOOL considers a gap in input data
  my $act_time = localtime();
  my $rrd_dir  = "$wrkdir/--HMC--$hmc";

  if ( !-d "$rrd_dir" ) {
    print_it("mkdir          : $rrd_dir") if $DEBUG;
    makex_path("$rrd_dir") || error( "Cannot mkdir $rrd_dir: $!" . __FILE__ . ":" . __LINE__ ) && return 0;
    touch("$rrd_dir");
  }

  print "creating $db_name\n" if $DEBUG == 2;
  my $rrd = "$rrd_dir/$db_name";
  print "$act_time: RRD create     : $rrd\n" if $DEBUG == 2;

  {
    $db_name =~ m/^mem/ && do {

      RRDp::cmd qq(create "$rrd"  --start "$time"  --step "$STEP"
      "DS:size:GAUGE:$no_time:0:102400000000"
      "DS:nuse:GAUGE:$no_time:0:102400000000"
      "DS:free:GAUGE:$no_time:0:102400000000"
      "DS:pin:GAUGE:$no_time:0:102400000000"
      "DS:in_use_work:GAUGE:$no_time:0:102400000000"
      "DS:in_use_clnt:GAUGE:$no_time:0:102400000000"
      "RRA:AVERAGE:0.5:1:$five_mins_sample"
      "RRA:AVERAGE:0.5:5:$one_hour_sample"
      "RRA:AVERAGE:0.5:60:$five_hours_sample"
      "RRA:AVERAGE:0.5:288:$one_day_sample"
      );
      last;
    };
    $db_name =~ m/^pgs/ && do {

      RRDp::cmd qq(create "$rrd"  --start "$time" --step "$STEP"
      "DS:page_in:$ds_mode:$no_time:0:$INPUT_LIMIT_PGS"
      "DS:page_out:$ds_mode:$no_time:0:$INPUT_LIMIT_PGS"
      "DS:paging_space:GAUGE:$no_time:0:U"
      "DS:percent:GAUGE:$no_time:0:100"
      "RRA:AVERAGE:0.5:1:$five_mins_sample"
      "RRA:AVERAGE:0.5:5:$one_hour_sample"
      "RRA:AVERAGE:0.5:60:$five_hours_sample"
      "RRA:AVERAGE:0.5:288:$one_day_sample"
      );
      last;
    };
    $db_name =~ m/^cpu/ && do {

      RRDp::cmd qq(create "$rrd"  --start "$time" --step "$STEP"
      "DS:cpu_id:COUNTER:$no_time:0:U"
      "DS:cpu_sy:COUNTER:$no_time:0:U"
      "DS:cpu_us:COUNTER:$no_time:0:U"
      "DS:cpu_wa:COUNTER:$no_time:0:U"
      "RRA:AVERAGE:0.5:1:$five_mins_sample"
      "RRA:AVERAGE:0.5:5:$one_hour_sample"
      "RRA:AVERAGE:0.5:60:$five_hours_sample"
      "RRA:AVERAGE:0.5:288:$one_day_sample"
      );
      last;
    };
    error( "Unknown item from agent hmc : $db_name , ignoring " . __FILE__ . ":" . __LINE__ ) && return 2;    # must be return 1 otherwise it stucks here for ever for that client, data is corrupted, then skip it and go further
  }

  if ( !Xorux_lib::create_check("file: $rrd, $five_mins_sample, $one_hour_sample, $five_hours_sample, $one_day_sample") ) {
    error( "unable to create $rrd : at " . __FILE__ . ": line " . __LINE__ );
    RRDp::end;
    RRDp::start "$rrdtool";
    return 0;
  }
  return 1;
}

sub create2_rrd {
  my $server        = shift;
  my $lpar          = shift;
  my $time          = shift;
  my $server_space  = shift;
  my $lpar_space    = shift;
  my $db_name       = shift;
  my $ONH_mode      = shift;
  my $nmon_interval = shift;
  my $cdom_uuid     = shift;
  my $net_name      = shift;
  my $type_dom      = shift;
  my $agent_version = shift;

  #print "\$server-$server,\$lpar-$lpar,\$time-$time,\$db_name-$db_name,\$ONH_mode-$ONH_mode,\$nmon_interval-$nmon_interval,\$cdom_uuid-$cdom_uuid,\$net_name-$net_name,\$type_dom-$type_dom,\$agent_version-$agent_version\n";
  #my $DEBUG = 2;
  # 20 minutes heartbeat for non NMON says the time interval when RRDTOOL considers a gap in input data
  my $no_time = 20 * 60;    # 20 minutes heartbeat for non NMON

  my $step_for_create = $STEP;

  my $ds_mode = "COUNTER";

  # from ext nmon we have seen step from 2 - 1800 seconds
  if ( $ONH_mode =~ /N/ ) {    # for NMON both intern and extern
    $ds_mode         = "GAUGE";
    $step_for_create = $nmon_interval;
    $no_time         = $step_for_create * 7;    # says the time interval when RRDTOOL considers a gap in input data

    if ( $no_time < 20 * 60 ) { $no_time = 20 * 60 }
    ;                                           #should be enough
  }

  $time = $time - $step_for_create;             # start time lower than actual one being updated
  my $act_time = localtime();
  my $found    = 0;
  my $rrd_dir  = "";
  my @files;
  print "creating $db_name\n" if $DEBUG == 2;
  if ( $server =~ /Hitachi/ ) {
    my $dir = "$wrkdir/$server_space";
    chomp($dir);
    if ( -d $dir ) {
      $found   = 1;
      $rrd_dir = $dir;
    }
  }
  elsif ( $server =~ /Solaris/ && $db_name =~ /mem|pgs|cpu$|lan-net\d/ ) {
    @files = <$wrkdir/Solaris--unknown/no_hmc/$lpar_space>;
    foreach my $rrd_dir_tmp (@files) {
      chomp($rrd_dir_tmp);
      if ( -d $rrd_dir_tmp ) {
        $found   = 1;
        $rrd_dir = $rrd_dir_tmp;
        last;
      }
    }
  }
  else {
    if ( $server_space =~ /Solaris/ ) {
      $server_space = "Solaris--unknown";
    }
    @files = <$wrkdir/$server_space/*>;
    foreach my $rrd_dir_tmp (@files) {
      chomp($rrd_dir_tmp);
      if ( -d $rrd_dir_tmp ) {
        $found   = 1;
        $rrd_dir = $rrd_dir_tmp;
        last;
      }
    }
  }

  if ( $rrd_dir eq '' && $server ne "Solaris" ) {
    error( "$server_space:$lpar_space: probably not existing symlink target: $wrkdir/$server_space " . __FILE__ . ":" . __LINE__ );
    return 0;
  }

  ###### MAKE DIR FOR ZONE
  if ( $server =~ /Solaris/ && $db_name !~ /mem|pgs|cpu$|CPUTOP|cputop|lan-net\d|_ldom|netstat|vnetstat|san_l|san_tresp/ && $ONH_mode ne "N" ) {
    my $db_a = "";
    $cdom_uuid = "";
    if ( $db_name =~ /\// ) {
      ( $db_a, $cdom_uuid ) = split( "\/", $db_name );
    }
    else {
      $db_a      = "$db_name";
      $cdom_uuid = "$lpar_space";
    }
    if ( !-d "$wrkdir/Solaris/$lpar_space/ZONE/" ) {
      if ( $agent_version >= 611 ) {
        print_it("mkdir : $wrkdir/Solaris/$lpar_space/ZONE/") if $DEBUG;
        makex_path("$wrkdir/Solaris/$lpar_space/ZONE") || error( "Cannot mkdir $wrkdir/Solaris/$lpar_space/ZONE : $!" . __FILE__ . ":" . __LINE__ ) && return 0;
        touch("$wrkdir/Solaris/$lpar_space/ZONE");
      }
    }
  }
  ###### MAKE DIR ONLY FOR OLD AGENT
  elsif ( $server =~ /Solaris/ && $db_name =~ /mem|pgs|cpu$|lan-net\d/ ) {
    $server =~ s/\d+//g;
    if ( !-d "$wrkdir/Solaris--unknown/no_hmc/$lpar_space/" ) {
      if ( $agent_version >= 611 ) {
        print_it("mkdir : $wrkdir/Solaris--unknown/no_hmc/$lpar_space/") if $DEBUG;
        makex_path("$wrkdir/Solaris--unknown/no_hmc/$lpar_space/") || error( "Cannot mkdir $wrkdir/Solaris--unknown/no_hmc/$lpar_space : $!" . __FILE__ . ":" . __LINE__ ) && return 0;
        touch("$wrkdir/Solaris--unknown/no_hmc/$lpar_space/");
      }
    }
  }
  ###### MAKE DIR ONLY FOR JOB
  elsif ( $db_name =~ m/^JOB\/cputop/ && $server =~ /Solaris/ ) {
    if ( !-d "$wrkdir/Solaris--unknown/no_hmc/$lpar_space/JOB/" ) {
      if ( $agent_version >= 611 ) {
        print_it("mkdir : $wrkdir/Solaris--unknown/no_hmc/$lpar_space/JOB/") if $DEBUG;
        makex_path("$wrkdir/Solaris--unknown/no_hmc/$lpar_space/JOB/") || error( "Cannot mkdir $wrkdir/Solaris--unknown/no_hmc/$lpar_space/JOB/ : $!" . __FILE__ . ":" . __LINE__ ) && return 0;
        touch("$wrkdir/Solaris--unknown/no_hmc/$lpar_space/JOB/");
      }
    }
  }
  ###### MAKE DIR ONLY FOR CDOM/LDOM
  elsif ( $server =~ /Solaris/ && $db_name =~ /_ldom|netstat|vnetstat|san_l|san_tresp/ ) {
    if ( !-d "$wrkdir/Solaris/$lpar_space/" ) {
      if ( $agent_version >= 611 ) {
        print_it("mkdir : $wrkdir/Solaris/$lpar_space/") if $DEBUG;
        makex_path("$wrkdir/Solaris/$lpar_space") || error( "Cannot mkdir $wrkdir/Solaris/$lpar_space : $!" . __FILE__ . ":" . __LINE__ ) && return 0;
        touch("$wrkdir/Solaris/$lpar_space");
      }
    }
  }
  elsif ( !-d "$rrd_dir/$lpar/" ) {
    print_it("mkdir : $db_name : $rrd_dir/$lpar/") if $DEBUG;
    makex_path("$rrd_dir/$lpar/") || error( "Cannot mkdir $rrd_dir/$lpar/: $!" . __FILE__ . ":" . __LINE__ ) && return 0;
    touch("$rrd_dir/$lpar/");
  }

  my $rrd = "$rrd_dir/$lpar/$db_name";

  print "$act_time: RRD create     : $rrd\n" if $DEBUG == 2;
  {
    $db_name =~ m/^mem/ && do {
      if ( $server =~ /Solaris/ ) {
        $server =~ s/\d+//g;
        if ( $lpar_space =~ /--NMON--$/ ) { $db_name =~ s/\.mmm//g; }
        $rrd = "$wrkdir/Solaris--unknown/no_hmc/$lpar_space/$db_name.mmm";
      }
      else {
        if ( -f "$rrd_dir/$lpar.mmm" ) {
          return conv_lpar( "$rrd_dir/$lpar.mmm", $server, $lpar, "$rrd_dir/$lpar", $tmpdir );
        }
      }
      RRDp::cmd qq(create "$rrd"  --start "$time"  --step "$step_for_create"
      "DS:size:GAUGE:$no_time:0:102400000000"
      "DS:nuse:GAUGE:$no_time:0:102400000000"
      "DS:free:GAUGE:$no_time:0:102400000000"
      "DS:pin:GAUGE:$no_time:0:102400000000"
      "DS:in_use_work:GAUGE:$no_time:0:102400000000"
      "DS:in_use_clnt:GAUGE:$no_time:0:102400000000"
      "RRA:AVERAGE:0.5:1:$one_minute_sample"
      "RRA:AVERAGE:0.5:5:$five_mins_sample"
      "RRA:AVERAGE:0.5:60:$one_hour_sample"
      "RRA:AVERAGE:0.5:300:$five_hours_sample"
      "RRA:AVERAGE:0.5:1440:$one_day_sample"
      );
      last;
    };
    $db_name =~ m/^pgs/ && do {

      if ( $server =~ /Solaris/ ) {
        $server =~ s/\d+//g;
        if ( $lpar_space =~ /--NMON--$/ ) { $db_name =~ s/\.mmm//g; }
        $rrd = "$wrkdir/Solaris--unknown/no_hmc/$lpar_space/$db_name.mmm";
      }

      RRDp::cmd qq(create "$rrd"  --start "$time" --step "$step_for_create"
      "DS:page_in:$ds_mode:$no_time:0:$INPUT_LIMIT_PGS"
      "DS:page_out:$ds_mode:$no_time:0:$INPUT_LIMIT_PGS"
      "DS:paging_space:GAUGE:$no_time:0:U"
      "DS:percent:GAUGE:$no_time:0:100"
      "RRA:AVERAGE:0.5:1:$one_minute_sample"
      "RRA:AVERAGE:0.5:5:$five_mins_sample"
      "RRA:AVERAGE:0.5:60:$one_hour_sample"
      "RRA:AVERAGE:0.5:300:$five_hours_sample"
      "RRA:AVERAGE:0.5:1440:$one_day_sample"
      );
      last;
    };
    $db_name =~ m/^lan/ && $db_name !~ m/ldom/ && $db_name !~ m/^lan_error/ && do {

      if ( $server =~ /Solaris/ ) {
        $server =~ s/\d+//g;
        if ( $lpar_space =~ /--NMON--$/ ) { $db_name =~ s/\.mmm//g; }
        $rrd = "$wrkdir/Solaris--unknown/no_hmc/$lpar_space/$db_name.mmm";
      }

      RRDp::cmd qq(create "$rrd"  --start "$time" --step "$step_for_create"
      "DS:recv_bytes:$ds_mode:$no_time:0:$INPUT_LIMIT_LAN"
      "DS:trans_bytes:$ds_mode:$no_time:0:$INPUT_LIMIT_LAN"
      "DS:recv_packets:$ds_mode:$no_time:0:$INPUT_LIMIT_PCK_LAN"
      "DS:trans_packets:$ds_mode:$no_time:0:$INPUT_LIMIT_PCK_LAN"
      "RRA:AVERAGE:0.5:1:$one_minute_sample"
      "RRA:AVERAGE:0.5:5:$five_mins_sample"
      "RRA:AVERAGE:0.5:60:$one_hour_sample"
      "RRA:AVERAGE:0.5:300:$five_hours_sample"
      "RRA:AVERAGE:0.5:1440:$one_day_sample"
      );
      last;
    };
    $db_name =~ m/^san-fcs/ && $db_name !~ m/^san_resp/ && do {

      RRDp::cmd qq(create "$rrd"  --start "$time" --step "$step_for_create"
      "DS:recv_bytes:$ds_mode:$no_time:0:$INPUT_LIMIT_SAN1"
      "DS:trans_bytes:$ds_mode:$no_time:0:$INPUT_LIMIT_SAN1"
      "DS:iops_in:$ds_mode:$no_time:0:$INPUT_LIMIT_SAN2"
      "DS:iops_out:$ds_mode:$no_time:0:$INPUT_LIMIT_SAN2"
      "RRA:AVERAGE:0.5:1:$one_minute_sample"
      "RRA:AVERAGE:0.5:5:$five_mins_sample"
      "RRA:AVERAGE:0.5:60:$one_hour_sample"
      "RRA:AVERAGE:0.5:300:$five_hours_sample"
      "RRA:AVERAGE:0.5:1440:$one_day_sample"
      );
      last;
    };
    $db_name =~ m/^san_l/ && do {
      if ( $db_name =~ /san_l/ ) {
        my $char_s = "san-";
        $rrd = "$wrkdir/Solaris/$lpar_space/$char_s$net_name.mmm";
      }
      RRDp::cmd qq(create "$rrd"  --start "$time" --step "$step_for_create"
      "DS:recv_bytes:GAUGE:$no_time:0:$INPUT_LIMIT_SAN1"
      "DS:trans_bytes:GAUGE:$no_time:0:$INPUT_LIMIT_SAN1"
      "DS:iops_in:GAUGE:$no_time:0:$INPUT_LIMIT_SAN2"
      "DS:iops_out:GAUGE:$no_time:0:$INPUT_LIMIT_SAN2"
      "RRA:AVERAGE:0.5:1:$one_minute_sample"
      "RRA:AVERAGE:0.5:5:$five_mins_sample"
      "RRA:AVERAGE:0.5:60:$one_hour_sample"
      "RRA:AVERAGE:0.5:300:$five_hours_sample"
      "RRA:AVERAGE:0.5:1440:$one_day_sample"
      );
      last;
    };
    $db_name =~ m/^san-host/ && do {

      RRDp::cmd qq(create "$rrd"  --start "$time" --step "$step_for_create"
      "DS:recv_bytes:$ds_mode:$no_time:0:$INPUT_LIMIT_SAN1"
      "DS:trans_bytes:$ds_mode:$no_time:0:$INPUT_LIMIT_SAN1"
      "DS:iops_in:$ds_mode:$no_time:0:$INPUT_LIMIT_SAN2"
      "DS:iops_out:$ds_mode:$no_time:0:$INPUT_LIMIT_SAN2"
      "RRA:AVERAGE:0.5:1:$one_minute_sample"
      "RRA:AVERAGE:0.5:5:$five_mins_sample"
      "RRA:AVERAGE:0.5:60:$one_hour_sample"
      "RRA:AVERAGE:0.5:300:$five_hours_sample"
      "RRA:AVERAGE:0.5:1440:$one_day_sample"
      );
      last;
    };
    $db_name =~ m/^san/ && $db_name !~ m/^san-fcs/ && $db_name !~ m/^san_resp/ && $db_name !~ m/^san-host/ && $db_name !~ /^san_tresp/ && $db_name !~ m/^sanmon/ && $db_name !~ m/^san_error/ && do {

      RRDp::cmd qq(create "$rrd"  --start "$time" --step "$step_for_create"
      "DS:recv_bytes:GAUGE:$no_time:0:$INPUT_LIMIT_SAN1"
      "DS:trans_bytes:GAUGE:$no_time:0:$INPUT_LIMIT_SAN1"
      "DS:iops_in:GAUGE:$no_time:0:$INPUT_LIMIT_SAN2"
      "DS:iops_out:GAUGE:$no_time:0:$INPUT_LIMIT_SAN2"
      "RRA:AVERAGE:0.5:1:$one_minute_sample"
      "RRA:AVERAGE:0.5:5:$five_mins_sample"
      "RRA:AVERAGE:0.5:60:$one_hour_sample"
      "RRA:AVERAGE:0.5:300:$five_hours_sample"
      "RRA:AVERAGE:0.5:1440:$one_day_sample"
      );
      last;
    };
    $db_name =~ m/^san_resp/ && do {

      RRDp::cmd qq(create "$rrd"  --start "$time" --step "$step_for_create"
      "DS:resp_t_r:GAUGE:$no_time:0:$INPUT_LIMIT_SAN1"
      "DS:resp_t_w:GAUGE:$no_time:0:$INPUT_LIMIT_SAN1"
      "RRA:AVERAGE:0.5:1:$one_minute_sample"
      "RRA:AVERAGE:0.5:5:$five_mins_sample"
      "RRA:AVERAGE:0.5:60:$one_hour_sample"
      "RRA:AVERAGE:0.5:300:$five_hours_sample"
      "RRA:AVERAGE:0.5:1440:$one_day_sample"
      );
      last;
    };
    $db_name =~ m/^san_tresp/ && do {

      my $char_s = "san_tresp-";
      $rrd = "$wrkdir/Solaris/$lpar_space/$char_s$net_name.mmm";
      RRDp::cmd qq(create "$rrd"  --start "$time" --step "$step_for_create"
      "DS:resp_all:GAUGE:$no_time:0:$INPUT_LIMIT_SAN1"
      "RRA:AVERAGE:0.5:1:$one_minute_sample"
      "RRA:AVERAGE:0.5:5:$five_mins_sample"
      "RRA:AVERAGE:0.5:60:$one_hour_sample"
      "RRA:AVERAGE:0.5:300:$five_hours_sample"
      "RRA:AVERAGE:0.5:1440:$one_day_sample"
      );
      last;
    };
    $db_name =~ m/^ame/ && do {

      RRDp::cmd qq(create "$rrd"  --start "$time" --step "$step_for_create"
      "DS:ame_mem:GAUGE:$no_time:0:U"
      "DS:ame_ratio:GAUGE:$no_time:0:1000"
      "DS:ame_deficit:GAUGE:$no_time:0:U"
      "RRA:AVERAGE:0.5:1:$one_minute_sample"
      "RRA:AVERAGE:0.5:5:$five_mins_sample"
      "RRA:AVERAGE:0.5:60:$one_hour_sample"
      "RRA:AVERAGE:0.5:300:$five_hours_sample"
      "RRA:AVERAGE:0.5:1440:$one_day_sample"
      );
      last;
    };
    $db_name =~ m/^queue_cpu_aix/ && do {

      RRDp::cmd qq(create "$rrd"  --start "$time" --step "$step_for_create"
       "DS:load:GAUGE:$no_time:0:U"
       "DS:virtual_p:GAUGE:$no_time:0:U"
       "DS:blocked_p:GAUGE:$no_time:0:U"
       "DS:blocked_raw:GAUGE:$no_time:0:U"
       "DS:blocked_IO:GAUGE:$no_time:0:U"
       "RRA:AVERAGE:0.5:1:$one_minute_sample"
       "RRA:AVERAGE:0.5:5:$five_mins_sample"
       "RRA:AVERAGE:0.5:60:$one_hour_sample"
       "RRA:AVERAGE:0.5:300:$five_hours_sample"
       "RRA:AVERAGE:0.5:1440:$one_day_sample"
       );
      last;
    };
    $db_name =~ m/^queue_cpu/ && do {

      if ( $server =~ m/Solaris/ ) {
        $server =~ s/\d+//g;
        if ( $lpar_space =~ /--NMON--$/ ) { $db_name =~ s/\.mmm//g; }
        $rrd = "$wrkdir/Solaris--unknown/no_hmc/$lpar_space/$db_name.mmm";
      }
      RRDp::cmd qq(create "$rrd"  --start "$time" --step "$step_for_create"
       "DS:load:GAUGE:$no_time:0:U"
       "DS:virtual_p:GAUGE:$no_time:0:U"
       "DS:blocked_p:GAUGE:$no_time:0:U"
       "RRA:AVERAGE:0.5:1:$one_minute_sample"
       "RRA:AVERAGE:0.5:5:$five_mins_sample"
       "RRA:AVERAGE:0.5:60:$one_hour_sample"
       "RRA:AVERAGE:0.5:300:$five_hours_sample"
       "RRA:AVERAGE:0.5:1440:$one_day_sample"
       );
      last;
    };
    $db_name =~ m/^cpu/ && do {

      if ( $server =~ /Solaris/ ) {
        $server =~ s/\d+//g;
        if ( $lpar_space =~ /--NMON--$/ ) { $db_name =~ s/\.mmm//g; }
        $rrd = "$wrkdir/Solaris--unknown/no_hmc/$lpar_space/$db_name.mmm";
      }

      RRDp::cmd qq(create "$rrd"  --start "$time" --step "$step_for_create"
      "DS:entitled:GAUGE:$no_time:0:U"
      "DS:cpu_sy:GAUGE:$no_time:0:U"
      "DS:cpu_us:GAUGE:$no_time:0:U"
      "DS:cpu_wa:GAUGE:$no_time:0:U"
      "RRA:AVERAGE:0.5:1:$one_minute_sample"
      "RRA:AVERAGE:0.5:5:$five_mins_sample"
      "RRA:AVERAGE:0.5:60:$one_hour_sample"
      "RRA:AVERAGE:0.5:300:$five_hours_sample"
      "RRA:AVERAGE:0.5:1440:$one_day_sample"
      );
      last;
    };
    $db_name =~ m/^st-cpu/ && do {
      RRDp::cmd qq(create "$rrd"  --start "$time" --step "$step_for_create"
      "DS:cpu_stol:GAUGE:$no_time:0:U"
      "DS:cpu_ni:GAUGE:$no_time:0:U"
      "DS:cpu_hi:GAUGE:$no_time:0:U"
      "DS:cpu_si:GAUGE:$no_time:0:U"
      "RRA:AVERAGE:0.5:1:$one_minute_sample"
      "RRA:AVERAGE:0.5:5:$five_mins_sample"
      "RRA:AVERAGE:0.5:60:$one_hour_sample"
      "RRA:AVERAGE:0.5:300:$five_hours_sample"
      "RRA:AVERAGE:0.5:1440:$one_day_sample"
      );
      last;
    };
    $db_name =~ m/^linux_cpu/ && do {

      RRDp::cmd qq(create "$rrd"  --start "$time" --step "$step_for_create"
      "DS:cpu_count:GAUGE:$no_time:0:U"
      "DS:cpu_in_mhz:GAUGE:$no_time:0:U"
      "DS:threads_core:GAUGE:$no_time:0:U"
      "DS:cores_per_socket:GAUGE:$no_time:0:U"
      "RRA:AVERAGE:0.5:1:$one_minute_sample"
      "RRA:AVERAGE:0.5:5:$five_mins_sample"
      "RRA:AVERAGE:0.5:60:$one_hour_sample"
      "RRA:AVERAGE:0.5:300:$five_hours_sample"
      "RRA:AVERAGE:0.5:1440:$one_day_sample"
      );
      last;
    };
    $db_name =~ m/^wlm/ && do {
      if ( !-d "$rrd_dir/$lpar/" ) {    # if superclass dir doesnt exist create it
        print_it("mkdir          : $rrd_dir/$lpar/") if $DEBUG;
        makex_path("$rrd_dir/$lpar/") || error( "Cannot mkdir $rrd_dir/$lpar/: $!" . __FILE__ . ":" . __LINE__ ) && return 0;
        touch("$rrd_dir/$lpar/");
      }

      RRDp::cmd qq(create "$rrd"  --start "$time" --step "$step_for_create"
      "DS:wlm_cpu:GAUGE:$no_time:0:100"
      "DS:wlm_mem:GAUGE:$no_time:0:U"
      "DS:wlm_dkio:GAUGE:$no_time:0:100"
      "RRA:AVERAGE:0.5:1:$one_minute_sample"
      "RRA:AVERAGE:0.5:5:$five_mins_sample"
      "RRA:AVERAGE:0.5:60:$one_hour_sample"
      "RRA:AVERAGE:0.5:300:$five_hours_sample"
      "RRA:AVERAGE:0.5:1440:$one_day_sample"
      );
      last;
    };
    $db_name =~ m/^sea/ && do {

      RRDp::cmd qq(create "$rrd"  --start "$time" --step "$step_for_create"
      "DS:recv_bytes:$ds_mode:$no_time:0:$INPUT_LIMIT_SEA"
      "DS:trans_bytes:$ds_mode:$no_time:0:$INPUT_LIMIT_SEA"
      "DS:recv_packets:$ds_mode:$no_time:0:$INPUT_LIMIT_PCK_SEA"
      "DS:trans_packets:$ds_mode:$no_time:0:$INPUT_LIMIT_PCK_SEA"
      "RRA:AVERAGE:0.5:1:$one_minute_sample"
      "RRA:AVERAGE:0.5:5:$five_mins_sample"
      "RRA:AVERAGE:0.5:60:$one_hour_sample"
      "RRA:AVERAGE:0.5:300:$five_hours_sample"
      "RRA:AVERAGE:0.5:1440:$one_day_sample"
      );
      last;
    };
    $db_name =~ m/^lpar/ && do {

      RRDp::cmd qq(create "$rrd"  --start "$time" --step "$step_for_create"
      "DS:entitled:GAUGE:$no_time:0:$INPUT_LIMIT_SEA"
      "DS:physical_cpu:GAUGE:$no_time:0:$INPUT_LIMIT_SEA"
      "RRA:AVERAGE:0.5:1:$one_minute_sample"
      "RRA:AVERAGE:0.5:5:$five_mins_sample"
      "RRA:AVERAGE:0.5:60:$one_hour_sample"
      "RRA:AVERAGE:0.5:300:$five_hours_sample"
      "RRA:AVERAGE:0.5:1440:$one_day_sample"
      );
      last;
    };

    ########
    ##
    ## Solaris - zones and ldoms
    ##
    ########
    $db_name =~ m/^sanmon/ && do {    ### NMON SAN
      $rrd = "$wrkdir/Solaris--unknown/no_hmc/$lpar_space/total-san.mmm";

      #  $san_message .= ":sanmon:$san_disk_read:$san_disk_write:$san_iops:$san_latency\::::";
      RRDp::cmd qq(create "$rrd"  --start "$time" --step "$step_for_create"
      "DS:disk_read:GAUGE:$no_time:0:U"
      "DS:disk_write:GAUGE:$no_time:0:U"
      "DS:disk_iops:GAUGE:$no_time:0:U"
      "DS:disk_latency:GAUGE:$no_time:0:U"
      "RRA:AVERAGE:0.5:1:$one_minute_sample"
      "RRA:AVERAGE:0.5:5:$five_mins_sample"
      "RRA:AVERAGE:0.5:60:$one_hour_sample"
      "RRA:AVERAGE:0.5:300:$five_hours_sample"
      "RRA:AVERAGE:0.5:1440:$one_day_sample"
      );
      last;
    };
    $db_name !~ /mem|pgs|cpu$|lan-net\d|^JOB\/cputop|cputop\d|_ldom|netstat|vnetstat|pool-sol/ && $server =~ /Solaris/ && do {    ##################### Solaris11 - zones
      if ( -f "$wrkdir/Solaris/$lpar_space/solaris11.txt" ) {
        $db_name =~ s/\.mmm//g;
        my $db_a      = "";
        my $cdom_uuid = "";
        if ( $db_name =~ /\// ) {
          ( $db_a, $cdom_uuid ) = split( "\/", $db_name );
        }
        else {
          $db_a      = "$db_name";
          $cdom_uuid = "$lpar_space";
        }
        $rrd = "$wrkdir/Solaris/$lpar_space/ZONE/$db_a.mmm";
        RRDp::cmd qq(create "$rrd"  --start "$time"  --step "$step_for_create"
      "DS:cpu_used:GAUGE:$no_time:0:U"
      "DS:cpu_used_perc:GAUGE:$no_time:0:U"
      "DS:phy_mem_us:GAUGE:$no_time:0:U"
      "DS:phy_mem_us_in_perc:GAUGE:$no_time:0:U"
      "DS:vir_mem_us_in_perc:GAUGE:$no_time:0:U"
      "DS:phy_net_in_perc:GAUGE:$no_time:0:U"
      "DS:cap_used_in_perc:GAUGE:$no_time:0:U"
      "DS:allocated_memory:GAUGE:$no_time:0:U"
      "RRA:AVERAGE:0.5:1:$one_minute_sample"
      "RRA:AVERAGE:0.5:5:$five_mins_sample"
      "RRA:AVERAGE:0.5:60:$one_hour_sample"
      "RRA:AVERAGE:0.5:300:$five_hours_sample"
      "RRA:AVERAGE:0.5:1440:$one_day_sample"
      );
        last;
      }
      elsif ( -f "$wrkdir/Solaris/$lpar_space/solaris10.txt" ) {
        $db_name =~ s/\.mmm//g;
        my $db_a = "";
        $cdom_uuid = "";
        if ( $db_name =~ /\// ) {
          ( $db_a, $cdom_uuid ) = split( "\/", $db_name );
        }
        else {
          $db_a      = "$db_name";
          $cdom_uuid = "$lpar_space";
        }
        $rrd = "$wrkdir/Solaris/$lpar_space/ZONE/$db_a.mmm";
        RRDp::cmd qq(create "$rrd"  --start "$time"  --step "$step_for_create"
        "DS:zone_id:GAUGE:$no_time:0:U"
        "DS:cpu_perc:GAUGE:$no_time:0:U"
        "DS:mem_perc:GAUGE:$no_time:0:U"
        "RRA:AVERAGE:0.5:1:$one_minute_sample"
        "RRA:AVERAGE:0.5:5:$five_mins_sample"
        "RRA:AVERAGE:0.5:60:$one_hour_sample"
        "RRA:AVERAGE:0.5:300:$five_hours_sample"
        "RRA:AVERAGE:0.5:1440:$one_day_sample"
        );
        last;
      }
    };
    $db_name =~ /_ldom/ && $server =~ /Solaris/ && do {
      $db_name =~ s/\.mmm//g;
      my $char_ldom = "_ldom";
      if ( $agent_version >= 611 ) {
        $rrd = "$wrkdir/Solaris/$lpar_space/$db_name.mmm";
      }
      else {    #### old method
        my $db_name_without_ldom = $db_name;
        $db_name_without_ldom =~ s/_ldom//g;
        $rrd = "$wrkdir/Solaris/$db_name_without_ldom/$db_name.mmm";
      }
      RRDp::cmd qq(create "$rrd"  --start "$time"  --step "$step_for_create"
      "DS:v_cpu:GAUGE:$no_time:0:U"
      "DS:mem_allocated:GAUGE:$no_time:0:U"
      "DS:cpu_util:GAUGE:$no_time:0:U"
      "RRA:AVERAGE:0.5:1:$one_minute_sample"
      "RRA:AVERAGE:0.5:5:$five_mins_sample"
      "RRA:AVERAGE:0.5:60:$one_hour_sample"
      "RRA:AVERAGE:0.5:300:$five_hours_sample"
      "RRA:AVERAGE:0.5:1440:$one_day_sample"
      );
      last;
    };
    $db_name eq "netstat" && $server =~ /Solaris/ && do {
      $db_name  =~ s/\.mmm//g;
      $net_name =~ s/\//&&1/;
      $rrd = "$wrkdir/Solaris/$lpar_space/$net_name.mmm";
      RRDp::cmd qq(create "$rrd"  --start "$time"  --step "$step_for_create"
      "DS:ipackets:GAUGE:$no_time:0:U"
      "DS:rbytes:GAUGE:$no_time:0:U"
      "DS:opackets:GAUGE:$no_time:0:U"
      "DS:obytes:GAUGE:$no_time:0:U"
      "RRA:AVERAGE:0.5:1:$one_minute_sample"
      "RRA:AVERAGE:0.5:5:$five_mins_sample"
      "RRA:AVERAGE:0.5:60:$one_hour_sample"
      "RRA:AVERAGE:0.5:300:$five_hours_sample"
      "RRA:AVERAGE:0.5:1440:$one_day_sample"
      );
      last;
    };
    $db_name eq "vnetstat" && $server =~ /Solaris/ && do {
      $db_name  =~ s/\.mmm//g;
      $net_name =~ s/\//&&1/;
      my $char_s = "vlan-";
      $rrd = "$wrkdir/Solaris/$lpar_space/$char_s$net_name.mmm";
      RRDp::cmd qq(create "$rrd"  --start "$time"  --step "$step_for_create"
      "DS:ipackets:GAUGE:$no_time:0:U"
      "DS:rbytes:GAUGE:$no_time:0:U"
      "DS:opackets:GAUGE:$no_time:0:U"
      "DS:obytes:GAUGE:$no_time:0:U"
      "RRA:AVERAGE:0.5:1:$one_minute_sample"
      "RRA:AVERAGE:0.5:5:$five_mins_sample"
      "RRA:AVERAGE:0.5:60:$one_hour_sample"
      "RRA:AVERAGE:0.5:300:$five_hours_sample"
      "RRA:AVERAGE:0.5:1440:$one_day_sample"
      );
      last;
    };
    $db_name eq "pool-sol" && $server =~ /Solaris/ && do {
      $db_name  =~ s/\.mmm//g;
      $net_name =~ s/\//&&1/;
      $rrd = "$wrkdir/Solaris/$lpar_space/$net_name.mmm";
      RRDp::cmd qq(create "$rrd"  --start "$time"  --step "$step_for_create"
      "DS:size_in_cores:GAUGE:$no_time:0:U"
      "DS:used:GAUGE:$no_time:0:U"
      "RRA:AVERAGE:0.5:1:$one_minute_sample"
      "RRA:AVERAGE:0.5:5:$five_mins_sample"
      "RRA:AVERAGE:0.5:60:$one_hour_sample"
      "RRA:AVERAGE:0.5:300:$five_hours_sample"
      "RRA:AVERAGE:0.5:1440:$one_day_sample"
      );
      last;
    };
    $db_name =~ m/^JOB\/cputop/ && do {

      # for JOB files there is only one (30)minute archiv for 8 days, no other archives
      #     # suffix of JOB cpu file is mmc
      # data format ":CPUTOP:$pid:$user:$command_out:$time_1_sec:$time_difference:$rss:$vzs\:";
      #              :CPUTOP:109944:lpar2rrd:yes:3635:1792:608:107900::
      #              :CPUTOP:109944:lpar2rrd:yes:7215:1791:608:107900:: # after another 60 minutes
      #              :CPUTOP:109847:jkubicek:sshd jkubicek@pts/8:71:71:4420:157196::CPUTOP:125733:root:[kworker/12]:18:18:0:0::CPUTOP:128671:root:[kworker/32]:16:16:0:0::CPUTOP:129965:root:[kworker/01]:15:15:0:0::
      #              :CPUTOP:109847:jkubicek:sshd jkubicek@pts/8:161:90:4944:157676::CPUTOP:1130:lpar2rrd:yes:147:83:604:107900::CPUTOP:125733:root:[kworker/12]:41:23:0:0::CPUTOP:129965:root:[kworker/01]:35:20:0:0::CPUTOP:128671:root:[kworker/32]:36:20:0:0::
      #              :CPUTOP:109847:jkubicek:sshd jkubicek@pts/8:247:86:4944:157804::CPUTOP:1130:lpar2rrd:yes:226:79:604:107900::CPUTOP:125733:root:[kworker/12]:64:23:0:0::CPUTOP:128671:root:[kworker/32]:54:18:0:0::CPUTOP:129965:root:[kworker/01]:48:13:0:0::

      if ( !-d "$rrd_dir/$lpar/JOB/" && $server !~ /Solaris/ ) {
        print_it("mkdir          : $rrd_dir/$lpar/JOB/") if $DEBUG;
        makex_path("$rrd_dir/$lpar/JOB/") || error( "Cannot mkdir $rrd_dir/$lpar/JOB/: $!" . __FILE__ . ":" . __LINE__ ) && return 0;
      }
      if ( $server =~ /Solaris/ ) {
        $rrd = "$rrd_dir/$lpar_space/$db_name";
      }
      $step_for_create = 1800;            ## for jobs is OK
      my $no_time = $step_for_create;     # heartbeat MUST be same as step!!! do not change it
      $rrd =~ s/mmm$/mmc/;
      $one_minute_sample = 24 * 2 * 8;    # 24 hours x steps in one hour x 8 days
      RRDp::cmd qq(create "$rrd"  --start "$time" --step "$step_for_create"
      "DS:pid:GAUGE:$no_time:0:U"
      "DS:time_diff:GAUGE:$no_time:0:U"
      "DS:rss:GAUGE:$no_time:0:U"
      "DS:vzs:GAUGE:$no_time:0:U"
      "RRA:AVERAGE:0.5:1:$one_minute_sample"
      );
      last;
    };

    #
    # Hitachi rrd files
    #

    $db_name =~ m/^SYS-CPU\./ && do {
      RRDp::cmd qq(create "$rrd"  --start "$time" --step "$step_for_create"
      "DS:cpu_capacity:GAUGE:$no_time:0:U"
      "DS:cpu_used:GAUGE:$no_time:0:U"
      "DS:cpu_insuff:GAUGE:$no_time:0:U"
      "DS:cpu_usedp:GAUGE:$no_time:0:U"
      "DS:cpu_insuffp:GAUGE:$no_time:0:U"
      "RRA:AVERAGE:0.5:1:$one_minute_sample"
      "RRA:AVERAGE:0.5:5:$five_mins_sample"
      "RRA:AVERAGE:0.5:60:$one_hour_sample"
      "RRA:AVERAGE:0.5:300:$five_hours_sample"
      "RRA:AVERAGE:0.5:1440:$one_day_sample"
      );
      last;
    };

    $db_name =~ m/^SYS-MEM\./ && do {
      RRDp::cmd qq(create "$rrd"  --start "$time" --step "$step_for_create"
      "DS:mem_capacity:GAUGE:$no_time:0:U"
      "DS:mem_used:GAUGE:$no_time:0:U"
      "DS:mem_usedp:GAUGE:$no_time:0:U"
      "RRA:AVERAGE:0.5:1:$one_minute_sample"
      "RRA:AVERAGE:0.5:5:$five_mins_sample"
      "RRA:AVERAGE:0.5:60:$one_hour_sample"
      "RRA:AVERAGE:0.5:300:$five_hours_sample"
      "RRA:AVERAGE:0.5:1440:$one_day_sample"
      );
      last;
    };

    $db_name =~ m/^SYS(1|2)/ && do {
      RRDp::cmd qq(create "$rrd"  --start "$time" --step "$step_for_create"
      "DS:cores:GAUGE:$no_time:0:U"
      "DS:used:GAUGE:$no_time:0:U"
      "DS:usedp:GAUGE:$no_time:0:U"
      "DS:used_cores:GAUGE:$no_time:0:U"
      "RRA:AVERAGE:0.5:1:$one_minute_sample"
      "RRA:AVERAGE:0.5:5:$five_mins_sample"
      "RRA:AVERAGE:0.5:60:$one_hour_sample"
      "RRA:AVERAGE:0.5:300:$five_hours_sample"
      "RRA:AVERAGE:0.5:1440:$one_day_sample"
      );
      last;
    };

    $db_name =~ m/^(SHR_LPAR|DED_LPAR)/ && do {
      RRDp::cmd qq(create "$rrd"  --start "$time" --step "$step_for_create"
      "DS:cores:GAUGE:$no_time:0:U"
      "DS:capacity:GAUGE:$no_time:0:U"
      "DS:used:GAUGE:$no_time:0:U"
      "DS:usedp:GAUGE:$no_time:0:U"
      "DS:used_cores:GAUGE:$no_time:0:U"
      "RRA:AVERAGE:0.5:1:$one_minute_sample"
      "RRA:AVERAGE:0.5:5:$five_mins_sample"
      "RRA:AVERAGE:0.5:60:$one_hour_sample"
      "RRA:AVERAGE:0.5:300:$five_hours_sample"
      "RRA:AVERAGE:0.5:1440:$one_day_sample"
      );
      last;
    };

    $db_name =~ m/\.hlm$/ && do {
      RRDp::cmd qq(create "$rrd"  --start "$time" --step "$step_for_create"
      "DS:cores:GAUGE:$no_time:0:U"
      "DS:usedp:GAUGE:$no_time:0:U"
      "DS:delayp:GAUGE:$no_time:0:U"
      "DS:idlep:GAUGE:$no_time:0:U"
      "DS:iowp:GAUGE:$no_time:0:U"
      "DS:niowp:GAUGE:$no_time:0:U"
      "RRA:AVERAGE:0.5:1:$one_minute_sample"
      "RRA:AVERAGE:0.5:5:$five_mins_sample"
      "RRA:AVERAGE:0.5:60:$one_hour_sample"
      "RRA:AVERAGE:0.5:300:$five_hours_sample"
      "RRA:AVERAGE:0.5:1440:$one_day_sample"
      );
      last;
    };

    $db_name =~ m/MEM-SYS\.hrm$/ && do {
      RRDp::cmd qq(create "$rrd"  --start "$time" --step "$step_for_create"
      "DS:used:GAUGE:$no_time:0:U"
      "DS:usedp:GAUGE:$no_time:0:U"
      "RRA:AVERAGE:0.5:1:$one_minute_sample"
      "RRA:AVERAGE:0.5:5:$five_mins_sample"
      "RRA:AVERAGE:0.5:60:$one_hour_sample"
      "RRA:AVERAGE:0.5:300:$five_hours_sample"
      "RRA:AVERAGE:0.5:1440:$one_day_sample"
      );
      last;
    };

    $db_name =~ m/MEM-LPAR\.hrm$/ && do {
      RRDp::cmd qq(create "$rrd"  --start "$time" --step "$step_for_create"
      "DS:used:GAUGE:$no_time:0:U"
      "DS:usedp:GAUGE:$no_time:0:U"
      "DS:lpar_usedp:GAUGE:$no_time:0:U"
      "RRA:AVERAGE:0.5:1:$one_minute_sample"
      "RRA:AVERAGE:0.5:5:$five_mins_sample"
      "RRA:AVERAGE:0.5:60:$one_hour_sample"
      "RRA:AVERAGE:0.5:300:$five_hours_sample"
      "RRA:AVERAGE:0.5:1440:$one_day_sample"
      );
      last;
    };

    $db_name =~ m/\.hnm$/ && do {
      RRDp::cmd qq(create "$rrd"  --start "$time" --step "$step_for_create"
      "DS:rbyte:GAUGE:$no_time:0:U"
      "DS:sbyte:GAUGE:$no_time:0:U"
      "DS:tbyte:GAUGE:$no_time:0:U"
      "DS:rpacket:GAUGE:$no_time:0:U"
      "DS:spacket:GAUGE:$no_time:0:U"
      "DS:tpacket:GAUGE:$no_time:0:U"
      "RRA:AVERAGE:0.5:1:$one_minute_sample"
      "RRA:AVERAGE:0.5:5:$five_mins_sample"
      "RRA:AVERAGE:0.5:60:$one_hour_sample"
      "RRA:AVERAGE:0.5:300:$five_hours_sample"
      "RRA:AVERAGE:0.5:1440:$one_day_sample"
      );
      last;
    };

    $db_name =~ m/\.hhm$/ && do {
      RRDp::cmd qq(create "$rrd"  --start "$time" --step "$step_for_create"
      "DS:rbyte:GAUGE:$no_time:0:U"
      "DS:wbyte:GAUGE:$no_time:0:U"
      "DS:tbyte:GAUGE:$no_time:0:U"
      "DS:rframe:GAUGE:$no_time:0:U"
      "DS:wframe:GAUGE:$no_time:0:U"
      "DS:tframe:GAUGE:$no_time:0:U"
      "RRA:AVERAGE:0.5:1:$one_minute_sample"
      "RRA:AVERAGE:0.5:5:$five_mins_sample"
      "RRA:AVERAGE:0.5:60:$one_hour_sample"
      "RRA:AVERAGE:0.5:300:$five_hours_sample"
      "RRA:AVERAGE:0.5:1440:$one_day_sample"
      );
      last;
    };

    $db_name =~ m/disk-total/ && do {
      $db_name =~ s/\.mmm//g;
      RRDp::cmd qq(create "$rrd"  --start "$time" --step "$step_for_create"
      "DS:read_iops:GAUGE:$no_time:0:U"
      "DS:read_data:GAUGE:$no_time:0:U"
      "DS:read_latency:GAUGE:$no_time:0:U"
      "DS:write_iops:GAUGE:$no_time:0:U"
      "DS:write_data:GAUGE:$no_time:0:U"
      "DS:write_latency:GAUGE:$no_time:0:U"
      "RRA:AVERAGE:0.5:1:$one_minute_sample"
      "RRA:AVERAGE:0.5:5:$five_mins_sample"
      "RRA:AVERAGE:0.5:60:$one_hour_sample"
      "RRA:AVERAGE:0.5:300:$five_hours_sample"
      "RRA:AVERAGE:0.5:1440:$one_day_sample"
      );
      last;
    };

    $db_name =~ m/san_error/ && do {
      RRDp::cmd qq(create "$rrd"  --start "$time" --step "$step_for_create"
      "DS:error_fcs:COUNTER:$no_time:0:U"
      "RRA:AVERAGE:0.5:1:$one_minute_sample"
      "RRA:AVERAGE:0.5:5:$five_mins_sample"
      "RRA:AVERAGE:0.5:60:$one_hour_sample"
      "RRA:AVERAGE:0.5:300:$five_hours_sample"
      "RRA:AVERAGE:0.5:1440:$one_day_sample"
      );
      last;
    };

    #$db_name =~ m/lan_error/ && do {
    #  RRDp::cmd qq(create "$rrd"  --start "$time" --step "$step_for_create"
    #  "DS:error_lan:COUNTER:$no_time:0:U"
    #  "RRA:AVERAGE:0.5:1:$one_minute_sample"
    #  "RRA:AVERAGE:0.5:5:$five_mins_sample"
    #  "RRA:AVERAGE:0.5:60:$one_hour_sample"
    #  "RRA:AVERAGE:0.5:300:$five_hours_sample"
    #  "RRA:AVERAGE:0.5:1440:$one_day_sample"
    #  );
    #  last;
    #};

    error( "Unknown item from agent, perhaps newer OS agent than the server : $db_name , ignoring $server_space:$lpar_space " . __FILE__ . ":" . __LINE__ ) && return 2;    # must be return 2 otherwise it stucks here for ever for that client, data is corrupted, then skip it and go further
  }

  if ( $server !~ /Solaris/ ) {
    if ( !Xorux_lib::create_check("file: $rrd, $one_minute_sample, $five_mins_sample, $one_hour_sample, $five_hours_sample, $one_day_sample") ) {
      error( "unable to create $rrd : at " . __FILE__ . ": line " . __LINE__ );
      RRDp::end;
      RRDp::start "$rrdtool";
      return 0;
    }
  }
  else {
    if ( $agent_version >= 611 ) {
      if ( !Xorux_lib::create_check("file: $rrd, $one_minute_sample, $five_mins_sample, $one_hour_sample, $five_hours_sample, $one_day_sample") ) {
        error( "unable to create $rrd : at " . __FILE__ . ": line " . __LINE__ );
        RRDp::end;
        RRDp::start "$rrdtool";
        return 0;
      }
    }
    else {
      RRDp::end;
      RRDp::start "$rrdtool";
      error( "Old agent - not found path - data skipping " . __FILE__ . ":" . __LINE__ ) && return 2;    # Data skipping, agent must be at least 6.11 on Solaris
    }
  }

  # create lpar directory and file hard link into the other HMC if there is dual HMC setup
  my $rrd_dir_base = basename($rrd_dir);
  foreach my $rrd_dir_new (@files) {
    chomp($rrd_dir_new);
    my $rrd_dir_new_base = basename($rrd_dir_new);
    if ( -d $rrd_dir_new && $rrd_dir_new_base !~ m/^$rrd_dir_base$/ ) {
      if ( !-d "$rrd_dir_new/$lpar/" ) {
        if ( $server =~ /Solaris\d|Solaris/ && $rrd_dir_new =~ /no_hmc/ ) {
          next;
        }
        print_it("mkdir dual     : $rrd_dir_new/$lpar/") if $DEBUG;
        makex_path("$rrd_dir_new/$lpar/") || error( "Cannot mkdir $rrd_dir_new/$lpar/: $!" . __FILE__ . ":" . __LINE__ ) && return 0;
      }
      if ( -f $rrd ) {
        print_it("hard link      : $rrd --> $rrd_dir_new/$lpar/$db_name") if $DEBUG;
        my $rrd_link_new = "$rrd_dir_new/$lpar/$db_name";
        if ( -f "$rrd_dir_new/$lpar/$db_name" ) {
          unlink("$rrd_dir_new/$lpar/$db_name");
        }
        link( $rrd, "$rrd_dir_new/$lpar/$db_name" ) || error( "Cannot link $rrd --> $rrd_dir_new/$lpar/$db_name : $! " . __FILE__ . ":" . __LINE__ ) && return 0;

        # same for .cfg files
        my $rrd_cfg = $rrd;
        $rrd_cfg =~ s/mmm$/cfg/;
        $rrd_cfg =~ s/mmc$/cfg/;
        my $db_name_cfg = $db_name;
        $db_name_cfg =~ s/mmm$/cfg/;
        $db_name_cfg =~ s/mmc$/cfg/;
        if ( ( $db_name_cfg =~ m/^lan-/ || $db_name =~ m/^san-/ || $db_name =~ m/^sea-/ ) && -f $rrd_cfg && !-f "$rrd_dir_new/$lpar/$db_name_cfg" ) {
          if ( -f "$rrd_dir_new/$lpar/$db_name_cfg" ) {
            unlink("$rrd_dir_new/$lpar/$db_name_cfg");
          }
          `touch "$rrd_cfg"`;    # trck here how to create source file which will be used afterwards
          link( $rrd_cfg, "$rrd_dir_new/$lpar/$db_name_cfg" ) || error( "Cannot link $rrd_cfg --> $rrd_dir_new/$lpar/$db_name_cfg : $! " . __FILE__ . ":" . __LINE__ ) && return 1;

          # return OK here on purpose, it is just a .cfg file, not important when any problem
        }
      }
      else {
        error( "Link source file does not exist, continuing anyway: $rrd " . __FILE__ . ":" . __LINE__ );
      }
    }
  }
  return 1;
}

sub makex_path {
  my $mypath = shift;

  #print "create this path $mypath\n"; # like mkdir -p
  my @base   = split( /\//, $mypath );
  my $c_path = "";
  foreach my $m (@base) {
    $c_path .= $m . "/";
    if ( -d $c_path )        {next}
    if ( !mkdir("$c_path") ) { return 0 }
    ;    # no success
    next;
  }
  return 1    # success
}

sub load_retentions {
  my $step    = shift;
  my $basedir = shift;

  # standards
  $one_minute_sample = 86400;
  $five_mins_sample  = 25920;
  $one_hour_sample   = 4320;
  $five_hours_sample = 1734;
  $one_day_sample    = 1080;

  if ( !-f "$basedir/etc/retention.cfg" ) {

    # standard retentions in place
    return 0;
  }

  # extra retentions are specified in $basedir/etc/retention.cfg
  open( FH, "< $basedir/etc/retention.cfg" ) || error("Can't read from: $basedir/etc/retention.cfg: $!");

  my @lines = <FH>;
  foreach my $line (@lines) {
    chomp($line);
    if ( $line !~ m/MEM/ ) {
      next;
    }
    if ( $line =~ m/^1min/ ) {
      ( undef, $one_minute_sample ) = split( /:/, $line );
    }
    if ( $line =~ m/^5min/ ) {
      ( undef, $five_mins_sample ) = split( /:/, $line );
    }
    if ( $line =~ m/^60min/ ) {
      ( undef, $one_hour_sample ) = split( /:/, $line );
    }
    if ( $line =~ m/^300min/ ) {
      ( undef, $five_hours_sample ) = split( /:/, $line );
    }
    if ( $line =~ m/^1440min/ ) {
      ( undef, $one_day_sample ) = split( /:/, $line );
    }
  }

  close(FH);

  $step              = $step / 60;
  $one_minute_sample = $one_minute_sample / $step;
  $five_mins_sample  = $five_mins_sample / $step;
  $one_hour_sample   = $one_hour_sample / $step;
  $five_hours_sample = $five_hours_sample / $step;
  $one_day_sample    = $one_day_sample / $step;

  return 1;
}

sub rrd_error {
  my $err_text = shift;
  my $rrd_file = shift;
  my $tmpdir   = "$basedir/tmp";
  if ( defined $ENV{TMPDIR_LPAR} ) {
    $tmpdir = $ENV{TMPDIR_LPAR};
  }
  my $act_time = localtime();

  chomp($err_text);

  # -PH, not necessary to keep files, it is for nothing anyway
  #if ( $err_text =~ m/ERROR:/ && $err_text !~ m/This RRD was created on another architecture/ ) {
  # copy of the corrupted file into "save" place and remove the original one
  #print "$rrd_file!!!!!!\n";
  #  copy( "$rrd_file", "$tmpdir/" ) || error( "Cannot: cp $rrd_file $tmpdir/: $!" . __FILE__ . ":" . __LINE__ );
  #  unlink("$rrd_file") || error( "Cannot rm $rrd_file : $!" . __FILE__ . ":" . __LINE__ );
  #  error("$act_time: $err_text : $rrd_file : moving it into: $tmpdir/");
  #} ## end if ( $err_text =~ m/ERROR:/...)
  #else {
  # exlude "This RRD was created on another architecture" as this might happen after Linux upgrade for example, this is not a corruption
  #}

  chomp($rrd_file);
  error("$act_time: $rrd_file : $err_text");
  return 0;
}

# extends fcsxx file for iops in-out

sub fcs_iops {
  my $rrd_file = shift;
  my $server   = shift;
  my $lpar     = shift;
  my $ent      = shift;

  #  read dumped file, defining new ds,
  my $f_dumped = "/tmp/rrd_dump";
  unlink($f_dumped);    #in any case
  ( !`rrdtool dump $rrd_file $f_dumped` ) || error( "Cannot dump $rrd_file to $f_dumped: $!" . __FILE__ . ":" . __LINE__ ) && return 0;
  open( DF_IN, "< $f_dumped" )            || error( "Cannot open for reading $f_dumped: $!" . __FILE__ . ":" . __LINE__ )  && return 0;
  my @lines = <DF_IN>;
  close(DF_IN);
  unlink($f_dumped);
  $f_dumped = "/tmp/rrd_dump_q";
  open( DF_OUT, "> $f_dumped" ) || error( "Cannot open for writing $f_dumped: $!" . __FILE__ . ":" . __LINE__ ) && return 0;

  my ( @ds1, @ds2, $line );
  while ( $line = shift @lines ) {
    print DF_OUT "$line";
    last if ( $line =~ "<ds>" );
  }

  #print "$lines[0],$lines[1],$lines[2],$lines[3]\n";
  $ds1[0] = $line;
  for ( my $i = 1; $i <= 11; $i++ ) {
    $line = shift @lines;
    print DF_OUT "$line";
    if ( $line =~ "recv_bytes" ) {
      $line =~ s/recv_bytes/iops_in/;
      $ds1[$i] = $line;
      next;
    }
    if ( $line =~ "<min>" ) {
      $ds1[$i] = "           <min> 0.0000000000e+00 </min>\n";
      next;
    }
    if ( $line =~ "<value>" ) {
      $ds1[$i] = "           <value> 0.0000000000e+00 </value>\n";
      next;
    }
    $ds1[$i] = $line;
    next;
  }
  while ( $line = shift @lines ) {
    print DF_OUT "$line";
    last if ( $line =~ "<ds>" );
  }
  $ds2[0] = $line;
  for ( my $i = 1; $i <= 11; $i++ ) {
    $line = shift @lines;
    print DF_OUT "$line";
    if ( $line =~ "trans_bytes" ) {
      $line =~ s/trans_bytes/iops_out/;
      $ds2[$i] = $line;
      next;
    }
    if ( $line =~ "<min>" ) {
      $ds2[$i] = "           <min> 0.0000000000e+00 </min>\n";
      next;
    }
    if ( $line =~ "<value>" ) {
      $ds2[$i] = "           <value> 0.0000000000e+00 </value>\n";
      next;
    }
    $ds2[$i] = $line;
    next;
  }

  # print next two ds
  print DF_OUT "\n";
  for ( my $i = 0; $i <= 11; $i++ ) {
    print DF_OUT "$ds1[$i]";

    # print "$ds1[$i]";
  }
  print DF_OUT "\n";
  for ( my $i = 0; $i <= 11; $i++ ) {
    print DF_OUT "$ds2[$i]";
  }

  # <!-- Round Robin Archives -->   <rra>
  # reading data points - 5 cycles (data and RRA) and till the end
  # prepare RRA ds 12 lines
  @ds1 = (
    "                      <ds>
", "                     <primary_value> NaN </primary_value>
", "                     <secondary_value> NaN </secondary_value>
", "                     <value> NaN </value>
", "                     <unknown_datapoints> 0 </unknown_datapoints>
", "                     </ds>
", "                     <ds>
", "                     <primary_value> NaN </primary_value>
", "                     <secondary_value> NaN </secondary_value>
", "                     <value> NaN </value>
", "                     <unknown_datapoints> 0 </unknown_datapoints>
", "                     </ds>
"
  );

  for ( my $cycle = 0; $cycle <= 4; $cycle++ ) {
    while ( $line = shift @lines ) {
      if ( $line =~ "</v></row>" ) {
        $line =~ s/<\/row>/<v> NaN <\/v><v> NaN <\/v><\/row>/;
      }
      last if ( $line =~ "</cdp_prep>" );
      print DF_OUT "$line";
    }

    # print next two ds
    for ( my $i = 0; $i <= 11; $i++ ) {
      print DF_OUT "$ds1[$i]";
    }
    print DF_OUT "$line";
    next;
  }    # end of for
  while ( $line = shift @lines ) {
    if ( $line =~ "</v></row>" ) {
      $line =~ s/<\/row>/<v> NaN <\/v><v> NaN <\/v><\/row>/;
    }
    print DF_OUT "$line";
  }
  close(DF_OUT) || error( "Cannot close $f_dumped: $!" . __FILE__ . ":" . __LINE__ ) && return 0;

  ( !`mv $rrd_file $rrd_file.backup` )       || error( "Cannot backup $rrd_file: $!" . __FILE__ . ":" . __LINE__ )  && return 0;
  ( !`rrdtool restore $f_dumped $rrd_file` ) || error( "Cannot restore $rrd_file: $!" . __FILE__ . ":" . __LINE__ ) && return 0;
  unlink($f_dumped);
  unlink("$rrd_file.backup");

  # create lpar directory and file hard link into the other HMC if there is dual HMC setup

  my $found        = 0;
  my $server_space = $server;
  if ( $server =~ m/ / ) {
    $server_space = "\"" . $server . "\"";    # it must be here to support space with server names
  }
  my @files = <$wrkdir/$server_space/*>;

  #  my @files = <$wrkdir/"$server"/*>;
  my $rrd_dir = "";
  foreach my $rrd_dir_tmp (@files) {
    chomp($rrd_dir_tmp);
    if ( -d $rrd_dir_tmp ) {
      $found   = 1;
      $rrd_dir = $rrd_dir_tmp;
      last;
    }
  }
  if ( $found == 0 ) {
    error("en part iops: Could not found a HMC in : $wrkdir/$server");
    return 0;
  }

  my $rrd_dir_base = basename($rrd_dir);
  foreach my $rrd_dir_new (@files) {
    chomp($rrd_dir_new);
    my $rrd_dir_new_base = basename($rrd_dir_new);
    if ( -d $rrd_dir_new && $rrd_dir_new_base !~ m/^$rrd_dir_base$/ ) {
      if ( !-d "$rrd_dir_new/$lpar/" ) {
        print_it("mkdir dual     : $rrd_dir_new/$lpar/") if $DEBUG;
        mkdir("$rrd_dir_new/$lpar/") || error( "Cannot mkdir $rrd_dir_new/$lpar/: $!" . __FILE__ . ":" . __LINE__ ) && return 0;
      }
      print_it(" hard link      : $rrd_file --> $rrd_dir_new/$lpar/$ent.mmm") if $DEBUG;
      my $rrd_link_new = "$rrd_dir_new/$lpar/$ent.mmm";
      unlink("$rrd_dir_new/$lpar/$ent.mmm");    #for every case
      link( $rrd_file, "$rrd_dir_new/$lpar/$ent.mmm" ) || error( "Cannot link $rrd_dir_new/$lpar/: $!" . __FILE__ . ":" . __LINE__ ) && return 0;
    }
  }

  return 1;

}

# finds lpar name per lpar_id in data/server/hmc/cpu.cfg
# at first find newest cpu.cfg

sub find_lpar_name {
  my $server  = shift;
  my $lpar_id = shift;

  my $found        = 0;
  my $server_space = $server;
  if ( $server =~ m/ / ) {
    $server_space = "\"" . $server . "\"";    # it must be here to support space with server names
  }
  my @files = <$wrkdir/$server_space/*/cpu.cfg>;

  my $cpu_file_time = 0;
  my $cpu_file      = "";
  foreach my $line (@files) {
    chomp($line);
    if ( !-f $line ) {
      next;    # just to be sure
    }
    my $cpu_file_time_tmp = ( stat("$line") )[9];
    if ( $cpu_file_time_tmp > $cpu_file_time ) {
      $cpu_file_time = $cpu_file_time_tmp;
      $cpu_file      = $line;
    }
  }
  if ( $cpu_file eq '' ) {
    print_it("LPAR ID not found:$server:$lpar_id no cpu.cfg") if $DEBUG == 2;
    return "";
  }
  open( FHC, "< $cpu_file" ) || error( "Can't open $cpu_file : $!" . __FILE__ . ":" . __LINE__ ) && return "";
  my @res_all = <FHC>;
  close(FHC);
  foreach my $line (@res_all) {
    chomp($line);
    if ( $line =~ m/,lpar_id=$lpar_id,/ ) {

      # lpar_id has been found
      $line =~ s/^lpar_name=//;
      $line =~ s/,lpar_id=.*//;
      print_it("LPAR ID found   : $server:$line:$lpar_id") if $DEBUG == 2;
      return $line;
    }
  }

  print_it("LPAR ID not found:$server:$lpar_id no line in cpu.cfg") if $DEBUG == 2;
  return "";
}

sub store_data_10    # returns 0 - fatal error, original $time as OK
{
  my $data             = shift;
  my $last_rec         = shift;
  my $protocol_version = shift;
  my $peer_address     = shift;
  my $en_last_rec      = $last_rec;
  my $act_time         = localtime();
  my $DEBUG            = 0;

  #example of $data
  #8233-E8B*53842P:BSRV22LPAR9:9:1392111120:2097152:2009792:87360:1243360:1962416:0:0:-1:4194304:135552:1143096:0:14824:85440:1836576:0:173216:619:31658:Tue Feb 11 10:32:00 2014:en2:192.168.201.69:1131735328:1493381247:en3:192.168.202.69:1099362694:1583796921:en4:172.31.216.179:25454855750:3192177654:fcs0:0xC050760329FC00C8:26690353045:90825841152:fcs0:iops:13678924:23553862:fcs1:0xC050760329FC00CA:15223131166:86896404992:fcs1:iops:1904252:15878939:tps:tps:4096:4

  my $server      = "";
  my $lpar_name   = "";
  my $time        = "";
  my $size        = "";
  my $inuse       = "";
  my $free        = "";
  my $pin         = "";
  my $virtual     = "";
  my $available   = "";
  my $loaned      = "";
  my $mmode       = "";
  my $size_pg     = "";
  my $inuse_pg    = "";
  my $pin_work    = "";
  my $pin_pers    = "";
  my $pin_clnt    = "";
  my $pin_other   = "";
  my $in_use_work = "";
  my $in_use_pers = "";
  my $in_use_clnt = "";
  my $page_in     = "";
  my $page_out    = "";
  my $dat1        = "";
  my $dat2        = "";
  my $dat3        = "";
  my $en          = "";
  my $enip        = "";
  my $entransb    = "";
  my $enrecb      = "";
  my $dfc5        = "";
  my $dfc6        = "";
  my $dfc7        = "";
  my $dfc8        = "";
  my $lpar_id     = -1;

  if ( $protocol_version < 11 ) {
    ( $server, $lpar, $time, $size, $inuse, $free, $pin, $virtual, $available, $loaned, $mmode, $size_pg, $inuse_pg, $pin_work, $pin_pers, $pin_clnt, $pin_other, $in_use_work, $in_use_pers, $in_use_clnt, $page_in, $page_out, $dat1, $dat2, $dat3, $en, $enip, $entransb, $enrecb, $dfc5, $dfc6, $dfc7, $dfc8 ) = split( /:/, $data );
  }
  else {
    # lpar_id on the 3rd possition
    ( $server, $lpar, $lpar_id, $time, $size, $inuse, $free, $pin, $virtual, $available, $loaned, $mmode, $size_pg, $inuse_pg, $pin_work, $pin_pers, $pin_clnt, $pin_other, $in_use_work, $in_use_pers, $in_use_clnt, $page_in, $page_out, $dat1, $dat2, $dat3, $en, $enip, $entransb, $enrecb, $dfc5, $dfc6, $dfc7, $dfc8 ) = split( /:/, $data );
    if ( $lpar_id > 1200000000 ) {

      # obviously still old data comming via a new protocol, just to be sure and do not case a gap after the agent upgrade
      ( $server, $lpar, $time, $size, $inuse, $free, $pin, $virtual, $available, $loaned, $mmode, $size_pg, $inuse_pg, $pin_work, $pin_pers, $pin_clnt, $pin_other, $in_use_work, $in_use_pers, $in_use_clnt, $page_in, $page_out, $dat1, $dat2, $dat3, $en, $enip, $entransb, $enrecb, $dfc5, $dfc6, $dfc7, $dfc8 ) = split( /:/, $data );
    }
  }

  # since 7.31-4 changed default behaviour, now sent lpar name is used instead of lpar_id what was before

  # Find out lpar name from lpar_id if it has not been done yet
  if ( $lpar eq '' && $lpar_id != -1 ) {
    my $lpar_name_id = find_lpar_name( $server, $lpar_id );
    if ( !$lpar_name_id eq '' ) {
      $lpar = $lpar_name_id;    # lpar name from lparstat -i does not have to be actual, linux on power does not provide lpar name at all
    }
  }

  #if ( $lpar eq '' && !$lpar_name eq '' ) {
  #
  #  # just make sure if lpar-id fails somehow then use transferred $lpar_name
  #$lpar = $lpar_name;
  #}
  if ( $lpar eq '' ) {
    error( "lpar name has not been found for client: $peer_address , server:$server, lpar_id:$lpar_id" . __FILE__ . ":" . __LINE__ );
    return 0;
  }

  print "$data" if $DEBUG == 2;

  my $lpar_real = $lpar;
  $lpar_real =~ s/\//&&1/g;

  my $rrd_file   = "";
  my $lpar_space = $lpar_real;
  if ( $lpar_real =~ m/ / ) {
    $lpar_space = "\"" . $lpar_real . "\"";    # it must be here to support space with lpar names
  }
  my $server_space = $server;
  if ( $server =~ m/ / ) {
    $server_space = "\"" . $server . "\"";     # it must be here to support space with server names
  }

  my @files = <$wrkdir/$server_space/*/$lpar_space/mem.mmm>;
  foreach my $rrd_file_tmp (@files) {
    chomp($rrd_file_tmp);
    $rrd_file = $rrd_file_tmp;
    last;
  }

  if ( !$rrd_file eq '' ) {
    my $filesize = -s "$rrd_file";
    if ( $filesize == 0 ) {

      # when a FS is full then it creates 0 Bytes rrdtool files what is a problem, delete it then
      error( "0 size rrd file: $rrd_file  - delete it" . __FILE__ . ":" . __LINE__ );
      unlink("$rrd_file") || error("Cannot rm $rrd_file : $!");
      $rrd_file = "";    # force to create a new one
    }
  }

  print "$act_time: Updating       : $server:$lpar - $rrd_file\n" if $DEBUG == 2;
  if ( $rrd_file eq '' ) {
    my $ret2 = create2_rrd( $server, $lpar_real, $time, $server_space, $lpar_space, "mem.mmm" );
    if ( $ret2 == 2 ) {
      return $time;      # when en error in create2_rrd but continue (2) to skip it then go here
    }
    if ( $ret2 == 0 ) {
      return $ret2;
    }
    $rrd_file = "";
    @files    = <$wrkdir/$server_space/*/$lpar_space/pgs.mmm>;
    foreach my $rrd_file_tmp (@files) {
      chomp($rrd_file_tmp);
      $rrd_file = $rrd_file_tmp;
      last;
    }
    if ( !-f $rrd_file || $rrd_file eq "" ) {
      my $ret2 = create2_rrd( $server, $lpar_real, $time, $server_space, $lpar_space, "pgs.mmm" );
      if ( $ret2 == 2 ) {
        return $time;    # when en error in create2_rrd but continue (2) to skip it then go here
      }
      if ( $ret2 == 0 ) {
        return $ret2;
      }
    }
    @files = <$wrkdir/$server_space/*/$lpar_space/mem.mmm>;
    foreach my $rrd_file_tmp (@files) {
      chomp($rrd_file_tmp);
      $rrd_file = $rrd_file_tmp;
      last;
    }
  }

  if ( $last_rec == 0 ) {

    # construction against crashing daemon Perl code when RRDTool error appears
    # this does not work well in old RRDTOool: $RRDp::error_mode = 'catch';
    # construction is not too costly as it runs once per each load
    eval {
      RRDp::cmd qq(last "$rrd_file" );
      my $last_rec_rrd = RRDp::read;
      chomp($$last_rec_rrd);
      $last_rec = $$last_rec_rrd;
    };
    if ($@) {
      rrd_error( $@ . __FILE__ . ":" . __LINE__, $rrd_file );
      return 0;
    }
  }

  if ( ( $last_rec + $STEP / 2 ) >= $time ) {

    #error("$server:$lpar : last rec : $last_rec + $STEP/2 >= $time, ignoring it ...".__FILE__.":".__LINE__);
    return $time;    # it is also wrong, must be returned original time, not last_rec
                     # --> no, no, it is not wrong, just ignore it!
  }

  #
  # Memory file update
  #

  #print "000 rrd_file $rrd_file $time:$size:$inuse:$free:$pin:$in_use_work:$in_use_clnt\n";
  my $update_ret = rrd_update( "$rrd_file", "$time:$size:$inuse:$free:$pin:$in_use_work:$in_use_clnt" );

  my $answer = "";
  if ( $rrdcached == 0 )  { $answer = RRDp::read; }
  if ( $update_ret == 0 ) { return 0; }
  ;    # rrdcached problem
  if ( $rrdcached == 0 && !$$answer eq '' && $$answer =~ m/ERROR/ ) {
    error(" $server:$lpar : $rrd_file : $time:$size:$inuse:$free:$pin:$virtual:$available ... : $$answer");
    if ( $$answer =~ m/is not an RRD file/ ) {
      ( my $err, my $file, my $txt ) = split( /'/, $$answer );
      error("Removing as it seems to be corrupted: $file");
      unlink("$file") || error("Cannot rm $file : $!");
    }
    return 0;
  }

  #
  # paging data
  #

  $rrd_file =~ s/mem\.mmm/pgs\.mmm/g;

  #print "001 rrd_file $rrd_file $time:$page_in:$page_out:$size_pg:U\n";
  my $nan = "U";
  $update_ret = rrd_update( "$rrd_file", "$time:$page_in:$page_out:$size_pg:$nan" );

  if ( $rrdcached == 0 )  { $answer = RRDp::read; }
  if ( $update_ret == 0 ) { return 0; }
  ;    # rrdcached problem
  if ( $rrdcached == 0 && !$$answer eq '' && $$answer =~ m/ERROR/ ) {
    error(" $server:$lpar : $rrd_file : $time:$size:$inuse:$free:$pin:$virtual:$available ... : $$answer");
    if ( $$answer =~ m/is not an RRD file/ ) {
      ( my $err, my $file, my $txt ) = split( /'/, $$answer );
      error("Removing as it seems to be corrupted: $file");
      unlink("$file") || error("Cannot rm $file : $!");
    }
    return 0;
  }

  print "2254 finish storing data from agent\n" if $DEBUG == 2;
  return $time;    # return time of last record
}

sub create_en_rrd {
  my $server   = shift;
  my $lpar     = shift;
  my $time     = shift;
  my $ent      = shift;
  my $no_time  = $STEP * 7;     # says the time interval when RRDTOOL consideres a gap in input data
  my $act_time = localtime();

  my $found        = 0;
  my $rrd_dir      = "";
  my $server_space = $server;
  if ( $server =~ m/ / ) {
    $server_space = "\"" . $server . "\"";    # it must be here to support space with server names
  }
  my @files = <$wrkdir/$server_space/*>;
  foreach my $rrd_dir_tmp (@files) {
    chomp($rrd_dir_tmp);
    if ( -d $rrd_dir_tmp ) {
      $found   = 1;
      $rrd_dir = $rrd_dir_tmp;
      last;
    }
  }

  if ( $found == 0 ) {
    error("en: Could not found a HMC in : $wrkdir/$server");
    return 0;
  }
  if ( !-d "$rrd_dir/$lpar/" ) {
    print_it("mkdir          : $rrd_dir/$lpar/") if $DEBUG;
    mkdir("$rrd_dir/$lpar/") || error( "Cannot mkdir $rrd_dir/$lpar/: $!" . __FILE__ . ":" . __LINE__ ) && return 0;
    touch("$rrd_dir/$lpar/");
  }

  my $rrd = "$rrd_dir/$lpar/$ent.mmm";
  print "en: $ent  $act_time: RRD create     : $rrd\n" if $DEBUG == 2;
  my $hb    = 2 * $STEP;
  my $stepx = 15 * $STEP;
  if ( $ent eq "ame" ) {
    RRDp::cmd qq(create "$rrd"  --start "$time-$stepx" --step "$STEP"
       "DS:ame_mem:GAUGE:$hb:0:U"
       "DS:ame_ratio:GAUGE:$hb:0:1000"
       "DS:ame_deficit:GAUGE:$hb:0:U"
       "RRA:AVERAGE:0.5:1:$one_minute_sample"
       "RRA:AVERAGE:0.5:5:$five_mins_sample"
       "RRA:AVERAGE:0.5:60:$one_hour_sample"
       "RRA:AVERAGE:0.5:300:$five_hours_sample"
       "RRA:AVERAGE:0.5:1440:$one_day_sample"
    );
  }
  elsif ( $ent eq "tps" ) {
    RRDp::cmd qq(create "$rrd"  --start "$time-$stepx" --step "$STEP"
       "DS:percent:GAUGE:$hb:0:100"
       "DS:paging_space:GAUGE:$hb:0:U"
       "RRA:AVERAGE:0.5:1:$one_minute_sample"
       "RRA:AVERAGE:0.5:5:$five_mins_sample"
       "RRA:AVERAGE:0.5:60:$one_hour_sample"
       "RRA:AVERAGE:0.5:300:$five_hours_sample"
       "RRA:AVERAGE:0.5:1440:$one_day_sample"
    );
  }
  elsif ( $ent =~ m/^fcs/ ) {
    RRDp::cmd qq(create "$rrd"  --start "$time-$stepx" --step "$STEP"
       "DS:recv_bytes:COUNTER:$hb:0:U"
       "DS:trans_bytes:COUNTER:$hb:0:U"
       "DS:iops_in:COUNTER:$hb:0:U"
       "DS:iops_out:COUNTER:$hb:0:U"
       "RRA:AVERAGE:0.5:1:$one_minute_sample"
       "RRA:AVERAGE:0.5:5:$five_mins_sample"
       "RRA:AVERAGE:0.5:60:$one_hour_sample"
       "RRA:AVERAGE:0.5:300:$five_hours_sample"
       "RRA:AVERAGE:0.5:1440:$one_day_sample"
    );
  }

  else {    # here is enxx
    RRDp::cmd qq(create "$rrd"  --start "$time-$stepx" --step "$STEP"
       "DS:recv_bytes:COUNTER:$hb:0:U"
       "DS:trans_bytes:COUNTER:$hb:0:U"
       "RRA:AVERAGE:0.5:1:$one_minute_sample"
       "RRA:AVERAGE:0.5:5:$five_mins_sample"
       "RRA:AVERAGE:0.5:60:$one_hour_sample"
       "RRA:AVERAGE:0.5:300:$five_hours_sample"
       "RRA:AVERAGE:0.5:1440:$one_day_sample"
    );
  }

  if ( !Xorux_lib::create_check("file: $rrd, $one_minute_sample, $five_mins_sample, $one_hour_sample, $five_hours_sample, $one_day_sample") ) {
    error( "unable to create $rrd : at " . __FILE__ . ": line " . __LINE__ );
    RRDp::end;
    RRDp::start "$rrdtool";
    return 0;
  }

  # create lpar directory and file hard link into the other HMC if there is dual HMC setup
  my $rrd_dir_base = basename($rrd_dir);
  foreach my $rrd_dir_new (@files) {
    chomp($rrd_dir_new);
    my $rrd_dir_new_base = basename($rrd_dir_new);
    if ( -d $rrd_dir_new && $rrd_dir_new_base !~ m/^$rrd_dir_base$/ ) {
      if ( !-d "$rrd_dir_new/$lpar/" ) {
        print_it("mkdir dual     : $rrd_dir_new/$lpar/") if $DEBUG;
        mkdir("$rrd_dir_new/$lpar/") || error( "Cannot mkdir $rrd_dir_new/$lpar/: $!" . __FILE__ . ":" . __LINE__ ) && return 0;
      }
      print_it("hard link      : $rrd --> $rrd_dir_new/$lpar/$ent.mmm") if $DEBUG;
      my $rrd_link_new = "$rrd_dir_new/$lpar/$ent.mmm";
      unlink("$rrd_dir_new/$lpar/$ent.mmm");    # for sure
      link( $rrd, "$rrd_dir_new/$lpar/$ent.mmm" ) || error( "Cannot link $rrd_dir_new/$lpar/: $!" . __FILE__ . ":" . __LINE__ ) && return 0;
    }
  }

  return 1;
}

# stdout handling
sub print_it {
  my $text     = shift;
  my $act_time = localtime();
  chomp($text);

  #print "ERROR          : $text : $!\n";
  print "$act_time: $text\n";

  return 1;
}

# error handling
sub error {
  my $text     = shift;
  my $act_time = localtime();
  chomp($text);

  #print "ERROR          : $text : $!\n";
  print STDERR "$act_time: $text : $!\n";
  print "$act_time: $text : $!\n" if $DEBUG == 2;

  return 1;
}

sub print_as400_debug {
  my $text     = shift;
  my $err_file = "$basedir/logs/as400-debug.txt";
  open( AS400_OUT, ">> $err_file" ) || error( "Cannot open for writing $err_file: $!" . __FILE__ . ":" . __LINE__ ) && return 0;
  print AS400_OUT "$text";
  close(AS400_OUT) || error( "Cannot close $err_file: $!" . __FILE__ . ":" . __LINE__ ) && return 0;
}

sub print_solaris_debug {
  my $text     = shift;
  my $err_file = "$basedir/logs/solaris-debug.txt";
  open( SOL_OUT, ">> $err_file" ) || error( "Cannot open for writing $err_file: $!" . __FILE__ . ":" . __LINE__ ) && return 0;
  print SOL_OUT "$text";
  close(SOL_OUT) || error( "Cannot close $err_file: $!" . __FILE__ . ":" . __LINE__ ) && return 0;
}

sub isdigit {
  my $digit = shift;
  my $text  = shift;

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

sub touch {
  my $text = shift;

  my $version    = "$ENV{version}";
  my $basedir    = $ENV{INPUTDIR};
  my $new_change = "$basedir/tmp/$version-run";
  my $host       = $ENV{HMC};
  my $DEBUG      = $ENV{DEBUG};

  if ( !-f $new_change ) {
    `touch $new_change`;    # say install_html.sh that there was any change
                            #if ( $text eq '' ) {
                            #  print "touch          : $host $new_change\n" if $DEBUG ;
                            #}
                            #else {
                            #  print "touch          : $host $new_change : $text\n" if $DEBUG ;
                            #}
  }

  return 0;
}

# reduces file 'lpar.mmm' into 'lpar/mem.mmm'
# at the same time creates 'lpar/pgs.mm'
# reduction:
# leave out data streams X
# data streams O export to new pgs.mmm
#
#  RRDp::cmd qq(create "$rrd"  --start "$time"  --step "$STEP"
#   "DS:size:GAUGE:$no_time:0:102400000"
#   "DS:nuse:GAUGE:$no_time:0:102400000"
#   "DS:free:GAUGE:$no_time:0:102400000"
#   "DS:pin:GAUGE:$no_time:0:102400000"
# X  "DS:virtual:GAUGE:$no_time:0:102400000"
# X  "DS:available:GAUGE:$no_time:0:102400000"
# X  "DS:loaned:GAUGE:$no_time:0:102400000"
# X  "DS:mmode:GAUGE:$no_time:0:20"
# X  "DS:size_pg:GAUGE:$no_time:0:102400000"
# X  "DS:inuse_pg:GAUGE:$no_time:0:102400000"
# X  "DS:pin_work:GAUGE:$no_time:0:102400000"
# X  "DS:pin_pers:GAUGE:$no_time:0:102400000"
# X  "DS:pin_clnt:GAUGE:$no_time:0:102400000"
# X  "DS:pin_other:GAUGE:$no_time:0:102400000"
#   "DS:in_use_work:GAUGE:$no_time:0:102400000"
# X  "DS:in_use_pers:GAUGE:$no_time:0:102400000"
#   "DS:in_use_clnt:GAUGE:$no_time:0:102400000"
# O  "DS:page_in:COUNTER:$no_time:0:U"
# O  "DS:page_out:COUNTER:$no_time:0:U"
#
#  retentions are taken from original file 'lpar.mmm'

#  creating pgs.mmm
#
#   RRDp::cmd qq(create "$rrd"  --start "$time" --step "$STEP"
#    "DS:page_in:COUNTER:$no_time:0:U"
#    "DS:page_out:COUNTER:$no_time:0:U"
#    "DS:paging_space:GAUGE:$no_time:0:U"
#    "DS:percent:GAUGE:$no_time:0:100"
#
#  retentions are taken from original file 'lpar.mmm'
#
#  algorithm:
#  -  if workdir/servers/hmcs/'lpar'.mmm ds names are as above ? no -> ret0
#  -  if not exists dir workdir/servers/hmcs/lpar/ then create
#  -  convert from 'lpar.mmm' -> lpar/mem.mmm and lpar/pgs.mmm
#  -  create hard links if dual hmc setup
#   --------------

# original data 'lpar.mmm'

#<!-- Round Robin Database Dump --><rrd> <version> 0003 </version>
#       <step> 60 </step> <!-- Seconds -->
#       <lastupdate> 1392645960 </lastupdate> <!-- 2014-02-17 15:06:00 GMT+01:00 -->
#
#       <ds>
#               <name> size </name>
#               <type> GAUGE </type>
#               <minimal_heartbeat> 120 </minimal_heartbeat>
#               <min> 0.0000000000e+00 </min>
#               <max> 1.0240000000e+08 </max>
#
#               <!-- PDP Status -->
#               <last_ds> UNKN </last_ds>
#               <value> 0.0000000000e+00 </value>
#               <unknown_sec> 0 </unknown_sec>
#       </ds>
#
#       <ds>
#               <name> nuse </name>
# and so on
#                <unknown_sec> 0 </unknown_sec>
#       </ds>

#<!-- Round Robin Archives -->   <rra>
#               <cf> AVERAGE </cf>
#               <pdp_per_row> 1 </pdp_per_row> <!-- 60 seconds -->

#               <params>
#               <xff> 5.0000000000e-01 </xff>
#               </params>
#               <cdp_prep>
#                       <ds>
#                       <primary_value> 1.0485760000e+06 </primary_value>
#                       <secondary_value> NaN </secondary_value>
#                       <value> NaN </value>
#                       <unknown_datapoints> 0 </unknown_datapoints>
#                       </ds>
#                       <ds>
#                       <primary_value> 1.0402800000e+06 </primary_value>
# and so on
#                         <unknown_datapoints> 0 </unknown_datapoints>
#                       </ds>
#                       <ds>
#                       <primary_value> 0.0000000000e+00 </primary_value>
#                       <secondary_value> NaN </secondary_value>
#                       <value> NaN </value>
#                       <unknown_datapoints> 0 </unknown_datapoints>
#                       </ds>
#               </cdp_prep>
#               <database>
#                       <!-- 2013-12-22 08:45:00 CET / 1387698300 --> <row><v> 1.0485760000e+06 </v><v> 1.0434915333e+06 </v><v> 5.0805333333e+03 </v><v> 4.0328000000e+05 </v><v> 6.2166573333e+05 </v><v> 3.7554233333e+05 </v><v> 0.0000000000e+00 </v><v> 0.0000000000e+00 </v><v> 3.2768000000e+06 </v><v> 6.5034000000e+03 </v><v> 3.5370000000e+05 </v><v> 0.0000000000e+00 </v><v> 0.0000000000e+00 </v><v> 4.9580000000e+04 </v><v> 6.2166573333e+05 </v><v> 0.0000000000e+00 </v><v> 4.2182580000e+05 </v><v> 0.0000000000e+00 </v><v> 0.0000000000e+00 </v></row>
#                       <!-- 2013-12-22 08:46:00 CET / 1387698360 --> <row><v> 1.0485760000e+06 </v><v> 1.0446240000e+06 <
# and so on
#                        <!-- 2014-02-20 08:44:00 CET / 1392882240 --> <row><v> 1.0485760000e+06 </v><v> 1.0402800000e+06 </v><v> 7.7720000000e+03 </v><v> 4.1174000000e+05 </v><v> 6.3619600000e+05 </v><v> 3.6001200000e+05 </v><v> 0.0000000000e+00 </v><v> 0.0000000000e+00 </v><v> 3.2768000000e+06 </v><v> 6.5280000000e+03 </v><v> 3.6216000000e+05 </v><v> 0.0000000000e+00 </v><v> 0.0000000000e+00 </v><v> 4.9580000000e+04 </v><v> 6.3567200000e+05 </v><v> 0.0000000000e+00 </v><v> 4.0460800000e+05 </v><v> 0.0000000000e+00 </v><v> 0.0000000000e+00 </v></row>
#                </database>
#       </rra>
#       <rra>
#               <cf> AVERAGE </cf>
#               <pdp_per_row> 5 </pdp_per_row> <!-- 300 seconds -->

#                <params>
#               <xff> 5.0000000000e-01 </xff>
#               </params>
#               <cdp_prep>
#                       <ds>
#                       <primary_value> 1.0485760000e+06 </primary_value>
# and so on
#
#              <pdp_per_row> 60 </pdp_per_row> <!-- 3600 seconds -->
#              <pdp_per_row> 300 </pdp_per_row> <!-- 18000 seconds -->
#              <pdp_per_row> 1440 </pdp_per_row> <!-- 86400 seconds -->

#

#  ****    main  ****
#

sub conv_lpar {
  my $rrd_file = shift;    # file to convert, usually "wrkdir/server/hmc/lpar.mmm"
  my $server   = shift;
  my $lpar     = shift;
  my $rrd_dir  = shift;    # "wrkdir/server/hmc/lpar"
  my $tmpd     = shift;

  # flush after every write
  $| = 1;
  my @filestttt = bsd_glob "$tmpd/*.tttt";
  if ( $filestttt[0] ne "" ) {
    `rm -r $tmpd/*.tttt`;
  }

  # start RRD pipe
  # RRDp::start "$rrdtool";
  my $tmpdir = "$tmpd/$server.$lpar.tttt";
  mkdir("$tmpdir") || error( "Cannot mkdir $tmpdir: $!" . __FILE__ . ":" . __LINE__ );
  my $f_dumped = "$tmpdir/rrd_dump";
  unlink($f_dumped);    #in any case

  RRDp::cmd qq(dump "$rrd_file" "$f_dumped");
  my $answer = RRDp::read;
  if ( $$answer =~ "ERROR" ) {
    error(" Convert rrdtool error : $$answer");
    if ( $$answer =~ "is not an RRD file" ) {
      ( my $err, my $file, my $txt ) = split( /'/, $$answer );
      error("It needs to be removed due to corruption: $file");
    }
    else {
      error("Convert rrdtool error : $$answer");
    }
    return 0;
  }

  open( DF_IN, "< $f_dumped" ) || error( "Cannot open for reading $f_dumped: $!" . __FILE__ . ":" . __LINE__ ) && return 0;

  my $f_pgs = "$tmpdir/rrd_dump_pgs";
  open( DF_OUT, "> $f_pgs" ) || error( "Cannot open for writing $f_pgs: $!" . __FILE__ . ":" . __LINE__ ) && return 0;

  my $line;
  while ( $line = <DF_IN> ) {    # beginning
    print DF_OUT "$line";
    last if ( $line =~ "<rrd>" );
  }
  my $version_dump = 0;          # our version
  if ( $line !~ "version" ) {
    $version_dump = 1;           # FOUCOU version
  }
  while ( $line = <DF_IN> ) {    # beginning
    print DF_OUT "$line";
    last if ( $line =~ "<ds>" );
  }
  while ( $line = <DF_IN> ) {
    last if ( $line =~ "<name> page_in </name>" );    # both version
  }
  print DF_OUT "$line";
  while ( $line = <DF_IN> ) {                         #R&W page_in page_out
    print DF_OUT "$line";
    last if ( $line =~ "<ds>" );
  }
  while ( $line = <DF_IN> ) {
    print DF_OUT "$line";
    last if ( $line =~ "</ds>" );
  }
  if ( $version_dump == 0 ) {
    print DF_OUT "
	<ds>
		<name> paging_space </name>
		<type> GAUGE </type>
		<minimal_heartbeat> 120 </minimal_heartbeat>
		<min> 0.0000000000e+00 </min>
		<max> NaN </max>

		<!-- PDP Status -->
		<last_ds> UNKN </last_ds>
		<value> 0.0000000000e+00 </value>
		<unknown_sec> 0 </unknown_sec>
	</ds>

	<ds>
		<name> percent </name>
		<type> GAUGE </type>
		<minimal_heartbeat> 120 </minimal_heartbeat>
		<min> 0.0000000000e+00 </min>
		<max> 1.0000000000e+02 </max>

		<!-- PDP Status -->
		<last_ds> UNKN </last_ds>
		<value> 0.0000000000e+00 </value>
		<unknown_sec> 0 </unknown_sec>
	</ds>
";
  }
  else {    # version FOUCOU
    print DF_OUT "
	<ds>
		<name> paging_space </name>
		<type> GAUGE </type>
		<minimal_heartbeat>120</minimal_heartbeat>
		<min>0.0000000000e+00</min>
		<max>NaN</max>

		<!-- PDP Status -->
		<last_ds>UNKN</last_ds>
		<value>0.0000000000e+00</value>
		<unknown_sec> 0 </unknown_sec>
	</ds>

	<ds>
		<name> percent </name>
		<type> GAUGE </type>
		<minimal_heartbeat>120</minimal_heartbeat>
		<min>0.0000000000e+00</min>
		<max>1.0000000000e+02</max>

		<!-- PDP Status -->
		<last_ds>UNKN</last_ds>
		<value>0.0000000000e+00</value>
		<unknown_sec> 0 </unknown_sec>
	</ds>
";
  }

  # <!-- Round Robin Archives -->   <rra>
  # reading data points - 5 cycles (RRA definition and data points) and till the end

  my $rra_lines;
  if ( $version_dump == 0 ) {
    $rra_lines = "			<ds>
			<primary_value> NaN </primary_value>
			<secondary_value> NaN </secondary_value>
			<value> NaN </value>
			<unknown_datapoints> 0 </unknown_datapoints>
			</ds>
			<ds>
			<primary_value> NaN </primary_value>
			<secondary_value> NaN </secondary_value>
			<value> NaN </value>
			<unknown_datapoints> 0 </unknown_datapoints>
			</ds>
";
  }
  else {
    $rra_lines = "			<ds>
			<primary_value>NaN</primary_value>
			<secondary_value>NaN</secondary_value>
			<value>NaN</value>
			<unknown_datapoints>0</unknown_datapoints>
			</ds>
			<ds>
			<primary_value>NaN</primary_value>
			<secondary_value>NaN</secondary_value>
			<value>NaN</value>
			<unknown_datapoints>0</unknown_datapoints>
			</ds>
";
  }

  for ( my $cycle = 0; $cycle <= 4; $cycle++ ) {
    while ( $line = <DF_IN> ) {    # until ds
      print DF_OUT "$line";
      last if ( $line =~ "<ds>" );
    }
    for ( my $ix = 1; $ix < 18; $ix++ ) {
      while ( $line = <DF_IN> ) {    # leave out until page_in ds
        last if ( $line =~ "<ds>" );
      }
    }
    while ( $line = <DF_IN> ) {      # for page_in
      print DF_OUT "$line";
      last if ( $line =~ "<ds>" );
    }
    while ( $line = <DF_IN> ) {      # for page_out_
      print DF_OUT "$line";
      last if ( $line =~ "</ds>" );
    }
    print DF_OUT "$rra_lines";       # and next two ds
    $line = <DF_IN>;
    print DF_OUT "$line";

    while ( $line = <DF_IN> ) {
      if ( $line =~ /<\/v><\/row>/ ) {
        ( my $p1, undef, undef, undef, undef, undef, undef, undef, undef, undef, undef, undef, undef, undef, undef, undef, undef, undef, my $p2, my $p3 ) = split( /<v>/, $line );
        if ( $version_dump == 0 ) {
          $p3 =~ s/<\/row>/<v> NaN <\/v><v> NaN <\/v><\/row>/;
        }
        else {
          $p3 =~ s/<\/row>/<v>NaN<\/v><v>NaN<\/v><\/row>/;
        }
        $line = $p1 . "<v>" . $p2 . "<v>" . $p3;
      }
      print DF_OUT "$line";
      last if ( $line =~ "<cdp_prep>" );
    }
  }    # end of for cycle

  while ( $line = <DF_IN> ) {    # until end of file
    print DF_OUT "$line";
  }                              # end of file

  close(DF_OUT) || error( "Cannot close $f_pgs: $!" . __FILE__ . ":" . __LINE__ )    && return 0;
  close(DF_IN)  || error( "Cannot close $f_dumped: $!" . __FILE__ . ":" . __LINE__ ) && return 0;

  #   2nd part: read dumped 'lpar.mmm', create mem.mmm,

  open( DF_IN, "< $f_dumped" ) || error( "Cannot open for reading $f_dumped: $!" . __FILE__ . ":" . __LINE__ ) && return 0;
  my $f_mem = "$tmpdir/rrd_dump_mem";
  open( DF_OUT, "> $f_mem" ) || error( "Cannot open for writing $f_mem: $!" . __FILE__ . ":" . __LINE__ ) && return 0;

  while ( $line = <DF_IN> ) {    # beginning
    print DF_OUT "$line";
    last if ( $line =~ "<ds>" );
  }
  while ( $line = <DF_IN> ) {    # size
    print DF_OUT "$line";
    last if ( $line =~ "<ds>" );
  }
  while ( $line = <DF_IN> ) {    # nuse
    print DF_OUT "$line";
    last if ( $line =~ "<ds>" );
  }
  while ( $line = <DF_IN> ) {    # free
    print DF_OUT "$line";
    last if ( $line =~ "<ds>" );
  }
  while ( $line = <DF_IN> ) {    # pin
    print DF_OUT "$line";
    last if ( $line =~ "<ds>" );
  }
  while ( $line = <DF_IN> ) {
    last if ( $line =~ "<name> in_use_work </name>" );
  }
  print DF_OUT "$line";
  while ( $line = <DF_IN> ) {    # in_use_work
    print DF_OUT "$line";
    last if ( $line =~ "<ds>" );
  }
  while ( $line = <DF_IN> ) {
    last if ( $line =~ "<name> in_use_clnt </name>" );
  }
  print DF_OUT "$line";
  while ( $line = <DF_IN> ) {    # in_use_clnt_
    print DF_OUT "$line";
    last if ( $line =~ "</ds>" );
  }
  while ( $line = <DF_IN> ) {
    last if ( $line =~ "Round Robin" );
  }
  print DF_OUT "\n$line";

  for ( my $cycle = 0; $cycle <= 4; $cycle++ ) {

    while ( $line = <DF_IN> ) {    # until ds
      print DF_OUT "$line";
      last if ( $line =~ "<ds>" );
    }
    while ( $line = <DF_IN> ) {    # size
      print DF_OUT "$line";
      last if ( $line =~ "<ds>" );
    }
    while ( $line = <DF_IN> ) {    # nuse
      print DF_OUT "$line";
      last if ( $line =~ "<ds>" );
    }
    while ( $line = <DF_IN> ) {    # free
      print DF_OUT "$line";
      last if ( $line =~ "<ds>" );
    }
    while ( $line = <DF_IN> ) {    # pin
      print DF_OUT "$line";
      last if ( $line =~ "<ds>" );
    }
    for ( my $ix = 1; $ix < 11; $ix++ ) {
      while ( $line = <DF_IN> ) {    # leave out until in_use_work
        last if ( $line =~ "<ds>" );
      }
    }
    while ( $line = <DF_IN> ) {      # in_use_work
      print DF_OUT "$line";
      last if ( $line =~ "<ds>" );
    }
    while ( $line = <DF_IN> ) {      # leave out until in_use_clnt
      last if ( $line =~ "<ds>" );
    }
    while ( $line = <DF_IN> ) {      # in_use_clnt
      print DF_OUT "$line";
      last if ( $line =~ "</ds>" );
    }
    while ( $line = <DF_IN> ) {      # leave out until in_use_clnt
      last if ( $line =~ "</cdp_prep>" );
    }
    print DF_OUT "$line";
    while ( $line = <DF_IN> ) {
      if ( $line =~ /<\/v><\/row>/ ) {
        ( my $p1, my $size, my $nuse, my $free, my $pin, undef, undef, undef, undef, undef, undef, undef, undef, undef, undef, my $in_use_work, undef, my $in_use_clnt, undef, undef ) = split( /<v>/, $line );
        $line = $p1 . "<v>" . $size . "<v>" . $nuse . "<v>" . $free . "<v>" . $pin . "<v>" . $in_use_work . "<v>" . $in_use_clnt . "<\/row>\n";
      }
      print DF_OUT "$line";
      last if ( $line =~ "<cdp_prep>" );
    }
  }    # end of for cycle

  while ( $line = <DF_IN> ) {    # until end of file
    print DF_OUT "$line";
  }                              # end of file

  close(DF_OUT) || error( "Cannot close $f_mem: $!" . __FILE__ . ":" . __LINE__ )    && return 0;
  close(DF_IN)  || error( "Cannot close $f_dumped: $!" . __FILE__ . ":" . __LINE__ ) && return 0;

  # test file pgs

  my $tmp_pgs = "$tmpdir/rrd_pgs";
  unlink("$tmp_pgs");

  RRDp::cmd qq(restore "$f_pgs" "$tmp_pgs");
  $answer = RRDp::read;
  if ( $$answer =~ "ERROR" ) {
    error(" Convert rrdtool error : $$answer");
    if ( $$answer =~ "is not an RRD file" ) {
      ( my $err, my $file, my $txt ) = split( /'/, $$answer );
      error("It needs to be removed due to corruption: $file");
    }
    else {
      error("Convert rrdtool error : $$answer");
    }
    return 0;
  }

  $rrd_file = $tmp_pgs;
  $f_dumped = "$tmpdir/rrd_dump_pgs2";
  unlink($f_dumped);    #in any case

  RRDp::cmd qq(dump "$rrd_file" "$f_dumped");
  $answer = RRDp::read;
  if ( $$answer =~ "ERROR" ) {
    error(" Convert rrdtool error : $$answer");
    if ( $$answer =~ "is not an RRD file" ) {
      ( my $err, my $file, my $txt ) = split( /'/, $$answer );
      error("It needs to be removed due to corruption: $file");
    }
    else {
      error("Convert rrdtool error : $$answer");
    }
    return 0;
  }
  my $f_one = "$tmpdir/rrd_dump_pgs";
  my $f_two = "$tmpdir/rrd_dump_pgs2";
  if ( compare( "$f_one", "$f_two" ) != 0 ) {
    error( "$f_one, $f_two are not the same for $rrd_dir : $!" . __FILE__ . ":" . __LINE__ ) && return 0;
  }
  unlink("$f_one");
  unlink("$f_two");

  # test file mem

  my $tmp_mem = "$tmpdir/rrd_mem";
  unlink("$tmp_mem");

  RRDp::cmd qq(restore "$f_mem" "$tmp_mem");
  $answer = RRDp::read;
  if ( $$answer =~ "ERROR" ) {
    error(" Convert rrdtool error : $$answer");
    if ( $$answer =~ "is not an RRD file" ) {
      ( my $err, my $file, my $txt ) = split( /'/, $$answer );
      error("It needs to be removed due to corruption: $file");
    }
    else {
      error("Convert rrdtool error : $$answer");
    }
    return 0;
  }

  $rrd_file = $tmp_mem;
  $f_dumped = "$tmpdir/rrd_dump_mem2";
  unlink($f_dumped);    #in any case

  RRDp::cmd qq(dump "$rrd_file" "$f_dumped");
  $answer = RRDp::read;
  if ( $$answer =~ "ERROR" ) {
    error(" Convert rrdtool error : $$answer");
    if ( $$answer =~ "is not an RRD file" ) {
      ( my $err, my $file, my $txt ) = split( /'/, $$answer );
      error("It needs to be removed due to corruption: $file");
    }
    else {
      error("Convert rrdtool error : $$answer");
    }
    return 0;
  }
  $f_one = "$tmpdir/rrd_dump_mem";
  $f_two = "$tmpdir/rrd_dump_mem2";
  if ( compare( "$f_one", "$f_two" ) != 0 ) {
    error( "$f_one, $f_two are not the same for $rrd_dir : $!" . __FILE__ . ":" . __LINE__ ) && return 0;
  }
  unlink("$f_one");
  unlink("$f_two");

  # ready to place files in dir lpar/

  if ( !-d "$rrd_dir/" ) {
    mkdir("$rrd_dir/") || error( "Cannot mkdir $rrd_dir/: $!" . __FILE__ . ":" . __LINE__ ) && return 0;
  }
  my $rrd_file_pgs = "$rrd_dir/pgs.mmm";
  my $rrd_file_mem = "$rrd_dir/mem.mmm";
  move( "$tmpdir/rrd_pgs", "$rrd_file_pgs" ) || error( "Cannot move $rrd_dir/pgs.mmm: $!" . __FILE__ . ":" . __LINE__ ) && return 0;
  move( "$tmpdir/rrd_mem", "$rrd_file_mem" ) || error( "Cannot move $rrd_dir/pgs.mmm: $!" . __FILE__ . ":" . __LINE__ ) && return 0;

  unlink("$tmpdir/rrd_dump");

  # create lpar directory and file hard link into the other HMC if there is dual HMC setup

  my $found        = 0;
  my $server_space = $server;
  if ( $server =~ m/ / ) {
    $server_space = "\"" . $server . "\"";    # it must be here to support space with server names
  }
  my @files = <$wrkdir/$server_space/*>;

  $rrd_dir = "";
  foreach my $rrd_dir_tmp (@files) {
    chomp($rrd_dir_tmp);
    if ( -d $rrd_dir_tmp ) {
      $found   = 1;
      $rrd_dir = $rrd_dir_tmp;
      last;
    }
  }
  if ( $found == 0 ) {
    error( "Convert: Could not found a HMC in : $wrkdir/$server $!" . __FILE__ . ":" . __LINE__ ) && return 0;
  }

  my $rrd_dir_base = basename($rrd_dir);
  foreach my $rrd_dir_new (@files) {
    chomp($rrd_dir_new);
    my $rrd_dir_new_base = basename($rrd_dir_new);
    if ( -d $rrd_dir_new && $rrd_dir_new_base !~ m/^$rrd_dir_base$/ ) {
      if ( !-d "$rrd_dir_new/$lpar/" ) {
        print_it("mkdir dual     : $rrd_dir_new/$lpar/") if $DEBUG;
        mkdir("$rrd_dir_new/$lpar/") || error( "Cannot mkdir $rrd_dir_new/$lpar/: $!" . __FILE__ . ":" . __LINE__ ) && return 0;
      }
      print_it("hard link      : $rrd_file_mem --> $rrd_dir_new/$lpar/mem.mmm") if $DEBUG;
      my $rrd_link_new = "$rrd_dir_new/$lpar/mem.mmm";
      unlink("$rrd_dir_new/$lpar/mem.mmm");    #for every case
      link( $rrd_file_mem, "$rrd_dir_new/$lpar/mem.mmm" ) || error( "Cannot link $rrd_dir_new/$lpar/mem.mmm: $!" . __FILE__ . ":" . __LINE__ ) && return 0;

      print_it("hard link      : $rrd_file_pgs --> $rrd_dir_new/$lpar/pgs.mmm") if $DEBUG;
      $rrd_link_new = "$rrd_dir_new/$lpar/pgs.mmm";
      unlink("$rrd_dir_new/$lpar/pgs.mmm");    #for every case
      link( $rrd_file_pgs, "$rrd_dir_new/$lpar/pgs.mmm" ) || error( "Cannot link $rrd_dir_new/$lpar/pgs.mmm: $!" . __FILE__ . ":" . __LINE__ ) && return 0;
    }
  }

  #  unlink the original 'lpar.mmm', care if double hmc
  foreach my $rrd_dir_new (@files) {
    chomp($rrd_dir_new);
    if ( -f "$rrd_dir_new/$lpar.mmm" ) {
      if ( -f "$rrd_dir_new/$lpar/mem.mmm" && -f "$rrd_dir_new/$lpar/pgs.mmm" ) {
        print_it("deleting org   : $rrd_dir_new/$lpar.mmm");
        unlink("$rrd_dir_new/$lpar.mmm");
      }
      else {
        print_it("not delete org : conversion failed for: $rrd_dir_new/$lpar.mmm, do not exist: $rrd_dir_new/$lpar/mem.mmm - $rrd_dir_new/$lpar/pgs.mmm");
        error("not delete org : conversion failed for: $rrd_dir_new/$lpar.mmm, do not exist: $rrd_dir_new/$lpar/mem.mmm - $rrd_dir_new/$lpar/pgs.mmm");
      }
    }
  }
  rmdir("$tmpdir") || error( "Cannot rmdir $tmpdir: $!" . __FILE__ . ":" . __LINE__ );

  return 1;
}

sub save_smt {
  my $smt      = shift;
  my $server   = shift;
  my $wrkdir   = shift;
  my $lpar     = shift;
  my $smt_file = "cpu.txt";

  if ( !defined($smt) || $smt eq '' || $smt !~ m/\|/ ) {
    return -1;
  }

  $smt =~ s/^.*\|//;    # filter out SMT

  if ( isdigit($smt) == 0 ) {
    return -1;          # OS agent probably does not support it
  }

  my $server_space = $server;
  if ( $server =~ m/ / ) {
    $server_space = "\"" . $server . "\"";    # it must be here to support space with server names
  }

  $lpar =~ s/\//&&1/g;                        # real file name, until 4.84-1 there was a bug

  my @hmcs = <$wrkdir/$server_space/*>;
  foreach my $hmc (@hmcs) {
    chomp($hmc);
    if ( !-d "$hmc" ) {
      next;
    }

    # update only once a day
    my $smt_file_name = "$hmc/$lpar/$smt_file";
    if ( -f "$smt_file_name" ) {
      my $time  = time();
      my $timem = ( ( stat("$smt_file_name") )[9] );
      if ( ( $time - $timem ) < 3600 ) {
        return 1;    # no update now
      }
    }

    open( FHS, "> $smt_file_name" ) || error( "Can't open $smt_file_name : $!" . __FILE__ . ":" . __LINE__ ) && return 0;
    print FHS "$smt\n";
    close(FHS);
    print "Saving SMT info into $smt_file_name : $smt\n" if $DEBUG == 2;
    last;
  }

  return 1;
}

sub save_cpu_ghz {
  my $cpu_hz_global = shift;
  my $cpu_hz        = shift;
  my $server        = shift;
  my $wrkdir        = shift;
  my $cpu_file      = "cpu_mhz.txt";

  #print "001 $cpu_hz_global : $cpu_hz \n";
  $cpu_hz_global =~ s/\|.*//;    #filter out SMT
  $cpu_hz        =~ s/\|.*//;    #filter out SMT
  if ( isdigit($cpu_hz_global) && $cpu_hz_global > 1000000000 ) {
    return $cpu_hz_global;       # already stored, skip it
  }

  #print "002 $cpu_hz_global : $cpu_hz \n";
  if ( $cpu_hz eq '' || !isdigit($cpu_hz) ) {
    return 0;                    # some problem, ignore
  }

  #print "003 $cpu_hz_global : $cpu_hz : \n";
  if ( isdigit($cpu_hz) && $cpu_hz < 1000000000 ) {
    return 0;                    # some problem, ignore
  }

  my $cpu_mhz = $cpu_hz / 1000000;

  my $server_space = $server;
  if ( $server =~ m/ / ) {
    $server_space = "\"" . $server . "\"";    # it must be here to support space with server names
  }

  #print "004 $cpu_hz_global : $cpu_hz : \n";
  my @hmcs = <$wrkdir/$server_space/*>;
  foreach my $hmc (@hmcs) {
    chomp($hmc);
    if ( !-d "$hmc" ) {
      next;
    }

    # update only once a day
    if ( -f "$hmc/$cpu_file" ) {

      #print "003 $cpu_hz_global : $cpu_hz : $hmc/$cpu_file\n";
      my $time  = time();
      my $timem = ( ( stat("$hmc/$cpu_file") )[9] );
      if ( ( $time - $timem ) < 86400 ) {

        #print "004 $cpu_hz_global : $cpu_hz : $hmc/$cpu_file\n";
        return $cpu_hz;    # no update now
      }
    }

    open( FH, "> $hmc/$cpu_file" ) || error( "Can't open $hmc/$cpu_file.txt : $!" . __FILE__ . ":" . __LINE__ ) && return 0;
    print FH "$cpu_mhz\n";
    close(FH);
    print "Saving CPU MHZ into $hmc/$cpu_file : $cpu_mhz\n" if $DEBUG == 2;

    #print "005 $cpu_hz_global : $cpu_hz : $hmc/$cpu_file\n";
    last;
  }

  return $cpu_hz;
}

# returns 0 - fatal error, original $time as OK
# $lpar is global variable where is the lpar name which was found out based on lpar_id
#  --> it is done once per a connection to do not do it for each record

sub store_data_50    # AS400
{
  my $data             = shift;
  my $last_rec         = shift;
  my $protocol_version = shift;
  my $peer_address     = shift;

  my $DEBUG = $ENV{DEBUG};
  $DEBUG = 2 if ( -f "$tmpdir/as400-debug" );
  my $en_last_rec = $last_rec;
  my $act_time    = localtime();

  $wrkdir = "$basedir/data";    #cause this is changed by external NMON processing

  #example of $data here ! data is one line !
  # 1st part is info about server, lpar, date, version, licence date
  # 9406-520*65356BE:65-356BE:1:1473229851:Sep 07 2016 08:30:51.300 version 1.0.4:2017-09-04::::

  # format of following data:
  # 9 items - example 9 items - control string saying how to process data
  # control items 4th - 9th contain |MIN|MAX info when creating DS in rrdfile (GAUGE or COUNTER)
  # processing data:
  # 1st item - name; if it is same as 1st control item -> this is name of rrdfile to store data
  #                  if not the same, take 1st control item as a name of rrdfile to store data
  # 2nd item -
  # 3rd item -
  # 4th - 9th item; if 'number' - check for number and save to rrdfile
  # 4th - 9th item; if 'str_2'  - check for only two exact possibilities
  # 4th - 9th item; if 'str_1_all'  - check for only one exact possibility and all others
  # 4th - 9th item; if 'str_3'  - check for one from 3 exact possibilities

  my $number         = "number|0|U";                              # GAUGE
  my $number_counter = "number|0|U|COUNTER";
  my $str_ONOF       = "str_2,OF,0,ON,1,|0|999";
  my $str_prg2i      = "str_1_all,prg2i,0,1,|0|999";
  my $str_PRG2I      = "str_1_all,PRG2I,0,1,|0|999";
  my $str_FIXED      = "str_3,*FIXED,0,*SAME,1,*CALC,2,|0|999";
  my $ignore         = "ignore|0|U";

  my $dat = "LPARF1PAR1:::prg2i:4:2:ON:OF::LPARF1PAR1:::$str_prg2i:$number:$number:$str_ONOF:$str_ONOF\::
LPARF1PAR2:::10368:4224:64:10000000:::LPARF1PAR2:::$number:$number:$number:$number\:::
LPARF1PAR3:::2:1:2:0.10:2.00:0.01:LPARF1PAR3:::$number:$number:$number:$number:$number:$number:
LPARF1PAR4:::0.00:0.00:2::::LPARF1PAR4:::$number:$number:$number\::::
LPARF1PAR5:::0.80:1:7296:128:0.00::LPARF1PAR5:::$number:$number:$number:$number:$number\::
LPARF2PAR1:::2:OF:ON:OF:::LPARF2PAR1:::$number:$str_ONOF:$str_ONOF:$str_ONOF\:::
LPARF2PAR2:::7296:71653186000000:51070000000:0:0:3999999:LPARF2PAR2:::$number:$number:$number:$number:$number:$number:
LPARF2PAR3:::2:1:2:0.00:0.80:128:LPARF2PAR3:::$number:$number:$number:$number:$number:$number:
LPARF2PAR4:::0:0.10:0:4.00:32772:0:LPARF2PAR4:::$number:$number:$number:$number:$number:$number:
LPARF2PAR5:::100.00:0:::::LPARF2PAR5:::$number:$number\:::::
S0220PARAM1:::PRG2I:000001:0:2:1.6:305:S0220PARAM1:::$str_PRG2I:$number:$number:$number:$number:$number:
S0220PARAM2:::3:0.80:1:261:821:163520:S0220PARAM2:::$number:$number:$number:$number:$number:$number:
S0400STORAGE:::PRG2I:000001:7396352:270016:422656::S0400STORAGE:::$str_PRG2I:$number:$number:$number:$number\::
S0400STORAGEL:::7396352:270016:422656::::S0400STORAGEL:::$number:$number:$number\::::
S040000Parm1:::*FIXED:1:716800:261824:::S040000Parm1:::$str_FIXED:$ignore:$number:$number\:::
S040000Parm2:::32767:0.0:0.0:0.0:0.0:166.3:S040000Parm2:::$number:$number:$number:$number:$number:$number:
S040000Parm3:::0.0:0.0:716800:125:0::S040000Parm3:::$number:$number:$number:$number:$number\::
S040000Parm4:::1:5.11:100.00:10.00:0.00:10.00:S040000Parm4:::$number:$number:$number:$number:$number:$number:
S040000Parm5:::0:0:716800:716800:::S040000Parm5:::$number:$number:$ignore:$ignore\:::
S0200INFO:::PRG2I:000425:0:0.0:3:4:S0200INFO:::$str_PRG2I:$number:$number:$number:$number:$number:
S0200PROCS:::1.3:0.80:2:1:0.0:820:S0200PROCS:::$number:$number:$number:$number:$number:$number:
S0200ASPJOB:::313:977105:23.9326:977105:260:163520:S0200ASPJOB:::$number:$number:$number:$number:$number:$number:
S0200ADDR:::0.010:0.035:0.000:0.000:0.000:0.000:S0200ADDR:::$number:$number:$number:$number:$number:$number:
S0200STORAGE:::22174:23952:7396352:0:1.0:7396352:S0200STORAGE:::$number:$number:$number:$number:$number:$number:
LST300JOB1:::RTV_SYSSTS CZ50257PH  177793:PH_SBS:CZ50257PH:BCH:0.5:RUN:LST300JOB1:::$number:$number:$number:$number:$number_counter:$number_counter:
LST300JOB2:::01.056:1:PGM-C_RTVSTS:10:*BASE:50:LST300JOB2:::$number:$number:$number:$number:$number_counter:$number_counter:
LST300JOB3:::258:0000.00.00.429:0:0:0000.00.00.005:0:LST300JOB3:::$number:$number:$number:$number:$number_counter:$number_counter:
LST300JOB4:::5:340:2:3:::LST300JOB4:::$number:$number:$number:$number:$number_counter:$number_counter:
ASP000Parm1:::resource:device:1:1:database:primary:ASP000Parm1:::$ignore\::::::
ASP000Parm2:::1:2:3:4:ASP status::ASP000Parm2:::$number:$number:$number:$number\:::
ASP000Parm3:::1:2:3:4:5:6:ASP000Parm3:::$number:$number:$number:$number:$number:$number:
ASP000Parm4:::1:2:3:4:5:6:ASP000Parm4:::$number:$number:$number:$number:$number:$number:
IFCD0100PAR1:::ETHLINE:Active:ELAN:00x21x5Ex19x76xA1:134458:6512106:IFCD0100PAR1:::$number:$number:$number:$number:$number:$number:
IFCD0100PAR2:::2586:0:0:2385:0:0:IFCD0100PAR2:::$number:$number:$number:$number:$number:$number:
ASPParm7:::1:68-0ECD5C0:1:1:2:2:ASPParm7:::$number:$number\:::::
LTCParm1:::1:0:0:2.971:0.013::LTCParm1:::$ignore:$number:$number:$number:$number\::";

  my @dat_tf = split /\s*\n\s*/, $dat;    # prepare for easy testing

  #print "$dat\n";
  #print Dumper(@dat_tf);

  # line1 example
  # LPARF1PAR1:::prg2i:4:2:ON:OF::
  # LPARF1PAR2:::10368:4224:64:10000000:::
  # LPARF1PAR3:::2:1:2:0.10:2.00:0.01:
  # LPARF1PAR4:::0.00:0.00:2::::
  # LPARF1PAR5:::0.80:1:7296:128:0.00::
  # LPARF2PAR1:::2:OF:ON:OF:::
  # LPARF2PAR2:::7296:71653186000000:51070000000:0:0:3999999:
  # LPARF2PAR3:::2:1:2:0.00:0.80:128:
  # LPARF2PAR4:::0:0.10:0:4.00:32772:0:
  # LPARF2PAR5:::100.00:0::::
  #line2 example - pools counted from 01 to 64
  # 8203-E4A*0659DC4:prg2i:4:1450041258:Dec 13 2015 21:14:18.360 version 1.0.0:::::
  # S0220PARAM1:::PRG2I:000001:0:2:1.6:305:
  # S0220PARAM2:::3:0.80:1:261:821:163520:
  # S0400STORAGE:::PRG2I:000001:7396352:270016:422656::
  # S0400STORAGEL:::7396352:270016:422656:::
  # S040001Parm1:::*FIXED:*MACHINE:716800:355164:::
  # S040001Parm2:::32767:0.0:0.0:0.0:0.0:28.0:
  # S040001Parm3:::0.0:0.0:716800:95:0::
  # S040001Parm4:::1:6.02:100.00:10.00:0.00:10.00:
  # S040001Parm5:::0:0:716800:716800:::
  # S040002Parm1:::*CALC:*BASE:6609664:4528:::S040002Parm2:::100:0.1:0.6:0.2:2.5:6752.9:S040002Parm3:::0.0:0.0:0:599:0::
  # S040002Parm4:::1:6.16:100.00:12.00:1.00:200.00:S040002Parm5:::5:32767:6609664:0:::
  # S040003Parm1:::*FIXED:*INTERACT:1024000:0:::S040003Parm2:::7:0.0:0.0:0.1:1.3:143.4:S040003Parm3:::0.0:0.0:1024000:12:0::
  # S040003Parm4:::1:10.00:100.00:12.00:1.00:200.00:S040003Parm5:::5:32767:1024000:1024000:::
  # S040004Parm1:::*FIXED:*SPOOL:102400:0:::S040004Parm2:::2:0.0:0.0:0.0:0.0:0.0:S040004Parm3:::0.0:0.0:102400:1:0::
  # S040004Parm4:::2:1.00:100.00:5.00:1.00:100.00:S040004Parm5:::5:32767:102400:102400:::
  # S040005Parm1:::*FIXED:1:256:0:MILAN:QGPL:
  # S040005Parm2:::1:0.0:0.0:0.0:0.0:0.0:
  # S040005Parm3:::0.0:0.0:256:0:0::
  # S040005Parm4:::0:0.00:0.00:0.00:0.00:0.00:
  # S040005Parm5:::0:0:256:256:::
  #line3 example
  # 8203-E4A*0659DC4:prg2i:4:1450082489:Dec 14 2015 08:41:29.580 version 1.0.0:::::
  # S0200INFO:::PRG2I:000425:0:0.0:3:4:
  # S0200PROCS:::1.3:0.80:2:1:0.0:820:
  # S0200ASPJOB:::313:977105:23.9326:977105:260:163520:
  # S0200ADDR:::0.010:0.035:0.000:0.000:0.000:0.000:
  # S0200STORAGE:::22174:23952:7396352:0:1.0:7396352:
  #line4 example
  # 8203-E4A*0659DC4:prg2i:4:1454495512:Feb 03 2016 10:31:52.720 version 1.0.0:::::
  # LST300JOB1:::RTV_SYSSTS CZ50257PH  177793:PH_SBS:CZ50257PH:BCH:0.5:RUN:
  # LST300JOB2:::01.056:1:PGM-C_RTVSTS:10:*BASE:50:
  # LST300JOB3:::258:0000.00.00.429:0:0:0000.00.00.005:0:
  # LST300JOB4:::5:340:2:3:::
  #line5 example
  # ASP123Parm1:::resource:device:1:1:database:primary:ASP123Parm1:::
  # ASP123Parm2:::1:2:3:4:5::
  # ASP123Parm3:::1:2:3:4:5:6:
  # ASP123Parm4:::1:2:3:4:5:6:
  #line6 example
  # IFCD0100PAR1:::ETHLINE:Active:ELAN:00x21x5Ex19x76xA1:134458:6512106:IFCD0100PAR1:::
  # IFCD0100PAR2:::2586:0:0:2385:0:0:IFCD0100PAR2:::
  #line7 example
  # ASPParm7:::1:68-0ECD5C0:1:1:2:2:
  #line8 example - latency
  # LTCParm1:::ASP number:Buffer overruns:Buffer underruns:Disk service time:Disk wait time::
  # LTCParm1:::1:0:0:2.971:0.013::
  # LTCParm1:::2:0:0:1.696:0.000::
  # LTCParm1:::33:0:0:1.340:0.000::

  my $server    = "";
  my $lpar_name = "";
  my $lpar_id   = -1;
  my $wpar_name;
  my $wpar_id;
  my $time = "";

  # as a success: always returns the original unix time - means $datar[3]

  # items count test

  my @datar = split( ":", $data . "sentinel" );
  $datar[-1] =~ s/sentinel$//;
  my $datar_len = @datar;

  if ( ( $datar_len % 9 ) != 2 ) {
    if ( $protocol_version >= 50 ) {

      # AS400 can send one ":"
      $data =~ s/:$//;
      @datar = split( ":", $data . "sentinel" );
      $datar[-1] =~ s/sentinel$//;
      $datar_len = @datar;
      if ( ( $datar_len % 9 ) != 2 ) {
        if ( $datar_len > 3 && !$datar[3] eq '' && isdigit( $datar[3] ) ) {

          # try to skip over that error and send back right response == saved instead of stucking here for ever
          error( "$peer_address: not correct items count: $datar_len, $data : try return ok ($datar[3])" . __FILE__ . ":" . __LINE__ );
          return $datar[3];
        }
        else {
          error( "$peer_address: not correct items count: $datar_len, $data :" . __FILE__ . ":" . __LINE__ );
          return 0;
        }
      }
    }
    else {
      if ( $datar_len > 3 && !$datar[3] eq '' && isdigit( $datar[3] ) ) {

        # try to skip over that error and send back right response == saved instead of stucking here for ever
        error( "$peer_address: not correct items count: $datar_len, $data : try return ok ($datar[3])" . __FILE__ . ":" . __LINE__ );
        return $datar[3];
      }
      else {
        error( "$peer_address: not correct items count: $datar_len, $data :" . __FILE__ . ":" . __LINE__ );
        return 0;
      }
    }
  }

  # return (store_data_hmc($data, $last_rec, $protocol_version, $peer_address)) if $datar[10] =~ /H/;  # possible hmc data

  # processing mandatory fieds means:
  # find out lpar name from lpar_id
  # db write time is in $time
  # prepare space proof server and lpar names

  $server  = $datar[0];
  $lpar    = $datar[1];
  $lpar_id = $datar[2];

  # for some trouble with unix time -> convert human time to unix
  # $time    = $datar[3];
  ( $time, undef ) = split( " ", $datar[6] );
  $time = "$datar[4]:$datar[5]:$time";
  $time = str2time($time);
  print_as400_debug("$datar[4]:$datar[5]:$datar[6] -> $time\n") if $DEBUG == 2;
  my $eol_time = $datar[7];    #  there is agent end of live date instead  of CPU in Ghz
  $wpar_name = "none";
  $wpar_id   = 0;

  print_as400_debug("$data\n") if $DEBUG == 2;

  # for EXT NMON there's no rules for Machine Type & Serial number > no test
  # for HMC data and INT NMON strict test for Machine & Serial
  # for INT NMON there are exceptions for standard linux/unix names

  if ( !( ( $datar[10] =~ /N/ ) && ( $datar[9] ne "" ) ) ) {    # not EXT NMON > check HWserial and machine

    if ( ( !defined($server) ) || $server eq '' ) {
      error( "$peer_address: not valid server name: $datar_len, $data :" . __FILE__ . ":" . __LINE__ );
      return $datar[3];
    }
    if ( $server =~ m/NotAvailable$/ ) {

      # OS agent might sometimes report "NotAvailable" as its serial, it is wrong, skip it
      error( "$peer_address: not correct HW serial: $datar_len, $data :" . __FILE__ . ":" . __LINE__ );
      return $datar[3];
    }

    if ( $datar[10] =~ /N/ && ( $server =~ m/^LINUX-RedHat/ || $server =~ m/^UX-Solaris/ ) || $server =~ m/^OS like Linux/ ) {

      # INT NMON
      # it is OK, let it go on
      if ( $server =~ m/^OS like Linux/ ) {
        $server = "Linux";
      }
    }
    else {
      if ( !defined($server) || $server eq '' ) {    #
        error( "$peer_address: server identification is null: $datar_len, $data :" . __FILE__ . ":" . __LINE__ );
        return $datar[3];
      }
      ( my $machinetype, my $hw_serial ) = split( '\*', $server );

      if ( $server =~ m/OS like Linux/ ) {

        # for support Linux OS agents, create fakes
      }
      else {
        if ( !defined($hw_serial) || $hw_serial eq '' ) {    # wrong HW serial
          error( "$peer_address: HW serial is null: $datar_len, $data :" . __FILE__ . ":" . __LINE__ );
          return $datar[3];
        }
        if ( ( length($hw_serial) > 7 ) || ( length($hw_serial) < 6 ) ) {    # old lpar version compatible
          error( "$peer_address: HW serial is longer > 7 or shorter < 6 chars: $datar_len, $data :" . __FILE__ . ":" . __LINE__ );
          return $datar[3];
        }
        if ( ( length($machinetype) > 8 ) || ( length($machinetype) < 8 ) ) {
          error( "$peer_address: Machine Type is longer > 8 or shorter < 8 chars: $datar_len, $data :" . __FILE__ . ":" . __LINE__ );
          return $datar[3];
        }
      }
    }
  }

  # workaround for slash in server name
  my $slash_alias = "∕";    #hexadec 2215 or \342\210\225
  $server =~ s/\//$slash_alias/g;

  if ( ( $datar[10] =~ /N/ ) && ( $datar[9] ne "" ) ) {    # for EXT NMON
    $wrkdir .= "_all";
    $server .= $datar[9];
    if ( !-d "$wrkdir" ) {
      mkdir( "$wrkdir", 0755 ) || error( " Cannot mkdir $wrkdir: $! " . __FILE__ . ":" . __LINE__ ) && return 0;
    }

    #`echo "server=$server--unknown&lpar=$lpar--NMON--&$time" >> "/tmp/ext-nmon-query-$datar[9]"`;

    my $f_query = "/tmp/ext-nmon-query-$datar[9]";
    open( DF_OUT, ">> $f_query" ) || error( "Cannot open for writing $f_query: $!" . __FILE__ . ":" . __LINE__ ) && return 0;
    print DF_OUT "server=$server--unknown&lpar=$lpar--NMON--&$time\n";
    close(DF_OUT);

  }
  else {
    if ( !$datar[8] eq '' ) {
      $wpar_name = $datar[8];
    }
    if ( !$datar[9] eq '' ) {
      $wpar_id = $datar[9];
    }
  }
  $server =~ s/=====double-colon=====/:/g;
  $lpar   =~ s/=====double-colon=====/:/g;

  if ( $server eq '' ) {
    if ( $datar_len > 3 && !$datar[3] eq '' && isdigit( $datar[3] ) ) {

      # try to skip over that error and send back right response == saved instead of stucking here for ever
      error( "server is null: $datar_len, $data : $server : $lpar : $lpar_id : $time : try return ok ($datar[3]) " . __FILE__ . ":" . __LINE__ );
      return $datar[3];
    }
    else {
      error( "server is null: $datar_len, $data : $server : $lpar : $lpar_id : $time " . __FILE__ . ":" . __LINE__ );
      return 0;
    }
  }

  # a bit trick how to find a symlink, there was a bug before 3.70 and agents transfered only 6 chars of serial (instead of 7)
  # in original constructions it is not a problem due to a "*" inside the link and shell usage <>
  my @servers = <$wrkdir/$server>;
  my $found   = 0;
  foreach my $file (@servers) {
    if ( -l "$wrkdir/$server" ) {
      $found = 1;
      last;
    }
  }
  if ( $found == 0 ) {

    # sym link does not exist --> server is either not registered yet or full lpar without the HMC
    my $NOSERVER_SUFFIX = "--unknown";
    my $NOHMC           = "no_hmc";
    if ( !-d "$wrkdir/$server$NOSERVER_SUFFIX" ) {
      mkdir( "$wrkdir/$server$NOSERVER_SUFFIX", 0755 ) || error( " Cannot mkdir $wrkdir/$server: $!" . __FILE__ . ":" . __LINE__ ) && return 0;
      touch("$wrkdir/$server$NOSERVER_SUFFIX");
    }
    if ( !-e "$wrkdir/$server" ) {
      symlink( "$wrkdir/$server$NOSERVER_SUFFIX", "$wrkdir/$server" ) || error( " Cannot ln -s $wrkdir/$server$NOSERVER_SUFFIX $wrkdir/$server: $!" . __FILE__ . ":" . __LINE__ ) && return 0;
      touch("$wrkdir/$server$NOSERVER_SUFFIX");
    }
    if ( !-d "$wrkdir/$server/$NOHMC" ) {
      mkdir( "$wrkdir/$server/$NOHMC", 0755 ) || error( " Cannot mkdir $wrkdir/$server/$NOHMC: $!" . __FILE__ . ":" . __LINE__ ) && return 0;
      touch("$wrkdir/$server/$NOHMC");
    }
    my $ltime = localtime();
    print_it("new server has been found and registered: $server (lpar=$lpar)");

  }

  # find out lpar name from lpar_id if it has not been done yet
  # oit is a primary method to get the lpar name
  if ( !$lpar_id eq '' && isdigit($lpar_id) ) {
    if ( $lpar_id != -1 ) {
      my $lpar_name_id = find_lpar_name( $server, $lpar_id );
      if ( !$lpar_name_id eq '' ) {
        $lpar = $lpar_name_id;    # lpar name from lparstat -i --> it does not have to be actual,
                                  # linux on power does not provide lpar name at all, only hostname
      }
    }
  }

  if ( $lpar eq '' && !$lpar_name eq '' ) {

    # just make sure if lpar-id fails somehow then use transferred $lpar_name
    $lpar = $lpar_name;
  }

  if ( $lpar eq '' ) {
    error( "$peer_address: lpar name has not been found for client: $peer_address , server:$server, lpar_id:$lpar_id" . __FILE__ . ":" . __LINE__ );
    return 0;
  }

  # save SMt info, must be here after lpar name detection, no in AS400
  # save_smt ($cpu_hz,$server,$wrkdir,$lpar);

  $lpar .= "--AS400--";

  #  there is no NMON for AS400

  my $lpar_real = $lpar;
  $lpar_real =~ s/\//&&1/g;

  if ( $wpar_id > 0 ) {    # Attention wpar is coming
                           # trick is: lpar contains both names lpar/wpar
    $wpar_name =~ s/=====double-colon=====/:/g;
    $lpar .= "/$wpar_name";
    my $wpar_real = $wpar_name;
    $wpar_real =~ s/\//&&1/g;
    $lpar_real .= "/$wpar_real";
  }

  my $lpar_space = $lpar_real;
  if ( $lpar_real =~ m/ / ) {
    $lpar_space = "\"" . $lpar_real . "\"";    # it must be here to support space with lpar names
  }
  my $server_space = $server;
  if ( $server =~ m/ / ) {
    $server_space = "\"" . $server . "\"";     # it must be here to support space with server names
  }
  my $rrd_file = "";

  my $lpar_space_orig = $lpar_space;
  my $lpar_real_orig  = $lpar_real;

  #
  # cycle for non-mandatory items
  #

  my $cycle_var = 11;    # is a pointer to data array

  # special procedure is for LST300JOB items
  # The 4 LST300JOB atoms must be always all 4 coming in rank 1-2-3-4
  my %job                = ();                                                                                    # keeps matched items for easy check
                                                                                                                  # original full JOB info, we use actually only 3 values then skip the others to save space
                                                                                                                  # my $job_update_pattern = ":percent_used:thread_count:temp_storage:page_fault:diskIO_total:proctime_total_ms";
  my $job_update_pattern = ":percent_used:diskIO_total:proctime_total_ms";
  my $job_config_pattern = "subsystem_name|user_name|type_subtype|status_aj|function_name_type|proctime_total";
  my $job_update         = "";
  my $job_config         = "";
  my $rrd_lstjob         = "";
  my $job_db_name        = "";
  my $job_step           = "";                                                                                    # enable to create rrd job files with steps 60/300/600 to save file space when there are thousands of jobs during week

  my $asp_config = "||||||";

  # special procedure is for IFCD0100PAR1(and 2) items
  # The 2 IFCD0100PARx atoms must be always 2 coming in rank 1-2
  # not interested in *LOOPBACK
  my %ifc                = ();                                                                                                                                      # keeps matched items for easy check
  my $ifc_update_pattern = ":total_bytes_recv:total_bytes_sent:total_inbound_packets_discarded:total_outbound_packets_discarded:total_pkts_recv:total_pkts_sent";
  my $ifc_config_pattern = "Status:phys_interface_status Line type:line_type Mac addr:mac_addr";
  my $ifc_update         = "";
  my $ifc_config         = "";
  my $rrd_ifc            = "";
  my $ifc_db_name        = "";

  # special procedure is for ASPParm7
  my $disk_update_pattern = ":proc_busy:total_requests_data_transfer";
  my $disk_config_pattern = "asp_num";
  my $disk_update         = "";
  my $disk_config         = "";

  while ( $datar[$cycle_var] ) {    # outer cycle - items

    my $processed = 0;              # do not update if not prepared
    my $control;
    my @ctr_arr       = ();
    my $update_values = "";
    my $skip_result   = 0;          # do not update when non-zero, this is not error, used for LST300JOB and skipping some non-interesting items
    my $db_name_ex;

    # clear info from previous items
    my $lpar_space = $lpar_space_orig;
    my $lpar_real  = $lpar_real_orig;

    # inner cycle - 9 parts of every item
    foreach my $i ( 0 .. 8 ) {
      if ( $i == 0 ) {
        if ( $datar[$cycle_var] eq 'lpar' && $wrkdir !~ /_all$/ ) {    # ignore when not external NMON
          $skip_result = 1;
          last;
        }

        # filter for leaving out some items which are not ready (yet) to work with
        if ( $datar[$cycle_var] =~ /ASP\d\d\dParm5/ ) {
          $skip_result = 1;
          last;
        }
        if ( $datar[$cycle_var] =~ /JOBTBLPERM/ ) {
          $skip_result = 1;
          last;
        }
        if ( $datar[$cycle_var] =~ /JOBTBLTEMP/ ) {
          $skip_result = 1;
          last;
        }
        if ( $datar[$cycle_var] =~ /JOBTBLTOT/ ) {
          $skip_result = 1;
          last;
        }
        if ( $datar[$cycle_var] =~ /JOBTBLINUSE/ ) {
          $skip_result = 1;
          last;
        }

        my $db_name = $datar[$cycle_var];    #prepare db name

        # if item is known

        my @match = grep {/^$db_name:/} @dat_tf;
        if ( scalar @match != 1 ) {

          # could be S0400[01-99]Parm[1-5]..., there is only control definition for S040000Parm[1-5]
          if ( $db_name =~ /S0400\d\dParm\d/ ) {

            # prepare pattern for match
            my $db_name_pat = substr( $db_name, 0, 5 ) . "00" . substr( $db_name, 7, 5 );
            my @match1      = grep {/^$db_name_pat/} @dat_tf;
            print_as400_debug("matching SHRPOOL \$db_name $db_name $match1[0]\n") if $DEBUG == 2;
            if ( scalar @match1 != 1 ) {last}
            ;    # not known item
            @match = @match1;
          }

          # could be ASP[001-999]Parm[1-4]..., there is only control definition for ASP000Parm[1-4], Parm1 is only cfg
          elsif ( $db_name =~ /ASP\d\d\dParm\d/ ) {

            # prepare pattern for match
            my $db_name_pat = "ASP000Parm" . substr( $db_name, 10, 1 );
            my @match1      = grep {/^$db_name_pat/} @dat_tf;
            print_as400_debug("matching ASPxxx \$db_name $db_name $match1[0]\n") if $DEBUG == 2;
            if ( scalar @match1 != 1 ) {last}
            ;    # not known item
            @match = @match1;
            if ( !( $lpar_space =~ /\/ASP$/ ) ) {
              $lpar_space .= "/ASP";
              $lpar_real  .= "/ASP";
            }
          }
          else {last}
          ;    # not known item
        }

        $control = $match[0];
        chomp($control);
        print_as400_debug("\$control $control\n") if $DEBUG == 2;
        @ctr_arr = ( split /:/, $control )[ 9, 10, 11, 12, 13, 14, 15, 16, 17 ];

        # specify construction of db name
        # or special name for LSTJOB
        if ( $db_name eq "LST300JOB1" ) {
          $job_update = $job_update_pattern;
          $job_config = $job_config_pattern;
          $job_update =~ s/percent_used/$datar[$cycle_var + 7]/;
          $job_config =~ s/subsystem_name/$datar[$cycle_var + 4]/;
          $job_config =~ s/user_name/$datar[$cycle_var + 5]/;
          $job_config =~ s/type_subtype/$datar[$cycle_var + 6]/;
          $job_config =~ s/status_aj/$datar[$cycle_var + 8]/;
          $db_name = $datar[ $cycle_var + 3 ];
          $db_name .= "\.mmm";
          $db_name_ex = $db_name . "1";

          if ( exists $job{$db_name_ex} ) {
            error( "item $db_name found repeatedly in $data " . __FILE__ . ":" . __LINE__ );
          }
          $job{$db_name_ex} = 0;
          print_as400_debug("3465 \$lpar_space $lpar_space\n") if $DEBUG == 2;
          if ( !( $lpar_space =~ /\/JOB$/ ) ) {
            $lpar_space .= "/JOB";
            $lpar_real  .= "/JOB";
          }
          print_as400_debug("3470 \$lpar_space $lpar_space\n") if $DEBUG == 2;
          $job_db_name = $db_name;    # must remember
          $processed   = 0;
          $skip_result = 1;

          # to get job_step now it is necessary to lookahead to LST300JOB2 cus the rrd file is going to be create
          if ( $datar[ $cycle_var + 9 ] eq "LST300JOB2" ) {
            $job_step = $datar[ $cycle_var + 12 ];
          }
        }
        elsif ( $db_name eq "IFCD0100PAR1" ) {
          $ifc_update = $ifc_update_pattern;
          $ifc_config = $ifc_config_pattern;
          $ifc_config =~ s/phys_interface_status/$datar[$cycle_var + 4]/;
          $ifc_config =~ s/line_type/$datar[$cycle_var + 5]/;
          $ifc_config =~ s/mac_addr/$datar[$cycle_var + 6]/;
          $ifc_update =~ s/total_bytes_recv/$datar[$cycle_var + 7]/;
          $ifc_update =~ s/total_bytes_sent/$datar[$cycle_var + 8]/;
          $db_name = $datar[ $cycle_var + 3 ];
          $db_name .= "\.mmm";
          $db_name_ex = $db_name . "1";

          if ( exists $ifc{$db_name_ex} ) {
            error( "item $db_name found repeatedly in $data " . __FILE__ . ":" . __LINE__ );
          }
          $ifc{$db_name_ex} = 0;
          print_as400_debug("3720 \$lpar_space $lpar_space\n") if $DEBUG == 2;
          if ( !( $lpar_space =~ /\/IFC$/ ) ) {
            $lpar_space .= "/IFC";
            $lpar_real  .= "/IFC";
          }
          print_as400_debug("3725 \$lpar_space $lpar_space\n") if $DEBUG == 2;
          $ifc_db_name = $db_name;                  # must remember
          $processed   = 0;
          $skip_result = 1;
          if ( $ifc_db_name =~ /^\*LOOPBACK/ ) {    # ignore
            last;
          }
        }
        elsif ( $db_name eq "ASPParm7" ) {
          $disk_update = $disk_update_pattern;
          $disk_config = $disk_config_pattern;
          $disk_config =~ s/asp_num/$datar[$cycle_var + 3]/;
          $disk_update =~ s/proc_busy/$datar[$cycle_var + 5]/;
          my $total_requests = $datar[ $cycle_var + 6 ] + $datar[ $cycle_var + 7 ];
          $disk_update =~ s/total_requests_data_transfer/$total_requests/;
          $update_values = $disk_update;
          $db_name       = $datar[ $cycle_var + 4 ];
          $db_name .= "\.mmc";

          if ( !( $lpar_space =~ /\/DSK/ ) ) {
            $lpar_space .= "/DSK";
            $lpar_real  .= "/DSK";
          }
          print_as400_debug("3760 DSK update $disk_update\n") if $DEBUG == 2;
        }
        elsif ( $db_name eq "LTCParm1" ) {
          $db_name = "LTC" . $datar[ $cycle_var + 3 ] . "Parm1";
          $db_name .= "\.mmc";

          if ( !( $lpar_space =~ /\/LTC/ ) ) {
            $lpar_space .= "/LTC";
            $lpar_real  .= "/LTC";
          }
          print_as400_debug("5231 LTC db file name $db_name\n") if $DEBUG == 2;
        }
        else {
          # $db_name = $ctr_arr[0] if $db_name ne $ctr_arr[0];
          $db_name .= "\.mmm";
        }

        # testing LSTJOB possibility
        if ( $db_name eq "LST300JOB2.mmm" ) {
          $db_name    = $job_db_name;
          $db_name_ex = $db_name . "2";
          $job_step   = $datar[ $cycle_var + 3 ];
          $job_update =~ s/thread_count/$datar[$cycle_var + 4]/;
          $job_update =~ s/temp_storage/$datar[$cycle_var + 6]/;
          $job_config =~ s/function_name_type/$datar[$cycle_var + 5]/;
          $skip_result = 1;
          if ( exists $job{$db_name_ex} ) {
            error( "item $db_name found repeatedly in $data " . __FILE__ . ":" . __LINE__ );
          }
          $job{$db_name_ex} = 0;
          $processed        = 0;
          $skip_result      = 1;
          last;
        }
        if ( $db_name eq "LST300JOB3.mmm" ) {
          $db_name    = $job_db_name;
          $db_name_ex = $db_name . "3";
          $job_config =~ s/proctime_total/$datar[$cycle_var + 4]/;
          my $proctime_total_ms = 0;
          ( my $hours, my $mins, my $secs ) = split( /\./, $datar[ $cycle_var + 4 ], 3 );
          my $milis = ( $secs + ( $mins * 60 ) + ( $hours * 3600 ) ) * 1000;
          print_as400_debug("$datar[$cycle_var + 4] $hours $mins $secs $milis\n") if $DEBUG == 2;
          $job_update =~ s/proctime_total_ms/$milis/;
          $job_update =~ s/page_fault/$datar[$cycle_var + 8]/;
          $skip_result = 1;

          if ( exists $job{$db_name_ex} ) {
            error( "item $db_name found repeatedly in $data " . __FILE__ . ":" . __LINE__ );
          }
          $job{$db_name_ex} = 0;
          $processed        = 0;
          $skip_result      = 1;
          last;
        }
        if ( $db_name eq "LST300JOB4.mmm" ) {
          $db_name    = $job_db_name;
          $db_name_ex = $db_name . "4";
          $job_update =~ s/diskIO_total/$datar[$cycle_var + 4]/;
          $skip_result   = 0;              # go for update
          $rrd_file      = $rrd_lstjob;    # proper rrd file name
          $update_values = $job_update;
          if ( exists $job{$db_name_ex} ) {
            error( "item $db_name found repeatedly in $data " . __FILE__ . ":" . __LINE__ );
          }
          $job{$db_name_ex} = 0;
          if ( scalar( keys %job ) != 4 ) {
            error( "there are not all 4 JOB items in $data " . __FILE__ . ":" . __LINE__ );
            $processed++;
          }
          else {
            print_as400_debug("write_lansancfg $rrd_lstjob, $job_config, $time\n") if $DEBUG == 2;
            write_lansancfg( $rrd_lstjob, $job_config, $time, "1" );    # force saving
            $processed++;
          }
          %job = ();                                                    # new start
          print_as400_debug("3535 ,$job_update, ,$job_config, ,$rrd_lstjob, \$processed ,$processed,\n") if $DEBUG == 2;
          last;
        }

        # testing IFC possibility
        if ( $db_name eq "IFCD0100PAR2.mmm" ) {
          if ( $ifc_db_name =~ /^\*LOOPBACK/ ) {                        # ignore
            $skip_result = 1;
            %ifc         = ();                                          # new start
            last;
          }

          # see following definition above
          # my $ifc_update_pattern = ":total_bytes_recv:total_bytes_sent:total_inbound_packets_discarded:total_outbound_packets_discarded:total_pkts_recv:total_pkts_sent";
          $db_name    = $ifc_db_name;
          $db_name_ex = $db_name . "2";
          $ifc_update =~ s/total_inbound_packets_discarded/$datar[$cycle_var + 5]/;
          $ifc_update =~ s/total_outbound_packets_discarded/$datar[$cycle_var + 8]/;
          my $pkts_recv = $datar[ $cycle_var + 3 ] + $datar[ $cycle_var + 4 ];
          my $pkts_sent = $datar[ $cycle_var + 6 ] + $datar[ $cycle_var + 7 ];
          $ifc_update =~ s/total_pkts_recv/$pkts_recv/;
          $ifc_update =~ s/total_pkts_sent/$pkts_sent/;
          $skip_result   = 0;             # go for update
          $rrd_file      = $rrd_ifc;      # proper rrd file name
          $update_values = $ifc_update;

          if ( exists $ifc{$db_name_ex} ) {
            error( "item $db_name found repeatedly in $data " . __FILE__ . ":" . __LINE__ );
          }
          $ifc{$db_name_ex} = 0;
          if ( scalar( keys %ifc ) != 2 ) {
            error( "there are not all 2 IFC items in $data " . __FILE__ . ":" . __LINE__ );
            $processed++;
          }
          else {
            print_as400_debug("write_lansancfg $rrd_ifc, $ifc_config, $time\n") if $DEBUG == 2;
            write_lansancfg( $rrd_ifc, $ifc_config, $time, "1" );    # force saving
            $processed++;
          }
          %ifc = ();                                                 # new start
          print_as400_debug("3916 ,$ifc_update, ,$ifc_config, ,$rrd_ifc, \$processed ,$processed,\n") if $DEBUG == 2;
          last;
        }

        my $db_name_space = $db_name;
        if ( $lpar_space =~ /\/JOB$/ || $lpar_space =~ /\/ASP$/ || $lpar_space =~ /\/IFC$/ || $lpar_space =~ /\/DSK$/ || $lpar_space =~ /\/LTC$/ ) {
          $db_name_space =~ s/mmm$/mmc/;
        }
        $db_name_space =~ s/ /\\ /g;    #it should not be, just for sure, can be in AS400

        $rrd_file = "";
        my @files = <$wrkdir/$server_space/*/$lpar_space/$db_name_space>;
        foreach my $rrd_file_tmp (@files) {
          chomp($rrd_file_tmp);
          $rrd_file = $rrd_file_tmp;
          last;
        }
        print_as400_debug("$act_time: Updating 0     : name is $db_name rrd is $rrd_file\n") if $DEBUG == 2;
        if ( !$rrd_file eq '' ) {
          my $filesize = -s "$rrd_file";
          if ( $filesize == 0 ) {

            # when a FS is full then it creates 0 Bytes rrdtool files what is a problem, delete it then
            error( "0 size rrd file: $rrd_file  - delete it" . __FILE__ . ":" . __LINE__ );
            unlink("$rrd_file") || error( "Cannot rm $rrd_file : $!" . __FILE__ . ":" . __LINE__ );
            $rrd_file = "";    # force to create a new one
          }
        }

        if ( $rrd_file eq '' ) {
          my $db_name_cr = $db_name;
          if ( $lpar_space =~ /\/JOB$/ || $lpar_space =~ /\/ASP$/ || $lpar_space =~ /\/IFC$/ || $lpar_space =~ /\/DSK$/ || $lpar_space =~ /\/LTC$/ ) {
            $db_name_cr =~ s/mmm$/mmc/;
          }

          my $ret2 = create5_rrd( $server, $lpar_real, $time, $server_space, $lpar_space, $db_name_cr, $datar[10], $datar[8], \@ctr_arr, $job_step );
          if ( $ret2 == 2 ) {
            return $datar[3];    # when en error in create2_rrd but continue (2) to skip it then go here
          }
          if ( $ret2 == 0 ) {
            return $ret2;
          }
          @files = <$wrkdir/$server_space/*/$lpar_space/$db_name_space>;
          foreach my $rrd_file_tmp (@files) {
            chomp($rrd_file_tmp);
            $rrd_file = $rrd_file_tmp;
            last;
          }
        }
        print_as400_debug("$act_time: Updating 1     : $server_space:$lpar_space - $rrd_file - last_rec: $last_rec\n") if $DEBUG == 2;
        if ( $last_rec == 0 ) {

          # construction against crashing daemon Perl code when RRDTool error appears
          # this does not work well in old RRDTOool: $RRDp::error_mode = 'catch';
          # construction is not too costly as it runs once per each load
          eval {
            RRDp::cmd qq(last "$rrd_file" );
            my $last_rec_rrd = RRDp::read;
            chomp($$last_rec_rrd);
            $last_rec = $$last_rec_rrd;
          };
          if ($@) {
            rrd_error( $@ . __FILE__ . ":" . __LINE__, $rrd_file );
            return 0;
          }
        }

        print_as400_debug("$act_time: Updating 2     : $server_space:$lpar_space - $rrd_file - last_rec: $last_rec\n") if $DEBUG == 2;
        my $step_info = $STEP;

        # find rrd database file step
        # print STDERR "find file step for \$rrd_file $rrd_file\n";
        RRDp::cmd qq("info" "$rrd_file");
        my $answer_info = RRDp::read;
        if ( $$answer_info =~ "ERROR" ) {
          error("Rrdtool error : $$answer_info");
        }
        else {
          my ($step_from_rrd) = $$answer_info =~ m/step = (\d+)/;
          if ( $step_from_rrd > 0 ) {
            $step_info = $step_from_rrd;
          }
        }

        if ( ( $last_rec + $step_info / 2 ) >= $time ) {

          #error("$server:$lpar : last rec : $last_rec + $STEP/2 >= $time, ignoring it ...".__FILE__.":".__LINE__);
          print_as400_debug("$act_time: Updating 3     : $last_rec : $time : $rrd_file : $step_info\n") if $DEBUG == 2;
          return $datar[3];    # returns original time, not last_rec
                               # --> no, no, it is not wrong, just ignore it!
        }
        print_as400_debug("$act_time: Updating 4     : $server_space:$lpar_space - $rrd_file - last_rec: $last_rec\n") if $DEBUG == 2;

        # remember the rrd name for later update
        if ( $datar[$cycle_var] eq "LST300JOB1" ) {
          $rrd_lstjob = $rrd_file;
          print_as400_debug("3623 \$rrd_lstjob $rrd_lstjob\n") if $DEBUG == 2;
          $skip_result = 1;
          last;
        }
        if ( $datar[$cycle_var] eq "IFCD0100PAR1" ) {
          $rrd_ifc = $rrd_file;
          print_as400_debug("3916 \$rrd_ifc $rrd_ifc\n") if $DEBUG == 2;
          $skip_result = 1;
          last;
        }
        if ( $datar[$cycle_var] eq "ASPParm7" ) {
          print_as400_debug("3957 \$rrd_file $rrd_file\n") if $DEBUG == 2;
          write_lansancfg( $rrd_file, $disk_config, $time, "1" );    # force saving
          $skip_result = 0;
          $processed++;
          last;
        }

        if ( $datar[$cycle_var] =~ /S0400\d\dParm1/ ) {              # on Parm1 save shrpool cfg
          my $shrpool_config      = $datar[ $cycle_var + 4 ] . " " . $datar[ $cycle_var + 7 ] . " " . $datar[ $cycle_var + 8 ];
          my $shrpool_config_file = $rrd_file;
          $shrpool_config_file =~ s/Parm1/Parm/g;
          print_as400_debug("cfg SHRPOOL \$shrpool_config $shrpool_config \$shrpool_config_file $shrpool_config_file\n") if $DEBUG == 2;
          write_lansancfg( $shrpool_config_file, $shrpool_config, $time, "1" );    # force saving
        }
        if ( $datar[$cycle_var] =~ /ASP\d\d\dParm1/ ) {                            # on Parm1 prepare ASP cfg, <<< not finito !!!! >>> to be added info from Parm2 with system ASP info
          $asp_config = "";
          if ( defined( $datar[ $cycle_var + 3 ] ) && !$datar[ $cycle_var + 3 ] eq '' && $datar[ $cycle_var + 3 ] !~ m/not known/ && $datar[ $cycle_var + 3 ] !~ m/no status/ ) {
            $asp_config .= "Res name: $datar[$cycle_var+3],";
          }
          if ( defined( $datar[ $cycle_var + 4 ] ) && !$datar[ $cycle_var + 4 ] eq '' && $datar[ $cycle_var + 4 ] !~ m/not known/ && $datar[ $cycle_var + 4 ] !~ m/no status/ ) {
            $asp_config .= "Dev name: $datar[$cycle_var+4],";
          }
          if ( defined( $datar[ $cycle_var + 5 ] ) && !$datar[ $cycle_var + 5 ] eq '' && $datar[ $cycle_var + 5 ] !~ m/not known/ && $datar[ $cycle_var + 5 ] !~ m/no status/ ) {
            $asp_config .= "Usage: $datar[$cycle_var+5],";
          }
          if ( defined( $datar[ $cycle_var + 6 ] ) && !$datar[ $cycle_var + 6 ] eq '' && $datar[ $cycle_var + 6 ] !~ m/not known/ && $datar[ $cycle_var + 6 ] !~ m/no status/ ) {
            $asp_config .= "Status: $datar[$cycle_var+6],";
          }
          if ( defined( $datar[ $cycle_var + 7 ] ) && !$datar[ $cycle_var + 7 ] eq '' && $datar[ $cycle_var + 7 ] !~ m/not known/ && $datar[ $cycle_var + 7 ] !~ m/no status/ ) {
            $asp_config .= "DB name: $datar[$cycle_var+7],";
          }
          if ( defined( $datar[ $cycle_var + 8 ] ) && !$datar[ $cycle_var + 8 ] eq '' && $datar[ $cycle_var + 8 ] !~ m/not known/ && $datar[ $cycle_var + 8 ] !~ m/no status/ ) {
            $asp_config .= "Primary res name: $datar[$cycle_var+8]";
          }
          my $asp_config_file = $rrd_file;
          $asp_config_file =~ s/Parm1/Parm/g;
          print_as400_debug("cfg ASP \$asp_config $asp_config \$asp_config_file $asp_config_file\n") if $DEBUG == 2;
          write_lansancfg( $asp_config_file, $asp_config, $time, "1" );    # force saving
        }

        #        if ($datar[$cycle_var] =~ /ASP\d\d\dParm2/) { # on Parm save ASP cfg with system ASP info
        #          $asp_config .= "|".$datar[$cycle_var+8];
        #          my $asp_config_file = $rrd_file;
        #          $asp_config_file =~ s/Parm2/Parm/g;
        #          print_as400_debug ("cfg ASP \$asp_config $asp_config \$asp_config_file $asp_config_file\n") if $DEBUG == 2;
        #          write_lansancfg ($asp_config_file, $asp_config, $time, "1"); # force saving
        #          $asp_config = "||||||"; # clear it
        #        }
      }

      if ( $i == 1 ) {
        if ( $ctr_arr[$i] eq "" ) {

          # do nothing
        }
      }

      if ( $i == 2 ) {
        if ( $ctr_arr[$i] eq "" ) {

          # do nothing
        }
      }
      if ( $i > 2 ) {
        next if !defined $ctr_arr[$i];
        if ( index( $ctr_arr[$i], "number" ) == 0 ) {
          if ( isdigit( $datar[ $cycle_var + $i ] ) ) {
            $update_values .= ":$datar[$cycle_var+$i]";
            $processed++;
          }
          else {
            $processed = 0;
          }
        }
        elsif ( index( $ctr_arr[$i], "str_3" ) == 0 ) {

          # there are  exactly 3 possibilities like *FIXED, *SAME ane *CALC
          ( undef, my $pos1_str, my $pos1_val, my $pos2_str, my $pos2_val, my $pos3_str, my $pos3_val ) = split( /,/, $ctr_arr[$i] );
          if ( $datar[ $cycle_var + $i ] eq $pos1_str ) {
            $update_values .= ":$pos1_val";
            $processed++;
          }
          elsif ( $datar[ $cycle_var + $i ] eq $pos2_str ) {
            $update_values .= ":$pos2_val";
            $processed++;
          }
          elsif ( $datar[ $cycle_var + $i ] eq $pos3_str ) {
            $update_values .= ":$pos3_val";
            $processed++;
          }
          else {
            error( "Unknown control or data values in sub store_data_50 : $ctr_arr[$i],$datar[$cycle_var+$i] " . __FILE__ . ":" . __LINE__ );
            $processed = 0;
          }
        }
        elsif ( index( $ctr_arr[$i], "str_2" ) == 0 ) {

          # there are  exactly 2 possibilities like ON and OFF
          ( undef, my $pos1_str, my $pos1_val, my $pos2_str, my $pos2_val ) = split( /,/, $ctr_arr[$i] );
          if ( $datar[ $cycle_var + $i ] eq $pos1_str ) {
            $update_values .= ":$pos1_val";
            $processed++;
          }
          elsif ( $datar[ $cycle_var + $i ] eq $pos2_str ) {
            $update_values .= ":$pos2_val";
            $processed++;
          }
          else {
            error( "Unknown control or data values in sub store_data_50 : $ctr_arr[$i],$datar[$cycle_var+$i] " . __FILE__ . ":" . __LINE__ );
            $processed = 0;
          }
        }
        elsif ( index( $ctr_arr[$i], "str_1_all" ) == 0 ) {

          # there are 2 possibilities like ONE and all others
          ( undef, my $pos1_str, my $pos1_val, my $pos2_val ) = split( /,/, $ctr_arr[$i] );
          if ( $datar[ $cycle_var + $i ] eq $pos1_str ) {
            $update_values .= ":$pos1_val";
            $processed++;
          }
          else {
            $update_values .= ":$pos2_val";
            $processed++;
          }
        }
        elsif ( index( $ctr_arr[$i], $ignore ) == 0 ) {
          $update_values .= ":U";
          $processed++;
        }
        else {
          error( "Unknown control string in sub store_data_50 : $ctr_arr[$i] " . __FILE__ . ":" . __LINE__ );
          $processed = 0;
        }
      }
    }    # inner cycle end

    my $answer     = "";
    my $update_ret = 1;

    if ( !$skip_result ) {

      if ( $processed == 0 && $error_first == 0 ) {
        print "Unprocessed data from agent : $server:$lpar : $datar[$cycle_var]:$datar[$cycle_var+1]:$datar[$cycle_var+2]:$datar[$cycle_var+3]:$datar[$cycle_var+4]:$datar[$cycle_var+5]:$datar[$cycle_var+6]:$datar[$cycle_var+7]:$datar[$cycle_var+8], only first error occurence is reported ";
        error( "Unprocessed data from agent : $server:$lpar : $datar[$cycle_var]:$datar[$cycle_var+1]:$datar[$cycle_var+2]:$datar[$cycle_var+3]:$datar[$cycle_var+4]:$datar[$cycle_var+5]:$datar[$cycle_var+6]:$datar[$cycle_var+7]:$datar[$cycle_var+8], only first error occurence is reported ) " . __FILE__ . ":" . __LINE__ );
        $error_first = 1;
      }
      print_as400_debug("000 : $datar[$cycle_var] $cycle_var : $time:$datar[$cycle_var+3]:$datar[$cycle_var+4]:$datar[$cycle_var+5]:$datar[$cycle_var+6]:$datar[$cycle_var+7]:$datar[$cycle_var+8] \n") if $DEBUG == 2;
      print_as400_debug("updating data:$time$update_values\n")                                                                                                                                          if $DEBUG == 2;

      if ( $processed != 0 ) {
        if ( !exists $first_update{ $datar[$cycle_var] } ) {

          # first insert through eval to be able to catch whatever error, next inserts with issues a new shell (eval)
          $first_update{ $datar[$cycle_var] } = 1;
          eval {
            $update_ret = rrd_update( "$rrd_file", "$time$update_values" );
            if ( $rrdcached == 0 ) { $answer = RRDp::read; }
          };
          if ( $update_ret == 0 || $@ ) {

            # error happened, zero the first to continue with eval
            delete $first_update{ $datar[$cycle_var] };
            if ( $error_first == 0 ) {
              error( " updating $server:$lpar : $rrd_file : update_ret=$update_ret : $@ " . __FILE__ . ":" . __LINE__ );    # print it only first time
            }
            $processed = 0;
          }
        }
        else {
          $update_ret = rrd_update( "$rrd_file", "$time$update_values" );
          if ( $rrdcached == 0 ) { $answer = RRDp::read; }
        }
      }

      if ( $processed != 0 && $rrdcached == 0 && !$$answer eq '' && $$answer =~ m/ERROR/ ) {
        error( " updating $server:$lpar : $rrd_file : $$answer" . __FILE__ . ":" . __LINE__ );
        if ( $$answer =~ m/is not an RRD file/ ) {
          ( my $err, my $file, my $txt ) = split( /'/, $$answer );
          error( "Removing as it seems to be corrupted: $file" . __FILE__ . ":" . __LINE__ );
          unlink("$file") || error( "Cannot rm $file : $!" . __FILE__ . ":" . __LINE__ );
        }

        # continue here although some error apeared just to do not stuck here for ever
      }
    }

    # prepare next cycle - always skips 9 atoms
    $cycle_var = $cycle_var + 9;
  }    # outer cycle end

  # write license time
  if ( $eol_time ne "" ) {
    $rrd_file =~ s/--AS400--.*/--AS400--\/license.cfg/;
    write_lansancfg( $rrd_file, $eol_time, $time, "1" );    # force saving
    print_as400_debug("4140 license written to: ,$rrd_file, $eol_time, $time,\n") if $DEBUG == 2;
  }

  # since 4.70 there is agent version in human date item - $datar[6], need to save it to agent.ver
  my $item_to_write = $datar[6];
  if ( $datar[6] !~ /version/ ) {
    $item_to_write .= " version <1.0";
  }
  else {
    $item_to_write =~ s/.*ersion//;
  }
  $rrd_file =~ s/--AS400--.*/--AS400--\/agent.cfg/;
  write_lansancfg( $rrd_file, $item_to_write, $time, 1 );
  print_as400_debug("3833 agent version written to: ,$rrd_file, $item_to_write, $time,\n") if $DEBUG == 2;

  print_as400_debug("3825 ,$job_update, ,$job_config, ,$rrd_lstjob,\n") if $DEBUG == 2;

  print "4167 finish storing data from agent $time\n" if $DEBUG == 2;
  return $datar[3];    # return time of last record
}

sub create5_rrd {
  my $server        = shift;
  my $lpar          = shift;
  my $time          = shift;
  my $server_space  = shift;
  my $lpar_space    = shift;
  my $db_name       = shift;
  my $ONH_mode      = shift;
  my $nmon_interval = shift;

  # info from ctrl string as array
  my $ctrl_ref = shift;
  my $job_step = shift;

  # 20 minutes heartbeat for non NMON says the time interval when RRDTOOL considers a gap in input data
  my $no_time = 20 * 60;    # 20 minutes heartbeat for non NMON

  # special length for AS400 - 60 mins > 1 hour
  $no_time = $no_time * 3;

  my $step_for_create = $STEP;

  # try to get step from $job_step in format 'min.sec.mil' ex. 01.056 or 00.19.581
  if ( defined $job_step ) {
    ( my $mins, my $secs, undef ) = split( '\.', $job_step );
    if ( isdigit($mins) ) {
      my $step_secs = $mins * 60;
      if ( isdigit($secs) ) {
        $step_secs = $step_secs + $secs;
      }
      if ( ( $step_secs + 10 ) > 400 ) {
        $step_for_create = 600;
      }
      elsif ( $step_secs + 10 > 200 ) {
        $step_for_create = 300;
      }
    }
  }

  my $ds_mode = "GAUGE";

  # from ext nmon we have seen step from 2 - 1800 seconds
  if ( $ONH_mode =~ /N/ ) {    # for NMON both intern and extern
    $ds_mode         = "GAUGE";
    $step_for_create = $nmon_interval;
    $no_time         = $step_for_create * 7;    # says the time interval when RRDTOOL considers a gap in input data

    if ( $no_time < 20 * 60 ) { $no_time = 20 * 60 }
    ;                                           #should be enough
  }

  $time = $time - $step_for_create;             # start time lower than actual one being updated

  my $act_time = localtime();
  my $found    = 0;
  my $rrd_dir  = "";

  print_as400_debug("creating (5) $db_name with step $step_for_create\n") if $DEBUG == 2;
  my @files = <$wrkdir/$server_space/*>;
  foreach my $rrd_dir_tmp (@files) {
    chomp($rrd_dir_tmp);
    if ( -d $rrd_dir_tmp ) {
      $found   = 1;
      $rrd_dir = $rrd_dir_tmp;
      last;
    }
  }

  if ( $found == 0 ) {
    error( "Could not found a HMC in (5) : $wrkdir/$server" . __FILE__ . ":" . __LINE__ ) && return 0;
  }
  if ( !-d "$rrd_dir/$lpar/" ) {
    print_it("mkdir          : $rrd_dir/$lpar/") if $DEBUG;
    makex_path("$rrd_dir/$lpar/") || error( "Cannot mkdir $rrd_dir/$lpar/: $!" . __FILE__ . ":" . __LINE__ ) && return 0;
    touch("$rrd_dir/$lpar/");
  }

  my $rrd = "$rrd_dir/$lpar/$db_name";
  print_as400_debug("$act_time: RRD create (5) : $rrd\n") if $DEBUG == 2;

  # prepare DS string
  my $ds_str = "";
  foreach my $i ( 3 .. 8 ) {
    next if !defined $ctrl_ref->[$i];
    next if $$ctrl_ref[$i] eq "";

    # for JOB save only 3 values so far to save space --PH : :percent_used:diskIO_total:proctime_total_ms, --> 3,7,8
    if ( $lpar_space =~ /\/JOB$/ ) {
      if ( $i > 3 && $i < 7 ) {
        next;
      }
    }

    print_as400_debug("3860 daemon $ctrl_ref->[$i].\n") if $DEBUG == 2;

    ( undef, my $min, my $max, my $ds_mode_ext ) = split( /\|/, $ctrl_ref->[$i] );

    # if ds_mode is explicit
    if ( defined $ds_mode_ext && $ds_mode_ext ne "" ) {
      $ds_mode = $ds_mode_ext;
    }
    $ds_str .= "DS:par$i:$ds_mode:$no_time:$min:$max\n";
  }
  print_as400_debug("DS string (5) : $ds_str\n") if $DEBUG == 2;

  if ( $lpar_space =~ /\/JOB$/ || $lpar_space =~ /\/DSK$/ ) {

    # for JOB files there is only one minute archiv for 8 days
    my $days = 8;
    if ( defined $ENV{CUSTOMER} && $ENV{CUSTOMER} eq "PPF" ) {
      $time = $time - 400000;
      $days = 30;
    }

    # suffix of JOB cpu file is mmc
    $rrd =~ s/mmm$/mmc/;
    $one_minute_sample = 24 * 60 * $days;
    if ( $step_for_create == 300 ) {
      $one_minute_sample = 24 * 12 * $days;
    }
    if ( $step_for_create == 600 ) {
      $one_minute_sample = 24 * 6 * $days;
    }
    RRDp::cmd qq(create "$rrd"  --start "$time"  --step "$step_for_create"
      $ds_str
      "RRA:AVERAGE:0.5:1:$one_minute_sample"
    );
  }
  else {
    RRDp::cmd qq(create "$rrd"  --start "$time"  --step "$step_for_create"
      $ds_str
      "RRA:AVERAGE:0.5:1:$one_minute_sample"
      "RRA:AVERAGE:0.5:5:$five_mins_sample"
      "RRA:AVERAGE:0.5:60:$one_hour_sample"
      "RRA:AVERAGE:0.5:300:$five_hours_sample"
      "RRA:AVERAGE:0.5:1440:$one_day_sample"
    );
  }

  if ( !Xorux_lib::create_check("file: $rrd, $one_minute_sample, $five_mins_sample, $one_hour_sample, $five_hours_sample, $one_day_sample") ) {
    error( "unable to create $rrd : at " . __FILE__ . ": line " . __LINE__ );
    RRDp::end;
    RRDp::start "$rrdtool";
    return 0;
  }

  # create lpar directory and file hard link into the other HMC if there is dual HMC setup
  my $rrd_dir_base = basename($rrd_dir);
  foreach my $rrd_dir_new (@files) {
    chomp($rrd_dir_new);
    my $rrd_dir_new_base = basename($rrd_dir_new);
    if ( -d $rrd_dir_new && $rrd_dir_new_base !~ m/^$rrd_dir_base$/ ) {
      if ( !-d "$rrd_dir_new/$lpar/" ) {
        print_it("mkdir dual     : $rrd_dir_new/$lpar/") if $DEBUG;
        makex_path("$rrd_dir_new/$lpar/") || error( "Cannot mkdir $rrd_dir_new/$lpar/: $!" . __FILE__ . ":" . __LINE__ ) && return 0;
        touch("$rrd_dir_new/$lpar/");
      }
      print_it("hard link      : $rrd --> $rrd_dir_new/$lpar/$db_name") if $DEBUG;
      my $rrd_link_new = "$rrd_dir_new/$lpar/$db_name";
      unlink("$rrd_dir_new/$lpar/$db_name");    # for sure
      link( $rrd, "$rrd_dir_new/$lpar/$db_name" ) || error( "Cannot link $rrd:$rrd_dir_new/$lpar/$db_name : $!" . __FILE__ . ":" . __LINE__ ) && return 0;

      # same for .cfg files
      my $rrd_cfg = $rrd;
      $rrd_cfg =~ s/mmm$/cfg/;
      $rrd_cfg =~ s/mmc$/cfg/;                  # as400 JOB files
      $rrd_cfg =~ s/Parm\d.cfg$/Parm.cfg/;      # as400 ASP files
      my $db_name_cfg = $db_name;
      $db_name_cfg =~ s/mmm$/cfg/;
      $db_name_cfg =~ s/mmc$/cfg/;

      if ( ( $db_name =~ m/^lan-/ || $db_name =~ m/^san-/ || $db_name =~ m/^sea-/ || $lpar_space =~ /\/JOB$/ || $lpar_space =~ /\/ASP$/ || $lpar_space =~ /\/IFC$/ || $lpar_space =~ /\/DSK$/ ) && -f $rrd_cfg && !-f "$rrd_dir_new/$lpar/$db_name_cfg" ) {
        `touch "$rrd_cfg"`;
        link( $rrd_cfg, "$rrd_dir_new/$lpar/$db_name_cfg" ) || error( "Cannot link $rrd_cfg:$rrd_dir_new/$lpar/$db_name_cfg : $!" . __FILE__ . ":" . __LINE__ ) && return 0;
      }
    }
  }
  return 1;
}

sub catch_sig {
  RRDp::end;    # just to be sure, ignore if any error in logs/error.log-daemon, it hapens whendaemon goes down
  $socket->close();
  waitpid( -1, WNOHANG );
  error "Exiting on $!\n";
  exit(1);
}

sub rrd_update {
  my $rrd_file = shift;
  my $data     = shift;

  if ( $rrdcached == 1 ) {
    $cache->RRD_update( "$rrd_file", "$data" ) or return 0;
  }
  else {
    RRDp::cmd qq(update "$rrd_file" "$data");
  }

  return 1;
}

sub alert {
  my $server       = shift;
  my $lpar         = shift;
  my $type         = shift;
  my $check_nmon   = shift;
  my $peer_address = shift;
  my $protocol     = shift;

  ### for testing
  #$server = "8231-E2B*064875R";
  #$lpar = "aix3";
  #$type = "LPAR";
  #$check_nmon = "";
  #$peer_address = "192.168.1.1.";
  #$protocol = "30";
  ###

  return if $protocol == 63;    # nothing now

  my $lpar_path   = "";
  my $lpar_name   = "";
  my $lpar_hmc    = "";
  my $server_name = "";

  my $file = "$basedir/etc/web_config/alerting.cfg";

  #if (! -f $file){
  #  $file = "$basedir/etc/alert.cfg";
  #}
  if ( !-f $file ) {

    #error ("Does not exist $file $!".__FILE__.":".__LINE__);
    return 0;
  }

  my @data = get_array_data($file);

  my $repeat_file      = "$tmpdir/alert_repeat_osagent.tmp";
  my @data_repeat_file = ();
  if ( -f $repeat_file ) {
    @data_repeat_file = get_array_data($repeat_file);
  }

  ### function alert call with parameter server lpar and type not for all rules in etc/alert.cfg
  if ( !defined $server || $server eq "" || !defined $lpar || $lpar eq "" ) {
    error( "Client: $peer_address: server:$server lpar:$lpar : not valid server name or lpar name for alerting: " . __FILE__ . ":" . __LINE__ );
    return;
  }

  # protocol is greater 20 and less 50
  if ( $protocol >= 50 ) { return; }    ### AS400;
  if ( $protocol < 20 ) {
    my $lpar_real = $lpar;
    $lpar_name = $lpar;
    $lpar_real =~ s/\//&&1/g;

    my $rrd_file   = "";
    my $lpar_space = $lpar_real;
    if ( $lpar_real =~ m/ / ) {
      $lpar_space = "\"" . $lpar_real . "\"";    # it must be here to support space with lpar names
    }
    my $server_space = $server;
    if ( $server =~ m/ / ) {
      $server_space = "\"" . $server . "\"";     # it must be here to support space with server names
    }
    my @lpars = <$wrkdir/$server_space/*/$lpar_space>;
    foreach my $lpar_item (@lpars) {
      $lpar_path = $lpar_item;
      my @paths = split( /\//, $lpar_item );
      my $size  = scalar @paths;
      $lpar_hmc = $paths[ $size - 2 ];
      last;
    }
    $server_name = get_name_server_for_alert($server);
    if ( !defined || $server_name eq "" ) { $server_name = $server; }
  }
  elsif ( $protocol >= 20 ) {

    if ( !( ( $type =~ /NMON/ ) && ( $check_nmon ne "" ) ) ) {    # not EXT NMON

      if ( $server =~ m/^SunOS/ || $server =~ m/^LINUX/ || $server =~ m/^UX-Solaris/ || $server =~ m/Linux/ ) {

        # General Linux and Solaris support
        if ( $server =~ m/Linux/ || $server =~ m/LINUX/ ) {
          $server = "Linux";
        }
        if ( $server =~ m/SunOS/ || $server =~ m/Solaris/ || $server =~ m/SOLARIS/ ) {
          $server = "Solaris";
        }
        $server_name = $server;
      }

      ( my $machinetype, my $hw_serial ) = split( '\*', $server );

      if ( $server !~ m/Linux/ && $server !~ m/Solaris/ && $server !~ m/HITACHI/ ) {

        # IBM Power only
        if ( !defined($hw_serial) || $hw_serial eq '' ) {    # wrong HW serial
          error( "$peer_address: HW serial is null: " . __FILE__ . ":" . __LINE__ );
          return;
        }
        if ( ( length($hw_serial) > 7 ) || ( length($hw_serial) < 6 ) ) {    # old lpar version compatible
          error( "$peer_address: HW serial is longer > 7 or shorter < 6 chars: " . __FILE__ . ":" . __LINE__ );
          return;
        }
        if ( ( length($machinetype) > 8 ) || ( length($machinetype) < 8 ) ) {
          error( "$peer_address: Machine Type is longer > 8 or shorter < 8 chars: " . __FILE__ . ":" . __LINE__ );
          return;
        }
        $server_name = get_name_server_for_alert($server);
      }
    }

    # workaround for slash in server name
    my $slash_alias = "∕";    #hexadec 2215 or \342\210\225
    $server =~ s/\//$slash_alias/g;

    $server =~ s/====double-colon=====/:/g;
    $lpar   =~ s/=====double-colon=====/:/g;
    $lpar_name = $lpar;

    if ( $type eq "NMON" ) {
      $lpar .= "--NMON--";
    }

    my $lpar_real = $lpar;
    $lpar_real =~ s/\//&&1/g;

    my $lpar_space = $lpar_real;
    if ( $lpar_real =~ m/ / ) {
      $lpar_space = "\"" . $lpar_real . "\"";    # it must be here to support space with lpar names
    }
    my $server_space = $server;
    if ( $server =~ m/ / ) {
      $server_space = "\"" . $server . "\"";     # it must be here to support space with server names
    }
    $server = $server_space;
    $lpar   = $lpar_space;
    my @lpars = <$wrkdir/$server/*/$lpar>;
    foreach my $lpar_item (@lpars) {
      $lpar_path = $lpar_item;
      my @paths = split( /\//, $lpar_item );
      my $size  = scalar @paths;
      $lpar_hmc = $paths[ $size - 2 ];
      last;
    }
  }
  if ( $lpar_name eq "" ) { return; }
  ###

  ### save data from alert.cfg

  my %groups = ();
  foreach my $line (@data) {
    chomp $line;
    if ( $line eq "" || $line =~ m/^#/ ) { next; }
    $line =~ s/^\s+|\s+$//g;
    if ( $line eq "" || $line =~ m/^#/ ) { next; }
    if ( $line =~ m/^LPAR/ || $line =~ m/^POOL/ ) {
      my $pom_line = $line;
      $pom_line =~ s/\\:/=====doublecoma=====/g;
      ( undef, my $server, my $lpar, my $metric, my $max, my $peek, my $repeat, my $exclude_time, my $email, undef, my $any_name ) = split( ":", $pom_line );
      my $g_key_s = "";
      my $g_key_l = "";
      if ( !defined $server || $server eq "" ) {
        $g_key_s = "nos";
      }
      else {
        $g_key_s = $server;
      }
      if ( !defined $any_name || $any_name eq "" ) {
        $g_key_l = "nol";
      }
      else {
        $g_key_l = $any_name;
      }
      $g_key_s .= $g_key_l;
      $groups{$g_key_s} = 1;

      #print Dumper(\%groups);
      if ( ( scalar keys %groups > ( $one_day_sample / 360 + 0.5 ) ) && ( ( length($log_err_v) + 1 ) == length($log_err) ) ) { last; }
      if ( $line =~ m/^POOL/ )                                                                                               { next; }
      if ( defined $server && $server ne "" ) {
        if ( $server ne $server_name ) { next; }
      }
      if ( ( !defined $lpar || $lpar eq "" ) && ( !defined $server || $server eq "" ) ) {
        push @{ $inventory_alert{DATA} }, "$line";    ### new general rule
        next;
      }
      if ( ( !defined $lpar || $lpar eq "" ) && ( defined $server && $server eq $server_name ) ) {
        push @{ $inventory_alert{DATA} }, "$line";    ### new general rule
        next;
      }
      $lpar =~ s/=====doublecoma=====/:/g;
      if ( $lpar_name eq $lpar ) {
        push @{ $inventory_alert{DATA} }, "$line";
      }
    }
    else {
      push @{ $inventory_alert{INFO} }, "$line";
    }
  }

  ###

  ### set up global info for alerting
  #print Dumper \%inventory_alert;

  foreach my $line ( @{ $inventory_alert{"INFO"} } ) {
    chomp $line;
    $line =~ s/^\s+|\s+$//g;

    if ( $line =~ m/^ALERT_HISTORY=|^PEAK_TIME_DEFAULT=|^REPEAT_DEFAULT=|^EMAIL_GRAPH=|^NAGIOS=|^EXTERN_ALERT=|^TRAP=|^MAILFROM=/ ) {
      ( my $property, my $value ) = split( /=/, $line );
      if ( defined $property && $property ne "" && defined $value && $value ne "" ) {
        $value =~ s/ //g;
        $value =~ s/>//g;
        $value =~ s/#.*$//g;
        $value =~ s/^\s+|\s+$//g;
        $inventory_alert{GLOBAL}{$property} = $value;
        next;
      }
    }

    # EMAIL section
    if ( $line =~ m/^EMAIL:/ ) {
      ( undef, my $email_group, my $emails ) = split( /:/, $line );
      if ( defined $email_group && $email_group ne "" && defined $emails && $emails ne "" ) {
        $inventory_alert{GLOBAL}{EMAIL}{$email_group} = $emails;
      }
    }

    if ( $line =~ m/^COMM_STRING=/ ) {
      my $comm_string_tmp = $line;
      $comm_string_tmp =~ s/^COMM_STRING=//;
      if ( defined $comm_string_tmp && $comm_string_tmp ne '' ) {
        $inventory_alert{GLOBAL}{'COMM_STRING'} = $comm_string_tmp;
      }
    }
    if ( $line =~ m/^WEB_UI_URL=/ ) {
      my $web_ui_url_tmp = $line;
      $web_ui_url_tmp =~ s/^WEB_UI_URL=//;
      if ( defined $web_ui_url_tmp && $web_ui_url_tmp ne '' ) {
        $inventory_alert{GLOBAL}{'WEB_UI_URL'} = $web_ui_url_tmp;
      }
    }

    if ( $line =~ m/^SERVICE_NOW/ ) {
      if ( $line =~ m/^SERVICE_NOW_IP=/ ) {
        $line =~ s/^SERVICE_NOW_IP=//;
        $inventory_alert{"GLOBAL"}{"SERVICE_NOW"}{"IP"} = $line;
      }
      elsif ( $line =~ m/^SERVICE_NOW_USER=/ ) {
        $line =~ s/^SERVICE_NOW_USER=//;
        $inventory_alert{"GLOBAL"}{"SERVICE_NOW"}{"USER"} = $line;
      }
      elsif ( $line =~ m/^SERVICE_NOW_PASSWORD=/ ) {
        $line =~ s/^SERVICE_NOW_PASSWORD=//;
        $inventory_alert{"GLOBAL"}{"SERVICE_NOW"}{"PASSWORD"} = $line;
      }
      elsif ( $line =~ m/^SERVICE_NOW_SEVERITY=/ ) {
        $line =~ s/^SERVICE_NOW_SEVERITY=//;
        $inventory_alert{"GLOBAL"}{"SERVICE_NOW"}{"SEVERITY"} = $line;
      }
      elsif ( $line =~ m/^SERVICE_NOW_TYPE=/ ) {
        $line =~ s/^SERVICE_NOW_TYPE=//;
        $inventory_alert{"GLOBAL"}{"SERVICE_NOW"}{"TYPE"} = $line;
      }
      elsif ( $line =~ m/^SERVICE_NOW_EVENT=/ ) {
        $line =~ s/^SERVICE_NOW_EVENT=//;
        $inventory_alert{"GLOBAL"}{"SERVICE_NOW"}{"EVENT"} = $line;
      }

      #print Dumper $inventory_alert{"GLOBAL"}{"SERVICE_NOW"};
    }
    if ( $line =~ m/^JIRA/ ) {
      if ( $line =~ m/^JIRA_URL=/ ) {
        $line =~ s/^JIRA_URL=//;
        $inventory_alert{"GLOBAL"}{"JIRA_CLOUD"}{"URL"} = $line;
      }
      elsif ( $line =~ m/^JIRA_TOKEN=/ ) {
        $line =~ s/^JIRA_TOKEN=//;
        $inventory_alert{"GLOBAL"}{"JIRA_CLOUD"}{"TOKEN"} = $line;
      }
      elsif ( $line =~ m/^JIRA_USER=/ ) {
        $line =~ s/^JIRA_USER=//;
        $inventory_alert{"GLOBAL"}{"JIRA_CLOUD"}{"USER"} = $line;
      }
      elsif ( $line =~ m/^JIRA_PROJECT_KEY=/ ) {
        $line =~ s/^JIRA_PROJECT_KEY=//;
        $inventory_alert{"GLOBAL"}{"JIRA_CLOUD"}{"PROJECT_KEY"} = $line;
      }
      elsif ( $line =~ m/^JIRA_ISSUE_ID=/ ) {
        $line =~ s/^JIRA_ISSUE_ID=//;
        $inventory_alert{"GLOBAL"}{"JIRA_CLOUD"}{"ISSUE_ID"} = $line;
      }
    }

    if ( $line =~ m/^OPSGENIE/ ) {
      if ( $line =~ m/^OPSGENIE_KEY=/ ) {
        $line =~ s/^OPSGENIE_KEY=//;
        $inventory_alert{"GLOBAL"}{"OPSGENIE"}{"KEY"} = $line;
      }
      if ( $line =~ m/^OPSGENIE_URL=/ ) {
        $line =~ s/^OPSGENIE_URL=//;
        $inventory_alert{"GLOBAL"}{"OPSGENIE"}{"URL"} = $line;
      }
    }

  }

  #print Dumper \%inventory_alert;

  ### set up global repeat alert for alerting

  foreach my $line (@data_repeat_file) {
    chomp $line;
    if ( $line eq "" || $line =~ m/^#/ ) { next; }
    $line =~ s/^\s+|\s+$//g;
    if ( $line eq "" || $line =~ m/^#/ ) { next; }
    push @{ $inventory_alert{REPEAT} }, "$line";
  }
  my @data_repeat_file_old = @data_repeat_file;
  @data_repeat_file = ();

  #print Dumper \%inventory_alert;

  ###

  ### set up metrics for lpars in structure inventory_alert
  ### LPAR:Linux--unknown:vm-lukas.virtuals:CPU:1:0.5:::
  ### remove min values
  ### add key value for duplicite rules other email group
  my $key = 0;

  foreach my $line ( @{ $inventory_alert{"DATA"} } ) {
    chomp $line;
    $line =~ s/^\s+|\s+$//g;
    $line =~ s/\\:/===========doublecoma=========/g;
    ( undef, undef, my $lpar, my $metric, my $max, my $peek, my $repeat, my $exclude_time, my $email ) = split( ":", $line );

    ### new general rule
    #LPAR:::OSCPU:2::::Boss
    #LPAR:ASRV11::OSCPU:1%:20:60:11-12:Boss
    if ( !defined $lpar || $lpar eq "" ) {
      $lpar = $lpar_name;
    }

    ### check data integrity
    if ( !defined $lpar || $lpar eq "" || !defined $metric || $metric eq "" ) { next; }

    ### max and min remove % char
    if ( defined $max ) { $max =~ s/\%//g; }

    #if (defined $min){$min =~ s/\%//g;}

    ### lpar special name convert ###
    #$lpar =~ s/\//&&1/g;
    $lpar =~ s/===========doublecoma=========/:/g;

    #my $org_lpar = $lpar;
    #$org_lpar =~ s/&&1/\//g;
    ###

    ### Add nmon section every metric with nmon will end -NMON ###
    #if ($type eq "NMON"){
    #  $lpar = $lpar . "--NMON--";
    #}

    if ( defined $max && isdigit($max) ) {
      $inventory_alert{LPAR}{$key}{$lpar}{METRIC}{$metric}{MAX} = $max;
    }
    else { $inventory_alert{LPAR}{$key}{$lpar}{METRIC}{$metric}{MAX} = "NAN"; }

    #if (defined $min && isdigit($min)){
    #  $inventory_alert{SERVER}{$server}{LPAR}{$key}{$lpar}{METRIC}{$metric}{MIN} = $min;
    #}
    #else{$inventory_alert{SERVER}{$server}{LPAR}{$key}{$lpar}{METRIC}{$metric}{MIN} = "NAN";}

    if ( defined $peek && isdigit($peek) ) {
      $inventory_alert{LPAR}{$key}{$lpar}{METRIC}{$metric}{PEAK} = $peek;
    }
    else { $inventory_alert{LPAR}{$key}{$lpar}{METRIC}{$metric}{PEAK} = "NAN"; }

    if ( defined $repeat && isdigit($repeat) ) {
      $inventory_alert{LPAR}{$key}{$lpar}{METRIC}{$metric}{REPEAT} = $repeat;
    }
    else { $inventory_alert{LPAR}{$key}{$lpar}{METRIC}{$metric}{REPEAT} = "NAN"; }
    if ( defined $exclude_time ) {
      $inventory_alert{LPAR}{$key}{$lpar}{METRIC}{$metric}{EXCLUDE} = $exclude_time;
    }
    else { $inventory_alert{LPAR}{$key}{$lpar}{METRIC}{$metric}{EXCLUDE} = "NAN"; }

    if ( defined $email && $email ne "" ) {
      $email =~ s/ //g;
      $email =~ s/>//g;
      $email =~ s/#.*$//g;
      $inventory_alert{LPAR}{$key}{$lpar}{METRIC}{$metric}{EMAIL} = $email;
    }
    else { $inventory_alert{LPAR}{$key}{$lpar}{METRIC}{$metric}{EMAIL} = "NAN"; }

    $inventory_alert{LPAR}{$key}{$lpar}{NAME} = $lpar;
    $inventory_alert{LPAR}{$key}{$lpar}{TYPE} = $type;
    $inventory_alert{LPAR}{$key}{$lpar}{PATH} = $lpar_path;
    $inventory_alert{LPAR}{$key}{$lpar}{HMC}  = $lpar_hmc;
    $key++;

  }

  ### for every lpar metric add repeat check line

  foreach my $line ( @{ $inventory_alert{"REPEAT"} } ) {
    chomp $line;
    $line =~ s/^\s+|\s+$//g;
    ( my $server_act, my $lpar, my $metric, my $email, my $timestamp, my $human_timestamp ) = split( /\|/, $line );

    #$lpar =~ s/\//&&1/g;
    if ( $server_name ne $server_act ) { next; }
    if ( $lpar ne $lpar_name )         { next; }

    #if ($type eq "NMON"){$lpar = $lpar . "--NMON--"}
    foreach my $key ( keys %{ $inventory_alert{LPAR} } ) {
      if ( defined $inventory_alert{LPAR}{$key}{$lpar}{METRIC}{$metric} ) {
        $inventory_alert{LPAR}{$key}{$lpar}{METRIC}{$metric}{REPEAT_CHECK} = $timestamp;
        if ( defined $inventory_alert{LPAR}{$key}{$lpar}{METRIC}{$metric}{EMAIL} ) {
          my $email_group = $inventory_alert{LPAR}{$key}{$lpar}{METRIC}{$metric}{EMAIL};
          my $emails      = $inventory_alert{GLOBAL}{EMAIL}{$email_group};
          if ( defined $emails && $emails eq $email ) {
            $inventory_alert{LPAR}{$key}{$lpar}{METRIC}{$metric}{REPEAT_CHECK} = $timestamp;
          }
          else { next; }
        }
        else { next; }
      }
      else {
        delete $inventory_alert{LPAR}{$key}{$lpar}{METRIC}{$metric};
      }
    }
  }

  #print Dumper \%inventory_alert;
  ###

  ### assign metric rrd file ###
  foreach my $key ( keys %{ $inventory_alert{LPAR} } ) {
    foreach my $lpar ( keys %{ $inventory_alert{LPAR}{$key} } ) {
      my $path = $inventory_alert{LPAR}{$key}{$lpar}{PATH};
      my $hmc  = $inventory_alert{LPAR}{$key}{$lpar}{HMC};
      my $type = $inventory_alert{LPAR}{$key}{$lpar}{TYPE};
      foreach my $metric ( keys %{ $inventory_alert{LPAR}{$key}{$lpar}{METRIC} } ) {
        if ( $metric =~ m/^OSCPU$/i ) {
          my $file = "$path/cpu.mmm";
          if ( -e $file ) {
            $inventory_alert{LPAR}{$key}{$lpar}{METRIC}{$metric}{FILE} = $file;
          }
        }
        if ( $metric =~ m/^MEM$/i ) {
          my $file = "$path/mem.mmm";
          if ( -e $file ) {
            $inventory_alert{LPAR}{$key}{$lpar}{METRIC}{$metric}{FILE} = $file;
          }
        }
        if ( $metric =~ m/FS/i ) {
          my $file = "$path/FS.csv";
          if ( -e $file ) {
            $inventory_alert{LPAR}{$key}{$lpar}{METRIC}{$metric}{FILE} = $file;
          }
        }
        if ( $metric =~ m/^PAGING1$|^PAGING2$/i ) {
          my $file = "$path/pgs.mmm";
          if ( -e $file ) {
            $inventory_alert{LPAR}{$key}{$lpar}{METRIC}{$metric}{FILE} = $file;
          }
        }
        if ( $metric =~ m/^LAN$|^SAN$|^SAN_IOPS$|^SAN_RESP$|^SEA$/i ) {
          my $lpar_space = $lpar;
          my $lpar_pom   = $lpar;
          $lpar_pom =~ s/\//&&1/g;
          if ( $type eq "NMON" ) {
            $lpar_pom = $lpar_pom . "--NMON--";
          }
          $lpar_space = $lpar_pom;
          if ( $lpar_pom =~ m/ / ) {
            $lpar_space = "\"" . $lpar_pom . "\"";    # it must be here to support space with server names
          }

          my $hmc_space = $hmc;
          if ( $hmc =~ m/ / ) {
            $hmc_space = "\"" . $hmc . "\"";          # it must be here to support space with server names
          }
          my @lan_files = <$wrkdir/$server/$hmc_space/$lpar_space/*>;
          my $prefix    = "";
          if ( $metric =~ m/^SAN$|^SAN_IOPS$/ ) { $prefix = "san-"; }
          if ( $metric =~ m/^SAN_RESP$/ )       { $prefix = "san_resp-"; }
          if ( $metric =~ m/^LAN$/ )            { $prefix = "lan-"; }
          if ( $metric =~ m/^SEA$/ )            { $prefix = "sea-"; }
          foreach my $file_lan (@lan_files) {
            my $name_file = basename($file_lan);
            if ( $name_file =~ m/^$prefix/ && $name_file =~ m/\.mmm$/ ) {
              push @{ $inventory_alert{LPAR}{$key}{$lpar}{METRIC}{$metric}{FILE} }, "$file_lan";
            }
          }
        }
      }

    }
  }

  #print Dumper \%inventory_alert;

  ####
  #print Dumper \%inventory_alert;
  ### get value from rrd file and compare with max or min a call alerting ###

  #my $ltime_str = localtime();

  ### percent value

  ### default repeat
  my $repeat_default = $inventory_alert{GLOBAL}{REPEAT_DEFAULT};
  if ( !defined $repeat_default || $repeat_default eq '' ) {
    $repeat_default = 60;
  }

  ### NAGIOS
  my $nagios = $inventory_alert{GLOBAL}{NAGIOS};
  if ( !defined $nagios ) {
    $nagios = 0;
  }

  ### external alert
  my $extern_alert = $inventory_alert{GLOBAL}{EXTERN_ALERT};
  if ( !defined $extern_alert ) {
    $extern_alert = "";
  }

  ### for testing data last 5 minutes  these values are peaks
  my $peak_default = $inventory_alert{GLOBAL}{PEAK_TIME_DEFAULT};
  if ( !defined $peak_default || $peak_default eq '' ) {
    error("PEAK_TIME_DEFAULT is not set, exiting ...");
    return 1;
  }

  my $end_time   = time();
  my $start_time = $end_time - ( $peak_default * 60 );

  ### alert history
  my $alert_history = $inventory_alert{GLOBAL}{ALERT_HISTORY};
  if ( !defined $alert_history || $alert_history eq '' ) {
    $alert_history = "$basedir/logs/alert_history.log";
  }

  ### email graph
  my $email_graph = $inventory_alert{GLOBAL}{EMAIL_GRAPH};
  if ( !defined $email_graph || !isdigit($email_graph) ) {
    $email_graph = 0;
  }

  ### email from
  my $mailfrom = $inventory_alert{GLOBAL}{MAILFROM};
  if ( !defined $mailfrom || $mailfrom eq '' ) {
    $mailfrom = "lpar2rrd";
  }

  ### SNMP TRAP
  my $snmp_trap = $inventory_alert{GLOBAL}{TRAP};
  if ( !defined $snmp_trap ) {
    $snmp_trap = 0;
  }

  #print Dumper \%inventory_alert;

  foreach my $key ( keys %{ $inventory_alert{LPAR} } ) {
    foreach my $lpar ( keys %{ $inventory_alert{LPAR}{$key} } ) {
      if ( !defined $inventory_alert{LPAR}{$key}{$lpar}{NAME} || $inventory_alert{LPAR}{$key}{$lpar}{NAME} eq "" ) { next; }
      if ( !defined $inventory_alert{LPAR}{$key}{$lpar}{TYPE} || $inventory_alert{LPAR}{$key}{$lpar}{TYPE} eq "" ) { next; }
      my $lpar_name = $inventory_alert{LPAR}{$key}{$lpar}{NAME};
      my $last_type = $inventory_alert{LPAR}{$key}{$lpar}{TYPE};
      my $hmc       = $inventory_alert{LPAR}{$key}{$lpar}{HMC};
      foreach my $metric ( keys %{ $inventory_alert{LPAR}{$key}{$lpar}{METRIC} } ) {

        #if ($metric eq "CPU") {next;} ### ask for this metric

        my $percent         = "";
        my $alert_type_text = "";
        my $item            = "";
        my @lan_path        = ();
        my $path            = "";
        if ( !defined $inventory_alert{LPAR}{$key}{$lpar}{METRIC}{$metric}{FILE} ) { next; }
        if ( $metric eq "LAN" || $metric eq "SAN" || $metric eq "SAN_IOPS" || $metric eq "SAN_RESP" || $metric eq "SEA" ) {
          @lan_path = @{ $inventory_alert{LPAR}{$key}{$lpar}{METRIC}{$metric}{FILE} };
        }
        else {
          $path = $inventory_alert{LPAR}{$key}{$lpar}{METRIC}{$metric}{FILE};
        }
        my $max = $inventory_alert{LPAR}{$key}{$lpar}{METRIC}{$metric}{MAX};

        #my $min = $inventory_alert{SERVER}{$server}{LPAR}{$key}{$lpar}{METRIC}{$metric}{MIN};
        my $peek         = $inventory_alert{LPAR}{$key}{$lpar}{METRIC}{$metric}{PEAK};
        my $repeat       = $inventory_alert{LPAR}{$key}{$lpar}{METRIC}{$metric}{REPEAT};
        my $email        = $inventory_alert{LPAR}{$key}{$lpar}{METRIC}{$metric}{EMAIL};
        my $repeat_check = $inventory_alert{LPAR}{$key}{$lpar}{METRIC}{$metric}{REPEAT_CHECK};
        my $exclude_time = $inventory_alert{LPAR}{$key}{$lpar}{METRIC}{$metric}{EXCLUDE};

        # EXCLUDE TIME
        if ( defined $exclude_time && $exclude_time ne "" && $exclude_time =~ m/-/ ) {
          ( my $hour_start, my $hour_end ) = split( /-/, $exclude_time );
          if ( $hour_start < $hour_end ) {
            my $start = get_timestamp_from_hour($hour_start);
            my $end   = get_timestamp_from_hour($hour_end);
            if ( $start <= $end_time && $end_time <= $end ) {
              ### run exlude time
              #print "Exclude active for $last_type:$hmc:$server_name:$lpar_name:$metric\n";
              next;
            }
          }
          else {
            my $start          = get_timestamp_from_hour($hour_start);
            my $end            = get_timestamp_from_hour( $hour_end, "1" );
            my $start_last_day = $start - ( 24 * 3600 );
            my $end_last_day   = $end - ( 24 * 3600 );
            if ( ( $start <= $end_time && $end_time <= $end ) || ( $start_last_day <= $end_time && $end_time <= $end_last_day ) ) {

              #print "Exclude active for $last_type:$hmc:$server_name:$lpar_name:$metric\n";
              ### run exlude time
              next;
            }
          }
        }

        #

        #### check local email
        if ( defined $email && $email ne "" && $email ne "NAN" ) {
          $email = $inventory_alert{GLOBAL}{EMAIL}{$email};
        }
        if ( defined $email ) {
          if ( $email ne "" ) {
            if ( $email eq "NAN" ) {
              $email = "";
            }
          }
        }
        else {
          $email = "";
        }

        my $start = "";
        my $tint  = "";

        if ( defined $peek && isdigit($peek) ) {
          $start = $end_time - ( $peek * 60 );
          $tint  = $peek;
        }
        else {
          $start = $start_time;
          $tint  = $peak_default;
        }

        if ( !defined $repeat || !isdigit($repeat) ) {
          $repeat = $repeat_default;
        }

        if ( $metric eq "MEM" ) {
          $alert_type_text = "MEMORY";
        }
        if ( $metric eq "OSCPU" ) {
          $alert_type_text = "OS CPU";
        }
        if ( $metric eq "PAGING1" ) {
          $alert_type_text = "PAGING 1";
        }
        if ( $metric eq "PAGING2" ) {
          $alert_type_text = "PAGING 2";
        }
        if ( $metric eq "LAN" ) {
          $alert_type_text = "LAN";
        }
        if ( $metric eq "SAN" ) {
          $alert_type_text = "SAN";
        }
        if ( $metric eq "SAN_IOPS" ) {
          $alert_type_text = "SAN IOPS";
        }
        if ( $metric eq "SAN_RESP" ) {
          $alert_type_text = "SAN RESP";
        }
        if ( $metric eq "SEA" ) {
          $alert_type_text = "SEA";
        }
        if ( $metric eq "FS" ) {
          $alert_type_text = "FS";
        }

        ### test alert run repeat_time
        my $ltime_str = localtime();
        my $time      = time();
        if ( defined $repeat_check && isdigit($repeat_check) && ( $time - $repeat_check ) < $repeat * 60 ) {
          my $ltime_str_last = localtime($repeat_check);
          my $repeat_t       = $repeat * 60;

          #print "003 Alert not send : $alert_type_text $last_type:$hmc:$server_name:$lpar_name not this time due to repeat time $ltime_str_last + $repeat_t secs > $ltime_str \n";
          next;    # skip it, retention period
        }

        $path =~ s/:/\\:/g;
        my $rrd_out_name = "graph.png";
        my $answer;
        if ( $metric eq "MEM" ) {
          $percent = "%";
          $item    = "mem";
          eval {
            RRDp::cmd qq(graph "$rrd_out_name"
            "--start" "$start"
            "--end" "$end_time"
            "--step=60"
            "DEF:used=$path:nuse:AVERAGE"
            "DEF:free=$path:free:AVERAGE"
            "DEF:in_use_clnt=$path:in_use_clnt:AVERAGE"
            "CDEF:usedg=used,1048576,/"
            "CDEF:in_use_clnt_g=in_use_clnt,1048576,/"
            "CDEF:used_realg=usedg,in_use_clnt_g,-"
            "CDEF:free_g=free,1048576,/"
            "CDEF:sum=used_realg,in_use_clnt_g,+,free_g,+"
            "CDEF:util=used_realg,sum,/,100,*"
            "PRINT:util:AVERAGE:Util %2.2lf"
            );
            $answer = RRDp::read;
          };
        }
        if ( $metric eq "OSCPU" ) {
          $percent = "%";
          $item    = "oscpu";
          eval {
            RRDp::cmd qq(graph "$rrd_out_name"
            "--start" "$start"
            "--end" "$end_time"
            "--step=60"
            "DEF:cpus=$path:cpu_sy:AVERAGE"
            "DEF:cpuu=$path:cpu_us:AVERAGE"
            "CDEF:util=cpus,cpuu,+"
            "PRINT:util:AVERAGE:Util %2.2lf"
            );
            $answer = RRDp::read;
          };
        }
        if ( $metric eq "PAGING2" ) {
          $percent = "%";
          $item    = "pg2";
          eval {
            RRDp::cmd qq(graph "$rrd_out_name"
            "--start" "$start"
            "--end" "$end_time"
            "--step=60"
            "DEF:util=$path:percent:AVERAGE"
            "PRINT:util:AVERAGE:Util %2.2lf"
            );
            $answer = RRDp::read;
          };
        }
        if ( $metric eq "LAN" || $metric eq "SAN" || $metric eq "SEA" ) {
          $percent = "";
          $item    = "lan";
          if ( $metric eq "LAN" ) { $item = "lan"; }
          if ( $metric eq "SAN" ) { $item = "san1"; }
          if ( $metric eq "SEA" ) { $item = "sea"; }

          # filter everything above 11Gbites
          my $filter  = 1100000000;
          my $divider = 1000000;

          #eval { RRDp::cmd qq(graph "$rrd_out_name"
          #  "--start" "$start"
          #  "--end" "$end_time"
          #  "--step=60"
          #  "DEF:recb=$path:recv_bytes:AVERAGE"
          #  "DEF:tranb=$path:trans_bytes:AVERAGE"
          #  "CDEF:trab=tranb,$filter,GT,UNKN,tranb,IF"
          #  "CDEF:reb=recb,$filter,GT,UNKN,recb,IF"
          #  "CDEF:tranm=trab,$divider,/"
          #  "CDEF:recm=reb,$divider,/"
          #  "PRINT:recm:AVERAGE:Util %2.2lf"
          #  "PRINT:tranm:AVERAGE:Util %2.2lf"
          #  );
          #  $answer = RRDp::read;
          #};
          my $cmd   = "";
          my $index = 0;
          $cmd .= " graph \"$rrd_out_name\"";
          $cmd .= " --start \"$start\"";
          $cmd .= " --end \"$end_time\"";
          $cmd .= " --step=60";
          foreach my $file (@lan_path) {
            $file =~ s/:/\\:/g;
            $cmd .= " DEF:recb${index}=\"$file\":recv_bytes:AVERAGE";
            $cmd .= " DEF:tranb${index}=\"$file\":trans_bytes:AVERAGE";
            $cmd .= " CDEF:trab${index}=tranb${index},$filter,GT,UNKN,tranb${index},IF";
            $cmd .= " CDEF:reb${index}=recb${index},$filter,GT,UNKN,recb${index},IF";
            $cmd .= " CDEF:tranm${index}=trab${index},UN,0,trab${index},IF,$divider,/";
            $cmd .= " CDEF:recm${index}=reb${index},UN,0,reb${index},IF,$divider,/";
            $index++;
          }

          #trans item
          my $index_actual = 0;
          $cmd .= " CDEF:item_tranm_sum=tranm${index_actual}";
          $index_actual++;
          for ( ; $index_actual < $index; $index_actual++ ) {
            $cmd .= ",tranm${index_actual},+";
          }

          #receive item
          $index_actual = 0;
          $cmd .= " CDEF:item_recm_sum=recm${index_actual}";
          $index_actual++;
          for ( ; $index_actual < $index; $index_actual++ ) {
            $cmd .= ",recm${index_actual},+";
          }
          $cmd .= " PRINT:item_recm_sum:AVERAGE:\"Util %2.2lf\"";
          $cmd .= " PRINT:item_tranm_sum:AVERAGE:\"Util %2.2lf\"";
          eval {
            RRDp::cmd qq($cmd);
            $answer = RRDp::read;
          };
        }
        if ( $metric eq "SAN_IOPS" ) {
          $percent = "";
          $item    = "san2";
          my $cmd   = "";
          my $index = 0;
          $cmd .= " graph \"$rrd_out_name\"";
          $cmd .= " --start \"$start\"";
          $cmd .= " --end \"$end_time\"";
          $cmd .= " --step=60";

          foreach my $file (@lan_path) {
            $file =~ s/:/\\:/g;
            $cmd .= " DEF:iops_read${index}=\"$file\":iops_in:AVERAGE";
            $cmd .= " DEF:iops_write${index}=\"$file\":iops_out:AVERAGE";
            $cmd .= " CDEF:iops_read_check${index}=iops_read${index},UN,0,iops_read${index},IF";
            $cmd .= " CDEF:iops_write_check${index}=iops_write${index},UN,0,iops_write${index},IF";
            $index++;
          }

          #read io item
          my $index_actual = 0;
          $cmd .= " CDEF:item_read_io_sum=iops_read_check${index_actual}";
          $index_actual++;
          for ( ; $index_actual < $index; $index_actual++ ) {
            $cmd .= ",iops_read_check${index_actual},+";
          }

          #write io item
          $index_actual = 0;
          $cmd .= " CDEF:item_write_io_sum=iops_write_check${index_actual}";
          $index_actual++;
          for ( ; $index_actual < $index; $index_actual++ ) {
            $cmd .= ",iops_write_check${index_actual},+";
          }
          $cmd .= " CDEF:item_io_sum=item_read_io_sum,item_write_io_sum,+";
          $cmd .= " PRINT:item_read_io_sum:AVERAGE:\"Util %2.0lf\"";
          $cmd .= " PRINT:item_write_io_sum:AVERAGE:\"Util %2.0lf\"";
          $cmd .= " PRINT:item_io_sum:AVERAGE:\"Util %2.0lf\"";
          eval {
            RRDp::cmd qq($cmd);
            $answer = RRDp::read;
          };
        }
        if ( $metric eq "SAN_RESP" ) {
          $percent = "";
          $item    = "san_resp";
          my $cmd   = "";
          my $index = 0;
          $cmd .= " graph \"$rrd_out_name\"";
          $cmd .= " --start \"$start\"";
          $cmd .= " --end \"$end_time\"";
          $cmd .= " --step=60";

          foreach my $file (@lan_path) {
            ### check exist file san-name
            my $file_name           = basename($file);
            my $file_full           = $file;
            my $file_name_duplicate = basename($file);
            $file_name =~ s/^san_resp-//g;
            $file_name =~ s/\.mmm$//g;
            $file_name =~ s/^\s+|\s+$//g;
            my $file_iops = "san-$file_name.mmm";
            $file_full =~ s/$file_name_duplicate/$file_iops/g;

            if ( -f $file_full ) {
              $file      =~ s/:/\\:/g;
              $file_full =~ s/:/\\:/g;
              $cmd .= " DEF:io_read${index}=\"$file_full\":iops_in:AVERAGE";
              $cmd .= " DEF:io_write${index}=\"$file_full\":iops_out:AVERAGE";
              $cmd .= " DEF:resp_r${index}=\"$file\":resp_t_r:AVERAGE";
              $cmd .= " DEF:resp_w${index}=\"$file\":resp_t_w:AVERAGE";

              $cmd .= " CDEF:check_io_read${index}=io_read${index},UN,0,io_read${index},IF";
              $cmd .= " CDEF:check_io_write${index}=io_write${index},UN,0,io_write${index},IF";
              $cmd .= " CDEF:check_resp_r${index}=resp_r${index},UN,0,resp_r${index},IF";
              $cmd .= " CDEF:check_resp_w${index}=resp_w${index},UN,0,resp_w${index},IF";

              $cmd .= " CDEF:item_part_read${index}=check_io_read${index},check_resp_r${index},*";
              $cmd .= " CDEF:item_part_write${index}=check_io_write${index},check_resp_w${index},*";
              $index++;

            }
            else { next; }
          }

          # summary IO if it is response time
          my $index_actual = 0;
          $cmd .= " CDEF:io_read_sum=check_io_read${index_actual}";
          $index_actual++;
          for ( ; $index_actual < $index; $index_actual++ ) {
            $cmd .= ",check_io_read${index_actual},+";
          }

          $index_actual = 0;
          $cmd .= " CDEF:io_write_sum=check_io_write${index_actual}";
          $index_actual++;
          for ( ; $index_actual < $index; $index_actual++ ) {
            $cmd .= ",check_io_write${index_actual},+";
          }

          # get summary
          $index_actual = 0;
          $cmd .= " CDEF:item_read=item_part_read${index_actual}";
          $index_actual++;
          for ( ; $index_actual < $index; $index_actual++ ) {
            $cmd .= ",item_part_read${index_actual},+";
          }
          $cmd .= ",io_read_sum,/";

          $index_actual = 0;
          $cmd .= " CDEF:item_write=item_part_write${index_actual}";
          $index_actual++;
          for ( ; $index_actual < $index; $index_actual++ ) {
            $cmd .= ",item_part_write${index_actual},+";
          }
          $cmd .= ",io_write_sum,/";
          $cmd .= " CDEF:item_read_num=io_read_sum,item_read,*";
          $cmd .= " CDEF:item_write_num=io_write_sum,item_write,*";
          $cmd .= " CDEF:item_resp_num=item_read_num,item_write_num,+";
          $cmd .= " CDEF:item_io_sum=io_read_sum,io_write_sum,+";
          $cmd .= " CDEF:total=item_resp_num,item_io_sum,/";

          $cmd .= " PRINT:item_read:AVERAGE:\"Util %2.2lf\"";
          $cmd .= " PRINT:item_write:AVERAGE:\"Util %2.2lf\"";
          $cmd .= " PRINT:total:AVERAGE:\"Util %2.2lf\"";
          eval {
            RRDp::cmd qq($cmd);
            $answer = RRDp::read;
          };

        }
        if ( $metric eq "PAGING1" ) {
          $percent = "";
          $item    = "pg1";

          # filter everything above 11Gbites
          my $filter = 1100000000;
          eval {
            RRDp::cmd qq(graph "$rrd_out_name"
            "--start" "$start"
            "--end" "$end_time"
            "--step=60"
            "DEF:pagein=$path:page_in:AVERAGE"
            "DEF:pageout=$path:page_out:AVERAGE"
            "CDEF:pagein_b_nf=pagein,4096,*"
            "CDEF:pageout_b_nf=pageout,4096,*"
            "CDEF:pagein_b=pagein_b_nf,$filter,GT,UNKN,pagein_b_nf,IF"
            "CDEF:pageout_b=pageout_b_nf,$filter,GT,UNKN,pageout_b_nf,IF"
            "CDEF:pagein_mb=pagein_b,1048576,/"
            "CDEF:pagein_mb_neg=pagein_mb,-1,*"
            "CDEF:pageout_mb=pageout_b,1048576,/"
            "PRINT:pagein_mb:AVERAGE:Util %2.2lf"
            "PRINT:pageout_mb:AVERAGE:Util %2.2lf"
            );
            $answer = RRDp::read;
          };
        }
        if ($@) {
          if ( $@ =~ "ERROR" ) {
            error("Rrrdtool error : $@");
            next;
          }
        }
        if ( $metric eq "FS" ) {    #FS doesnt have RRD graphs $$answer not defined
          my $file = $inventory_alert{LPAR}{$key}{$lpar}{METRIC}{$metric}{FILE};
          open( FS, "< $file" ) || error( "could not open $file: $!" . __FILE__ . ":" . __LINE__ ) && return 1;
          my @file_content = <FS>;
          close(FS);
          my $exclude_file = "$basedir/etc/alert_filesystem_exclude.cfg";

          my @exclude_lines;
          if ( -e $exclude_file ) {
            open( EXCLUDE, "< $exclude_file" ) || error( "could not open $exclude_file: $!" . __FILE__ . ":" . __LINE__ ) && return 1;
            @exclude_lines = <EXCLUDE>;
            close(EXCLUDE);
          }

          chomp(@file_content);
          chomp(@exclude_lines);
          my @data_to_exclude;

          foreach my $line (@file_content) {
            ( my $name, my $blocks, my $used, my $avaliable, my $percentage, my $mount ) = split( /\s+/, $line );

            if ( scalar @exclude_lines == 0 ) {last}
            foreach my $exclude_line (@exclude_lines) {

              if ( $exclude_line && $mount =~ m/^$exclude_line$/g ) {

                push @data_to_exclude, $line;
              }
            }
          }

          for ( my $i = 0; $i < scalar @file_content; $i++ ) {    # $one_fs ( @file_content ) left_curly

            foreach my $one_ex (@data_to_exclude) {

              $one_ex =~ s/^\s+|\s+$//g;
              if ( $one_ex =~ m/^#.*/g ) {next}
              if ( $one_ex eq $file_content[$i] ) {
                splice( @file_content, $i, 1 );
                $i--;
              }
            }
          }

          $percent = "%";
          my $email_text;
          my $unit;
          my $util;
          my $max_string;
          foreach my $line (@file_content) {
            ( my $name, my $blocks, my $used, my $avaliable, my $percentage, my $mount ) = split( /\s+/, $line );
            if ( ( defined $max && isdigit($max) && isdigit($percentage) && $percentage > $max ) ) {

              ### push line to alert_repeat.tmp
              ### add email for identification same rules
              my $repeat_line = "$server_name|$lpar_name|$metric|$email|$time|$ltime_str";
              push( @data_repeat_file, "$repeat_line" );

              my $util_string = $percentage . $percent;
              $max_string = $max . $percent;
              $unit       = $percent;

              # log an alarm to a file : alert.log
              open( FHL, ">> $alert_history" ) || error( "could not open $alert_history: $!" . __FILE__ . ":" . __LINE__ ) && return 1;
              my $alerting_ways = "";

              ### nagios alarm
              if ( $nagios == 1 ) {
                $alerting_ways .= ",nagios";
                nagios_alarm( "OS-agent", $server_name, $lpar_name, $util_string, $max, $ltime_str, $last_type, $alert_type_text, $metric );
              }

              # extern alert-
              if ( !$extern_alert eq '' ) {
                $alerting_ways .= ",external";
                extern_alarm( "OS-agent", $server_name, $lpar_name, $util_string, $max, $ltime_str, $last_type, $alert_type_text, $extern_alert, $mount );
              }

              # SNMP TRAP
              if ( defined($snmp_trap) && $snmp_trap !~ m/your_snmp_trap_server/ ) {
                $alerting_ways .= ",snmp trap($snmp_trap)";
                snmp_trap_alarm( $snmp_trap, $server_name, $lpar_name, $util_string, $max, $ltime_str, $last_type, $alert_type_text );
              }

              if ( defined $email && $email ne "" && $email ne "NAN" ) {
                $alerting_ways .= ",email($email)";
                my $lpar_path = $lpar;
                $lpar_path =~ s/\//&&1/g;
                my $graph_path = "";
                $util = "Higher than $max";

                #sendmail( $email, "$ltime_str: $alert_type_text alert for:\n LPAR: $lpar_name\n server: $server_name\n utilization in filesystem $name mounted on $mount is $percentage%\n $alert_type_text MAX limit: $max_string\n\n", $lpar_name, $util, $last_type, $alert_type_text, $server_name, $unit ); ## REMOVED: $graph_path, $email_graph

                $email_text .= " $name mounted on $mount is $percentage%\n";
                ## instead of sendmail use var which will be send later!
              }

              if ( defined $inventory_alert{"GLOBAL"}{"SERVICE_NOW"}{"IP"} && $inventory_alert{"GLOBAL"}{"SERVICE_NOW"}{"IP"} ne "" ) {
                $alerting_ways .= ",service_now";
                service_now( "$ltime_str: $alert_type_text alert for: LPAR: $lpar_name server: $server_name avg utilization during last $tint mins $util_string $alert_type_text MAX limit: $max_string", $lpar_name, $util, $last_type, $alert_type_text, $server_name, $unit, $inventory_alert{"GLOBAL"}{"SERVICE_NOW"} );
              }

              if ( defined $inventory_alert{"GLOBAL"}{"JIRA_CLOUD"}{"URL"} && $inventory_alert{"GLOBAL"}{"JIRA_CLOUD"}{"URL"} ne "" && defined $inventory_alert{"GLOBAL"}{"JIRA_CLOUD"}{"TOKEN"} ) {
                $alerting_ways .= ",jira_cloud";
                jira_cloud( "$ltime_str: $alert_type_text alert for: LPAR: $lpar_name server: $server_name avg utilization during last $tint mins $util_string $alert_type_text MAX limit: $max_string", $lpar_name, $util, $last_type, $alert_type_text, $server_name, $unit, $inventory_alert{"GLOBAL"}{"JIRA_CLOUD"} );
              }

              if ( defined $inventory_alert{"GLOBAL"}{"OPSGENIE"}{"KEY"} && $inventory_alert{"GLOBAL"}{"OPSGENIE"}{"KEY"} ne "" ) {
                $alerting_ways .= ",opsgenie";
                opsgenie( "$ltime_str: $alert_type_text alert for: LPAR: $lpar_name server: $server_name avg utilization during last $tint mins $util_string $alert_type_text MAX limit: $max_string", $lpar_name, $util, $last_type, $alert_type_text, $server_name, $unit, $inventory_alert{"GLOBAL"}{"OPSGENIE"} );
              }

              #print FHL "$ltime_str: $alert_type_text $last_type:$server_name:$lpar_name, $name mounted on: $mount actual util:$util_string, limit max:$max_string, $alerting_ways\n";
              print FHL "$ltime_str; $alert_type_text; $last_type; $server_name; $lpar_name; $name mounted on: $mount actual util:$util_string, limit max:$max_string, $alerting_ways\n";
              close(FHL);
            }
            else {
              if ( defined $percentage && isdigit($percentage) && defined $max && isdigit($max) ) {

                #print "Alert not send : $alert_type_text $last_type:$server_name:$lpar_name utilization $utilization is not greater max limit $max\n";
                next;
              }
              else {
                #print "Utilization is not defined or max limit is not defined\n";
                next;
              }
            }
          }
          if ( defined $email_text ) {
            sendmail( $mailfrom, $email, "$ltime_str: $alert_type_text alert for:\n LPAR: $lpar_name\n server: $server_name\n$email_text FS MAX LIMIT IS: $max_string\n", $lpar_name, $util, $last_type, $alert_type_text, $server_name, "", "", $unit, "FS_OK" );    #Util = higher than x%
          }
          next;
        }
        elsif ( !defined $answer ) { next; }
        my $aaa = $$answer;
        ( undef, my $utilization, my $utilization2, my $utilization3 ) = split( "\n", $aaa );
        $utilization =~ s/Util\s+//;
        $utilization =~ s/,/\./;       # -PH: CPU OS puts as decimal separator "," instead of ".", very weird ....

        if ( defined $utilization2 ) {
          $utilization2 =~ s/Util\s+//;
          $utilization2 =~ s/,/\./;       # -PH: CPU OS puts as decimal separator "," instead of ".", very weird ....
        }
        if ( defined $utilization3 ) {
          $utilization3 =~ s/Util\s+//;
          $utilization3 =~ s/,/\./;       # -PH: CPU OS puts as decimal separator "," instead of ".", very weird ....
        }
        my $util_pom = "";
        ### SAN IOPS AND SAN RESP add total value
        if ( $item eq "san2" ) {
          $util_pom    = $utilization;
          $utilization = $utilization3;
        }
        if ( $item eq "san_resp" ) {
          $util_pom    = $utilization;
          $utilization = $utilization3;
        }

        if ( $item ne "san2" && $item ne "san_resp" ) {

          # case 1 utilization is number utilization2 is not defined
          # do not nothing

          # case 2 utilization is nan  utilization2 is not defined or is not digit
          if ( !isdigit($utilization) && ( !defined $utilization2 || !isdigit($utilization2) ) ) {
            next;
          }

          # case 3 utitilization is nan utilization2 is number
          if ( !isdigit($utilization) && isdigit($utilization2) ) {
            $util_pom    = $utilization;
            $utilization = $utilization2;
          }

          # case 4 utilization is number utilization2 is number
          if ( isdigit($utilization) && defined $utilization2 && isdigit($utilization2) ) {
            if ( $utilization2 > $utilization ) {
              $util_pom    = $utilization;
              $utilization = $utilization2;
            }
          }
        }
        if ( ( defined $max && isdigit($max) && isdigit($utilization) && $utilization > $max ) ) {

          ### push line to alert_repeat.tmp
          ### add email for identification same rules
          my $repeat_line = "$server_name|$lpar_name|$metric|$email|$time|$ltime_str";
          push( @data_repeat_file, "$repeat_line" );

          ###

          my $util_string = $utilization . $percent;
          my $max_string  = $max . $percent;
          my $unit        = "";
          if ( $percent eq "%" ) {
            $unit = $percent;
          }

          #my $min_string = $min . $percent;
          if ( $item eq "pg1" ) {
            $unit = "MB/s";
            if ( $util_pom ne "" ) {
              $util_string = "$util_pom Page in MB/s, $utilization2 Page out MB/s";
            }
            else {
              $util_string = "$utilization Page in MB/s, $utilization2 Page out MB/s";
            }
          }
          if ( $item eq "lan" ) {
            $unit = "MB/s";
            if ( $util_pom ne "" ) {
              $util_string = "$util_pom READ/IN in MB/s, $utilization2 WRITE/OUT in MB/s";
            }
            else {
              $util_string = "$utilization READ/IN in MB/s, $utilization2 WRITE/OUT in MB/s";
            }
          }
          if ( $item eq "san1" ) {
            $unit = "MB/s";
            if ( $util_pom ne "" ) {
              $util_string = "$util_pom READ in MB/s, $utilization2 WRITE in MB/s";
            }
            else {
              $util_string = "$utilization READ in MB/s, $utilization2 WRITE in MB/s";
            }
          }
          if ( $item eq "san2" ) {
            $unit = "IOPS";

            #if ($util_pom ne ""){
            #  $util_string = "$util_pom READ IOPS, $utilization2 WRITE IOPS";
            #}
            #else{
            $util_string = "$util_pom READ IOPS, $utilization2 WRITE IOPS, $utilization TOTAL IOPS";

            #}
          }
          if ( $item eq "san_resp" ) {
            $unit = "ms";
            if ( $util_pom ne "" ) {
              $util_string = "$util_pom RESPONSE READ in ms, $utilization2 RESPONSE WRITE in ms, $utilization RESPONSE TOTAL in ms";
            }

            #else{
            #$util_string = "$utilization RESPONSE READ in ms, $utilization2 RESPONSE WRITE in ms";
            #}
          }
          if ( $item eq "sea" ) {
            $unit = "MB/s";
            if ( $util_pom ne "" ) {
              $util_string = "$util_pom READ/IN in MB/s, $utilization2 WRITE/OUT in MB/s";
            }
            else {
              $util_string = "$utilization READ/IN in MB/s, $utilization2 WRITE/OUT in MB/s";
            }
          }
          if ( $unit ne "%" ) {
            $max_string = "$max $unit";
          }

          # log an alarm to a file : alert.log
          open( FHL, ">> $alert_history" ) || error( "could not open $alert_history: $!" . __FILE__ . ":" . __LINE__ ) && return 1;
          my $alerting_ways = "";

          ### nagios alarm
          if ( $nagios == 1 ) {
            $alerting_ways .= ",nagios";
            nagios_alarm( "OS-agent", $server_name, $lpar_name, $util_string, $max, $ltime_str, $last_type, $alert_type_text, $metric );
          }

          # extern alert-
          if ( !$extern_alert eq '' ) {
            $alerting_ways .= ",external";
            extern_alarm( "OS-agent", $server_name, $lpar_name, $util_string, $max, $ltime_str, $last_type, $alert_type_text, $extern_alert, "" );    # last empty is a mount point which is not go through this
          }

          # SNMP TRAP
          if ( defined($snmp_trap) && $snmp_trap !~ m/your_snmp_trap_server/ ) {
            $alerting_ways .= ",snmp trap($snmp_trap)";
            snmp_trap_alarm( $snmp_trap, $server_name, $lpar_name, $util_string, $max, $ltime_str, $last_type, $alert_type_text );
          }

          if ( defined $email && $email ne "" && $email ne "NAN" ) {
            $alerting_ways .= ",email($email)";
            my $lpar_path = $lpar;
            $lpar_path =~ s/\//&&1/g;
            my $graph_path = "$tmpdir/alert_graph_$server-$hmc-$lpar_path.png";
            $graph_path =~ s/;//g;      # ";" cannot be in the path
            $graph_path =~ s/ //g;      # ";" cannot be in the path
            $graph_path =~ s/%//g;      # ";" cannot be in the path
            $graph_path =~ s/#//g;      # ";" cannot be in the path
            $graph_path =~ s/://g;      # ";" cannot be in the path
            $graph_path =~ s/&&1//g;    # ";" cannot be in the path
            my $util = $utilization;

            if ( $email_graph > 0 ) {
              if ( $type eq "NMON" ) {
                my $lpar_name_graf = $lpar_name . "--NMON--";
                create_graph( $hmc, $server, $lpar_name_graf, $graph_path, $basedir, $bindir, $email_graph, $item );
              }
              else {
                create_graph( $hmc, $server, $lpar_name, $graph_path, $basedir, $bindir, $email_graph, $item );
              }
            }
            sendmail( $mailfrom, $email, "$ltime_str: $alert_type_text alert for:\n LPAR: $lpar_name\n server: $server_name\n avg utilization during last $tint mins $util_string\n $alert_type_text MAX limit: $max_string\n\n", $lpar_name, $util, $last_type, $alert_type_text, $server_name, $graph_path, $email_graph, $unit );
          }

          if ( defined $inventory_alert{"GLOBAL"}{"SERVICE_NOW"}{"IP"} && $inventory_alert{"GLOBAL"}{"SERVICE_NOW"}{"IP"} ne "" ) {
            $alerting_ways .= ",service_now";
            my $util = $utilization;
            service_now( "$ltime_str: $alert_type_text alert for: LPAR: $lpar_name server: $server_name avg utilization during last $tint mins $util_string $alert_type_text MAX limit: $max_string", $lpar_name, $util, $last_type, $alert_type_text, $server_name, $unit, $inventory_alert{"GLOBAL"}{"SERVICE_NOW"} );
          }

          if ( defined $inventory_alert{"GLOBAL"}{"JIRA_CLOUD"}{"URL"} && $inventory_alert{"GLOBAL"}{"JIRA_CLOUD"}{"URL"} ne "" && defined $inventory_alert{"GLOBAL"}{"JIRA_CLOUD"}{"TOKEN"} ) {
            $alerting_ways .= ",jira_cloud";
            my $util = $utilization;
            jira_cloud( "$ltime_str: $alert_type_text alert for: LPAR: $lpar_name server: $server_name avg utilization during last $tint mins $util_string $alert_type_text MAX limit: $max_string", $lpar_name, $util, $last_type, $alert_type_text, $server_name, $unit, $inventory_alert{"GLOBAL"}{"JIRA_CLOUD"} );
          }

          if ( defined $inventory_alert{"GLOBAL"}{"OPSGENIE"}{"KEY"} && $inventory_alert{"GLOBAL"}{"OPSGENIE"}{"KEY"} ne "" ) {
            $alerting_ways .= ",opsgenie";
            opsgenie( "$ltime_str: $alert_type_text alert for: LPAR: $lpar_name server: $server_name avg utilization during last $tint mins $util_string $alert_type_text MAX limit: $max_string", $lpar_name, $utilization, $last_type, $alert_type_text, $server_name, $unit, $inventory_alert{"GLOBAL"}{"OPSGENIE"} );
          }

          #print FHL "$ltime_str: $alert_type_text $last_type:$server_name:$lpar_name, actual util:$util_string, limit max:$max_string, $alerting_ways\n";
          print FHL "$ltime_str; $alert_type_text; $last_type; $server_name; $lpar_name; actual util:$util_string, limit max:$max_string, $alerting_ways\n";
          close(FHL);
        }
        else {
          if ( defined $utilization && isdigit($utilization) && defined $max && isdigit($max) ) {

            #print "Alert not send : $alert_type_text $last_type:$server_name:$lpar_name utilization $utilization is not greater max limit $max\n";
            next;
          }
          else {
            #print "Utilization is not defined or max limit is not defined\n";
            next;
          }
        }
      }
    }
  }

  #
  # retention stuff management
  #

  my $alert_sent = 0;
  foreach my $line1 (@data_repeat_file) {
    chomp($line1);
    $alert_sent = 1;
    last;
  }

  if ( $alert_sent == 0 ) {
    return 1;    # skip end, nothing new for retention file
  }

  #save repeat_time in file
  my @data_repeat_file_act          = ();
  my @data_repeat_file_act_non_uniq = ();
  foreach my $line (@data_repeat_file_old) {
    chomp $line;
    ( my $server, my $lpar, my $metric, my $email ) = split( /\|/, $line );
    my $index  = -1;
    my $active = 0;
    foreach my $line_ar1 (@data_repeat_file) {
      chomp $line_ar1;
      $index++;
      ( my $server_ar1, my $lpar_ar1, my $metric_ar1, my $email_ar1 ) = split( /\|/, $line_ar1 );
      if ( $server_ar1 eq $server && $lpar eq $lpar_ar1 && $metric eq $metric_ar1 && $email eq $email_ar1 ) {
        push( @data_repeat_file_act_non_uniq, "$line_ar1" );
        splice( @data_repeat_file, $index, 1 );
        $active = 1;
        last;
      }
    }
    if ( $active == 1 ) { $active = 0; next; }
    push( @data_repeat_file_act_non_uniq, "$line" );
  }

  foreach my $line1 (@data_repeat_file) {
    chomp $line1;
    push( @data_repeat_file_act_non_uniq, "$line1" );
  }

  my %seen = ();
  @data_repeat_file_act = grep { !$seen{$_}++ } @data_repeat_file_act_non_uniq;

  my $anything_to_write = 0;
  foreach my $line1 (@data_repeat_file_act) {
    if ( !defined($line1) || $line1 eq '' || $line1 eq '\n' ) {
      next;
    }
    $anything_to_write = 1;
    last;
  }

  if ( $anything_to_write == 1 ) {

    my $repeat_non_empty = 0;
    my $any_new          = 0;
    foreach my $line1 (@data_repeat_file_old) {
      if ( !defined($line1) || $line1 eq '' || $line1 eq '\n' ) {
        next;
      }
      $repeat_non_empty = 1;
      last;
    }

    if ( $repeat_non_empty == 1 ) {

      # if @data_repeat_file_act == @data_repeat_file_old then skip, nothing new
      foreach my $i (@data_repeat_file_act) {
        chomp($i);
        foreach my $k (@data_repeat_file_old) {
          chomp($k);
          if ( $i eq $k ) {
            $any_new = 1;
            last;
          }
        }
      }
    }

    if ( $any_new == 1 || $repeat_non_empty == 0 ) {
      open( FHW, "> $repeat_file" ) || error( "Cannot write $repeat_file: $!" . __FILE__ . ":" . __LINE__ ) && return 1;
      foreach my $line1 (@data_repeat_file_act) {
        chomp($line1);
        print FHW "$line1\n";
      }
      close(FHW);
    }
  }

}

sub get_array_data {
  my $file = shift;
  open( FH, "< $file" ) || error( "Cannot read $file: $!" . __FILE__ . ":" . __LINE__ ) && exit(1);
  my @file_all = <FH>;
  close(FH);
  return @file_all;
}

sub sendmail {
  my $mailfrom        = shift;
  my $mailto          = shift;
  my $text            = shift;
  my $lpar            = shift;
  my $util            = shift;
  my $last_type       = shift;
  my $alert_type_text = shift;
  my $managed         = shift;
  my $graph_path      = shift;
  my $email_graph     = shift;
  my $unit            = shift;
  my $FS_checker      = shift;
  my $boundary        = "===" . time . "===";
  my $message_body;
  my @att_files;
  my @att_names;

  my $subject;
  if ( defined $FS_checker ) {
    if ( $FS_checker eq "FS_OK" ) {
      $subject = "LPAR2RRD: $alert_type_text alert for $managed $last_type: $lpar, usage is: $util $unit";    # FS
    }
    elsif ( $FS_checker eq "MULTI_OK" ) {
      $subject = "LPAR2RRD: $alert_type_text alert for $managed $last_type: $lpar";                           # MULTIPATH
    }
  }
  else {
    $subject = "LPAR2RRD: $alert_type_text alert for $managed $last_type: $lpar, utilization is: $util $unit";
  }
  my $message = "\n";

  $lpar =~ s/\&\&1/\//g;

  $message_body .= "$text\n";
  if ( exists $inventory_alert{GLOBAL}{'WEB_UI_URL'} && $inventory_alert{GLOBAL}{'WEB_UI_URL'} ne '' ) {
    $message_body .= "\n\nCheck it out in the LPAR2RRD UI: $inventory_alert{GLOBAL}{'WEB_UI_URL'}\n";
  }
  $message_body .= "\n\n";

  my $managed_space = $managed;
  $managed_space =~ s/ /\\ /g;
  $managed_space =~ s/;//g;
  my $lpar_space = $lpar;
  $lpar_space =~ s/ /\\ /g;
  $lpar_space =~ s/;//g;

  if ( isdigit($email_graph) && $email_graph > 0 && -f $graph_path ) {
    push @att_files, $graph_path;
    push @att_names, "$managed_space:$lpar_space.png";

  }

  my @email_list = split( /,/, $mailto );
  foreach my $email (@email_list) {
    chomp $email;
    Xorux_lib::send_email( $email, $mailfrom, $subject, $message_body, \@att_files, \@att_names );
  }
  foreach my $f_path (@att_files) {
    if ( -f $f_path ) {
      unlink($f_path);
    }
  }
  return 0;
}

sub create_graph {
  my $host        = shift;
  my $server      = shift;
  my $lpar        = shift;
  my $graph_path  = shift;
  my $basedir     = shift;
  my $bindir      = shift;
  my $email_graph = shift;
  my $type        = shift;
  my $log         = "$tmpdir/alert.log";
  my $perl        = $ENV{PERL};

  my $lpar_url = $lpar;
  $lpar_url =~ s/\//&&1/g;
  my $server_url = $server;
  $lpar_url   =~ s/([^a-zA-Z0-9_.!~*()'\''-])/sprintf("%%%02X", ord($1))/ge;
  $server_url =~ s/([^a-zA-Z0-9_.!~*()'\''-])/sprintf("%%%02X", ord($1))/ge;

  #print "Graph creation : $host:$server:$lpar\n";
  # set env for graphing script which is normally called via CGI-BIN
  if ( $type eq "mem" || $type eq "oscpu" || $type eq "pg1" || $type eq "pg2" || $type eq "lan" || $type eq "san1" || $type eq "san2" || $type eq "san_resp" || $type eq "sea" ) {

    # for LPARs
    $ENV{'QUERY_STRING'}   = "host=$host&server=$server_url&lpar=$lpar_url&item=$type&time=d&type_sam=m&detail=0&none=none&none1=none";
    $ENV{'REQUEST_METHOD'} = "GET";
  }

  #print "calling grapher: $perl $bindir/detail-graph-cgi.pl alarm $graph_path $email_graph > $log\n";
  #print "QUERY_STRING   : $ENV{'QUERY_STRING'}\n";

  `$perl $bindir/detail-graph-cgi.pl alarm $graph_path $email_graph > $log 2>&1`;

  # only LOG, not the picture
  if ( -f $log ) {
    open( FH, "< $log" );
    foreach my $line (<FH>) {
      print "$line";
    }
    close(FH);
    unlink($log);
  }

  return 1;
}

sub nagios_alarm {
  my $host            = shift;
  my $managed         = shift;
  my $lpar            = shift;
  my $util            = shift;
  my $utillim         = shift;
  my $ltime_str       = shift;
  my $last_type       = shift;
  my $alert_type_text = shift;
  my $metric          = shift;

  my $nagios_dir = "$basedir/nagios";
  my $lpar_name  = $lpar;
  $lpar_name =~ s/\//&&1/g;

  #print "Alert nagios   : $last_type=$lpar:$managed:$lpar utilization=$util\n";

  if ( !-d "$nagios_dir" ) {

    #print "mkdir          : $nagios_dir\n" if $DEBUG ;
    mkdir( "$nagios_dir", 0755 ) || error( "Cannot mkdir $nagios_dir: $!" . __FILE__ . ":" . __LINE__ ) && return 1;
    chmod 0777, "$nagios_dir" || error( "Can't chmod 666 $nagios_dir: $!" . __FILE__ . ":" . __LINE__ ) && return 1;
  }

  if ( !-d "$nagios_dir/$managed" ) {

    #print "mkdir          : $nagios_dir/$managed\n" if $DEBUG ;
    mkdir( "$nagios_dir/$managed", 0755 ) || error( "Cannot mkdir $nagios_dir/$managed: $!" . __FILE__ . ":" . __LINE__ ) && return 1;
    chmod 0777, "$nagios_dir/$managed" || error( "Can't chmod 666 $nagios_dir/$managed: $!" . __FILE__ . ":" . __LINE__ ) && return 1;
  }

  if ( !-d "$nagios_dir/$managed/$lpar_name" ) {

    #print "mkdir          : $nagios_dir/$managed/$lpar_name\n" if $DEBUG ;
    mkdir( "$nagios_dir/$managed/$lpar_name", 0755 ) || error( "Cannot mkdir $nagios_dir/$managed/$lpar_name: $!" . __FILE__ . ":" . __LINE__ ) && return 1;
    chmod 0777, "$nagios_dir/$managed/$lpar_name" || error( "Can't chmod 666 $nagios_dir/$managed/$lpar_name: $!" . __FILE__ . ":" . __LINE__ ) && return 1;
  }

  open( FH, "> $nagios_dir/$managed/$lpar_name/$metric" ) || error( "Can't create $nagios_dir/$managed/$lpar_name/$metric : $!" . __FILE__ . ":" . __LINE__ ) && return 1;

  if ( $alert_type_text =~ m/Swapping/ ) {
    print FH "$alert_type_text alert for: $last_type=$lpar server=$managed; $util, MAX limit=$utillim\n";
  }
  else {
    print FH "$alert_type_text alert for: $managed $last_type=$lpar server=$managed managed by = $host; utilization=$util, MAX limit=$utillim\n";
  }

  close(FH);

  chmod 0666, "$nagios_dir/$managed/$lpar_name/$metric" || error( "Can't chmod 666 $nagios_dir/$managed/$lpar_name/$metric : $!" . __FILE__ . ":" . __LINE__ ) && return 1;

  return 1;
}

sub extern_alarm {
  my $host            = shift;
  my $managed         = shift;
  my $lpar            = shift;
  my $util            = shift;
  my $utillim         = shift;
  my $ltime_str       = shift;
  my $last_type       = shift;
  my $alert_type_text = shift;
  my $extern_alert    = shift;
  my $FS_mount_point  = shift;

  if ( !-x "$extern_alert" ) {
    error("EXTERN_ALERT is set but the file is not executable : $extern_alert");
    return 1;
  }

  #print "Alert external : $last_type=$host:$managed:$lpar utilization=$util\n";

  system( "$extern_alert", "$alert_type_text", "$last_type", "$managed", "$lpar", "$util", "$utillim", "$host", "$FS_mount_point" );

  return 1;
}

sub get_timestamp_from_hour {
  my $hour_param     = shift;
  my $check_next_day = shift;

  my $act_time = time();
  ( my $sec, my $min, my $hour, my $mday, my $mon, my $year, my $wday, my $yday, my $isdst ) = localtime();
  my $midnight = $act_time - $sec - ( $min * 60 ) - ( $hour * 60 * 60 );

  if ( $hour_param =~ m/^0/ ) {
    $hour_param =~ s/0//;
  }
  if ( $hour_param eq "" ) { $hour_param = 0; }

  if ( $hour_param == 0 && !defined $check_next_day ) {
    return $midnight;
  }
  if ( defined $check_next_day ) {
    my $timestamp = $midnight + ( $hour_param * 60 * 60 ) + ( 24 * 60 * 60 );
    return $timestamp;
  }
  else {
    my $timestamp = $midnight + ( $hour_param * 60 * 60 );
    return $timestamp;
  }

}

sub get_name_server_for_alert {
  my $server = shift;
  if ( -l "$wrkdir/$server" ) {
    my $link        = readlink("$wrkdir/$server");
    my $server_name = basename($link);
    if ( defined $server_name && $server_name ne "" ) {
      return $server_name;
    }
    else {
      return $server;
    }
  }
  else {
    return $server;
  }

}

sub snmp_trap_alarm {
  my $trap_host       = shift;
  my $host            = "OS-agent";
  my $managed         = shift;
  my $lpar            = shift;
  my $util            = shift;
  my $utillim         = shift;
  my $ltime_str       = shift;
  my $last_type       = shift;
  my $alert_type_text = shift;

  my $SNMP_PEN         = "40540";
  my $PRE              = "1.3.6.1.4.1.40540";
  my $community_string = "public";

  if ( exists $inventory_alert{GLOBAL}{'COMM_STRING'} && $inventory_alert{GLOBAL}{'COMM_STRING'} ne '' ) {
    $community_string = $inventory_alert{GLOBAL}{'COMM_STRING'};
  }

  if ( defined $ENV{LPAR2RRD_SNMPTRAP_COMUNITY} ) {
    $community_string = $ENV{LPAR2RRD_SNMPTRAP_COMUNITY};
  }

  #print "Alert SNMP TRAP: $last_type=$lpar:$managed:$lpar utilization=$util\n";
  # this command sends canonical SNMP names
  # `snmptrap -v 1 -c $community_string $trap_host XORUX-MIB::lpar2rrdSendTrap '' 6 7 '' XORUX-MIB::lpar2rrdHmcName s '$host' XORUX-MIB::lpar2rrdServerName s '$host' XORUX-MIB::lpar2rrdLparName s '$lpar' XORUX-MIB::lpar2rrdValue s '$util' XORUX-MIB::lpar2rrdSu bsystem s '$alert_type_text'`;
  # this one send numerical (it's OK for our needs)

  my $snmp_exe = "/opt/freeware/bin/snmptrap";    # AIX place
  if ( !-f "$snmp_exe" ) {
    $snmp_exe = "/usr/bin/snmptrap";              #linux one
    if ( !-f "$snmp_exe" ) {
      $snmp_exe = "snmptrap";                     # lets hope it is in the PATH
    }
  }

  # print "SNMP trap exec : $snmp_exe -v 1 -c $community_string $trap_host $PRE.1.0.1.0.7 \'\' 6 7 \'\' $PRE.1.1 s $host $PRE.1.2 s $managed $PRE.1.3 s $lpar $PRE.1.4 s \'$alert_type_text\' $PRE.1.5 s $util\n";
  my $out = `$snmp_exe -v 1 -c '$community_string' '$trap_host' $PRE.1.0.1.0.7 '' 6 7 '' $PRE.1.1 s '$host' $PRE.1.2 s '$managed' $PRE.1.3 s '$lpar' $PRE.1.4 s '$alert_type_text' $PRE.1.5 s '$util' 2>&1;`;
  if ( $out =~ m/not found/ ) {
    error("SNMP Trap: $snmp_exe binnary has not been found, install net-snmp as per https://www.lpar2rrd.com/alerting_trap.php ($out)");
  }
  if ( $out =~ m/Usage: snmptrap/ ) {
    error("SNMP Trap: looks like you use native AIX /usr/sbin/snmptrap, it is not supported, check here: https://www.lpar2rrd.com/alerting_trap.php");
  }

  return 1;
}

sub hitachi_agent_mapping {
  my $lpar_space         = shift;
  my %hitachi_lpar_uuids = %{ shift @_ };
  my $uuid_file          = "$wrkdir/Hitachi/$lpar_space/lpar_uuids.json";
  my $no_hmc_dir         = "$wrkdir/Linux/no_hmc";
  my $agent_uuids_file   = "$no_hmc_dir/linux_uuid_name.json";
  my %lpar_uuid_conf;

  if ( !-e $uuid_file || ( time() - ( stat($uuid_file) )[9] > 3600 ) ) {
    my ( $code, $agent_uuids ) = -f $agent_uuids_file ? Xorux_lib::read_json($agent_uuids_file) : ( 0, undef );

    if ($code) {
      while ( my ( $name, $uuid ) = each %hitachi_lpar_uuids ) {
        my $agent_name = $agent_uuids->{$uuid};

        $lpar_uuid_conf{$name}{uuid} = $uuid;

        if ($agent_name) {
          $lpar_uuid_conf{$name}{agent_name} = $agent_name;
        }
      }

      if ( -d $no_hmc_dir ) {
        Xorux_lib::write_json( $uuid_file, \%lpar_uuid_conf );
      }
      else {
        error( "Directory $no_hmc_dir doesn't exist, can't create file linux_uuid_name.json:" . __FILE__ . ":" . __LINE__ );
      }
    }
  }
}

#
# this protocol accepts perf data file (from hyperv), stores it to tmpdir/< 1st atom contain >/< 2nd atom contain >/<filename is 8th atom contain>
# for future: you can use 1st & 2nd atom as a config and on this base you can choose dir for saving files
#
sub store_data_63 {
  my $data             = shift;         # this is pointer !!
  my $last_rec         = shift;
  my $protocol_version = shift;
  my $peer_address     = shift;
  my $en_last_rec      = $last_rec;
  my $act_time         = localtime();

  $wrkdir = "$basedir/data";            #cause this can be changed by external NMON processing

  # print $$data;
  # print "data_end\n";

  #example of $data here incl item names for docum purpose ! data is one line !
  # HYPERV:Notebook:::Wed Feb 12 11:58:34 2014:file_name:file_length:::file_content i.e. data to transfer
  # data to transfer is test file but char pipe"|" is used as eol because of different eol in Windows and Linux
  # char pipe"|" in orig data is hardcoded as "=====svislitko====="

  ( my $folder_name, my $subfolder_name, undef, undef, my $date1, my $date2, my $date3, my $filename, my $file_length ) = split( ":", $$data );

  my $dir_name = "$tmpdir/$folder_name";
  if ( !-d $dir_name ) {
    mkdir( $dir_name, 0777 ) || error( "Can't mkdir $dir_name: $!" . __FILE__ . ":" . __LINE__ ) && return 0;
  }
  $subfolder_name =~ s/=====colon=====/:/g;
  $dir_name = "$tmpdir/$folder_name/$subfolder_name";
  if ( !-d $dir_name ) {
    mkdir( $dir_name, 0777 ) || error( "Can't mkdir $dir_name: $!" . __FILE__ . ":" . __LINE__ ) && return 0;
  }
  my $perf_file   = "$dir_name/$filename";
  my $perf_string = ( split( ":", $$data, 12 ) )[11];
  my $size        = length $perf_string;

  # create linux eol
  $perf_string =~ tr/\|/\n/;
  $perf_string =~ s/=====svislitko=====/\|/g;

  open( PERF_FILE, ">", $perf_file ) || error( "Can't open $perf_file: $!" . __FILE__ . ":" . __LINE__ ) && return 0;
  print PERF_FILE $perf_string;    # "$file_content\n";
  close(PERF_FILE);
  return $size;
}

sub service_now {
  use LWP::UserAgent;
  use HTTP::Request;
  use JSON;

  my $description     = shift;
  my $lpar            = shift;
  my $util            = shift;
  my $last_type       = shift;
  my $alert_type_text = shift;
  my $server_name     = shift;
  my $unit            = shift;
  my $service_now     = shift;

  my $url                       = "https://$service_now->{'IP'}.service-now.com/api/global/em/jsonv2";
  my $error                     = "";
  my $alert_service_now_history = "$basedir/logs/alert_history_service_now.log";
  open( SN, ">> $alert_service_now_history" ) || error( "could not open $alert_service_now_history: $! " . __FILE__ . ":" . __LINE__ ) && return 1;
  print SN "#######################################\n";
  print SN "PRINT FROM DAEMON LPAR\n";

  #FOR DEBUG
  if ( $ENV{SERVICE_NOW_DEBUG} ) {
    print SN "#### DEBUG ####\n";
    print SN "DATA FROM GUI\n\n";
    print SN " USER: $service_now->{'USER'}\n PASSWORD: $service_now->{'PASSWORD'}\n INSTANCE NAME: $service_now->{'IP'}\n EVENT: $service_now->{'EVENT'}\n TYPE: $service_now->{'TYPE'}\n SEVERITY: $service_now->{'SEVERITY'}\n";
    print SN "\nEND DATA FROM GUI\n\n";

    print SN "CURL FOR TESTING\n";
    print SN "curl -i -X POST -k -u \"$service_now->{'USER'}:$service_now->{'PASSWORD'}\" -H \"Content-Type: application/json\" -H \"Accept: application/json\" $url -d '{\"records\":[{\"source\":\"lpar2rrd\",\"event_class\":\"$service_now->{'EVENT'}\",\"resource\":\"$lpar\",\"node\":\"$server_name\",\"metric_name\":\"$alert_type_text\",\"type\":\"$service_now->{'TYPE'}\",\"severity\":\"$service_now->{'SEVERITY'}\",\"description\":\"$description\"}]}'\n\n";

    print SN "#### END DEBUG ####\n";
  }

  if ( $service_now->{'USER'} eq "" ) {
    print SN "SERVICE NOW USER must be set!\n";
    $error = "error";
  }
  if ( $service_now->{'PASSWORD'} eq "" ) {
    print SN "SERVICE NOW PASSWORD must be set!\n";
    $error = "error";
  }
  if ( $service_now->{'IP'} eq "" ) {
    print SN "SERVICE NOW INSTANCE NAME must be set!\n";
    $error = "error";
  }

  if ( $error eq "error" ) {
    print SN "ERROR: required attributes have not been filled in\n";
    close(SN);
    return 1;
  }

  my %json_body = ();

  if ( $ENV{EVERSOURCE} ) {
    print SN "EVERSOURCE DAEMON\n";
    %json_body = (
      "records" => [
        { "source"      => "lpar2rrd",
          "event_class" => "$service_now->{'EVENT'}",      #lpar2rrd CPU alert for POOL
          "resource"    => "$lpar",                        #shared1
          "node"        => "$lpar",                        #shared1
          "metric_name" => "$alert_type_text",             #CPU
          "type"        => "$alert_type_text",
          "severity"    => "$service_now->{'SEVERITY'}",
          "description" => "$description"                  #Mon May 23 13:07:06 2022: CPU alert for: POOL: shared1 server: Power770 managed by: vhmc.int.xorux.com avg utilization during last 5 mins: 0.029 (CPU MAX limit: 0 actual util: 0.029, SharedPool1)
        }
      ]
    );
  }
  else {
    %json_body = (
      "records" => [
        { "source"      => "lpar2rrd",
          "event_class" => "$service_now->{'EVENT'}",      #lpar2rrd CPU alert for POOL
          "resource"    => "$lpar",                        #shared1
          "node"        => "$server_name",                 #Power770
          "metric_name" => "$alert_type_text",             #CPU
          "type"        => "$service_now->{'TYPE'}",
          "severity"    => "$service_now->{'SEVERITY'}",
          "description" => "$description"                  #Mon May 23 13:07:06 2022: CPU alert for: POOL: shared1 server: Power770 managed by: vhmc.int.xorux.com avg utilization during last 5 mins: 0.029 (CPU MAX limit: 0 actual util: 0.029, SharedPool1)
        }
      ]
    );
  }

  my $body = encode_json( \%json_body );

  my $agent   = LWP::UserAgent->new( ssl_opts => { verify_hostname => 0, SSL_verify_mode => 0 } );
  my $request = HTTP::Request->new( POST => $url );

  $request->header( 'Content-Type' => 'application/json', 'Accept' => 'application/json' );
  $request->authorization_basic( $service_now->{'USER'}, $service_now->{'PASSWORD'} );
  $request->content($body);

  my $results   = $agent->request($request);
  my $ltime_str = localtime();
  print SN "TIME: $ltime_str\n";
  print SN "POST url     : $url\n";
  print SN "JSON BODY\n\n";
  print SN "$body\n\n";
  if ( !$results->is_success ) {
    my $st_line = $results->status_line;
    my $res_con = $results->content;
    print SN "Request error: $st_line\n";
    print SN "Request error: $res_con\n";
    print SN "#######################################\n";
  }
  else {
    print SN "SUCCESS STATUS LINE: $results->status_line\n";
    print SN "#######################################\n";
  }
  close(SN);
  return 1;

}

sub jira_cloud {
  use LWP::UserAgent;
  use HTTP::Request;
  use JSON;

  my $description     = shift;
  my $lpar            = shift;
  my $util            = shift;
  my $last_type       = shift;
  my $alert_type_text = shift;
  my $server_name     = shift;
  my $unit            = shift;
  my $jira_cloud      = shift;

  my $subject   = "$alert_type_text alert for: $last_type";
  my $ltime_str = localtime();

  my $alert_jira_cloud_history = "$basedir/logs/alert_history_jira_cloud.log";
  open( JC, ">> $alert_jira_cloud_history" ) || error( "could not open $alert_jira_cloud_history: $! " . __FILE__ . ":" . __LINE__ ) && return 1;
  print JC "#######################################\n";
  print JC "PRINT from daemon\n";
  print JC "TIME : $ltime_str\n";
  print JC "\n";
  print JC "summary     : $subject\n";
  print JC "description : $description\n";
  print JC "project key : $jira_cloud->{PROJECT_KEY}\n";
  print JC "issue id    : $jira_cloud->{ISSUE_ID}\n";

  my %json_body = (
    "create" => {
      "worklog" => [
        { "add" => {
            "timeSpent" => "60m",
            "started"   => "$ltime_str"
          }
        }
      ]
    },
    "fields" => {
      "summary"     => "$subject",
      "description" => "$description",
      "project"     => { "key" => "$jira_cloud->{PROJECT_KEY}" },
      "issuetype"   => { "id"  => "$jira_cloud->{ISSUE_ID}" }
    }
  );

  my $body = encode_json( \%json_body );

  my $agent   = LWP::UserAgent->new( ssl_opts => { verify_hostname => 0, SSL_verify_mode => 0 } );
  my $request = HTTP::Request->new( POST => $jira_cloud->{URL} );

  $request->header( 'Content-Type' => 'application/json', 'Accept' => 'application/json' );
  $request->authorization_basic( $jira_cloud->{USER}, $jira_cloud->{TOKEN} );
  $request->content($body);

  my $results = $agent->request($request);

  if ( !$results->is_success ) {
    my $st_line = $results->status_line;
    my $res_con = $results->content;
    print JC "Request error: $st_line\n";
    print JC "Request error: $res_con\n";
  }
  else {
    print JC "SUCCESS\n";
  }

  print JC "\n";
  print JC "END\n";
  print JC "#######################\n";
  close(JC);
  return (1);

}

sub opsgenie {
  use LWP::UserAgent;
  use HTTP::Request;
  use JSON;

  my $description     = shift;
  my $lpar            = shift;
  my $util            = shift;
  my $last_type       = shift;
  my $alert_type_text = shift;
  my $server_name     = shift;
  my $unit            = shift;
  my $opsgenie        = shift;
  my $url             = $opsgenie->{'URL'};

  my $subject   = "$alert_type_text alert for: $last_type";
  my $ltime_str = localtime();

  my $alert_opsgenie_history = "$basedir/logs/alert_history_opsgenie.log";
  open( OPS, ">> $alert_opsgenie_history" ) || error( "could not open $alert_opsgenie_history: $! " . __FILE__ . ":" . __LINE__ ) && return 1;
  print OPS "#######################################\n";
  print OPS "PRINT from daemon\n";
  print OPS "TIME : $ltime_str\n";
  print OPS "\n";
  print OPS "summary     : $subject\n";
  print OPS "description : $description\n";
  print OPS "Key         : $opsgenie->{'KEY'}\n";
  print OPS "URL         : $opsgenie->{'URL'}\n";

  my %json_body = (
    "message"     => "$subject",
    "description" => "$description"
  );

  my $body = encode_json( \%json_body );

  my $agent   = LWP::UserAgent->new( ssl_opts => { verify_hostname => 0, SSL_verify_mode => 0 } );
  my $request = HTTP::Request->new( POST => $url );

  $request->header( 'Content-Type' => 'application/json', 'Accept' => 'application/json', 'Authorization' => 'GenieKey ' . $opsgenie->{'KEY'} . '' );
  $request->content($body);

  my $results = $agent->request($request);

  if ( !$results->is_success ) {
    my $st_line = $results->status_line;
    my $res_con = $results->content;
    print OPS "Request error: $st_line\n";
    print OPS "Request error: $res_con\n";
  }
  else {
    print OPS "SUCCESS\n";
  }

  print OPS "\n";
  print OPS "END\n";
  print OPS "#######################\n";
  close(OPS);
  return (1);

}

