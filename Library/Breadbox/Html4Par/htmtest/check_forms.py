#!/usr/bin/env python3
"""Exercise the ported form logic with host stubs; does not launch GEOS."""

from pathlib import Path
import re
import subprocess
import tempfile


root = Path(__file__).resolve().parents[1]
tags = (root / "htmlpars/parstags.goc").read_text()
opening = (root / "htmlpars/opentags.goc").read_text()
form = (root / "htmlclas/htmlform.goc").read_text()
header = (root.parents[2] / "CInclude/html4par.goh").read_text()


def block(source, marker):
    start = source.index(marker)
    brace = source.index("{", start)
    depth = 1
    end = brace + 1
    while depth:
        depth += (source[end] == "{") - (source[end] == "}")
        end += 1
    return source[start:end]


flags = "\n".join(re.findall(
    r"#define HTML_(?:SUBMIT_PRESSED|BUTTON_CONTENT)\s+0x[0-9a-fA-F]+", header))
button = tags.split("case SPEC_BUTTON:", 1)[1].split("case SPEC_TEXTAREA:", 1)[0]
append = form.split("@extern method HTMLTextClass, MSG_HTML_TEXT_FORM_APPEND_ELEMENT", 1)[1]
submit = append.split("case HTML_FORM_SUBMIT:", 1)[1].split("case HTML_FORM_IMAGE:", 1)[0]
harness = r'''
#include <assert.h>
#include <string.h>
#include <strings.h>
typedef unsigned short word;
typedef int Boolean;
typedef char TCHAR;
typedef struct {
    word HFD_itemType, HFD_name, HFD_value, HFD_prompt;
    struct { struct { word flags; } submit; } HFD_var;
} HTMLformData;
typedef struct { word spec; } TagOpenArguments;
enum { SPEC_FORM, SPEC_INPUT, SPEC_SELECT, SPEC_OPTION, SPEC_TEXTAREA };
enum { HTML_FORM_SUBMIT, HTML_FORM_RESET, HTML_FORM_BUTTON };
#define _pascal
#define FALSE 0
#define TRUE 1
#define NAME_POOL_NONE 0
#define CA_NULL_ELEMENT 65535
#define HTML_JAVASCRIPT 1
#define HTML_EVENT_OBJECT_ELEMENT 1
#define STRCMPISB strcasecmp
#define _TEXT(s) s
static struct { word HE_options; } ext, *HTMLext = &ext;
static word NamePool, storedContent, currentMenu, formDepth;
static unsigned added, released, events, closed;
static const char *typeP, *nameP, *valueP;
static char tokens[16][80], caption[80];
static word nextToken = 1;
static HTMLformData record;
static word EnclosingCount(word spec, word *topP)
{
    (void)topP;
    assert(spec == SPEC_FORM);
    return formDepth;
}
static char *GetParamValue(word params, const char *keyP)
{
    (void)params;
    if (!strcmp(keyP, "TYPE")) return (char *)typeP;
    if (!strcmp(keyP, "NAME")) return (char *)nameP;
    assert(!strcmp(keyP, "VALUE"));
    return (char *)valueP;
}
static word NamePoolTokenizeDOS(word pool, const char *textP, int flag)
{
    (void)pool; (void)flag;
    assert(nextToken < 16 && strlen(textP) < sizeof(tokens[0]));
    strcpy(tokens[nextToken], textP);
    return nextToken++;
}
static void NamePoolReleaseToken(word pool, word token)
{
    (void)pool;
    assert(token != NAME_POOL_NONE);
    released++;
}
static word AddFormElement(HTMLformData *fdP)
{
    record = *fdP;
    added++;
    return 7;
}
static void ParseEvents(word params, word object, word element)
{
    (void)params;
    assert(object == HTML_EVENT_OBJECT_ELEMENT && element == 7);
    events++;
}
static void ForceCloseStyle(word spec, word limit)
{
    (void)limit;
    assert(spec == SPEC_OPTION && currentMenu != CA_NULL_ELEMENT);
    closed++;
}
#define SPEC_DONT_MATCH 99
static void NamePoolCopy(word pool, char *bufP, unsigned size,
                         word token, char **resultPP)
{
    (void)pool;
    assert(token && strlen(tokens[token]) < size);
    strcpy(bufP, tokens[token]);
    if (resultPP) *resultPP = bufP;
}
static void NamePoolInitializeDynamic(char *bufP, unsigned size,
                                      const char *textP, char **resultPP)
{
    assert(strlen(textP) < size);
    strcpy(bufP, textP);
    *resultPP = bufP;
}
static void FormElementTextDrawButton(int state, int size, char *bufP)
{
    (void)state; (void)size;
    strcpy(caption, bufP);
}
static int FormElementGetSizeOfButton(char *bufP)
{
    return (int)strlen(bufP);
}
''' + flags + "\n" + block(tags, "Boolean _pascal KeepFormControl(void)")
harness += "\nstatic void closeButton(void) { word paramArray = 0; switch (0) { case 0:"
harness += button + "} }\n"
harness += "static void filterInput(word spec) { TagOpenArguments argValue, *arg = &argValue; arg->spec = spec;"
harness += block(opening, "if((arg->spec == SPEC_INPUT") + "added++; }\n"
for name, spec in (("discardTextarea", "SPEC_TEXTAREA"), ("discardOption", "SPEC_OPTION")):
    source = tags.split("case " + spec + ":", 1)[1]
    marker = "if(!KeepFormControl())" if spec == "SPEC_TEXTAREA" else "if(currentMenu==CA_NULL_ELEMENT)"
    harness += "static void " + name + "(void) { switch (0) { case 0:"
    harness += block(source, marker) + "} }\n"
