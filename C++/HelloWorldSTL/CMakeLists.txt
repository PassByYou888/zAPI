cmake_minimum_required(VERSION 3.10)
project(HelloWorldSTL)

add_executable(HelloWorldSTL
    HelloWorldSTL.cpp
    ../API_HubTool.c
    ../API_HubTool.h
    ../API_HubTool.hpp
)

target_include_directories(HelloWorldSTL PRIVATE ..)

if(WIN32)
    target_link_libraries(HelloWorldSTL kernel32)
endif()