use strict;
use warnings;
use Date::Parse;
use Xorux_lib;
use HostCfg;

my %hosts = %{ HostCfg::getHostConnections("IBM Power Systems") };

# uncoment&adjust if you want to use your own ssh identification file
#my $SSH = "ssh -i $ENV{HOME}/.ssh/lpar2rrd";
my $SSH = $ENV{SSH} . " ";

# set unbuffered stdout
$| = 1;

# get cmd line params
my $host = $ENV{HMC};
my $hea  = $ENV{HEA};
my $hmc_user;

#use from host config 23.11.18 insted of $hmc_user=ENV{HMC_USER} (HD)
foreach my $hmc_alias ( keys %hosts ) {
  if ( $host eq $hosts{$hmc_alias}{host} && $hosts{$hmc_alias}{auth_api} ) {
    print "Exit : HEA adapters for $host ($hmc_alias)\n";
    exit;
  }
  if ( $host eq $hosts{$hmc_alias}{host} ) {
    $hmc_user = $hosts{$hmc_alias}{username};
    $SSH      = $hosts{$hmc_alias}{ssh_key_id};
  }
}

my $webdir  = $ENV{WEBDIR};
my $basedir = $ENV{INPUTDIR};
my $rrdtool = $ENV{RRDTOOL};
my $DEBUG   = $ENV{DEBUG};

#$DEBUG="2";
my $pic_col                 = $ENV{PICTURE_COLOR};
my $STEP_HEA                = $ENV{STEP_HEA};
my $HWINFO                  = $ENV{HWINFO};
my $managed_systems_exclude = $ENV{MANAGED_SYSTEMS_EXCLUDE};
my $SYS_CHANGE              = $ENV{SYS_CHANGE};
my $MONTH_REFRESH           = 20000;                           # minimum time in sec when monthly graphs are updated (refreshed)
my $WEEK_REFRESH            = 7000;                            # minimum time in sec when weekly  graphs are updated (refreshed)

my $wrkdir          = "$basedir/data";
my @managednamelist = "";

my $timeout = 60;
my $model   = "";
my $serial  = "";
my $line    = "";

my $act_time = localtime();

#my $t = str2time($act_time);
my $t = "";

# start RRD via a pipe
use RRDp;
RRDp::start "$rrdtool";

main();

# close RRD pipe
RRDp::end;
exit(0);

sub main {

  # set alarm on first SSH command to make sure it does not hang
  eval {
    local $SIG{ALRM} = sub { die "$act_time: died in SIG ALRM"; };
    alarm($timeout);

    # get list of serveres managed through HMC
    @managednamelist = `$SSH $hmc_user\@$host "lssyscfg -r sys -F name,type_model,serial_num" 2>/dev/null`;
    alarm(0);
    if ( $managednamelist[0] =~ "no address associated with hostname" ) {
      print "HMC : $host does not exist\n"        if $DEBUG;
      print STDERR "HMC : $host does not exist\n" if $DEBUG;
      exit(0);
    }
  };
  if ($@) {
    if ( $@ =~ /died in SIG ALRM/ ) {
      print "*****WARNING*****WARNING*****WARNING*****\n";
      print "SSH command timed out after : $timeout seconds\n";
      print "Check why it takes so long, might be some network or authentification problems on the HMC\n";
      print "# ssh $hmc_user\@$host \"lssyscfg -r sys -F name\"\n";
      print "Continue with the other HMCs\n";
      print "*****WARNING*****WARNING*****WARNING*****\n";
      print STDERR "act_time : \n";
      print STDERR "SSH command timed out after : $timeout seconds\n";
      print STDERR "Check why it takes so long, might be some network or authentification problems on the HMC\n";
      print STDERR "# ssh $hmc_user\@$host \"lssyscfg -r sys -F name\"\n";
      print STDERR "Continue with the other HMCs\n";
      exit(1);
    }
  }

  # here must be local time on HMC, need Unix time and date in text to have complete time
  my $time = `$SSH $hmc_user\@$host "LC_ALL=en_US LANG=en_US LC_NUMERIC=en_US date \'+%m/%d/%Y %H:%M:%S\'" 2>/dev/null`;
  if ( defined($time) && $time ne '' ) {
    chomp($time);
  }
  else {
    print STDERR "$act_time : $host: No valid data time format got from HMC : empty string\n";
    return 0;
  }
  $t = str2time( substr( $time, 0, 19 ) );

  if ( length($t) < 10 ) {

    # leave it as wrong input data
    print "$host: No valid lpar data time format got from HMC\n";
    print STDERR "$act_time : $host: No valid data time format got from HMC $time:$t\n";
    return 0;
  }

  my $managed_ok;
  my $managedname_exl = "";
  my $managedname     = "";
  my @m_excl          = "";

  foreach my $line (@managednamelist) {
    chomp($line);

    if ( $line =~ m/Error:/ || $line =~ m/Permission denied/ ) {
      next;    # just ignore it here ...
    }

    if ( $line !~ ".*,.*,.*" ) {

      # it must look like : PWR6A-9117-MMA-SN103A4B0,9117-MMA,103A4B0, --> exclude banners
      next;
    }
    print "3- $line\n" if ( $DEBUG == 2 );

    ( $managedname, my $model, my $serial ) = split( /,/, $line );

    if ( is_IP($managedname) ) {
      next;    # wrong entry from the HMC, a problem of the HMC or unconfigured server yet
    }

    $managed_ok = 1;
    if ( defined($managed_systems_exclude) && $managed_systems_exclude ne '' ) {
      @m_excl = split( /:/, $managed_systems_exclude );
      foreach $managedname_exl (@m_excl) {
        chomp($managedname_exl);
        if ( $managedname =~ m/^$managedname_exl$/ ) {
          $managed_ok = 0;
        }
      }
    }
    if ( $managed_ok == 0 ) {
      next;
    }
    print "4- $managedname -- $model -- $serial\n" if ( $DEBUG == 2 );
    hea($managedname);
    fcs($managedname);

  }
  return 1;
}

