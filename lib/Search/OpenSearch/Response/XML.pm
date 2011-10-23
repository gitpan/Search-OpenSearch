package Search::OpenSearch::Response::XML;
use strict;
use warnings;
use Carp;
use base qw( Search::OpenSearch::Response );
use Data::Dump qw( dump );
use Search::Tools::XML;
use Encode;
use URI::Encode qw( uri_encode );
use POSIX qw( strftime );
use Data::UUID;

our $VERSION = '0.15';

my $XMLer = Search::Tools::XML->new;

my $header = <<EOF;
<?xml version="1.0" encoding="UTF-8"?>
 <feed xmlns="http://www.w3.org/2005/Atom" 
       xmlns:opensearch="http://a9.com/-/spec/opensearch/1.1/">
EOF

sub stringify {
    my $self       = shift;
    my $pager      = $self->build_pager();
    my $UUID_maker = Data::UUID->new;
    my @entries    = $self->_build_entries;

    my $now = strftime '%Y-%m-%dT%H:%M:%SZ', gmtime;

    my $query_encoded = uri_encode( $self->query );
    my $this_uri
        = $self->link
        . '?format=XML&q='
        . $query_encoded . '&p='
        . $self->page_size;

    my $self_link = $XMLer->singleton(
        'link',
        {   rel  => 'self',
            href => $this_uri . '&o=' . $self->offset
        }
    );

    my $feed = $XMLer->perl_to_xml(
        {   title                     => $self->title,
            author                    => $self->author,
            updated                   => $now,
            'opensearch:totalResults' => $self->total,
            'opensearch:startIndex'   => $self->offset,
            'opensearch:itemsPerPage' => $self->page_size,
            'id' =>
                $UUID_maker->create_from_name_str( NameSpace_URL, $self_link,
                ),
            'facets'      => $self->facets,
            'search_time' => $self->search_time,
            'build_time'  => $self->build_time,
            engine        => $self->engine,
        },
        'feed', 1
    );
    $feed =~ s,</?feed>,,g;    # strip wrapper tags for now

    # TODO language, et al
    $feed .= $XMLer->singleton(
        'opensearch:Query',
        {   role         => 'request',
            totalResults => $self->total,
            searchTerms  => $self->query,
            startIndex   => $self->offset,
        }
    );

    # main link
    my $link = $XMLer->singleton( 'link', { href => $self->link } );

    # pager links
    my @pager_links;
    push @pager_links, $self_link;

    unless ( $pager->current_page == $pager->first_page ) {
        my $prev_link = $XMLer->singleton(
            'link',
            {   rel  => 'previous',
                href => $this_uri . '&o='
                    . ( $self->offset - $self->page_size )
            }
        );
        push @pager_links, $prev_link;
        my $first_link = $XMLer->singleton(
            'link',
            {   rel  => 'first',
                href => $this_uri . '&o=0',
            }
        );
        push @pager_links, $first_link;
    }
    unless ( $pager->current_page == $pager->last_page ) {
        my $next_link = $XMLer->singleton(
            'link',
            {   rel  => 'next',
                href => $this_uri . '&o='
                    . ( $self->offset + $self->page_size )
            }
        );
        push @pager_links, $next_link;
        my $last_page = $XMLer->singleton(
            'link',
            {   rel  => 'last',
                href => $this_uri . '&o='
                    . ( $self->page_size * ( $pager->last_page - 1 ) )
            }
        );
        push @pager_links, $last_page;
    }

    # add to feed
    for (@pager_links) {
        $feed .= $_;
    }

    # results
    for my $entry (@entries) {
        $feed .= $entry;
    }

    # add the tags back
    $feed = $header . $feed . "</feed>";

    # make sure we have utf8 bytes. tidy() will return UTF-8 decoded
    # string, so we just encode it back to bytes.
    # This specifically fixes behaviour under Plack, which requires
    # bytes, not characters.
    return Encode::encode_utf8( $XMLer->tidy($feed) );

}

sub _build_entries {
    my $self    = shift;
    my $results = $self->results;
    my @entries;

    #my $UUID_maker = Data::UUID->new;

    for my $result (@$results) {
        my $entry = $XMLer->perl_to_xml(
            {   title   => $result->{title},
                content => $result->{summary},
                id      => $result->{uri},       # or uuid?
            },
            'entry',
            1,
            1
        );
        my $link = $XMLer->singleton( 'link', { href => $result->{uri} } );
        $entry =~ s,</entry>,$link</entry>,;
        push @entries, $entry,;
    }
    return @entries;
}

1;

__END__

=head1 NAME

Search::OpenSearch::Response::XML - provide search results in XML format

=head1 SYNOPSIS

 use Search::OpenSearch;
 my $engine = Search::OpenSearch->engine(
    type    => 'KSx',
    index   => [qw( path/to/index1 path/to/index2 )],
    facets  => {
        names       => [qw( color size flavor )],
        sample_size => 10_000,
    },
    fields  => [qw( color size flavor )],
 );
 my $response = $engine->search(
    q           => 'quick brown fox',   # query
    s           => 'rank desc',         # sort order
    o           => 0,                   # offset
    p           => 25,                  # page size
    h           => 1,                   # highlight query terms in results
    c           => 0,                   # return count stats only (no results)
    L           => 'field|low|high',    # limit results to inclusive range
    f           => 1,                   # include facets
    r           => 1,                   # include results
    format      => 'XML',               # or JSON
 );
 print $response;

=head1 DESCRIPTION

Search::OpenSearch::Response::XML serializes to XML following
the OpenSearch specification at 
http://www.opensearch.org/Specifications/OpenSearch/1.1.

=head1 METHODS

This class is a subclass of Search::OpenSearch::Response. 
Only new or overridden methods are documented here.

=head2 stringify

Returns the Response in XML format.

Response objects are overloaded to call stringify().

=head1 AUTHOR

Peter Karman, C<< <karman at cpan.org> >>

=head1 BUGS

Please report any bugs or feature requests to C<bug-search-opensearch at rt.cpan.org>, or through
the web interface at L<http://rt.cpan.org/NoAuth/ReportBug.html?Queue=Search-OpenSearch>.  I will be notified, and then you'll
automatically be notified of progress on your bug as I make changes.

=head1 SUPPORT

You can find documentation for this module with the perldoc command.

    perldoc Search::OpenSearch::Response


You can also look for information at:

=over 4

=item * RT: CPAN's request tracker

L<http://rt.cpan.org/NoAuth/Bugs.html?Dist=Search-OpenSearch>

=item * AnnoCPAN: Annotated CPAN documentation

L<http://annocpan.org/dist/Search-OpenSearch>

=item * CPAN Ratings

L<http://cpanratings.perl.org/d/Search-OpenSearch>

=item * Search CPAN

L<http://search.cpan.org/dist/Search-OpenSearch/>

=back

=head1 COPYRIGHT & LICENSE

Copyright 2010 Peter Karman.

This program is free software; you can redistribute it and/or modify it
under the terms of either: the GNU General Public License as published
by the Free Software Foundation; or the Artistic License.

See http://dev.perl.org/licenses/ for more information.


=cut
