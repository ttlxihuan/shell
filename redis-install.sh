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
# CentOS 5+
# Ubuntu 15+
#
# 下载地址
# https://redis.io/download
#
####################################################################################
##################################### 安装处理 #####################################
####################################################################################
# 加载基本处理
source basic.sh
# 获取工作目录
INSTALL_NAME='redis'
# 获取版本配置
VERSION_URL="http://download.redis.io/releases/"
VERSION_MATCH='redis-\d+\.\d+\.\d+\.tar\.gz'
VERSION_RULE='\d+\.\d+\.\d+'
# 安装最小版本
REDIS_VERSION_MIN='2.9.0'
# 初始化安装
init_install REDIS_VERSION
# ************** 编译安装 ******************
# 下载redis包
download_software http://download.redis.io/releases/redis-$REDIS_VERSION.tar.gz

# 新版的redis需要更高的GCC
if if_version "$REDIS_VERSION" ">=" "6.0.0" && if_version "`cc --version|grep -oP '\d+(\.\d+){2}'|head -1`" "<" "5.1.0";then
    run_install_shell gcc-install.sh 7.5.0
    if_error 'install gcc fail'
fi

# 编译
make_install

# 复制安装包
mkdir -p $INSTALL_PATH/$REDIS_VERSION
cp -R ./* $INSTALL_PATH/$REDIS_VERSION
cd $INSTALL_PATH/$REDIS_VERSION

# redis conf set
sed -i 's/daemonize no/daemonize yes/' redis.conf
sed -i 's/dir .\//dir .\/data/' redis.conf
mkdir data

# start server
echo './src/redis-server redis.conf'
./src/redis-server redis.conf

echo "install redis-$REDIS_VERSION success!";

