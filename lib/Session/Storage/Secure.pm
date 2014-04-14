use 5.008001;
use strict;
use warnings;

package Session::Storage::Secure;
# ABSTRACT: Encrypted, expiring, compressed, serialized session data with integrity
# VERSION

use Carp                    (qw/croak/);
use Crypt::CBC              ();
use Crypt::Rijndael         ();
use Crypt::URandom          (qw/urandom/);
use Digest::SHA             (qw/hmac_sha256/);
use Math::Random::ISAAC::XS ();
use MIME::Base64 3.12 (qw/encode_base64url decode_base64url/);
use Sereal::Encoder ();
use Sereal::Decoder ();
use String::Compare::ConstantTime qw/equals/;
use namespace::clean;

use Moo;
use MooX::Types::MooseLike::Base 0.16 qw(:all);

#--------------------------------------------------------------------------#
# Attributes
#--------------------------------------------------------------------------#

=attr secret_key (required)

This is used to secure the session data.  The encryption and message
authentication key is derived from this using a one-way function.  Changing it
will invalidate all sessions.

=cut

has secret_key => (
    is       => 'ro',
    isa      => Str,
    required => 1,
);

=attr old_secrets

An optional array reference of strings containing old secret keys no longer
used for encyption but still supported for decrypting session data.

=cut

has old_secrets => (
    is  => 'ro',
    isa => ArrayRef [Str],
);

=attr default_duration

Number of seconds for which the session may be considered valid.  If an
expiration is not provided to C<encode>, this is used instead to expire the
session after a period of time.  It is unset by default, meaning that sessions
expiration is not capped.

=cut

has default_duration => (
    is        => 'ro',
    isa       => Int,
    predicate => 1,
);

has _encoder => (
    is      => 'lazy',
    isa     => InstanceOf ['Sereal::Encoder'],
    handles => { '_freeze' => 'encode' },
);

sub _build__encoder {
    my ($self) = @_;
    return Sereal::Encoder->new(
        {
            snappy         => 1,
            croak_on_bless => 1,
        }
    );
}

has _decoder => (
    is      => 'lazy',
    isa     => InstanceOf ['Sereal::Decoder'],
    handles => { '_thaw' => 'decode' },
);

sub _build__decoder {
    my ($self) = @_;
    return Sereal::Decoder->new(
        {
            refuse_objects => 1,
            validate_utf8  => 1,
        }
    );
}

has _rng => (
    is      => 'lazy',
    isa     => InstanceOf ['Math::Random::ISAAC::XS'],
    handles => { '_irand' => 'irand' },
);

sub _build__rng {
    my ($self) = @_;
    return Math::Random::ISAAC::XS->new( map { unpack( "N", urandom(4) ) } 1 .. 256 );
}

=method encode

  my $string = $store->encode( $data, $expires );

The C<$data> argument should be a reference to a data structure.  It must not
contain objects. If it is undefined, an empty hash reference will be encoded
instead.

The optional C<$expires> argument should be the session expiration time
expressed as epoch seconds.  If the C<$expires> time is in the past, the
C<$data> argument is cleared and an empty hash reference is encoded and returned.
If no C<$expires> is given, then if the C<default_duration> attribute is set, it
will be used to calculate an expiration time.

The method returns a string that securely encodes the session data.  All binary
components are base64 encoded.

An exception is thrown on any errors.

=cut

sub encode {
    my ( $self, $data, $expires ) = @_;
    $data = {} unless defined $data;

    # If expiration is set, we want to check it and possibly clear data;
    # if not set, we might add an expiration based on default_duration
    if ( defined $expires ) {
        $data = {} if $expires < time;
    }
    else {
        $expires = $self->has_default_duration ? time + $self->default_duration : "";
    }

    # Random salt used to derive unique encryption/MAC key for each cookie
    my $salt = $self->_irand;
    my $key = hmac_sha256( $salt, $self->secret_key );

    my $cbc = Crypt::CBC->new( -key => $key, -cipher => 'Rijndael' );
    my ( $ciphertext, $mac );
    eval {
        $ciphertext = encode_base64url( $cbc->encrypt( $self->_freeze($data) ) );
        $mac = encode_base64url( hmac_sha256( "$expires~$ciphertext", $key ) );
    };
    croak "Encoding error: $@" if $@;

    return join( "~", $salt, $expires, $ciphertext, $mac );
}

=method decode

  my $data = $store->decode( $string );

The C<$string> argument must be the output of C<encode>.

If the message integrity check fails or if expiration exists and is in
the past, the method returns undef or an empty list (depending on context).

An exception is thrown on any errors.

=cut

