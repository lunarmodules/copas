# Copas 2.0

[![Build Status](https://travis-ci.org/keplerproject/copas.png?branch=master)](https://travis-ci.org/keplerproject/copas)
[![Coverage Status](https://coveralls.io/repos/github/keplerproject/copas/badge.svg?branch=master)](https://coveralls.io/github/keplerproject/copas?branch=master)

Copas is a dispatcher based on coroutines that can be used for asynchronous networking. For example TCP or UDP based servers. But it also features timers and client support for http(s), ftp and smtp requests.

It uses [LuaSocket](https://github.com/diegonehab/luasocket) as the interface with the TCP/IP stack and [LuaSec](https://github.com/brunoos/luasec) for ssl support.

A server or thread registered with Copas should provide a handler for requests and use Copas socket functions to send the response. Copas loops through requests and invokes the corresponding handlers. For a full implementation of a Copas HTTP server you can refer to [Xavante](http://keplerproject.github.io/xavante/) as an example.

Copas is free software and uses the same license as Lua 5.1 to 5.3 (MIT), and can be downloaded from [its GitHub page](https://github.com/keplerproject/copas).

The easiest way to install Copas is through [LuaRocks](https://luarocks.org/):

```
luarocks install copas
```

For more details see [the documentation](http://keplerproject.github.io/copas/).
