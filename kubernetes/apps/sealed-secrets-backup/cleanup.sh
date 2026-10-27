#!/bin/sh
set -eu
# NOTE: ShellCheck 0.11.0は、POSIX.1-2024で標準化されたpipefailを未定義として警告
# shellcheck disable=SC3040
set -o pipefail

controller_name=sealed-secrets-controller
controller_namespace=sealed-secrets
# NOTE: chartのDeploymentが付けるラベルで、instanceの値はArgo CDのApplication名
controller_pod_selector=app.kubernetes.io/name=sealed-secrets,app.kubernetes.io/instance=sealed-secrets
bucket=r2:home-iac-sealed-secrets-keys
decrypt_error='no key could decrypt secret'

# NOTE: PEMの改行の差を無視して比べるための、ヘッダー行・フッター行を除いたbase64の抽出
pem_body() {
  grep -v -e '-----' | tr -d '\r\n'
}

echo "triggered by ${TRIGGER_NAME}"

kubeseal --fetch-cert --controller-name "${controller_name}" --controller-namespace "${controller_namespace}" > "${WORK_DIR}/cert.pem"
latest=$(pem_body < "${WORK_DIR}/cert.pem")

kubectl get secrets -n "${controller_namespace}" -l sealedsecrets.bitnami.com/sealed-secrets-key=active \
  -o jsonpath='{range .items[*]}{.metadata.uid}{" "}{.metadata.name}{"\n"}{end}' > "${WORK_DIR}/keys.txt"

latest_uid=
latest_name=
while read -r uid name <&3; do
  cert=$(kubectl get secrets -n "${controller_namespace}" "${name}" -o jsonpath='{.data.tls\.crt}' | base64 -d | pem_body)
  if [ "${cert}" = "${latest}" ]; then
    latest_uid=${uid}
    latest_name=${name}
  fi
done 3< "${WORK_DIR}/keys.txt"

if [ -z "${latest_name}" ]; then
  echo "the key of the latest certificate not found" >&2
  exit 1
fi
echo "${latest_name}: latest"
kubectl get secrets -n "${controller_namespace}" "${latest_name}" -o yaml > "${WORK_DIR}/latest.yaml"

kubectl get sealedsecrets.bitnami.com --all-namespaces \
  -o jsonpath='{range .items[*]}{.metadata.namespace}{" "}{.metadata.name}{"\n"}{end}' > "${WORK_DIR}/sealedsecrets.txt"
# NOTE: SealedSecretの同期前に、R2から復元した鍵を削除しないために終了
if [ ! -s "${WORK_DIR}/sealedsecrets.txt" ]; then
  echo "SealedSecret not found"
  exit 0
fi

# NOTE: 暗号文が封入に使った鍵の情報を含まないため、最新の鍵だけでの復号の可否で封入の鍵を判定
while read -r namespace name <&3; do
  kubectl get sealedsecrets.bitnami.com -n "${namespace}" "${name}" -o yaml > "${WORK_DIR}/sealedsecret.yaml"

  # NOTE: 復号した平文をログに残さないため/dev/nullへ破棄
  if kubeseal --recovery-unseal --recovery-private-key "${WORK_DIR}/latest.yaml" < "${WORK_DIR}/sealedsecret.yaml" > /dev/null 2> "${WORK_DIR}/unseal.err"; then
    continue
  fi
  cat "${WORK_DIR}/unseal.err" >&2

  # NOTE: 鍵の誤削除を防ぐため、kubesealのエラーの全行が復号不能のときだけ封入し直す前と判断
  if grep -q -e "${decrypt_error}" "${WORK_DIR}/unseal.err" \
    && ! grep -v -q -e "${decrypt_error}" "${WORK_DIR}/unseal.err"; then
    echo "${namespace}/${name}: not sealed with the latest key"
    exit 0
  fi
  echo "${namespace}/${name}: failed to unseal" >&2
  exit 1
done 3< "${WORK_DIR}/sealedsecrets.txt"

# NOTE: ほかの鍵のファイルをR2から削除する前の、最新の鍵のファイルの存在確認
if [ -z "$(rclone lsf --files-only --include "sealed-secrets-key-${latest_uid}.yaml.age" "${bucket}")" ]; then
  echo "the backup of ${latest_name} not found" >&2
  exit 1
fi

grep -v -x -F -e "${latest_uid} ${latest_name}" "${WORK_DIR}/keys.txt" | cut -d ' ' -f 2 > "${WORK_DIR}/unused.txt" || true
if [ -s "${WORK_DIR}/unused.txt" ]; then
  # NOTE: 同時に実行される別のJobが先に削除した場合の失敗の防止
  xargs kubectl delete secrets -n "${controller_namespace}" --ignore-not-found < "${WORK_DIR}/unused.txt"

  # NOTE: 削除した鍵を反映させるためにcontrollerを再起動
  kubectl delete pods -n "${controller_namespace}" -l "${controller_pod_selector}"
fi

# NOTE: 途中で失敗しても再実行で削除できるようにクラスタの鍵の削除後に実行
rclone delete "${bucket}" \
  --filter "- sealed-secrets-key-${latest_uid}.yaml.age" \
  --filter '+ sealed-secrets-key-*.yaml.age' \
  --filter '- *'
