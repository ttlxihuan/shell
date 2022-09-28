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
# 自动排量同步方法：（同步前需要将数据复制到对应的服务器中）
#       1、增加定时器
#       2、如果有版本库则可使用钩子脚本实现自动同步
#       3、使用内置同步处理脚本
#
# 支持协议功能：
#       ssh     依赖ssh服务连接再调用rysnc命令进行同步处理
#               不需要开启额外服务，通过ssh+user进行权限控制
#               同步过滤需要通过rsync命令选项附加，权限控制需要目标和源目录的用户组权限控制
#       file    在本地进行同步处理
#               依赖文件系统即可进行同步，通过命令调用的用户权限进行控制
#               同步过滤需要通过rsync命令选项附加，权限控制需要目标和源目录的用户组权限控制，仅限本地同步
#       rsync   开启rsync服务进行再调用rsync命令进行同步处理（建议使用这种协议，服务配置后终端同步命令会再简单实用）
#               依赖rsync内置监听服务，并将过滤权限等功能进行服务配置管理
#               同步过滤不仅限rsync命令选项附加（附加也在服务配置有条件外有效），权限控制需要目标和源目录的用户组及同步指定的内置用户控制
# 同步方式：
#       将本地的差异文件上传到目标源库中，需要源库有写权限
#       将目标源库中的差异文件下载同步到本地，需要源库有读权限
#
# 命令说明：
# rsync         无加密同步或监听启动（SSL监听需要借助TCP代理作为加解密处理前端，实际rsync监听服务无加解密处理）
# rsync-ssl     加解密同步，只能用来同步SSL监听的同步服务，外网同步时建议使用（该命令是在rsync同步功能上增加了加解密处理功能，rsync同步使用参数均能使用）
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
[-H, --host='', {required|ip}]监听或同步地址
[-p, --port=3378, {required|int:0,65535}]服务监听端口号
[-t, --type=daemon, {required|in:daemon,rsync}]安装运行类型
#   daemon 指定为守护监听模式
#   rsync  指定为同步终端
#不同类型生成不同的配置文件，一般一个守护对多个同步终端
#守护监听模式需要安装在源服务器上，用来提供同步文件源
[-P, --password='', {required_with:ARGV_auth}]同步授权密码，所有模块共用
#生成随机密码语法 make:numm,set
#   make: 是随机生成密码关键字
#   num   是生成密码长度个数
#   set   限定密码包含字符，默认：数字、字母大小写、~!@#$%^&*()_-=+,.;:?/\|
#生成随机10位密码 make:10
#生成随机10位密码只包含指定字符 make:10,QWERTYU1234567890
#其它字符均为指定密码串，比如 123456
[-u, --auth='', {required_with:ARGV_password|regexp:'[[:alnum:]_-]+'}]同步授权账号，所有模块共用
#此账号仅用于同步通信不需要在系统中创建
#指定为空时则无需授权用户即可同步
[-m, --module='www:/www', {regexp:'[[:alnum:]]+:(/[[:alnum:]]+)+([[:alnum:]]+:[[:alnum:]]*)?(,[[:alnum:]]+:(/[[:alnum:]]+)+([[:alnum:]]+:[[:alnum:]]*)?)*'}]指定同步模块
#同步模块配置结构 name:path:auth:password 多个使用逗号分开
#   name    同步模块名
#   path    监听或同步根目录，必需是绝对路径
#           监听时为同步模块根目录
#           同步时为同步保存根目录
#   auth    同步专用授权用户，指定后共用无效（可选）
#  password 同步专用授权密码，格式与 --password 一样（可选）
#           指定授权用户未指定密码则密码为授权用户名
# 示例：
#   www:/www            指定名称：www，路径：/www
#   www:/www:www:       增加指定授权用户：www，密码与用户名相同
#   www:/www:www:123    增加指定授权用户：www，密码：123
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

# 创建用户
add_user rsyncd

# 解析模块列表
parse_lists MODULE_LISTS "$ARGV_module" ',' '.+'
# 密码处理
parse_use_password RSYNC_PASSWORD "${ARGV_password}"

