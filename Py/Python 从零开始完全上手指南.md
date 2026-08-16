# 🐍 Python 从零开始完全上手指南  
**适用系统：Windows 10/11 | 编辑器：Visual Studio Code（VS Code）| 语言：Python 3**  

这份手册专为零基础新手设计，从安装环境到写出第一个项目，每一步都有详细说明。只要你跟着操作，就能顺利进入 Python 的世界。

---

## 目录
1. [安装 Python 解释器](#1-安装-python-解释器)
2. [安装 VS Code 编辑器](#2-安装-vs-code-编辑器)
3. [配置 VS Code 的 Python 开发环境](#3-配置-vs-code-的-python-开发环境)
4. [创建并运行第一个 Python 程序](#4-创建并运行第一个-python-程序)
5. [Python 核心语法速览](#5-python-核心语法速览)
   - 5.1 变量与数据类型
   - 5.2 运算符
   - 5.3 字符串
   - 5.4 列表、元组、字典、集合
   - 5.5 条件判断
   - 5.6 循环
   - 5.7 函数
   - 5.8 模块与导入
   - 5.9 文件读写
   - 5.10 异常处理
6. [动手做三个小项目](#6-动手做三个小项目)
   - 6.1 简单计算器
   - 6.2 猜数字游戏
   - 6.3 命令行待办事项
7. [下一步学什么？](#7-下一步学什么)
8. [跨语言调用扩展](#8-跨语言调用扩展)

---

## 1. 安装 Python 解释器
Python 解释器是运行 Python 代码的核心，就像游戏引擎一样。

1. 打开浏览器，访问 [https://www.python.org/downloads/](https://www.python.org/downloads/)
2. 点击醒目的 **Download Python 3.x.x** 按钮（版本号会随时间更新，例如 3.12.0）。
3. 下载完成后，双击运行安装程序。
4. ⚠️ **关键步骤**：在安装界面底部，勾选 **“Add Python to PATH”**（把 Python 加入系统环境变量），然后点击 **“Install Now”**（立即安装）。
5. 等待安装完成，点击 **Close**。

**验证安装是否成功**：
- 按下键盘上的 `Win + R`，输入 `cmd` 并回车，打开命令提示符。
- 输入以下命令并回车：
  ```bash
  python --version
  ```
  如果显示出 `Python 3.x.x` 字样，说明安装成功。
- 再输入 `pip --version`，如果显示版本号，说明 Python 的包管理工具 pip 也已就绪。

> 如果提示“不是内部或外部命令”，请重启电脑后再试，或者重新安装并确保勾选了 “Add Python to PATH”。

---

## 2. 安装 VS Code 编辑器
VS Code（全称 Visual Studio Code）是微软开发的免费、轻量且功能强大的代码编辑器。

1. 访问 [https://code.visualstudio.com/](https://code.visualstudio.com/)
2. 点击 **Download for Windows** 下载安装程序。
3. 运行安装程序，一路点击 **“下一步”**，建议在**“选择附加任务”**页面时勾选：
   - **“将 ‘通过 Code 打开’ 操作添加到文件资源管理器目录上下文菜单”**
   - **“将 ‘通过 Code 打开’ 操作添加到文件资源管理器文件上下文菜单”**  
   这样以后你可以右键文件夹直接通过 VS Code 打开。
4. 完成安装，启动 VS Code。

---

## 3. 配置 VS Code 的 Python 开发环境
要让 VS Code 识别 Python 并拥有智能提示、调试等功能，需要安装 Python 扩展。

1. 打开 VS Code，左侧竖栏点击 **“扩展”** 图标（或按 `Ctrl+Shift+X`）。
2. 在搜索框中输入 **Python**。
3. 找到由 Microsoft 发布的 **Python** 扩展（一般下载量最高），点击 **“安装”**。
4. 安装完成后，Python 图标会出现在活动栏中。
5. 现在 VS Code 就可以自动识别你电脑上安装的 Python 解释器了。按 `Ctrl+Shift+P`，输入 “Python: Select Interpreter”，选择显示出来的 Python 版本（例如 `Python 3.12.0`）。

> 💡 另外，推荐同时安装 **Pylance** 扩展（通常会自动安装），它能提供更优秀的代码补全和类型检查。

---

## 4. 创建并运行第一个 Python 程序
让我们用 VS Code 创建一个项目并运行 Hello World。

1. 在电脑上找个位置，新建一个文件夹，命名为 `python_beginner`。
2. 在 VS Code 中，点击 **“文件”** → **“打开文件夹”**，选择刚才创建的文件夹。也可以在资源管理器中右键该文件夹，选择 **“通过 Code 打开”**。
3. 在左侧资源管理器区域，点击 **“新建文件”** 图标，输入文件名 `hello.py`（.py 是 Python 文件的扩展名）。
4. 在编辑区输入：
   ```python
   print("Hello, Python! 你好，世界！")
   ```
5. 运行程序有三种常用方法：
   - **右键编辑区** → 选择 **“运行 Python 文件”**（Run Python File）。
   - 点击右上角的 ▶️ 三角形运行按钮。
   - 打开终端（`Ctrl+ `` `），直接输入 `python hello.py` 并回车。
6. 下面的终端窗口会显示 `Hello, Python! 你好，世界！`，这就是你的第一个 Python 程序。

---

## 5. Python 核心语法速览
下面我们通过实际代码来学习 Python 最重要的基础语法。你可以在 VS Code 中新建一个 `learn_basics.py` 文件，把每段代码贴进去运行看看效果。

### 5.1 变量与数据类型
```python
# 变量不需要声明类型，直接赋值即可
name = "小明"          # 字符串（文本）
age = 25              # 整数
height = 1.75         # 浮点数（小数）
is_student = True     # 布尔值（True/False）

# 查看变量类型
print(type(name))     # <class 'str'>
print(type(age))      # <class 'int'>
```
**命名规则**：只能包含字母、数字、下划线，不能以数字开头，区分大小写。

### 5.2 运算符
```python
# 数学运算
print(10 + 3)   # 加  13
print(10 - 3)   # 减  7
print(10 * 3)   # 乘  30
print(10 / 3)   # 除  3.333...
print(10 // 3)  # 整除 3
print(10 % 3)   # 取余 1
print(10 ** 3)  # 次方 1000

# 比较运算 (返回布尔值)
print(10 > 5)   # True
print(10 == 10) # True  （注意是两个等号）
print(10 != 5)  # True
```

### 5.3 字符串
```python
# 字符串可以用单引号或双引号
s1 = 'hello'
s2 = "world"

# 拼接
greeting = s1 + " " + s2   # "hello world"

# 重复
print("哈" * 3)   # 哈哈哈

# 格式化（f-string，最推荐）
name = "小芳"
age = 20
print(f"我叫{name}，今年{age}岁。")  # 我叫小芳，今年20岁。

# 常用方法
message = "  Hello, Python!  "
print(message.strip())        # 去掉两端空格
print(message.lower())        # 全部小写
print(message.replace("Python", "World")) # 替换
```

### 5.4 列表、元组、字典、集合
```python
# ----- 列表（可变有序集合） -----
fruits = ["苹果", "香蕉", "橘子"]
fruits.append("葡萄")        # 添加
fruits.remove("香蕉")        # 删除
print(fruits[0])             # 索引访问：苹果
print(fruits[-1])            # 最后一个：葡萄
print(len(fruits))           # 长度 3

# ----- 元组（不可变有序集合） -----
coordinates = (10, 20)
print(coordinates[0])  # 10，不能修改元素

# ----- 字典（键值对） -----
person = {
    "name": "小红",
    "age": 22,
    "city": "成都"
}
print(person["name"])        # 小红
person["age"] = 23           # 修改值
person["job"] = "设计师"     # 添加新键值对

# ----- 集合（不重复无序） -----
numbers = {1, 2, 3, 3, 2}
print(numbers)   # {1, 2, 3}  自动去重
```

### 5.5 条件判断
```python
temperature = 28

if temperature > 30:
    print("太热了！")
elif temperature > 20:
    print("温暖舒适")
else:
    print("有点冷")
```
**注意**：Python 使用缩进（通常4个空格）表示代码块，冒号不能忘。

### 5.6 循环
```python
# for 循环遍历列表
colors = ["红", "绿", "蓝"]
for color in colors:
    print(color)

# range() 生成数字序列
for i in range(5):     # 0,1,2,3,4
    print(i)

# while 循环
count = 0
while count < 3:
    print(f"计数：{count}")
    count += 1   # 相当于 count = count + 1
```

### 5.7 函数
```python
# 定义函数
def greet(name):
    """向用户问好的函数"""
    return f"你好，{name}！"

# 调用函数
message = greet("张三")
print(message)   # 你好，张三！

# 带默认参数的函数
def power(base, exp=2):
    return base ** exp

print(power(3))    # 9  （使用默认的2次方）
print(power(3, 3)) # 27
```

### 5.8 模块与导入
```python
# 导入内置模块 math
import math
print(math.sqrt(16))   # 4.0

# 从模块导入特定函数
from random import randint
print(randint(1, 100))  # 随机1-100的整数

# 导入并使用别名
import datetime as dt
print(dt.datetime.now())  # 当前时间
```

### 5.9 文件读写
```python
# 写入文件
with open("日记.txt", "w", encoding="utf-8") as f:
    f.write("今天是学习Python的第一天。\n")
    f.write("感觉很有意思！")

# 追加内容
with open("日记.txt", "a", encoding="utf-8") as f:
    f.write("我一定会坚持下去的。\n")

# 读取整个文件
with open("日记.txt", "r", encoding="utf-8") as f:
    content = f.read()
    print(content)
```
`with` 语句会自动关闭文件，安全方便。

### 5.10 异常处理
```python
try:
    num = int(input("请输入一个整数："))
    result = 10 / num
    print(f"10除以{num}等于{result}")
except ValueError:
    print("输入的不是有效整数！")
except ZeroDivisionError:
    print("除数不能为零！")
else:
    print("计算成功。")  # 无异常时执行
finally:
    print("程序结束。")  # 无论如何都会执行
```

---

## 6. 动手做三个小项目
通过实践项目巩固刚才学到的知识。每个项目都在 VS Code 新建一个 `.py` 文件独立运行。

### 6.1 简单计算器
```python
print("==== 简单计算器 ====")
num1 = float(input("输入第一个数字："))
operator = input("输入运算符 (+, -, *, /)：")
num2 = float(input("输入第二个数字："))

if operator == "+":
    result = num1 + num2
elif operator == "-":
    result = num1 - num2
elif operator == "*":
    result = num1 * num2
elif operator == "/":
    if num2 != 0:
        result = num1 / num2
    else:
        result = "错误：除数不能为0"
else:
    result = "未知运算符"

print(f"计算结果：{result}")
```

### 6.2 猜数字游戏
```python
from random import randint

secret = randint(1, 100)
guess = None
attempts = 0

print("我心里想了一个 1~100 的数字，猜猜看！")

while guess != secret:
    try:
        guess = int(input("请输入你的猜测："))
    except ValueError:
        print("请输入一个整数！")
        continue

    attempts += 1
    if guess < secret:
        print("太小了，再试试！")
    elif guess > secret:
        print("太大了，再试试！")
    else:
        print(f"恭喜你猜中了！数字就是 {secret}。")
        print(f"你一共猜了 {attempts} 次。")
```

### 6.3 命令行待办事项
```python
tasks = []  # 存储待办事项的列表

def show_menu():
    print("\n===== 待办事项 =====")
    print("1. 查看所有任务")
    print("2. 添加任务")
    print("3. 完成任务 (删除)")
    print("4. 退出")

while True:
    show_menu()
    choice = input("请输入选项 (1-4)：")

    if choice == "1":
        if not tasks:
            print("当前没有任务。")
        else:
            for i, task in enumerate(tasks, 1):
                print(f"{i}. {task}")
    elif choice == "2":
        task = input("输入新任务：")
        tasks.append(task)
        print(f"已添加：{task}")
    elif choice == "3":
        if not tasks:
            print("没有任务可完成。")
            continue
        for i, task in enumerate(tasks, 1):
            print(f"{i}. {task}")
        try:
            idx = int(input("输入要完成的任务编号：")) - 1
            removed = tasks.pop(idx)
            print(f"已完成任务：{removed}")
        except (ValueError, IndexError):
            print("无效编号。")
    elif choice == "4":
        print("再见！")
        break
    else:
        print("无效选项，请重新输入。")
```

---

## 7. 下一步学什么？
掌握上面的内容后，你已经可以写出能解决简单问题的程序了。下一步建议按顺序学习：

1. **虚拟环境与 pip 深入**  
   学习 `python -m venv myenv` 创建虚拟环境，隔离项目依赖；使用 `pip install requests` 安装第三方库。

2. **常用第三方库**  
   - `requests`：发送网络请求，抓取网页数据。
   - `beautifulsoup4`：解析 HTML，做爬虫。
   - `pandas`：数据处理与分析。
   - `matplotlib`：数据可视化画图。

3. **面向对象编程（OOP）**  
   理解类（class）、对象、继承、封装，这是编写大型程序的基础。

4. **练习平台**  
   - 力扣（LeetCode）、牛客网刷基础算法题。
   - 尝试做一个小工具，比如批量重命名文件、自动整理文件夹。

5. **图形界面（GUI）**  
   学习 `tkinter` 或 `PyQt` 给程序加上图形窗口，让工具更好看。

6. **进阶方向**  
   根据兴趣选择：Web 开发（Django/Flask）、数据科学（numpy/pandas/matplotlib）、自动化运维、人工智能（pytorch）等。

---

## 8. 跨语言调用扩展

掌握 Python 基础后，你可以进一步学习如何使用 Python 调用其他语言编写的服务，或将 Python 函数暴露给其他语言调用。**zAPI** 提供了一套完整的跨语言调用方案：

- **Python 调用 C++/Go/Rust/Java 等异构服务**：通过 [从零到一，掌握多语言互调](从零到一，掌握多语言互调.md) 实现零 IDL、零代码生成的跨语言 RPC。
- **将 Python 函数暴露为远程 API**：供 C++、Go、Rust、Java、C#、PHP、Node.js 等语言调用。
- **v2.0 新增**：支持动态注销 API（`App.unregister()`）和运行时配置（`set_option()`）。
- **HTTP 网关支持**：PHP 和 Node.js 可通过 [ZAPI Bridge 完整使用手册](../bridge/📖%20ZAPI%20Bridge%20完整使用手册.md) 调用 Python 服务。

```python
# Python 调用 C++ 服务示例
from api_hub import C4

client = C4("CppService", "ipc:cpp_service")
result = client.compute("hello world")
print("C++ 计算结果:", result)
```

---

## 🎉 恭喜你！
现在你已经成功搭建好了 Windows + VS Code + Python 的开发环境，并写出了自己的程序。学习编程最重要是多动手、多查文档、保持耐心。遇到报错不要慌，仔细阅读错误信息，上网搜索解决办法（推荐用英文错误信息搜索），你会快速成长的。

**开始用代码改变世界吧！**

## 📚 相关资源（其他语言指南）

- [API Hub Tool C++ 使用指南](../C++/API%20Hub%20Tool%20C++%20使用指南.md)
- [API Hub Tool C 语言使用指南](../C++/API%20Hub%20Tool%20C%20语言使用指南.md)
- [从零到一，掌握多语言互调](从零到一，掌握多语言互调.md)
- [API Hub for Go 从零到一掌握多语言互调](../Go/API%20Hub%20for%20Go%20从零到一掌握多语言互调.md)
- [zAPI Rust 使用指南](../rust/zAPI%20Rust%20使用指南.md)
- [API Hub Java 使用指南](../java/API%20Hub%20Java%20使用指南.md)
- [API Hub Tool for C# — 完整使用指南](../C%23/API%20Hub%20Tool%20for%20C%23%20—%20完整使用指南.md)
- [API Hub Tool for Pascal](../pascal/API%20Hub%20Tool%20for%20Pascal.md)
- [Node.js 跨语言调用方案选型：为什么我们选择 Python 网关而非 npm 原生包](../node/Node.js%20跨语言调用方案选型：为什么我们选择%20Python%20网关而非%20npm%20原生包.md)
- [老哥别卷了,你的 VB.NET 代码今天开始全栈通杀](../VB.NET/老哥别卷了,%20你的%20VB.NET%20代码今天开始全栈通杀.md)
- [浏览器调用 C++ 的三种方案对比：为什么我们选择了 zAPI 网关](web/浏览器调用%20C++%20的三种方案对比：为什么我们选择了%20zAPI%20网关.md)
- [js_api.py 使用指南](web/js_api.py%20使用指南.md)
- [📖 ZAPI Bridge 完整使用手册](../bridge/📖%20ZAPI%20Bridge%20完整使用手册.md)
