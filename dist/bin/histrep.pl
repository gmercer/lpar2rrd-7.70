
use strict;
use warnings;
use CGI::Carp qw(fatalsToBrowser);

# use Data::Dumper;

my $inputdir = $ENV{INPUTDIR} ||= "";
my $cfgdir   = "$inputdir/etc/web_config";
my $perl     = $ENV{PERL};

# get URL parameters (could be GET or POST) and put them into hash %PAR
my ( $buffer, @pairs, $pair, $name, $value, %PAR );
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

if ( defined $PAR{platform} && $PAR{platform} eq "Power"  && $PAR{type} eq "historical_reports" ) { $PAR{mode} = "global"; }      #new url type for Xormon, there is not defined mode
if ( defined $PAR{platform} && $PAR{platform} eq "Vmware" && $PAR{type} eq "historical_reports" ) { $PAR{mode} = "globalvm"; }    #new url type for Xormon, there is not defined mode
if ( defined $PAR{platform} && $PAR{platform} eq "Linux"  && $PAR{type} eq "historical_reports" ) { $PAR{mode} = "linux"; }       #new url type for Xormon, there is not defined mode

if ( $PAR{mode} eq "global" ) {    ### run load.sh and show what to do next
  print "Content-type: text/html\n\n";
  print <<_MARKER_;
<center>
  <div style="font-size: .8em;">
    <!--span style="font-size: 1em; font-weight: bold">Time range: </span-->
    <label for="from">From</label>
    <input type="text" id="fromTime" size="14">
    <label for="to">to</label>
    <input type="text" id="toTime" size="14">
  </div>
    <form method="post" action="/lpar2rrd-cgi/lpar-list-cgi.sh" id="histrepg">
    <input type="hidden" name="start-hour" id="start-hour" size="3" value="12">
    <input type="hidden" name="start-day" id="start-day" size="3">
    <input type="hidden" name="start-mon" id="start-mon" size="3">
    <input type="hidden" name="start-yr" id="start-yr" size="3">
    <input type="hidden" name="end-hour" id="end-hour" size="3" value="12">
    <input type="hidden" name="end-day" id="end-day" size="3">
    <input type="hidden" name="end-mon" id="end-mon" size="3">
    <input type="hidden" name="end-yr" id="end-yr" size="3">
    <input type="hidden" name="type" id="type" size="3" value="x">
    <input type="hidden" name="yaxis" id="yaxis" size="3" value="c">
    <table border="0" cellspacing="5">
        <tbody>
        <tr>
            <td colspan="2">
            <table align="center">
                <tbody>
                <tr>
                    <td style="font-size: .8em;">Graph resolution <input type="text" name="HEIGHT" value="150" size="2"> x <input type="text" name="WIDTH" value="700" size="2"></td>
                    <td></td>
                </tr>
                </tbody>
            </table>
            </td>
        </tr>

        <tr>
            <td colspan="2" align="center">
            <input type="hidden" name="sort" value="server">
      <input type="hidden" name="gui" value="1">
      <input type="hidden" name="pool" value="">

            <table border="0">
                <tbody>
                <!--tr>
                    <td>
            <span style="font-size: 1em; font-weight: bold">LPARs</span>
                    </td>
                    <td>
            <span style="font-size: 1em; font-weight: bold">CPU Pools</span>
                    </td>
                    <td>
            <span style="font-size: 1em; font-weight: bold">Custom Groups</span>
                    </td>
                </tr-->
        <tr valign="top">
          <div>
          <td>
            <div style="float: left">
              <fieldset class="estimator">
                <legend>Server | LPARs <label><input type='checkbox' class="allcheck" name="alllpars" value='outdata'>all&nbsp;</label></legend>
                <input type="text" id="srvlparfilter" placeholder="Filter...">
                <div id="lpartree" name="selLpars" class="seltree"></div>
              </fieldset>
            </div>
          </td>
          <td>
            <div style="float: left" id="existserver">
              <fieldset class="estimator">
                <legend>Server | Pools <label><input type='checkbox' class="allcheck" name="allpools" value='outdata'>all&nbsp;</label></legend>
                <div id="hpooltree" name="selPool" class="seltree"></div>
              </fieldset>
            </div>
          </td>
          <td>
            <div style="float: left" id="existserver">
              <fieldset class="estimator">
                <legend>Custom Groups <label><input type='checkbox' class="allcheck" name="allgroups" value='outdata'>all&nbsp;</label></legend>
                <div id="custompowertree" name="selCust" class="seltree"></div>
              </fieldset>
            </div>
          </td>
        </div>
        </tr>
               </tbody>
            </table>
      <input type="hidden" name=entitle value="0"><br>
            <input type="submit" style="font-weight: bold" name="Report" value="Generate Report" alt="Generate Report">
            </td>
        </tr>
        </tbody>
    </table>
    </form>
</center>

_MARKER_

}

