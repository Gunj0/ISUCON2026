#!/usr/bin/env bash
#
# MySQL のスロークエリログを操作する。
#
# 設定は SET GLOBAL だけで行うため、isucon14 配下の設定ファイルは変更しない。
# その代わりコンテナを作り直すと既定値(記録オフ)に戻る。
#
# 使い方:
#   ./mysql-slowlog.sh on      全クエリを記録する状態にし、ログを空にする
#   ./mysql-slowlog.sh off     記録を止める
#   ./mysql-slowlog.sh report  ログを取り出して pt-query-digest で集計する
#   ./mysql-slowlog.sh status  現在の設定を表示する
#
set -euo pipefail

cd "$(dirname "$0")"
LOG_DIR="$PWD/logs"
mkdir -p "$LOG_DIR"

DB_CONTAINER="${DB_CONTAINER:-development-db-1}"
SLOW_LOG_IN_CONTAINER="/tmp/slow.log"
LIMIT="${LIMIT:-15}"

# MYSQL_PWD で渡すとパスワードの警告が出ない
mysql_exec() {
  docker exec -e MYSQL_PWD=isucon "$DB_CONTAINER" mysql -uroot -N -e "$1"
}

case "${1:-}" in
  on)
    mysql_exec "SET GLOBAL slow_query_log = OFF"
    docker exec -u root "$DB_CONTAINER" rm -f "$SLOW_LOG_IN_CONTAINER"
    mysql_exec "SET GLOBAL slow_query_log_file = '$SLOW_LOG_IN_CONTAINER';
                SET GLOBAL long_query_time = 0;
                SET GLOBAL log_queries_not_using_indexes = OFF;
                SET GLOBAL slow_query_log = ON"
    echo "==> 全クエリの記録を開始しました (long_query_time=0)"
    echo "    注意: 記録のぶんだけ遅くなるため、この状態のスコアは比較に使えません。"
    ;;

  off)
    mysql_exec "SET GLOBAL slow_query_log = OFF; SET GLOBAL long_query_time = 10"
    echo "==> 記録を停止しました"
    ;;

  report)
    if ! docker exec "$DB_CONTAINER" test -f "$SLOW_LOG_IN_CONTAINER"; then
      echo "エラー: ログがありません。先に ./mysql-slowlog.sh on を実行してください。" >&2
      exit 1
    fi
    docker exec "$DB_CONTAINER" cat "$SLOW_LOG_IN_CONTAINER" > "$LOG_DIR/slow.log"
    pt-query-digest --limit "$LIMIT" "$LOG_DIR/slow.log" > "$LOG_DIR/slow-digest.txt"
    echo "==> $LOG_DIR/slow-digest.txt に保存しました"
    echo
    # Profile 節(クエリごとの集計表)だけを抜き出して表示する
    sed -n '/^# Profile/,/^# Query 1/p' "$LOG_DIR/slow-digest.txt" | sed '$d'
    ;;

  status)
    mysql_exec "SELECT CONCAT('slow_query_log      = ', @@GLOBAL.slow_query_log);
                SELECT CONCAT('long_query_time     = ', @@GLOBAL.long_query_time);
                SELECT CONCAT('slow_query_log_file = ', @@GLOBAL.slow_query_log_file)"
    ;;

  *)
    sed -n '3,13p' "$0" | sed 's/^# \{0,1\}//'
    exit 1
    ;;
esac
