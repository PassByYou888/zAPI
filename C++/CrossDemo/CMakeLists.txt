cmake_minimum_required(VERSION 3.10)
project(CrossDemo VERSION 1.0)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# 可执行文件 – 使用父目录的 API_HubTool.c
add_executable(CrossService CrossService.cpp ../API_HubTool.c)
add_executable(CrossNode    CrossNode.cpp    ../API_HubTool.c)
add_executable(CrossCall    CrossCall.cpp    ../API_HubTool.c)

# 包含当前目录和父目录（以找到 API_HubTool.h / .hpp）
target_include_directories(CrossService PRIVATE . ..)
target_include_directories(CrossNode    PRIVATE . ..)
target_include_directories(CrossCall    PRIVATE . ..)

# 链接系统库（Windows: kernel32, Linux/macOS: dl）
if(WIN32)
    target_link_libraries(CrossService kernel32)
    target_link_libraries(CrossNode    kernel32)
    target_link_libraries(CrossCall    kernel32)
else()
    target_link_libraries(CrossService dl)
    target_link_libraries(CrossNode    dl)
    target_link_libraries(CrossCall    dl)
endif()