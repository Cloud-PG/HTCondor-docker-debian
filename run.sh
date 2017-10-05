#!/bin/bash
# Configure HTCondor and fire up supervisord
# Daemons for each role
MASTER_DAEMONS="COLLECTOR, NEGOTIATOR"
EXECUTOR_DAEMONS="STARTD"
SUBMITTER_DAEMONS="SCHEDD"

usage() {
  cat <<-EOF
	usage: $0 -m master-address|-e master-address|-s master-address [-c url-to-config] [-k url-to-public-key] [-u inject user -p password] [-C Condor Connection Broker (CCB) -P Private Network Namei -S Shared Secret -I Schedd Interface]
	
	Configure HTCondor role and start supervisord for this container. 
	
	OPTIONS:
	  -m master-address    	configure container as HTCondor master
	  -e master-address 	configure container as HTCondor executor for the given master
	  -s master-address 	configure container as HTCondor submitter for the given master
	  -c url-to-config  	config file reference from http url.
	  -k url-to-public-key	url to public key for ssh access to root
	  -u inject user	inject a user without root privileges for submitting jobs accessing via ssh. -p password required
	  -p password		user password (see -u attribute).
	  -C ccb		Condor Connection Broker (CCB).
	  -P private network	Private Network Name parameter for condor_config.
	  -S shared secret	Shared secret.
          -I schedd interface	Schedd ip address for condor config
	EOF
  exit 1
}

# Syntax checks
CONFIG_MODE=
SSH_ACCESS=

# Get our options
ROLE_DAEMONS=
CONDOR_HOST=
SCHEDD_HOST=
INTERFACE=
HEALTH_CHECKS=
ONEDATA=
CONFIG_URL=
KEY_URL=
USER=
PASSWORD=
CCB=
PRIVATE_NETWORK_NAME=
SHARED_SECRET=
while getopts ':m:e:s:c:k:u:p:C:P:S:I:' OPTION; do
  case $OPTION in
    m)
      [ -n "$ROLE_DAEMONS" -o -z "$OPTARG" ] && usage
      ROLE_DAEMONS="$MASTER_DAEMONS"
      CONDOR_HOST='$(FULL_HOSTNAME)'
      echo "NETWORK_INTERFACE = $OPTARG" >> /etc/condor/condor_config
      HEALTH_CHECK='master'
    ;;
    e)
      [ -n "$ROLE_DAEMONS" -o -z "$OPTARG" ] && usage
      ROLE_DAEMONS="$EXECUTOR_DAEMONS"
      CONDOR_HOST="$OPTARG"
      echo "SLOT_TYPE_1 = cpus=1,ram=2048" >> /etc/condor/condor_config
      echo "NUM_SLOTS = 1" >> /etc/condor/condor_config
      echo "NUM_SLOTS_TYPE_1 = 1" >> /etc/condor/condor_config
      echo "CCB_ADDRESS = $OPTARG" >> /etc/condor/condor_config
      ONEDATA='true'
      oneclient -i -o allow_other -H $AMS_ONEDATA_CACHE -t $ONEDATA_ACCESS_TOKEN mountpoint /mnt/onedata/
      HEALTH_CHECK='executor'
    ;;
    c)
      [ -n "$CONFIG_MODE" -o -z "$OPTARG" ] && usage
      CONFIG_MODE='http'
      CONFIG_URL="$OPTARG"
    ;;
    s)
      [ -n "$ROLE_DAEMONS" -o -z "$OPTARG" ] && usage
      ROLE_DAEMONS="$SUBMITTER_DAEMONS"
      CONDOR_HOST="$OPTARG"
      ONEDATA='true'
      oneclient -i -o allow_other -H $AMS_ONEDATA_CACHE -t $ONEDATA_ACCESS_TOKEN mountpoint /mnt/onedata/
      HEALTH_CHECK='submitter'
    ;;
    k)
      [ -n "$KEY_URL" -o -z "$OPTARG" ] && usage
      SSH_ACCESS='yes'
      wget -O - $OPTARG > /home/amsuser/.ssh/authorized_keys
      KEY_URL="$OPTARG"
    ;;  
    u)
      [ -n "$USER" -o -z "$OPTARG" ] && usage
      SSH_ACCESS='yes'
      USER="$OPTARG"
    ;;  
    p)
      [ -n "$PASSWORD" -o -z "$OPTARG" ] && usage
      SSH_ACCESS='yes'
      PASSWORD="$OPTARG"
    ;;  
    C)
      [ -n "$CCB" -o -z "$OPTARG" ] && usage
      CCB="$OPTARG"
    ;;   
    P)
      [ -n "$PRIVATE_NETWORK_NAME" -o -z "$OPTARG" ] && usage
      PRIVATE_NETWORK_NAME="$OPTARG"
    ;; 
    S)
      [ -n "$SHARED_SECRET" -o -z "$OPTARG" ] && usage
      SHARED_SECRET="$OPTARG"
    ;;
    I)
      [ -n "$SCHEDD_HOST" -o -z "$OPTARG" ] && usage
      echo "NETWORK_INTERFACE = $OPTARG" >> /etc/condor/condor_config
    ;;  
    *)
      usage
    ;;
  esac
