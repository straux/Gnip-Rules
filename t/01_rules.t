use strict;
use warnings;

use Test::More; # tests => 1;
use Test::Exception;
use JSON;

use Gnip::Rules;

my $client;
lives_ok( sub {
    $client = Gnip::Rules->new( context => {
        gnip => {
            collector_id => 1,
            user => 'foo',
            password => 'bar',
            base_url => 'http://localhost/',
            spore_spec => 't/spore-spec/gnip.json',
        },
    }, );
}, "Instanciate the client" );

my $cb;
my $mock_server    = {
    '/data_collectors/1/rules.json' => sub {
        my $req = shift;
        $req->new_response( $cb->( $req ) );
        #use YAML;
        #print Dump $req->{env};
        #my $params =
          #defined $req->{env}->{'spore.params'}
          #? $req->{env}->{'spore.params'}
          #: [];

        #my $p = @$params ? join( ' -> ', @$params ) : '';
        #$req->new_response( $cb->( $req ) );
            #200,
            #[ 'Content-Type' => 'text/plain' ],
            #'{ "status" : "ok", "params" : "' . $p . '" }'
        #);
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

done_testing();

