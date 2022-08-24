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
# CentOS 6.4+
# Ubuntu 15.04+
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
# 编译默认项（这里的配置会随着编译版本自动生成编译项）
DEFAULT_OPTIONS='rewrite ?cgi ?asis ssl ?proxy-scgi proxy proxy-http so ?threads'
# 加载基本处理
source "$(cd "$(dirname "${BASH_SOURCE[0]}")"; pwd)"/../../includes/install.sh || exit
# 初始化安装
init_install '2.0.50' "http://archive.apache.org/dist/httpd/" '(apache|httpd)-\d+\.\d+\.\d+\.tar\.gz'
#  限制空间大小（G）：编译目录、安装目录、内存
install_storage_require 3 1 4
# ************** 相关配置 ******************
# 编译初始选项（这里的指定必需有编译项）
CONFIGURE_OPTIONS="--prefix=$INSTALL_PATH$APACHE_VERSION "
# ************** 编译安装 ******************
# 下载apache包
download_software http://archive.apache.org/dist/httpd/httpd-$APACHE_VERSION.tar.gz
# 解析选项
parse_options CONFIGURE_OPTIONS $DEFAULT_OPTIONS $ARGV_options ?--datadir=$INSTALL_PATH$APACHE_VERSION
# 暂存编译目录
APACHE_CONFIGURE_PATH=`pwd`
# 额外动态需要增加的选项
EXTRA_OPTIONS=()
# 安装依赖
info_msg "安装相关已知依赖"
# 开启ssl
if in_options ssl $CONFIGURE_OPTIONS;then
    # 安装openssl-dev
    # apache2.x不兼容openssl1.0.x及以上的版本
    # 注意openssl-0.9.8版本从 a~f 等一些版本在部分服务器中MD5编译不通过需要增加no-asm选项
    # no-asm： 是在交叉编译过程中不使用汇编代码代码加速编译过程，原因是它的汇编代码是对arm格式不支持的。
    if if_version "$APACHE_VERSION" "<" "2.3.0";then
        OPENSSL_VERSION='0.9.7c'
    else
        OPENSSL_VERSION='0.9.8c'
    fi
    # 安装验证 openssl
    if ! install_openssl "$OPENSSL_VERSION" '' '1.1.1' 1;then
        EXTRA_OPTIONS[${#EXTRA_OPTIONS[@]}]="?ssl=`pwd` ?openssl=`pwd`"
    fi
fi

# 安装验证 libpcre
install_libpcre

# 获取最小版本，注意apr与apr-util是配套的，对应的大版本号必需一样，否则编译容易失败
# 部分版本编译时要求apr版本较低如果按指定的大版本去配置会出现编译失败，比如apache-2.3.x开始需要更高的apr
APR_MIN_VERSION=`grep -oiP 'APR version \d+\.\d+\.\d+' ./configure|sort -Vrb|head -n 1|grep -oP '\d+\.\d+\.\d+'`
if if_version "$APACHE_VERSION" ">" "2.3.0" && if_version "$APR_MIN_VERSION" "<" "1.4.0";then
    APR_MIN_VERSION='1.4.0'
fi
if [ -n "$APR_MIN_VERSION" ];then
    if ! install_apr "$APR_MIN_VERSION" "" "" 1;then
        # 复制到编译目录
        mv `pwd` $APACHE_CONFIGURE_PATH/srclib/apr
    fi
    if ! install_apr_util "$APR_MIN_VERSION" "" "" 1;then
        # 复制到编译目录
        mv `pwd` $APACHE_CONFIGURE_PATH/srclib/apr-util
    fi
    if [ -d "$APACHE_CONFIGURE_PATH/srclib/apr" ] || [ -d "$APACHE_CONFIGURE_PATH/srclib/apr-util" ];then
        EXTRA_OPTIONS[${#EXTRA_OPTIONS[@]}]="?included-apr"
    else
        # apr 多版本处理
        if if_many_version "apr-1-config" --version && [ -n "$INSTALL_apr_1_config_PATH" ];then
            EXTRA_OPTIONS[${#EXTRA_OPTIONS[@]}]="?apr=$INSTALL_apr_1_config_PATH"
        fi
        # apr-util 多版本处理
        if if_many_version "apu-1-config" --version && [ -n "$INSTALL_apu_1_config_PATH" ];then
            EXTRA_OPTIONS[${#EXTRA_OPTIONS[@]}]="?apr-util=$INSTALL_apu_1_config_PATH"
        fi
    fi
fi

cd $APACHE_CONFIGURE_PATH
# 解析额外选项
parse_options CONFIGURE_OPTIONS ${EXTRA_OPTIONS[@]}
# 编译安装
configure_install $CONFIGURE_OPTIONS

cd $INSTALL_PATH$APACHE_VERSION
info_msg '修改apache基本配置'
# 这里没有配置处理，需要了解下
# 开启rewrite
sed -i -r 's,^\s*#\s*(LoadModule\s+rewrite_module\s+modules/mod_rewrite\.so),\1,' conf/httpd.conf
# 开启代理
sed -i -r 's,^\s*#\s*(LoadModule\s+proxy_module\s+modules/mod_proxy\.so),\1,' conf/httpd.conf
sed -i -r 's,^\s*#\s*(LoadModule\s+proxy_fcgi_module\s+modules/mod_proxy_fcgi\.so),\1,' conf/httpd.conf
sed -i -r 's,^\s*#\s*(LoadModule\s+proxy_http_module\s+modules/mod_proxy_http\.so),\1,' conf/httpd.conf
# 开启vhost
sed -i -r 's,^\s*#\s*(LoadModule\s+vhost_alias_module\s+modules/mod_vhost_alias\.so),\1,' conf/httpd.conf
sed -i -r 's,^\s*#\s*(Include\s+conf/extra/httpd-vhosts\.conf),\1,' conf/httpd.conf
sed -i -r 's,^([^#].+),#\1,g' conf/extra/httpd-vhosts.conf
# 配置默认域名
sed -i -r 's,^\s*#\s*\s*(ServerName\s+).*$,\1 localhost:80,' conf/httpd.conf

# 添加服务配置
SERVICES_CONFIG=()
SERVICES_CONFIG[$SERVICES_CONFIG_START_RUN]="./bin/apachectl -k start"
SERVICES_CONFIG[$SERVICES_CONFIG_RESTART_RUN]="./bin/apachectl -k restart"
SERVICES_CONFIG[$SERVICES_CONFIG_STOP_RUN]="./bin/apachectl -k stop"
SERVICES_CONFIG[$SERVICES_CONFIG_PID_FILE]="./logs/httpd.pid"
# 服务并启动服务
add_service SERVICES_CONFIG

# 添加执行文件连接
ln -svf $INSTALL_PATH$APACHE_VERSION/bin/apachectl /usr/local/bin/httpd
info_msg "安装成功：apache-$APACHE_VERSION"
