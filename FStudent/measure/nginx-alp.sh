#!/usr/bin/env bash
#
# nginx のアクセスログを alp で集計する。
#
# ログは static-proxy/nginx.conf の access_log で JSON 形式で出力され、
# compose.yml のボリューム経由で measure/logs/ に書き出される。
#
# 使い方:
#   ./nginx-alp.sh reset   ログを空にする(走行前に実行する)
#   ./nginx-alp.sh report  集計結果を表示する
#
set -euo pipefail

cd "$(dirname "$0")"
LOG_DIR="$PWD/logs"
mkdir -p "$LOG_DIR"
ACCESS_LOG="$LOG_DIR/access_json.log"

# ULID を含むパスとフロントエンドの静的ファイルをまとめて数える
MATCHING_GROUPS='/api/app/rides/[^/]+/evaluation,/api/chair/rides/[^/]+/status,/assets/.+'

case "${1:-}" in
  reset)
    : > "$ACCESS_LOG"
    echo "==> $ACCESS_LOG を空にしました"
    ;;

  report)
    if [ ! -s "$ACCESS_LOG" ]; then
      echo "エラー: $ACCESS_LOG が空です。nginx 経由で負荷走行してから実行してください。" >&2
      exit 1
    fi
    # SUM(合計処理時間)の降順。合計が大きいものほど改善の余地が大きい。
    alp json --file "$ACCESS_LOG" \
      --sort sum -r \
      --matching-groups "$MATCHING_GROUPS" \
      --nosave-pos \
      -o count,method,uri,min,avg,max,sum,p99,2xx,3xx,4xx,5xx \
      | tee "$LOG_DIR/alp.txt"
    echo
    echo "==> $LOG_DIR/alp.txt に保存しました"
    ;;

  *)
    sed -n '3,11p' "$0" | sed 's/^# \{0,1\}//'
    exit 1
    ;;
esac
