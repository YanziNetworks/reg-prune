FROM jess/reg:v0.16.0

LABEL maintainer="efrecon@gmail.com"
LABEL org.label-schema.build-date=${BUILD_DATE}
LABEL org.label-schema.schema-version="1.0"
LABEL org.label-schema.name="yanzinetworks/reg-prune"
LABEL org.label-schema.description="Prune images from a Docker registry"
LABEL org.label-schema.url="https://github.com/YanziNetworks/reg-prune"
LABEL org.label-schema.docker.cmd="docker run -it --rm -v $HOME/.docker:/root/.docker:ro yanzinetworks/reg-prune --help"

ADD yu.sh/ /usr/local/lib/yu.sh/
ADD reg-prune.sh /usr/local/bin/reg-prune.sh

ENTRYPOINT [ "/usr/local/bin/reg-prune.sh" ]