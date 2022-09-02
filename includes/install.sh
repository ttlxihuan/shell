#!/bin/bash
############################################################################
# 编译安装公共处理文件，所有安装脚本运行的核心文件
# 此脚本不可单独运行，需要在其它脚本中引用执行
#
# 编译死循环处理
#   1、make时会检查编译文件时间，有的时候文件时间不匹配导致编译无限死循环，需要在编译目录下修改下文件时间（可使用命令： find ./ -type f|xargs touch ），再进行编译（注意是configure所在目录）
#   2、清空编译目录再解压重新编译安装
#   3、使用单核编译
############################################################################
if [ "$(basename "$0")" = "$(basename "${BASH_SOURCE[0]}")" ];then
    error_exit "${BASH_SOURCE[0]} 脚本是共用文件必需使用source调用"
fi

# 获取安装名
INSTALL_NAME=$(basename "$0" '-install.sh')
# 安装通用参数信息配置
SHELL_RUN_DESCRIPTION="安装${INSTALL_NAME}脚本"
DEFINE_RUN_PARAMS="$DEFINE_RUN_PARAMS
[version, {regexp:'^(new|[0-9]{1,}(.[0-9]{1,}){1,4})$'}]指定安装版本，不传则是获取最新稳定版本号
#传new安装最新版
#传指定版本号则安装指定版本
[--install-path='/usr/local', {required_with:ARGU_version|path}]安装根目录，规则：安装根目录/软件名/版本号
#没有特殊要求建议安装根目录不设置到非系统所在硬盘目录下
[-A, --action='install', {required|in:install,reinstall}]处理类型
#   install     标准安装
#   reinstall   重新安装（覆盖安装）
[-D, --download='again', {required|in:continue,reset,again}]下载方式
#   continue    延续下载，已经下载好的不再重新下载
#   again       延续下载并重新解压
#   reset       重新下载再解压
[--disk-space=ask, {required|in:ask,ignore,stop}]安装磁盘分区空间不够用时处理
#   ask     空间不足时询问操作
#   ignore  忽略空间不足
#   stop    空间不足停止安装
[--memory-space=ask, {required|in:swap,ask,ignore,stop}]内存空间不够用时处理
#   swap    空间不足直接创建虚拟内存
#   ask     空间不足时询问操作
#   ignore  忽略空间不足
#   stop    空间不足停止安装
#数据空间包括编译目录硬盘和内存大概最少剩余空间
#处理操作有：编译目录转移，自动添加虚拟内存等
"
if [ -n "$DEFAULT_OPTIONS" ];then
    _DEFAULT_OPTIONS=($DEFAULT_OPTIONS) _DEFAULT_OPTIONS_PART=()
    for ((INDEX=0;INDEX<=${#_DEFAULT_OPTIONS[@]};INDEX+=6));do
        _DEFAULT_OPTIONS_PART[${#_DEFAULT_OPTIONS_PART[@]}]="#  ${_DEFAULT_OPTIONS[@]:$INDEX:6}
"
    done
    DEFINE_RUN_PARAMS="$DEFINE_RUN_PARAMS
[--without-default-options]不要默认安装选项，默认选项有：
${_DEFAULT_OPTIONS_PART[@]}
"
    unset _DEFAULT_OPTIONS _DEFAULT_OPTIONS_PART
fi
SHELL_RUN_HELP="安装脚本一般使用方式:
获取最新稳定安装版本号:
    bash ${INSTALL_NAME}-install.sh

安装最新稳定版本${INSTALL_NAME}:
    bash ${INSTALL_NAME}-install.sh new

安装指定版本${INSTALL_NAME}:
    bash ${INSTALL_NAME}-install.sh 1.1.1
"
if [ -n "$DEFINE_INSTALL_TYPE" ];then
    DEFINE_RUN_PARAMS="$DEFINE_RUN_PARAMS
[-j, --make-jobs=0, {required|int:0}]编译同时允许N个任务 
#   =0 当前CPU数
#   >0 指定个数
#任务多编译快且资源消耗也大（不建议超过CPU核数）
#当编译因进程被系统杀掉时可减少此值重试。
[-o, --options=]添加${DEFINE_INSTALL_TYPE}选项，使用前请核对选项信息。
"
    if [ "$DEFINE_INSTALL_TYPE" = 'configure' ];then
        DEFINE_RUN_PARAMS="$DEFINE_RUN_PARAMS
#增加${DEFINE_INSTALL_TYPE}选项，支持以下三种方式传参：
#   1、原样选项 --xx 、-xx 或 ?--xx 、?-xx
#   2、启用选项 xx 或 ?xx 解析后是 --enable-xx 或 --with-xx 
#   3、禁用选项 !xx 或 ?!xx 解析后是 --disable-xx
#选项前面的?是在编译选项时会查找选项是否存在，如果不存在则丢弃，存在则附加
#选项前面的!是禁用某个选项，解析后会存在该选项则附加
#选项多数有依赖要求，在增选项前需要确认依赖是否满足，否则容易造成安装失败。
"
        SHELL_RUN_HELP=$SHELL_RUN_HELP"
安装最新稳定版本${INSTALL_NAME}且指定安装选项:
    bash ${INSTALL_NAME}-install.sh new --options=\"?ext1 ext2\"
"
    elif [ -n "$DEFINE_INSTALL_TYPE" ];then
        DEFINE_RUN_PARAMS="$DEFINE_RUN_PARAMS
#增加${DEFINE_INSTALL_TYPE}原样选项，选项按${DEFINE_INSTALL_TYPE}标准即可。
#选项部分有依赖要求，在增选项前需要确认依赖是否满足，否则容易造成安装失败。
"
        SHELL_RUN_HELP=$SHELL_RUN_HELP"
安装最新稳定版本${INSTALL_NAME}且指定安装选项:
    bash ${INSTALL_NAME}-install.sh new --options=\"opt1 opt2\"
"
    fi
fi
SHELL_RUN_HELP=$SHELL_RUN_HELP"
1、安装脚本会在脚本所在临时目录创建安装目录，此目录用于下载和编译安装包。
2、当后续再次安装相同版本时，已经存在的安装包将不再下载而是直接使用。
3、如果安装多台服务器可直接复制安装目录及安装包，这样就不会再下载而是直接安装处理。也可以使用远程安装工具脚本。
4、安装时会自动安装与之匹配的各种依赖包，但并未穷尽处理，尤其安装新版本或增加安装选项时需要格外注意安装结果。
5、安装后并未删除编译文件，需要手动删除。
"
# 引用公共文件
source "$(cd "$(dirname "${BASH_SOURCE[0]}")"; pwd)"/basic.sh || exit

# 随机生成密码
# @command random_password $password_val [$size] [$group]
# @param $password_val      生成密码写入变量名
# @param $size              密码长度，默认20
# @param $group             密码组合，默认包含：数字、字母大小写、~!@#$%^&*()_-=+,.;:?/\|
# return 1|0
random_password(){
    local PASSWORD_CHARS_STR='qwertyuiopasdfghjklzxcvbnm1234567890QWERTYUIOPASDFGHJKLZXCVBNM~!@#$%^&*_-=+,.;:?|'
    if [ -n "$3" ];then
        addc_slashes PASSWORD_CHARS_STR '\-|\?|\.|\*|\$|\^|\|'
        printf '%s' "$3"|grep -qP "^[$PASSWORD_CHARS_STR]+$"
        if_error "密码包含的字符无效: $3"
        PASSWORD_CHARS_STR=$3
    fi
    local PASSWORD_STR='' PASSWORD_INDEX_START='' PASSWORD_SIZE=25
    if [ -n "$2" ]; then
        if ! [[ "$2" =~ ^[1-9][0-9]*$ ]];then
            error_exit "生成密码位数必需是整数，现在是：$2"
        fi
        if (($2 < 0 || $2 > 100));then
            error_exit "生成密码位数范围是：1~99，现在是：$2"
        fi
        PASSWORD_SIZE=$2
    fi
    for ((I=0; I<$PASSWORD_SIZE; I++)); do
        # $RANDOM 是系统内置随机变量，每次提取值都会不一样，可用来做随机处理
         PASSWORD_INDEX_START=`expr $RANDOM % ${#PASSWORD_CHARS_STR}`
         PASSWORD_STR=$PASSWORD_STR${PASSWORD_CHARS_STR:$PASSWORD_INDEX_START:1}
    done
    eval "$1='$PASSWORD_STR'"
}
# 解析使用密码
# @command parse_use_password $password_val [$size|$password] [$group]
# @param $password_val      生成密码写入变量名
# @param $size              生成密码长度：%num，比如生成10位密码：%10
# @param $password          指定密码
# @param $group             生成密码组合，默认全部类型
# return 1|0
parse_use_password(){
    if [[ "$2" =~ ^make:[1-9][0-9]{0,2}(,.+)?$ ]];then
        local MAKE_PARAMS=${2#*:} MAKE_LENGTH MAKE_GROUP
        if [ "${MAKE_PARAMS/,/}" != "$MAKE_PARAMS" ];then
            MAKE_LENGTH=${MAKE_PARAMS%%,*}
            MAKE_GROUP=${MAKE_PARAMS:${#MAKE_LENGTH}+1}
        else
            MAKE_LENGTH=$MAKE_PARAMS
        fi
        random_password $1 $MAKE_LENGTH "$MAKE_GROUP"
    else
        eval "$1=\$2"
    fi
}
# 解析使用内存，计算结果是整数（四舍五入）
# @command parse_use_memory $var_name $ratio $unit
# @param $var_name          写入变量名
# @param $ratio             可用内存比率值，默认为 100
# @param $unit              转换内存单位，可选值：B、K、M、G，默认B
# return 1|0
parse_use_memory(){
    if ! [[ "$2" =~ ^([0-9]|[1-9][0-9]*)[BKMG%]?$ ]];then
        return 1
    fi
    local FREE_MAX_MEMORY USE_UNIT=${3:-B} CURRENT_UNIT='B'
    if [[ "$2" =~ ^0[BKMGT%]?$ ]];then
        # 不配置处理
        FREE_MAX_MEMORY=0
    else
        if [[ "$2" =~ ^[1-9][0-9]*%$ ]];then
            # 比率配置处理
            local RATIO_VALUE=${2//%/}
            # 内核3.14的上有MemAvailable
            if grep -q '^MemAvailable:' /proc/meminfo;then
                FREE_MAX_MEMORY=$(cat /proc/meminfo|grep -P '^(MemFree|MemAvailable):'|awk '{count+=$2} END{print count}')
            else
                FREE_MAX_MEMORY=$(cat /proc/meminfo|grep -P '^(MemFree|Buffers|Cached):'|awk '{count+=$2} END{print count}')
            fi
            if (( FREE_MAX_MEMORY > 0 && RATIO_VALUE > 0 && RATIO_VALUE < 100 ));then
                FREE_MAX_MEMORY=$((FREE_MAX_MEMORY * 1024 * RATIO_VALUE / 100))
            else
                warn_msg "配置使用内存率错误：${2}，按0处理"
                FREE_MAX_MEMORY=0
            fi
        else
            # 指定配置处理
            FREE_MAX_MEMORY=$2
            CURRENT_UNIT=${2:${#FREE_MAX_MEMORY}}
        fi
        if [ "$FREE_MAX_MEMORY" != '0' ];then
            size_switch FREE_MAX_MEMORY "$FREE_MAX_MEMORY" "$USE_UNIT"
            printf -v FREE_MAX_MEMORY '%.0f' "$FREE_MAX_MEMORY"
        fi
        local JUDGE_SIZE
        math_compute JUDGE_SIZE "$FREE_MAX_MEMORY > 0" 2
        if [ "$JUDGE_SIZE" = '0' ];then
            warn_msg "换算系统空闲物理内存不足1${USE_UNIT}，跳过相关配置处理"
        fi
    fi
    eval "$1=\$FREE_MAX_MEMORY"
}
# 当前安装内存空间要求，不够将添加虚拟内存扩充
# @command memory_require $min_size
# @param $min_size          安装脚本最低内存大小，G为单位
# return 1|0
memory_require(){
    local ASK_INPUT CURRENT_MEMORY DIFF_SIZE
    # 总内存G
    CURRENT_MEMORY=`cat /proc/meminfo|grep -P '^(MemTotal|SwapTotal):'|awk '{count+=$2} END{printf "%.2f", count/1048576}'`
    # 剩余内存G
    # CURRENT_MEMORY=cat /proc/meminfo|grep -P '^(MemFree|SwapFree):'|awk '{count+=$2} END{print count/1048576}'
    math_compute DIFF_SIZE "$1 - $CURRENT_MEMORY"
    if ((DIFF_SIZE > 0));then
        warn_msg "内存不足：${1}G，当前只有：${CURRENT_MEMORY}G"
        if [ "$ARGV_memory_space" = 'ignore' ] || ([ "$ARGV_memory_space" = 'ask' ] && ! ask_permit "是否增加虚拟内存 ${DIFF_SIZE}G ？");then
            warn_msg '忽略内存不足，继续安装'
            return
        elif [ "$ARGV_memory_space" = 'stop' ];then
            error_exit '内存空间不足，退出安装'
        fi
        local SWAP_PATH SWAP_NUM BASE_PATH='/'
        info_msg '即将在根目录下创建虚拟内存空间'
        path_require $BASE_PATH $DIFF_SIZE;
        SWAP_PATH=${BASE_PATH%/*}/swap
        SWAP_NUM=$(find $BASE_PATH -maxdepth 1 -name swap*|grep -oP 'swap\d+$'|sort -r|head -1|grep -oP '\d+$')
        if [ -n "$SWAP_NUM" ];then
            SWAP_PATH=$SWAP_PATH$(( SWAP_NUM + 1))
        elif [ -e "$SWAP_PATH" ];then
            SWAP_PATH=${SWAP_PATH}1
        fi
        info_msg '创建虚拟内存交换区：'$SWAP_PATH
        # 创建一个空文件区，并以每块bs字节重复写count次数且全部写0，主要是为防止内存溢出或越权访问到异常数据
        dd if=/dev/zero of=$SWAP_PATH bs=1024 count=${DIFF_SIZE}M
        # 将/swap目录设置为交换区
        mkswap $SWAP_PATH
        # 修改此目录权限
        chmod 0600 $SWAP_PATH
        # 开启/swap目录交换空间，开启后系统将建立虚拟内存，大小为 bs * count
        swapon $SWAP_PATH
        if [ "$ARGV_memory_space" != 'ask' ] || ask_permit '虚拟内存是否写入/etc/fstab文件用于重启后自动生效？';then
            # 写入配置文件，重启系统自动开启/swap目录交换空间
            if grep -qP "^$SWAP_PATH " /etc/fstab;then
                sed -i -r "s,^$SWAP_PATH .*$,$SWAP_PATH swap swap defaults 0 0," /etc/fstab
            else
                echo "$SWAP_PATH swap swap defaults 0 0" >> /etc/fstab
            fi
        else
            warn_msg '虚拟内存未写入/etc/fstab文件中，重启不会自动加载此虚拟内存'
        fi
        info_msg "如果需要删除虚拟内存，先关闭交换区 ，然后删除文件，再去掉/etc/fstab文件中的配置行。"
        info_msg "可以执行命令：swapoff $SWAP_PATH && rm -f $SWAP_PATH && sed -i -r '/^${SWAP_PATH//\//\\/}\s+/d' /etc/fstab"
    else
        info_msg "内存容量：${CURRENT_MEMORY}G"
    fi
}
# 获取指定目录对应挂载磁盘剩余空间要求
# @command path_require $min_size $path $path_name
# @param $path              判断的目录
# @param $min_size          要求目录挂载分区剩余空间G为单位
# @param $path_name         允许空间不足自动搜索空间够用目录，且将最终目录写入变量中
# return 1|0
path_require(){
    local PART_INFO=(`df_awk -k $1|awk '{print $1,$4}'|tail -1`)
    if ((${PART_INFO[1]} / 1048576 < $2 ));then
        warn_msg "目录 $1 所在分区 ${PART_INFO[0]} 剩余空间不足：${2}G"
        if [ "$ARGV_disk_space" = 'ignore' ] || ([ "$ARGV_disk_space" = 'ask' ] && ask_permit "是否继续安装？");then
            warn_msg '忽略磁盘空间不足，继续安装'
        else
            error_exit '磁盘空间不足，退出安装'
        fi
    else
        info_msg "目录 $1 所在分区 ${PART_INFO[0]} 可用空间：$((${PART_INFO[1]} / 1048576))G"
    fi
}
# 安装存储空间要求，单位G
# @command install_storage_require $work_path_size $install_path_size $memory_size
# @param $work_path_size       安装编译临时目录空间要求
# @param $install_path_size    安装目标目录空间要求
# @param $memory_size          安装编译内存要求
# return 1|0
install_storage_require(){
    local EXIST_SIZE=0 MIN_SIZE=$1
    info_msg "安装下载临时目录空间要求：${1}G"
    # 目标目录已经存在文件则自动减少要求空间
    if [ -d $SHELL_WROK_TEMP_PATH/shell-install ];then
        EXIST_SIZE=$(find $SHELL_WROK_TEMP_PATH/shell-install -maxdepth 1 -name $INSTALL_NAME-* -name *$INSTALL_VERSION* -exec du -k --max-depth=1 {} \;|awk 'BEGIN{total=0}{total+=$1}END{if(total>1048576){printf "%.0f",total/1048576}else{print 0}}')
        MIN_SIZE=$(($1 - EXIST_SIZE))
        info_msg "安装下载临时目录已经存在相关文件或目录占用：${EXIST_SIZE}G，扣除后要求：${MIN_SIZE}G"
    fi
    #编译安装临时目录
    path_require $SHELL_WROK_TEMP_PATH $MIN_SIZE
    MIN_SIZE=$2
    info_msg "安装目录空间要求：${2}G"
    # 目标目录已经存在文件则自动减少要求空间
    if [ -d $INSTALL_BASE_PATH/$INSTALL_NAME ];then
        EXIST_SIZE=$(find $INSTALL_BASE_PATH/$INSTALL_NAME -maxdepth 1 -name $INSTALL_VERSION -exec du -k --max-depth=1 {} \;|awk 'BEGIN{total=0}{total+=$1}END{if(total>1048576){printf "%.0f",total/1048576}else{print 0}}')
        MIN_SIZE=$(($1 - EXIST_SIZE))
        info_msg "安装目录空间已经存在相关文件或目录占用：${EXIST_SIZE}G，扣除后要求：${MIN_SIZE}G"
    fi
    #安装目录
    path_require $INSTALL_BASE_PATH $MIN_SIZE
    #内存
    info_msg "内存空间要求：${3}G"
    memory_require $3
}
# 添加安装的服务
# @command add_service $config_name
# @param  $config_name          配置数组名
# return 1|0
add_service(){
    local SERVICES_TOOL CONFIG_FILE CONFIG_NAME SERVICE_RUN SERVICE_BASE_PATH BLOCK_NAME EXIST_CONF=0
    eval CONFIG_NAME="\${$1[$SERVICES_CONFIG_NAME]}"
    eval SERVICE_RUN="\${$1[$SERVICES_CONFIG_START_RUN]}"
    eval "$1[$SERVICES_CONFIG_BASE_PATH]=\${$1[$SERVICES_CONFIG_BASE_PATH]-\"\$INSTALL_PATH\$INSTALL_VERSION\"}"
    if [ -z "$CONFIG_NAME" ];then
        CONFIG_NAME="$INSTALL_NAME-$INSTALL_VERSION"
        eval $1[$SERVICES_CONFIG_NAME]="$CONFIG_NAME"
    fi
    if [ -z "$SERVICE_RUN" ];then
        error_exit "服务启动命令未指定！"
    fi
    find_project_file etc services CONFIG_FILE
    # 只判断块名是否存在，不存在就增加，存在就跳过
    while read BLOCK_NAME;do
        if [ "$BLOCK_NAME" = "$CONFIG_NAME" ];then
            warn_msg "服务管理已经配置 $CONFIG_NAME ，跳过写配置处理！"
            EXIST_CONF=1
            break
        fi
    done <<EOF
$(grep -nP '^\s*\[.+\]' $CONFIG_FILE|grep -oP '(^\d+)|([~!@#\$%\^\&\*_\-\+/|:\.\?[:alnum:]]+)')
EOF
    # 锁定配置文件
    
    # 写服务配置
    if [ "$EXIST_CONF" = '0' ];then
        echo "" >> $CONFIG_FILE
        echo "[$CONFIG_NAME]" >> $CONFIG_FILE
        local CONFIG_VAL INDEX
        for ((INDEX=0;INDEX<${#SERVICES_CONFIG_KEYS[@]};INDEX++));do
            eval CONFIG_VAL="\${$1[$INDEX]}"
            if [ -n "$CONFIG_VAL" ];then
                echo "${SERVICES_CONFIG_KEYS[$INDEX]}=$CONFIG_VAL" >> $CONFIG_FILE
            fi
        done
    fi
    # 搜索服务管理脚本
    find_project_file tool services SERVICES_TOOL
    # 启动服务
    run_msg bash $SERVICES_TOOL start "$CONFIG_NAME"
}
# 初始化安装
# @command init_install $min_version $get_download_version_url $get_download_version_match [$get_download_version_rule]
# @param $min_version                安装脚本最低可安装版本号
# @param $get_download_version_url   安装脚本获取版本信息地址
# @param $get_download_version_match 安装脚本匹配版本信息正则
# @param $get_download_version_rule  安装脚本提取版本号正则
# return 1|0
init_install(){
    if [ -z "$INSTALL_NAME" ];then
        error_exit "获取安装名失败"
    fi
    if (($# < 3));then
        error_exit "安装初始化参数错误"
    fi
    local INSTALL_VERSION_NAME=`echo "${INSTALL_NAME}_VERSION"|tr '[:lower:]' '[:upper:]'|sed -r 's/-/_/g'` VERSION_RULE=${4-'\d+(\.\d+){2}'}
    # 版本处理
    if [ -z "$ARGU_version" ] || [[ $ARGU_version == "new" ]]; then
        get_download_version $INSTALL_VERSION_NAME "$2" "$3" "$VERSION_RULE"
        if [ -z "$ARGU_version" ];then
            info_msg "最新稳定版本：$(eval echo "\$$INSTALL_VERSION_NAME")"
            exit 0;
        fi
    elif echo "$ARGU_version"|grep -qP "^${VERSION_RULE}$";then
        eval "$INSTALL_VERSION_NAME=\"$ARGU_version\""
    else
        error_exit "安装版本号参数格式错误：$ARGU_version"
    fi
    INSTALL_VERSION=$(eval echo "\$$INSTALL_VERSION_NAME")
    local INSTALL_VERSION_MIN=$1
    if [ -n "$INSTALL_VERSION_MIN" ] && if_version "$INSTALL_VERSION" "<" "$INSTALL_VERSION_MIN"; then
        error_exit "最小安装版本号: $INSTALL_VERSION_MIN ，当前是：$INSTALL_VERSION"
    fi
    if has_run_shell "$INSTALL_NAME-install" ;then
        error_exit "$INSTALL_NAME 在安装运行中"
    fi
    # 安装目录
    INSTALL_PATH="$INSTALL_BASE_PATH/$INSTALL_NAME/"
    info_msg "即将安装：$INSTALL_NAME-$INSTALL_VERSION"
    info_msg "工作目录: $SHELL_WROK_TEMP_PATH"
    info_msg "安装目录: $INSTALL_PATH"
    if [ -e "$INSTALL_PATH$INSTALL_VERSION/" ] && find "$INSTALL_PATH$INSTALL_VERSION/" -type f -executable|grep -qP "$INSTALL_NAME|bin";then
        if [ "$ARGV_action" = 'install' ];then
            error_exit "$INSTALL_PATH$INSTALL_VERSION/ 安装目录不是空的，终止安装"
        else
            warn_msg "$INSTALL_PATH$INSTALL_VERSION/ 安装目录不是空的，即将强制重新安装：$INSTALL_NAME-$INSTALL_VERSION"
        fi
    fi
    if [ -n "$DEFINE_INSTALL_TYPE" ];then
        info_msg '安装验证最基本的编译工具'
        # 有编译类型安装编译所需基本工具
        install_gcc
        tools_install make ntpdate
        # 同步系统时间
        if if_command ntpdate; then
            ntpdate -u ntp.api.bz 2>&1 &>/dev/null &
        fi
        if if_many_version ldd --version;then
            warn_msg "glic 存在多版本，编译安装容易失败，建议删除非系统自带glibc版本！！！"
            warn_msg "glic 是系统基础库，不可全部删除，建议保留系统自带的glibc版本，否则可能导致系统故障！！！！"
        fi
    fi
    # 加载环境配置
    source /etc/profile
}

# 去掉默认选项
if [ -n "$ARGV_without_default_options" ];then
    DEFAULT_OPTIONS=''
fi
# 获取编译任务数
if [ -n "$DEFINE_INSTALL_TYPE" -a -z "$ARGV_make_jobs" -o "$ARGV_make_jobs" = '0' ];then
    INSTALL_THREAD_NUM=$TOTAL_THREAD_NUM
else
    INSTALL_THREAD_NUM=$ARGV_make_jobs
fi
#基本安装目录
INSTALL_BASE_PATH=${ARGV_install_path-/usr/local}
safe_realpath INSTALL_BASE_PATH
if [ -z "$INSTALL_BASE_PATH" ] || [ ! -d "$INSTALL_BASE_PATH" ];then
    error_exit '安装根目录无效：'$INSTALL_BASE_PATH
fi
# 包管理
source "$SHELL_WROK_INCLUDES_PATH/package.sh" || exit
# 安装根目录
INSTALL_BASE_PATH=$(cd $INSTALL_BASE_PATH; pwd)
# 服务配置键名
# 配置服务名
SERVICES_CONFIG_NAME=0
# 启动服务命令，必需指定否则不能启动服务
SERVICES_CONFIG_START_RUN=1
# 重启服务命令，可选，不指定会调用停止再启动
SERVICES_CONFIG_RESTART_RUN=2
# 服务对应的pid文件，当没有指定stop-run和status-run时必选否则无法获取状态或停止操作
SERVICES_CONFIG_PID_FILE=3
# 获取pid命令，属于动态提取pid，功能与pid-file一样，指定pid-file时此配置无效
SERVICES_CONFIG_PID_RUN=4
# 服务停止命令，如果未配置将取pid进行杀进程
SERVICES_CONFIG_STOP_RUN=5
# 获取服务状态命令，如果未配置将判断pid进程是否存在
SERVICES_CONFIG_STATUS_RUN=6
# 获取服务状态命令，如果未配置将判断pid进程是否存在
SERVICES_CONFIG_USER=7
# 获取服务状态运行根目录，默认为当前安装目录
SERVICES_CONFIG_BASE_PATH=8
# 服务配置键名对应位置
SERVICES_CONFIG_KEYS=('info' 'start-run' 'restart-run' 'pid-file' 'pid-run' 'stop-run' 'status-run' 'user' 'base-path')
# 可安装系统版本
OS_VERSION=($(get_os))
if [ ${#OS_VERSION[@]} != 0 ];then
    case ${OS_VERSION[0]} in
        ubuntu)
            MIN_OS_VERSION='16.04'
        ;;
        centos)
            MIN_OS_VERSION='6.4'
        ;;
        *)
            warn_msg "暂未验证过当前系统版本：${OS_VERSION[@]}"
        ;;
    esac
    if [ -n "$MIN_OS_VERSION" ] && if_version "$MIN_OS_VERSION" '>' "${OS_VERSION[1]}";then
        warn_msg "安装脚本暂时只兼容调试到：${OS_VERSION[0]} ${MIN_OS_VERSION}，当前系统版本为：${OS_VERSION[@]}，安装失败概率将增大！"
    fi
fi
