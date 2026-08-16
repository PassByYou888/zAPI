# Node.js 使用入门白皮书

**版本：** 1.0（通用 Node.js 入门指南）

---

## 1. 引言

Node.js 是一个基于 Chrome V8 引擎的 JavaScript 运行时环境，它让 JavaScript 能够脱离浏览器在服务器端运行。其事件驱动、非阻塞 I/O 模型使其非常适合构建高并发、实时性要求高的网络应用。本白皮书旨在为初学者提供一份准确、全面、可实践的入门指南，覆盖从环境搭建到构建完整 Web 服务的关键环节。

---

## 2. 安装与环境配置

### 2.1 版本选择
Node.js 提供两种主要版本线：
- **LTS（长期支持版）**：偶数版本号，如 20.x、18.x，适合生产环境，稳定且长期维护。
- **Current（当前版）**：奇数版本号，包含最新特性，适合尝鲜与测试。

推荐初学者安装最新的 LTS 版本。

### 2.2 安装方式
- **Windows / macOS**：访问 [nodejs.org](https://nodejs.org) 下载官方安装包，按向导完成安装。安装程序会自动配置 `PATH` 环境变量。
- **Linux**（Debian/Ubuntu 示例）：
  ```bash
  curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash -
  sudo apt-get install -y nodejs
  ```
  也可使用系统包管理器，但版本可能较旧，不推荐。
- **使用 nvm（Node Version Manager）**：适用于多版本共存，推荐开发环境使用。
  ```bash
  curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.7/install.sh | bash
  # 重启终端后
  nvm install --lts
  nvm use --lts
  ```

### 2.3 验证安装
打开终端（命令行）执行：
```bash
node -v   # 应显示 v20.x.x 等版本号
npm -v    # 应显示 npm 版本号
```
`npm` 是 Node 的包管理器，随 Node 一起安装。

### 2.4 第一个程序
创建 `hello.js`：
```javascript
console.log('Hello, Node.js!');
```
终端运行：
```bash
node hello.js
```
输出 `Hello, Node.js!` 即表示环境就绪。

---

## 3. 核心基础

### 3.1 全局对象
Node.js 中没有浏览器中的 `window`，顶层全局对象是 `global`。常用全局成员：
- `console`：日志输出。
- `setTimeout` / `clearTimeout`、`setInterval` / `clearInterval`：定时器，与浏览器行为一致。
- `__dirname`：当前模块所在目录的绝对路径。
- `__filename`：当前模块文件的绝对路径。
- `process`：进程对象，包含环境变量、标准输入输出等。
- `Buffer`：处理二进制数据。

### 3.2 模块系统 (CommonJS)
Node.js 默认使用 CommonJS 模块规范（`.js` 文件）。每个文件被视为一个独立的模块。

**导出模块**：
```javascript
// math.js
function add(a, b) {
  return a + b;
}
const PI = 3.14159;
module.exports = { add, PI };
// 或者单独导出：exports.add = add;
```

**导入模块**：
```javascript
// app.js
const math = require('./math.js');
console.log(math.add(2, 3)); // 5
```
`require` 会缓存模块，多次引用同一个模块只会执行一次。

**模块查找顺序**：
- 若路径以 `./` 或 `../` 开头，按文件路径查找。
- 若为内置模块名（如 `fs`、`http`），直接加载核心模块。
- 否则从 `node_modules` 目录向上查找。

### 3.3 ES 模块（ESM）
从 Node.js 12 起支持 ECMAScript 模块。使用 `.mjs` 扩展名，或在 `package.json` 中设置 `"type": "module"`。语法：
```javascript
// math.mjs
export function add(a, b) { return a + b; }
// app.mjs
import { add } from './math.mjs';
```
本白皮书主要使用 CommonJS，但掌握 ESM 也是必要的。

### 3.4 npm 与包管理
`npm`（Node Package Manager）是世界上最大的开源库生态系统。基本命令：

- `npm init`：初始化项目，生成 `package.json`。
  - 推荐 `npm init -y` 快速生成默认配置。
- `npm install <package>`：安装依赖。默认会记录在 `package.json` 的 `dependencies`。
  - 简写：`npm i <package>`。
- `npm install --save-dev <package>`：安装开发依赖（如测试框架、linter），记录在 `devDependencies`。
- `npm uninstall <package>`：卸载包。
- `npm update`：更新依赖。
- 全局安装：`npm i -g <package>`（例如 `nodemon`），可将命令行工具安装到系统路径。

`node_modules` 目录存放所有依赖，不应提交到版本控制。`package-lock.json` 锁定依赖版本树，确保安装一致性。

### 3.5 package.json 重要字段
```json
{
  "name": "my-app",
  "version": "1.0.0",
  "main": "index.js",          // 包入口
  "scripts": {
    "start": "node index.js",
    "dev": "nodemon index.js"
  },
  "dependencies": { ... },
  "devDependencies": { ... }
}
```
通过 `npm run <script>` 执行自定义脚本。

---

## 4. 异步编程核心

Node.js 的强项在于处理 I/O 密集型任务，其非阻塞特性依赖于异步编程模式。理解异步是使用 Node 的关键。

### 4.1 回调函数 (Callback)
传统的异步处理方式，易形成"回调地狱"。
```javascript
const fs = require('fs');
fs.readFile('file.txt', 'utf8', (err, data) => {
  if (err) {
    console.error('读取失败：', err);
    return;
  }
  console.log(data);
});
```
**约定**：回调的第一个参数为错误对象（如果有），第二个起为结果数据。

### 4.2 Promise
ES6 引入，解决了回调嵌套和错误处理混乱问题。
```javascript
const fsPromises = require('fs').promises;
fsPromises.readFile('file.txt', 'utf8')
  .then(data => console.log(data))
  .catch(err => console.error(err));
```
Promise 有三种状态：pending、fulfilled、rejected。可以链式调用 `.then()` 和 `.catch()`。

### 4.3 async / await
基于 Promise 的语法糖，让异步代码看起来像同步代码，极大提升可读性和可维护性。
```javascript
const fs = require('fs').promises;

async function readData() {
  try {
    const data = await fs.readFile('file.txt', 'utf8');
    console.log(data);
  } catch (err) {
    console.error('错误：', err);
  }
}
readData();
```
注意：`await` 只能在 `async` 函数内部使用。顶层 `await` 在 ESM 中可用。

**推荐做法**：在现代 Node.js 开发中，凡是涉及异步操作，尽量使用 `async/await` 加上 `try/catch` 进行错误处理。

---

## 5. 核心模块实战

Node.js 内置了许多实用模块，无需额外安装即可使用。这里选择最具代表性的进行讲解。

### 5.1 文件系统 (fs)
负责与文件系统交互，提供同步、异步、Promise 三套 API。推荐使用基于 Promise 的版本（`fs/promises`）。

```javascript
const fs = require('fs/promises');

// 读取文件
const content = await fs.readFile('input.txt', 'utf8');
// 写入文件（覆盖）
await fs.writeFile('output.txt', '新内容');
// 追加写入
await fs.appendFile('output.txt', '\n追加行');
// 检查文件是否存在
try {
  await fs.access('somefile.txt');
  console.log('文件存在');
} catch {
  console.log('文件不存在');
}
// 读取目录
const files = await fs.readdir('.');
console.log(files);
// 创建目录
await fs.mkdir('newDir', { recursive: true }); // recursive 防止父目录不存在报错
```

### 5.2 路径处理 (path)
跨平台处理文件路径，避免手动拼接。
```javascript
const path = require('path');

const fullPath = path.join(__dirname, 'files', 'data.txt');
console.log(fullPath); // 拼接路径，自动处理分隔符
console.log(path.extname('image.png')); // .png
console.log(path.basename('/foo/bar/baz.html')); // baz.html
console.log(path.dirname('/foo/bar/baz.html')); // /foo/bar
console.log(path.resolve('src', 'index.js')); // 解析为绝对路径
```

### 5.3 HTTP 模块
直接创建 HTTP 服务器，无需第三方框架。理解它的原理对后续使用 Express 等框架很有帮助。
```javascript
const http = require('http');

const server = http.createServer((req, res) => {
  // req: 请求对象, res: 响应对象
  const { method, url } = req;
  console.log(`${method} ${url}`);

  if (url === '/') {
    res.writeHead(200, { 'Content-Type': 'text/html; charset=utf-8' });
    res.end('<h1>欢迎</h1>');
  } else if (url === '/api') {
    res.writeHead(200, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({ message: 'Hello API' }));
  } else {
    res.writeHead(404);
    res.end('Not Found');
  }
});

server.listen(3000, () => {
  console.log('服务器运行在 http://localhost:3000');
});
```
这种直接处理路由的方式仅适用于演示。实际项目应使用框架。

### 5.4 事件模块 (events)
Node.js 的核心 API 大多基于事件驱动架构。`EventEmitter` 用于创建和处理自定义事件。
```javascript
const EventEmitter = require('events');

class MyEmitter extends EventEmitter {}
const myEmitter = new MyEmitter();

// 监听事件
myEmitter.on('data', (info) => {
  console.log('收到数据:', info);
});

// 触发事件
myEmitter.emit('data', { id: 1, msg: 'hello' });
```
常见模式：`on` 注册监听器，`emit` 触发事件，`once` 只监听一次。

### 5.5 流 (Stream)
流用于处理大量数据，避免一次性加载到内存。分为可读流、可写流、双工流和转换流。
```javascript
const fs = require('fs');

// 创建可读流和可写流
const readStream = fs.createReadStream('largeFile.txt', 'utf8');
const writeStream = fs.createWriteStream('copy.txt');

// 管道式传输
readStream.pipe(writeStream);

// 或者监听事件
readStream.on('data', (chunk) => {
  console.log('收到块:', chunk.length);
});
readStream.on('end', () => {
  console.log('读取完毕');
});
readStream.on('error', (err) => {
  console.error(err);
});
```
`pipe()` 自动处理背压，是流最常用的方法。

### 5.6 操作系统信息 (os)
```javascript
const os = require('os');
console.log('CPU 架构:', os.arch());
console.log('内存总量(字节):', os.totalmem());
console.log('空闲内存:', os.freemem());
console.log('临时目录:', os.tmpdir());
console.log('主机名:', os.hostname());
```

---

## 6. 构建一个真实的 Web 应用

为体现实用性，我们使用最流行的 Express 框架搭建一个提供静态文件服务、RESTful API 接口的简易服务，并连接数据库（以 SQLite 为例）。

### 6.1 初始化项目
```bash
mkdir my-webapp
cd my-webapp
npm init -y
npm install express
npm install --save-dev nodemon
```
修改 `package.json` 的 `scripts`：
```json
"scripts": {
  "start": "node server.js",
  "dev": "nodemon server.js"
}
```

### 6.2 创建服务器 (server.js)
```javascript
const express = require('express');
const path = require('path');
const app = express();
const PORT = process.env.PORT || 3000;

// 中间件：解析 JSON 请求体
app.use(express.json());
// 中间件：服务静态文件
app.use(express.static(path.join(__dirname, 'public')));

// 路由示例
app.get('/', (req, res) => {
  res.sendFile(path.join(__dirname, 'public', 'index.html'));
});

// RESTful API 示例：返回用户列表
let users = [
  { id: 1, name: 'Alice' },
  { id: 2, name: 'Bob' }
];

app.get('/api/users', (req, res) => {
  res.json(users);
});

app.post('/api/users', (req, res) => {
  const newUser = { id: users.length + 1, name: req.body.name };
  users.push(newUser);
  res.status(201).json(newUser);
});

// 全局错误处理中间件
app.use((err, req, res, next) => {
  console.error(err.stack);
  res.status(500).send('服务器内部错误');
});

app.listen(PORT, () => {
  console.log(`服务启动: http://localhost:${PORT}`);
});
```
在 `public` 目录下创建简单的 `index.html`，即可通过浏览器访问。

### 6.3 集成数据库 (SQLite)
安装 `better-sqlite3`（同步但快速）：
```bash
npm install better-sqlite3
```
创建 `db.js`：
```javascript
const Database = require('better-sqlite3');
const db = new Database('app.db');

