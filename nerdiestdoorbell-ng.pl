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

# CLI spec should supercede config file
$C::settings{$_} = $C::flags{$_} foreach (keys %C::flags);

## convenience hashes
%C::xmpp = %{$C::settings{xmpp_settings}};
%C::motion = %{$C::settings{motion_settings}};
%C::general = %{$C::settings{general_settings}};
%C::experimental = %{$C::settings{experimental_settings}};

## dump variables
print Dumper(\%C::flags)      if $C::general{verbose} gt 2;
print Dumper(\%C::settings) if $C::general{verbose} gt 2;
print Dumper(\%C::xmpp)    if $C::general{verbose} eq 1;
print Dumper(\%C::motion)  if $C::general{verbose} eq 1;
print Dumper(\%C::general) if $C::general{verbose} eq 1;
print Dumper(\%C::experimental) if $C::general{verbose} eq 1;

## ensure settings are sane
die "DIE:: unable to locate specified webcam:$C::motion{device}" unless -f $C::motion{device};
die "DIE:: unable to locate 'take_picture.py'" unless -f 'take_picture.py';
die "DIE:: unable to run on Windows currently" unless $^O =~ /linux/i;

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
		#$doc = $worker->XMLin($ffp, ForceArray => 1);
		$doc = $worker->XMLin($ffp);
	};
	
	if ($@) {
		warn "WARN: $@";
		return 0;
	}
	
	return %{$doc};
}