# VoIP部署脚本重构计划

## 一、目标架构

### 1.1 架构概述

```
                    ┌─────────────────┐
                    │   Load Balancer │
                    │   (DNS/VIP)     │
                    └────────┬────────┘
                             │
              ┌──────────────┴──────────────┐
              │                             │
     ┌────────▼────────┐         ┌──────────▼────────┐
     │  Kamailio-主    │◄───────►│  Kamailio-备      │
     │  (Active)       │ 心跳    │  (Standby)        │
     └────────┬────────┘         └───────────────────┘
              │
              │ dispatcher (状态监控/负载均衡)
              │
    ┌─────────┼─────────┬─────────────┐
    │         │         │             │
┌───▼───┐ ┌───▼───┐ ┌───▼───┐   ┌─────▼─────┐
│ FS-1  │ │ FS-2  │ │ FS-3  │...│ FS-N      │
│(独立) │ │(独立) │ │(独立) │   │(独立)     │
└───┬───┘ └───┬───┘ └───┬───┘   └─────┬─────┘
    │         │         │             │
    └─────────┴─────────┴─────────────┘
                    │
           ┌────────▼────────┐
           │     MySQL       │
           │  (主从复制)     │
           └─────────────────┘
```

### 1.2 核心设计原则

| 组件 | 架构模式 | 说明 |
|------|----------|------|
| Kamailio | 主备模式 | 备机监控主机状态，主机失效后自动接管 |
| FreeSWITCH | 独立多实例 | 无集群，由Kamailio统一调度和监控 |
| MySQL | 主从复制 | 读写分离，高可用 |

### 1.3 管理API需求

| 组件 | API功能 |
|------|---------|
| Kamailio | 运行状态、统计数据、日志查询、告警获取、dispatcher管理 |
| FreeSWITCH | 运行状态、通话统计、通道信息、日志查询、drain模式控制 |

## 二、现状评估

### 2.1 已实现功能

- ✅ MySQL单机部署
- ✅ Kamailio单机部署
- ✅ FreeSWITCH单机部署
- ✅ 基本的呼叫路由 (UA → Kamailio → FreeSWITCH → Kamailio → UA)
- ✅ 配置文件分离

### 2.2 待实现功能

- ❌ Kamailio主备切换
- ❌ FreeSWITCH多实例支持
- ❌ Kamailio dispatcher模块 (负载均衡/状态监控)
- ❌ FreeSWITCH drain模式
- ❌ 管理API接口
- ❌ MySQL主从复制
- ❌ 健康检查机制
- ❌ 统一部署入口

## 三、重构计划

### 阶段一：基础设施完善 (优先级: 高)

#### 1.1 公共配置与函数库

**创建 `etc/deploy.conf`:**
```bash
# 网络配置
NETWORK_NAME=voip-network

# MySQL配置
MYSQL_ROOT_PASSWORD=voip_root_password
MYSQL_USER=voip
MYSQL_PASSWORD=voip_password
MYSQL_DATABASE=voip

# Kamailio配置
KAMAILIO_SIP_PORT=5060
KAMAILIO_JSONRPC_PORT=8080

# FreeSWITCH配置
FREESWITCH_SIP_PORT=5080
FREESWITCH_ESL_PORT=8021
FREESWITCH_ESL_PASSWORD=ClueCon

# 部署路径
REMOTE_PATH=/opt/voip
```

**创建 `scripts/common.sh`:**
```bash
# 公共变量加载
load_config() { source "$PROJECT_DIR/etc/deploy.conf"; }

# 健康检查函数
check_mysql_healthy() { ... }
check_kamailio_healthy() { ... }
check_freeswitch_healthy() { ... }

# 等待服务就绪
wait_for_service() { ... }
```

#### 1.2 健康检查机制

```bash
# MySQL健康检查
check_mysql_healthy() {
    docker exec voip-mysql mysqladmin ping -h localhost -u root -p$MYSQL_ROOT_PASSWORD &>/dev/null
}

# Kamailio健康检查 (通过JSONRPC)
check_kamailio_healthy() {
    curl -s http://$HOST:$KAMAILIO_JSONRPC_PORT/RPC -d '{"jsonrpc":"2.0","method":"core.ping","id":1}' | grep -q "result"
}

# FreeSWITCH健康检查 (通过ESL)
check_freeswitch_healthy() {
    docker exec $CONTAINER fs_cli -x "status" &>/dev/null
}
```

#### 1.3 统一部署入口

