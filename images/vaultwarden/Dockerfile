# syntax=docker/dockerfile:1@sha256:4edf897a3ffa55b89f906fc8cc78afdb3f1834cc9c7083565e611a8a7d5fe99e

FROM docker.io/library/rust:1.99.1-slim-trixie@sha256:f6c4a35d21dbb3c89d7a8d056c193e94fc09037f2b58dd858b09c39a47dd02d7 AS build
WORKDIR /app

ARG VAULTWARDEN_VERSION=1.37.5
ARG VAULTWARDEN_COMMIT=6ed6921cc2b0e03b4d74189574d2a5e71c512e97

RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
  --mount=type=cache,target=/var/lib/apt,sharing=locked \
  apt-get update \
  && apt-get install -y --no-install-recommends libpq-dev libssl-dev pkgconf

ADD --checksum=${VAULTWARDEN_COMMIT} https://github.com/dani-garcia/vaultwarden.git#${VAULTWARDEN_VERSION} .

RUN --mount=type=cache,target=/usr/local/cargo/registry \
  # NOTE: backendにs3を使用。DBはSQLiteからPostgreSQLへの移行のため両方に対応
  VW_VERSION="${VAULTWARDEN_VERSION}" cargo build --locked --features sqlite,postgresql,s3 --release

# NOTE: web-vault・起動スクリプト・ヘルスチェックは、同じバージョンの公式のイメージのものを使う
FROM docker.io/vaultwarden/server:1.37.5@sha256:4fe17f415f90087377d37c755e0ea3cf189dcc6794e49cdd2a9adbb4937d9e1f

LABEL org.opencontainers.image.source=https://github.com/cffnpwr/home-iac

COPY --from=build --link /app/target/release/vaultwarden /vaultwarden
