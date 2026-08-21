#include "keyboard_layout/hypr_ipc.h"
#include "keyboard_layout/layout_memory.h"

#include <errno.h>
#include <fcntl.h>
#include <poll.h>
#include <signal.h>
#include <stddef.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <unistd.h>

enum { DEFAULT_LAYOUT = 0, EVENT_SIZE = 4096 };

struct app {
  struct hypr_ipc ipc;
  struct layout_memory memory;
  int latin;
};

static volatile sig_atomic_t stop_requested;

static void request_stop(int signal_number) {
  (void)signal_number;
  stop_requested = 1;
}

static int switch_to(struct app *app, int layout, int assign) {
  printf("restore:%d\n", layout);
  fflush(stdout);
  if (hypr_ipc_switch_layout(&app->ipc, layout) != 0) {
    fprintf(stderr, "keyboard-layoutd: could not restore layout %d\n", layout);
    return -1;
  }
  if (assign && layout_memory_assign(&app->memory, layout) != 0) {
    fprintf(stderr, "keyboard-layoutd: could not remember layout\n");
    return -1;
  }
  return 0;
}

static int focused_is_terminal(struct app *app) {
  uint64_t window = 0;
  int is_terminal = 0;
  if (hypr_ipc_active_window_info(&app->ipc, &window, &is_terminal) != 0)
    return 0;
  return is_terminal;
}

static void emit_ready(void) {
  printf("ready\n");
  fflush(stdout);
}

static void sync_state(struct app *app) {
  uint64_t window = 0;
  int is_terminal = 0;
  int layout = -1;
  int have_window =
      hypr_ipc_active_window_info(&app->ipc, &window, &is_terminal) == 0;
  hypr_ipc_current_layout(&app->ipc, &layout);
  if (layout_memory_reset(&app->memory, have_window ? window : 0, layout) != 0)
    fprintf(stderr, "keyboard-layoutd: could not initialize memory\n");
  if (app->latin && have_window && is_terminal && layout > 0)
    switch_to(app, 0, 1);
  emit_ready();
}

static void focus_window(struct app *app, const char *data) {
  uint64_t window = 0;
  int target = -1;
  if (layout_memory_parse_window(data, &window) != 0)
    return;

  int result = layout_memory_focus(&app->memory, window, &target);
  if (result < 0) {
    fprintf(stderr, "keyboard-layoutd: could not remember layout\n");
    return;
  }

  if (app->memory.overlay_held) {
    if (result > 0 && layout_memory_assign(&app->memory, target) != 0)
      fprintf(stderr, "keyboard-layoutd: could not remember layout\n");
    return;
  }

  if (app->latin && focused_is_terminal(app)) {
    if (app->memory.active_layout != 0 || result > 0)
      switch_to(app, 0, 1);
    return;
  }

  if (result > 0)
    switch_to(app, target, 1);
}

static void observe_layout(struct app *app, char *data) {
  char *separator = strchr(data, ',');
  if (separator == NULL || separator == data)
    return;
  *separator = '\0';
  if (!hypr_keyboard_is_typing(data))
    return;

  int layout = -1;
  if (hypr_ipc_device_layout(&app->ipc, data, &layout) == 0 &&
      layout_memory_observe(&app->memory, layout) != 0)
    fprintf(stderr, "keyboard-layoutd: could not remember layout\n");
}

static void handle_event(struct app *app, char *line) {
  char *separator = strstr(line, ">>");
  if (separator == NULL)
    return;
  *separator = '\0';
  char *data = separator + 2;

  if (strcmp(line, "activewindowv2") == 0) {
    focus_window(app, data);
  } else if (strcmp(line, "activelayout") == 0) {
    observe_layout(app, data);
  } else if (strcmp(line, "closewindow") == 0) {
    uint64_t window = 0;
    if (layout_memory_parse_window(data, &window) == 0)
      layout_memory_close(&app->memory, window);
  } else if (strcmp(line, "configreloaded") == 0) {
    sync_state(app);
  }
}

static void handle_command(struct app *app, const char *command) {
  int target = -1;
  int result;
  if (!app->latin || command == NULL || command[0] == '\0')
    return;

  if (strcmp(command, "latin-on") == 0) {
    result = layout_memory_overlay_enter(&app->memory, &target);
    if (result > 0)
      switch_to(app, target, 0);
    return;
  }

  if (strcmp(command, "latin-off") != 0)
    return;

  result = layout_memory_overlay_leave(&app->memory, &target);
  if (app->latin && focused_is_terminal(app)) {
    if (app->memory.active_layout != 0 || result > 0)
      switch_to(app, 0, 1);
    return;
  }
  if (result > 0)
    switch_to(app, target, 0);
}

