use strict;
use Date::Parse;
use Time::Local;
use RRDp;
use Xorux_lib;
use PowerDataWrapper;

# it runs only if not exist tmp/lpars_count-run or it has previous day timestamp

# set unbuffered stdout
$| = 1;

# get cmd line params
my $version = "$ENV{version}";
my $webdir  = $ENV{WEBDIR};
my $bindir  = $ENV{BINDIR};
my $basedir = $ENV{INPUTDIR};
my $tmpdir  = "$basedir/tmp";
if ( defined $ENV{TMPDIR_LPAR} ) {
  $tmpdir = $ENV{TMPDIR_LPAR};
}
my $rrdtool                 = $ENV{RRDTOOL};
my $pic_col                 = $ENV{PICTURE_COLOR};
my $DEBUG                   = $ENV{DEBUG};
my $upgrade                 = $ENV{UPGRADE};
my $managed_systems_exclude = $ENV{MANAGED_SYSTEMS_EXCLUDE};
my $wrkdir                  = "$basedir/data";
my $lpars_count_log         = "$basedir/logs/lpars_count.log";    # log output
my $lpars_count_run         = "$tmpdir/lpars_count-run";
my $filelpst                = "$tmpdir/daily_lpar_check.txt";
my $act_time                = localtime();

RRDp::start "$rrdtool";

=begin comment # use new data wrappers
foreach my $hmc (@{ PowerDataWrapper::get_items('HMC') }){
  my $hmc_uid = (keys %{ $hmc })[0];
  my $hmc_name = PowerDataWrapper::get_label('HMC', $hmc_uid);
  my $s_count = PowerDataWrapper::getServerCount($hmc_uid);
  my $l_count = PowerDataWrapper::getLparCount($hmc_uid);
  update_rrx( $hmc_name, $s_count, $l_count );
  warn "Rest API : $hmc_name has $s_count servers and $l_count lpars\n";
}
exit(0);
=cut

# disable Tobi's promo
#my $disable_rrdtool_tag = "COMMENT: ";
#my $disable_rrdtool_tag_agg = "COMMENT:\" \"";
my $disable_rrdtool_tag     = "--interlaced";    # just nope string, it is deprecated anyway
my $disable_rrdtool_tag_agg = "--interlaced";    # just nope string, it is deprecated anyway
my $rrd_ver                 = $RRDp::VERSION;
if ( isdigit($rrd_ver) && $rrd_ver > 1.35 ) {
  $disable_rrdtool_tag     = "--disable-rrdtool-tag";
  $disable_rrdtool_tag_agg = "--disable-rrdtool-tag";
}

if ( !-f $lpars_count_run ) {
  `touch $lpars_count_run`;    # first run after install
  print "lpars_count    : first run after install 01\n";
}
else {
  my $run_time = ( stat("$lpars_count_run") )[9];
  ( my $sec, my $min, my $h, my $aday, my $m, my $y, my $wday, my $yday, my $isdst ) = localtime( time() );
  ( $sec, $min, $h, my $png_day, $m, $y, $wday, $yday, $isdst ) = localtime($run_time);
  if ( $aday == $png_day ) {

    # If it is the same day then do not update except upgrade
    if ( $upgrade == 0 ) {
      print "lpars_count    : not this time $aday == $png_day\n";
      exit(0);    # run just once a day per timestamp on graphs
    }
    else {
      print "lpars_count    : run it as first run after the upgrade : $upgrade\n";
    }
  }
  else {
    print "lpars_count   : first run after the midnight 02: $aday != $png_day\n";
    `touch $lpars_count_run`;
  }
}

# read lpars info, choose those OK, sort according to hmc

#open FH,"< $filelpst" or die "Cannot read the file $filelpst: $!\n";
open( FH, "< $filelpst" ) || error( "Cannot open $filelpst: $!" . __FILE__ . ":" . __LINE__ ) && exit 1;
my @lines = <FH>;
close(FH);

#print join("", @lines);

my ( @lines1, @lines2 );
my $count_servers_lpars;
while ( my $line = shift @lines ) {
  chomp($line);

  # Power770,vhmc,shared2,OK,2020-02-25 09:43,poool
  if ( $line =~ m/poool/ ) {
    my ( $server_name, $hmc_name, $pool_name, $status, $timestamp, $type ) = split( ',', $line );
    $count_servers_lpars->{$hmc_name}{$server_name}{pools}{$pool_name} = $status if ( $line !~ m/InFo_lpar/ );
    if ( $line =~ m/InFo_lpar/ ) {    #HD - delete rrx files for servers, bug from months ago
      my $server = $hmc_name;
      unlink("$wrkdir/$server.rrx") if ( -e "$wrkdir/$server.rrx" );
    }
  }
  elsif ( $line =~ m/rrm/ ) {

    # Power770,vhmc,p770-demo.rrm,OK,2020-02-25 09:43
    my ( $server_name, $hmc_name, $lpar_name, $status, $timestamp ) = split( ',', $line );
    $count_servers_lpars->{$hmc_name}{$server_name}{lpars}{$lpar_name} = $status if ( $line !~ m/InFo_lpar/ && $line !~ m/InFo_hmc/ );
    if ( $line =~ m/InFo_lpar/ ) {    #HD - delete rrx files for servers, bug from months ago
      my $server = $hmc_name;
      unlink("$wrkdir/$server.rrx") if ( -e "$wrkdir/$server.rrx" );
    }
  }

  # looking for lpars OK

  if ( !( ( $line =~ m/InFo/ ) || ( $line =~ m/poool/ ) || ( $line =~ m/\.mmm/ ) ) ) {
    my @lpar_info = split( ',', $line );

    #   if ( $lpar_info[3] eq "OK" || 1) {  #HD, add it anyway, count is done differently now, also add $lpar_info[3] to the line
    #
    #   }
    push( @lines1, "$lpar_info[1],$lpar_info[0],$lpar_info[2],$lpar_info[3]\n" );
  }
}