// 建表
db.exec(`
  CREATE TABLE IF NOT EXISTS users (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    name TEXT NOT NULL,
    email TEXT UNIQUE
  )
`);
module.exports = db;
```
修改路由使用数据库：
```javascript
const db = require('./db');

app.get('/api/users', (req, res) => {
  const users = db.prepare('SELECT * FROM users').all();
  res.json(users);
});

app.post('/api/users', (req, res) => {
  const { name, email } = req.body;
  const stmt = db.prepare('INSERT INTO users (name, email) VALUES (?, ?)');
  const result = stmt.run(name, email);
  res.status(201).json({ id: result.lastInsertRowid, name, email });
});
```

### 6.4 环境变量管理
使用 `dotenv` 管理敏感配置：
```bash
npm install dotenv
```
创建 `.env` 文件：
```
PORT=3000
DB_PATH=app.db
```
在 `server.js` 最顶部引入：
```javascript
require('dotenv').config();
// 然后可用 process.env.PORT
```

---

## 7. 错误处理与调试

### 7.1 常见错误类型
- **同步异常**：`try/catch` 捕获。
- **异步错误**：Promise 的 `reject` 用 `catch` 或 `try/catch` + `await` 处理。
- **回调错误**：遵循 `(err, data)` 模式，判断 `if (err)`。
- **未捕获的异常**：可能导致进程崩溃。可通过 `process.on('uncaughtException', handler)` 兜底，但一般仅记录日志并优雅退出。
- **未处理的 Promise 拒绝**：监听 `process.on('unhandledRejection', handler)`。

**永远不要忽视错误处理**。每次异步操作都应处理可能出现的错误。

### 7.2 调试
- **console.log**：简单但有效。
- **Node.js 内置调试器**：`node inspect app.js`。
- **Chrome DevTools**：运行 `node --inspect-brk app.js`，然后打开 `chrome://inspect`。
- **VS Code 集成调试**：创建 `.vscode/launch.json` 配置，直接按 F5 调试。
- **日志库**：生产环境推荐 `winston`、`pino` 等结构化日志。

