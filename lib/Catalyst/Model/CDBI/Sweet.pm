package Catalyst::Model::CDBI::Sweet;

use strict;
use base qw[Class::DBI Catalyst::Base];

use Data::Page;
use Data::UUID;
use DBI;
use List::Util;
use SQL::Abstract;

# Catalyst component

our $VERSION = '0.01';

sub new {
    my ( $class, $c ) = @_;

    my $self = Catalyst::Base::new( $class, $c );

    unless ( $class eq __PACKAGE__ ) {
        no strict 'refs';
        no warnings 'redefine';
        *{"$class\::new"} = sub { Class::DBI::new( $class, @_ ) };
    }

    return $self;
}

sub process { 1 }

#----------------------------------------------------------------------
# RETRIEVING
#----------------------------------------------------------------------

__PACKAGE__->data_type(
    __ROWS   => DBI::SQL_INTEGER,
    __OFFSET => DBI::SQL_INTEGER
);

__PACKAGE__->set_sql( Count => <<'SQL' );
SELECT COUNT(*)
FROM   __TABLE__
WHERE  %s
SQL

sub count {
    my $proto = shift;
    my $class = ref($proto) || $proto;

    my ( $query, $attributes ) = $class->_search_args(@_);

    # make sure we take copy of $attribues since it can be reused
    my $count = { %{$attributes} };

    # no need for LIMIT/OFFSET and ORDER BY in COUNT(*)
    delete @{$count}{qw( rows offset order_by )};

    my ( $sql, $columns, $values ) = $proto->_search( $query, $count );

    my $sth = $class->sql_Count($sql);

    $class->_bind_param( $sth, $columns );

    return $sth->select_val(@$values);
}

sub search {
    my $proto = shift;
    my $class = ref($proto) || $proto;

    my ( $query, $attributes ) = $class->_search_args(@_);

    my ( $sql, $columns, $values ) = $proto->_search( $query, $attributes );

    my $sth = $class->sql_Retrieve($sql);

    $class->_bind_param( $sth, $columns );

    my $iterator = $class->sth_to_objects( $sth, $values );

    # If RDBM is not ROWS/OFFSET supported, slice iterator
    if ( $attributes->{rows} && $iterator->count > $attributes->{rows} ) {

        my $rows   = $attributes->{rows};
        my $offset = $attributes->{offset} || 0;

        warn sprintf( "slicing iterator, o: %d r: %d\n", $offset, $rows );

        $iterator = $iterator->slice( $offset, $offset + $rows - 1 );
    }

    return map $class->construct($_), $iterator->data if wantarray;
    return $iterator;
}

sub page {
    my $proto = shift;
    my $class = ref($proto) || $proto;

    my ( $query, $attributes ) = $proto->_search_args(@_);

    my $total = $class->count( $query, $attributes );
    my $rows    = $attributes->{rows} || 10;
    my $current = $attributes->{page} || 1;

    my $page = Data::Page->new( $total, $rows, $current );

    $attributes->{rows}   = $page->entries_per_page;
    $attributes->{offset} = $page->skipped;

    my $iterator = $class->search( $query, $attributes );

    return ( $page, $iterator );
}

sub _search {
    my $proto      = shift;
    my $query      = shift;
    my $attributes = shift;
    my $class      = ref($proto) || $proto;

    # Valid SQL::Abstract params
    my %params = map { $_ => $attributes->{$_} } qw(case cmp convert logic);

    # Overide bindtype, we need all columns and values for deflating
    my $abstract = SQL::Abstract->new( %params, bindtype => 'columns' );

    my ( $sql, @bind ) = $abstract->where( $query, $attributes->{order_by} );

    $sql =~ s/^\s*(WHERE)\s*//i;

    my ( @columns, @values, %cache );

    while ( my $bind = shift(@bind) ) {

        my $col    = shift(@$bind);
        my $column = $cache{$col};

        unless ($column) {

            $column = $class->find_column($col)
              || ( List::Util::first { $_->accessor eq $col } $class->columns )
              || $class->_croak("$col is not a column of $class");

            $cache{$col} = $column;
        }

        while ( my $value = shift(@$bind) ) {
            push( @columns, $column );
            push( @values, $class->_deflated_column( $column, $value ) );
        }
    }

    if ( $attributes->{rows} ) {

        my $rows   = $attributes->{rows};
        my $offset = $attributes->{offset} || 0;
        my $driver = $class->db_Main->{Driver}->{Name};

        if ( $driver =~ /^(maxdb|mysql|mysqlpp)$/ ) {
            $sql .= ' LIMIT ?, ?';
            push( @columns, '__OFFSET', '__ROWS' );
            push( @values, $offset, $rows );
        }

        if ( $driver =~ /^(pg|pgpp|sqlite|sqlite2)$/ ) {
            $sql .= ' LIMIT ?, OFFSET ?';
            push( @columns, '__ROWS', '__OFFSET' );
            push( @values, $rows, $offset );
        }

        if ( $driver =~ /^(interbase)$/ ) {
            $sql .= ' ROWS ? TO ?';
            push( @columns, '__ROWS', '__OFFSET' );
            push( @values, $rows, $offset + $rows );
        }
    }

    return ( $sql, \@columns, \@values );
}