**创建 `scripts/deploy-all.sh`:**
```bash
# 按顺序部署，每步确认状态
deploy_all() {
    deploy_mysql && wait_mysql_healthy
    deploy_kamailio && wait_kamailio_healthy
    deploy_freeswitch && wait_freeswitch_healthy
}
```

### 阶段二：管理API配置 (优先级: 高)

#### 2.1 Kamailio JSONRPC API

**修改 `kamailio.cfg` 启用JSONRPC:**
```kamailio
loadmodule "jsonrpcs.so"
loadmodule "htable.so"

# JSONRPC over HTTP
modparam("jsonrpcs", "transport", 1)  # HTTP transport
modparam("jsonrpcs", "pretty_format", 1)

# HTTP监听
listen=tcp:0.0.0.0:8080
```

**可用API:**
| 方法 | 说明 |
|------|------|
| `core.ping` | 心跳检测 |
| `core.uptime` | 运行时间 |
| `stats.get_statistics` | 获取统计数据 |
| `dispatcher.list` | 获取dispatcher列表 |
| `dispatcher.set_state` | 设置dispatcher状态 |

#### 2.2 FreeSWITCH ESL/HTTP API

**配置 `event_socket.conf.xml`:**
```xml
<configuration name="event_socket.conf">
  <settings>
    <param name="listen-ip" value="0.0.0.0"/>
    <param name="listen-port" value="8021"/>
    <param name="password" value="ClueCon"/>
  </settings>
</configuration>
```

**配置 `httapi.conf.xml` (可选HTTP API):**
```xml
<configuration name="httapi.conf">
  <settings>
    <param name="enable" value="true"/>
    <param name="listen-ip" value="0.0.0.0"/>
    <param name="listen-port" value="8022"/>
  </settings>
</configuration>
```

**可用API:**
| 命令 | 说明 |
|------|------|
| `status` | 系统状态 |
| `show channels` | 当前通话 |
| `show calls count` | 通话统计 |
| `sofia status` | SIP状态 |
| `fsctl pause` | 暂停接收新呼叫(drain) |
| `fsctl resume` | 恢复接收呼叫 |

### 阶段三：Kamailio高可用 (优先级: 中)

#### 3.1 主备架构

**主备切换方案:**
- 使用Keepalived实现VIP漂移
- 备机通过VRRP监控主机状态
- 主机失效时，VIP自动漂移到备机

**创建 `scripts/deploy-kamailio-ha.sh`:**
```bash
# 部署Kamailio主备
deploy_kamailio_master() {
    # 启动Kamailio + Keepalived (MASTER)
}

deploy_kamailio_backup() {
    # 启动Kamailio + Keepalived (BACKUP)
}
```

**Keepalived配置模板 `etc/kamailio/keepalived.conf`:**
```
vrrp_script check_kamailio {
    script "/usr/local/bin/check_kamailio.sh"
    interval 2
    weight -20
}

vrrp_instance VI_KAMAILIO {
    state MASTER  # 或 BACKUP
    interface eth0
    virtual_router_id 51
    priority 100  # BACKUP设为90

    virtual_ipaddress {
        192.168.139.100/24
    }

    track_script {
        check_kamailio
    }
}
```

#### 3.2 共享状态

- 用户注册信息存储在MySQL (usrloc db_mode=2)
- 主备Kamailio共享同一MySQL
- 切换时无需状态同步

### 阶段四：FreeSWITCH多实例与调度 (优先级: 中)

#### 4.1 Dispatcher模块配置

**修改 `kamailio.cfg`:**
```kamailio
loadmodule "dispatcher.so"

# Dispatcher参数
modparam("dispatcher", "db_url", DBURL)
modparam("dispatcher", "table_name", "dispatcher")
modparam("dispatcher", "flags", 2)           # 故障检测
modparam("dispatcher", "dst_avp", "$avp(ds_dst)")
modparam("dispatcher", "grp_avp", "$avp(ds_grp)")
modparam("dispatcher", "cnt_avp", "$avp(ds_cnt)")
modparam("dispatcher", "probe_mode", 1)      # 主动探测
modparam("dispatcher", "ds_ping_method", "OPTIONS")
modparam("dispatcher", "ds_ping_interval", 10)
modparam("dispatcher", "ds_probing_threshold", 3)
modparam("dispatcher", "ds_inactive_threshold", 3)

# 路由到FreeSWITCH
route[TO_FREESWITCH] {
    # 使用dispatcher选择FreeSWITCH
    if (!ds_select_dst("1", "4")) {  # group 1, round-robin
        sl_send_reply("503", "Service Unavailable");
        exit;
    }

    $ru = "sip:" + $rU + "@" + $avp(ds_dst);
    route(RELAY);
}
```

