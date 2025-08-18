# SPARQL クエリガイド
## EDC統合環境でのSPARQLクエリ実践

### 📋 概要
このガイドでは、SPARQL（SPARQL Protocol and RDF Query Language）の基本から応用まで、特にEDC（Eclipse Data Connector）環境でのRDFデータクエリについて詳しく説明します。Apache Jena Fusekiサーバーとの連携を含む実践的な例を提供します。

### 🛠️ 前提知識
- RDF（Resource Description Framework）の基本概念
- トリプル（Subject-Predicate-Object）の理解
- Apache Jena Fuseki の基本操作
- EDCの基本的な使用方法

---

## 🔍 SPARQLの基本概念

### **RDFトリプルの構造**
```
Subject    Predicate                Object
<battery1> <hasStateOfHealth>      "92.1"^^xsd:decimal
<battery1> <rdf:type>              <Battery>
<battery1> <hasFeatureOfInterest>  <battery1>
<battery1> <resultTime>            "2025-06-29"^^xsd:date
```

### **名前空間の定義**
```sparql
PREFIX rdf: <http://www.w3.org/1999/02/22-rdf-syntax-ns#>
PREFIX xsd: <http://www.w3.org/2001/XMLSchema#>
PREFIX sosa: <http://www.w3.org/ns/sosa/>
PREFIX battery: <http://example.org/battery/>
```

---

## 📚 SPARQL クエリの段階別例

### **レベル1: 基本クエリ**

#### **1.1 全データの取得**
```sparql
SELECT ?subject ?predicate ?object
WHERE {
  ?subject ?predicate ?object
}
LIMIT 25
```

#### **1.2 特定タイプのリソース取得**
```sparql
PREFIX rdf: <http://www.w3.org/1999/02/22-rdf-syntax-ns#>
PREFIX battery: <http://example.org/battery/>

SELECT ?battery
WHERE {
  ?battery rdf:type battery:Battery .
}
```

#### **1.3 特定プロパティの値取得**
```sparql
PREFIX battery: <http://example.org/battery/>

SELECT ?battery ?stateOfHealth
WHERE {
  ?battery battery:stateOfHealth ?stateOfHealth .
}
```

### **レベル2: フィルタリングクエリ**

#### **2.1 数値範囲でのフィルタ**
```sparql
PREFIX battery: <http://example.org/battery/>

SELECT ?battery ?soh
WHERE {
  ?battery battery:stateOfHealth ?soh .
  FILTER(?soh > 90.0)
}
ORDER BY DESC(?soh)
```

#### **2.2 日付範囲でのフィルタ**
```sparql
PREFIX sosa: <http://www.w3.org/ns/sosa/>
PREFIX xsd: <http://www.w3.org/2001/XMLSchema#>

SELECT ?battery ?resultTime
WHERE {
  ?battery sosa:resultTime ?resultTime .
  FILTER(?resultTime >= "2025-01-01"^^xsd:date && 
         ?resultTime <= "2025-12-31"^^xsd:date)
}
```

#### **2.3 文字列パターンマッチング**
```sparql
PREFIX battery: <http://example.org/battery/>

SELECT ?battery ?id
WHERE {
  ?battery battery:batteryId ?id .
  FILTER(REGEX(?id, "BAT-.*", "i"))
}
```

### **レベル3: 複合クエリ**

#### **3.1 複数条件の組み合わせ**
```sparql
PREFIX rdf: <http://www.w3.org/1999/02/22-rdf-syntax-ns#>
PREFIX battery: <http://example.org/battery/>
PREFIX sosa: <http://www.w3.org/ns/sosa/>

SELECT ?battery ?soh ?resultTime
WHERE {
  ?battery rdf:type battery:Battery ;
           battery:stateOfHealth ?soh ;
           sosa:resultTime ?resultTime .
  FILTER(?soh > 85.0 && ?resultTime > "2025-06-01"^^xsd:date)
}
ORDER BY DESC(?soh)
```

#### **3.2 オプショナルデータの取得**
```sparql
PREFIX battery: <http://example.org/battery/>

SELECT ?battery ?soh ?temperature
WHERE {
  ?battery battery:stateOfHealth ?soh .
  OPTIONAL { ?battery battery:temperature ?temperature }
}
```

#### **3.3 グループ化と集約**
```sparql
PREFIX battery: <http://example.org/battery/>
PREFIX sosa: <http://www.w3.org/ns/sosa/>

SELECT ?month (AVG(?soh) AS ?avgSOH) (COUNT(?battery) AS ?count)
WHERE {
  ?battery battery:stateOfHealth ?soh ;
           sosa:resultTime ?resultTime .
  BIND(MONTH(?resultTime) AS ?month)
}
GROUP BY ?month
ORDER BY ?month
```

