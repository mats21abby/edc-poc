# EDC SPARQL統合 クイックリファレンス

## 🚀 クイックスタート

### 1. ビルド
```bash
./gradlew transfer:transfer-00-prerequisites:connector:build
./gradlew transfer:transfer-03-consumer-pull:provider-proxy-data-plane:build
```

### 2. コネクタ起動
```bash
# ターミナル1: コンシューマー
java -Dedc.fs.config=transfer/transfer-00-prerequisites/resources/configuration/consumer-configuration.properties -jar transfer/transfer-00-prerequisites/connector/build/libs/connector.jar

# ターミナル2: プロバイダー
java -Dedc.fs.config=transfer/transfer-03-consumer-pull/resources/configuration/provider.properties -jar transfer/transfer-03-consumer-pull/provider-proxy-data-plane/build/libs/connector.jar
```

### 3. 自動セットアップ
```bash
./setup-edc-sparql.sh
```

---

## 📊 重要なエンドポイント

| コンポーネント | エンドポイント | 用途 |
|---------------|--------------|------|
| コンシューマー管理 | http://localhost:29193/management/v3 | カタログ、交渉、転送 |
| プロバイダー管理 | http://localhost:19193/management/v3 | アセット、ポリシー管理 |
| プロバイダープロトコル | http://localhost:19194/protocol | データスペース通信 |
| プロキシ | http://localhost:19291/public/ | データアクセス |
| SPARQL | http://localhost:3030/battery_dataset/query | データソース |

---

## 🔧 基本コマンド

### リソース作成
```bash
# アセット作成
curl -X POST "http://localhost:19193/management/v3/assets" -H "Content-Type: application/json" -d @battery-dataset-asset-fixed.json

# ポリシー作成  
curl -X POST "http://localhost:19193/management/v3/policydefinitions" -H "Content-Type: application/json" -d @transfer/transfer-01-negotiation/resources/create-policy.json

# コントラクト定義作成
curl -X POST "http://localhost:19193/management/v3/contractdefinitions" -H "Content-Type: application/json" -d @universal-contract-definition.json
```

### コントラクト交渉
```bash
# カタログ取得
curl -X POST "http://localhost:29193/management/v3/catalog/request" -H "Content-Type: application/json" -d @transfer/transfer-01-negotiation/resources/fetch-catalog.json

# 交渉開始
curl -X POST "http://localhost:29193/management/v3/contractnegotiations" -H "Content-Type: application/json" -d @battery-contract-negotiation-fixed.json

# データ転送開始
curl -X POST "http://localhost:29193/management/v3/transferprocesses" -H "Content-Type: application/json" -d @battery-transfer-request-fixed.json
```

### SPARQLクエリ
```bash
# 基本クエリ
curl -X POST "http://localhost:19291/public/" \
  -H "Authorization: $EDR_TOKEN" \
  -H "Content-Type: application/sparql-query" \
  --data 'SELECT ?s ?p ?o WHERE { ?s ?p ?o } LIMIT 5'

# フォーム形式
curl -X POST "http://localhost:19291/public/" \
  -H "Authorization: $EDR_TOKEN" \
  -H "Content-Type: application/x-www-form-urlencoded" \
  --data 'query=SELECT ?s ?p ?o WHERE { ?s ?p ?o } LIMIT 5'
```

---

## 🐛 トラブルシューティング

### よくあるエラー

| エラー | 原因 | 解決策 |
|--------|------|--------|
| 405 Method Not Allowed | プロキシ実装問題 | プロバイダー再起動 |
| 403 Forbidden | EDRトークン期限切れ | 新規交渉実行 |
| 404 Not Found | リソース未作成 | アセット等再作成 |
| Connection refused | コネクタ未起動 | コネクタ起動確認 |

### ステータス確認
```bash
# コネクタヘルスチェック
curl -s "http://localhost:19193/api/check/health" | jq .
curl -s "http://localhost:29193/api/check/health" | jq .

# 交渉状態確認
curl -s "http://localhost:29193/management/v3/contractnegotiations/$NEGOTIATION_ID" | jq '{state: .state, contractAgreementId: .contractAgreementId}'

# 転送状態確認  
curl -s "http://localhost:29193/management/v3/transferprocesses/$TRANSFER_ID" | jq '{state: .state}'
```

---

## 📝 サンプルクエリ

### バッテリーデータ用SPARQL
```sparql
# 全データ取得
SELECT ?subject ?predicate ?object 
WHERE { ?subject ?predicate ?object } 
LIMIT 10

# バッテリー健康状態
SELECT ?battery ?stateOfHealth 
WHERE {
  ?battery <http://example.org/battery/stateOfHealth> ?stateOfHealth .
  FILTER(?stateOfHealth > 90)
}

# 日付フィルター
SELECT ?battery ?resultTime 
WHERE {
  ?battery <http://www.w3.org/ns/sosa/resultTime> ?resultTime .
  FILTER(?resultTime >= "2025-01-01"^^xsd:date)
}
```

---

## 🔄 リセット手順

### 完全リセット
```bash
# 1. コネクタ停止 (Ctrl+C)
# 2. プロセス確認・停止
ps aux | grep java
kill -9 <PID>

# 3. 再ビルド
./gradlew clean build

# 4. 再起動
# コネクタを再起動

# 5. リソース再作成
./setup-edc-sparql.sh
```

---

## 📚 ファイル一覧

### 設定ファイル
- `transfer/transfer-03-consumer-pull/resources/configuration/provider.properties`
- `transfer/transfer-00-prerequisites/resources/configuration/consumer-configuration.properties`

### データファイル
- `battery-dataset-asset-fixed.json` - アセット定義
- `battery-contract-negotiation-fixed.json` - 交渉リクエスト
- `battery-transfer-request-fixed.json` - 転送リクエスト
- `universal-contract-definition.json` - コントラクト定義

### スクリプト
- `setup-edc-sparql.sh` - 自動セットアップ
- `check-deletion-obligations.sh` - 削除義務確認

### ドキュメント
- `EDC-SPARQL-Integration-Guide.md` - 詳細ガイド
- `QUICK-REFERENCE.md` - このファイル 