**dispatcher表结构:**
```sql
CREATE TABLE dispatcher (
    id INT AUTO_INCREMENT PRIMARY KEY,
    setid INT DEFAULT 0,
    destination VARCHAR(192),
    flags INT DEFAULT 0,
    priority INT DEFAULT 0,
    attrs VARCHAR(128),
    description VARCHAR(64)
);

-- FreeSWITCH实例
INSERT INTO dispatcher (setid, destination, description) VALUES
(1, 'sip:voip-freeswitch-1:5060', 'FreeSWITCH Node 1'),
(1, 'sip:voip-freeswitch-2:5060', 'FreeSWITCH Node 2');
```

#### 4.2 FreeSWITCH Drain模式

**实现平滑下线:**
```bash
# scripts/drain-freeswitch.sh
drain_freeswitch() {
    local node=$1

    # 1. Kamailio中禁用该节点
    curl -X POST http://$KAMAILIO_HOST:8080/RPC \
        -d '{"jsonrpc":"2.0","method":"dispatcher.set_state","params":["i",'$node'],"id":1}'

    # 2. FreeSWITCH暂停接收新呼叫
    docker exec voip-freeswitch-$node fs_cli -x "fsctl pause"

    # 3. 等待现有呼叫结束
    while [ $(docker exec voip-freeswitch-$node fs_cli -x "show calls count" | grep -oP '\d+') -gt 0 ]; do
        sleep 5
    done

    # 4. 停止服务
    docker stop voip-freeswitch-$node
}
```

#### 4.3 多实例部署脚本

**创建 `scripts/deploy-freeswitch-node.sh`:**
```bash
#!/bin/bash
# 用法: ./deploy-freeswitch-node.sh -n <node_id> -s <server>

deploy_freeswitch_node() {
    local node_id=$1
    local server=$2
    local container_name="voip-freeswitch-$node_id"

    # 部署容器
    docker run -d --name $container_name ...

    # 注册到Kamailio dispatcher
    mysql -h $MYSQL_HOST -u $MYSQL_USER -p$MYSQL_PASSWORD $MYSQL_DATABASE \
        -e "INSERT INTO dispatcher (setid, destination, description)
            VALUES (1, 'sip:$container_name:5060', 'FreeSWITCH Node $node_id')"

    # 通知Kamailio重载dispatcher
    curl -X POST http://$KAMAILIO_HOST:8080/RPC \
        -d '{"jsonrpc":"2.0","method":"dispatcher.reload","id":1}'
}
```

### 阶段五：运维工具 (优先级: 中)

#### 5.1 状态监控脚本

**创建 `scripts/status.sh`:**
```bash
#!/bin/bash
# 显示所有服务状态

show_status() {
    echo "=== MySQL ==="
    docker exec voip-mysql mysqladmin status

    echo "=== Kamailio ==="
    curl -s http://$KAMAILIO:8080/RPC -d '{"jsonrpc":"2.0","method":"stats.get_statistics","params":["all"],"id":1}'

    echo "=== FreeSWITCH Nodes ==="
    for node in $(docker ps --filter "name=voip-freeswitch" --format "{{.Names}}"); do
        echo "--- $node ---"
        docker exec $node fs_cli -x "show calls count"
        docker exec $node fs_cli -x "sofia status"
    done

    echo "=== Dispatcher Status ==="
    curl -s http://$KAMAILIO:8080/RPC -d '{"jsonrpc":"2.0","method":"dispatcher.list","id":1}'
}
```

#### 5.2 日志查看脚本

**创建 `scripts/logs.sh`:**
```bash
#!/bin/bash
# 用法: ./logs.sh [mysql|kamailio|freeswitch|all] [-f]

view_logs() {
    local service=$1
    local follow=$2

    case $service in
        mysql) docker logs $follow voip-mysql ;;
        kamailio) docker logs $follow voip-kamailio ;;
        freeswitch)
            for node in $(docker ps --filter "name=voip-freeswitch" --format "{{.Names}}"); do
                docker logs $follow $node
            done
            ;;
        all)
            docker logs $follow voip-mysql &
            docker logs $follow voip-kamailio &
            docker logs $follow voip-freeswitch-1 &
            wait
            ;;
    esac
}
```

#### 5.3 FreeSWITCH扩缩容脚本

