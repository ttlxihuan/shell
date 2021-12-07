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
# 注意：
#   1、编译安装时gcc的版本不需要太高，太高容易造成编译失败，可直接使用包管理器安装gcc
#   2、编译时使用 --enable-shared 选项，有些情况会要求配置动态库地址，否则python无法使用，没有特殊要求可以不加这个选项
#
####################################################################################
##################################### 安装处理 #####################################
####################################################################################
# 定义安装类型
DEFINE_INSTALL_TYPE='configure'
# 加载基本处理
source $(cd $(dirname ${BASH_SOURCE[0]}); pwd)/../../includes/install.sh || exit
# 初始化安装
init_install '2.6.0' "https://www.python.org/downloads/source/" 'Python-\d+\.\d+\.\d+\.tgz'
memory_require 4 # 内存最少G
work_path_require 1 # 安装编译目录最少G
install_path_require 1 # 安装目录最少G
# ************** 相关配置 ******************
# 编译初始选项（这里的指定必需有编译项）
CONFIGURE_OPTIONS="--prefix=$INSTALL_PATH$PYTHON_VERSION "
# 编译增加项（这里的配置会随着编译版本自动生成编译项）
ADD_OPTIONS='?ipv6 '$ARGV_options
# ************** 编译安装 ******************
# 下载python包
download_software https://www.python.org/ftp/python/$PYTHON_VERSION/Python-$PYTHON_VERSION.tgz
PYTHON_SHELL_WROK_TEMP_PATH=`pwd`
# 解析选项
parse_options CONFIGURE_OPTIONS $ADD_OPTIONS
# 安装依赖
info_msg "安装相关已知依赖"
if ! if_command 'gcc';then
    packge_manager_run install -GCC_C_PACKGE_NAMES
fi

if ! if_lib 'openssl'; then
    packge_manager_run install -OPENSSL_DEVEL_PACKGE_NAMES
fi

if if_lib 'zlib' '>=' '1.2.8'; then
    info_msg 'zlib ok'
else
    download_software http://zlib.net/zlib-1.2.11.tar.gz
    configure_install --prefix=$INSTALL_BASE_PATH"/zlib/1.2.11"
    cd $PYTHON_SHELL_WROK_TEMP_PATH
fi

packge_manager_run install -BZIP2_DEVEL_PACKGE_NAMES

# 版本在3.7时需要，以下依赖
if if_version "$PYTHON_VERSION" "<" "3.7.5" && if_version "$PYTHON_VERSION" ">=" "3.7.0";then
    packge_manager_run install -LIBFFI_DEVEL_PACKGE_NAMES
fi

# 编译安装
configure_install $CONFIGURE_OPTIONS

# 添加不同版本的连接
if if_version "$PYTHON_VERSION" ">=" "3.0.0";then
    # 添加启动连接
    ln -svf $INSTALL_PATH$PYTHON_VERSION/bin/python3 /usr/local/bin/python3
    PIP_NAME='pip3'
    PYTHON_NAME='python3'
elif if_version "$PYTHON_VERSION" ">=" "2.0.0";then
    # 添加启动连接
    ln -svf $INSTALL_PATH$PYTHON_VERSION/bin/python /usr/local/bin/python
    PIP_NAME='pip'
    PYTHON_NAME='python2'
fi
if [ -n "$PYTHON_NAME" ]; then
    ln -svf $INSTALL_PATH$PYTHON_VERSION/bin/$PYTHON_NAME /usr/local/bin/$PYTHON_NAME
    if [ -e "$INSTALL_PATH$PYTHON_VERSION/bin/$PIP_NAME" ]; then
        if [ ! -e "get-pip.py" ];then
            curl -OLkN --connect-timeout 7200 https://bootstrap.pypa.io/pip/${PYTHON_VERSION%.*}/get-pip.py -o get-pip.py
            if [ "$?" != '0' ];then
                curl -OLkN --connect-timeout 7200 https://bootstrap.pypa.io/get-pip.py -o get-pip.py
            fi
        fi
        if [ -e "get-pip.py" ]; then
            $INSTALL_PATH$PYTHON_VERSION/bin/$PYTHON_NAME get-pip.py
        fi
    fi
fi

info_msg "安装成功：python-$PYTHON_VERSION"

