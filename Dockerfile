# Dockerizing HTCondor submit node

FROM 	   cern/slc6-base
MAINTAINER Manuel Ciangottini <manuel.ciangottini@gmail.com>
ENV 	   TINI_VERSION v0.9.0
EXPOSE  5000
EXPOSE  22

#--- Environment variables
ENV AMS_USER="amsuser"
ENV AMS_USER_HOME="/home/amsuser"

#--- Patch yum for docker
RUN yum install -y yum-plugin-ovl

#--- Install rpms
RUN yum update -y; yum clean all
RUN yum -y install \
    freetype fuse sudo glibc-devel glibc-headers libstdc++-devel curl wget \
    man nano openssh-server openssl098e libXext libXpm \
    git gsl-devel freetype-devel libSM libX11-devel libXext-devel make gcc-c++ \
    gcc binutils libXpm-devel libXft-devel boost-devel \
    cmake ncurses ncurses-devel; \
    yum clean all
RUN yum install -y cvs openssh-clients

WORKDIR /root

# Setting up a user
RUN adduser $AMS_USER -d $AMS_USER_HOME && echo "$AMS_USER:ams" | chpasswd && \
    echo "$AMS_USER ALL=(root) NOPASSWD:ALL" > /etc/sudoers.d/$AMS_USER && \
    chmod 0440 /etc/sudoers.d/$AMS_USER
RUN chown -R $AMS_USER $AMS_USER_HOME

COPY setup_amsenv.sh  $AMS_USER_HOME
RUN chown -R $AMS_USER $AMS_USER_HOME/setup_amsenv.sh

COPY dot-bashrc  $AMS_USER_HOME/.bashrc
RUN chown $AMS_USER $AMS_USER_HOME/.bashrc
RUN chmod u+x $AMS_USER_HOME/setup_amsenv.sh

# CONDOR
ADD     https://github.com/krallin/tini/releases/download/${TINI_VERSION}/tini /sbin/tini

WORKDIR /etc/yum.repos.d
RUN	wget http://research.cs.wisc.edu/htcondor/yum/repo.d/htcondor-development-rhel6.repo
RUN     wget http://research.cs.wisc.edu/htcondor/yum/repo.d/htcondor-stable-rhel6.repo
RUN     wget http://research.cs.wisc.edu/htcondor/yum/RPM-GPG-KEY-HTCondor
RUN     rpm --import RPM-GPG-KEY-HTCondor
RUN     yum install -y condor-all python-pip && pip install supervisor supervisor-stdout && \
        # HEALTHCHECKS
        mkdir -p /opt/health/master/ /opt/health/executor/ /opt/health/submitter/ && \
        pip install Flask

COPY 	supervisord.conf /etc/supervisor/conf.d/supervisord.conf
COPY    condor_config /etc/condor/condor_config
COPY    master_healthcheck.py /opt/health/master/healthcheck.py
COPY    executor_healthcheck.py /opt/health/executor/healthcheck.py
COPY    submitter_healthcheck.py /opt/health/submitter/healthcheck.py
COPY 	sshd_config /etc/ssh/sshd_config
COPY    run.sh /usr/local/sbin/run.sh

ENTRYPOINT ["/sbin/tini", "--", "/usr/local/sbin/run.sh"]
