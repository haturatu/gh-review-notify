#!/bin/bash
# Slack Webhookでレビュー依頼とメンションを別々に通知するスクリプト
#
# 余談だけども`gh`コマンド自体があんまり開発活発じゃなくなったみたいで鬼ようなスクリプトになってしまった...
# AI開発にシフトしてあんまリソース割こうとしていないみたいなネタを見た
#
# 使用方法:
# 1. Slack Webhook URLとGithubのトークンを環境変数に設定:
# 2. スクリプトを実行:
#    ./gh-review-notify.sh
# cronで実行する場合
#   */5 * * * * /path/to/gh-review-notify.sh

##################################
# Configuration
# -------------------------------
# GitHub token環境変数の設定
PATH=$PATH:/opt/homebrew/bin

# `gh auth token`で取得したトークンをBase64エンコードして設定してください
GH_TOKEN_BASE64=""

# Slack Webhook URLの設定（環境変数から取得）
SLACK_WEBHOOK_URL_BASE64=""

#################################

GH_TOKEN=$(printf '%s' "$GH_TOKEN_BASE64" | base64 -d)
GITHUB_TOKEN=$(printf '%s' "$GH_TOKEN_BASE64" | base64 -d)
SLACK_WEBHOOK_URL=$(printf '%s' "$SLACK_WEBHOOK_URL_BASE64" | base64 -d)

# 状態ファイルの設定（レビュー依頼とメンションを別々に管理）
REVIEW_STATE_FILE="/tmp/gh_review_hashes"
MENTION_STATE_FILE="/tmp/gh_mention_hashes"

touch "$REVIEW_STATE_FILE"
touch "$MENTION_STATE_FILE"

# 共通のSlack通知関数
send_to_slack() {
  local title="$1"
  local item_list="$2"
  local message="$title\n\n"
  
  # 各項目の詳細情報を取得
  while IFS= read -r item_line; do
    if [[ -n "$item_line" ]]; then
      local repo_pr=$(echo "$item_line" | sed 's/^[[:space:]]*//')
      
      # PR番号が含まれているかチェック（#数字の形式）
      if echo "$repo_pr" | grep -q '#[0-9]'; then
        # 地獄のようなsedでリポジトリ名とPR番号を抽出
        local repo=$(echo "$repo_pr" | sed 's/\([^#]*\)#.*/\1/')
        local pr_number=$(echo "$repo_pr" | sed 's/.*#\([0-9]*\).*/\1/')
        local pr_title=$(gh pr view "$pr_number" --repo "$repo" --json title --jq '.title' 2>/dev/null)
        local pr_url="https://github.com/$repo/pull/$pr_number"
        
        if [[ -n "$pr_title" ]]; then
          message+="• <$pr_url|$repo#$pr_number> $pr_title\n"
        else
          continue
        fi
      else
        continue
      fi
    fi
  done <<< "$item_list"
  
  # Slackに送信
  local payload=$(cat <<EOF
{
  "text": "$message"
}
EOF
)
  
  curl -X POST -H 'Content-type: application/json' \
    --data "$payload" \
    "$SLACK_WEBHOOK_URL" 2>/dev/null
}

# 更新処理関数
process_updates() {
  local title="$1"
  local state_file="$2"
  local current_list="$3"
  
  local current_hashes=""
  local new_items_list=""
  
  if [[ -n "$current_list" ]]; then
    # 現在のリストの各行をハッシュ化
    while IFS= read -r line; do
      if [[ -n "$line" ]]; then
        line_hash=$(echo "$line" | sha256sum | cut -d' ' -f1)
        # 改行コードの分岐が面倒なので`:wq`等でエディタ次第で保存時に動的に改行入るように
        current_hashes+="$line_hash"$'
'
      fi
    done <<< "$current_list"
    
    # 以前のハッシュリストを読み込む
    previous_hashes=$(cat "$state_file" || echo "")
    
    # 現在のリストの各行について、以前のハッシュリストにないもの（=新しい項目）を見つける
    while IFS= read -r line; do
      if [[ -n "$line" ]]; then
        line_hash=$(echo "$line" | sha256sum | cut -d' ' -f1)
        # このハッシュが以前のリストにない場合、新しい項目
        # 改行コードの分岐が面倒なので`:wq`等でエディタ次第で保存時に動的に改行入るように
        if [[ -z "$previous_hashes" ]] || ! echo "$previous_hashes" | grep -Fxq "$line_hash"; then
          new_items_list+="$line"$'
'
        fi
      fi
    done <<< "$current_list"
    
    # 末尾の改行を削除
    new_items_list=$(echo "$new_items_list" | sed '/^$/d')
    
    if [[ -n "$new_items_list" ]]; then
      # タイトルから絵文字を除去してログに出力
      echo "$title_for_log detected:"
      echo "$new_items_list"
      
      # Slackに通知
      if [[ -n "$SLACK_WEBHOOK_URL" ]]; then
        send_to_slack "$title" "$new_items_list"
      fi
    else
      # タイトルから絵文字を除去してログに出力
      local title_for_log=$(echo "$title" | sed 's/^[^ ]* //')
      echo "No $title_for_log detected." >&2
    fi
  fi
  
  # 現在の状態を保存
  if [[ -n "$current_hashes" ]]; then
    echo "$current_hashes" | sed '/^$/d' > "$state_file"
  fi
}

trim() {
  sed 's/^[[:space:]]*//' | sed 's/[[:space:]]*$//'
}

main() {
  echo "Checking GitHub status..."

  # レビュー依頼を取得（Review RequestsセクションからRepository Activityセクションの前まで）
  # PR番号（#数字）が含まれている行のみを取得
  #
  # 本当はgh statusの出力を`json`形式で取得できれば良いが、`gh api`をあんまりよく知らないので、とりあえずテキスト処理で頑張る
  # そして、awkしているのは実はパイプではなく全角の縦棒（│）で区切られている。。。！
  review_requests=$(gh status 2>/dev/null | sed -n '/^Review Requests/,/^Repository Activity/p' | awk -F│ '{print $1}' | trim | grep -E '#[0-9]' | sort)

  # メンションを取得（Mentionsセクションから最後まで）
  # grep -A 1は、メンションの後に続く投稿内容の行も含めるため
  # これでハッシュしても、内容が変わった場合に再通知されるようになる
  # send_to_slack関数内でPR番号を抽出しているので、ここではそのまま渡す
  mentions=$(gh status 2>/dev/null | sed '/^Mentions/,$p' | awk -F│ '{print $2}' | trim | grep -A 1 -E '#[0-9]' | sort)

  # レビュー依頼を処理
  echo "Processing Review Requests..."
  process_updates "🔔 新しいレビューリクエストが来たよ！" "$REVIEW_STATE_FILE" "$review_requests"

  # メンションを処理
  echo "Processing Mentions..."
  process_updates "💬 人気者の君にメンションがついたよ！" "$MENTION_STATE_FILE" "$mentions"
}

main