sub decode {
    my ( $self, $string ) = @_;
    return unless length $string;

    # Having a string implies at least salt; expires is optional; rest required
    my ( $salt, $expires, $ciphertext, $mac ) = split qr/~/, $string;
    return unless defined($ciphertext) && length($ciphertext);
    return unless defined($mac)        && length($mac);

    # Try to decode against all known secret keys
    my @secrets = ( $self->secret_key, @{ $self->old_secrets || [] } );
    my $key;
    CHECK: foreach my $secret (@secrets) {
        $key = hmac_sha256( $salt, $secret );
        my $check_mac =
          eval {
              encode_base64url( hmac_sha256( "$expires~$ciphertext", $key ) )
          };
        last CHECK if ( defined($check_mac)
            && length($check_mac)
            && equals( $check_mac, $mac ) # constant time comparison
        );
        undef $key;
    }

    # Check MAC integrity
    return unless defined($key);

    # Check expiration
    return if length($expires) && $expires < time;

    # Decrypt and deserialize the data
    my $cbc = Crypt::CBC->new( -key => $key, -cipher => 'Rijndael' );
    my $data;
    eval { $self->_thaw( $cbc->decrypt( decode_base64url($ciphertext) ), $data ) };
    croak "Decoding error: $@" if $@;

    return $data;
}

1;

=for Pod::Coverage method_names_here

=head1 SYNOPSIS

  my $store = Session::Storage::Secure->new(
    secret_key   => "your pass phrase here",
    default_duration => 86400 * 7,
  );

  my $encoded = $store->encode( $data, $expires );

  my $decoded = $store->decode( $encoded );

=head1 DESCRIPTION

This module implements a secure way to encode session data.  It is primarily
intended for storing session data in browser cookies, but could be used with
other backend storage where security of stored session data is important.

Features include:

=for :list
* Data serialization and compression using L<Sereal>
* Data encryption using AES with a unique derived key per encoded session
* Enforced expiration timestamp (optional)
* Integrity protected with a message authentication code (MAC)

The storage protocol used in this module is based heavily on
L<A Secure Cookie Protocol|http://www.cse.msu.edu/~alexliu/publications/Cookie/Cookie_COMNET.pdf>
by Alex Liu and others.  Liu proposes a session cookie value as follows:

  user|expiration|E(data,k)|HMAC(user|expiration|data|ssl-key,k)

  where

    | denotes concatenation with a separator character
    E(p,q) is a symmetric encryption of p with key q
    HMAC(p,q) is a keyed message hash of p with key q
    k is HMAC(user|expiration, sk)
    sk is a secret key shared by all servers
    ssl-key is an SSL session key

Because SSL session keys are not readily available (and SSL termination
may happen prior to the application server), we omit C<ssl-key>.  This
weakens protection against replay attacks if an attacker can break
the SSL session key and intercept messages.

Using C<user> and C<expiration> to generate the encryption and MAC keys
was a method proposed to ensure unique keys to defeat volume attacks
against the secret key.  Rather than rely on those for uniqueness, which
also reveals user name and prohibits anonymous sessions, we replace
C<user> with a cryptographically-strong random salt value.

The original proposal also calculates a MAC based on unencrypted
data.  We instead calculate the MAC based on the encrypted data.  This
avoids the extra step of decrypting invalid messages.  Because the
salt is already encoded into the key, we omit it from the MAC input.

Therefore, the session storage protocol used by this module is as follows:

  salt|expiration|E(data,k)|HMAC(expiration|E(data,k),k)

  where

    | denotes concatenation with a separator character
    E(p,q) is a symmetric encryption of p with key q
    HMAC(p,q) is a keyed message hash of p with key q
    k is HMAC(salt, sk)
    sk is a secret key shared by all servers

The salt value is generated using L<Math::Random::ISAAC::XS>, seeded from
L<Crypt::URandom>.

The HMAC algorithm is C<hmac_sha256> from L<Digest::SHA>.  Encryption
is done by L<Crypt::CBC> using L<Crypt::Rijndael> (AES).  The ciphertext and
MAC's in the cookie are Base64 encoded by L<MIME::Base64>.

During session retrieval, if the MAC does not authenticate or if the expiration
is set and in the past, the session will be discarded.

=head1 LIMITATIONS

=head2 Secret key

You must protect the secret key, of course.  Rekeying periodically would
improve security.  Rekeying also invalidates all existing sessions unless the
C<old_secrets> attribute contains old encryption keys still used for
decryption.  In a multi-node application, all nodes must share the same secret
key.

=head2 Session size

