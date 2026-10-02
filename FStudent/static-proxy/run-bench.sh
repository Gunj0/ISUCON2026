#!/usr/bin/env bash
#
# 静的ファイルチェックを含めた負荷走行を行う。
#
# フロントエンドのビルドは isucon14/bench/benchrun/frontend_*.json を
# 書き換えるため、終了時に git で元の内容へ復元する。
#
# 前提: task up と task go:run でミドルウェアとアプリが起動済みであること。
#
set -euo pipefail

cd "$(dirname "$0")"
PROXY_DIR="$PWD"
REPO_ROOT="$(cd ../.. && pwd)"
ISUCON14="$REPO_ROOT/isucon14"

DURATION="${DURATION:-60}"
PROXY_PORT="${PROXY_PORT:-8081}"
PAYMENT_PORT="${PAYMENT_PORT:-12346}"

# ビルドで再生成される追跡ファイル
GENERATED=(
  "isucon14/bench/benchrun/frontend_files.json"
  "isucon14/bench/benchrun/frontend_hashes.json"
)

cleanup() {
  docker compose -f "$PROXY_DIR/compose.yml" down --remove-orphans >/dev/null 2>&1 || true
  git -C "$REPO_ROOT" checkout -- "${GENERATED[@]}" >/dev/null 2>&1 || true
  echo "==> nginx を停止し、再生成されたファイルを復元しました"
}
trap cleanup EXIT

# HTTP ステータスは問わない。応答があれば起動していると判断する。
if [ "$(curl -s -o /dev/null -w '%{http_code}' --max-time 5 http://localhost:8080/api/app/rides)" = "000" ]; then
  echo "エラー: localhost:8080 でアプリが起動していません。task go:run を先に実行してください。" >&2
  exit 1
fi

echo "==> フロントエンドをビルド"
(cd "$ISUCON14/frontend" && pnpm run build >/dev/null)

echo "==> 静的ファイル配信用の nginx を起動 (:$PROXY_PORT)"
PROXY_PORT="$PROXY_PORT" docker compose -f "$PROXY_DIR/compose.yml" up -d

for i in $(seq 1 30); do
  if curl -fsS -o /dev/null "http://localhost:$PROXY_PORT/client"; then
    break
  fi
  if [ "$i" -eq 30 ]; then
    echo "エラー: nginx が応答しません。" >&2
    exit 1
  fi
  sleep 1
done

echo "==> 負荷走行を開始 (target=:$PROXY_PORT, payment=:$PAYMENT_PORT, ${DURATION}秒)"
(cd "$ISUCON14/bench" && go run . run \
  --target "http://localhost:$PROXY_PORT" \
  -t "$DURATION" \
  --payment-bind-port "$PAYMENT_PORT" \
  --payment-url "http://localhost:$PAYMENT_PORT" \
  "$@")
