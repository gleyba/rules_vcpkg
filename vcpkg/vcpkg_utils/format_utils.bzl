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

def format_inner_list(deps, pattern = "%s"):
    if not deps:
        return ""

    result = [
        "       \"%s\"," % (pattern % dep)
        for dep in deps
    ]

    return "\n" + "\n".join(result) + "\n    "

def format_inner_dict(deps):
    if not deps:
        return ""

    return format_inner_list([
        "%s\": \"%s" % (k, v)
        for k, v in deps.items()
    ])
