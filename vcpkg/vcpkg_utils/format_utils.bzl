def dict_to_kv_list(d):
    if not d:
        return []

    return [
        "%s=%s" % (k, v)
        for k, v in d.items()
    ]

def add_or_extend_list_in_dict(m, key, values):
    if not values:
        return

    if key in m:
        m[key] += values
    else:
        m[key] = values

def add_or_extend_dict_to_list_in_dict(m, key, values):
    if not values:
        return

    if key in m:
        for inner_key, inner_values in values.items():
            add_or_extend_list_in_dict(
                m[key],
                inner_key,
                inner_values,
            )
    else:
        m[key] = values

def format_inner_list(
        deps,
        pattern = "\"%s\"",
        open_br = "[",
        close_br = "]",
        indent = 1):
    if not deps:
        return "%s%s" % (open_br, close_br)

    result = [
        "%s%s," % (
            "    " * int(indent + 1),
            pattern % dep,
        )
        for dep in deps
    ]

    return ("%s\n" % open_br) + "\n".join(result) + ("\n%s%s" % ("    " * int(indent), close_br))

def format_inner_dict(deps, pattern = "\"%s\"", indent = 1):
    if not deps:
        return "{}"

    return format_inner_list(
        deps = [
            "\"%s\": %s" % (k, pattern % v)
            for k, v in deps.items()
        ],
        pattern = "%s",
        open_br = "{",
        close_br = "}",
        indent = indent,
    )

def format_inner_dict_with_value_lists(deps, pattern = "\"%s\"", indent = 1):
    return format_inner_dict(
        deps = {
            key: format_inner_list(
                values,
                pattern = pattern,
                indent = indent + 1.,
            )
            for key, values in deps.items()
        },
        pattern = "%s",
        indent = indent,
    )