elsif ( $PAR{mode} eq "globalvm" ) {    ### run load.sh and show what to do next
  print "Content-type: text/html\n\n";
  print <<_MARKER_;
<div id="ghistrepvm">
  <label for="vmhistrepsrc">vCenter: </label>
  <select id="vmhistrepsrc"></select>
</div>
<div id="vmhistrepdiv" style="margin-top: 3em;"> </div>
_MARKER_

}
elsif ( $PAR{mode} eq "power" ) {    ### run load.sh and show what to do next
  print "Content-type: text/html\n\n";
  print <<_MARKER_;
<center>
  <div style="font-size: 0.8em">
    <label for="from">From</label>
    <input type="text" id="fromTime" size="14">
    <label for="to">to</label>
    <input type="text" id="toTime" size="14">
  </div>
    <form method="get" action="/lpar2rrd-cgi/lpar2rrd-cgi.sh" id="histrep">
    <input type="hidden" name="start-hour" id="start-hour" size="3" value="12">
    <input type="hidden" name="start-day" id="start-day" size="3">
    <input type="hidden" name="start-mon" id="start-mon" size="3">
    <input type="hidden" name="start-yr" id="start-yr" size="3">
    <input type="hidden" name="end-hour" id="end-hour" size="3" value="12">
    <input type="hidden" name="end-day" id="end-day" size="3">
    <input type="hidden" name="end-mon" id="end-mon" size="3">
    <input type="hidden" name="end-yr" id="end-yr" size="3">
    <table border="0" cellspacing="5">
        <tbody>
        <tr>
            <td colspan="2">
            <table align="center">
                <tbody>
                <tr>
                    <td style="font-size: .8em;">
            &nbsp;&nbsp;Sample rate
            <select id="type" name="type">
              <option value="60" selected>
              1 minute
              </option>
              <option value="3600">
              1 hour
              </option>
              <option value="86400">
              1 day
              </option>
            </select>
            &nbsp;&nbsp;Graph resolution <input type="text" name="HEIGHT" value="150" size="2"> x <input type="text" name="WIDTH" value="700" size="2">
            <input type="hidden" name="yaxis" id="yaxis" size="3" value="c">
          </td>
                </tr>
                </tbody>
            </table>
      <input type="hidden" name="HMC" id="hmc" size="3" value="">
      <input type="hidden" name="MNAME" id="mname" size="3" value="">
            </td>
        </tr>

        <tr>
            <td colspan="2" align="center">

            <table border="0">
                <tbody>
        <tr valign="top">
          <div>
          <td>
            <div style="float: left">
              <fieldset class="estimator">
                <legend>Select item(s)</legend>
                <div id="histreptree" name="selLpars" class="seltree"></div>
              </fieldset>
            </div>
          </td>
        </div>
        </tr>
               </tbody>
            </table>
      <input type="hidden" name="entitle" value="0"><br>
      <input type="hidden" name="gui" value="1">
            <input type="submit" style="font-weight: bold" name="Report" value="Generate Report" alt="Generate Report">
            </td>
        </tr>
        </tbody>
    </table>
    </form>
</center>
_MARKER_

}
elsif ( $PAR{mode} eq "linux" ) {
  print "Content-type: text/html\n\n";
  print <<_MARKER_;
<center>
  <div style="font-size: 0.8em">
    <label for="from">From</label>
    <input type="text" id="fromTime" size="14">
    <label for="to">to</label>
    <input type="text" id="toTime" size="14">
  </div>
    <form method="get" action="/lpar2rrd-cgi/lpar2rrd-cgi.sh" id="histrepl">
    <input type="hidden" name="start-hour" id="start-hour" size="3" value="12">
    <input type="hidden" name="start-day" id="start-day" size="3">
    <input type="hidden" name="start-mon" id="start-mon" size="3">
    <input type="hidden" name="start-yr" id="start-yr" size="3">
    <input type="hidden" name="end-hour" id="end-hour" size="3" value="12">
    <input type="hidden" name="end-day" id="end-day" size="3">
    <input type="hidden" name="end-mon" id="end-mon" size="3">
    <input type="hidden" name="end-yr" id="end-yr" size="3">
    	<table border="0" cellspacing="5">
        <tbody>
        <tr>
            <td colspan="2">
            <table align="center">
                <tbody>
                <tr>
                    <td style="font-size: .8em;">
            &nbsp;&nbsp;Sample rate
            <select id="type" name="type">
              <option value="60" selected>
              1 minute
              </option>
              <option value="3600">
              1 hour
              </option>
              <option value="86400">
              1 day
              </option>
            </select>
            &nbsp;&nbsp;Graph resolution <input type="text" name="HEIGHT" value="150" size="2"> x <input type="text" name="WIDTH" value="700" size="2">
            <input type="hidden" name="yaxis" id="yaxis" size="3" value="c">
          </td>
                </tr>
                </tbody>
            </table>
      <input type="hidden" name="HMC" id="hmc" size="3" value="">
      <input type="hidden" name="MNAME" id="mname" size="3" value="">
            </td>
        </tr>

        <tr>
            <td colspan="2" align="center">

            <table border="0">
                <tbody>
        <tr valign="top">
          <div>
          <td>
            <div style="float: left">
              <fieldset class="estimator">
                <legend>Select item(s)</legend>
                <div id="linuxtree" name="selLpars" class="seltree"></div>
              </fieldset>
            </div>
          </td>
        </div>
        </tr>
               </tbody>
            </table>
      <input type="hidden" name="entitle" value="0"><br>
      <input type="hidden" name="gui" value="1">
            <input type="submit" style="font-weight: bold" name="Report" value="Generate Report" alt="Generate Report">
            </td>
        </tr>
        </tbody>
    </table>
    </form>
</center>
_MARKER_

}
elsif ( $PAR{mode} eq "vcenter" ) {
  print "Content-type: text/html\n\n";
  print <<_MARKER_;
<center>
  <div style="font-size: .8em;">
    <!--span style="font-size: 1em; font-weight: bold">Time range: </span-->
    <label for="from">From</label>
    <input type="text" id="fromTime" size="14">
    <label for="to">to</label>
    <input type="text" id="toTime" size="14">
  </div>
    <form method="post" action="/lpar2rrd-cgi/vcenter-list-cgi.sh" id="histrepv">
    <input type="hidden" name="start-hour" id="start-hour" size="3" value="12">
    <input type="hidden" name="start-day" id="start-day" size="3">
    <input type="hidden" name="start-mon" id="start-mon" size="3">
    <input type="hidden" name="start-yr" id="start-yr" size="3">
    <input type="hidden" name="end-hour" id="end-hour" size="3" value="12">
    <input type="hidden" name="end-day" id="end-day" size="3">
    <input type="hidden" name="end-mon" id="end-mon" size="3">
    <input type="hidden" name="end-yr" id="end-yr" size="3">
    <input type="hidden" name="type" id="type" size="3" value="m">
    <input type="hidden" name="yaxis" id="yaxis" size="3" value="c">
    <table border="0" cellspacing="5">
        <tbody>
        <tr>
            <td colspan="2">
            <table align="center">
                <tbody>
                <tr>
                    <td style="font-size: .8em;">Graph resolution <input type="text" name="HEIGHT" value="150" size="2"> x <input type="text" name="WIDTH" value="700" size="2"></td>
                </tr>
                <tr>
                  <td>
                    <div id="hrepselcol" style="">
                      <input type="radio" id="radio1" name="radio"><label for="radio1">Cluster</label>
                      <input type="radio" id="radio2" name="radio"><label for="radio2">Resource Pool</label>
                      <input type="radio" id="radio3" name="radio"><label for="radio3">VM</label>
                      <input type="radio" id="radio4" name="radio"><label for="radio4">Datastore</label>
                    </div>
                    </td>
                    <td></td>
                </tr>
                </tbody>
            </table>
            </td>
        </tr>

        <tr>
            <td colspan="2" align="center">
            <input type="hidden" name="sort" value="server">
      <input type="hidden" name="gui" value="1">
      <input type="hidden" name="vcenter" id="vcenter" value="">

            <table border="0">
                <tbody>
        <tr valign="top">
          <div>
          <td>
            <div style="float: left" class="stree">
              <fieldset class="estimator">
                <legend>Cluster <label><input type='checkbox' class="allcheck" name="allclusters" value='outdata'>all&nbsp;</label></legend>
                <div id="clstrtree" name="selClusters" class="seltree"></div>
              </fieldset>
            </div>
          </td>
          <td>
            <div style="float: left" class="stree">
              <fieldset class="estimator">
                <legend>Resource Pool <label><input type='checkbox' class="allcheck" name="allrespools" value='outdata'>all&nbsp;</label></legend>
                <div id="respooltree" name="selResPools" class="seltree"></div>
              </fieldset>
            </div>
          </td>
          <td>
            <div style="float: left" class="stree">
              <fieldset class="estimator">
                <legend>VM <label><input type='checkbox' class="allcheck" name="allvms" value='outdata'>all&nbsp;</label></legend>
                <input type="text" id="vmfilter" placeholder="Filter...">
                <div id="vmtree" name="selVMs" class="seltree"></div>
              </fieldset>
            </div>
          </td>
          <td>
            <div style="float: left" class="stree">
              <fieldset class="estimator">
                <legend>Datastore <label><input type='checkbox' class="allcheck" name="alldatastores" value='outdata'>all&nbsp;</label></legend>
                <input type="text" id="dsfilter" placeholder="Filter...">
                <div id="dstree" name="selDataStores" class="seltree"></div>
              </fieldset>
            </div>
          </td>
        </div>
        </tr>
               </tbody>
            </table>
      <input type="hidden" name=entitle value="0"><br>
            <input type="submit" style="font-weight: bold" name="Report" value="Generate Report" alt="Generate Report">
            </td>
        </tr>
        </tbody>
    </table>
    </form>
</center>
_MARKER_
}
elsif ( $PAR{mode} eq "esxi" || $PAR{mode} eq "solo_esxi" ) {
  print "Content-type: text/html\n\n";
  print <<_MARKER_;
<center>
  <div style="font-size: 0.8em">
    <label for="from">From</label>
    <input type="text" id="fromTime" size="14">
    <label for="to">to</label>
    <input type="text" id="toTime" size="14">
  </div>
    <form method="post" action="/lpar2rrd-cgi/vcenter-list-cgi.sh" id="histrepesxi">
    <input type="hidden" name="start-hour" id="start-hour" size="3" value="12">
    <input type="hidden" name="start-day" id="start-day" size="3">
    <input type="hidden" name="start-mon" id="start-mon" size="3">
    <input type="hidden" name="start-yr" id="start-yr" size="3">
    <input type="hidden" name="end-hour" id="end-hour" size="3" value="12">
    <input type="hidden" name="end-day" id="end-day" size="3">
    <input type="hidden" name="end-mon" id="end-mon" size="3">
    <input type="hidden" name="end-yr" id="end-yr" size="3">
    	<table border="0" cellspacing="5">
        <tbody>
        <tr>
            <td colspan="2">
            <table align="center">
                <tbody>
                <tr>
                    <td style="font-size: .8em;">
            &nbsp;&nbsp;Sample rate
            <select id="type" name="type">
              <option value="60" selected>
              1 minute
              </option>
              <option value="3600">
              1 hour
              </option>
              <option value="86400">
              1 day
              </option>
            </select>
            &nbsp;&nbsp;Graph resolution <input type="text" name="HEIGHT" value="150" size="2"> x <input type="text" name="WIDTH" value="700" size="2">
            <input type="hidden" name="yaxis" id="yaxis" size="3" value="c">
          </td>
                </tr>
                </tbody>
            </table>
      <input type="hidden" name="HMC" id="hmc" size="3" value="">
      <input type="hidden" name="MNAME" id="mname" size="3" value="">
      <input type="hidden" name="vcenter" id="vcenter" value="">
      <input type="hidden" name="esxi" id="esxi" value="">
            </td>
        </tr>

        <tr>
            <td colspan="2" align="center">

            <table border="0">
                <tbody>
        <tr valign="top">
          <div>
          <td>
            <div style="float: left">
              <fieldset class="estimator">
                <legend>Select item(s)</legend>
                <div id="histreptree-esxi" name="selLpars" class="seltree"></div>
              </fieldset>
            </div>
          </td>
        </div>
        </tr>
               </tbody>
            </table>
      <input type="hidden" name="entitle" value="0"><br>
      <input type="hidden" name="gui" value="1">
            <input type="submit" style="font-weight: bold" name="Report" value="Generate Report" alt="Generate Report">
            </td>
        </tr>
        </tbody>
    </table>
    </form>
</center>
_MARKER_
}
elsif ( $PAR{mode} eq "solaris" ) {
  print "Content-type: text/html\n\n";
  print <<_MARKER_;
<center>
  <div style="font-size: 0.8em">
    <label for="from">From</label>
    <input type="text" id="fromTime" size="14">
    <label for="to">to</label>
    <input type="text" id="toTime" size="14">
  </div>
    <form method="post" action="/lpar2rrd-cgi/lpar-list-cgi.sh" id="histrepsol">
    <input type="hidden" name="start-hour" id="start-hour" size="3" value="12">
    <input type="hidden" name="start-day" id="start-day" size="3">
    <input type="hidden" name="start-mon" id="start-mon" size="3">
    <input type="hidden" name="start-yr" id="start-yr" size="3">
    <input type="hidden" name="end-hour" id="end-hour" size="3" value="12">
    <input type="hidden" name="end-day" id="end-day" size="3">
    <input type="hidden" name="end-mon" id="end-mon" size="3">
    <input type="hidden" name="end-yr" id="end-yr" size="3">
    	<table border="0" cellspacing="5">
        <tbody>
        <tr>
            <td colspan="2">
            <table align="center">
                <tbody>
                <tr>
                    <td style="font-size: .8em;">
            &nbsp;&nbsp;Sample rate
            <select id="type" name="type">
              <option value="60" selected>
              1 minute
              </option>
              <option value="3600">
              1 hour
              </option>
              <option value="86400">
              1 day
              </option>
            </select>
            &nbsp;&nbsp;Graph resolution <input type="text" name="HEIGHT" value="150" size="2"> x <input type="text" name="WIDTH" value="700" size="2">
            <input type="hidden" name="yaxis" id="yaxis" size="3" value="c">
          </td>
                </tr>
                </tbody>
            </table>
      <input type="hidden" name="HMC" id="hmc" size="3" value="">
      <input type="hidden" name="MNAME" id="mname" size="3" value="">
            </td>
        </tr>

        <tr>
            <td colspan="2" align="center">

            <table border="0">
                <tbody>
        <tr valign="top">
          <div>
          <td>
            <div style="float: left">
              <fieldset class="estimator">
                <legend>Select item(s)</legend>
                <div id="histreptree-solaris" name="selLpars" class="seltree"></div>
              </fieldset>
            </div>
          </td>
        </div>
        </tr>
               </tbody>
            </table>
      <input type="hidden" name="entitle" value="0"><br>
      <input type="hidden" name="gui" value="1">
            <input type="submit" style="font-weight: bold" name="Report" value="Generate Report" alt="Generate Report">
            </td>
        </tr>
        </tbody>
    </table>
    </form>
</center>
_MARKER_
}
elsif ( $PAR{mode} eq "hyperv" ) {
  print "Content-type: text/html\n\n";
  print <<_MARKER_;
<center>
  <div style="font-size: 0.8em">
    <label for="from">From</label>
    <input type="text" id="fromTime" size="14">
    <label for="to">to</label>
    <input type="text" id="toTime" size="14">
  </div>
    <form method="post" action="/lpar2rrd-cgi/lpar-list-cgi.sh" id="histrephyperv">
    <input type="hidden" name="start-hour" id="start-hour" size="3" value="12">
    <input type="hidden" name="start-day" id="start-day" size="3">
    <input type="hidden" name="start-mon" id="start-mon" size="3">
    <input type="hidden" name="start-yr" id="start-yr" size="3">
    <input type="hidden" name="end-hour" id="end-hour" size="3" value="12">
    <input type="hidden" name="end-day" id="end-day" size="3">
    <input type="hidden" name="end-mon" id="end-mon" size="3">
    <input type="hidden" name="end-yr" id="end-yr" size="3">
    	<table border="0" cellspacing="5">
        <tbody>
        <tr>
            <td colspan="2">
            <table align="center">
                <tbody>
                <tr>
                    <td style="font-size: .8em;">
            &nbsp;&nbsp;Sample rate
            <select id="type" name="type">
              <option value="60" selected>
              1 minute
              </option>
              <option value="3600">
              1 hour
              </option>
              <option value="86400">
              1 day
              </option>
            </select>
            &nbsp;&nbsp;Graph resolution <input type="text" name="HEIGHT" value="150" size="2"> x <input type="text" name="WIDTH" value="700" size="2">
            </tr>
            <tr>
              <td style="text-align: center;">
                <div id="hrepselcol" style="">
                  <input type="radio" id="radio1" name="radio"><label for="radio1">Server</label>
                  <input type="radio" id="radio2" name="radio"><label for="radio2">VM</label>
                </div>
              </td>
            <input type="hidden" name="yaxis" id="yaxis" size="3" value="c">
          </td>
                </tr>
                </tbody>
            </table>
      <input type="hidden" name="HMC" id="hmc" size="3" value="">
      <input type="hidden" name="MNAME" id="mname" size="3" value="">
            </td>
        </tr>

        <tr>
            <td colspan="2" align="center">

            <table border="0">
                <tbody>
        <tr valign="top">
          <div>
          <td>
            <div style="float: left" class="stree">
              <fieldset class="estimator">
                <legend>Server </legend>
                <div id="histreptree-hyperv-server" name="selLpars" class="seltree"></div>
              </fieldset>
            </div>
          </td>
          <td>
            <div style="float: left" class="stree">
              <fieldset class="estimator">
                <legend>VM </legend>
                <div id="histreptree-hyperv-vm" name="selLpars" class="seltree"></div>
              </fieldset>
            </div>
          </td>
        </div>
        </tr>
               </tbody>
            </table>
      <input type="hidden" name="entitle" value="0"><br>
      <input type="hidden" name="gui" value="1">
            <input type="submit" style="font-weight: bold" name="Report" value="Generate Report" alt="Generate Report">
            </td>
        </tr>
        </tbody>
    </table>
    </form>
</center>
_MARKER_
}
elsif ( $PAR{type} eq "histrep-oraclevm" ) {
  print "Content-type: text/html\n\n";
  print <<_MARKER_;
<center>
  <div style="font-size: 0.8em">
    <label for="from">From</label>
    <input type="text" id="fromTime" size="14">
    <label for="to">to</label>
    <input type="text" id="toTime" size="14">
  </div>
    <form method="post" action="/lpar2rrd-cgi/lpar-list-cgi.sh" id="histreporaclevm">
    <input type="hidden" name="start-hour" id="start-hour" size="3" value="12">
    <input type="hidden" name="start-day" id="start-day" size="3">
    <input type="hidden" name="start-mon" id="start-mon" size="3">
    <input type="hidden" name="start-yr" id="start-yr" size="3">
    <input type="hidden" name="end-hour" id="end-hour" size="3" value="12">
    <input type="hidden" name="end-day" id="end-day" size="3">
    <input type="hidden" name="end-mon" id="end-mon" size="3">
    <input type="hidden" name="end-yr" id="end-yr" size="3">
    	<table border="0" cellspacing="5">
        <tbody>
        <tr>
            <td colspan="2">
            <table align="center">
                <tbody>
                <tr>
                    <td style="font-size: .8em;">
            &nbsp;&nbsp;Sample rate
            <select id="type" name="type">
              <option value="60" selected>
              1 minute
              </option>
              <option value="3600">
              1 hour
              </option>
              <option value="86400">
              1 day
              </option>
            </select>
            &nbsp;&nbsp;Graph resolution <input type="text" name="HEIGHT" value="150" size="2"> x <input type="text" name="WIDTH" value="700" size="2">
            </tr>
            <tr>
              <td style="text-align: center;">
                <div id="hrepselcol" style="">
                  <input type="radio" id="radio1" name="radio"><label for="radio1">Server</label>
                  <input type="radio" id="radio2" name="radio"><label for="radio2">VM</label>
                </div>
              </td>
            <input type="hidden" name="yaxis" id="yaxis" size="3" value="c">
          </td>
                </tr>
                </tbody>
            </table>
      <input type="hidden" name="HMC" id="hmc" size="3" value="">
      <input type="hidden" name="MNAME" id="mname" size="3" value="">
            </td>
        </tr>

        <tr>
            <td colspan="2" align="center">

            <table border="0">
                <tbody>
        <tr valign="top">
          <div>
          <td>
            <div style="float: left" class="stree">
              <fieldset class="estimator">
                <legend>Server </legend>
                <div id="histreptree-oraclevm-server" name="selLpars" class="seltree"></div>
              </fieldset>
            </div>
          </td>
          <td>
            <div style="float: left" class="stree">
              <fieldset class="estimator">
                <legend>VM </legend>
                <div id="histreptree-oraclevm-vm" name="selLpars" class="seltree"></div>
              </fieldset>
            </div>
          </td>
        </div>
        </tr>
               </tbody>
            </table>
      <input type="hidden" name="entitle" value="0"><br>
      <input type="hidden" name="gui" value="1">
            <input type="submit" style="font-weight: bold" name="Report" value="Generate Report" alt="Generate Report">
            </td>
        </tr>
        </tbody>
    </table>
    </form>
</center>
_MARKER_
}
elsif ( $PAR{mode} eq "custom" ) {
  print "Content-type: text/html\n\n";
  print <<_MARKER_;
<center>
  <div style="font-size: .8em;">
    <!--span style="font-size: 1em; font-weight: bold">Time range: </span-->
    <label for="from">From</label>
    <input type="text" id="fromTime" size="14">
    <label for="to">to</label>
    <input type="text" id="toTime" size="14">
  </div>
    <form method="post" action="/lpar2rrd-cgi/lpar-list-cgi.sh" id="histrepcustom">
    <input type="hidden" name="start-hour" id="start-hour" size="3" value="12">
    <input type="hidden" name="start-day" id="start-day" size="3">
    <input type="hidden" name="start-mon" id="start-mon" size="3">
    <input type="hidden" name="start-yr" id="start-yr" size="3">
    <input type="hidden" name="end-hour" id="end-hour" size="3" value="12">
    <input type="hidden" name="end-day" id="end-day" size="3">
    <input type="hidden" name="end-mon" id="end-mon" size="3">
    <input type="hidden" name="end-yr" id="end-yr" size="3">
    <input type="hidden" name="type" id="type" size="3" value="x">
    <input type="hidden" name="yaxis" id="yaxis" size="3" value="c">
    <table border="0" cellspacing="5">
        <tbody>
        <tr>
            <td colspan="2">
            <table align="center">
                <tbody>
                <tr>
                    <td style="font-size: .8em;">Graph resolution <input type="text" name="HEIGHT" value="150" size="2"> x <input type="text" name="WIDTH" value="700" size="2"></td>
                    <td></td>
                </tr>
                </tbody>
            </table>
            </td>
        </tr>

        <tr>
            <td colspan="2" align="center">
            <input type="hidden" name="sort" value="server">
      <input type="hidden" name="gui" value="1">
      <input type="hidden" name="pool" value="">
            </tr>
            <tr>
              <td style="text-align: center;">

          <td>
            <div style="float: left" id="existserver">
              <fieldset class="estimator">
                <legend>Custom Groups <label><input type='checkbox' class="allcheck" name="allgroups" value='outdata'>all&nbsp;</label></legend>
                <div id="customtree" name="selCust" class="seltree"></div>
              </fieldset>
            </div>
          </td>
        </div>
        </tr>
               </tbody>
            </table>
      <input type="hidden" name=entitle value="0"><br>
            <input type="submit" style="font-weight: bold" name="Report" value="Generate Report" alt="Generate Report">
            </td>
        </tr>
        </tbody>
    </table>
    </form>
</center>

_MARKER_

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
