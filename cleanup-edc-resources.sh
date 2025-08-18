#!/bin/bash

# EDC リソースクリーンアップスクリプト
# Usage: ./cleanup-edc-resources.sh

set -e

echo "🗑️ EDCリソースのクリーンアップを開始します..."

# 設定変数
PROVIDER_MGMT="http://localhost:19193/management/v3"
CONSUMER_MGMT="http://localhost:29193/management/v3"

# 色付きログ
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
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

# 削除前の状態確認
check_current_state() {
    log_info "現在のリソース状態を確認しています..."
    
    ASSETS_COUNT=$(curl -s "$PROVIDER_MGMT/assets/request" \
      -X POST -H "Content-Type: application/json" \
      -d '{"@context": {"@vocab": "https://w3id.org/edc/v0.0.1/ns/"}, "@type": "QuerySpec"}' \
      2>/dev/null | jq 'length' 2>/dev/null || echo "0")
    
    POLICIES_COUNT=$(curl -s "$PROVIDER_MGMT/policydefinitions/request" \
      -X POST -H "Content-Type: application/json" \
      -d '{"@context": {"@vocab": "https://w3id.org/edc/v0.0.1/ns/"}, "@type": "QuerySpec"}' \
      2>/dev/null | jq 'length' 2>/dev/null || echo "0")
    
    CONTRACTS_COUNT=$(curl -s "$PROVIDER_MGMT/contractdefinitions/request" \
      -X POST -H "Content-Type: application/json" \
      -d '{"@context": {"@vocab": "https://w3id.org/edc/v0.0.1/ns/"}, "@type": "QuerySpec"}' \
      2>/dev/null | jq 'length' 2>/dev/null || echo "0")
    
    echo "削除前の状態:"
    echo "   - アセット: $ASSETS_COUNT 個"
    echo "   - ポリシー定義: $POLICIES_COUNT 個"
    echo "   - コントラクト定義: $CONTRACTS_COUNT 個"
}

# リソース削除
delete_resources() {
    log_info "リソースの削除を開始します..."
    
    # 1. コントラクト定義を削除（依存関係のため最初に削除）
    log_info "1. コントラクト定義を削除中..."
    curl -X DELETE "$PROVIDER_MGMT/contractdefinitions/universalContractDef" \
      -H "Content-Type: application/json" \
      -d '{"@context": {"@vocab": "https://w3id.org/edc/v0.0.1/ns/"}}' \
      -s > /dev/null 2>&1 || log_warn "コントラクト定義の削除に失敗（存在しない可能性があります）"
    
    # 2. アセットを削除（依存関係エラー対策）
    log_info "2. アセットを削除中..."
    ASSET_DELETE_RESULT=$(curl -X DELETE "$PROVIDER_MGMT/assets/batteryDatasetFixed" \
      -H "Content-Type: application/json" \
      -d '{"@context": {"@vocab": "https://w3id.org/edc/v0.0.1/ns/"}}' \
      -s 2>/dev/null)
    
    # 依存関係エラーの確認
    if echo "$ASSET_DELETE_RESULT" | grep -q "ObjectConflict" 2>/dev/null; then
        log_warn "⚠️ アセットが契約合意または進行中の交渉で参照されています"
        log_info "アクティブな転送プロセスを確認中..."
        
        # アクティブな転送プロセスをチェック
        ACTIVE_TRANSFERS=$(curl -s "$CONSUMER_MGMT/transferprocesses/request" \
          -X POST -H "Content-Type: application/json" \
          -d '{"@context": {"@vocab": "https://w3id.org/edc/v0.0.1/ns/"}, "@type": "QuerySpec"}' \
          2>/dev/null | jq -r '.[] | select(.assetId == "batteryDatasetFixed" and (.state == "STARTED" or .state == "REQUESTED")) | .["@id"]' 2>/dev/null)
        
        if [ -n "$ACTIVE_TRANSFERS" ]; then
            log_warn "アクティブな転送プロセスが見つかりました"
            log_info "推奨解決策: プロバイダーコネクタを再起動してインメモリデータをクリア"
        else
            log_warn "推奨解決策: プロバイダーコネクタを再起動してインメモリデータをクリア"
        fi
    else
        log_info "アセットが正常に削除されました"
    fi
    
    # 3. ポリシー定義を削除
    log_info "3. ポリシー定義を削除中..."
    curl -X DELETE "$PROVIDER_MGMT/policydefinitions/aPolicy" \
      -H "Content-Type: application/json" \
      -d '{"@context": {"@vocab": "https://w3id.org/edc/v0.0.1/ns/"}}' \
      -s > /dev/null 2>&1 || log_warn "ポリシー定義の削除に失敗（存在しない可能性があります）"
}

