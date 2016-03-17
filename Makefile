# $Id: Makefile,v 1.3 2007/10/29 22:50:16 carregal Exp $

# Default prefix
PREFIX = /usr/local

# System's lua directory (where Lua libraries are installed)
LUA_DIR= $(PREFIX)/share/lua/5.1

PKGPATH=-e "package.path='src/?.lua;'..package.path"

# Lua interpreter
LUA=lua

install:
	mkdir -p $(LUA_DIR)/copas
	cp src/copas.lua $(LUA_DIR)/copas.lua
	cp src/copas/ftp.lua $(LUA_DIR)/copas/ftp.lua
	cp src/copas/smtp.lua $(LUA_DIR)/copas/smtp.lua
	cp src/copas/http.lua $(LUA_DIR)/copas/http.lua
	cp src/copas/limit.lua $(LUA_DIR)/copas/limit.lua

test:
	$(LUA) $(PKGPATH) tests/largetransfer.lua
	$(LUA) $(PKGPATH) tests/request.lua 'http://www.google.com'
	$(LUA) $(PKGPATH) tests/request.lua 'https://www.google.nl'
	$(LUA) $(PKGPATH) tests/httpredirect.lua
	$(LUA) $(PKGPATH) tests/limit.lua
	$(LUA) $(PKGPATH) tests/connecttwice.lua
	$(LUA) $(PKGPATH) tests/exit.lua
	$(LUA) $(PKGPATH) tests/exittest.lua

coverage:
	$(RM) luacov.stats.out
	$(MAKE) test LUA="$(LUA) -lluacov"
	luacov src/copas

clean:
	$(RM) luacov.stats.out luacov.report.out
