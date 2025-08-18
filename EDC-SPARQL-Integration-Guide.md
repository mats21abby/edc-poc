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
# 管理APIの動作確認（プロバイダー）
curl -s "http://localhost:19193/management/v3/assets/request" \
  -X POST -H "Content-Type: application/json" \
  -d '{"@context": {"@vocab": "https://w3id.org/edc/v0.0.1/ns/"}, "@type": "QuerySpec"}' \
  | jq 'length'

# 管理APIの動作確認（コンシューマー）  
curl -s "http://localhost:29193/management/v3/catalog/request" \
  -X POST -H "Content-Type: application/json" \
  -d '{"@context": {"@vocab": "https://w3id.org/edc/v0.0.1/ns/"}, "counterPartyAddress": "http://localhost:19194/protocol", "protocol": "dataspace-protocol-http"}' \
  | jq '."dcat:dataset" | length'
```

---

## 📊 手順4: データセットとポリシーの登録

**⚡ 自動化オプション**: 手順4-6を自動実行したい場合は、以下のスクリプトを使用できます：
```bash
./setup-edc-sparql.sh
```
以下は手動実行の手順です。

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
# EDCサンプルのポリシーファイルを使用
curl -X POST "http://localhost:19193/management/v3/policydefinitions" \
     -H "Content-Type: application/json" \
     -d @transfer/transfer-01-negotiation/resources/create-policy.json

# または、直接JSON指定
curl -X POST "http://localhost:19193/management/v3/policydefinitions" \
     -H "Content-Type: application/json" \
     -d '{
       "@context": {
         "@vocab": "https://w3id.org/edc/v0.0.1/ns/",
         "odrl": "http://www.w3.org/ns/odrl/2/"
       },
       "@id": "aPolicy",
       "policy": {
         "@context": "http://www.w3.org/ns/odrl.jsonld",
         "@type": "Set",
         "permission": [],
         "prohibition": [],
         "obligation": []
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
# カタログにアセットが表示されることを確認
curl -X POST "http://localhost:29193/management/v3/catalog/request" \
     -H "Content-Type: application/json" \
     -d '{
       "@context": { "@vocab": "https://w3id.org/edc/v0.0.1/ns/" },
       "counterPartyAddress": "http://localhost:19194/protocol",
       "protocol": "dataspace-protocol-http"
     }' | jq '."dcat:dataset"'

# アセットが表示されない場合は、以下を確認：
# 1. アセットが登録されているか
curl -s "http://localhost:19193/management/v3/assets/request" \
  -X POST -H "Content-Type: application/json" \
  -d '{"@context": {"@vocab": "https://w3id.org/edc/v0.0.1/ns/"}, "@type": "QuerySpec"}' | jq .

# 2. ポリシーが登録されているか  
curl -s "http://localhost:19193/management/v3/policydefinitions/request" \
  -X POST -H "Content-Type: application/json" \
  -d '{"@context": {"@vocab": "https://w3id.org/edc/v0.0.1/ns/"}, "@type": "QuerySpec"}' | jq .

# 3. コントラクト定義が登録されているか
curl -s "http://localhost:19193/management/v3/contractdefinitions/request" \
  -X POST -H "Content-Type: application/json" \
  -d '{"@context": {"@vocab": "https://w3id.org/edc/v0.0.1/ns/"}, "@type": "QuerySpec"}' | jq .
```

