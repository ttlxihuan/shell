#!/bin/bash
# 所有调用脚本公共运行入口

# 搜索所有脚本
CURRENT_SHELL_BASH="$(cd "$(dirname "${BASH_SOURCE[0]}")"; pwd)"
RUN_SHELL_CACHE_FILE="$CURRENT_SHELL_BASH/temp/.run.cache"
# 解析配置数据
# @command search_shell_set $pathname $title
# @param $pathname        一级目录名
# @param $title           脚本集标题名
# return 0|1
search_shell_set(){
    local SHELL_FILE SHELL_DIR PREV_SHELL_DIR SHELL_FILE_NAME RUN_SHELL_HELP RUN_SHELL_LISTS=''
    local UPDATE_NUM=0
    live_msg "提取 $1 所有脚本信息：$UPDATE_NUM"
    for SHELL_FILE in $(cd $CURRENT_SHELL_BASH/$1;find ./ -maxdepth 1 -name '*.sh';find ./ -mindepth 2 -name '*.sh'|sort;);do
        SHELL_DIR=$(dirname $SHELL_FILE)
        if [ "$PREV_SHELL_DIR" != "$SHELL_DIR" -a "$SHELL_DIR" != '.' ];then
            RUN_SHELL_LISTS="$RUN_SHELL_LISTS${RUN_SHELL_LISTS:+\n}[${SHELL_DIR#*/}]\n"
            PREV_SHELL_DIR=$SHELL_DIR
        fi
        SHELL_FILE=$(cd $CURRENT_SHELL_BASH/$1/$SHELL_DIR; pwd)/$(basename $SHELL_FILE)
        # 异常脚本跳过
        RUN_SHELL_HELP=$(bash $SHELL_FILE -h 2>/dev/null)
        if [ $? != '0' ];then
            continue
        fi
        # 获取脚本名
        SHELL_FILE_NAME=$(basename $SHELL_FILE '.sh')
        NAME_LENGTH=${#SHELL_FILE_NAME}
        RUN_SHELL_LISTS="$RUN_SHELL_LISTS    $SHELL_FILE_NAME"
        RUN_SHELL_HELP="${RUN_SHELL_HELP#*Description:}"
        RUN_SHELL_HELP=$(echo -e -n "${RUN_SHELL_HELP%%Usage:*}"|sed -r -e 's/^\s+$//g' -e "s/^\s+/$(printf '%*s' 24)/g")
        if ((NAME_LENGTH < 20));then
            RUN_SHELL_HELP=${RUN_SHELL_HELP:$NAME_LENGTH+5}
        fi
        RUN_SHELL_LISTS="$RUN_SHELL_LISTS$RUN_SHELL_HELP\n"
        ((UPDATE_NUM++))
        live_msg "提取 $1 所有脚本信息：$UPDATE_NUM"
    done
    echo -e "$2" >> $RUN_SHELL_CACHE_FILE
    echo -e "$RUN_SHELL_LISTS" >> $RUN_SHELL_CACHE_FILE
    live_msg
}
# 缓存脚本信息
# @command cache_shell_info
# return 0|1
cache_shell_info(){
    search_shell_set installs '可用安装脚本名：'
    search_shell_set tools '可用工具脚本名：'
    info_msg '脚本信息更新完成'
}
# 初始化脚本信息
# @command init_shell
# return 0|1
init_shell(){
    # 首次自动写缓存
    if [ ! -e $RUN_SHELL_CACHE_FILE ];then
        info_msg '脚本初始化处理中，将生成脚本使用名单并缓存！';
        cache_shell_info
    fi
    SHELL_RUN_HELP="
脚本：
    bash $0 [options]
        options   可用选项

调用脚本：
    bash $0 script-name [options]
        script-name     脚本名
        options         脚本所需参数，此参数会全部转移到调用的脚本上

$(cat $RUN_SHELL_CACHE_FILE)

1、统一入口可以优化化目录结构和统一操作途径
2、此入口并非唯一操作入口，也可以通过调用内置直接脚本执行
"
}

# 参数信息配置
SHELL_RUN_DESCRIPTION='运行脚本，调用内置安装和工具脚本统一入口'
DEFINE_RUN_PARAMS='
[script-name, {required_without:ARGV_update}]指定执行的脚本名
[-u, --update]更新缓存信息。
#一般不需要更新，脚本在首次会自动更新
'
if (( $# == 0 ));then
    ARGV_help=1
fi

source ${CURRENT_SHELL_BASH}/includes/tool.sh $1 || exit

if [ "$ARGV_update" = '1' ];then
    info_msg '更新脚本信息'
    rm -f $RUN_SHELL_CACHE_FILE
    cache_shell_info
else
    source "$SHELL_WROK_INCLUDES_PATH/argvs.sh" || exit
    eval run_shell ${CALL_SAFE_ARGVS[@]}
fi
