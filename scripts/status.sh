#!/bin/bash
#
# VoIP服务状态监控脚本
# 显示所有服务的运行状态和统计信息
#

# 加载公共函数库
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common.sh"

# 加载配置
load_config

# 输出格式
OUTPUT_FORMAT="text"  # text, json

# 帮助信息
show_help() {
    show_help_header "$0" "显示VoIP服务状态"
    show_help_common_options
    echo "  --json      输出JSON格式"
    echo ""
    echo "示例:"
    echo "  $0                          # 显示所有服务状态"
    echo "  $0 -s 192.168.1.100         # 显示指定服务器状态"
    echo "  $0 --json                   # JSON格式输出"
}

# 解析命令行参数
while getopts "hs:u:p:-:" opt; do
    case $opt in
        h) show_help; exit 0 ;;
        s) SERVER="$OPTARG" ;;
        u) SSH_USER="$OPTARG" ;;
        p) REMOTE_PATH="$OPTARG" ;;
        -)
            case "${OPTARG}" in
                json) OUTPUT_FORMAT="json" ;;
                *) log_error "未知选项: --${OPTARG}"; exit 1 ;;
            esac
            ;;
        *) show_help; exit 1 ;;
    esac
done

# 设置默认值
SERVER="${SERVER:-$DEFAULT_SERVER}"
SSH_USER="${SSH_USER:-$DEFAULT_USER}"

# 分隔线
print_separator() {
    echo "============================================================"
}

# 显示MySQL状态
show_mysql_status() {
    echo ""
    print_separator
    echo "                     MySQL 状态"
    print_separator

    # 容器状态
    local container_status=$(get_container_status "${MYSQL_CONTAINER}")
    echo "容器状态: ${container_status}"

    if [ "$container_status" = "running" ]; then
        # MySQL状态
        local mysql_status=$(remote_exec "docker exec ${MYSQL_CONTAINER} mysqladmin status -uroot -p${MYSQL_ROOT_PASSWORD} 2>/dev/null" || echo "无法获取")
        echo "MySQL状态: ${mysql_status}"

        # 数据库连接数
        local connections=$(remote_exec "docker exec ${MYSQL_CONTAINER} mysql -uroot -p${MYSQL_ROOT_PASSWORD} -e 'SHOW STATUS LIKE \"Threads_connected\"' 2>/dev/null | tail -1 | awk '{print \$2}'" || echo "N/A")
        echo "当前连接数: ${connections}"

        # 数据库大小
        local db_size=$(remote_exec "docker exec ${MYSQL_CONTAINER} mysql -uroot -p${MYSQL_ROOT_PASSWORD} -e \"SELECT ROUND(SUM(data_length + index_length) / 1024 / 1024, 2) AS 'Size (MB)' FROM information_schema.tables WHERE table_schema='${MYSQL_DATABASE}'\" 2>/dev/null | tail -1" || echo "N/A")
        echo "数据库大小: ${db_size} MB"
    else
        echo "服务未运行"
    fi
}

# 显示Kamailio状态
show_kamailio_status() {
    echo ""
    print_separator
    echo "                   Kamailio 状态"
    print_separator

    # 容器状态
    local container_status=$(get_container_status "${KAMAILIO_CONTAINER}")
    echo "容器状态: ${container_status}"

    if [ "$container_status" = "running" ]; then
        # SIP端口检查
        if check_kamailio_sip_healthy; then
            echo "SIP端口: 正常 (${KAMAILIO_SIP_PORT})"
        else
            echo "SIP端口: 异常"
        fi

        # JSONRPC API检查
        local ping_result=$(kamailio_rpc "core.ping" 2>/dev/null)
        if echo "$ping_result" | grep -q "pong"; then
            echo "JSONRPC API: 正常 (${KAMAILIO_JSONRPC_PORT})"

            # 获取运行时间
            local uptime=$(kamailio_rpc "core.uptime" 2>/dev/null | grep -oP '"uptime":\s*\K\d+' || echo "N/A")
            if [ "$uptime" != "N/A" ]; then
                local days=$((uptime / 86400))
                local hours=$(((uptime % 86400) / 3600))
                local mins=$(((uptime % 3600) / 60))
                echo "运行时间: ${days}天 ${hours}小时 ${mins}分钟"
            fi

            # 获取统计信息
            echo ""
            echo "统计信息:"
            local stats=$(kamailio_rpc "stats.get_statistics" '["rcv_requests", "rcv_replies", "fwd_requests", "fwd_replies"]' 2>/dev/null)
            if [ -n "$stats" ]; then
                echo "$stats" | grep -oP '"[^"]+_[^"]+"\s*:\s*\d+' | sed 's/^/  /' | head -10
            fi
        else
            echo "JSONRPC API: 不可用"
        fi

        # 注册用户数
        local reg_users=$(remote_exec "docker exec ${MYSQL_CONTAINER} mysql -u${MYSQL_USER} -p${MYSQL_PASSWORD} ${MYSQL_DATABASE} -N -e 'SELECT COUNT(*) FROM location' 2>/dev/null" || echo "N/A")
        echo ""
        echo "注册用户数: ${reg_users}"
    else
        echo "服务未运行"
    fi
}

