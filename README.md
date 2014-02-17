
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
* Digest::MD5
* HTML::Template
* JSON
* Math::Base36
* Redis
* Text::MultiMarkdown

Installing them on a Debian GNU/Linux host should be as simple as:

     $ apt-get install libdigest-md5 libjson-perl libhtml-template libmath-base36 libredis-perl libtext-multimarkdown-perl


Live Demo
---------

* http://markdownshare.com/


Steve
--