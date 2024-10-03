package Db2Graph;

use strict;
use warnings;

use Db2DataWrapper;
use Data::Dumper;
use Xorux_lib qw(error read_json);

defined $ENV{INPUTDIR} || warn("INPUTDIR undefined, config etc/lpar2rrd.cfg probably has not been loaded ") && exit 1;

my $inputdir      = $ENV{INPUTDIR};
my $bindir        = $ENV{BINDIR};
my $main_data_dir = "$inputdir/data/DB2";


my $instance_names;
my $can_read;
my $ref;
my $del = "XORUX";    # delimiter, this is for rrdtool print lines for clickable legend

my @_colors = ( "#FF0000", "#0000FF", "#FFFF00", "#FFA500", "#00FF00", "#000000", "#1CE6FF", "#FF34FF", "#FF4A46", "#008941", "#006FA6", "#A30059", "#7A4900", "#0000A6", "#63FFAC", "#B79762", "#004D43", "#8FB0FF", "#997D87", "#5A0007", "#809693", "#1B4400", "#4FC601", "#3B5DFF", "#4A3B53", "#FF2F80", "#61615A", "#BA0900", "#6B7900", "#00C2A0", "#FFAA92", "#FF90C9", "#B903AA", "#D16100", "#000035", "#7B4F4B", "#A1C299", "#300018", "#0AA6D8", "#013349", "#00846F", "#372101", "#FFB500", "#C2FFED", "#A079BF", "#CC0744", "#C0B9B2", "#C2FF99", "#001E09", "#00489C", "#6F0062", "#0CBD66", "#EEC3FF", "#456D75", "#B77B68", "#7A87A1", "#788D66", "#885578", "#FAD09F", "#FF8A9A", "#D157A0", "#BEC459", "#456648", "#0086ED", "#886F4C", "#34362D", "#B4A8BD", "#00A6AA", "#452C2C", "#636375", "#A3C8C9", "#FF913F", "#938A81", "#575329", "#00FECF", "#B05B6F", "#8CD0FF", "#3B9700", "#04F757", "#C8A1A1", "#1E6E00", "#7900D7", "#A77500", "#6367A9", "#A05837", "#6B002C", "#772600", "#D790FF", "#9B9700", "#549E79", "#FFF69F", "#201625", "#72418F", "#BC23FF", "#99ADC0", "#3A2465", "#922329", "#5B4534", "#FDE8DC", "#404E55", "#0089A3", "#CB7E98", "#A4E804", "#324E72", "#6A3A4C", "#83AB58", "#001C1E", "#D1F7CE", "#004B28", "#C8D0F6", "#A3A489", "#806C66", "#222800", "#BF5650", "#E83000", "#66796D", "#DA007C", "#FF1A59", "#8ADBB4", "#1E0200", "#5B4E51", "#C895C5", "#320033", "#FF6832", "#66E1D3", "#CFCDAC", "#D0AC94", "#7ED379", "#012C58", "#7A7BFF", "#D68E01", "#353339", "#78AFA1", "#FEB2C6", "#75797C", "#837393", "#943A4D", "#B5F4FF", "#D2DCD5", "#9556BD", "#6A714A", "#001325", "#02525F", "#0AA3F7", "#E98176", "#DBD5DD", "#5EBCD1", "#3D4F44", "#7E6405", "#02684E", "#962B75", "#8D8546", "#9695C5", "#E773CE", "#D86A78", "#3E89BE", "#CA834E", "#518A87", "#5B113C", "#55813B", "#E704C4", "#00005F", "#A97399", "#4B8160", "#59738A", "#FF5DA7", "#F7C9BF", "#643127", "#513A01", "#6B94AA", "#51A058", "#A45B02", "#1D1702", "#E20027", "#E7AB63", "#4C6001", "#9C6966", "#64547B", "#97979E", "#006A66", "#391406", "#F4D749", "#0045D2", "#006C31", "#DDB6D0", "#7C6571", "#9FB2A4", "#00D891", "#15A08A", "#BC65E9", "#FFFFFE", "#C6DC99", "#203B3C", "#671190", "#6B3A64", "#F5E1FF", "#FFA0F2", "#CCAA35", "#374527", "#8BB400", "#797868", "#C6005A", "#3B000A", "#C86240", "#29607C", "#402334", "#7D5A44", "#CCB87C", "#B88183", "#AA5199", "#B5D6C3", "#A38469", "#9F94F0", "#A74571", "#B894A6", "#71BB8C", "#00B433", "#789EC9", "#6D80BA", "#953F00", "#5EFF03", "#E4FFFC", "#1BE177", "#BCB1E5", "#76912F", "#003109", "#0060CD", "#D20096", "#895563", "#29201D", "#5B3213", "#A76F42", "#89412E", "#1A3A2A", "#494B5A", "#A88C85", "#F4ABAA", "#A3F3AB", "#00C6C8", "#EA8B66", "#958A9F", "#BDC9D2", "#9FA064", "#BE4700", "#658188", "#83A485", "#453C23", "#47675D", "#3A3F00", "#061203", "#DFFB71", "#868E7E", "#98D058", "#6C8F7D", "#D7BFC2", "#3C3E6E", "#D83D66", "#2F5D9B", "#6C5E46", "#D25B88", "#5B656C", "#00B57F", "#545C46", "#866097", "#365D25", "#252F99", "#00CCFF", "#674E60", "#FC009C", "#92896B" );

