#!/bin/bash
#
# VoIP 部署公共函数库
# 提供所有部署脚本共享的函数和变量
#

# 获取脚本和项目目录
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# ============================================
# 配置加载
# ============================================

# 加载部署配置
load_config() {
    local config_file="${PROJECT_DIR}/etc/deploy.conf"
    if [ -f "$config_file" ]; then
        source "$config_file"
    else
        log_error "配置文件不存在: $config_file"
        exit 1
    fi
}

# ============================================
# 日志函数
# ============================================

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_debug() {
    if [ "$LOG_LEVEL" = "debug" ]; then
        echo -e "${BLUE}[DEBUG]${NC} $1"
    fi
}

log_step() {
    echo -e "\n${BLUE}>>> $1${NC}"
}

# ============================================
# SSH 远程执行函数
# ============================================

# 远程执行命令
# 用法: remote_exec "命令"
remote_exec() {
    local cmd="$1"
    ssh "${SSH_USER}@${SERVER}" "$cmd"
}

# 远程执行多行命令
# 用法: remote_exec_heredoc <<'ENDSSH'
#   commands here
# ENDSSH
remote_exec_heredoc() {
    ssh "${SSH_USER}@${SERVER}"
}

# 上传文件到远程
# 用法: remote_upload "本地文件" "远程路径"
remote_upload() {
    local local_file="$1"
    local remote_path="$2"
    scp "$local_file" "${SSH_USER}@${SERVER}:${remote_path}"
}

# 上传目录到远程
# 用法: remote_upload_dir "本地目录" "远程路径"
remote_upload_dir() {
    local local_dir="$1"
    local remote_path="$2"
    scp -r "$local_dir" "${SSH_USER}@${SERVER}:${remote_path}"
}

# ============================================
# Docker 网络函数
# ============================================

# 创建Docker网络(如果不存在)
ensure_docker_network() {
    log_step "检查Docker网络..."
    remote_exec "docker network create ${NETWORK_NAME} 2>/dev/null || true"
    log_info "Docker网络 ${NETWORK_NAME} 已就绪"
}

# ============================================
# 容器管理函数
# ============================================

# 停止并删除容器
# 用法: remove_container "容器名"
remove_container() {
    local container_name="$1"
    log_step "停止并删除容器 ${container_name}..."
    remote_exec "docker stop ${container_name} 2>/dev/null; docker rm ${container_name} 2>/dev/null; true"
}

# 检查容器是否运行
# 用法: is_container_running "容器名"
is_container_running() {
    local container_name="$1"
    remote_exec "docker ps -q -f name=${container_name}" | grep -q .
}

# 获取容器状态
# 用法: get_container_status "容器名"
get_container_status() {
    local container_name="$1"
    remote_exec "docker inspect -f '{{.State.Status}}' ${container_name} 2>/dev/null || echo 'not found'"
}

# 显示容器日志
# 用法: show_container_logs "容器名" [行数]
show_container_logs() {
    local container_name="$1"
    local lines="${2:-20}"
    remote_exec "docker logs --tail ${lines} ${container_name}"
}

# ============================================
# 健康检查函数
# ============================================

# MySQL 健康检查
check_mysql_healthy() {
    local host="${1:-$SERVER}"
    remote_exec "docker exec ${MYSQL_CONTAINER} mysqladmin ping -h localhost -u root -p${MYSQL_ROOT_PASSWORD} 2>/dev/null" | grep -q "alive"
}

# 等待 MySQL 就绪
wait_for_mysql() {
    local max_retries="${1:-30}"
    local retry=0

    log_info "等待 MySQL 启动..."
    while [ $retry -lt $max_retries ]; do
        if check_mysql_healthy; then
            log_info "MySQL 已就绪"
            return 0
        fi
        retry=$((retry + 1))
        sleep 2
    done

    log_error "MySQL 启动超时"
    return 1
}

# Kamailio 健康检查 (通过 JSONRPC)
check_kamailio_healthy() {
    local host="${1:-$SERVER}"
    local port="${KAMAILIO_JSONRPC_PORT:-8080}"

    # 尝试通过 JSONRPC ping
    curl -s --connect-timeout 3 "http://${host}:${port}/RPC" \
        -d '{"jsonrpc":"2.0","method":"core.ping","id":1}' 2>/dev/null | grep -q "result"
}

