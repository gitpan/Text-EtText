require 5.005;
use ExtUtils::MakeMaker;

sub MY::libscan {
  my($self,$path) = @_;

  return '' if ($path =~ /windows_install/
                );

  $path;
}

# See lib/ExtUtils/MakeMaker.pm for details of how to influence
# the contents of the Makefile that is written.
WriteMakefile(
    'NAME'	=> 'Text::EtText',
    'VERSION_FROM' => 'lib/Text/EtText.pm', # finds $VERSION

    'EXE_FILES'	=> [ 'ethtml2text', 'ettext2html'],

    'PL_FILES' => '',

    'PMLIBDIRS' => [ 'lib' ],

    'dist' => { COMPRESS => 'gzip -9f', SUFFIX => 'gz',
	      DIST_DEFAULT => 'tardist' },

    'clean' => { FILES =>
	't/log pod2html* '.
	'examples/*html EtText.spec doc/pod2html*'
    },

    'AUTHOR' => 'Justin Mason <jm@jmason.org>',
    'ABSTRACT' => 'A plain-text markup format for HTML'

);
