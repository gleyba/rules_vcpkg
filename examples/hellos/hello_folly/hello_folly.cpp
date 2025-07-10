#include <iostream>

#include <folly/Conv.h>
#include <folly/FBString.h>

int main(int argc, char *argv[]) {
  auto s = folly::to<folly::fbstring>("Hello, Folly!");

  std::cout << s << std::endl;

  return 0;
}
