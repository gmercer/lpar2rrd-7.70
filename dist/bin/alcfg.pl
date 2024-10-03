use strict;
use warnings;

use Data::Dumper;
use JSON;

use Alerting;    # use module
use Xorux_lib;

use ACL;
my $acl     = ACL->new();
my $useacl  = $acl->useACL();
my $isAdmin = $acl->isAdmin();

# get URL parameters (could be GET or POST) and put them into hash %PAR
my $buffer;

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

my %PAR = %{ Xorux_lib::parse_url_params($buffer) };

# print STDERR Dumper \%PAR;

if ( !defined $PAR{cmd} ) {
  print "Content-type: text/plain\n\n";
  print "No command specified, exiting...";
  exit;
}

if ( $PAR{cmd} eq "test" ) {    ### Get list of credentials
  print "Content-type: text/html\n\n";
  print "<pre>";
  print Dumper \%ENV;
  print Dumper \%PAR;

}

elsif ( $PAR{cmd} eq "file" ) {    ### Get raw cfg file
  print "Content-type: text/plain\n\n";
  Alerting::printConfig();
}

elsif ( $PAR{cmd} eq "smtptest" ) {
  print "Content-type: application/json\n\n";
  if ( !$PAR{sendto} ) {
    my $status = { success => \0, message => "E-mail test failed: <br><pre>No recepient</pre><br>" };
    print encode_json($status);
    exit;
  }

  my $subject = 'LPAR2RRD SMTP test E-mail';
  my $message = 'This is just the test email sent from <b>LPAR2RRD</b> application. ';

  my ( $res, $errors ) = Xorux_lib::send_email( $PAR{sendto}, "", $subject, $message, undef, undef, 1 );

  if ($res) {
    my $status = { success => \0, message => "E-mail test for $PAR{sendto} failed: <br><pre>$errors</pre><br><br>In case of any problem follow <a target='_blank' href='https://lpar2rrd.com/mail-troubleshooting.htm'>troubleshooting docu.</a>" };
    print encode_json($status);
  }
  else {
    my $status = { success => \1, message => "E-mail test for $PAR{sendto} was completed, please check your mailbox. <br><br>In case of any problem follow <a target='_blank' href='https://lpar2rrd.com/mail-troubleshooting.htm'>troubleshooting docu.</a>" };
    print encode_json($status);
  }
}

