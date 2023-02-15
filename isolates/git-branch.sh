#!/bin/bash
############################################################################
# 此脚本用来快速管理git分支，创建删除各重命名后会自动推送到远程版本库中
# 远程版本库需要开放版本库操作权限
#
# 推荐使用方式：（独立运行脚本）
# bash git-branch.sh action name
############################################################################

# 输出帮助信息
show_help(){
    echo "
git分支管理工具，分支变动将自动推送到远程版本库中
当前目录必需是git版本库工作目录。

命令：
    $(basename "${BASH_SOURCE[0]}") action name [-h|-?]

参数：
    action              分支操作名
                            create  创建新分支（合并当前分支内容）
                            delete  删除当前分支
                            rename  修改当前分支名
                            pull    拉取远程分支
    name                分支名
    
选项：
    -w path             git工作目录，不指定为当前目录
    -h, -?              显示帮助信息

说明：
    此脚本用来快速创建删除重命名或拉取git分支，本地分支变动会推送到远程版本库中。
    远程版本库需要开放分支管理权限，比如在github系统。
"
    exit 0
}
# 输出错误信息并终止运行
show_error(){
    echo "[error] $1"
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
GIT_PATH=./
for((INDEX=1; INDEX<=$#; INDEX++));do
    case "${@:$INDEX:1}" in
        -h|-\?)
            show_help
        ;;
        -w)
            GIT_PATH=${@:((++INDEX)):1}
        ;;
        *)
            if [ -z "$ACTION_NAME" ];then
                ACTION_NAME=${@:$INDEX:1}
            elif [ -z "$BRANCH_NAME" ];then
                BRANCH_NAME=${@:$INDEX:1}
            else
                show_error "未知参数选项：${@:$INDEX:1}"
            fi
        ;;
    esac
done

if [ -z "$ACTION_NAME" ];then
    ACTION_NAME='pull'
fi

if [ -z "$BRANCH_NAME" ];then
    show_error "请指定分支名"
fi

cd "$GIT_PATH"

if [ ! -d './.git' ];then
    show_error "请在git工作目录中运行此脚本"
fi

# 获取当前分支
CURRENT_NAME=$(git branch --show-current 2>/dev/null)

if [ -z "$CURRENT_NAME" ];then
    show_error "无法获取当前分支名，请核实git工作目录是否正常"
fi

case "$ACTION_NAME" in
    create)
        git branch "$BRANCH_NAME"
    ;;
    delete)
        if [ "$CURRENT_NAME" = "$BRANCH_NAME" ];then
            # 不能在当前分支下删除当前分支
            git checkout "$(git branch|awk '{if($1 != "*"){print $1}}'|head -n 1)"
        fi
        git branch -d "$BRANCH_NAME"
        git push origin -d "$BRANCH_NAME"
    ;;
    rename)
        git branch -m "$CURRENT_NAME" "$BRANCH_NAME"
        git push origin -d "$CURRENT_NAME"
    ;;
    pull)
        git fetch origin "$BRANCH_NAME"
        git checkout -b "$BRANCH_NAME" "origin/$BRANCH_NAME"
    ;;
    *)
        show_error "未知分支操作名：${ACTION_NAME}"
    ;;
esac

if [ "$ACTION_NAME" != "delete" -a "$ACTION_NAME" != "pull" ];then
    # 判断远程是否有这个分支
    if git fetch origin "$BRANCH_NAME" 2>/dev/null;then
        # 重新设置与远程分支基准，否则推送分支可能报：error: failed to push some refs to
        git pull --rebase origin "$BRANCH_NAME"
    fi
    # 切换到新分支
    git checkout "$BRANCH_NAME"
    # 推送新分支
    git push -u origin "$BRANCH_NAME"
fi
