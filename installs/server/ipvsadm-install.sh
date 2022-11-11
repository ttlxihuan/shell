#!/bin/bash
#
# ipvsadm快速编译安装shell脚本
# 官方地址：http://www.linux-vs.org/zh/index.html
#          http://www.linuxvirtualserver.org/Documents.html
#
# lvs 文档：http://www.austintek.com/LVS/LVS-HOWTO/HOWTO/
#
# 收集文档：
#     故障排查 http://ja.ssi.bg/L4-NAT-HOWTO.txt
#             http://ja.ssi.bg/TUN-HOWTO.txt
#             http://ja.ssi.bg/LVS_IPSEC.txt
#             http://ja.ssi.bg/LVS.txt
#             http://ja.ssi.bg/fib.txt
#     https://www.kernel.org/doc/html/latest/networking/ipvs-sysctl.html
#
# 隧道文档：
#     https://developers.redhat.com/blog/2019/05/17/an-introduction-to-linux-virtual-interfaces-tunnels
#
# 安装命令
# bash ipvsadm-install.sh new
# bash ipvsadm-install.sh $verions_num
# 
# 查看最新版命令
# bash ipvsadm-install.sh
#
# 可运行系统：
# CentOS 6.4+
# Ubuntu 16.04+
#
# LVS（Linux Virtual Server）是Linux虚拟服务，运行在内核中，工作在第4层网络，修改配置后可是一个高性能负载均衡服务。
# ipvsadm是实现LVS对外操作工具（类似iptables命令），ipvsadm受系统内核限制，不同的版本对系统内核有要求，不过现在的系统内核基本上已经远远超过了，要求最低的内核是1.1.8。
# ipvsadm最新版本是在2011年2月份更新的，后面没有更新
# LVS是使用虚拟路由冗余协议(Virtual Router Redundancy Protocol，简称VRRP)
#
# 【特别说明】：ipvsadm虽然是高效负载均衡器，但应用并不多相关文档也比较旧且存在兼容性问题。
#         ipvsadm配置使用和问题排查困难，因为其工作在内核层（数据运转追踪困难）并受内核差异影响，并不能像nginx、varnish等用户态负载均衡好使用，
#         虽然后者性能并不如前者，但后者使用方便并对系统内核无过多要求兼容性好，对于服务器运维能力不足的团队更建议使用用户态负载均衡器，一味追求上当次最后可能因能力和准备不足而翻跟头。
#
#
# 功能说明：
#   1、ipvsadm 主要是操作虚拟服务器（负载均衡器）表（实际就是在本机创建多个虚拟服务器地址）和真实服务器（后台服务器集）表，请求将先从虚拟服务器上接收按指定的负载均衡算法调度给某台真实服务器，
#       通过三种不同的模式进行转发处理，转发是在内核中完成（即无监听进程）速度要比用户态进程处理快，当请求连接请求过来时立即匹配请求地址，符合即进入转发流程，否则进入用户态进程。
#       非本机发送进来的请求会经过路由防火墙等模块相关信息会有变量，不同的工作模式需要作相关配置处理。
#   2、ipvsadm 还提供一了个连接同步功能（ipvs 0.9.2+或内核2.4起有效）简易的故障转移解决方案，连接同步在内核中完成减少用户态切换开销（同步连接使用UDP多播方式传播），
#       需要在一个主多备场景下，只需要在主均衡器上编辑配置即可自动同步到各备均衡器上，当主均衡器故障时可直接切换到备均衡器上（可以理解为只需要配置一次均衡器即可完成各备均衡器同步配置）。
#       但是切换需要人工操作同步连接不具备自动切换功能，实际同步连接会增加主均衡器的额外开销（虽然很小），一般此功能使用在高可用场景下，通过类似keepalived之类的工具进行自动主备切换。
#
# 工作模式：（防火墙需要开放）
#   1、NAT模式，一个公网地址作为入口（负载均衡器），通过LVS调度器访问各节点（节点不需要访问外网权限），请求与响应均需要通过负载均衡器（LVS调度器），单点负载均衡器吞吐量一般建议后台服务器个数在20台以内
#       该模式不需要修改节点，节点可是负载均衡器能访问的任何网络。也没有额外服务监听（没有指定端口号的监听服务），不限制负载均衡器与后台服务器的端口号必需相同（即允许端口号映射）
#       直接添加虚拟服务器（绑定到网卡IP地址上），再添加真实服务器（转发后台服务器）并指定NAT模式（-m 参数）即可使用，该模式修改修改来源IP地址进行转，所有不适用于收录来源IP场景。
#       文档：http://www.austintek.com/LVS/LVS-HOWTO/HOWTO/LVS-HOWTO.LVS-NAT.html
#       示例流程：（只配置负载均衡器）
#          1、添加虚拟服务器
#               ipvsadm -A -t 192.168.1.10:88 -s rr     添加虚拟服务器转发地址192.168.1.10:88，转发协议TCP，指定转发算法为轮询
#          2、添加转发后台真实服务器
#               ipvsadm -a -t 192.168.1.10:88 -r 192.168.1.11:80 -m -w 1    添加真实服务器192.168.1.11:80，转发来源虚拟服务器为192.168.1.10:88，转发协议TCP，指定NAT模式，权重值为1
#               ipvsadm -a -t 192.168.1.10:88 -r 192.168.1.12:80 -m -w 1    添加真实服务器192.168.1.12:80，转发来源虚拟服务器为192.168.1.10:88，转发协议TCP，指定NAT模式，权重值为1
#          3、查看规则
#               ipvsadm -l    应该可看到上面配置的规则（IP地址或端口号可能被转为英文表示）
#          4、开启连接跟踪（部分系统无此配置项，需要编译安装IPVS时CONFIG_IP_VS_NFCT=1启用）
#                echo 1 > /proc/sys/net/ipv4/vs/conntrack
#          5、外机访问转发配置，开启IP转发功能（如果 /proc/sys/net/ipv4/ip_forward 文件不存在时运行 modprobe ip_tables）
#                echo 1 > /proc/sys/net/ipv4/ip_forward
#          5、防火墙配置（需要借助iptables发送伪装包功能，外机访问必需项）
#              端口访问许可（注意端口号）
#                 iptables -I INPUT -p tcp -m state --state NEW -m tcp --dport 80 -j ACCEPT
#              转发许可：<RIP> 开放访问源IP（即用户IP，可指定IP段，比如：192.168.1.0/24），不指定IP段会导致负载均衡器无法对外访问网络
#                 iptables -t nat -A POSTROUTING -j MASQUERADE -s <RIP>    删除规则将-A改为-D
#              查看规则
#                 iptables -t nat -nvL
#          6、双网卡互转配置，将 <DIP>:<DPORT> 请求转到 <TIP>:<DPORT> 下（一个内网一个外网，没有双网卡跳过）
#                 iptables -t nat -A PREROUTING -d <DIP> -p tcp --dport <DPORT> -j DNAT --to-destination <TIP>       删除规则将-A改为-D
#          6、同一个物理机上可配置（关闭网卡上的icmp重定向），注意：<DEV> 是为对应网卡名 --------------- 暂未验证作用，目前使用可不配置此项 ---------------
#               	echo 0 > /proc/sys/net/ipv4/conf/all/send_redirects
#           	    echo 0 > /proc/sys/net/ipv4/conf/<DEV>/send_redirects
#          7、访问验证（内外网验证）
#               curl http://192.168.1.10:88
#          8、查看转发信息
#               ipvsadm -lc
#
#   2、TUN模式，与DR模式类似，各节点通过IP隧道（IP Encapsulation协议）将节点响应信息直接返回给终端（不需要再通过LVS调度器），单点负载均衡器吞吐量一般建议后台服务器个数在100台以内
#       该模式需要负载均衡器与各节点必需都支持IP隧道协议（不能端口号映射，参考NAT的5），各节点必需是能与客户端和负载均衡器通信不限制网络段。
#       该模式需要各节点隐藏不响应arp广播请求，只让虚拟主机（负载均衡器）响应arp广播请求，这样各节点才不能与虚拟主机进行响应竞争避免请求响应异常。
#       文档：http://www.austintek.com/LVS/LVS-HOWTO/HOWTO/LVS-HOWTO.LVS-Tun.html
#       示例流程：
#          【负载均衡器配置】
#               1、添加虚拟服务器
#                   ipvsadm -A -t 192.168.1.10:88 -s rr     添加虚拟服务器转发地址192.168.1.10:88，转发协议TCP，指定转发算法为轮询
#               2、添加转发后台真实服务器
#                   ipvsadm -a -t 192.168.1.10:88 -r 192.168.1.11:80 -i -w 1    添加真实服务器192.168.1.11:80，转发来源虚拟服务器为192.168.1.10:88，转发协议TCP，指定TUN模式，权重值为1
#                   ipvsadm -a -t 192.168.1.10:88 -r 192.168.1.12:80 -i -w 1    添加真实服务器192.168.1.12:80，转发来源虚拟服务器为192.168.1.10:88，转发协议TCP，指定TUN模式，权重值为1
#               3、查看规则
#                   ipvsadm -l    应该可看到上面配置的规则（IP地址或端口号可能被转为英文表示）
#               4、配置虚拟IP地址（注意网卡名为真实网卡，名称一般是e开头，:0表示网卡别名允许多个不同别名）
#                   ifconfig eth0:0 192.168.24.10 netmask 255.255.255.255 broadcast 192.168.24.10 up
#                   删除命令： ifconfig eth0:0 del 192.168.24.10
#               5、添加虚拟IP地址路由（注意网卡名）--------------- 暂未验证作用，目前使用可不配置此项（据说是不在同一个子网需要添加网络路由） ---------------
#                   route add -host 192.168.24.10 dev eth0:0
#                   删除命令 route del -host 192.168.24.10 dev eth0:0
#               5、防火墙配置（如果关闭防火墙跳过）
#                   iptables -I INPUT -p tcp -m state --state NEW -m tcp --dport 80 -j ACCEPT
#          【各节点直接服务器配置】（必需支持ipip隧道）
#               1、启用ipip模块（隧道网卡tunl0设备）
#                   modprobe ipip
#               2、配置虚拟IP地址（注意网卡名为tunl0）
#                   ifconfig tunl0 192.168.24.10 netmask 255.255.255.255 broadcast 192.168.24.10 up
#                   删除命令： ifconfig tunl0 del 192.168.24.10
#               3、添加虚拟IP地址路由（注意网卡名）--------------- 暂未验证作用，目前使用可不配置此项（据说是不在同一个子网需要添加网络路由） ---------------
#                   route add -host 192.168.24.10 dev tunl0
#                   删除命令 route del -host 192.168.24.10 dev tunl0
#               4、配置广播arp回复规则（禁止各节点回复arp广播请求，不配置请求无法正常工作），节点与负载均衡器不在同一网络无需跳过
#                   echo 1 > /proc/sys/net/ipv4/conf/tunl0/arp_ignore
#                   echo 2 > /proc/sys/net/ipv4/conf/tunl0/arp_announce
#                   echo 1 > /proc/sys/net/ipv4/conf/all/arp_ignore
#                   echo 2 > /proc/sys/net/ipv4/conf/all/arp_announce
#               5、关闭反向路由校验
#                   echo 0 > /proc/sys/net/ipv4/conf/tunl0/rp_filter
#                   echo 0 > /proc/sys/net/ipv4/conf/all/rp_filter
#               6、防火墙配置（如果关闭防火墙跳过）
#                   开方端口号（二选一命令）
#                     iptables -I INPUT -p tcp -m state --state NEW -m tcp --dport 80 -j ACCEPT
#                     iptables -I INPUT -i tunl0 -j ACCEPT -p tcp --dport 80
#                   允许ip隧道包（注意网卡名）
#                     iptables -I INPUT -i eth0 -j ACCEPT -p ipencap
#               7、重定向到其它节点的端口号（没有重定向修改端口号需要跳过），<VIP>是虚拟IP地址，<dport>目标端口号，<tport>重定向到端口号
#                   iptables -t nat -A PREROUTING -p tcp -d <VIP> --dport <dport> -j REDIRECT --to-port <tport>
#
#   3、DR模式，与TUN模式类似，是通过MAC地址交换，需要名节点与负载均衡器在同一内网中（不允许端口号映射，参考NAT的5），且各节点能与客户端通信，速度比TUN模式更快，单点负载均衡器吞吐量一般建议后台服务器个数在100台以内
#       该模式需要各节点隐藏不响应arp广播请求，只让虚拟主机（负载均衡器）响应arp广播请求，这样各节点才不能与虚拟主机进行响应竞争避免请求响应异常。
#       文档：http://www.austintek.com/LVS/LVS-HOWTO/HOWTO/LVS-HOWTO.LVS-DR.html
#       示例流程：
#          【负载均衡器配置】
#               1、选择一个虚拟IP地址（网段不一定要与实际网段一至），此地址不应该有实际的机器，用来配置到负载均衡器和各节点。
#                   比如：  192.168.1.10
#               1、添加虚拟服务器
#                   ipvsadm -A -t 192.168.1.10:88 -s rr     添加虚拟服务器转发地址192.168.1.10:88，转发协议TCP，指定转发算法为轮询
#               2、添加转发后台真实服务器
#                   ipvsadm -a -t 192.168.1.10:88 -r 192.168.1.11:80 -g -w 1    添加真实服务器192.168.1.11:80，转发来源虚拟服务器为192.168.1.10:88，转发协议TCP，指定DR模式，权重值为1
#                   ipvsadm -a -t 192.168.1.10:88 -r 192.168.1.12:80 -g -w 1    添加真实服务器192.168.1.12:80，转发来源虚拟服务器为192.168.1.10:88，转发协议TCP，指定DR模式，权重值为1
#               3、查看规则
#                   ipvsadm -l    应该可看到上面配置的规则（IP地址或端口号可能被转为英文表示）
#               4、配置虚拟IP地址（注意网卡名为真实网卡，名称一般是e开头，:0表示网卡别名允许多个不同别名）
#                   ifconfig eth0:0 192.168.24.10 netmask 255.255.255.255 broadcast 192.168.24.10 up
#                   删除命令： ifconfig eth0:0 del 192.168.24.10
#               5、添加虚拟IP地址路由（注意网卡名）--------------- 暂未验证作用，目前使用可不配置此项（据说是不在同一个子网需要添加网络路由） ---------------
#                   route add -host 192.168.24.10 dev eth0:0
#                   删除命令 route del -host 192.168.24.10 dev eth0:0
#               5、防火墙配置（如果关闭防火墙跳过）
#                   iptables -I INPUT -p tcp -m tcp --dport 80 -j ACCEPT
#          【各节点真实服务器配置】
#               1、配置虚拟IP地址（注意网卡名为lo， :0表示网卡别名允许多个不同别名）
#                   ifconfig lo:0 192.168.24.10 netmask 255.255.255.255
#                   删除命令： ifconfig lo:0 del 192.168.24.10
#               2、添加虚拟IP地址路由（注意网卡名） --------------- 暂未验证作用，目前使用可不配置此项（据说是不在同一个子网需要添加网络路由） ---------------
#                   route add -host 192.168.24.10 dev lo:0
#                   删除命令： route del -host 192.168.24.10 dev lo:0
#               3、配置广播arp回复规则（禁止各节点回复arp广播请求，不配置请求可能被某个节点回复arp广播请求后劫持跳过负载均衡器）
#                   echo 1 > /proc/sys/net/ipv4/conf/lo/arp_ignore
#                   echo 2 > /proc/sys/net/ipv4/conf/lo/arp_announce
#                   echo 1 > /proc/sys/net/ipv4/conf/all/arp_ignore
#                   echo 2 > /proc/sys/net/ipv4/conf/all/arp_announce
#               4、防火墙配置（如果关闭防火墙跳过）
#                   端口访问许可（注意端口号）
#                       iptables -I INPUT -p tcp -m state --state NEW -m tcp --dport 80 -j ACCEPT
#                   重定向端口号，将 <VIP>:<vport> 重定向到 <VIP>:<vport>（当对外和内部服务端口号不同时使用）
#                       iptables -t nat -A PREROUTING -p tcp -d <VIP> --dport <vport> -j REDIRECT --to-port <vport>
#               5、配置启动tcp服务
#                   nginx 或 apache 等其它服务，服务按正常配置即可（端口号需要保持一至）
#
#          【验证结果】
#               curl http://192.168.24.10
#
#
# 使用问题：
#   1、配置后规则后访问无响应，排查iptables规则
#   2、通过netstat是查不到虚拟服务的端口监听，转为ipvsadm不在用户态，是要内核态中网络协议处理层就识别并转发处理的
#   3、转发失败需要借助抓包工具进行分析，多数是配置与当前系统环境不符合需要更多配置才能正常工作
#   4、一台负载均衡器允许NAT与TUN或TUN与DR能共存同一网段，NAT与DR不能共存同一网段
#   5、各节配置没有共存限制
#
# ipvsadm 的使用流程主要有：
#   1、向虚拟服务器表中添加虚拟服务器地址（内网地址）
#   2、向虚拟服务器表中添加真实服务器地址
#   3、访问虚拟服务器验证是否调度给真实服务器
#   4、多个负载均衡器配置同步节点信息

