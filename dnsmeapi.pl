#!/usr/bin/perl -w

# This is a sample file demonstrating how to use the HMAC authentication for the
# DNS Made Easy REST API.  Commands and options entered here will be passed through to curl with
# the additional x-dnsme-* headers required for authentication.
# This file is only provided as an example of possible API usage.
#
# Use CPAN to get any of the modules that might be missing.  For example:
# perl -MCPAN -e "install Digest::HMAC_SHA1"
#
# Make sure the dnsmeapi.properties file is available in the location from which you run this
#

use strict;
use Digest::HMAC_SHA1 qw(hmac_sha1_hex);
use HTTP::Date;
use Config::Properties;

#Read the apiKey and secretKey values from the property file
my $pfn = "dnsmeapi.properties";

if (! -f $pfn) {
    die "Property file " . $pfn . " not found";
}

open PROPS, $pfn
    or die "Unable to open " . $pfn;
my $props = new Config::Properties();
$props->load(*PROPS);

my $apiKey = $props->getProperty("apiKey");
my $secretKey = $props->getProperty("secretKey");

if (!defined $apiKey || $apiKey eq "" || !defined $secretKey || $secretKey eq "" ) {
    die "Missing values for apiKey or secretKey properties";
}

# Set header values:
my $requestDate = time2str(time);
my $hmac = hmac_sha1_hex($requestDate, $secretKey);

my $apiKeyHeader = "x-dnsme-apiKey:" . $apiKey;
my $hmacHeader = "x-dnsme-hmac:" . $hmac;
my $requestDateHeader = "x-dnsme-requestDate:" . $requestDate;

# run curl with the DNS Made Easy API headers
system("curl", @ARGV, "--header", $apiKeyHeader, "--header", $hmacHeader, "--header", $requestDateHeader, );
exit $?;
