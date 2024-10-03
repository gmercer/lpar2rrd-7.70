
use strict;
use warnings;

# use Data::Dumper;

my $inputdir  = $ENV{INPUTDIR} ||= "";
my $cfgdir    = "$inputdir/etc/web_config";
my $perl      = $ENV{PERL};
my $vmwlibdir = "$inputdir/vmware-lib/apps";
my $credstore = "$inputdir/.vmware/credstore/vicredentials.xml";
my %cfg;

# get URL parameters (could be GET or POST) and put them into hash %PAR
my ( $buffer, @pairs, $pair, $name, $value, %PAR );

if ( defined $ENV{'CONTENT_TYPE'} && $ENV{'CONTENT_TYPE'} =~ "multipart/form-data" ) {
  print "Content-type: application/json\n\n";
  require CGI;
  my $cgi = new CGI;

  # print Dumper $cgi;
  my $file = $cgi->param('sdk');

  if ($file) {

    # if (length($file) <= 50000000) {
    if (0) {
      &result( 0, "File is too small, it cannot be VMware SDK for Perl." );
    }
    else {
      my $tmpfilename = $cgi->tmpFileName($file);
      rename $tmpfilename, "/tmp/$file";
      chmod 0664, "/tmp/$file";
      my $txt = "<pre>" . `$inputdir/bin/vmware_install_image.sh /tmp` . "</pre>";
      if ( $? == 0 ) {
        &result( 1, "SDK succesfully installed, now you can continue with configuration", "$txt" );
      }
      else {
        &result( 0, "SDK install failed", "$txt" );
      }
    }
  }
  else {
    &result( 0, "No file uploaded" );
  }
  exit;
}

if ( !defined $ENV{'REQUEST_METHOD'} ) {
  print "Content-type: text/plain\n\n";
  print "No command specified, exiting...";
  exit;
}

if ( lc $ENV{'REQUEST_METHOD'} eq "post" ) {
  read( STDIN, $buffer, $ENV{'CONTENT_LENGTH'} );
}
else {
  $buffer = $ENV{'QUERY_STRING'};
}

# Split information into name/value pairs
@pairs = split( /&/, $buffer );
foreach $pair (@pairs) {
  ( $name, $value ) = split( /=/, $pair );
  $value =~ tr/+/ /;
  $value =~ s/%(..)/pack("C", hex($1))/eg;
  $PAR{$name} = $value;
}

# print $call , "\n";

# print Dumper \%PAR;

