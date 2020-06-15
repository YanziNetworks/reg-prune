FROM jess/reg:v0.16.0

LABEL maintainer="efrecon@gmail.com"
# OCI Annotation: https://github.com/opencontainers/image-spec/blob/master/annotations.md
LABEL org.opencontainers.image.title="yanzinetworks/reg-prune"
LABEL org.opencontainers.image.description="Prune images from a Docker registry"
LABEL org.opencontainers.image.authors="Emmanuel Frecon <efrecon+github@gmail.com>"
LABEL org.opencontainers.image.url="https://github.com/YanziNetworks/reg-prune"
LABEL org.opencontainers.image.created=${BUILD_DATE}
LABEL org.opencontainers.image.version="1.0"
LABEL org.opencontainers.image.vendor="Yanzi Networks AB"
LABEL org.opencontainers.image.licenses="MIT"

ADD yu.sh/ /usr/local/lib/yu.sh/
ADD reg-prune.sh /usr/local/bin/reg-prune.sh

ENTRYPOINT [ "/usr/local/bin/reg-prune.sh" ]