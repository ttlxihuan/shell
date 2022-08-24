#!/bin/bash
# linux系统默认对程序可打开连接数有安全限制（由操作系统内核处理），超过连接限制将无法再创建新连接。
# 一般服务类软件需要支持更多连接时就必需修改系统内核连接数限制相关参数，否则仅修改了服务软件的连接个数是无效的。
# 此脚本将修改配置进行打包整合，可方便增加指定用户组最大连接数据限制，同时进行一些相关优化调整。
# 特别注意：
#   单系统连接数并不是允许无限个，连接信息由远端IP和端口号+本地地址和端口号组成，单个占用内存空间很小，
#   理论上内存越大可连接个数越多（超出内存范围可能会增加内存切换开销严重影响性能）。
#   内核在2.6.25之前是固定内核写死的 2**20 = 1048576 即单进程最多连接数100万多，超过配置无效并影响使用。
#   内核在2.6.25之后通过/proc/sys/fs/nr_open限制（默认是1048576），通过修改/ect/sysct.conf的fs.nr_open值然后运行sysctl -p生效，一般没有特殊情况不建议修改最大连接数
#   系统一般默认单进程最大连接数为 1024，所有要突破最大连接数就必需修改相关配置，同时还要调整连接状态和数据处理相关配置

# 参数信息配置
SHELL_RUN_DESCRIPTION='linux系统连接限制优化'
SHELL_RUN_HELP="
此脚本用来快速修改进程最大可连接数，并附带优化其它配置。
脚本默认最大可连接数为1048576即100万多，超出此配置需要手动修改。
内核在2.6.25之后/proc/sys/fs/nr_open限制为脚本最大允许修改连接数。
并不是连接数开的越多越好，需要结合实际连接处理状态。
当同时活跃并通信的连接数超出服务器可靠性能范围则不建议配置过高最大连接数。
"
# 提取最大连接数据限制和默认最大连接数
MAX_NOFILE_LIMIT=1048576
DEFAULT_SET_NOFILE=1024000
if [ -e /proc/sys/fs/nr_open ];then
    MAX_NOFILE_LIMIT=$(cat /proc/sys/fs/nr_open)
fi
if (( DEFAULT_SET_NOFILE > MAX_NOFILE_LIMIT ));then
    DEFAULT_SET_NOFILE=MAX_NOFILE_LIMIT
fi
DEFINE_RUN_PARAMS="
[user='*', {required}]开放指定用户组
#默认为通配所有用户组
#临时配置时无效
[-T, --type-nofile='temp', {required|in:temp,login,conf}]指定最大连接数据修改类型
# temp  临时配置，仅在当前会员下有效
# login 仅登录自动生效（不需要重启）
#       仅针对root账号有效，其它账户权限不够
# conf  仅写全局配置，必需重启才生效
[-S, --set-nofile=$DEFAULT_SET_NOFILE, {required|int:1024,$MAX_NOFILE_LIMIT}]开放最大连接数
#最小1024，最大$MAX_NOFILE_LIMIT
[-P, --set-nproc=0, {required|int:-1}]指定用户允许启动最大进程数
#指定=-1的值即不限制
#指定=0的值即路过配置
#指定>0的值即为限制数量
[-N, --skip-net]跳过网络配置参数优化
#网络配置优化有助于资源回收和限制
#网络配置并不能适用所有场景，最优值还需要实践调整
#脚本仅提供通用优化参数
"
source "$(cd "$(dirname "${BASH_SOURCE[0]}")"; pwd)"/../includes/tool.sh || exit

if [ "$ARGU_user" != '*' ] && ! has_user "$ARGU_user";then
    error_exit "用户 $ARGU_user 不存在"
fi

SECURITY_USERNAME=$ARGU_user
addc_slashes SECURITY_USERNAME '\*|\.'

