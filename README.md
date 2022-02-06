# Copas 3.0

[![Unix build](https://img.shields.io/github/workflow/status/keplerproject/copas/Unix%20build?label=Unix%20build&logo=linux)](https://github.com/keplerproject/copas/actions)
[![Coveralls code coverage](https://img.shields.io/coveralls/github/keplerproject/copas?logo=coveralls)](https://coveralls.io/github/keplerproject/copas)
[![Luacheck](https://github.com/keplerproject/copas/workflows/Luacheck/badge.svg)](https://github.com/keplerproject/copas/actions)
[![SemVer](https://img.shields.io/github/v/tag/keplerproject/copas?color=brightgreen&label=SemVer&logo=semver&sort=semver)](CHANGELOG.md)


Copas is a dispatcher based on coroutines that can be used for asynchronous networking. For example TCP or UDP based servers. But it also features timers and client support for http(s), ftp and smtp requests.

It uses [LuaSocket](https://github.com/diegonehab/luasocket) as the interface with the TCP/IP stack and [LuaSec](https://github.com/brunoos/luasec) for ssl support.

A server or thread registered with Copas should provide a handler for requests and use Copas socket functions to send the response. Copas loops through requests and invokes the corresponding handlers. For a full implementation of a Copas HTTP server you can refer to [Xavante](http://keplerproject.github.io/xavante/) as an example.

Copas is free software and uses the same license as Lua (MIT), and can be downloaded from [its GitHub page](https://github.com/keplerproject/copas).

The easiest way to install Copas is through [LuaRocks](https://luarocks.org/):

```
luarocks install copas
```

For more details see [the documentation](http://keplerproject.github.io/copas/).

### Releasing a new version

 - update changelog in docs (`index.html`, update `history` and `status` sections)
 - update version in `copas.lua`
 - update version at the top of this README,
 - update copyright years if needed
 - update rockspec
 - commit as `release X.Y.Z`
 - tag as `vX_Y_Z` and as `X.Y.Z`
 - push commit and tag
 - upload to luarocks
 - test luarocks installation