### 5.2 オファーIDの取得
```bash
# カタログからオファーIDを取得（アセットが表示されていることを前提）
OFFER_ID=$(curl -X POST "http://localhost:29193/management/v3/catalog/request" \
     -H "Content-Type: application/json" \
     -d '{
       "@context": { "@vocab": "https://w3id.org/edc/v0.0.1/ns/" },
       "counterPartyAddress": "http://localhost:19194/protocol",
       "protocol": "dataspace-protocol-http"
     }' -s | jq -r '."dcat:dataset" | ."odrl:hasPolicy"."@id"')

echo "Offer ID: $OFFER_ID"

# オファーIDが取得できない場合は、カタログを直接確認
curl -X POST "http://localhost:29193/management/v3/catalog/request" \
     -H "Content-Type: application/json" \
     -d '{
       "@context": { "@vocab": "https://w3id.org/edc/v0.0.1/ns/" },
       "counterPartyAddress": "http://localhost:19194/protocol",
       "protocol": "dataspace-protocol-http"
     }' | jq .
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

# 正しい方法：交渉一覧から該当する交渉を検索
CONTRACT_AGREEMENT_ID=$(curl -s "http://localhost:29193/management/v3/contractnegotiations/request" \
  -X POST -H "Content-Type: application/json" \
  -d '{"@context": {"@vocab": "https://w3id.org/edc/v0.0.1/ns/"}, "@type": "QuerySpec"}' \
  | jq -r ".[] | select(.\"@id\" == \"$NEGOTIATION_ID\") | .contractAgreementId")

echo "Contract Agreement ID: $CONTRACT_AGREEMENT_ID"

# 交渉状態も同時に確認
NEGOTIATION_STATE=$(curl -s "http://localhost:29193/management/v3/contractnegotiations/request" \
  -X POST -H "Content-Type: application/json" \
  -d '{"@context": {"@vocab": "https://w3id.org/edc/v0.0.1/ns/"}, "@type": "QuerySpec"}' \
  | jq -r ".[] | select(.\"@id\" == \"$NEGOTIATION_ID\") | .state")

echo "Negotiation State: $NEGOTIATION_STATE"

# 交渉が完了していない場合は待機
if [ "$NEGOTIATION_STATE" != "FINALIZED" ]; then
  echo "交渉がまだ完了していません。しばらく待ってから再実行してください。"
  exit 1
fi
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



#### 1. カタログが空 / オファーIDが取得できない
**原因**: ポリシー定義が存在しない、またはコントラクト定義の参照エラー
**解決策**: 
- ポリシー定義の確認: `curl -s "http://localhost:19193/management/v3/policydefinitions/request" -X POST -H "Content-Type: application/json" -d '{"@context": {"@vocab": "https://w3id.org/edc/v0.0.1/ns/"}, "@type": "QuerySpec"}' | jq .`
- 不足している場合は `aPolicy` を作成: `curl -X POST "http://localhost:19193/management/v3/policydefinitions" -H "Content-Type: application/json" -d @transfer/transfer-01-negotiation/resources/create-policy.json`

#### 2. 管理APIが404を返す
**原因**: EDCにはデフォルトでヘルスチェックエンドポイントが存在しない
**解決策**: 
- 管理APIエンドポイント（`/management/v3/assets/request` など）で動作確認
- 404は正常な動作です

#### 3. 管理APIが405 Method Not Allowedを返す
**原因**: EDC管理APIは個別リソースへの直接アクセス（`/resource/{id}`）を許可しない
**解決策**: 
- ❌ 間違い: `curl "http://localhost:29193/management/v3/contractnegotiations/{id}"`
- ✅ 正しい: `curl -X POST "http://localhost:29193/management/v3/contractnegotiations/request" -d '{"@type": "QuerySpec"}' | jq ".[] | select(.\"@id\" == \"{id}\")"`
- 全ての管理APIリソースは `/request` エンドポイントから検索する

#### 4. 405 Method Not Allowed エラー
**原因**: プロキシの実装問題またはSPARQLエンドポイントの問題
**解決策**: 
- プロバイダーの再ビルドと再起動
- SPARQLエンドポイントの動作確認

#### 5. 403 Forbidden エラー
**原因**: EDRトークンの期限切れまたは無効
**解決策**: 
- 新しいコントラクト交渉の実行
- 新しいEDRトークンの取得

#### 6. 404 Not Found エラー
**原因**: コントラクトアグリーメントが見つからない
**解決策**: 
- プロバイダーの再起動後にリソースを再作成
- アセット、ポリシー、コントラクト定義の再登録

#### 7. リソース削除時の依存関係エラー
**エラー**: `Asset cannot be deleted as it is referenced by at least one contract agreement or an ongoing negotiation`
**原因**: アセットが契約合意や進行中の交渉で参照されている
**解決策**: 
- 参照しているコントラクト定義を先に削除
- アクティブな転送プロセスの終了
- プロバイダーコネクタの再起動（インメモリストレージの場合）

#### 8. コネクタが起動しない
**原因**: ポートの競合またはビルドエラー
**解決策**: 
- 使用ポートの確認 (19193, 19194, 19291, 29193)
- 依存関係の再ビルド

---

## 📁 ファイル構成

### 作成されるファイル
```
Samples/
├── battery-dataset-asset-fixed.json          # バッテリーデータセット定義
├── battery-contract-negotiation-fixed.json   # コントラクト交渉リクエスト
├── battery-transfer-request-fixed.json       # データ転送リクエスト
├── universal-contract-definition.json        # ユニバーサルコントラクト定義
├── setup-edc-sparql.sh                      # 自動セットアップスクリプト
├── cleanup-edc-resources.sh                 # リソースクリーンアップスクリプト
├── EDC-SPARQL-Integration-Guide.md          # このガイド
└── QUICK-REFERENCE.md                       # クイックリファレンス
```

### 重要な設定ファイル
- `transfer/transfer-03-consumer-pull/resources/configuration/provider.properties`
- `transfer/transfer-00-prerequisites/resources/configuration/consumer-configuration.properties`
- `transfer/transfer-01-negotiation/resources/create-policy.json` - aPolicyの定義

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

---

## 🗑️ 手順7: リソースの削除

### 7.1 アセットの削除

#### **⚠️ 依存関係エラーの対処**
アセット削除時に以下のエラーが発生する場合があります：
```json
[{"message":"Asset batteryDatasetFixed cannot be deleted as it is referenced by at least one contract agreement or an ongoing negotiation","type":"ObjectConflict","path":null,"invalidValue":null}]
```

この場合、以下の順序で削除を実行してください：

```bash
# 1. 削除前に登録されているアセットを確認
curl -s "http://localhost:19193/management/v3/assets/request" \
  -X POST -H "Content-Type: application/json" \
  -d '{"@context": {"@vocab": "https://w3id.org/edc/v0.0.1/ns/"}, "@type": "QuerySpec"}' \
  | jq '.[] | {id: .["@id"], name: .properties.name}'

