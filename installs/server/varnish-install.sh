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
# 定义安装类型
DEFINE_INSTALL_TYPE='configure'
# 加载基本处理
source $(realpath ${BASH_SOURCE[0]}|sed -r 's/[^\/]+$//')../../includes/install.sh || exit
# 初始化安装
init_install '3.0.0' "http://varnish-cache.org/releases/index.html" 'varnish-\d+\.\d+\.\d+.tgz'
memory_require 4 # 内存最少G
work_path_require 1 # 安装编译目录最少G
install_path_require 1 # 安装目录最少G
# ************** 相关配置 ******************
# 编译初始选项（这里的指定必需有编译项）
CONFIGURE_OPTIONS="--prefix=$INSTALL_PATH$VARNISH_VERSION"
# 编译增加项（这里的配置会随着编译版本自动生成编译项）
ADD_OPTIONS=$ARGV_options
# ************** 编译安装 ******************
# 下载varnish包
download_software http://varnish-cache.org/_downloads/varnish-$VARNISH_VERSION.tgz
# 解析选项
parse_options CONFIGURE_OPTIONS $ADD_OPTIONS
# 安装依赖
info_msg "安装相关已知依赖"
if if_command autoconf;then
    info_msg 'autoconf ok'
else
    packge_manager_run install -AUTOCONF_PACKGE_NAMES
fi
if if_command libtool;then
    info_msg 'libtool ok'
else
    packge_manager_run install -LIBTOOL_PACKGE_NAMES
fi
if if_lib 'libedit';then
    info_msg 'libedit ok'
else
    packge_manager_run install -LIBEDIT_DEVEL_PACKGE_NAMES
fi
if if_command 'jemalloc.sh';then
    info_msg 'jemalloc ok'
else
    packge_manager_run install -JEMALLOC_DEVEL_PACKGE_NAMES
fi
if if_lib 'ncurses';then
    info_msg 'ncurses ok'
else
    packge_manager_run install -NCURSES_DEVEL_PACKGE_NAMES
fi
if if_version "$VARNISH_VERSION" ">=" "7.0.0"; then
    if if_lib 'libpcre2-8';then
        info_msg 'libpcre2-8 ok'
    else
        # 暂存编译目录
        VARNISH_CONFIGURE_PATH=`pwd`
        info_msg '安装：libpcre2-8'
        # 获取最新版
        get_version LIBPCRE2_VERSION https://ftp.pcre.org/pub/pcre/ "pcre2-\d+\.\d+\.tar\.gz"
        info_msg "下载：pcre2-$LIBPCRE2_VERSION"
        # 下载
        download_software https://ftp.pcre.org/pub/pcre/pcre2-$LIBPCRE2_VERSION.tar.gz
        configure_install --prefix=$INSTALL_BASE_PATH/pcre2/$LIBPCRE2_VERSION
        cd $VARNISH_CONFIGURE_PATH
    fi
else
    if if_lib 'libpcre';then
        info_msg 'pcre ok'
    else
        packge_manager_run install -PCRE_DEVEL_PACKGE_NAMES
    fi
fi
# 依赖包版本兼容
if if_version "$VARNISH_VERSION" ">=" "6.2.0"; then
    packge_manager_run install -PYTHON3_DOCUTILS_PACKGE_NAMES -PYTHON3_SPHINX_PACKGE_NAMES
    if ! if_command pip3 || ! pip3 show sphinx -q; then
        if ! if_command python3;then
            run_install_shell python-install.sh new
        fi
        if if_command pip3;then
            pip3 install sphinx
        else
            error_exit 'python3 和 pip3 安装失败'
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
    START_SERVER_PARAM="-n $INSTALL_PATH$VARNISH_VERSION/var/varnish"
fi

chown -R varnish:varnish ./*
# 启动服务
run_msg "./sbin/varnishd -f $INSTALL_PATH$VARNISH_VERSION/etc/default.vcl $START_SERVER_PARAM"
./sbin/varnishd -f $INSTALL_PATH$VARNISH_VERSION/etc/default.vcl $START_SERVER_PARAM

info_msg "安装成功：varnish-$VARNISH_VERSION"
