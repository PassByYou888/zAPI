cmake_minimum_required(VERSION 3.10)
project(FuncService)

add_executable(FuncService
    func_service.cpp
    ../API_HubTool.c
    ../API_HubTool.h
)
target_include_directories(FuncService PRIVATE ..)

if(WIN32)
    target_link_libraries(FuncService kernel32)
else()
    target_link_libraries(FuncService dl)
endif()
