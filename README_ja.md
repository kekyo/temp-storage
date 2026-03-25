# nginx + WebDAV テンポラリコンテナ

GitHub Actions の artifact 置き場として使うことを想定した、軽量な WebDAV テンポラリストレージサーバーです。

[![Docker Image Version](https://img.shields.io/docker/v/kekyo/nginx-webdav-temporary.svg?label=docker)](https://hub.docker.com/r/kekyo/nginx-webdav-temporary)

---

英語版は [README.md](./README.md) を参照してください。

## これは何?

`nginx + WebDAV + autoindex` を使った簡易ストレージ用コンテナ定義です。

主な用途は、GitHub Actions などから HTTP 経由で中間生成物を保存しつつ、人間がブラウザでディレクトリ一覧を確認できるようにすることです。

## 構成概要

- ベースイメージ: `nginx:1.27-alpine`
- 認証: HTTP Basic 認証
- 書き込み: `PUT`
- 取得: `GET`
- 削除: `DELETE`
- ディレクトリ作成: `MKCOL`
- 一覧表示: Nginx 標準の `autoindex`
- コンテナ内保存先: `/var/lib/webdav` (起動時変更可能)
- 待ち受けポート: `8080` (起動時変更可能)

---

## 起動方法

`docker` またはコンテナ互換環境が必要です。
公開イメージ名は `docker.io/kekyo/nginx-webdav-temporary` です [(docker.ioページ)](https://hub.docker.com/r/kekyo/nginx-webdav-temporary)。

最新版を pull する例:

```bash
docker pull docker.io/kekyo/nginx-webdav-temporary:latest
```

Docker で起動する例:

```bash
docker run -d \
  --name nginx-webdav-temporary \
  -p 8080:8080 \
  -e WEBDAV_USERNAME=storage-user \
  -e WEBDAV_PASSWORD=storage-pass \
  -v "$(pwd)/data:/var/lib/webdav" \
  docker.io/kekyo/nginx-webdav-temporary:latest
```

起動時に `/var/lib/webdav` 配下の既存ファイルをすべて削除したい場合は、`WEBDAV_CLEAR_STORAGE_ON_STARTUP=true` を指定してください。

```bash
docker run -d \
  --name nginx-webdav-temporary \
  -p 8080:8080 \
  -e WEBDAV_USERNAME=storage-user \
  -e WEBDAV_PASSWORD=storage-pass \
  -e WEBDAV_CLEAR_STORAGE_ON_STARTUP=true \
  -v "$(pwd)/data:/var/lib/webdav" \
  docker.io/kekyo/nginx-webdav-temporary:latest
```

このオプションを有効にすると、コンテナ起動時にストレージルート自体は残したまま、その配下のファイルとディレクトリを削除します。

---

## 使用方法

以下の例では、次の環境変数を使う前提にしています。

```bash
export WEBDAV_URL="http://127.0.0.1:8080"
export WEBDAV_USER="storage-user"
export WEBDAV_PASS="storage-pass"
```

### ディレクトリ一覧を表示する

ブラウザで開くか、`curl` を使います。

```bash
curl -u "${WEBDAV_USER}:${WEBDAV_PASS}" "${WEBDAV_URL}/"
```

サブディレクトリを見る場合は末尾に `/` を付けてください。

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

## 権限に関する注意

このイメージは、現在の rootless Podman 環境でも通常の Docker 利用でも bind mount を扱いやすくするため、少し強めの権限設定を使っています。

- Nginx worker はコンテナ内で `root` として動作します。
- そのため Docker で bind mount を使うと、ホスト側では作成ファイルが `root:root` に見えることがあります。
- rootless Podman では、環境によって subuid/subgid のマッピング後の所有者で見える場合があります。
- ホスト側の ownership が重要なら、bind mount ではなく named volume を使うか、事前に運用ポリシーに合う権限を付けたディレクトリを用意してください。

また、起動時スクリプトで `/var/lib/webdav` と `/var/lib/nginx/body` に対して `chmod -R a+rwX` を適用するため、マウントした保存先が書き込み可能な状態になります。

## 運用上の注意

- 認証は Basic 認証なので、本番利用では前段で TLS 終端を必ず用意してください。
- 一覧表示は人間向けの簡易確認用です。機械処理の主系統は、決め打ちパスを使う方が安定します。
- これはオブジェクトストレージではなく HTTP 越しのファイル置き場です。掃除や retention は別途管理が必要です。
- 現在のサイズ上限は `1g` です。必要なら [nginx.conf](./nginx.conf) を変更してください。

現在の Nginx 設定には次が含まれます。

- `client_max_body_size 1g`
- `create_full_put_path on`
- `min_delete_depth 2`
- `autoindex on`
- `autoindex_format html`

`min_delete_depth` が `2` なので、浅すぎるパスは `DELETE` できません。

---

## systemdとの統合

以下のファイルを配置することで、systemdで制御できます。

`/etc/systemd/system/container-nginx-webdav-temporary.service`:

```ini
[Unit]
Description=Podman container-nginx-webdav-temporary.service
Documentation=man:podman-generate-systemd(1)
Wants=network-online.target
After=network-online.target
RequiresMountsFor=%t/containers

[Service]
Environment=PODMAN_SYSTEMD_UNIT=%n
Restart=on-failure
TimeoutStopSec=70
ExecStartPre=/bin/rm -f %t/%n.ctr-id
ExecStart=/usr/bin/podman run --cidfile=%t/%n.ctr-id --cgroups=no-conmon --rm --sdnotify=conmon --replace -p 8080:8080 -e WEBDAV_USERNAME=*************** -e WEBDAV_PASSWORD=*************** -e WEBDAV_CLEAR_STORAGE_ON_STARTUP=true -v /storage0/temp_artifacts:/var/lib/webdav -d --name nginx-webdav-temporary nginx-webdav-temporary:test
ExecStop=/usr/bin/podman stop --ignore --cidfile=%t/%n.ctr-id
ExecStopPost=/usr/bin/podman rm -f --ignore --cidfile=%t/%n.ctr-id
Type=notify
NotifyAccess=all

[Install]
WantedBy=default.target
```

更に、 `/etc/systemd/system/container-nginx-webdav-temporary.timer` を配置して、毎日再起動させることができます:

```ini
[Unit]
Description=Reset container

[Timer]
OnCalendar=03:00
Persistent=false

[Install]
WantedBy=timers.target
```

`WEBDAV_CLEAR_STORAGE_ON_STARTUP=true` を指定しているので、再起動毎にストレージは削除され、クリーンアップされます
（もちろん、このオプションを外して永続化もできます）。

サービスとして有効化します:

```bash
sudo systemctl daemon-reload
sudo systemctl enable container-nginx-webdav-temporary
sudo systemctl start container-nginx-webdav-temporary
```

---

## ソースから build する

ビルド環境:

- `podman`
- `curl`
- [`screw-up-native`](https://github.com/kekyo/screw-up-native)

Podman でローカル build する例:

```bash
make build
```

デフォルトのローカルイメージ名は次です。

```text
localhost/nginx-webdav-temporary:test
```

`screw-up format` から計算される version を表示する例:

```bash
make print-version
```

`linux/amd64` と `linux/arm64` の multi-arch manifest をローカル build する例:

```bash
make build-multiarch
```

Docker Hub へ multi-arch イメージを push する例:

```bash
podman login docker.io
make push-multiarch
```

デフォルトでは、`make push-multiarch` は次のタグへ push します。

- `docker.io/kekyo/nginx-webdav-temporary:{version}`
- `docker.io/kekyo/nginx-webdav-temporary:latest`

ここで `{version}` は `printf '{version}\n' | screw-up format` の結果です。

## 動作確認

自動テストは次のコマンドで実行できます。

```bash
make test
```

このテストでは次を確認します。

- イメージ build
- コンテナ起動
- 認証付き一覧表示
- 通常起動時に既存ファイルが保持されること
- `WEBDAV_CLEAR_STORAGE_ON_STARTUP=true` で既存ファイルが削除されること
- `PUT`
- アップロード後の一覧確認
- `GET`
- `DELETE`
- 未認証アクセス時の `401`
- 削除後の `404`

## ライセンス

MIT です。
