# gh-review-notify

GitHubでの新しいレビューリクエストやメンションを検知し、Slackに通知するためのシェルスクリプトです。

## 概要

このスクリプトは、`gh status`コマンドの出力を監視し、以下のイベントをSlackに通知します。

- **新しいレビューリクエスト**: あなたがレビュー担当者としてアサインされたPull Request
- **新しいメンション**: あなたがメンションされたPull RequestやIssue

通知はレビューリクエストとメンションで別々のメッセージとして送信され、既に通知済みの項目は再通知されません。

## 依存関係

このスクリプトを実行するには、以下のツールがインストールされている必要があります。

- [GitHub CLI (`gh`)](https://cli.github.com/)
- `curl`
- `base64`
- `sha256sum`

## セットアップ

### 1. GitHub CLIの認証

まず、GitHub CLIでGitHubにログインします。

```bash
gh auth login
```

### 2. スクリプトの設定

スクリプト内の設定項目を編集します。

`gh-review-notify.sh`ファイルを開き、以下の2つの変数を設定してください。

```bash
##################################
# Configuration
# -------------------------------
# ...

# `gh auth token`で取得したトークンをBase64エンコードして設定してください
GH_TOKEN_BASE64="ここにBase64エンコードしたGitHubトークンを設定"

# Slack Webhook URLの設定（環境変数から取得）
SLACK_WEBHOOK_URL_BASE64="ここにBase64エンコードしたSlack Webhook URLを設定"

#################################
```

- **`GH_TOKEN_BASE64`**:
  1. 以下のコマンドでGitHubトークンを取得します。
     ```bash
     gh auth token
     ```
  2. 取得したトークンをBase64エンコードして、`GH_TOKEN_BASE64`の値として設定します。
     ```bash
     echo -n "YOUR_GITHUB_TOKEN" | base64
     ```

- **`SLACK_WEBHOOK_URL_BASE64`**:
  1. Slackで[Incoming WebhookのURL](https://slack.com/intl/ja-jp/help/articles/115005265063-Slack-%E3%81%A7%E3%81%AE-Incoming-Webhook-%E3%81%AE%E5%88%A9%E7%94%A8)を取得します。
  2. 取得したURLをBase64エンコードして、`SLACK_WEBHOOK_URL_BASE64`の値として設定します。
     ```bash
     echo -n "YOUR_SLACK_WEBHOOK_URL" | base64
     ```

> **Note**
> 最低限平文にならないようにしているだけ

## 使い方

### 手動実行

スクリプトに実行権限を与えて実行します。

```bash
chmod +x gh-review-notify.sh
./gh-review-notify.sh
```

### 定期実行 (cron)

`cron`を使ってスクリプトを定期的に実行することで、変更を自動的に検知できます。
以下は5分ごとにスクリプトを実行する例です。
動かないときは、環境変数の設定やパスの問題を確認してください。  
`bash -l`でもいいかも。

```cron
*/5 * * * * /path/to/gh-review-notify.sh > /dev/null 2>&1
```

`/path/to/gh-review-notify.sh`は、スクリプトの絶対パスに置き換えてください。
