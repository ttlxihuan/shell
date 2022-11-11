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
# CentOS 6.4+
# Ubuntu 16.04+
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
#       执行命令：yum -y update nss 不行则需要重装curl
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
#  8、configure报：（说明openssl版本过高了，需要低点版本的，类似的问题也都是版本不兼容）
#       checking for libcurl linked against old openssl... no
#       checking for curl_easy_perform in -lcurl... no
#       configure: error: There is something wrong. Please check config.log for more information.
#
#
####################################################################################
##################################### 安装处理 #####################################
####################################################################################
# 域名
PHP_HOST='www.php.net'
# 定义安装类型
DEFINE_INSTALL_TYPE='configure'
# 编译默认项（这里的配置会随着编译版本自动生成编译项）
DEFAULT_OPTIONS='sockets ?pdo-mysql mysqli fpm openssl curl bcmath ?xml mhash mbstring zip zlib gd jpeg ?png freetype ?gd-native-ttf ?mcrypt ?!pdo-sqlite ?!sqlite3 ?swoole ?pcntl gmp'
# 加载基本处理
source "$(cd "$(dirname "${BASH_SOURCE[0]}")"; pwd)"/../../includes/install.sh || exit
# 初始化安装
init_install '7.0.0' "https://$PHP_HOST/supported-versions.php" '#v\d+\.\d+\.\d+'
#  限制空间大小（G）：编译目录、安装目录、内存
install_storage_require 1 1 4
# ************** 相关配置 ******************
# 编译初始选项（这里的指定必需有编译项）
CONFIGURE_OPTIONS="--prefix=$INSTALL_PATH$PHP_VERSION "
# 配置编译安装pecl扩展块信息，只有指定了才会认定为pecl扩展包，并且需要在上面的选项中添加上（需要指定为询问安装比如 ?swoole），否则不会进行安装或安装异常
# 如果扩展包源文件已经放到PHP编译目录中则同PHP一起编译安装
# 如果没有则在PHP编译安装完成后再通过phpize方式安装
# 注意：有依赖的扩展包需要提前安装好依赖，需要通过phpize安装的扩展并在这里设置好相关编译配置
# 配置格式：扩展名={版本 编译选项集...}
# 版本默认为new是最新，其它为指定版本号
PECL_OPTIONS='swoole={new ?openssl ?http2} yar gmagick mongodb'
# ************** 编译安装 ******************
# 下载PHP包
download_software https://$PHP_HOST/distributions/php-$PHP_VERSION.tar.gz
# 暂存编译目录
PHP_CONFIGURE_PATH=`pwd`
# 解析选项
parse_options CONFIGURE_OPTIONS $DEFAULT_OPTIONS $ARGV_options
# 安装依赖
info_msg "安装相关已知依赖"
# ca-certificates 根证书更新
package_manager_run install -CA_CERT_PACKAGE_NAMES
# ***选项处理&选项依赖安装***
# fpm 附加选项增加
if has_option fpm $CONFIGURE_OPTIONS;then
    parse_options CONFIGURE_OPTIONS fpm-user=phpfpm fpm-group=phpfpm
fi
# mcrypt 扩展使用（PHP7已经不再使用）
if has_option mcrypt $CONFIGURE_OPTIONS;then
    if if_command libmcrypt-config;then
        info_msg 'libmcrypt ok'
    else
        # 安装 libmcrypt
        package_manager_run install -LIBMCRYPT_DEVEL_PACKAGE_NAMES
        if ! if_command libmcrypt-config;then
            # 下载
            download_software https://nchc.dl.sourceforge.net/project/mcrypt/Libmcrypt/2.5.8/libmcrypt-2.5.8.tar.gz "libmcrypt-2.5.8"
            # 编译安装
            configure_install
        fi
    fi
fi
# iconv扩展
if ! has_option !iconv $CONFIGURE_OPTIONS;then
    # 安装验证 iconv
    install_iconv
    #if if_many_version iconv --version;then
        # 安装多个版本需要指定安装目录
    #    CONFIGURE_OPTIONS="$CONFIGURE_OPTIONS --with-iconv=$(dirname ${INSTALL_iconv_PATH%/*}) "
    #fi