case "$ARGV_type_nofile" in
    login)
        info_msg "修改 profile 用户($ARGU_user)最大连接数为：${ARGV_set_nofile}"
        if [ "$ARGU_user" = '*' ];then
            edit_conf /etc/profile "#*\s*(ulimit\s+)-[a-zA-Z0-9]+\s+.*" "ulimit -HSn ${ARGV_set_nofile}"
        else
            if [ "$ARGU_user" = 'root' ];then
                PROFILE_CONF=$(cd ~;pwd)/.bash_profile
                if [ -e "$PROFILE_CONF" ];then
                    edit_conf "$PROFILE_CONF" "#*\s*(ulimit\s+)-[a-zA-Z0-9]+\s+.*" "ulimit -HSn ${ARGV_set_nofile}"
                else
                    error_exit "$ARGU_user 用户未创建home目录或没有创建 $PROFILE_CONF 文件"
                fi
            else
                warn_msg "非root账户暂不能指定最大连接数";
            fi
        fi
    ;;
    temp)
        info_msg "修改临时最大连接数为：${ARGV_set_nofile}"
        ulimit -HSn ${ARGV_set_nofile}
    ;;
    conf)
        info_msg "修改 /etc/security/limits.conf 全局配置最大连接数为：${ARGV_set_nofile}"
        # 修改 /etc/security/limits.conf 配置项
        # 配置文件不存在就自动创建
        if [ ! -e /etc/security/limits.conf ];then
            # 修改配置
            echo '# /etc/security/limits.conf' > /etc/security/limits.conf
        fi
        # 要使用配置生效必需重启服务器
        # 添加soft nofile限制
        edit_conf /etc/security/limits.conf "#*\s*(${SECURITY_USERNAME}\s+soft\s+nofile)\s+.*" "${ARGU_user} soft nofile ${ARGV_set_nofile}"
        # 添加hard nofile限制
        edit_conf /etc/security/limits.conf "#*\s*(${SECURITY_USERNAME}\s+hard\s+nofile)\s+.*" "${ARGU_user} hard nofile ${ARGV_set_nofile}"
    ;;
esac

# 修改 /etc/security/limits.d/*-nproc.conf 配置项，指定用户可打开进程数
if [ "$ARGV_set_nproc" != '0' -a -d '/etc/security/limits.d/' ];then
    if [ "$ARGV_set_nproc" = '-1' ];then
        ARGV_set_nproc='unlimited'
    fi
    LIMITS_CONFIG=$(find /etc/security/limits.d/ -name '*-nproc.conf'|tail -n 1)
    if [ -n "$LIMITS_CONFIG" ];then
        info_msg "修改 $LIMITS_CONFIG 最大进程数为：${ARGV_set_nproc}"
        edit_conf $LIMITS_CONFIG "#*\s*(${SECURITY_USERNAME}\s+soft\s+nproc)\s+.*" "${ARGU_user} soft nproc ${ARGV_set_nproc}"
    fi
fi

# 修改 /etc/sysctl.conf 配置项
if [ -z "$ARGV_skip_net" ];then
    info_msg "优化修改网络相关配置"
    # 指定网络连接TIME_WAIT状态最大数量，超过就会立即清除。
    # TIME_WAIT状态是连接时产生的，回收有助于释放资源，回收过频会释放有效连接导致尝试连接次数增加反而增加系统开销
    edit_conf /etc/sysctl.conf "#*\s*(net\.ipv4\.tcp_max_tw_buckets\s*=).*" "net.ipv4.tcp_max_tw_buckets = 20000"

    # 指定网络连接LISTEN状态最大数量，超过就会被拒绝请求（全局共享参数，默认128）
    # 网络连接状态是LISTEN的最大数量，从LISTEN转为ESTABLISHED后就可以传送数据，也可以理解为socket的accept处理阶段
    # 超过此配置将无法接收请求，多余的请求会被拒绝
    edit_conf /etc/sysctl.conf "#*\s*(net\.core\.somaxconn\s*=).*"             "net.core.somaxconn = 65535"

    # 指定网络连接SYN_REVD状态最大数量，超过就会被拒绝请求
    edit_conf /etc/sysctl.conf "#*\s*(net\.ipv4\.tcp_max_syn_backlog\s*=).*"   "net.ipv4.tcp_max_syn_backlog = 262144"

    # 指定允许发送到队列的数据包最大数量（即包数）
    # 可以理解为接收网络数据包队列长度，超出将丢弃数据包
    edit_conf /etc/sysctl.conf "#*\s*(net\.core\.netdev_max_backlog\s*=).*"    "net.core.netdev_max_backlog = 30000"

    if if_version "$(uname -r|grep -oP '^\d+(\.\d+)+')" '<' '4.12.0';then
        # Linux从4.12内核开始移除了 tcp_tw_recycle 配置
        # 指定是否快速回收TIME_WAIT状态连接，一般选择关闭，快速回收可能导致正常连接被中断
        edit_conf /etc/sysctl.conf "#*\s*(net\.ipv4\.tcp_tw_recycle\s*=).*"    "net.ipv4.tcp_tw_recycle = 0"
    fi

    # 所有进程总共可以打开的文件数量
    # 文件数量也包含连接
    edit_conf /etc/sysctl.conf "#*\s*(fs\.file-max\s*=).*"                     "fs.file-max = 6815744"

    if has_iptables_run;then
        # 防火墙跟踪表的大小，没有开防火墙会提示错误
        edit_conf /etc/sysctl.conf "#*\s*(net\.netfilter\.nf_conntrack_max\s*=).*" "net.netfilter.nf_conntrack_max = 2621440"
    fi
    # 生效配置
    info_msg "生效优化配置"
    sysctl -p
fi
