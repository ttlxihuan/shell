#!/bin/bash
#
# elasticsearch快速编译安装shell脚本
#
# 安装命令
# bash elasticsearch-install.sh new
# bash elasticsearch-install.sh $verions_num
# 
# 查看最新版命令
# bash elasticsearch-install.sh
#
# 可运行系统：
# CentOS 5+
# Ubuntu 15+
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
#
# 集群监控 Kibana 中的 Metrics 分支（Elasticsearch metrics）就可以监控集群相关信息
# 数据同步工具 canal-adapter
# 
####################################################################################
##################################### 安装处理 #####################################
####################################################################################
# 定义安装参数
DEFINE_INSTALL_PARAMS="
[-n, --cluster-name='']指定集群名，注意在主或数据节点中必需包含当前地址
[-t, --node-type='auto']指定当前节点类型：master 主节点、data 数据节点、all 主和数据节点、auto 自动提取节点集配置
[-N, --node-name='']指定当前节点在集群中的唯一名，不指定则是集群名+ip
[-m, --master-hosts='']指定主节点集用逗号分开，没有指定集群名此参数无效，仅支持IP地址，如果包含当前节点则自动过滤
[-d, --data-hosts='']指定数据节点集用逗号分开，没有指定集群名此参数无效，仅支持IP地址，如果包含当前节点则自动过滤
[-T, --tool='kibana']安装管理工具，目前支持 kibana
"
# 加载基本处理
source basic.sh
# 初始化安装
init_install 5.0.0 "https://www.elastic.co/downloads/elasticsearch" 'elasticsearch-\d+\.\d+\.\d+'
if [ -n "$ARGV_tool" ] && ! [[ "$ARGV_tool" =~ ^kibana$ ]]; then
    error_exit "--tool 只支持kibana，现在是：$ARGV_tool"
fi
get_ip
if [ -n "$ARGV_cluster_name" ];then
    if [ -z "$ARGV_master_hosts" ];then
        error_exit "--master-hosts 在集群中不能为空，最少指定一个主节点"
    fi
    if [ -z "$ARGV_node_name" ];then
        ARGV_node_name=$ARGV_cluster_name-$SERVER_IP
    fi
    if ! [[ "$ARGV_node_type" =~ ^(master|data|all|auto)$ ]];then
        error_exit "--node-type 参数值错误，只允许指定为：master、data、all、auto"
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
# ************** 安装 ******************
# 下载elasticsearch包
LINUX_BIT=`uname -a|grep -P 'el\d+\.x\d+_\d+' -o|grep -P 'x\d+_\d+' -o`
# 不同版本文件名有区别
if if_version $ELASTICSEARCH_VERSION '>=' '8.0.0'; then
    # 8.0以上的版本
    TAR_FILE_NAME="-alpha2-linux-$LINUX_BIT"
elif if_version $ELASTICSEARCH_VERSION '>=' '7.0.0'; then
    # 7.0以上的版本
    TAR_FILE_NAME="-linux-$LINUX_BIT"
else
    TAR_FILE_NAME=""