fi
# gmp扩展
if has_option gmp $CONFIGURE_OPTIONS;then
    # 提取gmp最低版本
    GMP_MIN_VERSION=$(grep -oP 'GNU MP Library version \d+(\.\d+)+' $PHP_CONFIGURE_PATH/configure|grep -oP '\d+(\.\d+)+'|tail -n 1)
    repair_version GMP_MIN_VERSION
    # 安装验证 gmp
    install_gmp "$GMP_MIN_VERSION"
fi
# gd 扩展使用
if has_option gd $CONFIGURE_OPTIONS;then
    if if_lib_range 'libpng';then
        info_msg 'libpng ok'
    else
        # 安装png-dev
        package_manager_run install -PNG_DEVEL_PACKAGE_NAMES
    fi
    if if_lib_range 'freetype2';then
        info_msg 'freetype2 ok'
    else
        # 安装freetype
        package_manager_run install -FREETYPE_DEVEL_PACKAGE_NAMES
    fi
    # jpeg扩展使用
    if has_option jpeg $CONFIGURE_OPTIONS;then
        if if_version $PHP_VERSION '>=' 7.4.0;then
            # 安装 libjpeg
            if if_lib_range "libjpeg";then
                info_msg 'libjpeg ok'
            else
                # 获取最新版
                get_download_version JPEG_PATH http://www.ijg.org/files/ 'jpegsrc\.v\d+c\.tar\.gz' '.*'
                JPEG_VERSION=`echo $JPEG_PATH|grep -oP '\d+c\.tar\.gz$'|grep -oP '\d+'`
                info_msg "安装：jpeg-$JPEG_VERSION"
                # 下载
                download_software http://www.ijg.org/files/$JPEG_PATH "jpeg-${JPEG_VERSION}c"
                # 编译安装
                configure_install --enable-shared --prefix=$INSTALL_BASE_PATH/jpeg/v${JPEG_VERSION}c
            fi
        else
            # 安装jpeg-dev
            package_manager_run install -JPEG_DEVEL_PACKAGE_NAMES
        fi
    fi
fi
# zip 扩展使用
if has_option zip $CONFIGURE_OPTIONS;then
    if if_version $PHP_VERSION '<' 7.3.0;then
        MIN_LIBZIP_VERSION=''
    else
        MIN_LIBZIP_VERSION='1.2.0'
    fi
    install_zip "$MIN_LIBZIP_VERSION"
fi
# openssl 扩展使用
if has_option openssl $CONFIGURE_OPTIONS;then
    if if_version $PHP_VERSION '<' 7.0.0;then
        MIN_OPENSSL_VERSION=''
        MAX_OPENSSL_VERSION=''
    else
        MIN_OPENSSL_VERSION='1.0.2'
        MAX_OPENSSL_VERSION='1.1.1g'
    fi
    install_openssl "$MIN_OPENSSL_VERSION" "$MAX_OPENSSL_VERSION" "$MAX_OPENSSL_VERSION"
fi
# curl 扩展使用
if has_option curl $CONFIGURE_OPTIONS;then
    if if_version $PHP_VERSION '<' 8.0.0;then
        MIN_CURL_VERSION=''
    elif ! if_lib_range "libcurl" '7.29.0';then
        MIN_CURL_VERSION='7.29.0'
    fi
    install_curl "$MIN_CURL_VERSION"
    # 获取libcurl安装目录
    get_lib_install_path libcurl LIBCURL_INSTALL_PATH
    if [ -n "$LIBCURL_INSTALL_PATH" ];then
        CONFIGURE_OPTIONS="${CONFIGURE_OPTIONS/--with-curl /--with-curl=$LIBCURL_INSTALL_PATH }"
    fi
fi
# sqlite3 扩展使用
if ! has_option !sqlite3 $CONFIGURE_OPTIONS || ! has_option !pdo-sqlite $CONFIGURE_OPTIONS;then
    if if_version $PHP_VERSION '>=' 7.4.0;then
        MIN_SQLITE_VERSION='3.7.4'
    else
        MIN_SQLITE_VERSION='3.0.0'
    fi
    install_sqlite "$MIN_SQLITE_VERSION"
