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
use CGI::Session;
use HTML::Template;
use Math::Base36 ':all';
use Redis;
use Text::Markdown 'markdown';



=begin doc

Create our session, and connect to redis.

=end doc

=cut

sub cgiapp_init
{
    my $self  = shift;
    my $query = $self->query();

    #
    # Open our redis connection.
    #
    $self->{ 'redis' } = Redis->new();

    my $cookie_name   = 'CGISESSID';
    my $cookie_expiry = '+7d';
    my $sid           = $query->cookie($cookie_name) || undef;

    # session setup
    my $session =
      CGI::Session->new( 'driver:redis',
                         $sid,
                         {  Redis  => $self->{ 'redis' },
                            Expire => 60 * 60 * 24
                         } );

    # assign the session object to a param
    $self->param( session => $session );

    # send a cookie if needed
    if ( !defined $sid or $sid ne $session->id )
    {
        my $cookie = $query->cookie( -name    => $cookie_name,
                                     -value   => $session->id,
                                     -expires => $cookie_expiry,
                                   );
        $self->header_props( -cookie => $cookie );
    }

    binmode STDOUT, ':utf8';

}

=begin doc

Cleanup our session and close our redis connection.

=end doc

=cut

sub teardown
{
    my ($self) = shift;

    #
    #  Flush the sesions
    #
    my $session = $self->param('session');
    $session->flush() if ( defined($session) );

    #
    #  Disconnect.
    #
    my $redis = $self->{ 'redis' };
    $redis->quit() if ($redis);
}


#
# Called before CGI::App dispatches to a runmode, merge GET + POST
# parameters.
#
# Source:
#  * http://www.perlmonks.org/?node_id=748939
#
sub cgiapp_prerun
{
    my ($self) = @_;

    # $self->mode_param so we don't have to go back and change this if we
    # ever decide to use something other than rm
    if ( $self->query->url_param( $self->mode_param ) )
    {

        # prerun_mode lets you change CGI::Apps notion of the current runmode
        $self->prerun_mode( $self->query->url_param( $self->mode_param ) );
    }
    return;
}



=begin doc

Setup our run-mode mappings, and the defaults for the application.

=end doc

=cut

sub setup
{
    my $self = shift;

    $self->run_modes(

        # Handlers
        'index'  => 'index',
        'cheat'  => 'cheat',
        'create' => 'create',
        'view'   => 'view',
        'raw'    => 'raw',

        # called on unknown mode.
        'AUTOLOAD' => 'unknown_mode',
    );

    #
    #  Start mode + mode name
    #
    $self->header_add( -charset => 'utf-8' );
    $self->start_mode('index');
    $self->mode_param('mode');
}



=begin doc

Redirect to the given URL.

=end doc

=cut

sub redirectURL
{
    my ( $self, $url ) = (@_);

    $self->header_add( -location => $url,
                       -status   => "302", );
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
    #  Prepare
    #
    my $cgi      = $self->query();
    my $template = $self->load_template("index.tmpl");

    #
    #  Set the domain
    #
    my $url = $cgi->url( -base => 1 );
    $template->param( domain => $url );

    return ( $template->output() );
}


sub cheat
{
    my ($self) = (@_);

    #
    #  Prepare
    #
    my $cgi      = $self->query();
    my $template = $self->load_template("cheat.tmpl");

    return ( $template->output() );
}



=begin doc

Create a new paste.

=end doc

=cut

sub create
{
    my ($self) = (@_);

    my $cgi = $self->query();
    my $sub = $cgi->param("submit");
    my $txt = $cgi->param("text") || "";


    #
    #  If we accept application/json.
    #
    foreach my $accept ( $cgi->Accept() )
    {
        if ( $accept =~ /application\/json/i )
        {

            #
            #  If we have TEXT submitted.
            #
            if ($txt)
            {

                #
                #  Save it.
                #
                my $id = $self->saveMarkdown($txt);

                #
                #  Build up the redirect link.
                #
                my $url = $cgi->url( -base => 1 ) . "/view/" . $id;
                return ("{\"id\":\"$id\",\"link\":\"$url\"}");
            }
            else
            {


                $self->header_props( -status => 404 );
                return "Missing TEXT parameter";
            }
        }
    }


    #
    #  Load the output template
    #
    my $template = $self->load_template("create.tmpl");

    #
    #
    #
    if ( $sub && ( $sub =~ /preview/i ) )
    {

        #
        #  Render the text
        #
        if ( length($txt) )
        {
            my $html = render($txt);

            #
            #  Populate both the text and the HTML
            #
            $template->param( html    => $html,
                              content => $txt, );
        }
    }
    elsif ( $sub && ( $sub =~ /create/i ) )
    {
        #
        #  Set the session.
        #
        my $session = $self->param('session');
        if ( $session )
        {
            $session->param( "flash", "Here we .." );
        }

        #
        #  Return
        #
        my $id = $self->saveMarkdown($txt);
        return ( $self->redirectURL( "/view/" . $id ) );
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

    #
    #  Is there a flash message?
    #
    my $flash = undef;

    #
    #  Possibly from the session.
    #
    my $session = $self->param('session');
    if ( $session && $session->param( "flash" ) && length( $session->param( "flash" )) )
    {
        # get the flash
        $flash = $session->param( "flash" );

        # empty?
        if ( length( $flash ) )
        {
            $session->param( "flash", "" );
        }
        else
        {
            $flash = undef;
        }

    }

    #
    #  Get the ID
    #
    my $cgi = $self->query();
    my $id  = $cgi->param("id");

    die "Missing ID" unless ($id);
    die "Invalid ID" unless ( $id =~ /^([a-z0-9]+)$/i );

    #
    #  Decode and get the text.
    #
    my $redis = Redis->new();
    my $uid   = decode_base36($id);
    my $text  = $redis->get("MARKDOWN:$uid:TEXT");

    #
    # Load the template
    #
    my $template = $self->load_template("view.tmpl");

    #
    #  Get the ID from Redis.
    #
    if ( defined($text) && length($text) )
    {
        $text = render($text);
        $template->param( html => $text );
    }

    #
    # Render.
    #
    $template->param( id => $id );
    $template->param( flash => $flash ) if ( $flash );
    return ( $template->output() );
}



=begin doc

Show the contents of a paste, as raw markdown.

=end doc

=cut

sub raw
{
    my ($self) = (@_);

    #
    #  Get the ID
    #
    my $cgi = $self->query();
    my $id  = $cgi->param("id");

    die "Missing ID" unless ($id);
    die "Invalid ID" unless ( $id =~ /^([a-z0-9]+)$/i );

    #
    #  Decode and get the text.
    #
    my $redis = Redis->new();
    my $uid   = decode_base36($id);
    my $text  = $redis->get("MARKDOWN:$uid:TEXT");

    if ( length( $text ) )
    {
        $self->header_add( '-type' => 'text/plain' );
        return( $text );
    }
    else
    {
        $self->header_props( -status => 404 );
        return "Not found";
    }

}



=begin doc

Render the text.

=end doc

=cut

sub render
{
    my ($txt) = (@_);
    return ( markdown($txt) );
}


=begin doc

Populate the given text in the next ID.

=end doc

=cut

sub saveMarkdown
{
    my ( $self, $txt ) = (@_);

    #
    #  Create the ID
    #
    my $redis = Redis->new();
    my $id    = $redis->incr("MARKDOWN:COUNT");

    #
    #  Set the text
    #
    $redis->set( "MARKDOWN:$id:TEXT", $txt );

    return ( encode_base36($id) );
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


