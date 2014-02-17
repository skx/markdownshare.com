
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
* HTML::Template
* JSON
* Math::Base36
* Redis
* Text::MultiMarkdown

Installing them on a Debian GNU/Linux host should be as simple as:

     $ apt-get install  libossp-uuid-perl libjson-perl libhtml-template-perl \
        libmath-base36-perl libredis-perl libtext-multimarkdown-perl \
        perl perl-modules libcgi-application-perl libcgi-session-perl


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

Deployment should be pretty straightforward, there is a sample
Apache2 virtual-host file provided beneath the [docker sub-directory](docker/).

As the name might suggest the software runs under `docker` too,
via the provided [Dockerfile](Dockerfile), although it does require you
to manually start the daemons.


Live Demo
---------

* http://markdownshare.com/


Steve
--