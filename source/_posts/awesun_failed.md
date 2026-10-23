---
title: 向日葵 linux 错误
date: 2026-10-14 14:25:00
tags: linux
---

# 向日葵「正在加载客户端信息」报错：重启没用，因为压根不是它的事

## 先说结论

这不是网络问题，不是代理问题，也不是服务端抽风。

是那个 RPM 包**没跑安装脚本**，后台服务以普通用户身份启动时在 `/etc` 下建配置文件被拒绝，然后**空指针崩了**。你重启一百次客户端也没用——因为你重启的从来就不是那个坏掉的进程。

下面是完整过程，包括我自己走的弯路。

## 事情是这样的

有人在 Linux 上装了向日葵（AweSun），扫码登录时弹一个错：

> 获取二维码出错，正在加载客户端信息，请稍后重试或重启客户端

按提示重启了客户端，没用。又重启了一遍，还是没用。

这个提示其实很有迷惑性。"正在加载客户端信息，请稍后重试或重启客户端"——它在暗示你：我这边卡住了，你耐心点，或者把我重启一下。于是正常人就会去重启，重启没用就会去查网络、关代理、换 DNS、清缓存。

我一开始也是这么答的。

对，你没看错。**我前两轮给的建议是：检查 DNS、关掉 Clash、校准系统时间、清 `%AppData%` 缓存、卸载重装。**

理由很充分：我搜到的公开资料全都这么说，向日葵官方 FAQ 也这么说，历史上它也确实崩过好几次服务器。这套话术放之四海而皆准，任何软件的任何登录失败都能套一遍。

问题是，**这套话术没有一个字是基于这台机器的**。我猜的。

直到对方把客户端日志贴出来了。

## 日志里有两个东西很扎眼

```
[Connect] rpc connect ret -1 failed errcode 111
[Connect] rpc connect ret -1 failed errcode 2
...
[inapp_web_login] [_handleGetClientId] clientid length: 0
```

第二行那个 `clientid length: 0` 是关键。

登录页是一个内嵌的 web 页面（`cc.sunlogin.oray.com/auth.html`），它在页面里通过 JS 桥向客户端原生层要一个 `clientId`，拿到之后才能去服务端换二维码。现在返回的长度是 **0**——不是拿错了，是根本没拿到。

这说明什么？说明**问题在本机，不在网络**。网络再烂，返回的也是"超时"或者"连接失败"，不会返回一个空字符串。空字符串意味着本地某个组件没给它东西。

再看 `errcode 111` 和 `errcode 2`：这是 Linux 的 errno，111 是 `ECONNREFUSED`（连接被拒绝，对面没人监听），2 是 `ENOENT`（文件不存在）。

也就是说：**UI 在连一个本机服务，那个服务没在运行。**

`ps -ef` 一看，果然：

```
scc  22712  /usr/local/awesun/awesun      ← 只有这个
```

`awesun_daemon` 没起来。`/run/user/1000/awesun` 目录是空的。

## 到这里，"重启无效"就解释通了

向日葵在 Linux 上是两个进程的架构：

- `awesun`（Flutter UI，你在屏幕上看到的那个窗口）
- `awesun_daemon` → 拉起 `awesun --mod=service`（后台服务，负责和服务器通信、提供 clientId）

二维码的前置请求，是 **web 页面 → UI → 本地 RPC → 后台服务** 这样一条链路。链路的最末端断了。

你点"重启客户端"，重启的只有 UI。后台服务要么压根没启动，要么启动即崩——这两件事，重启 UI 一个都改变不了。

## 那为什么后台服务没起来？

先手动拉一下：

```bash
/usr/local/awesun/bin/awesun_daemon -m server -name awesun
```

它确实拉起了一个子进程，然后两秒后：

```
Segmentation fault (core dumped)
```

段错误。于是看 core dump：

```
Signal: 11 (SEGV)
Command Line: /usr/local/awesun/bin/awesun --mod=service
```

用 gdb 打开（没有符号表，但够看了）：

