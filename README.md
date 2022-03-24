linux shell脚本集合，脚本分两大类：自动安装、辅助工具
===============

脚本仅支持linux系统的CentOS和Ubuntu两类系统，建议安装系统版本
* CentOS 6.4+
* Ubuntu 15.04+

## 如何使用
为方便增加脚本和管理，脚本全部存放在子目录中，由统一调用脚本 run.sh 入口操作。

自动安装 lnpm = nginx+php+mysql 最新版
```
bash run.sh install-batch @lnpm
```

挂载硬盘
```
bash run.sh disk
```

### 快速下载和使用
创建一个sh脚本
```
vim shells.sh
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
    if [ $? != '0' ];then
        echo '下载脚本包失败！'
        exit 1
    fi
    unzip master.zip
fi
cd shell-master
find ./ -maxdepth 3 ! -path '*/temp/*' -type f -exec sed -i 's/\r//' {} \;
for NAME in ${@:1}; do
    nohup bash run.sh $NAME 2>&1 &> ../$NAME.log &
done
exit 0
```

自动安装和工具会陆续增加，具体支持脚本可查看目录结构
```
bash shells.sh @lnpm
```

### 目录结构
./etc           脚本配置文件目录
./includes      公共脚本目录，包含脚本处理的基础，不可直接调用
./installs      自动安装脚本目录集，所有安装脚本均在此目录下，均可直接调用
./tools         工具脚本目录集，所以工具脚本均在此目录下，均可直接调用
./temp          脚本处理临时存储目录


### 查看功能信息
-----------------
```
bash run.sh -h
```

### 注意
如果命令运行出错可能是换行符的问题可以运行命令
```
find ./ -maxdepth 3 ! -path '*/temp/*' -type f -exec sed -i 's/\r//' {} \;
```

## 自动安装
安装过程中需要外网下载，并且需要root权限，安装成功后会自动尝试启动服务或应用。
不建议安装多版本先安装高再安装低版本，容易造成部分依赖包版本要求版本不一至导致安装失败
下载使用的是curl和wget两个命令，在使用前需要保证这两个命令能访问https网络

### 单一安装脚本命令
-----------------
命令语法：
```
bash run.sh [script-name] [version] [--options ...]
```

参数说明：
* [script-name]     指定安装脚本名，如：redis-install、nginx-install、php-install等
* [version]         指定安装版本，如果不指定则打印最新版本，如果要安装最新版本可以指定为 new
* [--options]       安装选项，各安装脚本选项信息不一致，了解更多通过 -h 参数查看

#### 示例
安装php最新版本
```
bash run.sh php-install new
```

### 批量安装脚本
-----------------
命令语法：
```
bash run.sh install-batch [name] [-c]
```
参数说明：
* [name]            安装包名，具体以配置文件 etc/install-batch.conf 为准
* [-c]              验证安装结果

注意：安装是切入后台执行，安装结果需要另行查证或使用脚本查证

#### 示例
安装php和nginx最新版本
```
bash run.sh install-batch php,nginx
```

### 远程批量安装命令
-----------------
命令语法：
```
bash run.sh install-remote [name] [remote] [-c]
```
参数说明：
* [name]            安装包名，具体以配置文件 etc/install-batch.conf 为准
* [remote]          指定匹配的远程节点名
* [-c]              验证安装结果

注意：远程批量安装是通过批量复制脚本库到各远程服务器中，再调用批量安装脚本进行安装操作，使用前需要修改配置文件

#### 示例
远程安装php和nginx最新版本
```
bash run.sh install-remote php,nginx
```

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
* 12、当你确认已经安装了匹配版本的动态为时可能是存在多个版本操作时加载了错误的版本动态库，如果有多个版本的动态库会引起安装或启动出错，需要手动去掉版本不匹配的动态库目录，动态库有环境变量 PKG_CONFIG_PATH 和 /etc/ld.so.conf 动态库目录配置文件，前者是pkg-config工具只要export环境变量即可，后者修改配置文件后需要ldconfig重新加载

## 辅助工具
目前辅助工具比较少，主要有：监控、磁盘挂载等

### 工具使用命令
-----------------
命令语法：
```
bash run.sh [name] [options ...]
```
参数说明：
* [name]            工具名
* [options]         工具可使用选项

#### 示例
挂载新增加硬盘
```
bash run.sh disk
```

## 特别说明
* 1、此脚本库仅仅是以方便使用，并非唯一选项，比如：各安装包可以使用docker快速应用，使用脚本成功率并没有docker高，但可以做更多更方便选择。
* 2、脚本不能满足指定系统的所有场景，比如：安装失败的原因多样化而无法穷尽。
* 3、有兴趣的朋友欢迎加入此坑。
