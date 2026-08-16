# Node.js 支持的 JavaScript 语言白皮书

**版本：** 1.0（通用 JavaScript 语言参考）

---

## 1. 引言
Node.js 是基于 Chrome V8 引擎的 JavaScript 运行时，它让 JavaScript 脱离浏览器，在服务器、命令行等环境中运行。本白皮书系统讲解 Node.js（现代 LTS 版本如 20.x）所支持的 JavaScript 语言本身，涵盖从基础语法到现代特性，并突出与浏览器环境的差异及 Node.js 独有的全局能力。掌握这些内容，你将能够用 JavaScript 在 Node.js 中编写任何逻辑。

## 2. 基础语法与类型系统

### 2.1 变量声明与作用域
- **`var`**：函数级作用域，存在变量提升，易产生意外，**不推荐使用**。
- **`let`**：块级作用域，不存在提升（暂存死区），可重新赋值。
- **`const`**：块级作用域，声明时必须初始化，不可重新赋值，但对象属性可变。**声明常量与引用不变的变量时首选**。

```javascript
let count = 1;
count = 2;          // OK
const PI = 3.14;
PI = 3;             // TypeError
const user = { name: 'Alice' };
user.name = 'Bob';  // OK，改变属性而非绑定
```

**暂存死区 (TDZ)**：在声明前访问 `let/const` 变量会抛出 `ReferenceError`。

### 2.2 数据类型
分为**原始类型**和**对象类型**。

**原始类型**（7种）：
- `number`：双精度 64 位浮点数，特殊值 `NaN`, `Infinity`。
- `string`：UTF-16 字符串。
- `boolean`：`true` / `false`。
- `null`：表示空值。
- `undefined`：未定义，变量已声明未赋值时为 `undefined`。
- `symbol`：ES6，唯一的不可变值，常用于对象属性键。
- `bigint`：ES2020，任意精度整数，字面量后加 `n`，如 `123n`。

**对象类型**：Object、Array、Function、Date、RegExp、Map、Set 等。

**类型检测**：
- `typeof`：返回类型字符串。`typeof null` 返回 `"object"`（历史遗留），函数返回 `"function"`。
- `instanceof`：检测构造函数的 `prototype` 是否在实例的原型链上。
- `Object.prototype.toString.call(value)` 精确判断。

```javascript
console.log(typeof 42);         // "number"
console.log(typeof 'hello');    // "string"
console.log(typeof undefined);  // "undefined"
console.log(typeof null);       // "object"
console.log(typeof Symbol());   // "symbol"
console.log(typeof 10n);        // "bigint"
console.log([] instanceof Array); // true
```

### 2.3 类型转换
- **显式转换**：`String()`, `Number()`, `Boolean()`, `parseInt()`, `parseFloat()`, `toString()`。
- **隐式转换**：发生在运算符、条件判断中。
  - `+` 号如果有一方是字符串则拼接，否则数学加法。
  - `==` 会进行类型转换再比较，**一律使用 `===` 和 `!==` 避免强制转换**。
- **假值**：`false`, `0`, `''`, `null`, `undefined`, `NaN`。其余皆为真值。

```javascript
console.log(5 + '5');   // "55"
console.log(5 - '2');   // 3
console.log(Boolean('')); // false
```

### 2.4 运算符
- 算术：`+ - * / % **`（指数）`++ --`
- 比较：`> < >= <= == != === !==`
- 逻辑：`&& || !`
- 三元：`condition ? expr1 : expr2`
- 位运算：`& | ^ ~ << >> >>>`
- **可选链** `?.`：当左侧为 `null/undefined` 时短路返回 `undefined`，而不报错。
- **空值合并** `??`：左侧为 `null/undefined` 时返回右侧，否则左侧。与 `||` 不同，`||` 遇到假值就返回右侧。
- 逻辑赋值：`||= &&= ??=`

```javascript
const obj = { a: { b: 1 } };
console.log(obj.a?.b);      // 1
console.log(obj.c?.d);      // undefined
const port = process.env.PORT ?? 3000;
let x = null;
x ??= 10;   // x 变为 10
```

