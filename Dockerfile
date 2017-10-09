# Dockerizing HTCondor nodes

FROM       centos:centos7
MAINTAINER Manuel Ciangottini <manuel.ciangottini@gmail.com>
ENV        TINI_VERSION v0.9.0
EXPOSE  5000
EXPOSE  22

#--- Environment variables
ENV AMS_USER="amsuser"
ENV AMS_USER_HOME="/home/amsuser"

#RUN curl -sS http://get.onedata.org/oneclient.sh | bash

#--- Patch yum for docker
RUN yum install -y yum-plugin-ovl

#--- Install rpms
RUN yum-config-manager --enable onedata
RUN yum install -y epel-release
RUN yum update -y; yum clean all
RUN yum -y install initscripts
RUN yum -y install freetype fuse sudo glibc-devel glibc-headers
RUN yum -y install man nano emacs openssh-server openssl098e libXext libXpm curl wget vim
RUN yum -y install git gsl-devel freetype-devel libSM libX11-devel libXext-devel make gcc-c++
RUN yum -y install gcc binutils libXpm-devel libXft-devel boost-devel krb5-workstation pam-krb5
RUN yum -y install ncurses ncurses-devel
RUN yum clean all
RUN yum install -y cvs openssh-clients

RUN yum -y install systemd; yum clean all; \
(cd /lib/systemd/system/sysinit.target.wants/; for i in *; do [ $i == systemd-tmpfiles-setup.service ] || rm -f $i; done); \
rm -f /lib/systemd/system/multi-user.target.wants/*; \
rm -f /etc/systemd/system/*.wants/*; \
rm -f /lib/systemd/system/local-fs.tar get.wants/*; \
rm -f /lib/systemd/system/sockets.target.wants/*udev*; \
rm -f /lib/systemd/system/sockets.target.wants/*initctl*; \
rm -f /lib/systemd/system/basic.target.wants/*; \
rm -f /lib/systemd/system/anaconda.target.wants/*;
VOLUME [ “/sys/fs/cgroup” ]

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
RUN mkdir $AMS_USER_HOME/.ssh
RUN chown $AMS_USER:$AMS_USER $AMS_USER_HOME/.ssh

# CMAKE

#RUN wget http://www.cmake.org/files/v3.0/cmake-3.0.0.tar.gz
#RUN tar -zxvf cmake-3.0.0.tar.gz
#WORKDIR /root/cmake-3.0.0
#RUN ./bootstrap
#RUN gmake
#RUN gmake install
#WORKDIR /root
#RUN mv cmake-3.0.0 /usr/local/
#WORKDIR /usr/local/cmake-3.0.0
#RUN mkdir share
#RUN cp -R /usr/local/share/cmake-3.0/ share/

# CONDOR
ADD     https://github.com/krallin/tini/releases/download/${TINI_VERSION}/tini /sbin/tini

WORKDIR /etc/yum.repos.d
RUN	wget http://research.cs.wisc.edu/htcondor/yum/repo.d/htcondor-development-rhel7.repo
RUN     wget http://research.cs.wisc.edu/htcondor/yum/repo.d/htcondor-stable-rhel7.repo
RUN     wget http://research.cs.wisc.edu/htcondor/yum/RPM-GPG-KEY-HTCondor
RUN     rpm --import RPM-GPG-KEY-HTCondor
RUN     yum-config-manager --enable onedata
RUN     yum install -y condor-all
RUN     yum install -y python-pip && pip install supervisor supervisor-stdout && \
        # HEALTHCHECKS
        mkdir -p /opt/health/master/ /opt/health/executor/ /opt/health/submitter/ && \
        pip install Flask

RUN     pip install --upgrade pip && \
#        pip uninstall -y distribute && \
        pip install --upgrade setuptools

# RUN curl -sS http://get.onedata.org/oneclient.sh | bash
# RUN wget -O onedata.repo http://packages.onedata.org/yum/onedata_centos_7x.repo
RUN wget -O onedata.rpm http://onedata-dev-packages.cloud.plgrid.pl/yum/centos/7x/x86_64/oneclient-17.06.0.rc4-1.el7.centos.x86_64.rpm
# RUN yum -y --enablerepo=onedata install oneclient && \
RUN yum -y localinstall onedata.rpm && \
    yum clean all

USER    root
WORKDIR /root
RUN     chmod u+x /sbin/tini

COPY    etc-krb5.conf /etc/krb5.conf
COPY 	supervisord.conf /etc/supervisor/conf.d/supervisord.conf
COPY    condor_config /etc/condor/condor_config
COPY    master_healthcheck.py /opt/health/master/healthcheck.py
COPY    executor_healthcheck.py /opt/health/executor/healthcheck.py
COPY    submitter_healthcheck.py /opt/health/submitter/healthcheck.py
COPY 	sshd_config /etc/ssh/sshd_config
COPY    run.sh /usr/local/sbin/run.sh

RUN     ln -s /usr/lib64/condor /usr/lib/condor
RUN     ln -s /usr/libexec/condor /usr/lib/condor/libexec

ENTRYPOINT ["/sbin/tini", "--", "/usr/local/sbin/run.sh"]
