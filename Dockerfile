#
# This is a trivial docker-file for the markdown-share application.
# It is now how I run the real site, that runs under thttpd with
# a custom proxy to handle the rewrites, but it does work.
#
# To build the image:
#     sudo docker build -t skxskx/markdown.share .
#
# Then to launch the image:
#     sudo docker run -t -i -p 3333:80 skxskx/markdown.share /bin/bash
#
# Once launched you should start apache2 + redis and you're golden.
# run:
#
#    /etc/init.d/redis-server start
#    /etc/init.d/apache2 start
#
# Then exit by pressing "Ctrl-p Ctrl-q".
#
# Once you've done that you can open your favourite browser and point
# it at http://localhost:3333/
#
# Steve
# --
#


#
#  From the Ubuntu starting point, create an image owned by Steve
#
FROM ubuntu
MAINTAINER steve@steve.org.uk

#
#  Ensure our packages are OK.
#
ENV DEBIAN_FRONTEND noninteractive
RUN apt-get update

#
#  Now install our servers
#
RUN apt-get install --yes --force-yes redis-server
RUN apt-get install --yes --force-yes apache2
RUN rm /etc/apache2/sites-enabled/000-default

#
#  Now install our Perl dependencies
#
RUN apt-get install --yes --force-yes libossp-uuid-perl libjson-perl libhtml-template-perl libmath-base36-perl libredis-perl libtext-multimarkdown-perl perl perl-modules libcgi-application-perl libcgi-session-perl

#
#  Install git and checkout our code
#
RUN apt-get install --yes --force-yes git
RUN cd /srv && git clone https://github.com/skx/markdown.share.git


#
# At this point we have all the daemons, now we'll configure Apache:
#
RUN a2enmod rewrite
ADD ./docker/docker.conf /etc/apache2/sites-enabled/markdown-share.conf


#
# Complete.  The user will need to launch the daemons though, because
# I'm done here.
#