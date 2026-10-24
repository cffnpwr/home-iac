# syntax=docker/dockerfile:1@sha256:4edf897a3ffa55b89f906fc8cc78afdb3f1834cc9c7083565e611a8a7d5fe99e

FROM rust:1.99.1-slim-trixie@sha256:aab42391a986424e22d6a3ec14f37bc6dd3dacff4d457ca7cccd781e02297cc6 AS age-plugin-yubikey
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

LABEL org.opencontainers.image.source=https://github.com/cffnpwr/home-iac

# NOTE: age-plugin-yubikeyはlibpcsclite.so.1を動的リンクする
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
  --mount=type=cache,target=/var/lib/apt,sharing=locked \
  apt-get update \
  && apt-get install -y --no-install-recommends ca-certificates libpcsclite1

# NOTE: kubectlがホームディレクトリにキャッシュを書く
RUN groupadd --system --gid 1001 sealed-secrets-backup \
  && useradd --system --uid 1001 --gid 1001 --create-home sealed-secrets-backup
WORKDIR /home/sealed-secrets-backup

COPY --from=age-plugin-yubikey --link /usr/local/bin/age-plugin-yubikey /usr/local/bin/
COPY --from=age --link /usr/local/bin/age /usr/local/bin/
# NOTE: クラスタのKubernetes 1.36系に合わせる
COPY --from=registry.k8s.io/kubectl:v1.36.5@sha256:0667e3f3e6ef435d7cd4c16684244703ebd67314c17511c2a9f87ea44f6cdf6b --link /bin/kubectl /usr/local/bin/
# NOTE: クラスタのsealed-secrets controller 0.40.0に合わせる
COPY --from=docker.io/bitnami/sealed-secrets-kubeseal:0.40.0@sha256:3401dfa2e51877380ede1364ca0a02442c1db1c00adf52a33f1c67815750805d --link /usr/local/bin/kubeseal /usr/local/bin/
COPY --from=rclone/rclone:1.75.2@sha256:2687085f718d3c628f7fdfb77c52a1d344332aed543110bb88088f2c70d43eb5 --link /usr/local/bin/rclone /usr/local/bin/

USER 1001:1001
