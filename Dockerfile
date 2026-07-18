FROM golang:1.26-alpine AS wireproxy-builder

ARG WIREPROXY_VERSION=v1.1.3

RUN apk add --no-cache git patch ca-certificates

COPY patches /patches

RUN git clone --depth 1 --branch "${WIREPROXY_VERSION}" \
        https://github.com/windtf/wireproxy.git /src/wireproxy \
    && cd /src/wireproxy \
    && git apply /patches/wireproxy-configurable-resources.patch \
    && go mod download \
    && WIREGUARD_DIR="$(go list -m -f '{{.Dir}}' golang.zx2c4.com/wireguard)" \
    && chmod u+w "${WIREGUARD_DIR}/tun/netstack/tun.go" \
    && patch -d "${WIREGUARD_DIR}" -p1 < /patches/wireguard-go-tcp-buffers.patch \
    && go test ./... \
    && CGO_ENABLED=0 go build -trimpath \
        -ldflags="-s -w -X main.version=${WIREPROXY_VERSION}" \
        -o /out/wireproxy ./cmd/wireproxy

FROM virb3/wgcf:2.2.31 AS wgcf-bin

FROM alpine:3.22

RUN apk add --no-cache ca-certificates curl netcat-openbsd

COPY --from=wgcf-bin /wgcf /usr/local/bin/wgcf
COPY --from=wireproxy-builder /out/wireproxy /usr/local/bin/wireproxy
COPY entrypoint.sh /usr/local/bin/entrypoint.sh

RUN chmod 0755 /usr/local/bin/entrypoint.sh /usr/local/bin/wgcf /usr/local/bin/wireproxy \
    && mkdir -p /data

WORKDIR /data
VOLUME ["/data"]
EXPOSE 1080

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