---

## 8. 测试基础

使用内置的 `node:test` 模块（Node 18+）或 `Jest`。示例使用 `node:test`：
```javascript
// test.js
const test = require('node:test');
const assert = require('assert');

test('加法测试', () => {
  assert.strictEqual(1 + 1, 2);
});
```
运行 `node test.js`。更复杂的测试需搭配 `supertest` 测试 HTTP 接口。

---

## 9. 部署与最佳实践

- **进程管理**：使用 `pm2` 保持应用存活，提供负载均衡和日志管理。
  ```bash
  npm install -g pm2
  pm2 start server.js --name my-app
  ```
- **反向代理**：生产环境通常将 Node 应用置于 Nginx 之后，处理静态资源、SSL 终止。
- **安全**：及时更新依赖（`npm audit`），避免 `eval`，验证输入，设置 HTTP 安全头（可用 `helmet` 中间件）。
- **性能**：避免同步阻塞操作，合理利用缓存，数据库查询优化，使用 cluster 模块或多进程。

---

## 10. 学习路线进阶

掌握本白皮书内容后，应继续深入学习：
- **Express 进阶**：中间件机制、路由组织、模板引擎。
- **数据库**：MySQL、PostgreSQL、MongoDB 的使用，ORM（如 Prisma、Sequelize）。
- **异步流程**：深入事件循环、微任务/宏任务机制。
- **RESTful API 设计**：状态码、版本控制、认证（JWT）。
- **GraphQL**：替代方案。
- **WebSocket**：`ws` 或 Socket.IO 实现实时通信。
- **测试框架**：Jest/Mocha + Chai，端到端测试。
- **Docker** 容器化部署。
- **TypeScript**：为 Node 项目添加类型安全。
- **跨语言调用**：通过 [ZAPI Bridge](../Py/bridge/📖%20ZAPI%20Bridge%20完整使用手册.md) 让 Node.js 无缝调用 C++/Python/Go/Rust 等异构服务。

