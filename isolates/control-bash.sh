#!/bin/bash
############################################################################
# 此脚本主要安装独立便捷脚本，便捷脚本来自项目内置脚本
# 请确保磁盘空间和写权限
#
# 推荐使用方式：（独立运行脚本）
# bash control-bash.sh action name
############################################################################

# 默认数据
DEFAULT_INSTALL_PATH=/usr/bin/
# 输出帮助信息
show_help(){
    echo "
便捷脚本工具管理

命令：
    $(basename "${BASH_SOURCE[0]}") action path [-h|-?]

参数：
    action              操作名
                            install     安装内置脚本集
                            uninstall   移除安装的内置脚本集
                            reinstall   重新安装内置脚本集
                            show        展示便捷脚本集信息
    path                安装目录，默认：${DEFAULT_INSTALL_PATH}
    
选项：
    -h, -?              显示帮助信息

说明：
    此脚本主要安装独立便捷脚本，便捷脚本来自项目内置脚本。
"
    exit 0
}
# 输出错误信息并终止运行
show_error(){
    echo "[error] $1" >&2
    exit 1
}
if_error(){
    if [ $? != 0 ];then
        show_error "$1"
    fi
}

# 参数处理
if [ $# = 0 ];then
    show_help
fi
for((INDEX=1; INDEX<=$#; INDEX++));do
    case "${@:$INDEX:1}" in
        -h|-\?)
            show_help
        ;;
        *)
            if [ -z "$ACTION_NAME" ];then
                ACTION_NAME=${@:$INDEX:1}
            elif [ -z "$INSTALL_PATH" ];then
                INSTALL_PATH=${@:$INDEX:1}
            else
                show_error "未知参数选项：${@:$INDEX:1}"
            fi
        ;;
    esac
done

if [ -z "$INSTALL_PATH" ];then
    INSTALL_PATH=${DEFAULT_INSTALL_PATH}
fi

INSTALL_PATH="$(cd "$INSTALL_PATH";pwd)"

if [ ! -d "$INSTALL_PATH" ];then
    show_error "安装目录不存在"
fi

cd "$(dirname "${BASH_SOURCE[0]}")"

# 执行处理
find ./ -name '*.sh'|while read LINE;do
    HELP_INFO=$(bash "$LINE" -h 2>/dev/null|head -n 2|tail -n 1)
    INSTALL_FILE="$INSTALL_PATH/${LINE%.*}"
    COMMAND_NAME=$(basename "$LINE" '.sh')
    echo -n "[info] ${COMMAND_NAME} $(printf '%*s' $((${#COMMAND_NAME} >=20 ? 1 : 20 - ${#COMMAND_NAME})))"
    if [ -z "$HELP_INFO" ];then
        echo '[不支持]'
        continue;
    fi
    echo -n "$HELP_INFO "
    case "$ACTION_NAME" in
        install)
            if [ ! -e "$INSTALL_FILE" ];then
                cp -f "$LINE" "$INSTALL_FILE" 2>&1 &>stdout.log
                if [ $? != 0 ];then
                    echo '[安装失败]'
                    cat stdout.log
                else
                    echo '[安装成功]'
                fi
            else
                echo '[已安装]'
            fi
        ;;
        uninstall)
            if [ -e "$INSTALL_FILE" ];then
                rm -f "$INSTALL_FILE" 2>&1 &>stdout.log
                if [ $? != 0 ];then
                    echo '[移除失败]'
                    cat stdout.log
                else
                    echo '[移除成功]'
                fi
            else
                echo '[未安装]'
            fi
        ;;
        reinstall)
            cp -f "$LINE" "$INSTALL_FILE" 2>&1 &>stdout.log
            if [ $? != 0 ];then
                echo '[重装失败]'
                cat stdout.log
            else
                echo '[重装成功]'
            fi
        ;;
        show)
            echo ''
        ;;
        *)
            show_error "请指定正确的操作名 ${ACTION_NAME}"
        ;;
    esac
    if [ -e stdout.log ];then
        rm -f stdout.log
    fi
    if [ -e "$INSTALL_FILE" ];then
        chmod +x "$INSTALL_FILE"
    fi
done
