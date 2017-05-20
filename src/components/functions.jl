function parse_kw(ps::ParseState, ::Type{Val{Tokens.FUNCTION}})
    startbyte = ps.t.startbyte
    start_col = ps.t.startpos[2] + 4

    # Parsing
    kw = INSTANCE(ps)
    format_kw(ps)
    # signature

    if isoperator(ps.nt.kind) && ps.nt.kind != Tokens.EX_OR && ps.nnt.kind == Tokens.LPAREN
        start1 = ps.nt.startbyte
        next(ps)
        op = OPERATOR(ps)
        next(ps)
        if issyntaxunarycall(op)
            sig = EXPR{UnarySyntaxOpCall}(EXPR[op, INSTANCE(ps)], 0, Variable[], "")
        else
            sig = EXPR(Call, EXPR[op, INSTANCE(ps)], 0)
        end
        @catcherror ps startbyte @default ps @closer ps paren parse_comma_sep(ps, sig)
        next(ps)
        push!(sig.args, INSTANCE(ps))
        sig.span = ps.nt.startbyte - start1
        @default ps @closer ps inwhere @closer ps ws @closer ps block while !closer(ps)
            @catcherror ps startbyte sig = parse_compound(ps, sig)
        end
    else
        @catcherror ps startbyte sig = @default ps @closer ps inwhere @closer ps block @closer ps ws parse_expression(ps)
    end
    
    while ps.nt.kind == Tokens.WHERE
        @catcherror ps startbyte sig = @default ps @closer ps inwhere @closer ps block @closer ps ws parse_compound(ps, sig)
    end

    if sig isa EXPR{InvisBrackets} && !(sig.args[1] isa EXPR{TupleH})
        sig.args[1] = EXPR(TupleH, EXPR[sig.args[1]], sig.args[1].span)
    end

    # _lint_func_sig(ps, sig, ps.nt.startbyte + (-sig.span:0))

    @catcherror ps startbyte block = @default ps @scope ps Scope{Tokens.FUNCTION} parse_block(ps, start_col)
    
    # fname0 = _get_fname(sig)
    # fname = fname0 isa IDENTIFIER ? fname0.val : :noname
    # _lint_func_body(ps, fname, block, ps.nt.startbyte - block.span)

    # Construction
    if isempty(block.args)
        if sig isa EXPR{Call} && !(sig.args[1] isa EXPR{OPERATOR{PlusOp,Tokens.EX_OR,false}})
            args = EXPR[sig, block]
        else
            args = EXPR[sig]
        end
    else
        args = EXPR[sig, block]
    end
    
    next(ps)
    
    ret = EXPR{FunctionDef}(EXPR[kw; args; INSTANCE(ps)], ps.nt.startbyte - startbyte, Variable[], "")
    # ret.defs = [Variable(function_name(sig), :Function, ret)]
    return ret
end

