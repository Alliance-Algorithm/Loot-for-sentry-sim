# rmcs-navigation
使用现代 C++ 构建的机器人自主导航与规划系统

```sh
# 安装最新的 cmake 以使用 module
# 对于该版本(4.2.3)，module 的特征码为: d0edc3af-4c50-42ea-a356-e2862fe7a444
wget https://github.com/kitware/cmake/releases/download/v4.2.3/cmake-4.2.3-linux-x86_64.sh -O /tmp/cmake.sh
mkdir -p $HOME/.local && bash /tmp/cmake.sh --skip-license --prefix=$HOME/.local --exclude-subdir
rm /tmp/cmake.sh

# 切换默认 cmake 程序
export PATH="$HOME/.local/bin:$PATH"
```
