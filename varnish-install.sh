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
# CentOS 5+
# Ubuntu 15+
#
#
####################################################################################
##################################### 安装处理 #####################################
####################################################################################
# 加载基本处理
source basic.sh
# 获取版本配置
VERSION_URL="http://varnish-cache.org/releases/index.html"
VERSION_MATCH='varnish-\d+\.\d+\.\d+.tgz'
VERSION_RULE='\d+\.\d+\.\d+'
# 安装目录
INSTALL_PATH="$INSTALL_BASE_PATH/varnish/"
# 初始化安装
init_install VARNISH_VERSION "$1"
# 获取工作目录
WORK_PATH='varnish'
# ************** 相关配置 ******************
# 编译初始选项（这里的指定必需有编译项）
CONFIGURE_OPTIONS="--prefix=$INSTALL_PATH$VARNISH_VERSION"
# 依赖包-包管理器对应包名配置
# 包管理器所需包配置，包名对应命令：yum apt dnf pkg，如果只配置一个则全部通用
AUTOCONF_PACKGE_NAMES=('autoconf')
JEMALLOC_DEVEL_PACKGE_NAMES=('jemalloc-devel' 'libjemalloc-dev')
LIBEDIT_DEVEL_PACKGE_NAMES=('libedit-devel' 'libedit-dev')
LIBTOOL_PACKGE_NAMES=('libtool')
LIBUWIND_DEVEL_PACKGE_NAMES=('libunwind-devel' '-')
NCURSES_DEVEL_PACKGE_NAMES=('ncurses-devel' 'libncurses-dev')
PCRE_DEVEL_PACKGE_NAMES=('pcre-devel' 'libpcre3-dev')
PKGCONFIG_PACKGE_NAMES=('pkgconfig' 'pkg-config')
PYTHON3_DOCUTILS_PACKGE_NAMES=('-' 'python3-docutils')
PYTHON3_SPHINX_PACKGE_NAMES=('-' 'python3-sphinx')
PYTHON_DOCUTILS_PACKGE_NAMES=('python-docutils')
PYTHON_SPHINX_PACKGE_NAMES=('python-sphinx')
echo "install varnish-$VARNISH_VERSION"
echo "install path: $INSTALL_PATH"
# ************** 编译安装 ******************
# 下载varnish包
download_software http://varnish-cache.org/_downloads/varnish-$VARNISH_VERSION.tgz
# 安装依赖
echo "install dependence"

packge_manager_run install -AUTOCONF_PACKGE_NAMES -JEMALLOC_DEVEL_PACKGE_NAMES -LIBEDIT_DEVEL_PACKGE_NAMES -LIBTOOL_PACKGE_NAMES
packge_manager_run install -NCURSES_DEVEL_PACKGE_NAMES -PCRE_DEVEL_PACKGE_NAMES -PKGCONFIG_PACKGE_NAMES
# 依赖包版本兼容
if if_version "$VARNISH_VERSION" ">=" "6.2.0"; then
    packge_manager_run install -PYTHON3_DOCUTILS_PACKGE_NAMES -PYTHON3_SPHINX_PACKGE_NAMES
    if ! if_command pip3 || ! pip3 show sphinx -q; then
        if ! if_command python3;then
            bash python-install.sh new
        fi
        if if_command pip3;then
            pip3 install sphinx
        else
            error_exit 'not install python3 and pip3'
        fi
    fi
    if if_version "$VARNISH_VERSION" ">=" "6.3.0";then
        packge_manager_run install -LIBUWIND_DEVEL_PACKGE_NAMES
    fi
else
    packge_manager_run install -PYTHON_DOCUTILS_PACKGE_NAMES -PYTHON_SPHINX_PACKGE_NAMES
fi
bash autogen.sh
# 编译安装
configure_install $CONFIGURE_OPTIONS

# 基础配置
mkdir $INSTALL_PATH$VARNISH_VERSION/etc
cp ./etc/example.vcl $INSTALL_PATH$VARNISH_VERSION/etc/default.vcl
cd $INSTALL_PATH$VARNISH_VERSION

# 启动服务
./sbin/varnishd -f $INSTALL_PATH$VARNISH_VERSION/etc/default.vcl

echo "install varnish-$VARNISH_VERSION success!"