### 2.5 字符串
- **模板字面量**：反引号包裹，支持多行和 `${}` 插值。
- 常用方法：`length`, `charAt`, `slice`, `substring`, `indexOf`, `includes`, `startsWith`, `endsWith`, `toUpperCase`, `toLowerCase`, `trim`, `trimStart`, `trimEnd`, `replace`, `replaceAll`, `split`, `padStart`, `padEnd`。

```javascript
const name = 'Node';
console.log(`Hello, ${name}!`);
const str = '  example  ';
console.log(str.trim()); // 'example'
```

### 2.6 数字与数学
- `NaN` 不等于任何值包括自身，使用 `Number.isNaN()` 判断。
- `Number.isFinite()`, `Number.isInteger()`, `Number.parseInt()`, `Number.parseFloat()`。
- `Math` 对象提供常用数学函数与常量。
- **BigInt**：不能与普通 `number` 直接混合运算，需显式转换。

```javascript
const big = 9007199254740991n;
const sum = big + 1n;
```

### 2.7 布尔与条件
- 假值列表，其余全为真值。条件判断会自动转换为布尔值。

## 3. 控制流

### 3.1 条件语句
```javascript
if (condition) { ... } else if { ... } else { ... }
switch (expression) {
  case value1: ... break;
  default: ...
}
```

### 3.2 循环
- `for`, `while`, `do...while`
- **`for...of`**：遍历可迭代对象（数组、字符串、Map、Set、生成器等），**推荐用于数组元素遍历**。
- **`for...in`**：遍历对象自身的及继承的可枚举属性键名（用于对象属性，不推荐用于数组，因为顺序不稳定）。
- `break` 和 `continue` 控制循环。
- `Array.prototype.forEach` 不能提前终止。

```javascript
const arr = [10, 20, 30];
for (const val of arr) {
  console.log(val);
}
const obj = { a: 1, b: 2 };
for (const key in obj) {
  console.log(key, obj[key]);
}
```

### 3.3 异常处理
```javascript
try {
  // 可能抛出异常的代码
  throw new Error('出错了');
} catch (error) {
  console.error(error.message);
} finally {
  // 始终执行
}
```
Node.js 回调常遵循 `(err, data)` 约定，异步 Promise 用 `catch` 或 `try/catch` + `await`。

## 4. 函数

### 4.1 定义与调用
- 函数声明：`function add(a, b) { return a + b; }` （存在提升）
- 函数表达式：`const add = function(a, b) { return a + b; };`
- **箭头函数**：`(a, b) => a + b`。没有自己的 `this`, `arguments`, `super`，继承外层词法作用域。

### 4.2 参数
- **默认值**：`function multiply(a, b = 1) { return a * b; }`
- **剩余参数**：`function sum(...numbers) { ... }` ，将多个参数收集为数组，取代 `arguments`。
- `arguments` 对象为类数组，箭头函数中不存在。

### 4.3 高阶函数与回调
函数可以作为参数传递或返回，这是 Node.js 异步编程的基础。
```javascript
function greet(name, callback) {
  callback(`Hello ${name}`);
}
greet('Node', msg => console.log(msg));
```

### 4.4 闭包
函数内部可以访问其外部作用域的变量，即使外部函数已执行完毕。模块化、数据隐私等依赖闭包。

### 4.5 立即执行函数表达式 (IIFE)
`(function() { ... })();`，常用于创建独立作用域，但现代模块已替代大部分用途。

## 5. 数据结构：对象与数组

### 5.1 对象
- 字面量：`{ key: value }`
- 属性访问：点号 `obj.key` 或方括号 `obj['key']`，后者支持动态键。
- **计算属性名**：`{ [expression]: value }`
- **属性简写**：`const name = 'a'; const obj = { name };` 等价于 `{ name: name }`
- **方法简写**：`{ sayHi() {} }`
- `this` 指向调用时所在的对象（取决于调用方式）。箭头函数中的 `this` 来自词法作用域。

