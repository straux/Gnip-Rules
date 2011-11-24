#/usr/bin/env perl

use strict;
use warnings;

use Test::More tests => 12;
use Test::Exception;
use JSON;

use Gnip::Rules;

my $client;
lives_ok( sub {
    $client = Gnip::Rules->new(
        user => 'foo',
        password => 'bar',
        base_url => 'http://localhost/',
        spore_spec => 'spore-spec/gnip.json',
        account => 'account',
        publisher => 'twitter',
        bulk_size => 10,
    );
}, "Instanciate the client" );

my $cb;
my $mock_server    = {
    '/accounts/account/publishers/twitter/streams/track/prod/rules.json' => sub {
        my $req = shift;
        $req->new_response( $cb->( $req ) );
    },
};
$client->gnip->enable( 'Mock', tests => $mock_server );

# get rules

my $rules = {
    rules => [
        { value => 'rule1' },
        { value => 'rule2', tag => 'tag1', },
        { value => 'rule3', tag => 'tag2', },
        { value => 'rule4', tag => 'tag1',  },
    ],
};

my $filtered = {
    rules => [
        { value => 'rule2', tag => 'tag1', },
        { value => 'rule4', tag => 'tag1',  },
    ],
};

$cb = sub {
    ( 200, [ 'Content-Type' => 'text/plain' ], encode_json( $rules ) );
};

is_deeply( $client->get_rules, $rules, 'get rules' );
is_deeply( $client->get_rules( filter => { tag1 => 1 }), $filtered, 'get rules - filter with HASH' );
is_deeply( $client->get_rules( filter => ['tag1']), $filtered, 'get rules - filter with ARRAY' );

# same rules ?

my @tests = (
    [ { value => 'rule1' }, { value => 'rule1' }, 1, 'same rules' ],
    [ { value => 'rule1', tag => '1' }, { value => 'rule1', tag => '1' }, 1, 'same rules, same tag' ],
    [ { value => 'rule1', tag => '1' }, { value => 'rule1', tag => '2' }, '', 'same rules, different tags' ],
    [ { value => 'rule1', tag => '1' }, { value => 'rule1', }, '', 'same rules, tag, no tag' ],
    [ { value => 'rule1', }, { value => 'rule1', tag => '1' }, '', 'same rules, no tag, tag' ],
    [ { value => 'rule1' }, { value => 'rule2' }, '', 'different rules' ],
);

foreach my $test ( @tests ) {
    is( Gnip::Rules::_same_rules( $test->[0], $test->[1] ), $test->[2], $test->[3] );
}

# update rules

$rules = {
    rules => [
        { value => 'rule1' },
        { value => 'rule2', tag => 'tag1', },
        { value => 'rule3', tag => 'tag2', },
        { value => 'rule4', tag => 'tag1',  },
    ],
};

my $update = {
    rules => [
        { value => 'rule2', tag => 'tag1', },
        { value => 'rule3', tag => 'tag2', },
        { value => 'rule4', tag => 'tag2',  },
        { value => 'rule5', tag => 'tag',  },
    ],
};

my $delete = [
    { value => 'rule4', tag => 'tag1',  },
    { value => 'rule1' },
];

my $add = [
    { value => 'rule4', tag => 'tag2',  },
    { value => 'rule5', tag => 'tag',  },
];

my $check = {
   nb_add => 2,
   nb_delete => 2,
   add => $add,
   delete => $delete,
};

$cb = sub {
    my $req = shift;
    my $method = $req->{env}->{REQUEST_METHOD};
    my $rc = $method eq 'GET' ? '200' : '201';
    ( $rc, [ 'Content-Type' => 'text/plain' ], encode_json( $rules ) );
};

is_deeply( $client->update_rules( $update, verbose => 1 ), $check, 'update rules' );

# _bulk_rules

sub generate {
    my $rules = [];
    push(@$rules, { value => 'rules_'.$_ }) for @_;
    { rules => $rules };
}

$rules = generate( 0..26 );
$check = [
    generate( 0..9 ),
    generate( 10..19 ),
    generate( 20..26 ),
];
my @bulk = ();

$cb = sub {
    push @bulk, decode_json shift->{env}->{'spore.payload'};
    ( 201, [ 'Content-Type' => 'text/plain' ], '{ "ok":"1"}' );
};

$client->set_rules( $rules );
is_deeply( [ @bulk ], $check, 'bulk rules' );

done_testing();