INDEX=0
# 解析模块配置，解析后会创建变量：MODULE_ITEM 模块数组、MODULE_AUTH 模块授权名、MODULE_PASSWORD 模块授权密码
# @command parse_module
# return 0
parse_module(){
    if ((${#MODULE_LISTS[@]} <= INDEX));then
        return 1
    fi
    parse_lists MODULE_ITEM "${MODULE_LISTS[$INDEX]}" ':' '.+'
    ((INDEX++))
    if [ -n "${MODULE_ITEM[2]}" ];then
        MODULE_AUTH="${MODULE_ITEM[2]}"
        if [ -n "${MODULE_ITEM[3]}" ];then
            parse_use_password MODULE_PASSWORD "${MODULE_ITEM[3]}"
        else
            MODULE_PASSWORD="$MODULE_AUTH"
        fi
    else
        MODULE_AUTH=''
    fi
    return 0
}
# 运行类型处理
if [ $ARGV_type = 'rsync' ];then
    # 同步模式
    mkdirs ./secrets
    cat > rsync.sh <<CONF
#!/bin/bash
# 特别说明：
#   1、有同步密码文件则需要修改权限为600，同步命令需要使用与密码文件相同的用户，否则无法访问密码文件
#   2、同步过来的目标目录需要开放读写权限，否则无法操作
#   3、此脚本可放在定时器中运行

cd $INSTALL_PATH$RSYNC_VERSION
RSYNC_HOST='$ARGV_host'

CONF
    while parse_module;do
        if [ -z "$MODULE_AUTH" ];then
            MODULE_AUTH=$ARGV_auth
            MODULE_PASSWORD=$RSYNC_PASSWORD
        fi
        if [ -n "$MODULE_PASSWORD" ];then
            echo "$MODULE_PASSWORD" > ./secrets/$MODULE_AUTH.password
            RSYNC_RUN_PASSWORD=" --password-file=./secrets/$MODULE_AUTH.password"
        else
            RSYNC_RUN_PASSWORD=''
        fi
        if [ -n "$MODULE_AUTH" ];then
            MODULE_AUTH="$MODULE_AUTH@"
        fi
        echo "echo '同步 ${MODULE_ITEM[0]}/ => ${MODULE_ITEM[1]}'" >> rsync.sh
        echo "./bin/rsync -av $MODULE_AUTH\$RSYNC_HOST::${MODULE_ITEM[0]}/ ${MODULE_ITEM[1]}$RSYNC_RUN_PASSWORD --port=$ARGV_port" >> rsync.sh
    done
    # 修改文件权限
    chown -R rsyncd:rsyncd ./*
    chmod +x rsync.sh
    chmod -R 600 ./secrets/*
    info_msg "同步脚本命令： sudo -u rsyncd bash $INSTALL_PATH$RSYNC_VERSION/rsync.sh"
elif [ $ARGV_type = 'daemon' ];then
    # 监听模式
    # 配置文件处理
    info_msg 'rsync 配置文件修改'
    mkdirs ./etc/rsyncd.d
    mkdirs ./hook
    mkdirs ./logs
    if [ ! -e ./etc/rsyncd.conf ];then
        cat > ./etc/rsyncd.conf <<CONF
# rsync 守护进程专用配置文件
# 配置并未详尽所有选项，如有缺失自己增加
###################### 全局配置 ######################
# 配置MOTD信息，当有连接时显示给客户端
# motd file = $INSTALL_PATH$RSYNC_VERSION/etc/motd

# 指定守护进程PID保存文件
pid file = $INSTALL_PATH$RSYNC_VERSION/logs/rsyncd.pid

# 指定守护进程监听端口号，默认873，非root账号启动端口号需要指定在1024以上
port = $ARGV_port

# 指定守护进程监听地址，不建议使用0.0.0.0，应该使用内网IP地址
address = $ARGV_host

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

# 传输前切换到指定根目录（默认 true），
# 此功能需要root权限，有安全作用，用来限制传输根目录（模块中 path 指定目录）并且传输前会切换到path指定的根目录
# use chroot = true

# 指定与终端连接前切换到根目录（默认 /），受use chroot配置影响
# 一般不建议修改这个值，该值必需在path的上及目录，传输操作目录层级是 /chroot/path
# daemon chroot = /

# 最大同时连接数，默认是0无限制
# max connections = 100

# 终端是否只写（只写即只能同步上传不能下载文件），默认为禁用
# write only = false

# 终端是否只读（只读即只能同步下载不能上传文件），默认为只读
# auth users能修改此选项限制
# read only = true

# 过滤器（多个空格分隔），决定哪些文件允许传输
# 语法：[+|-] RULE
#   +       规则前缀，表示排除
#   -       规则前缀，表示包含
#   *       表示通配路径，类似正则的 .+
#   /       表示目录层级
#   文件名  表示目录名或文件名
# 匹配优先级（当匹配多个规则时只选用优先级高的规则）：filter => include from => include => exclude from => exclude
# filter = - .git - .svn

# 排除过滤器（多个空格分隔），决定哪些文件不能传输，语法参考filter
exclude = .git .svn

# 单一排除过滤器（只能指定一个规则），语法参考filter
# exclude from =

# 包含过滤器器（多个空格分隔）开放一些允许传输文件，语法参考filter
# include = config

# 单一包含过滤器（只能指定一个规则），语法参考filter
# include from =

# 允许授权连接传输文件用户名集合（多个逗号或空格分开），默认不限制
# 格式：  name:power
#   name    用户名或组名，@开始表示组名，用户名不要求存在于系统中（是独立于系统用户体系外）
#   power   开放权限：（不指定为 ro/rw）
#               deny    拒绝读写
#               ro      允许只读
#               rw      允许读写
$([ -z "${ARGV_auth}" ] && echo -n '# ')auth users = ${ARGV_auth:-rsync}:ro

# 授权连接密码配置文件，指定auth users选项有效
# 格式：    user:password   或   @group:password
secrets file = $INSTALL_PATH$RSYNC_VERSION/etc/rsyncd.secrets

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
&include $INSTALL_PATH$RSYNC_VERSION/etc/rsyncd.d

# 模块配置
# [www]
# path = 模块路径，可以使用变量
# comment = 描述当前模块
# 专用授权账号
# auth users = rsync:ro

CONF
    fi
    # 开始同步调用脚本
    if [ ! -e ./hook/early.sh ];then
        cat > ./hook/early.sh <<CONF
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
    if [ ! -e ./hook/pre-xfer.sh ];then
        cat > ./hook/pre-xfer.sh <<CONF
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
    if [ ! -e ./hook/post-xfer.sh ];then
        cat > ./hook/post-xfer.sh <<CONF
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
    # 授权密码配置文件
    if [ ! -e ./etc/rsyncd.secrets ];then
        cat > ./etc/rsyncd.secrets <<CONF
# 授权连接密码配置文件，指定auth users选项有效
# 格式：    user:password   或   @group:password

CONF
    fi
    # 写授权和模块配置
    while parse_module;do
        # 写模块配置
        cat > ./etc/rsyncd.d/${MODULE_ITEM[0]}.conf <<CONF
# 模块配置
[${MODULE_ITEM[0]}]
path = ${MODULE_ITEM[1]}
# comment = 描述当前模块
# 专用授权账号
$([ -z "${MODULE_AUTH}" ] && echo -n '# ')auth users = ${MODULE_AUTH:-rsync}:ro
CONF
        # 写授权密码配置
        if [ -n "$MODULE_AUTH" ];then
            edit_conf ./etc/rsyncd.secrets "$MODULE_AUTH:.+" "$MODULE_AUTH:$MODULE_PASSWORD"
        fi
    done
    # 写共用密码
    if [ -n "$RSYNC_PASSWORD" ];then
        echo "$ARGV_auth:$RSYNC_PASSWORD"
        edit_conf ./etc/rsyncd.secrets "$ARGV_auth:.+" "$ARGV_auth:$RSYNC_PASSWORD"
    fi
    # 修改文件权限
    chown -R rsyncd:rsyncd ./*
    # rsync在非root启动时问题较多，可在传输时指定其它用户以减少安全问题
    chmod 600 ./etc/rsyncd.secrets
    chown root:root ./etc/rsyncd.secrets
    chmod -R +x ./hook/
    # 添加服务配置
    SERVICES_CONFIG=()
    SERVICES_CONFIG[$SERVICES_CONFIG_START_RUN]="./bin/rsync --daemon --config=./etc/rsyncd.conf"
    SERVICES_CONFIG[$SERVICES_CONFIG_PID_FILE]="./logs/rsyncd.pid"
    # 服务并启动服务
    add_service SERVICES_CONFIG
fi

info_msg "安装成功：rsync-$RSYNC_VERSION";
