# $Id: Makefile,v 1.3 2007/10/29 22:50:16 carregal Exp $

DESTDIR ?=

# Default prefix
PREFIX  ?= /usr/local

# System's lua directory (where Lua libraries are installed)
LUA_DIR ?= $(PREFIX)/share/lua/5.1

DELIM=-e "print(([[=]]):rep(70))"
PKGPATH=-e "package.path='src/?.lua;'..package.path"

# Lua interpreter
LUA=lua

.PHONY: certs

install:
	mkdir -p $(DESTDIR)$(LUA_DIR)/copas
	cp src/copas.lua $(DESTDIR)$(LUA_DIR)/copas.lua
	cp src/copas/ftp.lua $(DESTDIR)$(LUA_DIR)/copas/ftp.lua
	cp src/copas/smtp.lua $(DESTDIR)$(LUA_DIR)/copas/smtp.lua
	cp src/copas/http.lua $(DESTDIR)$(LUA_DIR)/copas/http.lua
	cp src/copas/limit.lua $(DESTDIR)$(LUA_DIR)/copas/limit.lua
	cp src/copas/timer.lua $(DESTDIR)$(LUA_DIR)/copas/timer.lua
	cp src/copas/lock.lua $(DESTDIR)$(LUA_DIR)/copas/lock.lua
	cp src/copas/semaphore.lua $(DESTDIR)$(LUA_DIR)/copas/semaphore.lua
	cp src/copas/queue.lua $(DESTDIR)$(LUA_DIR)/copas/queue.lua

tests/certs/clientA.pem:
	cd ./tests/certs && \
	./rootA.sh       && \
	./rootB.sh       && \
	./serverA.sh     && \
	./serverB.sh     && \
	./clientA.sh     && \
	./clientB.sh     && \
	cd ../..

certs: tests/certs/clientA.pem

test: certs
	$(LUA) $(DELIM) $(PKGPATH) tests/close.lua
	$(LUA) $(DELIM) $(PKGPATH) tests/connecttwice.lua
	$(LUA) $(DELIM) $(PKGPATH) tests/errhandlers.lua
	$(LUA) $(DELIM) $(PKGPATH) tests/exit.lua
	$(LUA) $(DELIM) $(PKGPATH) tests/exittest.lua
	#$(LUA) $(DELIM) $(PKGPATH) tests/httpredirect.lua
	$(LUA) $(DELIM) $(PKGPATH) tests/largetransfer.lua
	$(LUA) $(DELIM) $(PKGPATH) tests/limit.lua
	$(LUA) $(DELIM) $(PKGPATH) tests/lock.lua
	$(LUA) $(DELIM) $(PKGPATH) tests/loop_starter.lua
	$(LUA) $(DELIM) $(PKGPATH) tests/queue.lua
	$(LUA) $(DELIM) $(PKGPATH) tests/removeserver.lua
	$(LUA) $(DELIM) $(PKGPATH) tests/removethread.lua
	$(LUA) $(DELIM) $(PKGPATH) tests/request.lua 'http://www.google.com'
	$(LUA) $(DELIM) $(PKGPATH) tests/request.lua 'https://www.google.nl'
	$(LUA) $(DELIM) $(PKGPATH) tests/semaphore.lua
	$(LUA) $(DELIM) $(PKGPATH) tests/sleep.lua
	$(LUA) $(DELIM) $(PKGPATH) tests/tcptimeout.lua
	$(LUA) $(DELIM) $(PKGPATH) tests/timer.lua
	$(LUA) $(DELIM) $(PKGPATH) tests/tls-sni.lua
	$(LUA) $(DELIM) $(PKGPATH) tests/udptimeout.lua
	$(LUA) $(DELIM)

coverage:
	$(RM) luacov.stats.out
	$(MAKE) test LUA="$(LUA) -lluacov"
	luacov

clean:
	$(RM) luacov.stats.out luacov.report.out
	$(RM) tests/certs/*.pem tests/certs/*.srl
