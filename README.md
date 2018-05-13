
**NOTE**: This project has been replaced by a golang port:

* https://github.com/skx/markdownshare



markdown.share
--------------

This is a simple pastebin-like service which allows a user to submit
text which is formatted in Markdown, and share the resulting HTML.

A user uploads Markdown and both the rendered HTML and the original
markdown are available.

The user will be able to delete the content post-upload, if they
so wish.



Requirements
------------

The service uses Redis for persistence, but I'm open to the idea
of using the filesystem instead if there is a preference.

In addition to having `redis` listening upon localhost you will
need the following Perl modules:

* CGI::Application
* CGI::Session
* Data::UUID
* Digest::MD5
* HTML::Parser
   * This is optional and used to provide `:emojis:` support
* HTML::Template
* JSON
* Math::Base36
* Redis
* Text::MultiMarkdown

Installing them on a Debian GNU/Linux host should be as simple as:

     $ apt-get install  libossp-uuid-perl libjson-perl libhtml-template-perl \
        libmath-base36-perl libredis-perl libtext-multimarkdown-perl \
        perl perl-modules libcgi-application-perl libcgi-session-perl \
        libhtml-parser-perl


Notes
-----

In the past we used a single incrementing integer for storing all
submissions, which was base36-encoded for brevity.

We've now switched to using UUIDs, which means that the URLs are longer
but that it isn't possible for a remote attacker to spider the complete
list of uploaded documents.

It would have been possible to mix both schemes indefinitely, and allow
the user to choose between "Normal" and "Secure", but I'd rather remove
a checkbox/combobox and keep the interface simple.


Deployment
----------

Deployment should be pretty straightforward if you're familiar with
running Perl-based CGI applications.

There is a [sample Apache2 virtual-host](docker/docker.conf) file provided,
which documents the rewrites which are required to make the application
run with clean URLs.

Additionally there is a provided [Dockerfile](Dockerfile), which allows
you to easily build a container with a copy of the project code within it.
This container may then be launched to give yourself a local instance
of the application in an isolated environment.

There is a pre-built container available from the docker index:

* [skxskx/markdown.share](https://index.docker.io/u/skxskx/markdown.share/)


Live Demo
---------

* http://markdownshare.com/


Steve
--
