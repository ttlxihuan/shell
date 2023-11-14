#!/bin/bash
#
# Nginx快速编译安装shell脚本
# 官方文档：https://nginx.org/en/docs/
# 内置命令目录：https://nginx.org/en/docs/dirindex.html
# 内置变量目录：https://nginx.org/en/docs/varindex.html
#
# 安装命令
# bash nginx-install.sh new
# bash nginx-install.sh $verions_num
# 
# 查看最新版命令
# bash nginx-install.sh
#
# 可运行系统：
# CentOS 6.4+
# Ubuntu 16.04+
#
# 注意：
# nginx异常退出一般是系统kill掉了，通过 dmesg | tail -n 50 来查看，一般是高并发时内存占用过大
# 特别注意：当使用 nginx -s reload 无效时（实际未重新加载配置），可以使用 nginx -s stop && nginx 重启
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
# nginx 可以支持lua和njs（一种专用js）
# lua 是三方提供的模块，可以使用 openresty（集成nginx和lua包） 或 tengine（淘宝开源基于nginx集成包）。集成包提供了很多高级功能，可以说是nginx的延申。
#     openresty 下载地址： http://openresty.org/cn/download.html  版本与官方同步
#     tengine 下载地址：http://tengine.taobao.org/download.html  版本未与官方同步
# njs 是官方提供非绑定模块，此功能出来比较晚且没有lua应用多成熟
#       官方文档：http://nginx.org/en/docs/njs/index.html
#
####################################################################################
##################################### 安装处理 #####################################
####################################################################################
#域名
NGINX_HOST='nginx.org'
# 定义安装类型
DEFINE_INSTALL_TYPE='configure'
# 编译默认项（这里的配置会随着编译版本自动生成编译项）
DEFAULT_OPTIONS='threads ?ipv6 http_ssl_module http_stub_status_module'
# 加载基本处理
source "$(cd "$(dirname "${BASH_SOURCE[0]}")"; pwd)"/../../includes/install.sh || exit
# 初始化安装
init_install '1.0.0' "http://$NGINX_HOST/en/download.html" 'Stable version.*?nginx-\d+\.\d+\.\d+\.tar\.gz'
#  限制空间大小（G）：编译目录、安装目录、内存
install_storage_require 1 1 1
# ************** 相关配置 ******************
# 编译初始选项（这里的指定必需有编译项）
CONFIGURE_OPTIONS="--prefix=$INSTALL_PATH$NGINX_VERSION --user=nginx --group=nginx "
# ************** 编译安装 ******************
# 下载nginx包
download_software http://$NGINX_HOST/download/nginx-$NGINX_VERSION.tar.gz
# 解析选项
parse_options CONFIGURE_OPTIONS $DEFAULT_OPTIONS $ARGV_options
# 暂存编译目录
NGINX_CONFIGURE_PATH=`pwd`
# 安装依赖
info_msg "安装相关已知依赖"

# 安装验证 pcre-config
install_pcre_config

# ssl 模块
if has_option 'http_ssl_module' $CONFIGURE_OPTIONS;then
    # 注意nginx获取openssl目录时是指定几个目录的，所以安装目录变动了会导致编译失败
    # 当安装了多个版本时使用参数 --with-openssl=DIR 指定openssl编译源文件目录（不是安装后的目录）
    # 安装验证 openssl
    if ! install_openssl '1.0.1' '' '1.1.1' 2;then
        CONFIGURE_OPTIONS="$CONFIGURE_OPTIONS --with-openssl=`pwd`"
    fi
fi
# http_gzip_module 模块
if ! has_option '!http_gzip_module' $CONFIGURE_OPTIONS;then
    # 安装验证 zlib
    install_zip
fi

cd $NGINX_CONFIGURE_PATH
# 编译安装
configure_install $CONFIGURE_OPTIONS
# 创建用户组
add_user nginx
# 配置文件处理
info_msg "nginx 配置文件修改"
cd $INSTALL_PATH$NGINX_VERSION/conf
if [ ! -d "vhosts" ]; then
    mkdirs vhosts
    mkdirs certs
    cd vhosts
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

