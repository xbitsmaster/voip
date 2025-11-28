#!/bin/bash
#
# VoIP服务日志查看脚本
# 查看MySQL、Kamailio、FreeSWITCH的日志
#

# 加载公共函数库
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common.sh"

# 加载配置
load_config

# 日志行数
LINES=50

# 是否follow模式
FOLLOW=""

# 服务名
SERVICE=""

# 帮助信息
show_help() {
    show_help_header "$0" "查看VoIP服务日志"
    echo ""
    echo "用法: $0 [服务] [选项]"
    echo ""
    echo "服务:"
    echo "  mysql       查看MySQL日志"
    echo "  kamailio    查看Kamailio日志"
    echo "  freeswitch  查看FreeSWITCH日志 (所有节点)"
    echo "  all         查看所有服务日志"
    echo ""
    echo "选项:"
    show_help_common_options
    echo "  -n LINES    显示行数 (默认: ${LINES})"
    echo "  -f          实时跟踪日志 (follow模式)"
    echo "  --node ID   指定FreeSWITCH节点ID"
    echo ""
    echo "示例:"
    echo "  $0 mysql                    # 查看MySQL日志"
    echo "  $0 kamailio -f              # 实时跟踪Kamailio日志"
    echo "  $0 freeswitch -n 100        # 查看FreeSWITCH最后100行日志"
    echo "  $0 freeswitch --node 1      # 查看FreeSWITCH节点1日志"
    echo "  $0 all -f                   # 实时跟踪所有日志"
}

# 节点ID (可选)
NODE_ID=""

# 解析服务参数
if [ $# -gt 0 ]; then
    case "$1" in
        mysql|kamailio|freeswitch|all)
            SERVICE="$1"
            shift
            ;;
        -h|--help)
            show_help
            exit 0
            ;;
    esac
fi

# 解析命令行参数
while getopts "hs:u:p:n:f-:" opt; do
    case $opt in
        h) show_help; exit 0 ;;
        s) SERVER="$OPTARG" ;;
        u) SSH_USER="$OPTARG" ;;
        p) REMOTE_PATH="$OPTARG" ;;
        n) LINES="$OPTARG" ;;
        f) FOLLOW="-f" ;;
        -)
            case "${OPTARG}" in
                node)
                    NODE_ID="${!OPTIND}"
                    OPTIND=$((OPTIND + 1))
                    ;;
                node=*)
                    NODE_ID="${OPTARG#*=}"
                    ;;
                *) log_error "未知选项: --${OPTARG}"; exit 1 ;;
            esac
            ;;
        *) show_help; exit 1 ;;
    esac
done

# 设置默认值
SERVER="${SERVER:-$DEFAULT_SERVER}"
SSH_USER="${SSH_USER:-$DEFAULT_USER}"

# 查看MySQL日志
view_mysql_logs() {
    echo "=== MySQL 日志 (${MYSQL_CONTAINER}) ==="
    if [ -n "$FOLLOW" ]; then
        remote_exec "docker logs ${FOLLOW} --tail ${LINES} ${MYSQL_CONTAINER}"
    else
        remote_exec "docker logs --tail ${LINES} ${MYSQL_CONTAINER}"
    fi
}

# 查看Kamailio日志
view_kamailio_logs() {
    echo "=== Kamailio 日志 (${KAMAILIO_CONTAINER}) ==="
    if [ -n "$FOLLOW" ]; then
        remote_exec "docker logs ${FOLLOW} --tail ${LINES} ${KAMAILIO_CONTAINER}"
    else
        remote_exec "docker logs --tail ${LINES} ${KAMAILIO_CONTAINER}"
    fi
}

# 查看FreeSWITCH日志
view_freeswitch_logs() {
    if [ -n "$NODE_ID" ]; then
        # 查看指定节点日志
        local container="${FREESWITCH_CONTAINER}-${NODE_ID}"
        echo "=== FreeSWITCH 日志 (${container}) ==="
        if [ -n "$FOLLOW" ]; then
            remote_exec "docker logs ${FOLLOW} --tail ${LINES} ${container}"
        else
            remote_exec "docker logs --tail ${LINES} ${container}"
        fi
    else
        # 查看所有FreeSWITCH容器日志
        local containers=$(remote_exec "docker ps --filter 'name=voip-freeswitch' --format '{{.Names}}'" 2>/dev/null)

        if [ -z "$containers" ]; then
            echo "没有运行中的FreeSWITCH容器"
            return
        fi

        for container in $containers; do
            echo ""
            echo "=== FreeSWITCH 日志 (${container}) ==="
            if [ -n "$FOLLOW" ]; then
                # follow模式下只能查看一个容器
                log_warn "follow模式下只显示第一个容器的日志"
                remote_exec "docker logs ${FOLLOW} --tail ${LINES} ${container}"
                break
            else
                remote_exec "docker logs --tail ${LINES} ${container}"
            fi
        done
    fi
}

# 查看所有日志
view_all_logs() {
    if [ -n "$FOLLOW" ]; then
        # follow模式使用docker-compose logs (如果可用)
        log_warn "all + follow 模式将依次显示各服务日志"
        log_info "按 Ctrl+C 切换到下一个服务"
        echo ""

        echo "=== MySQL 日志 ==="
        timeout 10 ssh "${SSH_USER}@${SERVER}" "docker logs -f --tail ${LINES} ${MYSQL_CONTAINER}" || true

        echo ""
        echo "=== Kamailio 日志 ==="
        timeout 10 ssh "${SSH_USER}@${SERVER}" "docker logs -f --tail ${LINES} ${KAMAILIO_CONTAINER}" || true

        echo ""
        echo "=== FreeSWITCH 日志 ==="
        local containers=$(remote_exec "docker ps --filter 'name=voip-freeswitch' --format '{{.Names}}'" 2>/dev/null)
        for container in $containers; do
            timeout 10 ssh "${SSH_USER}@${SERVER}" "docker logs -f --tail ${LINES} ${container}" || true
        done
    else
        view_mysql_logs
        echo ""
        view_kamailio_logs
        echo ""
        view_freeswitch_logs
    fi
}

# 主逻辑
case "$SERVICE" in
    mysql)
        view_mysql_logs
        ;;
    kamailio)
        view_kamailio_logs
        ;;
    freeswitch)
        view_freeswitch_logs
        ;;
    all)
        view_all_logs
        ;;
    *)
        log_error "请指定服务: mysql, kamailio, freeswitch, all"
        echo ""
        show_help
        exit 1
        ;;
esac
