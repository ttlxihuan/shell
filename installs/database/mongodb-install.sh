#!/bin/bash
#
# mongoDB快速编译安装shell脚本
#
# 安装命令
# bash mongodb-install.sh new
# bash mongodb-install.sh $verions_num
# 
# 查看最新版命令
# bash mongodb-install.sh
#
# 可运行系统：
# CentOS 6.4+
# Ubuntu 15.04+
#
# 安装文档地址： https://docs.mongodb.com/manual/administration/install-on-linux/
# 配置文件地址：https://docs.mongodb.com/manual/reference/configuration-options/
#
# 报错：
#   1、gcc: error: unrecognized command line option '-fstack-protector-strong'
#       gcc 版本在4.9+版本中支持 -fstack-protector-strong ，确认下版本
#   2、g++: fatal error: Killed signal terminated program cc1plus
#       内存空间不够，排查适当增加，建议在4G+
#   3、error: unnecessary parentheses in declaration of 'assert_arg' [-Werror=parentheses]
#       gcc 版本过高，适当降低，建议版本不能超过 2.0.0 个版本序号，可以考虑在要求gcc版本上+1.0.0 
#
# 注意：
#   1、mongodb安装需要比较多的内存建议内存4G+，如果内存不足容易出现编译进程被kill报出类似错 
#   2、mongodb安装需要比较多的磁盘空间，一般建议空余空间在35G+，如果空间不足容易报类似错 No space left on device
#   3、mongodb安装依赖比较高的gcc，通过脚本安装时间比较长
#   4、多个不同版本的so动态库响应加载时需要调整动态库管理，打开 /etc/ld.so.conf 去掉不需要的动态库目录，然后运行 ldconfig ，类似错误提示：./bin/mongod: /usr/local/gcc/5.1.0/lib64/libstdc++.so.6: version `GLIBCXX_3.4.22' not found (required by ./bin/mongod)
#
#
####################################################################################
##################################### 安装处理 #####################################
####################################################################################
# 定义安装类型
DEFINE_INSTALL_TYPE='scons'
# 加载基本处理
source "$(cd "$(dirname "${BASH_SOURCE[0]}")"; pwd)"/../../includes/install.sh || exit
# 初始化安装
init_install '3.0.0' "http://downloads.mongodb.org.s3.amazonaws.com/current.json" 'mongodb-src-r\d+\.\d+\.\d+\.tar\.gz'
#  限制空间大小（G）：编译目录、安装目录、内存
install_storage_require 15 15 6
# ************** 相关配置 ******************
# 编译初始选项（这里的指定必需有编译项）
CONFIGURE_OPTIONS="--prefix=$INSTALL_PATH$MONGODB_VERSION $ARGV_options"
# ************** 编译安装 ******************
# 下载mongodb包
download_software https://fastdl.mongodb.org/src/mongodb-src-r$MONGODB_VERSION.tar.gz
# 暂存编译目录
MONGODB_CONFIGURE_PATH=`pwd`
# 安装依赖
info_msg "安装相关已知依赖"
# 获取编辑安装的依赖要求
GCC_MIN_VERSION=`grep -iP 'gcc\s+\d+(\.\d+)+' ./docs/building.md|grep -oP '\d+(\.\d+)+'|tail -n 1`
PYTHON_MIN_VERSION=`grep -iP 'Python\s+\d+(\.\d+)+' ./docs/building.md|grep -oP '\d+(\.\d+)+'|tail -n 1`
if [ -n "$GCC_MIN_VERSION" ];then
    # 安装验证 gcc
    repair_version GCC_MIN_VERSION
    install_gcc "$GCC_MIN_VERSION"
else
    warn_msg '获取 gcc 最低版本号失败'
fi
if [ -n "$PYTHON_MIN_VERSION" ];then
    # 安装验证 python
    repair_version PYTHON_MIN_VERSION
    install_python "$PYTHON_MIN_VERSION"
else
    warn_msg '获取 python 最低版本号失败'
    install_python
fi

# 安装验证 openssl
install_openssl

