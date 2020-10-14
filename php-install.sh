#!/bin/bash
#
# PHP快速编译安装shell脚本
#
# 安装命令
# bash php-install.sh new
# bash php-install.sh verions_num
# 
# 查看最新版命令
# bash php-install.sh
#
# 可运行系统：
# CentOS 5+
# Ubuntu 15+
#
# 未绑定的扩展尽量不要使用静态编译安装，这种安装方式容易出现问题，建议使用phpize安装，先自行下载源码，解压后使用phpize自动生成php扩展环境，剩下直接使用正常编译安装流程 ./configure && make && make install
# 官方文档：https://www.php.net/manual/zh/install.pecl.phpize.php
#
# 常见错误：
#  1、运行yum报错 Error: Cannot retrieve metalink for repository: epel. Please verify its path and try again
#       修改 /etc/yum.repos.d/epel.repo 文件的 baseurl 和 mirrorlist 配置，把 baseurl 配置前的#去掉，把 mirrorlist 配置前面增加#
#  2、configure: error: newly created file is older than distributed files!
#       说明系统时间不对，需要手动更新系统时间。使用命令： ntpdate -u ntp.api.bz  如果没有ntpdate命令则先安装 yum install -y ntpdate
#  3、curl: (35) SSL connect error
#       执行命令：yum -y update nss
#  4、使用wget报 Unable to establish SSL connection
#       直接更新下wget版本即可，执行命令：yum -y update wget
#  5、make 时报 virtual memory exhausted: Cannot allocate memory
#       依次执行命令：（主要是因为系统物理内存不够用，而虚拟内存也不够，导致make失败）
#           dd if=/dev/zero of=/swap bs=1024 count=1M           #创建一个大小为1G的文件/swap ，空间=bs*count，不要搞的太大
#           mkswap /swap                                        #将/swap作为swap空间
#           swapon /swap                                        #启用虚拟内存空间
#           echo "/swap swap swap sw 0 0" >> /etc/fstab         #配置开机后自动生效，非必需项
#  6、make时报 make: *** [sapi/cli/php] Error 1
#       这类问题大部份是某个库安装了多个不同的版本或位置找不到，导致在 configure 时搜索出来的库目录不对，造成make失败，
#       比如报错前提示： undefined reference to libiconv_open  之类的异常
#       一般解决法有：
#           1、删除报错库 iconv 所有不需要的版本，再重新 configure 处理，一般默认目录安装有： /usr/local  和 /usr ，子目录或文件： ./bin/iconv  ./include/  ./lib/  这种操作难度大容易删错文件，不建议使用 
#           2、在 make 时修改编译环境变量 ZEND_EXTRA_LIBS 指定编译使用动态库，即执行命令 make ZEND_EXTRA_LIBS='-liconv'
#               使用这种操作简单，但需要把动态库配置到库连接里通过命令查看 ldconfig -p|grep iconv，
#               如果没有则需要把动态库所在目录添加到配置文件 /etc/ld.so.conf 中或添加环境变量 LD_LIBRARY_PATH 中，然后需要调整 ldconfig 重新加载动态库地址并缓存起来
#           3、在 configure 指定库目录，如： configure --with-iconv=/usr/local/iconv  但使用当前方式时需要注意 --with-iconv 和 --with-iconv-dir 选项意义不一样，建议使用这种操作
#  7、make时如果报 Error: no such instruction: 类似错误，说明binutils版本过低，需要安装高版本的，建议安装版本2.30+ ，下载地址 http://ftp.gnu.org/gnu/binutils/ 常规编译安装即可
#
#
####################################################################################
##################################### 安装处理 #####################################
####################################################################################
# 加载基本处理
source basic.sh
# 域名
PHP_HOST='cn2.php.net'
# 获取工作目录
INSTALL_NAME='php'
# 获取版本配置
VERSION_URL="https://$PHP_HOST/supported-versions.php"
VERSION_MATCH='#v\d+\.\d+\.\d+'
# 安装最小版本
PHP_VERSION_MIN='5.0.0'
# 初始化安装
init_install PHP_VERSION "$1"
# ************** 相关配置 ******************
# 编译初始选项（这里的指定必需有编译项）
CONFIGURE_OPTIONS="--prefix=$INSTALL_PATH$PHP_VERSION "
# 编译增加项（这里的配置会随着编译版本自动生成编译项）
ADD_OPTIONS='sockets ?pdo-mysql mysqli fpm openssl curl bcmath ?xml mhash mbstring zip zlib gd jpeg ?png freetype ?gd-native-ttf ?mcrypt ?!pdo-sqlite ?!sqlite3 gmp'
# ************** 编译安装 ******************
# 下载PHP包
download_software https://$PHP_HOST/distributions/php-$PHP_VERSION.tar.gz
# 暂存编译目录
PHP_CONFIGURE_PATH=`pwd`
# 解析选项
parse_options CONFIGURE_OPTIONS $ADD_OPTIONS
# 安装依赖
echo "install dependence"
# ca-certificates 根证书更新
packge_manager_run install -CA_CERT_PACKGE_NAMES
# ***选项处理&选项依赖安装***
# fpm 附加选项增加
if in_options fpm $CONFIGURE_OPTIONS;then
    parse_options CONFIGURE_OPTIONS fpm-user=phpfpm fpm-group=phpfpm