harness += "static void closeSelect(void) { switch (0) { case 0:"
harness += tags.split("case SPEC_SELECT:", 1)[1].split("case SPEC_TABLE:", 1)[0] + "} }\n"
for name, file in (("drawCaption", "htmlfdrw.goc"), ("sizeCaption", "htmlfsiz.goc")):
    source = (root / "htmlclas" / file).read_text()
    harness += "static int " + name + "(void) { HTMLformData *p_formData = &record; char buf[80]; int size = 0;"
    if name == "drawCaption":
        harness += "int gstate = 0;"
    harness += "switch (0) { case 0:" + block(source, "if (p_formData->HFD_var.submit.flags & HTML_BUTTON_CONTENT)")
    harness += "} return size; }\n"
harness += r'''
static void checkSubmit(const char *expectedP, int pressed)
{
    HTMLformData *p_formData = &record;
    char buf[80], *bufP = (void *)0, nextPrefix = 0;
    int addName = FALSE, addBuf = FALSE;
    if (pressed) record.HFD_var.submit.flags |= HTML_SUBMIT_PRESSED;
    switch (0) { case 0:
''' + submit + r'''
    }
    assert(addName == pressed && addBuf == pressed);
    if (pressed) {
        assert(nextPrefix == '&' && !strcmp(bufP, expectedP));
        assert(!strcmp(tokens[record.HFD_name], "go"));
    }
}
int main(void)
{
    word js, inside, spec, content;
    unsigned i;
    const char *types[] = { (void *)0, "made-up", "submit", "ReSeT", "BuTtOn" };
    for (js = 0; js < 2; js++) for (inside = 0; inside < 2; inside++) {
        HTMLext->HE_options = js ? HTML_JAVASCRIPT : 0;
        formDepth = inside;
        assert(!!KeepFormControl() == (js || inside));
        for (spec = SPEC_FORM; spec <= SPEC_SELECT; spec++) {
            added = 0;
            currentMenu = 3;
            filterInput(spec);
            assert(added == (unsigned)(spec == SPEC_FORM || js || inside));
            assert((currentMenu == CA_NULL_ELEMENT) ==
                   (spec == SPEC_SELECT && !js && !inside));
        }
        added = released = events = 0;
        content = storedContent = NamePoolTokenizeDOS(0, "Continue & go", 0);
        typeP = (void *)0; nameP = "go"; valueP = "next";
        closeButton();
        assert(storedContent == NAME_POOL_NONE);
        assert(added == (unsigned)(js || inside) && events == added);
        assert(released == (unsigned)(!js && !inside));
        if (added) {
            assert(record.HFD_prompt == content);
            assert(!strcmp(tokens[record.HFD_value], "next"));
            drawCaption();
            assert(!strcmp(caption, "Continue & go"));
            assert(sizeCaption() == 13);
            checkSubmit("next", 0);
            checkSubmit("next", 1);
        }
        nextToken = 1;
    }
    formDepth = 1;
    for (i = 0; i < sizeof(types) / sizeof(types[0]); i++) {
        typeP = types[i]; valueP = (i & 1) ? "" : (void *)0;
        storedContent = NAME_POOL_NONE;
        closeButton();
        assert(record.HFD_itemType == (i == 3 ? HTML_FORM_RESET :
                                      i == 4 ? HTML_FORM_BUTTON : HTML_FORM_SUBMIT));
        drawCaption(); assert(!*caption && sizeCaption() == 0);
        if (record.HFD_itemType == HTML_FORM_SUBMIT) checkSubmit("", 1);
    }
    HTMLext->HE_options = formDepth = released = 0;
    storedContent = 1; discardTextarea();
    assert(released == 1 && storedContent == NAME_POOL_NONE);
    discardTextarea(); assert(released == 1);
    currentMenu = CA_NULL_ELEMENT;
    storedContent = 1; discardOption();
    assert(released == 2 && storedContent == NAME_POOL_NONE);
    discardOption(); assert(released == 2);
    currentMenu = 3; closeSelect();
    assert(closed == 1 && currentMenu == CA_NULL_ELEMENT);
    return 0;
}
'''

with tempfile.TemporaryDirectory() as directory:
    source = Path(directory) / "forms.c"
    binary = Path(directory) / "forms"
    source.write_text(harness)
    subprocess.run(["cc", "-std=c89", "-Wall", "-Wextra", "-Werror",
                    str(source), "-o", str(binary)], check=True)
    subprocess.run([str(binary)], check=True)
print("Form filtering and button checks passed")
