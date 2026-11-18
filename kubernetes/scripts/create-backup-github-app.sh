#!/bin/sh
set -eu
# NOTE: ShellCheck 0.11.0は、POSIX.1-2024で標準化されたpipefailを未定義として警告
# shellcheck disable=SC3040
set -o pipefail

# NOTE: 初回構築時はbootstrapが出力したsealed_secrets_certを書いたファイルを指定
cert=${SEALED_SECRETS_CERT_FILE:-kubernetes/apps/sealed-secrets/cert.pem}
definition=$(pwd)/.github/apps/backup.yaml
output=kubernetes/apps/sealed-secrets-backup/sealed-secrets-backup-github-app.yaml
private_key_file=sealed-secrets-backup-github-app.pem

is_forced=false
for arg in "$@"; do
  if [ "$arg" = --force ]; then
    is_forced=true
  fi
done
if [ -f "$output" ] && [ "$is_forced" = false ]; then
  echo "$output already exists; --force overwrites it" >&2
  exit 1
fi
# NOTE: 証明書として読めない内容を封入しないよう、封入前に検証
openssl x509 -in "$cert" -noout

work_dir=$(mktemp -d)
trap 'rm -rf "$work_dir"' EXIT

# NOTE: 秘密鍵をリポジトリの外に書き込むため、一時ディレクトリで実行
(cd "$work_dir" && go run "$CREATE_GITHUB_APP" --config "$definition" --repo cffnpwr/home-iac "$@") \
  | tee "$work_dir/output.txt"
client_id=$(sed -n 's/^Client ID: //p' "$work_dir/output.txt")
if [ -z "$client_id" ]; then
  echo "Client ID is not found in the output of create-github-app" >&2
  exit 1
fi

cert_sha256=$(openssl x509 -in "$cert" -noout -fingerprint -sha256 | cut -d = -f 2 | tr -d : | tr '[:upper:]' '[:lower:]')
jq -n --arg client_id "$client_id" --rawfile private_key "$work_dir/$private_key_file" \
  '{
    apiVersion: "v1",
    kind: "Secret",
    metadata: {name: "sealed-secrets-backup-github-app", namespace: "sealed-secrets"},
    data: {"client-id": ($client_id | @base64), "private-key": ($private_key | @base64)}
  }' \
  | kubeseal --cert "$cert" --format json \
  | jq --arg cert "$cert_sha256" '.metadata.annotations += {"home-iac/cert-sha256": $cert}' \
  | yq -p json -o yaml > "$output"
echo "wrote $output"
