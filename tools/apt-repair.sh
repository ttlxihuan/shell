#!/bin/bash
# apt 工具修复脚本
# 主要针对apt异常修复而用
# 修复后即可正常使用apt

# 参数信息配置
SHELL_RUN_DESCRIPTION='apt工具修复'
SHELL_RUN_HELP='修复目录只针对https访问异常，其它异常修复不能保证可用性'
source $(cd $(dirname ${BASH_SOURCE[0]}); pwd)/../includes/tool.sh || exit

error_exit '此脚本暂未开发完！'

if ! which apt 2>&1 >/dev/null;then
    error_exit '当前系统没有安装 apt 工具';
fi

# 清除缓存文件
# 适用于所有安装报：E: Sub-process /usr/bin/dpkg returned an error code (1)
rm -f /var/lib/dpkg/info/*

# 判断空间余量
YUM_CACHE_PATH=/var/lib/dpkg/
if [ -n "$YUM_CACHE_PATH" -a -d "$YUM_CACHE_PATH" ];then
    YUM_CACHE_PATH_USE=(`df_awk -ka $YUM_CACHE_PATH|tail -n 1|awk '{print $1,$5,$6}'`)
    if [ "${YUM_CACHE_PATH_USE[1]}" = '100%' ];then
        error_exit "yum 缓存目录 $YUM_CACHE_PATH 所在挂载目录 ${YUM_CACHE_PATH_USE[2]} 使用率已经是 ${YUM_CACHE_PATH_USE[1]} ，请清理分区 ${YUM_CACHE_PATH_USE[0]}"
    fi
fi

info_msg '清除 apt 缓存'
apt clean all

info_msg '重新生成 apt 缓存'
apt makecache

if [ $? != '0' ]; then
 
    yum makecache
    if [ $? = '0' ];then
        info_msg 'yum 修复成功'
    else
        warn_msg 'yum 修复失败'
    fi
else
    info_msg 'yum 正常，无需修复！'
fi
