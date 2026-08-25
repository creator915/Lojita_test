#define _GNU_SOURCE
#include <errno.h>
#include <spawn.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>

static void record_attempt(const char *name) {
  const char *path = getenv("CCZ_NOEXEC_LOG");
  FILE *handle;
  if (path == NULL) return;
  handle = fopen(path, "a");
  if (handle == NULL) return;
  fprintf(handle, "%s\n", name);
  fclose(handle);
}

int execve(const char *path, char *const argv[], char *const envp[]) {
  (void)path; (void)argv; (void)envp;
  record_attempt("execve"); errno = EPERM; return -1;
}

int execv(const char *path, char *const argv[]) {
  (void)path; (void)argv;
  record_attempt("execv"); errno = EPERM; return -1;
}

int execvp(const char *file, char *const argv[]) {
  (void)file; (void)argv;
  record_attempt("execvp"); errno = EPERM; return -1;
}

int execvpe(const char *file, char *const argv[], char *const envp[]) {
  (void)file; (void)argv; (void)envp;
  record_attempt("execvpe"); errno = EPERM; return -1;
}

int posix_spawn(pid_t *pid, const char *path,
                const posix_spawn_file_actions_t *actions,
                const posix_spawnattr_t *attributes,
                char *const argv[], char *const envp[]) {
  (void)pid; (void)path; (void)actions; (void)attributes; (void)argv; (void)envp;
  record_attempt("posix_spawn"); return EPERM;
}

int posix_spawnp(pid_t *pid, const char *file,
                 const posix_spawn_file_actions_t *actions,
                 const posix_spawnattr_t *attributes,
                 char *const argv[], char *const envp[]) {
  (void)pid; (void)file; (void)actions; (void)attributes; (void)argv; (void)envp;
  record_attempt("posix_spawnp"); return EPERM;
}

int system(const char *command) {
  (void)command; record_attempt("system"); errno = EPERM; return -1;
}

FILE *popen(const char *command, const char *type) {
  (void)command; (void)type; record_attempt("popen"); errno = EPERM; return NULL;
}

pid_t fork(void) {
  record_attempt("fork"); errno = EPERM; return -1;
}

pid_t vfork(void) {
  record_attempt("vfork"); errno = EPERM; return -1;
}
