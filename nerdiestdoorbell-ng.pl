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
#   make the XMPP object global and give the option for gtalk/jabber persistence
#   implement a Log4Perl solution instead of the $s{verbose} hacks

use strict;
use warnings;
use 5.010;

## intercept ctrl+c, do some cleanup
#$SIG{INT} = \&cleanup('ctrl-c');

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
%C::xmpp         = %{$C::settings{xmpp_settings}}         if defined $C::settings{xmpp_settings};
%C::motion       = %{$C::settings{motion_settings}}       if defined $C::settings{motion_settings};
%C::general      = %{$C::settings{general_settings}}      if defined $C::settings{general_settings};
%C::experimental = %{$C::settings{experimental_settings}} if $C::settings{experimental_settings};

## dump variables
print Dumper(\%C::flags)        if $C::general{verbose} gt 2;
print Dumper(\%C::settings)     if $C::general{verbose} gt 2;
print Dumper(\%C::xmpp)         if $C::general{verbose} eq 1;
print Dumper(\%C::motion)       if $C::general{verbose} eq 1;
print Dumper(\%C::general)      if $C::general{verbose} eq 1;
print Dumper(\%C::experimental) if $C::general{verbose} eq 1;

## ensure settings are sane
die "DIE:: unable to locate specified webcam:$C::motion{device}" unless -c $C::motion{device};
die "DIE:: unable to locate 'take_picture.py'" unless -f 'take_picture.py';
die "DIE:: unable to run on Windows currently" unless $^O =~ /linux/i;

print "DBGZ" if 0;

