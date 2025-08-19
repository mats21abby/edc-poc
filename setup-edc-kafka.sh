#!/bin/bash

# EDC Kafka統合 自動セットアップスクリプト
# このスクリプトはEDC Kafka統合のエンドツーエンドテストを自動実行します

set -e  # エラー時に停止

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
PROVIDER_PROTOCOL_URL="http://localhost:18182/protocol"
HTTP_LOGGER_PORT="4000"
KAFKA_TOPIC="kafka-stream-topic"
KAFKA_BOOTSTRAP_SERVERS="localhost:9093"

# 作業ディレクトリの確認
if [[ ! -d "transfer/transfer-06-kafka-broker" ]]; then
    log_error "transfer/transfer-06-kafka-broker ディレクトリが見つかりません"
    log_error "Samplesディレクトリから実行してください"
    exit 1
fi

log_info "🚀 EDC Kafka統合セットアップを開始します"

# ステップ1: Kafkaブローカーの確認
log_step "1. Kafkaブローカーの動作確認"
if ! docker ps | grep -q kafka-kraft; then
    log_error "Kafkaブローカーが起動していません"
    log_info "以下のコマンドでKafkaブローカーを起動してください："
    echo "docker run --rm --name=kafka-kraft -h kafka-kraft -p 9093:9093 \\"
    echo "    -v \"\$PWD/transfer/transfer-06-kafka-broker/kafka-config\":/config \\"
    echo "    --env-file transfer/transfer-06-kafka-broker/kafka.env \\"
    echo "    -e KAFKA_NODE_ID=1 \\"
    echo "    -e KAFKA_LISTENERS='PLAINTEXT://0.0.0.0:9093,BROKER://0.0.0.0:9092,CONTROLLER://0.0.0.0:9094' \\"
    echo "    -e KAFKA_ADVERTISED_LISTENERS='PLAINTEXT://localhost:9093,BROKER://localhost:9092' \\"
    echo "    -e KAFKA_PROCESS_ROLES='broker,controller' \\"
    echo "    -e KAFKA_OFFSETS_TOPIC_REPLICATION_FACTOR=1 \\"
    echo "    -e KAFKA_TRANSACTION_STATE_LOG_REPLICATION_FACTOR=1 \\"
    echo "    -e KAFKA_CONTROLLER_QUORUM_VOTERS='1@localhost:9094' \\"
    echo "    -e KAFKA_INTER_BROKER_LISTENER_NAME='BROKER' \\"
    echo "    -e KAFKA_CONTROLLER_LISTENER_NAMES='CONTROLLER' \\"
    echo "    -e KAFKA_OFFSETS_TOPIC_NUM_PARTITIONS=1 \\"
    echo "    -e CLUSTER_ID='4L6g3nShT-eMCtK--X86sw' \\"
    echo "    confluentinc/cp-kafka:7.5.2"
    exit 1
fi
log_info "✅ Kafkaブローカーが起動中です"

# ステップ2: EDCコネクタの確認
log_step "2. EDCコネクタの動作確認"
if ! curl -s "$PROVIDER_MGMT_URL/assets/request" -X POST -H "Content-Type: application/json" -d '{"@context": {"@vocab": "https://w3id.org/edc/v0.0.1/ns/"}, "@type": "QuerySpec"}' > /dev/null; then
    log_error "プロバイダーコネクタ($PROVIDER_MGMT_URL)にアクセスできません"
    exit 1
fi

if ! curl -s "$CONSUMER_MGMT_URL/assets/request" -X POST -H "Content-Type: application/json" -d '{"@context": {"@vocab": "https://w3id.org/edc/v0.0.1/ns/"}, "@type": "QuerySpec"}' > /dev/null; then
    log_error "コンシューマーコネクタ($CONSUMER_MGMT_URL)にアクセスできません"
    exit 1
fi
log_info "✅ EDCコネクタが正常に動作しています"

# ステップ3: Kafkaアセットの作成
log_step "3. Kafkaアセットの作成"
ASSET_RESPONSE=$(curl -s -H 'Content-Type: application/json' \
  -d '{
    "@context": { "@vocab": "https://w3id.org/edc/v0.0.1/ns/" },
    "@id": "kafka-stream-asset",
    "properties": {},
    "dataAddress": {
      "type": "Kafka",
      "kafka.bootstrap.servers": "'$KAFKA_BOOTSTRAP_SERVERS'",
      "topic": "'$KAFKA_TOPIC'"
    }
  }' \
  -X POST "$PROVIDER_MGMT_URL/assets")

