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
# Ubuntu 15.04+
#
# 是一个跨平台的数据同步工具，支持远程增量，可以使用scp、ssh、socket方式传输文件
# rsync需要配置服务端和客户同步端，客户同步端会自动同步服务端的变动文件
# 同步是由服务端监控指定目录，当文件或目录发生变化实时通知客户端进行同步操作
#
####################################################################################
##################################### 安装处理 #####################################
####################################################################################
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

# 配置文件处理
# info_msg 'rsync 配置文件修改'

info_msg "安装成功：rsync-$RSYNC_VERSION";
