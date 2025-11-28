#!/bin/bash
#
# FreeSWITCH节点部署脚本
# 在远程服务器上部署独立的FreeSWITCH实例并注册到Kamailio dispatcher
#

# 加载公共函数库
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common.sh"

# 加载配置
load_config

# 节点ID (必须指定)
NODE_ID=""

# 帮助信息
show_help() {
    show_help_header "$0" "在远程服务器上部署FreeSWITCH节点并注册到dispatcher"
    show_help_common_options
    echo "  -n NODE_ID  节点ID (必须, 如: 1, 2, 3)"
    echo "  -y          跳过确认提示"
    echo ""
    echo "示例:"
    echo "  $0 -n 1                           # 部署节点1到默认服务器"
    echo "  $0 -n 2 -s 192.168.1.101          # 部署节点2到指定服务器"
    echo "  $0 -n 3 -s 192.168.1.102 -y       # 跳过确认部署节点3"
    echo ""
    echo "说明:"
    echo "  - 每个节点使用不同的容器名: voip-freeswitch-<NODE_ID>"
    echo "  - 端口映射: SIP=${FREESWITCH_SIP_PORT}, ESL=${FREESWITCH_ESL_PORT}"
    echo "  - 部署后自动注册到Kamailio dispatcher"
}

# 解析命令行参数
parse_common_args "$@"
case $? in
    1) show_help; exit 0 ;;
    2) show_help; exit 1 ;;
esac

# 检查必须参数
if [ -z "$NODE_ID" ]; then
    log_error "必须指定节点ID (-n)"
    echo ""
    show_help
    exit 1
fi

# 节点相关变量
NODE_CONTAINER="${FREESWITCH_CONTAINER}-${NODE_ID}"
NODE_SIP_ADDR="sip:${NODE_CONTAINER}:5060"

# 显示部署摘要
show_deploy_summary "FreeSWITCH 节点 ${NODE_ID}"
echo "容器名称: ${NODE_CONTAINER}"
echo "SIP端口: ${FREESWITCH_SIP_PORT}"
echo "ESL端口: ${FREESWITCH_ESL_PORT}"
echo "Dispatcher地址: ${NODE_SIP_ADDR}"
echo "========================================="
echo ""

# 确认部署
if ! confirm_action "确认部署FreeSWITCH节点 ${NODE_ID}?"; then
    exit 0
fi

# 步骤1: 创建远程目录
log_step "创建远程目录..."
remote_exec "mkdir -p ${REMOTE_PATH}/freeswitch-${NODE_ID}/dialplan/public ${REMOTE_PATH}/freeswitch-${NODE_ID}/autoload_configs"

# 步骤2: 上传配置文件
log_step "上传配置文件..."
remote_upload "${PROJECT_DIR}/etc/freeswitch/vars.xml" "${REMOTE_PATH}/freeswitch-${NODE_ID}/"

if [ -f "${PROJECT_DIR}/etc/freeswitch/dialplan/public/01_kamailio_route.xml" ]; then
    remote_upload "${PROJECT_DIR}/etc/freeswitch/dialplan/public/01_kamailio_route.xml" "${REMOTE_PATH}/freeswitch-${NODE_ID}/dialplan/public/"
fi

# 步骤3: 创建Docker网络
ensure_docker_network

# 步骤4: 停止并删除旧容器
remove_container "${NODE_CONTAINER}"

# 步骤5: 启动FreeSWITCH容器
log_step "启动FreeSWITCH节点容器..."
remote_exec << ENDSSH
docker run -d \
    --name ${NODE_CONTAINER} \
    --network ${NETWORK_NAME} \
    --restart unless-stopped \
    -e MYSQL_HOST=${MYSQL_CONTAINER} \
    -e MYSQL_DATABASE=${MYSQL_DATABASE} \
    -e MYSQL_USER=${MYSQL_USER} \
    -e MYSQL_PASSWORD=${MYSQL_PASSWORD} \
    -v voip_freeswitch_${NODE_ID}_data:/var/lib/freeswitch \
    -v voip_freeswitch_${NODE_ID}_recordings:/var/lib/freeswitch/recordings \
    --cap-add NET_ADMIN \
    --cap-add SYS_NICE \
    ${FREESWITCH_IMAGE}
ENDSSH

if [ $? -ne 0 ]; then
    log_error "FreeSWITCH节点容器启动失败"
    exit 1
fi

# 步骤6: 等待容器启动
log_info "等待FreeSWITCH节点启动..."
sleep 5

# 步骤7: 复制配置到容器
log_step "复制配置到容器..."
remote_exec << ENDSSH
docker cp ${REMOTE_PATH}/freeswitch-${NODE_ID}/dialplan/public/01_kamailio_route.xml ${NODE_CONTAINER}:/etc/freeswitch/dialplan/public/ 2>/dev/null || true
docker cp ${REMOTE_PATH}/freeswitch-${NODE_ID}/vars.xml ${NODE_CONTAINER}:/etc/freeswitch/ 2>/dev/null || true
docker exec ${NODE_CONTAINER} fs_cli -x "reloadxml" 2>/dev/null || true
ENDSSH

# 步骤8: 等待FreeSWITCH就绪
wait_for_freeswitch "${NODE_CONTAINER}" 30

# 步骤9: 注册到Kamailio dispatcher
log_step "注册节点到Kamailio dispatcher..."
dispatcher_add_node "${NODE_CONTAINER}" "${NODE_SIP_ADDR}" "FreeSWITCH Node ${NODE_ID}"

# 步骤10: 通知Kamailio重载dispatcher
log_step "通知Kamailio重载dispatcher..."
kamailio_dispatcher_reload

# 步骤11: 显示容器状态
log_step "检查容器状态..."
remote_exec "docker ps -f name=${NODE_CONTAINER}"

# 步骤12: 显示dispatcher列表
log_step "当前dispatcher节点列表..."
dispatcher_list_nodes

# 完成信息
show_deploy_complete "FreeSWITCH 节点 ${NODE_ID}"
echo "节点信息:"
echo "  容器名: ${NODE_CONTAINER}"
echo "  网络地址: ${NODE_SIP_ADDR}"
echo "  所属dispatcher组: ${DISPATCHER_GROUP_ID}"
echo ""
echo "管理命令:"
echo "  docker logs -f ${NODE_CONTAINER}"
echo "  docker exec -it ${NODE_CONTAINER} fs_cli"
echo ""
echo "Drain模式:"
echo "  ./drain-freeswitch.sh -n ${NODE_ID} -s ${SERVER}"
echo "========================================="