```
0x628ea0:  mov 0x0(%r13),%rax
r13 = 0x0
附近字符串: "basic_token"
```

`r13` 是 0，然后程序试图读 `*r13`——**经典的空指针解引用**。旁边躺着的字符串是 `basic_token`。

崩是崩了，但**崩在哪不等于为什么崩**。空指针只是结果，得找到它为什么是空的。

## 真正一锤定音的是一行 strace

```bash
strace -f -tt -o /tmp/svc.strace /usr/local/awesun/bin/awesun --mod=service
```

strace 干的事很简单：把程序每一次系统调用（打开文件、建连接、读写）都打印出来。它不看代码，它看**程序到底对操作系统做了什么**。

崩溃前的记录：

```
openat("/etc/orayconfig.conf", O_WRONLY|O_CREAT|O_APPEND, 0666) = -1 EACCES
openat("/etc/sys_config.conf",  O_WRONLY|O_CREAT|O_APPEND, 0666) = -1 EACCES
```

**服务想在 `/etc` 下创建配置文件，因为是普通用户，权限被拒。**

配置文件没建成 → 读 token 时拿到 null → 空指针 → 段错误 → 服务没起来 → UI 连不上 → `clientId` 长度 0 → 弹那句"正在加载客户端信息"。

整条因果链，从一个 `EACCES` 串到了屏幕上那句话。

## 最后一步：为什么它会去 /etc 建文件？

按理说，一个正常打包的软件不该在运行时去 `/etc` 写文件。除非——**安装的时候就该把它建好**。

解开官方的 `.deb` 包看 `postinst`（Debian 系的安装脚本）：

```bash
if [ ! -f '/etc/orayconfig.conf' ]; then
  touch /etc/orayconfig.conf
fi
chmod 644 /etc/orayconfig.conf

cp runawesun.service /etc/systemd/system/
systemctl enable runawesun.service
```

一模一样。**官方安装脚本会预建这个文件，并把服务注册成 systemd 单元。**

而装的这个 RPM（明显是别人从 deb 转出来的）：

```
$ rpm -q --scripts awesun
（空）
```

没有 `%post`。三件事一件没做：配置文件没建、systemd 单元没注册、服务没启动。

**装完"看起来成功了"，实际是个半成品。**

## 修复

```bash
sudo touch /etc/orayconfig.conf && sudo chmod 644 /etc/orayconfig.conf
sudo cp /usr/local/awesun/scripts/runawesun.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now runawesun.service
```

然后重启 UI，好了。

配置文件建得出来了，服务以 root 身份由 systemd 托管（它本来的设计就是要 root——要抓屏、要注入按键、要开机自启），clientId 拿得到了，二维码出来了。

## 复盘：这事的三个教训

**一、报错文案是给人看的，不是给诊断用的。**

"正在加载客户端信息，请稍后重试或重启客户端"这句话里，没有一个字描述了真实故障。它把一个**权限+打包缺陷**包装成了"你再等等就好"。跟着提示走（重启、稍后重试）必然死循环。

**二、我第一轮的通用建议，本质上是在猜。**

关代理、换 DNS、清缓存——这些建议适用于一切登录失败，所以也**不针对任何具体问题**。它的坏处是：听起来很专业，实际没排除任何可能性，还可能把用户带偏半小时。

区别在哪？在于**有没有这台机器的日志和 shell**。有了证据，诊断从"列举可能性"变成"逐个证伪"。

**三、strace 是性价比最高的一招。**

这个案子里，gdb 告诉我"在哪崩的"，但真正破案的是 strace 那两行 `EACCES`。**当一个程序行为诡异，别猜它在想什么，直接看它对系统发了什么请求。** 大多数"玄学问题"在 syscall 层面都是大白话。

---

顺便说一句，如果你也在这台机器上装了这个 RPM，记住：**它缺 `%post`，下次升级版本，上面四条命令还得再跑一遍。** 这种坑不会自己好，只会等着你。
