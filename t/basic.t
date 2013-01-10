use 5.008001;
use strict;
use warnings;
use Test::More 0.96;
use Test::Deep qw/!blessed/;

use Session::Storage::Secure;

my $data = {
  foo => 'bar',
  baz => 'bam',
};

my $secret = "serenade viscount secretary frail";

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

subtest "defaults" => sub {
  my $store = _gen_store;
  cmp_deeply( $store->decode( $store->encode( $data ) ), $data, "roundtrip" );
};

# future expiration

# past expiration

# future default duration

# past default duration

# changed key

# modified message


done_testing;
# COPYRIGHT