fi
download_software https://artifacts.elastic.co/downloads/elasticsearch/elasticsearch-$ELASTICSEARCH_VERSION$TAR_FILE_NAME.tar.gz elasticsearch-$ELASTICSEARCH_VERSION$(echo "$TAR_FILE_NAME"|sed -r 's/-linux-.*$//')
# 创建用户
add_user elasticsearch
# 复制安装包
mkdirs $INSTALL_PATH$ELASTICSEARCH_VERSION
echo '复制所有文件到：'$INSTALL_PATH$ELASTICSEARCH_VERSION
cp -R ./* $INSTALL_PATH$ELASTICSEARCH_VERSION
cd $INSTALL_PATH$ELASTICSEARCH_VERSION
# 安装java
tools_install java

mkdirs data

chown -R elasticsearch:elasticsearch ./*

#echo "系统限制相关配置文件修改"
# 修改系统限制配置文件
#if [ -e '/etc/security/limits.conf' ] && ! grep -qP '^elasticsearch soft nofile' /etc/security/limits.conf;then
#    echo 'elasticsearch soft nofile 65536' > /etc/security/limits.conf
#    echo 'elasticsearch hard nofile 65536' > /etc/security/limits.conf
#fi
#if [ -e '/etc/sysctl.conf' ] && ! grep -qP '^vm\.max_map_count=' /etc/sysctl.conf;then
#    echo 'vm.max_map_count=262144' > /etc/sysctl.conf
#    sysctl -p
#fi
#if [ -d '/etc/security/limits.d/' ];then
#    LIMITS_CONFIG=`find /etc/security/limits.d/ -name '*nproc.conf'|tail -n 1`
#    if [ -n "$LIMITS_CONFIG" ] && ! grep -qP '^(\*|elasticsearch)\s+soft\s+nproc\s+4096' $LIMITS_CONFIG;then
#        echo 'elasticsearch     soft    nproc     4096' > $LIMITS_CONFIG
#    fi
#fi

echo "elasticsearch 配置文件修改"
if [ -e "/proc/$$/status" ] && ! cat /proc/$$/status|grep -qP '^Seccomp:';then
    echo "当前系统不支持SecComp，即将配置 bootstrap.system_call_filter: false"
    sed -i -r "s/^#?(bootstrap\.memory_lock:).*$/\1 false/" ./config/elasticsearch.yml
    SET_LINEON=`grep -noP '^#?bootstrap.memory_lock:' ./config/elasticsearch.yml|grep -oP '^\d+'`
    if [ -n "$SET_LINEON" ];then
        ((SET_LINEON++))
        sed -i "${SET_LINEON}i bootstrap.system_call_filter: false" ./config/elasticsearch.yml
    fi
fi
# 集群配置
if [ -n "$ARGV_cluster_name" ];then
    echo "集群配置处理"
    CLUSTER_NAME=$(printf '%s' "$ARGV_cluster_name"|sed 's/\//\\\//g')
    NODE_NAME=$(printf '%s' "$ARGV_node_name"|sed 's/\//\\\//g')
    NODES_HOST=`printf '%s' "$ARGV_master_hosts"|sed -r 's/[^0-9|\.]+/ /g'|sed -r 's/([0-9|\.]+)/"\1", /g'`
    NODES_HOST=$NODES_HOST`printf '%s' "$ARGV_data_hosts"|sed -r 's/[^0-9|\.]+/ /g'|sed -r 's/([0-9|\.]+)/"\1", /g'`
    NODES_HOST=`printf '%s' "$NODES_HOST"|sed -r "s/\"$SERVER_IP\"(, )?//"|sed -r 's/(,|\s)+$//'`
    NODES_NUM=$(( (`printf '%s' "$NODES_HOST"|grep -o ','|wc -m`+1)/2+1 ))
    # 写集群标识
    echo '写集群标识'
    echo '所有集群节点：'$NODES_HOST
    echo '集群节点数：'$NODES_NUM
    sed -i -r "s/^#?(cluster\.name:).*$/\1 $CLUSTER_NAME/" ./config/elasticsearch.yml
    sed -i -r "s/^#?(node\.name:).*$/\1 $NODE_NAME/" ./config/elasticsearch.yml
    # 写节点类型
    echo '写节点类型'
    SET_LINEON=`grep -noP '^node.name:' ./config/elasticsearch.yml|grep -oP '^\d+'`
    if [ -n "$SET_LINEON" ];then
        ((SET_LINEON++))
        sed -i "${SET_LINEON}i node.data: $NODE_DATA_VALUE" ./config/elasticsearch.yml
        sed -i "${SET_LINEON}i node.master: $NODE_MASTER_VALUE" ./config/elasticsearch.yml
    fi
    echo '写集群连接及限制'
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

# 启动服务
echo 'sudo -u elasticsearch ./bin/elasticsearch -d'
 sudo -u elasticsearch ./bin/elasticsearch -d

# 安装 kibana
if [ "$ARGV_tool" = 'kibana' ];then
    # 获取对应版本
    if if_version $ELASTICSEARCH_VERSION '>=' '8.0.0'; then
        # 8.0以上的版本
        TAR_FILE_NAME="-alpha2"
    else
        # 8.0以下的版本
        TAR_FILE_NAME="-linux-$LINUX_BIT"
    fi
    download_software https://artifacts.elastic.co/downloads/kibana/kibana-$ELASTICSEARCH_VERSION$TAR_FILE_NAME.tar.gz kibana-$ELASTICSEARCH_VERSION$TAR_FILE_NAME
    mkdirs $INSTALL_BASE_PATH/kibana/$ELASTICSEARCH_VERSION
    echo '复制所有文件到：'$INSTALL_BASE_PATH/kibana/$ELASTICSEARCH_VERSION
    cp -R ./* $INSTALL_BASE_PATH/kibana/$ELASTICSEARCH_VERSION
    cd $INSTALL_BASE_PATH/kibana/$ELASTICSEARCH_VERSION
    # 创建用户
    add_user kibana
    chown -R kibana:kibana ./*
    # 启动kibana
    echo 'nohup sudo -u kibana bin/kibana & 2>&1 >/dev/null'
    nohup sudo -u kibana bin/kibana & 2>&1 >/dev/null
    echo "kibana 管理地址：http://$SERVER_IP:5601"
fi

echo "安装成功：elasticsearch-$ELASTICSEARCH_VERSION"
