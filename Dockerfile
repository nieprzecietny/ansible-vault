# syntax=docker/dockerfile:1
FROM python:3.12-slim

ARG ANSIBLE_VERSION=9.12.0

# minimalne paczki, przydatne też jak kiedyś dojdzie git/ssh
RUN apt-get update && apt-get install -y --no-install-recommends \
      ca-certificates \
      openssh-client \
      git \
    && rm -rf /var/lib/apt/lists/*

# Ansible (ansible-vault jest w pakiecie)
RUN pip install --no-cache-dir "ansible==${ANSIBLE_VERSION}"

# nie róbmy tego jako root
RUN useradd -m -u 1000 ansible
USER ansible

WORKDIR /work

# domyślnie odpalaj ansible-vault
ENTRYPOINT ["ansible-vault"]
CMD ["--help"]
