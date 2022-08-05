#!/bin/bash
#
# memcached快速编译安装shell脚本
# 官方地址：http://memcached.org/
#
# 安装命令
# bash memcached-install.sh new
# bash memcached-install.sh $verions_num
# 
# 查看最新版命令
# bash memcached-install.sh
#
# 可运行系统：
# CentOS 6.4+
# Ubuntu 15.04+
#
# memcached 是单一键值对类型的缓存服务，体积小性能高，且未提供官方集群方案。
# memcached 比如适合大量键值对缓存，集群一般需要借助三方工具或自行开发。
#
####################################################################################
##################################### 安装处理 #####################################
####################################################################################
# 定义安装参数
DEFINE_INSTALL_TYPE='configure'
DEFINE_INSTALL_PARAMS="
[-m, --max-memory='']指定配置服务运行最大占用内存（整数）
#为空即默认可用内存的50%
#指定可用内存占比，比如：70%
#指定对应的大小，单位（B,K,M,G,T），比如：4G
#不指定单位为B
#指定为0时即不配置内存
"
# 加载基本处理
source "$(cd "$(dirname "${BASH_SOURCE[0]}")"; pwd)"/../../includes/install.sh || exit
# 解析最大运行内存参数处理
if ! parse_use_memory MEMCACHED_MAX_MEMORY "${ARGV_max_memory:-50%}" M;then
    error_exit '--max-memory 指定错误值'
fi
# 初始化安装
# memcached-1.4.6以前版本GCC版本低，高版本编译失败
init_install 1.4.6 "http://memcached.org/downloads" 'memcached-\d+(\.\d+){2}\.tar.gz'
#  限制空间大小（G）：编译目录、安装目录、内存
install_storage_require 1 1 1
# ************** 相关配置 ******************
# 编译初始选项（这里的指定必需有编译项）
CONFIGURE_OPTIONS="--prefix=$INSTALL_PATH$MEMCACHED_VERSION "
# 编译增加项（这里的配置会随着编译版本自动生成编译项）
ADD_OPTIONS=$ARGV_options
# ************** 编译安装 ******************
# 下载memcached包
# memcached 下载分两块，历史版本（1.4.15以前的使用old目录，为兼容后续版本增加下载链接判断）
DOWNLOAD_URL='http://memcached.org/files/'
if ! curl -I ${DOWNLOAD_URL}memcached-$MEMCACHED_VERSION.tar.gz|head -n 1|grep -q '200';then
    DOWNLOAD_URL=$DOWNLOAD_URL'old/'
fi
download_software ${DOWNLOAD_URL}memcached-$MEMCACHED_VERSION.tar.gz

# 解析选项
parse_options CONFIGURE_OPTIONS $ADD_OPTIONS
# 安装依赖
info_msg "安装相关已知依赖"
# 暂存编译目录
MEMCACHED_CONFIGURE_PATH=`pwd`
# 安装libevent
if ! if_lib libevent '>' '2.0.0';then
    # 获取最新版
    get_version LIBEVENT_VERSION https://libevent.org/ 'libevent-\d+(\.\d+)+-stable\.tar\.gz'
    info_msg "安装：libevent-$LIBEVENT_VERSION"
    # 下载
    download_software https://github.com/libevent/libevent/releases/download/release-$LIBEVENT_VERSION-stable/libevent-$LIBEVENT_VERSION-stable.tar.gz libevent-$LIBEVENT_VERSION-stable
    # 编译安装
    configure_install --prefix=$INSTALL_BASE_PATH/libevent/$LIBEVENT_VERSION
    cd $MEMCACHED_CONFIGURE_PATH
    CONFIGURE_OPTIONS=$CONFIGURE_OPTIONS" --with-libevent=$INSTALL_BASE_PATH/libevent/$LIBEVENT_VERSION "
else
    # 获取libevent安装目录
    get_lib_install_path libevent LIBEVENT_INSTALL_PATH
    if [ -n "$LIBEVENT_INSTALL_PATH" ];then
        CONFIGURE_OPTIONS=$CONFIGURE_OPTIONS" --with-libevent=$LIBEVENT_INSTALL_PATH "
    fi
fi
# 编译安装
configure_install $CONFIGURE_OPTIONS
# 创建用户组
add_user memcached
cd $INSTALL_PATH$MEMCACHED_VERSION
# 配置文件处理
# info_msg "memcached 配置文件修改"

# 指定启动参数
PID_FILE=$INSTALL_PATH$MEMCACHED_VERSION/run/memcached.pid
RUN_OPTIONS='-d -u memcached -l 127.0.0.1 -p 11211 -c 10000 -P '$PID_FILE
if ((MEMCACHED_MAX_MEMORY > 0));then
    RUN_OPTIONS=$RUN_OPTIONS" -m ${MEMCACHED_MAX_MEMORY}M"
fi

mkdirs ./run
if [ ! -e "$PID_FILE" ];then
    echo '' > $PID_FILE
fi

chown -R "memcached":"memcached" ./*

# 添加服务配置
SERVICES_CONFIG=()
SERVICES_CONFIG[$SERVICES_CONFIG_START_RUN]="./bin/memcached $RUN_OPTIONS"
SERVICES_CONFIG[$SERVICES_CONFIG_PID_FILE]="./run/memcached.pid"
# 服务并启动服务
add_service SERVICES_CONFIG

info_msg "安装成功：$INSTALL_NAME-$MEMCACHED_VERSION"
