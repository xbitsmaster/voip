#!/bin/bash
#
# pjsua Caller脚本
# 使用100134001@voip.com呼叫100134002@voip.com
#

# 默认配置
DEFAULT_SERVER="192.168.139.149"
SIP_PORT="5060"
CALLER_USER="100134001"
CALLER_DOMAIN="voip.com"
CALLER_PASSWORD="voip"
CALLEE_USER="100134002"
LOCAL_PORT="5062"
CALL_DURATION="30"

SERVER="$DEFAULT_SERVER"

# 帮助信息
show_help() {
    echo "用法: $0 [选项]"
    echo ""
    echo "pjsua Caller - 使用100134001呼叫100134002"
    echo ""
    echo "选项:"
    echo "  -h          显示帮助信息"
    echo "  -s SERVER   指定SIP服务器地址 (默认: $DEFAULT_SERVER)"
    echo "  -d SECONDS  指定通话时长 (默认: $CALL_DURATION秒)"
    echo "  -t          仅测试回声(呼叫9196)"
    echo ""
    echo "示例:"
    echo "  $0              # 呼叫100134002"
    echo "  $0 -t           # 呼叫回声测试9196"
    echo "  $0 -d 60        # 通话60秒"
}

TEST_ECHO=false

# 解析命令行参数
while getopts "hs:d:t" opt; do
    case $opt in
        h)
            show_help
            exit 0
            ;;
        s)
            SERVER="$OPTARG"
            ;;
        d)
            CALL_DURATION="$OPTARG"
            ;;
        t)
            TEST_ECHO=true
            ;;
        *)
            show_help
            exit 1
            ;;
    esac
done

# 设置呼叫目标
if [ "$TEST_ECHO" = true ]; then
    CALLEE_URI="sip:9196@$SERVER:$SIP_PORT"
    echo "模式: 回声测试"
else
    CALLEE_URI="sip:$CALLEE_USER@$SERVER:$SIP_PORT"
    echo "模式: 呼叫用户"
fi

echo "========================================="
echo "pjsua Caller"
echo "========================================="
echo "SIP服务器: $SERVER:$SIP_PORT"
echo "主叫: $CALLER_USER@$CALLER_DOMAIN"
echo "被叫: $CALLEE_URI"
echo "通话时长: ${CALL_DURATION}秒"
echo "========================================="
echo ""

# 检查pjsua是否可用
if ! command -v pjsua &> /dev/null; then
    echo "错误: pjsua未安装"
    exit 1
fi

# 创建pjsua配置文件
PJSUA_CFG=$(mktemp)
cat > "$PJSUA_CFG" << EOF
--local-port=$LOCAL_PORT
--id=sip:$CALLER_USER@$CALLER_DOMAIN
--registrar=sip:$SERVER:$SIP_PORT
--realm=*
--username=$CALLER_USER
--password=$CALLER_PASSWORD
--proxy=sip:$SERVER:$SIP_PORT
--no-stderr
--log-level=3
--app-log-level=3
--auto-answer=200
--duration=$CALL_DURATION
EOF

echo "启动pjsua并发起呼叫..."
echo "提示: 按'h'查看帮助, 按'q'退出"
echo ""

# 使用expect自动化呼叫（如果可用）
if command -v expect &> /dev/null; then
    expect << EXPECT_EOF
    set timeout 60
    spawn pjsua --config-file=$PJSUA_CFG

    # 等待注册成功
    expect {
        "registration success" {
            sleep 1
            send "m\r"
            expect "Make call:"
            send "$CALLEE_URI\r"
        }
        timeout {
            puts "注册超时"
            exit 1
        }
    }

    # 等待呼叫响应
    expect {
        "CONFIRMED" {
            puts "\\n呼叫已接通!"
        }
        "DISCONNECTED" {
            puts "\\n呼叫断开"
        }
        "DISCONNCTD" {
            puts "\\n呼叫断开"
        }
        "Busy Here" {
            puts "\\n对方忙"
        }
        "Not Found" {
            puts "\\n用户不存在"
        }
        "Temporarily Unavailable" {
            puts "\\n对方暂时不可用"
        }
        timeout {
            puts "\\n等待响应超时"
        }
    }

    # 等待用户交互
    interact
EXPECT_EOF
else
    # 没有expect，手动模式
    echo "========================================"
    echo "pjsua已启动，请手动操作："
    echo "1. 等待'registration success'消息"
    echo "2. 按'm'发起呼叫"
    echo "3. 输入: $CALLEE_URI"
    echo "4. 按Enter确认"
    echo "========================================"
    echo ""

    pjsua --config-file="$PJSUA_CFG"
fi

# 清理
rm -f "$PJSUA_CFG"

echo ""
echo "通话结束"