# 2. 該当アセットを参照しているコントラクト定義を確認
curl -s "http://localhost:19193/management/v3/contractdefinitions/request" \
  -X POST -H "Content-Type: application/json" \
  -d '{"@context": {"@vocab": "https://w3id.org/edc/v0.0.1/ns/"}, "@type": "QuerySpec"}' \
  | jq '.[] | select((.assetsSelector | type) == "object" and .assetsSelector.operandRight == "batteryDatasetFixed") | {id: .["@id"], assetsSelector: .assetsSelector}'

# 3. 参照しているコントラクト定義を先に削除
curl -X DELETE "http://localhost:19193/management/v3/contractdefinitions/universalContractDef" \
  -H "Content-Type: application/json" \
  -d '{"@context": {"@vocab": "https://w3id.org/edc/v0.0.1/ns/"}}'

# 4. 進行中の転送プロセスを確認
curl -s "http://localhost:29193/management/v3/transferprocesses/request" \
  -X POST -H "Content-Type: application/json" \
  -d '{"@context": {"@vocab": "https://w3id.org/edc/v0.0.1/ns/"}, "@type": "QuerySpec"}' \
  | jq '.[] | select(.assetId == "batteryDatasetFixed" and (.state == "STARTED" or .state == "REQUESTED")) | {id: .["@id"], state: .state, assetId: .assetId}'

