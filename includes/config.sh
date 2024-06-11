#!/bin/bash
# ************** 包管理器安装应对的包名 ************** #
# 配置规则
# CONFIG_NAME=(yum apt dnf pkg)
# 此配置需要与包管理器命令顺序一至，配置规则：
# 1、当各包管理器对应的工具名相同时只需要配置一个，比如：UNZIP_PACKAGE_NAMES=('unzip')
# 2、只有部分包管理器需要安装时，其它对应的工具名指定为 "-"，比如：POPT_DEVEL_PACKAGE_NAMES=('popt-devel' '-')
# 3、未指定包名的将路过安装
# 此配置设置支持的系统包管理器，用于不同的系统来运行
# 安装命令
PACKAGE_MANAGER_INSTALL_COMMAND=('yum -y install' 'apt -y install' 'dnf -y install' 'pkg -y install')
# 更新命令
PACKAGE_MANAGER_UPDATE_COMMAND=('yum -y update' 'apt -y update' 'dnf -y update' 'pkg -y update')
# 删除命令
PACKAGE_MANAGER_REMOVE_COMMAND=('yum -y erase' 'apt -y remove' 'dnf -y erase' 'pkg -y delete')
# 包信息
PACKAGE_MANAGER_INFO_COMMAND=('yum info' 'apt show' 'dnf info' 'pkg info')
# 包后缀
PACKAGE_MANAGER_FILE_SUFFIX=('rpm' 'deb' 'rpm')

