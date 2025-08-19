#!/bin/bash

# EDC Kafka統合 クリーンアップスクリプト
# このスクリプトはEDC Kafka統合で作成されたリソースを削除します

set -e

# 色付きログ用の関数
log_info() {
    echo -e "\033[32m[INFO]\033[0m $1"
}

log_warn() {
    echo -e "\033[33m[WARN]\033[0m $1"
}

log_error() {
    echo -e "\033[31m[ERROR]\033[0m $1"
}

log_step() {
    echo -e "\033[36m[STEP]\033[0m $1"
}

# 設定変数
PROVIDER_MGMT_URL="http://localhost:18181/management/v3"
CONSUMER_MGMT_URL="http://localhost:28181/management/v3"
KAFKA_TOPIC="kafka-stream-topic"

log_info "🧹 EDC Kafka統合リソースのクリーンアップを開始します"

# ステップ1: HTTP Request Loggerの停止
log_step "1. HTTP Request Loggerの停止"
if pgrep -f "http-request-logger" > /dev/null; then
    pkill -f "http-request-logger"
    log_info "✅ HTTP Request Loggerを停止しました"
else
    log_info "ℹ️  HTTP Request Loggerは実行されていません"
fi

# ステップ2: 転送プロセスの確認（削除はできませんが状態を表示）
log_step "2. 転送プロセスの状態確認"
TRANSFER_PROCESSES=$(curl -s "$CONSUMER_MGMT_URL/transferprocesses/request" \
  -X POST -H "Content-Type: application/json" \
  -d '{"@context": {"@vocab": "https://w3id.org/edc/v0.0.1/ns/"}, "@type": "QuerySpec"}' 2>/dev/null || echo "[]")

TRANSFER_COUNT=$(echo "$TRANSFER_PROCESSES" | jq 'length' 2>/dev/null || echo "0")
if [ "$TRANSFER_COUNT" -gt 0 ]; then
    log_info "📋 転送プロセス ($TRANSFER_COUNT 件):"
    echo "$TRANSFER_PROCESSES" | jq -r '.[] | "  - " + .["@id"] + " (" + .state + ")"' 2>/dev/null || log_warn "転送プロセス情報の取得に失敗"
    log_warn "⚠️  転送プロセスは自動削除されません（履歴として保持）"
else
    log_info "ℹ️  転送プロセスはありません"
fi

# ステップ3: 契約交渉の確認（削除はできませんが状態を表示）
log_step "3. 契約交渉の状態確認"
CONTRACT_NEGOTIATIONS=$(curl -s "$CONSUMER_MGMT_URL/contractnegotiations/request" \
  -X POST -H "Content-Type: application/json" \
  -d '{"@context": {"@vocab": "https://w3id.org/edc/v0.0.1/ns/"}, "@type": "QuerySpec"}' 2>/dev/null || echo "[]")

NEGOTIATION_COUNT=$(echo "$CONTRACT_NEGOTIATIONS" | jq 'length' 2>/dev/null || echo "0")
if [ "$NEGOTIATION_COUNT" -gt 0 ]; then
    log_info "📋 契約交渉 ($NEGOTIATION_COUNT 件):"
    echo "$CONTRACT_NEGOTIATIONS" | jq -r '.[] | "  - " + .["@id"] + " (" + .state + ")"' 2>/dev/null || log_warn "契約交渉情報の取得に失敗"
    log_warn "⚠️  契約交渉は自動削除されません（履歴として保持）"
else
    log_info "ℹ️  契約交渉はありません"
fi

# ステップ4: コントラクト定義の削除
log_step "4. コントラクト定義の削除"
CONTRACT_DEFINITIONS=$(curl -s "$PROVIDER_MGMT_URL/contractdefinitions/request" \
  -X POST -H "Content-Type: application/json" \
  -d '{"@context": {"@vocab": "https://w3id.org/edc/v0.0.1/ns/"}, "@type": "QuerySpec"}' 2>/dev/null || echo "[]")

