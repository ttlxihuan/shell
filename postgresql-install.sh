#!/bin/bash
#
# PostgreSQL快速编译安装shell脚本
#
# 安装命令
# bash postgresql-install.sh new
# bash postgresql-install.sh $verions_num
# 
# 查看最新版命令
# bash postgresql-install.sh
#
# 可运行系统：
# CentOS 5+
# Ubuntu 15+
#
# 下载地址：https://www.postgresql.org/download/
#
#
####################################################################################
##################################### 安装处理 #####################################
####################################################################################
# 加载基本处理
source basic.sh
# 获取工作目录
INSTALL_NAME='postgresql'
# 获取版本配置
VERSION_URL="https://www.postgresql.org/ftp/source/"
VERSION_MATCH='v\d+\.\d+(\.\d+)?'
VERSION_RULE='\d+\.\d+(\.\d+)?'
# 安装最小版本
POSTGRESQL_VERSION_MIN='6.1'
# 初始化安装
init_install POSTGRESQL_VERSION "$1"
# ************** 相关配置 ******************
# 编译初始选项（这里的指定必需有编译项）
CONFIGURE_OPTIONS="--prefix=$INSTALL_PATH$POSTGRESQL_VERSION"
# ************** 编译安装 ******************
# 下载postgresql包
download_software https://ftp.postgresql.org/pub/source/v$POSTGRESQL_VERSION/postgresql-$POSTGRESQL_VERSION.tar.gz
# 安装依赖
echo "install dependence"

packge_manager_run install -READLINE_DEVEL_PACKGE_NAMES -BZIP2_PACKGE_NAMES -ZLIB_DEVEL_PACKGE_NAMES

if ! if_command 'gcc';then
    packge_manager_run install -GCC_C_PACKGE_NAMES
fi

# 编译安装
configure_install $CONFIGURE_OPTIONS

# 创建用户组
add_user postgresql
cd $INSTALL_PATH$POSTGRESQL_VERSION

echo "postgresql config set"
if [ ! -d './database' ];then
    mkdir ./database
fi
chown postgresql:postgresql ./database
# 初始化数据
sudo -u postgresql ./bin/initdb -D $INSTALL_PATH$POSTGRESQL_VERSION/database

# 启动服务
sudo -u postgresql ./bin/pg_ctl -D ./database start

echo "install $INSTALL_NAME-$POSTGRESQL_VERSION success!"

