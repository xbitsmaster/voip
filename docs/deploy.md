## 基础架构
1. SIP 网关：kamailio， sip proxy， sip registrar
2. SIP 服务器：freeswitch， sip b2bua
3. 数据库：mysql

## 集群架构
1. kamailio集群：通过Load Balance实现负载均衡或通过DNS实现负载均衡，双机集群；
2. freeswitch集群：多机集群，无状态服务器，由kamailio实现负载均衡；
3. mysql集群：主从复制，主从同步，实现高可用；
4. kamailio通过粘性连接实现与freeswitch的粘性连接；
5. kamailio通过监控freeswitch的健康状态，实现freeswitch的故障转移，扩容；

## 运营监控
1. 实时跟踪服务器的运行状态，数据统计，日志信息与告警信息。配置由手工完成，不在管理平台上做；
2. 通过日志信息与告警信息，实现故障的快速定位与处理；
3. 通过直接操作数据库，实现用户管理，服务器状态管理等；

## 部署流程
1. 部署数据库，确认状态正常后，下一步；
2. 部署kamailio，确认状态正常后，下一步；
3. 部署freeswitch，确认状态正常后，下一步；
4. 部署其它freeswitch实例；
5. 所有服务均使用docker部署，使用docker-compose管理；

