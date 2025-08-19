# EDC Kafka統合 クイックリファレンス

## 🚀 クイックスタート

### 自動セットアップ
```bash
cd Samples
./setup-edc-kafka.sh
```

### 手動セットアップ（主要コマンド）
```bash
# 1. Kafkaブローカー起動
docker run --rm --name=kafka-kraft -h kafka-kraft -p 9093:9093 \
    -v "$PWD/Samples/transfer/transfer-06-kafka-broker/kafka-config":/config \
    --env-file Samples/transfer/transfer-06-kafka-broker/kafka.env \
    [その他の環境変数...] \
    confluentinc/cp-kafka:7.5.2

# 2. アセット作成
curl -H 'Content-Type: application/json' \
  -d '{"@context": {"@vocab": "https://w3id.org/edc/v0.0.1/ns/"}, "@id": "kafka-stream-asset", "properties": {}, "dataAddress": {"type": "Kafka", "kafka.bootstrap.servers": "localhost:9093", "topic": "kafka-stream-topic"}}' \
  -X POST "http://localhost:18181/management/v3/assets"

# 3. ポリシー作成
curl -H 'Content-Type: application/json' -d @transfer/transfer-06-kafka-broker/2-policy-definition.json \
  -X POST "http://localhost:18181/management/v3/policydefinitions"

# 4. コントラクト定義作成
curl -H 'Content-Type: application/json' -d @transfer/transfer-06-kafka-broker/3-contract-definition.json \
  -X POST "http://localhost:18181/management/v3/contractdefinitions"
```

### クリーンアップ
```bash
cd Samples
./cleanup-edc-kafka.sh
```

## 📊 主要エンドポイント

| コンポーネント | ポート | 用途 |
|---|---|---|
| プロバイダー管理API | 18181 | リソース管理 |
| プロバイダープロトコル | 18182 | データスペース通信 |
| コンシューマー管理API | 28181 | リソース管理 |
| コンシューマープロトコル | 28182 | データスペース通信 |
| Kafkaブローカー | 9093 | メッセージング |
| HTTP Request Logger | 4000 | EDR受信 |

## 🔍 確認コマンド

### EDCリソースの確認
```bash
# アセット一覧
curl -s "http://localhost:18181/management/v3/assets/request" \
  -X POST -H "Content-Type: application/json" \
  -d '{"@context": {"@vocab": "https://w3id.org/edc/v0.0.1/ns/"}, "@type": "QuerySpec"}' | jq

# ポリシー一覧
curl -s "http://localhost:18181/management/v3/policydefinitions/request" \
  -X POST -H "Content-Type: application/json" \
  -d '{"@context": {"@vocab": "https://w3id.org/edc/v0.0.1/ns/"}, "@type": "QuerySpec"}' | jq

# 転送プロセス状態
curl -s "http://localhost:28181/management/v3/transferprocesses/request" \
  -X POST -H "Content-Type: application/json" \
  -d '{"@context": {"@vocab": "https://w3id.org/edc/v0.0.1/ns/"}, "@type": "QuerySpec"}' | jq
```

### Kafkaの確認
```bash
# トピック一覧
docker exec kafka-kraft /bin/kafka-topics --list --bootstrap-server localhost:9093

# ACL一覧
docker exec kafka-kraft /bin/kafka-acls --list --bootstrap-server localhost:9093

# メッセージ送信
echo "テストメッセージ" | docker exec -i kafka-kraft /bin/kafka-console-producer \
  --topic kafka-stream-topic --producer.config=/config/admin.properties --bootstrap-server localhost:9093

# メッセージ受信
docker exec kafka-kraft /bin/kafka-console-consumer --topic kafka-stream-topic \
  --bootstrap-server localhost:9093 --consumer-property group.id=test_group \
  --consumer-property security.protocol=SASL_PLAINTEXT --consumer-property sasl.mechanism=PLAIN \
  --consumer-property sasl.jaas.config='org.apache.kafka.common.security.plain.PlainLoginModule required username="alice" password="alice-secret";' \
  --from-beginning --max-messages 5
```