if echo "$CONTRACT_DEFINITIONS" | jq -e '.[]' > /dev/null 2>&1; then
    echo "$CONTRACT_DEFINITIONS" | jq -r '.[] | .["@id"]' | while read -r contract_def_id; do
        if [ -n "$contract_def_id" ] && [ "$contract_def_id" != "null" ]; then
            DELETE_RESPONSE=$(curl -s -w "%{http_code}" -o /dev/null -X DELETE "$PROVIDER_MGMT_URL/contractdefinitions/$contract_def_id" 2>/dev/null || echo "000")
            if [ "$DELETE_RESPONSE" = "204" ] || [ "$DELETE_RESPONSE" = "200" ]; then
                log_info "✅ コントラクト定義を削除しました: $contract_def_id"
            elif [ "$DELETE_RESPONSE" = "404" ]; then
                log_warn "⚠️  コントラクト定義が見つかりません: $contract_def_id"
            else
                log_error "❌ コントラクト定義の削除に失敗: $contract_def_id (HTTP: $DELETE_RESPONSE)"
            fi
        fi
    done
else
    log_info "ℹ️  削除対象のコントラクト定義はありません"
fi

# ステップ5: ポリシー定義の削除
log_step "5. ポリシー定義の削除"
POLICY_DEFINITIONS=$(curl -s "$PROVIDER_MGMT_URL/policydefinitions/request" \
  -X POST -H "Content-Type: application/json" \
  -d '{"@context": {"@vocab": "https://w3id.org/edc/v0.0.1/ns/"}, "@type": "QuerySpec"}' 2>/dev/null || echo "[]")

if echo "$POLICY_DEFINITIONS" | jq -e '.[]' > /dev/null 2>&1; then
    echo "$POLICY_DEFINITIONS" | jq -r '.[] | .["@id"]' | while read -r policy_id; do
        if [ -n "$policy_id" ] && [ "$policy_id" != "null" ]; then
            DELETE_RESPONSE=$(curl -s -w "%{http_code}" -o /dev/null -X DELETE "$PROVIDER_MGMT_URL/policydefinitions/$policy_id" 2>/dev/null || echo "000")
            if [ "$DELETE_RESPONSE" = "204" ] || [ "$DELETE_RESPONSE" = "200" ]; then
                log_info "✅ ポリシー定義を削除しました: $policy_id"
            elif [ "$DELETE_RESPONSE" = "404" ]; then
                log_warn "⚠️  ポリシー定義が見つかりません: $policy_id"
            else
                log_error "❌ ポリシー定義の削除に失敗: $policy_id (HTTP: $DELETE_RESPONSE)"
            fi
        fi
    done
else
    log_info "ℹ️  削除対象のポリシー定義はありません"
fi

# ステップ6: アセットの削除
log_step "6. アセットの削除"
ASSETS=$(curl -s "$PROVIDER_MGMT_URL/assets/request" \
  -X POST -H "Content-Type: application/json" \
  -d '{"@context": {"@vocab": "https://w3id.org/edc/v0.0.1/ns/"}, "@type": "QuerySpec"}' 2>/dev/null || echo "[]")

if echo "$ASSETS" | jq -e '.[]' > /dev/null 2>&1; then
    echo "$ASSETS" | jq -r '.[] | .["@id"]' | while read -r asset_id; do
        if [ -n "$asset_id" ] && [ "$asset_id" != "null" ]; then
            DELETE_RESPONSE=$(curl -s -w "%{http_code}" -o /dev/null -X DELETE "$PROVIDER_MGMT_URL/assets/$asset_id" 2>/dev/null || echo "000")
            if [ "$DELETE_RESPONSE" = "204" ] || [ "$DELETE_RESPONSE" = "200" ]; then
                log_info "✅ アセットを削除しました: $asset_id"
            elif [ "$DELETE_RESPONSE" = "404" ]; then
                log_warn "⚠️  アセットが見つかりません: $asset_id"
            elif [ "$DELETE_RESPONSE" = "409" ]; then
                log_warn "⚠️  アセットは契約で使用中のため削除できません: $asset_id"
                log_info "    プロバイダーコネクタを再起動すると全てのメモリ内データがクリアされます"
            else
                log_error "❌ アセットの削除に失敗: $asset_id (HTTP: $DELETE_RESPONSE)"
            fi
        fi
    done
