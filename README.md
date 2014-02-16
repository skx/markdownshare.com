
markdown.share
--------------


This is a simple pastebin-like service which allows a user to submit
text which is formatted in Markdown, and share the resulting HTML.


Requirements
------------

The service uses Redis for persistence, but I'm open to the idea
of using the filesystem instead if there is a preference.

In addition to having `redis` listening upon localhost you will
need the following Perl modules:

* CGI::Application
* HTML::Template
* Math::Base36
* Redis
* Text::Markdown

Installing them on a Debian GNU/Linux host should be as simple as:

     $ apt-get install libhtml-template libmath-base36 libredis-perl libtext-markdown-perl


Live Demo
---------

* http://markdownsha.re/


Steve
--