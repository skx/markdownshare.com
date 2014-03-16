#!/usr/bin/perl -Ilib/
#
#  Test we can save some markdown, look it up, and delete it.
#
#


use strict;
use warnings;

use Test::More;


#
#  1. Load the Redis module.
#
BEGIN
{
    my $str = "use Redis;";
    ## no critic (Eval)
    eval($str);
    ## use critic

    plan skip_all => "Skipping as Redis isn't installed"
      if ($@);
}



#
#  2.  Try to connect to redis, if this can't be done we'll abort.
#
my $redis;
my $str = "\$redis = new Redis;";
## no critic (Eval)
eval($str);
## use critic
plan skip_all => "Skipping as Redis isn't running"
  if ($@);



#
#  3.  Run the tests.
#
ok( 1, "Redis installed." );
ok( 1, "Redis running." );


#
#  Load the modules
#
BEGIN {use_ok('Markdown::Application');}
require_ok('Markdown::Application');



my $app = new Markdown::Application();
ok( $app, "Created application instance." );
isa_ok( $app, "Markdown::Application",
        "The application has the correct type." );


my $input  = "Fortune favours the **BOLD**.";
my $result = $app->saveMarkdown($input);

ok( $result,             "Saving markdown was achieved" );
ok( $result->{ 'id' },   "The markdown had an ID: $result->{'id'}" );
ok( $result->{ 'auth' }, "The markdown had an auth token: $result->{'auth'}" );


#
#  Lookup the text by the token
#
my $found = $app->by_auth_token( $result->{ 'auth' } );
is( $found, $result->{ 'id' }, "Lookup of ID by auth token succeeded." );

#
#  Now delete the upload
#
$app->deleteMarkdown( $result->{ 'id' }, $result->{ 'auth' } );

#
#  At this point the token lookup should fail.
#
my $found2 = $app->by_auth_token( $result->{ 'auth' } );
ok( !$found2, "Failed to lookup deleted key, as expected" );

done_testing();