### **レベル4: 高度なクエリ**

#### **4.1 サブクエリの使用**
```sparql
PREFIX battery: <http://example.org/battery/>

SELECT ?battery ?soh
WHERE {
  ?battery battery:stateOfHealth ?soh .
  {
    SELECT (MAX(?maxSOH) AS ?threshold)
    WHERE {
      ?b battery:stateOfHealth ?maxSOH .
    }
  }
  FILTER(?soh > ?threshold * 0.9)
}
```

#### **4.2 UNION を使った複数パターン**
```sparql
PREFIX battery: <http://example.org/battery/>
PREFIX vehicle: <http://example.org/vehicle/>

SELECT ?item ?value
WHERE {
  {
    ?item battery:stateOfHealth ?value .
  }
  UNION
  {
    ?item vehicle:fuelLevel ?value .
  }
}
```

#### **4.3 推論とプロパティパス**
```sparql
PREFIX battery: <http://example.org/battery/>
PREFIX vehicle: <http://example.org/vehicle/>

SELECT ?vehicle ?battery ?soh
WHERE {
  ?vehicle vehicle:hasPart+ ?battery .
  ?battery battery:stateOfHealth ?soh .
  FILTER(?soh < 80.0)
}
```

---

## 🔧 EDC環境での実用的なクエリ例

### **バッテリーデータセット用クエリ**

#### **1. 健全性レポート**
```sparql
PREFIX rdf: <http://www.w3.org/1999/02/22-rdf-syntax-ns#>
PREFIX battery: <http://example.org/battery/>
PREFIX sosa: <http://www.w3.org/ns/sosa/>

SELECT ?batteryId ?stateOfHealth ?resultTime ?status
WHERE {
  ?battery rdf:type battery:Battery ;
           battery:batteryId ?batteryId ;
           battery:stateOfHealth ?stateOfHealth ;
           sosa:resultTime ?resultTime .
  
  BIND(
    IF(?stateOfHealth >= 90, "Excellent",
    IF(?stateOfHealth >= 80, "Good", 
    IF(?stateOfHealth >= 70, "Fair", "Poor"))) AS ?status
  )
}
ORDER BY DESC(?stateOfHealth)
```

#### **2. 劣化傾向分析**
```sparql
PREFIX battery: <http://example.org/battery/>
PREFIX sosa: <http://www.w3.org/ns/sosa/>

SELECT ?batteryId 
       (MIN(?stateOfHealth) AS ?minSOH)
       (MAX(?stateOfHealth) AS ?maxSOH)
       (AVG(?stateOfHealth) AS ?avgSOH)
       (COUNT(*) AS ?measurements)
WHERE {
  ?battery battery:batteryId ?batteryId ;
           battery:stateOfHealth ?stateOfHealth ;
           sosa:resultTime ?resultTime .
  FILTER(?resultTime >= "2025-01-01"^^xsd:date)
}
GROUP BY ?batteryId
HAVING (?maxSOH - ?minSOH > 5.0)
ORDER BY DESC(?maxSOH - ?minSOH)
```

#### **3. アラート生成**
```sparql
PREFIX rdf: <http://www.w3.org/1999/02/22-rdf-syntax-ns#>
PREFIX battery: <http://example.org/battery/>
PREFIX sosa: <http://www.w3.org/ns/sosa/>

SELECT ?batteryId ?stateOfHealth ?resultTime ?alertLevel
WHERE {
  ?battery rdf:type battery:Battery ;
           battery:batteryId ?batteryId ;
           battery:stateOfHealth ?stateOfHealth ;
           sosa:resultTime ?resultTime .
  
  BIND(
    IF(?stateOfHealth < 70, "CRITICAL",
    IF(?stateOfHealth < 80, "WARNING", "OK")) AS ?alertLevel
  )
  
  FILTER(?alertLevel != "OK")
}
ORDER BY ?stateOfHealth
```

### **製造業データクエリ例**

#### **4. 品質管理クエリ**
```sparql
PREFIX mfg: <http://example.org/manufacturing/>
PREFIX quality: <http://example.org/quality/>

SELECT ?productId ?qualityScore ?defectType ?timestamp
WHERE {
  ?product mfg:productId ?productId ;
           quality:qualityScore ?qualityScore ;
           quality:inspectionTime ?timestamp .
  
  OPTIONAL { ?product quality:defectType ?defectType }
  
  FILTER(?qualityScore < 95.0 || BOUND(?defectType))
}
ORDER BY ?timestamp
```