fi
# xml 扩展使用
if has_option xml $CONFIGURE_OPTIONS || ! has_option !xml $CONFIGURE_OPTIONS;then
    if if_version $PHP_VERSION '>=' 8.0.0;then
        MIN_LIBXML2_VERSION='2.9.0'
    else
        MIN_LIBXML2_VERSION='2.7.6'
    fi
    # 安装验证 libxml2
    install_libxml2 "$MIN_LIBXML2_VERSION"

    # 获取libxml安装目录
    get_lib_install_path libxml-2.0 LIBXML2_INSTALL_PATH
    if [ -n "$INSTALL_LIBXML2_PATH" ];then
        CONFIGURE_OPTIONS="$CONFIGURE_OPTIONS --with-libxml-dir=$LIBXML2_INSTALL_PATH "
    fi
fi
# 安装swoole，要求gcc-4.8+
if has_parse_option swoole $DEFAULT_OPTIONS $ARGV_options;then
    # php编译gcc版本不能过高，暂时限制在 4.8.0+
    install_gcc "4.8.0"
fi
# apxs2 扩展使用
#if has_option apxs2 $CONFIGURE_OPTIONS;then
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
#                info_msg 'bison ok'
#            else
#                # 获取最新版
#                get_download_version BISON_VERSION http://ftp.gnu.org/gnu/bison/ 'bison-\d+\.\d+\.tar\.gz'
#                info_msg "安装：bison-$BISON_VERSION"
#                # 下载
#                download_software http://ftp.gnu.org/gnu/bison/bison-$BISON_VERSION.tar.gz
#                # 编译安装
#                configure_install --prefix=$INSTALL_BASE_PATH/bison/$BISON_VERSION
#                # re2c 与 bison 是同时使用的，都是语言解析器
#                yum install -y re2c
#            fi
#        fi
    # 安装高版本的依赖
    if ! if_lib_range "oniguruma";then
        # 安装oniguruma-dev
        package_manager_run install -ONIGURUMA_DEVEL_PACKAGE_NAMES
        if ! if_lib_range "oniguruma"; then
            if [ ! -e "/usr/include/oniguruma.h" ];then
                # 下载
                download_software https://github.com/kkos/oniguruma/archive/v6.9.4.tar.gz oniguruma-6.9.4
                if [ ! -e 'configure' ];then
                    install_autoconf
                    package_manager_run install automake libtool
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
info_msg 'php 配置文件修改'
cp -f php.ini-production $INSTALL_PATH$PHP_VERSION/lib/php.ini
cd $INSTALL_PATH$PHP_VERSION
cp -f etc/php-fpm.conf.default etc/php-fpm.conf
cp -f etc/php-fpm.d/www.conf.default etc/php-fpm.d/www.conf

# 修改配置参数
info_msg '修改php-fpm配置'
math_compute MAX_CHILDREN "$TOTAL_THREAD_NUM * 10"
math_compute MIN_SPARE "$MAX_CHILDREN * 0.1"
math_compute MAX_SPARE "$MAX_CHILDREN * 0.5"
math_compute INIT_CHILDREN "$MAX_CHILDREN * 0.3"
sed -i -r "s/^;?(pm\.max_children\s*=\s*)[0-9]+/\1$MAX_CHILDREN/" etc/php-fpm.d/www.conf
sed -i -r "s/^;?(pm\.start_servers\s*=\s*)[0-9]+/\1$INIT_CHILDREN/" etc/php-fpm.d/www.conf
sed -i -r "s/^;?(pm\.min_spare_servers\s*=\s*)[0-9]+/\1$MIN_SPARE/" etc/php-fpm.d/www.conf
sed -i -r "s/^;?(pm\.max_spare_servers\s*=\s*)[0-9]+/\1$MAX_SPARE/" etc/php-fpm.d/www.conf
sed -i -r "s/^;?(pm\.max_requests\s*=\s*)[0-9]+/\1$MAX_CHILDREN/" etc/php-fpm.d/www.conf
# 开启opcache
if [ -z "`cat lib/php.ini|grep zend_extension=opcache.so`" ]; then
    echo "zend_extension=opcache.so" >> lib/php.ini
