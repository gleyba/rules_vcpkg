def _join(values, red):
    result = []
    for value in values:
        result.append("{red}WARN:{nc} {msg}".format(red = red, msg = value, nc = "\033[0m"))
    return "\n".join(result)

L = struct(
    warn = lambda *msgs: print("\n%s" % _join(msgs, "\033[0;31m")),  # buildifier: disable=print
)
