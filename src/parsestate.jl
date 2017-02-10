import Tokenize.Lexers: peekchar, prevchar, readchar, iswhitespace, emit, emit_error, backup!, accept_batch, eof

const empty_whitespace = Token()

type Closer
    newline::Bool
    eof::Bool
    tuple::Bool
    comma::Bool
    dot::Bool
    paren::Bool
    brace::Bool
    square::Bool
    block::Bool
    ifelse::Bool
    ifop::Bool
    trycatch::Bool
    ws::Bool
    precedence::Int
end

Closer() = Closer(true, true, false, false, false, false, false, false, false, false, false, false, false, 0)

type ParseState
    l::Lexer
    done::Bool
    lt::Token
    t::Token
    nt::Token
    lws::Token
    ws::Token
    nws::Token
    formatcheck::Bool
    ids::Dict{String,Any}
    hints::Vector{Any}
    closer::Closer
    T1::Int
    T2::Int
end
function ParseState(str::String)
    next(ParseState(tokenize(str), false, Token(), Token(), Token(), Token(), Token(), Token(), true, Dict(), [], Closer(), 0, 0))
end

function Base.show(io::IO, ps::ParseState)
    println(io, "ParseState $(ps.done ? "finished " : "")at $(ps.l.current_pos)")
    println(io, "token - (ws)")
    println(io,"last    : ", ps.lt, " ($(length(ps.lws.val)))")
    println(io,"current : ", ps.t, " ($(length(ps.ws.val)))")
    println(io,"next    : ", ps.nt, " ($(length(ps.nws.val)))")
end
peekchar(ps::ParseState) = peekchar(ps.l)

function next(ps::ParseState)
    global empty_whitespace
    ps.lt = ps.t
    ps.t = ps.nt
    ps.lws = ps.ws
    ps.ws = ps.nws
    b0 = Base.gc_time_ns()
    ps.nt, ps.done  = next(ps.l, ps.done)
    ps.T1+= Base.gc_time_ns()-b0
    if iswhitespace(peekchar(ps.l)) || peekchar(ps.l)=='#'
        b0 = Base.gc_time_ns()
        ps.nws = lex_ws_comment(ps.l, readchar(ps.l))
        ps.T2+= Base.gc_time_ns()-b0
    else
        ps.nws = Token(Tokens.begin_delimiters, (0, 0), (0, 0), ps.nt.endbyte, ps.nt.endbyte, "")
    end
    return ps
end

function lex_ws_comment(l::Lexer, c)
    newline = c=='\n'
    if prevchar(l)=='#'
        newline = read_comment(l)
    else
        newline = read_ws(l, newline)
    end
    while iswhitespace(peekchar(l)) || peekchar(l)=='#'
        readchar(l)
        if prevchar(l)=='#'
            read_comment(l)
        else
            newline = read_ws(l, newline)
        end
    end

    return emit(l, newline ? Tokens.begin_literal : Tokens.end_literal)
end

function read_ws(l::Lexer, ok)
    while iswhitespace(peekchar(l))
        readchar(l)=='\n' && (ok = true)
    end
    return ok
end

function read_comment(l::Lexer)
    if readchar(l) != '='
        while true
            c = readchar(l)
            if c == '\n' || eof(c)
                backup!(l)
                break
            end
        end
    else
        c = readchar(l) # consume the '='
        n_start, n_end = 1, 0
        while true
            if eof(c)
                return emit_error(l, Tokens.EOF_MULTICOMMENT)
            end
            nc = readchar(l)
            if c == '#' && nc == '='
                n_start += 1
            elseif c == '=' && nc == '#'
                n_end += 1
            end
            if n_start == n_end
                break
            end
            c = nc
        end
    end
end


isempty(t::Token) = t.kind == Tokens.begin_delimiters