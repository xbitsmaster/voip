#!/bin/bash
#
# 生成MySQL的docker-compose.yml文件
#

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
DOCKER_DIR="$PROJECT_DIR/docker"
OUTPUT_FILE="$DOCKER_DIR/mysql-compose.yml"

# 默认配置
MYSQL_ROOT_PASSWORD="voip_root_password"
MYSQL_DATABASE="voip"
MYSQL_USER="voip"
MYSQL_PASSWORD="voip_password"
MYSQL_PORT="3306"

# 帮助信息
show_help() {
    echo "用法: $0 [选项]"
    echo "选项:"
    echo "  -h          显示帮助信息"
    echo "  -o FILE     指定输出文件路径 (默认: $OUTPUT_FILE)"
    echo "  -d DATABASE 指定数据库名称 (默认: $MYSQL_DATABASE)"
    echo "  -u USER     指定数据库用户名 (默认: $MYSQL_USER)"
    echo "  -p PORT     指定端口号 (默认: $MYSQL_PORT)"
}

# 解析命令行参数
while getopts "ho:d:u:p:" opt; do
    case $opt in
        h)
            show_help
            exit 0
            ;;
        o)
            OUTPUT_FILE="$OPTARG"
            ;;
        d)
            MYSQL_DATABASE="$OPTARG"
            ;;
        u)
            MYSQL_USER="$OPTARG"
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

# 确保docker目录存在
mkdir -p "$DOCKER_DIR"

# 检查文件是否已存在
if [ -f "$OUTPUT_FILE" ]; then
    echo "警告: 文件已存在: $OUTPUT_FILE"
    echo "为避免覆盖手工修改的配置，跳过生成。"
    echo "如需重新生成，请先删除该文件。"
    exit 0
fi

# 生成docker-compose.yml
cat > "$OUTPUT_FILE" << EOF
version: '3.8'

services:
  mysql:
    image: mysql:8.0
    container_name: voip-mysql
    restart: unless-stopped
    environment:
      MYSQL_ROOT_PASSWORD: ${MYSQL_ROOT_PASSWORD}
      MYSQL_DATABASE: ${MYSQL_DATABASE}
      MYSQL_USER: ${MYSQL_USER}
      MYSQL_PASSWORD: ${MYSQL_PASSWORD}
    ports:
      - "${MYSQL_PORT}:3306"
    volumes:
      - mysql_data:/var/lib/mysql
      - ./mysql-init:/docker-entrypoint-initdb.d
    networks:
      - voip-network
    healthcheck:
      test: ["CMD", "mysqladmin", "ping", "-h", "localhost", "-u", "root", "-p${MYSQL_ROOT_PASSWORD}"]
      interval: 10s
      timeout: 5s
      retries: 5

volumes:
  mysql_data:

networks:
  voip-network:
    driver: bridge
EOF

echo "MySQL docker-compose.yml 已生成: $OUTPUT_FILE"
