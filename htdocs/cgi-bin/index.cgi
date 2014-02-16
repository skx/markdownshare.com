#!/usr/bin/perl -I../../lib/ -I./lib/

=head1 NAME

index.cgi - Driver for our application.

=cut

=head1 SYNOPSIS

None.

=cut

=head1 ABOUT

This is the driver for our L<CGI::Application> derived code.

It merely instantiates a new instance of our application module, and
passes control to it.

=cut

=head1 AUTHOR

Steve
--
http://www.steve.org.uk/

=cut

=head1 LICENSE

Copyright (c) 2011 by Steve Kemp.  All rights reserved.

=cut


use strict;
use warnings;

use CGI::Carp qw/ fatalsToBrowser /;
use Markdown::Application;


#
#  Launch our application
#
my $application = new Markdown::Application();
$application->run();

