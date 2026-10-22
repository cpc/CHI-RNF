
/*
*/

#define N 30
#define CORECOUNT 1

int done = 0;
int results[N];
int a12 = 0;
int a22 = 0;
int a32 = 0;
int a42 = 0;
int a52 = 0;
int a62 = 0;
int a72 = 0;
int a82 = 0;
int a1 = 0;
int a2 = 0;
int a3 = 0;
int a4 = 0;
int a5 = 0;
int a6 = 0;
int a7 = 0;
int a8 = 0;
int retval = 0;
int n;
int n2;
int loadaddr;
int done0 = 0;


int
main(void)
{
  // just to do load request
  n2 = loadaddr;

  n = 1234;
  n2 = n;

  
  a1 = 1111;
  a2 = 2222;
  a3 = 3333;
  a4 = 4444;
  a5 = 5555;
  a6 = 6666;
  a7 = 7777;
  a8 = 8888;

  //n2 = n;
  a12 = a1;
  a22 = a2;
  a32 = a3;
  a42 = a4;
  a52 = a5;
  a62 = a6;
  a72 = a7;
  a82 = a8;
  

  for( n=0; n<N; n=n+1){

    results[n] = N-n;

  }

  done++;
  done0 = 1;
  return 0;
}
