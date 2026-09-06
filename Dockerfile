FROM python:3.12-slim

ENV DEBIAN_FRONTEND=noninteractive \
    PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
       openssh-client \
       sshpass \
       git \
       ca-certificates \
    && rm -rf /var/lib/apt/lists/*

RUN pip install --no-cache-dir "ansible-core>=2.19,<2.20" "passlib>=1.7.4"

COPY requirements.yml /tmp/requirements.yml

# Install into the system-wide collection path rather than /root/.ansible, so the
# collections stay visible when the container runs as the unprivileged user.
RUN ansible-galaxy collection install -r /tmp/requirements.yml \
       -p /usr/share/ansible/collections \
    && rm -f /tmp/requirements.yml

# The container writes into the bind-mounted repository (fetched assets, generated
# manifests). Running as root left those files owned by root on the host, which
# blocked git and required sudo to clean up. UID/GID 1000 matches the host user.
RUN groupadd --gid 1000 ansible \
    && useradd --uid 1000 --gid 1000 --create-home --shell /bin/bash ansible \
    && mkdir -p /home/ansible/.ssh /workspace \
    && chmod 0700 /home/ansible/.ssh \
    && chown -R ansible:ansible /home/ansible /workspace

USER ansible

WORKDIR /workspace

CMD ["sleep", "infinity"]
