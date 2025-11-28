#!/bin/bash
#
# FreeSWITCH服务部署脚本
# 在远程服务器上使用Docker部署FreeSWITCH B2BUA
#

# 加载公共函数库
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common.sh"

# 加载配置
load_config

# 帮助信息
show_help() {
    show_help_header "$0" "在远程服务器上部署FreeSWITCH Docker服务"
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
show_deploy_summary "FreeSWITCH"
echo "容器名称: ${FREESWITCH_CONTAINER}"
echo "SIP端口: ${FREESWITCH_SIP_PORT}"
echo "ESL端口: ${FREESWITCH_ESL_PORT}"
echo "========================================="
echo ""

# 确认部署
if ! confirm_action "确认部署FreeSWITCH服务?"; then
    exit 0
fi

# 步骤1: 创建远程目录
log_step "创建远程目录..."
remote_exec "mkdir -p ${REMOTE_PATH}/freeswitch/dialplan/public ${REMOTE_PATH}/freeswitch/autoload_configs ${REMOTE_PATH}/freeswitch/sip_profiles"

# 步骤2: 上传配置文件
log_step "上传配置文件..."
# 上传vars.xml
remote_upload "${PROJECT_DIR}/etc/freeswitch/vars.xml" "${REMOTE_PATH}/freeswitch/"

# 上传dialplan
if [ -f "${PROJECT_DIR}/etc/freeswitch/dialplan/public/01_kamailio_route.xml" ]; then
    remote_upload "${PROJECT_DIR}/etc/freeswitch/dialplan/public/01_kamailio_route.xml" "${REMOTE_PATH}/freeswitch/dialplan/public/"
fi

# 上传autoload_configs (如果存在)
if [ -d "${PROJECT_DIR}/etc/freeswitch/autoload_configs" ]; then
    for f in "${PROJECT_DIR}/etc/freeswitch/autoload_configs/"*; do
        [ -f "$f" ] && remote_upload "$f" "${REMOTE_PATH}/freeswitch/autoload_configs/"
    done
fi

# 上传sip_profiles (如果存在)
if [ -d "${PROJECT_DIR}/etc/freeswitch/sip_profiles" ]; then
    for f in "${PROJECT_DIR}/etc/freeswitch/sip_profiles/"*; do
        [ -f "$f" ] && remote_upload "$f" "${REMOTE_PATH}/freeswitch/sip_profiles/"
    done
fi

# 步骤3: 创建Docker网络
ensure_docker_network

# 步骤4: 停止并删除旧容器
remove_container "${FREESWITCH_CONTAINER}"

# 步骤5: 启动FreeSWITCH容器
log_step "启动FreeSWITCH容器..."
remote_exec << ENDSSH
docker run -d \
    --name ${FREESWITCH_CONTAINER} \
    --network ${NETWORK_NAME} \
    --restart unless-stopped \
    -e MYSQL_HOST=${MYSQL_CONTAINER} \
    -e MYSQL_DATABASE=${MYSQL_DATABASE} \
    -e MYSQL_USER=${MYSQL_USER} \
    -e MYSQL_PASSWORD=${MYSQL_PASSWORD} \
    -p ${FREESWITCH_SIP_PORT}:5060/udp \
    -p ${FREESWITCH_SIP_PORT}:5060/tcp \
    -p ${FREESWITCH_ESL_PORT}:8021/tcp \
    -v voip_freeswitch_data:/var/lib/freeswitch \
    -v voip_freeswitch_recordings:/var/lib/freeswitch/recordings \
    --cap-add NET_ADMIN \
    --cap-add SYS_NICE \
    ${FREESWITCH_IMAGE}
ENDSSH

if [ $? -ne 0 ]; then
    log_error "FreeSWITCH容器启动失败"
    exit 1
fi

# 步骤6: 等待FreeSWITCH启动
log_info "等待FreeSWITCH启动..."
sleep 5

# 步骤7: 复制配置到容器
log_step "复制配置到容器..."
remote_exec << ENDSSH
# 复制dialplan配置到容器
docker cp ${REMOTE_PATH}/freeswitch/dialplan/public/01_kamailio_route.xml ${FREESWITCH_CONTAINER}:/etc/freeswitch/dialplan/public/ 2>/dev/null || true

# 复制vars.xml覆盖默认配置
docker cp ${REMOTE_PATH}/freeswitch/vars.xml ${FREESWITCH_CONTAINER}:/etc/freeswitch/ 2>/dev/null || true

# 重新加载FreeSWITCH配置
docker exec ${FREESWITCH_CONTAINER} fs_cli -x "reloadxml" 2>/dev/null || true
ENDSSH

# 步骤8: 等待FreeSWITCH就绪
wait_for_freeswitch "${FREESWITCH_CONTAINER}" 30

# 步骤9: 显示容器状态
log_step "检查容器状态..."
remote_exec "docker ps -f name=${FREESWITCH_CONTAINER}"

log_step "检查FreeSWITCH日志..."
show_container_logs "${FREESWITCH_CONTAINER}" 20

# 完成信息
show_deploy_complete "FreeSWITCH"
echo "服务信息:"
echo "  SIP: ${SERVER}:${FREESWITCH_SIP_PORT}"
echo "  ESL: ${SERVER}:${FREESWITCH_ESL_PORT}"
echo "  ESL密码: ${FREESWITCH_ESL_PASSWORD}"
echo ""
echo "管理命令:"
echo "  docker logs -f ${FREESWITCH_CONTAINER}"
echo "  docker exec -it ${FREESWITCH_CONTAINER} fs_cli"
echo "  docker restart ${FREESWITCH_CONTAINER}"
echo ""
echo "常用fs_cli命令:"
echo "  status              - 查看系统状态"
echo "  show calls count    - 查看通话数量"
echo "  sofia status        - 查看SIP状态"
echo "  fsctl pause         - 暂停接收新呼叫(drain模式)"
echo "  fsctl resume        - 恢复接收呼叫"
echo "========================================="
