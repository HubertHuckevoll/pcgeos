perfect — here’s a single, copy-and-paste-able note set you (or future-you) can drop into a `TODO-groups.txt` (or similar) in the repo.

---

# SVG `<g>` refactor — working notes & plan

## What we learned (from recent fixes)

* Our path walker is now robust to **mixed separators** (spaces/commas) and **command repetition** for all segment types. We added:

  * `SvgSkipCommaWS(const char*)`
  * `SvgIsNumStart(char)`
  * `SvgReadFlag(const char **, byte *)` (for `A/a` flags)
* We hardened handlers: `M/m, L/l, H/h, V/v, Q/q, T/t, C/c, S/s, A/a`.
  Result: fixed `poi.svg` (arc parsing/flags), `cartman.svg` eyes/hat (arc repeat + rotation), and general numeric edge cases.
* **Bug in `pull.svg`** came from ignoring `<g>` inheritance: the middle path inherited default `fill:black` (SVG default) instead of the group’s `fill:none`, so it filled a polygon instead of drawing just a stroke.

## Scope for `<g>` (do it “for real”)

Implement proper **group inheritance + transforms** with small stacks. No CSS engine; only presentation attributes we already parse.

### A. Style inheritance stack (push/pop)

Keep a tiny stack (depth \~8–16). Each frame carries *presence flags* and values:

* `fill` (known? none?)
* `stroke` (known? on?)
* `stroke-width` (WWFixed, in user units)
* `stroke-linecap` (`butt|round|square`)
* `stroke-linejoin` (`miter|round|bevel`)
* (optional later: `miterlimit`, `fill-rule`, `opacity`, `stroke-opacity`, `fill-opacity`, `stroke-dasharray`, `stroke-dashoffset`)

**APIs (add to `svg.h`):**

```c
void SvgStyleGroupPush(const char *tag);  /* on <g ...>  */
void SvgStyleGroupPop(void);              /* on </g>     */
```

**Resolution rule to apply everywhere:**

1. If the element has the attribute → use it.
2. Else, if the top group frame marked it known → use that.
3. Else, fall back to **SVG defaults**:

   * `fill` defaults to **black** (present)
   * `stroke` defaults to **none** (absent)
   * `stroke-width` defaults to **1 user unit**
   * `linecap` **butt**, `linejoin` **miter** (miterlimit 4)

Update **only** these places:

* `SvgStyleHasFill(tag)` and `SvgStyleHasStroke(tag)` consult group frame when element lacks explicit values.
* `SvgStyleApplyStrokeWidth(tag)` to pull width from group when missing on element.
* (Optional now / later) `SvgStyleApplyLineEndsIfUnset(tag)` to set cap/join when missing on element.

### B. Transform stack

Nested `<g transform="...">` must multiply into the element CTM.

**APIs (add to `svg.h`):**

```c
void SvgXformGroupPush(const char *tag);  /* on <g ...>  */
void SvgXformGroupPop(void);              /* on </g>     */
```

Implementation idea:

* Keep `SvgMatrix gCTMStack[N]; int gCTMDepth;`
* On push: `parent ∘ self` → push. (Use your existing `SvgXformParseAttrUser` + a small 2×3 multiply.)
* On pop: decrement depth.
* Modify one place:

  * Either make `SvgXformBuildWorld(tag, parentCTM, outWorld)` read `parentCTM` from the group stack, **or**
  * Wrap with a helper `SvgXformBuildWorldFromGroups(tag, outWorld)` that does the fetch then calls `SvgXformBuildWorld`.

### C. Dispatcher glue

Hook tag open/close (we already see `"/g"` in logs):

```c
if (SvgParserTagIs(tag, "g")) {
    SvgStyleGroupPush(tag);
    SvgXformGroupPush(tag);
    return; /* group itself draws nothing */
}
if (SvgParserTagIs(tag, "/g")) {
    SvgXformGroupPop();
    SvgStyleGroupPop();
    return;
}
```

### D. Acceptance tests (fast to eyeball)

