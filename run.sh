#!/bin/bash
# 所有调用脚本公共运行入口

# 搜索所有脚本
CURRENT_SHELL_BASH=$(cd $(dirname ${BASH_SOURCE[0]}); pwd)
RUN_SHELL_CACHE_FILE="$CURRENT_SHELL_BASH/temp/.run.cache"
# 解析配置数据
# @command search_shell_set $pathname $title
# @param $pathname        一级目录名
# @param $title           脚本集标题名
# return 0|1
search_shell_set(){
    local SHELL_FILE SHELL_DIR PREV_SHELL_DIR SHELL_FILE_NAME SPACE_NUM=20 RUN_SHELL_LISTS=''
    for SHELL_FILE in $(cd $CURRENT_SHELL_BASH/$1;find ./ -maxdepth 1 -name '*.sh';find ./ -mindepth 2 -name '*.sh'|sort;);do
        SHELL_DIR=$(dirname $SHELL_FILE)
        if [ "$PREV_SHELL_DIR" != "$SHELL_DIR" -a "$SHELL_DIR" != '.' ];then
            RUN_SHELL_LISTS="$RUN_SHELL_LISTS${RUN_SHELL_LISTS:+\n}[${SHELL_DIR#*/}]\n"
            PREV_SHELL_DIR=$SHELL_DIR
        fi
        SHELL_FILE=$(cd $1/$SHELL_DIR; pwd)/$(basename $SHELL_FILE)
        # 获取脚本名
        SHELL_FILE_NAME=$(basename $SHELL_FILE '.sh')
        NAME_LENGTH=$(echo -n $SHELL_FILE_NAME|wc -m)
        RUN_SHELL_LISTS="$RUN_SHELL_LISTS    $SHELL_FILE_NAME"
        if ((NAME_LENGTH >= SPACE_NUM));then
            RUN_SHELL_LISTS="$RUN_SHELL_LISTS\n"
        fi
        RUN_SHELL_LISTS=$RUN_SHELL_LISTS$(printf '%*s' $((NAME_LENGTH >= SPACE_NUM ? SPACE_NUM : SPACE_NUM-NAME_LENGTH)))$(bash $SHELL_FILE -h|head -2|tail -1|sed -r 's/^\s+//')"\n"
    done
    echo -e "$2" >> $RUN_SHELL_CACHE_FILE
    echo -e "$RUN_SHELL_LISTS" >> $RUN_SHELL_CACHE_FILE
}
# 首次自动写缓存
if [ ! -e $RUN_SHELL_CACHE_FILE ];then
    search_shell_set installs '可用安装脚本名：'
    search_shell_set tools '可用工具脚本名：'
fi
# 参数信息配置
SHELL_RUN_DESCRIPTION='运行脚本，调用内置安装和工具脚本统一入口'
SHELL_RUN_HELP="
脚本：
    bash $0 [options]
        options   可用选项

调用脚本：
    bash $0 name [options]
        name      脚本名
        options   脚本所需参数，此参数会全部转移到调用的脚本上

$(cat $RUN_SHELL_CACHE_FILE)

脚本的目录结构：
    etc/        配置文件目录
    includes/   公用文件目录
    install/    安装脚本目录
    tools/      工具脚本目录
    temp/       临时缓存目录，存储脚本使用的缓存文件和下载编译文件

1、统一入口可以优化化目录结构和统一操作途径
2、此入口并非唯一操作入口，也可以通过调用内置直接脚本执行
"
DEFINE_TOOL_PARAMS='
[name, {required_without:ARGV_update}]指定执行的脚本名
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
    bash $0 >/dev/null
    info_msg '脚本信息更新完成'
else
    RUN_SHELL_FILE=$(find $CURRENT_SHELL_BASH/installs $CURRENT_SHELL_BASH/tools -name $ARGU_name'.sh')    
    if [ -n "$RUN_SHELL_FILE" ];then
        RUN_SHELL_FILE=$(cd $(dirname $RUN_SHELL_FILE); pwd)/$(basename $RUN_SHELL_FILE)
        bash $RUN_SHELL_FILE ${@:2}
    else
        error_exit "脚本 $ARGU_name 不存在，查看可以通过运行：bash $0 -h"
    fi
fi
