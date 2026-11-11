set -e
cd /home/user/workspace/repo
rm -rf .alder-dbg && cp -r compiler/src .alder-dbg
python3 - <<'PYEOF'
import re
# patch 1: model_fail in lower.al
path='.alder-dbg/lower.al'
src=open(path).read()
start=src.index('fn lower_model_valid(')
end=src.index('fn lower_checked(')
body=src[start:end]
n=[0]
def repl(m):
    n[0]+=1
    return '{ return model_fail(%d) }' % n[0]
body2=re.sub(r'\{ return false \}', repl, body)
helper='''
fn model_fail(site: U64) -> Bool {
    if !out_string("MODEL-FAIL ") { return false }
    if !out_u64(site) { return false }
    if !out(10) { return false }
    return false
}

'''
src2=src[:start]+helper+body2+src[end:]
open(path,'w').write(src2)
print('model sites patched:', n[0])
# patch 2: VERIFY-FAIL in verify_phase10.al
path='.alder-dbg/verify_phase10.al'
src=open(path).read()
old='''    if __s0_buffer_len(MirVerifyDiagRec, verified.diagnostics) != 0 { return Ok(MirVerifyCompleteOutput(diagnostics: verified.diagnostics, complete: false, hosted: hosted, entry: 0)) }
    if hosted { return mir_v10_entry(d, store, verified.diagnostics) }'''