else
    log_info "ℹ️  削除対象のアセットはありません"
fi

# ステップ7: Kafkaリソースの確認
log_step "7. Kafkaリソースの状態確認"
if docker ps | grep -q kafka-kraft; then
    log_info "📋 Kafkaトピック一覧:"
    docker exec kafka-kraft /bin/kafka-topics --list --bootstrap-server localhost:9093 2>/dev/null | sed 's/^/  - /' || log_warn "トピック一覧の取得に失敗"
    
    log_info "📋 Kafka ACL一覧:"
    docker exec kafka-kraft /bin/kafka-acls --list --bootstrap-server localhost:9093 2>/dev/null | grep -v "^$" | sed 's/^/  /' || log_warn "ACL一覧の取得に失敗"
    
    log_warn "⚠️  Kafkaブローカーは手動で停止してください:"
    echo "    docker stop kafka-kraft"
else
    log_info "ℹ️  Kafkaブローカーは実行されていません"
fi

# ステップ8: 最終確認
log_step "8. 最終確認"

# プロバイダーリソースの確認
REMAINING_ASSETS=$(curl -s "$PROVIDER_MGMT_URL/assets/request" \
  -X POST -H "Content-Type: application/json" \
  -d '{"@context": {"@vocab": "https://w3id.org/edc/v0.0.1/ns/"}, "@type": "QuerySpec"}' 2>/dev/null | jq 'length' 2>/dev/null || echo "0")

REMAINING_POLICIES=$(curl -s "$PROVIDER_MGMT_URL/policydefinitions/request" \
  -X POST -H "Content-Type: application/json" \
  -d '{"@context": {"@vocab": "https://w3id.org/edc/v0.0.1/ns/"}, "@type": "QuerySpec"}' 2>/dev/null | jq 'length' 2>/dev/null || echo "0")

REMAINING_CONTRACTS=$(curl -s "$PROVIDER_MGMT_URL/contractdefinitions/request" \
  -X POST -H "Content-Type: application/json" \
  -d '{"@context": {"@vocab": "https://w3id.org/edc/v0.0.1/ns/"}, "@type": "QuerySpec"}' 2>/dev/null | jq 'length' 2>/dev/null || echo "0")

echo ""
echo "🎊 クリーンアップが完了しました！"
echo ""
echo "📊 残存リソース:"
echo "  - アセット: $REMAINING_ASSETS 件"
echo "  - ポリシー定義: $REMAINING_POLICIES 件"
echo "  - コントラクト定義: $REMAINING_CONTRACTS 件"
echo "  - 転送プロセス: $TRANSFER_COUNT 件 (履歴として保持)"
echo "  - 契約交渉: $NEGOTIATION_COUNT 件 (履歴として保持)"
echo ""

if [ "$REMAINING_ASSETS" -gt 0 ] || [ "$REMAINING_POLICIES" -gt 0 ] || [ "$REMAINING_CONTRACTS" -gt 0 ]; then
    log_warn "⚠️  一部のリソースが残存しています"
    echo ""
    echo "🔄 完全なクリーンアップ方法:"
    echo "  # EDCコネクタの再起動（メモリ内データを完全にクリア）"
    echo "  1. プロバイダーコネクタを停止・再起動"
    echo "  2. コンシューマーコネクタを停止・再起動"
    echo ""
    echo "  # Kafkaブローカーの停止"
    echo "  docker stop kafka-kraft"
else
    log_info "✅ 全てのEDCリソースが正常にクリーンアップされました"
fi

log_info "🧹 EDC Kafka統合のクリーンアップが完了しました！" 