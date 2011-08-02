package Gnip::Rules;

use Moose;
use Net::HTTP::Spore;
use Try::Tiny;

has 'context' => (
    isa => 'HashRef',
    is  => 'rw',
    required => 1,
);

has 'gnip' => (
    isa => 'Object',
    is => 'ro',
    lazy => 1,
    default => sub {
        my $self = shift;
        my $gnip = $self->context->{gnip};
        my $spore = Net::HTTP::Spore->new_from_spec( $gnip->{spore_spec}, base_url => $gnip->{base_url}, );
        $spore->enable('Format::JSON');
        $spore->enable('Auth::Basic', username => $gnip->{user}, password => $gnip->{password} );
        $spore;
    },
);

has 'collector_id' => (
    isa => 'Str',
    is => 'rw',
    lazy => 1,
    default => sub {
        my $context = shift->context->{gnip};
        die "collector_id must be defined\n"
            unless( defined $context && defined $context->{collector_id} );
        $context->{collector_id};
    }
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

