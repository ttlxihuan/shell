#!/bin/bash
#
# elasticsearch快速编译安装shell脚本
# 官方文档：https://www.elastic.co/guide/en/elasticsearch/reference/master/index.html
#
# 安装命令
# bash elasticsearch-install.sh new
# bash elasticsearch-install.sh $verions_num
# 
# 查看最新版命令
# bash elasticsearch-install.sh
#
# 可运行系统：
# CentOS 6.4+
# Ubuntu 16.04+
#
# 注意启动服务账号不能是root
#
# 如果修改了elasticsearch的监听地址则需要核对下系统里的两个配置：（用户文件描述符数和系统最大虚拟内存最大值）
# vim /etc/security/limits.conf 包含如下两行（一般在最后一行，如果没有则添加并重启登录对应账号），否则容易提示：[1]: max file descriptors [65535] for elasticsearch process is too low, increase to at least [65536]
# 
# * soft nofile 65536
# * hard nofile 65536
#
#
# vim /etc/sysctl.conf  包含如下一行（一般在最后一行，如果没有则添加并执行命令 sysctl -p ），否则容易提示：[2]: max virtual memory areas vm.max_map_count [65530] is too low, increase to at least [262144]
#
# vm.max_map_count=262144
#
#
#
# vim /etc/security/limits.d/90-nproc.conf 修改 *          soft    nproc     1024 中的1024为提示要求最小值，否则容易提示：max number of threads [1024] for user [elasticsearch] is too low, increase to at least [4096]
#
# *          soft    nproc     4096
#
#
#
# 【如果提示】：system call filters failed to install; check the logs and fix your configuration or disable system call filters at your own risk 说明当前系统不支持SecComp，需要修改elasticsearch.yml配置文件中增加bootstrap.system_call_filter选项为false
# vim elasticsearch.yml
#
# bootstrap.system_call_filter: false
#
#
#
# 集群配置点：
#
# cluster.name: 集群名（集群下所有节点配置必需相同）
# node.name:  节点名（集群下需要唯一）
# 
# node.master: 主节点（最少配置一个），true 或 false （主节点主要处理分发和查）
# node.data: 数据节点，true 或 false (数据节点主要处理数据增删改)
#
#
# network.publish_host: 推送域名，只有在discovery.zen.ping.unicast.hosts配置的是域名需要指明推送的域名
#
# discovery.zen.ping.unicast.hosts: ['节点1地址', '节点2地址']   集群节点地址集（主是要IP），不需要包含当前节点地址
# discovery.zen.minimum_master_nodes: 最少启动主节点数，必需小于等于集群主节点数并且大于1，一般设置为 = 主节点数/2+1 如果过大启动会报错：master_not_discovered_exception
#
#
# gateway.recover_after_nodes: 最少启动节点数，达不到就无法完成集群初始恢复等工作
#
#
# 集群配置结果查看命令：curl -XGET 'http://localhost:9200/_cluster/state?pretty'
#
# 【报错】：blocked by: [SERVICE_UNAVAILABLE/1/state not recovered / initialized] 则说明分块异常，主要是组成集群的条件没有达到，比如几个主节点，和最少初始节点数，也就说明集群建立失败。
#
# 注意：API访问默认使用的是9200端口，集群通信默认使用的是9300端口，如果不确认集群之间是通的可以使用命令相互调用 curl http://localhost:9300/ 如果显示： This is not an HTTP port 说明是通的，提示：couldn't connect to host 说明不通，需要排查下防火墙
#
#
# 动态修改集群配置：(通过API请求动态修改，一种临时 transient，一种永久 persistent)
# API: 
# PUT /_cluster/settings
# {
#    "persistent" : {
#        "discovery.zen.minimum_master_nodes" : 2 
#    },
#    "transient" : {
#        "indices.store.throttle.max_bytes_per_sec" : "50mb" 
#    }
#  }
#
# 注意：cluster.name，discovery.zen.ping.unicast.hosts 是不可以动态修改更新
#
# curl -X PUT -H "Content-Type: application/json" -d '{"persistent":{"node.name":"node-0","node.master": true,"node.data":false,"discovery.zen.minimum_master_nodes":1,"gateway.recover_after_nodes":2}}' http://fulltext.zujiekeji.cn:9200/_cluster/settings
#
#
#
#
# 【报错】：TCP: time wait bucket table overflow  这个错误是说网络连接里TIME_WAIT状态数过多，
# 查看错误命令有：dmesg | tail -n 100
# 查看TIME_WAIT数量命令：netstat -n |grep "^tcp" |awk '{print $6}' |sort|uniq -c |sort -n
# 查看套字节连接情况命令： ss -s
# 这类问题主要是系统配置限制最大的套字节连接数据，需要修改系统配置：
# vim /etc/sysctl.conf
#  主要修改配置有：（按上面查看连接总数和硬件配置的情况来调整）
#  net.ipv4.tcp_max_tw_buckets=50000
# 保存后执行生效命令： sysctl -p
#
#
# 【调优建议】
#   1、es查询性能依赖物理内存，且不能有内存交换到磁盘，所以需要开启内存锁定，关闭虚拟内存。jvm的堆内存设定为可用内存的一半以内。es8起支持自动配置。
#   2、创建索引时需要注意分片设置，每个索引有主分片number_of_shards（默认5，不可改）和副本分片数number_of_replicas（默认1，可改），
#       每个分片容量保持与jvm.options指定的-Xmx以内。主分片数据适中，如果数据量小可以设置为1。
#       主分片数据可读可写，副本分片数据只读。
#   3、总分片数不易过多（高版本有单节点最大分片数限制），如果一个索引number_of_shards=5且number_of_replicas=1则有10个分片生成。
#   4、当数据不是很重要或初始大量写时可以关闭refresh_interval=-1（关闭间隔刷新索引）、number_of_replicas=0（关闭副本）、sync_interval=1m（同步到磁盘频次）来提升性能
#   5、索引名尽量不使用_开头
#   6、尽量避免使用join查询，join分nested数据类型和同索引不同type的parent和child
#   7、避免大结果集进行深分页（分页到较高的数值，比如：100页），可以通过指定search_after进行上下页操作，从而减少深分页
#   8、集群配置冷热分离，即配置node.attr.box_type=warm或hot，hot节点配置高用于常用数据保存节点，warn配置低用于处理不怎么使用数据保存节点，可以节省成本和保证性能
#   9、不需要查询的数据建议存放到其它数据库中比如HBase中，无用的数据会增加es的开销
#   10、查询使用filter会存放到query cache缓存中，可以适当（数据变化频次，变化过快的就不用调整了）调整下缓存大小indices.queries.cache.size（默认10%）
#
# 集群监控 Kibana 中的 Metrics 分支（Elasticsearch metrics）就可以监控集群相关信息
# 数据同步工具 canal-adapter
# 
####################################################################################
##################################### 安装处理 #####################################
####################################################################################
# 定义安装参数
DEFINE_RUN_PARAMS="
[-s, --swapoff]禁用虚拟内存，开启后会自动关闭虚拟内存相关配置
[-n, --cluster-name='']指定集群名，注意在主或数据节点中必需包含当前地址
[-t, --node-type='auto', {required|in:master,data,all,auto}]指定当前节点类型：
# master 主节点
# data 数据节点
# all 主和数据节点
# auto 自动提取节点集配置
[-N, --node-name='']指定当前节点在集群中的唯一名，不指定则是集群名+ip
[-m, --master-hosts='']指定主节点集用逗号分开，仅支持IP地址
#如果包含当前节点则自动过滤，没有指定集群名此参数无效
[-d, --data-hosts='']指定数据节点集用逗号分开，仅支持IP地址
#如果包含当前节点则自动过滤，没有指定集群名此参数无效
[-T, --tool='kibana', {in:kibana}]安装管理工具，目前支持 kibana
[-M, --jvm-memory='50%', {required|size}]指定配置服务运行JVM最大占用内存（整数）
#指定可用内存占比，比如：70%
#指定对应的大小，单位（B,K,M,G,T），比如：4G
#不指定单位为B，最大空间30G，超过将截断
#指定为0时即不配置内存
[-U, --username='']

