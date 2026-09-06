#ifndef TIME_UTIL_H
#define TIME_UTIL_H

#include <Arduino.h>
#include <time.h>

void ntpInit();
uint64_t epochMillis();
bool timeSynced();

#endif