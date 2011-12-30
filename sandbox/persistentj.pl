#!/usr/bin/perl -w
## persistentj.pl -- sandbox for a persistent jabber connection object

use strict;
use warnings;

use Net::XMPP;

my %s = (
    # XMPP settings
    x_user     => "",
    x_password => "",
    x_domain   => "talk.google.com",
    x_name     => "gmail.com",
    x_port     => 5222, # yes, requires TLS
    x_resource => "test",
    x_throttle => 60, # number of seconds between messages.. 
    x_last_msg => time(), # so we don't send a message for at least 60 seconds
    
    x_targets => [ "you\@yours.com", ], # who to message
    x_messages => [ "OH TEH NOES!!!! MOTION DETECTED", "Houston, we have a problem.", "I sense a disturbance in the force..", "There's a N+-100% chance that someone is here.", "Whatever you do, don't look behind you."], # list of semi amusing messages to send, one chosen randomly for each send_alert()
);

my $j = Net::XMPP::Client->new();

connect_to($j);

my $r = send_alert($j, 'fizzy', 10);

sleep(10);

$r = send_alert($j, 'bang', 20);

$j->Disconnect();

exit;

sub connect_to {
    my ($xmpp, $status, $sid, @auth);
    
    $xmpp = shift;
    
	eval {
	    # connect to the server
	    $xmpp = Net::XMPP::Client->new();
    	$status = $xmpp->Connect(
        	hostname       => $s{x_domain},
	        port           => $s{x_port},
	        componentname  => $s{x_name},
	        connectiontype => "tcpip", # when would it be anything else?
	        tls            => 1,
	    ) or die "DIE:: cannot connect: $!\n";
    
    	# change hostname .. kind of
	    $sid = $xmpp->{SESSION}->{id};
	    $xmpp->{STREAM}->{SIDS}->{$sid}->{hostname} = $s{x_name};
    
	    # authenticate 
    	@auth = $xmpp->AuthSend(
        	username => $s{x_user},
    	    password => $s{x_password},
  	    	resource => $s{x_resource}, # this identifies the sender
	    );
    
	    die "DIE:: authorization failed: $auth[0] - $auth[1]" if $auth[0] ne "ok";
    };

	if ($@) { 
		warn "WARN:: unable to connect/authenticate: $@";
		return 1;
	}


}

sub send_alert {
    # send_alert($filename, $deviation_pcent) - pulls rest of the needful out of %s hash. return 0|1 for success|failure
    my ($xmpp, $filename, $deviation_pcent) = @_;
    my $results;

    # we're pulling from %s, but still, a little abstraction
    # server settings
    my $hostname      = $s{x_domain};
    my $port          = $s{x_port};
    my $componentname = $s{x_name};
    my $tls           = 1; # this should almost always be 1
    # auth settings
    my $user     = $s{x_user};
    my $password = $s{x_password};
    my $resource = $s{x_resource};
    # message settings
    my @targets  = @{$s{x_targets}};
    my @msgs     = @{$s{x_messages}};
    my $msg_txt  = $msgs[int(rand($#msgs))] . ", deviation: $deviation_pcent%, filename: $filename"; 

    # check throttle
    my $lt1 = time();
    my $lt2 = $s{x_last_msg}; # this also prevents a msg from being sent for the first minute.. disabling throttle is a good idea on a long sleep timer

    my $throttle = $s{x_throttle};
    my $sec_diff = $lt1 - $lt2;
    
    
    
    if ($sec_diff <= $throttle and $throttle != 0) {
        print "\tthrottling XMPP messages, t$throttle / s$sec_diff\n" if $s{verbose} ge 1;
        return 0; # returning success
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
        
        $lresults = ($lresults) ? " FAILED: $lresults" : " OK!";
        print " $results\n",
        
    }
    
    # throttle
    # my @lt1 = localtime;
    $s{x_last_msg} = time();
    
    
    return 0;
}
