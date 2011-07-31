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
use Time::HiRes; # ocd
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

sub compare_pictures {
    # compare_pictures($f1, $f2) - compares image files $f1 and $f2, if they are different enough, we assume motion.. this is not perfect .. return (0|1 for same|diff, $deviation_pcent)
    my ($f1, $f2) = @_;
    my $results = 0;
    
    warn "WARN:: unable to find '$f1'\n" and return 1 unless -e $f1;
    warn "WARN:: unable to find '$f2'\n" and return 1 unless -e $f2;
       
    # HT to http://www.perlmonks.org/?node_id=576382
    my $ih1 = GD::Image->new($f1);
    my $ih2 = GD::Image->new($f2);
  
    my $iterations        = $s{m_image_itr};
    my $allowed_deviation = int($iterations / $s{m_deviation}); # 1.000001  seems to be a good number so far.. looks like need to increase the sample size again or start RGB deviation
    my $deviation         = 0;
    
    # size of input image
    my $x = $s{m_image_x}; 
    my $y = $s{m_image_y};
    my %cache; # allows us to ensure unique coord comparison
	my $itr_start = Time::HiRes::gettimeofday();


	ITERATION:
    for (my $i = 0; $i < $iterations; $i++) {
		my ($gx, $gy); # scope hacking
		my $local_itr = 0; # keep track of while(1) iterations

		UNIQUE:
		while (1) {
			($gx, $gy) = get_coords($x, $y);
			
			unless ($cache{$x}{$y}) {
				$cache{$x}{$y} = 1;

				last UNIQUE;
			}

			$local_itr++;
			next ITERATION if $local_itr > 1_000_000; # should probably add a warning here, maybe make the ceiling configurable 
		}
		my $unique_created = Time::HiRes::gettimeofday();
		print "DBG:: found unique coordinates in ", ($unique_created - $itr_start), " s ($local_itr)\n" if $s{verbose} ge 3;

        my ($index1, $index2, @r1, @r2); # eval scope hack
        
        eval {
            # pull actual values
            $index1 = $ih1->getPixel($gx, $gy);
            $index2 = $ih2->getPixel($gx, $gy);
			
            print "\tcomparing '$index1' and '$index2'\n" if $s{verbose} ge 3;
            
            # compare values need to be broken down to RGB
            @r1 = $ih1->rgb($index1);
            @r2 = $ih2->rgb($index2);
            
            print "\tcomparing '@r1' and '@r2'\n" if $s{verbose} ge 4;
        };
        
        if ($@) { warn "WARN:: unable to grab pixels: $@"; return 1; } 
        
        # pixel RGB deviation detection.. it works
        if ($s{m_p_deviation}) {
            # this could be rewritten as a map
            my $p_deviation = $s{m_p_deviation}; # allowed pixel deviation
            my $l_deviation = 0;                 # set this if $diff  >= $p_deviation (where $diff is the difference between each RGB value of each pixel)
                    
            for (my $i = 0; $i < $#r1; $i++) {
                my $one = $r1[$i];
                my $two = $r2[$i];
                
                my $diff = $one - $two;
				$diff = ($diff < 0) ? $diff * -1 : $diff;
                
                $l_deviation = 1 if $diff >= $p_deviation;
            }
            
            $deviation++ if $l_deviation; 
            
        } else {
            # we could also compare $index1 and $index2 .. and apply some deviation there?
            $deviation++ unless @r1 ~~ @r2;
        }
        
    }

	my $itr_end = Time::HiRes::gettimeofday();
	print "DBG:: comparison complete in ", ($itr_end - $itr_start), "s\n" if $s{verbose} ge 3;
    $results = ($deviation > $allowed_deviation) ? 1 : 0; # 1 is different, 0 is same

    my $deviation_pcent = int(($deviation / $iterations) * 100); # we should really be keying off of this

    print "\tdeviation: d$deviation / a$allowed_deviation / i$iterations = $deviation_pcent%\n" if $s{verbose} ge 1;

    return $results, $deviation_pcent;
}

sub get_coords {
	# get_coords($max_x, $max_y) - returns a set ($x, $y) of coordinates based on input
	my ($max_x, $max_y) = @_;
	my ($x, $y);

	# not doing anything more complex than this since any other form 
	# of shuffling is such a performance hit that its better to rely
	# on %cache uniqueness checking
	$x = int(rand($max_x));
	$y = int(rand($max_y));


	return ($x, $y);
}
