#!/bin/bash
############################################################################
# 此脚本是代理命令过滤处理部分，当操作的目录在配置中指定则会终止脚本并提示
# 脚本不参与命令操作，主要提供给其它命令安全报警，当报警后终止执行其它命令即可保证命令执行的安全性
# 所代理命令必需是操作目录命令，否则特殊参数会被认为为目录进行判断处理
# 推荐使用方式：
#   (source safe-agent-run.sh && command $@)
############################################################################
# 解析出禁止通配所有
DISABLED_ALL_ITEMS=()
# 解析出禁止相同路径
DISABLED_EQUAL_ITEMS=()
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
    # 非根目录开始
    if [ "${FIND_PATH:0:1}" != '/' ];then
        if [ -d "${FIND_PATH}" ];then
            FIND_PATH=$(cd "${FIND_PATH}";pwd)'/'
        else
            FIND_PATH=$(cd "$(dirname "${FIND_PATH}")";pwd)/$(basename "${FIND_PATH}")
        fi
    fi
    if [[ "$_CONF" =~ .*\*[[:space:]]*$ ]];then
        # 禁止所有
        DISABLED_ALL_ITEMS[${#DISABLED_ALL_ITEMS[@]}]=$(dirname "${FIND_PATH}")'/'
    else
        DISABLED_EQUAL_ITEMS[${#DISABLED_EQUAL_ITEMS[@]}]="$FIND_PATH"
    fi
done <<EOF
$(cat /etc/safe-rm.conf)
EOF
# 参数解析处理，如果有涉及删除禁止目录将终止命令执行
for AVG_ITEM; do
    # 选项参数不需要
    if [  "${AVG_ITEM:0:1}" != '-' ];then
            while read -r FIND_PATH; do
                # 非根目录开始
                if [ "${FIND_PATH:0:1}" != '/' ];then
                    if [ -d "${FIND_PATH}" ];then
                        FIND_PATH=$(cd "${FIND_PATH}";pwd)'/'
                    else
                        FIND_PATH=$(cd "$(dirname "${FIND_PATH}")";pwd)/$(basename "${FIND_PATH}")
                    fi
                elif [ -d "${FIND_PATH}" ] && [[ "${FIND_PATH}" != */ ]];then
                    FIND_PATH=$FIND_PATH'/'
                fi
                for ((_INDEX=0;_INDEX<${#DISABLED_EQUAL_ITEMS[@]};_INDEX++));do
                    if [  "${DISABLED_EQUAL_ITEMS[$_INDEX]}" = "$FIND_PATH" ];then
                        echo "操作 $AVG_ITEM 在禁止区域 ${DISABLED_EQUAL_ITEMS[$_INDEX]}，终止操作！"
                        exit 1
                    fi
                done
                for ((_INDEX=0;_INDEX<${#DISABLED_ALL_ITEMS[@]};_INDEX++));do
                    if [  "${DISABLED_ALL_ITEMS[$_INDEX]}" = "${FIND_PATH:0:${#DISABLED_ALL_ITEMS[$_INDEX]}}" ];then
                        echo "操作 $AVG_ITEM 在禁止区域 ${DISABLED_ALL_ITEMS[$_INDEX]}，终止操作！"
                        exit 1
                    fi
                done
            done <<EOF
$(find "$AVG_ITEM" -maxdepth 1 2>/dev/null | head -n 1)
EOF
    fi
done