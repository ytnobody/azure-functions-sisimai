use strict;
use warnings;
use utf8;
use lib '../local/lib/perl5';
use Sisimai;
use JSON::PP;

my $file = $ENV{inputBlob};
my $bounced = Sisimai->make($file);

if (!defined $bounced) {
    print encode_json({message => "no bounced mail is contained", bounced => []});
    exit;
}

print encode_json({message => "found", bounced => [map {$_->damn} @$bounced]});

