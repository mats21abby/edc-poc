# EDC Kafka統合ガイド

Eclipse Data Connector (EDC) とApache Kafkaを統合し、セキュアなストリーミングデータアクセスを実現するための完全なガイドです。

## 📋 概要

このガイドでは、EDCを使用してKafkaトピックへのアクセスを制御し、契約ベースでストリーミングデータを提供する方法を説明します。

### 🎯 学習目標

- EDC Kafkaエクステンションの理解
- Kafkaブローカーのセットアップ（KRaftモード）
- EDCを通じたKafkaアクセス制御
- SASL認証とACL設定
- EndpointDataReference（EDR）を使用したセキュアアクセス

### 🏗️ アーキテクチャ

```
Producer → Kafka Broker → EDC Provider → EDC Consumer → Client
          (localhost:9093)   (18181/18182)   (28181/28182)
```

## 🔧 前提条件

### システム要件
- Java 11以上
- Docker
- curl, jq

### EDCコネクタの起動
EDCコネクタが起動していることを確認してください：

```bash
# プロバイダーコネクタ（ポート18181/18182）
# コンシューマーコネクタ（ポート28181/28182）
```

## 📝 手順

### 手順1: Kafkaブローカーの起動

#### 1.1 Kafkaブローカーの起動（KRaftモード）

```bash
cd /Users/mats21/edc-poc

# Kafkaブローカーを起動
docker run --rm --name=kafka-kraft -h kafka-kraft -p 9093:9093 \
    -v "$PWD/Samples/transfer/transfer-06-kafka-broker/kafka-config":/config \
    --env-file Samples/transfer/transfer-06-kafka-broker/kafka.env \
    -e KAFKA_NODE_ID=1 \
    -e KAFKA_LISTENERS='PLAINTEXT://0.0.0.0:9093,BROKER://0.0.0.0:9092,CONTROLLER://0.0.0.0:9094' \
    -e KAFKA_ADVERTISED_LISTENERS='PLAINTEXT://localhost:9093,BROKER://localhost:9092' \
    -e KAFKA_PROCESS_ROLES='broker,controller' \
    -e KAFKA_OFFSETS_TOPIC_REPLICATION_FACTOR=1 \
    -e KAFKA_TRANSACTION_STATE_LOG_REPLICATION_FACTOR=1 \
    -e KAFKA_CONTROLLER_QUORUM_VOTERS='1@localhost:9094' \
    -e KAFKA_INTER_BROKER_LISTENER_NAME='BROKER' \
    -e KAFKA_CONTROLLER_LISTENER_NAMES='CONTROLLER' \
    -e KAFKA_OFFSETS_TOPIC_NUM_PARTITIONS=1 \
    -e CLUSTER_ID='4L6g3nShT-eMCtK--X86sw' \
    confluentinc/cp-kafka:7.5.2
```

#### 1.2 Kafkaトピックの作成

```bash
# トピックを作成
docker exec kafka-kraft /bin/kafka-topics --create \
  --topic kafka-stream-topic \
  --bootstrap-server localhost:9093 \
  --partitions 1 \
  --replication-factor 1
```

#### 1.3 ACL（アクセス制御リスト）の設定

```bash
# aliceユーザーに読み取り権限を付与
docker exec kafka-kraft /bin/kafka-acls --authorizer-properties zookeeper.connect=localhost:2181 \
  --add --allow-principal User:alice \
  --operation Read --group '*' \
  --topic kafka-stream-topic \
  --bootstrap-server localhost:9093
```

### 手順2: EDCリソースの作成

#### 2.1 Kafkaアセットの作成

```bash
curl -H 'Content-Type: application/json' \
  -d '{
    "@context": { "@vocab": "https://w3id.org/edc/v0.0.1/ns/" },
    "@id": "kafka-stream-asset",
    "properties": {},
    "dataAddress": {
      "type": "Kafka",
      "kafka.bootstrap.servers": "localhost:9093",
      "topic": "kafka-stream-topic"
    }
  }' \
  -X POST "http://localhost:18181/management/v3/assets" -s | jq
```

