#!/bin/bash
#
# rsync快速编译安装shell脚本
# 官方文档：https://rsync.samba.org/documentation.html
#
# 安装命令
# bash rsync-install.sh new
# bash rsync-install.sh $verions_num
# 
# 查看最新版命令
# bash rsync-install.sh
#
# 可运行系统：
# CentOS 6.4+
# Ubuntu 16.04+
#
# 是一个跨平台的数据同步工具，支持远程增量，可以使用scp、ssh、socket方式传输文件
# rsync需要配置服务端和客户同步端，客户同步端会自动同步服务端的变动文件
# 同步是由服务端监控指定目录，当文件或目录发生变化实时通知客户端进行同步操作
# rsync 3.1.2+ 同步时会确保目录安全，建议使用
# 同步接收端容易产生安全问题，同步目录建议创建独立子目录（不使用系统默认存在的目录，而是在这些目录下创建子目录并指定好权限）
#
# 使用方法：
#   一、从服务器复制
#       1、所有需要通信的服务器均安装rsync
#       2、配置一个或多个监听源服务器（ssh或rsync），建议使用rsync --daemon监听
#       3、其它从服务器使用rsync命令同步下载，比如： rsync --port=873 -av 127.0.0.1::www/ /www/
#   二、源服务器推送
#       1、所有需要通信的服务器均安装rsync
#       2、在所有从服务器中配置监听（ssh或rsync），建议使用rsync --daemon监听
#       3、在源服务器中使用rsync命令同步上传，比如： rsync --port=873 -av /www/ 127.0.0.1::www/
#
#  自动排量同步方法：（同步前需要将数据复制到对应的服务器中）
#       1、增加定时器
#       2、如果有版本库则可使用钩子脚本实现自动同步
#       3、
#
# 报错：
#   1、rsync: [Receiver] failed to connect to ip (ip): No route to host (113)
#       建议增加目标服务器端口开放，比如：（注意端口号） iptable -A INPUT -p tcp -m state --state NEW -m tcp --dport 873 -j ACCEPT
#       也可以删除目标服务器的防火墙规则 REJECT  all  --  *   *   0.0.0.0/0  0.0.0.0/0  reject-with icmp-host-prohibited
#       或者关闭防火墙
#   2、@ERROR: invalid uid rsyncd
#       需要在目标服务器创建 rsyncd 用户
#
####################################################################################
##################################### 安装处理 #####################################
####################################################################################
# 定义安装参数
DEFINE_RUN_PARAMS="
[-d, --daemon]守护模式启动
#守护模式会开启监听服务
#守护模式运行在源服务器
#非守护模式运行在要同步服务器
"
# 定义安装类型
DEFINE_INSTALL_TYPE='configure'
# 编译默认项（这里的配置会随着编译版本自动生成编译项）
DEFAULT_OPTIONS='?!lz4 ?!zstd ?!xxhash ?!md2man'
# 加载基本处理
source "$(cd "$(dirname "${BASH_SOURCE[0]}")"; pwd)"/../../includes/install.sh || exit

# 初始化安装
init_install '2.0.0' "https://download.samba.org/pub/rsync/src/" 'rsync-\d+(\.\d+)+'
#  限制空间大小（G）：编译目录、安装目录、内存
install_storage_require 1 1 1
# ************** 相关配置 ******************
# 编译初始选项（这里的指定必需有编译项）
CONFIGURE_OPTIONS="--prefix=$INSTALL_PATH$RSYNC_VERSION "
# ************** 编译安装 ******************
# 下载rsync包
download_software https://download.samba.org/pub/rsync/src/rsync-$RSYNC_VERSION.tar.gz
# 解析选项
parse_options CONFIGURE_OPTIONS $DEFAULT_OPTIONS $ARGV_options
# 暂存编译目录
RSYNC_CONFIGURE_PATH=`pwd`
# 安装依赖
info_msg "安装相关已知依赖"

# 所有依赖均在INSTALL.md文件中说明了，暂时还没有处理