"""
    parse_call(ps, ret)

Parses a function call. Expects to start before the opening parentheses and is passed the expression declaring the function name, `ret`.
"""
function parse_call(ps::ParseState, ret)
    startbyte = ps.t.startbyte
    # Parsing
    if ret isa EXPR{OPERATOR{PlusOp,Tokens.EX_OR,false}} || ret isa EXPR{OPERATOR{DeclarationOp,Tokens.DECLARATION,false}} || ret isa EXPR{OPERATOR{TimesOp,Tokens.AND, d1}} where d1
        arg = @precedence ps 20 parse_expression(ps)
        ret = EXPR{UnarySyntaxOpCall}(EXPR[ret, arg], ret.span + arg.span, Variable[], "")
    elseif ret isa EXPR{OPERATOR{20,Tokens.NOT,d1}} where d1 || ret isa EXPR{OPERATOR{PlusOp,Tokens.MINUS, d2}} where d2 || ret isa EXPR{OPERATOR{PlusOp,Tokens.PLUS, d3}} where d3
        arg = @precedence ps 13 parse_expression(ps)
        if arg isa EXPR{TupleH}
            ret = EXPR{Call}(EXPR[ret; arg.args], ret.span + arg.span, Variable[], "")
        else
            ret = EXPR{UnaryOpCall}(EXPR[ret, arg], ret.span + arg.span, Variable[], "")
        end
    elseif ret isa EXPR{OPERATOR{ComparisonOp,Tokens.ISSUBTYPE,false}} || ret isa EXPR{OPERATOR{ComparisonOp,Tokens.ISSUPERTYPE,false}} || ret isa EXPR{OPERATOR{ComparisonOp,Tokens.ISSUPERTYPE,false}}
        arg = @precedence ps 13 parse_expression(ps)
        ret = EXPR{Call}(EXPR[ret; arg.args], ret.span + arg.span, Variable[], "")
    else
        next(ps)
        ret = EXPR{Call}(EXPR[ret, INSTANCE(ps)], ret.span - ps.t.startbyte, Variable[], "")
        format_lbracket(ps)
        @default ps @closer ps paren parse_comma_sep(ps, ret)
        next(ps)
        push!(ret.args, INSTANCE(ps))
        format_rbracket(ps)
        ret.span += ps.nt.startbyte
    end

    # if length(ret.args) > 0 && ismacro(ret.args[1])
    #     ret.head = MACROCALL
    # end
    # if ret.head isa HEAD{Tokens.CCALL} && length(ret.args) > 1 && ret.args[2] isa IDENTIFIER && (ret.args[2].val == :stdcall || ret.args[2].val == :fastcall || ret.args[2].val == :cdecl || ret.args[2].val == :thiscall)
    #     arg = splice!(ret.args, 2)
    #     push!(ret.args, EXPR(arg, [], arg.span))
    # end

    # Linting
    # if (ret.args[1] isa IDENTIFIER && ret.args[1].val == :Dict) || (ret.args[1] isa EXPR && ret.args[1].head == CURLY && ret.args[1].args[1] isa IDENTIFIER && ret.args[1].args[1].val == :Dict)
    #     _lint_dict(ps, ret)
    # end
    # _check_dep_call(ps, ret)

    # if fname isa IDENTIFIER && fname.val in keys(deprecated_symbols)
    #     push!(ps.diagnostics, Diagnostic{Diagnostics.Deprecation}(ps.nt.startbyte - ret.span + (0:(fname.span))))
    # end
    return ret
end


function parse_comma_sep(ps::ParseState, ret::EXPR, kw = true, block = false, formatcomma = true)
    startbyte = ps.nt.startbyte

    @catcherror ps startbyte @nocloser ps inwhere @noscope ps @nocloser ps newline @closer ps comma while !closer(ps)
        a = parse_expression(ps)
        if kw && !ps.closer.brace && a isa EXPR{BinarySyntaxOpCall} && a.args[2] isa EXPR{OPERATOR{AssignmentOp,Tokens.EQ,false}}
            a = EXPR{Kw}(a.args, a.span, Variable[], "")
        end
        push!(ret.args, a)
        if ps.nt.kind == Tokens.COMMA
            next(ps)
            push!(ret.args, INSTANCE(ps))
            if formatcomma
                format_comma(ps)
            else
                format_no_rws(ps)
            end
        end
        if ps.ws.kind == SemiColonWS
            break
        end
    end

    if ps.ws.kind == SemiColonWS
        if block
            body = EXPR{Block}(EXPR[pop!(ret.args)], 0, Variable[], "")
            body.span = body.args[1].span
            @nocloser ps newline @closer ps comma while @nocloser ps semicolon !closer(ps)
                @catcherror ps startbyte a = parse_expression(ps)
                push!(body.args, a)
            end
            push!(ret.args, body)

        else
            ps.nt.kind == Tokens.RPAREN && return 
            paras = EXPR{Parameters}(EXPR[], -ps.nt.startbyte, Variable[], "")
            @nocloser ps inwhere @nocloser ps newline @nocloser ps semicolon @closer ps comma while !closer(ps)
                @catcherror ps startbyte a = parse_expression(ps)
                if kw && !ps.closer.brace && a isa EXPR{BinarySyntaxOpCall} && a.args[2] isa EXPR{OPERATOR{AssignmentOp,Tokens.EQ,false}}
                    a = EXPR{Kw}(a.args, a.span, Variable[], "")
                end
                push!(paras.args, a)
                if ps.nt.kind == Tokens.COMMA
                    next(ps)
                    push!(paras.args, INSTANCE(ps))
                    format_comma(ps)
                end
            end
            paras.span += ps.nt.startbyte
            push!(ret.args, paras)
        end
    end
