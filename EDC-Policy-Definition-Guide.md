# EDC ポリシー定義ガイド
## ODRL (Open Digital Rights Language) を使った高度なアクセス制御

### 📋 概要
このガイドでは、Eclipse Data Connector (EDC) で使用できる様々なポリシー定義について詳しく説明します。ODRLを基盤とした柔軟で強力なアクセス制御メカニズムを理解し、実用的なポリシーを作成できるようになります。

### 🛠️ 前提知識
- ODRL (Open Digital Rights Language) の基本概念
- EDCの基本的な使用方法
- JSON-LD の基本的な理解

---

## 🔍 ODRLの基本構造

### **基本要素**
```json
{
  "@context": "http://www.w3.org/ns/odrl.jsonld",
  "@type": "Set",
  "permission": [/* 許可されるアクション */],
  "prohibition": [/* 禁止されるアクション */],
  "obligation": [/* 義務として実行すべきアクション */]
}
```

### **主要コンポーネント**
- **Permission**: データの使用を許可する条件
- **Prohibition**: データの使用を禁止する条件  
- **Obligation**: データ使用者が守るべき義務
- **Constraint**: 条件や制約の定義
- **Action**: 実行可能なアクション（use, distribute, delete等）

---

## 📚 ポリシー定義の段階別例

### **レベル1: 基本ポリシー**

#### **1.1 無制限アクセスポリシー（現在使用中）**
```json
{
  "@context": {
    "@vocab": "https://w3id.org/edc/v0.0.1/ns/",
    "odrl": "http://www.w3.org/ns/odrl/2/"
  },
  "@id": "openAccessPolicy",
  "policy": {
    "@context": "http://www.w3.org/ns/odrl.jsonld",
    "@type": "Set",
    "permission": [],
    "prohibition": [],
    "obligation": []
  }
}
```

#### **1.2 基本使用許可ポリシー**
```json
{
  "@context": {
    "@vocab": "https://w3id.org/edc/v0.0.1/ns/",
    "odrl": "http://www.w3.org/ns/odrl/2/"
  },
  "@id": "basicUsePolicy",
  "policy": {
    "@context": "http://www.w3.org/ns/odrl.jsonld",
    "@type": "Set",
    "permission": [{
      "action": "use",
      "target": "http://example.org/asset/data"
    }]
  }
}
```

### **レベル2: 時間制限ポリシー**

#### **2.1 有効期限付きポリシー**
```json
{
  "@context": {
    "@vocab": "https://w3id.org/edc/v0.0.1/ns/",
    "odrl": "http://www.w3.org/ns/odrl/2/"
  },
  "@id": "timeBasedPolicy",
  "policy": {
    "@context": "http://www.w3.org/ns/odrl.jsonld",
    "@type": "Set",
    "permission": [{
      "action": "use",
      "constraint": [{
        "leftOperand": "dateTime",
        "operator": "lt",
        "rightOperand": "2025-12-31T23:59:59Z"
      }]
    }]
  }
}
```

#### **2.2 営業時間限定ポリシー**
```json
{
  "@context": {
    "@vocab": "https://w3id.org/edc/v0.0.1/ns/",
    "odrl": "http://www.w3.org/ns/odrl/2/"
  },
  "@id": "businessHoursPolicy",
  "policy": {
    "@context": "http://www.w3.org/ns/odrl.jsonld",
    "@type": "Set",
    "permission": [{
      "action": "use",
      "constraint": [{
        "leftOperand": "dateTime",
        "operator": "gteq",
        "rightOperand": "T09:00:00"
      }, {
        "leftOperand": "dateTime", 
        "operator": "lteq",
        "rightOperand": "T17:00:00"
      }]
    }]
  }
}
```

### **レベル3: 地理的制限ポリシー**

#### **3.1 特定地域限定ポリシー**
```json
{
  "@context": {
    "@vocab": "https://w3id.org/edc/v0.0.1/ns/",
    "odrl": "http://www.w3.org/ns/odrl/2/"
  },
  "@id": "geoRestrictedPolicy",
  "policy": {
    "@context": "http://www.w3.org/ns/odrl.jsonld",
    "@type": "Set",
    "permission": [{
      "action": "use",
      "constraint": [{
        "leftOperand": "spatial",
        "operator": "eq",
        "rightOperand": "https://www.geonames.org/1861060/"
      }]
    }],
    "prohibition": [{
      "action": "use",
      "constraint": [{
        "leftOperand": "spatial",
        "operator": "neq",
        "rightOperand": "https://www.geonames.org/1861060/"
      }]
    }]
  }
}
```

### **レベル4: 用途制限ポリシー**

