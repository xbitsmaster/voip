#!/bin/bash
#
# FreeSWITCH扩缩容脚本
# 添加或移除FreeSWITCH节点
#

# 加载公共函数库
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common.sh"

# 加载配置
load_config

# 操作类型
ACTION=""

# 节点ID
NODE_ID=""

# 帮助信息
show_help() {
    show_help_header "$0" "FreeSWITCH扩缩容管理"
    echo ""
    echo "用法: $0 <action> [选项]"
    echo ""
    echo "操作:"
    echo "  add         添加新的FreeSWITCH节点"
    echo "  remove      移除FreeSWITCH节点 (会先执行drain)"
    echo "  list        列出所有FreeSWITCH节点"
    echo "  status      显示所有节点状态"
    echo ""
    echo "选项:"
    show_help_common_options
    echo "  -n NODE_ID  节点ID (add/remove时必须)"
    echo "  -y          跳过确认提示"
    echo ""
    echo "示例:"
    echo "  $0 add -n 2                     # 添加节点2"
    echo "  $0 add -n 3 -s 192.168.1.102    # 在指定服务器上添加节点3"
    echo "  $0 remove -n 2                  # 移除节点2 (先drain)"
    echo "  $0 list                         # 列出所有节点"
    echo "  $0 status                       # 显示节点状态"
}

# 检查第一个参数是否为操作
if [ $# -gt 0 ]; then
    case "$1" in
        add|remove|list|status)
            ACTION="$1"
            shift
            ;;
        -h|--help)
            show_help
            exit 0
            ;;
    esac
fi

# 解析命令行参数
parse_common_args "$@"
case $? in
    1) show_help; exit 0 ;;
    2) show_help; exit 1 ;;
esac

# 设置默认值
SERVER="${SERVER:-$DEFAULT_SERVER}"
SSH_USER="${SSH_USER:-$DEFAULT_USER}"

# 添加节点
do_add() {
    if [ -z "$NODE_ID" ]; then
        log_error "添加节点时必须指定节点ID (-n)"
        exit 1
    fi

    log_info "添加FreeSWITCH节点 ${NODE_ID}..."

    # 调用节点部署脚本
    "${SCRIPT_DIR}/deploy-freeswitch-node.sh" \
        -n "${NODE_ID}" \
        -s "${SERVER}" \
        -u "${SSH_USER}" \
        -p "${REMOTE_PATH}" \
        ${AUTO_CONFIRM:+-y}

    return $?
}

# 移除节点
do_remove() {
    if [ -z "$NODE_ID" ]; then
        log_error "移除节点时必须指定节点ID (-n)"
        exit 1
    fi

    local container="${FREESWITCH_CONTAINER}-${NODE_ID}"
    local sip_addr="sip:${container}:5060"

    echo "========================================="
    echo "移除FreeSWITCH节点 ${NODE_ID}"
    echo "========================================="
    echo "容器: ${container}"
    echo "服务器: ${SERVER}"
    echo "========================================="

    if ! confirm_action "确认移除节点 ${NODE_ID}? (将执行drain操作)"; then
        exit 0
    fi

    # 执行drain
    log_step "执行drain操作..."
    "${SCRIPT_DIR}/drain-freeswitch.sh" \
        -n "${NODE_ID}" \
        -s "${SERVER}" \
        -u "${SSH_USER}" \
        --stop \
        -y

    if [ $? -ne 0 ]; then
        log_error "drain操作失败"
        exit 1
    fi

    # 删除容器
    log_step "删除容器..."
    remote_exec "docker rm ${container} 2>/dev/null || true"

    # 清理volume (可选)
    log_step "清理数据卷..."
    remote_exec "docker volume rm voip_freeswitch_${NODE_ID}_data 2>/dev/null || true"
    remote_exec "docker volume rm voip_freeswitch_${NODE_ID}_recordings 2>/dev/null || true"

    log_info "节点 ${NODE_ID} 已移除"
}

# 列出所有节点
do_list() {
    echo "========================================="
    echo "Dispatcher节点列表"
    echo "========================================="
    dispatcher_list_nodes
    echo ""

    echo "========================================="
    echo "运行中的FreeSWITCH容器"
    echo "========================================="
    remote_exec "docker ps --filter 'name=voip-freeswitch' --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}'"
}

# 显示节点状态
do_status() {
    echo "========================================="
    echo "FreeSWITCH节点状态"
    echo "========================================="
    echo ""

    # 获取所有FreeSWITCH容器
    containers=$(remote_exec "docker ps --filter 'name=voip-freeswitch' --format '{{.Names}}'")

    if [ -z "$containers" ]; then
        log_warn "没有运行中的FreeSWITCH容器"
        return
    fi

    for container in $containers; do
        echo "--- ${container} ---"

        # 容器状态
        status=$(remote_exec "docker inspect -f '{{.State.Status}}' ${container} 2>/dev/null")
        echo "容器状态: ${status}"

        # FreeSWITCH状态
        fs_status=$(freeswitch_status "${container}" 2>/dev/null | head -3)
        echo "FreeSWITCH状态:"
        echo "$fs_status" | sed 's/^/  /'

        # 当前呼叫数
        calls=$(freeswitch_calls_count "${container}" 2>/dev/null || echo "N/A")
        echo "当前呼叫数: ${calls}"

        echo ""
    done

    # Dispatcher状态
    echo "========================================="
    echo "Kamailio Dispatcher状态"
    echo "========================================="
    dispatcher_list_nodes
}

# 主逻辑
case "$ACTION" in
    add)
        do_add
        ;;
    remove)
        do_remove
        ;;
    list)
        do_list
        ;;
    status)
        do_status
        ;;
    *)
        log_error "请指定操作: add, remove, list, status"
        echo ""
        show_help
        exit 1
        ;;
esac