#### **5. 生産効率分析**
```sparql
PREFIX mfg: <http://example.org/manufacturing/>

SELECT ?line 
       (SUM(?produced) AS ?totalProduced)
       (AVG(?efficiency) AS ?avgEfficiency)
       ?shift
WHERE {
  ?production mfg:productionLine ?line ;
              mfg:unitsProduced ?produced ;
              mfg:efficiency ?efficiency ;
              mfg:shift ?shift ;
              mfg:date ?date .
  
  FILTER(?date >= "2025-06-01"^^xsd:date)
}
GROUP BY ?line ?shift
ORDER BY ?line ?shift
```

---

## 🌐 EDCプロキシ経由でのクエリ実行

### **cURLでの基本実行**

#### **1. 直接SPARQLエンドポイント**
```bash
# 直接Fusekiサーバーへのクエリ
curl -X POST \
  -H "Content-Type: application/sparql-query" \
  --data 'SELECT ?s ?p ?o WHERE { ?s ?p ?o } LIMIT 10' \
  http://localhost:3030/battery_dataset/query
```

#### **2. EDCプロキシ経由**
```bash
# EDRトークンを使用してプロキシ経由でクエリ
curl -X POST \
  -H "Authorization: Bearer $EDR_AUTH_KEY" \
  -H "Content-Type: application/sparql-query" \
  --data 'SELECT ?battery ?soh WHERE { ?battery <http://example.org/battery/stateOfHealth> ?soh } LIMIT 5' \
  $EDR_ENDPOINT
```

#### **3. フォームデータとしての送信**
```bash
# application/x-www-form-urlencoded 形式
curl -X POST \
  -H "Authorization: Bearer $EDR_AUTH_KEY" \
  -H "Content-Type: application/x-www-form-urlencoded" \
  --data-urlencode 'query=SELECT ?s ?p ?o WHERE { ?s ?p ?o } LIMIT 10' \
  $EDR_ENDPOINT
```

### **Pythonでの実行例**

```python
import requests
import json

def execute_sparql_via_edc(edr_endpoint, auth_key, sparql_query):
    """EDCプロキシ経由でSPARQLクエリを実行"""
    headers = {
        'Authorization': f'Bearer {auth_key}',
        'Content-Type': 'application/sparql-query'
    }
    
    response = requests.post(edr_endpoint, 
                           headers=headers, 
                           data=sparql_query)
    
    if response.status_code == 200:
        return response.json()
    else:
        raise Exception(f"Query failed: {response.status_code} - {response.text}")

# 使用例
query = """
PREFIX battery: <http://example.org/battery/>
SELECT ?battery ?soh 
WHERE { 
  ?battery battery:stateOfHealth ?soh 
  FILTER(?soh > 90.0)
} 
ORDER BY DESC(?soh)
"""

try:
    result = execute_sparql_via_edc(edr_endpoint, auth_key, query)
    for binding in result['results']['bindings']:
        battery = binding['battery']['value']
        soh = binding['soh']['value']
        print(f"Battery: {battery}, SOH: {soh}")
except Exception as e:
    print(f"Error: {e}")
```

### **JavaScriptでの実行例**

```javascript
async function executeSparqlQuery(edrEndpoint, authKey, sparqlQuery) {
    const response = await fetch(edrEndpoint, {
        method: 'POST',
        headers: {
            'Authorization': `Bearer ${authKey}`,
            'Content-Type': 'application/sparql-query'
        },
        body: sparqlQuery
    });
    
    if (!response.ok) {
        throw new Error(`HTTP error! status: ${response.status}`);
    }
    
    return await response.json();
}

// 使用例
const query = `
    PREFIX battery: <http://example.org/battery/>
    SELECT ?battery ?soh ?resultTime
    WHERE { 
        ?battery battery:stateOfHealth ?soh ;
                 <http://www.w3.org/ns/sosa/resultTime> ?resultTime .
        FILTER(?resultTime > "2025-06-01"^^xsd:date)
    } 
    ORDER BY DESC(?resultTime)
`;

executeSparqlQuery(edrEndpoint, authKey, query)
    .then(result => {
        console.log('Query results:', result);
        result.results.bindings.forEach(binding => {
            console.log(`Battery: ${binding.battery.value}, SOH: ${binding.soh.value}`);
        });
    })
    .catch(error => {
        console.error('Query error:', error);
    });
```

---

## 📊 クエリ結果の形式

