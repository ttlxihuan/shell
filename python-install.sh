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
# CentOS 5+
# Ubuntu 15+
#
#
####################################################################################
##################################### 安装处理 #####################################
####################################################################################
# 加载基本处理
source basic.sh
# 获取工作目录
INSTALL_NAME='python'
# 获取版本配置
VERSION_URL="https://www.python.org/downloads/source/"
VERSION_MATCH='Python-\d+\.\d+\.\d+\.tgz'
VERSION_RULE='\d+\.\d+\.\d+'
# 初始化安装
init_install PYTHON_VERSION "$1"
# ************** 相关配置 ******************
# 编译初始选项（这里的指定必需有编译项）
CONFIGURE_OPTIONS="--prefix=$INSTALL_PATH$PYTHON_VERSION"
# ************** 编译安装 ******************
# 下载python包
download_software https://www.python.org/ftp/python/$PYTHON_VERSION/Python-$PYTHON_VERSION.tgz
# 安装依赖
echo "install dependence"

# 编译安装
configure_install $CONFIGURE_OPTIONS

echo "install python-$PYTHON_VERSION success!"