sub fcs {
  my $managedname = shift;
  my $fcs_port    = "";
  my $fcs_in      = "";
  my $fcs_out     = "";
  my $count       = 0;

  if ( !-f "$wrkdir/$managedname/$host/IVM" ) {
    return 0;
  }

  if ( !-d "$wrkdir/$managedname" ) {

    # do not create "$wrkdir/$managedname" as then does not work automatical server rename!!!!
    print "data dir not ex: $wrkdir/$managedname does not exist, not creating it here .... skipping\n" if $DEBUG;
    return 1;
  }

  if ( !-d "$wrkdir/$managedname/$host" ) {
    print "mkdir          : $wrkdir/$managedname/$host\n" if $DEBUG;
    mkdir( "$wrkdir/$managedname/$host", 0755 ) || die "$act_time: Cannot mkdir $wrkdir/$managedname/$host: $!";
  }

  my $fcs_list = `$SSH $hmc_user\@$host "LC_ALL=en_US LANG=en_US LC_NUMERIC=en_US ioscli lsdev 2>&1|grep fcs|awk '{print \\\$1}'" 2>/dev/null|xargs 2>&1`;
  print "$fcs_list\n" if ( $DEBUG == 2 );

  my @fcs_sum = `$SSH $hmc_user\@$host "for i in \`echo $fcs_list\`; do echo \"\\\$i\"; LC_ALL=en_US LANG=en_US LC_NUMERIC=en_US ioscli fcstat \\\$i|grep \" Bytes: \"|tail -2|awk -F: '{print \\\$2}'|sed 's/ //g'; done" 2>/dev/null`;

  foreach my $fcs_line (@fcs_sum) {
    chomp($fcs_line);
    print "5- $fcs_line\n" if ( $DEBUG == 2 );
    if ( $fcs_line =~ "fcs" ) {
      $fcs_port = $fcs_line;
      $count    = 0;
      next;
    }
    if ( $count == 0 ) {
      $fcs_in = "$fcs_line";
      $count++;
      next;
    }
    if ( $count == 1 ) {
      $fcs_out = "$fcs_line";
      $count++;
    }
    my $ret = substr( $fcs_line, 0, 1 );
    if ( $ret =~ /\D/ ) {

      # if it is not a digit then skip it
      next;
    }
    print "6- $fcs_port:$fcs_in:$fcs_out \n" if ( $DEBUG == 2 );

    my $rrd    = "$wrkdir/$managedname/$host/$fcs_port.db";
    my $answer = create_db_fcs( $rrd, $t );
    if ($answer) {
      RRDp::cmd qq(update "$rrd" $t:$fcs_in:$fcs_out);
      $answer = RRDp::read;
    }
  }
  return 1;
}

