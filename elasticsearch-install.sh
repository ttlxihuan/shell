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
# 加载基本处理
source basic.sh
# 获取工作目录
INSTALL_NAME='elasticsearch'
# 获取版本配置
VERSION_URL="https://www.elastic.co/downloads/elasticsearch"
VERSION_MATCH='elasticsearch-\d+\.\d+\.\d+'
VERSION_RULE='\d+\.\d+\.\d+'
# 初始化安装
init_install ELASTICSEARCH_VERSION
# ************** 安装 ******************
# 下载elasticsearch包
# 到7.0以上包名有变动
if if_version $ELASTICSEARCH_VERSION '>' '7.0.0'; then
    # 7.0以上的版本
    TAR_FILE_NAME="elasticsearch-$ELASTICSEARCH_VERSION-linux-`uname -a|grep -P 'el\d+\.x\d+_\d+' -o|grep -P 'x\d+_\d+' -o`.tar.gz"
else
    TAR_FILE_NAME="elasticsearch-$ELASTICSEARCH_VERSION.tar.gz"
fi
download_software https://artifacts.elastic.co/downloads/elasticsearch/$TAR_FILE_NAME
# 复制安装包
mkdir -p $INSTALL_PATH/$ELASTICSEARCH_VERSION
cp -R ./* $INSTALL_PATH/$ELASTICSEARCH_VERSION
cd $INSTALL_PATH/$ELASTICSEARCH_VERSION
# 安装java
tools_install java

# 默认数据目录判断是否存在
if [ ! -d "./data" ]; then
    mkdir data
fi

# 创建用户
add_user elasticsearch
chown -R elasticsearch:elasticsearch ./*

# 启动服务
sudo -u elasticsearch ./bin/elasticsearch -d

echo "install elasticsearch-$ELASTICSEARCH_VERSION success!"
