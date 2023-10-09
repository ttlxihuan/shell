#!/bin/bash
# windows系统下php环境安装，安装依赖于git-bash工具下进行
# 安装后会自动进行相关的配置处理，安装需要手动确认操作，安装成功后即可使用
# 安装成功后会在桌面生成一个启动脚本，方便管理
# 安装工具：php、apache、nginx、mysql 四个，允许指定各自安装版本，不指定则安装最新版
#
# php-cgi与php-fpm有所区别，windows下使用php-cgi时有两种模式
#   1、在php.ini配置doc_root绝对路径，所有请求将定位到此根目录下访问，不实用多项目目录配置
#   2、在php.ini配置doc_root相对路径（比如指定为 .），所有请求将来DOCUMENT_ROOT目录进行定位，适用于多项目目录配置
#
# 输出帮助信息
show_help(){
    echo "
windows系统git-bash内PHP环境安装工具，允许多版本并存

命令：
    $(basename "${BASH_SOURCE[0]}") install-path [option ...]

参数：
    install-path        安装目录

选项：
    --all               安装php,apache,nginx,mysql,redis最新版本
    --php[=version]     安装php，不指定版本即安装最新版本
    --apache[=version]  安装php，不指定版本即安装最新版本
    --apache-vc=version 指定apache编译使用的VC版本号
                        当apache不匹配的PHP编译VC版本时可指定
                        指定后如果PHP的VC与apache的VC不相同则只能使用cgi模式
    --nginx[=version]   安装nginx，不指定版本即安装最新版本
    --mysql[=version]   安装mysql，不指定版本即安装最新版本
    --redis[=version]   安装redis，不指定版本即安装最新版本
    --proxy [protocol://]host[:port]
                        使用代理下载
    -h, -?              显示帮助信息

说明：
    脚本直接获取软件官网信息进行下载，保证各包不存在内核加壳或修改
    下载安装速度取决于当前的网络，也可以手动将下载的包放在当前目录下
    安装完成后会进行基本配置修改，保证后面可正常使用，并且在桌面生成管理脚本工具
"
    exit 0
}

# 输出错误信息并终止运行
show_error(){
    echo "[error] $1" >&2
    exit 1
}
# 判断上个命令是否执行错误，错误就终止执行并输出错误说明
if_error(){
    if [ $? != 0 ];then
        show_error "$1"
    fi
}
# 判断指定参数是否为版本号
is_version(){
    if ! [[ $1 =~ ^[0-9]{1,3}(\.[0-9]{1,3}){2}$ ]];then
        show_error "请指定正确版本号：$1"
    fi
}
# 比较版本号大小
if_version(){
    local RESULT VERSIONS=`echo -e "$1\n$3"|sort -Vrb`
    case "$2" in
        "==")
            RESULT=`echo -e "$VERSIONS"|uniq|wc -l|grep 1`
        ;;
        "!=")
            RESULT=`echo -e "$VERSIONS"|uniq|wc -l|grep 2`
        ;;
        ">")
            RESULT=`echo -e "$VERSIONS"|uniq -u|head -n 1|grep "$1"`
        ;;
        ">=")
            RESULT=`echo -e "$VERSIONS"|uniq|head -n 1|grep "$1"`
        ;;
        "<")
            RESULT=`echo -e "$VERSIONS"|uniq -u|tail -n 1|grep "$1"`
        ;;
        "<=")
            RESULT=`echo -e "$VERSIONS"|uniq|tail -n 1|grep "$1"`
        ;;
        *)
            show_error "未知版本判断条件：$2"
        ;;
    esac
    if [ -n "$RESULT" ]; then
        return 0;
    fi
    return 1;
}
# 创建目录
mkdirs(){
    local _PATH
    for _PATH;do
        if [ ! -d "$_PATH" ];then
            mkdir -p "$_PATH"
            if_error "创建目录 $_PATH 失败"
        fi
    done
}
# 必需在windows系统下运行此脚本
if ! uname|grep -qP 'MINGW(64|32)' || ! echo $BASH|grep -q '^/usr/bin/bash$';then
    show_error "windows系统git-bash环境专用脚本"
fi
# 添加环境变量，直接添加到windows系统环境变量配置中
# add_path(){
#     # 判断目录是否存在
#     if [ -z "$1" ] || [ ! -d $1 ];then
#         show_error "不存在目录 $1 ，不可添加到环境目录中"
#     fi
#     local TEMP_PATH ADD_PATH=$(cd $1;pwd -W)
#     while read TEMP_PATH;do
#         if [ "$1" = "$TEMP_PATH" ];then
#             echo "[warn] $1 目录已经配置windows系统环境变量，跳过配置"
#             return
#         fi
#     done <<EOF
# echo "$PATH"|grep -oP '[^:]+'
# EOF
#     cmd <<EOF
# SETX PATH %PATH%;$ADD_PATH
# EOF
# }
for((INDEX=1; INDEX<=$#; INDEX++));do
    PARAM_ITEM=${@:$INDEX:1}
    case "${PARAM_ITEM}" in
        -h|-\?)
            show_help
        ;;
        --all)
            PHP_VERSION=new
            APACHE_VERSION=new
            NGINX_VERSION=new
            MYSQL_VERSION=new
            REDIS_VERSION=new
        ;;
        --php)
            PHP_VERSION=new
        ;;
        --php=*)
            PHP_VERSION=${PARAM_ITEM#*=}
            is_version "$PHP_VERSION"
            if if_version "$PHP_VERSION" '<' '7.0.0';then
                show_error "php最小安装版本：7.0.0"
            fi
        ;;
        --apache)
            APACHE_VERSION=new
        ;;
        --apache=*)
            APACHE_VERSION=${PARAM_ITEM#*=}
            is_version "$APACHE_VERSION"
            if if_version "$APACHE_VERSION" '<' '2.0.50';then
                show_error "apache最小安装版本：2.0.50"
            fi
        ;;
        --apache-vc=*)
            APACHE_VC_VERSION=${PARAM_ITEM#*=}
            if [[ "$APACHE_VC_VERSION" =~ ^[1-9][0-9]$ ]];then
                show_error "apache编译VC版本号错误，必需是两位数字"
            fi
        ;;
        --nginx)
            NGINX_VERSION=new
        ;;
        --nginx=*)
            NGINX_VERSION=${PARAM_ITEM#*=}
            is_version "$NGINX_VERSION"
            if if_version "$NGINX_VERSION" '<' '1.0.0';then
                show_error "nginx最小安装版本：1.0.0"
            fi
        ;;
        --mysql)
            MYSQL_VERSION=new
        ;;
        --mysql=*)
            MYSQL_VERSION=${PARAM_ITEM#*=}
            is_version "$MYSQL_VERSION"
            if if_version "$MYSQL_VERSION" '<' '5.0.0';then
                show_error "mysql最小安装版本：5.0.0"
            fi
        ;;
        --redis)
            REDIS_VERSION=new
        ;;
        --redis=*)
            REDIS_VERSION=${PARAM_ITEM#*=}
            is_version "$REDIS_VERSION"
            if if_version "$REDIS_VERSION" '<' '4.0.0';then
                show_error "redis最小安装版本：4.0.0"
            fi
        ;;
        --proxy=*)
            PROXY_ADDR="--proxy ${PARAM_ITEM#*=}"
        ;;
        *)
            INSTALL_PATH=${PARAM_ITEM}
        ;;
    esac
