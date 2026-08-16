// Client1.cpp - 客户端1，注册 client1_echo，支持交互命令调用服务端和 Client2
#include <iostream>
#include <string>
#include <cstring>
#include <vector>
#include <sstream>
#include <thread>
#include <chrono>
#include <atomic>
#include <mutex>
#include <condition_variable>
#include <queue>
#include "API_HubTool.h"

using namespace std;

static atomic<bool> g_bExit(false);
static mutex g_cmdMutex;
static condition_variable g_cv;
static queue<string> g_cmdQueue;

// ----- 自己的 API: 回显 -----
static void __cdecl Client1EchoCallback(void*, void* Input, void* Output)
{
    TDataHnd hIn = (TDataHnd)Input, hOut = (TDataHnd)Output;
    int64_t size = API_GetSize(hIn);
    if (size > 0) {
        vector<char> buf((size_t)size);
        API_SetPos(hIn, 0);
        API_ReadBuffer(hIn, buf.data(), size);
        API_WriteBuffer(hOut, buf.data(), size);
    }
}

// ----- 辅助：解析并调用服务端 add -----
static void CallServiceAdd(int a, int b)
{
    TDataHnd data = API_Create_DataHnd("add");
    API_WriteBuffer(data, &a, sizeof(int));
    API_WriteBuffer(data, &b, sizeof(int));
    TDataHnd result = API_Call("ServiceApp", data, 3000);
    API_Free_DataHnd(data);
    if (result && API_GetSize(result) >= sizeof(int)) {
        int sum;
        API_SetPos(result, 0);
        API_ReadBuffer(result, &sum, sizeof(int));
        cout << "Service.add(" << a << "," << b << ") = " << sum << endl;
        API_Free_DataHnd(result);
    }
    else {
        cout << "Service.add failed or timeout." << endl;
    }
}

static void CallServiceEcho(const string& msg)
{
    TDataHnd data = API_Create_DataHnd("echo");
    API_WriteBuffer(data, msg.c_str(), msg.size() + 1);
    TDataHnd result = API_Call("ServiceApp", data, 3000);
    API_Free_DataHnd(data);
    if (result && API_GetSize(result) > 0) {
        int64_t sz = API_GetSize(result);
        vector<char> buf((size_t)sz + 1);
        API_SetPos(result, 0);
        API_ReadBuffer(result, buf.data(), sz);
        buf[sz] = '\0';
        cout << "Service.echo replied: " << buf.data() << endl;
        API_Free_DataHnd(result);
    }
    else {
        cout << "Service.echo failed." << endl;
    }
}

static void CallServiceGetTime()
{
    TDataHnd data = API_Create_DataHnd("get_time");
    TDataHnd result = API_Call("ServiceApp", data, 3000);
    API_Free_DataHnd(data);
    if (result && API_GetSize(result) > 0) {
        int64_t sz = API_GetSize(result);
        vector<char> buf((size_t)sz + 1);
        API_SetPos(result, 0);
        API_ReadBuffer(result, buf.data(), sz);
        buf[sz] = '\0';
        cout << "Service.get_time = " << buf.data() << endl;
        API_Free_DataHnd(result);
    }
    else {
        cout << "Service.get_time failed." << endl;
    }
}

static void CallClient2Reverse(const string& msg)
{
    TDataHnd data = API_Create_DataHnd("client2_reverse");
    API_WriteBuffer(data, msg.c_str(), msg.size() + 1);
    TDataHnd result = API_Call("Client2", data, 3000);
    API_Free_DataHnd(data);
    if (result && API_GetSize(result) > 0) {
        int64_t sz = API_GetSize(result);
        vector<char> buf((size_t)sz + 1);
        API_SetPos(result, 0);
        API_ReadBuffer(result, buf.data(), sz);
        buf[sz] = '\0';
        cout << "Client2.reverse replied: " << buf.data() << endl;
        API_Free_DataHnd(result);
    }
    else {
        cout << "Client2.reverse failed (Client2 may not be running)." << endl;
    }
}