# Kamailio 健康检查 (通过 SIP OPTIONS)
check_kamailio_sip_healthy() {
    local host="${1:-$SERVER}"
    local port="${KAMAILIO_SIP_PORT:-5060}"

    # 使用 nc 检查端口是否开放
    nc -z -w 3 "$host" "$port" 2>/dev/null
}

# 等待 Kamailio 就绪
wait_for_kamailio() {
    local max_retries="${1:-30}"
    local retry=0

    log_info "等待 Kamailio 启动..."
    while [ $retry -lt $max_retries ]; do
        if check_kamailio_sip_healthy; then
            log_info "Kamailio 已就绪"
            return 0
        fi
        retry=$((retry + 1))
        sleep 2
    done

    log_error "Kamailio 启动超时"
    return 1
}

# FreeSWITCH 健康检查 (通过 ESL)
check_freeswitch_healthy() {
    local container="${1:-$FREESWITCH_CONTAINER}"
    remote_exec "docker exec ${container} fs_cli -x 'status' 2>/dev/null" | grep -q "UP"
}

# FreeSWITCH 健康检查 (通过端口)
check_freeswitch_port_healthy() {
    local host="${1:-$SERVER}"
    local port="${FREESWITCH_SIP_PORT:-5080}"

    nc -z -w 3 "$host" "$port" 2>/dev/null
}

# 等待 FreeSWITCH 就绪
wait_for_freeswitch() {
    local container="${1:-$FREESWITCH_CONTAINER}"
    local max_retries="${2:-30}"
    local retry=0

    log_info "等待 FreeSWITCH 启动..."
    while [ $retry -lt $max_retries ]; do
        if check_freeswitch_healthy "$container"; then
            log_info "FreeSWITCH 已就绪"
            return 0
        fi
        retry=$((retry + 1))
        sleep 2
    done

    log_error "FreeSWITCH 启动超时"
    return 1
}

# ============================================
# Kamailio JSONRPC API 函数
# ============================================

# 调用 Kamailio JSONRPC API
# 用法: kamailio_rpc "方法" ["参数JSON"]
kamailio_rpc() {
    local method="$1"
    local params="${2:-[]}"
    local host="${3:-$SERVER}"
    local port="${KAMAILIO_JSONRPC_PORT:-8080}"

    curl -s "http://${host}:${port}/RPC" \
        -H "Content-Type: application/json" \
        -d "{\"jsonrpc\":\"2.0\",\"method\":\"${method}\",\"params\":${params},\"id\":1}"
}

# 获取 Kamailio 统计信息
kamailio_get_stats() {
    kamailio_rpc "stats.get_statistics" "[\"all\"]"
}

# 获取 dispatcher 列表
kamailio_dispatcher_list() {
    kamailio_rpc "dispatcher.list"
}

# 设置 dispatcher 节点状态
# 用法: kamailio_dispatcher_set_state "状态" "组ID" "目标地址"
# 状态: a=active, i=inactive, d=disabled, p=probing
kamailio_dispatcher_set_state() {
    local state="$1"
    local group="$2"
    local destination="$3"
    kamailio_rpc "dispatcher.set_state" "[\"${state}\",${group},\"${destination}\"]"
}

# 重载 dispatcher 配置
kamailio_dispatcher_reload() {
    kamailio_rpc "dispatcher.reload"
}

# ============================================
# FreeSWITCH ESL 函数
# ============================================

# 执行 FreeSWITCH 命令
# 用法: freeswitch_exec "命令" ["容器名"]
freeswitch_exec() {
    local cmd="$1"
    local container="${2:-$FREESWITCH_CONTAINER}"
    remote_exec "docker exec ${container} fs_cli -x '${cmd}'"
}

# 获取 FreeSWITCH 状态
freeswitch_status() {
    local container="${1:-$FREESWITCH_CONTAINER}"
    freeswitch_exec "status" "$container"
}

# 获取当前通话数量
freeswitch_calls_count() {
    local container="${1:-$FREESWITCH_CONTAINER}"
    freeswitch_exec "show calls count" "$container" | grep -oP '\d+' | head -1
}

# 获取 Sofia 状态
freeswitch_sofia_status() {
    local container="${1:-$FREESWITCH_CONTAINER}"
    freeswitch_exec "sofia status" "$container"
}

# 暂停接收新呼叫 (drain 模式)
freeswitch_pause() {
    local container="${1:-$FREESWITCH_CONTAINER}"
    freeswitch_exec "fsctl pause" "$container"
    log_info "FreeSWITCH ${container} 已暂停接收新呼叫"
}

