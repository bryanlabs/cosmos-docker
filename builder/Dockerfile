FROM golang:1.23-alpine

RUN apk add --update --no-cache ca-certificates make git bash gcc linux-headers eudev-dev ncurses-dev openssh curl jq musl-dev && rm -rf /var/cache/apk/\*

WORKDIR /src

RUN mkdir /builds

COPY docker-entrypoint.sh /usr/local/bin/

ENTRYPOINT [ "docker-entrypoint.sh" ]
