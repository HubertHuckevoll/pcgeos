/* identifiers for list of formats which can be imported */
#define FORMAT_HPGL 0
#define FORMAT_CGM  1
#define FORMAT_SVG  2

/*
 * Data block passed between TransGet???portOptions and Trans???port
 */
struct ie_uidata {
  word booleanOptions;
};
