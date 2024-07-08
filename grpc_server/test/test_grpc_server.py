# created from cri.proto file 
import cri_pb2_grpc
import cri_pb2

import grpc 
from concurrent import futures
import subprocess 

# organise version information to return as protobuf
VERSION_INFO = { "KubeVersion": "v1",           # version of the kubelet runtime api
                 "RuntimeName": "Charliecloud", # name of the container runtime (const)
                 "RuntimeApiVersion": "v0" }    # api version of the container runtime (I do not really know what this is)

# this is an implementation of CRI's RuntimeService:
# Runtime service defines the public APIs for remote container runtimes 
class RuntimeServiceServicer(cri_pb2_grpc.RuntimeServiceServicer):
   # Version returns the runtime name, runtime version and runtime API version.
   def Version(self, request, context):
      print("version") # DEBUG
      response = cri_pb2.VersionResponse(version=VERSION_INFO["KubeVersion"], runtime_name = VERSION_INFO["RuntimeName"], runtime_api_version=VERSION_INFO["RuntimeApiVersion"])

      # this is the Charliecloud command we run to get the ch-run version
      cmd = "/usr/local/src/charliecloud/bin/ch-run"
      ca = [cmd, "--version"]
      
      # for some reason version response is in STDERR
      output = subprocess.check_output(ca, stderr=subprocess.STDOUT) 
      response.runtime_version = output.rstrip() # note: rstrip removes new line

      return response

def serve():
    server = grpc.server(futures.ThreadPoolExecutor(max_workers=10))
    cri_pb2_grpc.add_RuntimeServiceServicer_to_server(RuntimeServiceServicer(), server)
    server.add_insecure_port(f'unix:///tmp/test.sock')
    server.start()
    print("Server listening on port 50052...") # DEBUG
    server.wait_for_termination() 

if __name__ == '__main__':
    serve()
