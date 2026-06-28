FROM debian:bookworm-slim

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
       bash \
       ca-certificates \
       cifs-utils \
       e2fsprogs \
       openssh-server \
       python3-apt \
       samba \
       sudo \
       util-linux \
       python3 \
    && rm -rf /var/lib/apt/lists/*

RUN mkdir -p /run/sshd /var/log/samba /srv/fritz.nas /etc/samba /etc/ssh

COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod 0755 /usr/local/bin/entrypoint.sh

EXPOSE 22 445

CMD ["/usr/local/bin/entrypoint.sh"]
