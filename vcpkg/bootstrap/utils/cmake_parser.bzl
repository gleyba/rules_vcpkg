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
        if body[idx] in [" ", "\n"]:
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

def _parse_func_args(body, mnemo, *args):
    result = {}

    tokens = _parse_tokens(body)
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

def parse_calls(rctx, file, mnemo, func_name, *args):
    result = []
    func_name_len = len(func_name)
    data = rctx.read(file)
    data_len = len(data)
    mnemo = "%s for func %s" % (mnemo, func_name)

    pos = 0
    for _ in range(data_len):
        pos = data.find(func_name, pos)
        if pos == -1:
            break

        if data[pos + func_name_len] != "(":
            return None, "Parsing %s: next char is not '('" % mnemo

        end_pos = data.find(")", pos + func_name_len + 1)
        if end_pos == -1:
            return None, "Parsing %s: can't find ')' char after" % mnemo

        func_body = data[pos + func_name_len + 1:end_pos]
        pos = end_pos + 1

        args, err = _parse_func_args(func_body, mnemo, *args)
        if err:
            return None, err

        if not args:
            return None, "Parsing %s: args is empty after parsing" % mnemo

        result.append(args)

    return result, None
