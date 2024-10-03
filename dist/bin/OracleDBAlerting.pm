package OracleDBAlerting;

use strict;
use warnings;

use RRDp;
use Xorux_lib;
use Data::Dumper;
use OracleDBDataWrapper;
use MIME::Base64 qw(encode_base64 decode_base64);

my %alerted_metrics = (
  'CLC'    => "Current Logons Count",
  'ARCHL'  => "Archive_mode",
  'TBSU_P' => "Tablespaces_used",
  'STATUS' => "Database_status",
);
my %alerted_metrics_r = (
  'Current Logons Count' => "CLC",
  'Archive_mode'         => "ARCHL",
  'Tablespaces_used'     => "TBSU_P",
  'Database_status'      => "STATUS",
);

my %metric_type = (
  'Current Logons Count' => "PERF",
  'Archive_mode'         => "CONF",
  'Tablespaces_used'     => "CONF",
  'Database_status'      => "CONF",
);

my %status_enum = (
  'Archive_mode' => {
    '0' => "NOARCHIVELOG",
    '1' => "ARCHIVELOG",
  },
  'Database_status' => {
    '0' => "DOWN",
    '1' => "UP",
  },
);

my $inputdir   = $ENV{INPUTDIR};
my $tmpdir     = "$inputdir/tmp";
my $odb_dir    = "$inputdir/data/OracleDB";
my $realcfgdir = "$inputdir/etc";
my $cfgdir     = "$inputdir/etc/web_config";
my $log        = "$inputdir/logs/alert_history.log";


my %alerts;       # hash holding alerting configuration
my %emailgrps;    # hash holding e-mail groups
my %config;       # hash holding configuration
my @rawcfg;
my %grp_checker;
my $oldcfg = 0;

sub check_config {
  my $alias    = shift;
  my $data_ref = shift;
  my $type     = shift;
  my $ip       = shift;
  my %data     = %{$data_ref};
  my %alertable_data;
  my @instances;
  my @values;
  my $alert_bool = 0;
  read_cfg();

  #print Dumper \%alerts;

  unless ( $alerts{OracleDB}{$alias} ) {
    return;
  }

  if ( $type eq "RAC" ) {
    for my $instance ( keys %{ $data{RAC} } ) {
      next if ( $instance eq "info" );
      for my $metric_short ( keys %{ $alerts{OracleDB}{$alias}{DB} } ) {
        next unless ( $metric_short eq "CLC" );
        my $metric = $alerted_metrics{$metric_short};
        next if ( !( defined $data{RAC}{$instance}{'Session info'}{$metric} ) );
        my $value = $data{RAC}{$instance}{'Session info'}{$metric};
        if ( $alerts{OracleDB}{$alias}{DB}{$metric_short}[0]{limit} ) {
          $alertable_data{$metric}{$instance}{metric_value} = $value;
        }
      }
    }
  }
  elsif ( $type eq "Standalone" ) {
    for my $metric_short ( keys %{ $alerts{OracleDB}{$alias}{DB} } ) {
      next unless ( $metric_short eq "CLC" );
      my $metric = $alerted_metrics{$metric_short};
      next if ( !( defined $data{'Session info'}{$metric} ) );
      my $value = $data{'Session info'}{$metric};
      if ( $alerts{OracleDB}{$alias}{DB}{$metric_short}[0]{limit} ) {
        $alertable_data{$metric}{$ip}{metric_value} = $value;
      }
    }
  }
  my $alertable_instances = can_alert( $alias, \%alertable_data, \%alerts );
  if ($alertable_instances) {
    alert( $alias, $alertable_instances, \%alerts );

    #warn "GOT HERE";

    for my $metric ( keys %{$alertable_instances} ) {
      for my $instance ( keys %{ $alertable_instances->{$metric} } ) {
        create_alert_file( $alias, $instance, "repeat", $alerted_metrics_r{$metric} );
      }
    }
  }

  #after alert I should reset all checkers
  #what state Iam I at when I alert?
  #resets: exclude > no checkers to reset,
  #        repeat  > remove the file and create a new one right away so the counter resets,
  #        peak    > remove the file/s
  #May want to create sub for reseting file? //probably isnt needed as it would be used only in repeat reset
  #reset_alert();
}