**期待される出力:**
```json
{
  "@type": "IdResponse",
  "@id": "kafka-stream-asset",
  "createdAt": 1755583292793,
  "@context": {
    "@vocab": "https://w3id.org/edc/v0.0.1/ns/",
    "edc": "https://w3id.org/edc/v0.0.1/ns/",
    "odrl": "http://www.w3.org/ns/odrl/2/"
  }
}
```

#### 2.2 ポリシー定義の作成

```bash
curl -H 'Content-Type: application/json' \
  -d @Samples/transfer/transfer-06-kafka-broker/2-policy-definition.json \
  -X POST "http://localhost:18181/management/v3/policydefinitions" -s | jq
```

#### 2.3 コントラクト定義の作成

```bash
curl -H 'Content-Type: application/json' \
  -d @Samples/transfer/transfer-06-kafka-broker/3-contract-definition.json \
  -X POST "http://localhost:18181/management/v3/contractdefinitions" -s | jq
```

### 手順3: コントラクト交渉

#### 3.1 カタログからデータセットを取得

```bash
curl -H 'Content-Type: application/json' \
  -d @Samples/transfer/transfer-06-kafka-broker/4-get-dataset.json \
  -X POST "http://localhost:28181/management/v3/catalog/dataset/request" -s | jq
```

**期待される出力例:**
```json
{
  "@id": "kafka-stream-asset",
  "@type": "dcat:Dataset",
  "odrl:hasPolicy": {
    "@id": "Y29udHJhY3QtZGVmaW5pdGlvbg==:a2Fma2Etc3RyZWFtLWFzc2V0:NTU5YTJhYTktMmE1NC00YTRjLTgxODAtMGQyNmRkYWEzNzlk",
    "@type": "odrl:Offer",
    "odrl:permission": [],
    "odrl:prohibition": [],
    "odrl:obligation": []
  }
}
```

#### 3.2 コントラクト交渉の開始

取得したポリシーIDを使用：

```bash
POLICY_ID="Y29udHJhY3QtZGVmaW5pdGlvbg==:a2Fma2Etc3RyZWFtLWFzc2V0:NTU5YTJhYTktMmE1NC00YTRjLTgxODAtMGQyNmRkYWEzNzlk"

curl -H 'Content-Type: application/json' \
  -d '{
    "@context": {
      "@vocab": "https://w3id.org/edc/v0.0.1/ns/"
    },
    "@type": "ContractRequest",
    "counterPartyAddress": "http://localhost:18182/protocol",
    "protocol": "dataspace-protocol-http",
    "policy": {
      "@context": "http://www.w3.org/ns/odrl.jsonld",
      "@id": "'$POLICY_ID'",
      "@type": "Offer",
      "assigner": "provider",
      "target": "kafka-stream-asset"
    }
  }' \
  -X POST "http://localhost:28181/management/v3/contractnegotiations" -s | jq
```

#### 3.3 コントラクト交渉の状態確認

```bash
NEGOTIATION_ID="39fb5341-cfd9-4d74-831d-3c1a70b790fc"  # 上記で取得したID

sleep 5 && curl -s "http://localhost:28181/management/v3/contractnegotiations/request" \
  -X POST -H "Content-Type: application/json" \
  -d '{"@context": {"@vocab": "https://w3id.org/edc/v0.0.1/ns/"}, "@type": "QuerySpec"}' \
  | jq '.[] | select(.["@id"] == "'$NEGOTIATION_ID'") | {id: .["@id"], state: .state, contractAgreementId: .contractAgreementId}'
```

**期待される出力:**
```json
{
  "id": "39fb5341-cfd9-4d74-831d-3c1a70b790fc",
  "state": "FINALIZED",
  "contractAgreementId": "79e4537c-2853-40d5-80ef-117d3b4612dc"
}
```