### 5.2 解构赋值
从对象或数组中提取值赋给变量。
```javascript
// 对象解构
const { name, age: userAge = 18 } = user;
// 数组解构
const [first, , third] = [1, 2, 3];
// 函数参数解构
function print({ title, content }) { ... }
// 嵌套解构
const { address: { city } } = person;
```

### 5.3 展开运算符 `...`
- 对象展开：`const newObj = { ...obj, newProp: 1 };` （浅拷贝）
- 数组展开：`const merged = [...arr1, ...arr2];`

### 5.4 数组核心方法
- 增删：`push`, `pop`, `shift`, `unshift`, `splice(start, deleteCount, ...items)`, `slice(start, end)`（浅拷贝）
- 查找：`indexOf`, `lastIndexOf`, `includes`, `find(callback)`, `findIndex(callback)`, `findLast` (ES2023), `findLastIndex`
- 迭代：`forEach`
- 转换：`map`, `filter`, `reduce`, `reduceRight`, `flat(depth)`, `flatMap`
- 测试：`every`, `some`
- 排序：`sort([compareFn])`，数字排序应传入 `(a,b) => a - b`
- 其他：`concat`, `join`, `reverse`, `fill`, `copyWithin`, `from`, `of`, `Array.isArray`
- `at(index)`：支持负数索引。

```javascript
const numbers = [1, 2, 3, 4];
const doubled = numbers.map(n => n * 2);
const evens = numbers.filter(n => n % 2 === 0);
const sum = numbers.reduce((acc, cur) => acc + cur, 0);
console.log(numbers.at(-1)); // 4
```

### 5.5 Map 与 Set
- **Map**：键值对集合，键可以是任意类型。`set`, `get`, `has`, `delete`, `size`, `clear`, 迭代：`forEach`, `for...of`
- **Set**：唯一值的集合。`add`, `has`, `delete`, `size`, `clear`, 迭代类似。
- **WeakMap/WeakSet**：键为对象且弱引用，不会阻止垃圾回收，不可枚举。

```javascript
const map = new Map();
map.set('key', 'value');
console.log(map.get('key'));
const set = new Set([1, 2, 2, 3]); // Set {1, 2, 3}
```

### 5.6 JSON
- `JSON.stringify(value[, replacer, space])`：序列化。
- `JSON.parse(text[, reviver])`：反序列化。
- 不支持 `undefined`、函数、Symbol、循环引用，遇到时会忽略或报错。

## 6. 类与面向对象

ES6 引入类语法，底层仍是原型继承，但语法更清晰。

### 6.1 类声明
```javascript
class Person {
  constructor(name) {
    this.name = name;
  }
  greet() {
    console.log(`Hi, I'm ${this.name}`);
  }
  // getter
  get displayName() {
    return `[${this.name}]`;
  }
  // setter
  set displayName(value) {
    this.name = value;
  }
}
const p = new Person('Alice');
p.greet();
```

### 6.2 继承
```javascript
class Employee extends Person {
  constructor(name, title) {
    super(name);  // 必须调用父类构造函数
    this.title = title;
  }
  greet() {
    super.greet();  // 调用父类方法
    console.log(`I'm a ${this.title}`);
  }
}
```

### 6.3 静态方法、属性和私有字段
- 静态：`static methodName() {}` 或 `static property = value;`（ES2022），通过类名调用，不继承实例。
- 私有字段：以 `#` 开头，只能在类内部访问。
```javascript
class Counter {
  #count = 0;  // 私有实例字段
  static #instances = 0; // 静态私有字段
  increment() {
    this.#count++;
  }
  get value() {
    return this.#count;
  }
}
```

### 6.4 类注意事项
- 类声明不像函数声明那样提升（存在 TDZ）。
- 内部默认使用严格模式。
- 方法不可枚举。

## 7. 模块系统

Node.js 同时支持 CommonJS 和 ES Modules。理解两者至关重要。