# 5. 必要に応じて進行中の転送を終了
# アクティブな転送プロセスがある場合は個別に終了
# curl -X POST "http://localhost:29193/management/v3/transferprocesses/TRANSFER_ID/terminate" \
#   -H "Content-Type: application/json" \
#   -d '{"@context": {"@vocab": "https://w3id.org/edc/v0.0.1/ns/"}, "reason": "Manual cleanup"}'

# 例: 複数の転送プロセスを一括終了
# curl -s "http://localhost:29193/management/v3/transferprocesses/request" \
#   -X POST -H "Content-Type: application/json" \
#   -d '{"@context": {"@vocab": "https://w3id.org/edc/v0.0.1/ns/"}, "@type": "QuerySpec"}' \
#   | jq -r '.[] | select(.assetId == "batteryDatasetFixed" and (.state == "STARTED" or .state == "REQUESTED")) | .["@id"]' \
#   | while read -r transfer_id; do
#       curl -X POST "http://localhost:29193/management/v3/transferprocesses/$transfer_id/terminate" \
#         -H "Content-Type: application/json" \
#         -d '{"@context": {"@vocab": "https://w3id.org/edc/v0.0.1/ns/"}, "reason": "Manual cleanup"}'
#     done

# 6. アセットを削除
curl -X DELETE "http://localhost:19193/management/v3/assets/batteryDatasetFixed" \
  -H "Content-Type: application/json" \
  -d '{"@context": {"@vocab": "https://w3id.org/edc/v0.0.1/ns/"}}'

# 7. 削除確認
curl -s "http://localhost:19193/management/v3/assets/request" \
  -X POST -H "Content-Type: application/json" \
  -d '{"@context": {"@vocab": "https://w3id.org/edc/v0.0.1/ns/"}, "@type": "QuerySpec"}' \
  | jq 'length'

# 削除が失敗した場合の確認
ASSET_DELETE_RESPONSE=$(curl -s -X DELETE "http://localhost:19193/management/v3/assets/batteryDatasetFixed" \
  -H "Content-Type: application/json" \
  -d '{"@context": {"@vocab": "https://w3id.org/edc/v0.0.1/ns/"}}')

if echo "$ASSET_DELETE_RESPONSE" | grep -q "ObjectConflict"; then
  echo "⚠️ アセット削除に失敗しました。以下を確認してください："
  
  echo "1. 完了した契約合意（削除不可）:"
  curl -s "http://localhost:29193/management/v3/contractnegotiations/request" \
    -X POST -H "Content-Type: application/json" \
    -d '{"@context": {"@vocab": "https://w3id.org/edc/v0.0.1/ns/"}, "@type": "QuerySpec"}' \
    | jq '.[] | select(.state == "FINALIZED") | {id: .["@id"], state: .state, contractAgreementId: .contractAgreementId}'
  
  echo "2. アクティブな転送プロセス:"
  curl -s "http://localhost:29193/management/v3/transferprocesses/request" \
    -X POST -H "Content-Type: application/json" \
    -d '{"@context": {"@vocab": "https://w3id.org/edc/v0.0.1/ns/"}, "@type": "QuerySpec"}' \
    | jq '.[] | select(.state == "STARTED" or .state == "REQUESTED") | {id: .["@id"], state: .state, assetId: .assetId}'
  
  echo ""
  echo "💡 解決策:"
  echo "   - アクティブな転送プロセスがある場合は上記の手順5で終了"
  echo "   - 契約合意は履歴として保持され削除不可"
  echo "   - 🔄 推奨: プロバイダーコネクタを再起動（インメモリデータを全クリア）"
  
else
  echo "✅ アセットが正常に削除されました"
