cmake_minimum_required(VERSION 3.10)
project(API_Hub_All)

set(CMAKE_RUNTIME_OUTPUT_DIRECTORY "${CMAKE_SOURCE_DIR}/../Binary")

foreach(CONFIG DEBUG RELEASE MINSIZEREL RELWITHDEBINFO)
    set(CMAKE_RUNTIME_OUTPUT_DIRECTORY_${CONFIG} "${CMAKE_SOURCE_DIR}/../Binary")
endforeach()

add_subdirectory(API_Hub_Demo)
add_subdirectory(HelloWorld)
add_subdirectory(HelloWorldSTL)
add_subdirectory(service)
add_subdirectory(client1)
add_subdirectory(client2)
add_subdirectory(func_service)
add_subdirectory(func_client)
add_subdirectory(CrossDemo)
