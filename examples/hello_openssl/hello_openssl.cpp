#include <stdio.h>
#include <openssl/ssl.h>
#include <openssl/bio.h>

int main(int argc, char *argv[]) {

  BIO *bio_stdout;

  bio_stdout = BIO_new_fp(stdout, BIO_NOCLOSE);

  BIO_printf(bio_stdout, "Hello, OpenSSL!\n");

  BIO_free_all(bio_stdout);  

  return 0;
}
