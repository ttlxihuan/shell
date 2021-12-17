#!/bin/bash
#
# clickhouse快速编译安装shell脚本
# 官方中文文档：https://clickhouse.com/docs/zh/
#
# 安装命令
# bash clickhouse-install.sh new
# bash clickhouse-install.sh $verions_num
# 
# 查看最新版命令
# bash clickhouse-install.sh
#
# 可运行系统：
# CentOS 6.4+
# Ubuntu 15.04+
#
# ClickHouse 是一个列式存储的数据库，主要用于大数据统计查询
# 列式存储读取不像行式存储那样需要读取整行数据，列式是按列读取会节省读取I/O量从而提升查询量，在CPU或内存处理层并不会有太大的提升
# ClickHouse 不支持事务、支持标准SQL（子查询和部分函数不支持），建议批量写入（比如：1000条起，每秒写一次）、每秒最多查询100次、避免删除和修改操作。
# ClickHouse 支持集群分片和副本复制和分布式查询。
# ClickHouse 存储的字段尽量小，过大的字段会影响查询速度（字段过大会增加I/O量从而影响查询性能）
#
# 查询在内存中速度会很快但内存空间有限且不可持久保存又不得不使用磁盘持久巨量保存，
# 所以查询主要瓶颈是磁盘读取速度限制。磁盘读取是以扇区为单位读取的，扇区大小和数量直接影响读取速度，减少字段体量是查询性能提升的一个重要指标。
#
# 注意：非编译安装需要CPU支持 SSE 4.2 指令集，编译安装时可以禁用SSE 4.2或AArch64 cpu完成安装。
#
####################################################################################
##################################### 安装处理 #####################################
####################################################################################
# 定义安装参数
DEFINE_INSTALL_PARAMS="
[-a, --api='mysql']指定启用接口，支持：http、mysql
# JDBC、ODBC两个需要外加驱动包，暂时不支持
[-p, --api-port='']指定接口端口号，默认http是8123、mysql是9004
"
# 加载基本处理
source $(cd $(dirname ${BASH_SOURCE[0]}); pwd)/../../includes/install.sh || exit

error_exit '此脚本暂未开发完！'

# 初始化安装
init_install 20.0.0.0 "https://repo.clickhouse.com/tgz/stable/" 'clickhouse-server-\d+(\.\d+){3}' '\d+(\.\d+){3}'
#  限制空间大小（G）：编译目录、安装目录、内存
install_storage_require 1 1 1
# ************** 相关配置 ******************
# 编译初始选项（这里的指定必需有编译项）
CONFIGURE_OPTIONS="--prefix=$INSTALL_PATH$CLICKHOUSE_VERSION --user=clickhouse --group=clickhouse "
# 编译增加项（这里的配置会随着编译版本自动生成编译项）
ADD_OPTIONS=' '$ARGV_options
# ************** 编译安装 ******************
# 下载nginx包
download_software http://$NGINX_HOST/download/nginx-$NGINX_VERSION.tar.gz

# 架构支持处理
grep -q sse4_2 /proc/cpuinfo && echo "SSE 4.2 supported" || echo "SSE 4.2 not supported"

# 解析选项
parse_options CONFIGURE_OPTIONS $ADD_OPTIONS
# 安装依赖
info_msg "安装相关已知依赖"



# 编译安装
configure_install $CONFIGURE_OPTIONS
# 创建用户组
add_user clickhouse
# 配置文件处理
info_msg "clickhouse 配置文件修改"


# 启动服务


info_msg "安装成功：$INSTALL_NAME-$ELASTICSEARCH_VERSION"



