# EDC SPARQL統合ガイド
## transfer-03-consumer-pull + SPARQL エンドポイント対応プロキシ

### 📋 概要
このガイドでは、Eclipse Data Connector (EDC) の `transfer-03-consumer-pull` サンプルをベースに、SPARQLエンドポイントに対応したカスタムHTTPプロキシを実装し、完全なエンドツーエンドのデータ転送を実現する手順を説明します。

### 🛠️ 前提条件
- Java 17以上
- Apache Jena Fuseki (SPARQLエンドポイント)
- curl, jq コマンド
- ポート 19193, 19194, 19291, 29193, 3030 が利用可能

---

## 🚀 手順1: プロジェクトの準備

### 1.1 作業ディレクトリへの移動
```bash
cd /Users/mats21/edc-poc/Samples
```

### 1.2 必要コンポーネントのビルド
```bash
# 前提条件コネクタのビルド
./gradlew transfer:transfer-00-prerequisites:connector:build

# カスタムプロキシデータプレーンのビルド
./gradlew transfer:transfer-03-consumer-pull:provider-proxy-data-plane:build
```

---

## 🏗️ 手順2: SPARQLエンドポイントの準備

### 2.1 Apache Jena Fusekiの起動
```bash
# Fusekiサーバーを起動 (別ターミナル)
# http://localhost:3030/battery_dataset/query でアクセス可能にする
```

### 2.2 SPARQLエンドポイントの動作確認
```bash
curl -X POST \
  -H "Content-Type: application/sparql-query" \
  --data 'SELECT ?subject ?predicate ?object
          WHERE {
            ?subject ?predicate ?object
          }
          LIMIT 3' \
  http://localhost:3030/battery_dataset/query
```

---

## ⚡ 手順3: EDCコネクタの起動

### 3.1 コンシューマーコネクタの起動
```bash
# ターミナル1
java -Dedc.fs.config=transfer/transfer-00-prerequisites/resources/configuration/consumer-configuration.properties \
     -jar transfer/transfer-00-prerequisites/connector/build/libs/connector.jar
```

### 3.2 プロバイダーコネクタ（カスタムプロキシ）の起動
```bash
# ターミナル2
java -Dedc.fs.config=transfer/transfer-03-consumer-pull/resources/configuration/provider.properties \
     -jar transfer/transfer-03-consumer-pull/provider-proxy-data-plane/build/libs/connector.jar
```

### 3.3 起動確認
```bash
# コンシューマーのヘルスチェック
curl -s "http://localhost:29193/api/check/health" | jq .

# プロバイダーのヘルスチェック  
curl -s "http://localhost:19193/api/check/health" | jq .
```

---

## 📊 手順4: データセットとポリシーの登録

### 4.1 バッテリーデータセットアセットの作成
```bash
# battery-dataset-asset-fixed.json
curl -X POST "http://localhost:19193/management/v3/assets" \
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
         "baseUrl": "http://localhost:3030/battery_dataset/query",
         "proxyPath": "false",
         "method": "POST",
         "contentType": "application/x-www-form-urlencoded"
       }
     }'
```

### 4.2 アクセスポリシーの作成
```bash
curl -X POST "http://localhost:19193/management/v3/policydefinitions" \
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
     }'
```

### 4.3 コントラクト定義の作成
```bash
curl -X POST "http://localhost:19193/management/v3/contractdefinitions" \
     -H "Content-Type: application/json" \
     -d '{
       "@context": { "@vocab": "https://w3id.org/edc/v0.0.1/ns/" },
       "@id": "universalContractDef",
       "accessPolicyId": "aPolicy",
       "contractPolicyId": "aPolicy",
       "assetsSelector": []
     }'
```

---

## 🤝 手順5: コントラクト交渉とデータ転送

