#!/bin/sh
set -eu
# NOTE: ShellCheck 0.11.0は、POSIX.1-2024で標準化されたpipefailを未定義として警告
# shellcheck disable=SC3040
set -o pipefail

controller_name=sealed-secrets-controller
controller_namespace=sealed-secrets

work_dir=$(mktemp -d)
trap 'rm -rf "$work_dir"' EXIT

kubeseal --fetch-cert --controller-name "$controller_name" --controller-namespace "$controller_namespace" > "$work_dir/cert.pem"
cert_sha256=$(openssl x509 -in "$work_dir/cert.pem" -noout -fingerprint -sha256 | cut -d = -f 2 | tr -d : | tr '[:upper:]' '[:lower:]')
reencrypted=$work_dir/reencrypted.yaml
export cert_sha256 reencrypted

find kubernetes -name '*.yaml' -type f | sort | while IFS= read -r path; do
  if [ "$(yq '.kind' "$path")" != SealedSecret ]; then
    continue
  fi
  if [ "$(yq '.metadata.annotations["home-iac/cert-sha256"] // ""' "$path")" = "$cert_sha256" ]; then
    echo "$path: up to date"
    continue
  fi

  echo "$path: re-encrypting"
  kubeseal --re-encrypt --controller-name "$controller_name" --controller-namespace "$controller_namespace" --format yaml \
    < "$path" > "$reencrypted"
  # NOTE: --re-encryptがspec.template.dataを残さないため、再暗号化した暗号文だけを元のファイルに反映
  yq -i '.spec.encryptedData = load(strenv(reencrypted)).spec.encryptedData
    | .metadata.annotations["home-iac/cert-sha256"] = strenv(cert_sha256)' "$path"
done
