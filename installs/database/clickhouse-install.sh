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
# Ubuntu 16.04+
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
DEFINE_RUN_PARAMS="
[-l, --only-localhost]允许仅本地连接服务器
"
# 加载基本处理
source "$(cd "$(dirname "${BASH_SOURCE[0]}")"; pwd)"/../../includes/install.sh || exit

# 初始化安装
init_install 21.1.9.41 "https://packages.clickhouse.com/tgz/stable/" 'clickhouse-server-\d+(\.\d+){3}' '\d+(\.\d+){3}'
#  限制空间大小（G）：编译目录、安装目录、内存
install_storage_require 4 3 4
# ************** 编译安装 ******************
# 下载clickhouse包
download_software https://packages.clickhouse.com/tgz/stable/clickhouse-common-static-$CLICKHOUSE_VERSION.tgz
run_msg ./install/doinst.sh
download_software https://packages.clickhouse.com/tgz/stable/clickhouse-common-static-dbg-$CLICKHOUSE_VERSION.tgz
run_msg ./install/doinst.sh
download_software https://packages.clickhouse.com/tgz/stable/clickhouse-server-$CLICKHOUSE_VERSION.tgz
# 创建默认密码
mkdirs ./etc/clickhouse-server/users.d
if [ ! -e ./etc/clickhouse-server/users.d/default-password.xml ];then
    cat > ./etc/clickhouse-server/users.d/default-password.xml <<conf
<clickhouse>
    <users>
        <default>
            <password remove='1' />
            <!-- default-password: root -->
            <password_sha256_hex>$(echo -n "root" | sha256sum | tr -d '-')</password_sha256_hex>
        </default>
    </users>
</clickhouse>
conf
fi
# 默认监听地址，指定为非仅本地
# 如果允许非本地连接则会创建配置文件 etc/clickhouse-server/config.d/listen.xml
# 配置文件中的监听地址可以自行调整
if [ "$ARGV_only_localhost" = '1' ];then
    INPUT_VAL='y'
else
    INPUT_VAL='n'
fi
run_msg ./install/doinst.sh <<CMD
$INPUT_VAL
CMD
download_software https://packages.clickhouse.com/tgz/stable/clickhouse-client-$CLICKHOUSE_VERSION.tgz
run_msg ./install/doinst.sh

# 创建用户组
# add_user clickhouse
# 配置文件处理
# info_msg "clickhouse 配置文件修改"

# 添加服务配置
SERVICES_CONFIG=()
SERVICES_CONFIG[$SERVICES_CONFIG_START_RUN]="/etc/init.d/clickhouse-server start"
SERVICES_CONFIG[$SERVICES_CONFIG_PID_FILE]=""
# 服务并启动服务
add_service SERVICES_CONFIG

info_msg "安装成功：$INSTALL_NAME-$CLICKHOUSE_VERSION"
