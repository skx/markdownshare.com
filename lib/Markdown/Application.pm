#!/usr/bin/perl -w
#
# Steve
# --
#



use strict;
use warnings;

package Markdown::Application;
use base 'CGI::Application';


#
#  Standard modules
#
use HTML::Template;
use Math::Base36 ':all';
use Redis;
use Text::Markdown 'markdown';





=begin doc

Setup our run-mode mappings, and the defaults for the application.

=end doc

=cut

sub setup
{
    my $self = shift;

    $self->run_modes(

        # default
        'index' => 'index',
        'create'     => 'create',
        'view'      => 'view',

        # called on unknown mode.
        'AUTOLOAD' => 'unknown_mode',
    );

    #
    #  Start mode + mode name
    #
    $self->header_add(-charset => 'utf-8');
    $self->start_mode('index');
    $self->mode_param('mode');
}



=begin doc

Redirect to the given URL - and attempt to keep cookies correct.

=end doc

=cut

sub redirectURL
{
    my ( $self, $url ) = (@_);

    $self->header_add( -location => $url,
                       -status   => "302",
                     );
    $self->header_type('redirect');
    return "";

}



=begin doc

Load a template from our ./templates directory - which is outside the
web root directory for safety.

=end doc

=cut


sub load_template
{
    my ( $self, $file, %options ) = (@_);

    my $path = "";

    foreach my $dir (qw! ../templates/ ../../templates/ !)
    {
        $path = $dir if ( -d $dir );
    }
    die "No path" unless ( defined($path) );

    my $template = HTML::Template->new( filename => $file,
                                        path     => [$path],
                                        %options,
                                        die_on_bad_params => 0,
                                      );
    return ($template);
}


=begin doc

Show the index page.

=end doc

=cut

sub index
{
    my ($self) = (@_);

    #
    #  Load the default index.
    #
    my $template = $self->load_template("index.tmpl");
    return ( $template->output() );
}



=begin doc

Create a new paste.

=end doc

=cut

sub create
{
    my ($self) = (@_);

    my $cgi  = $self->query();
    my $sub  = $cgi->param( "submit" );

    my $template = $self->load_template("create.tmpl");

    if ( $sub && ( $sub =~ /preview/i ) )
    {
        #
        #  Render the text
        #
        my $html = render($cgi->param( "text" ) );

        $template->param( html => $html,
                          content => $cgi->param( "text" )
                        );
    }
    elsif ( $sub && ( $sub =~ /create/i ) )
    {
        #
        #  Create the ID
        #
        my $redis = Redis->new();
        my $id    = $redis->incr( "MARKDOWN:COUNT" );

        #
        #  Set the text
        #
        $redis->set( "MARKDOWN:$id:TEXT" , $cgi->param( "text" ) );

        #
        #  Return
        #
        return( $self->redirectURL( "/view/" . encode_base36( $id ) ) );
    }

    return ( $template->output() );
}


=begin doc

Show the contents of a paste.

=end doc

=cut

sub view
{

    my ($self) = (@_);

    my $cgi  = $self->query();
    my $id   = $cgi->param( "id" );
    my $uid  = decode_base36($id);

    #
    #  Create the ID
    #
    my $redis = Redis->new();
    my $text  = $redis->get( "MARKDOWN:$uid:TEXT" );
    $text = render( $text );

    #
    #  Return it
    #
    my $template = $self->load_template("view.tmpl");
    $template->param( html => $text, id => $id );

    return( $template->output() );
}


sub render
{
    my ( $txt ) = (@_ );
    return( markdown( $txt ) );
}


=begin doc

Called when an unknown mode is encountered.

=end doc

=cut

sub unknown_mode
{
    my ( $self, $requested ) = (@_);

    return ("mode not found $requested");
}




1;


