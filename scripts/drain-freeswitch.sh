#!/bin/bash
#
# FreeSWITCH平滑下线脚本 (Drain Mode)
# 实现FreeSWITCH节点的优雅停机，等待现有呼叫结束后再停止服务
#

# 加载公共函数库
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common.sh"

# 加载配置
load_config

# 节点ID
NODE_ID=""

# 是否停止容器 (默认只drain不停止)
STOP_AFTER_DRAIN="no"

# 最大等待时间 (秒)
MAX_WAIT_TIME=300

# 帮助信息
show_help() {
    show_help_header "$0" "FreeSWITCH节点平滑下线 (Drain模式)"
    show_help_common_options
    echo "  -n NODE_ID  节点ID (如: 1, 2, 3)，不指定则使用默认容器"
    echo "  --stop      drain完成后停止容器"
    echo "  -t SECONDS  最大等待时间 (默认: ${MAX_WAIT_TIME}秒)"
    echo "  -y          跳过确认提示"
    echo ""
    echo "Drain流程:"
    echo "  1. 在Kamailio dispatcher中禁用该节点"
    echo "  2. FreeSWITCH暂停接收新呼叫"
    echo "  3. 等待现有呼叫结束"
    echo "  4. (可选) 停止容器"
    echo ""
    echo "示例:"
    echo "  $0                          # drain默认FreeSWITCH"
    echo "  $0 -n 1                     # drain节点1"
    echo "  $0 -n 2 --stop              # drain节点2后停止容器"
    echo "  $0 -n 1 -t 600              # drain节点1，最多等待10分钟"
}

# 解析命令行参数
while getopts "hs:u:p:n:t:y-:" opt; do
    case $opt in
        h) show_help; exit 0 ;;
        s) SERVER="$OPTARG" ;;
        u) SSH_USER="$OPTARG" ;;
        p) REMOTE_PATH="$OPTARG" ;;
        n) NODE_ID="$OPTARG" ;;
        t) MAX_WAIT_TIME="$OPTARG" ;;
        y) AUTO_CONFIRM="yes" ;;
        -)
            case "${OPTARG}" in
                stop) STOP_AFTER_DRAIN="yes" ;;
                *) log_error "未知选项: --${OPTARG}"; exit 1 ;;
            esac
            ;;
        *) show_help; exit 1 ;;
    esac
done

# 设置默认值
SERVER="${SERVER:-$DEFAULT_SERVER}"
SSH_USER="${SSH_USER:-$DEFAULT_USER}"

# 确定容器名和SIP地址
if [ -n "$NODE_ID" ]; then
    CONTAINER="${FREESWITCH_CONTAINER}-${NODE_ID}"
    SIP_ADDR="sip:${CONTAINER}:5060"
else
    CONTAINER="${FREESWITCH_CONTAINER}"
    SIP_ADDR="sip:${CONTAINER}:5060"
fi

# 显示drain信息
echo "========================================="
echo "FreeSWITCH Drain (平滑下线)"
echo "========================================="
echo "目标服务器: ${SSH_USER}@${SERVER}"
echo "容器名称: ${CONTAINER}"
echo "Dispatcher地址: ${SIP_ADDR}"
echo "最大等待时间: ${MAX_WAIT_TIME} 秒"
echo "Drain后停止: ${STOP_AFTER_DRAIN}"
echo "========================================="
echo ""

# 确认操作
if ! confirm_action "确认开始drain ${CONTAINER}?"; then
    exit 0
fi

# 步骤1: 在Kamailio中禁用该节点
log_step "步骤1: 在Kamailio dispatcher中禁用节点..."
kamailio_dispatcher_set_state "i" "${DISPATCHER_GROUP_ID}" "${SIP_ADDR}"

if [ $? -eq 0 ]; then
    log_info "节点已在dispatcher中标记为inactive"
else
    log_warn "无法设置dispatcher状态 (可能JSONRPC未启用)"
fi

# 步骤2: FreeSWITCH暂停接收新呼叫
log_step "步骤2: FreeSWITCH暂停接收新呼叫..."
freeswitch_pause "${CONTAINER}"

# 步骤3: 等待现有呼叫结束
log_step "步骤3: 等待现有呼叫结束..."

start_time=$(date +%s)
check_interval=5

while true; do
    # 获取当前通话数
    calls=$(freeswitch_calls_count "${CONTAINER}" 2>/dev/null || echo "0")
    calls=${calls:-0}

    # 检查是否所有呼叫都已结束
    if [ "$calls" -eq 0 ] 2>/dev/null; then
        log_info "所有呼叫已结束"
        break
    fi

    # 检查是否超时
    current_time=$(date +%s)
    elapsed=$((current_time - start_time))

    if [ $elapsed -ge $MAX_WAIT_TIME ]; then
        log_warn "等待超时 (${MAX_WAIT_TIME}秒)，当前仍有 ${calls} 个呼叫"
        log_warn "强制继续..."
        break
    fi

    # 显示状态
    remaining=$((MAX_WAIT_TIME - elapsed))
    echo -ne "\r当前呼叫数: ${calls}, 已等待: ${elapsed}秒, 剩余: ${remaining}秒    "

    sleep $check_interval
done

echo ""

# 步骤4: 从dispatcher中删除节点
log_step "步骤4: 从dispatcher中删除节点..."
dispatcher_remove_node "${SIP_ADDR}"
kamailio_dispatcher_reload

log_info "节点已从dispatcher中移除"

# 步骤5: 停止容器 (如果指定)
if [ "$STOP_AFTER_DRAIN" = "yes" ]; then
    log_step "步骤5: 停止容器..."
    remote_exec "docker stop ${CONTAINER}"

    if [ $? -eq 0 ]; then
        log_info "容器 ${CONTAINER} 已停止"
    else
        log_error "停止容器失败"
        exit 1
    fi
else
    log_info "容器保持运行 (暂停状态)"
    log_info "如需恢复服务，请运行: docker exec ${CONTAINER} fs_cli -x 'fsctl resume'"
fi

# 完成信息
echo ""
echo "========================================="
echo "FreeSWITCH Drain 完成"
echo "========================================="
echo "容器: ${CONTAINER}"
echo "状态: $([ "$STOP_AFTER_DRAIN" = "yes" ] && echo "已停止" || echo "已暂停")"
echo ""
echo "后续操作:"
if [ "$STOP_AFTER_DRAIN" = "yes" ]; then
    echo "  # 删除容器"
    echo "  docker rm ${CONTAINER}"
    echo ""
    echo "  # 或重新启动"
    echo "  docker start ${CONTAINER}"
else
    echo "  # 恢复服务"
    echo "  ssh ${SSH_USER}@${SERVER} docker exec ${CONTAINER} fs_cli -x 'fsctl resume'"
    echo ""
    echo "  # 重新加入dispatcher"
    echo "  ./scale-freeswitch.sh add $([ -n "$NODE_ID" ] && echo "-n ${NODE_ID}") -s ${SERVER}"
fi
echo "========================================="