cd $RSYNC_CONFIGURE_PATH
# 编译安装
configure_install $CONFIGURE_OPTIONS

cd $INSTALL_PATH$RSYNC_VERSION
# 配置文件处理
info_msg 'rsync 配置文件修改'
mkdirs ./etc/rsyncd.d
mkdirs ./hook
mkdirs ./logs
if [ ! -e ./etc/rsyncd.conf ];then
    cat ./etc/rsyncd.conf <<CONF
# rsync 守护进程专用配置文件

###################### 全局配置 ######################
# 配置MOTD信息，当有连接时显示给客户端
# motd file = $INSTALL_PATH$RSYNC_VERSION/etc/motd

# 指定守护进程PID保存文件
pid file = $INSTALL_PATH$RSYNC_VERSION/logs/rsyncd.pid

# 指定守护进程监听端口号，默认873，非root账号启动端口号需要指定在1024以上
# port = 873

# 指定守护进程监听地址，不建议使用0.0.0.0，应该使用内网IP地址
# address = 0.0.0.0

# 配置套接字选项，需要阅读setsockopt()系统调用的手册
# socket = l:TCP_NODELAY=1
# socket = r:TCP_NODELAY=1

# 覆盖默认积压值，默认是5
# listen backlog = 5

###################### 模块配置 ######################
# 指定文件传输使用的用户，root启动时默认切换到nobody用户，非root启动可不指定
uid = rsyncd
gid = rsyncd

# 日志文件
log file = $INSTALL_PATH$RSYNC_VERSION/logs/rsyncd.log

# 锁定记录文件
lock file = $INSTALL_PATH$RSYNC_VERSION/logs/rsyncd.lock

# 传输前切换到指定根目录
# use chroot = true

# 指定根目录
# daemon chroot = /

# 最大同时连接数，默认是0无限制
# max connections = 100

# 是否只写（确定客户端是否可下载文件），默认为禁用
# write only = false

# 是否只读（只读即不允许客户端上传文件），默认为只读
# read only = true

# 过滤器（多个空格分隔），决定哪些文件允许传输
# filter = /

