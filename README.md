# VoIP 部署系统

基于 Docker 的 VoIP 服务部署系统，包含 Kamailio SIP 代理、FreeSWITCH B2BUA 和 MySQL 数据库。

## 架构概述

```
                     ┌─────────────────┐
                     │   SIP Client    │
                     └────────┬────────┘
                              │
                     ┌────────▼────────┐
                     │    Kamailio     │ ◄── SIP代理/注册/路由
                     │   (5060/5061)   │
                     └────────┬────────┘
                              │
              ┌───────────────┼───────────────┐
              │               │               │
        ┌─────▼─────┐   ┌─────▼─────┐   ┌─────▼─────┐
        │ FreeSWITCH│   │ FreeSWITCH│   │ FreeSWITCH│
        │  Node 1   │   │  Node 2   │   │  Node N   │
        └─────┬─────┘   └─────┬─────┘   └─────┬─────┘
              │               │               │
              └───────────────┼───────────────┘
                              │
                     ┌────────▼────────┐
                     │     MySQL       │
                     │    (3306)       │
                     └─────────────────┘
```

## 目录结构

```
VoIP/
├── etc/                          # 配置文件
│   ├── deploy.conf               # 部署配置
│   ├── kamailio/
│   │   └── kamailio.cfg          # Kamailio配置
│   ├── freeswitch/
│   │   ├── vars.xml              # FreeSWITCH变量
│   │   └── dialplan/             # 拨号计划
│   └── mysql/
│       └── init.sql              # 数据库初始化
├── scripts/                      # 部署脚本
│   ├── common.sh                 # 公共函数库
│   ├── deploy-all.sh             # 一键部署
│   ├── deploy-mysql.sh           # MySQL部署
│   ├── deploy-kamailio.sh        # Kamailio部署
│   ├── deploy-freeswitch.sh      # FreeSWITCH部署
│   ├── deploy-freeswitch-node.sh # FreeSWITCH节点部署
│   ├── drain-freeswitch.sh       # FreeSWITCH平滑下线
│   ├── scale-freeswitch.sh       # FreeSWITCH扩缩容
│   ├── status.sh                 # 状态监控
│   └── logs.sh                   # 日志查看
├── tests/                        # 测试脚本
│   ├── caller.sh                 # 主叫测试
│   └── callee.sh                 # 被叫测试
└── docs/                         # 文档
    └── refactor-plan.md          # 重构计划
```

## 快速开始

### 1. 配置

编辑 `etc/deploy.conf` 设置目标服务器和参数：

```bash
# 默认服务器
DEFAULT_SERVER="192.168.139.149"
DEFAULT_USER="root"

# MySQL配置
MYSQL_ROOT_PASSWORD="voip_root_password"
MYSQL_USER="voip"
MYSQL_PASSWORD="voip_password"
MYSQL_DATABASE="voip"
```

### 2. 一键部署

```bash
cd scripts

# 部署所有服务 (MySQL -> Kamailio -> FreeSWITCH)
./deploy-all.sh

# 部署到指定服务器
./deploy-all.sh -s 192.168.1.100

# 跳过确认直接部署
./deploy-all.sh -y
```

### 3. 单独部署

```bash
# 部署MySQL
./deploy-mysql.sh

# 部署Kamailio
./deploy-kamailio.sh

# 部署FreeSWITCH
./deploy-freeswitch.sh
```

## 运维操作

### 查看服务状态

```bash
# 查看所有服务状态
./status.sh

# 查看指定服务器状态
./status.sh -s 192.168.1.100

# JSON格式输出
./status.sh --json
```

### 查看日志

```bash
# 查看MySQL日志
./logs.sh mysql

# 查看Kamailio日志
./logs.sh kamailio

# 实时跟踪FreeSWITCH日志
./logs.sh freeswitch -f

# 查看所有日志
./logs.sh all

# 查看指定节点日志
./logs.sh freeswitch --node 1

# 显示最后100行
./logs.sh kamailio -n 100
```

### FreeSWITCH 扩缩容

```bash
# 添加新节点
./scale-freeswitch.sh add -n 2
./scale-freeswitch.sh add -n 3 -s 192.168.1.102

# 移除节点 (会先执行drain)
./scale-freeswitch.sh remove -n 2

# 列出所有节点
./scale-freeswitch.sh list

# 查看节点状态
./scale-freeswitch.sh status
```

