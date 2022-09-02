#!/bin/bash
#
# python快速编译安装shell脚本
#
# 安装命令
# bash python-install.sh new
# bash python-install.sh $verions_num
# 
# 查看最新版命令
# bash python-install.sh
#
# 可运行系统：
# CentOS 6.4+
# Ubuntu 16.04+
#
# 注意：
#   1、编译安装时gcc的版本不需要太高，太高容易造成编译失败，可直接使用包管理器安装gcc
#   2、编译时使用 --enable-shared 选项，有些情况会要求配置动态库地址，否则python无法使用，没有特殊要求可以不加这个选项
#
# 常见错误：
#   1、WARNING: pip is configured with locations that require TLS/SSL, however the ssl module in Python is not available.
#       ERROR: Could not find a version that satisfies the requirement pip (from versions: none)
#       ERROR: No matching distribution found for pip
#    未安装好ssl模块，必需重新编译安装，ssl模块对openssl有版本要求，编译时注意关注Openssl相关验证是否通过，未通过即有可能未能正常安装ssl模块
#
#
####################################################################################
##################################### 安装处理 #####################################
####################################################################################
# 定义安装类型
DEFINE_INSTALL_TYPE='configure'
# 编译默认项（这里的配置会随着编译版本自动生成编译项）
DEFAULT_OPTIONS='?ipv6 ?optimizations ?lto ?shared'
# 加载基本处理
source "$(cd "$(dirname "${BASH_SOURCE[0]}")"; pwd)"/../../includes/install.sh || exit
# 初始化安装
init_install '2.6.0' "https://www.python.org/downloads/source/" 'Python-\d+\.\d+\.\d+\.tgz'
#  限制空间大小（G）：编译目录、安装目录、内存
install_storage_require 1 1 4
# ************** 相关配置 ******************
# 编译初始选项（这里的指定必需有编译项）
CONFIGURE_OPTIONS="--prefix=$INSTALL_PATH$PYTHON_VERSION "
# ************** 编译安装 ******************
# 下载python包
download_software https://www.python.org/ftp/python/$PYTHON_VERSION/Python-$PYTHON_VERSION.tgz
# 解析选项
parse_options CONFIGURE_OPTIONS $DEFAULT_OPTIONS $ARGV_options
# 暂存编译目录
PYTHON_CONFIGURE_PATH=`pwd`
# 安装依赖
info_msg "安装相关已知依赖"

# 安装验证 gcc
install_gcc

# openssl最低版本
if if_version $PYTHON_VERSION '>=' '3.10.0';then
    OPENSSL_MIN_VERSION='1.1.1'
elif if_version $PYTHON_VERSION '>=' '3.6.0';then
    OPENSSL_MIN_VERSION='1.0.2'
fi

if ! install_openssl "$OPENSSL_MIN_VERSION" '' '' 1;then
    OPENSSL_DIR=$(pwd)
fi

# 安装验证 zlib
install_zlib '1.2.8' '' '1.2.11'

# 安装验证 bzip2
install_bzip2

# 版本在3.7时需要，以下依赖
if if_version "$PYTHON_VERSION" "<" "3.7.5" && if_version "$PYTHON_VERSION" ">=" "3.7.0";then
    # 安装验证 libffi
    install_libffi
fi

cd $PYTHON_CONFIGURE_PATH
# 编译安装
configure_install $CONFIGURE_OPTIONS
# 添加动态库目录
add_so_config $INSTALL_PATH$PYTHON_VERSION

# 添加不同版本的连接
if if_version "$PYTHON_VERSION" ">=" "3.0.0";then
    # 添加启动连接
    ln -svf $INSTALL_PATH$PYTHON_VERSION/bin/python3 /usr/local/bin/python3
    PIP_COMMAND_NAME='pip3'
    PYTHON_COMMAND_NAME='python3'
elif if_version "$PYTHON_VERSION" ">=" "2.0.0";then
    # 添加启动连接
    ln -svf $INSTALL_PATH$PYTHON_VERSION/bin/python /usr/local/bin/python
    PIP_COMMAND_NAME='pip'
    PYTHON_COMMAND_NAME='python2'
fi
if [ -n "$PYTHON_COMMAND_NAME" ]; then
    ln -svf $INSTALL_PATH$PYTHON_VERSION/bin/$PYTHON_COMMAND_NAME /usr/local/bin/$PYTHON_COMMAND_NAME
    if [ -e "$INSTALL_PATH$PYTHON_VERSION/bin/$PIP_COMMAND_NAME" ]; then
        # 安装验证 pip
        install_pip "$INSTALL_PATH$PYTHON_VERSION/bin/$PYTHON_COMMAND_NAME"
    fi
fi

info_msg "安装成功：python-$PYTHON_VERSION"