sub _search_args {
    my $proto = shift;

    my ( $query, $attributes );

    if ( @_ == 2 && ref( $_[0] ) =~ /^(ARRAY|HASH)$/ && ref( $_[1] ) eq 'HASH' )
    {
        $query      = $_[0];
        $attributes = $_[1];
    }
    elsif ( @_ == 1 && ref( $_[0] ) =~ /^(ARRAY|HASH)$/ ) {
        $query      = $_[0];
        $attributes = {};
    }
    else {
        $attributes = @_ % 2 ? pop(@_) : {};
        $query = {@_};
    }

    return ( $query, $attributes );
}

#----------------------------------------------------------------------
# CACHING
#----------------------------------------------------------------------

__PACKAGE__->mk_classdata('cache');

sub cache_key {
    my $proto = shift;
    my $class = ref($proto) || $proto;
    my $data;

    my @primary_columns = $class->primary_columns;

    if (@_) {
        if ( @_ == 1 && ref( $_[0] ) eq 'HASH' ) {
            $data = $_[0];
        }
        elsif ( @_ == 1 ) {
            $data = { $primary_columns[0] => $_[0] };
        }
        else {
            $data = {@_};
        }
    }
    else {
        @{$data}{@primary_columns} = $proto->get(@primary_columns);
    }

    unless ( @primary_columns == grep defined, @{$data}{@primary_columns} ) {
        return;
    }

    return join "|", $class, map $_ . '=' . $data->{$_}, sort @primary_columns;
}

sub _init {
    my $class = shift;

    unless ( $class->cache ) {
        return $class->SUPER::_init(@_);
    }

    my $data = shift || {};
    my $key  = $class->cache_key($data);

    my $object;

    if ( $key and $object = $class->cache->get($key) ) {
        return $object;
    }

    $object = bless {}, $class;
    $object->_attribute_store(%$data);

    if ($key) {
        $class->cache->set( $key, $object );
    }

    return $object;
}

sub retrieve {
    my $class = shift;

    if ( $class->cache ) {

        if ( my $key = $class->cache_key(@_) ) {

            if ( my $object = $class->cache->get($key) ) {
                $object->call_trigger('select');
                return $object;
            }
        }
    }

    return $class->SUPER::retrieve(@_);
}

sub update {
    my $self = shift;

    if ( $self->cache ) {
        $self->cache->remove( $self->cache_key );
    }

    return $self->SUPER::update(@_);
}

sub delete {
    my $self = shift;

    if ( $self->cache ) {
        $self->cache->remove( $self->cache_key );
    }

    return $self->SUPER::delete(@_);
}

#----------------------------------------------------------------------
# UNIVERSALLY UNIQUE IDENTIFIERS
#----------------------------------------------------------------------

sub _next_in_sequence {
    my $self = shift;

    if ( lc $self->sequence eq 'uuid' ) {
        return Data::UUID->new->create_str;
    }

    return $self->sql_Nextval( $self->sequence )->select_val;
}

1;

__END__

=head1 NAME

    Catalyst::Model::CDBI::Sweet - Making sweet things sweeter