### FreeSWITCH 平滑下线 (Drain)

```bash
# 平滑下线默认FreeSWITCH
./drain-freeswitch.sh

# 平滑下线指定节点
./drain-freeswitch.sh -n 1

# drain后停止容器
./drain-freeswitch.sh -n 2 --stop

# 设置最大等待时间 (秒)
./drain-freeswitch.sh -n 1 -t 600
```

Drain流程：
1. 在Kamailio dispatcher中禁用该节点
2. FreeSWITCH暂停接收新呼叫
3. 等待现有呼叫结束
4. (可选) 停止容器

## 测试

### SIP注册和呼叫测试

```bash
cd tests

# 启动被叫 (100134002)
./callee.sh -s 192.168.139.149

# 启动主叫并拨打被叫 (100134001 -> 100134002)
./caller.sh -s 192.168.139.149
```

测试用户：
- 100134001@voip.com (密码: voip)
- 100134002@voip.com (密码: voip)

## 端口说明

| 服务 | 端口 | 协议 | 说明 |
|------|------|------|------|
| Kamailio | 5060 | UDP/TCP | SIP信令 |
| Kamailio | 5061 | TCP | SIP TLS |
| Kamailio | 8080 | TCP | JSONRPC API |
| FreeSWITCH | 5080 | UDP/TCP | SIP信令 |
| FreeSWITCH | 8021 | TCP | ESL接口 |
| MySQL | 3306 | TCP | 数据库 |

## API接口

### Kamailio JSONRPC

```bash
# 心跳检测
curl http://SERVER:8080/RPC -d '{"jsonrpc":"2.0","method":"core.ping","id":1}'

# 获取运行时间
curl http://SERVER:8080/RPC -d '{"jsonrpc":"2.0","method":"core.uptime","id":1}'

# 获取统计信息
curl http://SERVER:8080/RPC -d '{"jsonrpc":"2.0","method":"stats.get_statistics","params":["all"],"id":1}'

# 查看dispatcher列表
curl http://SERVER:8080/RPC -d '{"jsonrpc":"2.0","method":"dispatcher.list","id":1}'

# 重载dispatcher
curl http://SERVER:8080/RPC -d '{"jsonrpc":"2.0","method":"dispatcher.reload","id":1}'
```

### FreeSWITCH ESL

```bash
# 进入FreeSWITCH CLI
docker exec -it voip-freeswitch fs_cli

# 常用命令
status              # 系统状态
show calls count    # 通话数量
sofia status        # SIP状态
fsctl pause         # 暂停接收新呼叫 (drain模式)
fsctl resume        # 恢复接收呼叫
reloadxml           # 重载配置
```

## 容器管理

```bash
# 查看容器状态
docker ps -f name=voip

# 查看容器日志
docker logs -f voip-mysql
docker logs -f voip-kamailio
docker logs -f voip-freeswitch

# 重启容器
docker restart voip-kamailio

# 进入容器
docker exec -it voip-kamailio bash
docker exec -it voip-freeswitch fs_cli
docker exec -it voip-mysql mysql -uvoip -pvoip_password voip
```

## 命令行参数

所有部署脚本支持以下通用参数：

| 参数 | 说明 | 默认值 |
|------|------|--------|
| -h | 显示帮助信息 | - |
| -s SERVER | 目标服务器地址 | 192.168.139.149 |
| -u USER | SSH用户名 | root |
| -p PATH | 远程部署路径 | /opt/voip |
| -y | 跳过确认提示 | - |

## 注意事项

1. 部署前确保目标服务器已安装 Docker
2. 确保 SSH 免密登录已配置
3. 防火墙需开放相应端口
4. 生产环境请修改默认密码
5. FreeSWITCH下线前务必使用drain模式

## 故障排查

### 服务启动失败

```bash
# 检查容器日志
docker logs voip-kamailio

# 检查端口占用
netstat -tlnp | grep 5060
```

### 呼叫失败

```bash
# 检查Kamailio日志
./logs.sh kamailio -n 100

# 检查FreeSWITCH日志
./logs.sh freeswitch -n 100

# 检查注册状态
docker exec voip-mysql mysql -uvoip -pvoip_password voip -e "SELECT * FROM location"
```

### 数据库连接失败

```bash
# 检查MySQL状态
docker exec voip-mysql mysqladmin ping -p

# 检查网络连通性
docker exec voip-kamailio ping voip-mysql
```
