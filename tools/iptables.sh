#!/bin/bash
#
# 说明：本脚本用于动态更新iptables规则，主要用于更新指定动态域名下的IP在这里的规则。
# 使用场景主要是：在非静态IP访问时在路由器中配置动态域名，然后在此脚本的配置文件中增加上对应的配置，当动态域名的IP变动时就会自动更新，摒弃使用VPN代理的开销
# 脚本需要使用定时器进行更新，定时时长建议在5分钟左右，同一个静态IP建议配置多个不同公司的动态域名，比如：花生壳、Tplink 等
# 每次进来都会重启下iptables用于更新规则，如果不需要动态规则的需要永久保存，否则容易被清除导致无法使用
#
# yum install iptables-services  如果是CentOS.7 需要安装服务启动器并关闭默认的 firewalld 防火墙 systemctl stop firewalld
#
# iptables 中文使用文档 https://www.frozentux.net/iptables-tutorial/cn/iptables-tutorial-cn-1.1.19.html
#
#
#
# ========================================================
# 【开启日志记录】
# iptables 日志是通过系统日志工具（CentOS.6以下 syslog ，CentOS.6以上 rsyslog）来完成的。需要配置 syslog.conf 或 rsyslog.conf 文件增加以下内容：
#    kern.warning      /var/log/iptables.log
#
# 然后重启服务：
#     service syslog restart   或  systemctl restart rsyslog
#
# 插入iptables日志记录
#     iptables -I INPUT -j LOG --log-prefix "iptables" --log-level warning
#
# 参数说明：
#  -I INPUT 输入类型（必需使用-I插入方式这样规则才在最上面，如果使用-A则追加到最下面会被上面的命令给截取并跳过从而导致日志收集失败，如果没有其它规则那-I或-A结果一样）
#  -j LOG 收集日志操作
#  --log-prefix "iptables"  日志内容增加前缀（此前缀会放在日期之后）
#  --log-level warning  日志级别，指定为warning与配置的kern.warning一样即可
#
# 注意：这种日志只是收集并不能收集防火墙的最终处理结果，由于数据量比较大，所以一般必要性不大，上面的命令是收集所有的输入请求，如果需要指定IP或端口则再单独添加
# 删除收集日志规则命令：
#     iptables -D INPUT -j LOG --log-prefix "iptables" --log-level warning
# ========================================================
#
#
#
#
# ========================================================
# 【排查防火墙异常丢包导致部分连接不上】
# 1、查看防火墙连接跟踪表nf_conntrack溢出，Linux为每个经过内核网络栈的数据包，生成一个新的连接记录项，当服务器处理的连接过多时，连接跟踪表被打满，服务器会丢弃新建连接的数据包。使用命令
#       dmesg|grep nf_conntrack
#    如果出现“nf_conntrack: table full, dropping packet”，说明服务器nf_conntrack表已经被打满。（需要开启日志功能）
#  查看当前最大跟踪连接数据命令：
#      cat /proc/sys/net/netfilter/nf_conntrack_max
#  查看当前跟踪连接数据命令：
#      cat /proc/sys/net/netfilter/nf_conntrack_count
#
#  设置跟踪连接参数命令：
#      sysctl -w net.netfilter.nf_conntrack_max=1048576
#      sysctl -w net.netfilter.nf_conntrack_buckets=262144
#      sysctl -w net.netfilter.nf_conntrack_tcp_timeout_established=3600
#
#
# ========================================================
#
#
#
#
#
# 网络状态说明：https://blog.csdn.net/qq_28098067/article/details/80811938
# 服务器网络时长会超时未响应排查：https://www.sdnlab.com/17530.html
#
#
#
#

EDIT_IPTABLES_CONF=".iptables.conf";
EDIT_IPTABLES_CONF_TMP=".tmp_iptables.conf";
DOMAIN_IPS="";
CLIENT_IP="";
if [ -n "$1" ];then
    CONFIG_FILE=$1;
else
    CONFIG_FILE="iptables.conf";
    CURRENT_DIR=`echo "$0" | grep -P '(/?[^/]+/)+' -o`
    if [ ! -e "$CONFIG_FILE" ] && [ -e "$CURRENT_DIR$CONFIG_FILE" ]; then
        cd $CURRENT_DIR
    fi
fi

if [ ! -e "$CONFIG_FILE" ]; then
    echo "$CONFIG_FILE config file is not exists!";
    exit;
fi

echo "check iptables run status";
#开启服务
if [ -z "`systemctl --version 2>&1|grep "bash: systemctl:"`" ];then
    if [ -z "`service iptables status|grep 'not running'`" ];then
        echo "iptables service running";
    else
        echo "[warning] iptables service not running";
        exit 1;
    fi
else
    # 默认没有iptables.service服务可以自己安装 ，否则需要使用 systemctl stop firewalld 来处理
    # yum install iptables-services
    if [ -z "`systemctl status iptables|grep 'Active: inactive (dead)'`" ];then
        echo "iptables service running";
    else
        echo "[warning] iptables service not running";
        exit 1;
    fi
fi


#添加IP到配置文件中
add_client_iptables_conf(){
    if [ -n "`echo $1|grep -P '^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}$'`" ] || [ "$1" == "-1" ];then
        echo "$1 $2 $3 $4 insert" >> $EDIT_IPTABLES_CONF_TMP
    else
        #获取对应的IP地址
        get_ip_by_domain $1
        if [ -z "$CLIENT_IP" ];then
            echo "$1 not ping ip"
        else
            echo "$CLIENT_IP $2 $3 $4 insert" >> $EDIT_IPTABLES_CONF_TMP
        fi
    fi
}