# 安装验证 curl
install_curl

# lzma 依赖 mongodb-5.0.3
# Cannot find system library 'lzma' required for use with libunwind
# package_manager_run install libunwind-devel
cd $MONGODB_CONFIGURE_PATH
# 编译安装
if [ -e "etc/pip/compile-requirements.txt" ];then
    info_msg "$PYTHON_COMMAND_NAME pip 自动安装依赖"
    $PIP_NAME install -r etc/pip/compile-requirements.txt
    if (($? != 0));then
        $PYTHON_COMMAND_NAME -m pip install -r etc/pip/compile-requirements.txt
    fi
    info_msg '$PYTHON_COMMAND_NAME 编译安装 mongobd'
    if grep -q '\-\-prefix' docs/building.md;then
        run_msg $PYTHON_COMMAND_NAME buildscripts/scons.py $CONFIGURE_OPTIONS install -j $INSTALL_THREAD_NUM
    else
        run_msg $PYTHON_COMMAND_NAME buildscripts/scons.py install-all PREFIX=$INSTALL_PATH$MONGODB_VERSION $ARGV_options -j $INSTALL_THREAD_NUM
    fi
    if_error '安装失败：mongodb'
else
    if [ -e 'buildscripts/requirements.txt' ];then
        $PYTHON_COMMAND_NAME -m pip install -r buildscripts/requirements.txt
    fi
    SCONS_VERSION=`grep -iP 'scons\s+\d+(\.\d+)+' ./docs/building.md|grep -oP '\d+(\.\d+)+'|tail -n 1`
    if [ -n "$SCONS_VERSION" ];then
        SCONS_CURRENT_VERSION=`scons -v 2>&1|grep -oP '\d+(\.\d+)+'|tail -n 1`
        if ! echo "$SCONS_VERSION"|grep -qP '^\d+\.\d+\.\d+$';then
            SCONS_VERSION=$SCONS_VERSION".1"
        fi
        if if_version "$SCONS_VERSION" '>' "$SCONS_CURRENT_VERSION"; then
            MONGODB_INSTALL_PATH=`pwd`
            # 安装最近版本
            download_software "http://prdownloads.sourceforge.net/scons/scons-$SCONS_VERSION.tar.gz"
            # 编译安装
            $PYTHON_COMMAND_NAME setup.py install
            # 编译安装
            if_error '安装失败：scons'
            cd $MONGODB_INSTALL_PATH
        else
            info_msg 'Scons OK'
        fi
        info_msg 'scons 编译安装 mongobd'
        run_msg scons all -j $INSTALL_THREAD_NUM
        run_msg scons $CONFIGURE_OPTIONS install
    else
        run_msg $PYTHON_COMMAND_NAME buildscripts/scons.py all $CONFIGURE_OPTIONS -j $INSTALL_THREAD_NUM
    fi
    if_error '安装失败：mongodb'
fi
# 创建用户组
add_user mongodb
cd $INSTALL_PATH$MONGODB_VERSION

info_msg "mongodb 配置文件修改"
# 配置文件处理
mkdirs etc

