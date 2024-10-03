# aws-genmenu.pl
# generate menu tree from Nutanix RRDs and print it as JSON
# replacement for an older equivalent to `find_active_lpar.pl` that generated `menu.txt`

use 5.008_008;

use strict;
use warnings;

use JSON;
use Data::Dumper;
use HostCfg;
use Xorux_lib;
use AWSDataWrapperOOP;
use AWSMenu;
use AWSLoadDataModule;

defined $ENV{INPUTDIR} || warn( localtime() . ': INPUTDIR undefined, config etc/lpar2rrd.cfg probably has not been loaded ' . __FILE__ . ':' . __LINE__ ) && exit 1;

my $inputdir = $ENV{INPUTDIR};

if ( keys %{ HostCfg::getHostConnections('AWS') } == 0 ) {
  exit(0);
}

my $aws_metadata = AWSDataWrapperOOP->new( { acl_check => 0 } );

my $menu_tree = AWSMenu::create_folder('Amazon Web Services');
my $regions   = gen_regions();

if ( scalar @{$regions} ) {
  my $configuration_page_url = AWSMenu::get_url( { type => 'configuration' } );
  my $configuration_page     = AWSMenu::create_page( 'Configuration', $configuration_page_url );
  my $health_page_url        = AWSMenu::get_url( { type => 'health' } );
  my $health_page            = AWSMenu::create_page( 'Health Status', $health_page_url );
  my $instance_page_url      = AWSMenu::get_url( { type => 'region-aggr' } );
  my $instance_page          = AWSMenu::create_page( 'Instance Overview', $instance_page_url );

  #my $heatmap_page_url       = AWSMenu::get_url( { type => 'heatmap' } );
  #my $heatmap_page           = AWSMenu::create_page( 'Heatmap', $heatmap_page_url );

  $menu_tree->{children} = [ $health_page, $configuration_page, $instance_page ];
  push @{ $menu_tree->{children} }, @{$regions};

  # print menu tree as JSON
  my $json      = JSON->new->utf8->pretty;
  my $json_data = $json->encode($menu_tree);
  print $json_data;
}
exit 0;