sub check_config_data {
  my $alias          = shift;
  my $alertable_data = shift;
  my $type           = shift;
  my @instances;
  my @values;
  my $alert_bool = 0;
  read_cfg();

  unless ( $alerts{OracleDB}{$alias} ) {
    return;
  }
  my $alertable_instances = can_alert( $alias, $alertable_data, \%alerts );
  if ($alertable_instances) {

    alert( $alias, $alertable_instances, \%alerts );

    #warn "GOT HERE";
    for my $metric ( keys %{$alertable_instances} ) {
      for my $instance ( keys %{ $alertable_instances->{$metric} } ) {
        if ( $alerted_metrics_r{$metric} eq "TBSU_P" ) {
          for my $t_space ( keys %{ $alertable_instances->{$metric}{$instance} } ) {
            create_alert_file( $alias, $instance, "repeat", $alerted_metrics_r{$metric} . "__" . $t_space );
          }
        }
        else {
          create_alert_file( $alias, $instance, "repeat", $alerted_metrics_r{$metric} );
        }
      }
    }
  }

  #after alert I should reset all checkers
  #what state Iam I at when I alert?
  #resets: exclude > no checkers to reset,
  #        repeat  > remove the file and create a new one right away so the counter resets,
  #        peak    > remove the file/s
  #May want to create sub for reseting file? //probably isnt needed as it would be used only in repeat reset
  #reset_alert();
}

