# isucon14構築

ローカル（macOS / Apple Silicon）で isucon14 を起動するまでに実行したコマンドの記録。

コマンド中のパスは、このドキュメントが置かれている `FStudent/` からの相対パスで記載している。

## 動作確認済み環境

| ツール | バージョン |
| --- | --- |
| macOS | 27.0 (Apple Silicon) |
| Docker Desktop | 4.52.0 / Engine 29.0.1 |
| Docker Compose | v2.40.3-desktop.1 |
| Task (go-task) | 3.53.1 |
| Go | 1.27.1 (darwin/arm64) |
| Node.js | v24.12.0 |
| pnpm | 11.24.0 (Homebrew) |

Apple Silicon では各ツールを **arm64 版で揃える**こと。macOS 27 で Rosetta による
x86_64 バイナリの変換が使えなくなったため、Intel 版が混ざっていると実行時に失敗する。

```bash
command -v go task pnpm docker   # すべて /opt/homebrew/bin 配下が望ましい
go version                       # darwin/arm64 であること
```

## セットアップで実行したコマンド

### 1. Docker CLI のパスを通す

Docker Desktop を起動する。

```bash
open -a Docker
```

`/usr/local/bin/docker` のシンボリックリンクがインストール時の DMG マウント先
（`/Volumes/Docker 3/...`）を指したまま切れていたため、`~/.zshrc` に実体のパスを追加した。

```bash
export PATH="/Applications/Docker.app/Contents/Resources/bin:$PATH"
```

```bash
source ~/.zshrc
docker compose version
```

### 2. Task のインストール

```bash
brew install go-task
```

### 3. pnpm のインストール

フロントエンドを動かす場合のみ必要。

```bash
brew install pnpm
```

Node.js に同梱の corepack 経由（`/usr/local/bin/pnpm`）は署名鍵が古くて失敗するため、
pnpm 本体を入れて使う。PATH の先頭が `/opt/homebrew/bin` なので Homebrew 版が優先される。

```bash
command -v pnpm   # /opt/homebrew/bin/pnpm になっていること
```

### 4. ミドルウェアの起動

```bash
cd ../isucon14
task up
```

`task up` は `development/compose-local.yml` を使って以下を起動する。

| コンテナ | 役割 | ポート |
| --- | --- | --- |
| `development-db-1` | MySQL 8（user: `isucon` / pass: `isucon` / db: `isuride`） | 3306 |
| `development-paymentmock-1` | 決済モックサーバー | 12345 |
| `development-matcher-1` | 0.5秒ごとに `/api/internal/matching` を叩き続ける | - |
| `development-waiter-1` | DB の起動待ち用（完了後 Exited(0) になるのが正常） | - |

`webapp/sql` が `docker-entrypoint-initdb.d` にマウントされているため、
初回起動時にスキーマと初期データが自動投入される。

状態確認。

```bash
docker compose -f development/compose-local.yml ps
```

### 5. バックエンドの起動

```bash
cd ../isucon14
task go:run
```

`webapp/go` で `go build -o isuride .` してから実行される。
`Listening on :8080` が出れば起動完了。

DB 接続先は環境変数が未設定なら `127.0.0.1:3306` / `isucon` / `isuride` にフォールバックするので、
`task up` の構成とそのまま噛み合う。

疎通確認。

```bash
curl -s -X POST http://localhost:8080/api/app/users \
  -H 'Content-Type: application/json' \
  -d '{"username":"probe","firstname":"a","lastname":"b","date_of_birth":"11111111"}'
```

なお `webapp/go` は API のみを提供するため、`http://localhost:8080/` は 404 になる。
画面を見る場合は次のフロントエンドを起動する。

### 6. フロントエンドの起動

バックエンドを起動したまま、別のターミナルで実行する。

```bash
cd ../isucon14/frontend
pnpm install --config.dangerouslyAllowAllBuilds=true
pnpm dev
```