end


# Iterators


# Linting
# Signature
# [+] repeated argument names
# [+] argument/function name conflict
# [+] check slurping in last position only
# [+] check kw arguments order
# [] check all parameters are used specified
"""
    _lint_func_sig(ps, sig)

Runs linting on function argument, assumes `sig` has just been parsed such that 
the byte offset is `ps.nt.startbyte - sig.span`.
"""
function _lint_func_sig(ps::ParseState, sig::IDENTIFIER, loc) end
    
function _lint_func_sig(ps::ParseState, sig::EXPR, loc)
    if sig isa EXPR && sig.head isa EXPR{OPERATOR{DeclarationOp,Tokens.DECLARATION,false}}
        return _lint_func_sig(ps, sig.args[1], loc)
    end
    fname = _get_fname(sig)
    # use where syntax
    if sig isa EXPR && sig.head == CALL && sig.args[1] isa EXPR && sig.args[1].head == CURLY
        push!(ps.diagnostics, Diagnostic{Diagnostics.parameterisedDeprecation}((first(loc) + sig.args[1].args[1].span):(first(loc) + sig.args[1].span), []))
        
        trailingws = last(sig) isa PUNCTUATION{Tokens.RPAREN} ? last(sig).span - 1 : 0
        loc1 = first(loc) + sig.span - trailingws
        push!(last(ps.diagnostics).actions, Diagnostics.TextEdit((loc1):(loc1), string(" where {", join((Expr(t) for t in sig.args[1].args[2:end]), ","), "}")))
        push!(last(ps.diagnostics).actions, Diagnostics.TextEdit((first(loc) + sig.args[1].args[1].span):(first(loc) + sig.args[1].span), ""))
    end
    
    format_funcname(ps, function_name(sig), sig.span)
    args = Tuple{Symbol,Any}[]
    nargs = length(sig.args) - 1
    firstkw  = nargs + 1
    for (i, arg) in enumerate(sig.args[2:end])
        if arg isa EXPR && arg.head isa EXPR{OPERATOR{DeclarationOp,Tokens.DECLARATION,false}} && length(arg.args) == 1
            #unhandled ::Type argument
            continue
        elseif arg isa EXPR && arg.head == PARAMETERS
            for (i1, arg1) in enumerate(arg.args)
                _lint_arg(ps, arg1, args, i + i1 - 1, fname, nargs, i - 1, loc)
            end
        else
            _lint_arg(ps, arg, args, i, fname, nargs, firstkw, loc)
        end
    end
    sig.defs = (a -> Variable(a[1], a[2], sig)).(args)
end
    
function _lint_arg(ps::ParseState, arg, args, i, fname, nargs, firstkw, loc)
    a = _arg_id(arg)
    t = get_t(arg)
    !(a isa IDENTIFIER) && return
    # if !(a.val in args)
    if !any(a.val == aa[1] for aa in args)
        push!(args, (a.val, t))
    else 
        push!(ps.diagnostics, Diagnostic{Diagnostics.DuplicateArgumentName}(loc, []))
    end
    if a.val == Expr(fname)
        push!(ps.diagnostics, Diagnostic{Diagnostics.ArgumentFunctionNameConflict}(loc, []))
    end
    if arg isa EXPR && arg.head isa OPERATOR{0,Tokens.DDDOT} && i != nargs
        push!(ps.diagnostics, Diagnostic{Diagnostics.SlurpingPosition}(loc, []))
    end
    if arg isa EXPR && arg.head isa HEAD{Tokens.KW} && i < firstkw
        firstkw = i
    end
    if !(arg isa EXPR && arg.head isa HEAD{Tokens.KW}) && i > firstkw
        push!(ps.diagnostics, Diagnostic{Diagnostics.KWPosition}(loc, []))
    end
    # Check 
