#!/usr/bin/perl -w
# nerdiestdoorbell-ng.pl -- cleaner version of NDB, but not quite a rewrite

# prereqs:
#  take_picture.py - python script to take a picture from webcam
#  python-opencv   - python package to interface with camera .. ubuntu can sudo apt-get install this
#  libgd2-xpm-dev  - image libraries for GD .. ubuntu can sudo apt-get install this too
#  libssl-dev      - SSL binaries .. ubuntu can sudo apt-get install
#  Crypt::SSLeay   - SSL crypto package from CPAN
#  IO::Socket:SSL  - SSL wrapper
#  XML::Stream     - XMPP dependency
#
# 
# run 'perl -c nerdiestdoorbell-ng.pl' for any machine specific dependencies

# TODO
#   need an interface for email and sms (google voice api?)
#   write an interrupt handler to cleanup

use strict;
use warnings;
use 5.010;

## prereqs here
use Data::Dumper;
use File::Basename; # could be replaced by a pretty simple regex..
use File::Spec;  # this can really only run on unix (GD), but still.. FFP FTW
use Getopt::Long; 
use GD;                # it sure seems like magic
use Net::XMPP;    # to connect to gtalk
use XML::Simple; # read configuration files  

$| = 1; # when i say

## process user input
GetOptions(\%C::flags, "help", "verbose:i", "xml:s"); # will be getting all other information from XML

## initialize variables
my $config_file = $C::flags{xml} // 'ndb-default.xml';
%C::settings = get_xml($config_file);

## dump variables
Data::Dumper(\%C::flags)      if $C::settings{verbose} ge 2;
Data::Dumper(\%C::settings) if $C::settings{verbose} ge 1;

print "DBGZ" if 0;

## loop
while (1) {
	
}

## cleanup

## subs below

sub get_xml {
	# get_xml($filename) - returns %contents of $filename or 0 for error
	my $ffp = shift;
	
	return 0 unless -f $ffp;
	
	my $worker = XML::Simple->new();
	my $doc;
	
	eval {
		$doc = $worker->XMLin($ffp, ForceArray => 1);
	};
	
	if ($@) {
		warn "WARN: $@";
		return 0;
	}
	
	return %{$doc};
}