fi
```

### 7.2 ポリシー定義の削除
```bash
# 削除前に登録されているポリシーを確認
curl -s "http://localhost:19193/management/v3/policydefinitions/request" \
  -X POST -H "Content-Type: application/json" \
  -d '{"@context": {"@vocab": "https://w3id.org/edc/v0.0.1/ns/"}, "@type": "QuerySpec"}' \
  | jq '.[] | {id: .["@id"]}'

# ポリシー定義を削除
curl -X DELETE "http://localhost:19193/management/v3/policydefinitions/aPolicy" \
  -H "Content-Type: application/json" \
  -d '{"@context": {"@vocab": "https://w3id.org/edc/v0.0.1/ns/"}}'

# 削除確認
curl -s "http://localhost:19193/management/v3/policydefinitions/request" \
  -X POST -H "Content-Type: application/json" \
  -d '{"@context": {"@vocab": "https://w3id.org/edc/v0.0.1/ns/"}, "@type": "QuerySpec"}' \
  | jq 'length'
```

### 7.3 コントラクト定義の削除
```bash
# 削除前に登録されているコントラクト定義を確認
curl -s "http://localhost:19193/management/v3/contractdefinitions/request" \
  -X POST -H "Content-Type: application/json" \
  -d '{"@context": {"@vocab": "https://w3id.org/edc/v0.0.1/ns/"}, "@type": "QuerySpec"}' \
  | jq '.[] | {id: .["@id"], accessPolicyId: .accessPolicyId, contractPolicyId: .contractPolicyId}'

# コントラクト定義を削除
curl -X DELETE "http://localhost:19193/management/v3/contractdefinitions/universalContractDef" \
  -H "Content-Type: application/json" \
  -d '{"@context": {"@vocab": "https://w3id.org/edc/v0.0.1/ns/"}}'

# 削除確認
curl -s "http://localhost:19193/management/v3/contractdefinitions/request" \
  -X POST -H "Content-Type: application/json" \
  -d '{"@context": {"@vocab": "https://w3id.org/edc/v0.0.1/ns/"}, "@type": "QuerySpec"}' \
  | jq 'length'
```

### 7.4 転送プロセスの確認と停止
```bash
# アクティブな転送プロセスを確認
curl -s "http://localhost:29193/management/v3/transferprocesses/request" \
  -X POST -H "Content-Type: application/json" \
  -d '{"@context": {"@vocab": "https://w3id.org/edc/v0.0.1/ns/"}, "@type": "QuerySpec"}' \
  | jq '.[] | {id: .["@id"], state: .state, assetId: .assetId}'

# 転送プロセスの終了（必要に応じて）
# 注意: 通常は自動的に完了するため、手動終了は推奨されません
TRANSFER_ID="your-transfer-id"
curl -X POST "http://localhost:29193/management/v3/transferprocesses/$TRANSFER_ID/terminate" \
  -H "Content-Type: application/json" \
  -d '{
    "@context": {"@vocab": "https://w3id.org/edc/v0.0.1/ns/"},
    "reason": "Manual termination for cleanup"
  }'
```

### 7.5 コントラクト交渉の確認
```bash
# 完了したコントラクト交渉を確認
curl -s "http://localhost:29193/management/v3/contractnegotiations/request" \
  -X POST -H "Content-Type: application/json" \
  -d '{"@context": {"@vocab": "https://w3id.org/edc/v0.0.1/ns/"}, "@type": "QuerySpec"}' \
  | jq '.[] | {id: .["@id"], state: .state, contractAgreementId: .contractAgreementId}'

# 注意: コントラクト交渉は削除できません（履歴として保持）
```

### 7.6 EDRトークンの確認
```bash
# アクティブなEDRトークンを確認
curl -s "http://localhost:29193/management/v3/edrs/request" \
  -X POST -H "Content-Type: application/json" \
  -d '{"@context": {"@vocab": "https://w3id.org/edc/v0.0.1/ns/"}, "@type": "QuerySpec"}' \
  | jq '.[] | {transferProcessId: .transferProcessId, createdAt: .createdAt}'

