use strict;
use Date::Parse;
use LoadDataModule;
use RRDp;
use Data::Dumper;
use HostCfg;
use XoruxEdition;
use JSON;
use MIME::Base64 qw(encode_base64 decode_base64);
use Alerting;

# set unbuffered stdout
$| = 1;

# get cmd line params
my $upgrade = "$ENV{UPGRADE}";
my $version = "$ENV{version}";
my $hea     = $ENV{HEA};

#use from host config 23.11.18 HD
my $hmc_user;    #     = $ENV{HMC_USER};
my $host;        #     = $ENV{HMC};
my $webdir  = $ENV{WEBDIR};
my $bindir  = $ENV{BINDIR};
my $basedir = $ENV{INPUTDIR};
my $tmpdir  = "$basedir/tmp";
if ( defined $ENV{TMPDIR_LPAR} ) {
  $tmpdir = $ENV{TMPDIR_LPAR};
}
my $cpu_max_filter = 100;    # max 100 core peaks are allowed in graphs
if ( defined $ENV{CPU_MAX_FILTER} ) {
  $cpu_max_filter = $ENV{CPU_MAX_FILTER};
}
my $alert_test    = "";
my $alerting_rest = "";
my $restapi       = "";
$alerting_rest = $ENV{ALERTING_REST} if defined $ENV{ALERTING_REST};
$restapi       = is_any_host_rest();
$alert_test    = $ENV{ALERT_TEST} if defined $ENV{ALERT_TEST};
if ( !defined($alert_test) ) {    # || isdigit($alert_test) == 0 )  left_curly
  $alert_test = 0;
}
elsif ( isdigit($alert_test) == 0 ) {
  $alert_test = 0;
}

my %hosts_configuration = %{ HostCfg::getHostConnections("IBM Power Systems") };

my %t = Alerting::getAlerts;
my $alert_def;
my $add = "add_lpar";
my $i   = 0;

foreach my $key ( sort keys %t ) {
  $alert_def->{$key} = $add if ( $i < length($add) - 5 );
  $i++;
}

my $rrdtool = $ENV{RRDTOOL};
my $DEBUG   = $ENV{DEBUG};


#$DEBUG = 2;
my $pic_col                 = $ENV{PICTURE_COLOR};
my $STEP                    = $ENV{SAMPLE_RATE};
my $no_time                 = $STEP * 6;                       # says the time interval when RRDTOOL consideres a gap in input data
my $HWINFO                  = $ENV{HWINFO};
my $managed_systems_exclude = $ENV{MANAGED_SYSTEMS_EXCLUDE};
my $SYS_CHANGE              = $ENV{SYS_CHANGE};
my $STEP_HEA                = $ENV{STEP_HEA};
my $SSH                     = $ENV{SSH} . " -q ";              # doubles -q from lpar2rrd.cfg, just to be sure ...

# uncoment&adjust if you want to use your own ssh identification file
#my $SSH = $ENV{SSH}." -i ".$ENV{HOME}."/.ssh/lpar2rrd -o ConnectTimeout=5 -o StrictHostKeyChecking=no -o PreferredAuthentications=publickey";
my $new_change = "$tmpdir/$version-run";
my $wrkdir     = "$basedir/data";
my @lpar_trans = "";                       # lpar translation names/ids for IVM systems
my $alert_log  = "$basedir/alert.log";
my $time_diff  = 0;
my $act_time   = localtime();
my $nagios_dir = "$basedir/nagios";
my $hmcv_num   = 701;                      # suppouse no one is using older nowadays --> it is now checked for HMC due to AMS support
print "LPAR2RRD alert script v:$version, started: $act_time\n";
my $step        = $STEP;
my $HMC         = 1;
my $IVM         = 0;
my $SDMC        = 0;
my $input       = "m";
my $input_shell = "m";
my $type_sam    = "m";
my @lpar_p      = "";
my @lpar_a      = "";
my $cfg         = $ENV{ALERCFG};

#my $from_mail="lpar2rrd";
my $from_mail                = "support\@gmail.com";
my $subject                  = "High CPU utilization";
my $alert_repeat             = "$tmpdir/alert_repeat.tmp";
my $ltime_str                = localtime();
my $ltime                    = str2time($ltime_str);
my @emails_name              = "";
my @emails_addr              = "";
my $last_file_default        = "last.txt";
my $last_file                = "last-alrt.txt";
my $alert_history            = "";
my $mem_params               = "";
my $idle_param               = "";
my $repeat_default           = "";
my $cpu_average_time_default = "";
my $email_default            = "";
my @lines_rep                = "";
my $community_string         = "public";
my $web_ui_url               = "";

# swapping
my @lpar_all_list   = "";
my @server_list_all = "";

# use alert here to be sure it does not hang due to any problem
my $timeout = 600;    # it must be enough

### new alerting
my $new_alert = 0;

if ( -f "$basedir/etc/web_config/alerting.cfg" ) {
  $cfg       = "$basedir/etc/web_config/alerting.cfg";
  $new_alert = 1;
}
else {
  $cfg = "etc/alert.cfg";    ### old alerting
}

print "Alert configuration :$cfg\n";

eval {
  my $act_time = localtime();
  local $SIG{ALRM} = sub { die "died in SIG ALRM: "; };
  alarm($timeout);

  RRDp::start "$rrdtool";
  read_cfg();

  alarm(0);

  # close RRD pipe
  RRDp::end;
  my $unixt = str2time($act_time);
  $act_time = localtime();
  my $unixt_end = str2time($act_time);
  my $run_time  = $unixt_end - $unixt;
  print "Finished       : $act_time, run time: $run_time secs\n";
};

if ($@) {
  if ( $@ =~ /died in SIG ALRM/ ) {
    error("$0 timed out after : $timeout seconds");
  }
  else {
    error("$0 failed: $@");
  }
  exit(1);
}

exit(0);

sub colons {
  return s/===double-col===/:/g;
}

sub urldecode {
  my $s = shift;

  #$s =~ s/\%([A-Fa-f0-9]{2})/pack('C', hex($1))/seg;
  #$s =~ s/\+/ /g;
  $s =~ s/\%([A-Fa-f0-9]{2})/pack('C', hex($1))/seg;
  return $s;
}

sub find_server {
  my $type = shift;
  my $lpar = shift;

  my $last_hmc    = "";
  my $last_server = "";
  my $index       = 1;
  my %hmc_server_del;

  my @replace_file;
  my %pools;
  my %stree;        # Serverr
  my %vclusters;    # Servers nested by clusters
  my %lstree;       # LPARs by Server
  my %lhtree;       # LPARs by HMC
  my %vtree;        # VMware vCenter
  my %cluster;      # VMware Cluster
  my %respool;      # VMware Resource Pool
  my @lnames;       # LPAR name (for autocomplete)
  my %inventory;    # server / type / name
  my %times;        # server timestamps
  my $free;         # 1 -> free / 0 -> full
  my $hasPower;     # flag for IBM Power presence
  my $hasVMware;    # flag for WMware presence

  if ( !defined $lpar || $lpar eq "" ) {
    return "";
  }

  my $menu = "$tmpdir/menu.txt";
  open( FH, "< $menu" ) || error( "could not open $menu : $!" . __FILE__ . ":" . __LINE__ ) && return 1;
  my @lines = <FH>;
  close(FH);

  foreach my $line (@lines) {
    chomp $line;
    if ( $line eq "" ) { next; }

    my ( $hmc, $srv, $txt, $url );
    my @val = split( ':', $line );
    for (@val) {
      &colons($_);
    }
    {
      "O" eq $val[0] && do {
        $free = ( $val[1] == 1 ) ? 1 : 0;
        last;
      };
      "D" eq $val[0] && do {

        #$server_del = $val[2];
        if ( $val[1] eq $last_hmc && $val[2] eq $last_server ) {
          last;
        }
        $hmc_server_del{$index}{HMC}    = $val[1];
        $hmc_server_del{$index}{SERVER} = $val[2];
        $last_hmc                       = $val[1];
        $last_server                    = $val[2];
        $index++;
        last;
      };

      #S:ahmc11:BSRV21:CPUpool-pool:CPU pool:ahmc11/BSRV21/pool/gui-cpu.html::1399967748
      "S" eq $val[0] && do {
        my ( $hmc, $srv, $pool, $txt, $url, $timestamp, $type ) = ( $val[1], $val[2], $val[3], $val[4], $val[5], $val[7], $val[8] );
        if (1) {
          if ( !$timestamp ) {
            $timestamp = 999;
          }
          if ( $type eq "V" ) {
            $hasVMware ||= 1;
            $vclusters{$hmc}{$srv} = 1;
            if ( $pool eq "hreports" ) {
              $hmc = ( $url =~ /^([^\/]*)/ )[0];
            }
            else {
              $hmc = ( $url =~ /host=([^&]*)/ )[0];
            }
          }
          elsif ( !exists $times{$srv}{timestamp}{$hmc} ) {
            $times{$srv}{timestamp}{$hmc} = $timestamp;
          }
          if ( $type eq "P" ) {
            $hasPower ||= 1;
          }
          if ( !$times{$srv}{"active"} ) {
            $times{$srv}{"active"} = 1;
          }
          $times{$srv}{"removed"}{$hmc} = 0;
          if ($type) {
            $times{$srv}{type} = $type;
          }
          if ( $pool =~ /^CPUpool/ ) {
            $pool = substr( $pool, 8 );
          }
          elsif ( $pool eq "pagingagg" || $pool eq "mem" ) {
            $pool = "cod";
          }
          elsif ( $pool eq "hea" ) {
            $pool = "hea";
          }
          else {
            $pool = "";
          }
          push @{ $stree{$srv}{$hmc} }, [ $txt, $url, $pool ];
          if ( $url =~ /item=(sh)?pool/ ) {
            my $poolname = ( split " : ", $txt )[1];
            $poolname ||= "CPU pool";
            my $pools = $url;
            $pools =~ s/.*lpar=//g;
            $pools =~ s/&item.*//g;
            $inventory{$srv}{"POOL"}{$pools}{"NAME"} = $poolname;
            $inventory{$srv}{"POOL"}{$pools}{"URL"}  = $url;
            $inventory{$srv}{TIMESTAMP}{$timestamp}  = $hmc;
            $inventory{$srv}{TYPE}                   = $type;
          }
        }
        last;
      };
      "L" eq $val[0] && do {
        my ( $hmc, $srv, $atxt, $txt, $url ) = ( $val[1], $val[2], $val[3], $val[4], $val[5] );
        my $jump = 0;
        foreach my $i ( keys %hmc_server_del ) {
          if ( $hmc_server_del{$i}{HMC} eq $val[1] && $hmc_server_del{$i}{SERVER} eq $val[2] ) {
            $jump = 1;
            last;
          }
        }
        if ( $jump == 1 ) { last; }
        if (1) {
          $atxt = urldecode($atxt);
          push @{ $lstree{$srv}{$hmc} }, [ $txt, $url, $atxt ];
          if ( $hmc eq "no_hmc" ) {
            $times{$srv}{timestamp}{$hmc}    = 999;
            $inventory{$srv}{TIMESTAMP}{999} = $hmc;
            $inventory{$srv}{TYPE}           = 'L';
          }
          else {
            push @{ $lhtree{$hmc}{$srv} }, [ $txt, $url, $atxt ];
          }
          if ( $hmc eq "no_hmc" && !$times{$srv}{"active"} ) {
            $times{$srv}{"active"} = 1;
          }
          push @lnames, $txt;
          if ( $hmc =~ /cluster_/ ) {
            $url =~ s/server=.*&lpar/server=$hmc&lpar/g;
          }
          $inventory{$srv}{"LPAR"}{ urldecode( $val[3] ) }{URL}  = $url;
          $inventory{$srv}{"LPAR"}{ urldecode( $val[3] ) }{NAME} = $txt;
        }
        last;
      };
    };
  }

  #print Dumper \%inventory;
  foreach my $server ( keys %inventory ) {
    if ( $type eq "POOL" ) {
      foreach my $pool ( keys %{ $inventory{$server}{$type} } ) {
        if ( !defined $inventory{$server}{$type}{$pool}{NAME} ) { next; }
        my $name_pool = $inventory{$server}{$type}{$pool}{NAME};
        if ( $name_pool eq $lpar ) {
          return $server;
        }
      }
    }
    else {
      foreach my $lpar_act ( keys %{ $inventory{$server}{$type} } ) {
        if ( !defined $inventory{$server}{$type}{$lpar_act}{NAME} ) { next; }
        my $name_lpar = $inventory{$server}{$type}{$lpar_act}{NAME};
        if ( $name_lpar eq $lpar ) {
          return $server;
        }
      }
    }
  }

}

