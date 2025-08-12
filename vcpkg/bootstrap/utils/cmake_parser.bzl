def _is_whitespace(ch):
    return ch in [" ", "\n", "\r"]

def _parse_tokens(body, _parse_ctx):
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

    return tokens

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

    return struct(
        state = state,
        clean_state = lambda: state.set_match_pos(None),
        is_matched = lambda: state.match_pos() == state.name_len() - 1,
        is_started = lambda: state.match_pos() != None,
        process_next_char = lambda ch: process_next_char(state, ch),
    )

def _parse_func_kwargs(tokens, match_args, parse_ctx):
    kwargs = {}

    def _process_cur_values(state):
        if state.found_arg() == None:
            return

        if not state.values():
            return

        elif len(state.values()) == 1:
            kwargs[state.found_arg()] = state.values()[0]
        else:
            kwargs[state.found_arg()] = state.values()

        state.set_found_arg(None)
        state.set_values([])

    state = _new_state(mutable_data = _to_dict(
        found_arg = None,
        values = [],
    ))

    for token in tokens:
        if state.found_arg() != None:
            if token.isupper():
                _process_cur_values(state)
            else:
                value = parse_ctx.substitute(token)
                if value != None:
                    state.values().append(value)
                continue

        if token in match_args:
            state.set_found_arg(token.lower())
            state.set_values([])

    _process_cur_values(state)

    for match_arg in match_args:
        if kwargs.setdefault(match_arg.lower()) != None:
            continue

        parse_ctx.on_err("Can't parse arg: '%s' in tokens: '%s'" % (
            match_arg,
            tokens,
        ))

    return kwargs

def _match_and_call(tokens, func_defs, parse_ctx):
    for func_def in func_defs:
        if hasattr(func_def, "match_tokens"):
            matched = True
            for idx, match_token in enumerate(func_def.match_tokens):
                if tokens[idx] == match_token:
                    continue

                matched = False
                break

            if not matched:
                continue

        args = [parse_ctx]
        kwargs = {}
        if hasattr(func_def, "match_args"):
            kwargs = _parse_func_kwargs(tokens, func_def.match_args, parse_ctx)
        else:
            args += tokens

        func_def.call(*args, **kwargs)

def _create_func_tracking(func_name, func_defs, parse_ctx):
    match_state = _match_state(func_name)

    def _process_next_char(match_state, ch):
        if match_state.is_matched():
            if ch == "(":
                return True
            elif not _is_whitespace(ch):
                match_state.clean_state()
        else:
            match_state.process_next_char(ch)

        return False

    def _call(body):
        tokens = _parse_tokens(body, parse_ctx)
        if tokens == None:
            return

        _match_and_call(tokens, func_defs, parse_ctx)

    return struct(
        name = func_name,
        call = _call,
        process_next_char = lambda ch: _process_next_char(match_state, ch),
        clean_state = lambda: match_state.clean_state(),
    )

def _create_func_trackings(funcs_defs, parse_ctx):
    funcs_trackings = []
    for func_name, defs in funcs_defs.items():
        func_tracking = _create_func_tracking(func_name, defs, parse_ctx)
        if func_tracking:
            funcs_trackings.append(func_tracking)

    return sorted(
        funcs_trackings,
        key = lambda x: len(x.name),
        reverse = True,
    )

def _create_tracking(funcs_defs, parse_ctx):
    funcs_trackings = _create_func_trackings(funcs_defs, parse_ctx)
    if not funcs_trackings:
        return None

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
    )

def _parse_calls(data, parse_ctx, funcs_defs):
    data_len = len(data)

    tracking = _create_tracking(funcs_defs, parse_ctx)
    if not tracking:
        return

    started = None
    for idx in range(data_len):
        if started:
            ch = data[idx]
            if ch == started.chars_to_call[-1]:
                started.chars_to_call.pop()
                if started.chars_to_call:
                    continue

                started.func.call(data[started.pos:idx])
                started = None
            elif ch == "\"":
                started.chars_to_call.append("\"")
        else:
            func_to_start = tracking.process_next_char(data[idx])
            if func_to_start == None:
                continue

            started = struct(
                func = func_to_start,
                pos = idx + 1,
                chars_to_call = [")"],
            )

    if started:
        parse_ctx.on_err("Can't finish parsing func - %s" % started.func.name)

def _parse_ctx(mnemo, substitutions = {}):
    errors = []

    def _on_err(err):
        if not err:
            return False

        errors.append("Parsing %s: %s" % (mnemo, err))
        return True

    def _substitute_var(result):
        for key, value in substitutions.items():
            result = result.replace("${%s}" % key, value)

        if "${" in result:
            _on_err("Not all substitutions unwrapped: %s" % result)
            return None

        return result

    def _set(key, value):
        substitutions[key] = value

    def _set_substitute(key, value, map = None):
        value = _substitute_var(value)
        if value == None:
            return

        if map == None:
            _set(key, value)
        else:
            _set(key, map(value))

    return struct(
        mnemo = mnemo,
        errors = errors,
        substitutions = substitutions,
        substitute = _substitute_var,
        set = _set,
        set_subst = _set_substitute,
        on_err = _on_err,
    )

def _wannabe_cmake_parser(data, mnemo, funcs_defs, substitutions = {}):
    parse_ctx = _parse_ctx(mnemo, substitutions)

    def _set(parse_ctx, *tokens):
        if len(tokens) != 2:
            parse_ctx.on_err("Set doesn't have 2 arguments: %s" % str(tokens))
            return

        parse_ctx.set_subst(tokens[0], tokens[1])

    funcs_defs.setdefault("set", [])
    funcs_defs["set"].append(struct(call = _set))

    def _replace(parse_ctx, *tokens):
        tokens_len = len(tokens)
        if tokens_len != 5:
            parse_ctx.on_err("len(tokens) == %s, but expected 5 for string(REPLACE ..." % tokens_len)
            return

        if tokens[0] != "REPLACE":
            parse_ctx.on_err(["Can only process string(REPLACE ..."])
            return

        parse_ctx.set_subst(tokens[3], tokens[4], lambda v: v.replace(tokens[1], tokens[2]))

    funcs_defs.setdefault("string", [])
    funcs_defs["string"].append(struct(
        match_tokens = ["REPLACE"],
        call = _replace,
    ))

    _parse_calls(data, parse_ctx, funcs_defs)
    return parse_ctx.errors

cmake_parser = _wannabe_cmake_parser
