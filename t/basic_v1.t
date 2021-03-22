use 5.008001;
use strict;
use warnings;
use Test::More 0.96;

$ENV{Session_Storage_Secure_Version} = 1;

note "Running basic tests with protocol version 1";

do './t/basic.t' or die $@ || $!;

# COPYRIGHT