pnpm 11 は依存パッケージのビルドスクリプトをデフォルトで拒否する。
`esbuild` と `@swc/core` が必要なため `--config.dangerouslyAllowAllBuilds=true` を付ける
（対話的に選ぶ場合は `pnpm approve-builds`）。

`http://localhost:3000/` で開く。`vite.config.ts` の `server.proxy` が `/api` を
`localhost:8080` に転送するので、フロント経由でそのまま API を叩ける。

| ルート | 内容 |
| --- | --- |
| `/` | ランディングページ |
| `/client` | 利用者向けモバイル画面（`/register`, `/login`, `/history`） |
| `/owner` | オーナー向け管理画面（`/sales`, `/register`, `/login`） |
| `/simulator` | 競技者用の動作シミュレーター |

`/client` と `/owner` は登録・ログインが必要なので、まず `/simulator` を見るのが手軽。

### 7. 停止

フロントエンドとバックエンドは `Ctrl+C` で停止する。コンテナは以下。

```bash
task down
```

## 踏んだトラブルと対処

### `zsh: command not found: docker`

Docker Desktop 本体は `/Applications/Docker.app` にあるが、`/usr/local/bin` の
シンボリックリンク（`docker`, `docker-compose`, `docker-credential-*`）が全て切れていた。
上記「1. Docker CLI のパスを通す」で解消。

`/usr/local/bin` 側を直したい場合は以下。

```bash
sudo ln -sf /Applications/Docker.app/Contents/Resources/bin/docker /usr/local/bin/docker
sudo ln -sf ~/.docker/cli-plugins/docker-compose /usr/local/bin/docker-compose
```

### `Bind for 127.0.0.1:3306 failed: port is already allocated`

`isucon13-main` の MySQL コンテナが `restart: always` で残っていて、
Docker Desktop の起動と同時に自動復帰し 3306 を占有していた。

```bash
docker stop mysql powerdns
docker update --restart=no mysql powerdns
```

`--restart=no` にしないと次回 Docker Desktop 起動時に再発する。
起動に失敗して中途半端に残ったコンテナを削除してからやり直す。

```bash
docker rm -f development-db-1 development-waiter-1 development-paymentmock-1 development-matcher-1
task up
```

### `docker compose -p isucon14 ... ps` が空を返す

コンテナは compose プロジェクト `development` に属しているため、
存在しない `isucon14` プロジェクトを見て 0 件になっていた。プロジェクト名の指定は不要。

```bash
docker compose -f development/compose-local.yml ps
```

### `Error: Cannot find matching keyid`（`pnpm dev` 実行時）

`/usr/local/bin/pnpm` が古い corepack（0.34.5）のシムだった。
`frontend/package.json` に `packageManager` フィールドが無いため corepack が
最新版の pnpm をレジストリに問い合わせに行き、バンドルされた署名鍵が古くて検証に失敗していた。

```
Error: Cannot find matching keyid: {"signatures":[...],"keys":[...]}
    at verifySignature (/usr/local/lib/node_modules/corepack/dist/lib/corepack.cjs:22688:11)
    at fetchLatestStableVersion (...)
```

corepack を経由せず pnpm 本体を入れて解決。上記「3. pnpm のインストール」を参照。

```bash
brew install pnpm
```

### `ERR_PNPM_IGNORED_BUILDS`

pnpm 11 はサプライチェーン対策として依存パッケージのビルドスクリプトを既定で実行しない。

```
[ERR_PNPM_IGNORED_BUILDS] Ignored build scripts: @swc/core@1.7.26, esbuild@0.17.6, esbuild@0.21.5
```

`esbuild` と `@swc/core` はネイティブバイナリの配置に postinstall が必要なので許可する。

```bash
pnpm install --config.dangerouslyAllowAllBuilds=true
```

### `bad CPU type in executable`（`task go:run` 実行時）