sub read_cfg {
  my $host             = "";
  my $managedname      = "";
  my $lpar             = "";
  my $cpulim           = "";
  my $cpulimmin        = "";
  my $tint             = "";
  my $trepeat          = "";
  my $email            = "";
  my $util             = "";
  my $name_rep         = "";
  my $ltime_rep        = "";
  my $ltime_human      = "";
  my $emails_count     = 0;
  my $nagios           = "";
  my $cpu_warning      = "";
  my $extern_alert     = "";
  my $trash            = "";
  my $line_rep         = "";
  my $email_admin      = "";
  my $line             = "";
  my $return           = "";
  my @server_proc_pool = "";
  my $server_proc      = 0;
  my $lpar_name_org    = "";
  my $email_graph      = 0;
  my $exclude          = "";
  my $snmp_trap        = "";
  my $mailfrom         = "";
  my %service_now;
  my %jira_cloud;
  my %opsgenie; 

  # those are globals due to swapping
  $repeat_default           = "";
  $cpu_average_time_default = "";
  $email_default            = "";

  open( FH, "< $cfg" ) || error( "could not open $cfg : $!" . __FILE__ . ":" . __LINE__ ) && return 1;
  my @lines = <FH>;
  close(FH);

  # allow usage of additional alert.cfg files like : etc/alert*.cfg
  ( my $cfg_pref, my $cfg_suff ) = split( /\./, $cfg );
  foreach my $cfg_cust (<$cfg_pref*\.$cfg_suff>) {
    chomp($cfg_cust);
    if ( $cfg =~ m/^$cfg_cust$/ ) {
      next;
    }
    if ($new_alert) {
      $cfg_cust = $cfg;
    }
    open( FH, "< $cfg_cust" ) || error( "could not open $cfg_cust : $!" . __FILE__ . ":" . __LINE__ ) && return 1;
    my @lines_cust = <FH>;
    close(FH);
    my @merged = ( @lines, @lines_cust );
    @lines = @merged;

    #print "001 $cfg_cust\n";
  }

  my @lines_sort = sort(@lines);

  if ( -f $alert_repeat ) {
    open( FHR, "< $alert_repeat" );
    @lines_rep = sort(<FHR>);
    close(FHR);
  }

  foreach $line (@lines) {
    if ( $line =~ m/^#/ ) {
      next;
    }
    chomp($line);
    if ( $line =~ m/^EMAIL_ADMIN=/ ) {
      ( $trash, $email_admin ) = split( /=/, $line );
      $email_admin =~ s/ //g;
      $email_admin =~ s/	//g;
      $email_admin =~ s/#.*$//g;
      next;
    }
    if ( $line =~ m/^CPU_WARNING_ALERT=/ ) {
      ( $trash, $cpu_warning ) = split( /=/, $line );
      $cpu_warning =~ s/ //g;
      $cpu_warning =~ s/	//g;
      $cpu_warning =~ s/#.*$//g;
      my $ret = isdigit( $cpu_warning, "CPU_WARNING_ALERT: $line" );
      if ( $ret == 0 ) {
        exit 0;
      }
      next;
    }
    if ( $line =~ m/^NAGIOS=/ ) {
      ( $trash, $nagios ) = split( /=/, $line );
      $nagios =~ s/ //g;
      $nagios =~ s/	//g;
      $nagios =~ s/#.*$//g;
      my $ret = isdigit( $nagios, "NAGIOS: $line" );
      if ( $ret == 0 ) {
        exit 0;
      }
      next;
    }
    if ( $line =~ m/^EMAIL_GRAPH=/ ) {
      ( $trash, $email_graph ) = split( /=/, $line );
      $email_graph =~ s/ //g;
      $email_graph =~ s/	//g;
      $email_graph =~ s/#.*$//g;
      next;
    }
    if ( $line =~ m/^TRAP=/ ) {
      ( $trash, $snmp_trap ) = split( /=/, $line );
      $snmp_trap =~ s/ //g;
      $snmp_trap =~ s/ //g;
      $snmp_trap =~ s/#.*$//g;
      next;
    }
    if ( $line =~ m/^EXTERN_ALERT=/ ) {
      ( $trash, $extern_alert ) = split( /=/, $line );
      $extern_alert =~ s/ //g;
      $extern_alert =~ s/	//g;
      $extern_alert =~ s/#.*$//g;
      next;
    }
    if ( $line =~ m/^ALERT_HISTORY=/ ) {
      ( $trash, $alert_history ) = split( /=/, $line );
      $alert_history =~ s/ //g;
      $alert_history =~ s/	//g;
      $alert_history =~ s/#.*$//g;
      next;
    }
    if ( $line =~ m/^MAILFROM=/ ) {
      ( $trash, $mailfrom ) = split( /=/, $line );
      $mailfrom =~ s/ //g;
      $mailfrom =~ s/      //g;
      $mailfrom =~ s/#.*$//g;
      next;
    }
    if ( $line =~ m/^REPEAT_DEFAULT=/ ) {
      ( $trash, $repeat_default ) = split( /=/, $line );
      $repeat_default =~ s/ //g;
      $repeat_default =~ s/	//g;
      $repeat_default =~ s/#.*$//g;
      my $ret = isdigit( $repeat_default, "REPEAT_DEFAULT: $line" );
      if ( $ret == 0 ) {
        exit 0;
      }
      next;
    }
    if ( $line =~ m/^PEAK_TIME_DEFAULT=/ ) {
      ( $trash, $cpu_average_time_default ) = split( /=/, $line );
      $cpu_average_time_default =~ s/ //g;
      $cpu_average_time_default =~ s/	//g;
      $cpu_average_time_default =~ s/#.*$//g;
      my $ret = isdigit( $cpu_average_time_default, "PEAK_TIME_DEFAULT: $line" );
      if ( $ret == 0 ) {
        exit 0;
      }
      next;
    }
    if ( $line =~ m/^PEAK_TIME_DEFAULT=/ ) {
      ( $trash, $cpu_average_time_default ) = split( /=/, $line );
      $cpu_average_time_default =~ s/ //g;
      $cpu_average_time_default =~ s/>-//g;
      $cpu_average_time_default =~ s/#.*$//g;
      my $ret = isdigit( $cpu_average_time_default, "PEAK_TIME_DEFAULT: $line" );
      if ( $ret == 0 ) {
        exit 0;
      }
      next;
    }
    if ( $line =~ m/^EMAIL=/ && $new_alert == 0 ) {
      ( $trash, $email_default ) = split( /=/, $line );
      $email_default =~ s/ //g;
      $email_default =~ s/	//g;
      $email_default =~ s/#.*$//g;
      next;
    }
    if ( $line =~ m/^EMAIL_/ && $new_alert == 0 ) {
      ( my $email_name, my $email_addr ) = split( /=/, $line );
      $email_name =~ s/ //g;
      $email_name =~ s/	//g;
      $email_name =~ s/#.*$//g;
      $email_addr =~ s/ //g;
      $email_addr =~ s/	//g;
      $email_addr =~ s/#.*$//g;
      $emails_name[$emails_count] = $email_name;
      $emails_addr[$emails_count] = $email_addr;

      #print "# 00 $emails_name[$emails_count] = $emails_addr[$emails_count] :: $email_name = $email_addr : $emails_count\n";
      $emails_count++;
      next;
    }
    if ( $line =~ m/^EMAIL:/ && $new_alert == 1 ) {
      ( undef, my $email_group, my $emails ) = split( /:/, $line );
      if ( defined $email_group && $email_group ne "" && defined $emails && $emails ne "" ) {
        $emails_name[$emails_count] = $email_group;
        $emails_addr[$emails_count] = $emails;
        $emails_count++;
        next;
      }
    }
    if ( $line =~ m/^COMM_STRING=/ ) {
      my $comm_string_tmp = $line;
      $comm_string_tmp =~ s/^COMM_STRING=//;
      if ( defined $comm_string_tmp && $comm_string_tmp ne '' ) {
        $community_string = $comm_string_tmp;
      }
      next;
    }
    if ( $line =~ m/^WEB_UI_URL=/ ) {
      my $web_ui_url_tmp = $line;
      $web_ui_url_tmp =~ s/^WEB_UI_URL=//;
      if ( defined $web_ui_url_tmp && $web_ui_url_tmp ne '' ) {
        $web_ui_url = "$web_ui_url_tmp";
      }
      next;
    }
    if ( $line =~ m/^SERVICE_NOW/ ) {
      if ( $line =~ m/^SERVICE_NOW_IP=/ ) {
        $line =~ s/^SERVICE_NOW_IP=//;
        $service_now{"ip"} = $line;
      }
      elsif ( $line =~ m/^SERVICE_NOW_USER=/ ) {
        $line =~ s/^SERVICE_NOW_USER=//;
        $service_now{"user"} = $line;
      }
      elsif ( $line =~ m/^SERVICE_NOW_PASSWORD=/ ) {
        $line =~ s/^SERVICE_NOW_PASSWORD=//;
        $service_now{"password"} = $line;
      }
      elsif ( $line =~ m/^SERVICE_NOW_SEVERITY=/ ) {
        $line =~ s/^SERVICE_NOW_SEVERITY=//;
        $service_now{"severity"} = $line;
      }
      elsif ( $line =~ m/^SERVICE_NOW_TYPE=/ ) {
        $line =~ s/^SERVICE_NOW_TYPE=//;
        $service_now{"type"} = $line;
      }
      elsif ( $line =~ m/^SERVICE_NOW_EVENT=/ ) {
        $line =~ s/^SERVICE_NOW_EVENT=//;
        $service_now{"event"} = $line;
      }
    }
    if ( $line =~ m/^JIRA/ ) {
      if ( $line =~ m/^JIRA_URL=/ ) {
        $line =~ s/^JIRA_URL=//;
        $jira_cloud{"url"} = $line;
      }
      elsif ( $line =~ m/^JIRA_TOKEN=/ ) {
        $line =~ s/^JIRA_TOKEN=//;
        $jira_cloud{"token"} = $line;
      }
      elsif ( $line =~ m/^JIRA_USER=/ ) {
        $line =~ s/^JIRA_USER=//;
        $jira_cloud{"user"} = $line;
      }
      elsif ( $line =~ m/^JIRA_PROJECT_KEY=/ ) {
        $line =~ s/^JIRA_PROJECT_KEY=//;
        $jira_cloud{"project_key"} = $line;
      }
      elsif ( $line =~ m/^JIRA_ISSUE_ID=/ ) {
        $line =~ s/^JIRA_ISSUE_ID=//;
        $jira_cloud{"issue_id"} = $line;
      }
    }
    if ( $line =~ m/^OPSGENIE/ ) {
      if ( $line =~ m/^OPSGENIE_KEY=/ ) {
        $line =~ s/^OPSGENIE_KEY=//;
        $opsgenie{'key'} = $line;
      }
      if ( $line =~ m/^OPSGENIE_URL=/ ) {
        $line =~ s/^OPSGENIE_URL=//;
        $opsgenie{'url'} = $line;
      }
    }

  }

  if ( $cpu_average_time_default eq '' ) {
    error("PEAK_TIME_DEFAULT is not set, exiting ...");
    exit 1;
  }
  if ( $repeat_default eq '' ) {
    error("REPEAT_DEFAULT is not set, exiting ...");
    exit 1;
  }
  if ( $alert_history eq '' ) {

    #error("ALERT_HISTORY is not set, exiting ...");
    #exit 1;
    $alert_history = "$basedir/logs/alert_history.log";
  }
  if ( $mailfrom eq '' ) {
    $mailfrom = "lpar2rrd";
  }
  if ( $nagios eq '' ) {
    $nagios = 0;
  }
  if ( $cpu_warning eq '' && $new_alert == 0 ) {
    error("CPU_WARNING_ALERT is not set, exiting ...");
    exit 1;
  }

  if ( $new_alert == 0 ) {

    # Handling all swapping
    swapping( $mailfrom, $email_graph, $nagios, $extern_alert, \@lines_sort );
  }

  #exit (0);

  # it has to be in separated run (sorted by hosts/server)
  # Load data selectively per lpar
  my $managedname_prev = "";
  my $lpars            = "";
  my $last_type        = "";
  foreach $line (@lines_sort) {
    chomp($line);
    if ( $line eq '' || $line =~ m/^#/ || $line =~ m/^SWAP/ || $line =~ m/SWAP:/ || $line !~ m/:/ || $line =~ m/^EMAIL:/ ) {
      next;    # exclude comments and swapping rules
    }

    if ( $new_alert == 0 ) {
      my $pom_line = $line;
      $pom_line =~ s/\\:/=====doublecoma=====/g;
      ( $trash, $managedname, $lpar, $cpulim, $cpulimmin, $tint, $trepeat, $email ) = split( /:/, $pom_line );

      if ( defined $lpar && $lpar ne "" ) {
        $lpar =~ s/=====doublecoma=====/:/g;
      }
    }
    else {
      my $pom_line = $line;
      $pom_line =~ s/\\:/=====doublecoma=====/g;
      ( $trash, $managedname, $lpar, my $cpu_string, $cpulim, $tint, $trepeat, $exclude, $email ) = split( /:/, $pom_line );
      if ( !defined $cpu_string || $cpu_string eq "" || $cpu_string ne "CPU" ) { next; }
      if ( defined $lpar && $lpar ne "" ) {
        $lpar =~ s/=====doublecoma=====/:/g;
      }
      if ( !defined $managedname || $managedname eq "" ) {
        my $server = find_server( $trash, $lpar );
        if ( defined $server && $server ne "" ) { $managedname = $server; }
      }
    }
    if ( $lpar eq '' || $managedname eq '' ) {
      next;    # something wrong
    }

    $lpar =~ s/\//\&\&1/g;

    if ( $line =~ m/^LPAR:/ ) {
      print "loading data   : $line\n" if !$restapi;
      $last_type = "LPAR";
      if ($new_alert) {
        print "001 $line : $lpar - $managedname_prev : $managedname - $lpar - $cpulim -  $tint - $trepeat - $email\n" if $DEBUG == 2;
      }
      else {
        print "001 $line : $lpar - $managedname_prev : $managedname - $lpar - $cpulim - $cpulimmin - $tint - $trepeat - $email\n" if $DEBUG == 2;
      }

      if ( $lpars eq '' ) {
        $managedname_prev = $managedname;
        $lpars .= $lpar;
        next;
      }
      if ( $managedname_prev =~ m/^$managedname$/ ) {
        $lpars .= "," . $lpar;
        next;
      }
      else {
        print "022 Load data      : $managedname_prev $lpars\n" if $DEBUG == 2;
        load_rrd_lpar( $managedname_prev, $lpars );
        $managedname_prev = $managedname;
        $lpars            = $lpar;
        next;
      }
    }

    if ( !$lpars eq '' ) {

      # do last load which is in $lpars
      print "023 Load data last : $managedname_prev $lpars\n" if $DEBUG == 2;
      load_rrd_lpar( $managedname_prev, $lpars );
      $managedname_prev = $managedname;
      $lpars            = "";
    }

    # same for pools

    if ( $line =~ m/^POOL:/ ) {
      print "loading data   : $line\n" if !$restapi;
      if ( $last_type =~ m/LPAR/ ) {

        # when switch to POOL then must be last saved lpars loaded
        if ( !$managedname eq '' && !$lpars eq '' ) {
          load_rrd_lpar( $managedname_prev, $lpars );
        }
      }

      $last_type = "POOL";
      if ( $lpar eq "POOL-TOTALS" ) {
        $lpar      = "pool_total";
        $last_type = "POOL_TOTAL";
      }
      else {
        $lpar = pool_translate( $lpar, $managedname );
      }
      if ( $lpar eq '' ) {

        # something wrong
        next;
      }
      if ( $lpar =~ m/pool/ ) {
        print "023 Load data pool : $managedname $lpar\n" if $DEBUG == 2;
        load_rrd_pool( $managedname, $lpar );
        load_rrd_lpar( $managedname, $lpars );
        $lpars = "";
        next;
      }
      else {
        # save name of server where are proc pools, just uniq names and load data afterwards
        my $found_srv = 0;
        foreach my $server_line (@server_proc_pool) {
          if ( $server_line =~ m/^$managedname$/ ) {
            $found_srv = 1;
            last;
          }
        }
        if ( $found_srv == 0 ) {
          $server_proc_pool[$server_proc] = $managedname;
          $server_proc++;
        }
      }
    }

  }

  if ( $last_type =~ m/LPAR/ && !$managedname eq '' && !$lpars eq '' ) {

    # it can go here only if no any pool is in alerting
    load_rrd_lpar( $managedname, $lpars );
  }

  # Load data from hmc of servers with proc pools
  foreach my $server_line (@server_proc_pool) {
    if ( $server_line eq '' || is_server_excluded_from_rest($managedname) ) {
      next;
    }
    load_rrd_pool( $server_line, "" );
  }

  # rrdtool databases are now up to date, now go again throuh all directive and check utilization

  foreach $line (@lines_sort) {
    chomp($line);
    if ( check_line_valid($line) == 1 ) {
      print STDERR "skipping alert for $line\n";
      next;    #skip alert
    }
    my $cpulim_pct    = "";
    my $cpulimmin_pct = "";
    my $total_cpu     = "";
    if ( $line =~ m/^SWAP/ || $line =~ m/SWAP:/ ) {
      next;    # swapping
    }
    if ( $line =~ m/^LPAR:/ || $line =~ m/^POOL:/ ) {
      $last_type = "LPAR";
      if ( $new_alert == 0 ) {
        my $pom_line = $line;
        $pom_line =~ s/\\:/=====doublecoma=====/g;
        ( $trash, $managedname, $lpar, $cpulim, $cpulimmin, $tint, $trepeat, $email ) = split( /:/, $pom_line );
        if ( defined $lpar && $lpar ne "" ) {
          $lpar =~ s/=====doublecoma=====/:/g;
        }
      }
      else {
        my $pom_line = $line;
        $pom_line =~ s/\\:/=====doublecoma=====/g;
        ( $trash, $managedname, $lpar, my $cpu_string, $cpulim, $tint, $trepeat, $exclude, $email ) = split( /:/, $pom_line );
        if ( !defined $cpu_string || $cpu_string eq "" || $cpu_string ne "CPU" ) { next; }
        if ( defined $lpar && $lpar ne "" ) {
          $lpar =~ s/=====doublecoma=====/:/g;
        }
        if ( !defined $managedname || $managedname eq "" ) {
          my $server = find_server( $trash, $lpar );
          if ( defined $server && $server ne "" ) { $managedname = $server; }
        }
      }
      if ( $new_alert == 0 ) {
        print "Working for    : $line\n";
        print "002 $managedname,$lpar,$cpulim,$cpulimmin,$tint,$trepeat,$email\n" if $DEBUG == 2;
      }
      else {
        print "Working for    : $line\n";
        print "002 $managedname,$lpar,$cpulim,$tint,$trepeat,$exclude,$email\n" if $DEBUG == 2;
      }
      if ( $managedname eq '' ) {
        error("server name is not provided : $line");
        next;
      }

      $lpar_name_org = $lpar;    # it keeps original name instead SharedPool, poll etc, must be used for alering
      if ( $line =~ m/^POOL:/ && $lpar ne "POOL-TOTALS" ) {
        $last_type = "POOL";
        $lpar      = pool_translate( $lpar, $managedname );
        if ( $lpar eq '' ) {

          # something wrong
          next;
        }
      }
      if ( $line =~ m/POOL-TOTALS:/ ) {
        $last_type = "POOL_TOTAL";
        $lpar      = "pool_total";
      }

      # exclude time
      if ( defined $exclude && $exclude =~ m/-/ ) {
        my $end_time = time();
        ( my $hour_start, my $hour_end ) = split( /-/, $exclude );
        if ( $hour_start < $hour_end ) {
          my $start = get_timestamp_from_hour($hour_start);
          my $end   = get_timestamp_from_hour($hour_end);
          if ( $start <= $end_time && $end_time <= $end ) {
            print "Active exclude time for $managedname:$lpar:$cpulim:$tint:$trepeat:$exclude:$email\n";
            ### run exlude time
            next;
          }
        }
        else {
          my $start          = get_timestamp_from_hour($hour_start);
          my $end            = get_timestamp_from_hour( $hour_end, "1" );
          my $start_last_day = $start - ( 24 * 3600 );
          my $end_last_day   = $end - ( 24 * 3600 );
          if ( ( $start <= $end_time && $end_time <= $end ) || ( $start_last_day <= $end_time && $end_time <= $end_last_day ) ) {
            print "Active exclude time for $managedname:$lpar:$cpulim:$tint:$trepeat:$exclude:$email\n";
            ### run exlude time
            next;
          }
        }
      }

      # get the latest used HMC
      if ( $line =~ /POOL-TOTALS/ ) {
        $host = get_hmc( $managedname, $lpar . ".rrt" );
      }
      else {
        $host = get_hmc( $managedname, $lpar . ".rrm" );
      }
      $hmc_user = `\$PERL $basedir/bin/hmc_list.pl --username $host`;
      my $is_host_rest = is_host_rest($host);

      #2021-06-17T07:52:00.000Z
      my $TZ_HMC = 0;#  = `$SSH $hmc_user\@$host "date '+%z'"`;
      my $TS_HMC = 0;#  = `$SSH $hmc_user\@$host "date '+%Y-%m-%dT%H:%M:%S%z'"`;
      my $TS_HMCB= 0;# = `$SSH $hmc_user\@$host "date '+%m/%d/%Y %H:%M:%S'"`;
      if (!$restapi){
        $TZ_HMC  = `$SSH $hmc_user\@$host "date '+%z'"`;
        $TS_HMC  = `$SSH $hmc_user\@$host "date '+%Y-%m-%dT%H:%M:%S%z'"`;
        $TS_HMCB = `$SSH $hmc_user\@$host "date '+%m/%d/%Y %H:%M:%S'"`;
      }
      my $TZ_LOCAL = `date '+%z'`;
      chomp( $TZ_HMC, $TZ_LOCAL );
      chomp($TS_HMC);
      chomp($TS_HMCB);

      my $is_server_excluded_from_rest;
      if ($is_host_rest) {
        $is_server_excluded_from_rest = is_server_excluded_from_rest($managedname);
      }
      else {
        $is_server_excluded_from_rest = 0;
      }
      if ( $host eq '' ) {

        # something wrong
        next;
      }
      if ( $is_host_rest && !$is_server_excluded_from_rest ) {

        #next;
      }

      $cpulim =~ s/ //g;
      if ( $new_alert == 0 ) {
        $cpulimmin =~ s/ //g;
      }
      $tint    =~ s/ //g;
      $trepeat =~ s/ //g;
      $email   =~ s/ //g;
      if ( $lpar eq '' ) {
        error("lpar name is not provided : $line");
        next;
      }
      $total_cpu = get_cpu_total( $host, $managedname, $lpar, $wrkdir, $trash );
      if ( isdigit($total_cpu) && $total_cpu == -1 && $alert_test == 0 ) {
        next;
      }

      if ( $cpulim =~ /%/ ) {
        $cpulim_pct = $cpulim;
        $cpulim =~ s/%//g;
        $cpulim = ( $total_cpu / 100 ) * $cpulim;
      }
      if ( $new_alert == 0 ) {
        if ( $cpulimmin =~ /%/ ) {
          $cpulimmin_pct = $cpulimmin;
          $cpulimmin =~ s/%//g;
          $cpulimmin = ( $total_cpu / 100 ) * $cpulimmin;
        }
      }

      if ( $cpulim eq '' && $alert_test == 0 ) {
        error("CPU limit MAX is not provided : $host:$managedname:$lpar : $line");
        next;
      }
      my $ret = isdigit( $cpulim, "cpulim: $cpulim : $line" );
      if ( $ret == 0 && $alert_test == 0 ) {
        next;
      }

      if ( $new_alert == 0 ) {
        if ( $cpulimmin eq '' && $alert_test == 0 ) {
          error("CPU limit MIN is not provided : $host:$managedname:$lpar : $line");
          next;
        }
        $ret = isdigit( $cpulimmin, "cpulimmin: $cpulimmin : $line" );
        if ( $ret == 0 && $alert_test == 0 ) {
          next;
        }
      }

      if ( $tint eq '' ) {
        if ( $cpu_average_time_default eq '' && $alert_test == 0 ) {
          error("PEAK_TIME is not provided and default is not specified as well: $host:$managedname:$lpar : $line");
          next;
        }
        else {
          $tint = $cpu_average_time_default * 60;    # in seconds
        }
      }
      else {
        $ret = isdigit( $tint, "tint: $tint : $line" );
        if ( $ret == 0 && $alert_test == 0 ) {
          next;
        }
        $tint = $tint * 60;    # in seconds
      }

      if ( $trepeat eq '' ) {
        if ( $repeat_default eq '' ) {
          error("REPEAT is not provided and default is not specified as well: $host:$managedname:$lpar : $line");
          next;
        }
        else {
          $trepeat = $repeat_default * 60;    # in seconds
        }
      }
      else {
        $ret = isdigit( $trepeat, "trepeat: $trepeat : $line" );
        if ( $ret == 0 && $alert_test == 0 ) {
          next;
        }
        $trepeat = $trepeat * 60;    # in seconds
      }

      # there must not be email alerting
      if ( $email eq '' ) {
        if ( !$email_default eq '' ) {
          $email = $email_default;
        }
      }

      if ( $line =~ m/^LPAR:/ ) {

        # LPARS
        $util = read_rrd( $host, $managedname, $lpar, $wrkdir, $tint );
        if ( $new_alert == 0 ) {
          print "003 read_rrd: $managedname $lpar : $util : $cpulim $cpulimmin $tint $trepeat $email\n" if $DEBUG == 2;
        }
        else {
          print "003 read_rrd: $managedname $lpar : $util : $cpulim $tint $trepeat $exclude $email\n" if $DEBUG == 2;
        }
        if ( $util == -1 && $alert_test == 0 ) {
          next;
        }
      }
      elsif ( $line =~ m/POOL-TOTALS:/ ) {

        #POOL Total
        $lpar = "pool_total";
        $util = read_rrd_pool_total( $host, $managedname, $lpar, $wrkdir, $tint );
        if ( $new_alert == 0 ) {
          print "005 read_rrd_pool_total: $managedname $lpar : $util : $cpulim $cpulimmin $tint $trepeat $email\n" if $DEBUG == 2;
        }
        else {
          print "005 read_rrd_pool_total: $managedname $lpar : $util : $cpulim $tint $trepeat $exclude $email\n" if $DEBUG == 2;
        }
        if ( $util == -1 && $alert_test == 0 ) {
          next;
        }
      }
      else {
        # POOLS
        $util = read_rrd_pool( $host, $managedname, $lpar, $wrkdir, $tint );
        if ( $new_alert == 0 ) {
          print "004 read_rrd_pool: $managedname $lpar : $util : $cpulim $cpulimmin $tint $trepeat $email\n" if $DEBUG == 2;
        }
        else {
          print "004 read_rrd_pool: $managedname $lpar : $util : $cpulim $tint $trepeat $exclude $email\n" if $DEBUG == 2;
        }
        if ( $util == -1 && $alert_test == 0 ) {
          next;
        }
      }
    }
    else {
      next;
    }

    if ( "$util" eq '' ) {
      error("no utilizaton has been found : $host:$managedname:$lpar");
      if ( $alert_test == 0 ) {
        next;
      }
    }

    my $alert_type      = 0;
    my $alert_type_text = "";

    #my $lpar_translated = $lpar;
    #$lpar = $lpar_name_org; # return original name before alerting, it is a must for pools

    # Critical
    if ( $new_alert == 0 ) {
      if ( $util > $cpulim || $util < $cpulimmin ) {
        $alert_type = 2;
        if ( $alert_test == 0 ) {
          $alert_type_text = "CPU";
        }
        else {
          $alert_type_text = "Testing mode : CPU";
        }
        print "005 CPU $lpar_name_org : $util > $cpulim < $cpulimmin ? \n" if $DEBUG == 2;
      }
      else {
        # Warning-
        my $maxw = $cpulim / 100 * $cpu_warning;
        my $minw = $cpulimmin + $cpulimmin / 100 * ( 100 - $cpu_warning );
        if ( $util > $maxw || $util < $minw ) {
          $alert_type      = 1;
          $cpulim          = $maxw;
          $cpulimmin       = $minw;
          $alert_type_text = "CPU Warning ";
          print "005 CPU Warning  $lpar_name_org : $util > $maxw  < $minw ? \n" if $DEBUG == 2;
        }
      }
    }
    else {
      #new critical
      if ( $util > $cpulim ) {
        $alert_type = 2;
        if ( $alert_test == 0 ) {
          $alert_type_text = "CPU";
        }
        else {
          $alert_type_text = "Testing mode : CPU";
        }
        print "005 CPU $lpar_name_org : $util > $cpulim ? \n" if $DEBUG == 2;
      }
    }
    if ( $alert_type > 0 ) {
      print "006 CPU alert $lpar_name_org : $util\n" if $DEBUG == 2;

      # check whether to send alam or not (retention)
      my $send_alarm = 1;
      foreach $line_rep (@lines_rep) {
        chomp($line_rep);
        if ( $line_rep eq '' ) {
          next;
        }
        ( $name_rep, $ltime_rep, $ltime_human ) = split( /\|/, $line_rep );
        if ( "$name_rep" eq '' ) {
          next;
        }
        if ( "$name_rep" =~ m/^$host$managedname$lpar_name_org$/ && $new_alert == 0 ) {
          if ( $ltime_rep + $trepeat > $ltime ) {
            $send_alarm = 0;
          }
          last;
        }
        if ( "$name_rep" =~ m/^$managedname$lpar_name_org$/ && $new_alert == 1 ) {
          if ( $ltime_rep + $trepeat > $ltime ) {
            $send_alarm = 0;
          }
          last;
        }
      }
      if ( $send_alarm == 0 && $alert_test == 0 ) {

        # do not send alarm
        print "025 $host:$managedname:$lpar_name_org : do not send alarm this time : $ltime_rep + $trepeat < $ltime \n" if $DEBUG == 2;
        my $ltime_rep_str = time2string($ltime_rep);
        my $ltime_str     = time2string($ltime);

        if ( $new_alert == 0 ) {
          print "Alert not send : $alert_type_text $last_type:$host:$managedname:$lpar_name_org act:$util : $cpulimmin - $cpulim: not this time due to repeat time $ltime_rep_str + $trepeat secs > $ltime_str\n";
          next;
        }
        else {
          print "Alert not send : $alert_type_text $last_type:$host:$managedname:$lpar_name_org act:$util : $cpulim: not this time due to repeat time $ltime_rep_str + $trepeat secs > $ltime_str\n";
          next;
        }
      }

      if ( $alert_test == 0 ) {

        # update retention alerts
        open( FHW, ">> $alert_repeat" ) || error( "could not open $alert_repeat : $!" . __FILE__ . ":" . __LINE__ ) && return 1;
        if ( $new_alert == 0 ) {
          print FHW "$host$managedname$lpar_name_org|$ltime|$ltime_str\n";
        }
        if ( $new_alert == 1 ) {
          print FHW "$managedname$lpar_name_org|$ltime|$ltime_str\n";
        }
        close(FHW);
      }

      # print alarm to stdout
      if ( $new_alert == 0 ) {
        print "099 $alert_type_text ALARM : $ltime_str: $last_type:$host:$managedname:$lpar_name_org, actual util:$util, limit max-min:$cpulim - $cpulimmin\n" if $DEBUG == 2;
        print "Alert logged   : $alert_type_text ALARM: $ltime_str:$host:$managedname:$lpar_name_org, actual util:$util, limit max-min:$cpulim - $cpulimmin\n";
      }
      else {
        print "099 $alert_type_text ALARM : $ltime_str: $last_type:$host:$managedname:$lpar_name_org, actual util:$util, limit max:$cpulim\n" if $DEBUG == 2;
        print "Alert logged   : $alert_type_text ALARM: $ltime_str:$host:$managedname:$lpar_name_org, actual util:$util, limit max:$cpulim\n";
      }

      # log an alarm to a file : alert.log
      if ( $new_alert == 0 ) {
        open( FHL, ">> $alert_history" ) || error( "could not open $alert_history: $!" . __FILE__ . ":" . __LINE__ ) && return 1;
        if ( $alert_test == 0 ) {

          #print FHL "$ltime_str: $alert_type_text $last_type:$host:$managedname:$lpar_name_org, actual util:$util, limit max-min:$cpulim - $cpulimmin\n";
          print FHL "$ltime_str; $alert_type_text; $last_type; $host; $managedname; $lpar_name_org, actual util:$util, limit max-min:$cpulim - $cpulimmin\n";
        }
        close(FHL);
      }
      else {
        open( FHL, ">> $alert_history" ) || error( "could not open $alert_history: $!" . __FILE__ . ":" . __LINE__ ) && return 1;
        if ( $alert_test == 0 ) {

          #print FHL "$ltime_str: $alert_type_text $last_type:$host:$managedname:$lpar_name_org, actual util:$util, limit max:$cpulim\n";
          print FHL "$ltime_str; $alert_type_text; $last_type; $host; $managedname; $lpar_name_org, actual util:$util, limit max:$cpulim\n";
        }
        close(FHL);
      }

      # mail alarm
      if ( !$email eq '' ) {
        send_mail( $mailfrom, $email, $host, $managedname, $lpar_name_org, $util, $cpulim, $cpulimmin, $ltime_str, $email_default, $last_type, $alert_type_text, $email_graph, $line, $lpar, $tint, $cpulim_pct, $cpulimmin_pct, $cpu_warning, $total_cpu );
      }

      # nagios alarm
      if ( $nagios == 1 ) {
        nagios_alarm( $host, $managedname, $lpar_name_org, $util, $cpulim, $cpulimmin, $ltime_str, $last_type, $alert_type_text, $alert_test );
      }

      # SNMP TRAP
      if ( defined($snmp_trap) && $snmp_trap ne '' && $snmp_trap !~ m/your_snmp_trap_server/ ) {
        snmp_trap_alarm( $snmp_trap, $host, $managedname, $lpar_name_org, $util, $cpulim, $cpulimmin, $ltime_str, $last_type, $alert_type_text );
      }

      # extern alert
      if ( !$extern_alert eq '' ) {
        extern_alarm( $host, $managedname, $lpar_name_org, $util, $cpulim, $cpulimmin, $ltime_str, $last_type, $alert_type_text, $extern_alert );
      }

      # Service_now
      if ( defined $service_now{'ip'} && $service_now{'ip'} ne '' ) {
        service_now( $host, $managedname, $lpar_name_org, $util, $cpulim, $cpulimmin, $ltime_str, $last_type, $alert_type_text, $line, $lpar, $tint, $cpulim_pct, $cpulimmin_pct, $cpu_warning, $total_cpu, \%service_now );
      }

      # Jira Cloud
      if ( defined $jira_cloud{'url'} && $jira_cloud{'url'} ne "" && defined $jira_cloud{'token'} && $jira_cloud{'token'} ne "" ) {
        jira_cloud( $host, $managedname, $lpar_name_org, $util, $cpulim, $cpulimmin, $ltime_str, $last_type, $alert_type_text, $line, $lpar, $tint, $cpulim_pct, $cpulimmin_pct, $cpu_warning, $total_cpu, \%jira_cloud );	
      }

      # Opsgenie
      if ( defined $opsgenie{'key'} && $opsgenie{'key'} ne "" ) {
        opsgenie( $host, $managedname, $lpar_name_org, $util, $cpulim, $cpulimmin, $ltime_str, $last_type, $alert_type_text, $line, $lpar, $tint, $cpulim_pct, $cpulimmin_pct, $cpu_warning, $total_cpu, \%opsgenie );
      }

    }
    else {
      print "No alerting    :$alert_type_text $last_type:$host:$managedname:$lpar_name_org act utilization:$util\n";
    }
  }

  # clean out alert repeat
  my @lines_rep_new = "";
  my $counter       = 0;
  if ( -f $alert_repeat ) {

    # read alert file with retentin alerts into an array
    open( FHR, "< $alert_repeat" );
    @lines_rep = sort(<FHR>);
    close(FHR);
    my $name_rep_prev    = "";
    my $ltime_rep_prev   = "";
    my $ltime_human_prev = "";
    foreach $line_rep (@lines_rep) {
      chomp($line_rep);
      ( $name_rep, $ltime_rep, $ltime_human ) = split( /\|/, $line_rep );
      if ( $name_rep_prev eq '' ) {
        $name_rep_prev    = $name_rep;
        $ltime_rep_prev   = $ltime_rep;
        $ltime_human_prev = $ltime_human;
        next;
      }
      if ( "$name_rep" =~ m/^$name_rep_prev$/ ) {
        $name_rep_prev    = $name_rep;
        $ltime_rep_prev   = $ltime_rep;
        $ltime_human_prev = $ltime_human;
      }
      else {
        $lines_rep_new[$counter] = "$name_rep_prev|$ltime_rep_prev|$ltime_human_prev";
        $counter++;
        $name_rep_prev    = $name_rep;
        $ltime_rep_prev   = $ltime_rep;
        $ltime_human_prev = $ltime_human;
      }
    }
    if ( "$name_rep" =~ m/^$name_rep_prev$/ ) {
      if ( !$name_rep eq '' ) {
        $lines_rep_new[$counter] = "$name_rep|$ltime_rep|$ltime_human";
        $counter++;
      }
    }
    else {
      $lines_rep_new[$counter] = "$name_rep_prev|$ltime_rep_prev|$ltime_human_prev";
      $counter++;
      $lines_rep_new[$counter] = "$name_rep|$ltime_rep|$ltime_human";
      $counter++;
    }

    open( FHW, "> $alert_repeat" );
    foreach $line_rep (@lines_rep_new) {
      print FHW "$line_rep\n";
      print "007 alert_repeat: $line_rep\n" if $DEBUG == 2;
    }
    close(FHW);
  }

  return 0;
}

