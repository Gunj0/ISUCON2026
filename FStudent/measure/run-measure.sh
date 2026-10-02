#!/usr/bin/env bash
#
# 計測付きの負荷走行を行い、MySQL と nginx のレポートを出す。
#
# スロークエリの全件記録でアプリが遅くなるため、ここで出るスコアは
# 改善の前後比較には使えない。スコアを測るときは記録なしの
# static-proxy/run-bench.sh を使うこと。
#
# 前提: task up と task go:run でミドルウェアとアプリが起動済みであること。
#
set -euo pipefail

cd "$(dirname "$0")"
MEASURE_DIR="$PWD"

report() {
  echo
  echo "============================================================"
  echo " MySQL: 合計実行時間の多いクエリ"
  echo "============================================================"
  "$MEASURE_DIR/mysql-slowlog.sh" off
  "$MEASURE_DIR/mysql-slowlog.sh" report || true

  echo
  echo "============================================================"
  echo " nginx: 合計応答時間の長いエンドポイント"
  echo "============================================================"
  "$MEASURE_DIR/nginx-alp.sh" report || true
}
# 走行が途中で失敗してもレポートは出す
trap report EXIT

"$MEASURE_DIR/mysql-slowlog.sh" on
"$MEASURE_DIR/nginx-alp.sh" reset

"$MEASURE_DIR/../static-proxy/run-bench.sh" "$@"
