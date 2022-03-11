#!/bin/bash
#
# redis快速编译安装shell脚本
#
# 安装命令
# bash redis-install.sh new
# bash redis-install.sh $verions_num
# 
# 查看最新版命令
# bash redis-install.sh
#
# 可运行系统：
# CentOS 6.4+
# Ubuntu 15.04+
#
# 下载地址
# https://redis.io/download
#
####################################################################################
##################################### 安装处理 #####################################
####################################################################################
# 定义安装类型
DEFINE_INSTALL_TYPE='make'
# 定义安装参数
DEFINE_INSTALL_PARAMS="
[-b, --bind='127.0.0.1']服务监听绑定地址
[-p, --port='6379']服务监听端口号
[-s, --save='60,5']开启自动保存到硬盘 m,n
#配置规则：n秒 m次修改，为空则不开启
[-P, --password='']安装成功后授权密码
#为空即无密码
#随机生成密码 %num，比如：%10
#指定固定密码，比如：123456
#配置集群时密码需要保持一至且不可随机生成
[-c, --cluster-hosts='']指定集群地址名集 ip:port，端口号不传为默认6379
#多个使用逗号分开，最少三个含当前服务器
#当前监听可不传
[-R, --cluster-replicas=1]指定集群副本数
[-a, --cluster-masterauth='']指定集群通信密码
#为空即无密码
#随机生成密码 %num，比如：%10
#指定固定密码，比如：123456
#配置集群时密码需要保持一至且不可随机生成
[-m, --max-memory='']指定配置服务运行最大占用内存（整数）
#为空即默认可用内存的70%
#指定可用内存占比，比如：70%
#指定对应的大小，单位（B,K,M,G,T），比如：4G
#不指定单位为B
#指定为0时即不配置内存
"
# 加载基本处理
source "$(cd "$(dirname "${BASH_SOURCE[0]}")"; pwd)"/../../includes/install.sh || exit
# 初始化安装
init_install '3.0.0' "http://download.redis.io/releases/" 'redis-\d+\.\d+\.\d+\.tar\.gz'
[ -n "$ARGV_bind" ] || error_exit '--bind 绑定监听地址不能为空'
[ -n "$ARGV_port" ] || error_exit '--bind 监听端口号不能为空'
# 集群限制
if [ -n "$ARGV_cluster_hosts" ];then
    if ! parse_lists CLUSTER_HOSTS "$ARGV_bind:$ARGV_port,$ARGV_cluster_hosts" ',' '\d{1,3}(\.\d{1,3}){3}(:\d{1,5})?';then
        error_exit '--cluster-hosts 集群地址格式错误：'${ARGV_cluster_hosts:$?}
    fi
    if ((${#CLUSTER_HOSTS[@]} < 3));then
        error_exit '--cluster-hosts 集群节点数包含当前节点最少是三个，现有：'${CLUSTER_HOSTS[@]}
    fi
    if (($ARGV_cluster_replicas >= ${#CLUSTER_HOSTS[@]}));then
        error_exit '--cluster-replicas 集群副本数不能等于或超过集群个数，集群只有：'${#CLUSTER_HOSTS[@]}
    fi
    if ! printf '%s' "$ARGV_cluster_replicas"|grep -qP '^[1-9]\d+$';then
        error_exit '--cluster-replicas 集群副本数必需是正整数'
    fi
    parse_use_password REDIS_MASTERAUTH_PASSWORD "$ARGV_cluster_masterauth"
fi
if [ -n "$ARGV_save" ] && ! [[ $ARGV_save =~ ^([0-9]|[1-9][0-9]+),([0-9]|[1-9][0-9]+)$ ]];then
    error_exit '--save 开启自动保存到硬盘参数错误'
fi
# 解析最大运行内存参数处理
if ! parse_use_memory REDIS_MAX_MEMORY "${ARGV_max_memory:-70%}";then
    error_exit '--max-memory 指定错误值'
fi
parse_use_password REDIS_PASSWORD "$ARGV_password"
#  限制空间大小（G）：编译目录、安装目录、内存
install_storage_require 1 1 4
# ************** 编译安装 ******************
# 下载redis包
download_software http://download.redis.io/releases/redis-$REDIS_VERSION.tar.gz

# 新版的redis需要更高的GCC
if if_version "$REDIS_VERSION" ">=" "6.0.0" && if_version "`cc --version|grep -oP '\d+(\.\d+){2}'|head -1`" "<" "5.1.0";then
    run_install_shell gcc 7.5.0
    if_error 'install gcc fail'
fi

# 编译
make_install '' $ARGV_options

# 复制安装包并创建用户
copy_install redis

# redis conf set
info_msg 'redis 配置文件修改'
sed -i -r 's/^(daemonize )no/\1yes/' redis.conf # 后台运行
sed -i -r "s/^(bind ).*/\1$ARGV_bind/" redis.conf # 地址
sed -i -r "s/^(port ).*/\1$ARGV_port/" redis.conf # 端口
# 最大内存，如果不设置可能会导致内存不足机器死机，默认配置为可用内存的70%
if (( REDIS_MAX_MEMORY > 0 ));then
    sed -i -r "s/^(\s*#)?\s*(maxmemory ).*/\2${REDIS_MAX_MEMORY}/" redis.conf
fi
# 最大连接数据
# sed -i -r "s/^(\s*#)?\s*(maxclients )/\220000/" redis.conf
# 开启自动保存到硬盘持久化配置
if [ -n "$ARGV_save" ];then
    sed -i -r "s/^\s*#?\s*(save )\s*60\s*[0-9]+$/\1 ${ARGV_save/,/ }/" redis.conf # 开启60秒内有50次修改自动保存到硬盘
fi
sed -i -r 's/^(dir ).\//\1.\/data/' redis.conf # 数据在磁盘保存目录
# 密码设置
if [ -n "$REDIS_PASSWORD" ];then
    sed -i -r 's/^#\s*(requirepass ).*/\1'${REDIS_PASSWORD}'/' redis.conf # 设置用户连接授权密码
fi
# 集群设置
if [ -n "$ARGV_cluster_hosts" ];then
    sed -i -r 's/^#\s*(cluster-enabled ).*/\1yes/' redis.conf # 开启集群
    sed -i -r 's/^#\s*(cluster-node-timeout ).*/\15000/' redis.conf # 集群节点连接超时毫秒数
    if [ -n "$REDIS_MASTERAUTH_PASSWORD" ];then
        sed -i -r 's/^#\s*(masterauth ).*/\1'${REDIS_MASTERAUTH_PASSWORD}'/' redis.conf # 设置集群连接授权密码
    fi
fi
mkdirs data redis

# 启动服务
sudo_msg redis ./src/redis-server redis.conf

# 创建集群
if [ -n "$ARGV_cluster_hosts" ];then
    # CLUSTER_MEET=''
    # for((INDEX=0;INDEX < ${#CLUSTER_HOSTS[@]};INDEX++));do
    #     CLUSTER_IP=${CLUSTER_HOSTS[$INDEX]/:.*$/}
    #     CLUSTER_PORT=${CLUSTER_HOSTS[$INDEX]/:.*$/}
    #     CLUSTER_MEET=$CLUSTER_MEET"CLUSTER MEET $CLUSTER_IP $CLUSTER_PORT\n"
    # done
    # # 通过命令添加集群处理
    # echo -e "$CLUSTER_MEET"|./src/redis-cli -h $ARGV_bind -p $ARGV_port --pipe
    if if_version $REDIS_VERSION '>=' '5.0.0';then
        ./src/redis-cli --cluster create ${CLUSTER_HOSTS[@]} --cluster-replicas $ARGV_cluster_replicas
    else
        # 安装ruby
        if if_version "2.4.0" '>=' `ruby --version|grep -oP '\d+(\.\d+){2}'`;then
            RUBY_VERSION='2.7.4'
            download_software "https://cache.ruby-lang.org/pub/ruby/${RUBY_VERSION%.*}/ruby-$RUBY_VERSION.tar.gz"
            configure_install --prefix=$INSTALL_BASE_PATH/ruby/$RUBY_VERSION
        fi
        gem install redis
        ./src/redis-trib.rb create --replicas $ARGV_cluster_replicas ${CLUSTER_HOSTS[@]}
    fi
fi

info_msg "安装成功：redis-$REDIS_VERSION";

