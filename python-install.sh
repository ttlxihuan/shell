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
# 加载基本处理
source basic.sh
# 获取工作目录
INSTALL_NAME='python'
# 获取版本配置
VERSION_URL="https://www.python.org/downloads/source/"
VERSION_MATCH='Python-\d+\.\d+\.\d+\.tgz'
VERSION_RULE='\d+\.\d+\.\d+'
# 安装最小版本
PYTHON_VERSION_MIN='2.6.0'
# 初始化安装
init_install PYTHON_VERSION "$1"
# ************** 相关配置 ******************
# 编译初始选项（这里的指定必需有编译项）
CONFIGURE_OPTIONS="--prefix=$INSTALL_PATH$PYTHON_VERSION"
# 编译增加项（这里的配置会随着编译版本自动生成编译项）
ADD_OPTIONS='ssl'
# ************** 编译安装 ******************
# 下载python包
download_software https://www.python.org/ftp/python/$PYTHON_VERSION/Python-$PYTHON_VERSION.tgz
PYTHON_CURRENT_PATH=`pwd`
# 安装依赖
echo "install dependence"
if ! if_command 'gcc';then
    packge_manager_run install -GCC_C_PACKGE_NAMES
fi

if ! if_lib 'openssl'; then
    packge_manager_run install -OPENSSL_DEVEL_PACKGE_NAMES
fi

if if_lib 'zlib' '>=' '1.2.8'; then
    echo 'zlib ok'
else
    download_software http://zlib.net/zlib-1.2.11.tar.gz
    configure_install --prefix=$INSTALL_PATH"zlib/1.2.11"
    cd $PYTHON_CURRENT_PATH
fi

packge_manager_run install -BZIP2_DEVEL_PACKGE_NAMES

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
            curl -OLkN --connect-timeout 7200 https://bootstrap.pypa.io/get-pip.py -o get-pip.py
        fi
        if [ -e "get-pip.py" ]; then
            $INSTALL_PATH$PYTHON_VERSION/bin/$PYTHON_NAME get-pip.py
        fi
    fi
fi

echo "install python-$PYTHON_VERSION success!"