### 手順4: データ転送の開始

#### 4.1 HTTP Request Loggerの起動

```bash
cd Samples
./gradlew util:http-request-logger:build

# バックグラウンドで起動
HTTP_SERVER_PORT=4000 java -jar util/http-request-logger/build/libs/http-request-logger.jar &
```

#### 4.2 データ転送の開始

```bash
CONTRACT_ID="79e4537c-2853-40d5-80ef-117d3b4612dc"  # 上記で取得したID

curl -H 'Content-Type: application/json' \
  -d '{
    "@context": {
      "@vocab": "https://w3id.org/edc/v0.0.1/ns/"
    },
    "@type": "TransferRequestDto",
    "connectorId": "provider",
    "counterPartyAddress": "http://localhost:18182/protocol",
    "contractId": "'$CONTRACT_ID'",
    "protocol": "dataspace-protocol-http",
    "transferType": "KafkaBroker-PULL",
    "assetId": "kafka-stream-asset",
    "dataDestination": {
      "type": "HttpProxy",
      "baseUrl": "http://localhost:4000"
    },
    "callbackAddresses": [
      {
        "uri": "http://localhost:4000",
        "events": ["transfer.process.started"]
      }
    ]
  }' \
  -X POST "http://localhost:28181/management/v3/transferprocesses" -s | jq
```

#### 4.3 転送プロセスの状態確認

```bash
TRANSFER_ID="1d7ae0cf-07aa-47e0-9abe-eeba13d9b899"  # 上記で取得したID

sleep 5 && curl -s "http://localhost:28181/management/v3/transferprocesses/request" \
  -X POST -H "Content-Type: application/json" \
  -d '{"@context": {"@vocab": "https://w3id.org/edc/v0.0.1/ns/"}, "@type": "QuerySpec"}' \
  | jq '.[] | select(.["@id"] == "'$TRANSFER_ID'") | {id: .["@id"], state: .state}'
```

**期待される出力:**
```json
{
  "id": "1d7ae0cf-07aa-47e0-9abe-eeba13d9b899",
  "state": "STARTED"
}
```

### 手順5: Kafkaメッセージのテスト

#### 5.1 Kafkaコンシューマーの起動

```bash
# バックグラウンドでコンシューマーを起動
docker exec -d kafka-kraft /bin/kafka-console-consumer --topic kafka-stream-topic \
  --bootstrap-server localhost:9093 \
  --consumer-property group.id=group_id \
  --consumer-property security.protocol=SASL_PLAINTEXT \
  --consumer-property sasl.mechanism=PLAIN \
  --consumer-property sasl.jaas.config='org.apache.kafka.common.security.plain.PlainLoginModule required username="alice" password="alice-secret";'
```

#### 5.2 テストメッセージの送信

```bash
# 単一メッセージの送信
echo "Hello from EDC Kafka Integration!" | docker exec -i kafka-kraft /bin/kafka-console-producer \
  --topic kafka-stream-topic \
  --producer.config=/config/admin.properties \
  --bootstrap-server localhost:9093

# 複数メッセージの送信
for i in {1..3}; do 
  echo "Test message $i from EDC-Kafka integration"
done | docker exec -i kafka-kraft /bin/kafka-console-producer \
  --topic kafka-stream-topic \
  --producer.config=/config/admin.properties \
  --bootstrap-server localhost:9093
```

## 🔍 技術詳細

### EDC Kafka統合エクステンション

#### KafkaExtension
- **場所**: `Samples/transfer/transfer-06-kafka-broker/kafka-runtime/src/main/java/org/eclipse/edc/samples/streaming/KafkaExtension.java`
- **機能**: `KafkaToKafkaDataFlowController`を登録