# 削除後の状態確認
check_final_state() {
    log_info "削除結果を確認しています..."
    
    sleep 2  # 削除処理の完了を待機
    
    ASSETS_COUNT=$(curl -s "$PROVIDER_MGMT/assets/request" \
      -X POST -H "Content-Type: application/json" \
      -d '{"@context": {"@vocab": "https://w3id.org/edc/v0.0.1/ns/"}, "@type": "QuerySpec"}' \
      2>/dev/null | jq 'length' 2>/dev/null || echo "0")
    
    POLICIES_COUNT=$(curl -s "$PROVIDER_MGMT/policydefinitions/request" \
      -X POST -H "Content-Type: application/json" \
      -d '{"@context": {"@vocab": "https://w3id.org/edc/v0.0.1/ns/"}, "@type": "QuerySpec"}' \
      2>/dev/null | jq 'length' 2>/dev/null || echo "0")
    
    CONTRACTS_COUNT=$(curl -s "$PROVIDER_MGMT/contractdefinitions/request" \
      -X POST -H "Content-Type: application/json" \
      -d '{"@context": {"@vocab": "https://w3id.org/edc/v0.0.1/ns/"}, "@type": "QuerySpec"}' \
      2>/dev/null | jq 'length' 2>/dev/null || echo "0")
    
    echo ""
    echo "✅ クリーンアップ完了:"
    echo "   - アセット: $ASSETS_COUNT 個"
    echo "   - ポリシー定義: $POLICIES_COUNT 個"
    echo "   - コントラクト定義: $CONTRACTS_COUNT 個"
}

# 履歴の表示
show_history() {
    log_info "削除できない履歴リソースを確認しています..."
    
    # コントラクト交渉の履歴
    NEGOTIATIONS_COUNT=$(curl -s "$CONSUMER_MGMT/contractnegotiations/request" \
      -X POST -H "Content-Type: application/json" \
      -d '{"@context": {"@vocab": "https://w3id.org/edc/v0.0.1/ns/"}, "@type": "QuerySpec"}' \
      2>/dev/null | jq 'length' 2>/dev/null || echo "0")
    
    # 転送プロセスの履歴
    TRANSFERS_COUNT=$(curl -s "$CONSUMER_MGMT/transferprocesses/request" \
      -X POST -H "Content-Type: application/json" \
      -d '{"@context": {"@vocab": "https://w3id.org/edc/v0.0.1/ns/"}, "@type": "QuerySpec"}' \
      2>/dev/null | jq 'length' 2>/dev/null || echo "0")
    
    echo ""
    echo "📊 履歴データ（削除されません）:"
    echo "   - コントラクト交渉: $NEGOTIATIONS_COUNT 個"
    echo "   - 転送プロセス: $TRANSFERS_COUNT 個"
    echo ""
    echo "💡 これらの履歴データはコネクタ再起動で消去されます（インメモリストレージの場合）"
}

# メイン実行
main() {
    echo "=================================="
    echo "🗑️ EDC リソースクリーンアップ"
    echo "=================================="
    
    check_current_state
    echo ""
    
    read -p "リソースを削除しますか？ (y/N): " -n 1 -r
    echo ""
    
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        delete_resources
        check_final_state
        show_history
        echo ""
        echo "🎉 クリーンアップが完了しました！"
    else
        echo "クリーンアップをキャンセルしました。"
    fi
}

# スクリプト実行
main "$@" 