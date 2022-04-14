local package_name = "copas"
local package_version = "3.0.0"
local rockspec_revision = "2"
local github_account_name = "lunarmodules"
local github_repo_name = package_name


package = package_name
version = package_version.."-"..rockspec_revision
source = {
  url = "git+https://github.com/"..github_account_name.."/"..github_repo_name..".git",
  branch = (package_version == "cvs") and "master" or nil,
  tag = (package_version ~= "cvs") and package_version or nil,
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
   homepage = "https://github.com/"..github_account_name.."/"..github_repo_name,
}
dependencies = {
   "lua >= 5.1, < 5.5",
   "luasocket >= 2.1",
   "coxpcall >= 1.14",
   "binaryheap >= 0.4",
   "timerwheel >= 0.2",
}
build = {
   type = "builtin",
   modules = {
      ["copas"] = "src/copas.lua",
      ["copas.http"] = "src/copas/http.lua",
      ["copas.ftp"] = "src/copas/ftp.lua",
      ["copas.smtp"] = "src/copas/smtp.lua",
      ["copas.limit"] = "src/copas/limit.lua",
      ["copas.timer"] = "src/copas/timer.lua",
      ["copas.lock"] = "src/copas/lock.lua",
      ["copas.semaphore"] = "src/copas/semaphore.lua",
   },
   copy_directories = {
      "docs",
   },
}
