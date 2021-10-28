#!/bin/bash
#
# apache快速编译安装shell脚本
#
# 安装命令
# bash apache-install.sh new
# bash apache-install.sh $verions_num
# 
#  命令参数说明
#  $1 指定安装版本，如果不传则获取最新版本号，为 new 时安装最新版本
#
# 查看最新版命令
# bash apache-install.sh
#
# 可运行系统：
# CentOS 5+
# Ubuntu 15+
#
# 注意：2.2.3以前的低版本，是捆绑的apr、apr-util所以不建议另外安装，如果有可以先删除，否则容易编译报错。
#
# 下载地址
# http://archive.apache.org/dist/httpd/
#
####################################################################################
##################################### 安装处理 #####################################
####################################################################################
# 定义安装类型
DEFINE_INSTALL_TYPE='configure'
# 加载基本处理
source basic.sh
# 初始化安装
init_install '2.0.50' "http://archive.apache.org/dist/httpd/" '(apache|httpd)-\d+\.\d+\.\d+\.tar\.gz'
# ************** 相关配置 ******************
# 编译初始选项（这里的指定必需有编译项）
CONFIGURE_OPTIONS="--prefix=$INSTALL_PATH$APACHE_VERSION "
# 编译增加项（这里的配置会随着编译版本自动生成编译项）
ADD_OPTIONS='rewrite ?cgi ?asis ssl ?proxy-scgi proxy proxy-http so ?threads '"?--datadir=$INSTALL_PATH$APACHE_VERSION "$ARGV_options
# ************** 编译安装 ******************
# 下载apache包
download_software http://archive.apache.org/dist/httpd/httpd-$APACHE_VERSION.tar.gz
# 解析选项
parse_options CONFIGURE_OPTIONS $ADD_OPTIONS
# 安装依赖
echo "安装相关已知依赖"
APACHE_CURRENT_PATH=`pwd`
# 开启ssl
if in_options ssl $CONFIGURE_OPTIONS;then
    # 安装openssl-dev
    # apache2.x不兼容openssl1.0.x及以上的版本
    # 注意openssl-0.9.8版本从 a~f 等一些版本在部分服务器中MD5编译不通过需要增加no-asm选项
    # no-asm： 是在交叉编译过程中不使用汇编代码代码加速编译过程，原因是它的汇编代码是对arm格式不支持的。
    # packge_manager_run install -OPENSSL_DEVEL_PACKGE_NAMES
    if if_version "$APACHE_VERSION" "<" "2.3.0";then
        OPENSSL_VERSION='0.9.7c'
    else
        OPENSSL_VERSION='0.9.8c'
    fi
    if if_lib "openssl" ">=" $OPENSSL_VERSION;then
        echo 'openssl ok'
    else
        OPENSSL_VERSION='1.1.1'
        download_software https://www.openssl.org/source/openssl-$OPENSSL_VERSION.tar.gz openssl-$OPENSSL_VERSION
        OPENSSL_PATH=`pwd`
        # # 添加编译文件连接
        # if [ ! -e './configure' ];then
        #     cp ./config ./configure
        #     if_error '创建编译文件失败'
        # fi
        # # 编译安装
        # configure_install no-asm -fPIC --prefix=$OPENSSL_PATH
        cd $APACHE_CURRENT_PATH
        parse_options CONFIGURE_OPTIONS "?--with-ssl=$OPENSSL_PATH ?--with-openssl=$OPENSSL_PATH"
    fi
fi
if if_lib 'libpcre';then
    echo 'pcre ok'
else
    packge_manager_run install -PCRE_DEVEL_PACKGE_NAMES
fi
# 获取最小版本，注意apr与apr-util是配套的，对应的大版本号必需一样，否则编译容易失败
# 部分版本编译时要求apr版本较低如果按指定的大版本去配置会出现编译失败，比如apache-2.3.x开始需要更高的apr
APR_MIN_VERSION=`grep -oiP 'APR version \d+\.\d+\.\d+' ./configure|sort -Vrb|head -n 1|grep -oP '\d+\.\d+\.\d+'`
if if_version "$APACHE_VERSION" ">" "2.3.0" && if_version "$APR_MIN_VERSION" "<" "1.4.0";then
    APR_MIN_VERSION='1.4.0'
fi
if [ -n "$APR_MIN_VERSION" ];then
    # 下载apr
    VERSION_MATCH=`echo $APR_MIN_VERSION'.\d+.\d+.\d+'|awk -F '.' '{print $1,$2,$NF}' OFS='\\\.'`
    if [ ! -d "$APACHE_CURRENT_PATH/srclib/apr" ];then
        # 获取最新版
        get_version APR_VERSION https://archive.apache.org/dist/apr/ "apr-$VERSION_MATCH\.tar\.gz"
        echo "下载：apr-$APR_VERSION"
        # 下载
        download_software https://archive.apache.org/dist/apr/apr-$APR_VERSION.tar.gz
        # 复制到编译目录
        mv `pwd` $APACHE_CURRENT_PATH/srclib/apr
    fi
    # 下载apr-util
    if [ ! -d "$APACHE_CURRENT_PATH/srclib/apr-util" ]; then
        # 获取最新版
        get_version APR_UTIL_VERSION https://archive.apache.org/dist/apr/ "apr-util-$VERSION_MATCH\.tar\.gz"
        echo "下载：apr-util-$APR_UTIL_VERSION"
        # 下载
        download_software https://archive.apache.org/dist/apr/apr-util-$APR_UTIL_VERSION.tar.gz
        # 复制到编译目录
        mv `pwd` $APACHE_CURRENT_PATH/srclib/apr-util
    fi
    cd $APACHE_CURRENT_PATH
    if [ -d './srclib/apr' ] || [ -d './srclib/apr-util' ];then
        CONFIGURE_OPTIONS=$CONFIGURE_OPTIONS"--with-included-apr"
    fi
fi
# 编译安装
configure_install $CONFIGURE_OPTIONS
# 启动服务
apachectl -k start
# 添加执行文件连接
ln -svf $INSTALL_PATH$APACHE_VERSION/bin/apachectl /usr/local/bin/httpd
echo "安装成功：apache-$APACHE_VERSION"