#### KafkaToKafkaDataFlowController
- **場所**: `Samples/transfer/transfer-06-kafka-broker/kafka-runtime/src/main/java/org/eclipse/edc/samples/streaming/KafkaToKafkaDataFlowController.java`
- **機能**: Kafka転送タイプを処理し、EDRトークンを生成

### データフロー

1. **アセット登録**: Kafkaトピックをアセットとして登録
2. **契約交渉**: 標準的なEDC契約交渉プロセス
3. **転送開始**: `KafkaBroker-PULL`転送タイプでEDR生成
4. **EDR配信**: HTTP Request LoggerにEDRが送信される
5. **Kafkaアクセス**: EDR内のクレデンシャルでKafkaアクセス

### セキュリティ

#### SASL認証
- **プロトコル**: SASL_PLAINTEXT
- **メカニズム**: PLAIN
- **クレデンシャル**: `alice` / `alice-secret`

#### ACL制御
- **ユーザー**: alice
- **権限**: Read
- **対象**: `kafka-stream-topic`

## 📊 重要な設定ファイル

### Kafkaアセット定義
```json
{
  "@context": { "@vocab": "https://w3id.org/edc/v0.0.1/ns/" },
  "@id": "kafka-stream-asset",
  "properties": {},
  "dataAddress": {
    "type": "Kafka",
    "kafka.bootstrap.servers": "localhost:9093",
    "topic": "kafka-stream-topic"
  }
}
```

### 転送リクエスト
```json
{
  "@context": {
    "@vocab": "https://w3id.org/edc/v0.0.1/ns/"
  },
  "@type": "TransferRequestDto",
  "transferType": "KafkaBroker-PULL",
  "assetId": "kafka-stream-asset",
  "dataDestination": {
    "type": "HttpProxy",
    "baseUrl": "http://localhost:4000"
  }
}
```

## 🚨 トラブルシューティング

### Kafka関連

#### Kafkaブローカーが起動しない
```bash
# コンテナログの確認
docker logs kafka-kraft

# ポートの確認
netstat -an | grep 9093
```

#### トピックが作成されない
```bash
# トピック一覧の確認
docker exec kafka-kraft /bin/kafka-topics --list --bootstrap-server localhost:9093
```

#### ACL設定エラー
```bash
# ACL一覧の確認
docker exec kafka-kraft /bin/kafka-acls --list --bootstrap-server localhost:9093
```

### EDC関連

#### コネクタが応答しない
```bash
# プロバイダーの確認
curl -s "http://localhost:18181/management/v3/assets/request" \
  -X POST -H "Content-Type: application/json" \
  -d '{"@context": {"@vocab": "https://w3id.org/edc/v0.0.1/ns/"}, "@type": "QuerySpec"}' | jq

# コンシューマーの確認
curl -s "http://localhost:28181/management/v3/assets/request" \
  -X POST -H "Content-Type: application/json" \
  -d '{"@context": {"@vocab": "https://w3id.org/edc/v0.0.1/ns/"}, "@type": "QuerySpec"}' | jq
```

#### 契約交渉が失敗する
```bash
# 交渉状態の確認
curl -s "http://localhost:28181/management/v3/contractnegotiations/request" \
  -X POST -H "Content-Type: application/json" \
  -d '{"@context": {"@vocab": "https://w3id.org/edc/v0.0.1/ns/"}, "@type": "QuerySpec"}' \
  | jq '.[] | {id: .["@id"], state: .state, errorDetail: .errorDetail}'
```

#### 転送プロセスが開始しない
```bash
# 転送プロセス状態の確認
curl -s "http://localhost:28181/management/v3/transferprocesses/request" \
  -X POST -H "Content-Type: application/json" \
  -d '{"@context": {"@vocab": "https://w3id.org/edc/v0.0.1/ns/"}, "@type": "QuerySpec"}' \
  | jq '.[] | {id: .["@id"], state: .state, errorDetail: .errorDetail}'
```

### HTTP Request Logger関連

