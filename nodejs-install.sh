#!/bin/bash
#
# nodejs快速编译安装shell脚本
#
# 安装命令
# bash nodejs-install.sh new
# bash nodejs-install.sh $verions_num
# 
# 查看最新版命令
# bash nodejs-install.sh
#
# 可运行系统：
# CentOS 5+
# Ubuntu 15+
#
####################################################################################
##################################### 安装处理 #####################################
####################################################################################
# 加载基本处理
source basic.sh
#域名
NODEJS_HOST='nodejs.org'
# 获取工作目录
INSTALL_NAME='nodejs'
# 获取版本配置
VERSION_URL="https://nodejs.org/zh-cn/download/"
VERSION_MATCH='v\d+\.\d+\.\d+/'
VERSION_RULE='\d+\.\d+\.\d+'
# 安装最小版本
NODEJS_VERSION_MIN='8.0.0'
# 初始化安装
init_install NODEJS_VERSION "$1"
# ************** 相关配置 ******************
# 编译初始选项（这里的指定必需有编译项）
CONFIGURE_OPTIONS="--prefix=$INSTALL_PATH$NODEJS_VERSION"
# 编译增加项（这里的配置会随着编译版本自动生成编译项）
ADD_OPTIONS=''
# ************** 编译安装 ******************
# 下载nodejs包
download_software https://nodejs.org/dist/v$NODEJS_VERSION/node-v$NODEJS_VERSION.tar.gz
# 解析选项
parse_options CONFIGURE_OPTIONS $ADD_OPTIONS
# 安装依赖
echo "install dependence"
# 在编译目录里BUILDING.md文件有说明依赖版本要求，GCC在不同的大版本中有差异
GCC_MIN_VERSION="`cat BUILDING.md|grep -oP '\`gcc\` and \`g\+\+\` (>= )?\d+(\.\d+)+ or newer'|grep -oP '\d+(\.\d+)+'`"
if [ -n "$GCC_MIN_VERSION" ];then
    if echo "$GCC_MIN_VERSION"|grep -qP '^\d+\.\d+$';then
        GCC_MIN_VERSION="$GCC_MIN_VERSION.0"
    fi
    # 获取当前安装的gcc版本
    for ITEM in `which -a gcc`; do
        GCC_CURRENT_VERSION=`$ITEM -v 2>&1|grep -oP '\d+(\.\d+){2}'|tail -n 1`
        if if_version $GCC_MIN_VERSION '<=' $GCC_CURRENT_VERSION;then
            break
        fi
    done
    if ! if_command gcc || if_version $GCC_MIN_VERSION '>' $GCC_CURRENT_VERSION;then
        run_install_shell gcc-install.sh $GCC_MIN_VERSION
        if_error 'install gcc fail'
    fi
    echo "gcc-$GCC_MIN_VERSION ok"
else
    echo 'get gcc min version fail!'
fi
# 安装python3
PYTHON_MIN_VERSION=`cat BUILDING.md|grep -oP 'Python\s+3(\.\d+)+'|grep -oP '\d+(\.\d+)+'|head -n 1`
if [ -z "$PYTHON_MIN_VERSION" ];then
    # 安装python2
    PYTHON_MIN_VERSION=`cat BUILDING.md|grep -oP 'Python\s+2(\.\d+)+'|grep -oP '\d+(\.\d+)+'|head -n 1`
fi
if [ -n "$PYTHON_MIN_VERSION" ];then
    if echo "$PYTHON_MIN_VERSION"|grep -qP '^\d+\.\d+$';then
        PYTHON_MIN_VERSION="$PYTHON_MIN_VERSION.0"
    fi
    if if_version "$PYTHON_MIN_VERSION" ">=" "3.0.0"; then
        PYTHON_NAME="python3"
    elif if_version "$PYTHON_MIN_VERSION" ">=" "2.0.0"; then
        PYTHON_NAME="python2"
    else
        PYTHON_NAME="python"
    fi
    if ! if_command $PYTHON_NAME || if_version $PYTHON_MIN_VERSION '>' "`eval "$PYTHON_NAME -V 2>&1 | grep -oP '\d+(\.\d+)+'"`";then
        run_install_shell python-install.sh $PYTHON_MIN_VERSION
        if_error 'install $PYTHON_NAME fail'
    fi
    echo "python-$PYTHON_MIN_VERSION ok"
else
    echo 'get python min version fail!'
fi

# 编译安装
configure_install $CONFIGURE_OPTIONS

echo "install nodejs-$NODEJS_VERSION success!";
