use strict;
use warnings;

use Xorux_lib;

use CGI::Carp qw(fatalsToBrowser);
use Time::Local;
use POSIX qw(mktime strftime);
use Data::Dumper;
require PDF;
use PowerDataWrapper;
use Overview;
use XoruxEdition;

my $acl;

if ( $ENV{HTTP_XORUX_APP} && $ENV{HTTP_XORUX_APP} eq "Xormon" ) {
  require ACLx;
  $acl = ACLx->new();
}
else {
  require ACL;
  $acl = ACL->new();
}

my ( $SERV, $CONF ) = PowerDataWrapper::init();
my @graph_png_files;
#
# basic variables
#
RRDp::start "$ENV{RRDTOOL}";
my $basedir = $ENV{INPUTDIR} || Xorux_lib::error("INPUTDIR in not defined!") && exit;
my $webdir  = $ENV{WEBDIR} ||= "$basedir/www";
my $wrkdir  = "$basedir/data";
my $tmpdir  = "$basedir/tmp";
my $bindir  = "$basedir/bin";

#eval (require "$bindir/reporter.pl");

my $table_width = "900px";

my ( $sunix, $eunix );

sub getURLparams {
  my ( $buffer, $PAR );

  if ( defined $ENV{'REQUEST_METHOD'} ) {
    if ( lc $ENV{'REQUEST_METHOD'} eq "post" ) {
      read( STDIN, $buffer, $ENV{'CONTENT_LENGTH'} );
    }
    else {
      $buffer = $ENV{'QUERY_STRING'};
    }

    $PAR = Xorux_lib::parse_url_params($buffer);

    return $PAR;
  }
  else {
    return 0;
  }
}

my $params = getURLparams();

if ( $params->{format} ne "pdf" ) {
  print "Content-type: text/html\n\n";
  print "<center>";
}

#
# set report time range
#
$eunix = "";
$sunix = "";

if ( exists $params->{timerange} ) {
  ( $sunix, $eunix ) = set_report_timerange( $params->{timerange} );
  my $diff = $eunix - $sunix;
}
elsif ( exists $params->{sunix} && exists $params->{eunix} ) {
  $sunix = $params->{sunix};
  $eunix = $params->{eunix};
}
else {
  Xorux_lib::error( "Cannot set report timerange! QUERY_STRING=''  $!" . __FILE__ . ":" . __LINE__ ) && exit;
}

