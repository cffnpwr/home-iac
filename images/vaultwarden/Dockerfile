# syntax=docker/dockerfile:1@sha256:572cebbc2b15e6f84c077742952674889cb63cd5e9b80abdffcbe587b6f19183

FROM rust:1.100.0-slim-trixie@sha256:6f14b2b4b278ec0d50aa1d69541c304ce0f95e0f6268487aa9924af1c2e9aebe AS build
WORKDIR /app

ARG VAULTWARDEN_VERSION=1.37.5
ARG VAULTWARDEN_COMMIT=6ed6921cc2b0e03b4d74189574d2a5e71c512e97

RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
  --mount=type=cache,target=/var/lib/apt,sharing=locked \
  apt-get update \
  && apt-get install -y --no-install-recommends libpq-dev libssl-dev pkgconf

ADD --checksum=${VAULTWARDEN_COMMIT} https://github.com/dani-garcia/vaultwarden.git#${VAULTWARDEN_VERSION} .

RUN --mount=type=cache,target=/usr/local/cargo/registry \
  # NOTE: backendにはs3を使用し、DBはSQLiteからPostgreSQLへの移行のため両方に対応
  VW_VERSION="${VAULTWARDEN_VERSION}" cargo build --locked --features sqlite,postgresql,s3 --release

# NOTE: web-vault・起動スクリプト・ヘルスチェックには、同じバージョンの公式イメージに含まれるものを使う
FROM docker.io/vaultwarden/server:1.37.5@sha256:4fe17f415f90087377d37c755e0ea3cf189dcc6794e49cdd2a9adbb4937d9e1f

LABEL org.opencontainers.image.source=https://github.com/cffnpwr/home-iac

COPY --from=build --link /app/target/release/vaultwarden /vaultwarden
