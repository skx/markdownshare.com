# -*- cperl -*- #

=head1 NAME

Markdown::Application - A CGI::Application .. application

=head1 DESCRIPTION

This module implements is a web application, built using L<CGI::Application>,
which allows the sharing and rendering of Markdown text.

Remote users can upload Markdown text, and when they do so they will
recieve a stable/static URL which can be shared.  That URL will allow
later visitors to either view the rendered markdown, or the raw text.

In addition to allowing user-uploads there are a small number of static
endpoints defined which will show pre-cooked markdown text.

=cut

=head1 IMPLEMENTATION NOTES

When a piece of text is uploaded then it is pushed into a redis database,
and at the same time an authentication token is generated.

The intention is that only the uploader knows the authentication token,
and that token is required to edit/remove the text in the future.

* When posts are created they are given UUIDs to avoid enumeration.
    * This will allow http://host/view/xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
* When a post is created it will have a token created allowing:
    * http://host/edit/$token
    * http://host/delete/$token

The token is a one-to-one mapping, again stored in our redis store.  So
given an ID ("xxxxxx-xxxx-...") and a TOKEN ( "1234" ) we merely run:

    redis->set( "MARKDOWN:KEY:$TOKEN", $ID )

This allows us to lookup the ID given the TOKEN, but not vice-versa, since
that shouldn't be required.

=cut

=head1 AUTHOR

Steve Kemp <steve@steve.org.uk>

=cut

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2014 Steve Kemp <steve@steve.org.uk>.

This library is free software. You can modify and or distribute it under
the same terms as Perl itself.

=cut




use strict;
use warnings;

#
# Hierarchy
#
package Markdown::Application;
use base 'Markdown::Application::Base';


#
# Standard module(s)
#
use Data::UUID;
use Digest::MD5 qw(md5_hex);
use JSON;
use HTML::Emoji;
use HTML::Scrubber;
use HTML::Template;
use Math::Base36 ':all';
use Text::MultiMarkdown 'markdown';




=begin doc

Setup our run-mode mappings, and the defaults for the application.

=end doc

=cut