# 【ipvsadm 命令详解】（各版本不尽相同，此处仅ipvsadm v1.31版本为例）
# 添加或修改虚拟服务器
#  ipvsadm -A|E virtual-service [-s scheduler] [-p [timeout]] [-M netmask] [--pe persistence_engine] [-b sched-flags]
# 删除虚拟服务器
#  ipvsadm -D virtual-service
# 清除虚拟服务器表所有记录
#  ipvsadm -C
# 从标准输入中还原所有虚拟服务器配置规则
#  ipvsadm -R
# 从标准输出中打印所有虚拟服务器配置规则
#  ipvsadm -S [-n]
# 向虚拟服务器中添加或修改真实服务器
#  ipvsadm -a|e virtual-service -r server-address [options]
# 向虚拟服务器中删除真实服务器
#  ipvsadm -d virtual-service -r server-address
# 打印已经存在的虚拟服务器表记录
#  ipvsadm -L|l [virtual-service] [options]
# 虚拟服务器计数器清零（清空当前的连接数量等）？？？
#  ipvsadm -Z [virtual-service]
# 设置连接超时值
#  ipvsadm --set tcp tcpfin udp
# 开启同步连接监听器，主从同步虚拟服务器表数据功能（在内核中完成）
#  ipvsadm --start-daemon {master|backup} [daemon-options]
# 关闭同步连接监听器
#  ipvsadm --stop-daemon {master|backup}
# 打印帮助信息
#  ipvsadm -h