# fastcgi接口监听 127.0.0.1:9000
# 转到php-fpm上
location ~ \.php\$ {
    fastcgi_pass   127.0.0.1:9000;
    fastcgi_index  index.php;
    fastcgi_param  SCRIPT_FILENAME  \$document_root\$fastcgi_script_name;
    include        fastcgi_params;
    # php配置调整，仅在当前配置下有效
    # 禁用函数
    # fastcgi_param  PHP_ADMIN_VALUE "disable_functions=eval";
    # 禁用类
    # fastcgi_param  PHP_ADMIN_VALUE "disable_classes=PDO";
    # 限制可打开目录
    # fastcgi_param  PHP_ADMIN_VALUE "open_basedir=/www";
}
# 使用静态配置
include vhosts/static;
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
    root /www/localhost/dist;

    # 独立日志文件，方便查看
    access_log logs/\$host-access.log;

    # 引用静态文件基础配置
    include vhosts/static;
}
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
    root /www/localhost/public;

    # 独立日志文件，方便查看
    access_log logs/\$host-access.log;

    # 检查请求实体大小，超出返回413状态码，为0则不检查。
    # client_max_body_size 10m;

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
    cat > upstream.conf.default <<conf
# 此文件为负载均衡配置模板
# 使用时建议复制文件并去掉文件名后缀 .default
# 开启后视需求修改：集群名、集群节点、负载均衡入口端口、独立日志

# 以下配置示例中丢弃了商业相关命令（即付费版本有效）
# 集群文档：http://nginx.org/en/docs/http/ngx_http_upstream_module.html

