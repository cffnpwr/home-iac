#!/bin/bash
set -euo pipefail

management_url=https://nb.cffnpwr.dev:443

# NOTE: setup keyが空だと、`netbird up`はSSOのログインを待ち続けてjobのtimeoutまで終わらないためエラーにする
if [[ -z $SETUP_KEY ]]; then
  echo "::error::The setup key is empty."
  exit 1
fi

netbird=$(mise which netbird)
sudo "$netbird" service install
sudo "$netbird" service start
# NOTE: postがピアを削除するためのnetbirdのパス
echo "netbird=$netbird" >> "$GITHUB_STATE"

# NOTE: コマンドラインの引数に平文を含めないため、setup keyをファイルで渡す
key_file=$RUNNER_TEMP/netbird-setup-key
trap 'rm -f "$key_file"' EXIT
(umask 077 && printf '%s' "$SETUP_KEY" > "$key_file")
sudo "$netbird" up \
  --setup-key-file "$key_file" \
  --management-url "$management_url" \
  --hostname "gha-$GITHUB_RUN_ID-$GITHUB_RUN_ATTEMPT-$GITHUB_JOB"

# NOTE: `netbird up`はルーティングピアへの接続を待たずに終了するため、宛先に接続できるまで待つ
host=${WAIT_ADDRESS%:*}
port=${WAIT_ADDRESS##*:}
for _ in $(seq 60); do
  if nc -z -w 3 "$host" "$port"; then
    exit 0
  fi
  sleep 2
done
echo "::error::Could not reach $WAIT_ADDRESS through NetBird."
sudo "$netbird" status --detail
exit 1