[-P, --password='']
#生成随机密码语法 make:numm,set
#   make: 是随机生成密码关键字
#   num   是生成密码长度个数
#   set   限定密码包含字符，默认：数字、字母大小写、~!@#$%^&*()_-=+,.;:?/\|
#生成随机10位密码 make:10
#生成随机10位密码只包含指定字符 make:10,QWERTYU1234567890
#其它字符均为指定密码串，比如 123456
"
# 加载基本处理
source "$(cd "$(dirname "${BASH_SOURCE[0]}")"; pwd)"/../../includes/install.sh || exit
# 初始化安装
init_install 5.0.0 "https://www.elastic.co/downloads/elasticsearch" 'elasticsearch-\d+\.\d+\.\d+-linux'
if [ -n "$ARGV_tool" ] && ! [[ "$ARGV_tool" =~ ^kibana$ ]]; then
    error_exit "--tool 只支持kibana，现在是：$ARGV_tool"
fi
# 解析最大运行内存参数处理
parse_use_memory JVM_XM_MEMORY "${ARGV_jvm_memory}" G

get_ip
if [ -n "$ARGV_cluster_name" ];then
    if ! parse_lists CLUSTER_MASTER_HOSTS "$ARGV_master_hosts" ',' '\d{1,3}(\.\d{1,3}){3}';then
        error_exit '--master-hosts 集群地址格式错误：'${ARGV_master_hosts:$?}
    fi
    if ((${#CLUSTER_MASTER_HOSTS[@]} < 1)) && ! [[ "$ARGV_node_type" =~ ^(master|all)$ ]];then
        error_exit "--master-hosts 在集群中不能为空，最少指定一个主节点"
    fi
    if ! parse_lists CLUSTER_DATA_HOSTS "$ARGV_data_hosts" ',' '\d{1,3}(\.\d{1,3}){3}';then
        error_exit '--data-hosts 集群地址格式错误：'${ARGV_data_hosts:$?}
    fi
    if [ -z "$ARGV_node_name" ];then
        ARGV_node_name=$ARGV_cluster_name-$SERVER_IP
    fi
    NODE_DATA_VALUE='false'
    NODE_MASTER_VALUE='false'
    if [ "$ARGV_node_type" = 'all' ];then
        NODE_DATA_VALUE='true'
        NODE_MASTER_VALUE='true'
    elif [ "$ARGV_node_type" = 'data' ];then
        NODE_DATA_VALUE='true'
    elif [ "$ARGV_node_type" = 'master' ];then
        NODE_MASTER_VALUE='true'
    elif [ "$ARGV_node_type" = 'auto' ];then
        if [[ "$ARGV_master_hosts" =~ (^|[^0-9])`echo $SERVER_IP`([^0-9]|$) ]];then
            NODE_MASTER_VALUE='true'
        fi
        if [[ "$ARGV_data_hosts" =~ (^|[^0-9])`echo $SERVER_IP`([^0-9]|$) ]];then
            NODE_DATA_VALUE='true'
        fi
        if [ "$NODE_MASTER_VALUE" = 'false' -a "$NODE_DATA_VALUE" = 'false' ];then
            error_exit "--node-type 节点集中无法匹配当前节点，请核对IP地址是否正确"
        fi
    fi
elif [ -n "$ARGV_master_hosts$ARGV_data_hosts" ];then
    error_exit "--cluster-name 未指定，无法配置集群，请核对安装参数"
fi
#  限制空间大小（G）：编译目录、安装目录、内存
install_storage_require 3 4 1
# ************** 安装 ******************
# 下载elasticsearch包
LINUX_BIT=`uname -a|grep -P 'x\d+_\d+' -o|tail -n 1`
# 不同版本文件名有区别
if if_version $ELASTICSEARCH_VERSION '>=' '7.0.0'; then
    # 7.0以上的版本
    TAR_FILE_NAME="-linux-$LINUX_BIT"
else
    TAR_FILE_NAME=""
fi
download_software https://artifacts.elastic.co/downloads/elasticsearch/elasticsearch-$ELASTICSEARCH_VERSION$TAR_FILE_NAME.tar.gz elasticsearch-$ELASTICSEARCH_VERSION$(echo "$TAR_FILE_NAME"|sed -r 's/-linux-.*$//')
# 暂存编译目录
ELASTICSEARCH_CONFIGURE_PATH=$(pwd)

# 安装验证 java
install_java

cd $ELASTICSEARCH_CONFIGURE_PATH
# 复制安装包并创建用户
copy_install elasticsearch

mkdirs data elasticsearch

info_msg "elasticsearch 配置文件修改"

# JVM堆内存大小配置，堆用来缓存数据，同时es也依赖filesystem cache
# 堆大小不建议超过32G且最多是系统物理内存的一半，堆内存大小受
# 为合理处理堆内存使用物理可用内存的1/2并向下取整为G，当不足1G时此参数不变
# es实际使用内存将可能超过JVM堆内存，因为es运行本身需要内存、还依赖缓冲区、文件系统缓存等
# es-8启支持自动配置-Xmx，即可以不指定
if ((JVM_XM_MEMORY > 0));then
    # 设置大小不建议超过30G，同时启动后注意：heap size [实际有效大小], compressed ordinary object pointers [true]
    JVM_XM_MEMORY=$((JVM_XM_MEMORY > 30 ? 30 : JVM_XM_MEMORY))
    info_msg "JVM 堆内存大小设置为：${JVM_XM_MEMORY}G"
    info_msg "启动后注意日志中打印的实际堆内存大小：heap size [看这里的大小], compressed ordinary object pointers [true]。如果小于配置就修改配置重启"
    sed -i -r "s/^\s*#*\s*(-Xm[sx])[0-9]+[mgt]/\1${JVM_XM_MEMORY}g/g" ./config/jvm.options
fi
# 调整内存交换，内存交换即将物理内存数据转移到磁盘上，用来回收物理内存
# 转移原则是访问频次底的内存页面优先转移，当应用使用时再转移到物理内存中，期间可能会导致应用卡顿等待内存读取
# 转移不仅会造成应用等待，还有可能是应用即将回收的数据来回转移拖慢性能（比如java的FullGC回收空间时会造成严重卡顿）
# 对于操作需要内存数据时尽量设置此配置为0，即优先清理page cache数据。
# 以下有修改待验证
if [ "$ARGV_swapoff" = '1' ];then
    info_msg '禁用虚拟内存，并修改相关配置'
    run_msg "echo '0' > /proc/sys/vm/swappiness"
    # 禁用所有swap，即无法进行物理数据转移到磁盘虚拟内存
    run_msg "swapoff -a"
fi
# 系统不支持SecComp处理
if [ -e "/proc/$$/status" ] && ! cat /proc/$$/status|grep -qP '^Seccomp:';then
    info_msg "当前系统不支持SecComp，即将配置 bootstrap.system_call_filter: false"
    sed -i -r "s/^#?(bootstrap\.memory_lock:).*$/\1 false/" ./config/elasticsearch.yml
    SET_LINEON=`grep -noP '^#?bootstrap.memory_lock:' ./config/elasticsearch.yml|grep -oP '^\d+'`
    if [ -n "$SET_LINEON" ];then
        ((SET_LINEON++))
        sed -i "${SET_LINEON}i bootstrap.system_call_filter: false" ./config/elasticsearch.yml
    fi
else
    info_msg "当前系统支持SecComp"
    # 锁定内存可能会失败，导致无法启动
    # sed -i -r "s/^#?(bootstrap\.memory_lock:).*$/\1 true/" ./config/elasticsearch.yml
fi
# 集群配置
if [ -n "$ARGV_cluster_name" ];then
    info_msg "集群配置处理"
    CLUSTER_NAME=$(printf '%s' "$ARGV_cluster_name"|sed 's/\//\\\//g')
    NODE_NAME=$(printf '%s' "$ARGV_node_name"|sed 's/\//\\\//g')
    NODES_HOST=`printf '%s' "$ARGV_master_hosts"|sed -r 's/[^0-9|\.]+/ /g'|sed -r 's/([0-9|\.]+)/"\1", /g'`
    NODES_HOST=$NODES_HOST`printf '%s' "$ARGV_data_hosts"|sed -r 's/[^0-9|\.]+/ /g'|sed -r 's/([0-9|\.]+)/"\1", /g'`
    NODES_HOST=`printf '%s' "$NODES_HOST"|sed -r "s/\"$SERVER_IP\"(, )?//"|sed -r 's/(,|\s)+$//'`
    NODES_NUM=$(( (`printf '%s' "$NODES_HOST"|grep -o ','|wc -m`+1)/2+1 ))
    # 写集群标识
    info_msg '写集群标识'
    info_msg '所有集群节点：'$NODES_HOST
    info_msg '集群节点数：'$NODES_NUM
    sed -i -r "s/^#?(cluster\.name:).*$/\1 $CLUSTER_NAME/" ./config/elasticsearch.yml
    sed -i -r "s/^#?(node\.name:).*$/\1 $NODE_NAME/" ./config/elasticsearch.yml
    # 写节点类型
    info_msg '写节点类型'
    SET_LINEON=`grep -noP '^node.name:' ./config/elasticsearch.yml|grep -oP '^\d+'`
    if [ -n "$SET_LINEON" ];then
        ((SET_LINEON++))
        sed -i "${SET_LINEON}i node.data: $NODE_DATA_VALUE" ./config/elasticsearch.yml
        sed -i "${SET_LINEON}i node.master: $NODE_MASTER_VALUE" ./config/elasticsearch.yml
    fi
    info_msg '写集群连接及限制'
    # 各版本差异
    if if_version $ELASTICSEARCH_VERSION '>=' '7.0.0'; then
        # 配置集群所有节点
        sed -i -r "s/^#?(discovery\.seed_hosts:).*$/\1 [$NODES_HOST]/" ./config/elasticsearch.yml
        # 配置初始化必需连接主节点，初始化完成后此参数无效
        sed -i -r "s/^#?(cluster\.initial_master_nodes:).*$/\1 [$NODES_HOST]/" ./config/elasticsearch.yml
    else
        # 配置集群所有节点
        sed -i -r "s/^#?(discovery\.zen\.ping.unicast.hosts:).*$/\1 [$NODES_HOST]/" ./config/elasticsearch.yml
        # 配置最少连接主节点数才能工作
        sed -i -r "s/^#?(discovery\.zen\.minimum_master_nodes:).*$/\1 $NODES_NUM/" ./config/elasticsearch.yml
    fi
    if if_version $ELASTICSEARCH_VERSION '<' '8.0.0'; then
        # 配置最少连接节点数才能进行选举操作并工作
        sed -i -r "s/^#?(gateway\.recover_after_nodes:).*$/\1 $NODES_NUM/" ./config/elasticsearch.yml
    fi
fi
if grep -qP '^logger\.xpack' ./config/*.properties; then
    # xpack 安全配置处理
    CA_FILE="./config/certs/elastic-stack-ca.p12"
    CERT_FILE="./config/certs/elastic-stack-cert.p12"
    # 生成证书
    if [ ! -e $CA_FILE ];then
        ./bin/elasticsearch-certutil ca --pass '' --out $CA_FILE
    fi
    if [ -e $CA_FILE -a ! -e $CERT_FILE ];then
        ./bin/elasticsearch-certutil cert --pass '' --out $CERT_FILE --ca $CA_FILE --ca-pass ''
        # 创建授权密码
        ./bin/elasticsearch-keystore create 
    fi

    
# 这里没有配置处理，需要了解下
#
#
#
#





    echo '# -------------- xpack --------------' >> ./config/elasticsearch.yml
    if [ -e $CA_FILE -a -e $CA_FILE ];then
        echo 'xpack.security.transport.ssl.enabled: true' >> ./config/elasticsearch.yml
        echo 'xpack.security.transport.ssl.verification_mode: certificate' >> ./config/elasticsearch.yml
        echo 'xpack.security.transport.ssl.keystore.path: certs/elastic-stack-cert.p12' >> ./config/elasticsearch.yml
        echo 'xpack.security.transport.ssl.truststore.path: certs/elastic-stack-cert.p12' >> ./config/elasticsearch.yml
    else
        echo 'xpack.security.transport.ssl.enabled: false' >> ./config/elasticsearch.yml
    fi
fi
# 添加服务配置
SERVICES_CONFIG=()
SERVICES_CONFIG[$SERVICES_CONFIG_START_RUN]="./bin/elasticsearch -d --pidfile ./logs/elasticsearch_server.pid"
SERVICES_CONFIG[$SERVICES_CONFIG_USER]="elasticsearch"
SERVICES_CONFIG[$SERVICES_CONFIG_PID_FILE]="./logs/elasticsearch_server.pid"
# 服务并启动服务
add_service SERVICES_CONFIG

# 安装 kibana
if [ "$ARGV_tool" = 'kibana' ];then
    # 获取对应版本
    KIBANA_PATH_NAME="kibana-$ELASTICSEARCH_VERSION-linux-$LINUX_BIT"
    if if_version $ELASTICSEARCH_VERSION '>=' '8.0.0'; then
        KIBANA_DIR_NAME="kibana-$ELASTICSEARCH_VERSION"
    else
        KIBANA_DIR_NAME=$KIBANA_PATH_NAME
    fi
    download_software https://artifacts.elastic.co/downloads/kibana/$KIBANA_PATH_NAME.tar.gz $KIBANA_DIR_NAME
    # 复制安装包并创建用户
    copy_install kibana "$INSTALL_BASE_PATH/kibana/$ELASTICSEARCH_VERSION"

    # 修改配置
    KIBANA_PID="./logs/kibana_server.pid"
    sed -i -r "s,^#\s*(pid.file:).*,\1 $KIBANA_PID," config/kibana.yml
    # 启动kibana

    # 添加服务配置
    SERVICES_CONFIG_KIBANA=()
    SERVICES_CONFIG_KIBANA[$SERVICES_CONFIG_NAME]="kibana-$ELASTICSEARCH_VERSION"
    SERVICES_CONFIG_KIBANA[$SERVICES_CONFIG_BASE_PATH]="$INSTALL_BASE_PATH/kibana/$ELASTICSEARCH_VERSION"
    SERVICES_CONFIG_KIBANA[$SERVICES_CONFIG_START_RUN]="nohup ./bin/kibana 2>&1 >>./logs/kibana_server.log &"
    SERVICES_CONFIG_KIBANA[$SERVICES_CONFIG_USER]="kibana"
    SERVICES_CONFIG_KIBANA[$SERVICES_CONFIG_PID_FILE]="$KIBANA_PID"
    # 服务并启动服务
    add_service SERVICES_CONFIG_KIBANA

fi

info_msg "安装成功：elasticsearch-$ELASTICSEARCH_VERSION"