if if_version $MONGODB_VERSION '>=' 4.2.0;then
    NET_TLS_CONFIG='
    # 4.2及之后版，弃用ssl协议
    # 与以前的ssl选项大体相同的功能
    tls:
        # 指定 tls 模式：
        #   disabled    禁用tls
        #   allowTLS    集群之间连接不使用tls，服务器接受tls和非tls
        #   preferTLS   集群之间连接使用tls，服务器接受tls和非tls
        #   requireTLS  集群仅使用并接受 TLS 加密连接
        mode: disabled

        # 指定tls证书pem文件
        # 仅 Linux/BSD 系统可用，且与certificateSelector选项互斥（二选一）
        # certificateKeyFile: <string>

        # 指定证书密码
        # certificateKeyFilePassword: <string>

        # 指定系统存储证书属性：
        #   1、证书上的主题名称或通用名称
        #   2、以十六进制表示的字节序列，用于通过其 SHA-1 摘要识别公钥
        # 仅 Windows、macOS 系统可用
        # certificateSelector: <string>

        # 指定集群之间系统存储证书属性：
        #   1、证书上的主题名称或通用名称
        #   2、以十六进制表示的字节序列，用于通过其 SHA-1 摘要识别公钥
        # 仅 Windows、macOS 系统可用
        # clusterCertificateSelector: <string>

        # 指定集群之间tls证书pem文件
        # 仅 Linux/BSD 系统可用，且与clusterCertificateSelector选项互斥（二选一）
        # clusterFile: <string>

        # 指定集群之间tls证书密码
        # 仅 Linux/BSD 系统可用
        # clusterPassword: <string>

        # pem证书颁发机构的根证书文件
        # 仅 Linux/BSD 系统可用，不要在certificateSelector时指定
        # CAFile: <string>

        # 集群之间pem证书颁发机构的根证书文件
        # 仅 Linux/BSD 系统可用，不要在clusterCertificateSelector时指定
        # clusterCAFile: <string>

        # 吊销列表pem文件，即不可用证书
        # 仅 Linux/BSD 系统可用
        # CRLFile: <string>

        # 允许无证书链接，主要用于混合部署时，部分有证书和部分无证书（使用的证书必需有效）。
        # allowConnectionsWithoutCertificates: <boolean>

        # 允许链接使用无效证书，可以理解不验证证书，不建议使用
        # allowInvalidCertificates: <boolean>

        # 允许主机名验证无效连接，可以理解不验证本机域名
        # allowInvalidHostnames: <boolean>

        # 禁用特定协议，多个使用逗号分开，可选协议有：
        #   TLS1_0
        #   TLS1_1
        #   TLS1_2
        #   TLS1_3
        # disabledProtocols: <string>

        # 启用FIPS模式
        # FIPS 兼容的 TLS/SSL 仅在企业版本有效
        # FIPSMode: <boolean>

        # 指定连接协议写日志，可选项参考禁用特定协议
        # logVersions: <string>
'
else
    NET_TLS_CONFIG='
    # 4.2以前版中配置，之后弃用ssl协议
    ssl:
        # 指定 TLS/SSL 模式：
        #   disabled    禁用TLS/SSL
        #   allowSSL    集群之间连接不使用TLS/SSL，服务器接受TLS/SSL和非TLS/SSL
        #   preferSSL   集群之间连接使用TLS/SSL，服务器接受TLS/SSL和非TLS/SSL
        #   requireSSL  集群仅使用并接受 TLS/SSL 加密连接
        mode: disabled

        # 指定TLS/SSL证书pem文件
        # 仅 Linux/BSD 系统可用，且与certificateSelector选项互斥（二选一）
        # PEMKeyFile: <string>

        # 指定证书密码
        # PEMKeyPassword: <string>

        # 指定系统存储证书属性：
        #   1、证书上的主题名称或通用名称
        #   2、以十六进制表示的字节序列，用于通过其 SHA-1 摘要识别公钥
        # 仅 Windows、macOS 系统可用
        # certificateSelector: <string>

        # 指定集群之间系统存储证书属性：
        #   1、证书上的主题名称或通用名称
        #   2、以十六进制表示的字节序列，用于通过其 SHA-1 摘要识别公钥
        # 仅 Windows、macOS 系统可用
        # clusterCertificateSelector: <string>

        # 指定集群之间TLS/SSL证书pem文件
        # 仅 Linux/BSD 系统可用，且与clusterCertificateSelector选项互斥（二选一）
        # clusterFile: <string>

        # 指定集群之间TLS/SSL证书密码
        # 仅 Linux/BSD 系统可用
        # clusterPassword: <string>

        # pem证书颁发机构的根证书文件
        # 仅 Linux/BSD 系统可用，不要在certificateSelector时指定
        # CAFile: <string>

        # 集群之间pem证书颁发机构的根证书文件
        # 仅 Linux/BSD 系统可用，不要在clusterCertificateSelector时指定
        # clusterCAFile: <string>

        # 吊销列表pem文件，即不可用证书
        # 仅 Linux/BSD 系统可用
        # CRLFile: <string>

        # 允许无证书链接，主要用于混合部署时，部分有证书和部分无证书（使用的证书必需有效）。
        # allowConnectionsWithoutCertificates: <boolean>

        # 允许链接使用无效证书，可以理解不验证证书，不建议使用
        # allowInvalidCertificates: <boolean>

        # 允许主机名验证无效连接，可以理解不验证本机域名
        # allowInvalidHostnames: <boolean>

        # 禁用特定协议，多个使用逗号分开，可选协议有：
        #   TLS1_0
        #   TLS1_1
        #   TLS1_2
        #   TLS1_3
        # disabledProtocols: <string>

        # 启用FIPS模式
        # FIPS 兼容的 TLS/SSL 仅在企业版本有效
        # FIPSMode: <boolean>