### **JSON形式のレスポンス**
```json
{
  "head": {
    "vars": ["battery", "stateOfHealth", "resultTime"]
  },
  "results": {
    "bindings": [
      {
        "battery": {
          "type": "uri",
          "value": "http://example.org/battery/BAT-01"
        },
        "stateOfHealth": {
          "type": "literal",
          "datatype": "http://www.w3.org/2001/XMLSchema#decimal",
          "value": "92.1"
        },
        "resultTime": {
          "type": "literal",
          "datatype": "http://www.w3.org/2001/XMLSchema#date",
          "value": "2025-06-29"
        }
      }
    ]
  }
}
```

### **CSV形式での出力**
```sparql
# CSVヘッダー付きでの結果取得
SELECT ?batteryId ?stateOfHealth ?resultTime
WHERE {
  ?battery <http://example.org/battery/batteryId> ?batteryId ;
           <http://example.org/battery/stateOfHealth> ?stateOfHealth ;
           <http://www.w3.org/ns/sosa/resultTime> ?resultTime .
}
ORDER BY ?batteryId
```

```csv
batteryId,stateOfHealth,resultTime
"BAT-01",92.1,2025-06-29
"BAT-02",87.4,2025-06-29
```

---

## 🛡️ セキュリティとベストプラクティス

### **クエリの最適化**

#### **1. LIMIT句の使用**
```sparql
# 大量データの場合は必ずLIMITを設定
SELECT ?s ?p ?o
WHERE { ?s ?p ?o }
LIMIT 1000
```

#### **2. 効率的なフィルタリング**
```sparql
# 早い段階でのフィルタリング
SELECT ?battery ?soh
WHERE {
  ?battery <http://example.org/battery/stateOfHealth> ?soh .
  FILTER(?soh > 90.0)  # 早期フィルタリング
}
```

#### **3. インデックス利用の最適化**
```sparql
# 具体的なプロパティパスを使用
SELECT ?battery ?soh
WHERE {
  ?battery <http://example.org/battery/stateOfHealth> ?soh .  # 具体的
  # ?battery ?prop ?soh . # 避ける（非効率）
}
```

### **セキュリティ考慮事項**

#### **1. インジェクション対策**
```python
# 悪い例
query = f"SELECT ?s WHERE {{ ?s <{user_input}> ?o }}"

# 良い例
from urllib.parse import quote
safe_uri = quote(user_input, safe=':/#')
query = f"SELECT ?s WHERE {{ ?s <{safe_uri}> ?o }}"
```

#### **2. アクセス制御**
```sparql
# 特定のグラフのみアクセス
SELECT ?s ?p ?o
FROM <http://example.org/public-data>
WHERE { ?s ?p ?o }
```

#### **3. 結果サイズの制限**
```sparql
# 結果サイズを制限
SELECT ?s ?p ?o
WHERE { ?s ?p ?o }
LIMIT 10000
```

---

## 🧪 テストとデバッグ

### **クエリテスト用スクリプト**

```bash
#!/bin/bash
# test-sparql-queries.sh

FUSEKI_ENDPOINT="http://localhost:3030/battery_dataset/query"
EDC_ENDPOINT="$EDR_ENDPOINT"
AUTH_KEY="$EDR_AUTH_KEY"

test_query() {
    local query="$1"
    local description="$2"
    
    echo "Testing: $description"
    echo "Query: $query"
    
    # 直接Fusekiテスト
    echo "Direct Fuseki:"
    curl -s -X POST \
        -H "Content-Type: application/sparql-query" \
        --data "$query" \
        "$FUSEKI_ENDPOINT" | jq .
    
    # EDC経由テスト
    echo "Via EDC Proxy:"
    curl -s -X POST \
        -H "Authorization: Bearer $AUTH_KEY" \
        -H "Content-Type: application/sparql-query" \
        --data "$query" \
        "$EDC_ENDPOINT" | jq .
    
    echo "---"
}

# テスト実行
test_query "SELECT ?s ?p ?o WHERE { ?s ?p ?o } LIMIT 5" "Basic triple query"

test_query "PREFIX battery: <http://example.org/battery/>
SELECT ?battery ?soh 
WHERE { ?battery battery:stateOfHealth ?soh } 
LIMIT 3" "Battery SOH query"

test_query "PREFIX battery: <http://example.org/battery/>
SELECT (COUNT(*) AS ?count) 
WHERE { ?battery battery:stateOfHealth ?soh }" "Count query"
```

### **パフォーマンス測定**

