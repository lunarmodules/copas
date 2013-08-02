package = "Copas"
version = "1.2.0-1"
source = {
   url = "http://www.keplerproject.org/files/copas-1.2.0.tar.gz",
}
description = {
   summary = "Coroutine Oriented Portable Asynchronous Services",
   detailed = [[
      Copas is a dispatcher based on coroutines that can be used by
      TCP/IP servers. It uses LuaSocket as the interface with the
      TCP/IP stack. A server registered with Copas should provide a
      handler for requests and use Copas socket functions to send
      the response. Copas loops through requests and invokes the
      corresponding handlers. For a full implementation of a Copas
      HTTP server you can refer to Xavante as an example. 
   ]],
   license = "MIT/X11",
   homepage = "http://www.keplerproject.org/copas/"
}
dependencies = {
   "lua >= 5.1",
   "luasocket >= 2.1",
   "coxpcall >= 1.14",
}
build = {
   type = "builtin",
   modules = { copas = "src/copas/copas.lua" } 
}
