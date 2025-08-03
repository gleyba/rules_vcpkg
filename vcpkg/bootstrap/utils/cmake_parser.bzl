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

def _to_dict(**kwargs):
    return kwargs

def _new_state(const_data = {}, mutable_data = {}):
    def const_getter(key):
        return lambda: const_data[key]

    def mutable_getter(key):
        return lambda: mutable_data[key]

    def mutable_setter(key):
        return lambda value: mutable_data.update({key: value})

    methods = {}
    for key in const_data:
        methods[key] = const_getter(key)

    for key in mutable_data:
        methods[key] = mutable_getter(key)
        methods["set_%s" % key] = mutable_setter(key)

    return struct(
        const = const_data,
        mutable = mutable_data,
        **methods
    )

_STRING_TYPE = type("foo")
_TUPLE_TYPE = type((42, "bar"))

def _match_state(name):
    state = _new_state(
        const_data = _to_dict(
            name = name,
            name_len = len(name),
        ),
        mutable_data = _to_dict(
            match_pos = None,
        ),
    )

    def clean_state(state):
        state.set_match_pos(None)

    def process_next_char(state, ch):
        pos = state.match_pos()
        if pos == None:
            pos = 0
        else:
            pos += 1

        if state.name()[pos] != ch:
            state.set_match_pos(None)
            return

        state.set_match_pos(pos)

    def is_matched(state):
        return state.match_pos() == state.name_len() - 1

    return struct(
        state = state,
        clean_state = lambda: state.set_match_pos(None),
        is_matched = lambda: state.match_pos() == state.name_len() - 1,
        is_started = lambda: state.match_pos() != None,
        process_next_char = lambda ch: process_next_char(state, ch),
    )

def _create_func_tracking(func_def, mnemo):
    match_state = _match_state(func_def.name)

    def process_next_char(match_state, ch):
        if match_state.is_matched():
            if ch == "(":
                return True
            elif not _is_whitespace(ch):
                match_state.clean_state()
        else:
            match_state.process_next_char(ch)

        return False

    def call(body):
        top_errors = []
        tokens, err = _parse_tokens(body)
        if err:
            top_errors.append(err)

        if tokens == None:
            return errors

        errors = func_def.call(*tokens)
        if errors:
            top_errors += errors

        return top_errors

    return struct(
        name = func_def.name,
        call = call,
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

    def _clean_state(funcs_trackings):
        for func_tracking in funcs_trackings:
            func_tracking.clean_state()

    def process_next_char(funcs_trackings, ch):
        for func_tracking in funcs_trackings:
            if not func_tracking.process_next_char(ch):
                continue

            _clean_state(funcs_trackings)
            return func_tracking

        return None

    return struct(
        process_next_char = lambda ch: process_next_char(funcs_trackings, ch),
    ), errors

def _parse_calls(data, mnemo, funcs_defs):
    data_len = len(data)

    tracking, errors = _create_tracking(funcs_defs, mnemo)

    if not tracking:
        return errors

    top_errors = []
    if errors:
        top_errors += errors

    started = None
    for idx in range(data_len):
        if started:
            ch = data[idx]
            if ch != ")":
                continue

            errors = started.func.call(data[started.pos:idx])
            if errors:
                top_errors += errors

            started = None
        else:
            func_to_start = tracking.process_next_char(data[idx])
            if func_to_start == None:
                continue

            started = struct(
                func = func_to_start,
                pos = idx + 1,
            )

    if started:
        top_errors.append("Parsing %s: can't finish parsing func - %s" % (mnemo, mnemo))

    return top_errors

def _parse_func_args(tokens, mnemo, *args):
    results = {}
    errors = []

    found_arg = None
    for token in tokens:
        if found_arg:
            results[found_arg] = token
            found_arg = None
            continue

        if token in args:
            found_arg = token
            continue

    if len(results) < len(args):
        errors.append("Parsing %s: can't parse all args: '%s' in tokens: '%s'" % (
            mnemo,
            args,
            tokens,
        ))

    return results, errors

def _substitute_var(result, substitutions):
    for key, value in substitutions.items():
        result = result.replace("${%s}" % key, value)

    err = None
    if "${" in result:
        err = "Not all substitutions unwrapped: %s" % result

    return result, err

def _wannabe_cmake_parser(data, mnemo, funcs, substitutions = {}):
    def _set(*tokens):
        if len(tokens) != 2:
            return ["Set doesn't have 2 arguments: %s" % str(tokens)]

        value, err = _substitute_var(tokens[1], substitutions)
        if value != None:
            substitutions[tokens[0]] = value

        if err != None:
            return [err]

        return []

    def _replace(*tokens):
        tokens_len = len(tokens)
        if tokens_len != 5:
            return ["len(tokens) == %s, but expected 5 for string(REPLACE, ..." % tokens_len]

        if tokens[0] != "REPLACE":
            return ["Can only process string(REPLACE, ..."]

        errors = []
        value, err = _substitute_var(tokens[4], substitutions)
        if err != None:
            errors.append(err)
        if not value:
            return errors

        substitutions[tokens[3]] = value.replace(tokens[1], tokens[2])

        return errors

    funcs_defs = [
        struct(
            name = "set",
            call = _set,
        ),
        struct(
            name = "string",
            call = _replace,
        ),
    ]

    def _call_func(func):
        def _inner_call(func, tokens):
            top_errors = []
            args, errors = _parse_func_args(
                tokens,
                "%s (function - %s)" % (mnemo, func.name),
                *func.args
            )
            if errors:
                top_errors += errors

            if args == None:
                return top_errors

            substitute_args = {}
            for key, value in args.items():
                value, err = _substitute_var(value, substitutions)
                if err != None:
                    top_errors.append(err)

                if value != None:
                    substitute_args[key.lower()] = value

            errors = func.call(**substitute_args)
            if errors:
                top_errors += errors

            return top_errors

        return lambda *tokens: _inner_call(func, tokens)

    for func in funcs:
        funcs_defs.append(struct(
            name = func.name,
            call = _call_func(func),
        ))

    return _parse_calls(data, mnemo, funcs_defs)

cmake_parser = _wannabe_cmake_parser