static int set_nonblock(int fd) {
  int flags = fcntl(fd, F_GETFL, 0);
  if (flags < 0)
    return -1;
  return fcntl(fd, F_SETFL, flags | O_NONBLOCK);
}

static void read_stdin_commands(struct app *app, char *line, size_t *length,
                                int *discarding) {
  char chunk[EVENT_SIZE];
  ssize_t count = read(STDIN_FILENO, chunk, sizeof(chunk));
  if (count < 0 && errno == EINTR)
    return;
  if (count <= 0)
    return;

  for (ssize_t i = 0; i < count; i++) {
    if (chunk[i] == '\n') {
      if (!*discarding) {
        line[*length] = '\0';
        handle_command(app, line);
      }
      *length = 0;
      *discarding = 0;
    } else if (!*discarding && *length < EVENT_SIZE - 1) {
      line[(*length)++] = chunk[i];
    } else {
      *discarding = 1;
    }
  }
}

static void read_events(int socket_fd, struct app *app) {
  char chunk[EVENT_SIZE];
  char line[EVENT_SIZE];
  char command[EVENT_SIZE];
  size_t length = 0;
  size_t command_length = 0;
  int discarding = 0;
  int command_discarding = 0;

  while (!stop_requested) {
    struct pollfd fds[2] = {
        {.fd = socket_fd, .events = POLLIN},
        {.fd = STDIN_FILENO, .events = POLLIN},
    };
    int ready = poll(fds, app->latin ? 2 : 1, -1);
    if (ready < 0 && errno == EINTR)
      continue;
    if (ready <= 0)
      return;

    if (fds[0].revents & (POLLERR | POLLHUP | POLLNVAL))
      return;
    if (fds[0].revents & POLLIN) {
      ssize_t count = read(socket_fd, chunk, sizeof(chunk));
      if (count < 0 && errno == EINTR)
        continue;
      if (count <= 0)
        return;

      for (ssize_t i = 0; i < count; i++) {
        if (chunk[i] == '\n') {
          if (!discarding) {
            line[length] = '\0';
            handle_event(app, line);
          }
          length = 0;
          discarding = 0;
        } else if (!discarding && length < sizeof(line) - 1) {
          line[length++] = chunk[i];
        } else {
          discarding = 1;
        }
      }
    }

    if (app->latin && (fds[1].revents & POLLIN))
      read_stdin_commands(app, command, &command_length, &command_discarding);
  }
}

static void reconnect_delay(void) {
  struct timespec delay = {.tv_sec = 1};
  while (!stop_requested && nanosleep(&delay, &delay) != 0 && errno == EINTR) {
  }
}

static int parse_args(int argc, char **argv) {
  int latin = 0;
  for (int i = 1; i < argc; i++) {
    if (strcmp(argv[i], "--latin") == 0)
      latin = 1;
  }
  return latin;
}

int main(int argc, char **argv) {
  struct sigaction action = {.sa_handler = request_stop};
  sigemptyset(&action.sa_mask);
  sigaction(SIGINT, &action, NULL);
  sigaction(SIGTERM, &action, NULL);

  struct app app = {.latin = parse_args(argc, argv)};
  if (hypr_ipc_init(&app.ipc, getenv("XDG_RUNTIME_DIR"),
                    getenv("HYPRLAND_INSTANCE_SIGNATURE")) != 0) {
    fprintf(stderr, "keyboard-layoutd: invalid Hyprland environment\n");
    return EXIT_FAILURE;
  }
  if (app.latin && set_nonblock(STDIN_FILENO) != 0) {
    fprintf(stderr, "keyboard-layoutd: could not read commands\n");
    return EXIT_FAILURE;
  }

  layout_memory_init(&app.memory, DEFAULT_LAYOUT);
  while (!stop_requested) {
    int socket_fd = hypr_ipc_connect_events(&app.ipc);
    if (socket_fd >= 0) {
      sync_state(&app);
      read_events(socket_fd, &app);
      close(socket_fd);
    }
    if (!stop_requested)
      reconnect_delay();
  }
  layout_memory_destroy(&app.memory);
  return EXIT_SUCCESS;
}