### 5.1 カタログの確認
```bash
curl -X POST "http://localhost:29193/management/v3/catalog/request" \
     -H "Content-Type: application/json" \
     -d '{
       "@context": { "@vocab": "https://w3id.org/edc/v0.0.1/ns/" },
       "counterPartyAddress": "http://localhost:19194/protocol",
       "protocol": "dataspace-protocol-http"
     }' | jq .
```

### 5.2 オファーIDの取得
```bash
OFFER_ID=$(curl -X POST "http://localhost:29193/management/v3/catalog/request" \
     -H "Content-Type: application/json" \
     -d '{
       "@context": { "@vocab": "https://w3id.org/edc/v0.0.1/ns/" },
       "counterPartyAddress": "http://localhost:19194/protocol",
       "protocol": "dataspace-protocol-http"
     }' -s | jq -r '."dcat:dataset"[] | select(.["@id"] == "batteryDatasetFixed") | ."odrl:hasPolicy"."@id"')

echo "Offer ID: $OFFER_ID"
```

### 5.3 コントラクト交渉の開始
```bash
NEGOTIATION_ID=$(curl -X POST "http://localhost:29193/management/v3/contractnegotiations" \
     -H "Content-Type: application/json" \
     -d "{
       \"@context\": {
         \"@vocab\": \"https://w3id.org/edc/v0.0.1/ns/\"
       },
       \"@type\": \"ContractRequest\",
       \"counterPartyAddress\": \"http://localhost:19194/protocol\",
       \"protocol\": \"dataspace-protocol-http\",
       \"policy\": {
         \"@context\": \"http://www.w3.org/ns/odrl.jsonld\",
         \"@id\": \"$OFFER_ID\",
         \"@type\": \"Offer\",
         \"assigner\": \"provider\",
         \"target\": \"batteryDatasetFixed\"
       }
     }" -s | jq -r '.["@id"]')

echo "Negotiation ID: $NEGOTIATION_ID"
```

### 5.4 交渉完了の確認
```bash
# 5秒待機後に状態確認
sleep 5
CONTRACT_AGREEMENT_ID=$(curl -s "http://localhost:29193/management/v3/contractnegotiations/$NEGOTIATION_ID" | jq -r '.contractAgreementId')

echo "Contract Agreement ID: $CONTRACT_AGREEMENT_ID"
```

### 5.5 データ転送の開始
```bash
TRANSFER_ID=$(curl -X POST "http://localhost:29193/management/v3/transferprocesses" \
     -H "Content-Type: application/json" \
     -d "{
       \"@context\": {
         \"@vocab\": \"https://w3id.org/edc/v0.0.1/ns/\"
       },
       \"@type\": \"TransferRequestDto\",
       \"connectorId\": \"provider\",
       \"counterPartyAddress\": \"http://localhost:19194/protocol\",
       \"contractId\": \"$CONTRACT_AGREEMENT_ID\",
       \"protocol\": \"dataspace-protocol-http\",
       \"transferType\": \"HttpData-PULL\",
       \"assetId\": \"batteryDatasetFixed\"
     }" -s | jq -r '.["@id"]')

echo "Transfer ID: $TRANSFER_ID"
```

### 5.6 EDRトークンの取得
```bash
# 5秒待機後にEDRトークン取得
sleep 5
EDR_TOKEN=$(curl -s "http://localhost:29193/management/v3/edrs/$TRANSFER_ID/dataaddress" | jq -r '.authorization')

echo "EDR Token: $EDR_TOKEN"
```

---

## 🎯 手順6: SPARQLクエリの実行

### 6.1 基本的なSPARQLクエリ
```bash
curl -X POST "http://localhost:19291/public/" \
  -H "Authorization: $EDR_TOKEN" \
  -H "Content-Type: application/sparql-query" \
  --data 'SELECT ?subject ?predicate ?object WHERE { ?subject ?predicate ?object } LIMIT 3' \
  -s | jq .
```