macOS 27 へのアップデートで Rosetta による x86_64 バイナリの変換が使えなくなり、
Intel 版 Homebrew（`/usr/local/Cellar`）に入っていた Go が動かなくなっていた。

```
task: Failed to run task "go:run": fork/exec .../webapp/go/isuride: bad CPU type in executable
```

シェル起動時に `~/.zshrc` 内の `go` 呼び出しも同時に失敗する。

```
/Users/.../.zshrc:22: bad CPU type in executable: go
```

状況確認。

```bash
uname -m                      # arm64
go version                    # darwin/amd64 だと NG
file webapp/go/isuride        # Mach-O 64-bit executable x86_64 だと NG
```

arm64 版の Go を入れ直す。PATH の先頭が `/opt/homebrew/bin` なので Homebrew 版が優先される。

```bash
brew install go
go version                    # go1.27.1 darwin/arm64
```

`task` は `sources` のチェックサムでビルド済み判定をするため、バイナリを消すだけでは
`Task "go:build" is up to date` となって再ビルドされない。`.task` キャッシュごと削除する。

```bash
cd ../isucon14
rm -rf .task webapp/go/isuride
task go:build
file webapp/go/isuride         # Mach-O 64-bit executable arm64 になること
```

あわせて `~/.zshrc` の以下の行を削除した。`/usr/local/go` は存在せず、
`$(go env GOPATH)` は Go が壊れている間シェル起動のたびにエラーを出していた。

```bash
export PATH=$PATH:/usr/local/go/bin      # 重複かつ存在しないパス
export PATH="$(go env GOPATH)/bin:$PATH" # $HOME/go/bin と重複
```

### 負荷走行の後半で大量の 500 が出る（`発生しているエラーが多すぎます`）

20秒走行では問題ないが、60秒走行にすると後半で 500 が急増して失格になる。

```
level=ERROR msg=クリティカルエラーが発生しました error=発生しているエラーが多すぎます
level=INFO msg=結果 pass=false スコア=3181 種別エラー数="map[1:100 2:3 3:21 7:14 ...]"
```

ベンチ側のログは `GET /api/chair/notification` の 500 が目立つが、
これは最も高頻度に叩かれるエンドポイントだからで、原因はそこではない。
アプリのログを採取すると一種類のエラーに集中している。

```
9502 件  dial tcp 127.0.0.1:3306: connect: can't assign requested address
```

`can't assign requested address` は新しい接続に割り当てる空きポートが無いという
OS レベルのエラー。**macOS のエフェメラルポート枯渇**であり、MySQL の
`max_connections`（151、実測ピーク 73）には達していない。

| 項目 | 値 |
| --- | --- |
| MySQL 向け `TIME_WAIT` ソケット | 848 |
| エフェメラルポート範囲 | 49152〜65535（16384個） |
| `net.inet.tcp.msl` | 15000ms |

`webapp/go` には接続プールの設定が無く、Go の既定ではアイドル接続を 2 本しか保持しない。
使い終わった接続が即座に閉じられて作り直されるため、`TIME_WAIT` が積み上がってポートを使い切る。
競技環境の Linux は既定のポート範囲が広く `TIME_WAIT` の扱いも異なるため、本番では起きない。

OS 側で吸収する場合（再起動で元に戻る一時設定）。

```bash
sudo sysctl -w net.inet.ip.portrange.first=16384   # 約4.9万個に拡大
sudo sysctl -w net.inet.tcp.msl=1000               # 解放待ちを15秒→1秒に短縮
```

元に戻す場合。

```bash
sudo sysctl -w net.inet.ip.portrange.first=49152 net.inet.tcp.msl=15000
```

なお、接続プールの設定自体は ISUCON14 で最初に手を入れる定番の改善点でもある。
チューニングを始めるなら `webapp/go/main.go` に以下を加えるのが正攻法。