elsif ( $PAR{cmd} eq "form" ) {    ### Get list of credentials
  print "Content-type: text/html\n\n";

  if ( $useacl && !$isAdmin ) {
    print "<div>You must be a member of Administrators group to configure Alerting!</div>";
    exit;
  }

  no warnings 'uninitialized';
  my %cfg = Alerting::getConfig();

  # TABs
  print <<_MARKER_;
<div id='tabs' style='text-align: center;'>
  <ul>
    <li><a href='#tabs-1'>Configuration</a></li>
    <li><a href='#tabs-2'>E-mail groups</a></li>
    <li><a href='#tabs-3'>Alerting options</a></li>
    <li><a href='#tabs-4'>HW events</a></li>
    <li><a href='#tabs-5'>SMTP options</a></li>
    <li><a href='/lpar2rrd-cgi/log-cgi.sh?name=alhist&gui=1'>Logs</a></li>
    <li><a href='/lpar2rrd-cgi/log-cgi.sh?name=alert_hw_log&gui=1'>Logs HW</a></li>
    <li><a href='#tabs-6'>Service Now</a></li>
    <li><a href='#tabs-7'>Jira Cloud</a></li>
    <li><a href='#tabs-8'>Opsgenie</a></li>
  </ul>

_MARKER_

  print <<_MARKER_;
<div id='tabs-1' style='display: inline-block'>
  <div style='float: left; margin-right: 10px; outline: none'>
    <fieldset class='estimator cggrpnames'>
      <table id="alrttree" class="cfgtree">
        <colgroup>
          <col width="2px">
          <col width="2px">
          <col width="220px">
          <col width="80px">
          <col width="45px">
          <col width="40px">
          <col width="45px">
          <col width="60px">
          <col width="120px">
          <col width="80px">
          <col width="20px">
        </colgroup>
        <thead>
        <tr>
          <th></th>
          <th></th>
          <th><button id="toggle" title="Expand/Collapse toggle" class="ui-icon-arrowthick-2-n-s">&plusmn;</button> <button id="addnewalrt">Add New Alert</button></th>
          <th>Metric</th>
          <th></th>
          <th><abbr title="limit value">Limit</abbr></th>
          <th><abbr title="value is in percent (CPU & CPU OS only)">%</abbr></th>
          <th><abbr title="time in minutes for length peak above the limit [10-unlimited]">Peak</abbr></th>
          <th><abbr title="minimum time in minutes between 2 alerts for the same rule [10-unlimited]">Repeat</abbr></th>
          <th><abbr title="time range in hours when the alerting is off [0-24]-[0-24]. Ex. 22-05&nbsp;(excludes alerting from 10pm to 5am)">Exclude hours</abbr></th>
          <th>Mail group</th>
          <th></th>
          <!--th><button id="cgcfg-help-button" title="Help on usage">?</button></th-->
        </tr>
        </thead>
        <tbody>
        </tbody>
      </table>
    </fieldset>
    <div style="text-align: center">
      <!--input type='submit' style='font-weight: bold; margin-top: .7em' name='testbtn' id='testalrtcfg' value='Test alerting'-->
      <input type='submit' style='font-weight: bold; margin-top: .7em' name='savegrp' class='savealrtcfg' value='Save configuration'>
    </div>
    <p class="notice">This feature is not supported yet for oVirt/RHV, XenServer, Solaris, OracleVM, Nutanix and MS Windows server/Hyper-V. It will come in future releases.</p>
    <div id="freeinfo" style="text-align: center; display: none">
      <p>You are using LPAR2RRD Free Edition, only 3 top items are allowed. Consider to upgrade to the <a href='http://www.lpar2rrd.com/support.htm' target='_blank'><b>Enterprise Edition</b></a>.</p>
    </div>
  </div>

  <br style="clear: both">
  <pre>
  <div id='aclfile' style='text-align: left; margin: auto; background: #fcfcfc; border: 1px solid #c0ccdf; border-radius: 10px; padding: 15px; display: none; overflow: auto'></div>
  </pre>
</div>

<div id='tabs-2' style='display: inline-block'>
  <div style='float: left; margin-right: 10px; outline: none'>
    <fieldset class='estimator cggrpnames'>
      <table id="alrtgrptree" class="cfgtree">
        <colgroup>
          <col width="2px">
          <col width="2px">
          <col width="320px">
          <col width="4px">
          <col width="20px">
        </colgroup>
        <thead>
        <tr>
        <th></th>
        <th></th>
        <th id="addcgrpth">E-mail group &nbsp;<button id="addalrtgrp">Add New</button></th>
        <th></th>
        <!--th><button id="cgcfg-help-button" title="Help on usage">?</button></th-->
        </tr>
        </thead>
        <tbody>
        </tbody>
      </table>
    </fieldset>
    <div style="text-align: center">
      <input type='submit' style='font-weight: bold; margin-top: .7em' name='savegrp' class='savealrtcfg' value='Save configuration'>
    </div>
    <div>
      <p style='margin-top:25px;font-size: 0.7em'><a href='https://lpar2rrd.com/email_setup_virtual-appliance.php' target='_blank'>E-mail setup documentation</a></p>
    </div>
  </div>
</div>
<div id='tabs-3' style='display: inline-block'>
  <div style='float: left; margin-right: 10px; outline: none'>
    <form id="optform" method="post" action="" style="display: table;" autocomplete="off">
    <fieldset>
    <div>
      <label for="element_2">Nagios alerting &nbsp;</label>
      <input id="element_2" name="NAGIOS" class="alrtoption text medium" type="text" maxlength="255" title="Call this script from nrpe.cfg: bin/check_lpar2rrd<br>More details on <a href='http://www.lpar2rrd.com/nagios.html'>http://www.lpar2rrd.com/nagios.html</a><br>[0/1] on/off" value="$cfg{NAGIOS}">
    </div>
    <div>
    <label for="element_3">External script for alerting &nbsp;</label>
      <input id="element_3" name="EXTERN_ALERT" class="alrtoption text medium" type="text" maxlength="255" title="It will be called once an alarm appears with these 6 parameters:<br>script.sh [SEVERITY] [TYPE] [SERVER] [LPAR_or_POOL] [ACT_UTILIZATION] [MAX_UTLIZATION_LIMIT] <br>- you can use <b>bin/external_alert_example.sh</b> as an example<br>- script must be placed in <b>{LPAR2RRD_HOME}/bin</b> and path start with <b>bin/</b>" value="$cfg{EXTERN_ALERT}">
    </div>
    <div>
    <label for="element_4">Include graphs &nbsp;</label>
      <input id="element_4" name="EMAIL_GRAPH" class="alrtoption text medium" type="text" maxlength="255" title="Include graphs into the email notification.<br>Any positive number gives number of hours which the graph contains. Examples: <br>0 - false<br>8 - last 8 hours in the graph<br>25 - last 25 hours in the graph<br>[0 - 256]" value="$cfg{EMAIL_GRAPH}">
    </div>
    <div>
    <label for="element_5">Default repeat time (min)&nbsp;</label>
      <input id="element_5" name="REPEAT_DEFAULT" class="alrtoption text medium" type="text" maxlength="255" title="Default time in minutes which says how often you should be alerted. You can specify per volume different value in <b>alert repeat time</b> column of each ALERT<br>[5 - 168]" value="$cfg{REPEAT_DEFAULT}">
    </div>
    <div>
    <label for="element_6">Default peak time (min)&nbsp;</label>
      <input id="element_6" name="PEAK_TIME_DEFAULT" class="alrtoption text medium" type="text" maxlength="255" title="The period of time in which avg traffic utilization has to be over the specified limit to generate an alert.<br>You can change it per volume level in <b>time in min</b> column of each ALERT note.<br> [15 - 120]" value="$cfg{PEAK_TIME_DEFAULT}">
    </div>
    <div>
    <label for="element_7">SNMP trap host&nbsp;</label>
      <input id="element_7" name="TRAP" class="alrtoption text medium" type="text" maxlength="80" title="Hostname or IP of SNMP trap receiver.<br> []" value="$cfg{TRAP}">
    </div>
    <div>
    <label for="element_8">SNMP community string&nbsp;</label>
      <input id="element_8" name="COMM_STRING" class="alrtoption text medium" type="text" maxlength="80" title="SNMP community string<br> []" value="$cfg{COMM_STRING}">
    </div>
    </fieldset>
    <div style="text-align: center">
      <input type='submit' style='font-weight: bold; margin-top: .7em' name='savegrp' class='savealrtcfg' value='Save configuration'>
    </div>
    </form>
  </div>
</div>
<div id='tabs-4' style='display: inline-block'>
  <div style='float: left; margin-right: 10px; outline: none'>
    <form id="moreoptform" method="post" action="" style="display: table;" autocomplete="off">
    <fieldset>
    <div>
    <label for="element_hw1"> E-mail targets &nbsp;</label>
      <input id="element_hw1" name="EMAIL_EVENT" class="alrtoption text medium" type="text" maxlength="255" title="Define email targets separated by a space" value="$cfg{EMAIL_EVENT}">
    </div>
    </fieldset>
    <p class='notice'>Used only for OS Multipath alerting so far (based on the OS agent).</p>
    <div style="text-align: center">
      <input type='submit' style='font-weight: bold; margin-top: .7em' name='savegrp' class='savealrtcfg' value='Save configuration'>
    </div>
    </form>
  </div>
</div>
_MARKER_
  my $encr;
  foreach my $enctype (qw/auto ssl tls none/) {
    if ( $cfg{SMTP_ENC} && $cfg{SMTP_ENC} eq $enctype ) {
      $encr->{$enctype} = "selected";
    }
    else {
      $encr->{$enctype} = "";
    }
  }
  print <<_SMTP_;
<div id='tabs-5' style='display: inline-block'>
  <div style='float: left; margin-right: 10px; outline: none'>
    <p>SMTP options (the same are used in Reporter)
    <p class='notice'>Note: When empty then OS system defaults are used.</p>
    <form id="smtpoptform" method="post" action="" style="display: table;" autocomplete="off">
    <fieldset>
    <div>
    <label for="element_s4">SMTP server address&nbsp;</label>
      <input id="element_s4" name="SMTP_HOST" class="alrtoption text medium" type="text" maxlength="80" title="Fill if you want or have to send e-mail via a named server instead of the local sendmail function." value="$cfg{SMTP_HOST}">
    </div>
    <div>
    <label for="element_s5">SMTP port&nbsp;</label>
      <input id="element_s5" name="SMTP_PORT" class="alrtoption text medium" type="text" maxlength="80" title="Optional. Defaults to 25 for unencrypted and TLS SMTP, and 465 for SSL SMTP." value="$cfg{SMTP_PORT}">
    </div>
    <div style="text-align: left;">
    <label for="element_s6">SMTP encryption&nbsp;</label>
    <select id="element_s6" name="SMTP_ENC" style="width: 10rem; margin-bottom: 2px" class="alrtoption medium" title="Enter the transport layer encryption required by your SMTP server." value="$cfg{SMTP_ENC}">
       <option value="" $encr->{none}>none</option>
       <option value="tls" $encr->{tls}>TLS</option>
       <option value="ssl" $encr->{ssl}>SSL</option>
    </select>
    </div>
    <div>
    <label for="element_s8">SMTP username&nbsp;</label>
      <input id="element_s8" name="SMTP_USER" class="alrtoption text medium" type="text" maxlength="80" title="Only enter a username if your SMTP server requires it." value="$cfg{SMTP_USER}" autocomplete="new-password">
    </div>
    <div>
    <label for="element_s9">SMTP password&nbsp;</label>
      <input id="element_s9" name="SMTP_PASS" class="alrtoption text medium passfield" type="password" maxlength="80" title="Only enter a password if your SMTP server requires it." value="$cfg{SMTP_PASS}" autocomplete="new-password">
    </div>
    <div style="text-align: left;">
    <label for="element_s7">Authentication method&nbsp;</label>
    <select id="element_s7" name="SMTP_AUTH" style="width: 10rem; margin-bottom: 2px" class="alrtoption medium" title="Only used if a username/password is set, ask your provider if you are unsure which method to use." value="$cfg{SMTP_AUTH}">
       <option value="">Plain</option>
       <option value="LOGIN">Login</option>
       <option value="CRAM-MD5">Cram-MD5</option>
       <option value="DIGEST-MD5">Digest-MD5</option>
    </select>
    </div>
    <div>
    <label for="element_s10">SMTP from address&nbsp;</label>
      <input id="element_s10" name="MAILFROM" class="alrtoption text medium" type="text" maxlength="80" title="Mail from" value="$cfg{MAILFROM}">
    </div>
    <div>
    <label for="element_s11">LPAR2RRD web UI URL&nbsp;</label>
      <input id="element_s11" name="WEB_UI_URL" class="alrtoption text medium" type="text" maxlength="80" title="Embeded links will point to this page." value="$cfg{WEB_UI_URL}">
    </div>
    </fieldset>
    <div style="text-align: center">
      <input type='submit' style='font-weight: bold; margin-top: .7em' name='savegrp' class='savealrtcfg' value='Save configuration'>
      <button style='font-weight: bold; padding: 0.4em; margin-top: .7em; margin-left: 1em;' id='smtptest'>Test sending e-mail</button>
    </div>
    </form>
  </div>
</div>
_SMTP_

  print <<_MARKER_;
<div id='tabs-6' style='display: inline-block'>
  <div style='float: left; margin-right: 10px; outline: none'>
    <form id="servicenowform" method="post" action="" style="display: table;" autocomplete="off">
    <fieldset>
    <div>
      <label for="element_11">Instancename &nbsp;</label>
      <input id="element_11" name="SERVICE_NOW_IP" class="alrtoption text medium required" type="text" maxlength="255" title="https://<instancename>.service-now.com/api/global/em/jsonv2" value="$cfg{SERVICE_NOW_IP}">
    </div>
    <div>
    <label for="element_13">User &nbsp;</label>
      <input id="element_13" name="SERVICE_NOW_USER" class="alrtoption text medium required" type="text" maxlength="255" title="" value="$cfg{SERVICE_NOW_USER}" autocomplete="new-password">
    </div>
    <div>
    <label for="element_14">Password &nbsp;</label>
      <input id="element_14" name="SERVICE_NOW_PASSWORD" class="alrtoption text medium required" type="password" maxlength="255" title="" value="$cfg{SERVICE_NOW_PASSWORD}" autocomplete="new-password">
    </div>
    <div>
    <label for="element_15">Severity &nbsp;</label>
      <input id="element_15" name="SERVICE_NOW_SEVERITY" class="alrtoption text medium" type="text" maxlength="255" title="Severity range from 1 – Critical to 5" value="$cfg{SERVICE_NOW_SEVERITY}">
    </div>
    <div>
    <label for="element_16">Type &nbsp;</label>
      <input id="element_16" name="SERVICE_NOW_TYPE" class="alrtoption text medium" type="text" maxlength="255" title="" value="$cfg{SERVICE_NOW_TYPE}">
    </div>
    <div>
    <label for="element_17">Event Class &nbsp;</label>
      <input id="element_17" name="SERVICE_NOW_EVENT" class="alrtoption text medium" type="text" maxlength="255" title="" value="$cfg{SERVICE_NOW_EVENT}">
    </div>
    </fieldset>
    <div style="text-align: center">
      <input type='submit' style='font-weight: bold; margin-top: .7em' name='saveservicenow' class='savealrtcfg' value='Save configuration'>
    </div>
    </form>
  </div>
</div>

<div id='tabs-7' style='display: inline-block'>
  <div style='float: left; margin-right: 10px; outline: none'>
    <form id="jiraform" class="optform" method="post" action="" style="display: table;" autocomplete="off">
    <fieldset>
    <div>
      <label for="element_18">URL &nbsp;</label>
      <input id="element_18" name="JIRA_URL" class="alrtoption text medium required" type="text" maxlength="255" title='https://<b>your-domain</b>.atlassian.net/rest/api/2/issue' value="$cfg{JIRA_URL}">
    </div>
    <div>
    <label for="element_19">Token &nbsp;</label>
      <input id="element_19" name="JIRA_TOKEN" class="alrtoption text medium required" type="password" maxlength="255" title="Create an API token. ( It should work at this url: https://id.atlassian.com/manage-profile/security/api-tokens )" value="$cfg{JIRA_TOKEN}" autocomplete="new-password">
    </div>
    <div>
    <label for="element_20">User &nbsp;</label>
      <input id="element_20" name="JIRA_USER" class="alrtoption text medium required" type="text" maxlength="255" title="email.example.com" value="$cfg{JIRA_USER}" autocomplete="new-password">
    </div>
    <div>
    <label for="element_21">Project Key &nbsp;</label>
      <input id="element_21" name="JIRA_PROJECT_KEY" class="alrtoption text medium required" type="text" maxlength="255" title="We will need a project key to which we assign all issues from our environment. ( All projects and keys can be found at this address: https://<b>your-domain</b>.atlassian.net/jira/settings/projects/manage )" value="$cfg{JIRA_PROJECT_KEY}">
    </div>
    <div>
    <label for="element_22">Issue ID &nbsp;</label>
      <input id="element_22" name="JIRA_ISSUE_ID" class="alrtoption text medium required" type="text" maxlength="255" title="For example, 10001(TASK), 10002(EPIC), 10003(SUBTASK). And many more, maybe even others of your own that you have created. You can find out how to get the issue id at this link: https://confluence.atlassian.com/jirakb/finding-the-id-for-issue-types-646186508.html" value="$cfg{JIRA_ISSUE_ID}">
    </div>
    </fieldset>
    <div style="text-align: center">
      <input type='submit' style='font-weight: bold; margin-top: .7em' name='savejiracloud' class='savealrtcfg' value='Save configuration'>
    </div>
    </form>
  </div>
</div>
_MARKER_
  my $url;
  $url->{'EU'} = "";
  $url->{'GLOBAL'} = "";
  if ( $cfg{OPSGENIE_URL} && $cfg{OPSGENIE_URL} eq "https://api.eu.opsgenie.com/v2/alerts" ) {
    $url->{'EU'} = "selected";
  }
  else {
    $url->{'GLOBAL'} = "selected";
  }
  print <<_OPSGENIE_;
<div id='tabs-8' style='display: inline-block'>
  <div style='float: left; margin-right: 10px; outline: none'>
    <form id="opsgenieform" class="optform" method="post" action="" style="display: table;" autocomplete="off">
    <fieldset>
    <div style="text-align: left;">
    <label for="element_23">Select the instance you are using&nbsp;</label>
    <select id="element_23" name="OPSGENIE_URL" style="width: 10rem; margin-bottom: 2px" class="alrtoption medium" title="Select the instance you are using" value="$cfg{OPSGENIE_URL}">
       <option value="https://api.eu.opsgenie.com/v2/alerts" $url->{'EU'}>https://api.eu.opsgenie.com</option>
       <option value="https://api.opsgenie.com/v2/alerts" $url->{'GLOBAL'}>https://api.opsgenie.com</option>
    </select>
    </div>
    <div>
      <label for="element_24">API Integration Key (GenieKey) &nbsp;</label>
      <input id="element_24" name="OPSGENIE_KEY" class="alrtoption text medium required" type="password" maxlength="255" title='teams -> integration -> search for API and create an API integration -> API Key' value="$cfg{OPSGENIE_KEY}" autocomplete="new-password">
    </div>
    </fieldset>
    <div style="text-align: center">
      <input type='submit' style='font-weight: bold; margin-top: .7em' name='saveopsgenie' class='savealrtcfg' value='Save configuration'>
    </div>
    </form>
  </div>
</div>

</div>
_OPSGENIE_

}
elsif ( $PAR{cmd} eq "save" ) {    ### Get list of credentials
  my $basedir = $ENV{INPUTDIR};
  $basedir ||= "..";

  my $cfgdir = "$basedir/etc/web_config";

  my $tmpdir = "$basedir/tmp";
  if ( defined $ENV{TMPDIR_LPAR} ) {
    $tmpdir = $ENV{TMPDIR_LPAR};
  }
  print "Content-type: text/html\n\n";
  if ( $PAR{acl} ) {
    my $cfg    = $PAR{acl};
    my $retstr = "";
    if ( $ENV{'SERVER_NAME'} eq "demo.lpar2rrd.com" ) {
      $cfg =~ s/\n/\\n/g;
      $cfg =~ s/\\:/\\\\:/g;
      $retstr = "\"msg\" : \"<div>This demo site does not allow saving any changes you do in the admin GUI panel.<br />";
      $retstr .= "You can only see the preview of alerting.cfg to be written.</div>\", \"cfg\" : \"";
      print "{ \"status\" : \"success\", $retstr" . "$cfg\" }";
    }
    elsif ( open( CFG, ">$cfgdir/alerting.cfg" ) ) {
      $cfg =~ s/\\:/===========doublecoma=========/g;
      print CFG "$cfg\n";
      close CFG;
      $cfg =~ s/\n/\\n/g;
      $cfg =~ s/\\:/\\\\:/g;
      $retstr = "\"msg\" : \"<div>Alerting configuration file has been successfully saved!<br /><br /></div>\", \"cfg\" : \"";
      print "{ \"status\" : \"success\", $retstr" . "$cfg\" }";
    }
    else {
      print "{ \"status\" : \"fail\", \"msg\" : \"<div>File $cfgdir/alerting.cfg cannot be written by webserver, check apache user permissions: <span style='color: red'>$!</span></div>\" }";
    }
  }
  else {
    print "{ \"status\" : \"fail\", \"msg\" : \"<div>No data was written to alerting.cfg</div>\" }";
  }

}

sub urldecode {
  my $s = shift;
  $s =~ s/\%([A-Fa-f0-9]{2})/pack('C', hex($1))/seg;
  $s =~ s/\+/ /g;
  return $s;
}
