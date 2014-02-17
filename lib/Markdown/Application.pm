#!/usr/bin/perl -w
#
# Simple Markdown-based pastebin service/site.
#
# Allows:
#
#   * Create.
#   * Raw-view + Rendered-view.
#   * Delete.
#
# Steve
# --
#



use strict;
use warnings;


use CGI::utf8;


package Markdown::Application;
use base 'CGI::Application';


#
#  Standard modules
#
use CGI::Session;
use Digest::MD5 qw(md5_hex);
use JSON;
use HTML::Template;
use Math::Base36 ':all';
use Redis;
use Text::MultiMarkdown 'markdown';



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
    my $session = CGI::Session->new( "driver:redis",
                                     $sid,
                                     {  Redis  => $self->{ 'redis' },
                                        Expire => 60 * 60 * 24
                                     } );

    if ( !$session )
    {
        $session = CGI::Session->new( undef, $sid, { Directory => '/tmp' } );
    }


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

    binmode STDIN,  ":encoding(utf8)";
    binmode STDOUT, ":encoding(utf8)";

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



=begin doc

Called before CGI::App dispatches to a runmode, merge GET + POST
parameters.

Source - http://www.perlmonks.org/?node_id=748939

=end doc

=cut

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

        # Static-page Handlers
        'index' => sub {showStatic( $self, 'index.tmpl' )},
        'api'   => sub {showStatic( $self, 'api.tmpl' )},
        'cheat' => sub {showStatic( $self, 'cheat.tmpl' )},

        # Real handlers.
        'create' => 'create',
        'delete' => 'delete',
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

    #
    #  Cookie name & expiry
    #
    my $cookie_name   = 'CGISESSID';
    my $cookie_expiry = '+7d';

    #
    #  Get the session identifier
    #
    my $query   = $self->query();
    my $session = $self->param('session');

    my $id = "";
    $id = $session->id() if ($session);

    #
    #  Create/Get the cookie
    #
    my $cookie = $query->cookie( -name    => $cookie_name,
                                 -value   => $id,
                                 -expires => $cookie_expiry,
                               );

    $self->header_add( -location => $url,
                       -status   => "302",
                       -cookie   => $cookie
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

Show a static page.

=end doc

=cut

sub showStatic
{
    my ( $self, $page ) = (@_);

    my $template = $self->load_template($page);

    my $cgi = $self->query();
    my $url = $cgi->url( -base => 1 );
    $template->param( domain => $url );

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
                #  Get the deletion link.
                #
                my $auth = $self->authLink($id);

                my %hash;
                $hash{ "id" } = $id;
                $hash{ "link" } = $cgi->url( -base => 1 ) . "/view/" . $id;
                $hash{ "delete" } =
                  $cgi->url( -base => 1 ) . "/delete/" . $auth;

                #
                #  Return the JSON object.
                #
                return to_json( \%hash );
            }
            else
            {

                #
                # We'll handle this better later.
                #
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
        #  Return
        #
        my $id = $self->saveMarkdown($txt);

        #
        #  Create a deletion link.
        #
        my $auth = $self->authLink($id);

        #
        #  Set the session-flash parameter with the secret ID.
        #
        my $session = $self->param('session');
        if ($session)
        {
            $session->param( "flash", $auth );
        }
        return ( $self->redirectURL( "/view/" . $id ) );
    }

    return ( $template->output() );
}


=begin doc

Delete a prior-upload by ID.

=end doc

=cut

sub delete
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
    #  Find the value, and see if it exists
    #
    my $redis = $self->{ 'redis' };
    my $rid   = $redis->get("MARKDOWN:KEY:$id");

    #
    #  If the value is present
    #
    if ( $rid && ( $rid =~ /^([0-9a-z]+)$/i ) )
    {

        #
        #  Delete the key
        #
        my $did = decode_base36($rid);
        $redis->set( "MARKDOWN:$did:TEXT", "" );
        $redis->del( "MARKDOWN:KEY:$id", "" );

        return ( $self->redirectURL( "/view/" . $rid ) );
    }
    else
    {
        $self->header_props( -status => 404 );
        return "Invalid auth-key: $rid";
    }
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
    if ( $session &&
         $session->param("flash") &&
         length( $session->param("flash") ) )
    {

        # get the flash
        $flash = $session->param("flash");

        # empty?
        if ( length($flash) )
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
    my $redis = $self->{ 'redis' };
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
    $template->param( flash => $flash ) if ($flash);
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

    if ( length($text) )
    {
        $self->header_add( '-type' => 'text/plain' );
        return ($text);
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
    my $redis = $self->{ 'redis' };
    my $id    = $redis->incr("MARKDOWN:COUNT");

    #
    #  Set the text
    #
    $redis->set( "MARKDOWN:$id:TEXT", $txt );

    return ( encode_base36($id) );
}


=begin doc

Create an auth-link for a given ID.

=end doc

=cut

sub authLink
{
    my ( $self, $id ) = (@_);

    my $cgi = $self->query();

    #
    #  The deletion link is "hash( time, ip, id )";
    #
    my $key = time . $cgi->remote_host() . $id;

    #
    # Add some more random data.
    #
    $key .= int( rand(1000) );
    $key .= int( rand(1000) );

    #
    # Make it URL-safe
    #
    my $digest = md5_hex($key);

    #
    # Set the value
    #
    my $redis = $self->{ 'redis' };
    $redis->set( "MARKDOWN:KEY:$digest", $id );
    return ($digest);
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