# 安装xz压缩工具
XZ_PACKAGE_NAMES=('xz' 'xz-utils')
# 安装unzip解压工具
UNZIP_PACKAGE_NAMES=('unzip')
# 安装libtool
LIBTOOL_PACKAGE_NAMES=('libtool')
# 安装openssl
OPENSSL_DEVEL_PACKAGE_NAMES=('openssl-devel' 'libssl-dev')
# 安装zlib
ZLIB_DEVEL_PACKAGE_NAMES=('zlib-devel' 'zlib1g-dev')
# 安装pcre
PCRE_DEVEL_PACKAGE_NAMES=('pcre-devel' 'libpcre3-dev')
# 安装ca证书
CA_CERT_PACKAGE_NAMES=('ca-certificates')
# 安装CURL
CURL_DEVEL_PACKAGE_NAMES=('curl-devel' 'libcurl4-openssl-dev')
# 安装png
PNG_DEVEL_PACKAGE_NAMES=('libpng-devel' 'libpng-dev')
# 安装gmp高精度运算
GMP_DEVEL_PACKAGE_NAMES=('gmp-devel' 'libgmp-dev')
# 安装jpeg
JPEG_DEVEL_PACKAGE_NAMES=('libjpeg-devel' 'libjpeg-dev')
# 安装zip
ZIP_DEVEL_PACKAGE_NAMES=('libzip-devel' 'libzip-dev')
# 安装python
PYTHON_DEVEL_PACKAGE_NAMES=('python-devel' 'python-dev')
# 安装xml2
LIBXML2_DEVEL_PACKAGE_NAMES=('libxml2-devel' 'libxml2-dev')
# 安装freetype
FREETYPE_DEVEL_PACKAGE_NAMES=('freetype-devel' 'libfreetype6-dev')
# 安装 oniguruma
ONIGURUMA_DEVEL_PACKAGE_NAMES=('oniguruma-devel' 'libonig-dev')
# 安装mcrypt
LIBMCRYPT_DEVEL_PACKAGE_NAMES=('libmcrypt-devel' 'libmcrypt-dev')
# 安装tcl
TCL_PACKAGE_NAMES=('tcl')
# 安装perl
PERL_DEVEL_PACKAGE_NAMES=('perl-devel' 'perl-dev')
# 安装apr
APR_DEVEL_PACKAGE_NAMES=('apr-devel' 'libapr1-dev')
# 安装apr-util
APR_UTIL_DEVEL_PACKAGE_NAMES=('apr-util-devel' 'libapr1-util-dev')
# 安装sqlite
SQLITE_DEVEL_PACKAGE_NAMES=('sqlite-devel' 'sqlite-dev')
# 安装gcc-c++
GCC_C_PACKAGE_NAMES=('gcc-c++' 'g++')
# 安装bzip2
BZIP2_DEVEL_PACKAGE_NAMES=('bzip2-devel' 'bzip2-dev')
BZIP2_PACKAGE_NAMES=('bzip2' 'bzip2')
# 安装m4
M4_PACKAGE_NAMES=('m4')
# 安装autoconf
AUTOCONF_PACKAGE_NAMES=('autoconf')
# 安装jemalloc
JEMALLOC_DEVEL_PACKAGE_NAMES=('jemalloc-devel' 'libjemalloc-dev')
# 安装libedit
LIBEDIT_DEVEL_PACKAGE_NAMES=('libedit-devel' 'libedit-dev')
# 安装libunwind
LIBUWIND_DEVEL_PACKAGE_NAMES=('libunwind-devel' 'libunwind-dev')
# 安装ncurses
NCURSES_DEVEL_PACKAGE_NAMES=('ncurses-devel' 'libncurses5-dev')
# 安装pkgconfig
PKGCONFIG_PACKAGE_NAMES=('pkgconfig' 'pkg-config')
# 安装python3
PYTHON3_DOCUTILS_PACKAGE_NAMES=('-' 'python3-docutils')
# 安装python3
PYTHON3_SPHINX_PACKAGE_NAMES=('-' 'python3-sphinx')
# 安装python-docutils
PYTHON_DOCUTILS_PACKAGE_NAMES=('python-docutils')
# 安装python-sphinx
PYTHON_SPHINX_PACKAGE_NAMES=('python-sphinx')
# 安装readline
READLINE_DEVEL_PACKAGE_NAMES=('readline-devel' 'libreadline-dev')
# 安装libffi
LIBFFI_DEVEL_PACKAGE_NAMES=('libffi-devel' 'libffi-dev')
# 安装gettext
GETTEXT_DEVEL_PACKAGE_NAMES=('gettext-devel' 'gettext-dev')
# 安装java
JAVA8_PACKAGE_NAMES=('java-1.8.0-openjdk' '-')
JAVA11_PACKAGE_NAMES=('java-11-openjdk' '-')
# 安装libnl3
LIBNL3_DEVEL_PACKAGE_NAMES=('libnl3-devel' 'libnl-genl-3-dev')
# 安装libnl3-route
LIBNL3_ROUTE_DEVEL_PACKAGE_NAMES=('-' 'libnl-route-3-dev')
# 安装libnl
LIBNL_DEVEL_PACKAGE_NAMES=('libnl-devel' 'libnlopt-dev')
# 安装popt
POPT_DEVEL_PACKAGE_NAMES=('popt-devel' 'libpopt-dev')
# 安装popt-static
POPT_STATIC_PACKAGE_NAMES=('popt-static' '-')
# 安装iptables-devel
IPTABLES_DEVEL_PACKAGE_NAMES=('iptables-devel' 'iptables-dev')
# 安装ipset-devel
IPSET_DEVEL_PACKAGE_NAMES=('ipset-devel' 'libipset-dev')
# 安装libnfnetlink-devel
LIBNFNETLINK_DEVEL_PACKAGE_NAMES=('libnfnetlink-devel' 'libnfnetlink-dev')
# 安装glibc-devel
GLIBC_DEVEL_PACKAGE_NAMES=('glibc-devel' 'linux-libc-dev')
# 安装kernel-headers
KERNEL_HEADERS_PACKAGE_NAMES=('kernel-headers' "linux-headers-$(uname -r)")
# 安装libevent-devel
LIBEVENT_DEVEL_PACKAGE_NAMES=('libevent-devel' 'libevent-dev')