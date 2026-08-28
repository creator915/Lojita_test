# Runtime NbE v14 typed AST

v14 replaces construct-specific v1–v13 payloads with one recursive, typed program format.  Old
schemas remain read-only compatibility inputs until every formal scenario has migrated; they are not
completion evidence for the unified adapter.

## Packet envelope

Every packet has exactly these common fields, followed by `definition-count` indexed definition
entries:

```text
schema=runtime-nbe-ir-v14
language=runtime-nbe-typed-ast-v1
context-size=0
type-ast=TYPE
term-ast=TERM
definition-count=N
def0-qname=Qualified.name
def0-type-ast=TYPE
def0-body-ast=TERM
...
source-qname=Qualified.result
agda-revision=...
provider-revision=...
```

Field order is canonical at production time. Consumers reject duplicate, missing and unknown fields.
QNames are identities, never executable source text. `context-size=0` means the selected result and
the transmitted definition closure are closed; de Bruijn variables are only legal under binders in
their enclosing AST.

## Declared grammar

The parser consumes one recursive AST grammar. The currently declared matrix uses these type,
term and definition-body nodes:

```text
TYPE ::= u | bool | def(N) | pi(TYPE,TYPE) | sigma(TYPE,TYPE)
       | app(def(N),TERM) | path(TYPE,TERM,TERM)
       | equiv(TYPE,TYPE) | evidence-constructor(def(N),BOOL)
       | path-to-equiv
TERM ::= false | true | var(N) | def(N) | app(TERM,TERM) | pair(TERM,TERM)
       | hcomp(i0,empty,TERM)
       | hcomp(i1,constant-system(TERM),TERM)
       | hcomp(i1,hit-path-system(ORIENTATION),TERM)
       | transp(FAMILY,i0,TERM)
       | glue(TYPE,i0,empty,TERM) | unglue(TERM)
       | iapply(hit-path,INTERVAL) | hit-left | hit-right
BODY ::= TERM | case-evidence(BOOL,BOOL) | evidence-family(def(N),def(N))
       | approved-con | rejected-con
       | interval-hit-type(def(N),def(N),def(N))
       | hit-left-con | hit-right-con | hit-path-con
       | builtin-path-to-equiv | negation-equiv(def(N)) | bool-not
```

`def(N)` is a checked reference into the packet definition array. Ordinary function bodies may only
reference earlier definitions; declaration bodies encode the explicitly supported family,
constructor, HIT and equivalence dependencies. A definition body of type `pi(bool,bool)` is checked
with binder depth one, so only `var(0)` is legal. The top-level term is checked at binder depth zero.
Forward references, cycles, out-of-range variables, ill-typed applications, declaration-shape
mismatches, trailing input, depth over 32 and more than 32 definitions fail closed.

## Local completion boundary

All ten formal reality scenarios now emit v14, and provider evaluation, integrated reification and
MAlonzo consumption are driven by this AST and its definition closure. Legacy v1–v13 parsers remain
read-only compatibility inputs and are not produced by the formal Agda lowerer.

This is a declared, fail-closed subset rather than a claim to serialize arbitrary Agda Internal
syntax. Extending the supported language must add AST typing rules, real Agda lowering, cctt
reflection, reify/recheck, same-input oracle coverage and final-program tests together. Local PASS
does not become acceptance until a specified commit is independently reproduced in a fresh clone
and on the required host matrix.
