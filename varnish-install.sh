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
# 获取工作目录
INSTALL_NAME='varnish'
# 获取版本配置
VERSION_URL="http://varnish-cache.org/releases/index.html"
VERSION_MATCH='varnish-\d+\.\d+\.\d+.tgz'
VERSION_RULE='\d+\.\d+\.\d+'
# 安装最小版本
VARNISH_VERSION_MIN='3.0.0'
# 初始化安装
init_install VARNISH_VERSION
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
echo "install dependence"
if if_command autoconf;then
    echo 'autoconf ok'
else
    packge_manager_run install -AUTOCONF_PACKGE_NAMES
fi
if if_command libtool;then
    echo 'libtool ok'
else
    packge_manager_run install -LIBTOOL_PACKGE_NAMES
fi
if if_lib 'libedit';then
    echo 'libedit ok'
else
    packge_manager_run install -LIBEDIT_DEVEL_PACKGE_NAMES
fi
if if_command 'jemalloc.sh';then
    echo 'jemalloc ok'
else
    packge_manager_run install -JEMALLOC_DEVEL_PACKGE_NAMES
fi
if if_lib 'ncurses';then
    echo 'ncurses ok'
else
    packge_manager_run install -NCURSES_DEVEL_PACKGE_NAMES
fi
if if_lib 'libpcre';then
    echo 'pcre ok'
else
    packge_manager_run install -PCRE_DEVEL_PACKGE_NAMES
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
if [ ! -d "$INSTALL_PATH$VARNISH_VERSION/etc" ];then
    mkdir $INSTALL_PATH$VARNISH_VERSION/etc
fi
# 复制配置文件
cp ./etc/example.vcl $INSTALL_PATH$VARNISH_VERSION/etc/default.vcl
cd $INSTALL_PATH$VARNISH_VERSION

# 创建用户组
add_user varnish

# 启动服务
echo "sudo -u varnish ./sbin/varnishd -f $INSTALL_PATH$VARNISH_VERSION/etc/default.vcl"
sudo -u varnish ./sbin/varnishd -f $INSTALL_PATH$VARNISH_VERSION/etc/default.vcl

echo "install varnish-$VARNISH_VERSION success!"