fi
if $INSTALL_PATH$PHP_VERSION/bin/php -m|grep -qP '^Zend OPcache$';then
    info_msg '开启opcache'
    # 修改配置
    sed -i -r 's/^;?(opcache\.enable=)[0-1]/\11/' lib/php.ini
    # CLI环境下，PHP启用OPcache
    sed -i -r 's/^;?(opcache\.enable_cli=)[0-1]/\11/' lib/php.ini
    # OPcache共享内存存储大小,单位MB
    sed -i -r 's/^;?(opcache.memory_consumption=)[0-9]+/\1512/' lib/php.ini
    # 缓存多少个PHP文件
    sed -i -r 's/^;?(opcache.max_accelerated_files=)[0-9]+/\120000/' lib/php.ini
    # 打开快速关闭, 在PHP Request Shutdown的时候回收内存的速度会提高
    sed -i -r 's/^;?(opcache.fast_shutdown=)[0-9]+/\11/' lib/php.ini
    # 设置的间隔秒数去检测文件的时间戳（timestamp）检查脚本是否更新
    sed -i -r 's/^;?(opcache.validate_timestamps=)[0-9]+/\10/' lib/php.ini
    if if_version $PHP_VERSION '>=' '8.0.0';then
        info_msg '开启opcache-jit'
        if grep -qP ';?(opcache\.jit=)' lib/php.ini;then
            # 存在配置直接修改
            sed -i -r 's/^;?(opcache\.jit=)[0-1]/\11/' lib/php.ini
            sed -i -r 's/^;?(opcache\.jit_buffer_size=)[0-1]/\11/' lib/php.ini
        else
            # 不存在配置添加
            OPCACHE_LINE_NUM=$(grep -onP ';?(opcache\.enable=)' lib/php.ini|grep -oP '^\d+')
            if [ -n "$OPCACHE_LINE_NUM" ];then
                sed -i "${OPCACHE_LINE_NUM}iopcache.jit_buffer_size=128M" lib/php.ini
                # 注意，此配置有多种可选值，在官方文档中有详细说明
                sed -i "${OPCACHE_LINE_NUM}iopcache.jit=1205" lib/php.ini
            else
                echo "opcache.jit=1205" >> lib/php.ini
                echo "opcache.jit_buffer_size=128M" >> lib/php.ini
            fi
        fi
    fi
fi

# 设置缓存的过期时间（单位是秒）,为0的话每次都要检查，当opcache.validate_timestamps=0此配置无效
# sed -i -r 's/^;?(opcache.revalidate_freq=)[0-9]+/\160/' lib/php.ini
# 上传配置
info_msg '修改php上传文件大小为8M'
sed -i -r 's/^;?(upload_max_filesize\s+=\s+)[0-9]+M/\18M/' lib/php.ini
# 隐藏php响应头信息
sed -i -r 's/^\s*(expose_php\s*=)\s*On/\1Off/' lib/php.ini