################################################################################

sub signpost {
  my $acl_check = shift;
  my $host      = shift;
  my $server    = shift;
  my $lpar      = shift;
  my $item      = shift;
  my $colors    = shift;
  my $dunno     = shift;

  if ( $item =~ /_a_/ ) {
    return graph_default( $acl_check, $host, $server, $lpar, $item, $dunno );
  }
  elsif ( $item =~ m/^db2/ ) {
    return graph_views( $acl_check, $host, $server, $lpar, $item, $colors );
  }
  else {
    return 0;
  }
}

sub get_formatted_label {

  my $label_space = shift;

  $label_space .= " " x ( 30 - length($label_space) );

  return $label_space;
}

sub get_formatted_label_val {
  my $label_space = shift;

  $label_space .= " " x ( 25 - length($label_space) );

  return $label_space;
}

sub get_color {
  my $colors_ref = shift;
  my $col        = shift;
  my @colors     = @{$colors_ref};
  my $color;
  my $next_index = $col % $#colors;
  $color = $colors[$next_index];
}

sub graph_default {
  my $acl_check = shift;
  my $host      = shift;
  my $server    = shift;
  my $type      = shift;
  my $item      = shift;
  my $dunno     = shift;
  my $color     = "#FF0000";
  if ( $item =~ m/_a_/ ) {
    $color = "#";
    $color .= Db2DataWrapper::basename( $item, '_a_' );
    $item = substr( $item, 0, index( $item, '_a_' ) );
  }
  my $_page    = Db2DataWrapper::basename( $item, '__' );
  my $metric_type = $type;
  if ($type eq "BUFFERPOOL"){
    $metric_type = Db2DataWrapper::get_type_from_page($_page);
  }
  my $rrd_type  = Db2DataWrapper::get_type($type);


  my $page     = Db2DataWrapper::basename( $item, '__' );
  my $pages_ref = Db2DataWrapper::get_pages($metric_type);
  my $rrd      = Db2DataWrapper::get_filepath_rrd( { type => $rrd_type, uuid => $server, id => $host, acl_check => $acl_check } );
  my $legend   = Db2DataWrapper::graph_legend($page);

  #my ( $header, $reduced_header ) = get_header( $type, 'Network Traffic Volume' );
  my $cmd_params = my $cmd_legend = my $cmd_cdef = my $cmd_def = my $cmd_vlabel = "";
  my $rrd_name   = $pages_ref->{$page}->{$dunno};

  $cmd_vlabel .= " --vertical-label=\"$legend->{v_label}\"";
  if ( $metric_type eq "Ratio" ) {
    $cmd_params .= " --upper-limit=133";
  }
  $cmd_params .= " --lower-limit=0.00";
  $cmd_params .= " --units-exponent=1.00";
  $cmd_def    .= " DEF:name=\"$rrd\":$rrd_name:AVERAGE";
  if ( $legend->{denom} == 1000000 ) {
    $cmd_cdef .= " CDEF:name_result=name,10000,LT,0,name,IF";
    $cmd_cdef .= " CDEF:name_div=name_result,1000000,/";
  }
  else {
    $cmd_cdef .= " CDEF:name_div=name,$legend->{denom},/";
  }
  my $label = get_formatted_label( $legend->{brackets} );
  $cmd_legend .= " COMMENT:\"$label Avrg       Max\\n\"";
  $label = "";
  $label = get_formatted_label_val( $legend->{value} );
  $cmd_legend .= " LINE1:name_div$color:\" $label\"";
  $cmd_legend .= " GPRINT:name_div:AVERAGE:\" %6.".$legend->{decimals}."lf\"";
  $cmd_legend .= " GPRINT:name_div:MAX:\" %6.".$legend->{decimals}."lf\"";
  $cmd_legend .= " COMMENT:\\n";

  return {
    filename => $rrd,     header   => $legend->{header}, reduced_header => "$server - $legend->{header}", cmd_params => $cmd_params,
    cmd_def  => $cmd_def, cmd_cdef => $cmd_cdef,         cmd_legend     => $cmd_legend,                   cmd_vlabel => $cmd_vlabel
  };
}

