#!/bin/bash
#
# pjsua Callee脚本
# 使用100134002@voip.com注册并等待来电
#

# 默认配置
DEFAULT_SERVER="192.168.139.149"
SIP_PORT="5060"
CALLEE_USER="100134002"
CALLEE_DOMAIN="voip.com"
CALLEE_PASSWORD="voip"
LOCAL_PORT="5064"

SERVER="$DEFAULT_SERVER"
AUTO_ANSWER=true

# 帮助信息
show_help() {
    echo "用法: $0 [选项]"
    echo ""
    echo "pjsua Callee - 使用100134002注册并等待来电"
    echo ""
    echo "选项:"
    echo "  -h          显示帮助信息"
    echo "  -s SERVER   指定SIP服务器地址 (默认: $DEFAULT_SERVER)"
    echo "  -m          手动接听模式 (默认自动接听)"
    echo ""
    echo "示例:"
    echo "  $0              # 自动接听模式"
    echo "  $0 -m           # 手动接听模式"
}

# 解析命令行参数
while getopts "hs:m" opt; do
    case $opt in
        h)
            show_help
            exit 0
            ;;
        s)
            SERVER="$OPTARG"
            ;;
        m)
            AUTO_ANSWER=false
            ;;
        *)
            show_help
            exit 1
            ;;
    esac
done

echo "========================================="
echo "pjsua Callee"
echo "========================================="
echo "SIP服务器: $SERVER:$SIP_PORT"
echo "被叫帐号: $CALLEE_USER@$CALLEE_DOMAIN"
if [ "$AUTO_ANSWER" = true ]; then
    echo "接听模式: 自动接听"
else
    echo "接听模式: 手动接听 (按'a'接听)"
fi
echo "========================================="
echo ""

# 检查pjsua是否可用
if ! command -v pjsua &> /dev/null; then
    echo "错误: pjsua未安装"
    exit 1
fi

# 创建pjsua配置文件
PJSUA_CFG=$(mktemp)

if [ "$AUTO_ANSWER" = true ]; then
    cat > "$PJSUA_CFG" << EOF
--local-port=$LOCAL_PORT
--id=sip:$CALLEE_USER@$CALLEE_DOMAIN
--registrar=sip:$SERVER:$SIP_PORT
--realm=*
--username=$CALLEE_USER
--password=$CALLEE_PASSWORD
--proxy=sip:$SERVER:$SIP_PORT
--use-cli
--no-stderr
--log-level=3
--app-log-level=3
--auto-answer=200
--max-calls=4
EOF
else
    cat > "$PJSUA_CFG" << EOF
--local-port=$LOCAL_PORT
--id=sip:$CALLEE_USER@$CALLEE_DOMAIN
--registrar=sip:$SERVER:$SIP_PORT
--realm=*
--username=$CALLEE_USER
--password=$CALLEE_PASSWORD
--proxy=sip:$SERVER:$SIP_PORT
--use-cli
--no-stderr
--log-level=3
--app-log-level=3
--max-calls=4
EOF
fi

echo "启动pjsua等待来电..."
echo "提示: 按'h'查看帮助, 按'a'接听, 按'q'退出"
echo ""

pjsua --config-file="$PJSUA_CFG"

# 清理
rm -f "$PJSUA_CFG"

echo ""
echo "已退出"