'
fi

# 生成yaml配置文件
cat > etc/mongod.conf <<conf
# mongodb 有两种配置文件格式，分别是 yaml 与 ini 现在使用的是 yaml
# 配置分企业版本的社区版本，企业版本会额外增加一些高级功能，以下配置选项中均有说明。

# 日志配置块
systemLog:
    # 日志信息级别，可选值：0~5
    # 默认是0 常规日志信息，
    # 1~5 是包含调试日志信息不同级别，分别对应：
    verbosity: 0

    # 运行mongos或mongod以安静模式，可选值：boolean
    # 默认是 false 开启后难以排查跟踪问题，但性能会略高
    quiet: false

    # 打印调试详细信息，会附加到日志中，可选值：boolean
    # 默认是 false 开启后方便排查问题
    traceAllExceptions: false

    # 设置系统日志来源，可选值：
    #      auth　　　　　　　认证相关的
    #    　authpriv　　　　　权限，授权相关的
    #    　cron　　　　　　　任务计划相关的
    #    　daemon　　　　　　守护进程相关
    #    　kern　　　　　　　内核相关的
    #    　lpr　　　　　　　 打印相关的
    #    　mail　　　　　　　邮件相关的
    #    　mark　　　　　　　标记相关的
    #    　news　　　　　　　新闻相关的
    #    　security　　　　　安全相关的，与auth类似
    #    　syslog　　　　　　syslog自己的
    #    　user　　　　　　　用户相关的
    #    　uucp　　　　　　　unix to unix cp相关的
    #    　local0 到 local7　用户自定义使用
    #    　*　　　　　　　　 表示所有的facility
    # 默认是 user
    # 只有在 destination = syslog 时有效
    # syslogFacility: user

    # 日志文件目录
    # 当 destination: file 时指定日志文件，其它值时不建议修改
    path: "$INSTALL_PATH$MONGODB_VERSION/logs/mongod.log"

    # 开启追加日志模式，重启不备份再重新写，可选值：boolean
    # 默认是 false
    logAppend: true

    # 指定轮换服务器日志和/或审计日志时命令的行为，可选值：rename 或 reopen
    # 默认值是 rename 当前指定为 reopen 时表示日志写到同一个文件中，且需要开启 logAppend: true 才有效
    logRotate: rename

    # 指定日志输出位置：file 或 syslog
    # file 是日志写文件，依赖 path 配置
    # syslog 是日志写到系统日志文件中
    # 如果不指定日志将输出到标准输出
    destination: file

    # 写日志的日期格式：iso8601-utc 或 iso8601-local
    # iso8601-utc 格式样例：1970-01-01T00:00:00.000Z
    # iso8601-local 默认值，格式样例：1969-12-31T19:00:00.000-05:00
    # timeStampFormat: iso8601-local

    # 组件日志
    component:
        # 访问控制组件
        accessControl:
            #访问控制相关的组件日志消息详细级别，可选值：0~5
            # 默认值是 0 
            verbosity: 0

        # 命令组件
        command:
            # 命令相关的组件的日志消息详细级别，可选值：0~5
            # 默认是 0
            verbosity: 0

        # 控制组件
        control:
            # 控制操作相关的组件的日志消息详细级别，可选值：0~5
            # 默认是 0
            verbosity: 0

        # 诊断组件
        ftdc:
            # 诊断数据收集操作相关的组件的日志消息详细级别，可选值：0~5
            # 默认是 0
            verbosity: 0

        # 地理空间组件
        geo:
            # 地理空间解析操作相关的组件的日志消息详细级别，可选值：0~5
            # 默认是 0
            verbosity: 0

        # 索引组件
        index:
            # 索引操作相关的组件的日志消息详细级别，可选值：0~5
            # 默认是 0
            verbosity: 0

        # 网络组件
        network:
            # 网络操作相关的组件的日志消息详细级别，可选值：0~5
            # 默认是 0
            verbosity: 0

        # 查询组件
        query:
            # 查询操作相关的组件的日志消息详细级别，可选值：0~5
            # 默认是 0
            verbosity: 0

        # 复制组件
        replication:
            # 复制相关的组件的日志消息详细级别，可选值：0~5
            # 默认是 0
            verbosity: 0

            # 选举子组件
            election:
                # 选举相关的组件的日志消息详细级别，可选值：0~5
                # 默认是 0
                verbosity: 0

            # 心跳子组件
            heartbeats:
                # 心跳相关的组件的日志消息详细级别，可选值：0~5
                # 默认是 0
                verbosity: 0

            # 初始同步子组件
            initialSync:
                # 初始同步相关的组件的日志消息详细级别，可选值：0~5
                # 默认是 0
                verbosity: 0

            # 回滚子组件
            rollback:
                # 回滚相关的组件的日志消息详细级别，可选值：0~5
                # 默认是 0
                verbosity: 0

        # 分片组件
        sharding:
            # 分片相关的组件的日志消息详细级别，可选值：0~5
            # 默认是 0
            verbosity: 0

        # 存储组件
        storage:
            # 存储相关的组件的日志消息详细级别，可选值：0~5
            # 默认是 0
            verbosity: 0

            # 日志子组件
            journal:
                # 日志相关的组件的日志消息详细级别，可选值：0~5
                # 默认是 0
                verbosity: 0

            # 恢复子组件
            recovery:
                # 恢复相关的组件的日志消息详细级别，可选值：0~5
                # 默认是 0
                verbosity: 0

        # 事务组件
        transaction:
            # 事务相关的组件的日志消息详细级别，可选值：0~5
            # 默认是 0
            verbosity: 0

        # 写入组件
        write:
            # 写入操作相关的组件的日志消息详细级别，可选值：0~5
            # 默认是 0
            verbosity: 0

