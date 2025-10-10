// test.cpp
#include <unistd.h>
#include <cstdlib>

void hot() {
  volatile long sum = 0;
  for (long i = 0; i < 500'000'000; ++i) sum += i;  // ~1.5s
  usleep(100'000);  // 0.1s pause
}

int main() {
  // INTENTIONAL LEAK: 4000 bytes
  int* leak = new int[1000];
  (void)leak;  // silence unused warning

  for (int i = 0; i < 5; ++i) {
    hot();
  }
  return 0;
}