new='''    if __s0_buffer_len(MirVerifyDiagRec, verified.diagnostics) != 0 {
        let diag0 = __s0_buffer_get(MirVerifyDiagRec, verified.diagnostics, 0)
        if !out_string("VERIFY-FAIL phase=") { return Ok(MirVerifyCompleteOutput(diagnostics: verified.diagnostics, complete: false, hosted: hosted, entry: 0)) }
        if !out_u64(diag0.phase) { return Ok(MirVerifyCompleteOutput(diagnostics: verified.diagnostics, complete: false, hosted: hosted, entry: 0)) }
        if !out_string(" kind=") { return Ok(MirVerifyCompleteOutput(diagnostics: verified.diagnostics, complete: false, hosted: hosted, entry: 0)) }
        if !out_u64(diag0.kind) { return Ok(MirVerifyCompleteOutput(diagnostics: verified.diagnostics, complete: false, hosted: hosted, entry: 0)) }
        if !out_string(" fn=") { return Ok(MirVerifyCompleteOutput(diagnostics: verified.diagnostics, complete: false, hosted: hosted, entry: 0)) }
        if !out_u64(diag0.function) { return Ok(MirVerifyCompleteOutput(diagnostics: verified.diagnostics, complete: false, hosted: hosted, entry: 0)) }
        if !out_string(" block=") { return Ok(MirVerifyCompleteOutput(diagnostics: verified.diagnostics, complete: false, hosted: hosted, entry: 0)) }
        if !out_u64(diag0.block) { return Ok(MirVerifyCompleteOutput(diagnostics: verified.diagnostics, complete: false, hosted: hosted, entry: 0)) }
        if !out_string(" instr=") { return Ok(MirVerifyCompleteOutput(diagnostics: verified.diagnostics, complete: false, hosted: hosted, entry: 0)) }
        if !out_u64(diag0.instruction) { return Ok(MirVerifyCompleteOutput(diagnostics: verified.diagnostics, complete: false, hosted: hosted, entry: 0)) }
        if !out_string(" op=") { return Ok(MirVerifyCompleteOutput(diagnostics: verified.diagnostics, complete: false, hosted: hosted, entry: 0)) }
        if !out_u64(diag0.operand) { return Ok(MirVerifyCompleteOutput(diagnostics: verified.diagnostics, complete: false, hosted: hosted, entry: 0)) }
        if !out_string(" ty=") { return Ok(MirVerifyCompleteOutput(diagnostics: verified.diagnostics, complete: false, hosted: hosted, entry: 0)) }
        if !out_u64(diag0.type_id) { return Ok(MirVerifyCompleteOutput(diagnostics: verified.diagnostics, complete: false, hosted: hosted, entry: 0)) }
        if !out_string(" decl=") { return Ok(MirVerifyCompleteOutput(diagnostics: verified.diagnostics, complete: false, hosted: hosted, entry: 0)) }
        if !out_u64(diag0.declaration) { return Ok(MirVerifyCompleteOutput(diagnostics: verified.diagnostics, complete: false, hosted: hosted, entry: 0)) }
        if !out_string(" exp=") { return Ok(MirVerifyCompleteOutput(diagnostics: verified.diagnostics, complete: false, hosted: hosted, entry: 0)) }
        if !out_u64(diag0.expected) { return Ok(MirVerifyCompleteOutput(diagnostics: verified.diagnostics, complete: false, hosted: hosted, entry: 0)) }
        if !out_string(" act=") { return Ok(MirVerifyCompleteOutput(diagnostics: verified.diagnostics, complete: false, hosted: hosted, entry: 0)) }
        if !out_u64(diag0.actual) { return Ok(MirVerifyCompleteOutput(diagnostics: verified.diagnostics, complete: false, hosted: hosted, entry: 0)) }
        if !out(10) { return Ok(MirVerifyCompleteOutput(diagnostics: verified.diagnostics, complete: false, hosted: hosted, entry: 0)) }
        if !out_string("DBG functions=") { return Ok(MirVerifyCompleteOutput(diagnostics: verified.diagnostics, complete: false, hosted: hosted, entry: 0)) }
        if !out_u64(__s0_buffer_len(MirFunctionRec, store.functions)) { return Ok(MirVerifyCompleteOutput(diagnostics: verified.diagnostics, complete: false, hosted: hosted, entry: 0)) }
        if !out_string(" locals=") { return Ok(MirVerifyCompleteOutput(diagnostics: verified.diagnostics, complete: false, hosted: hosted, entry: 0)) }
        if !out_u64(__s0_buffer_len(MirLocalRec, store.locals)) { return Ok(MirVerifyCompleteOutput(diagnostics: verified.diagnostics, complete: false, hosted: hosted, entry: 0)) }
        if !out(10) { return Ok(MirVerifyCompleteOutput(diagnostics: verified.diagnostics, complete: false, hosted: hosted, entry: 0)) }
        var dbg_at: U64 = 0
        while dbg_at < __s0_buffer_len(MirLocalRec, store.locals) {
            let dbg_local = __s0_buffer_get(MirLocalRec, store.locals, dbg_at)
            if !out_string("LOCAL ") { return Ok(MirVerifyCompleteOutput(diagnostics: verified.diagnostics, complete: false, hosted: hosted, entry: 0)) }
            if !out_u64(dbg_at + 1) { return Ok(MirVerifyCompleteOutput(diagnostics: verified.diagnostics, complete: false, hosted: hosted, entry: 0)) }
            if !out_string(" fn=") { return Ok(MirVerifyCompleteOutput(diagnostics: verified.diagnostics, complete: false, hosted: hosted, entry: 0)) }
            if !out_u64(dbg_local.function) { return Ok(MirVerifyCompleteOutput(diagnostics: verified.diagnostics, complete: false, hosted: hosted, entry: 0)) }
            if !out_string(" ord=") { return Ok(MirVerifyCompleteOutput(diagnostics: verified.diagnostics, complete: false, hosted: hosted, entry: 0)) }
            if !out_u64(dbg_local.ordinal) { return Ok(MirVerifyCompleteOutput(diagnostics: verified.diagnostics, complete: false, hosted: hosted, entry: 0)) }
            if !out(10) { return Ok(MirVerifyCompleteOutput(diagnostics: verified.diagnostics, complete: false, hosted: hosted, entry: 0)) }
            dbg_at = dbg_at + 1
        }
        dbg_at = 0
        while dbg_at < __s0_buffer_len(MirFunctionRec, store.functions) {
            let dbg_fn = __s0_buffer_get(MirFunctionRec, store.functions, dbg_at)
            if !out_string("FN ") { return Ok(MirVerifyCompleteOutput(diagnostics: verified.diagnostics, complete: false, hosted: hosted, entry: 0)) }
            if !out_u64(dbg_at + 1) { return Ok(MirVerifyCompleteOutput(diagnostics: verified.diagnostics, complete: false, hosted: hosted, entry: 0)) }
            if !out_string(" namelen=") { return Ok(MirVerifyCompleteOutput(diagnostics: verified.diagnostics, complete: false, hosted: hosted, entry: 0)) }
            if !out_u64(dbg_fn.name_end - dbg_fn.name_start) { return Ok(MirVerifyCompleteOutput(diagnostics: verified.diagnostics, complete: false, hosted: hosted, entry: 0)) }
            if !out(10) { return Ok(MirVerifyCompleteOutput(diagnostics: verified.diagnostics, complete: false, hosted: hosted, entry: 0)) }
            dbg_at = dbg_at + 1
        }
        dbg_at = 0
        while dbg_at < __s0_buffer_len(MirParamRec, store.params) {
            let dbg_param = __s0_buffer_get(MirParamRec, store.params, dbg_at)
            if !out_string("PARAM ") { return Ok(MirVerifyCompleteOutput(diagnostics: verified.diagnostics, complete: false, hosted: hosted, entry: 0)) }
            if !out_u64(dbg_at + 1) { return Ok(MirVerifyCompleteOutput(diagnostics: verified.diagnostics, complete: false, hosted: hosted, entry: 0)) }
            if !out_string(" fn=") { return Ok(MirVerifyCompleteOutput(diagnostics: verified.diagnostics, complete: false, hosted: hosted, entry: 0)) }
            if !out_u64(dbg_param.function) { return Ok(MirVerifyCompleteOutput(diagnostics: verified.diagnostics, complete: false, hosted: hosted, entry: 0)) }
            if !out_string(" ord=") { return Ok(MirVerifyCompleteOutput(diagnostics: verified.diagnostics, complete: false, hosted: hosted, entry: 0)) }
            if !out_u64(dbg_param.ordinal) { return Ok(MirVerifyCompleteOutput(diagnostics: verified.diagnostics, complete: false, hosted: hosted, entry: 0)) }
            if !out_string(" kind=") { return Ok(MirVerifyCompleteOutput(diagnostics: verified.diagnostics, complete: false, hosted: hosted, entry: 0)) }
            if !out_u64(dbg_param.kind) { return Ok(MirVerifyCompleteOutput(diagnostics: verified.diagnostics, complete: false, hosted: hosted, entry: 0)) }
            if !out(10) { return Ok(MirVerifyCompleteOutput(diagnostics: verified.diagnostics, complete: false, hosted: hosted, entry: 0)) }
            dbg_at = dbg_at + 1
        }
        dbg_at = 0
        while dbg_at < __s0_buffer_len(MirTypeRec, store.types) {
            let dbg_type = __s0_buffer_get(MirTypeRec, store.types, dbg_at)
            if !out_string("TYPE ") { return Ok(MirVerifyCompleteOutput(diagnostics: verified.diagnostics, complete: false, hosted: hosted, entry: 0)) }
            if !out_u64(dbg_at + 1) { return Ok(MirVerifyCompleteOutput(diagnostics: verified.diagnostics, complete: false, hosted: hosted, entry: 0)) }
            if !out_string(" kind=") { return Ok(MirVerifyCompleteOutput(diagnostics: verified.diagnostics, complete: false, hosted: hosted, entry: 0)) }
            if !out_u64(dbg_type.kind) { return Ok(MirVerifyCompleteOutput(diagnostics: verified.diagnostics, complete: false, hosted: hosted, entry: 0)) }
            if !out_string(" elem=") { return Ok(MirVerifyCompleteOutput(diagnostics: verified.diagnostics, complete: false, hosted: hosted, entry: 0)) }
            if !out_u64(dbg_type.elem) { return Ok(MirVerifyCompleteOutput(diagnostics: verified.diagnostics, complete: false, hosted: hosted, entry: 0)) }
            if !out_string(" len=") { return Ok(MirVerifyCompleteOutput(diagnostics: verified.diagnostics, complete: false, hosted: hosted, entry: 0)) }
            if !out_u64(dbg_type.length) { return Ok(MirVerifyCompleteOutput(diagnostics: verified.diagnostics, complete: false, hosted: hosted, entry: 0)) }
            if !out(10) { return Ok(MirVerifyCompleteOutput(diagnostics: verified.diagnostics, complete: false, hosted: hosted, entry: 0)) }
            dbg_at = dbg_at + 1
        }
        dbg_at = 0
        while dbg_at < __s0_buffer_len(MirInstrRec, store.instructions) {
            let dbg_instr = __s0_buffer_get(MirInstrRec, store.instructions, dbg_at)
            if !out_string("INSTR ") { return Ok(MirVerifyCompleteOutput(diagnostics: verified.diagnostics, complete: false, hosted: hosted, entry: 0)) }
            if !out_u64(dbg_at + 1) { return Ok(MirVerifyCompleteOutput(diagnostics: verified.diagnostics, complete: false, hosted: hosted, entry: 0)) }
            if !out_string(" fn=") { return Ok(MirVerifyCompleteOutput(diagnostics: verified.diagnostics, complete: false, hosted: hosted, entry: 0)) }
            if !out_u64(dbg_instr.function) { return Ok(MirVerifyCompleteOutput(diagnostics: verified.diagnostics, complete: false, hosted: hosted, entry: 0)) }
            if !out_string(" op=") { return Ok(MirVerifyCompleteOutput(diagnostics: verified.diagnostics, complete: false, hosted: hosted, entry: 0)) }
            if !out_u64(dbg_instr.op) { return Ok(MirVerifyCompleteOutput(diagnostics: verified.diagnostics, complete: false, hosted: hosted, entry: 0)) }
            if !out_string(" res=") { return Ok(MirVerifyCompleteOutput(diagnostics: verified.diagnostics, complete: false, hosted: hosted, entry: 0)) }
            if !out_u64(dbg_instr.result) { return Ok(MirVerifyCompleteOutput(diagnostics: verified.diagnostics, complete: false, hosted: hosted, entry: 0)) }
            if !out_string(" a=") { return Ok(MirVerifyCompleteOutput(diagnostics: verified.diagnostics, complete: false, hosted: hosted, entry: 0)) }
            if !out_u64(dbg_instr.a) { return Ok(MirVerifyCompleteOutput(diagnostics: verified.diagnostics, complete: false, hosted: hosted, entry: 0)) }
            if !out_string(" b=") { return Ok(MirVerifyCompleteOutput(diagnostics: verified.diagnostics, complete: false, hosted: hosted, entry: 0)) }
            if !out_u64(dbg_instr.b) { return Ok(MirVerifyCompleteOutput(diagnostics: verified.diagnostics, complete: false, hosted: hosted, entry: 0)) }
            if !out_string(" tgt=") { return Ok(MirVerifyCompleteOutput(diagnostics: verified.diagnostics, complete: false, hosted: hosted, entry: 0)) }
            if !out_u64(dbg_instr.target) { return Ok(MirVerifyCompleteOutput(diagnostics: verified.diagnostics, complete: false, hosted: hosted, entry: 0)) }
            if !out_string(" blk=") { return Ok(MirVerifyCompleteOutput(diagnostics: verified.diagnostics, complete: false, hosted: hosted, entry: 0)) }
            if !out_u64(dbg_instr.block) { return Ok(MirVerifyCompleteOutput(diagnostics: verified.diagnostics, complete: false, hosted: hosted, entry: 0)) }
            if !out_string(" ord=") { return Ok(MirVerifyCompleteOutput(diagnostics: verified.diagnostics, complete: false, hosted: hosted, entry: 0)) }
            if !out_u64(dbg_instr.ordinal) { return Ok(MirVerifyCompleteOutput(diagnostics: verified.diagnostics, complete: false, hosted: hosted, entry: 0)) }
            if !out(10) { return Ok(MirVerifyCompleteOutput(diagnostics: verified.diagnostics, complete: false, hosted: hosted, entry: 0)) }
            dbg_at = dbg_at + 1
        }
        dbg_at = 0
        while dbg_at < __s0_buffer_len(MirValueRec, store.values) {
            let dbg_value = __s0_buffer_get(MirValueRec, store.values, dbg_at)
            if !out_string("VALUE ") { return Ok(MirVerifyCompleteOutput(diagnostics: verified.diagnostics, complete: false, hosted: hosted, entry: 0)) }
            if !out_u64(dbg_at + 1) { return Ok(MirVerifyCompleteOutput(diagnostics: verified.diagnostics, complete: false, hosted: hosted, entry: 0)) }
            if !out_string(" fn=") { return Ok(MirVerifyCompleteOutput(diagnostics: verified.diagnostics, complete: false, hosted: hosted, entry: 0)) }
            if !out_u64(dbg_value.function) { return Ok(MirVerifyCompleteOutput(diagnostics: verified.diagnostics, complete: false, hosted: hosted, entry: 0)) }
            if !out_string(" ord=") { return Ok(MirVerifyCompleteOutput(diagnostics: verified.diagnostics, complete: false, hosted: hosted, entry: 0)) }
            if !out_u64(dbg_value.ordinal) { return Ok(MirVerifyCompleteOutput(diagnostics: verified.diagnostics, complete: false, hosted: hosted, entry: 0)) }
            if !out_string(" defk=") { return Ok(MirVerifyCompleteOutput(diagnostics: verified.diagnostics, complete: false, hosted: hosted, entry: 0)) }
            if !out_u64(dbg_value.def_kind) { return Ok(MirVerifyCompleteOutput(diagnostics: verified.diagnostics, complete: false, hosted: hosted, entry: 0)) }
            if !out_string(" blk=") { return Ok(MirVerifyCompleteOutput(diagnostics: verified.diagnostics, complete: false, hosted: hosted, entry: 0)) }
            if !out_u64(dbg_value.block) { return Ok(MirVerifyCompleteOutput(diagnostics: verified.diagnostics, complete: false, hosted: hosted, entry: 0)) }
            if !out_string(" item=") { return Ok(MirVerifyCompleteOutput(diagnostics: verified.diagnostics, complete: false, hosted: hosted, entry: 0)) }
            if !out_u64(dbg_value.item) { return Ok(MirVerifyCompleteOutput(diagnostics: verified.diagnostics, complete: false, hosted: hosted, entry: 0)) }
            if !out(10) { return Ok(MirVerifyCompleteOutput(diagnostics: verified.diagnostics, complete: false, hosted: hosted, entry: 0)) }
            dbg_at = dbg_at + 1
        }
        return Ok(MirVerifyCompleteOutput(diagnostics: verified.diagnostics, complete: false, hosted: hosted, entry: 0))
    }
    if hosted { return mir_v10_entry(d, store, verified.diagnostics) }'''
