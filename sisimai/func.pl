use strict;
use warnings;
use utf8;
use lib '../local/lib/perl5';
use Sisimai;
use JSON::PP;

require '../azure_func.pl';

my $file = $ENV{req};
my $bounced = Sisimai->make($file);

if (!defined $bounced) {
    res(
        200, 
        {"Content-Type" => "application/json"}, 
        {message => "no bounced mail is contained", bounced => []}
    );
}

res(
    200, 
    {"Content-Type" => "application/json"}, 
    {message => "found", bounced => [map {$_->damn} @$bounced]}
);