// ----- 控制台线程：读取命令 -----
static void ConsoleThread()
{
    string line;
    while (!g_bExit) {
        cout << "Client1> ";
        getline(cin, line);
        if (line == "exit") {
            g_bExit = true;
            break;
        }
        {
            lock_guard<mutex> lock(g_cmdMutex);
            g_cmdQueue.push(line);
        }
        g_cv.notify_one();
    }
}

// ----- 主线程执行命令（所有 API 调用在此）-----
static void ProcessCommand(const string& cmd, TAppHnd app)
{
    if (cmd.empty()) return;
    // 解析命令：格式 "call service add 10 20" 等
    istringstream iss(cmd);
    string verb;
    iss >> verb;
    if (verb == "call") {
        string target, api;
        iss >> target >> api;
        if (target == "service") {
            if (api == "add") {
                int a, b;
                if (iss >> a >> b) {
                    CallServiceAdd(a, b);
                }
                else {
                    cout << "Usage: call service add <a> <b>" << endl;
                }
            }
            else if (api == "echo") {
                string msg;
                getline(iss, msg);
                // 去除前导空格
                size_t pos = msg.find_first_not_of(' ');
                if (pos != string::npos) msg = msg.substr(pos);
                if (!msg.empty()) {
                    CallServiceEcho(msg);
                }
                else {
                    cout << "Usage: call service echo <message>" << endl;
                }
            }
            else if (api == "get_time") {
                CallServiceGetTime();
            }
            else {
                cout << "Unknown service API: " << api << endl;
            }
        }
        else if (target == "client2") {
            if (api == "reverse") {
                string msg;
                getline(iss, msg);
                size_t pos = msg.find_first_not_of(' ');
                if (pos != string::npos) msg = msg.substr(pos);
                if (!msg.empty()) {
                    CallClient2Reverse(msg);
                }
                else {
                    cout << "Usage: call client2 reverse <message>" << endl;
                }
            }
            else {
                cout << "Unknown client2 API: " << api << endl;
            }
        }
        else {
            cout << "Unknown target: " << target << endl;
        }
    }
    else {
        cout << "Unknown command. Available: call <service|client2> <api> ..." << endl;
    }
}

int main()
{
    cout << "=== API Hub Client1 ===" << endl;
    if (!API_LoadLibrary()) {
        cerr << "Failed to load API Hub library." << endl;
        return 1;
    }
    TAppHnd app = API_Create_APPHnd("Client1", "Client1 app");
    if (!app) {
        cerr << "Failed to create application." << endl;
        API_FreeLibrary();
        return 1;
    }

    API_Reg_Call(app, "client1_echo", "Echo from client1", nullptr, Client1EchoCallback);
    cout << "Registered client1_echo" << endl;

    API_Reset_Prepare();
    API_Prepare_Client("ipc:demo_service", app);

    cout << "Connecting to service..." << endl;
    if (API_Prepare_Done() != 1) {
        cerr << "Prepare_Done failed." << endl;
        // Note: API_Get_Status() is no longer available; check console output for errors.
        API_Free_APPHnd(app);
        API_shutdown();
        API_FreeLibrary();
        return 1;
    }
    cout << "Connected to service." << endl;
    cout << "Available commands:" << endl;
    cout << "  exit                         - quit" << endl;
    cout << "  call service add <a> <b>     - call Service.add" << endl;
    cout << "  call service echo <msg>      - call Service.echo" << endl;
    cout << "  call service get_time        - call Service.get_time" << endl;
    cout << "  call client2 reverse <msg>   - call Client2.reverse" << endl;

    // 启动控制台线程
    thread consoleThread(ConsoleThread);

    // 主循环
    while (!g_bExit) {
        string cmd;
        {
            lock_guard<mutex> lock(g_cmdMutex);
            if (!g_cmdQueue.empty()) {
                cmd = g_cmdQueue.front();
                g_cmdQueue.pop();
            }
        }
        if (!cmd.empty()) {
            ProcessCommand(cmd, app);
        }

        // Status messages are now printed to console automatically.
        this_thread::sleep_for(chrono::milliseconds(100));
    }

    if (consoleThread.joinable())
        consoleThread.join();

    cout << "Client1 shutting down..." << endl;
    API_Exit_MainThread();
    API_Free_APPHnd(app);
    API_shutdown();
    API_FreeLibrary();
    return 0;
}