end

# make this traverse EXPR that contribute scope
function _lint_func_body(ps::ParseState, fname, body, loc)
    for a in body.args
        if a isa EXPR
            for d in a.defs
                if d.id == fname
                    push!(ps.diagnostics, Diagnostic{Diagnostics.AssignsToFuncName}(loc + (0:a.span), []))
                end
            end
        end
        if contributes_scope(a)
            _lint_func_body(ps::ParseState, fname, a, loc)
        end
        loc += a.span
    end
end




# NEEDS FIX
_arg_id(x::INSTANCE) = x
_arg_id(x::EXPR{Quotenode}) = x.val

function _arg_id(x::EXPR)
    if x.head isa OPERATOR{DeclarationOp,Tokens.DECLARATION} || x.head == CURLY || x.head isa OPERATOR{0,Tokens.DDDOT} || x.head isa HEAD{Tokens.KW}
        return _arg_id(x.args[1])
    else
        return x
    end
end


function _sig_params(x, p = [])
    if x isa EXPR
        if x.head == CURLY
            for a in x.args[2:end]
                push!(p, get_id(a))
            end
        end
    end
    return p
end

function _get_fname(sig)
    if sig isa IDENTIFIER
        return sig
    elseif sig isa EXPR && sig.head == TUPLE
        return NOTHING
    elseif sig isa EXPR && sig.head isa OPERATOR{DeclarationOp,Tokens.DECLARATION}
        get_id(sig.args[1].args[1])
    else
        get_id(sig.args[1])
    end
end

function function_name(sig::EXPR)
    if sig isa EXPR
        if sig.head == CALL || sig.head == CURLY
            return function_name(sig.args[1])
        elseif sig.head isa OPERATOR{DotOp,Tokens.DOT}
            return function_name(sig.args[2])
        end
    elseif sig isa EXPR{Quotenode}
        function_name(sig.val)
    elseif sig isa IDENTIFIER
        return sig.val
    elseif sig isa OPERATOR
        return UNICODE_OPS_REVERSE[typeof(sig).parameters[2]]
    else
        error("$(Expr(sig)) is not a valid function name")
    end
end


function declares_function(x::EXPR)
    if x isa EXPR
        if x.head isa KEYWORD{Tokens.FUNCTION}
            return true
        elseif x.head isa OPERATOR{AssignmentOp,Tokens.EQ} && x.args[1] isa EXPR && x.args[1].head == CALL
            return true
        else
            return false
        end
    else
        return false
    end
end

function _lint_dict(ps::ParseState, x::EXPR)
    # paramaterised case
    if x.args[1] isa EXPR && x.args[1].head == CURLY
        # expect 2 parameters (+ :Dict)
        if length(x.args[1].args) != 3
            push!(ps.diagnostics, Diagnostic{Diagnostics.DictParaMisSpec}(ps.nt.startbyte - x.span + (0:x[1].span), []))
        end
    end
    # Handle generators
    if length(x.args) > 1 
        if x.args[2] isa EXPR && x.args[2].head == GENERATOR
            gen = x.args[2]
            if gen.args[1].head isa OPERATOR{AssignmentOp} && !(gen.args[1].head isa OPERATOR{AssignmentOp,Tokens.PAIR_ARROW})
                push!(ps.diagnostics, Diagnostic{Diagnostics.DictGenAssignment}(ps.nt.startbyte - x.span + (0:x.span), []))
            end
        # Lint items
        else
            locstart = ps.nt.startbyte - x.span + x.args[1].span + first(x.punctuation).span
            for (i, a) in enumerate(x.args[2:end])
                # non pair arrow assignment
                if a isa EXPR && a.head isa OPERATOR{AssignmentOp} && !(a.head isa OPERATOR{AssignmentOp,Tokens.PAIR_ARROW})
                    push!(ps.diagnostics, Diagnostic{Diagnostics.DictGenAssignment}(locstart + (0:a.span), []))
                end
                locstart += a.span + x.punctuation[i + 1].span
            end
        end
    end
end
