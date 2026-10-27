#!/bin/sh
set -eu
# NOTE: ShellCheck 0.11.0は、POSIX.1-2024で標準化されたpipefailを未定義として警告
# shellcheck disable=SC3040
set -o pipefail

# NOTE: values.schema.jsonを含むchartについて、kubernetes/apps/<name>/values.yamlをスキーマで検証
#       helm templateは描画の前にvalues.schema.jsonで値を検証する

work_dir=$(mktemp -d)
trap 'rm -rf "$work_dir"' EXIT

for app in kubernetes/apps/*/app.yaml; do
  dir=$(dirname "$app")
  name=$(basename "$dir")
  if [ "$(yq '.chart // ""' "$app")" = "" ]; then
    continue
  fi

  helm pull "$(yq '.chart.name' "$app")" \
    --repo "$(yq '.chart.repoURL' "$app")" \
    --version "$(yq '.chart.version' "$app")" \
    --untar --untardir "$work_dir/$name"
  chart_dir="$work_dir/$name/$(yq '.chart.name' "$app")"
  if [ ! -f "$chart_dir/values.schema.json" ]; then
    continue
  fi

  echo "$dir: validating values with values.schema.json"
  if [ -f "$dir/values.yaml" ]; then
    helm template "$name" "$chart_dir" --namespace "$(yq '.namespace' "$app")" --values "$dir/values.yaml" >/dev/null
  else
    helm template "$name" "$chart_dir" --namespace "$(yq '.namespace' "$app")" >/dev/null
  fi
done