sub gen_regions {

  #my $labels = NutanixDataWrapper::get_labels();

  my @region_folders = ();
  my @regions        = @{ $aws_metadata->get_items( { item_type => 'region' } ) };

  foreach my $region (@regions) {
    my ( $region_id, $region_label ) = each %{$region};

    my ( $ec2_folder, $totals_url, $ebs_folder, $totals_url_ebs, %totals_page, %totals_page_ebs, $rds_folder, $totals_url_rds, %totals_page_rds, $api_folder, $totals_url_api, %totals_page_api, $lambda_folder, $totals_url_lambda, %totals_page_lambda );

    my @ec2s = @{ $aws_metadata->get_items( { item_type => 'ec2', parent_type => 'region', parent_id => $region_id } ) };

    if ( scalar @ec2s >= 1 ) {

      $ec2_folder  = AWSMenu::create_folder('Elastic Compute Cloud');
      $totals_url  = AWSMenu::get_url( { type => 'ec2-aggr', region => $region_id } );
      %totals_page = %{ AWSMenu::create_page( 'EC2 Totals', $totals_url ) };

      foreach my $ec2 (@ec2s) {
        my ( $ec2_uuid, $ec2_label ) = each %{$ec2};

        my $filepath = $aws_metadata->get_filepath_rrd( { type => 'ec2', uuid => $ec2_uuid } );
        unless ( -f $filepath ) { next; }

        my $url      = AWSMenu::get_url( { type => 'ec2', ec2 => $ec2_uuid } );
        my %ec2_page = %{ AWSMenu::create_page( $ec2_label, $url ) };
        push @{ $ec2_folder->{children} }, \%ec2_page;

      }

    }

    my @ebs = @{ $aws_metadata->get_items( { item_type => 'volume', parent_type => 'region', parent_id => $region_id } ) };

    if ( scalar @ebs >= 1 ) {

      $ebs_folder      = AWSMenu::create_folder('Elastic Block Store');
      $totals_url_ebs  = AWSMenu::get_url( { type => 'ebs-aggr', region => $region_id } );
      %totals_page_ebs = %{ AWSMenu::create_page( 'EBS Totals', $totals_url_ebs ) };

      foreach my $volume (@ebs) {
        my ( $volume_uuid, $volume_label ) = each %{$volume};

        my $filepath = $aws_metadata->get_filepath_rrd( { type => 'volume', uuid => $volume_uuid } );
        unless ( -f $filepath ) { next; }

        my $url         = AWSMenu::get_url( { type => 'ebs', ebs => $volume_uuid } );
        my %volume_page = %{ AWSMenu::create_page( $volume_label, $url ) };
        push @{ $ebs_folder->{children} }, \%volume_page;

      }

    }

    my @rds = @{ $aws_metadata->get_items( { item_type => 'rds', parent_type => 'region', parent_id => $region_id } ) };

    if ( scalar @rds >= 1 ) {

      $rds_folder      = AWSMenu::create_folder('Relational Database Service');
      $totals_url_rds  = AWSMenu::get_url( { type => 'rds-aggr', region => $region_id } );
      %totals_page_rds = %{ AWSMenu::create_page( 'RDS Totals', $totals_url_rds ) };

      foreach my $db (@rds) {
        my ( $rds_uuid, $rds_label ) = each %{$db};

        my $filepath = $aws_metadata->get_filepath_rrd( { type => 'rds', uuid => $rds_uuid } );
        unless ( -f $filepath ) { next; }

        my $url      = AWSMenu::get_url( { type => 'rds', rds => $rds_uuid } );
        my %rds_page = %{ AWSMenu::create_page( $rds_label, $url ) };
        push @{ $rds_folder->{children} }, \%rds_page;

      }

    }

    my @api = @{ $aws_metadata->get_items( { item_type => 'api', parent_type => 'region', parent_id => $region_id } ) };

    if ( scalar @api >= 1 ) {

      $api_folder      = AWSMenu::create_folder('API Gateway');
      $totals_url_api  = AWSMenu::get_url( { type => 'api-aggr', region => $region_id } );
      %totals_page_api = %{ AWSMenu::create_page( 'API Totals', $totals_url_api ) };

      foreach my $ap (@api) {
        my ( $api_uuid, $api_label ) = each %{$ap};

        my $filepath = $aws_metadata->get_filepath_rrd( { type => 'api', uuid => $api_uuid } );
        unless ( -f $filepath ) { next; }

        my $url      = AWSMenu::get_url( { type => 'api', api => $api_uuid } );
        my %api_page = %{ AWSMenu::create_page( $api_label, $url ) };
        push @{ $api_folder->{children} }, \%api_page;

      }

    }

    my @lambda = @{ $aws_metadata->get_items( { item_type => 'lambda', parent_type => 'region', parent_id => $region_id } ) };

    if ( scalar @lambda >= 1 ) {

      $lambda_folder      = AWSMenu::create_folder('Lambda');
      $totals_url_lambda  = AWSMenu::get_url( { type => 'lambda-aggr', region => $region_id } );
      %totals_page_lambda = %{ AWSMenu::create_page( 'Lambda Totals', $totals_url_lambda ) };

      foreach my $la (@lambda) {
        my ( $lambda_uuid, $lambda_label ) = each %{$la};

        my $filepath = $aws_metadata->get_filepath_rrd( { type => 'lambda', uuid => $lambda_uuid } );
        unless ( -f $filepath ) { next; }

        my $url         = AWSMenu::get_url( { type => 'lambda', lambda => $lambda_uuid } );
        my %lambda_page = %{ AWSMenu::create_page( $lambda_label, $url ) };
        push @{ $lambda_folder->{children} }, \%lambda_page;

      }

    }

    my $region_folder = AWSMenu::create_folder($region_label);
    if ( scalar @ec2s >= 1 ) {
      push @{ $region_folder->{children} }, \%totals_page;
    }
    if ( scalar @ebs >= 1 ) {
      push @{ $region_folder->{children} }, \%totals_page_ebs;
    }
    if ( scalar @rds >= 1 ) {
      push @{ $region_folder->{children} }, \%totals_page_rds;
    }
    if ( scalar @api >= 1 ) {
      push @{ $region_folder->{children} }, \%totals_page_api;
    }
    if ( scalar @lambda >= 1 ) {
      push @{ $region_folder->{children} }, \%totals_page_lambda;
    }
    if ( scalar @ec2s >= 1 ) {
      push @{ $region_folder->{children} }, $ec2_folder;
    }
    if ( scalar @ebs >= 1 ) {
      push @{ $region_folder->{children} }, $ebs_folder;
    }
    if ( scalar @rds >= 1 ) {
      push @{ $region_folder->{children} }, $rds_folder;
    }
    if ( scalar @api >= 1 ) {
      push @{ $region_folder->{children} }, $api_folder;
    }
    if ( scalar @lambda >= 1 ) {
      push @{ $region_folder->{children} }, $lambda_folder;
    }

    push @region_folders, $region_folder;

  }

  return \@region_folders;

}
