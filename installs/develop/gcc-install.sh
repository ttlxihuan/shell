#!/bin/bash
#
# gcc快速编译安装shell脚本
#
# 安装命令
# bash gcc-install.sh new
# bash gcc-install.sh $verions_num
# 
# 查看最新版命令
# bash gcc-install.sh
#
# 可运行系统：
# CentOS 6.4+
# Ubuntu 15.04+
#
#  官网 https://gcc.gnu.org/
#
# 下载地址 （镜像）
# https://gcc.gnu.org/mirrors.html
#
# 依赖说明
# https://gcc.gnu.org/install/prerequisites.html
#
#
# 注意：如果有的时候编译时提示某个文件不存在，可以尝试重新解压再编译，比如提示config.host文件不存在
#
# 当编译时报类似错： [-Werror=implicit-function-declaration]
#   这种错误是编译警告报错，实际上是某些代码不符合规范默认是不再继续编译，如果需要再继续编译则有两个办法：
#       1、（需要手动在原来基础上make，不可make clean）找到编译报错的目录（即第一个make报错行退出的目录（一般是编译目录中的子目录） make: Leaving directory，进入目录打开Makefile文件，搜索到编译选项 -Werror=implicit-function-declaration 去掉并保存，重新编译
#       2、（不可用）增加编译环境变量CFLAGS或CXXFLAGS指定为-Wno-error，强制跳过-Werror选项报错，重新编译。CFLAGS是C编译，CXXFLAGS是C++编译，如果不清楚两个都指定
#          使用命令 export CFLAGS="-Wno-error" 或 export CXXFLAGS="-Wno-error"
#   其它警告可查看：https://blog.csdn.net/li_wen01/article/details/71171413
#
#  编译错误： error: static declaration of ‘secure_getenv’ follows non-static declaration secure_getenv (const char *name)
#       secure_getenv 是在glibc-2.17版起增加，如果系统存在多个glibc版本并且有低于和高于glibc-2.17时编译容易报错，需要彻底清除不需要的glibc版本，文档：http://www.tin.org/bin/man.cgi?section=3&topic=secure_getenv
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
# 镜像地址，如果地址不可用可去 https://gcc.gnu.org/mirrors.html 找合适的地址
MIRRORS_URL="https://bigsearcher.com/mirrors/gcc/"
# 安装curl
install_curl
# 判断默认镜像是否好用
if [ -z "`curl --connect-timeout 20 -I -X HEAD $MIRRORS_URL/releases/ 2>&1| grep '200 OK'`" ];then
    # 获取最快的镜像地址
    MIRRORS_URLS=`curl -k https://gcc.gnu.org/mirrors.html 2>&1 | grep -P 'http(s)?://([\w\-]+\.)+\w+/(\w+/)?gcc/' -o| uniq`
    MIRRORS_URL=''
    MIRRORS_HOST_PING_TIME=''
    for LINE in `echo -e $MIRRORS_URLS`
    do
        MIRRORS_HOST=`echo $LINE|grep -P 'http(s)?://([\w\-]+\.)+\w+/' -o|grep -P '([\w\-]+\.)+\w+' -o`
        PING_TIME=`ping -c 1 -W 10 $MIRRORS_HOST|grep -P 'time=\d+' -o|grep -P '\d+' -o`
        if [ -n "$PING_TIME" ] && [ -n "`curl --connect-timeout 20 -I -X HEAD $LINE/releases/ 2>&1| grep '200 OK'`" ];then
            if [ "$PING_TIME" -lt 150 ];then
                MIRRORS_URL=$LINE
                break
            fi
            MIRRORS_HOST_PING_TIME="$MIRRORS_HOST_PING_TIME$PING_TIME,$LINE\n"
        fi
    done
    if [ -z "$MIRRORS_URL" ];then
        MIRRORS_URL=`echo -e "$MIRRORS_HOST_PING_TIME"|grep -P '^\d+'|sort -n -t ',' -k 1|head -n 1|grep -P 'http.*$' -o`
    fi
    if [ -z "$MIRRORS_URL" ];then
        warn_msg '没有找到更快镜像下载地址'
        MIRRORS_URL="https://bigsearcher.com/mirrors/gcc/"
    fi
