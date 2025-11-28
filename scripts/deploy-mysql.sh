#!/bin/bash
#
# MySQL服务部署脚本
# 在远程服务器上使用Docker部署MySQL服务
#

# 加载公共函数库
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common.sh"

# 加载配置
load_config

# 帮助信息
show_help() {
    show_help_header "$0" "在远程服务器上部署MySQL Docker服务"
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
show_deploy_summary "MySQL"
echo "容器名称: ${MYSQL_CONTAINER}"
echo "MySQL端口: ${MYSQL_PORT}"
echo "数据库: ${MYSQL_DATABASE}"
echo "========================================="
echo ""

# 确认部署
if ! confirm_action "确认部署MySQL服务?"; then
    exit 0
fi

# 步骤1: 创建远程目录
log_step "创建远程目录..."
remote_exec "mkdir -p ${REMOTE_PATH}/mysql/init"

# 步骤2: 上传配置文件
log_step "上传配置文件..."
remote_upload "${PROJECT_DIR}/etc/mysql/init.sql" "${REMOTE_PATH}/mysql/init/"

# 步骤3: 创建Docker网络
ensure_docker_network

# 步骤4: 停止并删除旧容器
remove_container "${MYSQL_CONTAINER}"

# 步骤5: 启动MySQL容器
log_step "启动MySQL容器..."
remote_exec << ENDSSH
docker run -d \
    --name ${MYSQL_CONTAINER} \
    --network ${NETWORK_NAME} \
    --restart unless-stopped \
    -e MYSQL_ROOT_PASSWORD=${MYSQL_ROOT_PASSWORD} \
    -e MYSQL_DATABASE=${MYSQL_DATABASE} \
    -e MYSQL_USER=${MYSQL_USER} \
    -e MYSQL_PASSWORD=${MYSQL_PASSWORD} \
    -p ${MYSQL_PORT}:3306 \
    -v voip_mysql_data:/var/lib/mysql \
    -v ${REMOTE_PATH}/mysql/init:/docker-entrypoint-initdb.d:ro \
    ${MYSQL_IMAGE}
ENDSSH

if [ $? -ne 0 ]; then
    log_error "MySQL容器启动失败"
    exit 1
fi

# 步骤6: 等待MySQL就绪
wait_for_mysql 30

# 步骤7: 显示容器状态
log_step "检查容器状态..."
remote_exec "docker ps -f name=${MYSQL_CONTAINER}"

# 完成信息
show_deploy_complete "MySQL"
echo "连接信息:"
echo "  主机: ${SERVER}:${MYSQL_PORT}"
echo "  数据库: ${MYSQL_DATABASE}"
echo "  用户: ${MYSQL_USER}"
echo "  密码: ${MYSQL_PASSWORD}"
echo ""
echo "管理命令:"
echo "  docker logs ${MYSQL_CONTAINER}"
echo "  docker exec -it ${MYSQL_CONTAINER} mysql -u${MYSQL_USER} -p${MYSQL_PASSWORD} ${MYSQL_DATABASE}"
echo "========================================="
