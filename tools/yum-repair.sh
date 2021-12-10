#!/bin/bash
# yum 工具修复脚本
# 主要针对yum异常修复而用
# 修复后即可正常使用yum

# 参数信息配置
SHELL_RUN_DESCRIPTION='yum工具修复'
SHELL_RUN_HELP='修复目录只针对https访问异常，其它异常修复不能保证可用性'
source $(cd $(dirname ${BASH_SOURCE[0]}); pwd)/../includes/tool.sh || exit

if ! which yum 2>&1 >/dev/null;then
    error_exit '当前系统没有安装 yum 工具';
fi
# 判断空间余量
YUM_CACHE_PATH=$(cat /etc/yum.conf|grep -P '^cachedir\s*=\s*'|sed -r 's/.*?=\s*//'|sed -r 's/\$[^\/]+\/?//g')
if [ -n "$YUM_CACHE_PATH" -a -d "$YUM_CACHE_PATH" ];then
    YUM_CACHE_PATH_USE=(`df_awk -ka $YUM_CACHE_PATH|tail -n 1|awk '{print $1,$5,$6}'`)
    if [ "${YUM_CACHE_PATH_USE[1]}" = '100%' ];then
        error_exit "yum 缓存目录 $YUM_CACHE_PATH 所在挂载目录 ${YUM_CACHE_PATH_USE[2]} 使用率已经是 ${YUM_CACHE_PATH_USE[1]} ，请清理分区 ${YUM_CACHE_PATH_USE[0]}"
    fi
fi

info_msg '清除 yum 缓存'
yum clean all

info_msg '重新生成 yum 缓存'
yum makecache

if [ $? != '0' ]; then
    HTTP_REPO_FILE='/etc/yum.repos.d/CentOS-Base-http.repo'
    info_msg '尝试添加 http 镜像生成 yum 缓存 '$HTTP_REPO_FILE' ，修复成功后可手动删除生成的镜像文件'
    echo -e '
# 以下是收集可用http站点，主要针对yum报错：problem making ssl connection
# 因为openssl不可用或版本太低，需要更新，但大多数镜像使用的是https
# 而访问https依赖openssl，所以yum、wget、curl 等都不能正常访问https地址
# 通过以下镜像更新安装后就可以正常访问https地址，此文件就可删除或者保留
#
# 文件直接复制到yum配置目录中即，注意系统版本
# 证书更新 yum install ca-certificates
# 工具更新 yum install wget curl
#
# 如果以下镜像不能使用可以去官方镜像表中查找合适的镜像地址
# CentOS 官方镜像地址表：http://mirror-status.centos.org/
#
# 搜狐 http://mirrors.sohu.com/，支持CentOS 6+
# 中国科学技术大学 http://mirrors.ustc.edu.cn/ ，支持CentOS 7+
# 网易 http://mirrors.163.com/ ，支持CentOS 7+
# 欧洲镜像源 http://mirror.nsc.liu.se ，支持 CentOS 5+

[base]
name=CentOS-$releasever - Base - mirrors.aliyun.com
failovermethod=priority
baseurl=http://mirrors.sohu.com/centos/$releasever/os/$basearch/
        http://mirrors.ustc.edu.cn/centos/$releasever/os/$basearch/
        http://mirrors.163.com/centos/$releasever/os/$basearch/
        http://mirror.nsc.liu.se/centos-store/centos/$releasever/os/$basearch/
gpgcheck=1
gpgkey=http://mirrors.sohu.com/centos/$releasever/os/$basearch/RPM-GPG-KEY-CentOS-$releasever
       http://mirrors.ustc.edu.cn/centos/$releasever/os/$basearch/RPM-GPG-KEY-CentOS-$releasever
       http://mirrors.163.com/centos/$releasever/os/$basearch/RPM-GPG-KEY-CentOS-$releasever
       http://mirror.nsc.liu.se/centos-store/centos/$releasever/os/$basearch/RPM-GPG-KEY-CentOS-$releasever

#released updates 
[updates]
name=CentOS-$releasever - Updates - mirrors.aliyun.com
failovermethod=priority
baseurl=http://mirrors.sohu.com/centos/$releasever/updates/$basearch/
        http://mirrors.ustc.edu.cn/centos/$releasever/updates/$basearch/
        http://mirrors.163.com/centos/$releasever/updates/$basearch/
        http://mirror.nsc.liu.se/centos-store/centos/$releasever/updates/$basearch/
gpgcheck=1
gpgkey=http://mirrors.sohu.com/centos/$releasever/os/$basearch/RPM-GPG-KEY-CentOS-$releasever
       http://mirrors.ustc.edu.cn/centos/$releasever/os/$basearch/RPM-GPG-KEY-CentOS-$releasever
       http://mirrors.163.com/centos/$releasever/os/$basearch/RPM-GPG-KEY-CentOS-$releasever
       http://mirror.nsc.liu.se/centos-store/centos/$releasever/os/$basearch/RPM-GPG-KEY-CentOS-$releasever

#additional packages that may be useful
[extras]
name=CentOS-$releasever - Extras - mirrors.aliyun.com
failovermethod=priority
baseurl=http://mirrors.sohu.com/centos/$releasever/extras/$basearch/
        http://mirrors.ustc.edu.cn/centos/$releasever/extras/$basearch/
        http://mirrors.163.com/centos/$releasever/extras/$basearch/
        http://mirror.nsc.liu.se/centos-store/centos/$releasever/extras/$basearch/
gpgcheck=1
gpgkey=http://mirrors.sohu.com/centos/$releasever/os/$basearch/RPM-GPG-KEY-CentOS-$releasever
       http://mirrors.ustc.edu.cn/centos/$releasever/os/$basearch/RPM-GPG-KEY-CentOS-$releasever
       http://mirrors.163.com/centos/$releasever/os/$basearch/RPM-GPG-KEY-CentOS-$releasever
       http://mirror.nsc.liu.se/centos-store/centos/$releasever/os/$basearch/RPM-GPG-KEY-CentOS-$releasever

' > $HTTP_REPO_FILE
    yum makecache
    if [ $? = '0' ];then
        info_msg 'yum 修复成功'
    else
        warn_msg 'yum 修复失败'
    fi
else
    info_msg 'yum 正常，无需修复！'
fi