# 恢复接收呼叫
freeswitch_resume() {
    local container="${1:-$FREESWITCH_CONTAINER}"
    freeswitch_exec "fsctl resume" "$container"
    log_info "FreeSWITCH ${container} 已恢复接收呼叫"
}

# 重载 XML 配置
freeswitch_reload_xml() {
    local container="${1:-$FREESWITCH_CONTAINER}"
    freeswitch_exec "reloadxml" "$container"
}

# ============================================
# Dispatcher 数据库函数
# ============================================

# 添加 FreeSWITCH 节点到 dispatcher
# 用法: dispatcher_add_node "容器名" "SIP地址" "描述"
dispatcher_add_node() {
    local container_name="$1"
    local sip_addr="$2"
    local description="$3"

    remote_exec "docker exec ${MYSQL_CONTAINER} mysql -u${MYSQL_USER} -p${MYSQL_PASSWORD} ${MYSQL_DATABASE} \
        -e \"INSERT INTO dispatcher (setid, destination, flags, priority, attrs, description) \
             VALUES (${DISPATCHER_GROUP_ID}, '${sip_addr}', 0, 0, '', '${description}') \
             ON DUPLICATE KEY UPDATE description='${description}';\""
}

# 从 dispatcher 删除节点
# 用法: dispatcher_remove_node "SIP地址"
dispatcher_remove_node() {
    local sip_addr="$1"

    remote_exec "docker exec ${MYSQL_CONTAINER} mysql -u${MYSQL_USER} -p${MYSQL_PASSWORD} ${MYSQL_DATABASE} \
        -e \"DELETE FROM dispatcher WHERE destination='${sip_addr}';\""
}

# 列出所有 dispatcher 节点
dispatcher_list_nodes() {
    remote_exec "docker exec ${MYSQL_CONTAINER} mysql -u${MYSQL_USER} -p${MYSQL_PASSWORD} ${MYSQL_DATABASE} \
        -e \"SELECT id, setid, destination, flags, description FROM dispatcher;\""
}

# ============================================
# 帮助信息生成函数
# ============================================

# 显示通用帮助头部
show_help_header() {
    local script_name="$1"
    local description="$2"
    echo "用法: $script_name [选项]"
    echo ""
    echo "$description"
    echo ""
    echo "选项:"
}

# 显示通用帮助选项
show_help_common_options() {
    echo "  -h          显示帮助信息"
    echo "  -s SERVER   指定目标服务器地址 (默认: $DEFAULT_SERVER)"
    echo "  -u USER     指定SSH用户名 (默认: $DEFAULT_USER)"
    echo "  -p PATH     指定远程部署路径 (默认: $REMOTE_PATH)"
}

# ============================================
# 命令行参数解析
# ============================================

# 解析通用命令行参数
# 用法: parse_common_args "$@"
# 解析后设置: SERVER, SSH_USER, REMOTE_PATH
parse_common_args() {
    # 设置默认值
    SERVER="${DEFAULT_SERVER}"
    SSH_USER="${DEFAULT_USER}"

    while getopts "hs:u:p:n:y" opt; do
        case $opt in
            h)
                return 1  # 返回1表示请求帮助
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
            n)
                NODE_ID="$OPTARG"
                ;;
            y)
                AUTO_CONFIRM="yes"
                ;;
            *)
                return 2  # 返回2表示参数错误
                ;;
        esac
    done

    return 0
}

# ============================================
# 确认函数
# ============================================

# 确认操作
# 用法: confirm_action "提示信息"
confirm_action() {
    local prompt="$1"

    if [ "$AUTO_CONFIRM" = "yes" ]; then
        return 0
    fi

    read -p "$prompt (y/n): " confirm
    if [ "$confirm" != "y" ] && [ "$confirm" != "Y" ]; then
        echo "操作已取消"
        return 1
    fi
    return 0
}

# ============================================
# 部署信息显示
# ============================================

# 显示部署摘要
show_deploy_summary() {
    local service_name="$1"
    echo "========================================="
    echo "${service_name} 服务部署"
    echo "========================================="
    echo "目标服务器: ${SSH_USER}@${SERVER}"
    echo "远程路径: ${REMOTE_PATH}"
    echo "========================================="
    echo ""
}

# 显示部署完成信息
show_deploy_complete() {
    local service_name="$1"
    echo ""
    echo "========================================="
    echo "${service_name} 服务部署完成!"
    echo "========================================="
}
