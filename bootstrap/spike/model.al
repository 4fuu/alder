type SourceRec {
    path_start: U64
    path_end: U64
    text_start: U64
    text_end: U64
}

type DeclRec {
    source: U64
    start: U64
    end: U64
    name_start: U64
    name_end: U64
}

type UseRec {
    source: U64
    start: U64
    end: U64
    name_start: U64
    name_end: U64
}

type DiagRec {
    code: U64
    source: U64
    start: U64
    end: U64
    related_source: U64
    related_start: U64
    related_end: U64
}

type State {
    paths: __s0_Buffer(U8)
    texts: __s0_Buffer(U8)
    names: __s0_Buffer(U8)
    sources: __s0_Buffer(SourceRec)
    decls: __s0_Buffer(DeclRec)
    uses: __s0_Buffer(UseRec)
    diags: __s0_Buffer(DiagRec)
}