# 【选择功能选项】，用来指定操作哪个功能
#  --add-service     -A        添加一个虚拟服务器表规则记录
#  --edit-service    -E        编辑一个虚拟服务器表规则记录
#  --delete-service  -D        删除一个虚拟服务器表规则记录
#  --clear           -C        清除虚拟服务器表规则记录
#  --restore         -R        从标准输入还原虚拟服务器表规则记录
#  --save            -S        从标准输出打印虚拟服务器表规则记录
#  --add-server      -a        添加一个负载均衡调度真实服务器
#  --edit-server     -e        编辑一个负载均衡调度真实服务器
#  --delete-server   -d        删除一个负载均衡调度真实服务器
#  --list            -L|-l     打印所有虚拟服务器表记录
#  --zero            -Z        虚拟服务表计数器清零（清空当前的连接数量等）
#  --set tcp tcpfin udp        设置连接方式的超时时长
#  --start-daemon              开启主备同步连接监听器（内核中运行）
#  --stop-daemon               关闭主备同步连接监听器
#  --help            -h        打印帮助信息

# 【操作虚拟服务器专用选项】
#  --tcp-service|-t  service-address   虚拟服务器TCP协议入口地址和端口号
#  --udp-service|-u  service-address   虚拟服务器UDP协议入口地址和端口号
#  --sctp-service    service-address   虚拟服务器SCTP协议入口地址和端口号，SCTP是一种面向连接的协议（类似于 TCP）
#  --fwmark-service|-f fwmark          fwmark is an integer greater than zero