sub can_alert {
  my $alias          = shift;
  my $alert_data_ref = shift;
  my $alerts_ref     = shift;
  my %alerts         = %{$alerts_ref};
  my %alert_data     = %{$alert_data_ref};
  my %alertable_instances;
  my $def_repeat = defined $config{REPEAT_DEFAULT}    ? $config{REPEAT_DEFAULT}    : 10;
  my $def_peak   = defined $config{PEAK_TIME_DEFAULT} ? $config{PEAK_TIME_DEFAULT} : 10;

  #warn Dumper \%alerts;
  for my $metric ( keys %{ $alerts{OracleDB}{$alias}{DB} } ) {
    my @sp = split( /\_\_/, $metric );

    #warn Dumper \@sp;
    next if ( !defined $alerted_metrics{ $sp[0] } );

    my $metric_f  = $alerted_metrics{ $sp[0] };
    my $submetric = $sp[$#sp];
    my $exclude   = $alerts{OracleDB}{$alias}{DB}{$metric}[0]{exclude} ? $alerts{OracleDB}{$alias}{DB}{$metric}[0]{exclude} : "empty";
    my $repeat    = $alerts{OracleDB}{$alias}{DB}{$metric}[0]{repeat}  ? $alerts{OracleDB}{$alias}{DB}{$metric}[0]{repeat}  : $def_repeat;
    my $peak      = $alerts{OracleDB}{$alias}{DB}{$metric}[0]{peak}    ? $alerts{OracleDB}{$alias}{DB}{$metric}[0]{peak}    : $def_peak;
    my $limit     = $alerts{OracleDB}{$alias}{DB}{$metric}[0]{limit};

    #exclude > repeat > peak
    if ( check_exclude($exclude) ) {
      for my $instance ( keys %{ $alert_data{$metric_f} } ) {
        if ( defined $metric_type{$metric_f} and $metric_type{$metric_f} eq "PERF" ) {
          if (check_peak( $alias, $alert_data{$metric_f}{$instance}{metric_value}, $instance, $peak, $limit, $metric ) and check_repeat( $alias, $repeat, $instance, $metric ) ) {
            $alertable_instances{$metric_f}{$instance}{metric_value} = $alert_data{$metric_f}{$instance}{metric_value};
          }
        }
        elsif ( defined $metric_type{$metric_f} and $metric_type{$metric_f} eq "CONF" ) {
          my $current_val = $alert_data{$metric_f}{$instance}{metric_value};
          if ( $metric eq "STATUS" or $metric eq "ARCHL" ) {
            if (( $current_val == $limit ) and check_repeat( $alias, $repeat, $instance, $metric ) ) {
              $alertable_instances{$metric_f}{$instance}{metric_value} = $alert_data{$metric_f}{$instance}{metric_value};
            }
          }
          else {
            my $current_val = $alert_data{$metric_f}{$instance}{$submetric}{metric_value};
            if (( $current_val >= $limit ) and check_repeat( $alias, $repeat, $instance, $metric ) ) {
              $alertable_instances{$metric_f}{$instance}{$submetric}{metric_value} = $alert_data{$metric_f}{$instance}{$submetric}{metric_value};
            }
          }
        }
      }
    }
    else {
      next;
    }
  }

  #print Dumper \%alertable_instances;
  if (%alertable_instances) {
    return \%alertable_instances;
  }
  else {
    return 0;
  }
}

sub alert {
  my $alias          = shift;
  my $alert_data_ref = shift;
  my $alerts_ref     = shift;
  my %alerts         = %{$alerts_ref};
  my %alert_data     = %{$alert_data_ref};
  my $lpar_name      = "$alias";
  my $last_type      = "filler";
  my $server_name    = "filler";
  my $unit           = "";
  my $ltime_string   = localtime(time);
  my $graph_base     = "$tmpdir";
  my @graph_paths;

  #warn "ALERTS\n";
  #warn Dumper \%alerts;
  #warn "ALERT DATA\n";
  #warn Dumper \%alert_data;
  #  print Dumper \@emails;
  
  for my $metric ( keys %alert_data ) {

    #warn $metric;
    #my $util = "";
    #my $alert_type_text = "$metric";
    my $metric_short = $alerted_metrics_r{$metric};

    my $mess_metric = $metric;
    $mess_metric =~ s/_/ /g;
    my $subject      = "LPAR2RRD: $mess_metric alert for OracleDB: $alias";
    my $message_text = "$ltime_string: $mess_metric alert for:\n OracleDB: $alias";
    my $graph_bool   = 0;
    for my $instance ( keys %{ $alert_data{$metric} } ) {

      if ( $metric_type{$metric} eq "PERF" ) {
        $graph_bool = 1;
        my $graph_path = "$graph_base/alert-$instance-$alias-$metric_short.png";
        create_graph( $instance, $alias, '$lpar_translated', $graph_path, $inputdir, "$inputdir/bin", '$line', 1 );
        push( @graph_paths, $graph_path );
      }
      my $value;
      if ( $metric eq "Archive_mode" or $metric eq "Database_status" ) {
        $value = $status_enum{$metric}{ $alert_data{$metric}{$instance}{metric_value} };
      }
      elsif ( $metric eq "Tablespaces_used" ) {
        for my $tblspace ( keys %{ $alert_data{$metric}{$instance} } ) {
          $value = "$alert_data{$metric}{$instance}{$tblspace}{metric_value} %";
          my $tbs_mess   = " \n Instance: $instance\n Tablespace: $tblspace Value: $value";
          my $emails_tbs = getGroupMembers( $alerts{OracleDB}{$alias}{DB}{ $metric_short . "__" . $tblspace }[0]{mailgrp} );
          #warn "EMAILS TB TBS\n";
          #warn Dumper $emails_tbs;
          if ( defined $emails_tbs and $emails_tbs->[0] ) {
            my $time = gmtime(time);
            system(qq(echo "$time; $metric; Instance; OracleDB; $instance; $tbs_mess\n" >> $log));
            sendmail( $emails_tbs, $subject, $tbs_mess, $lpar_name, "util", $last_type, "alert_type_text", $server_name, \@graph_paths, $graph_bool, $unit );
          }
        }
      }
      else {
        $value = $alert_data{$metric}{$instance}{metric_value};
      }
      $message_text .= " \n Instance: $instance \n Metric: $metric Value: $value";
    }
    my $emails = getGroupMembers( $alerts{OracleDB}{$alias}{DB}{$metric_short}[0]{mailgrp} );
    next if ( $metric eq "Tablespaces_used" );
    #warn "EMAILS\n";
    #warn Dumper $emails;
    if ( defined $emails and $emails->[0] ) {
      my $time = gmtime(time);
      system(qq(echo "$time; $metric; Instance; OracleDB; $alias; $message_text\n" >> $log));
      sendmail( $emails, $subject, $message_text, $lpar_name, "util", $last_type, "alert_type_text", $server_name, \@graph_paths, $graph_bool, $unit );
    }
    if ( $config{TRAP} and $config{TRAP} ne "" ) {
      snmp_trap_alarm( $config{TRAP}, $alias, "$metric", \%alert_data );
    }
    foreach my $graph (@graph_paths) {
      unlink($graph);
    }
  }
}

sub sendmail {
  my $mailto          = shift;
  my $subject         = shift;
  my $text            = shift;
  my $lpar            = shift;
  my $util            = shift;
  my $last_type       = shift;
  my $alert_type_text = shift;
  my $managed         = shift;
  my $graph_paths_ref = shift;
  my $email_graph     = shift;
  my $unit            = shift;
  my $FS_checker      = shift;
  my $message_body;
  my @att_files;
  my @att_names;

  my $mailfrom = "";

  #if ( defined $FS_checker ) {
  #  $subject  = "LPAR2RRD: $alert_type_text alert for $managed $last_type: $lpar, usage is: $util $unit";
  #}
  #else {
  #  $subject  = "LPAR2RRD: $alert_type_text alert for $managed $last_type: $lpar, utilization is: $util $unit";
  #}

  $lpar =~ s/\&\&1/\//g;

  #if ( $alert_type_text =~ m/Swapping/ ) {
  # for swapping
  #$subject = "LPAR2RRD: $alert_type_text alert for $managed $last_type: $lpar : $util";
  #}

  #print "Alert emailing : $alert_type_text $last_type: $subject $mailto\n";

  #my @email_list = @{$mailto};
  #print Dumper \@{$mailto};

  $message_body .= "$text\n";
  if ( exists $config{'WEB_UI_URL'} && $config{'WEB_UI_URL'} ne '' ) {
    $message_body .= "\n\nCheck it out in the LPAR2RRD UI: $config{'WEB_UI_URL'}\n";
  }
  $message_body .= "\n\n";

  if ( isdigit($email_graph) && $email_graph > 0 ) {
    my @graph_paths = @{$graph_paths_ref};

    foreach my $graph_path (@graph_paths) {
      my $graph_name = OracleDBDataWrapper::basename( $graph_path, "/" );
      push @att_files, $graph_path;
      push @att_names, "$lpar:$graph_name";
    }
  }

  foreach my $email ( @{$mailto} ) {
    chomp $email;
    print "Alert emailing : $alert_type_text $last_type: $subject $mailto\n";
    #warn "CURRENT EMAIL";
    #warn "$email\n";i

    Xorux_lib::send_email( $email, $mailfrom, $subject, $message_body, \@att_files, \@att_names );
  }
  foreach my $f_path (@att_files) {
    if ( -f $f_path ) {
      unlink($f_path);
    }
  }
  return 0;
}

sub check_exclude {
  my $exclude_time = shift;
  my ( $sec, $min, $hour ) = ( gmtime(time) );

  if ( !$exclude_time or $exclude_time eq 'empty' ) {
    return 1;
  }

  my @split_exc = split( /-/, $exclude_time );

  if ( $split_exc[0] < $hour and $hour < $split_exc[1] ) {
    return 0;
  }
  else {
    return 1;
  }
}

sub check_repeat {
  my $alias        = shift;
  my $repeat       = shift;
  my $instance     = shift;
  my $metric_short = shift;

  my $file = "$odb_dir/$alias/Alerts/repeat-alert-$instance-$metric_short.txt";
  if ( -f $file ) {
    my $modtime   = ( stat($file) )[9];
    my $time_diff = time - $modtime;
    $repeat = $repeat * 60;
    if (($time_diff >= $repeat - 120) ) {
      unlink($file);
      return 1;
    }
    else {
      return 0;
    }
  }
  else {
    return 1;
  }
}

sub create_alert_file {
  my $alias    = shift;
  my $instance = shift;
  my $type     = shift;
  my $metric   = shift;
  my $file     = "$odb_dir/$alias/Alerts/$type-alert-$instance-$metric.txt";

  open my $fh, '>', $file;
  print $fh "1\n";
  close $fh;

}

sub check_peak {
  my $alias            = shift;
  my $metric_value     = shift;
  my $instance         = shift;
  my $peak             = shift;
  my $limit            = shift;
  my $metric_short     = shift;
  my $metric           = $alerted_metrics{$metric_short};
  my $instance_checker = 0;
##There could be a problem with one value hittig 15/15 minutes and the other being 10/15 and if I remove both file checkers  when alerting
##on the first one the second peak could get lost, but if I dont there may be mail spam and I alredy went the long route to get rid of it
  #warn "metric_value, limit, peak: $metric_value $limit $peak ";
  my $file = "$odb_dir/$alias/Alerts/peak-alert-$instance-$metric_short.txt";
  if ( -f $file ) {
    if ( $metric_value > $limit ) {
      my $modtime   = ( stat($file) )[9];
      my $time_diff = time - $modtime;
      $peak = $peak * 60;
      if ( $time_diff >= $peak - 120 ) {
        $instance_checker = 1;
      }
      else {
        $instance_checker = 0;
      }
    }
    else {
      unlink($file);
      $instance_checker = 0;
    }
  }
  else {
    if ( $metric_value >= $limit ) {
      open my $fh, '>', $file;
      print $fh "1\n";
      close $fh;
      $instance_checker = 0;
    }
    else {
      $instance_checker = 0;
    }
  }

  if ($instance_checker) {
    return 1;
  }
  else {
    return 0;
  }
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
  my $perl        = $ENV{PERL};

  my $lpar_url = $lpar;
  $lpar_url =~ s/\//&&1/g;
  my $server_url = $server;
  $lpar_url   =~ s/([^a-zA-Z0-9_.!~*()'\''-])/sprintf("%%%02X", ord($1))/ge;
  $server_url =~ s/([^a-zA-Z0-9_.!~*()'\''-])/sprintf("%%%02X", ord($1))/ge;

  print "Graph creation : $host:$server:$lpar\n";

  #  $ENV{'QUERY_STRING'} = "host=$host&server=$server_url&lpar=$lpar_url&item=shpool&time=d&type_sam=m&detail=0&none=none&none1=none";
  $ENV{'QUERY_STRING'} = "host=$host&server=$server&lpar=aggr_Session_info&item=oracledb_aggr_Session_info__Current_Logons_Count_a_FF0000&time=d&type_sam=d&detail=1";

  #print "calling grapher: $perl $bindir/detail-graph-cgi.pl alarm $graph_path 1 > $log\n";
  print "QUERY_STRING   : $ENV{'QUERY_STRING'}\n";

  #print "$perl $bindir/detail-graph-cgi.pl alarm $graph_path $email_graph";
  `$perl $bindir/detail-graph-cgi.pl alarm $graph_path $email_graph`;

  #  # only LOG, not the picture
  #  if ( -f $log ) {
  #    open( FH, "< $log" );
  #    foreach my $line (<FH>) {
  #      print "$line";
  #    }
  #    close(FH);
  #    unlink($log);
  #  } ## end if ( -f $log )

  return 1;
}

sub snmp_trap_alarm {
  my $trap_host       = shift;
  my $managed         = shift;
  my $metric          = shift;
  my $alert_data_ref  = shift;
  my $util            = shift;
  my $utillim         = shift;
  my $ltime_str       = shift;
  my $last_type       = shift;
  my $alert_type_text = shift;

  my %alert_data       = %{$alert_data_ref};
  my $SNMP_PEN         = "40540";
  my $PRE              = "1.3.6.1.4.1.40540";
  my $community_string = "public";

  #  if ( exists $inventory_alert{GLOBAL}{'COMM_STRING'} && $inventory_alert{GLOBAL}{'COMM_STRING'} ne '' ) {
  #    $community_string = $inventory_alert{GLOBAL}{'COMM_STRING'};
  #  }
  #
  #  if ( defined $ENV{LPAR2RRD_SNMPTRAP_COMUNITY} ) {
  #    $community_string = $ENV{LPAR2RRD_SNMPTRAP_COMUNITY}
  #  }

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
  my $trap_text = "";
  for my $instance ( keys %{ $alert_data{$metric} } ) {
    my $value = $alert_data{$metric}{$instance}{metric_value};
    $trap_text .= "$PRE.1.9 s '$instance' $PRE.1.11 s '$value'";
  }

  my $out = `$snmp_exe -v 1 -c '$community_string' '$trap_host' $PRE.1.0.1.0.7 '' 6 7 '' $PRE.1.8 s '$managed' $trap_text 2>&1;`;

  print $out;
  if ( $out =~ m/not found/ ) {
    error("SNMP Trap: $snmp_exe binnary has not been found, install net-snmp as per https://www.lpar2rrd.com/alerting_trap.php ($out)");
  }
  if ( $out =~ m/Usage: snmptrap/ ) {
    error("SNMP Trap: looks like you use native AIX /usr/sbin/snmptrap, it is not supported, check here: https://www.lpar2rrd.com/alerting_trap.php");
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

  my $basedir    = "TBD";
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

  # NOT a number
  return 0;
}

sub read_cfg {
  my $cfgfile = "$cfgdir/alerting.cfg";
  if ( !open( CFG, $cfgfile ) ) {
    if ( !open( CFG, "$realcfgdir/alert.cfg" ) ) {
      if ( !open( CFG, ">", $cfgfile ) ) {
        warn "Cannot open file: $!\n" && exit 1;
      }
    }
    $oldcfg = 1;
  }

  while ( my $line = <CFG> ) {
    chomp($line);
    if ( $line =~ /^WEB_UI_URL/ ) {
      my @val = split( /=/, $line, 2 );
      chomp @val;
      $config{ $val[0] } = $val[1];
      next;
    }
    $line =~ s/ *$//g;    # delete spaces at the end
    if ( $line =~ m/^$/
      || $line =~ m/^#/ )
    {
      next;
    }
    if ( $line =~ m/:/ ) {
      my @val = split( /:/, $line );

      for (@val) {
        doublecoma($_);
      }

      push @rawcfg, $line;

      # LPAR|POOL]:server:[lpar name|pool name]:metric:limit:peak time in min:alert repeat time in min:exclude time:email group
      my ( $type, $server, $name, $item, $limit, $peak, $repeat, $exclude, $mailgrp, $uuid, $cluster );

      if ($oldcfg) {
        ( $type, $server, $name, $limit, undef, $peak, $repeat, $mailgrp ) = @val;
        if ( $type eq "SWAP" ) {
          ( $type, $server, $name, $limit, $peak, $repeat, $mailgrp ) = @val;
        }
        $item    = "CPU";
        $exclude = "";
      }
      else {
        ( $type, $server, $name, $item, $limit, $peak, $repeat, $exclude, $mailgrp, $uuid, $cluster ) = @val;
      }
      if ( $mailgrp && $mailgrp =~ "@" ) {
        push @{ $emailgrps{Default} }, $mailgrp;
        $mailgrp = "Default";
      }
      $mailgrp ||= "";
      $server  ||= "";

      if ( $type eq "EMAIL" ) {
        my @mails;
        if ($name) {
          @mails = ( split /,/, $name );
          chomp(@mails);
          s{^\s+|\s+$}{}g foreach @mails;
          if(! defined $grp_checker{$server}){
            $grp_checker{$server} = 1;
            push @{ $emailgrps{$server} }, @mails;
          }
        }
      }
      elsif ( $type eq "OracleDB" ) {
        my $rule = { limit => $limit, peak => $peak, repeat => $repeat, exclude => $exclude, mailgrp => $mailgrp };
        $alerts{$type}{$server}{$name}{$item} = [$rule];
      }
    }
    elsif ( $line =~ m/=/ ) {
      my @val = split( /=/, $line, 2 );
      if ( $val[0] eq "PEEK_TIME_DEFAULT" ) {
        $val[0] = "PEAK_TIME_DEFAULT";
      }
      if ( $val[0] =~ "EMAIL_" ) {
        if ( $val[0] ne "EMAIL_ADMIN" && $val[0] ne "EMAIL_GRAPH" ) {
          my $mgrp  = ( split "EMAIL_", $val[0] )[1];
          my @mails = ( split /,/,      $val[1] );
          chomp(@mails);
          s{^\s+|\s+$}{}g foreach @mails;
          if(! defined $grp_checker{$mgrp}){
            $grp_checker{$mgrp} = 1;
            push @{ $emailgrps{$mgrp} }, @mails;
          }
        }
        else {
          $config{ $val[0] } = ( split /\s+/, $val[1] )[0];
        }
      }
      else {
        $config{ $val[0] } = ( split /\s+/, $val[1] )[0];
      }
    }
  }
  close CFG;
  if ( $ENV{GATEWAY_INTERFACE} && !-o $cfgfile ) {
    warn "Can't write to the file $cfgfile, copying to my own!";
    copy( $cfgfile, "$cfgfile.bak" );
    unlink $cfgfile;
    move( "$cfgfile.bak", $cfgfile );
    chmod 0664, $cfgfile;
  }

  # print Dumper \%emailgrps;
}

sub getGroupMembers {

  # param: group_name
  # return sorted array of defined alerts
  my $groupName = shift;

  #warn "EMAIL GROUPS";
  #warn Dumper \$groupName;
  #warn Dumper \%emailgrps;
  return $emailgrps{$groupName};
}

sub doublecoma {
  return s/===========doublecoma=========/:/g;
}

1;
