#!/bin/bash
############################################################################
# 脚本处理公共文件，所有脚本运行的核心
# 此脚本不可单独运行，需要在其它脚本中引用执行
############################################################################
if [ $(basename "$0") = $(basename "${BASH_SOURCE[0]}") ];then
    error_exit "${BASH_SOURCE[0]} 脚本是共用文件必需使用source调用"
fi
# 全局版本号
readonly SHELL_RUN_VERSION='1.0.1'
# 切换工作目录
# @command chdir $path
# @param $path      切换的子目录
# return 1|0
chdir(){
    mkdirs $SHELL_WROK_TEMP_PATH/$1
    cd $SHELL_WROK_TEMP_PATH/$1
}
# 递归创建目录
# @command mkdirs $path [$user]
# @param $path      创建的目录
# @param $user      指定目录所有者用户
# return 1|0
mkdirs(){
    if [ ! -d "$1" ];then
        mkdir -p "$1"
        if_error "创建目录失败: $1"
    fi
    if [ -n "$2" ];then
        chown -R $2:$2 "$1"
    fi
    return 0
}
# 常规高精度公式计算
# @command math_compute $result $formula [$scale]
# @param $result            计算结果写入变量名
# @param $formula           计算公式
# @param $scale             计算小数精度位数，默认是0
#                           支持运算：+-*/^%
# return 1|0
math_compute(){
    tools_install bc
    local SCALE_NUM=0
    if [ -n "$3" ]; then
        SCALE_NUM=$(echo "$3"|grep -oP '^\d+'|awk '{if($1 == ""){print "0"}else{print $1}}')
    fi
    RESULT_STR=`echo "scale=$SCALE_NUM; $2"|bc|sed 's/\\\\//'|awk -F '.' '{if($1 ~ "[+-]" || $1==""){print "0."$2}else{print $1"."$2}}'|sed 's/ //g'|grep -oP "^\d+(\.\d{0,$SCALE_NUM})?"|grep -oP '^\d+(\.\d*[1-9])?'`
    eval "$1='$RESULT_STR'"
}
# 获取系统名及版本号
# @command get_os
# return 1|0
get_os(){
    if [ -e '/etc/os-release' ];then
        echo $(source /etc/os-release;echo "$ID $VERSION_ID"|tr '[:upper:]' '[:lower:]')
    fi
}
# 获取当前IP地址，内网是局域IP，写入全局变量SERVER_IP
# @command get_ip
# return 1|0
get_ip(){
    SERVER_IP='127.0.0.1'
    if ! if_command ifconfig;then
        packge_manager_run install net-tools
    fi
    if if_command ifconfig;then
        SERVER_IP=`ifconfig|grep -P '\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}' -o -m 1|head -n 1`
    else
        warn_msg '没有ifconfig命令，无法获取当前IP，将使用默认地址：'$SERVER_IP
    fi
}
# 判断上一个命令的成功与否输出错误并退出
# @command if_error $error_str
# @param $error_str     错误内容
# return 1|0
if_error(){
    if [ $? -ne 0 ];then
        error_exit "$1"
    fi
    return 0
}
# 输出错误并退出
# @command error_exit $error_str
# @param $error_str     错误内容
# return 1
error_exit(){
    print_msg ERROR "$@"
    exit 1
}
# 输出常规信息
# @command info_msg $msg
# @param $msg       信息内容
# return 1
info_msg(){
    print_msg INFO "$@"
}
# 输出警告信息
# @command warn_msg $msg
# @param $msg       信息内容
# return 1
warn_msg(){
    print_msg WARN "$@"
}
# 输出运行信息
# @command run_msg $msg
# @param $msg       信息内容
# return 1
run_msg(){
    print_msg RUN "$@"
    eval "$@"
}
# 输出信息
# @command print_msg $type $msg
# @param $type      打印类型
# @param $msg       打印信息
# return 1
print_msg(){
    if [ -f /dev/stdout ];then
        # 重定向不需要输出颜色
        echo -n "[SHELL-$1]"
    else
        case "$1" in
            ERROR)
                echo -en "\033[40;31m[SHELL-ERROR]\033[0m"
                ;;
            INFO)
                echo -en "\033[40;32m[SHELL-INFO]\033[0m"
                ;;
            WARN)
                echo -en "\033[40;33m[SHELL-WARN]\033[0m"
                ;;
            RUN)
                echo -en "\033[40;34m[SHELL-RUN]\033[0m"
                ;;
            *)
                echo -en "\033[40;35m[SHELL-$1]\033[0m"
                ;;
        esac
    fi
    printf "%s\n" " ${@:2}"
}
# 询问选项处理
# @command ask_select $select_name $msg [$options]
# @param $select_name       询问获取输入内容写入变量名
# @param $msg               询问提示文案
# @param $options           询问输入选项，多个使用/分开，默认是 y/n
# return 1|0
ask_select(){
    local INPUT MSG_TEXT REGEXP_TEXT ATTEMPT=1  OPTIONS=$(printf '%s' "${3-y/n}"|sed 's/ //g')
    MSG_TEXT="$2 请输入：[ $OPTIONS ] "
    REGEXP_TEXT=$(printf '%s' "$OPTIONS"|sed 's/\//|/g')
    while [ -z "$INPUT" ]; do
        read -p "$MSG_TEXT" INPUT
        if printf '%s' "$INPUT"|grep -qP "^($REGEXP_TEXT)$";then
            break
        fi
        INPUT=''
        if ((ATTEMPT >= 10));then
            error_exit "已经连续输入错误 ${ATTEMPT} 次，终止询问！"
        else
            warn_msg "输入错误，请注意输入选项要求！"
            ((ATTEMPT++))
        fi
    done
    eval "$1=\$INPUT"
    return 1
}
# 询问许可操作
# @command ask_permit $msg
# @param $msg               询问提示文案
# return 1|0
ask_permit(){
    local ASK_INPUT
    ask_select ASK_INPUT "$1" || [ "$ASK_INPUT" = 'y' -o "$ASK_INPUT" = 'Y' ]
    return $?
}
# 获取文件系统的信息
# 此命令主要是处理很长的存储名可能会换行导致awk处理错位
# 虚拟机常见，通过修正可以让存储名与对应的信息保持在一行中
# @command df_awk $options
# @param $options         选项参数
# return 1|0
df_awk(){
    #去掉首行标题，合并截断行
    df $@|awk '{if(NR > 1){if(NF==1){prev=$1}else{{print prev,$1,$2,$3,$4,$5,$6,$7}prev=""}}}'
}
# 包管理系统运行
# @command packge_manager_run $command $packge_name
# @param $command       执行的命令
# @param $packge_name   操作的包名，或变量名，变量名前面需要增加 - 如 packge_manager_run install -PACKGE_NAME
# return 1|0
packge_manager_run(){
    local COMMAND_STR
    case $1 in
        install)
            COMMAND_STR=${PACKGE_MANAGER_INSTALL_COMMAND[$PACKGE_MANAGER_INDEX]}
        ;;
        remove)
            COMMAND_STR=${PACKGE_MANAGER_REMOVE_COMMAND[$PACKGE_MANAGER_INDEX]}
        ;;
        search)
            COMMAND_STR=${PACKGE_MANAGER_SEARCH_COMMAND[$PACKGE_MANAGER_INDEX]}
        ;;
        *)
            error_exit "未知包管理命令: $1"
        ;;
    esac
    if [ -z "$2" ];then
        error_exit "最少指定一个要安装的包名"
    fi
    local NAME COMMAND_ARRAY_VAL PACKGE_NAME COMMAND_ARRAY
    for NAME in ${@:2}; do
        if [ ${NAME:0:1} = '-' ];then
            COMMAND_ARRAY='${#'${NAME:1}'[@]}'
            if [ `eval "echo $COMMAND_ARRAY"` -gt 1 ];then
                COMMAND_ARRAY_VAL='${'${NAME:1}'['$[PACKGE_MANAGER_INDEX]']}'
            elif [ `eval "echo $COMMAND_ARRAY"` -gt 0 ];then
                COMMAND_ARRAY_VAL='${'${NAME:1}'[0]}'
            else
                error_exit "找不到配置的安装包名: $NAME"
            fi
            PACKGE_NAME=`eval "echo $COMMAND_ARRAY_VAL"`
            if [ "$PACKGE_NAME" = '-' -o "$PACKGE_NAME" = '' ];then
                continue;
            fi
        else
            PACKGE_NAME=$NAME
        fi
        if [ -z "$PACKGE_NAME" ];then
            error_exit "安装包名解析为空: $NAME"
        fi
        run_msg "$COMMAND_STR $PACKGE_NAME 2>/dev/null"
        if [ $? != '0' ];then
            warn_msg "$COMMAND_STR $PACKGE_NAME 运行失败，可能会影响后续运行结果"
        fi
    done
}
# 工具集安装
# @command tools_install $tool1 [$tool2 ...]
# @param $tool1 ...     工具名集（工具名全部是通用的）
# return 0
tools_install(){
    local TOOL
    for TOOL in $*; do
        if ! if_command $TOOL;then
            packge_manager_run install $TOOL 2> /dev/null
            if ! if_command $TOOL;then
                error_exit "安装工具 $TOOL 失败"
            fi
        fi
    done
    return 0
}
# 判断命令是否存在
# @command if_command $name
# @param $name          包名
# return 1|0
if_command(){
    if which $1 2>&1|grep -q "/$1";then
        return 0
    fi
    return 1
}
# 判断命令是否存在多个不同版本
# @command if_many_version $name $option1 [$option2 ...]
# @param $name          命令名
# @param $option1       命令对比参数，一般以版本号对比
# return 1|0
if_many_version(){
    if if_command $1;then
        local ITEM NEXT_VERSION PREV_VERSION
        for ITEM in `which -a $1`; do
            NEXT_VERSION=`$ITEM ${@:2} 2>&1`
            if [ -z "$PREV_VERSION" ];then
                PREV_VERSION=$NEXT_VERSION
            elif test "$NEXT_VERSION" != "$PREV_VERSION";then
                return 0
            fi
        done
    fi
    return 1
}
# 判断库是否存在
# @command if_lib $name [$if $version]
# @param $name          库名
# @param $if            判断版本条件：>=,>,<=,<,==
# @param $version       判断版本号
# return 1|0
if_lib(){
    # ldconfig 是动态库管理工具，主要是通过配置文件 /etc/ld.so.conf 来管理动态库所在目录
    # 安装pkg-config
    # pkg-config 是三方库管理工具，以.pc为后缀的文件来配置不同的三方头文件或库文件
    # 一般三方库需要有个以 -devel 为后缀的配置工具名安装后就会把以 .pc 为后缀的文件写到到 pkg-config 默认管理目录
    # 例如：安装openssl后需要再安装openssl-devel才可以使用 pkg-config 查看 openssl
    # 安装pkg-config
    if ! if_command pkg-config;then
        packge_manager_run install -PKGCONFIG_PACKGE_NAMES
    fi
    if ! if_command pkg-config;then
        # 获取最新版
        get_version PKG_CONFIG_VERSION https://pkg-config.freedesktop.org/releases/ 'pkg-config-\d+\.\d+\.tar\.gz'
        info_msg "安装 pkg-config-$PKG_CONFIG_VERSION"
        # 下载
        download_software https://pkg-config.freedesktop.org/releases/pkg-config-$PKG_CONFIG_VERSION.tar.gz
        # 编译安装
        configure_install --with-internal-glib --prefix=$INSTALL_BASE_PATH/pkg-config/$PKG_CONFIG_VERSION
    fi
    if pkg-config --exists "$1";then
        if [ -n "$2" -a -n "$3" ] && ! pkg-config --cflags --libs "$1 $2 $3" > /dev/null;then
            return 1
        fi
        return 0
    fi
    return 1
}
# 判断版本大小
# @command if_version $version1 $if $version2
# @param $version1  版本号1
# @param $if        判断条件：>=,>,<=,<,==,!=
# @param $version2  版本号2
# return 1|0
if_version(){
    local VERSIONS=`echo -e "$1\n$3"|sort -Vrb` RESULT
    case "$2" in
        "==")
            RESULT=`echo -e "$VERSIONS"|uniq|wc -l|grep 1`
        ;;
        "!=")
            RESULT=`echo -e "$VERSIONS"|uniq|wc -l|grep 2`
        ;;
        ">")
            RESULT=`echo -e "$VERSIONS"|uniq -u|head -n 1|grep "$1"`
        ;;
        ">=")
            RESULT=`echo -e "$VERSIONS"|uniq|head -n 1|grep "$1"`
        ;;
        "<")
            RESULT=`echo -e "$VERSIONS"|uniq -u|tail -n 1|grep "$1"`
        ;;
        "<=")
            RESULT=`echo -e "$VERSIONS"|uniq|tail -n 1|grep "$1"`
        ;;
        *)
            error_exit "未知版本判断条件：$2"
        ;;
    esac
    if [ -n "$RESULT" ]; then
        return 0;
    fi
    return 1;
}
# 解析shell脚本参数
# 命令参数解析成功后将写入参数名规则：
#   参数： ARGU_参数全名
#   选项： ARGV_选项全名
# 横线转换为下划线，缩写选项使用标准选项代替，使用时注意参数名的大小写不变
# @command parse_shell_param $define_name $options_name
# @param $define_name       定义参数变量名
#                           配置参数规则：
#                           [name, {validate}]              定义参数
#                           [name='', {validate}]           定义参数带默认值
#                           [-n, --name, {validate}]        定义无值选项
#                           [-n, --name='', {validate}]     带选项值的选项
#                           说明：
#                           name        参数名，前缀无减号，组合要求：字母、数字、减号
#                           -n          短选项名，前缀一个减号，组合要求：字母、数字、减号
#                                       短选项必需定义在长选项名前面且不可单独定义短选项
#                           --name      长选项名，前缀两个减号，组合要求：字母、数字、减号
#                           =''         定义参数或选项的默认值，选项指定后为带值选项，默认值为空时可省略后面的引号
#                                       默认值允许使用：字母、数字、减号、下划线、转义组合，或者使用单双引号
#                                       转义符在无引号或有引号时均有效使用时需要注意
#                           {validate}  选项或参数验证，验证支持参考函数：validate_shell_param
# @param $options_name      命令参数数组名
# return 1|0
parse_shell_param() {
    local PARAM NAME SHORT_NAME DEFAULT_VALUE DEFAULT_VALUE_STR DEFAULT_VALIDATE_STR PARAM_STR PARAM_INFO_STR PARAM_NAME_STR PARAM_SHOW_DEFINE PARAM_SHOW_INFO ARG_NAME INDEX 
    local SPACE_NUM=22 ARGUMENTS=() OPTIONS=() OPTIONALS=() ARGVS=() VALIDATES_NAME_QUEUE=() VALIDATES_RULE_QUEUE=() COMMENT_SHOW_ARGUMENTS='' COMMENT_SHOW_OPTIONS=''
    local REGEXP_ARGV='(-[a-z0-9]\s*,\s*)?--[a-z0-9][a-z0-9\-]+|[a-z0-9][a-z0-9\-]+' REGEXP_VALIDATE="\{\s*([,:\|]+|$REGEXP_QUOTE_STRING)*\s*\}"
    # 解析定义的参数
    while read -r PARAM; do
        if [ -z "$PARAM" ] || printf '%s' "$PARAM"|grep -qP '^\s*$'; then
            continue;
        fi
        if printf '%s' "$PARAM"|grep -qP '^\s*#';then
            PARAM=$(printf '%*s' $SPACE_NUM)"${PARAM:1}\n"
            if [[ "$NAME" == -* ]];then
                COMMENT_SHOW_OPTIONS="$COMMENT_SHOW_OPTIONS$PARAM"
            elif [ -n "$NAME" ];then
                COMMENT_SHOW_ARGUMENTS="$COMMENT_SHOW_ARGUMENTS$PARAM"
            else
                error_exit "备注无匹配参数信息：$PARAM"
            fi
            continue;
        fi
        # 提取匹配的定义参数语句结构
        PARAM_STR=$(printf '%s' "$PARAM"|grep -oiP "^\s*\[\s*($REGEXP_ARGV)(\s*=\s*($REGEXP_QUOTE_STRING)?)?(\s*,\s*$REGEXP_VALIDATE)?\s*\]")
        if [ -z "$PARAM_STR" ];then
            error_exit "定义参数解析失败：$PARAM"
        fi
        # 去掉首尾多余字符
        PARAM_INFO_STR=`printf '%s' "$PARAM_STR"|sed -r "s/(^\s*\[\s*)|(\s*\]\s*$)//g"`
        # 提取参数名定义
        PARAM_NAME_STR=`printf '%s' "$PARAM_INFO_STR"|grep -oP "^($REGEXP_ARGV)"`
        # 提取参数默认值定义
        DEFAULT_VALUE_STR=$(printf '%s' "${PARAM_INFO_STR:${#PARAM_NAME_STR}}"|grep -oP "^\s*=\s*($REGEXP_QUOTE_STRING)?")
        # 提取参数验证规则
        DEFAULT_VALIDATE_STR=$(printf '%s' "${PARAM_INFO_STR}"|grep -oP "$REGEXP_VALIDATE$"|sed -r "s/(^\s*\{\s*)|(\s*\}\s*$)//g")
        # 参数类型识别处理
        if [[ "$PARAM_NAME_STR" =~ ^-{1,2} ]];then
            SHORT_NAME=`printf '%s' "$PARAM_NAME_STR"|grep -oiP '^-[a-z0-9]'`
            NAME=`printf '%s' "$PARAM_NAME_STR"|grep -oiP '\-\-[a-z0-9][\w\-]+'`
            PARAM_SHOW_DEFINE="$NAME"
            if [ -n "$SHORT_NAME" ];then
                PARAM_SHOW_DEFINE="$SHORT_NAME, $PARAM_SHOW_DEFINE"
            fi
            if [ -n "$DEFAULT_VALUE_STR" ];then
                OPTIONS[${#OPTIONS[@]}]="$PARAM_SHOW_DEFINE"
            else
                OPTIONALS[${#OPTIONALS[@]}]="$PARAM_SHOW_DEFINE"
            fi
            ARG_NAME='ARGV_'
        else
            SHORT_NAME=''
            NAME=`printf '%s' $PARAM_NAME_STR|grep -oiP '^[a-z0-9][\w\-]+'`
            PARAM_SHOW_DEFINE="$NAME"
            ARG_NAME='ARGU_'
        fi
        # 重复参数校验
        for ((INDEX=0; INDEX < ${#ARGVS[@]}; INDEX++)); do
            if test ${ARGVS[$INDEX]} = $NAME || test ${ARGVS[$INDEX]} = "$SHORT_NAME";then
                error_exit "不能定义重名参数: ${ARGVS[$INDEX]} , $PARAM"
            fi
        done
        ARGVS[${#ARGVS[@]}]="$NAME"
        if [ -n "$SHORT_NAME" ];then
            ARGVS[${#ARGVS[@]}]="$SHORT_NAME"
        fi
        # 参数默认值写入参数可访问全局变量中
        ARG_NAME=$ARG_NAME`printf '%s' "$NAME"|sed -r "s/^-{1,2}//"|sed "s/-/_/g"`
        if [ -n "$DEFAULT_VALUE_STR" ];then
            DEFAULT_VALUE_STR=$(printf '%s' "$DEFAULT_VALUE_STR"|sed -r "s/(^=\s*)//")
            PARAM_SHOW_DEFINE="$PARAM_SHOW_DEFINE [= ${DEFAULT_VALUE_STR:-''}]"
            get_escape_string "$DEFAULT_VALUE_STR" $ARG_NAME
        elif ! declare -p $ARG_NAME 2>/dev/null >/dev/null;then
            eval "$ARG_NAME=''"
        fi
        # 参数有验证写入待验证队列中
        if [ -n "$DEFAULT_VALIDATE_STR" ];then
            VALIDATES_NAME_QUEUE[${#VALIDATES_NAME_QUEUE[@]}]="$ARG_NAME"
            VALIDATES_RULE_QUEUE[${#VALIDATES_RULE_QUEUE[@]}]="$DEFAULT_VALIDATE_STR"
        fi
        # 构造帮助命令中参数展示
        INDEX=`echo $[ $(printf '%s' "$PARAM_SHOW_DEFINE"|wc -m) + 4 ]`
        PARAM_SHOW_INFO="    $PARAM_SHOW_DEFINE"
        if ((INDEX >= SPACE_NUM));then
            PARAM_SHOW_INFO="$PARAM_SHOW_INFO\n"
        fi
        PARAM_SHOW_INFO=$PARAM_SHOW_INFO$(printf '%*s' $((INDEX >= SPACE_NUM ? SPACE_NUM : SPACE_NUM-INDEX)))${PARAM:${#PARAM_STR}}
        if [[ "$NAME" == -* ]];then
            COMMENT_SHOW_OPTIONS="$COMMENT_SHOW_OPTIONS$PARAM_SHOW_INFO \n"
        else
            ARGUMENTS[${#ARGUMENTS[@]}]="$NAME"
            COMMENT_SHOW_ARGUMENTS="$COMMENT_SHOW_ARGUMENTS$PARAM_SHOW_INFO \n"
        fi
    done <<EOF
$(eval "echo -e \"\$$1\"")
[-h, --help]显示脚本使用帮助信息
[-v, --version]显示脚本版本号
EOF
    # 解析匹配传入参数
    local ITEM ARG_NUM VALUE OPTIONS_TEMP NAME_TEMP VALUE_TEMP ARGUMENTS_INDEX=0 ARG_SIZE=$(eval "echo \${#$2[@]}")
    for ((ARG_NUM=0; ARG_NUM < ARG_SIZE; ARG_NUM++)); do
        eval "ITEM=\${$2[$ARG_NUM]}"
        if [ -z "$ITEM" ];then
            continue
        fi
        NAME=''
        if [[ "$ITEM" =~ ^(--[A-Za-z0-9][A-Za-z0-9\-]+=.*|-[A-Za-z0-9])$ ]]; then
            # 有参数的选项处理
            if [[ "$ITEM" =~ ^--[A-Za-z0-9][A-Za-z0-9\-]+=.*$ ]];then
                NAME_TEMP=$(printf '%s' "$ITEM"|grep -oiP '^--[a-z0-9][\w\-]+')
                VALUE=$(printf '%s' "$ITEM"|sed -r "s/^[^=]+=//")
            else
                NAME_TEMP="$ITEM"
                VALUE=''
                for ((INDEX=0; INDEX < ${#OPTIONALS[@]}; INDEX++)); do
                    OPTIONS_TEMP=${OPTIONALS[$INDEX]}
                    if [ "$OPTIONS_TEMP" != "`printf '%s' "$OPTIONS_TEMP"|sed -r "s/$NAME_TEMP($|,)//"`" ];then
                        NAME=${OPTIONS_TEMP#*--}
                        VALUE='1'
                        break
                    fi
                done
            fi
            if [ -z "$NAME" ];then
                for ((INDEX=0; INDEX < ${#OPTIONS[@]}; INDEX++)); do
                    OPTIONS_TEMP=${OPTIONS[$INDEX]}
                    if [ "$OPTIONS_TEMP" != "`printf '%s' "$OPTIONS_TEMP"|sed -r "s/$NAME_TEMP($|,)//"`" ];then
                        NAME=${OPTIONS_TEMP#*--}
                        if [[ -z "$VALUE" && "$NAME_TEMP" =~ ^-[a-z0-9]$ ]];then
                            ((ARG_NUM++))
                            eval "VALUE=\${$2[$ARG_NUM]}"
                        fi
                        if [ -z "$VALUE" ] && ! [[ $ITEM =~ = ]] && (($ARG_NUM >= $ARG_SIZE));then
                            error_exit "$NAME 必需指定一个值"
                        fi
                        break
                    fi
                done
            fi
            ARGUMENTS_INDEX=${#ARGUMENTS[@]}
            ARG_NAME='ARGV_'
        elif ((${#ARGUMENTS[@]} > 0 && $ARGUMENTS_INDEX < ${#ARGUMENTS[@]})); then
            NAME=${ARGUMENTS[$ARGUMENTS_INDEX]}
            VALUE="$ITEM"
            ARG_NAME='ARGU_'
            ((ARGUMENTS_INDEX+=1))
        fi
        if [ -z "$NAME" ];then
            warn_msg "未知参数: "$ITEM
        else
            eval "$ARG_NAME${NAME//-/_}=\$VALUE"
        fi
    done
    if [ "$ARGV_help" = '1' ];then
        # 帮助命令强制进入并终止后续执行
        local PARAMS_NAME=() INFO_SHOW_STR=""
        if [ -n "$COMMENT_SHOW_ARGUMENTS" ];then
            PARAMS_NAME[${#PARAMS_NAME[@]}]='[Arguments]'
            INFO_SHOW_STR="Arguments: \n$COMMENT_SHOW_ARGUMENTS\n";
        fi
        if [ -n "$COMMENT_SHOW_OPTIONS" ];then
            PARAMS_NAME[${#PARAMS_NAME[@]}]='[Options]'
            INFO_SHOW_STR=$INFO_SHOW_STR"Options: \n$COMMENT_SHOW_OPTIONS\n";
        fi
        if [ -n "$SHELL_RUN_HELP" ];then
            INFO_SHOW_STR=$INFO_SHOW_STR"Help: \n"$(echo -e "$SHELL_RUN_HELP"|sed -r 's/^(\s*\S)/    \1/g');
        fi
        local RUN_SHOW_STR="    bash $(echo -n $0|sed "s,^`pwd`/,,") ${PARAMS_NAME[@]}\n"
        if [ $(basename $0) != 'run.sh' -a -e $SHELL_WROK_BASH_PATH/run.sh ];then
            RUN_SHOW_STR="$RUN_SHOW_STR\n    bash "$(echo -n $SHELL_WROK_BASH_PATH/|sed "s,^`pwd`/,,")"run.sh $(basename $0 '.sh') ${PARAMS_NAME[@]}\n"
        fi
        echo -e "Description:
$(echo -e "$SHELL_RUN_DESCRIPTION"|sed -r 's/^(\s*\S)/    \1/g')

Usage:
$RUN_SHOW_STR

$INFO_SHOW_STR";
        exit
    elif [ "$ARGV_version" = '1' ];then
        # 展示脚本版本号信息强制终止后续执行
        echo -e "linux服务器常用工具和安装shell脚本，当前版本号：$SHELL_RUN_VERSION
脚本存放在github上，地址：https://github.com/ttlxihuan/shell"
    else
        # 验证参数
        for ((INDEX=0; INDEX < ${#VALIDATES_NAME_QUEUE[@]}; INDEX++)); do
            validate_shell_param ${VALIDATES_NAME_QUEUE[$INDEX]} "${VALIDATES_RULE_QUEUE[$INDEX]}"
        done
        return 0
    fi
    exit 0
}
# 验证脚本参数
# @command validate_shell_param $name $rules
# @param $name              参数变量全名
# @param $rules             参数规则要求，多个使用|分开
#                           支持规则有：
#                               required                                必填项
#                               required_with:name[,name...]            指定变量有存在时必填，name是参数变量名
#                               required_with_all:name[,name...]        指定变量全部存在时必填，name是参数变量名
#                               required_without:name[,name...]         指定变量有不存在时必填，name是参数变量名
#                               required_without_all:name[,name...]     指定变量全部不存在时必填，name是参数变量名
#                               required_if:name,value[,name,value...]  指定变量有等于指定值时必填，name是参数变量名，value是参数变量值
#                               required_nif:name,value[,name,value...] 指定变量有不等于指定值时必填，name是参数变量名，value是参数变量值
#                               int[:[min],[max]]       必需是整数，可以指定数值大小范围
#                               float[:[min],[max]]     必需是浮点数，可以指定数值大小范围
#                               string[:[min],[max]]    必需是字符串，可以指定长度范围
#                               ip[:4|6]           必需是ip4或ip6地址，可以指定限定ip4或ip6
#                               url                必需是有效URL
#                               path               必需是存在的目录
#                               file               必需是存在的文件
#                               in:opt1,opt2,...   限制可选值
#                               regexp:expr        正则表达式验证，正则使用 [[]] 命令处理
#                           规则名要求：必需是支持的规则名
#                           规则值要求：可以是单或双引号或无引号（特殊字符需要使用转义字符，非特殊字符有：字母、数字、下划线、减号）
# return 1|0
validate_shell_param(){
    local RULE_TEXT RULE_NAME RULE_VALUES ARG_NAME ARG_VALUE LISTS_STR INDEX ARG_REQUIRED_OPT ARG_REQUIRED_VAL VALUE_RULES="($REGEXP_QUOTE_STRING)"
    get_shell_option "$1" ARG_NAME ARG_VALUE
    while read RULE_TEXT; do
        RULE_NAME=$(printf '%s' "$RULE_TEXT"|grep -oP '^[^:\|]+')
        if ! [[ "$RULE_NAME" =~ ^(required(_(n?if|(with|without)(_all)?))?|int|float|string|path|file|ip|url|in|regexp)$ ]];then
            warn_msg "脚本参数 ${ARG_NAME} 未知验证：$RULE_NAME"
            continue
        fi
        ([[ -z "$ARG_VALUE" && "$RULE_NAME" != required* ]] || [[ -n "$ARG_VALUE" && "$RULE_NAME" == required* ]]) && continue
        RULE_VALUES=($(printf '%s' "${RULE_TEXT:${#RULE_NAME}+1}"|grep -oP "$VALUE_RULES"))
        # 剥离值前后引号
        for((INDEX=0;INDEX<${#RULE_VALUES[@]};INDEX+=2));do
            get_escape_string "${RULE_VALUES[$INDEX]}" RULE_VALUES[$INDEX]
        done
        [[ ! "$RULE_NAME" =~ ^(int|float|string)$ || "${RULE_VALUES[0]}" =~ ^([1-9][0-9]*|[0-9])*$ && "${RULE_VALUES[2]}" =~ ^([1-9][0-9]*|[0-9])*$ ]] ||
            error_exit "脚本参数 ${ARG_NAME} 校验规则错误，选项必需是数值范围：${RULE_TEXT}"
        LISTS_STR=''
        case "$RULE_NAME" in
            int)
                [[ "$ARG_VALUE" =~ ^[\-\+]?([1-9][0-9]*|[0-9])$ ]] || error_exit "脚本参数 ${ARG_NAME} 必需是整数，当前是：$ARG_VALUE"
                [ -z "${RULE_VALUES[0]}" ] || (( ARG_VALUE >= ${RULE_VALUES[0]} )) || error_exit "脚本参数 ${ARG_NAME} 必需 >= ${RULE_VALUES[0]}，当前是：$ARG_VALUE"
                [ -z "${RULE_VALUES[1]}" ] || (( ARG_VALUE <= ${RULE_VALUES[1]} )) || error_exit "脚本参数 ${ARG_NAME} 必需 <= ${RULE_VALUES[1]}，当前是：$ARG_VALUE"
            ;;
            float)
                tools_install bc
                [[ "$ARG_VALUE" =~ ^-?([1-9][0-9]*|[0-9])(\.[0-9]+)?$ ]] || error_exit "脚本参数 ${ARG_NAME} 必需是浮点数，当前是：$ARG_VALUE"
                [ -z "${RULE_VALUES[0]}" -o $(echo "$ARG_VALUE >= ${RULE_VALUES[0]}"|bc) = '1' ] || error_exit "脚本参数 ${ARG_NAME} 必需 >= ${RULE_VALUES[0]}，当前是：$ARG_VALUE"
                [ -z "${RULE_VALUES[0]}" -o $(echo "$ARG_VALUE <= ${RULE_VALUES[1]}"|bc) = '1' ] || error_exit "脚本参数 ${ARG_NAME} 必需 <= ${RULE_VALUES[1]}，当前是：$ARG_VALUE"
            ;;
            string)
                [ -z "${RULE_VALUES[0]}" ] || (( ${#ARG_VALUE} >= ${RULE_VALUES[0]} )) || error_exit "脚本参数 ${ARG_NAME} 字符长度必需 >= ${RULE_VALUES[0]}，当前是：$ARG_VALUE"
                [ -z "${RULE_VALUES[1]}" ] || (( ${#ARG_VALUE} <= ${RULE_VALUES[1]} )) || error_exit "脚本参数 ${ARG_NAME} 字符长度必需 <= ${RULE_VALUES[1]}，当前是：$ARG_VALUE"
            ;;
            path)
                [[ "$ARG_VALUE" =~ ^[~/] && -d "$ARG_VALUE" ]] || [[ "$ARG_VALUE" =~ ^[^~/] && -d "$SHELL_WROK_BASH_PATH/$ARG_VALUE" ]] ||
                error_exit "脚本参数 ${ARG_NAME} 指定目录不存在，当前是：$ARG_VALUE"
            ;;
            file)
                [[ "$ARG_VALUE" =~ ^[~/] && -e "$ARG_VALUE" ]] || [[ "$ARG_VALUE" =~ ^[^~/] && -e "$SHELL_WROK_BASH_PATH/$ARG_VALUE" ]] ||
                error_exit "脚本参数 ${ARG_NAME} 指定文件不存在，当前是：$ARG_VALUE"
            ;;
            required)
                error_exit "脚本参数 ${ARG_NAME} 不可为空"
            ;;
            required_if)
                for((INDEX=0;INDEX<${#RULE_VALUES[@]};INDEX+=2));do
                    get_shell_option "${RULE_VALUES[$INDEX]}" ARG_REQUIRED_OPT ARG_REQUIRED_VAL
                    [ -z "$ARG_REQUIRED_VAL" -o "$ARG_REQUIRED_VAL" != "${RULE_VALUES[$INDEX+1]}" ] || error_exit "脚本参数 ${ARG_NAME} 在 ${ARG_REQUIRED_OPT} = ${RULE_VALUES[$INDEX+1]} 时不可为空"
                done
            ;;
            required_nif)
                for((INDEX=0;INDEX<${#RULE_VALUES[@]};INDEX+=2));do
                    get_shell_option "${RULE_VALUES[$INDEX]}" ARG_REQUIRED_OPT ARG_REQUIRED_VAL
                    [ "$ARG_REQUIRED_VAL" = "${RULE_VALUES[$INDEX+1]}" ] || error_exit "脚本参数 ${ARG_NAME} 在 ${ARG_REQUIRED_OPT} != ${RULE_VALUES[$INDEX+1]} 时不可为空"
                done
            ;;
            required_with)
                for((INDEX=0;INDEX<${#RULE_VALUES[@]};INDEX++));do
                    get_shell_option "${RULE_VALUES[$INDEX]}" ARG_REQUIRED_OPT ARG_REQUIRED_VAL
                    [ -z "$ARG_REQUIRED_VAL" ] || error_exit "脚本参数 ${ARG_NAME} 在 ${ARG_REQUIRED_OPT} 指定后不可为空"
                done
            ;;
            required_with_all)
                for((INDEX=0;INDEX<${#RULE_VALUES[@]};INDEX++));do
                    get_shell_option "${RULE_VALUES[$INDEX]}" ARG_REQUIRED_OPT ARG_REQUIRED_VAL
                    [ -z "$ARG_REQUIRED_VAL" ] && continue 2
                    LISTS_STR="$LISTS_STR, $ARG_REQUIRED_OPT"
                done
                error_exit "脚本参数 ${ARG_NAME} 在 ${LISTS_STR:2} 指定后不可为空"
            ;;
            required_without)
                for((INDEX=0;INDEX<${#RULE_VALUES[@]};INDEX++));do
                    get_shell_option "${RULE_VALUES[$INDEX]}" ARG_REQUIRED_OPT ARG_REQUIRED_VAL
                    [ -n "$ARG_REQUIRED_VAL" ] || error_exit "脚本参数 ${ARG_NAME} 在 ${ARG_REQUIRED_OPT} 不指定时不可为空"
                done
            ;;
            required_without_all)
                for((INDEX=0;INDEX<${#RULE_VALUES[@]};INDEX++));do
                    get_shell_option "${RULE_VALUES[$INDEX]}" ARG_REQUIRED_OPT ARG_REQUIRED_VAL
                    [ -n "$ARG_REQUIRED_VAL" ] && continue 2
                    LISTS_STR="$LISTS_STR, $ARG_REQUIRED_OPT"
                done
                error_exit "脚本参数 ${ARG_NAME} 在 ${LISTS_STR:2} 不指定时不可为空"
            ;;
            ip)
                [[ -z "${RULE_VALUES[0]}" || "${RULE_VALUES[0]}" =~ ^[46]$ ]] || error_exit "脚本参数 ${ARG_NAME} 校验规则错误，选项必需4或6：${RULE_TEXT}"
                [[ "${RULE_VALUES[0]}" =~ ^4?$ && "$ARG_VALUE" =~ ^[0-9]{1,3}(\.[0-9]{1,3}){3}$ ]] || 
                [[ "${RULE_VALUES[0]}" =~ ^6?$ && "$ARG_VALUE" =~ ^[0-9A-Fa-f]{1,4}(:[0-9A-Fa-f]{1,4}){7}$ ]] ||
                error_exit "脚本参数 ${ARG_NAME} 不是有效ip${RULE_VALUES[0]:-4/6}地址，当前是：$ARG_VALUE"
            ;;
            url)
                tools_install curl
                curl -I -m 5 "$ARG_VALUE" 2>/dev/null >/dev/null || error_exit "脚本参数 ${ARG_NAME} 不是有效url地址，当前是：$ARG_VALUE"
            ;;
            in)
                for((INDEX=0;INDEX<${#RULE_VALUES[@]};INDEX++));do
                    if [ "${RULE_VALUES[$INDEX]}" = "$ARG_VALUE" ];then
                        ARG_EXIST=1
                        continue 2
                    fi
                    LISTS_STR="$LISTS_STR, ${RULE_VALUES[$INDEX]}"
                done
                error_exit "脚本参数 ${ARG_NAME} 必需是可选值其一：${LISTS_STR:2}，当前是：$ARG_VALUE"
            ;;
            regexp)
                [ -z "${RULE_VALUES[0]}" ] || eval [[ "\${ARG_VALUE}" =~ ${RULE_VALUES[0]} ]] || error_exit "脚本参数 ${ARG_NAME} 不符合正则表达式：${RULE_VALUES[0]}，当前是：$ARG_VALUE"
            ;;
            *)
                warn_msg "脚本参数 ${ARG_NAME} 无处理验证：$RULE_NAME"
            ;;
        esac
    done <<EOF
$(printf '%s' "$2"|grep -oP "[^:\|]+(:$VALUE_RULES(,$VALUE_RULES)*)?\|?")
EOF
}
# 获取转义后的字符串
# @command get_escape_string $string $export_name
# @param $string            要处理的字符串，前后引号会玻璃，内部转义符会全部替换
# @param $export_name       解析成功写入变量名
# return 1|0
get_escape_string(){
    local _TEMP_STRING=$(printf '%s' "$1"|sed -r "s/(^['\"])|(['\"]$)//g"|sed -r "s/\\\\(.)/\1/g")
    eval $2=\$_TEMP_STRING
}
# 通过变量名获取shell脚本选项信息
# @command get_shell_option $name $set_opt $set_val
# @param $name              要解析变量名
# @param $set_opt           解析选项成功写入变量名
# @param $set_val           解析选项值成功写入变量名
# return 1|0
get_shell_option(){
    local SHELL_OPTION_PREFIX='' SHELL_OPTION_NAME="${1:5}"
    if [[ "$1" == ARGV_* ]];then
        SHELL_OPTION_PREFIX='--'
    elif [[ "$1" != ARGU_* ]];then
        error_exit "${1} 未知校验参数"
    fi
    eval $2="$SHELL_OPTION_PREFIX${SHELL_OPTION_NAME//_/-}"
    eval $3=\${$1}
}
# 解析列表并去重再导出数组
# @command parse_lists $export_name $string $separator $match
# @param $export_name       计算结果写入变量名
# @param $string            要解析的列表字符串
# @param $separator         列表字符串的分隔符，可以是正则
# @param $match             列表每项匹配正则
# return 1|0
parse_lists(){
    local ITEM NEXT INDEX PARSE_STRING=`printf '%s' "$2"|sed -r "s/(^\s+|\s+$)//g"` PARSE_ARRAY=()
    eval "$1=()"
    while [ -n "$PARSE_STRING" ]; do
        NEXT=`printf '%s' "$PARSE_STRING"|grep -oP "^.*?$3"`
        ITEM=`printf '%s' "$NEXT"|sed -r "s/(^\s+|\s*$3$)//g"`
        if [ -z "$ITEM" ] || ! printf '%s' "$ITEM"|grep -qP "^$4$";then
            return $((`printf '%s' "$2"|wc -m` - `printf '%s' "$PARSE_STRING"|wc -m` + 1))
        fi
        PARSE_STRING=${PARSE_STRING:`printf '%s' "$NEXT"|wc -m`}
        # 去重处理
        for ((INDEX=0; INDEX < `eval "\${#$1[@]}"`; INDEX++)); do
            if test `eval "\${$1[$INDEX]}"` = $ITEM ;then
                continue 2
            fi
        done
        eval "$1[\${#$1[@]}]"="\$ITEM"
    done
    return 0
}
# 搜索项目中对应文件
# @command find_project_file $type $name $var_name
# @param $type              搜索类型
# @param $name              搜索名称，不需要后缀
# @param $var_name          搜索成功后写入变量
# return 1|0
find_project_file(){
    local FIND_DIR FIND_NAME
    case $1 in
        include)
            FIND_DIR=$SHELL_WROK_INCLUDES_PATH
            FIND_NAME="$2.sh"
            ;;
        install)
            FIND_DIR=$SHELL_WROK_INSTALLS_PATH
            FIND_NAME="$2-install.sh"
            ;;
        tool)
            FIND_DIR=$SHELL_WROK_TOOLS_PATH
            FIND_NAME="$2.sh"
            ;;
        etc)
            FIND_DIR=$SHELL_WROK_ETC_PATH
            FIND_NAME="$2.conf"
            ;;
        *)
            error_exit "可搜索类型错误 $1"
            ;;
    esac
    local FIND_LISTS=(`find $FIND_DIR -name "$FIND_NAME"`)
    if [ ${#FIND_LISTS[@]} = '0' ];then
        error_exit "搜索类型 $1 在 $FIND_DIR 目录下搜索不到 $2"
    elif [ ${#FIND_LISTS[@]} = '1' ];then
        eval "$3=$(cd $(dirname ${FIND_LISTS[0]});pwd)/$(basename ${FIND_LISTS[0]})"
    else
        error_exit "搜索类型 $1 在 $FIND_DIR 目录下搜索到 ${#FIND_LISTS[@]} 个匹配项"
    fi
}
if [ `whoami` != 'root' ];then
    warn_msg '当前执行用户非 root 可能会影响脚本正常运行！'
fi
# 提取工作目录
SHELL_WROK_BASH_PATH=$(cd $(cd $(dirname ${BASH_SOURCE[0]}); pwd)/../;pwd)
SHELL_WROK_INCLUDES_PATH=${SHELL_WROK_BASH_PATH}/includes
SHELL_WROK_INSTALLS_PATH=${SHELL_WROK_BASH_PATH}/installs
SHELL_WROK_TOOLS_PATH=${SHELL_WROK_BASH_PATH}/tools
SHELL_WROK_TEMP_PATH=${SHELL_WROK_BASH_PATH}/temp
SHELL_WROK_ETC_PATH=${SHELL_WROK_BASH_PATH}/etc
REGEXP_QUOTE_STRING="([\w\-]+|\\\\.)+|\"([^\"]+|\\\\.)*\"|'([^']+|\\\\.)*'"
# 加载配置
source $SHELL_WROK_INCLUDES_PATH/config.sh || exit
# 提取安装参数
CALL_INPUT_ARGVS=()
for ((INDEX=1;INDEX<=$#;INDEX++));do
    CALL_INPUT_ARGVS[${#CALL_INPUT_ARGVS[@]}]=${@:$INDEX:1}
done
unset INDEX
# 判断系统适用哪个包管理器
if if_command yum;then
    PACKGE_MANAGER_INDEX=0
    # epel-release 第三方软件依赖库EPEL，给yum、rpm等工具使用
    #yum -y install epel-release
    # 创建元数据缓存
    #yum makecache 2>&1 &>/dev/null
    yum -y update nss 2>&1 &>/dev/null &
elif if_command apt;then
    PACKGE_MANAGER_INDEX=1
elif if_command dnf;then
    PACKGE_MANAGER_INDEX=2
elif if_command pkg;then
    PACKGE_MANAGER_INDEX=3
else
    error_exit '暂无支持包管理，请确认系统信息，目前只支持：yum、apt'
fi