#### **4.1 研究目的限定ポリシー**
```json
{
  "@context": {
    "@vocab": "https://w3id.org/edc/v0.0.1/ns/",
    "odrl": "http://www.w3.org/ns/odrl/2/"
  },
  "@id": "researchOnlyPolicy",
  "policy": {
    "@context": "http://www.w3.org/ns/odrl.jsonld",
    "@type": "Set",
    "permission": [{
      "action": "use",
      "constraint": [{
        "leftOperand": "purpose",
        "operator": "eq",
        "rightOperand": "research"
      }]
    }],
    "prohibition": [{
      "action": "commercialize",
      "constraint": [{
        "leftOperand": "purpose",
        "operator": "eq",
        "rightOperand": "commercial"
      }]
    }]
  }
}
```

#### **4.2 商用利用禁止ポリシー**
```json
{
  "@context": {
    "@vocab": "https://w3id.org/edc/v0.0.1/ns/",
    "odrl": "http://www.w3.org/ns/odrl/2/"
  },
  "@id": "nonCommercialPolicy",
  "policy": {
    "@context": "http://www.w3.org/ns/odrl.jsonld",
    "@type": "Set",
    "permission": [{
      "action": "use",
      "constraint": [{
        "leftOperand": "purpose",
        "operator": "neq",
        "rightOperand": "commercial"
      }]
    }],
    "prohibition": [{
      "action": "sell"
    }, {
      "action": "commercialize"
    }]
  }
}
```

### **レベル5: 複合制約ポリシー**

#### **5.1 複数条件組み合わせポリシー**
```json
{
  "@context": {
    "@vocab": "https://w3id.org/edc/v0.0.1/ns/",
    "odrl": "http://www.w3.org/ns/odrl/2/"
  },
  "@id": "complexConstraintPolicy",
  "policy": {
    "@context": "http://www.w3.org/ns/odrl.jsonld",
    "@type": "Set",
    "permission": [{
      "action": "use",
      "constraint": [{
        "and": [{
          "leftOperand": "dateTime",
          "operator": "lt",
          "rightOperand": "2025-12-31T23:59:59Z"
        }, {
          "leftOperand": "purpose",
          "operator": "eq",
          "rightOperand": "research"
        }, {
          "leftOperand": "spatial",
          "operator": "eq",
          "rightOperand": "https://www.geonames.org/1861060/"
        }]
      }]
    }]
  }
}
```

### **レベル6: 義務付きポリシー**

#### **6.1 帰属表示義務ポリシー**
```json
{
  "@context": {
    "@vocab": "https://w3id.org/edc/v0.0.1/ns/",
    "odrl": "http://www.w3.org/ns/odrl/2/"
  },
  "@id": "attributionPolicy",
  "policy": {
    "@context": "http://www.w3.org/ns/odrl.jsonld",
    "@type": "Set",
    "permission": [{
      "action": "use",
      "duty": [{
        "action": "attribute",
        "constraint": [{
          "leftOperand": "payAmount",
          "operator": "eq",
          "rightOperand": "0"
        }]
      }]
    }]
  }
}
```

#### **6.2 削除義務付きポリシー**
```json
{
  "@context": {
    "@vocab": "https://w3id.org/edc/v0.0.1/ns/",
    "odrl": "http://www.w3.org/ns/odrl/2/"
  },
  "@id": "deletionObligationPolicy",
  "policy": {
    "@context": "http://www.w3.org/ns/odrl.jsonld",
    "@type": "Set",
    "permission": [{
      "action": "use",
      "constraint": [{
        "leftOperand": "dateTime",
        "operator": "lt",
        "rightOperand": "2025-12-31T23:59:59Z"
      }]
    }],
    "obligation": [{
      "action": "delete",
      "constraint": [{
        "leftOperand": "elapsedTime",
        "operator": "eq",
        "rightOperand": "P30D"
      }]
    }]
  }
}
```

### **レベル7: 支払い条件付きポリシー**

#### **7.1 従量課金ポリシー**
```json
{
  "@context": {
    "@vocab": "https://w3id.org/edc/v0.0.1/ns/",
    "odrl": "http://www.w3.org/ns/odrl/2/"
  },
  "@id": "payPerUsePolicy",
  "policy": {
    "@context": "http://www.w3.org/ns/odrl.jsonld",
    "@type": "Set",
    "permission": [{
      "action": "use",
      "duty": [{
        "action": "compensate",
        "constraint": [{
          "leftOperand": "payAmount",
          "operator": "eq",
          "rightOperand": "5.00"
        }, {
          "leftOperand": "unit",
          "operator": "eq", 
          "rightOperand": "http://dbpedia.org/resource/Euro"
        }]
      }]
    }]
  }
}
```

