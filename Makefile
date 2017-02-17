# TODO: Support this being a different directory
B = sql

include pgxntool/base.mk

testdeps: $(wildcard test/*.sql) # Be careful not to include directories in this

install: cat_tools count_nulls

.PHONY: cat_tools
cat_tools: $(DESTDIR)$(datadir)/extension/cat_tools.control

$(DESTDIR)$(datadir)/extension/cat_tools.control:
	pgxn install --unstable cat_tools

.PHONY: count_nulls
count_nulls: $(DESTDIR)$(datadir)/extension/count_nulls.control

$(DESTDIR)$(datadir)/extension/count_nulls.control:
	pgxn install --unstable count_nulls


$B:
	@mkdir -p $@

installcheck: $B/object_reference.sql
EXTRA_CLEAN += $B/object_reference.sql
$B/object_reference.sql: sql/object_reference.in.sql pgxntool/safesed
	(echo @generated@ && cat $< && echo @generated@) | sed -e 's#@generated@#-- GENERATED FILE! DO NOT EDIT! See $<#' > $@
	pgxntool/safesed $@ -E -e 's/^-- SED: EXTENSION ONLY//'