# 进程管理配置
processManagement:
    # 启用后台运行mongos或mongod进程是守护程序模式，可选值：boolean
    # 默认是 false
    fork: true

    # 指定进程PID保存路径
    pidFilePath: $INSTALL_PATH$MONGODB_VERSION/db0.pid

    # 时区数据库路径，不指定将使用内置时区数据库
    # 默认不指定，系统中中 /usr/share/zoneinfo
    # timeZoneInfo: 

# 此配置在4.0+版本中有效
# 需要注册云监控账号，用于社区版本
cloud:
    monitoring:
        free:
            # 启用或禁用免费的 MongoDB 云监控，可选值：runtime 、on 、off
            # state: 

            # 描述环境上下文的可选标记，注册获取
            # tags: 

# 网络配置块
net:
    # 指定监听端口号，一般不需要指定
    # 默认值：
    #   当mongod进程不是分片或配置服务器成员或mongos进程为 27017
    #   当mongod进程是分片为 27018
    #   当mongod进程是配置服务器为 27019
    # port: 27017

    # 指定监听地址，可以是 ip 、域名 、sock文件
    # 默认绑定到本机
    # 多个监听地址使用逗号分开，如果是ipv6需要开启 ipv6 配置
    bindIp: 127.0.0.1

    # 是否启用绑定通配IP地址，ip4是 0.0.0.0 , ip6 是 :: ，可选值：boolean
    # 默认是 false 一般不建议开启，尤其是外网条件
    # 此选项是一个快捷选项，在bindIp中设置为 ::,0.0.0.0 效果一样
    bindIpAll: false

    # mongos或mongod将接受的最大同时连接数
    # 默认是 65536
    # 如果此设置高于操作系统配置的最大连接跟踪阈值，则此设置无效
    # 此选项可以限流，但不建议过低
    maxIncomingConnections: 65536

    # 是否开启mongod或mongos实例在收到来自客户端的所有请求时进行验证，以防止客户端将格式错误或无效的 BSON 插入到 MongoDB 数据库中，可选值：boolean
    # 默认是 true 此验证对性能影响很小，一般不建议关闭
    wireObjectCheck: true

    # 是否开启IPV6地址支持，可选值：boolean
    # 默认是 false 如果需要监听ipv6地址必需开启
    ipv6: true

    # UNIX 域套接字配置
    # 配置bindIp且指定ip时此配置无效
    unixDomainSocket:
        # 启用或禁用侦听 UNIX 域套接字，可选值：boolean
        # 默认是 true 如果要监听sock文件就必需开启
        enabled: true

        # UNIX 套接字的路径
        # 默认是 /tmp
        pathPrefix: /tmp

        # 设置 UNIX 域套接字文件的权限
        # 默认是 0700
        filePermissions: 0700

    # 此选项在3.2起废弃
    # http:
    $NET_TLS_CONFIG
    # 链接压缩配置
    compression:
        # 指定压缩器，多个使用逗号分开，可选值：
        #   snappy      3.6起默认启用
        #   zstd        4.2起默认启用
        #   zlib        4.2起默认启用
        #   disabled    禁用压缩
        # compressors: snappy,zstd,zlib

