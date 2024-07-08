import grpc
import cri_pb2_grpc
import cri_pb2

def run():
    with grpc.insecure_channel('localhost:50051') as channel:
        stub = cri_pb2_grpc.CRIStub(channel)
        request = cri_pb2.VersionRequest()
        response = stub.GetVersion(request)
        print("CRI Version:", response.version)

if __name__ == '__main__':
    run()

