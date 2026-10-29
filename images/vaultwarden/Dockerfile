# syntax=docker/dockerfile:1@sha256:4edf897a3ffa55b89f906fc8cc78afdb3f1834cc9c7083565e611a8a7d5fe99e

FROM docker.io/library/rust:1.99.0-slim-trixie@sha256:2752b332db73fdbb7dc576f06c82ed1f312005784ef913d7e04a28f5f55dc581 AS build
WORKDIR /app

ARG VAULTWARDEN_VERSION=1.37.4
ARG VAULTWARDEN_COMMIT=7c188967e7a467b19b2757bc3326f9cf3ccae327

RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
  --mount=type=cache,target=/var/lib/apt,sharing=locked \
  apt-get update \
  && apt-get install -y --no-install-recommends libssl-dev pkgconf

ADD --checksum=${VAULTWARDEN_COMMIT} https://github.com/dani-garcia/vaultwarden.git#${VAULTWARDEN_VERSION} .

RUN --mount=type=cache,target=/usr/local/cargo/registry \
  # NOTE: backendにs3を使用
  VW_VERSION="${VAULTWARDEN_VERSION}" cargo build --locked --features sqlite,s3 --release

# NOTE: web-vault・起動スクリプト・ヘルスチェックは、同じバージョンの公式のイメージのものを使う
FROM docker.io/vaultwarden/server:1.37.4@sha256:efb3cde962015fcc036b2ea625242248611943b27212ebf4392841fb30fad055

LABEL org.opencontainers.image.source=https://github.com/cffnpwr/home-iac

COPY --from=build --link /app/target/release/vaultwarden /vaultwarden