fi
# curl 扩展使用
if in_options curl $CONFIGURE_OPTIONS && ! if_lib "libcurl";then
    # 安装 curl-dev
    packge_manager_run install -CURL_DEVEL_PACKGE_NAMES
fi
# mcrypt 扩展使用（PHP7已经不再使用）
if in_options mcrypt $CONFIGURE_OPTIONS;then
    if if_command libmcrypt-config;then
        echo 'libmcrypt ok'
    else
        # 安装 libmcrypt
        packge_manager_run install -LIBMCRYPT_DEVEL_PACKGE_NAMES
        if ! if_command libmcrypt-config;then
            # 下载
            download_software https://nchc.dl.sourceforge.net/project/mcrypt/Libmcrypt/2.5.8/libmcrypt-2.5.8.tar.gz "libmcrypt-2.5.8"
            # 编译安装
            configure_install
        fi
    fi
fi
# iconv扩展
if ! in_options !iconv $CONFIGURE_OPTIONS;then
    if ! if_command iconv;then
        # 安装iconv
        # 获取最新版
        get_version LIBICONV_VERSION http://ftp.gnu.org/pub/gnu/libiconv/ 'libiconv-\d+\.\d+\.tar\.gz' '\d+\.\d+'
        echo "install libiconv-$LIBICONV_VERSION"
        # 下载
        download_software http://ftp.gnu.org/pub/gnu/libiconv/libiconv-$LIBICONV_VERSION.tar.gz
        # 编译安装
        configure_install --prefix=$INSTALL_BASE_PATH/libiconv/$LIBICONV_VERSION --enable-shared
    elif if_many_version iconv --version;then
        # 安装多个版本需要指定安装目录
        CONFIGURE_OPTIONS="$CONFIGURE_OPTIONS --with-iconv="`which iconv|grep -oP '/([^/]+/)+'|grep -oP '(/[^/]+)+'`
    else
        echo 'libiconv ok'
    fi
fi
# gmp扩展
if in_options gmp $CONFIGURE_OPTIONS;then
    if ldconfig -p|grep -q '/libgmp\.so' && find /usr/include/ -name 'gmp.h'|grep 'gmp' && find /usr/local/include/ -name 'gmp.h'|grep 'gmp';then
        echo 'gmp ok'
    else
        # 安装gmp-dev
        packge_manager_run install -GMP_DEVEL_PACKGE_NAMES
    fi
fi
# gd 扩展使用
if in_options gd $CONFIGURE_OPTIONS;then
    if if_lib 'libpng';then
        echo 'libpng ok'
    else
        # 安装png-dev
        packge_manager_run install -PNG_DEVEL_PACKGE_NAMES
    fi
    if if_lib 'freetype2';then
        echo 'freetype2 ok'
    else
        # 安装freetype
        packge_manager_run install -FREETYPE_DEVEL_PACKGE_NAMES
    fi
    # jpeg扩展使用
    if in_options jpeg $CONFIGURE_OPTIONS;then
        if if_version $PHP_VERSION '>=' 7.4.0;then
            # 安装 libjpeg
            if if_lib "libjpeg";then
                echo 'libjpeg ok'
            else
                # 获取最新版
                get_version JPEG_PATH http://www.ijg.org/files/ 'jpegsrc\.v\d+c\.tar\.gz' '.*'
                JPEG_VERSION=`echo $JPEG_PATH|grep -oP '\d+c\.tar\.gz$'|grep -oP '\d+'`
                echo "install jpeg-$JPEG_VERSION"
                # 下载
                download_software http://www.ijg.org/files/$JPEG_PATH "jpeg-"$JPEG_VERSION"c"
                # 编译安装
                configure_install --enable-shared --prefix=$INSTALL_BASE_PATH/jpeg/v$JPEG_VERSION"c"
            fi
        else
            # 安装jpeg-dev
            packge_manager_run install -JPEG_DEVEL_PACKGE_NAMES
        fi
    fi
