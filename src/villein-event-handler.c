#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>

#include <errno.h>

#include <string.h>

#include <sys/types.h>
#include <sys/stat.h>

#include <fcntl.h>
#include <sys/select.h>

#include <netdb.h>
#include <sys/socket.h>
#include <arpa/inet.h>
#include <netinet/in.h>

#define BUFSIZE 2048

typedef struct {
  const char *hostname;
  const char *port;
  struct addrinfo *host_head;
  int sock;
} Mission;

extern char **environ;

void
cleanup(Mission *mission)
{
  if (mission->host_head != NULL)
    freeaddrinfo(mission->host_head);
  if (mission->sock != -1)
    close(mission->sock);
}

int
is_query_p()
{
  return getenv("SERF_EVENT") != NULL && strcmp(getenv("SERF_EVENT"), "query") == 0;
}

void
enable_nonblock(Mission *mission, int fd)
{
  errno = 0;
  unsigned int flags = fcntl(fd, F_GETFL);

  if (errno != 0) {
    perror("oops: F_GETCL");
    exit(1);
  }

  if (fcntl(fd, F_SETFL, flags | O_NONBLOCK) < 0) {
    perror("oops: F_SETCL");
    exit(1);
  }
}

void
connect_villein(Mission *mission)
{
  int err;
  struct addrinfo hints, *host;

  memset(&hints, 0, sizeof(hints));
  hints.ai_socktype = SOCK_STREAM;
  hints.ai_family = PF_UNSPEC;

  if ((err = getaddrinfo(mission->hostname, mission->port, &hints, &mission->host_head)) != 0) {
    fprintf(stderr, "oops: getaddrinfo(%s, %s) error: %s\n", mission->hostname, mission->port, gai_strerror(err));
    exit(1);
  }

  for(host = mission->host_head; host != NULL; host = host->ai_next) {
    if ((mission->sock = socket(host->ai_family, host->ai_socktype, host->ai_protocol)) < 0) {
      continue;
    }

    if (connect(mission->sock, host->ai_addr, host->ai_addrlen) != 0) {
      close(mission->sock);
      continue;
    }

    break;
  }

  if (host == NULL) {
    fprintf(stderr, "failed to connect host");
    cleanup(mission);
    exit(1);
  }
}

void
report_environ(Mission *mission)
{
  char **env = environ;

  while (*env) {
    write(mission->sock, *env, strlen(*env) + 1); /* \0 */
    env++;
  }
  write(mission->sock, "\0", 1);
}

void
copy_stream(Mission *mission, int from_fd, int to_fd)
{
  int maxfd = from_fd < to_fd ? to_fd : from_fd;
  int retval;
  fd_set rfds;
  char *buf;
  buf = malloc(BUFSIZE);

  FD_ZERO(&rfds);
  FD_SET(from_fd, &rfds);

  struct stat from_fdstat;
  fstat(from_fd, &from_fdstat);


  while (1) {
    ssize_t count = 0;
    retval = select(maxfd + 1, &rfds, NULL, NULL, NULL);

    if (retval == -1) {
      perror("oops: copy select");
      free(buf);
      cleanup(mission); exit(1);
    }

    errno = 0;

    if (S_ISSOCK(from_fdstat.st_mode)) {
      count = recv(from_fd, buf, BUFSIZE, 0);
    }
    else {
      count = read(from_fd, buf, BUFSIZE);
    }

    if (errno == EAGAIN || errno == EWOULDBLOCK) continue;
    if (errno != 0) {
      perror("oops: copy read");
      free(buf);
      cleanup(mission); exit(1);
    }
    if (count == 0) break;

    write(to_fd, buf, count);
  }
}

int
main(int argc, const char *argv[])
{
  if (argc < 3) {
    fprintf(stderr, "usage: $0 host port\n");
    return 2;
  }

  Mission mission;
  memset(&mission, 0, sizeof(mission));

  mission.hostname = argv[1];
  mission.port = argv[2];
  mission.sock = -1;

  connect_villein(&mission);
  report_environ(&mission);

  enable_nonblock(&mission, 0);
  copy_stream(&mission, 0, mission.sock);
  shutdown(mission.sock, 1); /* close_write */

  if (is_query_p()) {
    enable_nonblock(&mission, mission.sock);
    copy_stream(&mission, mission.sock, 1);
  }

  cleanup(&mission);

  return 0;
}