#print join("", @lines1);

my @sorted_lines = sort @lines1;

# print "after sort \n";
# print join("", @sorted_lines);

my $s_num  = 0;
my $l_num  = 0;
my $is_hmc = 0;
my ( $hmc_name, $s_name );
my ( $act_h, $act_s, $act_l );

# use different counting method

=begin comment
while ( my $line = shift @sorted_lines) {
  ( $act_h, $act_s, $act_l ) = split( ',', $line );


  if ( $is_hmc == 0 ) {
    $is_hmc   = 1;
    $hmc_name = $act_h;
    $s_name   = $act_s;
    $s_num++;
    $l_num++;
  } ## end if ( $is_hmc == 0 )
  else {
    if ( $hmc_name eq $act_h ) {    # same hmc
      if ( $s_name eq $act_s ) {    # same server
        $l_num++;
      }
      else {                        # next server
        $s_name = $act_s;
        $s_num++;
        $l_num++;
      }
    } ## end if ( $hmc_name eq $act_h)
    else {                          # next hmc
                                    #   print "lpars_count   :hmc $hmc_name has servers: $s_num, lpars: $l_num\n";

      #$s_num =15 ; $l_num = 158;
      update_rrx( $hmc_name, $s_num, $l_num );
      $hmc_name = $act_h;
      $s_name   = $act_s;
      $s_num    = 1;
      $l_num    = 1;
    } ## end else [ if ( $hmc_name eq $act_h)]
  } ## end else [ if ( $is_hmc == 0 ) ]
} ## end while ( my $line = shift ...)
=cut

foreach my $hmc ( keys %{$count_servers_lpars} ) {
  my $s_num_n = 0;
  my $l_num_n = 0;
  foreach my $server ( keys %{ $count_servers_lpars->{$hmc} } ) {
    $s_num_n++;
    foreach my $lpar ( keys %{ $count_servers_lpars->{$hmc}{$server}{lpars} } ) {
      $l_num_n++ if $count_servers_lpars->{$hmc}{$server}{lpars}{$lpar} eq 'OK';
    }
  }
  print "Counts per HMC : $hmc, servers: $s_num_n, lpars: $l_num_n\n";
  update_rrx( $hmc, $s_num_n, $l_num_n );
}

#if ( $is_hmc ne 0 ) {
#
#  print "Counts per HMC : $hmc_name, servers: $s_num, lpars: $l_num\n";
#  update_rrx( $hmc_name, $s_num, $l_num );
#}
print "lpars_count    : finished\n";

exit(0);

sub update_rrx {    # update (create if not exists)
  my $hmc      = shift;
  my $s_num    = shift;
  my $l_num    = shift;
  my $rrx_name = "$wrkdir/$hmc\.rrx";

  # test if exists database for lpars and servers for hmc
  if ( !-f $rrx_name ) {

    #initialise  rrx for servers and lpars count
    RRDp::cmd qq(create "$rrx_name"  --step "86400"
        "DS:servers:GAUGE:172800:0:48"
        "DS:lpars:GAUGE:172800:0:9999"
        "RRA:MAX:0.5:1:1500"
        "RRA:AVERAGE:0.5:1:1500"
        "RRA:LAST:0.5:1:1"
      );
    if ( !Xorux_lib::create_check("file: $rrx_name, 1500, 1500, 1") ) {
      error( "unable to create $rrx_name: at " . __FILE__ . ": line " . __LINE__ );
      RRDp::end;
      RRDp::start "$rrdtool";
      exit(1);
    }
  }
  RRDp::cmd qq(update "$rrx_name" N:$s_num:$l_num);
  my $answer = RRDp::read;
  if ($$answer) {
    error("unable to update $rrx_name: answer: $$answer");
    exit(1);
  }

  #print "updated $rrx_name, servers $s_num, lpars $l_num\n";
}

# error handling
sub error {
  my $text     = shift;
  my $act_time = localtime();
  chomp($text);

  # print "ERROR          : $text : $!\n";
  print STDERR "$act_time: $text : $!\n";

  return 1;
}

sub isdigit {
  my $digit = shift;

  my $digit_work = $digit;
  $digit_work =~ s/[0-9]//g;
  $digit_work =~ s/\.//;

  if ( length($digit_work) == 0 ) {

    # is a number
    return 1;
  }

  #if (($digit * 1) eq $digit){
  #  # is a number
  #  return 1;
  #}

  # NOT a number
  #error ("there was expected a digit but a string is there, field: $text , value: $digit");
  return 0;
}