sub get_cpu_total {
  my $host        = shift;
  my $managedname = shift;
  my $lpar        = shift;
  my $wrkdir      = shift;
  my $trash       = shift;
  $lpar =~ s/\//&&1/g;    ### workaround for lpar name with /
  my $rrd = "$wrkdir/$managedname/$host/$lpar.rrm";
  $rrd =~ s/===========doublecoma=========/\:/g;
  my $cpu_cfg  = "$wrkdir/$managedname/$host/cpu.cfg";
  my $answ_out = "";

  if ( $trash =~ /^POOL/ && $lpar eq "pool_total" ) {
    $rrd = "$wrkdir/$managedname/$host/$lpar.rrt";
    $rrd =~ s/===========doublecoma=========/\:/g;

    #$rrd =~ s/:/\\:/g;
    my $last_tt;
    RRDp::cmd qq(last "$rrd");
    eval { $last_tt = RRDp::read; };
    if ($@) { print STDERR "\n"; }
    my $l = localtime($$last_tt);

    # get LAST value from RRD
    RRDp::cmd qq(fetch "$rrd" "AVERAGE" "-s $$last_tt-$step" "-e $$last_tt-$step");
    my $row = "";
    eval { $row = RRDp::read; };
    if ($@) { print STDERR "DEBUG Error at " . __FILE__ . ":" . __LINE__ . "\n"; }
    chomp($$row);
    my @row_arr = split( /:/, $$row );

    $row_arr[0] =~ s/^\s+//g;
    my ( $total_cpu_name, undef, undef, undef ) = split( " ", $row_arr[0] );
    $row_arr[1] =~ s/^\s+//g;
    my ( $total_cpu_act, undef, undef, undef ) = split( " ", $row_arr[1] );

    my $total_cpu = sprintf '%g', $total_cpu_act;
    $answ_out = $total_cpu;
  }
  elsif ( $trash =~ /^POOL/ ) {
    if ( !-f $rrd ) {
      error( "lpar has not been found: $rrd : $host:$managedname:$lpar : $!" . __FILE__ . ":" . __LINE__ );
      return -1;
    }
    if ( $lpar =~ m/pool/ ) {

      #$rrd =~ s/:/\\:/g;
      RRDp::cmd qq(last "$rrd");
      my $last_tt;
      eval { $last_tt = RRDp::read; };
      if ($@) { print STDERR "DEBUG Error at " . __FILE__ . ":" . __LINE__ . "\n"; }
      my $l = localtime($$last_tt);

      # following must be for RRD 1.2+
      $l =~ s/:/\\:/g;
      my $t = "COMMENT:Updated\\: $l ";

      # get LAST value from RRD
      RRDp::cmd qq(fetch "$rrd" "AVERAGE" "-s $$last_tt-$step" "-e $$last_tt-$step");
      my $row = "";
      eval { $row = RRDp::read; };
      if ($@) { print STDERR "DEBUG Error at " . __FILE__ . ":" . __LINE__ . "\n"; }
      chomp($$row);
      my @row_arr = split( /:/, $$row );
      $row_arr[0] =~ s/^\s+//g;
      my ( undef, undef, $total_cpu_name, undef ) = split( " ", $row_arr[0] );
      $row_arr[1] =~ s/^\s+//g;
      my ( undef, undef, $total_cpu_act, $bor_cpu_act ) = split( " ", $row_arr[1] );
      $total_cpu_act =~ s/,/\./;    # no idea why but decimal separator was ",", fixed to '."
      $bor_cpu_act   =~ s/,/\./;
      my $total_cpu = sprintf '%g', $total_cpu_act;
      my $bor_cpu   = sprintf '%g', $bor_cpu_act;

      if ( isdigit($total_cpu) == 0 ) {
        error( "$total_cpu_name is not number in rrd file: $host:$managedname:$lpar : $total_cpu " . __FILE__ . ":" . __LINE__ );
        return -1;
      }
      if ( isdigit($bor_cpu) == 0 ) {
        error( "$total_cpu_name is not number in rrd file: $host:$managedname:$lpar : $bor_cpu " . __FILE__ . ":" . __LINE__ );
        $answ_out = $total_cpu;    # ignore borrowed
      }
      else {
        $answ_out = $total_cpu + $bor_cpu;
      }
    }
    else {
      $rrd =~ s/:/\\:/g;
      RRDp::cmd qq(last "$rrd");
      my $last_tt;
      eval { $last_tt = RRDp::read; };
      if ($@) { print STDERR "DEBUG Error at " . __FILE__ . ":" . __LINE__ . "\n"; }
      my $l = localtime($$last_tt);

      # following must be for RRD 1.2+
      $l =~ s/:/\\:/g;
      my $t = "COMMENT:Updated\\: $l ";

      # get LAST value from RRD
      RRDp::cmd qq(fetch "$rrd" "AVERAGE" "-s $$last_tt-$step" "-e $$last_tt-$step");
      my $row = "";
      eval { $row = RRDp::read; };
      if ($@) { print STDERR "DEBUG Error at " . __FILE__ . ":" . __LINE__ . "\n"; }
      chomp($$row);
      my @row_arr = split( /:/, $$row );
      $row_arr[0] =~ s/^\s+//g;
      my ( undef, undef, $total_cpu_name, undef ) = split( " ", $row_arr[0] );
      $row_arr[1] =~ s/^\s+//g;
      my ( undef, undef, $total_cpu, undef ) = split( " ", $row_arr[1] );
      $answ_out = sprintf '%g', $total_cpu;

      if ( isdigit($answ_out) == 0 ) {
        error( "$total_cpu_name is not number in rrd file: $host:$managedname:$lpar : " . __FILE__ . ":" . __LINE__ );
        return -1;
      }
    }
  }
  elsif ( $trash =~ /^LPAR/ ) {
    if ( !-f $cpu_cfg ) {
      error( "cpu.cfg has not been found: $host:$managedname:$lpar : $!" . __FILE__ . ":" . __LINE__ );
      return -1;
    }
    open( FH, "< $cpu_cfg" ) || error( "Cannot read $cpu_cfg: $!" . __FILE__ . ":" . __LINE__ ) && return -1;
    my @lines_cpu = <FH>;
    close(FH);

    $lpar =~ s/&&1/\//g;

    ( my $cfg_line ) = grep {/^lpar_name=$lpar,/} @lines_cpu;
    if ( !defined($cfg_line) || $cfg_line eq '' ) {
      error( "lpars not found in $cpu_cfg (empty file?): $host:$managedname:$lpar : " . __FILE__ . ":" . __LINE__ ) && return -1;
    }
    my ( undef, $part_two ) = split( ",curr_procs=", $cfg_line );
    my ( $curr_procs, undef ) = split( ",", $part_two );
    $answ_out = $curr_procs;
    if ( isdigit($answ_out) == 0 ) {
      error( "curr_proc is not number in $cpu_cfg: $host:$managedname:$lpar : " . __FILE__ . ":" . __LINE__ ) && return -1;
    }
  }

  return $answ_out;
}