# 注意: EDRトークンは有効期限で自動的に無効化されます
```

### 7.7 完全なクリーンアップスクリプト
```bash
#!/bin/bash
echo "🗑️ EDCリソースのクリーンアップを開始します..."

# コントラクト定義を削除（依存関係のため最初に削除）
echo "1. コントラクト定義を削除中..."
curl -X DELETE "http://localhost:19193/management/v3/contractdefinitions/universalContractDef" \
  -H "Content-Type: application/json" \
  -d '{"@context": {"@vocab": "https://w3id.org/edc/v0.0.1/ns/"}}' -s > /dev/null

# アセットを削除
echo "2. アセットを削除中..."
curl -X DELETE "http://localhost:19193/management/v3/assets/batteryDatasetFixed" \
  -H "Content-Type: application/json" \
  -d '{"@context": {"@vocab": "https://w3id.org/edc/v0.0.1/ns/"}}' -s > /dev/null

# ポリシー定義を削除
echo "3. ポリシー定義を削除中..."
curl -X DELETE "http://localhost:19193/management/v3/policydefinitions/aPolicy" \
  -H "Content-Type: application/json" \
  -d '{"@context": {"@vocab": "https://w3id.org/edc/v0.0.1/ns/"}}' -s > /dev/null

# 削除結果を確認
echo "4. 削除結果を確認中..."
ASSETS_COUNT=$(curl -s "http://localhost:19193/management/v3/assets/request" \
  -X POST -H "Content-Type: application/json" \
  -d '{"@context": {"@vocab": "https://w3id.org/edc/v0.0.1/ns/"}, "@type": "QuerySpec"}' \
  | jq 'length')

POLICIES_COUNT=$(curl -s "http://localhost:19193/management/v3/policydefinitions/request" \
  -X POST -H "Content-Type: application/json" \
  -d '{"@context": {"@vocab": "https://w3id.org/edc/v0.0.1/ns/"}, "@type": "QuerySpec"}' \
  | jq 'length')

CONTRACTS_COUNT=$(curl -s "http://localhost:19193/management/v3/contractdefinitions/request" \
  -X POST -H "Content-Type: application/json" \
  -d '{"@context": {"@vocab": "https://w3id.org/edc/v0.0.1/ns/"}, "@type": "QuerySpec"}' \
  | jq 'length')

echo "✅ クリーンアップ完了:"
echo "   - アセット: $ASSETS_COUNT 個"
echo "   - ポリシー定義: $POLICIES_COUNT 個" 
echo "   - コントラクト定義: $CONTRACTS_COUNT 個"
```

### ⚠️ 削除時の注意事項

#### **削除順序の重要性**
1. **コントラクト定義** → 他のリソースを参照するため最初に削除
2. **アセット** → データの実体
3. **ポリシー定義** → 最後に削除（参照されなくなってから）

#### **削除できないリソース**
- **コントラクト交渉**: 履歴として保持される（`FINALIZED`状態）
- **契約合意**: 履歴として保持される（削除不可）
- **転送プロセス**: 完了したものは履歴として保持
- **EDRトークン**: 有効期限で自動無効化

#### **インメモリストレージの場合**
- **🔄 推奨解決策**: コネクタ再起動で全データが自動的にクリアされる
- **手動削除の限界**: 契約合意が存在するアセットは削除不可
- 永続化ストレージを使用している場合は手動削除が必要

#### **💡 実用的な解決手順**
```bash
# 1. プロバイダーコネクタを停止（Ctrl+C）
# 2. プロバイダーコネクタを再起動
java -Dedc.fs.config=transfer/transfer-03-consumer-pull/resources/configuration/provider.properties \
     -jar transfer/transfer-03-consumer-pull/provider-proxy-data-plane/build/libs/connector.jar

# 3. 必要に応じてリソースを再作成
```

--- 