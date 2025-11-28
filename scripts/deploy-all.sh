#!/bin/bash
#
# VoIP全部服务统一部署脚本
# 按顺序部署 MySQL -> Kamailio -> FreeSWITCH
#

# 加载公共函数库
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common.sh"

# 加载配置
load_config

# 帮助信息
show_help() {
    show_help_header "$0" "在远程服务器上部署全部VoIP服务"
    show_help_common_options
    echo "  -y          跳过确认提示"
    echo ""
    echo "部署顺序:"
    echo "  1. MySQL     - 数据库服务"
    echo "  2. Kamailio  - SIP代理服务"
    echo "  3. FreeSWITCH - B2BUA媒体服务"
    echo ""
    echo "示例:"
    echo "  $0                          # 使用默认配置部署全部服务"
    echo "  $0 -s 192.168.1.100         # 部署到指定服务器"
    echo "  $0 -y                       # 跳过确认直接部署"
}

# 解析命令行参数
parse_common_args "$@"
case $? in
    1) show_help; exit 0 ;;
    2) show_help; exit 1 ;;
esac

# 显示部署摘要
echo "========================================="
echo "VoIP 全部服务部署"
echo "========================================="
echo "目标服务器: ${SSH_USER}@${SERVER}"
echo "远程路径: ${REMOTE_PATH}"
echo ""
echo "将按顺序部署以下服务:"
echo "  1. MySQL      (${MYSQL_CONTAINER})"
echo "  2. Kamailio   (${KAMAILIO_CONTAINER})"
echo "  3. FreeSWITCH (${FREESWITCH_CONTAINER})"
echo "========================================="
echo ""

# 确认部署
if ! confirm_action "确认部署全部VoIP服务?"; then
    exit 0
fi

# 记录开始时间
start_time=$(date +%s)

# 设置自动确认标志，传递给子脚本
export AUTO_CONFIRM="yes"

# ========================================
# 步骤1: 部署 MySQL
# ========================================
echo ""
echo "╔════════════════════════════════════════╗"
echo "║  [1/3] 部署 MySQL 数据库               ║"
echo "╚════════════════════════════════════════╝"
echo ""

"${SCRIPT_DIR}/deploy-mysql.sh" -s "${SERVER}" -u "${SSH_USER}" -p "${REMOTE_PATH}" -y

if [ $? -ne 0 ]; then
    log_error "MySQL 部署失败，停止部署"
    exit 1
fi

log_info "MySQL 部署成功"

# ========================================
# 步骤2: 部署 Kamailio
# ========================================
echo ""
echo "╔════════════════════════════════════════╗"
echo "║  [2/3] 部署 Kamailio SIP代理           ║"
echo "╚════════════════════════════════════════╝"
echo ""

"${SCRIPT_DIR}/deploy-kamailio.sh" -s "${SERVER}" -u "${SSH_USER}" -p "${REMOTE_PATH}" -y

if [ $? -ne 0 ]; then
    log_error "Kamailio 部署失败，停止部署"
    exit 1
fi

log_info "Kamailio 部署成功"

# ========================================
# 步骤3: 部署 FreeSWITCH
# ========================================
echo ""
echo "╔════════════════════════════════════════╗"
echo "║  [3/3] 部署 FreeSWITCH B2BUA           ║"
echo "╚════════════════════════════════════════╝"
echo ""

"${SCRIPT_DIR}/deploy-freeswitch.sh" -s "${SERVER}" -u "${SSH_USER}" -p "${REMOTE_PATH}" -y

if [ $? -ne 0 ]; then
    log_error "FreeSWITCH 部署失败"
    exit 1
fi

log_info "FreeSWITCH 部署成功"

# 计算耗时
end_time=$(date +%s)
duration=$((end_time - start_time))

# ========================================
# 部署完成总结
# ========================================
echo ""
echo "╔════════════════════════════════════════════════════════════╗"
echo "║                    部 署 完 成 总 结                       ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""
echo "部署耗时: ${duration} 秒"
echo ""
echo "服务状态:"
echo "  MySQL:      运行中 - ${SERVER}:${MYSQL_PORT}"
echo "  Kamailio:   运行中 - ${SERVER}:${KAMAILIO_SIP_PORT} (SIP)"
echo "  FreeSWITCH: 运行中 - ${SERVER}:${FREESWITCH_SIP_PORT} (SIP)"
echo ""
echo "管理端口:"
echo "  MySQL:      ${SERVER}:${MYSQL_PORT}"
echo "  Kamailio JSONRPC: http://${SERVER}:${KAMAILIO_JSONRPC_PORT}/RPC"
echo "  FreeSWITCH ESL:   ${SERVER}:${FREESWITCH_ESL_PORT}"
echo ""
echo "快速测试:"
echo "  # 检查 MySQL"
echo "  ssh ${SSH_USER}@${SERVER} docker exec ${MYSQL_CONTAINER} mysqladmin ping -p${MYSQL_ROOT_PASSWORD}"
echo ""
echo "  # 检查 Kamailio"
echo "  curl http://${SERVER}:${KAMAILIO_JSONRPC_PORT}/RPC -d '{\"jsonrpc\":\"2.0\",\"method\":\"core.ping\",\"id\":1}'"
echo ""
echo "  # 检查 FreeSWITCH"
echo "  ssh ${SSH_USER}@${SERVER} docker exec ${FREESWITCH_CONTAINER} fs_cli -x 'status'"
echo ""
echo "查看日志:"
echo "  ./logs.sh -s ${SERVER} all -f"
echo ""
echo "查看状态:"
echo "  ./status.sh -s ${SERVER}"
echo ""
echo "================================================================"
