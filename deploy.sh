#!/bin/bash 
# 部署脚本,所有关于博客的操作一定要切换到dev-2分支后进行

echo "切换到 dev-2 分支，并提交部署代码"
git switch dev-2
git add .
git commit -m "deploy"
git push origin dev-2

echo "使用 hexo 部署博客"
hexo clean
hexo g
hexo d