# 【常规选项】
#  --ipv6         -6                   启用IPv6地址转发
#  --scheduler    -s scheduler         指定负载均衡调度算法，默认 wlc ，需要与 -a|-e|-d 同时使用
#                                      rr 轮询，wrr 加权轮询，lc 最小连接量优先，wlc 加权最小连接量优先
#                                      lblc 局部的最小连接量优先，lblcr 带复制的局部性最少链接，dh 目标地址散列
#                                      sh 源地址散列，sed 最短时间，nq 永不排队 ？？？？？？？？？？？？？？？
#                                      one of rr|wrr|lc|wlc|lblc|lblcr|dh|sh|sed|nq|fo|ovf|mh,
#  --pe            engine              alternate persistence engine may be sip, not set by default.
#  --persistent   -p [timeout]         保持连接关系时长。即同一个客户的多次请求，全部转发到同一台真实的服务器处理。timeout 的默认值为300 秒。
#  --netmask      -M netmask           persistent granularity mask
#  --real-server  -r server-address    指定真实的服务器地址和端口号（不指定端口号与虚拟服务器端口号一样），需要与 -a|-e|-d 同时使用
#                                      只有NAT模式可指定端口号用来端口号映射，另外两种模式端口号必需与虚拟端口号相同
#  --gatewaying   -g                   指定为DR模式（直接路由模式）处理，默认为此模式，需要与 -A|-E|-D 同时使用，默认此模式
#  --ipip         -i                   指定为TUN模式（IP隧道模式）处理，需要与 -A|-E|-D 同时使用
#  --masquerading -m                   指定为NAT模式处理，需要与 -A|-E|-D 同时使用
#  --tun-type      type                选择一个隧道协议： ipip|gue|gre ，默认是ipip
#                                       ipip 是封装IP协议的隧道协议（端对端通信），使用前需要启动模块： modprobe ipip
#                                       gue 一种UDP隧道协议，内部支持ipip和gre封装，即可以使用ipip或gre模式来运行gue隧道模式
#                                       gre 是ipip升级版附加报头信息（多播通信），使用前需要启动模块：modprobe ip_gre
#  --tun-port      port                tunnel destination port
#  --tun-nocsum                        tunnel encapsulation without checksum
#  --tun-csum                          tunnel encapsulation with checksum
#  --tun-remcsum                       tunnel encapsulation with remote checksum
#  --weight       -w weight            指定真实服务器调度权重值，需要与 -a|-e|-d 且指定的权重调度算法时使用
#  --u-threshold  -x uthreshold        设置转发请求的最大上连接阈值，范围0~65535，当连接数超过上限，lvs则不会转发请求
#  --l-threshold  -y lthreshold        设置转发请求的下连接阈值，范围0~65535，当连接数降低至指定值，lvs则继续提供服务，默认0
#  --connection   -c                   显示IPVS目前的连接信息，需要与-l同时使用
#  --timeout                           输出tcp、tcpfin、udp的超时信息，需要与-l同时使用
#  --daemon                            显示同步信息，需要与-l同时使用
#  --stats                             显示统计信息，需要与-l同时使用
#  --rate                              显示速率信息，需要与-l同时使用
#  --exact                             显示数据包和字节数的准确值，扩大字符长度，需要与-l同时使用
#  --thresholds                        阈值信息输出（独立使用），需要与-l同时使用
#  --persistent-conn                   连接信息输出（独立使用），需要与-l同时使用
#  --tun-info                          隧道信息输出（独立使用），需要与-l同时使用
#  --nosort                            禁止输出信息时排序均衡器和节点IP地址，需要与-l同时使用
#  --sort                              无操作（可以理解为默认排序均衡器和节点IP地址），以实现向后兼容性，需要与-l同时使用
#  --ops          -o                   one-packet scheduling
#  --numeric      -n                   将输出的IP和port以数字化显示（默认显示别名），需要与-l同时使用
#  --sched-flags  -b flags             设置调度算法的范围表示，用于SH算法，两个标识：sh-fallback，如果real server不可用，将其转发到其他real server；sh-port，将源地址的端口号也添加到散列键=值中