## loop
while (1) {
	my ($deviation, $last_picture, $notification_results, $picture_results);
	
	# find the last picture we took
	$last_picture = (defined $C::motion{last_picture}) ? $C::motion{last_picture} : 'none';
	
	# take a picture
	$C::motion{current_picture} = take_a_picture();
	
	# compare the pictures
	if ($last_picture eq 'none') {
		print "DBG:: no last picture found (probably first new run)\n" if $C::general{verbose} ge 0;
        $C::motion{last_picture} = $C::motion{current_picture};
		next;
	} elsif (! -f $last_picture) {
		print "WARN:: last picture [$last_picture] does not exist, skipping\n" if $C::general{verbose} ge 1;
	}
	
	($picture_results, $deviation) = compare_pictures($last_picture, $C::motion{current_picture});
	
	# send alerts if need be
	if ($picture_results > 0) {
		$notification_results = send_alert($C::motion{current_picture}, $deviation);
		print "WARN:: sending alert failed\n" if $notification_results;
	}
	
	# sleep
	if ($C::motion{sleep} =~ /\d+/) {
		print "DBG:: sleeping [$C::motion{sleep}]\n";
		sleep $C::motion{sleep};
	}
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
	
	# post-processing?
	print "DBGZ" if 0;
	
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
  
    my $iterations        = $C::settings{motion_settings}{image}{itr};
    my $allowed_deviation = int($iterations / $C::settings{motion_settings}{image}{deviation}); # 1.000001  seems to be a good number so far.. looks like need to increase the sample size again or start RGB deviation

    my $deviation         = 0;
    
    # size of input image
    my $x = $C::settings{motion_settings}{image}{x}; 
    my $y = $C::settings{motion_settings}{image}{y};

    my %cache; # allows us to ensure unique coord comparison
	my $itr_start = Time::HiRes::gettimeofday();

	ITERATION:
    for (my $i = 0; $i < $iterations; $i++) {
		my ($gx, $gy); # scope hacking
		my $local_itr = 0; # keep track of while(1) iterations
		my $local_itr_start = Time::HiRes::gettimeofday();
		
		UNIQUE:
		while (1) {
			($gx, $gy) = get_coords($x, $y);
			
			unless ($cache{$gx}{$gy}) {
				$cache{$gx}{$gy} = 1;

				last UNIQUE;
			}

			$local_itr++;
			next ITERATION if $local_itr > 1_000_000; # should probably add a warning here, maybe make the ceiling configurable 
		}
		my $unique_created = Time::HiRes::gettimeofday();
		print "DBG:: found unique coordinates in ", ($unique_created - $local_itr_start), " s ($local_itr)\n" if $C::settings{general_settings}{verbose} ge 3;

        my ($index1, $index2, @r1, @r2); # eval scope hack
        
        eval {
            # pull actual values
            $index1 = $ih1->getPixel($gx, $gy);
            $index2 = $ih2->getPixel($gx, $gy);
			
		    print "\tcomparing '$index1' and '$index2'\n" if $C::settings{general_settings}{verbose} ge 3;

            # compare values need to be broken down to RGB
            @r1 = $ih1->rgb($index1);
            @r2 = $ih2->rgb($index2);
            
            print "\tcomparing '@r1' and '@r2'\n" if $C::settings{general_settings}{verbose} ge 4;
        };
        
        if ($@) { warn "WARN:: unable to grab pixels: $@"; return 1; } 
        
        # pixel RGB deviation detection.. it works
        if ($C::settings{motion_settings}{image}{p_deviation}) {
		    # this could be rewritten as a map
            my $p_deviation = $C::settings{motion_settings}{image}{p_deviation}; # allowed pixel deviation
            
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
	print "DBG:: comparison complete in ", ($itr_end - $itr_start), "s\n" if $C::settings{general_settings}{verbose} ge 3;
    $results = ($deviation > $allowed_deviation) ? 1 : 0; # 1 is different, 0 is same

    my $deviation_pcent = int(($deviation / $iterations) * 100); # we should really be keying off of this

    print "\tdeviation: d$deviation / a$allowed_deviation / i$iterations = $deviation_pcent%\n" if $C::settings{general_settings}{verbose} ge 1;

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

sub hdump {
    # hdump(\%hash, $type) - dumps %hash, helped by $type
    my ($href, $type) = @_;
    my %h = %{$href};
    
    print "> hdump($type):\n";
    
    foreach (sort keys %h) {
        print "\t$_", " " x (20 - length($_));
        
        print "$h{$_}\n"    unless $h{$_} =~ /array/i;
        print "@{$h{$_}}\n" if     $h{$_} =~ /array/i;
    }
    
    return;
}

sub send_alert {
    # send_alert($filename, $deviation_pcent) - pulls rest of the needful out of %s hash. return 0|1 for success|failure
    my ($filename, $deviation_pcent) = @_;
    my $results;

    # we're pulling from %s, but still, a little abstraction
    # server settings
    my $hostname      = $C::settings{xmpp_settings}{domain};
    my $port          = $C::settings{xmpp_settings}{port};
    my $componentname = $C::settings{xmpp_settings}{name};
    my $tls           = 1; # this should almost always be 1
    # auth settings
    my $user     = $C::settings{xmpp_settings}{user};
    my $password = $C::settings{xmpp_settings}{password};
    my $resource = $C::settings{xmpp_settings}{resource};
    # message settings
    my @targets  = @{$C::settings{xmpp_settings}{targets}};
    my @msgs     = @{$C::settings{xmpp_settings}{messages}};
    my $msg_txt  = $msgs[int(rand($#msgs))] . ", deviation: $deviation_pcent%, filename: $filename"; 

    # check throttle
    my $lt1 = time();
    my $lt2 = $C::settings{xmpp_settings}{last_msg} // time(); # this also prevents a msg from being sent for the first minute.. disabling throttle is a good idea on a long sleep timer

    my $throttle = $C::settings{general_settings}{throttle};
    my $sec_diff = $lt1 - $lt2;
    
    
    
    if ($sec_diff <= $throttle and $throttle != 0) {
        print "\tthrottling XMPP messages, t$throttle / s$sec_diff\n" if $C::settings{general_settings}{verbose} ge 1;
        return 0; # returning success
    }

	my ($xmpp, $status, $sid, @auth); # scope hacking

	eval {
	    # connect to the server
	    $xmpp = Net::XMPP::Client->new();
    	$status = $xmpp->Connect(
        	hostname       => $hostname,
	        port           => $port,
	        componentname  => $componentname,
	        connectiontype => "tcpip", # when would it be anything else?
	        tls            => $tls,
	    ) or die "DIE:: cannot connect: $!\n";
    
    	# change hostname .. kind of
	    $sid = $xmpp->{SESSION}->{id};
	    $xmpp->{STREAM}->{SIDS}->{$sid}->{hostname} = $componentname;
    
	    # authenticate 
    	@auth = $xmpp->AuthSend(
        	username => $user,
    	    password => $password,
  	    	resource => $resource, # this identifies the sender
	    );
    
	    die "DIE:: authorization failed: $auth[0] - $auth[1]" if $auth[0] ne "ok";
    };

	if ($@) { 
		warn "WARN:: unable to connect/authenticate: $@";
		return 1;
	}

    # send a message   
    foreach (@targets) {
        my $lresults = 0; 
        print "\tsending alert to '$_'..";
        
        $xmpp->MessageSend(
            to       => $_,
            body     => $msg_txt,
            resource => $resource, # could be used for sending to only a certain location, but if it doesn't match anything the user has, it delivers to all
        ) or $results = $!;
        
        $lresults = ($results) ? " FAILED: $results" : " OK!";
        print " $lresults\n",
        
    }
    
    # endup
    $xmpp->Disconnect();
    
    # throttle
    # my @lt1 = localtime;
    $C::settings{xmpp_settings}{last_msg} = time();
    
    
    return 0;
}

sub take_a_picture {
    # take_a_picture() - no params, we'll pull them out of %s, returns $filename
    # i feel dirty, but pythons modules are superior.. OUTSOURCED
    my ($filename, $cmd);
    
    my @lt1 = localtime; # need to define this locally so it gets updated on every run
    
    my $ts = nicetime(\@lt1, "both");
    
    $filename = "mcap-" . $ts . "_diff.jpg";
    $filename = File::Spec->catfile($C::settings{general_settings}{home}, $filename);
    
	$cmd = $C::settings{motion_settings}{cmd} . " $filename";
    
    my $results = `$cmd 2>&1`; # capture and suppress STDOUT and STDERR
    
    warn "WARN:: no picture taken\n" unless -e $filename;
    
    return $filename;
}
sub cleanup {
	# cleanup($keystroke) - does a little cleanup if the user hits ctrl+c
	my ($sequence, $response);
	$sequence = uc(shift);
	
	## what do we want to do here? settle for a confirmation prompt for now
	print uc($sequence) . " received, are you sure you want to quit? [y/N] ";
	chomp ($response = <STDIN>);
	
	if ($response =~ /y/i) {
		print STDERR "$0 exiting after receiving '$sequence'\n";
		exit 1;
	} else {
		print STDERR "$0 quit aborted\n";
	}
	
	return;
}
sub save_diff_files {
	# save_diff_files($f1, $f2) - makes a copy of $f1 and $f2 for later review - returns 0|1 for success|failure
	my @files_unverified = @_;
	my $save_dir  = $C::experimental{save_diffs};
	my $results = 0;        
	
	return 1 unless defined $C::experimental{save_diffs_dir}; # should we just try and create it?
	return 1 unless -d      $C::experimental{save_diffs_dir};
	
	my @files;
	foreach (@files_unverified) {
		push @files, $_ if -f $_;
	}
	
	$results = 1 unless $#files == $#files_unverified; 
	foreach my $file (@files) { 
		my $fname = basename($file);
		my $file_new = File::Spec->catfile($C::experimental{save_diffs_dir}, $fname);
		my $cmd = "cp $file $file_new";

		my $lresults = system($cmd);

		if ($lresults) { 
			# something went wrong
			print "WARN:: bad return code from copy [$fname --> $file_new]: $results" if $C::general{verbose} ge 1;
			$results = 1;
		}
		# end of loop
	}
	
	return $results;
}

sub nicetime {
	# nicetime(\@time, type) - returns time/date according to the type
	# types are: time, date, both
    my $aref = shift @_; my @time = @{$aref};
    my $type = shift @_ || "both"; # default variables ftw.
    warn "warn> nicetime: type '$type' unknown" unless ($type =~ /time|date|both/);
    warn "warn> nicetime: \@time may not be properly populated (", scalar @time, " elements)" unless scalar @time == 9;


    my $hour = $time[2]; my $minute = $time[1]; my $second = $time[0];
    $hour    = 0 . $hour   if $hour   < 10;
    $minute  = 0 . $minute if $minute < 10;
    $second  = 0 . $second if $second < 10;

    my $day = $time[3]; my $month = $time[4] + 1; my $year = $time[5] + 1900;
    $day   = 0 . $day   if $day   < 10;
    $month = 0 . $month if $month < 10;

    my $time = $hour .  "." . $minute . "." . $second;
        #my $date = $month . "." . $day    . "." . $year;
    my $date = $year . "." . $month . "." . $day; # new style, makes for better sorting

    my $full = $date . "-" . $time;

    if ($type eq "time") { return $time; }
    if ($type eq "date") { return $date; }
    if ($type eq "both") { return $full; }
}
