#!/bin/bash
#
# openssh快速编译安装shell脚本
# 官方文档：http://www.openssh.com/
# 镜像地址集：http://www.openssh.com/portable.html#http
#
# 安装命令
# bash openssh-install.sh new
# bash openssh-install.sh $verions_num
# 
# 查看最新版命令
# bash openssh-install.sh
#
# 可运行系统：
# CentOS 6.4+
# Ubuntu 15.04+
#
# openssh 是sshd、scp、sftp、ssh-keygen、ssh-keyscan、ssh-add、ssh-keysign、sftp-server、ssh-agent等工具的安装源包
# 一般系统均携带有openssh，但版本不是很高，还有些较早的系统没有快速安装包，使用此脚本即可解决安装问题
#
####################################################################################
##################################### 安装处理 #####################################
####################################################################################
# 定义安装类型
DEFINE_INSTALL_TYPE='configure'
# 加载基本处理
source "$(cd "$(dirname "${BASH_SOURCE[0]}")"; pwd)"/../../includes/install.sh || exit
# 初始化安装
# openssh早期版本号是三位的，从3.3起变成两位的，安装即按2位版本号来处理
init_install '4.1p1' "https://ftpmirror.infania.net/pub/OpenBSD/OpenSSH/portable/" 'openssh-\d+\.\d+p\d\.tar\.gz' '\d+\.\d+p\d'
#  限制空间大小（G）：编译目录、安装目录、内存
install_storage_require 1 1 1
# ************** 相关配置 ******************
# 编译初始选项（这里的指定必需有编译项）
CONFIGURE_OPTIONS="--prefix=$INSTALL_PATH$OPENSSH_VERSION "
# 编译增加项（这里的配置会随着编译版本自动生成编译项）
ADD_OPTIONS=$ARGV_options
# ************** 编译安装 ******************
# 下载openssh包
download_software https://ftpmirror.infania.net/pub/OpenBSD/OpenSSH/portable/openssh-$OPENSSH_VERSION.tar.gz openssh-$OPENSSH_VERSION
# 解析选项
parse_options CONFIGURE_OPTIONS $ADD_OPTIONS
# 安装依赖
info_msg "安装相关已知依赖"
# 暂存编译目录
OPENSSH_CONFIGURE_PATH=`pwd`
if if_lib libcrypto;then
    info_msg 'openssl ok'
else
    # 安装openssl-dev
    packge_manager_run install -OPENSSL_DEVEL_PACKGE_NAMES
fi
if if_lib libzip;then
    info_msg 'libzip ok'
else
    # 安装libzip-dev
    packge_manager_run install -ZIP_DEVEL_PACKGE_NAMES
fi
cd $OPENSSH_CONFIGURE_PATH
# --with-ssl-dir= --with-zlib=
# 编译安装
configure_install $CONFIGURE_OPTIONS
# 创建用户组
add_user sshd

# 启动服务
chown -R sshd:sshd ./
sudo -u sshd sshd

# 安装成功
info_msg "安装成功：openssh-$OPENSSH_VERSION";