* `pull.svg` renders with NO black fill, rope shows (inherits `stroke="#000"`), rounded ends/join if present.
* Nested group: outer sets `transform="scale(2)"`, inner sets `transform="translate(10,5)"` + `stroke-width="2"` → element reflects both CTMs and inherited width.
* Element override wins: `<g stroke="#00F"><path stroke="#E00" .../></g>` → red stroke.
* Defaults still hold: with no group and no element attrs → paths **fill black** and **do not stroke**; lines & polylines **only stroke** at width 1 (no fill).

### E. Pitfalls to avoid (we hit these earlier)

* Don’t serialize numeric params back to strings to call other parsers; pass numbers or refill the original tokenizer state.
* Flag parsing must consume **exactly** `'0'` or `'1'` (not a generic float).
* Repeat logic should continue only if the next non-WS/comma char **can start a number** (`+ - . 0-9`).

---

## Minimal code skeletons (to paste when you start)

**Style stack frame & push/pop (place in `svgStyle.goc`):**

```c
#define SVG_STYLE_GSTACK_MAX 8
typedef enum { SVG_CAP_UNSET=0, SVG_CAP_BUTT, SVG_CAP_ROUND, SVG_CAP_SQUARE } SvgCapKind;
typedef enum { SVG_JOIN_UNSET=0, SVG_JOIN_MITER, SVG_JOIN_ROUND, SVG_JOIN_BEVEL } SvgJoinKind;

typedef struct {
    Boolean fillKnown, strokeKnown, swKnown, capKnown, joinKnown;
    Boolean fillNone, strokeOn;
    WWFixedAsDWord strokeWidth;
    SvgCapKind  cap;
    SvgJoinKind join;
} SvgGroupStyle;

static SvgGroupStyle gStyleStack[SVG_STYLE_GSTACK_MAX];
static int gStyleDepth = 0;

/* Called on <g ...> */
void SvgStyleGroupPush(const char *tag)
{
    SvgGroupStyle st;
    char buf[32];
    Boolean present;

    if (gStyleDepth > 0) st = gStyleStack[gStyleDepth-1];
    else {
        st.fillKnown=st.strokeKnown=st.swKnown=st.capKnown=st.joinKnown=FALSE;
        st.fillNone=FALSE; st.strokeOn=FALSE;
        st.strokeWidth = SvgGeomMakeWWFixedFromInt(1);
        st.cap=SVG_CAP_UNSET; st.join=SVG_JOIN_UNSET;
    }

    present = SvgParserGetAttrBounded(tag, "fill", buf, sizeof(buf));
    if (present) { st.fillKnown=TRUE; st.fillNone = SvgUtilAsciiNoCaseEq(buf, "none"); }

    present = SvgParserGetAttrBounded(tag, "stroke", buf, sizeof(buf));
    if (present) { st.strokeKnown=TRUE; st.strokeOn = !SvgUtilAsciiNoCaseEq(buf, "none"); }

    if (SvgParserGetAttrBounded(tag, "stroke-width", buf, sizeof(buf))) {
        const char *s=buf; WWFixedAsDWord w;
        s = SvgParserParseWWFixed16_16(s, &w);
        st.swKnown=TRUE; st.strokeWidth=w;
    }

    if (SvgParserGetAttrBounded(tag, "stroke-linecap", buf, sizeof(buf))) {
        st.capKnown=TRUE;
        st.cap = SvgUtilAsciiNoCaseEq(buf,"round")?SVG_CAP_ROUND:
                 SvgUtilAsciiNoCaseEq(buf,"square")?SVG_CAP_SQUARE:SVG_CAP_BUTT;
    }

    if (SvgParserGetAttrBounded(tag, "stroke-linejoin", buf, sizeof(buf))) {
        st.joinKnown=TRUE;
        st.join = SvgUtilAsciiNoCaseEq(buf,"round")?SVG_JOIN_ROUND:
                  SvgUtilAsciiNoCaseEq(buf,"bevel")?SVG_JOIN_BEVEL:SVG_JOIN_MITER;
    }

    if (gStyleDepth < SVG_STYLE_GSTACK_MAX) gStyleStack[gStyleDepth++] = st;
}

/* Called on </g> */
void SvgStyleGroupPop(void)
{
    if (gStyleDepth > 0) gStyleDepth--;
}
```

**Style queries use the stack when element lacks an explicit value (edit existing):**

