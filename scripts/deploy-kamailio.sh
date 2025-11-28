#!/bin/bash
#
# Kamailio服务部署脚本
# 在远程服务器上使用Docker部署Kamailio SIP代理
#

# 加载公共函数库
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common.sh"

# 加载配置
load_config

# 帮助信息
show_help() {
    show_help_header "$0" "在远程服务器上部署Kamailio Docker服务"
    show_help_common_options
    echo "  -y          跳过确认提示"
    echo ""
    echo "示例:"
    echo "  $0                          # 使用默认配置部署"
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
show_deploy_summary "Kamailio"
echo "容器名称: ${KAMAILIO_CONTAINER}"
echo "SIP UDP/TCP端口: ${KAMAILIO_SIP_PORT}"
echo "TLS端口: ${KAMAILIO_TLS_PORT}"
echo "JSONRPC端口: ${KAMAILIO_JSONRPC_PORT}"
echo "========================================="
echo ""

# 确认部署
if ! confirm_action "确认部署Kamailio服务?"; then
    exit 0
fi

# 步骤1: 创建远程目录
log_step "创建远程目录..."
remote_exec "mkdir -p ${REMOTE_PATH}/kamailio"

# 步骤2: 上传配置文件
log_step "上传配置文件..."
remote_upload "${PROJECT_DIR}/etc/kamailio/kamailio.cfg" "${REMOTE_PATH}/kamailio/"

# 步骤3: 创建Docker网络
ensure_docker_network

# 步骤4: 停止并删除旧容器
remove_container "${KAMAILIO_CONTAINER}"

# 步骤5: 启动Kamailio容器
log_step "启动Kamailio容器..."
remote_exec << ENDSSH
docker run -d \
    --name ${KAMAILIO_CONTAINER} \
    --network ${NETWORK_NAME} \
    --restart unless-stopped \
    -e MYSQL_HOST=${MYSQL_CONTAINER} \
    -e MYSQL_DATABASE=${MYSQL_DATABASE} \
    -e MYSQL_USER=${MYSQL_USER} \
    -e MYSQL_PASSWORD=${MYSQL_PASSWORD} \
    -p ${KAMAILIO_SIP_PORT}:5060/udp \
    -p ${KAMAILIO_SIP_PORT}:5060/tcp \
    -p ${KAMAILIO_TLS_PORT}:5061/tcp \
    -p ${KAMAILIO_JSONRPC_PORT}:8080/tcp \
    -v ${REMOTE_PATH}/kamailio:/etc/kamailio:ro \
    --cap-add NET_ADMIN \
    --cap-add SYS_NICE \
    ${KAMAILIO_IMAGE}
ENDSSH

if [ $? -ne 0 ]; then
    log_error "Kamailio容器启动失败"
    exit 1
fi

# 步骤6: 等待Kamailio就绪
log_info "等待Kamailio启动..."
sleep 5
wait_for_kamailio 30

# 步骤7: 显示容器状态
log_step "检查容器状态..."
remote_exec "docker ps -f name=${KAMAILIO_CONTAINER}"

log_step "检查Kamailio日志..."
show_container_logs "${KAMAILIO_CONTAINER}" 20

# 完成信息
show_deploy_complete "Kamailio"
echo "SIP服务信息:"
echo "  UDP: ${SERVER}:${KAMAILIO_SIP_PORT}"
echo "  TCP: ${SERVER}:${KAMAILIO_SIP_PORT}"
echo "  TLS: ${SERVER}:${KAMAILIO_TLS_PORT}"
echo "  JSONRPC: http://${SERVER}:${KAMAILIO_JSONRPC_PORT}/RPC"
echo ""
echo "管理命令:"
echo "  docker logs -f ${KAMAILIO_CONTAINER}"
echo "  docker exec -it ${KAMAILIO_CONTAINER} kamctl"
echo "  docker restart ${KAMAILIO_CONTAINER}"
echo ""
echo "API测试:"
echo "  curl http://${SERVER}:${KAMAILIO_JSONRPC_PORT}/RPC -d '{\"jsonrpc\":\"2.0\",\"method\":\"core.ping\",\"id\":1}'"
echo "========================================="
