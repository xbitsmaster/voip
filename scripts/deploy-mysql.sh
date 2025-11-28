#!/bin/bash
#
# MySQL服务部署脚本
# 在远程服务器上使用Docker部署MySQL服务
#

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

# 默认配置
DEFAULT_SERVER="192.168.139.149"
DEFAULT_USER="root"
DEFAULT_REMOTE_PATH="/opt/voip"
CONTAINER_NAME="voip-mysql"
NETWORK_NAME="voip-network"

SERVER="$DEFAULT_SERVER"
SSH_USER="$DEFAULT_USER"
REMOTE_PATH="$DEFAULT_REMOTE_PATH"

# 帮助信息
show_help() {
    echo "用法: $0 [选项]"
    echo ""
    echo "在远程服务器上部署MySQL Docker服务"
    echo ""
    echo "选项:"
    echo "  -h          显示帮助信息"
    echo "  -s SERVER   指定目标服务器地址 (默认: $DEFAULT_SERVER)"
    echo "  -u USER     指定SSH用户名 (默认: $DEFAULT_USER)"
    echo "  -p PATH     指定远程部署路径 (默认: $DEFAULT_REMOTE_PATH)"
    echo ""
    echo "示例:"
    echo "  $0                          # 使用默认配置部署"
    echo "  $0 -s 192.168.1.100         # 部署到指定服务器"
}

# 解析命令行参数
while getopts "hs:u:p:" opt; do
    case $opt in
        h)
            show_help
            exit 0
            ;;
        s)
            SERVER="$OPTARG"
            ;;
        u)
            SSH_USER="$OPTARG"
            ;;
        p)
            REMOTE_PATH="$OPTARG"
            ;;
        *)
            show_help
            exit 1
            ;;
    esac
done

echo "========================================="
echo "MySQL 服务部署"
echo "========================================="
echo "目标服务器: $SSH_USER@$SERVER"
echo "远程路径: $REMOTE_PATH"
echo "容器名称: $CONTAINER_NAME"
echo "========================================="
echo ""

# 确认部署
read -p "确认部署MySQL服务? (y/n): " confirm
if [ "$confirm" != "y" ] && [ "$confirm" != "Y" ]; then
    echo "部署已取消"
    exit 0
fi

echo ""
echo ">>> 步骤1: 创建远程目录..."
ssh "$SSH_USER@$SERVER" "mkdir -p $REMOTE_PATH/mysql/init"

echo ""
echo ">>> 步骤2: 上传配置文件..."
scp "$PROJECT_DIR/etc/mysql/init.sql" "$SSH_USER@$SERVER:$REMOTE_PATH/mysql/init/"

echo ""
echo ">>> 步骤3: 创建Docker网络(如果不存在)..."
ssh "$SSH_USER@$SERVER" "docker network create $NETWORK_NAME 2>/dev/null || true"

echo ""
echo ">>> 步骤4: 停止并删除旧容器(如果存在)..."
ssh "$SSH_USER@$SERVER" "docker stop $CONTAINER_NAME 2>/dev/null; docker rm $CONTAINER_NAME 2>/dev/null; true"

echo ""
echo ">>> 步骤5: 启动MySQL容器..."
ssh "$SSH_USER@$SERVER" << ENDSSH
docker run -d \
    --name $CONTAINER_NAME \
    --network $NETWORK_NAME \
    --restart unless-stopped \
    -e MYSQL_ROOT_PASSWORD=voip_root_password \
    -e MYSQL_DATABASE=voip \
    -e MYSQL_USER=voip \
    -e MYSQL_PASSWORD=voip_password \
    -p 3306:3306 \
    -v voip_mysql_data:/var/lib/mysql \
    -v $REMOTE_PATH/mysql/init:/docker-entrypoint-initdb.d:ro \
    mysql:8.0

echo ""
echo "等待MySQL启动..."
sleep 10

echo ""
echo "检查容器状态:"
docker ps -f name=$CONTAINER_NAME
ENDSSH

if [ $? -ne 0 ]; then
    echo "错误: 部署失败"
    exit 1
fi

echo ""
echo "========================================="
echo "MySQL服务部署完成!"
echo "========================================="
echo "连接信息:"
echo "  主机: $SERVER:3306"
echo "  数据库: voip"
echo "  用户: voip"
echo "  密码: voip_password"
echo ""
echo "管理命令:"
echo "  docker logs $CONTAINER_NAME"
echo "  docker exec -it $CONTAINER_NAME mysql -uvoip -pvoip_password voip"
echo "========================================="
