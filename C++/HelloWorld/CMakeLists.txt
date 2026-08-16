cmake_minimum_required(VERSION 3.10)
project(HelloWorld)

add_executable(HelloWorld
    HelloWorld.cpp
    ../API_HubTool.c
    ../API_HubTool.h
)

target_include_directories(HelloWorld PRIVATE ..)

if(WIN32)
    target_link_libraries(HelloWorld kernel32)
endif()