```bash
#!/bin/bash
# measure-query-performance.sh

measure_query_time() {
    local query="$1"
    local endpoint="$2"
    local auth_header="$3"
    
    local start_time=$(date +%s.%N)
    
    curl -s -X POST \
        $auth_header \
        -H "Content-Type: application/sparql-query" \
        --data "$query" \
        "$endpoint" > /dev/null
    
    local end_time=$(date +%s.%N)
    local duration=$(echo "$end_time - $start_time" | bc)
    
    echo "Query execution time: ${duration}s"
}

# 使用例
COMPLEX_QUERY="PREFIX battery: <http://example.org/battery/>
SELECT ?battery (AVG(?soh) AS ?avgSOH) 
WHERE { ?battery battery:stateOfHealth ?soh } 
GROUP BY ?battery"

measure_query_time "$COMPLEX_QUERY" "$FUSEKI_ENDPOINT" ""
measure_query_time "$COMPLEX_QUERY" "$EDC_ENDPOINT" "-H 'Authorization: Bearer $AUTH_KEY'"
```

---

## 📚 よく使用されるクエリパターン

### **1. データ探索クエリ**
```sparql
# データセットの構造を理解
SELECT ?predicate (COUNT(*) AS ?count)
WHERE { ?s ?predicate ?o }
GROUP BY ?predicate
ORDER BY DESC(?count)
```

### **2. データ品質チェック**
```sparql
# 欠損データの確認
SELECT ?battery
WHERE {
  ?battery <http://www.w3.org/1999/02/22-rdf-syntax-ns#type> <http://example.org/battery/Battery> .
  FILTER NOT EXISTS { ?battery <http://example.org/battery/stateOfHealth> ?soh }
}
```

### **3. 時系列データ分析**
```sparql
PREFIX sosa: <http://www.w3.org/ns/sosa/>
PREFIX battery: <http://example.org/battery/>

SELECT ?date (AVG(?soh) AS ?avgSOH) (COUNT(?battery) AS ?count)
WHERE {
  ?battery battery:stateOfHealth ?soh ;
           sosa:resultTime ?datetime .
  BIND(xsd:date(?datetime) AS ?date)
}
GROUP BY ?date
ORDER BY ?date
```

### **4. 異常検出クエリ**
```sparql
PREFIX battery: <http://example.org/battery/>

SELECT ?battery ?soh ?deviation
WHERE {
  ?battery battery:stateOfHealth ?soh .
  
  {
    SELECT (AVG(?avgSOH) AS ?mean) (STDEV(?avgSOH) AS ?stddev)
    WHERE { ?b battery:stateOfHealth ?avgSOH }
  }
  
  BIND(ABS(?soh - ?mean) / ?stddev AS ?deviation)
  FILTER(?deviation > 2.0)  # 2σを超える異常値
}
ORDER BY DESC(?deviation)
```

---

## 🚀 高度な活用例

### **フェデレーテッドクエリ**
```sparql
# 複数のエンドポイントからデータを取得
PREFIX battery: <http://example.org/battery/>

SELECT ?battery ?soh ?maintenance
WHERE {
  ?battery battery:stateOfHealth ?soh .
  
  SERVICE <http://maintenance-service/sparql> {
    ?battery <http://example.org/maintenance/lastService> ?maintenance
  }
  
  FILTER(?soh < 85.0)
}
```

### **推論を活用したクエリ**
```sparql
# OWL推論を使用した高度なクエリ
PREFIX battery: <http://example.org/battery/>
PREFIX owl: <http://www.w3.org/2002/07/owl#>

SELECT ?battery ?category
WHERE {
  ?battery battery:stateOfHealth ?soh .
  ?battery a ?category .
  ?category owl:equivalentClass ?equivalentCategory .
  
  FILTER(?soh > 90.0)
}
```

---

## 📖 参考資料

### **SPARQL仕様**
- [SPARQL 1.1 Query Language](https://www.w3.org/TR/sparql11-query/)
- [SPARQL 1.1 Protocol](https://www.w3.org/TR/sparql11-protocol/)
- [SPARQL 1.1 Results Formats](https://www.w3.org/TR/sparql11-results-json/)

### **Apache Jena**
- [Jena Fuseki Documentation](https://jena.apache.org/documentation/fuseki2/)
- [ARQ SPARQL Processor](https://jena.apache.org/documentation/query/)

### **RDF関連**
- [RDF 1.1 Concepts](https://www.w3.org/TR/rdf11-concepts/)
- [RDF Schema](https://www.w3.org/TR/rdf-schema/)
- [OWL 2 Web Ontology Language](https://www.w3.org/TR/owl2-overview/)

---

このガイドを参考に、EDC環境でのSPARQLクエリを効果的に活用し、RDFデータから価値のある洞察を得てください。段階的に複雑なクエリに挑戦し、データ分析の幅を広げていきましょう。 