# 集群节点配置，需要指定唯一集群名
# 命令语法：upstream name { ... }
#   name        集群名
#   { ... }     集群节点及策略等配置区
# 集群名用于proxy_pass、fastcgi_pass配置，例如：
#   proxy_pass http://集群名
#   proxy_pass https://集群名
#   fastcgi_pass 集群名; 
# 实际注意修改集群名
upstream http_cluster {
    # 负载均衡策略配置分为：逐个循环、最少连接、ip哈希、哈希、随机等
    # 当一组负载只有一个节点时，将没有不可用处理
    # 默认逐个循环策略

    # 开启最少连接策略，开启后会优先匹配连接少的节点
    # 从1.3.2和1.2.2开始有效
    # least_conn;

    # 开启随机策略
    # 从1.15.1版本开始有效
    # 命令语法：random [two [method]];
    #   two         可选，指定随机提取两个节点再进行其它策略，不指定在所有节点中随机取一个节点
    #   method      可选，指定在随机节点基础上再策略，默认 least_conn
    #               指定后将在两个节点先中使用指定策略提取最终匹配节点
    # random

    # 开启ip哈希持久策略，开启后首次按其它策略匹配节点且生成ip哈希值并与节点绑定，之后对应IP哈希值持久连接到固定节点
    # 哈希匹配节点不可用将重新按首次匹配并绑定节点
    # 从1.3.2和1.2.2开始支持IPv6地址
    # 在1.3.1和1.2.2版本之前，不可指定节点权重
    # ip_hash;

    # 开启哈希持久策略，开启后首次按其它策略匹配节点且生成哈希值并与节点绑定，后续对应哈希值持久连接到固定节点
    # 哈希匹配节点不可用将重新按首次匹配并绑定节点
    # 添加或删除节点可能会导致将大多数密钥重新映射到不同的节点，避免需要增加consistent选项
    # 从1.7.2版本开始有效
    # 命令语法：hash key [consistent];
    # key           可以包含文本或变量（允许组合），指定后会按此值生成hash再绑定节点
    #               可用变量文档：https://nginx.org/en/docs/http/ngx_http_core_module.html#variables
    # consistent    可选项（固定值），则将使用ketama一致性哈希方法代替，减少节点可用数变化大量重新映射节点
    # 以下hash内容：服务端口号+请求类型+请求全地址（含GET参数）
    # hash \$server_port\$request_method\$request_uri consistent;

    # 节点配置
    # 命令语法：server address [parameters];
    #   address         节点HOST+IP，具体是http还是https由proxy_pass命令决定
    #   parameters      可选附加参数
    #       weight=number       节点权重配置，值越高匹配机率越大，默认 weight=1
    #       max_conns=number    限制节点最大连接数，1.11.5版开始有效，默认 max_conns=0
    #       max_fails=number    指定节点持续时间内最大失败尝试次数，超过即节点不可用，默认 max_fails=0
    #       fail_timeout=time   指定节点失败尝试持续时长，与max_fails对应次数，超过即节点不可用，默认 fail_timeout=10
    #       backup              指定为备份节点，当其它节点都不可用时才加入策略匹配，该参数不能与 hash、ip_hash、random 并存，默认无
    #       down                指定节点永久不可用，默认无
    #       resolve             监控节点域名对应的IP变化并自动修正到代理转发中，1.5.12版本开始有效【依赖商业命令sticky】
    #       route=string        设置节点路由名称【依赖商业命令sticky】
    #       service=name        启用解析 DNS SRV 记录，1.9.13版本开始有效【依赖商业命令sticky】
    #       slow_start=time     设置节点从不可用到可用时权重值回升时长，该参数不能与 hash、ip_hash、random 并存，默认无
    #       drain               设置节点为排水模式，1.13.6版本开始有效【依赖商业命令sticky】
    # 节点集配置
    server  localhost:10001 weight=1;

    # 通过keepalive的保活最大连接数，超过将关闭连接，不建议设置，此配置依赖 Keepalived 服务
    # 1.15.3版开始有效
    # keepalive_requests 100;

    # 限制通过一个保活连接处理请求的最长时间，此配置依赖 Keepalived 服务
    # 1.15.3版开始有效
    # keepalive_time 1h;

    # 在此期间与上游服务器的空闲保持连接将保持打开状态，此配置依赖 Keepalived 服务
    # 1.15.3版开始有效
    # keepalive_timeout 60s;

    # 设置保留在每个工作进程缓存中上游服务器的最大空闲保持连接数，此配置依赖 Keepalived 服务
    # 此配置项必需在节点集下面才有效
    # 1.1.4版开始有效
    # keepalive 100
}
# 负载均衡入口配置
server {
    # 配置端口号
    listen       80;

    # 配置https
    # include vhosts/ssl;
    # 指定使用的证书
    # include vhosts/host.cert;

    # 配置访问域名，多个空格隔开
    server_name  localhost;

    # 独立日志文件，方便查看
    # access_log logs/\$host-access.log

    location / {
        # 负载均衡各节点使用http
        proxy_pass http://http_cluster;

        # 负载均衡各节点使用https
        # proxy_pass https://http_cluster;

        # 负载均衡各节点使用fastcgi，比如php-fpm使用此命令
        # fastcgi_pass http_cluster;

        # 设置此参数可使用keepalive命令有效
        # fastcgi_keep_conn on

        proxy_redirect default;

        # 保持身份验证上下文时需要开启下两项
        # proxy_http_version 1.1;
        # proxy_set_header Connection "";
        
        # 指定携带头信息
        proxy_set_header platform proxy-\$host;
    }

    # 检查请求实体大小，超出返回413状态码，为0则不检查。
    # client_max_body_size 10m;
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
math_compute PROCESSES_NUM "$TOTAL_THREAD_NUM * 3 / 2"
sed -i -r "s/^(worker_processes\s+)[0-9]+;/\1 $PROCESSES_NUM;/" nginx.conf
# 修改每个工作进程最大连接数
math_compute MAX_CONNECTIONS "$TOTAL_THREAD_NUM * 1024"
sed -i -r "s/^(worker_connections\s+)[0-9]+;/\1 $MAX_CONNECTIONS;/" nginx.conf
# 添加引入虚拟配置目录
if [ -z "`cat nginx.conf|grep "vhosts/*"`" ];then
    LAST_NUM=`cat nginx.conf|grep -n '}'|tail -n 1|grep -oP '\d+'`
    sed -i "${LAST_NUM}d" nginx.conf
    cat >> nginx.conf <<EOF
    # 压缩配置
    gzip_min_length 512; # 最小压缩文件
    gzip_buffers     4 16k;  # 压缩缓存
    # gzip_http_version 1.1;
    gzip_comp_level 9;  # 压缩等级，1~9，等级高压缩率大CPU开销也大
    # 压缩响应类型
    gzip_types     *;  # 压缩所有数据
    gzip_vary on;
    gzip_proxied   any;
    # 禁止在低端浏览器上压缩
    gzip_disable   "MSIE [1-6]\.";

    # 去掉代理响应标识
    proxy_hide_header X-Powered-By;
    proxy_hide_header Server;

    # 加载站点配置
    include vhosts/*.conf;
}
EOF
fi

cd $INSTALL_PATH$NGINX_VERSION/sbin
if [ -n "`./nginx -t|grep error`" ]; then
    info_msg "nginx 配置文件错误，请注意修改"
else
    # 添加服务配置
    SERVICES_CONFIG=()
    SERVICES_CONFIG[$SERVICES_CONFIG_START_RUN]="./sbin/nginx"
    SERVICES_CONFIG[$SERVICES_CONFIG_STOP_RUN]="./sbin/nginx -s stop"
    SERVICES_CONFIG[$SERVICES_CONFIG_RESTART_RUN]="./sbin/nginx -s reload"
    SERVICES_CONFIG[$SERVICES_CONFIG_PID_FILE]="./logs/nginx.pid"
    # 服务并启动服务
    add_service SERVICES_CONFIG
fi

# 安装成功
info_msg "安装成功：nginx-$NGINX_VERSION";