if ( $params->{srctype} && $params->{platform} && ( lc( $params->{platform} ) eq "power" || lc( $params->{platform} ) eq "ibmi" ) ) {
  my $agent = 0;
  if ( $params->{srctype} eq "server" ) {
    my $interfaces_available = {};
    $interfaces_available = Xorux_lib::read_json("$basedir/tmp/restapi/servers_interface_ind.json") if ( -e "$basedir/tmp/restapi/servers_interface_ind.json" );

    if ( $params->{format} eq "pdf" ) {
      if (length(premium()) != 6){
        print "Content-type: text/html\n";
        print "Content-Disposition:attachment;filename=Premium_support.pdf\n\n";

        open( my $file, "<$webdir/Premium_support_LPAR2RRD.pdf" ) || Xorux_lib::error( "Couldn't open file $webdir/Premium_support.pdf $!" . __FILE__ . ":" . __LINE__ ) && exit;
        binmode $file;
        while (<$file>) {
          print $_;
        }
        close($file);
        exit;
      }

      my $pdf_data;

      my $server        = $params->{source};
      my $uid           = PowerDataWrapper::get_item_uid( { type => "SERVER", label => $server } );
      my $hmc_uid       = PowerDataWrapper::get_server_parent($uid);
      my $hmc_label     = PowerDataWrapper::get_label( "HMC", $hmc_uid );
      my $rrd_file_path = "$wrkdir/$server/$hmc_label/";

      my $env;
      $env->{servername}    = $server;
      $env->{serveruid}     = $uid;
      $env->{hmcname}       = $hmc_label;
      $env->{hmcuid}        = $hmc_uid;
      $env->{rrd_file_path} = $rrd_file_path;

      $pdf_data = createServerPDF( $uid, $pdf_data, $interfaces_available, $env );

      my $time     = time;
      my $pdf_file = "overview-server-$server-$hmc_label-$$-$time.pdf";
      my $tmp_file = "/tmp/overview_server-$server-$hmc_label-$$-$time-tmp.pdf";

      #print Dumper $pdf_data;
      PDF::createPDF( $tmp_file, $pdf_data );
      remove_graphs();

      if ( -f $tmp_file ) {
        print "Content-type: text/html\n";
        print "Content-Disposition:attachment;filename=$pdf_file\n\n";

        open( my $file, "<$tmp_file" ) || Xorux_lib::error( "Couldn't open file $tmp_file $!" . __FILE__ . ":" . __LINE__ ) && exit;
        binmode $file;
        while (<$file>) {
          print $_;
        }
        close($file);
        unlink($tmp_file);    #unlink when pdf already delivered through gui
      }
      else {
        Xorux_lib::error( "Something wrong, PDF file '$tmp_file' has not been created successfully... $!" . __FILE__ . ":" . __LINE__ ) && exit;
      }

      exit(0);
    }

    #identify server, get uid, parent hmc, rrd paths etc.
    my $server = $params->{source};
    my $uid    = PowerDataWrapper::get_item_uid( { type => "SERVER", label => $server } );

    #test ACL
    my $test_acl = 1;    # on some occasion -> do not test
    my $aclitem;
    my $acl_hw_type = "POWER";
    my $acl_item_id = $uid;
    $aclitem = { hw_type => $acl_hw_type, item_id => $acl_item_id, match => 'granted' };

    if ( $ENV{HTTP_XORUX_APP} && $ENV{HTTP_XORUX_APP} eq "Xormon" ) {
      if ( $test_acl && !$acl->isGranted($aclitem) ) {
        $aclitem->{label} = $server;
        my $str = join( ', ', map {"$_=>$aclitem->{$_}"} keys %{$aclitem} );
        print "<p> Not allowed item $server in acl at " . __FILE__ . ":" . __LINE__ . "</p>\n";
        exit(1);
      }
    }
    else {
      if ( !$acl->canShow( "POWER", "SERVER", $server ) ) {
        print "<p> Not allowed item $server in acl at " . __FILE__ . ":" . __LINE__ . "</p>\n";
        exit(1);
      }
    }

    my $hmc_uid       = PowerDataWrapper::get_server_parent($uid);
    my $hmc_label     = PowerDataWrapper::get_label( "HMC", $hmc_uid );
    my $rrd_file_path = "$wrkdir/$server/$hmc_label/";
    my $file_pth      = "$wrkdir/$server/*/";

    #get data from rrds
    my @pool_data     = @{ Overview::get_something( $rrd_file_path, "pool",     $file_pth, "pool.rrm", $params ) };
    my @pool_max_data = @{ Overview::get_something( $rrd_file_path, "pool-max", $file_pth, "pool.xrm", $params ) };

    my @pool_total_data     = @{ Overview::get_something( $rrd_file_path, "pool-total",     $file_pth, "pool_total.rrt", $params ) };
    my @pool_total_max_data = @{ Overview::get_something( $rrd_file_path, "pool-total-max", $file_pth, "pool_total.rxm", $params ) };

    my @mem_data     = @{ Overview::get_something( $rrd_file_path, "mem",     $file_pth, "mem.rrm", $params ) };
    my @mem_max_data = @{ Overview::get_something( $rrd_file_path, "mem-max", $file_pth, "mem.rrm", $params ) };

    if (!defined $params->{sunix}) { $params->{sunix} = 0;}
    if (!defined $params->{eunix}) { $params->{eunix} = 0;}

    print "<a class='pdffloat savetofile' href='/lpar2rrd-cgi/overview.sh?platform=power&source=$params->{source}&srctype=$params->{srctype}&timerange=$params->{timerange}&sunix=$params->{sunix}&eunix=$params->{eunix}&format=pdf' title='PDF' style='position: fixed; top: 70px; right: 16px;'><img src='css/images/pdf.png'></a>";
    print "<h4>Configuration (current)</h4>";
    print "<table class=\"tablesorter tablesorter-ice nofilter\" style=\"width:$table_width\">\n";
    print "<thead>\n";
    print "<tr>\n";
    print "  <th class='sortable'>Metric</th>\n";
    print "  <th class='sortable'>Value</th>\n";
    print "</tr>\n";
    print "</thead>\n";
    print "<tbody>\n";

    my $conf_metrics_dictionary = {
      "SerialNumber"                         => "Serial Number",
      "ConfigurableSystemProcessorUnits"     => "Configurable System Processor Units",
      "InstalledSystemProcessorUnits"        => "Installed System Processor Units",
      "CurrentAvailableSystemProcessorUnits" => "Current Available System Processor Units",
      "ConfigurableSystemMemory"             => "Configurable System Memory",
      "InstalledSystemMemory"                => "Installed System Memory",
      "CurrentAvailableSystemMemory"         => "Current Available System Memory",
      "MemoryUsedByHypervisor"               => "Memory Used By Hypervisor"
    };
    my $conf_metrics = [
      "SerialNumber",
      "ConfigurableSystemProcessorUnits",
      "InstalledSystemProcessorUnits",
      "CurrentAvailableSystemProcessorUnits",
      "ConfigurableSystemMemory",
      "InstalledSystemMemory",
      "CurrentAvailableSystemMemory",
      "MemoryUsedByHypervisor"
    ];

    if ( $ENV{DEMO} ) { $uid = "371933c39f93b112d4088aba69e9933c"; }

    print "<tr>\n";
    print "<td align=\"left\"> Model - machine type </td>\n";
    if ( defined $CONF->{servers}{$uid}{Model} && defined $CONF->{servers}{$uid}{MachineType} ) {
      print "<td align=\"left\"> $CONF->{servers}{$uid}{Model}-$CONF->{servers}{$uid}{MachineType} </td>\n" if ( defined $CONF->{servers}{$uid}{Model} && defined $CONF->{servers}{$uid}{MachineType} );
    }
    else {
      print "<td align=\"left\">  </td>\n";
    }
    print "</tr>\n";
    foreach my $conf_metric ( @{$conf_metrics} ) {
      my $metric_label = ucfirst( lc( $conf_metrics_dictionary->{$conf_metric} ) );
      if ( !defined $CONF->{servers}{$uid}{$conf_metric} || $CONF->{servers}{$uid}{$conf_metric} eq "not defined" ) { next; }
      print "<tr>\n";
      print "<td align=\"left\"> $metric_label</th>\n";
      if ( defined $CONF->{servers}{$uid}{$conf_metric} ) {
        if ( $metric_label =~ m/[mM]emory/ ) {    #print memory in GB
          my $value_mem = sprintf( "%.0f", $CONF->{servers}{$uid}{$conf_metric} / 1000 );    #to GB
          $value_mem = "$value_mem GB";
          print "<td align=\"left\"> $value_mem </th>\n";
        }
        else {                                                                               #standard
          print "<td align=\"left\"> $CONF->{servers}{$uid}{$conf_metric} </th>\n";
        }
      }
      else {
        print "<td align=\"left\"> not defined</th>\n";
      }
      print "</tr>\n";
    }
    print "</tbody></table>";

    #end configuration

    #performance table
    print "<h4>Performance</h4>";
    print "<table class=\"tablesorter tablesorter-ice nofilter\" style=\"width:$table_width\">\n";
    print "<thead>\n";
    print "<tr>\n";
    print "  <th class='sortable'>$server</th>\n";
    print "  <th class='sortable'>average</th>\n";
    print "  <th class='sortable'>maximum</th>\n";
    print "</tr>\n";
    print "</thead><tbody>\n";

    my $mem_avg = defined $mem_data[0]     ? sprintf( "%.0f", $mem_data[0] )     : "";
    my $mem_max = defined $mem_max_data[0] ? sprintf( "%.0f", $mem_max_data[0] ) : "";

    my $cpu_avg = defined $pool_data[0]     ? sprintf( "%.1f", $pool_data[0] )     : "";
    my $cpu_max = defined $pool_max_data[0] ? sprintf( "%.1f", $pool_max_data[0] ) : "";

    my $cpu_total_avg = defined $pool_total_data[0]     ? sprintf( "%.1f", $pool_total_data[0] )     : "";
    my $cpu_total_max = defined $pool_total_max_data[0] ? sprintf( "%.1f", $pool_total_max_data[0] ) : "";

    print "<TR>
         <TD><B>CPU Total [Cores]</B></TD>
          <TD align=\"left\">$cpu_total_avg</TD>
          <TD align=\"left\">$cpu_total_max</TD>
         </TR>
         <TR>
         <TD><B>CPU Pool [Cores]</B></TD>
          <TD align=\"left\">$cpu_avg</TD>
          <TD align=\"left\">$cpu_max</TD>
         </TR>
         <TR>
         <TD><B>Memory Allocated [GB]</B></TD>
          <TD align=\"left\">$mem_avg</TD>
          <TD align=\"left\">$mem_max</TD>
         </TR>\n";
    print "</tr></tbody></table>";

    #check if there is a active shared pool on the $uid server
    my $shp_ok = 0;
    foreach my $shp_uid ( keys %{ $CONF->{pools} } ) {
      if ( $CONF->{pools}{$shp_uid}{parent} eq $uid && $CONF->{pools}{$shp_uid}{AvailableProcUnits} ) {
        $shp_ok = 1;
        last;
      }
    }

    #shared cpu pools performance if shared pools present on the server
    if ($shp_ok) {
      print "<table class=\"tablesorter tablesorter-ice nofilter\" style=\"width:$table_width\">\n";
      print "<thead>\n";
      print "<tr>\n";
      print "  <th class='sortable'>Shared CPU Pools [Cores]</th>\n";
      print "  <th class='sortable'>average</th>\n";
      print "  <th class='sortable'>maximum</th>\n";
      print "</tr>\n";
      print "</thead><tbody>\n";

      foreach my $shp_uid ( keys %{ $CONF->{pools} } ) {

        if ( $CONF->{pools}{$shp_uid}{parent} ne $uid || !$CONF->{pools}{$shp_uid}{AvailableProcUnits} ) {    #skip shpools with no processors (no lpars) and the onen that doesn't belong to the $uid server
          next;
        }

        my $data     = Overview::get_something( $rrd_file_path, "shpool-cpu",     $file_pth, "$CONF->{pools}{$shp_uid}{label}.rrm", $params );
        my $data_max = Overview::get_something( $rrd_file_path, "shpool-cpu-max", $file_pth, "$CONF->{pools}{$shp_uid}{label}.xrm", $params );

        my $cpu_shpool_avg = defined $data->[0]     ? sprintf( "%.1f", $data->[0] )     : "";
        my $cpu_shpool_max = defined $data_max->[0] ? sprintf( "%.1f", $data_max->[0] ) : "";

        #print "<pre> $rrd_file_path, shpool,     $file_pth, $CONF->{pools}{$shp_uid}{label}.rrm  </pre>\n";
        my $metrics = {
          "cpu" => "CPU",
        };

        print "<TD><B>$CONF->{pools}{$shp_uid}{name}</B></TD>";
        print "<TD align=\"left\">$cpu_shpool_avg</TD>";
        print "<TD align=\"left\">$cpu_shpool_max</TD>";
        print "</TR>\n";
      }
      print "</tr></tbody></table>";
    }

    #which interfaces are available at particular server
    #graphs
    if ( $ENV{DEMO} ) {
      $hmc_label = "hmc1";
    }
    print "<table>";

    #push ( @graph_strings, "host=$hmc_label&server=$server&item=pool-total&lpar=pool&sunix=$sunix&eunix=$eunix&type_sam=m&detail=5&overview_power=1");
    #push ( @graph_strings, "host=$hmc_label&server=$server&item=pool-total-max&lpar=pool&sunix=$sunix&eunix=$eunix&type_sam=m&detail=5&overview_power=1");
    #push ( @graph_strings, "host=$hmc_label&server=$server&item=pool&lpar=pool&sunix=$sunix&eunix=$eunix&type_sam=m&overview_power=1");
    #push ( @graph_strings, "host=$hmc_label&server=$server&item=pool-max&lpar=pool&sunix=$sunix&eunix=$eunix&type_sam=m&overview_power=1");
    #push ( @graph_strings, "host=$hmc_label&server=$server&lpar=cod&item=memalloc&time=d&type_sam=m&detail=5&sunix=$sunix&eunix=$eunix&overview_power=1");
    #push ( @graph_strings, "host=$hmc_label&server=$server&lpar=cod&item=memaggreg&time=d&type_sam=m&detail=5&sunix=$sunix&eunix=$eunix&overview_power=1");
    #push ( @graph_strings, "host=$hmc_label&server=$server&lpar=pool-multi&item=lparagg&time=d&type_sam=m&detail=5&sunix=$sunix&eunix=$eunix&overview_power=1");

    print_graph("host=$hmc_label&server=$server&item=pool-total&lpar=pool&sunix=$sunix&eunix=$eunix&type_sam=m&detail=5&overview_power=1");
    print_graph("host=$hmc_label&server=$server&item=pool-total-max&lpar=pool&sunix=$sunix&eunix=$eunix&type_sam=m&detail=5&overview_power=1");
    print_graph("host=$hmc_label&server=$server&item=pool&lpar=pool&sunix=$sunix&eunix=$eunix&type_sam=m&overview_power=1");
    print_graph("host=$hmc_label&server=$server&item=pool-max&lpar=pool&sunix=$sunix&eunix=$eunix&type_sam=m&overview_power=1");
    print_graph("host=$hmc_label&server=$server&lpar=cod&item=memalloc&time=d&type_sam=m&detail=5&sunix=$sunix&eunix=$eunix&overview_power=1");
    print_graph("host=$hmc_label&server=$server&lpar=cod&item=memaggreg&time=d&type_sam=m&detail=5&sunix=$sunix&eunix=$eunix&overview_power=1");
    print_graph("host=$hmc_label&server=$server&lpar=pool-multi&item=lparagg&time=d&type_sam=m&detail=5&sunix=$sunix&eunix=$eunix&overview_power=1");

    if ( $interfaces_available->{$server}{lan} ) {
      print_graph("host=$hmc_label&server=$server&lpar=lan-totals&item=power_lan_data&time=d&type_sam=m&detail=5&sunix=$sunix&eunix=$eunix&overview_power=1");
      print_graph("host=$hmc_label&server=$server&lpar=lan-totals&item=power_lan_io&time=d&type_sam=m&detail=5&sunix=$sunix&eunix=$eunix&overview_power=1");
    }

    if ( $interfaces_available->{$server}{san} ) {
      print_graph("host=$hmc_label&server=$server&lpar=san-totals&item=power_san_data&time=d&type_sam=m&detail=5&sunix=$sunix&eunix=$eunix&overview_power=1");
      print_graph("host=$hmc_label&server=$server&lpar=san-totals&item=power_san_io&time=d&type_sam=m&detail=5&sunix=$sunix&eunix=$eunix&overview_power=1");
    }

    if ( $interfaces_available->{$server}{sas} ) {
      print_graph("host=$hmc_label&server=$server&lpar=sas-totals&item=power_sas_data&time=d&type_sam=m&detail=5&sunix=$sunix&eunix=$eunix&overview_power=1");
      print_graph("host=$hmc_label&server=$server&lpar=sas-totals&item=power_sas_io&time=d&type_sam=m&detail=5&sunix=$sunix&eunix=$eunix&overview_power=1");
    }

    if ( $interfaces_available->{$server}{sri} ) {
      print_graph("host=$hmc_label&server=$server&lpar=sri-totals&item=power_sri_data&time=d&type_sam=m&detail=5&sunix=$sunix&eunix=$eunix&overview_power=1");
      print_graph("host=$hmc_label&server=$server&lpar=sri-totals&item=power_sri_io&time=d&type_sam=m&detail=5&sunix=$sunix&eunix=$eunix&overview_power=1");
    }

    if ( $interfaces_available->{$server}{hea} ) {
      print_graph("host=$hmc_label&server=$server&lpar=hea-totals&item=power_hea_data&time=d&type_sam=m&detail=5&sunix=$sunix&eunix=$eunix&overview_power=1");
      print_graph("host=$hmc_label&server=$server&lpar=hea-totals&item=power_hea_io&time=d&type_sam=m&detail=5&sunix=$sunix&eunix=$eunix&overview_power=1");
    }
    print "</table>";
  }

  elsif ( $params->{srctype} eq "lpar" ) {
    if ( $params->{format} eq "pdf" ) {

      if (length(premium()) != 6){
        print "Content-type: text/html\n";
        print "Content-Disposition:attachment;filename=Premium_support.pdf\n\n";

        open( my $file, "<$webdir/Premium_support_LPAR2RRD.pdf" ) || Xorux_lib::error( "Couldn't open file $webdir/Premium_support.pdf $!" . __FILE__ . ":" . __LINE__ ) && exit;
        binmode $file;
        while (<$file>) {
          print $_;
        }
        close($file);
        exit;
      }

      my $vm_label = $params->{source};
      my $uid      = PowerDataWrapper::get_item_uid( { type => "VM", label => $vm_label } );

      #test ACL
      my $test_acl = 1;    # on some occasion -> do not test
      my $aclitem;
      my $acl_hw_type = "POWER";
      my $acl_item_id = $uid;
      $aclitem = { hw_type => $acl_hw_type, item_id => $acl_item_id, match => 'granted' };

      #      if ( $ENV{HTTP_XORUX_APP} && $ENV{HTTP_XORUX_APP} eq "Xormon" ) {
      #        if ( $test_acl && !$acl->isGranted( $aclitem ) ) {
      #          $aclitem->{label} = $vm_label;
      #          my $str = join(', ', map { "$_=>$aclitem->{$_}" } keys %{ $aclitem });
      #          print "<p> Not allowed item $vm_label in acl at " .  __FILE__ . ":" . __LINE__ . "</p>\n";
      #          exit(1);
      #        }
      #      }
      #      else {
      #        if ( !$acl->canShow( "POWER", "VM", $vm_label ) ) {
      #          print "<p> Not allowed item $vm_label in acl at " .  __FILE__ . ":" . __LINE__ . "</p>\n";
      #          exit( 1 );
      #        }
      #      }

      my $server_uid    = PowerDataWrapper::get_vm_parent($uid);
      my $server        = PowerDataWrapper::get_label( "SERVER", $server_uid );
      my $hmc_uid       = PowerDataWrapper::get_server_parent($server_uid);
      my $hmc_label     = PowerDataWrapper::get_label( "HMC", $hmc_uid );
      my $rrd_file_path = "$wrkdir/$server/$hmc_label/";
      my $file_pth      = "$wrkdir/$server/*/";

      my $env;
      $env->{vmname}        = $vm_label;
      $env->{vmuid}         = $uid;
      $env->{servername}    = $server;
      $env->{serveruid}     = $server_uid;
      $env->{hmcname}       = $hmc_label;
      $env->{hmcuid}        = $hmc_uid;
      $env->{rrd_file_path} = $rrd_file_path;
      $env->{file_path}     = $file_pth;

      #which interfaces are available at particular server
      my $interfaces_available;
      $interfaces_available = Xorux_lib::read_json("$basedir/tmp/restapi/servers_interface_ind.json") if ( -e "$basedir/tmp/restapi/servers_interface_ind.json" );

      if ( $ENV{DEMO} ) {
        if ( $params->{source} =~ m/aix[01][0-9]/ || $params->{source} =~ m/vio[01][0-9]/ || $params->{source} =~ m/lnx[01][0-9]/ ) {
          $server    = "Power-E880";
          $hmc_label = "hmc1";
        }
        else {
          $server    = "Power770";
          $hmc_label = "hmc1";
        }
      }

      #get data from rrdss
      my @lpar_data_avg = @{ Overview::get_something( $rrd_file_path, "lpar-cpu-avg", $file_pth, "$vm_label.rrm", $params ) };
      my @lpar_data_max = @{ Overview::get_something( $rrd_file_path, "lpar-cpu-max", $file_pth, "$vm_label.rrm", $params ) };

      my @lpar_mem_data_avg = @{ Overview::get_something( $rrd_file_path, "lpar-mem-avg", $file_pth, "$vm_label.rsm", $params ) };
      my @lpar_mem_data_max = @{ Overview::get_something( $rrd_file_path, "lpar-mem-max", $file_pth, "$vm_label.rsm", $params ) };

      my $lpar_mem_gb_avg = defined $lpar_mem_data_avg[0] ? sprintf( "%.0f", $lpar_mem_data_avg[0] / 1000 ) : "";
      my $lpar_mem_gb_max = defined $lpar_mem_data_max[0] ? sprintf( "%.0f", $lpar_mem_data_max[0] / 1000 ) : "";

      my $lpar_cpu_avg = defined $lpar_data_avg[0] ? sprintf( "%.1f", $lpar_data_avg[0] ) : "";
      my $lpar_cpu_max = defined $lpar_data_max[0] ? sprintf( "%.1f", $lpar_data_max[0] ) : "";

      $env->{lpar_data_avg}     = $lpar_cpu_avg;
      $env->{lpar_data_max}     = $lpar_cpu_max;
      $env->{lpar_mem_data_avg} = $lpar_mem_gb_avg;
      $env->{lpar_mem_data_max} = $lpar_mem_gb_max;

      my $pdf_data;

      $pdf_data = createLparPDF( $uid, $pdf_data, $interfaces_available, $env );

      my $time     = time;
      my $pdf_file = "overview-lpar-$vm_label-$hmc_label-$$-$time.pdf";
      my $tmp_file = "/tmp/overview_lpar-$vm_label-$hmc_label-$$-$time-tmp.pdf";

      #print Dumper $pdf_data;
      PDF::createPDF( $tmp_file, $pdf_data );
      remove_graphs();

      if ( -f $tmp_file ) {
        print "Content-type: text/html\n";
        print "Content-Disposition:attachment;filename=$pdf_file\n\n";

        open( my $file, "<$tmp_file" ) || Xorux_lib::error( "Couldn't open file $tmp_file $!" . __FILE__ . ":" . __LINE__ ) && exit;
        binmode $file;
        while (<$file>) {
          print $_;
        }
        close($file);
        unlink($tmp_file);    #unlink when pdf already delivered through gui
      }
      else {
        Xorux_lib::error( "Something wrong, PDF file '$tmp_file' has not been created successfully... $!" . __FILE__ . ":" . __LINE__ ) && exit;
      }

      exit(0);
    }

    #identify server, get uid, parent hmc, rrd paths etc.
    my $vm_label = $params->{source};
    my $uid      = PowerDataWrapper::get_item_uid( { type => "VM", label => $vm_label } );

    #test ACL
    my $test_acl = 1;    # on some occasion -> do not test
    my $aclitem;
    my $acl_hw_type = "POWER";
    my $acl_item_id = $uid;
    $aclitem = { hw_type => $acl_hw_type, item_id => $acl_item_id, match => 'granted' };
    if ( $ENV{HTTP_XORUX_APP} && $ENV{HTTP_XORUX_APP} eq "Xormon" ) {
      if ( $test_acl && !$acl->isGranted($aclitem) ) {
        $aclitem->{label} = $vm_label;
        my $str = join( ', ', map {"$_=>$aclitem->{$_}"} keys %{$aclitem} );
        print "<p> Not allowed item $vm_label in acl at " . __FILE__ . ":" . __LINE__ . "</p>\n";
        exit(1);
      }
    }
    else {
      if ( !$acl->canShow( "POWER", "VM", $vm_label ) ) {
        print "<p> Not allowed item $vm_label in acl at " . __FILE__ . ":" . __LINE__ . "</p>\n";
        exit(1);
      }
    }

    my $server_uid    = PowerDataWrapper::get_vm_parent($uid);
    my $server        = PowerDataWrapper::get_label( "SERVER", $server_uid );
    my $hmc_uid       = PowerDataWrapper::get_server_parent($server_uid);
    my $hmc_label     = PowerDataWrapper::get_label( "HMC", $hmc_uid );
    my $rrd_file_path = "$wrkdir/$server/$hmc_label/";
    my $file_pth      = "$wrkdir/$server/*/";
    if ( $ENV{DEMO} ) {
      if ( $params->{source} =~ m/aix[01][0-9]/ || $params->{source} =~ m/vio[01][0-9]/ || $params->{source} =~ m/lnx[01][0-9]/ ) {
        $server    = "Power-E880";
        $hmc_label = "hmc1";
      }
      else {
        $server    = "Power770";
        $hmc_label = "hmc1";
      }
    }

    #get data from rrdss
    my @lpar_data_avg = @{ Overview::get_something( $rrd_file_path, "lpar-cpu-avg", $file_pth, "$vm_label.rrm", $params ) };
    my @lpar_data_max = @{ Overview::get_something( $rrd_file_path, "lpar-cpu-max", $file_pth, "$vm_label.rrm", $params ) };

    my @lpar_mem_data_avg = @{ Overview::get_something( $rrd_file_path, "lpar-mem-avg", $file_pth, "$vm_label.rsm", $params ) };
    my @lpar_mem_data_max = @{ Overview::get_something( $rrd_file_path, "lpar-mem-max", $file_pth, "$vm_label.rsm", $params ) };

    if (!defined $params->{sunix}) { $params->{sunix} = 0;}
    if (!defined $params->{eunix}) { $params->{eunix} = 0;}

    #configuration
    print "<a class='pdffloat savetofile' href='/lpar2rrd-cgi/overview.sh?platform=power&source=$params->{source}&srctype=$params->{srctype}&timerange=$params->{timerange}&sunix=$params->{sunix}&eunix=$params->{eunix}&format=pdf' title='PDF' style='position: fixed; top: 70px; right: 16px;'><img src='css/images/pdf.png'></a>";
    print "<h4>Configuration (current)</h4>";
    print "<table class=\"tablesorter tablesorter-ice nofilter\" style=\"width:$table_width\">\n";
    print "<thead>\n";
    print "<tr>\n";
    print "  <th class='sortable'>Metric</th>\n";
    print "  <th class='sortable'>Value</th>\n";
    print "</tr>\n";
    print "</thead>\n";
    print "<tbody>\n";
    my $conf_metrics_dictionary = {
      "name"                          => "Name",
      "state"                         => "State",
      "curr_sharing_mode"             => "Current sharing mode",
      "CurrentProcessingUnits"        => "Current Processing Units",
      "curr_proc_units"               => "Current Processing Units",
      "curr_procs"                    => "Current Processors",
      "curr_min_procs"                => "Current Minimum Processors",
      "curr_max_procs"                => "Current Maximum Processors",
      "DesiredProcessingUnits"        => "Desired Processing Units",
      "MinimumProcessingUnits"        => "Minimum Processing Units",
      "MaximumProcessingUnits"        => "Maximum Processing Units",
      "CurrentMinimumProcessingUnits" => "Current Minimum Processing Units",
      "curr_min_proc_units"           => "Current Minimum Processing Units",
      "CurrentMaximumProcessingUnits" => "Current Maximum Processing Units",
      "curr_max_proc_units"           => "Current Maximum Processing Units",
      "RuntimeProcessingUnits"        => "Runtime Processing Units",
      "run_proc_units"                => "Runtime Processing Units",
      "CurrentMemory"                 => "Current Memory",
      "curr_mem"                      => "Current Memory",
      "DesiredMemory"                 => "Desired Memory",
      "MinimumMemory"                 => "Minimum Memory",
      "MaximumMemory"                 => "Maximum Memory",
      "CurrentMinimumMemory"          => "Current Minimum Memory",
      "CurrentMaximumMemory"          => "Current Maximum Memory",
      "curr_min_mem"                  => "Current Minimum Memory",
      "curr_max_mem"                  => "Current Maximum Memory",
      "RuntimeMemory"                 => "Runtime Memory",
      "vm_env"                        => "Vm env",
      "os_version"                    => "OS version"
    };

    my $conf_metrics = [
      "state",
      "CurrentProcessingUnits",
      "curr_proc_units",
      "curr_procs",
      "curr_min_procs",
      "curr_max_procs",
      "curr_sharing_mode",
      "DesiredProcessingUnits",
      "MinimumProcessingUnits",
      "MaximumProcessingUnits",
      "CurrentMinimumProcessingUnits",
      "curr_min_proc_units",
      "CurrentMaximumProcessingUnits",
      "curr_max_proc_units",
      "RuntimeProcessingUnits",
      "run_proc_units",
      "CurrentMemory",
      "curr_mem",
      "DesiredMemory",
      "MinimumMemory",
      "MaximumMemory",
      "CurrentMinimumMemory",
      "curr_min_mem",
      "CurrentMaximumMemory",
      "curr_max_mem",
      "RuntimeMemory",
      "vm_env",
      "os_version",
    ];

    #print "<pre>\n";
    #print Dumper $CONF->{vms};
    #print "</pre>\n";

    foreach my $conf_metric ( @{$conf_metrics} ) {
      my $metric_label = ucfirst( lc( $conf_metrics_dictionary->{$conf_metric} ) );
      print "<tr>\n";
      if ( defined $CONF->{vms}{$uid}{$conf_metric} ) {
        print "<td align=\"left\"> $metric_label </th>\n";
        if ( $metric_label =~ m/[mM]emory/ ) {
          my $value_mem = sprintf( "%.0f", $CONF->{vms}{$uid}{$conf_metric} / 1000 );
          $value_mem = "$value_mem GB";
          print "<td align=\"left\"> $value_mem</th>\n";
        }
        else {
          print "<td align=\"left\"> $CONF->{vms}{$uid}{$conf_metric} </th>\n";
        }
      }
      else {
        #print   "<td align=\"left\"> not defined</th>\n";
      }
      print "</tr>\n";
    }
    print "</tbody></table>";

    #end configuration

    #performance table
    print "<h4>Performance</h4>";

    print "<table class=\"tablesorter tablesorter-ice nofilter\" style=\"width:$table_width\">\n";
    print "<thead>\n";
    print "<tr>\n";
    print "  <th class='sortable'>$server</th>\n";
    print "  <th class='sortable'>average</th>\n";
    print "  <th class='sortable'>maximum</th>\n";
    print "</tr>\n";
    print "</thead><tbody>\n";

    my $lpar_mem_gb_avg = defined $lpar_mem_data_avg[0] ? sprintf( "%.0f", $lpar_mem_data_avg[0] / 1000 ) : "";
    my $lpar_mem_gb_max = defined $lpar_mem_data_max[0] ? sprintf( "%.0f", $lpar_mem_data_max[0] / 1000 ) : "";

    my $lpar_cpu_avg = defined $lpar_data_avg[0] ? sprintf( "%.1f", $lpar_data_avg[0] ) : "";
    my $lpar_cpu_max = defined $lpar_data_max[0] ? sprintf( "%.1f", $lpar_data_max[0] ) : "";

    print "<TR>
         <TD><B>CPU [Cores]</B></TD>
          <TD align=\"left\">$lpar_cpu_avg</TD>
          <TD align=\"left\">$lpar_cpu_max</TD>
         </TR>
         <TR>
         <TD><B>Memory Allocated [GB]</B></TD>
          <TD align=\"left\">$lpar_mem_gb_avg</TD>
          <TD align=\"left\">$lpar_mem_gb_max</TD>
         </TR>\n";

    print "</tr></tbody></table>";

    #which interfaces are available at particular server
    my $interfaces_available;
    $interfaces_available = Xorux_lib::read_json("$basedir/tmp/restapi/servers_interface_ind.json") if ( -e "$basedir/tmp/restapi/servers_interface_ind.json" );

    #graphs
    if ( $ENV{DEMO} ) {
      $hmc_label = "hmc1";
    }
    print "<table>";
    print_graph("host=$hmc_label&server=$server&item=lpar&lpar=$vm_label&sunix=$sunix&eunix=$eunix&type_sam=m&overview_power=1");
    if ( -e "$basedir/data/$server/$hmc_label/$vm_label/cpu.mmm" ) {
      print_graph("host=$hmc_label&server=$server&item=oscpu&lpar=$vm_label&sunix=$sunix&eunix=$eunix&type_sam=m&overview_power=1&detail=22");
      print_graph("host=$hmc_label&server=$server&item=queue_cpu&lpar=$vm_label&sunix=$sunix&eunix=$eunix&type_sam=m&overview_power=1&detail=22");
      print_graph("host=$hmc_label&server=$server&item=jobs&lpar=$vm_label&sunix=$sunix&eunix=$eunix&type_sam=m&overview_power=1&detail=22");
      print_graph("host=$hmc_label&server=$server&item=mem&lpar=$vm_label&sunix=$sunix&eunix=$eunix&type_sam=m&overview_power=1&detail=22");
      print_graph("host=$hmc_label&server=$server&item=pg1&lpar=$vm_label&sunix=$sunix&eunix=$eunix&type_sam=m&overview_power=1&detail=22");
      print_graph("host=$hmc_label&server=$server&item=pg2&lpar=$vm_label&sunix=$sunix&eunix=$eunix&type_sam=m&overview_power=1&detail=22");
      print_graph("host=$hmc_label&server=$server&item=lan&lpar=$vm_label&sunix=$sunix&eunix=$eunix&type_sam=m&overview_power=1&detail=22");
      print_graph("host=$hmc_label&server=$server&item=san1&lpar=$vm_label&sunix=$sunix&eunix=$eunix&type_sam=m&overview_power=1&detail=22");
      print_graph("host=$hmc_label&server=$server&item=san2&lpar=$vm_label&sunix=$sunix&eunix=$eunix&type_sam=m&overview_power=1&detail=22");
      print_graph("host=$hmc_label&server=$server&item=san_resp&lpar=$vm_label&sunix=$sunix&eunix=$eunix&type_sam=m&overview_power=1&detail=22");
    }

    #print STDERR "Does \"$basedir/data/$server/$hmc_label/$vm_label--AS400--/JOB || $basedir/data/$server/$hmc_label/$vm_label--AS400--/DSK\" exits?\n";
    if ( -d "$basedir/data/$server/$hmc_label/$vm_label--AS400--/JOB" || -d "$basedir/data/$server/$hmc_label/$vm_label--AS400--/DSK" ) {
      $agent = 1;
      print_graph("host=$hmc_label&server=$server&item=disk_io&lpar=$vm_label&sunix=$sunix&eunix=$eunix&type_sam=m&overview_power=1&detail=22");
      print_graph("host=$hmc_label&server=$server&item=disk_busy&lpar=$vm_label&sunix=$sunix&eunix=$eunix&type_sam=m&overview_power=1&detail=22");
      print_graph("host=$hmc_label&server=$server&item=S0200ASPJOB&lpar=$vm_label&sunix=$sunix&eunix=$eunix&type_sam=m&overview_power=1&detail=22");
      print_graph("host=$hmc_label&server=$server&item=threads&lpar=$vm_label&sunix=$sunix&eunix=$eunix&type_sam=m&overview_power=1&detail=22");
      print_graph("host=$hmc_label&server=$server&item=faults&lpar=$vm_label&sunix=$sunix&eunix=$eunix&type_sam=m&overview_power=1&detail=22");
      print_graph("host=$hmc_label&server=$server&item=pages&lpar=$vm_label&sunix=$sunix&eunix=$eunix&type_sam=m&overview_power=1&detail=22");
      print_graph("host=$hmc_label&server=$server&item=cap_used&lpar=$vm_label&sunix=$sunix&eunix=$eunix&type_sam=m&overview_power=1&detail=22");
      print_graph("host=$hmc_label&server=$server&item=cap_free&lpar=$vm_label&sunix=$sunix&eunix=$eunix&type_sam=m&overview_power=1&detail=22");
      print_graph("host=$hmc_label&server=$server&item=data_as&lpar=$vm_label&sunix=$sunix&eunix=$eunix&type_sam=m&overview_power=1&detail=22");
      print_graph("host=$hmc_label&server=$server&item=iops_as&lpar=$vm_label&sunix=$sunix&eunix=$eunix&type_sam=m&overview_power=1&detail=22");
      print_graph("host=$hmc_label&server=$server&item=dsk_latency&lpar=$vm_label&sunix=$sunix&eunix=$eunix&type_sam=m&overview_power=1&detail=22") if (length(premium()) != 6);
      print_graph("host=$hmc_label&server=$server&item=data_ifcb&lpar=$vm_label&sunix=$sunix&eunix=$eunix&type_sam=m&overview_power=1&detail=22");
    }
    if ( lc( $params->{platform} ) eq "ibmi" && !$agent ) {
      print "<p><b>IBMi agent not installed. For more graphs follow instructions here: <a target=\"_blank\" href=\"https://lpar2rrd.com/as400.php\">https://lpar2rrd.com/as400.php</a></b></p>\n";
    }
    print "</table>";
  }
  else {
    print "<pre>";
    print "not defined srctype\n";
    print Dumper $params;
    print "</pre>";
  }

}

