ARG IMAGE_REVISION=development
ARG PHORGE_REVISION=20aaead687fcc9376560adfa57c13a2201faedd4
ARG ARCANIST_REVISION=63de5a2953b79dbe6aac4ed92bdb64b45cad53d6

FROM registry.access.redhat.com/ubi10/ubi-init:10.2

ARG IMAGE_REVISION
ARG PHORGE_REVISION
ARG ARCANIST_REVISION

ARG PHORGE_UID=10001
ARG PHORGE_GID=10001

ARG PHORGE_ROOT=/app/phorge
ARG PHORGE_DATA=/var/lib/phorge
ARG ARCANIST_ROOT=/app/arcanist

ENV LANG=C.UTF-8

LABEL org.opencontainers.image.title="Phorge" \
      org.opencontainers.image.description="Phorge with systemd, nginx, PHP-FPM, and dedicated Git SSH" \
      org.opencontainers.image.source="https://github.com/zengxs/phorge-docker" \
      org.opencontainers.image.revision="${IMAGE_REVISION}" \
      io.phorge.component.phorge.revision="${PHORGE_REVISION}" \
      io.phorge.component.arcanist.revision="${ARCANIST_REVISION}"

RUN set -eux \
    && dnf -y --setopt=install_weak_deps=False install \
        https://dl.fedoraproject.org/pub/epel/epel-release-latest-10.noarch.rpm \
    && dnf -y --setopt=install_weak_deps=False install \
        ca-certificates curl git git-lfs sudo \
        subversion mercurial \
        nginx openssh-server \
        ImageMagick \
        php-bcmath php-cli php-curl php-fpm php-gd php-intl php-mbstring php-mysqlnd \
        php-opcache php-pecl-apcu php-process php-xml php-zip \
        python3 python3-jinja2 python3-pygments \
        patch diffutils which findutils tar gzip unzip \
    && dnf -y clean all \
    && rm -rf /var/cache/dnf \
    && rm -f /etc/nginx/conf.d/php-fpm.conf /etc/php-fpm.d/www.conf \
    && groupadd --gid "${PHORGE_GID}" phorge \
    && useradd --uid "${PHORGE_UID}" --gid phorge \
        --home-dir ${PHORGE_DATA} --create-home \
        --shell /sbin/nologin phorge \
    && install -d -o phorge -g phorge -m 0750 \
        /var/lib/phorge/repositories \
        /var/lib/phorge/files \
        /var/lib/phorge/working-copies \
        /var/lib/phorge/daemon

COPY --chown=phorge:nginx ./phorge/ ${PHORGE_ROOT}/
COPY --chown=phorge:nginx ./arcanist/ ${ARCANIST_ROOT}/

RUN set -eux; \
    install_git_metadata() { \
        component="$1"; \
        work_tree="$2"; \
        remote="$3"; \
        revision="$4"; \
        case "${revision}" in \
            *[!0-9a-f]*|'') \
                echo "${component} revision must be a lowercase hexadecimal Git object ID" >&2; \
                exit 1; \
                ;; \
        esac; \
        if [ "${#revision}" -ne 40 ]; then \
            echo "${component} revision must contain exactly 40 characters" >&2; \
            exit 1; \
        fi; \
        git_safe() { \
            git -c safe.directory="${work_tree}" -C "${work_tree}" "$@"; \
        }; \
        git_safe init --quiet --initial-branch=master; \
        git_safe remote add origin "${remote}"; \
        git_safe -c protocol.version=2 fetch \
            --quiet --depth=1 --filter=blob:none origin "${revision}"; \
        if [ "$(git_safe rev-parse FETCH_HEAD)" != "${revision}" ]; then \
            echo "${component} remote returned an unexpected revision" >&2; \
            exit 1; \
        fi; \
        git_safe update-ref refs/heads/master "${revision}"; \
        git_safe update-ref refs/remotes/origin/master "${revision}"; \
        git_safe symbolic-ref HEAD refs/heads/master; \
        verification_root="$(mktemp -d "/tmp/${component}-tree.XXXXXX")"; \
        mkdir -p "${verification_root}/objects"; \
        GIT_INDEX_FILE="${verification_root}/index" \
        GIT_OBJECT_DIRECTORY="${verification_root}/objects" \
        GIT_ALTERNATE_OBJECT_DIRECTORIES="${work_tree}/.git/objects" \
            git_safe read-tree "${revision}"; \
        GIT_INDEX_FILE="${verification_root}/index" \
        GIT_OBJECT_DIRECTORY="${verification_root}/objects" \
        GIT_ALTERNATE_OBJECT_DIRECTORIES="${work_tree}/.git/objects" \
            git_safe add -A; \
        source_tree="$( \
            GIT_INDEX_FILE="${verification_root}/index" \
            GIT_OBJECT_DIRECTORY="${verification_root}/objects" \
            GIT_ALTERNATE_OBJECT_DIRECTORIES="${work_tree}/.git/objects" \
                git_safe write-tree \
        )"; \
        expected_tree="$(git_safe rev-parse "${revision}^{tree}")"; \
        rm -rf -- "${verification_root}"; \
        if [ "${source_tree}" != "${expected_tree}" ]; then \
            echo "${component} source tree does not match ${revision}" >&2; \
            exit 1; \
        fi; \
        chown -R phorge:nginx "${work_tree}/.git"; \
    }; \
    install_git_metadata \
        phorge "${PHORGE_ROOT}" \
        https://github.com/phorgeit/phorge.git "${PHORGE_REVISION}"; \
    install_git_metadata \
        arcanist "${ARCANIST_ROOT}" \
        https://github.com/phorgeit/arcanist.git "${ARCANIST_REVISION}"

COPY ./rootfs/ /

RUN chmod 0755 /usr/libexec/phorge-prepare /usr/libexec/phorge-storage-upgrade \
    && chmod -R g+rX ${PHORGE_ROOT} ${ARCANIST_ROOT} \
    && systemctl disable sshd.service \
    && systemctl mask sshd.service \
    && systemctl enable nginx php-fpm phorge-phd phorge-sshd phorge-storage-upgrade

VOLUME ["/var/lib/phorge"]

EXPOSE 80 22
STOPSIGNAL SIGRTMIN+3
CMD ["/usr/sbin/init"]
