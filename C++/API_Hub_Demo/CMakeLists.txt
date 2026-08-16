cmake_minimum_required(VERSION 3.10)
project(API_Hub_Demo)

add_executable(API_Hub_Demo
    VC_API_Hub_Demo.cpp
    ../API_HubTool.c
    ../API_HubTool.h
)

target_include_directories(API_Hub_Demo PRIVATE ..)

if(WIN32)
    target_link_libraries(API_Hub_Demo kernel32)
endif()
