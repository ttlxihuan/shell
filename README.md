linux 服务器常用工具安装包
===============

安装脚本仅支持linux系统的CentOS和Ubuntu两类系统，建议安装系统版本
* CentOS 5+
* Ubuntu 15+

### 单一安装脚本命令
-----------------
```
bash *_install.sh [version] [other...]
```

参数说明：
* [version]  指定安装版本，如果不指定则打印最新版本，如果要安装最新版本可以指定为 new
* [other...]  安装脚本其它参数，主要用于密码，集群配置，具体以各安装脚本为准

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
bash install.sh
```
#### 机群批量安装命令
```
bash remote-install.sh
```

批量安装需要调整安装配置文件 install.conf
```
# 安装的服务器【机群安装】
默认账号为 root
[host]
192.168.181.130 password [user]

# 安装配置【本机或机群安装】
[install]
php 7.2.7
mysql 8.0.11-1.el7.x86_64
nginx 1.15.0
```

### 注意
不建议向低版本安装，比如原来已经安装高版本再安装低版本，容易造成部分依赖包版本要求而导致找不到
如果命令运行出错可能是换行符的问题可以运行命令
```
find -name '*.sh'|sed -i 's/\r//' file
```

### 快速使用
创建一个sh脚本
```
vim install.sh
```

复制输入下面的脚本代码并保存
```
#!/bin/bash
if ! which wget 2>&1 &>/dev/null || ! which unzip 2>&1 &>/dev/null ;then
    echo 'require install wget and unzip'
    exit 1
fi
if [ ! -d "shell-master" ];then
    wget --no-check-certificate -O master.zip https://github.com/ttlxihuan/shell/archive/master.zip
    unzip master.zip
fi
cd shell-master
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

执行安装，需要安装什么就增加对应的包名
```
bash install.sh nginx php mysql git
```

### 安装说明
安装速度取决于系统的硬件和网速（尤其是境外网速），编译安装相对较慢的有gcc和mysql，因为新版的mysql安装需要更高的gcc所以建议在安装mysql前先安装好高版本的GCC5.3以上


