requires "Carp" => "0";
requires "Crypt::CBC" => "0";
requires "Crypt::Rijndael" => "0";
requires "Crypt::URandom" => "0";
requires "Digest::SHA" => "0";
requires "MIME::Base64" => "3.12";
requires "Math::Random::ISAAC::XS" => "0";
requires "Moo" => "0";
requires "MooX::Types::MooseLike::Base" => "0.16";
requires "Sereal::Decoder" => "4.002";
requires "Sereal::Encoder" => "0";
requires "String::Compare::ConstantTime" => "0";
requires "namespace::clean" => "0";
requires "perl" => "5.008001";
requires "strict" => "0";
requires "warnings" => "0";

on 'test' => sub {
  requires "ExtUtils::MakeMaker" => "0";
  requires "File::Spec::Functions" => "0";
  requires "List::Util" => "0";
  requires "Test::Deep" => "0";
  requires "Test::Fatal" => "0";
  requires "Test::More" => "0.96";
  requires "Test::Tolerant" => "0";
  requires "version" => "0";
};

on 'test' => sub {
  recommends "CPAN::Meta" => "0";
  recommends "CPAN::Meta::Requirements" => "2.120900";
};

on 'configure' => sub {
  requires "ExtUtils::MakeMaker" => "6.17";
};

on 'develop' => sub {
  requires "Dist::Zilla" => "5.015";
  requires "Dist::Zilla::PluginBundle::DAGOLDEN" => "0.060";
  requires "File::Spec" => "0";
  requires "File::Temp" => "0";
  requires "IO::Handle" => "0";
  requires "IPC::Open3" => "0";
  requires "Pod::Coverage::TrustPod" => "0";
  requires "Test::CPAN::Meta" => "0";
  requires "Test::More" => "0";
  requires "Test::Pod" => "1.41";
  requires "Test::Pod::Coverage" => "1.08";
};
