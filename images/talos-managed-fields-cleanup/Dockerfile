# syntax=docker/dockerfile:1@sha256:4edf897a3ffa55b89f906fc8cc78afdb3f1834cc9c7083565e611a8a7d5fe99e

FROM debian:trixie-slim@sha256:62bd423aeee912639ca8ee681c2b762cb3e25137e0a92b20be455898a9f034ad

ARG USER="talos-managed-fields-cleanup"
ARG UID="1001"
ARG GID="1001"

LABEL org.opencontainers.image.source=https://github.com/cffnpwr/home-iac

RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
  --mount=type=cache,target=/var/lib/apt,sharing=locked \
  apt-get update \
  && apt-get install -y --no-install-recommends jq

RUN groupadd --system --gid ${GID} ${USER} \
  && useradd --system --uid ${UID} --gid ${GID} --create-home ${USER}
WORKDIR /home/${USER}

# NOTE: クラスタのKubernetes 1.36系に合わせる
COPY --from=registry.k8s.io/kubectl:v1.36.5@sha256:0667e3f3e6ef435d7cd4c16684244703ebd67314c17511c2a9f87ea44f6cdf6b --link /bin/kubectl /usr/local/bin/

USER ${UID}:${GID}
