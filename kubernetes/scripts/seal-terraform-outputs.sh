#!/bin/sh
set -eu
# NOTE: ShellCheck 0.11.0は、POSIX.1-2024で標準化されたpipefailを未定義として警告
# shellcheck disable=SC3040
set -o pipefail

# NOTE: 封入に使う、controllerの最新の証明書のパス
cert=kubernetes/apps/sealed-secrets/cert.pem

work_dir=$(mktemp -d)
trap 'rm -rf "$work_dir"' EXIT

for name in sealed_secrets sealed_secrets_data_hmac_key sealed_secrets_cert; do
  terraform -chdir=terraform output -json "$name" > "$work_dir/$name.json"
done

if [ -f "$cert" ]; then
  echo "Using $cert."
else
  echo "$cert not found. Using the initial certificate from Terraform."
  mkdir -p "$(dirname "$cert")"
  jq -r . "$work_dir/sealed_secrets_cert.json" > "$cert"
fi
# NOTE: 証明書として読めない内容での封入の防止
openssl x509 -in "$cert" -noout

cert_sha256=$(openssl x509 -in "$cert" -noout -fingerprint -sha256 | cut -d = -f 2 | tr -d : | tr '[:upper:]' '[:lower:]')
hmac_key=$(jq -r . "$work_dir/sealed_secrets_data_hmac_key.json")
jq -r 'keys[]' "$work_dir/sealed_secrets.json" > "$work_dir/paths.txt"

while IFS= read -r path; do
  # NOTE: resourcesに列挙していないファイルは、kustomizeの適用対象外
  kustomization=$(dirname "$path")/kustomization.yaml
  resource=$(basename "$path")
  export resource
  if [ -f "$kustomization" ] && [ "$(yq '.resources // [] | any_c(. == strenv(resource))' "$kustomization")" != true ]; then
    yq -i '.resources += [strenv(resource)]' "$kustomization"
  fi

  entry=$(jq -c --arg path "$path" '.[$path]' "$work_dir/sealed_secrets.json")
  data_hmac_sha256=$(printf '%s' "$(printf '%s' "$entry" | jq -cS .data)" \
    | openssl dgst -sha256 -mac HMAC -macopt "hexkey:$hmac_key" -r | cut -d ' ' -f 1)

  if [ -f "$path" ] \
    && [ "$(yq '.metadata.annotations["home-iac/cert-sha256"] // ""' "$path")" = "$cert_sha256" ] \
    && [ "$(yq '.metadata.annotations["home-iac/data-hmac-sha256"] // ""' "$path")" = "$data_hmac_sha256" ]; then
    echo "$path: up to date"
    continue
  fi

  echo "$path: sealing"
  # NOTE: 既存のファイルにある、controllerが作るSecretのテンプレート（data・labels等）を引き継ぐ
  template='{}'
  if [ -f "$path" ]; then
    template=$(yq -o json '.spec.template // {} | del(.metadata.name, .metadata.namespace, .metadata.creationTimestamp)' "$path")
  fi
  mkdir -p "$(dirname "$path")"
  printf '%s' "$entry" \
    | jq '{apiVersion: "v1", kind: "Secret", metadata: {name, namespace}, data: (.data | map_values(@base64))}' \
    | kubeseal --cert "$cert" --format json \
    | jq --arg cert "$cert_sha256" --arg hmac "$data_hmac_sha256" --argjson template "$template" \
      '.metadata.annotations += {"home-iac/cert-sha256": $cert, "home-iac/data-hmac-sha256": $hmac}
      | .spec.template *= $template' \
    | yq -p json -o yaml > "$path"
done < "$work_dir/paths.txt"
