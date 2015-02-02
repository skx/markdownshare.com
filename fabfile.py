#!/usr/bin/env python

from __future__ import with_statement

import os
import sys
import subprocess
import time

try:
    from fabric.api import *
    from fabric.contrib.console import confirm
except ImportError:
    print ("""The 'fabric' package is currently not installed. You can install it by typing:\n
sudo apt-get install fabric
""")
    sys.exit()



#
#  Username and hostname to ssh to.
#
env.hosts = ['www.steve.org.uk:2222']
env.user = 's-mark'



def deploy():
    """
    Deploy the application,
    """

    #
    #  Setup our release identifier.
    #
    env.release = time.strftime('%Y%m%d%H%M%S')

    #
    #  Create a tar-file and upload it
    #
    local('git archive --format=tar master | gzip > %(release)s.tar.gz' % env)
    run( "mkdir ~/releases/ || true")
    put('%(release)s.tar.gz' % env, '~/releases/' % env)

    #
    #  Remove the local copy.
    #
    local('rm %(release)s.tar.gz' % env)

    #
    #  Untar the remote version
    #
    run( "mkdir ~/releases/%(release)s && cd ~/releases/%(release)s && tar zxf ../%(release)s.tar.gz" % env )

    #
    #  Now symlink in the current release
    #
    run( "rm -f ~/current || true " )
    run( "ln -s ~/releases/%(release)s ~/current" % env )

    #
    #  And restart
    #
    run( "kill -9 $(cat lighttpd.pid)" )







#
#  This is our entry point.
#
if __name__ == '__main__':

    if len(sys.argv) > 1:
        #
        #  If we got an argument then invoke fabric with it.
        #
        subprocess.call(['fab', '-f', __file__] + sys.argv[1:])
    else:
        #
        #  Otherwise list our targets.
        #
        subprocess.call(['fab', '-f', __file__, '--list'])

