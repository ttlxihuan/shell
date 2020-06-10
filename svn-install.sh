#!/bin/bash
#
# svn快速编译安装shell脚本
#
# 安装命令
# bash svn-install.sh new [work_path]
# bash svn-install.sh $verions_num [work_path]
# 
#  命令参数说明
#  $1 指定安装版本，如果不传则获取最新版本号，为 new 时安装最新版本
#  $2 指定版本库工作目录，默认是 /var/svn
#
# 查看最新版命令
# bash svn-install.sh
#
# 可运行系统：
# CentOS 5+
# Ubuntu 15+
#
# 下载地址
# https://tortoisesvn.net/downloads.html
#
####################################################################################
##################################### 安装处理 #####################################
####################################################################################
# 加载基本处理
source basic.sh
# 获取工作目录
INSTALL_NAME='svn'
# 获取版本配置
VERSION_URL="https://downloads.apache.org/subversion/"
VERSION_MATCH='subversion-\d+\.\d+\.\d+\.tar\.gz'
VERSION_RULE='\d+\.\d+\.\d+'
# 安装最小版本
SVN_VERSION_MIN='1.0.0'
# 初始化安装
init_install SVN_VERSION "$1"
# 版本服务工作目录
SERVER_WORK_PATH='/var/svn'
# ************** 相关配置 ******************
# 编译初始选项（这里的指定必需有编译项）
CONFIGURE_OPTIONS="--prefix=$INSTALL_PATH$SVN_VERSION "
# 编译增加项（这里的配置会随着编译版本自动生成编译项）
ADD_OPTIONS='?utf8proc=internal ?lz4=internal'
# ************** 编译安装 ******************
if [ -n "$2" ];then
    SERVER_WORK_PATH="$2"
fi
# 下载svn包
download_software https://downloads.apache.org/subversion/subversion-$SVN_VERSION.tar.gz
# 解析选项
parse_options CONFIGURE_OPTIONS $ADD_OPTIONS
# 暂存编译目录
SVN_CONFIGURE_PATH=`pwd`
# 安装依赖
echo "install dependence"
# sqlite 处理
SQLITE_MINIMUM_VER=`grep -oP 'SQLITE_MINIMUM_VER="\d+(\.\d+)+"' ./configure|grep -oP '\d+(\.\d+)+'`
if [ -z "$SQLITE_MINIMUM_VER" ] || if_version "$SQLITE_MINIMUM_VER" "<" "3.0.0";then
    packge_manager_run install -SQLITE_DEVEL_PACKGE_NAMES
elif ! if_command sqlite3 || if_version "$SQLITE_MINIMUM_VER" ">" "`sqlite3 --version`";then
    # 获取最新版
    get_version SPLITE3_PATH https://www.sqlite.org/download.html '(\w+/)+sqlite-autoconf-\d+\.tar\.gz' '.*'
    SPLITE3_VERSION=`echo $SPLITE3_PATH|grep -oP '\d+\.tar\.gz$'|grep -oP '\d+'`
    echo "install sqlite3-$SPLITE3_VERSION"
    # 下载
    download_software https://www.sqlite.org/$SPLITE3_PATH
    # 编译安装
    configure_install --prefix=/usr/local --enable-shared
else
    echo 'sqlite ok'
fi
# 安装openssl
if if_lib "openssl";then
    echo 'openssl ok'
else
    packge_manager_run install -OPENSSL_DEVEL_PACKGE_NAMES
fi
# 安装zlib
if if_lib 'libzip';then
    echo 'libzip ok'
else
    packge_manager_run install -ZLIB_DEVEL_PACKGE_NAMES
fi
# 安装apr-util
if if_lib 'apr-util-1';then
    echo 'apr-util ok'
else
    packge_manager_run install -APR_UTIL_DEVEL_PACKGE_NAMES
fi
# 安装apr
if if_lib 'apr-1';then
    echo 'apr ok'
else
    packge_manager_run install -APR_DEVEL_PACKGE_NAMES
fi
cd $SVN_CONFIGURE_PATH
# 编译安装
configure_install $CONFIGURE_OPTIONS

# 基本项配置
# 创建库存目录
if [ ! -d "$SERVER_WORK_PATH" ];then
    mkdir $SERVER_WORK_PATH;
fi

# 启动服务
svnserve -d -r $SERVER_WORK_PATH

echo "install svn-$SVN_VERSION success!"