sub print_graph {
  my $link = shift;

  #  print "<a href=\"$link\">text</a>\n";
  print "<tr><td align='center' valign='top'><div><img class='lazy' border='0' data-src='/lpar2rrd-cgi/detail-graph.sh?$link' src='css/images/sloading.gif'></div></td></tr>\n";
}

sub set_report_timerange {
  my $time  = shift;
  my $sunix = 0;
  my $eunix = 0;

  my $day_sec  = 60 * 60 * 24;
  my $act_time = time();
  my ( $act_sec, $act_min, $act_hour, $act_day, $act_month, $act_year, $act_wday, $act_yday, $act_isdst ) = localtime();

  if ( $time eq "prevHour" ) {
    $eunix = mktime( 0, 0, $act_hour, $act_day, $act_month, $act_year );
    $sunix = $eunix - ( 60 * 60 );
  }
  elsif ( $time eq "prevDay" || $time eq "d" ) {
    $eunix = mktime( 0, 0, 0, $act_day, $act_month, $act_year );
    $sunix = $eunix - $day_sec;

    adjust_timerange();
  }
  elsif ( $time eq "prevWeek" || $time eq "w" ) {
    $eunix = mktime( 0, 0, 0, $act_day, $act_month, $act_year );
    $eunix = $eunix - ( ( $act_wday - 1 ) * $day_sec );
    $sunix = $eunix - ( 7 * $day_sec );

    adjust_timerange();
  }
  elsif ( $time eq "prevMonth" || $time eq "m" ) {
    $sunix = mktime( 0, 0, 0, 1, $act_month - 1, $act_year );
    $eunix = mktime( 0, 0, 0, 1, $act_month,     $act_year );

    adjust_timerange();
  }
  elsif ( $time eq "prevYear" || $time eq "y" ) {
    $sunix = mktime( 0, 0, 0, 1, 0, $act_year - 1 );
    $eunix = mktime( 0, 0, 0, 1, 0, $act_year );

    adjust_timerange();
  }
  elsif ( $time eq "lastHour" ) {
    $eunix = $act_time;
    $sunix = $eunix - ( 60 * 60 );
  }
  elsif ( $time eq "lastDay" ) {
    $eunix = $act_time;
    $sunix = $eunix - $day_sec;
  }
  elsif ( $time eq "lastWeek" ) {
    $eunix = $act_time;
    $sunix = $eunix - ( $day_sec * 7 );
  }
  elsif ( $time eq "lastMonth" ) {
    $sunix = mktime( $act_sec, $act_min, $act_hour, $act_day, $act_month - 1, $act_year );
    $eunix = $act_time;
  }
  elsif ( $time eq "lastYear" ) {
    $sunix = mktime( $act_sec, $act_min, $act_hour, $act_day, $act_month, $act_year - 1 );
    $eunix = $act_time;
  }
  else {
    Xorux_lib::error( "Cannot set report timerange! Unsupported time='$time'! $!" . __FILE__ . ":" . __LINE__ ) && exit;
  }

  return ( $sunix, $eunix ) if ( defined $sunix && defined $eunix );
  return ( 1,      1 );
}

