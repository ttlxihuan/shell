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
# 定义安装类型
DEFINE_INSTALL_TYPE='make'
# 加载基本处理
source basic.sh
# 初始化安装
init_install '2.9.0' "http://download.redis.io/releases/" 'redis-\d+\.\d+\.\d+\.tar\.gz'
# ************** 编译安装 ******************
# 下载redis包
download_software http://download.redis.io/releases/redis-$REDIS_VERSION.tar.gz

# 新版的redis需要更高的GCC
if if_version "$REDIS_VERSION" ">=" "6.0.0" && if_version "`cc --version|grep -oP '\d+(\.\d+){2}'|head -1`" "<" "5.1.0";then
    run_install_shell gcc-install.sh 7.5.0
    if_error 'install gcc fail'
fi

# 编译
make_install $ARGV_options

# 创建用户组
add_user redis

# 复制安装包
mkdirs $INSTALL_PATH/$REDIS_VERSION redis
echo '复制所有文件到：'$INSTALL_PATH/$REDIS_VERSION
cp -R ./* $INSTALL_PATH/$REDIS_VERSION
cd $INSTALL_PATH/$REDIS_VERSION

# redis conf set
echo 'redis 配置文件修改'
sed -i -r 's/^(daemonize )no/\1yes/' redis.conf
sed -i -r 's/^(dir ).\//\1.\/data/' redis.conf
mkdirs data redis

# 启动服务
echo 'sudo -u redis ./src/redis-server redis.conf'
sudo -u redis ./src/redis-server redis.conf

echo "安装成功：redis-$REDIS_VERSION";