if echo "$ASSET_RESPONSE" | jq -e '.["@id"]' > /dev/null 2>&1; then
    log_info "✅ Kafkaアセットを作成しました: kafka-stream-asset"
else
    log_error "❌ Kafkaアセットの作成に失敗しました"
    echo "$ASSET_RESPONSE" | jq .
    exit 1
fi

# ステップ4: ポリシー定義の作成
log_step "4. ポリシー定義の作成"
POLICY_RESPONSE=$(curl -s -H 'Content-Type: application/json' \
  -d @transfer/transfer-06-kafka-broker/2-policy-definition.json \
  -X POST "$PROVIDER_MGMT_URL/policydefinitions")

if echo "$POLICY_RESPONSE" | jq -e '.["@id"]' > /dev/null 2>&1; then
    POLICY_ID=$(echo "$POLICY_RESPONSE" | jq -r '.["@id"]')
    log_info "✅ ポリシー定義を作成しました: $POLICY_ID"
else
    log_error "❌ ポリシー定義の作成に失敗しました"
    echo "$POLICY_RESPONSE" | jq .
    exit 1
fi

# ステップ5: コントラクト定義の作成
log_step "5. コントラクト定義の作成"
CONTRACT_DEF_RESPONSE=$(curl -s -H 'Content-Type: application/json' \
  -d @transfer/transfer-06-kafka-broker/3-contract-definition.json \
  -X POST "$PROVIDER_MGMT_URL/contractdefinitions")

if echo "$CONTRACT_DEF_RESPONSE" | jq -e '.["@id"]' > /dev/null 2>&1; then
    CONTRACT_DEF_ID=$(echo "$CONTRACT_DEF_RESPONSE" | jq -r '.["@id"]')
    log_info "✅ コントラクト定義を作成しました: $CONTRACT_DEF_ID"
else
    log_error "❌ コントラクト定義の作成に失敗しました"
    echo "$CONTRACT_DEF_RESPONSE" | jq .
    exit 1
fi

# ステップ6: カタログからデータセットを取得
log_step "6. カタログからデータセットを取得"
CATALOG_RESPONSE=$(curl -s -H 'Content-Type: application/json' \
  -d @transfer/transfer-06-kafka-broker/4-get-dataset.json \
  -X POST "$CONSUMER_MGMT_URL/catalog/dataset/request")

if echo "$CATALOG_RESPONSE" | jq -e '.["@id"]' > /dev/null 2>&1; then
    OFFER_ID=$(echo "$CATALOG_RESPONSE" | jq -r '.["odrl:hasPolicy"]["@id"]')
    log_info "✅ カタログからデータセットを取得しました"
    log_info "オファーID: $OFFER_ID"
else
    log_error "❌ カタログからのデータセット取得に失敗しました"
    echo "$CATALOG_RESPONSE" | jq .
    exit 1
fi

# ステップ7: コントラクト交渉の開始
log_step "7. コントラクト交渉の開始"
NEGOTIATION_RESPONSE=$(curl -s -H 'Content-Type: application/json' \
  -d '{
    "@context": {
      "@vocab": "https://w3id.org/edc/v0.0.1/ns/"
    },
    "@type": "ContractRequest",
    "counterPartyAddress": "'$PROVIDER_PROTOCOL_URL'",
    "protocol": "dataspace-protocol-http",
    "policy": {
      "@context": "http://www.w3.org/ns/odrl.jsonld",
      "@id": "'$OFFER_ID'",
      "@type": "Offer",
      "assigner": "provider",
      "target": "kafka-stream-asset"
    }
  }' \
  -X POST "$CONSUMER_MGMT_URL/contractnegotiations")

if echo "$NEGOTIATION_RESPONSE" | jq -e '.["@id"]' > /dev/null 2>&1; then
    NEGOTIATION_ID=$(echo "$NEGOTIATION_RESPONSE" | jq -r '.["@id"]')
    log_info "✅ コントラクト交渉を開始しました: $NEGOTIATION_ID"
else
    log_error "❌ コントラクト交渉の開始に失敗しました"
    echo "$NEGOTIATION_RESPONSE" | jq .
    exit 1
fi