# 显示FreeSWITCH状态
show_freeswitch_status() {
    echo ""
    print_separator
    echo "                  FreeSWITCH 状态"
    print_separator

    # 获取所有FreeSWITCH容器
    local containers=$(remote_exec "docker ps -a --filter 'name=voip-freeswitch' --format '{{.Names}}'" 2>/dev/null)

    if [ -z "$containers" ]; then
        echo "没有FreeSWITCH容器"
        return
    fi

    for container in $containers; do
        echo ""
        echo "--- ${container} ---"

        local container_status=$(remote_exec "docker inspect -f '{{.State.Status}}' ${container} 2>/dev/null" || echo "not found")
        echo "容器状态: ${container_status}"

        if [ "$container_status" = "running" ]; then
            # FreeSWITCH状态
            local fs_status=$(freeswitch_status "${container}" 2>/dev/null | grep -E "^(UP|Content-Type)" | head -1 || echo "无法获取")
            echo "服务状态: ${fs_status}"

            # 当前呼叫数
            local calls=$(freeswitch_calls_count "${container}" 2>/dev/null || echo "N/A")
            echo "当前呼叫数: ${calls}"

            # Sofia状态
            local sofia=$(freeswitch_exec "sofia status profile external" "${container}" 2>/dev/null | grep -E "^(RUNNING|CALLS)" | head -2)
            if [ -n "$sofia" ]; then
                echo "Sofia状态:"
                echo "$sofia" | sed 's/^/  /'
            fi

            # 检查是否在暂停状态
            local paused=$(freeswitch_exec "fsctl status" "${container}" 2>/dev/null | grep -i "paused" || true)
            if [ -n "$paused" ]; then
                echo "警告: 服务处于暂停状态 (drain模式)"
            fi
        fi
    done
}

# 显示Dispatcher状态
show_dispatcher_status() {
    echo ""
    print_separator
    echo "                 Dispatcher 状态"
    print_separator

    dispatcher_list_nodes 2>/dev/null || echo "无法获取dispatcher状态"
}

# 显示Docker网络状态
show_network_status() {
    echo ""
    print_separator
    echo "                  Docker网络状态"
    print_separator

    remote_exec "docker network inspect ${NETWORK_NAME} --format '{{range .Containers}}{{.Name}}: {{.IPv4Address}}{{println}}{{end}}'" 2>/dev/null || echo "网络不存在"
}

# JSON输出
output_json() {
    echo "{"

    # MySQL
    local mysql_status=$(get_container_status "${MYSQL_CONTAINER}")
    echo "  \"mysql\": {"
    echo "    \"container\": \"${MYSQL_CONTAINER}\","
    echo "    \"status\": \"${mysql_status}\""
    echo "  },"

    # Kamailio
    local kamailio_status=$(get_container_status "${KAMAILIO_CONTAINER}")
    echo "  \"kamailio\": {"
    echo "    \"container\": \"${KAMAILIO_CONTAINER}\","
    echo "    \"status\": \"${kamailio_status}\""
    echo "  },"

    # FreeSWITCH
    echo "  \"freeswitch\": ["
    local containers=$(remote_exec "docker ps -a --filter 'name=voip-freeswitch' --format '{{.Names}}'" 2>/dev/null)
    local first=true
    for container in $containers; do
        local status=$(remote_exec "docker inspect -f '{{.State.Status}}' ${container} 2>/dev/null" || echo "not found")
        local calls=$(freeswitch_calls_count "${container}" 2>/dev/null || echo "0")
        if [ "$first" = "true" ]; then
            first=false
        else
            echo ","
        fi
        echo "    {"
        echo "      \"container\": \"${container}\","
        echo "      \"status\": \"${status}\","
        echo "      \"calls\": ${calls}"
        echo -n "    }"
    done
    echo ""
    echo "  ]"

    echo "}"
}

# 主逻辑
echo ""
echo "╔════════════════════════════════════════════════════════════╗"
echo "║                  VoIP 服务状态监控                         ║"
echo "╠════════════════════════════════════════════════════════════╣"
echo "║  服务器: ${SERVER}"
echo "║  时间: $(date '+%Y-%m-%d %H:%M:%S')"
echo "╚════════════════════════════════════════════════════════════╝"

if [ "$OUTPUT_FORMAT" = "json" ]; then
    output_json
else
    show_mysql_status
    show_kamailio_status
    show_freeswitch_status
    show_dispatcher_status
    show_network_status

    echo ""
    print_separator
    echo "状态检查完成"
    print_separator
fi
