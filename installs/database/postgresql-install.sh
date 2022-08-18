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
# CentOS 6.4+
# Ubuntu 15.04+
#
# 下载地址：https://www.postgresql.org/download/
#
#
####################################################################################
##################################### 安装处理 #####################################
####################################################################################
# 定义安装类型
DEFINE_INSTALL_TYPE='configure'
# 编译默认项（这里的配置会随着编译版本自动生成编译项）
DEFAULT_OPTIONS=''
# 加载基本处理
source "$(cd "$(dirname "${BASH_SOURCE[0]}")"; pwd)"/../../includes/install.sh || exit
# 初始化安装
init_install '6.1' "https://www.postgresql.org/ftp/source/" 'v\d+\.\d+(\.\d+)?' '\d+\.\d+(\.\d+)?'
#  限制空间大小（G）：编译目录、安装目录、内存
install_storage_require 1 1 4
# ************** 相关配置 ******************
# 编译初始选项（这里的指定必需有编译项）
CONFIGURE_OPTIONS="--prefix=$INSTALL_PATH$POSTGRESQL_VERSION "
# ************** 编译安装 ******************
# 下载postgresql包
download_software https://ftp.postgresql.org/pub/source/v$POSTGRESQL_VERSION/postgresql-$POSTGRESQL_VERSION.tar.gz
# 解析选项
parse_options CONFIGURE_OPTIONS $DEFAULT_OPTIONS $ARGV_options

# 暂存编译目录
POSTGRESQL_CONFIGURE_PATH=`pwd`

# 安装依赖
info_msg "安装相关已知依赖"

# 安装验证 gcc
install_gcc

# 安装验证 libzip
install_zip

# 安装验证 bzip2
install_bzip2

# 安装验证 readline
install_readline

cd $POSTGRESQL_CONFIGURE_PATH
# 编译安装
configure_install $CONFIGURE_OPTIONS

# 创建用户组
add_user postgresql
cd $INSTALL_PATH$POSTGRESQL_VERSION

info_msg "postgresql 基本配置处理"
mkdirs ./database postgresql

# 初始化数据
sudo_msg postgresql ./bin/initdb -D $INSTALL_PATH$POSTGRESQL_VERSION/database
# 修改配置
if [ -e ./database/postgresql.conf ];then
    sed -i -r "s,^#*\s*(external_pid_file\s*=).*(#.*)$,\1 './postgresql.pid' \2," ./database/postgresql.conf
fi

# 添加服务配置
SERVICES_CONFIG=()
SERVICES_CONFIG[$SERVICES_CONFIG_START_RUN]="./bin/pg_ctl start -D ./database"
SERVICES_CONFIG[$SERVICES_CONFIG_RESTART_RUN]="./bin/pg_ctl restart -D ./database"
SERVICES_CONFIG[$SERVICES_CONFIG_STOP_RUN]="./bin/pg_ctl stop -D ./database"
SERVICES_CONFIG[$SERVICES_CONFIG_STATUS_RUN]="./bin/pg_ctl status -D ./database"
SERVICES_CONFIG[$SERVICES_CONFIG_USER]="postgresql"
SERVICES_CONFIG[$SERVICES_CONFIG_PID_FILE]="./database/postgresql.pid"
# 服务并启动服务
add_service SERVICES_CONFIG

info_msg "安装成功：postgresql-$POSTGRESQL_VERSION"

