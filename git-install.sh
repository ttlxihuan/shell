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
# 获取版本配置
VERSION_URL="https://mirrors.edge.kernel.org/pub/software/scm/git/"
VERSION_MATCH='git-\d+\.\d+\.\d+\.tar\.gz'
VERSION_RULE='\d+\.\d+\.\d+'
# 安装目录
INSTALL_PATH="$INSTALL_BASE_PATH/git/"
# 初始化安装
init_install GIT_VERSION "$1"
# 获取工作目录
WORK_PATH='git'
# ************** 相关配置 ******************
# 编译初始选项（这里的指定必需有编译项）
CONFIGURE_OPTIONS="--prefix=$INSTALL_PATH$GIT_VERSION"
# 编译增加项（这里的配置会随着编译版本自动生成编译项）
# 这里配置编译所需要扩展或模块，以模块或扩展名来定义
# 比如 --with-mod 、 --enable-mod 、 --with-mod-dir= 、 --enable-mod-dir= 应该指定为 mod 或 mod=val，如果是上下版本编译增减项则为 ?mod 或 ?=mod=val
# 比如 --without-mod 或 --disable-mod 应该指定为 !mod，如果是上下版本编译增加项则为 ?!mod
# 可直接配置 -mod 、 --mod 、 ?-mod 、 ?--mod 如果指定了?则会判断编译器中是否存在这项
# 所有未配置 ? 的项在解析时未匹配成功则解析不通过
ADD_OPTIONS=''
# 依赖包-包管理器对应包名配置
# 包管理器所需包配置，包名对应命令：yum apt dnf pkg，如果只配置一个则全部通用
LIBXML2_DEVEL_PACKGE_NAMES=('libxml2-devel' 'libxml2-dev')
PERL_DEVEL_PACKGE_NAMES=('perl-devel' 'perl-dev')
echo "install git-$GIT_VERSION"
echo "install path: $INSTALL_PATH"
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
