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
# CentOS 6.4+
# Ubuntu 15.04+
#
# 下载地址
# https://tortoisesvn.net/downloads.html
#
####################################################################################
##################################### 安装处理 #####################################
####################################################################################
# 定义安装参数
DEFINE_INSTALL_PARAMS="
[-d, --work-dir='/var/svn']svn服务工作目录
"
# 定义安装类型
DEFINE_INSTALL_TYPE='configure'
# 加载基本处理
source "$(cd "$(dirname "${BASH_SOURCE[0]}")"; pwd)"/../../includes/install.sh || exit
# 初始化安装
init_install '1.0.0' "https://downloads.apache.org/subversion/" 'subversion-\d+\.\d+\.\d+\.tar\.gz'
#  限制空间大小（G）：编译目录、安装目录、内存
install_storage_require 1 1 4
# ************** 相关配置 ******************
# 编译初始选项（这里的指定必需有编译项）
CONFIGURE_OPTIONS="--prefix=$INSTALL_PATH$SVN_VERSION "
# 编译增加项（这里的配置会随着编译版本自动生成编译项）
ADD_OPTIONS='?utf8proc=internal ?lz4=internal '$ARGV_options
# ************** 编译安装 ******************
# 下载svn包
download_software https://archive.apache.org/dist/subversion/subversion-$SVN_VERSION.tar.gz
# 解析选项
parse_options CONFIGURE_OPTIONS $ADD_OPTIONS
# 暂存编译目录
SVN_CONFIGURE_PATH=`pwd`
# 安装依赖
info_msg "安装相关已知依赖"
# 安装openssl
if if_lib "openssl";then
    info_msg 'openssl ok'
else
    packge_manager_run install -OPENSSL_DEVEL_PACKGE_NAMES
fi
# 安装zlib
if if_lib 'libzip';then
    info_msg 'libzip ok'
else
    packge_manager_run install -ZLIB_DEVEL_PACKGE_NAMES
fi
# sqlite 处理，多个版本时容易出问题，svn: E200030: SQLite compiled for 3.36.0, but running with 3.6.20
# 目录需要把安装目录里的 libsqlite3.so.0.8.6 复制到 /usr/lib64 目录才能编译完成并正常使用svn
SQLITE_MINIMUM_VER=`grep -oP 'SQLITE_MINIMUM_VER="\d+(\.\d+)+"' ./configure|grep -oP '\d+(\.\d+)+'`
if [ -z "$SQLITE_MINIMUM_VER" ] || if_version "$SQLITE_MINIMUM_VER" "<" "3.0.0";then
    packge_manager_run install -SQLITE_DEVEL_PACKGE_NAMES
elif ! if_command sqlite3 || if_version "$SQLITE_MINIMUM_VER" ">" "`sqlite3 --version`";then
    # 获取最新版
    get_version SPLITE3_PATH https://www.sqlite.org/download.html '(\w+/)+sqlite-autoconf-\d+\.tar\.gz' '.*'
    SPLITE3_VERSION=`echo $SPLITE3_PATH|grep -oP '\d+\.tar\.gz$'|grep -oP '\d+'`
    info_msg "安装：sqlite3-$SPLITE3_VERSION"
    # 下载
    download_software https://www.sqlite.org/$SPLITE3_PATH
    # 编译安装
    configure_install --prefix=/usr/local --enable-shared
else
    info_msg 'sqlite ok'
fi
# sqlite3 多版本处理
if [ -n "$SQLITE_MINIMUM_VER" ] && if_version "$SQLITE_MINIMUM_VER" ">=" "3.0.0" && if_many_version sqlite3 --version;then
    get_lib_install_path sqlite3 SQLITE_PKG_PATH
    if [ -n "$SQLITE_PKG_PATH" ];then
        CONFIGURE_OPTIONS="$CONFIGURE_OPTIONS --with-sqlite=\"$SQLITE_PKG_PATH\""
    fi