### 6.2 フォームデータ形式でのクエリ
```bash
curl -X POST "http://localhost:19291/public/" \
  -H "Authorization: $EDR_TOKEN" \
  -H "Content-Type: application/x-www-form-urlencoded" \
  --data 'query=SELECT ?subject ?predicate ?object WHERE { ?subject ?predicate ?object } LIMIT 5' \
  -s | jq .
```

### 6.3 バッテリー特有のクエリ例
```bash
curl -X POST "http://localhost:19291/public/" \
  -H "Authorization: $EDR_TOKEN" \
  -H "Content-Type: application/sparql-query" \
  --data 'SELECT ?battery ?stateOfHealth WHERE {
    ?battery <http://example.org/battery/stateOfHealth> ?stateOfHealth .
    FILTER(?stateOfHealth > 90)
  }' \
  -s | jq .
```

---

## 🔧 トラブルシューティング

### よくある問題と解決策

#### 1. 405 Method Not Allowed エラー
**原因**: プロキシの実装問題またはSPARQLエンドポイントの問題
**解決策**: 
- プロバイダーの再ビルドと再起動
- SPARQLエンドポイントの動作確認

#### 2. 403 Forbidden エラー
**原因**: EDRトークンの期限切れまたは無効
**解決策**: 
- 新しいコントラクト交渉の実行
- 新しいEDRトークンの取得

#### 3. 404 Not Found エラー
**原因**: コントラクトアグリーメントが見つからない
**解決策**: 
- プロバイダーの再起動後にリソースを再作成
- アセット、ポリシー、コントラクト定義の再登録

#### 4. コネクタが起動しない
**原因**: ポートの競合またはビルドエラー
**解決策**: 
- 使用ポートの確認 (19193, 19194, 19291, 29193)
- 依存関係の再ビルド

---

## 📁 ファイル構成

### 作成されるファイル
```
Samples/
├── battery-dataset-asset-fixed.json      # バッテリーデータセット定義
├── battery-contract-negotiation-fixed.json # コントラクト交渉リクエスト
├── battery-transfer-request-fixed.json   # データ転送リクエスト
├── deletion-policy-example.json          # 削除ポリシー例
├── check-deletion-obligations.sh         # 削除義務確認スクリプト
└── EDC-SPARQL-Integration-Guide.md      # このガイド
```

### 重要な設定ファイル
- `transfer/transfer-03-consumer-pull/resources/configuration/provider.properties`
- `transfer/transfer-00-prerequisites/resources/configuration/consumer-configuration.properties`

---

## 🎉 完了確認

全ての手順が正常に完了すると、以下が実現されます：

1. ✅ EDCコネクタが正常に起動
2. ✅ SPARQLエンドポイントへの接続
3. ✅ コントラクト交渉の成功
4. ✅ データ転送プロセスの完了
5. ✅ EDRトークンの取得
6. ✅ プロキシ経由でのSPARQLクエリ実行

### 成功時のレスポンス例
```json
{
  "head": {
    "vars": ["subject", "predicate", "object"]
  },
  "results": {
    "bindings": [
      {
        "subject": { "type": "uri", "value": "http://example.org/battery/BAT-01" },
        "predicate": { "type": "uri", "value": "http://example.org/battery/stateOfHealth" },
        "object": { "type": "literal", "datatype": "http://www.w3.org/2001/XMLSchema#decimal", "value": "92.1" }
      }
    ]
  }
}
```

---

## 📚 参考情報

### 技術仕様
- **EDCバージョン**: Eclipse Data Connector
- **プロトコル**: Dataspace Protocol HTTP
- **認証**: EDR (EndpointDataReference) トークン
- **データ転送**: Consumer Pull パターン
- **SPARQLバージョン**: 1.1

### 関連ドキュメント
- Eclipse Data Connector Documentation
- Dataspace Protocol Specification
- SPARQL 1.1 Query Language
- Apache Jena Fuseki Documentation 