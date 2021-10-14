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
# CentOS 5+
# Ubuntu 15+
#
# 安装文档地址： https://docs.mongodb.com/manual/administration/install-on-linux/
#
#
# 注意：
#   1、mongodb安装需要比较多的内存建议内存4G+，如果内存不足容易出现编译进程被kill报出类似错 g++: fatal error: Killed signal terminated program cc1plus
#   2、mongodb安装需要比较多的磁盘空间，一般建议空余空间在35G+，如果空间不足容易报类似错 No space left on device
#   3、mongodb安装依赖比较高的gcc，通过脚本安装时间比较长
#   4、多个不同版本的so动态库响应加载时需要调整动态库管理，打开 /etc/ld.so.conf 去掉不需要的动态库目录，然后运行 ldconfig ，类似错误提示：./bin/mongod: /usr/local/gcc/5.1.0/lib64/libstdc++.so.6: version `GLIBCXX_3.4.22' not found (required by ./bin/mongod)
#
#
####################################################################################
##################################### 安装处理 #####################################
####################################################################################
# 加载基本处理
source basic.sh
# 获取工作目录
INSTALL_NAME='mongodb'
# 获取版本配置
VERSION_URL="http://downloads.mongodb.org.s3.amazonaws.com/current.json"
VERSION_MATCH='mongodb-src-r\d+\.\d+\.\d+\.tar\.gz'
VERSION_RULE='\d+\.\d+\.\d+'
# 安装最小版本
MONGODB_VERSION_MIN='3.0.0'
# 初始化安装
init_install MONGODB_VERSION
# ************** 相关配置 ******************
# 编译初始选项（这里的指定必需有编译项）
CONFIGURE_OPTIONS="--prefix=$INSTALL_PATH$MONGODB_VERSION $ARGV_options"
# ************** 编译安装 ******************
# 下载mongodb包
download_software https://fastdl.mongodb.org/src/mongodb-src-r$MONGODB_VERSION.tar.gz
# 安装依赖
echo "install dependence"
# 获取编辑安装的依赖要求
GCC_VERSION=`grep -iP 'gcc\s+\d+(\.\d+)+' ./docs/building.md|grep -oP '\d+(\.\d+)+'|tail -n 1`
PYTHON_VERSION=`grep -iP 'Python\s+\d+(\.\d+)+' ./docs/building.md|grep -oP '\d+(\.\d+)+'|tail -n 1`
GCC_CURRENT_VERSION=`gcc -v 2>&1|grep -oP '\d+(\.\d+){2}'|tail -n 1`
if ! echo "$GCC_VERSION"|grep -qP '^\d+\.\d+\.\d+$';then
    if echo "$GCC_VERSION"|grep -qP '^\d+\.\d+$';then
        if if_version "$GCC_VERSION" '>' '5.0';then
            if echo "$GCC_VERSION"|grep -qP '^\d+\.0$';then
                GCC_VERSION=`echo "$GCC_VERSION"|grep -oP '^\d+'`".1.0"
            else
                GCC_VERSION="$GCC_VERSION.0"
            fi
        else
            GCC_VERSION=$GCC_VERSION".1"
        fi
    else
        if if_version "$GCC_VERSION" '>' '5';then
            GCC_VERSION=`echo "$GCC_VERSION"|grep -oP '^\d+'`".1.0"
        else
            GCC_VERSION=$GCC_VERSION".1.1"
        fi
    fi
fi
# 注意GCC不建议安装过高的版本，否则容易造成编译异常
if if_version "$GCC_VERSION" '>' "$GCC_CURRENT_VERSION"; then
    run_install_shell gcc-install.sh $GCC_VERSION
    if_error 'install gcc fail'
else
    echo 'GCC OK'
fi
if ! echo "$PYTHON_VERSION"|grep -qP '^\d+\.\d+\.\d+$';then
    PYTHON_VERSION=$PYTHON_VERSION".0"
fi
if if_version "$PYTHON_VERSION" ">=" "3.0.0"; then
    PYTHON_NAME='python3'
    PIP_NAME='pip3'
else
    PYTHON_NAME='python'
    PIP_NAME='pip'
fi
if if_command $PYTHON_NAME;then
    PYTHON_CURRENT_VERSION=`$PYTHON_NAME -V 2>&1|grep -oP '\d+(\.\d+)+'`
else
    PYTHON_CURRENT_VERSION='0.0.1'
