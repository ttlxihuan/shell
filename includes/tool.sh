#!/bin/bash
############################################################################
# 工具脚本公共处理文件，所有工具脚本运行的核心文件
# 此脚本不可单独运行，需要在其它脚本中引用执行
# 引用此脚本需要配置以下变量
#   SHELL_RUN_DESCRIPTION   脚本功能说明，帮助信息展示
#   SHELL_RUN_HELP          脚本附加说明，帮助信息展示，可选
#   DEFINE_TOOL_PARAMS      脚本参数体，解析参数使用，可选
# 所有脚本会强制增加两个参数 --help、--version 用来展示信息
############################################################################
# 引用公共文件
source "$(cd "$(dirname "${BASH_SOURCE[0]}")"; pwd)"/basic.sh || exit
if [ "$(basename "$0")" = "$(basename "${BASH_SOURCE[0]}")" ];then
    error_exit "${BASH_SOURCE[0]} 脚本是共用文件必需使用source调用"
fi
# 解析通用ini格式配置文件
# @command parse_conf $path [$block [...]]
# @param $path              配置文件名
# @param $block             必需有的区块配置
# return 1|0
parse_conf(){
    CONF_FILE="$1"
    safe_realpath CONF_FILE
    if [ ! -e "$CONF_FILE" ];then
        error_exit "配置文件不存在：$1"
    fi
    local CONF_LINE INDEX BLOCK_NAME BLOCK_ITEMS_NAME ITEM_NAME ITEM_VALUE CONF_LINENO=0 REQUIRED_BLOCK=(${@:2})
    CONF_BLOCK_NAMES=()
    while read CONF_LINE;do
        ((CONF_LINENO++))
        # 空白或注释行跳过
        if [[ -z "$CONF_LINE" || "$CONF_LINE" =~ ^[[:space:]]*# ]];then
            continue
        fi
        # 提取块名
        if [[ "$CONF_LINE" =~ ^[[:space:]]*\[[[:space:]]*[~!@#\$%\^\&\*_\-\+/|:\.\?[:alnum:]]+[[:space:]]*\] ]];then
            ITEM_NAME=${CONF_LINE#*[}
            ITEM_NAME=${ITEM_NAME%%]*}
            ITEM_NAME=${ITEM_NAME//[[:space:]]/]}
            CONF_LINE=${CONF_LINE#*]}
            # 空白或注释行跳过
            if ! [[ -z "$CONF_LINE" || "$CONF_LINE" =~ ^[[:space:]]*# ]];then
                warn_msg "第${CONF_LINENO}行，区块声明行不能包括非注释内容：$CONF_LINE"
            fi
            make_conf_key BLOCK_NAME "$ITEM_NAME"
            BLOCK_ITEMS_NAME="CONF_BLOCK_ITEMS_$BLOCK_NAME"
            # 重复参数校验
            for ((INDEX=0; INDEX < ${#CONF_BLOCK_NAMES[@]}; INDEX++)); do
                if test ${CONF_BLOCK_NAMES[$INDEX]} = "$ITEM_NAME" ;then
                    warn_msg "第${CONF_LINENO}行，${ITEM_NAME} 区块声明已经存在，将进行清除重写"
                    break
                fi
            done
            CONF_BLOCK_NAMES[${#CONF_BLOCK_NAMES[@]}]="$ITEM_NAME"
            eval "$BLOCK_ITEMS_NAME=()"
            # 必需区块处理
            for ((INDEX=0; INDEX < ${#REQUIRED_BLOCK[@]}; INDEX++)); do
                if test ${REQUIRED_BLOCK[$INDEX]} = "$ITEM_NAME" ;then
                    unset REQUIRED_BLOCK[$INDEX]
                    REQUIRED_BLOCK=($REQUIRED_BLOCK)
                    break
                fi
            done
            continue
        fi
        # 提取块值
        if [ -n "$BLOCK_NAME" ];then
            if [[ "$CONF_LINE" =~ ^[[:space:]]*[~!@#\$%\^\&\*_\-\+/|:\.\?[:alnum:]]+[[:space:]]*= ]];then
                ITEM_NAME=${CONF_LINE%%=*}
                # 去掉配置前面的空格
                ITEM_VALUE=$(printf '%s' "${CONF_LINE#*=}"|sed -r 's/^[[:space:]]+//')
                eval "$BLOCK_ITEMS_NAME[\${#${BLOCK_ITEMS_NAME}[@]}]=\$ITEM_NAME"
                make_conf_key ITEM_NAME "$ITEM_NAME"
                eval "CONF_${BLOCK_NAME}_${ITEM_NAME}=\${ITEM_VALUE}"
            else
                warn_msg "第${CONF_LINENO}行，语法错误：$CONF_LINE"
            fi
        else
            warn_msg "第${CONF_LINENO}行，没有找到区块：$CONF_LINE"
        fi
    done < $1
    # 必需区块验证
    if [ ${#REQUIRED_BLOCK[@]} != '0' ];then
        error_exit "未找到区块配置：${REQUIRED_BLOCK[@]}"
    fi
}
# 生成配置数据键名
# @command make_conf_key $set_value $name
# @param $set_value         获取写入变量
# @param $name              配置名
# return 1|0
make_conf_key(){
    eval $1=$(printf '%s' "$2"|md5sum -t|awk '{print $1}')
}
# 获取配置项数据
# @command get_conf $set_value [$block] [$item]
# @param $set_value         获取写入变量
# @param $block             配置区块名，不指定获取所有区块数组
# @param $item              配置区块项名，不指定获取区块下所有项名
# return 1|0
get_conf(){
    if [ -n "$2" ];then
        local BLOCK_NAME
        make_conf_key BLOCK_NAME "$2"
        if [ -n "$3" ];then
            local ITEM_NAME
            make_conf_key ITEM_NAME "$3"
            eval "$1=\${CONF_${BLOCK_NAME}_${ITEM_NAME}}"
        else
            eval "$1=(\${CONF_BLOCK_ITEMS_${BLOCK_NAME}[@]})"
        fi
    else
        eval "$1=(\${CONF_BLOCK_NAMES[@]})"
    fi
}
# 循环配置项并调用函数
# @command each_conf $func [$block]
# @param $func              循环成功逐个调用函数
#                               未指定区块名调用函数参数：
#                                   $block_name     区块名
#                               指定区块名调用函数参数：
#                                   $item_name      区块内项名
#                                   $item_value     区块内项值
# @param $block             配置区块名，不指定则循环区块名
# return 1|0
each_conf(){
    local INDEX NAME
    if [ -n "$2" ];then
        local CONF_BLOCK_ITEMS CONF_ITEM_VALUE CINDEX
        get_conf CONF_BLOCK_ITEMS "$2"
        for ((INDEX=0; INDEX < ${#CONF_BLOCK_ITEMS[@]}; INDEX++)); do
            get_conf CONF_ITEM_VALUE "$2" "${CONF_BLOCK_ITEMS[$INDEX]}"
            $1 "${CONF_BLOCK_ITEMS[$INDEX]}" "$CONF_ITEM_VALUE"
        done
    else
        for ((INDEX=0; INDEX < ${#CONF_BLOCK_NAMES[@]}; INDEX++)); do
            $1 "${CONF_BLOCK_NAMES[$INDEX]}"
        done
    fi
}
# 获取文件全路径
# @command get_file_path $path $var_name $exist
# @param $path              文件名
# @param $var_name          全路径写入变量名
# @param $exist             验证文件存在
# return 1|0
# get_file_path(){
#     if [[ "$1" =~ ^[~/] ]];then
#         REALPATH_STR="$1"
#     elif [[ "$1" =~ ^[^~/] ]];then
#         REALPATH_STR="$SHELL_WROK_BASH_PATH/$1"
#     else
#         return 1
#     fi
#     if [ -n "$3" -a ! -e "$REALPATH_STR" ];then
#         return 1
#     fi
#     eval "$2=$REALPATH_STR"
# }
# 解析工具脚本参数
parse_shell_param DEFINE_TOOL_PARAMS CALL_INPUT_ARGVS
