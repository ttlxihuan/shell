#!/bin/bash
# apt 工具修复脚本
# 主要针对apt异常修复而用
# 修复后即可正常使用apt
#
# 注意：ubuntu系统初始root账号可能没有密码无法切换到root账号，可以使用 sudo passwd root 修改，然后就可以正常切换到root
#

# 参数信息配置
SHELL_RUN_DESCRIPTION='apt工具修复'
SHELL_RUN_HELP='修复目录只针对https访问异常，其它异常修复不能保证可用性'
source "$(cd "$(dirname "${BASH_SOURCE[0]}")"; pwd)"/../includes/tool.sh || exit

error_exit '此脚本暂未开发完！'

if ! which apt 2>&1 >/dev/null;then
    error_exit '当前系统没有安装 apt 工具';
fi

# 清除缓存文件
# 适用于所有安装报：E: Sub-process /usr/bin/dpkg returned an error code (1)
rm -f /var/lib/dpkg/info/*

# 判断空间余量
APT_CACHE_PATH=/var/lib/dpkg/
if [ -n "$APT_CACHE_PATH" -a -d "$APT_CACHE_PATH" ];then
    APT_CACHE_PATH_USE=(`df_awk -ka $APT_CACHE_PATH|tail -n 1|awk '{print $1,$5,$6}'`)
    if [ "${APT_CACHE_PATH_USE[1]}" = '100%' ];then
        error_exit "yum 缓存目录 $APT_CACHE_PATH 所在挂载目录 ${APT_CACHE_PATH_USE[2]} 使用率已经是 ${APT_CACHE_PATH_USE[1]} ，请清理分区 ${APT_CACHE_PATH_USE[0]}"
    fi
fi

# ubuntu系统对较早版本停止了镜像支持，相关的目录会删除导致apt失败大量404，可以通过三方镜像来修复，但修复的版本有限
apt update

if [ $? != '0' ]; then
    HTTP_REPO_FILE='/etc/apt/sources.list.d/other.list'

    yum makecache
    if [ $? = '0' ];then
        info_msg 'yum 修复成功'
    else
        warn_msg 'yum 修复失败'
    fi
else
    info_msg 'yum 正常，无需修复！'
fi
