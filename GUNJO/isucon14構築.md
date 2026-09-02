# isucon14構築

## 環境構築手順

## 手順

1. リポジトリをクローン

```bash
git clone https://github.com/isucon/isucon14
cd isucon14
```

2. 必要なツールをインストール

- Docker Desktop: `brew install --cask docker`
- Go: `brew install go`
- Node.js 20+: `brew install node`
- pnpm: `brew install pnpm`
- Task: `brew install go-task`

3. フロントビルド

```bash
cd frontend
pnpm install
pnpm approve-builds
pnpm build
cd ..
```

4. DBと決済モックを起動する

- Docker Desktopを起動して以下を実行する

```bash
task up
```

5. アプリケーションを起動する

```bash
task go:run
```

6. ブラウザでアプリケーションを確認する

```bash
cd frontend
pnpm dev
```

- ブラウザで `http://localhost:3000` にアクセスする
