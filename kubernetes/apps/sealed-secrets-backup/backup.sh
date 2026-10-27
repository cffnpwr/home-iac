#!/bin/sh
set -eu
# NOTE: ShellCheck 0.11.0は、POSIX.1-2024で標準化されたpipefailを未定義として警告
# shellcheck disable=SC3040
set -o pipefail

controller_name=sealed-secrets-controller
controller_namespace=sealed-secrets
bucket=r2:home-iac-sealed-secrets-keys
repository=cffnpwr/home-iac
event_type=sealed-secrets-key-added
github_api=https://api.github.com

# NOTE: PEMの改行の差を無視して比べるための、ヘッダー行・フッター行を除いたbase64の抽出
pem_body() {
  grep -v -e '-----' | tr -d '\r\n'
}

base64url() {
  openssl base64 -A | tr '+/' '-_' | tr -d '='
}

echo "triggered by ${TRIGGER_NAME}"

kubeseal --fetch-cert --controller-name "${controller_name}" --controller-namespace "${controller_namespace}" > "${WORK_DIR}/cert.pem"
latest=$(pem_body < "${WORK_DIR}/cert.pem")

kubectl get secrets -n "${controller_namespace}" -l sealedsecrets.bitnami.com/sealed-secrets-key=active \
  -o jsonpath='{range .items[*]}{.metadata.uid}{" "}{.metadata.name}{"\n"}{end}' > "${WORK_DIR}/keys.txt"

backed_up_latest=false
while read -r uid name <&3; do
  cert=$(kubectl get secrets -n "${controller_namespace}" "${name}" -o jsonpath='{.data.tls\.crt}' | base64 -d | pem_body)
  # NOTE: 平文の鍵を一時ファイルに書き出さないための、パイプでの暗号化
  kubectl get secrets -n "${controller_namespace}" "${name}" -o yaml \
    | age --encrypt --recipients-file "${RECIPIENTS_FILE}" --output "${WORK_DIR}/key.yaml.age"
  rclone copyto --ignore-existing "${WORK_DIR}/key.yaml.age" "${bucket}/sealed-secrets-key-${uid}.yaml.age"
  echo "${name}: backed up"
  if [ "${cert}" = "${latest}" ]; then
    backed_up_latest=true
  fi
done 3< "${WORK_DIR}/keys.txt"

# NOTE: 退避していない鍵の証明書での封入を防ぐため、最新の鍵の退避後だけ証明書を送信
if [ "${backed_up_latest}" != true ]; then
  echo "the key of the latest certificate is not backed up" >&2
  exit 1
fi

# NOTE: GitHub AppのJWTによるinstallation access tokenの発行
now=$(date +%s)
header=$(printf '{"typ":"JWT","alg":"RS256"}' | base64url)
payload=$(jq -cn --arg iss "${GITHUB_APP_CLIENT_ID}" --argjson now "${now}" '{iat: ($now - 60), exp: ($now + 540), iss: $iss}' | base64url)
signature=$(printf '%s.%s' "${header}" "${payload}" | openssl dgst -sha256 -sign "${GITHUB_APP_PRIVATE_KEY_FILE}" -binary | base64url)

# NOTE: コマンドライン引数にトークンを置かないためにファイルで指定
printf 'Authorization: Bearer %s.%s.%s\n' "${header}" "${payload}" "${signature}" > "${WORK_DIR}/jwt-header"
installation_id=$(curl -fsS -H @"${WORK_DIR}/jwt-header" -H 'Accept: application/vnd.github+json' \
  "${github_api}/repos/${repository}/installation" | jq -er .id)

curl -fsS -X POST -H @"${WORK_DIR}/jwt-header" -H 'Accept: application/vnd.github+json' \
  --data "$(jq -cn --arg repository "${repository#*/}" '{repositories: [$repository], permissions: {contents: "write"}}')" \
  "${github_api}/app/installations/${installation_id}/access_tokens" \
  | jq -er '"Authorization: Bearer \(.token)"' > "${WORK_DIR}/token-header"

jq -n --arg event_type "${event_type}" --rawfile cert "${WORK_DIR}/cert.pem" '{event_type: $event_type, client_payload: {cert: $cert}}' \
  | curl -fsS -X POST -H @"${WORK_DIR}/token-header" -H 'Accept: application/vnd.github+json' --data @- \
    "${github_api}/repos/${repository}/dispatches"
echo "sent ${event_type} to ${repository}"
