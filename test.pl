#!/usr/bin/perl

use LWP::UserAgent;
use MIME::Lite;
use MIME::Base64;
use Getopt::Std;
use JSON;
use strict;

use vars qw/ %opt /;

my $debug = 0;
my $host = "thermostat-6D-72-A8";
my $tempurl = "http://$host/tstat";

my $ua = LWP::UserAgent->new;
my $req = HTTP::Request->new(GET => $tempurl);
my $res = $ua->request($req);

if (! $res->is_success) {
    exit;
}

my $scalar = from_json($res->content);

# target isn't there if not in heat mode
my $t_heat = 0;
$t_heat = $scalar->{ 't_heat' } if $scalar->{ 't_heat' };

print "Temp is " . $scalar->{ 'temp' } . "\n";
print "Target temp is " . $t_heat . "\n";
print "Mode is " . $scalar->{ 'tstate' } . "\n";