done

# Additional checks
# USER XOR PASSWORD
if [ \( -n "$PASSWORD" -a -z "$USER" \) -a \( -z "$PASSWORD" -a -n "$USER" \) ]; then
  usage
fi;
# CCB and Private Network Name must be declared none or together
if [ \( -n "$CCB" -a -z "$PRIVATE_NETWORK_NAME" \) -a \( -z "$CCB" -a -n "$PRIVATE_NETWORK_NAME" \) ]; then
  usage
fi;

# Prepare SSH access
#if [ -n "$KEY_URL" -a -n "$SSH_ACCESS" ]; then
#  mkdir /root/.ssh
#  wget -O - "$KEY_URL" > /root/.ssh/authorized_keys
#fi

#if [ -n "$USER" -a -n "$PASSWORD" -a -n "$SSH_ACCESS" ]; then
#  mkdir /home/$USER && useradd $USER -d /home/$USER -s /bin/bash && echo "$USER:$PASSWORD" | chpasswd && chown -R $USER. /home/$USER/
#fi;

if [ -n "$SSH_ACCESS" ]; then

  cat >> /etc/supervisor/conf.d/supervisord.conf << EOL
[program:sshd]
command=/usr/sbin/sshd -D -p 23
autostart=true
EOL

fi;

# Prepare external config
if [ -n "$CONFIG_MODE" ]; then
  wget -O - "$CONFIG_URL" > /etc/condor/condor_config
fi

# Prepare HTCondor configuration
sed -i \
  -e 's/@CONDOR_HOST@/'"$CONDOR_HOST"'/' \
  -e 's/@ROLE_DAEMONS@/'"$ROLE_DAEMONS"'/' \
  /etc/condor/condor_config

# Prepare right HTCondor healthchecks
sed -i \
  -e 's/@ROLE@/'"$HEALTH_CHECK"'/' \
  /etc/supervisor/conf.d/supervisord.conf

#if [-n "$SCHEDD_HOST"]; then
#  echo "NETWORK_INTERFACE = $INTERFACE" >> /etc/condor/condor_config
#fi
#
#if [-n "$MASTER_HOST"]; then
#  echo "NETWORK_INTERFACE = $INTERFACE" >> /etc/condor/condor_config
#fi
#
#if [-n "$SCHEDD_HOST"]; then
#  echo "NETWORK_INTERFACE = $INTERFACE" >> /etc/condor/condor_config
#fi

# Prepare HTCondor to CCB connection
if [ -n "$CCB" -a -n "$PRIVATE_NETWORK_NAME" -a -n "$SHARED_SECRET" ]; then
  cat >> /etc/condor/condor_config << _EOF_
CCB_ADDRESS = $CCB
PRIVATE_NETWORK_NAME = $PRIVATE_NETWORK_NAME
SEC_PASSWORD_FILE= /etc/condor/condorSharedSecret
SEC_DAEMON_INTEGRITY= REQUIRED
SEC_DAEMON_AUTHENTICATION= REQUIRED
SEC_DAEMON_AUTHENTICATION_METHODS= PASSWORD
SEC_CLIENT_AUTHENTICATION_METHODS= FS, PASSWORD
_EOF_

  condor_store_cred -f /etc/condor/condorSharedSecret -p $SHARED_SECRET
fi

exec /usr/bin/supervisord -c /etc/supervisor/conf.d/supervisord.conf
