import grpc 
import cri_pb2_grpc
import cri_pb2
from concurrent import futures
import subprocess 
from subprocess import PIPE, Popen
# this is an implementation of CRI Servicer from the .proto file
class RuntimeServiceServicer(cri_pb2_grpc.RuntimeServiceServicer):
   # implements gret version grpc function from .proto file
   def Version(self, request, context):
      # debug 
      print("version")
      # hardcode version
      response = cri_pb2.VersionResponse(version="1.0.0")
      # this is the Charliecloud command we want
      cmd = "/usr/local/src/charliecloud/bin/ch-run"
      ca = [cmd, "--version"]
      test = subprocess.check_output(ca, stderr=subprocess.STDOUT)
      response.version = test 
      return response

def serve():
    server = grpc.server(futures.ThreadPoolExecutor(max_workers=10))
    # reference proto file
    cri_pb2_grpc.add_RuntimeServiceServicer_to_server(RuntimeServiceServicer(), server)
    server.add_insecure_port('[::]:50052')
    server.start()
    print("Server listening on port 50052...") # DEBUG
    server.wait_for_termination() # Listen

if __name__ == '__main__':
    serve()