assert old in src, 'verify anchor not found'
open(path,'w').write(src.replace(old,new))
print('verify patched')
PYEOF

python3 - <<'PYEOF2'
# patch 3: dump MIR text on verification failure (debug only)
path='.alder-dbg/main.al'
src=open(path).read()
old="""fn finish_verify(d: Domain, state: State, store: CheckStore, mir: MirStore, result: MirVerifyCompleteOutput, reports: __s0_Buffer(CopySiteRec)) -> I32 {
    if !result.complete { return driver_failure(4, "internal", "internal compiler failure: verification refused") }"""
new="""fn finish_verify(d: Domain, state: State, store: CheckStore, mir: MirStore, result: MirVerifyCompleteOutput, reports: __s0_Buffer(CopySiteRec)) -> I32 {
    if !result.complete {
        if driver_artifact_start("mir") {
            if !mir_print(d, mir) { return driver_failure(4, "internal", "debug mir print failed") }
            if !driver_artifact_finish() { return driver_failure(4, "internal", "debug mir finish failed") }
        }
        return driver_failure(4, "internal", "internal compiler failure: verification refused")
    }"""
assert old in src, 'main anchor not found'
open(path,'w').write(src.replace(old,new))
print('main patched')

PYEOF2
stage0=$(ls -t .alder-cache/alder-stage0-* | head -1)
mapfile -t order < <(tail -n +2 bootstrap/compiler-sources.order | sed 's|^compiler/src/|.alder-dbg/|')
"$stage0" compile --emit=c --bootstrap-private "${order[@]}" > /tmp/alder-dbg2.c 2>/tmp/alder-dbg2.err || { cat /tmp/alder-dbg2.err; exit 1; }
gcc -O2 -std=c11 -I runtime/c -I bootstrap -o /tmp/alderc/alderc-dbg2 /tmp/alder-dbg2.c bootstrap/alder_host.c runtime/c/alder.c -lm
echo DEBUG-READY
