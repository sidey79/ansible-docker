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

RUN pip install --no-cache-dir ansible-core \
    && ansible-galaxy collection install ansible.posix

RUN mkdir -p /root/.ssh /workspace

WORKDIR /workspace

CMD ["sleep", "infinity"]

