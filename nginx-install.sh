#!/bin/bash
#
# Nginx快速编译安装shell脚本
#
# 安装命令
# bash nginx-install.sh new
# bash nginx-install.sh $verions_num
# 
# 查看最新版命令
# bash nginx-install.sh
#
# 可运行系统：
# CentOS 5+
# Ubuntu 15+
#
# 注意：
#
# nginx异常退出一般是系统kill掉了，通过 dmesg | tail -n 50 来查看，一般是高并发时内存占用过大
#
# 优化点：
# ==============================================================
# ************************************************************
# ******************** 最大并发连接数调整 ********************
# ************************************************************
#
#  nginx作为http服务器的时候：
#    max_clients = worker_processes * worker_connections
#  nginx作为反向代理服务器的时候：（主要是反向代理时会产生代理连接占用）
#    max_clients = worker_processes * worker_connections/4
#
# 配置说明：在nginx.conf 最上面（默认）
#
# worker_processes  4; #工作进程数，一般是几核就指定几个，安装时就自动按几核设置好的
# events {
#     worker_connections  2048; #每个工作进程最大连接数，直接影响并发数量
# }
#
# worker_rlimit_nofile 15360; #每个工作进程打开的最大文件描述符，这个值不可超过系统最大文件描述符，系统查看命令 ulimit -n 。修改可以通过命令 ulimit -n 65535
#
# ==============================================================
#
####################################################################################
##################################### 安装处理 #####################################
####################################################################################
#域名
NGINX_HOST='nginx.org'
# 定义安装类型
DEFINE_INSTALL_TYPE='configure'
# 加载基本处理
source basic.sh
# 初始化安装
init_install '1.0.0' "http://$NGINX_HOST/en/download.html" 'Stable version.*?nginx-\d+\.\d+\.\d+\.tar\.gz'
# ************** 相关配置 ******************
# 编译初始选项（这里的指定必需有编译项）
CONFIGURE_OPTIONS="--prefix=$INSTALL_PATH$NGINX_VERSION --user=nginx --group=nginx "
# 编译增加项（这里的配置会随着编译版本自动生成编译项）
ADD_OPTIONS='threads ?ipv6 http_ssl_module http_stub_status_module '$ARGV_options
# ************** 编译安装 ******************
# 下载nginx包
download_software http://$NGINX_HOST/download/nginx-$NGINX_VERSION.tar.gz
# 解析选项
parse_options CONFIGURE_OPTIONS $ADD_OPTIONS
# 安装依赖
echo "安装相关已知依赖"
if ! if_command pcre-config;then
    # 安装pcre
    packge_manager_run install -PCRE_DEVEL_PACKGE_NAMES
fi
# ssl 模块
if in_options 'http_ssl_module' $CONFIGURE_OPTIONS;then
    # 注意nginx获取openssl目录时是指定几个目录的，所以安装目录变动了会导致编译失败
    # 当安装了多个版本时使用参数 --with-openssl=DIR 指定openssl编译源文件目录（不是安装后的目录）
    if if_many_version openssl version;then
        # 暂存编译目录
        NGINX_CONFIGURE_PATH=`pwd`
        # 获取最新版
        # get_version OPENSSL_VERSION https://www.openssl.org/source/ 'openssl-\d+\.\d+\.\d+[a-z]*\.tar\.gz[^\.]' '\d+\.\d+\.\d+[a-z]*'
        # 版本过高编译不能通过
        OPENSSL_VERSION='1.1.1'
        # 下载
        download_software https://www.openssl.org/source/openssl-$OPENSSL_VERSION.tar.gz openssl-$OPENSSL_VERSION
        CONFIGURE_OPTIONS="$CONFIGURE_OPTIONS --with-openssl=`pwd`"
        cd $NGINX_CONFIGURE_PATH
    elif if_lib 'openssl' '>=' '1.0.1' && which -a openssl|grep -P '^/usr(/local|/pkg)?/bin/openssl$';then
        echo 'openssl ok'
    else
        # 删除原来版本
        packge_manager_run remove -OPENSSL_DEVEL_PACKGE_NAMES
        # 重新安装openssl
        packge_manager_run install -OPENSSL_DEVEL_PACKGE_NAMES
    fi
fi
# http_gzip_module 模块
if ! in_options '!http_gzip_module' $CONFIGURE_OPTIONS;then
    if if_lib 'libzip';then
        echo 'libzip ok'
    else
        # 安装zlib
        packge_manager_run install -ZLIB_DEVEL_PACKGE_NAMES
    fi
fi
# 编译安装
configure_install $CONFIGURE_OPTIONS
# 创建用户组
add_user nginx
# 配置文件处理
echo "nginx 配置文件修改"
cd $INSTALL_PATH$NGINX_VERSION/conf
if [ ! -d "vhosts" ]; then
    mkdirs vhosts
    mkdirs certs
    cd vhosts
    cat > ssl <<conf
