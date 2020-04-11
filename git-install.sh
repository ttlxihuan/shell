#!/bin/bash
#
# git快速编译安装shell脚本
#
# 安装命令
# bash git-install.sh new
# bash git-install.sh $verions_num
# 
# 查看最新版命令
# bash git-install.sh
#
# 可运行系统：
# CentOS 5+
# Ubuntu 15+
#
# 下载地址
# https://mirrors.edge.kernel.org/pub/software/scm/git/
#
####################################################################################
##################################### 安装处理 #####################################
####################################################################################
# 加载基本处理
source basic.sh
# 获取工作目录
INSTALL_NAME='git'
# 获取版本配置
VERSION_URL="https://mirrors.edge.kernel.org/pub/software/scm/git/"
VERSION_MATCH='git-\d+\.\d+\.\d+\.tar\.gz'
VERSION_RULE='\d+\.\d+\.\d+'
# 初始化安装
init_install GIT_VERSION "$1"
# ************** 编译项配置 ******************
# 编译初始选项（这里的指定必需有编译项）
CONFIGURE_OPTIONS="--prefix=$INSTALL_PATH$GIT_VERSION"
# 编译增加项（这里的配置会随着编译版本自动生成编译项）
ADD_OPTIONS=''
# ************** 编译安装 ******************
# 下载git包
download_software https://mirrors.edge.kernel.org/pub/software/scm/git/git-$GIT_VERSION.tar.gz
# 解析选项
parse_options CONFIGURE_OPTIONS $ADD_OPTIONS
# 安装依赖
echo "install dependence"
packge_manager_run install -LIBXML2_DEVEL_PACKGE_NAMES -PERL_DEVEL_PACKGE_NAMES

# 编译安装
configure_install $CONFIGURE_OPTIONS

echo "install git-$GIT_VERSION success!"