#### HTTP Request Loggerが起動しない
```bash
# JARファイルの存在確認
ls -la Samples/util/http-request-logger/build/libs/

# 再ビルド
cd Samples
./gradlew util:http-request-logger:build
```

#### ポート4000が使用中
```bash
# ポート使用状況の確認
lsof -i :4000

# 別のポートを使用
HTTP_SERVER_PORT=4001 java -jar util/http-request-logger/build/libs/http-request-logger.jar &
```

## 🧪 検証方法

### 1. Kafkaブローカーの動作確認
```bash
# ブローカー情報の確認
docker exec kafka-kraft /bin/kafka-broker-api-versions --bootstrap-server localhost:9093
```

### 2. EDCリソースの確認
```bash
# アセット数の確認
curl -s "http://localhost:18181/management/v3/assets/request" \
  -X POST -H "Content-Type: application/json" \
  -d '{"@context": {"@vocab": "https://w3id.org/edc/v0.0.1/ns/"}, "@type": "QuerySpec"}' \
  | jq 'length'

# ポリシー数の確認
curl -s "http://localhost:18181/management/v3/policydefinitions/request" \
  -X POST -H "Content-Type: application/json" \
  -d '{"@context": {"@vocab": "https://w3id.org/edc/v0.0.1/ns/"}, "@type": "QuerySpec"}' \
  | jq 'length'

# コントラクト定義数の確認
curl -s "http://localhost:18181/management/v3/contractdefinitions/request" \
  -X POST -H "Content-Type: application/json" \
  -d '{"@context": {"@vocab": "https://w3id.org/edc/v0.0.1/ns/"}, "@type": "QuerySpec"}' \
  | jq 'length'
```

### 3. エンドツーエンドテスト
```bash
# メッセージ送信とコンシューマー確認を同時実行
echo "End-to-end test message" | docker exec -i kafka-kraft /bin/kafka-console-producer \
  --topic kafka-stream-topic \
  --producer.config=/config/admin.properties \
  --bootstrap-server localhost:9093 &

docker exec kafka-kraft /bin/kafka-console-consumer --topic kafka-stream-topic \
  --bootstrap-server localhost:9093 \
  --consumer-property group.id=test_group \
  --consumer-property security.protocol=SASL_PLAINTEXT \
  --consumer-property sasl.mechanism=PLAIN \
  --consumer-property sasl.jaas.config='org.apache.kafka.common.security.plain.PlainLoginModule required username="alice" password="alice-secret";' \
  --from-beginning --max-messages 1
```

## 📚 参考情報

### EDC関連
- [Eclipse Data Connector Documentation](https://eclipse-edc.github.io/docs/)
- [EDC Samples Repository](https://github.com/eclipse-edc/Samples)

### Kafka関連
- [Apache Kafka Documentation](https://kafka.apache.org/documentation/)
- [Kafka KRaft Mode](https://kafka.apache.org/documentation/#kraft)
- [Kafka Security](https://kafka.apache.org/documentation/#security)

### 関連ファイル
- `Samples/transfer/transfer-06-kafka-broker/README.md`
- `Samples/transfer/transfer-06-kafka-broker/kafka-runtime/build.gradle.kts`
- `Samples/transfer/transfer-06-kafka-broker/kafka.env`
- `Samples/transfer/transfer-06-kafka-broker/kafka-config/admin.properties`

## 🎯 次のステップ

1. **プロダクション環境への適用**
   - セキュリティ設定の強化
   - 高可用性構成の検討
   - 監視・ログ設定

2. **高度な機能の実装**
   - カスタムポリシーの実装
   - 複数トピックの管理
   - ストリーミングデータの変換

3. **統合テストの自動化**
   - CI/CDパイプラインの構築
   - パフォーマンステストの実装

---

**📝 作成日**: 2025-08-19  
**📖 バージョン**: 1.0  
**�� 最終更新**: 2025-08-19 