```go
db.SetMaxIdleConns(128)
db.SetMaxOpenConns(128)
db.SetConnMaxLifetime(0)
```

### アプリのログを採取する

`task go:run` の出力は画面に流れるだけなので、原因調査のときはファイルにも残す。

```bash
cd ../isucon14/webapp/go
./isuride 2>&1 | tee /tmp/isuride.log
```

ステータスの内訳とエラー内容の集計。

```bash
grep -oE "\- [0-9]{3} " /tmp/isuride.log | sort | uniq -c | sort -rn
grep -i ERROR /tmp/isuride.log | sed -E 's/^[0-9/]+ [0-9:]+ //' | sort | uniq -c | sort -rn | head
```

### `Cannot connect to the Docker daemon`

マシン再起動後は Docker Desktop が自動起動しないことがある。

```bash
open -a Docker
docker info      # 応答するまで数秒待つ
task up
```

## 既知の注意点

`isucon13-main` と `isucon14` はどちらも compose ファイルが `development/` にあるため、
Compose のプロジェクト名が両方 `development` になり 1 つのプロジェクトとして合体している。

```bash
docker compose ls -a
# development   exited(5), running(3)   .../isucon14/development/compose-local.yml,
#                                       .../isucon13-main/development/docker-compose-common.yml,
#                                       .../isucon13-main/development/docker-compose-node.yml
```

`Taskfile.yml` の `down` タスクは `-v --remove-orphans` 付きなので、
実行すると isucon13 のコンテナと `development_mysql_volume` /
`development_powerdns_volume` まで削除される可能性がある。

isucon13 のデータを残したい場合は `development/compose-local.yml` の先頭に
プロジェクト名を明示して分離する。

```yaml
name: isucon14

services:
  db:
    image: mysql:8
```

`pnpm dev` の起動時に以下が出るが、開発サーバーやアプリの動作には影響しない。

```
logined client page: http://localhost:3000/client?access_token=undefined&id=01M1H5XGZ...
LOGIN ERROR: SyntaxError: Unexpected non-whitespace character after JSON at position 4
```

`vite.config.ts` の開発用プラグインが自動ログイン URL を生成しようとして失敗している。
`access_token` が `undefined` なのは `POST /api/app/users` がトークンを Cookie で返す仕様のため。
`LOGIN ERROR` の方は本家のコードが `/api/owner/ownsers`（`owners` の綴り間違い）と
`/chair/register`（`/api` が抜けている）を叩いているため。画面からの手動登録・ログインは正常に行える。

## 8. 負荷走行（ベンチマーク）

`isucon14/bench` の `task run-local` をそのまま実行すると 2 箇所で失敗する。
`static-proxy/run-bench.sh` でどちらも回避している。

```bash
cd ../FStudent/static-proxy
DURATION=60 ./run-bench.sh
```

`task up` と `task go:run` でミドルウェアとアプリが起動済みであることが前提。
環境変数で調整できる。

| 変数 | 既定値 | 内容 |
| --- | --- | --- |
| `DURATION` | 60 | 負荷走行の秒数 |
| `PROXY_PORT` | 8081 | 静的ファイル配信用 nginx の待ち受けポート |
| `PAYMENT_PORT` | 12346 | ベンチマーカーが決済サーバーとして使うポート |

実測値（Apple Silicon, 20秒走行）: スコア 2431 / `pass=true` / エラー 0。

### なぜ素の `task run-local` が失敗するか

#### 失敗1: 静的ファイルのチェック

```
level=ERROR msg=静的ファイルのチェックに失敗しました error="GET /clientへのリクエストに対して、
期待されたHTTPステータスコードが確認できませんでした (expected:200～399, actual:404)"
```

ベンチは本番構成、すなわち nginx がフロントエンドのビルド成果物を `/` で配信し
`/api/` だけをアプリにプロキシする構成を前提にしている。
`compose-local.yml` + `task go:run` には nginx が無く、Go アプリは `/api/*` しか持たないため
`/client` が 404 になる。

