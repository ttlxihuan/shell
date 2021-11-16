linux 服务器常用工具安装包
===============

安装脚本仅支持linux系统的CentOS和Ubuntu两类系统，建议安装系统版本
* CentOS 5+
* Ubuntu 15+

### 查看安装脚本信息
-----------------
```
bash *_install.sh -h
```


### 单一安装脚本命令
-----------------
```
bash *_install.sh [version] [--options ...]
```

参数说明：
* [version]  指定安装版本，如果不指定则打印最新版本，如果要安装最新版本可以指定为 new
* [--options]  安装选项，各安装脚本选项信息不一致，了解更多通过 -h 参数查看

#### 示例
```
bash php_install.sh new
```


安装过程中需要外网下载，并且需要root权限，安装成功后会自动尝试启动服务或应用。
默认会使用多核编译如果需要指定编译核数据可以增加临时环境变量 INSTALL_HTREAD_NUM ，指定值不可过高，一般不超过实际核数


### 批量安装脚本命令
-----------------
#### 本机批量安装命令
```
bash install-batch.sh
```
#### 机群批量安装命令
```
bash install-remote.sh
```

批量安装需要调整安装配置文件 install-batch.conf
```
# 安装的服务器【机群安装】
默认账号为 root
[host]
192.168.181.130 password [user]

# 安装配置【本机或机群安装】
[install]
php 7.2.7
mysql 8.0.11
nginx 1.15.0
```

### 注意
不建议向低版本安装，比如原来已经安装高版本再安装低版本，容易造成部分依赖包版本要求而导致找不到
如果命令运行出错可能是换行符的问题可以运行命令
```
find ./ -maxdepth 1 -type f -name '*.sh' -exec sed -i 's/\r//' {} \;
```

### 快速使用
创建一个sh脚本
```
vim install.sh
```

复制输入下面的脚本代码并保存（注意需要安装 wget，如果版本过低下载容易报错）
```
#!/bin/bash
if ! which wget 2>&1 &>/dev/null || ! which unzip 2>&1 &>/dev/null ;then
    echo '需要安装： wget 和 unzip 进行下载和解压！'
    exit 1
fi
if [ ! -d "shell-master" ];then
    wget --no-check-certificate -O master.zip https://github.com/ttlxihuan/shell/archive/master.zip
    unzip master.zip
fi
cd shell-master
find ./ -maxdepth 1 -type f -name '*.sh' -exec sed -i 's/\r//' {} \;
if [ -d './tools' ];then
    find ./tools -maxdepth 1 -type f -name '*.sh' -o -name '*.conf'|xargs sed -i 's/\r//'
fi
for NAME in ${@:1}; do
    if [ -e "$NAME-install.sh" ];then
        echo "install $NAME"
        nohup bash $NAME-install.sh new 2>&1 &> ../$NAME-install.log &
    else
        echo "unknown install: $NAME"
    fi
done
exit 0
```

执行安装，需要安装什么就增加对应的包名（安装最新稳定版本，如果想安装指定版本则需要使用上面的安装方式）
```
bash install.sh nginx php mysql git
```

> 注意：以上脚本会下载所有安装脚本代码，保存在 ./shell-master 目录下。

### 安装说明
* 1、安装脚本有两种类型，如果安装的包存在编译安装则使用的是编译安装，否则是使用其它安装方式，比如elasticsearch解压即可使用
* 2、安装会自动下载对应的安装包，网速会影响安装速度，但你也可以把对应已经下载好的安装包放到安装脚本的根目录下（目录层级可以留意下已经运行过安装脚本后创建的文件目录）
* 3、编译安装一般会比较慢，由其是gcc、mysql、mongodb等编译时间会比较长，部分安装包需要比较高版本的gcc所以gcc如果有快速安装最好提前安装好，比如新版的mysql安装需要GCC5.3以上
* 4、并不是所有安装包都得选择编译安装，比如mysql、mongodb等它们有更更快速的rpm或deb
* 5、安装前需要留意下包的系统要求，主要是硬件要求，如果不满足需要调整安装的版本
* 6、大部安装脚本有设置最小安装版本，需要注意下，最小版本不是不能安装，只是不推荐安装，毕竟性能在高版本中才会更好
* 7、同一个安装脚本不能同时运行安装，如果多个安装的脚本需要依赖同一个安装脚本需要避开否则后进入依赖安装脚本时容易造成强制退出安装
* 8、在安装mysql、gcc、mongodb等需要较大磁盘和内存空间，磁盘最好可用空间在50G以上，内存最好在6G以上，否则系统容易强制杀编译进程导致编译失败，比如报错：fatal error: Killed signal terminated program
* 9、编译安装中途强制终止可能会导致无法再次继续编译安装，建议删除解压目录后再调用脚本进行编译安装，或者使用参数 --reset 3 自动处理
* 10、安装磁盘或内存空间不足时会自动选择其它可用硬盘或添加虚拟内存，可以选择不忽略空间处理，多数空间不足安装无法完成
* 11、部分系统存在多个版本依赖，导致安装失败，特别是gcc。这类往往需要手动干预，可以删除不需要的版本或者重新安装指定版本，也可以通过编译参数进行指定。

### 注意安装兼容说明
* 1、脚本不能满足指定系统的所有场景安装，安装失败的原因多样化而无法穷尽，如果你在安装过程中有失败的可以发issues或者提供代码来完善。
* 2、当你确认已经安装了匹配版本的动态为时可能是存在多个版本操作时加载了错误的版本动态库，如果有多个版本的动态库会引起安装或启动出错，需要手动去掉版本不匹配的动态库目录，动态库有环境变量 PKG_CONFIG_PATH 和 /etc/ld.so.conf 动态库目录配置文件，前者是pkg-config工具只要export环境变量即可，后者修改配置文件后需要ldconfig重新加载

