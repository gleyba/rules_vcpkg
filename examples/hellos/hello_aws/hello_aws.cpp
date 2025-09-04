#include <iostream>

#include <aws/core/Region.h>

int main(int argc, char *argv[]) {
  std::cout 
    << "Hello, "
    << Aws::Region::ComputeSignerRegion("aws-global")
    << "!"
    << std::endl;

  return 0;
}