sub graph_views {
  my $acl_check  = shift;
  my $host       = shift;
  my $server     = shift;
  my $type       = shift;
  my $item       = shift;
  my $colors_ref = shift;
  my $color;
  
  my $_page    = Db2DataWrapper::basename( $item, '__' );
  my $metric_type = $type;
  if ($type eq "BUFFERPOOL"){
    $metric_type = Db2DataWrapper::get_type_from_page($_page);
  }
  my $rrd_type  = Db2DataWrapper::get_type($type);
  my $pages_ref = Db2DataWrapper::get_pages($metric_type);
  my $g_number  = 0;
  my $rrd;
  my $cmd_params = my $cmd_legend = my $cmd_cdef = my $cmd_def = "";

  my %pages;
  if ( $pages_ref and $pages_ref ne "empty" ) {
    %pages = %{$pages_ref};
  }
  else {
    warn "no pages in views";
  }
  if ( $metric_type eq "Ratio" ) {
    $cmd_params .= " --upper-limit=123";
  }
  my $cur_hos = 0;
  $cmd_params .= " --lower-limit=0.00";
  $cmd_params .= " --alt-y-grid";
  $cmd_legend .= " COMMENT:\\n";
  undef $rrd;
  $rrd = Db2DataWrapper::get_filepath_rrd( { type => $rrd_type, uuid => $server, id => $host, acl_check => $acl_check } );
  my $legend = Db2DataWrapper::graph_legend($_page);
  my @values = keys %{ $pages{$_page} };
  @values = sort { lc($a) cmp lc($b) } @values;
  foreach my $val (@values) {
    my $rrdval = $pages{$_page}{$val};
    $cmd_def .= " DEF:name-$cur_hos-$rrdval=\"$rrd\":$rrdval:AVERAGE";
    if ( $legend->{denom} == 1000000 ) {
      $cmd_cdef .= " CDEF:name_result=name-$cur_hos-$rrdval,10000,LT,0,name,IF";
      $cmd_cdef .= " CDEF:name_div=name_result,1000000,/";
    }
    else {
      $cmd_cdef .= " CDEF:view-$cur_hos-$rrdval=name-$cur_hos-$rrdval,$legend->{denom},/";
    }
    $color = get_color( $colors_ref, $g_number );
    $g_number++;
    my $label   = get_formatted_label_val("$val");
    #$label .= "";
    my $ns_page = $_page;
    $ns_page =~ s/ /_/g;

    if ( $legend->{graph_type} eq "LINE1" ) {
      $cmd_legend .= " LINE1:view-$cur_hos-$rrdval" . "$color:\" $label\"";
    }
    else {
      if ( $cur_hos == 0 ) {
        $cmd_legend .= " AREA:view-$cur_hos-$rrdval" . "$color:\" $label\"";
      }
      else {
        $cmd_legend .= " STACK:view-$cur_hos-$rrdval" . "$color:\" $label\"";
      }
    }
    $cmd_legend .= " GPRINT:view-$cur_hos-$rrdval:AVERAGE:\" %6.".$legend->{decimals}."lf\"";
    $cmd_legend .= " GPRINT:view-$cur_hos-$rrdval:MAX:\" %6.".$legend->{decimals}."lf\"";
    $cmd_legend .= " PRINT:view-$cur_hos-$rrdval:AVERAGE:\" %6.".$legend->{decimals}."lf $del $item $del $label $del $color $del $ns_page\"";
    $cmd_legend .= " PRINT:view-$cur_hos-$rrdval:MAX:\" %6.".$legend->{decimals}."lf $del asd $del $label $del cur_hos\"";
    $cmd_legend .= " COMMENT:\\n";

    $cur_hos++;
  }

  return {
    filename => $rrd,     header   => "$legend->{header}", reduced_header => "$legend->{header}", cmd_params => $cmd_params,
    cmd_def  => $cmd_def, cmd_cdef => $cmd_cdef,           cmd_legend     => $cmd_legend,         cmd_vlabel => "$legend->{v_label}"
  };
}

1;
