FROM ubuntu:22.04

RUN apt update && apt upgrade -y && echo y | unminimize

# Install necessary packages
RUN apt update && \
    apt install -y openssh-server sudo curl wget supervisor nano && \
    rm -rf /var/lib/apt/lists/* && \
    mkdir /var/run/sshd

ADD ./supervisord.conf /etc/supervisor/supervisord.conf

ADD ./init.sh /init.sh

RUN chmod +x /init.sh

# Expose the SSH port
EXPOSE 2222

ENTRYPOINT ["/bin/bash", "-c"]

CMD ["/init.sh"]