#!/bin/bash
#
# 测试FreeSWITCH服务器是否部署成功
#

# 默认配置
DEFAULT_SERVER="192.168.139.149"
SIP_PORT="5080"
ESL_PORT="8021"
ESL_PASSWORD="ClueCon"

SERVER="$DEFAULT_SERVER"

# 帮助信息
show_help() {
    echo "用法: $0 [选项]"
    echo "选项:"
    echo "  -h          显示帮助信息"
    echo "  -s SERVER   指定目标服务器 (默认: $DEFAULT_SERVER)"
    echo "  -p PORT     指定SIP端口 (默认: $SIP_PORT)"
    echo "  -e PORT     指定ESL端口 (默认: $ESL_PORT)"
}

# 解析命令行参数
while getopts "hs:p:e:" opt; do
    case $opt in
        h)
            show_help
            exit 0
            ;;
        s)
            SERVER="$OPTARG"
            ;;
        p)
            SIP_PORT="$OPTARG"
            ;;
        e)
            ESL_PORT="$OPTARG"
            ;;
        *)
            show_help
            exit 1
            ;;
    esac
done

echo "========================================="
echo "FreeSWITCH 服务测试"
echo "========================================="
echo "服务器: $SERVER"
echo "SIP端口: $SIP_PORT"
echo "ESL端口: $ESL_PORT"
echo "========================================="
echo ""

# 测试1: SIP TCP端口连通性
echo ">>> 测试1: 检查SIP TCP端口连通性..."
nc -zv "$SERVER" "$SIP_PORT" 2>&1
if [ $? -eq 0 ]; then
    echo "✓ TCP端口 $SIP_PORT 可访问"
else
    echo "✗ TCP端口 $SIP_PORT 不可访问"
fi
echo ""

# 测试2: SIP UDP端口连通性
echo ">>> 测试2: 检查SIP UDP端口连通性..."
nc -zvu "$SERVER" "$SIP_PORT" 2>&1
if [ $? -eq 0 ]; then
    echo "✓ UDP端口 $SIP_PORT 可访问"
else
    echo "! UDP端口测试可能不准确"
fi
echo ""

# 测试3: ESL端口连通性
echo ">>> 测试3: 检查ESL端口连通性..."
nc -zv "$SERVER" "$ESL_PORT" 2>&1
if [ $? -eq 0 ]; then
    echo "✓ ESL端口 $ESL_PORT 可访问"
else
    echo "✗ ESL端口 $ESL_PORT 不可访问"
fi
echo ""

# 测试4: ESL连接测试
echo ">>> 测试4: 测试ESL连接..."
response=$(echo -e "auth $ESL_PASSWORD\n\napi status\n\nexit\n" | nc -w 3 "$SERVER" "$ESL_PORT" 2>/dev/null)
if echo "$response" | grep -q "Content-Type"; then
    echo "✓ ESL连接成功"
    if echo "$response" | grep -q "UP"; then
        echo "✓ FreeSWITCH状态正常"
    fi
else
    echo "! ESL连接测试未成功（可能是密码错误或防火墙限制）"
fi
echo ""

# 测试5: SIP OPTIONS请求
echo ">>> 测试5: 发送SIP OPTIONS请求..."
OPTIONS_MSG="OPTIONS sip:$SERVER:$SIP_PORT SIP/2.0\r\n\
Via: SIP/2.0/UDP localhost:5060;branch=z9hG4bK-test\r\n\
From: <sip:test@localhost>;tag=test123\r\n\
To: <sip:$SERVER>\r\n\
Call-ID: test-$(date +%s)@localhost\r\n\
CSeq: 1 OPTIONS\r\n\
Max-Forwards: 70\r\n\
Content-Length: 0\r\n\r\n"

response=$(echo -e "$OPTIONS_MSG" | nc -u -w 2 "$SERVER" "$SIP_PORT" 2>/dev/null)
if echo "$response" | grep -q "SIP/2.0"; then
    echo "✓ 收到SIP响应"
    echo "$response" | head -1
else
    echo "! 未收到SIP响应（可能是UDP超时或防火墙限制）"
fi
echo ""

echo "========================================="
echo "FreeSWITCH 服务测试完成"
echo "========================================="