# 【同步连接专用选项】
#  --syncid sid                        设置连接同步守护进程的SID号，用于标识连接同步组，范围0~255，默认：255
#  --sync-maxlen length                Max sync message length (default=1472)
#  --mcast-interface interface         指定同步连接网卡名（ifconfig命令查看）
#  --mcast-group address               IPv4/IPv6 group (default=224.0.0.81)
#  --mcast-port port                   UDP port (default=8848)
#  --mcast-ttl ttl                     Multicast TTL (default=1)

####################################################################################
##################################### 安装处理 #####################################
####################################################################################
# 定义安装类型
DEFINE_INSTALL_TYPE='make'
# 定义默认编译进程个数，ipvsadm多个编译进程容易失败
DEFINE_MAKE_JOBS=1
# 定义安装参数
DEFINE_RUN_PARAMS=""
# 加载基本处理
source "$(cd "$(dirname "${BASH_SOURCE[0]}")"; pwd)"/../../includes/install.sh || exit
# 初始化安装
init_install 1.26 "https://mirrors.edge.kernel.org/pub/linux/utils/kernel/ipvsadm/" 'ipvsadm-\d+\.\d+\.tar.gz' '\d+\.\d+'
#  限制空间大小（G）：编译目录、安装目录、内存
install_storage_require 1 1 1
# ************** 编译安装 ******************
# 下载ipvsadm包
# ipvsadm有两部分下载，早期需要区分内核下载，并且太久远了，暂时不提供下载处理
# 早期是1.25及以前的在http://www.linux-vs.org/software/ipvs.html
# 后期的在https://mirrors.edge.kernel.org/pub/linux/utils/kernel/ipvsadm/
download_software https://mirrors.edge.kernel.org/pub/linux/utils/kernel/ipvsadm/ipvsadm-$IPVSADM_VERSION.tar.gz
# 暂存编译目录
IPVSADM_CONFIGURE_PATH=`pwd`
# 安装依赖
info_msg "安装相关已知依赖"
# 编译时报：undefined reference to `xxx' 时说明依赖库文件找不到，一般是依赖包没有安装或版本不匹配
# 安装libnl-dev
if if_version $IPVSADM_VERSION '<' 1.27;then
    # 安装libnl-dev和popt-static
    package_manager_run install -LIBNL_DEVEL_PACKAGE_NAMES -POPT_STATIC_PACKAGE_NAMES