fi
# 安装apr和apr-util
APR_DIFF='-1'
if [ -e 'INSTALL' ];then
    # 获取最低版本
    MIN_APR_DEVEL_VERSION=$(grep -oP 'Apache Portable Runtime \d+(\.\d+)+ or newer' INSTALL|grep -oP '\d+(\.\d+)+')
    if [ -n "$MIN_APR_DEVEL_VERSION" ];then
        until echo "$MIN_APR_DEVEL_VERSION"|grep -qP '\d+(\.\d+){2,}';do
            MIN_APR_DEVEL_VERSION="$MIN_APR_DEVEL_VERSION.0"
        done
        for ITEM_APR in : -util:_UTIL;do
            if ! if_lib "apr${ITEM_APR%:*}$APR_DIFF" '>=' $MIN_APR_DEVEL_VERSION;then
                packge_manager_run install -APR${ITEM_APR#*:}_DEVEL_PACKGE_NAMES
            fi
            if if_lib "apr${ITEM_APR%:*}$APR_DIFF" '>=' $MIN_APR_DEVEL_VERSION;then
                info_msg "apr${ITEM_APR%:*} ok"
            else
                # 安装指定版本的apr和apr-util
                VERSION_MATCH=`echo $MIN_APR_DEVEL_VERSION'.\d+.\d+.\d+'|awk -F '.' '{print $1,$2,$NF}' OFS='\\\.'`
                # 获取相近高版本
                get_version APR_VERSION https://archive.apache.org/dist/apr/ "apr-$VERSION_MATCH\.tar\.gz"
                info_msg "下载：apr-$APR_VERSION"
                # 下载
                download_software https://archive.apache.org/dist/apr/apr-$APR_VERSION.tar.gz
                # 安装
                configure_install --prefix="$INSTALL_BASE_PATH/apr/$APR_VERSION"
                # 增加选项
                CONFIGURE_OPTIONS="$CONFIGURE_OPTIONS --with-apr=\"$(pwd)\""
                # 获取相近高版本
                get_version APR_UTIL_VERSION https://archive.apache.org/dist/apr/ "apr-util-$VERSION_MATCH\.tar\.gz"
                info_msg "下载：apr-util-$APR_UTIL_VERSION"
                # 下载
                download_software https://archive.apache.org/dist/apr/apr-util-$APR_UTIL_VERSION.tar.gz
                # 安装
                configure_install --prefix="$INSTALL_BASE_PATH/apr-util/$APR_UTIL_VERSION" --with-apr="$INSTALL_BASE_PATH/apr/$APR_VERSION"
                break
            fi
        done
    fi
else
    # 安装apr-util
    if if_lib 'apr-util'$APR_DIFF;then
        info_msg 'apr-util ok'
    else
        packge_manager_run install -APR_UTIL_DEVEL_PACKGE_NAMES
    fi
    if if_lib 'apr'$APR_DIFF;then
        info_msg 'apr ok'
    else
        packge_manager_run install -APR_DEVEL_PACKGE_NAMES
    fi
fi
# apr 多版本处理
if if_many_version apr$APR_DIFF-config --version;then
    for APR_PATH in $(which -a apr$APR_DIFF-config); do
        if [ -z "$MIN_APR_DEVEL_VERSION" ] || if_version $($APR_PATH --version|grep -oP '\d+(\.\d+){2}'|head -1) '>=' $MIN_APR_DEVEL_VERSION;then
            CONFIGURE_OPTIONS="$CONFIGURE_OPTIONS --with-apr=\"$APR_PATH\""
            break
        fi
    done
fi
# apr-util 多版本处理
if if_many_version apr$APR_DIFF-config --version;then
    for APR_PATH in $(which -a apu$APR_DIFF-config); do
        if [ -z "$MIN_APR_DEVEL_VERSION" ] || if_version $($APR_PATH --version|grep -oP '\d+(\.\d+){2}'|head -1) '>=' $MIN_APR_DEVEL_VERSION;then
            CONFIGURE_OPTIONS="$CONFIGURE_OPTIONS --with-apr-util=\"$APR_PATH\""
            break
        fi
    done
fi
cd $SVN_CONFIGURE_PATH
# 编译安装
configure_install $CONFIGURE_OPTIONS

cd $INSTALL_PATH$SVN_VERSION

# 创建用户
add_user svnserve

# 基本项配置
if [ -n "$ARGV_work_dir" ];then
    # 创建库存目录
    mkdirs $ARGV_work_dir;
    chown -R svnserve:svnserve $ARGV_work_dir
fi

mkdirs $INSTALL_PATH$SVN_VERSION/run/

chown -R svnserve:svnserve $INSTALL_PATH$SVN_VERSION

# 添加服务配置
SERVICES_CONFIG=()
SERVICES_CONFIG[$SERVICES_CONFIG_START_RUN]="$INSTALL_PATH$SVN_VERSION/bin/svnserve -d -r $ARGV_work_dir --pid-file $INSTALL_PATH$SVN_VERSION/run/svnserve.pid"
SERVICES_CONFIG[$SERVICES_CONFIG_USER]="svnserve"
SERVICES_CONFIG[$SERVICES_CONFIG_PID_FILE]="$INSTALL_PATH$SVN_VERSION/run/svnserve.pid"
# 服务并启动服务
add_service SERVICES_CONFIG

info_msg "安装成功：svn-$SVN_VERSION"
