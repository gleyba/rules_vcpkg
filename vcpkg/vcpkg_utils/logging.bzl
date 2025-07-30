def _warn(msg):
    print("{red}WARN:{nc} {msg}".format(red = "\033[0;31m", msg = msg, nc = "\033[0m"))

L = struct(
    warn = _warn,
)
