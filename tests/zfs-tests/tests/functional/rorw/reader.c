// A reader for testing that upgrading a read-only fs to a read/write fs does
// not close the file or otherwise cause subsequent reads to error out.
//
// This program expects one argument; a file (of nonzero length) it can open
// for repeated reads.  It opens the file and re-reads the first byte over
// and over until it receives (any) input on STDIN, at which point it exits
// and returns 0.
//
// If at any point a read fails, it immediately exits and returns 2.
//
// A return of 1 indicates an unrelated error; something wrong in poll()
// (which is used to monitor STDIN) or the designated read file being
// unavailable.

#include <stdio.h>
#include <unistd.h>
#include <errno.h>
#include <string.h>
#include <sys/poll.h>

int main(int argc, char **argv)
{
  if(argc != 2)
    {
      printf("Expected one argument: a file to read.\n");
      return 1;
    }

  char *path = argv[1];
  pid_t pid  = getpid();
  FILE *f;
  int   done = 0;

  if(!(f = fopen(path, "r")))
    {
      printf("fopen(\"%s\", \"r\") failed: %s\n", path, strerror(errno));
      return 1;
    }

  printf("PID:  %u\n", pid);
  printf("Path: %s\n", path);

  // Rather than polling stdin, we could watch SIGUSR1 or something...

  struct pollfd input_interrupt =
    {
      .fd = 0,          // STDIN
      .events = POLLIN, // Look for input.
    };

  while(!done)
    {
      unsigned char scratch;

      switch(poll(&input_interrupt, 1, 0))
        {
        case 0: // No input.
          break;

        case 1:
          done = 1;
          break;

        case 2: // Error.
          return 1;
        }

      if(1 != fread(&scratch, 1, 1, f)) // Try to read a byte.
        {
          // Should we ignore EAGAIN or EINTR here?
          
          printf("Error: %d\n", ferror(f));
          return 2;
        }

      rewind(f);
      usleep(250); // Don't spin too hard; attempt to read at roughly 4khz.
    }

  fclose(f);

  return 0;
}
