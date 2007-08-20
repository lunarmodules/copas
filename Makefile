# $Id: Makefile,v 1.2 2007/08/20 22:27:03 carregal Exp $

LUA_DIR= /usr/share/lua/5.1

install:
	mkdir -p $(LUA_DIR)/copas
	cp src/copas/copas.lua $(LUA_DIR)/copas.lua

clean:
