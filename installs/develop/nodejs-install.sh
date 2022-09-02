#!/bin/bash
#
# nodejs快速编译安装shell脚本
#
# 安装命令
# bash nodejs-install.sh new
# bash nodejs-install.sh $verions_num
# 
# 查看最新版命令
# bash nodejs-install.sh
#
# 可运行系统：
# CentOS 6.4+
# Ubuntu 16.04+
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
init_install '8.0.0' "https://nodejs.org/zh-cn/download/" 'v\d+\.\d+\.\d+/'
#  限制空间大小（G）：编译目录、安装目录、内存
install_storage_require 1 1 4
# ************** 相关配置 ******************
# 编译初始选项（这里的指定必需有编译项）
CONFIGURE_OPTIONS="--prefix=$INSTALL_PATH$NODEJS_VERSION"
# ************** 编译安装 ******************
# 下载nodejs包
download_software https://nodejs.org/dist/v$NODEJS_VERSION/node-v$NODEJS_VERSION.tar.gz
# 解析选项
parse_options CONFIGURE_OPTIONS $DEFAULT_OPTIONS $ARGV_options
# 暂存编译目录
NODEJS_CONFIGURE_PATH=`pwd`
# 安装依赖
info_msg "安装相关已知依赖"
# 在编译目录里BUILDING.md文件有说明依赖版本要求，GCC在不同的大版本中有差异
GCC_MIN_VERSION="`cat BUILDING.md|grep -oP '\`gcc\` and \`g\+\+\` (>= )?\d+(\.\d+)+ or newer'|grep -oP '\d+(\.\d+)+'`"
if [ -n "$GCC_MIN_VERSION" ];then
    repair_version GCC_MIN_VERSION
    install_gcc "$GCC_MIN_VERSION"
else
    warn_msg '获取 gcc 最低版本号失败'
fi

# 安装python
PYTHON_MIN_VERSION=`cat BUILDING.md|grep -oP 'Python\s+\d+(\.\d+)+'|grep -oP '\d+(\.\d+)+'|head -n 1`
if [ -n "$PYTHON_MIN_VERSION" ];then
    repair_version PYTHON_MIN_VERSION
    install_python "$PYTHON_MIN_VERSION"
else
    warn_msg '获取 python 最低版本号失败'
fi

cd $NODEJS_CONFIGURE_PATH
# 编译安装
configure_install $CONFIGURE_OPTIONS

info_msg "安装成功：nodejs-$NODEJS_VERSION";