# 安全配置
security:
    # 密钥文件路径，用于分片集群或副本集群相互验证共享密钥
    # keyFile: <string>

    # 集群认证方式，单选，可选值：
    #   keyFile         使用密钥文件验证，需配置 keyFile，默认值
    #   sendKeyFile     动态密钥文件验证，可以动态修改，用于在线升级或修改
    #   sendX509        动态x509证书验证，可以动态修改，用于在线升级或修改
    #   x509            使用x509证书验证，推荐验证方式，需配置 tls.CAFile
    # clusterAuthMode: <string>

    # 角色的访问控制 (RBAC) ，可选值：
    #   enabled     用户只能访问授权的数据库资源
    #   disabled    用户可访问所有数据库资源，默认值
    # authorization: <string>

    # 开启过渡验证，开启后将允许未经身份认证的链接，默认关闭
    # transitionToAuth: <boolean>

    # 开启服务端运行 javascript 脚本，默认开启
    # javascriptEnabled:  <boolean>

    # 开启诊断日志，企业版本有效
    # redactClientLogData: <boolean>

    # 指定集群允许来源地址列表，5.0增加
    # 配置后指定的来源地址段进行验证，其它来源地址不验证
    #clusterIpSourceAllowlist:
    #    - <string>
    #    指定 192.0.2.[0~24] 地址段
    #    - 192.0.2.0/24
    #    指定固定地址
    #    - 127.0.0.1
    #    指定通配地址
    #    - ::1

    # SASL 服务相关配置
    sasl:
        # 配置 SASL 或 Kerberos 身份验证的完全限定服务器域名
        # hostName: <string>

        # SASL 服务的注册名
        # serviceName: <string>

        # UNIX 域套接字文件的路径
        # saslauthdSocketPath: <string>

    # 启用加密的WiredTiger存储引擎，企业版本有效
    # enableEncryption: <boolean>

    # 静态加密的密码模式，企业版本有效
    # 可选值：
    #   AES256-CBC
    #   AES256-GCM
    # encryptionCipherMode: <string>

    # 通过KMIP以外的进程管理密钥时本地密钥文件的路径，企业版本有效
    # 需要开启 enableEncryption
    # encryptionKeyFile: <string>

    # KMIP服务相关配置，企业版本有效
    kmip:
        # KMIP 服务器中现有密钥的唯一 KMIP 标识符，不指定会自动创建
        # keyIdentifier: <string>

        # 开启轮换主密钥并重新加密内部密钥库
        # rotateMasterKey: <boolean>

        # 要连接的 KMIP 服务器的主机名或 IP 地址
        # serverName: <string>

        # 用于与 KMIP 服务器通信的端口号
        # port: <string>

        # 用于向 KMIP 服务器验证 MongoDB 的客户端证书路径的字符串
        # clientCertificateFile: <string>

        # 证书的密码
        # clientCertificatePassword: <string>

        # 在 Windows 和 macOS 上可用且与clientCertificateFile互斥
        # clientCertificateSelector: <string>

        # CA 文件的路径，用于验证与 KMIP 服务器的安全客户端连接。
        # serverCAFile: <string>

        # 重试与 KMIP 服务器的初始连接的次数，默认是0
        # connectRetries: <int>

        # 等待 KMIP 服务器响应的超时时间（以毫秒为单位），默认是 5000
        # connectTimeoutMS: <int>

    # LDAP 服务器相关配置，企业版本有效
    ldap:

        # 服务列表，多个使用逗号分开
        # servers: <string>

        # 
        bind:
            # 指定身份验证方式，可选值：
            #   simple  使用简单的身份验证，即 queryUser 和 queryPassword ，默认值
            #   sasl    使用 SASL 协议进行身份验证
            # method: <string>

            # SASL 机制列表，多个逗号分开，默认：DIGEST-MD5
            # saslMechanisms: <string>

            # 连接到 LDAP 服务器用户名
            # queryUser: <string>

            # 连接到 LDAP 服务器密码
            # queryPassword: <string>

            # 连接到 LDAP 服务器 Windows 登录凭据
            # 仅用于Windows平台
            # useOSDefaults: <boolean>

        # 安全连接，可选值：
        #   tls         默认值，对于 Linux 部署，您必须在/etc/openldap/ldap.conf文件中配置适当的 TLS 选项
        #   none        禁用
        # transportSecurity: <string>

        # 等待LDAP服务器响应时长，毫秒为单位，默认：10000
        # timeoutMS: <int>

        # 身份验证的用户名映射到 LDAP 专有名称 (DN)
        # userToDNMapping: <string>

        # LDAP 授权
        authz:
            # 查询检索实体所属的 DN 列表
            # queryTemplate: <string>

        # 实例是否在LDAP server(s)其启动过程中检查可用性
        # validateLDAPServerConfig: <boolean>

