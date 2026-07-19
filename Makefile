DEPS := .tests/site/pack/deps/start

.PHONY: test deps clean lint format

deps: $(DEPS)/plenary.nvim

$(DEPS)/plenary.nvim:
	git clone --depth=1 https://github.com/nvim-lua/plenary.nvim $@

test: deps
	nvim --headless -u tests/minimal_init.lua \
		-c "PlenaryBustedDirectory tests { minimal_init = 'tests/minimal_init.lua', sequential = true }"

lint:
	luacheck lua plugin tests

format:
	stylua lua plugin tests

clean:
	rm -rf .tests
