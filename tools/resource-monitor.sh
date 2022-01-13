#!/bin/bash
# 资源监听工具，可以监听：CPU、内存、硬盘、进程、网络等
# 监听可以发送请求通过，或者短信通知
# 可以使用常驻或者单次
#
# 了解语法：
# bash resource-monitor.sh -h
#
# vmstat 命令文档：https://man7.org/linux/man-pages/man8/vmstat.8.html
# iostat 命令文档：https://www.freebsd.org/cgi/man.cgi?iostat
#    sar 命令文档：http://linux.die.net/man/1/sar
#

# 参数信息配置
SHELL_RUN_DESCRIPTION='监听系统常规硬件资源信息'
SHELL_RUN_HELP='
此脚本只用监听系统常规硬件资源信息，可以通过脚本监听做一些报警功能。
可以放到定时器中执行，但必需指定持久监听否则。
各数据主要来源命令：ps、free、netstat、iostat、sar、df、lsblk

监听各资源名有：
    CPU（CPU）、物理内存（MEM）、虚拟内存（SWAP）、磁盘分区（PART）、
    进程（PROC）、网络（NET）、网卡（NETC）
CPU专用信息名：
    use         CPU总使用量占比
    user        用户进程CPU使用量占比
    system      内核进程CPU使用量占比
    wait        IO等待占比
    free        CPU空闲占比
    interrupt   每秒中断数，包括时钟中断占比
    switch      每秒上下文切换占比
内存专用信息名：
    use         内存使用量占比
    free        内存剩余量占比
    total       内存总量 KB
磁盘分区专用信息名：
    use         分区使用量
    free        分区剩余量
    total       分区总量
    write       分区写入速度 KB
    read        分区读取速度 KB
进程专用信息名：
    total       总进程数
    user.name   指定用户名进程数，name 替换为对应的用户名
网络专用信息名：
    total       总连接数
    CLOSED      套接字没有被使用。
    ESTABLISED  已经建立连接的状态。
    SYN_SENT    SYN 发起包，就是主动发起连接的数据包。
    SYN_RECV    接收到主动连接的数据包。
    FIN_WAIT1   正在中断的连接。
    FIN_WAIT2   已经中断的连接，但是正在等待对方主机进行确认。
    LISTEN      监听状态，只有 TCP 协议需要监听，而 UDP 协议不需要监听。
    CLOSING     等待远程TCP对连接中断的确认。
    TIME_WAIT   连接已经中断，但是套接字依然在网络中等待结束。
    LAST_ACK    等待原来发向远程TCP的连接中断请求的确认。
网卡信息名：
    rxpck       每秒钟接受的数据包
    txpck       每秒钟发送的数据包
    rxKB        每秒钟接受的数据包大小 KB
    txKB        每秒钟发送的数据包大小 KB
    rxcmp       每秒钟接受的压缩数据包
    txcmp       每秒钟发送的压缩包
    rxmcst      每秒钟接收的多播数据包   
    rxerr       每秒钟接收到的损坏的数据包
    txerr       每秒钟发送的数据包错误数
    coll        当发送数据包时候，每秒钟发生的冲撞（collisions）数
                这个是在半双工模式下才有
    rxdrop      当由于缓冲区满的时候，网卡设备接收端每秒钟丢掉的网络包的数目
    txdrop      当由于缓冲区满的时候，网络设备发送端每秒钟丢掉的网络包的数目
    txcarr      当发送数据包的时候，每秒钟载波错误发生的次数
    rxfram      在接收数据包的时候，每秒钟发生的帧对其错误的次数
    rxfifo      在接收数据包的时候，每秒钟缓冲区溢出的错误发生的次数
    txfifo      在发送数据包 的时候，每秒钟缓冲区溢出的错误发生的次数
