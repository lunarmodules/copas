# $Id: Makefile,v 1.1 2006/12/04 16:28:29 mascarenhas Exp $

LUA_DIR= /usr/local/share/lua/5.1

install:
	mkdir -p $(LUA_DIR)/copas
	cp src/copas/copas.lua $(LUA_DIR)/copas
	ln -s $(LUA_DIR)/copas/copas.lua $(LUA_DIR)/copas.lua

clean:
