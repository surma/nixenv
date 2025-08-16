import http from "node:http";

const server = http.createServer((req, res) => {
  try {
    res.end(JSON.stringify({
      headers: req.headers,
      url: req.url,
    }, null, 2));
  } catch(e) {
    res.statusCode = 500;
    res.end();
  }
});
server.on('clientError', (err, socket) => {
  socket.end('HTTP/1.1 400 Bad Request\r\n\r\n');
});
server.listen(process.env.PORT ?? 8000);
