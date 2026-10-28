# syntax=docker/dockerfile:1@sha256:4edf897a3ffa55b89f906fc8cc78afdb3f1834cc9c7083565e611a8a7d5fe99e

FROM golang:1.27.3-trixie@sha256:7b072c590a326b9d2a43b165ae247f6e8eafff32e1ad154ab97139e89f053be9 AS builder
WORKDIR /src

COPY --link go.mod go.sum ./

RUN --mount=type=cache,target=/go/pkg/mod go mod download

COPY --link cmd cmd
COPY --link internal internal

RUN --mount=type=cache,target=/go/pkg/mod \
  --mount=type=cache,target=/root/.cache/go-build \
  CGO_ENABLED=0 go build -trimpath -o /out/kea-ha-peers ./cmd/kea-ha-peers

FROM gcr.io/distroless/static-debian13:nonroot@sha256:18f4cc26c9ffa7f20a359298be7deadac5c607c8e03a02b8119f1a5fc2f82c99

LABEL org.opencontainers.image.source=https://github.com/cffnpwr/home-iac

COPY --from=builder --link /out/kea-ha-peers /usr/local/bin/kea-ha-peers

ENTRYPOINT ["/usr/local/bin/kea-ha-peers"]
