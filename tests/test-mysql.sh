#!/bin/bash
#
# 测试MySQL服务器是否部署成功
#

# 默认配置
DEFAULT_SERVER="192.168.139.149"
MYSQL_PORT="3306"
MYSQL_USER="voip"
MYSQL_PASSWORD="voip_password"
MYSQL_DATABASE="voip"

SERVER="$DEFAULT_SERVER"

# 帮助信息
show_help() {
    echo "用法: $0 [选项]"
    echo "选项:"
    echo "  -h          显示帮助信息"
    echo "  -s SERVER   指定目标服务器 (默认: $DEFAULT_SERVER)"
    echo "  -p PORT     指定MySQL端口 (默认: $MYSQL_PORT)"
}

# 解析命令行参数
while getopts "hs:p:" opt; do
    case $opt in
        h)
            show_help
            exit 0
            ;;
        s)
            SERVER="$OPTARG"
            ;;
        p)
            MYSQL_PORT="$OPTARG"
            ;;
        *)
            show_help
            exit 1
            ;;
    esac
done

echo "========================================="
echo "MySQL 服务测试"
echo "========================================="
echo "服务器: $SERVER:$MYSQL_PORT"
echo "========================================="
echo ""

# 测试1: 端口连通性
echo ">>> 测试1: 检查端口连通性..."
nc -zv "$SERVER" "$MYSQL_PORT" 2>&1
if [ $? -eq 0 ]; then
    echo "✓ 端口 $MYSQL_PORT 可访问"
else
    echo "✗ 端口 $MYSQL_PORT 不可访问"
    exit 1
fi
echo ""

# 测试2: MySQL连接
echo ">>> 测试2: 测试MySQL连接..."
if command -v mysql &> /dev/null; then
    mysql -h "$SERVER" -P "$MYSQL_PORT" -u "$MYSQL_USER" -p"$MYSQL_PASSWORD" -e "SELECT 1" 2>/dev/null
    if [ $? -eq 0 ]; then
        echo "✓ MySQL连接成功"
    else
        echo "✗ MySQL连接失败"
        exit 1
    fi
else
    echo "! mysql客户端未安装，跳过连接测试"
fi
echo ""

# 测试3: 数据库存在性
echo ">>> 测试3: 检查数据库..."
if command -v mysql &> /dev/null; then
    result=$(mysql -h "$SERVER" -P "$MYSQL_PORT" -u "$MYSQL_USER" -p"$MYSQL_PASSWORD" -e "SHOW DATABASES LIKE '$MYSQL_DATABASE'" 2>/dev/null)
    if echo "$result" | grep -q "$MYSQL_DATABASE"; then
        echo "✓ 数据库 $MYSQL_DATABASE 存在"
    else
        echo "✗ 数据库 $MYSQL_DATABASE 不存在"
        exit 1
    fi
fi
echo ""

echo "========================================="
echo "MySQL 服务测试完成"
echo "========================================="
