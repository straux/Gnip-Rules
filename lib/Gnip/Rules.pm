package Gnip::Rules;

use Moose;
use Net::HTTP::Spore;

has user         => ( isa => 'Str', is => 'ro', required => 1 );
has password     => ( isa => 'Str', is => 'ro', required => 1 );
has spore_spec   => ( isa => 'Str', is => 'ro', required => 1 );
has base_url     => ( isa => 'Str', is => 'ro', required => 1 );
has collector_id => ( isa => 'Str', is => 'rw', required => 1 );

has 'gnip' => (
    isa => 'Object',
    is => 'ro',
    lazy => 1,
    default => sub {
        my $self = shift;
        my $spore = Net::HTTP::Spore->new_from_spec( $self->spore_spec,
            base_url => $self->base_url, );
        $spore->enable('Format::JSON');
        $spore->enable('Auth::Basic',
            username => $self->user, password => $self->password );
        $spore;
    },
);

has bulk_size => ( isa => 'Int', is => 'ro', default => '5000' );

sub get_rules {
    my ( $self, %opt ) = @_;

    my $rules = $self->gnip->get_rules( collector_id => $self->collector_id, format => 'json' )->body;
    $rules = $self->filter_rules( $rules, %opt ) if( defined $opt{filter} );
    $rules;
}

sub set_rules {
    my ( $self, $rules, ) = @_;
    die "rules must be an HASH ref\n" unless ref $rules eq 'HASH';
    $self->_bulk_rules(
        collector_id => $self->collector_id,
        format => 'json',
        payload => $rules,
    );
    1;
}

sub delete_rules {
    my ( $self, $rules, ) = @_;
    die "rules must be an HASH ref\n" unless ref $rules eq 'HASH';
    $self->_bulk_rules(
        collector_id => $self->collector_id,
        format => 'json',
        _method => 'delete',
        payload => $rules,
    );
    1;
}

sub _bulk_rules {
    my ( $self, %params ) = @_;
    my $rules = delete( $params{payload} )->{rules};
    my $i = 0;
    my $size = scalar @$rules;
    while( ($i * $self->bulk_size) < $size ) {
        my $next = ($i+1) * $self->bulk_size;
        $next = $size if $size < $next;
        $self->gnip->set_rules(
            %params,
            payload => {
                rules => [ @$rules[($i*$self->bulk_size)..($next-1)] ],
            },
        );
        $i++;
    }
}

sub update_rules {
    my ( $self, $rules, %opt ) = @_;

    my $verbose = delete $opt{verbose};
    my $old_rules = delete $opt{old_rules};

    $old_rules ||= $self->get_rules( %opt );

    my $old = {};
    my $new = [];
    for( @{ $old_rules->{rules} } ) {
        $old->{ $_->{value} } = $_;
    }
    for( @{ $rules->{rules} } ) {
        my $same = 0;
        if( defined $old->{ $_->{value} } &&
            _same_rules( $_, $old->{ $_->{value} } )) {
            delete $old->{ $_->{value} };
            $same = 1;
        }
        push( @$new, $_ ) unless $same;
    }

    my $nb_add    = scalar @$new;
    my $nb_delete = scalar keys %$old;

    $self->delete_rules( { rules => [ values %$old ] } ) if $nb_delete;
    $self->set_rules( { rules => $new } ) if $nb_add;

    my $result = {
        nb_add => $nb_add,
        nb_delete => $nb_delete,
    };
    if( $verbose ) {
        $result->{add} = $new;
        $result->{delete} = [ values %$old ];
    }
    $result;
}

sub filter_rules {
    my ( $self, $rules, %opt ) = @_;

    my $filter = delete $opt{filter};
    return $rules unless $filter;

    if( ref $filter eq 'ARRAY' ) {
        my %f;
        @f{ @$filter } = ( 1 ) x scalar @$filter;
        $filter = \%f;
    }
    { rules => [grep {defined $_->{tag} && defined $filter->{$_->{tag}}} @{$rules->{rules}}] };
}

sub _same_rules {
    my ( $r1, $r2, ) = @_;

    my $cmp = $r1->{value} eq $r2->{value};
    if( $cmp ) {
       $cmp = ($r1->{tag} || '') eq ($r2->{tag} || '');
    }
    $cmp;
}

no Moose;

1;
__END__

=encoding utf-8

=head1 NAME

Gnip::Rules - REST client managing rules for Gnip API

=head1 SYNOPSIS

    use Gnip::Rules;
    use Try::Tiny;

    my $client = Gnip::Rules->new(
        user => 'user',
        password => 'password',
        base_url => 'https://gnipboxname.gnip.com/',
        spore_spec => 'spore-spec/gnip.json',
        collector_id => 1,
    );

    # get rules
    try {
        my $rules = $client->get_rules;
    } catch {
        die $_->raw_body."\n";
    };

    # set rules
    try {
        my $rules = $client->set_rules({
            rules => [
                { value => "rule" },
                { value => "rule_with_tag", tag => "tag" },
            ]
        });
    } catch {
        die $_->raw_body."\n";
    };

    # delete rules
    try {
        my $rules = $client->delete_rules({
            rules => [
                { value => "rule" },
                { value => "rule_with_tag", tag => "tag" },
            ]
        });
    } catch {
        die $_->raw_body."\n";
    };

=head1 DESCRIPTION

Gnip::Rules is an REST client managing rules for Gnip API,
available at L<http://docs.gnip.com/w/page/23733233/Rules%20Methods%20Documentation>

=head1 METHODS

=head2 my $client = Gnip::Rules->new( %args );

=over 4

=item B<user>, B<password>

Credentials for authentification.

=item B<base_url>

Base URL for the API, including your B<gnipboxname>.

=item B<spore_spec>

Path to L<Net::HTTP::Spore> specification file (see B<spore-spec/gnip.json> in the package).

=item B<collector_id>

Id of the collector to update.

=back

=head2 get_rules( %opt )

=head2 set_rules( \%rules )

=head2 delete_rules( \%rules )

=head2 update_rules( \%rules, %opt )

=head1 NOTES

The API uses the HTTPS protocol. For this, you need to install the L<Net::SSLeay> module.

=head1 AUTHOR

Stéphane Raux E<lt>stephane.raux@linkfluence.netE<gt>

=head1 LICENSE

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=head1 SEE ALSO

L<AnyEvent::Gnip::Stream> L<Net::HTTP::Spore>

=cut

