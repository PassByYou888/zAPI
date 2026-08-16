# Go 语言入门完全指南

> **面向读者**：完全零基础的新人。如果你从未接触过 Go，这份文档将从安装开始，带你写出第一个 Go 程序，并逐步掌握 Go 的核心语法与并发模型。文中包含大量可运行的例子，建议边看边敲。

**版本：** 1.0（通用 Go 语言入门指南）

---

## 目录

- [为什么选择 Go？](#为什么选择-go)
- [安装与配置](#安装与配置)
- [Hello, World!](#hello-world)
- [Go 模块与项目结构](#go-模块与项目结构)
- [变量与基本类型](#变量与基本类型)
- [常量](#常量)
- [函数](#函数)
- [控制流](#控制流)
- [数组与切片](#数组与切片)
- [映射（map）](#映射map)
- [结构体与方法](#结构体与方法)
- [接口](#接口)
- [错误处理](#错误处理)
- [defer、panic 与 recover](#deferpanic-与-recover)
- [并发编程：goroutine 与 channel](#并发编程goroutine-与-channel)
- [标准库常用包](#标准库常用包)
- [测试入门](#测试入门)
- [综合练习：猜数字游戏](#综合练习猜数字游戏)
- [跨语言调用扩展](#跨语言调用扩展)
- [下一步学什么？](#下一步学什么)


## 为什么选择 Go？

Go（又称 Golang）是 Google 开发的一门**静态类型、编译型语言**，主要特点：

- **简洁性**：语法干净，没有类继承、泛型（早期版本）、异常等复杂机制。
- **内置并发**：通过 `goroutine` 和 `channel` 轻松编写并发程序。
- **编译速度快**：适合大型项目，编译产物为静态二进制文件，部署简单。
- **自动垃圾回收**：既享受自动内存管理的便利，又能获得接近 C 的性能。
- **强大的标准库**：网络、HTTP、JSON、加密等开箱即用。

Go 广泛应用于云服务、微服务、CLI 工具、DevOps、区块链等领域。它的学习曲线平缓，非常适合作为第一门后端语言。


## 安装与配置

前往 [go.dev/dl](https://go.dev/dl/) 下载对应操作系统的安装包，或使用包管理器。

**macOS**：
```bash
brew install go
```

**Linux**（以 Ubuntu 为例）：
```bash
sudo apt update
sudo apt install golang-go
```

安装后验证：
```bash
go version
```

建议设置 Go 模块代理以加速依赖下载：
```bash
go env -w GOPROXY=https://goproxy.cn,direct   # 中国大陆用户推荐
```


## Hello, World!

创建 `hello.go` 文件：

```go
package main

import "fmt"

func main() {
    fmt.Println("Hello, World!")
}
```

运行：
```bash
go run hello.go
```

解释：
- `package main`：每个 Go 程序都由包组成，`main` 是程序入口包。
- `import "fmt"`：引入标准库 `fmt` 包，提供格式化输入输出。
- `func main()`：`main` 包中的 `main` 函数，是程序的起点。
- `fmt.Println`：打印一行并自动换行。


## Go 模块与项目结构

现代 Go 使用 **模块（module）** 管理依赖。创建一个独立项目：

```bash
mkdir hello-go
cd hello-go
go mod init example/hello-go
```

这会生成 `go.mod` 文件，记录模块路径和 Go 版本。你的程序写在 `*.go` 文件中即可。

**目录结构示例**：
```
hello-go/
├── go.mod
└── main.go
```

`go.mod` 内容大致为：
```
module example/hello-go

go 1.21
```

要添加外部依赖，直接 `import` 后运行 `go mod tidy` 即可自动下载。

常用命令：
- `go build`：编译成二进制文件。
- `go run`：编译并运行。
- `go mod tidy`：整理依赖。


## 变量与基本类型

### 变量声明

Go 中声明变量有多种方式：

```go
package main

import "fmt"

func main() {
    // 方式一：var 关键字，显式指定类型
    var name string = "Alice"

    // 方式二：类型推断
    var age = 30

    // 方式三：短变量声明（只能在函数内使用）
    city := "Beijing"

    // 多变量声明
    var x, y int = 1, 2
    a, b := "hello", 3.14

    fmt.Println(name, age, city, x, y, a, b)
}
```

注意：**未使用的变量会导致编译错误**，这鼓励保持代码整洁。

### 基本类型

| 类型    | 说明                   |
|---------|------------------------|
| `bool`  | `true` / `false`       |
| `string`| 字符串                 |
| `int`, `int8`, `int16`, `int32`, `int64` | 有符号整数 |
| `uint`, `uint8` … `uint64` | 无符号整数 |
| `float32`, `float64` | 浮点数 |
| `byte`  | `uint8` 的别名，常用于表示字节 |
| `rune`  | `int32` 的别名，代表一个 Unicode 码点 |

默认零值：数值类型 `0`，布尔 `false`，字符串 `""`。

```go
var i int       // 0
var f float64   // 0
var s string    // ""
var b bool      // false
```

类型转换必须显式进行：

```go
var i int = 42
var f float64 = float64(i)
var u uint = uint(f)
```


## 常量

使用 `const` 关键字定义常量，可以是字符、字符串、布尔或数值。

```go
const Pi = 3.14159
const World = "世界"

// 批量常量
const (
    StatusOK = 200
    StatusNotFound = 404
)

// iota 枚举
type Weekday int
const (
    Sunday Weekday = iota   // 0
    Monday                  // 1
    Tuesday                 // 2
    Wednesday               // 3
    Thursday                // 4
    Friday                  // 5
    Saturday                // 6
)
```

`iota` 在每一个 `const` 块中从 0 开始，每新增一行常量声明计数加 1，非常适合生成枚举。


## 函数

函数用 `func` 声明，参数类型放在参数名后，返回值类型放在最后。

```go
func add(a int, b int) int {
    return a + b
}

func main() {
    sum := add(3, 5)
    fmt.Println(sum)   // 8
}
```

当参数类型相同时，可以省略前面的类型：

```go
func add(a, b int) int {
    return a + b
}
```

### 多返回值

Go 函数可以返回多个值，常用于返回结果和错误。

```go
func divide(a, b float64) (float64, error) {
    if b == 0 {
        return 0, errors.New("division by zero")
    }
    return a / b, nil
}
```

### 命名返回值

返回值可以命名，就像形参一样，空 `return` 会返回这些变量的当前值。

```go
func split(sum int) (x, y int) {
    x = sum * 4 / 9
    y = sum - x
    return   // 返回 x, y
}
```


## 控制流

### if 语句

`if` 可以包含一个简短语句，用分号分隔。

```go
func pow(x, n, lim float64) float64 {
    if v := math.Pow(x, n); v < lim {
        return v
    }
    return lim
}
```

这里 `v` 的作用域仅限于 `if` 块内。

### for 循环

Go 只有 `for` 这一种循环，可以当作其他语言的 `for`、`while`、`foreach`。

```go
// 标准 for
for i := 0; i < 10; i++ {
    fmt.Println(i)
}

// 相当于 while
sum := 1
for sum < 1000 {
    sum += sum
}

// 无限循环
for {
    // ...
}
```

遍历数组/切片/映射等：

```go
nums := []int{2, 3, 4}
for index, value := range nums {
    fmt.Printf("索引 %d 值为 %d\n", index, value)
}

// 忽略索引
for _, value := range nums {
    fmt.Println(value)
}
```

### switch

Go 的 `switch` 不需要 `break`，默认只会执行匹配的 case。

```go
switch os := runtime.GOOS; os {
case "darwin":
    fmt.Println("macOS")
case "linux":
    fmt.Println("Linux")
default:
    fmt.Printf("%s\n", os)
}
```

无表达式的 `switch` 相当于 `switch true`，可以写更灵活的 case 条件。

```go
t := time.Now()
switch {
case t.Hour() < 12:
    fmt.Println("上午好")
case t.Hour() < 18:
    fmt.Println("下午好")
default:
    fmt.Println("晚上好")
}
```


## 数组与切片

### 数组

固定长度，声明方式 `[n]T`。

```go
var a [3]int
a[0] = 1
a[1] = 2
a[2] = 3
fmt.Println(a) // [1 2 3]

primes := [6]int{2, 3, 5, 7, 11, 13}
fmt.Println(primes)
```

数组是值类型，赋值或传参会拷贝整个数组。

### 切片（slice）

切片是数组的"动态视图"，更常用。`[]T` 表示元素类型为 T 的切片。

```go
// 从数组创建
primes := [6]int{2, 3, 5, 7, 11, 13}
var s []int = primes[1:4]   // 包含索引 1,2,3 -> [3 5 7]

// 切片字面量
names := []string{"Alice", "Bob", "Charlie"}

// 使用 make 创建
a := make([]int, 5)        // len=5, cap=5，零值填充
b := make([]int, 0, 5)     // len=0, cap=5

// 追加元素
a = append(a, 1, 2, 3)

// 遍历
for i, v := range a {
    fmt.Println(i, v)
}
```

切片底层引用一个数组，修改切片会反映到原始数组。`len()` 获取长度，`cap()` 获取容量。


## 映射（map）

映射存储键值对，声明方式 `map[K]V`，使用 `make` 初始化。

```go
m := make(map[string]int)
m["Alice"] = 25
m["Bob"] = 30

// 字面量
ages := map[string]int{
    "Charlie": 40,
    "Diana":   35,
}

// 取值
age := ages["Charlie"]   // 40

// 检查键是否存在
value, ok := ages["Unknown"]
if !ok {
    fmt.Println("键不存在")
}

// 删除键
delete(ages, "Bob")

// 遍历（顺序随机）
for key, value := range ages {
    fmt.Printf("%s -> %d\n", key, value)
}
```

访问不存在的键会返回零值，因此常用 `value, ok` 模式。


## 结构体与方法

### 结构体定义

```go
type Person struct {
    Name string
    Age  int
}

func main() {
    p := Person{"Alice", 30}
    fmt.Println(p.Name)

    // 字段名赋值
    p2 := Person{Name: "Bob", Age: 25}

    // 结构体指针
    p3 := &Person{Name: "Charlie", Age: 40}
    fmt.Println(p3.Age) // 指针自动解引用
}
```

### 方法

Go 没有类，但可以在类型上定义方法。方法是一个带有**接收者**的函数。

```go
type Rectangle struct {
    Width, Height float64
}

// 值接收者
func (r Rectangle) Area() float64 {
    return r.Width * r.Height
}

// 指针接收者（可以修改原值）
func (r *Rectangle) Scale(factor float64) {
    r.Width *= factor
    r.Height *= factor
}

func main() {
    rect := Rectangle{Width: 10, Height: 5}
    fmt.Println(rect.Area())  // 50

    rect.Scale(2)
    fmt.Println(rect.Area())  // 200
}
```

通常，类型的所有方法要么全部使用值接收者，要么全部使用指针接收者，以保持一致性。


## 接口

接口定义一组方法签名，任何类型只要实现了这些方法，就**隐式**实现了该接口。

```go
type Shape interface {
    Area() float64
    Perimeter() float64
}

type Circle struct {
    Radius float64
}

func (c Circle) Area() float64 {
    return math.Pi * c.Radius * c.Radius
}

func (c Circle) Perimeter() float64 {
    return 2 * math.Pi * c.Radius
}

func printShapeInfo(s Shape) {
    fmt.Printf("面积: %.2f, 周长: %.2f\n", s.Area(), s.Perimeter())
}

func main() {
    c := Circle{Radius: 5}
    printShapeInfo(c)  // 隐式实现了 Shape
}
```

### 空接口

`interface{}` 可以代表任何类型，类似于其他语言的 `Object` 或 `any`。

```go
var i interface{}
i = "hello"
fmt.Println(i)  // hello
i = 42
fmt.Println(i)  // 42
```

Go 1.18 引入了 `any` 作为 `interface{}` 的别名，语义相同。

### 类型断言

从接口值中提取具体类型：

```go
var i interface{} = "hello"
s := i.(string)
fmt.Println(s)

// 安全断言
s, ok := i.(string)
if ok {
    fmt.Println(s)
}
```


## 错误处理

Go 通过返回 `error` 类型来处理错误，而不是异常。`error` 是内置接口，只有一个 `Error() string` 方法。

```go
import (
    "errors"
    "fmt"
)

func divide(a, b float64) (float64, error) {
    if b == 0 {
        return 0, errors.New("除数不能为零")
    }
    return a / b, nil
}

func main() {
    result, err := divide(10, 0)
    if err != nil {
        fmt.Println("错误:", err)
        return
    }
    fmt.Println("结果:", result)
}
```

### 自定义错误类型

```go
type MyError struct {
    Msg string
    Code int
}

func (e *MyError) Error() string {
    return fmt.Sprintf("code %d: %s", e.Code, e.Msg)
}

func doSomething() error {
    return &MyError{"something wrong", 500}
}
```

通常，错误通过 `fmt.Errorf` 创建：

```go
err := fmt.Errorf("处理失败: %s", detail)
```


## defer、panic 与 recover

### defer

`defer` 语句将函数调用推迟到外层函数返回后执行，常用于资源清理。

```go
func readFile() {
    f, err := os.Open("file.txt")
    if err != nil {
        log.Fatal(err)
    }
    defer f.Close()  // 无论函数如何退出，都会关闭文件

    // 读取内容...
}
```

多个 `defer` 按"后进先出"顺序执行。

### panic 与 recover

`panic` 用于不可恢复的严重错误，正常情况下不要随意使用。`recover` 只能在 `defer` 中调用，可以捕获 `panic` 使程序继续执行。

```go
func mayPanic() {
    defer func() {
        if r := recover(); r != nil {
            fmt.Println("从 panic 恢复:", r)
        }
    }()
    panic("出现大问题")
}

func main() {
    mayPanic()
    fmt.Println("程序继续运行")
}
```

实际上很少使用 `panic/recover`，更推荐返回错误。


## 并发编程：goroutine 与 channel

### goroutine

`go` 关键字会启动一个轻量级线程（goroutine），它与当前函数并发执行。

```go
func say(s string) {
    for i := 0; i < 5; i++ {
        time.Sleep(100 * time.Millisecond)
        fmt.Println(s)
    }
}

func main() {
    go say("world")
    say("hello")
}
```

### channel

channel 是 goroutine 之间通信的管道，使用 `make` 创建。

```go
ch := make(chan int)   // 无缓冲通道

// 发送
ch <- 42

// 接收
value := <-ch
```

无缓冲 channel 会导致发送和接收 goroutine 同步阻塞。有缓冲 channel：`make(chan int, 2)` 允许在缓冲区未满时无阻塞发送。

```go
func sum(s []int, c chan int) {
    sum := 0
    for _, v := range s {
        sum += v
    }
    c <- sum
}

func main() {
    s := []int{7, 2, 8, -9, 4, 0}
    c := make(chan int)
    go sum(s[:len(s)/2], c)
    go sum(s[len(s)/2:], c)
    x, y := <-c, <-c // 从通道接收
    fmt.Println(x, y, x+y)
}
```

使用 `close` 关闭 channel，接收方可以用第二个返回值检测通道是否关闭。

```go
ch := make(chan int, 2)
ch <- 1
ch <- 2
close(ch)
for v := range ch {
    fmt.Println(v)
}
```

### select

`select` 语句使一个 goroutine 可以等待多个通信操作。

```go
func fibonacci(c, quit chan int) {
    x, y := 0, 1
    for {
        select {
        case c <- x:
            x, y = y, x+y
        case <-quit:
            fmt.Println("quit")
            return
        }
    }
}

func main() {
    c := make(chan int)
    quit := make(chan int)
    go func() {
        for i := 0; i < 10; i++ {
            fmt.Println(<-c)
        }
        quit <- 0
    }()
    fibonacci(c, quit)
}
```

### 同步：sync 包

除了 channel，Go 也提供传统的同步原语，如 `sync.Mutex`、`sync.WaitGroup`。

```go
var wg sync.WaitGroup
for i := 0; i < 5; i++ {
    wg.Add(1)
    go func(id int) {
        defer wg.Done()
        fmt.Printf("goroutine %d 完成\n", id)
    }(i)
}
wg.Wait()
```


## 标准库常用包

Go 标准库非常丰富，以下是新手最常用的几个包。

- **fmt**：格式化输入输出。`Println`、`Printf`、`Sprintf`、`Scan` 等。
- **os**：操作系统功能，如文件操作、环境变量、命令行参数。
- **io / ioutil**：`io.Reader`、`io.Writer` 接口，文件读取写入。
- **net/http**：构建 HTTP 客户端和服务端。
- **encoding/json**：JSON 编解码。
- **time**：时间处理。
- **strings**：字符串操作。
- **strconv**：字符串与基本类型转换。
- **log**：日志。

示例：HTTP 服务器

```go
package main

import (
    "fmt"
    "net/http"
)

func handler(w http.ResponseWriter, r *http.Request) {
    fmt.Fprintf(w, "Hello, %s!", r.URL.Path[1:])
}

func main() {
    http.HandleFunc("/", handler)
    http.ListenAndServe(":8080", nil)
}
```

运行后访问 `http://localhost:8080/world` 会显示 `Hello, world!`


## 测试入门

Go 语言内置轻量级测试框架。测试文件以 `_test.go` 结尾，函数名为 `TestXxx`，并接受 `*testing.T` 参数。

```go
// math_test.go
package main

import "testing"

func TestAdd(t *testing.T) {
    got := add(2, 3)
    want := 5
    if got != want {
        t.Errorf("add(2,3) = %d; want %d", got, want)
    }
}
```

运行测试：
```bash
go test
```

子测试和表格驱动测试是 Go 社区的惯用风格：

```go
func TestDivide(t *testing.T) {
    tests := []struct {
        a, b float64
        want float64
        errExpected bool
    }{
        {10, 2, 5, false},
        {10, 0, 0, true},
    }
    for _, tt := range tests {
        got, err := divide(tt.a, tt.b)
        if tt.errExpected && err == nil {
            t.Errorf("divide(%f,%f) 期望错误但没有发生", tt.a, tt.b)
        }
        if !tt.errExpected && got != tt.want {
            t.Errorf("divide(%f,%f) = %f; want %f", tt.a, tt.b, got, tt.want)
        }
    }
}
```


## 综合练习：猜数字游戏

把前面所学应用到一个小游戏中。

```bash
mkdir guessgame
cd guessgame
go mod init guessgame
```

新建 `main.go`：

```go
package main

import (
    "fmt"
    "math/rand"
    "time"
)

func main() {
    rand.Seed(time.Now().UnixNano())
    secret := rand.Intn(100) + 1

    fmt.Println("猜数字游戏！范围 1~100")

    var guess int
    for {
        fmt.Print("请输入你的猜测: ")
        fmt.Scanf("%d", &guess)

        if guess < secret {
            fmt.Println("太小了！")
        } else if guess > secret {
            fmt.Println("太大了！")
        } else {
            fmt.Println("恭喜你，猜对了！")
            break
        }
    }
}
```

运行：
```bash
go run main.go
```

这个游戏涵盖了变量、循环、条件判断、输入输出、包引入。你可以在此基础上添加猜测次数限制、错误输入处理等。


## 跨语言调用扩展

掌握 Go 语言基础后，你可以进一步学习如何使用 Go 调用其他语言编写的服务，或将 Go 函数暴露给其他语言调用。**zAPI** 提供了一套完整的跨语言调用方案：

- **Go 调用 C++/Python/Rust/Java 等异构服务**：通过 [API Hub for Go 从零到一掌握多语言互调](API%20Hub%20for%20Go%20从零到一掌握多语言互调.md) 实现零 IDL、零代码生成的跨语言 RPC。
- **将 Go 函数暴露为远程 API**：供 Python、C++、Rust、PHP、Node.js 等语言调用。
- **v2.0 新增**：支持动态注销 API（`Server.Unregister`）和运行时配置（`SetOption`）。
- **HTTP 网关支持**：PHP 和 Node.js 可通过 [ZAPI Bridge](../Py/bridge/📖%20ZAPI%20Bridge%20完整使用手册.md) 调用 Go 服务。

```go
// Go 调用 C++ 服务示例
client, _ := api_hub.NewClient()
client.PrepareClient("ipc:cpp_service")
client.PrepareDone()
h, _ := client.CreateDataHnd("compute")
client.WriteString(h, "hello world")
res, _ := client.Call("CppService", h, 5000)
result, _ := client.ReadString(res)
fmt.Println("C++ 计算结果:", result)
```


## 下一步学什么？

通过这篇指南，你已经掌握了 Go 语言的核心语法和最重要的并发原语，可以开始写一些实际应用了。继续深入的方向有：

1. **深入学习 goroutine 与 channel**：了解模式、避免死锁。
2. **标准库深度使用**：`net/http` 实现 REST API、`database/sql` 连接数据库。
3. **Go 的面向对象**：嵌入（embedding）代替继承、接口组合。
4. **泛型（Go 1.18+）**：类型参数的使用场景。
5. **常用框架与工具**：`gin`（Web 框架）、`gorm`（ORM）、`cobra`（CLI 工具）、`wire`（依赖注入）。
6. **阅读官方文档**：[A Tour of Go](https://go.dev/tour/) 是绝佳的互动教程；[Effective Go](https://go.dev/doc/effective_go) 是进阶必读。
7. **练手项目**：写一个 HTTP 服务器、命令行待办事项工具、文件下载器。
8. **跨语言调用**：学习 [API Hub for Go](API%20Hub%20for%20Go%20从零到一掌握多语言互调.md)，让 Go 与 C++/Python/Rust 等语言无缝通信。

**记住：Go 的精髓在于简洁与组合。** 多写代码，多看标准库源码，你会很快爱上这门语言。欢迎来到 Go 社区，祝你编码愉快！


## 📚 相关资源（其他语言指南）

- [API Hub Tool C++ 使用指南](../C++/API%20Hub%20Tool%20C++%20使用指南.md)
- [API Hub Tool C 语言使用指南](../C++/API%20Hub%20Tool%20C%20语言使用指南.md)
- [从零到一，掌握多语言互调](../Py/从零到一，掌握多语言互调.md)
- [API Hub for Go 从零到一掌握多语言互调](API%20Hub%20for%20Go%20从零到一掌握多语言互调.md)
- [zAPI Rust 使用指南](../rust/zAPI%20Rust%20使用指南.md)
- [API Hub Java 使用指南](../java/API%20Hub%20Java%20使用指南.md)
- [API Hub Tool for C# — 完整使用指南](../C%23/API%20Hub%20Tool%20for%20C%23%20—%20完整使用指南.md)
- [API Hub Tool for Pascal](../pascal/API%20Hub%20Tool%20for%20Pascal.md)
- [Node.js 跨语言调用方案选型：为什么我们选择 Python 网关而非 npm 原生包](../node/Node.js%20跨语言调用方案选型：为什么我们选择%20Python%20网关而非%20npm%20原生包.md)
- [老哥别卷了,你的 VB.NET 代码今天开始全栈通杀](../VB.NET/老哥别卷了,%20你的%20VB.NET%20代码今天开始全栈通杀.md)
- [浏览器调用 C++ 的三种方案对比：为什么我们选择了 zAPI 网关](../Py/web/浏览器调用%20C++%20的三种方案对比：为什么我们选择了%20zAPI%20网关.md)
- [js_api.py 使用指南](../Py/web/js_api.py%20使用指南.md)
- [📖 ZAPI Bridge 完整使用手册](../Py/bridge/📖%20ZAPI%20Bridge%20完整使用手册.md)