#常规https配置
#ssl                  on;
ssl_certificate      certs/ssl.pem;
ssl_certificate_key  certs/ssl.key;

#ssl_session_cache    shared:SSL:1m;
ssl_session_timeout  5m;

#ssl_ciphers  HIGH:!aNULL:!MD5;
#ssl_prefer_server_ciphers  on;
if ( \$scheme = http ) {
 return 301 https://\$host\$request_uri;
}
conf
    cat > ssl_websocket <<conf
# 代理websocket wss连接
location /websocket {
    proxy_pass http://127.0.0.1:800;
    proxy_http_version 1.1;
    proxy_set_header Upgrade \$http_upgrade;
    proxy_set_header Connection "upgrade";
}
conf
    cat > php <<conf
# PHP配置
if (!-e \$request_filename) {
    rewrite  ^/(.*)$ /index.php?s=\$1  last;
    break;
}

# proxy the PHP scripts to Apache listening on 127.0.0.1:80
#
#location ~ \.php$ {
#    proxy_pass   http://127.0.0.1;
#}

# pass the PHP scripts to FastCGI server listening on 127.0.0.1:9000
#
location ~ \.php\$ {
    fastcgi_pass   127.0.0.1:9000;
    fastcgi_index  index.php;
    fastcgi_param  SCRIPT_FILENAME  \$document_root\$fastcgi_script_name;
    include        fastcgi_params;
}
include vhosts/static;
conf
    cat > static <<conf
# 常规静态配置
location = / {
    index index.html index.htm index.php;
}
#error_page  404              /404.html;

# 去掉响应头服务器标识
server_tokens off;

# redirect server error pages to the static page /50x.html
#
# error_page   500 502 503 504  /50x.html;
# location = /50x.html {
#     root   html;
# }

# deny access to .htaccess files, if Apache's document root
# concurs with nginx's one
#

location ~* ^.+\.(jpg|jpeg|png|css|js|gif|html|htm|xls)$ {
    access_log  off;
    expires     30d;
}
conf
    cat > static.conf.default <<conf
server {
    listen 80;
    #listen 443 ssl;
    server_name  localhost;
    root /www/localhost/dist;
    include vhosts/static;
    #include vhosts/ssl;
}
conf
    cat > php.conf.default <<conf
server {
    listen 80;
    #listen 443 ssl;
    server_name localhost;
    root /www/localhost/public;
    include vhosts/php;
    #include vhosts/ssl;
}
conf
    cd ../
fi
if [ ! -e "nginx.conf" ]; then
    cp nginx.conf.default nginx.conf
fi
# 修改工作用户
sed -i -r 's/^#(user\s+)nobody/\1nginx/' nginx.conf
# 开户gzip
sed -i -r 's/^#(gzip\s+)on/\1 on/' nginx.conf
# 修改工作子进程数，最优化，子进程数 = CPU数 * 3 / 2
math_compute PROCESSES_NUM "$HTREAD_NUM * 3 / 2"
sed -i -r "s/^(worker_processes\s+)[0-9]+;/\1 $PROCESSES_NUM;/" nginx.conf
# 修改每个工作进程最大连接数
math_compute MAX_CONNECTIONS "$HTREAD_NUM * 1024"
sed -i -r "s/^(worker_connections\s+)[0-9]+;/\1 $MAX_CONNECTIONS;/" nginx.conf
# 添加引入虚拟配置目录
if [ -z "`cat nginx.conf|grep "vhosts/*"`" ];then
    LAST_NUM=`cat nginx.conf|grep -n '}'|tail -n 1|grep -oP '\d+'`
    LAST_NUM=`expr $LAST_NUM - 1`
    echo "`cat nginx.conf|head -n $LAST_NUM`" > nginx.conf
    echo "    # 如果服务器需要上传大文件时需要设置，否则报413 Request Entity Too Large 错误" >> nginx.conf
    echo "    # client_max_body_size 150m;" >> nginx.conf
    echo "    # 去掉代理响应标识" >> nginx.conf
    echo "    proxy_hide_header X-Powered-By;" >> nginx.conf
    echo "    proxy_hide_header Server;" >> nginx.conf
    echo "    include vhosts/*.conf;" >> nginx.conf
    echo "}" >> nginx.conf
fi
# openssl: error while loading shared libraries: libssl.so.1.1
#if ! ldconfig -v|grep libssl.so; then
#    echo `whereis libssl.so|grep -oP '(/\w+)+/'|grep -oP '(/\w+)+'` >> /etc/ld.so.conf
#fi
cd $INSTALL_PATH$NGINX_VERSION/sbin
if [ -n "`./nginx -t|grep error`" ]; then
    echo "nginx 配置文件错误，请注意修改"
else
    if [ -n "ps aux|grep nginx" ]; then
        ./nginx
    else
        ./nginx -s reload
    fi
fi

# 安装成功
echo "安装成功：nginx-$NGINX_VERSION";