fi
# zip 扩展使用
if in_options zip $CONFIGURE_OPTIONS;then
    if if_version $PHP_VERSION '<' 7.3.0;then
        if if_lib "libzip";then
            echo 'libzip ok'
        else
            # 安装libzip-dev
            packge_manager_run install -ZIP_DEVEL_PACKGE_NAMES
        fi
    elif ! if_lib "libzip" ">=" "1.2.0";then
        # 这里需要判断是否达到版本要求，达到了就不需要再安装了
        # libzip-1.4+ 版本需要使用cmake更高版本来安装，而cmake需要c++11安装相对麻烦
        # libzip-1.3+ 编译不能通过会提示 错误:‘LIBZIP_VERSION’未声明(在此函数内第一次使用)
        # 目前安装 1.2 版本可以通过编译
        LIBZIP_VERSION="1.2.0"
        echo "install libzip-$LIBZIP_VERSION"
        download_software https://libzip.org/download/libzip-$LIBZIP_VERSION.tar.gz
        # 删除旧包
        packge_manager_run remove -ZIP_DEVEL_PACKGE_NAMES
        # 安装zlib-dev
        packge_manager_run install -ZLIB_DEVEL_PACKGE_NAMES
        # 编译安装
        configure_install --prefix=$INSTALL_BASE_PATH/libzip/$LIBZIP_VERSION
        #cp /usr/local/lib/libzip/include/zipconf.h /usr/local/include/zipconf.h
    else
        echo 'libzip ok'
    fi
fi
# openssl 扩展使用
if in_options openssl $CONFIGURE_OPTIONS;then
    if if_version $PHP_VERSION '<' 7.4.0;then
        if if_lib "openssl";then
            echo 'openssl ok'
        else
            # 安装openssl-dev
            packge_manager_run install -OPENSSL_DEVEL_PACKGE_NAMES
        fi
    else
        # 安装 openssl
        if if_lib "openssl" ">=" "1.0.1";then
            echo 'openssl ok'
        else
            # 获取最新版
            get_version OPENSSL_VERSION https://www.openssl.org/source/ 'openssl-\d+\.\d+\.\d+[a-z]*\.tar\.gz[^\.]' '\d+\.\d+\.\d+[a-z]*'
            echo "install openssl-$OPENSSL_VERSION"
            # 下载
            download_software https://www.openssl.org/source/openssl-$OPENSSL_VERSION.tar.gz openssl-$OPENSSL_VERSION
            # 移除不要的组件
            packge_manager_run remove -OPENSSL_DEVEL_PACKGE_NAMES
            packge_manager_run remove openssl -OPENSSL_DEVEL_PACKGE_NAMES
            # 添加编译文件连接
            if [ ! -e './configure' ];then
                cp ./config ./configure
                if_error 'open make configure fail'
            fi
            # 编译安装
            configure_install --prefix=$INSTALL_BASE_PATH/openssl/$OPENSSL_VERSION
        fi
    fi
fi
# sqlite3 扩展使用
if ! in_options !sqlite3 $CONFIGURE_OPTIONS || ! in_options !pdo-sqlite $CONFIGURE_OPTIONS;then
    if if_version $PHP_VERSION '>=' 7.4.0;then
        if if_lib "sqlite3" ">" "3.7.4"; then
            echo 'sqlite3 ok'
        else
            # 安装tcl
            packge_manager_run install -TCL_PACKGE_NAMES
            # 获取最新版
            get_version SPLITE3_PATH https://www.sqlite.org/download.html '(\w+/)+sqlite-autoconf-\d+\.tar\.gz' '.*'
            SPLITE3_VERSION=`echo $SPLITE3_PATH|grep -oP '\d+\.tar\.gz$'|grep -oP '\d+'`
            echo "install sqlite3-$SPLITE3_VERSION"
            # 下载
            download_software https://www.sqlite.org/$SPLITE3_PATH
            # 编译安装
            configure_install --prefix=$INSTALL_BASE_PATH/sqlite/$SPLITE3_VERSION --enable-shared
        fi
    fi
