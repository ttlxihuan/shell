#!/bin/bash
############################################################################
# 此脚本是代理命令过滤处理部分，当操作的目录在配置中指定则会终止脚本并提示
# 脚本不参与命令操作，主要提供给其它命令安全报警，当报警后终止执行其它命令即可保证命令执行的安全性
# 所代理命令必需是操作目录命令，否则特殊参数会被认为为目录进行判断处理
# 推荐使用方式：
#   (source safe-agent-run.sh; command $ARGVS_STR)
############################################################################
# 解析出禁止通配所有
DISABLED_ALL_ITEMS=()
# 解析出禁止相同路径
DISABLED_EQUAL_ITEMS=()
# 获取绝对路径
# @command get_realpath $pathname $title $get_file
# @param $pathname        一级目录名
# @param $title           脚本集标题名
# @param $get_file        获取文件
# return 0|1
get_realpath(){
    local _REALPATH
    if [ -d "${1}" ];then
        _REALPATH="${1}"
    else
        _REALPATH=$(cd "$(dirname "${1}")";pwd)'/'
    fi
    if [ "${_REALPATH:0:1}" != '/' ];then
        _REALPATH=$(cd "${_REALPATH}";pwd)'/'
    fi
    if [ -n "$3" -a ! -d "${1}" ];then
        _REALPATH="$_REALPATH$(basename "${1}")"
    fi
    eval $2=\$_REALPATH
}
# 匹配禁止操作目录
# @command match_disabled $source $target $wildcard
# @param $source            源目录
# @param $target            目标目录
# @param $wildcard          是否通配
# return 0|1
match_disabled(){
    local DISABLED_PATH
    if (( ${#1} < ${#2} ));then
        # 源目录长度小于于目标目录长度
        [ "$1" = "${2:0:${#1}}" ]
    elif (( ${#1} > ${#2} ));then
        # 源目录长度大于目标目录长度
        [ "$3" = '1' -a  "${1:0:${#2}}" = "$2" ]
    else
        # 目录长度相等
        [ "$1" = "$2" ]
    fi
    if [ $? = '0' ];then
        echo "${1} 在禁止删除区域 ${2}，终止操作！"
        exit 1
    fi
}
# 配置提取
while read -r _CONF;do
    # 跳过注释
    if [[ "${_CONF}" =~ ^[[:space:]]*(#.*)?$ ]];then
        continue
    fi
    # 提取目录
    FIND_PATH=$(find $_CONF -maxdepth 1 2>/dev/null | head -n 1)
    # 解析出来为空就跳过
    if [ -z "$FIND_PATH" ];then
        continue
    fi
    # 处理目录
    get_realpath "$FIND_PATH" FIND_PATH
    if [[ "$_CONF" =~ .*\*[[:space:]]*$ ]];then
        # 禁止所有
        DISABLED_ALL_ITEMS[${#DISABLED_ALL_ITEMS[@]}]="$FIND_PATH"
    else
        DISABLED_EQUAL_ITEMS[${#DISABLED_EQUAL_ITEMS[@]}]="$FIND_PATH"
    fi
done <<EOF
$(cat /etc/safe-rm.conf)
EOF
# 目录参数匹配
ARGVS_STR=''
# 去掉自动追加进来的参数
if [ "$_" = "${BASH_SOURCE[${#BASH_SOURCE[@]}-1]}" -a "$1" = '-i' ];then
    shift
fi
for AVG_ITEM; do
    # 参数组装，方便特殊参数
    ARV_ITEM=${AVG_ITEM//\\/\\\\}
    ARV_ITEM=${ARV_ITEM//\"/\\\"}
    ARGVS_STR="$ARGVS_STR "'"'$ARV_ITEM'"'
    # 选项参数不需要
    if [ "${AVG_ITEM:0:1}" = '-' ];then
        continue
    fi
    while read -r FIND_PATH; do
        # 处理目录
        get_realpath "$FIND_PATH" FIND_PATH 1
        for ((_INDEX=0;_INDEX<${#DISABLED_EQUAL_ITEMS[@]};_INDEX++));do
            match_disabled "$FIND_PATH" "${DISABLED_EQUAL_ITEMS[$_INDEX]}"
        done
        for ((_INDEX=0;_INDEX<${#DISABLED_ALL_ITEMS[@]};_INDEX++));do
            match_disabled "$FIND_PATH" "${DISABLED_ALL_ITEMS[$_INDEX]}" 1
        done
    done <<EOF
$(find "$AVG_ITEM" -maxdepth 1 2>/dev/null | head -n 1)
EOF
done