if ( $PAR{cmd} eq "getlist" ) {    ### Get list of credentials
  print "Content-type: text/html\n\n";
  if ( !-e "$vmwlibdir/credstore_admin.pl" ) {
    print "<p><b>VMware Perl SDK</b> libraries and apps are not installed yet. We are not authorized to redistribute the <b>VMWare Perl SDK</b> due to licensing restrictions.<p>";
    if ( $ENV{VM_IMAGE} ) {
      print <<_MARKER_;
    <p>Please download <a href='https://my.vmware.com/web/vmware/details?downloadGroup=SDKPERL600&productId=490' target="blank"><b>vSphere SDK for Perl 6.0</b></a> from VMware site to your computer and then upload it to the running appliance via following form:<br>
    It requires free registration at VMware.<br>
    Does not matter if 32bit or 64bit package<br>
    VMware-vSphere-Perl-SDK-6.0.0-&lt;version&gt;.tar.gz, download one of *tar.gz</p>
    <form id="sdk-install" action="/lpar2rrd-cgi/vmwcfg.sh" method="post" enctype="multipart/form-data">
    <p>File to Upload: <input type="file" accept=".tar.gz" name="sdk"></p>
    <p><input type="submit" id="sdk-upload" name="Submit" value="Upload SDK file" /></p>
		<div class="progress">
			<div class="bar"></div >
			<div class="percent">0%</div >
		</div>
    </form>
	<div id="status"></div>
_MARKER_
    }
    else {
      print "<p>Try <a href=\"https://www.lpar2rrd.com/VMware-performance-monitoring-installation.php#VMWARE\"><b>manual installation</b></a> instead.</p>";
    }
    exit;
  }
  if ( !-f $credstore ) {
    if ( !-w "$inputdir/.vmware/credstore" ) {
      print "<p>Apache user has no write permissions to this directory:</p>";
      print "<pre style='color: red'>$inputdir/.vmware/credstore</pre>";
      print "<p>Please check file permissions on that directory.</p>";
      exit;
    }
    else {
      if ( open( NEWCRED, ">$credstore" ) ) {
        print NEWCRED <<_BLANK_;
<?xml version="1.0" encoding="UTF-8"?>
<viCredentials>
  <version>1.1</version>
</viCredentials>
_BLANK_
        close NEWCRED;
        chmod 0666, $credstore;
      }
      else {
        print "<p>Apache cannot write to this file:</p>";
        print "<pre style='color: red'>$credstore</pre>";
        print "<p>Please check file permissions.</p>";
        exit;
      }
    }
  }

  my $call  = "$perl $vmwlibdir/credstore_admin.pl --credstore '$credstore' list 2>&1 | cat";
  my @creds = `$call`;

  # print Dumper \@creds;
  if ( @creds && grep /^Server *User Name/, @creds ) {
    chomp @creds;
    print <<_MARKER_;

<style>
    #cred-dialog-form label, #cred-dialog-form input { display:block; }
    #cred-dialog-form input.text { margin-bottom:12px; width:95%; padding: .4em; }
    #cred-dialog-form fieldset { padding:0; border:0; margin-top:25px; }
    div#creds-contain { width: 800px; margin: 10px 0; }
    div#creds-contain table { margin: 1em 0; border-collapse: collapse; }
    div#creds-contain table td, div#creds-contain table th { border: 1px solid #ddd; padding: .3em 6px; text-align: left; }
    #cred-dialog-form .ui-dialog .ui-state-error { padding: .3em; }
    .validateTips { border: 1px solid transparent; padding: 0.1em; }
</style>
<div id="creds-contain" class="ui-widget">
  <h3>VMware credentials</h3>
  <p><i>Only VMware systems with non-empty alias will be included for monitoring.</i></p>
  <table id="credentials" class="ui-widget ui-widget-content">
    <thead>
      <tr class="ui-widget-header ">
        <th>Alias</th>
        <th>Hostname/IP</th>
        <th>User name</th>
        <th>Connection</th>
        <th></th>
      </tr>
    </thead>
    <tbody>
_MARKER_

    &readCfg;

    # print Dumper \%cfg;
    for my $line ( @creds[ 1 .. $#creds ] ) {
      if ( !$line ) {
        last;
      }
      if ( $line =~ /^Server *User Name/ ) {
        next;
      }
      $line =~ s/^\s+|\s+$//g;
      my @pair   = split " ", $line, 2;
      my $talias = "";
      if ( exists $cfg{ $pair[0] }{ $pair[1] } ) {
        $talias = $cfg{ $pair[0] }{ $pair[1] };
      }
      print <<_ROW_;
        <tr>
          <td>$talias</td>
          <td class="vmserver">$pair[0]</td>
          <td class="vmuser">$pair[1]</td>
          <td style="text-align: center"><button class="testvmconn">Test</button></td>
          <!--td><button class="editvmconn">Edit</button></td-->
          <td><button class="remvmconn">Remove</button></td>
        </tr>
_ROW_
    }
    print <<_MARKER_;
    </tbody>
  </table>
</div>
<button id="create-new-cred">Create new credentials</button>&nbsp;&nbsp;
<br>
<br>
_MARKER_

    if ( $ENV{VM_IMAGE} ) {
      print '<p>Once you have some connection defined and tested, <button id="run-data-load">run data load</button>.</p>';
    }
    else {
      print "<p>Once you have some connection defined and tested, run as lpar2rrd user:<br><pre>cd $inputdir\n./load.sh</pre></p>";
    }

  }
  else {
    print '<p>Something went wrong, cannot get credentials list! Command output follows:</p>';
    print "<pre style='color: red'>@creds</pre>";
  }

  print <<_MARKER_;
<p>In case of problems, <button id="collect-logs">collect system logs</button> and send us that file via our <a href="https://upload.lpar2rrd.com">secured upload service</a>.</p>
<p>Error and runtime logs:
<ul>
<li><b><a href="?menu=b2d37ae&tab=0">Run time</a></b>: output from run script load.sh</li>
<li><b><a href="?menu=b2d37ae&tab=1">Error</a></b>: run time errors </li>
_MARKER_
  if ( $ENV{VM_IMAGE} ) {
    print '<li><b><a href="?menu=b2d37ae&tab=3">Apache error</a></b>: web server error log</li>';
  }
  print "</ul></p>";

}
elsif ( $PAR{cmd} eq "test" ) {    ### test selected connection
  print "Content-type: application/json\n\n";
  my $username = $PAR{username};
  my $server   = $PAR{server};
  if ( $server && $username ) {

    # my $call = "PER5LIB=$perl5lib; $perl $vmwlibdir/connect.pl --credstore $credstore --server $server --username $username --verbose";
    my $call     = "$perl $vmwlibdir/connect.pl --credstore '$credstore' --server '$server' --username '$username' 2>&1";
    my $call_err = ". $inputdir/etc/lpar2rrd.cfg; \$PERL $vmwlibdir/connect.pl --credstore '$credstore' --server '$server' --username '$username' ";
    eval {
      local $SIG{ALRM} = sub { die "died in SIG ALRM" };
      alarm 15;                    # schedule alarm in 15 seconds

      # print $call . "\n";
      my $conn = `$call`;
      if ( $? == -1 ) {
        &result( 0, "command failed: $!\n$conn" );
      }
      elsif ( $? == 0 ) {
        chomp $conn;
        if ( $conn =~ "Successful" ) {
          require VMware::VIRuntime;

          # easy test if at least one VM and one HostSystem presented
          $ENV{VI_SERVER}    = "$server";
          $ENV{VI_CREDSTORE} = "$credstore";
          Opts::parse();
          Opts::validate();
          Util::connect();

          my $obj_views = Vim::find_entity_views( view_type => 'VirtualMachine', properties => ['name'] );
          if ( !defined $obj_views || $obj_views eq "" || !defined @$obj_views[0] ) {
            $conn = "not presented any VirtualMachine - is there Read-only permission for all Vmware folders?";
          }
          $obj_views = Vim::find_entity_views( view_type => 'HostSystem', properties => ['name'] );
          if ( !defined $obj_views || $obj_views eq "" || !defined @$obj_views[0] ) {
            $conn = "not presented any HostSystem - is there Read-only permission for all Vmware folders?";
          }
          Util::disconnect();
          if ( $conn =~ "not presented" ) {
            &result( 0, "$conn" );
          }
          else {
            &result( 1, "$conn" );
          }
        }
        else {
          &result( 0, "connection failed: $conn" );
        }
      }
      else {
        if ( $conn =~ "Server version unavailable" ) {
          &result( 0, "Looks like there is no running vCenter or ESXi on: https://$server" );
        }
        else {
          my $arg = sprintf( "command exited with value %d", $? >> 8 );
          &result( 0, "$arg\n$conn" );
        }
      }

      alarm 0;    # cancel the alarm
    };
    if ( $@ && $@ =~ /died in SIG ALRM/ ) {
      &result( 0, "Command timed out after 15 seconds.\nCheck why it takes so long, might be some network or firewall problem.\n\n$call_err" );
    }

  }
  else {
    &result( 0, "You have to specify server and username!" );
  }

}
elsif ( $PAR{cmd} eq "remove" ) {    ### remove selected connection
  print "Content-type: application/json\n\n";
  if ( defined $ENV{DEMO} ) {
    &result( 0, "You cannot remove credentials in live demo" );
    exit;
  }
  my $alias    = $PAR{alias};
  my $username = $PAR{username};
  my $server   = $PAR{server};
  if ($alias) {                      # remove just an alias
    &readCfg;
    foreach my $srv ( keys %cfg ) {
      foreach my $usr ( keys %{ $cfg{$srv} } ) {
        if ( $cfg{$srv}{$usr} eq $alias ) {
          $cfg{$srv}{$usr} = "";
        }
      }
    }
    if (&credsToCfg) {
      &result( 1, "alias removed" );
    }
    else {
      &result( 0, "File $cfgdir/vmware.cfg cannot be written by webserver, check webserver user permissions: <span style='color: red'>$!</span>" );
    }
  }
  else {
    if ( $server && $username ) {    # alias is empty, remove credentials too
                                     # my $call = "PER5LIB=$perl5lib; $perl $vmwlibdir/connect.pl --credstore $credstore --server $server --username $username --verbose";
      my $call = "$perl $vmwlibdir/credstore_admin.pl --credstore '$credstore' remove --server '$server' --username '$username' 2>&1";

      # print $call . "\n";
      my $conn = `$call`;
      if ( $? == -1 ) {
        &result( 0, "command failed: $!" );
      }
      elsif ( $? == 0 ) {
        chomp $conn;
        if ( $conn =~ "successfully" ) {
          &readCfg;
          if (&credsToCfg) {
            &result( 1, "$conn" );
          }
          else {
            &result( 0, "File $cfgdir/vmware.cfg cannot be written by webserver, check webserver user permissions: <span style='color: red'>$!</span>" );
          }
        }
        else {
          &result( 0, "$conn" );
        }
      }
      else {
        my $arg = sprintf( "command exited with value %d", $? >> 8 );
        &result( 0, "$arg\n$conn" );
      }
    }
    else {
      &result( 0, "You have to specify server and username!" );
    }
  }

}
elsif ( $PAR{cmd} eq "add" ) {    ### add new connection
  print "Content-type: application/json\n\n";
  my $alias    = $PAR{alias};
  my $username = $PAR{username};
  my $server   = $PAR{server};
  my $password = $PAR{password};
  if ( $alias && $server && $username && $password ) {
    $ENV{VMPASS} = $password;
    my $call = "$perl $vmwlibdir/credstore_admin.pl --credstore '$credstore' add --server '$server' --username '$username' --password \$VMPASS 2>&1";
    my $conn = `$call`;
    $ENV{VMPASS} = "";
    if ( $? == -1 ) {
      &result( 0, "command failed: $!" );
    }
    elsif ( $? == 0 ) {
      chomp $conn;
      if ( $conn =~ "successfully" ) {
        &readCfg;
        $cfg{$server}{$username} = $alias;
        if (&credsToCfg) {
          &result( 1, "$conn" );
        }
        else {
          &result( 0, "File $cfgdir/vmware.cfg cannot be written by webserver, check webserver user permissions: <span style='color: red'>$!</span>" );
        }
      }
      else {
        &result( 0, "$conn" );
      }
    }
    else {
      my $arg = sprintf( "command exited with value %d", $? >> 8 );
      &result( 0, "$arg $conn" );
    }
  }
  else {
    &result( 0, "You have to specify alias, server, username and password!" );
  }
}
elsif ( $PAR{cmd} eq "load" ) {    ### run load.sh and show what to do next
  print "Content-type: application/json\n\n";
  if ( system("nohup $inputdir/load.sh > $inputdir/logs/load.out 2>&1 &") == -1 ) {
    &result( 0, "Couldn't exec load.sh ($!)." );
  }
  else {
    my $txt = "Data load has been launched!\n It could take very long (up to 30 minutes) depending on your infrastructure size.\n" . "Try to refresh this page (F5) from time to time to see if it's already done.";
    &result( 1, $txt );
  }

}
elsif ( $PAR{cmd} eq "logs" ) {    ### collect logs and send them to browser for saving
  my $call = `cd $inputdir; tar czhf logs.tar.gz logs etc tmp`;
  if ( $? == -1 ) {
    print "Content-type: application/json\n\n";
    &result( 0, "command failed: $!" );
  }
  else {
    my $filename = "$inputdir/logs.tar.gz";
    my $length   = length($filename);
    my $buffsize = 64 * ( 2**10 );
    print "Content-type: application/x-gzip\n";
    print "Cache-Control: no-cache \n";
    print "Content-Length: $length \n";
    print "Content-Disposition:attachment;filename=logs.tar.gz\n\n";
    open( LOGS, "<", $filename ) || die "$0: cannot open $filename for reading: $!";
    binmode(LOGS);
    binmode STDOUT;

    while ( read( LOGS, $buffer, $buffsize ) ) {
      print $buffer;
    }
  }

}
else {
  print "Content-type: text/plain\n\n";
  print "No command specified, exiting...";

  # print \%ENV;
}

sub readCfg {
  if ( open( VMWCFG, "<$cfgdir/vmware.cfg" ) ) {
    while ( my $line = <VMWCFG> ) {
      chomp $line;
      $line =~ /.*"(.*)"/;
      $line = $1;
      my @hosts = split( / /, $line );
      foreach my $host (@hosts) {
        $host =~ s/^\s+|\s+$//g;
        my ( $al, $srv, $usr ) = split( /\|/, $host );
        $cfg{$srv}{$usr} = $al;
      }
    }
    close VMWCFG;
  }
}

sub credsToCfg {
  if ( open( VMVCFG, ">$cfgdir/vmware.cfg" ) ) {
    my $vmlist = "VMWARE_LIST=\"";
    my $call   = "$perl $vmwlibdir/credstore_admin.pl --credstore $credstore list";
    my @creds  = `$call`;
    chomp @creds;
    my $delim = "";
    if (@creds) {
      for my $line ( @creds[ 1 .. $#creds ] ) {
        if ( !$line ) {
          last;
        }
        $line =~ s/^\s+|\s+$//g;
        my @pair = split " ", $line, 2;

        # if (exists $cfg{$pair[0]}{$pair[1]} && $cfg{$pair[0]}{$pair[1]}) {
        if ( $cfg{ $pair[0] }{ $pair[1] } ) {
          $vmlist .= $delim . "$cfg{$pair[0]}{$pair[1]}|$pair[0]|$pair[1]";
          $delim = " ";
        }
      }
    }
    print VMVCFG $vmlist . "\"";
    close VMVCFG;
    return 1;
  }
  else {
    return 0;
  }
}

sub result {
  my ( $status, $msg, $log ) = @_;
  $log ||= "";
  $msg =~ s/\n/\\n/g;
  $msg =~ s/\\:/\\\\:/g;
  $log =~ s/\n/\\n/g;
  $log =~ s/\\:/\\\\:/g;
  $status = ($status) ? "true" : "false";
  print "{ \"success\": $status, \"message\" : \"$msg\", \"log\": \"$log\"}";
}
