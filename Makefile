clean:
	rm -rf public/

run: clean
	hugo server

build: clean
	hugo -D
