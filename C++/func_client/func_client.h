/**
 * @file func_client.h
 * @brief Client wrapper functions that encapsulate remote API calls
 *        as local C++ functions.
 *
 * All functions internally use API_Call() to communicate with the
 * "FuncService" application. Default timeout is 5000 ms; can be changed
 * via set_default_timeout().
 */

#pragma once

#include <string>
#include <vector>

 // Set global default timeout (milliseconds)
void set_default_timeout(int timeout_ms);

// Business function declarations
int32_t  func_add(int32_t a, int32_t b);
int32_t  func_subtract(int32_t a, int32_t b);
int32_t  func_multiply(int32_t a, int32_t b);
double   func_divide(int32_t a, int32_t b);
std::string func_to_upper(const std::string& s);
std::string func_to_lower(const std::string& s);
std::string func_reverse(const std::string& s);
std::string func_get_time();
int32_t  func_get_random(int32_t min, int32_t max);
std::string func_echo(const std::string& s);
int32_t  func_sum_array(const std::vector<int32_t>& arr);
std::string func_concat_strings(const std::vector<std::string>& arr);