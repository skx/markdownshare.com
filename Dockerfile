#
# This is a docker file for the markdown-share application.
#
# I do not run the real site under docker, instead that runs
# under thttpd with a custom proxy to handle the rewrites.
#
# To build this image:
#
#     sudo docker build -t skxskx/markdown.share .
#
# Then to launch the image:
#
#     sudo docker run -d -p 3333:80 skxskx/markdown.share
#
# Once launched you should open your favourite browser and point
# it at:
#
#      http://localhost:3333/
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
RUN echo 28-02-2015
ENV DEBIAN_FRONTEND noninteractive
RUN apt-get update

#
# Prepare for server-installation - See:
#    http://stackoverflow.com/questions/25193161/chfn-pam-system-error-interm
#
RUN ln -s -f /bin/true /usr/bin/chfn


#
#  Now install our servers
#

RUN apt-get install --yes --force-yes redis-server
RUN apt-get install --yes --force-yes apache2
RUN rm /etc/apache2/sites-enabled/000-default.conf

#
#  Now install our Perl dependencies
#
RUN apt-get install --yes --force-yes libossp-uuid-perl libjson-perl libhtml-template-perl libmath-base36-perl libredis-perl libtext-multimarkdown-perl perl perl-modules libcgi-application-perl libcgi-session-perl libhtml-parser-perl

#
#  Install git and checkout our code
#
RUN apt-get install --yes --force-yes git

RUN echo 2014-02-19r2
RUN cd /srv && git clone https://github.com/skx/markdown.share.git


#
# At this point we have all the daemons, now we'll configure Apache:
#
RUN a2enmod rewrite
RUN a2enmod cgi
ADD ./docker/docker.conf /etc/apache2/sites-enabled/markdown-share.conf


#
# Add a script to launch the two daemons
#
ADD ./docker/start.sh /srv/start.sh

#
# Now boot it up
#
CMD ["/srv/start.sh"]