sub adjust_timerange {

  # perl <5.12 has got some problems on aix with DST (daylight saving time)
  # sometimes there is one hour difference
  # therefore align the time to midnight again
  if ( $sunix eq "" ) { $sunix = 0; }
  if ( $eunix eq "" ) { $eunix = 0; }
  my ( $s_sec, $s_min, $s_hour, $s_day, $s_month, $s_year, $s_wday, $s_yday, $s_isdst ) = localtime($sunix);
  $sunix = mktime( 0, 0, 0, $s_day, $s_month, $s_year, $s_wday, $s_yday, $s_isdst );
  my ( $e_sec, $e_min, $e_hour, $e_day, $e_month, $e_year, $e_wday, $e_yday, $e_isdst ) = localtime($eunix);
  $eunix = mktime( 0, 0, 0, $e_day, $e_month, $e_year, $e_wday, $e_yday, $e_isdst );

  return 1;
}

### PDF format ###

sub createServerPDF {
  my $uid                  = shift;
  my $pdf_data             = shift;
  my $interfaces_available = shift;
  my $env                  = shift;
  my $server               = $SERV->{$uid};

  my $ov_servername = defined $server->{SystemName} ? $server->{SystemName} : $server->{label};

  push @{ $pdf_data->{content} }, set_PDF_table_text( "header", "center", "", $ov_servername );

  #header
  push @{ $pdf_data->{content} }, set_PDF_table_text( "h2-bold", "center", "", "Configuration" );

  #add configuration table

  my $conf_metrics_dictionary = {
    "SerialNumber"                         => "Serial Number",
    "ConfigurableSystemProcessorUnits"     => "Configurable System Processor Units",
    "InstalledSystemProcessorUnits"        => "Installed System Processor Units",
    "CurrentAvailableSystemProcessorUnits" => "Current Available System Processor Units",
    "ConfigurableSystemMemory"             => "Configurable System Memory",
    "InstalledSystemMemory"                => "Installed System Memory",
    "CurrentAvailableSystemMemory"         => "Current Available System Memory",
    "MemoryUsedByHypervisor"               => "Memory Used By Hypervisor"
  };
  my $conf_metrics = [
    "SerialNumber",
    "ConfigurableSystemProcessorUnits",
    "InstalledSystemProcessorUnits",
    "CurrentAvailableSystemProcessorUnits",
    "ConfigurableSystemMemory",
    "InstalledSystemMemory",
    "CurrentAvailableSystemMemory",
    "MemoryUsedByHypervisor"
  ];
  my $table;
  my $pdf_table;
  my $pdf_table_head;
  foreach my $conf_metric ( @{$conf_metrics} ) {
    if ( defined $CONF->{servers}{$uid}{$conf_metric} ) {
      push @{$table}, [ "$conf_metrics_dictionary->{$conf_metric}" => $CONF->{servers}{$uid}{$conf_metric} ];
    }
  }
  $pdf_table = addComponent( { 'component' => 'table1', 'data' => $table } );
  push @{ $pdf_data->{content} }, $pdf_table;

  my $hmc_uid       = $env->{hmcuid};
  my $hmc_label     = $env->{hmcname};
  my $rrd_file_path = "$wrkdir/$ov_servername/$hmc_label/";
  my $file_pth      = "$wrkdir/$ov_servername/*/";

  #$rrd_file_path =~ s/ /\\ /g;
  #$file_pth =~ s/ /\\ /g;

  #  my $params = {
  #    "srctype" => "server",
  #    "source" => $ov_servername,
  #    "platform" => "power",
  #    "timerange" => "prevDay",
  #    "format" => "html"
  #  };

  #get data from rrds
  my @pool_data     = @{ Overview::get_something( $rrd_file_path, "pool",     $file_pth, "pool.rrm", $params ) };
  my @pool_max_data = @{ Overview::get_something( $rrd_file_path, "pool-max", $file_pth, "pool.xrm", $params ) };

  my @pool_total_data     = @{ Overview::get_something( $rrd_file_path, "pool-total",     $file_pth, "pool_total.rrt", $params ) };
  my @pool_total_max_data = @{ Overview::get_something( $rrd_file_path, "pool-total-max", $file_pth, "pool_total.rxm", $params ) };

  my @mem_data     = @{ Overview::get_something( $rrd_file_path, "mem",     $file_pth, "mem.rrm", $params ) };
  my @mem_max_data = @{ Overview::get_something( $rrd_file_path, "mem-max", $file_pth, "mem.rrm", $params ) };

  #header
  push @{ $pdf_data->{content} }, set_PDF_table_text( "h2-bold", "center", "", "Server" );

  #pool, pool total, mem for the physical server
  my $data;
  $data = {
    "servername"     => "$ov_servername",
    "pool"           => $pool_data[0],
    "pool-max"       => $pool_max_data[0],
    "pool-total"     => $pool_total_data[0],
    "pool-total-max" => $pool_total_max_data[0],
    "mem"            => $mem_data[0],
    "mem-max"        => $mem_max_data[0]
  };
  push @{ $pdf_data->{content} }, set_PDF_table_perf_server($data);

  #header
  push @{ $pdf_data->{content} }, set_PDF_table_text( "h2-bold", "center", "", "Shared CPU Pools" );

  # shared cpu pools
  $data = {};
  foreach my $shp_uid ( keys %{ $CONF->{pools} } ) {

    if ( $CONF->{pools}{$shp_uid}{parent} ne $uid || ( defined $CONF->{pools}{$shp_uid}{AvailableProcUnits} && !$CONF->{pools}{$shp_uid}{AvailableProcUnits} ) ) {    #skip shpools with no processors (no lpars) and the onen that doesn't belong to the $uid server
      next;
    }

    my $shp_data     = Overview::get_something( $rrd_file_path, "shpool-cpu",     $file_pth, "$CONF->{pools}{$shp_uid}{label}.rrm", $params );
    my $shp_data_max = Overview::get_something( $rrd_file_path, "shpool-cpu-max", $file_pth, "$CONF->{pools}{$shp_uid}{label}.xrm", $params );
    my $cpu_shpool_avg = sprintf( "%.1f", $shp_data->[0] );
    my $cpu_shpool_max = sprintf( "%.1f", $shp_data_max->[0] );

    #print Dumper $CONF->{pools};
    $data->{$shp_uid}{conf}    = $CONF->{pools}{$shp_uid};
    $data->{$shp_uid}{cpu_avg} = $cpu_shpool_avg;
    $data->{$shp_uid}{cpu_max} = $cpu_shpool_max;

  }
  push @{ $pdf_data->{content} }, set_PDF_table_perf_shpools($data);

  #header
  push @{ $pdf_data->{content} }, set_PDF_table_text( "h2-bold", "center", "", "Graphs" );

  my @graph_strings;
  my $ov_servername_url = urlencode($ov_servername);
  push( @graph_strings, "host=$hmc_label&server=$ov_servername_url&item=pool-total&lpar=pool&sunix=$sunix&eunix=$eunix&type_sam=m&detail=5&overview_power=1" );
  push( @graph_strings, "host=$hmc_label&server=$ov_servername_url&item=pool-total-max&lpar=pool&sunix=$sunix&eunix=$eunix&type_sam=m&detail=5&overview_power=1" );
  push( @graph_strings, "host=$hmc_label&server=$ov_servername_url&item=pool&lpar=pool&sunix=$sunix&eunix=$eunix&type_sam=m&detail=5&overview_power=1" );
  push( @graph_strings, "host=$hmc_label&server=$ov_servername_url&item=pool-max&lpar=pool&sunix=$sunix&eunix=$eunix&type_sam=m&detail=5&overview_power=1" );
  push( @graph_strings, "host=$hmc_label&server=$ov_servername_url&lpar=cod&item=memalloc&time=d&type_sam=m&detail=5&sunix=$sunix&eunix=$eunix&overview_power=1" );
  push( @graph_strings, "host=$hmc_label&server=$ov_servername_url&lpar=cod&item=memaggreg&time=d&type_sam=m&detail=5&sunix=$sunix&eunix=$eunix&overview_power=1" );
  push( @graph_strings, "host=$hmc_label&server=$ov_servername_url&lpar=pool-multi&item=lparagg&time=d&type_sam=m&detail=5&sunix=$sunix&eunix=$eunix&overview_power=1" );

  if ( $interfaces_available->{$ov_servername}{lan} ) {
    push( @graph_strings, "host=$hmc_label&server=$ov_servername_url&lpar=lan-totals&item=power_lan_data&time=d&type_sam=m&detail=5&sunix=$sunix&eunix=$eunix&overview_power=1" );
    push( @graph_strings, "host=$hmc_label&server=$ov_servername_url&lpar=lan-totals&item=power_lan_io&time=d&type_sam=m&detail=5&sunix=$sunix&eunix=$eunix&overview_power=1" );
  }

  if ( $interfaces_available->{$ov_servername}{san} ) {
    push( @graph_strings, "host=$hmc_label&server=$ov_servername_url&lpar=san-totals&item=power_san_data&time=d&type_sam=m&detail=5&sunix=$sunix&eunix=$eunix&overview_power=1" );
    push( @graph_strings, "host=$hmc_label&server=$ov_servername_url&lpar=san-totals&item=power_san_io&time=d&type_sam=m&detail=5&sunix=$sunix&eunix=$eunix&overview_power=1" );
  }

  if ( $interfaces_available->{$ov_servername}{sas} ) {
    push( @graph_strings, "host=$hmc_label&server=$ov_servername_url&lpar=sas-totals&item=power_sas_data&time=d&type_sam=m&detail=5&sunix=$sunix&eunix=$eunix&overview_power=1" );
    push( @graph_strings, "host=$hmc_label&server=$ov_servername_url&lpar=sas-totals&item=power_sas_io&time=d&type_sam=m&detail=5&sunix=$sunix&eunix=$eunix&overview_power=1" );
  }

  if ( $interfaces_available->{$ov_servername}{sri} ) {
    push( @graph_strings, "host=$hmc_label&server=$ov_servername_url&lpar=sri-totals&item=power_sri_data&time=d&type_sam=m&detail=5&sunix=$sunix&eunix=$eunix&overview_power=1" );
    push( @graph_strings, "host=$hmc_label&server=$ov_servername_url&lpar=sri-totals&item=power_sri_io&time=d&type_sam=m&detail=5&sunix=$sunix&eunix=$eunix&overview_power=1" );
  }

  if ( $interfaces_available->{$ov_servername}{hea} ) {
    push( @graph_strings, "host=$hmc_label&server=$ov_servername_url&lpar=hea-totals&item=power_hea_data&time=d&type_sam=m&detail=5&sunix=$sunix&eunix=$eunix&overview_power=1" );
    push( @graph_strings, "host=$hmc_label&server=$ov_servername_url&lpar=hea-totals&item=power_hea_io&time=d&type_sam=m&detail=5&sunix=$sunix&eunix=$eunix&overview_power=1" );
  }

  my $i = 0;
  foreach my $graph (@graph_strings) {
    my $png_file = "/tmp/temp_file-$i-$$.png";
    $i++;

    #print "$png_file, $graph\n";
    get_img_png( $png_file, $graph );
    if ( -f $png_file ) {

      #$_->{FILE} = $png_file;
      push( @{ $pdf_data->{content} }, set_PDF_img($png_file) );
      push( @graph_png_files,          $png_file );
    }
    else {
      Xorux_lib::error( "PNG file $png_file does not exists! $!" . __FILE__ . ":" . __LINE__ ) && next;
    }
  }
  return $pdf_data;
}

