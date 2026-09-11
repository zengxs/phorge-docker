# ========================= dinit-builder  ========================= #
FROM registry.access.redhat.com/ubi10:10.2 AS dinit-builder

ARG DINIT_GIT_URL=https://github.com/davmac314/dinit.git
ARG DINIT_GIT_REV=b3ba792ca723e2c137cbc64d8967387039dbac16  # v0.22.1

RUN set -euo pipefail \
    && dnf -y install git-core gcc gcc-c++ make m4 \
    && git clone --depth 1 --revision "${DINIT_GIT_REV}" "${DINIT_GIT_URL}" /usr/src/dinit \
    && cd /usr/src/dinit \
    && ./configure \
        --prefix=/opt/dinit \
        --disable-shutdown \
        --disable-cgroups \
        --disable-capabilities \
        --disable-ioprio \
    && make \
    && make install


# ========================= runtime ========================= #
FROM registry.access.redhat.com/ubi10:10.2

ARG PHORGE_GIT_URL=https://github.com/phorgeit/phorge.git
ARG PHORGE_GIT_REV
ARG ARCANIST_GIT_URL=https://github.com/phorgeit/arcanist.git
ARG ARCANIST_GIT_REV

ARG PHORGE_UID=65532
ARG PHORGE_GID=65532
ARG GIT_UID=65533
ARG GIT_GID=65533

ARG PHORGE_ROOT=/opt/phorge
ARG ARCANIST_ROOT=/opt/arcanist

ARG PHORGE_DATA=/var/lib/phorge
ARG GIT_HOME=/var/empty

ENV LANG=C.UTF-8

LABEL org.opencontainers.image.title="Phorge" \
      org.opencontainers.image.description="Phorge with Dinit, nginx, PHP-FPM, and dedicated Git SSH" \
      org.opencontainers.image.source="https://github.com/zengxs/phorge-docker" \
      io.phorge.component.phorge.revision="${PHORGE_GIT_REV}" \
      io.phorge.component.arcanist.revision="${ARCANIST_GIT_REV}"

RUN set -euo pipefail \
    && dnf -y install \
        ca-certificates curl sudo \
        git-core git-lfs subversion \
        nginx openssh-server rsyslog logrotate util-linux procps-ng \
        php-bcmath php-cli php-curl php-fpm php-gd php-intl php-mbstring php-mysqlnd \
        php-opcache php-pecl-apcu php-process php-xml php-zip \
        python3 python3-jinja2 python3-pygments \
        patch diffutils which findutils tar gzip unzip zstd \
    && dnf -y install https://dl.fedoraproject.org/pub/epel/epel-release-latest-10.noarch.rpm \
    && dnf -y install ImageMagick mercurial \
    && dnf -y clean all \
    && rm -rf /var/cache/dnf \
    && rm -f /etc/nginx/conf.d/php-fpm.conf /etc/php-fpm.d/www.conf \
    && groupadd --gid "${PHORGE_GID}" phorge \
    && useradd --uid "${PHORGE_UID}" --gid phorge \
        --home-dir "${PHORGE_DATA}" --create-home \
        --shell /sbin/nologin phorge \
    && groupadd --gid "${GIT_GID}" git \
    && useradd --uid "${GIT_UID}" --gid git --groups phorge \
        --home-dir "${GIT_HOME}" --no-create-home \
        --shell /bin/sh --password NP git \
    && install -d -o root -g root -m 0755 "${GIT_HOME}"

# Git uses a shell for forced SSH commands and the phorge group to read config.
# NP is an unusable, non-locked password: OpenSSH rejects locked accounts even
# for key authentication. Password login is disabled in the generated sshd config.

RUN set -euo pipefail \
    && git clone --depth 1 --revision "${PHORGE_GIT_REV}" "${PHORGE_GIT_URL}" "${PHORGE_ROOT}" \
    && git clone --depth 1 --revision "${ARCANIST_GIT_REV}" "${ARCANIST_GIT_URL}" "${ARCANIST_ROOT}" \
    && git config --system --add safe.directory "${PHORGE_ROOT}" \
    && git config --system --add safe.directory "${ARCANIST_ROOT}"

COPY --from=dinit-builder /opt/dinit/ /opt/dinit/
COPY ./rootfs/ /

RUN install -d -o root -g root -m 0755 /var/log/phorge/logs \
    && chmod 0755 /usr/libexec/phorge-prepare /usr/libexec/phorge-storage-upgrade \
        /usr/libexec/phorge-runtime-init /usr/libexec/phorge-phd-start \
        /usr/libexec/phorge-entrypoint /usr/libexec/phorge-log-output \
        /usr/libexec/phorge-logrotate /usr/libexec/phorge-log-relay \
        /usr/libexec/phorge-log-fifo \
    && chmod -R g+rX "${PHORGE_ROOT}" "${ARCANIST_ROOT}" \
    && ln -s /opt/dinit/bin/dinitctl /usr/local/bin/dinitctl \
    && ln -s /opt/dinit/bin/dinit-check /usr/local/bin/dinit-check \
    && /opt/dinit/bin/dinit-check --services-dir /etc/dinit.d boot \
    && install -d -o root -g root -m 0700 /var/lib/phorge/rsyslog \
    && /usr/sbin/rsyslogd -N1 -f /etc/rsyslog.conf \
    && /usr/sbin/nginx -t \
    && /usr/sbin/php-fpm -t

VOLUME ["/var/lib/phorge"]

EXPOSE 80 22
STOPSIGNAL SIGTERM
ENTRYPOINT ["/usr/libexec/phorge-entrypoint"]
CMD ["/opt/dinit/bin/dinit", "--container", "--services-dir", "/etc/dinit.d", "--log-file", "/run/rsyslog/dinit-service.fifo"]
