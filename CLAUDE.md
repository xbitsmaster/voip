## VoIP
这是一个部署脚本项目，用于部署VoIP服务器

## 项目包括三个部分
1. kamailio 服务器：部署kamailio服务器，做为SIP网关；
2. freeswitch服务器：部署freeswitch服务器，做为B2BUA；
3. mysql服务器：部署mysql服务器，做为数据库；
4. 要求：
    1. 服务器使用docker部署；
    2. kamailio服务器使用kamailio的docker镜像；
    3. freeswitch服务器使用freeswitch的docker镜像；
    4. mysql服务器使用mysql的docker镜像；
    5. kamailio与freeswitch使用mysql数据库，使用同一个数据库；

## 项目结构
1. etc：存放配置文件，三个服务器的配置文件存放在不同的目录中；
2. scripts: 存放脚本文件，用三个脚本分别生成三个服务器的docker-compose.yml文件，存放在docker目录；
3. scripts: 存放远程部署脚本，根据docker-compose.yml文件与目标服务器信息，在目标服务器上部署服务器；
   - 脚本的命令行参数（都有默认值）：
      - -h: 显示帮助信息；
      - -c: 指定docker-compose.yml文件路径；
      - -s: 指定目标服务器信息；
      - -p: 指定docker-compose.yml文件存放在docker目录；
4. tests：存放测试脚本，用于测试服务器是否部署成功；
    - 测试kamailio是否部署成功；
    - 测试freeswitch是否部署成功；
    - 测试mysql是否部署成功；

## 隐私：除默认服务器地址外，不要存储任何敏感信息，包括但不限于含有个人信息的目录名，邮件名等。

