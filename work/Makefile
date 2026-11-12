PYTHON ?= python3
.PHONY: all proof extract native test benchmark docs verify
all:
	$(PYTHON) specs/build.py
proof extract native test benchmark docs:
	$(PYTHON) specs/build.py $@
verify:
	$(PYTHON) specs/verify.py
