#!/bin/bash
#
# VoIP系统综合测试脚本
# 测试 UA1 -> Kamailio -> FreeSWITCH -> Kamailio -> UA2 呼叫流程
#

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 默认配置
DEFAULT_SERVER="192.168.139.149"
SERVER="$DEFAULT_SERVER"

# 帮助信息
show_help() {
    echo "用法: $0 [选项] <测试类型>"
    echo ""
    echo "VoIP系统综合测试"
    echo ""
    echo "选项:"
    echo "  -h          显示帮助信息"
    echo "  -s SERVER   指定SIP服务器地址 (默认: $DEFAULT_SERVER)"
    echo ""
    echo "测试类型:"
    echo "  all         运行所有测试"
    echo "  services    测试服务连通性"
    echo "  register    测试SIP注册"
    echo "  echo        测试回声(9196)"
    echo "  call        测试端到端呼叫"
    echo ""
    echo "示例:"
    echo "  $0 services     # 测试服务是否启动"
    echo "  $0 register     # 测试注册功能"
    echo "  $0 echo         # 测试回声"
    echo "  $0 all          # 运行所有测试"
}

# 解析命令行参数
while getopts "hs:" opt; do
    case $opt in
        h)
            show_help
            exit 0
            ;;
        s)
            SERVER="$OPTARG"
            ;;
        *)
            show_help
            exit 1
            ;;
    esac
done

shift $((OPTIND-1))
TEST_TYPE="${1:-all}"

echo "========================================="
echo "VoIP 系统测试"
echo "========================================="
echo "服务器: $SERVER"
echo "测试类型: $TEST_TYPE"
echo "========================================="
echo ""

# 测试服务连通性
test_services() {
    echo ">>> 测试服务连通性..."
    echo ""

    # MySQL
    echo -n "MySQL (3306): "
    if nc -zv "$SERVER" 3306 2>&1 | grep -q "succeeded"; then
        echo "OK"
    else
        echo "FAILED"
    fi

    # Kamailio
    echo -n "Kamailio SIP (5060/tcp): "
    if nc -zv "$SERVER" 5060 2>&1 | grep -q "succeeded"; then
        echo "OK"
    else
        echo "FAILED"
    fi

    # FreeSWITCH
    echo -n "FreeSWITCH SIP (5080/tcp): "
    if nc -zv "$SERVER" 5080 2>&1 | grep -q "succeeded"; then
        echo "OK"
    else
        echo "FAILED"
    fi

    echo -n "FreeSWITCH ESL (8021/tcp): "
    if nc -zv "$SERVER" 8021 2>&1 | grep -q "succeeded"; then
        echo "OK"
    else
        echo "FAILED"
    fi

    echo ""
}

# 测试SIP注册
test_register() {
    echo ">>> 测试SIP注册..."
    echo ""

    if ! command -v pjsua &> /dev/null; then
        echo "错误: pjsua未安装"
        return 1
    fi

    # 创建临时配置
    PJSUA_CFG=$(mktemp)
    cat > "$PJSUA_CFG" << EOF
--local-port=5070
--id=sip:100134001@voip.com
--registrar=sip:$SERVER:5060
--realm=*
--username=100134001
--password=voip
--proxy=sip:$SERVER:5060
--null-audio
--auto-quit=5
EOF

    echo "注册 100134001@voip.com ..."
    result=$(pjsua --config-file="$PJSUA_CFG" 2>&1)

    if echo "$result" | grep -q "registration success"; then
        echo "注册成功"
    else
        echo "注册失败"
        echo "$result" | tail -5
    fi

    rm -f "$PJSUA_CFG"
    echo ""
}

# 测试回声
test_echo() {
    echo ">>> 测试回声 (9196)..."
    echo ""

    if ! command -v pjsua &> /dev/null; then
        echo "错误: pjsua未安装"
        return 1
    fi

    echo "呼叫 9196 (回声测试)，持续5秒..."

    # 创建临时配置
    PJSUA_CFG=$(mktemp)
    cat > "$PJSUA_CFG" << EOF
--local-port=5072
--id=sip:100134001@voip.com
--registrar=sip:$SERVER:5060
--realm=*
--username=100134001
--password=voip
--proxy=sip:$SERVER:5060
--null-audio
--duration=5
EOF

    # 使用expect自动呼叫
    if command -v expect &> /dev/null; then
        result=$(expect << EXPECT_EOF 2>&1
        log_user 0
        set timeout 15
        spawn pjsua --config-file=$PJSUA_CFG

        expect {
            "registration success" {
                sleep 1
                send "m\r"
                expect "Enter URL"
                send "sip:9196@$SERVER:5060\r"
                expect {
                    "CONFIRMED" {
                        puts "CALL_SUCCESS"
                        sleep 5
                        send "h\r"
                        sleep 1
                        send "q\r"
                    }
                    "DISCONN" {
                        puts "CALL_FAILED"
                    }
                    timeout {
                        puts "CALL_TIMEOUT"
                    }
                }
            }
            timeout {
                puts "REG_TIMEOUT"
            }
        }
        expect eof
EXPECT_EOF
)
        if echo "$result" | grep -q "CALL_SUCCESS"; then
            echo "回声测试成功"
        else
            echo "回声测试失败"
        fi
    else
        echo "需要安装expect进行自动化测试"
        echo "手动测试: $SCRIPT_DIR/caller.sh -t"
    fi

    rm -f "$PJSUA_CFG"
    echo ""
}

# 测试端到端呼叫
test_call() {
    echo ">>> 测试端到端呼叫..."
    echo ""
    echo "此测试需要在两个终端中分别运行:"
    echo ""
    echo "终端1 (被叫):"
    echo "  $SCRIPT_DIR/callee.sh -s $SERVER"
    echo ""
    echo "终端2 (主叫):"
    echo "  $SCRIPT_DIR/caller.sh -s $SERVER"
    echo ""
    echo "呼叫流程:"
    echo "  100134001 -> Kamailio -> FreeSWITCH -> Kamailio -> 100134002"
    echo ""
}

# 运行测试
case "$TEST_TYPE" in
    services)
        test_services
        ;;
    register)
        test_register
        ;;
    echo)
        test_echo
        ;;
    call)
        test_call
        ;;
    all)
        test_services
        test_register
        test_echo
        test_call
        ;;
    *)
        echo "未知测试类型: $TEST_TYPE"
        show_help
        exit 1
        ;;
esac

echo "========================================="
echo "测试完成"
echo "========================================="