sub createLparPDF {
  my $uid                  = shift;
  my $pdf_data             = shift;
  my $interfaces_available = shift;
  my $env                  = shift;
  my $server               = $SERV->{$uid};

  push @{ $pdf_data->{content} }, set_PDF_table_text( "header", "center", "", "$env->{vmname}" );

  #header
  push @{ $pdf_data->{content} }, set_PDF_table_text( "h2-bold", "center", "", "Configuration" );

  #add configuration table
  my $conf_metrics_dictionary = {
    "name"                          => "Name",
    "state"                         => "State",
    "curr_sharing_mode"             => "Current sharing mode",
    "CurrentProcessingUnits"        => "Current Processing Units",
    "curr_proc_units"               => "Current Processing Units",
    "curr_procs"                    => "Current Processors",
    "curr_min_procs"                => "Current Minimum Processors",
    "curr_max_procs"                => "Current Maximum Processors",
    "DesiredProcessingUnits"        => "Desired Processing Units",
    "MinimumProcessingUnits"        => "Minimum Processing Units",
    "MaximumProcessingUnits"        => "Maximum Processing Units",
    "CurrentMinimumProcessingUnits" => "Current Minimum Processing Units",
    "curr_min_proc_units"           => "Current Minimum Processing Units",
    "CurrentMaximumProcessingUnits" => "Current Maximum Processing Units",
    "curr_max_proc_units"           => "Current Maximum Processing Units",
    "RuntimeProcessingUnits"        => "Runtime Processing Units",
    "run_proc_units"                => "Runtime Processing Units",
    "CurrentMemory"                 => "Current Memory",
    "curr_mem"                      => "Current Memory",
    "DesiredMemory"                 => "Desired Memory",
    "MinimumMemory"                 => "Minimum Memory",
    "MaximumMemory"                 => "Maximum Memory",
    "CurrentMinimumMemory"          => "Current Minimum Memory",
    "CurrentMaximumMemory"          => "Current Maximum Memory",
    "curr_min_mem"                  => "Current Minimum Memory",
    "curr_max_mem"                  => "Current Maximum Memory",
    "RuntimeMemory"                 => "Runtime Memory",
    "vm_env"                        => "Vm env",
    "os_version"                    => "OS version"
  };
  my $conf_metrics = [
    "state",
    "CurrentProcessingUnits",
    "curr_proc_units",
    "curr_procs",
    "curr_min_procs",
    "curr_max_procs",
    "curr_sharing_mode",
    "DesiredProcessingUnits",
    "MinimumProcessingUnits",
    "MaximumProcessingUnits",
    "CurrentMinimumProcessingUnits",
    "curr_min_proc_units",
    "CurrentMaximumProcessingUnits",
    "curr_max_proc_units",
    "RuntimeProcessingUnits",
    "run_proc_units",
    "CurrentMemory",
    "curr_mem",
    "DesiredMemory",
    "MinimumMemory",
    "MaximumMemory",
    "CurrentMinimumMemory",
    "curr_min_mem",
    "CurrentMaximumMemory",
    "curr_max_mem",
    "RuntimeMemory",
    "vm_env",
    "os_version",
  ];
  my $table;
  my $pdf_table;
  my $pdf_table_head;
  push @{$table}, [ "metric" => "value" ];
  foreach my $conf_metric ( @{$conf_metrics} ) {
    if ( defined $CONF->{vms}{$uid}{$conf_metric} ) {
      push @{$table}, [ $conf_metric => $CONF->{vms}{$uid}{$conf_metric} ];
    }
  }
  $pdf_table = addComponent( { 'component' => 'table1', 'data' => $table } );
  push @{ $pdf_data->{content} }, $pdf_table;

  my $hmc_uid       = $env->{hmcuid};
  my $hmc_label     = $env->{hmcname};
  my $rrd_file_path = "$wrkdir/$env->{servername}/$hmc_label/";
  my $file_pth      = "$wrkdir/$env->{servername}/*/";

  #get data from rrds
  #already got it in env->{lpar_data}

  #header
  push @{ $pdf_data->{content} }, set_PDF_table_text( "h2-bold", "center", "", "Performance LPAR" );

  #pool, pool total, mem for the physical server
  my $data;
  $data = {
    "vmname"            => "$env->{vmname}",
    "lpar_data_avg"     => "$env->{lpar_data_avg}",
    "lpar_data_max"     => "$env->{lpar_data_max}",
    "lpar_mem_data_avg" => "$env->{lpar_mem_data_avg}",
    "lpar_mem_data_max" => "$env->{lpar_mem_data_max}"
  };

  push @{ $pdf_data->{content} }, set_PDF_table_perf_lpar($data);

  my @graph_lpar_strings;

  push( @graph_lpar_strings, "host=$hmc_label&server=$env->{servername}&item=lpar&lpar=$env->{vmname}&sunix=$sunix&eunix=$eunix&type_sam=m&overview_power=1" );

  if ( -e "$basedir/data/$env->{servername}/$hmc_label/$env->{vmname}/cpu.mmm" ) {
    push( @graph_lpar_strings, "host=$hmc_label&server=$env->{servername}&item=oscpu&lpar=$env->{vmname}&sunix=$sunix&eunix=$eunix&type_sam=m&overview_power=1&detail=22" );
    push( @graph_lpar_strings, "host=$hmc_label&server=$env->{servername}&item=queue_cpu&lpar=$env->{vmname}&sunix=$sunix&eunix=$eunix&type_sam=m&overview_power=1&detail=22" );
    push( @graph_lpar_strings, "host=$hmc_label&server=$env->{servername}&item=jobs&lpar=$env->{vmname}&sunix=$sunix&eunix=$eunix&type_sam=m&overview_power=1&detail=22" );
    push( @graph_lpar_strings, "host=$hmc_label&server=$env->{servername}&item=mem&lpar=$env->{vmname}&sunix=$sunix&eunix=$eunix&type_sam=m&overview_power=1&detail=22" );
    push( @graph_lpar_strings, "host=$hmc_label&server=$env->{servername}&item=pg1&lpar=$env->{vmname}&sunix=$sunix&eunix=$eunix&type_sam=m&overview_power=1&detail=22" );
    push( @graph_lpar_strings, "host=$hmc_label&server=$env->{servername}&item=pg2&lpar=$env->{vmname}&sunix=$sunix&eunix=$eunix&type_sam=m&overview_power=1&detail=22" );
    push( @graph_lpar_strings, "host=$hmc_label&server=$env->{servername}&item=lan&lpar=$env->{vmname}&sunix=$sunix&eunix=$eunix&type_sam=m&overview_power=1&detail=22" );
    push( @graph_lpar_strings, "host=$hmc_label&server=$env->{servername}&item=san1&lpar=$env->{vmname}&sunix=$sunix&eunix=$eunix&type_sam=m&overview_power=1&detail=22" );
    push( @graph_lpar_strings, "host=$hmc_label&server=$env->{servername}&item=san2&lpar=$env->{vmname}&sunix=$sunix&eunix=$eunix&type_sam=m&overview_power=1&detail=22" );
    push( @graph_lpar_strings, "host=$hmc_label&server=$env->{servername}&item=san_resp&lpar=$env->{vmname}&sunix=$sunix&eunix=$eunix&type_sam=m&overview_power=1&detail=22" );
  }

  if ( -d "$basedir/data/$env->{servername}/$hmc_label/$env->{vmname}--AS400--/JOB" || -d "$basedir/data/$env->{servername}/$hmc_label/$env->{vmname}--AS400--/DSK" ) {
    push( @graph_lpar_strings, "host=$hmc_label&server=$env->{servername}&item=disk_io&lpar=$env->{vmname}&sunix=$sunix&eunix=$eunix&type_sam=m&overview_power=1&detail=22" );
    push( @graph_lpar_strings, "host=$hmc_label&server=$env->{servername}&item=disk_busy&lpar=$env->{vmname}&sunix=$sunix&eunix=$eunix&type_sam=m&overview_power=1&detail=22" );
    push( @graph_lpar_strings, "host=$hmc_label&server=$env->{servername}&item=S0200ASPJOB&lpar=$env->{vmname}&sunix=$sunix&eunix=$eunix&type_sam=m&overview_power=1&detail=22" );
    push( @graph_lpar_strings, "host=$hmc_label&server=$env->{servername}&item=threads&lpar=$env->{vmname}&sunix=$sunix&eunix=$eunix&type_sam=m&overview_power=1&detail=22" );
    push( @graph_lpar_strings, "host=$hmc_label&server=$env->{servername}&item=faults&lpar=$env->{vmname}&sunix=$sunix&eunix=$eunix&type_sam=m&overview_power=1&detail=22" );
    push( @graph_lpar_strings, "host=$hmc_label&server=$env->{servername}&item=pages&lpar=$env->{vmname}&sunix=$sunix&eunix=$eunix&type_sam=m&overview_power=1&detail=22" );
    push( @graph_lpar_strings, "host=$hmc_label&server=$env->{servername}&item=cap_used&lpar=$env->{vmname}&sunix=$sunix&eunix=$eunix&type_sam=m&overview_power=1&detail=22" );
    push( @graph_lpar_strings, "host=$hmc_label&server=$env->{servername}&item=cap_free&lpar=$env->{vmname}&sunix=$sunix&eunix=$eunix&type_sam=m&overview_power=1&detail=22" );
    push( @graph_lpar_strings, "host=$hmc_label&server=$env->{servername}&item=data_as&lpar=$env->{vmname}&sunix=$sunix&eunix=$eunix&type_sam=m&overview_power=1&detail=22" );
    push( @graph_lpar_strings, "host=$hmc_label&server=$env->{servername}&item=iops_as&lpar=$env->{vmname}&sunix=$sunix&eunix=$eunix&type_sam=m&overview_power=1&detail=22" );
    push( @graph_lpar_strings, "host=$hmc_label&server=$env->{servername}&item=dsk_latency&lpar=$env->{vmname}&sunix=$sunix&eunix=$eunix&type_sam=m&overview_power=1&detail=22" ) if (length(premium()) == 6);
    push( @graph_lpar_strings, "host=$hmc_label&server=$env->{servername}&item=data_ifcb&lpar=$env->{vmname}&sunix=$sunix&eunix=$eunix&type_sam=m&overview_power=1&detail=22" );
  }
  else {
    #header
    push @{ $pdf_data->{content} }, set_PDF_table_text( "h2-bold", "center", "", 'IBMi agent not installed. For more graphs follow instructions here: https://lpar2rrd.com/as400.php' );
  }

  #header
  push @{ $pdf_data->{content} }, set_PDF_table_text( "h2-bold", "center", "", "Graphs" );

  my $i = 0;
  foreach my $graph (@graph_lpar_strings) {
    my $png_file = "/tmp/temp_file-$i-$$.png";
    $i++;

    #print "$png_file, $graph\n";
    get_img_png( $png_file, $graph );
    if ( -f $png_file ) {

      #$_->{FILE} = $png_file;
      push( @{ $pdf_data->{content} }, set_PDF_img($png_file) );
      push( @graph_png_files,          $png_file );
    }
    else {
      Xorux_lib::error( "PNG file $png_file does not exists! $!" . __FILE__ . ":" . __LINE__ ) && next;
    }
  }

  return $pdf_data;
}