fi
if if_version $PYTHON_VERSION '>' "$PYTHON_CURRENT_VERSION"; then
    # 安装对应的新版本
    run_install_shell python-install.sh $PYTHON_VERSION
    if_error 'install python fail'
else
    echo 'python OK'
fi
if if_lib "openssl";then
    echo 'openssl ok'
else
    # 安装openssl-dev
    packge_manager_run install -OPENSSL_DEVEL_PACKGE_NAMES
fi
# 编译安装
if [ -e "etc/pip/compile-requirements.txt" ];then
    $PIP_NAME install -r etc/pip/compile-requirements.txt
    if grep -q '\-\-prefix' docs/building.md;then
        $PYTHON_NAME buildscripts/scons.py $CONFIGURE_OPTIONS install
    else
        $PYTHON_NAME buildscripts/scons.py install-all PREFIX=$INSTALL_PATH$MONGODB_VERSION
    fi
    if_error 'install mongodb fail'
else
    SCONS_VERSION=`grep -iP 'scons\s+\d+(\.\d+)+' ./docs/building.md|grep -oP '\d+(\.\d+)+'|tail -n 1`
    SCONS_CURRENT_VERSION=`scons -v 2>&1|grep -oP '\d+(\.\d+)+'|tail -n 1`
    if ! echo "$SCONS_VERSION"|grep -qP '^\d+\.\d+\.\d+$';then
        SCONS_VERSION=$SCONS_VERSION".1"
    fi
    if if_version "$SCONS_VERSION" '>' "$SCONS_CURRENT_VERSION"; then
        MONGODB_INSTALL_PATH=`pwd`
        # 安装最近版本
        download_software "http://prdownloads.sourceforge.net/scons/scons-$SCONS_VERSION.tar.gz"
        # 编译安装
        $PYTHON_NAME setup.py install
        # 编译安装
        if_error 'install scons fail'
        cd $MONGODB_INSTALL_PATH
    else
        echo 'Scons OK'
    fi
    scons all -j $HTREAD_NUM
    scons $CONFIGURE_OPTIONS install
    if_error 'install mongodb fail'
fi
# 创建用户组
add_user mongodb
cd $INSTALL_PATH$MONGODB_VERSION

echo "mongodb config set"
# 配置文件处理
if [ ! -d 'etc/' ];
    mkdir etc
fi
cat > etc/mongod.conf <<conf
# mongodb 有两种配置文件格式，分别是 yaml 与 ini 现在使用的是 ini

##############################
####### 数据库相关配置 #######
##############################
      
# 以守护进程的方式运行MongoDB，创建服务器进程
fork = true

# 绑定监听地址，多个以逗号分开
bind_ip = 127.0.0.1

# 绑定监听端口号
port = 27017

# 安静模式，开启后，生产环境不要使用
#quiet = true

# 数据库目录
dbpath = $INSTALL_PATH$MONGODB_VERSION/mongodb

# 目录输出目录
logpath = $INSTALL_PATH$MONGODB_VERSION/log/mongod.log

# 日志输出方式，开启追日志内容加模式
logappend = true

# 
journal = true

# 设置PID保存文件
pidfilepath = $INSTALL_PATH$MONGODB_VERSION/mongodb/db0.pid

#设置最大连接数
maxConns=20000

#开启认证，开启认证后分片与复制也需要认证
#auth = true

#打开web监控
#httpinterface=true
#rest=true

####################################
######## 复制与分片相关配置 ########
####################################

# 复制设置
# 副本集名称, 同一组副本集名称必需一样
replSet = set0

# 开启认证后需要添加副本集认证文件，注意这个文件是密钥文件可以是任意内容，但大小必须小于1k且只能包含base64集的内容，所有同副本名的节点这个文件内容必须相同
# 其它认证参数有：sendKeyFile、sendX509、x509
keyFile = $INSTALL_PATH$MONGODB_VERSION/mongodb/keyfile

# 分片设置
# 指定为配置节点
configsvr = true
# 指定为碎片节点，注意configsvr与shardsvr必须二选一
# shardsvr = true

# 配置监听地址，多个以逗号分开
configdb = 10.8.0.12:27001
chunkSize = 64

conf

cd $INSTALL_PATH$MONGODB_VERSION/bin
# 启动服务器
sudo -u mongodb ./mongod -f etc/mongod.conf
echo "install mongodb-$MONGODB_VERSION success!";
# 安装成功
exit 0