**创建 `scripts/scale-freeswitch.sh`:**
```bash
#!/bin/bash
# 用法:
#   ./scale-freeswitch.sh add -n 3 -s 192.168.1.103    # 添加节点3
#   ./scale-freeswitch.sh remove -n 3                   # 移除节点3 (drain后)

scale_freeswitch() {
    local action=$1
    local node_id=$2
    local server=$3

    case $action in
        add)
            ./deploy-freeswitch-node.sh -n $node_id -s $server
            ;;
        remove)
            ./drain-freeswitch.sh $node_id
            # 从dispatcher删除
            mysql ... -e "DELETE FROM dispatcher WHERE description='FreeSWITCH Node $node_id'"
            curl ... dispatcher.reload
            ;;
    esac
}
```

## 四、重构后目录结构

```
VoIP/
├── etc/
│   ├── deploy.conf                    # 部署配置
│   ├── kamailio/
│   │   ├── kamailio.cfg               # 主配置
│   │   ├── kamailio-ha.cfg            # 高可用配置
│   │   └── keepalived.conf            # Keepalived配置模板
│   ├── freeswitch/
│   │   ├── vars.xml
│   │   ├── autoload_configs/
│   │   │   └── event_socket.conf.xml  # ESL配置
│   │   └── dialplan/
│   └── mysql/
│       ├── init.sql                   # 初始化(含dispatcher表)
│       ├── master.cnf                 # 主库配置
│       └── slave.cnf                  # 从库配置
├── scripts/
│   ├── common.sh                      # 公共函数库
│   ├── deploy-all.sh                  # 统一部署入口
│   ├── deploy-mysql.sh                # MySQL部署
│   ├── deploy-mysql-replica.sh        # MySQL从库部署
│   ├── deploy-kamailio.sh             # Kamailio单机部署
│   ├── deploy-kamailio-ha.sh          # Kamailio高可用部署
│   ├── deploy-freeswitch.sh           # FreeSWITCH部署
│   ├── deploy-freeswitch-node.sh      # FreeSWITCH节点部署
│   ├── drain-freeswitch.sh            # FreeSWITCH平滑下线
│   ├── scale-freeswitch.sh            # FreeSWITCH扩缩容
│   ├── status.sh                      # 状态监控
│   └── logs.sh                        # 日志查看
├── docs/
│   ├── refactor-plan.md               # 本文档
│   ├── api-reference.md               # API参考
│   └── operations-guide.md            # 运维指南
└── tests/
    ├── caller.sh
    └── callee.sh
```

## 五、实施步骤

| 步骤 | 内容 | 产出 | 依赖 |
|------|------|------|------|
| 1 | 创建common.sh和deploy.conf | 公共函数库 | 无 |
| 2 | 添加健康检查函数 | 服务可靠性 | 步骤1 |
| 3 | 配置Kamailio JSONRPC | 管理API | 步骤1-2 |
| 4 | 配置FreeSWITCH ESL | 管理API | 步骤1-2 |
| 5 | 创建deploy-all.sh | 统一部署 | 步骤1-4 |
| 6 | 配置dispatcher模块 | FreeSWITCH调度 | 步骤1-5 |
| 7 | 创建deploy-freeswitch-node.sh | 多实例支持 | 步骤6 |
| 8 | 实现drain-freeswitch.sh | 平滑下线 | 步骤6-7 |
| 9 | 实现Kamailio主备 | 高可用 | 步骤1-5 |
| 10 | 创建运维脚本 | 运维工具 | 步骤1-8 |

## 六、API接口汇总

### 6.1 Kamailio JSONRPC API

| 端点 | 方法 | 说明 |
|------|------|------|
| `http://<host>:8080/RPC` | `core.ping` | 心跳检测 |
| | `core.uptime` | 运行时间 |
| | `stats.get_statistics` | 统计数据 |
| | `dispatcher.list` | FreeSWITCH列表 |
| | `dispatcher.set_state` | 设置节点状态 |
| | `dispatcher.reload` | 重载配置 |

### 6.2 FreeSWITCH ESL命令

| 命令 | 说明 |
|------|------|
| `status` | 系统状态 |
| `show channels` | 当前通道 |
| `show calls count` | 通话数量 |
| `sofia status` | SIP状态 |
| `fsctl pause` | 暂停(drain模式) |
| `fsctl resume` | 恢复 |

## 七、结论

本重构计划聚焦于：

1. **Kamailio主备模式** - 使用Keepalived实现VIP漂移，备机自动接管
2. **FreeSWITCH独立实例** - 无需集群，由Kamailio dispatcher统一调度
3. **管理API** - Kamailio JSONRPC + FreeSWITCH ESL提供运行状态、统计、告警接口
4. **Drain模式** - 支持FreeSWITCH平滑下线，等待现有会话结束

建议按步骤实施，优先完成管理API配置，再实现高可用和多实例支持。