チェック内容は単なる疎通ではなく、`bench/benchrun/frontend_hashes.json` に載っている
59 ファイル全ての md5 比較。この期待値は `//go:embed` でベンチに焼き込まれている。
したがってフロントエンドをビルドして配信する必要がある。

失敗すると `Prepare` が `return err` で打ち切られるため、負荷は一切かからずに終了する。

#### 失敗2: 決済サーバーのポート衝突

静的チェックを `-s` でスキップすると、今度はこうなる。

```
level=ERROR msg=クリティカルエラーが発生しました
  error="評価は完了しているが、支払いが行われていないライドが存在します (CODE=34)"
```

ベンチマーカーは走行中に自分が決済サーバーとして振る舞い、既定で 12345 を使う。
ところがそこは `development-paymentmock-1` が押さえているため、アプリの決済リクエストが
モックに吸われてベンチ側に記録が残らない。`--payment-bind-port` と `--payment-url` をずらして回避する。

### isucon14 配下を変更しない工夫

フロントエンドをビルドすると、`vite.config.ts` の `generateHashesFile` プラグインが
`bench/benchrun/frontend_files.json` と `frontend_hashes.json` を上書きする。
公式ビルドとアセットハッシュが異なるため、実際に差分が出る。

走行中はこの再生成された期待値が必要（`go run` が再コンパイル時に埋め込む）なので、
`run-bench.sh` は `trap` で終了時に `git checkout` して元の内容へ戻す。
異常終了しても復元される。

```bash
GENERATED=(
  "isucon14/bench/benchrun/frontend_files.json"
  "isucon14/bench/benchrun/frontend_hashes.json"
)
cleanup() {
  docker compose -f "$PROXY_DIR/compose.yml" down --remove-orphans >/dev/null 2>&1 || true
  git -C "$REPO_ROOT" checkout -- "${GENERATED[@]}" >/dev/null 2>&1 || true
}
trap cleanup EXIT
```

nginx の設定と compose ファイルは `FStudent/static-proxy/` に置き、
`isucon14/development/` には手を入れていない。compose のプロジェクト名も
`isucon14-static-proxy` として `development` から分離している。

### nginx 設定のポイント

本家の `development/nginx/conf.d/nginx.conf` をそのまま流用すると、
`proxy_pass` が毎リクエストで接続を張り直すためタイムアウトが多発してスコアが 65 まで落ちた。

```
level=WARN msg="椅子の座標送信に失敗しました (CODE=1): ... context deadline exceeded"
level=INFO msg=結果 pass=true スコア=65 種別エラー数="map[1:12 25:3]"
```

本番では nginx とアプリが同一ホストにいるが、ここでは nginx がコンテナ、アプリがホストで
`host.docker.internal` 越しになるため接続コストが高い。upstream への keepalive を有効にし、
通知系のストリーミングのためにバッファリングを切ることで 2431 まで回復した。

```nginx
upstream app {
  server host.docker.internal:8080;
  keepalive 256;
  keepalive_requests 100000;
}

location /api/ {
  proxy_http_version 1.1;
  proxy_set_header Connection "";   # keepalive を効かせる
  proxy_buffering off;              # 通知系のストリーミングを素通し
  proxy_pass http://app;
}
```

### 静的チェックをスキップする場合

チューニングの反復中など、フロントエンドのビルドを省きたい場合は従来どおり直接実行する。
`Taskfile.yml` が `{{.CLI_ARGS}}` を渡しているので `task run-local` 経由でも引数を足せる。

```bash
cd ../isucon14/bench
task run-local -- -s --payment-bind-port 12346 --payment-url http://localhost:12346
```

## リンク

- [ISUCON14 問題（本家リポジトリ）](https://github.com/isucon/isucon14)
- [isucon14/README.md](../isucon14/README.md)