sub set_PDF_img {
  my $png_file = shift;

  my $content;

  $content->{type} = "IMG";
  $content->{file} = $png_file;

  return $content;
}

#perf table
sub set_PDF_table_perf {
  my $data = shift;
  my $content;
  $content->{type}           = "TABLE";
  $content->{table_settings} = {
    'padding_left'    => 5,
    'padding_right'   => 5,
    'border_c'        => '#ccc',
    'fg_color'        => 'black',
    'font'            => 'Helvetica',
    'max_word_length' => 50,
    'font_size'       => 10
  };

  # add header data
  push( @{ $content->{data} }, [ ( "",     "Total", undef, "Read", undef, "Write", undef ) ] );
  push( @{ $content->{data} }, [ ( "Pool", "avg",   "max", "avg",  "max", "avg",   "max" ) ] );

  # add header cell props
  push( @{ $content->{table_settings}->{cell_props} }, [ {}, { 'colspan' => 2, 'justify' => 'center' }, {}, { 'colspan' => '2', 'justify' => 'center' }, {}, { 'colspan' => '2', 'justify' => 'center' }, {} ] );
  push( @{ $content->{table_settings}->{cell_props} }, [ {}, { 'justify' => 'center' }, { 'justify' => 'center' }, { 'justify' => 'center' }, { 'justify' => 'center' }, { 'justify' => 'center' }, { 'justify' => 'center' } ] );
  $content->{table_settings}->{row_props} = [ { 'bg_color' => '#f6f8f9', 'font' => 'Helvetica-Bold' }, { 'bg_color' => '#f6f8f9', 'font' => 'Helvetica-Bold' } ];

  #print Dumper $data->{pool};

  #push( @{ $content->{data} }, [( "naaame", "$data->{pool}", "$data->{pool-max}", "$data->{pool-total}", "$data->{pool-total-max}","$data->{mem}", "$data->{mem-max}" ) ] );
  push( @{ $content->{data} }, [ ( "naaame", "$data->{'pool'}", "$data->{'pool-max'}", "$data->{'pool-total'}", "$data->{'pool-total-max'}", "$data->{'mem'}", "$data->{'mem-max'}" ) ] );

  return $content;
}

