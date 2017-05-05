#!/bin/bash
echo "Your @cern.ch username:"
read user

echo "Setting up ssh config"
if [ ! -e ~/.ssh ]; then
  mkdir ~/.ssh
fi
echo "GSSAPIAuthentication yes
GSSAPIDelegateCredentials yes
HOST lxplus*
GSSAPITrustDns yes
ForwardAgent yes

Host ams.cern.ch
User $user
ProxyCommand ssh -XY $user@lxplus.cern.ch nc %h %p 2> /dev/null" > ~/.ssh/config

export CVS_RSH=ssh
export CVSROOT=:ext:${user}@ams.cern.ch:/afs/cern.ch/exp/ams/Offline/CVS
echo "CVSROOT set, getting kerberos ticket..."
kinit $user@CERN.CH
echo "...done"

if [ ! -e workdir ]; then
  mkdir -p workdir
fi

echo "Downloading AMS software"
cd workdir
cvs co AMS
