#!/usr/bin/perl -Ilib/ -I../lib/ -w


use strict;
use warnings;

use Test::More qw! no_plan !;


BEGIN {use_ok('HTML::Emojis');}
require_ok('HTML::Emojis');


#
#  Create a helper
#
my $helper = HTML::Emojis->new( path => "/images" );

#
#  Ensure that worked and is the correct type
#
ok( $helper, "Loaded the helper." );
isa_ok( $helper, "HTML::Emojis" );


#
#  Now we'll test some simple strings
#
foreach my $line (<DATA>)
{
    chomp( $line );

    #
    #  The lines we'll have contain both the input and the expected
    # output
    #
    if ( $line =~/^(.*)\|(.*)$/ )
    {
        my $inp = $1;
        my $out = $2;

        my $expanded = $helper->expand( $inp );

        is( $out, $expanded, "We got the output we expected" );
    }

}

__DATA__
# No emojis
<p>Test</p>|<p>Test</p>

# Simple angel expansion
<p>Test :angel:</p>|<p>Test <img src="/images/angel.png" width="32" height="32" alt="angel" /></p>

# Ignore the expansion in non-text parts
<a href=":test:">Test</a>|<a href=":test:">Test</a>

# Only expanded once
<a href=":cat:">:cat:</a>|<a href=":cat:"><img src="/images/cat.png" width="32" height="32" alt="cat" /></a>

# Unknown type
<p>:fake:</p>|<p>:fake:</p>