### 7.1 CommonJS (CJS)
- 每个文件是一个模块，拥有自己的作用域。
- **导出**：`module.exports = value;` 或 `exports.key = value;` （`exports` 是 `module.exports` 的引用，不能直接对它赋值，否则切断引用）。
- **导入**：`const module = require('path');`
  - 可省略 `.js` / `.json` / `.node` 扩展名。
  - 若为目录，则寻找 `index.js`。
- 模块加载是同步的，第一次加载后缓存结果。
- `require.resolve` 可查看模块确切的文件路径。

```javascript
// math.js
exports.add = (a, b) => a + b;
// 或
module.exports = { add: (a, b) => a + b };

// app.js
const { add } = require('./math');
console.log(add(2,3));
```

### 7.2 ES Modules (ESM)
- 使用 `import` 和 `export` 语句，Node.js 中需将文件命名为 `.mjs` 或在 `package.json` 中设置 `"type": "module"`。
- 静态导入，支持异步动态导入 `import()`。
- 导出方式：
  - 命名导出：`export const name = ...;` 或 `export { name };`
  - 默认导出：`export default expression;` 一个模块只能有一个默认导出。
- 导入方式：
  ```javascript
  import defaultExport, { named1, named2 as alias } from './module.mjs';
  import * as myModule from './module.mjs';
  ```
- **动态导入**：`const module = await import('./module.mjs');` 可用于 CommonJS 和 ESM 中，返回 Promise。支持在 `async` 函数或 ESM 顶层 await 中使用。
- ESM 模块作用域内可使用 `import.meta.url` 获取当前模块 URL。
- **顶层 await**：在 ESM 中，`await` 可直接用于模块顶层，无需包裹 `async` 函数。

```javascript
// utils.mjs
export function helper() {}
export default function main() {}

// app.mjs
import main, { helper } from './utils.mjs';
main();
// 动态导入示例
if (condition) {
  const { feature } = await import('./feature.mjs');
  feature();
}
```

### 7.3 互操作
- CJS 模块可以使用动态 `import()` 导入 ESM。
- ESM 模块可以导入 CJS 模块，CJS 的 `module.exports` 会被视为默认导出。但不能使用命名导入（除非使用包装）。
- 不建议混用时过于复杂，新项目推荐全部采用 ESM。

## 8. 异步编程核心

Node.js 基于事件循环，非阻塞 I/O，正确理解异步是语言使用的关键。

### 8.1 事件循环与任务队列简要
- 宏任务：`setTimeout`, `setInterval`, `setImmediate`, I/O 回调。
- 微任务：`process.nextTick` 回调（优先级高于 Promise），`Promise.then/catch/finally`。
- 执行顺序：同步代码 -> `process.nextTick` -> Promise 微任务 -> 宏任务（下一轮循环）。

### 8.2 回调函数
遵循错误优先模式：
```javascript
fs.readFile('file.txt', (err, data) => {
  if (err) return console.error(err);
  console.log(data);
});
```
应避免深层嵌套（回调地狱），转向 Promise。

### 8.3 Promise
创建一个 Promise：
```javascript
const promise = new Promise((resolve, reject) => {
  // 异步操作
  setTimeout(() => resolve('成功'), 1000);
});
```
- 实例方法：`.then(onFulfilled, onRejected)`, `.catch(onRejected)`, `.finally(onFinally)`
- 静态方法：
  - `Promise.resolve(value)`
  - `Promise.reject(reason)`
  - `Promise.all(iterable)`：全部成功才成功，有一个失败则失败。
  - `Promise.race(iterable)`：第一个完成（无论成功失败）为准。
  - `Promise.allSettled(iterable)`：等所有完成，返回结果数组（包含状态）。
  - `Promise.any(iterable)`：第一个成功则成功，全失败则拒绝。

```javascript
const p1 = Promise.resolve(1);
const p2 = new Promise(res => setTimeout(res, 100, 2));
const results = await Promise.all([p1, p2]); // [1, 2]
```

### 8.4 async / await
- `async` 函数始终返回一个 Promise。
- `await` 暂停函数执行，直到 Promise 敲定，并返回 resolve 的值或抛出 reject。
- 错误处理：用 `try/catch` 包裹 `await` 表达式，或对返回的 Promise 添加 `.catch`。