=head1 SYNOPSIS

    package MyApp::Model::Article;
    use base 'Catalyst::Model::CDBI::Sweet';

    use DateTime;

    __PACKAGE__->table('article');
    __PACKAGE__->columns( Primary   => qw[ id ] );
    __PACKAGE__->columns( Essential => qw[ title created_on created_by ] );

    __PACKAGE__->has_a(
        created_on => 'DateTime',
        inflate    => sub { DateTime->from_epoch( epoch => shift ) },
        deflate    => sub { shift->epoch }
    );

    MyApp::Model::Article->connection('DBI:driver:database');


    package MyApp::Controller::Article;

    # Simple search, backwards compatible with C<Class::DBI->search>

    MyApp::Model::Article->search( created_by => 'sri', { order_by => 'title' } );

    MyApp::Model::Article->count( created_by => 'sri' );

    MyApp::Model::Article->page( created_by => 'sri', { page => 5 } );


    # More powerful search with deflating

    $query = {
        created_on => {
            -between => [
                DateTime->new( year => 2004 ),
                DateTime->new( year => 2005 ),
            ]
        },
        created_by => [ qw(chansen draven gabb sri) ],
        title      => {
            -like  => [ qw( perl% catalyst% ) ]
        }
    };

    MyApp::Model::Article->search( $query, { rows => 30 } );

    MyApp::Model::Article->count($query);

    MyApp::Model::Article->page( $query, { rows => 10, page => 2 } );


=head1 DESCRIPTION

Catalyst::Model::CDBI::Sweet provides convenient count, search, page and
cache functions in a sweet package. It integrates this functions with
C<Class::DBI> in a convenient and efficient way.

=head1 RETRIEVING OBJECTS

All retrieving methods can take the same query and attributes. Query is the
only required parameter.

=head4 query

Can be a hash, hashref or a arrayref. Takes the same options as
L<SQL::Abstract> where method. If values contain any objects they will be
deflated before querying database.

=head4 attributes

=over 4

=item case, cmp, convert and logic

These attributes are passed to L<SQL::Abstact>'s constuctor and alter the
behavior of query.

    { cmp => 'like' }

=item order_by

Specifies the sort order of the results.

    { order_by => 'created_on DESC' }

=item rows

Specifies the maximum number of rows to return. Currently supported RDBM's is
Interbase, MaxDB, MySQL, PostgreSQL and SQLite. For other RDBM's it will be
emulated.

    { rows => 10 }

=item offset

Specifies the offset of the first row to return. Defaults to 0 if unspecified.

    { offest => 0 }

=item page

Specifies the current page in C<page>. Defaults to 1 if unspecified.

    { page => 1 }

=back

=head2 count

Returns a count of the number of rows matching query. C<count> will discard
C<offset>, C<order_by> and C<rows>.

    $count = MyApp::Model::Article->count(%query);

=head2 search

Returns an iterator in scalar context and a array of objects in list context.

    @objects  = MyApp::Model::Article->search(%query);

    $iterator = MyApp::Model::Article->search(%query);

=head2 page

Retuns a page object and a iterator. Page object is an instance of
L<Data::Page>.

    ( $page, $iterator ) = MyApp::Model::Article->page( $query, { rows => 10, page => 2 );

    printf( "Results %d - %d of %d Found\n",
        $page->first, $page->last, $page->total_entries );


=head1 CACHING OBJECTS

Objects will be stored deflated in cache. Only C<Primary> and C<Essential>
columns will be cached.

=head2 cache

Class method, if this is set caching is enabled. Any cache object that has a
C<get>, C<set> and C<remove> method is supported.

    __PACKAGE__->cache(
        Cache::FastMmap->new(
            share_file => '/tmp/cdbi',
            expire_time => 3600
        )
    );

=head2 cache_key

returns a cache key for a object consisting of class and primary keys.

=head4 Overloaded methods

=over 4

=item _init

Overrides C<Class::DBI>'s internal cache. On cache hit it will return a cached
object, on cache miss it will create an new object and store it in cache.

=item retrieve

On cache hit the object will be inflated by C<select> trigger and then served.

=item update

Object is removed from cache and will be cached on next retrieval.

=item delete

Object is removed from cache.

=back

=head1 UNIVERSALLY UNIQUE IDENTIFIERS

If enabled a UUID string will be generated for primary column. A CHAR(36)
column is suitable for storage.

    __PACKAGE__->sequence('uuid');

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

L<Class::DBI>

L<Data::Page>

L<Data::UUID>

L<SQL::Abstract>

L<http://cpan.robm.fastmail.fm/cache_perf.html>
An comparison of different cahing modules for perl.

=cut
