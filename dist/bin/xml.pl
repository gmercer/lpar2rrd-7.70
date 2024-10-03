#use XML::Simple;

# workaround for AIX 7.1 problem:
# Can't locate object method "new" via package "XML::LibXML::SAX" at /usr/opt/perl5/lib/site_perl/5.10.1/XML/SAX/ParserFactory.pm line 43.

use XML::Simple;

# change since 2.52-13, this is x times faster than the default one
#$XML::Simple::PREFERRED_PARSER = "XML::Parser";

# change since 29.5.19, this will check for XML::Parser touched file (touched by load.sh) and will not set PREFERED_PARSER if XML:Parser is not present \HD
my $basedir = $ENV{INPUTDIR};
if ( -e "$basedir/tmp/xml_parser" ) {
  $XML::Simple::PREFERRED_PARSER = "XML::Parser";
}

#print "XML version : $XML::Simple::VERSION\n";
#$XML::Simple::PREFERRED_PARSER = "XML::SAX::PurePerl";
#use XML::SAX::PurePerl;

return 1;