# 设置 MongoDB 参数或MongoDB 服务器参数中描述参数
# 可选参数文档：https://docs.mongodb.com/manual/reference/parameters/
setParameter:
    # 参数名和值
    # <parameter1>: <value1>

# 存储配置块
storage:
    # 数据保存目录，不配置将使用默认地址，默认目录各系统存在差异
    dbPath: $INSTALL_PATH$MONGODB_VERSION/mongodb
    
    # 开启数据故障恢复和持久化数据
    journal:
        # 启用持久
        enabled: true

        # 进程允许的日志操作之间的最长时间（以毫秒为单位），默认100
        # commitIntervalMs: <num>

    # 使用单独的目录来存储每个数据库的数据，默认 false
    # directoryPerDB: <boolean>

    # 数据刷新到数据文件的隔间时长（秒为单位），默认60
    # syncPeriodSecs: <int>

    # 存储引擎，可选值：
    #   wiredTiger  需要配置 wiredTiger 模块，默认引擎
    #   inMemory    指定内存引擎，企业版本可用
    # engine: <string>

    # 引擎设置
    wiredTiger:
        # 引擎数据配置
        engineConfig:

            # 数据的内部缓存的最大大小，默认是内存的50%且最少256MB
            # 一般不建议修改
            # cacheSizeGB: <number>

            # 指定压缩 WiredTiger 日志数据的压缩类型，可选值：
            #   none        不使用压缩
            #   snappy      默认压缩方式
            #   zlib        可选压缩
            #   zstd        4.2新增压缩
            # journalCompressor: <string>

            # 将索引和集体存储在数据目录中单独子目录中，默认 false
            # directoryForIndexes: <boolean>

            # 指定WiredTigerLAS.wt最大空间，4.4开始弃用
            # maxCacheOverflowFileSizeGB: <number>

            # 指定zstd 压缩级别，5.0开始有效
            # zstdCompressionLevel: 6

        # 集合配置
        collectionConfig:
            # 指定集合数据压缩方式，可选值：
            #   none        不使用压缩
            #   snappy      默认压缩方式
            #   zlib        可选压缩
            #   zstd        4.2新增压缩
            # blockCompressor: <string>

        # 索引配置
        indexConfig:
            # 启用索引数据的前缀压缩，默认 true
            # prefixCompression: <boolean>

    # 引擎设置，企业版本有效
    inMemory:

        # 引擎数据配置
        engineConfig:

            # 最大内存量，默认值：物理 RAM 的 50% 减去 1 GB
            # inMemorySizeGB: <number>

    # 指定的最低小时数保持一个OPLOG条目，小时为单位，可以使用小数，默认为0
    # oplogMinRetentionHours: <double>

