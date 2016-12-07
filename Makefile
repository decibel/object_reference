include pgxntool/base.mk

install: cat_tools count_nulls

.PHONY: cat_tools
cat_tools: $(DESTDIR)$(datadir)/extension/cat_tools.control

$(DESTDIR)$(datadir)/extension/cat_tools.control:
	pgxn install --unstable cat_tools

.PHONY: count_nulls
count_nulls: $(DESTDIR)$(datadir)/extension/count_nulls.control

$(DESTDIR)$(datadir)/extension/count_nulls.control:
	pgxn install --unstable count_nulls