sub set_PDF_table_perf_server {
  my $data = shift;
  my $content;
  $content->{type}           = "TABLE";
  $content->{table_settings} = {
    'padding_left'    => 5,
    'padding_right'   => 5,
    'border_c'        => '#ccc',
    'fg_color'        => 'black',
    'font'            => 'Helvetica',
    'max_word_length' => 50,
    'font_size'       => 10
  };

  # add header data
  push( @{ $content->{data} }, [ ( "$data->{'servername'}", "average", "maximum" ) ] );

  # add header cell props
  #push( @{ $content->{table_settings}->{cell_props} }, [ {},{'colspan' => 2,'justify' => 'center'},{},{'colspan' => '2','justify' => 'center'},{}] );
  #push( @{ $content->{table_settings}->{cell_props} }, [ {}, {'justify' => 'center'}, {'justify' => 'center'}, {'justify' => 'center'}, {'justify' => 'center'} ] );
  $content->{table_settings}->{row_props} = [ { 'bg_color' => '#f6f8f9', 'font' => 'Helvetica-Bold' } ];

  #add content to rows
  push( @{ $content->{data} }, [ ( "CPU Total [Cores]", "$data->{'pool-total'}", "$data->{'pool-total-max'}" ) ] );
  push( @{ $content->{data} }, [ ( "CPU Pool [Cores]",  "$data->{'pool'}",       "$data->{'pool-max'}" ) ] );
  push( @{ $content->{data} }, [ ( "Memory [GB]",       "$data->{'mem'}",        "$data->{'mem-max'}" ) ] );

  return $content;
}

sub set_PDF_table_perf_lpar {
  my $data = shift;
  my $content;
  $content->{type}           = "TABLE";
  $content->{table_settings} = {
    'padding_left'    => 5,
    'padding_right'   => 5,
    'border_c'        => '#ccc',
    'fg_color'        => 'black',
    'font'            => 'Helvetica',
    'max_word_length' => 50,
    'font_size'       => 10
  };

  # add header data
  push( @{ $content->{data} }, [ ( "$data->{'vmname'}", "average", "maximum" ) ] );

  # add header cell props
  #push( @{ $content->{table_settings}->{cell_props} }, [ {},{'colspan' => 2,'justify' => 'center'},{},{'colspan' => '2','justify' => 'center'},{}] );
  #push( @{ $content->{table_settings}->{cell_props} }, [ {}, {'justify' => 'center'}, {'justify' => 'center'}, {'justify' => 'center'}, {'justify' => 'center'} ] );
  $content->{table_settings}->{row_props} = [ { 'bg_color' => '#f6f8f9', 'font' => 'Helvetica-Bold' } ];

  #add content to rows
  push( @{ $content->{data} }, [ ( "CPU [Cores]",           "$data->{'lpar_data_avg'}",     "$data->{'lpar_data_max'}" ) ] );
  push( @{ $content->{data} }, [ ( "Memory Allocated [GB]", "$data->{'lpar_mem_data_avg'}", "$data->{'lpar_mem_data_max'}" ) ] );

  return $content;
}