info_msg '处理pecl扩展'
# 解析处理pecl扩展
echo "$PECL_OPTIONS"|grep -oP '\w[\w\-]+(\s*=\s*\{[^\{\}]+\})?\s+'| while read EXT_CONFIG
do
    EXT_NAME="`echo $EXT_CONFIG|grep -oP '^\w[\w\-]+'`"  EXT_OPTIONS="`echo $EXT_CONFIG|grep -oP '\{[^\{\}]+\}'|grep -oP '[^\{\}]+'`" EXT_VERSION='new' EXT_ADD_OPTIONS=''
    if [ -n "$EXT_OPTIONS" ];then
        EXT_VERSION="`echo $EXT_OPTIONS|awk '{print $1}'`"
        EXT_ADD_OPTIONS="`echo $EXT_OPTIONS|awk '{$1=""; print}'`"
    fi
    if has_parse_option $EXT_NAME $DEFAULT_OPTIONS $ARGV_options && ! $INSTALL_PATH$PHP_VERSION/bin/php -m|grep -qP "^$EXT_NAME\$";then
        info_msg "安装pecl扩展：$EXT_NAME"
        # 最低PHP版本处理
        get_download_version MIN_PHP_VERSION "https://pecl.php.net/package/$EXT_NAME" "PHP Version: PHP \d+\.\d+\.\d+ or newer" "\d+\.\d+\.\d+"
        if if_version $MIN_PHP_VERSION '>' $PHP_VERSION;then
            warn_msg "$EXT_NAME 需要 php 版本大于：$MIN_PHP_VERSION"
            continue
        fi
        if [ -z $EXT_VERSION ] || [[ $EXT_VERSION == "new" ]]; then
            info_msg "获取 $EXT_NAME 最新版本号"
            get_download_version EXT_VERSION "https://pecl.php.net/package/$EXT_NAME" "$EXT_NAME-\d+\.\d+\.\d+.tgz" "\d+\.\d+\.\d+"
        fi
        info_msg "安装：$EXT_NAME-$EXT_VERSION"
        # 下载
        download_software https://pecl.php.net/get/$EXT_NAME-$EXT_VERSION.tgz
        if [ ! -e "./configure.ac" ];then
            $INSTALL_PATH$PHP_VERSION/bin/phpize
        fi
        # 获取autoconf版本要求
        if [ -e "./configure.ac" ];then
            PHP_EXT_CONFIGURE_PATH=$(pwd)
            AUTOCONF_MIN_VERSION=$(grep AC_PREREQ ./configure.ac|grep -oP '\d+(\.\d+)+');
            install_autoconf $AUTOCONF_MIN_VERSION
            cd "$PHP_EXT_CONFIGURE_PATH"
        fi
        # 通过phpize安装，生成configure编译文件
        $INSTALL_PATH$PHP_VERSION/bin/phpize
        if [ ! -e './configure' ];then
            warn_msg "生成configure文件失败，跳过安装：$EXT_NAME"
            continue
        fi
        # 解析选项
        parse_options EXT_CONFIGURE_OPTIONS $EXT_ADD_OPTIONS
        # 编译安装phpize
        configure_install $EXT_CONFIGURE_OPTIONS --with-php-config=$INSTALL_PATH$PHP_VERSION/bin/php-config
        cd $INSTALL_PATH$PHP_VERSION
        # 开启扩展
        if [ -z "`cat lib/php.ini|grep extension=$EXT_NAME.so`" ]; then
            echo "extension=$EXT_NAME.so" >> lib/php.ini
        fi
        info_msg "安装成功：$EXT_NAME-$EXT_VERSION"
    else
        info_msg "$EXT_NAME 扩展已安装"
    fi
done

# 添加服务配置
SERVICES_CONFIG=()
SERVICES_CONFIG[$SERVICES_CONFIG_START_RUN]="./sbin/php-fpm -c ./lib/ -y ./etc/php-fpm.conf --pid=./run/php-fpm.pid"
SERVICES_CONFIG[$SERVICES_CONFIG_PID_FILE]="./run/php-fpm.pid"
# 服务并启动服务
add_service SERVICES_CONFIG

# 添加执行文件连接
add_local_run $INSTALL_PATH$PHP_VERSION/bin/ php

# 证书处理 主要针对 https 类的请求处理
# 更新证书命令会造成 fsockopen 使用ssl 出错等
PHP_SSL_LOCA_CERT_FILE=`php -r "echo openssl_get_cert_locations()['default_cert_file'];"`
if [ -n "$PHP_SSL_LOCA_CERT_FILE" ] && [ ! -e "$PHP_SSL_LOCA_CERT_FILE" ];then
    download_software https://curl.haxx.se/ca/cacert.pem cert_pem
    if [ ! -e 'cacert.pem' ];then
        mv cacert.pem $PHP_SSL_LOCA_CERT_FILE
    fi
fi
info_msg "安装成功：php-$PHP_VERSION";
