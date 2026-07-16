import json
from http.server import ThreadingHTTPServer, BaseHTTPRequestHandler
import sys

from kgetnodes import get_k8s_node_list
import datetime 

class MyCustomHandler(BaseHTTPRequestHandler):
    # This is the "GET method code" that gets executed when you curl!
    def do_GET(self):
        # 1. Send the HTTP response headers
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.end_headers()
        
        now=datetime.datetime.now()
        output_time=now.strftime('%Y-%d-%m %H:%M:%S')
        # 2. Define the response payload
        response_data = {
            "status": "success",
            "message": "Hello from my-app concurrent server!",
            'time' : output_time

        }
        # for node in get_k8s_node_list():
        #     self.wfile.write(f"{node}\n".encode())
        
        # self.wfile.write(f"success at: {output_time}\n".encode())

        # 3. Write the response back to the client socket
        self.wfile.write(json.dumps(response_data).encode('utf-8')+'\r\n'.encode('utf-8')) 

if __name__ == '__main__':
    port = 8000
    # ThreadingHTTPServer spins up a new thread for every incoming GET request
    server = ThreadingHTTPServer(('0.0.0.0', port), MyCustomHandler)
    print(f"Starting concurrent server on port {port}...")
    server.serve_forever()

