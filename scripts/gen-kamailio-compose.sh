#!/bin/bash
#
# 生成Kamailio的docker-compose.yml文件
#

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
DOCKER_DIR="$PROJECT_DIR/docker"
OUTPUT_FILE="$DOCKER_DIR/kamailio-compose.yml"

# 默认配置
SIP_PORT="5060"
SIP_TLS_PORT="5061"
MYSQL_HOST="voip-mysql"
MYSQL_DATABASE="voip"
MYSQL_USER="voip"
MYSQL_PASSWORD="voip_password"

# 帮助信息
show_help() {
    echo "用法: $0 [选项]"
    echo "选项:"
    echo "  -h          显示帮助信息"
    echo "  -o FILE     指定输出文件路径 (默认: $OUTPUT_FILE)"
    echo "  -p PORT     指定SIP端口号 (默认: $SIP_PORT)"
    echo "  -m HOST     指定MySQL主机 (默认: $MYSQL_HOST)"
}

# 解析命令行参数
while getopts "ho:p:m:" opt; do
    case $opt in
        h)
            show_help
            exit 0
            ;;
        o)
            OUTPUT_FILE="$OPTARG"
            ;;
        p)
            SIP_PORT="$OPTARG"
            ;;
        m)
            MYSQL_HOST="$OPTARG"
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
  kamailio:
    image: kamailio/kamailio:5.7.2-bullseye
    container_name: voip-kamailio
    restart: unless-stopped
    environment:
      MYSQL_HOST: ${MYSQL_HOST}
      MYSQL_DATABASE: ${MYSQL_DATABASE}
      MYSQL_USER: ${MYSQL_USER}
      MYSQL_PASSWORD: ${MYSQL_PASSWORD}
    ports:
      - "${SIP_PORT}:5060/udp"
      - "${SIP_PORT}:5060/tcp"
      - "${SIP_TLS_PORT}:5061/tcp"
    volumes:
      - ./kamailio-config:/etc/kamailio
    networks:
      - voip-network
    depends_on:
      - mysql
    cap_add:
      - NET_ADMIN
      - SYS_NICE

networks:
  voip-network:
    external: true
    name: docker_voip-network
EOF

echo "Kamailio docker-compose.yml 已生成: $OUTPUT_FILE"