---

## 11. 结语

Node.js 凭借其高效、轻量与庞大的生态，已成为现代 Web 开发不可或缺的一环。本白皮书从环境搭建、核心概念、异步编程、内置模块到实际应用开发，构建了一条平滑的入门路径。只有亲自动手编写、调试、扩展代码，才能真正内化这些知识。希望这份指南能成为你进入 Node.js 世界的第一块坚实基石。

---

## 📚 相关资源（其他语言指南）

- [API Hub Tool C++ 使用指南](../C++/API%20Hub%20Tool%20C++%20使用指南.md)
- [API Hub Tool C 语言使用指南](../C++/API%20Hub%20Tool%20C%20语言使用指南.md)
- [从零到一，掌握多语言互调](../Py/从零到一，掌握多语言互调.md)
- [API Hub for Go 从零到一掌握多语言互调](../Go/API%20Hub%20for%20Go%20从零到一掌握多语言互调.md)
- [zAPI Rust 使用指南](../rust/zAPI%20Rust%20使用指南.md)
- [API Hub Java 使用指南](../java/API%20Hub%20Java%20使用指南.md)
- [API Hub Tool for C# — 完整使用指南](../C%23/API%20Hub%20Tool%20for%20C%23%20—%20完整使用指南.md)
- [API Hub Tool for Pascal](../pascal/API%20Hub%20Tool%20for%20Pascal.md)
- [Node.js 跨语言调用方案选型：为什么我们选择 Python 网关而非 npm 原生包](Node.js%20跨语言调用方案选型：为什么我们选择%20Python%20网关而非%20npm%20原生包.md)
- [老哥别卷了,你的 VB.NET 代码今天开始全栈通杀](../VB.NET/老哥别卷了,%20你的%20VB.NET%20代码今天开始全栈通杀.md)
- [浏览器调用 C++ 的三种方案对比：为什么我们选择了 zAPI 网关](../Py/web/浏览器调用%20C++%20的三种方案对比：为什么我们选择了%20zAPI%20网关.md)
- [js_api.py 使用指南](../Py/web/js_api.py%20使用指南.md)
- [📖 ZAPI Bridge 完整使用手册](../Py/bridge/📖%20ZAPI%20Bridge%20完整使用手册.md)
