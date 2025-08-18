#!/bin/bash

# EDC SPARQL統合 自動化スクリプト
# Usage: ./setup-edc-sparql.sh

set -e

echo "🚀 EDC SPARQL統合セットアップを開始します..."

# 設定変数
PROVIDER_MGMT="http://localhost:19193/management/v3"
CONSUMER_MGMT="http://localhost:29193/management/v3"
PROVIDER_PROTOCOL="http://localhost:19194/protocol"
PROXY_ENDPOINT="http://localhost:19291/public/"
SPARQL_ENDPOINT="http://localhost:3030/battery_dataset/query"

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

# 前提条件チェック
check_prerequisites() {
    log_info "前提条件をチェックしています..."
    
    # 必要なコマンドの確認
    for cmd in curl jq; do
        if ! command -v $cmd &> /dev/null; then
            log_error "$cmd が見つかりません。インストールしてください。"
            exit 1
        fi
    done
    
    # SPARQLエンドポイントの確認
    if ! curl -s --connect-timeout 5 "$SPARQL_ENDPOINT" > /dev/null; then
        log_warn "SPARQLエンドポイント ($SPARQL_ENDPOINT) に接続できません"
        log_warn "Apache Jena Fusekiが起動していることを確認してください"
    else
        log_info "SPARQLエンドポイントが利用可能です"
    fi
}

# コネクタの起動確認
check_connectors() {
    log_info "コネクタの起動状況を確認しています..."
    
    # プロバイダーの確認
    if curl -s --connect-timeout 5 "$PROVIDER_MGMT/assets" > /dev/null; then
        log_info "プロバイダーコネクタが起動しています"
    else
        log_error "プロバイダーコネクタが起動していません"
        log_error "以下のコマンドで起動してください:"
        log_error "java -Dedc.fs.config=transfer/transfer-03-consumer-pull/resources/configuration/provider.properties -jar transfer/transfer-03-consumer-pull/provider-proxy-data-plane/build/libs/connector.jar"
        exit 1
    fi
    
    # コンシューマーの確認
    if curl -s --connect-timeout 5 "$CONSUMER_MGMT/assets" > /dev/null; then
        log_info "コンシューマーコネクタが起動しています"
    else
        log_error "コンシューマーコネクタが起動していません"
        log_error "以下のコマンドで起動してください:"
        log_error "java -Dedc.fs.config=transfer/transfer-00-prerequisites/resources/configuration/consumer-configuration.properties -jar transfer/transfer-00-prerequisites/connector/build/libs/connector.jar"
        exit 1
    fi
}

# リソースの作成
create_resources() {
    log_info "EDCリソースを作成しています..."
    
    # アセットの作成
    log_info "バッテリーデータセットアセットを作成中..."
    curl -X POST "$PROVIDER_MGMT/assets" \
         -H "Content-Type: application/json" \
         -d '{
           "@context": { "@vocab": "https://w3id.org/edc/v0.0.1/ns/" },
           "@id": "batteryDatasetFixed",
           "properties": {
             "name": "Battery Dataset SPARQL Endpoint (Fixed)",
             "contenttype": "application/sparql-results+json",
             "description": "Battery dataset accessible via SPARQL queries - Fixed URL"
           },
           "dataAddress": {
             "type": "HttpData",
             "name": "Battery Dataset",
             "baseUrl": "'"$SPARQL_ENDPOINT"'",
             "proxyPath": "false",
             "method": "POST",
             "contentType": "application/x-www-form-urlencoded"
           }
         }' -s > /dev/null
    
    # ポリシーの作成
    log_info "アクセスポリシーを作成中..."
    curl -X POST "$PROVIDER_MGMT/policydefinitions" \
         -H "Content-Type: application/json" \
         -d '{
           "@context": { "@vocab": "https://w3id.org/edc/v0.0.1/ns/" },
           "@id": "aPolicy",
           "@type": "PolicyDefinition",
           "policy": {
             "@type": "odrl:Set",
             "odrl:permission": [],
             "odrl:prohibition": [],
             "odrl:obligation": []
           }
         }' -s > /dev/null
    
    # コントラクト定義の作成
    log_info "コントラクト定義を作成中..."
    curl -X POST "$PROVIDER_MGMT/contractdefinitions" \
         -H "Content-Type: application/json" \
         -d '{
           "@context": { "@vocab": "https://w3id.org/edc/v0.0.1/ns/" },
           "@id": "universalContractDef",
           "accessPolicyId": "aPolicy",
           "contractPolicyId": "aPolicy",
           "assetsSelector": []
         }' -s > /dev/null
    
    log_info "リソースの作成が完了しました"
}