sub setup
{
    my $self = shift;

    $self->run_modes(

        # Static-page Handlers
        'api'   => sub {showStatic( $self, 'api.tmpl' )},
        'cheat' => sub {showStatic( $self, 'cheat.tmpl' )},
        'faq'   => sub {showStatic( $self, 'faq.tmpl' )},
        'index' => sub {showStatic( $self, 'index.tmpl' )},

        # Real handlers.
        'create' => 'create',
        'delete' => 'delete',
        'edit'   => 'edit',
        'view'   => 'view_html',
        'raw'    => 'view_raw',

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

Show a static page, loaded from beneath ./templates

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
    #  See if the caller accepts "application/json", and handle
    # that first - this is suboptimal and should be merged in better
    # later on.
    #
    foreach my $accept ( $cgi->Accept() )
    {
        if ( $accept =~ /application\/json/i )
        {

            #
            #  If we have TEXT submitted.
            #
            if ( $txt && length($txt) )
            {

                #
                #  Save it, which will return an ID and auth-token.
                #
                my $data = $self->saveMarkdown($txt);

                #
                #  Here we can configure the text to expire
                # based on the expire=XX setting.
                #
                my $expire = $cgi->param("expire") || undef;
                if ($expire)
                {

                    #
                    #  Each text-submission results in two keys
                    # being used:
                    #
                    #  1.  for authentication.
                    #
                    #  2.  for holding the text.
                    #
                    my $seconds = 0;
                    if ( $expire =~ /^([0-9]+)$/ )
                    {
                        $seconds = $1;
                    }
                    if ( $expire =~ /^([0-9]+)m$/i )
                    {
                        $seconds = $1 * 60;
                    }
                    if ( $expire =~ /^([0-9]+)h$/i )
                    {
                        $seconds = $1 * 60 * 60;
                    }
                    if ( $expire =~ /^([0-9]+)d$/i )
                    {
                        $seconds = $1 * 60 * 60 * 24;
                    }

                    #
                    #  OK update the keys.
                    #
                    my $id   = $data->{ 'id' };
                    my $auth = $data->{ 'auth' };

                    if ( $seconds > 0 )
                    {
                        my $redis = $self->{ 'redis' };
                        $redis->expire( "MARKDOWN:$id:TEXT",  $seconds );
                        $redis->expire( "MARKDOWN:KEY:$auth", $seconds );
                    }
                }


                #
                # Build up something sensible to return to the caller
                #
                # At the least they need to know:
                #
                #   * The ID.
                #   * The view-link.
                #   * The raw-link.
                #   * The delete-link.
                #
                my $base = $cgi->url( -base => 1 );

                my %hash;
                $hash{ "id" }   = $data->{ 'id' };
                $hash{ "auth" } = $data->{ 'auth' };

                # view by id
                $hash{ "link" } = $base . "/view/" . $data->{ 'id' };
                $hash{ "raw" }  = $base . "/raw/" . $data->{ 'id' };

                # update via auth-token
                $hash{ "delete" } = $base . "/delete/" . $data->{ 'auth' };
                $hash{ "edit" }   = $base . "/edit/" . $data->{ 'auth' };

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
    #  OK at this point we have a browser-based submission,
    # with no acceptance of "application/json".
    #
    #  Proceed as per usual.
    #

    #
    #  Load the output template
    #
    my $template = $self->load_template("create.tmpl");

    #
    #  See what action the user is performing: preview vs. submit.
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
    elsif ( $sub &&
            ( $sub =~ /create/i ) &&
            length($txt) )
    {

        #
        #  Get the ID of the newly submitted entry.
        #
        my $data = $self->saveMarkdown($txt);

        #
        #  Set the session-flash parameter with the secret ID.
        #
        my $session = $self->param('session');
        if ($session)
        {
            $session->param( "flash", $data->{ 'auth' } );
        }

        #
        #  Redirect to view the new submission.
        #
        return ( $self->redirectURL( "/view/" . $data->{ 'id' } ) );
    }

    return ( $template->output() );
}


=begin doc

Edit a prior submission, via an authentication-token.

=end doc

=cut

sub edit
{
    my ($self) = (@_);

    #
    #  Get the ID
    #
    my $cgi = $self->query();
    my $id  = $cgi->param("id");

    #
    # If there's a missing ID redirect.  If the ID is bogus abort.
    #
    return ( $self->redirectURL("/") ) unless ($id);
    die "Invalid ID" unless ( $id =~ /^([-a-z0-9]+)$/i );

    #
    #  Find the key we'll be working with
    #
    my $real_id = $self->by_auth_token($id);
    if ( !$real_id )
    {
        $self->header_props( -status => 404 );
        return "Invalid auth-token!  (Has the post has been deleted?)";
    }


    #
    ##
    ##  Ok we can load the text and allow the preview-stuff to happen.
    ##
    #


    #
    #  Load the template
    #
    my $template = $self->load_template("edit.tmpl");

    #
    #  See if the user is submitting
    #
    my $submit = $cgi->param("submit");

    if ( $submit && ( $submit =~ /preview/i ) )
    {
        my $text = $cgi->param("text");

        #
        #  Render the text
        #
        if ( length($text) )
        {
            my $html = render($text);

            #
            #  Populate both the text and the HTML
            #
            $template->param( html    => $html,
                              id      => $id,
                              content => $text
                            );
        }
    }
    elsif ( $submit && ( $submit =~ /save/i ) )
    {

        #
        #  Get the text, and save it.
        #
        my $text = $cgi->param("text") || "";
        my $redis = $self->{ 'redis' };
        $redis->set( "MARKDOWN:$real_id:TEXT", $text );

        #
        #  Redirect to view it.
        #
        return ( $self->redirectURL( "/view/" . $real_id ) );

    }
    else
    {
        my $redis = $self->{ 'redis' };
        $template->param( content => $redis->get("MARKDOWN:$real_id:TEXT"),
                          id      => $id );
    }

    return ( $template->output() );
}


=begin doc

Delete some text which has been uploaded, via the authentication-token.

=end doc

=cut

sub delete
{
    my ($self) = (@_);

    #
    #  Get the ID
    #
    my $cgi  = $self->query();
    my $auth = $cgi->param("id");

    #
    # If there's a missing ID redirect.  If the ID is bogus abort.
    #
    return ( $self->redirectURL("/") ) unless ($auth);
    die "Invalid auth token" unless ( $auth =~ /^([-a-z0-9]+)$/i );

    #
    #  Find the key we'll be working with
    #
    my $id = $self->by_auth_token($auth);
    if ( !$id )
    {
        $self->header_props( -status => 404 );
        return "Invalid auth-token!  (Has the post has been deleted?)";
    }

    #
    #  Delete the text and the auth-key
    #
    $self->deleteMarkdown( $id, $auth );

    #
    # Redirect specifically so the user can see their post is gone.
    #
    return ( $self->redirectURL( "/view/" . $id ) );
}



=begin doc

Show the contents of a paste.

=end doc

=cut

sub view_html
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


    #
    #  HTML raw?  Or wrapped?
    #
    my $html = $cgi->param("html") || 0;

    #
    # If there's a missing ID redirect.  If the ID is bogus abort.
    #
    return ( $self->redirectURL("/") ) unless ($id);
    die "Invalid ID" unless ( $id =~ /^([-a-z0-9]+)$/i );

    #
    #  Decode and get the text.
    #
    #
    # If we have a legacy ID then decode, otherwise use as-is.
    #
    my $uid = $id;
    if ( length($id) < 3 )
    {
        $uid = decode_base36($id);
    }

    #
    #  Get the text
    #
    my $redis = $self->{ 'redis' };
    my $text  = $redis->get("MARKDOWN:$uid:TEXT");


    #
    # Load the template
    #
    my $template = $self->load_template("view.tmpl");

    #
    #  If we have the text then render it.
    #
    if ( defined($text) && length($text) )
    {
        $text = render($text);
        $template->param( html => $text );

        #
        #  Increase the view-count
        #
        $redis->incr("MARKDOWN:$uid:VIEWED");
    }
    else
    {

        # Look for a local copy
        if ( $uid =~ /^([a-z]+)$/ )
        {
            $text = $self->loadFile("samples/$uid.md");
            if ($text)
            {
                $text = render($text);
                $template->param( html => $text );
            }
        }
    }


    #
    # Render.
    #
    $template->param( id => $id );
    $template->param( flash => $flash ) if ($flash);

    if ( $html )
    {
        my $out = <<EOF;
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.1//EN" "http://www.w3.org/TR/xhtml11/DTD/xhtml11.dtd">
<html xmlns="http://www.w3.org/1999/xhtml" xml:lang="en">
<head>
<meta http-equiv="content-type" content="text/html; charset=utf-8" />
<link rel="author" href="/humans.txt" />
<title>$id</title>
</head>
<body>
$text
</body>
</html>
EOF
        return( $out );
    }
    else
    {
        return ( $template->output() );
    }
}



=begin doc

Show the contents of a paste, as raw markdown.

=end doc

=cut

sub view_raw
{
    my ($self) = (@_);

    #
    #  Get the ID
    #
    my $cgi = $self->query();
    my $id  = $cgi->param("id");

    #
    # If there's a missing ID redirect.  If the ID is bogus abort.
    #
    return ( $self->redirectURL("/") ) unless ($id);
    die "Invalid ID" unless ( $id =~ /^([-a-z0-9]+)$/i );

    #
    # If we have a legacy ID then decode, otherwise use as-is.
    #
    my $uid = $id;
    if ( length($id) < 3 )
    {
        $uid = decode_base36($id);
    }

    my $redis = $self->{ 'redis' };
    my $text  = $redis->get("MARKDOWN:$uid:TEXT");

    if ( !$text )
    {

        # Look for a local copy
        if ( $uid =~ /^([a-z]+)$/ )
        {
            $text = $self->loadFile("samples/$uid.md");
        }
    }

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




#
##
##  Utility methods follow - rather than URL-handlers.
##
#




=begin doc

Render the given markdown text, handling emoji expansion too.

B<NOTE> All our code passes the markdown through this method to ensure that
we only need to update the rendering process in one place.

=end doc

=cut

sub render
{
    my ($txt) = (@_);

    #
    # Convert to HTML
    #
    my $html = markdown($txt);

    #
    # Now we have HTML we can process the content for known-emojis too.
    #
    my $helper = HTML::Emoji->new( path => "/img/emojis" );

    $html = $helper->expand($html);


    my @allow = qw[blockquote style];
    my @deny =
      qw[script center embed object form input marquee menu meta option font div];
    my @rules = (
        img => {
            src    => qr{^(http://|\/)}i,    # only absolute image links allowed
            alt    => 1,                     # alt attribute allowed
            align  => 1,                     # align attribute allowed
            height => 1,
            width  => 1,
            '*'    => 0,                     # deny all other attributes
               },
        a => { href  => 1,                      # HREF
               name  => 1,                      # name attribute allowed
               id    => 1,                      # id attribute allowed
               title => 1,                      # title attribute allowed
               rel   => qr/^nofollow$/i,        # Link relationship
               '*'   => 0,                      # deny all other attributes
             },
        pre => { class => 1,
                 style => 0,
               },
        span => { class => 1,
                  style => 0,
                },
    );

    my @default = (
        1 =>                                 # default rule, allow all tags
          { '*' => 1,    # default rule, allow all attributes
            'href'     => qr{^(?!(?:java)?script)}i,
            'src'      => qr{^(?!(?:java)?script)}i,
            'cite'     => '(?i-xsm:^(?!(?:java)?script))',
            'language' => 0,
            'name'        => 1,    # could be sneaky, but hey ;)
            'onblur'      => 0,
            'color'       => 0,
            'class'       => 0,
            'style'       => 0,
            'onchange'    => 0,
            'onclick'     => 0,
            'ondblclick'  => 0,
            'onerror'     => 0,
            'onfocus'     => 0,
            'onkeydown'   => 0,
            'onkeypress'  => 0,
            'onkeyup'     => 0,
            'onload'      => 0,
            'onmousedown' => 0,
            'onmousemove' => 0,
            'onmouseout'  => 0,
            'onmouseover' => 0,
            'onmouseup'   => 0,
            'onreset'     => 0,
            'onselect'    => 0,
            'onsubmit'    => 0,
            'onunload'    => 0,
            'type'        => 0,
            'font'        => 0,
          } );


    #
    #  Create the scrubber.
    #
    my $safe = HTML::Scrubber->new();
    $safe->allow(@allow);
    $safe->rules(@rules);
    $safe->deny(@deny);
    $safe->default(@default);
    $safe->style(1);

    # deny HTML Comments
    $safe->comment(0);

    return ( $safe->scrub($html) );

}


=begin doc

Save the given text in our store and return the ID _and_ auth-token
which will be used to edit/delete it.

=end doc

=cut

sub saveMarkdown
{
    my ( $self, $txt ) = (@_);

    #
    #  Create the ID, which will hopefully avoid collisions.
    #
    my $helper = Data::UUID->new();
    my $id     = $helper->create_str();

    #
    #  We want to ensure that we don't collide.
    #
    my $redis = $self->{ 'redis' };
    while ( defined( $redis->get($id) ) )
    {

        #
        #  Regenerate
        #
        $id = $helper->create_str();
    }

    #
    #  Set the text
    #
    $redis->set( "MARKDOWN:$id:TEXT", $txt );

    #
    #  The return value of this method will be a hash
    # containing the ID of the post, and the authentication token.
    #
    my $result = {};

    $result->{ 'id' }   = $id;
    $result->{ 'auth' } = $self->gen_auth_token($id);

    return ($result);
}


=begin doc

Create an authentication token for a given ID.

We could use a UUID here, but to give it a different feel I used a hash
of the time, the remote IP, and some "randomness".  Hrm.

=end doc

=cut

sub gen_auth_token
{
    my ( $self, $id ) = (@_);

    my $cgi = $self->query();

    #
    #  The authentication token is "hash( time, ip, id )";
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

Given an authenticate token return the appropriate ID

=end doc

=cut

sub by_auth_token
{
    my ( $self, $token ) = (@_);

    #
    #  Lookup the token
    #
    my $redis = $self->{ 'redis' };
    my $id    = $redis->get("MARKDOWN:KEY:$token");

    #
    # If the value wasn't found then that's an error.
    #
    return if ( !$id );
    return if ( $id !~ /^([-0-9a-z]+)$/i );

    #
    # If we have a legacy ID then decode, otherwise use as-is.
    #
    if ( length($id) < 3 )
    {
        $id = decode_base36($id);
    }

    return ($id);
}


=begin doc

Remove the text from the store, along with the authentication token.

=end doc


=cut

sub deleteMarkdown
{
    my ( $self, $id, $auth ) = (@_);

    #
    # Get the DB-handle.
    #
    my $redis = $self->{ 'redis' };

    #
    #  Unset the text, and the view-count.
    #
    $redis->del("MARKDOWN:$id:TEXT");
    $redis->del("MARKDOWN:$id:VIEWED");

    #
    #  Remove the auth-token.
    #
    $redis->del("MARKDOWN:KEY:$auth");

}


1;