# ステップ8: 交渉完了まで待機
log_step "8. コントラクト交渉の完了を待機中..."
RETRY_COUNT=0
MAX_RETRIES=10
while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
    sleep 3
    NEGOTIATION_STATUS=$(curl -s "$CONSUMER_MGMT_URL/contractnegotiations/request" \
      -X POST -H "Content-Type: application/json" \
      -d '{"@context": {"@vocab": "https://w3id.org/edc/v0.0.1/ns/"}, "@type": "QuerySpec"}' \
      | jq -r '.[] | select(.["@id"] == "'$NEGOTIATION_ID'") | .state')
    
    if [ "$NEGOTIATION_STATUS" = "FINALIZED" ]; then
        CONTRACT_ID=$(curl -s "$CONSUMER_MGMT_URL/contractnegotiations/request" \
          -X POST -H "Content-Type: application/json" \
          -d '{"@context": {"@vocab": "https://w3id.org/edc/v0.0.1/ns/"}, "@type": "QuerySpec"}' \
          | jq -r '.[] | select(.["@id"] == "'$NEGOTIATION_ID'") | .contractAgreementId')
        log_info "✅ コントラクト交渉が完了しました"
        log_info "契約合意ID: $CONTRACT_ID"
        break
    elif [ "$NEGOTIATION_STATUS" = "TERMINATED" ]; then
        log_error "❌ コントラクト交渉が終了しました"
        exit 1
    fi
    
    RETRY_COUNT=$((RETRY_COUNT + 1))
    log_info "交渉状態: $NEGOTIATION_STATUS (試行 $RETRY_COUNT/$MAX_RETRIES)"
done

if [ $RETRY_COUNT -eq $MAX_RETRIES ]; then
    log_error "❌ コントラクト交渉がタイムアウトしました"
    exit 1
fi

# ステップ9: HTTP Request Loggerの起動
log_step "9. HTTP Request Loggerの起動"
if ! pgrep -f "http-request-logger" > /dev/null; then
    if [ ! -f "util/http-request-logger/build/libs/http-request-logger.jar" ]; then
        log_info "HTTP Request Loggerをビルドしています..."
        ./gradlew util:http-request-logger:build > /dev/null 2>&1
    fi
    
    log_info "HTTP Request Loggerを起動しています (ポート$HTTP_LOGGER_PORT)..."
    HTTP_SERVER_PORT=$HTTP_LOGGER_PORT java -jar util/http-request-logger/build/libs/http-request-logger.jar > /dev/null 2>&1 &
    HTTP_LOGGER_PID=$!
    sleep 2
    
    if kill -0 $HTTP_LOGGER_PID 2>/dev/null; then
        log_info "✅ HTTP Request Loggerが起動しました (PID: $HTTP_LOGGER_PID)"
    else
        log_error "❌ HTTP Request Loggerの起動に失敗しました"
        exit 1
    fi
else
    log_info "✅ HTTP Request Loggerは既に起動しています"
fi

# ステップ10: データ転送の開始
log_step "10. データ転送の開始"
TRANSFER_RESPONSE=$(curl -s -H 'Content-Type: application/json' \
  -d '{
    "@context": {
      "@vocab": "https://w3id.org/edc/v0.0.1/ns/"
    },
    "@type": "TransferRequestDto",
    "connectorId": "provider",
    "counterPartyAddress": "'$PROVIDER_PROTOCOL_URL'",
    "contractId": "'$CONTRACT_ID'",
    "protocol": "dataspace-protocol-http",
    "transferType": "KafkaBroker-PULL",
    "assetId": "kafka-stream-asset",
    "dataDestination": {
      "type": "HttpProxy",
      "baseUrl": "http://localhost:'$HTTP_LOGGER_PORT'"
    },
    "callbackAddresses": [
      {
        "uri": "http://localhost:'$HTTP_LOGGER_PORT'",
        "events": ["transfer.process.started"]
      }
    ]
  }' \
  -X POST "$CONSUMER_MGMT_URL/transferprocesses")

if echo "$TRANSFER_RESPONSE" | jq -e '.["@id"]' > /dev/null 2>&1; then
    TRANSFER_ID=$(echo "$TRANSFER_RESPONSE" | jq -r '.["@id"]')
    log_info "✅ データ転送を開始しました: $TRANSFER_ID"