fi
# xml 扩展使用
if in_options xml $CONFIGURE_OPTIONS || ! in_options !xml $CONFIGURE_OPTIONS;then
    if if_version $PHP_VERSION '<' 7.4.0;then
        if if_lib "libxml-2.0";then
            echo 'libxml ok'
        else
            # 安装libxml2-dev
            packge_manager_run install -LIBXML2_DEVEL_PACKGE_NAMES
        fi
    else
        # 安装libxml2
        if if_lib "libxml-2.0" ">=" "2.7.6";then
            echo 'libxml ok'
        else
            # 获取最新版
            get_version LIBXML2_VERSION "ftp://xmlsoft.org/libxml2/" 'libxml2-sources-\d+\.\d+\.\d+\.tar\.gz'
            echo "install libxml2-$LIBXML2_VERSION"
            # 下载
            download_software ftp://xmlsoft.org/libxml2/libxml2-sources-$LIBXML2_VERSION.tar.gz libxml2-$LIBXML2_VERSION
            # 安装 python-dev
            packge_manager_run install -PYTHON_DEVEL_PACKGE_NAMES
            # 编译安装
            configure_install --prefix=$INSTALL_BASE_PATH/libxml2/$LIBXML2_VERSION
        fi
    fi
fi
# apxs2 扩展使用
#if in_options apxs2 $CONFIGURE_OPTIONS;then
    # which httpd
    # which apxs
    #parse_options CONFIGURE_OPTIONS apxs2=/apxs
#fi
# ***编译必需依赖安装***
if if_version $PHP_VERSION '>=' 7.4.0;then
    # 需要bison-3.0及更高
    # 排查过编译文件是判断下面两文件，问题在于有时候解压时没有Zend目录
#        if test ! -f "$PHP_CONFIGURE_PATH/Zend/zend_language_parser.h" || test ! -f "$PHP_CONFIGURE_PATH/Zend/zend_language_parser.c"; then
#            # bison 安装
#            if if_command bison && if_version `bison -V|head -n 1|grep -oP '\d+\.\d+'` '>=' '3.0';then
#                echo 'bison ok'
#            else
#                # 获取最新版
#                get_version BISON_VERSION http://ftp.gnu.org/gnu/bison/ 'bison-\d+\.\d+\.tar\.gz'
#                echo "install bison-$BISON_VERSION"
#                # 下载
#                download_software http://ftp.gnu.org/gnu/bison/bison-$BISON_VERSION.tar.gz
#                # 编译安装
#                configure_install --prefix=$INSTALL_BASE_PATH/bison/$BISON_VERSION
#                # re2c 与 bison 是同时使用的，都是语言解析器
#                yum install -y re2c
#            fi
#        fi
    # 安装高版本的依赖
    if ! if_lib "oniguruma";then
        # 安装oniguruma-dev
        packge_manager_run install -ONIGURUMA_DEVEL_PACKGE_NAMES
        if ! if_lib "oniguruma"; then
            if [ ! -e "/usr/include/oniguruma.h" ];then
                # 下载
                download_software https://github.com/kkos/oniguruma/archive/v6.9.4.tar.gz oniguruma-6.9.4
                if [ ! -e 'configure' ];then
                    packge_manager_run install autoconf automake libtool
                    ./autogen.sh
                fi
                configure_install --prefix=$INSTALL_BASE_PATH/oniguruma/6.9.4
            else
                ONIG_PC_FILE='/usr/lib64/pkgconfig/oniguruma.pc'
                echo 'prefix=/usr' > $ONIG_PC_FILE
                echo 'exec_prefix=/usr' >> $ONIG_PC_FILE
                echo 'libdir=/usr/lib64' >> $ONIG_PC_FILE
                echo 'includedir=/usr/include' >> $ONIG_PC_FILE
                echo 'datarootdir=/usr/share' >> $ONIG_PC_FILE
                echo "datadir=/usr/share\n" >> $ONIG_PC_FILE
                echo 'Name: oniguruma' >> $ONIG_PC_FILE
                echo 'Description: Regular expression library' >> $ONIG_PC_FILE
                echo -n 'Version: ' >> $ONIG_PC_FILE
                echo `grep ONIGURUMA_VERSION /usr/include/oniguruma.h|grep -oP '\d+'`|sed -r 's/\s+/./g' >> $ONIG_PC_FILE
                echo 'Requires:' >> $ONIG_PC_FILE
                echo 'Libs: -L${libdir} -lonig' >> $ONIG_PC_FILE
                echo 'Cflags: -I${includedir}' >> $ONIG_PC_FILE
            fi
        fi
    fi
