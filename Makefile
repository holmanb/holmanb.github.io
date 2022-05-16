deps:
	@command -v hugo &>/dev/null
	@command -v spellintian &>/dev/null
clean:
	rm -rf public/

run: check clean deps
	hugo server

build: check clean deps
	hugo -D

check: deps
	spellintian content/_index.md
	spellintian content/blog/*