'
DEFINE_TOOL_PARAMS='
[-d, --debug]调试模式，将输出相关信息用于调试
[-f, --conf="etc/resource-monitor.conf", {required|file}]监听配置文件，相对脚本根目录
#配置文件格式：（块不分先后）
#   [condition]
#   别名=资源名:资源路径:时长(报警规则)
#   [msg]
#   别名=报警内容
#   [exec]
#   别名=报警调用命令
#   别名是对应各块的标识，不限制重名，所的重名均有效
[-l, --loop-time=0, {required|int:0}]循环监听时长，以秒为单位，大于0有效定时。
#定时器中不建议使用此参数。
[--cache-file="temp/.resource-monitor.cache", {required}] 持续数据缓存文件，主要用来记录异常的开始时间，用来判断异常时长。
#多个进程同时执行时建议指定不同的缓存文件以免干扰
'
source "$(cd "$(dirname "${BASH_SOURCE[0]}")"; pwd)"/../includes/tool.sh || exit
# 解析各资源数据
# @command parse_resources
# return 0|1
parse_resources(){
    local INFOS ITEM
    # 获取内存信息
    debug_show "获取CPU/内存/系统/网络信息"
    while read ITEM; do
        INFOS=($ITEM)
        if [ ${INFOS[0]} = 'Mem:' ];then
            declare -l MEM_total=${INFOS[1]} MEM_use=$((${INFOS[2]} * 100 / ${INFOS[1]})) MEM_free=$((${INFOS[3]} * 100 / ${INFOS[1]})) # 物理内存信息
        elif [ ${INFOS[0]} = 'Swap:' ];then
            declare -l SWAP_total=${INFOS[1]} SWAP_use=$((${INFOS[2]} * 100 / ${INFOS[1]})) SWAP_free=$((${INFOS[3]} * 100 / ${INFOS[1]})) # 物理内存信息
        fi
    done <<EOF
`free -k|awk 'NR>1 {print $1,$2,$3,$4}'`
EOF
    # 获取CPU信息  $5/($2+$3+$4+$5+$6+$7+$8+$9+$10+$11)
    INFOS=(`cat /proc/stat |grep -P '^cpu '|grep -oP '(\d+\s*)+'`)
    if (( ${#INFOS[@]} > 0 ));then
        ITEM=$(( `echo "${INFOS[@]}"|sed 's/ /+/g'` ))
        declare -l CPU_user=$(( (${INFOS[0]}+${INFOS[1]})*100/ITEM )) CPU_system=$(( ${INFOS[2]}*100/ITEM )) CPU_free=$(( ${INFOS[3]}*100/ITEM )) CPU_wait=$(( ${INFOS[4]}*100/ITEM )) # cpu信息
        declare -l CPU_interrupt=$(( ${INFOS[5]}*100/ITEM )) CPU_switch=$(( ${INFOS[6]}*100/ITEM )) # cpu信息
        declare -l CPU_use=$(( (ITEM - ${INFOS[3]})*100/ITEM )) # cpu信息
    fi
    # 获取进程信息
    declare -l PROC_total=0  # 进程信息
    while read ITEM; do
        INFOS=($ITEM)
        PROC_total=$(($PROC_total + ${INFOS[0]}))
        declare -l PROC_user_${INFOS[1]}=${INFOS[0]}  # 进程信息
    done <<EOF
`ps aux|awk 'NR>1 {print $1}'|sort|grep -oP '\w+'|uniq -c`
EOF
    # 获取网络信息
    declare -l NET_total=0  # 网络信息
    while read ITEM; do
        INFOS=($ITEM)
        NET_total=$(($NET_total + ${INFOS[0]}))
        declare -l NET_${INFOS[1]}=${INFOS[0]}  # 网络信息
    done <<EOF
`netstat -ntlp|awk 'NR>1 {print $6}'|sort|uniq -c`
EOF
    # 处理单一资源
    resources_warn '' CPU MEM SWAP PROC NET
    parse_part_resources # 处理分区
    parse_netc_resources # 处理网卡
}
# 解析磁盘分区数据
# @command parse_part_resources
# return 0|1
parse_part_resources(){
    # 获取分区信息
    debug_show "开始获取分区信息"
    local ITEM INFOS=()
    while read ITEM; do
        INFOS=(`df_awk -k $ITEM|tail -n 1`)
        declare -l PART_total=${INFOS[1]} PART_use=$((${INFOS[2]} * 100 / ${INFOS[1]})) PART_free=$((${INFOS[3]} * 100 / ${INFOS[1]})) # 分区信息
        INFOS=(`iostat -k $ITEM|grep -iP '[\w-]+(\s+[\d\.]+)+$'`)
        declare -l PART_write=`printf '%.0f' ${INFOS[2]}` PART_read=`printf '%.0f' ${INFOS[3]}` # 分区IO信息，此处有小数
        # 分区是多个，只能每个单独运行
        resources_warn $ITEM PART
    done <<EOF
`lsblk -bnal|awk '$6=="part"{print "/dev/"$1}'`
EOF
}
# 解析网卡数据
# @command parse_netc_resources
# return 0|1
parse_netc_resources(){
    # 网卡信息
    debug_show "开始获取网卡信息"
    local ITEM INDEX TEMP NAMES=() INFOS=()
    while read ITEM; do
        if [ -z "$ITEM" ];then
            continue
        fi
        TEMP=($ITEM)
        if [ ${TEMP[0]} = 'IFACE' ];then
            if ((${#NAMES[@]} > 0));then
                TEMP[0]=''
                NAMES=(${NAMES[@]} ${TEMP[@]//\/*/})
            else
                NAMES=(${TEMP[@]//\/*/})
            fi
            continue
        fi
        for ((INDEX=0;INDEX<${#INFOS[@]};INDEX++)); do
            if [ "${TEMP[0]}" == "${INFOS[$INDEX]%% *}" ];then
                INFOS[$INDEX]="${INFOS[$INDEX]} ${TEMP[@]:1}"
                continue 2
            fi
        done
        INFOS[${#INFOS[@]}]=${TEMP[@]}
    done <<EOF
`sar -n DEV,EDEV 1 1|awk 'BEGIN{count=0}$2 == "IFACE"{count++}count >0 && count < 3 && $1{$1=""; print}'`
EOF
    for ((INDEX=0;INDEX<${#INFOS[@]};INDEX++)); do
        TEMP=(${INFOS[$INDEX]})
        for ((ITEM=1;ITEM<${#NAMES[@]};ITEM++)); do
            declare -l NETC_${NAMES[$ITEM]//*%/}=`printf '%.0f' ${TEMP[$ITEM]}` # 网卡信息
        done
        # 网卡是多个，需要每个独立运行
        resources_warn ${TEMP[0]} NETC
    done
}
# 存在选项
# @command in_options $dist $options [...]
# @param $dist          源选项
# @param $options       选项集
# return 0|1
in_options(){
    if (( $# < 2));then
        return 0
    fi
    local INDEX
    for ((INDEX=2;INDEX<=$#;INDEX++));do
        if [ "${@:$INDEX:1}" = "$1" ];then
            return 0
        fi
    done
    return 1
}
# 资源数据报警处理
# @command resources_warn $path $name [...]
# @param $path      要处理的资源路径
# @param $name      要处理的资源名集
# return 0|1
resources_warn(){
    local INDEX MAX_INDEX _AS WARN_NAME WARN_TIME WARN_COND WARN_PATH=$1 ONLY_WARN=${@:2}
    if [ "$ARGV_debug" = '1' ];then
        info_msg "资源：${@:2} 可用变量集："
        declare -l|grep -oP '[A-Z]+_.*$'
    fi
    each_conf trigger_warn condition
}
# 触发报警
# @command trigger_warn $as
# @param $as            触发别名
#                                   $item_name      区块内项名
#                                   $item_value     区块内项值
# return 0|1
trigger_warn(){
    local WARN_RESOURCE=${2%%:*} 
    if ! in_options $WARN_RESOURCE $ONLY_WARN;then
        return 1
    fi
    # 提取必要数据
    local WARN_PATH=${2#*:} WARN_TIMER WARN_TIME WARN_COND WARN_MSG WARN_EXEC WARN_STATUS='0'
    [ -z "$WARN_PATH" ] && debug_show "condition 区块 $1 不能匹配报警路径、时长、条件" && return 1
    WARN_TIME=${WARN_PATH#*:}
    [ -z "$WARN_TIME" ] && debug_show "condition 区块 $1 不能匹配报警时长、条件" &&  return 1
    WARN_PATH=${WARN_PATH%%:*}
    WARN_COND=${WARN_TIME#*(}
    WARN_COND=${WARN_COND%)*}
    [ -z "$WARN_COND" ] && debug_show "condition 区块 $1 没有匹配到报警条件" && return 1
    WARN_TIME=${WARN_TIME%%(*}
    if ( [ $(( $WARN_COND )) != '0' ] ) 2>/dev/null;then
        if ! persist_warn "$WARN_PATH($WARN_COND)" WARN_TIMER "$WARN_TIME";then
            debug_show "资源：$WARN_RESOURCE ，资源路径：$WARN_PATH ，持续时长：$WARN_TIMER ，条件表达式：$WARN_COND ，触发报警时长启动处理"
            WARN_STATUS='1'
        else
            debug_show "资源：$WARN_RESOURCE ，资源路径：$WARN_PATH ，持续时长：$WARN_TIMER ，条件表达式：$WARN_COND ，触发报警处理"
            WARN_STATUS='2'
        fi
    else
        if persist_warn "$WARN_PATH($WARN_COND)";then
            debug_show "资源：$WARN_RESOURCE ，资源路径：$WARN_PATH ，条件表达式：$WARN_COND ，报警释放处理"
            WARN_STATUS='-1'
        else
            debug_show "资源：$WARN_RESOURCE ，资源路径：$WARN_PATH ，条件表达式：$WARN_COND ，资源使用正常处理"
        fi
    fi
    local ITEM_KEY ITEM_NAME ITEM_VALUE ITEMS=("$1:$WARN_STATUS" "$1:*")
    if [ "$WARN_STATUS" = '2' ];then
        ITEMS[${#ITEMS[@]}]="$1"
    fi
    for ITEM_NAME in msg:WARN_MSG exec:WARN_EXEC;do
        for ((ITEM_KEY=0;ITEM_KEY<${#ITEMS[@]};ITEM_KEY++));do
            if get_conf ITEM_VALUE ${ITEM_NAME%%:*} "${ITEMS[$ITEM_KEY]}";then
                ITEM_VALUE=$(printf '%s' "$ITEM_VALUE"|sed -r 's/([\\"])/\\\1/g')
                eval "${ITEM_NAME#*:}=\"$ITEM_VALUE\""
                break
            fi
        done
    done
    [ -n "$WARN_MSG" ] && warn_msg "$WARN_MSG"
    [ -n "$WARN_EXEC" ] && eval "$WARN_EXEC"
}
# 持续处理
# @command persist_warn $warn $time_name $time_str
# @param $warn          报警规则
# @param $time_name     持续时长写入变量名
# @param $time_str      持续时长格式串
# return 0|1
persist_warn(){
    local NAME
    make_conf_key NAME "$1"
    if [ -z "$3" ];then
        # 删除匹配行
        grep -qP "^$NAME=.*" $ARGV_cache_file && sed -i -r "/^$NAME=.*/d" $ARGV_cache_file
        return $?
    fi
    local CURR_TIME=`date "+%s"` PREV_TIME=`grep "$NAME=" $ARGV_cache_file|tail -n 1|awk -F '=' '{print $2}'`
    if [ -z "$PREV_TIME" ];then
        debug_show "开始触发报警，记录时间：`date -d @$CURR_TIME '+%Y-%m-%d %H:%M:%S'`"
        # 写异常节点
        echo "$NAME=$CURR_TIME" >> $ARGV_cache_file
        return 1
    else
        local DIFF_TIME=$((`echo "$3"|sed -e 's/i/*60+/g' -e 's/h/*3600+/g' -e 's/d/*86400+/g'|sed 's/+$//'`))
        debug_show "初始触发报警时间：`date -d @$PREV_TIME '+%Y-%m-%d %H:%M:%S'`，持续时间要求：$DIFF_TIME 秒，当前时间：`date -d @$CURR_TIME '+%Y-%m-%d %H:%M:%S'`"
        duration_format $2 $((CURR_TIME - PREV_TIME))
        return $((DIFF_TIME > CURR_TIME - PREV_TIME))
    fi
}
# 时长格式化
# @command date_format $time_name $time
# @param $time_name     时长写入变量名
# @param $time          时间秒数
# return 0|1
duration_format(){
    local _TIME_STR_='' _TIME_=${2-0}
    while (($_TIME_ >= 60));do
        if (($_TIME_ > 86400));then
            _TIME_STR_=${_TIME_STR_}$(($_TIME_ / 86400))'天'
            _TIME_=$(($_TIME_ % 86400))
        elif (($_TIME_ > 3600));then
            _TIME_STR_=${_TIME_STR_}$(($_TIME_ / 3600))'小时'
            _TIME_=$(($_TIME_ % 3600))
        elif (($_TIME_ > 60));then
            _TIME_STR_=${_TIME_STR_}$(($_TIME_ / 60))'分钟'
            _TIME_=$(($_TIME_ % 60))
        fi
    done
    eval "$1=\$_TIME_STR_"
}
# 调试输出
# @command debug_show $msg [...]
# @param $msg       调试要输出的信息集
# return 0|1
debug_show(){
    if [ "$ARGV_debug" = '1' ];then
        info_msg "$@"
        printf '[debug] 请回车继续：'
        read
    fi
}
# 配置文件解析
parse_conf $ARGV_conf condition msg exec
# 必要命令判断
if ! if_command sar || ! if_command iostat;then
    packge_manager_run install sysstat
    if [ -e '/etc/default/sysstat' ];then
        sed -i -r 's/^ENABLED="false"/ENABLED="true"/' /etc/default/sysstat
        service sysstat restart
    fi
fi
# 提取缓存文件
safe_realpath ARGV_cache_file
if [ ! -e "$ARGV_cache_file" ] && ! touch "$ARGV_cache_file";then
    error_exit "--cache-file 缓存文件无效：$ARGV_cache_file"
fi

# 执行监听
while true;do
    parse_resources
    wait
    if (( ARGV_loop_time > 0 ));then
        sleep $ARGV_loop_time
    else
        break
    fi
done
