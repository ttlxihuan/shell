#!/bin/bash
#
# keepalived快速编译安装shell脚本
# 官方地址：https://www.keepalived.org/index.html
#
# 安装命令
# bash keepalived-install.sh new
# bash keepalived-install.sh $verions_num
# 
# 查看最新版命令
# bash keepalived-install.sh
#
# 可运行系统：
# CentOS 6.4+
# Ubuntu 15.04+
#
# keepalived由C开发的路由软件，用于高可用自动切换备用节点的一种解决方案
#
# 1、编译报错：error: unknown type name ‘bool’，在c99标准中存在（编译时使用-std=c99也可以指定），在90标准中不存在。可以对应编译文件中增加头文件代码： #include <stdbool.h>
#       排查gcc支持哪些语言标准，且默认是哪个标准，可通过对应版本的文档查看（注意修改文档地址的版本号） https://gcc.gnu.org/onlinedocs/gcc-4.8.0/gcc/C-Dialect-Options.html#C-Dialect-Options ，进入文档后查看 This is the default for C code. 
#
#
####################################################################################
##################################### 安装处理 #####################################
####################################################################################
# 定义安装类型
DEFINE_INSTALL_TYPE='configure'
# 定义安装参数
DEFINE_INSTALL_PARAMS="

"
# 加载基本处理
source "$(cd "$(dirname "${BASH_SOURCE[0]}")"; pwd)"/../../includes/install.sh || exit

# 初始化安装
init_install 1.1.0 "https://www.keepalived.org/download.html" 'keepalived-\d+(\.\d+){2}.tar.gz'
#  限制空间大小（G）：编译目录、安装目录、内存
install_storage_require 1 1 1
# ************** 相关配置 ******************
# 编译初始选项（这里的指定必需有编译项）
CONFIGURE_OPTIONS="--prefix=$INSTALL_PATH$KEEPALIVED_VERSION "
# 编译增加项（这里的配置会随着编译版本自动生成编译项）
ADD_OPTIONS=' '$ARGV_options
# ************** 编译安装 ******************
# 下载keepalived包
download_software https://www.keepalived.org/software/keepalived-$KEEPALIVED_VERSION.tar.gz

# 解析选项
parse_options CONFIGURE_OPTIONS $ADD_OPTIONS

# 暂存编译目录
KEEPALIVED_CONFIGURE_PATH=$(pwd)

# 安装依赖
info_msg "安装相关已知依赖"

if if_version "$KEEPALIVED_VERSION" '<' '2.0.0';then
    if if_version "$KEEPALIVED_VERSION" '<' '1.2.9';then
        # 安装popt-dev
        packge_manager_run install -POPT_STATIC_PACKGE_NAMES -POPT_DEVEL_PACKGE_NAMES
    else
        packge_manager_run install -KERNEL_HEADERS_PACKGE_NAMES -GLIBC_DEVEL_PACKGE_NAMES
    fi
fi

if if_version "$KEEPALIVED_VERSION" '<' '1.3.0';then
    packge_manager_run install -LIBNL_DEVEL_PACKGE_NAMES
else
    packge_manager_run install -LIBNL3_DEVEL_PACKGE_NAMES -LIBNL3_ROUTE_DEVEL_PACKGE_NAMES -LIBNFNETLINK_DEVEL_PACKGE_NAMES
    # 安装其它依赖
    packge_manager_run install -IPTABLES_DEVEL_PACKGE_NAMES -IPSET_DEVEL_PACKGE_NAMES
    # ipset版本不通过超过6.38（7.0开始修改了ipset_*之类函数定义），会报错：error: unknown type name ‘ipset_outfn’; did you mean ‘ipset_printfn’?
    # if if_command ipset &&  if_version $(ipset --version) '>=' '7.0';then
    #     download_software https://ipset.netfilter.org/ipset-6.38.tar.bz2
    #     configure_install
    # fi
    # # glibc版本2.12以上才可以安装keepalived-2.0+，目前建议安装到2.20
    # if if_version $(getconf GNU_LIBC_VERSION|grep -oP '\d+(\.\d+)+') '<=' '2.12';then
    #     # 安装glibc较高点版本，太高安装容易失败
    #     # Centos 6.4在使用gcc-4.8.4 ~ 4.9.2 编译时容易报错 Error: no such instruction: `vinserti128 $1,%xmm0,%ymm0,%ymm0'
    #     # 需要错开gcc的这些版本，也可以安装较低的gcc版本
    #     download_software http://ftp.gnu.org/gnu/libc/glibc-2.20.tar.bz2
    #     mkdirs bind
    #     echo '../configure' > bind/configure
    #     chmod u+x bind/configure
    #     cd bind
    #     configure_install --disable-sanity-checks
    # fi
fi


# 安装openssl-dev
packge_manager_run install -OPENSSL_DEVEL_PACKGE_NAMES

# 暂时没有看到效果，可能需要更新高版本，预计需要glibc-3.0+
# packge_manager_run install -GLIBC_DEVEL_PACKGE_NAMES




cd $KEEPALIVED_CONFIGURE_PATH

# 此文件需要增加头文件
# keepalived/core/process.c


# 高版本依赖
# packge_manager_run install -IPTABLES_DEVEL_PACKGE_NAMES -IPSET_DEVEL_PACKGE_NAMES -LIBNL3_DEVEL_PACKGE_NAMES -LIBNFNETLINK_DEVEL_PACKGE_NAMES

# yum install -y file-devel net-snmp-devel glib2-devel pcre2-devel libnftnl-devel libmnl-devel systemd-devel kmod-devel
# yum install glibc-devel

# 编译安装
configure_install $CONFIGURE_OPTIONS
# 创建用户组
add_user keepalived
# 配置文件处理
info_msg "keepalived 配置文件修改"

# 启动服务


info_msg "安装成功：$INSTALL_NAME-$KEEPALIVED_VERSION"