done
# 没有指定安装目录
if [ -z "$INSTALL_PATH" ];then
    show_error "请指定安装目录"
    exit 0
fi

if ! [[ "$INSTALL_PATH" =~ ^([a-zA-Z0-9]|/|-|_|\.)+$ ]];then
    show_error "安装目录不可包含[a-z0-9/-_.]以外的字符，否则可能导致安装后的服务不可用，请确认安装目录：$INSTALL_PATH"
fi

echo "[info] 安装目录：$INSTALL_PATH"

SCRIPT_PATH="$(cd "$(dirname "${BASH_SOURCE[0]}")"; pwd)/$(basename "${BASH_SOURCE[0]}")"

mkdirs "$INSTALL_PATH/downloads" "$INSTALL_PATH/servers" "$INSTALL_PATH/www"

INSTALL_PATH=$(cd ${INSTALL_PATH};pwd)

# 下载目录
DOWNLOADS_PATH="$INSTALL_PATH/downloads"
# 服务目标
SERVERS_PATH="$INSTALL_PATH/servers"
# 文档目录
DOC_ROOT=$(cd "$INSTALL_PATH/www";pwd|sed -r 's,^/([a-z]+)/,\1:/,')

echo "[info] 如果长时间没有反应建议 Ctrl + C 终止脚本，再运行尝试"

# 运行CURL
run_curl(){
    if ! curl -LkN --max-time 1800 --connect-timeout 1800 $PROXY_ADDR $@ 2>/dev/null;then
        echo '' >&2
        show_error "请确认连接 ${@:$#} 是否能正常访问！"
    fi
}
# 获取最新版本号
get_version(){
    local TEMP_VERSION=$(run_curl "$2"|grep -oP "$3"|sort -Vrb|head -n 1|grep -oP "\d+(\.\d+){2,}")
    if [ -z "$TEMP_VERSION" ];then
        show_error "获取版本号信息失败"
    else
        echo $TEMP_VERSION
    fi
    eval "$1=\$TEMP_VERSION"
}
# 获取系统位数
if uname|grep -qP 'MINGW(64)';then
    OS_BIT=64
    AOS_BIT=64
else
    OS_BIT=86
    AOS_BIT=32
fi

# 获取PHP下载包名信息
if [ -n "$PHP_VERSION" ];then
    # 获取新版本
    if [ "$PHP_VERSION" = 'new' ];then
        echo -n '[info] 获取PHP最新版本号：'
        get_version PHP_VERSION 'https://www.php.net/supported-versions.php' '#v\d+\.\d+\.\d+'
    fi
    # 获取下载包名
    if if_version "$PHP_VERSION" '>=' '8.0.0';then
        VC_VS=vs
    else
        VC_VS=vc
    fi
    PHP_DOWNLOAD_URL='https://windows.php.net/downloads/releases/'
    PHP_FILE=$(run_curl $PHP_DOWNLOAD_URL|grep -oP "php-$PHP_VERSION-Win32-$VC_VS\d+-x$OS_BIT\.zip"|head -n 1)
    if [ -z "$PHP_FILE" ];then
        PHP_DOWNLOAD_URL=${PHP_DOWNLOAD_URL}archives/
        PHP_FILE=$(run_curl $PHP_DOWNLOAD_URL|grep -oP "php-$PHP_VERSION-Win32-$VC_VS\d+-x$OS_BIT\.zip"|head -n 1)
    fi
    if_error "php-$PHP_VERSION 包不存在无法下载"
fi

# 获取apache下载包名信息
if [ -n "$APACHE_VERSION" ];then
    # 提取VC信息
    if [ -n "$APACHE_VC_VERSION" ];then
        VC_VERSION=$APACHE_VC_VERSION
    elif [ -n "$PHP_FILE" ];then
        VC_VERSION=$(echo "$PHP_FILE"|grep -oP 'vs\d+-'|grep -oP '\d+')
        PHP_INSTALL_DIR="$SERVERS_PATH/php-$PHP_VERSION"
    else
        # 在安装目录里找已经安装的php再进行数据匹配
        PHP_INSTALL_DIR=$(find "$SERVERS_PATH" -maxdepth 1 -type d -name 'php-*' 2>/dev/null|sort -r|head -n 1)
        if [ -z "$PHP_INSTALL_DIR" ];then
            show_error "没有安装PHP，请指定VC版本信息"
        fi
        # 自动匹配
        VC_VERSION=$($PHP_INSTALL_DIR/php.exe -i|grep -P 'PHP Extension Build .*V[SC]\d+$'|grep -oP '\d+$')
    fi
    if (( VC_VERSION >= 16 ));then
        VC_NAME=VS$VC_VERSION
    else
        VC_NAME=VC$VC_VERSION
    fi
    # 提取对应的版本
    if [ "$APACHE_VERSION" = 'new' ];then
        echo -n '[info] 获取apache最新版本号：'
        get_version APACHE_VERSION "https://www.apachelounge.com/download/$VC_NAME/" "(apache|httpd)-\d+\.\d+\.\d+-win$AOS_BIT-$VC_NAME\.zip"
    elif [ -z "$APACHE_VC_VERSION" ];then
        run_curl "https://www.apachelounge.com/download/$VC_NAME/"|grep -oP "(apache|httpd)-$APACHE_VERSION-win$AOS_BIT-$VC_NAME\.zip" >/dev/null
        if_error "找不到匹配的apache版本，请指定 --apache-vc 编译的VC版本号"
    fi
fi

# 获取nginx下载包名信息
if [ "$NGINX_VERSION" = 'new' ];then
    echo -n '[info] 获取nginx最新版本号：'
    get_version NGINX_VERSION 'http://nginx.org/en/download.html' 'Stable version.*?nginx-\d+\.\d+\.\d+\.tar\.gz'
fi

# 获取mysql下载包名信息
if [ "$MYSQL_VERSION" = 'new' ];then
    echo -n '[info] 获取mysql最新版本号：'
    get_version MYSQL_VERSION 'https://dev.mysql.com/downloads/mysql/' 'mysql-\d+\.\d+\.\d+'
fi

# 获取redis下载包名信息
if [ "$REDIS_VERSION" = 'new' ];then
    echo -n '[info] 获取redis最新版本号：'
    get_version REDIS_VERSION 'https://github.com/tporadowski/redis/tags' 'v\d+(\.\d+){2,3}'
fi