fi
# 进入编译目录
cd $PHP_CONFIGURE_PATH
# 编译安装PHP
configure_install $CONFIGURE_OPTIONS
# 创建用户组
add_user phpfpm
# 配置文件处理
echo 'set config file'
cp -f php.ini-production $INSTALL_PATH$PHP_VERSION/lib/php.ini
cd $INSTALL_PATH$PHP_VERSION
cp -f etc/php-fpm.conf.default etc/php-fpm.conf
cp -f etc/php-fpm.d/www.conf.default etc/php-fpm.d/www.conf


# 修改配置参数
MAX_CHILDREN=$(expr $HTREAD_NUM \* 200)
MIN_SPARE=$(expr $MAX_CHILDREN \* 0.1)
MAX_SPARE=$(expr $MAX_CHILDREN \* 0.5)
INIT_CHILDREN=$(expr $MAX_CHILDREN \* 0.3)
sed -ir "s/pm.max_children\s*=\s*[0-9]+/pm.max_children = $MAX_CHILDREN/" etc/php-fpm.d/www.conf
sed -ir "s/pm.start_servers\s*=\s*[0-9]+/pm.start_servers = $INIT_CHILDREN/" etc/php-fpm.d/www.conf
sed -ir "s/pm.min_spare_servers\s*=\s*[0-9]+/pm.min_spare_servers = $MIN_SPARE/" etc/php-fpm.d/www.conf
sed -ir "s/pm.max_spare_servers\s*=\s*[0-9]+/pm.max_spare_servers = $MAX_SPARE/" etc/php-fpm.d/www.conf
sed -ir "s/pm.max_requests\s*=\s*[0-9]+/pm.max_requests = $MAX_CHILDREN/" etc/php-fpm.d/www.conf
# 开启opcache
if [ -z "`cat lib/php.ini|grep zend_extension=opcache.so`" ]; then
    echo "zend_extension=opcache.so" >> lib/php.ini
fi
# 修改配置
sed -ir 's/;opcache.enable=[0-1]/opcache.enable=1/' lib/php.ini
# CLI环境下，PHP启用OPcache
sed -ir 's/;opcache.enable_cli=[0-1]/opcache.enable_cli=1/' lib/php.ini
# OPcache共享内存存储大小,单位MB
sed -ir 's/;opcache.memory_consumption=[0-9]+/opcache.memory_consumption=512/' lib/php.ini
# 缓存多少个PHP文件
sed -ir 's/;opcache.max_accelerated_files=[0-9]+/opcache.max_accelerated_files=20000/' lib/php.ini
# 打开快速关闭, 在PHP Request Shutdown的时候回收内存的速度会提高
sed -ir 's/;opcache.fast_shutdown=[0-9]+/opcache.fast_shutdown=1/' lib/php.ini
# 设置的间隔秒数去检测文件的时间戳（timestamp）检查脚本是否更新
sed -ir 's/;opcache.validate_timestamps=[0-9]+/opcache.validate_timestamps=0/' lib/php.ini
# 设置缓存的过期时间（单位是秒）,为0的话每次都要检查，当opcache.validate_timestamps=0此配置无效
# sed -ir 's/;opcache.revalidate_freq=[0-9]+/opcache.revalidate_freq=60/' lib/php.ini
# 上传配置
sed -ir 's/upload_max_filesize\s+=\s+[0-9]+M/upload_max_filesize = 8M/' lib/php.ini

# 启动服务
echo './sbin/php-fpm -c ./lib/ -y ./etc/php-fpm.conf --pid=./run/php-fpm.pid'
./sbin/php-fpm -c ./lib/ -y ./etc/php-fpm.conf --pid=./run/php-fpm.pid
# 添加执行文件连接
ln -svf $INSTALL_PATH$PHP_VERSION/bin/php /usr/local/bin/php
# 证书处理 主要针对 https 类的请求处理
# 更新证书命令会造成 fsockopen 使用ssl 出错等
PHP_SSL_LOCA_CERT_FILE=`php -r "echo openssl_get_cert_locations()['default_cert_file'];"`
if [ -n "$PHP_SSL_LOCA_CERT_FILE" ] && [ ! -e "$PHP_SSL_LOCA_CERT_FILE" ];then
    download_software https://curl.haxx.se/ca/cacert.pem cert_pem
    if [ ! -e 'cacert.pem' ];then
        mv cacert.pem $PHP_SSL_LOCA_CERT_FILE
    fi
fi
echo "install php-$PHP_VERSION success!";
