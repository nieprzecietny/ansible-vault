# syntax=docker/dockerfile:1
#
# ansible-vault, and nothing else.
#
# Stage 1 assembles a minimal RHEL 10 root filesystem from the Red Hat UBI
# repositories (always the latest packages at build time, which is how RHEL
# errata reach the image on every scheduled rebuild). Stage 2 is that root
# filesystem on top of `scratch`: no package manager, no pip, no editors, no
# pager, no network tools. The RPM database is kept so scanners (Trivy, Grype)
# can see exactly what is inside.

FROM registry.access.redhat.com/ubi10/ubi:latest@sha256:a75ad754aa048d808dd3260243452f8c9a665831d0493b4c9d92f0c88fe2f8c3 AS builder

# hadolint ignore=DL3041  # unpinned on purpose: every rebuild must pick up the newest RHEL errata
RUN dnf install -y --nodocs --setopt=install_weak_deps=0 python3-pip \
 && mkdir -p /rootfs \
 && dnf install -y --installroot /rootfs --releasever 10 --nodocs --setopt=install_weak_deps=0 \
      redhat-release filesystem setup bash coreutils-single python3 \
 && dnf --installroot /rootfs clean all \
 && rm -rf /rootfs/var/cache/* /rootfs/var/log/* /rootfs/var/lib/dnf /rootfs/etc/dnf /rootfs/etc/yum.repos.d

COPY requirements.txt /tmp/requirements.txt
RUN python3 -m pip install --no-cache-dir --no-compile --require-hashes \
      --root /rootfs --prefix /usr/local -r /tmp/requirements.txt \
 && python3 -m compileall -q -s /rootfs /rootfs/usr/local/lib/python3.12/site-packages \
 # ansible-core ships a dozen CLIs; only the vault one belongs in this image
 && find /rootfs/usr/local/bin -mindepth 1 ! -name ansible-vault -delete \
 && rm -rf /rootfs/usr/local/lib/python3.12/site-packages/ansible_test \
 && echo 'ansible:x:1000:1000:ansible-vault:/tmp:/sbin/nologin' >> /rootfs/etc/passwd \
 && echo 'ansible:x:1000:' >> /rootfs/etc/group

FROM scratch
COPY --from=builder /rootfs/ /

# PAGER=cat: `view` pipes through $PAGER on a TTY and there is no less in here.
# ANSIBLE_HOME on /tmp lets the container run read-only and under any --user.
ENV LANG=C.UTF-8 \
    PAGER=cat \
    PYTHONDONTWRITEBYTECODE=1 \
    ANSIBLE_HOME=/tmp/.ansible \
    PATH=/usr/local/bin:/usr/bin:/bin

USER 1000:1000
WORKDIR /work
ENTRYPOINT ["ansible-vault"]
CMD ["--help"]