# 下载安装包
download_file(){
    local FILE_NAME=$(basename "$1")
    cd "$DOWNLOADS_PATH"
    if [ ! -e "$FILE_NAME" ];then
        echo "[info] 下载：$FILE_NAME [下载中...]"
        if (run_curl -O -o "$FILE_NAME" "$1" 2>/dev/null);then
            rm -f "$FILE_NAME"
            run_curl --http1.1 -O -o "$FILE_NAME" "$1"
        fi
        if [ $? != 0 ];then
            rm -f "$FILE_NAME"
            show_error "下载 $FILE_NAME 失败，下载地址：$1"
        fi
    else
        echo "[info] 下载：$FILE_NAME [已下载]"
    fi
    local SAVE_PATH="$SERVERS_PATH/${2}"
    if [ ! -d "$SAVE_PATH" ];then
        echo "[info] 解压：$FILE_NAME [解压中...]"
        unzip "$FILE_NAME" -d "$SAVE_PATH" >/dev/null 2>/dev/null
        if [ $? != 0 ];then
            rm -f "$FILE_NAME"
            show_error "解压 $FILE_NAME 失败，下载地址：$1"
        fi
        cd "$SERVERS_PATH"
        # 目录迁移
        local DEC_PATH
        while [ $(find $2 -maxdepth 1 -type d|grep -P '/.+'|wc -l) = 1 ];do
            DEC_PATH=$(find $2 -maxdepth 1 -type d|grep -P '/.+')
            mv $DEC_PATH ./$2-new
            rm -rf $2
            mv ./$2-new ./$2
        done
    else
        echo "[info] 解压：$FILE_NAME [已解压]"
    fi
}