## 🏗️ 重要なファイル

### 設定ファイル
- `transfer/transfer-06-kafka-broker/kafka.env` - Kafka環境変数
- `transfer/transfer-06-kafka-broker/kafka-config/admin.properties` - Kafka管理者設定
- `transfer/transfer-06-kafka-broker/2-policy-definition.json` - ポリシー定義
- `transfer/transfer-06-kafka-broker/3-contract-definition.json` - コントラクト定義
- `transfer/transfer-06-kafka-broker/4-get-dataset.json` - カタログ取得

### Javaファイル
- `transfer/transfer-06-kafka-broker/kafka-runtime/src/main/java/org/eclipse/edc/samples/streaming/KafkaExtension.java`
- `transfer/transfer-06-kafka-broker/kafka-runtime/src/main/java/org/eclipse/edc/samples/streaming/KafkaToKafkaDataFlowController.java`

### スクリプト
- `setup-edc-kafka.sh` - 自動セットアップ
- `cleanup-edc-kafka.sh` - 自動クリーンアップ

## 🔧 トラブルシューティング

### よくある問題

#### Kafkaブローカーが起動しない
```bash
# ログ確認
docker logs kafka-kraft

# ポート確認
netstat -an | grep 9093
```

#### EDCコネクタが応答しない
```bash
# ヘルスチェック
curl -s "http://localhost:18181/management/v3/assets/request" \
  -X POST -H "Content-Type: application/json" \
  -d '{"@context": {"@vocab": "https://w3id.org/edc/v0.0.1/ns/"}, "@type": "QuerySpec"}' > /dev/null && echo "OK" || echo "NG"
```

#### 契約交渉が失敗する
```bash
# 交渉状態確認
curl -s "http://localhost:28181/management/v3/contractnegotiations/request" \
  -X POST -H "Content-Type: application/json" \
  -d '{"@context": {"@vocab": "https://w3id.org/edc/v0.0.1/ns/"}, "@type": "QuerySpec"}' \
  | jq '.[] | {id: .["@id"], state: .state, errorDetail: .errorDetail}'
```

### エラーコード

| HTTPコード | 意味 | 対処法 |
|---|---|---|
| 200/204 | 成功 | - |
| 400 | リクエスト不正 | JSON形式・必須フィールドを確認 |
| 404 | リソース未発見 | IDを確認 |
| 409 | 競合 | 既存リソースとの重複を確認 |
| 500 | サーバーエラー | ログを確認 |

## 📚 リンク集

### ドキュメント
- [EDC Kafka統合ガイド](./EDC-Kafka-Integration-Guide.md) - 詳細ガイド
- [EDC SPARQL統合ガイド](./EDC-SPARQL-Integration-Guide.md) - SPARQL統合の参考
- [EDC ポリシー定義ガイド](./EDC-Policy-Definition-Guide.md) - ポリシー詳細

### 外部リンク
- [Eclipse Data Connector](https://eclipse-edc.github.io/docs/)
- [Apache Kafka](https://kafka.apache.org/documentation/)
- [Kafka KRaft Mode](https://kafka.apache.org/documentation/#kraft)

## 🎯 次のステップ

### 基本機能の拡張
1. **複数トピックの管理**
2. **カスタムポリシーの実装**
3. **監視・ログ機能の追加**

### プロダクション対応
1. **セキュリティ強化**（SSL/TLS、OAuth2）
2. **高可用性構成**（複数ブローカー、レプリケーション）
3. **パフォーマンス最適化**

### 統合・自動化
1. **CI/CDパイプライン**
2. **自動テスト**
3. **運用監視**

---

**📝 最終更新**: 2025-08-19  
**🔄 バージョン**: 1.0 