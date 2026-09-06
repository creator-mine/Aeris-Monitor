#ifndef TIME_UTIL_H
#define TIME_UTIL_H

#include <Arduino.h>
#include <time.h>

void ntpInit();
void ntpEnsureSynced();
uint64_t epochMillis();
bool timeSynced();

#endif