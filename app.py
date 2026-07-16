from http.server import SimpleHTTPRequestHandler, HTTPServer
import os

PORT = 8000
from kgetnodes import get_k8s_node_list

class MyHandler(SimpleHTTPRequestHandler):
    def do_GET(self):
        self.send_response(200)
        self.send_header("Content-type", "text/plain")
        self.end_headers()
        self.wfile.write(b"Hello! Your Python app is running inside Kubernetes, pulled from your local registry!\n")
        for node in get_k8s_node_list():
            self.wfile.write(f"{node}\n".encode())


if __name__ == "__main__":
    print(f"Starting server on port {PORT}...")
    server = HTTPServer(("0.0.0.0", PORT), MyHandler)
    server.serve_forever()
  