else
    log_error "❌ データ転送の開始に失敗しました"
    echo "$TRANSFER_RESPONSE" | jq .
    exit 1
fi

# ステップ11: 転送完了まで待機
log_step "11. データ転送の開始を待機中..."
RETRY_COUNT=0
MAX_RETRIES=10
while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
    sleep 3
    TRANSFER_STATUS=$(curl -s "$CONSUMER_MGMT_URL/transferprocesses/request" \
      -X POST -H "Content-Type: application/json" \
      -d '{"@context": {"@vocab": "https://w3id.org/edc/v0.0.1/ns/"}, "@type": "QuerySpec"}' \
      | jq -r '.[] | select(.["@id"] == "'$TRANSFER_ID'") | .state')
    
    if [ "$TRANSFER_STATUS" = "STARTED" ]; then
        log_info "✅ データ転送が開始されました"
        break
    elif [ "$TRANSFER_STATUS" = "TERMINATED" ]; then
        log_error "❌ データ転送が終了しました"
        exit 1
    fi
    
    RETRY_COUNT=$((RETRY_COUNT + 1))
    log_info "転送状態: $TRANSFER_STATUS (試行 $RETRY_COUNT/$MAX_RETRIES)"
done

if [ $RETRY_COUNT -eq $MAX_RETRIES ]; then
    log_error "❌ データ転送開始がタイムアウトしました"
    exit 1
fi

# ステップ12: テストメッセージの送信
log_step "12. Kafkaテストメッセージの送信"
echo "🎉 EDC Kafka Integration Test Message $(date)" | docker exec -i kafka-kraft /bin/kafka-console-producer \
  --topic $KAFKA_TOPIC \
  --producer.config=/config/admin.properties \
  --bootstrap-server $KAFKA_BOOTSTRAP_SERVERS

log_info "✅ テストメッセージを送信しました"

# ステップ13: 複数メッセージの送信
log_step "13. 複数メッセージの送信"
for i in {1..3}; do 
  echo "Test message $i from EDC-Kafka integration $(date)"
done | docker exec -i kafka-kraft /bin/kafka-console-producer \
  --topic $KAFKA_TOPIC \
  --producer.config=/config/admin.properties \
  --bootstrap-server $KAFKA_BOOTSTRAP_SERVERS

log_info "✅ 複数のテストメッセージを送信しました"

# 完了メッセージ
echo ""
echo "🎊 EDC Kafka統合セットアップが完了しました！"
echo ""
echo "📊 作成されたリソース:"
echo "  - Kafkaアセット: kafka-stream-asset"
echo "  - ポリシー定義: $POLICY_ID"
echo "  - コントラクト定義: $CONTRACT_DEF_ID"
echo "  - 契約合意: $CONTRACT_ID"
echo "  - 転送プロセス: $TRANSFER_ID"
echo ""
echo "🔍 確認コマンド:"
echo "  # Kafkaメッセージの確認"
echo "  docker exec kafka-kraft /bin/kafka-console-consumer --topic $KAFKA_TOPIC \\"
echo "    --bootstrap-server $KAFKA_BOOTSTRAP_SERVERS \\"
echo "    --consumer-property group.id=test_group \\"
echo "    --consumer-property security.protocol=SASL_PLAINTEXT \\"
echo "    --consumer-property sasl.mechanism=PLAIN \\"
echo "    --consumer-property sasl.jaas.config='org.apache.kafka.common.security.plain.PlainLoginModule required username=\"alice\" password=\"alice-secret\";' \\"
echo "    --from-beginning"
echo ""
echo "  # HTTP Request Loggerログの確認"
echo "  curl -s http://localhost:$HTTP_LOGGER_PORT/logs 2>/dev/null || echo 'ログエンドポイントが利用できません'"
echo ""
echo "🧹 クリーンアップ:"
echo "  # HTTP Request Loggerの停止"
echo "  pkill -f http-request-logger"
echo ""
echo "  # EDCリソースの削除"
echo "  curl -X DELETE '$PROVIDER_MGMT_URL/assets/kafka-stream-asset'"
echo "  curl -X DELETE '$PROVIDER_MGMT_URL/policydefinitions/$POLICY_ID'"
echo "  curl -X DELETE '$PROVIDER_MGMT_URL/contractdefinitions/$CONTRACT_DEF_ID'"
echo ""

log_info "🚀 EDC Kafka統合が正常に動作しています！" 