sub read_rrd {
  my $host        = shift;
  my $managedname = shift;
  my $lpar        = shift;
  my $wrkdir      = shift;
  my $tint        = shift;
  $lpar =~ s/\//&&1/g;    ### workaround for lpar name with /
  my $rrd      = "$wrkdir/$managedname/$host/$lpar.rrm";
  my $answ_out = "";

  if ( !-f $rrd ) {
    error( "lpar has not been found: $rrd : $host:$managedname:$lpar at " . __FILE__ . ":" . __LINE__ );
    return -1;
  }

  #print "--03 $time_diff \n";
  $rrd =~ s/:/\\:/g;
  RRDp::cmd qq(graph "$tmpdir/name.png"
    "--start" "end-$tint-$time_diff"
    "DEF:cur=$rrd:curr_proc_units:AVERAGE"
    "DEF:ent=$rrd:entitled_cycles:AVERAGE"
    "DEF:cap=$rrd:capped_cycles:AVERAGE"
    "DEF:uncap=$rrd:uncapped_cycles:AVERAGE"
    "CDEF:tot=cap,uncap,+"
    "CDEF:util=tot,ent,/,$cpu_max_filter,GT,UNKN,tot,ent,/,IF"
    "CDEF:utiltot=util,cur,*"
    "PRINT:utiltot:AVERAGE: %3.3lf"
  );
  my $answer = "";
  eval { $answer = RRDp::read; };
  if ($@) { print STDERR "DEBUG Error at " . __FILE__ . ":" . __LINE__ . "\n"; }

  #print "$$answer\n";
  print "008 read_rrd:answer: $rrd:\n $$answer\n" if $DEBUG == 2;

  # parse graph output, at the second line is avrg CPU load for TOP10 page
  my $once = 0;
  foreach my $answ ( split( / /, $$answer ) ) {
    if ( $once == 1 ) {
      $answ =~ s/ //g;
      my $ret = substr( $answ, 0, 1 );
      if ( $ret =~ /\D/ ) {
        next;
      }
      else {
        chomp($answ);
        $answ_out = $answ;
      }
    }
    else {
      if ( $answ =~ "ERROR" ) {
        error("Graph rrdtool error : $answ");
        if ( $answ =~ "is not an RRD file" ) {
          ( my $err, my $file, my $txt ) = split( /'/, $answ );
          error("Removing as it seems to be corrupted: $file");
          unlink("$file") || error( "Cannot rm $file : $!" . __FILE__ . ":" . __LINE__ ) && return 1;
        }
        else {
          print "027 Graph rrdtool error : $answ" if $DEBUG == 2;
        }
      }
    }
    $once++;
  }

  print "009 read_rrd:parsed: $answ_out ---- $lpar|$managedname|$host|$HMC\n" if $DEBUG == 2;
  if ( $answ_out eq '' ) {
    my $last_rec_raw;
    RRDp::cmd qq(last "$rrd" );
    eval { $last_rec_raw = RRDp::read; };
    if ($@) { print STDERR "DEBUG Error at " . __FILE__ . ":" . __LINE__ . "\n"; }
    chomp($$last_rec_raw);
    my $last_rec = localtime($$last_rec_raw);
    error( "no CPU data has been found: $host:$managedname:$lpar, last data timestamp : $last_rec at " . __FILE__ . ":" . __LINE__ . "\n" );
    return -1;
  }
  return $answ_out;
}

sub nagios_alarm {
  my $host            = shift;
  my $managed         = shift;
  my $lpar            = shift;
  my $util            = shift;
  my $utillim         = shift;
  my $utillimmin      = shift;
  my $ltime_str       = shift;
  my $last_type       = shift;
  my $alert_type_text = shift;
  my $alert_test      = shift;

  my $lpar_name = $lpar;
  $lpar_name =~ s/\//&&1/g;

  if ( $alert_test == 1 ) {
    print "Alert nagios   : $last_type=$lpar:$managed:$lpar utilization=$util - no alerting as no rights\n";
    return 0;
  }

  print "Alert nagios   : $last_type=$lpar:$managed:$lpar utilization=$util\n";

  if ( !-d "$nagios_dir" ) {
    print "mkdir          : $nagios_dir\n" if $DEBUG;
    mkdir( "$nagios_dir", 0755 ) || error( "Cannot mkdir $nagios_dir: $!" . __FILE__ . ":" . __LINE__ ) && return 1;
    chmod 0777, "$nagios_dir" || error( "Can't chmod 666 $nagios_dir: $!" . __FILE__ . ":" . __LINE__ ) && return 1;
  }

  if ( !-d "$nagios_dir/$managed" ) {
    print "mkdir          : $nagios_dir/$managed\n" if $DEBUG;
    mkdir( "$nagios_dir/$managed", 0755 ) || error( "Cannot mkdir $nagios_dir/$managed: $!" . __FILE__ . ":" . __LINE__ ) && return 1;
    chmod 0777, "$nagios_dir/$managed" || error( "Can't chmod 666 $nagios_dir/$managed: $!" . __FILE__ . ":" . __LINE__ ) && return 1;
  }

  open( FH, "> $nagios_dir/$managed/$last_type-$lpar_name" ) || error( "Can't create $nagios_dir/$managed/$last_type-$lpar_name : $!" . __FILE__ . ":" . __LINE__ ) && return 1;

  if ( $alert_type_text =~ m/Swapping/ ) {
    print FH "$alert_type_text alert for: $last_type=$lpar server=$managed; $util, MAX limit=$utillim\n";
  }
  else {
    if ( $new_alert == 0 ) {
      print FH "$alert_type_text alert for: $managed $last_type=$lpar server=$managed managed by = $host; utilization=$util, MAX limit=$utillim, MIN limit=$utillimmin\n";
    }
    else {
      print FH "$alert_type_text alert for: $managed $last_type=$lpar server=$managed managed by = $host; utilization=$util, MAX limit=$utillim\n";
    }
  }

  close(FH);

  chmod 0666, "$nagios_dir/$managed/$last_type-$lpar_name" || error( "Can't chmod 666 $nagios_dir/$managed/$last_type-$lpar_name : $!" . __FILE__ . ":" . __LINE__ ) && return 1;

  return 1;
}

sub send_mail {
  my $mailfrom         = shift;
  my $to               = shift;
  my $host             = shift;
  my $managed          = shift;
  my $lpar             = shift;
  my $util             = shift;
  my $utillim          = shift;
  my $utillimmin       = shift;
  my $ltime_str        = shift;
  my $email_default    = shift;
  my $last_type        = shift;
  my $alert_type_text  = shift;
  my $email_graph      = shift;
  my $line             = shift;
  my $lpar_translated  = shift;
  my $tint             = shift;
  my $cpulim_pct       = shift;
  my $cpulimmin_pct    = shift;
  my $cpu_warning      = shift;
  my $total_cpu        = shift;
  my $emails_counter   = 0;
  my @emails_inventory = ();

  $tint = $tint / 60;

  if ( $new_alert == 0 ) {
    $emails_inventory[0] = $to;
  }
  else {
    foreach my $line (@emails_name) {
      if ( $line =~ m/^$to/ && length($line) == length($to) ) {
        @emails_inventory = split( /,/, $emails_addr[$emails_counter] );
        last;
      }
      $emails_counter++;
    }
  }

  foreach my $emal_pom (@emails_inventory) {
    $to = $emal_pom;

    #print "010 send_mail: $to,$host,$managed,$lpar,$util,$utillim,$utillimmin,$ltime_str,$email_default,$emails_counter \n" if $DEBUG == 2;
    if ( $to eq '' ) {
      $to = $email_default;
    }
    else {
      if ( $to =~ m/^EMAIL_/ ) {
        foreach my $line (@emails_name) {

          #chomp ($line);
          if ( $line =~ m/^$to/ && length($line) == length($to) ) {
            $to = $emails_addr[$emails_counter];
          }
          $emails_counter++;
        }
      }
      else {
        if ( $to =~ m/^EMAIL/ ) {
          $to = $email_default;
        }
      }
    }

    if ( $to eq '' ) {
      error("email isn not set for this alert: $host:$managed:$lpar");

      # is that realy error?? what about Nagios alerting?
      return -1;
    }

    $lpar_translated =~ s/\//&&1/g;
    my $graph_path = "$tmpdir/alert_graph_$host-$managed-$lpar_translated.png";
    $graph_path =~ s/%//g;      # ";" cannot be in the path
    $graph_path =~ s/#//g;      # ";" cannot be in the path
    $graph_path =~ s/://g;      # ";" cannot be in the path
    $graph_path =~ s/&&1//g;    # ";" cannot be in the path
    $graph_path =~ s/;//g;      # ";" cannot be in the path
    $graph_path =~ s/ //g;      # ";" cannot be in the path

    if ( $email_graph > 0 ) {
      create_graph( $host, $managed, $lpar_translated, $graph_path, $basedir, $bindir, $line, $email_graph );
    }

    if ( $alert_type_text =~ m/Swapping/ ) {
      sendmail( $mailfrom, $to, "$ltime_str: $alert_type_text alert for:\n LPAR: $lpar\n server: $managed\n swapping for last $tint mins: \n   $util\n\n", $lpar, $util, $last_type, $alert_type_text, $managed, $graph_path, $email_graph );
    }
    if ( $alert_type_text !~ m/CPU Warning/ ) {
      if ( $cpulim_pct =~ /%/ ) {
        if ( $new_alert == 0 ) {
          sendmail( $mailfrom, $to, "$ltime_str: $alert_type_text alert for:\n $last_type: $lpar\n server: $managed\n managed by: $host\n avg utilization during last $tint mins: $util\n \($alert_type_text MAX limit: $utillim $cpulim_pct, $alert_type_text MIN limit: $utillimmin, $cpulimmin_pct\)\n\n", $lpar, $util, $last_type, $alert_type_text, $managed, $graph_path, $email_graph );
        }
        else {
          sendmail( $mailfrom, $to, "$ltime_str: $alert_type_text alert for:\n $last_type: $lpar\n server: $managed\n managed by: $host\n avg utilization during last $tint mins: $util cores\n \($alert_type_text MAX limit: $utillim $cpulim_pct\)\n\n", $lpar, $util, $last_type, $alert_type_text, $managed, $graph_path, $email_graph );
        }
      }
      else {
        if ( $new_alert == 0 ) {
          sendmail( $mailfrom, $to, "$ltime_str: $alert_type_text alert for:\n $last_type: $lpar\n server: $managed\n managed by: $host\n avg utilization during last $tint mins: $util\n \($alert_type_text MAX limit: $utillim $alert_type_text MIN limit: $utillimmin\)\n\n", $lpar, $util, $last_type, $alert_type_text, $managed, $graph_path, $email_graph );
        }
        else {
          sendmail( $mailfrom, $to, "$ltime_str: $alert_type_text alert for:\n $last_type: $lpar\n server: $managed\n managed by: $host\n avg utilization during last $tint mins: $util cores\n \($alert_type_text MAX limit: $utillim\)\n\n", $lpar, $util, $last_type, $alert_type_text, $managed, $graph_path, $email_graph );

        }
      }
    }
    if ( $alert_type_text =~ m/CPU Warning/ ) {
      if ( $cpulim_pct =~ /%/ ) {
        if ( $new_alert == 0 ) {
          sendmail( $mailfrom, $to, "$ltime_str: $alert_type_text alert for:\n $last_type: $lpar\n server: $managed\n managed by: $host\n avg utilization during last $tint mins: $util\n \($alert_type_text MAX limit: $utillim \($cpu_warning% from $cpulim_pct, max is $total_cpu cores\), $alert_type_text MIN limit: $utillimmin, $cpulimmin_pct\)\n\n", $lpar, $util, $last_type, $alert_type_text, $managed, $graph_path, $email_graph );
        }
        else {
          sendmail( $mailfrom, $to, "$ltime_str: $alert_type_text alert for:\n $last_type: $lpar\n server: $managed\n managed by: $host\n avg utilization during last $tint mins: $util cores\n \($alert_type_text MAX limit: $utillim \(max is $total_cpu cores\)\n\n", $lpar, $util, $last_type, $alert_type_text, $managed, $graph_path, $email_graph );
        }
      }
      else {
        if ( $new_alert == 0 ) {
          sendmail( $mailfrom, $to, "$ltime_str: $alert_type_text alert for:\n $last_type: $lpar\n server: $managed\n managed by: $host\n avg utilization during last $tint mins: $util\n \($alert_type_text MAX limit: $utillim \($cpu_warning% from $utillim, max is $total_cpu cores\), $alert_type_text MIN limit: $utillimmin\)\n\n", $lpar, $util, $last_type, $alert_type_text, $managed, $graph_path, $email_graph );
        }
        else {
          sendmail( $mailfrom, $to, "$ltime_str: $alert_type_text alert for:\n $last_type: $lpar\n server: $managed\n managed by: $host\n avg utilization during last $tint mins: $util cores\n \($alert_type_text MAX limit: $utillim \(max is $total_cpu cores\)\n\n", $lpar, $util, $last_type, $alert_type_text, $managed, $graph_path, $email_graph );
        }
      }
    }
  }

  return 1;
}

sub load_data_lpar {
  my $managedname         = shift;
  my $host                = shift;
  my $wrkdir              = shift;
  my $type_sam            = shift;
  my $act_time            = shift;
  my $lpars               = shift;
  my $HMC                 = shift;
  my $IVM                 = shift;
  my $SDMC                = shift;
  my $last_file           = shift;
  my $loadmins            = 0;
  my $MAX_ROWS            = 10000;
  my $MAX_ROWS_WORKAROUND = 100000;             # some HMCs have a problem with lslparutil -s d -r lpar/sys -h XY, solution is ...
  my $restrict_rows       = " -n $MAX_ROWS";    # workaround for HMC < 7.2.3 to do not exhaust memory

  if ( $lpars eq '' && $host eq '' && $managedname eq '' ) {
    print "No LPAR directive has been found, continuing with POOLs\n";
    return 1;
  }

  #if ( $lpars eq '' ) {
  #  error ("$host:$managedname - not defined lpars for data load, continuing with the others");
  #  return 1;
  #}

  # _shell variables for usage in shell cmd lines, must be to avoid a roblem with spaces in managed names

  $input       = "$wrkdir/$managedname/$host/in-alrt";
  $input_shell = $input;
  $input_shell =~ s/ /\\ /g;

  # here must be local time on HMC, need Unix time and date in text to have complete time
  my $date = `$SSH $hmc_user\@$host "export LANG=en_US; date \'+%m/%d/%Y %H:%M:%S\'"`;
  chomp($date);
  my $t          = str2time($date);    # ignore date +%s on purpose!!!
  my $local_time = time();

  # must be here as global variable to pass it to rrd graph creation
  # it must cope with different time on the HMC to get last 10minutes or so
  $time_diff = $local_time - $t;

  my $last_rec = get_last_time( $host, $managedname, $type_sam, "LPAR" );
  $loadmins = sprintf( "%.0f", ( $t - $last_rec ) / 60 + 5 );    # +5mins to be sure
  ( my $sec, my $ivmmin, my $ivmh, my $ivmd, my $ivmm, my $ivmy, my $wday, my $yday, my $isdst ) = localtime($last_rec);
  $ivmy += 1900;
  $ivmm += 1;
  print "last rec IVM   : $host:$managedname $ivmm/$ivmd/$ivmy $ivmh:$ivmmin HMC:$date\n" if $DEBUG;

  my $timerange       = " --minutes " . $loadmins . " ";
  my $loadsecs        = $loadmins * 60;
  my $hmc_start_utime = $t - $loadsecs;

  # Load lpar data
  print "fetching HMC   : $host:$managedname lpar data\n" if $DEBUG;

  if ( $HMC == 1 ) {
    #
    # here is the workaround for HMC < 7.2.3 for the problem with exhasting the memory during lslparutil
    #
    my $rowCount = $MAX_ROWS;
    my $rowTotal = 0;
    my $mins     = 0;
    my $line     = "";
    my $repeat   = 0;
    while ( $rowCount == $MAX_ROWS ) {
      $repeat++;
      if ( $rowTotal == 0 ) {

        #print "--- $timerange  : $restrict_rows\n" if $DEBUG ;
        `$SSH $hmc_user\@$host "LC_ALL=en_US LANG=en_US LC_NUMERIC=en_US lslparutil -s s -r lpar $timerange $restrict_rows -m \\"$managedname\\" -F time,lpar_name,curr_proc_units,curr_procs,curr_sharing_mode,entitled_cycles,capped_cycles,uncapped_cycles,shared_cycles_while_active$mem_params$idle_param --filter \"event_types=sample\"" > $input_shell-$type_sam`;
      }
      else {
        ( my $time_end, my $lpar, my $curr_proc_units, my $curr_procs, my $curr_sharing_mode, my $entitled_cycles, my $capped_cycles, my $uncapped_cycles, my $shared_cycles_while_active ) = split( /,/, $line );
        my $unixt = str2time($time_end);

        #print "--- $unixt - $rowCount : $line \n" if $DEBUG ;
        ( my $sec, my $hmcmin, my $hmch, my $hmcd, my $hmcm, my $hmcy, my $wday, my $yday, my $isdst ) = localtime($unixt);
        $hmcy += 1900;
        $hmcm++;    # month + 1, it starts from 0 in unix

        if ( $unixt < $hmc_start_utime ) {
          print "end time reach : $host:$managedname $hmcy-$hmcm-$hmcd $hmch:$hmcmin(to be downloaded) - $time_end(downloaded): $unixt < $hmc_start_utime\n";
          last;     #already Rdownloaded required time range
        }

        print "fetching HMC   : $host:$managedname lpar data : next $MAX_ROWS : $hmcy-$hmcm-$hmcd $hmch:$hmcmin - $time_end\n" if $DEBUG;
        `$SSH $hmc_user\@$host "LC_ALL=en_US LANG=en_US LC_NUMERIC=en_US lslparutil -s s -r lpar $restrict_rows --endyear $hmcy --endmonth $hmcm --endday $hmcd --endhour $hmch --endminute $hmcmin -m \\"$managedname\\" -F time,lpar_name,curr_proc_units,curr_procs,curr_sharing_mode,entitled_cycles,capped_cycles,uncapped_cycles,shared_cycles_while_active$mem_params$idle_param --filter \"event_types=sample\"" >> $input_shell-$type_sam`;
      }
      open( FH, "< $input-$type_sam" ) || error( "Can't open $input-$type_sam : $!" . __FILE__ . ":" . __LINE__ ) && return 1;
      $rowCount = 0;
      while ( my $l = <FH> ) {
        chomp($l);
        $rowCount++;
        $line = $l;
      }
      close(FH);
      $rowTotal = $rowCount;
      $rowCount = $rowCount / $repeat;
    }
    print "fetched        : $host:$managedname $rowTotal rows\n" if $DEBUG;
  }
  if ( $IVM == 1 ) {
    `$SSH $hmc_user\@$host "LC_ALL=en_US LANG=en_US LC_NUMERIC=en_US lslparutil -r lpar --startyear $ivmy --startmonth $ivmm --startday $ivmd --starthour $ivmh --startminute $ivmmin -m \\"$managedname\\" -F time,lpar_id,curr_proc_units,curr_procs,curr_sharing_mode,entitled_cycles,capped_cycles,uncapped_cycles,donated_cycles$mem_params --filter \\\\\\"lpar_names=$lpars\\\\\\"" > $input_shell-$type_sam`;
  }
  if ( $SDMC == 1 ) {
    $lpars =~ s/&&1/\//g;
    $lpars =~ s/;/\\;/g;
    LoadDataModule::sdmc_lpar_load( $SSH, $hmc_user, $host, $ivmy, $ivmm, $ivmd, $ivmh, $ivmmin, $managedname, "$input_shell-$type_sam", $type_sam, 0, $lpars, $mem_params );

    #print STDERR "$SSH,$hmc_user,$host,$ivmy,$ivmm,$ivmd,$ivmh,$ivmmin,$managedname,\"$input_shell-$type_sam\",$type_sam,0,$lpars,$mem_params\n";
    # first 0 means that t is called from alerting --> HMC data input file must have "alert" suffix"
  }

  return 0;
}

sub load_pool_data {
  my $managedname         = shift;
  my $host                = shift;
  my $wrkdir              = shift;
  my $type_sam            = shift;
  my $act_time            = shift;
  my $lpars               = shift;
  my $HMC                 = shift;
  my $IVM                 = shift;
  my $SDMC                = shift;
  my $last_file           = shift;
  my $loadhours           = 0;
  my $loadmins            = 0;
  my $MAX_ROWS            = 10000;
  my $MAX_ROWS_WORKAROUND = 100000;             # some HMCs have a problem with lslparutil -s d -r lpar/sys -h XY, solution is ...
  my $restrict_rows       = " -n $MAX_ROWS";    # workaround for HMC < 7.2.3 to do not exhaust memory

  # _shell variables for usage in shell cmd lines, must be to avoid a roblem with spaces in managed names
  my $input_pool          = "$wrkdir/$managedname/$host/pool.in-alrt";
  my $input_pool_sh       = "$wrkdir/$managedname/$host/pool_sh.in-alrt";
  my $input_shell         = $input;
  my $input_pool_shell    = $input_pool;
  my $input_pool_sh_shell = $input_pool_sh;
  $input_shell         =~ s/ /\\ /g;
  $input_pool_shell    =~ s/ /\\ /g;
  $input_pool_sh_shell =~ s/ /\\ /g;

  # here must be local time on HMC, need Unix time and date in text to have complete time
  my $date = `$SSH $hmc_user\@$host "export LANG=en_US; date \'+%m/%d/%Y %H:%M:%S\'"`;
  chomp($date);
  my $t          = str2time($date);    # ignore date +%s on purpose!!!
  my $local_time = time();

  # must be here as global variable to pass it to rrd graph creation
  # it must cope with different time on the HMC to get last 10minutes or so
  $time_diff = $local_time - $t;

  my $last_rec = 0;
  if ( $lpars =~ m/^pool$/ ) {
    $last_rec = get_last_time( $host, $managedname, $type_sam, "POOL" );
  }
  else {
    $last_rec = get_last_time( $host, $managedname, $type_sam, "POOLSH" );
  }
  $loadmins = sprintf( "%.0f", ( $t - $last_rec ) / 60 + 5 );    # +5mins to be sure
  ( my $sec, my $ivmmin, my $ivmh, my $ivmd, my $ivmm, my $ivmy, my $wday, my $yday, my $isdst ) = localtime($last_rec);
  $ivmy += 1900;
  $ivmm += 1;

  my $timerange = " --minutes " . $loadmins . " ";

  # Load CPU pool data
  print "fetching HMC   : $host:$managedname pool data\n" if $DEBUG;

  if ( $step == 3600 ) {
    if ( $loadhours >= 1 ) {
      if ( $HMC == 1 ) {
        if ( $lpars =~ m/^pool$/ ) {
          `$SSH $hmc_user\@$host "LC_ALL=en_US LANG=en_US LC_NUMERIC=en_US lslparutil -s $type_sam -r pool  -h $loadhours $restrict_rows  -m \\"$managedname\\" -F time,total_pool_cycles,utilized_pool_cycles,configurable_pool_proc_units,borrowed_pool_proc_units,curr_avail_pool_proc_units  --filter \"event_types=sample\"" > $input_pool_shell-$type_sam`;
        }
        else {
          print "fetching HMC   : $host:$managedname shared pool data\n" if $DEBUG;
          `$SSH $hmc_user\@$host "LC_ALL=en_US LANG=en_US LC_NUMERIC=en_US lslparutil -s $type_sam -r procpool  -h $loadhours $restrict_rows -m \\"$managedname\\" -F time,shared_proc_pool_id,total_pool_cycles,utilized_pool_cycles  --filter \"event_types=sample\"" > $input_pool_sh_shell-$type_sam`;
        }
      }
      if ( $IVM == 1 ) {
        `$SSH $hmc_user\@$host "LC_ALL=en_US LANG=en_US LC_NUMERIC=en_US lslparutil -r pool --startyear $ivmy --startmonth $ivmm --startday $ivmd --starthour $ivmh --startminute $ivmmin  -m \\"$managedname\\" -F time,total_pool_cycles,utilized_pool_cycles,configurable_pool_proc_units,borrowed_pool_proc_units,curr_avail_pool_proc_units" > $input_pool_shell-$type_sam`;
      }
      if ( $SDMC == 1 ) {
        if ( $lpars =~ m/^pool$/ ) {
          LoadDataModule::sdmc_pool_load( $SSH, $hmc_user, $host, $ivmy, $ivmm, $ivmd, $ivmh, $ivmmin, $managedname, "$input_pool_shell-$type_sam", $type_sam );
        }
        else {
          print "fetching HMC   : $host:$managedname shared pool data\n" if $DEBUG;
          LoadDataModule::sdmc_procpool_load( $SSH, $hmc_user, $host, $ivmy, $ivmm, $ivmd, $ivmh, $ivmmin, $managedname, "$input_pool_sh_shell-$type_sam", $type_sam );
        }
      }
    }
  }
  else {
    if ( $HMC == 1 ) {
      if ( $lpars =~ m/^pool$/ ) {
        print "fetching HMC   : $host:$managedname pool data: $input_pool_shell-$type_sam\n" if $DEBUG;
        `$SSH $hmc_user\@$host "LC_ALL=en_US LANG=en_US LC_NUMERIC=en_US lslparutil -s s -r pool $timerange $restrict_rows -m \\"$managedname\\" -F time,total_pool_cycles,utilized_pool_cycles,configurable_pool_proc_units,borrowed_pool_proc_units,curr_avail_pool_proc_units  --filter \"event_types=sample\"" > $input_pool_shell-$type_sam`;
      }
      else {
        print "fetching HMC   : $host:$managedname shared pool data: $input_pool_sh_shell-$type_sam\n" if $DEBUG;
        `$SSH $hmc_user\@$host "LC_ALL=en_US LANG=en_US LC_NUMERIC=en_US lslparutil -s s -r procpool $timerange $restrict_rows -m \\"$managedname\\" -F time,shared_proc_pool_id,total_pool_cycles,utilized_pool_cycles  --filter \"event_types=sample\"" > $input_pool_sh_shell-$type_sam`;
      }
    }
    if ( $IVM == 1 ) {
      `$SSH $hmc_user\@$host "LC_ALL=en_US LANG=en_US LC_NUMERIC=en_US lslparutil -r pool --startyear $ivmy --startmonth $ivmm --startday $ivmd --starthour $ivmh --startminute $ivmmin  -m \\"$managedname\\" -F time,total_pool_cycles,utilized_pool_cycles,configurable_pool_proc_units,borrowed_pool_proc_units",curr_avail_pool_proc_units > $input_pool_shell-$type_sam`;
    }
    if ( $SDMC == 1 ) {
      if ( $lpars =~ m/^pool$/ ) {
        LoadDataModule::sdmc_pool_load( $SSH, $hmc_user, $host, $ivmy, $ivmm, $ivmd, $ivmh, $ivmmin, $managedname, "$input_pool_shell-$type_sam", $type_sam, 0 );
      }
      else {
        print "fetching HMC   : $host:$managedname shared pool data\n" if $DEBUG;
        LoadDataModule::sdmc_procpool_load( $SSH, $hmc_user, $host, $ivmy, $ivmm, $ivmd, $ivmh, $ivmmin, $managedname, "$input_pool_sh_shell-$type_sam", $type_sam, 0 );
      }
    }
  }

  return 0;
}

# error handling
sub error {
  my $text     = shift;
  my $act_time = localtime();
  chomp($text);

  print "ERROR          : $text : $!\n";
  print STDERR "$act_time: $text\n";

  return 1;
}

sub get_last_time {
  my $host           = shift;
  my $managedname    = shift;
  my $type_sam       = shift;
  my $lpar_pool      = shift;
  my $last_rec       = "";
  my $last_rec_file  = "";
  my $last_rec_def   = "";
  my $last_rec_human = "";

  # now try last.txt
  if ( -f "$wrkdir/$managedname/$host/$last_file_default" ) {
    open( FHLT, "< $wrkdir/$managedname/$host/$last_file_default" ) || error( "Can't open $wrkdir/$managedname/$host/$last_file_default: $! " . __FILE__ . ":" . __LINE__ ) && return 1;
    foreach my $line (<FHLT>) {
      chomp($line);
      $last_rec_human = $line;
      $last_rec_def   = str2time($line);
    }
    close(FHLT);
    my $ret = substr( $last_rec_def, 0, 1 );
    if ( $ret eq '' || $ret =~ /\D/ ) {
      error("Wrong input data, file : $wrkdir/$managedname/$host/$last_file_default : $last_rec_def");
      unlink("$wrkdir/$managedname/$host/$last_file_default");
    }
    else {
      print "last rec       : $host:$managedname $last_rec_human $wrkdir/$managedname/$host/$last_file_default\n";
      print "051 last_rec: $last_rec_def , $wrkdir/$managedname/$host/$last_file_default\n" if $DEBUG == 2;

      #return $last_rec_def;
    }
  }

  if ( -f "$wrkdir/$managedname/$host/$last_file-$lpar_pool" ) {
    open( FHLT, "< $wrkdir/$managedname/$host/$last_file-$lpar_pool" ) || error( "Can't open $wrkdir/$managedname/$host/$last_file-$lpar_pool $! " . __FILE__ . ":" . __LINE__ ) && return 1;
    foreach my $line (<FHLT>) {
      chomp($line);
      $last_rec_human = $line;
      $last_rec_file  = str2time($line);
    }
    close(FHLT);
    my $ret = substr( $last_rec_file, 0, 1 );
    if ( $ret eq '' || $ret =~ /\D/ ) {
      error("Wrong input data, file : $wrkdir/$managedname/$host/$last_file-$lpar_pool : $last_rec_file");
      unlink("$wrkdir/$managedname/$host/$last_file-$lpar_pool");
    }
    else {
      print "050 last_rec: $last_rec_file , $wrkdir/$managedname/$host/$last_file-$lpar_pool \n" if $DEBUG == 2;
      print "last rec       : $host:$managedname $last_rec_human $wrkdir/$managedname/$host/$last_file-$lpar_pool\n";

      #return $last_rec_file;
    }
  }

  if ( !$last_rec_def eq '' && isdigit($last_rec_def) == 1 ) {
    if ( !$last_rec_file eq '' && isdigit($last_rec_file) == 1 ) {
      if ( $last_rec_def > $last_rec_file ) {
        return $last_rec_def;
      }
      else {
        return $last_rec_file;
      }
    }
    else {
      return $last_rec_def;
    }
  }
  else {
    if ( !$last_rec_file eq '' && isdigit($last_rec_file) ) {
      return $last_rec_file;
    }
  }

  # old not accurate way how to get last time stamp, keeping it here as backup if above temp fails for any reason
  if ( -f "$wrkdir/$managedname/$host/mem.rr$type_sam" ) {

    # find out last record in the db (hourly)
    my $last_rec_raw;
    eval {
      RRDp::cmd qq(last "$wrkdir/$managedname/$host/mem.rr$type_sam" );
      eval { $last_rec_raw = RRDp::read; };
      if ($@) { print STDERR "DEBUG Error at " . __FILE__ . ":" . __LINE__ . "\n"; }
      chomp($$last_rec_raw);
    };
    if ($@) {
      error( $@ . __FILE__ . ":" . __LINE__ );
      return -1;
    }

    if ( $$last_rec_raw < 0 ) {    # Do not know why, but it sometimes happens!!!
      if ( -f "$wrkdir/$managedname/$host/pool.rr$type_sam" ) {

        # find out last record in the db (hourly)
        RRDp::cmd qq(last "$wrkdir/$managedname/$host/pool.rr$type_sam" );
        my $last_rec_raw;
        eval { $last_rec_raw = RRDp::read; };
        if ($@) { print STDERR "DEBUG Error at " . __FILE__ . ":" . __LINE__ . "\n"; }
        chomp($$last_rec_raw);
        return $$last_rec_raw;
      }
    }
    else {
      print "052 last_rec: $$last_rec_raw \n" if $DEBUG == 2;
      print "last rec       : $host:$managedname $$last_rec_raw $wrkdir/$managedname/$host/mem.rr$type_sam   \n";
      return $$last_rec_raw;
    }
  }

  return -1;
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
  my $subject         = "LPAR2RRD: $alert_type_text alert for $managed $last_type: $lpar, utilization is: $util cores";
  my $message_body;
  my @att_files;
  my @att_names;

  $lpar =~ s/\&\&1/\//g;

  if ( $alert_type_text =~ m/Swapping/ ) {

    # for swapping
    $subject = "LPAR2RRD: $alert_type_text alert for $managed $last_type: $lpar : $util";
  }

  print "Alert emailing : $alert_type_text $last_type: subj:$subject to:$mailto from:$mailfrom\n";

  $message_body .= "$text\n";
  if ( defined $web_ui_url && $web_ui_url ne '' ) {
    $message_body .= "\n\nCheck it out in the lpar2rrd UI: $web_ui_url\n";
  }
  $message_body .= "\n\n";
  my $managed_space = $managed;
  $managed_space =~ s/ /\\ /g;
  $managed_space =~ s/;//g;
  my $lpar_space = $lpar;
  $lpar_space =~ s/ /\\ /g;
  $lpar_space =~ s/;//g;

  if ( $email_graph > 0 && -f $graph_path ) {

    push @att_files, $graph_path;
    push @att_names, "$managed_space:$lpar_space.png";

    # sending 2nd graph for CPU pools : lpars aggregated
    $graph_path =~ s/\.png/-lpar.png/;
    if ( $email_graph > 0 && -f $graph_path ) {

      push @att_files, $graph_path;
      push @att_names, "$managed_space:$lpar_space-lpar.png";

    }
  }
  Xorux_lib::send_email( $mailto, $mailfrom, $subject, $message_body, \@att_files, \@att_names );
  foreach my $f_path (@att_files) {
    if ( -f $f_path ) {
      unlink($f_path);
    }
  }
  return 0;
}

sub read_rrd_pool {
  my $host        = shift;
  my $managedname = shift;
  my $lpar        = shift;
  my $wrkdir      = shift;
  my $tint        = shift;
  $lpar =~ s/\//&&1/g;    ### workaround for lpar name with /
  my $rrd      = "$wrkdir/$managedname/$host/$lpar.rrm";
  my $answ_out = "";

  print "040 read_rrd_pool: $host $managedname $lpar $tint\n" if $DEBUG == 2;

  if ( !-f $rrd ) {
    error( "lpar has not been found: $rrd : $host:$managedname:$lpar at " . __FILE__ . ":" . __LINE__ );
    return -1;
  }
  if ( $lpar =~ m/pool/ ) {
    $rrd =~ s/:/\\:/g;
    RRDp::cmd qq(graph "$tmpdir/name.png"
    "--start" "end-$tint-$time_diff"
    "DEF:totcyc=$rrd:total_pool_cycles:AVERAGE"
    "DEF:uticyc=$rrd:utilized_pool_cyc:AVERAGE"
    "DEF:cpu=$rrd:conf_proc_units:AVERAGE"
    "DEF:cpubor=$rrd:bor_proc_units:AVERAGE"
    "CDEF:totcpu=cpu,cpubor,+"
    "CDEF:cpuutil=uticyc,totcyc,GT,UNKN,uticyc,totcyc,/,IF"
    "CDEF:cpuutiltot=cpuutil,totcpu,*"
    "PRINT:cpuutiltot:AVERAGE:%3.3lf"
    );
  }
  else {
    $rrd =~ s/:/\\:/g;
    RRDp::cmd qq(graph "$tmpdir/name.png"
    "--start" "end-$tint"
    "DEF:max=$rrd:max_pool_units:AVERAGE"
    "DEF:res=$rrd:res_pool_units:AVERAGE"
    "DEF:totcyc=$rrd:total_pool_cycles:AVERAGE"
    "DEF:uticyc=$rrd:utilized_pool_cyc:AVERAGE"
    "CDEF:max1=max,res,-"
    "CDEF:cpuutil=uticyc,totcyc,GT,UNKN,uticyc,totcyc,/,IF"
    "CDEF:cpuutiltot=cpuutil,max,*"
    "PRINT:cpuutiltot:AVERAGE:%3.3lf"
    );
  }

  my $answer = "";
  eval { $answer = RRDp::read; };
  if ($@) { print STDERR "DEBUG Error at " . __FILE__ . ":" . __LINE__ . " answer:\'$answer\' for rrd:$rrd\n"; }

  print "008 read_rrd:answer : $rrd:\n $$answer\n" if $DEBUG == 2;
  my $once = 0;
  my @arr;
  if ( $answer ne "" ) {
    foreach my $answ ( split( /\n/, $$answer ) ) {
      if ( $once == 1 ) {
        $answ =~ s/ //g;
        my $ret = substr( $answ, 0, 1 );
        if ( $ret =~ /\D/ ) {
          next;
        }
        else {
          chomp($answ);
          $answ_out = $answ;
        }
      }
      else {
        if ( $answ =~ "ERROR" ) {
          error("Graph rrdtool error : $answ");
          if ( $answ =~ "is not an RRD file" ) {
            ( my $err, my $file, my $txt ) = split( /'/, $answ );
            error("Removing as it seems to be corrupted: $file");

            #unlink("$file") || error("Cannot rm $file : $! ".__FILE__.":".__LINE__) && return 1;
          }
          else {
            print "027 Graph rrdtool error : $answ" if $DEBUG == 2;
          }
        }
      }
      $once++;
    }
  }

  print "009 read_rrd:parsed: $answ_out ---- $lpar|$managedname|$host|$HMC\n" if $DEBUG == 2;
  if ( $answ_out eq '' ) {
    my $last_rec_raw;
    RRDp::cmd qq(last "$rrd" );
    eval { $last_rec_raw = RRDp::read; };
    if ($@) { print STDERR "DEBUG Error cannot do last $rrd at " . __FILE__ . ":" . __LINE__ . "\n"; }
    my $last_rec;
    if ( !defined $last_rec_raw ) {
      chomp($$last_rec_raw);
      $last_rec = localtime($$last_rec_raw);
    }
    error( "no CPU data has been found: $host:$managedname:$lpar, last data timestamp : $last_rec at " . __FILE__ . ":" . __LINE__ . "\n" );
    return -1;
  }
  return $answ_out;
}

sub read_rrd_pool_total {
  my $host        = shift;
  my $managedname = shift;
  my $lpar        = shift;
  my $wrkdir      = shift;
  my $tint        = shift;
  $lpar =~ s/\//&&1/g;    ### workaround for lpar name with /

  my $suffix_rrd;
  if    ( $lpar =~ m/^pool_total$/ )     { $suffix_rrd = "rrt"; }    #average
  elsif ( $lpar =~ m/^pool-total-max$/ ) { $suffix_rrd = "rxm"; }    #max
  else {
    error("not implemented : pool_total -> $lpar <- : $host $managedname)\n");
    return -1;
  }

  my $rrd = "$wrkdir/$managedname/$host/$lpar.$suffix_rrd";
  $rrd =~ s/===========doublecoma=========/\:/g;
  my $answ_out = "";

  print "040 read_rrd_pool_total: $host $managedname $lpar $tint\n" if $DEBUG == 2;

  if ( !-f $rrd ) {
    error( "lpar has not been found: $rrd : $host:$managedname:$lpar at " . __FILE__ . ":" . __LINE__ );
    return -1;
  }

  #  if ( $lpar =~ m/pool/ ) {
  $rrd =~ s/:/\\:/g;
  RRDp::cmd qq(graph "$tmpdir/name.png"
    "--start" "end-$tint-$time_diff"
    "DEF:capped=$rrd:capped_cycles:AVERAGE"
    "DEF:uncapped=$rrd:uncapped_cycles:AVERAGE"
    "DEF:entitled=$rrd:entitled_cycles:AVERAGE"
    "DEF:curr_proc_units=$rrd:curr_proc_units:AVERAGE"

    "CDEF:tot=capped,uncapped,+"
    "CDEF:util=tot,entitled,/,$cpu_max_filter,GT,UNKN,tot,entitled,/,IF"
    "CDEF:utilperct=util,100,*"
    "CDEF:utiltot=util,curr_proc_units,*"
    "PRINT:utiltot:AVERAGE: %3.3lf"
    );

  #  } ## end if ( $lpar =~ m/pool/ )

  #  else {
  #    $rrd =~ s/:/\\:/g;
  #    RRDp::cmd qq(graph "$tmpdir/name.png"
  #    "--start" "end-$tint-$time_diff"
  #    "DEF:max=$rrd:max_pool_units:AVERAGE"
  #    "DEF:res=$rrd:res_pool_units:AVERAGE"
  #    "DEF:totcyc=$rrd:total_pool_cycles:AVERAGE"
  #    "DEF:uticyc=$rrd:utilized_pool_cyc:AVERAGE"
  #    "CDEF:max1=max,res,-"
  #    "CDEF:cpuutil=uticyc,totcyc,GT,UNKN,uticyc,totcyc,/,IF"
  #    "CDEF:cpuutiltot=cpuutil,max,*"
  #    "PRINT:cpuutiltot:AVERAGE: %3.3lf"
  #    );
  #  } ## end else [ if ( $lpar =~ m/pool/ )]
  my $answer = "";
  eval { $answer = RRDp::read; };
  if ($@) { print STDERR "DEBUG Error at " . __FILE__ . ":" . __LINE__ . "\n"; }
  print "008 read_rrd:answer: $rrd:\n $$answer\n" if $DEBUG == 2;
  my $once = 0;
  foreach my $answ ( split( / /, $$answer ) ) {
    if ( $once == 1 ) {
      $answ =~ s/ //g;
      my $ret = substr( $answ, 0, 1 );
      if ( $ret =~ /\D/ ) {
        next;
      }
      else {
        chomp($answ);
        $answ_out = $answ;
      }
    }
    else {
      if ( $answ =~ "ERROR" ) {
        error("Graph rrdtool error : $answ");
        if ( $answ =~ "is not an RRD file" ) {
          ( my $err, my $file, my $txt ) = split( /'/, $answ );
          error("Removing as it seems to be corrupted: $file");

          #unlink("$file") || error("Cannot rm $file : $! ".__FILE__.":".__LINE__) && return 1;
        }
        else {
          print "027 Graph rrdtool error : $answ" if $DEBUG == 2;
        }
      }
    }
    $once++;
  }

  print "009 read_rrd:parsed: $answ_out ---- $lpar|$managedname|$host|$HMC\n" if $DEBUG == 2;
  if ( $answ_out eq '' ) {
    RRDp::cmd qq(last "$rrd" );
    my $last_rec_raw;
    eval { $last_rec_raw = RRDp::read; };
    if ($@) { print STDERR "DEBUG Error last \"$rrd\" at " . __FILE__ . ":" . __LINE__ . "\n"; }
    chomp($$last_rec_raw);
    my $last_rec = localtime($$last_rec_raw);
    error( "no CPU data has been found: $host:$managedname:$lpar, last data timestamp : $last_rec at " . __FILE__ . ":" . __LINE__ . "\n" );
    return -1;
  }
  return $answ_out;
}

sub load_rrd_lpar {
  my $managedname = shift;
  my $lpars       = shift;

  # get the latest used HMC
  my $is_server_excluded_from_rest = is_server_excluded_from_rest($managedname);
  if ( !$restapi || $is_server_excluded_from_rest ) {
    $host = get_hmc( $managedname, "in-m" );
  }
  else {
    $host = get_hmc( $managedname, "hmc_touch" );
  }
  $hmc_user = `\$PERL $basedir/bin/hmc_list.pl --username $host`;


  #2021-06-17T07:52:00.000Z
  my $TZ_HMC = 0;#  = `$SSH $hmc_user\@$host "date '+%z'"`;
  my $TS_HMC = 0;#  = `$SSH $hmc_user\@$host "date '+%Y-%m-%dT%H:%M:%S%z'"`;
  my $TS_HMCB= 0;# = `$SSH $hmc_user\@$host "date '+%m/%d/%Y %H:%M:%S'"`;
  if (!$restapi){
    $TZ_HMC  = `$SSH $hmc_user\@$host "date '+%z'"`;
    $TS_HMC  = `$SSH $hmc_user\@$host "date '+%Y-%m-%dT%H:%M:%S%z'"`;
    $TS_HMCB = `$SSH $hmc_user\@$host "date '+%m/%d/%Y %H:%M:%S'"`;
  }
  my $TZ_LOCAL = `date '+%z'`;
  chomp( $TZ_HMC, $TZ_LOCAL );
  chomp($TS_HMC);
  chomp($TS_HMCB);

  my $is_host_rest = is_host_rest($host);
  if ( $host eq '' ) {

    # something wrong
    return 1;
  }
  if ( $is_host_rest && !$is_server_excluded_from_rest ) {
    return 1;
  }

  print "022 Load data      : $host $managedname $lpars\n" if $DEBUG == 2;
  if ( -f "$wrkdir/$managedname/$host/SDMC" ) {
    $SDMC = 1;
    $HMC  = 0;
    $IVM  = 0;
  }
  else {
    $SDMC = 0;
    if ( -f "$wrkdir/$managedname/$host/IVM" ) {
      $IVM = 1;
      $HMC = 0;
    }
    else {
      $HMC = 1;
      $IVM = 0;
    }
  }

  if ( $SDMC == 0 && $IVM == 0 ) {
    $HMC = 1;
    my $hmcv = `$SSH $hmc_user\@$host "lshmc -v" 2>/dev/null|grep RM| tr -d \'[:alpha:]\'|tr -d \'[:punct:]\'`;
    $hmcv =~ s/ //g;
    $hmcv_num = substr( $hmcv, 0, 3 );

    #print "DEBUG : $hmcv_num $hmcv\n";
    #print OUT "HMC version    : $hmcv" if $DEBUG ;
    if ( $hmcv_num > 734 || $hmcv_num < 600 ) {

      #$hmcv_num < 6 for PureFlex, not exact but should be ok  (actually it is in 1.2.0 version: Mar 2013)
      # set params for lslparutil and AMS available from HMC V7R3.4.0 Service Pack 2 (05-21-2009)
      $mem_params = ",mem_mode,curr_mem,phys_run_mem,curr_io_entitled_mem,mapped_io_entitled_mem,mem_overage_cooperation";
    }
    else {
      print "HMC version    : $host $hmcv $hmcv_num - no AMS ready : $HMC - $SDMC\n" if $DEBUG;
      $mem_params = "";
    }
  }
  else {
    $mem_params = ",mem_mode,curr_mem,phys_run_mem,curr_io_entitled_mem,mapped_io_entitled_mem,mem_overage_cooperation";
  }

  if ( $HMC == 1 && $hmcv_num > 772 ) {

    # for support of CPU dedicated partitions, V7 R7.3.0 (May 20, 2011)
    $idle_param = ",idle_cycles";
  }
  else {
    $idle_param = "";
  }

  print "023 Load data      : $host $managedname $lpars\n" if $DEBUG == 2;

  my $return = load_data_lpar( $managedname, $host, $wrkdir, $type_sam, $ltime_str, $lpars, $HMC, $IVM, $SDMC, $last_file . "-LPAR" );
  print "014 load_data_lpar:return: $return\n" if $DEBUG == 2;
  if ( $return == 1 ) {

    # something wrong
    return 1;
  }

  print "014 LoadDataModule::load_data ($managedname,$host,$wrkdir,$input,$type_sam,$ltime_str,$HMC,$IVM,$SDMC,\n      $step,-,$last_file-LPAR,$no_time,0,0, $TZ_HMC, $TZ_LOCAL)\n" if $DEBUG == 2;

  if ( -f "$wrkdir/$managedname/$host/lpar_trans.txt" ) {

    # IVM/SDMC translation ids to names
    open( FHR, "< $wrkdir/$managedname/$host/lpar_trans.txt" );
    my $idx = 0;
    foreach my $line_trans (<FHR>) {
      chomp($line_trans);
      $lpar_trans[$idx] = $line_trans;
      $idx++;
    }
    close(FHR);
  }

  print "017 LoadDataModule::load_data lpar_trans[0]: $lpar_trans[0]\n" if $DEBUG == 2;
  LoadDataModule::load_data( $managedname, $host, $wrkdir, $input, $type_sam, $ltime_str, $HMC, $IVM, $SDMC, $step, $DEBUG, \@lpar_trans, $last_file . "-LPAR", $no_time, $SSH, $hmc_user, 0, 0, $TZ_HMC, $TZ_LOCAL );
  return 0;
}

sub pool_translate {
  my $lpar        = shift;
  my $managedname = shift;

  ### for cpu pool
  if ( $lpar eq "CPU pool" ) {
    return "pool";
  }

  # pool name translation
  if ( $lpar =~ m/all_pools/ ) {
    $lpar = "pool";
  }
  else {
    # open pool mapping file
    my @map               = "";
    my $managedname_space = $managedname;
    if ( $managedname =~ m/ / ) {    # workaround for server name with a space inside, nothing else works, grrr
      $managedname_space = "\"" . $managedname . "\"";
    }

    my $map_time        = 0;
    my $map_file_latest = "";
    foreach my $map_file (<$wrkdir/$managedname_space/*\/cpu-pools-mapping.txt>) {
      my $map_time_act = ( stat("$map_file") )[9];
      if ( $map_time_act > $map_time ) {
        $map_file_latest = $map_file;
        $map_time        = $map_time_act;
      }
    }
    if ( $map_file_latest eq '' || !-f $map_file_latest ) {
      error( "alert  : no shared pool mapping file has been found : $managedname:$lpar : $wrkdir/$managedname_space/*/cpu-pools-mapping.txt at " . __FILE__ . ":" . __LINE__ );
      return "";
    }
    open( FHP, "< $map_file_latest" );
    @map = <FHP>;
    close(FHP);

    my $found = 0;
    foreach my $line_map (@map) {
      chomp($line_map);

      #print "001 $line_map : $map_file_latest : $lpar\n";
      if ( $line_map !~ m/^[0-9].*,/ ) {

        #something wrong , ignoring
        next;
      }
      ( my $pool_indx_new, my $pool_name_new ) = split( /,/, $line_map );
      if ( $pool_name_new =~ m/^$lpar$/ ) {
        $lpar = "SharedPool$pool_indx_new";
        $found++;
        last;
      }
    }
    if ( $found == 0 ) {

      #print "alert error    :  could not found name for shared pool : $managedname:$lpar\n";
      error("alert  : could not found name for shared pool : $managedname:$lpar");
      return "";
    }
  }
  print "029 pool name found: $lpar\n" if $DEBUG == 2;
  return $lpar;
}

sub get_hmc {
  my $managedname = shift;
  my $file        = shift;
  my $host        = "";

  # get the latest used HMC
  my $host_allp = "";
  my $atime     = 0;

  my $managedname_space = $managedname;
  $managedname_space =~ s/===========doublecoma=========/:/g;
  if ( $managedname =~ m/ / ) {    # workaround for server name with a space inside, nothing else works, grrr
    $managedname_space = "\"" . $managedname . "\"";
  }

  $file =~ s/\//&&1/g;             ### workaround for lpar name with /

  $managedname_space =~ s/===========doublecoma=========/\:/g;
  foreach my $line_host (<$wrkdir/$managedname_space/*>) {
    if ( -d $line_host && -f "$line_host/$file" ) {
      my $atime_act = ( stat("$line_host/$file") )[9];
      if ( $atime_act > $atime ) {
        $host_allp = $line_host;
        $atime     = $atime_act;
      }
    }
  }

  if ( $atime == 0 ) {
    $file =~ s/\.rr[m|h]//;
    print "HMC no found   : could not found HMC for: $managedname:$file, LPAR does not exist?\n";
    error("Error  : could not found HMC for: $managedname:$file");
    return "";
  }

  # basename without direct function
  my @base = split( /\//, $host_allp );
  foreach my $m (@base) {
    $host = $m;
  }

  print "045 get_hmc: $host \n" if $DEBUG == 2;
  return $host;
}

sub load_rrd_pool {
  my $managedname                  = shift;
  my $pool                         = shift;
  my $is_server_excluded_from_rest = is_server_excluded_from_rest($managedname);

  # get the latest used HMC
  if ( !$restapi || $is_server_excluded_from_rest ) {
    $host = get_hmc( $managedname, "pool.in-m" );
  }
  else {
    $host = get_hmc( $managedname, "hmc_touch" );
  }
  $hmc_user = `\$PERL $basedir/bin/hmc_list.pl --username $host`;
  my $is_host_rest = is_host_rest($host);
  if ( $host eq '' ) {

    # something wrong
    return 1;
  }
  if ( $is_host_rest && !$is_server_excluded_from_rest ) {
    return 1;
  }

  #2021-06-17T07:52:00.000Z
  my $TZ_HMC = 0;#  = `$SSH $hmc_user\@$host "date '+%z'"`;
  my $TS_HMC = 0;#  = `$SSH $hmc_user\@$host "date '+%Y-%m-%dT%H:%M:%S%z'"`;
  my $TS_HMCB= 0;# = `$SSH $hmc_user\@$host "date '+%m/%d/%Y %H:%M:%S'"`;
  if (!$restapi){
    $TZ_HMC  = `$SSH $hmc_user\@$host "date '+%z'"`;
    $TS_HMC  = `$SSH $hmc_user\@$host "date '+%Y-%m-%dT%H:%M:%S%z'"`;
    $TS_HMCB = `$SSH $hmc_user\@$host "date '+%m/%d/%Y %H:%M:%S'"`;
  }
  my $TZ_LOCAL = `date '+%z'`;
  chomp( $TZ_HMC, $TZ_LOCAL );
  chomp($TS_HMC);
  chomp($TS_HMCB);

  print "053 Load data pool : $host $managedname $pool \n" if $DEBUG == 2;
  if ( -f "$wrkdir/$managedname/$host/SDMC" ) {
    $SDMC = 1;
    $HMC  = 0;
    $IVM  = 0;
  }
  else {
    $SDMC = 0;
    if ( -f "$wrkdir/$managedname/$host/IVM" ) {
      $IVM = 1;
      $HMC = 0;
    }
    else {
      $HMC = 1;
      $IVM = 0;
    }
  }
  print "054 Load data pool : $host $managedname $pool \n" if $DEBUG == 2;
  my $return = load_pool_data( $managedname, $host, $wrkdir, $type_sam, $ltime_str, $pool, $HMC, $IVM, $SDMC, $last_file . "-POOL" );
  if ( $return == 1 ) {

    # something wrong
    print "055 load_data_lpar:return: $return\n" if $DEBUG == 2;
    return 1;
  }

  my $input_pool    = "$wrkdir/$managedname/$host/pool.in-alrt";
  my $input_pool_sh = "$wrkdir/$managedname/$host/pool_sh.in-alrt";
  $input_pool_sh =~ s/ /\\ /g;
  my @lpar_trans = "";

  if ( $pool =~ m/^pool$/ ) {

    # all pools
    print "056 LoadDataModule::load_data_pool ($managedname,$host,$wrkdir,$input,\n      $type_sam,$ltime_str,$HMC,$IVM,$SDMC,$step,$DEBUG,$last_file-POOL,$no_time,0,0, $TZ_HMC, $TZ_LOCAL)\n" if $DEBUG == 2;
    LoadDataModule::load_data_pool( $managedname, $host, $wrkdir, $input, $type_sam, $ltime_str, $HMC, $IVM, $SDMC, $step, $DEBUG, \@lpar_trans, $last_file . "-POOL", $input_pool, $no_time, 0, 0, $TZ_HMC, $TZ_LOCAL );
  }
  else {
    my $pool_list_file = "pool_list.txt";
    my @pool_list      = "";
    $input_pool_sh =~ s/\\//g;    # we are at Perl so no backslash, it does not work with it
    $last_file     =~ s/\\//g;
    print "056 LoadDataModule::load_data_pool_sh ($managedname,$host,$wrkdir,$input,\n     $type_sam,$ltime_str,$HMC,$IVM,$SDMC,$step,$DEBUG,-,$last_file.-POOLSH,$input_pool_sh,ssh,$hmc_user,-,$pool_list_file,$no_time,0,0, $TZ_HMC, $TZ_LOCAL)\n" if $DEBUG == 2;
    LoadDataModule::load_data_pool_sh( $managedname, $host, $wrkdir, $input, $type_sam, $ltime_str, $HMC, $IVM, $SDMC, $step, $DEBUG, \@lpar_trans, $last_file . "-POOLSH", $input_pool_sh, $SSH, $hmc_user, \@pool_list, $pool_list_file, $no_time, 0, 0,  $TZ_HMC, $TZ_LOCAL );
  }

  return 0;
}

sub procpoolagg {

  # just fake function, it is normally in lpar2rrd.pl byt called is from LoadDataModule
  return 1;
}

sub isdigit {
  my $digit = shift;
  my $text  = shift;

  return 1 if !defined $digit;

  my $digit_work = $digit;
  $digit_work =~ s/[0-9]//g;
  $digit_work =~ s/\.//;
  $digit_work =~ s/e//;
  $digit_work =~ s/-//;
  $digit_work =~ s/\+//;

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

sub extern_alarm {
  my $host            = shift;
  my $managed         = shift;
  my $lpar            = shift;
  my $util            = shift;
  my $utillim         = shift;
  my $utillimmin      = shift;
  my $ltime_str       = shift;
  my $last_type       = shift;
  my $alert_type_text = shift;
  my $extern_alert    = shift;

  if ( !-x "$extern_alert" ) {
    error("EXTERN_ALERT is set but the file is not executable : $extern_alert");
    return 1;
  }

  print "Alert external : $last_type=$host:$managed:$lpar utilization=$util\n";

  $managed =~ s/===========doublecoma=========/:/g;
  if ( $new_alert == 0 ) {
    system( "$extern_alert", "$alert_type_text", "$last_type", "$managed", "$lpar", "$util", "$utillim", "$utillimmin", "$host" );
  }
  else {
    system( "$extern_alert", "$alert_type_text", "$last_type", "$managed", "$lpar", "$util", "$utillim", "$host" );
  }

  return 1;
}

sub create_graph {
  my $host        = shift;
  my $server      = shift;
  my $lpar        = shift;
  my $graph_path  = shift;
  my $basedir     = shift;
  my $bindir      = shift;
  my $line        = shift;
  my $email_graph = shift;
  my $type        = shift;
  my $log         = "$tmpdir/alert.log";
  my $perl        = $ENV{PERL};

  my $lpar_url = $lpar;
  $lpar_url =~ s/\//&&1/g;
  my $server_url = $server;
  $lpar_url   =~ s/([^a-zA-Z0-9_.!~*()'\''-])/sprintf("%%%02X", ord($1))/ge;
  $server_url =~ s/([^a-zA-Z0-9_.!~*()'\''-])/sprintf("%%%02X", ord($1))/ge;

  print "Graph creation : $host:$server:$lpar\n";

  # set env for graphing script which is normally called via CGI-BIN
  if ( $line =~ m/^LPAR:/ ) {

    # for LPARs
    $ENV{'QUERY_STRING'} = "host=$host&server=$server_url&lpar=$lpar_url&item=lpar&time=d&type_sam=m&detail=0&none=none&none1=none";
  }
  else {
    if ( $line =~ m/swap/ ) {

      # for swapping
      $ENV{'QUERY_STRING'} = "host=$host&server=$server_url&lpar=$lpar_url&item=paging&time=d&type_sam=m&detail=0&none=none&none1=none";
    }
    else {
      if ( $lpar =~ m/^pool$/ ) {

        # all pools
        $ENV{'QUERY_STRING'} = "host=$host&server=$server_url&lpar=$lpar_url&item=pool&time=d&type_sam=m&detail=0&none=none&none1=none";
      }
      else {
        # shared pools
        $ENV{'QUERY_STRING'} = "host=$host&server=$server_url&lpar=$lpar_url&item=shpool&time=d&type_sam=m&detail=0&none=none&none1=none";
      }
    }
  }
  print "calling grapher: $perl $bindir/detail-graph-cgi.pl alarm $graph_path $email_graph > $log\n";
  print "QUERY_STRING   : $ENV{'QUERY_STRING'}\n";

  `$perl $bindir/detail-graph-cgi.pl alarm $graph_path $email_graph > $log 2>&1`;

  # all pools - lpar aggregated
  if ( $line =~ m/^POOL:/ && $lpar =~ m/^pool$/ ) {

    # Load all lpars to get latest data for aggregated graphs
    load_rrd_lpar( $server, "" );

    $ENV{'QUERY_STRING'} = "host=$host&server=$server_url&lpar=$lpar_url&item=lparagg&time=d&type_sam=m&detail=0&none=none";
    $graph_path =~ s/\.png/-lpar.png/;
    `$perl $bindir/detail-graph-cgi.pl alarm $graph_path $email_graph >> $log 2>&1`;
  }

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

######################################################
# Swapping part
######################################################

# go through all SWAP lines
sub swapping {
  my ( $mailfrom, $email_graph, $nagios, $extern_alert, $lines_sort_tmp ) = @_;
  my @lines_sort = @{$lines_sort_tmp};

  load_all_lpars();

  # to avoid double HMC setup
  my $time_mmm = 0;

  # go through all lines from the cfg file
  foreach my $line (@lines_sort) {
    chomp($line);
    if ( $line =~ m/^#/ || $line !~ m/^SWAP/ ) {
      next;    # exclude comments and no swapping rules
    }

    ( my $trash, my $server, my $lpar, my $swaplim, my $tint, my $trepeat, my $email ) = split( /:/, $line );

    print "001 $line : $lpar - $server - $swaplim - $tint - $trepeat - $email\n" if $DEBUG == 2;

    my $server_prev = "";
    my $lpar_prev   = "";

    # compare each line "SWAP:..." with list of all lpars with memory data ".mmm" which are stored in @lpar_all_list
    # it is due to regular expressions
    foreach my $line_all (@lpar_all_list) {
      if ( $line_all =~ m/^$server\/.*\/$lpar$/ ) {

        # separate actual server, hmc and lpar from $line_all
        my $line_all_tmp = $line_all;
        $line_all_tmp =~ s/^$wrkdir\///;
        ( my $server_new, my $host, my $lpar_new ) = split( /\//, $line_all_tmp );
        if ( $server_prev eq '' && $lpar_prev eq '' ) {

          # first one
          print "003 $line_all\n" if $DEBUG == 2;
          swapping_lpar_work( $line_all, $server_new, $host, $lpar_new, $swaplim, $tint, $trepeat, $email, $extern_alert, $nagios, $email_graph );
          $server_prev = $server_new;
          $lpar_prev   = $lpar_new;
        }
        else {
          if ( $server_prev =~ m/^$server_new$/ && $lpar_prev =~ m/^$lpar_new$/ ) {
            print "004 $line_all : avoid - double HMC\n" if $DEBUG == 2;
            next;    # double HMC
          }
          else {
            print "005 $line_all\n" if $DEBUG == 2;
            swapping_lpar_work( $mailfrom, $line_all, $server_new, $host, $lpar_new, $swaplim, $tint, $trepeat, $email, $extern_alert, $nagios, $email_graph );
            $server_prev = $server_new;
            $lpar_prev   = $lpar_new;
          }
        }
      }
    }
  }
  return 1;
}

# find all lpars with memory data and keep then to can search through regular expressions
sub load_all_lpars {
  my $lpar_indx   = 0;
  my $server_indx = 0;

  # goes through all hmc/server and find all lpars
  foreach my $server (<$wrkdir/*>) {
    if ( -l "$server" ) {

      # avoid symlinks
      next;
    }
    if ( -f "$server" ) {

      # avoid regular files
      next;
    }

    my $server_space = $server;
    if ( $server =~ m/ / ) {    # workaround for server name with a space inside, nothing else works, grrr
      $server_space = "\"" . $server . "\"";
    }

    foreach my $lpar_fullp (<$server_space/*/*/pgs.mmm>) {
      chomp($lpar_fullp);
      if ( $lpar_fullp =~ m/--NMON--/ ) {
        next;    # exclude NMON files, it is not testd yet
      }
      $lpar_fullp =~ s/\.mmm//;

      # place lpars into an array
      $lpar_all_list[$lpar_indx] = $lpar_fullp;
      $lpar_all_list[$lpar_indx] =~ s/^$wrkdir\///g;    # it must be here due to sorting purposes bellow
      $lpar_indx++;

      #print "33 $lpar_fullp\n";
    }
    $server_list_all[$server_indx] = $server;

    # basename without direct function
    my @link_l = split( /\//, $server_list_all[$server_indx] );
    foreach my $m (@link_l) {
      $server_list_all[$server_indx] = $m;              #lpar name, basename from $file
    }

    $server_indx++;

  }

  # sorting lpars due to dual HMC ....
  @lpar_all_list = sort { ( split '/', $a )[2] cmp( split '/', $b )[2] } @lpar_all_list;

  #foreach my $a (@lpar_all_list) {
  #  print "001 $a\n";
  #}
  return 1;
}

# check each lpar for swapping
sub swapping_lpar_work {
  my $mailfrom        = shift;
  my $line_all        = shift;
  my $server          = shift;
  my $host            = shift;
  my $lpar            = shift;
  my $swaplim         = shift;
  my $tint            = shift;
  my $trepeat         = shift;
  my $email           = shift;
  my $extern_alert    = shift;
  my $nagios          = shift;
  my $email_graph     = shift;
  my $ltime_rep       = "";
  my $alert_type_text = "";
  my $ltime_human     = "";
  $alert_type_text = "Swapping";

  $swaplim =~ s/ //g;
  $tint    =~ s/ //g;
  $trepeat =~ s/ //g;
  $email   =~ s/ //g;

  if ( $lpar eq '' ) {
    error("lpar name is not provided : $line_all");
    next;
  }

  if ( $swaplim eq '' ) {

    #error("SWAP max limit is not provided: $host:$server:$lpar : $line_all");
    return 0;
  }
  my $ret = isdigit( $swaplim, "swaplim: $swaplim : $line_all" );
  if ( $ret == 0 ) {
    return 0;
  }

  if ( $tint eq '' ) {
    if ( $cpu_average_time_default eq '' ) {
      error("PEAK_TIME is not provided and default is not specified as well: $host:$server:$lpar : $line_all");
      return 0;
    }
    else {
      $tint = $cpu_average_time_default * 60;    # in seconds
    }
  }
  else {
    $ret = isdigit( $tint, "tint: $tint : $line_all" );
    if ( $ret == 0 ) {
      return 0;
    }
    $tint = $tint * 60;    # in seconds
  }

  if ( $trepeat eq '' ) {
    if ( $repeat_default eq '' ) {
      error("REPEAT is not provided and default is not specified as well: $host:$server:$lpar : $line_all");
      return 0;
    }
    else {
      $trepeat = $repeat_default * 60;    # in seconds
    }
  }
  else {
    $ret = isdigit( $trepeat, "trepeat: $trepeat : $line_all" );
    if ( $ret == 0 ) {
      next;
    }
    $trepeat = $trepeat * 60;    # in seconds
  }

  # Note there must not be email alerting
  if ( $email eq '' ) {
    if ( !$email_default eq '' ) {
      $email = $email_default;
    }
  }

  my $page_in = read_rrd_swap( $line_all, $server, $lpar, $wrkdir, $tint, "page_in" );
  if ( $page_in == -1 ) {
    return 1;                    # all ok
  }

  my $page_out = read_rrd_swap( $line_all, $server, $lpar, $wrkdir, $tint, "page_out" );
  if ( $page_out == -1 ) {
    return 1;                    # all ok
  }

  if ( $page_in > $swaplim && $page_out > $swaplim ) {

    #print "010 SWAPPING : $line_all : page_in: $page_in kB/s, page_out: $page_out kB/s, limit: $swaplim kB/s \n";

    # check whether to send alam or not (retention)
    my $send_alarm = 1;
    foreach my $line_rep (@lines_rep) {
      chomp($line_rep);
      if ( $line_rep eq '' ) {
        next;
      }
      ( my $name_rep, $ltime_rep, $ltime_human ) = split( /\|/, $line_rep );
      if ( "$name_rep" eq '' ) {
        next;
      }
      if ( "$name_rep" =~ m/^$host$server$lpar-SWAP$/ && $new_alert == 0 ) {    # SWAP string is significant for swaping
        if ( $ltime_rep + $trepeat > $ltime ) {
          $send_alarm = 0;
        }
        last;
      }
      if ( "$name_rep" =~ m/^$server$lpar-SWAP$/ && $new_alert == 1 ) {         # SWAP string is significant for swaping
        if ( $ltime_rep + $trepeat > $ltime ) {
          $send_alarm = 0;
        }
        last;
      }
    }
    if ( $send_alarm == 0 ) {

      # do not send alarm
      my $ltime_rep_str = time2string($ltime_rep);
      my $ltime_str     = time2string($ltime);
      print "125 $host:$server:$lpar : do not send alarm this time : $ltime_rep_str + $trepeat < $ltime_str \n" if $DEBUG == 2;
      print "Alert not send : $alert_type_text $server:$lpar  page_in: $page_in kB/s, page_out: $page_out kB/s, limit: $swaplim kB/s :  not this time due to repeat time $ltime_rep_str + $trepeat secs > $ltime_str\n";
      return 1;
    }

    # update retention alerts
    open( FHW, ">> $alert_repeat" ) || error( "could not open $alert_repeat : $! " . __FILE__ . ":" . __LINE__ ) && return 1;
    print FHW "$host$server$lpar-SWAP|$ltime|$ltime_str\n";
    close(FHW);

    # print alarm to stdout
    print "099 $alert_type_text ALARM: $ltime_str: $server:$lpar,  page_in: $page_in kB/s, page_out: $page_out kB/s, limit: $swaplim kB/s\n" if $DEBUG == 2;
    print "Alert logged   : $alert_type_text ALARM: $ltime_str: $server:$lpar,  page_in: $page_in kB/s, page_out: $page_out kB/s, limit: $swaplim kB/s\n";

    # log an alarm to a file : alert.log
    open( FHL, ">> $alert_history" ) || error( "could not open $alert_history: $! " . __FILE__ . ":" . __LINE__ ) && return 1;

    #print FHL "$ltime_str: $alert_type_text $server:$lpar,  page_in: $page_in kB/s, page_out: $page_out kB/s, limit: $swaplim kB/s\n";
    print FHL "$ltime_str; $alert_type_text; $server; $lpar; page_in: $page_in kB/s, page_out: $page_out kB/s, limit: $swaplim kB/s\n";
    close(FHL);

    # mail alarm
    if ( !$email eq '' ) {
      send_mail( $mailfrom, $email, $host, $server, $lpar, "page_in: $page_in kB/s, page_out: $page_out kB/s", $swaplim, 0, $ltime_str, $email_default, "", $alert_type_text, $email_graph, "swap", $lpar, $tint );
    }

    $lpar =~ s/\&\&1/\//g;

    # nagios alarm
    if ( $nagios == 1 ) {
      nagios_alarm( $host, $server, $lpar, "page_in: $page_in kB/s, page_out: $page_out kB/s", $swaplim, 0, $ltime_str, "", $alert_type_text );
    }

    # extern alert
    if ( !$extern_alert eq '' ) {
      extern_alarm( $host, $server, $lpar, "page_in: $page_in kB/s, page_out: $page_out kB/s", $swaplim, 0, $ltime_str, "", $alert_type_text, $extern_alert );
    }

  }
  else {
    $lpar =~ s/\&\&1/\//g;
    print "No alerting    :$alert_type_text $server:$lpar act: page_in: $page_in kB/s, page_out: $page_out kB/s\n" if $DEBUG == 2;
  }

  return 1;
}

sub read_rrd_swap {
  my $line_all    = shift;
  my $server      = shift;
  my $lpar        = shift;
  my $wrkdir      = shift;
  my $tint        = shift;
  my $page_in_out = shift;                     # page_in or page_out
  my $rrd         = "$wrkdir/$line_all.mmm";
  my $page        = "";
  my $rrd_org     = $rrd;

  #print "040 read_rrd_swap: $line_all :  $server $lpar $tint\n" if $DEBUG == 2;

  #$rrd =~ s/\//&&1/g;   ### workaround for lpar name with /

  if ( !-f $rrd ) {
    error("SWAP: lpar has not been found: $rrd :$server:$lpar");
    return -1;
  }

  my $rrd_time   = ( stat("$rrd") )[9];
  my $ltime      = time();                # alwas do it here, do not use any global one
  my $delta_time = 0;
  if ( ( $ltime - $rrd_time ) < 1800 ) {

    # if rrd file is not older than 30m then exactly count last 10minutes to geat data from whole last interval
    #  although it does not nhave to be last 10m (agent send data every 10m)
    # when diff more than 30m then something is wrong == no data
    $delta_time = $ltime - $rrd_time;
  }

  #print "033 $delta_time = $ltime - $rrd_time : $tint-$time_diff-$delta_time\n";

  $rrd =~ s/:/\\:/g;
  RRDp::cmd qq(graph "$tmpdir/name.png"
    "--start" "now-$delta_time-$tint-$time_diff"
    "DEF:pi=$rrd:$page_in_out:AVERAGE"
    "CDEF:pi_b=pi,4096,*"
    "CDEF:pi_kb=pi_b,1024,/"
    "PRINT:pi_kb:AVERAGE: %6.1lf"
  );

  # there must be at least one decimal place otherwise parsing does not work well
  my $answer = "";
  eval { $answer = RRDp::read; };
  if ($@) { print STDERR "DEBUG Error at " . __FILE__ . ":" . __LINE__ . "\n"; }

  #print "008 read_rrd:answer: $rrd:\n $$answer\n" if $DEBUG == 2;
  chomp($$answer);
  ( my $trash, $page ) = split( / +/, $$answer );
  chomp($page);

  #print "008 read_rrd:answer: $rrd:\n $$answer\n==$page \n" ;
  if ( $$answer =~ "ERROR" ) {
    error("SWAP: Graph rrdtool error : $$answer");
    if ( $$answer =~ "is not an RRD file" ) {
      ( my $err, my $file, my $txt ) = split( /'/, $$answer );
      error("SWAP: Removing as it seems to be corrupted: $file");

      #unlink("$file") || error("Cannot rm $file : $!".__FILE__.":".__LINE__) && return 1;
    }
    else {
      print "027 Graph rrdtool error : $$answer" if $DEBUG == 2;
    }
  }

  #print "033 $page - $rrd\n";
  #print "009 read_rrd_swap:parsed: \"$page\"  $lpar|$server|$line_all|$HMC ; rrd:$rrd\n" if $DEBUG == 2;
  if ( $page eq '' || !isdigit($page) ) {
    my $last_rec_raw;
    eval {
      RRDp::cmd qq(last "$rrd_org" );
      eval { $last_rec_raw = RRDp::read; };
      if ($@) { print STDERR "DEBUG Error at " . __FILE__ . ":" . __LINE__ . "\n"; }
    };
    if ($@) {
      error( "$rrd : $@ " . __FILE__ . ":" . __LINE__ );    # print it only first time
      return -1;
    }
    chomp($$last_rec_raw);
    my $last_rec = localtime($$last_rec_raw);

    #error ("SWAP: no new data found     : $rrd :$server:$lpar, last data timestamp : $last_rec");
    # do not writ into a error log, a lot of such recoreds then is there
    return -1;
  }

  if ( $page > 100000 ) {

    # when paging more than 100MB/sec then probably caused by counter reset
    return 0;
  }
  return $page;
}

sub time2string {
  my $utime = shift;

  my ( $sec, $min, $hour, $day, $month, $year, $wday, $yday, $isdst ) = localtime($utime);
  my $str_time = $day . "." . $month . "." . $year . " " . $hour . ":" . $min;
  return $str_time;
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

sub snmp_trap_alarm {
  my $trap_host       = shift;
  my $host            = shift;
  my $managed         = shift;
  my $lpar            = shift;
  my $util            = shift;
  my $utillim         = shift;
  my $utillimmin      = shift;
  my $ltime_str       = shift;
  my $last_type       = shift;
  my $alert_type_text = shift;

  if ( defined $ENV{LPAR2RRD_SNMPTRAP_COMUNITY} ) {
    $community_string = $ENV{LPAR2RRD_SNMPTRAP_COMUNITY};
  }

  my $SNMP_PEN = "40540";
  my $PRE      = "1.3.6.1.4.1.40540";

  print "Alert SNMP TRAP: $last_type=$lpar:$managed:$lpar utilization=$util\n";

  # this command sends canonical SNMP names
  # `snmptrap -v 1 -c $community_string $trap_host XORUX-MIB::lpar2rrdSendTrap '' 6 7 '' XORUX-MIB::lpar2rrdHmcName s '$hmc' XORUX-MIB::lpar2rrdServerName s '$host' XORUX-MIB::lpar2rrdLparName s '$lpar' XORUX-MIB::lpar2rrdValue s '$util' XORUX-MIB::lpar2rrdSu bsystem s '$alert_type_text'`;
  # this one send numerical (it's OK for our needs)

  my $snmp_exe = "/opt/freeware/bin/snmptrap";    # AIX place
  if ( !-f "$snmp_exe" ) {
    $snmp_exe = "/usr/bin/snmptrap";              #linux one
    if ( !-f "$snmp_exe" ) {
      $snmp_exe = "snmptrap";                     # lets hope it is in the PATH
    }
  }

  print "SNMP trap exec : $snmp_exe -v 1 -c '$community_string' '$trap_host' $PRE.1.0.1.0.7 \'\' 6 7 \'\' $PRE.1.1 s $host $PRE.1.2 s $managed $PRE.1.3 s $lpar $PRE.1.4 s \'$alert_type_text\' $PRE.1.5 s $util\n";
  my $out = `$snmp_exe -v 1 -c '$community_string' '$trap_host' $PRE.1.0.1.0.7 '' 6 7 '' $PRE.1.1 s '$host' $PRE.1.2 s '$managed' $PRE.1.3 s '$lpar' $PRE.1.4 s '$alert_type_text' $PRE.1.5 s '$util'  2>&1;`;
  if ( $out =~ m/not found/ ) {
    error("SNMP Trap: $snmp_exe binnary has not been found, install net-snmp as per https://www.lpar2rrd.com/alerting_trap.htm ($out)");
  }
  if ( $out =~ m/Usage: snmptrap/ ) {
    error("SNMP Trap: looks like you use native AIX /usr/sbin/snmptrap, it is not supported, check here: https://www.lpar2rrd.com/alerting_trap.htm");
  }

  return 1;
}

sub is_host_rest {
  my $host  = shift;
  my %hosts = %hosts_configuration;
  foreach my $alias ( keys %hosts ) {
    if ( $host eq $hosts{$alias}{host} || $host eq $hosts{$alias}{hmc2} ) {
      if ( defined $hosts{$alias}{auth_api} && $hosts{$alias}{auth_api} ) {
        return 1;
      }
      else {
        return 0;
      }
      return $hosts{$alias}{auth_api};
    }
  }
}

sub is_server_excluded_from_rest {
  my $managedname      = shift;
  my $excluded_servers = shift;
  foreach my $e ( @{$excluded_servers} ) {
    if ( $managedname eq $e->{name} ) {
      if ( $e->{exclude_data_load} ) {
        return 1;
      }
    }
  }
  return 0;
}

=pod
sub is_server_excluded_from_rest{
  my $managedname = shift;
  my $excluded_servers;
  if (-e "$basedir/etc/web_config/exclude_rest_api.json"){
    $excluded_servers = read_json("$basedir/etc/web_config/exclude_rest_api.json");
  }
  else{
    return 0;
  }
  $excluded_servers = $excluded_servers->{exclude};
  foreach my $e (@{$excluded_servers}){
    if ($managedname eq $e->{name}){
      if ($e->{exclude_data_load}){
        return 1;
      }
    }
  }
  return 0;
}
=cut

sub read_json {
  my $src = shift;
  if ( !defined $src || $src eq "" ) {
    print "Path to json file(\"$src\") not defined, can't read it in function read_json()\n";
    return -1;
  }
  my $read;
  my $rawcfg;    # helper for file reading
                 # read from JSON file
  if ( open( CFG, "$src" ) ) {
    local $/ = undef;    # required for re-read of encode_json pretty output
    $rawcfg = <CFG>;
    if ($rawcfg) {
      $read = decode_json($rawcfg);
    }
    close CFG;
    return $read;
  }
  else {
    # error handling
    error( __FILE__ . ":" . __LINE__ . "Cannot read $src as .json file\n" );
  }
}

sub is_any_host_rest {
  if ( defined $ENV{DEMO} && $ENV{DEMO} == 1 ) {
    return 1;
  }
  my %hosts  = %{ HostCfg::getHostConnections("IBM Power Systems") };
  my $result = 0;
  foreach my $alias ( keys %hosts ) {
    if ( defined $hosts{$alias}{auth_api} && $hosts{$alias}{auth_api} ) {
      $result = 1;
    }
  }
  return $result;
}

sub check_line_valid {
  my $line        = shift;
  my @arr         = split( ':', $line );    # POOL:Power770:all_pools:CPU:0::::::
  my $server_name = $arr[1];
  $server_name =~ s/===========doublecoma=========/:/g if ( defined $arr[1] && $arr[1] ne "" );

  if ( length( premium() ) == 6 ) {
    return 0;
  }
  if ( $line =~ m/^LPAR:/ ) {

    #print "Checking $line - valid?\n";
    if ( $alert_def->{''} || $alert_def->{$server_name} ) {    # allow
      return 0;
    }
    else {                                                     #do not allow
      return 1;
    }
  }
  elsif ( $line =~ m/^POOL:/ ) {

    #print "Checking $line - valid?\n";
    if ( $alert_def->{$server_name} ) {

      #print "Allow $arr[1]\n";
      return 0;
    }
    else {
      #print "!!! DO NOT Allow \'$arr[1]\'\n";
      return 1;
    }
  }
  else {
    #print "Do I need to check for alerting?\n";
    #print "$line\n";
  }

  return 0;
}

sub service_now {
  use LWP::UserAgent;
  use HTTP::Request;

  my $host            = shift;
  my $managed         = shift;
  my $lpar            = shift;
  my $util            = shift;
  my $utillim         = shift;
  my $utillimmin      = shift;
  my $ltime_str       = shift;
  my $last_type       = shift;
  my $alert_type_text = shift;
  my $line            = shift;
  my $lpar_translated = shift;
  my $tint            = shift;
  my $cpulim_pct      = shift;
  my $cpulimmin_pct   = shift;
  my $cpu_warning     = shift;
  my $total_cpu       = shift;
  my $service_now     = shift;

  my $error       = "";
  my $url         = "https://$service_now->{'ip'}.service-now.com/api/global/em/jsonv2";
  my $description = "$ltime_str: $alert_type_text alert for: $last_type: $lpar server: $managed managed by: $host avg utilization during last $tint mins: $util ($alert_type_text MAX limit: $utillim actual: $util, $lpar_translated)";

  my $alert_service_now_history = "$basedir/logs/alert_history_service_now.log";
  open( SN, ">> $alert_service_now_history" ) || error( "could not open $alert_service_now_history: $! " . __FILE__ . ":" . __LINE__ ) && return 1;
  print SN "#######################################\n";
  print SN "print from ALRT\n";

  #FOR DEBUG
  if ( $ENV{SERVICE_NOW_DEBUG} ) {
    print SN "#### DEBUG ####\n";
    print SN "DATA FROM GUI\n\n";
    print SN " USER: $service_now->{'user'}\n PASSWORD: $service_now->{'password'}\n INSTANCE NAME: $service_now->{'ip'}\n EVENT: $service_now->{'event'}\n TYPE: $service_now->{'type'}\n SEVERITY: $service_now->{'severity'}\n";
    print SN "\nEND DATA FROM GUI\n\n";

    print SN "CURL FOR TESTING\n";
    print SN "curl -i -X POST -k -u \"$service_now->{'user'}:$service_now->{'password'}\" -H \"Content-Type: application/json\" -H \"Accept: application/json\" $url -d '{\"records\":[{\"source\":\"lpar2rrd\",\"event_class\":\"$service_now->{'event'}\",\"resource\":\"$lpar\",\"node\":\"$managed\",\"metric_name\":\"$alert_type_text\",\"type\":\"$service_now->{'type'}\",\"severity\":\"$service_now->{'severity'}\",\"description\":\"$description\"}]}'\n\n";

    print SN "#### END DEBUG ####\n";
  }

  if ( $service_now->{'user'} eq "" ) {
    print SN "SERVICE NOW USER must be set!\n";
    $error = "error";
  }
  if ( $service_now->{'password'} eq "" ) {
    print SN "SERVICE NOW PASSWORD must be set!\n";
    $error = "error";
  }
  if ( $service_now->{'ip'} eq "" ) {
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
    print SN "EVERSOURCE\n";
    %json_body = (
      "records" => [
        {
          "source"      => "lpar2rrd",
          "event_class" => "$service_now->{'event'}", #lpar2rrd CPU alert for POOL
          "resource"    => "$lpar", #shared1
          "node"        =>"$lpar", #shared1
          "metric_name" => "$alert_type_text", #CPU
          "type"        =>"$alert_type_text",
          "severity"    =>"$service_now->{'severity'}",
          "description" =>"$description" #Mon May 23 13:07:06 2022: CPU alert for: POOL: shared1 server: Power770 managed by: vhmc.int.xorux.com avg utilization during last 5 mins: 0.029 (CPU MAX limit: 0 actual util: 0.029, SharedPool1)
        }
      ]
    );
  }
  else{
    %json_body = (
      "records" => [
        {
          "source"      => "lpar2rrd",
          "event_class" => "$service_now->{'event'}", #lpar2rrd CPU alert for POOL
          "resource"    => "$lpar", #shared1
          "node"        =>"$managed", #Power770
          "metric_name" => "$alert_type_text", #CPU
          "type"        =>"$service_now->{'type'}",
          "severity"    =>"$service_now->{'severity'}",
          "description" =>"$description" #Mon May 23 13:07:06 2022: CPU alert for: POOL: shared1 server: Power770 managed by: vhmc.int.xorux.com avg utilization during last 5 mins: 0.029 (CPU MAX limit: 0 actual util: 0.029, SharedPool1)
        }
      ]
    );
  }

  my $body = encode_json( \%json_body );

  my $agent   = LWP::UserAgent->new( ssl_opts => { verify_hostname => 0, SSL_verify_mode => 0 } );
  my $request = HTTP::Request->new( POST => $url );

  $request->header( 'Content-Type' => 'application/json', 'Accept' => 'application/json' );
  $request->authorization_basic( $service_now->{'user'}, $service_now->{'password'} );
  $request->content($body);

  my $results = $agent->request($request);

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

  my $host            = shift;
  my $managed         = shift;
  my $lpar            = shift;
  my $util            = shift;
  my $utillim         = shift;
  my $utillimmin      = shift;
  my $ltime_str       = shift;
  my $last_type       = shift;
  my $alert_type_text = shift;
  my $line            = shift;
  my $lpar_translated = shift;
  my $tint            = shift;
  my $cpulim_pct      = shift;
  my $cpulimmin_pct   = shift;
  my $cpu_warning     = shift;
  my $total_cpu       = shift;
  my $jira_cloud      = shift;

  my $subject     = "$alert_type_text alert for: $last_type";
  my $description = "$ltime_str: $alert_type_text alert for: $last_type: $lpar server: $managed managed by: $host avg utilization during last $tint mins: $util ($alert_type_text MAX limit: $utillim actual: $util, $lpar_translated)";

  my $alert_jira_cloud_history = "$basedir/logs/alert_history_jira_cloud.log";
  open( JC, ">> $alert_jira_cloud_history" ) || error( "could not open $alert_jira_cloud_history: $! " . __FILE__ . ":" . __LINE__ ) && return 1;
  print JC "#######################################\n";
  print JC "PRINT from alrt\n";
  print JC "TIME : $ltime_str\n";
  print JC "\n";
  print JC "summary     : $subject\n";
  print JC "description : $description\n";
  print JC "project key : $jira_cloud->{project_key}\n";
  print JC "issue id    : $jira_cloud->{issue_id}\n";

  my %json_body = (
    "create" => {
      "worklog" => [
        {
          "add" => {
            "timeSpent" => "60m",
            "started" => "ltime_str"
          }
        }
      ]
    },
    "fields" => {
      "summary" => "$subject",
      "description" => "$description",
      "project" => { "key" => "$jira_cloud->{project_key}" },
      "issuetype" => { "id" => "$jira_cloud->{issue_id}" }
    }
  );

  my $body = encode_json( \%json_body );

  my $agent   = LWP::UserAgent->new( ssl_opts => { verify_hostname => 0, SSL_verify_mode => 0 } );
  my $request = HTTP::Request->new( POST => $jira_cloud->{url} );

  $request->header( 'Content-Type' => 'application/json', 'Accept' => 'application/json' );
  $request->authorization_basic( $jira_cloud->{user}, $jira_cloud->{token} );
  $request->content($body);

  my $results   = $agent->request($request);

  if ( !$results->is_success ) {
    my $st_line = $results->status_line;
    my $res_con = $results->content;
    print JC "Request error: $st_line\n";
    print JC "Request error: $res_con\n";}
  else {
    print JC "SUCCESS\n";
  }

  print JC "\n";
  print JC "END\n";
  print JC "#######################\n";
  close(JC);
  return(1);
}


sub opsgenie {
  use LWP::UserAgent;
  use HTTP::Request;

  my $host            = shift;
  my $managed         = shift;
  my $lpar            = shift;
  my $util            = shift;
  my $utillim         = shift;
  my $utillimmin      = shift;
  my $ltime_str       = shift;
  my $last_type       = shift;
  my $alert_type_text = shift;
  my $line            = shift;
  my $lpar_translated = shift;
  my $tint            = shift;
  my $cpulim_pct      = shift;
  my $cpulimmin_pct   = shift;
  my $cpu_warning     = shift;
  my $total_cpu       = shift;
  my $opsgenie        = shift;

  my $url = $opsgenie->{'url'};
  my $subject     = "$alert_type_text alert for: $last_type";
  my $description = "$ltime_str: $alert_type_text alert for: $last_type: $lpar server: $managed managed by: $host avg utilization during last $tint mins: $util ($alert_type_text MAX limit: $utillim actual: $util, $lpar_translated)";

  my $alert_opsgenie_history = "$basedir/logs/alert_history_opsgenie.log";
  open( OPS, ">> $alert_opsgenie_history" ) || error( "could not open $alert_opsgenie_history: $! " . __FILE__ . ":" . __LINE__ ) && return 1;
  print OPS "#######################################\n";
  print OPS "PRINT from alrt\n";
  print OPS "TIME : $ltime_str\n";
  print OPS "\n";
  print OPS "summary     : $subject\n";
  print OPS "description : $description\n";
  print OPS "project key : $opsgenie->{'key'}\n";
  print OPS "url         : $opsgenie->{'url'}\n";

  my %json_body = (
    "message" => "$subject",
    "description" => "$description",
  );

  my $body = encode_json( \%json_body );

  my $agent   = LWP::UserAgent->new( ssl_opts => { verify_hostname => 0, SSL_verify_mode => 0 } );
  my $request = HTTP::Request->new( POST => $url );

  $request->header( 'Content-Type' => 'application/json', 'Accept' => 'application/json', 'Authorization' => 'GenieKey '. $opsgenie->{'key'}. '' );
  $request->content($body);

  my $results   = $agent->request($request);

  if ( !$results->is_success ) {
    my $st_line = $results->status_line;
    my $res_con = $results->content;
    print OPS "Request error: $st_line\n";
    print OPS "Request error: $res_con\n";}
  else {
    print OPS "SUCCESS\n";
  }

  print OPS "\n";
  print OPS "END\n";
  print OPS "#######################\n";
  close(OPS);
  return(1);
}