php_init(){
    [ -d "$SERVERS_PATH/php-$PHP_VERSION" ] || show_error "php-$PHP_VERSION 下载解压失败，安装终止"
    echo "[info] PHP配置处理"
    cd "$SERVERS_PATH/php-$PHP_VERSION"
    if [ ! -e ./php.ini ];then
        cp php.ini-development php.ini
        if_error "php.ini 配置文件丢失，无法进行配置"
    fi
    local EXTENSION_NAME
    # 开启扩展
    for EXTENSION_NAME in bz2 curl gd gettext gmp mbstring openssl pdo pdo_mysql sockets;do
        if [ -e ./ext/php_${EXTENSION_NAME}.dll ];then
            sed -i -r "s/^\s*;\s*(extension=${EXTENSION_NAME})/\1/" php.ini
        fi
    done
    # 开启cgi
    sed -i -r "s/^\s*;\s*(cgi.fix_pathinfo=1)/\1/" php.ini
    # 扩展目录
    sed -i -r 's/^\s*;?\s*(extension_dir\s*=)\s*"ext"\s*/\1 "ext"/' php.ini
    # 访问目录范围限制配置
    # 配置目录访问目录，注意：open_basedir尽量不要配置，否则会影响可访问根目录
    sed -i -r "s,^\s*;?\s*(doc_root\s*=).*,\1," php.ini
    sed -i -r "s,^\s*;?\s*(open_basedir\s*=).*,; \1," php.ini
    sed -i -r "s,^\s*;?\s*(user_dir\s*=).*,\1," php.ini
    ln -svf $SERVERS_PATH/php-$PHP_VERSION/php.exe /usr/bin/php
    # 安装composer
    if which composer;then
        echo "[info] 已安装 composer"
    else
        echo "[info] 下载安装 composer"
        cat > composer-installer.php <<EOF
<?php
copy('https://getcomposer.org/installer', 'composer-setup.php');
require './composer-setup.php';
EOF
        ./php composer-installer.php
        if [ -e ./composer.phar ];then
            ln -svf $SERVERS_PATH/php-$PHP_VERSION/composer.phar /usr/bin/composer
            echo "[info] composer 安装成功";
        else
            echo "[warn] composer 安装失败";
        fi
        rm -f composer-installer.php
    fi
}
apache_init(){
    [ -d "$SERVERS_PATH/httpd-$APACHE_VERSION" ] || show_error "apache-$APACHE_VERSION 下载解压失败，安装终止"
    echo "[info] apache配置处理"
    cd "$SERVERS_PATH/httpd-$APACHE_VERSION"
    # 通用配置开启
    # 开启rewrite模块
    sed -i -r 's/\s*#\s*(LoadModule\s+rewrite_module\s+.*)/\1/' ./conf/httpd.conf
    # 开启access_compat_module模块，否则无法使用Order命令
    sed -i -r 's/\s*#\s*(LoadModule\s+access_compat_module\s+.*)/\1/' ./conf/httpd.conf
    # 开启vhost_alias模块
    sed -i -r 's/\s*#\s*(LoadModule\s+vhost_alias_module\s+.*)/\1/' ./conf/httpd.conf
    # 打开vhosts
    sed -i -r 's,\s*#\s*(Include\s+conf/extra/httpd-vhosts.conf.*),\1,' ./conf/httpd.conf
    # 注释配置
    if [ -e conf/extra/httpd-vhosts.conf ] && ! grep -qP 'ServerName localhost' ./conf/extra/httpd-vhosts.conf;then
        sed -i -r 's/^(\s*[^#]+)/# \1/' ./conf/extra/httpd-vhosts.conf
        cat >> ./conf/extra/httpd-vhosts.conf <<EOF
# 配置访问权限
<Directory "$DOC_ROOT">
    Options FollowSymLinks
    AllowOverride All
    Require all granted
    DirectoryIndex index.html index.php index.htm
</Directory>
EOF
    fi
    # 修改SRVROOT或ServerRoot
    local APACHE_INSTALL_PATH=$(pwd|sed -r 's,^/([a-z]+)/,\1:/,')
    if ! sed -i -r "s,\s*(Define\s+SRVROOT)\s+.*,\1 \"$APACHE_INSTALL_PATH\"," ./conf/httpd.conf;then
        sed -i -r "s,\s*(ServerRoot)\s+.*,\1 \"$APACHE_INSTALL_PATH\"," ./conf/httpd.conf
    fi
    # 配置ServerName，否则启动会有警告
    sed -i -r 's/\s*#\s*(ServerName\s+)[a-zA-Z0-9_\.:]+\s*$/\1 localhost/' ./conf/httpd.conf
    # 配置与PHP连接
    if [ -n "${PHP_INSTALL_DIR}" ] && [ -z "$APACHE_VC_VERSION" -o "$APACHE_VC_VERSION" = "$VC_VERSION" ];then
        # 配置PHP模块，所有目录的反斜线应转换为正斜线
        local APACHE_MODULE_VERSION=${APACHE_VERSION%.*}
        local PHP_MODULE_PATH=$(find "$PHP_INSTALL_DIR" -name "*${APACHE_MODULE_VERSION//./_}.dll")
        if [ $? = 0 ] && ! grep -qP '^LoadModule php_module' ./conf/httpd.conf;then
            local PHP_INSTALL_PATH=$(cd $PHP_INSTALL_DIR;pwd|sed -r 's,^/([a-z]+)/,\1:/,')
            cat >> ./conf/httpd.conf <<EOF

LoadModule php_module "$PHP_INSTALL_PATH/$(basename $PHP_MODULE_PATH)"
<FilesMatch \.php$>
    SetHandler application/x-httpd-php
</FilesMatch>
# 配置 php.ini 的路径
PHPIniDir "$PHP_INSTALL_PATH"

EOF
        fi
    fi
    # 配置cgi模式
    # 开启gcgi代理模块
    sed -i -r 's/\s*#\s*(LoadModule\s+proxy_module\s+.*)/\1/' ./conf/httpd.conf
    sed -i -r 's/\s*#\s*(LoadModule\s+proxy_fcgi_module\s+.*)/\1/' ./conf/httpd.conf
}
nginx_init(){
    [ -d "$SERVERS_PATH/nginx-$NGINX_VERSION" ] || show_error "nginx-$NGINX_VERSION 下载解压失败，安装终止"
    echo "[info] nginx配置处理"
    cd "$SERVERS_PATH/nginx-$NGINX_VERSION/conf"
    if [ ! -d ./vhosts ];then
        mkdir ./vhosts
        LAST_NUM=$(grep -n '^}' nginx.conf|tail -n 1|grep -oP '\d+')
        sed -i "${LAST_NUM}i include vhosts/*.conf;" nginx.conf
        cd ./vhosts
        cat > ssl <<conf
# 此文件为https证书相关配置模板，正常使用时请复制此模板并修改证书地址和监听端口，并修改文件为对应域名名为便识别，比如 www.api.com.ssl
# 注意：ssl连接握手前还不知道具体域名，当有请求时先使用默认的证书再逐个配置，所以过多个不同域名（主域名不同）的证书建议使用不同的IP或服务器分开

listen       443 ssl;
# 常规https配置，此配置不建议开启
# ssl                  on;

# 配置会话缓存，1m大概4000个会话
ssl_session_cache    shared:SSL:1m;
ssl_session_timeout  5m;

# ssl_ciphers  HIGH:!aNULL:!MD5;
# ssl_prefer_server_ciphers  on;
# 强制必需使用https
if (\$scheme = "http") {
    return 301 https://\$host\$request_uri;
}

# 发送HSTS头信息，强制浏览器使用https协议发送数据
add_header Strict-Transport-Security "max-age=63072000; includeSubDomains; preload"
conf
        cat > host.cert <<conf
# 注意修改证书名
# 从1.15.9版本开始且OpenSSL-1.0.2以上证书文件名可以使用变量（使用变量会导致每次请求重新加载证书，会额外增加开销）
ssl_certificate      certs/ssl.pem;
ssl_certificate_key  certs/ssl.key;
conf
        cat > websocket <<conf
# 此文件为共用文件，用于其它 server 块引用
# 代理websocket连接，建议使用复制文件再重命名方便多个 websocket 代理并存
# 引用后需要视需求修改：匹配地址、代理websocket地址
location /websocket {
    # 去掉路径前缀，只保存小括号匹配的路径信息（包括GET参数），不去掉将原路径代理访问
    rewrite ^[^/]+/(.*) /\$1 break;

    # 代理的websocket地址
    proxy_pass http://127.0.0.1:800;
    
    # 以下常规配置
    proxy_http_version 1.1;
    proxy_set_header Upgrade \$http_upgrade;
    proxy_set_header Connection "upgrade";
}
conf
        cat > static <<conf
# 此文件为共用文件，用于其它 server 块引用
# 常规静态配置
location = / {
    index index.html index.htm index.php;
}
#error_page  404              /404.html;

# 去掉响应头服务器标识
server_tokens off;

# 重定向错误页面
# error_page   500 502 503 504  /50x.html;
# 指定错误页面根目录，也可以不指定
# location = /50x.html {
#     root   html;
# }

# 静态可访问后缀
location ~* ^.+\.(jpg|jpeg|png|css|js|gif|html|htm|xls)$ {
    access_log  off;
    expires     30d;
}
conf
        cat > static.conf.default <<conf
# 此文件为静态服务配置模板
# 使用时建议复制文件并去掉文件名后缀 .default
# 开启后视需求修改：域名、ssl、根目录、独立日志
server {
    # 配置端口号
    listen 80;

    # 配置https
    # include vhosts/ssl;
    # 指定使用的证书
    # include vhosts/host.cert;

    # 配置访问域名，多个空格隔开
    server_name  localhost;

    # 配置根目录
    root $DOC_ROOT/localhost/dist;

    # 独立日志文件，方便查看
    access_log logs/\$host-access.log;

    # 引用静态文件基础配置
    include vhosts/static;
}
conf
        cat > php <<conf
# 此文件为共用文件，用于其它 server 块引用
# PHP配置
if (!-e \$request_filename) {
    rewrite  ^/(.*)$ /index.php?s=\$1  last;
    break;
}

# 代理 http://127.0.0.1:80 地址
#location ~ \.php$ {
#    proxy_pass   http://127.0.0.1;
#}

# fastcgi接口监听
# 转到php-fpm上
location ~ \.php\$ {
    fastcgi_pass   127.0.0.1:\$PHP_CGI_PORT;
    fastcgi_index  index.php;
    fastcgi_param  SCRIPT_FILENAME  \$document_root\$fastcgi_script_name;
    include        fastcgi_params;
}
# 使用静态配置
include vhosts/static;
conf
        cat > php.conf.default <<conf
# 此文件为PHP服务配置模板
# 使用时建议复制文件并去掉文件名后缀 .default
# 开启后视需求修改：域名、ssl、根目录、独立日志
server {
    # 配置http端口号
    listen 80;

    # 配置https
    # include vhosts/ssl;
    # 指定使用的证书
    # include vhosts/host.cert;

    # 配置访问域名，多个空格隔开
    server_name localhost;

    # 配置根目录
    root $DOC_ROOT/localhost/public;

    # 独立日志文件，方便查看
    access_log logs/\$host-access.log;

    # 检查请求实体大小，超出返回413状态码，为0则不检查。
    # client_max_body_size 10m;

    # 指定使用PHP版本
    

    # 引用PHP基础配置
    include vhosts/php;
}
conf
        cat > deny.other.conf.default <<conf
# 此文件为拒绝IP直接访问或未知域名配置，很多漏洞就是通过IP扫描，屏蔽直接IP访问减少部分安全事件泄露和扫描次数
# 使用时直接去掉文件名后缀 .default 即可，此配置不影响正常域名访问，仅限制没配置的域名地址不可访问
# 注意：同一监听IP地址和端口号只允许一个服务配置为 default_server
server {
    # 配置http端口号
    listen 80 default_server;

    # 配置https端口号
    listen 443 default_server;

    # 配置无效访问域名
    # 此域名配置会在其它域名匹配不上时使用
    server_name "";

    # 非标准代码444直接关闭连接，即终端无任何正常响应数据
    return 444;
}
conf
    fi
    
}
mysql_init(){
    [ -d "$SERVERS_PATH/mysql-$MYSQL_VERSION" ] || show_error "mysql-$MYSQL_VERSION 下载解压失败，安装终止"
    echo "[info] mysql配置处理"
    cd "$SERVERS_PATH/mysql-$MYSQL_VERSION"
    if [ ! -d ./database/mysql ];then
        echo '[info] 初始化数据库'
        if [ -e "./scripts/mysql_install_db" ];then
            ./scripts/mysql_install_db --basedir=./ --datadir=./database
        else
            ./bin/mysqld --initialize --basedir=./ --datadir=./database
        fi
    fi
    if [ ! -e ./my.ini ];then
        # 版本专用配置
        if if_version "$MYSQL_VERSION" "<" "8.0.26"; then
            # 8.0.26之前
            local LOG_UPDATES='log_slave_updates'
        else
            # 8.0.26起改名
            local LOG_UPDATES='log_replica_updates'
        fi
        cat > ./my.ini <<MY_CONF
# mysql配置文件，更多可查看官方文档
# https://dev.mysql.com/doc/refman/8.0/en/server-system-variables.html

[mysqld]
# 需要开启的增加将前面的注释符号 # 去掉即可
# 此文件是安装脚本自动生成的，并会自动增加一些常规配置

# 数据库保存目录
datadir=database

# socket连接文件
socket=./mysql.sock

# 错误目录路径
log-error=./mysqld.log

# 进程PID保证文件路径
pid-file=./mysqld.pid

# 关闭加载本地文件，加载本地文件可能存在安全隐患，无特殊要求不建议开启
local-infile=0

# 启动用户
# user=mysql

# SQL处理模式配置，不同版本有对应默认模式
# MySQL的SQL模式不同版本会有些变化，以下部分弃用模式未列出。
# 默认均为严格模式，在生产环境建议使用严格模式，兼容模式容易造成数据写入丢失或转换。
# 写数据时注意：数据类型、字符集、值合法性、值范围等
#
# MySQL8.0默认：ONLY_FULL_GROUP_BY,STRICT_TRANS_TABLES,NO_ZERO_IN_DATE,NO_ZERO_DATE,ERROR_FOR_DIVISION_BY_ZERO,NO_ENGINE_SUBSTITUTION。
# MySQL5.7默认：ONLY_FULL_GROUP_BY,STRICT_TRANS_TABLES,NO_ZERO_IN_DATE,NO_ZERO_DATE,ERROR_FOR_DIVISION_BY_ZERO,NO_AUTO_CREATE_USER,NO_ENGINE_SUBSTITUTION。
#
# 组合模式值：
#   ANSI
#       相当于： REAL_AS_FLOAT, PIPES_AS_CONCAT, ANSI_QUOTES, IGNORE_SPACE, ONLY_FULL_GROUP_BY（MySQL5.7.5开始增加）
#
#   TRADITIONAL
#       MySQL8.0相当于：STRICT_TRANS_TABLES, STRICT_ALL_TABLES, NO_ZERO_IN_DATE, NO_ZERO_DATE, ERROR_FOR_DIVISION_BY_ZERO, NO_ENGINE_SUBSTITUTION
#
# 标准模式值：
#   ALLOW_INVALID_DATES
#       不要对日期进行全面检查，仅验证月份和日期是否在范围内（比如月份只有1~12，日期段是每月不尽相同），
#       此模式针对date和datetime类型字段，验证失败会变成：0000-00-00，严格模式产生错误失败写入。
#
#   ANSI_QUOTES
#       将双引号解析为标识符引号，即双引号功能类似反引号。
#
#   ERROR_FOR_DIVISION_BY_ZERO
#       除0报错（一般程序除数为0均异常）。mysql除0操作将等于NULL。此模式已经弃用。
#       如果不指定此选项不会产生警告，指定会产生警告如果还启用严格模式将报错。在SQL中还可以指定IGNORE关键字忽略。
#
#   HIGH_NOT_PRECEDENCE
#       提升not运算优先级，默认not运算优先级不尽相同，指定后not将先于其它运算。
#
#   IGNORE_SPACE
#       允许内置函数名与左括号之间有空格（默认内置函数使用时函数后与左括号不能间隔）。
#       启用后内置函数将被视为保留字。自定义的函数或存储允许有空格且不受此模式影响。
#
#   NO_AUTO_CREATE_USER
#       禁止GRANT创建空密码账号。此模式已经弃用
#
#   NO_AUTO_VALUE_ON_ZERO
#       此模式影响指定auto_increment字段处理。当指定auto_increment字段写入0后，MYSQL通常会在遇到0后生成新序列号，启用后禁止自动生成新序列号。
#
#   NO_BACKSLASH_ESCAPES
#       禁用反斜杠字符作为字符串和标识符中的转义字符，指定后反斜杠将视为普通字符串处理，即没有转义字符。
#
#   NO_DIR_IN_CREATE
#       创建表时，忽略所有INDEX DIRECTORY和DATA DIRECTORY指令。此选项在副本服务器上很有用。
#
#   NO_ENGINE_SUBSTITUTION
#       当使用CREATE TABLE或ALTER TABLE之类的语句时指定禁用或未编译的存储引擎时，自动替换为默认存储引擎。不指定SQL中不可用的存储引擎将报错。
#
#   NO_UNSIGNED_SUBTRACTION
#       无符号字段允许写入有符号数值，当为负数时会转为0并写入。不指定将报错。
#
#   NO_ZERO_DATE
#       允许0000-00-00作为有效日期，从8.0开始弃用
#
#   NO_ZERO_IN_DATE
#       允许日期在年的部分是非零但当月或日部分可为0，比如：2010-00-01或2010-01-00，不会自动转为0000-00-00。从8.0开始弃用
#
#   ONLY_FULL_GROUP_BY
#       禁止
#
#   PAD_CHAR_TO_FULL_LENGTH
#       禁止查询时去掉char类型字段后面空格，char定长字段写入长度未满时后面是会补空格填满。从8.0.13开始弃用
#       默认会自动去掉后面的空格字符，指定此参数后保留后面的空格字符并返回.
#
#   PIPES_AS_CONCAT
#       将||视为字符串连接符（类似使用concat函数）而不是 or 运算符。
#
#   REAL_AS_FLOAT
#       将REAL作为FLOAT别名，不指定则REAL是DOUBLE的别名。
#
#   STRICT_ALL_TABLES
#       为所有存储引擎启用严格的SQL模式。无效的数据值被拒绝执行。
#
#   STRICT_TRANS_TABLES
#       为事务存储引擎启用严格的SQL模式，并在可能的情况下为非事务存储引擎启用
#
#   TIME_TRUNCATE_FRACTIONAL
#       当写入TIME、DATE、TIMESTAMP类型字段时有小数秒且小数位数超过限定位数时使用截断而不是四舍五入。默认不指定时是四舍五入。截断可以理解为字符串截取。从8.0起增加。
#
# 兼容模式
# sql_mode=NO_ZERO_IN_DATE,NO_ZERO_DATE,ERROR_FOR_DIVISION_BY_ZERO,NO_ENGINE_SUBSTITUTION
# 严格模式
sql_mode=ONLY_FULL_GROUP_BY,STRICT_TRANS_TABLES,NO_ZERO_DATE,ERROR_FOR_DIVISION_BY_ZERO

# 配置慢查询
# log-slow-queries=
# long_query_time=1s

#重置密码专用，重置密码后必需注释并重启服务
# 8.0及以上版本修改SQL（先去掉密码然后再重启修改密码）：update mysql.user set authentication_string='' where user='root';
# 8.0以下版本修改SQL：update mysql.user set password=password('root') where user='root';
# skip-grant-tables

# 总最大连接数，过小会报Too many connections
max_connections=16384

# 单个用户最大连接数据，为0不限制，默认为0
# max_user_connections=0

# 配置线程数，线程数过多会在并发时产生过多的线程切换，导致性能不升反降
# 可动态SQL修改
# innodb_thread_concurrency=1

# mysql 缓冲区配置项很多，具体可以SQL：show global variables like '%buffer%';

# 配置缓冲区容量，如果独享服务器可配置到物理内存的80%左右，如果是共享可配置在50%~70%左右。
# 建议超过1G以上，默认是128M，需要配置整数，最大值=2**(CPU位数64或32)-1。可动态SQL修改
# innodb_buffer_pool_size=128M

# 普通索引、范围索引或不使用索引联接缓冲区大小，最大4G-1
# 可以动态配置，默认256KB
# join_buffer_size=128M

# 设置必需排序缓冲区大小，最大4G-1
# 可以动态配置，默认256KB
# sort_buffer_size=2M

# 使用加密连接，复制时源和副本均需要配置
# 证书颁发机构 (CA) 证书文件的路径名，即根证书
# ssl_ca=cacert.pem

# 服务器公钥证书文件的路径名，通信公钥（服务器和客户端）
# ssl_cert=server-cert.pem

# 服务器私钥文件的路径名，通信私钥（仅服务器）
# ssl_key=server-key.pem

# 开启二进制日志
log-bin=mysql-bin-sync

# 配置自动删除几天前历史二进制日志
# 为0即禁止自动删除，此配置早期不建议使用
# expire_logs_days=7

# 配置自动删除几秒前历史二进制日志。默认2592000，即30天前。
# 为0即禁止自动删除，此配置为新增并建议使用
# 二进制日志可用于复制和恢复等操作，但占用空间
binlog_expire_logs_seconds=2592000

# 配置主从唯一ID
# server-id=1

# 日志在每次事务提交时写入并刷新到磁盘
innodb_flush_log_at_trx_commit=1

# 启用事务同步组数，多组同步可以减少同步到磁盘次数来提升性能，但异常时也容易丢失未同步数据
# 最安全的是每组同步一次（每组可以理解为每个事务），为0即关闭
sync_binlog=1

# 二进制格式，已经指定后不建议修改
# ROW       按每行动态记录，复制安全可靠，占用空间大，默认格式
# STATEMENT 按语句记录，复制对不确定性SQL产生复制警告，占用空间小
# MIXED     按行或语句记录，影响语句异常的按行记录否则按语句记录，占用空间适中，且安全可靠
#           混合模式使用临时表在8.0以前会强制不安全使用行记录直到临时表删除
#           innodb支持语句记录事务等级必需是可重读和串行
binlog_format=ROW

# 二进制日志记录模式
# full      记录所有列数据，即使有的列未修改，默认选项
# minimal   只记录要修改的列，可以减少二进制日志体量
# noblob    记录所有列数据，但blod或text之类列未修改不记录，其它列未修改仍记录
binlog_row_image=minimal

# 作为从服务器时的中继日志
# 中继日志是副本复制时创建产生，与二进制日志格式一样。
# 中继日志是当复制I/O线程、刷新日志、文件过大时会创建。创建规则与二进制日志类似。
# 中继文件会在复制完成后自动删除
#relay_log=school-relay-bin

#可以被复制的库。二进制需要同步的数据库名
#binlog-do-db=

#不可以被从服务器复制的库
binlog-ignore-db=mysql

# 多主复制时需要配置自增步进值，防止多主产生同时的自增值
auto_increment_increment=1

# 多主复制时需要配置自增开始值，避开自增值相同
auto_increment_offset=1

# 版本要求mysql5.7+ 设置数据提交延时长度，默认为0无延时
# 有延时会减少提交次数，减少同步队列数（微秒单位）,即集中写二进制日志到磁盘
# 增加延时提交在服务器异常时可能导致数据丢失
#binlog_group_commit_sync_delay=10

# 并行复制，默认为DATABASE（MYSQL5.6兼容值），版本要求MYSQL5.6+
#slave_parallel_type=LOGICAL_CLOCK
# 并行复制线程数
#slave_parallel_workers=$TOTAL_THREAD_NUM

# 启用自动中继日志恢复
relay_log_recovery=ON

# 复制的二进制数据写入到自己的二进制日志中，默认：ON
# 当使用链复制时使用此项，比如：C复制B，而B复制A
# 当需要切换为主数据库时建议关闭，这样就可以保证切换后的二进制日志不会混合
# 组复制时需要开启
# $LOG_UPDATES=OFF

[client]
# 使用加密连接，复制时副本需要配置
# 要使用加密复制时，配置SQL需要增加：MASTER_SSL=1 或 SOURCE_SSL=1
# 例如：CHANGE MASTER TO ... MASTER_SSL=1
# 例如：CHANGE REPLICATION SOURCE TO ... SOURCE_SSL=1
# 证书颁发机构 (CA) 证书文件的路径名，即根证书
# ssl_ca=cacert.pem

# 服务器公钥证书文件的路径名，通信公钥（服务器和客户端）
# ssl_cert=client-cert.pem

# 服务器私钥文件的路径名，通信私钥（仅服务器）
# ssl_key=client-key.pem

# 8.0以上，默认的字符集是utf8mb4，php7.0及以前的连接会报未知字符集错
# character-set-server=utf8
MY_CONF
    fi
}

