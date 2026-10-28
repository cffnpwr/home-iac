#!/bin/sh
set -eu
# NOTE: ShellCheck 0.11.0は、POSIX.1-2024で標準化されたpipefailを未定義として警告
# shellcheck disable=SC3040
set -o pipefail

# NOTE: Talosは作成済みのリソースを再適用しないため、talosのエントリは残り続ける
#       talosが共同で所有するフィールドは、Gitから削除してもserver-side applyで削除されない
talos_manager=talos
argocd_manager=argocd-controller
max_attempts=3

# NOTE: Argo CDがserver-side applyで所有するリソースだけを対象とし、Talos自身が管理するリソースは変更しない
#       untilの条件で呼ぶとset -eが無効になるため、失敗を明示的に返す
strip_talos_entry() {
  obj=$(kubectl get "$@" -o json --show-managed-fields --ignore-not-found) || return 1
  if [ -z "${obj}" ]; then
    return 0
  fi

  target=$(printf '%s' "${obj}" | jq -r --arg talos "${talos_manager}" --arg argocd "${argocd_manager}" '
    any(.metadata.managedFields[]?; .manager == $talos)
    and any(.metadata.managedFields[]?; .manager == $argocd and .operation == "Apply")') || return 1
  if [ "${target}" != true ]; then
    return 0
  fi

  # NOTE: 取得後に別の書き込みがあった場合は、resourceVersionのtestで失敗
  patch=$(printf '%s' "${obj}" | jq -c --arg talos "${talos_manager}" '[
    {op: "test", path: "/metadata/resourceVersion", value: .metadata.resourceVersion},
    {op: "replace", path: "/metadata/managedFields", value: [.metadata.managedFields[] | select(.manager != $talos)]}
  ]') || return 1
  kubectl patch "$@" --type=json -p "${patch}"
}

resources=$(kubectl get applications.argoproj.io -n argocd -o json \
  | jq -r '.items[].status.resources[]? | [(.group // ""), .kind, (.namespace // ""), .name] | join("|")')

while IFS='|' read -r group kind namespace name; do
  # NOTE: 空のリソース名でkubectl getを実行しないよう、その行を読み飛ばす
  if [ -z "${name}" ]; then
    continue
  fi

  set -- "${kind}${group:+.${group}}" "${name}"
  if [ -n "${namespace}" ]; then
    set -- "$@" --namespace "${namespace}"
  fi

  attempt=1
  until strip_talos_entry "$@"; do
    if [ "${attempt}" -ge "${max_attempts}" ]; then
      echo "failed to strip ${talos_manager} entry from $*" >&2
      exit 1
    fi
    attempt=$((attempt + 1))
    sleep 1
  done
done <<EOF
${resources}
EOF