# 通过域名获取IP
get_ip_by_domain(){
    local CACHE_IP=`echo -e "$DOMAIN_IPS"|grep -m 1 "^$1 "`;
    if [ -z "$CACHE_IP" ];then
        CLIENT_IP=`ping -c 1 -W 1 $1|grep -P "\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}" -o -m 1`
        DOMAIN_IPS="$DOMAIN_IPS\n$1 $CLIENT_IP"
        echo "ping $1 $CLIENT_IP"
    else
        CLIENT_IP=`echo "$CACHE_IP"|grep -oP "\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}$"`;
        echo "cache $1 $CLIENT_IP"
    fi
}


#判断文件是否存在
if [ ! -e $EDIT_IPTABLES_CONF ] ;then
    echo "# host   port   mac    switch" > $EDIT_IPTABLES_CONF
fi
if [ -e "$EDIT_IPTABLES_CONF_TMP" ];then
    echo 'update is runing'
    exit
fi
#生成临时配置文件
COMMENT_TEXT=`cat $EDIT_IPTABLES_CONF | grep -P "#.*"`
echo -e "$COMMENT_TEXT" > $EDIT_IPTABLES_CONF_TMP

#处理配置文件并添加规则
cat $CONFIG_FILE | while read LINE
do
    if [ -n "`echo $LINE|grep -P "^#.*$"`" ] || [ -n "`echo $LINE|grep -P "^[\t\n\s\r]*$"`" ] || [ -z "$LINE" ]; then
        continue;
    fi
    add_client_iptables_conf $LINE
done

#判断是否有不一样
CONFIG_DIFF=`diff $EDIT_IPTABLES_CONF_TMP $EDIT_IPTABLES_CONF`
if [ -n "$CONFIG_DIFF" ];then
    echo -e "$COMMENT_TEXT" > $EDIT_IPTABLES_CONF
    echo -e "$CONFIG_DIFF"|while read LINE
    do
        if [ "$LINE" == "---" ];then
            continue;
        fi
        if [ ${LINE:0:1} == '>' ]; then
            HANDLE_NAME='remove'
        elif [ ${LINE:0:1} == '<' ]; then
            HANDLE_NAME='insert'
        else
            continue;
        fi
        echo -e "${LINE:2}"|sed "s/[a-z]*$/$HANDLE_NAME/ig" >> $EDIT_IPTABLES_CONF
    done
    #处理变更的规则
    #编辑规则
    echo "edit iptables ruls";

    cat $EDIT_IPTABLES_CONF | while read LINE
    do
        if [ -n "$(echo $LINE|grep -P "^#.*$")" ] || [ -n "$(echo $LINE|grep -P "^[\t\n\s\r]*$")" ] || [ -z "$LINE" ]; then
            continue;
        fi
        #CONFIG=(${LINE//[:blank:]/});
        CONFIG=(`echo $LINE|grep -P "[\w\.\-]+" -o`);
        SET_IP="";
        SET_PORT="";
        SET_MAC="";
        SET_SWITCH="";
        SET_HANDLE="";
        # ip配置提取
        if [ -n "$(echo ${CONFIG[0]}|grep -P "^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}(/\d{1,2})?$")" ]; then #
            SET_IP=" -s ${CONFIG[0]}";
        elif [ "${CONFIG[0]}" != "-1" ]; then
            echo "ip config error ${CONFIG[0]}";
            continue;
        fi
        #port配置提取
        if [ -n "$(echo ${CONFIG[1]}|grep -P "^\d{1,4}(:\d{1,4})?$")" ]; then #
            SET_PORT=" --dport ${CONFIG[1]}";
        elif [ "${CONFIG[1]}" != "-1" ]; then
            echo "port config error ${CONFIG[1]}";
            continue;
        fi
        #max配置提取
        if [ -n "$(echo ${CONFIG[2]}|grep -P "^([a-z0-9A-Z]{2}-){5}[a-z0-9A-Z]{2}$")" ]; then #
            SET_MAC=" -m mac --mac-source ${CONFIG[2]}";
        elif [ "${CONFIG[2]}" != "-1" ]; then
            echo "mac config error ${CONFIG[2]}";
            continue;
        fi
        #switch配置提取
        if [ -n "$(echo ${CONFIG[3]}|grep -P "^(1|yes)$")" ]; then #
            SET_SWITCH=" -j ACCEPT";
        elif [ -n "$(echo ${CONFIG[3]}|grep -P "^(0|no)$")" ]; then #
            SET_SWITCH=" -j DROP";
        else
            echo "switch config error ${CONFIG[3]}";
            continue;
        fi
        #handle配置提取
        if [ -n "$(echo ${CONFIG[4]}|grep -P "^(remove)$")" ]; then #
            SET_HANDLE="-D";
        elif [ -n "$(echo ${CONFIG[4]}|grep -P "^(insert)$")" ]; then #
            SET_HANDLE="-I";
        elif [ -n "$(echo ${CONFIG[4]}|grep -P "^(add)$")" ]; then #
            SET_HANDLE="-A";
        else
            echo "remove config error ${CONFIG[4]}";
            continue;
        fi
        echo "iptables $SET_HANDLE INPUT -p tcp -m state --state NEW -m tcp$SET_IP$SET_PORT$SET_MAC$SET_SWITCH"
        iptables $SET_HANDLE INPUT -p tcp -m state --state NEW -m tcp$SET_IP$SET_PORT$SET_MAC$SET_SWITCH
    done

    #保存需要的规则
    cat $EDIT_IPTABLES_CONF_TMP > $EDIT_IPTABLES_CONF
fi

#删除临时文件
rm -f $EDIT_IPTABLES_CONF_TMP