redis_init(){
    # 修改配置
    [ -d "$SERVERS_PATH/redis-$REDIS_VERSION" ] || show_error "redis-$REDIS_VERSION 下载解压失败，安装终止"
    echo "[info] redis配置处理"
}

echo '[info] 下载各软件包'
if [ -n "$PHP_VERSION" ];then
    # PHP下载
    download_file "$PHP_DOWNLOAD_URL$PHP_FILE" "php-$PHP_VERSION" &
fi
if [ -n "$APACHE_VERSION" ];then
    # apache下载
    download_file https://www.apachelounge.com/download/$VC_NAME/binaries/httpd-$APACHE_VERSION-win$AOS_BIT-$VC_NAME.zip "httpd-$APACHE_VERSION" &
fi
if [ -n "$NGINX_VERSION" ];then
    # nginx下载
    download_file http://nginx.org/download/nginx-$NGINX_VERSION.zip "nginx-$NGINX_VERSION" &
fi
if [ -n "$MYSQL_VERSION" ];then
    # mysql下载
    download_file https://dev.mysql.com/get/Downloads/mysql-${MYSQL_VERSION%.*}/mysql-$MYSQL_VERSION-winx64.zip "mysql-$MYSQL_VERSION" &
fi
if [ -n "$REDIS_VERSION" ];then
    # redis下载
    download_file https://github.com/tporadowski/redis/releases/download/v$REDIS_VERSION/Redis-x64-$REDIS_VERSION.zip "redis-$REDIS_VERSION" &
