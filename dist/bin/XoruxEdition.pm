package XoruxEdition;

use Exporter;
@ISA = qw(Exporter);

@EXPORT = qw(premium get_rperf_all rperf_check lpm get_lpar_num lpm_find_files);

sub premium        { return "free"; }
sub get_rperf_all  { return 0; }
sub rperf_check    { return 0; }
sub lpm            { return 0; }
sub get_lpar_num   { return 0 }
sub lpm_find_files { return 0 }

1;
