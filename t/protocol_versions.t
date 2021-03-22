use 5.008001;
use strict;
use warnings;
use Test::More 0.96;
use Test::Fatal;
use Test::Deep qw/!blessed/;

use Session::Storage::Secure;

my $data = {
    foo => 'bar',
    baz => 'bam',
};

my $secret     = "serenade viscount secretary frail";
my $old_secret = "tornados hypocrisy overhang exegesis";

sub _gen_store {
    my ($config) = @_;
    local $Test::Builder::Level = $Test::Builder::Level + 1;
    my $store = Session::Storage::Secure->new(
        secret_key => $secret,
        %{ $config || {} },
    );
    ok( $store, "created a storage object" );
    return $store;
}

subtest "pv2 object reads pv1 session" => sub {
    my $pv1_store = _gen_store( { protocol_version => 1 } );
    my $pv2_store = _gen_store;

    my $pv1_session = $pv1_store->encode($data);
    my $decoded     = $pv2_store->decode($pv1_session);
    cmp_deeply( $decoded, $data, "roundtrip" );
};

subtest "pv1 object reads pv2 session" => sub {
    my $pv1_store = _gen_store( { protocol_version => 1 } );
    my $pv2_store = _gen_store;

    my $pv2_session = $pv2_store->encode($data);
    my $decoded     = $pv1_store->decode($pv2_session);
    cmp_deeply( $decoded, $data, "roundtrip" );
};

subtest "pv2 object reads pv1 old secrets" => sub {
    my $pv1_store = _gen_store(
        {
            secret_key       => $old_secret,
            protocol_version => 1
        }
    );
    my $pv2_store = _gen_store(
        {
            old_secrets => [ $old_secret ]
        }
    );

    my $pv1_session = $pv1_store->encode($data);
    my $decoded     = $pv2_store->decode($pv1_session);
    cmp_deeply( $decoded, $data, "roundtrip" );
};

done_testing;
# COPYRIGHT
