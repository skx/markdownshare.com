#!/usr/bin/perl -Ilib/ -I../lib/ -w


use strict;
use warnings;

use Test::More qw! no_plan !;


BEGIN {use_ok('HTML::Emoji');}
require_ok('HTML::Emoji');


#
#  Create a helper
#
my $helper = HTML::Emoji->new( path => "/images" );

#
#  Ensure that worked and is the correct type
#
ok( $helper, "Loaded the helper." );
isa_ok( $helper, "HTML::Emoji" );


#
#  Now we'll test some simple strings
#
foreach my $line (<DATA>)
{
    chomp($line);

    #
    #  The lines we'll have contain both the input and the expected
    # output
    #
    if ( $line =~ /^(.*)\|(.*)$/ )
    {
        my $inp = $1;
        my $out = $2;

        $inp = "\n" if ( $inp eq "\\n" );
        $out = "\n" if ( $out eq "\\n" );

        my $expanded = $helper->expand($inp);

        is( $out, $expanded, "We got the output we expected" );
    }

}


#
#  Test we have known types
#
my $known = $helper->all();
is( ref $known, "ARRAY", "Object is the correct type" );
ok( scalar @$known > 100, "We have more than 100 known types." );
is( scalar @$known, 864, "We have exactly the right number of types." );



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

# Empty
\n|\n
