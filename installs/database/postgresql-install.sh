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
# 加载基本处理
source $(cd $(dirname ${BASH_SOURCE[0]}); pwd)/../../includes/install.sh || exit
# 初始化安装
init_install '6.1' "https://www.postgresql.org/ftp/source/" 'v\d+\.\d+(\.\d+)?' '\d+\.\d+(\.\d+)?'
#  限制空间大小（G）：编译目录、安装目录、内存
install_storage_require 1 1 4
# ************** 相关配置 ******************
# 编译初始选项（这里的指定必需有编译项）
CONFIGURE_OPTIONS="--prefix=$INSTALL_PATH$POSTGRESQL_VERSION "
# 编译增加项（这里的配置会随着编译版本自动生成编译项）
ADD_OPTIONS=$ARGV_options
# ************** 编译安装 ******************
# 下载postgresql包
download_software https://ftp.postgresql.org/pub/source/v$POSTGRESQL_VERSION/postgresql-$POSTGRESQL_VERSION.tar.gz
# 解析选项
parse_options CONFIGURE_OPTIONS $ADD_OPTIONS
# 安装依赖
info_msg "安装相关已知依赖"

packge_manager_run install -READLINE_DEVEL_PACKGE_NAMES -BZIP2_PACKGE_NAMES -ZLIB_DEVEL_PACKGE_NAMES

if ! if_command 'gcc';then
    packge_manager_run install -GCC_C_PACKGE_NAMES
fi

# 编译安装
configure_install $CONFIGURE_OPTIONS

# 创建用户组
add_user postgresql
cd $INSTALL_PATH$POSTGRESQL_VERSION

info_msg "postgresql 基本配置处理"
mkdirs ./database postgresql

# 初始化数据
sudo -u postgresql ./bin/initdb -D $INSTALL_PATH$POSTGRESQL_VERSION/database

# 启动服务
run_msg sudo -u postgresql ./bin/pg_ctl -D ./database start

info_msg "安装成功：postgresql-$POSTGRESQL_VERSION"