#### **7.2 サブスクリプションポリシー**
```json
{
  "@context": {
    "@vocab": "https://w3id.org/edc/v0.0.1/ns/",
    "odrl": "http://www.w3.org/ns/odrl/2/"
  },
  "@id": "subscriptionPolicy",
  "policy": {
    "@context": "http://www.w3.org/ns/odrl.jsonld",
    "@type": "Set",
    "permission": [{
      "action": "use",
      "duty": [{
        "action": "compensate",
        "constraint": [{
          "leftOperand": "payAmount",
          "operator": "eq",
          "rightOperand": "100.00"
        }, {
          "leftOperand": "unit",
          "operator": "eq",
          "rightOperand": "http://dbpedia.org/resource/Euro"
        }, {
          "leftOperand": "recurrence",
          "operator": "eq",
          "rightOperand": "monthly"
        }]
      }]
    }]
  }
}
```

---

## 🔧 実用的なポリシー例

### **製造業データ共有ポリシー**
```json
{
  "@context": {
    "@vocab": "https://w3id.org/edc/v0.0.1/ns/",
    "odrl": "http://www.w3.org/ns/odrl/2/"
  },
  "@id": "manufacturingDataPolicy",
  "policy": {
    "@context": "http://www.w3.org/ns/odrl.jsonld",
    "@type": "Set",
    "permission": [{
      "action": "use",
      "constraint": [{
        "and": [{
          "leftOperand": "industry",
          "operator": "eq",
          "rightOperand": "automotive"
        }, {
          "leftOperand": "purpose",
          "operator": "isAnyOf",
          "rightOperand": ["quality-improvement", "predictive-maintenance"]
        }, {
          "leftOperand": "dateTime",
          "operator": "lt",
          "rightOperand": "2025-12-31T23:59:59Z"
        }]
      }]
    }],
    "prohibition": [{
      "action": "distribute",
      "constraint": [{
        "leftOperand": "recipient",
        "operator": "neq",
        "rightOperand": "original-requester"
      }]
    }],
    "obligation": [{
      "action": "delete",
      "constraint": [{
        "leftOperand": "elapsedTime",
        "operator": "eq",
        "rightOperand": "P90D"
      }]
    }, {
      "action": "notify",
      "constraint": [{
        "leftOperand": "event",
        "operator": "eq",
        "rightOperand": "data-access"
      }]
    }]
  }
}
```

### **個人データ保護ポリシー (GDPR準拠)**
```json
{
  "@context": {
    "@vocab": "https://w3id.org/edc/v0.0.1/ns/",
    "odrl": "http://www.w3.org/ns/odrl/2/"
  },
  "@id": "gdprCompliantPolicy",
  "policy": {
    "@context": "http://www.w3.org/ns/odrl.jsonld",
    "@type": "Set",
    "permission": [{
      "action": "use",
      "constraint": [{
        "and": [{
          "leftOperand": "purpose",
          "operator": "eq",
          "rightOperand": "legitimate-interest"
        }, {
          "leftOperand": "dataSubjectConsent",
          "operator": "eq",
          "rightOperand": "true"
        }, {
          "leftOperand": "spatial",
          "operator": "eq",
          "rightOperand": "https://www.geonames.org/6695072/"
        }]
      }]
    }],
    "prohibition": [{
      "action": "profile",
      "constraint": [{
        "leftOperand": "automated-decision-making",
        "operator": "eq",
        "rightOperand": "true"
      }]
    }],
    "obligation": [{
      "action": "delete",
      "constraint": [{
        "leftOperand": "event",
        "operator": "eq",
        "rightOperand": "consent-withdrawal"
      }]
    }, {
      "action": "anonymize",
      "constraint": [{
        "leftOperand": "elapsedTime",
        "operator": "eq",
        "rightOperand": "P2Y"
      }]
    }]
  }
}
```

---

## 📖 制約演算子リファレンス

### **比較演算子**
| 演算子 | 意味 | 例 |
|--------|------|-----|
| `eq` | 等しい | `"operator": "eq", "rightOperand": "research"` |
| `neq` | 等しくない | `"operator": "neq", "rightOperand": "commercial"` |
| `lt` | より小さい | `"operator": "lt", "rightOperand": "2025-12-31"` |
| `lteq` | 以下 | `"operator": "lteq", "rightOperand": "100"` |
| `gt` | より大きい | `"operator": "gt", "rightOperand": "18"` |
| `gteq` | 以上 | `"operator": "gteq", "rightOperand": "2024-01-01"` |

### **集合演算子**
| 演算子 | 意味 | 例 |
|--------|------|-----|
| `isAnyOf` | いずれかに含まれる | `"rightOperand": ["research", "education"]` |
| `isAllOf` | すべてに含まれる | `"rightOperand": ["consent", "legitimate"]` |
| `isNoneOf` | いずれにも含まれない | `"rightOperand": ["commercial", "marketing"]` |

### **論理演算子**
| 演算子 | 意味 | 例 |
|--------|------|-----|
| `and` | かつ | `"and": [constraint1, constraint2]` |
| `or` | または | `"or": [constraint1, constraint2]` |
| `xone` | 排他的論理和 | `"xone": [constraint1, constraint2]` |

---

## 🎯 ポリシーの実装と適用

### **EDCでのポリシー登録**
```bash
# 複合制約ポリシーの登録
curl -X POST "http://localhost:19193/management/v3/policydefinitions" \
     -H "Content-Type: application/json" \
     -d @complex-policy.json

# 登録確認
curl -s "http://localhost:19193/management/v3/policydefinitions/request" \
     -X POST -H "Content-Type: application/json" \
     -d '{"@context": {"@vocab": "https://w3id.org/edc/v0.0.1/ns/"}, "@type": "QuerySpec"}' \
     | jq '.[] | {id: .["@id"], policy: .policy}'
```

### **コントラクト定義での使用**
```bash
# 特定ポリシーを使用するコントラクト定義
curl -X POST "http://localhost:19193/management/v3/contractdefinitions" \
     -H "Content-Type: application/json" \
     -d '{
       "@context": { "@vocab": "https://w3id.org/edc/v0.0.1/ns/" },
       "@id": "restrictedContractDef",
       "accessPolicyId": "complexConstraintPolicy",
       "contractPolicyId": "complexConstraintPolicy", 
       "assetsSelector": [{"operandLeft": "id", "operator": "=", "operandRight": "batteryDatasetFixed"}]
     }'
```

---

## 🔍 ポリシー評価とデバッグ

### **ポリシー評価のログ確認**
EDCコネクタのログでポリシー評価結果を確認：
```
INFO PolicyEvaluator: Evaluating policy complexConstraintPolicy for asset batteryDatasetFixed
DEBUG ConstraintEvaluator: Constraint dateTime lt 2025-12-31T23:59:59Z: SATISFIED
DEBUG ConstraintEvaluator: Constraint purpose eq research: NOT_SATISFIED
INFO PolicyEvaluator: Policy evaluation result: DENIED
```

### **ポリシーテスト用のスクリプト**
```bash
#!/bin/bash
# policy-test.sh - ポリシーのテスト用スクリプト

POLICY_ID="$1"
ASSET_ID="$2"

echo "Testing policy $POLICY_ID for asset $ASSET_ID"

# カタログ取得でポリシーが適用されているか確認
OFFER=$(curl -s "http://localhost:29193/management/v3/catalog/request" \
  -X POST -H "Content-Type: application/json" \
  -d '{
    "@context": { "@vocab": "https://w3id.org/edc/v0.0.1/ns/" },
    "counterPartyAddress": "http://localhost:19194/protocol",
    "protocol": "dataspace-protocol-http"
  }' | jq ".\"dcat:dataset\" | select(.\"@id\" == \"$ASSET_ID\") | .\"odrl:hasPolicy\"")

echo "Applied policy in catalog:"
echo "$OFFER" | jq .
```

---

## 🚨 注意事項とベストプラクティス

### **ポリシー設計の原則**
1. **最小権限の原則**: 必要最小限の権限のみ付与
2. **明確な制約**: 曖昧さを避け、具体的な条件を設定
3. **監査可能性**: ログ出力とトレーサビリティを確保
4. **段階的適用**: 簡単なポリシーから徐々に複雑化

### **よくある落とし穴**
- **制約の矛盾**: permissionとprohibitionの競合
- **時間帯の考慮不足**: タイムゾーンや夏時間の処理
- **地理的制約の精度**: 座標系や行政区域の定義
- **義務の実行可能性**: 技術的に実装困難な義務の設定

### **パフォーマンスへの影響**
- **複雑な制約**: 評価時間の増加
- **外部参照**: ネットワークアクセスによる遅延
- **動的制約**: リアルタイム評価のオーバーヘッド

---

## 📚 参考資料

### **仕様書**
- [ODRL Information Model 2.2](https://www.w3.org/TR/odrl-model/)
- [ODRL Vocabulary & Expression 2.2](https://www.w3.org/TR/odrl-vocab/)
- [EDC Policy Engine Documentation](https://github.com/eclipse-edc/Connector)

### **関連標準**
- ISO/IEC 21000-5 (Rights Expression Language)
- Creative Commons License Framework
- GDPR (General Data Protection Regulation)

### **実装例**
- [Gaia-X Policy Examples](https://gaia-x.eu/)
- [Catena-X Data Space Policies](https://catena-x.net/)
- [IDSA Usage Control Patterns](https://industrialdataspace.org/)

---

このガイドを参考に、あなたのユースケースに適した柔軟で強力なポリシーを設計してください。ポリシーの複雑さと実装の実現可能性のバランスを考慮することが成功の鍵です。 