sub hea {
  my $managedname = shift;
  my @hea_sum     = "";

  my $HMCIVM = 1;
  if ( -f "$wrkdir/$managedname/$host/IVM" ) {
    my $HMCIVM = 0;
  }

  if ( !-d "$wrkdir/$managedname" ) {

    # do not create "$wrkdir/$managedname" as then does not work automatical server rename!!!!
    print "data dir not ex: $wrkdir/$managedname does not exist, not creating it here .... skipping\n" if $DEBUG;
    return 1;
  }

  if ( !-d "$wrkdir/$managedname/$host" ) {
    print "mkdir          : $wrkdir/$managedname/$host\n" if $DEBUG;
    mkdir( "$wrkdir/$managedname/$host", 0755 ) || die "$act_time: Cannot mkdir $wrkdir/$managedname/$host: $!";
  }

  if ( $HMCIVM == 1 ) {
    @hea_sum = `$SSH $hmc_user\@$host "LC_ALL=en_US LANG=en_US LC_NUMERIC=en_US lshwres -r hea -m \\"$managedname\\" --rsubtype phys --stat --level port -F 2>&1" 2>/dev/null`;
  }
  else {
    @hea_sum = `$SSH $hmc_user\@$host "LC_ALL=en_US LANG=en_US LC_NUMERIC=en_US lshwres -r hea --rsubtype phys --stat --level port -F 2>&1" 2>/dev/null`;
  }

  foreach my $hea_line (@hea_sum) {
    chomp($hea_line);
    print "5- $hea_line\n" if ( $DEBUG == 2 );
    if ( $hea_line =~ "HSCL" || $hea_line =~ "VIOSE0" ) {

      #print "No hea $managedname\n";
      next;
    }
    my $ret = substr( $hea_line, 0, 1 );
    if ( $ret =~ /\D/ ) {

      # if it is not a digit then skip it
      next;
    }
    print "6- $hea_line -- $ret\n" if ( $DEBUG == 2 );

    my $port = "";
    ( my $adapter_id, my $port_group, my $phys_port_id, my $recv_octets, my $d1, my $d2, my $d3, my $d4, my $d5, my $d6, my $d7, my $d8, my $d9, my $d10, my $d11, my $d12, my $d13, my $d14, my $d15, my $d16, my $d17, my $d18, my $d19, my $d20, my $d21, my $d22, my $d23, my $d24, my $d25, my $d26, my $trans_octets, my $d28, my $d29, my $d30, my $d31, my $d32, my $d33, my $d34, my $d35, my $d36, my $d37, my $d38, my $d39, my $d40, my $d41, my $d42, my $d43, my $d44, my $d45, my $d46 ) = split( /,/, $hea_line );
    $recv_octets =~ s/"//;
    my $recv_err  = $d7 + $d8 + $d9 + $d10 + $d11 + $d12 + $d21 + $d22;
    my $trans_err = $d34 + $d36 + $d37 + $d38 + $d39 + $d40 + $d42 + $d43 + $d44 + $d45;
    if ( $port_group == 1 && $phys_port_id == 0 ) { $port = 1; }
    if ( $port_group == 1 && $phys_port_id == 1 ) { $port = 2; }
    if ( $port_group == 2 && $phys_port_id == 0 ) { $port = 3; }
    if ( $port_group == 2 && $phys_port_id == 1 ) { $port = 4; }
    print "7- $adapter_id:$port $recv_octets $trans_octets\n" if ( $DEBUG == 2 );

    my $rrd    = "$wrkdir/$managedname/$host/hea-$adapter_id-port$port.db";
    my $answer = create_db( $rrd, $t );
    if ($answer) {
      print "8- $t:$recv_octets:$recv_err:$trans_octets:$trans_err $rrd\n" if ( $DEBUG == 2 );
      RRDp::cmd qq(update "$rrd" $t:$recv_octets:$recv_err:$trans_octets:$trans_err);
      $answer = RRDp::read;
    }
  }
  return 1;
}

sub create_db {
  my $rrd = shift;
  my $t   = shift;
  if ( not -f $rrd ) {
    my $hb = 2 * $STEP_HEA;
    print "creating new db: $rrd ; STEP=$STEP_HEA\n" if $DEBUG;
    RRDp::cmd qq(create "$rrd"  --start "$t" --step "$STEP_HEA"
			"DS:recv_octets:COUNTER:$hb:0:U"
			"DS:recv_octets_err:COUNTER:$hb:0:U"
			"DS:trans_octets:COUNTER:$hb:0:U"
			"DS:trans_octets_err:COUNTER:$hb:0:U"
			"RRA:AVERAGE:0.5:1:10000"
			"RRA:AVERAGE:0.5:6:1500"
			"RRA:AVERAGE:0.5:24:1000"
			"RRA:AVERAGE:0.5:288:1000"
	);
    if ( !Xorux_lib::create_check("file: $rrd, 10000, 1500, 1000, 1000") ) {
      die( "$act_time: unable to create $rrd : at " . __FILE__ . ": line " . __LINE__ );
      RRDp::end;
      RRDp::start "$rrdtool";
      return 0;
    }
  }
  return 1;
}

sub create_db_fcs {
  my $rrd = shift;
  my $t   = shift;
  if ( not -f $rrd ) {
    my $hb = 2 * $STEP_HEA;
    print "creating new db: $rrd ; STEP=$STEP_HEA\n" if $DEBUG;
    RRDp::cmd qq(create "$rrd"  --start "$t" --step "$STEP_HEA"
	"DS:recv_bytes:COUNTER:$hb:0:U"
	"DS:trans_bytes:COUNTER:$hb:0:U"
	"RRA:AVERAGE:0.5:1:10000"
	"RRA:AVERAGE:0.5:6:1500"
	"RRA:AVERAGE:0.5:24:1000"
	"RRA:AVERAGE:0.5:288:1000"
	);
    if ( !Xorux_lib::create_check("file: $rrd, 10000, 1500, 1000, 1000") ) {
      die( "$act_time: unable to create $rrd : at " . __FILE__ . ": line " . __LINE__ );
      RRDp::end;
      RRDp::start "$rrdtool";
      return 0;
    }
  }
  return 1;
}

# return 1 if the argument is valid IP, otherwise 0
sub is_IP {
  my $ip = shift;

  if ( $ip =~ /^(\d{1,3})\.(\d{1,3})\.(\d{1,3})\.(\d{1,3})$/ && ( ( $1 <= 255 && $2 <= 255 && $3 <= 255 && $4 <= 255 ) ) ) {
    return 1;
  }
  else {
    return 0;
  }
}