# 排除过滤器（多个空格分隔），决定哪些文件不能传输
exclude = */.git*/ */.svn/*

# 在排除过滤器中（多个空格分隔）开放一些允许传输文件
# include = config

# 允许授权连接传输文件用户名集合（多个逗号或空格分开），默认不限制
# 格式：  name:power
#   name    用户名或组名，@开始表示组名，用户名不要求存在于系统中（是独立于系统用户体系外）
#   power   开放权限：（不指定为 ro/rw）
#               deny 拒绝
#               ro 拒绝
#               rw 拒绝
# auth users = @rsync:ro

# 授权连接密码配置文件，指定auth users选项有效
# 格式：    user:password   或   @group:password
# secrets file = $INSTALL_PATH$RSYNC_VERSION/etc/rsyncd.secrets

# 允许连接IP/掩码地址集合（多个逗号或空格分开），默认不限制
# hosts allow = 127.0.0.1

# 拒绝连接的IP/掩码地址集合（多个逗号或空格分开），默认不限制
# hosts deny = 127.0.0.1

# 连接超时（秒），超时后就跳过连接进行下一个
# timeout = 600

# 有同步文件时调用命令，命令失败将不会传输同步数据
early exec = $INSTALL_PATH$RSYNC_VERSION/hook/early.sh

# 开始传输同步数据之前调用命令，命令失败将不会传输同步数据
pre-xfer exec = $INSTALL_PATH$RSYNC_VERSION/hook/pre-xfer.sh

# 传输同步数据结束后调用命令
post-xfer exec = $INSTALL_PATH$RSYNC_VERSION/hook/post-xfer.sh

# 合并各模块配置（），如果指定的是目录则会加载目录下匹配 *.inc 的文件
# &merge $INSTALL_PATH$RSYNC_VERSION/etc/rsyncd.d

# 加载各模块配置，如果指定的是目录则会加载目录下匹配 *.conf 的文件
# &include $INSTALL_PATH$RSYNC_VERSION/etc/rsyncd.d

# 模块配置
# [www]
# path = 模块路径，可以使用变量
# comment = 描述当前模块

CONF
fi
# 开始同步调用脚本
if [ ! -e ./hook/early.sh ];then
    cat ./hook/early.sh <<CONF
#!/bin/bash
# 同步操作前最先调用脚本（比 pre-xfer.sh 还前调用），调用出错误终止同步
# 脚本非 0 状态结束将停止同步

# rsync 支持环境变量，变量只在脚本调用时有效
#   RSYNC_MODULE_NAME   要访问的模块名
#   RSYNC_MODULE_PATH   模块路径
#   RSYNC_HOST_ADDR     访问的主机IP
#   RSYNC_HOST_NAME     访问的主机名
#   RSYNC_USER_NAME     访问的用户名（在 auth users 配置中指定的）
#   RSYNC_PID           同步进程PID


CONF
fi
# 同步前调用脚本
if [ ! -e ./etc/pre-xfer.sh ];then
    cat ./etc/pre-xfer.sh <<CONF
#!/bin/bash
# 同步操作前调用脚本，调用出错误终止同步
# 脚本非 0 状态结束将停止同步

# rsync 支持环境变量，变量只在脚本调用时有效
#   RSYNC_MODULE_NAME   要访问的模块名
#   RSYNC_MODULE_PATH   模块路径
#   RSYNC_HOST_ADDR     访问的主机IP
#   RSYNC_HOST_NAME     访问的主机名
#   RSYNC_USER_NAME     访问的用户名（在 auth users 配置中指定的）
#   RSYNC_PID           同步进程PID
#   RSYNC_REQUEST       用户指定的同步模块/路径，当指定多个同步源时会有空格分开，格式： mod/path
#   RSYNC_ARG#          同步参数（# 是序号类型，RSYNC_ARG0 = rsyncd ，指定序号参数由访问端指定）

CONF
fi
# 同步后调用脚本
if [ ! -e ./etc/post-xfer.sh ];then
    cat ./etc/post-xfer.sh <<CONF
#!/bin/bash
# 同步操作后调用脚本

# rsync 支持环境变量，变量只在脚本调用时有效
#   RSYNC_MODULE_NAME   要访问的模块名
#   RSYNC_MODULE_PATH   模块路径
#   RSYNC_HOST_ADDR     访问的主机IP
#   RSYNC_HOST_NAME     访问的主机名
#   RSYNC_USER_NAME     访问的用户名（在 auth users 配置中指定的）
#   RSYNC_PID           同步进程PID
#   RSYNC_EXIT_STATUS   同步结束退出状态，0 表示成功，>0 表示错误，-1 表示未正确退出，此值会返回给访问端
#   RSYNC_RAW_STATUS    原始退出值

CONF
fi
# 密码文件
if [ ! -e ./etc/rsyncd.secrets ];then
    cat ./etc/rsyncd.secrets <<CONF
# 授权连接密码配置文件，指定auth users选项有效
# 格式：    user:password   或   @group:password

# rsync:123456
CONF
fi

# 创建用户
add_user rsyncd
# 修改权限
chown -R rsyncd:rsyncd ./*
chmod 600 ./etc/rsyncd.secrets
chmod -R +x ./hook/

if [ "$ARGV_daemon" = '1' ];then
    # 添加服务配置
    SERVICES_CONFIG=()
    SERVICES_CONFIG[$SERVICES_CONFIG_START_RUN]="./bin/rsync --daemon --config=./etc/rsyncd.conf"
    SERVICES_CONFIG[$SERVICES_CONFIG_USER]="rsyncd"
    SERVICES_CONFIG[$SERVICES_CONFIG_PID_FILE]="./logs/rsyncd.pid"
    # 服务并启动服务
    add_service SERVICES_CONFIG

    # 添加服务配置 rsync-ssl

fi

info_msg "安装成功：rsync-$RSYNC_VERSION";