fi
# 初始化安装
init_install '4.0.0' "$MIRRORS_URL/releases/" 'gcc-\d+\.\d+\.\d+'
#  限制空间大小（G）：编译目录、安装目录、内存
install_storage_require 4 3 4
# ************** 编译项配置 ******************
# 编译初始选项（这里的指定必需有编译项）
CONFIGURE_OPTIONS="--prefix=$INSTALL_PATH$GCC_VERSION "
# ************** 编译安装 ******************
# 下载GCC包
download_software $MIRRORS_URL/releases/gcc-$GCC_VERSION/gcc-$GCC_VERSION.tar.gz
# 解析选项
parse_options CONFIGURE_OPTIONS $DEFAULT_OPTIONS $ARGV_options
# 暂存编译目录
GCC_CONFIGURE_PATH=`pwd`
# 安装依赖
info_msg "安装相关已知依赖"
if ! if_command g++;then
    package_manager_run install -GCC_C_PACKAGE_NAMES
fi

# 安装验证 bzip2
install_bzip2

# 安装验证 m4
install_m4

# 部分版需要下载配置文件
if [ ! -e "./configure" ] && [ -e "./contrib/download_prerequisites" ];then
    ./contrib/download_prerequisites
    if_error "gcc-$GCC_VERSION 安装失败，找不到依赖配置文件"
else
    # 下载必需依赖
    PACKAGE_LISTS=`cat contrib/download_prerequisites| grep -oP '\w+\-\d+\.\d+(\.\d+)?'`
    # while 循环使用的是管道，会开启子进程，无法修改外部的变量
    for LINE in `echo -e $PACKAGE_LISTS`
    do
        PACKAGE=`echo $LINE|grep -P '^\w+' -o`
        if [ -d "$GCC_CONFIGURE_PATH/$PACKAGE" ];then
            info_msg "$LINE 已经下载了，如果下载是失败文件必需删除后再安装";
            continue;
        fi
        DOWNLOAD_FILENAME=`echo $LINE|sed 's/\./\\\./'`
        PACKAGE_VERSION_FILE=`cat $GCC_CONFIGURE_PATH/contrib/download_prerequisites|grep -oP "$DOWNLOAD_FILENAME(\.\w+)+"|head -n 1`
        if [ -z "$PACKAGE_VERSION_FILE" ];then
            PACKAGE_VERSION_FILE=$LINE`cat $GCC_CONFIGURE_PATH/contrib/download_prerequisites|grep -oiP "$PACKAGE(\.\w+)+"|grep -oP '(\.\w+)+$'|head -n 1`
        fi
        # 下载安装包， 这里有问题，需要把内容复制到gcc的安装根目录下
        download_software $MIRRORS_URL/infrastructure/$PACKAGE_VERSION_FILE
        mv `pwd` $GCC_CONFIGURE_PATH/$PACKAGE
    done
    # 如果不能获取依赖的包，则使用安装包提供的下载脚本
    if [ -z "$PACKAGE_LISTS" ];then
        bash contrib/download_prerequisites
        if_error "gcc-$GCC_VERSION 安装失败，获取不到依赖包"
    fi
fi
# 进入编译目录
cd $GCC_CONFIGURE_PATH
# 64位系统需要禁用multilib
if uname -a|grep -q x86_64; then
    CONFIGURE_OPTIONS=$CONFIGURE_OPTIONS' --disable-multilib'
fi
# 编译安装
configure_install $CONFIGURE_OPTIONS
# 动态库处理
add_so_config $INSTALL_PATH$GCC_VERSION

info_msg "移动文件 lib64/*.py"
# 清除py文件，这些文件会影响共享的动态链接库ldconfig命令执行失败
for PY_FILE in `find $INSTALL_PATH$GCC_VERSION/lib64/ -name "*.py"`
do
    if [ -n "$PY_FILE" ] && [ -e "$PY_FILE" ];then
        run_msg mv $PY_FILE $INSTALL_PATH$GCC_VERSION
    fi
done
ldconfig

package_manager_run remove -GCC_C_PACKAGE_NAMES

# 添加启动连接，下载连接不加容易在其它工具使用时出现 C++ compiler None does not work 类似的错误
add_local_run $INSTALL_PATH$GCC_VERSION/bin/ gcc c++ g++ cpp
ln -svf /usr/local/bin/gcc /usr/bin/cc

info_msg "安装成功：gcc-$GCC_VERSION";