```javascript
async function fetchData() {
  try {
    const data = await someAsyncOperation();
    return data;
  } catch (err) {
    console.error('操作失败', err);
    throw err; // 或处理
  }
}
// 顶层 await（仅ESM）
// const result = await fetchData();
```

### 8.5 定时器与微任务
- `setTimeout(callback, delay)`：延迟后执行一次。
- `setInterval(callback, interval)`：周期性执行。
- `setImmediate(callback)`：在当前事件循环的"check"阶段执行，相当于 `setTimeout(fn, 0)` 但优先级稍有不同，通常在 I/O 回调后立即执行。
- `process.nextTick(callback)`：将回调放入微任务队列，在当前操作完成后、任何 I/O 事件之前执行。**谨慎使用，防止递归造成 I/O 饥饿**。
- `clearTimeout`, `clearInterval`, `clearImmediate` 取消定时器。

## 9. 迭代器与生成器

### 9.1 可迭代协议
一个对象成为可迭代的，需实现 `Symbol.iterator` 方法，返回一个迭代器。迭代器有 `next()` 方法，返回 `{ value, done }`。
内置可迭代对象：Array, String, Map, Set, arguments, NodeList 等。

### 9.2 for...of 循环
```javascript
for (const char of 'hello') { ... }
```

### 9.3 生成器 Generator
- 函数声明：`function* gen() { yield value; }`
- 调用生成器返回一个迭代器对象，可以使用 `next()`, `for...of`。
- `yield` 可暂停函数执行并返回值，`next(arg)` 可传入值作为上次 `yield` 的返回值。
- 生成器可用于实现异步流程控制（但不常见，现在多用 async/await）。

```javascript
function* idGenerator() {
  let id = 0;
  while (true) {
    yield id++;
  }
}
const gen = idGenerator();
console.log(gen.next().value); // 0
console.log(gen.next().value); // 1
```

## 10. 错误处理与调试增强

- `Error` 对象：`message`, `stack`, `name`。可自定义错误类：
  ```javascript
  class AppError extends Error {
    constructor(message, code) {
      super(message);
      this.code = code;
    }
  }
  ```
- **捕获堆栈**：`Error.captureStackTrace` (V8 专属，常用于自定义错误)。
- **全局未捕获处理**：
  - `process.on('uncaughtException', handler)` – 同步代码未捕获异常。
  - `process.on('unhandledRejection', handler)` – Promise 拒绝未处理。
  仅用于日志与优雅退出，不应让进程继续运行。
- 使用 `console.trace()` 打印当前堆栈。

## 11. Node.js 特有的全局对象与能力

这些并非 JavaScript 语言标准，而是 Node.js 提供的环境特性，但它们深深融入了日常编程。

### 11.1 `global`
类似于浏览器中的 `window`，是全局命名空间。变量未声明直接赋值会变成 `global` 的属性（严格模式下禁止）。使用 `globalThis` 可以跨环境访问全局对象（ES2020）。

### 11.2 `process`
进程对象，至关重要。
- `process.env`：环境变量对象。
- `process.argv`：命令行参数数组。
- `process.exit([code])`：退出进程。
- `process.cwd()`：当前工作目录。
- `process.stdout`, `process.stderr`, `process.stdin`：标准流。
- `process.nextTick(callback)`：微任务调度。
- `process.uptime()`, `process.memoryUsage()`, `process.hrtime()` 等。

### 11.3 `console`
`console.log`, `info`, `warn`, `error`, `debug`, `trace`, `time/timeEnd` 等。在 Node 中输出到标准输出流。

### 11.4 `Buffer`
用于处理二进制数据，是 Node 核心类型。可以从字符串、数组创建，转换编码。
```javascript
const buf = Buffer.from('hello', 'utf8');
console.log(buf.toString('hex'));
```
现代 JavaScript 有 `TypedArray`，但在文件系统和网络编程中 `Buffer` 仍很常用。

