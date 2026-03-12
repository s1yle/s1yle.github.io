---
title: Linux避坑实录：搞定virt-manager网络报错+dnsmasq端口占用
date: 2026-03-12 22:11:21
tags: linux
---

# 前言

> 最近在Arch Linux上部署KVM+virt-manager做虚拟机管理，本以为一键安装就能顺畅使用，结果接连踩中libvirt网络相关的多个坑，从最开始的套接字文件缺失、default网络找不到，到后续的临时网络无法删除、virsh命令查不到网络但虚拟网桥实际存在，甚至创建虚拟机时直接报「无法获取接口MTU、无此设备」的错误，折腾了好久才彻底修复。

> 这篇博客就把完整的 修复方案 整理出来

## 一、本次遇到的全部故障现象

先把排查过程中遇到的核心报错汇总，方便大家对照自查，基本覆盖了virt-manager网络配置的所有常见坑：

- 初始基础报错：无法连接libvirt qemu:///system，提示找不到virtqemud-sock、virtnetworkd-sock、virtstoraged-sock套接字文件；执行virsh net-list --all为空，无任何网络配置，手动启动default网络提示不存在；

- 配置冲突报错：手动创建default网络提示UUID冲突，删除网络时报「无法删除临时网络」；创建虚拟机报Cannot get interface MTU相关错误；

- 状态异常：sudo virsh net-list --all查看到default网络状态为inactive，Autostart为no，Persistent为yes，配置存在但无法激活。

## 二、核心问题根源

> 基础网络缺失/权限/守护进程问题

看似是多个不相关的报错，其实核心根源只有一个：Arch Linux默认不会完整启动libvirt的核心守护进程，也不会自动生成default NAT网络配置，再加上残留临时网络、用户权限不足、网络未持久化这三个小问题，叠加导致了一系列基础故障。简单说：管虚拟机网络、存储、虚拟化的后台服务没开，默认的虚拟机上网配置没建，残留的临时配置还捣乱，普通用户没权限查看系统级网络，就出现了各种奇怪报错。

## 三、完整实操修复步骤

### 步骤1：启动并开机自启libvirt模块化核心守护进程

Arch采用模块化libvirt架构，摒弃传统单一libvirtd服务，优先启动模块化守护进程，避免冲突，解决套接字缺失问题：

#### 启动网络、虚拟化、存储三大模块化服务
`sudo systemctl start virtnetworkd virtqemud virtstoraged`
#### 设置开机自启
`sudo systemctl enable virtnetworkd virtqemud virtstoraged`

### 步骤2：生成一个默认配置文件（如果没有）

#### 示例配置文件(实测有效)
```
# 1. 创建default网络的配置目录
sudo mkdir -p /etc/libvirt/qemu/networks/

# 2. 写入default网络的标准配置（复制粘贴整段）
sudo tee /etc/libvirt/qemu/networks/default.xml > /dev/null << 'EOF'
<network>
  <name>default</name>
  <uuid>5fb06bd0-0bb0-4e4f-a123-d916f20b45fe</uuid>
  <forward mode='nat'>
    <nat>
      <port start='1024' end='65535'/>
    </nat>
  </forward>
  <bridge name='virbr0' stp='on' delay='0'/>
  <mac address='52:54:00:ee:69:d7'/>
  <ip address='192.168.122.1' netmask='255.255.255.0'>
    <dhcp>
      <range start='192.168.122.2' end='192.168.122.254'/>
    </dhcp>
  </ip>
</network>
EOF
```

### 步骤3：重新激活default网络并设置开机自启

激活已定义的 `default` 网络，无需重新定义配置文件:

#### 直接启动default网络
`sudo virsh net-start default`
#### 设置网络开机自启，重启后自动激活
`sudo virsh net-autostart default`
#### 验证网络状态
`sudo virsh net-list --all`

## 四、修复成功效果验证

- 执行 `sudo virsh net-list --all` ，能看到 `default` 网络状态为`active` 、`Autostart` 为 `yes` 、`Persistent` 为 `yes`；

- `ip link show` 能查到 `virbr0` 虚拟网桥正常运行；

- 打开 `virt-manager` ，创建新虚拟机时，网络选项会自动识别 `default NAT` 网络，无需手动配置，创建虚拟机不再报任何网络相关错误，虚拟机可正常联网；

- 再次执行 `sudo virsh net-start default` 无报错

