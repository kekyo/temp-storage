# nginx + WebDAV テンポラリコンテナ

Light-weight temporary webdav storage server, designed for GitHub Actions artifacts.

---

For English version, see [README.md](./README.md).

## これは何?

`nginx + WebDAV + autoindex` を使った簡易ストレージ用コンテナ定義が含まれています。

想定用途は、GitHub Actions などから HTTP 経由で中間生成物を保存し、人間がブラウザでディレクトリ一覧を確認できるようにすることです。

## 構成概要

- ベースイメージ: `nginx:1.27-alpine`
- 認証: HTTP Basic 認証
- 書き込み: `PUT`
- 取得: `GET`
- 削除: `DELETE`
- ディレクトリ作成: `MKCOL`
- 一覧表示: Nginx 標準の `autoindex`
- コンテナ内保存先: `/var/lib/webdav`
- 待ち受けポート: `8080`

現在の設定では、次のような Nginx 設定になっています。

- `client_max_body_size 1g`
- `create_full_put_path on`
- `min_delete_depth 2`
- `autoindex on`
- `autoindex_format html`

`min_delete_depth 2` のため、浅すぎるパスは `DELETE` できません。

## 前提条件

- `podman` が使えること
- `curl` が使えること
- ホスト側に永続化先ディレクトリを作成できること

---

## セットアップ

### 1. イメージを build する

```bash
make build
```

明示的にイメージ名を指定する場合:

```bash
podman build -t temp-storage-nginx-webdav:local .
```

### 2. データ保存用ディレクトリを作成する

```bash
mkdir -p ./data
```

### 3. コンテナを起動する

```bash
podman run -d \
  --name temp-storage-nginx-webdav \
  -p 8080:8080 \
  -e WEBDAV_USERNAME=storage-user \
  -e WEBDAV_PASSWORD=storage-pass \
  -v "$(pwd)/data:/var/lib/webdav" \
  temp-storage-nginx-webdav:test
```

`WEBDAV_USERNAME` と `WEBDAV_PASSWORD` は必須です。未指定だとコンテナ起動時に失敗します。

ホスト側ディレクトリを SELinux 環境で bind mount する場合は、必要に応じて `:Z` を付けてください。

```bash
-v "$(pwd)/data:/var/lib/webdav:Z"
```

---

## 使用方法 (Actions runner/クライアント側)

以下では、次の値を使う前提で例を示します。

```bash
export WEBDAV_URL="http://127.0.0.1:8080"
export WEBDAV_USER="storage-user"
export WEBDAV_PASS="storage-pass"
```

### ディレクトリ一覧を表示する

ブラウザで次の URL を開くか、`curl` を使います。

```bash
curl -u "${WEBDAV_USER}:${WEBDAV_PASS}" "${WEBDAV_URL}/"
```

サブディレクトリ一覧を見る場合は、末尾に `/` を付けてください。

```bash
curl -u "${WEBDAV_USER}:${WEBDAV_PASS}" "${WEBDAV_URL}/runs/run-1/job-1/"
```

### ファイルをアップロードする

`PUT` で保存します。深いパスでも中間ディレクトリは自動作成されます。

```bash
curl -u "${WEBDAV_USER}:${WEBDAV_PASS}" \
  -T ./artifact.tgz \
  "${WEBDAV_URL}/runs/run-1/job-1/artifact.tgz"
```

### ファイルをダウンロードする

```bash
curl -u "${WEBDAV_USER}:${WEBDAV_PASS}" \
  -o ./artifact.tgz \
  "${WEBDAV_URL}/runs/run-1/job-1/artifact.tgz"
```

### ファイルを削除する

```bash
curl -u "${WEBDAV_USER}:${WEBDAV_PASS}" \
  -X DELETE \
  "${WEBDAV_URL}/runs/run-1/job-1/artifact.tgz"
```

### 空ディレクトリを作成する

必要なら `MKCOL` も使えます。

```bash
curl -u "${WEBDAV_USER}:${WEBDAV_PASS}" \
  -X MKCOL \
  "${WEBDAV_URL}/runs/run-2/"
```

## GitHub Actions からの利用例

```yaml
steps:
  - name: Upload artifact
    env:
      WEBDAV_URL: ${{ secrets.WEBDAV_URL }}
      WEBDAV_USER: ${{ secrets.WEBDAV_USER }}
      WEBDAV_PASS: ${{ secrets.WEBDAV_PASS }}
    run: |
      curl -fsS -u "${WEBDAV_USER}:${WEBDAV_PASS}" \
        -T artifact.tgz \
        "${WEBDAV_URL}/runs/${GITHUB_RUN_ID}/${GITHUB_JOB}/artifact.tgz"

  - name: Download artifact
    env:
      WEBDAV_URL: ${{ secrets.WEBDAV_URL }}
      WEBDAV_USER: ${{ secrets.WEBDAV_USER }}
      WEBDAV_PASS: ${{ secrets.WEBDAV_PASS }}
    run: |
      curl -fsS -u "${WEBDAV_USER}:${WEBDAV_PASS}" \
        -o artifact.tgz \
        "${WEBDAV_URL}/runs/${GITHUB_RUN_ID}/${GITHUB_JOB}/artifact.tgz"
```

## 運用上の注意

- 認証は Basic 認証なので、実運用では TLS 終端を必ず用意してください。
- 一覧表示は人間向けの簡易確認用です。機械処理の主系統は、決め打ちのパスを使う方が安定します。
- これはオブジェクトストレージではなく、HTTP 越しのファイル置き場です。TTL 管理や掃除は別途必要です。
- サイズ上限は現在 `1g` です。必要なら [nginx.conf](./nginx.conf) を変更してください。

---

## 動作確認

自動テストは次のコマンドで実行できます。

```bash
make test
```

このテストでは次を一通り確認します。

- イメージ build
- コンテナ起動
- 認証付き一覧表示
- `PUT`
- アップロード後の一覧確認
- `GET`
- `DELETE`
- 未認証アクセス時の `401`
- 削除後の `404`

---

## ライセンス

Under MIT.
