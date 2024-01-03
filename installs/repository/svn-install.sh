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
# Ubuntu 16.04+
#
# 常见错误：
#   1、svnserve: error while loading shared libraries: __vdso_time: invalid mode for dlopen(): Invalid argument
#       此错误一般是系统的glibc有变动（安装有多版本或更新降版系统自带版本）造成的，glibc是系统内核基本动态库，几乎所有程序均需要调整此库
#       如果修更新glibc版本导致系统不兼容会导致系统无法正常使用，一般不建议变更glibc版本
#       恢复原来版本可通过包管理器进行重新安装，然后清除其它版本动态库
#       通过命令 find / -name libc.so.6 排查是否有多个动态里链接到不同 libc-*.*.so （注意：* 是版本号数字），
#       有就统一调整为一个版本并删除多余的 libc.so.6 库链接文件和库文件（如果不删除编译时可能会重新自动链接到其它版本glibc库中），并且在安装多个版本glibc后再安装的软件有可能异常（异常就需要重新安装）
#       再重新编译安装svn
#   2、svn: E200030: SQLite compiled for 3.36.0, but running with 3.6.20
#       目录需要把安装目录里的 libsqlite3.so.0.8.6 复制到 /usr/lib64 目录才能编译完成并正常使用svn
#   3、configure: error: Subversion requires SQLite
#       此错误一般是sqlite版本不对，系统中存在多个版本，需要指定安装目录
# 下载地址
# https://tortoisesvn.net/downloads.html
#
####################################################################################
##################################### 安装处理 #####################################
####################################################################################
# 定义安装参数
DEFINE_RUN_PARAMS="
[-d, --work-dir='/var/svn', {required}]svn服务工作目录
"
# 定义安装类型
DEFINE_INSTALL_TYPE='configure'
# 编译默认项（这里的配置会随着编译版本自动生成编译项）
DEFAULT_OPTIONS='?utf8proc=internal ?lz4=internal'
# 加载基本处理
source "$(cd "$(dirname "${BASH_SOURCE[0]}")"; pwd)"/../../includes/install.sh || exit
# 初始化安装
init_install '1.0.0' "https://downloads.apache.org/subversion/" 'subversion-\d+\.\d+\.\d+\.tar\.gz'
#  限制空间大小（G）：编译目录、安装目录、内存
install_storage_require 1 1 4
# ************** 相关配置 ******************
# 编译初始选项（这里的指定必需有编译项）
CONFIGURE_OPTIONS="--prefix=$INSTALL_PATH$SVN_VERSION "
# ************** 编译安装 ******************
# 下载svn包
download_software https://archive.apache.org/dist/subversion/subversion-$SVN_VERSION.tar.gz
# 解析选项
parse_options CONFIGURE_OPTIONS $DEFAULT_OPTIONS $ARGV_options
# 额外动态需要增加的选项
EXTRA_OPTIONS=()
# 暂存编译目录
SVN_CONFIGURE_PATH=`pwd`
# 安装依赖
info_msg "安装相关已知依赖"

# 安装验证 openssl
install_openssl

# 安装验证 zlib
install_zlib

# sqlite 处理
SQLITE_MINIMUM_VER=`grep -oP 'SQLITE_MINIMUM_VER="\d+(\.\d+)+"' ./configure|grep -oP '\d+(\.\d+)+'`
# 安装验证 sqlite
install_sqlite "$SQLITE_MINIMUM_VER"
# sqlite3 多版本处理
if [ -n "$SQLITE_MINIMUM_VER" ] && if_many_version sqlite3 --version;then
    if [ -n "$INSTALL_sqlite3_PATH" ];then
        EXTRA_OPTIONS[${#EXTRA_OPTIONS[@]}]="?sqlite=$(dirname ${INSTALL_sqlite3_PATH%/*})"
    fi
fi
# 安装apr和apr-util
if [ -e 'INSTALL' ];then
    # 获取最低版本
    MIN_APR_DEVEL_VERSION=$(grep -oP 'Apache Portable Runtime \d+(\.\d+)+ or newer' INSTALL|grep -oP '\d+(\.\d+)+')
    if [ -n "$MIN_APR_DEVEL_VERSION" ];then
        until echo "$MIN_APR_DEVEL_VERSION"|grep -qP '\d+(\.\d+){2,}';do
            MIN_APR_DEVEL_VERSION="$MIN_APR_DEVEL_VERSION.0"
        done
    fi
fi
install_apr "$MIN_APR_DEVEL_VERSION"
install_apr_util "$MIN_APR_DEVEL_VERSION"
# 必需以pkg-config所有目录为准，否则编译容易失败
# apr 多版本处理
if if_many_version "apr-1-config" --version && [ -n "$INSTALL_apr_1_config_PATH" ];then
    EXTRA_OPTIONS[${#EXTRA_OPTIONS[@]}]="?apr=$INSTALL_apr_1_config_PATH"
fi
# apr-util 多版本处理
if if_many_version "apu-1-config" --version && [ -n "$INSTALL_apu_1_config_PATH" ];then
    EXTRA_OPTIONS[${#EXTRA_OPTIONS[@]}]="?apr-util=$INSTALL_apu_1_config_PATH"
fi

cd $SVN_CONFIGURE_PATH
# 解析额外选项
parse_options CONFIGURE_OPTIONS ${EXTRA_OPTIONS[@]}
# 编译安装
configure_install $CONFIGURE_OPTIONS

cd $INSTALL_PATH$SVN_VERSION

# 创建用户
add_user svnserve

# 添加执行文件连接
add_local_run $INSTALL_PATH$SVN_VERSION/bin/ 'svn' 'svnserve' 'svnadmin'

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
SERVICES_CONFIG[$SERVICES_CONFIG_START_RUN]="./bin/svnserve -d -r $ARGV_work_dir --pid-file ./run/svnserve.pid"
SERVICES_CONFIG[$SERVICES_CONFIG_USER]="svnserve"
SERVICES_CONFIG[$SERVICES_CONFIG_PID_FILE]="./run/svnserve.pid"
# 服务并启动服务
add_service SERVICES_CONFIG

info_msg "安装成功：svn-$SVN_VERSION"
