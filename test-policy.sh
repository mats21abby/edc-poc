#!/bin/bash

# EDC ポリシーテストスクリプト
# Usage: ./test-policy.sh [policy-file] [asset-id]

set -e

POLICY_FILE="$1"
ASSET_ID="${2:-batteryDatasetFixed}"
PROVIDER_MGMT="http://localhost:19193/management/v3"
CONSUMER_MGMT="http://localhost:29193/management/v3"
PROVIDER_PROTOCOL="http://localhost:19194/protocol"

# 色付きログ
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_step() {
    echo -e "${BLUE}[STEP]${NC} $1"
}

# 使用方法の表示
usage() {
    echo "Usage: $0 [policy-file] [asset-id]"
    echo ""
    echo "Examples:"
    echo "  $0 sample-policies/time-based-policy.json"
    echo "  $0 sample-policies/research-only-policy.json batteryDatasetFixed"
    echo ""
    echo "Available sample policies:"
    echo "  - sample-policies/time-based-policy.json"
    echo "  - sample-policies/research-only-policy.json"
    echo "  - sample-policies/deletion-obligation-policy.json"
    exit 1
}

# 引数チェック
if [ -z "$POLICY_FILE" ]; then
    log_error "ポリシーファイルが指定されていません"
    usage
fi

if [ ! -f "$POLICY_FILE" ]; then
    log_error "ポリシーファイル '$POLICY_FILE' が見つかりません"
    exit 1
fi

# ポリシーIDを取得
POLICY_ID=$(jq -r '.["@id"]' "$POLICY_FILE")
if [ "$POLICY_ID" = "null" ] || [ -z "$POLICY_ID" ]; then
    log_error "ポリシーファイルから@idを取得できませんでした"
    exit 1
fi

echo "=================================="
echo "🧪 EDC ポリシーテスト"
echo "=================================="
echo "ポリシーファイル: $POLICY_FILE"
echo "ポリシーID: $POLICY_ID"
echo "アセットID: $ASSET_ID"
echo ""

# ステップ1: 既存ポリシーの削除（存在する場合）
log_step "1. 既存ポリシーのクリーンアップ"
curl -X DELETE "$PROVIDER_MGMT/policydefinitions/$POLICY_ID" \
  -H "Content-Type: application/json" \
  -d '{"@context": {"@vocab": "https://w3id.org/edc/v0.0.1/ns/"}}' \
  -s > /dev/null 2>&1 || true
log_info "既存ポリシーをクリーンアップしました"

# ステップ2: 新しいポリシーの登録
log_step "2. 新しいポリシーの登録"
RESPONSE=$(curl -X POST "$PROVIDER_MGMT/policydefinitions" \
  -H "Content-Type: application/json" \
  -d @"$POLICY_FILE" \
  -s)

if echo "$RESPONSE" | jq -e '.["@id"]' > /dev/null 2>&1; then
    log_info "ポリシーが正常に登録されました"
else
    log_error "ポリシーの登録に失敗しました"
    echo "レスポンス: $RESPONSE"
    exit 1
fi

# ステップ3: コントラクト定義の更新
log_step "3. コントラクト定義の更新"

# 既存のコントラクト定義を削除
curl -X DELETE "$PROVIDER_MGMT/contractdefinitions/testContractDef" \
  -H "Content-Type: application/json" \
  -d '{"@context": {"@vocab": "https://w3id.org/edc/v0.0.1/ns/"}}' \
  -s > /dev/null 2>&1 || true

# 新しいコントラクト定義を作成
CONTRACT_RESPONSE=$(curl -X POST "$PROVIDER_MGMT/contractdefinitions" \
  -H "Content-Type: application/json" \
  -d "{
    \"@context\": { \"@vocab\": \"https://w3id.org/edc/v0.0.1/ns/\" },
    \"@id\": \"testContractDef\",
    \"accessPolicyId\": \"$POLICY_ID\",
    \"contractPolicyId\": \"$POLICY_ID\",
    \"assetsSelector\": [{\"operandLeft\": \"id\", \"operator\": \"=\", \"operandRight\": \"$ASSET_ID\"}]
  }" \
  -s)

if echo "$CONTRACT_RESPONSE" | jq -e '.["@id"]' > /dev/null 2>&1; then
    log_info "コントラクト定義が正常に更新されました"
else
    log_error "コントラクト定義の更新に失敗しました"
    echo "レスポンス: $CONTRACT_RESPONSE"
    exit 1
fi

# ステップ4: カタログでの確認
log_step "4. カタログでのポリシー確認"
sleep 2  # ポリシーの反映を待機

CATALOG_RESPONSE=$(curl -s "$CONSUMER_MGMT/catalog/request" \
  -X POST -H "Content-Type: application/json" \
  -d "{
    \"@context\": { \"@vocab\": \"https://w3id.org/edc/v0.0.1/ns/\" },
    \"counterPartyAddress\": \"$PROVIDER_PROTOCOL\",
    \"protocol\": \"dataspace-protocol-http\"
  }")

# アセットがカタログに表示されているか確認
ASSET_IN_CATALOG=$(echo "$CATALOG_RESPONSE" | jq ".\"dcat:dataset\" | select(.\"@id\" == \"$ASSET_ID\")")

if [ "$ASSET_IN_CATALOG" != "null" ] && [ -n "$ASSET_IN_CATALOG" ]; then
    log_info "✅ アセットがカタログに表示されています"
    
    # 適用されているポリシーを表示
    APPLIED_POLICY=$(echo "$ASSET_IN_CATALOG" | jq '.["odrl:hasPolicy"]')
    echo ""
    echo "適用されているポリシー:"
    echo "$APPLIED_POLICY" | jq .
    
else
    log_warn "❌ アセットがカタログに表示されていません"
    echo "これは以下の原因が考えられます:"
    echo "  - ポリシーの制約が厳しすぎる"
    echo "  - アセットIDが間違っている"
    echo "  - コントラクト定義に問題がある"
fi

# ステップ5: ポリシー詳細の表示
log_step "5. ポリシー詳細の表示"
echo ""
echo "登録されたポリシーの詳細:"
jq . "$POLICY_FILE"

echo ""
echo "🎉 ポリシーテストが完了しました！"
echo ""
echo "📝 次のステップ:"
echo "  1. コントラクト交渉を試行してポリシーの動作を確認"
echo "  2. 制約条件を変更してテストを繰り返し"
echo "  3. より複雑なポリシーの作成と適用" 