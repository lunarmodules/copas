-- when a socket is being closed, while another coroutine
-- is reading on it, the `select` call does not return an event on that
-- socket. Hence the loop keeps running until the watch-dog kicks-in, reads
-- on the socket, and that returns the final "closed" error to the reading
-- coroutine.
--
-- when a socket is closed, any read/write operation should return immediately
-- with a "closed" error.

local copas = require "copas"
local socket = require "socket"

copas.loop(function()

  local client_socket
  local close_time
  local send_end_time
  local receive_end_time

  print "------------- starting close test ---------------"

  local function check_exit()
    if receive_end_time and send_end_time then
      -- both set, so we're done
      print "success!"
      os.exit(0)
    end
  end


  do -- set up a server that accepts but doesn't read or write anything
    local server = socket.bind("localhost", 20000)

    copas.addserver(server, copas.handler(function(conn_skt)
      -- client connected, we're not doing anything, let the client
      -- wait in the read/write queues
      copas.sleep(2)
      -- now we're closing the connecting_socket
      close_time = socket.gettime()
      print("closing client socket now, client receive and send operation should immediately error out now")
      client_socket:close()

      copas.sleep(10)
      conn_skt:close()
      copas.removeserver(server)
      print "timeout, test failed"
      os.exit(1)
    end))
  end


  do -- create a client that connect to the server
    client_socket = copas.wrap(socket.connect("localhost", 20000))

    copas.addthread(function()
      local data, err = client_socket:receive(1)
      print("receive result: ", tostring(data), tostring(err))
      receive_end_time = socket.gettime()
      print("receive took: ", receive_end_time - close_time)
      check_exit()
    end)

    copas.addthread(function()
      local ok, err = true, nil
      while ok do -- loop to fill any buffers, until we get stuck
        ok, err = client_socket:send(("hello world"):rep(100))
      end
      print("send result: ", tostring(ok), tostring(err))
      send_end_time = socket.gettime()
      print("send took: ", send_end_time - close_time)
      check_exit()
    end)
  end

end)