fi

# 等待下载完
echo '[wait] 等待下载解压完成'

wait

cd "$INSTALL_PATH/www"
# 生成测试文件
cat >> ./index.php <<EOF
<?php

phpinfo();

EOF

[ -n "$APACHE_VERSION" ] && apache_init
[ -n "$NGINX_VERSION" ] && nginx_init
[ -n "$MYSQL_VERSION" ] && mysql_init
[ -n "$REDIS_VERSION" ] && redis_init
if [ -n "$PHP_VERSION" ];then
    PHP_CGI_PORT=${PHP_VERSION//./}
    php_init
    cd "$SERVERS_PATH"
    # 追加apache配置
    for HTTPD_DIR in $(find ./ -maxdepth 1 -type d -name 'httpd-*' 2>/dev/null);do
        cat >> ${HTTPD_DIR}/conf/extra/httpd-vhosts.conf <<EOF
# 示例模板
<VirtualHost _default_:80>
    # 服务域名只能一个
    ServerName api.game.loc
    # 别名域名可以多个
    ServerAlias admin.game.loc
    # 工作目录
    DocumentRoot "$DOC_ROOT/localhost/public"
    # 指定使用的PHP-$PHP_VERSION
    <FilesMatch "\.php\$">
        # apache-2.4.26起有两个值 FPM|GENERIC
        # php 使用的是GENERIC模式，不指定则会出现 No input file specified.
        ProxyFCGIBackendType GENERIC
        SetHandler "proxy:fcgi://127.0.0.1:${PHP_CGI_PORT}/"
        ProxyFCGISetEnvIf "reqenv('SCRIPT_FILENAME') =~ m#^/?(.*)\$#" SCRIPT_FILENAME "\$1"
    </FilesMatch>
</VirtualHost>
EOF
    done
    # 追加nginx配置
    for NGINX_DIR in $(find ./ -maxdepth 1 -type d -name 'nginx-*' 2>/dev/null);do
        if ! grep -q "set \$PHP_CGI_PORT ${PHP_CGI_PORT};" ${NGINX_DIR}/conf/vhosts/php.conf.default;then
            sed -i "25 a\   # set \$PHP_CGI_PORT ${PHP_CGI_PORT}; # php-$PHP_VERSION" ${NGINX_DIR}/conf/vhosts/php.conf.default
        fi
    done
fi

echo "[info] 生成控制脚本文件"
cd "$INSTALL_PATH"

sed -n "$((LINENO + 4)),\$p" ${SCRIPT_PATH} > run.sh
sed -i "s,__INSTALL_PATH__,\"$SERVERS_PATH\"," run.sh
exit

#!/bin/bash
echo -e "\e[40;35m初始化中...\e[0m";
SERVICES=(httpd nginx mysql php redis)
DEFAULT_RUN_CONF='./.default.run'
cd "/d/php-env/servers"
# 获取进程ID
get_pid(){
    ps aux|grep "/${1}/"|awk '{print $1}'
}
# 获取服务版本集
get_versions(){
    eval "echo \${$(echo "$1"|tr '[:lower:]' '[:upper:]')_VERSIONS[@]}"
}
# 启动服务
start_run(){
    local _VERSION _PARAMS _NAME _PID
    for _VERSION in $(get_versions "$1");do
        _NAME="$1-$_VERSION"
        if [ ! -d "./${_NAME}" ];then
            echo "[warn] ${_NAME}未安装";
            continue
        fi
        case "$1" in
            httpd)
                _PARAMS=(./httpd-$_VERSION/bin/httpd.exe)
            ;;
            nginx)
                _PARAMS=(./nginx-$_VERSION/nginx.exe -p ./nginx-$_VERSION)
            ;;
            mysql)
                _PARAMS=(./mysql-$_VERSION/bin/mysqld.exe)
            ;;
            php)
                PHP_CGI_PORT=${_VERSION//./}
                _PARAMS=(./php-$_VERSION/php-cgi.exe -b 127.0.0.1:$PHP_CGI_PORT -c ./php-$_VERSION/php.ini)
            ;;
            redis)
                _PARAMS=(./redis-$_VERSION/redis-server.exe)
            ;;
            *)
                echo "[warn] 未知服务：$1";
                return 1
            ;;
        esac
        if has_run "${1}";then
            echo "[warn] ${_NAME} 已在运行中";
        else
            nohup ${_PARAMS[@]} 2>/dev/null >/dev/null &
            echo "[info] ${_NAME} 启动中";
        fi
    done
}
# 停止服务
stop_run(){
    local _VERSION _NAME _PID
    for _VERSION in $(get_versions "$1");do
        _NAME="$1-$_VERSION"
        _PID=$(get_pid "${_NAME}")
        if [ -n "$_PID" ];then
            if kill $_PID;then
                echo "[info] ${_NAME} 执行停止"
            else
                echo "[warn] ${_NAME} 停止失败"
            fi
        else
            echo "[warn] 未找到启动进程，跳过停止 ${_NAME}"
        fi
    done
}
# 是否运行
has_run(){
    local _VERSION _RUN=0 _STOP=0
    for _VERSION in $(get_versions "$1");do
        if [ -n "$(get_pid "$1-$_VERSION")" ];then
            ((_RUN++))
        else
            ((_STOP++))
        fi
    done
    if (( _RUN <= 0 ));then
        return 2
    elif (( _STOP > 0 ));then
        return 1
    else
        return 0
    fi
}
# 是否停止
has_stop(){
    has_run $1
    return $((2-$?))
}
# 显示状态
show_status(){
    has_run $1
    local _RES=$?
    if [ "$_RES" = 0 ];then
        echo "\e[40;35m已启动\e[0m";
    elif [ "$_RES" = 1 ];then
        echo "\e[40;33m部分启动\e[0m";
    else
        echo "\e[40;37m未启动\e[0m";
    fi
}
update_default_run(){
    local _NAME _INDEX _ACTION=$1
    shift
    for _NAME;do
        for ((_INDEX=0;_INDEX<${#DEFAULT_RUN_NAME[@]};_INDEX++));do
            if [ "$_NAME" = "${DEFAULT_RUN_NAME[$_INDEX]}" ];then
                if [ "$_ACTION" = 'del' ];then
                    unset DEFAULT_RUN_NAME[$_INDEX]
                else
                    continue 2
                fi
            fi
        done
        if [ "$_ACTION" = 'add' ];then
            DEFAULT_RUN_NAME[${#DEFAULT_RUN_NAME[@]}]=$_NAME
        fi
    done
    echo "${DEFAULT_RUN_NAME[*]}"|base64 -i > $DEFAULT_RUN_CONF
}
# 处理时间
START_TIME=0
CURRENT_TIME=0
DEFAULT_RUN_NAME=()
# 默认启动
if [ -e $DEFAULT_RUN_CONF ];then
    DEFAULT_RUN_NAME=($(cat $DEFAULT_RUN_CONF|base64 -d))
else
    DEFAULT_RUN_NAME=()
fi
echo -e "\e[40;35m读取版本信息...\e[0m";
# 获取安装的版本信息
for _NAME in ${SERVICES[@]};do
    _VERSIONS=($(find ./ -maxdepth 1 -type d -name "${_NAME}-*" 2>/dev/null|grep -oP '\d+(\.\d+)+$'|sort -r))
    eval "$(echo "$_NAME"|tr '[:lower:]' '[:upper:]')_VERSIONS=(${_VERSIONS[@]})"
done
echo -e "\e[40;35m读取启动配置...\e[0m";
if ((${#DEFAULT_RUN_NAME[@]} > 0));then
    HANDLE_LISTS=(${DEFAULT_RUN_NAME[@]});
    HANDLE_NAMES=('init');
    START_TIME=$(date +'%s')
else
    HANDLE_LISTS=();
    HANDLE_NAMES=();
fi
# 服务别名
httpd_ALIAS=apache
php_ALIAS=php-cgi
# 启动状态
HANDLE_STATUS='stop'
echo -e "\e[40;35m初始完成...\e[0m";
while true;do
    CURRENT_TIME=$(date +'%s')
    PRINT_TEXT="\n\e[40;33m可操作序号：\e[0m

\e[40;32m 1、启停apache+php+mysql\e[0m
\e[40;32m 2、启停nginx+php+mysql\e[0m
"
    # 单个启停
    HANDLE_INDEX=3
    for ((_INDEX=0;_INDEX<${#SERVICES[@]};_INDEX++));do
        _NAME=${SERVICES[${_INDEX}]}
        PRINT_TEXT="$PRINT_TEXT\e[40;32m $((_INDEX+3))、启停$(eval "echo \${${_NAME}_ALIAS:-${_NAME}}")\e[0m  [$(show_status ${_NAME})]\n"
    done
    RUN_ACTION=''
    # 处理完前不接受输入
    case "${HANDLE_NAMES[0]}" in
        has_*)
            # 判断是否成功
            HAS_SUCCESS=0
            for SERVER_NAME in ${HANDLE_LISTS[@]};do
                if ${HANDLE_NAMES[0]} $SERVER_NAME;then
                    HAS_SUCCESS=1
                    if [ "${HANDLE_NAMES[0]}" = 'has_stop' ];then
                        CURRENT_STATUS="已停止"
                    else
                        CURRENT_STATUS="已启动"
                    fi
                    break
                fi
            done
            if [ "$HAS_SUCCESS" = 1 ];then
                HANDLE_NAMES=(${HANDLE_NAMES[@]:1})
            else
                if [ "${HANDLE_NAMES[0]}" = 'has_stop' ];then
                    CURRENT_STATUS="停止中..."
                else
                    CURRENT_STATUS="启动中..."
                fi
            fi
            PRINT_TEXT="$PRINT_TEXT\n\n\e[40;31m${CURRENT_STATUS} $((CURRENT_TIME-START_TIME))s\e[0m"
        ;;
        \-)
            PRINT_TEXT="$PRINT_TEXT\n\n\e[40;31m停止中...\e[0m"
            RUN_ACTION='stop'
        ;;
        \+)
            PRINT_TEXT="$PRINT_TEXT\n\n\e[40;31m启动中...\e[0m"
            RUN_ACTION='start'
        ;;
        init)
            PRINT_TEXT="$PRINT_TEXT\n\n\e[40;31m初始启动中...\e[0m"
            HANDLE_NAMES=('+')
        ;;
        \*)
            HANDLE_NAMES=('-' '+')
            echo "重启进行" >&2;
        ;;
        *)
            PRINT_TEXT="$PRINT_TEXT\n
\e[40;35m 功能：启动（+） 停止（-） 重启（*）\e[0m \e[40;36m输入示例：重启 apache，输入 *3\e[0m
\e[40;31m 退出界面输入：q|Q\e[0m\n\n"
        ;;
    esac
    clear
    echo -e "$PRINT_TEXT"
    case "${RUN_ACTION}" in
        stop)
            for SERVER_NAME in ${HANDLE_LISTS[@]};do
                stop_run $SERVER_NAME
            done
            HANDLE_NAMES[0]=has_stop
            HANDLE_STATUS=stop
            # 更新自动启动
            update_default_run 'del' ${HANDLE_LISTS[@]}
        ;;
        start)
            for SERVER_NAME in ${HANDLE_LISTS[@]};do
                start_run $SERVER_NAME
            done
            HANDLE_NAMES[0]=has_run
            HANDLE_STATUS=run
            # 更新自动启动
            update_default_run 'add' ${HANDLE_LISTS[@]}
        ;;
    esac
    if (( START_TIME > 0 ));then
        sleep 0.1
        # 超时就清除操作
        if ((${#HANDLE_NAMES[@]} <= 0 || START_TIME < CURRENT_TIME - 30));then
            START_TIME=0
            HANDLE_NAMES=()
        fi
        continue
    fi
    echo -n '请输入要功能+序号：'
    # 补偿启动处理
    if [ "$HANDLE_STATUS" = 'run' ];then
        for SERVER_NAME in ${HANDLE_LISTS[@]};do
            start_run $SERVER_NAME >/dev/null
        done
    fi
    # 输入提取处理
    while read -t 5 -r INPUT_NUM;do
        case "$INPUT_NUM" in
            [\+\-\*]1)
                HANDLE_LISTS=(httpd php mysql)
            ;;
            [\+\-\*]2)
                HANDLE_LISTS=(nginx php mysql)
            ;;
            [\+\-\*][34567])
                HANDLE_LISTS=("${SERVICES[$((${INPUT_NUM:1} - 3))]}")
            ;;
            q|Q)
                exit
            ;;
            *)
                echo -n -e "未知操作码：${INPUT_NUM}\n请重新输入："
                continue
            ;;
        esac
        HANDLE_NAMES=("${INPUT_NUM:0:1}")
        START_TIME=$(date +'%s')
        echo -e "\n执行操作：${INPUT_NUM}"
        break
    done
    echo -e '\n即将刷新...'
done
