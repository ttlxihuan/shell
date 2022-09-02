#!/bin/bash
#
# lvs快速编译安装shell脚本
# 官方地址：http://www.linux-vs.org/zh/index.html
#
# 安装命令
# bash ipvsadm-install.sh new
# bash ipvsadm-install.sh $verions_num
# 
# 查看最新版命令
# bash ipvsadm-install.sh
#
# 可运行系统：
# CentOS 6.4+
# Ubuntu 16.04+
#
# LVS（Linux Virtual Server）是Linux虚拟服务，是一个高性能负载均衡服务。
# ipvsadm是实现LVS工具，ipvsadm依赖系统内核限制，不同的版本对系统内核有要求，
# 不过现在的系统内核基本上已经远远超过了，要求最低的内核是1.1.8。
# ipvsadm最新版本是在2011年2月份更新的，后面没有更新
# LVS是使用虚拟路由冗余协议(Virtual Router Redundancy Protocol，简称VRRP)
#
####################################################################################
##################################### 安装处理 #####################################
####################################################################################
# 定义安装参数
DEFINE_RUN_PARAMS=""
# 加载基本处理
source "$(cd "$(dirname "${BASH_SOURCE[0]}")"; pwd)"/../../includes/install.sh || exit
# 初始化安装
init_install 1.26 "https://mirrors.edge.kernel.org/pub/linux/utils/kernel/ipvsadm/" 'ipvsadm-\d+\.\d+\.tar.gz' '\d+\.\d+'
#  限制空间大小（G）：编译目录、安装目录、内存
install_storage_require 1 1 1
# ************** 编译安装 ******************
# 下载ipvsadm包
# ipvsadm有两部分下载，早期需要区分内核下载，并且太久远了，暂时不提供下载处理
# 早期是1.25及以前的在http://www.linux-vs.org/software/ipvs.html
# 后期的在https://mirrors.edge.kernel.org/pub/linux/utils/kernel/ipvsadm/
download_software https://mirrors.edge.kernel.org/pub/linux/utils/kernel/ipvsadm/ipvsadm-$IPVSADM_VERSION.tar.gz
# 暂存编译目录
IPVSADM_CONFIGURE_PATH=`pwd`
# 安装依赖
info_msg "安装相关已知依赖"
# 编译时报：undefined reference to `xxx' 时说明依赖库文件找不到，一般是依赖包没有安装或版本不匹配
# 安装libnl-dev
if if_version $IPVSADM_VERSION '<' 1.27;then
    # 安装libnl-dev和popt-static
    package_manager_run install -LIBNL_DEVEL_PACKAGE_NAMES -POPT_STATIC_PACKAGE_NAMES
else
    package_manager_run install -LIBNL3_DEVEL_PACKAGE_NAMES
fi
# 安装popt-dev
package_manager_run install -POPT_DEVEL_PACKAGE_NAMES

cd $IPVSADM_CONFIGURE_PATH
# 修改安装目录
export BUILD_ROOT=$INSTALL_PATH$IPVSADM_VERSION
# 编译
make_install $INSTALL_PATH$IPVSADM_VERSION $ARGV_options

# 创建用户组
add_user ipvsadm

cd $INSTALL_PATH$IPVSADM_VERSION
# 配置文件处理
info_msg "ipvsadm 配置文件修改"
# 这里没有配置处理，需要了解下
#
#
#
#

# 添加服务配置
SERVICES_CONFIG=()
SERVICES_CONFIG[$SERVICES_CONFIG_START_RUN]="./bin/ipvsadm"
SERVICES_CONFIG[$SERVICES_CONFIG_PID_FILE]=""
# 服务并启动服务
add_service SERVICES_CONFIG

info_msg "安装成功：$INSTALL_NAME-$IPVSADM_VERSION"