# 分析器配置
operationProfiling:
    # 指定应分析哪些操作，可选值：
    #   off         关闭，默认
    #   slowOp      收集慢操作
    #   all         收集所有操作
    # mode: <string>

    # 慢的操作时间阈值，单位为毫秒，默认100
    # slowOpThresholdMs: <int>

    # 分析或记录的慢速操作的比例，默认1.0
    # slowOpSampleRate: <double>

    # 控制分析和记录哪些操作的过滤器表达式
    # 当filter设置后slowOpThresholdMs和slowOpSampleRate不能用于分析和慢查询日志行
    # filter: <string>

# 复制配置
replication:
    # 复制操作日志（即oplog）的最大大小（以兆字节为单位）
    # 默认是可用磁盘空间的5%
    # oplogSizeMB: <int>

    # 副本集的名称
    # replSetName: <string>

    # 启用majority，默认 true
    # 5.0 起不可修改永远为 true
    # enableMajorityReadConcern: <boolean>

# 分片配置块
sharding:
    # mongod实例在分片集群中的角色，可选值：configsvr 和 shardsvr
    # configsvr 是指定为配置服务节点，默认实例监听27019端口
    # shardsvr 是指定为碎片节点，默认实例监听27018端口
    # clusterRole: 
    
    # 区块迁移时是否保存碎片文档，设置为 bool 值，从3.2开始默认为 false
    archiveMovedChunks: false

# 审计日志配置，企业版本有效
auditLog:
    # 审计输出，可选值：
    #   syslog      审计事件以JSON格式输出到系统日志，windows系统不可用
    #   console     以JSON格式输出到stdout（标准输出）
    #   file        将审计内存写到指定文件中
    # destination: <string>

    # 输出文件的格式审计格式，可选值：
    #   JSON    以JSON格式输出
    #   BSON    以BSON二进制格式输出
    # 在destination=file时配置，BSON格式性能较高
    # format: <string>

    # 审计保存文件地址，在destination=file时配置
    # path: <string>

    # 过滤限制类型的操作审计记录
    # filter: <string>

# SNMP配置
snmp:
    # 禁用SNMP访问mongod，默认是 false
    # disabled: <boolean>

    # 作为子代理运行
    # subagent: <boolean>

    # 作为主站运行
    # master: <boolean>
# 
conf

mkdirs data
mkdirs logs
chown -R mongodb:mongodb ./*

# 添加服务配置
SERVICES_CONFIG=()
SERVICES_CONFIG[$SERVICES_CONFIG_START_RUN]="./bin/mongod -f ./etc/mongod.conf"
SERVICES_CONFIG[$SERVICES_CONFIG_USER]="mongodb"
SERVICES_CONFIG[$SERVICES_CONFIG_PID_FILE]=""
# 服务并启动服务
add_service SERVICES_CONFIG

# 安装成功
info_msg "安装成功：mongodb-$MONGODB_VERSION";