sub set_PDF_table_perf_shpools {
  my $data = shift;
  my $content;
  $content->{type}           = "TABLE";
  $content->{table_settings} = {
    'padding_left'    => 5,
    'padding_right'   => 5,
    'border_c'        => '#ccc',
    'fg_color'        => 'black',
    'font'            => 'Helvetica',
    'max_word_length' => 50,
    'font_size'       => 10
  };

  # add header data
  push( @{ $content->{data} }, [ ( "Shared CPU Pools [Cores]", "average", "maximum" ) ] );

  # add header cell props
  #push( @{ $content->{table_settings}->{cell_props} }, [ {},{'colspan' => 2,'justify' => 'center'},{},{'colspan' => '2','justify' => 'center'},{}] );
  #push( @{ $content->{table_settings}->{cell_props} }, [ {}, {'justify' => 'center'}, {'justify' => 'center'}, {'justify' => 'center'}, {'justify' => 'center'} ] );
  $content->{table_settings}->{row_props} = [ { 'bg_color' => '#f6f8f9', 'font' => 'Helvetica-Bold' } ];

  #add content to rows
  foreach my $shpool_uid ( keys %{$data} ) {
    push( @{ $content->{data} }, [ ( "$data->{$shpool_uid}{conf}{name}", "$data->{$shpool_uid}{cpu_avg}", "$data->{$shpool_uid}{cpu_max}" ) ] );
  }

  return $content;
}

sub get_img_png {
  my $png_file     = shift;
  my $query_string = shift;

  $ENV{'PICTURE_COLOR'} = "FFF";
  $ENV{'QUERY_STRING'}  = $query_string;

  my $error_log_tmp = "/var/tmp/error.log-tmp-$$";

  chdir("$bindir") || Xorux_lib::error( "Couldn't change directory to $bindir $!" . __FILE__ . ":" . __LINE__ ) && exit;

  my $ret = `$ENV{PERL} $bindir/detail-graph-cgi.pl 2>$error_log_tmp`;

  if ( -s "$error_log_tmp" ) {
    open( my $file, "<$error_log_tmp" ) || Xorux_lib::error( "Couldn't open file $error_log_tmp $!" . __FILE__ . ":" . __LINE__ ) && exit;
    my @lines = <$file>;
    close($file);

    Xorux_lib::error("ERROR detail-graph-cgi.pl: QUERY_STRING=$ENV{'QUERY_STRING'}");
    foreach my $line (@lines) {
      chomp $line;
      Xorux_lib::error("ERROR detail-graph-cgi.pl: $line");
    }
    unlink("$error_log_tmp");
  }
  if ( -f "$error_log_tmp" ) {
    unlink("$error_log_tmp");
  }

  # remove html header
  my ( undef, $justpng ) = ( split "\n\n", $ret, 2 );

  if ( defined $justpng && $justpng ne '' ) {
    open( my $file, ">$png_file" ) || Xorux_lib::error( "Couldn't open file $png_file $!" . __FILE__ . ":" . __LINE__ ) && exit;
    print $file $justpng;
    close $file;
  }

  return 1;
}

#create component
sub addComponent {
  my $data             = shift;
  my $table_parameters = getTableSpecs("$data->{component}");
  my $pdf_table        = createTable( $table_parameters, $data->{data} );
  return $pdf_table;
}

sub createTable {
  my $params = shift;
  my $data   = shift;
  my $table  = {};
  $table = $params;
  $table->{data} = $data;
  return $table;
}

#specify fonts, sizes etc for different types of objects.
sub getTableSpecs {
  my $type  = shift;
  my $specs = {};
  if ( $type eq "header1" ) {
    $specs->{type}           = 'TABLE-TEXTONLY';
    $specs->{table_settings} = {
      'justify'         => 'center',
      'fg_color'        => 'white',
      'padding'         => 10,
      'font_size'       => 16,
      'bg_color'        => '#0B2F3A',
      'font'            => 'Helvetica',
      'max_word_length' => 50,
      'border_w'        => 0
    };
    $specs->{text_settings} = { 'padding_y' => 3 };
  }
  elsif ( $type eq "header2" ) {
    $specs->{type}           = 'TABLE-TEXTONLY';
    $specs->{table_settings} = {
      'justify'         => 'center',
      'fg_color'        => 'black',
      'padding'         => 0,
      'font_size'       => 14,
      'font'            => 'Helvetica',
      'max_word_length' => 50,
      'border_w'        => 0
    };
    $specs->{text_settings} = { 'padding_y' => 3 };
  }
  elsif ( $type eq "header2-href" ) {
    $specs->{type}           = 'TABLE-TEXTONLY';
    $specs->{table_settings} = {
      'justify'         => 'center',
      'fg_color'        => 'black',
      'padding'         => 0,
      'font_size'       => 14,
      'font'            => 'Helvetica',
      'max_word_length' => 999,
      'border_w'        => 0
    };
    $specs->{text_settings} = { 'padding_y' => 3 };
  }
  elsif ( $type eq "table1" ) {
    $specs->{type}           = "TABLE";
    $specs->{table_settings} = {
      'padding_left'    => 5,
      'max_word_length' => '50',
      'padding_right'   => 5,
      'border_c'        => '#ccc',
      'fg_color'        => 'black',
      'font'            => 'Helvetica',
      'max_word_length' => 50,
      'font_size'       => 10,
      'header_props'    => {
        'bg_color' => '#f6f8f9',
        'font'     => 'Helvetica-Bold'
      }
    };
  }
  return $specs;
}

sub set_PDF_table_text {
  my $type      = shift;
  my $align     = shift;
  my $padding_y = shift;
  my $text      = shift;

  unless ( defined $padding_y && Xorux_lib::isdigit($padding_y) ) { $padding_y = 3; }    # default vertical distance

  my $content;

  $content->{type} = "TABLE-TEXTONLY";

  if ( $type eq "header" ) {
    $content->{table_settings} = {
      'fg_color'        => 'white',
      'bg_color'        => '#0B2F3A',
      'justify'         => $align,
      'padding'         => 10,
      'border_w'        => 0,
      'font'            => 'Helvetica',
      'max_word_length' => 50,
      'font_size'       => 16
    };
    $content->{text_settings} = { 'padding_y' => $padding_y };
  }
  elsif ( $type eq "header2" ) {
    $content->{table_settings} = {
      'fg_color'        => 'white',
      'bg_color'        => '#0B2F3A',
      'justify'         => $align,
      'padding'         => 2,
      'border_w'        => 0,
      'font'            => 'Helvetica',
      'max_word_length' => 50,
      'font_size'       => 12
    };
    $content->{text_settings} = { 'padding_y' => $padding_y };
  }
  elsif ( $type eq "h1" ) {
    $content->{table_settings} = {
      'fg_color'        => 'black',
      'justify'         => $align,
      'padding'         => 0,
      'border_w'        => 0,
      'font'            => 'Helvetica',
      'max_word_length' => 50,
      'font_size'       => 14
    };
    $content->{text_settings} = { 'padding_y' => $padding_y };
  }
  elsif ( $type eq "h2" ) {
    $content->{table_settings} = {
      'fg_color'        => 'black',
      'justify'         => $align,
      'padding'         => 0,
      'border_w'        => 0,
      'font'            => 'Helvetica',
      'max_word_length' => 50,
      'font_size'       => 10
    };
    $content->{text_settings} = { 'padding_y' => $padding_y };
  }
  elsif ( $type eq "h3" ) {
    $content->{table_settings} = {
      'fg_color'        => 'black',
      'justify'         => $align,
      'padding'         => 0,
      'border_w'        => 0,
      'font'            => 'Helvetica',
      'max_word_length' => 50,
      'font_size'       => 8
    };
    $content->{text_settings} = { 'padding_y' => $padding_y };
  }
  elsif ( $type eq "h1-bold" ) {
    $content->{table_settings} = {
      'fg_color'        => 'black',
      'justify'         => $align,
      'padding'         => 0,
      'border_w'        => 0,
      'font'            => 'Helvetica-Bold',
      'max_word_length' => 50,
      'font_size'       => 14
    };
    $content->{text_settings} = { 'padding_y' => $padding_y };
  }
  elsif ( $type eq "h2-bold" ) {
    $content->{table_settings} = {
      'fg_color'        => 'black',
      'justify'         => $align,
      'padding'         => 0,
      'border_w'        => 0,
      'font'            => 'Helvetica-Bold',
      'max_word_length' => 50,
      'font_size'       => 10
    };
    $content->{text_settings} = { 'padding_y' => $padding_y };
  }
  elsif ( $type eq "h3-bold" ) {
    $content->{table_settings} = {
      'fg_color'        => 'black',
      'justify'         => $align,
      'padding'         => 0,
      'border_w'        => 0,
      'font'            => 'Helvetica-Bold',
      'max_word_length' => 50,
      'font_size'       => 8
    };
    $content->{text_settings} = { 'padding_y' => $padding_y };
  }
  else {    # default
    $content->{table_settings} = {
      'fg_color'        => 'black',
      'justify'         => $align,
      'padding'         => 0,
      'border_w'        => 0,
      'font'            => 'Helvetica',
      'max_word_length' => 50,
      'font_size'       => 14
    };
    $content->{text_settings} = { 'padding_y' => $padding_y };
  }

  push( @{ $content->{data} }, [ ($text) ] );

  return $content;
}

sub remove_graphs {
  foreach my $g_file (@graph_png_files) {
    if ( -f $g_file ) { unlink $g_file; }
  }
}

sub urlencode {
  my $s = shift;
  $s =~ s/([^a-zA-Z0-9!~*()'\''-])/sprintf("%%%02X", ord($1))/ge;
  return $s;
}
RRDp::end;