# コントラクト交渉とデータ転送
negotiate_and_transfer() {
    log_info "コントラクト交渉を開始しています..."
    
    # オファーIDの取得
    log_info "カタログからオファーIDを取得中..."
    OFFER_ID=$(curl -X POST "$CONSUMER_MGMT/catalog/request" \
         -H "Content-Type: application/json" \
         -d '{
           "@context": { "@vocab": "https://w3id.org/edc/v0.0.1/ns/" },
           "counterPartyAddress": "'"$PROVIDER_PROTOCOL"'",
           "protocol": "dataspace-protocol-http"
         }' -s | jq -r '."dcat:dataset"[] | select(.["@id"] == "batteryDatasetFixed") | ."odrl:hasPolicy"."@id"')
    
    if [ "$OFFER_ID" = "null" ] || [ -z "$OFFER_ID" ]; then
        log_error "オファーIDの取得に失敗しました"
        exit 1
    fi
    log_info "オファーID: $OFFER_ID"
    
    # コントラクト交渉の開始
    log_info "コントラクト交渉を開始中..."
    NEGOTIATION_ID=$(curl -X POST "$CONSUMER_MGMT/contractnegotiations" \
         -H "Content-Type: application/json" \
         -d '{
           "@context": {
             "@vocab": "https://w3id.org/edc/v0.0.1/ns/"
           },
           "@type": "ContractRequest",
           "counterPartyAddress": "'"$PROVIDER_PROTOCOL"'",
           "protocol": "dataspace-protocol-http",
           "policy": {
             "@context": "http://www.w3.org/ns/odrl.jsonld",
             "@id": "'"$OFFER_ID"'",
             "@type": "Offer",
             "assigner": "provider",
             "target": "batteryDatasetFixed"
           }
         }' -s | jq -r '.["@id"]')
    
    if [ "$NEGOTIATION_ID" = "null" ] || [ -z "$NEGOTIATION_ID" ]; then
        log_error "コントラクト交渉の開始に失敗しました"
        exit 1
    fi
    log_info "交渉ID: $NEGOTIATION_ID"
    
    # 交渉完了の待機
    log_info "交渉完了を待機中..."
    sleep 5
    
    CONTRACT_AGREEMENT_ID=$(curl -s "$CONSUMER_MGMT/contractnegotiations/request" \
         -X POST -H "Content-Type: application/json" \
         -d '{"@context": {"@vocab": "https://w3id.org/edc/v0.0.1/ns/"}, "@type": "QuerySpec"}' \
         | jq -r ".[] | select(.\"@id\" == \"$NEGOTIATION_ID\") | .contractAgreementId")
    
    if [ "$CONTRACT_AGREEMENT_ID" = "null" ] || [ -z "$CONTRACT_AGREEMENT_ID" ]; then
        log_error "コントラクトアグリーメントIDの取得に失敗しました"
        exit 1
    fi
    log_info "コントラクトアグリーメントID: $CONTRACT_AGREEMENT_ID"
    
    # データ転送の開始
    log_info "データ転送を開始中..."
    TRANSFER_ID=$(curl -X POST "$CONSUMER_MGMT/transferprocesses" \
         -H "Content-Type: application/json" \
         -d '{
           "@context": {
             "@vocab": "https://w3id.org/edc/v0.0.1/ns/"
           },
           "@type": "TransferRequestDto",
           "connectorId": "provider",
           "counterPartyAddress": "'"$PROVIDER_PROTOCOL"'",
           "contractId": "'"$CONTRACT_AGREEMENT_ID"'",
           "protocol": "dataspace-protocol-http",
           "transferType": "HttpData-PULL",
           "assetId": "batteryDatasetFixed"
         }' -s | jq -r '.["@id"]')
    
    if [ "$TRANSFER_ID" = "null" ] || [ -z "$TRANSFER_ID" ]; then
        log_error "データ転送の開始に失敗しました"
        exit 1
    fi
    log_info "転送ID: $TRANSFER_ID"
    
    # EDRトークンの取得
    log_info "EDRトークンを取得中..."
    sleep 5
    
    EDR_TOKEN=$(curl -s "$CONSUMER_MGMT/edrs/$TRANSFER_ID/dataaddress" | jq -r '.authorization')
    
    if [ "$EDR_TOKEN" = "null" ] || [ -z "$EDR_TOKEN" ]; then
        log_error "EDRトークンの取得に失敗しました"
        exit 1
    fi
    log_info "EDRトークンを取得しました"
    
    # グローバル変数として保存
    export EDR_TOKEN
}

# SPARQLクエリのテスト
test_sparql_queries() {
    log_info "SPARQLクエリをテストしています..."
    
    # 基本クエリのテスト
    log_info "基本的なSPARQLクエリを実行中..."
    RESULT=$(curl -X POST "$PROXY_ENDPOINT" \
         -H "Authorization: $EDR_TOKEN" \
         -H "Content-Type: application/sparql-query" \
         --data 'SELECT ?subject ?predicate ?object WHERE { ?subject ?predicate ?object } LIMIT 3' \
         -s)
    
    if echo "$RESULT" | jq -e '.results.bindings' > /dev/null 2>&1; then
        log_info "✅ SPARQLクエリが成功しました!"
        echo "$RESULT" | jq .
    else
        log_error "❌ SPARQLクエリが失敗しました"
        echo "レスポンス: $RESULT"
        exit 1
    fi
}

# メイン実行
main() {
    echo "=================================="
    echo "🔧 EDC SPARQL統合セットアップ"
    echo "=================================="
    
    check_prerequisites
    check_connectors
    create_resources
    negotiate_and_transfer
    test_sparql_queries
    
    echo ""
    echo "🎉 セットアップが完了しました!"
    echo ""
    echo "📝 使用方法:"
    echo "以下のコマンドでSPARQLクエリを実行できます:"
    echo ""
    echo "curl -X POST \"$PROXY_ENDPOINT\" \\"
    echo "  -H \"Authorization: $EDR_TOKEN\" \\"
    echo "  -H \"Content-Type: application/sparql-query\" \\"
    echo "  --data 'SELECT ?subject ?predicate ?object WHERE { ?subject ?predicate ?object } LIMIT 10' \\"
    echo "  -s | jq ."
    echo ""
    echo "💾 EDRトークンを保存しました:"
    echo "export EDR_TOKEN=\"$EDR_TOKEN\""
}

# スクリプト実行
main "$@" 