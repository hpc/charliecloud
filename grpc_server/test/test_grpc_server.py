# created from cri.proto file 
import cri_pb2_grpc
import cri_pb2

import grpc 
from concurrent import futures
import subprocess 

# ImageService defines the public APIs for managing images.
class ImageServiceServicer(cri_pb2_grpc.ImageServiceServicer):
   # Lists existing images
   def ListImages(self, request, context):
      print("in List Images") # DEBUG

      # creates empty respone
      response = cri_pb2.ListImagesResponse()

      # calls ch-image list and stores stdout
      cmd = "/usr/local/src/charliecloud/bin/ch-image"
      ca = [cmd, "list"]
      output = subprocess.check_output(ca, stderr=subprocess.STDOUT)
      
      # images as strings 
      # note: decode changes bytes to string, split converts string to array, and finally remove the empty string
      images = output.decode("utf-8").split("\n")[:-1]
     
      # for every image in charliecloud cache: 
      #   create an image object with the name as the ID and append to the repeated field 
      for img in images:
         response.images.append(cri_pb2.Image(id=img)) # note: incomplete... image missing fields

      print(response.images) # DEBUG
      return response

   # ImageFSInfo returns information of the filesystem that is used to store images.
   def ImageFsInfo(self, request, context):
      print("In Image Fs Info") # DEBUG
      
      # dummy placeholders
      filesystem_info = cri_pb2.FilesystemUsage()
      response = cri_pb2.ImageFsInfoResponse(image_filesystems=[filesystem_info])
      
      return response 



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

   # dummy start container function
   def StartContainer(self, request, context):
      print("start container:", request.container_id) # DEBUG
      return cri_pb2.StartContainerResponse() 
    
 
def serve():
    server = grpc.server(futures.ThreadPoolExecutor(max_workers=10))
    cri_pb2_grpc.add_RuntimeServiceServicer_to_server(RuntimeServiceServicer(), server)
    cri_pb2_grpc.add_ImageServiceServicer_to_server(ImageServiceServicer(), server)
    server.add_insecure_port(f'unix:///tmp/test.sock')
    server.start()
    print("Server listening on port 50052...") # DEBUG
    server.wait_for_termination() 

if __name__ == '__main__':
    # start gRPC server
    serve()
