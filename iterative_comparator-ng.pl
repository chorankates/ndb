#!/usr/bin/perl -w
## iterative_comparator-ng.pl

use strict;
use warnings;

use Time::HiRes;

## real world use
#my $max_x = 640;
#my $max_y = 480;
#my $itr = 300_000; # 640x480 = 307_200

## breaking point
my $max_x = 1920;
my $max_y = 1080;
my $itr   = 2_000_000; ## should come up with a formula here

my %cache;

my ($already_checked, $new_comparison, $inner_loops);

my $begin = Time::HiRes::gettimeofday();

for (my $i = 0; $i < $itr; $i++) {
    my ($x, $y); # scope hack
    
    UNIQUE:
    while (1) {
        ($x, $y) = get_coords($max_x, $max_y);
        $inner_loops++; # how many times did we have to regenerate coords?
    
        unless ($cache{$x}{$y}) {
            # these are new coordinates, use them
            $new_comparison++;
            
            $cache{$x}{$y} = 1;
            
            last UNIQUE;
            
        } else {
            # already looked at this one
            $already_checked++;
        }
        
        
    }

}

my $end = Time::HiRes::gettimeofday();

print(
    "statistics:\n",
    "  already checked: $already_checked\n",
    "  new comparison:  $new_comparison\n",
    "  inner loops:     $inner_loops\n",
    "\n",
    "took: ", ($end - $begin), "s\n",
    );

exit;

## subs below

sub get_coords {
    # get_coords($max_x, $max_y) -- returns ($x, $y) based off of input
    my ($max_x, $max_y) = @_;
    my ($x, $y);
    
    # this is not going to lead to a very good distribution.. depending on big of a performance hit it is
    # it might be worth building an array of valid integers and then Fisher-Yates'ing it
    
    # can't fisher-yates it because our data set is so large than the shuffle increases the runtime unacceptably (and doesn't affect the distribution as much as it should)
    if (1) { 
        $x = int(rand($max_x));
        $y = int(rand($max_y));
    } else {
        ## fisher yates
        my @x = (0..$max_x);
        my @y = (0..$max_y);
        
        @x = fisher_yates(\@x);
        @y = fisher_yates(\@y);
        
        $x = $x[int(rand($#x))];
        $y = $y[int(rand($#y))];
        
    }
    
    return ($x, $y);
}

sub fisher_yates {
    # fisher_yates(\@array) -- applies the Fisher Yates shuffling mechanism to @array
    my $array = shift;
    my $i;
    for ($i = @$array; --$i; ) {
        my $j = int rand ($i+1);
        next if $i == $j;
        @$array[$i,$j] = @$array[$j,$i];
    }

    return @{$array};
}
