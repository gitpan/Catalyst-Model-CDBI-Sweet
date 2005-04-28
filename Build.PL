use strict;
use Module::Build;

my $build = Module::Build->new(
    create_makefile_pl => 'passthrough',
    license            => 'perl',
    module_name        => 'Catalyst::Model::CDBI::Sweet',
    requires           => {
        Catalyst        => 5,
        'Data::Page'    => 0,
        'Data::UUID'    => 0,
        DBI             => 0,
        'Class::DBI'    => 0,
        'List::Util'    => 0,
        'SQL::Abstract' => 0
    },
    create_makefile_pl => 'passthrough',
    test_files         => [ glob('t/*.t') ]
);
$build->create_build_script;