### 11.5 `__dirname` 和 `__filename`
- `__dirname`：当前模块文件所在目录的绝对路径。
- `__filename`：当前模块文件的绝对路径。
- 仅在 CommonJS 模块中可用。在 ESM 中，可使用 `import.meta.url` 和 `fileURLToPath` 获得类似信息。

### 11.6 `require`、`module`、`exports`
CommonJS 模块的核心，前面已详述。

### 11.7 `setImmediate` / `clearImmediate`
已介绍。

### 11.8 `URL` 和 `URLSearchParams`
实现了 WHATWG URL 标准，方便处理 URL。
```javascript
const myURL = new URL('https://example.com:8000/path?name=Node');
console.log(myURL.searchParams.get('name')); // Node
```
全局可用，无需导入。

## 12. 现代 JavaScript 特性在 Node.js 中的使用

现代 Node.js LTS 版本支持绝大多数 ES2023 及之前的标准特性。以下是开发中常用且须掌握的：

- **可选链** `?.` 和 **空值合并** `??`（见 2.4）。
- **逻辑赋值运算符**：`||=`, `&&=`, `??=`
- **数字分隔符**：`1_000_000` 增强可读性。
- **`String.prototype.matchAll`**：返回所有匹配的迭代器。
- **`Promise.any`**，**`Promise.allSettled`**（见 8.3）。
- **`Object.fromEntries()`**：将键值对列表转为对象，是 `Object.entries` 的逆操作。
- **`Array.prototype.flat()` 和 `flatMap()`**。
- **`globalThis`**：统一访问全局对象。
- **类中的静态初始化块**：`static { ... }` 执行类设置代码。
- **私有字段和方法**（`#`）。
- **顶层 await**（在 ESM 中）。
- **`WeakRef` 和 `FinalizationRegistry`**（高级内存管理，谨慎使用）。

```javascript
// 使用示例
const entries = [['a', 1], ['b', 2]];
const obj = Object.fromEntries(entries); // { a: 1, b: 2 }
const bigNum = 1_000_000_000n;
```

## 13. 编码规范与最佳实践

在 Node.js 中编写 JavaScript，建议遵循以下约定以提高代码质量和可维护性。

- **使用严格模式**：Node 模块默认自动使用，无需手动声明 `"use strict"`。
- **变量声明**：全部使用 `const` 和 `let`，杜绝 `var`。
- **比较**：始终使用 `===` 和 `!==`。
- **函数**：尽量使用箭头函数保留词法 `this`，避免 `var self = this` 模式。
- **异步处理**：优先使用 `async/await`；每个 `await` 都要有错误处理或由上层捕获。
- **模块**：新项目推荐使用 ES 模块，清晰可移植。
- **命名约定**：变量、函数用驼峰命名，类和构造函数用帕斯卡命名，常量用大写蛇形命名。
- **避免全局污染**：不要向 `global` 添加属性。
- **使用 `path` 模块处理路径**，不要手动拼接字符串。
- **环境配置**：用 `process.env` 配合 `.env` 文件管理配置。
- **代码格式化与 Linting**：使用 ESLint + Prettier 统一风格。

## 14. 跨语言调用扩展

掌握 JavaScript 基础后，你可以进一步学习如何使用 Node.js 调用其他语言编写的服务。**zAPI** 提供了一套完整的跨语言调用方案：

- **Node.js 调用 C++/Python/Go/Rust 等异构服务**：通过 [ZAPI Bridge](../Py/bridge/📖%20ZAPI%20Bridge%20完整使用手册.md) 实现零依赖、零编译的 HTTP 网关调用。
- **双向调用**：Node.js 不仅可以调用其他语言，也可以被其他语言调用。
- **v2.0 新增**：支持 PHP 和浏览器 JavaScript 通过同一网关接入。

```javascript
// Node.js 调用 C++ 服务示例（通过 ZAPI Bridge）
const { callRemote } = require('./gateway-client');
const result = await callRemote('CppService', 'sha256', ['hello world']);
console.log('哈希结果:', result);
