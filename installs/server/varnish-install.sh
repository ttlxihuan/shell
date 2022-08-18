#!/bin/bash
#
# varnish快速编译安装shell脚本
#
# 安装命令
# bash varnish-install.sh new
# bash varnish-install.sh $verions_num
# 
# 查看最新版命令
# bash varnish-install.sh
#
# 可运行系统：
# CentOS 6.4+
# Ubuntu 15.04+
#
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
init_install '3.0.0' "http://varnish-cache.org/releases/index.html" 'varnish-\d+\.\d+\.\d+.tgz'
#  限制空间大小（G）：编译目录、安装目录、内存
install_storage_require 1 1 4
# ************** 相关配置 ******************
# 编译初始选项（这里的指定必需有编译项）
CONFIGURE_OPTIONS="--prefix=$INSTALL_PATH$VARNISH_VERSION"
# ************** 编译安装 ******************
# 下载varnish包
download_software http://varnish-cache.org/_downloads/varnish-$VARNISH_VERSION.tgz
# 解析选项
parse_options CONFIGURE_OPTIONS $DEFAULT_OPTIONS $ARGV_options
# 暂存编译目录
VARNISH_CONFIGURE_PATH=`pwd`

# 安装依赖
info_msg "安装相关已知依赖"

# 安装验证 autoconf
install_autoconf

# 安装验证 libtool
install_libtool

# 安装验证 libedit
install_libedit

# 安装验证 jemalloc
install_jemalloc

# 安装验证 ncurses
install_ncurses

# 安装验证 libpcre
if if_version "$VARNISH_VERSION" ">=" "7.0.0"; then
    install_libpcre2_8
else
    install_libpcre
fi

# 依赖包版本兼容
if if_version "$VARNISH_VERSION" ">=" "6.2.0"; then
    package_manager_run install -PYTHON3_DOCUTILS_PACKAGE_NAMES -PYTHON3_SPHINX_PACKAGE_NAMES
    if ! if_command pip3 || ! pip3 show sphinx -q; then
        if ! if_command python3;then
            run_install_shell python new
        fi
        if if_command pip3;then
            pip3 install sphinx
        else
            error_exit 'python3 和 pip3 安装失败'
        fi
    fi
    if if_version "$VARNISH_VERSION" ">=" "6.3.0";then
        package_manager_run install -LIBUWIND_DEVEL_PACKAGE_NAMES
    fi
else
    package_manager_run install -PYTHON_DOCUTILS_PACKAGE_NAMES -PYTHON_SPHINX_PACKAGE_NAMES
fi

cd $VARNISH_CONFIGURE_PATH
bash autogen.sh
# 编译安装
configure_install $CONFIGURE_OPTIONS
# 创建用户组
add_user varnish
# 基础配置
mkdirs $INSTALL_PATH$VARNISH_VERSION/etc varnish

# 复制配置文件
cp ./etc/example.vcl $INSTALL_PATH$VARNISH_VERSION/etc/default.vcl
cd $INSTALL_PATH$VARNISH_VERSION

# 启动选项
START_SERVER_PARAM=''
if if_version "$VARNISH_VERSION" ">=" "6.6.0"; then
    START_SERVER_PARAM="-n ./var/varnish"
fi

chown -R varnish:varnish ./*

# 添加服务配置
SERVICES_CONFIG=()
SERVICES_CONFIG[$SERVICES_CONFIG_START_RUN]="./sbin/varnishd -f ./etc/default.vcl $START_SERVER_PARAM"
SERVICES_CONFIG[$SERVICES_CONFIG_USER]="varnish"
SERVICES_CONFIG[$SERVICES_CONFIG_PID_FILE]=""
# 服务并启动服务
add_service SERVICES_CONFIG

info_msg "安装成功：varnish-$VARNISH_VERSION"
