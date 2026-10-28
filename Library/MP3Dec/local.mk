#include <$(SYSMAKEFILE)>
# Pascal internal calls, large-model far pointers and SS different from DS.
# ATTENTION: Cross-resource table references need real segments. Keep the
# immutable tables in fixed dgroup (currently below 16 KB). Move them behind
# locked-handle interfaces before selecting -zc or movable table resources.
XCCOMFLAGS += -ecp