else
    package_manager_run install -LIBNL3_DEVEL_PACKAGE_NAMES
fi
# 安装popt-dev
package_manager_run install -POPT_DEVEL_PACKAGE_NAMES

cd $IPVSADM_CONFIGURE_PATH
# 修改安装目录
export BUILD_ROOT=$INSTALL_PATH$IPVSADM_VERSION
# 编译
make_install $INSTALL_PATH$IPVSADM_VERSION $ARGV_options

cd $INSTALL_PATH$IPVSADM_VERSION

# 添加到默认路径中
if [ -e etc/rc.d/init.d/ipvsadm ];then
  ln -svf etc/rc.d/init.d/ipvsadm /etc/rc.d/init.d/ipvsadm
fi
# 创建配置保存目录
if [ ! -e /etc/ipvsadm.rules ];then
  touch /etc/ipvsadm.rules
fi
# 添加路径，必需添加到/sbin目录下
ln -svf $INSTALL_PATH$IPVSADM_VERSION/sbin/ipvsadm /sbin/ipvsadm
ln -svf $INSTALL_PATH$IPVSADM_VERSION/sbin/ipvsadm-save /sbin/ipvsadm-save
ln -svf $INSTALL_PATH$IPVSADM_VERSION/sbin/ipvsadm-restore /sbin/ipvsadm-restore

info_msg "请使用脚本：bash $INSTALL_PATH$IPVSADM_VERSION/ipvsadm.sh 操作ipvsadm"

info_msg "安装成功：$INSTALL_NAME-$IPVSADM_VERSION"
