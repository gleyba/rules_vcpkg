def _is_whitespace(ch):
    return ch in [" ", "\n", "\r"]

def _parse_tokens(body):
    body_len = len(body)
    tokens = []

    def add_token(token):
        if token[0] == '"' and token[-1] == '"':
            tokens.append(token[1:-1])
        else:
            tokens.append(token)

    start_token_pos = None
    for idx in range(body_len):
        if _is_whitespace(body[idx]):
            if start_token_pos == None:
                continue

            add_token(body[start_token_pos:idx])
            start_token_pos = None
            continue

        if start_token_pos != None:
            continue

        start_token_pos = idx

    if start_token_pos:
        add_token(body[start_token_pos:body_len])

    return tokens, None

def _parse_func_args(body, mnemo, *args):
    result = {}

    tokens, err = _parse_tokens(body)
    if err:
        return None, err

    found_arg = None
    for token in tokens:
        if found_arg:
            result[found_arg] = token
            found_arg = None
            continue

        if token in args:
            found_arg = token
            continue

    if len(result) < len(args):
        return None, "Parsing %s: can't parse all args: '%s' in tokens: '%s'" % (
            mnemo,
            args,
            tokens,
        )

    return result, None

_STRING_TYPE = type("foo")
_TUPLE_TYPE = type((42, "bar"))

def _match_state(name):
    data = {
        "name": name,
        "name_len": len(name),
    }

    def clean_state(data):
        data["match_pos"] = None

    clean_state(data)

    def process_next_char(data, ch):
        pos = data["match_pos"]
        if pos == None:
            pos = 0
        else:
            pos += 1

        if data["name"][pos] != ch:
            clean_state(data)
            return

        data["match_pos"] = pos

    return struct(
        data = data,
        clean_state = lambda: clean_state(data),
        is_matched = lambda: data["match_pos"] == data["name_len"] - 1,
        is_started = lambda: data["match_pos"] != None,
        process_next_char = lambda ch: process_next_char(data, ch),
    )

def _create_func_tracking(func, mnemo):
    func_type = type(func)
    if func_type == _STRING_TYPE:
        name = func
        parse_func = _parse_tokens
    elif func_type == _TUPLE_TYPE:
        name = func[0]
        parse_func = lambda body: _parse_func_args(
            body,
            "%s (function - %s)" % (mnemo, func[0]),
            *func[1]
        )
    else:
        return None, "Unknown function type: %s" % func_type

    match_state = _match_state(name)

    def process_next_char(match_state, ch):
        if match_state.is_matched():
            if ch == "(":
                return True
            elif not _is_whitespace(ch):
                match_state.clean_state()
        else:
            match_state.process_next_char(ch)

        return False

    return struct(
        name = name,
        parse = parse_func,
        process_next_char = lambda ch: process_next_char(match_state, ch),
        clean_state = lambda: match_state.clean_state(),
    ), None

def _create_func_trackings(funcs_defs, mnemo):
    funcs_trackings = []
    errors = []

    for func in funcs_defs:
        func_tracking, err = _create_func_tracking(func, mnemo)
        if err:
            errors.append(err)
        if func_tracking:
            funcs_trackings.append(func_tracking)

    return sorted(
        funcs_trackings,
        key = lambda x: len(x.name),
        reverse = True,
    ), errors

def _create_tracking(funcs_defs, mnemo):
    funcs_trackings, errors = _create_func_trackings(funcs_defs, mnemo)
    if not funcs_trackings:
        return None, errors

    def clean_state(funcs_trackings):
        for func_tracking in funcs_trackings:
            func_tracking.clean_state()

    def process_next_char(funcs_trackings, ch):
        for func_tracking in funcs_trackings:
            if not func_tracking.process_next_char(ch):
                continue

            clean_state(funcs_trackings)
            return func_tracking

        return None

    return struct(
        process_next_char = lambda ch: process_next_char(funcs_trackings, ch),
    ), errors

def parse_calls(data, mnemo, funcs_defs):
    results = []
    data_len = len(data)

    tracking, errors = _create_tracking(funcs_defs, mnemo)
    if not tracking:
        return None, errors

    func_started = None
    for idx in range(data_len):
        if func_started:
            ch = data[idx]
            if ch != ")":
                continue

            result, err = func_started.func.parse(data[func_started.pos:idx])
            if err:
                errors.append(err)
            if result:
                results.append((func_started.func.name, result))
            func_started = None
        else:
            func_to_start = tracking.process_next_char(data[idx])
            if func_to_start == None:
                continue

            func_started = struct(
                func = func_to_start,
                pos = idx + 1,
            )

    if func_started:
        errors.append("Parsing %s: can't finish parsing func - %s" % (mnemo, mnemo))

    return results, errors

def _substitute_vars(result, sunstitutions):
    for key, value in sunstitutions.items():
        result = result.replace("${%s}" % key, value)

    err = None
    if "${" in result:
        err = "Not all substitutions unwrapped: %s" % result

    return result, err

def unwrap_func_args(func_parse_results, sunstitutions = {}):
    results = []
    errors = []
    for result in func_parse_results:
        if result[0] == "set":
            if len(result[1]) != 2:
                errors.append("Set doesn't have 2 arguments: %s" % result[1])
                continue

            value, err = _substitute_vars(result[1][1], sunstitutions)
            if err:
                errors.append(err)
            if value:
                sunstitutions[result[1][0]] = value
        else:
            result_args = {}
            for key, value in result[1].items():
                value, err = _substitute_vars(value, sunstitutions)
                if err:
                    errors.append(err)
                if value:
                    result_args[key] = value

            results.append((result[0], result_args))

    return results, errors
