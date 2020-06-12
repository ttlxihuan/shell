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
PYTHON_VERSION_MIN='2.0.0'
# 初始化安装
init_install PYTHON_VERSION "$1"
# ************** 相关配置 ******************
# 编译初始选项（这里的指定必需有编译项）
CONFIGURE_OPTIONS="--prefix=$INSTALL_PATH$PYTHON_VERSION"
# ************** 编译安装 ******************
# 下载python包
download_software https://www.python.org/ftp/python/$PYTHON_VERSION/Python-$PYTHON_VERSION.tgz
# 安装依赖
echo "install dependence"
if ! if_command 'gcc';then
    packge_manager_run install -GCC_C_PACKGE_NAMES
fi
packge_manager_run install -BZIP2_DEVEL_PACKGE_NAMES
# 编译安装
configure_install $CONFIGURE_OPTIONS

# 添加启动连接
ln -svf $INSTALL_PATH$PYTHON_VERSION/bin/python /usr/local/bin/python

# 添加不同版本的连接
if if_version "$PYTHON_VERSION" ">=" "3.0.0";then
    PYTHON_NAME='python3'
elif if_version "$PYTHON_VERSION" ">=" "2.0.0";then
    PYTHON_NAME='python2'
else
    PYTHON_NAME=''
fi
if [ -n "$PYTHON_NAME" ];then
    ln -svf $INSTALL_PATH$PYTHON_VERSION/bin/python /usr/local/bin/$PYTHON_NAME
fi

echo "install python-$PYTHON_VERSION success!"

