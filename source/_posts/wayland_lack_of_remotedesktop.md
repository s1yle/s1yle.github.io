---
title: lack of RemoteDesktop interface on Wayland?
date: 2026-05-17 00:33:12
tags: linux
---

# Wayland环境下 RemoteDesktop 接口缺失问题解析

近期在Fedora Sway上使用Deskflow时，遇到了这样的错误：`ERROR: failed to initialize remote desktop session: GDBus\.Error:org\.freedesktop\.DBus\.Error\.InvalidArgs: 无此接口“org\.freedesktop\.portal\.RemoteDesktop”`。结合实际使用场景和上游项目进展，就把这个问题的来龙去脉、原因及临时解决办法说清楚。

## 一、官方修复进展：仍未解决

截至2026年5月16日，无论是Sway依赖的wlroots官方门户后端`xdg\-desktop\-portal\-wlr`，还是Hyprland使用的`xdg\-desktop\-portal\-hyprland`（最新版1\.3\.12，2026年4月更新），都未官方实现`org\.freedesktop\.portal\.RemoteDesktop`接口。

这个问题并非个例，上游相关issue已开放多年：

- wlroots端：[emersion/xdg\-desktop\-portal\-wlr\#2](https://github.com/emersion/xdg-desktop-portal-wlr/issues/2)，自2019年提出至今未合并

- Hyprland端：[hyprwm/xdg\-desktop\-portal\-hyprland\#252](https://github.com/hyprwm/xdg-desktop-portal-hyprland/issues/252)，2024年开放，目前仍在推进中

Deskflow官方也已在Wayland支持讨论\#7499中，将该问题标记为“需上游修复”。

## 二、问题根源：接口缺失\+依赖限制

上述错误的核心原因很明确，主要有三点：

1. Deskflow在Wayland环境下以客户端模式运行时，会强制依赖`RemoteDesktop`门户接口，否则无法初始化远程会话；

2. Sway基于wlroots开发，其默认的门户后端`xdg\-desktop\-portal\-wlr`，恰好未实现这个关键接口；

3. 即便安装了`xdg\-desktop\-portal\-gtk`等其他门户后端，也无法为Sway提供支持——门户后端与桌面合成器（如Sway、GNOME）是绑定的，非对应后端无法适配。

## 三、关键概念快速理解

总结一下几个易混的概念:

|组件|说明|作用|
|---|---|---|
|D\-Bus|Linux系统中应用间通信的标准机制|应用调用其他进程接口时，若接口不存在、参数错误或无权限，会返回`org\.freedesktop\.DBus\.Error`类错误|
|RemoteDesktop接口|XDG Desktop Portal规范中的标准接口|Wayland环境下，应用实现远程控制（键盘、鼠标操作）的唯一合法途径，需用户授权，避免X11的安全隐患|
|wlroots/Sway|wlroots是Wayland合成器基础库，Sway是基于它开发的平铺式窗口管理器|Sway依赖`xdg\-desktop\-portal\-wlr`提供门户接口支持，二者深度绑定|

## 四、临时解决方案

目前官方尚未修复，如果有 wayland 下多设备键鼠共享的需求, 实测 sway+win10 环境下 可用 lan-mouse.  
目前使用下来, 暂时发现如下问题:

1. 使用 linux 作为服务端设备
2. 触摸板到了windows端滚动速度过低等问题.