If storing the encoded session in a cookie, keep in mind that cookies must fit
within 4k, so don't store too much data.  This module uses L<Sereal> for
serialization and enables the C<snappy> compression option.  Sereal plus Snappy
appears to be one of the fastest and most compact serialization options for
Perl, according to the
L<Sereal benchmarks|https://github.com/Sereal/Sereal/wiki/Sereal-Comparison-Graphs>
page.

However, nothing prevents the encoded output from exceeding 4k.  Applications
must check for this condition and handle it appropriately with an error or
by splitting the value across multiple cookies.

=head2 Objects not stored

Session data may not include objects.  Sereal is configured to die if objects
are encountered because object serialization/deserialiation can have
undesirable side effects.  Applications should take steps to deflate/inflate
objects before storing them in session data.

=head1 SECURITY

Storing encrypted session data within a browser cookie avoids latency and
overhead of backend session storage, but has several additional security
considerations.

=head2 Transport security

If using cookies to store session data, an attacker could intercept cookies and
replay them to impersonate a valid user regardless of encryption.  SSL
encryption of the transport channel is strongly recommended.

=head2 Cookie replay

Because all session state is maintained in the session cookie, an attacker
or malicious user could replay an old cookie to return to a previous state.
Cookie-based sessions should not be used for recording incremental steps
in a transaction or to record "negative rights".

Because cookie expiration happens on the client-side, an attacker or malicious
user could replay a cookie after its scheduled expiration date.  It is strongly
recommended to set C<cookie_duration> or C<default_duration> to limit the window of
opportunity for such replay attacks.

=head2 Session authentication

A compromised secret key could be used to construct valid messages appearing to
be from any user.  Applications should take extra steps in their use of session
data to ensure that sessions are authenticated to the user.

One simple approach could be to store a hash of the user's hashed password
in the session on login and to verify it on each request.

  # on login
  my $hashed_pw = bcrypt( $password, $salt );
  if ( $hashed_pw eq $hashed_pw_from_db ) {
    session user => $user;
    session auth => bcrypt( $hashed_pw, $salt ) );
  }

  # on each request
  if ( bcrypt( $hashed_pw_from_db, $salt ) ne session("auth") ) {
    context->destroy_session;
  }

The downside of this is that if there is a read-only attack against the
database (SQL injection or leaked backup dump) and the secret key is compromised,
then an attacker can forge a cookie to impersonate any user.

A more secure approach suggested by Stephen Murdoch in
L<Hardened Stateless Session Cookies|http://www.cl.cam.ac.uk/~sjm217/papers/protocols08cookies.pdf>
is to store an iterated hash of the hashed password in the
database and use the hashed password itself within the session.

  # on login
  my $hashed_pw = bcrypt( $password, $salt );
  if ( bcrypt( $hashed_pw, $salt ) eq $double_hashed_pw_from_db ) {
    session user => $user;
    session auth => $hashed_pw;
  }

  # on each request
  if ( $double_hashed_pw_from_db ne bcrypt( session("auth"), $salt ) ) {
    context->destroy_session;
  }

This latter approach means that even a compromise of the secret key and the
database contents can't be used to impersonate a user because doing so would
requiring reversing a one-way hash to determine the correct authenticator to
put into the forged cookie.

Both methods require an additional database read per request. This diminishes
some of the scalability benefits of storing session data in a cookie, but
the read could be cached and there is still no database write needed
to store session data.

=head1 SEE ALSO

Papers on secure cookies and cookie session storage:

=for :list
* Liu, Alex X., et al., L<A Secure Cookie Protocol|http://www.cse.msu.edu/~alexliu/publications/Cookie/Cookie_COMNET.pdf>
* Murdoch, Stephen J., L<Hardened Stateless Session Cookies|http://www.cl.cam.ac.uk/~sjm217/papers/protocols08cookies.pdf>
* Fu, Kevin, et al., L<Dos and Don'ts of Client Authentication on the Web|http://pdos.csail.mit.edu/papers/webauth:sec10.pdf>

CPAN modules implementing cookie session storage:

=for :list
* L<Catalyst::Plugin::CookiedSession> -- encryption only
* L<Dancer::Session::Cookie> -- Dancer 1, encryption only
* L<Dancer::SessionFactory::Cookie> -- Dancer 2, forthcoming, based on this module
* L<HTTP::CryptoCookie> -- encryption only
* L<Mojolicious::Sessions> -- MAC only
* L<Plack::Middleware::Session::Cookie> -- MAC only
* L<Plack::Middleware::Session::SerializedCookie> -- really just a framework and you provide the guts with callbacks

Related CPAN modules that offer frameworks for serializing and encrypting data,
but without features relevant for sessions like expiration and unique keying.

=for :list
* L<Crypt::Util>
* L<Data::Serializer>

=cut

# vim: ts=4 sts=4 sw=4 et:
