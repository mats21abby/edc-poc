#!/bin/bash

# SPARQLクエリテストスクリプト
# Usage: ./test-sparql-queries.sh [query-file] [endpoint-type]

set -e

QUERY_FILE="$1"
ENDPOINT_TYPE="${2:-both}"  # direct, edc, both

# エンドポイント設定
FUSEKI_ENDPOINT="http://localhost:3030/battery_dataset/query"
EDC_ENDPOINT="$EDR_ENDPOINT"
AUTH_KEY="$EDR_AUTH_KEY"

# 色付きログ
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
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

log_step() {
    echo -e "${BLUE}[STEP]${NC} $1"
}

# 使用方法の表示
usage() {
    echo "Usage: $0 [query-file] [endpoint-type]"
    echo ""
    echo "Arguments:"
    echo "  query-file    : SPARQLクエリファイル (.sparql)"
    echo "  endpoint-type : direct, edc, both (default: both)"
    echo ""
    echo "Examples:"
    echo "  $0 sample-sparql-queries/basic-queries.sparql"
    echo "  $0 sample-sparql-queries/advanced-queries.sparql edc"
    echo ""
    echo "Available sample queries:"
    echo "  - sample-sparql-queries/basic-queries.sparql"
    echo "  - sample-sparql-queries/advanced-queries.sparql"
    exit 1
}

# 引数チェック
if [ -z "$QUERY_FILE" ]; then
    log_error "クエリファイルが指定されていません"
    usage
fi

if [ ! -f "$QUERY_FILE" ]; then
    log_error "クエリファイル '$QUERY_FILE' が見つかりません"
    exit 1
fi

# 単一クエリの実行
execute_query() {
    local query="$1"
    local endpoint="$2"
    local auth_header="$3"
    local endpoint_name="$4"
    
    log_step "Executing query via $endpoint_name"
    echo "Query:"
    echo "$query"
    echo ""
    
    local start_time=$(date +%s.%N)
    
    local response=$(curl -s -X POST \
        $auth_header \
        -H "Content-Type: application/sparql-query" \
        --data "$query" \
        "$endpoint")
    
    local end_time=$(date +%s.%N)
    local duration=$(echo "$end_time - $start_time" | bc 2>/dev/null || echo "N/A")
    
    # レスポンスの確認
    if echo "$response" | jq . >/dev/null 2>&1; then
        log_info "✅ Query successful (${duration}s)"
        
        # 結果の概要を表示
        local result_count=$(echo "$response" | jq -r '.results.bindings | length' 2>/dev/null || echo "N/A")
        local vars=$(echo "$response" | jq -r '.head.vars | join(", ")' 2>/dev/null || echo "N/A")
        
        echo "Results: $result_count rows"
        echo "Variables: $vars"
        
        # 最初の3行を表示
        echo "Sample results:"
        echo "$response" | jq -r '.results.bindings[0:3][] | to_entries | map("\(.key): \(.value.value)") | join(", ")' 2>/dev/null || echo "N/A"
        
    else
        log_error "❌ Query failed"
        echo "Response: $response"
    fi
    
    echo "---"
}

# クエリファイルの解析と実行
parse_and_execute_queries() {
    local query_file="$1"
    local current_query=""
    local query_number=0
    
    while IFS= read -r line; do
        # コメント行の処理
        if [[ "$line" =~ ^#.*$ ]]; then
            # 前のクエリがあれば実行
            if [ -n "$current_query" ]; then
                query_number=$((query_number + 1))
                echo "=================================="
                echo "🔍 Query #$query_number"
                echo "=================================="
                
                # 直接Fusekiエンドポイント
                if [ "$ENDPOINT_TYPE" = "direct" ] || [ "$ENDPOINT_TYPE" = "both" ]; then
                    execute_query "$current_query" "$FUSEKI_ENDPOINT" "" "Direct Fuseki"
                fi
                
                # EDCプロキシ経由
                if [ "$ENDPOINT_TYPE" = "edc" ] || [ "$ENDPOINT_TYPE" = "both" ]; then
                    if [ -n "$EDC_ENDPOINT" ] && [ -n "$AUTH_KEY" ]; then
                        execute_query "$current_query" "$EDC_ENDPOINT" "-H 'Authorization: Bearer $AUTH_KEY'" "EDC Proxy"
                    else
                        log_warn "EDC endpoint or auth key not configured, skipping EDC test"
                    fi
                fi
                
                current_query=""
            fi
            continue
        fi
        
        # 空行をスキップ
        if [[ -z "$line" ]]; then
            continue
        fi
        
        # クエリ行の追加
        if [ -n "$current_query" ]; then
            current_query="$current_query"$'\n'"$line"
        else
            current_query="$line"
        fi
        
    done < "$query_file"
    
    # 最後のクエリを実行
    if [ -n "$current_query" ]; then
        query_number=$((query_number + 1))
        echo "=================================="
        echo "🔍 Query #$query_number"
        echo "=================================="
        
        # 直接Fusekiエンドポイント
        if [ "$ENDPOINT_TYPE" = "direct" ] || [ "$ENDPOINT_TYPE" = "both" ]; then
            execute_query "$current_query" "$FUSEKI_ENDPOINT" "" "Direct Fuseki"
        fi
        
        # EDCプロキシ経由
        if [ "$ENDPOINT_TYPE" = "edc" ] || [ "$ENDPOINT_TYPE" = "both" ]; then
            if [ -n "$EDC_ENDPOINT" ] && [ -n "$AUTH_KEY" ]; then
                execute_query "$current_query" "$EDC_ENDPOINT" "-H 'Authorization: Bearer $AUTH_KEY'" "EDC Proxy"
            else
                log_warn "EDC endpoint or auth key not configured, skipping EDC test"
            fi
        fi
    fi
}

echo "🧪 SPARQL クエリテスト"
echo "======================"
echo "Query file: $QUERY_FILE"
echo "Endpoint type: $ENDPOINT_TYPE"
echo ""

# bcコマンドの存在確認
if ! command -v bc &> /dev/null; then
    log_warn "bc command not found, execution time will not be measured"
fi

# jqコマンドの存在確認
if ! command -v jq &> /dev/null; then
    log_error "jq command is required but not found"
    exit 1
fi

# クエリの実行
parse_and_execute_queries "$QUERY_FILE"

echo ""
echo "🎉 すべてのクエリテストが完了しました！"
echo ""
echo "📝 次のステップ:"
echo "  1. クエリ結果を分析してデータの理解を深める"
echo "  2. 複雑なクエリでパフォーマンスを測定"
echo "  3. カスタムクエリを作成して特定の分析を実行" 