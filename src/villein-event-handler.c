#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>

#include <errno.h>

#include <string.h>

#include <sys/types.h>

#include <fcntl.h>
#include <sys/select.h>

#include <netdb.h>
#include <sys/socket.h>
#include <arpa/inet.h>
#include <netinet/in.h>

extern char **environ;

int
main(int argc, const char *argv[])
{
  if (argc < 2) {
    fprintf(stderr, "usage: $0 host port\n");
    return 2;
  }

  const char *hostname = argv[1];
  const char *port = argv[2];
  int err;
  struct addrinfo hints, *host0, *host;

  memset(&hints, 0, sizeof(hints));
  hints.ai_socktype = SOCK_STREAM;
  hints.ai_family = PF_UNSPEC;

  if ((err = getaddrinfo(hostname, port, &hints, &host0)) != 0) {
    fprintf(stderr, "%s %s -- ", hostname, port);
    fprintf(stderr, "oops: getaddrinfo error: %s\n", gai_strerror(err));
    return 1;
  }

  int sock;
  for(host = host0; host != NULL; host = host->ai_next) {
    if ((sock = socket(host->ai_family, host->ai_socktype, host->ai_protocol)) < 0) {
      continue;
    }

    if (connect(sock, host->ai_addr, host->ai_addrlen) != 0) {
      close(sock);
      continue;
    }

    break;
  }

  if (host == NULL) {
    fprintf(stderr, "failed to connect host");
    freeaddrinfo(host);
    return 1;
  }

  char **env = environ;

  while (*env) {
    write(sock, *env, strlen(*env) + 1); /* \0 */
    env++;
  }
  write(sock, "\0", 1);

  /* pass-thru stdin */

  unsigned int flags = fcntl(0, F_GETFL);
  fcntl(0, F_SETFL, flags | O_NONBLOCK);

  fd_set rfds;
  int retval;

  FD_ZERO(&rfds);
  FD_SET(0, &rfds);

  char *buf;
  buf = malloc(2048);
  memset(buf, 0, sizeof(*buf));

  while (1) {
    ssize_t count = 0;
    retval = select(1, &rfds, NULL, NULL, NULL);

    if (retval == -1) {
      perror("oops: stdin select");
      return 1;
    }

    errno = 0;
    count = read(0, buf, 2048);

    if (errno == EAGAIN || errno == EWOULDBLOCK) continue;
    if (errno != 0) {
      perror("oops: read stdin");
      return 1;
    }
    if (count == 0) break;

    write(sock, buf, count);
  }

  shutdown(sock, 1); /* close_write */

  if (getenv("SERF_EVENT") != NULL && strcmp(getenv("SERF_EVENT"), "query") == 0) {
    flags = fcntl(sock, F_GETFL);
    fcntl(sock, F_SETFL, flags | O_NONBLOCK);

    fd_set rss;
    FD_ZERO(&rss);
    FD_SET(sock, &rss);

    while (1) {
      ssize_t count = 0;
      retval = select(sock + 1, &rss, NULL, NULL, NULL);

      if (retval == -1) {
        perror("oops: sock select");
        return 1;
      }

      errno = 0;
      count = recv(sock, buf, 2048, 0);

      if (errno == EAGAIN || errno == EWOULDBLOCK) continue;
      if (errno != 0) {
        perror("oops: sock stdin");
        return 1;
      }
      if (count == 0) break;

      write(1, buf, count);
    }
  }

  free(buf);
  close(sock);
  freeaddrinfo(host);

  return 0;
}
