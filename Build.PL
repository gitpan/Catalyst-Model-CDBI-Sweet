use strict;
use Module::Build;

my %arguments = (
    create_makefile_pl => 'passthrough',
    license            => 'perl',
    module_name        => 'Catalyst::Model::CDBI::Sweet',
    requires           => {
        'Catalyst'          => 0,
        'Class::DBI::Sweet' => 0
    },
    create_makefile_pl => 'passthrough',
    test_files         => [ glob('t/*.t') ]
);

if ( $^O eq 'MSWin32' ) {
    $arguments{requires}->{'Win32API::GUID'} = 0;
}
else {
    $arguments{requires}->{'Data::UUID'} = 0;
}

Module::Build->new(%arguments)->create_build_script;
