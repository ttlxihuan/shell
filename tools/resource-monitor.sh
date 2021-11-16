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

# 解析命令参数
# 命令参数解析成功后，将写入参数名规则：ARGV_参数全名（横线转换为下划线，缩写选项使用标准选项代替，使用时注意参数名的大小写不变）
# @command parse_command_param
# return 1|0
parse_command_param() {
    # 解析匹配传入参数
    local NAME INDEX ITEM ARG_NAME ARG_NUM VALUE OPTIONS_TEMP NAME_TEMP VALUE_TEMP ARGUMENTS_INDEX=0 ARG_SIZE=${#CALL_INPUT_ARGVS[@]}
    for ((ARG_NUM=0; ARG_NUM < $ARG_SIZE; ARG_NUM++)); do
        ITEM=${CALL_INPUT_ARGVS[$ARG_NUM]}
        if [ -z "$ITEM" ];then
            continue
        fi
        NAME=''
        if printf '%s' "$ITEM"|grep -qiP '^((--[a-z0-9][\w\-]+(=.*)?)|(-[a-z0-9]))$'; then
            # 有参数的选项处理
            if printf '%s' "$ITEM"|grep -qiP '^--[a-z0-9][\w\-]+=.*';then
                NAME_TEMP=$(printf '%s' "$ITEM"|grep -oiP '^--[a-z0-9][\w\-]+')
                VALUE=$(printf '%s' "$ITEM"|sed -r "s/^[^=]+=//")
            else
                NAME_TEMP="$ITEM"
                VALUE=''
                for ((INDEX=0; INDEX < ${#OPTIONALS[@]}; INDEX++)); do
                    OPTIONS_TEMP=${OPTIONALS[$INDEX]}
                    if [ "$OPTIONS_TEMP" != "`printf '%s' "$OPTIONS_TEMP"|sed -r "s/$NAME_TEMP($|,)//"`" ];then
                        NAME=$(printf '%s' "$OPTIONS_TEMP"|sed -r "s/(-[A-Za-z0-9]\s*,\s*)?--//")
                        VALUE='1'
                        break
                    fi
                done
            fi
            if [ -z "$NAME" ];then
                for ((INDEX=0; INDEX < ${#OPTIONS[@]}; INDEX++)); do
                    OPTIONS_TEMP=${OPTIONS[$INDEX]}
                    if [ "$OPTIONS_TEMP" != "`printf '%s' "$OPTIONS_TEMP"|sed -r "s/$NAME_TEMP($|,)//"`" ];then
                        NAME=$(printf '%s' "$OPTIONS_TEMP"|sed -r "s/(-[A-Za-z0-9]\s*,\s*)?--//")
                        if [ -z "$VALUE" ] && printf '%s' "$NAME_TEMP"|grep -qiP '^-[a-z0-9]$';then
                            ((ARG_NUM++))
                            VALUE=${CALL_INPUT_ARGVS[$ARG_NUM]}
                        fi
                        if [ -z "$VALUE" ] && ! [[ $ITEM =~ = ]] && (($ARG_NUM >= $ARG_SIZE));then
                            error_exit "$NAME 必需指定一个值"
                        fi
                        break
                    fi
                done
            fi
            ARGUMENTS_INDEX=${#ARGUMENTS[@]}
        elif ((${#ARGUMENTS[@]} > 0 && $ARGUMENTS_INDEX < ${#ARGUMENTS[@]})); then
            NAME=${ARGUMENTS[$ARGUMENTS_INDEX]}
            VALUE="$ITEM"
            ((ARGUMENTS_INDEX+=1))
        fi
        if [ -z "$NAME" ];then
            echo "未知参数: "$ITEM
        else
            ARG_NAME="ARGV_"`printf '%s' "$NAME"|sed -r "s/^-{1,2}//"|sed "s/-/_/g"`
            eval "$ARG_NAME=\$VALUE"
        fi
    done
}
# 输出错误并退出
# @command error_exit $error_str
# @param $error_str     错误内容
# return 1
error_exit(){
    echo "[ERROR] $1"
    exit 1;
}
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
        INFOS=(`df -k $ITEM|tail -n 1`)
        declare -l PART_total=${INFOS[1]} PART_use=$((${INFOS[2]} * 100 / ${INFOS[1]})) PART_free=$((${INFOS[3]} * 100 / ${INFOS[1]})) # 分区信息
        INFOS=(`iostat -k $ITEM|grep -iP '[\w-]+(\s+[\d\.]+)+$'`)
        declare -l PART_write=`printf '%.0f' ${INFOS[2]}` PART_read=`printf '%.0f' ${INFOS[3]}` # 分区IO信息，此处有小数
        # 分区是多个，只能每个单独运行
        resources_warn $ITEM PART
    done <<EOF
`lsblk -bnapl|awk '$6=="part"{print $1}'`
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
        if [ "`eval echo \$$INDEX`" = "$1" ];then
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
    local INDEX MAX_INDEX _AS WARN_NAME WARN_TIME WARN_COND WARN_PATH=$1
    if [ "$ARGV_debug" = '1' ];then
        echo "资源：${@:2} 可用变量集："
        declare -l|grep -oP '[A-Z]+_.*$'
    fi
    for WARN_NAME in ${@:2}; do
        debug_show "${WARN_NAME} 报警处理开始"
        MAX_INDEX=$(eval echo \${#CONDITION_ITEMS_$WARN_NAME[@]})
        for ((INDEX=0;INDEX<MAX_INDEX;INDEX+=4));do
            if [ -n "$WARN_PATH" ] && ! in_options "$WARN_PATH" $(eval "echo \${CONDITION_ITEMS_$3[$((INDEX+1))]}|awk -F ',' '{print}'");then
                continue
            fi
            eval _AS=\${CONDITION_ITEMS_$WARN_NAME[$INDEX]}
            eval WARN_TIME=\${CONDITION_ITEMS_$WARN_NAME[$((INDEX+2))]}
            eval WARN_COND=\${CONDITION_ITEMS_$WARN_NAME[$((INDEX+3))]}
            echo "$WARN_COND"
            if [ $(( $WARN_COND )) != '0' ];then
                debug_show "资源名：$WARN_NAME ，资源路径：$WARN_PATH ，持续时长：$WARN_TIME ，条件表达式：$WARN_COND ，触发报警处理"
                if ! persist_warn WARN_TIME "$WARN_PATH($WARN_COND)" "$WARN_TIME";then
                    continue
                fi
            else
                debug_show "资源名：$WARN_NAME ，资源路径：$WARN_PATH ，持续时长：$WARN_TIME ，条件表达式：$WARN_COND ，释放报警处理"
                persist_warn WARN_TIME "$WARN_PATH($WARN_COND)"
                continue
            fi
            # 生成报警信息
            trigger_warn "$_AS"
        done
        debug_show "${WARN_NAME} 报警处理结束"
    done
}
# 触发报警
# @command trigger_warn $as
# @param $as            触发别名
# return 0|1
trigger_warn(){
    debug_show "触发报警：$1"
    local INDEX TEXT_STR MAX_INDEX=$(eval echo \${#MSG_ITEMS_$1[@]})
    for ((INDEX=0;INDEX<MAX_INDEX;INDEX++));do
        eval TEXT_STR=\${MSG_ITEMS_$1[$INDEX]}
        debug_show "报警消息："$TEXT_STR
        eval echo $TEXT_STR
    done
    MAX_INDEX=$(eval echo \${#EXEC_ITEMS_$1[@]})
    for ((INDEX=0;INDEX<MAX_INDEX;INDEX++));do
        eval TEXT_STR=\${EXEC_ITEMS_$1[$INDEX]}
        debug_show "报警命令："$TEXT_STR
        eval $TEXT_STR
    done
}
# 持续处理
# @command persist_warn $time_name $warn $time_str
# @param $time_name     持续时长写入变量名
# @param $warn          报警规则
# @param $time_str      持续时长格式串
# return 0|1
persist_warn(){
    local NAME=`printf '%s' "$2"|sed -r 's/\s+//g'|md5sum -t|awk '{print $1}'`
    if [ -z "$3" ];then
        # 删除匹配行
        sed -i -r "/^$NAME=.*/d" $ARGV_cache_file
        eval "$1=''"
        return 1
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
        duration_format $1 $((CURR_TIME - PREV_TIME))
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
        echo -e "$@"
        printf '[debug] 请回车继续：'
        read
    fi
}

# 解析配置文件
# @command parse_conf $file
# @param $file       要解析的配置文件
# return 0|1
parse_conf(){
    sed -i 's/\r//' $1
    local ITEM _ITEM LINES_NUM GET_LINES GET_CONTENTS _ALIAS_NAME _ALIAS_VALUE _NAME CONF_TAGS_LINE=$(grep -noP '^\s*\[[^\]]+\]' $1)
    for ITEM in condition msg exec;do
        LINES_NUM=(`echo -e "$CONF_TAGS_LINE"|grep -P "\s*\[\s*$ITEM\s*\]" -A 1|grep -oP '^\d+'`)
        if ((${#LINES_NUM[@]} >1));then
            GET_LINES=$((${LINES_NUM[0]}+1)),$((${LINES_NUM[1]}-1))p
        else
            GET_LINES=$((${LINES_NUM[0]}+1))',$p'
        fi
        GET_CONTENTS=$(sed -n $GET_LINES "$1"|grep -P '^\s*[^#=\s]+\s*=')
        debug_show "[$ITEM]\n$GET_CONTENTS"
        if [[ "$GET_CONTENTS" =~ ^[[:space:]]*$ ]];then
            continue
        fi
        # 整理数据，方便后面提取
        while read _ITEM;do
            if [[ "$_ITEM" =~ ^[[:space:]]*$ ]];then
                continue
            fi
            _ALIAS_NAME=$(printf '%s' "$_ITEM"|grep -oP '^\s*[^#=\s]+\s*='|grep -oP '[^#=\s]+'|md5sum -t|awk '{print $1}'|tr '[:lower:]' '[:upper:]')
            _ALIAS_VALUE=${_ITEM#*=}
            if [ "$ITEM" = 'condition' ];then
                while read _ITEM;do
                    if [[ "$_ITEM" =~ ^[[:space:]]*$ ]];then
                        continue
                    fi
                    _NAME=CONDITION_ITEMS_$(echo "$_ITEM"|grep -oP '(^|\W)\w+\s*:'|grep -oP '\w+')
                    eval "if [ -z \"\${#$_NAME[@]}\" ];then $_NAME=(); fi; $_NAME[\${#$_NAME[@]}]=\$_ALIAS_NAME"
                    eval "$_NAME[\${#$_NAME[@]}]=\$(echo \"\$_ITEM\"|grep -oP ':\s*([\w/\.,\s]+)?:'|head -n 1|grep -oP '[\w/\.,\s]+')"
                    eval "$_NAME[\${#$_NAME[@]}]=\$(echo \"\$_ITEM\"|grep -oP ':\s*([0-9]+[ihd])*\s*\('|head -n 1|grep -oP '([0-9]+[ihd])*')"
                    eval "$_NAME[\${#$_NAME[@]}]=\$(echo \"\$_ITEM\"|grep -oP '\(.*?\)\s*;'|sed -r 's/(^\(+|\)\s*;$)//g'|sed 's/\./_/g')"
                done <<EOF
`printf '%s' "$_ALIAS_VALUE"|grep -oP '(^|\W)(CPU|MEM|SWAP|PART|PROC|NET|NETC)\s*:\s*([\w/\.,\s]+)?:\s*([0-9]+[ihd])*\s*\(.*?\)\s*;'`
EOF
            else
                _NAME=$(echo $ITEM|tr '[:lower:]' '[:upper:]')_ITEMS_
                eval "if [ -z \"\${#$_NAME$_ALIAS_NAME[@]}\" ];then $_NAME$_ALIAS_NAME=(); fi; $_NAME$_ALIAS_NAME[\${#$_NAME$_ALIAS_NAME[@]}]=\$_ALIAS_VALUE"
            fi
        done <<EOF
`printf '%s' "$GET_CONTENTS"`
EOF
    done
    if [ "$ARGV_debug" = '1' ];then
        echo "配置解析数据集："
        declare -a|grep -oP '\s(CONDITION|MSG|EXEC)_ITEMS_\w+=.*$'
    fi
}
# 定义参数
ARGUMENTS=()
# 定义有值选项
OPTIONS=('-f, --warn-conf' '-l, --loop-time' '--cache-file')
# 定义无值选项
OPTIONALS=('-h,--help' '-d, --debug' '-i, --auto-install')
# 提取安装参数
CALL_INPUT_ARGVS=()
for ((INDEX=1;INDEX<=$#;INDEX++));do
    CALL_INPUT_ARGVS[${#CALL_INPUT_ARGVS[@]}]=${@:$INDEX:1}
done
unset INDEX
# 参数默认值
ARGV_warn_conf="resource-monitor.conf"
ARGV_cache_file=".resource-monitor.tmp"
# 解析参数
parse_command_param
if [ -n "$ARGV_help" ];then
    echo -e "Description:
    监听系统常规硬件资源信息
Usage:
    bash $0.sh [Options ...]

Options:
    -h, --help              显示脚本帮助信息
    -d, --debug             调试模式，将输出相关信息用于调试
    -i, --auto-install      自动安装依赖工具：sysstat
                            如果已经安装此参数无效，使用此参数需要在root账号下运行
    -f, --warn-conf [='$ARGV_warn_conf']
                            监听配置文件，方便使用更复杂的监听条件
                            配置文件格式：（块不分先后）
                                [condition]
                                别名=资源名:资源路径:时长(报警规则)
                                [msg]
                                别名=报警内容
                                [exec]
                                别名=报警调用命令
                            别名是对应各块的标识，不限制重名，所的重名均有效
    -l, --loop-time [=0]    循环监听时长，以秒为单位，大于0有效定时。
                            定时器中不建议使用此参数。
    --cache-file [='$ARGV_cache_file']
                            持续数据缓存文件，主要用来记录异常的开始时间，用来判断异常时长。
                            多个进程同时执行时建议指定不同的缓存文件以免干扰

Help:
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
";
    exit 0
fi
# 必要命令判断
for COMMAND_NAME in sar iostat; do
    if ! which $COMMAND_NAME 2>&1 >/dev/null;then
        if [ -n "$ARGV_auto_install" ];then
            if [ `whoami` != 'root' ];then
                echo '当前执行用户非 root 可能会无法正常安装！' >&2;
            fi
            for INSTALL_COMMAND_NAME in yum apt dnf; do
                if which $INSTALL_COMMAND_NAME 2>&1 >/dev/null;then
                    if $INSTALL_COMMAND_NAME install -y sysstat;then
                        if [ -e '/etc/default/sysstat' ];then
                            sed -i -r 's/^ENABLED="false"/ENABLED="true"/' /etc/default/sysstat
                            service sysstat restart
                        fi
                        break 2
                    fi
                fi
            done
            echo '当前系统安装没有找到支持的安装工具，需要手动安装！'
        fi
        echo '安装命令可参考：[yum|apt|dnf] install sysstat'
        echo '或者使用 --auto-install 参数自动安装，自动安装只支持 yum|apt|dnf'
        error_exit "当前系统没有安装 $COMMAND_NAME 工具，请安装后再使用！";
    fi
done
# 参数验证处理
if [ -n "$ARGV_warn_conf" -a -e "$ARGV_warn_conf" ];then
    debug_show "配置文件处理：$ARGV_warn_conf"
    parse_conf "$ARGV_warn_conf"
else
    error_exit "--warn-conf 未指定有效配置文件：$ARGV_warn_conf"
fi
if [ -n "$ARGV_loop_time" ];then
    if [[ "$ARGV_loop_time" =~ ^[1-9][0-9]+$ ]];then
        debug_show "循环间隔时长：$ARGV_loop_time"
    else
        error_exit "--loop-time 未指定有效循环监听时长：$ARGV_loop_time"
    fi
fi
if [ ! -e "$ARGV_cache_file" ] && ! touch "$ARGV_cache_file";then
    error_exit "--cache-file 缓存文件无效：$ARGV_cache_file"
fi
# 执行监听
while true;do
    parse_resources
    if [ -n "$ARGV_loop_time" ];then
        sleep $ARGV_loop_time
    else
        break
    fi
done
