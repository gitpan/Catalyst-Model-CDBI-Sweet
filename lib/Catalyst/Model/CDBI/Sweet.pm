package Catalyst::Model::CDBI::Sweet;

use strict;
use base qw[Class::DBI::Sweet Catalyst::Base];

our $VERSION = '0.04';

*new = \&Catalyst::Base::new;

1;

__END__

=head1 NAME

    Catalyst::Model::CDBI::Sweet - Making sweet things sweeter

=head1 SYNOPSIS

    package MyApp::Model::CDBI;
    use base 'Catalyst::Model::CDBI::Sweet';
    MyApp::Model::CDBI->connection('DBI:driver:database');
    
    package MyApp::Model::Article;
    use base 'MyApp::Model::CDBI';
    
    use DateTime;
    
    __PACKAGE__->table('article');
    __PACKAGE__->columns( Primary   => qw[ id ] );
    __PACKAGE__->columns( Essential => qw[ title created_on created_by ] );
    
    __PACKAGE__->has_a(
        created_on => 'DateTime',
        inflate    => sub { DateTime->from_epoch( epoch => shift ) },
        deflate    => sub { shift->epoch }
    );
    
    # Simple search
    
    MyApp::Model::Article->search( created_by => 'sri', { order_by => 'title' } );
    
    MyApp::Model::Article->count( created_by => 'sri' );
    
    MyApp::Model::Article->page( created_by => 'sri', { page => 5 } );
    
    MyApp::Model::Article->retrieve_all( order_by => 'created_on' );
    
    
    # More powerful search with deflating
    
    $criteria = {
        created_on => {
            -between => [
                DateTime->new( year => 2004 ),
                DateTime->new( year => 2005 ),
            ]
        },
        created_by => [ qw(chansen draven gabb jester sri) ],
        title      => {
            -like  => [ qw( perl% catalyst% ) ]
        }
    };
    
    MyApp::Model::Article->search( $criteria, { rows => 30 } );
    
    MyApp::Model::Article->count($criteria);
    
    MyApp::Model::Article->page( $criteria, { rows => 10, page => 2 } );
    
    
    # Using Catalyst::Model::CDBI::Sweet with Catalyst::Model::CDBI
    
    package MyApp::Model::CDBI;
    use base 'Catalyst::Model::CDBI';
    
    use Catalyst::Model::CDBI::Sweet;
    
    __PACKAGE__->config(
        dsn           => 'dbi:driver:dbname',
        password      => 'username',
        user          => 'password',
        relationships => 1
    );
    
    sub new {
         my $class = shift;
    
         my $self = $class->NEXT::new(@_);
    
         foreach my $subclass ( $self->loader->classes ) {
             no strict 'refs';
             unshift @{ $subclass . '::ISA' }, 'Catalyst::Model::CDBI::Sweet';
         }
    
         return $self;
    }


=head1 DESCRIPTION

This is the Catalyst::Model::CDBI::Sweet model class. It's built on top of 
Class::DBI::Sweet.

=head1 AUTHOR

Christian Hansen <ch@ngmedia.com>

=head1 THANKS TO

Danijel Milicevic, Jesse Sheidlower, Marcus Ramberg, Sebastian Riedel,
Viljo Marrandi

=head1 SUPPORT

#catalyst on L<irc://irc.perl.org>

L<http://lists.rawmode.org/mailman/listinfo/catalyst>

L<http://lists.rawmode.org/mailman/listinfo/catalyst-dev>

=head1 LICENSE

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=head1 SEE ALSO

L<Catalyst>

L<Class::DBI::Sweet>

=cut
