# syntax=docker/dockerfile:1@sha256:4edf897a3ffa55b89f906fc8cc78afdb3f1834cc9c7083565e611a8a7d5fe99e

FROM rust:1.99.1-slim-trixie@sha256:b8e062b1c3a80183df83d9ba187cadd2b5ab84bc78d453dbfeb2fccd5f982247 AS age-plugin-yubikey
WORKDIR /work

ARG AGE_PLUGIN_YUBIKEY_VERSION=0.5.1

RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
  --mount=type=cache,target=/var/lib/apt,sharing=locked \
  apt-get update \
  && apt-get install -y --no-install-recommends libpcsclite-dev pkgconf

# NOTE: age-plugin-yubikeyはarm64向けのビルド済みバイナリを配布していないため、ソースからビルドする
RUN --mount=type=cache,target=/usr/local/cargo/registry \
  cargo install --locked --version "${AGE_PLUGIN_YUBIKEY_VERSION}" --root /usr/local age-plugin-yubikey

# NOTE: Debianのageパッケージはtag受信者（age1tag1…）に対応しない1.2系のため、公式リリースを使う
FROM debian:trixie-slim@sha256:62bd423aeee912639ca8ee681c2b762cb3e25137e0a92b20be455898a9f034ad AS age
WORKDIR /work

RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
  --mount=type=cache,target=/var/lib/apt,sharing=locked \
  apt-get update \
  && apt-get install -y --no-install-recommends ca-certificates curl jq

COPY --from=ghcr.io/sigstore/cosign/cosign:v3.1.4@sha256:0f06154836d2de34f887a5c273506d52ca43edaa1d9e53e6510fa78a48f69c2d --link /ko-app/cosign /usr/local/bin/

ARG TARGETARCH
ARG AGE_VERSION=v1.3.2
RUN curl -fsSL -o age.tar.gz "https://github.com/FiloSottile/age/releases/download/${AGE_VERSION}/age-${AGE_VERSION}-linux-${TARGETARCH}.tar.gz"
RUN curl -fsSL "https://api.github.com/repos/FiloSottile/age/attestations/sha256:$(sha256sum age.tar.gz | cut -d ' ' -f 1)" \
  | jq -e '.attestations[0].bundle' > bundle.json
# NOTE: GitHubのartifact attestationで検証
RUN cosign verify-blob-attestation \
  --bundle bundle.json \
  --type slsaprovenance1 \
  --certificate-oidc-issuer https://token.actions.githubusercontent.com \
  --certificate-identity "https://github.com/FiloSottile/age/.github/workflows/build.yml@refs/tags/${AGE_VERSION}" \
  age.tar.gz
RUN tar -xzf age.tar.gz -C /usr/local/bin --strip-components=1 age/age

FROM debian:trixie-slim@sha256:62bd423aeee912639ca8ee681c2b762cb3e25137e0a92b20be455898a9f034ad AS runtime

ARG USER="sealed-secrets-backup"
ARG UID="1001"
ARG GID="1001"

LABEL org.opencontainers.image.source=https://github.com/cffnpwr/home-iac

# NOTE: libpcsclite1はage-plugin-yubikey用、curl・jq・opensslはrepository_dispatchの送信用
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
  --mount=type=cache,target=/var/lib/apt,sharing=locked \
  apt-get update \
  && apt-get install -y --no-install-recommends ca-certificates curl jq libpcsclite1 openssl

# NOTE: kubectlがホームディレクトリにキャッシュを書く
RUN groupadd --system --gid ${GID} ${USER} \
  && useradd --system --uid ${UID} --gid ${GID} --create-home ${USER}
WORKDIR /home/${USER}

COPY --from=age-plugin-yubikey --link /usr/local/bin/age-plugin-yubikey /usr/local/bin/
COPY --from=age --link /usr/local/bin/age /usr/local/bin/
# NOTE: クラスタのKubernetes 1.36系に合わせる
COPY --from=registry.k8s.io/kubectl:v1.36.5@sha256:0667e3f3e6ef435d7cd4c16684244703ebd67314c17511c2a9f87ea44f6cdf6b --link /bin/kubectl /usr/local/bin/
# NOTE: クラスタのsealed-secrets controller 0.40.0に合わせる
COPY --from=docker.io/bitnami/sealed-secrets-kubeseal:0.41.2@sha256:6697225a70537d94061b56e6a138ba9ca26307a702f827dac0a77b0a007bc84f --link /usr/local/bin/kubeseal /usr/local/bin/
COPY --from=rclone/rclone:1.75.2@sha256:2687085f718d3c628f7fdfb77c52a1d344332aed543110bb88088f2c70d43eb5 --link /usr/local/bin/rclone /usr/local/bin/

USER ${UID}:${GID}
