FROM golang:1.26-alpine AS wireproxy-builder

ARG WIREPROXY_VERSION=v1.1.3

RUN apk add --no-cache git ca-certificates \
    && CGO_ENABLED=0 go install github.com/windtf/wireproxy/cmd/wireproxy@${WIREPROXY_VERSION}

FROM virb3/wgcf:2.2.31 AS wgcf-bin

FROM alpine:3.22

RUN apk add --no-cache ca-certificates curl netcat-openbsd

COPY --from=wgcf-bin /wgcf /usr/local/bin/wgcf
COPY --from=wireproxy-builder /go/bin/wireproxy /usr/local/bin/wireproxy
COPY entrypoint.sh /usr/local/bin/entrypoint.sh

RUN chmod 0755 /usr/local/bin/entrypoint.sh /usr/local/bin/wgcf /usr/local/bin/wireproxy \
    && mkdir -p /data

WORKDIR /data
VOLUME ["/data"]
EXPOSE 1080

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