```c
Boolean SvgStyleHasFill(const char *tag)
{
    char b[32];
    if (SvgParserGetAttrBounded(tag,"fill",b,sizeof(b)))
        return !SvgUtilAsciiNoCaseEq(b,"none");
    if (gStyleDepth>0 && gStyleStack[gStyleDepth-1].fillKnown)
        return !gStyleStack[gStyleDepth-1].fillNone;
    return TRUE; /* SVG default */
}

Boolean SvgStyleHasStroke(const char *tag)
{
    char b[32];
    if (SvgParserGetAttrBounded(tag,"stroke",b,sizeof(b)))
        return !SvgUtilAsciiNoCaseEq(b,"none");
    if (gStyleDepth>0 && gStyleStack[gStyleDepth-1].strokeKnown)
        return gStyleStack[gStyleDepth-1].strokeOn;
    return FALSE; /* SVG default */
}

/* width default/override */
void SvgStyleApplyStrokeWidth(const char *tag)
{
    WWFixedAsDWord w;
    char b[32];
    if (SvgParserGetAttrBounded(tag,"stroke-width",b,sizeof(b))) {
        const char *s=b; s = SvgParserParseWWFixed16_16(s,&w);
    } else if (gStyleDepth>0 && gStyleStack[gStyleDepth-1].swKnown) {
        w = gStyleStack[gStyleDepth-1].strokeWidth;
    } else {
        w = SvgGeomMakeWWFixedFromInt(1);
    }
    /* call your existing line-width setter with w */
}
```

**Transform stack (in `svgTransform.goc`):**

```c
#define SVG_XFORM_GSTACK_MAX 16
static SvgMatrix gCTMStack[SVG_XFORM_GSTACK_MAX];
static int gCTMDepth=0;

static void SvgXformIdentity(SvgMatrix *m)
{ m->a=WWFIXED_ONE; m->b=0; m->c=0; m->d=WWFIXED_ONE; m->e=0; m->f=0; }

/* 2x3 multiply: R = A ∘ B */
static void SvgXformMul(const SvgMatrix *A,const SvgMatrix *B,SvgMatrix *R)
{
    WWFixedAsDWord a = GrAddWWFixed(GrMulWWFixed(A->a,B->a), GrMulWWFixed(A->c,B->b));
    WWFixedAsDWord b = GrAddWWFixed(GrMulWWFixed(A->b,B->a), GrMulWWFixed(A->d,B->b));
    WWFixedAsDWord c = GrAddWWFixed(GrMulWWFixed(A->a,B->c), GrMulWWFixed(A->c,B->d));
    WWFixedAsDWord d = GrAddWWFixed(GrMulWWFixed(A->b,B->c), GrMulWWFixed(A->d,B->d));
    WWFixedAsDWord e = GrAddWWFixed(GrAddWWFixed(GrMulWWFixed(A->a,B->e), GrMulWWFixed(A->c,B->f)), A->e);
    WWFixedAsDWord f = GrAddWWFixed(GrAddWWFixed(GrMulWWFixed(A->b,B->e), GrMulWWFixed(A->d,B->f)), A->f);
    R->a=a; R->b=b; R->c=c; R->d=d; R->e=e; R->f=f;
}

void SvgXformGroupPush(const char *tag)
{
    SvgMatrix parent, self, out;
    if (gCTMDepth>0) parent = gCTMStack[gCTMDepth-1]; else SvgXformIdentity(&parent);
    SvgXformIdentity(&self);
    SvgXformParseAttrUser(tag, &self); /* leaves identity if absent */
    SvgXformMul(&parent, &self, &out);
    if (gCTMDepth<SVG_XFORM_GSTACK_MAX) gCTMStack[gCTMDepth++] = out;
}

void SvgXformGroupPop(void)
{
    if (gCTMDepth>0) gCTMDepth--;
}
```

**Dispatcher hook (where you handle tags):**

```c
if (SvgParserTagIs(tag, "g"))  { SvgStyleGroupPush(tag); SvgXformGroupPush(tag); return; }
if (SvgParserTagIs(tag, "/g")) { SvgXformGroupPop();     SvgStyleGroupPop();     return; }
```

> When applying transforms for elements, fetch the current group CTM as the “parent” for your existing `SvgXformBuildWorld` or fold it inside `SvgXformBuildElemOnWorld`.

---

## Pointers to the code in this branch (for context)

