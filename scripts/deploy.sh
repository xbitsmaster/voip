#!/bin/bash
#
# 远程部署脚本
# 将docker-compose.yml文件部署到目标服务器
#

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

# 默认配置
DEFAULT_SERVER="192.168.139.149"
DEFAULT_USER="root"
DEFAULT_SERVICE_USER="voip"
DEFAULT_COMPOSE_FILE=""
DEFAULT_REMOTE_PATH="/opt/voip"

SERVER="$DEFAULT_SERVER"
SSH_USER="$DEFAULT_USER"
SERVICE_USER="$DEFAULT_SERVICE_USER"
COMPOSE_FILE="$DEFAULT_COMPOSE_FILE"
REMOTE_PATH="$DEFAULT_REMOTE_PATH"

# 帮助信息
show_help() {
    echo "用法: $0 [选项]"
    echo ""
    echo "远程部署VoIP服务器的docker-compose配置"
    echo ""
    echo "选项:"
    echo "  -h          显示帮助信息"
    echo "  -c FILE     指定docker-compose.yml文件路径"
    echo "  -s SERVER   指定目标服务器信息 (默认: $DEFAULT_SERVER)"
    echo "  -u USER     指定SSH用户名 (默认: $DEFAULT_USER)"
    echo "  -p PATH     指定远程服务器上的部署路径 (默认: $DEFAULT_REMOTE_PATH)"
    echo ""
    echo "示例:"
    echo "  $0 -c docker/mysql-compose.yml"
    echo "  $0 -c docker/mysql-compose.yml -s 192.168.1.100"
    echo "  $0 -c docker/kamailio-compose.yml -s user@192.168.1.100"
}

# 解析命令行参数
while getopts "hc:s:u:p:" opt; do
    case $opt in
        h)
            show_help
            exit 0
            ;;
        c)
            COMPOSE_FILE="$OPTARG"
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

# 检查必要参数
if [ -z "$COMPOSE_FILE" ]; then
    echo "错误: 请使用 -c 指定docker-compose.yml文件路径"
    show_help
    exit 1
fi

if [ ! -f "$COMPOSE_FILE" ]; then
    # 尝试在项目目录下查找
    if [ -f "$PROJECT_DIR/$COMPOSE_FILE" ]; then
        COMPOSE_FILE="$PROJECT_DIR/$COMPOSE_FILE"
    else
        echo "错误: 文件不存在: $COMPOSE_FILE"
        exit 1
    fi
fi

# 获取compose文件的基本名称
COMPOSE_BASENAME=$(basename "$COMPOSE_FILE")
SERVICE_NAME="${COMPOSE_BASENAME%-compose.yml}"

echo "========================================="
echo "VoIP 远程部署脚本"
echo "========================================="
echo "目标服务器: $SSH_USER@$SERVER"
echo "Compose文件: $COMPOSE_FILE"
echo "服务名称: $SERVICE_NAME"
echo "远程路径: $REMOTE_PATH"
echo "服务用户: $SERVICE_USER"
echo "========================================="
echo ""

# 确认部署
read -p "确认部署? (y/n): " confirm
if [ "$confirm" != "y" ] && [ "$confirm" != "Y" ]; then
    echo "部署已取消"
    exit 0
fi

echo ""
echo ">>> 步骤1: 检查并创建服务用户 $SERVICE_USER..."
ssh "$SSH_USER@$SERVER" << ENDSSH
    # 检查用户是否存在
    if ! id "$SERVICE_USER" &>/dev/null; then
        echo "创建用户 $SERVICE_USER..."
        useradd -m -s /bin/bash "$SERVICE_USER"
        usermod -aG docker "$SERVICE_USER"
        echo "用户 $SERVICE_USER 创建成功"
    else
        echo "用户 $SERVICE_USER 已存在"
        # 确保用户在docker组中
        usermod -aG docker "$SERVICE_USER" 2>/dev/null || true
    fi
ENDSSH

if [ $? -ne 0 ]; then
    echo "错误: 创建服务用户失败"
    exit 1
fi

echo ""
echo ">>> 步骤2: 创建远程目录结构..."
ssh "$SSH_USER@$SERVER" << ENDSSH
    mkdir -p "$REMOTE_PATH/$SERVICE_NAME"
    chown -R "$SERVICE_USER:$SERVICE_USER" "$REMOTE_PATH"
ENDSSH

if [ $? -ne 0 ]; then
    echo "错误: 创建远程目录失败"
    exit 1
fi

echo ""
echo ">>> 步骤3: 上传compose文件..."
scp "$COMPOSE_FILE" "$SSH_USER@$SERVER:$REMOTE_PATH/$SERVICE_NAME/docker-compose.yml"

if [ $? -ne 0 ]; then
    echo "错误: 上传文件失败"
    exit 1
fi

# 上传相关配置文件
CONFIG_DIR="$PROJECT_DIR/etc/$SERVICE_NAME"
if [ -d "$CONFIG_DIR" ]; then
    echo ""
    echo ">>> 步骤4: 上传配置文件..."
    scp -r "$CONFIG_DIR" "$SSH_USER@$SERVER:$REMOTE_PATH/$SERVICE_NAME/config"
fi

echo ""
echo ">>> 步骤5: 设置文件权限..."
ssh "$SSH_USER@$SERVER" << ENDSSH
    chown -R "$SERVICE_USER:$SERVICE_USER" "$REMOTE_PATH/$SERVICE_NAME"
ENDSSH

echo ""
echo ">>> 步骤6: 启动服务..."
ssh "$SSH_USER@$SERVER" << ENDSSH
    cd "$REMOTE_PATH/$SERVICE_NAME"

    # 使用voip用户运行docker-compose
    sudo -u "$SERVICE_USER" docker-compose pull
    sudo -u "$SERVICE_USER" docker-compose up -d

    echo ""
    echo "服务状态:"
    sudo -u "$SERVICE_USER" docker-compose ps
ENDSSH

if [ $? -ne 0 ]; then
    echo "错误: 启动服务失败"
    exit 1
fi

echo ""
echo "========================================="
echo "部署完成!"
echo "========================================="
echo "服务已部署到: $SSH_USER@$SERVER:$REMOTE_PATH/$SERVICE_NAME"
echo ""
echo "管理命令:"
echo "  ssh $SSH_USER@$SERVER"
echo "  cd $REMOTE_PATH/$SERVICE_NAME"
echo "  sudo -u $SERVICE_USER docker-compose logs -f"
echo "  sudo -u $SERVICE_USER docker-compose restart"
echo "  sudo -u $SERVICE_USER docker-compose down"
echo "========================================="