* Meta GString bridge: `Library/Breadbox/Meta/meta/meta.goc`. ([GitHub][1])
* SVG core & dispatcher: `Library/Breadbox/Meta/SVG/svg.goc`. ([GitHub][2])
* Public header (types, prototypes): `Library/Breadbox/Meta/SVG/svg.h`. ([GitHub][3])
* Geometry helpers (WWFixed math): `svgGeom.goc`. ([GitHub][4])
* Path handling: `svgPath.goc`. ([GitHub][5])
* Shapes (line/poly/rect/ellipse…): `svgShape.goc`. ([GitHub][6])
* Style layer: `svgStyle.goc`. ([GitHub][7])
* Transform layer: `svgTransform.goc`. ([GitHub][8])
* Utils: `svgUtil.goc`. ([GitHub][9])
* ViewBox/viewport mapping: `svgView.goc`. ([GitHub][10])
* Logging macros: `dbglog.h`. ([GitHub][11])

(Those are the exact files we’ll touch for groups: **svg.goc** (dispatcher), **svgStyle.goc** (style stack), **svgTransform.goc** (CTM stack), and possibly tiny edits in **svg.h** for prototypes.)

---

## “When you start” checklist (fast)

1. Add prototypes to `svg.h`.
2. Add style stack to `svgStyle.goc`; update `HasFill/HasStroke/ApplyStrokeWidth`; (optional) add `ApplyLineEndsIfUnset`.
3. Add CTM stack + multiply in `svgTransform.goc`; ensure element CTM composes with current group CTM.
4. Hook `<g>` / `</g>` in `svg.goc` dispatcher.
5. Test: `pull.svg`, nested transform, element overrides, defaults.
6. Commit as `feat(svg): add group style+transform stacks; hook dispatcher`.

That’s the whole plan—bite-sized and safe to land.

[1]: https://raw.githubusercontent.com/HubertHuckevoll/pcgeos/refs/heads/SVG-Refactor-1/Library/Breadbox/Meta/meta/meta.goc "raw.githubusercontent.com"
[2]: https://raw.githubusercontent.com/HubertHuckevoll/pcgeos/refs/heads/SVG-Refactor-1/Library/Breadbox/Meta/SVG/svg.goc" "raw.githubusercontent.com"
[3]: https://raw.githubusercontent.com/HubertHuckevoll/pcgeos/refs/heads/SVG-Refactor-1/Library/Breadbox/Meta/SVG/svg.h "raw.githubusercontent.com"
[4]: https://raw.githubusercontent.com/HubertHuckevoll/pcgeos/refs/heads/SVG-Refactor-1/Library/Breadbox/Meta/SVG/svgGeom.goc "raw.githubusercontent.com"
[5]: https://raw.githubusercontent.com/HubertHuckevoll/pcgeos/refs/heads/SVG-Refactor-1/Library/Breadbox/Meta/SVG/svgPath.goc "raw.githubusercontent.com"
[6]: https://raw.githubusercontent.com/HubertHuckevoll/pcgeos/refs/heads/SVG-Refactor-1/Library/Breadbox/Meta/SVG/svgShape.goc "raw.githubusercontent.com"
[7]: https://raw.githubusercontent.com/HubertHuckevoll/pcgeos/refs/heads/SVG-Refactor-1/Library/Breadbox/Meta/SVG/svgStyle.goc "raw.githubusercontent.com"
[8]: https://raw.githubusercontent.com/HubertHuckevoll/pcgeos/refs/heads/SVG-Refactor-1/Library/Breadbox/Meta/SVG/svgTransform.goc "raw.githubusercontent.com"
[9]: https://raw.githubusercontent.com/HubertHuckevoll/pcgeos/refs/heads/SVG-Refactor-1/Library/Breadbox/Meta/SVG/svgUtil.goc "raw.githubusercontent.com"
[10]: https://raw.githubusercontent.com/HubertHuckevoll/pcgeos/refs/heads/SVG-Refactor-1/Library/Breadbox/Meta/SVG/svgView.goc "raw.githubusercontent.com"
[11]: https://raw.githubusercontent.com/HubertHuckevoll/pcgeos/refs/heads/SVG-Refactor-1/Library/Breadbox/Meta/SVG/dbglog.h "raw.githubusercontent.com"
